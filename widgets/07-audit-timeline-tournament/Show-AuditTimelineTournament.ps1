<#
    Show-AuditTimelineTournament.ps1 - the Audit Timeline + Tournament console (Widget 07) UI entrypoint.

    A native WinForms window (run STA) that RENDERS, STRICTLY READ-ONLY, the audit-pipeline tier A2 slice:
      - the s2.6 tool-selection TOURNAMENT (router + selpol + plan-validation elimination brackets with a
        machine reconciliation proof), over a real #40 routed context_packet (+ the #30 plan), and
      - the s2.1 cross-context OMNISCIENT stitched TIMELINE (a real wave: #30 plan + reports, stitched with
        #39 episodes + #42 state_version chains + batons-when-present).
    It drives NOTHING: no doc write, no git write, no executor job, no model call, NO lease held, NO pause
    point. non_execution holds; it enables no action; it writes NOTHING outside its own runtime/ dir.

    It is a THIN shell over AuditTimelineTournament.psm1: the UI only builds controls and renders the core's
    Get-AuditModel / Format-AuditHeader output. All parsing, the tournament brackets, the reconciliation, and
    the timeline stitch live in the tested, WinForms-free core.

    Launch:    launch.bat   (pwsh -NoProfile -STA -File Show-AuditTimelineTournament.ps1)
    Self-test: pwsh -STA -File Show-AuditTimelineTournament.ps1 -SelfTest   (builds + drives + disposes the
               form off-screen over the committed REAL fixtures; prints SELFTEST_*_OK incl. SELFTEST_LAYOUT_OK
               + SELFTEST_READONLY_OK + SELFTEST_TOURNAMENT_OK + SELFTEST_TIMELINE_OK)
    Options:   -PacketFile <path> a specific #40 packet; -PlanFile <path> a specific #30 plan.json (its
               reports/ sibling is read); -RepoRoot <dir> the repo to discover real artifacts under (else ../..).
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$PacketFile,
    [string]$PlanFile,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AuditTimelineTournament.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:AState = @{
    form       = $null
    widgetRoot = $PSScriptRoot
    repoRoot   = $RepoRoot
    packetPath = $PacketFile
    planPath   = $PlanFile
    model      = $null
    tabs       = @{}
}

function Set-WText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Resolve-DefaultPacket {
    $s = $script:AState
    if ($s.packetPath -and (Test-Path -LiteralPath $s.packetPath -PathType Leaf)) { return $s.packetPath }
    $paths = Resolve-AuditPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    $real = Find-NewestRoutedPacket -ArtifactsDir $paths.CompilerArtifacts
    if ($real) { return $real }
    $fx = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'routed_packet.json'))
    if (Test-Path -LiteralPath $fx -PathType Leaf) { return $fx }
    return $null
}

