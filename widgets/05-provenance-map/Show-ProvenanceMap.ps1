<#
    Show-ProvenanceMap.ps1 - the Provenance Map (Widget 05) UI entrypoint.

    A native WinForms window (run STA) that READS the project's own construction provenance and shows it at a
    glance: a unit map (module/widget -> version -> iteration -> D-entry -> commit -> verification), a
    one-click "what did iteration N build and under which decision?" (an iteration picker), a "new since
    iteration N" diff, per-unit verification state, the git dev.ship commit stream, the decisions index,
    planned-but-unbuilt, and over-budget hot-doc flags. It is STRICTLY READ-ONLY: it parses the canonical
    on-disk docs + read-only git and drives nothing, writes no doc, runs no git write, submits no executor
    job, and calls no model. The ONLY thing it may persist is its own "new since last visit" marker under
    widgets/05-provenance-map/runtime/ (guarded so it can never escape that dir).

    It is a THIN shell over ProvenanceMap.psm1: the UI only builds controls and renders the core's
    Get-ProvenanceModel / Format-* output. All parsing + the join live in the tested, WinForms-free core.

    Launch:    launch.bat   (pwsh -NoProfile -STA -File Show-ProvenanceMap.ps1)
    Self-test: pwsh -STA -File Show-ProvenanceMap.ps1 -SelfTest   (builds+drives+disposes the form off-screen;
               prints SELFTEST_*_OK -- incl. SELFTEST_LAYOUT_OK + SELFTEST_READONLY_OK)
    Options:   -RepoRoot <dir> point at a specific repo (else the widget's ../..); -Iteration <N> open a wave;
               -GitLogFile <path> (self-test) feed a fixture git-log with <<RS>>/<<US>> tokens.
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$RepoRoot,
    [int]$Iteration = 0,
    [string]$GitLogFile
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProvenanceMap.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


$script:PState = @{
    form          = $null
    repoRoot      = $RepoRoot
    gitLogText    = $null            # set from -GitLogFile in self-test; $null -> live git
    model         = $null
    iterNums      = @()              # iteration numbers aligned with the picker items
    pendingIter   = $Iteration
    lastVisit     = $null
    suspendPickerEvents = $false
    tabs          = @{}              # name -> @{ list; header }
}

function Set-WText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Get-ProvModel {
    # Build the model honouring -RepoRoot + an injected git-log (self-test), else live git. Never throws to
    # the UI: a failure yields a well-formed ok=false model the header renders.
    $s = $script:PState
    try {
        if ($null -ne $s.gitLogText) {
            if ($s.repoRoot) { return Get-ProvenanceModel -RepoRoot $s.repoRoot -WidgetRoot $PSScriptRoot -GitLogText $s.gitLogText }
            return Get-ProvenanceModel -WidgetRoot $PSScriptRoot -GitLogText $s.gitLogText
        }
        if ($s.repoRoot) { return Get-ProvenanceModel -RepoRoot $s.repoRoot -WidgetRoot $PSScriptRoot }
        return Get-ProvenanceModel -WidgetRoot $PSScriptRoot
    }
    catch {
        return [pscustomobject]@{ ok = $false; error = $_.Exception.Message; repo_root = [string]$s.repoRoot
            units = @(); planned = @(); decisions = @(); iterations = @(); commits = @(); plans = @()
            verdicts = @(); doc_flags = @(); flags = @('model build threw: ' + $_.Exception.Message)
            counts = [ordered]@{ modules = 0; widgets = 0; units = 0; built = 0; planned = 0; decisions = 0; iterations = 0; commits = 0; verdicts = 0; over_budget_docs = 0; degradation_flags = 1 } }
    }
}

function Update-ProvToolbarLayout {
    # Position the iteration combo + "since" control + Refresh from the toolbar's CURRENT width (wired to the
    # toolbar Resize + Add_Shown). Robust to WHEN the real width arrives -- the widget-04 lesson: anchoring
    # before a Dock=Top panel is sized baselines against its default ~200px width and throws a Right-anchored
    # button off-screen. StrictMode-safe ContainsKey guards (a Resize can fire before the keys register).
    $s = $script:PState
    if ($null -eq $s) { return }
    foreach ($k in 'toolbar', 'iterCombo', 'sinceLabel', 'sinceBox', 'refreshBtn') { if (-not $s.ContainsKey($k)) { return } }
    if ($null -eq $s.toolbar -or $null -eq $s.iterCombo -or $null -eq $s.sinceLabel -or $null -eq $s.sinceBox -or $null -eq $s.refreshBtn) { return }
    $margin = 8; $gap = 12; $minCombo = 200
    $w = [int]$s.toolbar.ClientSize.Width
    if ($w -le 0) { return }
    $s.refreshBtn.Top = 8
    $s.refreshBtn.Left = $w - $s.refreshBtn.Width - $margin
    $s.sinceBox.Top = 9
    $s.sinceBox.Left = $s.refreshBtn.Left - $s.sinceBox.Width - $gap
    $s.sinceLabel.Top = 13
    $s.sinceLabel.Left = $s.sinceBox.Left - $s.sinceLabel.Width - 4
    $s.iterCombo.Left = 74
    $comboW = $s.sinceLabel.Left - $s.iterCombo.Left - $gap
    if ($comboW -lt $minCombo) { $comboW = $minCombo }
    $s.iterCombo.Width = $comboW
}

function New-ProvTab {
    # Build a TabPage: an optional monospace header Label (Dock=Top) + a monospace ListBox (Dock=Fill).
    param([string]$Name, [string]$Text, [System.Drawing.Font]$Mono)
    $page = [System.Windows.Forms.TabPage]::new()
    $page.Text = $Text
    $header = [System.Windows.Forms.Label]::new()
    $header.Dock = 'Top'; $header.Height = 18; $header.Font = $Mono
    $header.ForeColor = [System.Drawing.Color]::DimGray; $header.Text = ''
    $list = [System.Windows.Forms.ListBox]::new()
    $list.Dock = 'Fill'; $list.Font = $Mono; $list.IntegralHeight = $false; $list.HorizontalScrollbar = $true
    $page.Controls.Add($list)
    $page.Controls.Add($header)
    $script:PState.tabs[$Name] = @{ page = $page; list = $list; header = $header }
    return $page
}

function New-ProvForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Provenance Map - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1180, 820)
    $form.MinimumSize = [System.Drawing.Size]::new(900, 560)
    $form.StartPosition = 'CenterScreen'

    # ===== status strip =====
    $status = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $statusLabel.Text = 'No model loaded.'
    [void]$status.Items.Add($statusLabel)

    # ===== toolbar (top) =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'; $toolbar.Height = 44
    $lblIter = [System.Windows.Forms.Label]::new()
    $lblIter.Text = 'Iteration:'; $lblIter.Location = [System.Drawing.Point]::new(8, 13); $lblIter.AutoSize = $true
    $iterCombo = [System.Windows.Forms.ComboBox]::new()
    $iterCombo.DropDownStyle = 'DropDownList'
    $iterCombo.Location = [System.Drawing.Point]::new(74, 9)
    $iterCombo.Size = [System.Drawing.Size]::new(700, 26)
    $iterCombo.Anchor = 'Top,Left'
    $iterCombo.Font = $mono
    $sinceLabel = [System.Windows.Forms.Label]::new()
    $sinceLabel.Text = 'New since i:'; $sinceLabel.AutoSize = $true; $sinceLabel.Location = [System.Drawing.Point]::new(800, 13)
    $sinceBox = [System.Windows.Forms.NumericUpDown]::new()
    $sinceBox.Minimum = 0; $sinceBox.Maximum = 999; $sinceBox.Width = 60
    $sinceBox.Location = [System.Drawing.Point]::new(880, 9)
    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Refresh'; $refreshBtn.Size = [System.Drawing.Size]::new(96, 27)
    $refreshBtn.Location = [System.Drawing.Point]::new(960, 8); $refreshBtn.Anchor = 'Top,Left'
    $toolbar.Controls.AddRange(@($lblIter, $iterCombo, $sinceLabel, $sinceBox, $refreshBtn))
    # Register toolbar controls BEFORE docking (docking fires Resize -> Update-ProvToolbarLayout; StrictMode
    # Latest throws on a missing hashtable key, so the keys must exist when that first Resize fires).
    $script:PState.toolbar = $toolbar
    $script:PState.iterCombo = $iterCombo
    $script:PState.sinceLabel = $sinceLabel
    $script:PState.sinceBox = $sinceBox
    $script:PState.refreshBtn = $refreshBtn
    $toolbar.Add_Resize({ Update-ProvToolbarLayout }.GetNewClosure())

    # ===== header (project provenance summary + flags) =====
    $headerBox = [System.Windows.Forms.RichTextBox]::new()
    $headerBox.Dock = 'Top'; $headerBox.Height = 74; $headerBox.ReadOnly = $true
    $headerBox.Font = $mono; $headerBox.BackColor = [System.Drawing.Color]::White; $headerBox.BorderStyle = 'None'
    $headerBox.Text = 'Select an iteration above, or press Refresh.'

    # ===== tabs =====
    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'; $tabs.Font = $mono
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'exists'    -Text 'What Exists'   -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'iteration' -Text 'Iteration N'   -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'newsince'  -Text 'New Since'     -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'verify'    -Text 'Verification'  -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'commits'   -Text 'Commits'       -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'decisions' -Text 'Decisions'     -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'planned'   -Text 'Planned'       -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'docbudget' -Text 'Doc Budget'    -Mono $mono))
    [void]$tabs.TabPages.Add((New-ProvTab -Name 'flags'     -Text 'Flags'         -Mono $mono))

    # center first, then docked edges (z-order)
    $form.Controls.Add($tabs)
    $form.Controls.Add($headerBox)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:PState
    $s.form = $form
    $s.headerBox = $headerBox
    $s.tabControl = $tabs
    $s.statusLabel = $statusLabel

    # Handlers touch ONLY $script:PState + script functions -> scope-safe (the D-0060 lesson). .GetNewClosure()
    # applied defensively.
    $refreshBtn.Add_Click({ Invoke-ProvRefresh }.GetNewClosure())
    $iterCombo.Add_SelectedIndexChanged({ if (-not $script:PState.suspendPickerEvents) { Show-SelectedIteration } }.GetNewClosure())
    $sinceBox.Add_ValueChanged({ if (-not $script:PState.suspendPickerEvents) { Show-NewSinceTab } }.GetNewClosure())
    $form.Add_Shown({
            Update-ProvToolbarLayout
            Initialize-ProvView
        }.GetNewClosure())

    return $form
}

