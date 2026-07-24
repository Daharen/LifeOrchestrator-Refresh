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
    [string]$PwshPath
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

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $temporaryPath = "$Path.tmp"
    $json = $Value | ConvertTo-Json -Depth 20
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8WithoutBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
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

# ----------------------------------------------------------------------------
# Finalization
# ----------------------------------------------------------------------------

function Move-FinalizedTask {
    param(
        [Parameter(Mandatory)] [string]$RunningDirectory,
        [Parameter(Mandatory)] [string]$FinalStatus
    )

    $taskName = Split-Path -Leaf $RunningDirectory
    $destinationRoot = if ($FinalStatus -eq "completed") { $directories["completed"] } else { $directories["failed"] }
    $destination = Join-Path $destinationRoot $taskName
    if (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $destinationRoot ("{0}-{1}" -f $taskName, [Guid]::NewGuid().ToString("N"))
    }
    Move-Item -LiteralPath $RunningDirectory -Destination $destination
    return $destination
}

function Write-FinalResult {
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

    $destination = Move-FinalizedTask -RunningDirectory $Entry.RunningDirectory -FinalStatus $Status
    Write-ExecutorLog "Task '$($Entry.TaskId)' finalized as '$Status' -> '$destination'."
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
                Stop-ProcessTree -ProcessId $entry.Process.Id
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
        if (Test-Path -LiteralPath $stopRequestedPath) {
            Write-ExecutorLog "Stop request detected (control/stop.requested)." "WARN"
            $shutdownReason = "Executor stop was requested."
            break
        }

        # 1) Poll active tasks for exit / timeout.
        foreach ($taskId in @($script:activeTasks.Keys)) {
            $entry = $script:activeTasks[$taskId]
            $entry.Process.Refresh()

            if ($entry.Process.HasExited) {
                $exitCode = $entry.Process.ExitCode
                $status = if ($exitCode -eq 0) { "completed" } else { "failed" }
                $reason = if ($exitCode -eq 0) { $null } else { "Script exited with code $exitCode." }
                Write-FinalResult -Entry $entry -Status $status -ExitCode $exitCode -FailureReason $reason
                $script:activeTasks.Remove($taskId)
                $nextQueueScan = Get-UtcNow
                continue
            }

            if ($entry.TimeoutSeconds -gt 0) {
                $elapsed = (Get-UtcNow) - $entry.StartedAt
                if ($elapsed.TotalSeconds -ge $entry.TimeoutSeconds) {
                    Write-ExecutorLog "Task '$taskId' exceeded timeout of $($entry.TimeoutSeconds)s; terminating." "WARN"
                    Stop-ProcessTree -ProcessId $entry.Process.Id
                    Write-FinalResult -Entry $entry -Status "timed_out" -ExitCode $null `
                        -FailureReason "Task exceeded its timeout of $($entry.TimeoutSeconds) seconds."
                    $script:activeTasks.Remove($taskId)
                    $nextQueueScan = Get-UtcNow
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
