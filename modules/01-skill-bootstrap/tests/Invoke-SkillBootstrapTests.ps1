#requires -Version 7.0
# Regression tests for Module 1 (skill.bootstrap). Run directly or via the executor.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'lib/SkillContract.psm1') -Force
$skillDir = Join-Path $moduleRoot 'skills/ref.echo'
$script:fail = 0
function Check([string]$name, [bool]$cond) {
    if ($cond) { [Console]::Out.WriteLine("PASS  $name") }
    else { [Console]::Out.WriteLine("FAIL  $name"); $script:fail++ }
}

# 1. Manifest validates.
$mv = Test-SkillManifest -Path (Join-Path $skillDir 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

# 2. Direct invocation emits a valid envelope.
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$out = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $skillDir 'Invoke-RefEcho.ps1') -Message 'unit' -Repeat 2
$code = $LASTEXITCODE; $ErrorActionPreference = $prev
Check 'direct invocation exits 0' ($code -eq 0)
$envJson = ([string]($out | Out-String)).Trim()
$ev = Test-SkillResultEnvelope -Json $envJson
Check 'direct envelope validates' ([bool]$ev.valid)
if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$obj = $envJson | ConvertFrom-Json
Check 'status is ok' ($obj.status -eq 'ok')
Check 'echoed content correct' ($obj.result.echoed -eq "unit`nunit")
Check 'artifact listed' (@($obj.artifacts).Count -ge 1)
Check 'artifact file exists' (Test-Path -LiteralPath (@($obj.artifacts)[0].path))

# 3. Wrapper reports manifest+envelope valid.
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $moduleRoot 'Invoke-Skill.ps1') -SkillDir $skillDir -InputsJson '{"message":"wrap","repeat":1}'
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

# 4. Error path: repeat < 1 yields status=error with a valid error envelope.
$eout = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $skillDir 'Invoke-RefEcho.ps1') -Message 'x' -Repeat 0
$eobj = ([string]($eout | Out-String)).Trim() | ConvertFrom-Json
$eev = Test-SkillResultEnvelope -Envelope $eobj
Check 'error envelope validates' ([bool]$eev.valid)
Check 'error status is error' ($eobj.status -eq 'error')

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 }
else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
