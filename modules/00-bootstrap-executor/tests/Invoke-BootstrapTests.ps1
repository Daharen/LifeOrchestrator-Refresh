<#
.SYNOPSIS
    Deterministic integration tests for the Trusted High-Risk Bootstrap Executor.

.DESCRIPTION
    Exercises the twelve behaviours required by the specification. Each test uses
    its own fresh runtime root and starts/stops its own executor instance so the
    tests do not interfere with each other.

    Run from anywhere:
        pwsh -NoProfile -File ./tests/Invoke-BootstrapTests.ps1

    Exits 0 if every test passes, 1 otherwise.
#>
[CmdletBinding()]
param(
    [string]$PwshPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$moduleRoot     = Split-Path -Parent $PSScriptRoot
$startScript    = Join-Path $moduleRoot "Start-BootstrapExecutor.ps1"
$submitScript   = Join-Path $moduleRoot "Submit-BootstrapTask.ps1"
$stopScript     = Join-Path $moduleRoot "Stop-BootstrapExecutor.ps1"

if ([string]::IsNullOrWhiteSpace($PwshPath)) {
    $PwshPath = (Get-Process -Id $PID).Path
}

$testWorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tbe-tests-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testWorkRoot -Force | Out-Null

$script:results = New-Object System.Collections.ArrayList

function New-RuntimeRoot {
    param([string]$Name)
    $root = Join-Path $testWorkRoot $Name
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Start-Executor {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [int]$MaxConcurrentTasks = 4
    )
    $hostLog = Join-Path $Root "executor.host.log"
    $args = @(
        "-NoProfile", "-File", $startScript,
        "-Root", $Root,
        "-QueuePollSeconds", "1",
        "-ProcessPollMilliseconds", "200",
        "-MaxConcurrentTasks", "$MaxConcurrentTasks",
        "-PwshPath", $PwshPath
    )
    $proc = Start-Process -FilePath $PwshPath -ArgumentList $args -PassThru `
        -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err"
    return $proc
}

function Stop-Executor {
    param(
        [Parameter(Mandatory)] $Process,
        [Parameter(Mandatory)] [string]$Root,
        [int]$WaitSeconds = 20
    )
    try { & $PwshPath -NoProfile -File $stopScript -Root $Root | Out-Null } catch { }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $Process.HasExited) {
        try { & taskkill.exe /PID $Process.Id /T /F 2>&1 | Out-Null } catch { }
        try { $Process.Kill($true) } catch { }
    }
}

function Submit-Task {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$TaskId,
        [Parameter(Mandatory)] [string]$ScriptText,
        [int]$TimeoutSeconds = -1
    )
    $params = @{ Root = $Root; TaskId = $TaskId; ScriptText = $ScriptText }
    if ($TimeoutSeconds -ge 0) { $params["TimeoutSeconds"] = $TimeoutSeconds }
    return & $submitScript @params
}

function Get-TaskResult {
    param([string]$Root, [string]$TaskId)
    foreach ($bucket in @("completed", "failed")) {
        $dir = Join-Path $Root (Join-Path $bucket $TaskId)
        $resultPath = Join-Path $dir "result.json"
        if (Test-Path -LiteralPath $resultPath) {
            return [pscustomobject]@{
                Bucket = $bucket
                Dir    = $dir
                Result = (Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json)
            }
        }
    }
    return $null
}

function Wait-TaskResult {
    param([string]$Root, [string]$TaskId, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $r = Get-TaskResult -Root $Root -TaskId $TaskId
        if ($null -ne $r) { return $r }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    try {
        & $Body
        [void]$script:results.Add([pscustomobject]@{ Name = $Name; Passed = $true; Message = "" })
        Write-Host "PASS: $Name" -ForegroundColor Green
    }
    catch {
        [void]$script:results.Add([pscustomobject]@{ Name = $Name; Passed = $false; Message = $_.Exception.Message })
        Write-Host "FAIL: $Name -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# ---------------------------------------------------------------------------
# 1. hello-world completes with exit 0 and captured stdout
# ---------------------------------------------------------------------------
Invoke-Test "01 hello-world completes (exit 0, stdout captured)" {
    $root = New-RuntimeRoot "t01"
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000001" -ScriptText 'Write-Output "hello-marker-123"' | Out-Null
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000001" -TimeoutSeconds 30
        Assert-True ($null -ne $r) "No result was produced."
        Assert-True ($r.Bucket -eq "completed") "Expected completed, got $($r.Bucket)."
        Assert-True ($r.Result.status -eq "completed") "status was $($r.Result.status)."
        Assert-True ($r.Result.exit_code -eq 0) "exit_code was $($r.Result.exit_code)."
        $stdout = Get-Content -LiteralPath (Join-Path $r.Dir "stdout.txt") -Raw
        Assert-True ($stdout -match "hello-marker-123") "stdout did not contain the marker."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 2. throwing task fails with captured stderr
# ---------------------------------------------------------------------------
Invoke-Test "02 throwing task fails (stderr captured)" {
    $root = New-RuntimeRoot "t02"
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000002" -ScriptText 'Write-Error "err-marker-xyz"; throw "boom"' | Out-Null
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000002" -TimeoutSeconds 30
        Assert-True ($null -ne $r) "No result was produced."
        Assert-True ($r.Bucket -eq "failed") "Expected failed, got $($r.Bucket)."
        Assert-True ($r.Result.status -eq "failed") "status was $($r.Result.status)."
        Assert-True ($r.Result.exit_code -ne 0) "exit_code should be non-zero."
        $stderr = Get-Content -LiteralPath (Join-Path $r.Dir "stderr.txt") -Raw
        Assert-True ($stderr -match "err-marker-xyz") "stderr did not contain the marker."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 3. sleeping task exceeds timeout and is terminated
# ---------------------------------------------------------------------------
Invoke-Test "03 task exceeds timeout and is terminated" {
    $root = New-RuntimeRoot "t03"
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000003" -ScriptText 'Start-Sleep -Seconds 120' -TimeoutSeconds 2 | Out-Null
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000003" -TimeoutSeconds 30
        Assert-True ($null -ne $r) "No result was produced."
        Assert-True ($r.Bucket -eq "failed") "Expected failed bucket."
        Assert-True ($r.Result.status -eq "timed_out") "status was $($r.Result.status)."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 4. at least three tasks execute concurrently
# ---------------------------------------------------------------------------
Invoke-Test "04 at least three tasks run concurrently" {
    $root = New-RuntimeRoot "t04"
    $proc = Start-Executor -Root $root -MaxConcurrentTasks 4
    try {
        foreach ($i in 1..4) {
            Submit-Task -Root $root -TaskId ("instruction-00004{0}" -f $i) -ScriptText 'Start-Sleep -Seconds 5' | Out-Null
        }
        $runningDir = Join-Path $root "running"
        $maxObserved = 0
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            $count = @(Get-ChildItem -LiteralPath $runningDir -Directory -ErrorAction SilentlyContinue).Count
            if ($count -gt $maxObserved) { $maxObserved = $count }
            if ($maxObserved -ge 3) { break }
            Start-Sleep -Milliseconds 200
        }
        Assert-True ($maxObserved -ge 3) "Max concurrent observed was $maxObserved (expected >= 3)."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 5. a directory left under staging is ignored
# ---------------------------------------------------------------------------
Invoke-Test "05 staging directory is ignored" {
    $root = New-RuntimeRoot "t05"
    $runtime = $root
    $ghost = Join-Path (Join-Path $runtime "staging") "instruction-ghost.tmp"
    New-Item -ItemType Directory -Path $ghost -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ghost "task.ps1") -Value 'Write-Output "should not run"'
    Set-Content -LiteralPath (Join-Path $ghost "task.json") -Value '{"task_id":"instruction-ghost","script_file":"task.ps1"}'

    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000051" -ScriptText 'Write-Output "real"' | Out-Null
        $real = Wait-TaskResult -Root $root -TaskId "instruction-000051" -TimeoutSeconds 30
        Assert-True ($null -ne $real) "The real task never completed."
        Start-Sleep -Seconds 2
        Assert-True (Test-Path -LiteralPath $ghost) "The staging ghost directory disappeared."
        $ghostResult = Get-TaskResult -Root $root -TaskId "instruction-ghost"
        Assert-True ($null -eq $ghostResult) "The staging ghost task was executed."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 6. a task is atomically moved from pending to running before execution
# ---------------------------------------------------------------------------
Invoke-Test "06 task moves pending -> running (not copied)" {
    $root = New-RuntimeRoot "t06"
    $runtime = $root
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000006" -ScriptText 'Start-Sleep -Seconds 4' | Out-Null
        $runningTaskDir = Join-Path (Join-Path $runtime "running") "instruction-000006"
        $pendingTaskDir = Join-Path (Join-Path $runtime "pending") "instruction-000006"
        $seenRunning = $false
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath (Join-Path $runningTaskDir "state.json")) {
                $seenRunning = $true
                Assert-True (-not (Test-Path -LiteralPath $pendingTaskDir)) "Task existed in pending AND running simultaneously."
                break
            }
            Start-Sleep -Milliseconds 100
        }
        Assert-True $seenRunning "Never observed the task under running with state.json."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 7. a task cannot be executed twice
# ---------------------------------------------------------------------------
Invoke-Test "07 task executes exactly once" {
    $root = New-RuntimeRoot "t07"
    $sentinel = Join-Path $root "sentinel.txt"
    $sentinelForScript = $sentinel.Replace("\", "\\")
    $proc = Start-Executor -Root $root
    try {
        $scriptText = "Add-Content -LiteralPath '$sentinelForScript' -Value 'ran'"
        Submit-Task -Root $root -TaskId "instruction-000007" -ScriptText $scriptText | Out-Null
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000007" -TimeoutSeconds 30
        Assert-True ($null -ne $r) "No result produced."
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $sentinel -ErrorAction SilentlyContinue)
        Assert-True ($lines.Count -eq 1) "Sentinel had $($lines.Count) lines (expected exactly 1)."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 8. a task left in running is marked abandoned after restart
# ---------------------------------------------------------------------------
Invoke-Test "08 task left in running -> abandoned_after_restart" {
    $root = New-RuntimeRoot "t08"
    $runtime = $root
    $running = Join-Path $runtime "running"
    $orphan = Join-Path $running "instruction-000008"
    New-Item -ItemType Directory -Path $orphan -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $orphan "task.ps1") -Value 'Write-Output "orphan"'
    Set-Content -LiteralPath (Join-Path $orphan "task.json") -Value '{"task_id":"instruction-000008","script_file":"task.ps1"}'

    $proc = Start-Executor -Root $root
    try {
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000008" -TimeoutSeconds 20
        Assert-True ($null -ne $r) "No result produced for the orphan."
        Assert-True ($r.Bucket -eq "failed") "Orphan not in failed bucket."
        Assert-True ($r.Result.status -eq "abandoned_after_restart") "status was $($r.Result.status)."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# 9. duplicate task id is rejected by the submission helper
# ---------------------------------------------------------------------------
Invoke-Test "09 duplicate task id is rejected" {
    $root = New-RuntimeRoot "t09"
    Submit-Task -Root $root -TaskId "instruction-000009" -ScriptText 'Write-Output "a"' | Out-Null
    $threw = $false
    try {
        Submit-Task -Root $root -TaskId "instruction-000009" -ScriptText 'Write-Output "b"' | Out-Null
    }
    catch { $threw = $true }
    Assert-True $threw "The submission helper accepted a duplicate task id."
}

# ---------------------------------------------------------------------------
# 10. stop helper causes orderly cancellation and shutdown
# ---------------------------------------------------------------------------
Invoke-Test "10 stop helper cancels active task and shuts down" {
    $root = New-RuntimeRoot "t10"
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000010" -ScriptText 'Start-Sleep -Seconds 60' | Out-Null
        $runningTaskDir = Join-Path (Join-Path $root "running") "instruction-000010"
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath (Join-Path $runningTaskDir "state.json"))) {
            Start-Sleep -Milliseconds 200
        }
        Assert-True (Test-Path -LiteralPath (Join-Path $runningTaskDir "state.json")) "Task never started."

        & $PwshPath -NoProfile -File $stopScript -Root $root | Out-Null
        $exitDeadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $exitDeadline) {
            $proc.Refresh(); if ($proc.HasExited) { break }
            Start-Sleep -Milliseconds 200
        }
        Assert-True ($proc.HasExited) "Executor did not exit after stop request."
        $r = Get-TaskResult -Root $root -TaskId "instruction-000010"
        Assert-True ($null -ne $r) "No result for the cancelled task."
        Assert-True ($r.Result.status -eq "cancelled") "status was $($r.Result.status) (expected cancelled)."
    }
    finally { Stop-Executor -Process $proc -Root $root -WaitSeconds 5 }
}

# ---------------------------------------------------------------------------
# 11. a second executor cannot acquire the same runtime lock
# ---------------------------------------------------------------------------
Invoke-Test "11 second executor cannot acquire the lock" {
    $root = New-RuntimeRoot "t11"
    $procA = Start-Executor -Root $root
    try {
        Start-Sleep -Seconds 2  # let A acquire the lock
        $errLog = Join-Path $root "second.err"
        $outLog = Join-Path $root "second.out"
        $args = @("-NoProfile", "-File", $startScript, "-Root", $root, "-PwshPath", $PwshPath)
        $procB = Start-Process -FilePath $PwshPath -ArgumentList $args -PassThru -Wait `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        Assert-True ($procB.ExitCode -ne 0) "Second executor exited 0 (expected failure)."
        $err = (Get-Content -LiteralPath $errLog -Raw -ErrorAction SilentlyContinue)
        Assert-True ($err -match "already using this runtime") "Second executor did not report the lock conflict."
    }
    finally { Stop-Executor -Process $procA -Root $root }
}