function Set-TabLines {
    param([string]$Name, [string]$Header, $Lines)
    $s = $script:PState
    if (-not $s.tabs.ContainsKey($Name)) { return }
    $t = $s.tabs[$Name]
    $t.header.Text = [string]$Header
    $t.list.BeginUpdate()
    $t.list.Items.Clear()
    foreach ($ln in @($Lines)) { [void]$t.list.Items.Add([string]$ln) }
    $t.list.EndUpdate()
}

function Render-Model {
    # Read the model + render every static tab + header. Reads only (Set-LastVisit is separate).
    $s = $script:PState
    $model = Get-ProvModel
    $s.model = $model
    $rows = Format-ProvenanceRows -Model $model

    Set-WText $s.headerBox (($rows.header_lines) -join "`r`n")
    $s.statusLabel.Text = [string]$rows.summary_line

    Set-TabLines -Name 'exists'    -Header $rows.exists_header  -Lines $rows.exists_lines
    Set-TabLines -Name 'verify'    -Header ''                   -Lines $rows.verify_lines
    Set-TabLines -Name 'commits'   -Header $rows.commit_header  -Lines $rows.commit_lines
    Set-TabLines -Name 'decisions' -Header ''                   -Lines $rows.decision_lines
    Set-TabLines -Name 'planned'   -Header ''                   -Lines $rows.planned_lines
    Set-TabLines -Name 'docbudget' -Header $rows.docflag_header -Lines $rows.docflag_lines
    Set-TabLines -Name 'flags'     -Header ''                   -Lines $rows.flag_lines

    # (re)build the iteration picker, preserving the selection by number
    $prevNum = $null
    if (@($s.iterNums).Count -gt 0 -and $s.iterCombo.SelectedIndex -ge 0 -and $s.iterCombo.SelectedIndex -lt @($s.iterNums).Count) {
        $prevNum = [int]@($s.iterNums)[$s.iterCombo.SelectedIndex]
    }
    $items = @(Get-IterationList -Model $model)
    $s.iterNums = @($items | ForEach-Object { $_.num })
    $prev = $s.suspendPickerEvents; $s.suspendPickerEvents = $true
    try {
        $s.iterCombo.Items.Clear()
        foreach ($it in $items) { [void]$s.iterCombo.Items.Add([string]$it.label) }
        $sel = 0
        if ($null -ne $prevNum) { for ($i = 0; $i -lt @($s.iterNums).Count; $i++) { if ([int]@($s.iterNums)[$i] -eq $prevNum) { $sel = $i; break } } }
        elseif ($s.pendingIter -gt 0) { for ($i = 0; $i -lt @($s.iterNums).Count; $i++) { if ([int]@($s.iterNums)[$i] -eq $s.pendingIter) { $sel = $i; break } } }
        if ($s.iterCombo.Items.Count -gt 0) { $s.iterCombo.SelectedIndex = $sel }
    }
    finally { $s.suspendPickerEvents = $prev }
}

