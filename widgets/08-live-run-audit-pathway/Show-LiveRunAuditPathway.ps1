<#
    Show-LiveRunAuditPathway.ps1 - the Live-Run Audit Pathway (Widget 08) UI entrypoint.

    A native WinForms window (run STA) that RENDERS a REPLAYED #40 lifeorch.context_packet/0.2 compile as ONE
    chronological, plain-language, INTENT-vs-actual pathway (the audit program's phenomenological top surface,
    D-0120 / AUDIT_PIPELINE.md P9). It is STRICTLY READ-ONLY: it parses an existing compile artifact and drives
    NOTHING -- no model, no lease, no pause point, no git/doc write, no executor job, no re-compile. The ONLY
    thing it may write is under widgets/08-live-run-audit-pathway/runtime/ (guarded; the render path writes
    nothing). non_execution holds; it enables no action.

    It is a THIN shell over LiveRunAuditPathway.psm1 (the WinForms-free, cloud-testable driver core) which in
    turn reuses Widgets 06/07's public readers ONLY through the pinned LrapReaderAdapter.psm1 (the recompute
    entrypoints are excluded). The UI builds controls and renders the core's Get-LrapModel output: the six-step
    spine, the four lanes per step, the honesty-map P2 lanes, and the collapsed RECONCILE marker (the naming
    prose stays COLLAPSED until "Show why", per red-team F5; the raw 06/07 expert pane is reachable ONLY via
    "Show raw trace", per F7).

    Launch:    launch.bat   (pwsh -NoProfile -STA -File Show-LiveRunAuditPathway.ps1)
    Self-test: pwsh -STA -File Show-LiveRunAuditPathway.ps1 -SelfTest   (builds + drives + disposes the form
               off-screen over the committed REAL fixtures; prints SELFTEST_*_OK incl. SELFTEST_RECONCILE_OK,
               SELFTEST_DESCEND_OK, SELFTEST_READONLY_OK, SELFTEST_LAYOUT_OK)
    Options:   -PacketFile <path> a specific #40 artifact; -RepoRoot <dir> the repo whose #40 artifacts the
               default resolver scans (else ../..).
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$PacketFile,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LiveRunAuditPathway.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'LrapPoser.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:LState = @{
    form         = $null
    widgetRoot   = $PSScriptRoot
    repoRoot     = $RepoRoot
    packetPath   = $PacketFile
    model        = $null
    selectedStep = 1
    showWhy      = $false
    showRaw      = $false
    suspend      = $false
    lastError    = ''
    poser        = $null       # the modeless "?" pop-up chat state (built on first Ask)
    poserSync    = $false      # -SelfTest: run the worker synchronously (with a mock gateway) instead of detached
    poserGateway = ''          # -SelfTest: mock-gateway path handed to the worker (empty => the real #7 gateway)
}

# Event handlers are dedicated NAMED functions (the handler scriptblocks just call them, so no local-scope or
# scriptblock-passing fragility) and each is FAIL-SOFT: any throw is recorded (lastError) + surfaced to the
# status bar instead of raising an unhandled WinForms dialog. The SelfTest PerformClicks each one and asserts
# lastError stays empty, so an interaction-layer defect fails the -Live gate rather than only hitting the user.
function Set-LrapError { param([string]$Msg) $script:LState.lastError = $Msg; try { $script:LState.statusLabel.Text = 'error: ' + $Msg } catch { } }

function On-LrapRefresh { try { Invoke-LrapRefresh; $script:LState.lastError = '' } catch { Set-LrapError $_.Exception.Message } }
function On-LrapWhy { try { $script:LState.showWhy = -not $script:LState.showWhy; Render-LrapDetail; $script:LState.lastError = '' } catch { Set-LrapError $_.Exception.Message } }
function On-LrapRaw { try { $script:LState.showRaw = -not $script:LState.showRaw; Render-LrapDetail; $script:LState.lastError = '' } catch { Set-LrapError $_.Exception.Message } }
function On-LrapSelect {
    try {
        if ($script:LState.suspend) { return }
        $idx = $script:LState.spineList.SelectedIndex
        $tag = $null
        if ($idx -ge 0 -and $idx -lt $script:LState.spineIndex.Count) { $tag = $script:LState.spineIndex[$idx] }
        if ($null -ne $tag) { $script:LState.selectedStep = $tag; $script:LState.showWhy = $false; $script:LState.showRaw = $false; Render-LrapDetail }
        $script:LState.lastError = ''
    }
    catch { Set-LrapError $_.Exception.Message }
}
function On-LrapBrowse {
    try {
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Filter = 'JSON artifacts (*.json)|*.json|All files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:LState.packetPath = $dlg.FileName; Invoke-LrapRefresh }
        $script:LState.lastError = ''
    }
    catch { Set-LrapError $_.Exception.Message }
}
function On-LrapAsk {
    # Open the "?" pop-up seeded on the CURRENTLY SELECTED step (the operator can re-target any element in the
    # pop-up's dropdown). Fail-soft like every other handler.
    try {
        $sel = $script:LState.selectedStep
        $elementId = if ($sel -is [int] -or ($sel -match '^\d+$')) { 'step:' + [int]$sel } else { 'header' }
        Open-LrapPoserPopup -ElementId $elementId
        $script:LState.lastError = ''
    }
    catch { Set-LrapError $_.Exception.Message }
}

