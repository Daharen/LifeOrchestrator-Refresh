<#
.SYNOPSIS
  project.map (module:44) test entrypoint. Runs the cloud suite FIRST (tests/run_tests.py -- the single
  source of truth for every WO s6 test class), then, with -Live, the full-repo smoke against the real
  repo with a -RepoState expectation parameter (RT1-F11) and a cloud-vs-box render digest parity check.

.DESCRIPTION
  The substantive test logic lives in the stdlib Python runner so it runs byte-identically on the cloud,
  the mount VM (3.10), and the box (3.12). This wrapper maps its exit code and adds the -Live steps.
#>
[CmdletBinding()]
param(
  [switch]$Live,
  [ValidateSet('Skeleton','Folded')]
  [string]$RepoState = 'Skeleton',
  [string]$Repo,
  [string]$PythonPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $PythonPath) {
  $PythonPath = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source
  if (-not $PythonPath) { $PythonPath = (Get-Command python -ErrorAction SilentlyContinue)?.Source }
  if (-not $PythonPath) { $PythonPath = 'python' }
}

Write-Host "== project.map cloud suite =="
& $PythonPath (Join-Path $PSScriptRoot 'run_tests.py')
$cloud = $LASTEXITCODE
if ($cloud -ne 0) { Write-Error "cloud suite FAILED ($cloud)"; exit $cloud }

if ($Live) {
  if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $root '..\..')).Path }  # repo root two levels up
  Write-Host "== -Live full-repo smoke (RepoState=$RepoState) against $Repo =="
  & $PythonPath (Join-Path $PSScriptRoot 'live_smoke.py') $Repo $RepoState
  $liveExit = $LASTEXITCODE
  if ($liveExit -ne 0) { Write-Error "-Live smoke FAILED ($liveExit)"; exit $liveExit }
}
Write-Host "ALL TESTS GREEN"
exit 0
