#requires -Version 7.0
<#
  Invoke-OrchestrateFanoutTests.ps1 -- drives the REAL Invoke-OrchestrateFanout.ps1. Deterministic +
  OS-portable (temp plans/art dirs), ASCII-only. Runs off-GPU on cloud pwsh (pre-ship gate) and unchanged
  live via the executor. Exercises plan (schedule + GPU clamp + doc conflicts + embedded res.lease commands),
  the res.lease preflight seam (a mock res.lease), report/status/ready-cadence, handoff (a Verification
  Console packet + next prompts), list, and the error paths. Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh'),
    [string]$SkillPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OrchestrateFanout.ps1'),
    [string]$MockResLease = (Join-Path $PSScriptRoot 'mock-reslease.ps1'),
    [string]$WrapperPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m30-fanout-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$plansDir = Join-Path $work 'plans'
$artRoot = Join-Path $work 'art'
New-Item -ItemType Directory -Path $plansDir -Force | Out-Null

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# Run the real skill via -InputsJson, with named -PlansDir/-ArtifactRoot (win) + any extra named args.
function Run-Fan([hashtable]$inputs, [string[]]$extra) {
    $ij = ($inputs | ConvertTo-Json -Compress -Depth 12)
    $errF = Join-Path $work ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $callArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $SkillPath, '-InputsJson', $ij, '-PlansDir', $plansDir, '-ArtifactRoot', $artRoot)
    if ($null -ne $extra) { $callArgs += $extra }
    $out = & $PwshExe @callArgs 2> $errF
    $txt = ($out | Out-String).Trim()
    $e = $null; try { $e = $txt | ConvertFrom-Json } catch { }
    return @{ env = $e; raw = $txt; err = (Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}
function Res($r) { if ($r.env) { return $r.env.result } else { return $null } }

Write-Output "==== orchestrate.fanout harness ===="
Write-Output ("skill=" + $SkillPath)
Write-Output ""

# --- S0: manifest sanity ---
$manifest = $null
try { $manifest = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SkillPath) 'skill.json') -Raw | ConvertFrom-Json } catch { }
Write-Output "S0 manifest:"
Ok ($null -ne $manifest -and $manifest.skill_id -eq 'orchestrate.fanout') 'S0 skill_id orchestrate.fanout'
Ok ($null -ne $manifest -and $manifest.parallel_safe -eq $true -and $manifest.determinism -eq 'deterministic') 'S0 parallel_safe true + deterministic'

# --- S1: plan, 2 non-gpu workers, max_parallel 2 ---
$r = Run-Fan @{ action = 'plan'; title = 'S1'; max_parallel = 2; no_preflight = $true; workers = @(
        @{ id = 'w1'; unit = 'build thing A' },
        @{ id = 'w2'; unit = 'edit a doc'; docs = @('CURRENT_STATE.md') }
    ) } $null
$e = $r.env; $res = Res $r
Write-Output "S1 plan (2 non-gpu):"
Ok ($null -ne $e -and $e.schema -eq 'lifeorch.skill.result/0.1' -and $e.status -eq 'ok') 'S1 envelope ok'
Ok ($null -ne $res -and $res.action -eq 'plan' -and -not [string]::IsNullOrWhiteSpace($res.plan_id)) 'S1 plan_id assigned'
Ok ($null -ne $res -and @($res.dispatch_now).Count -eq 2 -and @($res.queued).Count -eq 0) 'S1 both dispatch now, none queued'
Ok ($null -ne $res -and @($res.workers).Count -eq 2) 'S1 two workers in result'
Ok ($null -ne $e -and $null -eq $e.confidence -and @($e.model_provenance).Count -eq 0) 'S1 deterministic (null confidence, no provenance)'
$w2 = @($res.workers | Where-Object { $_.id -eq 'w2' })[0]
Ok ($null -ne $w2 -and (@($w2.leases) -contains 'git') -and (@($w2.leases) -contains 'doc:CURRENT_STATE.md')) 'S1 w2 leases include git + doc:CURRENT_STATE.md'
Ok ($null -ne $w2 -and (Test-Path -LiteralPath $w2.prompt_path)) 'S1 w2 worker prompt file exists'
Ok ($null -ne $res -and (Test-Path -LiteralPath $res.check_in_prompt_path)) 'S1 check-in prompt file exists'
Ok ($null -ne $res -and (Test-Path -LiteralPath (Join-Path $res.plan_dir 'plan.json'))) 'S1 plan persisted (plan.json)'
$planWithDoc = if ($res) { [string]$res.plan_id } else { '' }

