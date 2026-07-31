#requires -Version 7.0
# =====================================================================================================
# Supervisor.psm1 -- model.gateway #7 warm-pool DURABLE gateway supervisor core (WARM_POOL_DESIGN
# section 10 residual (a); the durable form of red-team finding 5). Stage-1.1 shipped a per-call
# residency path (managed tag + taskkill /T + a PID/creation-time guard); a per-call Windows Job Object
# dies on process exit, so durable ownership of the llama-server tree ACROSS separate invocations needs a
# PERSISTENT supervisor. This module is that supervisor's INTEGRITY + PROTOCOL core.
#
# Like PoolManager.psm1 it is deliberately free of any hard live-model / GPU / Windows dependency: every
# host-specific action (launch a server, kill a tree, a Windows Job Object, nvidia-smi VRAM, the socket
# owner, /health) enters through an INJECTABLE SEAM, so every invariant -- the control protocol, the
# attach/reuse handshake, the residency state machine, reconcile-on-restart -- is unit-testable OFF-MACHINE
# (cloud pwsh 7.4.6 on Linux) with a deterministic stub, and unchanged live via the executor. A seam that is
# unavailable off-Windows degrades to a reported 'unsupported'/'unknown' and NEVER throws.
#
# It EXTENDS (never replaces) PoolManager.psm1: the supervisor is the single owner that runs the
# PoolManager transitions (fencing token + CAS, CanServe, the crash-atomic state machine
# EMPTY->STOPPING->EMPTY_CONFIRMED->STARTING->RESIDENT, verified socket-owner publish, GPU-handoff
# planning). All integrity invariants stay NON-bypassable; the -BypassPoolManager cold-isolated escape in
# the gateway is untouched. The pool STAYS DEFAULT-OFF this wave.
#
# Control channel = a FILE-PROTOCOL control dir under runtime/supervisor/ (chosen over a named pipe /
# loopback endpoint because it is cross-platform testable, crash-atomic via tmp+Move, and matches the
# executor/res.lease file idioms already trusted in this repo). Request -> req/<id>.json; the supervisor
# answers atomically into resp/<id>.json. The RESIDENT manifest stays at runtime/warm-server.json (the
# existing lifeorch.model_gateway.warm/0.3 schema) so the gateway's classic reuse + PoolStatus paths read a
# supervisor-published resident with ZERO changes.
#
# ASCII-only (Windows PowerShell 5.1 / dev.ship AST + non-ASCII grep). UTF-8 no BOM. LF.
# =====================================================================================================
Set-StrictMode -Version Latest

# Reuse the shipped integrity core (fencing, CanServe, state machine, manifest atomics, lock, GPU planner).
# IDEMPOTENT import: if PoolManager is ALREADY loaded (e.g. the entrypoint imported it -Global), do NOT
# re-import -- a `-Force` re-import would EVICT the caller's global PoolManager and re-scope it privately to
# this module, which makes Get-ResidentConfig / New-InstanceGeneration vanish from global and breaks every
# GetNewClosure handler that resolves them (a real, debugged trap). Only import when the core is absent.
if (Get-Command 'Get-ResidentConfig' -ErrorAction SilentlyContinue) { $script:SupPoolCoreLoaded = $true }
else { try { Import-Module (Join-Path $PSScriptRoot 'PoolManager.psm1') -ErrorAction Stop; $script:SupPoolCoreLoaded = $true } catch { $script:SupPoolCoreLoaded = $false } }

$script:SUP_MANIFEST_SCHEMA = 'lifeorch.model_gateway.supervisor/0.1'
$script:SUP_REQ_SCHEMA      = 'lifeorch.model_gateway.supervisor_request/0.1'
$script:SUP_RESP_SCHEMA     = 'lifeorch.model_gateway.supervisor_response/0.1'
$script:SUP_OPS             = @('ping','status','ensure_resident','prepare_gpu','evict','reconcile','shutdown')
$script:SupUtf8NoBom        = [System.Text.UTF8Encoding]::new($false)

