#requires -Version 7.0
# OFF-MACHINE tests for the i21 R1b CONSUMER wave: model.gateway -UsePoolLeaseSplit adoption of the
# res.lease 0.4.0 GPU-lease split + the lib/PoolEvictor.ps1 '-EvictorMode command' contract.
#
# Drives the REAL Invoke-ModelGateway.ps1 + the REAL Invoke-ResLease.ps1 (pure pwsh, identical on Linux +
# Windows) against the cross-platform MOCK llama-server and MOCK supervisor/nvidia-smi SEAMS
# ($env:LIFEORCH_POOLEVICTOR_SEAMS), so it runs on the cloud pre-ship gate AND, unchanged, live via the
# executor (live runs simply leave the seams unset -> real nvidia-smi + the real durable supervisor).
#
# Covers: (A) DEFAULT-OFF byte-identity (no split keys anywhere with the flag off); (B) the PoolEvictor
# fail-closed ladder (free/occupied, target_instance_required, fence-op refusal of a stale target,
# vram-unknown as a normal failed prepare, partial-tree refusal, the FULL two-phase transition composition
# with a real revoked pin + a real killed sleeper); (C) gateway adoption (pin between calls, exec re-attach
# reuse, two-phase swap + commit, revocation honored on entry, the late-stale-result authority refusal);
# (D) the supervisor-side TARGET-FENCED evict. ASCII-only. Exit 0 iff all pass.
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
$entry    = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$evictor  = Join-Path $moduleRoot 'lib/PoolEvictor.ps1'
$supMod   = Join-Path $moduleRoot 'lib/Supervisor.psm1'
$mock     = Join-Path $PSScriptRoot 'mock-llama-server.ps1'
$reslease = Join-Path $modulesDir '29-resource-lease/Invoke-ResLease.ps1'

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# ---- scratch: mock registry + isolated warm registry + isolated lease dir + seam scripts ----
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-split-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$modelA = Join-Path $scratch 'model-a.gguf'; [System.IO.File]::WriteAllText($modelA, 'x', $utf8)
$modelB = Join-Path $scratch 'model-b.gguf'; [System.IO.File]::WriteAllText($modelB, 'x', $utf8)
$reg = [ordered]@{
    schema       = 'lifeorch.model_registry/0.1'
    engine_build = 'mock-build-1'
    engines      = [ordered]@{ 'llama-server' = $mock }
    defaults     = [ordered]@{ llm = 'mock.a' }
    tiers        = [ordered]@{ llm = [ordered]@{ mid = 'mock.a'; strong = 'mock.b' } }
    models       = @(
        [ordered]@{ model_id = 'mock.a'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelA; context = 4096; gpu_layers = 99; params = [ordered]@{ sha256 = 'aaaa'; size_bytes = 1 } },
        [ordered]@{ model_id = 'mock.b'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelB; context = 4096; gpu_layers = 99; params = [ordered]@{ sha256 = 'bbbb'; size_bytes = 1 } }
    )
}
$regPath = Join-Path $scratch 'models.json'
[System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 8), $utf8)
$warmReg  = Join-Path $scratch 'warm-server.json'
$leaseDir = Join-Path $scratch 'leases'; New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null
$receipts = Join-Path $scratch 'evictor-receipts'

