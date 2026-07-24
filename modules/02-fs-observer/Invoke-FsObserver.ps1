#requires -Version 7.0
<#
.SYNOPSIS
  fs.observer — deterministic filesystem tree + name search for Life Orchestrator (skill contract v0.1).
.DESCRIPTION
  Lists a directory tree under -Path (bounded by -Depth) with per-entry metadata, sorted for stable
  output; optional -Pattern name-glob search. Emits one lifeorch.skill.result/0.1 envelope to stdout and
  writes tree.md + index.json artifacts under <ArtifactRoot>/<InvocationId>/. Diagnostics go to stderr.
  Exits 0 whenever a valid envelope is produced (including logical status=error/partial).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path 'C:\Users\just_\LifeOrchestrator-Refresh' -Depth 2
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -InputsJson '{"path":"C:\\src","depth":3,"pattern":"*.md"}'
#>
[CmdletBinding()]
param(
    [string]$Path,
    [int]$Depth = 3,
    [string]$Pattern,
    [bool]$IncludeHidden = $false,
    [int]$MaxEntries = 5000,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'fs.observer'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[fs.observer] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$matchCount = 0; $matchesBounded = @()
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $names = $p.PSObject.Properties.Name
            if ($names -contains 'path')           { $Path = [string]$p.path }
            if ($names -contains 'depth')          { $Depth = [int]$p.depth }
            if ($names -contains 'pattern')        { $Pattern = [string]$p.pattern }
            if ($names -contains 'include_hidden') { $IncludeHidden = [bool]$p.include_hidden }
            if ($names -contains 'max_entries')    { $MaxEntries = [int]$p.max_entries }
        }
    }

    $normInputs = [ordered]@{ path = $Path; depth = $Depth; pattern = $Pattern; include_hidden = $IncludeHidden; max_entries = $MaxEntries }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status = 'error'; $errorObj = [ordered]@{ code = 'invalid_input'; message = 'path is required'; retryable = $false }
    }
    elseif (-not (Test-Path -LiteralPath $Path)) {
        $status = 'error'; $errorObj = [ordered]@{ code = 'path_not_found'; message = "path not found: $Path"; retryable = $false }
    }
    elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $status = 'error'; $errorObj = [ordered]@{ code = 'not_a_directory'; message = "path is not a directory: $Path"; retryable = $false }
    }
    else {
        $rootFull = (Resolve-Path -LiteralPath $Path).Path
        $entries = New-Object System.Collections.Generic.List[object]
        $truncated = $false; $dirCount = 0; $fileCount = 0; [long]$bytesTotal = 0

        $stack = New-Object System.Collections.Generic.Stack[object]
        $stack.Push([pscustomobject]@{ FullName = $rootFull; Depth = 0 })
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($node.Depth -ge $Depth) { continue }
            try { $kids = @(Get-ChildItem -LiteralPath $node.FullName -Force:$IncludeHidden -ErrorAction Stop) }
            catch { $warnings.Add("cannot read '$($node.FullName)': $($_.Exception.Message)"); continue }
            foreach ($k in $kids) {
                if ($entries.Count -ge $MaxEntries) { $truncated = $true; break }
                $isDir = [bool]$k.PSIsContainer
                $isReparse = (($k.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
                $type = if ($isReparse) { 'symlink' } elseif ($isDir) { 'dir' } else { 'file' }
                $rel = $k.FullName.Substring($rootFull.Length).TrimStart([char]'\', [char]'/').Replace('\','/')
                $bytes = if ($type -eq 'file') { [long]$k.Length } else { 0 }
                $childDepth = $node.Depth + 1
                $entries.Add([pscustomobject]@{ rel = $rel; name = $k.Name; type = $type; bytes = $bytes; mtime_utc = $k.LastWriteTimeUtc.ToString('o'); depth = $childDepth; abs = $k.FullName })
                if ($isDir) { $dirCount++ } elseif ($type -eq 'file') { $fileCount++; $bytesTotal += $bytes }
                if ($isDir -and -not $isReparse) { $stack.Push([pscustomobject]@{ FullName = $k.FullName; Depth = $childDepth }) }
            }
            if ($truncated) { break }
        }

        # Deterministic ordinal (case-insensitive) sort by relative path -> pre-order.
        $arr = $entries.ToArray()
        $cmp = [System.Comparison[object]]{ param($a, $b) [string]::CompareOrdinal($a.rel.ToLowerInvariant(), $b.rel.ToLowerInvariant()) }
        [System.Array]::Sort($arr, $cmp)

        # Matches (name glob)
        if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
            $matched = @($arr | Where-Object { $_.name -like $Pattern })
            $matchCount = $matched.Count
            $matchesBounded = @($matched | Select-Object -First 200 | ForEach-Object { $_.abs })
            if ($matchCount -gt 200) { $warnings.Add("matches truncated to 200 of $matchCount") }
        }

        # index.json
        $indexObj = [ordered]@{
            schema = 'lifeorch.fs.index/0.1'; root = $rootFull; generated_at_utc = $startedAt.ToString('o')
            depth = $Depth; entry_count = $arr.Count
            entries = @($arr | ForEach-Object { [ordered]@{ rel = $_.rel; name = $_.name; type = $_.type; bytes = $_.bytes; mtime_utc = $_.mtime_utc; depth = $_.depth } })
        }
        $indexPath = Join-Path $invDir 'index.json'
        [System.IO.File]::WriteAllText($indexPath, ($indexObj | ConvertTo-Json -Depth 6), $utf8)

        # tree.md
        $tb = [System.Text.StringBuilder]::new()
        [void]$tb.AppendLine("# fs.observer — $rootFull")
        [void]$tb.AppendLine("")
        [void]$tb.AppendLine("depth=$Depth  entries=$($arr.Count)  dirs=$dirCount  files=$fileCount  bytes=$bytesTotal  truncated=$truncated")
        if (-not [string]::IsNullOrWhiteSpace($Pattern)) { [void]$tb.AppendLine("pattern=$Pattern  matches=$matchCount") }
        [void]$tb.AppendLine("")
        foreach ($e in $arr) {
            $indent = '  ' * [Math]::Max(0, $e.depth - 1)
            if ($e.type -eq 'dir') { [void]$tb.AppendLine("$indent$($e.name)/") }
            elseif ($e.type -eq 'symlink') { [void]$tb.AppendLine("$indent$($e.name)@") }
            else { [void]$tb.AppendLine("$indent$($e.name)  ($($e.bytes) B)") }
        }
        $treePath = Join-Path $invDir 'tree.md'
        [System.IO.File]::WriteAllText($treePath, $tb.ToString(), $utf8)

        foreach ($ap in @(@{p=$treePath;k='markdown'}, @{p=$indexPath;k='json'})) {
            $b = [System.IO.File]::ReadAllBytes($ap.p)
            $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $ap.p).Path; kind = $ap.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
        }

        $result = [ordered]@{
            root = $rootFull; depth = $Depth; generated_at_utc = $startedAt.ToString('o')
            entry_count = $arr.Count; dir_count = $dirCount; file_count = $fileCount; bytes_total = $bytesTotal
            truncated = $truncated; pattern = $Pattern; match_count = $matchCount; matches = $matchesBounded
        }
        if ($truncated -or $warnings.Count -gt 0) { $status = 'partial' }
        Write-Diag "observed $($arr.Count) entries under $rootFull (dirs=$dirCount files=$fileCount) -> $invDir"
    }
}
catch {
    $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[fs.observer] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $inputsDigest
    result = $result; confidence = $null; artifacts = $artifacts; model_provenance = @()
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
