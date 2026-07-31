#requires -Version 7.0
<#
  Invoke-ResLeaseR1bTests.ps1 -- the R1b (v0.3) adversarial off-machine gate for res.lease.
  Drives the REAL Invoke-ResLease.ps1. Deterministic + OS-portable (temp lease dir), ASCII-only. Runs off-GPU
  on cloud pwsh 7.4.6 (pre-ship gate) and unchanged live via the executor. Exercises the THREE-IDENTITY fencing
  (gpu_authority_epoch / resident_generation / exec_lease_id), the single scheduler-owned ATOMIC transition,
  the ADVERSARIAL mock evictor (late evict / partial tree / headroom never / headroom fell / cancel / timeout),
  commit-if-epoch-current (superseded), single-winner serialization, crash reconcile, in-flight revocation
  (result-after-revocation), expiry-during-exec, and the byte-identical / R1a-unchanged guards.
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

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m29-r1b-tests-" + [Guid]::NewGuid().ToString('N'))
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
# Replicate the skill's per-resource sibling-file naming (fence / txn) so the harness can inject/inspect.
function Sibling([string]$res,[string]$ext) {
    $safe = ($res -replace '[^A-Za-z0-9._-]','_'); if ($safe.Length -gt 48){$safe=$safe.Substring(0,48)}
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try { $h=([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($res)))).Replace('-','').ToLowerInvariant().Substring(0,8) } finally { $sha.Dispose() }
    return (Join-Path $leaseDir "$safe-$h.$ext")
}

Write-Output "res.lease R1b (v0.3) adversarial gate"
Write-Output "===================================="

# ---------- T0: manifest reports v0.3 ----------
$manifestPath = Join-Path (Split-Path -Parent $SkillPath) 'skill.json'
$mani = $null; if (Test-Path $manifestPath) { $mani = Get-Content -Raw $manifestPath | ConvertFrom-Json }
# version pin tracks the res.lease version bump; the 36 BEHAVIORAL assertions below are unchanged (0-regression).
Ok ($null -ne $mani -and $mani.version -eq '0.4.0' -and $mani.contract_version -eq '0.4') 'T0 skill.json reports version 0.4.0 / contract 0.4'
$r = Run-Res @{ action='acquire'; resource='probe'; holder='p'; owner_id='p' }
Ok ($null -ne $r.env -and $r.env.skill_version -eq '0.4.0') 'T0 envelope skill_version 0.4.0'

# ---------- T1: three-identity fencing ----------
Write-Output "T1 three-identity fencing:"
$r = Run-Res @{ action='acquire'; resource='gpu-t1'; holder='H1'; owner_id='H1'; resident_generation='gen-A' }
$res = $r.env.result
Ok ($null -ne $res -and $res.acquired -eq $true) 'T1 engaged exec acquire succeeds'
Ok ($res.gpu_authority_epoch -eq $res.fencing_token -and $res.fencing_token -ge 1) 'T1 gpu_authority_epoch == fencing_token'
Ok ($res.exec_lease_id -eq $res.lease_id -and -not [string]::IsNullOrWhiteSpace($res.exec_lease_id)) 'T1 exec_lease_id == lease_id'
Ok ($res.resident_generation -eq 'gen-A' -and $res.owner_id -eq 'H1') 'T1 resident_generation + owner_id stamped'
$tok = [long]$res.fencing_token
# full-tuple assertion: correct owner + generation + token -> authority_ok
$c = (Run-Res @{ action='check'; resource='gpu-t1'; owner_id='H1'; resident_generation='gen-A'; authority_epoch=$tok }).env.result
Ok ($c.authority_ok -eq $true -and $c.owner_current -eq $true -and $c.generation_current -eq $true -and $c.token_current -eq $true) 'T1 check: matching tuple -> authority_ok'
# wrong generation
$c = (Run-Res @{ action='check'; resource='gpu-t1'; owner_id='H1'; resident_generation='gen-WRONG'; authority_epoch=$tok }).env.result
Ok ($c.generation_current -eq $false -and $c.authority_ok -eq $false) 'T1 check: wrong resident_generation -> authority_ok false'
# wrong owner
$c = (Run-Res @{ action='check'; resource='gpu-t1'; owner_id='OTHER'; resident_generation='gen-A'; authority_epoch=$tok }).env.result
Ok ($c.owner_current -eq $false -and $c.authority_ok -eq $false) 'T1 check: wrong owner_id -> authority_ok false'
# stale epoch (stale idle callback: an old-epoch actor cannot assert authority)
$c = (Run-Res @{ action='check'; resource='gpu-t1'; owner_id='H1'; resident_generation='gen-A'; authority_epoch=($tok-1) }).env.result
Ok ($c.token_current -eq $false -and $c.authority_ok -eq $false) 'T1 check: stale authority_epoch -> authority_ok false (stale idle callback fenced)'

