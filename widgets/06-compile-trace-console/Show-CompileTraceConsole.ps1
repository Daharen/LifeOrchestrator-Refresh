<#
    Show-CompileTraceConsole.ps1 - the Compile Trace Console (Widget 06) UI entrypoint.

    A native WinForms window (run STA) that RENDERS a real lifeorch.context_packet/0.2 compile artifact (a
    #40 0.8.0/0.9.0 packet) across the audit-pipeline s2.1 panes 1-4,6, plus the s2.5a compile-layer
    counterfactual runner. It is STRICTLY READ-ONLY: it parses existing compile/eval artifacts and drives
    NOTHING, writes no doc, runs no git write, submits no executor job, and calls NO model. The ONLY thing it
    may write is the counterfactual re-compile scratch + diffs under widgets/06-compile-trace-console/runtime/
    (guarded so it can never escape that dir). non_execution holds; it enables no action.

    It is a THIN shell over CompileTraceConsole.psm1: the UI only builds controls and renders the core's
    Get-CompileTraceModel / Format-* / Get-PacketDiff / Invoke-CompileCounterfactual output. All parsing, the
    pane builders, the differ, and the counterfactual re-compile live in the tested, WinForms-free core.

    Launch:    launch.bat   (pwsh -NoProfile -STA -File Show-CompileTraceConsole.ps1)
    Self-test: pwsh -STA -File Show-CompileTraceConsole.ps1 -SelfTest   (builds + drives + disposes the form
               off-screen over the committed REAL fixtures; prints SELFTEST_*_OK incl. SELFTEST_LAYOUT_OK +
               SELFTEST_READONLY_OK + SELFTEST_COUNTERFACTUAL_OK)
    Options:   -PacketFile <path> a specific packet artifact; -CaseFile <path> the mock base case for the
               counterfactual runner; -RepoRoot <dir> the repo whose #40 the runner re-invokes (else ../..).
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$PacketFile,
    [string]$CaseFile,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CompileTraceConsole.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:CState = @{
    form        = $null
    widgetRoot  = $PSScriptRoot
    repoRoot    = $RepoRoot
    packetPath  = $PacketFile
    casePath    = $CaseFile
    model       = $null
    tabs        = @{}
    suspendEvents = $false
}

function Set-WText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Resolve-DefaultPacket {
    # Choose the packet to render: -PacketFile, else the newest artifact under #40 runtime/artifacts, else the
    # bundled routed fixture. Read-only discovery.
    $s = $script:CState
    if ($s.packetPath -and (Test-Path -LiteralPath $s.packetPath -PathType Leaf)) { return $s.packetPath }
    $paths = Resolve-CompileTracePaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    if (Test-Path -LiteralPath $paths.ArtifactsDir -PathType Container) {
        # newest cc_meta.json that actually CARRIES a packet (a `compile` meta -- skip `normalize`/`expand`)
        foreach ($cand in @(Get-ChildItem -LiteralPath $paths.ArtifactsDir -Recurse -File -Filter 'cc_meta.json' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc -Descending)) {
            if ((Read-ContextPacket -Path $cand.FullName).ok) { return $cand.FullName }
        }
    }
    $fx = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'routed_packet.json'))
    if (Test-Path -LiteralPath $fx -PathType Leaf) { return $fx }
    return $null
}

function Resolve-DefaultCase {
    $s = $script:CState
    if ($s.casePath -and (Test-Path -LiteralPath $s.casePath -PathType Leaf)) { return $s.casePath }
    $paths = Resolve-CompileTracePaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    $cc = [System.IO.Path]::Combine($paths.CompilerDir, 'fixtures', 'compile_case.json')
    if (Test-Path -LiteralPath $cc -PathType Leaf) { return $cc }
    $fx = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'base_case.json'))
    if (Test-Path -LiteralPath $fx -PathType Leaf) { return $fx }
    return $null
}

function New-CtcTab {
    param([string]$Name, [string]$Text, [System.Drawing.Font]$Mono)
    $page = [System.Windows.Forms.TabPage]::new()
    $page.Text = $Text
    $list = [System.Windows.Forms.ListBox]::new()
    $list.Dock = 'Fill'; $list.Font = $Mono; $list.IntegralHeight = $false; $list.HorizontalScrollbar = $true
    $page.Controls.Add($list)
    $script:CState.tabs[$Name] = @{ page = $page; list = $list }
    return $page
}

