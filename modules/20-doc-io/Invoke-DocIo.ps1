#requires -Version 7.0
<#
.SYNOPSIS
    doc.io -- Local Document I/O (read / write / edit / append). Life Orchestrator Module 20.

.DESCRIPTION
    A small, DETERMINISTIC document primitive that local models (and the escalator / a local
    orchestrator / Widgets / unattended executor tasks) call to read, write, edit, and append
    UTF-8 text documents on this machine. One operation per invocation (-Op read|write|edit|append).

    Contract: emits a single lifeorch.skill.result/0.1 envelope on stdout (and result.json in the
    artifact dir); diagnostics go to stderr / stderr.txt. determinism="deterministic" (confidence
    null, empty model_provenance, NOT a review-queue producer). Not a model; uses only pwsh + .NET.

    Safety: writes are ATOMIC (temp file in the same directory, then rename over the target); an
    optional -ExpectSha256 optimistic-concurrency precondition guards read-modify-write loops; every
    mutation copies the prior content into the artifact dir as before.<ext> (recoverable pre-image).
    EOL is preserved on edit/append (a CRLF file stays CRLF); byte-level I/O keeps behavior identical
    on Windows and Linux (no Environment.NewLine / Set-Content / Out-File).

.NOTES
    skill_id doc.io | version 0.1.0 | contract_version 0.2 | parallel_safe:false | batch:false
#>
[CmdletBinding()]
param(
    [string]$Op,
    [string]$Path,
    [string]$Content,
    [string]$OldString,
    [string]$NewString,
    [switch]$ReplaceAll,
    [int]$ExpectCount,
    [int]$StartLine,
    [int]$EndLine,
    [int]$MaxBytes,
    [string]$Eol,
    [bool]$Overwrite,
    [bool]$CreateDirs,
    [bool]$Create,
    [bool]$EnsureNewline,
    [string]$Encoding,
    [string]$ExpectSha256,
    [switch]$NoPreimage,
    [string]$ArtifactRoot,
    [string]$InputsJson,
    # --- doc:<path> lease wiring (res.lease #29); opt-in, serializes concurrent editors ---
    [switch]$Lease,                  # opt-in: acquire res.lease doc:<relpath> around write/edit/append
    [int]$LeaseWaitSeconds = 120,    # blocking wait budget for the doc lease
    [int]$LeaseTtlSeconds = 300,     # lease TTL (doc ops are quick; renew not needed)
    [string]$LeaseHolder,            # default $env:LIFEORCH_INSTANCE else doc.io:<pid>
    [string]$LeaseResource,          # override the auto doc:<relpath> resource name
    [string]$LeaseDir,               # shared lease dir passthrough (all coordinators must agree)
    [string]$ResLeasePath,           # override path to Invoke-ResLease.ps1 (default: auto-resolve)
    [string]$PwshPath                # pwsh used to spawn res.lease (default: resolve via PATH)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Bootstrap: invocation id, artifact dir, diagnostics buffer
# ---------------------------------------------------------------------------
$Bound = $PSBoundParameters
$script:Diag = [System.Collections.Generic.List[string]]::new()
function Add-Diag([string]$m) { $script:Diag.Add(("{0}  {1}" -f ([DateTime]::UtcNow.ToString('o')), $m)) | Out-Null }

$invocationId = [guid]::NewGuid().ToString()
$startedAt = [DateTime]::UtcNow

if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $artDir = Join-Path (Join-Path (Join-Path $PSScriptRoot 'runtime') 'artifacts') $invocationId
} else {
    $artDir = Join-Path $ArtifactRoot $invocationId
}
try { New-Item -ItemType Directory -Force -Path $artDir | Out-Null } catch {
    New-Item -ItemType Directory -Force -Path $artDir -ErrorAction SilentlyContinue | Out-Null
}
Add-Diag "doc.io start invocation_id=$invocationId artDir=$artDir"

# ---------------------------------------------------------------------------
# Input resolution: -InputsJson merged with named params (named param wins, per SKILL_CONTRACT 3.1)
# ---------------------------------------------------------------------------
$inputs = @{}
if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
    try {
        $parsed = $InputsJson | ConvertFrom-Json -ErrorAction Stop
        foreach ($p in $parsed.PSObject.Properties) { $inputs[$p.Name] = $p.Value }
        Add-Diag ("InputsJson parsed keys=" + (($inputs.Keys) -join ','))
    } catch {
        Add-Diag "InputsJson parse FAILED: $($_.Exception.Message)"
    }
}

function ConvertTo-BoolSafe($v, [bool]$default) {
    if ($null -eq $v) { return $default }
    if ($v -is [bool]) { return $v }
    if ($v -is [System.Management.Automation.SwitchParameter]) { return $v.IsPresent }
    $s = ([string]$v).Trim().ToLowerInvariant()
    if ($s -in @('true','1','yes','y','on'))  { return $true }
    if ($s -in @('false','0','no','n','off','')) { return $false }
    return $default
}
function ConvertTo-IntSafe($v, [int]$default) {
    if ($null -eq $v) { return $default }
    try { return [int]$v } catch { return $default }
}

function Resolve-Str([string]$paramName, [string]$key, $default) {
    if ($Bound.ContainsKey($paramName)) { return [string]$Bound[$paramName] }
    if ($inputs.ContainsKey($key) -and $null -ne $inputs[$key]) { return [string]$inputs[$key] }
    return $default
}
function Resolve-Bool([string]$paramName, [string]$key, [bool]$default) {
    if ($Bound.ContainsKey($paramName)) { return ConvertTo-BoolSafe $Bound[$paramName] $default }
    if ($inputs.ContainsKey($key)) { return ConvertTo-BoolSafe $inputs[$key] $default }
    return $default
}
function Resolve-Int([string]$paramName, [string]$key, [int]$default) {
    if ($Bound.ContainsKey($paramName)) { return ConvertTo-IntSafe $Bound[$paramName] $default }
    if ($inputs.ContainsKey($key)) { return ConvertTo-IntSafe $inputs[$key] $default }
    return $default
}
function Has-Value([string]$paramName, [string]$key) {
    if ($Bound.ContainsKey($paramName)) { return $true }
    if ($inputs.ContainsKey($key) -and $null -ne $inputs[$key]) { return $true }
    return $false
}

