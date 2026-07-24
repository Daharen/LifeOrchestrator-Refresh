#requires -Version 7.0
<#
.SYNOPSIS
  review.processor — drain review_queue.jsonl by adjudicating flagged items one at a time with a STRONGER
  local model via model.gateway (Life Orchestrator, contract v0.1).
.DESCRIPTION
  The first consumer/drainer of the review queue (REVIEW_QUEUE.md, D-0007). The queue has two producers:
  model.gateway (Module 7, low generation-completeness) and classify.batch (Module 8, low classification
  confidence). This skill selects OPEN items, and for each one feeds a stronger local model (default
  -Tier mid = Qwen2.5-3B; -Tier strong = 27B) ONLY the distilled item: its reason/requested/weak_result plus
  a bounded fragment resolved from source_ref — never the whole batch. It parses a small JSON verdict, then:
    * confident  -> status "resolved", fills resolution {by, decision, at_utc, note, ...}
    * not sure   -> status "escalated", escalated_to "frontier" (a status transition, NOT a frontier call)
  It writes the live queue IN PLACE (re-reading immediately before an atomic replace; original flagging fields
  preserved; other/producer/malformed lines pass through verbatim) AND appends an immutable
  lifeorch.review.resolution/0.1 record per adjudication to review_resolved.jsonl. -DryRun writes nothing.
  Like classify.batch, it suppresses the child gateway's own review-queue writes so draining never grows the
  queue. Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; exits 0 whenever a
  valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -Tier mid -MaxItems 10
  pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -InputsJson '{"tier":"strong","gpu_layers":30,"max_items":5}'
#>
[CmdletBinding()]
param(
    [string]$QueuePath,
    [int]$MaxItems = 25,
    [string]$FlaggedBy,
    [string]$Reason,
    [object]$Ids,
    [string]$Tier = 'mid',
    [string]$Model,
    [int]$GpuLayers = -1,
    [int]$LoadTimeoutSec = 0,
    [int]$MaxTokens = 384,
    [double]$Temperature = 0.0,
    [int]$Seed = 42,
    [double]$EscalateThreshold = 0.5,
    [int]$MaxFragmentChars = 1500,
    [switch]$DryRun,
    [string]$ResolutionLogPath,
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

$SKILL_ID = 'review.processor'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$RESOLUTION_SCHEMA = 'lifeorch.review.resolution/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[review.processor] $m") }
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
function Get-Cap([string]$s, [int]$n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -gt $n) { return $s.Substring(0, $n) }
    return $s
}
# Normalize a candidate label/answer token for matching: strip fences/quotes/punctuation, casefold.
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
# Extract the first balanced {...} JSON object substring from arbitrary model text.
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

# fatal (pass-level) gateway error codes: if the FIRST call hits one, no item can be adjudicated — abort.
$FATAL_GW_CODES = @('model_not_found','model_not_wired','tier_not_found','registry_not_found','no_model_selected','engine_not_found','unsupported_type','unsupported_engine','model_file_missing')

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @()
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$resolutionLines = New-Object System.Collections.Generic.List[string]