# seam: mock nvidia-smi (value scripted via env GWSPLIT_VRAM_VALUE; 'unknown' -> non-numeric)
$vramMock = Join-Path $scratch 'vram-mock.ps1'
[System.IO.File]::WriteAllText($vramMock, @'
$v = $env:GWSPLIT_VRAM_VALUE
if ([string]::IsNullOrWhiteSpace($v)) { $v = '8000' }
[Console]::Out.WriteLine($v)
'@, $utf8)

# seam: mock durable supervisor (targeted evict against the warm manifest; GWSPLIT_SUP_PARTIAL=1 simulates a
# survivor child: reports evicted but leaves the tree alive -> PoolEvictor must refuse via tree-gone confirm)
$supMock = Join-Path $scratch 'sup-mock.ps1'
[System.IO.File]::WriteAllText($supMock, @'
param([string]$Op, [string]$ParamsJson)
$ErrorActionPreference = 'Stop'
function HasP($o,$n){ return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
$p = $null; try { $p = $ParamsJson | ConvertFrom-Json } catch { }
$wr = $env:GWSPLIT_WARMREG
$out = [ordered]@{ action='evict'; had_resident=$false; evicted=$false; resident_pid=$null; reason='no_resident' }
if ($Op -ne 'evict') { $out.reason = 'unsupported_op'; [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); return }
$m = $null
if (-not [string]::IsNullOrWhiteSpace($wr) -and (Test-Path -LiteralPath $wr -PathType Leaf)) { try { $m = Get-Content -LiteralPath $wr -Raw | ConvertFrom-Json } catch { } }
if ($null -eq $m -or -not (HasP $m 'pid')) { [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); return }
$out.had_resident = $true; $out.resident_pid = [int]$m.pid
$tgt = if ($null -ne $p -and (HasP $p 'target_resident_instance_id')) { [string]$p.target_resident_instance_id } else { '' }
$cur = if (HasP $m 'resident_instance_id') { [string]$m.resident_instance_id } else { '' }
if (-not [string]::IsNullOrWhiteSpace($tgt)) {
    if ([string]::IsNullOrWhiteSpace($cur)) { $out.reason = 'manifest_instance_unknown'; [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); return }
    if ($tgt -ne $cur) { $out.reason = 'target_instance_mismatch'; [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); return }
}
if ($env:GWSPLIT_SUP_PARTIAL -eq '1') {
    # adversarial: claim the stop happened but leave the tree alive (a survivor child)
    $out.evicted = $true; $out.reason = 'evicted'
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress)); return
}
try { Stop-Process -Id ([int]$m.pid) -Force -ErrorAction SilentlyContinue } catch { }
for ($i=0; $i -lt 40; $i++) { $alive = $null; try { $alive = Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue } catch { }; if ($null -eq $alive) { break }; Start-Sleep -Milliseconds 50 }
Remove-Item -LiteralPath $wr -Force -ErrorAction SilentlyContinue
$out.evicted = $true; $out.reason = 'evicted'
[Console]::Out.WriteLine(($out | ConvertTo-Json -Compress))
'@, $utf8)

$seams = [ordered]@{
    vram_cmd = $vramMock; supervisor_cmd = $supMock; res_lease = $reslease
    warm_registry = $warmReg; pwsh = $PwshPath
    observations = 3; interval_ms = 10; receipt_dir = $receipts
}
$env:LIFEORCH_POOLEVICTOR_SEAMS = ($seams | ConvertTo-Json -Compress)
$env:GWSPLIT_WARMREG = $warmReg
$env:GWSPLIT_VRAM_VALUE = '8000'
$env:GWSPLIT_SUP_PARTIAL = ''
$env:LIFEORCH_OWNER_INCARNATION = ''
$env:LIFEORCH_INSTANCE = ''

function RunGw([string[]]$extra) {
    $base = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $entry,
        '-Registry', $regPath, '-WarmRegistryPath', $warmReg, '-PwshPath', $PwshPath, '-LeaseDir', $leaseDir,
        '-MaxTokens', '8', '-Temperature', '0.1', '-Seed', '42')
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    $obj = $null; try { $obj = $txt | ConvertFrom-Json } catch { }
    return $obj
}
function RunRl([hashtable]$in) {
    if (-not $in.ContainsKey('lease_dir')) { $in['lease_dir'] = $leaseDir }
    $j = ($in | ConvertTo-Json -Compress -Depth 6)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $reslease -InputsJson $j 2>$null
    $ErrorActionPreference = $prev
    $t = ([string]($o | Out-String)).Trim()
    try { return ($t | ConvertFrom-Json).result } catch { return $null }
}
function RunEvictor([hashtable]$ctx) {
    $j = ($ctx | ConvertTo-Json -Compress -Depth 6)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $evictor -ContextJson $j 2>$null
    $ErrorActionPreference = $prev
    $t = ([string]($o | Out-String)).Trim()
    try { return ($t | ConvertFrom-Json) } catch { return $null }
}
function ReadWarm { if (Test-Path -LiteralPath $warmReg) { try { return (Get-Content -LiteralPath $warmReg -Raw | ConvertFrom-Json) } catch { return $null } } return $null }
function ReadLease {
    $f = Get-ChildItem -LiteralPath $leaseDir -Filter 'gpu-*.lease' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $f) { return $null }
    try { return (Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json) } catch { return $null }
}
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }
function StartSleeper {
    $sl = Join-Path $scratch 'sleeper.ps1'
    if (-not (Test-Path -LiteralPath $sl)) { [System.IO.File]::WriteAllText($sl, 'Start-Sleep -Seconds 300', $utf8) }
    $p = Start-Process -FilePath $PwshPath -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$sl) -PassThru
    return [int]$p.Id
}