# ---------------------------------------------------------------------------
# Byte / text helpers (explicit; cross-platform)
# ---------------------------------------------------------------------------
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

# Detect BOM -> encoding descriptor @{ name; bom; bomLen }
function Get-EncodingInfo([byte[]]$bytes) {
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ name = 'utf-8'; bom = $true; bomLen = 3 }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{ name = 'utf-16le'; bom = $true; bomLen = 2 }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return @{ name = 'utf-16be'; bom = $true; bomLen = 2 }
    }
    return @{ name = 'utf-8'; bom = $false; bomLen = 0 }
}

# Binary if it has a NUL byte and is not BOM'd UTF-16 (where NULs are normal).
function Test-IsBinary([byte[]]$bytes, $encInfo) {
    if ($encInfo.name -like 'utf-16*') { return $false }
    $limit = [Math]::Min($bytes.Length, 65536)
    for ($i = 0; $i -lt $limit; $i++) { if ($bytes[$i] -eq 0) { return $true } }
    return $false
}

function ConvertFrom-Bytes([byte[]]$bytes, $encInfo) {
    $len = $bytes.Length - $encInfo.bomLen
    if ($len -le 0) { return '' }
    switch ($encInfo.name) {
        'utf-16le' { return ([System.Text.UnicodeEncoding]::new($false, $false)).GetString($bytes, $encInfo.bomLen, $len) }
        'utf-16be' { return ([System.Text.UnicodeEncoding]::new($true, $false)).GetString($bytes, $encInfo.bomLen, $len) }
        default    { return ([System.Text.UTF8Encoding]::new($false, $false)).GetString($bytes, $encInfo.bomLen, $len) }
    }
}

# Encode text -> bytes for the given descriptor. $emitBom controls whether the BOM is prepended.
# Always returns a genuine [byte[]] (leading-comma return + no @() at call sites).
function ConvertTo-Bytes([string]$text, $encInfo, [bool]$emitBom) {
    if ($null -eq $text) { $text = '' }
    [byte[]]$body = switch ($encInfo.name) {
        'utf-16le' { ([System.Text.UnicodeEncoding]::new($false, $false)).GetBytes($text) }
        'utf-16be' { ([System.Text.UnicodeEncoding]::new($true, $false)).GetBytes($text) }
        default    { ([System.Text.UTF8Encoding]::new($false, $false)).GetBytes($text) }
    }
    [byte[]]$bom = @()
    if ($emitBom) {
        [byte[]]$bom = switch ($encInfo.name) {
            'utf-16le' { @(0xFF, 0xFE) }
            'utf-16be' { @(0xFE, 0xFF) }
            default    { @(0xEF, 0xBB, 0xBF) }
        }
    }
    $out = New-Object byte[] ($bom.Length + $body.Length)
    if ($bom.Length -gt 0) { [System.Array]::Copy($bom, 0, $out, 0, $bom.Length) }
    [System.Array]::Copy($body, 0, $out, $bom.Length, $body.Length)
    return ,$out
}

function Get-Eol([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return 'none' }
    $crlf = ([regex]::Matches($text, "`r`n")).Count
    $lfTotal = ([regex]::Matches($text, "`n")).Count
    $loneLf = $lfTotal - $crlf
    if ($lfTotal -eq 0) { return 'none' }
    if ($loneLf -eq 0) { return 'crlf' }
    if ($crlf -eq 0) { return 'lf' }
    return 'mixed'
}
function ConvertTo-Lf([string]$text) {
    if ($null -eq $text) { return '' }
    return $text.Replace("`r`n", "`n").Replace("`r", "`n")
}
function Set-Eol([string]$lfText, [string]$eol) {
    # $lfText is LF-normalized. Return with the requested convention.
    if ($eol -eq 'crlf') { return $lfText.Replace("`n", "`r`n") }
    return $lfText   # lf / none / mixed => LF
}
function Get-LineCount([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return 0 }
    $lf = ConvertTo-Lf $text
    $n = ([regex]::Matches($lf, "`n")).Count
    if (-not $lf.EndsWith("`n")) { $n = $n + 1 }
    return $n
}
function Get-EffectiveEol([string]$eol) {
    # For writing back: uniform crlf stays crlf; everything else becomes lf.
    if ($eol -eq 'crlf') { return 'crlf' }
    return 'lf'
}

