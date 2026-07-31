#requires -Version 7.0
<#
.SYNOPSIS
  model.gateway — a common interface to run local models (Life Orchestrator, contract v0.1).
.DESCRIPTION
  MVP: runs local LLMs (GGUF text models) through the built llama.cpp `llama-server` (start -> wait for
  /health -> POST /v1/chat/completions -> stop the server). The model is chosen from a declarative
  registry (models.json) by an explicit -Model id or a -Tier alias (weak|strong); the registry declares
  every discovered local model (LLM/STT/TTS/embedding), but only wired LLMs execute in this MVP — a
  non-wired or non-LLM model returns a structured `model_not_wired` error.

  Governor Phase 2 -- WARM/persistent server (opt-in via -Warm): the llama-server is kept RESIDENT across
  separate gateway invocations (recorded in runtime/warm-server.json). A later -Warm call REUSES the resident
  server when the model (+ ngl/ctx) is unchanged (no reload -> health_ms ~0), and EVICTS+reloads it on a model
  change. The gpu lease stays PER-CALL (acquired/released each invocation, NOT held across the resident life);
  because every GPU user takes the lease first and then reuses-or-evicts the single resident, at most one
  llama-server is ever on the GPU. Default is OFF -> the classic per-call spawn/kill is byte-for-byte unchanged.
  -EvictWarm tears down the resident server and returns (no generation) for clean teardown / no orphans.

  Governor Phase 3 Stage-1 -- named warm POOL MANAGER (mechanism C, D-0063). The shipped D-0057 warm server is
  extended into a NAMED POOL MANAGER that keeps ONE model GPU-active and fast-swaps to a named model on demand.
  Reuse is decided by an EXPANDED RESIDENCY KEY (not just the model filename): model_id + model_sha256 +
  model_size + engine build/path + gpu_layers + context + no_think + cache_type_k + cache_type_v + flash_attn +
  parallel(-np) + chat_template(+args) + mmproj_sha256 + generation_id. An EXACT key match reuses the resident
  (~1 ms, no reload) and refreshes its keep-resident timer; any change (e.g. KV type / context / no_think) is a
  REAL swap: the resident is terminated (process-exit + VRAM-recovery CONFIRMED), the requested model is loaded
  via its registry engine, /health + model provenance are confirmed, and a new residency manifest is published.
  -EnsureResident performs this residency check/change and RETURNS without generating (the governor's
  Ensure-ResidentModel(model_id, config_key)); -PoolStatus reports the resident + idle age read-only; -SweepIdle
  evicts a resident idle beyond -KeepResidentSeconds (default 90 s). The gpu lease is HELD across the whole
  check/change; a caller that pre-holds the lease (stable holder, whole-task) is honored and never released here
  (owned = not already_held), so at most one llama-server is ever GPU-resident even across separate calls. Same-
  model PREFIX REUSE is in-scope (normal prompt caching, -np 1, explicit id_slot, clear at session boundary);
  persistent --slot-save-path across eviction, the native --models router, and any coding specialist are Stage-2+
  and are NOT built here. Default OFF -> the classic per-call spawn/kill and the D-0057 warm path are unchanged.

  Governor Phase 3 Stage-2 -- OPT-IN per-token logprobs (-Logprobs / {"logprobs":true}): the chat request adds
  OpenAI-style logprobs+top_logprobs and the result surfaces result.generation.logprobs {available, top_k,
  token_count, first_token_entropy, mean_entropy, decision_token_entropy} (top-k-approximate Shannon entropy in
  nats). Default OFF -> the request body + the result are byte-for-byte unchanged. The STEP-1 live probe
  confirmed clean logprobs on BOTH engine builds (b8661 + b10092); consumed by agent.local -AutoRamp
  -LogprobConfidence as one more soft-strike signal.

  This is the first stochastic/mixed skill: it populates `model_provenance[]` (id/version/params/tokens/
  timings/finish_reason/runtime) and `confidence` (a documented generation-completeness heuristic, NOT a
  semantic-correctness score). Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to
  stderr; writes output.txt + exchange.json + result.json + stderr.txt. Exits 0 whenever a valid envelope
  is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Tier weak -Prompt "Reply with exactly one word: PONG" -MaxTokens 16
  pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Model llm.weak.qwen2p5-1p5b -System "You are terse." -Prompt "Name three primary colors." -MaxTokens 64
#>
[CmdletBinding()]
param(
    [string]$Model,
    [string]$Tier,
    [string]$Prompt,
    [string]$System,
    [int]$MaxTokens = 256,
    [double]$Temperature = 0.7,
    [double]$TopP = 0.95,
    [int]$TopK = 40,
    [int]$Seed = -1,
    [string[]]$Stop,
    [string]$Registry,
    [int]$Port = 0,
    [int]$GpuLayers = -1,
    [int]$Context = 0,
    [int]$LoadTimeoutSec = 120,
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId,
    # --- GPU lease wiring (res.lease #29) ---
    [string]$GpuLease = 'auto',          # off | auto | wait | require
    [int]$GpuLeaseWaitSeconds = 900,     # wait budget for -GpuLease wait|require (auto forces 0)
    [int]$GpuLeaseTtlSeconds = 1800,     # lease TTL; renewed only if a run outlives it
    [string]$GpuLeaseHolder,             # stable holder id; default $env:LIFEORCH_INSTANCE else model.gateway:<pid>
    [string]$LeaseDir,                   # shared lease dir passthrough (default: res.lease resolves it)
    [string]$ResLeasePath,               # override path to Invoke-ResLease.ps1 (default: auto-resolve)
    [string]$PwshPath,                   # pwsh used to spawn res.lease (default: resolve via PATH)
    # --- Governor Phase 2: warm/persistent llama-server ---
    [switch]$Warm,                       # keep the llama-server resident across calls; reuse when model unchanged
    [switch]$EvictWarm,                  # tear down the resident warm server and return (no generation)
    [string]$WarmRegistryPath,           # override the resident-server registry (default: runtime/warm-server.json)
    # --- Governor Phase 3 Stage-2: opt-in per-token logprobs (OFF by default -> request/response byte-identical) ---
    [switch]$Logprobs,                   # request OpenAI-style logprobs/top_logprobs and return decision-token entropy
    [int]$TopLogprobs = 5,               # top-k candidates per token (llama-server clamps to its own cap)
    # --- Governor Phase 3 Stage-1: named warm POOL MANAGER (mechanism C, D-0063). All OFF by default -> byte-identical. ---
    [switch]$EnsureResident,             # pool op: make the requested model resident under the EXPANDED residency key, then RETURN (no generation)
    [switch]$PoolStatus,                 # read-only: report the current resident manifest + idle age + liveness/health (no lease, no change)
    [switch]$SweepIdle,                  # evict the resident IFF it is idle beyond the keep-resident window (a contender/other module reclaims the GPU)
    [string]$CacheTypeK = 'f16',         # KV key-cache type (residency-key field; f16 default per D-0063 -- q8_0 only after the S0 re-pass)
    [string]$CacheTypeV = 'f16',         # KV value-cache type (residency-key field)
    [switch]$FlashAttn,                  # enable flash-attention (residency-key field; OFF by default)
    [int]$Parallel = 1,                  # llama-server slot count (-np); Stage-1 pins 1 for deterministic same-model prefix reuse
    [int]$IdSlot = 0,                    # explicit slot id for prefix reuse (Stage-1: -np 1 + a single fixed slot)
    [switch]$ClearSlot,                  # session-boundary: erase the prefix-cache slot before generating (best-effort POST /slots/<id>?action=erase)
    [int]$KeepResidentSeconds = 90,      # idle keep-resident window; SweepIdle evicts a resident idle beyond this (refresh on same-model reuse)
    [int]$Generation = -1,               # DEPRECATED (finding 6): kept for back-compat; if >=0 it now forces a reload (does NOT poison the config hash)
    # --- Governor Phase 3 Stage-1.1 HARDENING (WARM_POOL_DESIGN section 10, D-0067). All OFF/neutral by default. ---
    [switch]$ForceReload,                # integrity-neutral: force an evict+reload even when the resident CanServe the request
    [string]$ExpectGeneration,           # finding 1: reject an inference call unless the resident's instance_generation matches (no wrong-generation call lands)
    [int]$ExpectFence = -1,              # finding 1: reject an inference call unless the resident's fence matches (-1 = do not check)
    [int]$FenceTtlSeconds = 120,         # finding 1: short renewable fence TTL (~90-120 s), NOT 1800 s; renewed within a whole-task hold
    [switch]$PrepareGpu,                 # finding 2: AcquirePreparedGpu -- evict-before-grant so releasing does not leave the GPU blocked for another consumer
    [int]$RequiredVramMib = 0,           # finding 2: VRAM another consumer needs; PrepareGpu evicts the resident if headroom is short
    [int]$VramSafetyMib = 512,           # finding 15: target-headroom margin over RequiredVramMib
    [int]$VramConfirmTimeoutMs = 5000,   # finding 15: WDDM frees async -- confirm recovery over this interval, not a single sample
    [switch]$Reconcile,                  # finding 3: run crash-recovery reconcile (also runs implicitly on every pool op) and RETURN
    # --- DURABLE gateway supervisor (WARM_POOL_DESIGN section 10 residual (a); durable finding 5). Default-OFF, additive. ---
    [switch]$UseSupervisor,              # route residency ops (EnsureResident/PoolStatus/PrepareGpu/EvictWarm/Reconcile) to a RUNNING persistent supervisor so the resident + its Job-Object tree ownership survive across per-call invocations; degrade to the per-call path (with a warning) if no supervisor is live. Inference is NOT routed -- it reuses the supervisor-published resident via the classic warm path (same warm-server.json).
    [string]$SupervisorRoot,             # supervisor control-dir root (default: runtime/supervisor); must match Start-GatewaySupervisor.ps1
    [switch]$BypassPoolManager,          # framing: legacy escape -- force the classic cold isolated-server path even under -Warm (integrity invariants stay non-bypassable)
    # --- R1b CONSUMER wave (i21): GPU-lease-split adoption of res.lease 0.4.0. ALL DEFAULT-OFF; with the flag
    #     off every path above is byte-for-byte unchanged. When ON (-Warm/-EnsureResident pool paths only):
    #     a revocable residency_pin is held BETWEEN calls (priority = the task's tier); a same-model reuse takes
    #     a plain short exec re-attach (~1 ms-class residency decision); a swap/eviction goes through the v0.4
    #     TWO-PHASE transition (-Transition -TwoPhaseCommit -> capability -> start -> '-Action commit -HealthOk')
    #     with the REAL evictor lib/PoolEvictor.ps1 (-EvictorMode command, supervisor-routed, fence-op-gated);
    #     every inference asserts the FULL v0.4 tuple (owner_id + owner_incarnation_id + gpu_authority_epoch +
    #     resident_generation + resident_instance_id + exec_lease_id) via res.lease '-Action check' and a late
    #     stale result is DISCARDED. ---
    [switch]$UsePoolLeaseSplit,          # engage the split (default-OFF; OFF == today's D-0057 warm + Stage-1.1 pool byte-for-byte)
    [int]$SplitPriority = 0,             # residency-pin priority (0 = derive from the tier: tiny 10 / weak 20 / mid 30 / strong 40)
    [string]$OwnerIncarnationId,         # v0.4 ABA identity minted per owning-process RESTART (default: $env:LIFEORCH_OWNER_INCARNATION else minted per invocation)
    [int]$SplitRequiredVramMib = 0,      # transition required_vram_mib = the measured PEAK for the config (0 = derive: size_mib + max(512, 10%))
    [int]$SplitExecTtlSeconds = 120,     # TTL of the short exec/transition lease
    [int]$SplitPinTtlSeconds = 600,      # TTL of the between-calls residency pin (renewed by re-attach on each call)
    [int]$SplitDrainTimeoutMs = 2000     # bounded drain of an ACTIVE inference before cancel -> supervisor tree-kill
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Stage-1.1 integrity core (fencing / state machine / CanServe / config-hash split / handoff planner).
# Pure + unit-tested off-machine (tests/Invoke-ModelGatewayPoolCoreTests.ps1). Import is fail-open: if the
# module is missing the classic + D-0057 warm paths still run (the pool simply cannot be enabled).
$script:PoolCoreLoaded = $false
try { Import-Module (Join-Path $PSScriptRoot 'lib/PoolManager.psm1') -Force -ErrorAction Stop; $script:PoolCoreLoaded = $true } catch { }

$SKILL_ID = 'model.gateway'; $SKILL_VERSION = '0.5.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$CONF_THRESHOLD = 0.5
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[model.gateway] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
# Shannon entropy (nats) over one token's top-k candidates. Each carries .logprob (p=exp) or .prob (already p).
# Normalized over the returned top-k, so it is a top-k-approximate entropy (documented; the tail is unobserved).
function Get-TokenEntropy($topArr) {
    if ($null -eq $topArr) { return $null }
    $arr = @($topArr); if ($arr.Count -eq 0) { return $null }
    $ps = New-Object System.Collections.Generic.List[double]
    foreach ($t in $arr) { if (Has $t 'logprob') { $ps.Add([math]::Exp([double]$t.logprob)) } elseif (Has $t 'prob') { $ps.Add([double]$t.prob) } }
    if ($ps.Count -eq 0) { return $null }
    $sum = 0.0; foreach ($x in $ps) { $sum += $x }
    if ($sum -le 0) { return $null }
    $h = 0.0; foreach ($x in $ps) { $q = $x / $sum; if ($q -gt 0) { $h += (-1.0 * $q * [math]::Log($q)) } }
    return [math]::Round($h, 4)
}
function Get-FreePort([int]$start) {
    for ($p = $start; $p -lt ($start + 300); $p++) {
        try { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p); $l.Start(); $l.Stop(); return $p } catch { }
    }
    return 0
}
function Resolve-RepoRoot([string]$start) {
    try {
        $d = Get-Item -LiteralPath $start
        for ($i = 0; $i -lt 8 -and $null -ne $d; $i++) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'core-docs')) { return $d.FullName }
            $d = $d.Parent
        }
    } catch { }
    return $null
}
# ---- res.lease (#29) integration: resolve pwsh + the lease script, and shell out to it ----
function Get-PwshExe {
    if (-not [string]::IsNullOrWhiteSpace($PwshPath)) { return $PwshPath }
    if (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_PWSH)) { return $env:LIFEORCH_PWSH }
    try { $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c -and $c.Source) { return $c.Source } } catch { }
    try { $mm = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName; if ($mm -match '(?i)pwsh') { return $mm } } catch { }
    return 'pwsh'
}
function Resolve-ResLeasePath {
    if (-not [string]::IsNullOrWhiteSpace($ResLeasePath)) {
        if (Test-Path -LiteralPath $ResLeasePath -PathType Leaf) { return (Resolve-Path -LiteralPath $ResLeasePath).Path }
        return $null
    }
    $root = Resolve-RepoRoot $PSScriptRoot
    if ($null -ne $root) {
        $cand = Join-Path $root 'modules/29-resource-lease/Invoke-ResLease.ps1'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { return (Resolve-Path -LiteralPath $cand).Path }
    }
    $sib = Join-Path (Split-Path -Parent $PSScriptRoot) '29-resource-lease/Invoke-ResLease.ps1'
    if (Test-Path -LiteralPath $sib -PathType Leaf) { return (Resolve-Path -LiteralPath $sib).Path }
    return $null
}
# Run one res.lease action as a SEPARATE pwsh process (its `exit 0` must not terminate this script) and
# return the parsed .result object, or $null on any failure (caller treats $null as "lease unavailable").
function Invoke-GpuLeaseAction {
    param(
        [string]$LeaseAction, [string]$Resource, [string]$Holder,
        [int]$Ttl = 1800, [double]$Wait = 0, [string]$LeaseIdArg, [string]$LeaseDirArg,
        [string]$RlPath, [string]$PwshExe
    )
    if ([string]::IsNullOrWhiteSpace($RlPath) -or [string]::IsNullOrWhiteSpace($PwshExe)) { return $null }
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $RlPath,
           '-Action', $LeaseAction, '-Resource', $Resource, '-Holder', $Holder)
    if ($LeaseAction -eq 'acquire') { $a += @('-TtlSeconds', "$Ttl", '-WaitSeconds', "$Wait") }
    if (-not [string]::IsNullOrWhiteSpace($LeaseIdArg))  { $a += @('-LeaseId', $LeaseIdArg) }
    if (-not [string]::IsNullOrWhiteSpace($LeaseDirArg)) { $a += @('-LeaseDir', $LeaseDirArg) }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $PwshExe @a 2>$null
        $txt = ([string]($out | Out-String)).Trim()
        if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
        $envObj = $txt | ConvertFrom-Json
        if ($null -ne $envObj -and (Has $envObj 'result') -and $null -ne $envObj.result) { return $envObj.result }
        return $null
    } catch {
        Write-Diag "res.lease $LeaseAction invocation error: $($_.Exception.Message)"
        return $null
    } finally { $ErrorActionPreference = $prev }
}
# i21 split: run ONE res.lease action with the FULL v0.3/v0.4 surface via -InputsJson (a separate pwsh process;
# its `exit 0` must not terminate this script). Returns the parsed .result object, or $null on any failure.
function Invoke-ResLeaseJson {
    param([Parameter(Mandatory)][hashtable]$LeaseInputs, [string]$RlPath, [string]$PwshExe)
    if ([string]::IsNullOrWhiteSpace($RlPath) -or [string]::IsNullOrWhiteSpace($PwshExe)) { return $null }
    if (-not [string]::IsNullOrWhiteSpace($LeaseDir) -and -not $LeaseInputs.ContainsKey('lease_dir')) { $LeaseInputs['lease_dir'] = $LeaseDir }
    $json = ($LeaseInputs | ConvertTo-Json -Compress -Depth 6)
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $RlPath, '-InputsJson', $json)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $PwshExe @a 2>$null
        $txt = ([string]($out | Out-String)).Trim()
        if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
        $envObj = $txt | ConvertFrom-Json
        if ($null -ne $envObj -and (Has $envObj 'result') -and $null -ne $envObj.result) { return $envObj.result }
        return $null
    } catch {
        Write-Diag "res.lease json action '$($LeaseInputs['action'])' invocation error: $($_.Exception.Message)"
        return $null
    } finally { $ErrorActionPreference = $prev }
}
# i21 split: residency-pin priority = the task's tier (explicit -SplitPriority wins).
function Get-SplitTierPriority {
    param([string]$TierName, [string]$ModelId, $Reg)
    if ($SplitPriority -gt 0) { return $SplitPriority }
    $t = $TierName
    if ([string]::IsNullOrWhiteSpace($t) -and $null -ne $Reg -and (Has $Reg 'tiers') -and (Has $Reg.tiers 'llm')) {
        foreach ($tp in $Reg.tiers.llm.PSObject.Properties) { if ([string]$tp.Value -eq $ModelId) { $t = [string]$tp.Name; break } }
    }
    switch (("$t").ToLowerInvariant()) {
        'tiny'   { return 10 }
        'weak'   { return 20 }
        'mid'    { return 30 }
        'strong' { return 40 }
        default  { return 20 }
    }
}

