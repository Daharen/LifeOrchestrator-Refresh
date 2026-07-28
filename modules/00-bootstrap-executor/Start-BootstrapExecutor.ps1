<#
.SYNOPSIS
    Trusted High-Risk Bootstrap Executor - queue poller and task runner.

.DESCRIPTION
    Polls runtime/pending for task directories, atomically claims them into
    runtime/running, executes their PowerShell script in an isolated pwsh
    process, captures stdout/stderr/exit code/timing, and finalizes them into
    runtime/completed or runtime/failed with a machine-readable result.json.

    THIS IS A TRUSTED, HIGH-RISK EXECUTOR - NOT A SANDBOX. Any actor that can
    place a task directory into runtime/pending runs arbitrary PowerShell with
    the full authority of the Windows user running this executor. There are no
    allowlists, content filters, or approval prompts by design.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot "runtime"),
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),
    [int]$QueuePollSeconds,
    [int]$ProcessPollMilliseconds,
    [int]$MaxConcurrentTasks,
    [int]$DefaultTimeoutSeconds,
    [string]$PwshPath,
    # --- D-0055 wedge hardening (all optional; config-backed) ---
    [string[]]$ReapProcessNames,        # process names to sweep on timeout/cancel (default: llama-server)
    [int]$StuckFinalizeMaxAttempts,     # finalize retries before flagging the executor degraded
    [int]$PollErrorThreshold,           # consecutive poll-loop errors before flagging degraded
    [switch]$DefineOnly                 # (tests) define functions + return; no runtime dirs, lock, or loop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------

function Get-UtcNow {
    return [DateTime]::UtcNow
}

function Format-Utc {
    param([Parameter(Mandatory)] [DateTime]$Value)
    return $Value.ToUniversalTime().ToString("o")
}

function Invoke-WithFileRetry {
    # In-process self-heal: retry a filesystem operation that hits a transient sharing violation
    # (the class of error that fatal-crashed the executor on 2026-07-24) instead of letting it bubble.
    # Only IOException / UnauthorizedAccessException are retried; anything else rethrows immediately.
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [int]$MaxAttempts = 6,
        [int]$DelayMs = 150
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try { return (& $Action) }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            if ($attempt -ge $MaxAttempts) { throw }
            Start-Sleep -Milliseconds ($DelayMs * $attempt)   # linear backoff
        }
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $temporaryPath = "$Path.tmp"
    $json = $Value | ConvertTo-Json -Depth 20
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    Invoke-WithFileRetry -Action {
        [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8WithoutBom)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string]$Name,
        $DefaultValue
    )

    if ($null -eq $Object) { return $DefaultValue }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    if ($null -eq $property.Value) { return $DefaultValue }
    return $property.Value
}

function Stop-ProcessTree {
    <#
        Terminate a process and its entire child tree.
        On Windows this uses taskkill /T /F (the spec's required mechanism).
        On other platforms it falls back to .NET Process.Kill($true) so the
        cross-platform smoke tests behave sensibly.
    #>
    param([Parameter(Mandatory)] [int]$ProcessId)

    try {
        if ($IsWindows) {
            & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
        }
        else {
            $existing = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($null -ne $existing) { $existing.Kill($true) }
        }
    }
    catch {
        # The process (or a child) may already have exited; that is fine.
    }
}

# ----------------------------------------------------------------------------
# Process-tree reaping incl. detached / orphaned children (D-0055 hardening)
# ----------------------------------------------------------------------------

function Stop-ProcessHard {
    # Forcefully kill a SINGLE process by pid. .NET Process.Kill($true) does not reliably kill a
    # (grand)child tree on Linux, so we SIGKILL each pid directly: taskkill /F on Windows, kill -9 elsewhere.
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return }
    try {
        if ($IsWindows) { & taskkill.exe /PID $ProcessId /F 2>&1 | Out-Null }
        else { & kill -9 $ProcessId 2>$null }
    }
    catch { }
}

