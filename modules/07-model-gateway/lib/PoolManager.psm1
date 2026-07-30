#requires -Version 7.0
# =====================================================================================================
# PoolManager.psm1 -- model.gateway #7 warm-pool Stage-1.1 hardening core (mechanism C, D-0067).
#
# This module is the INTEGRITY CORE of the named warm pool. It is deliberately free of any live model /
# GPU / Windows dependency so every invariant is unit-testable OFF-MACHINE (cloud pwsh 7.4.6) and,
# unchanged, live via the executor. Every host-specific probe (VRAM, socket owner, Job Object) enters
# through an INJECTABLE SEAM so tests substitute a deterministic stub and the real gateway wires the
# Windows/nvidia-smi implementation; a seam that is unavailable off-Windows degrades to 'unknown' and
# NEVER throws.
#
# Closes WARM_POOL_DESIGN section 10:
#   #1  fencing token + CAS + short renewable TTL + generation-mismatch rejection
#   #3  crash-atomic state machine EMPTY->STOPPING->EMPTY_CONFIRMED->STARTING->RESIDENT + reconcile
#       under a machine-global lock
#   #4  verified-generation identity (nonce/port/pid/creation-time/exe-hash) + socket-owner gate
#   #6  split resident_config_hash (deterministic; hashes CONTENTS) vs instance_generation (per-launch nonce)
#   #7/#8/#9  CanServe(resident, request): exact on semantic-identity, '>=' on capacity
#   #2/#15  GPU-handoff eviction planning (target headroom + async-confirm interval) -- pure planner here
#
# Manifest schema: lifeorch.model_gateway.warm/0.3 (adds state / instance_generation / resident_config_hash
# / fence block; keeps residency_key_sha = resident_config_hash and ngl/ctx for backward-compatible readers).
# ASCII-only (Windows PowerShell 5.1 / dev.ship AST + non-ASCII grep). UTF-8 no BOM.
# =====================================================================================================
Set-StrictMode -Version Latest

$script:WARM_SCHEMA   = 'lifeorch.model_gateway.warm/0.3'
$script:POOL_STATES   = @('EMPTY','STOPPING','EMPTY_CONFIRMED','STARTING','RESIDENT')
$script:Utf8NoBom     = [System.Text.UTF8Encoding]::new($false)

