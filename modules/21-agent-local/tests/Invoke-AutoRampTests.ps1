#requires -Version 7.0
<#
  Off-machine gate for the Governor Phase 3 Stage-1 auto-ramp controller (agent.local -AutoRamp).
  MOCK mode (default): a scripted mock gateway + a mock tool (REAL filesystem side effects) + the REAL
  res.lease running against a temp lease dir. Proves: epoch monotonicity, hard + soft triggers, frozen
  success-contract gating, residency-key mismatch -> evict/reload, idempotency/duplicate-refusal, and the
  completed_unverified / no-contract path. The GPU/warm-server end-to-end is proven by the -Live gate.
#>
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$TempRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $PwshPath = (Get-Process -Id $PID).Path; if ([string]::IsNullOrWhiteSpace($PwshPath) -or $PwshPath -notmatch 'pwsh') { $PwshPath = 'pwsh' } }

$here       = $PSScriptRoot
$controller = (Resolve-Path -LiteralPath (Join-Path $here '..\Invoke-AutoRamp.ps1')).Path
$mockGw     = (Resolve-Path -LiteralPath (Join-Path $here 'mock-gateway.ps1')).Path
$mockTool   = (Resolve-Path -LiteralPath (Join-Path $here 'mock-tool.ps1')).Path
$reslease   = (Resolve-Path -LiteralPath (Join-Path $here '..\..\29-resource-lease\Invoke-ResLease.ps1')).Path
$models     = (Resolve-Path -LiteralPath (Join-Path $here '..\..\07-model-gateway\models.json')).Path
if ([string]::IsNullOrWhiteSpace($TempRoot)) { $TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("autoramp-test-" + [Guid]::NewGuid().ToString('N').Substring(0,8)) }
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
$leaseDir = Join-Path $TempRoot 'leases'; New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null