function Get-ProcParentMap {
    # @{ pid = ppid } for all processes. Cross-platform: Win32_Process on Windows, `ps` elsewhere.
    $map = @{}
    try {
        if ($IsWindows) {
            foreach ($p in (Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) {
                $map[[int]$p.ProcessId] = [int]$p.ParentProcessId
            }
        }
        else {
            $lines = & ps -eo pid=,ppid= 2>$null
            foreach ($ln in @($lines)) {
                $t = ([string]$ln).Trim() -split '\s+'
                if ($t.Count -ge 2) {
                    $pidv = 0; $ppidv = 0
                    if ([int]::TryParse($t[0], [ref]$pidv) -and [int]::TryParse($t[1], [ref]$ppidv)) { $map[$pidv] = $ppidv }
                }
            }
        }
    }
    catch { }
    return $map
}

function Get-DescendantPids {
    # All transitive descendants of $RootPid, from a pid->ppid map (captured BEFORE a kill).
    param([Parameter(Mandatory)][int]$RootPid, [hashtable]$ParentMap)
    if ($null -eq $ParentMap) { $ParentMap = Get-ProcParentMap }
    $children = @{}
    foreach ($kv in $ParentMap.GetEnumerator()) {
        $pp = [int]$kv.Value
        if (-not $children.ContainsKey($pp)) { $children[$pp] = New-Object System.Collections.Generic.List[int] }
        [void]$children[$pp].Add([int]$kv.Key)
    }
    $result = New-Object System.Collections.Generic.List[int]
    $seen = @{}
    $stack = New-Object System.Collections.Generic.Stack[int]
    $stack.Push($RootPid)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        if ($children.ContainsKey($cur)) {
            foreach ($c in $children[$cur]) {
                if (-not $seen.ContainsKey($c)) { $seen[$c] = $true; [void]$result.Add($c); $stack.Push($c) }
            }
        }
    }
    return $result.ToArray()
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try { return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) } catch { return $false }
}

function Invoke-OrphanNameSweep {
    # Kill processes named in $ReapNames whose parent is NOT alive -- a detached llama-server whose
    # spawning task/intermediate already exited. Returns the count killed. Attribution-safe: a
    # name-matched process with a LIVE parent (another task's server) is left alone. Skipped if the
    # process map could not be built (never over-kill on a snapshot failure).
    param([string[]]$ReapNames, [hashtable]$ParentMap)
    if ($null -eq $ReapNames -or @($ReapNames).Count -eq 0) { return 0 }
    if ($null -eq $ParentMap) { $ParentMap = Get-ProcParentMap }
    if ($ParentMap.Count -eq 0) { return 0 }
    $killed = 0
    foreach ($name in $ReapNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $ppid = if ($ParentMap.ContainsKey([int]$p.Id)) { [int]$ParentMap[[int]$p.Id] } else { 0 }
            $parentAlive = ($ppid -gt 0 -and (Test-ProcessAlive -ProcessId $ppid))
            if (-not $parentAlive) { Stop-ProcessHard -ProcessId $p.Id; $killed++ }
        }
    }
    return $killed
}

function Stop-TaskTreeAndReap {
    # Kill a task's whole tree AND any detached child that escaped it (a breakaway, or a child whose
    # intermediate parent already exited), plus a name-based orphan sweep of $ReapNames. This runs
    # BEFORE the finalize move so a detached llama-server can no longer lock a file in running/.
    # Returns the number of EXTRA processes reaped beyond the direct tree kill.
    param([Parameter(Mandatory)][int]$ProcessId, [string[]]$ReapNames)
    $map = Get-ProcParentMap
    $descendants = @(Get-DescendantPids -RootPid $ProcessId -ParentMap $map)   # capture BEFORE any kill
    # Kill descendants FIRST -- while their parent links are still intact and each is a clean child -- with a
    # reliable per-PID SIGKILL. Doing this before the root avoids the reparent race AND .NET's unreliable
    # entire-tree kill on Linux (which leaves a pwsh/llama-server grandchild alive).
    $extra = 0
    foreach ($d in $descendants) {
        if (Test-ProcessAlive -ProcessId $d) { Stop-ProcessHard -ProcessId $d; $extra++ }
    }
    Stop-ProcessTree -ProcessId $ProcessId    # kill the root's tree (best effort, Windows taskkill /T is thorough)
    Stop-ProcessHard  -ProcessId $ProcessId   # ...and ensure the root itself is gone
    $extra += (Invoke-OrphanNameSweep -ReapNames $ReapNames)
    return $extra
}

$script:faultCounts = @{}
function Test-InjectedFinalizeFault {
    # TEST-ONLY seam. OFF unless $env:LOEXEC_FINALIZE_FAULT="<taskSubstr>:<failCount>" is set. Makes the
    # finalize move throw <failCount> times for a task whose name contains <taskSubstr>, to exercise the
    # resilient-finalize / degraded path deterministically (a locked file cannot be forced cross-platform).
    param([Parameter(Mandatory)][string]$TaskName)
    $spec = $env:LOEXEC_FINALIZE_FAULT
    if ([string]::IsNullOrWhiteSpace($spec)) { return $false }
    $parts = $spec.Split(':')
    if ($parts.Count -lt 2) { return $false }
    $substr = $parts[0]
    if ([string]::IsNullOrWhiteSpace($substr) -or -not $TaskName.Contains($substr)) { return $false }
    $max = 0; [void][int]::TryParse($parts[1], [ref]$max)
    if ($max -le 0) { return $false }
    $used = if ($script:faultCounts.ContainsKey($TaskName)) { [int]$script:faultCounts[$TaskName] } else { 0 }
    if ($used -ge $max) { return $false }
    $script:faultCounts[$TaskName] = $used + 1
    return $true
}

