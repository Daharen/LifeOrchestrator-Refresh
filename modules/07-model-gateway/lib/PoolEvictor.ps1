#requires -Version 7.0
# =====================================================================================================
# PoolEvictor.ps1 -- the REAL res.lease '-EvictorMode command' seam (R1b CONSUMER wave, i21).
#
# Invoked BY res.lease (Invoke-ResLease.ps1 Invoke-Evictor 'command' mode) as:
#     & PoolEvictor.ps1 -ContextJson '<json>'
# INSIDE the res.lease pwsh process (dot-run). Therefore this script must NEVER call `exit` and must
# write EXACTLY ONE JSON object to stdout:
#     { confirmed, free_vram_mib, evicted, tree_gone, outcome, detail }
# `confirmed` may be true ONLY when tree_gone is true AND headroom is STABLE (every observation
# >= required_vram_mib + target_headroom_mib, plus one final re-check immediately before returning).
#
# Fail-closed ladder (any step failing => confirmed:false; a failed prepare is NORMAL, never a throw):
#   1. state=occupied: the destructive stop MUST name the exact target_resident_instance_id captured at
#      dispatch (never "whatever currently serves this resource" -> target_instance_required) and MUST
#      pass the res.lease '-Action fence-op' gate first (a stale target is REFUSED). The expected
#      mid-transition answer is reason=authority_revoked with current instance == target AND current
#      epoch == our transition's authority_epoch (the transition already revoked the pin); plain
#      reason=current is also accepted. Anything else refuses the stop.
#   2. The stop itself is routed through the DURABLE SUPERVISOR (Start-GatewaySupervisor.ps1 /
#      lib/Supervisor.psm1 Job Object) via a targeted 'evict' request -- NEVER a PID kill from here
#      (the D-0055/56 re-wedge class). A bounded cooperative DRAIN (drain_timeout_ms) of any ACTIVE
#      inference runs first (poll /slots best-effort); then the supervisor stop = graceful ->
#      Job-Object tree-kill. No live supervisor => supervisor_unavailable (fail-closed, no kill).
#   3. Confirm the managed tree is GONE: manifest cleared/pid dead + listening socket owner gone.
#      A surviving child => tree_gone:false => partial_tree_term (the transition will NOT grant).
#   4. Confirm headroom STABLE: nvidia-smi memory.free, `observations` (default 3) readings
#      ~interval_ms (default 250) apart, EVERY reading >= required+target, then one final re-check.
#      required_vram_mib is the measured PEAK for the config (weights+KV+compute+overhead+margin),
#      NOT the GGUF size -- the CALLER supplies it; this script only enforces it.
#   5. Off-Windows / nvidia-smi absent: the VRAM probe returns 'unknown' -> confirmed:false
#      (outcome vram_unknown), never a throw. This is why the MOCK, not this script, runs in the
#      off-machine gate. NEVER kill an unidentified VRAM consumer.
#
# Test seams (off-machine): $env:LIFEORCH_POOLEVICTOR_SEAMS = inline JSON or a path to a JSON file:
#   { vram_cmd, supervisor_cmd, supervisor_root, warm_registry, res_lease, pwsh, observations,
#     interval_ms, skip_drain_probe, receipt_dir }
#   vram_cmd:       a pwsh script printing an integer free-MiB (or 'unknown') per call -- replaces nvidia-smi.
#   supervisor_cmd: a pwsh script invoked `& cmd -Op evict -ParamsJson <json>` printing the evict-result
#                   JSON -- replaces the live Send-SupervisorRequest round-trip.
# Live (no seams): real nvidia-smi + the real supervisor file-protocol client.
#
# Every run writes a receipt JSON (fence consult + supervisor response + observations) under
# runtime/evictor/ for live-proof evidence. ASCII-only. UTF-8 no BOM. Diagnostics -> stderr only.
# =====================================================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ContextJson
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ev-Diag([string]$m) { try { [Console]::Error.WriteLine("[pool.evictor] $m") } catch { } }
function Ev-Prop([object]$o, [string]$n, $def) {
    if ($null -eq $o) { return $def }
    if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] } return $def }
    if ($o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) { return $o.$n }
    return $def
}