# ---------- T2: transition on a free slot ----------
Write-Output "T2 transition (free slot):"
$priorEpoch = 0
if (Test-Path (Sibling 'gpu-t2' 'fence')) { $priorEpoch = [long](Get-Content -Raw (Sibling 'gpu-t2' 'fence')) }
$r = Run-Res @{ action='acquire'; resource='gpu-t2'; holder='W'; owner_id='W'; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm'; resident_generation='g2' }
$res = $r.env.result
Ok ($res.acquired -eq $true -and $res.transition -eq $true) 'T2 transition grants on a free slot'
Ok ($res.transition_state -eq 'STARTING' -and $res.headroom_confirmed -eq $true) 'T2 state STARTING + headroom confirmed'
Ok ($res.gpu_authority_epoch -gt $priorEpoch) 'T2 authority epoch minted (> prior)'
Ok ($res.exec_lease_id -eq $res.lease_id) 'T2 exec_lease_id set on the granted exec lease'

# ---------- T3: transition preempts a lower-priority pin + result-after-revocation ----------
Write-Output "T3 transition preempts a lower-priority pin:"
$pin = (Run-Res @{ action='acquire'; resource='gpu-t3'; holder='PINNER'; owner_id='PINNER'; kind='residency_pin'; priority=1 }).env.result
$pinTok = [long]$pin.fencing_token
Ok ($pin.acquired -eq $true -and $pin.revocable -eq $true) 'T3 lower-priority residency_pin resident'
$r = Run-Res @{ action='acquire'; resource='gpu-t3'; holder='SEIZER'; owner_id='SEIZER'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='needs_evict'; resident_generation='g3' }
$res = $r.env.result
Ok ($res.acquired -eq $true -and $res.revocation_signaled -eq $true) 'T3 transition revokes the pin + seizes'
Ok ($res.revoked_pin.holder -eq 'PINNER' -and $res.evict_performed -eq $true -and $res.tree_gone -eq $true) 'T3 evicted the pin owner, tree gone'
Ok ($res.gpu_authority_epoch -gt $pinTok) 'T3 seizer authority epoch exceeds the pin epoch'
# result-after-revocation: the old pinner, using its old epoch, is fenced out (cannot publish)
$c = (Run-Res @{ action='check'; resource='gpu-t3'; owner_id='PINNER'; authority_epoch=$pinTok }).env.result
Ok ($c.authority_ok -eq $false) 'T3 revoked pinner (old epoch) -> authority_ok false (late result refused)'

# ---------- T4: adversarial evictor scenarios (only late_evict grants) ----------
Write-Output "T4 adversarial evictor scenarios:"
function Trans([string]$res,[string]$mock){ return (Run-Res @{ action='acquire'; resource=$res; holder='X'; owner_id='X'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result=$mock }).env.result }
$a = Trans 'gpu-t4a' 'timeout'
Ok ($a.acquired -eq $false -and $a.transition_state -eq 'ABORTED' -and $a.reason -eq 'evictor_timeout') 'T4 timeout -> no grant (ABORTED)'
$b = Trans 'gpu-t4b' 'partial_tree_term'
Ok ($b.acquired -eq $false -and $b.tree_gone -eq $false) 'T4 partial_tree_term -> no grant (tree not gone)'
$cc = Trans 'gpu-t4c' 'headroom_never'
Ok ($cc.acquired -eq $false -and $cc.headroom_confirmed -eq $false) 'T4 headroom_never -> no grant'
$d = Trans 'gpu-t4d' 'headroom_fell'
Ok ($d.acquired -eq $false -and $d.headroom_confirmed -eq $false) 'T4 headroom_fell (reached then fell) -> no grant'
$e = Trans 'gpu-t4e' 'cancel_during_prepare'
Ok ($e.acquired -eq $false -and $e.evictor_outcome -eq 'cancelled') 'T4 cancel_during_prepare -> no grant (cancelled)'
$f = Trans 'gpu-t4f' 'late_evict'
Ok ($f.acquired -eq $true -and $f.headroom_confirmed -eq $true) 'T4 late_evict -> grants (we WAITED for stable headroom)'
# headroom observations recorded (WDDM discipline)
Ok (@($f.headroom_observations).Count -ge 1) 'T4 headroom observations recorded'

# ---------- T5: cannot preempt exec / equal-priority pin ----------
Write-Output "T5 non-preemptible residents:"
[void](Run-Res @{ action='acquire'; resource='gpu-t5a'; holder='EXECR'; owner_id='EXECR'; kind='exec'; priority=1 })
$r5a = Trans 'gpu-t5a' 'confirm'
Ok ($r5a.acquired -eq $false -and $r5a.reason -eq 'held_incompatible') 'T5 exec resident -> transition cannot preempt'
[void](Run-Res @{ action='acquire'; resource='gpu-t5b'; holder='PIN5'; owner_id='PIN5'; kind='residency_pin'; priority=5 })
$r5b = Trans 'gpu-t5b' 'confirm'   # transition also priority 5 -> equal, no preempt
Ok ($r5b.acquired -eq $false -and $r5b.reason -eq 'held_incompatible') 'T5 equal-priority pin -> transition cannot preempt (deterministic)'

# ---------- T6: commit-if-epoch-current (superseded during eviction) ----------
Write-Output "T6 commit-if-epoch-current:"
# a command-mode evictor that BUMPS the fence during eviction (simulates a concurrent seizer minting a higher epoch)
$evScript = Join-Path $work 'evictor_bump.ps1'
@'
param([string]$ContextJson)
$ctx = $ContextJson | ConvertFrom-Json
$res = [string]$ctx.resource; $ld = [string]$ctx.lease_dir
$safe = ($res -replace '[^A-Za-z0-9._-]','_'); if ($safe.Length -gt 48){$safe=$safe.Substring(0,48)}
$sha=[System.Security.Cryptography.SHA256]::Create()
try { $h=([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($res)))).Replace('-','').ToLowerInvariant().Substring(0,8) } finally { $sha.Dispose() }
$fp = Join-Path $ld "$safe-$h.fence"
$cur = 0; if (Test-Path $fp) { $cur = [long](Get-Content -Raw $fp) }
[System.IO.File]::WriteAllText($fp, [string]($cur + 5))   # a competing transition minted a higher epoch
[ordered]@{ confirmed=$true; free_vram_mib=99999; evicted=$true; tree_gone=$true; outcome='confirm'; detail='bumped fence to simulate concurrent seize' } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $evScript -Encoding ascii
$r6 = Run-Res @{ action='acquire'; resource='gpu-t6'; holder='SLOW'; owner_id='SLOW'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='command'; evictor_command=$evScript }
$res = $r6.env.result
Ok ($res.acquired -eq $false -and $res.superseded -eq $true -and $res.reason -eq 'superseded_during_transition') 'T6 superseded epoch during eviction -> no grant (fenced out)'
Ok ($res.transition_state -eq 'ABORTED') 'T6 transition ABORTED on supersede'

