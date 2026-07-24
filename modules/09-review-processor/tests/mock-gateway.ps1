#requires -Version 7.0
# MOCK model.gateway for CLOUD-ONLY logic testing of review.processor (no GPU/Windows).
# Emits a lifeorch.skill.result/0.1 envelope shaped like the real gateway, whose result.output.text is a
# reviewer-style JSON verdict derived deterministically from the -System (kind) + -Prompt (item content), so
# review.processor's select/parse/adjudicate/queue-rewrite/escalation/log logic can be exercised end-to-end on
# Linux. NOT shipped to the device; the real gateway (a stronger local model) is used there.
[CmdletBinding()]
param(
    [string]$Model,[string]$Tier,[string]$Prompt,[string]$System,
    [int]$MaxTokens = 256,[double]$Temperature = 0.7,[double]$TopP = 0.95,[int]$TopK = 40,[int]$Seed = -1,
    [string[]]$Stop,[string]$Registry,[int]$Port = 0,[int]$GpuLayers = -1,[int]$Context = 0,[int]$LoadTimeoutSec = 120,
    [string]$ReviewQueuePath,[string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),[string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow

# batch-fatal simulation (first-call config error path)
if ($Model -eq 'llm.bogus') {
    $env = [ordered]@{ schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'; invocation_id=$InvocationId; status='error'; started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=1; inputs_digest=('sha256:'+('0'*64)); result=$null; confidence=$null; artifacts=@(); model_provenance=@(); diagnostics=@{log='stderr.txt'}; warnings=@(); error=[ordered]@{ code='model_not_found'; message='bogus'; retryable=$false } }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20)); exit 0
}

$p = ($Prompt).ToLowerInvariant()
$finish = 'stop'
if ($p -match 'force_length') { $finish = 'length' }

# detect the reviewer kind from the system prompt
$kind = 'generic'
if ($System -match 'single correct category') { $kind = 'category_single' }
elseif ($System -match 'multi-label') { $kind = 'category_multi' }
elseif ($System -match 'extraction reviewer') { $kind = 'extraction' }
elseif ($System -match 'output-quality reviewer') { $kind = 'generation' }

# pull the ALLOWED LABELS line if present
$allowed = @()
$mAllow = [regex]::Match($Prompt, '(?im)^ALLOWED LABELS:\s*(.+)$')
if ($mAllow.Success) { $allowed = @($mAllow.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

function Pick-Label {
    $lab = if ($allowed.Count -gt 0) { $allowed[0] } else { 'animal' }
    if ($p -match 'puppy|dog|retriever|cat|kitten|animal|horse') { $lab = ($allowed | Where-Object { $_ -match 'animal' } | Select-Object -First 1) }
    elseif ($p -match 'truck|car|vehicle|bus|bike') { $lab = ($allowed | Where-Object { $_ -match 'vehicle' } | Select-Object -First 1) }
    elseif ($p -match 'ramen|bowl|food|pizza|sushi|noodle') { $lab = ($allowed | Where-Object { $_ -match 'food' } | Select-Object -First 1) }
    if ([string]::IsNullOrWhiteSpace($lab)) { $lab = if ($allowed.Count -gt 0) { $allowed[0] } else { 'animal' } }
    return $lab
}

$text = ''
if ($p -match 'force_empty') { $text = '' }
elseif ($p -match 'force_badjson') { $text = 'I believe the correct answer is probably an animal, but I am not fully certain.' }
elseif ($p -match 'force_escalate') { $text = '{"verdict":"uncertain","answer":null,"confidence":0.2,"escalate":true,"rationale":"insufficient context to decide"}' }
elseif ($kind -eq 'category_single') {
    $lab = Pick-Label
    $text = ('{"verdict":"confirm","answer":"' + $lab + '","confidence":0.9,"escalate":false,"rationale":"the item clearly matches ' + $lab + '"}')
}
elseif ($kind -eq 'category_multi') {
    $lab = Pick-Label
    $text = ('{"verdict":"correct","answer":["' + $lab + '"],"confidence":0.85,"escalate":false,"rationale":"one label applies"}')
}
elseif ($kind -eq 'extraction') {
    $text = '{"verdict":"correct","answer":{"animal":"dog","color":"brown"},"confidence":0.85,"escalate":false,"rationale":"corrected from the text"}'
}
elseif ($kind -eq 'generation') {
    $verdict = if ($p -match 'regenerate|truncat|incomplete') { 'reject' } else { 'confirm' }
    $ans = if ($verdict -eq 'reject') { 'regenerate' } else { 'acceptable' }
    $text = ('{"verdict":"' + $verdict + '","answer":"' + $ans + '","confidence":0.8,"escalate":false,"rationale":"quality judged from the output"}')
}
else {
    $text = '{"verdict":"confirm","answer":"ok","confidence":0.7,"escalate":false,"rationale":"generic adjudication"}'
}

$ct = [Math]::Max(1, ($text -split '\s+').Count)
$conf = $(if ([string]::IsNullOrWhiteSpace($text)) { 0.1 } elseif ($finish -eq 'length') { 0.4 } else { 0.7 })
$env = [ordered]@{
    schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'
    invocation_id=$InvocationId; status=$(if ([string]::IsNullOrWhiteSpace($text)) { 'partial' } else { 'ok' })
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=5
    inputs_digest=('sha256:'+('a'*64))
    result=[ordered]@{
        model=$(if ($Model) { $Model } else { 'llm.weak.qwen2p5-3b' }); engine='llama-server'; mode='chat'
        selected_from=$(if ($Model) { 'model_id' } else { "tier:$Tier" })
        request=[ordered]@{ max_tokens=$MaxTokens; temperature=$Temperature }
        output=[ordered]@{ role='assistant'; text=$text }
        generation=[ordered]@{ finish_reason=$finish; prompt_tokens=42; completion_tokens=$ct; total_tokens=(42+$ct); timings=$null }
        server=[ordered]@{ port=8140; health_ms=200; gpu_layers=$(if ($GpuLayers -ge 0) { $GpuLayers } else { 28 }); context=4096 }
    }
    confidence=$conf
    artifacts=@()
    model_provenance=@([ordered]@{ model_id=$(if ($Model) { $Model } else { 'llm.weak.qwen2p5-3b' }); version='mock'; family='qwen2.5'; engine='llama-server'; engine_build='mock'; device='cpu'; params=@{}; prompt_tokens=42; completion_tokens=$ct; total_tokens=(42+$ct); finish_reason=$finish; timings=$null; runtime_ms=200 })
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$ArtifactRoot }
    warnings=@(); error=$null
}
# emulate the real gateway's own review-queue append on low confidence (to prove review.processor suppresses it)
if ($env.confidence -lt 0.5 -and -not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) {
    $line = ([ordered]@{ schema='lifeorch.review.item/0.1'; id='gwrq'; flagged_by='model.gateway'; reason='low_confidence'; confidence=$env.confidence } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText($ReviewQueuePath, $line + "`n", $utf8)
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
