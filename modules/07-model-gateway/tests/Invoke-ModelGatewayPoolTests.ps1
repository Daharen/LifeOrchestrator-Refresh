#requires -Version 7.0
# OFF-MACHINE pool-manager tests for model.gateway (Governor Phase 3 Stage-1, mechanism C, D-0063).
# Drives the REAL Invoke-ModelGateway.ps1 against the cross-platform MOCK llama-server (no GPU / no models),
# so it runs on the cloud pre-ship gate AND, unchanged, live via the executor. ASCII-only. Exit 0 iff all pass.
#
# Covers: EnsureResident (Ensure-ResidentModel) cold-start / ~1ms reuse / evict+reload; the EXPANDED residency
# key (a context / cache-type / model change is a REAL swap; a matching filename is insufficient); swap_count;
# PoolStatus (read-only); SweepIdle (idle keep-resident window); whole-task gpu-lease hold (caller-held lease is
# honored and never released); same-model prefix-reuse plumbing (-np 1 + id_slot); and 0 orphaned servers.
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
$entry = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$mock  = Join-Path $PSScriptRoot 'mock-llama-server.ps1'
$reslease = Join-Path $modulesDir '29-resource-lease/Invoke-ResLease.ps1'

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# ---- scratch: mock registry (two llm models, each with params for the residency key) + isolated warm registry ----
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-pool-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$modelA = Join-Path $scratch 'model-a.gguf'; [System.IO.File]::WriteAllText($modelA, 'x', $utf8)
$modelB = Join-Path $scratch 'model-b.gguf'; [System.IO.File]::WriteAllText($modelB, 'x', $utf8)
$reg = [ordered]@{
    schema       = 'lifeorch.model_registry/0.1'
    engine_build = 'mock-build-1'
    engines      = [ordered]@{ 'llama-server' = $mock }
    defaults     = [ordered]@{ llm = 'mock.a' }
    tiers        = [ordered]@{ llm = [ordered]@{ tiny = 'mock.a' } }
    models       = @(
        [ordered]@{ model_id = 'mock.a'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelA; context = 4096; gpu_layers = 99; params = [ordered]@{ sha256 = 'aaaa'; size_bytes = 1 } },
        [ordered]@{ model_id = 'mock.b'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelB; context = 4096; gpu_layers = 99; params = [ordered]@{ sha256 = 'bbbb'; size_bytes = 1 } }
    )
}
$regPath = Join-Path $scratch 'models.json'
[System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 8), $utf8)
$warmReg = Join-Path $scratch 'warm-server.json'

function RunGw([string[]]$extra) {
    $base = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $entry,
        '-Registry', $regPath, '-WarmRegistryPath', $warmReg, '-PwshPath', $PwshPath,
        '-MaxTokens', '8', '-Temperature', '0.1', '-Seed', '42')
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    $obj = $null; try { $obj = $txt | ConvertFrom-Json } catch { }
    return $obj
}
function RunRl([string[]]$a) { $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $reslease @a; return (([string]($o | Out-String)).Trim() | ConvertFrom-Json) }
function ReadWarm { if (Test-Path -LiteralPath $warmReg) { try { return (Get-Content -LiteralPath $warmReg -Raw | ConvertFrom-Json) } catch { return $null } } return $null }
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }

Write-Output "==== model.gateway POOL-manager tests (mock engine) ===="
Write-Output "pwsh=$PwshPath"; Write-Output "entry=$entry"; Write-Output ""

