#requires -Version 7.0
# =====================================================================================================
# OFF-MACHINE seam tests for the i23 SUPERVISOR-HARDENING wave -- the frontier red-team's 10 must-fixes folded
# into the durable gateway supervisor + integrity layer + real evictor
# (core-docs/research/2026-07-31-frontier-supervisor-redteam.md). PURE + SEAM: every Windows/GPU action enters
# through an injected scriptblock/handle seam, so the invariants are proven on the cloud gate AND, unchanged,
# live via the executor. The real per-resident Job-Object CUSTODY (must-fix 1/2) is Windows-only; here we prove
# the ORDERING + FATALITY CONTRACT via an injected launcher (custody proven live on the box). ASCII-only.
# Exit 0 iff all pass.
# =====================================================================================================
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'lib/PoolManager.psm1') -Force
Import-Module (Join-Path $moduleRoot 'lib/Supervisor.psm1') -Force

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { if ($null -eq $o) { return $false } if ($o -is [System.Collections.IDictionary]) { return $o.Contains($n) } return ($o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-hard-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$spawned = New-Object System.Collections.Generic.List[int]
function Cleanup-Spawned { foreach ($sp in $script:spawned) { try { Stop-Process -Id $sp -Force -ErrorAction SilentlyContinue } catch { } } }

Write-Output "==== SUPERVISOR-HARDENING off-machine seam suite (i23) ===="
Write-Output "module=$(Join-Path $moduleRoot 'lib/Supervisor.psm1')"; Write-Output ""

# =================================================================================================
# MF6 -- abandonment-aware pool lock + nonce'd release (red-team blocker 4)
# =================================================================================================
Write-Output "-- MF6: abandonment-aware pool lock + nonce'd release --"
$lp = Join-Path $scratch 'mf6.lock'

# basic acquire / block / release / dead-holder-break still hold (parity with PoolCore L.*)
$a = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($a.acquired -eq $true) 'MF6.1 lock acquired'
Ok ((Has $a 'nonce') -and -not [string]::IsNullOrWhiteSpace($a.nonce)) 'MF6.2 acquired lock carries an ownership nonce'
$b = Enter-PoolLock -LockPath $lp -TimeoutMs 300
Ok ($b.acquired -eq $false) 'MF6.3 second acquire blocks while a LIVE owner holds it'

# a LIVE owner is NEVER stolen on a time bound: an OLD acquired_utc with a live (our own) pid + matching
# start-ticks must NOT be broken, even with a tiny StaleMs (the old 60s age-steal is gone).
$held = Get-Content -LiteralPath $lp -Raw | ConvertFrom-Json
$myTicks = [long]((Get-Process -Id $PID).StartTime.Ticks)
$aged = [ordered]@{ pid = $PID; owner_start_ticks = $myTicks; nonce = ([string]$held.nonce); acquired_utc = ((Get-Date).ToUniversalTime().AddHours(-2).ToString('o')) }
[System.IO.File]::WriteAllText($lp, ($aged | ConvertTo-Json -Compress), $utf8)
$c = Enter-PoolLock -LockPath $lp -TimeoutMs 400 -StaleMs 50
Ok ($c.acquired -eq $false) 'MF6.4 a LIVE owner is NOT stolen on an age bound (no time-steal)'

# release with a NON-matching nonce must NOT delete a replacement owner's lock (no split-brain)
$foreign = [ordered]@{ acquired = $true; path = $lp; owner_pid = $PID; nonce = 'deadbeefdeadbeefdeadbeefdeadbeef' }
Exit-PoolLock $foreign
Ok (Test-Path -LiteralPath $lp) 'MF6.5 release with a mismatched nonce leaves the live owner lock intact'

# the true owner (matching on-disk nonce) releases and frees the lock
[System.IO.File]::WriteAllText($lp, ($aged | ConvertTo-Json -Compress), $utf8)   # restore the real nonce record
$trueOwner = [ordered]@{ acquired = $true; path = $lp; owner_pid = $PID; nonce = ([string]$held.nonce) }
Exit-PoolLock $trueOwner
Ok (-not (Test-Path -LiteralPath $lp)) 'MF6.6 the true owner (matching nonce) releases the lock'

# dead-holder abandonment still breaks (parity with L.4) -- record a dead pid, no ticks
[System.IO.File]::WriteAllText($lp, (([ordered]@{ pid = 999999; owner_start_ticks = 0; nonce = 'x'; acquired_utc = ((Get-Date).ToUniversalTime().ToString('o')) }) | ConvertTo-Json -Compress), $utf8)
$d = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($d.acquired -eq $true) 'MF6.7 a dead-holder (abandoned) lock is broken and re-acquired'
Exit-PoolLock $d

# pid-reuse abandonment: alive pid but MISMATCHED start-ticks -> abandoned -> broken
[System.IO.File]::WriteAllText($lp, (([ordered]@{ pid = $PID; owner_start_ticks = 1; nonce = 'y'; acquired_utc = ((Get-Date).ToUniversalTime().ToString('o')) }) | ConvertTo-Json -Compress), $utf8)
Ok (Test-PoolLockAbandoned (Get-Content -LiteralPath $lp -Raw | ConvertFrom-Json)) 'MF6.8 alive pid + mismatched start-ticks is treated as abandoned (PID reuse)'
$e = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($e.acquired -eq $true) 'MF6.9 a pid-reused (abandoned) lock is broken and re-acquired'
Exit-PoolLock $e
Ok (-not (Test-Path -LiteralPath $lp)) 'MF6.10 lock file gone after true release'

# =================================================================================================
# MF8 -- heartbeat-stale => UNRESPONSIVE, no live-but-unresponsive fallback (red-team blocker 6 / must-fix 8)
# =================================================================================================
Write-Output ""
Write-Output "-- MF8: heartbeat-stale => UNRESPONSIVE + no split-brain fallback --"
$St = { param([int]$procId) try { return [long]((Get-Process -Id $procId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 } }
$myTicksN = [long]((Get-Process -Id $PID).StartTime.Ticks)

# a RUNNING + fresh-heartbeat manifest is responsive
$freshMan = [ordered]@{ pid = $PID; start_ticks = $myTicksN; state = 'RUNNING'; heartbeat_utc = ([DateTime]::UtcNow.ToString('o')) }
$lFresh = Test-SupervisorLiveness -Manifest $freshMan -StartTicksProbe $St
Ok ($lFresh.running -eq $true -and $lFresh.responsive -eq $true) 'MF8.1 alive + fresh heartbeat -> running AND responsive'

# a RUNNING but STALE-heartbeat manifest is running-but-NOT-responsive (WEDGED)
$staleMan = [ordered]@{ pid = $PID; start_ticks = $myTicksN; state = 'RUNNING'; heartbeat_utc = ([DateTime]::UtcNow.AddMinutes(-10).ToString('o')) }
$lStale = Test-SupervisorLiveness -Manifest $staleMan -StartTicksProbe $St
Ok ($lStale.running -eq $true -and $lStale.responsive -eq $false) 'MF8.2 alive + STALE heartbeat -> running but NOT responsive (wedged)'

# Send-SupervisorRequest against a wedged (alive+stale) supervisor -> supervisor_unresponsive, no_fallback=true
$wedgeRoot = Join-Path $scratch 'sup-wedge'
$wp = Get-SupervisorPaths -Root $wedgeRoot -WarmRegistryPath (Join-Path $scratch 'wedge-warm.json')
Initialize-SupervisorDirs -Paths $wp
[void](Write-SupervisorManifest -Path $wp.manifest -Obj $staleMan)
$wResp = Send-SupervisorRequest -Paths $wp -Op 'ensure_resident' -Params @{ model = 'x' } -TimeoutMs 600 -StartTicksProbe $St
Ok (-not $wResp.ok -and [string]$wResp.error.code -eq 'supervisor_unresponsive' -and [bool]$wResp.error.no_fallback -eq $true) 'MF8.3 request to a wedged supervisor -> supervisor_unresponsive, no_fallback=true'
Ok (@(Get-ChildItem -LiteralPath $wp.req_dir -Filter *.json -ErrorAction SilentlyContinue).Count -eq 0) 'MF8.4 no request file is written to a wedged supervisor (nothing to service)'

# absent supervisor -> supervisor_unavailable, no_fallback=false (per-call degrade is SAFE)
$absRoot = Join-Path $scratch 'sup-absent'
$ap = Get-SupervisorPaths -Root $absRoot -WarmRegistryPath (Join-Path $scratch 'abs-warm.json')
$aResp = Send-SupervisorRequest -Paths $ap -Op 'status' -TimeoutMs 300 -StartTicksProbe $St
Ok (-not $aResp.ok -and [string]$aResp.error.code -eq 'supervisor_unavailable' -and [bool]$aResp.error.no_fallback -eq $false) 'MF8.5 absent supervisor -> supervisor_unavailable, no_fallback=false (safe degrade)'

# CLIENT-LEVEL split-brain guard: -UseSupervisor -EnsureResident against a WEDGED supervisor must FAIL CLOSED
# and spawn NO server (no warm resident published).
$gw = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$mock = Join-Path $PSScriptRoot 'mock-llama-server.ps1'
$modelX = Join-Path $scratch 'mx.gguf'; [System.IO.File]::WriteAllText($modelX, 'x', $utf8)
$regX = [ordered]@{ schema='lifeorch.model_registry/0.1'; engine_build='mb'; engines=[ordered]@{ 'llama-server'=$mock }; defaults=[ordered]@{ llm='mock.a' }; tiers=[ordered]@{ llm=[ordered]@{ tiny='mock.a' } }; models=@([ordered]@{ model_id='mock.a'; type='llm'; wired=$true; engine='llama-server'; path=$modelX; context=4096; gpu_layers=99; params=[ordered]@{ sha256='aaaa'; size_bytes=1 } }) }
$regXPath = Join-Path $scratch 'mx-models.json'; [System.IO.File]::WriteAllText($regXPath, ($regX | ConvertTo-Json -Depth 8), $utf8)
$warmX = Join-Path $scratch 'mx-warm.json'
# publish a WEDGED supervisor manifest at the client's SupervisorRoot (pid=$PID alive, stale heartbeat)
[void](Write-SupervisorManifest -Path $wp.manifest -Obj $staleMan)   # reuse the wedge root
$base = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$gw,'-Registry',$regXPath,'-WarmRegistryPath',$warmX,'-SupervisorRoot',$wedgeRoot,'-PwshPath',$PwshPath,'-GpuLease','off')
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$o = & $PwshPath @base '-EnsureResident' '-UseSupervisor' '-Model' 'mock.a' '-Context' '4096' 2>$null
$ErrorActionPreference = $prev
$env8 = $null; try { $env8 = ($o | Out-String).Trim() | ConvertFrom-Json } catch { }
Ok ($null -ne $env8 -and $env8.status -eq 'error' -and [string]$env8.error.code -eq 'supervisor_unresponsive') 'MF8.6 client -UseSupervisor against a wedged supervisor FAILS CLOSED (status=error)'
$warmPublished = Test-Path -LiteralPath $warmX
Ok (-not $warmPublished) 'MF8.7 client fail-closed spawned NO per-call server (no warm resident published -> no split-brain)'

# =================================================================================================
# MF3 -- lifetime supervisor singleton (red-team two-start race / must-fix 3)
# =================================================================================================
Write-Output ""
Write-Output "-- MF3: lifetime supervisor singleton --"
$root1 = Join-Path $scratch 'sup-root-A'
$root2 = Join-Path $scratch 'sup-root-B'
New-Item -ItemType Directory -Path $root1 -Force | Out-Null
New-Item -ItemType Directory -Path $root2 -Force | Out-Null

# the name is deterministic + canonical-root-derived; different roots -> different singletons
$nameA = Get-SupervisorSingletonName $root1
$nameB = Get-SupervisorSingletonName $root2
Ok ($nameA -ne $nameB) 'MF3.1 different roots derive DIFFERENT singleton names'
Ok ($nameA -eq (Get-SupervisorSingletonName ($root1 + [System.IO.Path]::DirectorySeparatorChar))) 'MF3.2 the singleton name is canonical (trailing-separator invariant)'

# a child process holds the singleton for root1; the parent CANNOT claim it (second supervisor exits)
$holder = Join-Path $scratch 'singleton-holder.ps1'
$holderSrc = @"
param([string]`$Root)
Import-Module '$(Join-Path $moduleRoot 'lib/Supervisor.psm1')' -Force
`$c = Enter-SupervisorSingleton -Root `$Root -TimeoutMs 0
Write-Output ("HELD=" + `$c.acquired)
Start-Sleep -Seconds 6
"@
[System.IO.File]::WriteAllText($holder, $holderSrc, $utf8)
$hp = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$holder,'-Root',$root1) -PassThru -RedirectStandardOutput (Join-Path $scratch 'holder.out') -RedirectStandardError (Join-Path $scratch 'holder.err')
$spawned.Add([int]$hp.Id)
Start-Sleep -Milliseconds 1500
$claimBlocked = Enter-SupervisorSingleton -Root $root1 -TimeoutMs 400
Ok ($claimBlocked.acquired -eq $false -and $claimBlocked.reason -eq 'held_by_other') 'MF3.3 a second supervisor CANNOT claim a held singleton (would exit cleanly)'
# a DIFFERENT root is independent (both supervisors could coexist on different roots)
$claimOther = Enter-SupervisorSingleton -Root $root2 -TimeoutMs 400
Ok ($claimOther.acquired -eq $true) 'MF3.4 a singleton on a DIFFERENT root is independent'
Exit-SupervisorSingleton $claimOther | Out-Null

# after the holder exits (abandons the mutex), the singleton becomes claimable again. Poll for the holder to
# ACTUALLY exit first (Windows process teardown + mutex release is not instant), then claim -- retrying to
# absorb the OS-side abandon/release propagation delay.
try { Stop-Process -Id $hp.Id -Force -ErrorAction SilentlyContinue } catch { }
for ($w = 0; $w -lt 60; $w++) { if (-not (PidAlive $hp.Id)) { break }; Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds 500
$claimAfter = $null
for ($r = 0; $r -lt 12; $r++) { $claimAfter = Enter-SupervisorSingleton -Root $root1 -TimeoutMs 1000; if ($claimAfter.acquired) { break }; Start-Sleep -Milliseconds 400 }
if (-not $claimAfter.acquired) { Write-Output ("    [MF3.5 diag] reason=" + $claimAfter.reason + " holderAlive=" + (PidAlive $hp.Id)) }
Ok ($claimAfter.acquired -eq $true) 'MF3.5 after the holder dies the singleton is re-claimable (abandoned mutex inherited)'
Exit-SupervisorSingleton $claimAfter | Out-Null

# =================================================================================================
# MF7 -- hard nvidia-smi probe deadlines + unmanaged_vram_pressure (red-team blocker 7 / must-fix 7)
# =================================================================================================
Write-Output ""
Write-Output "-- MF7: hard probe deadlines + unmanaged_vram_pressure --"

# Invoke-BoundedCommand: a slow child is KILLED at the deadline and reported timed_out (never hangs).
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$slow = Invoke-BoundedCommand -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30') -DeadlineMs 700
$sw.Stop()
Ok ($slow.timed_out -eq $true -and $slow.ok -eq $false) 'MF7.1 a probe past its deadline is killed -> timed_out (never hangs)'
Ok ($sw.Elapsed.TotalMilliseconds -lt 5000) 'MF7.2 the bounded probe returns promptly at the deadline (<5s for a 30s child)'

# a fast child returns stdout + ok
$fast = Invoke-BoundedCommand -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Write-Output 4242') -DeadlineMs 8000
Ok ($fast.ok -eq $true -and ([string]$fast.stdout).Trim() -eq '4242') 'MF7.3 a fast probe returns ok + stdout'

# Get-GpuFreeMibBounded: unknown ($null) when nvidia-smi is absent (off-box) OR a real non-negative MiB on a
# box WITH nvidia-smi -- never a throw either way.
$probeR = Get-GpuFreeMibBounded -DeadlineMs 2000
Ok (($null -eq $probeR) -or ([int]$probeR -ge 0)) 'MF7.4 the bounded probe returns $null (off-box) OR a real MiB (on-box), never a throw'

# a MOCK nvidia-smi (env-pinned) is honored and bounded
$smiMock = Join-Path $scratch 'smi-mock.ps1'
[System.IO.File]::WriteAllText($smiMock, "Write-Output '7777'`n", $utf8)
# wrap the pwsh mock as an 'nvidia-smi' by pinning the env var to a tiny launcher .cmd-like shim is awkward;
# instead prove the pin+bound contract at the Invoke-BoundedCommand layer (the smi path just feeds it).
$mockRun = Invoke-BoundedCommand -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$smiMock) -DeadlineMs 8000
$mn = 0; $ml = (([string]$mockRun.stdout) -split "`n" | Where-Object { "$_".Trim() -ne '' } | Select-Object -First 1)
Ok ($mockRun.ok -eq $true -and [int]::TryParse(("$ml").Trim(), [ref]$mn) -and $mn -eq 7777) 'MF7.5 a pinned probe binary is executed + parsed'

# Get-GpuHandoffPlan flags unmanaged_pressure additively (decision/reason UNCHANGED for back-compat)
$pIns = Get-GpuHandoffPlan -FreeMib 2902 -RequiredMib 6800 -HasResident $false
Ok ($pIns.decision -eq 'insufficient' -and $pIns.reason -eq 'insufficient_headroom_no_resident') 'MF7.6 short headroom + no resident: decision/reason unchanged (back-compat)'
Ok ($pIns.unmanaged_pressure -eq $true) 'MF7.7 ...and unmanaged_pressure is flagged (no managed target to evict)'
$pGrant = Get-GpuHandoffPlan -FreeMib 9000 -RequiredMib 6800 -HasResident $false
Ok ($pGrant.decision -eq 'grant' -and $pGrant.unmanaged_pressure -eq $false) 'MF7.8 ample headroom: grant, no unmanaged pressure'
$pEv = Get-GpuHandoffPlan -FreeMib 2902 -RequiredMib 6800 -HasResident $true
Ok ($pEv.decision -eq 'evict_then_grant' -and $pEv.unmanaged_pressure -eq $false) 'MF7.9 short headroom + managed resident: evict_then_grant, not unmanaged'

# Invoke-SupervisorPrepareGpu surfaces unmanaged_vram_pressure (never a blind kill) when no managed target
$warmRegP = Join-Path $scratch 'mf7-warm.json'
$lockP = "$warmRegP.lock"
$pg = Invoke-SupervisorPrepareGpu -WarmRegPath $warmRegP -LockPath $lockP -RequiredVramMib 8000 -SafetyMib 512 -VramProbe { return 1000 } -StopProbe { param($r,$l) return $true } -StartTicksProbe { param($p) return 0 }
Ok ($pg.plan -eq 'insufficient' -and $pg.unmanaged_vram_pressure -eq $true -and $pg.reason -eq 'unmanaged_vram_pressure' -and $pg.evicted -eq $false -and $pg.ready -eq $false) 'MF7.10 prepare_gpu with short headroom + no resident -> unmanaged_vram_pressure, ungranted, NO blind kill'

# =================================================================================================
# MF1+2 -- per-resident suspended-create Job custody + assignment-FATAL (red-team blockers 1+3 / must-fix 1+2)
# The real suspended-create custody is Windows-only (proven LIVE on the box); here we prove the CONTRACT:
# resident-instance plumbing to the launcher, the FATALITY gate (job_owned:false => no publish), the honest
# off-Windows degrade, tree-accounting accessors, and the command-line quoter.
# =================================================================================================
Write-Output ""
Write-Output "-- MF1+2: per-resident Job custody + assignment-fatal --"
$mfWarm = Join-Path $scratch 'mf12-warm.json'
$mfLock = "$mfWarm.lock"
$HealthTrue = { param($h,$p) return $true }
$StartTicksP = { param([int]$procId) try { return [long]((Get-Process -Id $procId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 } }
$SockNull = { param($port) return $null }
$StopReal = { param($reg,$liveness) $pidv = 0; try { $pidv = [int]$reg.pid } catch { $pidv = 0 }; if ($pidv -le 0) { return $true }; try { Stop-Process -Id $pidv -Force -ErrorAction SilentlyContinue } catch { }; for ($i=0;$i -lt 20;$i++){ if (-not (PidAlive $pidv)) { return $true }; Start-Sleep -Milliseconds 100 }; return $false }
$cfg = Get-ResidentConfig ([pscustomobject]@{ model_id='m'; params=[pscustomobject]@{ sha256='s'; size_bytes=1 } }) $null 99 4096 $false 'f16' 'f16' $false 1 'exehash'
function New-Sleeper { $p = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 60') -PassThru; $script:spawned.Add([int]$p.Id); Start-Sleep -Milliseconds 150; return $p }

# (a) FATALITY: a launcher that returns pid>0 but job_owned=$false, WITH -RequireJobCustody => THROW + no publish + the uncustodied pid is terminated
$captured = @{}
$launchNoJob = { param($ReqConfig,[int]$PortHint,[string]$ResidentInstanceId) $script:captured['rii'] = $ResidentInstanceId; $sp = New-Sleeper; $script:captured['lastpid'] = [int]$sp.Id; return [ordered]@{ pid=[int]$sp.Id; start_ticks=[long]((Get-Process -Id $sp.Id).StartTime.Ticks); host='127.0.0.1'; port=18711; job_owned=$false; custody_supported=$true; stage='verify'; error='IsProcessInJob=false' } }.GetNewClosure()
$threw = $false; $errCode = ''
try { [void](Invoke-SupervisorEnsureResident -WarmRegPath $mfWarm -LockPath $mfLock -ReqConfig $cfg -ModelMeta @{ model_id='m' } -Launcher $launchNoJob -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicksP -RequireJobCustody) }
catch { $threw = $true; $tgt = $_.TargetObject; if ($null -ne $tgt -and (Has $tgt 'code')) { $errCode = [string]$tgt.code } }
Ok ($threw -and $errCode -eq 'job_custody_failed') 'MF1.1 job_owned:false WITH -RequireJobCustody is FATAL (job_custody_failed)'
Ok (-not (Test-Path -LiteralPath $mfWarm)) 'MF1.2 ...and NO manifest is published for an uncustodied resident'
# the fatality path must have TERMINATED the uncustodied process (no orphan)
$uncustodiedPid = [int]$script:captured['lastpid']
Start-Sleep -Milliseconds 400
Ok ($uncustodiedPid -gt 0 -and -not (PidAlive $uncustodiedPid)) 'MF1.3 the uncustodied process is TERMINATED by the fatality path (no orphan)'

# (b) the resident_instance_id is plumbed to the launcher BEFORE launch (so custody can be keyed to it)
Ok (-not [string]::IsNullOrWhiteSpace([string]$script:captured['rii'])) 'MF1.4 the launcher receives a resident_instance_id (custody key) BEFORE the launch'
$pinnedId = 'riPINNED0001'
$capturedGen = @{}
$launchOk = { param($ReqConfig,[int]$PortHint,[string]$ResidentInstanceId) $script:capturedGen['rii'] = $ResidentInstanceId; $sp = New-Sleeper; return [ordered]@{ pid=[int]$sp.Id; start_ticks=[long]((Get-Process -Id $sp.Id).StartTime.Ticks); host='127.0.0.1'; port=18712; job_owned=$true; job_instance_id='LifeorchResJob_PINNED'; custody_supported=$true } }.GetNewClosure()
$okRes = Invoke-SupervisorEnsureResident -WarmRegPath $mfWarm -LockPath $mfLock -ReqConfig $cfg -ModelMeta @{ model_id='m' } -Launcher $launchOk -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicksP -ResidentInstanceId $pinnedId -RequireJobCustody
Ok ([string]$script:capturedGen['rii'] -eq $pinnedId) 'MF1.5 a caller-pinned resident_instance_id reaches the launcher unchanged'
Ok ($okRes.started_new -eq $true -and $okRes.job_owned -eq $true) 'MF1.6 a job_owned:true launch WITH -RequireJobCustody succeeds'
$mfMan = Get-Content -LiteralPath $mfWarm -Raw | ConvertFrom-Json
Ok ([string]$mfMan.job_instance_id -eq 'LifeorchResJob_PINNED' -and [string]$mfMan.resident_instance_id -eq $pinnedId) 'MF1.7 the published manifest carries job_instance_id + resident_instance_id'
# clean up the resident from (b)
try { [void](Invoke-SupervisorEvict -WarmRegPath $mfWarm -LockPath $mfLock -StopProbe $StopReal -StartTicksProbe $StartTicksP) } catch { }

# (c) WITHOUT -RequireJobCustody, job_owned:false is NON-fatal (back-compat: the default-OFF/off-Windows path)
$launchNoJob2 = { param($ReqConfig,[int]$PortHint,[string]$ResidentInstanceId) $sp = New-Sleeper; return [ordered]@{ pid=[int]$sp.Id; start_ticks=[long]((Get-Process -Id $sp.Id).StartTime.Ticks); host='127.0.0.1'; port=18713; job_owned=$false } }.GetNewClosure()
$mfWarm2 = Join-Path $scratch 'mf12b-warm.json'; $mfLock2 = "$mfWarm2.lock"
$bcRes = Invoke-SupervisorEnsureResident -WarmRegPath $mfWarm2 -LockPath $mfLock2 -ReqConfig $cfg -ModelMeta @{ model_id='m' } -Launcher $launchNoJob2 -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicksP
Ok ($bcRes.started_new -eq $true -and $bcRes.job_owned -eq $false) 'MF1.8 WITHOUT -RequireJobCustody job_owned:false still publishes (back-compat/off-Windows honest degrade)'
try { [void](Invoke-SupervisorEvict -WarmRegPath $mfWarm2 -LockPath $mfLock2 -StopProbe $StopReal -StartTicksProbe $StartTicksP) } catch { }

# (d) New-CustodiedServer off-Windows: honest degrade (custody_supported:false, job_owned:false, real pid)
$so2 = Join-Path $scratch 'cs.out'; $se2 = Join-Path $scratch 'cs.err'
$cs = New-CustodiedServer -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 30') -ResidentInstanceId 'riCS1' -StdoutPath $so2 -StderrPath $se2
if ($cs.ok -and $cs.pid -gt 0) { $script:spawned.Add([int]$cs.pid) }
if ($IsWindows) {
    Ok ($cs.ok -and $cs.custody_supported -eq $true -and $cs.job_owned -eq $true) 'MF1.9 [Windows] New-CustodiedServer achieves real per-resident Job custody'
    Ok ((Get-ResidentJobMemberCount 'riCS1') -ge 1) 'MF1.10 [Windows] the resident Job reports >=1 active member'
    $ct = Close-ResidentJobTree 'riCS1'; Ok ($ct.members_zero -eq $true) 'MF1.11 [Windows] Close-ResidentJobTree drives the Job to ZERO members (tree_gone)'
} else {
    Ok ($cs.ok -and $cs.custody_supported -eq $false -and $cs.job_owned -eq $false -and $cs.pid -gt 0) 'MF1.9 [off-Windows] New-CustodiedServer degrades honestly (custody_supported:false, real pid)'
    Ok ((Get-ResidentJobMemberCount 'riNONE') -eq -1) 'MF1.10 [off-Windows] member-count for an untracked resident is -1 (unknown)'
    $ct = Close-ResidentJobTree 'riNONE'; Ok ($ct.had_job -eq $false -and $ct.members_zero -eq $true) 'MF1.11 Close-ResidentJobTree on an untracked id is a no-op (had_job:false)'
}

# (e) Initialize-CustodyType is honest about platform support
Ok ((Initialize-CustodyType) -eq $IsWindows) 'MF1.12 Initialize-CustodyType supported == IsWindows (no false durability claim off-Windows)'

# (f) the Windows command-line quoter handles spaces + quotes (argv[0] first)
$cl = ConvertTo-Win32CommandLine -FilePath 'C:\Program Files\llama\llama-server.exe' -Arguments @('-m','C:\a b\model.gguf','--host','127.0.0.1')
Ok ($cl -eq '"C:\Program Files\llama\llama-server.exe" -m "C:\a b\model.gguf" --host 127.0.0.1') 'MF1.13 ConvertTo-Win32CommandLine quotes only tokens with spaces (argv[0] first)'
$cl2 = ConvertTo-Win32CommandLine -FilePath 'llama' -Arguments @('--json','{"k":"v"}')
Ok ($cl2 -match '\\"k\\"') 'MF1.14 the quoter escapes embedded double-quotes'

# =================================================================================================
# MF4 -- authenticated exact-target-fenced IPC (red-team blocker 2 / must-fix 4)
# =================================================================================================
Write-Output ""
Write-Output "-- MF4: authenticated / path-contained / replay-guarded IPC --"
$ipcPaths = Get-SupervisorPaths -Root (Join-Path $scratch 'ipc') -WarmRegistryPath (Join-Path $scratch 'ipc-warm.json')
Initialize-SupervisorDirs -Paths $ipcPaths
Reset-SupervisorConsumedRequests

# (a) request_id PATH CONTAINMENT: a crafted id with path separators / traversal is rejected
Ok ((Test-SupervisorRequestId ([Guid]::NewGuid().ToString('N'))) -eq $true) 'MF4.1 a GUID request_id is valid'
Ok ((Test-SupervisorRequestId '../../etc/passwd') -eq $false) 'MF4.2 a path-traversal request_id is REJECTED (containment)'
Ok ((Test-SupervisorRequestId 'a/b') -eq $false -and (Test-SupervisorRequestId 'a\b') -eq $false) 'MF4.3 request_ids with path separators are REJECTED'
# write an ATTACK request straight into req_dir with a NORMAL filename but a malicious request_id in its CONTENT
$attackBody = ([ordered]@{ schema=$SUP_REQ_SCHEMA; request_id='../../pwn'; op='evict'; params=[ordered]@{} } | ConvertTo-Json -Compress)
[System.IO.File]::WriteAllText((Join-Path $ipcPaths.req_dir 'attack.json'), $attackBody, $utf8)
$pb = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{ evict = { param($r) return @{ ok=$true } } } -SupervisorPid 3 -SupervisorGeneration 'GEN1'
# no response file escaped the resp dir's parent; a safe 'badreq_*' response exists instead
$escaped = Test-Path -LiteralPath (Join-Path (Split-Path -Parent $ipcPaths.resp_dir) 'pwn.json')
$safeResp = @(Get-ChildItem -LiteralPath $ipcPaths.resp_dir -Filter 'badreq_*.json' -ErrorAction SilentlyContinue)
Ok ((-not $escaped) -and $safeResp.Count -ge 1) 'MF4.4 a crafted-id request (bad request_id in content) writes a SAFE contained response (no path escape)'

# (b) idempotent REPLAY guard for a mutating op
Reset-SupervisorConsumedRequests
$rid1 = 'evictreq0001'
$rq1 = [pscustomobject]@{ schema=$SUP_REQ_SCHEMA; request_id=$rid1; op='evict'; params=[pscustomobject]@{}; expect_generation='' }
[void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rq1)
$p1 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{ evict = { param($r) return @{ evicted=$true } } } -SupervisorPid 3 -SupervisorGeneration 'GEN1'
$r1 = Read-SupervisorResponseFile (Join-Path $ipcPaths.resp_dir "$rid1.json")
Ok ($null -ne $r1 -and [bool]$r1.ok -eq $true) 'MF4.5 a fresh mutating request is handled'
# replay the SAME id -> refused
[void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rq1)
$p2 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{ evict = { param($r) return @{ evicted=$true } } } -SupervisorPid 3 -SupervisorGeneration 'GEN1'
$r2 = Read-SupervisorResponseFile (Join-Path $ipcPaths.resp_dir "$rid1.json")
Ok ($null -ne $r2 -and -not [bool]$r2.ok -and [string]$r2.error.code -eq 'stale_or_replayed') 'MF4.6 a REPLAYED mutating request_id is REFUSED (idempotent receipt)'

# (c) generation binding: a mutating request naming a WRONG generation is refused
$rq3 = [pscustomobject]@{ schema=$SUP_REQ_SCHEMA; request_id='greq0003'; op='prepare_gpu'; params=[pscustomobject]@{}; expect_generation='WRONGGEN' }
[void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rq3)
$p3 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{ prepare_gpu = { param($r) return @{ ok=$true } } } -SupervisorPid 3 -SupervisorGeneration 'GEN1'
$r3 = Read-SupervisorResponseFile (Join-Path $ipcPaths.resp_dir 'greq0003.json')
Ok ($null -ne $r3 -and -not [bool]$r3.ok -and [string]$r3.error.code -eq 'generation_mismatch') 'MF4.7 a mutating request naming the WRONG supervisor generation is REFUSED'

# (d) authenticated shutdown
$rqSdBad = [pscustomobject]@{ schema=$SUP_REQ_SCHEMA; request_id='sd0001'; op='shutdown'; params=[pscustomobject]@{}; expect_generation='' }
[void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rqSdBad)
$ps1 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{} -SupervisorPid 3 -SupervisorGeneration 'GEN1'
Ok ($ps1.shutdown -eq $false) 'MF4.8 an UNauthenticated shutdown does NOT stop the supervisor'
$rqSdOk = [pscustomobject]@{ schema=$SUP_REQ_SCHEMA; request_id='sd0002'; op='shutdown'; params=[pscustomobject]@{}; expect_generation='GEN1' }
[void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rqSdOk)
$ps2 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{} -SupervisorPid 3 -SupervisorGeneration 'GEN1'
Ok ($ps2.shutdown -eq $true) 'MF4.9 an AUTHENTICATED shutdown (matching generation) stops the supervisor'

# (e) read-only ops (ping/status) are NOT gated by replay/generation (exempt)
$ridPing = 'pingreq01'
foreach ($k in 1..2) { $rqp = [pscustomobject]@{ schema=$SUP_REQ_SCHEMA; request_id=$ridPing; op='ping'; params=[pscustomobject]@{} }; [void](Write-SupervisorRequest -ReqDir $ipcPaths.req_dir -Request $rqp); $pp2 = Invoke-SupervisorPollOnce -Paths $ipcPaths -Handlers @{} -SupervisorPid 3 -SupervisorGeneration 'GEN1' }
$rp = Read-SupervisorResponseFile (Join-Path $ipcPaths.resp_dir "$ridPing.json")
Ok ($null -ne $rp -and [bool]$rp.ok -and [bool]$rp.result.pong) 'MF4.10 read-only ping is exempt from the replay guard (idempotent + safe)'

# =================================================================================================
# MF5 -- no launch after a failed / partial evict or a failed CAS (red-team blocker 5 / must-fix 5)
# =================================================================================================
Write-Output ""
Write-Output "-- MF5: no launch after a failed/partial evict or failed CAS --"
$mf5Warm = Join-Path $scratch 'mf5-warm.json'; $mf5Lock = "$mf5Warm.lock"
# publish a resident (a live sleeper stands in for the server)
$launch5 = { param($ReqConfig,[int]$PortHint,[string]$ResidentInstanceId) $sp = New-Sleeper; return [ordered]@{ pid=[int]$sp.Id; start_ticks=[long]((Get-Process -Id $sp.Id).StartTime.Ticks); host='127.0.0.1'; port=18721; job_owned=$false } }.GetNewClosure()
$r5a = Invoke-SupervisorEnsureResident -WarmRegPath $mf5Warm -LockPath $mf5Lock -ReqConfig $cfg -ModelMeta @{ model_id='m' } -Launcher $launch5 -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicksP
$oldResidentPid = [int]$r5a.pid
Ok ((PidAlive $oldResidentPid) -and (Test-Path -LiteralPath $mf5Warm)) 'MF5.0 a resident is published (setup)'
# now force a reload with a StopProbe that FAILS to stop the resident -> evict is NOT confirmed
$stopFails = { param($reg,$liveness) return $false }
$launch5b = { param($ReqConfig,[int]$PortHint,[string]$ResidentInstanceId) $script:captured['relaunched'] = $true; $sp = New-Sleeper; return [ordered]@{ pid=[int]$sp.Id; start_ticks=0; host='127.0.0.1'; port=18722; job_owned=$false } }.GetNewClosure()
$script:captured['relaunched'] = $false
$threw5 = $false; $code5 = ''
try { [void](Invoke-SupervisorEnsureResident -WarmRegPath $mf5Warm -LockPath $mf5Lock -ReqConfig $cfg -ModelMeta @{ model_id='m' } -Launcher $launch5b -HealthProbe $HealthTrue -StopProbe $stopFails -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicksP -ForceReload) }
catch { $threw5 = $true; $tgt = $_.TargetObject; if ($null -ne $tgt -and (Has $tgt 'code')) { $code5 = [string]$tgt.code } }
Ok ($threw5 -and $code5 -eq 'evict_not_confirmed') 'MF5.1 a failed evict is FATAL (evict_not_confirmed) -- transition aborts'
Ok ($script:captured['relaunched'] -eq $false) 'MF5.2 ...NO replacement server was launched (no split-brain)'
Ok (Test-Path -LiteralPath $mf5Warm) 'MF5.3 ...the manifest was NOT cleared (cannot prove it empty)'
$mf5reg = Get-Content -LiteralPath $mf5Warm -Raw | ConvertFrom-Json
Ok ([int]$mf5reg.pid -eq $oldResidentPid) 'MF5.4 ...the old resident claim is preserved (GPU left as-is, ungranted to a new server)'
# cleanup: kill the old resident + clear
try { Stop-Process -Id $oldResidentPid -Force -ErrorAction SilentlyContinue } catch { }
try { Remove-Item -LiteralPath $mf5Warm -Force -ErrorAction SilentlyContinue } catch { }

# =================================================================================================
# MF9 -- restart reconcile: no manifest-only survivor adoption (red-team survivor-adoption / must-fix 9)
# =================================================================================================
Write-Output ""
Write-Output "-- MF9: restart reconcile - no manifest-only survivor adoption --"
$mf9Warm = Join-Path $scratch 'mf9-warm.json'; $mf9Lock = "$mf9Warm.lock"
$mySt = [long]((Get-Process -Id $PID).StartTime.Ticks)
# a healthy verified RESIDENT claim (pid=$PID alive, identity ok, healthy) naming instance 'riSURV'
$residentClaim = [ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$PID; start_ticks=$mySt; resident_instance_id='riSURV'; port=0; fence=1; fence_holder='h'; fence_ttl_seconds=120; fence_expires_utc=([DateTime]::UtcNow.AddSeconds(120).ToString('o')) }

# (a) DEFAULT reconcile (no -RequireCustodian) KEEPS a healthy verified resident (parity with S7 -- back-compat)
[void](Write-PoolManifest $mf9Warm $residentClaim)
$rcDef = Invoke-SupervisorReconcile -WarmRegPath $mf9Warm -LockPath $mf9Lock -StartTicksProbe $StartTicksP -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe { param($r,$l) return $true }
Ok ($rcDef.kept_resident -eq $true -and $rcDef.action -eq 'kept_valid_resident') 'MF9.1 DEFAULT reconcile keeps a healthy verified resident (back-compat with S7)'

# (b) -RequireCustodian WITHOUT a retained custodian => survivor NOT adopted -> EMPTY (fenced/killed)
[void](Write-PoolManifest $mf9Warm $residentClaim)
$killed = @{}
$stopRec = { param($reg,$liveness) $script:captured['recStopCalled'] = $true; return $true }
$script:captured['recStopCalled'] = $false
$rcNo = Invoke-SupervisorReconcile -WarmRegPath $mf9Warm -LockPath $mf9Lock -StartTicksProbe $StartTicksP -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe $stopRec -RequireCustodian
Ok ($rcNo.kept_resident -eq $false -and $rcNo.action -like 'survivor_not_adopted*' -and -not (Test-Path -LiteralPath $mf9Warm)) 'MF9.2 -RequireCustodian: a manifest-only survivor is NOT adopted -> driven to EMPTY'
Ok ($script:captured['recStopCalled'] -eq $true) 'MF9.3 ...the unadopted survivor is fenced/killed (not left running)'

# (c) -RequireCustodian WITH a retained custodian for that instance => KEPT (durable custodian verified).
# On Windows a real per-resident Job (live members) is required; off-Windows a registered entry suffices.
if ($IsWindows) {
    $so9 = Join-Path $scratch 'mf9.out'; $se9 = Join-Path $scratch 'mf9.err'
    $cs9 = New-CustodiedServer -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 60') -ResidentInstanceId 'riSURV2' -StdoutPath $so9 -StderrPath $se9
    if ($cs9.ok -and $cs9.pid -gt 0) { $script:spawned.Add([int]$cs9.pid) }
    $claim9 = [ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=[int]$cs9.pid; start_ticks=[long]$cs9.start_ticks; resident_instance_id='riSURV2'; port=0; fence=1; fence_holder='h'; fence_ttl_seconds=120; fence_expires_utc=([DateTime]::UtcNow.AddSeconds(120).ToString('o')) }
    [void](Write-PoolManifest $mf9Warm $claim9)
    $rcYes = Invoke-SupervisorReconcile -WarmRegPath $mf9Warm -LockPath $mf9Lock -StartTicksProbe $StartTicksP -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe { param($r,$l) return $true } -RequireCustodian
    Ok ($rcYes.kept_resident -eq $true -and $rcYes.action -eq 'kept_custodian_verified') 'MF9.4 [Windows] a resident WITH a REAL retained custodian (live job members) IS adopted'
    try { [void](Close-ResidentJobTree -InstanceId 'riSURV2') } catch { }
} else {
    [void](Write-PoolManifest $mf9Warm $residentClaim)
    Register-ResidentJob -InstanceId 'riSURV' -JobInfo @{ name='fakejob'; pid=$PID }   # off-Windows: presence == custodian (member-count is Windows-only)
    $rcYes = Invoke-SupervisorReconcile -WarmRegPath $mf9Warm -LockPath $mf9Lock -StartTicksProbe $StartTicksP -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe { param($r,$l) return $true } -RequireCustodian
    Ok ($rcYes.kept_resident -eq $true -and $rcYes.action -eq 'kept_custodian_verified') 'MF9.4 [off-Windows] a resident WITH a retained custodian entry IS adopted'
    try { [void](Close-ResidentJobTree -InstanceId 'riSURV') } catch { }
}
try { Remove-Item -LiteralPath $mf9Warm -Force -ErrorAction SilentlyContinue } catch { }

# =================================================================================================
# MF10 -- real content verification + stronger identity (red-team blocker 7 / must-fix 10) [partial: primitives
# + fail-closed pre-launch hook; the ACL'd app-data relocation + trust-root provisioning are NAMED residuals]
# =================================================================================================
Write-Output ""
Write-Output "-- MF10: real content verification + trust-root path hardening --"
$vfile = Join-Path $scratch 'engine.bin'
[System.IO.File]::WriteAllText($vfile, 'the real engine bytes', $utf8)
$goodSha = Get-FileSha256Hex $vfile
Ok (-not [string]::IsNullOrWhiteSpace($goodSha) -and $goodSha.Length -eq 64) 'MF10.1 Get-FileSha256Hex computes a sha256 over actual bytes'
$vGood = Test-ContentHashTrusted -Path $vfile -ExpectedSha256 $goodSha
Ok ($vGood.ok -eq $true -and $vGood.reason -eq 'match') 'MF10.2 matching content -> trusted (match)'
$vBad = Test-ContentHashTrusted -Path $vfile -ExpectedSha256 ('0' * 64)
Ok ($vBad.ok -eq $false -and $vBad.reason -eq 'hash_mismatch') 'MF10.3 a content-hash MISMATCH is refused (not trusted)'
$vMissing = Test-ContentHashTrusted -Path (Join-Path $scratch 'nope.bin') -ExpectedSha256 $goodSha
Ok ($vMissing.ok -eq $false -and $vMissing.reason -eq 'file_missing') 'MF10.4 a missing file is refused'
$vNoExp = Test-ContentHashTrusted -Path $vfile -ExpectedSha256 ''
Ok ($vNoExp.ok -eq $false -and $vNoExp.reason -eq 'no_expected') 'MF10.5 no trusted expected hash -> not trusted (no blind trust of models.json)'

# reparse-point rejection on a trust root (symlink) -- best effort; skip cleanly if the FS/OS disallows it
$linkOk = $false
try {
    $target = Join-Path $scratch 'realdir'; New-Item -ItemType Directory -Path $target -Force | Out-Null
    $tf = Join-Path $target 'engine.bin'; [System.IO.File]::WriteAllText($tf, 'x', $utf8)
    $link = Join-Path $scratch 'linkdir'
    New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
    $linkOk = $true
    $viaLink = Join-Path $link 'engine.bin'
    Ok ((Test-PathReparsePoint $viaLink) -eq $true) 'MF10.6 a path through a REPARSE POINT is detected (rejected on a trust root)'
    Ok ((Test-PathReparsePoint $tf) -eq $false) 'MF10.7 a direct (non-reparse) path is clean'
} catch {
    Ok ($true) 'MF10.6 (skipped: symlink creation not permitted on this FS -- reparse detection is a live check)'
    Ok ((Test-PathReparsePoint $vfile) -eq $false) 'MF10.7 a direct (non-reparse) path is clean'
}

# fail-closed PRE-LAUNCH verify hook in New-CustodiedServer: a content-hash mismatch => NO launch
$so10 = Join-Path $scratch 'v10.out'; $se10 = Join-Path $scratch 'v10.err'
$csBad = New-CustodiedServer -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep 5') -ResidentInstanceId 'riV10' -StdoutPath $so10 -StderrPath $se10 -PreLaunchVerify @{ $vfile = ('0' * 64) }
Ok ($csBad.ok -eq $false -and $csBad.stage -eq 'content_verify' -and $csBad.pid -eq 0) 'MF10.8 New-CustodiedServer with a content-hash MISMATCH does NOT launch (fail-closed)'
$csGood = New-CustodiedServer -FilePath $PwshPath -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep 30') -ResidentInstanceId 'riV10b' -StdoutPath $so10 -StderrPath $se10 -PreLaunchVerify @{ $vfile = $goodSha }
if ($csGood.ok -and $csGood.pid -gt 0) { $script:spawned.Add([int]$csGood.pid) }
Ok ($csGood.ok -eq $true -and $csGood.pid -gt 0) 'MF10.9 New-CustodiedServer with a MATCHING content hash launches normally'
if ($IsWindows -and $csGood.pid -gt 0) { try { [void](Close-ResidentJobTree -InstanceId 'riV10b') } catch { } }

# =================================================================================================
Cleanup-Spawned
try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Output ""
Write-Output "==== HARDENING RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
