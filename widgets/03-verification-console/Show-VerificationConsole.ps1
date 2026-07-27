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
    $openBtn.Size = [System.Drawing.Size]::new(110, 26)
    $exportBtn = [System.Windows.Forms.Button]::new()
    $exportBtn.Text = 'Export result...'
    $exportBtn.Location = [System.Drawing.Point]::new(124, 7)
    $exportBtn.Size = [System.Drawing.Size]::new(120, 26)
    $exportBtn.Enabled = $false
    $packetLabel = [System.Windows.Forms.Label]::new()
    $packetLabel.Text = 'No packet loaded. Open a verification packet Claude wrote.'
    $packetLabel.Location = [System.Drawing.Point]::new(258, 12)
    $packetLabel.AutoSize = $true
    $packetLabel.ForeColor = [System.Drawing.Color]::DimGray
    $toolbar.Controls.AddRange(@($openBtn, $exportBtn, $packetLabel))

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
    $leftSplit.Panel2.Controls.Add($detailBox)
    $leftSplit.Panel2.Controls.Add($lblDetail)

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
    $s.itemList = $itemList; $s.detailBox = $detailBox
    $s.runBtn = $runBtn; $s.cancelBtn = $cancelBtn; $s.runHint = $runHint; $s.resultBox = $resultBox
    $s.overallCombo = $overallCombo; $s.saveItemBtn = $saveItemBtn; $s.notesBox = $notesBox; $s.checkList = $checkList
    $s.stateLabel = $stateLabel; $s.elapsedLabel = $elapsedLabel; $s.countLabel = $countLabel; $s.timer = $timer
    $s.outerSplit = $outer; $s.leftSplit = $leftSplit; $s.rightSplit = $rightSplit

    $openBtn.Add_Click({ Invoke-OpenPacket })
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
}

function Invoke-OpenPacket {
    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Filter = 'Verification packet (*.json)|*.json|All files (*.*)|*.*'
    $dlg.Title = 'Open verification packet'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Import-PacketPath $dlg.FileName }
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
    $s.itemState = @{}
    foreach ($it in $s.items) {
        $checks = New-Object System.Collections.Generic.List[object]
        foreach ($c in @($it.checklist)) { $checks.Add(@{ id = [string]$c.id; text = [string]$c.text; verdict = 'unchecked'; note = '' }) }
        $s.itemState[[string]$it.id] = @{ checks = $checks.ToArray(); overall = 'skipped'; notes = ''; ran = $false; run = $null; runText = '' }
    }
    $s.currentId = $null
    Set-VText $s.detailBox (Format-PacketSummary -Packet $pk)
    $s.packetLabel.Text = ('Packet: ' + [string]$pk.title + '   (' + [string]$pk.item_count + ' items, report_back=' + [string]$pk.report_back + ')')
    $s.packetLabel.ForeColor = [System.Drawing.Color]::Black
    $s.exportBtn.Enabled = $true
    $s.countLabel.Text = 'Items: ' + [string]$pk.item_count
    Update-ItemListLabels
    if ($s.itemList.Items.Count -gt 0) { $s.itemList.SelectedIndex = 0 }
}

function Update-ItemListLabels {
    $s = $script:VState
    $sel = $s.itemList.SelectedIndex
    $s.itemList.BeginUpdate()
    $s.itemList.Items.Clear()
    foreach ($it in $s.items) {
        $st = $s.itemState[[string]$it.id]
        $verdict = if ($st) { [string]$st.overall } else { 'skipped' }
        $mark = switch ($verdict) { 'pass' { '(pass) ' } 'fail' { '(FAIL) ' } 'partial' { '(part) ' } default { '' } }
        [void]$s.itemList.Items.Add(($mark + (Format-ItemListLine -Item $it)))
    }
    $s.itemList.EndUpdate()
    if ($sel -ge 0 -and $sel -lt $s.itemList.Items.Count) { $s.itemList.SelectedIndex = $sel }
}

function Get-SelectedItem {
    $s = $script:VState
    $idx = $s.itemList.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($s.items).Count) { return $null }
    return @($s.items)[$idx]
}

function Show-SelectedItem {
    $s = $script:VState
    # save the outgoing item's verdict first
    if ($s.currentId) { Save-CurrentItemVerdict }
    $it = Get-SelectedItem
    if ($null -eq $it) { return }
    $s.currentId = [string]$it.id
    Set-VText $s.detailBox (Format-ItemDetail -Item $it)

    # load this item's saved verdict state into the controls
    $st = $s.itemState[[string]$it.id]
    $s.checkList.Items.Clear()
    foreach ($c in @($st.checks)) {
        $checked = ([string]$c.verdict -eq 'pass')
        [void]$s.checkList.Items.Add(([string]$c.text), $checked)
    }
    $ovi = $s.overallCombo.Items.IndexOf([string]$st.overall)
    $s.overallCombo.SelectedIndex = $(if ($ovi -ge 0) { $ovi } else { 0 })
    $s.notesBox.Text = [string]$st.notes
    if ($st.runText) { Set-VText $s.resultBox ([string]$st.runText) }
    else { Set-VText $s.resultBox $(if ([string]$it.kind -eq 'human_action') { 'This is a hand task - do it, then record the verdict below.' } else { 'Press Run item to run this module locally.' }) }

    $canRun = ([string]$it.kind -eq 'run_module' -and [bool]$it.valid -and $null -eq $s.handle)
    $s.runBtn.Enabled = $canRun
}

function Save-CurrentItemVerdict {
    $s = $script:VState
    if (-not $s.currentId) { return }
    $st = $s.itemState[[string]$s.currentId]
    if (-not $st) { return }
    $checks = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $s.checkList.Items.Count; $i++) {
        $src = if ($i -lt @($st.checks).Count) { @($st.checks)[$i] } else { @{ id = ('c' + ($i + 1)); text = [string]$s.checkList.Items[$i]; note = '' } }
        $verdict = if ($s.checkList.GetItemChecked($i)) { 'pass' } else { 'unchecked' }
        $checks.Add(@{ id = [string]$src.id; text = [string]$src.text; verdict = $verdict; note = [string]$src.note })
    }
    $st.checks = $checks.ToArray()
    $st.overall = [string]$s.overallCombo.SelectedItem
    if (-not $st.overall) { $st.overall = 'skipped' }
    $st.notes = [string]$s.notesBox.Text
    $s.itemState[[string]$s.currentId] = $st
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
    $s.handle = $null
}

function Stop-ItemRunUI {
    $s = $script:VState
    if ($s.handle) { try { Stop-SkillProcess -Handle $s.handle } catch { } }
    $s.timer.Stop()
    $s.stateLabel.Text = 'State: Cancelled'
    $s.resultBox.AppendText("`r`n`r`n[cancelled by user]")
    $s.runBtn.Enabled = $true; $s.openBtn.Enabled = $true; $s.cancelBtn.Enabled = $false
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
    $form.Dispose()
    Write-Output 'SELFTEST_FORM_OK'
    return
}
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
