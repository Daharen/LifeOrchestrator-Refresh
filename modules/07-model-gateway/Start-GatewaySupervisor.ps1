#requires -Version 7.0
<#
  Start-GatewaySupervisor.ps1 -- model.gateway #7 warm-pool DURABLE gateway supervisor (lifecycle CLI).
  WARM_POOL_DESIGN section 10 residual (a); the durable form of red-team finding 5.

  The PERSISTENT process that owns the warm resident llama-server ACROSS separate per-call gateway
  invocations. It creates ONE Windows Job Object (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE) and assigns every
  llama-server it starts to it, so if the supervisor dies -- for any reason -- the OS reaps the WHOLE server
  tree (durable finding-5 guarantee; own-by-HANDLE, never by process-name). Per-call gateways ATTACH over a
  file-protocol control channel and reuse the resident (~1 ms, no respawn) instead of each managing a server.

  All integrity is delegated to lib/PoolManager.psm1 (fencing token + CAS, CanServe, the crash-atomic state
  machine, verified socket-owner publish, GPU-handoff planning) through lib/Supervisor.psm1; the supervisor is
  the single owner running those transitions. Integrity invariants stay NON-bypassable; the gateway's
  -BypassPoolManager cold-isolated escape is untouched. The pool STAYS DEFAULT-OFF this wave.

  ACTIONS:
    start      launch a detached supervisor (idempotent; returns already_running if one is live)
    run        the detached loop body (creates the Job Object, serves the control channel); not called directly
    stop       graceful shutdown request -> the resident is evicted + the Job Object reaps the tree; then clear
    status     report the supervisor + resident (read-only)
    reconcile  crash-recovery reconcile of the resident manifest (verify-the-claim, never trust)
    ping       round-trip a control-channel ping to a running supervisor

  FOLLOW-ON (named, NOT built this wave): exec.watchdog #00.1 relaunch integration -- have the watchdog
  restart a dead supervisor exactly as it relaunches the executor (Recover-Executor pattern). See README.

  ASCII-only. UTF-8 no BOM. LF. Emits ONE lifeorch.model_gateway.supervisor_result/0.1 JSON object to stdout;
  all diagnostics go to stderr / the supervisor log.
#>
[CmdletBinding()]
param(
    [ValidateSet('start','stop','status','run','reconcile','ping')]
    [string]$Action = 'status',
    [string]$Registry,
    [string]$SupervisorRoot,
    [string]$WarmRegistryPath,
    [string]$PwshPath,
    [int]$PollMs = 200,
    [int]$HeartbeatSec = 5,
    [int]$IdleShutdownSec = 0,          # 0 = run until stopped; >0 = auto-exit after this many idle seconds (soak-friendly)
    [int]$StartTimeoutSec = 25,
    [int]$StopTimeoutSec = 25,
    [int]$LoadTimeoutSec = 120,
    [int]$FenceTtlSeconds = 120,
    [int]$KeepResidentSeconds = 90,
    # one-shot client params (ensure/status/prepare done via -Action against a running supervisor are rare;
    # normally the loop's handlers do the work when a per-call gateway sends a request)
    [string]$Model,
    [string]$Tier,
    [int]$GpuLayers = -1,
    [int]$Context = 0,
    [string]$CacheTypeK = 'f16',
    [string]$CacheTypeV = 'f16',
    [switch]$FlashAttn,
    [int]$Parallel = 1,
    [int]$RequiredVramMib = 0,
    [int]$VramSafetyMib = 512,
    [int]$RequestTimeoutMs = 30000,
    [switch]$NoDetach                   # start: launch the run child in-foreground/as-a-child (tests) instead of Win32_Process.Create
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)

# -Global so PoolManager + Supervisor exports resolve from the handler/launcher CLOSURES too. A closure made
# with .GetNewClosure() runs in its own module session state; script-level (non-global) module imports are
# NOT visible there, so a handler calling Get-ResidentConfig / New-InstanceGeneration / Add-ProcessToGatewayJob
# would fail 'not recognized'. Global import puts them in the global command table, visible from every scope.
Import-Module (Join-Path $PSScriptRoot 'lib/PoolManager.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'lib/Supervisor.psm1') -Force -Global

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[gateway.supervisor] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256HexLocal([byte[]]$b) { $s = [System.Security.Cryptography.SHA256]::Create(); try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() } }

function Get-PwshExeLocal {
    if (-not [string]::IsNullOrWhiteSpace($PwshPath) -and (Test-Path -LiteralPath $PwshPath)) { return $PwshPath }
    $cand = Join-Path $PSHOME 'pwsh'
    if (Test-Path -LiteralPath $cand) { return $cand }
    if (Test-Path -LiteralPath "$cand.exe") { return "$cand.exe" }
    $gc = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $gc) { return $gc.Source }
    return 'pwsh'
}
function Get-SupFreePort([int]$start = 8140) {
    for ($p = $start; $p -lt ($start + 400); $p++) {
        try { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p); $l.Start(); $l.Stop(); return $p } catch { continue }
    }
    return 0
}

