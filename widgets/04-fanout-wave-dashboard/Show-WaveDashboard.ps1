<#
    Show-WaveDashboard.ps1 - the Fan-out Wave Dashboard (Widget 04) UI entrypoint.

    A native WinForms window (run STA) that READS a fan-out wave's live runtime state and shows it at a glance:
    a plan picker (newest wave first), a worker table (id / lane / GPU / state / summary), a lease panel (who
    holds gpu / git / doc:<path> and for how long), the dispatch_now vs queued counts, and ready_for_handoff.
    A Refresh button re-reads the plan + lease dirs. It is READ-ONLY: it drives nothing and writes nothing.

    It is a THIN shell over WaveDashboard.psm1: the UI only builds controls and renders the core's
    Get-WaveState / Format-WaveRows output. All parsing + the ready_for_handoff rule live in the tested core.

    Launch:    launch.bat   (pwsh -NoProfile -STA -File Show-WaveDashboard.ps1)
    Self-test: pwsh -STA -File Show-WaveDashboard.ps1 -SelfTest   (builds+drives+disposes the form; prints SELFTEST_*_OK)
    Options:   -PlanDir <dir> open a specific plan; -PlansDir / -LeaseDir override the data-source dirs.
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$PlanDir,
    [string]$PlansDir,
    [string]$LeaseDir
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WaveDashboard.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:WState = @{
    form         = $null
    plans        = @()
    plansDir     = $PlansDir
    leaseDir     = $LeaseDir
    currentPlanDir = $null
    pendingPlanDir = $PlanDir
    lastLoadedState = $null
    suspendPickerEvents = $false
}

function Set-WText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Resolve-WaveDirs {
    # Resolve the two data-source dirs once (honouring any -PlansDir/-LeaseDir overrides), and cache them.
    $s = $script:WState
    if ($s.plansDir -and $s.leaseDir) { return }
    $p = Resolve-WavePaths -PlansDir $s.plansDir -LeaseDir $s.leaseDir
    if (-not $s.plansDir) { $s.plansDir = $p.PlansDir }
    if (-not $s.leaseDir) { $s.leaseDir = $p.LeaseDir }
}

function Update-WaveToolbarLayout {
    # Position the plan combo + Refresh button from the toolbar's CURRENT width (wired to the toolbar Resize
    # + called from Add_Shown). Robust to WHEN the real width arrives -- unlike Left/Right anchoring, which
    # baselines against the Panel's default 200px width when the children are added before the Panel is
    # docked/sized (that put Refresh off the right edge + overran the combo). Touches only $script:WState.
    $s = $script:WState
    # StrictMode-safe: ContainsKey never throws on an absent key (a bare $s.toolbar would, if the toolbar
    # Resize fires during construction before the keys are registered). Both guards -> robust under any mode.
    if ($null -eq $s) { return }
    if (-not ($s.ContainsKey('toolbar') -and $s.ContainsKey('planCombo') -and $s.ContainsKey('refreshBtn'))) { return }
    if ($null -eq $s.toolbar -or $null -eq $s.planCombo -or $null -eq $s.refreshBtn) { return }
    $margin = 8; $gap = 12; $minCombo = 160
    $w = [int]$s.toolbar.ClientSize.Width
    if ($w -le 0) { return }
    $btnLeft = $w - $s.refreshBtn.Width - $margin
    $minLeft = $s.planCombo.Left + $minCombo + $gap
    if ($btnLeft -lt $minLeft) { $btnLeft = $minLeft }
    $s.refreshBtn.Top = 8
    $s.refreshBtn.Left = $btnLeft
    $s.planCombo.Left = 52
    $comboW = $s.refreshBtn.Left - $s.planCombo.Left - $gap
    if ($comboW -lt $minCombo) { $comboW = $minCombo }
    $s.planCombo.Width = $comboW
}

