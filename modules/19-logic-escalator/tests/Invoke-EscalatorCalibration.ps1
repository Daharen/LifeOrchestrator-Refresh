#requires -Version 7.0
# Empirical calibration of logic.escalator (D-0029 guardrail 2). Runs a LABELED closed-set eval through the
# escalator LIVE (via the real model.gateway) and measures, with actual numbers:
#   - resolve-level distribution (which tier is the accepted layer, per task)
#   - accuracy of the ladder's final answer vs the known label (+ always-tiny and always-mid baselines)
#   - false-approval rate: items accepted BELOW the top tier that are WRONG and NOT flagged for the frontier
#     (the "two too-weak tiers rubber-stamped a wrong answer" failure the deterministic gates must defend)
#   - cost: mean gateway calls/item AND a params_b-weighted cost/item, vs the cost of one always-strong call
#   - whether accuracy reaches the ~95% target (states it plainly either way)
# Writes escalation-calibration.json + .md to -OutDir and prints the summary. Run through the executor.
[CmdletBinding()]
param(
    [string]$EvalPath,
    [object]$Tiers = @('tiny','weak','mid','strong'),
    [int]$Samples = 1,
    [double]$AcceptConsistency = 1.0,
    [double]$FrontierThreshold = 0.5,
    [int]$LoadTimeoutSec = 300,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$GatewayPath,
    [string]$Registry,
    [string]$OutDir,
    [switch]$SkipBaselines
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
$entry = Join-Path $moduleRoot 'Invoke-LogicEscalator.ps1'
if ([string]::IsNullOrWhiteSpace($EvalPath)) { $EvalPath = Join-Path $moduleRoot 'eval/classify-eval.json' }
if ([string]::IsNullOrWhiteSpace($GatewayPath)) { $GatewayPath = Join-Path $modulesDir '07-model-gateway/Invoke-ModelGateway.ps1' }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $moduleRoot ('runtime/calibration/' + [Guid]::NewGuid().ToString('N').Substring(0,8)) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# params_b cost weight per tier (from models.json); a call to a bigger model costs proportionally more.
$PARAMS_B = @{ tiny = 0.5; weak = 1.5; mid = 3.0; strong = 27.0 }
function Clean-Tier([string]$s) { if ($null -eq $s) { return '' }; return ($s.Trim().Trim([char[]]@([char]39,[char]34)).Trim().ToLowerInvariant()) }
$tierList = @(@($Tiers) | ForEach-Object { Clean-Tier ([string]$_) })
if ($tierList.Count -eq 1 -and ([string]$tierList[0]).Contains(',')) { $tierList = @(([string]$tierList[0]) -split ',' | ForEach-Object { Clean-Tier $_ }) }
$tierList = @($tierList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
function Norm([string]$s) { if ($null -eq $s) { return '' }; return ($s.Trim().ToLowerInvariant().Trim([char[]]('"',"'",'.',',',' '))) }
function Log([string]$m) { [Console]::Out.WriteLine($m) }

# ---- load the eval set ----
$eval = (Get-Content -LiteralPath $EvalPath -Raw) | ConvertFrom-Json
$labels = @($eval.labels)
$goldById = @{}
$tasksForRun = New-Object System.Collections.Generic.List[object]
foreach ($t in @($eval.tasks)) {
    $goldById[[string]$t.id] = Norm ([string]$t.label)
    $tasksForRun.Add([ordered]@{ id = [string]$t.id; text = [string]$t.text })
}
$N = $tasksForRun.Count
Log "calibration: N=$N tiers=[$($tierList -join ',')] samples=$Samples eval=$EvalPath"

# ---- run the escalator over a whole batch with a given tier list; return parsed result ----
function Run-Config([string[]]$tiers, [int]$samples, [string]$tag) {
    $inputs = [ordered]@{ kind = 'classify'; labels = $labels; tiers = $tiers; samples = $samples; accept_consistency = $AcceptConsistency; frontier_threshold = $FrontierThreshold; load_timeout_s = $LoadTimeoutSec; gateway_path = $GatewayPath; pwsh_path = $PwshPath; tasks = $tasksForRun.ToArray() }
    if (-not [string]::IsNullOrWhiteSpace($Registry)) { $inputs.registry = $Registry }
    $ij = $inputs | ConvertTo-Json -Depth 12 -Compress
    $art = Join-Path $OutDir ("art-" + $tag)
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-ArtifactRoot',$art,'-InputsJson',$ij)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $swc = [System.Diagnostics.Stopwatch]::StartNew()
    $o = & $PwshPath @a
    $swc.Stop()
    $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    Log "  [$tag] wall=$([int]$swc.Elapsed.TotalSeconds)s status=$(if ($null -ne $env) { $env.status } else { 'PARSE_FAIL' })"
    return [pscustomobject]@{ env = $env; wall_s = [int]$swc.Elapsed.TotalSeconds; raw = $txt }
}

# ---- accuracy of a single-answer config (baseline) ----
function Accuracy([object]$env) {
    if ($null -eq $env -or $null -eq $env.result) { return $null }
    $ok = 0; $tot = 0
    foreach ($it in @($env.result.tasks)) {
        $tot++
        $g = $goldById[[string]$it.id]
        if ((Norm ([string]$it.answer)) -eq $g) { $ok++ }
    }
    if ($tot -eq 0) { return $null }
    return [Math]::Round($ok / [double]$tot, 4)
}
function Weighted-Cost([object]$env) {
    # sum over per-tier calls of params_b[tier]; returns total and per-item mean
    if ($null -eq $env -or $null -eq $env.result) { return $null }
    $tot = 0.0; $calls = 0
    foreach ($pv in @($env.model_provenance)) {
        $tn = [string]$pv.tier
        $c = [int]$pv.calls
        $w = if ($PARAMS_B.ContainsKey($tn)) { $PARAMS_B[$tn] } else { 1.0 }
        $tot += ($c * $w); $calls += $c
    }
    return [pscustomobject]@{ weighted = [Math]::Round($tot, 2); calls = $calls; per_item_weighted = [Math]::Round($tot / [double]$N, 3); per_item_calls = [Math]::Round($calls / [double]$N, 3) }
}

# ---- LADDER run (primary) ----
$ladder = Run-Config $tierList $Samples 'ladder'
if ($null -eq $ladder.env -or $null -eq $ladder.env.result) { Log "FATAL: ladder run produced no result"; Log $ladder.raw; exit 1 }
$lr = $ladder.env.result
$topTier = $tierList[-1]

$perItem = New-Object System.Collections.Generic.List[object]
$correct = 0; $wrong = 0; $flagged = 0
$acceptedBelowTop = 0; $falseApproval = 0; $wrongAtTop = 0
$resolveDist = [ordered]@{}
foreach ($t in $tierList) { $resolveDist[$t] = 0 }
foreach ($it in @($lr.tasks)) {
    $id = [string]$it.id; $gold = $goldById[$id]
    $ans = Norm ([string]$it.answer)
    $isCorrect = ($ans -eq $gold)
    $at = [string]$it.accepted_tier
    $nf = [bool]$it.needs_frontier
    if ($resolveDist.Contains($at)) { $resolveDist[$at] = [int]$resolveDist[$at] + 1 }
    if ($isCorrect) { $correct++ } else { $wrong++ }
    if ($nf) { $flagged++ }
    $belowTop = ($at -ne $topTier)
    if ($belowTop) { $acceptedBelowTop++ }
    if ($belowTop -and (-not $isCorrect) -and (-not $nf)) { $falseApproval++ }   # confidently wrong at a low tier
    if ((-not $belowTop) -and (-not $isCorrect)) { $wrongAtTop++ }
    $perItem.Add([ordered]@{ id = $id; gold = $gold; answer = $ans; correct = $isCorrect; accepted_tier = $at; needs_frontier = $nf; confidence = $it.confidence; gateway_calls = $it.gateway_calls; accepted_via = $(if ($it.PSObject.Properties.Name -contains 'accepted_via') { $it.accepted_via } else { $null }) })
}
$accLadder = [Math]::Round($correct / [double]$N, 4)
$faRate = if ($acceptedBelowTop -gt 0) { [Math]::Round($falseApproval / [double]$acceptedBelowTop, 4) } else { 0 }
$ladderCost = Weighted-Cost $ladder.env

# ---- baselines (cheap: single-tier) ----
$accTiny = $null; $accMid = $null; $tinyCost = $null; $midCost = $null
if (-not $SkipBaselines) {
    if ($tierList -contains 'tiny') { $b = Run-Config @('tiny') 1 'baseline-tiny'; $accTiny = Accuracy $b.env; $tinyCost = Weighted-Cost $b.env }
    $midT = if ($tierList -contains 'mid') { 'mid' } elseif ($tierList -contains 'weak') { 'weak' } else { $tierList[-1] }
    $b2 = Run-Config @($midT) 1 "baseline-$midT"; $accMid = Accuracy $b2.env; $midCost = Weighted-Cost $b2.env
}

# ---- cost references ----
$alwaysStrongPerItem = $PARAMS_B['strong']   # one 27B call/item
$savingsVsStrong = if ($null -ne $ladderCost) { [Math]::Round(1.0 - ($ladderCost.per_item_weighted / $alwaysStrongPerItem), 4) } else { $null }
$reaches95 = ($accLadder -ge 0.95)

$report = [ordered]@{
    schema = 'lifeorch.escalator_calibration/0.1'
    generated_utc = ([DateTime]::UtcNow).ToString('o')
    eval = $EvalPath; n = $N; labels = $labels
    config = [ordered]@{ tiers = $tierList; samples = $Samples; accept_consistency = $AcceptConsistency; frontier_threshold = $FrontierThreshold }
    accuracy = [ordered]@{ ladder = $accLadder; baseline_tiny = $accTiny; baseline_mid = $accMid; target = 0.95; reaches_target = $reaches95 }
    resolve_distribution = $resolveDist
    residue = [ordered]@{ needs_frontier = $flagged; needs_frontier_rate = [Math]::Round($flagged / [double]$N, 4) }
    correctness = [ordered]@{ correct = $correct; wrong = $wrong; wrong_rate = [Math]::Round($wrong / [double]$N, 4) }
    false_approval = [ordered]@{
        definition = 'accepted BELOW the top tier, WRONG, and NOT flagged needs_frontier (a confidently-wrong low-tier acceptance)'
        accepted_below_top = $acceptedBelowTop; false_approvals = $falseApproval; false_approval_rate = $faRate; wrong_at_top_tier = $wrongAtTop
    }
    cost = [ordered]@{
        ladder = $ladderCost
        always_strong_per_item_weighted = $alwaysStrongPerItem
        ladder_vs_always_strong_savings = $savingsVsStrong
        baseline_tiny = $tinyCost; baseline_mid = $midCost
        note = 'weighted cost = sum over gateway calls of params_b(tier) [tiny 0.5, weak 1.5, mid 3, strong 27]; a fair proxy for compute since there is no warm worker (each call reloads its model).'
    }
    wall_seconds = [ordered]@{ ladder = $ladder.wall_s }
    per_item = $perItem.ToArray()
}
$jsonPath = Join-Path $OutDir 'escalation-calibration.json'
[System.IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 20), $utf8)

# ---- markdown ----
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# logic.escalator -- calibration")
$md.Add("")
$md.Add("- eval: ``$EvalPath`` (N=$N, labels: $($labels -join ', '))")
$md.Add("- config: tiers ``$($tierList -join ' -> ')`` | samples(K)=$Samples | accept_consistency=$AcceptConsistency | frontier_threshold=$FrontierThreshold")
$md.Add("")
$md.Add("## Accuracy")
$md.Add("- **ladder: $accLadder** (target 0.95 -> reaches: $reaches95)")
$md.Add("- baseline always-tiny: $accTiny | baseline always-$(if ($tierList -contains 'mid') { 'mid' } else { 'weak' }): $accMid")
$md.Add("")
$md.Add("## Resolve-level distribution (which tier is the accepted layer)")
foreach ($k in $resolveDist.Keys) { $md.Add("- $($k): $($resolveDist[$k])") }
$md.Add("")
$md.Add("## False approval (the rubber-stamp failure mode)")
$md.Add("- accepted below the top tier: $acceptedBelowTop | of those, confidently-wrong (false approvals): $falseApproval -> **rate $faRate**")
$md.Add("- wrong at the top tier (not a false approval): $wrongAtTop | flagged needs_frontier: $flagged ($([Math]::Round($flagged/[double]$N,4)))")
$md.Add("")
$md.Add("## Cost")
if ($null -ne $ladderCost) {
    $md.Add("- ladder mean gateway calls/item: $($ladderCost.per_item_calls) | mean params_b-weighted cost/item: **$($ladderCost.per_item_weighted)**")
    $md.Add("- one always-strong (27B) call/item = $alwaysStrongPerItem weighted -> ladder saves **$([Math]::Round($savingsVsStrong*100,1))%** vs always-strong")
    if ($null -ne $midCost) { $md.Add("- always-mid (3B) call/item = $($midCost.per_item_weighted) weighted") }
    if ($null -ne $tinyCost) { $md.Add("- always-tiny (0.5B) call/item = $($tinyCost.per_item_weighted) weighted") }
}
$md.Add("")
$md.Add("## Per-item")
$md.Add("| id | gold | answer | correct | accepted_tier | via | conf | needs_frontier | calls |")
$md.Add("|----|------|--------|---------|---------------|-----|------|----------------|-------|")
foreach ($p in $perItem.ToArray()) { $md.Add("| $($p.id) | $($p.gold) | $($p.answer) | $($p.correct) | $($p.accepted_tier) | $($p.accepted_via) | $($p.confidence) | $($p.needs_frontier) | $($p.gateway_calls) |") }
$md.Add("")
$md.Add("_False-approval rate is the fraction of low-tier acceptances that are confidently wrong -- the concrete measure of the ladder rubber-stamping. Accuracy is measured against known-correct labels. Weighted cost uses params_b as a compute proxy (no warm worker; each call reloads its model)._")
$mdPath = Join-Path $OutDir 'escalation-calibration.md'
[System.IO.File]::WriteAllText($mdPath, ([string]::Join("`n", $md.ToArray())), $utf8)

Log ""
Log "==== CALIBRATION SUMMARY ===="
Log "accuracy: ladder=$accLadder  tiny=$accTiny  mid=$accMid  (target 0.95, reaches=$reaches95)"
$rdParts = @(); foreach ($k in $resolveDist.Keys) { $rdParts += "$k=$($resolveDist[$k])" }
Log ("resolve_distribution: " + ($rdParts -join '  '))
Log "false_approval: below_top=$acceptedBelowTop false_approvals=$falseApproval rate=$faRate  wrong_at_top=$wrongAtTop  flagged=$flagged"
if ($null -ne $ladderCost) { Log "cost: ladder/item weighted=$($ladderCost.per_item_weighted) calls=$($ladderCost.per_item_calls)  always_strong/item=$alwaysStrongPerItem  savings=$([Math]::Round($savingsVsStrong*100,1))%" }
Log "reports: $jsonPath"
Log "reports: $mdPath"
Log "==== DONE ===="
exit 0
