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
# Portable, testable: an atomic O_CREAT|O_EXCL lock file next to the manifest.
#
# i23 supervisor-hardening (red-team blocker 4, must-fix 6): ABANDONMENT-AWARE, never a time-bound steal.
# The record carries pid + the holder's process START-TICKS + a random OWNERSHIP NONCE. A held lock is broken
# ONLY on genuine ABANDONMENT -- the holder pid is dead, OR the pid is alive but its current start-ticks do
# NOT match the recorded ones (PID REUSE == the original holder is gone). A LIVE owner is NEVER stolen on an
# age bound (the old StaleMs>60s steal is removed; -StaleMs is retained for signature compat but unused for a
# live holder). A wedged-but-live holder is recovered by killing the holder (MF8 watchdog), after which its
# pid dies and the lock breaks naturally -- NOT by stealing the lock out from under it.
# Exit-PoolLock is NONCE-CHECKED: it deletes the lock ONLY when the on-disk nonce still matches the one it
# acquired, so a resumed wedged owner cannot delete a REPLACEMENT owner's lock (the split-brain the red-team
# flagged). On Windows the gateway ALSO wraps a real named Mutex (belt-and-suspenders); the file lock is the
# always-on, cross-platform mechanism the tests drive.
# ------------------------------------------------------------------------------------------------
function Test-PidAlive { param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try { $null = Get-Process -Id $ProcessId -ErrorAction Stop; return $true } catch { return $false }
}
# Current start-ticks of a pid (0 = cannot determine). Off-Windows StartTime is still available for our own
# and child pids; 0 degrades to "cannot prove reuse" (we then treat an alive pid as the live holder).
function Get-PidStartTicks { param([int]$ProcessId)
    if ($ProcessId -le 0) { return 0 }
    try { return [long]((Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.Ticks) } catch { return 0 }
}
# Is the recorded lock holder genuinely GONE (abandoned)? dead pid, corrupt record, or pid-reuse.
function Test-PoolLockAbandoned { param([object]$Held)
    if ($null -eq $Held) { return $true }
    $hp = if (Test-HasProp $Held 'pid') { [int]$Held.pid } else { 0 }
    if ($hp -le 0) { return $true }
    if (-not (Test-PidAlive $hp)) { return $true }
    # pid alive: prove it is the SAME process via start-ticks (PID-reuse guard). If the record has no ticks or
    # we cannot read the live ticks, we CANNOT prove reuse -> treat as a live holder (do NOT steal).
    $wantTicks = if (Test-HasProp $Held 'owner_start_ticks') { [long]$Held.owner_start_ticks } else { 0 }
    if ($wantTicks -le 0) { return $false }
    $haveTicks = Get-PidStartTicks $hp
    if ($haveTicks -le 0) { return $false }
    return ([Math]::Abs($haveTicks - $wantTicks) -ge [TimeSpan]::FromSeconds(2).Ticks)   # reused pid -> abandoned
}
function Enter-PoolLock {
    param([string]$LockPath, [int]$TimeoutMs = 8000, [int]$StaleMs = 60000, [int]$OwnerPid = $PID)
    $deadline = (Get-NowUtc).AddMilliseconds($TimeoutMs)
    $nonce = [Guid]::NewGuid().ToString('N')
    $ownerTicks = Get-PidStartTicks $OwnerPid
    while ($true) {
        try {
            $dir = Split-Path -Parent $LockPath
            if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            # atomic create-new: CreateNew throws if it already exists (our O_EXCL)
            $fs = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $rec = ([ordered]@{ pid = $OwnerPid; owner_start_ticks = $ownerTicks; nonce = $nonce; acquired_utc = (ConvertTo-UtcString (Get-NowUtc)) } | ConvertTo-Json -Compress)
                $b = $script:Utf8NoBom.GetBytes($rec); $fs.Write($b, 0, $b.Length)
            } finally { $fs.Dispose() }
            return ([ordered]@{ acquired = $true; path = $LockPath; owner_pid = $OwnerPid; nonce = $nonce })
        } catch {
            # exists -> break ONLY if the holder is genuinely abandoned (dead / pid-reused / corrupt). Never on age.
            $held = Read-PoolManifest $LockPath
            if (Test-PoolLockAbandoned $held) { try { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue } catch { } ; continue }
            if ((Get-NowUtc) -ge $deadline) { return ([ordered]@{ acquired = $false; path = $LockPath; owner_pid = $OwnerPid; reason = 'timeout' }) }
            Start-Sleep -Milliseconds 40
        }
    }
}
# Release. NONCE-CHECKED: only delete the lock file if the on-disk nonce still matches ours. A resumed wedged
# owner whose lock was already broken + re-acquired by a replacement owner will see a DIFFERENT nonce (or none)
# and leave the replacement's lock untouched (no split-brain). A lock acquired by legacy code (no nonce in the
# returned object) falls back to an unconditional delete for back-compat.
function Exit-PoolLock { param([object]$Lock)
    if ($null -eq $Lock -or -not (Test-HasProp $Lock 'path')) { return }
    $path = [string]$Lock.path
    $myNonce = if (Test-HasProp $Lock 'nonce') { [string]$Lock.nonce } else { $null }
    try {
        if ([string]::IsNullOrWhiteSpace($myNonce)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return }
        $held = Read-PoolManifest $path
        $onDisk = if ($null -ne $held -and (Test-HasProp $held 'nonce')) { [string]$held.nonce } else { $null }
        # match -> ours, delete. absent on disk -> legacy/foreign writer, delete to avoid a leak. different -> a
        # replacement owner holds it now; DO NOT delete.
        if ([string]::IsNullOrWhiteSpace($onDisk) -or $onDisk -eq $myNonce) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    } catch { }
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
        return [ordered]@{ decision = $(if ($HasResident) { 'evict_then_grant' } else { 'grant' }); reason = 'vram_unknown'; free_mib = $null; target_mib = $target; headroom_ok = $null; unmanaged_pressure = $false }
    }
    if ($FreeMib -ge $target) { return [ordered]@{ decision = 'grant'; reason = 'headroom_available'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $true; unmanaged_pressure = $false } }
    if ($HasResident)          { return [ordered]@{ decision = 'evict_then_grant'; reason = 'insufficient_headroom_with_resident'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $false; unmanaged_pressure = $false } }
    # i23 MF7 (red-team must-fix 7): headroom is short but there is NO managed target to evict -> the VRAM is
    # held by an UNIDENTIFIED consumer. Flag it (unmanaged_pressure) so the caller reports
    # 'unmanaged_vram_pressure' and NEVER blind-kills a consumer it does not own. decision/reason unchanged.
    return [ordered]@{ decision = 'insufficient'; reason = 'insufficient_headroom_no_resident'; free_mib = [int]$FreeMib; target_mib = $target; headroom_ok = $false; unmanaged_pressure = $true }
}