function Resolve-DefaultPacket {
    # -PacketFile, else the newest #40 artifact that carries a packet, else the bundled clean fixture
    # (the widget-06 resolution order; design s6). Read-only discovery.
    $s = $script:LState
    if ($s.packetPath -and (Test-Path -LiteralPath $s.packetPath -PathType Leaf)) { return $s.packetPath }
    $paths = Resolve-LrapPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
    if (Test-Path -LiteralPath $paths.ArtifactsDir -PathType Container) {
        foreach ($cand in @(Get-ChildItem -LiteralPath $paths.ArtifactsDir -Recurse -File -Filter 'cc_meta.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
            if ((Read-LrapModelSafe $cand.FullName).ok) { return $cand.FullName }
        }
    }
    $fx = Join-Path $s.widgetRoot (Join-Path 'tests' (Join-Path 'fixtures' 'clean_routed.json'))
    if (Test-Path -LiteralPath $fx -PathType Leaf) { return $fx }
    return $null
}

function Read-LrapModelSafe {
    param([string]$Path)
    try { return Get-LrapModel -PacketPath $Path } catch { return [pscustomobject]@{ ok = $false; error = $_.Exception.Message } }
}

function Update-LrapToolbarLayout {
    # Position the toolbar children from the toolbar's ACTUAL width (the widget-04 off-screen-toolbar lesson):
    # anchoring before a Dock=Top panel is sized baselines against its default ~200px width and throws a
    # right-anchored control off-screen. StrictMode-safe ContainsKey guards.
    $s = $script:LState
    if ($null -eq $s) { return }
    foreach ($k in 'toolbar', 'packetBox', 'browseBtn', 'refreshBtn') { if (-not $s.ContainsKey($k)) { return } }
    foreach ($k in 'toolbar', 'packetBox', 'browseBtn', 'refreshBtn') { if ($null -eq $s[$k]) { return } }
    $margin = 8; $gap = 8
    $w = [int]$s.toolbar.ClientSize.Width
    if ($w -le 0) { return }
    $s.refreshBtn.Top = 8; $s.refreshBtn.Left = $w - $s.refreshBtn.Width - $margin
    $s.browseBtn.Top = 8; $s.browseBtn.Left = $s.refreshBtn.Left - $s.browseBtn.Width - $gap
    $s.packetBox.Top = 9; $s.packetBox.Left = 64
    $pbW = $s.browseBtn.Left - $gap - $s.packetBox.Left
    if ($pbW -lt 120) { $pbW = 120 }
    $s.packetBox.Width = $pbW
}

function New-LrapForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Live-Run Audit Pathway - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1240, 860)
    $form.MinimumSize = [System.Drawing.Size]::new(980, 620)
    $form.StartPosition = 'CenterScreen'

    $status = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $statusLabel.Text = 'No packet loaded.'
    [void]$status.Items.Add($statusLabel)

    # ===== toolbar (top) =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'; $toolbar.Height = 44
    $lblPacket = [System.Windows.Forms.Label]::new()
    $lblPacket.Text = 'Packet:'; $lblPacket.Location = [System.Drawing.Point]::new(8, 12); $lblPacket.AutoSize = $true
    $packetBox = [System.Windows.Forms.TextBox]::new()
    $packetBox.Location = [System.Drawing.Point]::new(64, 9); $packetBox.Width = 760; $packetBox.Font = $mono; $packetBox.ReadOnly = $true
    $browseBtn = [System.Windows.Forms.Button]::new()
    $browseBtn.Text = 'Browse...'; $browseBtn.Size = [System.Drawing.Size]::new(84, 24); $browseBtn.Location = [System.Drawing.Point]::new(900, 8)
    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Reload'; $refreshBtn.Size = [System.Drawing.Size]::new(90, 24); $refreshBtn.Location = [System.Drawing.Point]::new(1000, 8)
    $toolbar.Controls.AddRange(@($lblPacket, $packetBox, $browseBtn, $refreshBtn))
    $toolbar.Add_Resize({ Update-LrapToolbarLayout }.GetNewClosure())

    # ===== header =====
    $headerBox = [System.Windows.Forms.RichTextBox]::new()
    $headerBox.Dock = 'Top'; $headerBox.Height = 116; $headerBox.ReadOnly = $true; $headerBox.WordWrap = $true
    $headerBox.Font = $mono; $headerBox.BackColor = [System.Drawing.Color]::White; $headerBox.BorderStyle = 'None'
    $headerBox.Text = 'Loading...'

    # ===== split: left = the six-step spine; right = the selected step's four lanes =====
    $split = [System.Windows.Forms.SplitContainer]::new()
    $split.Dock = 'Fill'; $split.Orientation = 'Vertical'
    # NB: SplitterDistance is set in Add_Shown (below), AFTER the container is sized -- setting it at
    # construction (when Panel1 is still the default ~150px wide) throws InvalidOperationException.

    $spineList = [System.Windows.Forms.ListBox]::new()
    $spineList.Dock = 'Fill'; $spineList.Font = $mono; $spineList.IntegralHeight = $false; $spineList.HorizontalScrollbar = $true
    $spineHint = [System.Windows.Forms.Label]::new()
    $spineHint.Dock = 'Top'; $spineHint.Height = 22; $spineHint.TextAlign = 'MiddleLeft'
    $spineHint.Text = ' THE RUN, STEP BY STEP -- click a step to inspect its four lanes:'
    $spineHint.Font = [System.Drawing.Font]::new('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $split.Panel1.Controls.Add($spineList)
    $split.Panel1.Controls.Add($spineHint)

    $rightTop = [System.Windows.Forms.Panel]::new()
    $rightTop.Dock = 'Top'; $rightTop.Height = 34
    $whyBtn = [System.Windows.Forms.Button]::new()
    $whyBtn.Text = 'Show why (reconcile detail)'; $whyBtn.Size = [System.Drawing.Size]::new(210, 26); $whyBtn.Location = [System.Drawing.Point]::new(6, 4)
    $rawBtn = [System.Windows.Forms.Button]::new()
    $rawBtn.Text = 'Show raw trace'; $rawBtn.Size = [System.Drawing.Size]::new(140, 26); $rawBtn.Location = [System.Drawing.Point]::new(224, 4)
    $askBtn = [System.Windows.Forms.Button]::new()
    $askBtn.Text = 'Ask (local 9B)  ?'; $askBtn.Size = [System.Drawing.Size]::new(160, 26); $askBtn.Location = [System.Drawing.Point]::new(372, 4)
    $rightTop.Controls.AddRange(@($whyBtn, $rawBtn, $askBtn))
    $detailList = [System.Windows.Forms.ListBox]::new()
    $detailList.Dock = 'Fill'; $detailList.Font = $mono; $detailList.IntegralHeight = $false; $detailList.HorizontalScrollbar = $true
    $split.Panel2.Controls.Add($detailList)
    $split.Panel2.Controls.Add($rightTop)

    $form.Controls.Add($split)
    $form.Controls.Add($headerBox)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:LState
    $s.form = $form; $s.toolbar = $toolbar; $s.packetBox = $packetBox; $s.browseBtn = $browseBtn; $s.refreshBtn = $refreshBtn
    $s.headerBox = $headerBox; $s.spineList = $spineList; $s.detailList = $detailList; $s.statusLabel = $statusLabel
    $s.whyBtn = $whyBtn; $s.rawBtn = $rawBtn; $s.askBtn = $askBtn; $s.split = $split

    $refreshBtn.Add_Click({ On-LrapRefresh }.GetNewClosure())
    $whyBtn.Add_Click({ On-LrapWhy }.GetNewClosure())
    $rawBtn.Add_Click({ On-LrapRaw }.GetNewClosure())
    $askBtn.Add_Click({ On-LrapAsk }.GetNewClosure())
    $spineList.Add_SelectedIndexChanged({ On-LrapSelect }.GetNewClosure())
    $browseBtn.Add_Click({ On-LrapBrowse }.GetNewClosure())
    $form.Add_Shown({
            Update-LrapToolbarLayout
            try { $sp = $script:LState.split; $w = [int]$sp.Width; if ($w -gt 220) { $sp.SplitterDistance = [int]([Math]::Min(460, [Math]::Max(200, [int]($w * 0.36)))) } } catch { }
            Initialize-LrapView
        }.GetNewClosure())
    return $form
}