function Test-SupHasProp { param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Name) }
    return ($Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name))
}
function Get-SupNowUtc { return [DateTime]::UtcNow }
function ConvertTo-SupUtcString { param([DateTime]$T) return $T.ToString('o') }
function ConvertFrom-SupUtcString { param([string]$S)
    if ([string]::IsNullOrWhiteSpace($S)) { return $null }
    try { return [DateTime]::Parse($S, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { return $null }
}
function Read-SupJson { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
# Atomic write (tmp + Move -Force): a reader never observes a half-written control/manifest file.
function Write-SupJsonAtomic { param([string]$Path, [object]$Obj)
    try {
        $dir = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Path.tmp-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        [System.IO.File]::WriteAllText($tmp, ($Obj | ConvertTo-Json -Depth 12), $script:SupUtf8NoBom)
        [System.IO.File]::Move($tmp, $Path, $true)
        return $true
    } catch { return $false }
}
function Test-SupPidAlive { param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try { $null = Get-Process -Id $ProcessId -ErrorAction Stop; return $true } catch { return $false }
}

# ------------------------------------------------------------------------------------------------
# Paths. Everything the supervisor owns lives under a single root (default runtime/supervisor/), so a
# test can point it at an isolated scratch dir. The RESIDENT manifest (warm-server.json) is passed in
# separately (it is shared with the gateway's classic path) and defaults next to the module runtime.
# ------------------------------------------------------------------------------------------------
function Get-SupervisorPaths {
    param([Parameter(Mandatory)][string]$Root, [string]$WarmRegistryPath)
    $root = $Root
    $ctrl = Join-Path $root 'control'
    $warm = if (-not [string]::IsNullOrWhiteSpace($WarmRegistryPath)) { $WarmRegistryPath } else { Join-Path (Split-Path -Parent $root) 'warm-server.json' }
    return [ordered]@{
        root            = $root
        manifest        = (Join-Path $root 'supervisor.json')
        control         = $ctrl
        req_dir         = (Join-Path $ctrl 'req')
        resp_dir        = (Join-Path $ctrl 'resp')
        stop_sentinel   = (Join-Path $ctrl 'stop')
        warm_registry   = $warm
        warm_lock       = "$warm.lock"
        log             = (Join-Path $root 'supervisor.log')
    }
}
function Initialize-SupervisorDirs {
    param([Parameter(Mandatory)]$Paths)
    foreach ($d in @($Paths.root, $Paths.control, $Paths.req_dir, $Paths.resp_dir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ------------------------------------------------------------------------------------------------
# i23 MF3 (red-team blocker: two-start race / must-fix 3): LIFETIME SUPERVISOR SINGLETON. A named OS mutex,
# keyed by the CANONICAL supervisor root, claimed in 'run' BEFORE the manifest is published. A second
# supervisor that cannot claim it EXITS cleanly (no double custody of the GPU tree). An ABANDONED mutex (the
# prior supervisor died without releasing) counts as ACQUIRED -- the new generation takes over. The claim is
# thread-affine (acquired + released on the run loop's main thread). Self-contained hash (no PoolManager dep)
# so it works even if the integrity core failed to load. Cross-platform (Windows session namespace / Linux
# temp-backed named mutex); proven cross-process on the cloud gate.
# ------------------------------------------------------------------------------------------------
function Get-SupervisorSingletonName {
    param([Parameter(Mandatory)][string]$Root)
    $canon = try { [System.IO.Path]::GetFullPath($Root) } catch { $Root }
    $canon = ($canon.TrimEnd('/','\')).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hex = ([System.BitConverter]::ToString($sha.ComputeHash($script:SupUtf8NoBom.GetBytes($canon)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    return ('lifeorch_gwsup_' + $hex.Substring(0, 24))
}
function Enter-SupervisorSingleton {
    param([Parameter(Mandatory)][string]$Root, [int]$TimeoutMs = 0)
    $name = Get-SupervisorSingletonName $Root
    $mx = $null
    try { $created = $false; $mx = [System.Threading.Mutex]::new($false, $name, [ref]$created) }
    catch { return [ordered]@{ acquired = $false; mutex = $null; name = $name; reason = "mutex_create_failed:$($_.Exception.Message)"; supported = $false } }
    $got = $false
    try { $got = $mx.WaitOne([Math]::Max(0, $TimeoutMs)) }
    catch [System.Threading.AbandonedMutexException] { $got = $true }   # prior owner died -> we inherit it
    catch { $got = $false }
    if (-not $got) { try { $mx.Dispose() } catch { }; return [ordered]@{ acquired = $false; mutex = $null; name = $name; reason = 'held_by_other'; supported = $true } }
    return [ordered]@{ acquired = $true; mutex = $mx; name = $name; reason = 'ok'; supported = $true }
}
function Exit-SupervisorSingleton {
    param([object]$Claim)
    if ($null -eq $Claim -or -not (Test-SupHasProp $Claim 'mutex') -or $null -eq $Claim.mutex) { return $false }
    try { $Claim.mutex.ReleaseMutex() } catch { }
    try { $Claim.mutex.Dispose() } catch { }
    return $true
}

# ------------------------------------------------------------------------------------------------
# Supervisor manifest: identity (pid + creation-time + a per-launch nonce) + a heartbeat. A client PROVES
# the supervisor is live by (pid alive) AND (creation-time matches, rejecting PID reuse) AND (heartbeat
# fresh). The StartTicksProbe is a seam (Process.StartTime); off-box liveness stays advisory, never throws.
# ------------------------------------------------------------------------------------------------
function Write-SupervisorManifest { param([string]$Path, [object]$Obj) return (Write-SupJsonAtomic -Path $Path -Obj $Obj) }
function Read-SupervisorManifest  { param([string]$Path) return (Read-SupJson -Path $Path) }
function Clear-SupervisorManifest { param([string]$Path) try { if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue } } catch { } }

function Test-SupervisorHeartbeatFresh {
    param([object]$Manifest, [int]$MaxAgeSeconds = 30, [DateTime]$Now = (Get-SupNowUtc))
    if ($null -eq $Manifest -or -not (Test-SupHasProp $Manifest 'heartbeat_utc')) { return $false }
    $hb = ConvertFrom-SupUtcString ([string]$Manifest.heartbeat_utc)
    if ($null -eq $hb) { return $false }
    return (($Now - $hb).TotalSeconds -le $MaxAgeSeconds)
}
function Test-SupervisorLiveness {
    param([object]$Manifest, [scriptblock]$StartTicksProbe = $null, [int]$HeartbeatMaxAgeSeconds = 30)
    $res = [ordered]@{ present = $false; alive = $false; identity_ok = $false; heartbeat_fresh = $false; running = $false; pid = $null }
    if ($null -eq $Manifest -or -not (Test-SupHasProp $Manifest 'pid')) { return $res }
    $res.present = $true
    $procId = [int]$Manifest.pid; $res.pid = $procId
    $proc = $null
    try { $proc = Get-Process -Id $procId -ErrorAction Stop } catch { return $res }
    $res.alive = $true
    try {
        $wantTicks = if (Test-SupHasProp $Manifest 'start_ticks') { [long]$Manifest.start_ticks } else { 0 }
        if ($wantTicks -gt 0) {
            $haveTicks = if ($null -ne $StartTicksProbe) { [long](& $StartTicksProbe $procId) } else { [long]$proc.StartTime.Ticks }
            $res.identity_ok = ([Math]::Abs($haveTicks - $wantTicks) -lt [TimeSpan]::FromSeconds(2).Ticks)
        } else { $res.identity_ok = $true }
    } catch { $res.identity_ok = $false }
    $res.heartbeat_fresh = Test-SupervisorHeartbeatFresh -Manifest $Manifest -MaxAgeSeconds $HeartbeatMaxAgeSeconds
    $stateRunning = (-not (Test-SupHasProp $Manifest 'state')) -or ([string]$Manifest.state -eq 'RUNNING')
    # "running" for routing = alive AND identity matches AND still in RUNNING state (unchanged; start/status use it).
    $res.running = ($res.alive -and $res.identity_ok -and $stateRunning)
    # i23 MF8 (red-team blocker 6): RESPONSIVE folds in heartbeat freshness. running-but-NOT-responsive == a
    # WEDGED supervisor (process alive, still holding the GPU tree, but its IPC + heartbeat loop have stalled).
    # The client MUST NOT fall back to a per-call second server in that state (that + a stolen lock = split-brain);
    # it fails closed until the out-of-process watchdog kills + relaunches the wedged supervisor.
    $res['responsive'] = ($res.running -and $res.heartbeat_fresh)
    return $res
}

# ------------------------------------------------------------------------------------------------
# Control protocol (PURE): request / response encode + decode + validate. request_id is caller-supplied
# or a fresh GUID; the response file is named by the SAME request_id so a client polls one deterministic path.
# ------------------------------------------------------------------------------------------------
function New-SupervisorRequest {
    param([Parameter(Mandatory)][string]$Op, [hashtable]$Params, [string]$RequestId,
          [string]$ExpectGeneration, [long]$ExpectFence = -1, [string]$Holder)
    $rid = if (-not [string]::IsNullOrWhiteSpace($RequestId)) { $RequestId } else { [Guid]::NewGuid().ToString('N') }
    $p = [ordered]@{}
    if ($null -ne $Params) { foreach ($k in $Params.Keys) { $p[[string]$k] = $Params[$k] } }
    return [ordered]@{
        schema            = $script:SUP_REQ_SCHEMA
        request_id        = $rid
        op                = $Op
        params            = $p
        holder            = $Holder
        expect_generation = $ExpectGeneration
        expect_fence      = $ExpectFence
        created_utc       = (ConvertTo-SupUtcString (Get-SupNowUtc))
    }
}
# i23 MF4 (red-team blocker 2): a STRICT request_id format so an id that becomes a response FILENAME cannot
# escape the control dir (path containment). Legitimate ids are GUID-N (32 hex) -> conform. Reject anything
# with a path separator, '..', drive/UNC, or a non-[A-Za-z0-9_.-] byte.
$script:SUP_REQID_RE = [regex]'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$'
function Test-SupervisorRequestId {
    param([string]$RequestId)
    if ([string]::IsNullOrWhiteSpace($RequestId)) { return $false }
    if ($RequestId -match '[\\/:]' -or $RequestId.Contains('..')) { return $false }
    return $script:SUP_REQID_RE.IsMatch($RequestId)
}
# The mutating ops that require replay/target/generation authentication (read-only ping/status are exempt).
$script:SUP_MUTATING_OPS = @('ensure_resident','prepare_gpu','evict','reconcile','shutdown')
# Idempotent request-receipt ledger (per supervisor process): a replayed destructive request_id is refused.
$script:SupConsumedRequests = @{}
function Reset-SupervisorConsumedRequests { $script:SupConsumedRequests = @{} }
function Test-SupervisorRequestValid {
    param([object]$Request)
    $errs = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Request) { $errs.Add('null_request'); return [ordered]@{ valid = $false; errors = $errs.ToArray() } }
    if (-not (Test-SupHasProp $Request 'schema') -or [string]$Request.schema -ne $script:SUP_REQ_SCHEMA) { $errs.Add('bad_schema') }
    $rid = if (Test-SupHasProp $Request 'request_id') { [string]$Request.request_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($rid)) { $errs.Add('missing_request_id') }
    elseif (-not (Test-SupervisorRequestId $rid)) { $errs.Add('bad_request_id') }   # i23 MF4: path-containment
    $op = if (Test-SupHasProp $Request 'op') { [string]$Request.op } else { '' }
    if ([string]::IsNullOrWhiteSpace($op) -or ($script:SUP_OPS -notcontains $op)) { $errs.Add("bad_op:$op") }
    return [ordered]@{ valid = ($errs.Count -eq 0); errors = $errs.ToArray() }
}
function Write-SupervisorRequest {
    param([Parameter(Mandatory)][string]$ReqDir, [Parameter(Mandatory)][object]$Request)
    $rid = [string]$Request.request_id
    $path = Join-Path $ReqDir "$rid.json"
    [void](Write-SupJsonAtomic -Path $path -Obj $Request)
    return $path
}
function Read-SupervisorRequestFile { param([string]$Path) return (Read-SupJson -Path $Path) }

function New-SupervisorResponse {
    param([Parameter(Mandatory)][object]$Request, [bool]$Ok, [object]$Result, [object]$ErrorObj,
          [int]$SupervisorPid = 0, [string]$SupervisorGeneration)
    $rid = if ($null -ne $Request -and (Test-SupHasProp $Request 'request_id')) { [string]$Request.request_id } else { [Guid]::NewGuid().ToString('N') }
    $op  = if ($null -ne $Request -and (Test-SupHasProp $Request 'op')) { [string]$Request.op } else { $null }
    return [ordered]@{
        schema                = $script:SUP_RESP_SCHEMA
        request_id            = $rid
        op                    = $op
        ok                    = [bool]$Ok
        result                = $Result
        error                 = $ErrorObj
        supervisor_pid        = $SupervisorPid
        supervisor_generation = $SupervisorGeneration
        handled_utc           = (ConvertTo-SupUtcString (Get-SupNowUtc))
    }
}
function Write-SupervisorResponse {
    param([Parameter(Mandatory)][string]$RespDir, [Parameter(Mandatory)][object]$Response)
    $rid = [string]$Response.request_id
    $path = Join-Path $RespDir "$rid.json"
    [void](Write-SupJsonAtomic -Path $path -Obj $Response)
    return $path
}
function Read-SupervisorResponseFile { param([string]$Path) return (Read-SupJson -Path $Path) }

# ------------------------------------------------------------------------------------------------
# CLIENT: the attach/reuse handshake. A per-call gateway writes a request and polls for the matching
# response, bounded by -TimeoutMs. It FIRST proves the supervisor is running (liveness) so an absent /
# dead supervisor returns supervisor_unavailable IMMEDIATELY and the caller can degrade to the classic
# per-call path (the pool is an OPTIONAL optimised layer, never the sole authority). PURE file I/O ->
# cross-platform testable.
# ------------------------------------------------------------------------------------------------
function Send-SupervisorRequest {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$Op,
        [hashtable]$Params,
        [string]$ExpectGeneration,
        [long]$ExpectFence = -1,
        [string]$Holder,
        [int]$TimeoutMs = 20000,
        [int]$PollMs = 50,
        [scriptblock]$StartTicksProbe = $null,
        [int]$HeartbeatMaxAgeSeconds = 30
    )
    $manifest = Read-SupervisorManifest $Paths.manifest
    $live = Test-SupervisorLiveness -Manifest $manifest -StartTicksProbe $StartTicksProbe -HeartbeatMaxAgeSeconds $HeartbeatMaxAgeSeconds
    if (-not $live.running) {
        # absent / dead / identity-mismatch / not-RUNNING: OUR supervisor is not holding the GPU tree, so the
        # caller MAY safely degrade to the per-call path (no_fallback=false).
        return [ordered]@{ ok = $false; delivered = $false; error = [ordered]@{ code = 'supervisor_unavailable'; message = 'no running supervisor (attach failed); caller may use the per-call path'; retryable = $true; supervisor_alive = [bool]$live.alive; no_fallback = $false }; liveness = $live }
    }
    # i23 MF8: RUNNING but heartbeat STALE == WEDGED. The process is alive and STILL OWNS the GPU tree, so a
    # per-call second server would be split-brain. Fail closed (no_fallback=true) WITHOUT writing a request that
    # will never be serviced -- recovery is the out-of-process watchdog killing + relaunching the supervisor.
    if (-not $live.heartbeat_fresh) {
        return [ordered]@{ ok = $false; delivered = $false; error = [ordered]@{ code = 'supervisor_unresponsive'; message = 'supervisor process alive but heartbeat stale (wedged); failing closed -- NO per-call fallback (split-brain guard)'; retryable = $true; supervisor_alive = $true; no_fallback = $true }; liveness = $live }
    }
    Initialize-SupervisorDirs -Paths $Paths
    $req = New-SupervisorRequest -Op $Op -Params $Params -ExpectGeneration $ExpectGeneration -ExpectFence $ExpectFence -Holder $Holder
    $reqPath = Write-SupervisorRequest -ReqDir $Paths.req_dir -Request $req
    $respPath = Join-Path $Paths.resp_dir "$($req.request_id).json"
    $deadline = (Get-SupNowUtc).AddMilliseconds($TimeoutMs)
    while ((Get-SupNowUtc) -lt $deadline) {
        if (Test-Path -LiteralPath $respPath -PathType Leaf) {
            $resp = Read-SupervisorResponseFile $respPath
            if ($null -ne $resp) {
                try { Remove-Item -LiteralPath $respPath -Force -ErrorAction SilentlyContinue } catch { }
                return [ordered]@{ ok = [bool]$resp.ok; delivered = $true; response = $resp; error = $(if ($resp.ok) { $null } else { $resp.error }); request_id = $req.request_id }
            }
        }
        # if the supervisor dies mid-wait, stop waiting (fail fast so the caller can degrade -- the GPU tree is
        # gone with it, so a per-call server is safe: no_fallback=false).
        $m2 = Read-SupervisorManifest $Paths.manifest
        $l2 = Test-SupervisorLiveness -Manifest $m2 -StartTicksProbe $StartTicksProbe -HeartbeatMaxAgeSeconds $HeartbeatMaxAgeSeconds
        if (-not $l2.alive) {
            try { Remove-Item -LiteralPath $reqPath -Force -ErrorAction SilentlyContinue } catch { }
            return [ordered]@{ ok = $false; delivered = $true; error = [ordered]@{ code = 'supervisor_died'; message = 'supervisor exited while the request was in flight'; retryable = $true; supervisor_alive = $false; no_fallback = $false }; request_id = $req.request_id }
        }
        Start-Sleep -Milliseconds $PollMs
    }
    try { Remove-Item -LiteralPath $reqPath -Force -ErrorAction SilentlyContinue } catch { }
    # i23 MF8: on timeout, re-check liveness. If the process is STILL ALIVE it is WEDGED (owns the GPU tree but
    # did not answer) -> no_fallback=true (fail closed; no split-brain). Only a dead process is fallback-safe.
    $mT = Read-SupervisorManifest $Paths.manifest
    $lT = Test-SupervisorLiveness -Manifest $mT -StartTicksProbe $StartTicksProbe -HeartbeatMaxAgeSeconds $HeartbeatMaxAgeSeconds
    if ($lT.alive) {
        return [ordered]@{ ok = $false; delivered = $true; error = [ordered]@{ code = 'supervisor_timeout'; message = "no response within ${TimeoutMs} ms (supervisor process still alive -> wedged; failing closed, NO per-call fallback)"; retryable = $true; supervisor_alive = $true; no_fallback = $true }; request_id = $req.request_id }
    }
    return [ordered]@{ ok = $false; delivered = $true; error = [ordered]@{ code = 'supervisor_died'; message = "no response within ${TimeoutMs} ms and the supervisor is gone"; retryable = $true; supervisor_alive = $false; no_fallback = $false }; request_id = $req.request_id }
}

# ------------------------------------------------------------------------------------------------
# SERVER: one poll iteration. Scan the req dir oldest-first, dispatch each to $Handlers[$op] (a scriptblock
# {param($request) -> result-hashtable}; throw -> a structured error response), write the response, delete
# the request. PURE given the handler map -> testable with mock handlers off-machine. Never throws out of a
# single request (a handler fault becomes an error response, so one bad request cannot wedge the loop).
# ------------------------------------------------------------------------------------------------
function Invoke-SupervisorPollOnce {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][hashtable]$Handlers,
        [int]$SupervisorPid = 0,
        [string]$SupervisorGeneration,
        [int]$MaxPerPoll = 16
    )
    $handled = New-Object System.Collections.Generic.List[object]
    $shutdown = $false
    if (-not (Test-Path -LiteralPath $Paths.req_dir)) { return [ordered]@{ handled = $handled.ToArray(); count = 0; shutdown = $false } }
    $files = @(Get-ChildItem -LiteralPath $Paths.req_dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTimeUtc | Select-Object -First $MaxPerPoll)
    foreach ($f in $files) {
        $req = Read-SupervisorRequestFile $f.FullName
        $valid = Test-SupervisorRequestValid $req
        $resp = $null
        if (-not $valid.valid) {
            $resp = New-SupervisorResponse -Request $req -Ok $false -ErrorObj ([ordered]@{ code = 'bad_request'; message = ([string]::Join(';', $valid.errors)) }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
        } else {
            $op = [string]$req.op
            $rid = [string]$req.request_id
            $isMutating = ($script:SUP_MUTATING_OPS -contains $op)
            $expGen = if (Test-SupHasProp $req 'expect_generation') { [string]$req.expect_generation } else { '' }
            # i23 MF4: AUTHENTICATE mutating requests. (1) generation binding -- an expect_generation that does not
            # match this supervisor's generation is a stale/foreign request -> REFUSE. (2) idempotent replay guard
            # -- a request_id already consumed is REFUSED (a replayed destructive request cannot re-fire). ping /
            # status are read-only and exempt. shutdown additionally requires admin auth (a matching generation).
            $authErr = $null
            if ($isMutating) {
                if (-not [string]::IsNullOrWhiteSpace($expGen) -and -not [string]::IsNullOrWhiteSpace($SupervisorGeneration) -and $expGen -ne $SupervisorGeneration) {
                    $authErr = [ordered]@{ code = 'generation_mismatch'; message = "expect_generation '$expGen' != supervisor '$SupervisorGeneration' (stale/foreign request refused)" }
                }
                elseif ($script:SupConsumedRequests.ContainsKey($rid)) {
                    $authErr = [ordered]@{ code = 'stale_or_replayed'; message = "request_id already consumed (idempotent replay guard)" }
                }
            }
            if ($null -ne $authErr) {
                $resp = New-SupervisorResponse -Request $req -Ok $false -ErrorObj $authErr -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
            } elseif ($op -eq 'shutdown') {
                # i23 MF4: shutdown is a SEPARATE AUTHENTICATED ADMIN op -- it MUST carry the supervisor's exact
                # generation (proving the caller read the current manifest). An unauthenticated/stale shutdown is
                # refused (never a plain dispatch).
                if ([string]::IsNullOrWhiteSpace($SupervisorGeneration)) {
                    # generation unknown (bare unit tests): accept (no authority to check against)
                    $shutdown = $true
                    $resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ action = 'shutdown'; accepted = $true; admin_authenticated = $false }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
                } elseif ($expGen -eq $SupervisorGeneration) {
                    $shutdown = $true
                    $resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ action = 'shutdown'; accepted = $true; admin_authenticated = $true }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
                } else {
                    $resp = New-SupervisorResponse -Request $req -Ok $false -ErrorObj ([ordered]@{ code = 'admin_auth_required'; message = 'shutdown requires the supervisor generation (authenticated admin op); refused' }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
                }
                if ($shutdown) { $script:SupConsumedRequests[$rid] = (ConvertTo-SupUtcString (Get-SupNowUtc)) }
            } elseif ($op -eq 'ping') {
                $resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ action = 'ping'; pong = $true; supervisor_pid = $SupervisorPid }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
            } elseif ($Handlers.ContainsKey($op)) {
                try {
                    $r = & $Handlers[$op] $req
                    $resp = New-SupervisorResponse -Request $req -Ok $true -Result $r -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
                    if ($isMutating) { $script:SupConsumedRequests[$rid] = (ConvertTo-SupUtcString (Get-SupNowUtc)) }   # consumed only on success
                } catch {
                    $ex = $_.Exception
                    $code = 'handler_error'; $msg = "$($ex.Message)"
                    if ($null -ne $ex -and (Test-SupHasProp $ex 'code')) { $code = [string]$ex.code }
                    $tgt = $_.TargetObject
                    if ($null -ne $tgt -and (Test-SupHasProp $tgt 'code')) { $code = [string]$tgt.code; if (Test-SupHasProp $tgt 'message') { $msg = [string]$tgt.message } }
                    $resp = New-SupervisorResponse -Request $req -Ok $false -ErrorObj ([ordered]@{ code = $code; message = $msg }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
                }
            } else {
                $resp = New-SupervisorResponse -Request $req -Ok $false -ErrorObj ([ordered]@{ code = 'unsupported_op'; message = "no handler for op '$op'" }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
            }
        }
        # i23 MF4: PATH CONTAINMENT -- the response filename derives from request_id, which is validated by
        # Test-SupervisorRequestValid above; a bad id yields a 'bad_request' response written under a SAFE
        # sanitized name so a crafted id can never place a file outside resp_dir.
        $respRid = [string]$resp.request_id
        if (-not (Test-SupervisorRequestId $respRid)) {
            $safe = ('badreq_' + [Guid]::NewGuid().ToString('N').Substring(0,12))
            $resp['request_id'] = $safe
        }
        [void](Write-SupervisorResponse -RespDir $Paths.resp_dir -Response $resp)
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } catch { }
        $handled.Add([ordered]@{ request_id = $resp.request_id; op = $resp.op; ok = $resp.ok })
    }
    return [ordered]@{ handled = $handled.ToArray(); count = $handled.Count; shutdown = $shutdown }
}

# ------------------------------------------------------------------------------------------------
# Windows JOB OBJECT (P/Invoke). The supervisor creates ONE job with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
# and assigns every llama-server it starts to it -> if the supervisor dies (any reason), the last handle
# to the job closes and the OS reaps the WHOLE server tree (durable finding-5 guarantee, own-by-HANDLE not
# by process-name). The job handle is NON-inheritable so a launched child does not keep the job open.
# Off-Windows every call degrades to { supported = $false } and NEVER throws (the state machine still runs;
# tests substitute a fake job whose Close reaps tracked pids).
# ------------------------------------------------------------------------------------------------
$script:JobTypeLoaded = $false
function Initialize-JobObjectType {
    if ($script:JobTypeLoaded) { return $true }
    if (-not $IsWindows) { return $false }
    $src = @'
using System;
using System.Runtime.InteropServices;
public static class LifeorchJob {
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount; public ulong WriteOperationCount; public ulong OtherOperationCount;
        public ulong ReadTransferCount; public ulong WriteTransferCount; public ulong OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    public const int JobObjectExtendedLimitInformation = 9;
    public const uint PROCESS_ALL_ACCESS = 0x1F0FFF;
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
    public static IntPtr CreateKillOnCloseJob(string name) {
        IntPtr h = CreateJobObject(IntPtr.Zero, name);
        if (h == IntPtr.Zero) return IntPtr.Zero;
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(len);
        try {
            Marshal.StructureToPtr(info, p, false);
            if (!SetInformationJobObject(h, JobObjectExtendedLimitInformation, p, (uint)len)) { CloseHandle(h); return IntPtr.Zero; }
        } finally { Marshal.FreeHGlobal(p); }
        return h;
    }
    public static bool AssignPid(IntPtr hJob, int pid) {
        IntPtr hp = OpenProcess(PROCESS_ALL_ACCESS, false, pid);
        if (hp == IntPtr.Zero) return false;
        try { return AssignProcessToJobObject(hJob, hp); } finally { CloseHandle(hp); }
    }
}
'@
    try { Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop; $script:JobTypeLoaded = $true; return $true } catch { return $false }
}
function New-GatewayJobObject {
    param([string]$Name = ("LifeorchGatewayJob_" + [Guid]::NewGuid().ToString('N').Substring(0,12)))
    if (-not $IsWindows) { return [ordered]@{ supported = $false; handle = [IntPtr]::Zero; name = $Name; reason = 'not_windows'; kill_on_close = $true } }
    if (-not (Initialize-JobObjectType)) { return [ordered]@{ supported = $false; handle = [IntPtr]::Zero; name = $Name; reason = 'addtype_failed'; kill_on_close = $true } }
    try {
        $h = [LifeorchJob]::CreateKillOnCloseJob($Name)
        if ($h -eq [IntPtr]::Zero) { return [ordered]@{ supported = $false; handle = [IntPtr]::Zero; name = $Name; reason = 'create_failed'; kill_on_close = $true } }
        return [ordered]@{ supported = $true; handle = $h; name = $Name; reason = 'ok'; kill_on_close = $true }
    } catch { return [ordered]@{ supported = $false; handle = [IntPtr]::Zero; name = $Name; reason = "exception:$($_.Exception.Message)"; kill_on_close = $true } }
}
function Add-ProcessToGatewayJob {
    param([Parameter(Mandatory)]$Job, [Parameter(Mandatory)][int]$ProcessId)
    if ($null -eq $Job -or -not (Test-SupHasProp $Job 'supported') -or -not [bool]$Job.supported) { return $false }
    if ($ProcessId -le 0) { return $false }
    try { return [bool][LifeorchJob]::AssignPid([IntPtr]$Job.handle, $ProcessId) } catch { return $false }
}
function Close-GatewayJob {
    param([Parameter(Mandatory)]$Job)
    if ($null -eq $Job -or -not (Test-SupHasProp $Job 'supported') -or -not [bool]$Job.supported) { return $false }
    try { return [bool][LifeorchJob]::CloseHandle([IntPtr]$Job.handle) } catch { return $false }
}

# ================================================================================================
# i23 MF1+2 (red-team blockers 1+3, must-fix 1+2): PER-RESIDENT SUSPENDED-CREATE JOB CUSTODY.
# The single supervisor-wide job (above) assigns a server AFTER Start-Process has already run it -- a child
# spawned pre-assignment (or via Win32_Process.Create) is never inherited into the job, and on a supervisor
# crash escapes KILL_ON_JOB_CLOSE. This replaces it as the PRIMARY custody mechanism: for EACH resident,
#   CreateProcess(CREATE_SUSPENDED) -> AssignProcessToJobObject(per-resident KILL_ON_JOB_CLOSE job)
#   -> IsProcessInJob verify -> ResumeThread.
# NO child executes before it is in its job. The supervisor HOLDS the per-resident job handle for the
# resident's lifetime (durable custody + crash reap); tree_gone becomes "this resident's job reports ZERO
# active members", not pid-death+socket. Any custody step failing => terminate the (still-suspended) process
# and FAIL (job_owned:false is FATAL on the Windows default-ON path -- no manifest publish). Off-Windows the
# suspended-create is unavailable, so New-CustodiedServer degrades to Start-Process (custody_supported:false,
# job_owned:false) and the ORDERING + FATALITY CONTRACT is proven off-machine via an injected launcher.
# ================================================================================================
$script:CustodyTypeLoaded = $false
function Initialize-CustodyType {
    if ($script:CustodyTypeLoaded) { return $true }
    if (-not $IsWindows) { return $false }
    $src = @'
using System;
using System.Runtime.InteropServices;
public static class LifeorchCustody {
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount; public ulong WriteOperationCount; public ulong OtherOperationCount;
        public ulong ReadTransferCount; public ulong WriteTransferCount; public ulong OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_PROCESS_ID_LIST {
        public uint NumberOfAssignedProcesses; public uint NumberOfProcessIdsInList; public IntPtr ProcessIdList0;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize; public int dwXCountChars; public int dwYCountChars;
        public int dwFillAttribute; public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }
    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }

    public const uint JOB_KILL_ON_CLOSE = 0x2000;
    public const int JobObjectExtendedLimitInformation = 9;
    public const int JobObjectBasicProcessIdList = 3;
    public const uint CREATE_SUSPENDED = 0x4;
    public const uint CREATE_NO_WINDOW = 0x08000000;
    public const uint STARTF_USESTDHANDLES = 0x100;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint GENERIC_READ = 0x80000000;
    public const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2;
    public const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3;
    public const uint FILE_ATTRIBUTE_NORMAL = 0x80;

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr j, int cls, IntPtr info, uint len, IntPtr ret);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr j, uint code);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessInJob(IntPtr proc, IntPtr job, out bool result);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa, uint disp, uint flags, IntPtr tmpl);

    public class CustodyResult {
        public bool ok; public int pid; public IntPtr hProcess; public IntPtr hJob; public bool inJob;
        public string stage; public string error; public string jobName;
    }
    static readonly IntPtr INVALID_HANDLE = new IntPtr(-1);

    // The load-bearing sequence: suspended-create -> assign -> verify -> resume. NO child runs before it is
    // in its per-resident KILL_ON_JOB_CLOSE job. Any failure terminates the suspended process (it never ran).
    public static CustodyResult CreateSuspendedInJob(string app, string cmdLine, string cwd, string jobName, string stdoutPath, string stderrPath) {
        var r = new CustodyResult { ok=false, pid=0, hProcess=IntPtr.Zero, hJob=IntPtr.Zero, inJob=false, stage="init", error="", jobName=jobName };
        IntPtr hJob = CreateJobObject(IntPtr.Zero, jobName);
        if (hJob == IntPtr.Zero) { r.stage="create_job"; r.error="CreateJobObject err="+Marshal.GetLastWin32Error(); return r; }
        var eli = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        eli.BasicLimitInformation.LimitFlags = JOB_KILL_ON_CLOSE;
        int eliLen = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr eliP = Marshal.AllocHGlobal(eliLen);
        try {
            Marshal.StructureToPtr(eli, eliP, false);
            if (!SetInformationJobObject(hJob, JobObjectExtendedLimitInformation, eliP, (uint)eliLen)) { r.stage="set_job"; r.error="SetInformationJobObject err="+Marshal.GetLastWin32Error(); CloseHandle(hJob); return r; }
        } finally { Marshal.FreeHGlobal(eliP); }
        var sa = new SECURITY_ATTRIBUTES(); sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)); sa.bInheritHandle = 1; sa.lpSecurityDescriptor = IntPtr.Zero;
        IntPtr hOut = CreateFileW(stdoutPath, GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE, ref sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        IntPtr hErr = CreateFileW(stderrPath, GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE, ref sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        IntPtr hIn  = CreateFileW("NUL", GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE, ref sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (hOut == INVALID_HANDLE || hErr == INVALID_HANDLE) {
            r.stage="redirect"; r.error="CreateFile redirect failed err="+Marshal.GetLastWin32Error();
            if (hOut != INVALID_HANDLE && hOut != IntPtr.Zero) CloseHandle(hOut);
            if (hErr != INVALID_HANDLE && hErr != IntPtr.Zero) CloseHandle(hErr);
            if (hIn  != INVALID_HANDLE && hIn  != IntPtr.Zero) CloseHandle(hIn);
            CloseHandle(hJob); return r;
        }
        var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = (int)STARTF_USESTDHANDLES; si.hStdOutput = hOut; si.hStdError = hErr; si.hStdInput = (hIn == INVALID_HANDLE ? IntPtr.Zero : hIn);
        PROCESS_INFORMATION pi;
        bool created = CreateProcess(app, cmdLine, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED|CREATE_NO_WINDOW, IntPtr.Zero, cwd, ref si, out pi);
        if (hOut != IntPtr.Zero && hOut != INVALID_HANDLE) CloseHandle(hOut);
        if (hErr != IntPtr.Zero && hErr != INVALID_HANDLE) CloseHandle(hErr);
        if (hIn  != IntPtr.Zero && hIn  != INVALID_HANDLE) CloseHandle(hIn);
        if (!created) { r.stage="create_process"; r.error="CreateProcess err="+Marshal.GetLastWin32Error(); CloseHandle(hJob); return r; }
        if (!AssignProcessToJobObject(hJob, pi.hProcess)) {
            r.stage="assign"; r.error="AssignProcessToJobObject err="+Marshal.GetLastWin32Error();
            TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hThread); CloseHandle(pi.hProcess); CloseHandle(hJob); return r;
        }
        bool inJob = false;
        if (!IsProcessInJob(pi.hProcess, hJob, out inJob) || !inJob) {
            r.stage="verify"; r.error="IsProcessInJob=false";
            TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hThread); CloseHandle(pi.hProcess); CloseHandle(hJob); return r;
        }
        uint rt = ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
        if (rt == 0xFFFFFFFF) {
            r.stage="resume"; r.error="ResumeThread failed";
            TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hProcess); CloseHandle(hJob); return r;
        }
        r.ok = true; r.stage="running"; r.pid = pi.dwProcessId; r.hProcess = pi.hProcess; r.hJob = hJob; r.inJob = true;
        return r;
    }
    // ZERO members == the resident's tree is gone (durable, not pid+socket heuristic).
    public static int JobActiveProcessCount(IntPtr hJob) {
        if (hJob == IntPtr.Zero) return -1;
        int len = 1024; IntPtr buf = Marshal.AllocHGlobal(len);
        try { if (!QueryInformationJobObject(hJob, JobObjectBasicProcessIdList, buf, (uint)len, IntPtr.Zero)) return -1; return Marshal.ReadInt32(buf, 0); }
        finally { Marshal.FreeHGlobal(buf); }
    }
    public static bool KillJobTree(IntPtr hJob) { if (hJob == IntPtr.Zero) return false; return TerminateJobObject(hJob, 1); }
    public static void CloseJobHandle(IntPtr hJob) { if (hJob != IntPtr.Zero) CloseHandle(hJob); }
    public static void CloseProcHandle(IntPtr hProc) { if (hProc != IntPtr.Zero) CloseHandle(hProc); }
}
'@
    try { Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop; $script:CustodyTypeLoaded = $true; return $true } catch { return $false }
}