# mock tools registry (doc.io -> the mock tool)
$toolsFile = Join-Path $TempRoot 'mock-tools.json'
@{ tools = @(
    @{ tool='doc.io'; skill_id='doc.io'; entrypoint=$mockTool; description='write a text file'; args_hint='op,path,content'; args_example=@{op='write';path='x.txt';content='hi'}; required=@('op','path'); side_effecting=$true }
) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $toolsFile -Encoding utf8

$script:pass = 0; $script:fail = 0; $script:scn = 0
function Assert($cond, $name) { if ($cond) { $script:pass++; Write-Host "  [PASS] $name" } else { $script:fail++; Write-Host "  [FAIL] $name" -ForegroundColor Red } }
function Section($n) { $script:scn++; Write-Host ""; Write-Host "=== Scenario ${script:scn}: $n ===" }

function Run-AutoRamp {
    param([string]$Name, [string]$Scratch, [string]$Goal, $Contract, $Plan, [hashtable]$Inputs, [string[]]$ExtraArgs, $WarmSeed, [string]$ToolsFileOverride)
    $planFile = Join-Path $TempRoot "plan-$Name.json"
    ($Plan | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $planFile -Encoding utf8
    $stateFile = Join-Path $TempRoot "state-$Name.txt"; if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
    $argStateFile = Join-Path $TempRoot "argstate-$Name.txt"; if (Test-Path $argStateFile) { Remove-Item $argStateFile -Force }
    $warmReg = Join-Path $TempRoot "warm-$Name.json"; if (Test-Path $warmReg) { Remove-Item $warmReg -Force }
    if ($null -ne $WarmSeed) { ($WarmSeed | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $warmReg -Encoding utf8 }
    $env:AR_MOCK_PLAN = $planFile; $env:AR_MOCK_STATE = $stateFile; $env:AR_MOCK_ARGSTATE = $argStateFile
    $inp = [ordered]@{ goal=$Goal; working_dir=$Scratch; gpu_lease='auto'; gpu_lease_holder=("ar-"+$Name); gpu_lease_ttl_s=120; max_total_steps=12 }
    if ($null -ne $Contract) { $inp.success_contract = $Contract }
    if ($null -ne $Inputs) { foreach ($k in $Inputs.Keys) { $inp[$k] = $Inputs[$k] } }
    $arts = Join-Path $TempRoot "arts-$Name"
    $tf = if (-not [string]::IsNullOrWhiteSpace($ToolsFileOverride)) { $ToolsFileOverride } else { $toolsFile }
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$controller,
        '-InputsJson',($inp | ConvertTo-Json -Depth 20 -Compress),
        '-GatewayPath',$mockGw,'-ToolsPath',$tf,'-ResLeasePath',$reslease,'-LeaseDir',$leaseDir,
        '-WarmRegistryPath',$warmReg,'-Registry',$models,'-PwshPath',$PwshPath,'-ArtifactRoot',$arts)
    if ($null -ne $ExtraArgs) { $a += $ExtraArgs }
    $errf = New-TemporaryFile
    $out = & $PwshPath @a 2> $errf.FullName
    $errtxt = Get-Content -LiteralPath $errf.FullName -Raw -ErrorAction SilentlyContinue; Remove-Item $errf.FullName -Force -ErrorAction SilentlyContinue
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    if ($null -eq $env) { Write-Host "  <no envelope> raw: $(if($txt.Length -gt 300){$txt.Substring(0,300)}else{$txt})"; Write-Host "  stderr: $(if($errtxt){$errtxt.Substring(0,[Math]::Min(400,$errtxt.Length))})" }
    return @{ env=$env; result=$(if ($null -ne $env) { $env.result } else { $null }); warmReg=$warmReg }
}
function Epochs($r) { return @($r.result.governor_trace | ForEach-Object { $_.epoch }) }
function IsMonotonic($r) {
    $rank = @{ 'M0'=0; 'M1'=1; 'S0'=2; 'X0'=3 }
    $seq = @(Epochs $r | ForEach-Object { $rank[$_] })
    for ($i=1; $i -lt $seq.Count; $i++) { if ($seq[$i] -lt $seq[$i-1]) { return $false } }
    return $true
}
function NewScratch($n) { $s = Join-Path $TempRoot "sc-$n"; New-Item -ItemType Directory -Path $s -Force | Out-Null; return (Resolve-Path -LiteralPath $s).Path }

# ---------------------------------------------------------------------------------------------------
Section 'floor-solvable -> verified_success at M0, no escalation'
$sc = NewScratch 's1'; $f = Join-Path $sc 'ok.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}, @{predicate='artifact_nonempty';path=$f}) }
$plan = @{ decisions=@(@{text='doc.io';finish_reason='stop'}); args=@{ 'doc.io'=@{op='write';path=$f;content='VERIFIED'} } }
$r = Run-AutoRamp 's1' $sc 'Write VERIFIED to ok.txt' $c $plan $null $null $null
Assert ($null -ne $r.result) 's1 produced an envelope'
Assert ($r.result.final_status -eq 'verified_success') "s1 final_status=verified_success (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'M0') "s1 accepted_epoch=M0 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 0) "s1 model_swaps=0 (got $($r.result.model_swaps))"
Assert ((Epochs $r) -notcontains 'S0') 's1 never reached S0 (no needless escalation)'
Assert (Test-Path -LiteralPath $f) 's1 the real file was written by the tool'
Assert ([bool]$r.result.gpu_lease.acquired -and [bool]$r.result.gpu_lease.released) 's1 gpu lease acquired + released (real res.lease)'

# ---------------------------------------------------------------------------------------------------
Section 'HARD empty decision at M0 -> immediate S0 (skip M1)'
$sc = NewScratch 's2'; $f = Join-Path $sc 't.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='';finish_reason='length'}, @{text='doc.io';finish_reason='stop'}); args=@{ 'doc.io'=@{op='write';path=$f;content='x'} } }
$r = Run-AutoRamp 's2' $sc 'make t.txt' $c $plan $null $null $null
Assert ($r.result.final_status -eq 'verified_success') "s2 verified_success (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'S0') "s2 accepted_epoch=S0 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 1) "s2 model_swaps=1 (got $($r.result.model_swaps))"
Assert ((Epochs $r) -notcontains 'M1') 's2 skipped M1 on a HARD trigger'
Assert ($r.result.governor_trace[0].hard_trigger -eq 'empty_decision') "s2 step1 hard_trigger=empty_decision (got $($r.result.governor_trace[0].hard_trigger))"
Assert ($r.result.governor_trace[0].escalated_to -eq 'S0') 's2 step1 escalated_to=S0'
Assert (IsMonotonic $r) 's2 epochs monotonic'

# ---------------------------------------------------------------------------------------------------
Section 'SOFT strikes at M0 -> M1 (expanded mid) -> success'
$sc = NewScratch 's3'; $f = Join-Path $sc 'm.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
# step1 M0: decide doc.io, arg-call 0 = bad json (soft arg_parse + soft no-progress -> >=2 -> escalate M1)
# step2 M1: decide doc.io, arg-call 1 = good -> writes m.txt -> contract passes at M1
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0); args=@{ 'doc.io'=@{op='write';path=$f;content='y'} } }
$r = Run-AutoRamp 's3' $sc 'make m.txt' $c $plan $null $null $null
Assert ($r.result.final_status -eq 'verified_success') "s3 verified_success (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'M1') "s3 accepted_epoch=M1 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 0) "s3 model_swaps=0 (M1 is same 3B, no reload) (got $($r.result.model_swaps))"
Assert ($r.result.governor_trace[0].escalated_to -eq 'M1') 's3 step1 escalated_to=M1 (soft path uses M1 first)'
Assert ((Epochs $r) -contains 'M1' -and (Epochs $r) -notcontains 'S0') 's3 reached M1, not S0'
Assert (IsMonotonic $r) 's3 epochs monotonic'