Write-Output "==== model.gateway GPU-LEASE-SPLIT tests (i21 R1b consumer adoption; mock engine + seams) ===="
Write-Output "pwsh=$PwshPath"; Write-Output "entry=$entry"; Write-Output ""

# =====================================================================================================
Write-Output "-- A: DEFAULT-OFF byte-identity --"
$offHolder = 'gw-split-off'
$a1 = RunGw @('-Model','mock.a','-Warm','-Prompt','hi','-GpuLeaseHolder',$offHolder)
Ok ($null -ne $a1 -and $a1.status -eq 'ok') 'A1 warm generate (split OFF) status ok'
Ok ($null -ne $a1 -and -not (Has $a1.result.server.gpu_lease 'split')) 'A1 gpu_lease carries NO split key with the flag off'
$aKeys = @($a1.result.server.gpu_lease.PSObject.Properties.Name)
Ok (($aKeys -join ',') -eq 'mode,requested,available,acquired,owned,already_held,reclaimed_stale,lease_id,holder,held_by,released,note') "A1 gpu_lease key set byte-identical to the classic path (got $($aKeys -join ','))"
$am = ReadWarm
Ok ($null -ne $am -and (Has $am 'resident_instance_id') -and -not [string]::IsNullOrWhiteSpace([string]$am.resident_instance_id)) 'A1 manifest carries resident_instance_id (additive per-tree identity, stamped at every launch)'
$a1pid = if ($null -ne $am) { [int]$am.pid } else { -1 }
$a2 = RunGw @('-EvictWarm')
Ok ($null -ne $a2 -and $a2.status -eq 'ok' -and -not (PidAlive $a1pid)) 'A2 evict_warm teardown (classic path untouched by the split code)'
$al = ReadLease
Ok ($null -eq $al) 'A2 no lease file left by the classic per-call path'

