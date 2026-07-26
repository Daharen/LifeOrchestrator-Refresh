<#
    mock-agent-local.ps1 - a stand-in for modules/21-agent-local/Invoke-AgentLocal.ps1
    used ONLY by the Local Agent Console cloud pre-ship gate (a GPU-bound real agent.local
    cannot run on the Linux cloud box). It accepts the same -InputsJson / -ArtifactRoot the
    console passes and emits a canned but shape-accurate lifeorch.skill.result/0.1 envelope
    to stdout, so the console core's spawn -> parse -> format path is exercised for real.

    Goal keywords select a scenario:
      (default)  -> a completed run that invoked doc.io
      STOPME     -> status stopped + needs_frontier (the max_steps budget caught it)
      ERRORME    -> an error envelope (status=error)
      NOISY      -> prints banner noise to stdout before the JSON (tests tolerant parsing)
#>
param(
    [string]$InputsJson,
    [string]$Goal,
    [string]$ArtifactRoot,
    [Parameter(ValueFromRemainingArguments = $true)] $Rest
)
$ErrorActionPreference = 'Continue'

$goal = $Goal
$dryRun = $false
$maxSteps = 4
if ($InputsJson) {
    try {
        $o = $InputsJson | ConvertFrom-Json
        if ($o.PSObject.Properties['goal']) { $goal = [string]$o.goal }
        if ($o.PSObject.Properties['dry_run']) { $dryRun = [bool]$o.dry_run }
        if ($o.PSObject.Properties['max_steps']) { $maxSteps = [int]$o.max_steps }
    } catch { }
}
if (-not $goal) { $goal = '(no goal)' }

# ML libraries print freely to stderr; the console must ignore it and parse only stdout.
[Console]::Error.WriteLine('[mock-agent-local] loading tiers tiny/weak/mid ...')

$scenario = 'completed'
if ($goal -match 'STOPME') { $scenario = 'stopped' }
elseif ($goal -match 'ERRORME') { $scenario = 'error' }

if ($goal -match 'NOISY') {
    Write-Output 'llama-server: loading model ... done'   # stdout noise before the JSON
}

$now = [datetime]::UtcNow.ToString('o')

if ($scenario -eq 'error') {
    $envelope = [ordered]@{
        schema           = 'lifeorch.skill.result/0.1'
        skill_id         = 'agent.local'
        skill_version    = '0.1.0'
        contract_version = '0.2'
        invocation_id    = [guid]::NewGuid().ToString()
        status           = 'error'
        started_at_utc   = $now
        finished_at_utc  = $now
        duration_ms      = 1234
        result           = $null
        confidence       = $null
        artifacts        = @()
        model_provenance = @()
        warnings         = @()
        error            = [ordered]@{ code = 'decision_failed'; message = 'the escalator could not produce a valid action'; retryable = $true }
    }
    ($envelope | ConvertTo-Json -Depth 12)
    exit 0
}

$toolInvoked = -not $dryRun
$step = [ordered]@{
    index       = 1
    decision    = [ordered]@{ chosen_tool = 'doc.io'; confidence = 0.82; accepted_tier = 'mid'; accepted_via = 'in_set_gate'; needs_frontier = $false; ok = $true }
    args        = [ordered]@{ op = 'write'; path = 'notes/hello.txt'; content = 'hi from agent.local' }
    args_raw    = '{"op":"write","path":"notes/hello.txt","content":"hi from agent.local"}'
    tool        = [ordered]@{ skill_id = 'doc.io'; invoked = $toolInvoked; status = $(if ($toolInvoked) { 'ok' } else { 'skipped' }); error = $null; artifact_dir = "$ArtifactRoot/step1" }
    observation = $(if ($toolInvoked) { 'wrote 19 bytes to notes/hello.txt (sha256 3f2a...)' } else { '(dry run: no tool invoked)' })
    error       = $null
}

$stopped = ($scenario -eq 'stopped')
$result = [ordered]@{
    goal            = $goal
    working_dir     = '.'
    status          = $(if ($stopped) { 'stopped' } else { 'completed' })
    final_answer    = $(if ($stopped) { 'Reached the step budget before self-terminating; the write appears to have succeeded.' } else { "Created notes/hello.txt containing 'hi from agent.local'." })
    needs_frontier  = $stopped
    stop_reason     = $(if ($stopped) { 'max_steps' } else { 'finish' })
    step_count      = 1
    max_steps       = $maxSteps
    dry_run         = $dryRun
    tools_available = @(
        [ordered]@{ tool = 'doc.io'; skill_id = 'doc.io'; side_effecting = $true },
        [ordered]@{ tool = 'fs.observer'; skill_id = 'fs.observer'; side_effecting = $false }
    )
    steps           = @($step)
    cost            = [ordered]@{ decision_calls = 1; gen_calls = 2; tool_calls = $(if ($toolInvoked) { 1 } else { 0 }); total_gateway_calls = 3; total_tokens = 412; total_runtime_ms = 5210 }
    decision_tiers  = @('tiny', 'weak', 'mid')
    gen_tier        = 'mid'
    review          = [ordered]@{ mode = 'redirect'; child_review_path = "$ArtifactRoot/child_review.jsonl"; child_review_count = 0; is_producer = $false }
    is_review_producer = $false
}

$envelope = [ordered]@{
    schema           = 'lifeorch.skill.result/0.1'
    skill_id         = 'agent.local'
    skill_version    = '0.1.0'
    contract_version = '0.2'
    invocation_id    = [guid]::NewGuid().ToString()
    status           = $(if ($stopped) { 'partial' } else { 'ok' })
    started_at_utc   = $now
    finished_at_utc  = $now
    duration_ms      = 5210
    result           = $result
    confidence       = 0.82
    artifacts        = @()
    model_provenance = @(
        [ordered]@{ stage = 'decision'; model_id = 'llm.tiny.qwen2p5-0p5b'; runtime_ms = 900 },
        [ordered]@{ stage = 'gen'; model_id = 'llm.mid.qwen2p5-3b'; runtime_ms = 3100 }
    )
    warnings         = @()
    error            = $null
}
($envelope | ConvertTo-Json -Depth 12)
exit 0
