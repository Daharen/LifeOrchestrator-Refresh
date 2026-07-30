#requires -Version 7.0
<#
  Invoke-ResLeaseTests.ps1 -- drives the REAL Invoke-ResLease.ps1. Deterministic + OS-portable (temp lease dir),
  ASCII-only. Runs off-GPU on cloud pwsh (pre-ship gate) and unchanged live via the executor. Exercises the
  atomic acquire, TTL expiry + race-safe stale reclaim, blocking acquire, and -- the money test -- N-way
  cross-process concurrency (exactly one winner). Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh'),
    [string]$SkillPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-ResLease.ps1'),
    [string]$WrapperPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m29-reslease-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$leaseDir = Join-Path $work 'leases'
$artRoot = Join-Path $work 'art'
New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# Synchronous run through -InputsJson (exercises the InputsJson merge path). Named -LeaseDir/-ArtifactRoot win.
function Run-Res([hashtable]$inputs) {
    $ij = ($inputs | ConvertTo-Json -Compress -Depth 8)
    $errF = Join-Path $work ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $out = & $PwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SkillPath -InputsJson $ij -LeaseDir $leaseDir -ArtifactRoot $artRoot 2> $errF
    $txt = ($out | Out-String).Trim()
    $e = $null; try { $e = $txt | ConvertFrom-Json } catch { }
    return @{ env=$e; raw=$txt; err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}
# Async process (named args) -- for real cross-process contention. Returns the started Process.
function Start-ResProc([string[]]$rest) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PwshExe
    foreach ($a in @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$SkillPath) + $rest) { [void]$psi.ArgumentList.Add([string]$a) }
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}
function Read-ProcEnv([System.Diagnostics.Process]$p) {
    $out = $p.StandardOutput.ReadToEnd()   # drains + blocks until the child's stdout closes (exit)
    $p.WaitForExit()
    $e = $null; try { $e = ($out.Trim() | ConvertFrom-Json) } catch { }
    return $e
}
function Acq-Args([string]$res,[string]$h,[int]$ttl,[double]$wait) {
    return @('-Action','acquire','-Resource',$res,'-Holder',$h,'-TtlSeconds',[string]$ttl,'-WaitSeconds',[string]$wait,'-LeaseDir',$leaseDir,'-ArtifactRoot',$artRoot)
}

Write-Output "==== res.lease harness ===="
Write-Output ("skill=" + $SkillPath)
Write-Output ""

# --- S0: manifest sanity ---
$manifest = $null
try { $manifest = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SkillPath) 'skill.json') -Raw | ConvertFrom-Json } catch { }
Write-Output "S0 manifest:"
Ok ($null -ne $manifest -and $manifest.skill_id -eq 'res.lease') 'S0 skill_id res.lease'
Ok ($null -ne $manifest -and $manifest.parallel_safe -eq $true -and $manifest.determinism -eq 'deterministic') 'S0 parallel_safe true + deterministic'

# --- S1: acquire a free resource ---
$r = Run-Res @{ action='acquire'; resource='r1'; holder='A'; ttl_seconds=60 }
$e = $r.env; $res = if ($e){$e.result}else{$null}
Write-Output "S1 acquire-free:"
Ok ($null -ne $e -and $e.schema -eq 'lifeorch.skill.result/0.1' -and $e.status -eq 'ok') 'S1 envelope ok'
Ok ($null -ne $res -and $res.acquired -eq $true -and -not [string]::IsNullOrWhiteSpace($res.lease_id)) 'S1 acquired with a lease_id'
Ok ($null -ne $e -and $null -eq $e.confidence -and @($e.model_provenance).Count -eq 0) 'S1 deterministic (null confidence, no provenance)'
$leaseId1 = if ($res){[string]$res.lease_id}else{''}

# --- S2: second acquire (non-blocking) is busy ---
$r = Run-Res @{ action='acquire'; resource='r1'; holder='B'; ttl_seconds=60; wait_seconds=0 }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S2 second-acquire-busy:"
Ok ($null -ne $res -and $res.acquired -eq $false) 'S2 second acquirer does not get it'
Ok ($null -ne $res -and $res.held_by -eq 'A' -and $r.env.status -eq 'ok') 'S2 reports held_by=A, status ok (not an error)'

