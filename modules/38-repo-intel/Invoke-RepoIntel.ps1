#requires -Version 7.0
<#
.SYNOPSIS
  repo.intel -- deterministic repository intelligence (Life Orchestrator, Module 38, Wave 2).
.DESCRIPTION
  Parses the repo BY SOURCE TYPE and emits TYPED record-envelope artifacts conforming to
  core-docs/MEMORY_CONTRACT.md section 1 (the record + provenance envelope v0.1), so the catalog
  (#36 artifact.search 0.2) can ingest them as FIRST-CLASS records, NOT chunks. It walks ALLOWLISTED
  roots (default modules/ + core-docs/) with TESTED exclusions (.git/venvs/model files/DBs/binaries),
  content-hashes an inventory, runs type-aware DETERMINISTIC parsers (Markdown section hierarchy;
  PowerShell function/class defs + imports; Python def/class + imports via ast; skill.json manifests;
  JSON/config structure), derives repository-intelligence RELATIONSHIPS (file->symbol, imports,
  file->module, test<->module, schema producer/consumer) as first-class `relationship` records +
  parent/child edges, builds DETERMINISTIC structural summaries (per-file outline, per-folder index),
  and VALIDATES every emitted record against MEMORY_CONTRACT s1. record_kinds: symbol|entity|
  relationship|skill|summary. CPU-only, stdlib-only Python worker (repo_intel.py), no model, no
  network -> determinism=deterministic, confidence=null, empty model_provenance, NOT a review producer.

  Ops: index (default) walks roots and emits records + manifest + inventory + ingest_records drop-in;
  validate checks an existing records artifact against s1. Canonical artifacts (records.jsonl,
  records.json, ingest_records.json, index_manifest.json, inventory.json) contain NO absolute paths,
  timestamps, or wall-clock ids -> identical corpus content yields byte-identical artifacts across runs.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes the artifacts
  above + repo_intel_meta.json + worker.log + result.json + stderr.txt. Exits 0 when a valid envelope
  is produced (a logical failure is status:error inside the envelope, still exit 0).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Root .\fixtures\repo -Namespace fixture
  pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Roots ..\..\modules,..\..\core-docs -FileBudget 200
  pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -InputsJson '{"op":"validate","records_path":"records.jsonl"}'
#>
[CmdletBinding()]
param(
    [string]$Op = 'index',
    [string[]]$Roots,
    [string]$Root,
    [string]$RootsManifest,
    [string]$Namespace,
    [string]$SourceLabel,
    [int]$FileBudget,
    [string[]]$ExcludeDirs,
    [string[]]$ExcludeGlobs,
    [string[]]$IncludeGlobs,
    [string]$RecordsPath,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'repo.intel'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[repo.intel] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-SystemPython([string]$FallbackLiteral, [string]$StartDir = $PSScriptRoot) {
    # ADDITIVE portability seam (mirrors image.util #15 / detect.objects #16): a machine config
    # (ops\setup\config.json -> python_interpreters.system) MAY relocate the SYSTEM python on a fresh
    # box. Return the CONFIGURED interpreter ONLY when it came from config, DIFFERS, and exists; else
    # return the literal UNCHANGED. Fail-closed to the literal on ANY error. Pure lookup, ASCII-only.
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
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c 'import ast,json,hashlib,re' 2>$null | Out-Null
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

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
    }
    if ($null -ne $p) {
        if ((Has $p 'op')            -and -not $bound.ContainsKey('Op'))           { $Op = [string]$p.op }
        if ((Has $p 'root')          -and -not $bound.ContainsKey('Root'))         { $Root = [string]$p.root }
        if ((Has $p 'namespace')     -and -not $bound.ContainsKey('Namespace'))    { $Namespace = [string]$p.namespace }
        if ((Has $p 'source_label')  -and -not $bound.ContainsKey('SourceLabel'))  { $SourceLabel = [string]$p.source_label }
        if ((Has $p 'records_path')  -and -not $bound.ContainsKey('RecordsPath'))  { $RecordsPath = [string]$p.records_path }
        if ((Has $p 'python_path')   -and -not $bound.ContainsKey('PythonPath'))   { $PythonPath = [string]$p.python_path }
        if ((Has $p 'worker_path')   -and -not $bound.ContainsKey('WorkerPath'))   { $WorkerPath = [string]$p.worker_path }
        if ((Has $p 'roots')         -and -not $bound.ContainsKey('Roots'))        { $Roots = @([string[]]($p.roots)) }
        if ((Has $p 'roots_manifest') -and -not $bound.ContainsKey('RootsManifest')) { $RootsManifest = [string]$p.roots_manifest }
        if ((Has $p 'exclude_dirs')  -and -not $bound.ContainsKey('ExcludeDirs'))  { $ExcludeDirs = @([string[]]($p.exclude_dirs)) }
        if ((Has $p 'exclude_globs') -and -not $bound.ContainsKey('ExcludeGlobs')) { $ExcludeGlobs = @([string[]]($p.exclude_globs)) }
        if ((Has $p 'include_globs') -and -not $bound.ContainsKey('IncludeGlobs')) { $IncludeGlobs = @([string[]]($p.include_globs)) }
    }
    $hasBudget = $bound.ContainsKey('FileBudget')
    if ($null -ne $p -and (Has $p 'file_budget') -and -not $hasBudget) { $FileBudget = [int]$p.file_budget; $hasBudget = $true }

    if ([string]::IsNullOrWhiteSpace($Op)) { $Op = 'index' }
    $Op = $Op.ToLowerInvariant()
    if (@('index','validate') -notcontains $Op) {
        throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' (index|validate)"; retryable=$false }
    }

    # ---- resolve + validate roots / records ----
    $rootAbs = @()
    if ($Op -eq 'index') {
        $rootList = New-Object System.Collections.Generic.List[string]
        if ($null -ne $Roots) { foreach ($r in @([string[]]$Roots)) { if (-not [string]::IsNullOrWhiteSpace($r)) { $rootList.Add($r) } } }
        if (-not [string]::IsNullOrWhiteSpace($Root)) { $rootList.Add($Root) }
        if ($rootList.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($RootsManifest)) {
            # i63 D-0163 (C63-12): the NARROW declarative roots manifest (ops/repo-intel-roots.json) makes
            # ops/close-txn/spec discoverable through the ordinary public entrypoint. Roots are repo-relative
            # and resolved against the manifest's repo root; every root is confined + must exist.
            if (-not (Test-Path -LiteralPath $RootsManifest -PathType Leaf)) {
                throw [PSCustomObject]@{ code='roots_manifest_not_found'; message="roots manifest not found: $RootsManifest"; retryable=$false }
            }
            $rmAbs = (Resolve-Path -LiteralPath $RootsManifest).Path
            try { $rmDoc = (Get-Content -Raw -LiteralPath $rmAbs | ConvertFrom-Json) } catch { throw [PSCustomObject]@{ code='roots_manifest_malformed'; message='roots manifest is not valid JSON'; retryable=$false } }
            $rmRoots = @()
            if (Has $rmDoc 'roots') { $rmRoots = @([string[]]$rmDoc.roots) }
            if ($rmRoots.Count -eq 0) { throw [PSCustomObject]@{ code='roots_manifest_empty'; message='roots manifest has no roots[]'; retryable=$false } }
            $repoRoot = (Split-Path -Parent (Split-Path -Parent $rmAbs))
            $seen = @{}
            foreach ($rr in $rmRoots) {
                if ([string]::IsNullOrWhiteSpace($rr) -or ($rr -match '\.\.') -or [System.IO.Path]::IsPathRooted($rr) -or ($rr -match '^[A-Za-z]:')) {
                    throw [PSCustomObject]@{ code='roots_manifest_unsafe'; message="unsafe root in manifest: $rr"; retryable=$false }
                }
                $cand = Join-Path $repoRoot $rr
                if (-not (Test-Path -LiteralPath $cand -PathType Container)) {
                    throw [PSCustomObject]@{ code='root_not_found'; message="roots-manifest root not found: $rr"; retryable=$false }
                }
                $candAbs = (Resolve-Path -LiteralPath $cand).Path
                $relToRepo = [System.IO.Path]::GetRelativePath($repoRoot, $candAbs)
                if ($relToRepo.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relToRepo)) {
                    throw [PSCustomObject]@{ code='roots_manifest_escape'; message="roots-manifest root escapes repo: $rr"; retryable=$false }
                }
                $key = $candAbs.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $rootList.Add($rr) }
            }
        }
        if ($rootList.Count -eq 0) {
            throw [PSCustomObject]@{ code='missing_root'; message='index needs -Root or -Roots (or InputsJson.root/roots[])'; retryable=$false }
        }
        foreach ($r in $rootList.ToArray()) {
            if (-not (Test-Path -LiteralPath $r -PathType Container)) {
                throw [PSCustomObject]@{ code='root_not_found'; message="root not found: $r"; retryable=$false }
            }
            $rootAbs += (Resolve-Path -LiteralPath $r).Path
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($RecordsPath)) {
            throw [PSCustomObject]@{ code='missing_records_path'; message='validate needs -RecordsPath (records.jsonl or records.json)'; retryable=$false }
        }
        if (-not (Test-Path -LiteralPath $RecordsPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='records_not_found'; message="records file not found: $RecordsPath"; retryable=$false }
        }
        $RecordsPath = (Resolve-Path -LiteralPath $RecordsPath).Path
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{
        op=$Op; roots=$rootAbs; namespace=$Namespace; source_label=$SourceLabel;
        roots_manifest=$(if ([string]::IsNullOrWhiteSpace($RootsManifest)) { $null } else { $RootsManifest });
        file_budget=$(if ($hasBudget) { [int]$FileBudget } else { $null });
        records_path=$(if ($Op -eq 'validate') { $RecordsPath } else { $null });
        exclude_dirs=$(if ($null -ne $ExcludeDirs) { @([string[]]$ExcludeDirs) } else { $null });
        exclude_globs=$(if ($null -ne $ExcludeGlobs) { @([string[]]$ExcludeGlobs) } else { $null });
        include_globs=$(if ($null -ne $IncludeGlobs) { @([string[]]$IncludeGlobs) } else { $null });
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))

    # ---- resolve python (stdlib only) ----
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    $sysPyLiteral = 'C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe'
    try { $cfgPy = Resolve-SystemPython $sysPyLiteral; if ($cfgPy -ne $sysPyLiteral) { $cands.Add($cfgPy) } } catch { }
    $cands.Add($sysPyLiteral)
    foreach ($n in @('python3','python','py')) {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $w = & where.exe $n 2>$null
            $ErrorActionPreference = $prev
            foreach ($line in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($line)) { $cands.Add($line.Trim()) } }
        } catch { }
    }
    $python = $null
    foreach ($c in $cands.ToArray()) { if (Test-Python $c) { $python = $c; break } }
    if ([string]::IsNullOrWhiteSpace($python)) {
        throw [PSCustomObject]@{ code='python_not_found'; message="no python (stdlib ast/json/hashlib) found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'repo_intel.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="repo_intel.py not found at '$WorkerPath' (set -WorkerPath)"; retryable=$false }
    }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- build worker args (args-file hand-off) ----
    $metaPath = Join-Path $invDir 'repo_intel_meta.json'
    $wargs = [ordered]@{ op = $Op; output_dir = $invDir; meta_path = $metaPath }
    if ($Op -eq 'index') {
        $wargs.roots = @($rootAbs)
        if (-not [string]::IsNullOrWhiteSpace($Namespace))    { $wargs.namespace = $Namespace }
        if (-not [string]::IsNullOrWhiteSpace($SourceLabel))  { $wargs.source_label = $SourceLabel }
        if ($hasBudget)                                       { $wargs.file_budget = [int]$FileBudget }
        if ($null -ne $ExcludeDirs)  { $wargs.exclude_dirs = @([string[]]$ExcludeDirs) }
        if ($null -ne $ExcludeGlobs) { $wargs.exclude_globs = @([string[]]$ExcludeGlobs) }
        if ($null -ne $IncludeGlobs) { $wargs.include_globs = @([string[]]$IncludeGlobs) }
    } else {
        $wargs.records_path = $RecordsPath
    }
    $argsFile = Join-Path $invDir 'repo_intel_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 8), $utf8)

    Write-Diag "python=$python worker=$WorkerPath op=$Op roots=$($rootAbs -join ';')"
    $run = Invoke-Worker $python @($WorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='repo_intel_failed'; message="repo_intel worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'repo_intel_failed'); $em = [string](Prop $meta 'error' 'repo_intel worker failed')
        throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$false }
    }

    # ---- hash the emitted artifact files (wrapper owns artifact hashing) ----
    foreach ($om in @(Prop $meta 'outputs' @())) {
        $opath = [string](Prop $om 'path' '')
        if (-not [string]::IsNullOrWhiteSpace($opath) -and (Test-Path -LiteralPath $opath -PathType Leaf)) {
            $b = [System.IO.File]::ReadAllBytes($opath)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $opath).Path; kind=[string](Prop $om 'kind' 'file'); bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    foreach ($w in @(Prop $meta 'warnings' @())) { $warnings.Add([string]$w) }

    # ---- assemble the result payload from meta (drop the raw outputs list; artifacts[] carries it) ----
    $result = [ordered]@{
        op                    = [string](Prop $meta 'op' $Op)
        namespace             = (Prop $meta 'namespace' $Namespace)
        total_records         = [int](Prop $meta 'total_records' 0)
        record_counts_by_kind = (Prop $meta 'record_counts_by_kind' $null)
        record_kinds          = (Prop $meta 'record_kinds' @())
        records_digest        = (Prop $meta 'records_digest' $null)
        file_count            = (Prop $meta 'file_count' $null)
        excluded_count        = (Prop $meta 'excluded_count' $null)
        file_budget_hit       = (Prop $meta 'file_budget_hit' $false)
        parse_failure_count   = [int](Prop $meta 'parse_failure_count' 0)
        parse_failures        = (Prop $meta 'parse_failures' @())
        validation            = (Prop $meta 'validation' $null)
        edge_summary          = (Prop $meta 'edge_summary' $null)
        ingest_run_id         = (Prop $meta 'ingest_run_id' $null)
        records_path          = (Prop $meta 'records_path' $null)
        runtime_ms            = [int](Prop $meta 'runtime_ms' 0)
        worker                = (Prop $meta 'worker' $null)
    }
    Write-Diag "ok op=$Op records=$($result.total_records) kinds=$(($result.record_kinds) -join ',') validation_ok=$(Prop $result.validation 'ok' '')"
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

# ---- stderr sidecar ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[repo.intel] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "sidecar write failed: $($_.Exception.Message)" }

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
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