function Set-ListLines { param($List, $Lines) $List.BeginUpdate(); $List.Items.Clear(); foreach ($ln in @($Lines)) { [void]$List.Items.Add([string]$ln) }; $List.EndUpdate() }

function Render-LrapSpine {
    # The left spine: one line per step with its NEUTRAL reconcile marker (prose collapsed). Two trailing
    # entries for the P2 backlog + the intent-catalog review, kept in the same pathway.
    $s = $script:LState
    $m = $s.model
    $lines = New-Object System.Collections.Generic.List[string]
    $index = New-Object System.Collections.Generic.List[object]
    if ($null -eq $m -or -not $m.ok) {
        Set-ListLines $s.spineList @('(no model)')
        $s.spineIndex = @($null)
        return
    }
    foreach ($st in @($m.steps)) {
        $mk = [string]$st.reconcile.marker
        [void]$lines.Add(('{0}. {1,-26} [{2}]' -f $st.step_no, $st.title, $mk))
        [void]$index.Add([int]$st.step_no)
    }
    [void]$lines.Add('')
    [void]$lines.Add('--- P2 backlog (not-emitted-yet lanes; a build output) ---')
    [void]$index.Add($null); [void]$index.Add('p2')
    [void]$lines.Add('--- Intent catalog + review ---')
    [void]$index.Add('intent')
    Set-ListLines $s.spineList $lines.ToArray()
    $s.spineIndex = $index.ToArray()
}

