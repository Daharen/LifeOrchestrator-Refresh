<#
.SYNOPSIS
    Submit a task to the Trusted High-Risk Bootstrap Executor queue.

.DESCRIPTION
    Builds a task directory under runtime/staging, writes task.ps1 and task.json,
    then atomically moves the finished directory into runtime/pending. The
    executor never reads from staging, so a task only becomes visible once the
    single atomic move completes.

    Refuses to overwrite an existing task with the same id.

.EXAMPLE
    ./Submit-BootstrapTask.ps1 -TaskId instruction-000101 `
        -ScriptText 'Write-Output "hi"' -SubmittedBy claude -Description "demo"

.EXAMPLE
    ./Submit-BootstrapTask.ps1 -TaskId instruction-000102 `
        -SourceScriptPath ./examples/hello-world.ps1
#>
[CmdletBinding(DefaultParameterSetName = "ScriptPath")]
param(
    [Parameter(Mandatory)]
    [ValidatePattern("^[A-Za-z0-9._-]+$")]
    [string]$TaskId,

    [Parameter(Mandatory, ParameterSetName = "ScriptPath")]
    [string]$SourceScriptPath,

    [Parameter(Mandatory, ParameterSetName = "ScriptText")]
    [string]$ScriptText,

    [string]$Root = (Join-Path $PSScriptRoot "runtime"),
    [string]$WorkingDirectory,
    [int]$TimeoutSeconds,
    [bool]$VisibleWindow = $false,
    [string]$SubmittedBy = "unknown",
    [string]$Description = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Reject dangerous ids the character pattern alone would still allow.
if ($TaskId -in @(".", "..") -or $TaskId -notmatch "[A-Za-z0-9]") {
    throw "TaskId must contain at least one alphanumeric character and cannot be '.' or '..'."
}

$stagingRoot   = Join-Path $Root "staging"
$pendingRoot   = Join-Path $Root "pending"
$runningRoot   = Join-Path $Root "running"
$completedRoot = Join-Path $Root "completed"
$failedRoot    = Join-Path $Root "failed"

foreach ($path in @($stagingRoot, $pendingRoot, $runningRoot, $completedRoot, $failedRoot)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

# Refuse to collide with a task id already anywhere in the pipeline.
foreach ($rootToCheck in @($pendingRoot, $runningRoot, $completedRoot, $failedRoot)) {
    if (Test-Path -LiteralPath (Join-Path $rootToCheck $TaskId)) {
        throw "Task '$TaskId' already exists under '$rootToCheck'."
    }
}

$stagingDirectory = Join-Path $stagingRoot "$TaskId.tmp"
$pendingDirectory = Join-Path $pendingRoot $TaskId

if (Test-Path -LiteralPath $stagingDirectory) {
    throw "A staging directory for '$TaskId' already exists: $stagingDirectory"
}

New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

try {
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    $destinationScriptPath = Join-Path $stagingDirectory "task.ps1"

    if ($PSCmdlet.ParameterSetName -eq "ScriptPath") {
        if (-not (Test-Path -LiteralPath $SourceScriptPath -PathType Leaf)) {
            throw "Source script '$SourceScriptPath' was not found."
        }
        Copy-Item -LiteralPath $SourceScriptPath -Destination $destinationScriptPath
    }
    else {
        [System.IO.File]::WriteAllText($destinationScriptPath, $ScriptText, $utf8WithoutBom)
    }

    $task = [ordered]@{
        task_id      = $TaskId
        script_file  = "task.ps1"
        visible_window = $VisibleWindow
        submitted_by = $SubmittedBy
        description  = $Description
    }
    # Only pin a timeout when the caller supplied one; otherwise the executor
    # applies its configured default_timeout_seconds.
    if ($PSBoundParameters.ContainsKey("TimeoutSeconds")) {
        $task["timeout_seconds"] = $TimeoutSeconds
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $task["working_directory"] = $WorkingDirectory
    }

    $taskJson = $task | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $stagingDirectory "task.json"), $taskJson, $utf8WithoutBom)

    # Atomic publish: rename the completed staging directory into pending.
    Move-Item -LiteralPath $stagingDirectory -Destination $pendingDirectory
    Write-Output $pendingDirectory
}
catch {
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}
