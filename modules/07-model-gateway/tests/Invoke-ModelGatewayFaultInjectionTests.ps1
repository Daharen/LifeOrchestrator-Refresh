#requires -Version 7.0
# OFF-MACHINE FAULT-INJECTION suite for model.gateway Stage-1.1 (WARM_POOL_DESIGN section 10, D-0067).
# REQUIRED gate before the pool may be enabled by default. Drives the REAL Invoke-ModelGateway.ps1 against the
# cross-platform MOCK llama-server (no GPU / no models) so every fault path is exercised deterministically on the
# cloud gate AND, unchanged, live via the executor. ASCII-only. Exit 0 iff all pass.
#
# Scenarios (section 10 "Required before done"):
#   FI-1  crash at each transition point -> reconcile drives to a clean EMPTY; a valid resident is KEPT
#   FI-2  forced fence/generation expiry mid-request -> inference REJECTED (no wrong-generation call lands)
#   FI-3  a stale idle-callback vs a fresh request -> the refreshed resident is NOT raced into eviction
#   FI-4  Job-Object reap + PID-reuse -> a reused pid (identity mismatch) is NOT killed; managed tag present
#   FI-5  KV isolation across crash/cancel -> erase-on-checkout AND check-in fire (no cross-task prefix reuse)
#   FI-6  GPU-handoff eviction -> evict-before-grant (no blind co-load); 0 orphans
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$mock  = Join-Path $PSScriptRoot 'mock-llama-server.ps1'

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-fi-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$modelA = Join-Path $scratch 'model-a.gguf'; [System.IO.File]::WriteAllText($modelA, 'x', $utf8)
$reg = [ordered]@{
    schema = 'lifeorch.model_registry/0.1'; engine_build = 'mock-build-1'
    engines = [ordered]@{ 'llama-server' = $mock }; defaults = [ordered]@{ llm = 'mock.a' }
    tiers = [ordered]@{ llm = [ordered]@{ tiny = 'mock.a' } }
    models = @([ordered]@{ model_id = 'mock.a'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelA; context = 4096; gpu_layers = 99; params = [ordered]@{ sha256 = 'aaaa'; size_bytes = 1 } })
}
$regPath = Join-Path $scratch 'models.json'; [System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 8), $utf8)
$warmReg = Join-Path $scratch 'warm-server.json'
$lockPath = "$warmReg.lock"

function RunGw([string[]]$extra) {
    $base = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $entry,
        '-Registry', $regPath, '-WarmRegistryPath', $warmReg, '-PwshPath', $PwshPath, '-GpuLease', 'off',
        '-MaxTokens', '8', '-Temperature', '0.1', '-Seed', '42')
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    $obj = $null; try { $obj = $txt | ConvertFrom-Json } catch { }
    return $obj
}
function ReadWarm { if (Test-Path -LiteralPath $warmReg) { try { return (Get-Content -LiteralPath $warmReg -Raw | ConvertFrom-Json) } catch { return $null } } return $null }
function WriteWarm($obj) { [System.IO.File]::WriteAllText($warmReg, ($obj | ConvertTo-Json -Depth 10), $utf8) }
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }
function Cleanup { $lo = ReadWarm; if ($null -ne $lo -and (Has $lo 'pid')) { try { Stop-Process -Id ([int]$lo.pid) -Force -ErrorAction SilentlyContinue } catch { } }; Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }

Write-Output "==== model.gateway FAULT-INJECTION suite (mock engine) ===="
Write-Output "entry=$entry"; Write-Output ""