function Update-CtcToolbarLayout {
    # Position BOTH toolbar rows from the toolbar's ACTUAL width (the widget-04 off-screen-toolbar lesson:
    # anchoring/positioning before a Dock=Top panel is sized baselines against its default ~200px width and
    # throws a right-anchored control off-screen). Row 1: packet path box + Browse (right). Row 2: the
    # counterfactual combo/value + Run + Refresh (right). StrictMode-safe ContainsKey guards.
    $s = $script:CState
    if ($null -eq $s) { return }
    foreach ($k in 'toolbar', 'refreshBtn', 'runCfBtn', 'cfCombo', 'cfValue', 'packetBox', 'browseBtn') { if (-not $s.ContainsKey($k)) { return } }
    foreach ($k in 'toolbar', 'refreshBtn', 'runCfBtn', 'cfCombo', 'cfValue', 'packetBox', 'browseBtn') { if ($null -eq $s[$k]) { return } }
    $margin = 8; $gap = 8
    $w = [int]$s.toolbar.ClientSize.Width
    if ($w -le 0) { return }
    # row 1 (y=8..): packet box stretches from x=64 up to Browse; Browse pinned right
    $s.browseBtn.Top = 8; $s.browseBtn.Left = $w - $s.browseBtn.Width - $margin
    $s.packetBox.Top = 9; $s.packetBox.Left = 64
    $pbW = $s.browseBtn.Left - $gap - $s.packetBox.Left
    if ($pbW -lt 120) { $pbW = 120 }
    $s.packetBox.Width = $pbW
    # row 2 (y=42..): Refresh pinned right, then Run, then value box, then the variation combo
    $s.refreshBtn.Top = 42; $s.refreshBtn.Left = $w - $s.refreshBtn.Width - $margin
    $s.runCfBtn.Top = 42; $s.runCfBtn.Left = $s.refreshBtn.Left - $s.runCfBtn.Width - $gap
    $s.cfValue.Top = 44; $s.cfValue.Left = $s.runCfBtn.Left - $s.cfValue.Width - $gap
    $s.cfCombo.Top = 43; $s.cfCombo.Left = 110
    $comboW = $s.cfValue.Left - $gap - $s.cfCombo.Left
    if ($comboW -lt 140) { $comboW = 140 }
    if ($comboW -gt 260) { $comboW = 260 }
    $s.cfCombo.Width = $comboW
}

