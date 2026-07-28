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

    When -InputsJson carries "autoramp":true (Governor Phase 3), it emits an auto-ramp-shaped
    envelope whose result carries a governor_trace (+ final_status / accepted_epoch / model_swaps /
    contract), reflecting any success_contract_path it received. Goal keyword VERIFIED -> a
    verified_success at M0 (1 governor step); otherwise -> an M0->M1->S0 escalation that ends
    local_ceiling_reached with the frozen contract failing (3 governor steps).
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
$route = $false
$autoramp = $false
$contractPathReceived = $null
if ($InputsJson) {
    try {
        $o = $InputsJson | ConvertFrom-Json
        if ($o.PSObject.Properties['goal']) { $goal = [string]$o.goal }
        if ($o.PSObject.Properties['dry_run']) { $dryRun = [bool]$o.dry_run }
        if ($o.PSObject.Properties['max_steps']) { $maxSteps = [int]$o.max_steps }
        if ($o.PSObject.Properties['route']) { $route = [bool]$o.route }
        if ($o.PSObject.Properties['autoramp']) { $autoramp = [bool]$o.autoramp }
        if ($o.PSObject.Properties['success_contract_path']) { $contractPathReceived = [string]$o.success_contract_path }
    } catch { }
}
if (-not $goal) { $goal = '(no goal)' }

# ML libraries print freely to stderr; the console must ignore it and parse only stdout.
[Console]::Error.WriteLine('[mock-agent-local] loading tiers tiny/weak/mid ...')