function Write-AtomicBytes([string]$targetPath, [byte[]]$bytes) {
    $dir = [System.IO.Path]::GetDirectoryName($targetPath)
    if ([string]::IsNullOrEmpty($dir)) { $dir = (Get-Location).Path }
    $tmp = Join-Path $dir ('.docio-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        [System.IO.File]::Move($tmp, $targetPath, $true)
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Resolve-AbsPath([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return [System.IO.Path]::GetFullPath($p) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $p))
}
function Get-ArtExt([string]$targetPath) {
    $e = [System.IO.Path]::GetExtension($targetPath)
    if ([string]::IsNullOrEmpty($e)) { return '.txt' }
    if ($e.Length -gt 12) { return '.txt' }
    return $e
}

$PreimageMaxBytes = 8000000  # skip the pre-image copy for files larger than ~8 MB

# ---------------------------------------------------------------------------
# res.lease (#29) integration: opt-in doc:<path> lease to serialize concurrent editors of the same
# target. CPU-only. Graceful (warn + proceed) when res.lease is absent/errors; released on every emit.
# ---------------------------------------------------------------------------
$script:DocLease = $null

function Get-PwshExe([string]$override) {
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }
    if (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_PWSH)) { return $env:LIFEORCH_PWSH }
    try { $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c -and $c.Source) { return $c.Source } } catch { }
    try { $mm = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName; if ($mm -match '(?i)pwsh') { return $mm } } catch { }
    return 'pwsh'
}
function Resolve-RepoRootDoc([string]$start) {
    # ORIGINAL core-docs walk-up (unchanged) -- the trusted, byte-identical result on this box.
    $wu = $null
    try {
        $d = Get-Item -LiteralPath $start
        for ($i = 0; $i -lt 8 -and $null -ne $d; $i++) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'core-docs')) { $wu = $d.FullName; break }
            $d = $d.Parent
        }
    } catch { }
    # ADDITIVE portability seam (FANOUT_AGENT_002, i16 plan fo-16-f125365c; the same additive+fallback
    # shim wired into modules/14 + 16 at i15): let a machine config / env override -- ops/setup/config.json
    # or $env:LIFEORCH_REPO_ROOT, resolved via Resolve-LifeorchConfig -- WIN only when it points at a real,
    # DIFFERENT repo (a relocated checkout on a new box). Otherwise keep the walk-up. Byte-identical here
    # (config repo_root == the walk-up), reversible, and fail-closed to the walk-up on ANY error. ASCII-only.
    try {
        $probe = if ($null -ne $wu) { $wu } else { $start }
        $p = Get-Item -LiteralPath $probe -ErrorAction Stop
        for ($k = 0; $k -lt 8 -and $null -ne $p; $k++) {
            $cfgMod = Join-Path $p.FullName 'ops\setup\LifeorchConfig.psm1'
            if (Test-Path -LiteralPath $cfgMod -PathType Leaf) {
                Import-Module $cfgMod -DisableNameChecking -Force -ErrorAction Stop
                $rr = [string](Resolve-LifeorchConfig).repo_root
                $rrValid = $false
                if (-not [string]::IsNullOrWhiteSpace($rr)) {
                    try { $rrValid = [bool](Test-Path -LiteralPath ([System.IO.Path]::Combine($rr, 'core-docs')) -ErrorAction Stop) } catch { $rrValid = $false }
                }
                if ($rrValid) {
                    $rrn = (Get-Item -LiteralPath $rr).FullName
                    if ($null -eq $wu -or $rrn -ne $wu) { return $rrn }
                }
                break
            }
            $p = $p.Parent
        }
    } catch { }
    return $wu
}
function Resolve-ResLeaseScript([string]$override) {
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if (Test-Path -LiteralPath $override -PathType Leaf) { return (Resolve-Path -LiteralPath $override).Path }
        return $null
    }
    $root = Resolve-RepoRootDoc $PSScriptRoot
    if ($null -ne $root) {
        $cand = Join-Path $root 'modules/29-resource-lease/Invoke-ResLease.ps1'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { return (Resolve-Path -LiteralPath $cand).Path }
    }
    $sib = Join-Path (Split-Path -Parent $PSScriptRoot) '29-resource-lease/Invoke-ResLease.ps1'
    if (Test-Path -LiteralPath $sib -PathType Leaf) { return (Resolve-Path -LiteralPath $sib).Path }
    return $null
}
# Run a res.lease action as a SEPARATE pwsh process (its `exit 0` must NOT terminate doc.io); return the
# parsed .result object, or $null on any failure (caller treats $null as "lease unavailable" -> proceed).
function Invoke-DocLeaseAction([string]$LeaseAction, [string]$Resource, [string]$Holder, [int]$Ttl, [double]$Wait, [string]$LeaseIdArg, [string]$LeaseDirArg, [string]$RlPath, [string]$PwshExe) {
    if ([string]::IsNullOrWhiteSpace($RlPath) -or [string]::IsNullOrWhiteSpace($PwshExe)) { return $null }
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $RlPath,
           '-Action', $LeaseAction, '-Resource', $Resource, '-Holder', $Holder)
    if ($LeaseAction -eq 'acquire') { $a += @('-TtlSeconds', "$Ttl", '-WaitSeconds', "$Wait") }
    if (-not [string]::IsNullOrWhiteSpace($LeaseIdArg))  { $a += @('-LeaseId', $LeaseIdArg) }
    if (-not [string]::IsNullOrWhiteSpace($LeaseDirArg)) { $a += @('-LeaseDir', $LeaseDirArg) }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $PwshExe @a 2>$null
        $txt = ([string]($out | Out-String)).Trim()
        if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
        $envObj = $txt | ConvertFrom-Json
        if ($null -ne $envObj -and ($envObj.PSObject.Properties.Name -contains 'result') -and $null -ne $envObj.result) { return $envObj.result }
        return $null
    } catch { Add-Diag "res.lease $LeaseAction invocation error: $($_.Exception.Message)"; return $null }
    finally { $ErrorActionPreference = $prev }
}
# Public projection of the doc-lease state for the result envelope (omits internal path fields).
function Project-DocLease() {
    if ($null -eq $script:DocLease) { return $null }
    $d = $script:DocLease
    return [ordered]@{
        enabled = $d.enabled; resource = $d.resource; holder = $d.holder
        available = $d.available; acquired = $d.acquired; owned = $d.owned
        already_held = $d.already_held; lease_id = $d.lease_id; held_by = $d.held_by; released = $d.released
    }
}
# Release a freshly-acquired doc lease (idempotent; a same-holder re-attach is left for the outer owner).
function Release-DocLease() {
    if ($null -eq $script:DocLease) { return }
    $d = $script:DocLease
    if (-not $d.owned) { return }
    if ($d.released -eq $true) { return }
    $rel = Invoke-DocLeaseAction 'release' $d.resource $d.holder 0 0 $d.lease_id $d.lease_dir $d.rl_path $d.pwsh
    if ($null -ne $rel -and [bool]$rel.released) { $d.released = $true; Add-Diag "doc lease released $($d.resource)" }
    else { $d.released = $false; Add-Diag "doc lease release unconfirmed $($d.resource)" }
}

# ---------------------------------------------------------------------------
# Envelope emission
# ---------------------------------------------------------------------------
$script:Warnings = @()
function Add-Warning([string]$w) { $script:Warnings = @($script:Warnings + $w); Add-Diag "WARN: $w" }