# ---------- seams (real Windows/GPU probes; degrade off-box, NEVER throw) ----------
$HealthProbe = {
    param([string]$ServerHost, [int]$ServerPort)
    if ($ServerPort -le 0) { return $false }
    try { $h = Invoke-WebRequest -Uri "http://$($ServerHost):$ServerPort/health" -UseBasicParsing -TimeoutSec 2; return ($h.StatusCode -eq 200) } catch { return $false }
}
$StartTicksProbe = { param([int]$ProcId) try { return [long]((Get-Process -Id $ProcId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 } }
$SocketOwnerProbe = {
    param([int]$SockPort)
    if ($SockPort -le 0) { return $null }
    try {
        $gc = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
        if ($null -ne $gc) {
            $c = Get-NetTCPConnection -LocalPort $SockPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $c) { return [int]$c.OwningProcess }
            return $null
        }
    } catch { }
    foreach ($tool in @('lsof','ss')) {
        try {
            $cmd = Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $cmd) { continue }
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try {
                if ($tool -eq 'lsof') {
                    $o = & $cmd.Source "-iTCP:$SockPort" '-sTCP:LISTEN' '-t' '-P' '-n' 2>$null
                    $line = (@($o) | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -First 1)
                    if ($null -ne $line) { return [int]("$line".Trim()) }
                } else {
                    $o = & $cmd.Source '-ltnpH' 2>$null
                    foreach ($ln in @($o)) { if ("$ln" -match ":$SockPort\s" -and "$ln" -match 'pid=(\d+)') { return [int]$Matches[1] } }
                }
            } finally { $ErrorActionPreference = $prev }
        } catch { }
    }
    return $null
}
# i23 MF7: PINNED ABSOLUTE nvidia-smi + a HARD deadline (Get-GpuFreeMibBounded, PoolManager). A hung/absent
# nvidia-smi -> $null (unknown), never a hang and never a bare-PATH shim. The pool lock is NEVER held across it.
$VramProbe = {
    try { return (Get-GpuFreeMibBounded -DeadlineMs 4000) } catch { return $null }
}
# StopProbe mirrors the gateway's Stop-ResidentServer: kill the whole TREE by PID (taskkill /T on Windows),
# confirm exit; refuse to kill an alive-but-unidentified pid (PID reuse -> a foreign process). The Job Object
# is the durable backstop; this is the explicit evict path.
$StopProbe = {
    param($Reg, $Liveness)
    if ($null -eq $Reg -or -not ($Reg.PSObject.Properties.Name -contains 'pid')) { return $true }
    if (-not $Liveness.alive) { return $true }
    if (-not $Liveness.identity_ok) { return $false }
    $procId = [int]$Reg.pid
    try { if ($IsWindows) { & taskkill /PID $procId /T /F 2>$null | Out-Null } } catch { }
    try { $pp = Get-Process -Id $procId -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
    for ($i = 0; $i -lt 30; $i++) {
        $still = $null; try { $still = Get-Process -Id $procId -ErrorAction SilentlyContinue } catch { $still = $null }
        if ($null -eq $still) { return $true }
        try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch { }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

# ---------- engine exe content-hash cache (identity; matches the gateway so config hashes agree) ----------
$script:ExeHashCache = @{}
function Get-EngineExeHashLocal([string]$EnginePath) {
    if ([string]::IsNullOrWhiteSpace($EnginePath) -or -not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) { return $null }
    try {
        $fi = Get-Item -LiteralPath $EnginePath
        $key = "$($fi.FullName)|$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
        if ($script:ExeHashCache.ContainsKey($key)) { return $script:ExeHashCache[$key] }
        $h = Get-Sha256HexLocal ([System.IO.File]::ReadAllBytes($fi.FullName))
        $script:ExeHashCache[$key] = $h
        return $h
    } catch { return $null }
}

# ---------- model resolution (mirrors Invoke-ModelGateway.ps1; Stage-1.1 knobs only) ----------
function Resolve-ModelLaunch {
    param([object]$Reg, [hashtable]$P)
    $wantModel = if ($P.ContainsKey('model')) { [string]$P['model'] } else { '' }
    $wantTier  = if ($P.ContainsKey('tier'))  { [string]$P['tier'] }  else { '' }
    $models = @(); if (Has $Reg 'models') { $models = @($Reg.models) }
    $wantId = $null
    if (-not [string]::IsNullOrWhiteSpace($wantModel)) { $wantId = $wantModel }
    elseif (-not [string]::IsNullOrWhiteSpace($wantTier)) {
        if ((Has $Reg 'tiers') -and (Has $Reg.tiers 'llm') -and (Has $Reg.tiers.llm $wantTier)) { $wantId = [string]$Reg.tiers.llm.$wantTier }
        else { throw [PSCustomObject]@{ code = 'tier_not_found'; message = "tier '$wantTier' not defined for llm" } }
    } else {
        if ((Has $Reg 'defaults') -and (Has $Reg.defaults 'llm')) { $wantId = [string]$Reg.defaults.llm }
        else { throw [PSCustomObject]@{ code = 'no_model_selected'; message = 'provide model or tier; no registry default llm' } }
    }
    $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $wantId) } | Select-Object -First 1
    if ($null -eq $m) { throw [PSCustomObject]@{ code = 'model_not_found'; message = "model '$wantId' not in registry" } }
    $mType = if (Has $m 'type') { [string]$m.type } else { 'unknown' }
    if (-not ((Has $m 'wired') -and [bool]$m.wired)) { throw [PSCustomObject]@{ code = 'model_not_wired'; message = "model '$wantId' not wired" } }
    if ($mType -ne 'llm') { throw [PSCustomObject]@{ code = 'unsupported_type'; message = "type=llm only (got '$mType')" } }
    $engine = if (Has $m 'engine') { [string]$m.engine } else { '' }
    if ($engine -ne 'llama-server') { throw [PSCustomObject]@{ code = 'unsupported_engine'; message = "engine=llama-server only (got '$engine')" } }
    $enginePath = if (Has $m 'engine_path') { [string]$m.engine_path } else { $null }
    if ([string]::IsNullOrWhiteSpace($enginePath) -and (Has $Reg 'engines') -and (Has $Reg.engines 'llama-server')) { $enginePath = [string]$Reg.engines.'llama-server' }
    if ([string]::IsNullOrWhiteSpace($enginePath) -or -not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'engine_not_found'; message = "llama-server engine not found at '$enginePath'" } }
    $modelPath = if (Has $m 'path') { [string]$m.path } else { '' }
    if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'model_file_missing'; message = "model file not found at '$modelPath'" } }
    $ngl = if ($P.ContainsKey('gpu_layers') -and [int]$P['gpu_layers'] -ge 0) { [int]$P['gpu_layers'] } elseif (Has $m 'gpu_layers') { [int]$m.gpu_layers } else { 99 }
    $ctx = if ($P.ContainsKey('context') -and [int]$P['context'] -gt 0) { [int]$P['context'] } elseif (Has $m 'context') { [int]$m.context } else { 4096 }
    $noThink = ((Has $m 'no_think') -and [bool]$m.no_think)
    $ctk = if ($P.ContainsKey('cache_type_k')) { [string]$P['cache_type_k'] } else { 'f16' }
    $ctv = if ($P.ContainsKey('cache_type_v')) { [string]$P['cache_type_v'] } else { 'f16' }
    $flash = ($P.ContainsKey('flash_attn') -and [bool]$P['flash_attn'])
    $np = if ($P.ContainsKey('parallel') -and [int]$P['parallel'] -gt 0) { [int]$P['parallel'] } else { 1 }
    $exeHash = Get-EngineExeHashLocal $enginePath
    $reqConfig = Get-ResidentConfig $m $Reg $ngl $ctx $noThink $ctk $ctv $flash $np $exeHash
    return [ordered]@{
        model_id = [string]$m.model_id; engine_path = $enginePath; model_path = $modelPath
        ngl = $ngl; ctx = $ctx; no_think = $noThink; ctk = $ctk; ctv = $ctv; flash = $flash; np = $np
        req_config = $reqConfig
    }
}