# ---- Governor Phase 3 (auto-ramp) scenario: emit an envelope carrying a governor trace ----
if ($autoramp) {
    [Console]::Error.WriteLine('[mock-agent-local] -AutoRamp: ensuring resident model + gpu lease ...')
    $arNow = [datetime]::UtcNow.ToString('o')
    $verified = ($goal -match 'VERIFIED')
    $contractSupplied = [bool]$contractPathReceived
    if ($verified) {
        $trace = @(
            [ordered]@{ schema = 'lifeorch.governor_trace/0.1'; step = 1; epoch = 'M0'; model = 'llm.weak.qwen2p5-3b'; decision = 'doc.io'; decision_in_set = $true; decision_finish_reason = 'stop'; decision_conf = 0.7; decision_empty = $false; tool_invoked = $true; tool_status = 'ok'; skipped_repeat = $false; contract_evaluated = $true; contract_passed = $true; contract_failed = @(); residency_match = $true; residency_mismatch_reason = $null; residency_evicted = $false; hard_trigger = $null; soft_strikes_this_step = 0; soft_strikes_window = 0; escalated_to = $null; model_swaps = 0 }
        )
        $finalStatus = 'verified_success'; $acceptedEpoch = 'M0'; $swaps = 0; $epochs = @('M0')
        $contractPassed = $true; $contractChecks = @([ordered]@{ predicate = 'file_exists'; passed = $true; evidence = 'ramp_ok.txt' })
    }
    else {
        $trace = @(
            [ordered]@{ schema = 'lifeorch.governor_trace/0.1'; step = 1; epoch = 'M0'; model = 'llm.weak.qwen2p5-3b'; decision = 'fs.manage'; decision_in_set = $true; decision_finish_reason = 'stop'; decision_conf = 0.7; decision_empty = $false; tool_invoked = $false; tool_status = $null; skipped_repeat = $false; contract_evaluated = $false; contract_passed = $null; contract_failed = @(); residency_match = $true; residency_mismatch_reason = $null; residency_evicted = $false; hard_trigger = $null; soft_strikes_this_step = 3; soft_strikes_window = 3; escalated_to = 'M1'; model_swaps = 0; soft_reasons = @('test_forced_soft', 'no_state_fingerprint_change') },
            [ordered]@{ schema = 'lifeorch.governor_trace/0.1'; step = 2; epoch = 'M1'; model = 'llm.weak.qwen2p5-3b'; decision = 'fs.manage'; decision_in_set = $true; decision_finish_reason = 'stop'; decision_conf = 0.7; decision_empty = $false; tool_invoked = $false; tool_status = $null; skipped_repeat = $false; contract_evaluated = $false; contract_passed = $null; contract_failed = @(); residency_match = $true; residency_mismatch_reason = $null; residency_evicted = $false; hard_trigger = $null; soft_strikes_this_step = 3; soft_strikes_window = 3; escalated_to = 'S0'; model_swaps = 0; soft_reasons = @('test_forced_soft', 'no_state_fingerprint_change') },
            [ordered]@{ schema = 'lifeorch.governor_trace/0.1'; step = 3; epoch = 'S0'; model = 'llm.strong.qwen3p5-9b'; decision = 'fs.manage'; decision_in_set = $true; decision_finish_reason = 'stop'; decision_conf = 0.7; decision_empty = $false; tool_invoked = $true; tool_status = 'error'; skipped_repeat = $false; contract_evaluated = $true; contract_passed = $false; contract_failed = @('file_exists:ramp_done.txt', 'artifact_nonempty:bytes=-1'); residency_match = $false; residency_mismatch_reason = 'model_id,context,engine_path'; residency_evicted = $true; hard_trigger = $null; soft_strikes_this_step = 2; soft_strikes_window = 2; escalated_to = $null; model_swaps = 1; soft_reasons = @('tool_failed:invalid_op', 'no_state_fingerprint_change') }
        )
        $finalStatus = 'local_ceiling_reached'; $acceptedEpoch = $null; $swaps = 1; $epochs = @('M0', 'M1', 'S0')
        $contractPassed = $false; $contractChecks = @(
            [ordered]@{ predicate = 'file_exists'; passed = $false; evidence = 'ramp_done.txt' },
            [ordered]@{ predicate = 'artifact_nonempty'; passed = $false; evidence = 'bytes=-1' }
        )
    }
    $arResult = [ordered]@{
        goal                        = $goal
        working_dir                 = '.'
        autoramp                    = $true
        final_status                = $finalStatus
        verified_success            = $verified
        accepted_epoch              = $acceptedEpoch
        model_swaps                 = $swaps
        step_count                  = $trace.Count
        max_total_steps             = 12
        contract                    = [ordered]@{
            supplied        = $contractSupplied
            checkable       = $contractSupplied
            hash            = $(if ($contractSupplied) { 'sha256:mock00000000000000000000000000000000000000000000000000000000mock' } else { $null })
            predicate_count = $contractChecks.Count
            last            = [ordered]@{ evaluated = $true; passed = $contractPassed; checkable = $contractSupplied; checks = $contractChecks; reason = $(if ($contractPassed) { 'all_passed' } else { 'some_failed' }) }
        }
        epochs_visited              = $epochs
        gpu_lease                   = [ordered]@{ mode = 'auto'; available = $true; acquired = $true; owned = $true; renew_count = 0; released = $true; lost = $false }
        success_contract_path       = $contractPathReceived
        completed_tools             = @()
        governor_trace              = $trace
        governor_trace_path         = "$ArtifactRoot/governor-trace.json"
        is_review_producer          = $false
        child_reviews_redirected_to = "$ArtifactRoot/child_review.jsonl"
        excluded                    = @('X0/27B', 'logprobs/entropy', 'self-consistency', 'pattern-learning')
    }
    $arEnvelope = [ordered]@{
        schema           = 'lifeorch.skill.result/0.1'
        skill_id         = 'agent.local'
        skill_version    = '0.1.0'
        contract_version = '0.2'
        invocation_id    = [guid]::NewGuid().ToString()
        status           = $(if ($verified) { 'ok' } else { 'partial' })
        started_at_utc   = $arNow
        finished_at_utc  = $arNow
        duration_ms      = 8200
        result           = $arResult
        confidence       = 0.7
        artifacts        = @()
        model_provenance = @([ordered]@{ stage = 'decide-1'; model_id = 'llm.weak.qwen2p5-3b'; runtime_ms = 2219 })
        warnings         = @()
        error            = $null
    }
    ($arEnvelope | ConvertTo-Json -Depth 20)
    exit 0
}

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
    route_enabled   = $route
    planned_tools   = $(if ($route) { @('doc.io') } else { $null })
    route           = [ordered]@{ enabled = $route; entrypoint_found = $route; applied = $route; fell_back = $false; planned_tools = $(if ($route) { @('doc.io') } else { $null }); route_status = $(if ($route) { 'ok' } else { $null }); route_confidence = $(if ($route) { 0.7 } else { $null }); full_tool_count = 10; constrained_tool_count = $(if ($route) { 1 } else { 10 }); route_gateway_calls = $(if ($route) { 1 } else { 0 }); route_tokens = $(if ($route) { 41 } else { 0 }); route_runtime_ms = $(if ($route) { 420 } else { 0 }) }
    outcome         = [ordered]@{ tools_invoked = $(if ($toolInvoked) { 1 } else { 0 }); tools_succeeded = $(if ($toolInvoked) { 1 } else { 0 }); tools_failed = 0; succeeded_tools = $(if ($toolInvoked) { @('doc.io') } else { @() }); failed_tools = @() }
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