# ------------------------------------------------------------------------------------------------
# i23 MF7 (red-team must-fix 7): HARD-DEADLINE bounded external probe. Runs an executable with a HARD wall
# deadline; on timeout it KILLS the process tree and returns timed_out=$true (never hangs the caller / the
# pool lock). stdout/stderr are drained async (the child-pipe-deadlock gotcha). Host-agnostic + pure: the
# SEAM is which command; nvidia-smi is one caller. Used to replace every unbounded `& nvidia-smi` in the
# supervisor / gateway / evictor probe paths.
# ------------------------------------------------------------------------------------------------
function Invoke-BoundedCommand {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [int]$DeadlineMs = 4000)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return [ordered]@{ ok = $false; timed_out = $false; exit_code = -1; stdout = $null; stderr = 'no_filepath' } }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in @($Arguments)) { [void]$psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = $null
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $p) { return [ordered]@{ ok = $false; timed_out = $false; exit_code = -1; stdout = $null; stderr = 'start_failed' } }
        $soT = $p.StandardOutput.ReadToEndAsync(); $seT = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit([Math]::Max(1, $DeadlineMs))) {
            try { $p.Kill($true) } catch { try { $p.Kill() } catch { } }
            try { [void]$p.WaitForExit(2000) } catch { }
            return [ordered]@{ ok = $false; timed_out = $true; exit_code = -1; stdout = $null; stderr = 'deadline_exceeded' }
        }
        $out = try { $soT.GetAwaiter().GetResult() } catch { '' }
        $err = try { $seT.GetAwaiter().GetResult() } catch { '' }
        return [ordered]@{ ok = ($p.ExitCode -eq 0); timed_out = $false; exit_code = [int]$p.ExitCode; stdout = $out; stderr = $err }
    } catch { return [ordered]@{ ok = $false; timed_out = $false; exit_code = -1; stdout = $null; stderr = "$($_.Exception.Message)" } }
    finally { if ($null -ne $p) { try { $p.Dispose() } catch { } } }
}
# Resolve a PINNED ABSOLUTE nvidia-smi (never a bare PATH lookup -> no PATH-shim / reparse-point surprise).
# Env override LIFEORCH_NVIDIA_SMI wins (tests / non-standard installs). $null => off-box / not found -> the
# caller degrades to 'unknown' (confirmed:false), never a throw.
function Get-NvidiaSmiPath {
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_NVIDIA_SMI)) { $cands.Add([string]$env:LIFEORCH_NVIDIA_SMI) }
    if ($IsWindows) {
        $sysRoot = if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) { [string]$env:SystemRoot } else { 'C:\Windows' }
        $cands.Add((Join-Path $sysRoot 'System32\nvidia-smi.exe'))
        if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $cands.Add((Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')) }
    }
    foreach ($c in $cands) { if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c } }
    return $null
}
# Bounded + pinned nvidia-smi free-VRAM probe. Returns an int (MiB) or $null (unknown: absent / timeout / parse
# fail). This is the ONLY real-VRAM entry the hardened supervisor uses.
function Get-GpuFreeMibBounded {
    param([int]$DeadlineMs = 4000, [string]$SmiPath = $null)
    $smi = if (-not [string]::IsNullOrWhiteSpace($SmiPath)) { $SmiPath } else { Get-NvidiaSmiPath }
    if ([string]::IsNullOrWhiteSpace($smi) -or -not (Test-Path -LiteralPath $smi -PathType Leaf)) { return $null }
    $r = Invoke-BoundedCommand -FilePath $smi -Arguments @('--query-gpu=memory.free','--format=csv,noheader,nounits') -DeadlineMs $DeadlineMs
    if (-not $r.ok -or $r.timed_out -or [string]::IsNullOrWhiteSpace([string]$r.stdout)) { return $null }
    $line = (([string]$r.stdout) -split "`n" | Where-Object { "$_".Trim() -ne '' } | Select-Object -First 1)
    $n = 0; if ($null -ne $line -and [int]::TryParse((("$line").Trim()), [ref]$n)) { return $n }
    return $null
}

