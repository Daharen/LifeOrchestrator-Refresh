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

  CONVENTIONAL RESOURCE NAMES (any string works; these are the documented ones):
    gpu          -- the single GPU / model-server / diffusers-pipeline lease (model modules are parallel_safe:false).
    git          -- the git index/commit lock (dev.ship + any git write).
    doc:<path>   -- doc-ownership for a shared core-doc edit (e.g. doc:CURRENT_STATE.md).

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
  pwsh -NoProfile -File .\Invoke-ResLease.ps1 -InputsJson '{"action":"acquire","resource":"git","wait_seconds":10}'
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
    [string]$LeaseDir,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'res.lease'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$LEASE_SCHEMA = 'lifeorch.res.lease/0.1'
$PARTIAL_GRACE_SEC = 15   # an unparseable/empty lease (a partial write) is reclaimable at mtime + this
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

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
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind -bor [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
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
# Identity of a stale lease, so concurrent reclaimers of the SAME stale lease compute the SAME claim marker.
function Get-StaleId($read) {
    if ($read.partial) { return "partial-$($read.mtime.Ticks)" }
    $lid = [string](Prop $read.lease 'lease_id' '')
    if ([string]::IsNullOrWhiteSpace($lid)) { return "x-$($read.mtime.Ticks)" }
    return $lid
}
function New-LeaseObject([string]$resource, [string]$holder, [string]$lid, [DateTime]$acquiredAt, [DateTime]$expiresAt, [int]$ttl, [int]$renewCount, [string]$note) {
    return [ordered]@{
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
        }
    }

    if ([string]::IsNullOrWhiteSpace($Action)) { throw [PSCustomObject]@{ code='missing_parameter'; message='action is required (acquire|release|renew|status|list)'; retryable=$false } }
    $Action = $Action.ToLowerInvariant()
    if (@('acquire','release','renew','status','list') -notcontains $Action) { throw [PSCustomObject]@{ code='invalid_action'; message="action must be acquire|release|renew|status|list (got '$Action')"; retryable=$false } }
    if ($Action -ne 'list' -and [string]::IsNullOrWhiteSpace($Resource)) { throw [PSCustomObject]@{ code='missing_parameter'; message="$Action needs a resource"; retryable=$false } }
    if ($TtlSeconds -lt 1) { $TtlSeconds = 1 }

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
            $now0 = [DateTime]::UtcNow
            $deadline = $now0.AddSeconds([Math]::Max(0, $WaitSeconds))
            $myLid = [Guid]::NewGuid().ToString()
            $acquired = $false; $alreadyHeld = $false; $reclaimedStale = $false
            $heldBy = $null; $heldExp = $null; $leaseObj = $null
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
            $normInputs = [ordered]@{ action='acquire'; resource=$Resource; holder=$Holder }
            Write-Diag "acquire resource=$Resource acquired=$acquired reclaimed_stale=$reclaimedStale already_held=$alreadyHeld waited_ms=$waitedMs"
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
                $heldBy = $curHolder
                $idMatch = (-not [string]::IsNullOrWhiteSpace($LeaseId)) -and ($LeaseId -eq $curLid)
                $holderMatch = [string]::IsNullOrWhiteSpace($LeaseId) -and ($Holder -eq $curHolder)
                if ($idMatch -or $holderMatch) {
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
            if ($null -eq $read) { $reason = 'not_held' }
            elseif ($read.partial) { $reason = 'lease_unreadable' }
            else {
                $curLid = [string](Prop $read.lease 'lease_id' '')
                $heldBy = [string](Prop $read.lease 'holder' '')
                if ((-not [string]::IsNullOrWhiteSpace($LeaseId)) -and ($LeaseId -eq $curLid)) {
                    $nowR = [DateTime]::UtcNow
                    $newExpiresAt = $nowR.AddSeconds($TtlSeconds)
                    $prevCount = 0; try { $prevCount = [int](Prop $read.lease 'renew_count' 0) } catch { $prevCount = 0 }
                    $renewCount = $prevCount + 1
                    $acqAt = ConvertTo-Utc (Prop $read.lease 'acquired_at_utc' $null)
                    if ($null -eq $acqAt) { $acqAt = $nowR }
                    $updated = New-LeaseObject $Resource $heldBy $curLid $acqAt $newExpiresAt $TtlSeconds $renewCount ([string](Prop $read.lease 'note' ''))
                    $tmp = "$leasePath.renew-$([Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
                    [System.IO.File]::WriteAllText($tmp, ($updated | ConvertTo-Json -Depth 6), $utf8)
                    try {
                        [System.IO.File]::Move($tmp, $leasePath, $true)   # atomic replace
                        $renewed = $true; $newExp = $newExpiresAt.ToString('o')
                    } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; $reason = 'renew_write_failed' }
                } else { $reason = 'lease_lost' }
            }
            $result = [ordered]@{ action='renew'; resource=$Resource; renewed=$renewed; lease_id=$(if($renewed){$LeaseId}else{$null}); expires_at_utc=$newExp; renew_count=$renewCount; reason=$reason; held_by=$heldBy; lease_dir=$LeaseDir }
            $normInputs = [ordered]@{ action='renew'; resource=$Resource; lease_id=$LeaseId }
            Write-Diag "renew resource=$Resource renewed=$renewed reason=$reason"
        }
        'status' {
            $leasePath = Join-Path $LeaseDir (Get-LeaseFileName $Resource)
            $read = Read-LeaseFile $leasePath
            $nowS = [DateTime]::UtcNow
            if ($null -eq $read) {
                $result = [ordered]@{ action='status'; resource=$Resource; exists=$false; held=$false; stale=$false; holder=$null; lease_id=$null; expires_at_utc=$null; seconds_remaining=$null; lease_dir=$LeaseDir }
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
            }
            $normInputs = [ordered]@{ action='status'; resource=$Resource }
            Write-Diag "status resource=$Resource exists=$($result.exists) held=$($result.held)"
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
                $leases.Add([ordered]@{
                    resource=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'resource' '') })
                    holder=$(if ($read.partial) { '<writing>' } else { [string](Prop $read.lease 'holder' '') })
                    lease_id=$(if ($read.partial) { $null } else { [string](Prop $read.lease 'lease_id' '') })
                    expires_at_utc=$(if ($null -ne $exp) { $exp.ToString('o') } else { $null })
                    held=(-not $stale); stale=$stale
                    seconds_remaining=$(if ($null -ne $exp) { [int]($exp - $nowLst).TotalSeconds } else { $null })
                    file=$f.Name
                })
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
