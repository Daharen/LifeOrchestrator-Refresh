#requires -Version 7.0
<#
.SYNOPSIS
  logic.escalator -- the Local Logic Escalator (Life Orchestrator, contract v0.2).
.DESCRIPTION
  Runs an escalating ladder of local model tiers (tiny 0.5B -> weak 1.5B -> mid 3B -> strong 27B, all via
  model.gateway #7) over a batch of tasks. The weakest tier ANSWERS a task; each higher tier JUDGES the
  current answer and either ACCEPTs it (stop -- the accepted layer is the tier that produced the current
  answer) or REJECTs it and produces its own answer for the next tier to judge; the top tier's answer is
  accepted if the ladder is exhausted.

  Every rung is anchored with DETERMINISTIC ground-truth gates so the ladder never rests on LLM-judges-LLM
  alone (D-0029 guardrail 1):
    - classify (closed set): in-set membership (HARD gate) + self-consistency across K samples.
    - extract (named fields): JSON schema validity + all required fields present (HARD) + source grounding.
    - generic (freeform): no deterministic gate (ungated) + self-consistency (exact match) only.
  A deterministic HARD-FAIL is authoritative for REJECT (it overrides an LLM-judge ACCEPT -- the defense
  against two too-weak tiers rubber-stamping each other). Strong self-consistency + hard-pass is
  authoritative for ACCEPT (a deterministic short-circuit with no judge call -- the cost saver for easy
  tasks). The LLM judge decides accept-vs-escalate only among deterministically-valid answers.

  It is an ORCHESTRATOR, not a review-queue producer: it suppresses the child gateway's own review writes to
  an in-artifact file and surfaces `needs_frontier` per task as a status field in its own result; it never
  writes the canonical review_queue.jsonl (scope: NOT extending review.processor's queue writes).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes escalation.json +
  escalation.md + result.json + stderr.txt. Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-LogicEscalator.ps1 -InputsJson '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid"],"tasks":[{"id":"a","text":"a golden retriever puppy"}]}'
#>
[CmdletBinding()]
param(
    [string]$Kind = 'classify',
    [object]$Tasks,
    [string]$TasksPath,
    [object]$Labels,
    [object]$Fields,
    [object]$Tiers,
    [int]$Samples = 1,
    [double]$SampleTemperature = 0.7,
    [double]$AcceptConsistency = 1.0,
    [double]$FrontierThreshold = 0.5,
    [int]$MaxTokens = 0,
    [double]$Temperature = 0.0,
    [int]$Seed = 42,
    [int]$MaxInputChars = 2000,
    [int]$LoadTimeoutSec = 0,
    [int]$GpuLayers = -1,
    [string]$Registry,
    [string]$GatewayPath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'logic.escalator'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[logic.escalator] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-RepoRoot([string]$start) {
    try {
        $d = Get-Item -LiteralPath $start
        for ($i = 0; $i -lt 10 -and $null -ne $d; $i++) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'core-docs')) { return $d.FullName }
            $d = $d.Parent
        }
    } catch { }
    return $null
}
function Get-Cap([string]$s, [int]$n) { if ($null -eq $s) { return '' }; if ($s.Length -gt $n) { return $s.Substring(0, $n) }; return $s }
# Normalize a tier alias: strip surrounding quotes/space (native array-arg passing to pwsh -File can wrap
# each element in literal quotes on Windows) and casefold.
function Clean-Tier([string]$s) { if ($null -eq $s) { return '' }; return ($s.Trim().Trim([char[]]@([char]39,[char]34)).Trim().ToLowerInvariant()) }
function Get-NormToken([string]$s) {
    if ($null -eq $s) { return '' }
    $t = $s.Trim()
    $t = $t -replace '^```[a-zA-Z]*','' -replace '```$',''
    $t = $t.Trim()
    $t = $t -replace '^(label|category|answer|class|result)\s*[:\-]\s*',''
    $trimChars = [char[]]('"',"'",[char]0x201C,[char]0x201D,[char]0x2018,[char]0x2019,'.',',',';',':','!','?','(',')','[',']','{','}','*','-','_',' ',"`t")
    $t = $t.Trim().Trim($trimChars)
    return $t.ToLowerInvariant().Trim()
}
function Get-FirstJsonObject([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $start = $s.IndexOf('{')
    if ($start -lt 0) { return $null }
    $depth = 0
    for ($i = $start; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $s.Substring($start, $i - $start + 1) } }
    }
    return $null
}

# fatal (pass-level) gateway error codes: if the FIRST call hits one, nothing can run -- abort.
$FATAL_GW_CODES = @('model_not_found','model_not_wired','tier_not_found','registry_not_found','no_model_selected','engine_not_found','unsupported_type','unsupported_engine','model_file_missing')

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @()
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

# per-tier provenance accumulators (populated during the run)
$script:tierAcc = [ordered]@{}      # tierAlias -> { calls, pt, ct, tt, rt, model }
$script:totalCalls = 0
$script:aborted = $false; $script:abortCode = $null; $script:abortMsg = $null

