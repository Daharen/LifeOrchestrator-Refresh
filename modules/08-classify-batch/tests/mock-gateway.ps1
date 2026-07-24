#requires -Version 7.0
# MOCK model.gateway for CLOUD-ONLY logic testing of classify.batch (no GPU/Windows).
# Emits a lifeorch.skill.result/0.1 envelope shaped like the real gateway, deriving the "model output"
# deterministically from the -Prompt so classify.batch's parse/confidence/group/review logic can be
# exercised end-to-end on Linux. NOT shipped to the device; the real gateway is used there.
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

# batch-fatal simulation
if ($Model -eq 'llm.bogus') {
    $env = [ordered]@{ schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'; invocation_id=$InvocationId; status='error'; started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=1; inputs_digest=('sha256:'+('0'*64)); result=$null; confidence=$null; artifacts=@(); model_provenance=@(); diagnostics=@{log='stderr.txt'}; warnings=@(); error=[ordered]@{ code='model_not_found'; message='bogus'; retryable=$false } }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20)); exit 0
}

$p = ($Prompt).ToLowerInvariant()
$isExtract = ($System -match 'JSON object')
$isMulti = ($System -match 'ZERO OR MORE')
$finish = 'stop'
$text = ''

if ($p -match 'force_empty') { $text = ''; $finish = 'stop' }
elseif ($isExtract) {
    $finish = if ($p -match 'force_length') { 'length' } else { 'stop' }
    $name = 'Ada Lovelace'; $topic = 'computing'
    if ($p -match 'ocean') { $name = 'null'; $topic = 'oceanography' }
    if ($p -match 'force_bad_json') { $text = 'sorry, I cannot' }
    else { $text = ('{"name": "' + $name + '", "topic": "' + $topic + '"}') }
}
else {
    if ($p -match 'force_length') { $finish = 'length' }
    $label = 'animal'
    if ($p -match 'puppy|dog|retriever|cat|animal') { $label = 'animal' }
    elseif ($p -match 'truck|car|vehicle|bike') { $label = 'vehicle' }
    elseif ($p -match 'ramen|bowl|food|pizza|sushi') { $label = 'food' }
    elseif ($p -match 'force_oov') { $label = 'spaceship' }  # out-of-vocab
    if ($p -match 'force_multi' -and $isMulti) { $text = 'animal, food' }
    elseif ($p -match 'force_none' -and $isMulti) { $text = 'NONE' }
    else { $text = $label }
}

$ct = [Math]::Max(1, ($text -split '\s+').Count)
$env = [ordered]@{
    schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'
    invocation_id=$InvocationId; status=$(if ([string]::IsNullOrWhiteSpace($text)) { 'partial' } else { 'ok' })
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=5
    inputs_digest=('sha256:'+('a'*64))
    result=[ordered]@{
        model=$(if ($Model) { $Model } else { 'llm.weak.qwen2p5-1p5b' }); engine='llama-server'; mode='chat'
        selected_from=$(if ($Model) { 'model_id' } else { "tier:$Tier" })
        request=[ordered]@{ max_tokens=$MaxTokens; temperature=$Temperature }
        output=[ordered]@{ role='assistant'; text=$text }
        generation=[ordered]@{ finish_reason=$finish; prompt_tokens=17; completion_tokens=$ct; total_tokens=(17+$ct); timings=$null }
        server=[ordered]@{ port=8140; health_ms=120; gpu_layers=99; context=4096 }
    }
    confidence=$(if ([string]::IsNullOrWhiteSpace($text)) { 0.1 } elseif ($finish -eq 'length') { 0.4 } else { 0.7 })
    artifacts=@()
    model_provenance=@([ordered]@{ model_id=$(if ($Model) { $Model } else { 'llm.weak.qwen2p5-1p5b' }); version='mock'; family='qwen2.5'; engine='llama-server'; engine_build='mock'; device='cpu'; params=@{}; prompt_tokens=17; completion_tokens=$ct; total_tokens=(17+$ct); finish_reason=$finish; timings=$null; runtime_ms=120 })
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$ArtifactRoot }
    warnings=@(); error=$null
}
# emulate the real gateway's own review-queue append on low confidence (to prove classify.batch suppresses it)
if ($env.confidence -lt 0.5 -and -not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) {
    $line = ([ordered]@{ schema='lifeorch.review.item/0.1'; id='gwrq'; flagged_by='model.gateway'; reason='low_confidence'; confidence=$env.confidence } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText($ReviewQueuePath, $line + "`n", $utf8)
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