function Show-SelectedIteration {
    $s = $script:PState
    $idx = $s.iterCombo.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($s.iterNums).Count) { return }
    $n = [int]@($s.iterNums)[$idx]
    $build = Get-IterationBuild -Model $s.model -Iteration $n
    $fmt = Format-IterationBuild -Build $build
    Set-TabLines -Name 'iteration' -Header ('what iteration ' + [string]$n + ' built + under which decision') -Lines $fmt.lines
    # one-click: bring the iteration tab forward
    if ($s.tabs.ContainsKey('iteration')) { try { $s.tabControl.SelectedTab = $s.tabs['iteration'].page } catch { } }
}

function Show-NewSinceTab {
    $s = $script:PState
    if ($null -eq $s.model) { return }
    $since = [int]$s.sinceBox.Value
    $ns = Get-NewSince -Model $s.model -Since $since
    $fmt = Format-NewSince -NewSince $ns
    Set-TabLines -Name 'newsince' -Header ('diff vs last visit (persisted only in this widget''s runtime dir)') -Lines $fmt.lines
}

function Initialize-ProvView {
    $s = $script:PState
    # last-visit marker: default the "since" box to the last visited iteration (persisted in runtime/ only).
    $paths = Resolve-ProvenancePaths -WidgetRoot $PSScriptRoot -RepoRoot $s.repoRoot
    $s.lastVisit = Get-LastVisit -RuntimeDir $paths.RuntimeDir
    Render-Model
    $maxIter = 0
    foreach ($n in @($s.iterNums)) { if ([int]$n -gt $maxIter) { $maxIter = [int]$n } }
    $sinceDefault = if ($null -ne $s.lastVisit -and [int]$s.lastVisit.last_iteration -gt 0) { [int]$s.lastVisit.last_iteration } elseif ($maxIter -gt 0) { $maxIter - 1 } else { 0 }
    if ($sinceDefault -lt 0) { $sinceDefault = 0 }
    $prev = $s.suspendPickerEvents; $s.suspendPickerEvents = $true
    try { if ($sinceDefault -le [int]$s.sinceBox.Maximum) { $s.sinceBox.Value = $sinceDefault } } finally { $s.suspendPickerEvents = $prev }
    Show-SelectedIteration
    Show-NewSinceTab
}

