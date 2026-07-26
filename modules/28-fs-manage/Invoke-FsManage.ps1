#requires -Version 7.0
<#
.SYNOPSIS
  fs.manage -- deterministic file placement: copy / move / mkdir (Life Orchestrator, contract v0.2).
.DESCRIPTION
  The last-mile file-management primitive a local model (agent.local #21, a Widget, an unattended task) calls
  to PUT a produced file where the user wants it -- e.g. "place the generated image on my desktop". One op per
  invocation:
    - copy  : copy an existing file to a destination (folder or file path).
    - move  : move/rename an existing file to a destination (folder or file path).
    - mkdir : create a folder (and any missing parents).

  Smart, forgiving PATH RESOLUTION on source + dest (this is what makes "put it on my desktop" work by default):
  known-folder names (desktop | downloads | documents/docs | pictures | music | videos | home | temp) resolve to
  the real user folder; `~` -> the user home; `%VAR%` env vars are expanded; an absolute path is used as-is; a
  bare/relative path resolves against the current directory. When the destination is a folder (a known folder, an
  existing directory, a trailing-separator path, or an extension-less non-file), the source's own filename is kept
  inside it. An existing destination file is NOT overwritten unless -Overwrite is set (else `already_exists`).

  DETERMINISTIC + a tool, not a model: `determinism:"deterministic"`, `confidence:null`, empty model_provenance,
  NOT a review-queue producer (the canonical review_queue.jsonl + the ten-producer set are untouched). Pure
  PowerShell + .NET -- no external binary / Python / model / models.json change. `parallel_safe:false` (mutates
  arbitrary caller-chosen paths, like doc.io #20), `batch:false`, `streaming:false`. Emits one
  lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes manage.json/manage.md. Exits 0
  whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-FsManage.ps1 -Op copy -Source C:\tmp\image.png -Dest desktop
  pwsh -NoProfile -File .\Invoke-FsManage.ps1 -InputsJson '{"op":"move","source":"C:\\tmp\\a.png","dest":"~\\Desktop\\dog.png"}'
  pwsh -NoProfile -File .\Invoke-FsManage.ps1 -Op mkdir -Path desktop\dog-pics
#>
[CmdletBinding()]
param(
    [string]$Op,
    [string]$Source,
    [string]$Dest,
    [string]$Path,
    [switch]$Overwrite,
    [bool]$CreateDirs = $true,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'fs.manage'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[fs.manage] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Get-UserHome {
    $h = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($h)) { $h = $env:USERPROFILE }
    if ([string]::IsNullOrWhiteSpace($h)) { $h = $HOME }
    return $h
}
function Get-KnownFolder([string]$name) {
    $uhome = Get-UserHome
    switch ($name.ToLowerInvariant()) {
        'desktop'   { $p = [Environment]::GetFolderPath('Desktop');    if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Desktop' }; return $p }
        'documents' { $p = [Environment]::GetFolderPath('MyDocuments'); if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Documents' }; return $p }
        'docs'      { $p = [Environment]::GetFolderPath('MyDocuments'); if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Documents' }; return $p }
        'pictures'  { $p = [Environment]::GetFolderPath('MyPictures');  if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Pictures' }; return $p }
        'music'     { $p = [Environment]::GetFolderPath('MyMusic');     if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Music' }; return $p }
        'videos'    { $p = [Environment]::GetFolderPath('MyVideos');    if ([string]::IsNullOrWhiteSpace($p)) { $p = Join-Path $uhome 'Videos' }; return $p }
        'downloads' { return (Join-Path $uhome 'Downloads') }
        'home'      { return $uhome }
        'temp'      { $t = $env:TEMP; if ([string]::IsNullOrWhiteSpace($t)) { $t = [System.IO.Path]::GetTempPath() }; return $t }
        default     { return $null }
    }
}
# Resolve a caller-supplied path: strip quotes, expand env + ~, map a known-folder first segment, absolutize.
function Resolve-UserPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    $s = $p.Trim().Trim('"').Trim("'").Trim()
    $s = [Environment]::ExpandEnvironmentVariables($s)
    # split on either separator; drop empty leading segment
    $segs = @($s -split '[\\/]+' | Where-Object { $_ -ne '' })
    if (@($segs).Count -eq 0) { return $s }
    $first = $segs[0]
    $base = $null
    if ($first -eq '~') { $base = Get-UserHome; $segs = @($segs | Select-Object -Skip 1) }
    else {
        $kf = Get-KnownFolder $first
        if ($null -ne $kf) { $base = $kf; $segs = @($segs | Select-Object -Skip 1) }
    }
    if ($null -ne $base) {
        $out = $base
        foreach ($seg in $segs) { $out = Join-Path $out $seg }
        return $out
    }
    if ([System.IO.Path]::IsPathRooted($s)) { return $s }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $s))
}
# A destination is treated as a DIRECTORY (keep the source filename) when it is a known folder, an existing dir,
# ends with a separator, or has no file extension.
function Test-DestIsDir([string]$origDest, [string]$resolvedDest) {
    $t = $origDest.Trim().Trim('"').Trim("'").Trim()
    if ($t -match '[\\/]\s*$') { return $true }
    $first = @($t -split '[\\/]+' | Where-Object { $_ -ne '' })
    if (@($first).Count -eq 1 -and ($first[0] -eq '~' -or $null -ne (Get-KnownFolder $first[0]))) { return $true }
    if (Test-Path -LiteralPath $resolvedDest -PathType Container) { return $true }
    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($resolvedDest))) { return $true }
    return $false
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
            if ((Has $p 'op')          -and -not $bound.ContainsKey('Op'))         { $Op = [string]$p.op }
            if ((Has $p 'source')      -and -not $bound.ContainsKey('Source'))     { $Source = [string]$p.source }
            if ((Has $p 'src')         -and -not $bound.ContainsKey('Source') -and [string]::IsNullOrWhiteSpace($Source)) { $Source = [string]$p.src }
            if ((Has $p 'dest')        -and -not $bound.ContainsKey('Dest'))       { $Dest = [string]$p.dest }
            if ((Has $p 'destination') -and -not $bound.ContainsKey('Dest') -and [string]::IsNullOrWhiteSpace($Dest)) { $Dest = [string]$p.destination }
            if ((Has $p 'path')        -and -not $bound.ContainsKey('Path'))       { $Path = [string]$p.path }
            if ((Has $p 'overwrite')   -and -not $bound.ContainsKey('Overwrite'))  { if ([bool]$p.overwrite) { $Overwrite = [switch]$true } }
            if ((Has $p 'create_dirs') -and -not $bound.ContainsKey('CreateDirs')) { $CreateDirs = [bool]$p.create_dirs }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Op)) { throw [PSCustomObject]@{ code='missing_parameter'; message='op is required (copy|move|mkdir)'; retryable=$false } }
    $Op = $Op.ToLowerInvariant()
    if (@('copy','move','mkdir') -notcontains $Op) { throw [PSCustomObject]@{ code='invalid_op'; message="op must be copy|move|mkdir (got '$Op')"; retryable=$false } }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    if ($Op -eq 'mkdir') {
        $rawTarget = if (-not [string]::IsNullOrWhiteSpace($Path)) { $Path } elseif (-not [string]::IsNullOrWhiteSpace($Dest)) { $Dest } else { '' }
        if ([string]::IsNullOrWhiteSpace($rawTarget)) { throw [PSCustomObject]@{ code='missing_parameter'; message='mkdir needs path'; retryable=$false } }
        $target = Resolve-UserPath $rawTarget
        $existed = Test-Path -LiteralPath $target -PathType Container
        if ((Test-Path -LiteralPath $target) -and -not $existed) { throw [PSCustomObject]@{ code='path_is_file'; message="a file already exists at '$target'"; retryable=$false } }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $result = [ordered]@{ op='mkdir'; path=$target; created=(-not $existed); existed=$existed }
        $normInputs = [ordered]@{ op='mkdir'; path=$target }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Source)) { throw [PSCustomObject]@{ code='missing_parameter'; message="$Op needs source"; retryable=$false } }
        if ([string]::IsNullOrWhiteSpace($Dest))   { throw [PSCustomObject]@{ code='missing_parameter'; message="$Op needs dest"; retryable=$false } }
        $src = Resolve-UserPath $Source
        if (-not (Test-Path -LiteralPath $src)) { throw [PSCustomObject]@{ code='input_not_found'; message="source not found: $src"; retryable=$false } }
        if (Test-Path -LiteralPath $src -PathType Container) { throw [PSCustomObject]@{ code='source_is_directory'; message="source is a directory (MVP handles files only): $src"; retryable=$false } }
        $srcName = [System.IO.Path]::GetFileName($src)

        $destResolved = Resolve-UserPath $Dest
        $destIsDir = Test-DestIsDir $Dest $destResolved
        $final = if ($destIsDir) { Join-Path $destResolved $srcName } else { $destResolved }
        $finalParent = [System.IO.Path]::GetDirectoryName($final)

        if (-not [string]::IsNullOrWhiteSpace($finalParent) -and -not (Test-Path -LiteralPath $finalParent -PathType Container)) {
            if ($CreateDirs) { New-Item -ItemType Directory -Path $finalParent -Force | Out-Null }
            else { throw [PSCustomObject]@{ code='parent_not_found'; message="destination parent does not exist: $finalParent"; retryable=$false } }
        }

        $destExisted = Test-Path -LiteralPath $final -PathType Leaf
        if ($destExisted -and -not $Overwrite) { throw [PSCustomObject]@{ code='already_exists'; message="destination already exists (set overwrite=true to replace): $final"; retryable=$false } }
        if ((Test-Path -LiteralPath $final -PathType Container)) { throw [PSCustomObject]@{ code='dest_is_directory'; message="destination resolves to an existing directory with the source name inside it is required: $final"; retryable=$false } }

        if ($Op -eq 'copy') { Copy-Item -LiteralPath $src -Destination $final -Force }
        else {
            if ($destExisted) { Remove-Item -LiteralPath $final -Force }
            Move-Item -LiteralPath $src -Destination $final -Force
        }
        $final = (Resolve-Path -LiteralPath $final).Path
        $fb = [System.IO.File]::ReadAllBytes($final)
        $result = [ordered]@{
            op=$Op; source=$src; dest=$final; dest_folder=([System.IO.Path]::GetDirectoryName($final))
            filename=$srcName; dest_was_dir=$destIsDir; overwrote=$destExisted
            bytes=$fb.Length; sha256=(Get-Sha256Hex $fb)
            source_still_exists=(Test-Path -LiteralPath $src -PathType Leaf)
        }
        $normInputs = [ordered]@{ op=$Op; source=$src; dest=$final }
    }

    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
    Write-Diag "ok op=$Op"
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

# ---- artifacts: manage.json + manage.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $mj = [ordered]@{ schema='lifeorch.fs.manage/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $mjPath = Join-Path $invDir 'manage.json'
        [System.IO.File]::WriteAllText($mjPath, ($mj | ConvertTo-Json -Depth 20), $utf8)
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# fs.manage -- $($result.op)")
        [void]$mb.AppendLine('')
        foreach ($k in $result.Keys) { [void]$mb.AppendLine("- **${k}:** $($result.$k)") }
        [void]$mb.AppendLine('')
        $mdPath = Join-Path $invDir 'manage.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        foreach ($a in @([pscustomobject]@{ p=$mjPath; k='json' }, [pscustomobject]@{ p=$mdPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [byte[]]([System.IO.File]::ReadAllBytes($a.p))
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[fs.manage] invocation $InvocationId status=$status`n", $utf8)
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
