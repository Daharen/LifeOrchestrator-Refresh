<#
    Show-VerificationConsole.ps1 - the Verification Console (Widget 03) UI entrypoint.

    A native WinForms window (run STA) that loads a VERIFICATION PACKET Claude wrote, lets a human RUN each
    'run_module' item locally through the Module 1 generic wrapper, SEE inputs / outputs / artifacts, work
    through each item's CHECKLIST + overall verdict + notes, and EXPORT a VERIFICATION RESULT JSON Claude
    reads back. 'human_action' items carry a handed subtask (nothing to run - do it, then record the verdict).

    It is a THIN shell over VerificationConsole.psm1: the UI only builds controls, loads the packet, starts a
    run off the UI thread and polls it from a Timer (so every control update stays on the UI thread), and
    renders via the core's Format-* functions. It reimplements nothing.

    Launch:   launch.bat   (pwsh -NoProfile -STA -File Show-VerificationConsole.ps1)
    Self-test: pwsh -STA -File Show-VerificationConsole.ps1 -SelfTest   (builds+disposes the form, prints SELFTEST_FORM_OK)
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$PacketPath,
    [string]$InvokeSkillPath,
    [string]$PwshPath
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'VerificationConsole.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:VState = @{
    form            = $null
    packet          = $null
    items           = @()
    itemState       = @{}       # id -> @{ checks=@(); overall='skipped'; notes=''; ran=$false; run=$null; runText='' }
    currentId       = $null
    handle          = $null
    startedUtc      = $null
    invokeSkillPath = $InvokeSkillPath
    pwshPath        = $PwshPath
    paths           = $null
    suspendItemEvents = $false   # true while a programmatic list/control rebuild runs, so it cannot drive a spurious save (D-0064)
}

function Set-VText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Set-SplitterDistanceSafe {
    param($Split, [int]$Distance)
    try { $Split.SplitterDistance = $Distance } catch { }
}