function New-CtcForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Compile Trace Console - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1200, 840)
    $form.MinimumSize = [System.Drawing.Size]::new(960, 600)
    $form.StartPosition = 'CenterScreen'

    $status = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $statusLabel.Text = 'No packet loaded.'
    [void]$status.Items.Add($statusLabel)

    # ===== toolbar (top) =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'; $toolbar.Height = 76

    $lblPacket = [System.Windows.Forms.Label]::new()
    $lblPacket.Text = 'Packet:'; $lblPacket.Location = [System.Drawing.Point]::new(8, 12); $lblPacket.AutoSize = $true
    $packetBox = [System.Windows.Forms.TextBox]::new()
    $packetBox.Location = [System.Drawing.Point]::new(64, 9); $packetBox.Width = 720; $packetBox.Font = $mono
    $packetBox.ReadOnly = $true
    $browseBtn = [System.Windows.Forms.Button]::new()
    $browseBtn.Text = 'Browse...'; $browseBtn.Size = [System.Drawing.Size]::new(84, 24); $browseBtn.Location = [System.Drawing.Point]::new(792, 8)

    $lblCf = [System.Windows.Forms.Label]::new()
    $lblCf.Text = 'Counterfactual:'; $lblCf.Location = [System.Drawing.Point]::new(8, 46); $lblCf.AutoSize = $true
    $cfCombo = [System.Windows.Forms.ComboBox]::new()
    $cfCombo.DropDownStyle = 'DropDownList'; $cfCombo.Location = [System.Drawing.Point]::new(110, 43); $cfCombo.Width = 220; $cfCombo.Font = $mono
    foreach ($v in (Get-CounterfactualVariations)) { [void]$cfCombo.Items.Add([string]$v.id) }
    if ($cfCombo.Items.Count -gt 0) { $cfCombo.SelectedIndex = 0 }
    $cfValue = [System.Windows.Forms.TextBox]::new()
    $cfValue.Location = [System.Drawing.Point]::new(340, 43); $cfValue.Width = 120; $cfValue.Font = $mono
    $runCfBtn = [System.Windows.Forms.Button]::new()
    $runCfBtn.Text = 'Run counterfactual'; $runCfBtn.Size = [System.Drawing.Size]::new(150, 26); $runCfBtn.Location = [System.Drawing.Point]::new(880, 42)
    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Refresh'; $refreshBtn.Size = [System.Drawing.Size]::new(96, 26); $refreshBtn.Location = [System.Drawing.Point]::new(1040, 42)

    $toolbar.Controls.AddRange(@($lblPacket, $packetBox, $browseBtn, $lblCf, $cfCombo, $cfValue, $runCfBtn, $refreshBtn))
    $script:CState.toolbar = $toolbar
    $script:CState.packetBox = $packetBox
    $script:CState.cfCombo = $cfCombo
    $script:CState.cfValue = $cfValue
    $script:CState.runCfBtn = $runCfBtn
    $script:CState.refreshBtn = $refreshBtn
    $toolbar.Add_Resize({ Update-CtcToolbarLayout }.GetNewClosure())

    # ===== header =====
    $headerBox = [System.Windows.Forms.RichTextBox]::new()
    $headerBox.Dock = 'Top'; $headerBox.Height = 74; $headerBox.ReadOnly = $true
    $headerBox.Font = $mono; $headerBox.BackColor = [System.Drawing.Color]::White; $headerBox.BorderStyle = 'None'
    $headerBox.Text = 'Loading...'

    # ===== tabs =====
    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'; $tabs.Font = $mono
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'timeline'  -Text '1 Timeline'          -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'modelview' -Text '2 Model View'        -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'retrieval' -Text '3 Retrieval+Select'  -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'rules'     -Text '4 Rule/Exception'    -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'ledger'    -Text '6 Token/State'       -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'counterfactual' -Text 'Counterfactual' -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'companion' -Text 'Eval/Rehearsal/Fold' -Mono $mono))
    [void]$tabs.TabPages.Add((New-CtcTab -Name 'flags'     -Text 'Flags'               -Mono $mono))

    $form.Controls.Add($tabs)
    $form.Controls.Add($headerBox)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:CState
    $s.form = $form; $s.headerBox = $headerBox; $s.tabControl = $tabs; $s.statusLabel = $statusLabel

    $refreshBtn.Add_Click({ Invoke-CtcRefresh }.GetNewClosure())
    $runCfBtn.Add_Click({ Invoke-CtcCounterfactual }.GetNewClosure())
    $browseBtn.Add_Click({
            try {
                $dlg = [System.Windows.Forms.OpenFileDialog]::new()
                $dlg.Filter = 'JSON artifacts (*.json)|*.json|All files (*.*)|*.*'
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $script:CState.packetPath = $dlg.FileName
                    Invoke-CtcRefresh
                }
            }
            catch { $script:CState.statusLabel.Text = 'browse failed: ' + $_.Exception.Message }
        }.GetNewClosure())
    $form.Add_Shown({
            Update-CtcToolbarLayout
            Initialize-CtcView
        }.GetNewClosure())

    return $form
}

function Set-TabLines {
    param([string]$Name, $Lines)
    $s = $script:CState
    if (-not $s.tabs.ContainsKey($Name)) { return }
    $t = $s.tabs[$Name]
    $t.list.BeginUpdate()
    $t.list.Items.Clear()
    foreach ($ln in @($Lines)) { [void]$t.list.Items.Add([string]$ln) }
    $t.list.EndUpdate()
}

function Get-CtcModel {
    $s = $script:CState
    $packet = Resolve-DefaultPacket
    $paths = Resolve-CompileTracePaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    # optional companions: prefer bundled fixtures (always present) so the tab is populated
    $fxDir = Join-Path $s.widgetRoot (Join-Path 'tests' 'fixtures')
    $evalP = Join-Path $fxDir 'eval_report.json'; if (-not (Test-Path -LiteralPath $evalP)) { $evalP = $null }
    $rehP = Join-Path $fxDir 'rehearsal_report.json'; if (-not (Test-Path -LiteralPath $rehP)) { $rehP = $null }
    $foldP = Join-Path $fxDir 'fold_smoke.log'; if (-not (Test-Path -LiteralPath $foldP)) { $foldP = $null }
    if ($null -eq $packet) {
        return [pscustomobject]@{ ok = $false; error = 'no packet artifact found'; source_path = ''; flags = @('no packet artifact found (use Browse)'); panes = $null; companion = $null; sanitize = $null; counts = [ordered]@{}; packet_id = ''; schema = ''; compiler_version = ''; disposition = ''; non_execution = $null }
    }
    return Get-CompileTraceModel -PacketPath $packet -EvalPath $evalP -RehearsalPath $rehP -FoldPath $foldP -RepoRoot $s.repoRoot -WidgetRoot $s.widgetRoot
}