function New-WaveForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Fan-out Wave Dashboard - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1120, 800)
    $form.MinimumSize = [System.Drawing.Size]::new(860, 560)
    $form.StartPosition = 'CenterScreen'

    # ===== status strip =====
    $status = [System.Windows.Forms.StatusStrip]::new()
    $statusLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $statusLabel.Text = 'No wave loaded.'
    [void]$status.Items.Add($statusLabel)

    # ===== toolbar (top) =====
    $toolbar = [System.Windows.Forms.Panel]::new()
    $toolbar.Dock = 'Top'
    $toolbar.Height = 44
    $lblPlan = [System.Windows.Forms.Label]::new()
    $lblPlan.Text = 'Wave:'
    $lblPlan.Location = [System.Drawing.Point]::new(8, 13)
    $lblPlan.AutoSize = $true
    $planCombo = [System.Windows.Forms.ComboBox]::new()
    $planCombo.DropDownStyle = 'DropDownList'
    $planCombo.Location = [System.Drawing.Point]::new(52, 9)
    $planCombo.Size = [System.Drawing.Size]::new(820, 26)
    $planCombo.Anchor = 'Top,Left'
    $planCombo.Font = $mono
    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Refresh'
    $refreshBtn.Size = [System.Drawing.Size]::new(96, 27)
    $refreshBtn.Location = [System.Drawing.Point]::new(884, 8)
    $refreshBtn.Anchor = 'Top,Left'
    $toolbar.Controls.AddRange(@($lblPlan, $planCombo, $refreshBtn))
    # Register the toolbar controls in $script:WState NOW, before the toolbar is docked into the form below:
    # docking a Dock=Top panel fires Resize, which invokes Update-WaveToolbarLayout -- and StrictMode Latest
    # throws on a missing hashtable key, so these keys must already exist when that first Resize fires.
    $script:WState.toolbar = $toolbar
    $script:WState.planCombo = $planCombo
    $script:WState.refreshBtn = $refreshBtn
    # A Dock=Top Panel is only sized to the form's client width AFTER the form is shown, so anchoring the
    # combo/Refresh before that baselines them against the Panel's default 200px width -- which threw the
    # Refresh button off the right edge and overran the combo (a rendered-UI defect the build-only SelfTest
    # missed; D-0049/D-0060/D-0064). Lay them out from the toolbar's ACTUAL width on every Resize instead.
    $toolbar.Add_Resize({ Update-WaveToolbarLayout }.GetNewClosure())

    # ===== header (plan / iteration / title / counts / ready) =====
    $headerBox = [System.Windows.Forms.RichTextBox]::new()
    $headerBox.Dock = 'Top'
    $headerBox.Height = 92
    $headerBox.ReadOnly = $true
    $headerBox.Font = $mono
    $headerBox.BackColor = [System.Drawing.Color]::White
    $headerBox.BorderStyle = 'None'
    $headerBox.Text = 'Select a wave above, or press Refresh.'

    # ===== split: workers (top) | leases (bottom) =====
    $split = [System.Windows.Forms.SplitContainer]::new()
    $split.Dock = 'Fill'
    $split.Orientation = 'Horizontal'
    try { $split.SplitterDistance = 420 } catch { }

    # ----- worker pane -----
    $lblWorkers = [System.Windows.Forms.Label]::new()
    $lblWorkers.Dock = 'Top'
    $lblWorkers.Height = 20
    $lblWorkers.Font = $mono
    $lblWorkers.Text = 'WORKERS'
    $workerHeader = [System.Windows.Forms.Label]::new()
    $workerHeader.Dock = 'Top'
    $workerHeader.Height = 18
    $workerHeader.Font = $mono
    $workerHeader.ForeColor = [System.Drawing.Color]::DimGray
    $workerHeader.Text = ''
    $workerList = [System.Windows.Forms.ListBox]::new()
    $workerList.Dock = 'Fill'
    $workerList.Font = $mono
    $workerList.IntegralHeight = $false
    $workerList.HorizontalScrollbar = $true
    $split.Panel1.Controls.Add($workerList)
    $split.Panel1.Controls.Add($workerHeader)
    $split.Panel1.Controls.Add($lblWorkers)

    # ----- lease pane -----
    $lblLeases = [System.Windows.Forms.Label]::new()
    $lblLeases.Dock = 'Top'
    $lblLeases.Height = 20
    $lblLeases.Font = $mono
    $lblLeases.Text = 'LEASES (res.lease #29 -- read-only)'
    $leaseHeader = [System.Windows.Forms.Label]::new()
    $leaseHeader.Dock = 'Top'
    $leaseHeader.Height = 18
    $leaseHeader.Font = $mono
    $leaseHeader.ForeColor = [System.Drawing.Color]::DimGray
    $leaseHeader.Text = ''
    $leaseList = [System.Windows.Forms.ListBox]::new()
    $leaseList.Dock = 'Fill'
    $leaseList.Font = $mono
    $leaseList.IntegralHeight = $false
    $leaseList.HorizontalScrollbar = $true
    $split.Panel2.Controls.Add($leaseList)
    $split.Panel2.Controls.Add($leaseHeader)
    $split.Panel2.Controls.Add($lblLeases)

    # center first, then docked edges (z-order)
    $form.Controls.Add($split)
    $form.Controls.Add($headerBox)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($status)

    $s = $script:WState
    $s.form = $form
    $s.toolbar = $toolbar
    $s.planCombo = $planCombo
    $s.refreshBtn = $refreshBtn
    $s.headerBox = $headerBox
    $s.workerList = $workerList
    $s.workerHeader = $workerHeader
    $s.leaseList = $leaseList
    $s.leaseHeader = $leaseHeader
    $s.statusLabel = $statusLabel
    $s.split = $split

    # Handlers touch ONLY $script:WState + script functions, so they are scope-safe (the D-0060 lesson is
    # about a bare LOCAL captured in a handler). .GetNewClosure() is applied to be defensive on the combo
    # handler, which is the one most likely to be refactored to capture a local later.
    $refreshBtn.Add_Click({ Invoke-WaveRefresh }.GetNewClosure())
    $planCombo.Add_SelectedIndexChanged({ if (-not $script:WState.suspendPickerEvents) { Show-SelectedPlan } }.GetNewClosure())
    $form.Add_Shown({
            try { $script:WState.split.SplitterDistance = [int]($script:WState.split.Height * 0.55) } catch { }
            Update-WaveToolbarLayout
            Initialize-WaveView
        }.GetNewClosure())

    return $form
}