function Resolve-DefaultWave {
    # Returns { plan_path, report_paths[] } from -PlanFile (+ its reports/ sibling), else the newest real
    # complete wave on the box, else the bundled fixture wave.
    $s = $script:AState
    if ($s.planPath -and (Test-Path -LiteralPath $s.planPath -PathType Leaf)) {
        $repDir = Join-Path (Split-Path $s.planPath -Parent) 'reports'
        $reps = @()
        if (Test-Path -LiteralPath $repDir -PathType Container) { $reps = @(Get-ChildItem -LiteralPath $repDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
        return [pscustomobject]@{ plan_path = $s.planPath; report_paths = $reps }
    }
    $paths = Resolve-AuditPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    $real = Find-NewestCompleteWave -PlansDir $paths.PlansDir
    if ($null -ne $real) { return [pscustomobject]@{ plan_path = $real.plan_path; report_paths = $real.report_paths } }
    $fxPlan = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' (Join-Path 'wave' 'plan.json')))
    $fxRepDir = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' (Join-Path 'wave' 'reports')))
    $reps = @()
    if (Test-Path -LiteralPath $fxRepDir -PathType Container) { $reps = @(Get-ChildItem -LiteralPath $fxRepDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    if (Test-Path -LiteralPath $fxPlan -PathType Leaf) { return [pscustomobject]@{ plan_path = $fxPlan; report_paths = $reps } }
    return [pscustomobject]@{ plan_path = $null; report_paths = @() }
}

function Resolve-Episodes {
    $s = $script:AState
    $paths = Resolve-AuditPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    $real = @(Find-Episodes -EpisodesDir $paths.EpisodesDir -Max 6)
    if ($real.Count -gt 0) { return $real }
    $fxDir = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'episodes'))
    if (Test-Path -LiteralPath $fxDir -PathType Container) { return @(Get-ChildItem -LiteralPath $fxDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    return @()
}

function Resolve-WorkingStates {
    $s = $script:AState
    $paths = Resolve-AuditPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    $real = @(Find-WorkingStates -WorkingMemoryDir $paths.WorkingMemoryDir -Max 20)
    if ($real.Count -gt 0) { return $real }
    $fx = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'working_state.json'))
    if (Test-Path -LiteralPath $fx -PathType Leaf) { return @($fx) }
    return @()
}

function New-AttTab {
    param([string]$Name, [string]$Text, [System.Drawing.Font]$Mono)
    $page = [System.Windows.Forms.TabPage]::new()
    $page.Text = $Text
    $list = [System.Windows.Forms.ListBox]::new()
    $list.Dock = 'Fill'; $list.Font = $Mono; $list.IntegralHeight = $false; $list.HorizontalScrollbar = $true
    $page.Controls.Add($list)
    $script:AState.tabs[$Name] = @{ page = $page; list = $list }
    return $page
}

function Update-AttToolbarLayout {
    # Position both toolbar rows from the toolbar's ACTUAL width (the widget-04 off-screen-toolbar lesson).
    $s = $script:AState
    if ($null -eq $s) { return }
    foreach ($k in 'toolbar', 'refreshBtn', 'packetBox', 'browsePacketBtn', 'planBox', 'browsePlanBtn') { if (-not $s.ContainsKey($k)) { return } }
    foreach ($k in 'toolbar', 'refreshBtn', 'packetBox', 'browsePacketBtn', 'planBox', 'browsePlanBtn') { if ($null -eq $s[$k]) { return } }
    $margin = 8; $gap = 8
    $w = [int]$s.toolbar.ClientSize.Width
    if ($w -le 0) { return }
    # row 1 (y=8): packet box stretches x=64..Browse; Browse pinned right
    $s.browsePacketBtn.Top = 8; $s.browsePacketBtn.Left = $w - $s.browsePacketBtn.Width - $margin
    $s.packetBox.Top = 9; $s.packetBox.Left = 64
    $pbW = $s.browsePacketBtn.Left - $gap - $s.packetBox.Left
    if ($pbW -lt 120) { $pbW = 120 }
    $s.packetBox.Width = $pbW
    # row 2 (y=42): Refresh pinned right, Browse-wave left of it, plan box stretches to Browse-wave
    $s.refreshBtn.Top = 42; $s.refreshBtn.Left = $w - $s.refreshBtn.Width - $margin
    $s.browsePlanBtn.Top = 42; $s.browsePlanBtn.Left = $s.refreshBtn.Left - $s.browsePlanBtn.Width - $gap
    $s.planBox.Top = 43; $s.planBox.Left = 64
    $plW = $s.browsePlanBtn.Left - $gap - $s.planBox.Left
    if ($plW -lt 120) { $plW = 120 }
    $s.planBox.Width = $plW
}

function New-AttForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Audit Timeline + Tournament - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1240, 860)
    $form.MinimumSize = [System.Drawing.Size]::new(960, 600)
    $form.StartPosition = 'CenterScreen'

    $status = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $statusLabel.Text = 'Loading...'
    [void]$status.Items.Add($statusLabel)

    # ===== toolbar =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'; $toolbar.Height = 76

    $lblPacket = [System.Windows.Forms.Label]::new()
    $lblPacket.Text = 'Packet:'; $lblPacket.Location = [System.Drawing.Point]::new(8, 12); $lblPacket.AutoSize = $true
    $packetBox = [System.Windows.Forms.TextBox]::new()
    $packetBox.Location = [System.Drawing.Point]::new(64, 9); $packetBox.Width = 720; $packetBox.Font = $mono; $packetBox.ReadOnly = $true
    $browsePacketBtn = [System.Windows.Forms.Button]::new()
    $browsePacketBtn.Text = 'Browse...'; $browsePacketBtn.Size = [System.Drawing.Size]::new(84, 24); $browsePacketBtn.Location = [System.Drawing.Point]::new(792, 8)

    $lblPlan = [System.Windows.Forms.Label]::new()
    $lblPlan.Text = 'Wave:'; $lblPlan.Location = [System.Drawing.Point]::new(8, 46); $lblPlan.AutoSize = $true
    $planBox = [System.Windows.Forms.TextBox]::new()
    $planBox.Location = [System.Drawing.Point]::new(64, 43); $planBox.Width = 620; $planBox.Font = $mono; $planBox.ReadOnly = $true
    $browsePlanBtn = [System.Windows.Forms.Button]::new()
    $browsePlanBtn.Text = 'Browse wave...'; $browsePlanBtn.Size = [System.Drawing.Size]::new(104, 24); $browsePlanBtn.Location = [System.Drawing.Point]::new(700, 42)
    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Refresh'; $refreshBtn.Size = [System.Drawing.Size]::new(96, 24); $refreshBtn.Location = [System.Drawing.Point]::new(812, 42)

    $toolbar.Controls.AddRange(@($lblPacket, $packetBox, $browsePacketBtn, $lblPlan, $planBox, $browsePlanBtn, $refreshBtn))
    $script:AState.toolbar = $toolbar
    $script:AState.packetBox = $packetBox
    $script:AState.browsePacketBtn = $browsePacketBtn
    $script:AState.planBox = $planBox
    $script:AState.browsePlanBtn = $browsePlanBtn
    $script:AState.refreshBtn = $refreshBtn
    $toolbar.Add_Resize({ Update-AttToolbarLayout }.GetNewClosure())

    # ===== header =====
    $headerBox = [System.Windows.Forms.RichTextBox]::new()
    $headerBox.Dock = 'Top'; $headerBox.Height = 84; $headerBox.ReadOnly = $true
    $headerBox.Font = $mono; $headerBox.BackColor = [System.Drawing.Color]::White; $headerBox.BorderStyle = 'None'
    $headerBox.Text = 'Loading...'

    # ===== tabs =====
    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'; $tabs.Font = $mono
    [void]$tabs.TabPages.Add((New-AttTab -Name 'tournament' -Text 'Tournament (s2.6)' -Mono $mono))
    [void]$tabs.TabPages.Add((New-AttTab -Name 'timeline' -Text 'Timeline (s2.1)' -Mono $mono))
    [void]$tabs.TabPages.Add((New-AttTab -Name 'flags' -Text 'Flags' -Mono $mono))

    $form.Controls.Add($tabs)
    $form.Controls.Add($headerBox)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:AState
    $s.form = $form; $s.headerBox = $headerBox; $s.tabControl = $tabs; $s.statusLabel = $statusLabel

    $refreshBtn.Add_Click({ Invoke-AttRefresh }.GetNewClosure())
    $browsePacketBtn.Add_Click({
            try {
                $dlg = [System.Windows.Forms.OpenFileDialog]::new()
                $dlg.Filter = 'JSON packet (*.json)|*.json|All files (*.*)|*.*'
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:AState.packetPath = $dlg.FileName; Invoke-AttRefresh }
            }
            catch { $script:AState.statusLabel.Text = 'browse failed: ' + $_.Exception.Message }
        }.GetNewClosure())
    $browsePlanBtn.Add_Click({
            try {
                $dlg = [System.Windows.Forms.OpenFileDialog]::new()
                $dlg.Filter = 'fan-out plan (plan.json)|plan.json|JSON (*.json)|*.json|All files (*.*)|*.*'
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:AState.planPath = $dlg.FileName; Invoke-AttRefresh }
            }
            catch { $script:AState.statusLabel.Text = 'browse failed: ' + $_.Exception.Message }
        }.GetNewClosure())
    $form.Add_Shown({
            Update-AttToolbarLayout
            Invoke-AttRefresh
        }.GetNewClosure())

    return $form
}