# ---- warm/persistent server (Governor Phase 2): a single cross-invocation resident llama-server ----
# The registry (runtime/warm-server.json) records the one resident server so a LATER, separate gateway
# invocation can reuse it (same model) or evict+reload it (model change). The gpu lease stays PER-CALL;
# a resident server holds VRAM between calls, and any GPU user acquires the gpu lease first and then
# reuses-or-evicts the single resident -> at most one llama-server is ever on the GPU (no orphans).
function Get-WarmRegistryPath {
    param([string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override }
    return (Join-Path $PSScriptRoot 'runtime/warm-server.json')
}
function Read-WarmServer {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
function Write-WarmServer {
    param([string]$Path, $Obj)
    try {
        $dir = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Path.tmp-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        [System.IO.File]::WriteAllText($tmp, ($Obj | ConvertTo-Json -Depth 8), $utf8)
        [System.IO.File]::Move($tmp, $Path, $true)
        return $true
    } catch { return $false }
}
function Clear-WarmServer {
    param([string]$Path)
    try { if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue } } catch { }
}
# Liveness + identity of a recorded resident: PID alive AND (start-ticks match when readable).
function Get-WarmServerLiveness {
    param($Reg)
    $res = [ordered]@{ alive = $false; identity_ok = $false }
    if ($null -eq $Reg -or -not (Has $Reg 'pid')) { return $res }
    $procId = [int]$Reg.pid
    $proc = $null
    try { $proc = Get-Process -Id $procId -ErrorAction Stop } catch { return $res }
    $res.alive = $true
    try {
        $wantTicks = if (Has $Reg 'start_ticks') { [long]$Reg.start_ticks } else { 0 }
        if ($wantTicks -gt 0) {
            # Tolerance (2s): Process.StartTime is imprecise on Linux (~ms jitter between the launch handle and
            # a later Get-Process read); a REUSED pid would differ by seconds+, so this still rejects impostors.
            $res.identity_ok = ([Math]::Abs($proc.StartTime.Ticks - $wantTicks) -lt [TimeSpan]::FromSeconds(2).Ticks)
        }
        else { $res.identity_ok = $true }
    } catch { $res.identity_ok = $false }   # StartTime unreadable -> cannot claim identity
    return $res
}
function Test-ServerHealthy {
    param([string]$ServerHost, [int]$ServerPort, [int]$TimeoutSec = 2)
    if ($ServerPort -le 0) { return $false }
    try { $h = Invoke-WebRequest -Uri "http://$($ServerHost):$ServerPort/health" -UseBasicParsing -TimeoutSec $TimeoutSec; return ($h.StatusCode -eq 200) } catch { return $false }
}
# Kill a resident server ONLY when it is positively identified (never kill a foreign/reused PID).
function Stop-ResidentServer {
    param($Reg, $Liveness)
    if ($null -eq $Reg -or -not (Has $Reg 'pid')) { return $true }
    if (-not $Liveness.alive) { return $true }         # already gone
    if (-not $Liveness.identity_ok) { return $false }  # alive but unidentified -> refuse to kill
    $procId = [int]$Reg.pid
    try { & taskkill /PID $procId /T /F 2>$null | Out-Null } catch { }
    try { $pp = Get-Process -Id $procId -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
    # CONFIRM the process is gone before returning: Process.Kill can return before the OS reaps the pid
    # (esp. on Linux), and Stop-Process -Force is a sturdier fallback. Bounded to ~3s.
    for ($i = 0; $i -lt 30; $i++) {
        $still = $null; try { $still = Get-Process -Id $procId -ErrorAction SilentlyContinue } catch { $still = $null }
        if ($null -eq $still) { return $true }
        try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch { }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

# ---- Governor Phase 3 Stage-1: named POOL MANAGER (mechanism C, D-0063) helpers ----
# The EXPANDED residency key -- reuse ONLY on an exact match of every field that changes what is GPU-resident.
# A matching filename is INSUFFICIENT: a KV-type / context / no_think / engine / generation change is a REAL swap.
function Get-ResidencyKey {
    param($M, $Reg, [int]$Ngl, [int]$Ctx, [bool]$NoThink, [string]$Ctk, [string]$Ctv, [bool]$Flash, [int]$Np, [int]$Gen)
    $p = if (Has $M 'params') { $M.params } else { $null }
    $sha   = if ($null -ne $p -and (Has $p 'sha256'))        { [string]$p.sha256 }        else { $null }
    $sz    = if ($null -ne $p -and (Has $p 'size_bytes'))    { [long]$p.size_bytes }       else { $null }
    $mmsha = if ($null -ne $p -and (Has $p 'mmproj_sha256')) { [string]$p.mmproj_sha256 } else { $null }
    $ep = if (Has $M 'engine_path') { [string]$M.engine_path } elseif ((Has $Reg 'engines') -and (Has $Reg.engines 'llama-server')) { [string]$Reg.engines.'llama-server' } else { $null }
    $eb = if (Has $Reg 'engine_build') { [string]$Reg.engine_build } else { $null }
    $tmpl = if (Has $M 'chat_template') { [string]$M.chat_template } else { $null }
    $tmplArgs = if (Has $M 'chat_template_args') { [string]($M.chat_template_args | ConvertTo-Json -Depth 6 -Compress) } else { $null }
    $genId = if ($Gen -ge 0) { $Gen } elseif (Has $M 'generation_id') { [int]$M.generation_id } elseif (Has $Reg 'generation_id') { [int]$Reg.generation_id } else { 0 }
    return [ordered]@{
        model_id = [string]$M.model_id; model_sha256 = $sha; model_size_bytes = $sz
        engine_build = $eb; engine_path = $ep
        gpu_layers = $Ngl; context = $Ctx; no_think = $NoThink
        cache_type_k = $Ctk; cache_type_v = $Ctv; flash_attn = $Flash; parallel = $Np
        chat_template = $tmpl; chat_template_args = $tmplArgs; mmproj_sha256 = $mmsha
        generation_id = $genId
    }
}
function Get-ResidencyKeySha { param($Key) return (Get-Sha256Hex $utf8.GetBytes(($Key | ConvertTo-Json -Depth 8 -Compress))) }
# Best-effort GPU free VRAM (MiB); $null when nvidia-smi is absent (off-machine / mock) -> non-fatal.
# i23 MF7: prefer the PINNED-ABSOLUTE + HARD-DEADLINE probe (Get-GpuFreeMibBounded, PoolManager) so a hung
# nvidia-smi cannot stall a residency op; degrade to the legacy PATH lookup only if the helper is unavailable.
function Get-GpuFreeMib {
    try {
        if (Get-Command Get-GpuFreeMibBounded -ErrorAction SilentlyContinue) { return (Get-GpuFreeMibBounded -DeadlineMs 4000) }
        $smi = Get-Command nvidia-smi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $smi) { return $null }
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $o = & $smi.Source '--query-gpu=memory.free' '--format=csv,noheader,nounits' 2>$null } finally { $ErrorActionPreference = $prev }
        $line = (@($o) | Where-Object { "$_".Trim() -ne '' } | Select-Object -First 1)
        if ($null -eq $line) { return $null }
        $n = 0; if ([int]::TryParse((("$line").Trim()), [ref]$n)) { return $n }
        return $null
    } catch { return $null }
}
# Confirm the resident server actually loaded a model (GET /v1/models, fallback /props). Soft: /health is the hard gate.
function Confirm-ResidentProvenance {
    param([string]$ServerHost, [int]$ServerPort, [int]$TimeoutSec = 5)
    $res = [ordered]@{ ok = $false; reported = @(); source = $null }
    if ($ServerPort -le 0) { return $res }
    try {
        $r = Invoke-RestMethod -Uri "http://$($ServerHost):$ServerPort/v1/models" -TimeoutSec $TimeoutSec -Method Get
        if ($null -ne $r -and (Has $r 'data')) {
            $ids = @(@($r.data) | ForEach-Object { if (Has $_ 'id') { [string]$_.id } } | Where-Object { $_ })
            $res.reported = $ids; $res.source = '/v1/models'; $res.ok = ($ids.Count -gt 0)
        }
    } catch {
        try {
            $pr = Invoke-RestMethod -Uri "http://$($ServerHost):$ServerPort/props" -TimeoutSec $TimeoutSec -Method Get
            if ($null -ne $pr) { $res.source = '/props'; $res.ok = $true; if (Has $pr 'model_path') { $res.reported = @([string]$pr.model_path) } }
        } catch { }
    }
    return $res
}
# Idle age (ms) of a resident manifest from last_used_utc (else started_at_utc); $null if unknown.
function Get-ResidentIdleMs {
    param($Reg)
    if ($null -eq $Reg) { return $null }
    $stamp = if (Has $Reg 'last_used_utc') { [string]$Reg.last_used_utc } elseif (Has $Reg 'started_at_utc') { [string]$Reg.started_at_utc } else { $null }
    if ([string]::IsNullOrWhiteSpace($stamp)) { return $null }
    try { $t = [DateTime]::Parse($stamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind); return [int]([DateTime]::UtcNow - $t).TotalMilliseconds } catch { return $null }
}

# ---- Stage-1.1 live seams (wire the pure PoolManager core to real Windows/GPU probes; degrade off-box) ----
# #6: engine exe CONTENT hash (identity, not the path). Cached by path+size+mtime so warm reuse never re-hashes.
function Get-EngineExeHashCached {
    param([string]$EnginePath)
    if ([string]::IsNullOrWhiteSpace($EnginePath) -or -not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) { return $null }
    try {
        $fi = Get-Item -LiteralPath $EnginePath
        $cacheDir = Join-Path $PSScriptRoot 'runtime'
        $cachePath = Join-Path $cacheDir 'engine-hash-cache.json'
        $key = "$($fi.FullName)|$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
        $cache = $null
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) { try { $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json } catch { $cache = $null } }
        if ($null -ne $cache -and (Has $cache $key)) { return [string]$cache.$key }
        $bytes = [System.IO.File]::ReadAllBytes($fi.FullName)
        $h = Get-Sha256Hex $bytes
        try {
            if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            $obj = [ordered]@{}; if ($null -ne $cache) { foreach ($pp in $cache.PSObject.Properties) { $obj[$pp.Name] = $pp.Value } }
            $obj[$key] = $h
            $tmp = "$cachePath.tmp-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            [System.IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 4), $utf8); [System.IO.File]::Move($tmp, $cachePath, $true)
        } catch { }
        return $h
    } catch { return $null }
}
# #4: cross-platform listening-socket owner pid. Windows: Get-NetTCPConnection. Linux: lsof/ss. $null = undeterminable.
$script:SocketOwnerProbe = {
    param([int]$SockPort)
    if ($SockPort -le 0) { return $null }
    try {
        $gc = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
        if ($null -ne $gc) {
            $c = Get-NetTCPConnection -LocalPort $SockPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $c) { return [int]$c.OwningProcess }
            return $null
        }
    } catch { }
    # Linux fallbacks (off-machine gate): lsof, then ss
    foreach ($tool in @('lsof','ss')) {
        try {
            $cmd = Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $cmd) { continue }
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try {
                if ($tool -eq 'lsof') {
                    $o = & $cmd.Source "-iTCP:$SockPort" '-sTCP:LISTEN' '-t' '-P' '-n' 2>$null
                    $line = (@($o) | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -First 1)
                    if ($null -ne $line) { return [int]("$line".Trim()) }
                } else {
                    $o = & $cmd.Source '-ltnpH' 2>$null
                    foreach ($ln in @($o)) { if ("$ln" -match ":$SockPort\s" -and "$ln" -match 'pid=(\d+)') { return [int]$Matches[1] } }
                }
            } finally { $ErrorActionPreference = $prev }
        } catch { }
    }
    return $null
}
$script:StartTicksProbe = { param([int]$ProcId) try { return [long]((Get-Process -Id $ProcId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 } }

# #3: crash-recovery reconcile. Runs under the machine-global pool lock. Reads the manifest as a CLAIM,
# VERIFIES it (pid alive + creation-time identity + /health + socket owner), and drives an inconsistent
# claim to a clean EMPTY. A healthy, verified resident is KEPT untouched (warmth preserved).
function Invoke-PoolReconcile {
    param([string]$WarmRegPath, [string]$LockPath)
    $out = [ordered]@{ ran = $false; state_before = $null; state_after = $null; action = 'none'; kept_resident = $false; killed_pid = $null; notes = @() }
    if (-not $script:PoolCoreLoaded) { return $out }
    $lock = Enter-PoolLock -LockPath $LockPath -TimeoutMs 8000
    try {
        $reg = Read-PoolManifest $WarmRegPath
        $out.ran = $true
        if ($null -eq $reg) { $out.state_after = 'EMPTY'; $out.action = 'no_manifest'; return $out }
        $out.state_before = Get-ManifestState $reg
        $ident = Test-ResidentIdentity $reg $script:StartTicksProbe
        $port = if (Has $reg 'port') { [int]$reg.port } else { 0 }
        $healthy = $ident.alive -and (Test-ServerHealthy '127.0.0.1' $port)
        $sockOwner = $null
        if ($ident.alive -and (Has $reg 'pid')) { $sockOwner = Test-SocketOwner -Port $port -ExpectedPid ([int]$reg.pid) -SocketOwnerProbe $script:SocketOwnerProbe }
        $stateBefore = $out.state_before
        $validResident = ($stateBefore -eq 'RESIDENT' -and $ident.alive -and $ident.identity_ok -and $healthy -and ($sockOwner -ne $false))
        if ($validResident) {
            $out.state_after = 'RESIDENT'; $out.action = 'kept_valid_resident'; $out.kept_resident = $true; return $out
        }
        # inconsistent claim (crash mid-transition, dead pid, unhealthy, wrong socket owner) -> confirm-stop -> EMPTY
        if ($ident.alive -and $ident.identity_ok) {
            $ls = [ordered]@{ alive = $ident.alive; identity_ok = $ident.identity_ok }
            if (Stop-ResidentServer $reg $ls) { $out.killed_pid = [int]$reg.pid; $out.notes += 'stopped stale/identified resident' }
            else { $out.notes += 'resident alive but unidentified; not killed' }
        } elseif ($ident.alive -and -not $ident.identity_ok) {
            $out.notes += 'recorded pid alive but identity mismatch (PID reuse); manifest cleared without killing a foreign process'
        }
        Clear-PoolManifest $WarmRegPath
        $out.state_after = 'EMPTY'; $out.action = "reconciled_from_$stateBefore"
        return $out
    } finally { Exit-PoolLock $lock }
}

# ---- DURABLE SUPERVISOR client (residual (a)): a per-call gateway ATTACHES to a running persistent supervisor
# over the file-protocol control channel and asks it to run the residency op, so the resident llama-server +
# its Job-Object tree ownership persist ACROSS separate invocations. Lazy Supervisor.psm1 import (only under
# -UseSupervisor). Returns the Send-SupervisorRequest result ({ ok; response; error }); ok=$false -> the caller
# degrades to the per-call path. ----
function Invoke-SupervisorClient {
    param([string]$Op, [hashtable]$Params, [string]$SupRoot, [string]$WarmReg, [string]$ExpectGen, [int]$ExpectFenceArg = -1, [int]$TimeoutMs = 60000)
    $modPath = Join-Path $PSScriptRoot 'lib/Supervisor.psm1'
    if (-not (Test-Path -LiteralPath $modPath -PathType Leaf)) { return [ordered]@{ ok = $false; error = [ordered]@{ code = 'supervisor_module_missing'; message = 'lib/Supervisor.psm1 not found' } } }
    try { Import-Module $modPath -ErrorAction Stop } catch { return [ordered]@{ ok = $false; error = [ordered]@{ code = 'supervisor_import_failed'; message = "$($_.Exception.Message)" } } }
    $root = if (-not [string]::IsNullOrWhiteSpace($SupRoot)) { $SupRoot } else { Join-Path $PSScriptRoot 'runtime/supervisor' }
    $paths = Get-SupervisorPaths -Root $root -WarmRegistryPath $WarmReg
    return (Send-SupervisorRequest -Paths $paths -Op $Op -Params $Params -ExpectGeneration $ExpectGen -ExpectFence $ExpectFenceArg -TimeoutMs $TimeoutMs)
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @()
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$outputText = $null; $exchange = $null

# roadmap module that will wire each non-LLM type (for a helpful model_not_wired message)
$wireModuleByType = @{ stt = 'Module 11 (speech.stt)'; tts = 'Module 12 (speech.tts)'; embedding = 'Module 23 (artifact.search)'; vision = 'Module 17 (image.interpret)' }

try {
    # ---- merge -InputsJson (named params win where explicitly set) ----
    $messages = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if (Has $p 'model')          { $Model = [string]$p.model }
            if (Has $p 'tier')           { $Tier = [string]$p.tier }
            if (Has $p 'prompt')         { $Prompt = [string]$p.prompt }
            if (Has $p 'system')         { $System = [string]$p.system }
            if (Has $p 'messages')       { $messages = $p.messages }
            if (Has $p 'max_tokens')     { $MaxTokens = [int]$p.max_tokens }
            if (Has $p 'temperature')    { $Temperature = [double]$p.temperature }
            if (Has $p 'top_p')          { $TopP = [double]$p.top_p }
            if (Has $p 'top_k')          { $TopK = [int]$p.top_k }
            if (Has $p 'seed')           { $Seed = [int]$p.seed }
            if (Has $p 'stop')           { $Stop = @($p.stop) }
            if (Has $p 'registry')       { $Registry = [string]$p.registry }
            if (Has $p 'port')           { $Port = [int]$p.port }
            if (Has $p 'gpu_layers')     { $GpuLayers = [int]$p.gpu_layers }
            if (Has $p 'context')        { $Context = [int]$p.context }
            if (Has $p 'load_timeout_s') { $LoadTimeoutSec = [int]$p.load_timeout_s }
            if (Has $p 'review_queue_path') { $ReviewQueuePath = [string]$p.review_queue_path }
            if (Has $p 'gpu_lease')        { $GpuLease = [string]$p.gpu_lease }
            if (Has $p 'gpu_lease_wait_s')  { $GpuLeaseWaitSeconds = [int]$p.gpu_lease_wait_s }
            if (Has $p 'gpu_lease_ttl_s')   { $GpuLeaseTtlSeconds = [int]$p.gpu_lease_ttl_s }
            if (Has $p 'gpu_lease_holder')  { $GpuLeaseHolder = [string]$p.gpu_lease_holder }
            if (Has $p 'lease_dir')        { $LeaseDir = [string]$p.lease_dir }
            if (Has $p 'res_lease_path')    { $ResLeasePath = [string]$p.res_lease_path }
            if (Has $p 'pwsh_path')        { $PwshPath = [string]$p.pwsh_path }
            if (Has $p 'warm')             { $Warm = [bool]$p.warm }
            if (Has $p 'evict_warm')       { $EvictWarm = [bool]$p.evict_warm }
            if (Has $p 'warm_registry_path') { $WarmRegistryPath = [string]$p.warm_registry_path }
            if (Has $p 'logprobs')         { $Logprobs = [bool]$p.logprobs }
            if (Has $p 'top_logprobs')     { $TopLogprobs = [int]$p.top_logprobs }
            if (Has $p 'ensure_resident')  { $EnsureResident = [bool]$p.ensure_resident }
            if (Has $p 'pool_status')      { $PoolStatus = [bool]$p.pool_status }
            if (Has $p 'sweep_idle')       { $SweepIdle = [bool]$p.sweep_idle }
            if (Has $p 'cache_type_k')     { $CacheTypeK = [string]$p.cache_type_k }
            if (Has $p 'cache_type_v')     { $CacheTypeV = [string]$p.cache_type_v }
            if (Has $p 'flash_attn')       { $FlashAttn = [bool]$p.flash_attn }
            if (Has $p 'parallel')         { $Parallel = [int]$p.parallel }
            if (Has $p 'id_slot')          { $IdSlot = [int]$p.id_slot }
            if (Has $p 'clear_slot')       { $ClearSlot = [bool]$p.clear_slot }
            if (Has $p 'keep_resident_s')  { $KeepResidentSeconds = [int]$p.keep_resident_s }
            if (Has $p 'generation')       { $Generation = [int]$p.generation }
            if (Has $p 'force_reload')     { $ForceReload = [bool]$p.force_reload }
            if (Has $p 'expect_generation'){ $ExpectGeneration = [string]$p.expect_generation }
            if (Has $p 'expect_fence')     { $ExpectFence = [int]$p.expect_fence }
            if (Has $p 'fence_ttl_s')      { $FenceTtlSeconds = [int]$p.fence_ttl_s }
            if (Has $p 'prepare_gpu')      { $PrepareGpu = [bool]$p.prepare_gpu }
            if (Has $p 'required_vram_mib'){ $RequiredVramMib = [int]$p.required_vram_mib }
            if (Has $p 'vram_safety_mib')  { $VramSafetyMib = [int]$p.vram_safety_mib }
            if (Has $p 'vram_confirm_timeout_ms') { $VramConfirmTimeoutMs = [int]$p.vram_confirm_timeout_ms }
            if (Has $p 'reconcile')        { $Reconcile = [bool]$p.reconcile }
            if (Has $p 'bypass_pool_manager') { $BypassPoolManager = [bool]$p.bypass_pool_manager }
            if (Has $p 'use_pool_lease_split')    { $UsePoolLeaseSplit = [bool]$p.use_pool_lease_split }
            if (Has $p 'split_priority')          { $SplitPriority = [int]$p.split_priority }
            if (Has $p 'owner_incarnation_id')    { $OwnerIncarnationId = [string]$p.owner_incarnation_id }
            if (Has $p 'split_required_vram_mib') { $SplitRequiredVramMib = [int]$p.split_required_vram_mib }
            if (Has $p 'split_exec_ttl_s')        { $SplitExecTtlSeconds = [int]$p.split_exec_ttl_s }
            if (Has $p 'split_pin_ttl_s')         { $SplitPinTtlSeconds = [int]$p.split_pin_ttl_s }
            if (Has $p 'split_drain_timeout_ms')  { $SplitDrainTimeoutMs = [int]$p.split_drain_timeout_ms }
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- warm-server registry path + mode flags (Governor Phase 2 warm + Phase 3 Stage-1 pool manager) ----
    $warmRegPath = Get-WarmRegistryPath $WarmRegistryPath
    $lockPath = "$warmRegPath.lock"
    # framing: the legacy escape forces the classic cold isolated-server path; the pool becomes a no-op layer.
    if ($BypassPoolManager) {
        if ($Warm -or $EnsureResident -or $PoolStatus -or $SweepIdle -or $PrepareGpu) { $warnings.Add('bypass_pool_manager: pool layer disabled for this call; classic cold isolated-server path') }
        $Warm = $false; $EnsureResident = $false; $PoolStatus = $false; $SweepIdle = $false; $PrepareGpu = $false; $Reconcile = $false
        if ($UsePoolLeaseSplit) { $warnings.Add('bypass_pool_manager: use_pool_lease_split disabled (classic path takes the plain per-call gpu lease)'); $UsePoolLeaseSplit = $false }
    }
    $doEvictWarm  = [bool]$EvictWarm
    $doPoolStatus = [bool]$PoolStatus
    $doSweepIdle  = [bool]$SweepIdle
    $doEnsure     = [bool]$EnsureResident
    $doPrepareGpu = [bool]$PrepareGpu
    $doReconcile  = [bool]$Reconcile
    if ($doEnsure) { $Warm = $true }   # a residency op MUST leave the server resident for the next call

    # ---- DURABLE SUPERVISOR routing (residual (a); default-OFF). If -UseSupervisor and a residency op is
    #      requested, ATTACH to a running persistent supervisor and let IT run the transition (its Job Object
    #      owns the server tree ACROSS invocations). Degrade to the per-call path (below) with a warning if no
    #      supervisor is live. Inference is NOT routed -- it reuses the supervisor-published resident via the
    #      classic warm path (the supervisor publishes to the SAME warm-server.json). ----
    $supervisorRouted = $false
    # i21 split: an -EnsureResident under -UsePoolLeaseSplit is NOT short-circuit-routed -- the v0.4 two-phase
    # transition must WRAP the supervisor launch (the split residency path below still routes the actual server
    # start/stop through the supervisor; only the orchestration moves into the transition).
    if ($UseSupervisor -and -not $BypassPoolManager -and (($doEnsure -and -not $UsePoolLeaseSplit) -or $doPoolStatus -or $doPrepareGpu -or $doEvictWarm -or $doReconcile)) {
        $supOp = if ($doReconcile) { 'reconcile' } elseif ($doPrepareGpu) { 'prepare_gpu' } elseif ($doEvictWarm) { 'evict' } elseif ($doPoolStatus) { 'status' } else { 'ensure_resident' }
        $supParams = @{}
        if ($doEnsure) {
            if (-not [string]::IsNullOrWhiteSpace($Model)) { $supParams['model'] = $Model }
            if (-not [string]::IsNullOrWhiteSpace($Tier))  { $supParams['tier'] = $Tier }
            if ($GpuLayers -ge 0) { $supParams['gpu_layers'] = $GpuLayers }
            if ($Context -gt 0)   { $supParams['context'] = $Context }
            $supParams['cache_type_k'] = $CacheTypeK; $supParams['cache_type_v'] = $CacheTypeV
            if ($FlashAttn) { $supParams['flash_attn'] = $true }
            if ($Parallel -gt 0) { $supParams['parallel'] = $Parallel }
            if (([bool]$ForceReload) -or ($Generation -ge 0)) { $supParams['force_reload'] = $true }
        }
        if ($doPrepareGpu) { $supParams['required_vram_mib'] = $RequiredVramMib; $supParams['safety_mib'] = $VramSafetyMib }
        $supResp = Invoke-SupervisorClient -Op $supOp -Params $supParams -SupRoot $SupervisorRoot -WarmReg $warmRegPath -TimeoutMs ([Math]::Max(60000, ($LoadTimeoutSec * 1000)))
        if ($null -ne $supResp -and [bool]$supResp.ok) {
            $supervisorRouted = $true
            $rr = $supResp.response.result
            if ($doReconcile) { $result = [ordered]@{ action = 'reconcile'; via_supervisor = $true; reconcile = $rr } }
            elseif ($doPrepareGpu) { $result = [ordered]@{ action = 'prepare_gpu'; via_supervisor = $true; gpu = $rr } }
            elseif ($doEvictWarm) { $result = [ordered]@{ action = 'evict_warm'; via_supervisor = $true; warm = $rr } }
            elseif ($doPoolStatus) { $result = [ordered]@{ action = 'pool_status'; via_supervisor = $true; pool = $rr } }
            else {
                $result = [ordered]@{
                    model = $(if (Has $rr 'model_id') { [string]$rr.model_id } else { $Model }); engine = 'llama-server'; mode = 'ensure_resident'; via_supervisor = $true
                    pool = [ordered]@{
                        action = $(if (Has $rr 'action') { [string]$rr.action } else { $null }); reused = $(if (Has $rr 'reused') { [bool]$rr.reused } else { $null }); started_new = $(if (Has $rr 'started_new') { [bool]$rr.started_new } else { $null })
                        evicted = $(if (Has $rr 'evicted') { [bool]$rr.evicted } else { $null }); evict_confirmed = $(if (Has $rr 'evict_confirmed') { $rr.evict_confirmed } else { $null })
                        resident_config_hash = $(if (Has $rr 'resident_config_hash') { [string]$rr.resident_config_hash } else { $null }); residency_key_sha = $(if (Has $rr 'resident_config_hash') { [string]$rr.resident_config_hash } else { $null })
                        instance_generation = $(if (Has $rr 'instance_generation') { [string]$rr.instance_generation } else { $null }); fence = $(if (Has $rr 'fence') { $rr.fence } else { $null }); fence_ttl_seconds = $FenceTtlSeconds
                        can_serve = $(if (Has $rr 'can_serve') { $rr.can_serve } else { $null }); can_serve_mismatches = $(if (Has $rr 'can_serve_mismatches') { $rr.can_serve_mismatches } else { @() })
                        socket_owner_verified = $(if (Has $rr 'socket_owner_verified') { $rr.socket_owner_verified } else { $null })
                        swap_count = $(if (Has $rr 'swap_count') { [int]$rr.swap_count } else { $null }); keep_resident_seconds = $(if (Has $rr 'keep_resident_seconds') { [int]$rr.keep_resident_seconds } else { $KeepResidentSeconds })
                        load_ms = $(if (Has $rr 'load_ms') { [int]$rr.load_ms } else { $null }); health_ok = $(if (Has $rr 'health_ok') { [bool]$rr.health_ok } else { $null }); job_owned = $(if (Has $rr 'job_owned') { [bool]$rr.job_owned } else { $null })
                        vram = $(if (Has $rr 'vram') { $rr.vram } else { $null })
                    }
                    server = [ordered]@{ port = $(if (Has $rr 'port') { $rr.port } else { $null }); pid = $(if (Has $rr 'pid') { $rr.pid } else { $null })
                        warm = [ordered]@{ enabled = $true; reused = $(if (Has $rr 'reused') { [bool]$rr.reused } else { $null }); started_new = $(if (Has $rr 'started_new') { [bool]$rr.started_new } else { $null }); registry_path = $warmRegPath; via_supervisor = $true } }
                }
            }
            $status = 'ok'
            Write-Diag "use_supervisor: routed op=$supOp ok=true action=$(if (Has $rr 'action') { $rr.action } else { $supOp })"
        } else {
            $rc = if ($null -ne $supResp -and $null -ne $supResp.error) { [string]$supResp.error.code } else { 'supervisor_unavailable' }
            # i23 MF8 (red-team blocker 6): a WEDGED-but-ALIVE supervisor still owns the GPU tree. Its error carries
            # no_fallback=true. In that case we MUST NOT spawn a per-call second server (that + a stolen lock =
            # split-brain) -- FAIL CLOSED. Only a genuinely absent/dead supervisor (no_fallback=false) degrades to
            # the per-call path. Recovery from a wedge is the out-of-process watchdog relaunch, not a second server.
            $errObjR = if ($null -ne $supResp) { $supResp.error } else { $null }
            $noFallback = $false
            if ($null -ne $errObjR) {
                if ($errObjR -is [System.Collections.IDictionary]) { $noFallback = ($errObjR.Contains('no_fallback') -and [bool]$errObjR['no_fallback']) }
                elseif ($errObjR.PSObject -and ($errObjR.PSObject.Properties.Name -contains 'no_fallback')) { $noFallback = [bool]$errObjR.no_fallback }
            }
            if ($noFallback) {
                $supervisorRouted = $true   # skip the per-call residency path entirely
                $status = 'error'
                $errorObj = [ordered]@{ code = $rc; message = "supervisor alive but unresponsive ($rc); failing closed -- NO per-call fallback (split-brain / stolen-lock guard). Recover via the watchdog supervisor relaunch."; retryable = $true }
                $result = [ordered]@{ action = $supOp; via_supervisor = $false; supervisor_unresponsive = $true }
                $warnings.Add("use_supervisor: supervisor UNRESPONSIVE ($rc); FAILING CLOSED (no per-call fallback -> no split-brain)")
                Write-Diag "use_supervisor: FAIL-CLOSED ($rc) -- no second server spawned"
            } else {
                $warnings.Add("use_supervisor: no live supervisor ($rc); falling back to the per-call path")
                Write-Diag "use_supervisor: fallback ($rc)"
            }
        }
    }

    # #3: reconcile on EVERY startup for any pool-touching path so a crashed transition self-heals before use.
    $reconcileResult = $null
    $poolTouch = ($doEvictWarm -or $doPoolStatus -or $doSweepIdle -or $doEnsure -or $doPrepareGpu -or $doReconcile -or [bool]$Warm)
    if ($script:PoolCoreLoaded -and $poolTouch -and -not $supervisorRouted) {
        try { $reconcileResult = Invoke-PoolReconcile -WarmRegPath $warmRegPath -LockPath $lockPath } catch { $warnings.Add("reconcile error: $($_.Exception.Message)") }
    }

    if ($supervisorRouted) {
        # residency op already handled by the durable supervisor; result is set above. Fall through to emit.
        Write-Diag "use_supervisor: op handled by supervisor; skipping per-call residency path"
    }
    elseif ($doReconcile) {
        # ---- RECONCILE op: run crash-recovery and RETURN a report (no lease, no model load) ----
        $status = 'ok'
        $result = [ordered]@{ action = 'reconcile'; reconcile = $(if ($null -ne $reconcileResult) { $reconcileResult } else { [ordered]@{ ran = $false; note = 'pool core not loaded' } }) }
        Write-Diag "reconcile: ran=$($null -ne $reconcileResult)"
    }
    elseif ($doPrepareGpu) {
        # ---- PREPARE GPU (finding 2): evict-before-grant so a handoff to another consumer never OOMs ----
        $pgReg = Read-WarmServer $warmRegPath
        $pgHasResident = $false; $pgKilled = $false; $pgReason = 'no_resident'
        $pgFreeBefore = Get-GpuFreeMib; $pgFreeAfter = $pgFreeBefore
        if ($null -ne $pgReg) {
            $pgl = Get-WarmServerLiveness $pgReg
            $pgHasResident = [bool]$pgl.alive
        }
        $plan = if ($script:PoolCoreLoaded) { Get-GpuHandoffPlan -FreeMib $pgFreeBefore -RequiredMib $RequiredVramMib -HasResident $pgHasResident -SafetyMib $VramSafetyMib } else { [ordered]@{ decision = 'grant'; reason = 'pool_core_absent'; free_mib = $pgFreeBefore; target_mib = ($RequiredVramMib + $VramSafetyMib); headroom_ok = $null } }
        if ($plan.decision -eq 'evict_then_grant' -and $null -ne $pgReg) {
            $lk = if ($script:PoolCoreLoaded) { Enter-PoolLock -LockPath $lockPath -TimeoutMs 8000 } else { $null }
            try {
                $pgl2 = Get-WarmServerLiveness $pgReg
                if ($pgl2.alive) {
                    if (Stop-ResidentServer $pgReg $pgl2) {
                        $pgKilled = $true; $pgReason = 'evicted_for_handoff'; Clear-WarmServer $warmRegPath
                        # finding 15: WDDM frees async -> confirm recovery over an interval, not a single sample
                        $deadline = (Get-Date).AddMilliseconds($VramConfirmTimeoutMs); $target = $RequiredVramMib + $VramSafetyMib
                        while ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200; $pgFreeAfter = Get-GpuFreeMib; if ($null -eq $pgFreeAfter -or $pgFreeAfter -ge $target) { break } }
                    } else { $pgReason = 'alive_unidentified_not_killed'; $warnings.Add('prepare_gpu: resident alive but unidentified; not killed') }
                }
            } finally { if ($null -ne $lk) { Exit-PoolLock $lk } }
        } elseif ($plan.decision -eq 'grant') { $pgReason = 'headroom_available' }
        elseif ($plan.decision -eq 'insufficient') { $pgReason = 'insufficient_headroom_no_resident'; $warnings.Add('prepare_gpu: insufficient VRAM headroom and no resident to evict') }
        $pgTarget = $RequiredVramMib + $VramSafetyMib
        $pgReady = $false
        if ($null -eq $pgFreeAfter) { $pgReady = ($plan.decision -ne 'insufficient') }   # unknown VRAM: ready unless the planner said impossible
        else { $pgReady = ($pgFreeAfter -ge $pgTarget) }
        $status = 'ok'
        $result = [ordered]@{
            action = 'prepare_gpu'
            gpu = [ordered]@{
                required_vram_mib = $RequiredVramMib; safety_mib = $VramSafetyMib; target_mib = $pgTarget
                had_resident = $pgHasResident; plan = $plan.decision; reason = $pgReason; evicted = $pgKilled
                free_mib_before = $pgFreeBefore; free_mib_after = $pgFreeAfter
                recovered_mib = $(if ($null -ne $pgFreeBefore -and $null -ne $pgFreeAfter) { ($pgFreeAfter - $pgFreeBefore) } else { $null })
                ready = $pgReady
            }
        }
        Write-Diag "prepare_gpu: plan=$($plan.decision) evicted=$pgKilled free_after=$pgFreeAfter ready=$pgReady"
    }
    elseif ($doEvictWarm) {
        # ---- EVICT shortcut: tear down the resident warm server and return (no model load, no generation) ----
        $evResident = Read-WarmServer $warmRegPath
        $evAlive = $false; $evIdentity = $false; $evEvicted = $false
        if ($null -ne $evResident) {
            $evl = Get-WarmServerLiveness $evResident
            $evAlive = [bool]$evl.alive; $evIdentity = [bool]$evl.identity_ok
            if (Stop-ResidentServer $evResident $evl) { $evEvicted = $true }
            else { $warnings.Add('evict_warm: resident alive but unidentified; not killed (possible external process)') }
            Clear-WarmServer $warmRegPath
        }
        $status = 'ok'
        $result = [ordered]@{
            action = 'evict_warm'
            warm   = [ordered]@{ registry_path = $warmRegPath; had_resident = ($null -ne $evResident); was_alive = $evAlive; identity_ok = $evIdentity; evicted = $evEvicted; resident_pid = $(if ($null -ne $evResident -and (Has $evResident 'pid')) { [int]$evResident.pid } else { $null }) }
        }
        Write-Diag "evict_warm: had_resident=$($null -ne $evResident) alive=$evAlive evicted=$evEvicted"
    }
    elseif ($doPoolStatus) {
        # ---- POOL STATUS: read-only report of the current resident (no lease, no model load, no change) ----
        $psReg = Read-WarmServer $warmRegPath
        $psAlive = $false; $psId = $false; $psHealthy = $false; $psIdleMs = $null
        if ($null -ne $psReg) {
            $psl = Get-WarmServerLiveness $psReg
            $psAlive = [bool]$psl.alive; $psId = [bool]$psl.identity_ok
            $psPort = if (Has $psReg 'port') { [int]$psReg.port } else { 0 }
            $psHealthy = $psAlive -and (Test-ServerHealthy '127.0.0.1' $psPort)
            $psIdleMs = Get-ResidentIdleMs $psReg
        }
        $status = 'ok'
        $result = [ordered]@{
            action = 'pool_status'
            pool = [ordered]@{
                registry_path = $warmRegPath; has_resident = ($null -ne $psReg)
                resident_pid = $(if ($null -ne $psReg -and (Has $psReg 'pid')) { [int]$psReg.pid } else { $null })
                model_id = $(if ($null -ne $psReg -and (Has $psReg 'model_id')) { [string]$psReg.model_id } else { $null })
                residency_key_sha = $(if ($null -ne $psReg -and (Has $psReg 'residency_key_sha')) { [string]$psReg.residency_key_sha } else { $null })
                alive = $psAlive; identity_ok = $psId; healthy = $psHealthy
                idle_ms = $psIdleMs; keep_resident_seconds = $KeepResidentSeconds
                idle_expired = $(if ($null -ne $psIdleMs) { ($psIdleMs -gt ($KeepResidentSeconds * 1000)) } else { $null })
                swap_count = $(if ($null -ne $psReg -and (Has $psReg 'swap_count')) { [int]$psReg.swap_count } else { $null })
                resident_since_utc = $(if ($null -ne $psReg -and (Has $psReg 'resident_since_utc')) { [string]$psReg.resident_since_utc } else { $null })
                last_used_utc = $(if ($null -ne $psReg -and (Has $psReg 'last_used_utc')) { [string]$psReg.last_used_utc } else { $null })
            }
        }
        Write-Diag "pool_status: has_resident=$($null -ne $psReg) healthy=$psHealthy idle_ms=$psIdleMs"
    }
    elseif ($doSweepIdle) {
        # ---- SWEEP IDLE: evict the resident IFF it is idle beyond the keep-resident window (contender reclaim) ----
        $swReg = Read-WarmServer $warmRegPath
        $swIdleMs = Get-ResidentIdleMs $swReg
        $swWindowMs = $KeepResidentSeconds * 1000
        $swEvicted = $false; $swKept = $false; $swVramBefore = $null; $swVramAfter = $null; $swReason = 'no_resident'
        if ($null -ne $swReg) {
            # finding 11: idle eviction is a POLICY op, not an autonomous correctness mechanism. Take the lock and
            # RE-READ under it (generation-conditional) so a request that refreshed the resident just now is not
            # raced into eviction. LRU is meaningless at capacity 1 and is NOT used.
            $swLock = if ($script:PoolCoreLoaded) { Enter-PoolLock -LockPath $lockPath -TimeoutMs 8000 } else { $null }
            try {
                $swReg = Read-WarmServer $warmRegPath          # re-read under the lock
                $swIdleMs = Get-ResidentIdleMs $swReg
                if ($null -eq $swReg) { $swReason = 'no_resident' }
                else {
                    $swl = Get-WarmServerLiveness $swReg
                    $expired = ($null -ne $swIdleMs -and $swIdleMs -gt $swWindowMs)
                    if (-not $swl.alive) { Clear-WarmServer $warmRegPath; $swReason = 'stale_registry_cleared' }
                    elseif ($expired) {
                        $swVramBefore = Get-GpuFreeMib
                        if (Stop-ResidentServer $swReg $swl) {
                            $swEvicted = $true; $swReason = 'idle_evicted'; Clear-WarmServer $warmRegPath
                            Start-Sleep -Milliseconds 200; $swVramAfter = Get-GpuFreeMib
                        } else { $swReason = 'alive_unidentified_not_killed'; $warnings.Add('sweep_idle: resident alive but unidentified; not killed') }
                    } else { $swKept = $true; $swReason = 'within_keep_resident_window' }
                }
            } finally { if ($null -ne $swLock) { Exit-PoolLock $swLock } }
        }
        $status = 'ok'
        $result = [ordered]@{
            action = 'sweep_idle'
            pool = [ordered]@{
                registry_path = $warmRegPath; had_resident = ($null -ne $swReg); idle_ms = $swIdleMs
                keep_resident_seconds = $KeepResidentSeconds; evicted = $swEvicted; kept = $swKept; reason = $swReason
                resident_pid = $(if ($null -ne $swReg -and (Has $swReg 'pid')) { [int]$swReg.pid } else { $null })
                vram_free_mib_before = $swVramBefore; vram_free_mib_after = $swVramAfter
                vram_recovered_mib = $(if ($null -ne $swVramBefore -and $null -ne $swVramAfter) { ($swVramAfter - $swVramBefore) } else { $null })
            }
        }
        Write-Diag "sweep_idle: had_resident=$($null -ne $swReg) idle_ms=$swIdleMs evicted=$swEvicted reason=$swReason"
    }
    else {

    # ---- load registry ----
    if ([string]::IsNullOrWhiteSpace($Registry)) { $Registry = Join-Path $PSScriptRoot 'models.json' }
    if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) {
        throw [PSCustomObject]@{ code = 'registry_not_found'; message = "model registry not found: $Registry"; retryable = $false }
    }
    $reg = (Get-Content -LiteralPath $Registry -Raw) | ConvertFrom-Json
    $models = @()
    if (Has $reg 'models') { $models = @($reg.models) }

    # ---- resolve the requested model ----
    $selectedFrom = $null
    $wantId = $null
    if (-not [string]::IsNullOrWhiteSpace($Model)) { $wantId = $Model; $selectedFrom = 'model_id' }
    elseif (-not [string]::IsNullOrWhiteSpace($Tier)) {
        $selectedFrom = "tier:$Tier"
        if ((Has $reg 'tiers') -and (Has $reg.tiers 'llm') -and (Has $reg.tiers.llm $Tier)) { $wantId = [string]$reg.tiers.llm.$Tier }
        else { throw [PSCustomObject]@{ code = 'tier_not_found'; message = "tier '$Tier' is not defined for llm in the registry"; retryable = $false } }
    }
    else {
        $selectedFrom = 'default'
        if ((Has $reg 'defaults') -and (Has $reg.defaults 'llm')) { $wantId = [string]$reg.defaults.llm }
        else { throw [PSCustomObject]@{ code = 'no_model_selected'; message = "provide -Model or -Tier; no registry default llm is set"; retryable = $false } }
    }

    $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $wantId) } | Select-Object -First 1
    if ($null -eq $m) {
        $known = ($models | ForEach-Object { $_.model_id }) -join ', '
        throw [PSCustomObject]@{ code = 'model_not_found'; message = "model '$wantId' not in registry. Known: $known"; retryable = $false }
    }

    $mType = if (Has $m 'type') { [string]$m.type } else { 'unknown' }
    $mWired = ((Has $m 'wired') -and [bool]$m.wired)
    if (-not $mWired) {
        $where = if ($wireModuleByType.ContainsKey($mType)) { $wireModuleByType[$mType] } else { 'a later module' }
        throw [PSCustomObject]@{ code = 'model_not_wired'; message = "model '$wantId' (type=$mType) is declared but not wired to run in the gateway MVP; execution arrives in $where. It is staged and ready."; retryable = $false }
    }
    if ($mType -ne 'llm') {
        throw [PSCustomObject]@{ code = 'unsupported_type'; message = "gateway MVP runs type=llm only (got '$mType')"; retryable = $false }
    }
    $engine = if (Has $m 'engine') { [string]$m.engine } else { '' }
    if ($engine -ne 'llama-server') {
        throw [PSCustomObject]@{ code = 'unsupported_engine'; message = "gateway MVP supports engine=llama-server only (got '$engine')"; retryable = $false }
    }
    $enginePath = if (Has $m 'engine_path') { [string]$m.engine_path } elseif (Has $reg 'engines') { $null } else { $null }
    if ([string]::IsNullOrWhiteSpace($enginePath) -and (Has $reg 'engines') -and (Has $reg.engines 'llama-server')) { $enginePath = [string]$reg.engines.'llama-server' }
    if ([string]::IsNullOrWhiteSpace($enginePath) -or -not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
        throw [PSCustomObject]@{ code = 'engine_not_found'; message = "llama-server engine not found at '$enginePath'"; retryable = $false }
    }
    $modelPath = if (Has $m 'path') { [string]$m.path } else { '' }
    if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code = 'model_file_missing'; message = "model file not found at '$modelPath'"; retryable = $true }
    }

    # ---- resolve runtime knobs (explicit override > registry > default) ----
    $ngl = if ($GpuLayers -ge 0) { $GpuLayers } elseif (Has $m 'gpu_layers') { [int]$m.gpu_layers } else { 99 }
    $ctx = if ($Context -gt 0) { $Context } elseif (Has $m 'context') { [int]$m.context } else { 4096 }

    # ---- Stage-1.1 pool manager: resolve residency knobs; SPLIT resident_config_hash (deterministic, hashes
    #      CONTENTS; finding 6) from instance_generation (per-launch fencing nonce). CanServe (finding 8) decides
    #      reuse vs reload -- NOT raw key equality. ----
    $noThink  = ((Has $m 'no_think') -and [bool]$m.no_think)
    $ctkUse   = $CacheTypeK; $ctvUse = $CacheTypeV
    $flashUse = [bool]$FlashAttn
    $npUse    = if ($Parallel -gt 0) { $Parallel } else { 1 }
    $poolMode = [bool]$Warm    # warm/pool launches get the pool server flags; OFF -> classic path byte-for-byte unchanged
    $engineExeHash = if ($script:PoolCoreLoaded) { Get-EngineExeHashCached $enginePath } else { $null }
    $reqConfig = $null
    if ($script:PoolCoreLoaded) {
        $reqConfig       = Get-ResidentConfig $m $reg $ngl $ctx $noThink $ctkUse $ctvUse $flashUse $npUse $engineExeHash
        $residencyKey    = $reqConfig                        # 0.3: the residency key IS the resident config block
        $residencyKeySha = Get-ResidentConfigHash $reqConfig
    } else {
        $residencyKey    = Get-ResidencyKey $m $reg $ngl $ctx $noThink $ctkUse $ctvUse $flashUse $npUse $Generation
        $residencyKeySha = Get-ResidencyKeySha $residencyKey
    }
    # finding 6: -Generation no longer poisons the config hash; if set (>=0) or -ForceReload, force an evict+reload.
    $forceReload = ([bool]$ForceReload) -or ($Generation -ge 0)

    # ---- build chat messages ----
    $msgList = New-Object System.Collections.Generic.List[object]
    if ($null -ne $messages) {
        foreach ($mm in @($messages)) { $msgList.Add([ordered]@{ role = [string]$mm.role; content = [string]$mm.content }) }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($System)) { $msgList.Add([ordered]@{ role = 'system'; content = $System }) }
        if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $msgList.Add([ordered]@{ role = 'user'; content = $Prompt }) }
        elseif (-not $doEnsure) { throw [PSCustomObject]@{ code = 'no_prompt'; message = "provide -Prompt (or messages in -InputsJson)"; retryable = $false } }
        # -EnsureResident is a residency op with no generation, so a prompt is not required.
    }
    $msgArr = $msgList.ToArray()
    if ((Has $m 'no_think') -and [bool]$m.no_think) {
        $sysIdx = -1
        for ($i = 0; $i -lt $msgList.Count; $i++) { if ([string]$msgList[$i].role -eq 'system') { $sysIdx = $i; break } }
        if ($sysIdx -ge 0) { $msgList[$sysIdx].content = ([string]$msgList[$sysIdx].content).TrimEnd() + ' /no_think' }
        else { $msgList.Insert(0, [ordered]@{ role = 'system'; content = '/no_think' }) }
    }
    $stopArr = @()
    if ($null -ne $Stop -and @($Stop).Count -gt 0) { $stopArr = @($Stop) }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ model = $m.model_id; messages = $msgArr; max_tokens = $MaxTokens; temperature = $Temperature; top_p = $TopP; top_k = $TopK; seed = $Seed; stop = $stopArr }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Depth 8 -Compress)))

    # ---- pick a port ----
    $usePort = if ($Port -gt 0) { $Port } else { Get-FreePort 8140 }
    if ($usePort -le 0) { throw [PSCustomObject]@{ code = 'no_free_port'; message = 'could not find a free loopback port'; retryable = $true } }

    # ---- GPU lease (res.lease #29): acquire BEFORE starting llama-server; release AFTER teardown ----
    $glMode = if ([string]::IsNullOrWhiteSpace($GpuLease)) { 'auto' } else { $GpuLease.ToLowerInvariant() }
    if (@('off','auto','wait','require') -notcontains $glMode) { $warnings.Add("unknown -GpuLease '$GpuLease'; using 'auto'"); $glMode = 'auto' }
    $glHolder = if (-not [string]::IsNullOrWhiteSpace($GpuLeaseHolder)) { $GpuLeaseHolder }
                elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE }
                else { "model.gateway:$PID" }
    $leaseState = [ordered]@{
        mode = $glMode; requested = ($glMode -ne 'off'); available = $null
        acquired = $false; owned = $false; already_held = $false; reclaimed_stale = $false
        lease_id = $null; holder = $glHolder; held_by = $null; released = $null; note = $null
    }
    $srvLog = Join-Path $invDir 'server.out.log'; $srvErr = Join-Path $invDir 'server.err.log'
    $srvArgs = @('-m', $modelPath, '-ngl', "$ngl", '-c', "$ctx", '--host', '127.0.0.1', '--port', "$usePort", '--no-warmup')
    # Stage-1 pool flags: pin one slot for deterministic same-model prefix reuse (-np 1) + KV/flash-attn key fields.
    # Only added in pool/warm mode -> the classic per-call (non-warm) launch is byte-for-byte unchanged.
    if ($poolMode) {
        $srvArgs += @('--parallel', "$npUse")
        if (-not [string]::IsNullOrWhiteSpace($ctkUse) -and $ctkUse -ne 'f16') { $srvArgs += @('--cache-type-k', $ctkUse) }
        if (-not [string]::IsNullOrWhiteSpace($ctvUse) -and $ctvUse -ne 'f16') { $srvArgs += @('--cache-type-v', $ctvUse) }
        if ($flashUse) { $srvArgs += @('--flash-attn') }
    }
    $sp = $null; $serverPid = 0; $healthOk = $false; $healthMs = $null; $loadStart = $null
    $resp = $null
    # ---- i21 GPU-lease-split state (ALL inert when -UsePoolLeaseSplit is off) ----
    $splitOn = $false
    $splitState = $null
    if ($UsePoolLeaseSplit) {
        if (-not $poolMode -and -not $doEnsure) { $warnings.Add('use_pool_lease_split requires the pool (-Warm / -EnsureResident); flag ignored for this classic call') }
        elseif (-not $script:PoolCoreLoaded)    { $warnings.Add('use_pool_lease_split requires lib/PoolManager.psm1; flag ignored') }
        elseif ($glMode -eq 'off')              { $warnings.Add('use_pool_lease_split requires the gpu lease (-GpuLease off given); flag ignored') }
        else {
            $rlProbe = Resolve-ResLeasePath
            if ($null -eq $rlProbe) { throw [PSCustomObject]@{ code = 'res_lease_required_for_split'; message = 'use_pool_lease_split requires modules/29-resource-lease/Invoke-ResLease.ps1 (not found); the split is fail-closed, not gracefully degraded'; retryable = $false } }
            $splitOn = $true
            $splitInc = if (-not [string]::IsNullOrWhiteSpace($OwnerIncarnationId)) { $OwnerIncarnationId }
                        elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_OWNER_INCARNATION)) { $env:LIFEORCH_OWNER_INCARNATION }
                        else { 'inc' + [Guid]::NewGuid().ToString('N') }
            $splitPrio = Get-SplitTierPriority $Tier $m.model_id $reg
            $splitStoredPinPrio = $splitPrio   # the STORED pin priority (re-read from check; a re-attach keeps the original)
            $splitState = [ordered]@{
                on = $true; priority = $splitPrio; owner_incarnation_id = $splitInc
                pin = $null; pin_contended = $false; revocation = $null
                transition = $null; commit = $null; exec_released = $null; repinned = $null
                active = $null; pending_txn_id = $null; swap_committed = $false; discard_check = $null
                required_vram_mib = 0; evictor = 'lib/PoolEvictor.ps1'
            }
        }
    }
    try {
        # -- i21 SPLIT: acquire/re-attach the revocable residency PIN (held BETWEEN calls; priority = tier);
        #    honor revocation on entry (a revoked pin means a higher-priority transition wants the GPU ->
        #    STOP SERVING and let it evict cleanly). The plain per-call lease branch below is byte-for-byte
        #    unchanged when the split is off. --
        if ($glMode -ne 'off' -and $splitOn) {
            $rlPath = Resolve-ResLeasePath
            $leaseState.available = $true
            $glWait = if ($glMode -eq 'auto') { 0 } else { $GpuLeaseWaitSeconds }
            $curManifest = Read-WarmServer $warmRegPath
            $pinIn = @{ action='acquire'; resource='gpu'; holder=$glHolder; kind='residency_pin'; priority=$splitPrio
                        ttl_seconds=$SplitPinTtlSeconds; wait_seconds=$glWait; owner_id=$glHolder
                        owner_incarnation_id=$splitInc; note='model.gateway split residency pin' }
            if ($null -ne $curManifest) {
                if (Has $curManifest 'instance_generation')   { $pinIn['resident_generation']  = [string]$curManifest.instance_generation }
                if (Has $curManifest 'resident_instance_id')  { $pinIn['resident_instance_id'] = [string]$curManifest.resident_instance_id }
            }
            $pinAcq = Invoke-ResLeaseJson -LeaseInputs $pinIn -RlPath $rlPath -PwshExe (Get-PwshExe)
            if ($null -eq $pinAcq) { throw [PSCustomObject]@{ code = 'gpu_split_lease_error'; message = 'res.lease pin acquire invocation failed (split is fail-closed)'; retryable = $true } }
            if ([bool]$pinAcq.acquired) {
                $leaseState.acquired = $true
                $leaseState.lease_id = [string]$pinAcq.lease_id
                $leaseState.already_held = [bool]$pinAcq.already_held
                $leaseState.reclaimed_stale = [bool]$pinAcq.reclaimed_stale
                $leaseState.owned = $false   # the PIN persists between calls BY DESIGN; never released by the classic finally
                $leaseState.note = 'split: residency pin persists between calls'
                $splitState.pin = [ordered]@{
                    lease_id = [string]$pinAcq.lease_id; already_held = [bool]$pinAcq.already_held
                    gpu_authority_epoch = $(if (Has $pinAcq 'gpu_authority_epoch') { [long]$pinAcq.gpu_authority_epoch } else { $null })
                    resident_generation = $(if (Has $pinAcq 'resident_generation') { $pinAcq.resident_generation } else { $null })
                    resident_instance_id = $(if (Has $pinAcq 'resident_instance_id') { $pinAcq.resident_instance_id } else { $null })
                    priority = $splitPrio; ttl_seconds = $SplitPinTtlSeconds
                }
                # re-attach does not extend the TTL -> explicit renew keeps the pin alive across long tasks
                if ([bool]$pinAcq.already_held) {
                    $null = Invoke-ResLeaseJson -LeaseInputs @{ action='renew'; resource='gpu'; holder=$glHolder; lease_id=[string]$pinAcq.lease_id; ttl_seconds=$SplitPinTtlSeconds } -RlPath $rlPath -PwshExe (Get-PwshExe)
                }
                # honor revocation on entry: a revoked pin => a higher-priority owner is taking the GPU.
                # (owner_incarnation_id engages the v0.4 check surface so the result REPORTS the pin's STORED
                # incarnation -- the continuity adoption below needs it; the *_current comparison is not used here.)
                $chk = Invoke-ResLeaseJson -LeaseInputs @{ action='check'; resource='gpu'; owner_id=$glHolder; owner_incarnation_id=$splitInc } -RlPath $rlPath -PwshExe (Get-PwshExe)
                if ($null -ne $chk -and (Has $chk 'priority') -and $null -ne $chk.priority) { $splitStoredPinPrio = [int]$chk.priority }
                # incarnation CONTINUITY on re-attach: the same logical owner re-attaching to its live pin is the
                # SAME incarnation (v0.4: a NEW incarnation is minted on owner RESTART = pin lost/expired). An
                # EXPLICIT -OwnerIncarnationId / $env:LIFEORCH_OWNER_INCARNATION (the governor's) always wins.
                $incExplicit = (-not [string]::IsNullOrWhiteSpace($OwnerIncarnationId)) -or (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_OWNER_INCARNATION))
                if (-not $incExplicit -and [bool]$pinAcq.already_held -and $null -ne $chk -and (Has $chk 'owner_incarnation_id') -and -not [string]::IsNullOrWhiteSpace([string]$chk.owner_incarnation_id)) {
                    $splitInc = [string]$chk.owner_incarnation_id
                    $splitState.owner_incarnation_id = $splitInc
                }
                if ($null -ne $chk) {
                    $splitState.revocation = [ordered]@{ fence_status = $(if (Has $chk 'fence_status') { [string]$chk.fence_status } else { $null }); revoked_by = $(if (Has $chk 'revoked_by') { $chk.revoked_by } else { $null }) }
                    $isRevoked = ((Has $chk 'revoked_by') -and $null -ne $chk.revoked_by) -or ((Has $chk 'fence_status') -and ([string]$chk.fence_status -eq 'revoked'))
                    if ($isRevoked) {
                        throw [PSCustomObject]@{ code = 'gpu_pin_revoked'; message = "split residency pin was REVOKED (revoked_by=$($chk.revoked_by)); stopping serving so the preempting transition can evict cleanly"; retryable = $true }
                    }
                }
                Write-Diag "split pin acquired lease_id=$($leaseState.lease_id) already_held=$($leaseState.already_held) prio=$splitPrio epoch=$($splitState.pin.gpu_authority_epoch)"
            } else {
                $splitState.pin_contended = $true
                $leaseState.held_by = [string]$pinAcq.held_by
                if ($glMode -eq 'require') {
                    throw [PSCustomObject]@{ code = 'gpu_lease_unavailable'; message = "gpu residency pin held by '$($pinAcq.held_by)'; -GpuLease require did not acquire within $glWait s"; retryable = $true }
                }
                Write-Diag "split pin contended held_by=$($pinAcq.held_by); a swap may still preempt via the transition (priority $splitPrio)"
            }
        }
        # -- acquire the gpu lease (graceful fallback: log + proceed if res.lease is absent; wait|proceed|require per the switch) --
        elseif ($glMode -ne 'off') {
            $rlPath = Resolve-ResLeasePath
            if ($null -eq $rlPath) {
                $leaseState.available = $false
                $leaseState.note = 'res.lease not found; proceeding without GPU arbitration'
                $warnings.Add('gpu lease: res.lease module not found; proceeding without a lease (graceful fallback)')
                Write-Diag $leaseState.note
            } else {
                $leaseState.available = $true
                $glWait = if ($glMode -eq 'auto') { 0 } else { $GpuLeaseWaitSeconds }
                $acq = Invoke-GpuLeaseAction -LeaseAction 'acquire' -Resource 'gpu' -Holder $glHolder -Ttl $GpuLeaseTtlSeconds -Wait $glWait -LeaseDirArg $LeaseDir -RlPath $rlPath -PwshExe (Get-PwshExe)
                if ($null -eq $acq) {
                    $leaseState.available = $false
                    $leaseState.note = 'res.lease invocation failed; proceeding without GPU arbitration'
                    $warnings.Add('gpu lease: res.lease invocation failed; proceeding without a lease (graceful fallback)')
                    Write-Diag $leaseState.note
                } elseif ([bool]$acq.acquired) {
                    $leaseState.acquired = $true
                    $leaseState.lease_id = [string]$acq.lease_id
                    $leaseState.already_held = [bool]$acq.already_held
                    $leaseState.reclaimed_stale = [bool]$acq.reclaimed_stale
                    $leaseState.owned = (-not [bool]$acq.already_held)   # release only what we freshly created
                    Write-Diag "gpu lease acquired lease_id=$($leaseState.lease_id) already_held=$($leaseState.already_held) reclaimed_stale=$($leaseState.reclaimed_stale) owned=$($leaseState.owned)"
                } else {
                    $leaseState.held_by = [string]$acq.held_by
                    if ($glMode -eq 'require') {
                        throw [PSCustomObject]@{ code = 'gpu_lease_unavailable'; message = "gpu lease held by '$($acq.held_by)'; -GpuLease require did not acquire within $glWait s"; retryable = $true }
                    }
                    $leaseState.note = "contended (held by '$($acq.held_by)'); proceeding"
                    $warnings.Add("gpu lease: $($leaseState.note) (log+proceed)")
                    Write-Diag "gpu lease contended held_by=$($acq.held_by); proceeding"
                }
            }
        }

        # ---- POOL MANAGER (Stage-1.1): reconcile+fence under the machine-global lock; CanServe decides reuse vs
        #      reload; residency is a crash-atomic state machine EMPTY->STARTING->RESIDENT (findings 1/3/4/8). ----
        $warmOn = [bool]$Warm
        $warmReused = $false; $warmStartedNew = $false; $warmEvicted = $false
        # pool telemetry (declared before the resident test so the cold-start path leaves them valid under StrictMode)
        $evictConfirmed = $null; $idleMsAtEntry = $null; $swapCount = 0; $residentSinceUtc = $null
        $vramBefore = $null; $vramAfter = $null; $vramRecovered = $null; $poolProvenance = $null
        $residencyAction = 'cold_start'
        $poolLock = $null; $myFence = -1; $prevFence = 0; $instanceGen = $null; $canServeInfo = $null; $socketOwnerVerified = $null
        # finding 1/3: hold the machine-global lock for the whole residency check/change (released after publish,
        # never over I/O). The FENCE is the residency EPOCH: a monotonic integer that bumps on each new launch and
        # is UNCHANGED across reuse, so a caller's -ExpectGeneration/-ExpectFence stays stable until a real swap.
        if ($poolMode -and $script:PoolCoreLoaded) {
            $poolLock = Enter-PoolLock -LockPath $lockPath -TimeoutMs 15000
            if (-not $poolLock.acquired) { $warnings.Add('pool lock not acquired within timeout; proceeding unserialized'); $poolLock = $null }
        }
        $resident = Read-WarmServer $warmRegPath
        # Only a manifest carrying a live pid is a residency claim; a fence-only skeleton is not a resident.
        $hasRealResident = ($null -ne $resident -and (Has $resident 'pid') -and ([int]$resident.pid -gt 0))
        if (-not $hasRealResident) { $resident = $null }
        if ($null -eq $resident) { $myFence = 1 }   # cold-start epoch
        if ($null -ne $resident) {
            $rl = Get-WarmServerLiveness $resident
            $residentPort = if (Has $resident 'port') { [int]$resident.port } else { 0 }
            $idleMsAtEntry = Get-ResidentIdleMs $resident
            $prevSwaps = if (Has $resident 'swap_count') { [int]$resident.swap_count } else { 0 }
            $prevFence = if (Has $resident 'fence') { [long]$resident.fence } else { 0 }
            # finding 8: CanServe(resident, request) -- exact identity + capacity '>=', NOT raw key equality.
            $canServe = $false
            if ($script:PoolCoreLoaded -and $null -ne $reqConfig -and (Has $resident 'resident_config')) {
                $canServeInfo = Test-CanServe $resident.resident_config $reqConfig
                $canServe = [bool]$canServeInfo.can_serve
            } elseif (Has $resident 'residency_key_sha') { $canServe = ([string]$resident.residency_key_sha -eq $residencyKeySha) }
            elseif ((Has $resident 'model_id') -and ([string]$resident.model_id -eq [string]$m.model_id) -and (Has $resident 'ngl') -and ([int]$resident.ngl -eq $ngl) -and (Has $resident 'ctx') -and ([int]$resident.ctx -eq $ctx)) { $canServe = $true }
            if ($forceReload) { $canServe = $false }
            $healthy = $rl.alive -and (Test-ServerHealthy '127.0.0.1' $residentPort)
            # finding 4: prove the resident by the LISTENING SOCKET OWNER, not a /v1/models alias (advisory off-box)
            if ($rl.alive -and $script:PoolCoreLoaded) { $socketOwnerVerified = Test-SocketOwner -Port $residentPort -ExpectedPid ([int]$resident.pid) -SocketOwnerProbe $script:SocketOwnerProbe }
            $identOk = ([bool]$rl.identity_ok) -and ($socketOwnerVerified -ne $false)
            if ($warmOn -and $healthy -and $canServe -and $identOk) {
                # ~1 ms REUSE: keep the epoch fence, refresh the keep-resident timer + carry swap count + renew TTL
                $usePort = $residentPort; $warmReused = $true; $residencyAction = 'reuse'; $swapCount = $prevSwaps; $myFence = $prevFence
                $residentSinceUtc = if (Has $resident 'resident_since_utc') { [string]$resident.resident_since_utc } else { $null }
                $instanceGen = if (Has $resident 'instance_generation') { [string]$resident.instance_generation } else { $null }
                $poolProvenance = [ordered]@{ ok = $true; source = 'reuse'; reported = @([string]$m.model_id) }
                try {
                    $obj = [ordered]@{}; foreach ($pp in $resident.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
                    $obj['last_used_utc'] = ([DateTime]::UtcNow).ToString('o')
                    [void](Write-WarmServer $warmRegPath $obj)
                    if ($myFence -ge 0 -and (Has $resident 'fence')) { [void](Update-FenceRenewal -Path $warmRegPath -Fence $myFence -TtlSeconds $FenceTtlSeconds) }
                } catch { }
                Write-Diag "pool reuse: pid=$($resident.pid) port=$usePort key=$($residencyKeySha.Substring(0,12)) idle_ms=$idleMsAtEntry can_serve=$canServe fence=$myFence"
            } else {
                # cannot serve / unhealthy / non-warm / forced -> EVICT (state STOPPING; confirm exit + VRAM) then reload
                $myFence = $prevFence + 1   # new residency epoch (monotonic across the swap chain)
                if ($poolMode -and $script:PoolCoreLoaded -and $null -ne $poolLock -and (Has $resident 'fence')) { [void](Set-ManifestCas -Path $warmRegPath -Fence $prevFence -Updates @{ state = 'STOPPING' }) }
                if ($splitOn) {
                    # i21 SPLIT: the eviction is NOT performed inline here -- the v0.4 two-phase transition below
                    # drives lib/PoolEvictor.ps1 (fence-op-gated, supervisor-routed drain->cancel->tree-kill->
                    # headroom-confirm). The manifest is left in place so the evictor can verify the EXACT
                    # target_resident_instance_id; the supervisor clears it on the targeted stop.
                    if ($warmOn -and -not $canServe) { $swapCount = $prevSwaps + 1 } else { $swapCount = $prevSwaps }
                    $residencyAction = if ($warmOn) { 'evict_reload' } else { 'cold_start' }
                    Write-Diag "split: deferring eviction of pid=$($resident.pid) to the two-phase transition (target=$(if (Has $resident 'resident_instance_id') { $resident.resident_instance_id } else { '<no-instance-id>' }))"
                    $resident = $null
                } else {
                if ($rl.alive) {
                    $vramBefore = Get-GpuFreeMib
                    if (Stop-ResidentServer $resident $rl) {
                        $warmEvicted = $true; $evictConfirmed = $true
                        Start-Sleep -Milliseconds 200; $vramAfter = Get-GpuFreeMib
                        if ($null -ne $vramBefore -and $null -ne $vramAfter) { $vramRecovered = ($vramAfter - $vramBefore) }
                        Write-Diag "pool evict: pid=$($resident.pid) can_serve=$canServe healthy=$healthy warm=$warmOn vram_recovered_mib=$vramRecovered fence=$myFence"
                    } else {
                        $evictConfirmed = $false
                        $warnings.Add("resident server pid=$($resident.pid) alive but unidentified; not killed (possible external process)")
                        Write-Diag 'resident unidentified; not killed'
                    }
                }
                if ($warmOn -and -not $canServe) { $swapCount = $prevSwaps + 1 } else { $swapCount = $prevSwaps }
                $residencyAction = if ($warmOn) { 'evict_reload' } else { 'cold_start' }
                Clear-WarmServer $warmRegPath
                $resident = $null
                }
            }
        }

        # ================= i21 SPLIT: any LOAD (swap or cold start) goes through the v0.4 TWO-PHASE TRANSITION ====
        # -Transition -TwoPhaseCommit -RequiredVramMiB <peak> -EvictorMode command -EvictorCommand lib/PoolEvictor.ps1
        # => a NON-usable transition_capability (the new server starts under scheduler authority, NOT an ordinary
        # exec lease); '-Action commit -HealthOk' AFTER health publishes + issues the first USABLE exec lease; on
        # failure '-Action commit -HealthFailed' drops the exact tentative instance and leaves the GPU EMPTY.
        # The transition runs as a SCHEDULER sub-identity ("<holder>!sched", priority pin+1) so it can preempt +
        # revoke our own (or the governor's) residency pin and target the exact old resident_instance_id.
        $splitSupLaunched = $false
        if ($splitOn -and -not $warmReused) {
            # never hold the gateway pool lock across the transition: the evictor -> supervisor stop takes the
            # SAME machine-global lock (a guaranteed self-deadlock otherwise). res.lease's txn claim + fence
            # serialize transitions; the supervisor's own lock serializes manifest mutation.
            if ($null -ne $poolLock) { Exit-PoolLock $poolLock; $poolLock = $null }
            $rlPath2 = Resolve-ResLeasePath
            $splitNewInstId = 'ri' + [Guid]::NewGuid().ToString('N')
            $splitNewGen = if ($script:PoolCoreLoaded) { New-InstanceGeneration } else { [Guid]::NewGuid().ToString('N') }
            $reqVram = $SplitRequiredVramMib
            if ($reqVram -le 0) {
                $szB = if ((Has $m 'params') -and (Has $m.params 'size_bytes')) { [long]$m.params.size_bytes } else { 0 }
                $szMib = [int][Math]::Ceiling($szB / 1048576.0)
                $reqVram = $szMib + [Math]::Max(512, [int][Math]::Ceiling($szMib * 0.10))   # measured-PEAK policy: weights + max(512 MiB, 10%) initial margin (NOT the GGUF size alone)
            }
            $splitState.required_vram_mib = $reqVram
            $splitSchedHolder = "$glHolder!sched"
            $evictorPath = Join-Path $PSScriptRoot 'lib/PoolEvictor.ps1'
            # our OWN pin (held by this holder): the scheduler sub-identity must strictly outrank the STORED pin
            # priority to preempt it (a swap of our own resident). A pin held by ANOTHER owner keeps our REAL
            # priority -- res.lease only revokes a strictly-lower-priority revocable pin (finding 13 preserved).
            $splitTransPrio = if ($leaseState.acquired -and -not $splitState.pin_contended) { [Math]::Max($splitPrio, $splitStoredPinPrio) + 1 } else { $splitPrio }
            $trIn = @{ action='acquire'; resource='gpu'; holder=$splitSchedHolder; kind='exec'; priority=$splitTransPrio
                       ttl_seconds=$SplitExecTtlSeconds; transition=$true; two_phase_commit=$true
                       required_vram_mib=$reqVram; target_headroom_mib=$VramSafetyMib
                       evictor_mode='command'; evictor_command=$evictorPath; drain_timeout_ms=$SplitDrainTimeoutMs
                       confirm_timeout_ms=$VramConfirmTimeoutMs
                       owner_id=$glHolder; owner_incarnation_id=$splitInc
                       resident_generation=$splitNewGen; resident_instance_id=$splitNewInstId
                       request_id=("split-" + $InvocationId) }
            $tr = Invoke-ResLeaseJson -LeaseInputs $trIn -RlPath $rlPath2 -PwshExe (Get-PwshExe)
            if ($null -eq $tr) { throw [PSCustomObject]@{ code = 'gpu_split_lease_error'; message = 'res.lease transition invocation failed (split is fail-closed)'; retryable = $true } }
            $splitState.transition = [ordered]@{
                transition_id = $(if (Has $tr 'transition_id') { [string]$tr.transition_id } else { $null })
                transition_state = $(if (Has $tr 'transition_state') { [string]$tr.transition_state } else { $null })
                acquired = [bool]$tr.acquired
                capability_only = $(if (Has $tr 'capability_only') { [bool]$tr.capability_only } else { $false })
                usable = $(if (Has $tr 'usable') { [bool]$tr.usable } else { $null })
                gpu_authority_epoch = $(if (Has $tr 'gpu_authority_epoch') { $tr.gpu_authority_epoch } else { $null })
                old_resident_instance_id = $(if (Has $tr 'old_resident_instance_id') { $tr.old_resident_instance_id } else { $null })
                resident_instance_id = $(if (Has $tr 'resident_instance_id') { $tr.resident_instance_id } else { $null })
                evict_performed = $(if (Has $tr 'evict_performed') { [bool]$tr.evict_performed } else { $false })
                tree_gone = $(if (Has $tr 'tree_gone') { $tr.tree_gone } else { $null })
                headroom_confirmed = $(if (Has $tr 'headroom_confirmed') { [bool]$tr.headroom_confirmed } else { $false })
                free_vram_mib = $(if (Has $tr 'free_vram_mib') { $tr.free_vram_mib } else { $null })
                evictor_outcome = $(if (Has $tr 'evictor_outcome') { $tr.evictor_outcome } else { $null })
                reason = $(if (Has $tr 'reason') { $tr.reason } else { $null })
                idempotent_replay = $(if (Has $tr 'idempotent_replay') { [bool]$tr.idempotent_replay } else { $false })
                revoked_pin = $(if (Has $tr 'revoked_pin') { $tr.revoked_pin } else { $null })
            }
            if (-not [bool]$tr.acquired) {
                $trReason = if (Has $tr 'reason') { [string]$tr.reason } else { 'unknown' }
                $code = if ($trReason -eq 'held_incompatible') { 'gpu_split_contended' } else { 'gpu_split_transition_failed' }
                throw [PSCustomObject]@{ code = $code; message = "two-phase transition did not grant (reason=$trReason evictor=$($splitState.transition.evictor_outcome) state=$($splitState.transition.transition_state)); fail-closed, nothing evicted beyond the transition's own receipts"; retryable = $true }
            }
            if (-not [bool]$splitState.transition.capability_only) {
                # a same-holder short-circuit (already_held) means the resource already belongs to this holder --
                # legal for res.lease but NOT a two-phase capability; treat as a fail-closed contention signal.
                throw [PSCustomObject]@{ code = 'gpu_split_transition_failed'; message = "transition returned a non-capability grant (reason=$($splitState.transition.reason)); expected a two-phase capability (usable:false)"; retryable = $true }
            }
            $splitState.pending_txn_id = [string]$splitState.transition.transition_id
            $warmEvicted = [bool]$splitState.transition.evict_performed
            $evictConfirmed = $(if ($warmEvicted) { [bool]$splitState.transition.headroom_confirmed } else { $null })
            $vramAfter = $splitState.transition.free_vram_mib
            Write-Diag "split transition: capability txn=$($splitState.pending_txn_id) epoch=$($splitState.transition.gpu_authority_epoch) old_inst=$($splitState.transition.old_resident_instance_id) new_inst=$splitNewInstId evicted=$warmEvicted evictor=$($splitState.transition.evictor_outcome)"

            # ---- start the new server UNDER the capability: via the DURABLE SUPERVISOR when available ----
            if ($UseSupervisor) {
                $supParams2 = @{ resident_instance_id = $splitNewInstId; instance_generation = $splitNewGen }
                if (-not [string]::IsNullOrWhiteSpace($Model)) { $supParams2['model'] = $Model }
                if (-not [string]::IsNullOrWhiteSpace($Tier))  { $supParams2['tier'] = $Tier }
                if ($GpuLayers -ge 0) { $supParams2['gpu_layers'] = $GpuLayers }
                if ($Context -gt 0)   { $supParams2['context'] = $Context }
                $supParams2['cache_type_k'] = $CacheTypeK; $supParams2['cache_type_v'] = $CacheTypeV
                if ($FlashAttn) { $supParams2['flash_attn'] = $true }
                if ($Parallel -gt 0) { $supParams2['parallel'] = $Parallel }
                $supResp2 = Invoke-SupervisorClient -Op 'ensure_resident' -Params $supParams2 -SupRoot $SupervisorRoot -WarmReg $warmRegPath -TimeoutMs ([Math]::Max(60000, ($LoadTimeoutSec * 1000)))
                if ($null -ne $supResp2 -and [bool]$supResp2.ok) {
                    $rr2 = $supResp2.response.result
                    $splitSupLaunched = $true
                    $warmStartedNew = $true
                    $serverPid = $(if (Has $rr2 'pid') { [int]$rr2.pid } else { 0 })
                    $usePort = $(if (Has $rr2 'port') { [int]$rr2.port } else { $usePort })
                    $healthOk = $(if (Has $rr2 'health_ok') { [bool]$rr2.health_ok } else { $false })
                    $healthMs = $(if (Has $rr2 'load_ms') { [int]$rr2.load_ms } else { $null })
                    $instanceGen = $(if ((Has $rr2 'instance_generation') -and -not [string]::IsNullOrWhiteSpace([string]$rr2.instance_generation)) { [string]$rr2.instance_generation } else { $splitNewGen })
                    $socketOwnerVerified = $(if (Has $rr2 'socket_owner_verified') { $rr2.socket_owner_verified } else { $null })
                    $poolProvenance = [ordered]@{ ok = $healthOk; source = 'supervisor'; reported = @([string]$m.model_id) }
                    Write-Diag "split launch via supervisor: pid=$serverPid port=$usePort health_ok=$healthOk load_ms=$healthMs inst=$splitNewInstId"
                } else {
                    $rc2 = if ($null -ne $supResp2 -and $null -ne $supResp2.error) { [string]$supResp2.error.code } else { 'supervisor_unavailable' }
                    # i23 MF8: a WEDGED-but-alive supervisor (no_fallback=true) must NOT be worked around with a
                    # per-call managed launch (split-brain risk). FAIL the transition closed; the outer cleanup
                    # releases the leases. A genuinely absent/dead supervisor (no_fallback=false) still degrades.
                    $errObjR2 = if ($null -ne $supResp2) { $supResp2.error } else { $null }
                    $noFallback2 = $false
                    if ($null -ne $errObjR2) {
                        if ($errObjR2 -is [System.Collections.IDictionary]) { $noFallback2 = ($errObjR2.Contains('no_fallback') -and [bool]$errObjR2['no_fallback']) }
                        elseif ($errObjR2.PSObject -and ($errObjR2.PSObject.Properties.Name -contains 'no_fallback')) { $noFallback2 = [bool]$errObjR2.no_fallback }
                    }
                    if ($noFallback2) {
                        throw [PSCustomObject]@{ code = 'supervisor_unresponsive'; message = "split capability launch: supervisor alive but unresponsive ($rc2); failing closed (no per-call fallback -> no split-brain)" }
                    }
                    $warnings.Add("split: no live supervisor for the capability launch ($rc2); falling back to the per-call managed launch")
                    Write-Diag "split launch: supervisor fallback ($rc2)"
                }
            }
            if (-not $splitSupLaunched) {
                # per-call managed launch (the existing path below); re-take the pool lock for the manifest writes
                if ($poolMode -and $script:PoolCoreLoaded -and $null -eq $poolLock) {
                    $poolLock = Enter-PoolLock -LockPath $lockPath -TimeoutMs 15000
                    if (-not $poolLock.acquired) { $warnings.Add('split: pool lock not re-acquired for the launch; proceeding unserialized'); $poolLock = $null }
                }
            }
        }

        Write-Diag "server: reuse=$warmReused warm=$warmOn port=$usePort model=$($m.model_id) ngl=$ngl ctx=$ctx"
        $loadStart = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            if ($splitSupLaunched) {
                # i21 split: the server was started by the DURABLE SUPERVISOR under the transition capability;
                # adopt its result (health/socket-owner/publish ran inside the supervisor).
                $loadStart.Stop()
                if ($null -eq $healthMs) { $healthMs = [int]$loadStart.Elapsed.TotalMilliseconds }
                if (-not $healthOk) { throw [PSCustomObject]@{ code = 'health_timeout'; message = "supervisor-launched server did not become healthy (split capability launch)"; retryable = $true } }
            }
            elseif (-not $warmReused) {
                # start a fresh server. Cross-platform launch; a .ps1 engine_path is run under pwsh (mock/test seam).
                if ($enginePath -match '\.ps1$') {
                    $spFile = (Get-PwshExe)
                    $spArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $enginePath) + $srvArgs
                } else {
                    $spFile = $enginePath; $spArgs = $srvArgs
                }
                # Launch the server. A WARM server on Windows MUST escape the executor task's Job object, or
                # the resident is killed when the launching task completes (verified: the pid died before the
                # next task, so warmth never survived across separate gateway invocations). A Start-Process
                # child stays in the caller's Job; Win32_Process.Create parents the server to WmiPrvSE (OUTSIDE
                # the Job) so it OUTLIVES the job -- while staying PID-tracked and killable by -EvictWarm / the
                # model-change evict / the executor's orphan-name sweep. Non-warm and the off-machine/Linux path
                # keep the redirected Start-Process: their server is killed before the call returns (or has no
                # Job-kill), so nothing leaks. (CIM Win32_Process is Windows-only, hence the $IsWindows guard.)
                $useWmiLaunch = ($warmOn -and $IsWindows)
                if ($useWmiLaunch) {
                    $cmdLine = ((@($spFile) + $spArgs) | ForEach-Object { $s = "$_"; if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s } }) -join ' '
                    $wmi = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
                    $wrc = if ($null -ne $wmi) { [int]$wmi.ReturnValue } else { -1 }
                    $wpid = if ($null -ne $wmi -and $null -ne $wmi.ProcessId) { [int]$wmi.ProcessId } else { 0 }
                    if ($wrc -ne 0 -or $wpid -le 0) { throw [PSCustomObject]@{ code = 'server_start_failed'; message = "Win32_Process.Create failed (rc=$wrc pid=$wpid)"; retryable = $true } }
                    $serverPid = $wpid
                } else {
                    $spSplat = @{ FilePath = $spFile; ArgumentList = $spArgs; PassThru = $true; RedirectStandardOutput = $srvLog; RedirectStandardError = $srvErr }
                    if ($IsWindows) { $spSplat['WindowStyle'] = 'Hidden' }
                    $sp = Start-Process @spSplat
                    $serverPid = [int]$sp.Id
                }
                $warmStartedNew = $true
                # finding 4: per-launch verified-generation identity -- a fresh nonce + this pid + creation-time.
                # (i21 split: the generation + per-tree resident_instance_id were PRE-MINTED and stamped into the
                #  transition capability, so the res.lease identity and the manifest identity agree.)
                $instanceGen = if ($splitOn) { $splitNewGen } elseif ($script:PoolCoreLoaded) { New-InstanceGeneration } else { [Guid]::NewGuid().ToString('N') }
                # start-ticks (identity): re-read the pid -- WMI returns no process handle, and Start-Process
                # StartTime is re-readable too; a REUSED pid would differ by seconds, so this still rejects impostors.
                $startTicks = 0
                try { $startTicks = [long]((Get-Process -Id $serverPid -ErrorAction Stop).StartTime.Ticks) } catch { try { if ($null -ne $sp) { $startTicks = [long]$sp.StartTime.Ticks } } catch { } }
                if ($warmOn) {
                    $nowUtc = ([DateTime]::UtcNow).ToString('o')
                    if ([string]::IsNullOrWhiteSpace($residentSinceUtc)) { $residentSinceUtc = $nowUtc }
                    # finding 3: publish state=STARTING IMMEDIATELY (crash-atomic) so a mid-load crash leaves a
                    # tracked, reconcilable claim. finding 6: resident_config_hash (deterministic) is split from
                    # instance_generation (fencing nonce). finding 5: a managed tag marks this as OUR server so the
                    # orphan sweep counts only UNMANAGED llama-server (and never the intended warm resident).
                    $manifest = [ordered]@{
                        schema = 'lifeorch.model_gateway.warm/0.3'; state = 'STARTING'
                        pid = $serverPid; start_ticks = $startTicks; instance_generation = $instanceGen
                        resident_instance_id = $(if ($splitOn) { $splitNewInstId } else { 'ri' + [Guid]::NewGuid().ToString('N') })
                        host = '127.0.0.1'; port = $usePort; model_id = $m.model_id; model_path = $modelPath
                        engine_path = $enginePath; engine_exe_hash = $engineExeHash; ngl = $ngl; ctx = $ctx
                        resident_config = $residencyKey; resident_config_hash = $residencyKeySha; residency_key_sha = $residencyKeySha
                        cache_type_k = $ctkUse; cache_type_v = $ctvUse; flash_attn = $flashUse; parallel = $npUse
                        no_think = $noThink; registry_config_version = $(if (Has $reg 'registry_config_version') { [int]$reg.registry_config_version } else { 0 })
                        keep_resident_seconds = $KeepResidentSeconds; swap_count = $swapCount
                        started_at_utc = $nowUtc; resident_since_utc = $residentSinceUtc; last_used_utc = $nowUtc
                        holder = $glHolder; managed_by = 'model.gateway'; manager_holder = $glHolder
                        socket_owner_verified = $null
                        fence = $(if ($myFence -ge 0) { $myFence } else { 0 }); fence_holder = $glHolder; fence_ttl_seconds = $FenceTtlSeconds
                        fence_acquired_utc = $nowUtc; fence_renewed_utc = $nowUtc; fence_expires_utc = ([DateTime]::UtcNow).AddSeconds($FenceTtlSeconds).ToString('o')
                    }
                    [void](Write-WarmServer $warmRegPath $manifest)
                }
                $deadline = (Get-Date).AddSeconds($LoadTimeoutSec)
                while ((Get-Date) -lt $deadline) {
                    $procGone = if ($null -ne $sp) { $sp.HasExited } else { ($null -eq (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) }
                    if ($procGone) { throw [PSCustomObject]@{ code = 'server_start_failed'; message = 'llama-server exited during load; see server logs'; retryable = $true } }
                    if (Test-ServerHealthy '127.0.0.1' $usePort) { $healthOk = $true; break }
                    Start-Sleep -Milliseconds 500
                }
                $loadStart.Stop(); $healthMs = [int]$loadStart.Elapsed.TotalMilliseconds
                if (-not $healthOk) { throw [PSCustomObject]@{ code = 'health_timeout'; message = "llama-server did not become healthy within $LoadTimeoutSec s"; retryable = $true } }
                # finding 4: VERIFY the listening socket owner BEFORE publishing RESIDENT -- a fixed port + /health
                # (or a /v1/models alias) can validate the WRONG generation. An explicit owner mismatch is a HARD,
                # non-bypassable failure; an undeterminable owner (off-Windows) is advisory (publish proceeds).
                if ($poolMode -and $script:PoolCoreLoaded) {
                    $socketOwnerVerified = Test-SocketOwner -Port $usePort -ExpectedPid $serverPid -SocketOwnerProbe $script:SocketOwnerProbe
                    if ($socketOwnerVerified -eq $false) {
                        throw [PSCustomObject]@{ code = 'socket_owner_mismatch'; message = "listening socket on port $usePort is not owned by the launched pid $serverPid; refusing to publish (wrong-generation guard)"; retryable = $true }
                    }
                }
                # Stage-1: confirm the resident actually loaded a model (provenance). Soft -- /health + socket owner are the hard gates.
                if ($poolMode) {
                    $poolProvenance = Confirm-ResidentProvenance '127.0.0.1' $usePort 5
                    if (-not $poolProvenance.ok) { $warnings.Add('pool: model provenance not confirmed via /v1/models or /props (health OK)') }
                    else { Write-Diag "pool provenance ok source=$($poolProvenance.source) reported=$([string]::Join(',', @($poolProvenance.reported)))" }
                }
                # finding 3: transition STARTING -> RESIDENT via a fence-gated CAS (the manifest becomes a verified claim).
                if ($warmOn -and $script:PoolCoreLoaded) {
                    $casOk = Set-ManifestCas -Path $warmRegPath -Fence $(if ($myFence -ge 0) { $myFence } else { 0 }) -Updates @{ state = 'RESIDENT'; socket_owner_verified = $socketOwnerVerified }
                    if (-not $casOk) { $warnings.Add('pool: RESIDENT publish CAS failed (fence superseded); a contender took the residency') }
                }
                # residency mutation complete -> release the machine-global pool lock BEFORE generation (never held over I/O)
                if ($null -ne $poolLock) { Exit-PoolLock $poolLock; $poolLock = $null }
            } else {
                # warm reuse: no model load; health already confirmed above
                $loadStart.Stop(); $healthOk = $true; $healthMs = [int]$loadStart.Elapsed.TotalMilliseconds
                # residency check complete on the reuse path -> release the machine-global pool lock before generation
                if ($null -ne $poolLock) { Exit-PoolLock $poolLock; $poolLock = $null }
            }

            # finding 1: a caller that expects a specific resident passes its instance_generation / fence; if the
            # LIVE resident does not match, REJECT before any completion is issued (no wrong-generation call lands).
            if ($poolMode -and $script:PoolCoreLoaded -and (-not [string]::IsNullOrWhiteSpace($ExpectGeneration) -or $ExpectFence -ge 0)) {
                $liveReg = Read-WarmServer $warmRegPath
                $gm = Test-GenerationMatch $liveReg $ExpectGeneration $ExpectFence
                if (-not $gm.match) {
                    throw [PSCustomObject]@{ code = 'generation_mismatch'; message = "expected resident generation/fence not current (reason=$($gm.reason); resident_generation=$($gm.resident_generation) resident_fence=$($gm.resident_fence)); call rejected"; retryable = $true }
                }
            }

            # ============ i21 SPLIT: phase-2 COMMIT (after health) + the FULL v0.4 authority tuple ============
            if ($splitOn) {
                $rlPath3 = Resolve-ResLeasePath
                if (-not [string]::IsNullOrWhiteSpace([string]$splitState.pending_txn_id)) {
                    # '-Action commit -HealthOk': publish the started resident + issue the FIRST usable exec lease
                    # ONLY now that health passed (STARTING -> HEALTHY_UNPUBLISHED -> COMMITTED; no grant-before-ready).
                    $cm = Invoke-ResLeaseJson -LeaseInputs @{ action='commit'; resource='gpu'; holder="$glHolder!sched"; owner_id=$glHolder
                                                              ttl_seconds=$SplitExecTtlSeconds; transition_id=[string]$splitState.pending_txn_id
                                                              resident_instance_id=$splitNewInstId; health_ok=$true
                                                              health_receipt=("health200 pid=$serverPid port=$usePort gen=$instanceGen")
                                                              request_id=("split-" + $InvocationId) } -RlPath $rlPath3 -PwshExe (Get-PwshExe)
                    $cmOk = ($null -ne $cm -and [bool]$cm.committed)
                    $splitState.commit = [ordered]@{
                        committed = $cmOk
                        reason = $(if ($null -ne $cm -and (Has $cm 'reason')) { [string]$cm.reason } else { 'invoke_failed' })
                        exec_lease_id = $(if ($null -ne $cm -and (Has $cm 'exec_lease_id')) { $cm.exec_lease_id } else { $null })
                        gpu_authority_epoch = $(if ($null -ne $cm -and (Has $cm 'gpu_authority_epoch')) { $cm.gpu_authority_epoch } else { $null })
                        transition_state = $(if ($null -ne $cm -and (Has $cm 'transition_state')) { [string]$cm.transition_state } else { $null })
                    }
                    if (-not $cmOk) {
                        throw [PSCustomObject]@{ code = 'gpu_split_commit_failed'; message = "phase-2 commit did not publish (reason=$($splitState.commit.reason)); the tentative instance is dropped fail-closed"; retryable = $true }
                    }
                    $splitState.pending_txn_id = $null
                    $splitState.swap_committed = $true
                    $splitState.active = [ordered]@{
                        holder = "$glHolder!sched"; owner_id = $glHolder; owner_incarnation_id = $splitInc
                        gpu_authority_epoch = $splitState.commit.gpu_authority_epoch
                        resident_generation = $instanceGen; resident_instance_id = $splitNewInstId
                        exec_lease_id = $splitState.commit.exec_lease_id
                    }
                    Write-Diag "split commit: COMMITTED epoch=$($splitState.active.gpu_authority_epoch) exec_lease=$($splitState.active.exec_lease_id) inst=$splitNewInstId"
                } else {
                    # same-model REUSE: a plain short exec acquire (re-attaches to our residency pin ~instantly)
                    # supplies the exec_lease_id leg of the tuple; the pin itself stays resident between calls.
                    $liveReg2 = Read-WarmServer $warmRegPath
                    $curGen  = if ($null -ne $liveReg2 -and (Has $liveReg2 'instance_generation'))  { [string]$liveReg2.instance_generation } else { $instanceGen }
                    $curInst = if ($null -ne $liveReg2 -and (Has $liveReg2 'resident_instance_id')) { [string]$liveReg2.resident_instance_id } else { $null }
                    $exIn = @{ action='acquire'; resource='gpu'; holder=$glHolder; kind='exec'; priority=$splitPrio
                               ttl_seconds=$SplitExecTtlSeconds; owner_id=$glHolder; owner_incarnation_id=$splitInc }
                    if (-not [string]::IsNullOrWhiteSpace($curGen))  { $exIn['resident_generation']  = $curGen }
                    if (-not [string]::IsNullOrWhiteSpace($curInst)) { $exIn['resident_instance_id'] = $curInst }
                    $exAcq = Invoke-ResLeaseJson -LeaseInputs $exIn -RlPath $rlPath3 -PwshExe (Get-PwshExe)
                    if ($null -eq $exAcq -or -not [bool]$exAcq.acquired) {
                        $hb = if ($null -ne $exAcq -and (Has $exAcq 'held_by')) { [string]$exAcq.held_by } else { '<unknown>' }
                        throw [PSCustomObject]@{ code = 'gpu_split_contended'; message = "split exec re-attach did not acquire (held_by=$hb); cannot serve without exec authority"; retryable = $true }
                    }
                    $splitState.active = [ordered]@{
                        holder = $glHolder; owner_id = $glHolder; owner_incarnation_id = $splitInc
                        gpu_authority_epoch = $(if (Has $exAcq 'gpu_authority_epoch') { $exAcq.gpu_authority_epoch } else { $null })
                        resident_generation = $curGen; resident_instance_id = $curInst
                        exec_lease_id = [string]$exAcq.lease_id
                    }
                }
                # ---- the PRE-GENERATION gate: Test-GenerationMatch EXTENDED with the res.lease authority check --
                #      a generation/epoch/incarnation/instance mismatch is rejected BEFORE any completion. ----
                $gateReg = Read-WarmServer $warmRegPath
                $gm2 = Test-GenerationMatch $gateReg ([string]$splitState.active.resident_generation) -1
                if (-not $gm2.match) {
                    throw [PSCustomObject]@{ code = 'generation_mismatch'; message = "split pre-generation gate: manifest generation mismatch (reason=$($gm2.reason) resident=$($gm2.resident_generation) expected=$($splitState.active.resident_generation)); call rejected"; retryable = $true }
                }
                $chkIn = @{ action='check'; resource='gpu'; owner_id=$glHolder; owner_incarnation_id=$splitInc }
                if ($null -ne $splitState.active.gpu_authority_epoch) { $chkIn['authority_epoch'] = [long]$splitState.active.gpu_authority_epoch }
                if (-not [string]::IsNullOrWhiteSpace([string]$splitState.active.resident_generation)) { $chkIn['resident_generation'] = [string]$splitState.active.resident_generation }
                if (-not [string]::IsNullOrWhiteSpace([string]$splitState.active.resident_instance_id)) { $chkIn['resident_instance_id'] = [string]$splitState.active.resident_instance_id }
                $preChk = Invoke-ResLeaseJson -LeaseInputs $chkIn -RlPath $rlPath3 -PwshExe (Get-PwshExe)
                $preOk = ($null -ne $preChk -and (Has $preChk 'authority_ok') -and [bool]$preChk.authority_ok)
                if (-not $preOk) {
                    $fr = if ($null -ne $preChk -and (Has $preChk 'fence_status')) { [string]$preChk.fence_status } else { 'check_failed' }
                    throw [PSCustomObject]@{ code = 'authority_mismatch'; message = "split pre-generation gate: res.lease authority_ok=false (fence_status=$fr); the full tuple (owner+incarnation+epoch+generation+instance+exec) is not current; call rejected BEFORE any completion"; retryable = $true }
                }
                Write-Diag "split authority gate OK: epoch=$($splitState.active.gpu_authority_epoch) gen=$($splitState.active.resident_generation) inst=$($splitState.active.resident_instance_id) exec=$($splitState.active.exec_lease_id)"
            }

            if ($doEnsure) {
                # -EnsureResident: the requested model is resident + provenance-confirmed under the held gpu lease.
                # RETURN without generating (the governor's Ensure-ResidentModel(model_id, config_key)).
                Write-Diag "ensure_resident: action=$residencyAction model=$($m.model_id) key=$($residencyKeySha.Substring(0,12)) load_ms=$healthMs reused=$warmReused evicted=$warmEvicted gen=$instanceGen"
            } else {
                # finding 12: same-model PREFIX REUSE is DROPPED from the correctness path (cross-task KV-bleed risk).
                # The non-bypassable "no cross-task KV" invariant is enforced by ERASE-ON-CHECKOUT: in pool mode the
                # single slot (-np 1) is erased immediately before generation, so no prior task's KV can be reused.
                if ($poolMode) {
                    try { Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/slots/0?action=erase" -Method Post -TimeoutSec 10 | Out-Null; Write-Diag 'kv isolation: erased slot 0 on checkout (no cross-task prefix reuse)' }
                    catch { $warnings.Add('kv_isolation: slot erase-on-checkout not confirmed (non-fatal; server may lack /slots)') }
                }
                $bodyObj = [ordered]@{ model = $m.model_id; messages = $msgArr; max_tokens = $MaxTokens; temperature = $Temperature; top_p = $TopP; top_k = $TopK; seed = $Seed }
                if ($stopArr.Count -gt 0) { $bodyObj.stop = $stopArr }
                if ($Logprobs) { $bodyObj.logprobs = $true; $bodyObj.top_logprobs = $TopLogprobs }   # opt-in (Stage-2); off -> body unchanged
                $body = $bodyObj | ConvertTo-Json -Depth 8
                $genSw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec ([Math]::Max(30, $LoadTimeoutSec))
                } catch {
                    throw [PSCustomObject]@{ code = 'completion_failed'; message = "chat completion request failed: $($_.Exception.Message)"; retryable = $true }
                }
                $genSw.Stop()
                # finding 12: erase-on-check-in as well -> the slot never carries this task's KV to the next task
                if ($poolMode) { try { Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/slots/0?action=erase" -Method Post -TimeoutSec 10 | Out-Null } catch { } }

                # ---- i21 SPLIT: the POST-GENERATION discard gate. Re-assert the FULL tuple AFTER the completion
                #      returned; a stale-epoch/instance actor's authority_ok is FALSE and the in-flight result is
                #      DISCARDED (never surfaced, never published) -- live adversarial tests A/B ride this gate. ----
                if ($splitOn) {
                    $rlPath4 = Resolve-ResLeasePath
                    $chkIn2 = @{ action='check'; resource='gpu'; owner_id=$glHolder; owner_incarnation_id=$splitInc }
                    if ($null -ne $splitState.active.gpu_authority_epoch) { $chkIn2['authority_epoch'] = [long]$splitState.active.gpu_authority_epoch }
                    if (-not [string]::IsNullOrWhiteSpace([string]$splitState.active.resident_generation)) { $chkIn2['resident_generation'] = [string]$splitState.active.resident_generation }
                    if (-not [string]::IsNullOrWhiteSpace([string]$splitState.active.resident_instance_id)) { $chkIn2['resident_instance_id'] = [string]$splitState.active.resident_instance_id }
                    $postChk = Invoke-ResLeaseJson -LeaseInputs $chkIn2 -RlPath $rlPath4 -PwshExe (Get-PwshExe)
                    $postOk = ($null -ne $postChk -and (Has $postChk 'authority_ok') -and [bool]$postChk.authority_ok)
                    $splitState.discard_check = [ordered]@{
                        authority_ok = $postOk
                        fence_status = $(if ($null -ne $postChk -and (Has $postChk 'fence_status')) { [string]$postChk.fence_status } else { $null })
                        checked_epoch = $splitState.active.gpu_authority_epoch
                        checked_instance = $splitState.active.resident_instance_id
                    }
                    if (-not $postOk) {
                        # evidence for the report: the fenced result also cannot pass the target-fenced side-effect
                        # gate (fence-op op_kind=result_publish naming OUR captured instance is refused when stale).
                        $fev = Invoke-ResLeaseJson -LeaseInputs @{ action='fence-op'; resource='gpu'; op_kind='result_publish'; resident_instance_id=[string]$splitState.active.resident_instance_id } -RlPath $rlPath4 -PwshExe (Get-PwshExe)
                        $fevOk = ($null -ne $fev -and (Has $fev 'fenced_op_ok') -and [bool]$fev.fenced_op_ok)
                        $fevReason = if ($null -ne $fev -and (Has $fev 'reason')) { [string]$fev.reason } else { 'unknown' }
                        $splitState.discard_check['fence_op_result_publish'] = [ordered]@{ fenced_op_ok = $fevOk; reason = $fevReason }
                        $resp = $null   # DISCARD: the completion text is never surfaced/published
                        throw [PSCustomObject]@{ code = 'stale_result_discarded'; message = "split post-generation gate: authority_ok=false (fence_status=$($splitState.discard_check.fence_status)) AND fence-op result_publish refused (reason=$fevReason target=$($splitState.active.resident_instance_id)); the in-flight completion was DISCARDED"; retryable = $true }
                    }
                }
            }

            # ---- i21 SPLIT: return to steady state -- release the scheduler exec lease and re-take the
            #      revocable residency PIN under the stable holder (held BETWEEN calls; the split's whole point). ----
            if ($splitOn -and $splitState.swap_committed) {
                $rlPath5 = Resolve-ResLeasePath
                $relEx = Invoke-ResLeaseJson -LeaseInputs @{ action='release'; resource='gpu'; holder="$glHolder!sched"; lease_id=[string]$splitState.active.exec_lease_id } -RlPath $rlPath5 -PwshExe (Get-PwshExe)
                $splitState.exec_released = ($null -ne $relEx -and [bool]$relEx.released)
                $rp = Invoke-ResLeaseJson -LeaseInputs @{ action='acquire'; resource='gpu'; holder=$glHolder; kind='residency_pin'; priority=$splitPrio
                                                          ttl_seconds=$SplitPinTtlSeconds; owner_id=$glHolder; owner_incarnation_id=$splitInc
                                                          resident_generation=$instanceGen; resident_instance_id=$splitNewInstId
                                                          note='model.gateway split residency pin (post-swap)' } -RlPath $rlPath5 -PwshExe (Get-PwshExe)
                if ($null -ne $rp -and [bool]$rp.acquired) {
                    $splitState.repinned = $true
                    $leaseState.acquired = $true; $leaseState.lease_id = [string]$rp.lease_id; $leaseState.owned = $false
                    $splitState.pin = [ordered]@{
                        lease_id = [string]$rp.lease_id; already_held = [bool]$rp.already_held
                        gpu_authority_epoch = $(if (Has $rp 'gpu_authority_epoch') { $rp.gpu_authority_epoch } else { $null })
                        resident_generation = $instanceGen; resident_instance_id = $splitNewInstId
                        priority = $splitPrio; ttl_seconds = $SplitPinTtlSeconds
                    }
                    Write-Diag "split re-pin: pin=$($rp.lease_id) exec_released=$($splitState.exec_released) gen=$instanceGen inst=$splitNewInstId"
                } else {
                    $splitState.repinned = $false
                    $warnings.Add('split: post-swap re-pin did not acquire; the resident is unpinned until the next call re-pins (revocation window)')
                }
            }
        }
        finally {
            # teardown: WARM leaves the server resident (registry persists) so the NEXT call reuses it;
            # NON-WARM kills the per-call server (unchanged). A freshly-started warm server that FAILED
            # to load is torn down + de-registered so no dead resident is left behind.
            $killServer = $false
            if (-not $warmOn) { $killServer = ($serverPid -gt 0) }
            elseif ($warmStartedNew -and -not $healthOk) {
                # i21 split: a SUPERVISOR-launched tentative server is torn down by the supervisor (targeted evict
                # in the split cleanup below), never by a gateway-side PID kill (the D-0055/56 re-wedge rule).
                if (-not $splitSupLaunched) { $killServer = ($serverPid -gt 0); Clear-WarmServer $warmRegPath }
            }
            if ($killServer -and $serverPid -gt 0) {
                # kill by PID with /T = the whole child TREE (finding 5: never kill by a bare PID). This reaps
                # llama.cpp's children (per-call ownership). The DURABLE Job-Object owner across invocations is now
                # the persistent supervisor (Start-GatewaySupervisor.ps1 + lib/Supervisor.psm1; use -UseSupervisor).
                try { & taskkill /PID $serverPid /T /F 2>$null | Out-Null } catch { }
                try { $pp = Get-Process -Id $serverPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
            }
            # safety: release the machine-global pool lock if any path (e.g. a mid-publish throw) left it held
            if ($null -ne $poolLock) { try { Exit-PoolLock $poolLock } catch { }; $poolLock = $null }
        }
    }
    finally {
        # ---- i21 SPLIT crash-path cleanup (fail-closed; runs BEFORE the classic release below) ----
        if ($splitOn -and $null -ne $splitState) {
            try {
                $rlPathF = Resolve-ResLeasePath
                if (-not [string]::IsNullOrWhiteSpace([string]$splitState.pending_txn_id)) {
                    # an UNCOMMITTED capability (launch/health failed or a throw before phase-2): '-Action commit
                    # -HealthFailed' terminates the exact tentative instance's capability and grants NOTHING --
                    # the GPU is left EMPTY (the old resident is NOT silently restored; that is a NEW acquisition).
                    $hf = Invoke-ResLeaseJson -LeaseInputs @{ action='commit'; resource='gpu'; holder="$glHolder!sched"; owner_id=$glHolder
                                                              transition_id=[string]$splitState.pending_txn_id
                                                              resident_instance_id=$splitNewInstId; health_failed=$true
                                                              request_id=("split-" + $InvocationId) } -RlPath $rlPathF -PwshExe (Get-PwshExe)
                    $hfReason = if ($null -ne $hf -and (Has $hf 'reason')) { [string]$hf.reason } else { 'invoke_failed' }
                    $splitState.commit = [ordered]@{ committed = $false; reason = $hfReason; health_failed_sent = $true }
                    $warnings.Add("split: uncommitted capability closed with -HealthFailed (reason=$hfReason); GPU left empty, fail-closed")
                    Write-Diag "split cleanup: commit -HealthFailed sent (reason=$hfReason)"
                    if ($splitSupLaunched -and $serverPid -gt 0) {
                        # tear down the supervisor-launched tentative tree via a TARGETED supervisor evict
                        $tev = Invoke-SupervisorClient -Op 'evict' -Params @{ target_resident_instance_id = $splitNewInstId } -SupRoot $SupervisorRoot -WarmReg $warmRegPath -TimeoutMs 30000
                        $tOk = ($null -ne $tev -and [bool]$tev.ok)
                        Write-Diag "split cleanup: targeted supervisor evict of tentative inst=$splitNewInstId ok=$tOk"
                        if (-not $tOk) { $warnings.Add('split: targeted supervisor evict of the tentative instance did not confirm; verify 0 orphans out-of-band') }
                    }
                    $splitState.pending_txn_id = $null
                }
                elseif ($splitState.swap_committed -and ($null -eq $splitState.repinned)) {
                    # committed but a throw landed before the re-pin: release the scheduler exec lease so the
                    # resource is not wedged under the sched sub-identity (the next call re-pins).
                    $relF = Invoke-ResLeaseJson -LeaseInputs @{ action='release'; resource='gpu'; holder="$glHolder!sched" } -RlPath $rlPathF -PwshExe (Get-PwshExe)
                    $splitState.exec_released = ($null -ne $relF -and [bool]$relF.released)
                    Write-Diag "split cleanup: sched exec lease release=$($splitState.exec_released)"
                }
            } catch { Write-Diag "split cleanup error: $($_.Exception.Message)" }
            $leaseState['split'] = $splitState   # additive: present ONLY when the split is engaged
        }
        # release the gpu lease AFTER the server is fully torn down (only a lease we freshly acquired)
        if ($leaseState.owned -and -not [string]::IsNullOrWhiteSpace([string]$leaseState.lease_id) -and $leaseState.available) {
            $rel = Invoke-GpuLeaseAction -LeaseAction 'release' -Resource 'gpu' -Holder $glHolder -LeaseIdArg ([string]$leaseState.lease_id) -LeaseDirArg $LeaseDir -RlPath (Resolve-ResLeasePath) -PwshExe (Get-PwshExe)
            if ($null -ne $rel -and [bool]$rel.released) {
                $leaseState.released = $true
                Write-Diag "gpu lease released lease_id=$($leaseState.lease_id)"
            } else {
                $leaseState.released = $false
                $rr = if ($null -ne $rel) { [string]$rel.reason } else { 'invoke_failed' }
                $warnings.Add("gpu lease: release unconfirmed (reason=$rr)")
                Write-Diag "gpu lease release unconfirmed reason=$rr"
            }
        }
    }

    if ($doEnsure) {
        # ---- POOL residency result (Stage-1 Ensure-ResidentModel): no generation, confidence stays null ----
        $result = [ordered]@{
            model = $m.model_id; engine = 'llama-server'; mode = 'ensure_resident'; selected_from = $selectedFrom
            pool = [ordered]@{
                action = $residencyAction; reused = $warmReused; started_new = $warmStartedNew; evicted = $warmEvicted; evict_confirmed = $evictConfirmed
                residency_key = $residencyKey; residency_key_sha = $residencyKeySha; resident_config_hash = $residencyKeySha
                instance_generation = $instanceGen; fence = $(if ($myFence -ge 0) { $myFence } else { $null }); fence_ttl_seconds = $FenceTtlSeconds
                can_serve = $(if ($null -ne $canServeInfo) { $canServeInfo.can_serve } else { $null }); can_serve_mismatches = $(if ($null -ne $canServeInfo) { $canServeInfo.mismatches } else { @() })
                socket_owner_verified = $socketOwnerVerified; engine_exe_hash = $engineExeHash
                swap_count = $swapCount; keep_resident_seconds = $KeepResidentSeconds
                idle_ms_at_entry = $idleMsAtEntry; resident_since_utc = $residentSinceUtc
                load_ms = $healthMs; health_ok = $healthOk; provenance = $poolProvenance
                vram = [ordered]@{ free_mib_before = $vramBefore; free_mib_after = $vramAfter; recovered_mib = $vramRecovered }
            }
            server = [ordered]@{ port = $usePort; health_ms = $healthMs; gpu_layers = $ngl; context = $ctx; gpu_lease = $leaseState
                warm = [ordered]@{ enabled = $warmOn; reused = $warmReused; started_new = $warmStartedNew; evicted = $warmEvicted; load_ms = $healthMs; registry_path = $warmRegPath } }
        }
        $modelProvenance = @(
            [ordered]@{
                model_id = $m.model_id; engine = 'llama-server'
                engine_build = $(if (Has $reg 'engine_build') { [string]$reg.engine_build } else { $null })
                device = 'cuda:0'
                params = [ordered]@{ gpu_layers = $ngl; context = $ctx; cache_type_k = $ctkUse; cache_type_v = $ctvUse; flash_attn = $flashUse; parallel = $npUse }
                residency_key_sha = $residencyKeySha; runtime_ms = $healthMs
            }
        )
        Write-Diag "ensure_resident done: action=$residencyAction reused=$warmReused evicted=$warmEvicted load_ms=$healthMs swaps=$swapCount"
    }
    else {
    # ---- parse response ----
    $content = ''; $finish = 'unknown'; $usage = $null; $timings = $null; $lpBlock = $null
    if ($null -ne $resp -and (Has $resp 'choices')) {
        $ch = @($resp.choices)
        if ($ch.Count -gt 0) {
            $c0 = $ch[0]
            if ((Has $c0 'message') -and (Has $c0.message 'content')) { $content = [string]$c0.message.content }
            if (Has $c0 'finish_reason') { $finish = [string]$c0.finish_reason }
            # ---- opt-in per-token logprobs -> decision-token entropy (Stage-2). OpenAI schema: choices[0].logprobs.content[] ----
            if ($Logprobs -and (Has $c0 'logprobs') -and $null -ne $c0.logprobs -and (Has $c0.logprobs 'content') -and $null -ne $c0.logprobs.content) {
                $lpContent = @($c0.logprobs.content)
                if ($lpContent.Count -gt 0) {
                    $ents = New-Object System.Collections.Generic.List[double]; $firstEnt = $null; $decEnt = $null
                    foreach ($tk in $lpContent) {
                        $tl = if (Has $tk 'top_logprobs') { @($tk.top_logprobs) } else { @() }
                        $e = Get-TokenEntropy $tl
                        if ($null -ne $e) {
                            $ents.Add($e)
                            if ($null -eq $firstEnt) { $firstEnt = $e }
                            if ($null -eq $decEnt) {
                                $ts = if (Has $tk 'token') { [string]$tk.token } else { '' }
                                if (-not [string]::IsNullOrWhiteSpace($ts)) { $decEnt = $e }
                            }
                        }
                    }
                    $meanEnt = if ($ents.Count -gt 0) { [math]::Round((($ents | Measure-Object -Sum).Sum / $ents.Count), 4) } else { $null }
                    if ($null -eq $decEnt) { $decEnt = $firstEnt }
                    $lpBlock = [ordered]@{ available = $true; top_k = $TopLogprobs; token_count = $lpContent.Count; first_token_entropy = $firstEnt; mean_entropy = $meanEnt; decision_token_entropy = $decEnt }
                }
            }
        }
    }
    if ($Logprobs -and $null -eq $lpBlock) { $lpBlock = [ordered]@{ available = $false; top_k = $TopLogprobs; token_count = 0; first_token_entropy = $null; mean_entropy = $null; decision_token_entropy = $null } }
    if ((Has $resp 'usage')) { $usage = $resp.usage }
    if ((Has $resp 'timings')) { $timings = $resp.timings }

    # ---- confidence heuristic (generation completeness, NOT semantic correctness) ----
    if ([string]::IsNullOrWhiteSpace($content)) {
        $confidence = 0.1; $status = 'partial'; $warnings.Add('model returned empty content')
    } elseif ($finish -eq 'length') {
        $confidence = 0.4; $warnings.Add("output truncated at max_tokens=$MaxTokens (finish_reason=length)")
    } elseif ($finish -eq 'stop') {
        $confidence = 0.7
    } else {
        $confidence = 0.5; $warnings.Add("unrecognized finish_reason '$finish'")
    }

    $ptok = if ($null -ne $usage -and (Has $usage 'prompt_tokens')) { [int]$usage.prompt_tokens } else { $null }
    $ctok = if ($null -ne $usage -and (Has $usage 'completion_tokens')) { [int]$usage.completion_tokens } else { $null }
    $ttok = if ($null -ne $usage -and (Has $usage 'total_tokens')) { [int]$usage.total_tokens } else { $null }

    $result = [ordered]@{
        model = $m.model_id
        engine = 'llama-server'
        mode = 'chat'
        selected_from = $selectedFrom
        request = [ordered]@{ messages = $msgArr; max_tokens = $MaxTokens; temperature = $Temperature; top_p = $TopP; top_k = $TopK; seed = $Seed; stop = $stopArr }
        output = [ordered]@{ role = 'assistant'; text = $content }
        generation = [ordered]@{ finish_reason = $finish; prompt_tokens = $ptok; completion_tokens = $ctok; total_tokens = $ttok; timings = $timings }
        server = [ordered]@{ port = $usePort; health_ms = $healthMs; gpu_layers = $ngl; context = $ctx; gpu_lease = $leaseState
            warm = [ordered]@{ enabled = $warmOn; reused = $warmReused; started_new = $warmStartedNew; evicted = $warmEvicted; load_ms = $healthMs; registry_path = $warmRegPath } }
    }
    if ($null -ne $lpBlock) { $result.generation.logprobs = $lpBlock }   # only present when -Logprobs was requested (off -> byte-identical)
    # Stage-1.1 pool telemetry on a WARM generation only (off -> server.warm has no .pool key -> classic path byte-identical)
    if ($poolMode) {
        $result.server.warm.pool = [ordered]@{
            action = $residencyAction; residency_key_sha = $residencyKeySha; resident_config_hash = $residencyKeySha; swap_count = $swapCount
            instance_generation = $instanceGen; fence = $(if ($myFence -ge 0) { $myFence } else { $null }); fence_ttl_seconds = $FenceTtlSeconds
            can_serve = $(if ($null -ne $canServeInfo) { $canServeInfo.can_serve } else { $null }); socket_owner_verified = $socketOwnerVerified
            idle_ms_at_entry = $idleMsAtEntry; keep_resident_seconds = $KeepResidentSeconds
            prefix_reuse = 'disabled_stage_1_1'; kv_isolation = 'erase_on_checkout_and_checkin'   # finding 12
            cache_type_k = $ctkUse; cache_type_v = $ctvUse; flash_attn = $flashUse; parallel = $npUse; engine_exe_hash = $engineExeHash
            provenance = $poolProvenance
            vram = [ordered]@{ free_mib_before = $vramBefore; free_mib_after = $vramAfter; recovered_mib = $vramRecovered }
        }
    }

    $modelProvenance = @(
        [ordered]@{
            model_id = $m.model_id
            version = $(if (Has $m 'version') { [string]$m.version } elseif (Has $m 'quant') { [string]$m.quant } else { 'unknown' })
            family = $(if (Has $m 'family') { [string]$m.family } else { $null })
            format = $(if (Has $m 'format') { [string]$m.format } else { $null })
            engine = 'llama-server'
            engine_build = $(if (Has $reg 'engine_build') { [string]$reg.engine_build } else { $null })
            device = 'cuda:0'
            params = [ordered]@{ gpu_layers = $ngl; context = $ctx; max_tokens = $MaxTokens; temperature = $Temperature; top_p = $TopP; top_k = $TopK; seed = $Seed }
            prompt_tokens = $ptok; completion_tokens = $ctok; total_tokens = $ttok
            finish_reason = $finish
            timings = $timings
            runtime_ms = $healthMs
        }
    )
    Write-Diag "ok model=$($m.model_id) finish=$finish ctok=$ctok conf=$confidence"
    }  # end else (generation path, not ensure_resident)
    }  # end else (non-evict generation path)
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    }
    elseif ($_.Exception -and $_.Exception.Message -and ($_.Exception.Message -match '^\{.*"code".*\}$')) {
        $o = $_.Exception.Message | ConvertFrom-Json
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$o.code; message = [string]$o.message; retryable = [bool]$o.retryable }
    }
    else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) — $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    $artList = New-Object System.Collections.Generic.List[object]
    if ($null -ne $result -and ($result -is [System.Collections.IDictionary]) -and $result.Contains('output')) {
        $outPath = Join-Path $invDir 'output.txt'
        [System.IO.File]::WriteAllText($outPath, [string]$result.output.text, $utf8)
        $artList.Add([pscustomobject]@{ p = $outPath; k = 'text' })

        $exchange = [ordered]@{ schema = 'lifeorch.model_exchange/0.1'; invocation_id = $InvocationId; generated_at_utc = $startedAt.ToString('o'); request = $result.request; response = @{ model = $result.model; output = $result.output; generation = $result.generation; server = $result.server } }
        $exPath = Join-Path $invDir 'exchange.json'
        [System.IO.File]::WriteAllText($exPath, ($exchange | ConvertTo-Json -Depth 12), $utf8)
        $artList.Add([pscustomobject]@{ p = $exPath; k = 'json' })
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[model.gateway] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)

    foreach ($a in $artList.ToArray()) {
        $b = [System.IO.File]::ReadAllBytes($a.p)
        $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $a.p).Path; kind = $a.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
    }
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (low confidence / truncated) ----
try {
    if ($null -ne $confidence -and $confidence -lt $CONF_THRESHOLD -and $status -ne 'error') {
        $rqItem = [ordered]@{
            schema = 'lifeorch.review.item/0.1'
            id = "rq-$($InvocationId.Substring(0,8))"
            created_at_utc = ([DateTime]::UtcNow).ToString('o')
            flagged_by = $SKILL_ID
            reason = 'low_confidence'
            confidence = $confidence
            source_ref = "artifact://$invDir/exchange.json"
            weak_result = @{ model = $(if ($null -ne $result) { $result.model } else { $null }); finish_reason = $(if ($null -ne $result) { $result.generation.finish_reason } else { $null }); text_preview = $(if ($null -ne $result) { $s = [string]$result.output.text; if ($s.Length -gt 200) { $s.Substring(0,200) } else { $s } } else { $null }) }
            requested = 'review_generation_quality'
            status = 'open'
            resolution = $null
            escalated_to = $null
        }
        $rqLine = ($rqItem | ConvertTo-Json -Depth 8 -Compress)
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        [System.IO.File]::AppendAllText($rqPath, $rqLine + "`n", $utf8)
        $warnings.Add("flagged to review queue ($rqPath): confidence $confidence < $CONF_THRESHOLD")
        Write-Diag "review-queued: conf=$confidence -> $rqPath"
    }
} catch { Write-Diag "review-queue append failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result = $result; confidence = $confidence; artifacts = $artifacts; model_provenance = $modelProvenance
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
