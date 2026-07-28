<#
    Show-AgentConsole.ps1 - the Local Agent Console (Widget 01) UI entrypoint.

    A native WinForms window (run STA) that lets a human submit a goal to agent.local (#21)
    and read its result envelope + child transcript. It is a THIN shell over AgentConsole.psm1:
    the UI only builds controls, starts the child off the UI thread, polls it from a Timer
    (so every control update stays on the UI thread - no cross-thread marshaling), and renders
    via the core's Format-AgentTranscript. It reimplements nothing.

    Launch:   launch.bat   (pwsh -NoProfile -STA -File Show-AgentConsole.ps1)
    Self-test: pwsh -STA -File Show-AgentConsole.ps1 -SelfTest   (builds+disposes the form, prints SELFTEST_FORM_OK)
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$AgentLocalPath,
    [string]$RouteToolsPath,
    [string]$PwshPath
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AgentConsole.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ConsoleState = @{
    handle         = $null
    sync           = $null
    startedUtc     = $null
    mode           = 'run'
    agentLocalPath = $AgentLocalPath
    routeToolsPath = $RouteToolsPath
    pwshPath       = $PwshPath
}

function New-AgentConsoleForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Local Agent Console - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1020, 820)
    $form.MinimumSize = [System.Drawing.Size]::new(760, 600)
    $form.StartPosition = 'CenterScreen'

    # ----- top panel: goal + options -----
    $top = [System.Windows.Forms.Panel]::new()
    $top.Dock = 'Top'
    $top.Height = 196

    $lblGoal = [System.Windows.Forms.Label]::new()
    $lblGoal.Text = 'Goal (what should the local agent do?):'
    $lblGoal.Location = [System.Drawing.Point]::new(10, 6)
    $lblGoal.AutoSize = $true

    $goalBox = [System.Windows.Forms.TextBox]::new()
    $goalBox.Multiline = $true
    $goalBox.WordWrap = $true
    $goalBox.ScrollBars = 'Vertical'
    $goalBox.Location = [System.Drawing.Point]::new(12, 26)
    $goalBox.Size = [System.Drawing.Size]::new(980, 62)
    $goalBox.Anchor = 'Top,Left,Right'
    $goalBox.Font = $mono

    $lblWd = [System.Windows.Forms.Label]::new()
    $lblWd.Text = 'Working dir:'
    $lblWd.Location = [System.Drawing.Point]::new(12, 100)
    $lblWd.AutoSize = $true

    $wdBox = [System.Windows.Forms.TextBox]::new()
    $wdBox.Location = [System.Drawing.Point]::new(92, 97)
    $wdBox.Size = [System.Drawing.Size]::new(430, 22)
    $wdBox.Anchor = 'Top,Left,Right'
    try { $wdBox.Text = (Resolve-AgentConsolePaths).RepoRoot } catch { $wdBox.Text = '' }

    $lblSteps = [System.Windows.Forms.Label]::new()
    $lblSteps.Text = 'Max steps:'
    $lblSteps.Location = [System.Drawing.Point]::new(540, 100)
    $lblSteps.AutoSize = $true
    $lblSteps.Anchor = 'Top,Right'

    $stepsBox = [System.Windows.Forms.NumericUpDown]::new()
    $stepsBox.Location = [System.Drawing.Point]::new(612, 97)
    $stepsBox.Size = [System.Drawing.Size]::new(52, 22)
    $stepsBox.Minimum = 1
    $stepsBox.Maximum = 20
    $stepsBox.Value = 10
    $stepsBox.Anchor = 'Top,Right'

    $dryRunBox = [System.Windows.Forms.CheckBox]::new()
    $dryRunBox.Text = 'Dry run (plan only - no tool is invoked)'
    $dryRunBox.Location = [System.Drawing.Point]::new(680, 98)
    $dryRunBox.AutoSize = $true
    $dryRunBox.Checked = $false
    $dryRunBox.Anchor = 'Top,Right'

    # ----- auto-ramp (Governor Phase 3) opt-in row -----
    $autoRampBox = [System.Windows.Forms.CheckBox]::new()
    $autoRampBox.Text = 'Auto-ramp (Governor Phase 3)'
    $autoRampBox.Location = [System.Drawing.Point]::new(12, 128)
    $autoRampBox.AutoSize = $true
    $autoRampBox.Checked = $false

    $lblContract = [System.Windows.Forms.Label]::new()
    $lblContract.Text = 'Success contract (.json):'
    $lblContract.Location = [System.Drawing.Point]::new(250, 130)
    $lblContract.AutoSize = $true
    $lblContract.Enabled = $false

    $contractBox = [System.Windows.Forms.TextBox]::new()
    $contractBox.Location = [System.Drawing.Point]::new(410, 127)
    $contractBox.Size = [System.Drawing.Size]::new(548, 22)
    $contractBox.Anchor = 'Top,Left,Right'
    $contractBox.Enabled = $false

    $browseBtn = [System.Windows.Forms.Button]::new()
    $browseBtn.Text = '...'
    $browseBtn.Location = [System.Drawing.Point]::new(962, 126)
    $browseBtn.Size = [System.Drawing.Size]::new(30, 24)
    $browseBtn.Anchor = 'Top,Right'
    $browseBtn.Enabled = $false

    # contract path only matters with auto-ramp on -- gate the fields to make that clear.
    $autoRampBox.Add_CheckedChanged({
            $on = [bool]$autoRampBox.Checked
            $lblContract.Enabled = $on
            $contractBox.Enabled = $on
            $browseBtn.Enabled = $on
        })
    $browseBtn.Add_Click({
            try {
                $dlg = [System.Windows.Forms.OpenFileDialog]::new()
                $dlg.Filter = 'Success contract (*.json)|*.json|All files (*.*)|*.*'
                $dlg.Title = 'Select a pre-frozen lifeorch.goal_verification/0.1 contract file'
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $contractBox.Text = $dlg.FileName }
            }
            catch { }
        })

    $planBtn = [System.Windows.Forms.Button]::new()
    $planBtn.Text = 'Plan'
    $planBtn.Location = [System.Drawing.Point]::new(12, 162)
    $planBtn.Size = [System.Drawing.Size]::new(90, 26)

    $runBtn = [System.Windows.Forms.Button]::new()
    $runBtn.Text = 'Run'
    $runBtn.Location = [System.Drawing.Point]::new(108, 162)
    $runBtn.Size = [System.Drawing.Size]::new(90, 26)

    $cancelBtn = [System.Windows.Forms.Button]::new()
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.Location = [System.Drawing.Point]::new(204, 162)
    $cancelBtn.Size = [System.Drawing.Size]::new(90, 26)
    $cancelBtn.Enabled = $false

    $lblHint = [System.Windows.Forms.Label]::new()
    $lblHint.Text = 'Plan = route.tools only.  Run = route + execute.  Auto-ramp: ramp M0->M1->S0 until the success contract verifies.'
    $lblHint.Location = [System.Drawing.Point]::new(304, 168)
    $lblHint.AutoSize = $true
    $lblHint.ForeColor = [System.Drawing.Color]::DimGray

    $top.Controls.AddRange(@($lblGoal, $goalBox, $lblWd, $wdBox, $lblSteps, $stepsBox, $dryRunBox,
            $autoRampBox, $lblContract, $contractBox, $browseBtn,
            $planBtn, $runBtn, $cancelBtn, $lblHint))

    # ----- center: split transcript / raw -----
    $split = [System.Windows.Forms.SplitContainer]::new()
    $split.Dock = 'Fill'
    $split.Orientation = 'Horizontal'
    $split.SplitterDistance = 380

    $lblT = [System.Windows.Forms.Label]::new()
    $lblT.Text = 'Transcript (result + child steps)'
    $lblT.Dock = 'Top'
    $lblT.Height = 18
    $transcriptBox = [System.Windows.Forms.RichTextBox]::new()
    $transcriptBox.Dock = 'Fill'
    $transcriptBox.ReadOnly = $true
    $transcriptBox.Font = $mono
    $transcriptBox.WordWrap = $false
    $transcriptBox.Text = 'Type a goal above and press Run. The local agent decides which tool to use, generates its arguments, invokes it, and reports back here.'
    $split.Panel1.Controls.Add($transcriptBox)
    $split.Panel1.Controls.Add($lblT)

    $lblR = [System.Windows.Forms.Label]::new()
    $lblR.Text = 'Raw result envelope / diagnostics'
    $lblR.Dock = 'Top'
    $lblR.Height = 18
    $rawBox = [System.Windows.Forms.RichTextBox]::new()
    $rawBox.Dock = 'Fill'
    $rawBox.ReadOnly = $true
    $rawBox.Font = $mono
    $rawBox.WordWrap = $false
    $split.Panel2.Controls.Add($rawBox)
    $split.Panel2.Controls.Add($lblR)

    # ----- status strip -----
    $status = [System.Windows.Forms.StatusStrip]::new()
    $stateLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $stateLabel.Text = 'State: Idle'
    $sep1 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep1.Text = '   |   '
    $elapsedLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $elapsedLabel.Text = 'Elapsed: 0s'
    $sep2 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep2.Text = '   |   '
    $costLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $costLabel.Text = 'Cost: -'
    [void]$status.Items.AddRange(@($stateLabel, $sep1, $elapsedLabel, $sep2, $costLabel))

    # ----- timer (UI thread) -----
    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 300

    # add center FIRST so the docked edges claim their space, then edges
    $form.Controls.Add($split)
    $form.Controls.Add($top)
    $form.Controls.Add($status)

    $script:ConsoleState.form          = $form
    $script:ConsoleState.goalBox       = $goalBox
    $script:ConsoleState.wdBox         = $wdBox
    $script:ConsoleState.stepsBox      = $stepsBox
    $script:ConsoleState.dryRunBox     = $dryRunBox
    $script:ConsoleState.autoRampBox   = $autoRampBox
    $script:ConsoleState.contractBox   = $contractBox
    $script:ConsoleState.planBtn       = $planBtn
    $script:ConsoleState.runBtn        = $runBtn
    $script:ConsoleState.cancelBtn     = $cancelBtn
    $script:ConsoleState.transcriptBox = $transcriptBox
    $script:ConsoleState.rawBox        = $rawBox
    $script:ConsoleState.stateLabel    = $stateLabel
    $script:ConsoleState.elapsedLabel  = $elapsedLabel
    $script:ConsoleState.costLabel     = $costLabel
    $script:ConsoleState.timer         = $timer

    $planBtn.Add_Click({ Start-ConsolePlan })
    $runBtn.Add_Click({ Start-ConsoleRun })
    $cancelBtn.Add_Click({ Stop-ConsoleRun })
    $timer.Add_Tick({ Update-ConsoleRun })
    $form.Add_FormClosing({
            if ($script:ConsoleState.handle) { try { Stop-AgentLocalProcess -Handle $script:ConsoleState.handle } catch { } }
        })

    return $form
}