# --- S2: GPU clamp -- 2 gpu + 1 cpu, max_parallel 2 -> <=1 gpu in dispatch_now, both gpu serialized ---
$r = Run-Fan @{ action = 'plan'; max_parallel = 2; no_preflight = $true; workers = @(
        @{ id = 'gA'; unit = 'gpu unit A'; gpu = $true },
        @{ id = 'gB'; unit = 'gpu unit B'; gpu = $true },
        @{ id = 'cC'; unit = 'cpu unit C' }
    ) } $null
$res = Res $r
Write-Output "S2 GPU clamp:"
$dn = @($res.dispatch_now)
$gpuInDispatch = @($dn | Where-Object { $_ -eq 'gA' -or $_ -eq 'gB' }).Count
Ok ($null -ne $res -and $dn.Count -eq 2) 'S2 dispatch_now is max_parallel (2)'
Ok ($gpuInDispatch -le 1) 'S2 at most one GPU worker dispatched now'
Ok ($null -ne $res -and @($res.conflicts.gpu_serialized).Count -eq 2) 'S2 both gpu workers flagged serialized'
Ok ($null -ne $res -and @($res.queued).Count -eq 1) 'S2 one worker queued'

# --- S3: doc-ownership conflict ---
$r = Run-Fan @{ action = 'plan'; no_preflight = $true; workers = @(
        @{ id = 'd1'; unit = 'x'; docs = @('SHARED.md') },
        @{ id = 'd2'; unit = 'y'; docs = @('SHARED.md') }
    ) } $null
$res = Res $r
Write-Output "S3 doc conflict:"
$dc = @($res.conflicts.doc_contention)
Ok ($dc.Count -eq 1 -and $dc[0].doc -eq 'SHARED.md') 'S3 SHARED.md flagged as contended'
Ok (@($dc[0].workers).Count -eq 2) 'S3 both workers listed for the contended doc'

# --- S4: acquire-order (gpu -> git -> doc) + embedded res.lease commands + reverse release ---
$r = Run-Fan @{ action = 'plan'; no_preflight = $true; workers = @(
        @{ id = 'wx'; unit = 'z'; gpu = $true; docs = @('D.md') }
    ) } $null
$res = Res $r
$wx = @($res.workers)[0]
Write-Output "S4 acquire order + commands:"
Ok (@($wx.leases).Count -eq 3 -and $wx.leases[0] -eq 'gpu' -and $wx.leases[1] -eq 'git' -and $wx.leases[2] -eq 'doc:D.md') 'S4 leases ordered gpu,git,doc:D.md'
Ok ($wx.acquire_commands[0] -match 'Invoke-ResLease\.ps1 -Action acquire -Resource "gpu"') 'S4 first acquire command is the gpu lease via res.lease'
Ok ($wx.release_commands[0] -match 'release -Resource "doc:D.md"') 'S4 release is reverse (doc first)'
$wxPrompt = Get-Content -LiteralPath $wx.prompt_path -Raw
Ok ($wxPrompt -match 'Invoke-ResLease\.ps1 -Action acquire -Resource "gpu"') 'S4 worker prompt embeds the acquire command'
Ok ($wxPrompt -match '-Action report -PlanId') 'S4 worker prompt embeds the report-back command'

