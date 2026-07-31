#requires -Version 7.0
# OFF-MACHINE core tests for the DURABLE gateway supervisor (lib/Supervisor.psm1; WARM_POOL_DESIGN section 10
# residual (a), durable finding 5). PURE + SEAM: the control protocol, the attach handshake, the poll/dispatch
# loop, the residency state machine (reuse / evict+reload) driven by an INJECTED launcher + stub seams, reconcile
# (verify-the-claim), fence/generation rejection, the GPU-handoff planner, and the Windows Job-Object SEAM
# (degrades to supported=$false off-Windows, never throws). Runs green on the cloud gate AND, unchanged, live
# via the executor. No GPU / no real llama-server (a cheap cross-platform 'sleeper' process stands in for a
# launched server so the state machine is exercised without HTTP). ASCII-only. Exit 0 iff all pass.
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'lib/PoolManager.psm1') -Force
Import-Module (Join-Path $moduleRoot 'lib/Supervisor.psm1') -Force

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-sup-core-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$warmReg = Join-Path $scratch 'warm-server.json'
$lockPath = "$warmReg.lock"
$spawned = New-Object System.Collections.Generic.List[int]
function Spawn-Sleeper {
    $p = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 120') -PassThru
    $script:spawned.Add([int]$p.Id)
    Start-Sleep -Milliseconds 150
    return $p
}
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }
function Cleanup-Spawned { foreach ($sp in $script:spawned) { try { Stop-Process -Id $sp -Force -ErrorAction SilentlyContinue } catch { } } }

# stub seams
$HealthTrue = { param($h,$p) return $true }
$StartTicks = { param([int]$procId) try { return [long]((Get-Process -Id $procId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 } }
$SockNull   = { param($port) return $null }        # undeterminable -> advisory, never a hard fail
$StopReal   = { param($reg,$liveness) if ($null -eq $reg -or -not ($reg.PSObject.Properties.Name -contains 'pid')) { return $true }; if (-not $liveness.alive) { return $true }; if (-not $liveness.identity_ok) { return $false }; $procId=[int]$reg.pid; try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch { }; for ($i=0;$i -lt 30;$i++){ if (-not (PidAlive $procId)) { return $true }; Start-Sleep -Milliseconds 100 }; return $false }

Write-Output "==== gateway SUPERVISOR core suite (pure + seam) ===="
Write-Output "module=$(Join-Path $moduleRoot 'lib/Supervisor.psm1')"; Write-Output ""

# =================================================================================================
# S1 control protocol: request/response encode + decode + validate + atomic round-trip
# =================================================================================================
$req = New-SupervisorRequest -Op 'ensure_resident' -Params @{ model='mock.a'; context=4096 }
Ok ([string]$req.schema -eq $SUP_REQ_SCHEMA) 'S1 request has the request schema id'
Ok ([string]$req.op -eq 'ensure_resident' -and $req.request_id.Length -ge 8) 'S1 request carries op + a request_id'
Ok ([string]$req.params.model -eq 'mock.a' -and [int]$req.params.context -eq 4096) 'S1 request preserves params'
Ok ((Test-SupervisorRequestValid $req).valid) 'S1 a well-formed request validates'
$badOp = New-SupervisorRequest -Op 'frobnicate'
Ok (-not (Test-SupervisorRequestValid $badOp).valid) 'S1 an unknown op is rejected'
$badSchema = [pscustomobject]@{ schema='wrong'; request_id='x'; op='ping' }
Ok (-not (Test-SupervisorRequestValid $badSchema).valid) 'S1 a wrong schema is rejected'
$resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ a=1 }) -SupervisorPid 123 -SupervisorGeneration 'g1'
Ok ([string]$resp.schema -eq $SUP_RESP_SCHEMA -and [string]$resp.request_id -eq [string]$req.request_id -and [bool]$resp.ok) 'S1 response echoes request_id + ok'
$paths0 = Get-SupervisorPaths -Root (Join-Path $scratch 'sup0')
Initialize-SupervisorDirs -Paths $paths0
$rp = Write-SupervisorRequest -ReqDir $paths0.req_dir -Request $req
$rr = Read-SupervisorRequestFile $rp
Ok ($null -ne $rr -and [string]$rr.request_id -eq [string]$req.request_id) 'S1 request round-trips through the control dir'
$sp = Write-SupervisorResponse -RespDir $paths0.resp_dir -Response $resp
$sr = Read-SupervisorResponseFile $sp
Ok ($null -ne $sr -and [bool]$sr.ok -and [int]$sr.result.a -eq 1) 'S1 response round-trips through the control dir'

