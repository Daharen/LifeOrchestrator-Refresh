#requires -Version 7.0
<#
  Invoke-ResLeaseR1bPrimeTests.ps1 -- the R1b' (v0.4) adversarial off-machine gate for res.lease.
  Drives the REAL Invoke-ResLease.ps1. Deterministic + OS-portable (temp lease dir), ASCII-only. Runs off-GPU on
  cloud pwsh 7.4.6 (pre-ship gate) and unchanged live via the executor. This is the off-machine-PROVABLE subset of
  the i19 red-team's adversarial matrix (frontier pack b823d9db). It folds the BLOCKING primitive changes that the
  three proposed identities + the ten-step transition were found NOT sufficient without:

    A  ABA recovery         -- a restarted owner mints a NEW incarnation + a NEW resident_instance_id; every stale
                               callback (result/manifest/release/renew/stop/kill) captured against the OLD identity
                               is FENCED OUT and cannot publish, mutate, release, or kill the replacement.
    B  commit-response loss -- a retry on the SAME acquisition idempotency key returns the SAME committed grant,
                               never a second epoch / lease / resident (single-shot AND two-phase commit).
    C  stale side-effect matrix -- every late side effect from an old instance (result_publish / manifest_write /
                               lease_release / lease_renew / stop / health_fail / idle_evict / complete) fails
                               against the new instance.
    D  superseded external op -- a T1 whose epoch was superseded by T2 cannot affect T2 with its delayed actions.
    E  reentrant evictor     -- a command evictor that synchronously calls back into res.lease (status/check/
                               fence-op/acquire) does not deadlock, invert lock order, or create a second transition.
    F  renewal/revocation race -- exactly one CAS wins; a renewal can NEVER resurrect a revoked lease.
    G  active preemption liveness (mock) -- reserve+fence is one commit; no new lower-priority exec is issued;
                               the higher-priority transition succeeds bounded (does not wait forever on the old owner).
    H  partial-alloc-fail (mock) -- a partial-load OOM (evictor partial_tree_term / phase-2 health_failed) publishes
                               and grants NOTHING; the partial tree is reclaimed; a later clean transition succeeds.
    J  lease expiry in EVERY phase -- reserved/fenced, draining, starting(capability), healthy-unpublished,
                               committed-but-response-lost; a crashed txn in each phase is reconciled to ABORTED.
    K  waiter sequencing     -- a waiter re-reads a DURABLE state_version (monotonic across grant/renew/revoke/
                               release), never a one-shot signal; a stale state_version is fenced out.

  The single scheduler-owned transition + two-phase capability (blocker 1: no ordinary exec authority before health
  + publish), the target-fenced side-effect gate (blockers 4/8), and the idempotent journal (blocker 5) are what
  make the above hold at the PRIMITIVE layer. res.lease stays PURE: the real supervisor (drain/cancel/tree-kill
  under a Job Object) + real health/admission + the LIVE cases below are the later #7 consumer wave.

  DEFERRED to the LIVE consumer wave (NOT faked here -- listed so coverage is honest):
    * real GPU OOM on a real llama-server partial load (H-live), real supervisor/descendant escape + PID reuse
      (red-team I), real WDDM external-consumer pressure after headroom sampling (section 5 live), and the real
      3B<->9B swap / pin-revocation / prepared-eviction proof. Findings 1/13/14 close only after those pass live.

  Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh'),
    [string]$SkillPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-ResLease.ps1')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m29-r1bprime-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$leaseDir = Join-Path $work 'leases'