# --- S5: preflight via the mock res.lease (reports gpu held) ---
$r = Run-Fan @{ action = 'plan'; workers = @(@{ id = 'p1'; unit = 'needs gpu'; gpu = $true }) } @('-ResLeasePath', $MockResLease)
$res = Res $r
Write-Output "S5 preflight (mock res.lease):"
Ok ($null -ne $res -and $res.preflight.ran -eq $true) 'S5 preflight ran'
Ok ($null -ne $res -and (@($res.preflight.held) -contains 'gpu')) 'S5 preflight reports gpu held'
Ok ($null -ne $r.env -and (@($r.env.warnings) | Where-Object { $_ -match "gpu" }).Count -ge 1) 'S5 warns that gpu is held live'
# S5b: preflight disabled
$r = Run-Fan @{ action = 'plan'; no_preflight = $true; workers = @(@{ id = 'p2'; unit = 'x' }) } $null
$res = Res $r
Ok ($null -ne $res -and $res.preflight.ran -eq $false) 'S5b -NoPreflight skips the preflight'

# --- S6: report -> status reflects it (on_all not ready with a non-terminal worker) ---
Write-Output "S6 report + status:"
$r = Run-Fan @{ action = 'report'; plan_id = $planWithDoc; worker_id = 'w1'; state = 'done'; summary = 'did A' } $null
Ok ((Res $r).recorded -eq $true) 'S6 report w1 done recorded'
$r = Run-Fan @{ action = 'report'; plan_id = $planWithDoc; worker_id = 'w2'; state = 'progress'; summary = 'halfway' } $null
Ok ((Res $r).recorded -eq $true) 'S6 report w2 progress recorded'
$r = Run-Fan @{ action = 'status'; plan_id = $planWithDoc } $null
$res = Res $r
$sw1 = @($res.workers | Where-Object { $_.id -eq 'w1' })[0]
$sw2 = @($res.workers | Where-Object { $_.id -eq 'w2' })[0]
Ok ($sw1.state -eq 'done' -and $sw2.state -eq 'progress') 'S6 status shows w1 done, w2 progress'
Ok ($res.counts.done -eq 1 -and $res.counts.running -eq 1) 'S6 counts: 1 done, 1 running'
Ok ($res.ready_for_handoff -eq $false) 'S6 on_all not ready while a worker is non-terminal'

# --- S7: ready cadence (on_all when all terminal; on_each when >=1 terminal) ---
Write-Output "S7 ready cadence:"
$r = Run-Fan @{ action = 'report'; plan_id = $planWithDoc; worker_id = 'w2'; state = 'done'; summary = 'done B' } $null
$r = Run-Fan @{ action = 'status'; plan_id = $planWithDoc } $null
Ok ((Res $r).ready_for_handoff -eq $true) 'S7 on_all ready once every worker terminal'
# an on_each plan
$r = Run-Fan @{ action = 'plan'; report_back = 'on_each'; no_preflight = $true; workers = @(@{ id = 'e1'; unit = 'x' }, @{ id = 'e2'; unit = 'y' }) } $null
$planEach = (Res $r).plan_id
$r = Run-Fan @{ action = 'report'; plan_id = $planEach; worker_id = 'e1'; state = 'done'; summary = 'one done' } $null
$r = Run-Fan @{ action = 'status'; plan_id = $planEach } $null
Ok ((Res $r).ready_for_handoff -eq $true) 'S7 on_each ready after the first terminal worker'

# --- S8: handoff -> verification packet + next prompts + one check-in ---
Write-Output "S8 handoff:"
$r = Run-Fan @{ action = 'plan'; iteration = 3; no_preflight = $true; workers = @(
        @{ id = 'h1'; unit = 'ship fs.observer tweak'; skill_id = 'fs.observer'; skill_dir = 'modules/02-fs-observer'; inputs = @{ path = '.'; depth = 1 } },
        @{ id = 'h2'; unit = 'a hand check' }
    ) } $null
