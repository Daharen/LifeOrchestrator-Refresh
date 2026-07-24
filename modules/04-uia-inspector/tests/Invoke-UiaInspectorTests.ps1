#requires -Version 7.0
# Regression tests for Module 4 (uia.inspector). Run directly or via the executor.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-UiaInspector.ps1'
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

# desktop root, small depth
$envJson = RunEntry @('-Depth', '2', '-MaxElements', '300')
Check 'direct exit 0' ($script:code -eq 0)
$ev = Test-SkillResultEnvelope -Json $envJson
Check 'envelope validates' ([bool]$ev.valid)
if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$o = $envJson | ConvertFrom-Json
Check 'status ok/partial' (@('ok','partial') -contains $o.status)
Check 'element_count > 0' ($o.result.element_count -gt 0)
Check 'target resolved' ($null -ne $o.result.target -and -not [string]::IsNullOrEmpty($o.result.target.control_type))
Check 'two artifacts' (@($o.artifacts).Count -eq 2)
$tree = @($o.artifacts | Where-Object { $_.kind -eq 'markdown' })[0]
$els  = @($o.artifacts | Where-Object { $_.path -like '*elements.json' })[0]
Check 'tree.md exists'     ($null -ne $tree -and (Test-Path -LiteralPath $tree.path))
Check 'elements.json exists'($null -ne $els -and (Test-Path -LiteralPath $els.path))
$edata = Get-Content -LiteralPath $els.path -Raw | ConvertFrom-Json
Check 'elements.json count matches' ($edata.element_count -eq $o.result.element_count)
Check 'elements have control_type' (@($o.result.elements | Where-Object { $_.control_type }).Count -gt 0)

# name filter
$o2 = (RunEntry @('-Depth', '2', '-MaxElements', '300', '-NameFilter', '*')) | ConvertFrom-Json
Check 'name filter matches' ($o2.result.match_count -gt 0)

# target error path
$e = RunEntry @('-Title', 'zzz-no-such-window-zzz')
$ev3 = Test-SkillResultEnvelope -Json $e
$o3 = $e | ConvertFrom-Json
Check 'error envelope valid' ([bool]$ev3.valid)
Check 'error target_not_found' ($o3.status -eq 'error' -and $o3.error.code -eq 'target_not_found')

# wrapped
$inputs = @{ depth = 2; max_elements = 200 } | ConvertTo-Json -Compress
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $inputs
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