try {
    # ---- merge -InputsJson (named params win where explicitly set on the command line) ----
    $bound = $PSBoundParameters
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'queue_path')          -and -not $bound.ContainsKey('QueuePath'))          { $QueuePath = [string]$p.queue_path }
            if ((Has $p 'review_queue_path')   -and -not $bound.ContainsKey('ReviewQueuePath'))    { $ReviewQueuePath = [string]$p.review_queue_path }
            if ((Has $p 'max_items')           -and -not $bound.ContainsKey('MaxItems'))           { $MaxItems = [int]$p.max_items }
            if ((Has $p 'flagged_by')          -and -not $bound.ContainsKey('FlaggedBy'))          { $FlaggedBy = [string]$p.flagged_by }
            if ((Has $p 'reason')              -and -not $bound.ContainsKey('Reason'))             { $Reason = [string]$p.reason }
            if ((Has $p 'ids')                 -and -not $bound.ContainsKey('Ids'))                { $Ids = $p.ids }
            if ((Has $p 'tier')                -and -not $bound.ContainsKey('Tier'))               { $Tier = [string]$p.tier }
            if ((Has $p 'model')               -and -not $bound.ContainsKey('Model'))              { $Model = [string]$p.model }
            if ((Has $p 'gpu_layers')          -and -not $bound.ContainsKey('GpuLayers'))          { $GpuLayers = [int]$p.gpu_layers }
            if ((Has $p 'load_timeout_s')      -and -not $bound.ContainsKey('LoadTimeoutSec'))     { $LoadTimeoutSec = [int]$p.load_timeout_s }
            if ((Has $p 'max_tokens')          -and -not $bound.ContainsKey('MaxTokens'))          { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'temperature')         -and -not $bound.ContainsKey('Temperature'))        { $Temperature = [double]$p.temperature }
            if ((Has $p 'seed')                -and -not $bound.ContainsKey('Seed'))               { $Seed = [int]$p.seed }
            if ((Has $p 'escalate_threshold')  -and -not $bound.ContainsKey('EscalateThreshold'))  { $EscalateThreshold = [double]$p.escalate_threshold }
            if ((Has $p 'max_fragment_chars')  -and -not $bound.ContainsKey('MaxFragmentChars'))   { $MaxFragmentChars = [int]$p.max_fragment_chars }
            if ((Has $p 'dry_run')             -and -not $bound.ContainsKey('DryRun'))             { if ([bool]$p.dry_run) { $DryRun = [switch]$true } }
            if ((Has $p 'resolution_log_path') -and -not $bound.ContainsKey('ResolutionLogPath'))  { $ResolutionLogPath = [string]$p.resolution_log_path }
            if ((Has $p 'registry')            -and -not $bound.ContainsKey('Registry'))           { $Registry = [string]$p.registry }
            if ((Has $p 'gateway_path')        -and -not $bound.ContainsKey('GatewayPath'))        { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'pwsh_path')           -and -not $bound.ContainsKey('PwshPath'))           { $PwshPath = [string]$p.pwsh_path }
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- resolve the queue path (QueuePath, then the ReviewQueuePath alias, then repo-root default) ----
    if ([string]::IsNullOrWhiteSpace($QueuePath) -and -not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $QueuePath = $ReviewQueuePath }
    if ([string]::IsNullOrWhiteSpace($QueuePath)) {
        $root = Resolve-RepoRoot $PSScriptRoot
        $QueuePath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
    }
    if ([string]::IsNullOrWhiteSpace($ResolutionLogPath)) {
        $ResolutionLogPath = Join-Path ([System.IO.Path]::GetDirectoryName($QueuePath)) 'review_resolved.jsonl'
    }

    # ---- id filter set ----
    $idFilter = @()
    if ($null -ne $Ids) { $idFilter = @(@($Ids) | ForEach-Object { [string]$_ }) }

    # ---- load queue lines (each: raw string + parsed obj or $null when malformed) ----
    $entries = New-Object System.Collections.Generic.List[object]   # {raw, obj, id, st}
    $totalOpen = 0; $skippedMalformed = 0
    if (Test-Path -LiteralPath $QueuePath -PathType Leaf) {
        $rawLines = @(Get-Content -LiteralPath $QueuePath)
        foreach ($ln in $rawLines) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            $obj = $null
            try { $obj = $ln | ConvertFrom-Json } catch { $obj = $null }
            $id = $null; $st = $null
            if ($null -ne $obj) {
                if (Has $obj 'id') { $id = [string]$obj.id }
                if (Has $obj 'status') { $st = [string]$obj.status }
                if ($st -eq 'open') { $totalOpen++ }
            } else { $skippedMalformed++ }
            $entries.Add([pscustomobject]@{ raw = $ln; obj = $obj; id = $id; st = $st })
        }
    }

    # ---- select open items matching the filters, bounded by MaxItems ----
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($e in $entries.ToArray()) {
        if ($selected.Count -ge $MaxItems) { break }
        if ($null -eq $e.obj) { continue }
        if ($e.st -ne 'open') { continue }
        if (-not [string]::IsNullOrWhiteSpace($FlaggedBy)) {
            $fb = if (Has $e.obj 'flagged_by') { [string]$e.obj.flagged_by } else { '' }
            if ($fb -ne $FlaggedBy) { continue }
        }
        if (-not [string]::IsNullOrWhiteSpace($Reason)) {
            $rn = if (Has $e.obj 'reason') { [string]$e.obj.reason } else { '' }
            if ($rn -ne $Reason) { continue }
        }
        if ($idFilter.Count -gt 0) {
            if ($idFilter -notcontains [string]$e.id) { continue }
        }
        $selected.Add($e.obj)
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
    # Only require the gateway when there is actually something to adjudicate.
    if ($selected.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($GatewayPath) -or -not (Test-Path -LiteralPath $GatewayPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code = 'gateway_not_found'; message = "model.gateway entrypoint not found (looked near modules/07-model-gateway; set -GatewayPath). got '$GatewayPath'"; retryable = $false }
        }
    }

    # ---- gateway plumbing (suppress the gateway's own review writes) ----
    $gwArtRoot = Join-Path $invDir 'gateway'
    $gwReviewSuppressed = Join-Path $invDir '_gateway_review_suppressed.jsonl'
    if ($selected.Count -gt 0) { New-Item -ItemType Directory -Path $gwArtRoot -Force | Out-Null }

    # ---- source_ref resolver (best-effort, bounded) ----
    function Resolve-SourceRef([string]$sref) {
        $r = [ordered]@{ resolved = $false; kind = $null; mode = $null; labels = @(); fields = @(); item = $null; text = $null; request_preview = $null; output_preview = $null; finish_reason = $null; note = $null }
        if ([string]::IsNullOrWhiteSpace($sref)) { $r.note = 'no source_ref'; return [pscustomobject]$r }
        $s = $sref.Trim()
        foreach ($pre in @('artifact://','file://')) { if ($s.StartsWith($pre)) { $s = $s.Substring($pre.Length) } }
        $frag = $null
        $h = $s.LastIndexOf('#')
        if ($h -ge 0) { $frag = $s.Substring($h + 1); $s = $s.Substring(0, $h) }
        $path = $s
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $r.note = "source file not found: $path"; return [pscustomobject]$r }
        $fname = ([System.IO.Path]::GetFileName($path)).ToLowerInvariant()
        $json = $null
        try { $json = (Get-Content -LiteralPath $path -Raw) | ConvertFrom-Json } catch { $r.note = "source not JSON: $($_.Exception.Message)"; return [pscustomobject]$r }
        $rr = if (Has $json 'result') { $json.result } else { $json }
        $looksClassify = (($fname -eq 'classified.json') -or ((Has $rr 'items') -and ((Has $rr 'labels') -or (Has $rr 'fields') -or (Has $rr 'mode'))))
        $looksExchange = (($fname -eq 'exchange.json') -or (Has $json 'response'))
        if ($looksClassify) {
            $r.kind = 'classify'
            if (Has $rr 'mode') { $r.mode = [string]$rr.mode }
            if (Has $rr 'labels') { $r.labels = @($rr.labels) }
            if (Has $rr 'fields') { $r.fields = @($rr.fields) }
            if ($null -ne $frag -and (Has $rr 'items')) {
                $it = @($rr.items) | Where-Object { (Has $_ 'id') -and ([string]$_.id -eq $frag) } | Select-Object -First 1
                if ($null -ne $it) {
                    $r.item = $it
                    if (Has $it 'input_preview') { $r.text = Get-Cap ([string]$it.input_preview) $MaxFragmentChars }
                }
            }
            $r.resolved = $true
        }
        elseif ($looksExchange) {
            $r.kind = 'generation'
            $reqTxt = ''
            if (Has $json 'request') { try { $reqTxt = ($json.request | ConvertTo-Json -Depth 6 -Compress) } catch { $reqTxt = '' } }
            $outTxt = ''
            if ((Has $json 'response') -and (Has ($json.response) 'output') -and (Has ($json.response.output) 'text')) { $outTxt = [string]$json.response.output.text }
            if ((Has $json 'response') -and (Has ($json.response) 'generation') -and (Has ($json.response.generation) 'finish_reason')) { $r.finish_reason = [string]$json.response.generation.finish_reason }
            $r.request_preview = Get-Cap $reqTxt $MaxFragmentChars
            $r.output_preview = Get-Cap $outTxt $MaxFragmentChars
            $r.text = $r.output_preview
            $r.resolved = $true
        }
        else { $r.note = "unrecognized source file: $fname" }
        return [pscustomobject]$r
    }

    # ---- gateway invocation helper (mirrors classify.batch) ----
    function Invoke-Gateway([string]$sys, [string]$userText) {
        $gwArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$GatewayPath,
                    '-System',$sys,'-Prompt',$userText,'-MaxTokens',"$MaxTokens",'-Temperature',"$Temperature",'-Seed',"$Seed",
                    '-ArtifactRoot',$gwArtRoot,'-ReviewQueuePath',$gwReviewSuppressed)
        if (-not [string]::IsNullOrWhiteSpace($Model)) { $gwArgs += @('-Model',$Model) } else { $gwArgs += @('-Tier',$Tier) }
        if ($GpuLayers -ge 0) { $gwArgs += @('-GpuLayers',"$GpuLayers") }
        if ($LoadTimeoutSec -gt 0) { $gwArgs += @('-LoadTimeoutSec',"$LoadTimeoutSec") }
        if (-not [string]::IsNullOrWhiteSpace($Registry)) { $gwArgs += @('-Registry',$Registry) }
        $tmpErr = New-TemporaryFile
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = & $PwshPath @gwArgs 2> $tmpErr.FullName
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        $errText = ''
        try { $errText = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
        Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
        $envObj = $null; $parseErr = $null
        $txt = ([string]($out | Out-String)).Trim()
        if (-not [string]::IsNullOrWhiteSpace($txt)) { try { $envObj = $txt | ConvertFrom-Json } catch { $parseErr = $_.Exception.Message } }
        else { $parseErr = 'gateway produced no stdout envelope' }
        return [pscustomobject]@{ envelope = $envObj; exit = $code; parse_error = $parseErr; stderr_tail = $(if ($errText -and $errText.Length -gt 400) { $errText.Substring($errText.Length - 400) } else { $errText }) }
    }

    # ---- build a requested-aware reviewer system prompt ----
    function Build-ReviewerSystem([string]$kind) {
        if ($kind -eq 'category_single') {
            return @"
You are a senior text-classification reviewer. A weaker model assigned ONE category to ONE item and it was flagged as uncertain. Decide the single correct category for this item, choosing ONLY from the allowed labels shown in the user message.
Respond with ONLY a minified JSON object and nothing else:
{"verdict":"confirm|correct|reject|uncertain","answer":"<one allowed label, or null>","confidence":<0..1>,"escalate":<true|false>,"rationale":"<one short sentence>"}
verdict: "confirm" = the weak label is right; "correct" = a different allowed label is right (put it in answer); "reject" = none of the labels apply (answer null); "uncertain" = you cannot tell from what is given (set escalate true).
"@
        }
        if ($kind -eq 'category_multi') {
            return @"
You are a senior multi-label text-classification reviewer. A weaker model assigned zero or more categories to ONE item and it was flagged as uncertain. Decide the correct set of labels, choosing ONLY from the allowed labels shown in the user message.
Respond with ONLY a minified JSON object and nothing else:
{"verdict":"confirm|correct|reject|uncertain","answer":["<allowed label>", "..."],"confidence":<0..1>,"escalate":<true|false>,"rationale":"<one short sentence>"}
answer is a JSON array of allowed labels (use [] if none apply). Set verdict "uncertain" and escalate true if you cannot tell.
"@
        }
        if ($kind -eq 'extraction') {
            return @"
You are a senior information-extraction reviewer. A weaker model extracted named fields from ONE item and it was flagged. Verify and correct the fields using the item text shown in the user message.
Respond with ONLY a minified JSON object and nothing else:
{"verdict":"confirm|correct|reject|uncertain","answer":{"<field>":"<value or null>"},"confidence":<0..1>,"escalate":<true|false>,"rationale":"<one short sentence>"}
answer is a JSON object with the same field names, corrected. Use null for a field genuinely absent. Set verdict "uncertain" and escalate true if the text is insufficient.
"@
        }
        if ($kind -eq 'generation') {
            return @"
You are a senior output-quality reviewer. A weaker model's generated output was flagged for low completeness/quality. Judge whether the output shown in the user message is acceptable as-is or should be regenerated.
Respond with ONLY a minified JSON object and nothing else:
{"verdict":"confirm|correct|reject|uncertain","answer":"acceptable|regenerate","confidence":<0..1>,"escalate":<true|false>,"rationale":"<one short sentence>"}
verdict "confirm" = acceptable; "reject" = should be regenerated; "uncertain" = you cannot tell (set escalate true).
"@
        }
        return @"
You are a senior reviewer. A weaker model produced a result for ONE item that was flagged as uncertain. Judge it using only what is shown in the user message.
Respond with ONLY a minified JSON object and nothing else:
{"verdict":"confirm|correct|reject|uncertain","answer":"<your adjudication, short>","confidence":<0..1>,"escalate":<true|false>,"rationale":"<one short sentence>"}
Set verdict "uncertain" and escalate true if you cannot decide from what is given.
"@
    }

    # ---- run the adjudication pass ----
    $items = New-Object System.Collections.Generic.List[object]
    $adjudicated = @{}   # id -> {new_status, resolution, escalated_to}
    $resolvedCount = 0; $escalatedCount = 0; $errCount = 0
    $confSum = 0.0; $confN = 0
    $calls = 0; $sumP = 0; $sumC = 0; $sumT = 0; $sumRt = 0
    $provTemplate = $null; $resolvedModel = $null; $resolvedSelectedFrom = $null
    $aborted = $false; $abortCode = $null; $abortMsg = $null

    foreach ($qi in $selected.ToArray()) {
        $id = if (Has $qi 'id') { [string]$qi.id } else { "(no-id)" }
        $rsn = if (Has $qi 'reason') { [string]$qi.reason } else { $null }
        $req = if (Has $qi 'requested') { [string]$qi.requested } else { $null }
        $flby = if (Has $qi 'flagged_by') { [string]$qi.flagged_by } else { $null }
        $weak = if (Has $qi 'weak_result') { $qi.weak_result } else { $null }
        $sref = if (Has $qi 'source_ref') { [string]$qi.source_ref } else { $null }

        # resolve the bounded source fragment
        $frag = Resolve-SourceRef $sref

        # determine the adjudication kind
        $weakMode = $null
        if ($null -ne $weak -and (Has $weak 'mode')) { $weakMode = [string]$weak.mode }
        elseif (-not [string]::IsNullOrWhiteSpace($frag.mode)) { $weakMode = [string]$frag.mode }
        $kind = 'generic'
        if ($req -eq 'verify_extraction') { $kind = 'extraction' }
        elseif ($req -eq 'review_generation_quality') { $kind = 'generation' }
        elseif ($req -eq 'adjudicate_category') { $kind = if ($weakMode -eq 'multilabel') { 'category_multi' } else { 'category_single' } }
        elseif ($weakMode -eq 'multilabel') { $kind = 'category_multi' }
        elseif ($weakMode -eq 'classify') { $kind = 'category_single' }
        elseif ($null -ne $weak -and (Has $weak 'extracted')) { $kind = 'extraction' }

        # closed label set (from the fragment) for in-set validation on category kinds
        $labelNames = @()
        if ($frag.resolved -and @($frag.labels).Count -gt 0) { $labelNames = @($frag.labels | ForEach-Object { [string]$_ }) }
        $normMap = @{}
        foreach ($ln in $labelNames) { $k = Get-NormToken $ln; if (-not [string]::IsNullOrWhiteSpace($k) -and -not $normMap.ContainsKey($k)) { $normMap[$k] = $ln } }

        # item text preview to show the reviewer
        $itemText = $null
        if (-not [string]::IsNullOrWhiteSpace($frag.text)) { $itemText = [string]$frag.text }
        elseif ($null -ne $weak -and (Has $weak 'text_preview')) { $itemText = [string]$weak.text_preview }

        # build the reviewer user prompt (compact, bounded)
        $ub = New-Object System.Collections.Generic.List[string]
        if ($flby) { $ub.Add("FLAGGED BY: ${flby}") }
        if ($rsn)  { $ub.Add("REASON: ${rsn}") }
        if ($null -ne $weak) { $ub.Add("WEAK MODEL DECISION: " + (Get-Cap (($weak | ConvertTo-Json -Depth 8 -Compress)) $MaxFragmentChars)) }
        if ($normMap.Count -gt 0) { $ub.Add("ALLOWED LABELS: " + ((@($labelNames)) -join ', ')) }
        if ($kind -eq 'extraction' -and @($frag.fields).Count -gt 0) { $ub.Add("FIELDS TO VERIFY: " + ((@($frag.fields | ForEach-Object { [string]$_ })) -join ', ')) }
        if (-not [string]::IsNullOrWhiteSpace($itemText)) { $ub.Add("ITEM TEXT: " + (Get-Cap $itemText $MaxFragmentChars)) }
        if ($kind -eq 'generation' -and -not [string]::IsNullOrWhiteSpace($frag.output_preview)) { $ub.Add("FLAGGED OUTPUT: " + (Get-Cap ([string]$frag.output_preview) $MaxFragmentChars)) }
        $userPrompt = [string]::Join("`n", $ub.ToArray())
        if ([string]::IsNullOrWhiteSpace($userPrompt)) { $userPrompt = "Nothing but the flag is available. Judge conservatively." }
        $sysPrompt = Build-ReviewerSystem $kind

        $gw = Invoke-Gateway $sysPrompt $userPrompt
        $gwEnv = $gw.envelope

        # gateway produced no envelope, or a gateway-level error?
        $gwFailed = $false; $gwCode = $null; $gwMsg = $null
        if ($null -eq $gwEnv -or -not (Has $gwEnv 'status')) {
            $gwFailed = $true; $gwCode = 'no_envelope'; $gwMsg = if ($gw.parse_error) { [string]$gw.parse_error } else { 'gateway returned no valid envelope' }
        }
        elseif ($gwEnv.status -eq 'error') {
            $gwCode = if ((Has $gwEnv 'error') -and ($null -ne $gwEnv.error) -and (Has $gwEnv.error 'code')) { [string]$gwEnv.error.code } else { 'gateway_error' }
            $gwMsg  = if ((Has $gwEnv 'error') -and ($null -ne $gwEnv.error) -and (Has $gwEnv.error 'message')) { [string]$gwEnv.error.message } else { 'gateway error' }
            if ($calls -eq 0 -and $FATAL_GW_CODES -contains $gwCode) {
                $aborted = $true; $abortCode = $gwCode; $abortMsg = $gwMsg
                Write-Diag "pass-fatal gateway error on first item ($gwCode): $gwMsg — aborting"
                break
            }
            $gwFailed = $true
        }

        if ($gwFailed) {
            # per-item gateway failure: DO NOT mutate the queue line; leave it open, count as error.
            $errCount++
            $items.Add([ordered]@{ id = $id; flagged_by = $flby; reason = $rsn; requested = $req; kind = $kind;
                prior_status = 'open'; new_status = 'open'; verdict = $null; decision = $null; reviewer_confidence = $null;
                model_self_confidence = $null; escalated_to = $null; finish_reason = $null; source_fragment_resolved = [bool]$frag.resolved;
                error = "${gwCode}: $gwMsg" })
            Write-Diag "item ${id}: gateway failed ($gwCode) — left open"
            continue
        }

        # success — pull the model output + provenance
        $calls++
        $answerText = ''
        if ((Has $gwEnv 'result') -and ($null -ne $gwEnv.result) -and (Has $gwEnv.result 'output') -and (Has $gwEnv.result.output 'text')) { $answerText = [string]$gwEnv.result.output.text }
        $finish = 'unknown'
        if ((Has $gwEnv 'result') -and ($null -ne $gwEnv.result) -and (Has $gwEnv.result 'generation') -and (Has $gwEnv.result.generation 'finish_reason')) { $finish = [string]$gwEnv.result.generation.finish_reason }
        if ((Has $gwEnv 'model_provenance')) {
            $mp = @($gwEnv.model_provenance)
            if ($mp.Count -ge 1) {
                $p0 = $mp[0]
                if ((Has $p0 'prompt_tokens') -and $null -ne $p0.prompt_tokens) { $sumP += [int]$p0.prompt_tokens }
                if ((Has $p0 'completion_tokens') -and $null -ne $p0.completion_tokens) { $sumC += [int]$p0.completion_tokens }
                if ((Has $p0 'total_tokens') -and $null -ne $p0.total_tokens) { $sumT += [int]$p0.total_tokens }
                if ((Has $p0 'runtime_ms') -and $null -ne $p0.runtime_ms) { $sumRt += [int]$p0.runtime_ms }
                if ($null -eq $provTemplate) { $provTemplate = $p0 }
            }
        }
        if (($null -eq $resolvedModel) -and (Has $gwEnv 'result') -and (Has $gwEnv.result 'model')) { $resolvedModel = [string]$gwEnv.result.model }
        if (($null -eq $resolvedSelectedFrom) -and (Has $gwEnv 'result') -and (Has $gwEnv.result 'selected_from')) { $resolvedSelectedFrom = [string]$gwEnv.result.selected_from }

        # ---- parse the reviewer verdict ----
        $vjson = Get-FirstJsonObject $answerText
        $vobj = $null
        if ($null -ne $vjson) { try { $vobj = $vjson | ConvertFrom-Json } catch { $vobj = $null } }

        $verdict = $null; $answer = $null; $selfConf = $null; $modelEscalate = $false; $rationale = $null
        $parsed = ($null -ne $vobj)
        if ($parsed) {
            if (Has $vobj 'verdict') { $verdict = ([string]$vobj.verdict).Trim().ToLowerInvariant() }
            if (Has $vobj 'answer') { $answer = $vobj.answer }
            if ((Has $vobj 'confidence') -and $null -ne $vobj.confidence) { try { $selfConf = [double]$vobj.confidence } catch { $selfConf = $null } }
            if (Has $vobj 'escalate') { try { $modelEscalate = [bool]$vobj.escalate } catch { $modelEscalate = $false } }
            if (Has $vobj 'rationale') { $rationale = Get-Cap ([string]$vobj.rationale) 400 }
        }
        $truncated = ($finish -eq 'length')

        # ---- reviewer confidence heuristic (structural completeness+validity, NOT calibrated) ----
        $revConf = 0.15
        $decision = $null
        if (-not $parsed) {
            $revConf = 0.15
        }
        elseif ($verdict -eq 'uncertain') {
            $revConf = 0.4
        }
        else {
            if ($kind -eq 'category_single') {
                $ansTok = Get-NormToken ([string]$answer)
                $inSet = ($normMap.Count -gt 0 -and $normMap.ContainsKey($ansTok))
                $isReject = ($verdict -eq 'reject')
                if ($isReject) { $decision = $null; $revConf = if ($normMap.Count -gt 0) { 0.7 } else { 0.5 } }
                elseif ($inSet) { $decision = $normMap[$ansTok]; $revConf = if ($finish -eq 'stop') { 0.85 } else { 0.6 } }
                elseif ($normMap.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$answer)) { $decision = [string]$answer; $revConf = 0.5 }
                else { $decision = [string]$answer; $revConf = 0.4 }
            }
            elseif ($kind -eq 'category_multi') {
                $ansArr = @()
                if ($answer -is [System.Array]) { $ansArr = @($answer | ForEach-Object { [string]$_ }) }
                elseif ($null -ne $answer) { $ansArr = @(([string]$answer) -split '[,\n;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
                $kept = New-Object System.Collections.Generic.List[string]; $dropped = 0
                foreach ($a in $ansArr) { $t = Get-NormToken $a; if ($normMap.ContainsKey($t)) { $c = $normMap[$t]; if (-not $kept.Contains($c)) { $kept.Add($c) } } else { $dropped++ } }
                $decision = $kept.ToArray()
                if ($normMap.Count -eq 0) { $revConf = 0.5 }
                elseif ($dropped -eq 0) { $revConf = if ($finish -eq 'stop') { 0.85 } else { 0.6 } }
                elseif ($kept.Count -ge 1) { $revConf = 0.5 }
                else { $revConf = 0.4 }
            }
            elseif ($kind -eq 'extraction') {
                if ($answer -is [System.Management.Automation.PSCustomObject]) {
                    $nonNull = 0
                    foreach ($pp in $answer.PSObject.Properties) { if ($null -ne $pp.Value -and -not [string]::IsNullOrWhiteSpace([string]$pp.Value)) { $nonNull++ } }
                    $decision = $answer
                    $revConf = if ($nonNull -ge 1 -and $finish -eq 'stop') { 0.8 } elseif ($nonNull -ge 1) { 0.6 } else { 0.4 }
                } else { $decision = $answer; $revConf = 0.4 }
            }
            elseif ($kind -eq 'generation') {
                $ans = Get-NormToken ([string]$answer)
                if ($ans -eq 'acceptable' -or $ans -eq 'regenerate') { $decision = $ans; $revConf = if ($finish -eq 'stop') { 0.8 } else { 0.6 } }
                elseif ($verdict -eq 'confirm') { $decision = 'acceptable'; $revConf = 0.7 }
                elseif ($verdict -eq 'reject') { $decision = 'regenerate'; $revConf = 0.7 }
                else { $decision = [string]$answer; $revConf = 0.4 }
            }
            else {
                if (-not [string]::IsNullOrWhiteSpace([string]$answer)) { $decision = [string]$answer; $revConf = 0.6 } else { $decision = $null; $revConf = 0.4 }
            }
        }
        if ($truncated) { $revConf = [Math]::Min($revConf, 0.4); $warnings.Add("item $id reviewer output truncated (finish_reason=length)") | Out-Null }

        # ---- decide status ----
        $escalate = ((-not $parsed) -or $modelEscalate -or ($revConf -lt $EscalateThreshold))
        $newStatus = if ($escalate) { 'escalated' } else { 'resolved' }
        $escTo = if ($escalate) { 'frontier' } else { $null }
        $by = "review.processor:" + $(if ($resolvedModel) { $resolvedModel } elseif ($Model) { $Model } else { "tier:$Tier" })
        $nowUtc = ([DateTime]::UtcNow).ToString('o')
        $note = if ($rationale) { $rationale } elseif (-not $parsed) { 'reviewer output was not parseable JSON' } else { "verdict=$verdict" }

        $resolutionObj = [ordered]@{
            by = $by; decision = $decision; at_utc = $nowUtc; note = $note
            verdict = $verdict; reviewer_confidence = $revConf; model_self_confidence = $selfConf
            escalated = $escalate; source_fragment_resolved = [bool]$frag.resolved; reviewer_finish_reason = $finish
        }
        $adjudicated[$id] = [pscustomobject]@{ new_status = $newStatus; resolution = $resolutionObj; escalated_to = $escTo }

        if ($escalate) { $escalatedCount++ } else { $resolvedCount++ }
        $confSum += $revConf; $confN++

        # append-only resolution-log record (immutable history)
        $resolutionLines.Add((([ordered]@{
            schema = $RESOLUTION_SCHEMA; id = $id; at_utc = $nowUtc; by = $by; flagged_by = $flby; reason = $rsn; requested = $req
            prior_status = 'open'; new_status = $newStatus; escalated_to = $escTo; verdict = $verdict
            decision = $decision; reviewer_confidence = $revConf; model_self_confidence = $selfConf; note = $note
        }) | ConvertTo-Json -Depth 10 -Compress))

        $items.Add([ordered]@{ id = $id; flagged_by = $flby; reason = $rsn; requested = $req; kind = $kind;
            prior_status = 'open'; new_status = $newStatus; verdict = $verdict; decision = $decision;
            reviewer_confidence = $revConf; model_self_confidence = $selfConf; escalated_to = $escTo;
            finish_reason = $finish; source_fragment_resolved = [bool]$frag.resolved; error = $null })
        Write-Diag "item ${id}: kind=$kind verdict=$verdict revConf=$revConf -> $newStatus"
    }

    # ---- pass-fatal abort? ----
    if ($aborted) {
        throw [PSCustomObject]@{ code = $abortCode; message = "gateway could not run the review pass: $abortMsg"; retryable = $false }
    }

    # ---- write the queue back IN PLACE (re-read immediately before an atomic replace) ----
    $wroteQueue = $false
    if (-not $DryRun -and $adjudicated.Count -gt 0) {
        try {
            $currentLines = @()
            if (Test-Path -LiteralPath $QueuePath -PathType Leaf) { $currentLines = @(Get-Content -LiteralPath $QueuePath) }
            $outLines = New-Object System.Collections.Generic.List[string]
            foreach ($ln in $currentLines) {
                if ([string]::IsNullOrWhiteSpace($ln)) { $outLines.Add($ln); continue }
                $o = $null
                try { $o = $ln | ConvertFrom-Json } catch { $o = $null }
                if ($null -eq $o -or -not (Has $o 'id')) { $outLines.Add($ln); continue }
                $oid = [string]$o.id
                $ost = if (Has $o 'status') { [string]$o.status } else { $null }
                if ($adjudicated.ContainsKey($oid) -and $ost -eq 'open') {
                    $upd = $adjudicated[$oid]
                    if (Has $o 'status') { $o.status = $upd.new_status } else { $o | Add-Member -NotePropertyName 'status' -NotePropertyValue $upd.new_status }
                    if (Has $o 'resolution') { $o.resolution = $upd.resolution } else { $o | Add-Member -NotePropertyName 'resolution' -NotePropertyValue $upd.resolution }
                    if (Has $o 'escalated_to') { $o.escalated_to = $upd.escalated_to } else { $o | Add-Member -NotePropertyName 'escalated_to' -NotePropertyValue $upd.escalated_to }
                    $outLines.Add(($o | ConvertTo-Json -Depth 12 -Compress))
                } else {
                    $outLines.Add($ln)
                }
            }
            $tmpQueue = "$QueuePath.tmp-$($InvocationId.Substring(0,8))"
            [System.IO.File]::WriteAllText($tmpQueue, ([string]::Join("`n", $outLines.ToArray()) + "`n"), $utf8)
            $moved = $false
            for ($attempt = 0; $attempt -lt 4 -and -not $moved; $attempt++) {
                try { [System.IO.File]::Move($tmpQueue, $QueuePath, $true); $moved = $true }
                catch { Start-Sleep -Milliseconds (150 * ($attempt + 1)) }
            }
            if (-not $moved) {
                try { Copy-Item -LiteralPath $tmpQueue -Destination $QueuePath -Force; Remove-Item -LiteralPath $tmpQueue -Force -ErrorAction SilentlyContinue; $moved = $true } catch { }
            }
            $wroteQueue = $moved
            if (-not $moved) { $warnings.Add("could not replace the queue file after retries: $QueuePath") | Out-Null }
        } catch { Write-Diag "queue write-back failed: $($_.Exception.Message)"; $warnings.Add("queue write-back failed: $($_.Exception.Message)") | Out-Null }
    }

    # ---- append the resolution log (immutable history) ----
    $wroteLog = $false
    if (-not $DryRun -and $resolutionLines.Count -gt 0) {
        try {
            [System.IO.File]::AppendAllText($ResolutionLogPath, ([string]::Join("`n", $resolutionLines.ToArray()) + "`n"), $utf8)
            $wroteLog = $true
        } catch { Write-Diag "resolution-log append failed: $($_.Exception.Message)"; $warnings.Add("resolution-log append failed: $($_.Exception.Message)") | Out-Null }
    }

    # ---- inputs digest ----
    $selIds = @($selected.ToArray() | ForEach-Object { if (Has $_ 'id') { [string]$_.id } else { '' } })
    $normInputs = [ordered]@{ queue = $QueuePath; max_items = $MaxItems; flagged_by = $FlaggedBy; reason = $Reason; ids = $idFilter; tier = $Tier; model = $Model; gpu_layers = $GpuLayers; max_tokens = $MaxTokens; temperature = $Temperature; seed = $Seed; escalate_threshold = $EscalateThreshold; dry_run = [bool]$DryRun; selected = $selIds }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Depth 8 -Compress)))

    # ---- envelope confidence + provenance aggregate ----
    if ($confN -gt 0) { $confidence = [Math]::Round(($confSum / $confN), 4) } else { $confidence = $null }
    if ($calls -gt 0 -and $null -ne $provTemplate) {
        $modelProvenance = @(
            [ordered]@{
                model_id = $(if (Has $provTemplate 'model_id') { $provTemplate.model_id } else { $resolvedModel })
                version  = $(if (Has $provTemplate 'version') { $provTemplate.version } else { $null })
                family   = $(if (Has $provTemplate 'family') { $provTemplate.family } else { $null })
                engine   = $(if (Has $provTemplate 'engine') { $provTemplate.engine } else { $null })
                engine_build = $(if (Has $provTemplate 'engine_build') { $provTemplate.engine_build } else { $null })
                device   = $(if (Has $provTemplate 'device') { $provTemplate.device } else { $null })
                mode = 'review'
                calls = $calls
                prompt_tokens_total = $sumP
                completion_tokens_total = $sumC
                total_tokens_total = $(if ($sumT -gt 0) { $sumT } else { $sumP + $sumC })
                runtime_ms_total = $sumRt
                params = [ordered]@{ tier = $Tier; model = $Model; gpu_layers = $GpuLayers; temperature = $Temperature; seed = $Seed; max_tokens = $MaxTokens }
            }
        )
    }

    # ---- open items remaining after this pass ----
    $openRemaining = $totalOpen - $resolvedCount - $escalatedCount
    if ($openRemaining -lt 0) { $openRemaining = 0 }

    # ---- final status ----
    if ($errCount -gt 0 -and ($resolvedCount + $escalatedCount) -gt 0) { $status = 'partial'; $warnings.Add("$errCount item(s) could not be adjudicated (gateway failure); left open") | Out-Null }
    elseif ($errCount -gt 0 -and ($resolvedCount + $escalatedCount) -eq 0) { $status = 'partial'; $warnings.Add("all $errCount selected item(s) failed at the gateway; left open") | Out-Null }
    else { $status = 'ok' }

    $reviewerModelOut = if ($resolvedModel) { $resolvedModel } elseif ($Model) { $Model } else { "tier:$Tier" }
    $result = [ordered]@{
        queue_path = $QueuePath
        dry_run = [bool]$DryRun
        tier = $Tier
        reviewer_model = $reviewerModelOut
        selected_from = $(if ($resolvedSelectedFrom) { $resolvedSelectedFrom } elseif ($Model) { 'model_id' } else { "tier:$Tier" })
        escalate_threshold = $EscalateThreshold
        selected_count = $selected.Count
        resolved_count = $resolvedCount
        escalated_count = $escalatedCount
        error_count = $errCount
        skipped_malformed = $skippedMalformed
        open_remaining = $openRemaining
        queue_written = $wroteQueue
        items = $items.ToArray()
        resolution_log_path = $(if ($wroteLog) { $ResolutionLogPath } elseif ($DryRun) { $null } else { $ResolutionLogPath })
        resolution_count = $resolutionLines.Count
    }
    Write-Diag "pass done: selected=$($selected.Count) resolved=$resolvedCount escalated=$escalatedCount err=$errCount dryRun=$([bool]$DryRun) meanConf=$confidence"
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) — $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    $artList = New-Object System.Collections.Generic.List[object]
    if ($null -ne $result) {
        $rjPath = Join-Path $invDir 'review.json'
        [System.IO.File]::WriteAllText($rjPath, ($result | ConvertTo-Json -Depth 20), $utf8)
        $artList.Add([pscustomobject]@{ p = $rjPath; k = 'json' })

        $md = New-Object System.Collections.Generic.List[string]
        $md.Add("# review.processor — queue drain")
        $md.Add("")
        $md.Add("- queue: ``$($result.queue_path)``")
        $md.Add("- reviewer: ``$($result.reviewer_model)`` (selected_from ``$($result.selected_from)``) · dry_run: $($result.dry_run)")
        $md.Add("- selected: $($result.selected_count) · resolved: $($result.resolved_count) · escalated: $($result.escalated_count) · error: $($result.error_count) · open_remaining: $($result.open_remaining)")
        $md.Add("- escalate_threshold: $($result.escalate_threshold) · mean_reviewer_confidence: $confidence")
        $md.Add("")
        $md.Add("| id | flagged_by | reason | kind | -> status | verdict | rev_conf | decision |")
        $md.Add("|----|-----------|--------|------|-----------|---------|----------|----------|")
        foreach ($it in $result.items) {
            $dec = ''
            if ($null -ne $it.decision) { if ($it.decision -is [System.Array]) { $dec = (@($it.decision) -join ', ') } elseif ($it.decision -is [System.Management.Automation.PSCustomObject]) { $dec = ($it.decision | ConvertTo-Json -Depth 6 -Compress) } else { $dec = [string]$it.decision } }
            $dec = ($dec -replace '\|','\|' -replace '\r?\n',' ')
            $md.Add("| $($it.id) | $($it.flagged_by) | $($it.reason) | $($it.kind) | $($it.new_status) | $($it.verdict) | $($it.reviewer_confidence) | $dec |")
        }
        $md.Add("")
        $md.Add("_Reviewer confidence is a documented structural completeness+validity heuristic (valid JSON verdict, in-set corrected answer, generation completeness), NOT a calibrated correctness score. Items below the escalate threshold — or whose output could not be parsed — are escalated to the frontier. Resolutions are written to the live queue in place (original flagging fields preserved) and appended to an immutable resolution log._")
        $mdPath = Join-Path $invDir 'review.md'
        [System.IO.File]::WriteAllText($mdPath, ([string]::Join("`n", $md.ToArray())), $utf8)
        $artList.Add([pscustomobject]@{ p = $mdPath; k = 'markdown' })
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[review.processor] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)

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
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir; gateway_reviews_suppressed_to = (Join-Path $invDir '_gateway_review_suppressed.jsonl') }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 24
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