function Write-Envelope($status, $result, $errorObj, [string[]]$artifactPaths, [string]$inputsDigest) {
    Release-DocLease   # backstop: release a held doc lease on every emit (success or error), idempotent
    $finishedAt = [DateTime]::UtcNow
    $artifacts = @()
    foreach ($ap in $artifactPaths) {
        if ([string]::IsNullOrEmpty($ap)) { continue }
        if (-not (Test-Path -LiteralPath $ap)) { continue }
        $b = [System.IO.File]::ReadAllBytes($ap)
        $kind = switch ([System.IO.Path]::GetExtension($ap).ToLowerInvariant()) {
            '.json' { 'json' }; '.md' { 'markdown' }; '.txt' { 'text' }; default { 'text' }
        }
        $artifacts += [ordered]@{ path = $ap; kind = $kind; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) }
    }
    $env = [ordered]@{
        schema           = 'lifeorch.skill.result/0.1'
        skill_id         = 'doc.io'
        skill_version    = '0.1.0'
        contract_version = '0.2'
        invocation_id    = $invocationId
        status           = $status
        started_at_utc   = $startedAt.ToString('o')
        finished_at_utc  = $finishedAt.ToString('o')
        duration_ms      = [int][Math]::Round(($finishedAt - $startedAt).TotalMilliseconds)
        inputs_digest    = $inputsDigest
        result           = $result
        confidence       = $null
        artifacts        = $artifacts
        model_provenance = @()
        diagnostics      = @{ log = 'stderr.txt' }
        warnings         = @($script:Warnings)
        error            = $errorObj
    }
    $json = $env | ConvertTo-Json -Depth 30
    # result.json + stderr.txt in the artifact dir
    try { [System.IO.File]::WriteAllText((Join-Path $artDir 'result.json'), $json, ([System.Text.UTF8Encoding]::new($false))) } catch {}
    try { [System.IO.File]::WriteAllText((Join-Path $artDir 'stderr.txt'), (($script:Diag) -join [Environment]::NewLine), ([System.Text.UTF8Encoding]::new($false))) } catch {}
    [Console]::Out.WriteLine($json)
    if ($script:Diag.Count -gt 0) { [Console]::Error.WriteLine(($script:Diag[-1])) }
}

function New-Error([string]$code, [string]$message, [bool]$retryable = $false) {
    return [ordered]@{ code = $code; message = $message; retryable = $retryable }
}
function Fail([string]$code, [string]$message, $partialResult = $null, [bool]$retryable = $false) {
    Add-Diag "ERROR ${code}: $message"
    $res = if ($null -ne $partialResult) { $partialResult } else { [ordered]@{ op = $script:OpName; path = $script:AbsPath } }
    Write-Envelope 'error' $res (New-Error $code $message $retryable) @() $script:InputsDigest
    exit 0
}

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------
$script:OpName   = (Resolve-Str 'Op' 'op' '').Trim().ToLowerInvariant()
$rawPath         = Resolve-Str 'Path' 'path' ''
$script:AbsPath  = if ([string]::IsNullOrWhiteSpace($rawPath)) { '' } else { Resolve-AbsPath $rawPath }

# inputs digest (normalized) for caching/idempotency
$digestSrc = ($script:OpName + '|' + $script:AbsPath + '|' + (Resolve-Str 'Content' 'content' '') + '|' + (Resolve-Str 'OldString' 'old_string' '') + '|' + (Resolve-Str 'NewString' 'new_string' ''))
$script:InputsDigest = 'sha256:' + (Get-Sha256Hex ([System.Text.UTF8Encoding]::new($false).GetBytes($digestSrc)))

Add-Diag "op=$($script:OpName) path=$($script:AbsPath)"

if ($script:OpName -notin @('read','write','edit','append')) {
    Fail 'invalid_op' "op must be one of read|write|edit|append (got '$($script:OpName)')."
}
if ([string]::IsNullOrWhiteSpace($rawPath)) {
    Fail 'missing_parameter' "'path' is required."
}
if (Test-Path -LiteralPath $script:AbsPath -PathType Container) {
    Fail 'path_is_directory' "Target path is a directory: $($script:AbsPath)"
}

$encName = (Resolve-Str 'Encoding' 'encoding' 'utf-8').Trim().ToLowerInvariant()
if ($encName -notin @('utf-8','utf8','utf-8-bom','utf8bom')) {
    Fail 'encoding_unsupported' "encoding '$encName' not supported (MVP: utf-8, utf-8-bom; utf-16 is detect/preserve only)."
}
$writeEncInfo = if ($encName -in @('utf-8-bom','utf8bom')) { @{ name='utf-8'; bom=$true; bomLen=3 } } else { @{ name='utf-8'; bom=$false; bomLen=0 } }

$expectSha = (Resolve-Str 'ExpectSha256' 'expect_sha256' '').Trim().ToLowerInvariant()
$noPreimage = Resolve-Bool 'NoPreimage' 'no_preimage' $false

$fileExists = Test-Path -LiteralPath $script:AbsPath -PathType Leaf

# helper: read current file bytes + derived state
function Read-Current() {
    $bytes = [System.IO.File]::ReadAllBytes($script:AbsPath)
    $enc = Get-EncodingInfo $bytes
    $isBin = Test-IsBinary $bytes $enc
    return @{ bytes = $bytes; enc = $enc; isBinary = $isBin; sha = (Get-Sha256Hex $bytes); text = $(if ($isBin) { '' } else { ConvertFrom-Bytes $bytes $enc }) }
}

function Assert-Precondition($currentSha) {
    if ([string]::IsNullOrWhiteSpace($expectSha)) { return }
    $want = $expectSha
    if ($want.StartsWith('sha256:')) { $want = $want.Substring(7) }
    if ($currentSha -ne $want) {
        Fail 'precondition_failed' "expect_sha256 mismatch: current=$currentSha expected=$want"
    }
}