# =====================================================================================================
Write-Output ""
Write-Output "-- B: PoolEvictor.ps1 contract (fail-closed ladder; mock supervisor/nvidia-smi seams) --"
# B1 free slot, stable headroom
$b1 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB1'; operation_id='o1'; authority_epoch=0; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='free' }
Ok ($null -ne $b1 -and $b1.confirmed -eq $true -and $b1.evicted -eq $false -and $b1.tree_gone -eq $true -and $b1.outcome -eq 'confirmed') 'B1 free slot + stable headroom -> confirmed (no evict)'
Ok ($null -ne $b1 -and [int]$b1.free_vram_mib -eq 8000) 'B1 reports the observed free VRAM'
# B2 free slot, headroom below need
$env:GWSPLIT_VRAM_VALUE = '900'
$b2 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB2'; operation_id='o1'; authority_epoch=0; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='free' }
Ok ($null -ne $b2 -and $b2.confirmed -eq $false -and $b2.outcome -eq 'headroom_not_stable') 'B2 headroom below required+target -> confirmed:false (headroom_not_stable)'
# B3 VRAM unknown -> a NORMAL failed prepare, never a throw
$env:GWSPLIT_VRAM_VALUE = 'unknown'
$b3 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB3'; operation_id='o1'; authority_epoch=0; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='free' }
Ok ($null -ne $b3 -and $b3.confirmed -eq $false -and $b3.outcome -eq 'vram_unknown') 'B3 nvidia-smi unavailable -> vram_unknown, confirmed:false (fail-closed, no throw)'
$env:GWSPLIT_VRAM_VALUE = '8000'
# B4 occupied WITHOUT a target: "stop whatever serves this resource" is impossible
$b4 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB4'; operation_id='o1'; authority_epoch=0; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='occupied' }
Ok ($null -ne $b4 -and $b4.confirmed -eq $false -and $b4.tree_gone -eq $false -and $b4.outcome -eq 'target_instance_required') 'B4 occupied + no target_resident_instance_id -> REFUSED (target_instance_required)'
# B5 occupied + a target but NO live lease -> fence-op refuses (no_live_resident); nothing is killed
$b5sleeper = StartSleeper
[System.IO.File]::WriteAllText($warmReg, ([ordered]@{ pid=$b5sleeper; resident_instance_id='riB5'; port=0 } | ConvertTo-Json), $utf8)
$b5 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB5'; operation_id='o1'; authority_epoch=7; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='occupied'; target_resident_instance_id='riB5' }
Ok ($null -ne $b5 -and $b5.confirmed -eq $false -and $b5.outcome -like 'fence_refused:*') 'B5 no live lease -> fence-op refusal (stale/unprotected target; fail-closed)'
Ok (PidAlive $b5sleeper) 'B5 the process was NOT killed on a fence refusal'
try { Stop-Process -Id $b5sleeper -Force -ErrorAction SilentlyContinue } catch { }
Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue
# B6 the FULL two-phase composition: live pin (riLIVE) + live sleeper in the manifest; a higher-priority
#    transition drives the REAL PoolEvictor (fence authority_revoked-for-our-epoch accepted, supervisor
#    mock tree-kill, tree-gone + headroom confirmed) -> capability -> commit -HealthOk -> usable exec lease.
$b6sleeper = StartSleeper
[System.IO.File]::WriteAllText($warmReg, ([ordered]@{ pid=$b6sleeper; resident_instance_id='riLIVE'; port=0 } | ConvertTo-Json), $utf8)
$b6pin = RunRl @{ action='acquire'; resource='gpu'; holder='OLDOWNER'; kind='residency_pin'; priority=1; owner_id='OLDOWNER'; owner_incarnation_id='incOLD'; resident_instance_id='riLIVE'; resident_generation='gLIVE' }
Ok ($null -ne $b6pin -and $b6pin.acquired -eq $true) 'B6 setup: low-priority pin riLIVE resident'
$b6 = RunRl @{ action='acquire'; resource='gpu'; holder='NEWOWNER'; owner_id='NEWOWNER'; owner_incarnation_id='incNEW'; priority=5; transition=$true; two_phase_commit=$true; required_vram_mib=1000; target_headroom_mib=512; evictor_mode='command'; evictor_command=$evictor; drain_timeout_ms=200; resident_instance_id='riNEW'; request_id='rqB6' }
Ok ($null -ne $b6 -and $b6.acquired -eq $true -and $b6.capability_only -eq $true -and $b6.usable -eq $false) 'B6 transition grants a NON-usable capability (usable:false)'
Ok ($null -ne $b6 -and $b6.evict_performed -eq $true -and $b6.tree_gone -eq $true -and $b6.headroom_confirmed -eq $true) 'B6 REAL evictor: supervisor-routed stop + tree gone + stable headroom'
Ok ($null -ne $b6 -and [string]$b6.old_resident_instance_id -eq 'riLIVE') 'B6 the drain/kill targeted the EXACT old resident_instance_id'
Ok (-not (PidAlive $b6sleeper)) 'B6 the old managed tree is really dead (mock supervisor tree-kill)'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'B6 manifest cleared by the targeted supervisor stop'
$b6c = RunRl @{ action='commit'; resource='gpu'; holder='NEWOWNER'; owner_id='NEWOWNER'; resident_instance_id='riNEW'; health_ok=$true; transition_id=[string]$b6.transition_id }
Ok ($null -ne $b6c -and $b6c.committed -eq $true -and $b6c.usable -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$b6c.exec_lease_id)) 'B6 phase-2 commit -HealthOk publishes the FIRST usable exec lease'
$null = RunRl @{ action='release'; resource='gpu'; holder='NEWOWNER'; lease_id=[string]$b6c.lease_id }
# B7 adversarial partial tree: the supervisor CLAIMS the stop but a survivor stays -> tree-gone confirm refuses
$b7sleeper = StartSleeper
[System.IO.File]::WriteAllText($warmReg, ([ordered]@{ pid=$b7sleeper; resident_instance_id='riP7'; port=0 } | ConvertTo-Json), $utf8)
$b7pin = RunRl @{ action='acquire'; resource='gpu'; holder='POWNER'; kind='residency_pin'; priority=1; owner_id='POWNER'; resident_instance_id='riP7' }
$env:GWSPLIT_SUP_PARTIAL = '1'
$b7 = RunRl @{ action='acquire'; resource='gpu'; holder='PNEW'; owner_id='PNEW'; priority=5; transition=$true; two_phase_commit=$true; required_vram_mib=1000; target_headroom_mib=512; evictor_mode='command'; evictor_command=$evictor; drain_timeout_ms=100; resident_instance_id='riP8' }
$env:GWSPLIT_SUP_PARTIAL = ''
Ok ($null -ne $b7 -and $b7.acquired -eq $false -and $b7.tree_gone -eq $false -and [string]$b7.transition_state -eq 'ABORTED') 'B7 partial tree (survivor child) -> tree_gone:false -> transition does NOT grant'
Ok (PidAlive $b7sleeper) 'B7 the survivor is still alive (the evictor never PID-kills; fail-closed abort)'
try { Stop-Process -Id $b7sleeper -Force -ErrorAction SilentlyContinue } catch { }
Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue
$null = RunRl @{ action='release'; resource='gpu'; holder='POWNER' }
# B8 stale-target refusal: the manifest/lease moved on (riX2) while a delayed evictor still targets riX1
$b8sleeper = StartSleeper
[System.IO.File]::WriteAllText($warmReg, ([ordered]@{ pid=$b8sleeper; resident_instance_id='riX2'; port=0 } | ConvertTo-Json), $utf8)
$b8pin = RunRl @{ action='acquire'; resource='gpu'; holder='XOWNER'; kind='residency_pin'; priority=1; owner_id='XOWNER'; resident_instance_id='riX2' }
$b8 = RunEvictor @{ resource='gpu'; lease_dir=$leaseDir; txn_id='tB8'; operation_id='o1'; authority_epoch=999; required_vram_mib=1000; target_headroom_mib=512; drain_timeout_ms=100; state='occupied'; target_resident_instance_id='riX1' }
Ok ($null -ne $b8 -and $b8.confirmed -eq $false -and ($b8.outcome -like 'fence_refused:*')) 'B8 a DELAYED stop naming the OLD instance is REFUSED (fence-op target mismatch)'
Ok (PidAlive $b8sleeper) 'B8 the CURRENT resident survives the stale kill attempt'
try { Stop-Process -Id $b8sleeper -Force -ErrorAction SilentlyContinue } catch { }
Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue
$null = RunRl @{ action='release'; resource='gpu'; holder='XOWNER' }