# ---------------------------------------------------------------------------------------------------
Section 'SOFT M0 -> M1 -> S0 (M1 also fails) -> success, one model swap'
$sc = NewScratch 's4'; $f = Join-Path $sc 's.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0,1); args=@{ 'doc.io'=@{op='write';path=$f;content='z'} } }
$r = Run-AutoRamp 's4' $sc 'make s.txt' $c $plan $null $null $null
Assert ($r.result.final_status -eq 'verified_success') "s4 verified_success (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'S0') "s4 accepted_epoch=S0 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 1) "s4 model_swaps=1 (got $($r.result.model_swaps))"
Assert (((Epochs $r) -contains 'M0') -and ((Epochs $r) -contains 'M1') -and ((Epochs $r) -contains 'S0')) 's4 visited M0,M1,S0'
Assert (IsMonotonic $r) 's4 epochs monotonic (never de-escalate)'

# ---------------------------------------------------------------------------------------------------
Section 'frozen-contract gating: finish is NOT honored on the model say-so'
$sc = NewScratch 's5'; $f = Join-Path $sc 'g.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='finish'}, @{text='doc.io'}); args=@{ 'doc.io'=@{op='write';path=$f;content='q'} } }
$r = Run-AutoRamp 's5' $sc 'make g.txt' $c $plan $null $null $null
Assert ($r.result.governor_trace[0].decision -eq 'finish') 's5 step1 model chose finish'
Assert ($r.result.governor_trace[0].contract_passed -eq $false) 's5 step1 contract did NOT pass'
Assert ($r.result.governor_trace[0].hard_trigger -eq 'finish_but_contract_failed') "s5 step1 hard=finish_but_contract_failed (got $($r.result.governor_trace[0].hard_trigger))"
Assert ($r.result.final_status -eq 'verified_success' -and $r.result.accepted_epoch -eq 'S0') 's5 verified only after the contract really passed at S0'
Assert (Test-Path -LiteralPath $f) 's5 the file exists only after S0 actually did the work'

# ---------------------------------------------------------------------------------------------------
Section 'residency-key mismatch -> evict + reload (HARD trigger)'
$sc = NewScratch 's6'; $f = Join-Path $sc 'r.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$seed = @{ schema='lifeorch.model_gateway.warm/0.1'; pid=999999; model_id='llm.strong.qwen3p5-9b'; ngl=99; ctx=8192; engine_path='F:\eng\llama.cpp-b10092\bin\llama-server.exe'; host='127.0.0.1'; port=8140 }
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}); args=@{ 'doc.io'=@{op='write';path=$f;content='r'} } }
$r = Run-AutoRamp 's6' $sc 'make r.txt' $c $plan $null $null $seed
$t0 = $r.result.governor_trace[0]
Assert ($t0.residency_match -eq $false) 's6 step1 residency_match=false (wrong resident detected)'
Assert ($t0.residency_evicted -eq $true) 's6 step1 wrong resident was EVICTED'
Assert ($t0.residency_mismatch_reason -like '*model_id*') "s6 mismatch reason includes model_id (got $($t0.residency_mismatch_reason))"
Assert ($t0.hard_trigger -like 'resident_model_mismatch*') "s6 hard=resident_model_mismatch (got $($t0.hard_trigger))"
Assert ($t0.escalated_to -eq 'S0') 's6 residency mismatch escalated to S0 (per the frozen HARD-trigger list)'
Assert ($r.result.final_status -eq 'verified_success') 's6 recovered to verified_success at S0'

# ---------------------------------------------------------------------------------------------------
Section 'idempotency / duplicate-side-effect refusal + resume-from-state across epochs'
$sc = NewScratch 's7'; $fa = Join-Path $sc 'a.txt'; $fb = Join-Path $sc 'b.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$fa}, @{predicate='file_exists';path=$fb}) }
# step1 M0: write a.txt ; step2 M0: SAME write a.txt (dup, no state change -> HARD) -> S0 ; step3 S0: write b.txt
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'});
           args_seq=@(@{op='write';path=$fa;content='A'}, @{op='write';path=$fa;content='A'}, @{op='write';path=$fb;content='B'}) }