# P1: EnsureResident cold start -> resident recorded with the EXPANDED key + sha; provenance confirmed; no generation
$r1 = RunGw @('-Model', 'mock.a', '-Context', '4096', '-EnsureResident', '-GpuLease', 'off')
Ok ($null -ne $r1 -and $r1.status -eq 'ok') 'P1 ensure_resident status ok'
Ok ($null -ne $r1 -and $r1.result.mode -eq 'ensure_resident' -and $r1.result.pool.action -eq 'cold_start') 'P1 action=cold_start'
Ok ($null -ne $r1 -and -not (Has $r1.result 'output')) 'P1 no generation output on an ensure op'
Ok ($null -ne $r1 -and $null -eq $r1.confidence) 'P1 confidence null (no review-queue path)'
$keyA4096 = if ($null -ne $r1) { [string]$r1.result.pool.residency_key_sha } else { '' }
Ok (-not [string]::IsNullOrWhiteSpace($keyA4096)) 'P1 residency_key_sha present'
Ok ($null -ne $r1 -and $r1.result.pool.provenance.ok -eq $true) 'P1 provenance confirmed (/v1/models)'
$reg1 = ReadWarm; $pidA = if ($null -ne $reg1 -and (Has $reg1 'pid')) { [int]$reg1.pid } else { -1 }
Ok ($null -ne $reg1 -and (PidAlive $pidA)) 'P1 resident recorded + alive'
Ok ($null -ne $reg1 -and (Has $reg1 'residency_key_sha') -and ([string]$reg1.residency_key_sha -eq $keyA4096)) 'P1 manifest carries residency_key_sha'
Ok ($null -ne $reg1 -and (Has $reg1 'schema') -and ([string]$reg1.schema -eq 'lifeorch.model_gateway.warm/0.2')) 'P1 manifest schema 0.2'

# P2: EnsureResident again, identical config -> ~1ms REUSE (same pid, timer refreshed), no new process
$reg1LastUsed = if ($null -ne $reg1 -and (Has $reg1 'last_used_utc')) { [string]$reg1.last_used_utc } else { '' }
Start-Sleep -Milliseconds 1100
$r2 = RunGw @('-Model', 'mock.a', '-Context', '4096', '-EnsureResident', '-GpuLease', 'off')
Ok ($null -ne $r2 -and $r2.result.pool.action -eq 'reuse' -and $r2.result.pool.reused -eq $true -and $r2.result.pool.started_new -eq $false) 'P2 action=reuse (no reload)'
Ok ($null -ne $r2 -and [int]$r2.result.pool.load_ms -lt 500) 'P2 reuse load_ms small (~ms, no upload)'
$reg2 = ReadWarm; $pidA2 = if ($null -ne $reg2 -and (Has $reg2 'pid')) { [int]$reg2.pid } else { -2 }
Ok ($pidA2 -eq $pidA -and (PidAlive $pidA)) 'P2 same resident pid (warm survived across invocations)'
Ok ($null -ne $reg2 -and ([string]$reg2.last_used_utc -ne $reg1LastUsed)) 'P2 keep-resident timer refreshed (last_used_utc advanced)'

# P3: EnsureResident, SAME model but CONTEXT changed -> different residency key -> REAL swap (evict+reload)
$r3 = RunGw @('-Model', 'mock.a', '-Context', '8192', '-EnsureResident', '-GpuLease', 'off')
Ok ($null -ne $r3 -and $r3.result.pool.action -eq 'evict_reload' -and $r3.result.pool.evicted -eq $true) 'P3 context change forces evict_reload'
$keyA8192 = if ($null -ne $r3) { [string]$r3.result.pool.residency_key_sha } else { '' }
Ok ($keyA8192 -ne '' -and $keyA8192 -ne $keyA4096) 'P3 residency key differs on a context change'
Ok ($null -ne $r3 -and [int]$r3.result.pool.swap_count -ge 1) 'P3 swap_count incremented'
Start-Sleep -Milliseconds 300
Ok (-not (PidAlive $pidA)) 'P3 old resident pid dead (evicted)'
$reg3 = ReadWarm; $pidA8 = if ($null -ne $reg3 -and (Has $reg3 'pid')) { [int]$reg3.pid } else { -3 }
Ok ($null -ne $reg3 -and ($pidA8 -ne $pidA) -and (PidAlive $pidA8)) 'P3 new resident alive with new pid'