function Render-LrapDetail {
    $s = $script:LState
    $m = $s.model
    if ($null -eq $m -or -not $m.ok) { Set-ListLines $s.detailList @('(no model)'); return }
    $sel = $s.selectedStep
    $lines = New-Object System.Collections.Generic.List[string]

    if ($sel -eq 'p2') {
        [void]$lines.Add('P2 BACKLOG -- lanes no existing artifact can emit yet (rendered visibly; never faked):')
        [void]$lines.Add('')
        foreach ($g in @($m.p2_backlog)) { [void]$lines.Add(('[' + $g.id + '] step ' + $g.step_no + ' ' + $g.lane + ' (' + $g.kind + ')')); [void]$lines.Add('    ' + $g.text) }
        Set-ListLines $s.detailList $lines.ToArray(); return
    }
    if ($sel -eq 'intent') {
        $r = $m.intent_review
        [void]$lines.Add('INTENT CATALOG + REVIEW (the yardstick every RECONCILE is judged against; s3b own-gate)')
        [void]$lines.Add('reviewed=' + $r.reviewed + '  all_cited=' + $r.all_cited + '  blocks=' + $r.block_count)
        [void]$lines.Add('reviewer: ' + $r.reviewer)
        [void]$lines.Add('')
        foreach ($b in @(Get-LrapIntentCatalog)) {
            [void]$lines.Add(('step ' + $b.step_no + ' ' + $b.title))
            [void]$lines.Add('   intent : ' + $b.intent)
            [void]$lines.Add('   clause : ' + $b.contract_clause + '  [' + $b.contract_version + ']')
        }
        Set-ListLines $s.detailList $lines.ToArray(); return
    }

    $step = $null
    foreach ($st in @($m.steps)) { if ($st.step_no -eq [int]$sel) { $step = $st; break } }
    if ($null -eq $step) { Set-ListLines $s.detailList @('(select a step)'); return }

    [void]$lines.Add(('STEP ' + $step.step_no + ' -- ' + $step.title + '   (' + $step.step_key + ')'))
    [void]$lines.Add('')
    [void]$lines.Add('INTENT   [' + $step.intent.class + '] (what this step is SUPPOSED to do)')
    [void]$lines.Add('   ' + $step.intent.text)
    [void]$lines.Add('   contract: ' + $step.intent.contract_clause + '  [' + $step.intent.contract_version + ']')
    [void]$lines.Add('')
    [void]$lines.Add('INPUT    [' + $step.input.class + '] (its actual input)')
    foreach ($l in @($step.input.lines)) { [void]$lines.Add('   ' + $l) }
    [void]$lines.Add('')
    [void]$lines.Add('OUTPUT   [' + $step.output.class + '] (its actual output)')
    foreach ($l in @($step.output.lines)) { [void]$lines.Add('   ' + $l) }
    [void]$lines.Add('')
    [void]$lines.Add('RECONCILE [' + $step.reconcile.lane_class + ']: ' + $step.reconcile.marker)
    if ($s.showWhy) {
        [void]$lines.Add('   -- why (collapsed by default) --')
        foreach ($l in @($step.reconcile.descend_prose)) { [void]$lines.Add('   ' + $l) }
        foreach ($n in @($step.reconcile.p2_notes)) { [void]$lines.Add('   P2: ' + $n) }
    }
    else { [void]$lines.Add('   (press "Show why" for the plain-language detail)') }
    if ($s.showRaw) {
        [void]$lines.Add('')
        $raw = Get-LrapRawTraceForStep -Packet $m.packet -StepNo ([int]$sel)
        [void]$lines.Add($raw.header)
        foreach ($l in @($raw.lines)) { [void]$lines.Add('   ' + $l) }
    }
    Set-ListLines $s.detailList $lines.ToArray()
    $s.whyBtn.Text = if ($s.showWhy) { 'Hide why' } else { 'Show why (reconcile detail)' }
    $s.rawBtn.Text = if ($s.showRaw) { 'Hide raw trace' } else { 'Show raw trace' }
}

function Render-LrapModel {
    $s = $script:LState
    $packet = Resolve-DefaultPacket
    if ($null -eq $packet) {
        $s.model = [pscustomobject]@{ ok = $false; error = 'no packet artifact found (use Browse)' }
        $s.headerBox.Text = 'LIVE-RUN AUDIT PATHWAY -- no packet artifact found (use Browse).'
        Render-LrapSpine; Render-LrapDetail
        return
    }
    $s.model = Get-LrapModel -PacketPath $packet
    $hdr = Format-LrapHeader -Model $s.model
    $s.headerBox.Text = (($hdr.header_lines) -join "`r`n")
    $s.statusLabel.Text = [string]$hdr.summary_line
    $s.packetBox.Text = [string]$s.model.source_path
    $s.suspend = $true
    Render-LrapSpine
    # default selection: the inconsistent step if any, else step 1. Highlight the row (so the spine visibly
    # reads as a selector) while suspended, then render its detail once.
    $target = 1
    if ($s.model.ok -and $s.model.overall.inconsistent_step -gt 0) { $target = $s.model.overall.inconsistent_step }
    try { $s.spineList.SelectedIndex = ($target - 1) } catch { }
    $s.suspend = $false
    $s.selectedStep = $target; $s.showWhy = $false; $s.showRaw = $false
    Render-LrapDetail
}

function Initialize-LrapView { Render-LrapModel }
function Invoke-LrapRefresh { Render-LrapModel }