# =================================================================================================
# S2 paths
# =================================================================================================
$paths = Get-SupervisorPaths -Root (Join-Path $scratch 'sup') -WarmRegistryPath $warmReg
Ok ($paths.manifest -like '*supervisor.json' -and $paths.req_dir -like '*control*req' -and [string]$paths.warm_registry -eq $warmReg) 'S2 paths resolve (manifest/req/resp/warm)'

# =================================================================================================
# S3 supervisor liveness + heartbeat
# =================================================================================================
Ok (-not (Test-SupervisorLiveness -Manifest $null).running) 'S3 null manifest -> not running'
$now = [DateTime]::UtcNow
$liveMan = [ordered]@{ pid=$PID; start_ticks=([long]((Get-Process -Id $PID).StartTime.Ticks)); state='RUNNING'; heartbeat_utc=$now.ToString('o') }
$lv = Test-SupervisorLiveness -Manifest $liveMan -StartTicksProbe $StartTicks
Ok ($lv.alive -and $lv.identity_ok -and $lv.heartbeat_fresh -and $lv.running) 'S3 alive + matching creation-time + fresh heartbeat -> running'
$badTicks = [ordered]@{ pid=$PID; start_ticks=1; state='RUNNING'; heartbeat_utc=$now.ToString('o') }
$lb = Test-SupervisorLiveness -Manifest $badTicks -StartTicksProbe $StartTicks
Ok ($lb.alive -and -not $lb.identity_ok -and -not $lb.running) 'S3 PID-reuse (creation-time mismatch) -> not running'
$deadMan = [ordered]@{ pid=999999; start_ticks=5; state='RUNNING'; heartbeat_utc=$now.ToString('o') }
Ok (-not (Test-SupervisorLiveness -Manifest $deadMan -StartTicksProbe $StartTicks).alive) 'S3 dead pid -> not alive'
$staleMan = [ordered]@{ pid=$PID; start_ticks=([long]((Get-Process -Id $PID).StartTime.Ticks)); state='RUNNING'; heartbeat_utc=$now.AddSeconds(-600).ToString('o') }
Ok (-not (Test-SupervisorHeartbeatFresh -Manifest $staleMan -MaxAgeSeconds 30)) 'S3 a 10-min-old heartbeat is stale'

# =================================================================================================
# S4 Windows Job Object seam (degrades off-Windows; never throws)
# =================================================================================================
$job = New-GatewayJobObject
Ok ($null -ne $job -and $job.Contains('supported') -and $job.Contains('kill_on_close') -and [bool]$job['kill_on_close']) 'S4 New-GatewayJobObject returns a job descriptor (kill_on_close=true)'
if ($IsWindows) {
    Ok ([bool]$job.supported) 'S4 [Windows] Job Object is supported (real handle)'
    if ([bool]$job.supported) { Ok ((Add-ProcessToGatewayJob -Job $job -ProcessId $PID) -is [bool]) 'S4 [Windows] Add-ProcessToGatewayJob returns a bool'; [void](Close-GatewayJob -Job $job) }
} else {
    Ok (-not [bool]$job.supported -and [string]$job.reason -eq 'not_windows') 'S4 [off-Windows] Job Object degrades to supported=false (reason=not_windows)'
    Ok ((Add-ProcessToGatewayJob -Job $job -ProcessId 99999) -eq $false) 'S4 [off-Windows] Add-to-job is a no-op false (never throws)'
    Ok ((Close-GatewayJob -Job $job) -eq $false) 'S4 [off-Windows] Close-job is a no-op false (never throws)'
}