function Set-ConsoleText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Start-ConsolePlan {
    $st = $script:ConsoleState
    $goal = $st.goalBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($goal)) {
        [void][System.Windows.Forms.MessageBox]::Show('Please enter a goal first.', 'Local Agent Console')
        return
    }
    Set-ConsoleText $st.transcriptBox "Planning (route.tools) ...`r`n(selecting the tools this goal needs - loading the router model can take a moment)"
    $st.rawBox.Text = ''
    $st.mode = 'plan'
    $st.planBtn.Enabled = $false
    $st.runBtn.Enabled = $false
    $st.cancelBtn.Enabled = $true
    $st.stateLabel.Text = 'State: Planning'
    $st.costLabel.Text = 'Cost: -'
    $st.startedUtc = [datetime]::UtcNow
    $sync = [hashtable]::Synchronized(@{})
    $st.sync = $sync
    try {
        $h = Start-RouteToolsProcess -Goal $goal -Sync $sync `
            -RouteToolsPath $st.routeToolsPath `
            -PwshPath $st.pwshPath
        $st.handle = $h
        $st.timer.Start()
    }
    catch {
        $st.stateLabel.Text = 'State: Error'
        Set-ConsoleText $st.transcriptBox ("Failed to start route.tools:`r`n" + $_.Exception.Message)
        $st.planBtn.Enabled = $true
        $st.runBtn.Enabled = $true
        $st.cancelBtn.Enabled = $false
    }
}

