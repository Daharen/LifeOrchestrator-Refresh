#requires -Version 7.0
<#
.SYNOPSIS
  agent.local -- Local Orchestrator / Agent core (Life Orchestrator, contract v0.2).
.DESCRIPTION
  A bounded, ReAct-style LOCAL agent loop: given a natural-language goal it decides which Module (tool)
  to call, generates that tool's arguments, invokes it, observes the result, and repeats until the goal
  is finished or a hard step budget is reached. It is the frontier agent's tool loop, done locally, to
  offload orchestration off the scarce weekly frontier allotment.

  Composition (reimplements nothing):
    - DECISION ("which tool next, or finish?") routes THROUGH logic.escalator (#19) as a closed-set
      `classify` task (labels = the registered tool names + `finish`). The escalator's deterministic
      in-set gate guarantees a valid action (or surfaces needs_frontier); its tiny->weak->mid ladder is
      the cost-offload.
    - ARG-GENERATION and the FINAL ANSWER use model.gateway (#7) directly (one call each).
    - TOOLS are conforming Modules invoked as child skills (the image.index/#18 spawn-and-parse-envelope
      pattern). The default registry (tools.json) ships doc.io (#20) + fs.observer (#2); it is the agent's
      entire capability surface (no arbitrary-shell tool).

  Guardrails: a hard max_steps budget; a -DryRun plan-preview (plans tools+args, invokes nothing);
  needs_frontier surfaced as a status field (never a frontier call / queue write). ORCHESTRATOR, NOT a
  review-queue producer: it redirects every child's review writes to an in-artifact child_review.jsonl and
  never writes the canonical review_queue.jsonl (the seven-producer set is unchanged).

  determinism=mixed, parallel_safe=false (drives the gateway -> GPU/port and can invoke doc.io file
  mutations), batch=false, streaming=false. Emits one lifeorch.skill.result/0.1 envelope on stdout;
  diagnostics to stderr; writes agent.json, agent.md, child_review.jsonl, result.json, stderr.txt (+ per
  child sub-roots). Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -Goal "Create hello.txt containing 'hi from agent.local'" -WorkingDir C:\tmp\scratch
  pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -InputsJson '{"goal":"read notes.md and write its line count to stats.txt","working_dir":"C:\\tmp\\scratch","max_steps":4}'
  pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -Goal "list the .md files here and write them to index.txt" -WorkingDir C:\tmp\scratch -DryRun
#>
[CmdletBinding()]
param(
    [string]$Goal,
    [string]$WorkingDir,
    [int]$MaxSteps = 4,
    [switch]$DryRun,
    [string[]]$DecisionTiers = @('tiny','weak','mid'),
    [string]$GenTier = 'mid',
    [double]$FrontierThreshold = 0.5,
    [int]$MaxObservationChars = 600,
    [int]$MaxTranscriptChars = 4000,
    [double]$Temperature = 0.0,
    [int]$Seed = 42,
    [int]$MaxTokens = 512,
    [string]$ToolsPath,
    [string]$Tools,
    [string]$EscalatorPath,
    [string]$GatewayPath,
    [string]$Registry,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [int]$LoadTimeoutSec,
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'agent.local'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[agent.local] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
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
# Resolve a child entrypoint: an -Override leaf wins; else module-relative to this skill; else repo-relative.
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
# Resolve a tool/registry entrypoint that may be absolute, repo-relative (modules/..), or module-relative (..\..).
function Resolve-EntryPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if ([System.IO.Path]::IsPathRooted($p)) { if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path } ; return $null }
    $root = Resolve-RepoRoot $PSScriptRoot
    if ($null -ne $root) {
        $c = Join-Path $root $p
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    $c2 = Join-Path $PSScriptRoot $p
    if (Test-Path -LiteralPath $c2 -PathType Leaf) { return (Resolve-Path -LiteralPath $c2).Path }
    return $null
}
# Run a child pwsh entrypoint (-InputsJson / -ArtifactRoot) and return its parsed lifeorch envelope.
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
function Get-ChildErrCode($env) {
    if ($null -ne $env -and (Has $env 'error') -and $null -ne $env.error) { return [string](Prop $env.error 'code' 'child_error') }
    return 'child_error'
}
# Extract the first brace-matched {...} JSON object from arbitrary model text (skips prose/fences).
function Get-FirstJsonObject([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $start = $text.IndexOf('{')
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $start; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($ch -ceq '\') { $esc = $true }
            elseif ($ch -ceq '"') { $inStr = $false }
        } else {
            if ($ch -ceq '"') { $inStr = $true }
            elseif ($ch -ceq '{') { $depth++ }
            elseif ($ch -ceq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start, $i - $start + 1) } }
        }
    }
    return $null
}
function Limit-Text([string]$s, [int]$n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0, $n) + " ...[+$($s.Length - $n) chars]"
}
# Build a bounded, human-readable observation string from a child tool's envelope.
function Get-Observation($env, [string]$skillId, [int]$max) {
    if ($null -eq $env) { return 'no result' }
    $st = [string](Prop $env 'status' 'unknown')
    if (-not (Has $env 'result') -or $null -eq $env.result) { return (Limit-Text "status=$st" $max) }
    $r = $env.result
    $parts = New-Object System.Collections.Generic.List[string]
    switch -Wildcard ($skillId) {
        'doc.io' {
            $op = [string](Prop $r 'op' '')
            $parts.Add("op=$op")
            if (Has $r 'path') { $parts.Add("path=$([string](Prop $r 'path' ''))") }
            if ((Has $r 'file') -and $null -ne $r.file) { $parts.Add("lines=$([string](Prop $r.file 'line_count' '?')) sha256=$([string](Prop $r.file 'sha256' ''))") }
            if ($op -eq 'read' -and (Has $r 'content')) { $parts.Add("content=<<" + (Limit-Text ([string]$r.content) ([Math]::Max(80, $max - 80))) + ">>") }
            elseif ($op -eq 'edit')   { $parts.Add("replacements=$([string](Prop $r 'replacements' '?'))") }
            elseif ($op -eq 'write')  { $parts.Add("bytes_written=$([string](Prop $r 'bytes_written' '?'))") }
            elseif ($op -eq 'append') { $parts.Add("bytes_appended=$([string](Prop $r 'bytes_appended' '?'))") }
        }
        'fs.observer' {
            $parts.Add("root=$([string](Prop $r 'root' ''))")
            $parts.Add("files=$([string](Prop $r 'file_count' '?')) dirs=$([string](Prop $r 'dir_count' '?')) entries=$([string](Prop $r 'entry_count' '?'))")
            if (Has $r 'match_count') { $parts.Add("matches=$([string](Prop $r 'match_count' 0))") }
            if ((Has $r 'matches') -and $null -ne $r.matches) {
                $names = @(@($r.matches) | Select-Object -First 12 | ForEach-Object { if ($_ -is [string]) { $_ } else { [string](Prop $_ 'name' (Prop $_ 'path' '')) } })
                if ($names.Count -gt 0) { $parts.Add("match_names=[" + ($names -join ', ') + "]") }
            }
        }
        default {
            $parts.Add("result=" + (Limit-Text (($r | ConvertTo-Json -Compress -Depth 6)) ([Math]::Max(120, $max - 40))))
        }
    }
    return (Limit-Text ("status=$st; " + ($parts -join '; ')) $max)
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null
$modelProvenance = New-Object System.Collections.Generic.List[object]
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$steps = New-Object System.Collections.Generic.List[object]

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null; $toolsInline = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'goal')                 -and -not $bound.ContainsKey('Goal'))                { $Goal = [string]$p.goal }
            if ((Has $p 'working_dir')           -and -not $bound.ContainsKey('WorkingDir'))          { $WorkingDir = [string]$p.working_dir }
            if ((Has $p 'max_steps')             -and -not $bound.ContainsKey('MaxSteps'))            { $MaxSteps = [int]$p.max_steps }
            if ((Has $p 'dry_run')               -and -not $bound.ContainsKey('DryRun'))              { if ([bool]$p.dry_run) { $DryRun = [switch]$true } }
            if ((Has $p 'decision_tiers')        -and -not $bound.ContainsKey('DecisionTiers'))       { $DecisionTiers = @($p.decision_tiers | ForEach-Object { [string]$_ }) }
            if ((Has $p 'gen_tier')              -and -not $bound.ContainsKey('GenTier'))             { $GenTier = [string]$p.gen_tier }
            if ((Has $p 'frontier_threshold')    -and -not $bound.ContainsKey('FrontierThreshold'))   { $FrontierThreshold = [double]$p.frontier_threshold }
            if ((Has $p 'max_observation_chars') -and -not $bound.ContainsKey('MaxObservationChars')) { $MaxObservationChars = [int]$p.max_observation_chars }
            if ((Has $p 'max_transcript_chars')  -and -not $bound.ContainsKey('MaxTranscriptChars'))  { $MaxTranscriptChars = [int]$p.max_transcript_chars }
            if ((Has $p 'temperature')           -and -not $bound.ContainsKey('Temperature'))         { $Temperature = [double]$p.temperature }
            if ((Has $p 'seed')                  -and -not $bound.ContainsKey('Seed'))                { $Seed = [int]$p.seed }
            if ((Has $p 'max_tokens')            -and -not $bound.ContainsKey('MaxTokens'))           { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'tools_path')            -and -not $bound.ContainsKey('ToolsPath'))           { $ToolsPath = [string]$p.tools_path }
            if  (Has $p 'tools')                 { $toolsInline = $p.tools }
            if ((Has $p 'escalator_path')        -and -not $bound.ContainsKey('EscalatorPath'))       { $EscalatorPath = [string]$p.escalator_path }
            if ((Has $p 'gateway_path')          -and -not $bound.ContainsKey('GatewayPath'))         { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'registry')              -and -not $bound.ContainsKey('Registry'))            { $Registry = [string]$p.registry }
            if ((Has $p 'pwsh_path')             -and -not $bound.ContainsKey('PwshPath'))            { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'load_timeout_s')        -and -not $bound.ContainsKey('LoadTimeoutSec'))      { $LoadTimeoutSec = [int]$p.load_timeout_s }
            if ((Has $p 'review_queue_path')     -and -not $bound.ContainsKey('ReviewQueuePath'))     { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    if ($bound.ContainsKey('Tools') -and -not [string]::IsNullOrWhiteSpace($Tools)) {
        try { $toolsInline = $Tools | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_tools_json'; message='-Tools is not valid JSON'; retryable=$false } }
    }

    if ([string]::IsNullOrWhiteSpace($Goal)) { throw [PSCustomObject]@{ code='missing_parameter'; message='goal is required'; retryable=$false } }
    if ($MaxSteps -lt 1) { throw [PSCustomObject]@{ code='invalid_argument'; message='max_steps must be >= 1'; retryable=$false } }

    # ---- resolve working dir (advisory + relative-path base) ----
    $workDirResolved = $null
    if (-not [string]::IsNullOrWhiteSpace($WorkingDir)) {
        try { if (Test-Path -LiteralPath $WorkingDir -PathType Container) { $workDirResolved = (Resolve-Path -LiteralPath $WorkingDir).Path } else { $workDirResolved = $WorkingDir } } catch { $workDirResolved = $WorkingDir }
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $childReviewPath = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $ReviewQueuePath } else { Join-Path $invDir 'child_review.jsonl' }
    $reviewMode = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { 'redirected_explicit' } else { 'redirected_in_artifact' }

    # ---- load the tool registry ----
    $toolsObj = $null
    if ($null -ne $toolsInline) {
        $toolsObj = $toolsInline
    } else {
        $tp = if (-not [string]::IsNullOrWhiteSpace($ToolsPath)) { $ToolsPath } else { Join-Path $PSScriptRoot 'tools.json' }
        if (-not (Test-Path -LiteralPath $tp -PathType Leaf)) { throw [PSCustomObject]@{ code='tools_registry_not_found'; message="tools registry not found: $tp"; retryable=$false } }
        try { $toolsObj = (Get-Content -LiteralPath $tp -Raw) | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_tools_registry'; message="tools registry is not valid JSON: $($_.Exception.Message)"; retryable=$false } }
    }
    # accept either a bare array or {tools:[...]}
    $toolList = @()
    if ($toolsObj -is [System.Array]) { $toolList = @($toolsObj) }
    elseif (Has $toolsObj 'tools') { $toolList = @($toolsObj.tools) }
    else { throw [PSCustomObject]@{ code='invalid_tools_registry'; message='tools registry must be an array or {tools:[...]}'; retryable=$false } }
    if (@($toolList).Count -lt 1) { throw [PSCustomObject]@{ code='no_tools'; message='the tool registry is empty'; retryable=$false } }

    # normalize + resolve each tool  (NB: not $tools -- that name collides case-insensitively with the [string]$Tools param)
    $toolDefs = New-Object System.Collections.Generic.List[object]
    foreach ($t in $toolList) {
        $name = [string](Prop $t 'tool' (Prop $t 'skill_id' ''))
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $entryRel = [string](Prop $t 'entrypoint' '')
        $entry = Resolve-EntryPath $entryRel
        $toolDefs.Add([pscustomobject]@{
            tool          = $name
            skill_id      = [string](Prop $t 'skill_id' $name)
            entrypoint    = $entry
            entrypoint_raw= $entryRel
            description   = [string](Prop $t 'description' '')
            args_hint     = [string](Prop $t 'args_hint' '')
            args_example  = (Prop $t 'args_example' $null)
            required      = @((Prop $t 'required' @()) | ForEach-Object { [string]$_ })
            side_effecting= [bool](Prop $t 'side_effecting' $false)
        })
    }
    $missing = @($toolDefs | Where-Object { [string]::IsNullOrWhiteSpace($_.entrypoint) })
    foreach ($m in $missing) { $warnings.Add("tool '$($m.tool)' entrypoint not resolved: $($m.entrypoint_raw)") }
    $usableTools = @($toolDefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_.entrypoint) })
    if (@($usableTools).Count -lt 1) { throw [PSCustomObject]@{ code='no_usable_tools'; message='no tool in the registry resolved to an existing entrypoint'; retryable=$false } }

    $toolNames = @($usableTools | ForEach-Object { $_.tool })
    $labels = @($toolNames + 'finish')

    # ---- resolve the escalator + gateway entrypoints ----
    $escalatorEntry = Resolve-Child $EscalatorPath '..\19-logic-escalator\Invoke-LogicEscalator.ps1'
    if ([string]::IsNullOrWhiteSpace($escalatorEntry)) { throw [PSCustomObject]@{ code='escalator_not_found'; message='logic.escalator entrypoint not found (set -EscalatorPath)'; retryable=$false } }
    $gatewayEntry = Resolve-Child $GatewayPath '..\07-model-gateway\Invoke-ModelGateway.ps1'
    if ([string]::IsNullOrWhiteSpace($gatewayEntry)) { throw [PSCustomObject]@{ code='gateway_not_found'; message='model.gateway entrypoint not found (set -GatewayPath)'; retryable=$false } }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ goal=$Goal; working_dir=$workDirResolved; max_steps=$MaxSteps; dry_run=[bool]$DryRun;
        decision_tiers=$DecisionTiers; gen_tier=$GenTier; frontier_threshold=$FrontierThreshold;
        temperature=$Temperature; seed=$Seed; tools=$toolNames }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))

    # tool menu string for the model prompts
    $menuSb = [System.Text.StringBuilder]::new()
    foreach ($ut in $usableTools) {
        $se = if ($ut.side_effecting) { ' [writes files]' } else { ' [read-only]' }
        [void]$menuSb.AppendLine("- $($ut.tool)$se : $($ut.description)")
    }
    [void]$menuSb.AppendLine("- finish : the goal is complete (or cannot progress); produce the final answer.")
    $toolMenu = $menuSb.ToString().TrimEnd()

    # ---- shared child plumbing knobs ----
    function New-EscalatorInputs([string]$stepId, [string]$decisionText) {
        $o = [ordered]@{
            kind='classify'; labels=$labels; tiers=$DecisionTiers;
            tasks=@(@{ id=$stepId; text=$decisionText });
            frontier_threshold=$FrontierThreshold; temperature=$Temperature; seed=$Seed;
            max_input_chars=([Math]::Max(2000, $MaxTranscriptChars + 2000));
            review_queue_path=$childReviewPath; pwsh_path=$PwshPath
        }
        if (-not [string]::IsNullOrWhiteSpace($Registry)) { $o.registry = $Registry }
        if (-not [string]::IsNullOrWhiteSpace($GatewayPath)) { $o.gateway_path = $gatewayEntry }
        if ($LoadTimeoutSec -gt 0) { $o.load_timeout_s = $LoadTimeoutSec }
        return ($o | ConvertTo-Json -Compress -Depth 12)
    }
    function New-GatewayInputs([string]$system, [string]$prompt, [int]$maxTok) {
        $o = [ordered]@{
            tier=$GenTier; system=$system; prompt=$prompt;
            max_tokens=$maxTok; temperature=$Temperature; seed=$Seed;
            review_queue_path=$childReviewPath
        }
        if (-not [string]::IsNullOrWhiteSpace($Registry)) { $o.registry = $Registry }
        if ($LoadTimeoutSec -gt 0) { $o.load_timeout_s = $LoadTimeoutSec }
        return ($o | ConvertTo-Json -Compress -Depth 12)
    }
    function Get-GatewayText($env) {
        if ($null -ne $env -and (Has $env 'result') -and (Has $env.result 'output')) { return [string](Prop $env.result.output 'text' '') }
        return ''
    }

    # transcript of the run (bounded when shown to the model)
    $transcript = New-Object System.Collections.Generic.List[string]
    $transcript.Add("GOAL: $Goal")
    if (-not [string]::IsNullOrWhiteSpace($workDirResolved)) { $transcript.Add("WORKING_DIR: $workDirResolved") }

    $decisionConfs = New-Object System.Collections.Generic.List[double]
    $costDecisionCalls = 0; $costGenCalls = 0; $costToolCalls = 0
    $costGatewayCalls = 0; $costTokens = 0; $costRuntimeMs = 0
    $finished = $false; $stopReason = $null; $anyDecisionNeedsFrontier = $false

    for ($stepIdx = 1; $stepIdx -le $MaxSteps; $stepIdx++) {
        $stepId = "step-$stepIdx"
        $transWindow = Limit-Text (($transcript.ToArray()) -join "`n") $MaxTranscriptChars

        # ===== 1) DECIDE the next action THROUGH the escalator (closed-set classify) =====
        $decisionText = @(
            "You are a local task agent. Decide the SINGLE best next action for the goal.",
            "Choose exactly one action label from the allowed set.",
            "",
            "GOAL: $Goal",
            "",
            "AVAILABLE ACTIONS:",
            $toolMenu,
            "",
            "PROGRESS SO FAR:",
            $transWindow,
            "",
            "Which action should run next? Answer with one label only."
        ) -join "`n"

        $decSub = Join-Path $invDir "decision-$stepIdx"
        $decJson = New-EscalatorInputs $stepId $decisionText
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $decR = Invoke-Child $escalatorEntry $decJson $decSub
        $swS.Stop(); $costRuntimeMs += [int]$swS.Elapsed.TotalMilliseconds
        $costDecisionCalls++
        $decEnv = $decR.env

        $chosen = $null; $decConf = $null; $accTier = $null; $accVia = $null; $decNeedsFrontier = $false; $decOk = $false
        if ((Test-ChildOk $decEnv) -and (Has $decEnv 'result') -and (Has $decEnv.result 'tasks')) {
            $tasksArr = @($decEnv.result.tasks)
            $t0 = if ($tasksArr.Count -gt 0) { $tasksArr[0] } else { $null }
            if ($null -ne $t0) {
                $chosen = [string](Prop $t0 'answer' $null)
                if (Has $t0 'confidence') { $decConf = (Prop $t0 'confidence' $null) }
                $accTier = [string](Prop $t0 'accepted_tier' $null)
                $accVia = [string](Prop $t0 'accepted_via' $null)
                $decNeedsFrontier = [bool](Prop $t0 'needs_frontier' $false)
                $decOk = $true
            }
            Add-Provenance $modelProvenance $decEnv "decision-$stepIdx"
            if (Has $decEnv.result 'cost') { $costGatewayCalls += [int](Prop $decEnv.result.cost 'total_gateway_calls' 0); $costTokens += [int](Prop $decEnv.result.cost 'total_tokens' 0) }
        }
        if ($null -ne $decConf) { $decisionConfs.Add([double]$decConf) }
        if ($decNeedsFrontier) { $anyDecisionNeedsFrontier = $true }

        # validate the chosen label is in-set (the escalator's gate should guarantee this)
        $isFinish = ($null -ne $chosen -and $chosen -eq 'finish')
        $chosenTool = $null
        if (-not $isFinish -and $null -ne $chosen) {
            $match = @($usableTools | Where-Object { $_.tool -eq $chosen })
            if ($match.Count -gt 0) { $chosenTool = $match[0] }
        }

        $stepRec = [ordered]@{
            index = $stepIdx
            decision = [ordered]@{ chosen_tool=$chosen; confidence=$decConf; accepted_tier=$accTier; accepted_via=$accVia; needs_frontier=$decNeedsFrontier; ok=$decOk }
            args = $null
            args_raw = $null
            tool = [ordered]@{ skill_id=$null; invoked=$false; status=$null; error=$null; artifact_dir=$null }
            observation = $null
            error = $null
        }

        if (-not $decOk) {
            $stepRec.error = "decision_failed: escalator produced no usable verdict ($(if($null -ne $decEnv){Get-ChildErrCode $decEnv}else{'no_envelope'}))"
            $transcript.Add("STEP ${stepIdx}: decision failed; stopping.")
            $steps.Add([pscustomobject]$stepRec)
            $stopReason = 'decision_failed'; $anyDecisionNeedsFrontier = $true
            Write-Diag "step $stepIdx decision failed: $($decR.err)"
            break
        }

        Write-Diag "step $stepIdx decision -> '$chosen' (tier=$accTier via=$accVia conf=$decConf frontier=$decNeedsFrontier)"

        # ===== finish? =====
        if ($isFinish) {
            $transcript.Add("STEP ${stepIdx}: decided to FINISH.")
            $steps.Add([pscustomobject]$stepRec)
            $finished = $true; $stopReason = 'finish'
            break
        }
        if ($null -eq $chosenTool) {
            # escalator returned a label that is not a known tool nor finish (should not happen with the in-set gate)
            $stepRec.error = "unknown_tool: '$chosen' is not a registered tool"
            $transcript.Add("STEP ${stepIdx}: chosen action '$chosen' is not a known tool; stopping.")
            $steps.Add([pscustomobject]$stepRec)
            $stopReason = 'unknown_tool'; $anyDecisionNeedsFrontier = $true
            break
        }

        # ===== 2) GENERATE the tool arguments via the gateway =====
        $exampleStr = if ($null -ne $chosenTool.args_example) { ($chosenTool.args_example | ConvertTo-Json -Compress -Depth 8) } else { '{}' }
        $reqStr = if (@($chosenTool.required).Count -gt 0) { ($chosenTool.required -join ', ') } else { '(none listed)' }
        $argSystem = "You produce arguments for a tool call. Output ONLY a single JSON object and nothing else (no prose, no code fences)."
        $argPrompt = @(
            "GOAL: $Goal",
            $(if (-not [string]::IsNullOrWhiteSpace($workDirResolved)) { "WORKING_DIR: $workDirResolved (use paths under here; a bare filename is fine)" } else { "" }),
            "",
            "TOOL: $($chosenTool.tool)  (skill_id=$($chosenTool.skill_id))",
            "TOOL PURPOSE: $($chosenTool.description)",
            "ARGUMENT GUIDE: $($chosenTool.args_hint)",
            "REQUIRED ARGUMENTS: $reqStr",
            "EXAMPLE ARGUMENTS: $exampleStr",
            "",
            "PROGRESS SO FAR:",
            $transWindow,
            "",
            "Output the JSON arguments object for the '$($chosenTool.tool)' tool to make progress on the goal now."
        ) -join "`n"

        $argSub = Join-Path $invDir "arggen-$stepIdx"
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $argR = Invoke-Child $gatewayEntry (New-GatewayInputs $argSystem $argPrompt $MaxTokens) $argSub
        $swS.Stop(); $costRuntimeMs += [int]$swS.Elapsed.TotalMilliseconds
        $costGenCalls++; $costGatewayCalls++
        $argEnv = $argR.env
        Add-Provenance $modelProvenance $argEnv "arggen-$stepIdx"
        if ($null -ne $argEnv -and (Has $argEnv 'result') -and (Has $argEnv.result 'generation')) { $costTokens += [int](Prop $argEnv.result.generation 'total_tokens' 0) }
        $argText = Get-GatewayText $argEnv
        $stepRec.args_raw = Limit-Text $argText 1200
        $argJsonStr = Get-FirstJsonObject $argText
        $argObj = $null
        if ($null -ne $argJsonStr) { try { $argObj = $argJsonStr | ConvertFrom-Json } catch { $argObj = $null } }

        if ($null -eq $argObj) {
            $stepRec.error = 'arg_parse_failed: the model did not return a valid JSON arguments object'
            $transcript.Add("STEP ${stepIdx}: chose '$chosen' but produced no valid arguments; skipping the tool.")
            $steps.Add([pscustomobject]$stepRec)
            Write-Diag "step $stepIdx arg parse failed; raw='$(Limit-Text $argText 200)'"
            continue
        }

        # resolve relative path-like args against working_dir
        $argHash = [ordered]@{}
        foreach ($pn in $argObj.PSObject.Properties.Name) {
            $val = $argObj.$pn
            if ($val -is [string] -and -not [string]::IsNullOrWhiteSpace($workDirResolved) -and
                (@('path','input','output','out','file','dest','destination') -contains $pn.ToLowerInvariant()) -and
                -not [System.IO.Path]::IsPathRooted([string]$val)) {
                $val = Join-Path $workDirResolved ([string]$val)
            }
            $argHash[$pn] = $val
        }
        $stepRec.args = $argHash

        # ===== 3) INVOKE the tool (unless dry-run) =====
        $stepRec.tool.skill_id = $chosenTool.skill_id
        if ($DryRun) {
            $stepRec.tool.invoked = $false
            $stepRec.tool.status = 'dry_run'
            $obs = "[dry-run] would invoke $($chosenTool.tool) with args: " + ($argHash | ConvertTo-Json -Compress -Depth 8)
            $stepRec.observation = Limit-Text $obs $MaxObservationChars
            $transcript.Add("STEP ${stepIdx}: [dry-run] $($chosenTool.tool) args=" + (Limit-Text ($argHash | ConvertTo-Json -Compress -Depth 8) 300))
            $steps.Add([pscustomobject]$stepRec)
            continue
        }

        # pass a child review sink for tools that accept it (harmless extra key for those that ignore it)
        if (-not $argHash.Contains('review_queue_path')) { $argHash['review_queue_path'] = $childReviewPath }
        $toolSub = Join-Path $invDir "tool-$stepIdx"
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $toolR = Invoke-Child $chosenTool.entrypoint ($argHash | ConvertTo-Json -Compress -Depth 12) $toolSub
        $swS.Stop(); $costRuntimeMs += [int]$swS.Elapsed.TotalMilliseconds
        $costToolCalls++
        $toolEnv = $toolR.env
        Add-Provenance $modelProvenance $toolEnv "tool-$stepIdx"
        $stepRec.tool.invoked = $true
        $stepRec.tool.artifact_dir = $toolSub

        if (Test-ChildOk $toolEnv) {
            $stepRec.tool.status = [string](Prop $toolEnv 'status' 'ok')
            $obs = Get-Observation $toolEnv $chosenTool.skill_id $MaxObservationChars
            $stepRec.observation = $obs
            $transcript.Add("STEP ${stepIdx}: ran $($chosenTool.tool) -> $obs")
            Write-Diag "step $stepIdx tool $($chosenTool.skill_id) ok"
        } else {
            $ec = if ($null -ne $toolEnv) { Get-ChildErrCode $toolEnv } else { 'no_envelope' }
            $stepRec.tool.status = if ($null -ne $toolEnv -and (Has $toolEnv 'status')) { [string]$toolEnv.status } else { 'error' }
            $stepRec.tool.error = $ec
            $obs = "tool $($chosenTool.tool) FAILED: $ec"
            $stepRec.observation = Limit-Text $obs $MaxObservationChars
            $transcript.Add("STEP ${stepIdx}: $obs")
            Write-Diag "step $stepIdx tool FAILED: $ec -- $(Limit-Text $toolR.err 300)"
        }
        $steps.Add([pscustomobject]$stepRec)
    }

    if (-not $finished -and $null -eq $stopReason) { $stopReason = 'max_steps' }

    # ===== FINAL ANSWER via the gateway =====
    $finalAnswer = $null
    $transWindowF = Limit-Text (($transcript.ToArray()) -join "`n") $MaxTranscriptChars
    $ansSystem = "You are a local task agent. Write a brief, plain final answer for the user. No preamble."
    $ansPrompt = @(
        "GOAL: $Goal",
        "",
        "STEPS TAKEN:",
        $transWindowF,
        "",
        $(if ($finished) { "The agent decided the goal is complete. Summarize what was accomplished in 1-3 sentences." }
          elseif ($stopReason -eq 'max_steps') { "The step budget was reached before finishing. State what was done and what still remains, in 1-3 sentences." }
          else { "The agent stopped early ($stopReason). State what was done and why it stopped, in 1-3 sentences." })
    ) -join "`n"
    $finSub = Join-Path $invDir 'final'
    $swS = [System.Diagnostics.Stopwatch]::StartNew()
    $finR = Invoke-Child $gatewayEntry (New-GatewayInputs $ansSystem $ansPrompt ([Math]::Max(128, [Math]::Min($MaxTokens, 384)))) $finSub
    $swS.Stop(); $costRuntimeMs += [int]$swS.Elapsed.TotalMilliseconds
    $costGenCalls++; $costGatewayCalls++
    $finEnv = $finR.env
    Add-Provenance $modelProvenance $finEnv 'final'
    if ($null -ne $finEnv -and (Has $finEnv 'result') -and (Has $finEnv.result 'generation')) { $costTokens += [int](Prop $finEnv.result.generation 'total_tokens' 0) }
    if (Test-ChildOk $finEnv) { $finalAnswer = (Get-GatewayText $finEnv).Trim() }
    if ([string]::IsNullOrWhiteSpace($finalAnswer)) { $finalAnswer = if ($finished) { 'Goal completed.' } else { "Stopped ($stopReason) after $($steps.Count) step(s)." } }

    # ===== status + needs_frontier + confidence =====
    $runStatus = if ($finished) { 'completed' } elseif ($stopReason -eq 'max_steps') { 'stopped' } else { 'stopped' }
    $needsFrontier = ($runStatus -ne 'completed') -or $anyDecisionNeedsFrontier
    if ($decisionConfs.Count -gt 0) { $confidence = ($decisionConfs.ToArray() | Measure-Object -Minimum).Minimum } else { $confidence = $null }

    # child review count (in-artifact aggregate only)
    $childReviewCount = 0
    if (Test-Path -LiteralPath $childReviewPath -PathType Leaf) {
        try { $childReviewCount = @(Get-Content -LiteralPath $childReviewPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }).Count } catch { }
    }

    $result = [ordered]@{
        goal = $Goal
        working_dir = $workDirResolved
        status = $runStatus
        final_answer = $finalAnswer
        needs_frontier = $needsFrontier
        stop_reason = $stopReason
        step_count = $steps.Count
        max_steps = $MaxSteps
        dry_run = [bool]$DryRun
        tools_available = @($usableTools | ForEach-Object { [ordered]@{ tool=$_.tool; skill_id=$_.skill_id; side_effecting=$_.side_effecting } })
        steps = $steps.ToArray()
        cost = [ordered]@{ decision_calls=$costDecisionCalls; gen_calls=$costGenCalls; tool_calls=$costToolCalls;
            total_gateway_calls=$costGatewayCalls; total_tokens=$costTokens; total_runtime_ms=$costRuntimeMs }
        decision_tiers = $DecisionTiers
        gen_tier = $GenTier
        review = [ordered]@{ mode=$reviewMode; child_review_path=$childReviewPath; child_review_count=$childReviewCount; is_producer=$false }
        is_review_producer = $false
        child_reviews_redirected_to = $childReviewPath
    }
    if ($warnings.Count -gt 0 -and $status -eq 'ok') { $status = 'partial' }
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code=[string]$ex.code; message=[string]$ex.message; retryable=[bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts: agent.json + agent.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $aj = [ordered]@{ schema='lifeorch.agent.run/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            goal=$result.goal; working_dir=$result.working_dir; status=$result.status; final_answer=$result.final_answer;
            needs_frontier=$result.needs_frontier; stop_reason=$result.stop_reason; step_count=$result.step_count;
            max_steps=$result.max_steps; dry_run=$result.dry_run; tools_available=$result.tools_available;
            steps=$result.steps; cost=$result.cost; decision_tiers=$result.decision_tiers; gen_tier=$result.gen_tier;
            review=$result.review; model_provenance=$modelProvenance.ToArray() }
        $ajPath = Join-Path $invDir 'agent.json'
        [System.IO.File]::WriteAllText($ajPath, ($aj | ConvertTo-Json -Depth 30), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# agent.local run")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("**Goal:** $($result.goal)")
        if (-not [string]::IsNullOrWhiteSpace([string]$result.working_dir)) { [void]$mb.AppendLine("**Working dir:** $($result.working_dir)") }
        [void]$mb.AppendLine("**Status:** $($result.status)   **stop:** $($result.stop_reason)   **steps:** $($result.step_count)/$($result.max_steps)   **needs_frontier:** $($result.needs_frontier)   **dry_run:** $($result.dry_run)")
        [void]$mb.AppendLine("**Tools:** " + (@($result.tools_available | ForEach-Object { $_.tool }) -join ', '))
        [void]$mb.AppendLine('')
        foreach ($st in @($result.steps)) {
            $d = $st.decision
            [void]$mb.AppendLine("## Step $($st.index): $($d.chosen_tool)")
            [void]$mb.AppendLine("- decision: tier=$($d.accepted_tier) via=$($d.accepted_via) conf=$($d.confidence) needs_frontier=$($d.needs_frontier)")
            if ($null -ne $st.args) { [void]$mb.AppendLine("- args: " + ($st.args | ConvertTo-Json -Compress -Depth 8)) }
            if ($null -ne $st.tool -and $null -ne $st.tool.status) { [void]$mb.AppendLine("- tool: $($st.tool.skill_id) status=$($st.tool.status)" + $(if ($st.tool.error) { " error=$($st.tool.error)" } else { '' })) }
            if ($null -ne $st.observation) { [void]$mb.AppendLine("- observation: $($st.observation)") }
            if ($null -ne $st.error) { [void]$mb.AppendLine("- error: $($st.error)") }
            [void]$mb.AppendLine('')
        }
        [void]$mb.AppendLine("## Final answer")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine([string]$result.final_answer)
        [void]$mb.AppendLine('')
        $amPath = Join-Path $invDir 'agent.md'
        [System.IO.File]::WriteAllText($amPath, $mb.ToString(), $utf8)

        foreach ($a in @([pscustomobject]@{ p=$ajPath; k='json' }, [pscustomobject]@{ p=$amPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [byte[]]([System.IO.File]::ReadAllBytes($a.p))
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[agent.local] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$confidence; artifacts=$artifacts; model_provenance=$modelProvenance.ToArray()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir; child_reviews_redirected_to=$(if ($result) { $result.child_reviews_redirected_to } else { $null }) }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