function New-VerificationForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Verification Console - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1180, 840)
    $form.MinimumSize = [System.Drawing.Size]::new(920, 640)
    $form.StartPosition = 'CenterScreen'

    # ===== status strip =====
    $status = [System.Windows.Forms.StatusStrip]::new()
    $stateLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $stateLabel.Text = 'State: Idle'
    $sep1 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep1.Text = '   |   '
    $elapsedLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $elapsedLabel.Text = 'Elapsed: 0s'
    $sep2 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep2.Text = '   |   '
    $countLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $countLabel.Text = 'Items: -'
    [void]$status.Items.AddRange(@($stateLabel, $sep1, $elapsedLabel, $sep2, $countLabel))

    # ===== toolbar (top) =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'
    $toolbar.Height = 40
    $openBtn = [System.Windows.Forms.Button]::new()
    $openBtn.Text = 'Open packet...'
    $openBtn.Location = [System.Drawing.Point]::new(8, 7)
    $openBtn.Size = [System.Drawing.Size]::new(108, 26)
    # D-0063: kill the GUID hunt -- open the newest packet directly, or pick from a recent list.
    $openLatestBtn = [System.Windows.Forms.Button]::new()
    $openLatestBtn.Text = 'Open latest'
    $openLatestBtn.Location = [System.Drawing.Point]::new(120, 7)
    $openLatestBtn.Size = [System.Drawing.Size]::new(96, 26)
    $recentBtn = [System.Windows.Forms.Button]::new()
    $recentBtn.Text = 'Recent packets...'
    $recentBtn.Location = [System.Drawing.Point]::new(220, 7)
    $recentBtn.Size = [System.Drawing.Size]::new(126, 26)
    $exportBtn = [System.Windows.Forms.Button]::new()
    $exportBtn.Text = 'Export result...'
    $exportBtn.Location = [System.Drawing.Point]::new(352, 7)
    $exportBtn.Size = [System.Drawing.Size]::new(120, 26)
    $exportBtn.Enabled = $false
    $packetLabel = [System.Windows.Forms.Label]::new()
    $packetLabel.Text = 'No packet loaded. Open latest, pick a recent packet, or browse for one Claude wrote.'
    $packetLabel.Location = [System.Drawing.Point]::new(484, 12)
    $packetLabel.AutoSize = $true
    $packetLabel.ForeColor = [System.Drawing.Color]::DimGray
    $toolbar.Controls.AddRange(@($openBtn, $openLatestBtn, $recentBtn, $exportBtn, $packetLabel))

    # ===== outer split: left (items) | right (run + verdict) =====
    $outer = [System.Windows.Forms.SplitContainer]::new()
    $outer.Dock = 'Fill'
    $outer.Orientation = 'Vertical'
    Set-SplitterDistanceSafe $outer 400

    # ----- left: item list over item detail -----
    $leftSplit = [System.Windows.Forms.SplitContainer]::new()
    $leftSplit.Dock = 'Fill'
    $leftSplit.Orientation = 'Horizontal'
    Set-SplitterDistanceSafe $leftSplit 300

    $itemList = [System.Windows.Forms.ListBox]::new()
    $itemList.Dock = 'Fill'
    $itemList.Font = $mono
    $itemList.IntegralHeight = $false
    $leftSplit.Panel1.Controls.Add($itemList)

    $lblDetail = [System.Windows.Forms.Label]::new()
    $lblDetail.Text = 'Item detail (what to check)'
    $lblDetail.Dock = 'Top'
    $lblDetail.Height = 18
    $detailBox = [System.Windows.Forms.RichTextBox]::new()
    $detailBox.Dock = 'Fill'
    $detailBox.ReadOnly = $true
    $detailBox.Font = $mono
    $detailBox.WordWrap = $true
    $detailBox.Text = 'Open a packet, then select an item on the left.'

    # ----- 'Open' affordance for an item's referenced files / folders (D-0063: surface output locations) -----
    $openPanel = [System.Windows.Forms.Panel]::new()
    $openPanel.Dock = 'Bottom'
    $openPanel.Height = 34
    $lblOpen = [System.Windows.Forms.Label]::new()
    $lblOpen.Text = 'Open:'
    $lblOpen.Location = [System.Drawing.Point]::new(4, 9)
    $lblOpen.AutoSize = $true
    $openCombo = [System.Windows.Forms.ComboBox]::new()
    $openCombo.DropDownStyle = 'DropDownList'
    $openCombo.Location = [System.Drawing.Point]::new(46, 6)
    $openCombo.Size = [System.Drawing.Size]::new(250, 24)
    $openCombo.Anchor = 'Top,Left,Right'
    $openCombo.Enabled = $false
    $openPathBtn = [System.Windows.Forms.Button]::new()
    $openPathBtn.Text = 'Open'
    $openPathBtn.Location = [System.Drawing.Point]::new(302, 5)
    $openPathBtn.Size = [System.Drawing.Size]::new(70, 24)
    $openPathBtn.Anchor = 'Top,Right'
    $openPathBtn.Enabled = $false
    $openPanel.Controls.AddRange(@($lblOpen, $openCombo, $openPathBtn))

    $leftSplit.Panel2.Controls.Add($detailBox)
    $leftSplit.Panel2.Controls.Add($lblDetail)
    $leftSplit.Panel2.Controls.Add($openPanel)

    $outer.Panel1.Controls.Add($leftSplit)

    # ----- right: run pane (top) over verdict pane (bottom) -----
    $rightSplit = [System.Windows.Forms.SplitContainer]::new()
    $rightSplit.Dock = 'Fill'
    $rightSplit.Orientation = 'Horizontal'
    Set-SplitterDistanceSafe $rightSplit 380

    # run pane
    $runBar = [System.Windows.Forms.Panel]::new()
    $runBar.Dock = 'Top'
    $runBar.Height = 40
    $runBtn = [System.Windows.Forms.Button]::new()
    $runBtn.Text = 'Run item'
    $runBtn.Location = [System.Drawing.Point]::new(6, 6)
    $runBtn.Size = [System.Drawing.Size]::new(100, 27)
    $runBtn.Enabled = $false
    $cancelBtn = [System.Windows.Forms.Button]::new()
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.Location = [System.Drawing.Point]::new(112, 6)
    $cancelBtn.Size = [System.Drawing.Size]::new(90, 27)
    $cancelBtn.Enabled = $false
    $runHint = [System.Windows.Forms.Label]::new()
    $runHint.Text = 'Runs this item''s module locally through the Module 1 wrapper.'
    $runHint.Location = [System.Drawing.Point]::new(210, 12)
    $runHint.AutoSize = $true
    $runHint.ForeColor = [System.Drawing.Color]::DimGray
    $runBar.Controls.AddRange(@($runBtn, $cancelBtn, $runHint))

    $lblResult = [System.Windows.Forms.Label]::new()
    $lblResult.Text = 'Run output (inputs / status / result / artifacts)'
    $lblResult.Dock = 'Top'
    $lblResult.Height = 18
    $resultBox = [System.Windows.Forms.RichTextBox]::new()
    $resultBox.Dock = 'Fill'
    $resultBox.ReadOnly = $true
    $resultBox.Font = $mono
    $resultBox.WordWrap = $true
    $resultBox.Text = 'Select a run_module item and press Run item, or complete a human_action by hand.'
    $rightSplit.Panel1.Controls.Add($resultBox)
    $rightSplit.Panel1.Controls.Add($lblResult)
    $rightSplit.Panel1.Controls.Add($runBar)

    # verdict pane
    $verdictBottom = [System.Windows.Forms.Panel]::new()
    $verdictBottom.Dock = 'Bottom'
    $verdictBottom.Height = 132
    $lblOverall = [System.Windows.Forms.Label]::new()
    $lblOverall.Text = 'Overall verdict:'
    $lblOverall.Location = [System.Drawing.Point]::new(6, 8)
    $lblOverall.AutoSize = $true
    $overallCombo = [System.Windows.Forms.ComboBox]::new()
    $overallCombo.DropDownStyle = 'DropDownList'
    $overallCombo.Location = [System.Drawing.Point]::new(110, 5)
    $overallCombo.Size = [System.Drawing.Size]::new(140, 24)
    [void]$overallCombo.Items.AddRange(@('skipped', 'pass', 'fail', 'partial'))
    $overallCombo.SelectedIndex = 0
    $saveItemBtn = [System.Windows.Forms.Button]::new()
    $saveItemBtn.Text = 'Save item verdict'
    $saveItemBtn.Location = [System.Drawing.Point]::new(262, 4)
    $saveItemBtn.Size = [System.Drawing.Size]::new(140, 26)
    $lblNotes = [System.Windows.Forms.Label]::new()
    $lblNotes.Text = 'Notes:'
    $lblNotes.Location = [System.Drawing.Point]::new(6, 38)
    $lblNotes.AutoSize = $true
    $notesBox = [System.Windows.Forms.TextBox]::new()
    $notesBox.Multiline = $true
    $notesBox.ScrollBars = 'Vertical'
    $notesBox.Location = [System.Drawing.Point]::new(6, 58)
    $notesBox.Size = [System.Drawing.Size]::new(700, 66)
    $notesBox.Anchor = 'Top,Left,Right'
    $notesBox.Font = $mono
    $verdictBottom.Controls.AddRange(@($lblOverall, $overallCombo, $saveItemBtn, $lblNotes, $notesBox))

    $lblChecks = [System.Windows.Forms.Label]::new()
    $lblChecks.Text = 'Checklist (tick = pass; leave unticked if not-yet / failed, and note why):'
    $lblChecks.Dock = 'Top'
    $lblChecks.Height = 18
    $checkList = [System.Windows.Forms.CheckedListBox]::new()
    $checkList.Dock = 'Fill'
    $checkList.Font = $mono
    $checkList.CheckOnClick = $true
    $checkList.IntegralHeight = $false

    $rightSplit.Panel2.Controls.Add($checkList)
    $rightSplit.Panel2.Controls.Add($lblChecks)
    $rightSplit.Panel2.Controls.Add($verdictBottom)

    $outer.Panel2.Controls.Add($rightSplit)

    # ===== timer =====
    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 300

    # center first, then docked edges
    $form.Controls.Add($outer)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:VState
    $s.form = $form; $s.openBtn = $openBtn; $s.exportBtn = $exportBtn; $s.packetLabel = $packetLabel
    $s.openLatestBtn = $openLatestBtn; $s.recentBtn = $recentBtn
    $s.itemList = $itemList; $s.detailBox = $detailBox
    $s.openPanel = $openPanel; $s.openCombo = $openCombo; $s.openPathBtn = $openPathBtn; $s.currentOpenPaths = @()
    $s.runBtn = $runBtn; $s.cancelBtn = $cancelBtn; $s.runHint = $runHint; $s.resultBox = $resultBox
    $s.overallCombo = $overallCombo; $s.saveItemBtn = $saveItemBtn; $s.notesBox = $notesBox; $s.checkList = $checkList
    $s.stateLabel = $stateLabel; $s.elapsedLabel = $elapsedLabel; $s.countLabel = $countLabel; $s.timer = $timer
    $s.outerSplit = $outer; $s.leftSplit = $leftSplit; $s.rightSplit = $rightSplit

    # NOTE (D-0060): handlers that touch only $script:VState / script functions are scope-safe as-is (the
    # existing handlers do the same). .GetNewClosure() is applied where a handler captures a LOCAL var (the
    # Recent-packets picker below) -- that is the bare-local null-ref case the lesson is about.
    $openBtn.Add_Click({ Invoke-OpenPacket })
    $openLatestBtn.Add_Click({ Invoke-OpenLatestPacket })
    $recentBtn.Add_Click({ Invoke-OpenRecentPacket })
    $openPathBtn.Add_Click({ Invoke-OpenSelectedReferencedPath })
    $exportBtn.Add_Click({ Invoke-ExportResult })
    $itemList.Add_SelectedIndexChanged({ Show-SelectedItem })
    $runBtn.Add_Click({ Start-ItemRunUI })
    $cancelBtn.Add_Click({ Stop-ItemRunUI })
    $saveItemBtn.Add_Click({ Save-CurrentItemVerdict; Update-ItemListLabels })
    $timer.Add_Tick({ Update-ItemRunUI })
    $form.Add_Shown({ Set-InitialLayout; if ($script:VState.pendingPacketPath) { Import-PacketPath $script:VState.pendingPacketPath } })
    $form.Add_FormClosing({ if ($script:VState.handle) { try { Stop-SkillProcess -Handle $script:VState.handle } catch { } } })

    return $form
}