function Write-Preimage([byte[]]$bytes, [string]$ext) {
    if ($noPreimage) { return @{ written = $false; path = $null; reason = 'disabled' } }
    if ($bytes.Length -gt $PreimageMaxBytes) {
        Add-Warning "pre-image skipped: file larger than $PreimageMaxBytes bytes"
        return @{ written = $false; path = $null; reason = 'too_large' }
    }
    $p = Join-Path $artDir ("before" + $ext)
    [System.IO.File]::WriteAllBytes($p, $bytes)
    return @{ written = $true; path = $p; reason = $null }
}
function Write-Afterimage([byte[]]$bytes, [string]$ext) {
    $p = Join-Path $artDir ("after" + $ext)
    [System.IO.File]::WriteAllBytes($p, $bytes)
    return $p
}

function Build-FileState([byte[]]$bytes, $encInfo, [string]$text) {
    return [ordered]@{
        encoding   = $encInfo.name
        bom        = [bool]$encInfo.bom
        eol        = (Get-Eol $text)
        line_count = (Get-LineCount $text)
        byte_count = $bytes.Length
        char_count = $text.Length
        sha256     = (Get-Sha256Hex $bytes)
    }
}

# ===========================================================================
# OP: read
# ===========================================================================
if ($script:OpName -eq 'read') {
    if (-not $fileExists) { Fail 'input_not_found' "File not found: $($script:AbsPath)" }
    $cur = Read-Current
    if ($cur.isBinary) {
        Fail 'binary_file' "File appears to be binary (NUL byte found); doc.io reads text documents only. bytes=$($cur.bytes.Length) sha256=$($cur.sha)"
    }
    $maxBytes = Resolve-Int 'MaxBytes' 'max_bytes' 5000000
    if ($maxBytes -le 0) { $maxBytes = 5000000 }
    $fullText = $cur.text
    $totalLines = Get-LineCount $fullText
    $hasRange = (Has-Value 'StartLine' 'start_line') -or (Has-Value 'EndLine' 'end_line')
    $startLn = 0; $endLn = 0; $slice = $fullText
    if ($hasRange) {
        $startLn = Resolve-Int 'StartLine' 'start_line' 1
        $endLn = Resolve-Int 'EndLine' 'end_line' $totalLines
        if ($startLn -lt 1) { Fail 'invalid_range' "start_line must be >= 1 (got $startLn)." }
        if ($endLn -lt $startLn) { Fail 'invalid_range' "end_line ($endLn) must be >= start_line ($startLn)." }
        if ($startLn -gt $totalLines) { Fail 'invalid_range' "start_line ($startLn) exceeds line_count ($totalLines)." }
        if ($endLn -gt $totalLines) { $endLn = $totalLines }
        $lfLines = (ConvertTo-Lf $fullText).Split("`n")
        # trailing-newline safety: a trailing "\n" yields an empty final element we ignore
        $lineList = @($lfLines)
        if ($lineList.Count -gt $totalLines) { $lineList = @($lineList[0..($totalLines-1)]) }
        $slice = ($lineList[($startLn-1)..($endLn-1)] -join "`n")
    } else {
        $startLn = $(if ($totalLines -eq 0) { 0 } else { 1 })
        $endLn = $totalLines
    }
    $sliceBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($slice)
    $truncated = $false
    if ($sliceBytes.Length -gt $maxBytes) {
        # cut on a UTF-8 char boundary by trimming the decoded string conservatively
        $approxChars = [Math]::Max(0, [int]($maxBytes))
        if ($approxChars -lt $slice.Length) { $slice = $slice.Substring(0, $approxChars) }
        while (([System.Text.UTF8Encoding]::new($false).GetBytes($slice)).Length -gt $maxBytes -and $slice.Length -gt 0) {
            $slice = $slice.Substring(0, $slice.Length - 256)
        }
        $sliceBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($slice)
        $truncated = $true
        Add-Warning "content truncated to max_bytes=$maxBytes"
    }
    $readTxt = Join-Path $artDir 'read.txt'
    [System.IO.File]::WriteAllBytes($readTxt, $sliceBytes)

    $result = [ordered]@{
        op       = 'read'
        path     = $script:AbsPath
        existed  = $true
        file     = (Build-FileState $cur.bytes $cur.enc $fullText)
        content  = $slice
        returned = [ordered]@{
            start_line = $startLn
            end_line   = $endLn
            line_count = (Get-LineCount $slice)
            byte_count = $sliceBytes.Length
            truncated  = $truncated
            ranged     = $hasRange
        }
        is_binary = $false
    }
    $docJson = Join-Path $artDir 'doc.json'
    [System.IO.File]::WriteAllText($docJson, ($result | ConvertTo-Json -Depth 20), ([System.Text.UTF8Encoding]::new($false)))
    $docMd = Join-Path $artDir 'doc.md'
    $md = @()
    $md += "# doc.io read"
    $md += ""
    $md += "- **path:** ``$($script:AbsPath)``"
    $md += "- **encoding:** $($cur.enc.name) (bom=$([bool]$cur.enc.bom)) · **eol:** $($result.file.eol)"
    $md += "- **file:** $($result.file.line_count) lines · $($result.file.byte_count) bytes · sha256 ``$($result.file.sha256)``"
    $md += "- **returned:** lines $startLn-$endLn ($($result.returned.line_count) lines, $($result.returned.byte_count) bytes, truncated=$truncated)"
    [System.IO.File]::WriteAllText($docMd, (($md -join "`n") + "`n"), ([System.Text.UTF8Encoding]::new($false)))

    Add-Diag "read ok lines=$totalLines returned=$startLn-$endLn truncated=$truncated"
    Write-Envelope 'ok' $result $null @($readTxt, $docJson, $docMd) $script:InputsDigest
    exit 0
}