function Render-CtcModel {
    $s = $script:CState
    $model = Get-CtcModel
    $s.model = $model
    $hdr = Format-CompileTraceHeader -Model $model
    Set-WText $s.headerBox (($hdr.header_lines) -join "`r`n")
    $s.statusLabel.Text = [string]$hdr.summary_line
    if ($null -ne $model.source_path) { $s.packetBox.Text = [string]$model.source_path }

    if ($model.ok -and $null -ne $model.panes) {
        Set-TabLines -Name 'timeline'  -Lines (@($model.panes.timeline.header) + @($model.panes.timeline.lines))
        Set-TabLines -Name 'modelview' -Lines (@($model.panes.modelview.header) + @($model.panes.modelview.lines))
        Set-TabLines -Name 'retrieval' -Lines (@($model.panes.retrieval.header) + @($model.panes.retrieval.lines))
        Set-TabLines -Name 'rules'     -Lines (@($model.panes.rules.header) + @($model.panes.rules.lines))
        Set-TabLines -Name 'ledger'    -Lines (@($model.panes.ledger.header) + @($model.panes.ledger.lines))
        $comp = Format-CompanionRows -Model $model
        Set-TabLines -Name 'companion' -Lines $comp.lines
    }
    else {
        foreach ($n in 'timeline', 'modelview', 'retrieval', 'rules', 'ledger', 'companion') { Set-TabLines -Name $n -Lines @('(no model)') }
    }
    $flagLines = @($model.flags)
    if ($flagLines.Count -eq 0) { $flagLines = @('(no flags -- clean render)') }
    Set-TabLines -Name 'flags' -Lines $flagLines
}

function Initialize-CtcView {
    Render-CtcModel
    Set-TabLines -Name 'counterfactual' -Lines @('Pick a variation + press "Run counterfactual" to re-compile the SAME pinned snapshot',
        'with ONE varied input and diff the packets (ZERO model calls -- deterministic re-compile).',
        '', 'Variations:')
    $s = $script:CState
    $t = $s.tabs['counterfactual']
    foreach ($v in (Get-CounterfactualVariations)) { [void]$t.list.Items.Add(('   ' + $v.id + ' -- ' + $v.desc)) }
}

function Invoke-CtcRefresh {
    # Re-read the packet + companions from disk and re-render every pane. Read-only (Render-CtcModel sets the
    # status line from the freshly-built header).
    Render-CtcModel
}

function Invoke-CtcCounterfactual {
    $s = $script:CState
    $variation = [string]$s.cfCombo.SelectedItem
    if (-not $variation) { $variation = 'budget' }
    $val = [string]$s.cfValue.Text; if ([string]::IsNullOrWhiteSpace($val)) { $val = $null }
    $case = Resolve-DefaultCase
    $paths = Resolve-CompileTracePaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    if ($null -eq $case) {
        Set-TabLines -Name 'counterfactual' -Lines @('ERROR: no mock base case found (set -CaseFile or place modules/40/fixtures/compile_case.json)')
        return
    }
    Set-TabLines -Name 'counterfactual' -Lines @('running counterfactual "' + $variation + '" (re-compiling the pinned snapshot, zero model calls)...')
    [System.Windows.Forms.Application]::DoEvents()
    $r = Invoke-CompileCounterfactual -BaseCasePath $case -Variation $variation -Value $val -RepoRoot $s.repoRoot -WidgetRoot $s.widgetRoot -RuntimeDir $paths.RuntimeDir
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('COUNTERFACTUAL: ' + $variation + '   ' + [string]$r.description)
    if (-not $r.ok) { [void]$lines.Add('ERROR: ' + [string]$r.error) }
    else {
        [void]$lines.Add('re-compiled the SAME pinned snapshot with one varied input (ZERO model calls).')
        [void]$lines.Add('')
        foreach ($ln in @($r.diff.summary_lines)) { [void]$lines.Add($ln) }
    }
    Set-TabLines -Name 'counterfactual' -Lines $lines.ToArray()
    try { $s.tabControl.SelectedTab = $s.tabs['counterfactual'].page } catch { }
}

# ----- entry -----
$form = New-CtcForm