$r = Run-AutoRamp 's7' $sc 'make a.txt and b.txt' $c $plan $null $null $null
$dupStep = @($r.result.governor_trace | Where-Object { $_.skipped_repeat -eq $true })
Assert (@($dupStep).Count -ge 1) 's7 a duplicate (tool,args) was refused (skipped_repeat)'
Assert ($dupStep[0].tool_invoked -eq $false) 's7 the duplicate mutation was NOT re-invoked (idempotent)'
Assert ($dupStep[0].hard_trigger -eq 'repeat_identical_action_no_state_change') "s7 dup+no-change is a HARD trigger (got $($dupStep[0].hard_trigger))"
Assert ($r.result.final_status -eq 'verified_success' -and $r.result.accepted_epoch -eq 'S0') 's7 completed at S0 by resuming (a.txt kept, b.txt added)'
Assert ((Test-Path $fa) -and (Test-Path $fb)) 's7 both files exist (a from M0, b from S0 -- state resumed, not restarted)'

# ---------------------------------------------------------------------------------------------------
# CHANGED (D-0061): a contract-less finish on a goal that implies NO output is now closed by the D-0046
# terminator as `completed` (not completed_unverified) -- the terminator is satisfied (nothing to produce).
Section 'no contract + no implied output -> completed via the terminator (NOT completed_unverified)'
$sc = NewScratch 's8'
$plan = @{ decisions=@(@{text='finish'}) }
$r = Run-AutoRamp 's8' $sc 'do something un-verifiable' $null $plan $null $null $null
Assert ($r.result.final_status -eq 'completed') "s8 final_status=completed via terminator (got $($r.result.final_status))"
Assert ($r.result.final_status -ne 'completed_unverified') 's8 does NOT return completed_unverified when the terminator is satisfied'
Assert ($r.result.verified_success -eq $false) 's8 verified_success=false with no contract'
Assert ($r.result.accepted_epoch -eq 'M0') 's8 resolved at M0'
Assert ([int]$r.result.model_swaps -eq 0) 's8 no escalation (0 model swaps)'

# ---------------------------------------------------------------------------------------------------
# NEW (D-0061): the CRITICAL INVARIANT -- a contract-less SIMPLE goal that implies an output fast-paths at
# M0 with 0 escalation / 0 model swaps and returns `completed` (via the terminator), same cost as the floor.
Section 'no contract + implied output + tool succeeds -> completed at M0 via the D-0046 terminator (fast-path)'
$sc = NewScratch 's17'; $f = Join-Path $sc 'ok17.txt'
$plan = @{ decisions=@(@{text='doc.io'}, @{text='finish'}); args=@{ 'doc.io'=@{op='write';path=$f;content='M0'} } }
$r = Run-AutoRamp 's17' $sc 'make ok17.txt' $null $plan $null $null $null
Assert ($r.result.final_status -eq 'completed') "s17 completed (got $($r.result.final_status))"
Assert ($r.result.final_status -ne 'completed_unverified') 's17 NOT completed_unverified (terminator satisfied)'
Assert ($r.result.accepted_epoch -eq 'M0') "s17 accepted_epoch=M0 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 0) "s17 model_swaps=0 -- no escalation for a simple goal (got $($r.result.model_swaps))"
Assert (((Epochs $r) -notcontains 'S0') -and ((Epochs $r) -notcontains 'M1')) 's17 stayed at M0 (no ramp)'
Assert (Test-Path -LiteralPath $f) 's17 the tool actually ran at M0 (file written)'
Assert ($r.result.terminator.enabled -eq $true -and $r.result.terminator.mode -eq 'heuristic') 's17 terminator enabled (heuristic, contract-less)'
Assert ([int]$r.result.terminator.finish_blocked_count -eq 0) 's17 finish NOT spuriously blocked (tool ran before finish)'

# ---------------------------------------------------------------------------------------------------
# NEW (D-0061): the D-0046 terminator BLOCKS a premature finish (goal implies output, no tool has succeeded)
# and forces the side-effecting tool, then completes at M0 -- never re-running a done action, no ramp.
Section 'no contract: terminator BLOCKS a premature finish + forces the side-effecting tool, then completes at M0'
$sc = NewScratch 's18'; $f = Join-Path $sc 'blk18.txt'
$plan = @{ decisions=@(@{text='finish'}, @{text='finish'}); args=@{ 'doc.io'=@{op='write';path=$f;content='B'} } }
$r = Run-AutoRamp 's18' $sc 'make blk18.txt' $null $plan $null $null $null
Assert ($r.result.final_status -eq 'completed') "s18 completed (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'M0') 's18 completed at M0 (no ramp)'
Assert ([int]$r.result.model_swaps -eq 0) 's18 no escalation'
Assert ([int]$r.result.terminator.finish_blocked_count -ge 1) "s18 the premature finish was blocked >=1 (got $($r.result.terminator.finish_blocked_count))"
$blk = @($r.result.governor_trace | Where-Object { $_.terminator_finish_blocked -eq $true })
Assert (@($blk).Count -ge 1) 's18 a governor step recorded terminator_finish_blocked'
Assert ($blk[0].terminator_forced_tool -eq 'doc.io' -and $blk[0].tool_invoked -eq $true) 's18 step1 forced doc.io despite the finish decision'
Assert (Test-Path -LiteralPath $f) 's18 the forced side-effecting tool actually ran'