# ---------------------------------------------------------------------------
# doc lease acquire (op is write|edit|append here -- read already returned). Opt-in via -Lease/lease:true.
# Held around the whole read-modify-write below; released after the atomic write / on any emit (Write-Envelope).
# ---------------------------------------------------------------------------
$leaseEnabled = Resolve-Bool 'Lease' 'lease' $false
if ($leaseEnabled) {
    $leaseWaitS    = Resolve-Int 'LeaseWaitSeconds' 'lease_wait_s' 120
    $leaseTtlS     = Resolve-Int 'LeaseTtlSeconds'  'lease_ttl_s'  300
    $leaseHolderIn = Resolve-Str 'LeaseHolder'   'lease_holder'   ''
    $leaseResIn    = Resolve-Str 'LeaseResource' 'lease_resource' ''
    $leaseDirIn    = Resolve-Str 'LeaseDir'      'lease_dir'      ''
    $resLeaseIn    = Resolve-Str 'ResLeasePath'  'res_lease_path' ''
    $pwshIn        = Resolve-Str 'PwshPath'      'pwsh_path'      ''

    $holder = if (-not [string]::IsNullOrWhiteSpace($leaseHolderIn)) { $leaseHolderIn }
              elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE }
              else { "doc.io:$PID" }

    if (-not [string]::IsNullOrWhiteSpace($leaseResIn)) {
        $resource = $leaseResIn
    } else {
        # doc:<repo-relpath> when the target is under the repo (readable, matches the res.lease convention);
        # else doc:<abspath>. Forward slashes so all coordinators derive the SAME name for the same file.
        $key = $script:AbsPath -replace '\\', '/'
        $repoRoot = Resolve-RepoRootDoc $PSScriptRoot
        if ($null -ne $repoRoot) {
            $rootN = ([System.IO.Path]::GetFullPath($repoRoot) -replace '\\', '/').TrimEnd('/')
            if ($key.Length -gt ($rootN.Length + 1) -and $key.ToLowerInvariant().StartsWith($rootN.ToLowerInvariant() + '/')) {
                $key = $key.Substring($rootN.Length + 1)
            }
        }
        $resource = 'doc:' + $key
    }

    $rlPath  = Resolve-ResLeaseScript $resLeaseIn
    $pwshExe = Get-PwshExe $pwshIn
    $script:DocLease = [ordered]@{
        enabled = $true; resource = $resource; holder = $holder; mode = 'wait'
        available = $null; acquired = $false; owned = $false; already_held = $false
        lease_id = $null; held_by = $null; released = $null
        lease_dir = $leaseDirIn; rl_path = $rlPath; pwsh = $pwshExe
    }
    if ($null -eq $rlPath) {
        $script:DocLease.available = $false
        Add-Warning "doc lease: res.lease not found; proceeding without serialization (graceful fallback)"
    } else {
        $script:DocLease.available = $true
        $acq = Invoke-DocLeaseAction 'acquire' $resource $holder $leaseTtlS $leaseWaitS '' $leaseDirIn $rlPath $pwshExe
        if ($null -eq $acq) {
            $script:DocLease.available = $false
            Add-Warning "doc lease: res.lease invocation failed; proceeding without serialization (graceful fallback)"
        } elseif ([bool]$acq.acquired) {
            $script:DocLease.acquired     = $true
            $script:DocLease.lease_id     = [string]$acq.lease_id
            $script:DocLease.already_held = [bool]$acq.already_held
            $script:DocLease.owned        = (-not [bool]$acq.already_held)   # release only what we freshly created
            Add-Diag "doc lease acquired resource=$resource lease_id=$($script:DocLease.lease_id) already_held=$($script:DocLease.already_held)"
        } else {
            $script:DocLease.held_by = [string]$acq.held_by
            Fail 'doc_lease_unavailable' "doc lease '$resource' is held by '$($acq.held_by)'; not acquired within ${leaseWaitS}s." ([ordered]@{ op = $script:OpName; path = $script:AbsPath; lease = (Project-DocLease) }) $true
        }
    }
}

# ===========================================================================
# OP: write
# ===========================================================================
if ($script:OpName -eq 'write') {
    if (-not (Has-Value 'Content' 'content')) { Fail 'missing_parameter' "'content' is required for write." }
    $contentIn = Resolve-Str 'Content' 'content' ''
    $overwrite = Resolve-Bool 'Overwrite' 'overwrite' $true
    $createDirs = Resolve-Bool 'CreateDirs' 'create_dirs' $true
    $eolReq = (Resolve-Str 'Eol' 'eol' 'lf').Trim().ToLowerInvariant()
    if ($eolReq -notin @('lf','crlf')) { Fail 'invalid_argument' "eol must be lf|crlf (got '$eolReq')." }

    $shaBefore = $null; $bytesBefore = 0; $preBytes = $null
    if ($fileExists) {
        $bytesRaw = [System.IO.File]::ReadAllBytes($script:AbsPath)
        $shaBefore = Get-Sha256Hex $bytesRaw
        $bytesBefore = $bytesRaw.Length
        $preBytes = $bytesRaw
        Assert-Precondition $shaBefore
        if (-not $overwrite) { Fail 'already_exists' "File exists and overwrite=false: $($script:AbsPath)" }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($expectSha)) { Fail 'precondition_failed' "expect_sha256 supplied but file does not exist: $($script:AbsPath)" }
        $parent = [System.IO.Path]::GetDirectoryName($script:AbsPath)
        if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
            if ($createDirs) { New-Item -ItemType Directory -Force -Path $parent | Out-Null; Add-Diag "created parent dir $parent" }
            else { Fail 'parent_not_found' "Parent directory does not exist and create_dirs=false: $parent" }
        }
    }

    $newText = Set-Eol (ConvertTo-Lf $contentIn) $eolReq
    [byte[]]$newBytes = ConvertTo-Bytes $newText $writeEncInfo $writeEncInfo.bom
    $ext = Get-ArtExt $script:AbsPath

    $pre = @{ written = $false; path = $null; reason = 'not_existed' }
    if ($fileExists) { $pre = Write-Preimage $preBytes $ext }
    Write-AtomicBytes $script:AbsPath $newBytes
    $afterPath = Write-Afterimage $newBytes $ext
    Release-DocLease   # release the doc lease immediately after the atomic write

    $result = [ordered]@{
        op                = 'write'
        path              = $script:AbsPath
        existed           = $fileExists
        created           = (-not $fileExists)
        overwrite         = $overwrite
        bytes_written     = $newBytes.Length
        byte_count_before = $bytesBefore
        sha256_before     = $shaBefore
        file              = (Build-FileState $newBytes $writeEncInfo $newText)
        preimage          = [ordered]@{ written = [bool]$pre.written; path = $pre.path; reason = $pre.reason }
    }
    if ($null -ne $script:DocLease) { $result.lease = (Project-DocLease) }
    $docJson = Join-Path $artDir 'doc.json'
    [System.IO.File]::WriteAllText($docJson, ($result | ConvertTo-Json -Depth 20), ([System.Text.UTF8Encoding]::new($false)))
    $docMd = Join-Path $artDir 'doc.md'
    $md = @("# doc.io write","","- **path:** ``$($script:AbsPath)``","- **created:** $(-not $fileExists) · **overwrote:** $fileExists","- **wrote:** $($newBytes.Length) bytes · $($result.file.line_count) lines · eol=$($result.file.eol) · enc=$($writeEncInfo.name) bom=$($writeEncInfo.bom)","- **sha256:** ``$($result.file.sha256)`` (before ``$shaBefore``)")
    [System.IO.File]::WriteAllText($docMd, (($md -join "`n") + "`n"), ([System.Text.UTF8Encoding]::new($false)))

    Add-Diag "write ok bytes=$($newBytes.Length) created=$(-not $fileExists)"
    Write-Envelope 'ok' $result $null @($afterPath, $pre.path, $docJson, $docMd) $script:InputsDigest
    exit 0
}

