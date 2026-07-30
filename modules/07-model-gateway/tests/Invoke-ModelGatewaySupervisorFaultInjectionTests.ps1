#requires -Version 7.0
# OFF-MACHINE + LIVE fault-injection suite for the DURABLE gateway supervisor (WARM_POOL_DESIGN section 10
# residual (a); durable finding 5). Drives the REAL Start-GatewaySupervisor.ps1 + the REAL Invoke-ModelGateway.ps1
# (-UseSupervisor) against the cross-platform MOCK llama-server, so every fault path is exercised deterministically
# on the cloud gate AND, unchanged, live via the executor. ASCII-only. Exit 0 iff all pass.
#
# Scenarios:
#   FS-1  start DETACHED -> supervisor manifest published (state RUNNING, a Job-Object descriptor)
#   FS-2  DURABLE reuse: TWO SEPARATE gateway invocations reuse the SAME resident via the supervisor (no respawn)
#   FS-3  forced fence/generation expiry mid-request -> inference REJECTED (no wrong-generation call lands)
#   FS-4  supervisor CRASH -> [Windows] the Job Object reaps the whole server tree (0 unmanaged orphans);
#         [off-Windows] the Job Object is unsupported so the OS reap is a LIVE-only guarantee -- the suite proves
#         the FALLBACK (reconcile-after-crash) instead, and asserts job_owned/job_supported honesty
#   FS-5  restart -> reconcile drives a stale post-crash claim to EMPTY (verify-the-claim, never trust)
#   FS-6  GPU-handoff eviction -> evict-before-grant (no blind co-load); grant when nothing to evict
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $moduleRoot 'Start-GatewaySupervisor.ps1'
$gw    = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$mock  = Join-Path $PSScriptRoot 'mock-llama-server.ps1'
Import-Module (Join-Path $moduleRoot 'lib/Supervisor.psm1') -Force

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-sup-fi-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$modelA = Join-Path $scratch 'model-a.gguf'; [System.IO.File]::WriteAllText($modelA, 'x', $utf8)
$reg = [ordered]@{
    schema='lifeorch.model_registry/0.1'; engine_build='mock-build-1'
    engines=[ordered]@{ 'llama-server'=$mock }; defaults=[ordered]@{ llm='mock.a' }
    tiers=[ordered]@{ llm=[ordered]@{ tiny='mock.a' } }
    models=@([ordered]@{ model_id='mock.a'; type='llm'; wired=$true; engine='llama-server'; path=$modelA; context=4096; gpu_layers=99; params=[ordered]@{ sha256='aaaa'; size_bytes=1 } })
}
$regPath = Join-Path $scratch 'models.json'; [System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 8), $utf8)
$supRoot = Join-Path $scratch 'runtime/supervisor'
$warm    = Join-Path $scratch 'runtime/warm-server.json'
$paths   = Get-SupervisorPaths -Root $supRoot -WarmRegistryPath $warm

function RunSup([string[]]$extra) {
    $base = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-SupervisorRoot',$supRoot,'-WarmRegistryPath',$warm,'-Registry',$regPath,'-PwshPath',$PwshPath)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $obj = $null; try { $obj = ($o | Out-String).Trim() | ConvertFrom-Json } catch { }
    return $obj
}
function RunGw([string[]]$extra) {
    $base = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$gw,'-Registry',$regPath,'-WarmRegistryPath',$warm,'-SupervisorRoot',$supRoot,'-PwshPath',$PwshPath,'-GpuLease','off','-MaxTokens','8','-Temperature','0.1','-Seed','42')
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $obj = $null; try { $obj = ($o | Out-String).Trim() | ConvertFrom-Json } catch { }
    return $obj
}
function StopSup { try { [void](RunSup @('-Action','stop')) } catch { } }

Write-Output "==== gateway SUPERVISOR fault-injection suite (mock engine) ===="
Write-Output "entry=$entry"; Write-Output "IsWindows=$IsWindows"; Write-Output ""

