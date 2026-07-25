#requires -Version 7.0
# MOCK model.gateway for CLOUD-ONLY logic testing of logic.escalator (no GPU/Windows).
# Emits a lifeorch.skill.result/0.1 envelope shaped like the real gateway. Its result.output.text is a
# deterministic ANSWER (a label) or a JUDGE verdict JSON, derived from:
#   - the call ROLE: -System containing "classifier"/"information extractor" -> ANSWER; "reviewer" -> JUDGE.
#   - the requested TIER (-Tier).
#   - a MOCK directive embedded in the task text (which the escalator forwards verbatim as -Prompt for an
#     answer call, and inside the judge user prompt as "TASK ITEM: ..." for a judge call).
# Directive tokens (space-separated key=value; values use : and , with NO spaces), e.g.:
#   MOCK a=tiny:dog,weak:cat,mid:cat,strong:cat jacc=cat vary=tiny foos=tiny jforce=accept g=tiny:hi rq=1
#     a=      per-tier ANSWER label (classify) / text (generic). Missing tier -> the last listed value.
#     jacc=   JUDGE accepts iff the candidate answer normalizes to this label; else rejects.
#     vary=   tiers whose ANSWER alternates by seed parity (simulates low self-consistency).
#     foos=   tiers that ANSWER out-of-set ("zzz").
#     jforce=accept  JUDGE always accepts (rubber-stamp; used to prove the deterministic in-set override).
#     g=      per-tier generic text.
#     rq=1    append a mock low-confidence review line to -ReviewQueuePath (to prove the escalator routes
#             the child gateway's review writes to its suppressed sink, never the canonical queue).
# NOT shipped to the device; the real gateway (real local models) is used there.
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

function Norm([string]$s) { if ($null -eq $s) { return '' }; return ($s.Trim().Trim([char[]]('"',"'",'.',',',';',':','!','?',' ',"`t")).ToLowerInvariant().Trim()) }