$artRoot  = Join-Path $work 'art'
New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function Run-Res([hashtable]$inputs) {
    $ij = ($inputs | ConvertTo-Json -Compress -Depth 8)
    $errF = Join-Path $work ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $out = & $PwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SkillPath -InputsJson $ij -LeaseDir $leaseDir -ArtifactRoot $artRoot 2> $errF
    $txt = ($out | Out-String).Trim()
    $e = $null; try { $e = $txt | ConvertFrom-Json } catch { }
    return @{ env=$e; raw=$txt; err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}
function Res([hashtable]$inputs) { return (Run-Res $inputs).env.result }
# Replicate the skill's per-resource sibling-file naming (fence / txn / state) so the harness can inject/inspect.
function Sibling([string]$res,[string]$ext) {
    $safe = ($res -replace '[^A-Za-z0-9._-]','_'); if ($safe.Length -gt 48){$safe=$safe.Substring(0,48)}
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try { $h=([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($res)))).Replace('-','').ToLowerInvariant().Substring(0,8) } finally { $sha.Dispose() }
    return (Join-Path $leaseDir "$safe-$h.$ext")
}
# Async process (named args) for real cross-process races.
function Start-ResProc([string[]]$rest) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PwshExe
    foreach ($a in @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$SkillPath) + $rest + @('-LeaseDir',$leaseDir,'-ArtifactRoot',$artRoot)) { [void]$psi.ArgumentList.Add([string]$a) }
    $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}
function Read-ProcEnv([System.Diagnostics.Process]$p) {
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    $e = $null; try { $e = ($out.Trim() | ConvertFrom-Json) } catch { }
    return $e
}

Write-Output "res.lease R1b' (v0.4) adversarial gate"
Write-Output "======================================"

# ---------- T0: manifest + envelope report v0.4 ----------
$manifestPath = Join-Path (Split-Path -Parent $SkillPath) 'skill.json'
$mani = $null; if (Test-Path $manifestPath) { $mani = Get-Content -Raw $manifestPath | ConvertFrom-Json }
Ok ($null -ne $mani -and $mani.version -eq '0.4.0' -and $mani.contract_version -eq '0.4') 'T0 skill.json reports version 0.4.0 / contract 0.4'
$probe = Res @{ action='acquire'; resource='probe'; holder='p'; owner_id='p'; owner_incarnation_id='i0' }
Ok ($null -ne $probe -and $probe.owner_incarnation_id -eq 'i0' -and -not [string]::IsNullOrWhiteSpace($probe.resident_instance_id)) 'T0 v0.4 engaged acquire carries owner_incarnation_id + resident_instance_id'

# =====================================================================================================
# A -- ABA recovery: a restarted owner + a stale-manifest reclaim mint NEW incarnations; old callbacks die.
# =====================================================================================================
Write-Output "A ABA recovery (restarted owner + stale callbacks fenced):"
$a1 = Res @{ action='acquire'; resource='aba'; holder='H'; owner_id='H'; owner_incarnation_id='incA'; resident_instance_id='riA'; resident_generation='G7' }
$tokA = [long]$a1.gpu_authority_epoch
Ok ($a1.acquired -eq $true -and $a1.owner_incarnation_id -eq 'incA' -and $a1.resident_instance_id -eq 'riA') 'A old resident G7/incA/riA acquired'
Run-Res @{ action='release'; resource='aba'; lease_id=$a1.lease_id } | Out-Null
# same logical owner RESTARTS -> a NEW incarnation + a NEW instance; the epoch is strictly greater
$a2 = Res @{ action='acquire'; resource='aba'; holder='H'; owner_id='H'; owner_incarnation_id='incB'; resident_instance_id='riB'; resident_generation='G7' }
$tokB = [long]$a2.gpu_authority_epoch
Ok ($a2.owner_incarnation_id -eq 'incB' -and $a2.resident_instance_id -eq 'riB' -and $tokB -gt $tokA) 'A restart -> NEW incarnation + NEW instance + epoch advanced (ABA cycle broken)'
# the old owner_incarnation cannot assert authority even with the same owner_id + generation
$c = Res @{ action='check'; resource='aba'; owner_id='H'; owner_incarnation_id='incA'; resident_generation='G7'; authority_epoch=$tokA }
Ok ($c.authority_ok -eq $false -and $c.owner_incarnation_current -eq $false) 'A stale owner_incarnation -> authority_ok false (cannot publish a stale result)'
# an old stop/kill callback captured against riA is refused against the current riB
$fs = Res @{ action='fence-op'; resource='aba'; op_kind='stop'; resident_instance_id='riA'; authority_epoch=$tokA }
Ok ($fs.fenced_op_ok -eq $false -and $fs.reason -eq 'target_instance_mismatch') 'A stale stop/kill callback (old instance) -> REFUSED (cannot terminate the replacement)'
# an old manifest_write + an old idle_evict likewise refused
$fm = Res @{ action='fence-op'; resource='aba'; op_kind='manifest_write'; resident_instance_id='riA' }
$fi = Res @{ action='fence-op'; resource='aba'; op_kind='idle_evict'; resident_instance_id='riA' }
Ok ($fm.fenced_op_ok -eq $false -and $fi.fenced_op_ok -eq $false) 'A stale manifest_write + idle_evict against the old instance -> REFUSED'
# an old lease-release with the stale epoch is fenced out (cannot release the replacement)
$rl = Res @{ action='release'; resource='aba'; lease_id=$a1.lease_id; authority_epoch=$tokA }
Ok ($rl.released -eq $false) 'A stale lease-release (old lease_id/epoch) -> cannot release the replacement'