# Build a launcher scriptblock (closure via GetNewClosure so the resolved locals survive being invoked from
# inside the Supervisor module -- the CURRENT_STATE 'bare-local handler loses scope' gotcha). It Start-Process
# the server as a CHILD of the (persistent, detached) supervisor, assigns the pid to the Job Object, and
# returns identity. The mock/test .ps1 engine is run under pwsh (same seam the gateway uses).
function New-RealLauncher {
    param([object]$ML, [object]$Job, [string]$Pwsh, [string]$LogDir, [hashtable]$TrustedHashes = $null)
    $enginePath = [string]$ML.engine_path; $modelPath = [string]$ML.model_path
    $ngl = [int]$ML.ngl; $ctx = [int]$ML.ctx; $ctk = [string]$ML.ctk; $ctv = [string]$ML.ctv; $flash = [bool]$ML.flash; $np = [int]$ML.np
    $modelIdRef = [string]$ML.model_id; $trustedRef = $TrustedHashes
    $jobRef = $Job; $pwshRef = $Pwsh; $logDirRef = $LogDir
    $sb = {
        param($ReqConfig, [int]$PortHint, [string]$ResidentInstanceId)
        $port = if ($PortHint -gt 0) { $PortHint } else { Get-SupFreePort 8140 }
        if ($port -le 0) { throw [PSCustomObject]@{ code = 'no_free_port'; message = 'no free loopback port' } }
        $srvArgs = @('-m', $modelPath, '-ngl', "$ngl", '-c', "$ctx", '--host', '127.0.0.1', '--port', "$port", '--no-warmup', '--parallel', "$np")
        if (-not [string]::IsNullOrWhiteSpace($ctk) -and $ctk -ne 'f16') { $srvArgs += @('--cache-type-k', $ctk) }
        if (-not [string]::IsNullOrWhiteSpace($ctv) -and $ctv -ne 'f16') { $srvArgs += @('--cache-type-v', $ctv) }
        if ($flash) { $srvArgs += @('--flash-attn') }
        if ($enginePath -match '\.ps1$') { $spFile = $pwshRef; $spArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$enginePath) + $srvArgs }
        else { $spFile = $enginePath; $spArgs = $srvArgs }
        if (-not (Test-Path -LiteralPath $logDirRef)) { New-Item -ItemType Directory -Path $logDirRef -Force | Out-Null }
        $so = Join-Path $logDirRef "server-$port.out.log"; $se = Join-Path $logDirRef "server-$port.err.log"
        $rii = if (-not [string]::IsNullOrWhiteSpace($ResidentInstanceId)) { $ResidentInstanceId } else { ('ri' + [Guid]::NewGuid().ToString('N')) }
        # i23 MF10: build a PRE-LAUNCH content-verify set from the TRUSTED-HASHES manifest (if provisioned). Each
        # engine/model file is sha256-verified (+ reparse-point rejected) immediately before launch. Absent trusted
        # hashes => no verification (a NAMED residual: provision trusted-hashes.json in the ACL'd state dir).
        $preVerify = $null
        if ($null -ne $trustedRef -and $trustedRef.ContainsKey($modelIdRef)) {
            $th = $trustedRef[$modelIdRef]; $preVerify = @{}
            if ($null -ne $th) {
                $eh = if ($th -is [System.Collections.IDictionary]) { [string]$th['engine_sha256'] } elseif ($th.PSObject.Properties.Name -contains 'engine_sha256') { [string]$th.engine_sha256 } else { '' }
                $mh = if ($th -is [System.Collections.IDictionary]) { [string]$th['model_sha256'] } elseif ($th.PSObject.Properties.Name -contains 'model_sha256') { [string]$th.model_sha256 } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($eh)) { $preVerify[$enginePath] = $eh }
                if (-not [string]::IsNullOrWhiteSpace($mh)) { $preVerify[$modelPath] = $mh }
            }
        }
        # i23 MF1+2: launch UNDER PER-RESIDENT SUSPENDED-CREATE JOB CUSTODY (Windows) -- suspended-create ->
        # assign -> IsProcessInJob verify -> resume; the supervisor holds the per-resident job handle. Off-Windows
        # this degrades to Start-Process (job_owned:false, honestly reported). The single supervisor-wide Job
        # ($jobRef) is retained ONLY as a crash-time backstop reaper (precision correction).
        $cs = New-CustodiedServer -FilePath $spFile -Arguments $spArgs -WorkDir $logDirRef -ResidentInstanceId $rii -StdoutPath $so -StderrPath $se -PreLaunchVerify $preVerify
        if (-not $cs.ok) { return [ordered]@{ pid = 0; job_owned = $false; custody_supported = $cs.custody_supported; stage = $cs.stage; error = $cs.error; host = '127.0.0.1'; port = $port } }
        $serverPid = [int]$cs.pid
        # belt-and-suspenders: also add to the shared supervisor-wide job (crash-time backstop). On Win8+ a
        # process may be in multiple (nested) jobs; a failure here is NON-fatal (per-resident custody is primary).
        if (-not $cs.custody_supported) { try { [void](Add-ProcessToGatewayJob -Job $jobRef -ProcessId $serverPid) } catch { } }
        $startTicks = if ($cs.start_ticks -gt 0) { [long]$cs.start_ticks } else { 0 }
        if ($startTicks -le 0) { try { $startTicks = [long]((Get-Process -Id $serverPid -ErrorAction Stop).StartTime.Ticks) } catch { } }
        return [ordered]@{ pid = $serverPid; start_ticks = $startTicks; instance_generation = (New-InstanceGeneration); host = '127.0.0.1'; port = $port; job_owned = [bool]$cs.job_owned; job_instance_id = $cs.job_instance_id; custody_supported = [bool]$cs.custody_supported }
    }.GetNewClosure()
    return $sb
}