# ===========================================================================
# OP: edit
# ===========================================================================
if ($script:OpName -eq 'edit') {
    if (-not (Has-Value 'OldString' 'old_string')) { Fail 'missing_parameter' "'old_string' is required for edit." }
    if (-not (Has-Value 'NewString' 'new_string')) { Fail 'missing_parameter' "'new_string' is required for edit." }
    if (-not $fileExists) { Fail 'input_not_found' "File not found: $($script:AbsPath)" }
    $oldStr = Resolve-Str 'OldString' 'old_string' ''
    $newStr = Resolve-Str 'NewString' 'new_string' ''
    if ($oldStr -eq '') { Fail 'invalid_argument' "old_string must be non-empty." }
    if ($oldStr -ceq $newStr) { Fail 'no_change' "old_string and new_string are identical; nothing to do." }
    $replaceAll = Resolve-Bool 'ReplaceAll' 'replace_all' $false
    $hasExpectCount = Has-Value 'ExpectCount' 'expect_count'
    $expectCount = Resolve-Int 'ExpectCount' 'expect_count' -1

    $cur = Read-Current
    if ($cur.isBinary) { Fail 'binary_file' "File appears to be binary; doc.io edits text documents only." }
    Assert-Precondition $cur.sha

    $origEol = Get-Eol $cur.text
    $effEol = Get-EffectiveEol $origEol
    if ($origEol -eq 'mixed') { Add-Warning "file has mixed EOL; normalizing written output to LF" }

    $fileLf = ConvertTo-Lf $cur.text
    $oldLf = ConvertTo-Lf $oldStr
    $newLf = ConvertTo-Lf $newStr

    $occurrences = ($fileLf.Split([string[]]@($oldLf), [System.StringSplitOptions]::None)).Length - 1
    if ($occurrences -lt 1) { Fail 'not_found' "old_string not found in file." (@{ op='edit'; path=$script:AbsPath; occurrences=0 }) }
    if ($hasExpectCount) {
        if ($occurrences -ne $expectCount) { Fail 'count_mismatch' "expected $expectCount occurrence(s) but found $occurrences." (@{ op='edit'; path=$script:AbsPath; occurrences=$occurrences }) }
    } elseif (-not $replaceAll -and $occurrences -gt 1) {
        Fail 'not_unique' "old_string is not unique ($occurrences occurrences); pass replace_all=true or expect_count, or provide more context." (@{ op='edit'; path=$script:AbsPath; occurrences=$occurrences })
    }

    $replacements = if ($replaceAll -or $hasExpectCount) { $occurrences } else { 1 }
    if ($replacements -eq $occurrences) {
        $newLfContent = $fileLf.Replace($oldLf, $newLf)
    } else {
        # replace only the first occurrence
        $idx = $fileLf.IndexOf($oldLf, [System.StringComparison]::Ordinal)
        $newLfContent = $fileLf.Substring(0, $idx) + $newLf + $fileLf.Substring($idx + $oldLf.Length)
    }

    $newText = Set-Eol $newLfContent $effEol
    [byte[]]$newBytes = ConvertTo-Bytes $newText $cur.enc $cur.enc.bom
    $ext = Get-ArtExt $script:AbsPath

    $pre = Write-Preimage $cur.bytes $ext
    Write-AtomicBytes $script:AbsPath $newBytes
    $afterPath = Write-Afterimage $newBytes $ext
    Release-DocLease   # release the doc lease immediately after the atomic write

    $result = [ordered]@{
        op                = 'edit'
        path              = $script:AbsPath
        existed           = $true
        occurrences       = $occurrences
        replacements      = $replacements
        replace_all       = [bool]$replaceAll
        byte_count_before = $cur.bytes.Length
        sha256_before     = $cur.sha
        file              = (Build-FileState $newBytes $cur.enc $newText)
        preimage          = [ordered]@{ written = [bool]$pre.written; path = $pre.path; reason = $pre.reason }
    }
    if ($null -ne $script:DocLease) { $result.lease = (Project-DocLease) }
    $docJson = Join-Path $artDir 'doc.json'
    [System.IO.File]::WriteAllText($docJson, ($result | ConvertTo-Json -Depth 20), ([System.Text.UTF8Encoding]::new($false)))
    $docMd = Join-Path $artDir 'doc.md'
    $md = @("# doc.io edit","","- **path:** ``$($script:AbsPath)``","- **occurrences:** $occurrences · **replacements:** $replacements · replace_all=$replaceAll","- **eol preserved:** $($result.file.eol) (was $origEol) · enc=$($cur.enc.name) bom=$($cur.enc.bom)","- **sha256:** ``$($result.file.sha256)`` (before ``$($cur.sha)``)")
    [System.IO.File]::WriteAllText($docMd, (($md -join "`n") + "`n"), ([System.Text.UTF8Encoding]::new($false)))

    Add-Diag "edit ok occ=$occurrences repl=$replacements eol=$($result.file.eol)"
    Write-Envelope 'ok' $result $null @($afterPath, $pre.path, $docJson, $docMd) $script:InputsDigest
    exit 0
}

