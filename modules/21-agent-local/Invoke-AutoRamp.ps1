#requires -Version 7.0
<#
.SYNOPSIS
  agent.local -AutoRamp -- Governor Phase 3 Stage-1 auto-ramp controller (Life Orchestrator, contract v0.2).
  OPT-IN, ADDITIVE. The shipped agent.local floor default + model.gateway behavior are unchanged; you only
  get this controller by invoking it (or agent.local -AutoRamp, which delegates here).
.DESCRIPTION
  The refined MONOTONIC, MODEL-AFFINE EPOCH controller (frontier second opinion, D-0058). It wraps a bounded
  ReAct task in resource epochs, each running EVERY LLM call on ONE resident model, and NEVER de-escalating
  within a task:
    M0 -- 3B floor        : decide=[mid]  DIRECT one-rung classify, 768 tok, up to 6 steps.
    M1 -- expanded mid     : SAME 3B, one fresh-context retry (1536/1024 tok, +2 steps), context REBUILT from
                             {goal, current authoritative state, completed actions + artifact ids, failed
                             checks, tools available} -- NOT "judge the previous answer".
    S0 -- 9B strong        : escalate the WHOLE epoch to the resident 9B, decide=[strong] as a DIRECT one-rung
                             classify (1536-2048 tok). (Calibration D-0058: the 9B needs >=~1024 tok or it
                             returns empty content -> at S0 we provision 2048.)
    X0 -- 27B legacy       : STAGE-2 ADDITIVE, OPT-IN (-AllowLegacy27B, OFF by default). After S0 still fails
                             its trigger, a SINGLE monotonic one-shot escalation to the legacy 27B
                             (llm.strong.qwen3p5-27b, b8661) as a DIRECT one-rung classify (2048 tok -- the
                             27B reasons in-content and returns empty below ~1k tok, per the STEP-1 probe),
                             STRICTLY deadline-gated: if the hard wall-clock deadline passes before a verified
                             contract pass, X0 aborts cleanly to completed_unverified / human_verification_required
                             (never hangs, never claims success on say-so). It reuses the whole-task gpu lease,
                             the exact residency-key evict+reload, the duplicate-side-effect guard (resume from
                             the last authoritative state), and the SAME frozen success contract.
  STAGE-2 OPT-IN also: logprob/entropy decision-confidence (-LogprobConfidence, OFF by default) -- the STEP-1
  live probe confirmed clean per-token logprobs on BOTH engine builds (b8661 + b10092), so a high decision-token
  entropy can add ONE more soft strike. It never replaces the heuristic and changes no default.
  STILL EXCLUDED (deferred): self-consistency, pattern-learning.

  CLOSING SIGNAL = a caller-supplied PRE-FROZEN deterministic success contract (schema
  lifeorch.goal_verification/0.1), frozen by hash BEFORE execution. A tier is "good enough" ONLY when the SAME
  frozen contract passes -- never the model's own say-so. Predicate vocabulary: file_exists,
  sha256_equals_source, json_schema_valid, command_exit_zero, artifact_exists, artifact_nonempty,
  state_version_changed, value_equals, all_required_tool_postconditions_passed. With no contract the run
  returns completed_unverified; with an un-checkable contract it returns human_verification_required.

  WARM-SERVER COMPOSITION: consumes the model.gateway (#7) resident warm server. Ensure-ResidentModel matches
  the WHOLE residency config key (model_id + model_sha256 + engine_build + gpu_layers + context + no_think +
  server generation) against runtime/warm-server.json + models.json, and reuses ONLY on an exact match, else
  it evicts + reloads. GPU LEASE: acquired ONCE for the whole ramped task and renewed ~30s (NOT per call) --
  gateway calls run with the SAME holder so they re-attach (already_held) and never release it out from under
  the task; per-call leasing would let another process swap the resident model mid-task.

  TRIGGERS: HARD (empty/malformed/out-of-set/length-truncated decision, finish-but-goal-verifier-fails,
  repeat-identical-action-with-no-state-change, resident-model mismatch) -> immediate escalation to S0.
  SOFT-STRIKE accumulator (low heuristic confidence, no state-fingerprint change, retry-needed/arg_parse,
  tool failure, truncation) escalates at >=2 strikes within 3 steps (uses M1 once before the reload).
  DUPLICATE-SIDE-EFFECT GUARD after escalation: RESUME from the last authoritative state (state persists in
  one process; the transcript is NOT restarted), task-scoped idempotency keys (hash of tool id + normalized
  args), refuse exact-duplicate mutations. Emits a machine-checkable GOVERNOR TRACE (per step: epoch/model,
  decision, contract-check, trigger fired, strike count).

  Orchestrator, NOT a review-queue producer (child review writes redirected to child_review.jsonl). Emits one
  lifeorch.skill.result/0.1 envelope on stdout; writes autoramp.json, governor-trace.json, autoramp.md,
  child_review.jsonl. Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-AutoRamp.ps1 -Goal "Write VERIFIED to ramp_ok.txt" -WorkingDir C:\tmp\s `
    -SuccessContract '{"schema":"lifeorch.goal_verification/0.1","predicates":[{"predicate":"file_exists","path":"C:\\tmp\\s\\ramp_ok.txt"},{"predicate":"artifact_nonempty","path":"C:\\tmp\\s\\ramp_ok.txt"}]}'
#>
[CmdletBinding()]
param(
    [string]$Goal,
    [string]$WorkingDir,
    [string]$SuccessContract,        # JSON: lifeorch.goal_verification/0.1
    [string]$SuccessContractPath,    # or a path to the contract JSON
    [int]$TaskTimeoutSec = 900,
    [int]$MaxModelSwaps = 1,
    [int]$MaxTotalSteps = 12,
    [double]$Temperature = 0.0,
    [int]$Seed = 42,
    # epoch model overrides (default from registry tiers mid/mid/strong); tests + engineered-fail use these
    [string]$M0Model = 'llm.weak.qwen2p5-3b',
    [string]$M1Model = 'llm.weak.qwen2p5-3b',
    [string]$S0Model = 'llm.strong.qwen3p5-9b',
    [int]$M0DecideTokens = 768,  [int]$M0GenTokens = 768,  [int]$M0MaxSteps = 6,
    [int]$M1DecideTokens = 1536, [int]$M1GenTokens = 1024, [int]$M1ExtraSteps = 2,
    [int]$S0DecideTokens = 2048, [int]$S0GenTokens = 2048, [int]$S0ExtraSteps = 4,
    # --- Stage-2 X0/27B one-shot recovery rung (ADDITIVE, OPT-IN, deadline-gated; OFF by default) ---
    # After S0 still fails its trigger, allow a SINGLE monotonic escalation to the legacy 27B as a DIRECT
    # one-rung classify, strictly bounded by a HARD wall-clock deadline (never hang; abort cleanly). The
    # 27B needs a generous token budget (2048) or it returns empty content -- section-5 + the live probe
    # (first token 'Thinking', empty at 24 tok). Only reachable when -AllowLegacy27B is set.
    [switch]$AllowLegacy27B,
    [string]$X0Model = 'llm.strong.qwen3p5-27b',
    [int]$X0DecideTokens = 2048, [int]$X0GenTokens = 2048, [int]$X0MaxSteps = 2,
    [int]$X0DeadlineSec = 300, [int]$X0LoadTimeoutSec = 260, [int]$X0MinBudgetSec = 1,
    # --- Stage-2 logprob/entropy decision-confidence (ADDITIVE, OPT-IN soft signal; OFF by default) ---
    # Only wired because the STEP-1 live probe confirmed clean per-token logprobs on BOTH engine builds
    # (b8661 + b10092). When on, decision calls request logprobs and a high decision-token entropy adds ONE
    # more soft strike; the existing heuristic and every default are unchanged (this is off by default).
    [switch]$LogprobConfidence,
    [int]$TopLogprobs = 5,
    [double]$EntropyStrikeThreshold = 1.0,
    [string]$ToolsPath,
    [string]$Tools,
    [string]$GatewayPath,
    [string]$Registry,
    [string]$WarmRegistryPath,       # override runtime/warm-server.json (tests)
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [int]$LoadTimeoutSec,
    [string]$ReviewQueuePath,
    # --- whole-task GPU lease (res.lease #29) ---
    [string]$GpuLease = 'auto',      # off | auto | require
    [int]$GpuLeaseWaitSeconds = 900,
    [int]$GpuLeaseTtlSeconds = 120,
    [int]$GpuLeaseRenewSeconds = 30,
    [string]$GpuLeaseHolder,
    [string]$LeaseDir,
    [string]$ResLeasePath,
    [int]$MaxObservationChars = 500,
    # --- test seam only (documented; no effect on real runs) ---
    [string[]]$FaultEscalateEpochs = @(),   # inject a synthetic HARD trigger at each named epoch's first step (-> immediate S0)
    [string[]]$FaultSoftEpochs = @(),        # inject 2 synthetic SOFT strikes at each named epoch's first step, WITHOUT acting (-> M0->M1->S0)
    [int]$X0SimulatedDelaySec = 0,           # test seam: sleep before the X0 decision to drive the deadline-abort path deterministically off-machine
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'agent.local.autoramp'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$VERIF_SCHEMA  = 'lifeorch.goal_verification/0.1'
$TRACE_SCHEMA  = 'lifeorch.governor_trace/0.1'
$PREDICATE_VOCAB = @('file_exists','artifact_exists','artifact_nonempty','sha256_equals_source','json_schema_valid','command_exit_zero','state_version_changed','value_equals','all_required_tool_postconditions_passed')
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[agent.local.autoramp] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Get-FileSha256([string]$path) {
    try { $b = [System.IO.File]::ReadAllBytes($path); return (Get-Sha256Hex $b) } catch { return $null }
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
function Resolve-Child([string]$override, [string]$relPath) {
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if (Test-Path -LiteralPath $override -PathType Leaf) { return (Resolve-Path -LiteralPath $override).Path }
        return $null
    }
    $cand = Join-Path $PSScriptRoot $relPath
    if (Test-Path -LiteralPath $cand -PathType Leaf) { return (Resolve-Path -LiteralPath $cand).Path }
    $root = Resolve-RepoRoot $PSScriptRoot
    if ($null -ne $root) {
        $cand2 = Join-Path $root ($relPath -replace '\.\.[\\/]', 'modules\')
        if (Test-Path -LiteralPath $cand2 -PathType Leaf) { return (Resolve-Path -LiteralPath $cand2).Path }
    }
    return $null
}
function Resolve-EntryPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if ([System.IO.Path]::IsPathRooted($p)) { if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path } ; return $null }
    $root = Resolve-RepoRoot $PSScriptRoot
    if ($null -ne $root) { $c = Join-Path $root $p; if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path } }
    $c2 = Join-Path $PSScriptRoot $p
    if (Test-Path -LiteralPath $c2 -PathType Leaf) { return (Resolve-Path -LiteralPath $c2).Path }
    return $null
}
function Invoke-Child([string]$entry, [string]$inputsJson, [string]$subRoot) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-InputsJson',$inputsJson,'-ArtifactRoot',$subRoot)
    $out = & $PwshPath @callArgs 2> $tmpErr.FullName
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $errTxt = ''; try { $errTxt = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ exit = $code; env = $env; raw = $txt; err = $errTxt }
}
# Run a child pwsh WITHOUT -ArtifactRoot (for res.lease, which has its own ArtifactRoot default) and parse .result.
function Invoke-Bare([string[]]$argList) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass @argList 2>$null
    $ErrorActionPreference = $prev
    $txt = ([string]($out | Out-String)).Trim()
    if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
    try { $e = $txt | ConvertFrom-Json; if ((Has $e 'result')) { return $e.result } ; return $e } catch { return $null }
}
function Add-Provenance($agg, $env, [string]$stage) {
    if ($null -ne $env -and (Has $env 'model_provenance')) {
        foreach ($mp in @($env.model_provenance)) {
            if ($null -eq $mp) { continue }
            $o = [ordered]@{ stage = $stage }
            foreach ($pn in $mp.PSObject.Properties.Name) { $o[$pn] = $mp.$pn }
            $agg.Add([pscustomobject]$o)
        }
    }
}
function Test-ChildOk($env) { return ($null -ne $env -and (Has $env 'status') -and (@('ok','partial') -contains [string]$env.status)) }
function Get-ChildErrCode($env) { if ($null -ne $env -and (Has $env 'error') -and $null -ne $env.error) { return [string](Prop $env.error 'code' 'child_error') } ; return 'child_error' }
function Get-FirstJsonObject([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $start = $text.IndexOf('{'); if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $start; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($inStr) { if ($esc) { $esc = $false } elseif ($ch -ceq '\') { $esc = $true } elseif ($ch -ceq '"') { $inStr = $false } }
        else { if ($ch -ceq '"') { $inStr = $true } elseif ($ch -ceq '{') { $depth++ } elseif ($ch -ceq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start, $i - $start + 1) } } }
    }
    return $null
}
function Limit-Text([string]$s, [int]$n) { if ($null -eq $s) { return '' } ; if ($s.Length -le $n) { return $s } ; return $s.Substring(0, $n) + " ...[+$($s.Length - $n) chars]" }
function Get-ArgSignature([string]$toolName, $argHash) {
    $pairs = New-Object System.Collections.Generic.List[string]
    if ($null -ne $argHash) {
        $keys = @($argHash.Keys | Where-Object { [string]$_ -ne 'review_queue_path' } | Sort-Object { [string]$_ })
        foreach ($k in $keys) {
            $v = $argHash[$k]
            $vs = if ($null -eq $v) { '' } elseif (($v -is [string]) -or ($v -is [ValueType])) { [string]$v } else { ($v | ConvertTo-Json -Compress -Depth 8) }
            $pairs.Add((([string]$k).ToLowerInvariant()) + '=' + $vs.Trim().ToLowerInvariant())
        }
    }
    return (([string]$toolName).ToLowerInvariant() + '|' + ($pairs -join '&'))
}
function Get-Observation($env, [string]$skillId, [int]$max) {
    if ($null -eq $env) { return 'no result' }
    $st = [string](Prop $env 'status' 'unknown')
    if (-not (Has $env 'result') -or $null -eq $env.result) { return (Limit-Text "status=$st" $max) }
    $r = $env.result
    $parts = New-Object System.Collections.Generic.List[string]
    switch -Wildcard ($skillId) {
        'doc.io'   { $parts.Add("op=$([string](Prop $r 'op' ''))"); if (Has $r 'path') { $parts.Add("path=$([string](Prop $r 'path' ''))") }; if ((Has $r 'file') -and $null -ne $r.file) { $parts.Add("sha256=$([string](Prop $r.file 'sha256' ''))") } }
        'fs.manage'{ $parts.Add("op=$([string](Prop $r 'op' ''))"); if (Has $r 'dest') { $parts.Add("dest=$([string](Prop $r 'dest' ''))") }; if (Has $r 'path') { $parts.Add("path=$([string](Prop $r 'path' ''))") } }
        'gen.image'{ if ((Has $r 'image') -and $null -ne $r.image) { $parts.Add("image=$([string](Prop $r.image 'path' ''))") } else { $parts.Add('generated') } }
        'fs.observer'{ $parts.Add("root=$([string](Prop $r 'root' ''))"); $parts.Add("files=$([string](Prop $r 'file_count' '?'))") }
        default    { $parts.Add("result=" + (Limit-Text (($r | ConvertTo-Json -Compress -Depth 6)) ([Math]::Max(120, $max - 40)))) }
    }
    return (Limit-Text ("status=$st; " + ($parts -join '; ')) $max)
}
# artifact ids/paths a tool produced (for the authoritative-state summary + idempotent resume)
function Get-ArtifactRefs($env) {
    $refs = New-Object System.Collections.Generic.List[string]
    if ($null -ne $env -and (Has $env 'artifacts')) {
        foreach ($a in @($env.artifacts)) { if ($null -ne $a -and (Has $a 'path')) { $refs.Add([string]$a.path) } }
    }
    if ($null -ne $env -and (Has $env 'result') -and $null -ne $env.result -and (Has $env.result 'image') -and $null -ne $env.result.image -and (Has $env.result.image 'path')) { $refs.Add([string]$env.result.image.path) }
    return $refs.ToArray()
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$modelProvenance = New-Object System.Collections.Generic.List[object]
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$trace = New-Object System.Collections.Generic.List[object]

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null; $toolsInline = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'goal')                 -and -not $bound.ContainsKey('Goal'))               { $Goal = [string]$p.goal }
            if ((Has $p 'working_dir')           -and -not $bound.ContainsKey('WorkingDir'))         { $WorkingDir = [string]$p.working_dir }
            if ((Has $p 'success_contract')      -and -not $bound.ContainsKey('SuccessContract'))    { $SuccessContract = ($p.success_contract | ConvertTo-Json -Depth 20 -Compress) }
            if ((Has $p 'success_contract_path') -and -not $bound.ContainsKey('SuccessContractPath')){ $SuccessContractPath = [string]$p.success_contract_path }
            if ((Has $p 'task_timeout_s')        -and -not $bound.ContainsKey('TaskTimeoutSec'))     { $TaskTimeoutSec = [int]$p.task_timeout_s }
            if ((Has $p 'max_model_swaps')       -and -not $bound.ContainsKey('MaxModelSwaps'))      { $MaxModelSwaps = [int]$p.max_model_swaps }
            if ((Has $p 'max_total_steps')       -and -not $bound.ContainsKey('MaxTotalSteps'))      { $MaxTotalSteps = [int]$p.max_total_steps }
            if ((Has $p 'temperature')           -and -not $bound.ContainsKey('Temperature'))        { $Temperature = [double]$p.temperature }
            if ((Has $p 'seed')                  -and -not $bound.ContainsKey('Seed'))               { $Seed = [int]$p.seed }
            if ((Has $p 'tools_path')            -and -not $bound.ContainsKey('ToolsPath'))          { $ToolsPath = [string]$p.tools_path }
            if  (Has $p 'tools')                 { $toolsInline = $p.tools }
            if ((Has $p 'gateway_path')          -and -not $bound.ContainsKey('GatewayPath'))        { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'registry')              -and -not $bound.ContainsKey('Registry'))           { $Registry = [string]$p.registry }
            if ((Has $p 'warm_registry_path')    -and -not $bound.ContainsKey('WarmRegistryPath'))   { $WarmRegistryPath = [string]$p.warm_registry_path }
            if ((Has $p 'pwsh_path')             -and -not $bound.ContainsKey('PwshPath'))           { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'load_timeout_s')        -and -not $bound.ContainsKey('LoadTimeoutSec'))     { $LoadTimeoutSec = [int]$p.load_timeout_s }
            if ((Has $p 'review_queue_path')     -and -not $bound.ContainsKey('ReviewQueuePath'))    { $ReviewQueuePath = [string]$p.review_queue_path }
            if ((Has $p 'gpu_lease')             -and -not $bound.ContainsKey('GpuLease'))           { $GpuLease = [string]$p.gpu_lease }
            if ((Has $p 'gpu_lease_holder')      -and -not $bound.ContainsKey('GpuLeaseHolder'))     { $GpuLeaseHolder = [string]$p.gpu_lease_holder }
            if ((Has $p 'gpu_lease_ttl_s')       -and -not $bound.ContainsKey('GpuLeaseTtlSeconds')) { $GpuLeaseTtlSeconds = [int]$p.gpu_lease_ttl_s }
            if ((Has $p 'gpu_lease_renew_s')     -and -not $bound.ContainsKey('GpuLeaseRenewSeconds')){ $GpuLeaseRenewSeconds = [int]$p.gpu_lease_renew_s }
            if ((Has $p 'gpu_lease_wait_s')      -and -not $bound.ContainsKey('GpuLeaseWaitSeconds')) { $GpuLeaseWaitSeconds = [int]$p.gpu_lease_wait_s }
            if ((Has $p 'lease_dir')             -and -not $bound.ContainsKey('LeaseDir'))           { $LeaseDir = [string]$p.lease_dir }
            if ((Has $p 'res_lease_path')        -and -not $bound.ContainsKey('ResLeasePath'))       { $ResLeasePath = [string]$p.res_lease_path }
            if ((Has $p 'm0_model') -and -not $bound.ContainsKey('M0Model')) { $M0Model = [string]$p.m0_model }
            if ((Has $p 'm1_model') -and -not $bound.ContainsKey('M1Model')) { $M1Model = [string]$p.m1_model }
            if ((Has $p 's0_model') -and -not $bound.ContainsKey('S0Model')) { $S0Model = [string]$p.s0_model }
            if ((Has $p 'fault_escalate_epochs') -and -not $bound.ContainsKey('FaultEscalateEpochs')) { $FaultEscalateEpochs = @($p.fault_escalate_epochs | ForEach-Object { [string]$_ }) }
            if ((Has $p 'fault_soft_epochs') -and -not $bound.ContainsKey('FaultSoftEpochs')) { $FaultSoftEpochs = @($p.fault_soft_epochs | ForEach-Object { [string]$_ }) }
            # --- Stage-2 X0 + logprob-confidence knobs (opt-in) ---
            if ((Has $p 'allow_legacy_27b')  -and -not $bound.ContainsKey('AllowLegacy27B'))       { $AllowLegacy27B = [bool]$p.allow_legacy_27b }
            if ((Has $p 'x0_model')          -and -not $bound.ContainsKey('X0Model'))              { $X0Model = [string]$p.x0_model }
            if ((Has $p 'x0_decide_tokens')  -and -not $bound.ContainsKey('X0DecideTokens'))       { $X0DecideTokens = [int]$p.x0_decide_tokens }
            if ((Has $p 'x0_gen_tokens')     -and -not $bound.ContainsKey('X0GenTokens'))          { $X0GenTokens = [int]$p.x0_gen_tokens }
            if ((Has $p 'x0_max_steps')      -and -not $bound.ContainsKey('X0MaxSteps'))           { $X0MaxSteps = [int]$p.x0_max_steps }
            if ((Has $p 'x0_deadline_s')     -and -not $bound.ContainsKey('X0DeadlineSec'))        { $X0DeadlineSec = [int]$p.x0_deadline_s }
            if ((Has $p 'x0_load_timeout_s') -and -not $bound.ContainsKey('X0LoadTimeoutSec'))     { $X0LoadTimeoutSec = [int]$p.x0_load_timeout_s }
            if ((Has $p 'x0_min_budget_s')   -and -not $bound.ContainsKey('X0MinBudgetSec'))       { $X0MinBudgetSec = [int]$p.x0_min_budget_s }
            if ((Has $p 'x0_simulated_delay_s') -and -not $bound.ContainsKey('X0SimulatedDelaySec')) { $X0SimulatedDelaySec = [int]$p.x0_simulated_delay_s }
            if ((Has $p 'logprob_confidence') -and -not $bound.ContainsKey('LogprobConfidence'))   { $LogprobConfidence = [bool]$p.logprob_confidence }
            if ((Has $p 'top_logprobs')      -and -not $bound.ContainsKey('TopLogprobs'))          { $TopLogprobs = [int]$p.top_logprobs }
            if ((Has $p 'entropy_strike_threshold') -and -not $bound.ContainsKey('EntropyStrikeThreshold')) { $EntropyStrikeThreshold = [double]$p.entropy_strike_threshold }
        }
    }
    if ($bound.ContainsKey('Tools') -and -not [string]::IsNullOrWhiteSpace($Tools)) {
        try { $toolsInline = $Tools | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_tools_json'; message='-Tools is not valid JSON'; retryable=$false } }
    }

    if ([string]::IsNullOrWhiteSpace($Goal)) { throw [PSCustomObject]@{ code='missing_parameter'; message='goal is required'; retryable=$false } }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $childReviewPath = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $ReviewQueuePath } else { Join-Path $invDir 'child_review.jsonl' }

    $workDirResolved = $null
    if (-not [string]::IsNullOrWhiteSpace($WorkingDir)) {
        try { if (Test-Path -LiteralPath $WorkingDir -PathType Container) { $workDirResolved = (Resolve-Path -LiteralPath $WorkingDir).Path } else { $workDirResolved = $WorkingDir } } catch { $workDirResolved = $WorkingDir }
    }

    # ---- FREEZE the success contract (by hash, BEFORE any execution) ----
    $contractObj = $null; $contractPredicates = @(); $contractHash = $null; $contractSupplied = $false; $contractCheckable = $true
    if ([string]::IsNullOrWhiteSpace($SuccessContract) -and -not [string]::IsNullOrWhiteSpace($SuccessContractPath)) {
        if (Test-Path -LiteralPath $SuccessContractPath -PathType Leaf) { $SuccessContract = Get-Content -LiteralPath $SuccessContractPath -Raw }
        else { throw [PSCustomObject]@{ code='contract_not_found'; message="success_contract_path not found: $SuccessContractPath"; retryable=$false } }
    }
    if (-not [string]::IsNullOrWhiteSpace($SuccessContract)) {
        try { $contractObj = $SuccessContract | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_contract'; message='success_contract is not valid JSON'; retryable=$false } }
        $contractSupplied = $true
        $rawPreds = @()
        if ((Has $contractObj 'predicates')) { $rawPreds = @($contractObj.predicates) }
        elseif ($contractObj -is [System.Array]) { $rawPreds = @($contractObj) }
        # normalize predicates deterministically (sorted keys) so the freeze hash is canonical
        $normPreds = New-Object System.Collections.Generic.List[object]
        foreach ($pr in $rawPreds) {
            if ($null -eq $pr) { continue }
            $pname = [string](Prop $pr 'predicate' '')
            if ([string]::IsNullOrWhiteSpace($pname)) { continue }
            if ($PREDICATE_VOCAB -notcontains $pname) { $contractCheckable = $false; $warnings.Add("contract predicate '$pname' is not in the closed vocabulary; contract is un-checkable") }
            $o = [ordered]@{}
            foreach ($k in (@($pr.PSObject.Properties.Name) | Sort-Object)) { $o[[string]$k] = $pr.$k }
            $normPreds.Add([pscustomobject]$o)
        }
        $contractPredicates = $normPreds.ToArray()
        if (@($contractPredicates).Count -lt 1) { $contractCheckable = $false; $warnings.Add('contract has no usable predicates') }
        $canon = ([ordered]@{ schema=$VERIF_SCHEMA; predicates=$contractPredicates } | ConvertTo-Json -Depth 20 -Compress)
        $contractHash = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes($canon))
        Write-Diag "contract frozen: predicates=$(@($contractPredicates).Count) checkable=$contractCheckable hash=$contractHash"
    }

    # ---- load the tool registry ----
    $toolsObj = $null
    if ($null -ne $toolsInline) { $toolsObj = $toolsInline }
    else {
        $tp = if (-not [string]::IsNullOrWhiteSpace($ToolsPath)) { $ToolsPath } else { Join-Path $PSScriptRoot 'tools.json' }
        if (-not (Test-Path -LiteralPath $tp -PathType Leaf)) { throw [PSCustomObject]@{ code='tools_registry_not_found'; message="tools registry not found: $tp"; retryable=$false } }
        try { $toolsObj = (Get-Content -LiteralPath $tp -Raw) | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_tools_registry'; message="tools registry is not valid JSON"; retryable=$false } }
    }
    $toolList = @()
    if ($toolsObj -is [System.Array]) { $toolList = @($toolsObj) } elseif (Has $toolsObj 'tools') { $toolList = @($toolsObj.tools) }
    else { throw [PSCustomObject]@{ code='invalid_tools_registry'; message='tools registry must be an array or {tools:[...]}'; retryable=$false } }
    $toolDefs = New-Object System.Collections.Generic.List[object]
    foreach ($t in $toolList) {
        $name = [string](Prop $t 'tool' (Prop $t 'skill_id' ''))
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $entry = Resolve-EntryPath ([string](Prop $t 'entrypoint' ''))
        $toolDefs.Add([pscustomobject]@{
            tool=$name; skill_id=[string](Prop $t 'skill_id' $name); entrypoint=$entry; entrypoint_raw=[string](Prop $t 'entrypoint' '')
            description=[string](Prop $t 'description' ''); args_hint=[string](Prop $t 'args_hint' ''); args_example=(Prop $t 'args_example' $null)
            required=@((Prop $t 'required' @()) | ForEach-Object { [string]$_ }); side_effecting=[bool](Prop $t 'side_effecting' $false); resolve_paths=[bool](Prop $t 'resolve_paths' $true)
        })
    }
    $usableTools = @($toolDefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_.entrypoint) })
    foreach ($m in @($toolDefs | Where-Object { [string]::IsNullOrWhiteSpace($_.entrypoint) })) { $warnings.Add("tool '$($m.tool)' entrypoint not resolved: $($m.entrypoint_raw)") }
    if (@($usableTools).Count -lt 1) { throw [PSCustomObject]@{ code='no_usable_tools'; message='no tool resolved to an existing entrypoint'; retryable=$false } }
    $toolNames = @($usableTools | ForEach-Object { $_.tool })
    $labels = @($toolNames + 'finish')
    $labelSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$labels)
    # tool menu WITH descriptions (both the router and the decider read these -- names alone are ambiguous,
    # e.g. doc.io vs fs.manage for "create a text file")
    $menuSb = [System.Text.StringBuilder]::new()
    foreach ($ut in $usableTools) { $se = if ($ut.side_effecting) { ' [writes files]' } else { ' [read-only]' }; [void]$menuSb.AppendLine("- $($ut.tool)$se : $($ut.description)") }
    [void]$menuSb.AppendLine('- finish : the goal is already fully satisfied; stop.')
    $toolMenu = $menuSb.ToString().TrimEnd()

    $gatewayEntry = Resolve-Child $GatewayPath '..\07-model-gateway\Invoke-ModelGateway.ps1'
    if ([string]::IsNullOrWhiteSpace($gatewayEntry)) { throw [PSCustomObject]@{ code='gateway_not_found'; message='model.gateway entrypoint not found (set -GatewayPath)'; retryable=$false } }
    $resleaseEntry = Resolve-Child $ResLeasePath '..\29-resource-lease\Invoke-ResLease.ps1'

    # registry (models.json) for residency validation + model file hashes
    $regPath = if (-not [string]::IsNullOrWhiteSpace($Registry)) { $Registry } else { Resolve-Child $null '..\07-model-gateway\models.json' }
    $regObj = $null
    if (-not [string]::IsNullOrWhiteSpace($regPath) -and (Test-Path -LiteralPath $regPath -PathType Leaf)) { try { $regObj = (Get-Content -LiteralPath $regPath -Raw) | ConvertFrom-Json } catch { } }
    function Get-ModelEntry([string]$modelId) {
        if ($null -eq $regObj -or -not (Has $regObj 'models')) { return $null }
        return (@($regObj.models) | Where-Object { (Has $_ 'model_id') -and ([string]$_.model_id -eq $modelId) } | Select-Object -First 1)
    }
    # expected residency key (the WHOLE config key) for a model id, from the registry
    function Get-ExpectedResidency([string]$modelId) {
        $m = Get-ModelEntry $modelId
        $engineBuild = 'unknown'
        $enginePath = $null
        if ($null -ne $m -and (Has $m 'engine_path')) { $enginePath = [string]$m.engine_path } elseif ($null -ne $regObj -and (Has $regObj 'engines') -and (Has $regObj.engines 'llama-server')) { $enginePath = [string]$regObj.engines.'llama-server' }
        if ($null -ne $enginePath) { if ($enginePath -match 'b10092') { $engineBuild = 'b10092' } elseif ($enginePath -match 'b8661') { $engineBuild = 'b8661' } }
        $sha = $null; if ($null -ne $m -and (Has $m 'params') -and (Has $m.params 'sha256')) { $sha = [string]$m.params.sha256 }
        $ngl = if ($null -ne $m -and (Has $m 'gpu_layers')) { [int]$m.gpu_layers } else { 99 }
        $ctx = if ($null -ne $m -and (Has $m 'context')) { [int]$m.context } else { 4096 }
        $noThink = ($null -ne $m -and (Has $m 'no_think') -and [bool]$m.no_think)
        return [ordered]@{ model_id=$modelId; model_sha256=$sha; engine_path=$enginePath; engine_build=$engineBuild; gpu_layers=$ngl; context=$ctx; no_think=$noThink }
    }
    $warmRegFile = if (-not [string]::IsNullOrWhiteSpace($WarmRegistryPath)) { $WarmRegistryPath } else {
        $gwDir = Split-Path -Parent $gatewayEntry; Join-Path $gwDir 'runtime/warm-server.json'
    }
    function Read-WarmResident {
        if ([string]::IsNullOrWhiteSpace($warmRegFile) -or -not (Test-Path -LiteralPath $warmRegFile -PathType Leaf)) { return $null }
        try { return (Get-Content -LiteralPath $warmRegFile -Raw | ConvertFrom-Json) } catch { return $null }
    }
    # Ensure-ResidentModel: reuse ONLY on an EXACT whole-key match, else evict (stop+reload). A mismatch is a
    # HARD ("stale/wrong-model") trigger ONLY when the resident is a model WE did not load ($loadedModel) --
    # i.e. an external/stale server. A mismatch equal to our own PREVIOUS epoch model is the EXPECTED transition
    # after an escalation: evict it so the next warm call cold-loads the new epoch model, but do NOT hard-trigger.
    # Returns @{ match; hard; had_resident; evicted; resident_model; mismatch_reason }.
    function Ensure-ResidentModel([string]$modelId, [string]$loadedModel) {
        $exp = Get-ExpectedResidency $modelId
        $res = Read-WarmResident
        $out = [ordered]@{ match=$false; hard=$false; had_resident=($null -ne $res); evicted=$false; expected_model=$modelId; expected_engine_build=$exp.engine_build; resident_model=$null; mismatch_reason=$null }
        if ($null -eq $res) { $out.match = $true; return $out }   # no resident -> next warm call cold-loads the right model
        $out.resident_model = [string](Prop $res 'model_id' '')
        $mismatch = @()
        if ([string](Prop $res 'model_id' '') -ne $exp.model_id) { $mismatch += 'model_id' }
        if ((Has $res 'ngl') -and [int]$res.ngl -ne [int]$exp.gpu_layers) { $mismatch += 'gpu_layers' }
        if ((Has $res 'ctx') -and [int]$res.ctx -ne [int]$exp.context) { $mismatch += 'context' }
        if ((Has $res 'engine_path') -and -not [string]::IsNullOrWhiteSpace([string]$exp.engine_path) -and ([string]$res.engine_path -ne [string]$exp.engine_path)) { $mismatch += 'engine_path' }
        if (@($mismatch).Count -eq 0) { $out.match = $true; return $out }
        # a resident WE did not load (not our previous epoch model) is stale/external -> HARD; our own prior model is an expected transition
        $out.hard = ([string]::IsNullOrWhiteSpace($loadedModel) -or ([string]$out.resident_model -ne [string]$loadedModel))
        $out.mismatch_reason = ($mismatch -join ',')
        try {
            $ev = Invoke-Child $gatewayEntry (([ordered]@{ evict_warm=$true; warm_registry_path=$warmRegFile } | ConvertTo-Json -Compress)) (Join-Path $invDir 'evict')
            if ($null -ne $ev.env -and (Has $ev.env 'result') -and (Has $ev.env.result 'warm') -and (Has $ev.env.result.warm 'evicted')) { $out.evicted = [bool]$ev.env.result.warm.evicted }
        } catch { }
        Write-Diag "resident mismatch ($($out.mismatch_reason)) resident=$($out.resident_model) expected=$modelId loaded=$loadedModel hard=$($out.hard) -> evicted=$($out.evicted)"
        return $out
    }

    # ---- GPU lease (whole-task): acquire once, renew ~30s, release in finally ----
    $glMode = if ([string]::IsNullOrWhiteSpace($GpuLease)) { 'auto' } else { $GpuLease.ToLowerInvariant() }
    if (@('off','auto','require') -notcontains $glMode) { $warnings.Add("unknown -GpuLease '$GpuLease'; using 'auto'"); $glMode = 'auto' }
    $holder = if (-not [string]::IsNullOrWhiteSpace($GpuLeaseHolder)) { $GpuLeaseHolder } elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE } else { "agent.local.autoramp:$PID" }
    $env:LIFEORCH_INSTANCE = $holder   # so child gateway res.lease spawns re-attach to THIS holder
    $leaseState = [ordered]@{ mode=$glMode; available=$null; acquired=$false; owned=$false; already_held=$false; lease_id=$null; holder=$holder; renew_count=0; released=$null; lost=$false }
    $lastRenew = [DateTime]::UtcNow

    # whole-task gpu lease helpers (acquire once; renew ~30s; release in finally)
    function Lease-Acquire {
        if ($glMode -eq 'off' -or [string]::IsNullOrWhiteSpace($resleaseEntry)) { if ($glMode -ne 'off') { $leaseState.available=$false; $warnings.Add('gpu lease: res.lease not found; proceeding without a lease') } ; return }
        $leaseState.available = $true
        $a = @('-File',$resleaseEntry,'-Action','acquire','-Resource','gpu','-Holder',$holder,'-TtlSeconds',"$GpuLeaseTtlSeconds",'-WaitSeconds',"$GpuLeaseWaitSeconds")
        if (-not [string]::IsNullOrWhiteSpace($LeaseDir)) { $a += @('-LeaseDir',$LeaseDir) }
        $r = Invoke-Bare $a
        if ($null -eq $r) { $leaseState.available=$false; $warnings.Add('gpu lease: acquire invocation failed; proceeding without a lease'); return }
        if ([bool](Prop $r 'acquired' $false)) {
            $leaseState.acquired=$true; $leaseState.lease_id=[string](Prop $r 'lease_id' ''); $leaseState.already_held=[bool](Prop $r 'already_held' $false); $leaseState.owned=(-not $leaseState.already_held)
            $script:lastRenew = [DateTime]::UtcNow
        } else {
            if ($glMode -eq 'require') { throw [PSCustomObject]@{ code='gpu_lease_unavailable'; message="gpu lease held by '$(Prop $r 'held_by' '?')'"; retryable=$true } }
            $warnings.Add("gpu lease contended (held by '$(Prop $r 'held_by' '?')'); proceeding")
        }
    }
    function Lease-RenewIfDue {
        if (-not $leaseState.owned -or [string]::IsNullOrWhiteSpace([string]$leaseState.lease_id)) { return $true }
        if (([DateTime]::UtcNow - $script:lastRenew).TotalSeconds -lt $GpuLeaseRenewSeconds) { return $true }
        $a = @('-File',$resleaseEntry,'-Action','renew','-Resource','gpu','-Holder',$holder,'-LeaseId',[string]$leaseState.lease_id,'-TtlSeconds',"$GpuLeaseTtlSeconds")
        if (-not [string]::IsNullOrWhiteSpace($LeaseDir)) { $a += @('-LeaseDir',$LeaseDir) }
        $r = Invoke-Bare $a
        $script:lastRenew = [DateTime]::UtcNow
        if ($null -ne $r -and [bool](Prop $r 'renewed' $false)) { $leaseState.renew_count++; return $true }
        $leaseState.lost = $true; $warnings.Add('gpu lease renew failed (lease lost)'); return $false
    }
    function Lease-Release {
        if (-not $leaseState.owned -or [string]::IsNullOrWhiteSpace([string]$leaseState.lease_id) -or -not $leaseState.available) { return }
        $a = @('-File',$resleaseEntry,'-Action','release','-Resource','gpu','-Holder',$holder,'-LeaseId',[string]$leaseState.lease_id)
        if (-not [string]::IsNullOrWhiteSpace($LeaseDir)) { $a += @('-LeaseDir',$LeaseDir) }
        $r = Invoke-Bare $a
        $leaseState.released = ($null -ne $r -and [bool](Prop $r 'released' $false))
    }

    # ---- gateway calls (direct, warm, pinned to the epoch model) ----
    function Invoke-GwGenerate([string]$modelId, [string]$system, [string]$prompt, [int]$maxTok, [string]$sub, [bool]$reqLogprobs = $false, [int]$loadTimeoutOverride = 0) {
        $o = [ordered]@{ model=$modelId; system=$system; prompt=$prompt; max_tokens=$maxTok; temperature=$Temperature; seed=$Seed; warm=$true; gpu_lease=$(if ($glMode -eq 'off') { 'off' } else { 'auto' }); gpu_lease_holder=$holder; pwsh_path=$PwshPath; warm_registry_path=$warmRegFile; review_queue_path=$childReviewPath }
        if (-not [string]::IsNullOrWhiteSpace($Registry)) { $o.registry = $Registry }
        if (-not [string]::IsNullOrWhiteSpace($LeaseDir)) { $o.lease_dir = $LeaseDir }
        # opt-in per-token logprobs (STEP 3): the gateway adds logprobs/top_logprobs to the chat body and
        # returns decision-token entropy in result.generation.logprobs. Off by default -> byte-identical request.
        if ($reqLogprobs) { $o.logprobs = $true; $o.top_logprobs = $TopLogprobs }
        # X0 bounds its own gateway call inside the hard deadline; else use the module load timeout.
        if ($loadTimeoutOverride -gt 0) { $o.load_timeout_s = $loadTimeoutOverride }
        elseif ($LoadTimeoutSec -gt 0) { $o.load_timeout_s = $LoadTimeoutSec }
        return (Invoke-Child $gatewayEntry ($o | ConvertTo-Json -Compress -Depth 12) $sub)
    }
    function Parse-Decision([string]$text) {
        $t = if ($null -ne $text) { $text } else { '' }
        $ci = $t.LastIndexOf('</think>'); if ($ci -ge 0) { $t = $t.Substring($ci + 8) }
        $low = $t.ToLowerInvariant()
        $dec = $null; $pos = [int]::MaxValue
        foreach ($lab in $labels) { $idx = $low.IndexOf($lab.ToLowerInvariant()); if ($idx -ge 0 -and $idx -lt $pos) { $pos = $idx; $dec = $lab } }
        $inSet = ($null -ne $dec)
        if (-not $inSet) { $dec = (($t.Trim() -split '\s+') | Select-Object -First 1) }
        return [pscustomobject]@{ decision=$dec; in_set=$inSet }
    }

    $decSystem = 'You are the decision controller for a local task agent. Given a GOAL, the CURRENT STATE (completed actions and the resulting authoritative world state), and the closed set of AVAILABLE ACTIONS (tool names plus finish), choose the single best NEXT action toward the GOAL. If -- and only if -- the GOAL is already fully satisfied, choose finish. Answer with EXACTLY ONE action name from the AVAILABLE ACTIONS and nothing else.'
    $argSystem = 'You produce arguments for a tool call. Output ONLY a single JSON object and nothing else (no prose, no code fences).'

    # ---- authoritative-state model (persists ACROSS epochs: resume, do not restart the transcript) ----
    $completed = New-Object System.Collections.Generic.List[object]   # {tool, observation, artifacts[]}
    $succeededSignatures = New-Object 'System.Collections.Generic.HashSet[string]'
    $succeededToolSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $lastFailedChecks = @()

    function Build-DecisionContext {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("GOAL: $Goal")
        if (-not [string]::IsNullOrWhiteSpace($workDirResolved)) { [void]$sb.AppendLine("WORKING_DIR: $workDirResolved") }
        [void]$sb.AppendLine('AVAILABLE ACTIONS:')
        [void]$sb.AppendLine($toolMenu)
        [void]$sb.AppendLine('CURRENT STATE:')
        if ($completed.Count -eq 0) { [void]$sb.AppendLine('- No actions have been completed yet.') }
        else { foreach ($c in $completed) { $art = if (@($c.artifacts).Count -gt 0) { ' [artifacts: ' + ((@($c.artifacts) | Select-Object -First 2) -join '; ') + ']' } else { '' }; [void]$sb.AppendLine("- COMPLETED $($c.tool): $($c.observation)$art") } }
        if (@($lastFailedChecks).Count -gt 0) {
            [void]$sb.AppendLine('THE GOAL IS NOT YET VERIFIED -- failing checks:')
            foreach ($fc in @($lastFailedChecks)) { [void]$sb.AppendLine("- $fc") }
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Best next action:')
        return $sb.ToString()
    }

    # ---- deterministic success-contract evaluation (frozen predicates only) ----
    function Test-Predicate($pred) {
        $name = [string](Prop $pred 'predicate' '')
        $ev = [ordered]@{ predicate=$name; passed=$false; evidence=$null }
        try {
            switch ($name) {
                'file_exists'       { $pt=[string](Prop $pred 'path' ''); $ev.passed = (Test-Path -LiteralPath $pt -PathType Leaf); $ev.evidence=$pt }
                'artifact_exists'   { $pt=[string](Prop $pred 'path' ''); $ev.passed = (Test-Path -LiteralPath $pt); $ev.evidence=$pt }
                'artifact_nonempty' { $pt=[string](Prop $pred 'path' ''); $ok=(Test-Path -LiteralPath $pt -PathType Leaf); $sz=if($ok){(Get-Item -LiteralPath $pt).Length}else{-1}; $ev.passed=($ok -and $sz -gt 0); $ev.evidence="bytes=$sz" }
                'sha256_equals_source' {
                    $pt=[string](Prop $pred 'path' ''); $src=[string](Prop $pred 'source' ''); $want=[string](Prop $pred 'sha256' '')
                    $h = Get-FileSha256 $pt
                    if (-not [string]::IsNullOrWhiteSpace($want)) { $ev.passed=($null -ne $h -and $h -eq $want.ToLowerInvariant()); $ev.evidence="path=$h want=$want" }
                    elseif (-not [string]::IsNullOrWhiteSpace($src)) { $hs = Get-FileSha256 $src; $ev.passed=($null -ne $h -and $null -ne $hs -and $h -eq $hs); $ev.evidence="path=$h source=$hs" }
                    else { $ev.passed=$false; $ev.evidence='no source/sha256' }
                }
                'json_schema_valid' {
                    $pt=[string](Prop $pred 'path' ''); $req=@((Prop $pred 'required_keys' @()) | ForEach-Object { [string]$_ })
                    $ok=$false; $why='not_found'
                    if (Test-Path -LiteralPath $pt -PathType Leaf) { try { $j = (Get-Content -LiteralPath $pt -Raw) | ConvertFrom-Json; $ok=$true; $why='valid_json'; foreach ($rk in $req) { if (-not (Has $j $rk)) { $ok=$false; $why="missing_key:$rk"; break } } } catch { $ok=$false; $why='invalid_json' } }
                    $ev.passed=$ok; $ev.evidence=$why
                }
                'command_exit_zero' {
                    $cmd=[string](Prop $pred 'command' ''); $cargs=@((Prop $pred 'args' @()) | ForEach-Object { [string]$_ })
                    if ([string]::IsNullOrWhiteSpace($cmd)) { $ev.passed=$false; $ev.evidence='no command' }
                    else { try { $psi = Start-Process -FilePath $cmd -ArgumentList $cargs -NoNewWindow -PassThru -Wait -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -RedirectStandardError ([System.IO.Path]::GetTempFileName()); $ev.passed=($psi.ExitCode -eq 0); $ev.evidence="exit=$($psi.ExitCode)" } catch { $ev.passed=$false; $ev.evidence="run_failed:$($_.Exception.Message)" } }
                }
                'state_version_changed' {
                    $pt=[string](Prop $pred 'path' ''); $base=[string](Prop $pred 'baseline_sha256' '')
                    $h = Get-FileSha256 $pt; $ev.passed=($null -ne $h -and $h -ne $base.ToLowerInvariant()); $ev.evidence="now=$h baseline=$base"
                }
                'value_equals' {
                    $act = Prop $pred 'actual' $null; $exp = Prop $pred 'expected' $null
                    if ($null -eq $act -and (Has $pred 'path')) { $pt=[string]$pred.path; if (Test-Path -LiteralPath $pt -PathType Leaf) { $act = (Get-Content -LiteralPath $pt -Raw).Trim() } }
                    $ev.passed = ([string]$act -eq [string]$exp); $ev.evidence="actual=$(Limit-Text ([string]$act) 60) expected=$(Limit-Text ([string]$exp) 60)"
                }
                'all_required_tool_postconditions_passed' {
                    $req=@((Prop $pred 'tools' @()) | ForEach-Object { [string]$_ })
                    $miss=@($req | Where-Object { -not $succeededToolSet.Contains($_) })
                    $ev.passed=(@($miss).Count -eq 0); $ev.evidence="missing=[$($miss -join ',')]"
                }
                default { $ev.passed=$false; $ev.evidence="unknown_predicate:$name" }
            }
        } catch { $ev.passed=$false; $ev.evidence="eval_error:$($_.Exception.Message)" }
        return [pscustomobject]$ev
    }
    function Test-SuccessContract {
        if (-not $contractSupplied) { return [pscustomobject]@{ evaluated=$false; passed=$false; checkable=$false; checks=@(); reason='no_contract' } }
        if (-not $contractCheckable) { return [pscustomobject]@{ evaluated=$false; passed=$false; checkable=$false; checks=@(); reason='uncheckable_contract' } }
        $checks = New-Object System.Collections.Generic.List[object]
        $allPass = $true
        foreach ($pr in $contractPredicates) { $c = Test-Predicate $pr; $checks.Add($c); if (-not $c.passed) { $allPass=$false } }
        return [pscustomobject]@{ evaluated=$true; passed=$allPass; checkable=$true; checks=$checks.ToArray(); reason=$(if($allPass){'all_passed'}else{'some_failed'}) }
    }
    # fingerprint of the authoritative state referenced by the contract (+ succeeded sigs) -> progress detection
    function Get-StateFingerprint {
        $sb = [System.Text.StringBuilder]::new()
        foreach ($s in (@($succeededSignatures) | Sort-Object)) { [void]$sb.Append("sig:$s;") }
        if ($contractSupplied) {
            foreach ($pr in $contractPredicates) {
                $pt = [string](Prop $pr 'path' '')
                if (-not [string]::IsNullOrWhiteSpace($pt)) { $exists = Test-Path -LiteralPath $pt -PathType Leaf; $sz = if ($exists) { (Get-Item -LiteralPath $pt).Length } else { -1 }; $h = if ($exists) { Get-FileSha256 $pt } else { '' }; [void]$sb.Append("f:${pt}:${exists}:${sz}:${h};") }
            }
        }
        return (Get-Sha256Hex $utf8.GetBytes($sb.ToString()))
    }

    # ---- epoch config ----
    function Resolve-EpochConfig([string]$epoch) {
        switch ($epoch) {
            'M0' { return [ordered]@{ epoch='M0'; model_id=$M0Model; decide_tokens=$M0DecideTokens; gen_tokens=$M0GenTokens; max_steps=$M0MaxSteps } }
            'M1' { return [ordered]@{ epoch='M1'; model_id=$M1Model; decide_tokens=$M1DecideTokens; gen_tokens=$M1GenTokens; max_steps=$M1ExtraSteps } }
            'S0' { return [ordered]@{ epoch='S0'; model_id=$S0Model; decide_tokens=$S0DecideTokens; gen_tokens=$S0GenTokens; max_steps=$S0ExtraSteps } }
            'X0' { return [ordered]@{ epoch='X0'; model_id=$X0Model; decide_tokens=$X0DecideTokens; gen_tokens=$X0GenTokens; max_steps=$X0MaxSteps } }
        }
        return $null
    }

    # ================= MAIN CONTROL LOOP =================
    Lease-Acquire
    try {
        $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($Goal + '|' + ($labels -join ',') + '|' + [string]$contractHash)))
        $stateEpoch = 'M0'; $modelSwaps = 0; $expandedMidUsed = $false; $loadedModel = $null
        $x0Attempted = $false; $x0DeadlineUtc = $null   # X0 one-shot state (opt-in, deadline-gated)
        $softWindow = New-Object System.Collections.Generic.List[int]   # per-step soft counts (window of 3)
        $stepsInEpoch = 0; $lastFingerprint = Get-StateFingerprint
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, $TaskTimeoutSec))
        $finalStatus = $null; $acceptedEpoch = $null; $lastVerification = $null
        $residentEnsured = @{}
        $stepNo = 0; $faultUsed = @{}

        while ($stepNo -lt $MaxTotalSteps) {
            if ([DateTime]::UtcNow -ge $deadline) { $finalStatus = 'time_budget_exhausted'; break }
            if (-not (Lease-RenewIfDue)) { $finalStatus = 'lease_lost'; break }
            $stepNo++; $stepsInEpoch++
            $epochCfg = Resolve-EpochConfig $stateEpoch
            $modelId = [string]$epochCfg.model_id

            # ----- X0 one-shot HARD wall-clock deadline gate (never hang; abort cleanly BEFORE any side effect) -----
            # The test seam sleeps to simulate a slow 27B running past the deadline; the deadline check then
            # aborts to completed_unverified / human_verification_required (never verified_success on say-so).
            if ($stateEpoch -eq 'X0') {
                if ($X0SimulatedDelaySec -gt 0 -and -not $faultUsed.ContainsKey('x0delay')) { $faultUsed['x0delay'] = $true; Start-Sleep -Seconds ([Math]::Min($X0SimulatedDelaySec, 120)) }
                if ($null -ne $x0DeadlineUtc -and [DateTime]::UtcNow -ge $x0DeadlineUtc) {
                    $finalStatus = if (-not $contractSupplied) { 'completed_unverified' } else { 'human_verification_required' }
                    $trace.Add([pscustomobject]([ordered]@{ schema=$TRACE_SCHEMA; step=$stepNo; epoch='X0'; model=$modelId
                        decision=$null; decision_in_set=$null; decision_finish_reason=$null; decision_conf=$null; decision_empty=$null; decision_entropy=$null
                        tool_invoked=$false; tool_status=$null; skipped_repeat=$false
                        contract_evaluated=$false; contract_passed=$null; contract_failed=@()
                        residency_match=$null; residency_mismatch_reason=$null; residency_evicted=$null
                        hard_trigger='x0_deadline_exceeded'; soft_strikes_this_step=0; soft_strikes_window=0; escalated_to=$null; model_swaps=$modelSwaps
                        x0_deadline_abort=$true; x0_deadline_remaining_ms=0 }))
                    Write-Diag "X0 deadline exceeded before a verified pass -> $finalStatus (clean abort, no hang)"
                    break
                }
            }

            # ----- Ensure-ResidentModel: exact whole-key residency; evict on mismatch; HARD only if the resident is stale/external -----
            $residency = Ensure-ResidentModel $modelId $loadedModel
            $residencyHardTrigger = [bool]$residency.hard

            $rec = [ordered]@{ schema=$TRACE_SCHEMA; step=$stepNo; epoch=$stateEpoch; model=$modelId
                decision=$null; decision_in_set=$null; decision_finish_reason=$null; decision_conf=$null; decision_empty=$null; decision_entropy=$null
                tool_invoked=$false; tool_status=$null; skipped_repeat=$false
                contract_evaluated=$false; contract_passed=$null; contract_failed=@()
                residency_match=[bool]$residency.match; residency_mismatch_reason=$residency.mismatch_reason; residency_evicted=[bool]$residency.evicted
                hard_trigger=$null; soft_strikes_this_step=0; soft_strikes_window=0; escalated_to=$null; model_swaps=$modelSwaps
                x0_deadline_abort=$null; x0_deadline_remaining_ms=$null }
            if ($stateEpoch -eq 'X0' -and $null -ne $x0DeadlineUtc) { $rec.x0_deadline_remaining_ms = [int][Math]::Max(0, ($x0DeadlineUtc - [DateTime]::UtcNow).TotalMilliseconds) }

            $hard = $false; $hardReason = $null; $soft = 0; $softReasons = New-Object System.Collections.Generic.List[string]
            $pd = [pscustomobject]@{ decision=$null; in_set=$false }
            if ($residencyHardTrigger) {
                # a wrong resident was found + evicted -> HARD; skip the decision call entirely (do not spend an
                # LLM call against a model we already know is wrong) and go straight to escalation.
                $hard = $true; $hardReason = "resident_model_mismatch:$($residency.mismatch_reason)"
            } else {
                # ----- DECIDE (direct warm classify, pinned to the epoch model) -----
                $decCtx = Build-DecisionContext
                # X0 bounds its own gateway call to the remaining hard deadline so the 27B call can never hang.
                $decLoadTo = 0
                if ($stateEpoch -eq 'X0' -and $null -ne $x0DeadlineUtc) {
                    $rem = [int]([Math]::Ceiling(($x0DeadlineUtc - [DateTime]::UtcNow).TotalSeconds))
                    $decLoadTo = [Math]::Max(5, [Math]::Min($X0LoadTimeoutSec, $rem))
                }
                $decR = Invoke-GwGenerate $modelId $decSystem $decCtx $epochCfg.decide_tokens (Join-Path $invDir "decide-$stepNo") ([bool]$LogprobConfidence) $decLoadTo
                $decEnv = $decR.env; Add-Provenance $modelProvenance $decEnv "decide-$stepNo"
                $loadedModel = $modelId   # the warm server now holds this epoch's model (loaded by the decision call)
                $decText = ''; $decFinish=''; $decConf=$null
                if (Test-ChildOk $decEnv) { $decText = [string](Prop (Prop $decEnv.result 'output' $null) 'text' ''); $decFinish = [string](Prop (Prop $decEnv.result 'generation' $null) 'finish_reason' ''); $decConf = Prop $decEnv 'confidence' $null }
                $decEmpty = [string]::IsNullOrWhiteSpace($decText)
                # optional logprob-derived decision-token entropy (STEP 3, opt-in). Additive soft signal ONLY.
                $decEntropy = $null
                if (Test-ChildOk $decEnv) {
                    $gen = Prop $decEnv.result 'generation' $null
                    $lp = if ($null -ne $gen) { Prop $gen 'logprobs' $null } else { $null }
                    if ($null -ne $lp) {
                        if (Has $lp 'decision_token_entropy' -and $null -ne $lp.decision_token_entropy) { $decEntropy = [double]$lp.decision_token_entropy }
                        elseif (Has $lp 'first_token_entropy' -and $null -ne $lp.first_token_entropy) { $decEntropy = [double]$lp.first_token_entropy }
                    }
                }
                $pd = Parse-Decision $decText
                $chosen = $pd.decision
                $rec.decision = $chosen; $rec.decision_in_set = $pd.in_set; $rec.decision_finish_reason = $decFinish; $rec.decision_conf = $decConf; $rec.decision_empty = $decEmpty; $rec.decision_entropy = $decEntropy

                if ($decEmpty) { $hard=$true; $hardReason='empty_decision' }
                elseif (-not $pd.in_set) { $hard=$true; $hardReason='out_of_set_decision' }
                elseif ($decFinish -eq 'length') { $hard=$true; $hardReason='length_truncated_decision' }
                if ($null -ne $decConf -and [double]$decConf -lt 0.5) { $soft++; $softReasons.Add('low_confidence') }
                # opt-in entropy soft strike: a high decision-token entropy is one more soft signal (never a hard
                # reject -- a low-entropy wrong answer is still wrong, per the frontier note). Off by default.
                if ($LogprobConfidence -and $null -ne $decEntropy -and [double]$decEntropy -ge $EntropyStrikeThreshold) { $soft++; $softReasons.Add("high_decision_entropy:$([Math]::Round([double]$decEntropy,3))") }

                # ----- test seam: synthetic HARD trigger to deterministically exercise the live ramp -----
                if (-not $hard -and (@($FaultEscalateEpochs) -contains $stateEpoch) -and -not $faultUsed.ContainsKey("hard:$stateEpoch")) {
                    $faultUsed["hard:$stateEpoch"] = $true; $hard=$true; $hardReason='test_forced_escalation'
                }
            }

            # ----- test seam: synthetic SOFT strikes (no action this step) -> exercises the M0->M1->S0 soft path live -----
            $softFaultFired = $false
            if (-not $hard -and (@($FaultSoftEpochs) -contains $stateEpoch) -and -not $faultUsed.ContainsKey("soft:$stateEpoch")) {
                $faultUsed["soft:$stateEpoch"] = $true; $soft += 2; $softReasons.Add('test_forced_soft'); $softFaultFired = $true
            }

            $progressed = $false
            if (-not $hard -and -not $softFaultFired -and $pd.in_set) {
                if ($chosen -eq 'finish') {
                    $v = Test-SuccessContract
                    $rec.contract_evaluated = $v.evaluated; $rec.contract_passed = $v.passed
                    $rec.contract_failed = @($v.checks | Where-Object { -not $_.passed } | ForEach-Object { "$($_.predicate):$($_.evidence)" })
                    $lastVerification = $v
                    if (-not $contractSupplied) {
                        # no machine-checkable contract -> we cannot claim verified success
                        $finalStatus = 'completed_unverified'; $acceptedEpoch = $stateEpoch; $trace.Add([pscustomobject]$rec); break
                    } elseif (-not $contractCheckable) {
                        $finalStatus = 'human_verification_required'; $acceptedEpoch = $stateEpoch; $trace.Add([pscustomobject]$rec); break
                    } elseif ($v.passed) {
                        $finalStatus = 'verified_success'; $acceptedEpoch = $stateEpoch; $trace.Add([pscustomobject]$rec); break
                    } else {
                        # a CHECKABLE contract that does NOT pass -> HARD (never honor a self-claimed finish)
                        $hard = $true; $hardReason = 'finish_but_contract_failed'; $lastFailedChecks = $rec.contract_failed
                    }
                }
                else {
                    # a tool decision -> arg-gen (warm, pinned) -> idempotency guard -> invoke
                    $toolDef = @($usableTools | Where-Object { $_.tool -eq $chosen })[0]
                    $exampleStr = if ($null -ne $toolDef.args_example) { ($toolDef.args_example | ConvertTo-Json -Compress -Depth 8) } else { '{}' }
                    $reqStr = if (@($toolDef.required).Count -gt 0) { ($toolDef.required -join ', ') } else { '(none listed)' }
                    $argPrompt = @(
                        "GOAL: $Goal",
                        $(if (-not $toolDef.resolve_paths) { "PATHS: this tool resolves paths itself. For a destination folder use a KNOWN-FOLDER NAME ('desktop','downloads','documents','pictures') or an absolute path -- do NOT prefix it. For a source use the EXACT path shown in CURRENT STATE." }
                          elseif (-not [string]::IsNullOrWhiteSpace($workDirResolved)) { "WORKING_DIR: $workDirResolved (bare filenames resolve here)" } else { '' }),
                        "TOOL: $($toolDef.tool) (skill_id=$($toolDef.skill_id))",
                        "TOOL PURPOSE: $($toolDef.description)",
                        "ARGUMENT GUIDE: $($toolDef.args_hint)",
                        "REQUIRED ARGUMENTS: $reqStr",
                        "EXAMPLE ARGUMENTS: $exampleStr",
                        '',
                        'CURRENT STATE:',
                        (Build-DecisionContext),
                        '',
                        "Output the JSON arguments object for '$($toolDef.tool)' to make progress now."
                    ) -join "`n"
                    $argR = Invoke-GwGenerate $modelId $argSystem $argPrompt $epochCfg.gen_tokens (Join-Path $invDir "arggen-$stepNo")
                    $argEnv = $argR.env; Add-Provenance $modelProvenance $argEnv "arggen-$stepNo"
                    $argText = ''; if (Test-ChildOk $argEnv) { $argText = [string](Prop (Prop $argEnv.result 'output' $null) 'text' '') }
                    $argJson = Get-FirstJsonObject $argText
                    $argObj = $null; if ($null -ne $argJson) { try { $argObj = $argJson | ConvertFrom-Json } catch { $argObj = $null } }
                    if ($null -eq $argObj) { $soft++; $softReasons.Add('arg_parse_failed') }
                    else {
                        $argHash = [ordered]@{}
                        foreach ($pn in $argObj.PSObject.Properties.Name) {
                            $val = $argObj.$pn
                            if ($toolDef.resolve_paths -and $val -is [string] -and -not [string]::IsNullOrWhiteSpace($workDirResolved) -and (@('path','input','output','out','file','dest','destination','source') -contains $pn.ToLowerInvariant()) -and -not [System.IO.Path]::IsPathRooted([string]$val)) { $val = Join-Path $workDirResolved ([string]$val) }
                            $argHash[$pn] = $val
                        }
                        $sig = Get-ArgSignature $toolDef.tool $argHash
                        if ($succeededSignatures.Contains($sig)) {
                            # DUPLICATE-SIDE-EFFECT GUARD: refuse the exact-duplicate mutation
                            $rec.skipped_repeat = $true; $rec.tool_status = 'skipped_repeat'
                            $fpNow = Get-StateFingerprint
                            if ($fpNow -eq $lastFingerprint) { $hard=$true; $hardReason='repeat_identical_action_no_state_change' }
                            else { $soft++; $softReasons.Add('repeat_but_state_changed') }
                        } else {
                            if (-not $argHash.Contains('review_queue_path')) { $argHash['review_queue_path'] = $childReviewPath }
                            $toolR = Invoke-Child $toolDef.entrypoint ($argHash | ConvertTo-Json -Compress -Depth 12) (Join-Path $invDir "tool-$stepNo")
                            $toolEnv = $toolR.env; Add-Provenance $modelProvenance $toolEnv "tool-$stepNo"
                            $rec.tool_invoked = $true
                            if (Test-ChildOk $toolEnv) {
                                $rec.tool_status = [string](Prop $toolEnv 'status' 'ok')
                                [void]$succeededSignatures.Add($sig); [void]$succeededToolSet.Add($toolDef.tool)
                                $obs = Get-Observation $toolEnv $toolDef.skill_id $MaxObservationChars
                                $completed.Add([pscustomobject]@{ tool=$toolDef.tool; observation=$obs; artifacts=(Get-ArtifactRefs $toolEnv) })
                            } else {
                                $rec.tool_status = if ($null -ne $toolEnv -and (Has $toolEnv 'status')) { [string]$toolEnv.status } else { 'error' }
                                $ec = Get-ChildErrCode $toolEnv
                                $soft++; $softReasons.Add("tool_failed:$ec")
                                $completed.Add([pscustomobject]@{ tool=$toolDef.tool; observation="FAILED: $ec"; artifacts=@() })
                            }
                        }
                    }
                    # after any tool step, re-check the contract (maybe the goal is now verified)
                    $v = Test-SuccessContract
                    $rec.contract_evaluated = $v.evaluated; $rec.contract_passed = $v.passed
                    $rec.contract_failed = @($v.checks | Where-Object { -not $_.passed } | ForEach-Object { "$($_.predicate):$($_.evidence)" })
                    $lastVerification = $v; $lastFailedChecks = $rec.contract_failed
                    if ($v.evaluated -and $v.passed) { $finalStatus='verified_success'; $acceptedEpoch=$stateEpoch; $trace.Add([pscustomobject]$rec); break }
                }
            }

            # progress / no-progress fingerprint
            $fp = Get-StateFingerprint
            if ($fp -ne $lastFingerprint) { $progressed = $true; $lastFingerprint = $fp } else { $soft++; $softReasons.Add('no_state_fingerprint_change') }

            # soft-strike accumulator: sum over the last 3 steps
            $softWindow.Add($soft)
            while ($softWindow.Count -gt 3) { $softWindow.RemoveAt(0) }
            $softSum = ($softWindow | Measure-Object -Sum).Sum
            $rec.hard_trigger = $hardReason; $rec.soft_strikes_this_step = $soft; $rec.soft_strikes_window = [int]$softSum
            if ($softReasons.Count -gt 0) { $rec.soft_reasons = $softReasons.ToArray() }

            # ---- ESCALATION (monotonic; never de-escalate) ----
            $escalate = $false; $escReason = $null
            if ($hard) { $escalate = $true; $escReason = "hard:$hardReason" }
            elseif ($softSum -ge 2) { $escalate = $true; $escReason = "soft>=2:$([string]::Join(',', $softReasons.ToArray()))" }
            elseif ($stepsInEpoch -ge [int]$epochCfg.max_steps -and -not $progressed) { $escalate = $true; $escReason = 'epoch_budget_exhausted_no_progress' }

            if ($escalate) {
                if ($hard -and ($stateEpoch -eq 'M0' -or $stateEpoch -eq 'M1')) {
                    # HARD -> immediate S0 (skip M1)
                    if ($modelSwaps -lt $MaxModelSwaps) { $rec.escalated_to='S0'; $stateEpoch='S0'; $modelSwaps++; $stepsInEpoch=0; $softWindow.Clear() }
                    else { $finalStatus='local_ceiling_reached' }
                }
                elseif ($stateEpoch -eq 'M0' -and -not $expandedMidUsed) {
                    # SOFT / budget -> use M1 once before the reload
                    $rec.escalated_to='M1'; $stateEpoch='M1'; $expandedMidUsed=$true; $stepsInEpoch=0; $softWindow.Clear()
                }
                elseif (($stateEpoch -eq 'M0' -or $stateEpoch -eq 'M1') -and $modelSwaps -lt $MaxModelSwaps) {
                    $rec.escalated_to='S0'; $stateEpoch='S0'; $modelSwaps++; $stepsInEpoch=0; $softWindow.Clear()
                }
                elseif ($stateEpoch -eq 'S0' -and $AllowLegacy27B -and -not $x0Attempted) {
                    # ----- OPT-IN X0/27B ONE-SHOT RECOVERY: S0 failed its trigger; escalate ONCE to the legacy 27B,
                    # strictly deadline-gated. Monotonic + model-affine (M0->M1->S0->X0), never de-escalate. -----
                    $x0Remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
                    if ($x0Remaining -ge $X0MinBudgetSec) {
                        $x0Attempted = $true
                        $x0DeadlineUtc = [DateTime]::UtcNow.AddSeconds([Math]::Min([double]$X0DeadlineSec, $x0Remaining))
                        $MaxTotalSteps += $X0MaxSteps   # guarantee the one-shot X0 epoch its own step budget
                        $rec.escalated_to='X0'; $stateEpoch='X0'; $modelSwaps++; $stepsInEpoch=0; $softWindow.Clear()
                        Write-Diag "S0 failed its trigger -> X0 one-shot 27B recovery (AllowLegacy27B); deadline=$([Math]::Round([Math]::Min([double]$X0DeadlineSec,$x0Remaining)))s"
                    } else {
                        $rec.escalated_to = $null
                        $finalStatus = if (-not $contractSupplied) { 'completed_unverified' } else { 'human_verification_required' }
                        Write-Diag "S0 ceiling + AllowLegacy27B but insufficient deadline for X0 ($([Math]::Round($x0Remaining))s < ${X0MinBudgetSec}s) -> $finalStatus"
                    }
                }
                elseif ($stateEpoch -eq 'X0') {
                    # X0 (the one-shot 27B) itself failed its trigger -> nowhere above; abort cleanly, never claim success.
                    $finalStatus = if (-not $contractSupplied) { 'completed_unverified' } else { 'human_verification_required' }
                    Write-Diag "X0 one-shot recovery failed its trigger -> $finalStatus (top of ladder reached)"
                }
                else {
                    # already at S0 (or swap cap hit) with X0 not enabled -> local ceiling (Stage-1 default, UNCHANGED)
                    $finalStatus='local_ceiling_reached'
                }
            }
            $trace.Add([pscustomobject]$rec)
            if ($null -ne $finalStatus) { break }
        }

        if ($null -eq $finalStatus) {
            if ([DateTime]::UtcNow -ge $deadline) { $finalStatus='time_budget_exhausted' }
            elseif (-not $contractSupplied) { $finalStatus='completed_unverified' }
            elseif (-not $contractCheckable) { $finalStatus='human_verification_required' }
            else { $finalStatus='local_ceiling_reached' }
        }

        # ---- write the governor trace artifact ----
        $traceObj = [ordered]@{ schema=$TRACE_SCHEMA; invocation_id=$InvocationId; goal=$Goal; contract_hash=$contractHash
            final_status=$finalStatus; accepted_epoch=$acceptedEpoch; model_swaps=$modelSwaps; steps=$trace.ToArray() }
        $tracePath = Join-Path $invDir 'governor-trace.json'
        [System.IO.File]::WriteAllText($tracePath, ($traceObj | ConvertTo-Json -Depth 20), $utf8)

        $verifiedSuccess = ($finalStatus -eq 'verified_success')
        $result = [ordered]@{
            goal=$Goal; working_dir=$workDirResolved
            autoramp=$true; final_status=$finalStatus; verified_success=$verifiedSuccess
            accepted_epoch=$acceptedEpoch; model_swaps=$modelSwaps; step_count=$stepNo; max_total_steps=$MaxTotalSteps
            contract=[ordered]@{ supplied=$contractSupplied; checkable=$contractCheckable; hash=$contractHash; predicate_count=@($contractPredicates).Count; last=$lastVerification }
            epochs_visited=@($trace.ToArray() | ForEach-Object { $_.epoch } | Select-Object -Unique)
            gpu_lease=$leaseState
            completed_tools=@($succeededToolSet)
            governor_trace=$trace.ToArray()
            governor_trace_path=$tracePath
            is_review_producer=$false; child_reviews_redirected_to=$childReviewPath
            x0=[ordered]@{ enabled=[bool]$AllowLegacy27B; attempted=$x0Attempted; model=$X0Model; deadline_s=$X0DeadlineSec; decide_tokens=$X0DecideTokens; max_steps=$X0MaxSteps; fired=(@($trace.ToArray() | ForEach-Object { $_.epoch }) -contains 'X0') }
            logprob_confidence=[ordered]@{ enabled=[bool]$LogprobConfidence; top_logprobs=$TopLogprobs; entropy_strike_threshold=$EntropyStrikeThreshold }
            excluded=@('self-consistency','pattern-learning')
            optin_stage2=@('X0/27B one-shot recovery via -AllowLegacy27B (deadline-gated)','logprob/entropy decision-confidence via -LogprobConfidence')
        }
        if ($warnings.Count -gt 0 -and $status -eq 'ok') { $status = 'partial' }
    }
    finally {
        # evict the warm server after the ramped task (leave 0 orphans) + release the whole-task lease
        try { [void](Invoke-Child $gatewayEntry (([ordered]@{ evict_warm=$true; warm_registry_path=$warmRegFile } | ConvertTo-Json -Compress)) (Join-Path $invDir 'evict-final')) } catch { }
        Lease-Release
    }
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) { $status='error'; $errorObj=[ordered]@{ code=[string]$ex.code; message=[string]$ex.message; retryable=[bool]$ex.retryable } }
    else { $status='error'; $errorObj=[ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }; Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)" }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts: autoramp.json + autoramp.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $aj = [ordered]@{ schema='lifeorch.autoramp.run/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result; model_provenance=$modelProvenance.ToArray() }
        $ajPath = Join-Path $invDir 'autoramp.json'
        [System.IO.File]::WriteAllText($ajPath, ($aj | ConvertTo-Json -Depth 30), $utf8)
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# agent.local -AutoRamp run"); [void]$mb.AppendLine('')
        [void]$mb.AppendLine("**Goal:** $($result.goal)")
        [void]$mb.AppendLine("**Final status:** $($result.final_status)   **verified_success:** $($result.verified_success)   **accepted_epoch:** $($result.accepted_epoch)   **model_swaps:** $($result.model_swaps)   **steps:** $($result.step_count)")
        [void]$mb.AppendLine("**Epochs visited:** " + (@($result.epochs_visited) -join ' -> '))
        [void]$mb.AppendLine("**Contract:** supplied=$($result.contract.supplied) checkable=$($result.contract.checkable) hash=$($result.contract.hash)")
        [void]$mb.AppendLine('')
        foreach ($st in @($result.governor_trace)) {
            [void]$mb.AppendLine("## Step $($st.step) [$($st.epoch) / $($st.model)]")
            [void]$mb.AppendLine("- decision: $($st.decision) (in_set=$($st.decision_in_set) finish=$($st.decision_finish_reason) empty=$($st.decision_empty) entropy=$($st.decision_entropy))")
            [void]$mb.AppendLine("- tool: invoked=$($st.tool_invoked) status=$($st.tool_status) skipped_repeat=$($st.skipped_repeat)")
            [void]$mb.AppendLine("- contract: evaluated=$($st.contract_evaluated) passed=$($st.contract_passed) failed=[$(@($st.contract_failed) -join '; ')]")
            [void]$mb.AppendLine("- residency: match=$($st.residency_match) mismatch=$($st.residency_mismatch_reason) evicted=$($st.residency_evicted)")
            [void]$mb.AppendLine("- triggers: hard=$($st.hard_trigger) soft_step=$($st.soft_strikes_this_step) soft_window=$($st.soft_strikes_window) escalated_to=$($st.escalated_to)")
            if ($st.epoch -eq 'X0') { [void]$mb.AppendLine("- x0: deadline_remaining_ms=$($st.x0_deadline_remaining_ms) deadline_abort=$($st.x0_deadline_abort)") }
            [void]$mb.AppendLine('')
        }
        $amPath = Join-Path $invDir 'autoramp.md'
        [System.IO.File]::WriteAllText($amPath, $mb.ToString(), $utf8)
        foreach ($a in @([pscustomobject]@{ p=$ajPath; k='json' }, [pscustomobject]@{ p=$amPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) { $b=[byte[]]([System.IO.File]::ReadAllBytes($a.p)); $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) }) }
        }
        if (Test-Path -LiteralPath $result.governor_trace_path -PathType Leaf) { $b=[byte[]]([System.IO.File]::ReadAllBytes($result.governor_trace_path)); $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $result.governor_trace_path).Path; kind='json'; bytes=$b.Length; sha256=(Get-Sha256Hex $b) }) }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[agent.local.autoramp] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$confidence = $null
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$confidence; artifacts=$artifacts; model_provenance=$modelProvenance.ToArray()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
