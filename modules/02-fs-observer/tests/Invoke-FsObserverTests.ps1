#requires -Version 7.0
# Regression tests for Module 2 (fs.observer). Run directly or via the executor.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot                 # modules/02-fs-observer
$modulesDir = Split-Path -Parent $moduleRoot                   # modules
$repoRoot   = Split-Path -Parent $modulesDir                   # LifeOrchestrator-Refresh
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-FsObserver.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}

# 1. manifest
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

# 2. direct tree over the repo root
$envJson = RunEntry @('-Path', $repoRoot, '-Depth', '2')
Check 'direct exit 0' ($script:code -eq 0)
$ev = Test-SkillResultEnvelope -Json $envJson
Check 'envelope validates' ([bool]$ev.valid)
if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$o = $envJson | ConvertFrom-Json
Check 'status ok/partial' (@('ok','partial') -contains $o.status)
Check 'entry_count > 0' ($o.result.entry_count -gt 0)
Check 'counts consistent' (($o.result.dir_count + $o.result.file_count) -le $o.result.entry_count)
Check 'two artifacts' (@($o.artifacts).Count -eq 2)
$tree  = @($o.artifacts | Where-Object { $_.kind -eq 'markdown' })[0]
$index = @($o.artifacts | Where-Object { $_.kind -eq 'json' })[0]
Check 'tree.md exists'   ($null -ne $tree  -and (Test-Path -LiteralPath $tree.path))
Check 'index.json exists'($null -ne $index -and (Test-Path -LiteralPath $index.path))
$idx = Get-Content -LiteralPath $index.path -Raw | ConvertFrom-Json
Check 'index entry_count matches' ($idx.entry_count -eq $o.result.entry_count)

# 3. search
$o2 = (RunEntry @('-Path', $repoRoot, '-Depth', '3', '-Pattern', '*.md')) | ConvertFrom-Json
Check 'search finds *.md' ($o2.result.match_count -gt 0)
Check 'matches populated' (@($o2.result.matches).Count -gt 0)

# 4. error path
$e = RunEntry @('-Path', 'C:\definitely\nope\zzz-nonexistent')
$ev3 = Test-SkillResultEnvelope -Json $e
$o3 = $e | ConvertFrom-Json
Check 'error envelope validates' ([bool]$ev3.valid)
Check 'error status + code' ($o3.status -eq 'error' -and $o3.error.code -eq 'path_not_found')

# 5. wrapped via Module 1
$inputs = @{ path = $repoRoot; depth = 1 } | ConvertTo-Json -Compress
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $inputs
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