# ---------- resolve paths + registry ----------
$supRoot = if (-not [string]::IsNullOrWhiteSpace($SupervisorRoot)) { $SupervisorRoot } else { Join-Path $PSScriptRoot 'runtime/supervisor' }
$warmRegDefault = if (-not [string]::IsNullOrWhiteSpace($WarmRegistryPath)) { $WarmRegistryPath } else { Join-Path $PSScriptRoot 'runtime/warm-server.json' }
$paths = Get-SupervisorPaths -Root $supRoot -WarmRegistryPath $warmRegDefault
$regPath = if (-not [string]::IsNullOrWhiteSpace($Registry)) { $Registry } else { Join-Path $PSScriptRoot 'models.json' }
$pwshExe = Get-PwshExeLocal

$warnings = New-Object System.Collections.Generic.List[string]
function Emit([string]$Act, [string]$Status, [object]$Result, [object]$ErrorObj) {
    $env = [ordered]@{
        schema = 'lifeorch.model_gateway.supervisor_result/0.1'
        action = $Act; status = $Status; result = $Result; error = $ErrorObj
        warnings = $warnings.ToArray()
        host = [System.Net.Dns]::GetHostName()
        emitted_utc = ([DateTime]::UtcNow).ToString('o')
    }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 14))
}

# =====================================================================================================
# RUN -- the detached loop body. Creates the Job Object, publishes the supervisor manifest, serves the
# control channel, and reaps on exit. Everything a per-call gateway asks for happens here.
# =====================================================================================================
function Invoke-SupervisorRun {
    Initialize-SupervisorDirs -Paths $paths
    # i23 MF3: claim the lifetime singleton BEFORE publishing anything. A second supervisor on this root cannot
    # claim it and exits cleanly (no double custody). Held for the whole run; released in the finally.
    $singleton = Enter-SupervisorSingleton -Root $paths.root -TimeoutMs 0
    if (-not $singleton.acquired) {
        Write-Diag "another supervisor already holds the singleton for $($paths.root) (reason=$($singleton.reason)); exiting cleanly"
        Emit 'run' 'ok' ([ordered]@{ ran = $false; already_running = $true; reason = 'singleton_held'; singleton = $singleton.name; supervisor_root = $paths.root }) $null
        return
    }
    $reg = $null
    try { if (Test-Path -LiteralPath $regPath -PathType Leaf) { $reg = (Get-Content -LiteralPath $regPath -Raw) | ConvertFrom-Json } } catch { $reg = $null }
    if ($null -eq $reg) { Write-Diag "WARNING: registry not loaded from $regPath; ensure_resident will error per-request" }

    $job = New-GatewayJobObject
    Write-Diag "job object: supported=$($job.supported) reason=$($job.reason) name=$($job.name)"
    $selfTicks = 0; try { $selfTicks = [long]((Get-Process -Id $PID).StartTime.Ticks) } catch { }
    $generation = [Guid]::NewGuid().ToString('N')
    $nowUtc = ([DateTime]::UtcNow).ToString('o')
    $manifest = [ordered]@{
        schema = 'lifeorch.model_gateway.supervisor/0.1'; state = 'RUNNING'
        pid = $PID; start_ticks = $selfTicks; supervisor_generation = $generation
        host = '127.0.0.1'; control_dir = $paths.control; req_dir = $paths.req_dir; resp_dir = $paths.resp_dir
        warm_registry = $paths.warm_registry; warm_lock = $paths.warm_lock; registry = $regPath; pwsh = $pwshExe
        job_object = [ordered]@{ supported = [bool]$job.supported; name = $job.name; kill_on_close = $true; reason = $job.reason }
        managed_by = 'model.gateway.supervisor'; poll_ms = $PollMs
        started_at_utc = $nowUtc; heartbeat_utc = $nowUtc; idle_shutdown_sec = $IdleShutdownSec
    }
    [void](Write-SupervisorManifest -Path $paths.manifest -Obj $manifest)
    Write-Diag "supervisor RUNNING pid=$PID gen=$generation root=$($paths.root) warm_registry=$($paths.warm_registry)"

    # startup reconcile: verify any prior published resident as a CLAIM (never trust). Runs without our lock.
    # i23 MF9: -RequireCustodian -- a FRESH supervisor holds NO retained custodian, so a manifest-only survivor
    # is an orphan of failed custody (never adopted); it is fenced/killed and the pool driven to a clean EMPTY.
    try {
        $rc = Invoke-SupervisorReconcile -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -StartTicksProbe $StartTicksProbe -SocketOwnerProbe $SocketOwnerProbe -HealthProbe $HealthProbe -StopProbe $StopProbe -RequireCustodian
        Write-Diag "startup reconcile: action=$($rc.action) kept=$($rc.kept_resident) killed_pid=$($rc.killed_pid)"
    } catch { Write-Diag "startup reconcile error: $($_.Exception.Message)" }

    # ---- handler map (GetNewClosure so the closures survive invocation from inside the Supervisor module) ----
    $ensureHandler = {
        param($Request)
        if ($null -eq $reg) { throw [PSCustomObject]@{ code = 'registry_absent'; message = "registry not loaded from $regPath" } }
        $p = @{}
        if ($null -ne $Request -and ($Request.PSObject.Properties.Name -contains 'params') -and $null -ne $Request.params) {
            foreach ($pp in $Request.params.PSObject.Properties) { $p[$pp.Name] = $pp.Value }
        }
        $ml = Resolve-ModelLaunch -Reg $reg -P $p
        $forceReload = ($p.ContainsKey('force_reload') -and [bool]$p['force_reload'])
        # v0.4 (i21): a caller-pinned resident_instance_id + instance_generation (the res.lease transition
        # capability identities) stamp the manifest so the lease's destructive-op target / generation binding
        # and the actual server tree agree. Absent => minted inside.
        $reqInstId = if ($p.ContainsKey('resident_instance_id')) { [string]$p['resident_instance_id'] } else { $null }
        $reqInstGen = if ($p.ContainsKey('instance_generation')) { [string]$p['instance_generation'] } else { $null }
        # i23 MF10: load the optional TRUSTED-HASHES manifest (model_id -> {engine_sha256, model_sha256}) so the
        # launcher content-verifies the engine+model bytes before launch. Provisioned OUT of the mutable
        # models.json (the digest's anti-theater rule). Absent => no verification (a named residual).
        $trustedHashes = $null
        $thPath = Join-Path $paths.root 'trusted-hashes.json'
        try { if (Test-Path -LiteralPath $thPath -PathType Leaf) { $thj = (Get-Content -LiteralPath $thPath -Raw) | ConvertFrom-Json; $trustedHashes = @{}; foreach ($pr in $thj.PSObject.Properties) { $trustedHashes[$pr.Name] = $pr.Value } } } catch { $trustedHashes = $null }
        $launcher = New-RealLauncher -ML $ml -Job $job -Pwsh $pwshExe -LogDir (Join-Path $paths.root 'servers') -TrustedHashes $trustedHashes
        $meta = @{ model_id = $ml.model_id; host = '127.0.0.1'; port_hint = 0; managed_by = 'model.gateway.supervisor'; keep_resident_seconds = $KeepResidentSeconds }
        $res = Invoke-SupervisorEnsureResident -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock `
            -ReqConfig $ml.req_config -ModelMeta $meta -Launcher $launcher `
            -HealthProbe $HealthProbe -StopProbe $StopProbe -SocketOwnerProbe $SocketOwnerProbe -StartTicksProbe $StartTicksProbe -VramProbe $VramProbe `
            -FenceHolder 'model.gateway.supervisor' -FenceTtlSeconds $FenceTtlSeconds -LoadTimeoutSec $LoadTimeoutSec -ForceReload:$forceReload -ResidentInstanceId $reqInstId -InstanceGeneration $reqInstGen `
            -RequireJobCustody:$IsWindows   # i23 MF1+2: custody is FATAL on the Windows default-ON path (no uncustodied publish)
        return $res
    }.GetNewClosure()
    $statusHandler = { param($Request) return (Get-SupervisorResidencyStatus -WarmRegPath $paths.warm_registry -StartTicksProbe $StartTicksProbe -HealthProbe $HealthProbe -KeepResidentSeconds $KeepResidentSeconds) }.GetNewClosure()
    $evictHandler  = {
        param($Request)
        # v0.4 (i21): an optional target_resident_instance_id makes this a TARGET-FENCED stop -- the supervisor
        # itself refuses a stop naming a stale/mismatched instance (red-team blockers 4/8). No target => legacy.
        $p = @{}
        if ($null -ne $Request -and ($Request.PSObject.Properties.Name -contains 'params') -and $null -ne $Request.params) { foreach ($pp in $Request.params.PSObject.Properties) { $p[$pp.Name] = $pp.Value } }
        $tgt = if ($p.ContainsKey('target_resident_instance_id')) { [string]$p['target_resident_instance_id'] } else { $null }
        return (Invoke-SupervisorEvict -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -StopProbe $StopProbe -StartTicksProbe $StartTicksProbe -VramProbe $VramProbe -TargetResidentInstanceId $tgt)
    }.GetNewClosure()
    $reconcileHandler = { param($Request) return (Invoke-SupervisorReconcile -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -StartTicksProbe $StartTicksProbe -SocketOwnerProbe $SocketOwnerProbe -HealthProbe $HealthProbe -StopProbe $StopProbe) }.GetNewClosure()
    $prepareHandler = {
        param($Request)
        $p = @{}
        if ($null -ne $Request -and ($Request.PSObject.Properties.Name -contains 'params') -and $null -ne $Request.params) { foreach ($pp in $Request.params.PSObject.Properties) { $p[$pp.Name] = $pp.Value } }
        $req = if ($p.ContainsKey('required_vram_mib')) { [int]$p['required_vram_mib'] } else { 0 }
        $safety = if ($p.ContainsKey('safety_mib')) { [int]$p['safety_mib'] } else { $VramSafetyMib }
        return (Invoke-SupervisorPrepareGpu -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -RequiredVramMib $req -SafetyMib $safety -StopProbe $StopProbe -StartTicksProbe $StartTicksProbe -VramProbe $VramProbe)
    }.GetNewClosure()
    $handlers = @{ ensure_resident = $ensureHandler; status = $statusHandler; evict = $evictHandler; reconcile = $reconcileHandler; prepare_gpu = $prepareHandler }

    # ---- serve loop ----
    $lastHeartbeat = [DateTime]::UtcNow
    $lastActivity = [DateTime]::UtcNow
    $stopReason = 'unknown'
    try {
        while ($true) {
            if (Test-Path -LiteralPath $paths.stop_sentinel -PathType Leaf) { $stopReason = 'stop_sentinel'; break }
            $poll = Invoke-SupervisorPollOnce -Paths $paths -Handlers $handlers -SupervisorPid $PID -SupervisorGeneration $generation
            if ($poll.count -gt 0) { $lastActivity = [DateTime]::UtcNow; Write-Diag "handled $($poll.count) request(s)" }
            if ($poll.shutdown) { $stopReason = 'shutdown_request'; break }
            $now = [DateTime]::UtcNow
            if (($now - $lastHeartbeat).TotalSeconds -ge $HeartbeatSec) {
                $m = Read-SupervisorManifest $paths.manifest
                if ($null -ne $m) { $mm = ConvertTo-MutableMap $m; $mm['heartbeat_utc'] = ($now.ToString('o')); [void](Write-SupervisorManifest -Path $paths.manifest -Obj $mm) }
                $lastHeartbeat = $now
            }
            if ($IdleShutdownSec -gt 0 -and ($now - $lastActivity).TotalSeconds -ge $IdleShutdownSec) { $stopReason = 'idle_shutdown'; break }
            Start-Sleep -Milliseconds $PollMs
        }
    } finally {
        Write-Diag "supervisor stopping (reason=$stopReason); evicting resident + closing job"
        # graceful: state=STOPPING, evict the resident so no orphan survives, THEN close the job (reaps any remainder)
        try { $m = Read-SupervisorManifest $paths.manifest; if ($null -ne $m) { $mm = ConvertTo-MutableMap $m; $mm['state'] = 'STOPPING'; [void](Write-SupervisorManifest -Path $paths.manifest -Obj $mm) } } catch { }
        try { [void](Invoke-SupervisorEvict -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -StopProbe $StopProbe -StartTicksProbe $StartTicksProbe -VramProbe $VramProbe) } catch { Write-Diag "evict-on-stop error: $($_.Exception.Message)" }
        try { $nRes = Close-AllResidentJobTrees; if ($nRes -gt 0) { Write-Diag "closed $nRes per-resident job tree(s)" } } catch { }   # i23 MF1+2
        try { [void](Close-GatewayJob -Job $job) } catch { }
        Clear-SupervisorManifest $paths.manifest
        try { if (Test-Path -LiteralPath $paths.stop_sentinel) { Remove-Item -LiteralPath $paths.stop_sentinel -Force -ErrorAction SilentlyContinue } } catch { }
        try { [void](Exit-SupervisorSingleton $singleton) } catch { }   # i23 MF3: release the lifetime singleton
        Write-Diag "supervisor stopped pid=$PID"
    }
    Emit 'run' 'ok' ([ordered]@{ ran = $true; stop_reason = $stopReason; supervisor_pid = $PID; job_supported = [bool]$job.supported }) $null
}

