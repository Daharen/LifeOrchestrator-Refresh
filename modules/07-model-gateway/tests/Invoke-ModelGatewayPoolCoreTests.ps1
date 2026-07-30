#requires -Version 7.0
# OFF-MACHINE unit tests for the Stage-1.1 pool-manager integrity core (lib/PoolManager.psm1).
# Pure functions only -- no llama-server, no GPU, no Windows dependency -- so every WARM_POOL_DESIGN
# section-10 invariant is exercised deterministically on the cloud gate and, unchanged, live.
# ASCII-only. Exit 0 iff all pass.
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'lib/PoolManager.psm1') -Force

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-core-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

Write-Output "==== model.gateway POOL-CORE unit tests (pure) ===="

# ---- fixtures: two model configs on one mock engine ----
$modelA = [pscustomobject]@{ model_id = 'mock.a'; engine_path = '/some/enginA'; params = [pscustomobject]@{ sha256 = 'aaaa'; size_bytes = 10 } }
$modelB = [pscustomobject]@{ model_id = 'mock.b'; engine_path = '/some/enginA'; params = [pscustomobject]@{ sha256 = 'bbbb'; size_bytes = 20 } }
$reg    = [pscustomobject]@{ engine_build = 'b-1'; engines = [pscustomobject]@{ 'llama-server' = '/some/enginA' } }

# =================================================================================================
# #6 config-hash / instance-generation split
# =================================================================================================
$cfgA_4k = Get-ResidentConfig $modelA $reg 99 4096 $true 'f16' 'f16' $false 1 'EXEHASH1'
$hA_4k   = Get-ResidentConfigHash $cfgA_4k
Ok (-not [string]::IsNullOrWhiteSpace($hA_4k)) '6.1 resident_config_hash computed'
# generation nonce is NOT in the config hash -> two launches of the same config hash-equal
$gen1 = New-InstanceGeneration; $gen2 = New-InstanceGeneration
Ok ($gen1 -ne $gen2) '6.2 instance_generation is a fresh per-launch nonce'
$hA_4k_again = Get-ResidentConfigHash (Get-ResidentConfig $modelA $reg 99 4096 $true 'f16' 'f16' $false 1 'EXEHASH1')
Ok ($hA_4k -eq $hA_4k_again) '6.3 config hash is deterministic (nonce-independent)'
# engine_path differs but exe hash + everything else identical -> SAME hash (hash contents, not paths)
$modelA_moved = [pscustomobject]@{ model_id = 'mock.a'; engine_path = '/DIFFERENT/path'; params = [pscustomobject]@{ sha256 = 'aaaa'; size_bytes = 10 } }
$hA_moved = Get-ResidentConfigHash (Get-ResidentConfig $modelA_moved $reg 99 4096 $true 'f16' 'f16' $false 1 'EXEHASH1')
Ok ($hA_moved -eq $hA_4k) '6.4 relocating the engine path does NOT change the hash (contents, not paths)'
# a DIFFERENT engine exe hash DOES change the hash
$hA_exe2 = Get-ResidentConfigHash (Get-ResidentConfig $modelA $reg 99 4096 $true 'f16' 'f16' $false 1 'EXEHASH2')
Ok ($hA_exe2 -ne $hA_4k) '6.5 a different engine exe hash changes the config hash'
# context / model / KV changes each change the hash
Ok ((Get-ResidentConfigHash (Get-ResidentConfig $modelA $reg 99 8192 $true 'f16' 'f16' $false 1 'EXEHASH1')) -ne $hA_4k) '6.6 context change changes the hash'
Ok ((Get-ResidentConfigHash (Get-ResidentConfig $modelB $reg 99 4096 $true 'f16' 'f16' $false 1 'EXEHASH1')) -ne $hA_4k) '6.7 model change changes the hash'
Ok ((Get-ResidentConfigHash (Get-ResidentConfig $modelA $reg 99 4096 $true 'q8_0' 'f16' $false 1 'EXEHASH1')) -ne $hA_4k) '6.8 KV-type change changes the hash'