function Set-InitialLayout {
    $s = $script:VState
    Set-SplitterDistanceSafe $s.outerSplit 400
    Set-SplitterDistanceSafe $s.leftSplit ([int]($s.leftSplit.Height * 0.5))
    Set-SplitterDistanceSafe $s.rightSplit ([int]($s.rightSplit.Height * 0.55))
    # size the 'Open' affordance row to the detail pane width
    try {
        $op = $s.openPanel
        $s.openPathBtn.Left = [Math]::Max(120, $op.Width - $s.openPathBtn.Width - 8)
        $s.openCombo.Width = [Math]::Max(80, $s.openPathBtn.Left - $s.openCombo.Left - 8)
    }
    catch { }
}

function Get-PacketsDirSafe {
    $s = $script:VState
    if ($null -eq $s.paths) { try { $s.paths = Resolve-VerificationPaths } catch { } }
    $repoRoot = if ($s.paths) { $s.paths.RepoRoot } else { $null }
    try { return (Get-DefaultPacketsDir -RepoRoot $repoRoot) } catch { return $null }
}

function Invoke-OpenPacket {
    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Filter = 'Verification packet (*.json)|*.json|All files (*.*)|*.*'
    $dlg.Title = 'Open verification packet'
    # D-0063: default the browse dialog into the fan-out artifacts dir so the user is already at the packets.
    $pd = Get-PacketsDirSafe
    if ($pd -and (Test-Path -LiteralPath $pd)) { $dlg.InitialDirectory = $pd }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Import-PacketPath $dlg.FileName }
}

