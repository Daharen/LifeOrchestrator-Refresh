#requires -Version 7.0
# Regression tests for Module 9 (review.processor). Run through the executor (the live checks need the GPU +
# staged models via model.gateway). Fast checks (manifest, missing-queue, error paths, dry-run) need no model
# load; live checks make the skill call the real gateway (default the mid/3B reviewer), which spins up
# llama-server on a staged LLM and tears it down. Pass -IncludeStrong to also exercise + time the 27B (strong)
# tier with -StrongGpuLayers (the 27B gpu_layers tuning; off by default to keep the gate fast).
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$IncludeStrong,
    [int]$StrongGpuLayers = 28
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-ReviewProcessor.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$utf8    = [System.Text.UTF8Encoding]::new($false)
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Run([string[]]$rpArgs) {
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-PwshPath',$PwshPath) + $rpArgs
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
# a scratch working dir under TEMP for seeded queues/fragments
$work = Join-Path $env:TEMP ("lo-rp-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

function New-Classified([string]$path, [string]$itemId, [string]$preview) {
    $c = @{ result = @{ mode='classify'; labels=@('animal','vehicle','food'); items=@(@{ id=$itemId; input_preview=$preview; label=$null; confidence=0.2 }) } }
    [System.IO.File]::WriteAllText($path, ($c | ConvertTo-Json -Depth 12), $utf8)
}
function New-QueueLine([hashtable]$o) { return ($o | ConvertTo-Json -Depth 10 -Compress) }

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$man = (Get-Content -LiteralPath (Join-Path $moduleRoot 'skill.json') -Raw) | ConvertFrom-Json
Check 'manifest batch=true parallel_safe=false determinism=mixed' ($man.batch -eq $true -and $man.parallel_safe -eq $false -and $man.determinism -eq 'mixed')

# ---- missing / empty queue -> ok empty (no model load) ----
$e0 = Run @('-QueuePath', (Join-Path $work 'nope.jsonl'))
$ev0 = Test-SkillResultEnvelope -Json $e0
Check 'missing-queue envelope validates' ([bool]$ev0.valid)
$o0 = $e0 | ConvertFrom-Json
Check 'missing-queue ok + selected 0 + exit 0' ($o0.status -eq 'ok' -and $o0.result.selected_count -eq 0 -and $script:code -eq 0)

# ---- gateway_not_found error path (1 open item, bad gateway; no model load) ----
$qErr = Join-Path $work 'q-err.jsonl'
[System.IO.File]::WriteAllText($qErr, (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-err-1'; created_at_utc='2026-07-24T02:00:00Z'; flagged_by='classify.batch'; reason='uncategorized'; source_ref='artifact://x#y'; weak_result=@{ mode='classify'; text_preview='a cat' }; requested='adjudicate_category'; status='open'; resolution=$null; escalated_to=$null }) + "`n", $utf8)
$eErr = Run @('-QueuePath',$qErr,'-GatewayPath','C:\nope\nogateway.ps1')
$oErr = $eErr | ConvertFrom-Json
Check 'gateway_not_found error envelope + exit 0' ((Test-SkillResultEnvelope -Json $eErr).valid -and $oErr.status -eq 'error' -and $oErr.error.code -eq 'gateway_not_found' -and $script:code -eq 0)
Check 'gateway_not_found did NOT mutate the queue' (@(Get-Content -LiteralPath $qErr).Count -eq 1)

# ---- LIVE: mid (3B) adjudication of a classify.batch item, resolved in place ----
$classified = Join-Path $work 'classified.json'
New-Classified $classified 'r1' 'a red pickup truck on the highway'
$qLive = Join-Path $work 'q-live.jsonl'
$logLive = Join-Path $work 'review_resolved.jsonl'
$origLines = @(
  (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-live-r1'; created_at_utc='2026-07-24T02:10:00Z'; flagged_by='classify.batch'; reason='uncategorized'; confidence=0.2; source_ref=("artifact://$classified#r1"); weak_result=@{ mode='classify'; model='llm.weak.qwen2p5-1p5b'; item_id='r1'; finish_reason='stop'; text_preview='a red pickup truck on the highway'; label=$null }; requested='adjudicate_category'; status='open'; resolution=$null; escalated_to=$null }),
  'this is not json { ever',
  (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-live-done'; created_at_utc='2026-07-24T02:11:00Z'; flagged_by='classify.batch'; reason='uncategorized'; source_ref='artifact://x#y'; weak_result=@{ mode='classify' }; requested='adjudicate_category'; status='resolved'; resolution=@{ by='prior'; decision='food'; at_utc='2026-07-24T03:00:00Z'; note='done' }; escalated_to=$null })
)
[System.IO.File]::WriteAllText($qLive, ([string]::Join("`n",$origLines) + "`n"), $utf8)
# -InputsJson supplies the ids filter (also exercises the InputsJson merge path); only rq-live-r1 is open anyway
$eL = Run @('-QueuePath',$qLive,'-ResolutionLogPath',$logLive,'-Tier','mid','-InputsJson','{"ids":["rq-live-r1"]}')
$evL = Test-SkillResultEnvelope -Json $eL
Check 'live mid envelope validates' ([bool]$evL.valid)
if (-not $evL.valid) { $evL.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$oL = $eL | ConvertFrom-Json
Check 'live mid status ok, selected 1' ($oL.status -eq 'ok' -and $oL.result.selected_count -eq 1)
Check 'live mid reviewer model 3B, tier mid' ($oL.result.reviewer_model -eq 'llm.weak.qwen2p5-3b' -and $oL.result.selected_from -eq 'tier:mid')
$itL = @($oL.result.items | Where-Object { $_.id -eq 'rq-live-r1' })[0]
Check 'live mid item adjudicated (resolved|escalated)' ($itL.new_status -in @('resolved','escalated'))
Check 'live mid source fragment resolved' ($itL.source_fragment_resolved -eq $true)
Check 'live mid reviewer_confidence in 0..1' ($itL.reviewer_confidence -ge 0 -and $itL.reviewer_confidence -le 1)
if ($itL.new_status -eq 'resolved') { Check 'live mid resolved decision is an allowed label' (@('animal','vehicle','food') -contains [string]$itL.decision) }
Check 'live mid provenance aggregate mode=review calls>=1' (@($oL.model_provenance).Count -eq 1 -and $oL.model_provenance[0].mode -eq 'review' -and $oL.model_provenance[0].calls -ge 1)
$cjArt = @($oL.artifacts | Where-Object { $_.kind -eq 'json' })
Check 'live mid has json+md artifacts' (@($oL.artifacts).Count -ge 2 -and $cjArt.Count -ge 1 -and @($oL.artifacts | Where-Object { $_.kind -eq 'markdown' }).Count -ge 1)
if ($cjArt.Count -ge 1 -and (Test-Path -LiteralPath $cjArt[0].path)) {
    $b = [System.IO.File]::ReadAllBytes($cjArt[0].path)
    $sha = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($b))).Replace('-','').ToLowerInvariant()
    Check 'live mid review.json sha256 matches' ($sha -eq $cjArt[0].sha256)
}
# queue written in place, history preserved
$ql = @(Get-Content -LiteralPath $qLive)
Check 'live mid queue keeps all 3 lines' ($ql.Count -eq 3)
Check 'live mid malformed line preserved' ($ql -contains 'this is not json { ever')
$byId = @{}; foreach ($ln in $ql) { try { $o = $ln | ConvertFrom-Json; if ($o.PSObject.Properties.Name -contains 'id') { $byId[[string]$o.id] = $o } } catch { } }
Check 'live mid r1 line updated, weak_result + source_ref preserved' ($byId['rq-live-r1'].status -in @('resolved','escalated') -and $byId['rq-live-r1'].weak_result.item_id -eq 'r1' -and $byId['rq-live-r1'].source_ref -eq "artifact://$classified#r1" -and $byId['rq-live-r1'].resolution.by -like 'review.processor:*')
Check 'live mid already-resolved item untouched' ($byId['rq-live-done'].status -eq 'resolved' -and $byId['rq-live-done'].resolution.by -eq 'prior')
Check 'live mid resolution log written w/ schema' ((Test-Path -LiteralPath $logLive) -and ((@(Get-Content -LiteralPath $logLive)[0]) | ConvertFrom-Json).schema -eq 'lifeorch.review.resolution/0.1')

# ---- LIVE: forced escalation (EscalateThreshold 0.99) ----
$qEsc = Join-Path $work 'q-esc.jsonl'
[System.IO.File]::WriteAllText($qEsc, (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-esc-1'; created_at_utc='2026-07-24T02:20:00Z'; flagged_by='model.gateway'; reason='low_confidence'; confidence=0.4; source_ref='artifact://gone/missing.json'; weak_result=@{ model='llm.weak.qwen2p5-1p5b'; finish_reason='length'; text_preview='an incomplete sentence that just' }; requested='review_generation_quality'; status='open'; resolution=$null; escalated_to=$null }) + "`n", $utf8)
$eE = Run @('-QueuePath',$qEsc,'-Tier','mid','-EscalateThreshold','0.99')
$oE = $eE | ConvertFrom-Json
Check 'live escalation: item escalated to frontier' ($oE.result.escalated_count -ge 1 -and @($oE.result.items | Where-Object { $_.id -eq 'rq-esc-1' })[0].escalated_to -eq 'frontier')
$eb = @(Get-Content -LiteralPath $qEsc)[0] | ConvertFrom-Json
Check 'live escalation: queue line now escalated' ($eb.status -eq 'escalated' -and $eb.escalated_to -eq 'frontier')

# ---- DryRun no-op ----
$qDry = Join-Path $work 'q-dry.jsonl'
New-Classified (Join-Path $work 'c2.json') 'd1' 'a golden retriever puppy'
[System.IO.File]::WriteAllText($qDry, (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-dry-1'; created_at_utc='2026-07-24T02:30:00Z'; flagged_by='classify.batch'; reason='uncategorized'; source_ref=("artifact://" + (Join-Path $work 'c2.json') + "#d1"); weak_result=@{ mode='classify'; text_preview='a golden retriever puppy' }; requested='adjudicate_category'; status='open'; resolution=$null; escalated_to=$null }) + "`n", $utf8)
$dryLog = Join-Path $work 'review_resolved_dry.jsonl'
$before = [System.IO.File]::ReadAllText($qDry)
$eD = Run @('-QueuePath',$qDry,'-ResolutionLogPath',$dryLog,'-Tier','mid','-DryRun')
$oD = $eD | ConvertFrom-Json
Check 'dry-run reports an adjudication' (($oD.result.resolved_count + $oD.result.escalated_count) -ge 1 -and $oD.result.dry_run -eq $true)
Check 'dry-run did NOT mutate the queue' ([System.IO.File]::ReadAllText($qDry) -eq $before)
Check 'dry-run did NOT write the resolution log' (-not (Test-Path -LiteralPath $dryLog))

# ---- Wrapper (Module 1), fast (missing queue) ----
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson ('{"queue_path":"' + ((Join-Path $work 'none.jsonl') -replace '\\','\\\\') + '"}')
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
Check 'wrapper ran review.processor' ($repObj.envelope.skill_id -eq 'review.processor')

# ---- OPTIONAL: strong (27B) tier + gpu_layers timing ----
if ($IncludeStrong) {
    $classifiedS = Join-Path $work 'classified-strong.json'
    New-Classified $classifiedS 's1' 'a steaming bowl of ramen noodles'
    $qS = Join-Path $work 'q-strong.jsonl'
    [System.IO.File]::WriteAllText($qS, (New-QueueLine @{ schema='lifeorch.review.item/0.1'; id='rq-strong-1'; created_at_utc='2026-07-24T02:40:00Z'; flagged_by='classify.batch'; reason='uncategorized'; source_ref=("artifact://$classifiedS#s1"); weak_result=@{ mode='classify'; item_id='s1'; finish_reason='stop'; text_preview='a steaming bowl of ramen noodles'; label=$null }; requested='adjudicate_category'; status='open'; resolution=$null; escalated_to=$null }) + "`n", $utf8)
    $swS = [System.Diagnostics.Stopwatch]::StartNew()
    # -LoadTimeoutSec 300: a cold 27B load (~90s) plus generation at ~2 tok/s needs more than the gateway's
    # default 120s (which bounds BOTH load and the completion request). Cap tokens: a verdict JSON is small.
    $eS = Run @('-QueuePath',$qS,'-Tier','strong','-GpuLayers',"$StrongGpuLayers",'-MaxItems','1','-LoadTimeoutSec','300','-MaxTokens','200')
    $swS.Stop()
    $oS = $eS | ConvertFrom-Json
    $itS = @($oS.result.items)[0]
    [Console]::Out.WriteLine("STRONG(27B) gpu_layers=$StrongGpuLayers wall_ms=$([int]$swS.Elapsed.TotalMilliseconds) status=$($oS.status) new_status=$($itS.new_status) verdict=$($itS.verdict) rev_conf=$($itS.reviewer_confidence)")
    Check 'live strong envelope validates' ([bool](Test-SkillResultEnvelope -Json $eS).valid)
    Check 'live strong produced a result' ($oS.status -in @('ok','partial') -and $oS.result.selected_count -eq 1)
    Check 'live strong item adjudicated end-to-end' ($itS.new_status -in @('resolved','escalated') -and $itS.error -eq $null)
    Check 'live strong tier resolved to 27B' ($oS.result.reviewer_model -eq 'llm.strong.qwen3p5-27b')
}

# ---- no orphaned server processes (allow a big 27B server time to finish tearing down) ----
Start-Sleep -Seconds 3
$orphans = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
Check 'no orphaned llama-server' ($orphans.Count -eq 0)

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