# Per-resident custody registry: resident_instance_id -> { hJob; hProcess; name; pid }. Lives in the supervisor
# process (the run loop), reachable from both the launcher closure and the evict path.
$script:SupResidentJobs = @{}
function Register-ResidentJob { param([Parameter(Mandatory)][string]$InstanceId, [Parameter(Mandatory)][object]$JobInfo) $script:SupResidentJobs[$InstanceId] = $JobInfo }
function Get-ResidentJobInfo { param([string]$InstanceId) if (-not [string]::IsNullOrWhiteSpace($InstanceId) -and $script:SupResidentJobs.ContainsKey($InstanceId)) { return $script:SupResidentJobs[$InstanceId] } return $null }
function Get-ResidentJobMemberCount {
    param([string]$InstanceId)
    $info = Get-ResidentJobInfo $InstanceId
    if ($null -eq $info -or -not $info.ContainsKey('hJob')) { return -1 }
    if (-not $IsWindows -or -not $script:CustodyTypeLoaded) { return -1 }
    try { return [int][LifeorchCustody]::JobActiveProcessCount([IntPtr]$info['hJob']) } catch { return -1 }
}
# Close (KILL_ON_JOB_CLOSE reaps) + terminate the resident's tree; returns whether members reached ZERO.
function Close-ResidentJobTree {
    param([string]$InstanceId, [int]$ConfirmTimeoutMs = 3000)
    $info = Get-ResidentJobInfo $InstanceId
    if ($null -eq $info) { return [ordered]@{ had_job = $false; members_zero = $true; note = 'no_tracked_job' } }
    $out = [ordered]@{ had_job = $true; members_zero = $false; note = 'ok' }
    if ($IsWindows -and $script:CustodyTypeLoaded) {
        try { [void][LifeorchCustody]::KillJobTree([IntPtr]$info['hJob']) } catch { }
        $deadline = (Get-SupNowUtc).AddMilliseconds($ConfirmTimeoutMs)
        while ((Get-SupNowUtc) -lt $deadline) {
            $cnt = try { [int][LifeorchCustody]::JobActiveProcessCount([IntPtr]$info['hJob']) } catch { -1 }
            if ($cnt -le 0) { $out.members_zero = $true; break }
            Start-Sleep -Milliseconds 100
        }
        try { [LifeorchCustody]::CloseJobHandle([IntPtr]$info['hJob']) } catch { }
        try { [LifeorchCustody]::CloseProcHandle([IntPtr]$info['hProcess']) } catch { }
    } else { $out.members_zero = $true; $out.note = 'custody_unsupported' }
    if ($script:SupResidentJobs.ContainsKey($InstanceId)) { [void]$script:SupResidentJobs.Remove($InstanceId) }
    return $out
}
# Close EVERY tracked per-resident Job (graceful stop). On a HARD crash the OS closes these handles for us and
# KILL_ON_JOB_CLOSE reaps each tree -- the durable finding-5 guarantee; this is the clean-exit belt-and-suspenders.
function Close-AllResidentJobTrees {
    $ids = @($script:SupResidentJobs.Keys)
    $n = 0
    foreach ($id in $ids) { try { [void](Close-ResidentJobTree -InstanceId ([string]$id)); $n++ } catch { } }
    return $n
}
# Windows command-line quoter (CreateProcess takes ONE command-line string; argv[0] is the program name).
function ConvertTo-Win32CommandLine {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @())
    $q = {
        param([string]$s)
        if ([string]::IsNullOrEmpty($s)) { return '""' }
        if ($s -notmatch '[ \t"]') { return $s }
        $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $s.ToCharArray()) {
            if ($ch -eq '\') { $bs++ }
            elseif ($ch -eq '"') { [void]$sb.Append('\', ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0 }
            else { if ($bs -gt 0) { [void]$sb.Append('\', $bs); $bs = 0 }; [void]$sb.Append($ch) }
        }
        if ($bs -gt 0) { [void]$sb.Append('\', ($bs * 2)) }
        [void]$sb.Append('"'); return $sb.ToString()
    }
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add((& $q $FilePath))
    foreach ($a in @($Arguments)) { [void]$parts.Add((& $q ([string]$a))) }
    return ([string]::Join(' ', $parts))
}
# Launch a model server UNDER PER-RESIDENT SUSPENDED-CREATE CUSTODY (Windows) or, off-Windows, degrade to a
# Start-Process launch (custody_supported:false, job_owned:false) so the mock-server state machine still runs.
# Returns { ok; custody_supported; job_owned; pid; start_ticks; job_instance_id; in_job; stage; error }.
function New-CustodiedServer {
    param(
        [Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [string]$WorkDir,
        [Parameter(Mandatory)][string]$ResidentInstanceId, [Parameter(Mandatory)][string]$StdoutPath, [Parameter(Mandatory)][string]$StderrPath,
        [hashtable]$PreLaunchVerify = $null   # i23 MF10: { <abs path> = <trusted expected sha256> } -- every entry
                                              # is content-verified (+ reparse-point rejected) IMMEDIATELY before
                                              # launch; ANY mismatch/reparse => NO launch (fail-closed).
    )
    # i23 MF10: verify engine+model file CONTENTS against the trusted expected-hash manifest before we launch.
    if ($null -ne $PreLaunchVerify -and $PreLaunchVerify.Count -gt 0 -and (Get-Command Test-ContentHashTrusted -ErrorAction SilentlyContinue)) {
        foreach ($vp in @($PreLaunchVerify.Keys)) {
            $exp = [string]$PreLaunchVerify[$vp]
            if ([string]::IsNullOrWhiteSpace($exp)) { continue }   # no trusted hash for this file -> skip (named residual: provision one)
            $vr = Test-ContentHashTrusted -Path $vp -ExpectedSha256 $exp -RejectReparse
            if (-not $vr.ok) {
                return [ordered]@{ ok = $false; custody_supported = $IsWindows; job_owned = $false; pid = 0; start_ticks = 0; job_instance_id = $null; in_job = $false; stage = 'content_verify'; error = "content verification FAILED for '$vp' (reason=$($vr.reason)); refusing to launch" }
            }
        }
    }
    $logDir = Split-Path -Parent $StdoutPath
    if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $cwd = if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $WorkDir } else { (Split-Path -Parent $FilePath) }
    if ($IsWindows -and (Initialize-CustodyType)) {
        $safe = ($ResidentInstanceId -replace '[^A-Za-z0-9_]', '')
        if ($safe.Length -gt 20) { $safe = $safe.Substring(0, 20) }
        $jobName = 'LifeorchResJob_' + $safe + '_' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
        $cmdLine = ConvertTo-Win32CommandLine -FilePath $FilePath -Arguments $Arguments
        $res = $null
        try { $res = [LifeorchCustody]::CreateSuspendedInJob($FilePath, $cmdLine, $cwd, $jobName, $StdoutPath, $StderrPath) }
        catch { return [ordered]@{ ok = $false; custody_supported = $true; job_owned = $false; pid = 0; start_ticks = 0; job_instance_id = $null; in_job = $false; stage = 'exception'; error = "$($_.Exception.Message)" } }
        if ($null -eq $res -or -not $res.ok) {
            return [ordered]@{ ok = $false; custody_supported = $true; job_owned = $false; pid = 0; start_ticks = 0; job_instance_id = $null; in_job = $false; stage = $(if ($null -ne $res) { [string]$res.stage } else { 'null_result' }); error = $(if ($null -ne $res) { [string]$res.error } else { 'null' }) }
        }
        Register-ResidentJob -InstanceId $ResidentInstanceId -JobInfo @{ hJob = $res.hJob; hProcess = $res.hProcess; name = $jobName; pid = [int]$res.pid }
        $startTicks = 0; try { $startTicks = [long]((Get-Process -Id ([int]$res.pid) -ErrorAction Stop).StartTime.Ticks) } catch { }
        return [ordered]@{ ok = $true; custody_supported = $true; job_owned = $true; pid = [int]$res.pid; start_ticks = $startTicks; job_instance_id = $jobName; in_job = $true; stage = 'running'; error = $null }
    }
    # off-Windows fallback: Start-Process, NO OS custody (job_owned:false honestly recorded)
    $splat = @{ FilePath = $FilePath; ArgumentList = @($Arguments); PassThru = $true; RedirectStandardOutput = $StdoutPath; RedirectStandardError = $StderrPath }
    $proc = $null
    try { $proc = Start-Process @splat }
    catch { return [ordered]@{ ok = $false; custody_supported = $false; job_owned = $false; pid = 0; start_ticks = 0; job_instance_id = $null; in_job = $false; stage = 'start_process'; error = "$($_.Exception.Message)" } }
    $spid = [int]$proc.Id
    $startTicks = 0; try { $startTicks = [long]((Get-Process -Id $spid -ErrorAction Stop).StartTime.Ticks) } catch { try { $startTicks = [long]$proc.StartTime.Ticks } catch { } }
    return [ordered]@{ ok = $true; custody_supported = $false; job_owned = $false; pid = $spid; start_ticks = $startTicks; job_instance_id = $null; in_job = $false; stage = 'running'; error = $null }
}

# ------------------------------------------------------------------------------------------------
# Reconcile-on-restart (finding #3). Read the resident manifest as a CLAIM and VERIFY it (pid alive +
# creation-time identity + /health + socket owner); a valid resident is KEPT (warmth preserved), an
# inconsistent claim is confirm-stopped and driven to a clean EMPTY. All probes are seams so it runs
# off-machine. Delegates every integrity primitive to PoolManager. Mirrors the gateway's Invoke-PoolReconcile
# so the supervisor and the gateway reconcile IDENTICALLY.
# ------------------------------------------------------------------------------------------------
function Invoke-SupervisorReconcile {
    param(
        [Parameter(Mandatory)][string]$WarmRegPath, [Parameter(Mandatory)][string]$LockPath,
        [scriptblock]$StartTicksProbe = $null, [scriptblock]$SocketOwnerProbe = $null,
        [scriptblock]$HealthProbe = $null, [scriptblock]$StopProbe = $null,
        [switch]$RequireCustodian   # i23 MF9: on a supervisor (RE)START, a surviving server is EVIDENCE OF FAILED
                                    # CUSTODY, not an asset -- adopt ONLY via a durable custodian this process
                                    # retained (a tracked per-resident Job with live members); else fence/kill + EMPTY.
    )
    $out = [ordered]@{ ran = $false; state_before = $null; state_after = $null; action = 'none'; kept_resident = $false; killed_pid = $null; notes = @() }
    if (-not $script:SupPoolCoreLoaded) { $out.notes += 'pool core not loaded'; return $out }
    $lock = Enter-PoolLock -LockPath $LockPath -TimeoutMs 8000
    try {
        $reg = Read-PoolManifest $WarmRegPath
        $out.ran = $true
        if ($null -eq $reg) { $out.state_after = 'EMPTY'; $out.action = 'no_manifest'; return $out }
        # a fence-only skeleton (no pid) is not a residency claim
        if (-not (Test-SupHasProp $reg 'pid') -or ([int]$reg.pid -le 0)) { $out.state_before = Get-ManifestState $reg; $out.state_after = 'EMPTY'; $out.action = 'no_resident_pid'; return $out }
        $out.state_before = Get-ManifestState $reg
        $ident = Test-ResidentIdentity $reg $StartTicksProbe
        $port = if (Test-SupHasProp $reg 'port') { [int]$reg.port } else { 0 }
        $healthy = $false
        if ($ident.alive -and $null -ne $HealthProbe) { try { $healthy = [bool](& $HealthProbe '127.0.0.1' $port) } catch { $healthy = $false } }
        $sockOwner = $null
        if ($ident.alive -and (Test-SupHasProp $reg 'pid')) { $sockOwner = Test-SocketOwner -Port $port -ExpectedPid ([int]$reg.pid) -SocketOwnerProbe $SocketOwnerProbe }
        $stateBefore = $out.state_before
        $validResident = ($stateBefore -eq 'RESIDENT' -and $ident.alive -and $ident.identity_ok -and $healthy -and ($sockOwner -ne $false))
        # i23 MF9: NO MANIFEST-ONLY ADOPTION. A survivor is adopted ONLY if THIS supervisor holds a durable
        # custodian for its resident_instance_id (a tracked per-resident Job with live members). A fresh
        # (restarted) supervisor holds NONE -> any survivor is an orphan of failed custody: fence/kill + EMPTY.
        if ($RequireCustodian) {
            $claimInst = if (Test-SupHasProp $reg 'resident_instance_id') { [string]$reg.resident_instance_id } else { $null }
            $custodian = if (-not [string]::IsNullOrWhiteSpace($claimInst)) { Get-ResidentJobInfo $claimInst } else { $null }
            $custodianLive = $false
            if ($null -ne $custodian) {
                if ($IsWindows -and $script:CustodyTypeLoaded) { $custodianLive = ((Get-ResidentJobMemberCount $claimInst) -gt 0) } else { $custodianLive = $true }
            }
            if ($validResident -and $custodianLive) { $out.state_after = 'RESIDENT'; $out.action = 'kept_custodian_verified'; $out.kept_resident = $true; return $out }
            # not adopted: a survivor without a retained custodian is an orphan -> kill (if alive+identity_ok) + EMPTY
            $out.notes += 'require_custodian: manifest-only survivor NOT adopted (no retained custodian handle)'
            if ($ident.alive -and $ident.identity_ok) {
                $stopped = $false
                if (-not [string]::IsNullOrWhiteSpace($claimInst)) { try { [void](Close-ResidentJobTree -InstanceId $claimInst) } catch { } }
                if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
                if ($stopped) { $out.killed_pid = [int]$reg.pid; $out.notes += 'fenced/killed the unadopted survivor' }
                else { $out.notes += 'survivor alive but unstopped; manifest cleared (orphan flagged)' }
            } elseif ($ident.alive -and -not $ident.identity_ok) {
                $out.notes += 'recorded pid alive but identity mismatch (PID reuse); manifest cleared without killing a foreign process'
            }
            Clear-PoolManifest $WarmRegPath
            $out.state_after = 'EMPTY'; $out.action = "survivor_not_adopted_from_$stateBefore"
            return $out
        }
        if ($validResident) { $out.state_after = 'RESIDENT'; $out.action = 'kept_valid_resident'; $out.kept_resident = $true; return $out }
        if ($ident.alive -and $ident.identity_ok) {
            $stopped = $false
            if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
            if ($stopped) { $out.killed_pid = [int]$reg.pid; $out.notes += 'stopped stale/identified resident' }
            else { $out.notes += 'resident alive but unstopped/unidentified; not killed' }
        } elseif ($ident.alive -and -not $ident.identity_ok) {
            $out.notes += 'recorded pid alive but identity mismatch (PID reuse); manifest cleared without killing a foreign process'
        }
        Clear-PoolManifest $WarmRegPath
        $out.state_after = 'EMPTY'; $out.action = "reconciled_from_$stateBefore"
        return $out
    } finally { Exit-PoolLock $lock }
}

# ------------------------------------------------------------------------------------------------
# RESIDENCY TRANSITION (the supervisor is the single owner). Runs the PoolManager crash-atomic state
# machine under the machine-global lock: reconcile -> CanServe? reuse (~1 ms, renew fence TTL) : evict (CAS
# STOPPING, confirm exit + VRAM) + launch (via the Launcher seam, which assigns the new pid to the Job
# Object) + health + socket-owner verify + CAS STARTING->RESIDENT + publish. Every host action is a seam:
#   Launcher      {param($reqConfig,$port) -> @{ pid; start_ticks; instance_generation; host; port }}   (assigns to Job)
#   HealthProbe   {param($host,$port) -> bool}
#   StopProbe     {param($reg,$liveness) -> bool}    (taskkill /T tree-kill; confirm exit)
#   SocketOwnerProbe {param($port) -> pid|$null}
#   StartTicksProbe  {param($pid) -> ticks}
#   VramProbe     {-> free MiB | $null}
# The result is the same shape the gateway's -EnsureResident emits under result.pool, so the client maps it 1:1.
# ------------------------------------------------------------------------------------------------
function Invoke-SupervisorEnsureResident {
    param(
        [Parameter(Mandatory)][string]$WarmRegPath, [Parameter(Mandatory)][string]$LockPath,
        [Parameter(Mandatory)][object]$ReqConfig,       # ordered map from Get-ResidentConfig (PoolManager)
        [Parameter(Mandatory)][hashtable]$ModelMeta,    # { model_id; host; port_hint; managed_by; keep_resident_seconds; job_owned }
        [Parameter(Mandatory)][scriptblock]$Launcher,
        [scriptblock]$HealthProbe = $null, [scriptblock]$StopProbe = $null,
        [scriptblock]$SocketOwnerProbe = $null, [scriptblock]$StartTicksProbe = $null, [scriptblock]$VramProbe = $null,
        [string]$FenceHolder = 'gateway.supervisor', [int]$FenceTtlSeconds = 120,
        [switch]$ForceReload, [int]$LoadTimeoutSec = 120,
        [string]$ResidentInstanceId,  # v0.4 (i21): caller-pinned per-server-tree instance id stamped into the manifest (the target of every destructive op); omitted => minted here
        [string]$InstanceGeneration,  # v0.4 (i21): caller-pinned per-launch generation nonce -- the split pre-mints it and stamps it into the transition capability, so the manifest MUST carry the same value (resident_generation binding); omitted => the launcher's mint
        [switch]$RequireJobCustody    # i23 MF1+2: on the hardened Windows default-ON path, a launch that did not achieve per-resident Job membership (job_owned:false) is FATAL -- terminate + fail, NO uncustodied publish
    )
    if (-not $script:SupPoolCoreLoaded) { throw [PSCustomObject]@{ code = 'pool_core_absent'; message = 'PoolManager.psm1 not loaded' } }
    $reqHash = Get-ResidentConfigHash $ReqConfig
    $modelId = [string]$ModelMeta['model_id']
    $host127 = if ($ModelMeta.ContainsKey('host') -and -not [string]::IsNullOrWhiteSpace([string]$ModelMeta['host'])) { [string]$ModelMeta['host'] } else { '127.0.0.1' }
    $managedBy = if ($ModelMeta.ContainsKey('managed_by') -and -not [string]::IsNullOrWhiteSpace([string]$ModelMeta['managed_by'])) { [string]$ModelMeta['managed_by'] } else { 'model.gateway.supervisor' }
    $keepSec = if ($ModelMeta.ContainsKey('keep_resident_seconds')) { [int]$ModelMeta['keep_resident_seconds'] } else { 90 }

    $out = [ordered]@{
        action = 'cold_start'; reused = $false; started_new = $false; evicted = $false; evict_confirmed = $null
        model_id = $modelId; resident_config_hash = $reqHash; instance_generation = $null; fence = $null; fence_ttl_seconds = $FenceTtlSeconds
        can_serve = $null; can_serve_mismatches = @(); socket_owner_verified = $null
        swap_count = 0; keep_resident_seconds = $keepSec; port = $null; pid = $null
        load_ms = 0; health_ok = $false; job_owned = $false
        resident_instance_id = $null
        vram = [ordered]@{ free_mib_before = $null; free_mib_after = $null; recovered_mib = $null }
    }
    $lock = Enter-PoolLock -LockPath $LockPath -TimeoutMs 15000
    if (-not $lock.acquired) { throw [PSCustomObject]@{ code = 'pool_lock_timeout'; message = 'could not acquire the machine-global pool lock' } }
    try {
        # We already hold the machine-global lock, so we do NOT call Invoke-SupervisorReconcile here (it takes the
        # SAME lock -> a self-deadlock, and its Exit-PoolLock would delete our lock). Instead we INLINE the
        # reconcile verify below: a dead / unhealthy / wrong-socket / PID-reused claim falls through to the evict
        # branch (ident.alive=false skips the kill; a foreign PID is refused by the StopProbe) and is cleared +
        # cold-reloaded, while a valid resident is reused. The dedicated -reconcile op + startup reconcile call
        # Invoke-SupervisorReconcile WITHOUT holding the lock, so the full state-machine reconcile runs there.
        $reg = Read-PoolManifest $WarmRegPath
        $hasResident = ($null -ne $reg -and (Test-SupHasProp $reg 'pid') -and ([int]$reg.pid -gt 0))
        if (-not $hasResident) { $reg = $null }
        $prevFence = if ($null -ne $reg -and (Test-SupHasProp $reg 'fence')) { [long]$reg.fence } else { 0 }
        $prevSwaps = if ($null -ne $reg -and (Test-SupHasProp $reg 'swap_count')) { [int]$reg.swap_count } else { 0 }
        $myFence = if ($null -eq $reg) { $prevFence + 1 } else { $prevFence }

        $canServe = $false; $csInfo = $null
        if ($null -ne $reg) {
            $ident = Test-ResidentIdentity $reg $StartTicksProbe
            $port = if (Test-SupHasProp $reg 'port') { [int]$reg.port } else { 0 }
            $healthy = $false
            if ($ident.alive -and $null -ne $HealthProbe) { try { $healthy = [bool](& $HealthProbe $host127 $port) } catch { $healthy = $false } }
            $sockOwner = $null
            if ($ident.alive) { $sockOwner = Test-SocketOwner -Port $port -ExpectedPid ([int]$reg.pid) -SocketOwnerProbe $SocketOwnerProbe }
            $identOk = ([bool]$ident.identity_ok) -and ($sockOwner -ne $false)
            if ((Test-SupHasProp $reg 'resident_config') -and $null -ne $reg.resident_config) {
                $csInfo = Test-CanServe $reg.resident_config $ReqConfig
                $canServe = [bool]$csInfo.can_serve
            } elseif (Test-SupHasProp $reg 'resident_config_hash') { $canServe = ([string]$reg.resident_config_hash -eq $reqHash) }
            if ($ForceReload) { $canServe = $false }
            $out.can_serve = $canServe
            if ($null -ne $csInfo) { $out.can_serve_mismatches = $csInfo.mismatches }

            if ($healthy -and $canServe -and $identOk) {
                # ~1 ms REUSE across invocations: keep the epoch fence, renew TTL, refresh keep-resident timer
                $out.action = 'reuse'; $out.reused = $true; $out.swap_count = $prevSwaps; $out.fence = $prevFence
                $out.resident_instance_id = if (Test-SupHasProp $reg 'resident_instance_id') { [string]$reg.resident_instance_id } else { $null }
                $out.instance_generation = if (Test-SupHasProp $reg 'instance_generation') { [string]$reg.instance_generation } else { $null }
                $out.port = $port; $out.pid = [int]$reg.pid; $out.health_ok = $true
                $out.socket_owner_verified = $sockOwner
                $out.job_owned = if (Test-SupHasProp $reg 'job_owned') { [bool]$reg.job_owned } else { $false }
                $map = ConvertTo-MutableMap $reg
                $map['last_used_utc'] = (ConvertTo-SupUtcString (Get-SupNowUtc))
                [void](Write-PoolManifest $WarmRegPath $map)
                [void](Update-FenceRenewal -Path $WarmRegPath -Fence $prevFence -TtlSeconds $FenceTtlSeconds)
                return $out
            }
            # cannot serve / unhealthy / forced -> EVICT (CAS STOPPING, confirm exit + tree-gone + VRAM), then reload.
            # i23 MF5 (red-team blocker 5): a FAILED / PARTIAL evict, or a failed STOPPING CAS, is FATAL. We do NOT
            # clear a manifest we cannot prove empty and do NOT launch a replacement over a resident that may still
            # hold the GPU (split-brain). tree_gone is confirmed by the per-resident Job reporting ZERO active
            # members (durable), not pid-death alone. The GPU is left ungranted; recovery is a retry / the watchdog.
            $myFence = $prevFence + 1
            $oldInstId = if (Test-SupHasProp $reg 'resident_instance_id') { [string]$reg.resident_instance_id } else { $null }
            $casStop = Set-ManifestCas -Path $WarmRegPath -Fence $prevFence -Updates @{ state = 'STOPPING' }
            if (-not $casStop) {
                throw [PSCustomObject]@{ code = 'evict_cas_failed'; message = 'STOPPING CAS failed (fence superseded); refusing to evict/launch -- GPU left ungranted, manifest NOT cleared' }
            }
            if ($ident.alive) {
                if ($null -ne $VramProbe) { try { $out.vram.free_mib_before = & $VramProbe } catch { } }
                $stopped = $false
                if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
                if (-not $stopped) {
                    $out.evict_confirmed = $false
                    throw [PSCustomObject]@{ code = 'evict_not_confirmed'; message = 'the resident did not stop (evict unconfirmed); refusing to launch a replacement (no split-brain) -- GPU ungranted, manifest NOT cleared' }
                }
                # tree-gone: the per-resident Job must report ZERO active members (durable). No tracked job
                # (off-Windows / classic) => had_job:false => trivially gone (pid-death already proven above).
                if (-not [string]::IsNullOrWhiteSpace($oldInstId)) {
                    $ct = Close-ResidentJobTree -InstanceId $oldInstId
                    if ($ct.had_job -and -not $ct.members_zero) {
                        $out.evict_confirmed = $false
                        throw [PSCustomObject]@{ code = 'partial_tree_term'; message = "evicted the root but the resident Job still reports active members (partial tree); refusing to launch (no orphan/split-brain)" }
                    }
                }
                $out.evicted = $true; $out.evict_confirmed = $true
                Start-Sleep -Milliseconds 200
                if ($null -ne $VramProbe) { try { $out.vram.free_mib_after = & $VramProbe } catch { } }
                if ($null -ne $out.vram.free_mib_before -and $null -ne $out.vram.free_mib_after) { $out.vram.recovered_mib = ($out.vram.free_mib_after - $out.vram.free_mib_before) }
            } else {
                # the recorded resident is already gone: reap any tracked per-resident Job handle to avoid a leak
                if (-not [string]::IsNullOrWhiteSpace($oldInstId)) { [void](Close-ResidentJobTree -InstanceId $oldInstId) }
            }
            $out.swap_count = $prevSwaps + 1
            $out.action = 'evict_reload'
            Clear-PoolManifest $WarmRegPath
            $reg = $null
        }

        # ---- LAUNCH a fresh resident (cold_start or evict_reload). ----
        # v0.4 (i21): the per-server-tree resident_instance_id -- the TARGET of every destructive op (never
        # generation/config-key alone) and the KEY of the per-resident Job custody registry. Caller-pinned (so the
        # res.lease grant and the manifest agree) or minted. Computed BEFORE the launch so the launcher can key
        # per-resident Job custody (i23 MF1+2) to it.
        $resInstId = if (-not [string]::IsNullOrWhiteSpace($ResidentInstanceId)) { $ResidentInstanceId } else { ('ri' + [Guid]::NewGuid().ToString('N')) }
        $portHint = if ($ModelMeta.ContainsKey('port_hint')) { [int]$ModelMeta['port_hint'] } else { 0 }
        $launch = & $Launcher $ReqConfig $portHint $resInstId
        if ($null -eq $launch -or -not (Test-SupHasProp $launch 'pid') -or ([int]$launch.pid -le 0)) {
            $lstage = if ($null -ne $launch -and (Test-SupHasProp $launch 'stage')) { [string]$launch.stage } else { '?' }
            $lerr = if ($null -ne $launch -and (Test-SupHasProp $launch 'error')) { [string]$launch.error } else { 'launcher returned no pid' }
            throw [PSCustomObject]@{ code = 'server_start_failed'; message = "launcher returned no pid (stage=$lstage error=$lerr)" }
        }
        $serverPid = [int]$launch.pid
        $usePort = if (Test-SupHasProp $launch 'port') { [int]$launch.port } else { $portHint }
        $startTicks = if (Test-SupHasProp $launch 'start_ticks') { [long]$launch.start_ticks } else { 0 }
        $instanceGen = if (-not [string]::IsNullOrWhiteSpace($InstanceGeneration)) { $InstanceGeneration }
                       elseif (Test-SupHasProp $launch 'instance_generation') { [string]$launch.instance_generation }
                       else { (New-InstanceGeneration) }
        $jobOwned = if (Test-SupHasProp $launch 'job_owned') { [bool]$launch.job_owned } else { $false }
        $jobInstId = if (Test-SupHasProp $launch 'job_instance_id') { [string]$launch.job_instance_id } else { $null }
        # i23 MF1+2: on the hardened Windows default-ON path, job_owned:false is FATAL. A resident that did not
        # achieve per-resident Job membership would be an UNMANAGED ORPHAN on a supervisor crash -> terminate the
        # (uncustodied) process and FAIL the transition. NO manifest publish on job_owned:false.
        if ($RequireJobCustody -and -not $jobOwned) {
            if ($serverPid -gt 0) {
                try { if ($null -ne $StopProbe) { [void](& $StopProbe ([pscustomobject]@{ pid = $serverPid }) ([pscustomobject]@{ alive = $true; identity_ok = $true })) } } catch { }
                try { $pp = Get-Process -Id $serverPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
            }
            throw [PSCustomObject]@{ code = 'job_custody_failed'; message = "per-resident Job custody failed (job_owned:false, stage=$(if (Test-SupHasProp $launch 'stage') { $launch.stage } else { '?' })); terminated the uncustodied process; refusing to publish (no orphan)" }
        }
        $out.started_new = $true; $out.pid = $serverPid; $out.port = $usePort; $out.instance_generation = $instanceGen; $out.fence = $myFence; $out.job_owned = $jobOwned
        $out.resident_instance_id = $resInstId
        $out['job_instance_id'] = $jobInstId

        $nowUtc = ConvertTo-SupUtcString (Get-SupNowUtc)
        $manifest = [ordered]@{
            schema = 'lifeorch.model_gateway.warm/0.3'; state = 'STARTING'
            pid = $serverPid; start_ticks = $startTicks; instance_generation = $instanceGen
            resident_instance_id = $resInstId
            host = $host127; port = $usePort; model_id = $modelId
            resident_config = $ReqConfig; resident_config_hash = $reqHash; residency_key_sha = $reqHash
            ngl = $(if (Test-SupHasProp $ReqConfig 'gpu_layers') { $ReqConfig.gpu_layers } else { $null })
            ctx = $(if (Test-SupHasProp $ReqConfig 'context') { $ReqConfig.context } else { $null })
            keep_resident_seconds = $keepSec; swap_count = $out.swap_count
            started_at_utc = $nowUtc; resident_since_utc = $nowUtc; last_used_utc = $nowUtc
            managed_by = $managedBy; manager_holder = $FenceHolder; job_owned = $jobOwned; job_instance_id = $jobInstId
            socket_owner_verified = $null
            fence = $myFence; fence_holder = $FenceHolder; fence_ttl_seconds = $FenceTtlSeconds
            fence_acquired_utc = $nowUtc; fence_renewed_utc = $nowUtc
            fence_expires_utc = (ConvertTo-SupUtcString ((Get-SupNowUtc).AddSeconds($FenceTtlSeconds)))
        }
        [void](Write-PoolManifest $WarmRegPath $manifest)

        # health-poll
        $loadSw = [System.Diagnostics.Stopwatch]::StartNew()
        $healthOk = $false
        $deadline = (Get-SupNowUtc).AddSeconds($LoadTimeoutSec)
        while ((Get-SupNowUtc) -lt $deadline) {
            if (-not (Test-SupPidAlive $serverPid)) { throw [PSCustomObject]@{ code = 'server_start_failed'; message = 'server exited during load' } }
            $h = $false; if ($null -ne $HealthProbe) { try { $h = [bool](& $HealthProbe $host127 $usePort) } catch { $h = $false } }
            if ($h) { $healthOk = $true; break }
            Start-Sleep -Milliseconds 300
        }
        $loadSw.Stop(); $out.load_ms = [int]$loadSw.Elapsed.TotalMilliseconds; $out.health_ok = $healthOk
        if (-not $healthOk) {
            if ($null -ne $StopProbe) { try { [void](& $StopProbe (Read-PoolManifest $WarmRegPath) (Test-ResidentIdentity (Read-PoolManifest $WarmRegPath) $StartTicksProbe)) } catch { } }
            [void](Close-ResidentJobTree -InstanceId $resInstId)   # i23 MF1+2: reap the just-launched per-resident Job
            Clear-PoolManifest $WarmRegPath
            throw [PSCustomObject]@{ code = 'health_timeout'; message = "server did not become healthy within $LoadTimeoutSec s" }
        }
        # finding #4: verify the LISTENING SOCKET owner before publishing RESIDENT (advisory off-Windows)
        $sockVerified = Test-SocketOwner -Port $usePort -ExpectedPid $serverPid -SocketOwnerProbe $SocketOwnerProbe
        $out.socket_owner_verified = $sockVerified
        if ($sockVerified -eq $false) {
            if ($null -ne $StopProbe) { try { [void](& $StopProbe (Read-PoolManifest $WarmRegPath) (Test-ResidentIdentity (Read-PoolManifest $WarmRegPath) $StartTicksProbe)) } catch { } }
            [void](Close-ResidentJobTree -InstanceId $resInstId)
            Clear-PoolManifest $WarmRegPath
            throw [PSCustomObject]@{ code = 'socket_owner_mismatch'; message = "listening socket on port $usePort not owned by pid $serverPid (wrong-generation guard)" }
        }
        # STARTING -> RESIDENT via fence-gated CAS. i23 MF5: a FAILED final CAS means a higher fence superseded
        # us mid-transition -> the server we launched is UNAUTHORIZED. Tear it down + FAIL (never publish a
        # RESIDENT we no longer have authority for; never leave an orphan). Leave the GPU ungranted.
        $casOk = Set-ManifestCas -Path $WarmRegPath -Fence $myFence -Updates @{ state = 'RESIDENT'; socket_owner_verified = $sockVerified }
        if (-not $casOk) {
            if ($null -ne $StopProbe) { try { [void](& $StopProbe ([pscustomobject]@{ pid = $serverPid; start_ticks = $startTicks }) ([pscustomobject]@{ alive = $true; identity_ok = $true })) } catch { } }
            [void](Close-ResidentJobTree -InstanceId $resInstId)
            throw [PSCustomObject]@{ code = 'resident_publish_superseded'; message = 'final RESIDENT CAS failed (fence superseded mid-transition); tore down the unauthorized server; GPU left ungranted (no split-brain)' }
        }
        return $out
    } finally { Exit-PoolLock $lock }
}

# Evict the resident under the lock (returns a report). Idempotent when there is no resident.
# v0.4 (R1b consumer wave, i21): an OPTIONAL -TargetResidentInstanceId makes the stop TARGET-FENCED at the
# supervisor itself (red-team blockers 4/8): when supplied, the manifest's resident_instance_id must match
# EXACTLY or the stop is REFUSED (reason target_instance_mismatch; a manifest without the field refuses too,
# manifest_instance_unknown -- fail-closed, never "stop whatever currently serves"). No target => unchanged
# legacy behavior (back-compatible).
function Invoke-SupervisorEvict {
    param([Parameter(Mandatory)][string]$WarmRegPath, [Parameter(Mandatory)][string]$LockPath,
          [scriptblock]$StopProbe = $null, [scriptblock]$StartTicksProbe = $null, [scriptblock]$VramProbe = $null,
          [string]$TargetResidentInstanceId)
    $out = [ordered]@{ action = 'evict'; had_resident = $false; evicted = $false; resident_pid = $null; reason = 'no_resident'; vram = [ordered]@{ free_mib_before = $null; free_mib_after = $null; recovered_mib = $null } }
    if (-not $script:SupPoolCoreLoaded) { return $out }
    $lock = Enter-PoolLock -LockPath $LockPath -TimeoutMs 8000
    try {
        $reg = Read-PoolManifest $WarmRegPath
        if ($null -eq $reg -or -not (Test-SupHasProp $reg 'pid') -or ([int]$reg.pid -le 0)) { return $out }
        $out.had_resident = $true; $out.resident_pid = [int]$reg.pid
        if (-not [string]::IsNullOrWhiteSpace($TargetResidentInstanceId)) {
            $curInst = if (Test-SupHasProp $reg 'resident_instance_id') { [string]$reg.resident_instance_id } else { '' }
            if ([string]::IsNullOrWhiteSpace($curInst)) { $out.reason = 'manifest_instance_unknown'; $out['target_resident_instance_id'] = $TargetResidentInstanceId; return $out }
            if ($curInst -ne $TargetResidentInstanceId) { $out.reason = 'target_instance_mismatch'; $out['target_resident_instance_id'] = $TargetResidentInstanceId; $out['current_resident_instance_id'] = $curInst; return $out }
        }
        $ident = Test-ResidentIdentity $reg $StartTicksProbe
        $evInstId = if (Test-SupHasProp $reg 'resident_instance_id') { [string]$reg.resident_instance_id } else { $null }
        if ($null -ne $VramProbe) { try { $out.vram.free_mib_before = & $VramProbe } catch { } }
        [void](Set-ManifestCas -Path $WarmRegPath -Fence ([long](Get-ManifestFence $reg)) -Updates @{ state = 'STOPPING' })
        $stopped = $false
        if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
        if ($stopped -or -not $ident.alive) {
            # i23 MF1+2/MF5: reap the per-resident Job (durable tree-kill) + confirm ZERO members. No tracked job
            # (off-Windows / classic) => had_job:false => tree-gone by pid-death (already proven by StopProbe).
            $treeZero = $true
            if (-not [string]::IsNullOrWhiteSpace($evInstId)) { $ct = Close-ResidentJobTree -InstanceId $evInstId; if ($ct.had_job -and -not $ct.members_zero) { $treeZero = $false } }
            if (-not $treeZero) { $out.reason = 'partial_tree_term'; $out['tree_gone'] = $false; return $out }
            $out.evicted = $true; $out.reason = 'evicted'; $out['tree_gone'] = $true
            Clear-PoolManifest $WarmRegPath
            Start-Sleep -Milliseconds 150
            if ($null -ne $VramProbe) { try { $out.vram.free_mib_after = & $VramProbe } catch { } }
            if ($null -ne $out.vram.free_mib_before -and $null -ne $out.vram.free_mib_after) { $out.vram.recovered_mib = ($out.vram.free_mib_after - $out.vram.free_mib_before) }
        } else { $out.reason = 'alive_unidentified_not_killed' }
        return $out
    } finally { Exit-PoolLock $lock }
}

# GPU-handoff (finding #2/#15): evict-before-grant so releasing does not leave the GPU blocked for another
# consumer. Pure planner (PoolManager) + a bounded async-confirm of VRAM recovery (WDDM frees async).
function Invoke-SupervisorPrepareGpu {
    param([Parameter(Mandatory)][string]$WarmRegPath, [Parameter(Mandatory)][string]$LockPath,
          [int]$RequiredVramMib = 0, [int]$SafetyMib = 512, [int]$ConfirmTimeoutMs = 5000,
          [scriptblock]$StopProbe = $null, [scriptblock]$StartTicksProbe = $null, [scriptblock]$VramProbe = $null)
    $out = [ordered]@{ action = 'prepare_gpu'; required_vram_mib = $RequiredVramMib; safety_mib = $SafetyMib; target_mib = ($RequiredVramMib + $SafetyMib)
        had_resident = $false; plan = 'grant'; reason = 'no_resident'; evicted = $false; unmanaged_vram_pressure = $false
        free_mib_before = $null; free_mib_after = $null; recovered_mib = $null; ready = $false }
    if (-not $script:SupPoolCoreLoaded) { $out.reason = 'pool_core_absent'; return $out }
    $reg = Read-PoolManifest $WarmRegPath
    $hasResident = $false
    if ($null -ne $reg -and (Test-SupHasProp $reg 'pid') -and ([int]$reg.pid -gt 0)) {
        $il = Test-ResidentIdentity $reg $StartTicksProbe; $hasResident = [bool]$il.alive
    }
    $out.had_resident = $hasResident
    $freeBefore = if ($null -ne $VramProbe) { try { & $VramProbe } catch { $null } } else { $null }
    $out.free_mib_before = $freeBefore; $out.free_mib_after = $freeBefore
    $plan = Get-GpuHandoffPlan -FreeMib $freeBefore -RequiredMib $RequiredVramMib -HasResident $hasResident -SafetyMib $SafetyMib
    $out.plan = $plan.decision
    if ($plan.decision -eq 'evict_then_grant' -and $hasResident) {
        $lock = Enter-PoolLock -LockPath $LockPath -TimeoutMs 8000
        try {
            $reg2 = Read-PoolManifest $WarmRegPath
            if ($null -ne $reg2 -and (Test-SupHasProp $reg2 'pid')) {
                $ident2 = Test-ResidentIdentity $reg2 $StartTicksProbe
                $stopped = $false
                if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg2 $ident2) } catch { $stopped = $false } }
                if ($stopped -or -not $ident2.alive) {
                    $out.evicted = $true; $out.reason = 'evicted_for_handoff'; Clear-PoolManifest $WarmRegPath
                    $target = $RequiredVramMib + $SafetyMib
                    $deadline = (Get-SupNowUtc).AddMilliseconds($ConfirmTimeoutMs)
                    while ((Get-SupNowUtc) -lt $deadline) {
                        Start-Sleep -Milliseconds 200
                        $out.free_mib_after = if ($null -ne $VramProbe) { try { & $VramProbe } catch { $null } } else { $null }
                        if ($null -eq $out.free_mib_after -or $out.free_mib_after -ge $target) { break }
                    }
                } else { $out.reason = 'alive_unidentified_not_killed' }
            }
        } finally { Exit-PoolLock $lock }
    } elseif ($plan.decision -eq 'grant') { $out.reason = 'headroom_available' }
    elseif ($plan.decision -eq 'insufficient') {
        # i23 MF7: short headroom with NO managed target to evict -> UNMANAGED VRAM PRESSURE. Report it and
        # leave the GPU UNGRANTED (ready=$false); NEVER blind-kill the unidentified consumer holding the VRAM.
        $out.unmanaged_vram_pressure = $true; $out.reason = 'unmanaged_vram_pressure'
    }
    if ($null -ne $out.free_mib_before -and $null -ne $out.free_mib_after) { $out.recovered_mib = ($out.free_mib_after - $out.free_mib_before) }
    if ($null -eq $out.free_mib_after) { $out.ready = ($plan.decision -ne 'insufficient') }
    else { $out.ready = ($out.free_mib_after -ge $out.target_mib) }
    return $out
}

# Read-only residency status (no lease, no change).
function Get-SupervisorResidencyStatus {
    param([Parameter(Mandatory)][string]$WarmRegPath, [scriptblock]$StartTicksProbe = $null, [scriptblock]$HealthProbe = $null, [int]$KeepResidentSeconds = 90)
    $reg = Read-PoolManifest $WarmRegPath
    $out = [ordered]@{ has_resident = $false; resident_pid = $null; model_id = $null; resident_config_hash = $null
        alive = $false; identity_ok = $false; healthy = $false; idle_ms = $null; keep_resident_seconds = $KeepResidentSeconds
        instance_generation = $null; fence = $null; state = 'EMPTY'; port = $null }
    if ($null -eq $reg -or -not (Test-SupHasProp $reg 'pid') -or ([int]$reg.pid -le 0)) { return $out }
    $out.has_resident = $true; $out.resident_pid = [int]$reg.pid
    $out.model_id = if (Test-SupHasProp $reg 'model_id') { [string]$reg.model_id } else { $null }
    $out.resident_config_hash = if (Test-SupHasProp $reg 'resident_config_hash') { [string]$reg.resident_config_hash } else { $null }
    $out.instance_generation = if (Test-SupHasProp $reg 'instance_generation') { [string]$reg.instance_generation } else { $null }
    $out.fence = if ($script:SupPoolCoreLoaded) { [long](Get-ManifestFence $reg) } else { $null }
    $out.state = if ($script:SupPoolCoreLoaded) { Get-ManifestState $reg } else { 'UNKNOWN' }
    $out.port = if (Test-SupHasProp $reg 'port') { [int]$reg.port } else { $null }
    $il = if ($script:SupPoolCoreLoaded) { Test-ResidentIdentity $reg $StartTicksProbe } else { [ordered]@{ alive = (Test-SupPidAlive ([int]$reg.pid)); identity_ok = $false } }
    $out.alive = [bool]$il.alive; $out.identity_ok = [bool]$il.identity_ok
    if ($il.alive -and $null -ne $HealthProbe) { try { $out.healthy = [bool](& $HealthProbe '127.0.0.1' ([int]$out.port)) } catch { $out.healthy = $false } }
    $stamp = if (Test-SupHasProp $reg 'last_used_utc') { [string]$reg.last_used_utc } elseif (Test-SupHasProp $reg 'started_at_utc') { [string]$reg.started_at_utc } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($stamp)) { $t = ConvertFrom-SupUtcString $stamp; if ($null -ne $t) { $out.idle_ms = [int]((Get-SupNowUtc) - $t).TotalMilliseconds } }
    return $out
}

Export-ModuleMember -Function `
    Test-SupHasProp, Get-SupNowUtc, ConvertTo-SupUtcString, ConvertFrom-SupUtcString, Read-SupJson, Write-SupJsonAtomic, Test-SupPidAlive, `
    Get-SupervisorPaths, Initialize-SupervisorDirs, `
    Get-SupervisorSingletonName, Enter-SupervisorSingleton, Exit-SupervisorSingleton, `
    Write-SupervisorManifest, Read-SupervisorManifest, Clear-SupervisorManifest, Test-SupervisorHeartbeatFresh, Test-SupervisorLiveness, `
    New-SupervisorRequest, Test-SupervisorRequestValid, Test-SupervisorRequestId, Reset-SupervisorConsumedRequests, Write-SupervisorRequest, Read-SupervisorRequestFile, `
    New-SupervisorResponse, Write-SupervisorResponse, Read-SupervisorResponseFile, `
    Send-SupervisorRequest, Invoke-SupervisorPollOnce, `
    Initialize-JobObjectType, New-GatewayJobObject, Add-ProcessToGatewayJob, Close-GatewayJob, `
    Initialize-CustodyType, New-CustodiedServer, ConvertTo-Win32CommandLine, Register-ResidentJob, Get-ResidentJobInfo, Get-ResidentJobMemberCount, Close-ResidentJobTree, Close-AllResidentJobTrees, `
    Invoke-SupervisorReconcile, Invoke-SupervisorEnsureResident, Invoke-SupervisorEvict, Invoke-SupervisorPrepareGpu, Get-SupervisorResidencyStatus `
    -Variable SUP_MANIFEST_SCHEMA, SUP_REQ_SCHEMA, SUP_RESP_SCHEMA, SUP_OPS