function Invoke-OpenLatestPacket {
    # Open the newest verification packet by mtime -- no GUID hunt (D-0063).
    $pd = Get-PacketsDirSafe
    $recent = @(Get-RecentPackets -PacketsDir $pd -Max 1)
    if ($recent.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(("No verification packets found under:`r`n" + [string]$pd + "`r`n`r`nUse 'Open packet...' to browse for one."), 'Verification Console')
        return
    }
    Import-PacketPath ([string]$recent[0].path)
}

function Show-RecentPacketsPicker {
    # Build a modal list of recent packets and return the chosen index (or -1). ShowDialog is modal, so the
    # selection is read AFTER it returns -- no handler-captured state needed except the double-click shortcut.
    param($Entries)
    $picker = [System.Windows.Forms.Form]::new()
    $picker.Text = 'Recent verification packets (newest first)'
    $picker.Size = [System.Drawing.Size]::new(840, 420)
    $picker.StartPosition = 'CenterParent'
    $picker.MinimizeBox = $false; $picker.MaximizeBox = $false

    $list = [System.Windows.Forms.ListBox]::new()
    $list.Dock = 'Fill'
    $list.Font = [System.Drawing.Font]::new('Consolas', 9.5)
    $list.IntegralHeight = $false
    foreach ($e in @($Entries)) { [void]$list.Items.Add((Format-RecentPacketLine -Entry $e)) }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }

    $btnPanel = [System.Windows.Forms.Panel]::new(); $btnPanel.Dock = 'Bottom'; $btnPanel.Height = 44
    $okBtn = [System.Windows.Forms.Button]::new(); $okBtn.Text = 'Open'; $okBtn.Size = [System.Drawing.Size]::new(90, 28)
    $okBtn.Location = [System.Drawing.Point]::new(640, 8); $okBtn.Anchor = 'Top,Right'
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancelBtn = [System.Windows.Forms.Button]::new(); $cancelBtn.Text = 'Cancel'; $cancelBtn.Size = [System.Drawing.Size]::new(90, 28)
    $cancelBtn.Location = [System.Drawing.Point]::new(736, 8); $cancelBtn.Anchor = 'Top,Right'
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnPanel.Controls.AddRange(@($okBtn, $cancelBtn))
    $picker.AcceptButton = $okBtn; $picker.CancelButton = $cancelBtn

    # double-click a row = open it. This handler captures the LOCAL $picker, so .GetNewClosure() is REQUIRED
    # (D-0060: a bare local in a WinForms handler resolves to $null when the handler fires outside this scope).
    $list.Add_DoubleClick({ $picker.DialogResult = [System.Windows.Forms.DialogResult]::OK; $picker.Close() }.GetNewClosure())

    $picker.Controls.Add($list)
    $picker.Controls.Add($btnPanel)
    $result = $picker.ShowDialog()
    $idx = $list.SelectedIndex
    $picker.Dispose()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $idx -ge 0) { return $idx }
    return -1
}

