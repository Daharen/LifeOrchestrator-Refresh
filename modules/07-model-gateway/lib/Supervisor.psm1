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
    # "running" for routing = alive AND identity matches AND still in RUNNING state. Heartbeat freshness is
    # reported but is advisory for routing (a busy in-process op can briefly delay a heartbeat write).
    $res.running = ($res.alive -and $res.identity_ok -and $stateRunning)
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
function Test-SupervisorRequestValid {
    param([object]$Request)
    $errs = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Request) { $errs.Add('null_request'); return [ordered]@{ valid = $false; errors = $errs.ToArray() } }
    if (-not (Test-SupHasProp $Request 'schema') -or [string]$Request.schema -ne $script:SUP_REQ_SCHEMA) { $errs.Add('bad_schema') }
    if (-not (Test-SupHasProp $Request 'request_id') -or [string]::IsNullOrWhiteSpace([string]$Request.request_id)) { $errs.Add('missing_request_id') }
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
        return [ordered]@{ ok = $false; delivered = $false; error = [ordered]@{ code = 'supervisor_unavailable'; message = 'no running supervisor (attach failed); caller should use the per-call path'; retryable = $true }; liveness = $live }
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
        # if the supervisor dies mid-wait, stop waiting (fail fast so the caller can degrade)
        $m2 = Read-SupervisorManifest $Paths.manifest
        $l2 = Test-SupervisorLiveness -Manifest $m2 -StartTicksProbe $StartTicksProbe -HeartbeatMaxAgeSeconds $HeartbeatMaxAgeSeconds
        if (-not $l2.alive) {
            try { Remove-Item -LiteralPath $reqPath -Force -ErrorAction SilentlyContinue } catch { }
            return [ordered]@{ ok = $false; delivered = $true; error = [ordered]@{ code = 'supervisor_died'; message = 'supervisor exited while the request was in flight'; retryable = $true }; request_id = $req.request_id }
        }
        Start-Sleep -Milliseconds $PollMs
    }
    try { Remove-Item -LiteralPath $reqPath -Force -ErrorAction SilentlyContinue } catch { }
    return [ordered]@{ ok = $false; delivered = $true; error = [ordered]@{ code = 'supervisor_timeout'; message = "no response within ${TimeoutMs} ms"; retryable = $true }; request_id = $req.request_id }
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
            if ($op -eq 'shutdown') {
                $shutdown = $true
                $resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ action = 'shutdown'; accepted = $true }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
            } elseif ($op -eq 'ping') {
                $resp = New-SupervisorResponse -Request $req -Ok $true -Result ([ordered]@{ action = 'ping'; pong = $true; supervisor_pid = $SupervisorPid }) -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
            } elseif ($Handlers.ContainsKey($op)) {
                try {
                    $r = & $Handlers[$op] $req
                    $resp = New-SupervisorResponse -Request $req -Ok $true -Result $r -SupervisorPid $SupervisorPid -SupervisorGeneration $SupervisorGeneration
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
        [scriptblock]$HealthProbe = $null, [scriptblock]$StopProbe = $null
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
        [string]$ResidentInstanceId   # v0.4 (i21): caller-pinned per-server-tree instance id stamped into the manifest (the target of every destructive op); omitted => minted here
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
            # cannot serve / unhealthy / forced -> EVICT (CAS STOPPING, confirm exit + VRAM), then reload
            $myFence = $prevFence + 1
            [void](Set-ManifestCas -Path $WarmRegPath -Fence $prevFence -Updates @{ state = 'STOPPING' })
            if ($ident.alive) {
                if ($null -ne $VramProbe) { try { $out.vram.free_mib_before = & $VramProbe } catch { } }
                $stopped = $false
                if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
                if ($stopped) {
                    $out.evicted = $true; $out.evict_confirmed = $true
                    Start-Sleep -Milliseconds 200
                    if ($null -ne $VramProbe) { try { $out.vram.free_mib_after = & $VramProbe } catch { } }
                    if ($null -ne $out.vram.free_mib_before -and $null -ne $out.vram.free_mib_after) { $out.vram.recovered_mib = ($out.vram.free_mib_after - $out.vram.free_mib_before) }
                } else { $out.evict_confirmed = $false }
            }
            $out.swap_count = $prevSwaps + 1
            $out.action = 'evict_reload'
            Clear-PoolManifest $WarmRegPath
            $reg = $null
        }

        # ---- LAUNCH a fresh resident (cold_start or evict_reload). The Launcher assigns the pid to the Job. ----
        $portHint = if ($ModelMeta.ContainsKey('port_hint')) { [int]$ModelMeta['port_hint'] } else { 0 }
        $launch = & $Launcher $ReqConfig $portHint
        if ($null -eq $launch -or -not (Test-SupHasProp $launch 'pid') -or ([int]$launch.pid -le 0)) {
            throw [PSCustomObject]@{ code = 'server_start_failed'; message = 'launcher returned no pid' }
        }
        $serverPid = [int]$launch.pid
        $usePort = if (Test-SupHasProp $launch 'port') { [int]$launch.port } else { $portHint }
        $startTicks = if (Test-SupHasProp $launch 'start_ticks') { [long]$launch.start_ticks } else { 0 }
        $instanceGen = if (Test-SupHasProp $launch 'instance_generation') { [string]$launch.instance_generation } else { (New-InstanceGeneration) }
        $jobOwned = if (Test-SupHasProp $launch 'job_owned') { [bool]$launch.job_owned } else { $false }
        # v0.4 (i21): the per-server-tree resident_instance_id -- the TARGET of every destructive op (never
        # generation/config-key alone). Caller-pinned (so the res.lease grant and the manifest agree) or minted.
        $resInstId = if (-not [string]::IsNullOrWhiteSpace($ResidentInstanceId)) { $ResidentInstanceId } else { ('ri' + [Guid]::NewGuid().ToString('N')) }
        $out.started_new = $true; $out.pid = $serverPid; $out.port = $usePort; $out.instance_generation = $instanceGen; $out.fence = $myFence; $out.job_owned = $jobOwned
        $out.resident_instance_id = $resInstId

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
            managed_by = $managedBy; manager_holder = $FenceHolder; job_owned = $jobOwned
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
            Clear-PoolManifest $WarmRegPath
            throw [PSCustomObject]@{ code = 'health_timeout'; message = "server did not become healthy within $LoadTimeoutSec s" }
        }
        # finding #4: verify the LISTENING SOCKET owner before publishing RESIDENT (advisory off-Windows)
        $sockVerified = Test-SocketOwner -Port $usePort -ExpectedPid $serverPid -SocketOwnerProbe $SocketOwnerProbe
        $out.socket_owner_verified = $sockVerified
        if ($sockVerified -eq $false) {
            if ($null -ne $StopProbe) { try { [void](& $StopProbe (Read-PoolManifest $WarmRegPath) (Test-ResidentIdentity (Read-PoolManifest $WarmRegPath) $StartTicksProbe)) } catch { } }
            Clear-PoolManifest $WarmRegPath
            throw [PSCustomObject]@{ code = 'socket_owner_mismatch'; message = "listening socket on port $usePort not owned by pid $serverPid (wrong-generation guard)" }
        }
        # STARTING -> RESIDENT via fence-gated CAS
        $casOk = Set-ManifestCas -Path $WarmRegPath -Fence $myFence -Updates @{ state = 'RESIDENT'; socket_owner_verified = $sockVerified }
        if (-not $casOk) { $out.can_serve_mismatches = @('resident_publish_cas_failed_fence_superseded') }
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
        if ($null -ne $VramProbe) { try { $out.vram.free_mib_before = & $VramProbe } catch { } }
        [void](Set-ManifestCas -Path $WarmRegPath -Fence ([long](Get-ManifestFence $reg)) -Updates @{ state = 'STOPPING' })
        $stopped = $false
        if ($null -ne $StopProbe) { try { $stopped = [bool](& $StopProbe $reg $ident) } catch { $stopped = $false } }
        if ($stopped -or -not $ident.alive) {
            $out.evicted = $true; $out.reason = 'evicted'
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
        had_resident = $false; plan = 'grant'; reason = 'no_resident'; evicted = $false
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
    elseif ($plan.decision -eq 'insufficient') { $out.reason = 'insufficient_headroom_no_resident' }
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
    Write-SupervisorManifest, Read-SupervisorManifest, Clear-SupervisorManifest, Test-SupervisorHeartbeatFresh, Test-SupervisorLiveness, `
    New-SupervisorRequest, Test-SupervisorRequestValid, Write-SupervisorRequest, Read-SupervisorRequestFile, `
    New-SupervisorResponse, Write-SupervisorResponse, Read-SupervisorResponseFile, `
    Send-SupervisorRequest, Invoke-SupervisorPollOnce, `
    Initialize-JobObjectType, New-GatewayJobObject, Add-ProcessToGatewayJob, Close-GatewayJob, `
    Invoke-SupervisorReconcile, Invoke-SupervisorEnsureResident, Invoke-SupervisorEvict, Invoke-SupervisorPrepareGpu, Get-SupervisorResidencyStatus `
    -Variable SUP_MANIFEST_SCHEMA, SUP_REQ_SCHEMA, SUP_RESP_SCHEMA, SUP_OPS