function Get-PlanPickerLine {
    param($Entry)
    $plan = [string](Get-Prop $Entry 'plan_id')
    $iter = [string](Get-Prop $Entry 'iteration')
    $title = Limit-Text (Get-Prop $Entry 'title') 90
    $flag = if ([bool](Get-Prop $Entry 'ok' $true)) { '' } else { '  [unreadable]' }
    return ($plan.PadRight(20) + ' (i' + $iter + ')  ' + $title + $flag)
}

function Update-PlanPicker {
    # (Re)load the plan list newest-first into the combo, preserving the current selection by plan_id.
    $s = $script:WState
    Resolve-WaveDirs
    $prevId = $null
    if ($s.currentPlanDir) { $prevId = Split-Path -Leaf $s.currentPlanDir }
    $s.plans = @(Get-WavePlans -PlansDir $s.plansDir)
    $prev = $s.suspendPickerEvents
    $s.suspendPickerEvents = $true
    try {
        $s.planCombo.Items.Clear()
        foreach ($e in $s.plans) { [void]$s.planCombo.Items.Add((Get-PlanPickerLine -Entry $e)) }
        $sel = 0
        if ($prevId) {
            for ($i = 0; $i -lt $s.plans.Count; $i++) {
                if ((Split-Path -Leaf ([string]$s.plans[$i].dir)) -eq $prevId) { $sel = $i; break }
            }
        }
        if ($s.planCombo.Items.Count -gt 0) { $s.planCombo.SelectedIndex = $sel }
    }
    finally { $s.suspendPickerEvents = $prev }
}