function Invoke-OpenRecentPacket {
    $pd = Get-PacketsDirSafe
    $recent = @(Get-RecentPackets -PacketsDir $pd -Max 25)
    if ($recent.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(("No verification packets found under:`r`n" + [string]$pd + "`r`n`r`nUse 'Open packet...' to browse for one."), 'Verification Console')
        return
    }
    $idx = Show-RecentPacketsPicker -Entries $recent
    if ($idx -ge 0 -and $idx -lt $recent.Count) { Import-PacketPath ([string]$recent[$idx].path) }
}

function Open-PathInShell {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            [void][System.Windows.Forms.MessageBox]::Show(("Not found on disk:`r`n" + $Path), 'Verification Console'); return
        }
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Start-Process -FilePath $Path | Out-Null                                   # open the folder
        }
        else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $Path + '"') | Out-Null   # reveal the file
        }
    }
    catch { [void][System.Windows.Forms.MessageBox]::Show(("Could not open:`r`n" + $Path + "`r`n" + $_.Exception.Message), 'Verification Console') }
}

function Invoke-OpenSelectedReferencedPath {
    $s = $script:VState
    $idx = $s.openCombo.SelectedIndex
    $paths = @($s.currentOpenPaths)
    if ($idx -lt 0 -or $idx -ge $paths.Count) { return }
    Open-PathInShell ([string]$paths[$idx].path)
}

function Import-PacketPath {
    param([string]$Path)
    $s = $script:VState
    $pk = Import-VerificationPacket -Path $Path
    if (-not [bool]$pk.ok) {
        [void][System.Windows.Forms.MessageBox]::Show(('Could not load packet:' + "`r`n" + [string]$pk.error), 'Verification Console')
        return
    }
    $s.packet = $pk
    $s.items = @($pk.items)
    # per-item verdict state now lives in the CORE (D-0064): a plain id->state store, seeded + saved + read
    # through Initialize-ItemVerdictStore / Save-ItemVerdictState / Get-ItemVerdictState so the whole
    # save/restore cycle is unit-tested off-machine (the shell-only logic slipped the 133/133 mock gate).
    $s.itemState = Initialize-ItemVerdictStore -Items $s.items
    $s.currentId = $null
    Set-VText $s.detailBox (Format-PacketSummary -Packet $pk)
    $plan = [string]$pk.plan_id; if (-not $plan) { $plan = Get-PlanIdFromPacket -Packet $pk }
    $s.packetLabel.Text = ('Packet: ' + [string]$pk.title + '   plan=' + $(if ($plan) { $plan } else { '(none)' }) +
        '   (' + [string]$pk.item_count + ' items, report_back=' + [string]$pk.report_back + ')')
    $s.packetLabel.ForeColor = [System.Drawing.Color]::Black
    $s.exportBtn.Enabled = $true
    $s.countLabel.Text = 'Items: ' + [string]$pk.item_count
    Update-ItemListLabels
    if ($s.itemList.Items.Count -gt 0) { $s.itemList.SelectedIndex = 0 }
}

function Update-ItemListLabels {
    $s = $script:VState
    $sel = $s.itemList.SelectedIndex
    # Relabelling clears + refills the list, and Clear()/reselect raise SelectedIndexChanged. Suspend item
    # events across the rebuild so that churn cannot re-enter Show-SelectedItem and drive a spurious
    # Save-CurrentItemVerdict against transitional control state (a data-loss path). D-0064.
    $prevSuspend = $s.suspendItemEvents
    $s.suspendItemEvents = $true
    try {
        $s.itemList.BeginUpdate()
        $s.itemList.Items.Clear()
        foreach ($it in $s.items) {
            $st = Get-ItemVerdictState -Store $s.itemState -ItemId ([string]$it.id)
            $verdict = [string](Get-Prop $st 'overall' 'skipped')
            $mark = switch ($verdict) { 'pass' { '(pass) ' } 'fail' { '(FAIL) ' } 'partial' { '(part) ' } default { '' } }
            [void]$s.itemList.Items.Add(($mark + (Format-ItemListLine -Item $it)))
        }
        $s.itemList.EndUpdate()
        if ($sel -ge 0 -and $sel -lt $s.itemList.Items.Count) { $s.itemList.SelectedIndex = $sel }
    }
    finally { $s.suspendItemEvents = $prevSuspend }
}

function Get-SelectedItem {
    $s = $script:VState
    $idx = $s.itemList.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($s.items).Count) { return $null }
    return @($s.items)[$idx]
}