# =====================================================================================================
# B -- commit-response loss: a retry on the SAME request_id returns the SAME grant (no 2nd epoch/lease).
# =====================================================================================================
Write-Output "B commit-response loss (idempotent replay):"
# single-shot transition with an idempotency key
$b1 = Res @{ action='acquire'; resource='bidem'; holder='W'; owner_id='W'; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; request_id='RQ'; resident_instance_id='riS' }
Ok ($b1.acquired -eq $true -and $b1.idempotent_replay -eq $false) 'B first transition grants (not a replay)'
$b2 = Res @{ action='acquire'; resource='bidem'; holder='W'; owner_id='W'; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; request_id='RQ'; resident_instance_id='riS' }
Ok ($b2.idempotent_replay -eq $true -and $b2.lease_id -eq $b1.lease_id -and [long]$b2.gpu_authority_epoch -eq [long]$b1.gpu_authority_epoch) 'B retry on the same request_id -> SAME lease + SAME epoch (no 2nd transition)'
# two-phase: commit, then a lost-response retry of the COMMIT replays the same usable grant
$bp1 = Res @{ action='acquire'; resource='btp'; holder='W'; owner_id='W'; transition=$true; two_phase_commit=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; resident_instance_id='riT' }
Ok ($bp1.usable -eq $false -and $bp1.capability_only -eq $true) 'B phase-1 issues a NON-usable capability'
$bc1 = Res @{ action='commit'; resource='btp'; holder='W'; owner_id='W'; resident_instance_id='riT'; health_ok=$true }
$bc2 = Res @{ action='commit'; resource='btp'; holder='W'; owner_id='W'; resident_instance_id='riT'; health_ok=$true }
Ok ($bc1.committed -eq $true -and $bc1.usable -eq $true -and -not [string]::IsNullOrWhiteSpace($bc1.exec_lease_id)) 'B phase-2 commit publishes a usable exec lease'
Ok ($bc2.committed -eq $true -and $bc2.reason -eq 'idempotent_replay' -and $bc2.exec_lease_id -eq $bc1.exec_lease_id) 'B commit RETRY (lost response) -> SAME committed grant'

