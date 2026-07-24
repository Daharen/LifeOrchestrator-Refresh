#requires -Version 7.0
<#
.SYNOPSIS
  exec.watchdog - a cooperative, session-scoped supervisor for the Trusted High-Risk Bootstrap Executor.

.DESCRIPTION
  Watches the executor's runtime/control dir and AUTONOMOUSLY (no approval) recovers it:
    - executor healthy .................. do nothing
    - alive but heartbeat stale (HUNG) .. kill its process tree + restart
    - down after a crash / hard-kill .... restart
    - down after an AUTHORIZED stop ..... STAND DOWN (do not restart) and exit
  "Authorized stop" is detected from control/last-exit.json (reason stop_requested | signal), which the
  executor writes on any graceful exit (Ctrl+C, stop.requested, or window-close). A crash writes
  reason "fatal_error"; a hard-kill / power-loss writes nothing (no marker => treated as a crash).

  This is COOPERATIVE, not perpetual: it only heals failures and always honors a deliberate stop, so it
  does not resist shutdown or preserve access against the user's will (DECISION_LOG D-0013). It installs
  NO persistence (no scheduled task / service / Run key), does not survive logout/reboot, does not relaunch
  itself, and stops on control/watchdog.stop.requested or when its own window is closed. Crash-loop backoff
  prevents hammering.

.EXAMPLE
  pwsh -NoProfile -File .\Watch-Executor.ps1            # supervise the canonical executor
  pwsh -NoProfile -File .\Watch-Executor.ps1 -DefineOnly   # (tests) define functions, do not loop
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\runtime',
    [string]$ExecutorScript = 'C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\Start-BootstrapExecutor.ps1',
    [int]$PollSeconds = 10,
    [int]$HeartbeatStaleSeconds = 45,
    [int]$MaxRestarts = 5,
    [int]$RestartWindowSeconds = 300,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$VisibleExecutor,
    [switch]$DefineOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UtcNow { [DateTime]::UtcNow }

function Test-ExecutorAlive {
    # Alive iff the single-instance lock is held (cannot be opened exclusively).
    param([Parameter(Mandatory)][string]$LockPath)
    if (-not (Test-Path -LiteralPath $LockPath)) { return $false }
    try {
        $fs = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Close(); $fs.Dispose()
        return $false   # opened exclusively => nobody holds it => not alive
    }
    catch {
        return $true    # sharing violation => the executor holds it => alive
    }
}

function Get-ExecutorState {
    <# Reads the control dir and returns a flat state object for Get-WatchdogDecision. #>
    param([Parameter(Mandatory)][string]$Root)
    $control  = Join-Path $Root 'control'
    $lockPath = Join-Path $control 'executor.lock'
    $hbPath   = Join-Path $control 'heartbeat.json'
    $lePath   = Join-Path $control 'last-exit.json'

    $alive = Test-ExecutorAlive -LockPath $lockPath

    # Heartbeat age from the file's actual modification time (parse-free and objective: a hung
    # process cannot refresh the file, so its mtime stops advancing). pid/instance are read from
    # the JSON separately, so a transient read failure never blanks the age.
    $hbAge = $null; $hbPid = $null; $hbInstance = $null
    if (Test-Path -LiteralPath $hbPath) {
        try { $hbAge = ((Get-UtcNow) - (Get-Item -LiteralPath $hbPath).LastWriteTimeUtc).TotalSeconds } catch { }
        try {
            $hb = Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
            $hbPid = [int]$hb.pid
            $hbInstance = [string]$hb.instance_id
        }
        catch { }
    }

    $leReason = $null; $leAt = $null
    if (Test-Path -LiteralPath $lePath) {
        try {
            $le = Get-Content -LiteralPath $lePath -Raw | ConvertFrom-Json
            $leReason = [string]$le.reason
            $leAt = [string]$le.at_utc
        }
        catch { }
    }

    return [pscustomobject]@{
        alive                 = $alive
        heartbeat_age_seconds = $hbAge
        heartbeat_pid         = $hbPid
        heartbeat_instance    = $hbInstance
        last_exit_reason      = $leReason
        last_exit_at          = $leAt
    }
}

function Get-WatchdogDecision {
    <#
      PURE decision function (no I/O) -> one of: none | kill_restart | restart | stand_down | backoff.
        none         : executor healthy (alive + fresh heartbeat)
        kill_restart : alive but heartbeat stale => hung
        stand_down   : down after an authorized stop (reason stop_requested|signal)
        restart      : down after a crash (fatal_error), a hard-kill (no marker), or never started
        backoff      : a restart is warranted but the crash-loop cap was hit
    #>
    param(
        [bool]$Alive,
        $HeartbeatAgeSeconds,          # $null when there is no heartbeat file
        [int]$HeartbeatStaleSeconds,
        [string]$LastExitReason,       # $null/'' when there is no last-exit marker
        [int]$RestartsInWindow,
        [int]$MaxRestarts
    )
    if ($Alive) {
        if ($null -ne $HeartbeatAgeSeconds -and [double]$HeartbeatAgeSeconds -ge $HeartbeatStaleSeconds) {
            return 'kill_restart'
        }
        return 'none'
    }
    if ($LastExitReason -eq 'stop_requested' -or $LastExitReason -eq 'signal') {
        return 'stand_down'
    }
    if ($RestartsInWindow -ge $MaxRestarts) { return 'backoff' }
    return 'restart'
}