function Show-SelectedItem {
    $s = $script:VState
    if ($s.suspendItemEvents) { return }   # a programmatic list/control rebuild is in progress -- ignore (D-0064)
    # save the outgoing item's verdict first
    if ($s.currentId) { Save-CurrentItemVerdict }
    $it = Get-SelectedItem
    if ($null -eq $it) { return }
    $s.currentId = [string]$it.id

    if ($null -eq $s.paths) { try { $s.paths = Resolve-VerificationPaths } catch { } }
    $repoRoot = if ($s.paths) { $s.paths.RepoRoot } else { $null }
    Set-VText $s.detailBox (Format-ItemDetail -Item $it -RepoRoot $repoRoot)

    # The core action model decides Run-button state + which referenced paths to offer 'Open' for. All the
    # by-kind / validity logic is in the core (unit-tested); the shell only renders it here.
    $am = Get-ItemActionModel -Item $it -RepoRoot $repoRoot
    $s.currentOpenPaths = @($am.open_paths)
    $s.openCombo.Items.Clear()
    foreach ($p in @($s.currentOpenPaths)) {
        $mark = if ([bool](Get-Prop $p 'exists' $false)) { '' } else { '  (not found)' }
        [void]$s.openCombo.Items.Add(([string](Get-Prop $p 'label') + $mark))
    }
    $hasPaths = (@($s.currentOpenPaths).Count -gt 0)
    if ($hasPaths) { $s.openCombo.SelectedIndex = 0 }
    $s.openCombo.Enabled = $hasPaths
    $s.openPathBtn.Enabled = $hasPaths

    # load this item's saved verdict state into the controls -- ALL of {checks, overall, notes} restored from
    # the CORE store (D-0064). suspendItemEvents guards the repopulation so no control update can re-enter a
    # save; SetItemChecked FORCES the checkbox state, because CheckedListBox.Items.Add(text, [bool]) does not
    # reliably render the tick under CheckOnClick -- so the check the user saved actually shows on return.
    $st = Get-ItemVerdictState -Store $s.itemState -ItemId ([string]$it.id)
    $prevSuspend = $s.suspendItemEvents
    $s.suspendItemEvents = $true
    try {
        $s.checkList.Items.Clear()
        $ci = 0
        foreach ($c in @(Get-Prop $st 'checks' @())) {
            $checked = ([string](Get-Prop $c 'verdict') -eq 'pass')
            [void]$s.checkList.Items.Add(([string](Get-Prop $c 'text')), $checked)
            try { $s.checkList.SetItemChecked($ci, $checked) } catch { }
            $ci++
        }
        $ovi = $s.overallCombo.Items.IndexOf([string](Get-Prop $st 'overall' 'skipped'))
        $s.overallCombo.SelectedIndex = $(if ($ovi -ge 0) { $ovi } else { 0 })
        $s.notesBox.Text = [string](Get-Prop $st 'notes' '')
    }
    finally { $s.suspendItemEvents = $prevSuspend }
    $stRunText = [string](Get-Prop $st 'runText' '')
    if ($stRunText) { Set-VText $s.resultBox $stRunText }
    elseif ([string]$it.kind -eq 'human_action') { Set-VText $s.resultBox 'This is a hand task - do it, then record the verdict below.' }
    elseif ([bool]$am.invalid) { Set-VText $s.resultBox ([string]$am.reason + "`r`n" + [string]$am.fix_hint) }
    else { Set-VText $s.resultBox 'Press Run item to run this module locally.' }

    $s.runBtn.Enabled = ([bool]$am.can_run -and $null -eq $s.handle)
    $s.runHint.Text = [string]$am.reason
}

function Save-CurrentItemVerdict {
    $s = $script:VState
    if (-not $s.currentId) { return }
    if ($s.suspendItemEvents) { return }   # never persist while a programmatic control rebuild is in progress (D-0064)
    # thin marshaller: read the control snapshot, hand it to the CORE store logic (unit-tested off-machine).
    $checked = New-Object System.Collections.Generic.List[bool]
    $texts = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $s.checkList.Items.Count; $i++) {
        $checked.Add([bool]$s.checkList.GetItemChecked($i))
        $texts.Add([string]$s.checkList.Items[$i])
    }
    [void](Save-ItemVerdictState -Store $s.itemState -ItemId ([string]$s.currentId) `
            -Checked $checked.ToArray() -Overall ([string]$s.overallCombo.SelectedItem) `
            -Notes ([string]$s.notesBox.Text) -CheckTexts $texts.ToArray())
}