# --- S3: wrong lease_id release is refused; correct one works; then re-acquire ---
$r = Run-Res @{ action='release'; resource='r1'; lease_id='not-the-right-id' }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S3 release-guard + re-acquire:"
Ok ($null -ne $res -and $res.released -eq $false -and $res.reason -eq 'lease_mismatch') 'S3 wrong lease_id refused (lease_mismatch)'
$r = Run-Res @{ action='release'; resource='r1'; lease_id=$leaseId1 }
Ok ($null -ne $r.env.result -and $r.env.result.released -eq $true) 'S3 correct lease_id releases'
$r = Run-Res @{ action='acquire'; resource='r1'; holder='B'; ttl_seconds=60 }
Ok ($null -ne $r.env.result -and $r.env.result.acquired -eq $true) 'S3 resource is re-acquirable after release'
$leaseId1b = if ($r.env.result){[string]$r.env.result.lease_id}else{''}

# --- S4: renew extends; wrong lease_id renew refused ---
$r = Run-Res @{ action='status'; resource='r1' }
$expBefore = if ($r.env.result){[string]$r.env.result.expires_at_utc}else{''}
Start-Sleep -Milliseconds 1100
$r = Run-Res @{ action='renew'; resource='r1'; lease_id=$leaseId1b; ttl_seconds=120 }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S4 renew:"
Ok ($null -ne $res -and $res.renewed -eq $true -and $res.renew_count -eq 1) 'S4 renew succeeds (renew_count=1)'
Ok ($null -ne $res -and ([DateTime]$res.expires_at_utc) -gt ([DateTime]$expBefore)) 'S4 renew extends expiry'
$r = Run-Res @{ action='renew'; resource='r1'; lease_id='bogus' }
Ok ($null -ne $r.env.result -and $r.env.result.renewed -eq $false -and $r.env.result.reason -eq 'lease_lost') 'S4 wrong lease_id renew refused (lease_lost)'

# --- S5: status + list reflect reality ---
$r = Run-Res @{ action='status'; resource='r1' }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S5 status/list:"
Ok ($null -ne $res -and $res.exists -eq $true -and $res.held -eq $true -and $res.holder -eq 'B') 'S5 status: held by B'
Ok ($null -ne $res -and $res.stale -eq $false -and $res.seconds_remaining -gt 0) 'S5 status: not stale, time remaining'
$r = Run-Res @{ action='status'; resource='does-not-exist' }
Ok ($null -ne $r.env.result -and $r.env.result.exists -eq $false -and $r.env.result.held -eq $false) 'S5 status of a free resource: exists=false'
$r = Run-Res @{ action='list' }
$res = if ($r.env){$r.env.result}else{$null}
Ok ($null -ne $res -and $res.count -ge 1 -and (@($res.leases | Where-Object { $_.resource -eq 'r1' }).Count -eq 1)) 'S5 list includes r1'

# --- S6: TTL expiry -> race-safe stale reclaim ---
$r = Run-Res @{ action='acquire'; resource='ephemeral'; holder='short'; ttl_seconds=1 }
Ok ($null -ne $r.env.result -and $r.env.result.acquired -eq $true) 'S6 acquire with ttl=1'
Start-Sleep -Seconds 2
$r = Run-Res @{ action='status'; resource='ephemeral' }
Ok ($null -ne $r.env.result -and $r.env.result.stale -eq $true) 'S6 lease is stale after ttl'
$r = Run-Res @{ action='acquire'; resource='ephemeral'; holder='next'; ttl_seconds=60; wait_seconds=0 }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S6 stale-reclaim:"
Ok ($null -ne $res -and $res.acquired -eq $true -and $res.reclaimed_stale -eq $true) 'S6 next acquirer reclaims the stale lease'
Ok ($null -ne $res -and $res.holder -eq 'next') 'S6 reclaimer now holds it'