if ($DefineOnly) { return }   # tests dot-source this file to reach the pure reap/fault helpers above

# ----------------------------------------------------------------------------
# Runtime directories
# ----------------------------------------------------------------------------

$directoryNames = @("staging", "pending", "running", "completed", "failed", "control", "logs")
$directories = @{}
foreach ($name in $directoryNames) {
    $path = Join-Path $Root $name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $directories[$name] = $path
}

$logPath = Join-Path $directories["logs"] "executor.log"

function Write-ExecutorLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")] [string]$Level = "INFO"
    )
    $line = "{0} [{1}] {2}" -f (Format-Utc (Get-UtcNow)), $Level, $Message
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

# ----------------------------------------------------------------------------
# Configuration (file, overridden by explicit parameters)
# ----------------------------------------------------------------------------

$config = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config file '$ConfigPath': $($_.Exception.Message)"
    }
}

if (-not $PSBoundParameters.ContainsKey("QueuePollSeconds")) {
    $QueuePollSeconds = [int](Get-OptionalProperty $config "queue_poll_seconds" 30)
}
if (-not $PSBoundParameters.ContainsKey("ProcessPollMilliseconds")) {
    $ProcessPollMilliseconds = [int](Get-OptionalProperty $config "process_poll_milliseconds" 1000)
}
if (-not $PSBoundParameters.ContainsKey("MaxConcurrentTasks")) {
    $MaxConcurrentTasks = [int](Get-OptionalProperty $config "max_concurrent_tasks" 4)
}
if (-not $PSBoundParameters.ContainsKey("DefaultTimeoutSeconds")) {
    $DefaultTimeoutSeconds = [int](Get-OptionalProperty $config "default_timeout_seconds" 900)
}
if (-not $PSBoundParameters.ContainsKey("PwshPath")) {
    $PwshPath = [string](Get-OptionalProperty $config "pwsh_path" "pwsh.exe")
}
if (-not $PSBoundParameters.ContainsKey("ReapProcessNames")) {
    $cfgReap = Get-OptionalProperty $config "reap_process_names" @("llama-server")
    $ReapProcessNames = @($cfgReap | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
if (-not $PSBoundParameters.ContainsKey("StuckFinalizeMaxAttempts")) {
    $StuckFinalizeMaxAttempts = [int](Get-OptionalProperty $config "stuck_finalize_max_attempts" 5)
}
if (-not $PSBoundParameters.ContainsKey("PollErrorThreshold")) {
    $PollErrorThreshold = [int](Get-OptionalProperty $config "poll_error_threshold" 5)
}
if ($StuckFinalizeMaxAttempts -lt 1) { $StuckFinalizeMaxAttempts = 1 }
if ($PollErrorThreshold -lt 1) { $PollErrorThreshold = 1 }

if ($QueuePollSeconds -lt 1) { throw "QueuePollSeconds must be at least 1." }
if ($ProcessPollMilliseconds -lt 100) { throw "ProcessPollMilliseconds must be at least 100." }
if ($MaxConcurrentTasks -lt 1) { throw "MaxConcurrentTasks must be at least 1." }
if ($DefaultTimeoutSeconds -lt 0) { throw "DefaultTimeoutSeconds cannot be negative." }

$resolvedPwsh = Get-Command $PwshPath -ErrorAction Stop
$PwshPath = $resolvedPwsh.Source

# ----------------------------------------------------------------------------
# Single-instance lock (held for the executor's lifetime via exclusive handle)
# ----------------------------------------------------------------------------

$lockPath = Join-Path $directories["control"] "executor.lock"
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
}
catch {
    throw "Another executor instance is already using this runtime directory ('$Root')."
}

$executorInstanceId = [Guid]::NewGuid().ToString()
$stopRequestedPath = Join-Path $directories["control"] "stop.requested"
$script:activeTasks = @{}

# A stale stop.requested from a prior run must not immediately stop us.
if (Test-Path -LiteralPath $stopRequestedPath) {
    Remove-Item -LiteralPath $stopRequestedPath -Force -ErrorAction SilentlyContinue
}

# --- Watchdog cooperation markers (additive; do not affect the queue protocol) ---
# heartbeat.json refreshes each loop so a supervisor can detect a hang (alive but stuck).
# last-exit.json is written on any graceful exit so a supervisor can tell an authorized
# stop (reason stop_requested|signal) from a crash (reason fatal_error). Clearing both at
# startup means: presence of last-exit.json => this run exited gracefully; its absence
# after a start => the process was hard-killed / lost power.
$heartbeatPath = Join-Path $directories["control"] "heartbeat.json"
$lastExitPath  = Join-Path $directories["control"] "last-exit.json"
$script:sawStopRequest = $false
$script:lastHeartbeat  = [DateTime]::MinValue
foreach ($staleMarker in @($lastExitPath, $heartbeatPath)) {
    if (Test-Path -LiteralPath $staleMarker) { Remove-Item -LiteralPath $staleMarker -Force -ErrorAction SilentlyContinue }
}

# Best-effort: if the console window is CLOSED (X), or on logoff/shutdown, record an authorized
# "signal" exit so a supervisor treats it as a manual stop rather than a crash. Implemented in C#
# so the native control-handler callback writes the file directly (a PowerShell scriptblock invoked
# from a native callback thread has no runspace and is unreliable). Ctrl+C is intentionally left to
# PowerShell's own handling, which runs the finally block and records reason "signal" there.
try {
    if ($IsWindows) {
        if (-not ("LoExecExitHandler" -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class LoExecExitHandler {
    public delegate bool Handler(uint ctrlType);
    [DllImport("kernel32.dll")] private static extern bool SetConsoleCtrlHandler(Handler handler, bool add);
    private static Handler _keepAlive;
    private static string _path;
    private static string _instance;
    public static void Arm(string path, string instance) {
        _path = path; _instance = instance;
        _keepAlive = new Handler(OnCtrl);
        SetConsoleCtrlHandler(_keepAlive, true);
    }
    private static bool OnCtrl(uint ctrlType) {
        // 2 = CTRL_CLOSE_EVENT, 5 = CTRL_LOGOFF_EVENT, 6 = CTRL_SHUTDOWN_EVENT
        if (ctrlType == 2 || ctrlType == 5 || ctrlType == 6) {
            try {
                int pid = System.Diagnostics.Process.GetCurrentProcess().Id;
                string json = "{\"instance_id\":\"" + _instance + "\",\"pid\":" + pid +
                    ",\"at_utc\":\"" + DateTime.UtcNow.ToString("o") + "\",\"reason\":\"signal\"}";
                File.WriteAllText(_path, json);
            } catch { }
        }
        return false; // never suppress; let default handling proceed to terminate
    }
}
"@
        }
        [LoExecExitHandler]::Arm($lastExitPath, $executorInstanceId)
    }
}
catch {
    Write-ExecutorLog ("Console-close handler unavailable; window-close will look like a crash to the watchdog " +
        "(stop cleanly via Ctrl+C or stop.requested instead): $($_.Exception.Message)") "WARN"
}

# ----------------------------------------------------------------------------
# Finalization
# ----------------------------------------------------------------------------

function Move-FinalizedTask {
    param(
        [Parameter(Mandatory)] [string]$RunningDirectory,
        [Parameter(Mandatory)] [string]$FinalStatus
    )

    $taskName = Split-Path -Leaf $RunningDirectory
    if (Test-InjectedFinalizeFault -TaskName $taskName) {
        throw [System.IO.IOException]::new("injected finalize fault (test) for '$taskName'")
    }
    $destinationRoot = if ($FinalStatus -eq "completed") { $directories["completed"] } else { $directories["failed"] }
    $destination = Join-Path $destinationRoot $taskName
    if (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $destinationRoot ("{0}-{1}" -f $taskName, [Guid]::NewGuid().ToString("N"))
    }
    Invoke-WithFileRetry -Action { Move-Item -LiteralPath $RunningDirectory -Destination $destination }
    return $destination
}

function Write-TaskResultJson {
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [string]$Status,
        $ExitCode,
        [string]$FailureReason
    )
    $finishedAt = Get-UtcNow
    $durationMs = [int][Math]::Round(($finishedAt - $Entry.StartedAt).TotalMilliseconds)
    $result = [ordered]@{
        task_id              = $Entry.TaskId
        status               = $Status
        exit_code            = $ExitCode
        started_at_utc       = (Format-Utc $Entry.StartedAt)
        finished_at_utc      = (Format-Utc $finishedAt)
        duration_ms          = $durationMs
        stdout_file          = "stdout.txt"
        stderr_file          = "stderr.txt"
        executor_instance_id = $executorInstanceId
        failure_reason       = $FailureReason
    }
    try {
        Write-JsonAtomic -Path (Join-Path $Entry.RunningDirectory "result.json") -Value $result
    }
    catch {
        Write-ExecutorLog "Failed writing result.json for '$($Entry.TaskId)': $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-TaskFinalize {
    # Resilient finalize used by the poll loop: write result.json, then attempt the running->completed/failed
    # move ISOLATED in try/catch. Returns $true on success; $false if the move is blocked (a locked file), so
    # the caller can DEFER it (Add-StuckFinalize) and keep serving the queue instead of wedging (D-0055 fix 2).
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [string]$Status,
        $ExitCode,
        [string]$FailureReason
    )
    Write-TaskResultJson -Entry $Entry -Status $Status -ExitCode $ExitCode -FailureReason $FailureReason
    try {
        $destination = Move-FinalizedTask -RunningDirectory $Entry.RunningDirectory -FinalStatus $Status
        Write-ExecutorLog "Task '$($Entry.TaskId)' finalized as '$Status' -> '$destination'."
        return $true
    }
    catch [System.IO.IOException], [System.UnauthorizedAccessException] {
        Write-ExecutorLog "Finalize move for '$($Entry.TaskId)' is blocked (a file in running/ is still locked): $($_.Exception.Message)" "WARN"
        return $false
    }
    catch {
        Write-ExecutorLog "Finalize move for '$($Entry.TaskId)' failed unexpectedly: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Write-FinalResult {
    # Best-effort finalize for callers that cannot defer (restart recovery, invalid task, shutdown). Writes
    # result.json and attempts the move; a blocked move is logged (the dir stays in running/ and the next
    # restart's recovery finalizes it as abandoned_after_restart) but NEVER throws into the caller.
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [string]$Status,
        $ExitCode,
        [string]$FailureReason
    )
    Write-TaskResultJson -Entry $Entry -Status $Status -ExitCode $ExitCode -FailureReason $FailureReason
    try {
        $destination = Move-FinalizedTask -RunningDirectory $Entry.RunningDirectory -FinalStatus $Status
        Write-ExecutorLog "Task '$($Entry.TaskId)' finalized as '$Status' -> '$destination'."
    }
    catch {
        Write-ExecutorLog "Finalize move for '$($Entry.TaskId)' blocked; left in running/ for restart recovery: $($_.Exception.Message)" "WARN"
    }
}

# Tasks whose finalize move was blocked -> retried each loop without wedging the pending-claim path.
$script:stuckFinalize = @{}   # taskId -> { Entry, Status, ExitCode, Reason, Attempts, FirstFailedAtUtc }
$script:pollErrorStreak = 0

function Add-StuckFinalize {
    param([Parameter(Mandatory)] $Entry, [Parameter(Mandatory)] [string]$Status, $ExitCode, [string]$Reason)
    # First deferral: sweep any orphaned reap-name process (e.g. a detached llama-server) that may be
    # holding the handle, then record for bounded retry.
    [void](Invoke-OrphanNameSweep -ReapNames $ReapProcessNames)
    $script:stuckFinalize[$Entry.TaskId] = [pscustomobject]@{
        Entry = $Entry; Status = $Status; ExitCode = $ExitCode; Reason = $Reason
        Attempts = 1; FirstFailedAtUtc = (Get-UtcNow)
    }
    Write-ExecutorLog "Task '$($Entry.TaskId)' finalize deferred (blocked); will retry without stalling the queue." "WARN"
}

function Complete-InvalidTask {
    param(
        [Parameter(Mandatory)] [string]$RunningDirectory,
        [Parameter(Mandatory)] [string]$TaskId,
        [Parameter(Mandatory)] [string]$Reason
    )

    $entry = [pscustomobject]@{
        TaskId           = $TaskId
        RunningDirectory = $RunningDirectory
        StartedAt        = (Get-UtcNow)
    }
    Write-FinalResult -Entry $entry -Status "invalid_task" -ExitCode $null -FailureReason $Reason
}

# ----------------------------------------------------------------------------
# Claim + start a task
# ----------------------------------------------------------------------------

function Start-QueuedTask {
    param([Parameter(Mandatory)] [string]$PendingDirectory)

    $taskName = Split-Path -Leaf $PendingDirectory
    $runningDirectory = Join-Path $directories["running"] $taskName

    # Atomically claim by moving the whole directory pending -> running.
    try {
        Move-Item -LiteralPath $PendingDirectory -Destination $runningDirectory -ErrorAction Stop
    }
    catch {
        # Lost the claim (e.g. it was already moved). Skip quietly.
        return
    }

    Write-ExecutorLog "Claimed task '$taskName' (pending -> running)."

    try {
        $taskPath = Join-Path $runningDirectory "task.json"
        if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) { throw "task.json is missing." }

        $task = Get-Content -LiteralPath $taskPath -Raw | ConvertFrom-Json

        $taskId = [string](Get-OptionalProperty $task "task_id" "")
        if ([string]::IsNullOrWhiteSpace($taskId)) { throw "task_id is missing." }
        if ($taskId -ne $taskName) { throw "task_id '$taskId' must match the task directory name '$taskName'." }

        $scriptFile = [string](Get-OptionalProperty $task "script_file" "")
        if ([string]::IsNullOrWhiteSpace($scriptFile)) { throw "script_file is missing." }

        $scriptPath = Join-Path $runningDirectory $scriptFile
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "script_file '$scriptFile' does not exist in the task directory."
        }

        $workingDirectory = [string](Get-OptionalProperty $task "working_directory" $runningDirectory)
        if ([string]::IsNullOrWhiteSpace($workingDirectory)) { $workingDirectory = $runningDirectory }
        if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
            throw "working_directory '$workingDirectory' does not exist."
        }

        $timeoutSeconds = [int](Get-OptionalProperty $task "timeout_seconds" $DefaultTimeoutSeconds)
        if ($timeoutSeconds -lt 0) { throw "timeout_seconds cannot be negative." }

        $visibleWindow = [bool](Get-OptionalProperty $task "visible_window" $false)

        $stdoutPath = Join-Path $runningDirectory "stdout.txt"
        $stderrPath = Join-Path $runningDirectory "stderr.txt"

        # Pass the script path as its own argument-list element; do NOT hand-quote
        # it. Start-Process quotes elements that contain spaces.
        $arguments = @(
            "-NoLogo", "-NoProfile", "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath
        )

        $startParameters = @{
            FilePath               = $PwshPath
            ArgumentList           = $arguments
            WorkingDirectory       = $workingDirectory
            PassThru               = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError  = $stderrPath
        }
        if ($IsWindows) {
            $startParameters["WindowStyle"] = if ($visibleWindow) { "Normal" } else { "Hidden" }
        }

        $startedAt = Get-UtcNow
        $process = Start-Process @startParameters

        $state = [ordered]@{
            task_id              = $taskId
            status               = "running"
            executor_instance_id = $executorInstanceId
            pid                  = $process.Id
            started_at_utc       = (Format-Utc $startedAt)
            timeout_seconds      = $timeoutSeconds
            script_file          = $scriptFile
            visible_window       = $visibleWindow
        }
        Write-JsonAtomic -Path (Join-Path $runningDirectory "state.json") -Value $state

        $script:activeTasks[$taskId] = [pscustomobject]@{
            TaskId           = $taskId
            Process          = $process
            RunningDirectory = $runningDirectory
            StartedAt        = $startedAt
            TimeoutSeconds   = $timeoutSeconds
        }

        Write-ExecutorLog "Started task '$taskId' as PID $($process.Id) (timeout=$timeoutSeconds s, visible=$visibleWindow)."
    }
    catch {
        $reason = $_.Exception.Message
        Write-ExecutorLog "Task '$taskName' is invalid: $reason" "ERROR"
        Complete-InvalidTask -RunningDirectory $runningDirectory -TaskId $taskName -Reason $reason
    }
}