# =================================================================================================
# #7/#8/#9 CanServe(resident, request): exact identity, capacity '>='
# =================================================================================================
$resid_9b_32k = Get-ResidentConfig ([pscustomobject]@{ model_id='9b'; params=[pscustomobject]@{sha256='99'} }) $reg 99 32768 $true 'f16' 'f16' $false 4 'E'
$req_9b_16k   = Get-ResidentConfig ([pscustomobject]@{ model_id='9b'; params=[pscustomobject]@{sha256='99'} }) $reg 99 16384 $true 'f16' 'f16' $false 1 'E'
Ok ((Test-CanServe $resid_9b_32k $req_9b_16k).can_serve -eq $true) '8.1 a 32K/np4 resident serves a 16K/np1 request (capacity >=)'
Ok ((Test-CanServe $req_9b_16k $resid_9b_32k).can_serve -eq $false) '8.2 a 16K resident CANNOT serve a 32K request (capacity fails)'
Ok ((Test-CanServe $resid_9b_32k $resid_9b_32k).can_serve -eq $true) '8.3 identical config serves'
# identity mismatch -> cannot serve
$req_other = Get-ResidentConfig ([pscustomobject]@{ model_id='9b'; params=[pscustomobject]@{sha256='DIFFERENT'} }) $reg 99 16384 $true 'f16' 'f16' $false 1 'E'
Ok ((Test-CanServe $resid_9b_32k $req_other).can_serve -eq $false) '8.4 model_sha256 mismatch -> cannot serve'
$req_flash = Get-ResidentConfig ([pscustomobject]@{ model_id='9b'; params=[pscustomobject]@{sha256='99'} }) $reg 99 16384 $true 'f16' 'f16' $true 1 'E'
Ok ((Test-CanServe $resid_9b_32k $req_flash).can_serve -eq $false) '8.5 flash_attn mismatch -> cannot serve'
# finding 9: a resident 9B serves an M0 (3B-floor-sized) request that is smaller in capacity
$m0_small = Get-ResidentConfig ([pscustomobject]@{ model_id='9b'; params=[pscustomobject]@{sha256='99'} }) $reg 99 2048 $true 'f16' 'f16' $false 1 'E'
Ok ((Test-CanServe $resid_9b_32k $m0_small).can_serve -eq $true) '9.1 a resident 9B (32K) serves a smaller M0 request (no downshift)'

# =================================================================================================
# #1 fencing: monotonic token, CAS, short renewable TTL, supersede on lapse
# =================================================================================================
$fp = Join-Path $scratch 'fence.json'
$f1 = Grant-Fence -Path $fp -Holder 'taskA' -TtlSeconds 120
Ok ($f1 -eq 1) '1.1 first fence == 1'
$f2 = Grant-Fence -Path $fp -Holder 'taskA' -TtlSeconds 120   # same holder can re-grant (monotonic)
Ok ($f2 -eq 2) '1.2 fence is monotonic on re-grant'
Ok ((Test-FenceCurrent -Path $fp -Fence 2) -eq $true) '1.3 holder of the current fence has authority'
Ok ((Test-FenceCurrent -Path $fp -Fence 1) -eq $false) '1.4 a superseded (older) fence has NO authority'
# a DIFFERENT holder cannot co-own while the fence is live
$fb = Grant-Fence -Path $fp -Holder 'taskB' -TtlSeconds 120
Ok ($null -eq $fb) '1.5 a second holder is refused while the fence is live (no co-ownership)'
# expire the fence, then taskB may supersede (renewal lapsed -> authority lost)
$regNow = Read-PoolManifest $fp
$mm = ConvertTo-MutableMap $regNow
$mm['fence_expires_utc'] = (ConvertTo-UtcString ((Get-NowUtc).AddSeconds(-5)))   # force-expire
[void](Write-PoolManifest $fp $mm)
Ok ((Test-FenceCurrent -Path $fp -Fence 2) -eq $false) '1.6 an expired fence loses authority'
$fb2 = Grant-Fence -Path $fp -Holder 'taskB' -TtlSeconds 120
Ok ($fb2 -eq 3) '1.7 a contender supersedes an expired fence (fence bumped)'
# taskA (fence 2) is now superseded: a CAS mutation must fail
Ok ((Set-ManifestCas -Path $fp -Fence 2 -Updates @{ state = 'RESIDENT' }) -eq $false) '1.8 a superseded holder CANNOT CAS-mutate (lost authority)'
Ok ((Set-ManifestCas -Path $fp -Fence 3 -Updates @{ state = 'RESIDENT' }) -eq $true) '1.9 the current holder CAN CAS-mutate'
Ok ((Update-FenceRenewal -Path $fp -Fence 3 -TtlSeconds 120) -eq $true) '1.10 the current holder renews its TTL'
Ok ((Update-FenceRenewal -Path $fp -Fence 2 -TtlSeconds 120) -eq $false) '1.11 a superseded holder cannot renew'

# =================================================================================================
# #1 generation-mismatch rejection for inference
# =================================================================================================
$manifest = [pscustomobject]@{ instance_generation = 'GEN-CURRENT'; fence = 3 }
Ok ((Test-GenerationMatch $manifest 'GEN-CURRENT' 3).match -eq $true) '1.12 inference matches the resident generation+fence'
Ok ((Test-GenerationMatch $manifest 'GEN-STALE' -1).reason -eq 'generation_mismatch') '1.13 a stale expected generation is REJECTED'
Ok ((Test-GenerationMatch $manifest 'GEN-CURRENT' 2).reason -eq 'fence_mismatch') '1.14 a stale expected fence is REJECTED'
Ok ((Test-GenerationMatch $null 'GEN-CURRENT' -1).reason -eq 'no_resident') '1.15 no resident -> rejected'