# =================================================================================================
# S5 poll/dispatch (server side) with a mock handler map
# =================================================================================================
$pp = Get-SupervisorPaths -Root (Join-Path $scratch 'sup5')
Initialize-SupervisorDirs -Paths $pp
$handlers = @{ echo = { param($r) return [ordered]@{ got = [string]$r.params.msg } }; boom = { param($r) throw [PSCustomObject]@{ code='kaboom'; message='handler blew up' } } }
# NOTE: 'echo'/'boom' are not in SUP_OPS, so we validate the dispatch of KNOWN ops + error paths instead.
# valid op with a handler:
$reqEnsure = New-SupervisorRequest -Op 'status'
[void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqEnsure)
$h2 = @{ status = { param($r) return [ordered]@{ ok_marker = 'served' } } }
$poll = Invoke-SupervisorPollOnce -Paths $pp -Handlers $h2 -SupervisorPid 7 -SupervisorGeneration 'g'
$respPath = Join-Path $pp.resp_dir "$($reqEnsure.request_id).json"
$got = Read-SupervisorResponseFile $respPath
Ok ($poll.count -eq 1 -and $null -ne $got -and [bool]$got.ok -and [string]$got.result.ok_marker -eq 'served') 'S5 a known op is dispatched to its handler + a response is written'
Ok (-not (Test-Path -LiteralPath (Join-Path $pp.req_dir "$($reqEnsure.request_id).json"))) 'S5 the request file is consumed (deleted) after handling'
# ping (built-in):
$reqPing = New-SupervisorRequest -Op 'ping'; [void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqPing)
$poll2 = Invoke-SupervisorPollOnce -Paths $pp -Handlers @{} -SupervisorPid 7 -SupervisorGeneration 'g'
$pong = Read-SupervisorResponseFile (Join-Path $pp.resp_dir "$($reqPing.request_id).json")
Ok ($null -ne $pong -and [bool]$pong.ok -and [bool]$pong.result.pong) 'S5 built-in ping -> pong'
# shutdown (built-in) -- i23 MF4: authenticated admin op requires the supervisor generation:
$reqSd = New-SupervisorRequest -Op 'shutdown' -ExpectGeneration 'g'; [void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqSd)
$poll3 = Invoke-SupervisorPollOnce -Paths $pp -Handlers @{} -SupervisorPid 7 -SupervisorGeneration 'g'
Ok ($poll3.shutdown -eq $true) 'S5 shutdown op (with the matching generation) sets the shutdown flag'
# a shutdown WITHOUT the generation is REFUSED (not a plain dispatch)
$reqSdBad = New-SupervisorRequest -Op 'shutdown'; [void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqSdBad)
$poll3b = Invoke-SupervisorPollOnce -Paths $pp -Handlers @{} -SupervisorPid 7 -SupervisorGeneration 'g'
$sdBadResp = Read-SupervisorResponseFile (Join-Path $pp.resp_dir "$($reqSdBad.request_id).json")
Ok ($poll3b.shutdown -eq $false -and $null -ne $sdBadResp -and [string]$sdBadResp.error.code -eq 'admin_auth_required') 'S5 an UNauthenticated shutdown is REFUSED (admin_auth_required)'
# handler throws a structured error -> ok=false with the code:
$reqBoom = New-SupervisorRequest -Op 'ensure_resident'; [void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqBoom)
$poll4 = Invoke-SupervisorPollOnce -Paths $pp -Handlers @{ ensure_resident = { param($r) throw [PSCustomObject]@{ code='kaboom'; message='blew up' } } } -SupervisorPid 7 -SupervisorGeneration 'g'
$boomResp = Read-SupervisorResponseFile (Join-Path $pp.resp_dir "$($reqBoom.request_id).json")
Ok ($null -ne $boomResp -and -not [bool]$boomResp.ok -and [string]$boomResp.error.code -eq 'kaboom') 'S5 a handler fault becomes a structured error response (loop survives)'
# an unsupported op (valid schema, no handler):
$reqNo = New-SupervisorRequest -Op 'evict'; [void](Write-SupervisorRequest -ReqDir $pp.req_dir -Request $reqNo)
$poll5 = Invoke-SupervisorPollOnce -Paths $pp -Handlers @{} -SupervisorPid 7 -SupervisorGeneration 'g'
$noResp = Read-SupervisorResponseFile (Join-Path $pp.resp_dir "$($reqNo.request_id).json")
Ok ($null -ne $noResp -and -not [bool]$noResp.ok -and [string]$noResp.error.code -eq 'unsupported_op') 'S5 a valid op with no handler -> unsupported_op'