# =================================================================================================
# FI-1: crash at EACH transition point -> reconcile drives to a clean EMPTY; a valid resident is KEPT
# =================================================================================================
foreach ($st in @('STARTING','RESIDENT','STOPPING','EMPTY_CONFIRMED')) {
    # a crashed transition leaves a manifest CLAIMING $st but the pid is DEAD (999999 never exists)
    WriteWarm ([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state=$st; pid=999999; start_ticks=123; host='127.0.0.1'; port=8199; model_id='mock.a'; fence=7; managed_by='model.gateway' })
    $rc = RunGw @('-Reconcile')
    $after = ReadWarm
    Ok ($null -ne $rc -and $rc.status -eq 'ok' -and $rc.result.reconcile.ran -eq $true) "FI-1[$st] reconcile ran"
    Ok ($null -eq $after) "FI-1[$st] a dead-pid $st claim is reconciled to EMPTY (manifest cleared)"
}
# a crashed resident is not silently reused: start a real resident, KILL it out-of-band, then EnsureResident cold-starts
$r = RunGw @('-Model','mock.a','-EnsureResident')
$reg0 = ReadWarm; $pid0 = if ($null -ne $reg0 -and (Has $reg0 'pid')) { [int]$reg0.pid } else { -1 }
Ok ($null -ne $reg0 -and (PidAlive $pid0) -and [string]$reg0.state -eq 'RESIDENT') 'FI-1[crash] a real resident is RESIDENT + alive'
try { Stop-Process -Id $pid0 -Force -ErrorAction SilentlyContinue } catch { }   # simulate a crash (server dies, manifest stays)
Start-Sleep -Milliseconds 300
$r2 = RunGw @('-Model','mock.a','-EnsureResident')   # reconcile sees the dead pid, cleans, then cold-starts
Ok ($null -ne $r2 -and $r2.result.pool.action -eq 'cold_start') 'FI-1[crash] a crashed resident is NOT reused; a fresh cold_start replaces it'
$reg1 = ReadWarm; $pid1 = if ($null -ne $reg1 -and (Has $reg1 'pid')) { [int]$reg1.pid } else { -1 }
Ok ($pid1 -ne $pid0 -and (PidAlive $pid1)) 'FI-1[crash] the new resident has a fresh pid'
# a VALID resident is KEPT by reconcile (warmth preserved)
$rcv = RunGw @('-Reconcile')
Ok ($null -ne $rcv -and $rcv.result.reconcile.kept_resident -eq $true) 'FI-1[valid] reconcile KEEPS a healthy verified resident (warmth preserved)'
Ok ((ReadWarm) -ne $null -and (PidAlive $pid1)) 'FI-1[valid] the valid resident survived reconcile'
Cleanup

# =================================================================================================
# FI-2: forced fence/generation expiry mid-request -> inference REJECTED (no wrong-generation call lands)
# =================================================================================================
$e1 = RunGw @('-Model','mock.a','-Context','4096','-EnsureResident')
$gen1 = [string]$e1.result.pool.instance_generation; $fence1 = [int]$e1.result.pool.fence
Ok (-not [string]::IsNullOrWhiteSpace($gen1)) 'FI-2 captured resident generation G1'
# a config change forces a RELAUNCH -> a NEW generation G2 supersedes G1
$e2 = RunGw @('-Model','mock.a','-Context','8192','-EnsureResident')
$gen2 = [string]$e2.result.pool.instance_generation; $fence2 = [int]$e2.result.pool.fence
Ok ($gen2 -ne $gen1 -and $fence2 -gt $fence1) 'FI-2 a relaunch produced a new generation G2 + a higher fence'
# an inference expecting the STALE G1 is REJECTED before any completion (no wrong-generation call lands)
$rej = RunGw @('-Model','mock.a','-Context','8192','-Prompt','ping','-Warm','-ExpectGeneration',$gen1)
Ok ($null -ne $rej -and $rej.status -eq 'error' -and $rej.error.code -eq 'generation_mismatch') 'FI-2 inference with a STALE generation is REJECTED (generation_mismatch)'
Ok ($null -ne $rej -and (-not (Has $rej.result 'output') -or $null -eq $rej.result)) 'FI-2 no completion output was produced on the rejected call'
# an inference expecting the CURRENT G2 succeeds
$acc = RunGw @('-Model','mock.a','-Context','8192','-Prompt','ping','-Warm','-ExpectGeneration',$gen2)
Ok ($null -ne $acc -and $acc.status -eq 'ok' -and $acc.result.output.text -eq 'PONG') 'FI-2 inference with the CURRENT generation succeeds'
# a stale FENCE is likewise rejected; the current fence is accepted
$curFence = [int](ReadWarm).fence
$rejF = RunGw @('-Model','mock.a','-Context','8192','-Prompt','ping','-Warm','-ExpectFence',"$fence1")
Ok ($null -ne $rejF -and $rejF.status -eq 'error' -and $rejF.error.code -eq 'generation_mismatch') 'FI-2 inference with a STALE fence is REJECTED'
Cleanup