# ---------------------------------------------------------------------------------------------------
# NEW (D-0061): contract-less runs ramp ONLY on a HARD trigger -- SOFT strikes (bad arg-gen + no-progress)
# do NOT escalate without a contract; the run recovers + completes at M0 (proves "no cost change" holds).
Section 'no contract: SOFT strikes do NOT ramp (contract-less ramps only on a HARD trigger); completes at M0'
$sc = NewScratch 's19'; $f = Join-Path $sc 'soft19.txt'
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='finish'}); bad_arg_calls=@(0); args=@{ 'doc.io'=@{op='write';path=$f;content='S'} } }
$r = Run-AutoRamp 's19' $sc 'make soft19.txt' $null $plan $null $null $null
Assert ($r.result.final_status -eq 'completed') "s19 completed (got $($r.result.final_status))"
Assert (((Epochs $r) -notcontains 'M1') -and ((Epochs $r) -notcontains 'S0')) 's19 NO ramp on soft strikes without a contract (stayed M0)'
Assert ([int]$r.result.model_swaps -eq 0) 's19 zero model swaps'
Assert (Test-Path -LiteralPath $f) 's19 recovered on the good arg-gen and wrote the file at M0'

# ---------------------------------------------------------------------------------------------------
# NEW (D-0061): THE REGRESSION GUARD the single-side-effecting-tool mock could NOT provide (this is exactly why
# iter-8 shipped broken). With a registry that has MULTIPLE side-effecting tools (doc.io NEEDED + fs.manage
# EXTRA), a contract-less finish AFTER the needed tool succeeded must be HONORED at M0 -- NOT redirected to
# force the unrelated fs.manage. The reverted attempt blocked while ANY side-effecting tool was unsatisfied, so
# it forced fs.manage here and looped to max_steps+error on the real registry; the fix blocks only while NONE
# has succeeded, so this resolves in exactly 2 steps with fs.manage never touched.
Section 'no contract + MULTI side-effecting tools: finish honored after the needed tool (fs.manage NOT forced)'
$multiTools = Join-Path $TempRoot 'mock-tools-multi.json'
@{ tools = @(
    @{ tool='doc.io'; skill_id='doc.io'; entrypoint=$mockTool; description='write a text file'; args_hint='op,path,content'; args_example=@{op='write';path='x.txt';content='hi'}; required=@('op','path'); side_effecting=$true },
    @{ tool='fs.manage'; skill_id='fs.manage'; entrypoint=$mockTool; description='copy/move files'; args_hint='op,source,dest'; args_example=@{op='copy';source='a';dest='b'}; required=@('op'); side_effecting=$true }
) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $multiTools -Encoding utf8
$sc = NewScratch 's20'; $f = Join-Path $sc 'multi20.txt'
$plan = @{ decisions=@(@{text='doc.io'}, @{text='finish'}); args=@{ 'doc.io'=@{op='write';path=$f;content='M'} } }
$r = Run-AutoRamp 's20' $sc 'make multi20.txt' $null $plan $null $null $null $multiTools
Assert ($r.result.final_status -eq 'completed') "s20 completed (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'M0') "s20 accepted_epoch=M0 (got $($r.result.accepted_epoch))"
Assert ([int]$r.result.model_swaps -eq 0) "s20 model_swaps=0 (got $($r.result.model_swaps))"
Assert ([int]$r.result.terminator.finish_blocked_count -eq 0) "s20 finish NOT redirected (finish_blocked_count=0; the iter-8 bug forced fs.manage here) (got $($r.result.terminator.finish_blocked_count))"
Assert ([int]$r.result.step_count -eq 2) "s20 exactly 2 steps: doc.io + finish (got $($r.result.step_count))"
Assert ((@($r.result.completed_tools) -contains 'doc.io') -and (@($r.result.completed_tools) -notcontains 'fs.manage')) 's20 only doc.io ran; fs.manage was NEVER forced'
$fsRows = @($r.result.governor_trace | Where-Object { $_.decision -eq 'fs.manage' -or $_.terminator_forced_tool -eq 'fs.manage' })
Assert (@($fsRows).Count -eq 0) 's20 no governor step ever selected/forced fs.manage'
Assert (Test-Path -LiteralPath $f) 's20 the real file was written at M0'

# ---------------------------------------------------------------------------------------------------
# NEW (D-0061): robustness to a model that UNDER-USES `finish` (D-0032 -- the real failure mode, not caught by
# the mock's scripted finish). Contract-less, the model keeps re-choosing the already-succeeded action. The
# duplicate-side-effect guard, once the terminator is satisfied, is the DETERMINISTIC close (mirror the strict
# floor) -> completed at M0, 0 swaps, tool run once (NOT a hard escalation, NOT a max_steps loop).
Section 'no contract: model never emits finish (repeats) -> terminator closes at M0 (0 swaps, tool run once)'
$sc = NewScratch 's21'; $f = Join-Path $sc 'rep21.txt'
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}); args=@{ 'doc.io'=@{op='write';path=$f;content='R'} } }
$r = Run-AutoRamp 's21' $sc 'make rep21.txt' $null $plan $null $null $null
Assert ($r.result.final_status -eq 'completed') "s21 completed (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'M0') 's21 completed at M0'
Assert ([int]$r.result.model_swaps -eq 0) "s21 zero model swaps despite the model never emitting finish (got $($r.result.model_swaps))"
Assert (((Epochs $r) -notcontains 'M1') -and ((Epochs $r) -notcontains 'S0')) 's21 no ramp (the repeat is the terminator close, NOT a hard escalation)'
$dup = @($r.result.governor_trace | Where-Object { $_.skipped_repeat -eq $true })
Assert (@($dup).Count -ge 1) 's21 the repeat was caught (skipped_repeat)'
Assert ($dup[0].terminator_satisfied -eq $true) 's21 the repeat closed the run via the terminator (terminator_satisfied)'
Assert ($dup[0].hard_trigger -ne 'repeat_identical_action_no_state_change') 's21 the contract-less repeat did NOT hard-escalate'
Assert (Test-Path -LiteralPath $f) 's21 the file was written once at M0'
Assert ([int]$r.result.step_count -eq 2) "s21 exactly 2 steps: write + repeat-close (got $($r.result.step_count))"

