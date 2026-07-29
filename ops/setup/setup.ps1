#requires -Version 7.0
<#
.SYNOPSIS
  Life Orchestrator portability / new-machine bring-up -- Stage-1 bootstrap (ops/setup).
  FANOUT_AGENT_002, plan fo-14-5ea064b6. CPU-only. NO GPU/model invocation.
.DESCRIPTION
  A thin CLI over LifeorchConfig.psm1 + LifeorchSetup.psm1. Actions:
    prereq  -- check prereqs (pwsh>=7.4, git, .NET SDK, curl.exe, CUDA via nvidia-smi) + report pass/fail.
    detect  -- DETECT this machine's repo-root + data-root + profile and WRITE ops/setup/config.json.
    gen     -- generate a machine-specific models.json (VRAM-sized, data-root-repointed) to
               ops/setup/out/models.machine.json + a staging plan to ops/setup/out/staging-plan.txt.
               Reads modules/07-model-gateway/models.json READ-ONLY as the base; NEVER writes it.
    verify  -- CPU-only verify pass (config resolves, repo paths exist, models.machine.json valid,
               executor heartbeat fresh + degraded:false).
    all     -- prereq -> gen -> verify (add -WriteConfig to also (re)write config.json).
  Emits ONE lifeorch.setup.result/0.1 JSON object on stdout; human logs go to stderr.
  Off-Windows, Windows-only probes degrade to 'unknown' and nothing throws (the cloud gate).
.EXAMPLE
  pwsh -NoProfile -File ops/setup/setup.ps1 -Action all -WriteConfig
.EXAMPLE
  pwsh -NoProfile -File ops/setup/setup.ps1 -Action gen -VramMiBOverride 11264 -MockNvidiaSmiText 'NVIDIA GeForce RTX 2080 Ti, 11264'
#>
[CmdletBinding()]
param(
    [ValidateSet('prereq', 'detect', 'gen', 'verify', 'all')]
    [string]$Action = 'all',
    [string]$RepoRoot,
    [string]$DataRoot,
    [string]$BaseModelsPath,
    [int]$VramMiBOverride = 0,
    [int]$DisplayReserveMiB = 1024,
    [string]$MockNvidiaSmiText,
    [switch]$WriteConfig,
    [switch]$SkipHeartbeat,
    [int]$MaxHeartbeatAgeSeconds = 120
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = [System.Text.UTF8Encoding]::new($false)
function Diag([string]$m) { [Console]::Error.WriteLine("[setup] $m") }
function WriteText([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), $utf8)
}

$here = $PSScriptRoot
Import-Module (Join-Path $here 'LifeorchConfig.psm1') -DisableNameChecking -Force -ErrorAction Stop
Import-Module (Join-Path $here 'LifeorchSetup.psm1') -DisableNameChecking -Force -ErrorAction Stop

$startedAt = [DateTime]::UtcNow
$result = [ordered]@{
    schema         = 'lifeorch.setup.result/0.1'
    action         = $Action
    ok             = $true
    started_at_utc = $startedAt.ToString('o')
    repo_root      = $null
    data_root      = $null
    prereq         = $null
    config         = $null
    generation     = $null
    verify         = $null
    warnings       = @()
    error          = $null
}
$warnings = New-Object System.Collections.Generic.List[string]
$hardFail = $false