function Get-SelectedPlanDir {
    $s = $script:WState
    $idx = $s.planCombo.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($s.plans).Count) { return $null }
    return [string]@($s.plans)[$idx].dir
}

function Show-SelectedPlan {
    $s = $script:WState
    $planDir = Get-SelectedPlanDir
    if (-not $planDir) { return }
    $s.currentPlanDir = $planDir
    Render-Wave -PlanDir $planDir
}

function Render-Wave {
    param([string]$PlanDir)
    $s = $script:WState
    Resolve-WaveDirs
    $state = Get-WaveState -PlanDir $PlanDir -LeaseDir $s.leaseDir
    $s.lastLoadedState = $state
    $rows = Format-WaveRows -State $state

    Set-WText $s.headerBox (($rows.header_lines) -join "`r`n")

    $s.workerHeader.Text = [string]$rows.worker_header
    $s.workerList.BeginUpdate()
    $s.workerList.Items.Clear()
    foreach ($ln in @($rows.worker_lines)) { [void]$s.workerList.Items.Add([string]$ln) }
    $s.workerList.EndUpdate()

    $s.leaseHeader.Text = [string]$rows.lease_header
    $s.leaseList.BeginUpdate()
    $s.leaseList.Items.Clear()
    foreach ($ln in @($rows.lease_lines)) { [void]$s.leaseList.Items.Add([string]$ln) }
    $s.leaseList.EndUpdate()

    $s.statusLabel.Text = [string]$rows.summary_line
}

function Invoke-WaveRefresh {
    # Re-read the plans dir (a new wave may have appeared) AND re-render the current wave from disk.
    Update-PlanPicker
    Show-SelectedPlan
}

function Initialize-WaveView {
    $s = $script:WState
    Update-PlanPicker
    # -PlanDir opens a specific wave on start (if it is in the list); otherwise the newest is selected.
    if ($s.pendingPlanDir) {
        $want = Split-Path -Leaf $s.pendingPlanDir
        for ($i = 0; $i -lt @($s.plans).Count; $i++) {
            if ((Split-Path -Leaf ([string]@($s.plans)[$i].dir)) -eq $want) { $s.planCombo.SelectedIndex = $i; break }
        }
    }
    Show-SelectedPlan
}

# ----- entry -----
$form = New-WaveForm