# =====================================================================================================
# action dispatch
# =====================================================================================================
try {
    switch ($Action) {

        'run' { Invoke-SupervisorRun; exit 0 }

        'start' {
            $m = Read-SupervisorManifest $paths.manifest
            $live = Test-SupervisorLiveness -Manifest $m -StartTicksProbe $StartTicksProbe
            if ($live.running) { Emit 'start' 'ok' ([ordered]@{ started = $false; already_running = $true; supervisor_pid = $live.pid; root = $paths.root }) $null; exit 0 }
            if ($live.present -and -not $live.alive) { Clear-SupervisorManifest $paths.manifest }   # stale dead manifest
            Initialize-SupervisorDirs -Paths $paths
            $childArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $PSCommandPath,
                '-Action','run','-Registry',$regPath,'-SupervisorRoot',$supRoot,'-WarmRegistryPath',$paths.warm_registry,
                '-PwshPath',$pwshExe,'-PollMs',"$PollMs",'-HeartbeatSec',"$HeartbeatSec",'-IdleShutdownSec',"$IdleShutdownSec",
                '-LoadTimeoutSec',"$LoadTimeoutSec",'-FenceTtlSeconds',"$FenceTtlSeconds",'-KeepResidentSeconds',"$KeepResidentSeconds")
            $launchMode = $null; $childPid = 0
            if ($IsWindows -and -not $NoDetach) {
                # Win32_Process.Create parents to WmiPrvSE -> the supervisor ESCAPES the executor task's job so it
                # survives across per-call invocations (the D-0057 detach mechanism, here for the supervisor itself).
                $cmdLine = ((@($pwshExe) + $childArgs) | ForEach-Object { $s = "$_"; if ($s -match '[\s"]') { '"' + ($s -replace '"','\"') + '"' } else { $s } }) -join ' '
                $wmi = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
                $wrc = if ($null -ne $wmi) { [int]$wmi.ReturnValue } else { -1 }
                $childPid = if ($null -ne $wmi -and $null -ne $wmi.ProcessId) { [int]$wmi.ProcessId } else { 0 }
                if ($wrc -ne 0) { throw [PSCustomObject]@{ code = 'supervisor_start_failed'; message = "Win32_Process.Create rc=$wrc" } }
                $launchMode = 'win32_detached'
            } else {
                $so = Join-Path $paths.root 'run.out.log'; $se = Join-Path $paths.root 'run.err.log'
                $proc = Start-Process -FilePath $pwshExe -ArgumentList $childArgs -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
                $childPid = [int]$proc.Id; $launchMode = 'child_process'
            }
            # wait for the run child to publish a live manifest
            $deadline = (Get-Date).AddSeconds($StartTimeoutSec); $ok = $false; $supPid = 0
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 200
                $mm = Read-SupervisorManifest $paths.manifest
                $ll = Test-SupervisorLiveness -Manifest $mm -StartTicksProbe $StartTicksProbe
                if ($ll.running) { $ok = $true; $supPid = $ll.pid; break }
            }
            if (-not $ok) { throw [PSCustomObject]@{ code = 'supervisor_no_manifest'; message = "supervisor did not become live within $StartTimeoutSec s (launch=$launchMode child_pid=$childPid)" } }
            Emit 'start' 'ok' ([ordered]@{ started = $true; already_running = $false; supervisor_pid = $supPid; launch = $launchMode; root = $paths.root; job_supported = $(if ($mm.job_object) { [bool]$mm.job_object.supported } else { $null }) }) $null
            exit 0
        }

        'stop' {
            $m = Read-SupervisorManifest $paths.manifest
            $live = Test-SupervisorLiveness -Manifest $m -StartTicksProbe $StartTicksProbe
            if (-not $live.present) { Emit 'stop' 'ok' ([ordered]@{ stopped = $false; not_running = $true }) $null; exit 0 }
            $supPid = $live.pid
            $method = 'graceful'
            if ($live.running) {
                # i23 MF4: shutdown is an authenticated admin op -- pass the supervisor's generation (read from the
                # manifest) so the running loop accepts it. The stop-sentinel below remains the belt-and-suspenders.
                $supGen = if ($null -ne $m -and (Has $m 'supervisor_generation')) { [string]$m.supervisor_generation } else { '' }
                $resp = Send-SupervisorRequest -Paths $paths -Op 'shutdown' -ExpectGeneration $supGen -TimeoutMs 5000 -StartTicksProbe $StartTicksProbe
                if (-not $resp.ok) { $warnings.Add("graceful shutdown request not acked: $($resp.error.code)") }
            }
            # also drop the stop sentinel (belt-and-suspenders) so a busy loop still exits
            try { [System.IO.File]::WriteAllText($paths.stop_sentinel, ([DateTime]::UtcNow.ToString('o')), $utf8) } catch { }
            $deadline = (Get-Date).AddSeconds($StopTimeoutSec); $gone = $false
            while ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200; if (-not (Test-SupPidAlive $supPid)) { $gone = $true; break } }
            if (-not $gone -and $supPid -gt 0) {
                $method = 'forced'
                try { if ($IsWindows) { & taskkill /PID $supPid /T /F 2>$null | Out-Null } } catch { }
                try { $pp = Get-Process -Id $supPid -ErrorAction SilentlyContinue; if ($null -ne $pp) { $pp.Kill($true) } } catch { }
                for ($i = 0; $i -lt 30; $i++) { if (-not (Test-SupPidAlive $supPid)) { $gone = $true; break }; Start-Sleep -Milliseconds 100 }
            }
            if ($gone) { Clear-SupervisorManifest $paths.manifest; try { if (Test-Path -LiteralPath $paths.stop_sentinel) { Remove-Item -LiteralPath $paths.stop_sentinel -Force -ErrorAction SilentlyContinue } } catch { } }
            Emit 'stop' $(if ($gone) { 'ok' } else { 'error' }) ([ordered]@{ stopped = $gone; supervisor_pid = $supPid; method = $method }) $(if ($gone) { $null } else { [ordered]@{ code = 'supervisor_stop_failed'; message = "supervisor pid $supPid still alive after $StopTimeoutSec s" } })
            exit 0
        }

        'status' {
            $m = Read-SupervisorManifest $paths.manifest
            $live = Test-SupervisorLiveness -Manifest $m -StartTicksProbe $StartTicksProbe
            $resident = Get-SupervisorResidencyStatus -WarmRegPath $paths.warm_registry -StartTicksProbe $StartTicksProbe -HealthProbe $HealthProbe -KeepResidentSeconds $KeepResidentSeconds
            $res = [ordered]@{
                supervisor = [ordered]@{
                    present = $live.present; running = $live.running; alive = $live.alive; identity_ok = $live.identity_ok; heartbeat_fresh = $live.heartbeat_fresh
                    supervisor_pid = $live.pid; root = $paths.root; control_dir = $paths.control; warm_registry = $paths.warm_registry
                    generation = $(if ($null -ne $m -and (Has $m 'supervisor_generation')) { [string]$m.supervisor_generation } else { $null })
                    job_supported = $(if ($null -ne $m -and (Has $m 'job_object')) { [bool]$m.job_object.supported } else { $null })
                    started_at_utc = $(if ($null -ne $m -and (Has $m 'started_at_utc')) { [string]$m.started_at_utc } else { $null })
                    heartbeat_utc = $(if ($null -ne $m -and (Has $m 'heartbeat_utc')) { [string]$m.heartbeat_utc } else { $null })
                }
                resident = $resident
            }
            Emit 'status' 'ok' $res $null
            exit 0
        }

        'reconcile' {
            $rc = Invoke-SupervisorReconcile -WarmRegPath $paths.warm_registry -LockPath $paths.warm_lock -StartTicksProbe $StartTicksProbe -SocketOwnerProbe $SocketOwnerProbe -HealthProbe $HealthProbe -StopProbe $StopProbe
            Emit 'reconcile' 'ok' ([ordered]@{ reconcile = $rc }) $null
            exit 0
        }

        'ping' {
            $resp = Send-SupervisorRequest -Paths $paths -Op 'ping' -TimeoutMs $RequestTimeoutMs -StartTicksProbe $StartTicksProbe
            if ($resp.ok) { Emit 'ping' 'ok' ([ordered]@{ pong = $true; response = $resp.response }) $null }
            else { Emit 'ping' 'error' ([ordered]@{ pong = $false }) $resp.error }
            exit 0
        }
    }
} catch {
    $ex = $_.Exception; $tgt = $_.TargetObject
    $code = 'supervisor_error'; $msg = "$($ex.Message)"
    if ($null -ne $tgt -and (Has $tgt 'code')) { $code = [string]$tgt.code; if (Has $tgt 'message') { $msg = [string]$tgt.message } }
    Write-Diag "ERROR ($code): $msg"
    Emit $Action 'error' $null ([ordered]@{ code = $code; message = $msg; retryable = $true })
    exit 1
}