# P4: EnsureResident with cache-type change (q8_0) -> different key -> swap (a matching filename is insufficient)
$r4 = RunGw @('-Model', 'mock.a', '-Context', '8192', '-CacheTypeK', 'q8_0', '-EnsureResident', '-GpuLease', 'off')
$keyA8q8 = if ($null -ne $r4) { [string]$r4.result.pool.residency_key_sha } else { '' }
Ok ($null -ne $r4 -and $r4.result.pool.action -eq 'evict_reload') 'P4 cache-type change forces a swap'
Ok ($keyA8q8 -ne '' -and $keyA8q8 -ne $keyA8192) 'P4 residency key differs on a KV-type change'
$reg4 = ReadWarm; $pidA8q8 = if ($null -ne $reg4 -and (Has $reg4 'pid')) { [int]$reg4.pid } else { -4 }

# P5: EnsureResident for a DIFFERENT model -> swap; swap_count grows monotonically on this lineage
$r5 = RunGw @('-Model', 'mock.b', '-Context', '8192', '-CacheTypeK', 'q8_0', '-EnsureResident', '-GpuLease', 'off')
Ok ($null -ne $r5 -and $r5.result.pool.action -eq 'evict_reload' -and $r5.result.model -eq 'mock.b') 'P5 model change -> evict_reload to mock.b'
Ok ($null -ne $r5 -and [int]$r5.result.pool.swap_count -ge [int]$r4.result.pool.swap_count + 1) 'P5 swap_count monotonic on the lineage'
Start-Sleep -Milliseconds 300
Ok (-not (PidAlive $pidA8q8)) 'P5 previous resident evicted'

# P6: PoolStatus (read-only) reports the resident + idle age; makes NO change (same pid before/after)
$reg6 = ReadWarm; $pidB = if ($null -ne $reg6 -and (Has $reg6 'pid')) { [int]$reg6.pid } else { -6 }
$r6 = RunGw @('-PoolStatus')
Ok ($null -ne $r6 -and $r6.result.action -eq 'pool_status' -and $r6.result.pool.has_resident -eq $true) 'P6 pool_status reports a resident'
Ok ($null -ne $r6 -and $r6.result.pool.model_id -eq 'mock.b' -and $r6.result.pool.healthy -eq $true) 'P6 pool_status: model + healthy'
Ok ($null -ne $r6 -and $null -ne $r6.result.pool.idle_ms) 'P6 pool_status reports idle age'
$reg6b = ReadWarm; $pidB2 = if ($null -ne $reg6b -and (Has $reg6b 'pid')) { [int]$reg6b.pid } else { -7 }
Ok ((PidAlive $pidB) -and ($pidB2 -eq $pidB)) 'P6 pool_status made no change (resident untouched)'

# P7: WARM generation reuses the resident + exposes pool telemetry (prefix-reuse plumbing: -np 1 + id_slot)
$r7 = RunGw @('-Model', 'mock.b', '-Context', '8192', '-CacheTypeK', 'q8_0', '-Prompt', 'ping', '-Warm', '-IdSlot', '0', '-GpuLease', 'off')
Ok ($null -ne $r7 -and $r7.status -eq 'ok' -and $r7.result.output.text -eq 'PONG') 'P7 warm generation ok (PONG)'
Ok ($null -ne $r7 -and $r7.result.server.warm.reused -eq $true) 'P7 warm generation reused the resident'
$poolT = if ($null -ne $r7 -and (Has $r7.result.server.warm 'pool')) { $r7.result.server.warm.pool } else { $null }
Ok ($null -ne $poolT -and [int]$poolT.id_slot -eq 0 -and [int]$poolT.parallel -eq 1) 'P7 prefix-reuse plumbing: id_slot=0 + parallel=1'
Ok ($null -ne $poolT -and -not [string]::IsNullOrWhiteSpace([string]$poolT.residency_key_sha)) 'P7 warm generation carries residency_key_sha'

