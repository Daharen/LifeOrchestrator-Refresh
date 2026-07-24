#requires -Version 7.0
<#
.SYNOPSIS
  classify.batch — batch categorize/label/extract over a set of text items using a weak local model
  (Life Orchestrator, contract v0.1).
.DESCRIPTION
  The first real consumer of model.gateway (Module 7). For each item in a batch it builds a mode-specific
  prompt, calls the gateway (default -Tier weak = Qwen2.5-1.5B) as a child pwsh process, parses the
  completion into a structured per-item result, computes a CLASSIFICATION-appropriate confidence (a
  documented completeness+validity heuristic, NOT a calibrated correctness score), and routes items below
  the confidence threshold to review_queue.jsonl (flagged_by "classify.batch"). The gateway's own
  review-queue writes are suppressed to an in-artifact file so this skill is the sole, correctly-attributed
  author for the batch.

  Modes:
    classify    — assign exactly one label from a closed -Labels set (also "routing/sorting").
    multilabel  — assign zero or more labels from the closed set.
    extract     — pull a set of named -Fields from each item into a JSON object.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes classified.json +
  classified.md + result.json + stderr.txt (and nests each gateway call's artifacts under gateway/). Exits 0
  whenever a valid envelope is produced (including logical status=error).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '{"mode":"classify","tier":"weak","labels":["animal","vehicle","food"],"items":[{"id":"a","text":"a golden retriever puppy"},{"id":"b","text":"a red pickup truck"}]}'
#>
[CmdletBinding()]
param(
    [string]$Mode = 'classify',
    [string]$Tier = 'weak',
    [string]$Model,
    [object]$Labels,
    [object]$Fields,
    [object]$Items,
    [string]$ItemsPath,
    [int]$MaxTokens = 0,
    [double]$Temperature = 0.0,
    [int]$Seed = 42,
    [int]$MaxInputChars = 2000,
    [double]$ConfidenceThreshold = 0.5,
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

$SKILL_ID = 'classify.batch'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$REVIEW_SCHEMA = 'lifeorch.review.item/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[classify.batch] $m") }
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
# Normalize a candidate label/answer token for matching: strip fences/quotes/punctuation, casefold.
function Get-NormToken([string]$s) {
    if ($null -eq $s) { return '' }
    $t = $s.Trim()
    $t = $t -replace '^```[a-zA-Z]*',''  -replace '```$',''
    $t = $t.Trim()
    # drop a leading "label:" / "category:" / "answer:" prefix
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

# fatal (batch-level) gateway error codes: if the FIRST call hits one, no item can succeed — abort the batch.
$FATAL_GW_CODES = @('model_not_found','model_not_wired','tier_not_found','registry_not_found','no_model_selected','engine_not_found','unsupported_type','unsupported_engine','model_file_missing')

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @()
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$reviewLines = New-Object System.Collections.Generic.List[string]

try {
    # ---- merge -InputsJson (named params win where explicitly set on the command line) ----
    $bound = $PSBoundParameters
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'mode')                 -and -not $bound.ContainsKey('Mode'))                { $Mode = [string]$p.mode }
            if ((Has $p 'tier')                 -and -not $bound.ContainsKey('Tier'))                { $Tier = [string]$p.tier }
            if ((Has $p 'model')                -and -not $bound.ContainsKey('Model'))               { $Model = [string]$p.model }
            if ((Has $p 'labels')               -and -not $bound.ContainsKey('Labels'))              { $Labels = $p.labels }
            if ((Has $p 'fields')               -and -not $bound.ContainsKey('Fields'))              { $Fields = $p.fields }
            if ((Has $p 'items')                -and -not $bound.ContainsKey('Items'))               { $Items = $p.items }
            if ((Has $p 'items_path')           -and -not $bound.ContainsKey('ItemsPath'))           { $ItemsPath = [string]$p.items_path }
            if ((Has $p 'max_tokens')           -and -not $bound.ContainsKey('MaxTokens'))           { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'temperature')          -and -not $bound.ContainsKey('Temperature'))         { $Temperature = [double]$p.temperature }
            if ((Has $p 'seed')                 -and -not $bound.ContainsKey('Seed'))                { $Seed = [int]$p.seed }
            if ((Has $p 'max_input_chars')      -and -not $bound.ContainsKey('MaxInputChars'))       { $MaxInputChars = [int]$p.max_input_chars }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'registry')             -and -not $bound.ContainsKey('Registry'))            { $Registry = [string]$p.registry }
            if ((Has $p 'gateway_path')         -and -not $bound.ContainsKey('GatewayPath'))         { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'pwsh_path')            -and -not $bound.ContainsKey('PwshPath'))            { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path')    -and -not $bound.ContainsKey('ReviewQueuePath'))     { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate mode ----
    $Mode = ([string]$Mode).Trim().ToLowerInvariant()
    if (@('classify','multilabel','extract') -notcontains $Mode) {
        throw [PSCustomObject]@{ code = 'invalid_mode'; message = "mode must be classify|multilabel|extract (got '$Mode')"; retryable = $false }
    }

    # ---- resolve the label / field schema ----
    $labelDefs = @()   # [ {name, description} ]
    $fieldDefs = @()
    function ConvertTo-Defs([object]$raw) {
        $acc = New-Object System.Collections.Generic.List[object]
        foreach ($e in @($raw)) {
            if ($null -eq $e) { continue }
            if ($e -is [string]) { $acc.Add([ordered]@{ name = [string]$e; description = $null }); continue }
            if (Has $e 'name') { $acc.Add([ordered]@{ name = [string]$e.name; description = $(if (Has $e 'description') { [string]$e.description } else { $null }) }) }
        }
        return $acc.ToArray()
    }
    if ($Mode -eq 'extract') {
        $fieldDefs = @(ConvertTo-Defs $Fields)
        if ($fieldDefs.Count -lt 1) { throw [PSCustomObject]@{ code = 'no_fields'; message = "extract mode requires a non-empty -Fields list"; retryable = $false } }
    } else {
        $labelDefs = @(ConvertTo-Defs $Labels)
        if ($labelDefs.Count -lt 1) { throw [PSCustomObject]@{ code = 'no_labels'; message = "$Mode mode requires a non-empty -Labels list"; retryable = $false } }
    }
    # normalized label lookup: normtoken -> canonical name
    $normMap = @{}
    foreach ($ld in $labelDefs) { $k = Get-NormToken $ld.name; if (-not [string]::IsNullOrWhiteSpace($k) -and -not $normMap.ContainsKey($k)) { $normMap[$k] = $ld.name } }

    # ---- resolve the items ----
    $rawItems = @()
    if ($null -ne $Items) { $rawItems = @($Items) }
    elseif (-not [string]::IsNullOrWhiteSpace($ItemsPath)) {
        if (-not (Test-Path -LiteralPath $ItemsPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'items_file_not_found'; message = "items_path not found: $ItemsPath"; retryable = $false } }
        $rawText = Get-Content -LiteralPath $ItemsPath -Raw
        $trimmed = $rawText.TrimStart()
        try {
            if ($trimmed.StartsWith('[')) { $rawItems = @(($rawText | ConvertFrom-Json)) }
            else { $rawItems = @($rawText -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json }) }
        } catch { throw [PSCustomObject]@{ code = 'items_parse_error'; message = "could not parse items_path ($ItemsPath): $($_.Exception.Message)"; retryable = $false } }
    }
    # normalize each item to { id, text }
    $itemList = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($ri in $rawItems) {
        $id = $null; $text = $null
        if ($ri -is [string]) { $text = [string]$ri }
        elseif ($null -ne $ri) {
            if (Has $ri 'text') { $text = [string]$ri.text }
            elseif (Has $ri 'content') { $text = [string]$ri.content }
            if (Has $ri 'id') { $id = [string]$ri.id }
        }
        if ([string]::IsNullOrWhiteSpace($id)) { $id = "item-$idx" }
        $itemList.Add([ordered]@{ id = $id; text = $text })
        $idx++
    }
    if ($itemList.Count -lt 1) { throw [PSCustomObject]@{ code = 'no_items'; message = "provide -Items (array) or -ItemsPath (a non-empty file)"; retryable = $false } }

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

    # ---- per-mode max tokens default ----
    $modeDefaultTokens = @{ classify = 24; multilabel = 48; extract = 220 }
    $genTokens = if ($MaxTokens -gt 0) { $MaxTokens } else { $modeDefaultTokens[$Mode] }

    # ---- suppressed review path for the gateway's own low-confidence writes ----
    $gwArtRoot = Join-Path $invDir 'gateway'
    $gwReviewSuppressed = Join-Path $invDir '_gateway_review_suppressed.jsonl'
    New-Item -ItemType Directory -Path $gwArtRoot -Force | Out-Null

    # ---- build the mode-specific system prompt ----
    function Build-SystemPrompt {
        if ($Mode -eq 'extract') {
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($f in $fieldDefs) { $lines.Add("- $($f.name)" + $(if ($f.description) { ": $($f.description)" } else { '' })) }
            $keys = ($fieldDefs | ForEach-Object { '"' + $_.name + '"' }) -join ', '
            return @"
You are a precise information extractor. From the user's text, extract these fields:
$([string]::Join("`n", $lines.ToArray()))
Respond with ONLY a single minified JSON object whose keys are exactly: $keys.
Use null for any field that is absent. Do not add commentary, code fences, or extra keys.
"@
        }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($l in $labelDefs) { $lines.Add("- $($l.name)" + $(if ($l.description) { ": $($l.description)" } else { '' })) }
        $set = ($labelDefs | ForEach-Object { $_.name }) -join ', '
        if ($Mode -eq 'classify') {
            return @"
You are a precise text classifier. Choose EXACTLY ONE label for the user's text from this exact set:
$([string]::Join("`n", $lines.ToArray()))
Respond with ONLY the single chosen label, copied verbatim from the set ($set). No explanation, no punctuation, no extra words.
"@
        }
        # multilabel
        return @"
You are a precise multi-label text classifier. Choose ZERO OR MORE labels for the user's text from this exact set:
$([string]::Join("`n", $lines.ToArray()))
Respond with ONLY a comma-separated list of chosen labels copied verbatim from the set ($set), or the single word NONE if none apply. No explanation, no extra words.
"@
    }
    $systemPrompt = Build-SystemPrompt

    # ---- gateway invocation helper ----
    function Invoke-Gateway([string]$sys, [string]$userText) {
        $gwArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$GatewayPath,
                    '-System',$sys,'-Prompt',$userText,'-MaxTokens',"$genTokens",'-Temperature',"$Temperature",'-Seed',"$Seed",
                    '-ArtifactRoot',$gwArtRoot,'-ReviewQueuePath',$gwReviewSuppressed)
        if (-not [string]::IsNullOrWhiteSpace($Model)) { $gwArgs += @('-Model',$Model) } else { $gwArgs += @('-Tier',$Tier) }
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

    # ---- run the batch ----
    $items = New-Object System.Collections.Generic.List[object]
    $groups = [ordered]@{}
    $sumP = 0; $sumC = 0; $sumT = 0; $sumRt = 0; $calls = 0
    $provTemplate = $null
    $resolvedModel = $null; $resolvedSelectedFrom = $null
    $confSum = 0.0; $confN = 0
    $okCount = 0; $flaggedCount = 0; $errCount = 0
    $aborted = $false; $abortCode = $null; $abortMsg = $null
    $requestedLabel = $(if ($Mode -eq 'extract') { 'verify_extraction' } else { 'adjudicate_category' })

    function Add-ToGroup([string]$label, [string]$id) {
        if (-not $groups.Contains($label)) { $groups[$label] = New-Object System.Collections.Generic.List[string] }
        $groups[$label].Add($id)
    }

    $itemIndex = 0
    foreach ($it in $itemList.ToArray()) {
        $itemIndex++
        $id = [string]$it.id
        $text = [string]$it.text
        $preview = if ($null -ne $text) { if ($text.Length -gt 160) { $text.Substring(0,160) } else { $text } } else { '' }

        # guard: empty item text -> error item, no gateway call
        if ([string]::IsNullOrWhiteSpace($text)) {
            $errCount++; $flaggedCount++
            $rid = "rq-$($InvocationId.Substring(0,8))-$id"
            $items.Add([ordered]@{ id = $id; input_preview = $preview; status = 'error'; label = $null; labels = @(); extracted = $null;
                confidence = 0.1; finish_reason = $null; parsed = $false; in_set = $false; prompt_tokens = $null; completion_tokens = $null;
                raw_preview = $null; flagged = $true; flag_reason = 'failed_transform'; review_id = $rid; error = 'empty item text' })
            $reviewLines.Add((([ordered]@{ schema=$REVIEW_SCHEMA; id=$rid; created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='failed_transform'; confidence=0.1; source_ref="artifact://$invDir/classified.json#$id"; weak_result=@{ mode=$Mode; item_id=$id; note='empty input text' }; requested=$requestedLabel; status='open'; resolution=$null; escalated_to=$null }) | ConvertTo-Json -Depth 8 -Compress))
            if ($Mode -ne 'extract') { Add-ToGroup '(unlabeled)' $id }
            continue
        }

        $inText = if ($text.Length -gt $MaxInputChars) { $text.Substring(0,$MaxInputChars) } else { $text }
        $gw = Invoke-Gateway $systemPrompt $inText
        $gwEnv = $gw.envelope

        # gateway-level error envelope?
        if ($null -eq $gwEnv -or -not (Has $gwEnv 'status')) {
            $errCount++; $flaggedCount++
            $rid = "rq-$($InvocationId.Substring(0,8))-$id"
            $msg = if ($gw.parse_error) { $gw.parse_error } else { 'gateway returned no valid envelope' }
            $items.Add([ordered]@{ id=$id; input_preview=$preview; status='error'; label=$null; labels=@(); extracted=$null; confidence=0.1; finish_reason=$null; parsed=$false; in_set=$false; prompt_tokens=$null; completion_tokens=$null; raw_preview=$null; flagged=$true; flag_reason='failed_transform'; review_id=$rid; error=$msg })
            $reviewLines.Add((([ordered]@{ schema=$REVIEW_SCHEMA; id=$rid; created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='failed_transform'; confidence=0.1; source_ref="artifact://$invDir/classified.json#$id"; weak_result=@{ mode=$Mode; item_id=$id; note=$msg }; requested=$requestedLabel; status='open'; resolution=$null; escalated_to=$null }) | ConvertTo-Json -Depth 8 -Compress))
            if ($Mode -ne 'extract') { Add-ToGroup '(unlabeled)' $id }
            Write-Diag "item ${id}: gateway produced no envelope ($msg)"
            continue
        }
        if ($gwEnv.status -eq 'error') {
            $gcode = if ((Has $gwEnv 'error') -and ($null -ne $gwEnv.error) -and (Has $gwEnv.error 'code')) { [string]$gwEnv.error.code } else { 'gateway_error' }
            $gmsg  = if ((Has $gwEnv 'error') -and ($null -ne $gwEnv.error) -and (Has $gwEnv.error 'message')) { [string]$gwEnv.error.message } else { 'gateway error' }
            if ($calls -eq 0 -and $FATAL_GW_CODES -contains $gcode) {
                # first call, batch-fatal config error -> abort the whole batch cleanly
                $aborted = $true; $abortCode = $gcode; $abortMsg = $gmsg
                Write-Diag "batch-fatal gateway error on first item ($gcode): $gmsg — aborting batch"
                break
            }
            $errCount++; $flaggedCount++
            $rid = "rq-$($InvocationId.Substring(0,8))-$id"
            $items.Add([ordered]@{ id=$id; input_preview=$preview; status='error'; label=$null; labels=@(); extracted=$null; confidence=0.1; finish_reason=$null; parsed=$false; in_set=$false; prompt_tokens=$null; completion_tokens=$null; raw_preview=$null; flagged=$true; flag_reason='failed_transform'; review_id=$rid; error="${gcode}: $gmsg" })
            $reviewLines.Add((([ordered]@{ schema=$REVIEW_SCHEMA; id=$rid; created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='failed_transform'; confidence=0.1; source_ref="artifact://$invDir/classified.json#$id"; weak_result=@{ mode=$Mode; item_id=$id; gateway_error=$gcode; note=$gmsg }; requested=$requestedLabel; status='open'; resolution=$null; escalated_to=$null }) | ConvertTo-Json -Depth 8 -Compress))
            if ($Mode -ne 'extract') { Add-ToGroup '(unlabeled)' $id }
            Write-Diag "item ${id}: gateway error $gcode"
            continue
        }

        # success — pull the model output + provenance
        $calls++
        $answer = ''
        if ((Has $gwEnv 'result') -and ($null -ne $gwEnv.result) -and (Has $gwEnv.result 'output') -and (Has $gwEnv.result.output 'text')) { $answer = [string]$gwEnv.result.output.text }
        $finish = 'unknown'
        if ((Has $gwEnv 'result') -and ($null -ne $gwEnv.result) -and (Has $gwEnv.result 'generation') -and (Has $gwEnv.result.generation 'finish_reason')) { $finish = [string]$gwEnv.result.generation.finish_reason }
        $pt = $null; $ct = $null
        if ((Has $gwEnv 'model_provenance')) {
            $mp = @($gwEnv.model_provenance)
            if ($mp.Count -ge 1) {
                $p0 = $mp[0]
                if (Has $p0 'prompt_tokens') { $pt = $p0.prompt_tokens }
                if (Has $p0 'completion_tokens') { $ct = $p0.completion_tokens }
                if ($null -ne $pt) { $sumP += [int]$pt }
                if ($null -ne $ct) { $sumC += [int]$ct }
                if ((Has $p0 'total_tokens') -and $null -ne $p0.total_tokens) { $sumT += [int]$p0.total_tokens }
                if ((Has $p0 'runtime_ms') -and $null -ne $p0.runtime_ms) { $sumRt += [int]$p0.runtime_ms }
                if ($null -eq $provTemplate) { $provTemplate = $p0 }
            }
        }
        if (($null -eq $resolvedModel) -and (Has $gwEnv 'result') -and (Has $gwEnv.result 'model')) { $resolvedModel = [string]$gwEnv.result.model }
        if (($null -eq $resolvedSelectedFrom) -and (Has $gwEnv 'result') -and (Has $gwEnv.result 'selected_from')) { $resolvedSelectedFrom = [string]$gwEnv.result.selected_from }
        $rawPrev = if ($answer.Length -gt 160) { $answer.Substring(0,160) } else { $answer }
        $truncated = ($finish -eq 'length')

        # ---- parse + confidence per mode ----
        $itemLabel = $null; $itemLabels = @(); $itemExtract = $null; $inSet = $false; $parsed = $false
        $conf = 0.1; $flagReason = $null

        if ($Mode -eq 'classify') {
            $ans = Get-NormToken $answer
            if ([string]::IsNullOrWhiteSpace($answer)) { $conf = 0.1; $flagReason = 'malformed' }
            elseif ($normMap.ContainsKey($ans)) { $itemLabel = $normMap[$ans]; $inSet = $true; $parsed = $true; $conf = 0.8 }
            else {
                # fuzzy: a known label appears as a token/substring in the answer
                $firstLine = ($answer -split "`n")[0]
                $ansN = Get-NormToken $firstLine
                $hit = $null
                foreach ($k in $normMap.Keys) { if ($ansN -eq $k) { $hit = $k; break } }
                if ($null -eq $hit) { foreach ($k in ($normMap.Keys | Sort-Object { $_.Length } -Descending)) { if ($ansN -match ('\b' + [regex]::Escape($k) + '\b')) { $hit = $k; break } } }
                if ($null -ne $hit) { $itemLabel = $normMap[$hit]; $inSet = $true; $parsed = $true; $conf = 0.6 }
                else { $itemLabel = $null; $inSet = $false; $parsed = $true; $conf = 0.2; $flagReason = 'uncategorized' }
            }
            if ($truncated) { $conf = [Math]::Min($conf, 0.4) }
            $grpKey = if ($null -ne $itemLabel) { $itemLabel } else { '(unlabeled)' }
            Add-ToGroup $grpKey $id
        }
        elseif ($Mode -eq 'multilabel') {
            if ([string]::IsNullOrWhiteSpace($answer)) { $conf = 0.15; $flagReason = 'malformed' }
            else {
                $toks = @($answer -split '[,\n;]' | ForEach-Object { Get-NormToken $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($toks.Count -eq 1 -and $toks[0] -eq 'none') { $itemLabels = @(); $parsed = $true; $inSet = $true; $conf = 0.7 }
                else {
                    $kept = New-Object System.Collections.Generic.List[string]
                    $dropped = 0
                    foreach ($t in $toks) { if ($normMap.ContainsKey($t)) { $c = $normMap[$t]; if (-not $kept.Contains($c)) { $kept.Add($c) } } else { $dropped++ } }
                    $itemLabels = $kept.ToArray()
                    $parsed = $true
                    if ($dropped -eq 0 -and $itemLabels.Count -ge 1) { $inSet = $true; $conf = 0.75 }
                    elseif ($itemLabels.Count -ge 1) { $inSet = $false; $conf = 0.5 }
                    else { $inSet = $false; $conf = 0.2; $flagReason = 'uncategorized' }
                }
                if ($truncated) { $conf = [Math]::Min($conf, 0.4) }
            }
            if ($itemLabels.Count -eq 0) { Add-ToGroup '(none)' $id } else { foreach ($lab in $itemLabels) { Add-ToGroup $lab $id } }
        }
        else { # extract
            $jsonStr = Get-FirstJsonObject $answer
            $obj = $null
            if ($null -ne $jsonStr) { try { $obj = $jsonStr | ConvertFrom-Json } catch { $obj = $null } }
            $ext = [ordered]@{}
            if ($null -ne $obj) {
                $present = 0
                foreach ($f in $fieldDefs) {
                    $v = $null
                    if (Has $obj $f.name) { $v = $obj.$($f.name) }
                    $ext[$f.name] = $v
                    if ($null -ne $v -and -not ([string]::IsNullOrWhiteSpace([string]$v))) { $present++ }
                }
                $itemExtract = $ext; $parsed = $true
                if ($present -eq $fieldDefs.Count) { $inSet = $true; $conf = 0.75 }
                elseif ($present -ge 1) { $inSet = $false; $conf = 0.5 }
                else { $inSet = $false; $conf = 0.3; $flagReason = 'failed_transform' }
            } else {
                foreach ($f in $fieldDefs) { $ext[$f.name] = $null }
                $itemExtract = $ext; $parsed = $false
                if ([string]::IsNullOrWhiteSpace($answer)) { $conf = 0.1 } else { $conf = 0.3 }
                $flagReason = 'malformed'
            }
            if ($truncated) { $conf = [Math]::Min($conf, 0.4) }
        }

        if ($truncated) { $warnings.Add("item $id truncated at max_tokens=$genTokens (finish_reason=length)") | Out-Null }

        $flagged = ($conf -lt $ConfidenceThreshold)
        if ($flagged) {
            $flaggedCount++
            if ($null -eq $flagReason) { $flagReason = 'low_confidence' }
            $rid = "rq-$($InvocationId.Substring(0,8))-$id"
            $wr = [ordered]@{ mode = $Mode; model = $resolvedModel; item_id = $id; finish_reason = $finish; text_preview = $rawPrev }
            if ($Mode -eq 'classify') { $wr.label = $itemLabel }
            elseif ($Mode -eq 'multilabel') { $wr.labels = $itemLabels }
            else { $wr.extracted = $itemExtract }
            $reviewLines.Add((([ordered]@{ schema=$REVIEW_SCHEMA; id=$rid; created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$flagReason; confidence=$conf; source_ref="artifact://$invDir/classified.json#$id"; weak_result=$wr; requested=$requestedLabel; status='open'; resolution=$null; escalated_to=$null }) | ConvertTo-Json -Depth 8 -Compress))
        } else {
            $okCount++
        }
        $reviewId = if ($flagged) { "rq-$($InvocationId.Substring(0,8))-$id" } else { $null }

        $confSum += $conf; $confN++

        $itemObj = [ordered]@{ id=$id; input_preview=$preview; status='ok'; confidence=$conf; finish_reason=$finish; parsed=$parsed; in_set=$inSet; prompt_tokens=$pt; completion_tokens=$ct; raw_preview=$rawPrev; flagged=$flagged; flag_reason=$flagReason; review_id=$reviewId; error=$null }
        if ($Mode -eq 'classify') { $itemObj.label = $itemLabel }
        elseif ($Mode -eq 'multilabel') { $itemObj.labels = $itemLabels }
        else { $itemObj.extracted = $itemExtract }
        $items.Add($itemObj)
        Write-Diag "item ${id}: conf=$conf finish=$finish flagged=$flagged"
    }

    # ---- batch-fatal abort? ----
    if ($aborted) {
        throw [PSCustomObject]@{ code = $abortCode; message = "gateway could not run the batch: $abortMsg"; retryable = $false }
    }

    # ---- inputs digest ----
    $digestItems = @($itemList.ToArray() | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
    $normInputs = [ordered]@{ mode=$Mode; model=$Model; tier=$Tier; labels=@($labelDefs | ForEach-Object { $_.name }); fields=@($fieldDefs | ForEach-Object { $_.name }); items=$digestItems; max_tokens=$genTokens; temperature=$Temperature; seed=$Seed; confidence_threshold=$ConfidenceThreshold }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Depth 12 -Compress)))

    # ---- groups -> plain arrays ----
    $groupsOut = [ordered]@{}
    foreach ($k in $groups.Keys) { $groupsOut[$k] = $groups[$k].ToArray() }

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
                mode = 'batch'
                calls = $calls
                prompt_tokens_total = $sumP
                completion_tokens_total = $sumC
                total_tokens_total = $(if ($sumT -gt 0) { $sumT } else { $sumP + $sumC })
                runtime_ms_total = $sumRt
                params = [ordered]@{ tier=$Tier; model=$Model; temperature=$Temperature; seed=$Seed; max_tokens=$genTokens }
            }
        )
    }

    # ---- final status ----
    if ($errCount -gt 0 -and $okCount -gt 0) { $status = 'partial'; $warnings.Add("$errCount of $($items.Count) item(s) failed") | Out-Null }
    elseif ($errCount -gt 0 -and $okCount -eq 0) { $status = 'partial'; $warnings.Add("all $errCount item(s) failed at the model call") | Out-Null }
    else { $status = 'ok' }

    $result = [ordered]@{
        mode = $Mode
        model = $(if ($resolvedModel) { $resolvedModel } elseif ($Model) { $Model } else { "tier:$Tier" })
        selected_from = $(if ($resolvedSelectedFrom) { $resolvedSelectedFrom } elseif ($Model) { 'model_id' } else { "tier:$Tier" })
        count = $items.Count
        ok_count = $okCount
        flagged_count = $flaggedCount
        error_count = $errCount
        confidence_threshold = $ConfidenceThreshold
        max_tokens = $genTokens
        temperature = $Temperature
        seed = $Seed
        items = $items.ToArray()
        groups = $groupsOut
        review_count = $reviewLines.Count
    }
    if ($Mode -eq 'extract') { $result.fields = @($fieldDefs | ForEach-Object { $_.name }) }
    else { $result.labels = @($labelDefs | ForEach-Object { $_.name }) }
    Write-Diag "batch done: ok=$okCount flagged=$flaggedCount err=$errCount calls=$calls meanConf=$confidence"
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
        $cjPath = Join-Path $invDir 'classified.json'
        [System.IO.File]::WriteAllText($cjPath, ($result | ConvertTo-Json -Depth 20), $utf8)
        $artList.Add([pscustomobject]@{ p = $cjPath; k = 'json' })

        # human-readable markdown
        $md = New-Object System.Collections.Generic.List[string]
        $md.Add("# classify.batch — $($result.mode)")
        $md.Add("")
        $md.Add("- model: ``$($result.model)`` (selected_from ``$($result.selected_from)``)")
        $md.Add("- items: $($result.count) · ok: $($result.ok_count) · flagged: $($result.flagged_count) · error: $($result.error_count)")
        $md.Add("- confidence_threshold: $($result.confidence_threshold) · mean_confidence: $confidence")
        $md.Add("")
        if ($Mode -eq 'extract') {
            $md.Add("| id | " + (@($fieldDefs | ForEach-Object { $_.name }) -join ' | ') + " | conf | flagged |")
            $md.Add("|----|" + (@($fieldDefs | ForEach-Object { '----' }) -join '|') + "|------|---------|")
            foreach ($it in $result.items) {
                $cells = @($fieldDefs | ForEach-Object { $n = $_.name; $v = if (($null -ne $it.extracted) -and ($it.extracted.Contains($n)) -and ($null -ne $it.extracted[$n])) { [string]$it.extracted[$n] } else { '' }; ($v -replace '\|','\|' -replace '\r?\n',' ') })
                $md.Add("| $($it.id) | " + ($cells -join ' | ') + " | $($it.confidence) | $($it.flagged) |")
            }
        } elseif ($Mode -eq 'multilabel') {
            $md.Add("| id | labels | conf | flagged | preview |")
            $md.Add("|----|--------|------|---------|---------|")
            foreach ($it in $result.items) { $md.Add("| $($it.id) | $((@($it.labels)) -join ', ') | $($it.confidence) | $($it.flagged) | $(([string]$it.input_preview) -replace '\|','\|' -replace '\r?\n',' ') |") }
        } else {
            $md.Add("| id | label | conf | flagged | preview |")
            $md.Add("|----|-------|------|---------|---------|")
            foreach ($it in $result.items) { $md.Add("| $($it.id) | $($it.label) | $($it.confidence) | $($it.flagged) | $(([string]$it.input_preview) -replace '\|','\|' -replace '\r?\n',' ') |") }
        }
        $md.Add("")
        $md.Add("## groups")
        foreach ($k in $result.groups.Keys) { $md.Add("- **$k**: " + ((@($result.groups[$k])) -join ', ')) }
        $md.Add("")
        $md.Add("_Confidence is a documented completeness+validity heuristic (in-set match, parse success, generation completeness), NOT a calibrated correctness score. Items below the threshold are appended to the review queue._")
        $mdPath = Join-Path $invDir 'classified.md'
        [System.IO.File]::WriteAllText($mdPath, ([string]::Join("`n", $md.ToArray())), $utf8)
        $artList.Add([pscustomobject]@{ p = $mdPath; k = 'markdown' })
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[classify.batch] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)

    foreach ($a in $artList.ToArray()) {
        $b = [System.IO.File]::ReadAllBytes($a.p)
        $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $a.p).Path; kind = $a.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
    }
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue append (this skill is the sole author for the batch) ----
try {
    if ($reviewLines.Count -gt 0 -and $status -ne 'error') {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        [System.IO.File]::AppendAllText($rqPath, ([string]::Join("`n", $reviewLines.ToArray()) + "`n"), $utf8)
        if ($null -ne $result) { $result.review_queue_path = (Resolve-Path -LiteralPath $rqPath -ErrorAction SilentlyContinue).Path; if ($null -eq $result.review_queue_path) { $result.review_queue_path = $rqPath } }
        $warnings.Add("appended $($reviewLines.Count) item(s) to review queue: $rqPath") | Out-Null
        Write-Diag "review-queued $($reviewLines.Count) item(s) -> $rqPath"
        # re-write classified.json so review_queue_path is reflected, and refresh its artifact hash
        if ($null -ne $result) {
            $cjPath = Join-Path $invDir 'classified.json'
            [System.IO.File]::WriteAllText($cjPath, ($result | ConvertTo-Json -Depth 20), $utf8)
            $nb = [System.IO.File]::ReadAllBytes($cjPath)
            for ($i = 0; $i -lt $artifacts.Count; $i++) { if ($artifacts[$i].path -eq (Resolve-Path -LiteralPath $cjPath).Path) { $artifacts[$i].bytes = $nb.Length; $artifacts[$i].sha256 = (Get-Sha256Hex $nb) } }
        }
    } elseif ($null -ne $result -and -not (Has $result 'review_queue_path')) {
        $result.review_queue_path = $null
    }
} catch { Write-Diag "review-queue append failed: $($_.Exception.Message)" }

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