# =================================================================================================
# S6 client attach handshake: unavailable (no supervisor) + timeout (running manifest, nobody serving)
# =================================================================================================
$pc = Get-SupervisorPaths -Root (Join-Path $scratch 'sup6') -WarmRegistryPath (Join-Path $scratch 'w6.json')
$un = Send-SupervisorRequest -Paths $pc -Op 'status' -TimeoutMs 500 -StartTicksProbe $StartTicks
Ok (-not $un.ok -and [string]$un.error.code -eq 'supervisor_unavailable') 'S6 no supervisor -> supervisor_unavailable (caller degrades)'
Initialize-SupervisorDirs -Paths $pc
[void](Write-SupervisorManifest -Path $pc.manifest -Obj ([ordered]@{ schema=$SUP_MANIFEST_SCHEMA; pid=$PID; start_ticks=([long]((Get-Process -Id $PID).StartTime.Ticks)); state='RUNNING'; heartbeat_utc=([DateTime]::UtcNow.ToString('o')) }))
$to = Send-SupervisorRequest -Paths $pc -Op 'status' -TimeoutMs 800 -PollMs 50 -StartTicksProbe $StartTicks
Ok (-not $to.ok -and [string]$to.error.code -eq 'supervisor_timeout') 'S6 running manifest but nobody serving -> supervisor_timeout'
Ok (@(Get-ChildItem -LiteralPath $pc.req_dir -Filter *.json -ErrorAction SilentlyContinue).Count -eq 0) 'S6 the timed-out request is cleaned up (no leaked request file)'

# =================================================================================================
# S7 reconcile (verify-the-claim) with stub seams -- no real server
# =================================================================================================
Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue
$r0 = Invoke-SupervisorReconcile -WarmRegPath $warmReg -LockPath $lockPath -StartTicksProbe $StartTicks -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe $StopReal
Ok ([string]$r0.action -eq 'no_manifest') 'S7 reconcile: no manifest -> no_manifest'
# dead-pid RESIDENT claim -> reconciled to EMPTY (manifest cleared)
[System.IO.File]::WriteAllText($warmReg, (([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=999999; start_ticks=5; port=8123; fence=3 }) | ConvertTo-Json), $utf8)
$r1 = Invoke-SupervisorReconcile -WarmRegPath $warmReg -LockPath $lockPath -StartTicksProbe $StartTicks -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe $StopReal
Ok ([string]$r1.action -eq 'reconciled_from_RESIDENT' -and -not (Test-Path -LiteralPath $warmReg)) 'S7 reconcile: a dead-pid RESIDENT claim -> cleared to EMPTY'
# valid resident (this process stands in as an alive+identified server) -> KEPT
$goodTicks = [long]((Get-Process -Id $PID).StartTime.Ticks)
[System.IO.File]::WriteAllText($warmReg, (([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$PID; start_ticks=$goodTicks; port=8124; fence=4 }) | ConvertTo-Json), $utf8)
$r2 = Invoke-SupervisorReconcile -WarmRegPath $warmReg -LockPath $lockPath -StartTicksProbe $StartTicks -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe $StopReal
Ok ($r2.kept_resident -eq $true -and (Test-Path -LiteralPath $warmReg)) 'S7 reconcile: a healthy verified resident is KEPT (warmth preserved)'
# PID-reuse claim (alive pid but creation-time mismatch) -> cleared WITHOUT killing the foreign process
[System.IO.File]::WriteAllText($warmReg, (([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$PID; start_ticks=1; port=8125; fence=5 }) | ConvertTo-Json), $utf8)
$r3 = Invoke-SupervisorReconcile -WarmRegPath $warmReg -LockPath $lockPath -StartTicksProbe $StartTicks -SocketOwnerProbe $SockNull -HealthProbe $HealthTrue -StopProbe $StopReal
Ok ((PidAlive $PID) -and -not (Test-Path -LiteralPath $warmReg)) 'S7 reconcile: a PID-reuse claim is cleared WITHOUT killing the foreign process'