function Invoke-ProvRefresh {
    # Re-read everything from disk + git, then persist the "new since last visit" marker at the newest
    # iteration -- the ONLY write the widget makes, guarded to its own runtime dir (acceptance c/d).
    $s = $script:PState
    Render-Model
    Show-SelectedIteration
    Show-NewSinceTab
    $maxIter = 0
    foreach ($n in @($s.iterNums)) { if ([int]$n -gt $maxIter) { $maxIter = [int]$n } }
    if ($maxIter -gt 0) {
        try {
            $paths = Resolve-ProvenancePaths -WidgetRoot $PSScriptRoot -RepoRoot $s.repoRoot
            [void](Set-LastVisit -Iteration $maxIter -RuntimeDir $paths.RuntimeDir)
            $s.lastVisit = Get-LastVisit -RuntimeDir $paths.RuntimeDir
        }
        catch { $s.statusLabel.Text = 'note: could not persist last-visit marker (' + $_.Exception.Message + ')' }
    }
}

# ----- entry -----
if ($GitLogFile -and (Test-Path -LiteralPath $GitLogFile -PathType Leaf)) {
    $raw = Get-Content -LiteralPath $GitLogFile -Raw
    $script:PState.gitLogText = ($raw -replace '<<RS>>', ([char]0x1E)) -replace '<<US>>', ([char]0x1F)
}