# --- S7: same-holder re-attach (live lease, same holder) ---
$r = Run-Res @{ action='acquire'; resource='reattach'; holder='sticky'; ttl_seconds=60 }
$lid = if ($r.env.result){[string]$r.env.result.lease_id}else{''}
$r = Run-Res @{ action='acquire'; resource='reattach'; holder='sticky'; ttl_seconds=60 }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S7 same-holder re-attach:"
Ok ($null -ne $res -and $res.acquired -eq $true -and $res.already_held -eq $true) 'S7 re-acquire by same holder re-attaches'
Ok ($null -ne $res -and $res.lease_id -eq $lid) 'S7 re-attach returns the original lease_id'

# --- S8: blocking acquire unblocks when the holder releases ---
$r = Run-Res @{ action='acquire'; resource='blk'; holder='H1'; ttl_seconds=60 }
$blkLid = if ($r.env.result){[string]$r.env.result.lease_id}else{''}
Write-Output "S8 blocking-acquire:"
Ok (-not [string]::IsNullOrWhiteSpace($blkLid)) 'S8 H1 holds blk'
$bg = Start-ResProc (Acq-Args 'blk' 'H2' 60 12)    # H2 waits up to 12s
Start-Sleep -Milliseconds 3000                     # hold well past a slow (Windows) child cold-start so H2 is blocking
$rel = Run-Res @{ action='release'; resource='blk'; lease_id=$blkLid }
Ok ($null -ne $rel.env.result -and $rel.env.result.released -eq $true) 'S8 H1 releases blk'
$bgEnv = Read-ProcEnv $bg
$bgRes = if ($bgEnv){$bgEnv.result}else{$null}
Ok ($null -ne $bgRes -and $bgRes.acquired -eq $true -and $bgRes.holder -eq 'H2') 'S8 waiting H2 acquires after release'
Ok ($null -ne $bgRes -and $bgRes.waited_ms -ge 400) 'S8 H2 actually blocked (waited_ms>=400)'

# --- S9: N-way cross-process concurrency -> exactly one winner ---
Write-Output "S9 concurrency (exactly one winner):"
$N = 6
$procs = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le $N; $i++) { $procs.Add((Start-ResProc (Acq-Args 'contended' "w$i" 60 0))) }   # launch all, THEN read
$winners = 0; $losers = 0; $bad = 0
foreach ($p in $procs) {
    $env2 = Read-ProcEnv $p
    if ($null -eq $env2 -or $null -eq $env2.result) { $bad++; continue }
    if ($env2.result.acquired -eq $true) { $winners++ } elseif ($env2.result.acquired -eq $false) { $losers++ } else { $bad++ }
}
Ok ($bad -eq 0) "S9 all $N acquirers returned a valid envelope"
Ok ($winners -eq 1) "S9 EXACTLY ONE winner (got $winners)"
Ok ($losers -eq ($N - 1)) "S9 the other $($N-1) are cleanly denied (got $losers)"
$r = Run-Res @{ action='status'; resource='contended' }
Ok ($null -ne $r.env.result -and $r.env.result.held -eq $true) 'S9 the resource ends up held by exactly the one winner'

# --- S9b: N processes racing to RECLAIM one stale lease -> exactly one winner (the reclaim CAS) ---
Write-Output "S9b concurrent stale-reclaim (exactly one reclaimer):"
$r = Run-Res @{ action='acquire'; resource='staled'; holder='dead'; ttl_seconds=1 }
Ok ($null -ne $r.env.result -and $r.env.result.acquired -eq $true) 'S9b seed a lease with ttl=1'
Start-Sleep -Seconds 2   # let it go stale
$M = 6
$rprocs = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le $M; $i++) { $rprocs.Add((Start-ResProc (Acq-Args 'staled' "rec$i" 60 0))) }
$rwin = 0; $rlose = 0; $rbad = 0
foreach ($p in $rprocs) {
    $env3 = Read-ProcEnv $p
    if ($null -eq $env3 -or $null -eq $env3.result) { $rbad++; continue }
    if ($env3.result.acquired -eq $true) { $rwin++ } elseif ($env3.result.acquired -eq $false) { $rlose++ } else { $rbad++ }
}
Ok ($rbad -eq 0) "S9b all $M reclaimers returned a valid envelope"
Ok ($rwin -eq 1) "S9b EXACTLY ONE reclaimer wins the stale lease (got $rwin)"
Ok ($rlose -eq ($M - 1)) "S9b the other $($M-1) are cleanly denied (got $rlose)"