# ============================================================================
#  the interpretability POSER "?" pop-up (D-0126) -- a modeless chat seeded with the selected element's
#  context bundle. The widget stays READ-ONLY: it only writes request/answer files under runtime\poser\ (guarded
#  by LrapPoser) and SPAWNS the query worker DETACHED, so this UI process never calls a model or holds a lease.
#  Fail-silent: a worker that never answers times out to "explanation unavailable"; the main window is unaffected.
# ============================================================================

function Get-LrapPoserRuntimeDir {
    $p = Resolve-LrapPaths -WidgetRoot $script:LState.widgetRoot -RepoRoot $script:LState.repoRoot
    return $p.RuntimeDir
}

function Append-LrapPoserConvo {
    param([string]$Role, [string]$Text)
    $c = $script:LState.poser.convo
    $prefix = switch ($Role) { 'you' { '>> you:  ' } 'model' { '-- local 9B:  ' } default { '   ' } }
    $c.AppendText($prefix + $Text + "`r`n`r`n")
    $c.SelectionStart = $c.TextLength; $c.ScrollToCaret()
}

function Build-LrapPoserPopup {
    $s = $script:LState
    if ($null -ne $s.poser -and $null -ne $s.poser.form -and -not $s.poser.form.IsDisposed) { return }
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)
    $f = [System.Windows.Forms.Form]::new()
    $f.Text = 'Ask the local 9B about this element  (advisory -- it explains, you judge)'
    $f.Size = [System.Drawing.Size]::new(780, 600)
    $f.MinimumSize = [System.Drawing.Size]::new(520, 360)
    $f.StartPosition = 'CenterParent'

    $top = [System.Windows.Forms.Panel]::new(); $top.Dock = 'Top'; $top.Height = 34
    $lbl = [System.Windows.Forms.Label]::new(); $lbl.Text = 'Element:'; $lbl.Location = [System.Drawing.Point]::new(8, 9); $lbl.AutoSize = $true
    $combo = [System.Windows.Forms.ComboBox]::new(); $combo.DropDownStyle = 'DropDownList'
    $combo.Location = [System.Drawing.Point]::new(70, 6); $combo.Width = 680; $combo.Font = $mono; $combo.Anchor = 'Top,Left,Right'
    $top.Controls.AddRange(@($lbl, $combo))

    $bottom = [System.Windows.Forms.Panel]::new(); $bottom.Dock = 'Bottom'; $bottom.Height = 74
    $input = [System.Windows.Forms.TextBox]::new(); $input.Location = [System.Drawing.Point]::new(8, 8); $input.Width = 636; $input.Font = $mono; $input.Anchor = 'Top,Left,Right'
    $sendBtn = [System.Windows.Forms.Button]::new(); $sendBtn.Text = 'Ask'; $sendBtn.Size = [System.Drawing.Size]::new(108, 26); $sendBtn.Location = [System.Drawing.Point]::new(652, 7); $sendBtn.Anchor = 'Top,Right'
    $statusLabel = [System.Windows.Forms.Label]::new(); $statusLabel.Location = [System.Drawing.Point]::new(8, 42); $statusLabel.AutoSize = $true
    $statusLabel.Text = 'The local 9B explains this element from the audit surface only. It is advisory -- you make the call.'
    $bottom.Controls.AddRange(@($input, $sendBtn, $statusLabel))

    $convo = [System.Windows.Forms.RichTextBox]::new(); $convo.Dock = 'Fill'; $convo.ReadOnly = $true; $convo.WordWrap = $true
    $convo.Font = $mono; $convo.BackColor = [System.Drawing.Color]::White

    $f.Controls.Add($convo); $f.Controls.Add($top); $f.Controls.Add($bottom)
    $f.AcceptButton = $sendBtn

    $timer = [System.Windows.Forms.Timer]::new(); $timer.Interval = 600

    $s.poser = @{
        form = $f; combo = $combo; convo = $convo; input = $input; sendBtn = $sendBtn; statusLabel = $statusLabel; timer = $timer
        elements = @(); elementIds = @(); modelTurns = @(); runtimeDir = ''
        pendingReqId = ''; pendingAnswer = ''; pendingQ = ''; deadlineTicks = [long]0; seq = 0; suspendCombo = $false
    }

    $combo.Add_SelectedIndexChanged({ On-LrapPoserElementChanged }.GetNewClosure())
    $sendBtn.Add_Click({ On-LrapPoserSend }.GetNewClosure())
    $timer.Add_Tick({ On-LrapPoserTick }.GetNewClosure())
    $f.Add_FormClosing({ param($sender, $e) try { $e.Cancel = $true; $script:LState.poser.timer.Stop(); $sender.Hide() } catch { } }.GetNewClosure())
}

function Set-LrapPoserComboElements {
    $s = $script:LState; $p = $s.poser
    $els = @(Get-LrapPoserElements -Model $s.model)
    $p.elements = $els
    $p.elementIds = @($els | ForEach-Object { [string]$_.element_id })
    $p.suspendCombo = $true
    $p.combo.Items.Clear()
    foreach ($e in $els) { [void]$p.combo.Items.Add([string]$e.label) }
    $p.suspendCombo = $false
}