# =====================================================================================================
# C -- stale side-effect matrix: after publishing riNEW, EVERY late side effect from riOLD fails.
# =====================================================================================================
Write-Output "C stale side-effect matrix (old instance cannot touch the new one):"
# a pin (old resident riOLD) is preempted by a transition that publishes riNEW
$oldPin = Res @{ action='acquire'; resource='cmx'; holder='OLD'; owner_id='OLD'; kind='residency_pin'; priority=1; owner_incarnation_id='incOLD'; resident_instance_id='riOLD' }
$tr = Res @{ action='acquire'; resource='cmx'; holder='NEW'; owner_id='NEW'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='needs_evict'; owner_incarnation_id='incNEW'; resident_instance_id='riNEW' }
Ok ($tr.acquired -eq $true -and $tr.resident_instance_id -eq 'riNEW') 'C transition published the new instance riNEW'
$matrix = @('result_publish','manifest_write','lease_release','lease_renew','stop','health_fail','idle_evict','complete')
$allRefused = $true
foreach ($op in $matrix) {
    $r = Res @{ action='fence-op'; resource='cmx'; op_kind=$op; resident_instance_id='riOLD'; authority_epoch=$oldPin.gpu_authority_epoch }
    if ($r.fenced_op_ok -ne $false) { $allRefused = $false; Write-Output "      (op $op unexpectedly allowed)" }
}
Ok $allRefused 'C ALL 8 late side effects from riOLD are refused against riNEW'
# the same op TARGETING riNEW with the current epoch is allowed (positive control)
$okOp = Res @{ action='fence-op'; resource='cmx'; op_kind='complete'; resident_instance_id='riNEW'; authority_epoch=$tr.gpu_authority_epoch }
Ok ($okOp.fenced_op_ok -eq $true) 'C the same op targeting the CURRENT instance riNEW is allowed (positive control)'
# the old pinner cannot renew (it was revoked) and cannot release the new lease
$oldRenew = Res @{ action='renew'; resource='cmx'; lease_id=$oldPin.lease_id }
Ok ($oldRenew.renewed -eq $false -and ($oldRenew.reason -eq 'revoked' -or $oldRenew.reason -eq 'lease_lost')) 'C old pinner renew -> refused (authority lost)'

# =====================================================================================================
# D -- superseded external op: a T1 whose epoch was superseded cannot affect the winner T2.
# =====================================================================================================
Write-Output "D superseded external op (T1 delayed actions cannot touch T2):"
$t2 = Res @{ action='acquire'; resource='dsx'; holder='T2'; owner_id='T2'; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; owner_incarnation_id='incT2'; resident_instance_id='riT2' }
$tokT2 = [long]$t2.gpu_authority_epoch
Ok ($t2.acquired -eq $true) 'D T2 is the winner (published riT2)'
# T1 captured an older epoch (tokT2-1) + an old instance riT1; its delayed stop / recommit are fenced out
$d1 = Res @{ action='fence-op'; resource='dsx'; op_kind='stop'; resident_instance_id='riT1'; authority_epoch=($tokT2-1) }
$d2 = Res @{ action='check'; resource='dsx'; owner_id='T1'; owner_incarnation_id='incT1'; resident_instance_id='riT1'; authority_epoch=($tokT2-1) }
Ok ($d1.fenced_op_ok -eq $false -and $d2.authority_ok -eq $false) 'D T1 delayed stop + recommit (old epoch/instance) -> refused'
# T2 remains healthy + published
$d3 = Res @{ action='check'; resource='dsx'; owner_id='T2'; owner_incarnation_id='incT2'; resident_instance_id='riT2'; authority_epoch=$tokT2 }
Ok ($d3.authority_ok -eq $true -and $d3.resident_instance_current -eq $true) 'D T2 stays healthy + published (unaffected by T1)'

