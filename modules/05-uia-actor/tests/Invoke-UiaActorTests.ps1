#requires -Version 7.0
# Regression tests for Module 5 (uia.actor). Run directly or via the executor.
# Core checks (manifest, dry-run, error paths, wrapper) are side-effect-free. Live-action checks spin up a
# self-contained WinForms probe window (Start-UiaProbe.ps1) and really invoke/toggle/setvalue against it,
# self-verifying via UIA state + a signal file, with guaranteed teardown.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-UiaActor.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$probe   = Join-Path $PSScriptRoot 'Start-UiaProbe.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function WaitFile([string]$p, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) { if (Test-Path -LiteralPath $p) { return $true }; Start-Sleep -Milliseconds 300 }
    return (Test-Path -LiteralPath $p)
}

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

# ---- dry-run against desktop root (path '' = the target itself), side-effect free ----
$d = RunEntry @('-Action','focus','-Path','','-DryRun')
Check 'dry-run exit 0' ($script:code -eq 0)
$ev = Test-SkillResultEnvelope -Json $d
Check 'dry-run envelope validates' ([bool]$ev.valid)
if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$od = $d | ConvertFrom-Json
Check 'dry-run status ok/partial' (@('ok','partial') -contains $od.status)
Check 'dry-run performed=false' ($od.result.performed -eq $false)
Check 'dry-run dry_run=true' ($od.result.dry_run -eq $true)
Check 'dry-run resolved element' ($null -ne $od.result.resolved_element)

# ---- error paths (all side-effect free, must be valid error envelopes) ----
$e1 = RunEntry @('-Action','invoke') | ConvertFrom-Json
Check 'no_locator error' ($e1.status -eq 'error' -and $e1.error.code -eq 'no_locator')

$e2 = RunEntry @('-Action','frobnicate','-ControlType','Button') | ConvertFrom-Json
Check 'invalid_action error' ($e2.status -eq 'error' -and $e2.error.code -eq 'invalid_action')

$e3 = RunEntry @('-Action','setvalue','-ControlType','Edit') | ConvertFrom-Json
Check 'value_required error' ($e3.status -eq 'error' -and $e3.error.code -eq 'value_required')

$e4txt = RunEntry @('-Action','focus','-Title','zzz-no-such-window-zzz','-ControlType','Button')
$ev4 = Test-SkillResultEnvelope -Json $e4txt
$e4 = $e4txt | ConvertFrom-Json
Check 'target_not_found valid envelope' ([bool]$ev4.valid)
Check 'target_not_found error' ($e4.status -eq 'error' -and $e4.error.code -eq 'target_not_found')

$e5 = RunEntry @('-Action','focus','-AutomationId','zz-no-such-aid-zz','-Depth','1','-MaxElements','60') | ConvertFrom-Json
Check 'element_not_found error' ($e5.status -eq 'error' -and $e5.error.code -eq 'element_not_found')

# ---- wrapper (Module 1) ----
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson '{"action":"focus","path":"","dry_run":true}'
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

# ---- live actions against a self-contained WinForms probe window ----
$token = [Guid]::NewGuid().ToString('N').Substring(0,8)
$signalDir = Join-Path $env:TEMP "lo-uia-probe-$token"
$titleGlob = "LO UIA Probe $token*"
$val = "hello-uia-$token"
$proc = $null
try {
    $proc = Start-Process -FilePath $PwshPath -PassThru -ArgumentList @('-NoLogo','-NoProfile','-File',$probe,'-Token',$token,'-SignalDir',$signalDir,'-Seconds','120')
    $ready = WaitFile (Join-Path $signalDir 'ready.txt') 25
    Check 'probe window ready' $ready

    if ($ready) {
        # setvalue (ValuePattern) — read back to confirm
        $sv = RunEntry @('-Title',$titleGlob,'-Action','setvalue','-ControlType','Edit','-Value',$val) | ConvertFrom-Json
        Check 'setvalue performed' ($sv.status -eq 'ok' -and $sv.result.performed -eq $true)
        Check 'setvalue after==value' ($null -ne $sv.result.after_state -and $sv.result.after_state.value -eq $val)

        # toggle (TogglePattern) — Off -> On
        $tg = RunEntry @('-Title',$titleGlob,'-Action','toggle','-ControlType','CheckBox') | ConvertFrom-Json
        Check 'toggle performed' ($tg.status -eq 'ok' -and $tg.result.performed -eq $true)
        Check 'toggle Off->On' ($tg.result.before_state.toggle_state -eq 'Off' -and $tg.result.after_state.toggle_state -eq 'On')

        # soft: automation_id locator (only asserted if WinForms exposed one)
        $aid = [string]$sv.result.resolved_element.automation_id
        if (-not [string]::IsNullOrWhiteSpace($aid)) {
            $fa = RunEntry @('-Title',$titleGlob,'-Action','focus','-AutomationId',$aid,'-DryRun') | ConvertFrom-Json
            Check 'automation_id locator resolves' ($null -ne $fa.result.resolved_element)
        } else {
            [Console]::Out.WriteLine("NOTE  probe exposed no AutomationId (WinForms) — automation_id locator asserted only via path/name/control_type")
        }

        # dry-run invoke must NOT click
        $di = RunEntry @('-Title',$titleGlob,'-Action','invoke','-ControlType','Button','-DryRun') | ConvertFrom-Json
        Check 'dry invoke not performed' ($di.result.performed -eq $false -and $di.result.actionable -eq $true)
        Check 'dry invoke left button un-clicked' (-not (Test-Path -LiteralPath (Join-Path $signalDir 'clicked.txt')))

        # real invoke (InvokePattern) — confirmed via signal file (also closes the window)
        $iv = RunEntry @('-Title',$titleGlob,'-Action','invoke','-ControlType','Button') | ConvertFrom-Json
        Check 'invoke performed' ($iv.status -eq 'ok' -and $iv.result.performed -eq $true)
        $clicked = WaitFile (Join-Path $signalDir 'clicked.txt') 6
        Check 'invoke fired click handler' $clicked
        if ($clicked) {
            $body = [string]([System.IO.File]::ReadAllText((Join-Path $signalDir 'clicked.txt')))
            Check 'clicked.txt carries set value' ($body -eq $val)
        }
    }
}
finally {
    try { if ($null -ne $proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
    Start-Sleep -Milliseconds 300
    try { if (Test-Path -LiteralPath $signalDir) { Remove-Item -LiteralPath $signalDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