function Start-ExecutorProcess {
    param([Parameter(Mandatory)][string]$ExecutorScript, [Parameter(Mandatory)][string]$PwshPath, [Parameter(Mandatory)][string]$Root, [bool]$Visible = $false)
    $startArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$ExecutorScript,'-Root',$Root)
    $style = if ($Visible) { 'Minimized' } else { 'Hidden' }
    return Start-Process -FilePath $PwshPath -ArgumentList $startArgs -WindowStyle $style -PassThru
}

function Stop-ExecutorProcess {
    param([int]$ExecutorPid)
    if ($null -ne $ExecutorPid -and $ExecutorPid -gt 0) {
        try { & taskkill.exe /PID $ExecutorPid /T /F 2>&1 | Out-Null } catch { }
    }
}

if ($DefineOnly) { return }   # tests dot-source this file to reach the pure functions

# ---------------------------------------------------------------------------
# Watchdog loop
# ---------------------------------------------------------------------------
$control = Join-Path $Root 'control'
New-Item -ItemType Directory -Path $control -Force | Out-Null
$logPath        = Join-Path (Join-Path $Root 'logs') 'watchdog.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null
$statusPath     = Join-Path $control 'watchdog.json'
$stopPath       = Join-Path $control 'watchdog.stop.requested'
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-WatchdogLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-UtcNow).ToString('o'), $Level, $Message
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}
function Write-WatchdogStatus {
    param([string]$LastAction)
    try {
        $obj = [ordered]@{ pid = $PID; started_at_utc = $script:watchdogStartedAt; last_action = $LastAction; at_utc = (Get-UtcNow).ToString('o'); root = $Root }
        $tmp = "$statusPath.tmp"
        [System.IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6), $utf8)
        Move-Item -LiteralPath $tmp -Destination $statusPath -Force
    }
    catch { }
}

# A stale stop request from a prior run must not immediately stop us.
if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue }

$script:watchdogStartedAt = (Get-UtcNow).ToString('o')
$restarts = @()   # datetimes of recent (re)starts, for crash-loop backoff

Write-WatchdogLog "Watchdog starting (pid $PID). Root: $Root"
Write-WatchdogLog "poll=${PollSeconds}s heartbeat_stale>=${HeartbeatStaleSeconds}s max_restarts=$MaxRestarts/${RestartWindowSeconds}s visible_executor=$($VisibleExecutor.IsPresent)"
Write-WatchdogStatus -LastAction 'starting'

try {
    while ($true) {
        if (Test-Path -LiteralPath $stopPath) {
            Write-WatchdogLog "Watchdog stop requested (control/watchdog.stop.requested). Exiting." 'WARN'
            Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
            Write-WatchdogStatus -LastAction 'stopped'
            break
        }

        $state = Get-ExecutorState -Root $Root

        # Slide the restart window.
        $cutoff = (Get-UtcNow).AddSeconds(-$RestartWindowSeconds)
        $restarts = @($restarts | Where-Object { $_ -ge $cutoff })

        $decision = Get-WatchdogDecision -Alive $state.alive `
            -HeartbeatAgeSeconds $state.heartbeat_age_seconds -HeartbeatStaleSeconds $HeartbeatStaleSeconds `
            -LastExitReason $state.last_exit_reason -RestartsInWindow $restarts.Count -MaxRestarts $MaxRestarts

        switch ($decision) {
            'none' { }
            'stand_down' {
                Write-WatchdogLog "Executor was stopped on purpose (last_exit reason='$($state.last_exit_reason)'). Standing down." 'WARN'
                Write-WatchdogStatus -LastAction 'stand_down'
                break
            }
            'kill_restart' {
                Write-WatchdogLog "Executor HUNG (heartbeat age $([int]$state.heartbeat_age_seconds)s >= ${HeartbeatStaleSeconds}s). Killing pid $($state.heartbeat_pid) and restarting." 'WARN'
                Stop-ExecutorProcess -ExecutorPid $state.heartbeat_pid
                Start-Sleep -Seconds 2
                $p = Start-ExecutorProcess -ExecutorScript $ExecutorScript -PwshPath $PwshPath -Root $Root -Visible $VisibleExecutor.IsPresent
                $restarts += (Get-UtcNow)
                Write-WatchdogLog "Restarted executor as pid $($p.Id) after hang."
                Write-WatchdogStatus -LastAction 'kill_restart'
            }
            'restart' {
                $why = if ([string]::IsNullOrEmpty($state.last_exit_reason)) { 'no marker (hard-kill / power-loss / never-started)' } else { "reason='$($state.last_exit_reason)'" }
                Write-WatchdogLog "Executor is down ($why). Restarting." 'WARN'
                $p = Start-ExecutorProcess -ExecutorScript $ExecutorScript -PwshPath $PwshPath -Root $Root -Visible $VisibleExecutor.IsPresent
                $restarts += (Get-UtcNow)
                Write-WatchdogLog "Restarted executor as pid $($p.Id)."
                Write-WatchdogStatus -LastAction 'restart'
            }
            'backoff' {
                Write-WatchdogLog "Crash-loop backoff: $($restarts.Count) restarts within ${RestartWindowSeconds}s (cap $MaxRestarts). Not restarting this cycle; manual attention may be needed." 'ERROR'
                Write-WatchdogStatus -LastAction 'backoff'
            }
        }

        if ($decision -eq 'stand_down') { break }

        Start-Sleep -Seconds $PollSeconds
    }
}
finally {
    Write-WatchdogLog "Watchdog stopped (pid $PID)."
}