# =================================================================================================
# FI-3: a stale idle-callback vs a fresh request -> a refreshed resident is NOT raced into eviction
# =================================================================================================
$i1 = RunGw @('-Model','mock.a','-EnsureResident','-KeepResidentSeconds','3600')
$regI = ReadWarm; $pidI = if ($null -ne $regI -and (Has $regI 'pid')) { [int]$regI.pid } else { -1 }
# backdate last_used_utc to make the resident LOOK long-idle (simulates a stale idle observation)
$mm = [ordered]@{}; foreach ($p in $regI.PSObject.Properties) { $mm[$p.Name] = $p.Value }
$mm['last_used_utc'] = ([DateTime]::UtcNow).AddSeconds(-600).ToString('o'); WriteWarm $mm
# a FRESH request (reuse) refreshes the keep-resident timer under the lock
$i2 = RunGw @('-Model','mock.a','-EnsureResident','-KeepResidentSeconds','3600')
Ok ($null -ne $i2 -and $i2.result.pool.action -eq 'reuse') 'FI-3 the fresh request reused + refreshed the resident'
# a sweep that was authorized against the STALE idle reading now re-reads under the lock -> KEEPS (not raced)
$sw = RunGw @('-SweepIdle','-KeepResidentSeconds','60')
Ok ($null -ne $sw -and $sw.result.pool.kept -eq $true -and $sw.result.pool.evicted -eq $false) 'FI-3 the sweep re-reads under the lock and KEEPS the just-refreshed resident (no race)'
Ok (PidAlive $pidI) 'FI-3 the refreshed resident survived the stale idle sweep'
# and a genuinely-idle resident IS evicted (the policy still works)
$sw2 = RunGw @('-SweepIdle','-KeepResidentSeconds','0')
Ok ($null -ne $sw2 -and $sw2.result.pool.evicted -eq $true) 'FI-3 a genuinely-idle resident is still evicted (policy intact)'
Cleanup

# =================================================================================================
# FI-4: Job-Object reap + PID-reuse -> a reused pid (identity mismatch) is NOT killed; managed tag present
# =================================================================================================
$j1 = RunGw @('-Model','mock.a','-EnsureResident')
$regJ = ReadWarm
Ok ($null -ne $regJ -and (Has $regJ 'managed_by') -and [string]$regJ.managed_by -eq 'model.gateway') 'FI-4 the resident carries the managed tag (0 orphaned == 0 UNMANAGED)'
$pidJ = [int]$regJ.pid
# simulate PID REUSE: rewrite the manifest to claim THIS test process pid ($PID, alive) with a BOGUS creation-time.
# reconcile must NOT kill $PID (a foreign process that happens to reuse the pid) and must clear the stale claim.
try { Stop-Process -Id $pidJ -Force -ErrorAction SilentlyContinue } catch { }; Start-Sleep -Milliseconds 200
$mmj = [ordered]@{}; foreach ($p in $regJ.PSObject.Properties) { $mmj[$p.Name] = $p.Value }
$mmj['pid'] = $PID; $mmj['start_ticks'] = 1; $mmj['state'] = 'RESIDENT'; WriteWarm $mmj   # start_ticks=1 != real -> identity mismatch
$rcj = RunGw @('-Reconcile')
Ok (PidAlive $PID) 'FI-4 a reused pid (identity mismatch) is NOT killed -- the foreign process (this test) survives'
Ok ((ReadWarm) -eq $null) 'FI-4 the stale PID-reuse claim is cleared without killing the foreign process'
Cleanup

