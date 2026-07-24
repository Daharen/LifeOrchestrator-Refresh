#requires -Version 7.0
# Regression tests for Module 3 (proc.observer). Run directly or via the executor.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-ProcObserver.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}

$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

$envJson = RunEntry @()
Check 'direct exit 0' ($script:code -eq 0)
$ev = Test-SkillResultEnvelope -Json $envJson
Check 'envelope validates' ([bool]$ev.valid)
if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$o = $envJson | ConvertFrom-Json
Check 'status ok/partial' (@('ok','partial') -contains $o.status)
Check 'process_count > 0' ($o.result.process_count -gt 0)
Check 'window_count > 0' ($o.result.window_count -gt 0)
Check 'three artifacts' (@($o.artifacts).Count -eq 3)
$rep = @($o.artifacts | Where-Object { $_.kind -eq 'markdown' })[0]
$pj  = @($o.artifacts | Where-Object { $_.path -like '*processes.json' })[0]
$wj  = @($o.artifacts | Where-Object { $_.path -like '*windows.json' })[0]
Check 'report.md exists'     ($null -ne $rep -and (Test-Path -LiteralPath $rep.path))
Check 'processes.json exists'($null -ne $pj  -and (Test-Path -LiteralPath $pj.path))
Check 'windows.json exists'  ($null -ne $wj  -and (Test-Path -LiteralPath $wj.path))
$pdata = Get-Content -LiteralPath $pj.path -Raw | ConvertFrom-Json
Check 'processes.json count matches' ($pdata.count -eq $o.result.process_count)

$o2 = (RunEntry @('-NameFilter', 'pwsh*')) | ConvertFrom-Json
Check 'name filter finds pwsh' ($o2.result.process_count -gt 0)

$o3json = RunEntry @('-NameFilter', 'zzz-no-such-proc-zzz')
$ev3 = Test-SkillResultEnvelope -Json $o3json
$o3 = $o3json | ConvertFrom-Json
Check 'no-match envelope valid'  ([bool]$ev3.valid)
Check 'no-match process_count 0' ($o3.result.process_count -eq 0)

$inputs = @{ visible_only = $true; name_filter = 'pwsh*' } | ConvertTo-Json -Compress
$rep2 = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $inputs
$repObj = ([string]($rep2 | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