function Set-TabLines {
    param([string]$Name, $Lines)
    $s = $script:AState
    if (-not $s.tabs.ContainsKey($Name)) { return }
    $t = $s.tabs[$Name]
    $t.list.BeginUpdate()
    $t.list.Items.Clear()
    foreach ($ln in @($Lines)) { [void]$t.list.Items.Add([string]$ln) }
    $t.list.EndUpdate()
}

function Get-AttModel {
    $s = $script:AState
    $packet = Resolve-DefaultPacket
    $wave = Resolve-DefaultWave
    $episodes = @(Resolve-Episodes)
    $states = @(Resolve-WorkingStates)
    return Get-AuditModel -PacketPath $packet -PlanPath $wave.plan_path -ReportPaths @($wave.report_paths) `
        -EpisodePaths $episodes -WorkingStatePaths $states -RepoRoot $s.repoRoot -WidgetRoot $s.widgetRoot
}

function Render-AttModel {
    $s = $script:AState
    $model = Get-AttModel
    $s.model = $model
    $hdr = Format-AuditHeader -Model $model
    Set-WText $s.headerBox (($hdr.header_lines) -join "`r`n")
    $s.statusLabel.Text = [string]$hdr.summary_line
    if ($null -ne $model.packet_source) { $s.packetBox.Text = [string]$model.packet_source }
    if ($null -ne $model.timeline) { $s.planBox.Text = [string]$model.timeline.wave_plan_id }

    if ($null -ne $model.tournament) {
        Set-TabLines -Name 'tournament' -Lines (@($model.tournament.header) + @('') + @($model.tournament.lines))
    }
    else { Set-TabLines -Name 'tournament' -Lines @('(no packet -- tournament unavailable; use Browse)') }

    if ($null -ne $model.timeline) {
        $srcLine = ('sources: wave=' + $model.timeline.wave_plan_id + '  events=' + $model.timeline.counts.total_events +
            '  (wave=' + $model.timeline.counts.wave_events + ' episode=' + $model.timeline.counts.episode_events +
            ' state=' + $model.timeline.counts.working_state_events + ' baton=' + $model.timeline.counts.baton_count + ')' +
            '  span=' + $model.timeline.span_from + ' .. ' + $model.timeline.span_to)
        Set-TabLines -Name 'timeline' -Lines (@($model.timeline.header) + @($srcLine) + @('') + @($model.timeline.lines))
    }
    else { Set-TabLines -Name 'timeline' -Lines @('(no wave -- timeline unavailable)') }

    $flagLines = @($model.flags)
    if ($flagLines.Count -eq 0) { $flagLines = @('(no flags -- clean render; tournament reconciled + timeline sanitized)') }
    Set-TabLines -Name 'flags' -Lines $flagLines
}

function Invoke-AttRefresh { Render-AttModel }

# ----- entry -----
$form = New-AttForm

if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) } catch { }
    try {
        $s = $script:AState
        $fxDir = Join-Path $PSScriptRoot (Join-Path 'tests' 'fixtures')
        # drive over the committed REAL fixtures
        $s.packetPath = Join-Path $fxDir 'routed_packet.json'
        $s.planPath = Join-Path $fxDir (Join-Path 'wave' 'plan.json')
        if (-not $s.repoRoot) {
            $rp = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $s.repoRoot = $rp.Path }
        }

        function Get-TreeSig { param([string]$Root)
            $acc = New-Object System.Collections.Generic.List[string]
            foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
                [void]$acc.Add($f.FullName + '|' + [string]$f.Length + '|' + $f.LastWriteTimeUtc.ToString('o'))
            }
            return ($acc.ToArray() -join "`n")
        }
        $sigBefore = Get-TreeSig -Root $fxDir

        $form.StartPosition = 'Manual'
        $form.Location = [System.Drawing.Point]::new(-4000, -4000)
        $form.ShowInTaskbar = $false
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-AttRefresh
        [System.Windows.Forms.Application]::DoEvents()

        $model = $s.model
        $modelOk = ($null -ne $model -and $model.ok -and $model.schema -eq 'lifeorch.context_packet/0.2' -and $model.packet_id -match '^cpkt_')
        $hdrText = [string]$s.headerBox.Text
        $headerOk = ($hdrText -match 'AUDIT TIMELINE \+ TOURNAMENT' -and $hdrText -match 'holds_lease=no')
        if ($modelOk -and $headerOk) { Write-Output 'SELFTEST_MODEL_OK' } else { Write-Output ("SELFTEST_MODEL_FAIL: model=$modelOk header=$headerOk") }

        # TOURNAMENT: brackets present + reconciled
        $tv = $s.tabs['tournament'].list; $tvText = ''
        for ($i = 0; $i -lt $tv.Items.Count; $i++) { $tvText += [string]$tv.Items[$i] + "`n" }
        $tourOk = ($null -ne $model.tournament -and $model.tournament.reconciled -and
            $tvText -match 'BRACKET A: ROUTER' -and $tvText -match 'classification' -and $tvText -match 'channel_selection' -and
            $tvText -match 'BRACKET B: SELECTION' -and $tvText -match 'raw_retrieval' -and
            $tvText -match 'BRACKET C: PLAN VALIDATION' -and $tvText -match 'OVERALL RECONCILED')
        if ($tourOk) { Write-Output 'SELFTEST_TOURNAMENT_OK' } else { Write-Output ("SELFTEST_TOURNAMENT_FAIL: reconciled=" + [string]$model.tournament.reconciled) }

        # TIMELINE: a real wave stitched end-to-end + cross-context events
        $tl = $s.tabs['timeline'].list; $tlText = ''
        for ($i = 0; $i -lt $tl.Items.Count; $i++) { $tlText += [string]$tl.Items[$i] + "`n" }
        $timeOk = ($null -ne $model.timeline -and $model.timeline.counts.total_events -ge 4 -and
            $tlText -match 'plan_created' -and $tlText -match 'report:done' -and $tlText -match 'episode:' -and
            $tlText -match 'working_memory:' -and $tlText -match 'BATONS:' -and
            $model.timeline.lease.holds -eq $false -and $model.timeline.lease.window_violations -eq 0)
        if ($timeOk) { Write-Output 'SELFTEST_TIMELINE_OK' } else { Write-Output ("SELFTEST_TIMELINE_FAIL: events=" + [string]$model.timeline.counts.total_events) }

        # SANITIZE: router trace channel-only + timeline events allowlisted
        $sanOk = ($null -ne $model.sanitize -and $model.sanitize.trace_sanitized -and $model.sanitize.timeline_sanitized)
        if ($sanOk) { Write-Output 'SELFTEST_SANITIZE_OK' } else { Write-Output ("SELFTEST_SANITIZE_FAIL: " + ($model.sanitize | ConvertTo-Json -Compress -Depth 4)) }

        # REFRESH re-reads without throwing
        Invoke-AttRefresh
        [System.Windows.Forms.Application]::DoEvents()
        if ($s.tabs['timeline'].list.Items.Count -ge 6) { Write-Output 'SELFTEST_REFRESH_OK' } else { Write-Output 'SELFTEST_REFRESH_FAIL' }

        # READ-ONLY: the fixtures tree is byte-identical; the write-guard rejects an outside-runtime target
        [System.Windows.Forms.Application]::DoEvents()
        $sigAfter = Get-TreeSig -Root $fxDir
        $fixturesUntouched = ($sigBefore -eq $sigAfter)
        $paths = Resolve-AuditPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
        $guardOk = $false
        try { [void](Assert-UnderRuntime -Target ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'att-evil.json')) -RuntimeDir $paths.RuntimeDir) } catch { $guardOk = $true }
        if ($fixturesUntouched -and $guardOk) { Write-Output 'SELFTEST_READONLY_OK' }
        else { Write-Output ("SELFTEST_READONLY_FAIL: fixturesUntouched=$fixturesUntouched guard=$guardOk") }

        # LAYOUT guard: Refresh + both Browse buttons sit FULLY inside the toolbar; boxes do not overrun.
        Update-AttToolbarLayout
        [System.Windows.Forms.Application]::DoEvents()
        $tbw = [int]$s.toolbar.ClientSize.Width
        $refR = [int]$s.refreshBtn.Bounds.Right
        $bpR = [int]$s.browsePacketBtn.Bounds.Right
        $pkR = [int]$s.packetBox.Bounds.Right
        $layoutOk = ($tbw -gt 0) -and ($refR -le $tbw) -and ($bpR -le $tbw) -and ($pkR -le $s.browsePacketBtn.Bounds.Left) -and [bool]$s.refreshBtn.Visible -and [bool]$s.browsePlanBtn.Visible
        if ($layoutOk) { Write-Output 'SELFTEST_LAYOUT_OK' }
        else { Write-Output ('SELFTEST_LAYOUT_FAIL: toolbarW=' + $tbw + ' refreshR=' + $refR + ' browsePacketR=' + $bpR + ' packetR=' + $pkR) }
    }
    catch { Write-Output ('SELFTEST_RENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