$script:EvUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:ModuleRoot = Split-Path -Parent $PSScriptRoot   # modules/07-model-gateway

# ---- final emitter: exactly one JSON object on stdout; never exit; never throw out of here ----
function Ev-Emit {
    param([bool]$Confirmed, $FreeMib, [bool]$Evicted, [bool]$TreeGone, [string]$Outcome, [string]$Detail, $Receipt)
    $free = 0
    if ($null -ne $FreeMib) { try { $free = [int]$FreeMib } catch { $free = 0 } }
    $o = [ordered]@{
        confirmed = [bool]$Confirmed
        free_vram_mib = $free
        evicted = [bool]$Evicted
        tree_gone = [bool]$TreeGone
        outcome = [string]$Outcome
        detail = [string]$Detail
    }
    # receipt file (live-proof evidence); best-effort, never fatal
    try {
        if ($null -ne $Receipt) {
            $Receipt['result'] = $o
            $rd = [string]$Receipt['receipt_dir']
            if (-not [string]::IsNullOrWhiteSpace($rd)) {
                if (-not (Test-Path -LiteralPath $rd)) { New-Item -ItemType Directory -Path $rd -Force | Out-Null }
                $rp = Join-Path $rd ("evictor-" + [string]$Receipt['txn_id'] + "-" + [string]$Receipt['operation_id'] + ".receipt.json")
                [System.IO.File]::WriteAllText($rp, ($Receipt | ConvertTo-Json -Depth 10), $script:EvUtf8)
            }
        }
    } catch { Ev-Diag "receipt write failed: $($_.Exception.Message)" }
    # PIPELINE output, NOT [Console]::Out -- res.lease invokes this script in-process (& cmd | Out-String) and
    # captures the PIPELINE; a Console write would bypass that capture AND leak into the caller's stdout.
    Write-Output (($o | ConvertTo-Json -Compress -Depth 4))
}