# =====================================================================================================
Write-Output ""
Write-Output "-- C: gateway -UsePoolLeaseSplit adoption (pin between calls, exec around ops, two-phase swap) --"
$spHolder = 'gw-split-owner'
# C1 cold start ensure: pin + two-phase transition on a free GPU + per-call launch under the capability + commit + re-pin
$c1 = RunGw @('-Model','mock.a','-EnsureResident','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder,'-SplitDrainTimeoutMs','200')
Ok ($null -ne $c1 -and $c1.status -eq 'ok') 'C1 split cold-start ensure status ok'
$c1s = if ($null -ne $c1) { $c1.result.server.gpu_lease.split } else { $null }
Ok ($null -ne $c1s -and $c1s.on -eq $true) 'C1 split block present + on'
Ok ($null -ne $c1s -and $null -ne $c1s.transition -and $c1s.transition.capability_only -eq $true -and $c1s.transition.usable -eq $false) 'C1 load went through the TWO-PHASE transition (non-usable capability first)'
Ok ($null -ne $c1s -and $null -ne $c1s.commit -and $c1s.commit.committed -eq $true) 'C1 phase-2 commit -HealthOk AFTER health (no grant-before-ready)'
Ok ($null -ne $c1s -and $c1s.repinned -eq $true) 'C1 back to steady state: exec released + residency pin re-taken'
$c1m = ReadWarm
$c1lease = ReadLease
Ok ($null -ne $c1m -and $null -ne $c1lease -and ([string]$c1m.resident_instance_id -eq [string]$c1lease.resident_instance_id)) 'C1 manifest resident_instance_id == pin resident_instance_id (one per-tree identity)'
Ok ($null -ne $c1lease -and ([string]$c1lease.lease_kind -eq 'residency_pin') -and ($c1lease.revocable -eq $true)) 'C1 the between-calls hold is a REVOCABLE residency_pin'
Ok ($null -ne $c1m -and ([string]$c1m.instance_generation -eq [string]$c1lease.resident_generation)) 'C1 resident_generation bound to the manifest instance_generation'
$c1pid = if ($null -ne $c1m) { [int]$c1m.pid } else { -1 }
Ok (PidAlive $c1pid) 'C1 resident launched + alive under the capability'
# C2 same-model reuse: plain short exec re-attach; full-tuple authority gate; pin persists
$c2 = RunGw @('-Model','mock.a','-Warm','-Prompt','hello','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder)
Ok ($null -ne $c2 -and $c2.status -eq 'ok' -and -not [string]::IsNullOrWhiteSpace([string]$c2.result.output.text)) 'C2 split reuse generate ok'
$c2s = if ($null -ne $c2) { $c2.result.server.gpu_lease.split } else { $null }
Ok ($null -ne $c2s -and $null -eq $c2s.transition) 'C2 reuse took NO transition (plain short exec re-attach)'
Ok ($null -ne $c2 -and $c2.result.server.warm.reused -eq $true -and [int]$c2.result.server.warm.load_ms -le 100 -and ([string]$c2.result.server.warm.pool.action -eq 'reuse')) 'C2 pool reuse stayed ms-class (no reload)'
Ok ($null -ne $c2s -and $null -ne $c2s.active -and -not [string]::IsNullOrWhiteSpace([string]$c2s.active.exec_lease_id)) 'C2 exec_lease_id carried on the call (full v0.4 tuple)'
Ok ($null -ne $c2s -and $null -ne $c2s.discard_check -and $c2s.discard_check.authority_ok -eq $true) 'C2 post-generation authority re-check passed (result NOT discarded)'
$c2lease = ReadLease
Ok ($null -ne $c2lease -and ([string]$c2lease.lease_kind -eq 'residency_pin') -and ([string]$c2lease.holder -eq $spHolder)) 'C2 the pin persists between calls (held, kind residency_pin)'
# C3 swap mock.a -> mock.b: the transition + REAL PoolEvictor evict the old server (via the mock supervisor), then commit
$c3 = RunGw @('-Model','mock.b','-Warm','-Prompt','swap','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder,'-SplitDrainTimeoutMs','200')
Ok ($null -ne $c3 -and $c3.status -eq 'ok' -and -not [string]::IsNullOrWhiteSpace([string]$c3.result.output.text)) 'C3 split swap generate ok'
$c3s = if ($null -ne $c3) { $c3.result.server.gpu_lease.split } else { $null }
Ok ($null -ne $c3s -and $null -ne $c3s.transition -and $c3s.transition.capability_only -eq $true) 'C3 swap went through the two-phase transition'
Ok ($null -ne $c3s -and $c3s.transition.evict_performed -eq $true -and $c3s.transition.tree_gone -eq $true) 'C3 the OLD resident was evicted by the REAL evictor (tree gone confirmed)'
Ok (-not (PidAlive $c1pid)) 'C3 the old server process is really dead'
$c3m = ReadWarm
Ok ($null -ne $c3m -and ([string]$c3m.model_id -eq 'mock.b') -and ([int]$c3m.swap_count -ge 1)) 'C3 new resident is mock.b; swap_count bumped'
$c3lease = ReadLease
Ok ($null -ne $c3s -and $null -ne $c3m -and $null -ne $c3lease -and ([string]$c3m.resident_instance_id -eq [string]$c3lease.resident_instance_id) -and ([string]$c3s.active.resident_instance_id -eq [string]$c3m.resident_instance_id)) 'C3 lease + manifest + tuple agree on the NEW resident_instance_id'
Ok ($null -ne $c3s -and $c3s.repinned -eq $true -and ([string]$c3lease.lease_kind -eq 'residency_pin')) 'C3 re-pinned after the swap (exec only around the op)'
# C4 revocation honored on entry: a higher-priority owner transitions the GPU away; our next call STOPS SERVING
$c3pid = if ($null -ne $c3m) { [int]$c3m.pid } else { -1 }
$c4tr = RunRl @{ action='acquire'; resource='gpu'; holder='PREEMPTOR'; owner_id='PREEMPTOR'; owner_incarnation_id='incPre'; priority=99; transition=$true; two_phase_commit=$true; required_vram_mib=1000; target_headroom_mib=512; evictor_mode='command'; evictor_command=$evictor; drain_timeout_ms=200; resident_instance_id='riPRE'; request_id='rqC4' }
Ok ($null -ne $c4tr -and $c4tr.acquired -eq $true -and $c4tr.evict_performed -eq $true) 'C4 a higher-priority transition REVOKED our pin + evicted our resident (the real evictor)'
Ok (-not (PidAlive $c3pid)) 'C4 our old server is gone (supervisor-routed targeted stop)'
$c4 = RunGw @('-Model','mock.b','-Warm','-Prompt','late','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder)
Ok ($null -ne $c4 -and $c4.status -eq 'error' -and ([string]$c4.error.code -in @('gpu_pin_revoked','gpu_split_contended'))) "C4 revoked/contended pin on entry -> STOP SERVING (got $($c4.error.code))"
# C5 the late-stale-result authority refusal (the discard gate's evidence, driven at the res.lease layer):
#    the OLD tuple captured at C3 must now fail check.authority_ok AND fence-op result_publish must refuse it.
$c5chk = RunRl @{ action='check'; resource='gpu'; owner_id=$spHolder; owner_incarnation_id=[string]$c3s.owner_incarnation_id; authority_epoch=[long]$c3s.active.gpu_authority_epoch; resident_generation=[string]$c3s.active.resident_generation; resident_instance_id=[string]$c3s.active.resident_instance_id }
Ok ($null -ne $c5chk -and $c5chk.authority_ok -eq $false) 'C5 the captured OLD tuple -> check authority_ok:false (a late result CANNOT publish)'
$c5f = RunRl @{ action='fence-op'; resource='gpu'; op_kind='result_publish'; resident_instance_id=[string]$c3s.active.resident_instance_id }
Ok ($null -ne $c5f -and $c5f.fenced_op_ok -eq $false) 'C5 fence-op result_publish naming the STALE instance -> REFUSED'
$c5f2 = RunRl @{ action='fence-op'; resource='gpu'; op_kind='stop'; resident_instance_id=[string]$c3s.active.resident_instance_id }
Ok ($null -ne $c5f2 -and $c5f2.fenced_op_ok -eq $false) 'C5 a late stop naming the STALE instance cannot kill the new resident'
$null = RunRl @{ action='release'; resource='gpu'; holder='PREEMPTOR' }
# C4b the SIGNAL-revocation path: re-establish our pin + resident, then a plain (non-transition)
#     higher-priority acquire signal-revokes the pin IN PLACE; our next call sees revoked_by on entry.
$c4b0 = RunGw @('-Model','mock.a','-EnsureResident','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder,'-SplitDrainTimeoutMs','200')
Ok ($null -ne $c4b0 -and $c4b0.status -eq 'ok') 'C4b re-established resident + pin after preemption (fresh split ensure)'
$c4bsig = RunRl @{ action='acquire'; resource='gpu'; holder='SIGNALER'; owner_id='SIGNALER'; priority=99; kind='exec' }
Ok ($null -ne $c4bsig -and $c4bsig.acquired -eq $false -and (Has $c4bsig 'revocation_signaled') -and $c4bsig.revocation_signaled -eq $true) 'C4b a higher-priority acquire SIGNAL-revoked our pin in place'
$c4b = RunGw @('-Model','mock.a','-Warm','-Prompt','revoked','-UsePoolLeaseSplit','-GpuLeaseHolder',$spHolder)
Ok ($null -ne $c4b -and $c4b.status -eq 'error' -and ([string]$c4b.error.code -eq 'gpu_pin_revoked')) "C4b REVOKED pin on entry -> gpu_pin_revoked (stop serving; got $($c4b.error.code))"
$null = RunRl @{ action='release'; resource='gpu'; holder=$spHolder }
$null = RunGw @('-EvictWarm')
# C6 byte-identity re-check after all split activity: a plain call still carries no split key
$c6 = RunGw @('-Model','mock.a','-Warm','-Prompt','off-again','-GpuLeaseHolder','gw-off-2')
Ok ($null -ne $c6 -and $c6.status -eq 'ok' -and -not (Has $c6.result.server.gpu_lease 'split')) 'C6 split OFF again -> no split key (defaults untouched)'
$null = RunGw @('-EvictWarm')

# =====================================================================================================
Write-Output ""
Write-Output "-- D: supervisor-side TARGET-FENCED evict (Invoke-SupervisorEvict) --"
Import-Module $supMod -Force
$dSleeper = StartSleeper
$dLock = Join-Path $scratch 'd-warm.lock'
$dReg  = Join-Path $scratch 'd-warm.json'
$StopReal = { param($m,$l) try { Stop-Process -Id ([int]$m.pid) -Force -ErrorAction SilentlyContinue } catch { }; for ($i=0;$i -lt 40;$i++){ $a=$null; try { $a=Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue } catch { }; if ($null -eq $a) { return $true }; Start-Sleep -Milliseconds 50 }; return $false }
[System.IO.File]::WriteAllText($dReg, ([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$dSleeper; resident_instance_id='riD1'; instance_generation='gD1'; fence=3 } | ConvertTo-Json), $utf8)
$d1 = Invoke-SupervisorEvict -WarmRegPath $dReg -LockPath $dLock -StopProbe $StopReal -TargetResidentInstanceId 'riWRONG'
Ok ($null -ne $d1 -and $d1.evicted -eq $false -and ([string]$d1.reason -eq 'target_instance_mismatch') -and (PidAlive $dSleeper)) 'D1 supervisor REFUSES a stop naming the wrong instance (resident survives)'
$d2 = Invoke-SupervisorEvict -WarmRegPath $dReg -LockPath $dLock -StopProbe $StopReal -TargetResidentInstanceId 'riD1'
Ok ($null -ne $d2 -and $d2.evicted -eq $true -and -not (PidAlive $dSleeper)) 'D2 supervisor honors the EXACT-target stop (tree killed, manifest cleared)'
$dSleeper2 = StartSleeper
[System.IO.File]::WriteAllText($dReg, ([ordered]@{ schema='lifeorch.model_gateway.warm/0.3'; state='RESIDENT'; pid=$dSleeper2; instance_generation='gD2'; fence=4 } | ConvertTo-Json), $utf8)
$d3 = Invoke-SupervisorEvict -WarmRegPath $dReg -LockPath $dLock -StopProbe $StopReal -TargetResidentInstanceId 'riD2'
Ok ($null -ne $d3 -and $d3.evicted -eq $false -and ([string]$d3.reason -eq 'manifest_instance_unknown') -and (PidAlive $dSleeper2)) 'D3 a manifest WITHOUT an instance id refuses a targeted stop (fail-closed)'
$d4 = Invoke-SupervisorEvict -WarmRegPath $dReg -LockPath $dLock -StopProbe $StopReal
Ok ($null -ne $d4 -and $d4.evicted -eq $true -and -not (PidAlive $dSleeper2)) 'D4 legacy untargeted evict unchanged (back-compat)'

# =====================================================================================================
Write-Output ""
Write-Output "-- E: hygiene: leases released; no orphan mock servers --"
$null = RunRl @{ action='release'; resource='gpu'; holder=$spHolder }
$eLease = ReadLease
Ok ($null -eq $eLease -or ($eLease.holder -ne $spHolder)) 'E1 split pin released by holder (leases dir clean for our holder)'
$em = ReadWarm
$eOrphan = $false
if ($null -ne $em -and (Has $em 'pid')) { $eOrphan = PidAlive ([int]$em.pid) }
Ok (-not $eOrphan) 'E2 no orphaned mock server (manifest empty or pid dead)'
$evReceipts = @(Get-ChildItem -LiteralPath $receipts -Filter '*.receipt.json' -File -ErrorAction SilentlyContinue)
Ok ($evReceipts.Count -ge 3) "E3 PoolEvictor wrote per-run receipts for the live-proof evidence trail ($($evReceipts.Count) found)"

Write-Output ""
Write-Output "==== SPLIT RESULT pass=$pass fail=$fail ===="
try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue } catch { }
$env:LIFEORCH_POOLEVICTOR_SEAMS = ''
if ($fail -gt 0) { Write-Output 'FAILURES PRESENT'; exit 1 }
Write-Output 'ALL PASS'
exit 0
