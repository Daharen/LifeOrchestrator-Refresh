#requires -Version 7.0
<#
.SYNOPSIS
  res.lease -- a filesystem lease/lock so N processes on this one box arbitrate contended resources
  (Life Orchestrator, contract v0.2). The multi-instance coordination primitive (D-0050/D-0051).
.DESCRIPTION
  A generic named LEASE with a TTL. One action per invocation:
    - acquire : reserve a resource. Atomic (File CreateNew = open(O_CREAT|O_EXCL)/CREATE_NEW, atomic-fail-if-
                exists on BOTH Linux and Windows). Returns {acquired, lease_id, expires_at_utc}. If the resource
                is already held live, returns acquired:false + held_by (a NORMAL outcome, not an error). An
                EXPIRED lease is reclaimed (race-safe: an atomic source-rename CAS -- exactly one reclaimer
                wins). -WaitSeconds N blocks (polls) up to N seconds; 0 = try once. Re-acquiring a live lease
                you already hold (same holder) re-attaches to your lease_id (already_held:true).
    - release : drop a lease you hold. Requires the lease_id (or a matching holder). A wrong lease_id is
                refused (reason:lease_mismatch) so a slow holder can never release a reclaimed lease.
    - renew   : extend expires_at by ttl_seconds (requires the lease_id). A lost lease -> renewed:false.
    - status  : report {exists, held, stale, holder, lease_id, expires_at_utc, seconds_remaining} for one resource.
    - list    : report every lease in the lease dir.
    - check   : (v0.2) validate a fencing token + report {fencing_token, lease_kind, revocable, revoked_by,
                token_current, fence_status} for one resource -- the surface a holder polls to learn it has
                been FENCED OUT or that a residency_pin has been REVOKED.

  CONVENTIONAL RESOURCE NAMES (any string works; these are the documented ones):
    gpu          -- the single GPU / model-server / diffusers-pipeline lease (model modules are parallel_safe:false).
    git          -- the git index/commit lock (dev.ship + any git write).
    doc:<path>   -- doc-ownership for a shared core-doc edit (e.g. doc:CURRENT_STATE.md).

  v0.2 ADDITIVE, DEFAULT-OFF surface (an acquire that supplies NONE of the new inputs behaves byte-identically
  to v0.1 -- same result fields, same values, same lease semantics). The new capabilities:
    - Monotonic per-resource FENCING TOKEN (finding 1): minted on every fresh grant, persisted in a durable
      sibling <resource>.fence counter (survives lease-file deletion on release), returned on acquire/renew/
      status/check when the fencing surface is engaged. -FencingToken <n> is a CAS guard on renew/release/check
      (reason:fence_stale when the caller's token is not current) -- a superseded holder is FENCED OUT.
    - Two LEASE KINDS (finding 13): -Kind exec|residency_pin (default exec = today's short execution/transition
      lease). residency_pin = the revocable right to STAY resident between exec ops; a higher -Priority acquire
      REVOKES a lower-priority pin (writes revoked_by + the new holder's fencing_token into it) so the pinned
      holder learns on its next renew/check that it has LOST AUTHORITY. A pin is ALWAYS revocable (STOP otherwise).
    - PREPARED / evict-before-grant handoff (findings 2/15): -RequiredVramMiB <n> [-Priority <n>] drives an
      AcquirePreparedGpu-style variant that detects an incompatible/lower-priority resident pin, signals the
      revocation, and grants ONLY AFTER a PLUGGABLE evictor seam confirms headroom (target-headroom invariant +
      a WDDM-async confirmation interval). res.lease stays PURE (no nvidia-smi, no server kill) -- a MOCK evictor
      ships for tests; the REAL PoolManager evictor is the R1b integration point (-EvictorMode command).
    - LOCK-ORDER-INVERSION rejection (finding 14): canonical rank gpu -> git -> doc:<path>. Acquiring a
      cheaper/later-ranked resource while THIS holder already holds an earlier-ranked one (e.g. holding gpu,
      block-acquiring git) is rejected fail-closed (lock_order_violation); -AllowLockOrder -LockOrderReason
      overrides with a recorded reason. Build-then-verify: git for the commit, RELEASE git, then gpu to verify.

  DETERMINISTIC + a tool, not a model: confidence:null, empty model_provenance, NOT a review-queue producer.
  Pure PowerShell + .NET -- no external binary / Python / model / models.json change. parallel_safe:TRUE (it is
  DESIGNED for concurrent invocation; concurrent ops on the same resource are exactly what the atomic primitive
  serializes). batch:false, streaming:false. Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics
  to stderr; writes reslease.json/reslease.md. Exits 0 whenever a valid envelope is produced.

  Leases live in a SHARED dir every process resolves identically: -LeaseDir, else $env:LIFEORCH_LEASE_DIR, else
  $PSScriptRoot/runtime/leases. The holder identity is -Holder, else $env:LIFEORCH_INSTANCE, else <host>:<pid>:<guid8>;
  set a STABLE holder per instance so re-attach + release-by-holder work.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -Holder worker-A -TtlSeconds 300
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action release -Resource gpu -LeaseId <id>
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -Kind residency_pin -Priority 1 -Holder pinner
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -RequiredVramMiB 6700 -Priority 5 -EvictorMode mock -MockEvictorResult needs_evict
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action check -Resource gpu -FencingToken 3
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action list
#>
[CmdletBinding()]
param(
    [string]$Action,
    [string]$Resource,
    [string]$Holder,
    [int]$TtlSeconds = 120,
    [double]$WaitSeconds = 0,
    [string]$LeaseId,
    [string]$Note,
    # ---- v0.2 additive surface (all default-off; a plain acquire supplies NONE of these) ----
    [string]$Kind = 'exec',                 # exec (default, today's behavior) | residency_pin (finding 13)
    [int]$Priority = 0,                     # higher wins; a higher-priority acquire revokes a lower-priority pin
    [bool]$Revocable = $true,               # a residency_pin is ALWAYS revocable (non-revocable pin = STOP)
    [long]$FencingToken = -1,               # renew/release/check CAS guard (-1 = not supplied)
    [int]$RequiredVramMiB = -1,             # prepared / evict-before-grant handoff (>=0 engages it; -1 = not supplied)
    [int]$TargetHeadroomMiB = 512,          # extra free headroom the evictor seam must confirm beyond RequiredVramMiB
    [string]$EvictorMode = 'none',          # none | mock | command  (the pluggable evictor seam; R1b ships the real one)
    [string]$MockEvictorResult = 'confirm', # mock evictor: confirm | needs_evict | timeout
    [int]$MockFreeVramMiB = 0,              # mock evictor: the free VRAM it reports (0 = auto = just-enough)
    [string]$EvictorCommand,                # command-mode evictor: a pwsh script invoked with the handshake context JSON
    [int]$ConfirmIntervalMs = 200,          # WDDM-async headroom confirmation poll interval
    [int]$ConfirmTimeoutMs = 3000,          # give up confirming headroom after this
    [switch]$AllowLockOrder,                # override the lock-order-inversion rejection (records a reason)
    [string]$LockOrderReason,               # the recorded reason for an -AllowLockOrder override
    # ---- v0.3 (R1b) additive surface (all default-off; a plain / v0.2 call supplies NONE of these) ----
    [string]$OwnerId,                       # three-identity: the stable owner identity asserted on every op (default = Holder)
    [string]$ResidentGeneration,            # three-identity: the PoolManager-owned resident_generation stamped + asserted (finding 1)
    [switch]$Transition,                    # engage the single scheduler-owned ATOMIC hand-off transition (evictor OUTSIDE the mutex, txn journal)
    [int]$DrainTimeoutMs = 2000,            # bounded drain of an ACTIVE exec before cancel -> supervisor tree-kill (in-flight revocation)
    [int]$HeadroomObservations = 3,         # WDDM: require headroom STABLE across this many observations before granting
    [int]$HeadroomStableIntervalMs = 250,   # WDDM: spacing between the stable-headroom observations
    [switch]$Reconcile,                     # reconcile a crashed/stale transition journal (crash in PREPARING/DRAINING/STARTING)
    [long]$AuthorityEpoch = -1,             # assert-this-epoch CAS for a transition/exec op (-1 = not supplied); side effects ASSERT, never advance
    [string]$LeaseDir,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'res.lease'; $SKILL_VERSION = '0.3.0'; $CONTRACT = '0.3'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$LEASE_SCHEMA = 'lifeorch.res.lease/0.1'
$PARTIAL_GRACE_SEC = 15   # an unparseable/empty lease (a partial write) is reclaimable at mtime + this
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

# v0.2 InputsJson engagement flags (set during the merge below)
$jsonNew = $false; $jsonPriority = $false; $jsonFencing = $false; $jsonAllowLO = $false
# v0.3 (R1b) InputsJson engagement flags
$jsonR1b = $false; $jsonTransition = $false; $jsonReconcile = $false; $jsonOwnerId = $false; $jsonResidentGen = $false

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[res.lease] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Get-HostName {
    $h = $null
    try { $h = [System.Net.Dns]::GetHostName() } catch { }
    if ([string]::IsNullOrWhiteSpace($h)) { $h = $env:COMPUTERNAME }
    if ([string]::IsNullOrWhiteSpace($h)) { $h = 'host' }
    return $h
}
# Map a resource name to a safe, unique lease filename: sanitized prefix + short hash of the full name.
function Get-LeaseFileName([string]$resource) {
    $safe = ($resource -replace '[^A-Za-z0-9._-]', '_')
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48) }
    $h = (Get-Sha256Hex $utf8.GetBytes($resource)).Substring(0, 8)
    return "$safe-$h.lease"
}
# The durable per-resource fencing counter file (sibling of the lease; survives lease deletion on release).
function Get-FenceFileName([string]$resource) {
    $safe = ($resource -replace '[^A-Za-z0-9._-]', '_')
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48) }
    $h = (Get-Sha256Hex $utf8.GetBytes($resource)).Substring(0, 8)
    return "$safe-$h.fence"
}
# Convert a lease timestamp to a UTC DateTime. Robust across timezones: ConvertFrom-Json hands back a
# [DateTime] (Kind=Utc) for a "...Z" field, so we must NOT re-stringify (that drops the Kind, and a later
# ToUniversalTime() on the Kind=Unspecified re-parse shifts it by the LOCAL offset -> stale never fires off-UTC).
function ConvertTo-Utc($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [DateTime]) {
        if ($v.Kind -eq [System.DateTimeKind]::Utc) { return $v }
        if ($v.Kind -eq [System.DateTimeKind]::Local) { return $v.ToUniversalTime() }
        return [System.DateTime]::SpecifyKind($v, [System.DateTimeKind]::Utc)   # Unspecified: our stamps are UTC
    }
    $s = [string]$v
    $dt = [DateTime]::MinValue
    # RoundtripKind alone: honors a trailing 'Z'/offset (-> Kind=Utc/Local); a no-offset string parses as
    # Unspecified and is specified UTC below. (RoundtripKind is mutually exclusive with AssumeUniversal/AdjustToUniversal.)
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if ([DateTime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        if ($dt.Kind -eq [System.DateTimeKind]::Local) { return $dt.ToUniversalTime() }
        if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) { return [System.DateTime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
        return $dt
    }
    return $null
}
# Read a lease file with SHARED access. Returns $null if it does not exist / vanished, else a reader object
# { partial=$bool; mtime=<utc>; lease=<obj or $null> }.
function Read-LeaseFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $txt = $null; $mtime = [DateTime]::UtcNow
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $sr = New-Object System.IO.StreamReader($fs, $utf8)
            try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        } finally { $fs.Dispose() }
        $mtime = [System.IO.File]::GetLastWriteTimeUtc($path)
    } catch { return $null }   # vanished / locked mid-read -> treat as gone; caller retries
    if ([string]::IsNullOrWhiteSpace($txt)) { return [pscustomobject]@{ partial = $true; mtime = $mtime; lease = $null } }
    $obj = $null
    try { $obj = $txt | ConvertFrom-Json } catch { return [pscustomobject]@{ partial = $true; mtime = $mtime; lease = $null } }
    return [pscustomobject]@{ partial = $false; mtime = $mtime; lease = $obj }
}
# Expiry: full lease -> its expires_at_utc; partial write -> mtime + grace.
function Test-LeaseExpired($read, [DateTime]$now) {
    if ($null -eq $read) { return $true }
    if ($read.partial) { return ($read.mtime.AddSeconds($PARTIAL_GRACE_SEC) -lt $now) }
    $exp = ConvertTo-Utc (Prop $read.lease 'expires_at_utc' $null)
    if ($null -eq $exp) { return ($read.mtime.AddSeconds($PARTIAL_GRACE_SEC) -lt $now) }
    return ($exp -lt $now)
}
# Atomic reservation. $true if we created the file (we now hold it); $false if it already existed.
function Try-CreateLease([string]$path, [byte[]]$bytes) {
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        return $true
    } catch [System.IO.IOException] {
        return $false   # already exists (CreateNew on an existing file throws IOException)
    } finally {
        if ($null -ne $fs) { $fs.Dispose() }
    }
}
# Atomic write-or-replace (temp + Move overwrite). Used by the v0.2 prepared grant / seize; retries transient
# AV/indexer locks. Unlike Try-CreateLease this INTENTIONALLY overwrites -- callers must already hold authority.
function Grant-LeaseAtomic([string]$path, [byte[]]$bytes) {
    $tmp = "$path.grant-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
    try { [System.IO.File]::WriteAllBytes($tmp, $bytes) } catch { return $false }
    for ($mi = 0; $mi -lt 6; $mi++) { try { [System.IO.File]::Move($tmp, $path, $true); return $true } catch { Start-Sleep -Milliseconds 15 } }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $false
}
# Identity of a stale lease, so concurrent reclaimers of the SAME stale lease compute the SAME claim marker.
function Get-StaleId($read) {
    if ($read.partial) { return "partial-$($read.mtime.Ticks)" }
    $lid = [string](Prop $read.lease 'lease_id' '')
    if ([string]::IsNullOrWhiteSpace($lid)) { return "x-$($read.mtime.Ticks)" }
    return $lid
}
function New-LeaseObject([string]$resource, [string]$holder, [string]$lid, [DateTime]$acquiredAt, [DateTime]$expiresAt, [int]$ttl, [int]$renewCount, [string]$note, [System.Collections.IDictionary]$ext = $null) {
    $o = [ordered]@{
        schema          = $LEASE_SCHEMA
        resource        = $resource
        holder          = $holder
        holder_pid      = $PID
        host            = (Get-HostName)
        lease_id        = $lid
        acquired_at_utc = $acquiredAt.ToString('o')
        expires_at_utc  = $expiresAt.ToString('o')
        ttl_seconds     = $ttl
        renew_count     = $renewCount
        note            = $note
    }
    if ($null -ne $ext) { foreach ($k in $ext.Keys) { $o[$k] = $ext[$k] } }   # v0.2 additive fields (omitted when $ext is $null)
    return $o
}