# ------------------------------------------------------------------------------------------------
# i23 MF10 (red-team blocker 7, must-fix 10): REAL content verification + trust-root path hardening.
# The v0.4 identity used an engine hash cached by path+size+mtime and a model sha COPIED from the mutable
# models.json -- neither proves the launched BYTES. These primitives verify a file's ACTUAL sha256 against a
# TRUSTED expected hash immediately before launch, and reject REPARSE POINTS (symlink/junction) on trust roots
# so a redirected path cannot smuggle different bytes past the check. No THEATER: a hash is trusted only
# because the CALLER supplies it from a trusted manifest, never because it sits in models.json.
# ------------------------------------------------------------------------------------------------
function Get-FileSha256Hex {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = $null
    try { $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
          return ([System.BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-','').ToLowerInvariant() }
    catch { return $null } finally { if ($null -ne $fs) { $fs.Dispose() }; $sha.Dispose() }
}
# Is a path (or any ancestor up to the drive/root) a REPARSE POINT? Off a trust root that means a redirected
# location -> reject. Returns $true if a reparse point is found on the chain (so the caller refuses).
function Test-PathReparsePoint {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $cur = [System.IO.Path]::GetFullPath($Path)
        while (-not [string]::IsNullOrWhiteSpace($cur)) {
            if (Test-Path -LiteralPath $cur) {
                $attr = [System.IO.File]::GetAttributes($cur)
                if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint) { return $true }
            }
            $parent = [System.IO.Path]::GetDirectoryName($cur)
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
            $cur = $parent
        }
        return $false
    } catch { return $true }   # cannot prove it is clean -> treat as suspect (fail-closed)
}
# Verify a file's ACTUAL content hash against a TRUSTED expected hash. Returns an ordered result:
# { ok; reason; actual }. reason: match | hash_mismatch | file_missing | reparse_point | no_expected.
function Test-ContentHashTrusted {
    param([Parameter(Mandatory)][string]$Path, [string]$ExpectedSha256, [switch]$RejectReparse)
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) { return [ordered]@{ ok = $false; reason = 'no_expected'; actual = $null } }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{ ok = $false; reason = 'file_missing'; actual = $null } }
    if ($RejectReparse -and (Test-PathReparsePoint $Path)) { return [ordered]@{ ok = $false; reason = 'reparse_point'; actual = $null } }
    $actual = Get-FileSha256Hex $Path
    if ([string]::IsNullOrWhiteSpace($actual)) { return [ordered]@{ ok = $false; reason = 'unreadable'; actual = $null } }
    $match = ($actual.ToLowerInvariant() -eq ([string]$ExpectedSha256).ToLowerInvariant())
    return [ordered]@{ ok = $match; reason = $(if ($match) { 'match' } else { 'hash_mismatch' }); actual = $actual }
}

Export-ModuleMember -Function `
    Invoke-BoundedCommand, Get-NvidiaSmiPath, Get-GpuFreeMibBounded, `
    Get-FileSha256Hex, Test-PathReparsePoint, Test-ContentHashTrusted, `
    Test-HasProp, Get-Sha256Hex, Get-Sha256OfString, Get-NowUtc, ConvertTo-UtcString, ConvertFrom-UtcString, `
    Read-PoolManifest, Write-PoolManifest, Clear-PoolManifest, ConvertTo-MutableMap, `
    Test-PidAlive, Get-PidStartTicks, Test-PoolLockAbandoned, Enter-PoolLock, Exit-PoolLock, `
    Get-ResidentConfig, Get-ResidentConfigHash, New-InstanceGeneration, `
    Get-ConfigField, Test-CanServe, `
    Get-ManifestFence, Test-FenceExpired, Grant-Fence, Test-FenceCurrent, Update-FenceRenewal, Set-ManifestCas, `
    Test-GenerationMatch, `
    Test-LegalTransition, Get-ManifestState, `
    Test-ResidentIdentity, Test-SocketOwner, `
    Get-GpuHandoffPlan `
    -Variable WARM_SCHEMA, POOL_STATES