function Start-ItemRunUI {
    $s = $script:VState
    $it = Get-SelectedItem
    if ($null -eq $it) { return }
    if ([string]$it.kind -ne 'run_module' -or -not [bool]$it.valid) {
        [void][System.Windows.Forms.MessageBox]::Show('This item is not a runnable module.', 'Verification Console'); return
    }
    $inputs = [string]$it.inputs_json
    if ([string]::IsNullOrWhiteSpace($inputs)) { $inputs = '{}' }
    try { [void]($inputs | ConvertFrom-Json) }
    catch { [void][System.Windows.Forms.MessageBox]::Show(("The item's inputs_json is not valid JSON:`r`n" + $_.Exception.Message), 'Verification Console'); return }

    if ($null -eq $s.paths) { try { $s.paths = Resolve-VerificationPaths } catch { } }
    $repoRoot = if ($s.paths) { $s.paths.RepoRoot } else { $null }
    $skillDir = Resolve-ItemSkillDir -Item $it -RepoRoot $repoRoot

    Set-VText $s.resultBox ('Running ' + [string]$it.skill_id + ' through the Module 1 wrapper ...' + "`r`n" + '(loading any models this module needs can take a moment)')
    $s.runBtn.Enabled = $false; $s.openBtn.Enabled = $false; $s.cancelBtn.Enabled = $true
    $s.openLatestBtn.Enabled = $false; $s.recentBtn.Enabled = $false
    $s.stateLabel.Text = 'State: Running ' + [string]$it.skill_id
    $s.startedUtc = [datetime]::UtcNow
    try {
        $h = Start-SkillProcess -SkillDir $skillDir -InputsJson $inputs -WorkingDir $repoRoot `
            -InvokeSkillPath $s.invokeSkillPath -PwshPath $s.pwshPath
        $s.handle = $h
        $s.timer.Start()
    }
    catch {
        $s.stateLabel.Text = 'State: Error'
        Set-VText $s.resultBox ('Failed to start the module:' + "`r`n" + $_.Exception.Message)
        $s.runBtn.Enabled = $true; $s.openBtn.Enabled = $true; $s.cancelBtn.Enabled = $false
        $s.openLatestBtn.Enabled = $true; $s.recentBtn.Enabled = $true
    }
}

function Update-ItemRunUI {
    $s = $script:VState
    if (-not $s.handle) { $s.timer.Stop(); return }
    $elapsed = [int]([datetime]::UtcNow - $s.startedUtc).TotalSeconds
    $s.elapsedLabel.Text = "Elapsed: ${elapsed}s"
    if (-not $s.handle.Process.HasExited) { return }

    $s.timer.Stop()
    $run = Complete-SkillRun -Handle $s.handle
    $text = Format-SkillResult -Run $run
    Set-VText $s.resultBox $text
    if ($s.currentId) {
        $st = $s.itemState[[string]$s.currentId]
        $st.ran = $true; $st.run = $run; $st.runText = $text
        $s.itemState[[string]$s.currentId] = $st
    }
    $s.stateLabel.Text = if ($run.ok) { 'State: Done (' + [string]$run.skill_status + ')' } else { 'State: Finished (' + [string]$run.skill_status + ')' }
    $s.runBtn.Enabled = $true; $s.openBtn.Enabled = $true; $s.cancelBtn.Enabled = $false
    $s.openLatestBtn.Enabled = $true; $s.recentBtn.Enabled = $true
    $s.handle = $null
}

function Stop-ItemRunUI {
    $s = $script:VState
    if ($s.handle) { try { Stop-SkillProcess -Handle $s.handle } catch { } }
    $s.timer.Stop()
    $s.stateLabel.Text = 'State: Cancelled'
    $s.resultBox.AppendText("`r`n`r`n[cancelled by user]")
    $s.runBtn.Enabled = $true; $s.openBtn.Enabled = $true; $s.cancelBtn.Enabled = $false
    $s.openLatestBtn.Enabled = $true; $s.recentBtn.Enabled = $true
    $s.handle = $null
}

function Invoke-ExportResult {
    $s = $script:VState
    if ($null -eq $s.packet) { return }
    Save-CurrentItemVerdict
    $resultItems = New-Object System.Collections.Generic.List[object]
    foreach ($it in $s.items) {
        $st = $s.itemState[[string]$it.id]
        $run = if ($st) { $st.run } else { $null }
        $checks = if ($st) { $st.checks } else { @() }
        $overall = if ($st) { [string]$st.overall } else { 'skipped' }
        $notes = if ($st) { [string]$st.notes } else { '' }
        $resultItems.Add((New-VerificationResultItem -Item $it -Run $run -Checks $checks -Overall $overall -Notes $notes))
    }
    $result = New-VerificationResult -Packet $s.packet -Items $resultItems.ToArray()

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Filter = 'Verification result (*.json)|*.json'
    $dlg.Title = 'Export verification result'
    $pid2 = [string]$s.packet.packet_id; if (-not $pid2) { $pid2 = 'result' }
    $dlg.FileName = ('verification-result-' + $pid2 + '.json')
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            [void](Save-VerificationResult -Result $result -Path $dlg.FileName)
            $sum = $result.summary
            [void][System.Windows.Forms.MessageBox]::Show(
                ('Saved.' + "`r`n" + 'pass=' + $sum.pass + ' fail=' + $sum.fail + ' partial=' + $sum.partial + ' skipped=' + $sum.skipped + ' / ' + $sum.total),
                'Verification Console')
        }
        catch { [void][System.Windows.Forms.MessageBox]::Show(('Could not save:' + "`r`n" + $_.Exception.Message), 'Verification Console') }
    }
}

# ----- entry -----
if ($PacketPath) { $script:VState.pendingPacketPath = $PacketPath }
$form = New-VerificationForm
if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    # D-0060 lesson (mock/API gates miss rendered-UI bugs): exercise the NEW discovery + by-kind rendering
    # paths on the built form under STA, so a scope/null bug in Show-SelectedItem / Get-ItemActionModel / the
    # Open affordance is caught here, not only in a human pass. Defensive: a throw prints a FAIL marker the
    # gate asserts on, rather than crashing the SelfTest.
    try {
        $s = $script:VState
        $fx = Join-Path $PSScriptRoot (Join-Path 'tests' (Join-Path 'fixtures' 'packet.json'))
        if (Test-Path -LiteralPath $fx) {
            Import-PacketPath $fx
            if ($s.itemList.Items.Count -ge 3) { Write-Output 'SELFTEST_PACKET_LOADED_OK' }
            $sawHuman = $false; $sawRun = $false
            for ($i = 0; $i -lt $s.itemList.Items.Count; $i++) {
                $s.itemList.SelectedIndex = $i    # fires Show-SelectedItem -> Get-ItemActionModel + Open combo
                $it = @($s.items)[$i]
                if ([string]$it.kind -eq 'human_action') { $sawHuman = $true }
                if ([string]$it.kind -eq 'run_module') { $sawRun = $true }
            }
            $humanIdx = -1
            for ($i = 0; $i -lt @($s.items).Count; $i++) { if ([string](@($s.items)[$i].kind) -eq 'human_action') { $humanIdx = $i; break } }
            if ($humanIdx -ge 0) {
                $s.itemList.SelectedIndex = $humanIdx
                $openOk = ($s.openCombo.Items.Count -ge 1)          # human fixture references launch.bat
                $runDisabledForHuman = (-not $s.runBtn.Enabled)     # nothing to run for a hand task
                if ($sawHuman -and $sawRun -and $openOk -and $runDisabledForHuman) { Write-Output 'SELFTEST_ITEMRENDER_OK' }
            }
            if (Get-PacketsDirSafe) { Write-Output 'SELFTEST_PACKETSDIR_OK' }

            # D-0064: exercise the verdict SAVE/RESTORE cycle on the REAL controls under STA. This class of bug
            # (checklist + Overall verdict reset on navigate-away-and-back) slipped the mock gate; only a
            # live-form exercise catches a rendered-UI / marshalling regression.
            $withChecks = -1
            for ($i = 0; $i -lt @($s.items).Count; $i++) { if (@(@($s.items)[$i].checklist).Count -ge 1) { $withChecks = $i; break } }
            if ($withChecks -ge 0 -and $s.itemList.Items.Count -gt 1) {
                $s.itemList.SelectedIndex = $withChecks
                $targetId = [string](@($s.items)[$withChecks].id)
                $s.checkList.SetItemChecked(0, $true)                       # tick the first checklist row
                $pIdx = $s.overallCombo.Items.IndexOf('pass'); if ($pIdx -ge 0) { $s.overallCombo.SelectedIndex = $pIdx }
                $s.notesBox.Text = 'selftest verdict note'
                Save-CurrentItemVerdict                                     # what the Save button does
                $other = if ($withChecks -eq 0) { 1 } else { 0 }
                $s.itemList.SelectedIndex = $other                          # navigate away...
                $s.itemList.SelectedIndex = $withChecks                     # ...and back
                $tickOk = ($s.checkList.Items.Count -ge 1 -and [bool]$s.checkList.GetItemChecked(0))
                $overallOk = ([string]$s.overallCombo.SelectedItem -eq 'pass')
                $notesOk = ([string]$s.notesBox.Text -eq 'selftest verdict note')
                $storeOk = ([string](Get-ItemVerdictState -Store $s.itemState -ItemId $targetId).overall -eq 'pass')
                if ($tickOk -and $overallOk -and $notesOk -and $storeOk) { Write-Output 'SELFTEST_VERDICT_PERSIST_OK' }
                else { Write-Output ('SELFTEST_VERDICT_PERSIST_FAIL: tick=' + $tickOk + ' overall=' + $overallOk + ' notes=' + $notesOk + ' store=' + $storeOk) }
            }
        }
    }
    catch { Write-Output ('SELFTEST_ITEMRENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