$planH = (Res $r).plan_id
$r = Run-Fan @{ action = 'report'; plan_id = $planH; worker_id = 'h1'; state = 'done'; summary = 'shipped' } $null
$r = Run-Fan @{ action = 'report'; plan_id = $planH; worker_id = 'h2'; state = 'done'; summary = 'checked' } $null
$r = Run-Fan @{ action = 'handoff'; plan_id = $planH } $null
$res = Res $r
Ok ($null -ne $res -and $res.next_iteration -eq 4) 'S8 next_iteration = iteration + 1'
Ok ($null -ne $res -and (Test-Path -LiteralPath $res.verification_packet_path)) 'S8 verification packet written'
$pkt = $null; try { $pkt = Get-Content -LiteralPath $res.verification_packet_path -Raw | ConvertFrom-Json } catch { }
Ok ($null -ne $pkt -and $pkt.schema -eq 'lifeorch.verification.packet/0.1' -and @($pkt.items).Count -eq 2) 'S8 packet is a valid verification packet with 2 items'
$hItem = @($pkt.items | Where-Object { $_.id -eq 'h1' })[0]
Ok ($null -ne $hItem -and $hItem.kind -eq 'run_module' -and $hItem.skill_id -eq 'fs.observer') 'S8 worker with skill_id -> a run_module item'
$h2Item = @($pkt.items | Where-Object { $_.id -eq 'h2' })[0]
Ok ($null -ne $h2Item -and $h2Item.kind -eq 'human_action') 'S8 worker without skill_id -> a human_action item'
Ok (@($res.worker_prompts_next).Count -ge 2 -and (Test-Path -LiteralPath @($res.worker_prompts_next)[0])) 'S8 next-iteration worker prompts written'
Ok ($null -ne $res -and (Test-Path -LiteralPath $res.check_in_prompt_path)) 'S8 one check-in prompt written'

# --- S9: list ---
$r = Run-Fan @{ action = 'list' } $null
$res = Res $r
Write-Output "S9 list:"
Ok ($null -ne $res -and $res.count -ge 3) 'S9 list reports >=3 plans'
Ok (@($res.plans | Where-Object { $_.plan_id -eq $planH }).Count -eq 1) 'S9 list includes the handoff plan'

# --- S10: error paths ---
Write-Output "S10 error paths:"
$r = Run-Fan @{ title = 'no action' } $null
Ok ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_parameter') 'S10 no action -> missing_parameter'
$r = Run-Fan @{ action = 'frobnicate' } $null
Ok ($null -ne $r.env -and $r.env.error.code -eq 'invalid_action') 'S10 bad action -> invalid_action'
$r = Run-Fan @{ action = 'plan'; no_preflight = $true; workers = @() } $null
Ok ($null -ne $r.env -and $r.env.error.code -eq 'missing_parameter') 'S10 plan with no workers -> missing_parameter'
$r = Run-Fan @{ action = 'report'; plan_id = 'nope-nope'; worker_id = 'x'; state = 'done' } $null
Ok ($null -ne $r.env -and $r.env.error.code -eq 'plan_not_found') 'S10 report unknown plan -> plan_not_found'
$r = Run-Fan @{ action = 'report'; plan_id = $planH; worker_id = 'x'; state = 'bogus' } $null
Ok ($null -ne $r.env -and $r.env.error.code -eq 'invalid_state') 'S10 bad state -> invalid_state'

# --- S11: Module 1 wrapper ---
if (-not [string]::IsNullOrWhiteSpace($WrapperPath) -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path -Parent $SkillPath
    $ij = [ordered]@{ action = 'list'; plans_dir = $plansDir } | ConvertTo-Json -Compress
    $wout = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WrapperPath -SkillDir $skillDir -InputsJson $ij -PwshPath $PwshExe 2> (Join-Path $work 'err-wrap.txt')
    $wcode = $LASTEXITCODE
    $rep = $null; try { $rep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
    Write-Output "S11 Module-1 wrapper:"
    Ok ($null -ne $rep -and $rep.manifest_valid -eq $true) 'S11 manifest valid'
    Ok ($null -ne $rep -and $rep.envelope_valid -eq $true -and $rep.exit_code -eq 0 -and $wcode -eq 0) 'S11 envelope valid + exit 0'
    Ok ($null -ne $rep -and $rep.envelope.result.action -eq 'list') 'S11 wrapped list ran'
} else { Write-Output "S11 Module-1 wrapper: SKIPPED (no -WrapperPath)" }

# --- S12: not a review-queue producer (no review_queue.jsonl anywhere it writes) ---
Write-Output "S12 non-producer:"
$rq = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter 'review_queue.jsonl' -ErrorAction SilentlyContinue)
Ok ($rq.Count -eq 0) 'S12 no review_queue.jsonl written (orchestrator/non-producer)'

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