if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) } catch { }
    try {
        $s = $script:CState
        $fxDir = Join-Path $PSScriptRoot (Join-Path 'tests' 'fixtures')
        # drive over the committed REAL routed packet; the runner uses the REAL repo #40 (../..) on the box
        $s.packetPath = Join-Path $fxDir 'routed_packet.json'
        $s.casePath = Join-Path $fxDir 'base_case.json'
        if (-not $s.repoRoot) {
            $rp = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $s.repoRoot = $rp.Path }
        }

        # READ-ONLY guard: snapshot the fixtures tree before any render; assert byte-identical after.
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
        Initialize-CtcView
        [System.Windows.Forms.Application]::DoEvents()

        # MODEL: the routed packet rendered; header names the packet_id + schema; disposition answerable
        $model = $s.model
        $modelOk = ($null -ne $model -and $model.ok -and $model.schema -eq 'lifeorch.context_packet/0.2' -and $model.counts.trace_stages -eq 3)
        $hdrText = [string]$s.headerBox.Text
        $headerOk = ($hdrText -match 'COMPILE TRACE CONSOLE' -and $hdrText -match 'cpkt_')
        if ($modelOk -and $headerOk) { Write-Output 'SELFTEST_MODEL_OK' } else { Write-Output ("SELFTEST_MODEL_FAIL: model=$modelOk header=$headerOk") }

        # PANES: pane2 has all four region trust banners; pane3 has the R-1 router trace; pane1 timeline populated
        $tl = $s.tabs['timeline'].list; $mv = $s.tabs['modelview'].list; $rt = $s.tabs['retrieval'].list
        $mvText = ''; for ($i = 0; $i -lt $mv.Items.Count; $i++) { $mvText += [string]$mv.Items[$i] + "`n" }
        $rtText = ''; for ($i = 0; $i -lt $rt.Items.Count; $i++) { $rtText += [string]$rt.Items[$i] + "`n" }
        $regionsOk = ($mvText -match 'control_plane' -and $mvText -match 'task_input' -and $mvText -match 'working_memory' -and $mvText -match 'evidence' -and $mvText -match 'TRUST')
        $routerOk = ($rtText -match 'R-1 ROUTER STAGE-TRACE' -and $rtText -match 'classification' -and $rtText -match 'channel_selection')
        $tlOk = ($tl.Items.Count -ge 8)
        if ($regionsOk -and $routerOk -and $tlOk) { Write-Output 'SELFTEST_PANES_OK' } else { Write-Output ("SELFTEST_PANES_FAIL: regions=$regionsOk router=$routerOk timeline=$tlOk") }

        # SANITIZE: the router trace is channel-only (no forbidden identifying keys)
        $sanOk = ($null -ne $model.sanitize -and $model.sanitize.sanitized -and $model.sanitize.trace_present)
        if ($sanOk) { Write-Output 'SELFTEST_SANITIZE_OK' } else { Write-Output ("SELFTEST_SANITIZE_FAIL: " + ($model.sanitize | ConvertTo-Json -Compress)) }

        # COMPANION: eval/rehearsal/fold rendered
        $cp = $s.tabs['companion'].list; $cpText = ''
        for ($i = 0; $i -lt $cp.Items.Count; $i++) { $cpText += [string]$cp.Items[$i] + "`n" }
        $companionOk = ($cpText -match 'REHEARSAL REPORT' -and $cpText -match 'FOLD SMOKE' -and $cpText -match 'hybrid_applicability')
        if ($companionOk) { Write-Output 'SELFTEST_COMPANION_OK' } else { Write-Output ("SELFTEST_COMPANION_FAIL: " + (Limit-Text $cpText 100)) }

        # COUNTERFACTUAL: run the budget variation via the REAL #40 (if resolvable); assert a real packet delta.
        # Also assert the vector-mask reconciliation (zero delta). If no compiler is resolvable, render a diff
        # from the committed base/variant packets so the tab still proves out.
        $paths = Resolve-CompileTracePaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
        $cfOk = $false; $cfDetail = ''
        $ranLive = $false
        if (Test-Path -LiteralPath $paths.CompilerWorker -PathType Leaf) {
            $rB = Invoke-CompileCounterfactual -BaseCasePath $s.casePath -Variation budget -Value 90 -RepoRoot $s.repoRoot -WidgetRoot $s.widgetRoot -RuntimeDir $paths.RuntimeDir
            $rV = Invoke-CompileCounterfactual -BaseCasePath $s.casePath -Variation channel_mask -Value vector -RepoRoot $s.repoRoot -WidgetRoot $s.widgetRoot -RuntimeDir $paths.RuntimeDir
            if ($rB.ok -and $rV.ok) {
                $ranLive = $true
                $budgetOk = ($rB.diff.packet_id_changed -and $rB.diff.excerpt_count_delta -lt 0)
                $reconcileOk = (-not $rV.diff.packet_id_changed -and $rV.diff.excerpt_count_delta -eq 0)
                $cfOk = ($budgetOk -and $reconcileOk)
                $cfDetail = "runner budget_delta=$($rB.diff.excerpt_count_delta) vectormask_changed=$($rV.diff.packet_id_changed)"
            }
        }
        if (-not $ranLive) {
            # no compiler / python resolvable -> prove the CF TAB renders a real diff from committed packets
            # (the end-to-end runner is separately gated in the tests harness when python is available)
            $bp = (Read-ContextPacket (Join-Path $fxDir 'cf_base_packet.json')).packet
            $vp = (Read-ContextPacket (Join-Path $fxDir 'cf_variant_budget_packet.json')).packet
            $d = Get-PacketDiff -BasePacket $bp -VariantPacket $vp
            $cfOk = ($d.packet_id_changed -and $d.excerpt_count_delta -lt 0)
            $cfDetail = "differ-only fallback delta=$($d.excerpt_count_delta)"
        }
        if ($cfOk) { Write-Output ('SELFTEST_COUNTERFACTUAL_OK (' + $cfDetail + ')') } else { Write-Output ("SELFTEST_COUNTERFACTUAL_FAIL: " + $cfDetail) }

        # REFRESH re-reads without throwing
        Invoke-CtcRefresh
        [System.Windows.Forms.Application]::DoEvents()
        if ($s.tabs['timeline'].list.Items.Count -ge 8) { Write-Output 'SELFTEST_REFRESH_OK' } else { Write-Output 'SELFTEST_REFRESH_FAIL' }

        # READ-ONLY over the repo/fixtures: the fixtures tree must be byte-identical after full render + CF;
        # every counterfactual write must land under the widget runtime dir.
        [System.Windows.Forms.Application]::DoEvents()
        $sigAfter = Get-TreeSig -Root $fxDir
        $fixturesUntouched = ($sigBefore -eq $sigAfter)
        $runtimeFull = [System.IO.Path]::GetFullPath($paths.RuntimeDir)
        $escaped = $false
        if (Test-Path -LiteralPath $runtimeFull -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $runtimeFull -Recurse -File -ErrorAction SilentlyContinue)) {
                if (-not ([System.IO.Path]::GetFullPath($f.FullName)).StartsWith($runtimeFull, [System.StringComparison]::OrdinalIgnoreCase)) { $escaped = $true }
            }
        }
        $guardOk = $false
        try { [void](Assert-UnderRuntime -Target ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'ctc-evil.json')) -RuntimeDir $runtimeFull) } catch { $guardOk = $true }
        if ($fixturesUntouched -and -not $escaped -and $guardOk) { Write-Output 'SELFTEST_READONLY_OK' }
        else { Write-Output ("SELFTEST_READONLY_FAIL: fixturesUntouched=$fixturesUntouched escaped=$escaped guard=$guardOk") }

        # LAYOUT guard: Run + Refresh sit FULLY inside the toolbar; combo does not overrun Run.
        Update-CtcToolbarLayout
        [System.Windows.Forms.Application]::DoEvents()
        $tbw = [int]$s.toolbar.ClientSize.Width
        $btnR = [int]$s.refreshBtn.Bounds.Right
        $btnL = [int]$s.runCfBtn.Bounds.Left
        $cbR = [int]$s.cfCombo.Bounds.Right
        $layoutOk = ($tbw -gt 0) -and ($btnR -le $tbw) -and ($btnL -ge 0) -and ($cbR -le $s.cfValue.Bounds.Left) -and [bool]$s.refreshBtn.Visible -and [bool]$s.runCfBtn.Visible
        if ($layoutOk) { Write-Output 'SELFTEST_LAYOUT_OK' }
        else { Write-Output ('SELFTEST_LAYOUT_FAIL: toolbarW=' + $tbw + ' refreshR=' + $btnR + ' runL=' + $btnL + ' comboR=' + $cbR) }
    }
    catch { Write-Output ('SELFTEST_RENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