# ---------------------------------------------------------------------------------------------------
Section 'un-checkable contract (unknown predicate) -> human_verification_required'
$sc = NewScratch 's9'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='vibes_are_good';path='x'}) }
$plan = @{ decisions=@(@{text='finish'}) }
$r = Run-AutoRamp 's9' $sc 'do a fuzzy thing' $c $plan $null $null $null
Assert ($r.result.final_status -eq 'human_verification_required') "s9 final_status=human_verification_required (got $($r.result.final_status))"
Assert ($r.result.contract.checkable -eq $false) 's9 contract marked un-checkable'

# ---------------------------------------------------------------------------------------------------
Section 'whole-task gpu lease renewal fires (renew ~30s -> here every step)'
$sc = NewScratch 's10'; $f = Join-Path $sc 'L.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
# force two tool steps before success so at least one renew is due (renew_s=0 -> every step)
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0); args=@{ 'doc.io'=@{op='write';path=$f;content='L'} } }
$r = Run-AutoRamp 's10' $sc 'make L.txt' $c $plan @{ gpu_lease_renew_s = 0 } $null $null
Assert ([int]$r.result.gpu_lease.renew_count -ge 1) "s10 gpu lease renewed >=1 (got $($r.result.gpu_lease.renew_count))"
Assert ([bool]$r.result.gpu_lease.released) 's10 gpu lease released'

# ---------------------------------------------------------------------------------------------------
Section 'governor trace artifact is written + machine-checkable'
$sc = NewScratch 's11'; $f = Join-Path $sc 'tr.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='doc.io'}); args=@{ 'doc.io'=@{op='write';path=$f;content='t'} } }
$r = Run-AutoRamp 's11' $sc 'make tr.txt' $c $plan $null $null $null
Assert (-not [string]::IsNullOrWhiteSpace($r.result.governor_trace_path)) 's11 governor_trace_path present'
Assert (Test-Path -LiteralPath $r.result.governor_trace_path) 's11 governor-trace.json exists on disk'
$traceOk = $false; try { $tj = (Get-Content -LiteralPath $r.result.governor_trace_path -Raw) | ConvertFrom-Json; $traceOk = ($tj.schema -eq 'lifeorch.governor_trace/0.1' -and @($tj.steps).Count -ge 1) } catch {}
Assert $traceOk 's11 governor-trace.json parses with schema + steps'