# =================================================================================================
# #3 state-machine transition legality
# =================================================================================================
Ok ((Test-LegalTransition 'EMPTY' 'STARTING') -eq $true)  '3.1 EMPTY->STARTING legal'
Ok ((Test-LegalTransition 'STARTING' 'RESIDENT') -eq $true) '3.2 STARTING->RESIDENT legal'
Ok ((Test-LegalTransition 'RESIDENT' 'STOPPING') -eq $true) '3.3 RESIDENT->STOPPING legal'
Ok ((Test-LegalTransition 'STOPPING' 'EMPTY_CONFIRMED') -eq $true) '3.4 STOPPING->EMPTY_CONFIRMED legal'
Ok ((Test-LegalTransition 'EMPTY_CONFIRMED' 'EMPTY') -eq $true) '3.5 EMPTY_CONFIRMED->EMPTY legal'
Ok ((Test-LegalTransition 'EMPTY' 'RESIDENT') -eq $false) '3.6 EMPTY->RESIDENT is ILLEGAL (must pass through STARTING)'
Ok ((Test-LegalTransition 'RESIDENT' 'EMPTY') -eq $false) '3.7 RESIDENT->EMPTY is ILLEGAL (must confirm stop first)'

# =================================================================================================
# #4 verified identity + socket-owner seam
# =================================================================================================
$owner = { param($port) if ($port -eq 9999) { return 4242 } else { return 7777 } }
Ok ((Test-SocketOwner -Port 9999 -ExpectedPid 4242 -SocketOwnerProbe $owner) -eq $true)  '4.1 socket owner matches launched pid -> verified'
Ok ((Test-SocketOwner -Port 9999 -ExpectedPid 1111 -SocketOwnerProbe $owner) -eq $false) '4.2 socket owner mismatch -> NOT verified (wrong generation guarded)'
Ok ($null -eq (Test-SocketOwner -Port 9999 -ExpectedPid 4242 -SocketOwnerProbe $null))    '4.3 no probe (off-Windows) -> undeterminable/null (advisory, never throws)'
# identity with an injected start-ticks probe (avoids a real process)
$fakeReg = [pscustomobject]@{ pid = $PID; start_ticks = 123456789 }
$tickProbe = { param($procId) return 123456789 }
Ok ((Test-ResidentIdentity $fakeReg $tickProbe).identity_ok -eq $true) '4.4 matching creation-time -> identity ok'
$tickProbeBad = { param($procId) return 999999999999 }
Ok ((Test-ResidentIdentity $fakeReg $tickProbeBad).identity_ok -eq $false) '4.5 mismatched creation-time -> identity rejected (PID-reuse guard)'

# =================================================================================================
# #2/#15 GPU handoff planner
# =================================================================================================
Ok ((Get-GpuHandoffPlan -FreeMib 9000 -RequiredMib 6800 -HasResident $false).decision -eq 'grant') '2.1 ample headroom -> grant'
Ok ((Get-GpuHandoffPlan -FreeMib 2902 -RequiredMib 6800 -HasResident $true).decision -eq 'evict_then_grant') '2.2 resident blocks headroom -> evict then grant'
Ok ((Get-GpuHandoffPlan -FreeMib 2902 -RequiredMib 6800 -HasResident $false).decision -eq 'insufficient') '2.3 no resident + no headroom -> insufficient (no blind co-load)'
Ok ((Get-GpuHandoffPlan -FreeMib $null -RequiredMib 6800 -HasResident $true).reason -eq 'vram_unknown') '2.4 VRAM unknown (off-box) -> non-fatal plan (evict to be safe)'

# =================================================================================================
# machine-global lock: acquire / stale-break
# =================================================================================================
$lp = Join-Path $scratch 'pool.lock'
$lk = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($lk.acquired -eq $true) 'L.1 lock acquired'
$lk2 = Enter-PoolLock -LockPath $lp -TimeoutMs 300
Ok ($lk2.acquired -eq $false) 'L.2 second acquire blocks while held'
Exit-PoolLock $lk
$lk3 = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($lk3.acquired -eq $true) 'L.3 lock re-acquired after release'
Exit-PoolLock $lk3
# stale-break: a lock file owned by a dead pid is broken
[System.IO.File]::WriteAllText($lp, (([ordered]@{ pid = 999999; acquired_utc = (ConvertTo-UtcString (Get-NowUtc)) } | ConvertTo-Json -Compress)))
$lk4 = Enter-PoolLock -LockPath $lp -TimeoutMs 2000
Ok ($lk4.acquired -eq $true) 'L.4 a stale lock (dead holder pid) is broken and re-acquired'
Exit-PoolLock $lk4

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
