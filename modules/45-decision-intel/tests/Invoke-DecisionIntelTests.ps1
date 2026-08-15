#requires -Version 7.0
<#
.SYNOPSIS
  decision.intel -- the REAL entrypoint -> REAL worker test runner (cloud pre-ship gate AND the -Live
  executor gate). Drives Invoke-DecisionIntel.ps1 TWICE against the REAL core-docs/DECISION_LOG.md +
  DECISION_LOG_INDEX.md (a real native `git rev-parse HEAD` supplies -IngestedThrough -- this TEST
  HARNESS may shell to git; the WORKER (decision_intel.py) never does), asserts the emitted
  lifeorch.skill.result/0.1 envelope + coverage + validation + supersession resolution, asserts
  double-run byte-identity over every canonical artifact, then also runs the off-machine python
  determinism/coverage/validator harness (tests/test_decision_intel.py) against the same real corpus.
  Exit 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh.exe'),
    [string]$PythonPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ModuleDir = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ModuleDir)
$LogPath = Join-Path $RepoRoot 'core-docs\DECISION_LOG.md'
$IdxPath = Join-Path $RepoRoot 'core-docs\DECISION_LOG_INDEX.md'
$Invoke = Join-Path $ModuleDir 'Invoke-DecisionIntel.ps1'

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "PASS: $name" }
    else { $script:fail++; Write-Host "FAIL: $name $(if ($detail) { "-- $detail" })" -ForegroundColor Red }
}

Write-Host "[decision.intel tests] repo_root=$RepoRoot"
Check 'DECISION_LOG.md exists' (Test-Path -LiteralPath $LogPath -PathType Leaf) $LogPath
Check 'DECISION_LOG_INDEX.md exists' (Test-Path -LiteralPath $IdxPath -PathType Leaf) $IdxPath
Check 'Invoke-DecisionIntel.ps1 exists' (Test-Path -LiteralPath $Invoke -PathType Leaf) $Invoke
if ($fail -gt 0) { Write-Host "RESULT: $pass passed, $fail failed"; exit 1 }

# ---- native git HEAD (the TEST HARNESS may shell to git; the worker never does) ----
Push-Location $RepoRoot
try {
    $headSha = ((& git --no-optional-locks rev-parse HEAD) | Out-String).Trim()
} finally { Pop-Location }
Check 'resolved a real git HEAD sha' ($headSha -match '^[0-9a-f]{40}$') $headSha

$root1 = Join-Path ([System.IO.Path]::GetTempPath()) ('decint-t1-' + [Guid]::NewGuid().ToString('N'))
$root2 = Join-Path ([System.IO.Path]::GetTempPath()) ('decint-t2-' + [Guid]::NewGuid().ToString('N'))
$id1 = [Guid]::NewGuid().ToString(); $id2 = [Guid]::NewGuid().ToString()

function Invoke-Run([string]$artifactRoot, [string]$invId) {
    # NOTE: deliberately does NOT merge stderr via 2>&1 -- when the target is a NESTED pwsh.exe (a native
    # process from this process's point of view), PowerShell wraps each stderr line the child writes as an
    # ErrorRecord and interleaves it into the captured pipeline BEFORE the child's stdout text, which
    # corrupts ConvertFrom-Json on the merged string even though the child's stdout-only JSON is well-formed.
    # Redirecting stderr to a file instead keeps stdout capture pure text for JSON parsing.
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) ('decint-stderr-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $argv = @('-NoProfile', '-File', $Invoke, '-DecisionLogPath', $LogPath, '-DecisionLogIndexPath', $IdxPath,
              '-IngestedThrough', $headSha, '-ArtifactRoot', $artifactRoot, '-InvocationId', $invId)
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $argv += @('-PythonPath', $PythonPath) }
    $global:LASTEXITCODE = 0
    $out = & $PwshExe @argv 2>$errFile | Out-String
    $exit = $LASTEXITCODE
    $errText = ''
    try { $errText = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    return @{ exit = $exit; out = $out; err = $errText }
}

