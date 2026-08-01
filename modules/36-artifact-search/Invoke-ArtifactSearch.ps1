#requires -Version 7.0
<#
.SYNOPSIS
  artifact.search -- deterministic SQLite catalog + hybrid LEXICAL (FTS5) search (Life Orchestrator,
  Module 36, contract v0.2). The Collective Agent's authoritative catalog substrate (D-0080 Wave 1).
.DESCRIPTION
  A thin PowerShell entrypoint over a stdlib-only Python worker (artifact_search.py) that owns a SQLite
  database (the authoritative catalog) with SQLite FTS5. One op per invocation:

    ingest              -- walk a root; content-hash inventory; new/changed/moved/deleted detection;
                           Markdown-aware chunking (+ generic-text fallback); FTS5 index; a MOCK
                           embedding provider (the D-0077 seam); incremental reconcile with NO duplicate
                           chunks; a DB integrity check; a deterministic catalog_digest.
    search              -- hybrid retrieval (mode fts | exact) returning ranked, provenance-complete
                           hits {source_path, content_hash, chunk_id, span, section_path, score, snippet}
                           in a DETERMINISTIC order (stable tie-break) -- the retriever interface (#37 consumes).
    embed               -- the MOCK embedding-provider envelope {model_*, dim, normalized, count, vectors
                           (exact input order), input_status} -- contract-shaped so the REAL adapter drops in.
    integrity           -- PRAGMA integrity_check + catalog invariants.
    catalog             -- catalog_digest + counts.
    export-chunk-texts  -- deterministic ordered [{chunk_id, rel_path, content_hash, span, text}] (fold input).
    store-embeddings    -- load externally-produced vectors keyed by chunk_id (fold drop-in for #35).

  Worker+meta hand-off (D-0021), robust to library stdout chatter. Determinism: chunk/document/version
  ids are content+path derived; catalog_digest is byte-identical for identical corpus content across runs
  AND machines (repo-relative paths + byte spans); the SQLite file itself is NOT byte-reproducible.
  CPU-only, no model, no network -> determinism=deterministic, confidence=null, empty model_provenance.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr. Exits 0 whenever a
  valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op ingest -Source core-docs -Root ..\..\core-docs -DbPath .\runtime\catalog\as.db
  pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "resource lease" -Mode fts -K 5 -DbPath .\runtime\catalog\as.db
  pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"search","query":"D-0077","mode":"exact","db":"...","filters":{"type":"markdown_section"}}'
#>
[CmdletBinding()]
param(
    [string]$Op = 'search',
    [string]$Query,
    [string]$Text,
    [string]$Source,
    [string]$Root,
    [string]$DbPath,
    [string]$Mode = 'fts',
    [int]$K = 10,
    [int]$Dim,
    [object]$Normalize,
    [int]$MaxFiles,
    [int]$MaxChunkChars,
    [string]$EmbedProvider,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'artifact.search'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[artifact.search] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-SystemPython([string]$FallbackLiteral, [string]$StartDir = $PSScriptRoot) {
    # ADDITIVE portability seam (FANOUT_AGENT_002): a machine config (ops\setup\config.json ->
    # python_interpreters.system, resolved via Resolve-LifeorchInterpreter) MAY relocate the SYSTEM python
    # on a fresh box. Return the CONFIGURED interpreter ONLY when it (a) came from config, (b) DIFFERS from
    # the literal, and (c) exists; otherwise return the literal UNCHANGED. Fail-closed to the literal on ANY
    # error. Pure lookup, ASCII-only.
    try {
        $p = Get-Item -LiteralPath $StartDir -ErrorAction Stop
        for ($k = 0; $k -lt 8 -and $null -ne $p; $k++) {
            $cfgMod = Join-Path $p.FullName 'ops\setup\LifeorchConfig.psm1'
            if (Test-Path -LiteralPath $cfgMod -PathType Leaf) {
                Import-Module $cfgMod -DisableNameChecking -Force -ErrorAction Stop
                $res = Resolve-LifeorchInterpreter -Role 'system' -Fallback $FallbackLiteral
                $cand = [string]$res.path
                if ($res.source -eq 'config' -and -not [string]::IsNullOrWhiteSpace($cand) -and ($cand -ne $FallbackLiteral) -and (Test-Path -LiteralPath $cand -PathType Leaf)) {
                    return $cand
                }
                break
            }
            $p = $p.Parent
        }
    } catch { }
    return $FallbackLiteral
}
function Test-Python([string]$exe) {
    # artifact.search needs stdlib sqlite3 WITH FTS5 -- probe both (fail-closed).
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c "import sqlite3; c=sqlite3.connect(':memory:'); c.execute('CREATE VIRTUAL TABLE t USING fts5(x)')" 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}
function Invoke-Worker([string]$exe, [string[]]$argv) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $exe @argv 2> $tmpErr.FullName
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $err = ''; try { $err = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    return @{ exit = $code; out = ($out | Out-String); err = $err }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$VALID_OPS = @('ingest','search','embed','integrity','catalog','export-chunk-texts','store-embeddings')

try {
    # ---- build the worker args: start from InputsJson (generic pass-through), then named params win ----
    $wargs = [ordered]@{}
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
    }
    if ($null -ne $p -and $null -ne $p.PSObject) {
        foreach ($pr in $p.PSObject.Properties) { $wargs[$pr.Name] = $pr.Value }
    }
    # named params override matching InputsJson keys (documented precedence, mirrors image.util)
    if ($bound.ContainsKey('Op'))            { $wargs['op'] = $Op } elseif (-not $wargs.Contains('op')) { $wargs['op'] = $Op }
    if ($bound.ContainsKey('Query'))         { $wargs['query'] = $Query }
    if ($bound.ContainsKey('Text'))          { $wargs['text'] = $Text }
    if ($bound.ContainsKey('Source'))        { $wargs['source'] = $Source }
    if ($bound.ContainsKey('Root'))          { $wargs['root'] = $Root }
    if ($bound.ContainsKey('DbPath'))        { $wargs['db'] = $DbPath }
    if ($bound.ContainsKey('Mode'))          { $wargs['mode'] = $Mode } elseif (-not $wargs.Contains('mode')) { $wargs['mode'] = $Mode }
    if ($bound.ContainsKey('K'))             { $wargs['k'] = $K } elseif (-not $wargs.Contains('k')) { $wargs['k'] = $K }
    if ($bound.ContainsKey('Dim'))           { $wargs['dim'] = $Dim }
    if ($bound.ContainsKey('Normalize') -and $null -ne $Normalize) { $wargs['normalize'] = [bool]$Normalize }
    if ($bound.ContainsKey('MaxFiles'))      { $wargs['max_files'] = $MaxFiles }
    if ($bound.ContainsKey('MaxChunkChars')) { $wargs['max_chunk_chars'] = $MaxChunkChars }
    if ($bound.ContainsKey('EmbedProvider')) { $wargs['embed_provider'] = $EmbedProvider }

    $Op = [string]$wargs['op']
    if ([string]::IsNullOrWhiteSpace($Op)) { $Op = 'search'; $wargs['op'] = $Op }
    $Op = $Op.ToLowerInvariant(); $wargs['op'] = $Op
    if ($VALID_OPS -notcontains $Op) {
        throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' ($($VALID_OPS -join '|'))"; retryable=$false }
    }

    # ---- resolve the DB path (persist under the module runtime by default; embed needs none) ----
    if ($Op -ne 'embed') {
        $dbVal = [string]$wargs['db']
        if ([string]::IsNullOrWhiteSpace($dbVal)) {
            $dbVal = Join-Path $PSScriptRoot 'runtime/catalog/artifact_search.db'
        }
        $dbDir = Split-Path -Parent $dbVal
        if (-not [string]::IsNullOrWhiteSpace($dbDir) -and -not (Test-Path -LiteralPath $dbDir)) {
            New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        }
        $wargs['db'] = $dbVal
        if ($Op -ne 'ingest') {
            if (-not (Test-Path -LiteralPath $dbVal -PathType Leaf)) {
                throw [PSCustomObject]@{ code='db_not_found'; message="catalog db not found: $dbVal (run op=ingest first)"; retryable=$false }
            }
        }
    }
    if ($Op -eq 'ingest') {
        $rootVal = [string]$wargs['root']
        if ([string]::IsNullOrWhiteSpace($rootVal)) { throw [PSCustomObject]@{ code='missing_root'; message='op=ingest needs -Root (a directory to index)'; retryable=$false } }
        if (-not (Test-Path -LiteralPath $rootVal -PathType Container)) { throw [PSCustomObject]@{ code='root_not_found'; message="ingest root not found: $rootVal"; retryable=$false } }
        $wargs['root'] = (Resolve-Path -LiteralPath $rootVal).Path
    }
    if ($Op -eq 'search' -and [string]::IsNullOrWhiteSpace([string]$wargs['query'])) {
        throw [PSCustomObject]@{ code='missing_query'; message='op=search needs -Query'; retryable=$false }
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $wargs['output_dir'] = $invDir
    $metaPath = Join-Path $invDir 'as_meta.json'
    $wargs['meta_path'] = $metaPath

    # ---- normalized inputs digest (over the op params, excluding volatile output paths) ----
    $digestObj = [ordered]@{}
    foreach ($key in ($wargs.Keys | Sort-Object)) {
        if ($key -in @('output_dir','meta_path')) { continue }
        $digestObj[$key] = $wargs[$key]
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($digestObj | ConvertTo-Json -Compress -Depth 20)))

    # ---- resolve python (stdlib sqlite3 + FTS5) ----
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    if ($wargs.Contains('python_path') -and -not [string]::IsNullOrWhiteSpace([string]$wargs['python_path'])) { $cands.Add([string]$wargs['python_path']) }
    $sysPyLiteral = 'C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe'
    try { $cfgPy = Resolve-SystemPython $sysPyLiteral; if ($cfgPy -ne $sysPyLiteral) { $cands.Add($cfgPy) } } catch { }
    $cands.Add($sysPyLiteral)
    $cands.Add('F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe')
    foreach ($n in @('python3','python','py')) { $cands.Add($n) }
    foreach ($n in @('python','python3','py')) {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $w = & where.exe $n 2>$null
            $ErrorActionPreference = $prev
            foreach ($line in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($line)) { $cands.Add($line.Trim()) } }
        } catch { }
    }
    $python = $null
    foreach ($c in ($cands.ToArray() | Select-Object -Unique)) {
        if (Test-Python $c) { $python = $c; break }
    }
    if ([string]::IsNullOrWhiteSpace($python)) {
        throw [PSCustomObject]@{ code='python_not_found'; message="no python with stdlib sqlite3+FTS5 found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'artifact_search.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="artifact_search.py not found at '$WorkerPath' (set -WorkerPath)"; retryable=$false }
    }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- write args file + invoke ----
    $argsFile = Join-Path $invDir 'as_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 30), $utf8)

    Write-Diag "python=$python worker=$WorkerPath op=$Op db=$($wargs['db'])"
    $run = Invoke-Worker $python @($WorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='artifact_search_failed'; message="worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'artifact_search_failed'); $em = [string](Prop $meta 'error' 'artifact.search worker failed')
        throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$false }
    }

    foreach ($w in @(Prop $meta 'warnings' @())) { $warnings.Add([string]$w) }
    $result = [ordered]@{
        op         = [string](Prop $meta 'op' $Op)
        result     = (Prop $meta 'result' $null)
        worker     = (Prop $meta 'worker' $null)
        runtime_ms = [int](Prop $meta 'runtime_ms' 0)
    }
    Write-Diag "ok op=$Op warnings=$($warnings.Count)"
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

# ---- artifacts (wrapper owns sha256 hashing of every file the worker wrote) ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $metaArts = @()
        try { $metaArts = @(Prop ((Get-Content -LiteralPath (Join-Path $invDir 'as_meta.json') -Raw) | ConvertFrom-Json) 'artifacts' @()) } catch { }
        foreach ($a in $metaArts) {
            $ap = [string](Prop $a 'path' ''); $ak = [string](Prop $a 'kind' 'file')
            if (-not [string]::IsNullOrWhiteSpace($ap) -and (Test-Path -LiteralPath $ap -PathType Leaf)) {
                $b = [System.IO.File]::ReadAllBytes($ap)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $ap).Path; kind=$ak; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[artifact.search] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$confidence; artifacts=$artifacts; model_provenance=$modelProvenance
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 40
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