try {
    # ---- resolve config first (roots) ----
    $resolveArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $resolveArgs['RepoRoot'] = $RepoRoot }
    if (-not [string]::IsNullOrWhiteSpace($DataRoot)) { $resolveArgs['DataRoot'] = $DataRoot }
    if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { $resolveArgs['MockNvidiaSmiText'] = $MockNvidiaSmiText }
    $cfg = Resolve-LifeorchConfig @resolveArgs
    $RepoRoot = [string]$cfg.repo_root
    $effDataRoot = if (-not [string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot } else { [string]$cfg.data_root }
    $result.repo_root = $RepoRoot
    $result.data_root = $effDataRoot
    Diag "repo_root=$RepoRoot data_root=$effDataRoot (repo via $($cfg.provenance.repo_root), data via $($cfg.provenance.data_root))"

    $doPrereq = ($Action -in @('prereq', 'all'))
    $doDetect = ($Action -eq 'detect') -or ($Action -eq 'all' -and $WriteConfig)
    $doGen = ($Action -in @('gen', 'all'))
    $doVerify = ($Action -in @('verify', 'all'))

    # ---- prereq ----
    if ($doPrereq) {
        $pr = Get-LifeorchPrereqReport
        $result.prereq = $pr
        Diag "prereq ok=$($pr.ok) pass=$($pr.summary.pass) fail=$($pr.summary.fail) unknown=$($pr.summary.unknown)"
        if (-not $pr.ok) { $hardFail = $true; foreach ($c in $pr.checks) { if ($c.status -eq 'fail') { $warnings.Add("prereq FAIL: $($c.name) -- $($c.detail)") } } }
    }

    # ---- detect / write config.json ----
    if ($doDetect) {
        $cfgOut = Join-Path $here 'config.json'
        $wcArgs = @{ OutPath = $cfgOut }
        if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $wcArgs['RepoRoot'] = $RepoRoot }
        if (-not [string]::IsNullOrWhiteSpace($effDataRoot)) { $wcArgs['DataRoot'] = $effDataRoot }
        if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { $wcArgs['MockNvidiaSmiText'] = $MockNvidiaSmiText }
        $wc = Write-LifeorchConfig @wcArgs
        $result.config = [pscustomobject]@{ path = $wc.path; valid = $wc.valid; errors = $wc.errors; written = $true }
        Diag "wrote config.json valid=$($wc.valid) -> $($wc.path)"
        if (-not $wc.valid) { $hardFail = $true; $warnings.Add('config.json failed schema validation: ' + ($wc.errors -join '; ')) }
    }

    # ---- gen models.machine.json + staging plan ----
    if ($doGen) {
        if ([string]::IsNullOrWhiteSpace($BaseModelsPath)) { $BaseModelsPath = Join-Path $RepoRoot 'modules/07-model-gateway/models.json' }
        if (-not (Test-Path -LiteralPath $BaseModelsPath -PathType Leaf)) { throw "base models.json not found: $BaseModelsPath" }
        $baseReg = (Get-Content -LiteralPath $BaseModelsPath -Raw) | ConvertFrom-Json

        # VRAM: override wins; else detected; else degrade with a clear error.
        $vram = $VramMiBOverride
        $gpu = if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { Get-LifeorchGpuInfo -MockText $MockNvidiaSmiText } else { Get-LifeorchGpuInfo }
        if ($vram -le 0 -and $gpu.present -and $null -ne $gpu.vram_total_mib) { $vram = [int]$gpu.vram_total_mib }
        if ($vram -le 0) { throw 'GPU VRAM not detected and no -VramMiBOverride given; cannot size models.json (pass -VramMiBOverride <MiB>).' }

        $genDataRoot = if (-not [string]::IsNullOrWhiteSpace($effDataRoot)) { $effDataRoot } else { 'F:\My_Programs\LifeOrchestrator-Refresh_Large_Data' }
        if ([string]::IsNullOrWhiteSpace($effDataRoot)) { $warnings.Add("data_root unresolved; generated paths use the default $genDataRoot -- set config.json/LIFEORCH_DATA_ROOT on the target box") }

        $machineReg = New-MachineModelsJson -BaseRegistry $baseReg -VramMiB $vram -DataRoot $genDataRoot -DisplayReserveMiB $DisplayReserveMiB -HostName ([string]$cfg.machine.hostname)
        $outModels = Join-Path $here 'out/models.machine.json'
        WriteText $outModels (($machineReg | ConvertTo-Json -Depth 40))

        $mv = Test-MachineModelsJson -Registry $outModels
        $plan = New-StagingPlan -Registry $machineReg -DataRoot $genDataRoot
        $outPlan = Join-Path $here 'out/staging-plan.txt'
        WriteText $outPlan $plan

        # CONFIRM the live registry was not touched (we only ever READ it; out goes to ops/setup/out/).
        $liveUntouched = $true; $liveNote = 'not applicable'
        $liveModels = Join-Path $RepoRoot 'modules/07-model-gateway/models.json'
        $baseResolved = (Resolve-Path -LiteralPath $BaseModelsPath -ErrorAction SilentlyContinue)
        $liveResolved = (Resolve-Path -LiteralPath $liveModels -ErrorAction SilentlyContinue)
        if ($null -ne $baseResolved -and $null -ne $liveResolved -and $baseResolved.Path -ieq $liveResolved.Path) {
            $liveNote = 'base==live models.json; opened READ-ONLY, out written only to ops/setup/out/'
        } else { $liveNote = "base ($BaseModelsPath) is distinct from the live models.json; live not opened for write" }

        $g = $machineReg._generated
        $result.generation = [pscustomobject]@{
            base_models_path      = $BaseModelsPath
            vram_mib              = $vram
            vram_source           = if ($VramMiBOverride -gt 0) { 'override' } elseif ($gpu.present) { 'nvidia-smi' } else { 'none' }
            gpu_name              = [string]$gpu.name
            data_root             = $genDataRoot
            old_data_root         = [string]$g.old_data_root
            strong_pick           = [string]$g.strong_pick
            display_reserve_mib   = $DisplayReserveMiB
            budget_mib            = $g.budget_mib
            models_machine_path   = $outModels
            models_machine_valid  = $mv.valid
            models_machine_errors = $mv.errors
            staging_plan_path     = $outPlan
            sizing                = $g.sizing
            live_models_untouched = $liveUntouched
            live_models_note      = $liveNote
        }
        Diag "gen: vram=$vram strong_pick=$($g.strong_pick) models.machine.json valid=$($mv.valid) -> $outModels"
        Diag "gen: staging plan -> $outPlan ; live models.json untouched ($liveNote)"
        if (-not $mv.valid) { $hardFail = $true; $warnings.Add('models.machine.json failed schema validation: ' + ($mv.errors -join '; ')) }
    }

    # ---- verify ----
    if ($doVerify) {
        $vArgs = @{ RepoRoot = $RepoRoot; Config = $cfg; MaxHeartbeatAgeSeconds = $MaxHeartbeatAgeSeconds }
        if ($SkipHeartbeat) { $vArgs['SkipHeartbeat'] = $true }
        $vr = Invoke-SetupVerify @vArgs
        $result.verify = $vr
        Diag "verify ok=$($vr.ok) pass=$($vr.summary.pass) fail=$($vr.summary.fail) warn=$($vr.summary.warn)"
        if (-not $vr.ok) { $hardFail = $true; foreach ($c in $vr.checks) { if ($c.status -eq 'fail') { $warnings.Add("verify FAIL: $($c.name) -- $($c.detail)") } } }
    }
}
catch {
    $hardFail = $true
    $result.error = [ordered]@{ message = "$($_.Exception.Message)"; line = $_.InvocationInfo.ScriptLineNumber }
    Diag "ERROR line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
}

$result.ok = (-not $hardFail)
$result.warnings = $warnings.ToArray()
$result.finished_at_utc = ([DateTime]::UtcNow.ToString('o'))
[Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 40))
if ($hardFail) { exit 1 } else { exit 0 }