# ---- v0.2 fencing token (finding 1) ----
function Read-FenceCounter([string]$fencePath) {
    if (-not (Test-Path -LiteralPath $fencePath -PathType Leaf)) { return [long]0 }
    try {
        $fs = [System.IO.File]::Open($fencePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $t = $null
        try { $sr = New-Object System.IO.StreamReader($fs, $utf8); try { $t = $sr.ReadToEnd() } finally { $sr.Dispose() } } finally { $fs.Dispose() }
        $n = [long]0
        if (-not [string]::IsNullOrWhiteSpace($t) -and [long]::TryParse($t.Trim(), [ref]$n)) { return $n }
        return [long]0
    } catch { return [long]0 }
}
# Mint a fresh, strictly-increasing per-resource token. Called ONLY by the unique fresh-grant holder of a
# resource -- lease exclusivity already serializes fresh grants of ONE resource, so no extra lock is needed;
# the counter write is atomic (temp + Move overwrite). $prevToken guards a crash that left the counter behind.
function Mint-FencingToken([string]$fencePath, [long]$prevToken) {
    $cur = Read-FenceCounter $fencePath
    $base = if ($prevToken -gt $cur) { $prevToken } else { $cur }
    $next = $base + [long]1
    try {
        $tmp = "$fencePath.mint-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
        [System.IO.File]::WriteAllText($tmp, [string]$next, $utf8)
        $moved = $false
        for ($mi = 0; $mi -lt 6 -and -not $moved; $mi++) { try { [System.IO.File]::Move($tmp, $fencePath, $true); $moved = $true } catch { Start-Sleep -Milliseconds 15 } }
        if (-not $moved) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    } catch { }
    return $next
}
# Rewrite a just-won lease ($cand is the ordered hashtable we wrote) adding the v0.2 ext fields (atomic replace).
function Set-LeaseExt([string]$leasePath, [System.Collections.IDictionary]$cand, [System.Collections.IDictionary]$ext) {
    $o = [ordered]@{}
    foreach ($k in $cand.Keys) { $o[$k] = $cand[$k] }
    foreach ($k in $ext.Keys) { $o[$k] = $ext[$k] }
    $bytes = $utf8.GetBytes(($o | ConvertTo-Json -Depth 6))
    return (Grant-LeaseAtomic $leasePath $bytes)
}
# Rewrite a resident residency_pin (preserving its identity + ext) with a revoked_by stamp (finding 13).
function Set-PinRevoked([string]$leasePath, $rd, [string]$byHolder, [long]$byToken, [int]$byPriority, [string]$reason) {
    $l = $rd.lease
    $acq = ConvertTo-Utc (Prop $l 'acquired_at_utc' $null); if ($null -eq $acq) { $acq = [DateTime]::UtcNow }
    $exp = ConvertTo-Utc (Prop $l 'expires_at_utc' $null);  if ($null -eq $exp) { $exp = [DateTime]::UtcNow }
    $ext = [ordered]@{
        fencing_token     = [long](Prop $l 'fencing_token' 0)
        lease_kind        = [string](Prop $l 'lease_kind' 'residency_pin')
        priority          = [int](Prop $l 'priority' 0)
        revocable         = $true
        required_vram_mib = [int](Prop $l 'required_vram_mib' 0)
        revoked_by        = [ordered]@{ holder = $byHolder; fencing_token = $byToken; priority = $byPriority; at_utc = ([DateTime]::UtcNow.ToString('o')); reason = $reason }
    }
    $o = New-LeaseObject ([string](Prop $l 'resource' '')) ([string](Prop $l 'holder' '')) ([string](Prop $l 'lease_id' '')) $acq $exp ([int](Prop $l 'ttl_seconds' 120)) ([int](Prop $l 'renew_count' 0)) ([string](Prop $l 'note' '')) $ext
    $bytes = $utf8.GetBytes(($o | ConvertTo-Json -Depth 6))
    return (Grant-LeaseAtomic $leasePath $bytes)
}
# Canonical lock-order rank: gpu(0) -> git(1) -> doc:<path>(2). -1 = non-canonical (not subject to the rule).
function Get-ResourceRank([string]$resource) {
    if ($resource -eq 'gpu') { return 0 }
    if ($resource -eq 'git') { return 1 }
    if ($resource -like 'doc:*') { return 2 }
    return -1
}
# Lock-order-inversion check (finding 14): $null if fine, else the earlier-ranked lease THIS holder already
# holds live while acquiring a later/cheaper-ranked one (e.g. holds gpu, acquiring git -> the gpu sits idle).
function Get-LockOrderConflict([string]$leaseDir, [string]$holder, [string]$resource) {
    $ar = Get-ResourceRank $resource
    if ($ar -le 0) { return $null }   # acquiring gpu(0) or a non-canonical resource: nothing ranks before it
    $now = [DateTime]::UtcNow
    $files = @(Get-ChildItem -LiteralPath $leaseDir -Filter '*.lease' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $rd = Read-LeaseFile $f.FullName
        if ($null -eq $rd -or $rd.partial) { continue }
        if (Test-LeaseExpired $rd $now) { continue }
        if ([string](Prop $rd.lease 'holder' '') -ne $holder) { continue }
        $hr = [string](Prop $rd.lease 'resource' '')
        $hrank = Get-ResourceRank $hr
        if ($hrank -ge 0 -and $hrank -lt $ar) {
            return [ordered]@{ held_resource = $hr; held_rank = $hrank; acquire_rank = $ar; held_lease_id = [string](Prop $rd.lease 'lease_id' '') }
        }
    }
    return $null
}
# The pluggable evictor seam (findings 2/15). res.lease is PURE -- it never inspects VRAM or kills a server;
# it drives a MOCK evictor (tests) or a command-mode evictor (the R1b PoolManager integration point) and grants
# only when the seam CONFIRMS headroom (>= RequiredVramMiB + TargetHeadroomMiB) within the confirmation interval.
function Invoke-Evictor([string]$mode, [string]$mockResult, [int]$mockFree, [string]$cmd, $ctx, [int]$required, [int]$targetHead, [int]$intervalMs, [int]$timeoutMs) {
    $need = $required + $targetHead
    if ($mode -eq 'mock') {
        if ($mockResult -eq 'confirm') {
            $free = if ($mockFree -gt 0) { $mockFree } else { $need }
            return [ordered]@{ confirmed = ($free -ge $need); free_vram_mib = $free; evicted = $false; outcome = 'confirm'; detail = 'mock: headroom already sufficient' }
        } elseif ($mockResult -eq 'needs_evict') {
            Start-Sleep -Milliseconds ([Math]::Max(0, $intervalMs))   # WDDM-async: VRAM frees a confirm-interval after the evict
            $free = if ($mockFree -gt 0) { $mockFree } else { $need }
            return [ordered]@{ confirmed = ($free -ge $need); free_vram_mib = $free; evicted = $true; outcome = 'needs_evict'; detail = 'mock: evicted resident, headroom confirmed after interval' }
        } else {   # timeout
            Start-Sleep -Milliseconds ([Math]::Min([Math]::Max(0, $timeoutMs), 400))
            return [ordered]@{ confirmed = $false; free_vram_mib = ([Math]::Max(0, $mockFree)); evicted = $true; outcome = 'timeout'; detail = 'mock: eviction requested, headroom NOT confirmed within confirm timeout' }
        }
    } elseif ($mode -eq 'command') {
        try {
            $ctxJson = ($ctx | ConvertTo-Json -Compress -Depth 6)
            $raw = (& $cmd -ContextJson $ctxJson 2>$null | Out-String).Trim()
            $r = $null; try { $r = $raw | ConvertFrom-Json } catch { }
            if ($null -eq $r) { return [ordered]@{ confirmed = $false; free_vram_mib = 0; evicted = $false; outcome = 'command_error'; detail = 'evictor command produced no JSON result' } }
            return [ordered]@{ confirmed = [bool](Prop $r 'confirmed' $false); free_vram_mib = [int](Prop $r 'free_vram_mib' 0); evicted = [bool](Prop $r 'evicted' $false); outcome = [string](Prop $r 'outcome' 'command'); detail = [string](Prop $r 'detail' '') }
        } catch { return [ordered]@{ confirmed = $false; free_vram_mib = 0; evicted = $false; outcome = 'command_error'; detail = "evictor command failed: $($_.Exception.Message)" } }
    }
    return [ordered]@{ confirmed = $false; free_vram_mib = 0; evicted = $false; outcome = 'no_evictor'; detail = 'no evictor seam configured (EvictorMode=none)' }
}

# ============================================================================================================
# v0.3 (R1b) -- the single scheduler-owned ATOMIC hand-off transition support.
# Three identities (frontier review section 2): gpu_authority_epoch (= the per-resource fencing_token; bumps
# ONLY when exclusive GPU authority changes; side effects ASSERT it), resident_generation (PoolManager-owned;
# supplied via -ResidentGeneration), exec_lease_id (= the exec acquire's lease_id). res.lease stays PURE: the
# evictor (drain->cancel->tree-kill->confirm) is a SEAM; the transition drives it OUTSIDE the lease mutex and
# commits the grant only if the reserved authority epoch is STILL current (nobody seized during eviction).
# ============================================================================================================
function Get-TxnFileName([string]$resource) {
    $safe = ($resource -replace '[^A-Za-z0-9._-]', '_')
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48) }
    $h = (Get-Sha256Hex $utf8.GetBytes($resource)).Substring(0, 8)
    return "$safe-$h.txn"
}
function Read-Txn([string]$txnPath) {
    if (-not (Test-Path -LiteralPath $txnPath -PathType Leaf)) { return $null }
    try {
        $fs = [System.IO.File]::Open($txnPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $t = $null
        try { $sr = New-Object System.IO.StreamReader($fs, $utf8); try { $t = $sr.ReadToEnd() } finally { $sr.Dispose() } } finally { $fs.Dispose() }
        if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        return ($t | ConvertFrom-Json)
    } catch { return $null }
}
function Write-Txn([string]$txnPath, [System.Collections.IDictionary]$rec) {
    $bytes = $utf8.GetBytes(($rec | ConvertTo-Json -Depth 8))
    return (Grant-LeaseAtomic $txnPath $bytes)   # atomic replace (temp + Move overwrite)
}
# Reconcile a crashed/stale transition: a PREPARING/DRAINING/STARTING txn whose owner is gone (stale) OR whose
# reserved epoch was superseded is rolled to ABORTED (idempotent). Returns a small report or $null if nothing to do.
function Reconcile-Txn([string]$txnPath, [string]$fencePath, [int]$graceSec) {
    $t = Read-Txn $txnPath
    if ($null -eq $t) { return $null }
    $state = [string](Prop $t 'state' '')
    # only a crashed IN-PROGRESS transition is reconcilable; terminal states (COMMITTED/ABORTED) are left alone.
    if (@('RESERVING','PREPARING','DRAINING','STARTING') -notcontains $state) { return $null }
    $stamp = ConvertTo-Utc (Prop $t 'updated_utc' $null)
    $age = if ($null -ne $stamp) { ([DateTime]::UtcNow - $stamp).TotalSeconds } else { [double]999999 }
    $curEpoch = Read-FenceCounter $fencePath
    $txnEpoch = [long](Prop $t 'authority_epoch' 0)
    $superseded = ($curEpoch -gt $txnEpoch)
    if ($age -ge $graceSec -or $superseded) {
        $r = [ordered]@{}
        foreach ($p in $t.PSObject.Properties) { $r[$p.Name] = $p.Value }
        $r['state'] = 'ABORTED'
        $r['reconciled_utc'] = ([DateTime]::UtcNow.ToString('o'))
        $r['reconcile_reason'] = if ($superseded) { 'superseded_epoch' } else { 'stale_owner' }
        [void](Write-Txn $txnPath $r)
        return [ordered]@{ reconciled=$true; from_state=$state; reason=[string]$r['reconcile_reason']; age_sec=[int]$age }
    }
    return [ordered]@{ reconciled=$false; from_state=$state; reason='still_active'; age_sec=[int]$age }
}
# The R1b transition evictor: drives the seam, requires the managed tree GONE, and requires headroom STABLE
# across N observations ~intervalMs apart (WDDM-async discipline). MOCK models the adversarial hardware
# behaviors; the REAL PoolManager evictor plugs into -EvictorMode command and must return
# {confirmed, free_vram_mib, evicted, tree_gone, outcome, detail}. Distinct from R1a's Invoke-Evictor
# (which stays byte-identical for the R1a prepared path).
function Invoke-TransitionEvictor {
    param([string]$mode, [string]$mockResult, [int]$mockFree, [string]$cmd, $ctx,
          [int]$required, [int]$targetHead, [int]$obsCount, [int]$intervalMs, [int]$timeoutMs)
    $need = $required + $targetHead
    if ($mode -eq 'command') {
        $r = Invoke-Evictor 'command' $mockResult $mockFree $cmd $ctx $required $targetHead $intervalMs $timeoutMs
        $treeGone = $true; try { if (Has $r 'tree_gone') { $treeGone = [bool]$r.tree_gone } } catch { }
        return [ordered]@{ confirmed=[bool]$r.confirmed; free_vram_mib=[int]$r.free_vram_mib; evicted=[bool]$r.evicted; tree_gone=$treeGone; outcome=[string]$r.outcome; detail=[string]$r.detail; observations=@() }
    }
    if ($mode -ne 'mock') {
        return [ordered]@{ confirmed=$false; free_vram_mib=0; evicted=$false; tree_gone=$false; outcome='no_evictor'; detail='EvictorMode must be mock|command for a transition'; observations=@() }
    }
    if ($obsCount -lt 1) { $obsCount = 1 }
    $obs = New-Object System.Collections.Generic.List[int]
    $evicted = $true; $treeGone = $true; $outcome = $mockResult
    switch ($mockResult) {
        'confirm'           { $evicted=$false; for ($i=0;$i -lt $obsCount;$i++){ $obs.Add($need) } }
        'needs_evict'       { for ($i=0;$i -lt $obsCount;$i++){ $obs.Add($(if($mockFree -gt 0){$mockFree}else{$need})) } }
        'late_evict'        { Start-Sleep -Milliseconds ([Math]::Min([Math]::Max(0,$intervalMs*2),400)); for ($i=0;$i -lt $obsCount;$i++){ $obs.Add($need) } }  # eviction completes LATE, then headroom is stable -> we WAITED, confirm
        'partial_tree_term' { $treeGone=$false; for ($i=0;$i -lt $obsCount;$i++){ $obs.Add($need) } }               # headroom looks fine but a child survived -> NOT gone
        'headroom_never'    { for ($i=0;$i -lt $obsCount;$i++){ $obs.Add([Math]::Max(0,$need-256)) } }
        'headroom_fell'     { $obs.Add($need); $obs.Add($need); $obs.Add([Math]::Max(0,$need-256)) }                # reached then fell -> not stable
        'cancel_during_prepare' { return [ordered]@{ confirmed=$false; free_vram_mib=0; evicted=$false; tree_gone=$false; outcome='cancelled'; detail='cancellation arrived during prepare'; observations=@() } }
        'timeout'           { Start-Sleep -Milliseconds ([Math]::Min([Math]::Max(0,$timeoutMs),300)); return [ordered]@{ confirmed=$false; free_vram_mib=([Math]::Max(0,$mockFree)); evicted=$true; tree_gone=$true; outcome='timeout'; detail='eviction requested, headroom NOT confirmed within timeout'; observations=@() } }
    }
    # spacing between observations (bounded so tests stay fast) -- WDDM async settle
    for ($i=1;$i -lt $obs.Count;$i++){ Start-Sleep -Milliseconds ([Math]::Min([Math]::Max(0,$intervalMs),300)) }
    $allStable = ($obs.Count -ge 1)
    foreach ($o in $obs) { if ($o -lt $need) { $allStable = $false } }
    $confirmed = ($allStable -and $treeGone)
    $freeReport = if ($obs.Count -gt 0) { $obs[$obs.Count-1] } else { 0 }
    $det = if (-not $treeGone) { 'managed tree NOT confirmed gone (partial termination)' } elseif (-not $allStable) { 'headroom not stable across observations' } else { 'tree gone + headroom stable across observations' }
    return [ordered]@{ confirmed=$confirmed; free_vram_mib=$freeReport; evicted=$evicted; tree_gone=$treeGone; outcome=$outcome; detail=$det; observations=$obs.ToArray() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $null
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'action')       -and -not $bound.ContainsKey('Action'))      { $Action = [string]$p.action }
            if ((Has $p 'resource')     -and -not $bound.ContainsKey('Resource'))    { $Resource = [string]$p.resource }
            if ((Has $p 'holder')       -and -not $bound.ContainsKey('Holder'))      { $Holder = [string]$p.holder }
            if ((Has $p 'ttl_seconds')  -and -not $bound.ContainsKey('TtlSeconds'))  { $TtlSeconds = [int]$p.ttl_seconds }
            if ((Has $p 'wait_seconds') -and -not $bound.ContainsKey('WaitSeconds')) { $WaitSeconds = [double]$p.wait_seconds }
            if ((Has $p 'lease_id')     -and -not $bound.ContainsKey('LeaseId'))     { $LeaseId = [string]$p.lease_id }
            if ((Has $p 'note')         -and -not $bound.ContainsKey('Note'))        { $Note = [string]$p.note }
            if ((Has $p 'lease_dir')    -and -not $bound.ContainsKey('LeaseDir'))    { $LeaseDir = [string]$p.lease_dir }
            # v0.2 additive keys
            if ((Has $p 'kind')                -and -not $bound.ContainsKey('Kind'))              { $Kind = [string]$p.kind; $jsonNew = $true }
            if ((Has $p 'priority')            -and -not $bound.ContainsKey('Priority'))          { $Priority = [int]$p.priority; $jsonNew = $true; $jsonPriority = $true }
            if ((Has $p 'revocable')           -and -not $bound.ContainsKey('Revocable'))         { $Revocable = [bool]$p.revocable; $jsonNew = $true }
            if ((Has $p 'fencing_token')       -and -not $bound.ContainsKey('FencingToken'))      { $FencingToken = [long]$p.fencing_token; $jsonNew = $true; $jsonFencing = $true }
            if ((Has $p 'required_vram_mib')   -and -not $bound.ContainsKey('RequiredVramMiB'))   { $RequiredVramMiB = [int]$p.required_vram_mib; $jsonNew = $true }
            if ((Has $p 'target_headroom_mib') -and -not $bound.ContainsKey('TargetHeadroomMiB')) { $TargetHeadroomMiB = [int]$p.target_headroom_mib; $jsonNew = $true }
            if ((Has $p 'evictor_mode')        -and -not $bound.ContainsKey('EvictorMode'))       { $EvictorMode = [string]$p.evictor_mode; $jsonNew = $true }
            if ((Has $p 'mock_evictor_result') -and -not $bound.ContainsKey('MockEvictorResult')) { $MockEvictorResult = [string]$p.mock_evictor_result; $jsonNew = $true }
            if ((Has $p 'mock_free_vram_mib')  -and -not $bound.ContainsKey('MockFreeVramMiB'))   { $MockFreeVramMiB = [int]$p.mock_free_vram_mib; $jsonNew = $true }
            if ((Has $p 'evictor_command')     -and -not $bound.ContainsKey('EvictorCommand'))    { $EvictorCommand = [string]$p.evictor_command; $jsonNew = $true }
            if ((Has $p 'confirm_interval_ms') -and -not $bound.ContainsKey('ConfirmIntervalMs')) { $ConfirmIntervalMs = [int]$p.confirm_interval_ms; $jsonNew = $true }
            if ((Has $p 'confirm_timeout_ms')  -and -not $bound.ContainsKey('ConfirmTimeoutMs'))  { $ConfirmTimeoutMs = [int]$p.confirm_timeout_ms; $jsonNew = $true }
            if ((Has $p 'allow_lock_order')    -and -not $bound.ContainsKey('AllowLockOrder'))    { if ([bool]$p.allow_lock_order) { $jsonAllowLO = $true }; $jsonNew = $true }
            if ((Has $p 'lock_order_reason')   -and -not $bound.ContainsKey('LockOrderReason'))   { $LockOrderReason = [string]$p.lock_order_reason; $jsonNew = $true }
            # v0.3 (R1b) additive keys
            if ((Has $p 'owner_id')                     -and -not $bound.ContainsKey('OwnerId'))                  { $OwnerId = [string]$p.owner_id; $jsonNew = $true; $jsonR1b = $true; $jsonOwnerId = $true }
            if ((Has $p 'resident_generation')          -and -not $bound.ContainsKey('ResidentGeneration'))       { $ResidentGeneration = [string]$p.resident_generation; $jsonNew = $true; $jsonR1b = $true; $jsonResidentGen = $true }
            if ((Has $p 'transition')                   -and -not $bound.ContainsKey('Transition'))               { if ([bool]$p.transition) { $jsonTransition = $true }; $jsonNew = $true; $jsonR1b = $true }
            if ((Has $p 'drain_timeout_ms')             -and -not $bound.ContainsKey('DrainTimeoutMs'))           { $DrainTimeoutMs = [int]$p.drain_timeout_ms; $jsonNew = $true; $jsonR1b = $true }
            if ((Has $p 'headroom_observations')        -and -not $bound.ContainsKey('HeadroomObservations'))     { $HeadroomObservations = [int]$p.headroom_observations; $jsonNew = $true; $jsonR1b = $true }
            if ((Has $p 'headroom_stable_interval_ms')  -and -not $bound.ContainsKey('HeadroomStableIntervalMs')) { $HeadroomStableIntervalMs = [int]$p.headroom_stable_interval_ms; $jsonNew = $true; $jsonR1b = $true }
            if ((Has $p 'reconcile')                    -and -not $bound.ContainsKey('Reconcile'))                { if ([bool]$p.reconcile) { $jsonReconcile = $true }; $jsonNew = $true; $jsonR1b = $true }
            if ((Has $p 'authority_epoch')              -and -not $bound.ContainsKey('AuthorityEpoch'))           { $AuthorityEpoch = [long]$p.authority_epoch; $jsonNew = $true; $jsonR1b = $true }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Action)) { throw [PSCustomObject]@{ code='missing_parameter'; message='action is required (acquire|release|renew|status|list|check)'; retryable=$false } }
    $Action = $Action.ToLowerInvariant()
    if (@('acquire','release','renew','status','list','check') -notcontains $Action) { throw [PSCustomObject]@{ code='invalid_action'; message="action must be acquire|release|renew|status|list|check (got '$Action')"; retryable=$false } }
    if ($Action -ne 'list' -and [string]::IsNullOrWhiteSpace($Resource)) { throw [PSCustomObject]@{ code='missing_parameter'; message="$Action needs a resource"; retryable=$false } }
    if ($TtlSeconds -lt 1) { $TtlSeconds = 1 }

    # v0.2 value validation (all defaults are valid, so a plain call never trips these)
    if (@('exec','residency_pin') -notcontains $Kind) { throw [PSCustomObject]@{ code='invalid_kind'; message="kind must be exec|residency_pin (got '$Kind')"; retryable=$false } }
    if (@('none','mock','command') -notcontains $EvictorMode) { throw [PSCustomObject]@{ code='invalid_evictor_mode'; message="evictor_mode must be none|mock|command (got '$EvictorMode')"; retryable=$false } }
    $MOCK_RESULTS = @('confirm','needs_evict','timeout','late_evict','partial_tree_term','headroom_never','headroom_fell','cancel_during_prepare')
    if ($MOCK_RESULTS -notcontains $MockEvictorResult) { throw [PSCustomObject]@{ code='invalid_mock_result'; message="mock_evictor_result must be one of $($MOCK_RESULTS -join '|') (got '$MockEvictorResult')"; retryable=$false } }

    # ---- v0.2 engagement: the new surface is INERT unless the caller supplies >=1 new input (byte-identical default) ----
    $newKeys = @('Kind','Priority','Revocable','FencingToken','RequiredVramMiB','TargetHeadroomMiB','EvictorMode','MockEvictorResult','MockFreeVramMiB','EvictorCommand','ConfirmIntervalMs','ConfirmTimeoutMs','AllowLockOrder','LockOrderReason')
    $engagedNew = $jsonNew
    foreach ($k in $newKeys) { if ($bound.ContainsKey($k)) { $engagedNew = $true; break } }
    if ($Action -eq 'check') { $engagedNew = $true }
    $prioritySupplied = $bound.ContainsKey('Priority') -or $jsonPriority
    $fencingTokenSupplied = $bound.ContainsKey('FencingToken') -or $jsonFencing
    $allowLO = $AllowLockOrder.IsPresent -or $jsonAllowLO
    $isPin = ($Kind -eq 'residency_pin')
    $isPrepared = ($Action -eq 'acquire') -and ($RequiredVramMiB -ge 0)

    # ---- v0.3 (R1b) engagement: three-identity fencing + the scheduler-owned atomic transition ----
    $engagedR1b = $jsonR1b
    foreach ($k in @('OwnerId','ResidentGeneration','Transition','DrainTimeoutMs','HeadroomObservations','HeadroomStableIntervalMs','Reconcile','AuthorityEpoch')) { if ($bound.ContainsKey($k)) { $engagedR1b = $true; break } }
    if ($engagedR1b) { $engagedNew = $true }   # R1b implies the engaged (non-byte-identical) surface
    $doTransition = ($Transition.IsPresent -or $jsonTransition)
    $doReconcile  = ($Reconcile.IsPresent -or $jsonReconcile)
    $authorityEpochSupplied = $bound.ContainsKey('AuthorityEpoch') -or ($AuthorityEpoch -ge 0)
    if ([string]::IsNullOrWhiteSpace($OwnerId)) { $OwnerId = $Holder }
    # gpu_authority_epoch is the fencing_token under a clearer name; an -AuthorityEpoch assertion is a fencing CAS.
    if ($authorityEpochSupplied -and -not $fencingTokenSupplied) { $FencingToken = $AuthorityEpoch; $fencingTokenSupplied = $true }

    # ---- resolve holder + lease dir ----
    if ([string]::IsNullOrWhiteSpace($Holder)) {
        $Holder = $env:LIFEORCH_INSTANCE
        if ([string]::IsNullOrWhiteSpace($Holder)) { $Holder = "$(Get-HostName):$($PID):$([Guid]::NewGuid().ToString('N').Substring(0,8))" }
    }
    if ([string]::IsNullOrWhiteSpace($LeaseDir)) {
        $LeaseDir = $env:LIFEORCH_LEASE_DIR
        if ([string]::IsNullOrWhiteSpace($LeaseDir)) { $LeaseDir = Join-Path $PSScriptRoot 'runtime/leases' }
    }
    New-Item -ItemType Directory -Path $LeaseDir -Force | Out-Null
    $LeaseDir = (Resolve-Path -LiteralPath $LeaseDir).Path
    if ([string]::IsNullOrWhiteSpace($Note)) { $Note = '' }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    switch ($Action) {
        'acquire' {
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $fencePath = Join-Path $LeaseDir (Get-FenceFileName $Resource)

            # ===================== v0.3 (R1b): the single scheduler-owned ATOMIC hand-off transition ==============
            # reserve -> fence old owner off new exec -> drain/cancel active exec -> invalidate publish -> shut down
            # resident -> confirm tree gone -> confirm STABLE headroom -> grant (start+health-check+publish = the
            # consumer). No interval where the old owner can reacquire exec; the evictor runs OUTSIDE the mutex and
            # the grant commits ONLY if the reserved authority epoch is still current.
            if ($doTransition) {
                $txnPath = Join-Path $LeaseDir (Get-TxnFileName $Resource)
                $txnClaimPath = "$txnPath.claim"
                $txnId = [Guid]::NewGuid().ToString('N')
                $t0 = [DateTime]::UtcNow
                $heldBy = $null; $leaseObj = $null
                $reconcileReport = Reconcile-Txn $txnPath $fencePath $PARTIAL_GRACE_SEC   # crash recovery FIRST
                $trAcquired=$false; $trReason=$null; $trState='RESERVING'; $newEpoch=$null; $revoked=$null
                $evConfirmed=$false; $evEvicted=$false; $evTreeGone=$null; $evFree=$null; $evOutcome=$null; $evObs=@(); $superseded=$false
                $myLid=[Guid]::NewGuid().ToString()
                # serialize transitions: exactly ONE transition-in-progress per resource (equal-priority single winner)
                $claimBytes=$utf8.GetBytes("txn=$txnId owner=$OwnerId at=$($t0.ToString('o'))")
                $gotClaim=$false
                if (Try-CreateLease $txnClaimPath $claimBytes) { $gotClaim=$true }
                else {
                    $cm=[DateTime]::UtcNow; try { $cm=[System.IO.File]::GetLastWriteTimeUtc($txnClaimPath) } catch {}
                    if ($cm.AddSeconds($PARTIAL_GRACE_SEC) -lt [DateTime]::UtcNow) { Remove-Item -LiteralPath $txnClaimPath -Force -ErrorAction SilentlyContinue; if (Try-CreateLease $txnClaimPath $claimBytes) { $gotClaim=$true } }
                }
                if (-not $gotClaim) { $trReason='transition_in_progress' }
                else {
                  try {
                    $read=Read-LeaseFile $leasePath
                    $nowP=[DateTime]::UtcNow
                    $priorEpoch=[long](Read-FenceCounter $fencePath)
                    $residentHolder=$null; $residentKind=$null; $residentPrio=0; $residentGen=$null
                    $hasResident = ($null -ne $read -and -not $read.partial -and -not (Test-LeaseExpired $read $nowP))
                    if ($hasResident) {
                        $residentHolder=[string](Prop $read.lease 'holder' '')
                        $residentKind=[string](Prop $read.lease 'lease_kind' 'exec')
                        $residentPrio=[int](Prop $read.lease 'priority' 0)
                        $residentGen=[string](Prop $read.lease 'resident_generation' '')
                        if ($residentHolder -eq $Holder) {
                            $trAcquired=$true; $trState='COMMITTED'; $myLid=[string](Prop $read.lease 'lease_id' $myLid); $newEpoch=[long](Prop $read.lease 'fencing_token' $priorEpoch); $trReason='already_held'; $leaseObj=$read.lease
                        } elseif (-not ($residentKind -eq 'residency_pin' -and [bool](Prop $read.lease 'revocable' $false) -and $residentPrio -lt $Priority)) {
                            $trReason='held_incompatible'; $heldBy=$residentHolder   # exec / equal-or-higher pin: cannot preempt
                        }
                    }
                    if (-not $trAcquired -and ($null -eq $trReason)) {
                        # ---- RESERVE: bump the GPU authority epoch (authority TRANSFERS to us) ----
                        $newEpoch = Mint-FencingToken $fencePath $priorEpoch
                        $trState='PREPARING'
                        $txnRec=[ordered]@{ schema='lifeorch.res.lease.txn/0.1'; txn_id=$txnId; resource=$Resource; owner_id=$OwnerId; holder=$Holder; state=$trState; authority_epoch=$newEpoch; prior_epoch=$priorEpoch; resident_holder=$residentHolder; resident_generation=$residentGen; required_vram_mib=$RequiredVramMiB; target_headroom_mib=$TargetHeadroomMiB; started_utc=$t0.ToString('o'); updated_utc=([DateTime]::UtcNow.ToString('o')) }
                        [void](Write-Txn $txnPath $txnRec)
                        # ---- FENCE the old owner off (stamp revoked_by so its old epoch is stale) ----
                        if ($hasResident -and $residentKind -eq 'residency_pin') {
                            [void](Set-PinRevoked $leasePath $read $Holder $newEpoch $Priority 'preempted_by_transition')
                            $revoked=[ordered]@{ holder=$residentHolder; lease_id=[string](Prop $read.lease 'lease_id' ''); prior_fencing_token=[long](Prop $read.lease 'fencing_token' 0); priority=$residentPrio }
                        }
                        # ---- DRAINING: the evictor drains->cancels->tree-kills OUTSIDE the lease mutex ----
                        $trState='DRAINING'; $txnRec['state']=$trState; $txnRec['updated_utc']=[DateTime]::UtcNow.ToString('o'); [void](Write-Txn $txnPath $txnRec)
                        $evCtx=[ordered]@{ resource=$Resource; lease_dir=$LeaseDir; txn_id=$txnId; owner_id=$OwnerId; authority_epoch=$newEpoch; required_vram_mib=$RequiredVramMiB; target_headroom_mib=$TargetHeadroomMiB; resident_holder=$residentHolder; resident_generation=$residentGen; drain_timeout_ms=$DrainTimeoutMs; state=$(if($hasResident){'occupied'}else{'free'}) }
                        $ev=Invoke-TransitionEvictor $EvictorMode $MockEvictorResult $MockFreeVramMiB $EvictorCommand $evCtx $RequiredVramMiB $TargetHeadroomMiB $HeadroomObservations $HeadroomStableIntervalMs $ConfirmTimeoutMs
                        $evConfirmed=[bool]$ev.confirmed; $evEvicted=[bool]$ev.evicted; $evTreeGone=[bool]$ev.tree_gone; $evFree=$ev.free_vram_mib; $evOutcome=[string]$ev.outcome; $evObs=$ev.observations
                        # ---- COMMIT-IF-EPOCH-CURRENT: grant ONLY if our reserved epoch is still the authority ----
                        $curEpoch=[long](Read-FenceCounter $fencePath)
                        if ($curEpoch -ne $newEpoch) { $superseded=$true; $trReason='superseded_during_transition'; $trState='ABORTED' }
                        elseif ($evConfirmed) {
                            $nowL=[DateTime]::UtcNow; $expiresAt=$nowL.AddSeconds($TtlSeconds)
                            $ext=[ordered]@{ fencing_token=$newEpoch; gpu_authority_epoch=$newEpoch; lease_kind=$Kind; priority=$Priority; revocable=$(if($isPin){$true}else{$false}); required_vram_mib=$RequiredVramMiB; resident_generation=$ResidentGeneration; owner_id=$OwnerId; revoked_by=$null }
                            $cand=New-LeaseObject $Resource $Holder $myLid $nowL $expiresAt $TtlSeconds 0 $Note $ext
                            $bytes=$utf8.GetBytes(($cand | ConvertTo-Json -Depth 6))
                            if (Grant-LeaseAtomic $leasePath $bytes) { $trAcquired=$true; $leaseObj=$cand; $trState='STARTING' }
                            else { $trReason='seize_failed'; $trState='ABORTED' }
                        } else { $trReason=$(if($evOutcome){"evictor_$evOutcome"}else{'headroom_not_confirmed'}); $trState='ABORTED' }
                        $txnRec['state']=$trState; $txnRec['updated_utc']=[DateTime]::UtcNow.ToString('o'); $txnRec['evictor_outcome']=$evOutcome; [void](Write-Txn $txnPath $txnRec)
                    }
                  } finally { Remove-Item -LiteralPath $txnClaimPath -Force -ErrorAction SilentlyContinue }
                }
                $trWaitedMs=[int]([DateTime]::UtcNow - $t0).TotalMilliseconds
                $result=[ordered]@{
                    action='acquire'; resource=$Resource; acquired=$trAcquired
                    lease_id=$(if($trAcquired){$myLid}else{$null}); holder=$Holder
                    expires_at_utc=$(if($trAcquired -and $null -ne $leaseObj){[string](Prop $leaseObj 'expires_at_utc' '')}else{$null})
                    ttl_seconds=$TtlSeconds; waited_ms=$trWaitedMs
                    reclaimed_stale=$false; already_held=$(if($trReason -eq 'already_held'){$true}else{$false})
                    held_by=$(if($trAcquired){$null}else{$heldBy}); held_expires_at_utc=$null; lease_dir=$LeaseDir
                    fencing_token=$newEpoch; gpu_authority_epoch=$newEpoch; exec_lease_id=$(if($trAcquired -and $Kind -eq 'exec'){$myLid}else{$null})
                    resident_generation=$(if([string]::IsNullOrWhiteSpace($ResidentGeneration)){$null}else{$ResidentGeneration}); owner_id=$OwnerId
                    lease_kind=$Kind; priority=$Priority; revocable=$(if($isPin){$true}else{$false}); revoked_by=$null
                    transition=$true; transition_id=$txnId; transition_state=$trState
                    prepared=$trAcquired; required_vram_mib=$RequiredVramMiB; target_headroom_mib=$TargetHeadroomMiB
                    evict_performed=$evEvicted; tree_gone=$evTreeGone; headroom_confirmed=$evConfirmed
                    free_vram_mib=$evFree; evictor_mode=$EvictorMode; evictor_outcome=$evOutcome; headroom_observations=$evObs
                    superseded=$superseded; reason=$trReason
                }
                if ($null -ne $revoked) { $result['revocation_signaled']=$true; $result['revoked_pin']=$revoked }
                if ($null -ne $reconcileReport) { $result['reconciled']=$reconcileReport }
                $normInputs=[ordered]@{ action='acquire'; resource=$Resource; holder=$Holder; transition=$true; owner_id=$OwnerId }
                Write-Diag "TRANSITION resource=$Resource acquired=$trAcquired state=$trState epoch=$newEpoch outcome=$evOutcome reason=$trReason waited_ms=$trWaitedMs"
                break
            }
            # ===================== end transition; the R1a/classic acquire paths follow unchanged ================
            $now0 = [DateTime]::UtcNow
            $deadline = $now0.AddSeconds([Math]::Max(0, $WaitSeconds))
            $myLid = [Guid]::NewGuid().ToString()
            $acquired = $false; $alreadyHeld = $false; $reclaimedStale = $false
            $heldBy = $null; $heldExp = $null; $leaseObj = $null
            $fencingToken = $null; $revokedPin = $null; $acqReason = $null; $lockOverride = $null
            $prepared = $false; $headroomConfirmed = $false; $evictPerformed = $false; $freeVram = $null; $evictorOutcome = $null

            # ---- finding 14: lock-order-inversion rejection (fires for any git/doc acquire; -AllowLockOrder overrides) ----
            $lockConflict = Get-LockOrderConflict $LeaseDir $Holder $Resource
            if ($null -ne $lockConflict) {
                if ($allowLO) {
                    $lockOverride = [ordered]@{ held_resource=$lockConflict.held_resource; held_rank=$lockConflict.held_rank; acquire_rank=$lockConflict.acquire_rank; reason=$(if ([string]::IsNullOrWhiteSpace($LockOrderReason)) { '(no reason given)' } else { $LockOrderReason }) }
                    Write-Diag "lock-order OVERRIDE: holder=$Holder holds $($lockConflict.held_resource) acquiring $Resource reason=$($lockOverride.reason)"
                } else {
                    throw [PSCustomObject]@{ code='lock_order_violation'; message="lock-order inversion: holder '$Holder' already holds '$($lockConflict.held_resource)' (rank $($lockConflict.held_rank)); acquiring '$Resource' (rank $($lockConflict.acquire_rank)) would hold the earlier/costlier lease idle. Canonical order gpu->git->doc: sequence the work (e.g. git for the commit, RELEASE git, then gpu for the live verify) or pass -AllowLockOrder -LockOrderReason '<why>'. (finding 14)"; retryable=$false }
                }
            }

            if ($isPin -and -not $Revocable) {
                throw [PSCustomObject]@{ code='non_revocable_pin_forbidden'; message='a residency_pin is ALWAYS revocable; -Revocable:$false on -Kind residency_pin is a hard STOP (finding 13).'; retryable=$false }
            }

            if ($isPrepared) {
                # ---- findings 2/15: prepared / evict-before-grant handoff (primitive layer; MOCK/command evictor seam) ----
                while ($true) {
                    $read = Read-LeaseFile $leasePath
                    $nowP = [DateTime]::UtcNow
                    if ($null -eq $read -or (Test-LeaseExpired $read $nowP)) {
                        # slot free/stale: no resident to evict -> confirm headroom via the seam (or trivially grant if none)
                        if ($EvictorMode -eq 'none') { $headroomConfirmed = $true; $evictorOutcome = 'free_no_evict_needed' }
                        else {
                            $ev = Invoke-Evictor $EvictorMode $MockEvictorResult $MockFreeVramMiB $EvictorCommand ([ordered]@{ resource=$Resource; required_vram_mib=$RequiredVramMiB; target_headroom_mib=$TargetHeadroomMiB; state='free'; confirm_interval_ms=$ConfirmIntervalMs; confirm_timeout_ms=$ConfirmTimeoutMs }) $RequiredVramMiB $TargetHeadroomMiB $ConfirmIntervalMs $ConfirmTimeoutMs
                            $headroomConfirmed = [bool]$ev.confirmed; $freeVram = $ev.free_vram_mib; $evictorOutcome = [string]$ev.outcome; $evictPerformed = [bool]$ev.evicted
                        }
                        if ($headroomConfirmed) {
                            $ftk = Mint-FencingToken $fencePath 0
                            $nowL = [DateTime]::UtcNow; $expiresAt = $nowL.AddSeconds($TtlSeconds)
                            $ext = [ordered]@{ fencing_token=$ftk; lease_kind=$Kind; priority=$Priority; revocable=$(if ($isPin) { $true } else { $false }); required_vram_mib=$RequiredVramMiB; revoked_by=$null }
                            $cand = New-LeaseObject $Resource $Holder $myLid $nowL $expiresAt $TtlSeconds 0 $Note $ext
                            $bytes = $utf8.GetBytes(($cand | ConvertTo-Json -Depth 6))
                            if ($null -eq $read) {
                                if (Try-CreateLease $leasePath $bytes) { $acquired=$true; $leaseObj=$cand; $fencingToken=$ftk; $prepared=$true; break }
                                if ([DateTime]::UtcNow -ge $deadline) { $acqReason='raced_lost'; break }
                                Start-Sleep -Milliseconds 20; continue
                            } else {
                                if (Grant-LeaseAtomic $leasePath $bytes) { $acquired=$true; $leaseObj=$cand; $fencingToken=$ftk; $prepared=$true; $reclaimedStale=$true }
                                else { $acqReason='seize_failed' }
                                break
                            }
                        } else { $acqReason='headroom_timeout'; break }
                    }
                    # slot occupied
                    $rHolder = [string](Prop $read.lease 'holder' '')
                    if ($rHolder -eq $Holder) {
                        $acquired=$true; $alreadyHeld=$true; $leaseObj=$read.lease; $myLid=[string](Prop $read.lease 'lease_id' $myLid); $fencingToken=[long](Prop $read.lease 'fencing_token' 0); $prepared=$true; $headroomConfirmed=$true; break
                    }
                    $rKind = [string](Prop $read.lease 'lease_kind' 'exec')
                    $rRev = [bool](Prop $read.lease 'revocable' $false)
                    $rPrio = [int](Prop $read.lease 'priority' 0)
                    if ($rKind -eq 'residency_pin' -and $rRev -and $rPrio -lt $Priority) {
                        # revoke the lower-priority pin, drive the evictor, then SEIZE (evict-before-grant)
                        $tq = Mint-FencingToken $fencePath 0
                        [void](Set-PinRevoked $leasePath $read $Holder $tq $Priority 'preempted_by_prepared_acquire')
                        $revokedPin = [ordered]@{ holder=$rHolder; lease_id=[string](Prop $read.lease 'lease_id' ''); prior_fencing_token=[long](Prop $read.lease 'fencing_token' 0); priority=$rPrio }
                        $ev = Invoke-Evictor $EvictorMode $MockEvictorResult $MockFreeVramMiB $EvictorCommand ([ordered]@{ resource=$Resource; required_vram_mib=$RequiredVramMiB; target_headroom_mib=$TargetHeadroomMiB; state='occupied'; resident_holder=$rHolder; resident_priority=$rPrio; confirm_interval_ms=$ConfirmIntervalMs; confirm_timeout_ms=$ConfirmTimeoutMs }) $RequiredVramMiB $TargetHeadroomMiB $ConfirmIntervalMs $ConfirmTimeoutMs
                        $headroomConfirmed=[bool]$ev.confirmed; $freeVram=$ev.free_vram_mib; $evictorOutcome=[string]$ev.outcome; $evictPerformed=[bool]$ev.evicted
                        if ($headroomConfirmed) {
                            $nowL=[DateTime]::UtcNow; $expiresAt=$nowL.AddSeconds($TtlSeconds)
                            $ext=[ordered]@{ fencing_token=$tq; lease_kind=$Kind; priority=$Priority; revocable=$(if ($isPin) { $true } else { $false }); required_vram_mib=$RequiredVramMiB; revoked_by=$null }
                            $cand=New-LeaseObject $Resource $Holder $myLid $nowL $expiresAt $TtlSeconds 0 $Note $ext
                            $bytes=$utf8.GetBytes(($cand | ConvertTo-Json -Depth 6))
                            if (Grant-LeaseAtomic $leasePath $bytes) { $acquired=$true; $leaseObj=$cand; $fencingToken=$tq; $prepared=$true }
                            else { $acqReason='seize_failed' }
                        } else { $acqReason='headroom_timeout' }
                        break
                    }
                    # incompatible resident (exec, or an equal/higher-priority pin): cannot preempt -- wait or busy
                    $heldBy=$rHolder; $heldExp=[string](Prop $read.lease 'expires_at_utc' '')
                    if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; continue }
                    $acqReason='held_incompatible'; break
                }
                $waitedMs = [int]([DateTime]::UtcNow - $now0).TotalMilliseconds
            }
            else {
                # ---- finding 13 (non-prepared): signal-revoke a lower-priority resident pin, THEN the classic loop ----
                if ($engagedNew -and $prioritySupplied) {
                    $rd0 = Read-LeaseFile $leasePath
                    if ($null -ne $rd0 -and -not $rd0.partial -and -not (Test-LeaseExpired $rd0 ([DateTime]::UtcNow))) {
                        $rH0=[string](Prop $rd0.lease 'holder' ''); $rK0=[string](Prop $rd0.lease 'lease_kind' 'exec'); $rR0=[bool](Prop $rd0.lease 'revocable' $false); $rP0=[int](Prop $rd0.lease 'priority' 0)
                        if ($rH0 -ne $Holder -and $rK0 -eq 'residency_pin' -and $rR0 -and $rP0 -lt $Priority) {
                            $tq0 = Mint-FencingToken $fencePath 0
                            [void](Set-PinRevoked $leasePath $rd0 $Holder $tq0 $Priority 'preempted_by_priority')
                            $revokedPin = [ordered]@{ holder=$rH0; lease_id=[string](Prop $rd0.lease 'lease_id' ''); prior_fencing_token=[long](Prop $rd0.lease 'fencing_token' 0); priority=$rP0 }
                        }
                    }
                }
                # ---- classic acquire loop (UNCHANGED v0.1 behavior) ----
                $iter = 0; $maxIter = 2000000
                while ($true) {
                    $iter++
                    if ($iter -gt $maxIter) { break }
                    $nowL = [DateTime]::UtcNow
                    $expiresAt = $nowL.AddSeconds($TtlSeconds)
                    $cand = New-LeaseObject $Resource $Holder $myLid $nowL $expiresAt $TtlSeconds 0 $Note
                    $bytes = $utf8.GetBytes(($cand | ConvertTo-Json -Depth 6))
                    if (Try-CreateLease $leasePath $bytes) { $acquired = $true; $leaseObj = $cand; break }

                    $read = Read-LeaseFile $leasePath
                    if ($null -eq $read) {
                        if ([DateTime]::UtcNow -ge $deadline) { break }
                        Start-Sleep -Milliseconds 20; continue
                    }
                    # same-holder live re-attach
                    if (-not $read.partial -and ([string](Prop $read.lease 'holder' '') -eq $Holder) -and -not (Test-LeaseExpired $read ([DateTime]::UtcNow))) {
                        $acquired = $true; $alreadyHeld = $true; $leaseObj = $read.lease
                        $myLid = [string](Prop $read.lease 'lease_id' $myLid); break
                    }
                    if (Test-LeaseExpired $read ([DateTime]::UtcNow)) {
                        # Race-safe reclaim. TWO guards make it correct under concurrent reclaimers:
                        #  (1) an atomic CLAIM marker keyed on the stale lease's identity serializes reclaim of THIS
                        #      stale lease (exactly one claimer at a time);
                        #  (2) RE-VERIFY before delete -- the claim winner re-reads the lease and only removes it if it
                        #      is STILL the same stale lease. So a straggler that later re-wins a re-created claim marker
                        #      re-reads, sees the now-fresh lease (different id), and aborts instead of destroying it.
                        #  A blind rename/delete (guard 1 alone) let a straggler delete the winner's fresh lease -> many winners.
                        $origId = if ($read.partial) { $null } else { [string](Prop $read.lease 'lease_id' '') }
                        $sid = (Get-StaleId $read) -replace '[^A-Za-z0-9._-]', '_'
                        $claimPath = "$leasePath.claim.$sid"
                        $claimBytes = $utf8.GetBytes("claim holder=$Holder lid=$myLid at=$([DateTime]::UtcNow.ToString('o'))")
                        if (Try-CreateLease $claimPath $claimBytes) {
                            try {
                                $again = Read-LeaseFile $leasePath
                                if ($null -eq $again) {
                                    # the stale lease vanished (freed) -> the slot is free: plain atomic create.
                                    # (Do NOT overwrite here -- a fresh acquirer may have just grabbed the free slot.)
                                    if (Try-CreateLease $leasePath $bytes) { $acquired = $true; $leaseObj = $cand; $reclaimedStale = $true }
                                } elseif ((Test-LeaseExpired $again ([DateTime]::UtcNow)) -and ($again.partial -or ([string](Prop $again.lease 'lease_id' '') -eq $origId))) {
                                    # STILL the same stale lease and I hold the claim -> ATOMIC REPLACE (write temp, Move overwrite).
                                    # No delete+create gap -> avoids the Windows pending-delete failure; retry transient AV/indexer locks.
                                    $tmp = "$leasePath.take-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
                                    [System.IO.File]::WriteAllBytes($tmp, $bytes)
                                    $moved = $false
                                    for ($mi = 0; $mi -lt 6 -and -not $moved; $mi++) {
                                        try { [System.IO.File]::Move($tmp, $leasePath, $true); $moved = $true } catch { Start-Sleep -Milliseconds 15 }
                                    }
                                    if ($moved) { $acquired = $true; $leaseObj = $cand; $reclaimedStale = $true }
                                    else { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
                                }
                                # else: replaced by a FRESH (or different) lease -> do NOT touch it; abort reclaim (loop -> see busy)
                            } finally { Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue }
                            if ($acquired) { break }
                            if ([DateTime]::UtcNow -ge $deadline) { break }
                            Start-Sleep -Milliseconds 20; continue
                        }
                        # another process is reclaiming this stale lease; clear a crashed claimer's stale marker + retry
                        $cm = [DateTime]::UtcNow
                        try { $cm = [System.IO.File]::GetLastWriteTimeUtc($claimPath) } catch { }
                        if ($cm.AddSeconds($PARTIAL_GRACE_SEC) -lt [DateTime]::UtcNow) { Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue; continue }
                        $heldBy = '<reclaiming>'; $heldExp = $null
                        if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50; continue }
                        break
                    }
                    # live, held by another
                    $heldBy = if ($read.partial) { '<writing>' } else { [string](Prop $read.lease 'holder' '') }
                    $heldExp = if ($read.partial) { $read.mtime.AddSeconds($PARTIAL_GRACE_SEC).ToString('o') } else { [string](Prop $read.lease 'expires_at_utc' '') }
                    if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; continue }
                    break
                }
                $waitedMs = [int]([DateTime]::UtcNow - $now0).TotalMilliseconds
                # ---- post-grant: mint + embed the fencing/kind fields on a FRESH grant (findings 1/13) ----
                if ($acquired -and -not $alreadyHeld -and ($engagedNew -or (Test-Path -LiteralPath $fencePath -PathType Leaf))) {
                    $fencingToken = Mint-FencingToken $fencePath 0
                    $ext = [ordered]@{ fencing_token=$fencingToken; lease_kind=$Kind; priority=$Priority; revocable=$(if ($isPin) { $true } else { $false }); required_vram_mib=$(if ($RequiredVramMiB -ge 0) { $RequiredVramMiB } else { 0 }); revoked_by=$null }
                    if ($engagedR1b) { $ext['gpu_authority_epoch']=$fencingToken; $ext['resident_generation']=$(if([string]::IsNullOrWhiteSpace($ResidentGeneration)){$null}else{$ResidentGeneration}); $ext['owner_id']=$OwnerId }
                    [void](Set-LeaseExt $leasePath $leaseObj $ext)
                } elseif ($acquired -and $alreadyHeld) {
                    $fencingToken = [long](Prop $leaseObj 'fencing_token' 0)
                }
            }

            # ---- build result (legacy fields byte-identical; new fields ONLY when the new surface is engaged) ----
            $result = [ordered]@{
                action = 'acquire'; resource = $Resource; acquired = $acquired
                lease_id = $(if ($acquired) { $myLid } else { $null })
                holder = $Holder
                expires_at_utc = $(if ($acquired -and $null -ne $leaseObj) { [string](Prop $leaseObj 'expires_at_utc' '') } else { $null })
                ttl_seconds = $TtlSeconds; waited_ms = $waitedMs
                reclaimed_stale = $reclaimedStale; already_held = $alreadyHeld
                held_by = $(if ($acquired) { $null } else { $heldBy })
                held_expires_at_utc = $(if ($acquired) { $null } else { $heldExp })
                lease_dir = $LeaseDir
            }
            if ($engagedNew) {
                $result['fencing_token'] = $fencingToken
                $result['lease_kind'] = $Kind
                $result['priority'] = $Priority
                $result['revocable'] = $(if ($isPin) { $true } else { $false })
                $result['revoked_by'] = $null
                if ($null -ne $revokedPin) { $result['revocation_signaled'] = $true; $result['revoked_pin'] = $revokedPin }
                if ($isPrepared) {
                    $result['prepared'] = $prepared
                    $result['required_vram_mib'] = $RequiredVramMiB
                    $result['target_headroom_mib'] = $TargetHeadroomMiB
                    $result['free_vram_mib'] = $freeVram
                    $result['evict_performed'] = $evictPerformed
                    $result['headroom_confirmed'] = $headroomConfirmed
                    $result['evictor_mode'] = $EvictorMode
                    $result['evictor_outcome'] = $evictorOutcome
                }
                if ($null -ne $lockOverride) { $result['lock_order_override'] = $lockOverride }
                if ($null -ne $acqReason) { $result['reason'] = $acqReason }
            }
            if ($engagedR1b) {
                # three-identity fencing surface (frontier review section 2): gpu_authority_epoch (= fencing_token),
                # exec_lease_id (= the exec lease_id), resident_generation (consumer-owned), owner_id.
                $result['gpu_authority_epoch'] = $fencingToken
                $result['exec_lease_id'] = $(if ($acquired -and $Kind -eq 'exec') { $myLid } else { $null })
                $result['resident_generation'] = $(if ([string]::IsNullOrWhiteSpace($ResidentGeneration)) { $null } else { $ResidentGeneration })
                $result['owner_id'] = $OwnerId
            }
            $normInputs = [ordered]@{ action='acquire'; resource=$Resource; holder=$Holder }
            if ($engagedNew) { $normInputs['kind'] = $Kind; if ($prioritySupplied) { $normInputs['priority'] = $Priority } }
            Write-Diag "acquire resource=$Resource acquired=$acquired reclaimed_stale=$reclaimedStale already_held=$alreadyHeld prepared=$prepared waited_ms=$waitedMs"
        }
        'release' {
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $read = Read-LeaseFile $leasePath
            $released = $false; $reason = $null; $heldBy = $null
            if ($null -eq $read) { $reason = 'not_held' }
            elseif ($read.partial) { $reason = 'lease_unreadable' }
            else {
                $curLid = [string](Prop $read.lease 'lease_id' '')
                $curHolder = [string](Prop $read.lease 'holder' '')
                $curToken = [long](Prop $read.lease 'fencing_token' 0)
                $heldBy = $curHolder
                $idMatch = (-not [string]::IsNullOrWhiteSpace($LeaseId)) -and ($LeaseId -eq $curLid)
                $holderMatch = [string]::IsNullOrWhiteSpace($LeaseId) -and ($Holder -eq $curHolder)
                if (($idMatch -or $holderMatch) -and $fencingTokenSupplied -and ($FencingToken -ne $curToken)) {
                    # v0.2 CAS guard: a superseded holder (stale token) is FENCED OUT of releasing the current lease
                    $reason = 'fence_stale'
                } elseif ($idMatch -or $holderMatch) {
                    try { Remove-Item -LiteralPath $leasePath -Force; $released = $true } catch { $reason = 'delete_failed' }
                } else { $reason = 'lease_mismatch' }
            }
            $result = [ordered]@{ action='release'; resource=$Resource; released=$released; reason=$reason; held_by=$heldBy; lease_dir=$LeaseDir }
            $normInputs = [ordered]@{ action='release'; resource=$Resource; lease_id=$LeaseId }
            Write-Diag "release resource=$Resource released=$released reason=$reason"
        }
        'renew' {
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $read = Read-LeaseFile $leasePath
            $renewed = $false; $reason = $null; $heldBy = $null; $newExp = $null; $renewCount = $null
            $curToken = $null; $revokedBy = $null
            if ($null -eq $read) { $reason = 'not_held' }
            elseif ($read.partial) { $reason = 'lease_unreadable' }
            else {
                $curLid = [string](Prop $read.lease 'lease_id' '')
                $heldBy = [string](Prop $read.lease 'holder' '')
                $isFenced = (Has $read.lease 'fencing_token')
                $curToken = [long](Prop $read.lease 'fencing_token' 0)
                $revokedBy = Prop $read.lease 'revoked_by' $null
                if ((-not [string]::IsNullOrWhiteSpace($LeaseId)) -and ($LeaseId -eq $curLid)) {
                    if ($fencingTokenSupplied -and ($FencingToken -ne $curToken)) {
                        $reason = 'fence_stale'   # a superseded holder cannot renew
                    } elseif ($null -ne $revokedBy) {
                        $reason = 'revoked'       # a higher-priority acquire revoked this pin -> authority LOST
                    } else {
                        $nowR = [DateTime]::UtcNow
                        $newExpiresAt = $nowR.AddSeconds($TtlSeconds)
                        $prevCount = 0; try { $prevCount = [int](Prop $read.lease 'renew_count' 0) } catch { $prevCount = 0 }
                        $renewCount = $prevCount + 1
                        $acqAt = ConvertTo-Utc (Prop $read.lease 'acquired_at_utc' $null)
                        if ($null -eq $acqAt) { $acqAt = $nowR }
                        # preserve the v0.2 ext fields (same fencing_token) on a fenced lease; byte-identical otherwise
                        $rExt = $null
                        if ($isFenced) {
                            $rExt = [ordered]@{
                                fencing_token     = $curToken
                                lease_kind        = [string](Prop $read.lease 'lease_kind' 'exec')
                                priority          = [int](Prop $read.lease 'priority' 0)
                                revocable         = [bool](Prop $read.lease 'revocable' $false)
                                required_vram_mib = [int](Prop $read.lease 'required_vram_mib' 0)
                                revoked_by        = $null
                            }
                        }
                        $updated = New-LeaseObject $Resource $heldBy $curLid $acqAt $newExpiresAt $TtlSeconds $renewCount ([string](Prop $read.lease 'note' '')) $rExt
                        $tmp = "$leasePath.renew-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
                        [System.IO.File]::WriteAllText($tmp, ($updated | ConvertTo-Json -Depth 6), $utf8)
                        try {
                            [System.IO.File]::Move($tmp, $leasePath, $true)   # atomic replace
                            $renewed = $true; $newExp = $newExpiresAt.ToString('o')
                        } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; $reason = 'renew_write_failed' }
                    }
                } else { $reason = 'lease_lost' }
            }
            $result = [ordered]@{ action='renew'; resource=$Resource; renewed=$renewed; lease_id=$(if($renewed){$LeaseId}else{$null}); expires_at_utc=$newExp; renew_count=$renewCount; reason=$reason; held_by=$heldBy; lease_dir=$LeaseDir }
            if ($engagedNew -or ($reason -eq 'fence_stale') -or ($reason -eq 'revoked')) {
                $result['fencing_token'] = $curToken
                $result['revoked_by'] = $revokedBy
            }
            $normInputs = [ordered]@{ action='renew'; resource=$Resource; lease_id=$LeaseId }
            Write-Diag "renew resource=$Resource renewed=$renewed reason=$reason"
        }
        'status' {
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $read = Read-LeaseFile $leasePath
            $nowS = [DateTime]::UtcNow
            if ($null -eq $read) {
                $result = [ordered]@{ action='status'; resource=$Resource; exists=$false; held=$false; stale=$false; holder=$null; lease_id=$null; expires_at_utc=$null; seconds_remaining=$null; lease_dir=$LeaseDir }
                if ($engagedNew) { $result['fencing_token']=$null; $result['lease_kind']=$null; $result['revocable']=$null; $result['revoked_by']=$null; $result['priority']=$null }
            } else {
                $stale = Test-LeaseExpired $read $nowS
                $exp = $(if ($read.partial) { $null } else { ConvertTo-Utc (Prop $read.lease 'expires_at_utc' $null) })
                $secRem = $(if ($null -ne $exp) { [int]($exp - $nowS).TotalSeconds } else { $null })
                $result = [ordered]@{
                    action='status'; resource=$Resource; exists=$true; held=(-not $stale); stale=$stale
                    holder=$(if ($read.partial) { '<writing>' } else { [string](Prop $read.lease 'holder' '') })
                    lease_id=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'lease_id' '') })
                    expires_at_utc=$(if ($null -ne $exp) { $exp.ToString('o') } else { $null })
                    seconds_remaining=$secRem; lease_dir=$LeaseDir
                }
                if ($engagedNew) {
                    $result['fencing_token']=$(if ($read.partial) { $null } else { [long](Prop $read.lease 'fencing_token' 0) })
                    $result['lease_kind']=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'lease_kind' 'exec') })
                    $result['revocable']=$(if ($read.partial) { $null } else { [bool](Prop $read.lease 'revocable' $false) })
                    $result['revoked_by']=$(if ($read.partial) { $null } else { Prop $read.lease 'revoked_by' $null })
                    $result['priority']=$(if ($read.partial) { $null } else { [int](Prop $read.lease 'priority' 0) })
                }
            }
            $normInputs = [ordered]@{ action='status'; resource=$Resource }
            Write-Diag "status resource=$Resource exists=$($result.exists) held=$($result.held)"
        }
        'check' {
            # v0.2 fencing-validation surface: does the caller's -FencingToken still command this resource?
            # v0.3: -Reconcile rolls a crashed transition journal to ABORTED (supervisor/watchdog crash recovery).
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $fencePath = Join-Path $LeaseDir (Get-FenceFileName $Resource)
            $txnPath = Join-Path $LeaseDir (Get-TxnFileName $Resource)
            $checkReconcile = $(if ($doReconcile) { Reconcile-Txn $txnPath $fencePath $PARTIAL_GRACE_SEC } else { $null })
            $read = Read-LeaseFile $leasePath
            $nowC = [DateTime]::UtcNow
            if ($null -eq $read) {
                $result = [ordered]@{ action='check'; resource=$Resource; exists=$false; held=$false; stale=$false; holder=$null; lease_id=$null; fencing_token=$null; lease_kind=$null; revocable=$null; revoked_by=$null; priority=$null; expires_at_utc=$null; seconds_remaining=$null; token_current=$(if ($fencingTokenSupplied) { $false } else { $null }); fence_status='not_held'; lease_dir=$LeaseDir }
                if ($engagedR1b) { $result['gpu_authority_epoch']=$null; $result['exec_lease_id']=$null; $result['resident_generation']=$null; $result['owner_id']=$null; $result['owner_current']=$false; $result['generation_current']=$false; $result['authority_ok']=$false }
            } elseif ($read.partial) {
                $result = [ordered]@{ action='check'; resource=$Resource; exists=$true; held=$true; stale=$false; holder='<writing>'; lease_id=$null; fencing_token=$null; lease_kind=$null; revocable=$null; revoked_by=$null; priority=$null; expires_at_utc=$null; seconds_remaining=$null; token_current=$(if ($fencingTokenSupplied) { $false } else { $null }); fence_status='writing'; lease_dir=$LeaseDir }
                if ($engagedR1b) { $result['gpu_authority_epoch']=$null; $result['exec_lease_id']=$null; $result['resident_generation']=$null; $result['owner_id']=$null; $result['owner_current']=$false; $result['generation_current']=$false; $result['authority_ok']=$false }
            } else {
                $stale = Test-LeaseExpired $read $nowC
                $exp = ConvertTo-Utc (Prop $read.lease 'expires_at_utc' $null)
                $curToken = [long](Prop $read.lease 'fencing_token' 0)
                $revokedBy = Prop $read.lease 'revoked_by' $null
                $fenceStatus = 'current'
                if ($stale) { $fenceStatus = 'stale' } elseif ($null -ne $revokedBy) { $fenceStatus = 'revoked' }
                $tokCur = $null
                if ($fencingTokenSupplied) {
                    $tokCur = ((-not $stale) -and ($null -eq $revokedBy) -and ($FencingToken -eq $curToken))
                    if ((-not $tokCur) -and ($fenceStatus -eq 'current')) { $fenceStatus = 'fence_stale' }
                }
                $result = [ordered]@{
                    action='check'; resource=$Resource; exists=$true; held=(-not $stale); stale=$stale
                    holder=[string](Prop $read.lease 'holder' ''); lease_id=[string](Prop $read.lease 'lease_id' '')
                    fencing_token=$curToken; lease_kind=[string](Prop $read.lease 'lease_kind' 'exec')
                    revocable=[bool](Prop $read.lease 'revocable' $false); revoked_by=$revokedBy
                    priority=[int](Prop $read.lease 'priority' 0)
                    expires_at_utc=$(if ($null -ne $exp) { $exp.ToString('o') } else { $null })
                    seconds_remaining=$(if ($null -ne $exp) { [int]($exp - $nowC).TotalSeconds } else { $null })
                    token_current=$tokCur; fence_status=$fenceStatus; lease_dir=$LeaseDir
                }
                if ($engagedR1b) {
                    # ---- three-identity full-tuple assertion: owner_id + gpu_authority_epoch + resident_generation + exec_lease_id ----
                    $rGen = [string](Prop $read.lease 'resident_generation' '')
                    $rOwner = [string](Prop $read.lease 'owner_id' '')
                    $ownerIdSupplied = $bound.ContainsKey('OwnerId') -or $jsonOwnerId
                    $residentGenSupplied = $bound.ContainsKey('ResidentGeneration') -or $jsonResidentGen
                    $live = ((-not $stale) -and ($null -eq $revokedBy))
                    $ownerCur = $(if ($ownerIdSupplied) { ($live -and ($OwnerId -eq $rOwner)) } else { $null })
                    $genCur   = $(if ($residentGenSupplied) { ($live -and ($ResidentGeneration -eq $rGen)) } else { $null })
                    $authorityOk = $live
                    if ($fencingTokenSupplied) { $authorityOk = ($authorityOk -and [bool]$tokCur) }
                    if ($ownerIdSupplied)      { $authorityOk = ($authorityOk -and [bool]$ownerCur) }
                    if ($residentGenSupplied)  { $authorityOk = ($authorityOk -and [bool]$genCur) }
                    $result['gpu_authority_epoch'] = $curToken
                    $result['exec_lease_id'] = [string](Prop $read.lease 'lease_id' '')
                    $result['resident_generation'] = $(if ([string]::IsNullOrWhiteSpace($rGen)) { $null } else { $rGen })
                    $result['owner_id'] = $(if ([string]::IsNullOrWhiteSpace($rOwner)) { $null } else { $rOwner })
                    $result['owner_current'] = $ownerCur
                    $result['generation_current'] = $genCur
                    $result['authority_ok'] = $authorityOk
                }
            }
            if ($null -ne $checkReconcile) { $result['reconciled'] = $checkReconcile }
            $normInputs = [ordered]@{ action='check'; resource=$Resource }
            Write-Diag "check resource=$Resource exists=$($result.exists) fence_status=$($result.fence_status)"
        }
        'list' {
            $nowLst = [DateTime]::UtcNow
            $leases = New-Object System.Collections.Generic.List[object]
            $files = @(Get-ChildItem -LiteralPath $LeaseDir -Filter '*.lease' -File -ErrorAction SilentlyContinue)
            foreach ($f in $files) {
                $read = Read-LeaseFile $f.FullName
                if ($null -eq $read) { continue }
                $stale = Test-LeaseExpired $read $nowLst
                $exp = $(if ($read.partial) { $null } else { ConvertTo-Utc (Prop $read.lease 'expires_at_utc' $null) })
                $row = [ordered]@{
                    resource=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'resource' '') })
                    holder=$(if ($read.partial) { '<writing>' } else { [string](Prop $read.lease 'holder' '') })
                    lease_id=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'lease_id' '') })
                    expires_at_utc=$(if ($null -ne $exp) { $exp.ToString('o') } else { $null })
                    held=(-not $stale); stale=$stale
                    seconds_remaining=$(if ($null -ne $exp) { [int]($exp - $nowLst).TotalSeconds } else { $null })
                    file=$f.Name
                }
                if ($engagedNew -and -not $read.partial) {
                    $row['fencing_token'] = [long](Prop $read.lease 'fencing_token' 0)
                    $row['lease_kind'] = [string](Prop $read.lease 'lease_kind' 'exec')
                    $row['revocable'] = [bool](Prop $read.lease 'revocable' $false)
                    $row['revoked_by'] = Prop $read.lease 'revoked_by' $null
                    $row['priority'] = [int](Prop $read.lease 'priority' 0)
                }
                $leases.Add($row)
            }
            $result = [ordered]@{ action='list'; lease_dir=$LeaseDir; count=$leases.Count; leases=$leases.ToArray() }
            $normInputs = [ordered]@{ action='list'; lease_dir=$LeaseDir }
            Write-Diag "list lease_dir=$LeaseDir count=$($leases.Count)"
        }
    }

    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code=[string]$ex.code; message=[string]$ex.message; retryable=[bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts: reslease.json + reslease.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $rj = [ordered]@{ schema='lifeorch.res.lease.result/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $rjPath = Join-Path $invDir 'reslease.json'
        [System.IO.File]::WriteAllText($rjPath, ($rj | ConvertTo-Json -Depth 20), $utf8)
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# res.lease -- $($result.action)")
        [void]$mb.AppendLine('')
        foreach ($k in $result.Keys) {
            $v = $result.$k
            if ($k -eq 'leases') { [void]$mb.AppendLine("- **${k}:** $(@($v).Count) lease(s)") }
            else { [void]$mb.AppendLine("- **${k}:** $v") }
        }
        [void]$mb.AppendLine('')
        $mdPath = Join-Path $invDir 'reslease.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        foreach ($a in @([pscustomobject]@{ p=$rjPath; k='json' }, [pscustomobject]@{ p=$mdPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [byte[]]([System.IO.File]::ReadAllBytes($a.p))
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[res.lease] invocation $InvocationId action=$Action status=$status`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$null; artifacts=$artifacts; model_provenance=@()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
