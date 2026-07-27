<#
    Show-ModuleLauncher.ps1 - the Module Launcher & Registry Browser (Widget 02) UI entrypoint.

    A native WinForms window (run STA) that lets a human BROWSE every installed Module (from its
    skill.json manifest) and RUN any one directly through the Module 1 generic wrapper. It is a THIN
    shell over ModuleLauncher.psm1: the UI only builds controls, populates the list from the registry,
    starts the child off the UI thread, polls it from a Timer (so every control update stays on the UI
    thread - no cross-thread marshaling), and renders via the core's Format-* functions. It reimplements
    nothing (discovery = parse skill.json; run = spawn Invoke-Skill.ps1 and parse its report).

    Launch:   launch.bat   (pwsh -NoProfile -STA -File Show-ModuleLauncher.ps1)
    Self-test: pwsh -STA -File Show-ModuleLauncher.ps1 -SelfTest   (builds+disposes the form, prints SELFTEST_FORM_OK)
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$InvokeSkillPath,
    [string]$PwshPath
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ModuleLauncher.psm1') -Force

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:LauncherState = @{
    handle          = $null
    sync            = $null
    startedUtc      = $null
    modules         = @()
    filtered        = @()
    invokeSkillPath = $InvokeSkillPath
    pwshPath        = $PwshPath
}