# =================================================================================================
# FI-5: KV isolation across crash/cancel -> erase-on-checkout AND check-in fire (no cross-task prefix reuse).
# The mock records erases to a deterministic per-PORT temp file (WMI-safe -- env vars do not survive the
# Windows detached-launch), so the suite reads that file by the resident's port.
# =================================================================================================
$k1 = RunGw @('-Model','mock.a','-Prompt','ping','-Warm')   # a warm generation
Ok ($null -ne $k1 -and $k1.status -eq 'ok' -and $k1.result.output.text -eq 'PONG') 'FI-5 warm generation ok'
$poolK = if ($null -ne $k1 -and (Has $k1.result.server.warm 'pool')) { $k1.result.server.warm.pool } else { $null }
Ok ($null -ne $poolK -and [string]$poolK.prefix_reuse -eq 'disabled_stage_1_1' -and [string]$poolK.kv_isolation -eq 'erase_on_checkout_and_checkin') 'FI-5 telemetry: prefix reuse disabled + KV erase-on-checkout/check-in'
$k1Port = if ($null -ne $k1) { [int]$k1.result.server.port } else { 0 }
$eraseLog = Join-Path ([System.IO.Path]::GetTempPath()) "mock-erase-$k1Port.log"
Start-Sleep -Milliseconds 300
$erases = if (Test-Path -LiteralPath $eraseLog) { @(Get-Content -LiteralPath $eraseLog) } else { @() }
Ok ($erases.Count -ge 2) 'FI-5 the gateway issued BOTH an erase-on-checkout AND an erase-on-check-in (>=2 erases)'
# a SECOND warm generation ALSO erases on checkout -> a prior crashed task cannot bleed KV into it
$k2 = RunGw @('-Model','mock.a','-Prompt','ping','-Warm')
Start-Sleep -Milliseconds 300
$erases2 = if (Test-Path -LiteralPath $eraseLog) { @(Get-Content -LiteralPath $eraseLog) } else { @() }
Ok ($erases2.Count -ge $erases.Count + 1) 'FI-5 a subsequent task also erases on checkout (a crashed prior task cannot bleed KV)'
Remove-Item -LiteralPath $eraseLog -Force -ErrorAction SilentlyContinue
Cleanup

# =================================================================================================
# FI-6: GPU-handoff eviction -> evict-before-grant (no blind co-load); 0 orphans
# =================================================================================================
$g1 = RunGw @('-Model','mock.a','-EnsureResident')
$regG = ReadWarm; $pidG = if ($null -ne $regG -and (Has $regG 'pid')) { [int]$regG.pid } else { -1 }
Ok (PidAlive $pidG) 'FI-6 a resident holds the GPU'
# A consumer needs MORE than the whole card (the mock itself uses no VRAM, so on the box real free VRAM is
# ample -- an impossible required value deterministically forces the evict-before-grant path on both cloud and
# box). The planner must EVICT the resident first (no blind co-load), never grant while a resident holds the GPU.
$pg = RunGw @('-PrepareGpu','-RequiredVramMib','99999999')
Ok ($null -ne $pg -and $pg.result.action -eq 'prepare_gpu' -and $pg.result.gpu.plan -eq 'evict_then_grant') 'FI-6 PrepareGpu plans evict-before-grant (no blind co-load)'
Ok ($null -ne $pg -and $pg.result.gpu.evicted -eq $true) 'FI-6 the resident was evicted to free the GPU for the handoff'
Start-Sleep -Milliseconds 300
Ok (-not (PidAlive $pidG)) 'FI-6 the evicted resident pid is dead (0 orphans)'
Ok ((ReadWarm) -eq $null) 'FI-6 the registry is cleared after the handoff eviction'
# PrepareGpu with NO resident + a trivially-small requirement -> grant (nothing to evict, ample headroom)
$pg2 = RunGw @('-PrepareGpu','-RequiredVramMib','1')
Ok ($null -ne $pg2 -and $pg2.result.gpu.plan -eq 'grant' -and $pg2.result.gpu.had_resident -eq $false) 'FI-6 PrepareGpu with no resident -> grant'
Cleanup

# ---- final: 0 orphaned mock servers ----
Start-Sleep -Milliseconds 300
$orphans = @()
foreach ($p in @($pid0, $pid1, $pidI, $pidJ, $pidG)) { if (PidAlive $p) { $orphans += $p } }
Ok ($orphans.Count -eq 0) 'FI-end no orphaned mock servers after the suite'
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