# ---------------------------------------------------------------------------------------------------
Section 'STAGE-2 X0: fires ONLY after S0 fails AND only under -AllowLegacy27B -> verified_success at X0'
$sc = NewScratch 's12'; $f = Join-Path $sc 'x0.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
# M0, M1, S0 arg-gens all fail (bad json) -> ramp M0->M1->S0->X0; X0 arg-gen (call 3) is good -> writes the file
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0,1,2); args=@{ 'doc.io'=@{op='write';path=$f;content='X0'} } }
$r = Run-AutoRamp 's12' $sc 'make x0.txt' $c $plan @{ x0_min_budget_s=1 } @('-AllowLegacy27B') $null
Assert ($r.result.final_status -eq 'verified_success') "s12 verified_success (got $($r.result.final_status))"
Assert ($r.result.accepted_epoch -eq 'X0') "s12 accepted_epoch=X0 (got $($r.result.accepted_epoch))"
Assert ((Epochs $r) -contains 'X0') 's12 the X0 rung fired'
Assert ((Epochs $r) -contains 'S0') 's12 X0 fired only AFTER S0 (S0 present + before X0)'
Assert (IsMonotonic $r) 's12 monotonic M0->M1->S0->X0 (never de-escalates)'
Assert ([int]$r.result.model_swaps -eq 2) "s12 model_swaps=2 (M->S0, S0->X0) (got $($r.result.model_swaps))"
Assert ([bool]$r.result.x0.enabled -and [bool]$r.result.x0.attempted -and [bool]$r.result.x0.fired) 's12 result.x0 records enabled+attempted+fired'
Assert ($r.result.x0.model -eq 'llm.strong.qwen3p5-27b') 's12 X0 model is the legacy 27B'
Assert (Test-Path -LiteralPath $f) 's12 the real file was written by the X0 rung'
$x0row = @($r.result.governor_trace | Where-Object { $_.epoch -eq 'X0' })[0]
Assert ($null -ne $x0row.x0_deadline_remaining_ms -and [int]$x0row.x0_deadline_remaining_ms -gt 0) 's12 X0 trace row carries deadline_remaining_ms'

# ---------------------------------------------------------------------------------------------------
Section 'STAGE-2 X0: WITHOUT -AllowLegacy27B the SAME failing plan stops at local_ceiling (Stage-1 default UNCHANGED)'
$sc = NewScratch 's13'; $f = Join-Path $sc 'nox0.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0,1,2); args=@{ 'doc.io'=@{op='write';path=$f;content='X0'} } }
$r = Run-AutoRamp 's13' $sc 'make nox0.txt' $c $plan $null $null $null
Assert ($r.result.final_status -eq 'local_ceiling_reached') "s13 final_status=local_ceiling_reached (got $($r.result.final_status))"
Assert ((Epochs $r) -notcontains 'X0') 's13 X0 NEVER fires without the switch'
Assert ([bool]$r.result.x0.enabled -eq $false -and [bool]$r.result.x0.fired -eq $false) 's13 result.x0 shows disabled + not fired'
Assert ([int]$r.result.model_swaps -eq 1) "s13 model_swaps=1 (M->S0 only) (got $($r.result.model_swaps))"

# ---------------------------------------------------------------------------------------------------
Section 'STAGE-2 X0: deadline-gated -- a simulated slow 27B past the deadline aborts cleanly (NEVER hangs)'
$sc = NewScratch 's14'; $f = Join-Path $sc 'slow.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}); bad_arg_calls=@(0,1,2); args=@{ 'doc.io'=@{op='write';path=$f;content='X0'} } }
$swW = [System.Diagnostics.Stopwatch]::StartNew()
$r = Run-AutoRamp 's14' $sc 'make slow.txt' $c $plan @{ x0_min_budget_s=1; x0_deadline_s=1; x0_simulated_delay_s=3 } @('-AllowLegacy27B') $null
$swW.Stop()
Assert ($r.result.final_status -eq 'human_verification_required') "s14 aborts to human_verification_required (got $($r.result.final_status))"
Assert ([bool]$r.result.x0.attempted) 's14 X0 was attempted (fired) before the deadline abort'
$abortRow = @($r.result.governor_trace | Where-Object { $_.epoch -eq 'X0' -and $_.x0_deadline_abort -eq $true })
Assert (@($abortRow).Count -eq 1) 's14 exactly one X0 deadline-abort row (single one-shot, no loop)'
Assert ($abortRow[0].hard_trigger -eq 'x0_deadline_exceeded') "s14 abort trigger=x0_deadline_exceeded (got $($abortRow[0].hard_trigger))"
Assert (-not (Test-Path -LiteralPath $f)) 's14 NO side effect after the deadline abort'
Assert ($r.result.verified_success -eq $false) 's14 never claims verified_success past the deadline'
Assert ($swW.Elapsed.TotalSeconds -lt 30) "s14 returned promptly ($([int]$swW.Elapsed.TotalSeconds)s) -- proves it did not hang"

