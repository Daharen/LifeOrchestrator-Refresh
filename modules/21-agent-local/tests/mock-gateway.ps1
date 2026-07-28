# Mock model.gateway for the -AutoRamp off-machine gate. Scripts decisions/args deterministically and
# honors evict_warm. Driven by env AR_MOCK_PLAN (plan json) + AR_MOCK_STATE (decision counter file).
[CmdletBinding()]
param(
    [string]$InputsJson,
    [string]$ArtifactRoot,
    [string]$InvocationId
)
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }
function Has($o,$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Emit($status,$result,$conf){
    $env = [ordered]@{
        schema='lifeorch.skill.result/0.1'; skill_id='model.gateway'; skill_version='mock'; contract_version='0.1'
        invocation_id=$InvocationId; status=$status; started_at_utc=([DateTime]::UtcNow).ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
        duration_ms=1; inputs_digest='sha256:mock'; result=$result; confidence=$conf
        artifacts=@(); model_provenance=@([ordered]@{ model_id='mock'; engine='mock'; runtime_ms=1 })
        diagnostics=[ordered]@{ log='none' }; warnings=@(); error=$null
    }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
    exit 0
}
$p = $InputsJson | ConvertFrom-Json

# evict_warm: delete the warm registry (simulate teardown) and report evicted
if ((Has $p 'evict_warm') -and [bool]$p.evict_warm) {
    $wrp = if (Has $p 'warm_registry_path') { [string]$p.warm_registry_path } else { $null }
    $had = $false
    if (-not [string]::IsNullOrWhiteSpace($wrp) -and (Test-Path -LiteralPath $wrp -PathType Leaf)) { $had=$true; Remove-Item -LiteralPath $wrp -Force -ErrorAction SilentlyContinue }
    Emit 'ok' ([ordered]@{ action='evict_warm'; warm=[ordered]@{ registry_path=$wrp; had_resident=$had; evicted=$had } }) $null
}

$plan = Get-Content -LiteralPath $env:AR_MOCK_PLAN -Raw | ConvertFrom-Json
$system = if (Has $p 'system') { [string]$p.system } else { '' }
$modelId = if (Has $p 'model') { [string]$p.model } else { 'mock' }

if ($system -like 'You are the decision controller*') {
    $stateF = $env:AR_MOCK_STATE
    $i = 0; if (Test-Path -LiteralPath $stateF) { try { $i = [int]((Get-Content -LiteralPath $stateF -Raw).Trim()) } catch { $i = 0 } }
    $decs = @($plan.decisions)
    $d = if ($i -lt $decs.Count) { $decs[$i] } else { $decs[$decs.Count-1] }
    [System.IO.File]::WriteAllText($stateF, [string]($i+1), $utf8)
    $text = if (Has $d 'text') { [string]$d.text } else { '' }
    $fr = if (Has $d 'finish_reason') { [string]$d.finish_reason } else { 'stop' }
    $conf = if ([string]::IsNullOrWhiteSpace($text)) { 0.1 } elseif ($fr -eq 'length') { 0.4 } else { 0.7 }
    $result = [ordered]@{ model=$modelId; output=[ordered]@{ role='assistant'; text=$text }; generation=[ordered]@{ finish_reason=$fr; prompt_tokens=10; completion_tokens=($text.Length); total_tokens=(10+$text.Length) }; server=[ordered]@{ warm=[ordered]@{ enabled=$true; reused=$false } } }
    Emit 'ok' $result $conf
}
else {
    # arg-gen: FIFO by arg-call index (AR_MOCK_ARGSTATE). bad_arg_calls[] -> invalid json; args_seq[] overrides
    # the per-tool args map for that call index; else fall back to args.<tool>.
    $prompt = if (Has $p 'prompt') { [string]$p.prompt } else { '' }
    $tool = ''
    if ($prompt -match 'TOOL:\s*(\S+)') { $tool = $Matches[1] }
    $astateF = $env:AR_MOCK_ARGSTATE
    $ai = 0; if (-not [string]::IsNullOrWhiteSpace($astateF) -and (Test-Path -LiteralPath $astateF)) { try { $ai = [int]((Get-Content -LiteralPath $astateF -Raw).Trim()) } catch { $ai = 0 } }
    if (-not [string]::IsNullOrWhiteSpace($astateF)) { [System.IO.File]::WriteAllText($astateF, [string]($ai+1), $utf8) }
    $badCalls = @(); if (Has $plan 'bad_arg_calls') { $badCalls = @($plan.bad_arg_calls | ForEach-Object { [int]$_ }) }
    $badTools = @(); if (Has $plan 'bad_args_tools') { $badTools = @($plan.bad_args_tools | ForEach-Object { [string]$_ }) }
    if (($badCalls -contains $ai) -or ($badTools -contains $tool)) {
        Emit 'ok' ([ordered]@{ model=$modelId; output=[ordered]@{ role='assistant'; text='sorry, no valid json here' }; generation=[ordered]@{ finish_reason='stop'; total_tokens=8 } }) 0.7
    }
    $argsObj = $null
    if ((Has $plan 'args_seq')) { $seq = @($plan.args_seq); if ($ai -lt $seq.Count -and $null -ne $seq[$ai]) { $argsObj = $seq[$ai] } }
    if ($null -eq $argsObj -and (Has $plan 'args') -and (Has $plan.args $tool)) { $argsObj = $plan.args.$tool }
    $argText = if ($null -ne $argsObj) { ($argsObj | ConvertTo-Json -Compress -Depth 8) } else { '{}' }
    Emit 'ok' ([ordered]@{ model=$modelId; output=[ordered]@{ role='assistant'; text=$argText }; generation=[ordered]@{ finish_reason='stop'; total_tokens=20 } }) 0.7
}