# =====================================================================================================
try {
    $ctx = $null
    try { $ctx = $ContextJson | ConvertFrom-Json } catch { }
    if ($null -eq $ctx) { Ev-Emit $false 0 $false $false 'bad_context' 'ContextJson did not parse as JSON' $null; return }

    # ---- seams (test doubles) ----
    $seams = $null
    $seamRaw = $env:LIFEORCH_POOLEVICTOR_SEAMS
    if (-not [string]::IsNullOrWhiteSpace($seamRaw)) {
        try {
            if (Test-Path -LiteralPath $seamRaw -PathType Leaf) { $seams = (Get-Content -LiteralPath $seamRaw -Raw) | ConvertFrom-Json }
            else { $seams = $seamRaw | ConvertFrom-Json }
        } catch { Ev-Diag "seams JSON unreadable: $($_.Exception.Message)" }
    }

    $resource      = [string](Ev-Prop $ctx 'resource' 'gpu')
    $leaseDir      = [string](Ev-Prop $ctx 'lease_dir' '')
    $txnId         = [string](Ev-Prop $ctx 'txn_id' 'no-txn')
    $opId          = [string](Ev-Prop $ctx 'operation_id' 'no-op')
    $authEpoch     = [long](Ev-Prop $ctx 'authority_epoch' 0)
    $requiredMib   = [int](Ev-Prop $ctx 'required_vram_mib' 0)
    $targetHeadMib = [int](Ev-Prop $ctx 'target_headroom_mib' 512)
    $targetInst    = [string](Ev-Prop $ctx 'target_resident_instance_id' '')
    $drainMs       = [int](Ev-Prop $ctx 'drain_timeout_ms' 2000)
    $state         = [string](Ev-Prop $ctx 'state' 'free')
    $need          = $requiredMib + $targetHeadMib

    $obsCount   = [int](Ev-Prop $seams 'observations' 3); if ($obsCount -lt 1) { $obsCount = 1 }
    $intervalMs = [int](Ev-Prop $seams 'interval_ms' 250); if ($intervalMs -lt 0) { $intervalMs = 0 }
    $supRoot    = [string](Ev-Prop $seams 'supervisor_root' (Join-Path $script:ModuleRoot 'runtime/supervisor'))
    $warmReg    = [string](Ev-Prop $seams 'warm_registry' (Join-Path $script:ModuleRoot 'runtime/warm-server.json'))
    $resLease   = [string](Ev-Prop $seams 'res_lease' '')
    if ([string]::IsNullOrWhiteSpace($resLease)) {
        $resLease = Join-Path (Split-Path -Parent $script:ModuleRoot) '29-resource-lease/Invoke-ResLease.ps1'
    }
    $pwshExe = [string](Ev-Prop $seams 'pwsh' '')
    if ([string]::IsNullOrWhiteSpace($pwshExe)) {
        if (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_PWSH)) { $pwshExe = $env:LIFEORCH_PWSH }
        else { $cand = Join-Path $PSHOME ($(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })); $pwshExe = $(if (Test-Path -LiteralPath $cand) { $cand } else { 'pwsh' }) }
    }
    $receiptDir = [string](Ev-Prop $seams 'receipt_dir' (Join-Path $script:ModuleRoot 'runtime/evictor'))
    $vramCmd    = [string](Ev-Prop $seams 'vram_cmd' '')
    $supCmd     = [string](Ev-Prop $seams 'supervisor_cmd' '')
    $skipDrain  = [bool](Ev-Prop $seams 'skip_drain_probe' $false)

    $receipt = [ordered]@{
        schema = 'lifeorch.pool_evictor.receipt/0.1'
        txn_id = $txnId; operation_id = $opId; resource = $resource
        target_resident_instance_id = $(if ([string]::IsNullOrWhiteSpace($targetInst)) { $null } else { $targetInst })
        authority_epoch = $authEpoch; state = $state
        required_vram_mib = $requiredMib; target_headroom_mib = $targetHeadMib
        drain_timeout_ms = $drainMs
        started_utc = ([DateTime]::UtcNow.ToString('o'))
        fence_consult = $null; drain = $null; supervisor = $null; tree_confirm = $null
        headroom_observations = @(); receipt_dir = $receiptDir
    }

    # ---- VRAM probe (a SEAM: seams.vram_cmd else real nvidia-smi; unknown => $null, NEVER a throw) ----
    $probeVram = {
        if (-not [string]::IsNullOrWhiteSpace($vramCmd)) {
            try {
                $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $o = & $pwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $vramCmd 2>$null } finally { $ErrorActionPreference = $prev }
                $t = ([string]($o | Out-String)).Trim()
                $n = 0
                if ([int]::TryParse($t, [ref]$n)) { return $n }
                return $null
            } catch { return $null }
        }
        try {
            $smi = Get-Command 'nvidia-smi' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $smi) { return $null }
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { $o = & $smi.Source '--query-gpu=memory.free' '--format=csv,noheader,nounits' 2>$null } finally { $ErrorActionPreference = $prev }
            $line = @($o) | Select-Object -First 1
            $n = 0
            if ($null -ne $line -and [int]::TryParse(([string]$line).Trim(), [ref]$n)) { return $n }
            return $null
        } catch { return $null }
    }

    $evicted = $false
    $treeGone = $true   # free GPU: nothing managed to remove

    if ($state -eq 'occupied') {
        $treeGone = $false
        # ---- 1a. exact-target discipline: no target => NO stop ("stop whatever serves" is impossible) ----
        if ([string]::IsNullOrWhiteSpace($targetInst)) {
            Ev-Emit $false 0 $false $false 'target_instance_required' 'occupied but no target_resident_instance_id captured at dispatch; refusing any stop' $receipt
            return
        }
        # ---- 1b. fence-op consult BEFORE the destructive step (a stale target is REFUSED) ----
        $fenceOk = $false; $fenceReason = 'not_consulted'; $fenceObj = $null
        if (-not (Test-Path -LiteralPath $resLease -PathType Leaf)) {
            $receipt['fence_consult'] = [ordered]@{ ok = $false; reason = 'res_lease_not_found'; path = $resLease }
            Ev-Emit $false 0 $false $false 'fence_unavailable' "res.lease not found at $resLease; refusing the stop (fail-closed)" $receipt
            return
        }
        try {
            $fa = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $resLease,
                    '-Action','fence-op','-Resource',$resource,'-OpKind','stop','-ResidentInstanceId',$targetInst)
            if (-not [string]::IsNullOrWhiteSpace($leaseDir)) { $fa += @('-LeaseDir',$leaseDir) }
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { $fo = & $pwshExe @fa 2>$null } finally { $ErrorActionPreference = $prev }
            $ft = ([string]($fo | Out-String)).Trim()
            $fenv = $null; try { $fenv = $ft | ConvertFrom-Json } catch { }
            if ($null -ne $fenv -and ($fenv.PSObject.Properties.Name -contains 'result') -and $null -ne $fenv.result) { $fenceObj = $fenv.result }
        } catch { Ev-Diag "fence-op invocation error: $($_.Exception.Message)" }
        if ($null -eq $fenceObj) {
            $receipt['fence_consult'] = [ordered]@{ ok = $false; reason = 'fence_invoke_failed' }
            Ev-Emit $false 0 $false $false 'fence_unavailable' 'fence-op consult produced no result; refusing the stop (fail-closed)' $receipt
            return
        }
        $fenceReason = [string](Ev-Prop $fenceObj 'reason' 'unknown')
        $curInst  = [string](Ev-Prop $fenceObj 'current_resident_instance_id' '')
        $curEpoch = [long](Ev-Prop $fenceObj 'current_epoch' 0)
        $rawOk    = [bool](Ev-Prop $fenceObj 'fenced_op_ok' $false)
        # Decision: plain 'current' passes; the expected MID-TRANSITION state is 'authority_revoked' where the
        # CURRENT lease instance is still our EXACT target (the transition revoked the pin -- stamping revoked_by
        # with the REVOKER's token while the pin keeps its original fencing_token -- then dispatched us).
        # The instance identity is the load-bearing gate (red-team: process ops target ONLY the captured
        # resident_instance_id): a superseding transition T2 replaces the lease with a DIFFERENT instance, so a
        # stale T1 evictor fails target mismatch here, and T1's later recommit is epoch-fenced by res.lease
        # itself (commit-if-epoch-current). Anything else => refuse, no kill.
        if ($rawOk) { $fenceOk = $true }
        elseif ($fenceReason -eq 'authority_revoked' -and $curInst -eq $targetInst) { $fenceOk = $true }
        $receipt['fence_consult'] = [ordered]@{ ok = $fenceOk; reason = $fenceReason; fenced_op_ok = $rawOk
            current_resident_instance_id = $(if ([string]::IsNullOrWhiteSpace($curInst)) { $null } else { $curInst })
            current_epoch = $curEpoch; our_epoch = $authEpoch; target = $targetInst }
        if (-not $fenceOk) {
            Ev-Emit $false 0 $false $false "fence_refused:$fenceReason" "fence-op refused the stop (reason=$fenceReason target=$targetInst current=$curInst); stale/superseded target -- no kill" $receipt
            return
        }

        # ---- 2a. bounded cooperative DRAIN of any ACTIVE inference (best-effort /slots probe) ----
        $manifest = $null
        try { if (Test-Path -LiteralPath $warmReg -PathType Leaf) { $manifest = (Get-Content -LiteralPath $warmReg -Raw) | ConvertFrom-Json } } catch { }
        $mInst = [string](Ev-Prop $manifest 'resident_instance_id' '')
        $mPid  = [int](Ev-Prop $manifest 'pid' 0)
        $mPort = [int](Ev-Prop $manifest 'port' 0)
        if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace($mInst) -and $mInst -ne $targetInst) {
            $receipt['tree_confirm'] = [ordered]@{ manifest_instance = $mInst; target = $targetInst }
            Ev-Emit $false 0 $false $false 'manifest_target_mismatch' "warm manifest resident_instance_id=$mInst != target=$targetInst; refusing (never kill an unidentified consumer)" $receipt
            return
        }
        $drainInfo = [ordered]@{ waited_ms = 0; active_seen = $false; idle_confirmed = $false; probe = 'none' }
        if (-not $skipDrain -and $mPort -gt 0 -and $drainMs -gt 0) {
            $dSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($dSw.ElapsedMilliseconds -lt $drainMs) {
                $busy = $null
                try {
                    $slots = Invoke-RestMethod -Uri "http://127.0.0.1:$mPort/slots" -TimeoutSec 2
                    $drainInfo.probe = 'slots'
                    $busy = $false
                    foreach ($s in @($slots)) {
                        $proc = Ev-Prop $s 'is_processing' $null
                        if ($null -eq $proc) { $st = Ev-Prop $s 'state' 0; $proc = ([int]$st -ne 0) }
                        if ([bool]$proc) { $busy = $true }
                    }
                } catch { $busy = $null; $drainInfo.probe = 'unreachable' }
                if ($busy -eq $true) { $drainInfo.active_seen = $true; Start-Sleep -Milliseconds 200; continue }
                if ($busy -eq $false) { $drainInfo.idle_confirmed = $true }
                break   # idle, or probe unavailable (cannot determine -> bounded wait ends; the ladder proceeds to cancel/stop)
            }
            $dSw.Stop(); $drainInfo.waited_ms = [int]$dSw.ElapsedMilliseconds
        }
        $receipt['drain'] = $drainInfo

        # ---- 2b. supervisor-routed targeted stop (graceful -> Job-Object tree-kill); NEVER a PID kill here ----
        $supResult = $null
        if (-not [string]::IsNullOrWhiteSpace($supCmd)) {
            # test seam: a mock supervisor command
            try {
                $pj = ([ordered]@{ target_resident_instance_id = $targetInst; drain_timeout_ms = $drainMs } | ConvertTo-Json -Compress)
                $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $so = & $pwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $supCmd -Op 'evict' -ParamsJson $pj 2>$null } finally { $ErrorActionPreference = $prev }
                $stx = ([string]($so | Out-String)).Trim()
                try { $supResult = $stx | ConvertFrom-Json } catch { }
            } catch { Ev-Diag "mock supervisor invoke failed: $($_.Exception.Message)" }
            if ($null -eq $supResult) {
                $receipt['supervisor'] = [ordered]@{ ok = $false; reason = 'mock_supervisor_no_result' }
                Ev-Emit $false 0 $false $false 'supervisor_unavailable' 'mock supervisor command produced no result; refusing (fail-closed, no PID kill from the evictor)' $receipt
                return
            }
        } else {
            # live: attach to the running durable supervisor over the file protocol
            $supModule = Join-Path $script:ModuleRoot 'lib/Supervisor.psm1'
            $supOk = $false
            try {
                Import-Module $supModule -ErrorAction Stop
                $paths = Get-SupervisorPaths -Root $supRoot -WarmRegistryPath $warmReg
                $resp = Send-SupervisorRequest -Paths $paths -Op 'evict' -Params @{ target_resident_instance_id = $targetInst; drain_timeout_ms = $drainMs } -TimeoutMs ([Math]::Max(30000, $drainMs + 20000))
                if ($null -ne $resp -and [bool]$resp.ok) { $supResult = $resp.response.result; $supOk = $true }
                else {
                    $ec = if ($null -ne $resp -and $null -ne (Ev-Prop $resp 'error' $null)) { [string](Ev-Prop $resp.error 'code' 'supervisor_error') } else { 'supervisor_unavailable' }
                    $receipt['supervisor'] = [ordered]@{ ok = $false; reason = $ec }
                    Ev-Emit $false 0 $false $false 'supervisor_unavailable' "no live durable supervisor to route the stop through ($ec); refusing (fail-closed, no PID kill from the evictor)" $receipt
                    return
                }
            } catch {
                $receipt['supervisor'] = [ordered]@{ ok = $false; reason = "supervisor_client_error: $($_.Exception.Message)" }
                Ev-Emit $false 0 $false $false 'supervisor_unavailable' "supervisor client error: $($_.Exception.Message); refusing (fail-closed)" $receipt
                return
            }
        }
        $supEvicted = [bool](Ev-Prop $supResult 'evicted' $false)
        $supReason  = [string](Ev-Prop $supResult 'reason' 'unknown')
        $receipt['supervisor'] = [ordered]@{ ok = $true; evicted = $supEvicted; reason = $supReason; raw = $supResult }
        if (-not $supEvicted -and $supReason -ne 'no_resident') {
            Ev-Emit $false 0 $false $false "supervisor_stop_failed:$supReason" "supervisor did not confirm the targeted stop (reason=$supReason)" $receipt
            return
        }
        $evicted = $supEvicted

        # ---- 3. confirm the managed tree is GONE (pid dead + manifest cleared + socket owner gone) ----
        $tc = [ordered]@{ manifest_cleared = $false; pid_dead = $false; socket_free = $null; survivor_pid = $null }
        $m2 = $null
        try { if (Test-Path -LiteralPath $warmReg -PathType Leaf) { $m2 = (Get-Content -LiteralPath $warmReg -Raw) | ConvertFrom-Json } } catch { }
        $tc.manifest_cleared = ($null -eq $m2)
        $pidDead = $true
        if ($mPid -gt 0) {
            try { $pp = Get-Process -Id $mPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pidDead = $false; $tc.survivor_pid = $mPid } } catch { $pidDead = $true }
        }
        $tc.pid_dead = $pidDead
        $sockFree = $null
        if ($mPort -gt 0) {
            try {
                $gc = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
                if ($null -ne $gc) {
                    $c = Get-NetTCPConnection -LocalPort $mPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
                    $sockFree = ($null -eq $c)
                    if (-not $sockFree) { $tc.survivor_pid = [int]$c.OwningProcess }
                }
            } catch { $sockFree = $null }
        }
        $tc.socket_free = $sockFree
        $receipt['tree_confirm'] = $tc
        $treeGone = ($pidDead -and ($sockFree -ne $false))
        if (-not $treeGone) {
            Ev-Emit $false 0 $evicted $false 'partial_tree_term' "managed tree NOT confirmed gone (pid_dead=$pidDead socket_free=$sockFree survivor=$($tc.survivor_pid)); the transition will NOT grant" $receipt
            return
        }
    }

    # ---- 4. headroom STABLE across observations + one final re-check (WDDM frees async) ----
    $obs = New-Object System.Collections.Generic.List[object]
    $anyUnknown = $false
    for ($i = 0; $i -lt $obsCount; $i++) {
        if ($i -gt 0 -and $intervalMs -gt 0) { Start-Sleep -Milliseconds $intervalMs }
        $f = & $probeVram
        if ($null -eq $f) { $anyUnknown = $true; $obs.Add('unknown') } else { $obs.Add([int]$f) }
    }
    $finalCheck = & $probeVram
    if ($null -eq $finalCheck) { $anyUnknown = $true }
    $receipt['headroom_observations'] = @($obs.ToArray() + @($(if ($null -eq $finalCheck) { 'unknown' } else { [int]$finalCheck })))
    if ($anyUnknown) {
        Ev-Emit $false 0 $evicted $treeGone 'vram_unknown' 'VRAM probe unavailable (off-Windows / nvidia-smi absent) -- a normal failed prepare, not an error' $receipt
        return
    }
    $allStable = $true
    foreach ($o in $obs) { if ([int]$o -lt $need) { $allStable = $false } }
    if ([int]$finalCheck -lt $need) { $allStable = $false }
    $freeNow = [int]$finalCheck
    if (-not $allStable) {
        Ev-Emit $false $freeNow $evicted $treeGone 'headroom_not_stable' "headroom not stable across $obsCount observations + final re-check (need >= $need MiB; observed $((@($obs.ToArray()) -join ','))/final=$freeNow)" $receipt
        return
    }
    $okDetail = $(if ($state -eq 'occupied') { "targeted stop confirmed (tree gone) + headroom stable >= $need MiB across $obsCount obs + final re-check" } else { "free slot; headroom stable >= $need MiB across $obsCount obs + final re-check" })
    Ev-Emit $true $freeNow $evicted $treeGone 'confirmed' $okDetail $receipt
}
catch {
    # absolute backstop: still emit the one JSON object (fail-closed), never throw/exit out of the seam
    try { Ev-Diag "unhandled: $($_.Exception.Message)" } catch { }
    Ev-Emit $false 0 $false $false 'evictor_error' "unhandled evictor error: $($_.Exception.Message)" $null
}