# ---------- T7: single-winner serialization (transition-in-progress) ----------
Write-Output "T7 single-winner serialization:"
$claim = (Sibling 'gpu-t7' 'txn') + '.claim'
[System.IO.File]::WriteAllText($claim, "txn=other owner=other at=" + ([DateTime]::UtcNow.ToString('o')))
$r7 = Run-Res @{ action='acquire'; resource='gpu-t7'; holder='LATE'; owner_id='LATE'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm' }
Ok ($r7.env.result.acquired -eq $false -and $r7.env.result.reason -eq 'transition_in_progress') 'T7 concurrent transition claim -> loses deterministically (no co-ownership)'
Remove-Item -LiteralPath $claim -Force -ErrorAction SilentlyContinue

# ---------- T8: crash reconcile (PREPARING/DRAINING/STARTING) ----------
Write-Output "T8 crash reconcile:"
$txnPath = Sibling 'gpu-t8' 'txn'
$staleTxn = [ordered]@{ schema='lifeorch.res.lease.txn/0.1'; txn_id='dead'; resource='gpu-t8'; owner_id='DEAD'; holder='DEAD'; state='PREPARING'; authority_epoch=1; prior_epoch=0; started_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')); updated_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')) }
[System.IO.File]::WriteAllText($txnPath, ($staleTxn | ConvertTo-Json -Depth 6))
$r8 = (Run-Res @{ action='check'; resource='gpu-t8'; reconcile=$true }).env.result
Ok ($null -ne $r8.reconciled -and $r8.reconciled.reconciled -eq $true -and $r8.reconciled.from_state -eq 'PREPARING') 'T8 check -Reconcile rolls a stale PREPARING txn to ABORTED'
# a transition auto-reconciles a stale txn on entry
$txnPath2 = Sibling 'gpu-t8b' 'txn'
$staleTxn2 = [ordered]@{ schema='lifeorch.res.lease.txn/0.1'; txn_id='dead2'; resource='gpu-t8b'; owner_id='DEAD'; holder='DEAD'; state='DRAINING'; authority_epoch=1; prior_epoch=0; started_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')); updated_utc=([DateTime]::UtcNow.AddMinutes(-5).ToString('o')) }
[System.IO.File]::WriteAllText($txnPath2, ($staleTxn2 | ConvertTo-Json -Depth 6))
$r8b = (Run-Res @{ action='acquire'; resource='gpu-t8b'; holder='NEW'; owner_id='NEW'; priority=5; transition=$true; required_vram_mib=6700; evictor_mode='mock'; mock_evictor_result='confirm' }).env.result
Ok ($null -ne $r8b.reconciled -and $r8b.reconciled.reconciled -eq $true -and $r8b.acquired -eq $true) 'T8 transition auto-reconciles a stale DRAINING txn then grants'

# ---------- T9: expiry-during-exec ----------
Write-Output "T9 expiry during exec:"
$ex = (Run-Res @{ action='acquire'; resource='gpu-t9'; holder='E'; owner_id='E'; ttl_seconds=1; resident_generation='g9' }).env.result
$exTok = [long]$ex.fencing_token
Start-Sleep -Seconds 2
$c = (Run-Res @{ action='check'; resource='gpu-t9'; owner_id='E'; resident_generation='g9'; authority_epoch=$exTok }).env.result
Ok ($c.stale -eq $true -and $c.authority_ok -eq $false) 'T9 an exec lease that expired mid-task -> authority_ok false (lost authority)'

# ---------- T10: byte-identical / R1a-unchanged guards ----------
Write-Output "T10 additive/default-off guards:"
# a PLAIN acquire (no engaged surface) must NOT carry ANY v0.2/v0.3 fields
$r10 = (Run-Res @{ action='acquire'; resource='plain10'; holder='P' }).env.result
$plainClean = -not (Has $r10 'fencing_token') -and -not (Has $r10 'gpu_authority_epoch') -and -not (Has $r10 'owner_id') -and -not (Has $r10 'transition') -and -not (Has $r10 'lease_kind')
Ok $plainClean 'T10 plain acquire is byte-identical (no v0.2/v0.3 fields)'
# an R1a-engaged acquire (kind only) carries fencing_token but NOT the v0.3 three-identity fields
$r10b = (Run-Res @{ action='acquire'; resource='r1a10'; holder='P'; kind='exec' }).env.result
$r1aClean = (Has $r10b 'fencing_token') -and -not (Has $r10b 'gpu_authority_epoch') -and -not (Has $r10b 'owner_id') -and -not (Has $r10b 'exec_lease_id')
Ok $r1aClean 'T10 R1a-engaged acquire unchanged (fencing_token, no v0.3 identity fields)'

Write-Output ""
Write-Output ("==== R1b RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