# =================================================================================================
# S8 residency STATE MACHINE via Invoke-SupervisorEnsureResident (injected launcher spawns a real sleeper;
#    stub health; the state machine + fencing + CanServe + swap accounting are exercised without a real llama-server)
# =================================================================================================
Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue
$fakeModel = [pscustomobject]@{ model_id='mock.a'; params=[pscustomobject]@{ sha256='aaaa'; size_bytes=1 } }
$fakeReg   = [pscustomobject]@{ engine_build='mock-build-1' }
function Cfg([int]$ctx) { return (Get-ResidentConfig $fakeModel $fakeReg 99 $ctx $true 'f16' 'f16' $false 1 'exehash-1') }
$launcher = {
    param($ReqConfig, [int]$PortHint)
    $p = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 120') -PassThru
    $script:spawned.Add([int]$p.Id); Start-Sleep -Milliseconds 150
    $ticks = 0; try { $ticks = [long]((Get-Process -Id $p.Id).StartTime.Ticks) } catch { }
    return [ordered]@{ pid=[int]$p.Id; start_ticks=$ticks; instance_generation=(New-InstanceGeneration); host='127.0.0.1'; port=8890; job_owned=$false }
}.GetNewClosure()
$meta = @{ model_id='mock.a'; host='127.0.0.1'; port_hint=8890; managed_by='test'; keep_resident_seconds=90 }
$e1 = Invoke-SupervisorEnsureResident -WarmRegPath $warmReg -LockPath $lockPath -ReqConfig (Cfg 4096) -ModelMeta $meta -Launcher $launcher -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicks
Ok ([string]$e1.action -eq 'cold_start' -and $e1.started_new -and $e1.health_ok -and (PidAlive $e1.pid)) 'S8 first ensure -> cold_start (server launched + RESIDENT + alive)'
$man1 = Read-PoolManifest $warmReg
Ok ($null -ne $man1 -and [string]$man1.state -eq 'RESIDENT' -and [int]$man1.fence -eq 1) 'S8 manifest published state=RESIDENT fence=1'
$pidCold = [int]$e1.pid; $genCold = [string]$e1.instance_generation
# same config -> ~1 ms REUSE (same pid, fence unchanged, no new spawn)
$before = $script:spawned.Count
$e2 = Invoke-SupervisorEnsureResident -WarmRegPath $warmReg -LockPath $lockPath -ReqConfig (Cfg 4096) -ModelMeta $meta -Launcher $launcher -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicks
Ok ([string]$e2.action -eq 'reuse' -and [int]$e2.pid -eq $pidCold -and [int]$e2.fence -eq 1 -and $script:spawned.Count -eq $before) 'S8 same config -> REUSE (same pid, fence unchanged, NO respawn)'
# generation rejection: a STALE generation is rejected against the live manifest
$gmStale = Test-GenerationMatch (Read-PoolManifest $warmReg) 'deadbeefstalegen'
Ok (-not $gmStale.match -and [string]$gmStale.reason -eq 'generation_mismatch') 'S8 a stale generation is rejected (generation_mismatch)'
$gmOk = Test-GenerationMatch (Read-PoolManifest $warmReg) $genCold
Ok ($gmOk.match) 'S8 the current generation matches'
# different config (context 4096 -> 8192; resident 4096 canNOT serve 8192) -> EVICT + RELOAD
$e3 = Invoke-SupervisorEnsureResident -WarmRegPath $warmReg -LockPath $lockPath -ReqConfig (Cfg 8192) -ModelMeta $meta -Launcher $launcher -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicks
Ok ([string]$e3.action -eq 'evict_reload' -and $e3.evicted -eq $true -and [int]$e3.pid -ne $pidCold) 'S8 a capacity-exceeding request -> EVICT + RELOAD (new pid)'
Ok ([int]$e3.fence -eq 2 -and [int]$e3.swap_count -eq 1) 'S8 the swap bumps the fence (2) + swap_count (1)'
Ok (-not (PidAlive $pidCold)) 'S8 the evicted resident pid is dead (0 orphans from the swap)'
# ForceReload on the same config still swaps
$e4 = Invoke-SupervisorEnsureResident -WarmRegPath $warmReg -LockPath $lockPath -ReqConfig (Cfg 8192) -ModelMeta $meta -Launcher $launcher -HealthProbe $HealthTrue -StopProbe $StopReal -SocketOwnerProbe $SockNull -StartTicksProbe $StartTicks -ForceReload
Ok ([string]$e4.action -eq 'evict_reload' -and [int]$e4.fence -eq 3) 'S8 -ForceReload evicts+reloads even when the resident could serve'
# evict via Invoke-SupervisorEvict -> manifest cleared, pid dead
$ev = Invoke-SupervisorEvict -WarmRegPath $warmReg -LockPath $lockPath -StopProbe $StopReal -StartTicksProbe $StartTicks
Ok ($ev.evicted -eq $true -and -not (Test-Path -LiteralPath $warmReg)) 'S8 Invoke-SupervisorEvict tears down the resident + clears the manifest'