# P8: SweepIdle -- within the window keeps; beyond a 0s window evicts (idle keep-resident policy)
$r8a = RunGw @('-SweepIdle', '-KeepResidentSeconds', '3600')
Ok ($null -ne $r8a -and $r8a.result.action -eq 'sweep_idle' -and $r8a.result.pool.kept -eq $true -and $r8a.result.pool.evicted -eq $false) 'P8 sweep keeps a fresh resident within the window'
$reg8 = ReadWarm; $pidB3 = if ($null -ne $reg8 -and (Has $reg8 'pid')) { [int]$reg8.pid } else { -8 }
Ok (PidAlive $pidB3) 'P8 resident still alive after in-window sweep'
$r8b = RunGw @('-SweepIdle', '-KeepResidentSeconds', '0')
Ok ($null -ne $r8b -and $r8b.result.pool.evicted -eq $true -and $r8b.result.pool.reason -eq 'idle_evicted') 'P8 sweep evicts a resident beyond the (0s) window'
Start-Sleep -Milliseconds 300
Ok (-not (PidAlive $pidB3)) 'P8 evicted resident pid dead'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'P8 registry cleared after idle eviction'

# P9: WHOLE-TASK gpu lease hold -- a caller-held lease (stable holder) is honored and NEVER released by the gateway
$ld = Join-Path $scratch 'lease'
Ok (Test-Path -LiteralPath $reslease) 'P9 res.lease present'
$pre = RunRl @('-Action', 'acquire', '-Resource', 'gpu', '-Holder', 'governor', '-TtlSeconds', '300', '-LeaseDir', $ld)
Ok ($pre.result.acquired -eq $true) 'P9 governor pre-acquired the whole-task gpu lease'
$r9 = RunGw @('-Model', 'mock.a', '-EnsureResident', '-GpuLease', 'require', '-GpuLeaseHolder', 'governor', '-LeaseDir', $ld, '-ResLeasePath', $reslease)
$gl9 = if ($null -ne $r9) { $r9.result.server.gpu_lease } else { $null }
Ok ($null -ne $r9 -and $r9.status -eq 'ok' -and $r9.result.pool.action -eq 'cold_start') 'P9 ensure ran under the held lease'
Ok ($null -ne $gl9 -and $gl9.already_held -eq $true -and $gl9.owned -eq $false) 'P9 lease already_held + not owned (whole-task hold)'
Ok ($null -ne $gl9 -and $gl9.released -ne $true) 'P9 gateway did NOT release the caller-held lease'
$st9 = RunRl @('-Action', 'status', '-Resource', 'gpu', '-LeaseDir', $ld)
Ok ($st9.result.held -eq $true -and $st9.result.holder -eq 'governor') 'P9 lease still held by governor after the call'
# evict the resident this ensure created, then release the whole-task lease
RunGw @('-EvictWarm') | Out-Null
RunRl @('-Action', 'release', '-Resource', 'gpu', '-Holder', 'governor', '-LeaseDir', $ld) | Out-Null

# ---- cleanup: leave no mock server behind + assert zero orphans of OUR pids ----
$leftover = ReadWarm
if ($null -ne $leftover -and (Has $leftover 'pid')) { try { Stop-Process -Id ([int]$leftover.pid) -Force -ErrorAction SilentlyContinue } catch { } }
foreach ($p in @($pidA, $pidA8, $pidA8q8, $pidB, $pidB3)) { if (PidAlive $p) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { } } }
Start-Sleep -Milliseconds 300
$stillAlive = @(@($pidA, $pidA8, $pidA8q8, $pidB, $pidB3) | Where-Object { PidAlive $_ })
Ok ($stillAlive.Count -eq 0) 'P10 no orphaned mock servers after the suite'
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
