#requires -Version 7.0
<#
  mock-child.ps1 -- a deterministic stand-in for every child agent.local spawns, for OFF-GPU logic tests.
  It branches on the -ArtifactRoot LEAF (the image.index #18 mock pattern):
    decision-*  -> a mock logic.escalator envelope (result.tasks[0] carries the chosen action)
    arggen-*    -> a mock model.gateway envelope returning a JSON args object (or non-JSON, per goal marker)
    final       -> a mock model.gateway envelope returning a final answer
    tool-*      -> a mock tool envelope (doc.io / fs.observer shaped result; or an error, per an arg marker)
  It emits exactly one lifeorch.skill.result/0.1 object on stdout. ASCII-only; no Set-StrictMode (tolerant).
  Scenario is driven by MARKERS embedded in the goal text (which the orchestrator threads into the prompts):
    FINISH_AFTER_ONE | TWO_TOOLS | LOOP_FOREVER | UNKNOWN_TOOL ; sub-markers NF_LOW | BAD_ARGS | TOOL_ERR .
#>
[CmdletBinding()]
param(
    [string]$InputsJson,
    [string]$ArtifactRoot,
    [string]$InvocationId
)
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }
$leaf = if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { 'root' } else { Split-Path -Leaf $ArtifactRoot }

function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
$p = $null
if (-not [string]::IsNullOrWhiteSpace($InputsJson)) { try { $p = $InputsJson | ConvertFrom-Json } catch { $p = $null } }

function Emit($result, $conf, $prov) {
    $env = [ordered]@{
        schema='lifeorch.skill.result/0.1'; skill_id='mock.child'; skill_version='0.1.0'; contract_version='0.2'
        invocation_id=$InvocationId; status='ok'
        started_at_utc=([DateTime]'2026-01-01T00:00:00Z').ToString('o'); finished_at_utc=([DateTime]'2026-01-01T00:00:01Z').ToString('o')
        duration_ms=1; inputs_digest='sha256:mock'
        result=$result; confidence=$conf; artifacts=@(); model_provenance=$prov
        diagnostics=[ordered]@{ log='stderr.txt' }; warnings=@(); error=$null
    }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 30))
    exit 0
}
function Emit-Error($code) {
    $env = [ordered]@{
        schema='lifeorch.skill.result/0.1'; skill_id='mock.child'; skill_version='0.1.0'; contract_version='0.2'
        invocation_id=$InvocationId; status='error'
        started_at_utc=([DateTime]'2026-01-01T00:00:00Z').ToString('o'); finished_at_utc=([DateTime]'2026-01-01T00:00:01Z').ToString('o')
        duration_ms=1; inputs_digest='sha256:mock'
        result=$null; confidence=$null; artifacts=@(); model_provenance=@()
        diagnostics=[ordered]@{ log='stderr.txt' }; warnings=@(); error=[ordered]@{ code=$code; message='simulated'; retryable=$false }
    }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 30))
    exit 0
}