# =================================================================================================
# S9 GPU-handoff planner (evict-before-grant) via Invoke-SupervisorPrepareGpu with stub VRAM
# =================================================================================================
# no resident + ample free VRAM -> grant
$pg1 = Invoke-SupervisorPrepareGpu -WarmRegPath $warmReg -LockPath $lockPath -RequiredVramMib 1000 -SafetyMib 512 -VramProbe { return 9000 } -StopProbe $StopReal -StartTicksProbe $StartTicks
Ok ([string]$pg1.plan -eq 'grant' -and $pg1.had_resident -eq $false -and $pg1.ready -eq $true) 'S9 prepare_gpu: no resident + ample VRAM -> grant'
# a resident + short headroom -> evict_then_grant (the resident is evicted before granting)
$sl = Spawn-Sleeper; $slTicks = [long]((Get-Process -Id $sl.Id).StartTime.Ticks)
[System.IO.File]::WriteAllText($warmReg, (([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$sl.Id; start_ticks=$slTicks; port=8126; fence=9 }) | ConvertTo-Json), $utf8)
$pg2 = Invoke-SupervisorPrepareGpu -WarmRegPath $warmReg -LockPath $lockPath -RequiredVramMib 8000 -SafetyMib 512 -VramProbe { return 1000 } -StopProbe $StopReal -StartTicksProbe $StartTicks
Ok ([string]$pg2.plan -eq 'evict_then_grant' -and $pg2.evicted -eq $true -and -not (PidAlive $sl.Id)) 'S9 prepare_gpu: resident + short headroom -> evict_then_grant (resident evicted, no blind co-load)'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'S9 prepare_gpu clears the manifest after the handoff eviction'

# ---- cleanup ----
Cleanup-Spawned
Start-Sleep -Milliseconds 200
$orphans = @(); foreach ($sp in $script:spawned) { if (PidAlive $sp) { $orphans += $sp } }
Ok ($orphans.Count -eq 0) 'S-end no orphaned sleeper processes after the suite'
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