$form = New-ProvForm

if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    # FAIL-FAST on any exception raised INSIDE a WinForms event handler (e.g. Add_Shown -> Initialize): the
    # default WinForms behaviour pops a MODAL ThreadException dialog, which HANGS a headless off-screen
    # SelfTest forever (it waits for a click that never comes). ThrowException mode re-raises so my try/catch
    # below turns it into a SELFTEST_RENDER_FAIL marker the gate asserts on -- never a hang.
    try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) } catch { }
    # D-0049/D-0060/D-0064 lesson: mock/API gates miss rendered-UI defects, so drive the REAL controls under
    # STA over the FIXTURE repo -- a scope/null/marshalling bug in the picker, Render-Model, or a Format-*
    # surfaces HERE. A throw prints a FAIL marker the gate asserts on.
    try {
        $s = $script:PState
        $fixtureRepo = Join-Path $PSScriptRoot (Join-Path 'tests' (Join-Path 'fixtures' 'repo'))
        $fixtureGit = Join-Path $PSScriptRoot (Join-Path 'tests' (Join-Path 'fixtures' 'git-log.fixture.txt'))
        # point the plan + verdict dirs at the committable fixture dirs (outside any runtime/ path)
        $env:LIFEORCH_PROVENANCE_PLANS = Join-Path $PSScriptRoot (Join-Path 'tests' (Join-Path 'fixtures' 'plans'))
        $env:LIFEORCH_PROVENANCE_VERDICTS = Join-Path $PSScriptRoot (Join-Path 'tests' (Join-Path 'fixtures' 'verdicts'))
        $s.repoRoot = $fixtureRepo
        if (Test-Path -LiteralPath $fixtureGit -PathType Leaf) {
            $raw = Get-Content -LiteralPath $fixtureGit -Raw
            $s.gitLogText = ($raw -replace '<<RS>>', ([char]0x1E)) -replace '<<US>>', ([char]0x1F)
        }
        $s.pendingIter = 40

        # READ-ONLY guard: snapshot the fixture repo tree BEFORE any render; assert it is byte-identical AFTER.
        function Get-TreeSig { param([string]$Root)
            $acc = New-Object System.Collections.Generic.List[string]
            foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
                [void]$acc.Add($f.FullName + '|' + [string]$f.Length + '|' + $f.LastWriteTimeUtc.ToString('o'))
            }
            return ($acc.ToArray() -join "`n")
        }
        $fixturesRoot = Split-Path $fixtureRepo -Parent
        $sigBefore = Get-TreeSig -Root $fixturesRoot

        # Show the form OFF-SCREEN so a REAL layout pass runs (the Dock=Top toolbar gets its true width) --
        # the build-only SelfTest never showed the form + missed the anchored-toolbar defect (widget-04).
        $form.StartPosition = 'Manual'
        $form.Location = [System.Drawing.Point]::new(-4000, -4000)
        $form.ShowInTaskbar = $false
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()

        Initialize-ProvView
        [System.Windows.Forms.Application]::DoEvents()

        # MODEL rendered: units tab has the 4 fixture units, header names the repo + counts
        $existsList = $s.tabs['exists'].list
        $unitsOk = ($existsList.Items.Count -ge 4)
        $headerOk = ([string]$s.headerBox.Text -match 'PROVENANCE MAP' -and [string]$s.headerBox.Text -match 'modules:')
        $w05Ok = $false
        for ($i = 0; $i -lt $existsList.Items.Count; $i++) { if ([string]$existsList.Items[$i] -match 'Provenance Map' -and [string]$existsList.Items[$i] -match 'Proposed') { $w05Ok = $true } }
        if ($unitsOk -and $headerOk -and $w05Ok) { Write-Output 'SELFTEST_MODEL_OK' }
        else { Write-Output ("SELFTEST_MODEL_FAIL: units=$unitsOk header=$headerOk w05=$w05Ok") }

        # ITERATION one-click: pick i40 -> the iteration tab names model.gateway + D-0110 + the iteration tab is selected
        $iterIdx = -1
        for ($i = 0; $i -lt @($s.iterNums).Count; $i++) { if ([int]@($s.iterNums)[$i] -eq 40) { $iterIdx = $i; break } }
        if ($iterIdx -ge 0) { $s.iterCombo.SelectedIndex = $iterIdx }
        [System.Windows.Forms.Application]::DoEvents()
        $itList = $s.tabs['iteration'].list
        $itText = ''
        for ($i = 0; $i -lt $itList.Items.Count; $i++) { $itText += [string]$itList.Items[$i] + "`n" }
        $iterOk = ($itText -match 'model.gateway') -and ($itText -match 'D-0110') -and ($itText -match '(?i)a1a1a1a')
        $tabSelOk = $false; try { $tabSelOk = ($s.tabControl.SelectedTab -eq $s.tabs['iteration'].page) } catch { }
        if ($iterOk -and $tabSelOk) { Write-Output 'SELFTEST_ITERATION_OK' }
        else { Write-Output ("SELFTEST_ITERATION_FAIL: iterOk=$iterOk tabSel=$tabSelOk") }

        # NEW SINCE: set since=39 -> the newsince tab lists model.gateway / a1a1a1a and 1 unit / 2 commits
        $s.sinceBox.Value = 39
        [System.Windows.Forms.Application]::DoEvents()
        $nsList = $s.tabs['newsince'].list
        $nsText = ''
        for ($i = 0; $i -lt $nsList.Items.Count; $i++) { $nsText += [string]$nsList.Items[$i] + "`n" }
        $nsOk = ($nsText -match 'NEW SINCE ITERATION 39') -and ($nsText -match 'model.gateway') -and ($nsText -match 'units=1')
        if ($nsOk) { Write-Output 'SELFTEST_NEWSINCE_OK' } else { Write-Output ("SELFTEST_NEWSINCE_FAIL: " + (Limit-Text $nsText 120)) }

        # FLAGS: doc-budget tab marks CURRENT_STATE OVER; flags tab carries the OVER BUDGET / PB-3 line
        $dbList = $s.tabs['docbudget'].list; $flList = $s.tabs['flags'].list
        $overOk = $false
        for ($i = 0; $i -lt $dbList.Items.Count; $i++) { if ([string]$dbList.Items[$i] -match 'CURRENT_STATE' -and [string]$dbList.Items[$i] -match 'OVER') { $overOk = $true } }
        $flagOk = $false
        for ($i = 0; $i -lt $flList.Items.Count; $i++) { if ([string]$flList.Items[$i] -match 'OVER BUDGET' -and [string]$flList.Items[$i] -match 'PB-3') { $flagOk = $true } }
        if ($overOk -and $flagOk) { Write-Output 'SELFTEST_FLAGS_OK' } else { Write-Output ("SELFTEST_FLAGS_FAIL: over=$overOk flag=$flagOk") }

        # READ-ONLY over the repo: the fixture tree must be byte-identical after a full render (Get-ProvModel
        # + all Format-* + iteration + newsince). Plus Set-LastVisit must refuse an out-of-runtime target.
        [System.Windows.Forms.Application]::DoEvents()
        $sigAfter = Get-TreeSig -Root $fixturesRoot
        $repoUntouched = ($sigBefore -eq $sigAfter)
        $tmpRuntime = Join-Path ([System.IO.Path]::GetTempPath()) ('prov-ro-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $wrote = Set-LastVisit -Iteration 40 -RuntimeDir $tmpRuntime
        $wroteInside = ([string]$wrote).StartsWith([System.IO.Path]::GetFullPath($tmpRuntime))
        $onlyOne = (@(Get-ChildItem -LiteralPath $tmpRuntime -Recurse -File).Count -eq 1)
        try { Remove-Item -LiteralPath $tmpRuntime -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        if ($repoUntouched -and $wroteInside -and $onlyOne) { Write-Output 'SELFTEST_READONLY_OK' }
        else { Write-Output ("SELFTEST_READONLY_FAIL: repoUntouched=$repoUntouched wroteInside=$wroteInside onlyOne=$onlyOne") }

        # REFRESH re-reads without throwing (writes the last-visit marker into the widget's OWN runtime dir)
        Invoke-ProvRefresh
        [System.Windows.Forms.Application]::DoEvents()
        if ($s.tabs['exists'].list.Items.Count -ge 4) { Write-Output 'SELFTEST_REFRESH_OK' } else { Write-Output 'SELFTEST_REFRESH_FAIL' }

        # LAYOUT guard (D-0049/D-0060/D-0064): Refresh must sit FULLY inside the toolbar; the combo must not
        # overrun the "since" controls -- the rendered-UI defect the old build-only SelfTest missed.
        Update-ProvToolbarLayout
        [System.Windows.Forms.Application]::DoEvents()
        $tbw = [int]$s.toolbar.ClientSize.Width
        $cbR = [int]$s.iterCombo.Bounds.Right
        $slL = [int]$s.sinceLabel.Bounds.Left
        $btnL = [int]$s.refreshBtn.Bounds.Left
        $btnR = [int]$s.refreshBtn.Bounds.Right
        $layoutOk = ($tbw -gt 0) -and ($btnR -le $tbw) -and ($btnL -ge 0) -and ($cbR -le $slL) -and [bool]$s.refreshBtn.Visible
        if ($layoutOk) { Write-Output 'SELFTEST_LAYOUT_OK' }
        else { Write-Output ('SELFTEST_LAYOUT_FAIL: toolbarW=' + $tbw + ' combo.Right=' + $cbR + ' sinceL=' + $slL + ' refresh=' + $s.refreshBtn.Bounds.ToString()) }
    }
    catch { Write-Output ('SELFTEST_RENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