# --- S10: error paths ---
$r = Run-Res @{ resource='x' }                       # no action
Write-Output "S10 error-paths:"
Ok ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_parameter') 'S10 no action -> missing_parameter'
$r = Run-Res @{ action='frobnicate'; resource='x' }
Ok ($null -ne $r.env -and $r.env.error.code -eq 'invalid_action') 'S10 bad action -> invalid_action'
$r = Run-Res @{ action='acquire' }                   # no resource
Ok ($null -ne $r.env -and $r.env.error.code -eq 'missing_parameter') 'S10 acquire without resource -> missing_parameter'

# --- S11: Module 1 wrapper ---
if (-not [string]::IsNullOrWhiteSpace($WrapperPath) -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path -Parent $SkillPath
    $ij = [ordered]@{ action='acquire'; resource='wrapped'; holder='wrap'; ttl_seconds=30; lease_dir=$leaseDir } | ConvertTo-Json -Compress
    $wout = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WrapperPath -SkillDir $skillDir -InputsJson $ij -PwshPath $PwshExe 2> (Join-Path $work 'err-wrap.txt')
    $wcode = $LASTEXITCODE
    $rep = $null; try { $rep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
    Write-Output "S11 Module-1 wrapper:"
    Ok ($null -ne $rep -and $rep.manifest_valid -eq $true) 'S11 manifest valid'
    Ok ($null -ne $rep -and $rep.envelope_valid -eq $true -and $rep.exit_code -eq 0 -and $wcode -eq 0) 'S11 envelope valid + exit 0'
    Ok ($null -ne $rep -and $rep.envelope.result.acquired -eq $true) 'S11 wrapped acquire succeeded'
} else { Write-Output "S11 Module-1 wrapper: SKIPPED (no -WrapperPath)" }

# ============================================================================================
# v0.2 additive surface: fencing token (1), lease kinds + revocation (13), prepared/evict-before-
# grant (2/15), lock-order-inversion rejection (14). Drives the REAL skill; evictor MOCKED (+ a
# command-mode fixture for the R1b seam). ASCII-only; runs on the cloud gate + unchanged live.
# ============================================================================================

# Synchronous run through NAMED args (so -Kind/-Priority/-FencingToken/-RequiredVramMiB engage the new surface).
function Run-ResArgs([string[]]$rest) {
    $errF = Join-Path $work ("erra-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $argv = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$SkillPath) + $rest + @('-LeaseDir',$leaseDir,'-ArtifactRoot',$artRoot)
    $out = & $PwshExe @argv 2> $errF
    $txt = ($out | Out-String).Trim()
    $e = $null; try { $e = $txt | ConvertFrom-Json } catch { }
    return @{ env=$e; raw=$txt; err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}
function Acq-ArgsK([string]$res,[string]$h,[int]$ttl,[double]$wait,[string]$kind) {
    return @('-Action','acquire','-Resource',$res,'-Holder',$h,'-TtlSeconds',[string]$ttl,'-WaitSeconds',[string]$wait,'-Kind',$kind,'-LeaseDir',$leaseDir,'-ArtifactRoot',$artRoot)
}
function Rel([string]$res,[string]$h) { Run-ResArgs @('-Action','release','-Resource',$res,'-Holder',$h) | Out-Null }

# --- S12: a plain acquire (no new params) is BYTE-IDENTICAL to v0.1 -- the dev.ship git / plain gpu / doc paths ---
Write-Output "S12 byte-identical default path:"
$r = Run-Res @{ action='acquire'; resource='bid1'; holder='A'; ttl_seconds=60 }
$res = if ($r.env){$r.env.result}else{$null}
$legacyKeys = @('action','resource','acquired','lease_id','holder','expires_at_utc','ttl_seconds','waited_ms','reclaimed_stale','already_held','held_by','held_expires_at_utc','lease_dir')
$gotKeys = @(); if ($null -ne $res) { $gotKeys = @($res.PSObject.Properties.Name) }
Ok ($null -ne $res -and $res.acquired -eq $true) 'S12 default acquire succeeds'
Ok (($gotKeys -join ',') -eq ($legacyKeys -join ',')) 'S12 result carries EXACTLY the v0.1 keys in order (no fencing fields)'
Ok (-not (Has $res 'fencing_token')) 'S12 no fencing_token on a plain acquire'
Run-Res @{ action='release'; resource='bid1'; holder='A' } | Out-Null
$rg = Run-Res @{ action='acquire'; resource='gpu'; holder='PG'; ttl_seconds=60 }
Ok ($rg.env.result.acquired -eq $true -and -not (Has $rg.env.result 'fencing_token')) 'S12 plain gpu acquire is byte-identical'
Run-Res @{ action='release'; resource='gpu'; holder='PG' } | Out-Null
$rd = Run-Res @{ action='acquire'; resource='doc:CURRENT_STATE.md'; holder='PD'; ttl_seconds=60 }
Ok ($rd.env.result.acquired -eq $true -and -not (Has $rd.env.result 'fencing_token')) 'S12 plain doc:<path> acquire is byte-identical'
Run-Res @{ action='release'; resource='doc:CURRENT_STATE.md'; holder='PD' } | Out-Null

# --- S13: fencing token minted + monotonic; re-attach + renew keep it; strictly-greater after release + stale reclaim ---
Write-Output "S13 fencing token monotonicity:"
$r = Run-ResArgs @('-Action','acquire','-Resource','fen1','-Holder','A','-Kind','exec','-TtlSeconds','60')
$tokA = if ($r.env){[long]$r.env.result.fencing_token}else{-1}
$lidA = if ($r.env){[string]$r.env.result.lease_id}else{''}
Ok ($tokA -ge 1) 'S13 fresh grant mints a fencing_token >= 1'
$r2 = Run-ResArgs @('-Action','acquire','-Resource','fen1','-Holder','A','-Kind','exec','-TtlSeconds','60')
Ok ($null -ne $r2.env -and $r2.env.result.already_held -eq $true -and [long]$r2.env.result.fencing_token -eq $tokA) 'S13 same-holder re-attach keeps the SAME token'
$r3 = Run-ResArgs @('-Action','renew','-Resource','fen1','-LeaseId',$lidA,'-Kind','exec','-TtlSeconds','60')
Ok ($null -ne $r3.env -and $r3.env.result.renewed -eq $true -and [long]$r3.env.result.fencing_token -eq $tokA) 'S13 renew keeps the SAME token'
Rel 'fen1' 'A'
$r4 = Run-ResArgs @('-Action','acquire','-Resource','fen1','-Holder','B','-Kind','exec','-TtlSeconds','60')
$tokB = if ($r4.env){[long]$r4.env.result.fencing_token}else{-1}
Ok ($tokB -gt $tokA) 'S13 re-acquire after release is STRICTLY GREATER (monotonic across lease deletion)'
Rel 'fen1' 'B'
$r5 = Run-ResArgs @('-Action','acquire','-Resource','fen1','-Holder','C','-Kind','exec','-TtlSeconds','1')
$tokC = if ($r5.env){[long]$r5.env.result.fencing_token}else{-1}
Start-Sleep -Seconds 2
$r6 = Run-ResArgs @('-Action','acquire','-Resource','fen1','-Holder','D','-Kind','exec','-TtlSeconds','60')
Ok ($null -ne $r6.env -and $r6.env.result.reclaimed_stale -eq $true -and [long]$r6.env.result.fencing_token -gt $tokC) 'S13 STRICTLY GREATER token after a stale reclaim'
Rel 'fen1' 'D'

# --- S14: N-way cross-process concurrency WITH fencing -> exactly one winner AND its token exceeds the prior holder's ---
Write-Output "S14 concurrent fencing (one winner, token advances):"
$seed = Run-ResArgs @('-Action','acquire','-Resource','fenconc','-Holder','seed','-Kind','exec','-TtlSeconds','60')
$seedTok = if ($seed.env){[long]$seed.env.result.fencing_token}else{-1}
Rel 'fenconc' 'seed'
$N = 6
$procs = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le $N; $i++) { $procs.Add((Start-ResProc (Acq-ArgsK 'fenconc' "fw$i" 60 0 'exec'))) }
$win = 0; $winTok = -1; $bad = 0
foreach ($p in $procs) {
    $e2 = Read-ProcEnv $p
    if ($null -eq $e2 -or $null -eq $e2.result) { $bad++; continue }
    if ($e2.result.acquired -eq $true) { $win++; $winTok = [long]$e2.result.fencing_token } elseif ($e2.result.acquired -eq $false) { } else { $bad++ }
}
Ok ($bad -eq 0) "S14 all $N fenced acquirers returned a valid envelope"
Ok ($win -eq 1) "S14 EXACTLY ONE winner (got $win)"
Ok ($winTok -gt $seedTok) "S14 winner token ($winTok) exceeds the prior holder's ($seedTok)"
$w = Run-ResArgs @('-Action','check','-Resource','fenconc')
if ($null -ne $w.env) { Rel 'fenconc' ([string]$w.env.result.holder) }

# --- S15: CAS -- a stale -FencingToken is FENCED OUT of check/renew/release; the current token works ---
Write-Output "S15 fencing CAS (fence_stale):"
$r = Run-ResArgs @('-Action','acquire','-Resource','cas','-Holder','C','-Kind','exec','-TtlSeconds','120')
$casLid = if ($r.env){[string]$r.env.result.lease_id}else{''}
$casTok = if ($r.env){[long]$r.env.result.fencing_token}else{-1}
$c = Run-ResArgs @('-Action','check','-Resource','cas','-FencingToken','999999')
Ok ($null -ne $c.env -and $c.env.result.token_current -eq $false -and $c.env.result.fence_status -eq 'fence_stale') 'S15 check rejects a stale token (fence_stale)'
$rn = Run-ResArgs @('-Action','renew','-Resource','cas','-LeaseId',$casLid,'-FencingToken','999999')
Ok ($null -ne $rn.env -and $rn.env.result.renewed -eq $false -and $rn.env.result.reason -eq 'fence_stale') 'S15 renew rejects a stale token'
$rl = Run-ResArgs @('-Action','release','-Resource','cas','-LeaseId',$casLid,'-FencingToken','999999')
Ok ($null -ne $rl.env -and $rl.env.result.released -eq $false -and $rl.env.result.reason -eq 'fence_stale') 'S15 release rejects a stale token'
$c2 = Run-ResArgs @('-Action','check','-Resource','cas','-FencingToken',[string]$casTok)
Ok ($null -ne $c2.env -and $c2.env.result.token_current -eq $true -and $c2.env.result.fence_status -eq 'current') 'S15 check accepts the CURRENT token'
$rl2 = Run-ResArgs @('-Action','release','-Resource','cas','-LeaseId',$casLid,'-FencingToken',[string]$casTok)
Ok ($null -ne $rl2.env -and $rl2.env.result.released -eq $true) 'S15 release with the current token succeeds'

# --- S16: exec vs residency_pin are distinct kinds, independently held ---
Write-Output "S16 lease kinds:"
$e1 = Run-ResArgs @('-Action','acquire','-Resource','ex1','-Holder','X','-Kind','exec','-TtlSeconds','60')
Ok ($null -ne $e1.env -and $e1.env.result.lease_kind -eq 'exec' -and $e1.env.result.revocable -eq $false) 'S16 exec kind (revocable=false)'
$p1 = Run-ResArgs @('-Action','acquire','-Resource','pin1','-Holder','Y','-Kind','residency_pin','-Priority','2','-TtlSeconds','60')
Ok ($null -ne $p1.env -and $p1.env.result.lease_kind -eq 'residency_pin' -and $p1.env.result.revocable -eq $true) 'S16 residency_pin kind (revocable=true)'
$se = Run-Res @{ action='status'; resource='ex1' }; $sp = Run-Res @{ action='status'; resource='pin1' }
Ok ($null -ne $se.env -and $null -ne $sp.env -and $se.env.result.held -eq $true -and $sp.env.result.held -eq $true) 'S16 exec + pin independently held'
Rel 'ex1' 'X'; Rel 'pin1' 'Y'

# --- S17: a higher-priority acquire REVOKES a lower-priority pin (revoked_by + fencing set); holder learns it; non-revocable pin STOP ---
Write-Output "S17 pin revocation:"
$pp = Run-ResArgs @('-Action','acquire','-Resource','gpu','-Holder','P','-Kind','residency_pin','-Priority','1','-TtlSeconds','120')
$pPrior = if ($pp.env){[long]$pp.env.result.fencing_token}else{-1}
$q = Run-ResArgs @('-Action','acquire','-Resource','gpu','-Holder','Q','-Priority','5','-WaitSeconds','0')
Ok ($null -ne $q.env -and $q.env.result.revocation_signaled -eq $true -and $q.env.result.revoked_pin.holder -eq 'P') 'S17 higher-priority acquire signals revocation of the lower-priority pin'
$chk = Run-ResArgs @('-Action','check','-Resource','gpu')
Ok ($null -ne $chk.env -and $chk.env.result.fence_status -eq 'revoked' -and $null -ne $chk.env.result.revoked_by -and [long]$chk.env.result.revoked_by.fencing_token -gt $pPrior) 'S17 pin carries revoked_by + a fencing token greater than the pin token'
$pLid = if ($chk.env){[string]$chk.env.result.lease_id}else{''}
$pr = Run-ResArgs @('-Action','renew','-Resource','gpu','-LeaseId',$pLid)
Ok ($null -ne $pr.env -and $pr.env.result.renewed -eq $false -and $pr.env.result.reason -eq 'revoked') 'S17 the revoked pin holder learns it LOST AUTHORITY on renew'
Rel 'gpu' 'P'
$stop = Run-Res @{ action='acquire'; resource='npX'; holder='Z'; kind='residency_pin'; revocable=$false }
Ok ($null -ne $stop.env -and $stop.env.status -eq 'error' -and $stop.env.error.code -eq 'non_revocable_pin_forbidden') 'S17 a non-revocable pin is a hard STOP'

# --- S18: prepared / evict-before-grant handshake -- mock confirm / needs_evict / timeout + the command-mode seam ---
Write-Output "S18 prepared handoff (evictor seam):"
$pc = Run-ResArgs @('-Action','acquire','-Resource','pgpu1','-Holder','G','-RequiredVramMiB','6700','-Priority','5','-EvictorMode','mock','-MockEvictorResult','confirm','-MockFreeVramMiB','9000','-TtlSeconds','60')
Ok ($null -ne $pc.env -and $pc.env.result.acquired -eq $true -and $pc.env.result.prepared -eq $true -and $pc.env.result.headroom_confirmed -eq $true) 'S18 prepared(confirm) grants with headroom confirmed'
Rel 'pgpu1' 'G'
Run-ResArgs @('-Action','acquire','-Resource','pgpu2','-Holder','PP','-Kind','residency_pin','-Priority','1','-TtlSeconds','120') | Out-Null
$pe = Run-ResArgs @('-Action','acquire','-Resource','pgpu2','-Holder','HH','-RequiredVramMiB','6700','-Priority','9','-EvictorMode','mock','-MockEvictorResult','needs_evict','-MockFreeVramMiB','9000','-TtlSeconds','60')
Ok ($null -ne $pe.env -and $pe.env.result.acquired -eq $true -and $pe.env.result.evict_performed -eq $true -and $pe.env.result.revoked_pin.holder -eq 'PP') 'S18 prepared(needs_evict) revokes + evicts + seizes the pin'
Ok ($null -ne $pe.env -and [long]$pe.env.result.fencing_token -gt [long]$pe.env.result.revoked_pin.prior_fencing_token) 'S18 the seizer token exceeds the evicted pin token'
Rel 'pgpu2' 'HH'
$pt = Run-ResArgs @('-Action','acquire','-Resource','pgpu3','-Holder','TT','-RequiredVramMiB','6700','-EvictorMode','mock','-MockEvictorResult','timeout')
Ok ($null -ne $pt.env -and $pt.env.result.acquired -eq $false -and $pt.env.result.prepared -eq $false -and $pt.env.result.reason -eq 'headroom_timeout') 'S18 prepared(timeout) does NOT grant'
$evFix = Join-Path $work 'evictor-fixture.ps1'
$evBody = @'
param([string]$ContextJson)
$ctx = $ContextJson | ConvertFrom-Json
$need = [int]$ctx.required_vram_mib + [int]$ctx.target_headroom_mib
[pscustomobject]@{ confirmed=$true; free_vram_mib=($need+100); evicted=($ctx.state -eq 'occupied'); outcome='command_confirmed'; detail='fixture evictor' } | ConvertTo-Json -Compress
'@
Set-Content -LiteralPath $evFix -Value $evBody -Encoding ascii
$pcmd = Run-ResArgs @('-Action','acquire','-Resource','pgpu4','-Holder','CC','-RequiredVramMiB','6700','-Priority','5','-EvictorMode','command','-EvictorCommand',$evFix,'-TtlSeconds','60')
Ok ($null -ne $pcmd.env -and $pcmd.env.result.acquired -eq $true -and $pcmd.env.result.evictor_mode -eq 'command' -and $pcmd.env.result.headroom_confirmed -eq $true) 'S18 the command-mode evictor SEAM confirms + grants (R1b integration point)'
Rel 'pgpu4' 'CC'

# --- S19: lock-order-inversion rejection (finding 14) + -AllowLockOrder override; a clean git acquire stays byte-identical ---
Write-Output "S19 lock-order inversion:"
Run-ResArgs @('-Action','acquire','-Resource','gpu','-Holder','LW','-Kind','exec','-TtlSeconds','120') | Out-Null
$lv = Run-ResArgs @('-Action','acquire','-Resource','git','-Holder','LW','-WaitSeconds','0')
Ok ($null -ne $lv.env -and $lv.env.status -eq 'error' -and $lv.env.error.code -eq 'lock_order_violation') 'S19 holding gpu then acquiring git is rejected (lock_order_violation)'
$lo = Run-ResArgs @('-Action','acquire','-Resource','git','-Holder','LW','-AllowLockOrder','-LockOrderReason','commit then release')
Ok ($null -ne $lo.env -and $lo.env.result.acquired -eq $true -and $null -ne $lo.env.result.lock_order_override -and $lo.env.result.lock_order_override.reason -eq 'commit then release') 'S19 -AllowLockOrder overrides with a recorded reason'
Rel 'git' 'LW'; Rel 'gpu' 'LW'
$clean = Run-Res @{ action='acquire'; resource='git'; holder='FRESH'; wait_seconds=0 }
Ok ($null -ne $clean.env -and $clean.env.result.acquired -eq $true -and -not (Has $clean.env.result 'fencing_token')) 'S19 a plain git acquire (not holding gpu) stays byte-identical (dev.ship path)'
Run-Res @{ action='release'; resource='git'; holder='FRESH' } | Out-Null

# --- S20: the check action on a free resource; engaged status surfaces fencing fields; plain status stays byte-identical ---
Write-Output "S20 check + engaged status:"
$cf = Run-ResArgs @('-Action','check','-Resource','nolease-xyz')
Ok ($null -ne $cf.env -and $cf.env.result.exists -eq $false -and $cf.env.result.fence_status -eq 'not_held') 'S20 check on a free resource: not_held'
Run-ResArgs @('-Action','acquire','-Resource','stq','-Holder','SS','-Kind','exec','-TtlSeconds','60') | Out-Null
$ss = Run-ResArgs @('-Action','status','-Resource','stq','-Kind','exec')
Ok ($null -ne $ss.env -and (Has $ss.env.result 'fencing_token') -and [long]$ss.env.result.fencing_token -ge 1 -and $ss.env.result.lease_kind -eq 'exec') 'S20 engaged status surfaces the fencing fields'
$spn = Run-Res @{ action='status'; resource='stq' }
Ok ($null -ne $spn.env -and -not (Has $spn.env.result 'fencing_token')) 'S20 a plain status stays byte-identical (no fencing fields)'
Rel 'stq' 'SS'

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
