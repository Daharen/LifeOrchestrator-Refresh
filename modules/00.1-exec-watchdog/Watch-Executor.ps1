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
    [int]$PollErrorThreshold = 5,          # poll-error streak (from heartbeat) that counts as a wedge
    [int]$WedgeGraceSeconds = 60,          # a running task past timeout + this grace counts as a wedge
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
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$WedgeGraceSeconds = 60   # a running task counts as wedged only past timeout + this grace
    )
    $control  = Join-Path $Root 'control'
    $lockPath = Join-Path $control 'executor.lock'
    $hbPath   = Join-Path $control 'heartbeat.json'
    $lePath   = Join-Path $control 'last-exit.json'

    $alive = Test-ExecutorAlive -LockPath $lockPath

    # Heartbeat age from the file's actual modification time (parse-free and objective: a hung
    # process cannot refresh the file, so its mtime stops advancing). pid/instance are read from
    # the JSON separately, so a transient read failure never blanks the age.
    $hbAge = $null; $hbPid = $null; $hbInstance = $null
    $hbDegraded = $false; $hbPollStreak = 0; $hbStuckCount = 0
    if (Test-Path -LiteralPath $hbPath) {
        try { $hbAge = ((Get-UtcNow) - (Get-Item -LiteralPath $hbPath).LastWriteTimeUtc).TotalSeconds } catch { }
        try {
            $hb = Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
            $hbPid = [int]$hb.pid
            $hbInstance = [string]$hb.instance_id
            # health fields are additive: older heartbeats without them read as benign defaults.
            $props = $hb.PSObject.Properties
            if ($props['degraded'])             { $hbDegraded  = [bool]$hb.degraded }
            if ($props['poll_error_streak'])    { $hbPollStreak = [int]$hb.poll_error_streak }
            if ($props['stuck_finalize_count']) { $hbStuckCount = [int]$hb.stuck_finalize_count }
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

    # Independent wedge check: a running/<task>/state.json whose (started_at + timeout + grace) is in the
    # past means the executor should have finalized it and did not -- a wedge even if the heartbeat is fresh.
    # This does not rely on the executor self-reporting, so it catches a wedge the heartbeat health missed.
    $wedgedRunning = $false; $wedgedTask = $null
    $runningDir = Join-Path $Root 'running'
    if (Test-Path -LiteralPath $runningDir) {
        foreach ($d in @(Get-ChildItem -LiteralPath $runningDir -Directory -ErrorAction SilentlyContinue)) {
            $statePath = Join-Path $d.FullName 'state.json'
            if (-not (Test-Path -LiteralPath $statePath)) { continue }
            try {
                $stObj = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                $to = [int]$stObj.timeout_seconds
                if ($to -le 0) { continue }   # a no-timeout task can run forever; never "wedged"
                # TZ-robust: ConvertFrom-Json auto-parses an ISO-8601 'Z' string into a [datetime]
                # (Kind=Utc, original UTC components) -- so re-stringifying and re-parsing would let the
                # machine's LOCAL offset leak in (a no-op only where local==UTC). Read the value directly.
                $sv = $stObj.started_at_utc
                if ($sv -is [datetime]) {
                    $startedUtc = if ($sv.Kind -eq [System.DateTimeKind]::Local) { $sv.ToUniversalTime() }
                                  else { [DateTime]::SpecifyKind($sv, [System.DateTimeKind]::Utc) }
                } else {
                    $startedUtc = ([DateTimeOffset]::Parse([string]$sv, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime
                }
                $ageSec = ((Get-UtcNow) - $startedUtc).TotalSeconds
                if ($ageSec -ge ($to + $WedgeGraceSeconds)) { $wedgedRunning = $true; $wedgedTask = $d.Name; break }
            }
            catch { }
        }
    }

    return [pscustomobject]@{
        alive                 = $alive
        heartbeat_age_seconds = $hbAge
        heartbeat_pid         = $hbPid
        heartbeat_instance    = $hbInstance
        last_exit_reason      = $leReason
        last_exit_at          = $leAt
        degraded              = $hbDegraded
        poll_error_streak     = $hbPollStreak
        stuck_finalize_count  = $hbStuckCount
        wedged_running        = $wedgedRunning
        wedged_running_task   = $wedgedTask
    }
}

function Get-WatchdogDecision {
    <#
      PURE decision function (no I/O) -> one of: none | kill_restart | restart | stand_down | backoff.
        none         : executor healthy (alive + fresh heartbeat + not wedged)
        kill_restart : alive but hung (stale heartbeat) OR WEDGED -- alive + fresh heartbeat but not making
                       progress: self-reported degraded, a poll-error streak past threshold, or a running
                       task stuck past its timeout+grace and never finalized (the D-0055 blind spot, fix 3)
        stand_down   : down after an authorized stop (reason stop_requested|signal)
        restart      : down after a crash (fatal_error), a hard-kill (no marker), or never started
        backoff      : a restart is warranted but the crash-loop cap was hit
      The wedge params all default to benign values, so callers that pass only the original arguments get
      the original behaviour unchanged.
    #>
    param(
        [bool]$Alive,
        $HeartbeatAgeSeconds,          # $null when there is no heartbeat file
        [int]$HeartbeatStaleSeconds,
        [string]$LastExitReason,       # $null/'' when there is no last-exit marker
        [int]$RestartsInWindow,
        [int]$MaxRestarts,
        [bool]$Degraded = $false,      # executor self-reported degraded in heartbeat.json
        [int]$PollErrorStreak = 0,     # consecutive poll-loop errors reported in heartbeat.json
        [int]$PollErrorThreshold = 5,
        [bool]$WedgedRunning = $false  # a running task is past its timeout+grace and not finalized
    )
    if ($Alive) {
        if ($null -ne $HeartbeatAgeSeconds -and [double]$HeartbeatAgeSeconds -ge $HeartbeatStaleSeconds) {
            return 'kill_restart'
        }
        if ($Degraded -or $WedgedRunning -or ($PollErrorThreshold -gt 0 -and $PollErrorStreak -ge $PollErrorThreshold)) {
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
    # Propagate our pwsh to the executor so a restarted executor runs tasks with the same interpreter.
    $startArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$ExecutorScript,'-Root',$Root,'-PwshPath',$PwshPath)
    if ($IsWindows) {
        $style = if ($Visible) { 'Minimized' } else { 'Hidden' }
        return Start-Process -FilePath $PwshPath -ArgumentList $startArgs -WindowStyle $style -PassThru
    }
    return Start-Process -FilePath $PwshPath -ArgumentList $startArgs -PassThru
}

function Stop-ExecutorProcess {
    param([int]$ExecutorPid)
    if ($null -ne $ExecutorPid -and $ExecutorPid -gt 0) {
        if ($IsWindows) {
            try { & taskkill.exe /PID $ExecutorPid /T /F 2>&1 | Out-Null } catch { }
        }
        else {
            try { $p = Get-Process -Id $ExecutorPid -ErrorAction SilentlyContinue; if ($null -ne $p) { $p.Kill($true) } } catch { }
        }
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

        $state = Get-ExecutorState -Root $Root -WedgeGraceSeconds $WedgeGraceSeconds

        # Slide the restart window.
        $cutoff = (Get-UtcNow).AddSeconds(-$RestartWindowSeconds)
        $restarts = @($restarts | Where-Object { $_ -ge $cutoff })

        $decision = Get-WatchdogDecision -Alive $state.alive `
            -HeartbeatAgeSeconds $state.heartbeat_age_seconds -HeartbeatStaleSeconds $HeartbeatStaleSeconds `
            -LastExitReason $state.last_exit_reason -RestartsInWindow $restarts.Count -MaxRestarts $MaxRestarts `
            -Degraded $state.degraded -PollErrorStreak $state.poll_error_streak -PollErrorThreshold $PollErrorThreshold `
            -WedgedRunning $state.wedged_running

        switch ($decision) {
            'none' { }
            'stand_down' {
                Write-WatchdogLog "Executor was stopped on purpose (last_exit reason='$($state.last_exit_reason)'). Standing down." 'WARN'
                Write-WatchdogStatus -LastAction 'stand_down'
                break
            }
            'kill_restart' {
                $why =
                    if ($null -ne $state.heartbeat_age_seconds -and [double]$state.heartbeat_age_seconds -ge $HeartbeatStaleSeconds) { "HUNG (heartbeat age $([int]$state.heartbeat_age_seconds)s >= ${HeartbeatStaleSeconds}s)" }
                    elseif ($state.degraded) { "WEDGED (executor self-reported degraded; stuck_finalize=$($state.stuck_finalize_count) poll_errors=$($state.poll_error_streak))" }
                    elseif ($state.wedged_running) { "WEDGED (task '$($state.wedged_running_task)' past its timeout in running/ and never finalized)" }
                    elseif ($state.poll_error_streak -ge $PollErrorThreshold) { "WEDGED (poll error streak $($state.poll_error_streak) >= $PollErrorThreshold)" }
                    else { "unhealthy" }
                Write-WatchdogLog "Executor $why. Killing pid $($state.heartbeat_pid) and restarting." 'WARN'
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
