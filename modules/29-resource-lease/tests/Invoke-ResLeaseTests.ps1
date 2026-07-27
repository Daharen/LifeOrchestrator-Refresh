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

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
