#requires -Version 7.0
<#
.SYNOPSIS
  CONFIRM that ops/setup/out/staging-plan.txt is well-formed and actionable, WITHOUT downloading
  the tens-of-GB payloads. Life Orchestrator portability follow-on (FANOUT_AGENT_002, plan
  fo-15-27a03513, CPU lane). NO GPU / model invocation; HTTP-HEAD reachability only.
.DESCRIPTION
  Parses the emitted staging plan, HTTP-HEADs each real URL (advertised status + size; a 405
  falls back to a 1-byte ranged GET, NOT a full pull), flags every TODO_CONFIRM URL / missing
  sha256 / dead link, and writes ops/setup/out/staging-plan-confirm.json. Emits the same object on
  stdout. Off-box / no internet: pass -Offline (or it degrades per-URL) -- it still confirms
  structure + sha/URL presence and never throws. Exit 0 iff the plan is well-formed.
.EXAMPLE
  pwsh -NoProfile -File ops/setup/Confirm-StagingPlan.ps1                      # live HEAD probe on the box
.EXAMPLE
  pwsh -NoProfile -File ops/setup/Confirm-StagingPlan.ps1 -Offline             # structure-only, no network
#>
[CmdletBinding()]
param(
    [string]$PlanPath,
    [string]$OutPath,
    [switch]$Offline,
    [switch]$NoProbe,
    [int]$TimeoutSec = 20,
    [string]$MockResultsJson
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Diag([string]$m) { [Console]::Error.WriteLine("[confirm-staging] $m") }

$here = $PSScriptRoot
Import-Module (Join-Path $here 'LifeorchStagingConfirm.psm1') -DisableNameChecking -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($PlanPath)) { $PlanPath = Join-Path $here 'out/staging-plan.txt' }
if ([string]::IsNullOrWhiteSpace($OutPath)) { $OutPath = Join-Path $here 'out/staging-plan-confirm.json' }

$mock = $null
if (-not [string]::IsNullOrWhiteSpace($MockResultsJson)) {
    try { $mock = $MockResultsJson | ConvertFrom-Json } catch { Diag "bad -MockResultsJson: $($_.Exception.Message)"; $mock = $null }
}

$cfArgs = @{ PlanPath = $PlanPath; TimeoutSec = $TimeoutSec }
if ($Offline) { $cfArgs['Offline'] = $true }
if ($NoProbe) { $cfArgs['NoProbe'] = $true }
if ($null -ne $mock) { $cfArgs['MockResults'] = $mock }

$confirm = Confirm-StagingPlan @cfArgs

# write the confirm JSON (UTF-8 no BOM, LF) to out/
$json = ($confirm | ConvertTo-Json -Depth 40)
$dir = Split-Path -Parent $OutPath
if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($OutPath, ($json -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
Diag "wrote $OutPath (well_formed=$($confirm.well_formed) ok=$($confirm.ok) mode=$($confirm.probe_mode))"
Diag "summary: entries=$($confirm.summary.entries) reachable=$($confirm.summary.url_reachable) dead=$($confirm.summary.url_dead) offline=$($confirm.summary.url_offline) placeholder=$($confirm.summary.url_placeholder) missing_sha=$($confirm.summary.missing_sha256) actionable=$($confirm.summary.actionable_now)"
foreach ($b in $confirm.blockers) { Diag "blocker: $b" }

[Console]::Out.WriteLine($json)
if ($confirm.well_formed) { exit 0 } else { exit 1 }