function Open-LrapPoserPopup {
    param([string]$ElementId)
    $s = $script:LState
    if ($null -eq $s.model -or -not $s.model.ok) { Set-LrapError 'no run loaded to ask about'; return }
    Build-LrapPoserPopup
    $p = $s.poser
    $p.runtimeDir = Get-LrapPoserRuntimeDir
    Set-LrapPoserComboElements
    $idx = [array]::IndexOf($p.elementIds, $ElementId); if ($idx -lt 0) { $idx = 0 }
    $p.suspendCombo = $true; $p.combo.SelectedIndex = $idx; $p.suspendCombo = $false
    $p.convo.Clear(); $p.modelTurns = @()
    try { [void]$p.form.Show($s.form) } catch { [void]$p.form.Show() }
    $p.form.BringToFront()
    Invoke-LrapPoserAsk -Question ''
}

function On-LrapPoserElementChanged {
    try {
        $p = $script:LState.poser
        if ($null -eq $p -or $p.suspendCombo) { return }
        $p.convo.Clear(); $p.modelTurns = @()
        Invoke-LrapPoserAsk -Question ''
    }
    catch { try { $script:LState.poser.statusLabel.Text = 'error: ' + $_.Exception.Message } catch { } }
}

function On-LrapPoserSend {
    try {
        $p = $script:LState.poser
        $q = [string]$p.input.Text
        if ([string]::IsNullOrWhiteSpace($q)) { return }
        $p.input.Clear()
        Invoke-LrapPoserAsk -Question $q
    }
    catch { try { $script:LState.poser.statusLabel.Text = 'error: ' + $_.Exception.Message } catch { } }
}

function Launch-LrapPoserWorker {
    param([string]$RequestPath)
    $s = $script:LState
    $worker = Join-Path $s.widgetRoot 'Invoke-LrapPoserQuery.ps1'
    $pwsh = (Get-Process -Id $PID).Path; if ([string]::IsNullOrWhiteSpace($pwsh)) { $pwsh = 'pwsh' }
    if ($s.poserSync) {
        $a = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $worker, '-RequestPath', $RequestPath, '-PwshPath', $pwsh)
        if ($s.poserGateway) { $a += @('-GatewayPath', $s.poserGateway) }
        & $pwsh @a | Out-Null
    }
    else {
        $a = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $worker, '-RequestPath', $RequestPath)
        [void](Start-Process -FilePath $pwsh -ArgumentList $a -WindowStyle Hidden)
    }
}

function Invoke-LrapPoserAsk {
    param([string]$Question)
    $s = $script:LState; $p = $s.poser
    $eid = if ($p.combo.SelectedIndex -ge 0 -and $p.combo.SelectedIndex -lt $p.elementIds.Count) { [string]$p.elementIds[$p.combo.SelectedIndex] } else { 'header' }
    $bundle = Get-LrapPoserBundle -Model $s.model -ElementId $eid
    if ([string]::IsNullOrWhiteSpace($Question)) { Append-LrapPoserConvo 'you' '(explain this element)' } else { Append-LrapPoserConvo 'you' $Question }
    $p.seq++
    $reqId = 'ui-' + [string]$p.seq + '-' + $eid.Replace(':', '_')
    $req = New-LrapPoserRequest -RuntimeDir $p.runtimeDir -Bundle $bundle -Question $Question -PriorTurns $p.modelTurns -RequestId $reqId
    $p.pendingReqId = $reqId; $p.pendingAnswer = $req.answer_path
    $p.pendingQ = if ([string]::IsNullOrWhiteSpace($Question)) { 'Explain this element: what is it, and what did the agent actually do here?' } else { $Question }
    $p.deadlineTicks = [long]([System.DateTime]::UtcNow.AddSeconds(180).Ticks)
    $p.sendBtn.Enabled = $false
    $p.statusLabel.Text = 'asking the local 9B... (a cold model can take ~1-2 min; the window stays usable)'
    Launch-LrapPoserWorker -RequestPath $req.request_path
    $p.timer.Start()
}

function On-LrapPoserTick {
    try {
        $p = $script:LState.poser
        if ($null -eq $p -or [string]::IsNullOrEmpty($p.pendingAnswer)) { if ($null -ne $p) { $p.timer.Stop() }; return }
        $ans = Read-LrapPoserAnswer -AnswerPath $p.pendingAnswer
        if ($null -ne $ans) {
            $p.timer.Stop()
            if ($ans.ok) {
                Append-LrapPoserConvo 'model' ([string]$ans.text)
                $p.modelTurns = @($p.modelTurns) + @(
                    [pscustomobject]@{ role = 'user'; content = [string]$p.pendingQ },
                    [pscustomobject]@{ role = 'assistant'; content = [string]$ans.text })
                $p.statusLabel.Text = 'answered -- advisory, you judge. Ask a follow-up, or pick another element.'
            }
            else {
                Append-LrapPoserConvo 'model' ('[explanation unavailable: ' + [string]$ans.error + ']')
                $p.statusLabel.Text = 'explanation unavailable (the local model returned nothing usable). You can still open the raw trace.'
            }
            $p.pendingAnswer = ''; $p.pendingReqId = ''; $p.sendBtn.Enabled = $true
            return
        }
        if ([System.DateTime]::UtcNow.Ticks -gt $p.deadlineTicks) {
            $p.timer.Stop()
            Append-LrapPoserConvo 'model' '[explanation unavailable: the local model did not answer in time -- it may still be loading. Try again.]'
            $p.statusLabel.Text = 'timed out (fail-silent). The audit surface is unaffected.'
            $p.pendingAnswer = ''; $p.sendBtn.Enabled = $true
        }
    }
    catch { try { $script:LState.poser.timer.Stop() } catch { } }
}

