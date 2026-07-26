#requires -Version 7.0
<#
  MOCK model.gateway for CLOUD-ONLY logic testing of route.tools (no GPU/Windows).
  Emits a lifeorch.skill.result/0.1 envelope shaped like the real gateway; its result.output.text is a
  deterministic ROUTER completion (normally a JSON array of tool ids), derived from a directive embedded in
  the REQUEST line of the router USER prompt (which route.tools forwards via -InputsJson {system,prompt,...}).

  Directive (in the request text): "ROUTE_EMIT=<spec>"
    ROUTE_EMIT=gen.image            -> output ["gen.image"]
    ROUTE_EMIT=gen.image,notatool   -> output ["gen.image","notatool"]  (notatool is gated out downstream)
    ROUTE_EMIT=none                 -> output []                          (legitimate "no tool fits")
    ROUTE_EMIT=prose                -> output prose with NO array          (thinking-model sim; parse fails)
    ROUTE_EMIT=fenced:gen.image     -> output prose + a ```json fenced array (tolerant extraction test)
    ROUTE_EMIT=truncate:gen.image   -> output ["gen.image"] with finish_reason=length
    rq                              -> also append a mock low-confidence review line to review_queue_path
  With no directive, a keyword heuristic maps the request to a plausible array.
  NOT shipped to the device; the real gateway (real local models) is used there.
#>
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

function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
# route.tools calls the gateway with -InputsJson only; parse it for tier/system/prompt/review_queue_path.
if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
    try {
        $p = $InputsJson | ConvertFrom-Json
        if (Has $p 'tier')   { $Tier = [string]$p.tier }
        if (Has $p 'system') { $System = [string]$p.system }
        if (Has $p 'prompt') { $Prompt = [string]$p.prompt }
        if (Has $p 'seed')   { $Seed = [int]$p.seed }
        if (Has $p 'review_queue_path') { $ReviewQueuePath = [string]$p.review_queue_path }
    } catch { }
}

# extract the REQUEST line from the router user prompt
$request = ''
$mReq = [regex]::Match([string]$Prompt, '(?im)^REQUEST:\s*(.+)$')
if ($mReq.Success) { $request = $mReq.Groups[1].Value.Trim() }

$finish = 'stop'
$text = '[]'
$mEmit = [regex]::Match($request, '(?i)ROUTE_EMIT=([^\s]+)')
if ($mEmit.Success) {
    $spec = $mEmit.Groups[1].Value
    if ($spec -ieq 'none') { $text = '[]' }
    elseif ($spec -ieq 'prose') { $text = 'The request needs an image generator and a file writer to save it.' }
    elseif ($spec -imatch '^fenced:(.+)$') {
        $ids = ($matches[1] -split ',' | ForEach-Object { '"' + $_.Trim() + '"' }) -join ','
        $fence = ([char]96).ToString() * 3   # three backticks, avoids double-quote escaping
        $nl = [char]10
        $text = 'Here is the plan:' + $nl + $fence + 'json' + $nl + "[$ids]" + $nl + $fence
    }
    elseif ($spec -imatch '^truncate:(.+)$') {
        # a complete array, but the model would have kept going -> finish_reason=length (confidence 0.4 branch)
        $ids = ($matches[1] -split ',' | ForEach-Object { '"' + $_.Trim() + '"' }) -join ','
        $text = "[$ids]"; $finish = 'length'
    }
    else {
        $ids = ($spec -split ',' | ForEach-Object { '"' + $_.Trim() + '"' }) -join ','
        $text = "[$ids]"
    }
} else {
    # keyword heuristic over the catalog request
    $r = $request.ToLowerInvariant()
    $picks = @()
    if ($r -match 'imag|picture|photo|draw|dog|cat|sunset') { $picks += 'gen.image' }
    if ($r -match 'music|melod|song|piano|instrument') { $picks += 'gen.music' }
    if ($r -match 'screen|on my screen|what does the text') { $picks += 'ocr.layout' }
    elseif ($r -match 'transcrib|audio|speech|\.wav') { $picks += 'speech.stt' }
    if ($r -match 'write|append|save.*file|read .*file|edit') { $picks += 'doc.io' }
    if ($r -match 'list|find .*files|what files') { $picks += 'fs.observer' }
    $picks = @($picks | Select-Object -Unique)
    if ($picks.Count -eq 0) { $text = '[]' } else { $text = '[' + (($picks | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']' }
}

$ct = [Math]::Max(1, ($text -split '\s+').Count)
$conf = if ($finish -eq 'length') { 0.4 } else { 0.7 }
$env = [ordered]@{
    schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'
    invocation_id=$InvocationId; status='ok'
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=4
    inputs_digest=('sha256:'+('a'*64))
    result=[ordered]@{
        model=('llm.mock.' + $Tier); engine='llama-server'; mode='chat'; selected_from=("tier:$Tier")
        request=[ordered]@{ max_tokens=$MaxTokens; temperature=$Temperature; seed=$Seed }
        output=[ordered]@{ role='assistant'; text=$text }
        generation=[ordered]@{ finish_reason=$finish; prompt_tokens=40; completion_tokens=$ct; total_tokens=(40+$ct); timings=$null }
        server=[ordered]@{ port=8140; health_ms=4; gpu_layers=$(if ($GpuLayers -ge 0) { $GpuLayers } else { 99 }); context=4096 }
    }
    confidence=$conf; artifacts=@()
    model_provenance=@([ordered]@{ model_id=('llm.mock.' + $Tier); version='mock'; family='mock'; engine='llama-server'; engine_build='mock'; device='cpu'; params=@{}; prompt_tokens=40; completion_tokens=$ct; total_tokens=(40+$ct); finish_reason=$finish; timings=$null; runtime_ms=4 })
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$ArtifactRoot }
    warnings=@(); error=$null
}
# simulate the real gateway's low-confidence review append (to prove route.tools redirects it)
if ($request -match '(?i)\brq\b' -and -not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) {
    $line = ([ordered]@{ schema='lifeorch.review.item/0.1'; id='gwrq'; flagged_by='model.gateway'; reason='low_confidence'; confidence=0.4 } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText($ReviewQueuePath, $line + "`n", $utf8)
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