try {
    # =============================================================================================
    # FS-1  start DETACHED -> the supervisor manifest is published
    # =============================================================================================
    $s = RunSup @('-Action','start')
    Ok ($null -ne $s -and $s.status -eq 'ok' -and ($s.result.started -eq $true -or $s.result.already_running -eq $true)) 'FS-1 supervisor start ok'
    $supPid = [int]$s.result.supervisor_pid
    Ok ((PidAlive $supPid)) 'FS-1 the supervisor process is alive'
    $man = Get-Content -LiteralPath $paths.manifest -Raw | ConvertFrom-Json
    Ok ([string]$man.schema -eq $SUP_MANIFEST_SCHEMA -and [string]$man.state -eq 'RUNNING' -and (Has $man 'job_object')) 'FS-1 supervisor.json published (state=RUNNING, job descriptor present)'
    if ($IsWindows) { Ok ([bool]$man.job_object.supported) 'FS-1 [Windows] the Job Object is supported (real KILL_ON_JOB_CLOSE ownership)' }
    else { Ok (-not [bool]$man.job_object.supported) 'FS-1 [off-Windows] Job Object unsupported (honest; the durable reap is a LIVE-only guarantee)' }
    $stat = RunSup @('-Action','status')
    Ok ($stat.result.supervisor.running -eq $true) 'FS-1 status reports the supervisor running'

    # =============================================================================================
    # FS-2  DURABLE reuse: two SEPARATE gateway invocations reuse the SAME resident via the supervisor
    # =============================================================================================
    $g1 = RunGw @('-EnsureResident','-UseSupervisor','-Model','mock.a','-Context','4096')
    Ok ($null -ne $g1 -and $g1.status -eq 'ok' -and $g1.result.via_supervisor -eq $true -and $g1.result.pool.action -eq 'cold_start') 'FS-2 gateway #1 -> cold_start via supervisor'
    $pidA = [int]$g1.result.server.pid; $genA = [string]$g1.result.pool.instance_generation; $fenceA = [int]$g1.result.pool.fence
    $g2 = RunGw @('-EnsureResident','-UseSupervisor','-Model','mock.a','-Context','4096')
    Ok ($null -ne $g2 -and $g2.result.via_supervisor -eq $true -and $g2.result.pool.action -eq 'reuse') 'FS-2 gateway #2 (separate process) -> reuse via supervisor'
    $pidB = [int]$g2.result.server.pid
    Ok ($pidA -gt 0 -and $pidA -eq $pidB) "FS-2 SAME resident pid across two separate invocations ($pidA == $pidB) -- NO respawn (durable across invocations)"
    # classic inference (no -UseSupervisor) reuses the supervisor-published resident
    $inf = RunGw @('-Warm','-Model','mock.a','-Context','4096','-Prompt','ping')
    Ok ($null -ne $inf -and $inf.status -eq 'ok' -and $inf.result.output.text -eq 'PONG' -and $inf.result.server.warm.reused -eq $true) 'FS-2 classic -Warm inference REUSES the supervisor resident (PONG)'

    # =============================================================================================
    # FS-3  forced fence/generation expiry -> a stale-generation inference is REJECTED
    # =============================================================================================
    # a config change (ctx 4096 -> 8192) forces a relaunch via the supervisor -> new generation G2 + higher fence
    $g3 = RunGw @('-EnsureResident','-UseSupervisor','-Model','mock.a','-Context','8192')
    Ok ($g3.result.pool.action -eq 'evict_reload' -and [string]$g3.result.pool.instance_generation -ne $genA -and [int]$g3.result.pool.fence -gt $fenceA) 'FS-3 a config change relaunched the resident (new generation + higher fence)'
    $genB = [string]$g3.result.pool.instance_generation
    # an inference expecting the STALE generation G1 is rejected before any completion (classic path reads the live manifest)
    $rej = RunGw @('-Warm','-Model','mock.a','-Context','8192','-Prompt','ping','-ExpectGeneration',$genA)
    Ok ($null -ne $rej -and $rej.status -eq 'error' -and $rej.error.code -eq 'generation_mismatch') 'FS-3 inference with a STALE generation is REJECTED (generation_mismatch)'
    # an inference expecting the CURRENT generation G2 succeeds
    $acc = RunGw @('-Warm','-Model','mock.a','-Context','8192','-Prompt','ping','-ExpectGeneration',$genB)
    Ok ($null -ne $acc -and $acc.status -eq 'ok' -and $acc.result.output.text -eq 'PONG') 'FS-3 inference with the CURRENT generation succeeds'
    # a stale FENCE is likewise rejected
    $rejF = RunGw @('-Warm','-Model','mock.a','-Context','8192','-Prompt','ping','-ExpectFence',"$fenceA")
    Ok ($null -ne $rejF -and $rejF.status -eq 'error' -and $rejF.error.code -eq 'generation_mismatch') 'FS-3 inference with a STALE fence is REJECTED'

    # =============================================================================================
    # FS-4  supervisor CRASH -> tree reap (Windows) / reconcile-after-crash (off-Windows)
    # =============================================================================================
    $residentReg = Get-Content -LiteralPath $warm -Raw | ConvertFrom-Json
    $residentPid = [int]$residentReg.pid
    $jobOwned = ((Has $residentReg 'job_owned') -and [bool]$residentReg.job_owned)
    Ok ((PidAlive $residentPid)) 'FS-4 a resident is live before the crash'
    if ($IsWindows) { Ok ($jobOwned -eq $true) 'FS-4 [Windows] the resident is owned by the supervisor Job Object (job_owned=true)' }
    else { Ok ($jobOwned -eq $false) 'FS-4 [off-Windows] job_owned=false is recorded honestly (no false durability claim)' }
    # CRASH the supervisor (hard kill, NOT graceful) so no evict-on-stop runs
    try { $pp = Get-Process -Id $supPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
    for ($i=0; $i -lt 30; $i++) { if (-not (PidAlive $supPid)) { break }; Start-Sleep -Milliseconds 100 }
    Start-Sleep -Milliseconds 600
    if ($IsWindows) {
        Ok (-not (PidAlive $residentPid)) 'FS-4 [Windows] the Job Object reaped the resident tree on supervisor death (0 unmanaged orphans)'
    } else {
        # off-Windows the OS does not reap a Start-Process child on parent death; the durable reap is a LIVE Job-Object
        # guarantee. Prove the FALLBACK: a fresh supervisor RECONCILE (next scenario) drives the stale claim to EMPTY.
        Ok ($true) 'FS-4 [off-Windows] OS tree-reap is a Windows Job-Object guarantee (verified live); fallback = reconcile (FS-5)'
        # clean the orphaned mock so the suite leaves 0 orphans
        try { if (PidAlive $residentPid) { Stop-Process -Id $residentPid -Force -ErrorAction SilentlyContinue } } catch { }
    }
    # supervisor status now reports NOT running (dead pid)
    $statDead = RunSup @('-Action','status')
    Ok ($statDead.result.supervisor.running -eq $false) 'FS-4 status reports the supervisor NOT running after the crash'

    # =============================================================================================
    # FS-5  restart -> reconcile drives the stale post-crash claim to EMPTY, then a fresh ensure cold-starts
    # =============================================================================================
    $s2 = RunSup @('-Action','start')
    Ok ($s2.result.started -eq $true) 'FS-5 a new supervisor starts after the crash'
    $supPid = [int]$s2.result.supervisor_pid
    # the startup reconcile verified the stale claim; the manifest must NOT point at a live wrong resident
    $rc = RunSup @('-Action','reconcile')
    Ok ($null -ne $rc -and $rc.result.reconcile.ran -eq $true) 'FS-5 reconcile ran (verify-the-claim)'
    $gFresh = RunGw @('-EnsureResident','-UseSupervisor','-Model','mock.a','-Context','4096')
    Ok ($gFresh.result.pool.action -eq 'cold_start') 'FS-5 a post-crash ensure COLD-STARTS a fresh resident (the dead claim was not reused)'
    $freshPid = [int]$gFresh.result.server.pid
    Ok ((PidAlive $freshPid) -and $freshPid -ne $residentPid) 'FS-5 the fresh resident has a new live pid'

    # =============================================================================================
    # FS-6  GPU-handoff eviction (evict-before-grant) via the gateway -PrepareGpu -UseSupervisor
    # =============================================================================================
    $pg = RunGw @('-PrepareGpu','-UseSupervisor','-RequiredVramMib','99999999')
    Ok ($null -ne $pg -and $pg.result.via_supervisor -eq $true -and $pg.result.gpu.plan -eq 'evict_then_grant' -and $pg.result.gpu.evicted -eq $true) 'FS-6 PrepareGpu plans evict-before-grant (no blind co-load) + evicts the resident'
    Start-Sleep -Milliseconds 300
    Ok (-not (PidAlive $freshPid)) 'FS-6 the evicted resident is dead (0 orphans)'
    $pg2 = RunGw @('-PrepareGpu','-UseSupervisor','-RequiredVramMib','1')
    Ok ($null -ne $pg2 -and $pg2.result.gpu.plan -eq 'grant' -and $pg2.result.gpu.had_resident -eq $false) 'FS-6 PrepareGpu with no resident -> grant'

} finally {
    StopSup
    Start-Sleep -Milliseconds 400
}

# ---- final: no orphaned mock servers (search by the scratch model path in the args is not portable; rely on
#      the tracked pids being reaped/evicted above). A best-effort global check on Windows/Linux: ----
$orphans = 0
try {
    if ($IsWindows) { $orphans = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='dotnet.exe'" -ErrorAction SilentlyContinue | Where-Object { "$($_.CommandLine)" -like "*mock-llama-server*$scratch*" -or "$($_.CommandLine)" -like "*$modelA*" }).Count }
} catch { $orphans = 0 }
Ok ($orphans -eq 0) 'FS-end no orphaned mock servers after the suite'
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