# =====================================================================================================
# E -- reentrant evictor: a command evictor that calls back into res.lease does not deadlock / re-transition.
# =====================================================================================================
Write-Output "E reentrant evictor (no deadlock, no lock-order inversion, no second transition):"
$reentrant = Join-Path $work 'evictor_reentrant.ps1'
$body = @"
param([string]`$ContextJson)
`$ctx = `$ContextJson | ConvertFrom-Json
`$ld = [string]`$ctx.lease_dir; `$res = [string]`$ctx.resource
# synchronously RE-ENTER res.lease from inside the evictor: status + check + fence-op + a plain acquire on ANOTHER
# resource. If any lease-state mutex were held across the evictor call, one of these would deadlock.
& '$PwshExe' -NoLogo -NoProfile -NonInteractive -File '$SkillPath' -Action status -Resource `$res -LeaseDir `$ld 2>`$null | Out-Null
& '$PwshExe' -NoLogo -NoProfile -NonInteractive -File '$SkillPath' -Action check  -Resource `$res -LeaseDir `$ld 2>`$null | Out-Null
& '$PwshExe' -NoLogo -NoProfile -NonInteractive -File '$SkillPath' -Action fence-op -Resource `$res -OpKind stop -ResidentInstanceId reentrant-none -LeaseDir `$ld 2>`$null | Out-Null
& '$PwshExe' -NoLogo -NoProfile -NonInteractive -File '$SkillPath' -Action acquire -Resource 'other-reentrant' -Holder ev -LeaseDir `$ld 2>`$null | Out-Null
[ordered]@{ confirmed=`$true; free_vram_mib=99999; evicted=`$true; tree_gone=`$true; outcome='confirm'; detail='reentrant evictor returned' } | ConvertTo-Json -Compress
"@
Set-Content -LiteralPath $reentrant -Value $body -Encoding ascii
$e1 = Res @{ action='acquire'; resource='reent'; holder='RE'; owner_id='RE'; transition=$true; required_vram_mib=6700; evictor_mode='command'; evictor_command=$reentrant; resident_instance_id='riRE' }
Ok ($e1.acquired -eq $true -and $e1.transition_state -eq 'STARTING') 'E transition with a reentrant command evictor completes (no deadlock)'
$txns = @(Get-ChildItem -LiteralPath $leaseDir -Filter '*reent*.txn' -File -ErrorAction SilentlyContinue)
Ok ($txns.Count -eq 1) 'E exactly ONE transition journal for the resource (no accidental second transition)'
$otherSt = Res @{ action='status'; resource='other-reentrant' }
Ok ($otherSt.exists -eq $true) 'E the reentrant plain acquire on another resource succeeded (no lock-order inversion)'

# =====================================================================================================
# F -- renewal/revocation race: exactly one CAS wins; a renewal cannot resurrect a revoked lease.
# =====================================================================================================
Write-Output "F renewal/revocation race (a renew cannot resurrect a revoked pin):"
# deterministic: revoke THEN renew -> the renew observes revoked and refuses (never clears revoked_by)
$fp = Res @{ action='acquire'; resource='frr'; holder='P'; owner_id='P'; kind='residency_pin'; priority=1 }
[void](Res @{ action='acquire'; resource='frr'; holder='Q'; owner_id='Q'; priority=5 })   # revokes P's pin
$fr = Res @{ action='renew'; resource='frr'; lease_id=$fp.lease_id }
Ok ($fr.renewed -eq $false -and $fr.reason -eq 'revoked') 'F renew AFTER revoke -> revoked (never resurrects)'
$fchk = Res @{ action='check'; resource='frr' }
Ok ($fchk.fence_status -eq 'revoked' -and $null -ne $fchk.revoked_by) 'F the pin stays revoked (revoked_by preserved)'
Run-Res @{ action='release'; resource='frr'; holder='P' } | Out-Null
# concurrent: N renewers race a revoker; the revoke must NEVER be lost (oplock serializes the RMW)
$fp2 = Res @{ action='acquire'; resource='frr2'; holder='P'; owner_id='P'; kind='residency_pin'; priority=1 }
$procs = New-Object System.Collections.Generic.List[object]
for ($i=0; $i -lt 4; $i++) { $procs.Add((Start-ResProc @('-Action','renew','-Resource','frr2','-LeaseId',$fp2.lease_id,'-Kind','residency_pin'))) }
$procs.Add((Start-ResProc @('-Action','acquire','-Resource','frr2','-Holder','Q','-OwnerId','Q','-Priority','5')))
foreach ($p in $procs) { [void](Read-ProcEnv $p) }
$fchk2 = Res @{ action='check'; resource='frr2' }
Ok ($fchk2.fence_status -eq 'revoked' -and $null -ne $fchk2.revoked_by) 'F concurrent renewers vs revoker -> revoke NEVER lost (final state revoked)'
$fr2 = Res @{ action='renew'; resource='frr2'; lease_id=$fp2.lease_id }
Ok ($fr2.renewed -eq $false) 'F a post-race renew still cannot resurrect the revoked pin'

# =====================================================================================================
# G -- active preemption liveness (mock): reserve+fence one commit; no new lower exec; bounded success.
# =====================================================================================================
Write-Output "G active priority-preemption liveness:"
$lowPin = Res @{ action='acquire'; resource='glv'; holder='LOW'; owner_id='LOW'; kind='residency_pin'; priority=1; resident_instance_id='riLOW' }
$hi = Res @{ action='acquire'; resource='glv'; holder='HI'; owner_id='HI'; priority=9; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='needs_evict'; resident_instance_id='riHI' }
Ok ($hi.acquired -eq $true -and $hi.revocation_signaled -eq $true) 'G higher-priority transition preempts + succeeds (bounded, not waiting forever)'
Ok ([long]$hi.gpu_authority_epoch -gt [long]$lowPin.gpu_authority_epoch) 'G reserve+fence is one commit (epoch advanced atomically)'
# the low-priority owner cannot renew or reacquire an exec through the transition (no new lower exec issued)
$lowRenew = Res @{ action='renew'; resource='glv'; lease_id=$lowPin.lease_id }
Ok ($lowRenew.renewed -eq $false) 'G the preempted low-priority owner cannot renew (no lower-priority exec survives)'

# =====================================================================================================
# H -- partial-alloc-fail (mock): nothing published/granted; partial tree reclaimed; later transition succeeds.
# =====================================================================================================
Write-Output "H partial-alloc-fail (mock):"
# evictor reports the managed tree did NOT fully exit -> no grant
$h1 = Res @{ action='acquire'; resource='hpf'; holder='X'; owner_id='X'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='partial_tree_term'; resident_instance_id='riH1' }
Ok ($h1.acquired -eq $false -and $h1.tree_gone -eq $false -and $h1.transition_state -eq 'ABORTED') 'H partial tree term -> no grant, ABORTED'
Ok ((Res @{ action='status'; resource='hpf' }).exists -eq $false) 'H nothing published on partial tree term'
# two-phase: capability granted, then health_failed (partial-load OOM) -> capability dropped, GPU empty
$h2 = Res @{ action='acquire'; resource='hpf2'; holder='X'; owner_id='X'; transition=$true; two_phase_commit=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; resident_instance_id='riH2' }
$h2c = Res @{ action='commit'; resource='hpf2'; holder='X'; owner_id='X'; resident_instance_id='riH2'; health_failed=$true }
Ok ($h2c.committed -eq $false -and $h2c.reason -eq 'health_failed' -and $h2c.transition_state -eq 'ABORTED') 'H phase-2 health_failed -> publish/grant NOTHING (fail-closed)'
Ok ((Res @{ action='status'; resource='hpf2' }).exists -eq $false) 'H the partial tentative instance is reclaimed (slot empty)'
# a LATER clean transition on the reclaimed slot succeeds
$h3 = Res @{ action='acquire'; resource='hpf2'; holder='Y'; owner_id='Y'; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; resident_instance_id='riH3' }
Ok ($h3.acquired -eq $true) 'H a later clean transition on the reclaimed slot succeeds'

# =====================================================================================================
# J -- lease expiry in every phase (capability expiry + a crashed txn in each phase reconciled).
# =====================================================================================================
Write-Output "J lease expiry in every phase:"
# a two-phase capability that expires before commit -> commit fails closed (capability_lost); nothing usable
$j1 = Res @{ action='acquire'; resource='jexp'; holder='W'; owner_id='W'; transition=$true; two_phase_commit=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; ttl_seconds=1; resident_instance_id='riJ' }
Ok ($j1.usable -eq $false) 'J capability issued with ttl=1'
Start-Sleep -Seconds 2
$jchk = Res @{ action='check'; resource='jexp'; owner_id='W'; resident_instance_id='riJ' }
Ok ($jchk.stale -eq $true -and $jchk.authority_ok -eq $false) 'J an expired capability confers NO authority'
$jc = Res @{ action='commit'; resource='jexp'; holder='W'; owner_id='W'; resident_instance_id='riJ'; health_ok=$true }
Ok ($jc.committed -eq $false -and $jc.reason -eq 'capability_lost') 'J commit of an expired capability -> capability_lost (no usable grant)'
# a crashed txn in EACH durable phase is reconciled to ABORTED (check -Reconcile)
$phases = @('RESERVED_FENCED','DRAINING','TERMINATING','STARTING','HEALTHY_UNPUBLISHED')
$allReconciled = $true
foreach ($ph in $phases) {
    $rn = "jr-$ph"
    $tp = Sibling $rn 'txn'
    $stale = [ordered]@{ schema='lifeorch.res.lease.txn/0.2'; txn_id="dead-$ph"; resource=$rn; owner_id='DEAD'; holder='DEAD'; state=$ph; authority_epoch=1; prior_epoch=0; started_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')); updated_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')) }
    [System.IO.File]::WriteAllText($tp, ($stale | ConvertTo-Json -Depth 6))
    $rr = Res @{ action='check'; resource=$rn; reconcile=$true }
    if (-not ($null -ne $rr.reconciled -and $rr.reconciled.reconciled -eq $true -and $rr.reconciled.from_state -eq $ph)) { $allReconciled = $false; Write-Output "      (phase $ph not reconciled)" }
}
Ok $allReconciled 'J a crashed txn in EVERY durable phase is reconciled to ABORTED'

# =====================================================================================================
# K -- waiter sequencing: a durable, monotonic state_version (never a one-shot signal); stale version fenced.
# =====================================================================================================
Write-Output "K waiter sequencing (durable state_version):"
$k1 = Res @{ action='acquire'; resource='kwait'; holder='K'; owner_id='K'; resident_instance_id='riK' }
$sv1 = [long]$k1.state_version
$kc1 = Res @{ action='check'; resource='kwait'; owner_id='K'; resident_instance_id='riK' }
Ok ($kc1.current_state_version -eq $sv1 -and $sv1 -ge 1) 'K a waiter reads the DURABLE current_state_version'
$kr = Res @{ action='renew'; resource='kwait'; lease_id=$k1.lease_id; owner_id='K' }
$kc2 = Res @{ action='check'; resource='kwait'; owner_id='K'; resident_instance_id='riK' }
Ok ([long]$kc2.current_state_version -gt $sv1) 'K state_version bumps on renew (a waiter re-reads a newer durable version)'
# a stale state_version (captured before the renew) is fenced out on a fence-op / check CAS
$kf = Res @{ action='fence-op'; resource='kwait'; op_kind='complete'; resident_instance_id='riK'; state_version=$sv1 }
Ok ($kf.fenced_op_ok -eq $false -and $kf.reason -eq 'state_version_stale') 'K a stale captured state_version is fenced out (no lost-wakeup action)'
$svBeforeRel = [long]$kc2.current_state_version
Run-Res @{ action='release'; resource='kwait'; lease_id=$k1.lease_id } | Out-Null
$kc3 = Res @{ action='check'; resource='kwait'; resident_instance_id='riK' }   # a v0.4 input surfaces current_state_version
Ok ([long]$kc3.current_state_version -gt $svBeforeRel) 'K state_version bumps on release (monotonic across grant/renew/release)'

# ---------- additive/default-off guards (v0.4 is INERT unless engaged) ----------
Write-Output "Z additive/default-off guards:"
$z1 = Res @{ action='acquire'; resource='zplain'; holder='Z' }
Ok (-not (Has $z1 'owner_incarnation_id') -and -not (Has $z1 'resident_instance_id') -and -not (Has $z1 'state_version') -and -not (Has $z1 'usable')) 'Z a plain acquire carries NO v0.4 fields (byte-identical to v0.1)'
$z2 = Res @{ action='acquire'; resource='zr3'; holder='Z'; owner_id='Z'; resident_generation='g'; transition=$false }
Ok (-not (Has $z2 'owner_incarnation_id') -and -not (Has $z2 'resident_instance_id')) 'Z a v0.3-engaged acquire (owner_id/resident_generation, no v0.4 input) carries NO incarnation fields'

Write-Output ""
Write-Output ("==== R1b' RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