try {
    # ---- merge -InputsJson (named params win where explicitly set on the command line) ----
    $bound = $PSBoundParameters
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'kind')                -and -not $bound.ContainsKey('Kind'))               { $Kind = [string]$p.kind }
            if ((Has $p 'tasks')               -and -not $bound.ContainsKey('Tasks'))              { $Tasks = $p.tasks }
            if ((Has $p 'tasks_path')          -and -not $bound.ContainsKey('TasksPath'))          { $TasksPath = [string]$p.tasks_path }
            if ((Has $p 'labels')              -and -not $bound.ContainsKey('Labels'))             { $Labels = $p.labels }
            if ((Has $p 'fields')              -and -not $bound.ContainsKey('Fields'))             { $Fields = $p.fields }
            if ((Has $p 'tiers')               -and -not $bound.ContainsKey('Tiers'))              { $Tiers = $p.tiers }
            if ((Has $p 'samples')             -and -not $bound.ContainsKey('Samples'))            { $Samples = [int]$p.samples }
            if ((Has $p 'sample_temperature')  -and -not $bound.ContainsKey('SampleTemperature'))  { $SampleTemperature = [double]$p.sample_temperature }
            if ((Has $p 'accept_consistency')  -and -not $bound.ContainsKey('AcceptConsistency'))  { $AcceptConsistency = [double]$p.accept_consistency }
            if ((Has $p 'frontier_threshold')  -and -not $bound.ContainsKey('FrontierThreshold'))  { $FrontierThreshold = [double]$p.frontier_threshold }
            if ((Has $p 'max_tokens')          -and -not $bound.ContainsKey('MaxTokens'))          { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'temperature')         -and -not $bound.ContainsKey('Temperature'))        { $Temperature = [double]$p.temperature }
            if ((Has $p 'seed')                -and -not $bound.ContainsKey('Seed'))               { $Seed = [int]$p.seed }
            if ((Has $p 'max_input_chars')     -and -not $bound.ContainsKey('MaxInputChars'))      { $MaxInputChars = [int]$p.max_input_chars }
            if ((Has $p 'load_timeout_s')      -and -not $bound.ContainsKey('LoadTimeoutSec'))     { $LoadTimeoutSec = [int]$p.load_timeout_s }
            if ((Has $p 'gpu_layers')          -and -not $bound.ContainsKey('GpuLayers'))          { $GpuLayers = [int]$p.gpu_layers }
            if ((Has $p 'registry')            -and -not $bound.ContainsKey('Registry'))           { $Registry = [string]$p.registry }
            if ((Has $p 'gateway_path')        -and -not $bound.ContainsKey('GatewayPath'))        { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'pwsh_path')           -and -not $bound.ContainsKey('PwshPath'))           { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path')   -and -not $bound.ContainsKey('ReviewQueuePath'))    { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate kind ----
    $Kind = ([string]$Kind).Trim().ToLowerInvariant()
    if (@('classify','extract','generic') -notcontains $Kind) {
        throw [PSCustomObject]@{ code = 'invalid_kind'; message = "kind must be classify|extract|generic (got '$Kind')"; retryable = $false }
    }
    if ($Samples -lt 1) { $Samples = 1 }

    # ---- resolve the tier ladder ----
    $tierList = @()
    if ($null -ne $Tiers) { $tierList = @(@($Tiers) | ForEach-Object { Clean-Tier ([string]$_) }) }
    if ($tierList.Count -eq 1 -and ([string]$tierList[0]).Contains(',')) { $tierList = @(([string]$tierList[0]) -split ',' | ForEach-Object { Clean-Tier $_ }) }
    $tierList = @($tierList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($tierList.Count -lt 1) { $tierList = @('tiny','weak','mid','strong') }

    # ---- resolve shared label / field schema ----
    function ConvertTo-Names([object]$raw) {
        $acc = New-Object System.Collections.Generic.List[string]
        foreach ($e in @($raw)) {
            if ($null -eq $e) { continue }
            if ($e -is [string]) { $acc.Add([string]$e); continue }
            if (Has $e 'name') { $acc.Add([string]$e.name) }
        }
        return $acc.ToArray()
    }
    $sharedLabels = @(ConvertTo-Names $Labels)
    $sharedFields = @(ConvertTo-Names $Fields)

    # ---- resolve tasks ----
    $rawTasks = @()
    if ($null -ne $Tasks) { $rawTasks = @($Tasks) }
    elseif (-not [string]::IsNullOrWhiteSpace($TasksPath)) {
        if (-not (Test-Path -LiteralPath $TasksPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'tasks_file_not_found'; message = "tasks_path not found: $TasksPath"; retryable = $false } }
        $rawText = Get-Content -LiteralPath $TasksPath -Raw
        $trimmed = $rawText.TrimStart()
        try {
            if ($trimmed.StartsWith('[')) { $rawTasks = @(($rawText | ConvertFrom-Json)) }
            elseif ($trimmed.StartsWith('{')) {
                $obj = $rawText | ConvertFrom-Json
                if (Has $obj 'tasks') { $rawTasks = @($obj.tasks) } else { $rawTasks = @($obj) }
                if ((Has $obj 'labels') -and $sharedLabels.Count -eq 0) { $sharedLabels = @(ConvertTo-Names $obj.labels) }
                if ((Has $obj 'fields') -and $sharedFields.Count -eq 0) { $sharedFields = @(ConvertTo-Names $obj.fields) }
                if ((Has $obj 'kind') -and -not $bound.ContainsKey('Kind') -and [string]::IsNullOrWhiteSpace($InputsJson)) { $Kind = [string]$obj.kind }
            }
            else { $rawTasks = @($rawText -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json }) }
        } catch { throw [PSCustomObject]@{ code = 'tasks_parse_error'; message = "could not parse tasks_path ($TasksPath): $($_.Exception.Message)"; retryable = $false } }
    }
    # normalize each task -> { id, text, labels, fields }
    $taskList = New-Object System.Collections.Generic.List[object]
    $ti = 0
    foreach ($rt in $rawTasks) {
        $id = $null; $text = $null; $tl = @(); $tf = @()
        if ($rt -is [string]) { $text = [string]$rt }
        elseif ($null -ne $rt) {
            if (Has $rt 'text') { $text = [string]$rt.text }
            elseif (Has $rt 'prompt') { $text = [string]$rt.prompt }
            elseif (Has $rt 'content') { $text = [string]$rt.content }
            if (Has $rt 'id') { $id = [string]$rt.id }
            if (Has $rt 'labels') { $tl = @(ConvertTo-Names $rt.labels) }
            if (Has $rt 'fields') { $tf = @(ConvertTo-Names $rt.fields) }
        }
        if ([string]::IsNullOrWhiteSpace($id)) { $id = "task-$ti" }
        if ($tl.Count -eq 0) { $tl = $sharedLabels }
        if ($tf.Count -eq 0) { $tf = $sharedFields }
        $taskList.Add([ordered]@{ id = $id; text = $text; labels = $tl; fields = $tf })
        $ti++
    }
    if ($taskList.Count -lt 1) { throw [PSCustomObject]@{ code = 'no_tasks'; message = "provide -Tasks (array) or -TasksPath (a non-empty file)"; retryable = $false } }
    if ($Kind -eq 'classify' -and $sharedLabels.Count -lt 1 -and (@($taskList.ToArray() | Where-Object { @($_.labels).Count -lt 1 }).Count -gt 0)) {
        throw [PSCustomObject]@{ code = 'no_labels'; message = "classify kind requires -Labels (shared) or per-task labels"; retryable = $false }
    }
    if ($Kind -eq 'extract' -and $sharedFields.Count -lt 1 -and (@($taskList.ToArray() | Where-Object { @($_.fields).Count -lt 1 }).Count -gt 0)) {
        throw [PSCustomObject]@{ code = 'no_fields'; message = "extract kind requires -Fields (shared) or per-task fields"; retryable = $false }
    }

    # ---- resolve the gateway entrypoint ----
    if ([string]::IsNullOrWhiteSpace($GatewayPath)) {
        $cand = Join-Path $PSScriptRoot '..\07-model-gateway\Invoke-ModelGateway.ps1'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $GatewayPath = (Resolve-Path -LiteralPath $cand).Path }
        else {
            $root = Resolve-RepoRoot $PSScriptRoot
            if ($null -ne $root) { $GatewayPath = Join-Path $root 'modules\07-model-gateway\Invoke-ModelGateway.ps1' }
        }
    }
    if ([string]::IsNullOrWhiteSpace($GatewayPath) -or -not (Test-Path -LiteralPath $GatewayPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code = 'gateway_not_found'; message = "model.gateway entrypoint not found (looked near modules/07-model-gateway; set -GatewayPath). got '$GatewayPath'"; retryable = $false }
    }

    # ---- gateway plumbing (suppress the child gateway's own review writes; NOT a producer) ----
    $gwArtRoot = Join-Path $invDir 'gateway'
    $gwReviewSuppressed = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $ReviewQueuePath } else { Join-Path $invDir '_gateway_review_suppressed.jsonl' }
    New-Item -ItemType Directory -Path $gwArtRoot -Force | Out-Null

    # ---- per-mode default answer tokens ----
    $answerTokens = if ($MaxTokens -gt 0) { $MaxTokens } elseif ($Kind -eq 'extract') { 220 } elseif ($Kind -eq 'generic') { 384 } else { 24 }
    $judgeTokens  = if ($MaxTokens -gt 0) { $MaxTokens } elseif ($Kind -eq 'extract') { 260 } elseif ($Kind -eq 'generic') { 400 } else { 96 }

    # ============================ helpers: gateway ============================
    function Invoke-Gateway([string]$tierAlias, [string]$sys, [string]$userText, [double]$temp, [int]$seedV, [int]$genTokens) {
        $gwArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$GatewayPath,
                    '-Tier',$tierAlias,'-System',$sys,'-Prompt',$userText,'-MaxTokens',"$genTokens",'-Temperature',"$temp",'-Seed',"$seedV",
                    '-ArtifactRoot',$gwArtRoot,'-ReviewQueuePath',$gwReviewSuppressed)
        if ($GpuLayers -ge 0) { $gwArgs += @('-GpuLayers',"$GpuLayers") }
        if ($LoadTimeoutSec -gt 0) { $gwArgs += @('-LoadTimeoutSec',"$LoadTimeoutSec") }
        if (-not [string]::IsNullOrWhiteSpace($Registry)) { $gwArgs += @('-Registry',$Registry) }
        $tmpErr = New-TemporaryFile
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & $PwshPath @gwArgs 2> $tmpErr.FullName
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
        $envObj = $null; $parseErr = $null
        $txt = ([string]($out | Out-String)).Trim()
        if (-not [string]::IsNullOrWhiteSpace($txt)) { try { $envObj = $txt | ConvertFrom-Json } catch { $parseErr = $_.Exception.Message } }
        else { $parseErr = 'gateway produced no stdout envelope' }

        $ok = $false; $gcode = $null; $gmsg = $null; $outText = ''; $finish = 'unknown'; $pt = $null; $ct = $null; $rt = $null; $model = $null
        if ($null -eq $envObj -or -not (Has $envObj 'status')) {
            $gcode = 'no_envelope'; $gmsg = if ($parseErr) { $parseErr } else { 'gateway returned no valid envelope' }
        } elseif ($envObj.status -eq 'error') {
            $gcode = if ((Has $envObj 'error') -and ($null -ne $envObj.error) -and (Has $envObj.error 'code')) { [string]$envObj.error.code } else { 'gateway_error' }
            $gmsg  = if ((Has $envObj 'error') -and ($null -ne $envObj.error) -and (Has $envObj.error 'message')) { [string]$envObj.error.message } else { 'gateway error' }
        } else {
            $ok = $true
            if ((Has $envObj 'result') -and ($null -ne $envObj.result)) {
                if ((Has $envObj.result 'output') -and (Has $envObj.result.output 'text')) { $outText = [string]$envObj.result.output.text }
                if ((Has $envObj.result 'generation') -and (Has $envObj.result.generation 'finish_reason')) { $finish = [string]$envObj.result.generation.finish_reason }
                if (Has $envObj.result 'model') { $model = [string]$envObj.result.model }
            }
            if (Has $envObj 'model_provenance') {
                $mp = @($envObj.model_provenance)
                if ($mp.Count -ge 1) {
                    $p0 = $mp[0]
                    if ((Has $p0 'prompt_tokens') -and $null -ne $p0.prompt_tokens) { $pt = [int]$p0.prompt_tokens }
                    if ((Has $p0 'completion_tokens') -and $null -ne $p0.completion_tokens) { $ct = [int]$p0.completion_tokens }
                    if ((Has $p0 'runtime_ms') -and $null -ne $p0.runtime_ms) { $rt = [int]$p0.runtime_ms }
                    if (($null -eq $model) -and (Has $p0 'model_id')) { $model = [string]$p0.model_id }
                }
            }
        }

        # first-call-fatal guard (mirrors classify.batch / review.processor)
        $wasFirst = ($script:totalCalls -eq 0)
        $script:totalCalls++
        if ((-not $ok) -and $wasFirst -and ($FATAL_GW_CODES -contains $gcode)) {
            $script:aborted = $true; $script:abortCode = $gcode; $script:abortMsg = $gmsg
        }
        if ($ok) {
            if (-not $script:tierAcc.Contains($tierAlias)) { $script:tierAcc[$tierAlias] = [ordered]@{ calls = 0; pt = 0; ct = 0; rt = 0; model = $null } }
            $acc = $script:tierAcc[$tierAlias]
            $acc.calls++
            if ($null -ne $pt) { $acc.pt += $pt }
            if ($null -ne $ct) { $acc.ct += $ct }
            if ($null -ne $rt) { $acc.rt += $rt }
            if ($null -eq $acc.model -and $null -ne $model) { $acc.model = $model }
        }
        return [pscustomobject]@{ ok = $ok; code = $gcode; msg = $gmsg; text = $outText; finish = $finish; prompt_tokens = $pt; completion_tokens = $ct; runtime_ms = $rt; model = $model }
    }

    # ============================ helpers: parse an answer ============================
    function Get-NormMap([string[]]$names) {
        $m = @{}
        foreach ($n in $names) { $k = Get-NormToken $n; if (-not [string]::IsNullOrWhiteSpace($k) -and -not $m.ContainsKey($k)) { $m[$k] = $n } }
        return $m
    }
    # returns { label|obj|text, key, in_set|parsed, hardpass, grounded, present, required, display }
    function Parse-Answer([string]$raw, [hashtable]$normMap, [string[]]$fieldNames, [string]$sourceText) {
        if ($Kind -eq 'classify') {
            $label = $null; $inSet = $false
            $ans = Get-NormToken $raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                if ($normMap.ContainsKey($ans)) { $label = $normMap[$ans]; $inSet = $true }
                else {
                    $firstLine = ($raw -split "`n")[0]
                    $ansN = Get-NormToken $firstLine
                    $hit = $null
                    foreach ($k in $normMap.Keys) { if ($ansN -eq $k) { $hit = $k; break } }
                    if ($null -eq $hit) { foreach ($k in ($normMap.Keys | Sort-Object { $_.Length } -Descending)) { if ($ansN -match ('\b' + [regex]::Escape($k) + '\b')) { $hit = $k; break } } }
                    if ($null -ne $hit) { $label = $normMap[$hit]; $inSet = $true }
                }
            }
            $key = if ($null -ne $label) { Get-NormToken $label } else { "(null:$ans)" }
            return [pscustomobject]@{ label = $label; key = $key; in_set = $inSet; hardpass = $inSet; grounded = $null; present = $(if ($inSet) { 1 } else { 0 }); required = 1; display = $(if ($null -ne $label) { $label } else { '(none)' }) }
        }
        elseif ($Kind -eq 'extract') {
            $jsonStr = Get-FirstJsonObject $raw
            $obj = $null
            if ($null -ne $jsonStr) { try { $obj = $jsonStr | ConvertFrom-Json } catch { $obj = $null } }
            $ext = [ordered]@{}; $present = 0; $grounHit = 0; $grounTot = 0
            $srcN = if ($null -ne $sourceText) { $sourceText.ToLowerInvariant() } else { '' }
            foreach ($f in $fieldNames) {
                $v = $null
                if (($null -ne $obj) -and (Has $obj $f)) { $v = $obj.$f }
                $ext[$f] = $v
                if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
                    $present++
                    $grounTot++
                    $vn = ([string]$v).ToLowerInvariant().Trim()
                    if ($vn.Length -gt 0 -and $srcN.Contains($vn)) { $grounHit++ }
                }
            }
            $parsed = ($null -ne $obj)
            $hardpass = ($parsed -and $present -eq $fieldNames.Count -and $fieldNames.Count -gt 0)
            $grounded = if ($grounTot -gt 0) { ($grounHit -eq $grounTot) } else { $false }
            $key = ($ext | ConvertTo-Json -Depth 6 -Compress)
            return [pscustomobject]@{ obj = $ext; key = $key.ToLowerInvariant(); in_set = $hardpass; hardpass = $hardpass; grounded = $grounded; present = $present; required = $fieldNames.Count; display = (Get-Cap $key 80) }
        }
        else { # generic
            $t = if ($null -ne $raw) { $raw.Trim() } else { '' }
            $parsed = (-not [string]::IsNullOrWhiteSpace($t))
            return [pscustomobject]@{ text = $t; key = (Get-NormToken $t); in_set = $parsed; hardpass = $parsed; grounded = $null; present = $(if ($parsed) { 1 } else { 0 }); required = 1; display = (Get-Cap $t 80) }
        }
    }

    # ============================ helpers: prompts ============================
    function Build-AnswerSystem([string[]]$labelNames, [string[]]$fieldNames) {
        if ($Kind -eq 'classify') {
            $set = ($labelNames -join ', ')
            return "You are a precise text classifier. Choose EXACTLY ONE label for the user's text from this exact set: $set. Respond with ONLY the single chosen label, copied verbatim from the set. No explanation, no punctuation, no extra words."
        }
        if ($Kind -eq 'extract') {
            $keys = ($fieldNames | ForEach-Object { '"' + $_ + '"' }) -join ', '
            return "You are a precise information extractor. From the user's text, extract these fields: $($fieldNames -join ', '). Respond with ONLY a single minified JSON object whose keys are exactly: $keys. Use null for any field that is absent. No commentary, no code fences, no extra keys."
        }
        return "You are a precise, concise assistant. Answer the user's task directly and briefly. Give only the answer, no preamble."
    }
    function Build-JudgeSystem([string[]]$labelNames, [string[]]$fieldNames) {
        if ($Kind -eq 'classify') {
            $set = ($labelNames -join ', ')
            return @"
You are a senior text-classification reviewer. A weaker model assigned ONE label to an item. Decide whether that label is correct, choosing ONLY from the allowed labels ($set).
Respond with ONLY a minified JSON object and nothing else:
{"accept":<true|false>,"answer":"<one allowed label>","confidence":<0..1>,"rationale":"<one short sentence>"}
accept=true means the candidate label is correct (echo it in answer). accept=false means it is wrong (put the correct allowed label in answer).
"@
        }
        if ($Kind -eq 'extract') {
            return @"
You are a senior information-extraction reviewer. A weaker model extracted named fields from an item. Verify and correct them using the item text.
Respond with ONLY a minified JSON object and nothing else:
{"accept":<true|false>,"answer":{"<field>":"<value or null>"},"confidence":<0..1>,"rationale":"<one short sentence>"}
accept=true means the candidate extraction is correct (echo it in answer). accept=false means it is wrong (put the corrected object in answer, same field names, null for absent).
"@
        }
        return @"
You are a senior answer reviewer. A weaker model answered a task. Decide whether its answer is correct and adequate.
Respond with ONLY a minified JSON object and nothing else:
{"accept":<true|false>,"answer":"<your answer>","confidence":<0..1>,"rationale":"<one short sentence>"}
accept=true means the candidate answer is good (echo it in answer). accept=false means it is inadequate (put a better answer in answer).
"@
    }
    function Build-JudgeUser([string]$itemText, [string]$candidateDisplay, [string[]]$labelNames, [string[]]$fieldNames) {
        $ub = New-Object System.Collections.Generic.List[string]
        $ub.Add("TASK ITEM: " + (Get-Cap $itemText $MaxInputChars))
        $ub.Add("CANDIDATE ANSWER (from a weaker model): " + (Get-Cap $candidateDisplay 400))
        if ($Kind -eq 'classify' -and $labelNames.Count -gt 0) { $ub.Add("ALLOWED LABELS: " + ($labelNames -join ', ')) }
        if ($Kind -eq 'extract' -and $fieldNames.Count -gt 0) { $ub.Add("FIELDS: " + ($fieldNames -join ', ')) }
        return [string]::Join("`n", $ub.ToArray())
    }

    # ============================ helpers: answer a tier (self-consistency) ============================
    function Invoke-AnswerTier([string]$tierAlias, [int]$tierIdx, [string]$sysP, [string]$itemText, [hashtable]$normMap, [string[]]$fieldNames, [System.Collections.Generic.List[object]]$trace) {
        $samplesOut = New-Object System.Collections.Generic.List[object]
        $anyOk = $false; $lastFinish = 'unknown'; $errMsg = $null
        for ($k = 0; $k -lt $Samples; $k++) {
            if ($script:aborted) { break }
            $seedK = $Seed + $k
            $temp = if ($Samples -gt 1) { $SampleTemperature } else { $Temperature }
            $gw = Invoke-Gateway $tierAlias $sysP $itemText $temp $seedK $answerTokens
            if (-not $gw.ok) { $errMsg = "$($gw.code): $($gw.msg)"; continue }
            $anyOk = $true; $lastFinish = $gw.finish
            $samplesOut.Add((Parse-Answer $gw.text $normMap $fieldNames $itemText))
        }
        # majority vote
        $answer = $null; $agreement = $null
        if ($samplesOut.Count -gt 0) {
            $counts = @{}
            foreach ($s in $samplesOut.ToArray()) { $kk = [string]$s.key; if (-not $counts.ContainsKey($kk)) { $counts[$kk] = 0 }; $counts[$kk]++ }
            $bestKey = $null; $bestN = 0
            foreach ($kk in $counts.Keys) { if ($counts[$kk] -gt $bestN) { $bestN = $counts[$kk]; $bestKey = $kk } }
            $agreement = [Math]::Round(($bestN / [double]$samplesOut.Count), 4)
            foreach ($s in $samplesOut.ToArray()) { if ([string]$s.key -eq $bestKey) { $answer = $s; break } }
        }
        if ($Samples -le 1) { $agreement = $null }   # no self-consistency signal from a single greedy sample
        $trace.Add([ordered]@{ tier = $tierAlias; tier_index = $tierIdx; role = 'answer'; ok = $anyOk; samples = $samplesOut.Count; agreement = $agreement;
            answer = $(if ($null -ne $answer) { $answer.display } else { $null }); hardpass = $(if ($null -ne $answer) { [bool]$answer.hardpass } else { $false });
            finish_reason = $lastFinish; error = $errMsg })
        return [pscustomobject]@{ answer = $answer; agreement = $agreement; ok = $anyOk; finish = $lastFinish; error = $errMsg }
    }

    # ============================ helpers: judge with a tier ============================
    function Invoke-JudgeTier([string]$tierAlias, [int]$tierIdx, [string]$judgeSys, [string]$judgeUser, [string]$itemText, [hashtable]$normMap, [string[]]$fieldNames, [System.Collections.Generic.List[object]]$trace) {
        $gw = Invoke-Gateway $tierAlias $judgeSys $judgeUser $Temperature $Seed $judgeTokens
        $accept = $false; $judgeConf = $null; $rationale = $null; $judgeAnswer = $null; $parsed = $false
        if ($gw.ok) {
            $vjson = Get-FirstJsonObject $gw.text
            $vobj = $null
            if ($null -ne $vjson) { try { $vobj = $vjson | ConvertFrom-Json } catch { $vobj = $null } }
            if ($null -ne $vobj) {
                $parsed = $true
                if (Has $vobj 'accept') { try { $accept = [bool]$vobj.accept } catch { $accept = $false } }
                elseif (Has $vobj 'verdict') { $vd = ([string]$vobj.verdict).Trim().ToLowerInvariant(); $accept = ($vd -in @('confirm','accept','yes','true','correct-as-is')) }
                if ((Has $vobj 'confidence') -and $null -ne $vobj.confidence) { try { $judgeConf = [double]$vobj.confidence } catch { $judgeConf = $null } }
                if (Has $vobj 'rationale') { $rationale = Get-Cap ([string]$vobj.rationale) 300 }
                if (Has $vobj 'answer') {
                    $ansRaw = if ($Kind -eq 'extract') { ($vobj.answer | ConvertTo-Json -Depth 8 -Compress) } else { [string]$vobj.answer }
                    $judgeAnswer = Parse-Answer $ansRaw $normMap $fieldNames $itemText
                }
            }
        }
        $trace.Add([ordered]@{ tier = $tierAlias; tier_index = $tierIdx; role = 'judge'; ok = $gw.ok; parsed = $parsed; accept = $accept;
            judge_confidence = $judgeConf; produced_answer = $(if ($null -ne $judgeAnswer) { $judgeAnswer.display } else { $null });
            finish_reason = $gw.finish; error = $(if ($gw.ok) { $null } else { "$($gw.code): $($gw.msg)" }) })
        return [pscustomobject]@{ ok = $gw.ok; parsed = $parsed; accept = $accept; judge_conf = $judgeConf; rationale = $rationale; answer = $judgeAnswer; finish = $gw.finish }
    }

    # ============================ the ladder, per task ============================
    $taskRecords = New-Object System.Collections.Generic.List[object]
    $resolveDist = [ordered]@{}
    foreach ($t in $tierList) { $resolveDist[$t] = 0 }
    $resolvedCount = 0; $needFrontierCount = 0; $errTaskCount = 0
    $confSum = 0.0; $confN = 0

    foreach ($task in $taskList.ToArray()) {
        if ($script:aborted) { break }
        $tid = [string]$task.id
        $itemText = [string]$task.text
        $labelNames = @($task.labels)
        $fieldNames = @($task.fields)
        $normMap = Get-NormMap $labelNames
        $trace = New-Object System.Collections.Generic.List[object]

        if ([string]::IsNullOrWhiteSpace($itemText)) {
            $errTaskCount++
            $taskRecords.Add([ordered]@{ id = $tid; kind = $Kind; status = 'error'; accepted_tier = $null; accepted_tier_index = $null; answer = $null; confidence = 0.1; needs_frontier = $true; self_consistency = $null; gate = [ordered]@{ hard_pass = $false; grounded = $null; reason = 'empty task text' }; ladder = @(); gateway_calls = 0; error = 'empty task text' })
            $needFrontierCount++
            continue
        }

        $ansSys = Build-AnswerSystem $labelNames $fieldNames
        $judgeSys = Build-JudgeSystem $labelNames $fieldNames
        $callsBefore = $script:totalCalls

        # tier 0 answers
        $cur = Invoke-AnswerTier $tierList[0] 0 $ansSys $itemText $normMap $fieldNames $trace
        if ($script:aborted) { break }
        $curIdx = 0
        $acceptedIdx = -1; $acceptedVia = $null; $acceptJudgeConf = $null

        # short-circuit at tier 0 (self-consistency + hard-pass)
        if ($Samples -gt 1 -and $null -ne $cur.agreement -and $cur.agreement -ge $AcceptConsistency -and $null -ne $cur.answer -and $cur.answer.hardpass) {
            $acceptedIdx = 0; $acceptedVia = 'consistency'
        }

        if ($acceptedIdx -lt 0) {
            for ($j = 1; $j -lt $tierList.Count; $j++) {
                if ($script:aborted) { break }
                $candDisplay = if ($null -ne $cur.answer) { $cur.answer.display } else { '(none)' }
                $judgeUser = Build-JudgeUser $itemText $candDisplay $labelNames $fieldNames
                $jd = Invoke-JudgeTier $tierList[$j] $j $judgeSys $judgeUser $itemText $normMap $fieldNames $trace
                if ($script:aborted) { break }
                $candHard = ($null -ne $cur.answer -and $cur.answer.hardpass)
                $canAccept = ($jd.ok -and $jd.accept -and $candHard)   # deterministic hard-fail overrides a judge ACCEPT
                if ($canAccept) {
                    $acceptedIdx = $curIdx; $acceptedVia = 'judge'; $acceptJudgeConf = $jd.judge_conf
                    break
                }
                # higher tier j produces its own answer: use the judge's proposed correction ONLY when it
                # hard-passes the deterministic gate (a rubber-stamped/echoed bad answer does not qualify);
                # otherwise spend a fresh answer call at tier j.
                if ($jd.ok -and ($null -ne $jd.answer) -and $jd.answer.hardpass) {
                    $cur = [pscustomobject]@{ answer = $jd.answer; agreement = $null; ok = $true; finish = $jd.finish; error = $null }
                } else {
                    $ans2 = Invoke-AnswerTier $tierList[$j] $j $ansSys $itemText $normMap $fieldNames $trace
                    $cur = $ans2
                }
                $curIdx = $j
                if ($script:aborted) { break }
                # short-circuit on tier j's freshly-sampled answer
                if ($Samples -gt 1 -and $null -ne $cur.agreement -and $cur.agreement -ge $AcceptConsistency -and $null -ne $cur.answer -and $cur.answer.hardpass) {
                    $acceptedIdx = $j; $acceptedVia = 'consistency'; break
                }
            }
        }
        if ($script:aborted) { break }
        if ($acceptedIdx -lt 0) { $acceptedIdx = $curIdx; $acceptedVia = 'top' }

        # ---- per-task confidence (documented structural heuristic, NOT calibrated correctness) ----
        $acc = $cur.answer
        $hard = ($null -ne $acc -and [bool]$acc.hardpass)
        $agree = $cur.agreement
        $selfConsist = $agree
        $conf = 0.2
        if (-not $hard) { $conf = 0.2 }
        elseif ($acceptedVia -eq 'consistency') { $conf = [Math]::Min(0.95, 0.6 + 0.35 * [double]$agree) }
        elseif ($acceptedVia -eq 'judge') {
            $jc = if ($null -ne $acceptJudgeConf) { [double]$acceptJudgeConf } else { 0.5 }
            $conf = 0.5 + 0.35 * $jc
            if ($conf -gt 0.9) { $conf = 0.9 }; if ($conf -lt 0.3) { $conf = 0.3 }
        }
        else { # top
            $conf = 0.55
            if ($Samples -gt 1 -and $null -ne $agree) { $conf = [Math]::Min(0.85, 0.5 + 0.3 * [double]$agree) }
        }
        # extract grounding lowers confidence when values are not found in the source
        if ($Kind -eq 'extract' -and $hard -and ($null -ne $acc) -and (Has $acc 'grounded') -and (-not [bool]$acc.grounded)) { $conf = [Math]::Min($conf, 0.5) }
        # generic is ungated -> lower ceiling
        if ($Kind -eq 'generic') { $conf = [Math]::Min($conf, 0.7) }
        $conf = [Math]::Round($conf, 4)
        $needsFrontier = ((-not $hard) -or ($conf -lt $FrontierThreshold))

        $acceptedTier = $tierList[$acceptedIdx]
        if ($resolveDist.Contains($acceptedTier)) { $resolveDist[$acceptedTier] = [int]$resolveDist[$acceptedTier] + 1 } else { $resolveDist[$acceptedTier] = 1 }
        if ($needsFrontier) { $needFrontierCount++ } else { $resolvedCount++ }
        $confSum += $conf; $confN++

        $answerOut = $null
        if ($null -ne $acc) {
            if ($Kind -eq 'classify') { $answerOut = $acc.label }
            elseif ($Kind -eq 'extract') { $answerOut = $acc.obj }
            else { $answerOut = $acc.text }
        }
        $gwCallsTask = $script:totalCalls - $callsBefore
        $reasonTxt = if (-not $hard) { $(if ($Kind -eq 'classify') { 'answer out of label set' } elseif ($Kind -eq 'extract') { 'missing required fields' } else { 'empty answer' }) } else { "accepted_via=$acceptedVia" }

        $taskRecords.Add([ordered]@{
            id = $tid; kind = $Kind; status = 'ok'
            accepted_tier = $acceptedTier; accepted_tier_index = $acceptedIdx
            answer = $answerOut; confidence = $conf; needs_frontier = $needsFrontier
            accepted_via = $acceptedVia; self_consistency = $selfConsist
            gate = [ordered]@{ hard_pass = $hard; grounded = $(if ($null -ne $acc -and (Has $acc 'grounded')) { $acc.grounded } else { $null }); reason = $reasonTxt }
            ladder = $trace.ToArray()
            gateway_calls = $gwCallsTask
        })
        Write-Diag "task ${tid}: accepted_tier=$acceptedTier via=$acceptedVia hard=$hard conf=$conf needs_frontier=$needsFrontier calls=$gwCallsTask"
    }

    # ---- pass-fatal abort? ----
    if ($script:aborted) {
        throw [PSCustomObject]@{ code = $script:abortCode; message = "gateway could not run the escalation pass: $($script:abortMsg)"; retryable = $false }
    }

    # ---- inputs digest ----
    $digestTasks = @($taskList.ToArray() | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
    $normInputs = [ordered]@{ kind = $Kind; tiers = $tierList; samples = $Samples; accept_consistency = $AcceptConsistency; frontier_threshold = $FrontierThreshold; labels = $sharedLabels; fields = $sharedFields; tasks = $digestTasks; temperature = $Temperature; sample_temperature = $SampleTemperature; seed = $Seed }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Depth 12 -Compress)))

    # ---- provenance aggregate (one entry per tier used, stage-tagged) ----
    $provList = New-Object System.Collections.Generic.List[object]
    $totalPt = 0; $totalCt = 0; $totalRt = 0
    foreach ($ta in $script:tierAcc.Keys) {
        $a = $script:tierAcc[$ta]
        $totalPt += [int]$a.pt; $totalCt += [int]$a.ct; $totalRt += [int]$a.rt
        $provList.Add([ordered]@{ tier = $ta; model_id = $a.model; engine = 'llama-server'; calls = [int]$a.calls; prompt_tokens_total = [int]$a.pt; completion_tokens_total = [int]$a.ct; total_tokens_total = ([int]$a.pt + [int]$a.ct); runtime_ms_total = [int]$a.rt })
    }
    $modelProvenance = $provList.ToArray()

    if ($confN -gt 0) { $confidence = [Math]::Round(($confSum / $confN), 4) } else { $confidence = $null }
    $meanCalls = if ($taskList.Count -gt 0) { [Math]::Round(($script:totalCalls / [double]$taskList.Count), 3) } else { 0 }

    # ---- final status ----
    if ($errTaskCount -gt 0 -and $errTaskCount -lt $taskList.Count) { $status = 'partial'; $warnings.Add("$errTaskCount of $($taskList.Count) task(s) had empty text") | Out-Null }
    elseif ($errTaskCount -gt 0 -and $errTaskCount -eq $taskList.Count) { $status = 'partial'; $warnings.Add("all $errTaskCount task(s) had empty text") | Out-Null }
    else { $status = 'ok' }

    $result = [ordered]@{
        kind = $Kind
        tiers = $tierList
        samples = $Samples
        accept_consistency = $AcceptConsistency
        frontier_threshold = $FrontierThreshold
        count = $taskList.Count
        resolved_count = $resolvedCount
        needs_frontier_count = $needFrontierCount
        error_count = $errTaskCount
        resolve_distribution = $resolveDist
        cost = [ordered]@{ total_gateway_calls = $script:totalCalls; total_prompt_tokens = $totalPt; total_completion_tokens = $totalCt; total_tokens = ($totalPt + $totalCt); mean_calls_per_task = $meanCalls; total_runtime_ms = $totalRt }
        tasks = $taskRecords.ToArray()
        is_review_producer = $false
        gateway_reviews_suppressed_to = $gwReviewSuppressed
    }
    if ($Kind -eq 'classify') { $result.labels = $sharedLabels }
    elseif ($Kind -eq 'extract') { $result.fields = $sharedFields }
    Write-Diag "pass done: tasks=$($taskList.Count) resolved=$resolvedCount needs_frontier=$needFrontierCount calls=$($script:totalCalls) meanConf=$confidence"
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    $artList = New-Object System.Collections.Generic.List[object]
    if ($null -ne $result) {
        $ejPath = Join-Path $invDir 'escalation.json'
        [System.IO.File]::WriteAllText($ejPath, ($result | ConvertTo-Json -Depth 24), $utf8)
        $artList.Add([pscustomobject]@{ p = $ejPath; k = 'json' })

        $md = New-Object System.Collections.Generic.List[string]
        $md.Add("# logic.escalator -- $($result.kind)")
        $md.Add("")
        $md.Add("- tiers: ``$(($result.tiers) -join ' -> ')`` | samples(K): $($result.samples) | accept_consistency: $($result.accept_consistency) | frontier_threshold: $($result.frontier_threshold)")
        $md.Add("- tasks: $($result.count) | resolved: $($result.resolved_count) | needs_frontier: $($result.needs_frontier_count) | mean_gateway_calls/task: $($result.cost.mean_calls_per_task)")
        $rdParts = @(); foreach ($k in $result.resolve_distribution.Keys) { $rdParts += "$($k)=$($result.resolve_distribution[$k])" }
        $md.Add("- resolve distribution (accepted layer): " + ($rdParts -join ' | '))
        $md.Add("")
        $md.Add("| id | accepted_tier | via | hard_pass | conf | needs_frontier | calls | answer |")
        $md.Add("|----|--------------|-----|-----------|------|----------------|-------|--------|")
        foreach ($it in $result.tasks) {
            $a = ''
            if ($null -ne $it.answer) { if ($it.answer -is [System.Management.Automation.PSCustomObject]) { $a = ($it.answer | ConvertTo-Json -Depth 6 -Compress) } else { $a = [string]$it.answer } }
            $a = ($a -replace '\|','\|' -replace '\r?\n',' ')
            $via = if (Has $it 'accepted_via') { $it.accepted_via } else { '' }
            $md.Add("| $($it.id) | $($it.accepted_tier) | $via | $($it.gate.hard_pass) | $($it.confidence) | $($it.needs_frontier) | $($it.gateway_calls) | $a |")
        }
        $md.Add("")
        $md.Add("_The ladder anchors every rung with deterministic ground-truth gates (in-set membership / JSON-schema validity + source grounding / self-consistency across samples): a hard-fail overrides an LLM-judge ACCEPT, and strong self-consistency accepts without a judge. Per-task confidence is a documented structural heuristic (hard-pass + self-consistency + judge confidence + generation completeness), NOT a calibrated correctness score. needs_frontier is a status signal only -- this skill is an orchestrator, not a review-queue producer, and never writes the canonical review_queue.jsonl._")
        $mdPath = Join-Path $invDir 'escalation.md'
        [System.IO.File]::WriteAllText($mdPath, ([string]::Join("`n", $md.ToArray())), $utf8)
        $artList.Add([pscustomobject]@{ p = $mdPath; k = 'markdown' })
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[logic.escalator] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)

    foreach ($a in $artList.ToArray()) {
        $b = [System.IO.File]::ReadAllBytes($a.p)
        $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $a.p).Path; kind = $a.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
    }
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result = $result; confidence = $confidence; artifacts = $artifacts; model_provenance = $modelProvenance
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir; gateway_reviews_suppressed_to = $(if ($null -ne $result) { $result.gateway_reviews_suppressed_to } else { $null }) }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 28
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