# batch-fatal simulation
if ($Tier -eq 'bogus' -or $Model -eq 'llm.bogus') {
    $env = [ordered]@{ schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'; invocation_id=$InvocationId; status='error'; started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=1; inputs_digest=('sha256:'+('0'*64)); result=$null; confidence=$null; artifacts=@(); model_provenance=@(); diagnostics=@{log='stderr.txt'}; warnings=@(); error=[ordered]@{ code='tier_not_found'; message='bogus tier'; retryable=$false } }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20)); exit 0
}

# ---- parse the MOCK directive from the task text ----
$dir = @{}
$mDir = [regex]::Match($Prompt, '(?im)MOCK\s+([^\r\n|]+)')
if ($mDir.Success) {
    foreach ($tok in ($mDir.Groups[1].Value.Trim() -split '\s+')) {
        if ($tok -match '^([a-z]+)=(.+)$') { $dir[$matches[1]] = $matches[2] }
    }
}
function Get-TierMap([string]$spec) {
    $m = @{}
    if (-not [string]::IsNullOrWhiteSpace($spec)) {
        foreach ($pair in ($spec -split ',')) { if ($pair -match '^([a-z0-9]+):(.+)$') { $m[$matches[1]] = $matches[2] } }
    }
    return $m
}
$aMap = Get-TierMap $(if ($dir.ContainsKey('a')) { $dir['a'] } else { '' })
$gMap = Get-TierMap $(if ($dir.ContainsKey('g')) { $dir['g'] } else { '' })
$varySet = @(); if ($dir.ContainsKey('vary')) { $varySet = @($dir['vary'] -split ',') }
$foosSet = @(); if ($dir.ContainsKey('foos')) { $foosSet = @($dir['foos'] -split ',') }
$jacc = $(if ($dir.ContainsKey('jacc')) { $dir['jacc'] } else { '' })
$jforce = $(if ($dir.ContainsKey('jforce')) { $dir['jforce'] } else { '' })

# ---- role detection ----
$role = 'answer'
if ($System -match 'reviewer') { $role = 'judge' }
$kind = 'classify'
if ($System -match 'information extractor' -or $System -match 'extraction reviewer') { $kind = 'extract' }
elseif ($System -match 'classifier' -or $System -match 'classification reviewer') { $kind = 'classify' }
elseif ($System -match 'assistant' -or $System -match 'answer reviewer') { $kind = 'generic' }

function Tier-Value([hashtable]$map, [string]$tier) {
    if ($map.ContainsKey($tier)) { return $map[$tier] }
    if ($map.Count -gt 0) { return @($map.Values)[-1] }
    return $null
}

$text = ''
if ($role -eq 'answer') {
    if ($foosSet -contains $Tier) { $text = 'zzz' }
    elseif ($kind -eq 'generic') { $g = Tier-Value $gMap $Tier; $text = $(if ($null -ne $g) { $g } else { 'mock generic answer' }) }
    elseif ($kind -eq 'extract') {
        # minimal extract answer: emit a JSON object from the a= map if present, else a fixed one
        $text = $(if ($aMap.ContainsKey($Tier)) { $aMap[$Tier] } else { '{"animal":"dog","color":"brown"}' })
    }
    else {
        $lab = Tier-Value $aMap $Tier
        if ($null -eq $lab) { $lab = 'animal' }
        if ($varySet -contains $Tier -and (($Seed % 2) -ne 0)) {
            # alternate to a different allowed label on odd seeds -> lowers self-consistency
            $set = @()
            $mSet = [regex]::Match($System, '(?i)from this exact set:\s*(.+?)\.')
            if ($mSet.Success) { $set = @($mSet.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            $alt = @($set | Where-Object { (Norm $_) -ne (Norm $lab) } | Select-Object -First 1)
            if ($alt.Count -ge 1) { $lab = $alt[0] }
        }
        $text = $lab
    }
} else {
    # judge: extract the candidate from the user prompt
    $cand = ''
    $mc = [regex]::Match($Prompt, '(?im)CANDIDATE ANSWER[^:]*:\s*(.+)$')
    if ($mc.Success) { $cand = $mc.Groups[1].Value.Trim() }
    $accept = $false
    if ($jforce -eq 'accept') { $accept = $true }
    elseif (-not [string]::IsNullOrWhiteSpace($jacc)) { $accept = ((Norm $cand) -eq (Norm $jacc)) }
    else { $accept = $false }
    if ($kind -eq 'extract') {
        $ans = $(if ($accept) { $cand } else { '{"animal":"dog","color":"brown"}' })
        if ($ans -notmatch '^\s*\{') { $ans = '{"animal":"dog","color":"brown"}' }
        $text = ('{"accept":' + $accept.ToString().ToLowerInvariant() + ',"answer":' + $ans + ',"confidence":0.85,"rationale":"mock"}')
    } else {
        $ownAns = $(if ($accept) { $cand } else { $t = Tier-Value $aMap $Tier; if ($null -ne $t) { $t } elseif (-not [string]::IsNullOrWhiteSpace($jacc)) { $jacc } else { 'animal' } })
        $text = ('{"accept":' + $accept.ToString().ToLowerInvariant() + ',"answer":"' + $ownAns + '","confidence":0.85,"rationale":"mock"}')
    }
}

$ct = [Math]::Max(1, ($text -split '\s+').Count)
$finish = 'stop'
$conf = 0.7
$env = [ordered]@{
    schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='0.1.0'; contract_version='0.1'
    invocation_id=$InvocationId; status='ok'
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o'); duration_ms=5
    inputs_digest=('sha256:'+('a'*64))
    result=[ordered]@{
        model=('llm.mock.' + $Tier); engine='llama-server'; mode='chat'; selected_from=("tier:$Tier")
        request=[ordered]@{ max_tokens=$MaxTokens; temperature=$Temperature; seed=$Seed }
        output=[ordered]@{ role='assistant'; text=$text }
        generation=[ordered]@{ finish_reason=$finish; prompt_tokens=20; completion_tokens=$ct; total_tokens=(20+$ct); timings=$null }
        server=[ordered]@{ port=8140; health_ms=5; gpu_layers=$(if ($GpuLayers -ge 0) { $GpuLayers } else { 99 }); context=4096 }
    }
    confidence=$conf; artifacts=@()
    model_provenance=@([ordered]@{ model_id=('llm.mock.' + $Tier); version='mock'; family='mock'; engine='llama-server'; engine_build='mock'; device='cpu'; params=@{}; prompt_tokens=20; completion_tokens=$ct; total_tokens=(20+$ct); finish_reason=$finish; timings=$null; runtime_ms=5 })
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$ArtifactRoot }
    warnings=@(); error=$null
}
# simulate the real gateway's low-confidence review append (to prove the escalator suppresses/redirects it)
if ($dir.ContainsKey('rq') -and $dir['rq'] -eq '1' -and -not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) {
    $line = ([ordered]@{ schema='lifeorch.review.item/0.1'; id='gwrq'; flagged_by='model.gateway'; reason='low_confidence'; confidence=0.4 } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText($ReviewQueuePath, $line + "`n", $utf8)
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