if ($leaf -eq 'route') {
    # ---- mock route.tools: pre-select a toolset from the request markers ----
    $req = if (Has $p 'request') { [string]$p.request } else { '' }
    if ($req -match 'ROUTE_EMPTY') { $sel = @() }
    elseif ($req -match 'TWO_TOOLS') { $sel = @('fs.observer','doc.io') }
    else { $sel = @('doc.io') }
    $result = [ordered]@{
        request=$req; tier='mid'; model='llm.mock.mid'; catalog=@(); catalog_count=0
        tools=$sel; planned_tools=$sel; count=@($sel).Count; tools_dropped=@(); parsed_ok=$true; gated=$true
        raw_output=('[' + ((@($sel) | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'); finish_reason='stop'
        cost=[ordered]@{ gateway_calls=1; total_tokens=15; runtime_ms=2 }; is_review_producer=$false
    }
    $prov = @([ordered]@{ model_id='llm.mock.mid'; engine='llama-server'; calls=1; prompt_tokens_total=30; completion_tokens_total=4; total_tokens_total=34; runtime_ms_total=2 })
    Emit $result 0.7 $prov
}
elseif ($leaf -like 'decision-*') {
    # ---- mock escalator: choose an action from the decision text markers ----
    $text = ''
    if ((Has $p 'tasks') -and @($p.tasks).Count -gt 0) { $t0 = @($p.tasks)[0]; if (Has $t0 'text') { $text = [string]$t0.text } }
    $hasStep1 = $text -match 'STEP 1:'
    $hasStep2 = $text -match 'STEP 2:'
    $answer = 'finish'; $needsFrontier = $false; $conf = 0.9
    if ($text -match 'UNKNOWN_TOOL') {
        $answer = 'notatool'
    } elseif ($text -match 'LOOP_FOREVER') {
        $answer = 'fs.observer'
    } elseif ($text -match 'TWO_TOOLS') {
        if ($hasStep2) { $answer = 'finish' } elseif ($hasStep1) { $answer = 'doc.io' } else { $answer = 'fs.observer' }
    } else {
        # FINISH_AFTER_ONE (default): a single primary tool, then finish
        if ($hasStep1) { $answer = 'finish' } else { $answer = 'doc.io' }
    }
    if ($answer -ne 'finish' -and ($text -match 'NF_LOW')) { $needsFrontier = $true; $conf = 0.3 }
    $task = [ordered]@{
        id='mock'; kind='classify'; status='ok'; accepted_tier='weak'; accepted_tier_index=1
        answer=$answer; confidence=$conf; needs_frontier=$needsFrontier; accepted_via='judge'; self_consistency=$null
        gate=[ordered]@{ hard_pass=$true; grounded=$null; reason='mock' }
        ladder=@([ordered]@{ tier='tiny'; tier_index=0; role='answer'; ok=$true; answer=$answer; hardpass=$true; finish_reason='stop'; error=$null })
        gateway_calls=2
    }
    $result = [ordered]@{
        kind='classify'; tiers=@('tiny','weak','mid'); samples=1; count=1; resolved_count=1
        needs_frontier_count=$(if($needsFrontier){1}else{0}); error_count=0
        resolve_distribution=[ordered]@{ weak=1 }
        cost=[ordered]@{ total_gateway_calls=2; total_prompt_tokens=20; total_completion_tokens=2; total_tokens=22; mean_calls_per_task=2.0; total_runtime_ms=2 }
        tasks=@($task); is_review_producer=$false; labels=$(if (Has $p 'labels') { @($p.labels) } else { @() })
    }
    $prov = @([ordered]@{ tier='weak'; model_id='llm.mock.weak'; engine='llama-server'; calls=1; prompt_tokens_total=20; completion_tokens_total=2; total_tokens_total=22; runtime_ms_total=2 })
    Emit $result $conf $prov
}
elseif ($leaf -like 'arggen-*') {
    # ---- mock gateway: produce args JSON keyed to the chosen tool + goal markers ----
    $prompt = if (Has $p 'prompt') { [string]$p.prompt } else { '' }
    $text = '{}'
    if ($prompt -match 'BAD_ARGS') { $text = 'Sorry, I cannot produce arguments for that.' }
    elseif ($prompt -match 'TOOL_ERR') { $text = '{"op":"read","path":"__MOCK_TOOLERR__"}' }
    elseif ($prompt -match 'TOOL:\s*doc\.io') { $text = '{"op":"write","path":"mock_out.txt","content":"mock content"}' }
    elseif ($prompt -match 'TOOL:\s*fs\.observer') { $text = '{"path":".","pattern":"*.md"}' }
    $result = [ordered]@{
        model='llm.mock.mid'; engine='llama-server'; mode='chat'; selected_from='tier:mid'
        output=[ordered]@{ role='assistant'; text=$text }
        generation=[ordered]@{ finish_reason='stop'; prompt_tokens=30; completion_tokens=8; total_tokens=38; timings=$null }
        server=[ordered]@{ port=0; health_ms=1; gpu_layers=0; context=4096 }
    }
    $prov = @([ordered]@{ model_id='llm.mock.mid'; engine='llama-server'; calls=1; prompt_tokens_total=30; completion_tokens_total=8; total_tokens_total=38; runtime_ms_total=2 })
    Emit $result 0.7 $prov
}
elseif ($leaf -eq 'final') {
    $result = [ordered]@{
        model='llm.mock.mid'; engine='llama-server'; mode='chat'; selected_from='tier:mid'
        output=[ordered]@{ role='assistant'; text='Mock final answer: the task was handled by the mock children.' }
        generation=[ordered]@{ finish_reason='stop'; prompt_tokens=40; completion_tokens=12; total_tokens=52; timings=$null }
        server=[ordered]@{ port=0; health_ms=1; gpu_layers=0; context=4096 }
    }
    $prov = @([ordered]@{ model_id='llm.mock.mid'; engine='llama-server'; calls=1; prompt_tokens_total=40; completion_tokens_total=12; total_tokens_total=52; runtime_ms_total=2 })
    Emit $result 0.7 $prov
}
elseif ($leaf -like 'tool-*') {
    # ---- mock tool: doc.io / fs.observer shaped result, or an error on the toolerr marker ----
    $raw = if ($null -ne $InputsJson) { $InputsJson } else { '' }
    if ($raw -match '__MOCK_TOOLERR__') { Emit-Error 'mock_tool_error' }
    if (Has $p 'op') {
        $op = [string]$p.op
        $path = if (Has $p 'path') { [string]$p.path } else { '' }
        $file = [ordered]@{ encoding='utf-8'; bom=$false; eol='lf'; line_count=1; byte_count=12; char_count=12; sha256='deadbeefmock' }
        $result = [ordered]@{ op=$op; path=$path; existed=$true; file=$file }
        if ($op -eq 'read') { $result.content = 'mock file contents line1'; $result.file.line_count = 3 }
        elseif ($op -eq 'write') { $result.created=$true; $result.bytes_written=12; $result.sha256_before=$null }
        elseif ($op -eq 'edit') { $result.replacements=1; $result.occurrences=1 }
        elseif ($op -eq 'append') { $result.bytes_appended=12; $result.created=$false }
        Emit $result $null @()
    } else {
        # fs.observer shape
        $path = if (Has $p 'path') { [string]$p.path } else { '.' }
        $result = [ordered]@{ root=$path; depth=2; entry_count=5; dir_count=1; file_count=4; bytes_total=1234; truncated=$false
            pattern=$(if (Has $p 'pattern') { [string]$p.pattern } else { $null }); match_count=2
            matches=@([ordered]@{ name='a.md'; path=(Join-Path $path 'a.md') }, [ordered]@{ name='b.md'; path=(Join-Path $path 'b.md') }) }
        Emit $result $null @()
    }
}
else {
    # unknown leaf: emit a harmless ok envelope
    Emit ([ordered]@{ note='unknown-leaf'; leaf=$leaf }) $null @()
}
