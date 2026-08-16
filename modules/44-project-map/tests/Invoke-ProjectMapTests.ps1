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
  # WindowsApps python/python3 are Store alias STUBS (exit 9009) -- exclude them (D-0129 trap class),
  # mirroring Invoke-ProjectMap.ps1 so the test gate never resolves the fake python (i49 fix).
  $pmCands = @((Get-Command python3 -ErrorAction SilentlyContinue), (Get-Command python -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and $_.Source -and ($_.Source -notmatch 'WindowsApps') }
  if ($pmCands) { $PythonPath = @($pmCands)[0].Source } else { $PythonPath = 'python' }
}

Write-Host "== project.map cloud suite =="
& $PythonPath (Join-Path $PSScriptRoot 'run_tests.py')
$cloud = $LASTEXITCODE
if ($cloud -ne 0) { Write-Error "cloud suite FAILED ($cloud)"; exit $cloud }

# FO-6 (i60, D-0155): the wrapper's non-harvest argv branch used to drop -Repo, so query --q
# section:/card:/evidence: --harvest could not resolve repo-backed content through the entrypoint.
# Spawn the wrapper as a REAL child process (not via `&` in-process) -- Invoke-ProjectMap.ps1 ends in
# `exit`, which would tear down this test process if invoked in-process.
Write-Host "== project.map wrapper argv (FO-6: query -Repo passthrough) =="
$fo6Wrapper = Join-Path $root 'Invoke-ProjectMap.ps1'
$fo6PwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$fo6PwshExe = if ($fo6PwshCmd) { $fo6PwshCmd.Source } else { 'pwsh' }
$fo6Repo = Join-Path ([System.IO.Path]::GetTempPath()) ('pm-fo6-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$fo6Out = & $fo6PwshExe -NoProfile -File $fo6Wrapper -Action query -Repo $fo6Repo -Q 'entity:module:44' 2>&1 | Out-String
$fo6Needle = "--repo $fo6Repo"
if ($fo6Out -notlike "*$fo6Needle*") {
  Write-Error "FO-6 REGRESSION: wrapper argv echo for 'query -Repo' is missing '$fo6Needle'.`n---- wrapper output ----`n$fo6Out"
  exit 1
}

# backward compatibility: omitting -Repo must NOT emit --repo (provider-guarded, only when $Repo is set)
$fo6OutNoRepo = & $fo6PwshExe -NoProfile -File $fo6Wrapper -Action query -Q 'entity:module:44' 2>&1 | Out-String
if ($fo6OutNoRepo -like '*--repo*') {
  Write-Error "FO-6 REGRESSION: wrapper argv echo emits --repo even though -Repo was not supplied.`n---- wrapper output ----`n$fo6OutNoRepo"
  exit 1
}
Write-Host "FO-6 OK: query -Repo passthrough present; omitted-Repo case unchanged"

if ($Live) {
  if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $root '..\..')).Path }  # repo root two levels up
  Write-Host "== -Live full-repo smoke (RepoState=$RepoState) against $Repo =="
  & $PythonPath (Join-Path $PSScriptRoot 'live_smoke.py') $Repo $RepoState
  $liveExit = $LASTEXITCODE
  if ($liveExit -ne 0) { Write-Error "-Live smoke FAILED ($liveExit)"; exit $liveExit }
}
Write-Host "ALL TESTS GREEN"
exit 0