# ---------------------------------------------------------------------------
# 12. completed task scripts and metadata are preserved
# ---------------------------------------------------------------------------
Invoke-Test "12 completed task files are preserved" {
    $root = New-RuntimeRoot "t12"
    $proc = Start-Executor -Root $root
    try {
        Submit-Task -Root $root -TaskId "instruction-000012" -ScriptText 'Write-Output "keep me"' | Out-Null
        $r = Wait-TaskResult -Root $root -TaskId "instruction-000012" -TimeoutSeconds 30
        Assert-True ($null -ne $r) "No result produced."
        Assert-True (Test-Path -LiteralPath (Join-Path $r.Dir "task.ps1")) "task.ps1 was not preserved."
        Assert-True (Test-Path -LiteralPath (Join-Path $r.Dir "task.json")) "task.json was not preserved."
        Assert-True (Test-Path -LiteralPath (Join-Path $r.Dir "result.json")) "result.json missing."
    }
    finally { Stop-Executor -Process $proc -Root $root }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================ SUMMARY ================"
$passed = @($script:results | Where-Object { $_.Passed }).Count
$total = $script:results.Count
foreach ($result in $script:results) {
    $tag = if ($result.Passed) { "PASS" } else { "FAIL" }
    Write-Host ("{0}  {1}" -f $tag, $result.Name)
    if (-not $result.Passed) { Write-Host ("       -> {0}" -f $result.Message) }
}
Write-Host "----------------------------------------"
Write-Host ("{0}/{1} tests passed" -f $passed, $total)

try { Remove-Item -LiteralPath $testWorkRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

if ($passed -ne $total) { exit 1 }
exit 0