# ---------------------------------------------------------------------------------------------------
Section 'STAGE-2 X0: the duplicate-side-effect guard refuses an exact-duplicate mutation on the X0 resume'
$sc = NewScratch 's15'; $fa = Join-Path $sc 'a.txt'; $fb = Join-Path $sc 'b.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$fa}, @{predicate='file_exists';path=$fb}) }
# step1 M0 writes a.txt (progress); M0(step2)/M1/S0 fail -> X0; X0 re-issues the SAME write a.txt -> refused
$plan = @{ decisions=@(@{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'}, @{text='doc.io'});
           bad_arg_calls=@(1,2,3); args_seq=@(@{op='write';path=$fa;content='A'}, $null, $null, $null, @{op='write';path=$fa;content='A'}) }
$r = Run-AutoRamp 's15' $sc 'make a.txt and b.txt' $c $plan @{ x0_min_budget_s=1 } @('-AllowLegacy27B') $null
$x0dup = @($r.result.governor_trace | Where-Object { $_.epoch -eq 'X0' -and $_.skipped_repeat -eq $true })
Assert (@($x0dup).Count -ge 1) 's15 a duplicate mutation was refused DURING the X0 resume (skipped_repeat on an X0 row)'
Assert ($x0dup[0].tool_invoked -eq $false) 's15 the duplicate X0 mutation was NOT re-invoked (idempotent resume)'
Assert ($x0dup[0].hard_trigger -eq 'repeat_identical_action_no_state_change') "s15 X0 dup is the frozen HARD trigger (got $($x0dup[0].hard_trigger))"
Assert (Test-Path -LiteralPath $fa) 's15 a.txt (written at M0) survives the escalation to X0 -- state resumed, not restarted'
Assert ([bool]$r.result.x0.attempted) 's15 X0 was reached'

# ---------------------------------------------------------------------------------------------------
Section 'STAGE-2 logprob/entropy soft signal: opt-in adds a strike; OFF by default changes nothing'
$sc = NewScratch 's16'; $f = Join-Path $sc 'e.txt'
$c = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}) }
# M0 step1: high-entropy decision + a bad arg-gen -> soft strikes -> M1; step2 M1 writes the file
$planE = @{ decisions=@(@{text='doc.io'; entropy=1.6}, @{text='doc.io'; entropy=0.1}); bad_arg_calls=@(0); args=@{ 'doc.io'=@{op='write';path=$f;content='E'} } }
# ON: -LogprobConfidence -> the controller requests logprobs; the mock surfaces entropy; the strike is counted
$rOn = Run-AutoRamp 's16on' $sc 'make e.txt (entropy on)' $c $planE @{ logprob_confidence=$true } $null $null
$onStep0 = $rOn.result.governor_trace[0]
Assert ($null -ne $onStep0.decision_entropy -and [double]$onStep0.decision_entropy -eq 1.6) "s16 ON: decision_entropy surfaced (proves logprobs were requested) (got $($onStep0.decision_entropy))"
Assert (@($onStep0.soft_reasons) -match 'high_decision_entropy') 's16 ON: a high_decision_entropy soft strike was added'
Assert ([int]$onStep0.soft_strikes_this_step -eq 3) "s16 ON: step1 soft=3 (arg_parse + no_progress + entropy) (got $($onStep0.soft_strikes_this_step))"
Assert ($rOn.result.final_status -eq 'verified_success') 's16 ON: still completes (additive, not a hard reject)'
# OFF (default): a fresh scratch so the file_exists contract starts unsatisfied; no logprobs requested, no strike
$sc2 = NewScratch 's16b'; $f2 = Join-Path $sc2 'e.txt'
$c2 = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f2}) }
$planE2 = @{ decisions=@(@{text='doc.io'; entropy=1.6}, @{text='doc.io'; entropy=0.1}); bad_arg_calls=@(0); args=@{ 'doc.io'=@{op='write';path=$f2;content='E'} } }
$rOff = Run-AutoRamp 's16off' $sc2 'make e.txt (entropy off)' $c2 $planE2 $null $null $null
$offStep0 = $rOff.result.governor_trace[0]
Assert ($null -eq $offStep0.decision_entropy) 's16 OFF: no entropy surfaced by default (logprobs NOT requested)'
Assert (-not (@($offStep0.soft_reasons) -match 'high_decision_entropy')) 's16 OFF: no entropy strike by default'
Assert ([int]$offStep0.soft_strikes_this_step -eq 2) "s16 OFF: step1 soft=2 (arg_parse + no_progress only) (got $($offStep0.soft_strikes_this_step))"

# ---------------------------------------------------------------------------------------------------
Write-Host ""
Write-Host "================= AUTORAMP OFF-MACHINE GATE ================="
Write-Host ("Scenarios: {0}   PASS: {1}   FAIL: {2}" -f $script:scn, $script:pass, $script:fail)
Write-Host "============================================================"
try { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