$r1 = Invoke-Run $root1 $id1
Check 'run1 exit 0' ($r1.exit -eq 0) "exit=$($r1.exit) stderr_tail=$(($r1.err -split "`n" | Select-Object -Last 5) -join ' | ')"
$env1 = $null
try { $env1 = ($r1.out | ConvertFrom-Json) } catch { }
Check 'run1 envelope parses' ($null -ne $env1)
if ($env1) {
    Check 'run1 schema' ($env1.schema -eq 'lifeorch.skill.result/0.1')
    Check 'run1 status ok|partial' (@('ok', 'partial') -contains $env1.status) $env1.status
    Check 'run1 result.coverage.ok' ([bool]$env1.result.coverage.ok) ($env1.result.coverage | ConvertTo-Json -Compress)
    Check 'run1 result.validation.ok' ([bool]$env1.result.validation.ok) ($env1.result.validation | ConvertTo-Json -Compress)
    Check 'run1 unresolved_supersession_targets empty' (@($env1.result.unresolved_supersession_targets).Count -eq 0)
    Check 'run1 total_records == index_row_count' ($env1.result.total_records -eq $env1.result.coverage.index_row_count)
    Check 'run1 at least 1 artifact hashed' (@($env1.artifacts).Count -ge 5) "$(@($env1.artifacts).Count)"
}

$r2 = Invoke-Run $root2 $id2
Check 'run2 exit 0' ($r2.exit -eq 0)
$env2 = $null
try { $env2 = ($r2.out | ConvertFrom-Json) } catch { }
Check 'run2 envelope parses' ($null -ne $env2)
if ($env1 -and $env2) {
    Check 'records_digest identical across runs' ($env1.result.records_digest -eq $env2.result.records_digest) `
        "$($env1.result.records_digest) vs $($env2.result.records_digest)"
}

# ---- double-run byte-identity over every canonical artifact file (by content, not by declared invocation dir) ----
if ($env1 -and $env2) {
    $dir1 = Join-Path $root1 $id1
    $dir2 = Join-Path $root2 $id2
    $names = @('records.jsonl', 'records.json', 'ingest_records.json', 'index_manifest.json', 'coverage.json')
    $allIdentical = $true
    foreach ($n in $names) {
        $p1 = Join-Path $dir1 $n; $p2 = Join-Path $dir2 $n
        $ok = $false
        if ((Test-Path -LiteralPath $p1 -PathType Leaf) -and (Test-Path -LiteralPath $p2 -PathType Leaf)) {
            $b1 = [System.IO.File]::ReadAllBytes($p1); $b2 = [System.IO.File]::ReadAllBytes($p2)
            $ok = ($b1.Length -eq $b2.Length) -and (-not (Compare-Object $b1 $b2))
        }
        Check "byte-identical across runs: $n" $ok
        $allIdentical = $allIdentical -and $ok
    }
    Check 'byte-identical across runs: ALL canonical artifacts' $allIdentical
}

# ---- op=validate against run1's records.jsonl ----
if ($env1) {
    $recPath = Join-Path (Join-Path $root1 $id1) 'records.jsonl'
    $vErrFile = Join-Path ([System.IO.Path]::GetTempPath()) ('decint-stderr-validate-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $argv = @('-NoProfile', '-File', $Invoke, '-Op', 'validate', '-RecordsPath', $recPath,
              '-ArtifactRoot', $root1, '-InvocationId', [Guid]::NewGuid().ToString())
    $global:LASTEXITCODE = 0
    $vout = & $PwshExe @argv 2>$vErrFile | Out-String
    $vexit = $LASTEXITCODE
    Remove-Item -LiteralPath $vErrFile -Force -ErrorAction SilentlyContinue
    $venv = $null
    try { $venv = ($vout | ConvertFrom-Json) } catch { }
    Check 'validate op exit 0' ($vexit -eq 0)
    Check 'validate op parses' ($null -ne $venv)
    if ($venv) { Check 'validate op result.validation.ok' ([bool]$venv.result.validation.ok) }
}

# ---- off-machine python harness (real corpus) ----
$pyTest = Join-Path $ModuleDir 'tests\test_decision_intel.py'
if (Test-Path -LiteralPath $pyTest -PathType Leaf) {
    $pyExe = if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $PythonPath } else { 'C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe' }
    if (-not (Test-Path -LiteralPath $pyExe -PathType Leaf)) { $pyExe = 'python' }
    $global:LASTEXITCODE = 0
    $pyOut = & $pyExe $pyTest $LogPath $IdxPath 2>&1 | Out-String
    Write-Host $pyOut
    Check 'python off-machine harness exit 0' ($LASTEXITCODE -eq 0)
}

Remove-Item -LiteralPath $root1 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $root2 -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "RESULT: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 } else { exit 0 }