# ----- entry -----
$form = New-LrapForm

if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) } catch { }
    try {
        $s = $script:LState
        $fxDir = Join-Path $PSScriptRoot (Join-Path 'tests' 'fixtures')
        $s.packetPath = Join-Path $fxDir 'clean_routed.json'
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
        Initialize-LrapView
        [System.Windows.Forms.Application]::DoEvents()

        # MODEL: the routed packet rendered; schema + 6 steps + packet_id
        $m = $s.model
        $modelOk = ($null -ne $m -and $m.ok -and $m.schema -eq 'lifeorch.context_packet/0.2' -and @($m.steps).Count -eq 6 -and $m.packet_id -match '^cpkt_')
        $hdrText = [string]$s.headerBox.Text
        if ($modelOk -and ($hdrText -match 'LIVE-RUN AUDIT PATHWAY') -and ($hdrText -match 'cpkt_')) { Write-Output 'SELFTEST_MODEL_OK' } else { Write-Output ("SELFTEST_MODEL_FAIL: model=$modelOk") }

        # PANES: the spine list has the 6 steps; the detail renders all four lanes for a step
        $spineOk = ($s.spineList.Items.Count -ge 6)
        $s.selectedStep = 6; $s.showWhy = $false; $s.showRaw = $false; Render-LrapDetail
        $dt = ''; for ($i = 0; $i -lt $s.detailList.Items.Count; $i++) { $dt += [string]$s.detailList.Items[$i] + "`n" }
        $lanesOk = ($dt -match 'INTENT' -and $dt -match 'INPUT' -and $dt -match 'OUTPUT' -and $dt -match 'RECONCILE')
        if ($spineOk -and $lanesOk) { Write-Output 'SELFTEST_PANES_OK' } else { Write-Output ("SELFTEST_PANES_FAIL: spine=$spineOk lanes=$lanesOk") }

        # RECONCILE: the five-fixture machine classification + collapsed-first-pass (marker shown, prose hidden)
        $expect = @{ 'clean_routed.json' = 0; 'defect_mis_route.json' = 3; 'defect_dropped_candidate.json' = 4; 'defect_wrong_record.json' = 6; 'quirk_flat.json' = 0 }
        $fp = 0; $fn = 0; $classOk = $true
        foreach ($fn2 in $expect.Keys) {
            $mm = Get-LrapModel -PacketPath (Join-Path $fxDir $fn2)
            $got = [int]$mm.overall.inconsistent_step
            $exp = [int]$expect[$fn2]
            if ($got -ne $exp) {
                $classOk = $false
                if ($exp -eq 0 -and $got -ne 0) { $fp++ }
                if ($exp -ne 0 -and $got -ne $exp) { $fn++ }
            }
        }
        # collapsed-first-pass: with showWhy=false the RECONCILE marker shows but the naming prose does not
        $s.selectedStep = 6; $s.showWhy = $false; Render-LrapDetail
        $dt6 = ''; for ($i = 0; $i -lt $s.detailList.Items.Count; $i++) { $dt6 += [string]$s.detailList.Items[$i] + "`n" }
        $collapsedOk = ($dt6 -match 'RECONCILE' -and $dt6 -match 'Show why')
        if ($classOk -and $collapsedOk) { Write-Output 'SELFTEST_RECONCILE_OK' } else { Write-Output ("SELFTEST_RECONCILE_FAIL: classOk=$classOk fp=$fp fn=$fn collapsed=$collapsedOk") }

        # DESCEND: a defect's plain-language why names the offender + is NOT the raw pane; raw pane is separate
        $mw = Get-LrapModel -PacketPath (Join-Path $fxDir 'defect_wrong_record.json')
        $why = (@(Get-LrapStepDescend -Model $mw -StepNo 6) -join "`n")
        $descendOk = ($why -match 'occ_d73b3615a58ba5f1ab226020' -and $why -match 'STILL PRESENT' -and ($why -notmatch 'TRUST:'))
        $rawPane = Get-LrapRawTraceForStep -Packet $mw.packet -StepNo 6
        $rawOk = ((@($rawPane.lines) -join "`n") -match 'TRUST')
        if ($descendOk -and $rawOk) { Write-Output 'SELFTEST_DESCEND_OK' } else { Write-Output ("SELFTEST_DESCEND_FAIL: descend=$descendOk raw=$rawOk") }

        # SANITIZE: the router trace is channel-only (i33)
        $sanOk = ($null -ne $m.sanitize -and $m.sanitize.sanitized -and $m.sanitize.trace_present)
        if ($sanOk) { Write-Output 'SELFTEST_SANITIZE_OK' } else { Write-Output 'SELFTEST_SANITIZE_FAIL' }

        # REFRESH re-reads without throwing
        Invoke-LrapRefresh
        [System.Windows.Forms.Application]::DoEvents()
        if ($s.spineList.Items.Count -ge 6) { Write-Output 'SELFTEST_REFRESH_OK' } else { Write-Output 'SELFTEST_REFRESH_FAIL' }

        # INTERACT: drive the REAL event handlers (PerformClick + spine selection) -- the click-dispatch path the
        # cloud gate cannot reach. Handlers are fail-soft (record lastError), so a throw is caught HERE (and by
        # the user as a status line) instead of an unhandled WinForms dialog. This is the gate that would have
        # caught the reported button errors.
        $s.lastError = ''
        $s.refreshBtn.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $eRef = [string]$s.lastError
        $s.whyBtn.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $eWhy = [string]$s.lastError
        $whyToggled = ([string]$s.whyBtn.Text -eq 'Hide why')
        $s.rawBtn.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $eRaw = [string]$s.lastError
        $dtRaw = ''; for ($i = 0; $i -lt $s.detailList.Items.Count; $i++) { $dtRaw += [string]$s.detailList.Items[$i] + "`n" }
        $rawToggled = (([string]$s.rawBtn.Text -eq 'Hide raw trace') -and ($dtRaw -match 'RAW EXPERT TRACE'))
        $eSel = ''
        if ($s.spineList.Items.Count -ge 4) { $s.spineList.SelectedIndex = 3; [System.Windows.Forms.Application]::DoEvents(); $eSel = [string]$s.lastError }
        $interactOk = ($eRef -eq '' -and $eWhy -eq '' -and $eRaw -eq '' -and $eSel -eq '' -and $whyToggled -and $rawToggled)
        if ($interactOk) { Write-Output 'SELFTEST_INTERACT_OK' }
        else { Write-Output ("SELFTEST_INTERACT_FAIL: refresh=[$eRef] why=[$eWhy] raw=[$eRaw] select=[$eSel] whyToggled=$whyToggled rawToggled=$rawToggled") }

        # READ-ONLY: fixtures tree byte-identical after render; write-guard refuses an outside-runtime target
        [System.Windows.Forms.Application]::DoEvents()
        $sigAfter = Get-TreeSig -Root $fxDir
        $paths = Resolve-LrapPaths -WidgetRoot $s.widgetRoot -RepoRoot $s.repoRoot
        $guardOk = $false
        try { [void](Assert-UnderRuntime -Target ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'lrap-evil.json')) -RuntimeDir $paths.RuntimeDir) } catch { $guardOk = $true }
        if (($sigBefore -eq $sigAfter) -and $guardOk) { Write-Output 'SELFTEST_READONLY_OK' } else { Write-Output ("SELFTEST_READONLY_FAIL: untouched=" + ($sigBefore -eq $sigAfter) + " guard=$guardOk") }

        # POSER (D-0126): the "?" pop-up builds off-screen; the element dropdown lists all 31 elements; an Ask
        # round-trips through the REAL worker + a MOCK gateway (no GPU) to an advisory answer; writes stay under
        # runtime\poser\ (the widget itself makes no model call). This is the click-path the cloud gate can't reach.
        try {
            $s.poserSync = $true
            $s.poserGateway = Join-Path $s.widgetRoot (Join-Path 'tests' 'mock-poser-gateway.ps1')
            $s.selectedStep = 4
            Open-LrapPoserPopup -ElementId 'step:4'
            [System.Windows.Forms.Application]::DoEvents()
            $comboCount = [int]$s.poser.combo.Items.Count
            On-LrapPoserTick   # the sync worker already wrote the answer; ingest it deterministically
            [System.Windows.Forms.Application]::DoEvents()
            $convoText = [string]$s.poser.convo.Text
            $answered = ($convoText -match 'local 9B' -and $convoText -match 'explanation of the instrument')
            $poserDir = Join-Path (Get-LrapPoserRuntimeDir) 'poser'
            $wroteUnderRuntime = (Test-Path -LiteralPath $poserDir)
            try { $s.poser.timer.Stop(); $s.poser.form.Hide() } catch { }
            if (($comboCount -eq 31) -and $answered -and $wroteUnderRuntime) { Write-Output 'SELFTEST_POSER_OK' }
            else { Write-Output ("SELFTEST_POSER_FAIL: combo=$comboCount answered=$answered underRt=$wroteUnderRuntime") }
        }
        catch { Write-Output ('SELFTEST_POSER_FAIL: ' + $_.Exception.Message) }
        finally { $s.poserSync = $false; $s.poserGateway = '' }

        # LAYOUT: Browse + Refresh sit FULLY inside the toolbar after layout
        Update-LrapToolbarLayout
        [System.Windows.Forms.Application]::DoEvents()
        $tbw = [int]$s.toolbar.ClientSize.Width
        $btnR = [int]$s.refreshBtn.Bounds.Right
        $btnBL = [int]$s.browseBtn.Bounds.Left
        $layoutOk = ($tbw -gt 0) -and ($btnR -le $tbw) -and ($btnBL -ge 0) -and [bool]$s.refreshBtn.Visible -and [bool]$s.browseBtn.Visible
        if ($layoutOk) { Write-Output 'SELFTEST_LAYOUT_OK' } else { Write-Output ('SELFTEST_LAYOUT_FAIL: toolbarW=' + $tbw + ' refreshR=' + $btnR + ' browseL=' + $btnBL) }
    }
    catch { Write-Output ('SELFTEST_RENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