# ------------------------------------------------------------------------------------------------
# small helpers
# ------------------------------------------------------------------------------------------------
function Test-HasProp { param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Name) }
    return ($Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name))
}
function Get-Sha256Hex { param([byte[]]$Bytes)
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Get-Sha256OfString { param([string]$Text)
    return (Get-Sha256Hex ($script:Utf8NoBom.GetBytes([string]$Text)))
}
function Get-NowUtc { return [DateTime]::UtcNow }
function ConvertTo-UtcString { param([DateTime]$T) return $T.ToString('o') }
function ConvertFrom-UtcString { param([string]$S)
    if ([string]::IsNullOrWhiteSpace($S)) { return $null }
    try { return [DateTime]::Parse($S, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { return $null }
}

# ------------------------------------------------------------------------------------------------
# atomic manifest read / write (write tmp + Move -Force == crash-atomic replace, finding #3)
# ------------------------------------------------------------------------------------------------
function Read-PoolManifest { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
function Write-PoolManifest { param([string]$Path, [object]$Obj)
    try {
        $dir = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Path.tmp-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        [System.IO.File]::WriteAllText($tmp, ($Obj | ConvertTo-Json -Depth 12), $script:Utf8NoBom)
        [System.IO.File]::Move($tmp, $Path, $true)   # atomic replace: the manifest is never seen half-written
        return $true
    } catch { return $false }
}
function Clear-PoolManifest { param([string]$Path)
    try { if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue } } catch { }
}
# Convert a parsed manifest (PSCustomObject from JSON) OR an [ordered]/hashtable config to a mutable
# ordered dictionary for CAS updates. Handles IDictionary explicitly (PSObject.Properties on a dictionary
# enumerates CLR members, not entries -- a subtle trap).
function ConvertTo-MutableMap { param([object]$Obj)
    $map = [ordered]@{}
    if ($null -eq $Obj) { return $map }
    if ($Obj -is [System.Collections.IDictionary]) { foreach ($k in $Obj.Keys) { $map[[string]$k] = $Obj[$k] }; return $map }
    if ($Obj.PSObject) { foreach ($p in $Obj.PSObject.Properties) { $map[$p.Name] = $p.Value } }
    return $map
}

# ------------------------------------------------------------------------------------------------
# machine-global lock (finding #3: reconcile / residency mutation under a machine-global mutex).
# Portable, testable: an atomic O_CREAT|O_EXCL lock file next to the manifest, holder pid + stamp, with
# stale-breaking (dead holder pid OR older than -StaleMs). On Windows the gateway ALSO wraps a real named
# Mutex (belt-and-suspenders) but the file lock is the always-on, cross-platform mechanism the tests drive.
# ------------------------------------------------------------------------------------------------
function Test-PidAlive { param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try { $null = Get-Process -Id $ProcessId -ErrorAction Stop; return $true } catch { return $false }
}
function Enter-PoolLock {
    param([string]$LockPath, [int]$TimeoutMs = 8000, [int]$StaleMs = 60000, [int]$OwnerPid = $PID)
    $deadline = (Get-NowUtc).AddMilliseconds($TimeoutMs)
    while ($true) {
        try {
            $dir = Split-Path -Parent $LockPath
            if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            # atomic create-new: CreateNew throws if it already exists (our O_EXCL)
            $fs = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $rec = ([ordered]@{ pid = $OwnerPid; acquired_utc = (ConvertTo-UtcString (Get-NowUtc)) } | ConvertTo-Json -Compress)
                $b = $script:Utf8NoBom.GetBytes($rec); $fs.Write($b, 0, $b.Length)
            } finally { $fs.Dispose() }
            return ([ordered]@{ acquired = $true; path = $LockPath; owner_pid = $OwnerPid })
        } catch {
            # exists -> maybe stale (dead holder or too old); break it if so
            $held = Read-PoolManifest $LockPath
            $brk = $false
            if ($null -eq $held) { $brk = $true }
            else {
                $hp = if (Test-HasProp $held 'pid') { [int]$held.pid } else { 0 }
                $ha = if (Test-HasProp $held 'acquired_utc') { ConvertFrom-UtcString ([string]$held.acquired_utc) } else { $null }
                if ($hp -gt 0 -and -not (Test-PidAlive $hp)) { $brk = $true }
                elseif ($null -ne $ha -and ((Get-NowUtc) - $ha).TotalMilliseconds -gt $StaleMs) { $brk = $true }
            }
            if ($brk) { try { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue } catch { } ; continue }
            if ((Get-NowUtc) -ge $deadline) { return ([ordered]@{ acquired = $false; path = $LockPath; owner_pid = $OwnerPid; reason = 'timeout' }) }
            Start-Sleep -Milliseconds 40
        }
    }
}
function Exit-PoolLock { param([object]$Lock)
    if ($null -ne $Lock -and (Test-HasProp $Lock 'path')) { try { Remove-Item -LiteralPath ([string]$Lock.path) -Force -ErrorAction SilentlyContinue } catch { } }
}

# ------------------------------------------------------------------------------------------------
# #6 config-hash / instance-generation split.
# resident_config_hash = deterministic sha256 over the IMMUTABLE launch config that determines what is
# GPU-resident. It hashes CONTENTS (model sha256, engine exe hash, mmproj sha256), NEVER paths, and NEVER
# the per-launch generation nonce or any request-scoped sampler field. instance_generation is a separate
# per-launch nonce used only for fencing/identity.
# ------------------------------------------------------------------------------------------------
function Get-ResidentConfig {
    param($M, $Reg, [int]$Ngl, [int]$Ctx, [bool]$NoThink, [string]$Ctk, [string]$Ctv, [bool]$Flash, [int]$Np,
          [string]$EngineExeHash)
    $p = if (Test-HasProp $M 'params') { $M.params } else { $null }
    $sha   = if ($null -ne $p -and (Test-HasProp $p 'sha256'))        { [string]$p.sha256 }        else { $null }
    $sz    = if ($null -ne $p -and (Test-HasProp $p 'size_bytes'))    { [long]$p.size_bytes }      else { $null }
    $mmsha = if ($null -ne $p -and (Test-HasProp $p 'mmproj_sha256')) { [string]$p.mmproj_sha256 } else { $null }
    $ep = if (Test-HasProp $M 'engine_path') { [string]$M.engine_path } elseif ((Test-HasProp $Reg 'engines') -and (Test-HasProp $Reg.engines 'llama-server')) { [string]$Reg.engines.'llama-server' } else { $null }
    $eb = if (Test-HasProp $Reg 'engine_build') { [string]$Reg.engine_build } else { $null }
    $tmpl = if (Test-HasProp $M 'chat_template') { [string]$M.chat_template } else { $null }
    $tmplArgs = if (Test-HasProp $M 'chat_template_args') { [string]($M.chat_template_args | ConvertTo-Json -Depth 6 -Compress) } else { $null }
    # NOTE: engine_path is retained for launch, but is NOT in the semantic-identity set (exe HASH is; paths move).
    return [ordered]@{
        model_id     = [string]$M.model_id
        model_sha256 = $sha
        model_size_bytes = $sz
        mmproj_sha256 = $mmsha
        engine_build = $eb
        engine_path  = $ep
        engine_exe_hash = $EngineExeHash
        gpu_layers   = $Ngl
        context      = $Ctx
        no_think     = [bool]$NoThink
        cache_type_k = $Ctk
        cache_type_v = $Ctv
        flash_attn   = [bool]$Flash
        parallel     = $Np
        chat_template = $tmpl
        chat_template_args = $tmplArgs
    }
}
# The deterministic fingerprint. Excludes engine_path (a moving path; exe hash is the identity) so a
# relocated-but-identical engine still reuses; excludes generation + samplers entirely.
function Get-ResidentConfigHash { param($Config)
    $c = ConvertTo-MutableMap $Config
    if ($c.Contains('engine_path')) { $c.Remove('engine_path') }   # hash CONTENTS (exe hash), not the path
    return (Get-Sha256OfString (($c | ConvertTo-Json -Depth 8 -Compress)))
}
function New-InstanceGeneration { return ([Guid]::NewGuid().ToString('N')) }   # per-launch nonce (fencing identity)

# ------------------------------------------------------------------------------------------------
# #7/#8/#9 CanServe(resident, request): exact on semantic-identity, '>=' on capacity. Reload ONLY when
# the resident cannot correctly serve the requested launch config. Sampler/request-scoped fields never
# enter this decision (they are applied per-request). A larger resident serves a smaller request:
# a 32K resident serves 16K; parallel N>=M. Identity fields (model, exe, KV type, flash, template, mmproj,
# no_think) must match exactly -- they change what is loaded / how KV is stored.
# ------------------------------------------------------------------------------------------------
$script:CANSERVE_EXACT    = @('model_id','model_sha256','engine_build','engine_exe_hash','no_think','cache_type_k','cache_type_v','flash_attn','chat_template','chat_template_args','mmproj_sha256')
$script:CANSERVE_CAPACITY = @('context','parallel')   # resident value must be >= requested value
function Get-ConfigField { param($Cfg, [string]$Name)
    if ($null -eq $Cfg) { return $null }
    if (Test-HasProp $Cfg $Name) { return $Cfg.$Name }
    if ($Cfg -is [System.Collections.IDictionary] -and $Cfg.Contains($Name)) { return $Cfg[$Name] }
    return $null
}
function Test-CanServe { param($Resident, $Request)
    $mismatches = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Resident -or $null -eq $Request) { return [ordered]@{ can_serve = $false; reason = 'null_config'; mismatches = @('null_config') } }
    foreach ($f in $script:CANSERVE_EXACT) {
        $rv = Get-ConfigField $Resident $f; $qv = Get-ConfigField $Request $f
        $rs = if ($null -eq $rv) { '' } else { [string]$rv }
        $qs = if ($null -eq $qv) { '' } else { [string]$qv }
        if ($rs -ne $qs) { $mismatches.Add("identity:${f}(resident='$rs' request='$qs')") }
    }
    foreach ($f in $script:CANSERVE_CAPACITY) {
        $rv = Get-ConfigField $Resident $f; $qv = Get-ConfigField $Request $f
        $rn = 0L; $qn = 0L
        [void][long]::TryParse(("$rv"), [ref]$rn); [void][long]::TryParse(("$qv"), [ref]$qn)
        if ($rn -lt $qn) { $mismatches.Add("capacity:${f}(resident=$rn < request=$qn)") }
    }
    $ok = ($mismatches.Count -eq 0)
    return [ordered]@{ can_serve = $ok; reason = $(if ($ok) { 'exact_or_superset' } else { 'cannot_serve' }); mismatches = $mismatches.ToArray() }
}

# ------------------------------------------------------------------------------------------------
# #1 fencing: monotonic token + CAS + short renewable TTL. Authority == (I hold the CURRENT on-disk fence)
# AND (the fence has not expired). A holder whose renewal lapses is superseded by the next acquirer (fence
# bumps); a lapsed holder that returns and tries to mutate sees a higher fence and ABORTS (lost authority).
# All fence ops run INSIDE Enter-PoolLock so the read-modify-write is a true CAS (no lost updates).
# ------------------------------------------------------------------------------------------------
function Get-ManifestFence { param($Reg)
    if ($null -ne $Reg -and (Test-HasProp $Reg 'fence')) { try { return [long]$Reg.fence } catch { return 0 } }
    return 0
}
function Test-FenceExpired { param($Reg, [DateTime]$Now = (Get-NowUtc))
    if ($null -eq $Reg -or -not (Test-HasProp $Reg 'fence_expires_utc')) { return $true }
    $exp = ConvertFrom-UtcString ([string]$Reg.fence_expires_utc)
    if ($null -eq $exp) { return $true }
    return ($Now -ge $exp)
}
# Acquire authority: bump the on-disk fence, become holder, set the TTL. Returns the new fence token.
# Refuses (returns $null) if a DIFFERENT holder's fence is still live (not expired) -- unless -Steal.
function Grant-Fence {
    param([string]$Path, [string]$Holder, [int]$TtlSeconds = 120, [switch]$Steal)
    $reg = Read-PoolManifest $Path
    $cur = Get-ManifestFence $reg
    if ($null -ne $reg -and (Test-HasProp $reg 'fence_holder')) {
        $curHolder = [string]$reg.fence_holder
        $live = -not (Test-FenceExpired $reg)
        if ($live -and $curHolder -ne $Holder -and -not $Steal) { return $null }  # another live owner -> do not co-own
    }
    $now = Get-NowUtc
    $newFence = $cur + 1
    $map = ConvertTo-MutableMap $reg
    $map['fence']            = $newFence
    $map['fence_holder']     = $Holder
    $map['fence_ttl_seconds']= $TtlSeconds
    $map['fence_acquired_utc'] = (ConvertTo-UtcString $now)
    $map['fence_renewed_utc']  = (ConvertTo-UtcString $now)
    $map['fence_expires_utc']  = (ConvertTo-UtcString ($now.AddSeconds($TtlSeconds)))
    if (-not $map.Contains('state')) { $map['state'] = 'EMPTY' }
    [void](Write-PoolManifest $Path $map)
    return $newFence
}
# Do I still hold authority? (current on-disk fence == mine AND not expired)
function Test-FenceCurrent { param([string]$Path, [long]$Fence, [DateTime]$Now = (Get-NowUtc))
    $reg = Read-PoolManifest $Path
    if ($null -eq $reg) { return $false }
    if ((Get-ManifestFence $reg) -ne $Fence) { return $false }   # superseded
    if (Test-FenceExpired $reg $Now) { return $false }           # lapsed
    return $true
}
# Renew my TTL (only if I still hold the current fence). Returns $true on renew.
function Update-FenceRenewal { param([string]$Path, [long]$Fence, [int]$TtlSeconds = 120)
    $reg = Read-PoolManifest $Path
    if ($null -eq $reg -or (Get-ManifestFence $reg) -ne $Fence) { return $false }
    $now = Get-NowUtc
    $map = ConvertTo-MutableMap $reg
    $map['fence_renewed_utc'] = (ConvertTo-UtcString $now)
    $map['fence_expires_utc'] = (ConvertTo-UtcString ($now.AddSeconds($TtlSeconds)))
    [void](Write-PoolManifest $Path $map)
    return $true
}
# CAS a set of field updates iff I still hold the current fence. Returns $true on success, $false if superseded.
function Set-ManifestCas { param([string]$Path, [long]$Fence, [hashtable]$Updates)
    $reg = Read-PoolManifest $Path
    if ($null -eq $reg -or (Get-ManifestFence $reg) -ne $Fence) { return $false }
    $map = ConvertTo-MutableMap $reg
    foreach ($k in $Updates.Keys) { $map[$k] = $Updates[$k] }
    return (Write-PoolManifest $Path $map)
}

# ------------------------------------------------------------------------------------------------
# #1 generation-mismatch rejection for inference. A caller that expects to run against a specific resident
# passes its instance_generation (and/or fence). If the live resident's identity does not match, the call
# is REJECTED before any completion is issued (no wrong-generation call ever lands).
# ------------------------------------------------------------------------------------------------
function Test-GenerationMatch {
    param($Reg, [string]$ExpectGeneration, [long]$ExpectFence = -1)
    $res = [ordered]@{ match = $true; reason = 'ok'; resident_generation = $null; resident_fence = $null }
    if ($null -eq $Reg) { $res.match = $false; $res.reason = 'no_resident'; return $res }
    $res.resident_generation = if (Test-HasProp $Reg 'instance_generation') { [string]$Reg.instance_generation } else { $null }
    $res.resident_fence = Get-ManifestFence $Reg
    if (-not [string]::IsNullOrWhiteSpace($ExpectGeneration)) {
        if ([string]$res.resident_generation -ne $ExpectGeneration) { $res.match = $false; $res.reason = 'generation_mismatch' }
    }
    if ($ExpectFence -ge 0 -and $res.match) {
        if ([long]$res.resident_fence -ne $ExpectFence) { $res.match = $false; $res.reason = 'fence_mismatch' }
    }
    return $res
}

# ------------------------------------------------------------------------------------------------
# #3 state machine transition validation. Legal edges only; the manifest is driven via atomic replace.
# ------------------------------------------------------------------------------------------------
$script:LEGAL_TRANSITIONS = @{
    'EMPTY'           = @('STARTING','STOPPING')                  # STOPPING allowed to reconcile a stale claim
    'STARTING'        = @('RESIDENT','STOPPING','EMPTY')          # failed start -> back to EMPTY/STOPPING
    'RESIDENT'        = @('STOPPING','STARTING')                  # STARTING == a same-lock swap
    'STOPPING'        = @('EMPTY_CONFIRMED','RESIDENT')           # RESIDENT if a stop is aborted
    'EMPTY_CONFIRMED' = @('EMPTY','STARTING')
}
function Test-LegalTransition { param([string]$From, [string]$To)
    if ($script:POOL_STATES -notcontains $To) { return $false }
    if ([string]::IsNullOrWhiteSpace($From)) { return ($To -eq 'EMPTY' -or $To -eq 'STARTING' -or $To -eq 'STOPPING') }
    if (-not $script:LEGAL_TRANSITIONS.ContainsKey($From)) { return $false }
    return ($script:LEGAL_TRANSITIONS[$From] -contains $To)
}
function Get-ManifestState { param($Reg)
    if ($null -ne $Reg -and (Test-HasProp $Reg 'state')) { return [string]$Reg.state } return 'EMPTY'
}

# ------------------------------------------------------------------------------------------------
# #4 verified-generation identity. The resident is proven by pid + creation-time + exe hash + the
# LISTENING SOCKET OWNER, not by a /v1/models alias. The socket-owner probe is a SEAM: the gateway wires
# Get-NetTCPConnection (Windows); off-Windows it returns 'unknown' and publish proceeds advisory-only.
# ------------------------------------------------------------------------------------------------
function Test-ResidentIdentity {
    param($Reg, [scriptblock]$StartTicksProbe = $null)
    $res = [ordered]@{ alive = $false; identity_ok = $false }
    if ($null -eq $Reg -or -not (Test-HasProp $Reg 'pid')) { return $res }
    $procId = [int]$Reg.pid
    $proc = $null
    try { $proc = Get-Process -Id $procId -ErrorAction Stop } catch { return $res }
    $res.alive = $true
    try {
        $wantTicks = if (Test-HasProp $Reg 'start_ticks') { [long]$Reg.start_ticks } else { 0 }
        if ($wantTicks -gt 0) {
            $haveTicks = if ($null -ne $StartTicksProbe) { [long](& $StartTicksProbe $procId) } else { [long]$proc.StartTime.Ticks }
            $res.identity_ok = ([Math]::Abs($haveTicks - $wantTicks) -lt [TimeSpan]::FromSeconds(2).Ticks)
        } else { $res.identity_ok = $true }
    } catch { $res.identity_ok = $false }
    return $res
}
# Verify the listening socket is owned by our launched pid. Returns $true/$false/$null (null = undeterminable
# -> advisory only, never a hard failure off-Windows). $SocketOwnerProbe is a seam: {param($port) -> pid|$null}.
function Test-SocketOwner {
    param([int]$Port, [int]$ExpectedPid, [scriptblock]$SocketOwnerProbe = $null)
    if ($Port -le 0 -or $ExpectedPid -le 0) { return $null }
    if ($null -eq $SocketOwnerProbe) { return $null }
    $owner = $null
    try { $owner = & $SocketOwnerProbe $Port } catch { return $null }
    if ($null -eq $owner) { return $null }
    return ([int]$owner -eq [int]$ExpectedPid)
}

# ------------------------------------------------------------------------------------------------
# #2/#15 GPU-handoff eviction PLANNER (pure). Given the free VRAM and the resident's footprint, decide
# whether a handoff to a consumer needing -RequiredMib can proceed, must evict first, or is impossible.
# Target headroom = required + safety margin; the caller confirms recovery over an async interval (WDDM).
# VRAM is a seam ($FreeMib may be $null off-box -> 'unknown', a non-fatal, evict-to-be-safe plan).
# ------------------------------------------------------------------------------------------------
function Get-GpuHandoffPlan {
    param([Nullable[int]]$FreeMib, [int]$RequiredMib, [bool]$HasResident, [int]$SafetyMib = 512)
    $target = $RequiredMib + $SafetyMib
    if ($null -eq $FreeMib) {
        # cannot measure VRAM (off-box / nvidia-smi absent): if a resident holds the GPU, evict to be safe.
        return [ordered]@{ decision = $(if ($HasResident) { 'evict_then_grant' } else { 'grant' }); reason = 'vram_unknown'; free_mib = $null; target_mib = $target; headroom_ok = $null }
    }
    if ($FreeMib -ge $target) { return [ordered]@{ decision = 'grant'; reason = 'headroom_available'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $true } }
    if ($HasResident)          { return [ordered]@{ decision = 'evict_then_grant'; reason = 'insufficient_headroom_with_resident'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $false } }
    return [ordered]@{ decision = 'insufficient'; reason = 'insufficient_headroom_no_resident'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $false }
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Sha256Hex, Get-Sha256OfString, Get-NowUtc, ConvertTo-UtcString, ConvertFrom-UtcString, `
    Read-PoolManifest, Write-PoolManifest, Clear-PoolManifest, ConvertTo-MutableMap, `
    Test-PidAlive, Enter-PoolLock, Exit-PoolLock, `
    Get-ResidentConfig, Get-ResidentConfigHash, New-InstanceGeneration, `
    Get-ConfigField, Test-CanServe, `
    Get-ManifestFence, Test-FenceExpired, Grant-Fence, Test-FenceCurrent, Update-FenceRenewal, Set-ManifestCas, `
    Test-GenerationMatch, `
    Test-LegalTransition, Get-ManifestState, `
    Test-ResidentIdentity, Test-SocketOwner, `
    Get-GpuHandoffPlan `
    -Variable WARM_SCHEMA, POOL_STATES
