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
    [int]$Generation = -1                # override the residency-key generation_id to FORCE a swap even when all else matches (-1 = registry/model value)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'model.gateway'; $SKILL_VERSION = '0.3.0'; $CONTRACT = '0.1'
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
# Best-effort GPU free VRAM (MiB) via nvidia-smi; $null when nvidia-smi is absent (off-machine / mock) -> non-fatal.
function Get-GpuFreeMib {
    try {
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
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- warm-server registry path + mode flags (Governor Phase 2 warm + Phase 3 Stage-1 pool manager) ----
    $warmRegPath = Get-WarmRegistryPath $WarmRegistryPath
    $doEvictWarm  = [bool]$EvictWarm
    $doPoolStatus = [bool]$PoolStatus
    $doSweepIdle  = [bool]$SweepIdle
    $doEnsure     = [bool]$EnsureResident
    if ($doEnsure) { $Warm = $true }   # a residency op MUST leave the server resident for the next call

    if ($doEvictWarm) {
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

    # ---- Stage-1 pool manager: resolve the residency-determining knobs + compute the EXPANDED residency key ----
    $noThink  = ((Has $m 'no_think') -and [bool]$m.no_think)
    $ctkUse   = $CacheTypeK; $ctvUse = $CacheTypeV
    $flashUse = [bool]$FlashAttn
    $npUse    = if ($Parallel -gt 0) { $Parallel } else { 1 }
    $poolMode = [bool]$Warm    # warm/pool launches get the pool server flags + prefix-reuse plumbing; OFF -> classic path unchanged
    $residencyKey    = Get-ResidencyKey $m $reg $ngl $ctx $noThink $ctkUse $ctvUse $flashUse $npUse $Generation
    $residencyKeySha = Get-ResidencyKeySha $residencyKey

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
    try {
        # -- acquire the gpu lease (graceful fallback: log + proceed if res.lease is absent; wait|proceed|require per the switch) --
        if ($glMode -ne 'off') {
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

        # ---- POOL MANAGER (Stage-1): reuse on EXACT residency-key match, else evict (confirm exit + VRAM) + reload ----
        $warmOn = [bool]$Warm
        $warmReused = $false; $warmStartedNew = $false; $warmEvicted = $false
        # pool telemetry (declared before the resident test so the cold-start path leaves them valid under StrictMode)
        $evictConfirmed = $null; $idleMsAtEntry = $null; $swapCount = 0; $residentSinceUtc = $null
        $vramBefore = $null; $vramAfter = $null; $vramRecovered = $null; $poolProvenance = $null
        $residencyAction = 'cold_start'
        $resident = Read-WarmServer $warmRegPath
        if ($null -ne $resident) {
            $rl = Get-WarmServerLiveness $resident
            $residentPort = if (Has $resident 'port') { [int]$resident.port } else { 0 }
            $idleMsAtEntry = Get-ResidentIdleMs $resident
            $prevSwaps = if (Has $resident 'swap_count') { [int]$resident.swap_count } else { 0 }
            # EXACT residency-key match (D-0063). Fall back to the legacy model_id+ngl+ctx test for a pre-Stage-1 manifest.
            $sameKey = $false
            if (Has $resident 'residency_key_sha') { $sameKey = ([string]$resident.residency_key_sha -eq $residencyKeySha) }
            elseif ((Has $resident 'model_id') -and ([string]$resident.model_id -eq [string]$m.model_id) -and (Has $resident 'ngl') -and ([int]$resident.ngl -eq $ngl) -and (Has $resident 'ctx') -and ([int]$resident.ctx -eq $ctx)) { $sameKey = $true }
            $healthy = $rl.alive -and (Test-ServerHealthy '127.0.0.1' $residentPort)
            if ($warmOn -and $healthy -and $sameKey) {
                # ~1 ms REUSE: refresh the keep-resident timer (last_used_utc) + carry the swap count; republish the manifest
                $usePort = $residentPort; $warmReused = $true; $residencyAction = 'reuse'; $swapCount = $prevSwaps
                $residentSinceUtc = if (Has $resident 'resident_since_utc') { [string]$resident.resident_since_utc } else { $null }
                $poolProvenance = [ordered]@{ ok = $true; source = 'reuse'; reported = @([string]$m.model_id) }
                try {
                    $obj = [ordered]@{}; foreach ($pp in $resident.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
                    $obj['last_used_utc'] = ([DateTime]::UtcNow).ToString('o')
                    [void](Write-WarmServer $warmRegPath $obj)
                } catch { }
                Write-Diag "pool reuse: pid=$($resident.pid) port=$usePort key=$($residencyKeySha.Substring(0,12)) idle_ms=$idleMsAtEntry"
            } else {
                # residency-key change / unhealthy / non-warm -> EVICT (confirm process exit + VRAM recovery) then reload
                if ($rl.alive) {
                    $vramBefore = Get-GpuFreeMib
                    if (Stop-ResidentServer $resident $rl) {
                        $warmEvicted = $true; $evictConfirmed = $true
                        Start-Sleep -Milliseconds 200; $vramAfter = Get-GpuFreeMib
                        if ($null -ne $vramBefore -and $null -ne $vramAfter) { $vramRecovered = ($vramAfter - $vramBefore) }
                        Write-Diag "pool evict: pid=$($resident.pid) sameKey=$sameKey healthy=$healthy warm=$warmOn vram_recovered_mib=$vramRecovered"
                    } else {
                        $evictConfirmed = $false
                        $warnings.Add("resident server pid=$($resident.pid) alive but unidentified; not killed (possible external process)")
                        Write-Diag 'resident unidentified; not killed'
                    }
                }
                if ($warmOn -and -not $sameKey) { $swapCount = $prevSwaps + 1 } else { $swapCount = $prevSwaps }
                $residencyAction = if ($warmOn) { 'evict_reload' } else { 'cold_start' }
                Clear-WarmServer $warmRegPath
                $resident = $null
            }
        }

        Write-Diag "server: reuse=$warmReused warm=$warmOn port=$usePort model=$($m.model_id) ngl=$ngl ctx=$ctx"
        $loadStart = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            if (-not $warmReused) {
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
                # start-ticks (identity): re-read the pid -- WMI returns no process handle, and Start-Process
                # StartTime is re-readable too; a REUSED pid would differ by seconds, so this still rejects impostors.
                $startTicks = 0
                try { $startTicks = [long]((Get-Process -Id $serverPid -ErrorAction Stop).StartTime.Ticks) } catch { try { if ($null -ne $sp) { $startTicks = [long]$sp.StartTime.Ticks } } catch { } }
                if ($warmOn) {
                    $nowUtc = ([DateTime]::UtcNow).ToString('o')
                    if ([string]::IsNullOrWhiteSpace($residentSinceUtc)) { $residentSinceUtc = $nowUtc }
                    # record the resident registry IMMEDIATELY (before the health wait) so a mid-load crash leaves a
                    # tracked pid the next call can identify + clean up. Stage-1 publishes the EXPANDED residency
                    # manifest (full key + sha + pool fields) so the NEXT call's reuse test is exact (D-0063).
                    [void](Write-WarmServer $warmRegPath ([ordered]@{
                        schema = 'lifeorch.model_gateway.warm/0.2'; pid = $serverPid; start_ticks = $startTicks
                        host = '127.0.0.1'; port = $usePort; model_id = $m.model_id; model_path = $modelPath
                        engine_path = $enginePath; ngl = $ngl; ctx = $ctx
                        residency_key = $residencyKey; residency_key_sha = $residencyKeySha
                        cache_type_k = $ctkUse; cache_type_v = $ctvUse; flash_attn = $flashUse; parallel = $npUse
                        no_think = $noThink; generation_id = $residencyKey.generation_id
                        keep_resident_seconds = $KeepResidentSeconds; swap_count = $swapCount
                        started_at_utc = $nowUtc; resident_since_utc = $residentSinceUtc; last_used_utc = $nowUtc
                        holder = $glHolder
                    }))
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
                # Stage-1: confirm the resident actually loaded a model (provenance). Soft -- /health is the hard gate.
                if ($poolMode) {
                    $poolProvenance = Confirm-ResidentProvenance '127.0.0.1' $usePort 5
                    if (-not $poolProvenance.ok) { $warnings.Add('pool: model provenance not confirmed via /v1/models or /props (health OK)') }
                    else { Write-Diag "pool provenance ok source=$($poolProvenance.source) reported=$([string]::Join(',', @($poolProvenance.reported)))" }
                }
            } else {
                # warm reuse: no model load; health already confirmed above
                $loadStart.Stop(); $healthOk = $true; $healthMs = [int]$loadStart.Elapsed.TotalMilliseconds
            }

            if ($doEnsure) {
                # -EnsureResident: the requested model is resident + provenance-confirmed under the held gpu lease.
                # RETURN without generating (the governor's Ensure-ResidentModel(model_id, config_key)).
                Write-Diag "ensure_resident: action=$residencyAction model=$($m.model_id) key=$($residencyKeySha.Substring(0,12)) load_ms=$healthMs reused=$warmReused evicted=$warmEvicted"
            } else {
                if ($poolMode -and $ClearSlot) {
                    # session boundary: erase the pinned prefix-cache slot so a new task does not reuse a stale prefix
                    try { Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/slots/${IdSlot}?action=erase" -Method Post -TimeoutSec 10 | Out-Null; Write-Diag "cleared prefix slot ${IdSlot} (session boundary)" }
                    catch { $warnings.Add('clear_slot: slot erase not confirmed (non-fatal)') }
                }
                $bodyObj = [ordered]@{ model = $m.model_id; messages = $msgArr; max_tokens = $MaxTokens; temperature = $Temperature; top_p = $TopP; top_k = $TopK; seed = $Seed }
                if ($stopArr.Count -gt 0) { $bodyObj.stop = $stopArr }
                if ($Logprobs) { $bodyObj.logprobs = $true; $bodyObj.top_logprobs = $TopLogprobs }   # opt-in (Stage-2); off -> body unchanged
                if ($poolMode) { $bodyObj.id_slot = $IdSlot }   # Stage-1 same-model prefix reuse: pin a single fixed slot (-np 1)
                $body = $bodyObj | ConvertTo-Json -Depth 8
                $genSw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec ([Math]::Max(30, $LoadTimeoutSec))
                } catch {
                    throw [PSCustomObject]@{ code = 'completion_failed'; message = "chat completion request failed: $($_.Exception.Message)"; retryable = $true }
                }
                $genSw.Stop()
            }
        }
        finally {
            # teardown: WARM leaves the server resident (registry persists) so the NEXT call reuses it;
            # NON-WARM kills the per-call server (unchanged). A freshly-started warm server that FAILED
            # to load is torn down + de-registered so no dead resident is left behind.
            $killServer = $false
            if (-not $warmOn) { $killServer = ($serverPid -gt 0) }
            elseif ($warmStartedNew -and -not $healthOk) { $killServer = ($serverPid -gt 0); Clear-WarmServer $warmRegPath }
            if ($killServer -and $serverPid -gt 0) {
                # kill by PID (works for both the $sp Start-Process and the detached WMI launch)
                try { & taskkill /PID $serverPid /T /F 2>$null | Out-Null } catch { }
                try { $pp = Get-Process -Id $serverPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
            }
        }
    }
    finally {
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
                residency_key = $residencyKey; residency_key_sha = $residencyKeySha
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
    # Stage-1 pool telemetry on a WARM generation only (off -> server.warm has no .pool key -> classic path byte-identical)
    if ($poolMode) {
        $result.server.warm.pool = [ordered]@{
            action = $residencyAction; residency_key_sha = $residencyKeySha; swap_count = $swapCount
            idle_ms_at_entry = $idleMsAtEntry; keep_resident_seconds = $KeepResidentSeconds; id_slot = $IdSlot
            cache_type_k = $ctkUse; cache_type_v = $ctvUse; flash_attn = $flashUse; parallel = $npUse
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