function Set-LauncherText {
    param($Box, [string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $Box.Text = $norm
}

function Set-SplitterDistanceSafe {
    param($Split, [int]$Distance)
    try { $Split.SplitterDistance = $Distance } catch { }
}

function New-ModuleLauncherForm {
    $mono = [System.Drawing.Font]::new('Consolas', 9.5)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Module Launcher & Registry Browser - Life Orchestrator'
    $form.Size = [System.Drawing.Size]::new(1120, 820)
    $form.MinimumSize = [System.Drawing.Size]::new(880, 620)
    $form.StartPosition = 'CenterScreen'

    # ===== status strip =====
    $status = [System.Windows.Forms.StatusStrip]::new()
    $stateLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $stateLabel.Text = 'State: Idle'
    $sep1 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep1.Text = '   |   '
    $elapsedLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $elapsedLabel.Text = 'Elapsed: 0s'
    $sep2 = [System.Windows.Forms.ToolStripStatusLabel]::new(); $sep2.Text = '   |   '
    $countLabel = [System.Windows.Forms.ToolStripStatusLabel]::new(); $countLabel.Text = 'Modules: -'
    [void]$status.Items.AddRange(@($stateLabel, $sep1, $elapsedLabel, $sep2, $countLabel))

    # ===== outer split: left browser | right run =====
    $outer = [System.Windows.Forms.SplitContainer]::new()
    $outer.Dock = 'Fill'
    $outer.Orientation = 'Vertical'
    Set-SplitterDistanceSafe $outer 360

    # ----- left: module browser -----
    $filterPanel = [System.Windows.Forms.Panel]::new()
    $filterPanel.Dock = 'Top'
    $filterPanel.Height = 60

    $lblModules = [System.Windows.Forms.Label]::new()
    $lblModules.Text = 'Installed Modules (double-click list / select to inspect):'
    $lblModules.Location = [System.Drawing.Point]::new(6, 4)
    $lblModules.AutoSize = $true

    $filterBox = [System.Windows.Forms.TextBox]::new()
    $filterBox.Location = [System.Drawing.Point]::new(8, 26)
    $filterBox.Size = [System.Drawing.Size]::new(230, 22)
    $filterBox.Anchor = 'Top,Left,Right'
    $filterBox.Font = $mono

    $refreshBtn = [System.Windows.Forms.Button]::new()
    $refreshBtn.Text = 'Refresh'
    $refreshBtn.Location = [System.Drawing.Point]::new(244, 25)
    $refreshBtn.Size = [System.Drawing.Size]::new(88, 24)
    $refreshBtn.Anchor = 'Top,Right'

    $filterPanel.Controls.AddRange(@($lblModules, $filterBox, $refreshBtn))

    $moduleSplit = [System.Windows.Forms.SplitContainer]::new()
    $moduleSplit.Dock = 'Fill'
    $moduleSplit.Orientation = 'Horizontal'
    Set-SplitterDistanceSafe $moduleSplit 300

    $moduleList = [System.Windows.Forms.ListBox]::new()
    $moduleList.Dock = 'Fill'
    $moduleList.Font = $mono
    $moduleList.IntegralHeight = $false
    $moduleSplit.Panel1.Controls.Add($moduleList)

    $lblDetail = [System.Windows.Forms.Label]::new()
    $lblDetail.Text = 'Module detail (skill.json manifest)'
    $lblDetail.Dock = 'Top'
    $lblDetail.Height = 18
    $detailBox = [System.Windows.Forms.RichTextBox]::new()
    $detailBox.Dock = 'Fill'
    $detailBox.ReadOnly = $true
    $detailBox.Font = $mono
    $detailBox.WordWrap = $true
    $detailBox.Text = 'Select a module on the left to see its purpose, inputs, and requirements.'
    $moduleSplit.Panel2.Controls.Add($detailBox)
    $moduleSplit.Panel2.Controls.Add($lblDetail)

    # add Fill first, then the docked Top panel
    $outer.Panel1.Controls.Add($moduleSplit)
    $outer.Panel1.Controls.Add($filterPanel)

    # ----- right: inputs + run + results -----
    $topPanel = [System.Windows.Forms.Panel]::new()
    $topPanel.Dock = 'Top'
    $topPanel.Height = 196

    $lblInputs = [System.Windows.Forms.Label]::new()
    $lblInputs.Text = 'Inputs (JSON object passed to the module as -InputsJson):'
    $lblInputs.Dock = 'Top'
    $lblInputs.Height = 18

    $inputsBox = [System.Windows.Forms.TextBox]::new()
    $inputsBox.Multiline = $true
    $inputsBox.WordWrap = $false
    $inputsBox.ScrollBars = 'Both'
    $inputsBox.Dock = 'Fill'
    $inputsBox.Font = $mono
    $inputsBox.Text = '{}'

    $runBar = [System.Windows.Forms.Panel]::new()
    $runBar.Dock = 'Bottom'
    $runBar.Height = 92

    $lblWd = [System.Windows.Forms.Label]::new()
    $lblWd.Text = 'Working dir:'
    $lblWd.Location = [System.Drawing.Point]::new(4, 8)
    $lblWd.AutoSize = $true

    $wdBox = [System.Windows.Forms.TextBox]::new()
    $wdBox.Location = [System.Drawing.Point]::new(84, 5)
    $wdBox.Size = [System.Drawing.Size]::new(560, 22)
    $wdBox.Anchor = 'Top,Left,Right'
    $wdBox.Font = $mono
    try { $wdBox.Text = (Resolve-ModuleLauncherPaths).RepoRoot } catch { $wdBox.Text = '' }

    $runBtn = [System.Windows.Forms.Button]::new()
    $runBtn.Text = 'Run module'
    $runBtn.Location = [System.Drawing.Point]::new(84, 34)
    $runBtn.Size = [System.Drawing.Size]::new(110, 28)

    $cancelBtn = [System.Windows.Forms.Button]::new()
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.Location = [System.Drawing.Point]::new(200, 34)
    $cancelBtn.Size = [System.Drawing.Size]::new(90, 28)
    $cancelBtn.Enabled = $false

    $cautionLabel = [System.Windows.Forms.Label]::new()
    $cautionLabel.Text = 'Runs the selected Module directly through the Module 1 wrapper. No agent, no decision loop.'
    $cautionLabel.Location = [System.Drawing.Point]::new(4, 68)
    $cautionLabel.AutoSize = $true
    $cautionLabel.ForeColor = [System.Drawing.Color]::DimGray

    $runBar.Controls.AddRange(@($lblWd, $wdBox, $runBtn, $cancelBtn, $cautionLabel))

    # add Fill first, then the docked edges
    $topPanel.Controls.Add($inputsBox)
    $topPanel.Controls.Add($lblInputs)
    $topPanel.Controls.Add($runBar)

    $resultSplit = [System.Windows.Forms.SplitContainer]::new()
    $resultSplit.Dock = 'Fill'
    $resultSplit.Orientation = 'Horizontal'
    Set-SplitterDistanceSafe $resultSplit 300

    $lblResult = [System.Windows.Forms.Label]::new()
    $lblResult.Text = 'Result (rendered)'
    $lblResult.Dock = 'Top'
    $lblResult.Height = 18
    $resultBox = [System.Windows.Forms.RichTextBox]::new()
    $resultBox.Dock = 'Fill'
    $resultBox.ReadOnly = $true
    $resultBox.Font = $mono
    $resultBox.WordWrap = $true
    $resultBox.Text = 'Select a module, edit the inputs JSON, and press Run module.'
    $resultSplit.Panel1.Controls.Add($resultBox)
    $resultSplit.Panel1.Controls.Add($lblResult)

    $lblRaw = [System.Windows.Forms.Label]::new()
    $lblRaw.Text = 'Raw invocation report / diagnostics'
    $lblRaw.Dock = 'Top'
    $lblRaw.Height = 18
    $rawBox = [System.Windows.Forms.RichTextBox]::new()
    $rawBox.Dock = 'Fill'
    $rawBox.ReadOnly = $true
    $rawBox.Font = $mono
    $rawBox.WordWrap = $false
    $resultSplit.Panel2.Controls.Add($rawBox)
    $resultSplit.Panel2.Controls.Add($lblRaw)

    $outer.Panel2.Controls.Add($resultSplit)
    $outer.Panel2.Controls.Add($topPanel)

    # ===== timer (UI thread) =====
    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 300

    # add center FIRST so the docked edges claim their space, then edges
    $form.Controls.Add($outer)
    $form.Controls.Add($status)

    $script:LauncherState.form         = $form
    $script:LauncherState.filterBox    = $filterBox
    $script:LauncherState.refreshBtn   = $refreshBtn
    $script:LauncherState.moduleList   = $moduleList
    $script:LauncherState.detailBox    = $detailBox
    $script:LauncherState.inputsBox    = $inputsBox
    $script:LauncherState.wdBox        = $wdBox
    $script:LauncherState.runBtn       = $runBtn
    $script:LauncherState.cancelBtn    = $cancelBtn
    $script:LauncherState.cautionLabel = $cautionLabel
    $script:LauncherState.resultBox    = $resultBox
    $script:LauncherState.rawBox       = $rawBox
    $script:LauncherState.stateLabel   = $stateLabel
    $script:LauncherState.elapsedLabel = $elapsedLabel
    $script:LauncherState.countLabel   = $countLabel
    $script:LauncherState.timer        = $timer
    $script:LauncherState.outerSplit   = $outer
    $script:LauncherState.moduleSplit  = $moduleSplit
    $script:LauncherState.resultSplit  = $resultSplit

    $moduleList.Add_SelectedIndexChanged({ Show-SelectedModule })
    $filterBox.Add_TextChanged({ Update-ModuleFilter })
    $refreshBtn.Add_Click({ Update-ModuleRegistry })
    $runBtn.Add_Click({ Start-LauncherRun })
    $cancelBtn.Add_Click({ Stop-LauncherRun })
    $timer.Add_Tick({ Update-LauncherRun })
    $form.Add_Shown({ Set-InitialLayout; Update-ModuleRegistry })
    $form.Add_FormClosing({
            if ($script:LauncherState.handle) { try { Stop-ModuleProcess -Handle $script:LauncherState.handle } catch { } }
        })

    return $form
}

function Update-ModuleRegistry {
    $st = $script:LauncherState
    try { $st.modules = @(Get-ModuleRegistry) } catch { $st.modules = @() }
    Update-ModuleFilter
}

function Update-ModuleFilter {
    $st = $script:LauncherState
    $q = ''
    try { $q = [string]$st.filterBox.Text } catch { }
    $q = $q.Trim().ToLowerInvariant()
    $subset = @()
    if ($q) {
        $subset = @($st.modules | Where-Object {
                ([string]$_.skill_id).ToLowerInvariant().Contains($q) -or
                ([string]$_.name).ToLowerInvariant().Contains($q) -or
                ([string]$_.folder_name).ToLowerInvariant().Contains($q)
            })
    }
    else { $subset = @($st.modules) }
    $st.filtered = $subset
    $st.moduleList.BeginUpdate()
    $st.moduleList.Items.Clear()
    foreach ($e in $subset) { [void]$st.moduleList.Items.Add((Format-ModuleListLine -Entry $e)) }
    $st.moduleList.EndUpdate()
    $st.countLabel.Text = ('Modules: ' + @($st.modules).Count + $(if ($q) { ' (' + @($subset).Count + ' shown)' } else { '' }))
}

function Get-SelectedEntry {
    $st = $script:LauncherState
    $idx = $st.moduleList.SelectedIndex
    if ($idx -lt 0 -or $idx -ge @($st.filtered).Count) { return $null }
    return @($st.filtered)[$idx]
}

function Show-SelectedModule {
    $st = $script:LauncherState
    $e = Get-SelectedEntry
    if ($null -eq $e) { return }
    Set-LauncherText $st.detailBox (Format-ModuleDetail -Entry $e)
    if ([bool]$e.manifest_ok) {
        Set-LauncherText $st.inputsBox (Get-ModuleInputTemplate -Entry $e)
        $fs = ''
        if ($e.requirements) { try { $fs = [string]$e.requirements.filesystem } catch { } }
        if ($fs -match 'write') {
            $st.cautionLabel.Text = 'NOTE: this module can create or modify files (filesystem=' + $fs + '). It runs for real - not a dry run.'
            $st.cautionLabel.ForeColor = [System.Drawing.Color]::Firebrick
        }
        else {
            $st.cautionLabel.Text = 'Read-only / safe module (filesystem=' + $(if ($fs) { $fs } else { 'none' }) + ').'
            $st.cautionLabel.ForeColor = [System.Drawing.Color]::DimGray
        }
    }
    else {
        Set-LauncherText $st.inputsBox '{}'
        $st.cautionLabel.Text = 'This module has an unreadable manifest and cannot be launched.'
        $st.cautionLabel.ForeColor = [System.Drawing.Color]::Firebrick
    }
}

function Start-LauncherRun {
    $st = $script:LauncherState
    $e = Get-SelectedEntry
    if ($null -eq $e) {
        [void][System.Windows.Forms.MessageBox]::Show('Select a module first.', 'Module Launcher')
        return
    }
    if (-not [bool]$e.manifest_ok -or -not [bool]$e.entrypoint_exists) {
        [void][System.Windows.Forms.MessageBox]::Show('This module cannot be launched (bad manifest or missing entrypoint).', 'Module Launcher')
        return
    }
    $inputs = [string]$st.inputsBox.Text
    if ([string]::IsNullOrWhiteSpace($inputs)) { $inputs = '{}' }
    try { [void]($inputs | ConvertFrom-Json) }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(("The inputs box is not valid JSON:`r`n" + $_.Exception.Message), 'Module Launcher')
        return
    }

    Set-LauncherText $st.resultBox ("Running " + [string]$e.skill_id + " through the Module 1 wrapper ...`r`n(loading any models this module needs can take a moment)")
    $st.rawBox.Text = ''
    $st.runBtn.Enabled = $false
    $st.refreshBtn.Enabled = $false
    $st.cancelBtn.Enabled = $true
    $st.stateLabel.Text = 'State: Running ' + [string]$e.skill_id
    $st.startedUtc = [datetime]::UtcNow
    $sync = [hashtable]::Synchronized(@{})
    $st.sync = $sync
    try {
        $h = Start-ModuleProcess -SkillDir $e.skill_dir -InputsJson $inputs `
            -WorkingDir ($st.wdBox.Text.Trim()) `
            -InvokeSkillPath $st.invokeSkillPath -PwshPath $st.pwshPath -Sync $sync
        $st.handle = $h
        $st.timer.Start()
    }
    catch {
        $st.stateLabel.Text = 'State: Error'
        Set-LauncherText $st.resultBox ("Failed to start the module:`r`n" + $_.Exception.Message)
        $st.runBtn.Enabled = $true
        $st.refreshBtn.Enabled = $true
        $st.cancelBtn.Enabled = $false
    }
}

function Update-LauncherRun {
    $st = $script:LauncherState
    if (-not $st.handle) { $st.timer.Stop(); return }
    $elapsed = [int]([datetime]::UtcNow - $st.startedUtc).TotalSeconds
    $st.elapsedLabel.Text = "Elapsed: ${elapsed}s"
    if (-not $st.handle.Process.HasExited) { return }

    $st.timer.Stop()
    $run = Complete-ModuleRun -Handle $st.handle
    Set-LauncherText $st.resultBox (Format-ModuleResult -Run $run)
    if ($run.report) { Set-LauncherText $st.rawBox ($run.report | ConvertTo-Json -Depth 14) }
    else { Set-LauncherText $st.rawBox ("RAW STDOUT:`r`n" + $run.raw_stdout + "`r`n`r`nSTDERR (tail):`r`n" + $run.stderr_tail) }
    $st.stateLabel.Text = if ($run.ok) { 'State: Done (' + [string]$run.skill_status + ')' } else { 'State: Finished (' + [string]$run.skill_status + ')' }
    $st.runBtn.Enabled = $true
    $st.refreshBtn.Enabled = $true
    $st.cancelBtn.Enabled = $false
    $st.handle = $null
}

function Stop-LauncherRun {
    $st = $script:LauncherState
    if ($st.handle) { try { Stop-ModuleProcess -Handle $st.handle } catch { } }
    $st.timer.Stop()
    $st.stateLabel.Text = 'State: Cancelled'
    $st.resultBox.AppendText("`r`n`r`n[cancelled by user]")
    $st.runBtn.Enabled = $true
    $st.refreshBtn.Enabled = $true
    $st.cancelBtn.Enabled = $false
    $st.handle = $null
}

function Set-InitialLayout {
    # Set the splitter positions AFTER the form is shown, when the containers have their real size.
    # (Setting SplitterDistance at construction fails silently -- the container is still ~150px, so a
    #  360px distance is out of range -- which is why the panels were mis-sized on first paint.)
    $st = $script:LauncherState
    Set-SplitterDistanceSafe $st.outerSplit 360                                  # left browser column width
    Set-SplitterDistanceSafe $st.moduleSplit ([int]($st.moduleSplit.Height * 0.55))  # list over detail
    Set-SplitterDistanceSafe $st.resultSplit ([int]($st.resultSplit.Height * 0.6))   # result over raw
}

# ----- entry -----
$form = New-ModuleLauncherForm
if ($SelfTest) {
    $form.Dispose()
    Write-Output 'SELFTEST_FORM_OK'
    return
}
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