# ----------------------------------------------------------------------------
# Restart recovery
# ----------------------------------------------------------------------------

function Restore-AbandonedTasks {
    $leftover = Get-ChildItem -LiteralPath $directories["running"] -Directory -ErrorAction SilentlyContinue
    foreach ($directory in $leftover) {
        $entry = [pscustomobject]@{
            TaskId           = $directory.Name
            RunningDirectory = $directory.FullName
            StartedAt        = (Get-UtcNow)
        }
        Write-ExecutorLog "Restart recovery: task '$($directory.Name)' was left in running; marking abandoned_after_restart." "WARN"
        Write-FinalResult -Entry $entry -Status "abandoned_after_restart" -ExitCode $null `
            -FailureReason "The prior executor stopped before recording completion. Not re-executed to avoid duplicate side effects."
    }
}

# ----------------------------------------------------------------------------
# Cancellation (shutdown)
# ----------------------------------------------------------------------------

function Stop-AllActiveTasks {
    param([string]$Reason = "Executor shutdown requested.")

    foreach ($taskId in @($script:activeTasks.Keys)) {
        $entry = $script:activeTasks[$taskId]
        try {
            $entry.Process.Refresh()
            if (-not $entry.Process.HasExited) {
                # Reap the whole tree incl. a detached llama-server so shutdown does not leave an orphan
                # holding a handle in running/ (same D-0055 hazard as the timeout path).
                [void](Stop-TaskTreeAndReap -ProcessId $entry.Process.Id -ReapNames $ReapProcessNames)
            }
        }
        catch { }
        Write-FinalResult -Entry $entry -Status "cancelled" -ExitCode $null -FailureReason $Reason
        $script:activeTasks.Remove($taskId)
    }
}

# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------

$shutdownReason = "Executor shutting down."
$fatalError = $null

try {
    Write-ExecutorLog "Executor starting."
    Write-ExecutorLog "Executor instance ID: $executorInstanceId"
    Write-ExecutorLog "Runtime root: $Root"
    Write-ExecutorLog "PowerShell: $PwshPath"
    Write-ExecutorLog ("Config: max_concurrent={0} queue_poll={1}s process_poll={2}ms default_timeout={3}s" -f `
        $MaxConcurrentTasks, $QueuePollSeconds, $ProcessPollMilliseconds, $DefaultTimeoutSeconds)

    Restore-AbandonedTasks

    $nextQueueScan = Get-UtcNow

    while ($true) {
      try {
        if (Test-Path -LiteralPath $stopRequestedPath) {
            Write-ExecutorLog "Stop request detected (control/stop.requested)." "WARN"
            $script:sawStopRequest = $true
            $shutdownReason = "Executor stop was requested."
            break
        }

        # Refresh the heartbeat (throttled). The added health fields let a supervisor detect a WEDGE -- a
        # fresh heartbeat that is nonetheless not finalizing / not making progress (the D-0055 blind spot,
        # fix 3) -- not just a stale-heartbeat hang.
        $heartbeatNow = Get-UtcNow
        if (($heartbeatNow - $script:lastHeartbeat).TotalMilliseconds -ge 2000) {
            $stuckCount = $script:stuckFinalize.Count
            $oldestStuckAge = 0.0
            $anyPastMax = $false
            foreach ($sv in $script:stuckFinalize.Values) {
                $age = ($heartbeatNow - $sv.FirstFailedAtUtc).TotalSeconds
                if ($age -gt $oldestStuckAge) { $oldestStuckAge = $age }
                if ($sv.Attempts -ge $StuckFinalizeMaxAttempts) { $anyPastMax = $true }
            }
            $degraded = $anyPastMax -or ($script:pollErrorStreak -ge $PollErrorThreshold)
            $degradedReason =
                if (-not $degraded) { $null }
                elseif ($anyPastMax) { "finalize blocked for $stuckCount task(s) past $StuckFinalizeMaxAttempts attempts" }
                else { "poll error streak $($script:pollErrorStreak) >= $PollErrorThreshold" }
            try {
                Write-JsonAtomic -Path $heartbeatPath -Value ([ordered]@{
                    instance_id                       = $executorInstanceId
                    pid                               = $PID
                    at_utc                            = (Format-Utc $heartbeatNow)
                    active_tasks                      = $script:activeTasks.Count
                    stuck_finalize_count              = $stuckCount
                    oldest_stuck_finalize_age_seconds = [int][Math]::Round($oldestStuckAge)
                    poll_error_streak                 = $script:pollErrorStreak
                    degraded                          = $degraded
                    degraded_reason                   = $degradedReason
                })
            }
            catch { }
            $script:lastHeartbeat = $heartbeatNow
        }

        # 1) Poll active tasks for exit / timeout. Each finalize is ISOLATED: a blocked move on ONE task is
        #    DEFERRED (Add-StuckFinalize) instead of throwing and starving the pending-claim step (fix 2).
        foreach ($taskId in @($script:activeTasks.Keys)) {
            $entry = $script:activeTasks[$taskId]
            try { $entry.Process.Refresh() } catch { }

            if ($entry.Process.HasExited) {
                $exitCode = $entry.Process.ExitCode
                $status = if ($exitCode -eq 0) { "completed" } else { "failed" }
                $reason = if ($exitCode -eq 0) { $null } else { "Script exited with code $exitCode." }
                $script:activeTasks.Remove($taskId)
                if (-not (Invoke-TaskFinalize -Entry $entry -Status $status -ExitCode $exitCode -FailureReason $reason)) {
                    Add-StuckFinalize -Entry $entry -Status $status -ExitCode $exitCode -Reason $reason
                }
                $nextQueueScan = Get-UtcNow
                continue
            }

            if ($entry.TimeoutSeconds -gt 0) {
                $elapsed = (Get-UtcNow) - $entry.StartedAt
                if ($elapsed.TotalSeconds -ge $entry.TimeoutSeconds) {
                    Write-ExecutorLog "Task '$taskId' exceeded timeout of $($entry.TimeoutSeconds)s; reaping process tree + orphans, then finalizing." "WARN"
                    # fix 1: reap the WHOLE tree incl. a detached llama-server BEFORE the finalize move.
                    $reaped = Stop-TaskTreeAndReap -ProcessId $entry.Process.Id -ReapNames $ReapProcessNames
                    if ($reaped -gt 0) { Write-ExecutorLog "Reaped $reaped extra/orphaned process(es) for timed-out task '$taskId'." "WARN" }
                    $script:activeTasks.Remove($taskId)
                    $toReason = "Task exceeded its timeout of $($entry.TimeoutSeconds) seconds."
                    if (-not (Invoke-TaskFinalize -Entry $entry -Status "timed_out" -ExitCode $null -FailureReason $toReason)) {
                        Add-StuckFinalize -Entry $entry -Status "timed_out" -ExitCode $null -Reason $toReason
                    }
                    $nextQueueScan = Get-UtcNow
                }
            }
        }

        # 1b) Retry any DEFERRED (blocked) finalizes -- each isolated. This must NOT block the claim step below.
        foreach ($stuckId in @($script:stuckFinalize.Keys)) {
            $sv = $script:stuckFinalize[$stuckId]
            if (Invoke-TaskFinalize -Entry $sv.Entry -Status $sv.Status -ExitCode $sv.ExitCode -FailureReason $sv.Reason) {
                $script:stuckFinalize.Remove($stuckId)
                Write-ExecutorLog "Deferred finalize for '$stuckId' recovered after $($sv.Attempts) attempt(s)."
            }
            else {
                $sv.Attempts++
                if ($sv.Attempts -eq $StuckFinalizeMaxAttempts) {
                    Write-ExecutorLog "Task '$stuckId' finalize still blocked after $($sv.Attempts) attempts; executor now reports DEGRADED so the watchdog can recover it." "ERROR"
                }
            }
        }

        # 2) Claim new tasks (in lexicographic order) if we have capacity.
        if ((Get-UtcNow) -ge $nextQueueScan -and $script:activeTasks.Count -lt $MaxConcurrentTasks) {
            $pending = Get-ChildItem -LiteralPath $directories["pending"] -Directory -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($pendingTask in $pending) {
                if ($script:activeTasks.Count -ge $MaxConcurrentTasks) { break }
                if (Test-Path -LiteralPath $stopRequestedPath) { break }
                Start-QueuedTask -PendingDirectory $pendingTask.FullName
            }
            $nextQueueScan = (Get-UtcNow).AddSeconds($QueuePollSeconds)
        }

        # A full clean iteration reached the claim step -> reset the poll-error streak (health signal).
        $script:pollErrorStreak = 0
      }
      catch [System.IO.IOException], [System.UnauthorizedAccessException] {
          # Belt-and-suspenders for the 2026-07-24 crash class: a transient sharing violation that slipped
          # past the per-operation retry does not kill the executor - log it, COUNT it toward the degraded
          # health signal (so a persistent poll error surfaces to the watchdog), and keep polling.
          $script:pollErrorStreak++
          Write-ExecutorLog "Transient IO error in poll loop (streak $($script:pollErrorStreak)); continuing: $($_.Exception.Message)" "WARN"
      }

        Start-Sleep -Milliseconds $ProcessPollMilliseconds
    }
}
catch {
    $fatalError = $_
    $shutdownReason = "Executor terminated because of a fatal error: $($_.Exception.Message)"
    Write-ExecutorLog "Fatal executor error: $($_.Exception.Message)" "ERROR"
}
finally {
    # Runs on normal stop, on Ctrl+C, and on fatal error. Cancels anything
    # still active, records results, releases the lock, and exits cleanly.
    try { Stop-AllActiveTasks -Reason $shutdownReason } catch { Write-ExecutorLog "Error during cancellation: $($_.Exception.Message)" "ERROR" }

    # Record how we exited so a supervisor can distinguish an authorized stop from a crash.
    # Written before the lock is released, so a watchdog that sees the lock free will find it.
    try {
        $exitReason = if ($null -ne $fatalError) { "fatal_error" }
                      elseif ($script:sawStopRequest) { "stop_requested" }
                      else { "signal" }
        Write-JsonAtomic -Path $lastExitPath -Value ([ordered]@{
            instance_id = $executorInstanceId
            pid         = $PID
            at_utc      = (Format-Utc (Get-UtcNow))
            reason      = $exitReason
        })
    }
    catch { Write-ExecutorLog "Failed writing last-exit.json: $($_.Exception.Message)" "ERROR" }

    if (Test-Path -LiteralPath $stopRequestedPath) {
        Remove-Item -LiteralPath $stopRequestedPath -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
    Write-ExecutorLog "Executor stopped."
}

if ($null -ne $fatalError) { throw $fatalError }
