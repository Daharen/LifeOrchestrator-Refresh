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
    [int]$TopLogprobs = 5                # top-k candidates per token (llama-server clamps to its own cap)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'model.gateway'; $SKILL_VERSION = '0.2.0'; $CONTRACT = '0.1'
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
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- warm-server registry path + evict-mode flag (Governor Phase 2) ----
    $warmRegPath = Get-WarmRegistryPath $WarmRegistryPath
    $doEvictWarm = [bool]$EvictWarm

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

    # ---- build chat messages ----
    $msgList = New-Object System.Collections.Generic.List[object]
    if ($null -ne $messages) {
        foreach ($mm in @($messages)) { $msgList.Add([ordered]@{ role = [string]$mm.role; content = [string]$mm.content }) }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($System)) { $msgList.Add([ordered]@{ role = 'system'; content = $System }) }
        if ([string]::IsNullOrWhiteSpace($Prompt)) { throw [PSCustomObject]@{ code = 'no_prompt'; message = "provide -Prompt (or messages in -InputsJson)"; retryable = $false } }
        $msgList.Add([ordered]@{ role = 'user'; content = $Prompt })
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

        # ---- start OR reuse the server (warm-aware), health-wait, complete, teardown ----
        $warmOn = [bool]$Warm
        $warmReused = $false; $warmStartedNew = $false; $warmEvicted = $false
        $resident = Read-WarmServer $warmRegPath
        if ($null -ne $resident) {
            $rl = Get-WarmServerLiveness $resident
            $residentPort = if (Has $resident 'port') { [int]$resident.port } else { 0 }
            $sameModel = $false
            if ((Has $resident 'model_id') -and ([string]$resident.model_id -eq [string]$m.model_id) -and (Has $resident 'ngl') -and ([int]$resident.ngl -eq $ngl) -and (Has $resident 'ctx') -and ([int]$resident.ctx -eq $ctx)) { $sameModel = $true }
            $healthy = $rl.alive -and (Test-ServerHealthy '127.0.0.1' $residentPort)
            if ($warmOn -and $healthy -and $sameModel) {
                $usePort = $residentPort; $warmReused = $true
                Write-Diag "warm hit: reusing resident llama-server pid=$($resident.pid) port=$usePort model=$($m.model_id)"
            } else {
                # different model / unhealthy / non-warm call -> evict so at most one server is ever on the GPU
                if ($rl.alive) {
                    if (Stop-ResidentServer $resident $rl) { $warmEvicted = $true; Write-Diag "evicted resident server pid=$($resident.pid) (sameModel=$sameModel healthy=$healthy warm=$warmOn)" }
                    else { $warnings.Add("resident server pid=$($resident.pid) alive but unidentified; not killed (possible external process)"); Write-Diag 'resident unidentified; not killed' }
                }
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
                    # record the resident registry IMMEDIATELY (before the health wait) so a mid-load crash
                    # leaves a tracked pid that the next call can identify and clean up.
                    [void](Write-WarmServer $warmRegPath ([ordered]@{
                        schema = 'lifeorch.model_gateway.warm/0.1'; pid = $serverPid; start_ticks = $startTicks
                        host = '127.0.0.1'; port = $usePort; model_id = $m.model_id; model_path = $modelPath
                        engine_path = $enginePath; ngl = $ngl; ctx = $ctx
                        started_at_utc = ([DateTime]::UtcNow).ToString('o'); holder = $glHolder
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
            } else {
                # warm reuse: no model load; health already confirmed above
                $loadStart.Stop(); $healthOk = $true; $healthMs = [int]$loadStart.Elapsed.TotalMilliseconds
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