# ===========================================================================
# OP: append
# ===========================================================================
if ($script:OpName -eq 'append') {
    if (-not (Has-Value 'Content' 'content')) { Fail 'missing_parameter' "'content' is required for append." }
    $contentIn = Resolve-Str 'Content' 'content' ''
    $create = Resolve-Bool 'Create' 'create' $true
    $ensureNewline = Resolve-Bool 'EnsureNewline' 'ensure_newline' $true
    $eolExplicit = Has-Value 'Eol' 'eol'
    $eolReq = (Resolve-Str 'Eol' 'eol' 'lf').Trim().ToLowerInvariant()
    if ($eolReq -notin @('lf','crlf')) { Fail 'invalid_argument' "eol must be lf|crlf (got '$eolReq')." }

    $existingBytes = [byte[]]@()
    $encInfo = $writeEncInfo
    $shaBefore = $null; $bytesBefore = 0; $origEol = 'none'; $created = $false
    if ($fileExists) {
        $cur = Read-Current
        if ($cur.isBinary) { Fail 'binary_file' "File appears to be binary; doc.io appends to text documents only." }
        Assert-Precondition $cur.sha
        $existingBytes = [byte[]]$cur.bytes
        $encInfo = $cur.enc
        $shaBefore = $cur.sha
        $bytesBefore = $cur.bytes.Length
        $origEol = Get-Eol $cur.text
    } else {
        if (-not $create) { Fail 'input_not_found' "File not found and create=false: $($script:AbsPath)" }
        if (-not [string]::IsNullOrWhiteSpace($expectSha)) { Fail 'precondition_failed' "expect_sha256 supplied but file does not exist: $($script:AbsPath)" }
        $parent = [System.IO.Path]::GetDirectoryName($script:AbsPath)
        if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null; Add-Diag "created parent dir $parent"
        }
        $created = $true
    }

    # EOL for the appended block: explicit -Eol wins; else the file's detected uniform EOL; else lf.
    $appendEol = if ($eolExplicit) { $eolReq } elseif ($origEol -eq 'crlf') { 'crlf' } else { 'lf' }
    $nl = if ($appendEol -eq 'crlf') { "`r`n" } else { "`n" }

    $appendText = Set-Eol (ConvertTo-Lf $contentIn) $appendEol
    [byte[]]$appendBytes = ConvertTo-Bytes $appendText $encInfo $false   # never re-emit BOM; existing bytes already carry it

    [byte[]]$sepBytes = @()
    $ensured = $false
    if ($ensureNewline -and $existingBytes.Length -gt 0) {
        # does the existing content already end with a newline?
        $endsWithNl = $false
        $lastText = (ConvertFrom-Bytes $existingBytes $encInfo)
        if ($lastText.EndsWith("`n") -or $lastText.EndsWith("`r")) { $endsWithNl = $true }
        if (-not $endsWithNl) {
            [byte[]]$sepBytes = ConvertTo-Bytes $nl $encInfo $false
            $ensured = $true
        }
    }

    [byte[]]$newBytes = New-Object byte[] ($existingBytes.Length + $sepBytes.Length + $appendBytes.Length)
    [System.Array]::Copy($existingBytes, 0, $newBytes, 0, $existingBytes.Length)
    if ($sepBytes.Length -gt 0) { [System.Array]::Copy($sepBytes, 0, $newBytes, $existingBytes.Length, $sepBytes.Length) }
    [System.Array]::Copy($appendBytes, 0, $newBytes, $existingBytes.Length + $sepBytes.Length, $appendBytes.Length)

    $ext = Get-ArtExt $script:AbsPath
    $pre = @{ written = $false; path = $null; reason = 'not_existed' }
    if ($fileExists) { $pre = Write-Preimage $existingBytes $ext }
    Write-AtomicBytes $script:AbsPath $newBytes
    $afterPath = Write-Afterimage $newBytes $ext
    Release-DocLease   # release the doc lease immediately after the atomic write

    $newFullText = if ((Test-IsBinary $newBytes $encInfo)) { '' } else { ConvertFrom-Bytes $newBytes $encInfo }
    $result = [ordered]@{
        op                = 'append'
        path              = $script:AbsPath
        existed           = $fileExists
        created           = $created
        bytes_appended    = ($sepBytes.Length + $appendBytes.Length)
        ensured_newline   = $ensured
        byte_count_before = $bytesBefore
        sha256_before     = $shaBefore
        file              = (Build-FileState $newBytes $encInfo $newFullText)
        preimage          = [ordered]@{ written = [bool]$pre.written; path = $pre.path; reason = $pre.reason }
    }
    if ($null -ne $script:DocLease) { $result.lease = (Project-DocLease) }
    $docJson = Join-Path $artDir 'doc.json'
    [System.IO.File]::WriteAllText($docJson, ($result | ConvertTo-Json -Depth 20), ([System.Text.UTF8Encoding]::new($false)))
    $docMd = Join-Path $artDir 'doc.md'
    $md = @("# doc.io append","","- **path:** ``$($script:AbsPath)``","- **created:** $created · **appended:** $($result.bytes_appended) bytes (ensured_newline=$ensured)","- **eol:** $($result.file.eol) · enc=$($encInfo.name) bom=$($encInfo.bom)","- **sha256:** ``$($result.file.sha256)`` (before ``$shaBefore``)")
    [System.IO.File]::WriteAllText($docMd, (($md -join "`n") + "`n"), ([System.Text.UTF8Encoding]::new($false)))

    Add-Diag "append ok appended=$($result.bytes_appended) created=$created ensured=$ensured"
    Write-Envelope 'ok' $result $null @($afterPath, $pre.path, $docJson, $docMd) $script:InputsDigest
    exit 0
}

# Unreachable (op validated above), but keep a safety net.
Fail 'invalid_op' "Unhandled op '$($script:OpName)'."
