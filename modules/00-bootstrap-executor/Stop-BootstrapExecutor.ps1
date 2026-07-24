<#
.SYNOPSIS
    Request an orderly shutdown of the Trusted High-Risk Bootstrap Executor.

.DESCRIPTION
    Creates runtime/control/stop.requested. The running executor notices this
    file, stops claiming new tasks, cancels active tasks, records their results,
    releases its lock, and exits.

    This helper does nothing else. It does not install persistence, modify
    startup settings, or search for unrelated PowerShell processes.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot "runtime")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$controlDirectory = Join-Path $Root "control"
New-Item -ItemType Directory -Path $controlDirectory -Force | Out-Null

$stopPath = Join-Path $controlDirectory "stop.requested"
[System.IO.File]::WriteAllText(
    $stopPath,
    [DateTime]::UtcNow.ToString("o"),
    [System.Text.UTF8Encoding]::new($false))

Write-Output "Stop requested at: $stopPath"