function Start-ConsoleRun {
    $st = $script:ConsoleState
    $goal = $st.goalBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($goal)) {
        [void][System.Windows.Forms.MessageBox]::Show('Please enter a goal first.', 'Local Agent Console')
        return
    }
    $autoRamp = [bool]$st.autoRampBox.Checked
    $contractPath = $st.contractBox.Text.Trim()
    $runMsg = if ($autoRamp) {
        "Running agent.local -AutoRamp (Governor Phase 3: route + ramp M0->M1->S0) ...`r`n(goal submitted - loading + ramping the local models can take a minute or more)"
    }
    else {
        "Running agent.local (route + execute) ...`r`n(goal submitted - loading the local models can take a minute or two)"
    }
    Set-ConsoleText $st.transcriptBox $runMsg
    $st.rawBox.Text = ''
    $st.mode = 'run'
    $st.planBtn.Enabled = $false
    $st.runBtn.Enabled = $false
    $st.cancelBtn.Enabled = $true
    $st.stateLabel.Text = if ($autoRamp) { 'State: Running (auto-ramp)' } else { 'State: Running' }
    $st.costLabel.Text = 'Cost: -'
    $st.startedUtc = [datetime]::UtcNow
    $sync = [hashtable]::Synchronized(@{})
    $st.sync = $sync
    try {
        $h = Start-AgentLocalProcess -Goal $goal `
            -WorkingDir ($st.wdBox.Text.Trim()) `
            -MaxSteps ([int]$st.stepsBox.Value) `
            -DryRun:([bool]$st.dryRunBox.Checked) `
            -Route `
            -Sync $sync `
            -AgentLocalPath $st.agentLocalPath `
            -PwshPath $st.pwshPath `
            -AutoRamp:$autoRamp `
            -SuccessContractPath $contractPath
        $st.handle = $h
        $st.timer.Start()
    }
    catch {
        $st.stateLabel.Text = 'State: Error'
        Set-ConsoleText $st.transcriptBox ("Failed to start agent.local:`r`n" + $_.Exception.Message)
        $st.planBtn.Enabled = $true
        $st.runBtn.Enabled = $true
        $st.cancelBtn.Enabled = $false
    }
}

function Update-ConsoleRun {
    $st = $script:ConsoleState
    if (-not $st.handle) { $st.timer.Stop(); return }
    $elapsed = [int]([datetime]::UtcNow - $st.startedUtc).TotalSeconds
    $st.elapsedLabel.Text = "Elapsed: ${elapsed}s"
    if (-not $st.handle.Process.HasExited) { return }

    $st.timer.Stop()
    if ($st.mode -eq 'plan') {
        $run = Complete-RouteToolsRun -Handle $st.handle
        Set-ConsoleText $st.transcriptBox (Format-RoutePlan -Run $run)
        if ($run.envelope) { Set-ConsoleText $st.rawBox ($run.envelope | ConvertTo-Json -Depth 12) }
        else { Set-ConsoleText $st.rawBox ("RAW STDOUT:`r`n" + $run.raw_stdout + "`r`n`r`nSTDERR (tail):`r`n" + $run.stderr_tail) }
        $rc = if ($run.result) { Get-Prop $run.result 'count' } else { $null }
        $st.costLabel.Text = ('Plan: ' + [string]$rc + ' tool(s) selected')
        $st.stateLabel.Text = if ($run.ok) { 'State: Planned' } else { 'State: Plan finished (' + $run.status + ')' }
    }
    else {
        $run = Complete-AgentLocalRun -Handle $st.handle
        Set-ConsoleText $st.transcriptBox (Format-AgentTranscript -Run $run)
        if ($run.envelope) { Set-ConsoleText $st.rawBox ($run.envelope | ConvertTo-Json -Depth 12) }
        else { Set-ConsoleText $st.rawBox ("RAW STDOUT:`r`n" + $run.raw_stdout + "`r`n`r`nSTDERR (tail):`r`n" + $run.stderr_tail) }
        $rr = if ($run.result) { $run.result } else { $null }
        $finalStatus = if ($rr) { Get-Prop $rr 'final_status' } else { $null }
        $cost = if ($rr) { Get-Prop $rr 'cost' } else { $null }
        if ($cost) {
            $st.costLabel.Text = ('Cost: ' + [string](Get-Prop $cost 'total_gateway_calls' '?') + ' gateway calls, ' + [string](Get-Prop $cost 'total_tokens' '?') + ' tokens')
        }
        elseif ($finalStatus) {
            $st.costLabel.Text = ('Auto-ramp: ' + [string]$finalStatus + ' (' + [string](Get-Prop $rr 'model_swaps' 0) + ' swap(s))')
        }
        $st.stateLabel.Text = if ($finalStatus) { 'State: ' + [string]$finalStatus } elseif ($run.ok) { 'State: Done' } else { 'State: Finished (' + $run.status + ')' }
    }
    $st.planBtn.Enabled = $true
    $st.runBtn.Enabled = $true
    $st.cancelBtn.Enabled = $false
    $st.handle = $null
}

function Stop-ConsoleRun {
    $st = $script:ConsoleState
    if ($st.handle) { try { Stop-AgentLocalProcess -Handle $st.handle } catch { } }
    $st.timer.Stop()
    $st.stateLabel.Text = 'State: Cancelled'
    $st.transcriptBox.AppendText("`r`n`r`n[cancelled by user]")
    $st.planBtn.Enabled = $true
    $st.runBtn.Enabled = $true
    $st.cancelBtn.Enabled = $false
    $st.handle = $null
}

# ----- entry -----
$form = New-AgentConsoleForm
if ($SelfTest) {
    $form.Dispose()
    Write-Output 'SELFTEST_FORM_OK'
    return
}
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
