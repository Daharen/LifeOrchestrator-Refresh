#requires -Version 7.0
<#
.SYNOPSIS
  On-demand executor recovery. Because YOU invoke it, it is authorized to (re)start unconditionally.

.DESCRIPTION
  - executor down  -> start it (ignores the last-exit marker; you're explicitly asking for it up).
  - executor hung  -> kill its tree + restart.
  - executor healthy -> no-op, unless -Force (then kill + restart anyway; this is your "interrupt a
    slow/stuck run and restart it" button).
  Prints a machine-readable JSON summary. Reuses the watchdog's helper functions.

.EXAMPLE
  pwsh -NoProfile -File .\Recover-Executor.ps1            # start if down / restart if hung
  pwsh -NoProfile -File .\Recover-Executor.ps1 -Force     # kill + restart even if healthy
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\runtime',
    [string]$ExecutorScript = 'C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\Start-BootstrapExecutor.ps1',
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [int]$HeartbeatStaleSeconds = 45,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Watch-Executor.ps1') -DefineOnly

$state = Get-ExecutorState -Root $Root
$hung = ($state.alive -and $null -ne $state.heartbeat_age_seconds -and [double]$state.heartbeat_age_seconds -ge $HeartbeatStaleSeconds)

$action = 'none'
$newPid = $null

if ($state.alive) {
    if ($hung -or $Force) {
        Stop-ExecutorProcess -ExecutorPid $state.heartbeat_pid
        Start-Sleep -Seconds 2
        $p = Start-ExecutorProcess -ExecutorScript $ExecutorScript -PwshPath $PwshPath -Root $Root -Visible $true
        $newPid = $p.Id
        $action = if ($hung) { 'killed_hung_and_restarted' } else { 'force_killed_and_restarted' }
    }
    else {
        $action = 'already_healthy_no_op'
    }
}
else {
    $p = Start-ExecutorProcess -ExecutorScript $ExecutorScript -PwshPath $PwshPath -Visible $true
    $newPid = $p.Id
    $action = 'started'
}

[pscustomobject]@{
    schema            = 'lifeorch.exec.recovery/0.1'
    at_utc            = ([DateTime]::UtcNow).ToString('o')
    action            = $action
    forced            = [bool]$Force
    prior_alive       = $state.alive
    prior_hung        = $hung
    prior_last_exit   = $state.last_exit_reason
    prior_heartbeat_age_seconds = $state.heartbeat_age_seconds
    executor_pid      = $newPid
} | ConvertTo-Json -Depth 6