if ($SelfTest) {
    Write-Output 'SELFTEST_FORM_OK'
    # D-0049/D-0060/D-0064 lesson: mock/API gates miss rendered-UI defects, so drive the REAL controls under
    # STA over the FIXTURE dirs -- a scope/null/marshalling bug in the picker, Render-Wave, or Format-WaveRows
    # surfaces HERE, not only in a human pass. Defensive: a throw prints a FAIL marker the gate asserts on.
    try {
        $s = $script:WState
        $fixtures = Join-Path $PSScriptRoot (Join-Path 'tests' 'fixtures')
        $s.plansDir = Join-Path $fixtures 'plans'
        $s.leaseDir = Join-Path $fixtures 'leases'
        $s.pendingPlanDir = $null

        # Show the form OFF-SCREEN so a REAL layout pass runs (the Dock=Top toolbar gets its true width and
        # the combo/Refresh layout is exercised) -- the build-only SelfTest never showed the form and so
        # missed the anchored-toolbar defect (D-0049/D-0060/D-0064). Invisible: off-screen + no taskbar.
        $form.StartPosition = 'Manual'
        $form.Location = [System.Drawing.Point]::new(-4000, -4000)
        $form.ShowInTaskbar = $false
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()

        Initialize-WaveView   # loads the plan picker (newest first) + renders the default (newest) wave

        $pickerOk = ($s.planCombo.Items.Count -ge 2)
        $newestIsTestwave = ([string]$s.planCombo.Items[0] -like 'fo-99-testwave*')   # newest-first ordering
        if ($pickerOk -and $newestIsTestwave) { Write-Output 'SELFTEST_PICKER_OK' }

        # newest wave (fo-99-testwave) rendered: 3 workers, a 'coding' lane row, NOT ready
        $st = $s.lastLoadedState
        $workersOk = ($s.workerList.Items.Count -ge 3)
        $laneOk = $false
        for ($i = 0; $i -lt $s.workerList.Items.Count; $i++) { if ([string]$s.workerList.Items[$i] -match 'coding') { $laneOk = $true } }
        $notReadyOk = (-not [bool]$st.ready_for_handoff) -and ([string]$s.headerBox.Text -match 'not ready|ready_for_handoff: False')
        # lease panel: >=1 row, a gpu row, and the doc lease shown EXPIRED
        $leaseGpuOk = $false; $leaseExpiredOk = $false
        for ($i = 0; $i -lt $s.leaseList.Items.Count; $i++) {
            $row = [string]$s.leaseList.Items[$i]
            if ($row -match '^gpu\s') { $leaseGpuOk = $true }
            if ($row -match 'EXPIRED') { $leaseExpiredOk = $true }
        }
        if ($workersOk -and $laneOk -and $notReadyOk -and $leaseGpuOk -and $leaseExpiredOk) { Write-Output 'SELFTEST_RENDER_OK' }
        else { Write-Output ("SELFTEST_RENDER_FAIL: workers=$workersOk lane=$laneOk notReady=$notReadyOk gpu=$leaseGpuOk expired=$leaseExpiredOk") }

        # switch to the older fully-done wave -> ready_for_handoff true (drives the picker handler live)
        for ($i = 0; $i -lt $s.planCombo.Items.Count; $i++) {
            if ([string]$s.planCombo.Items[$i] -like 'fo-98-oldwave*') { $s.planCombo.SelectedIndex = $i; break }
        }
        $st2 = $s.lastLoadedState
        $readyOk = [bool]$st2.ready_for_handoff -and ([string]$s.headerBox.Text -match 'READY FOR HANDOFF|ready_for_handoff: True')
        if ($readyOk) { Write-Output 'SELFTEST_READY_OK' }
        else { Write-Output ("SELFTEST_READY_FAIL: ready=" + [string]$st2.ready_for_handoff) }

        # Refresh re-reads without throwing and keeps the current (fo-98) selection
        Invoke-WaveRefresh
        if ([string]$s.planCombo.Text -like 'fo-98-oldwave*') { Write-Output 'SELFTEST_REFRESH_OK' }
        else { Write-Output ('SELFTEST_REFRESH_FAIL: sel=' + [string]$s.planCombo.Text) }

        # LAYOUT guard (D-0049/D-0060/D-0064): the Refresh button must sit FULLY inside the toolbar and the
        # plan combo must not overrun it -- the rendered-UI defect the old build-only SelfTest missed.
        Update-WaveToolbarLayout
        [System.Windows.Forms.Application]::DoEvents()
        $tbw = [int]$s.toolbar.ClientSize.Width
        $cbR = [int]$s.planCombo.Bounds.Right
        $btnL = [int]$s.refreshBtn.Bounds.Left
        $btnR = [int]$s.refreshBtn.Bounds.Right
        $layoutOk = ($tbw -gt 0) -and ($btnR -le $tbw) -and ($btnL -ge 0) -and ($cbR -le $btnL) -and [bool]$s.refreshBtn.Visible
        if ($layoutOk) { Write-Output 'SELFTEST_LAYOUT_OK' }
        else { Write-Output ('SELFTEST_LAYOUT_FAIL: toolbarW=' + $tbw + ' combo.Right=' + $cbR + ' refresh=' + $s.refreshBtn.Bounds.ToString()) }
    }
    catch { Write-Output ('SELFTEST_RENDER_FAIL: ' + $_.Exception.Message) }
    $form.Dispose()
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
