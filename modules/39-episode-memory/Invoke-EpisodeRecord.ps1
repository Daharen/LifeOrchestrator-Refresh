#requires -Version 7.0
<#
.SYNOPSIS
  episode.record -- the Wave 2 PRODUCER: DEFINE the EPISODE + FAILURE record schemas (MEMORY_CONTRACT
  s1 envelope v0.1.1, Amendment A1 / D-0085) and a DETERMINISTIC RECORDER that turns a run TRACE into a
  COMPLETE episode record -- with the full per-stage detail carried STRUCTURALLY in the episode body --
  even on failure, plus a failure-signature retrieval SEAM and an s1 VALIDATOR (Life Orchestrator module
  39, contract v0.2). Thin contract wrapper over the deterministic stdlib-only Python worker
  episode_record.py -- the worker owns all schema/id/recorder/seam logic (integer-only canonical output;
  byte-identical on a re-run, cross-machine).
.DESCRIPTION
  Ops (-Op, or op in -InputsJson; default 'record'):
    record          -Trace <run_trace.json|inline> -> an episode record (per-stage detail folded IN the
                    episode body; episode_stage is NOT a separate record, v0.1.1) + a candidate failure
                    when the run failed, an ingest_records bundle, and an s1 validation report.
                    A FAILED/TRUNCATED trace still yields a COMPLETE episode.
    build-failure   -Failures <list|path> (or -Failure <one>) -> curated failure s1 record(s).
    search-failures -TaskContext <query|path> -Corpus <records-or-descriptors|path> [-K n]
                    -> ranked matching failures (the SEAM). Unrelated failures never surface.
    validate        -Records <list|path> -> an s1 validation report (incl. provenance recomputation).
  Inputs may be passed as named params, or generically via -InputsJson '<json>' whose keys are:
    { op, trace|input, failure, failures, task_context, corpus, records, namespace, emit_failure, k,
      base_dir, python_path, worker_path }.
  The record/failure/search/validation JSON artifacts are CANONICAL (UTF-8 no BOM, sorted keys,
  integer-only) and byte-identical on a re-run; this lifeorch.skill.result/0.1 envelope carries the
  volatile diagnostics. CPU-only, no model, no network -> parallel_safe:true.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op record -Trace .\tests\fixtures\trace-success.json
  pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -InputsJson '{"op":"search-failures","task_context":"tc.json","corpus":"corpus.json"}'
#>
[CmdletBinding()]
param(
    [string]$Op,
    [string]$InputFile,
    [string]$InputsJson,
    [string]$Trace,
    [string]$Failure,
    [string]$Failures,
    [string]$TaskContext,
    [string]$Corpus,
    [string]$Records,
    [string]$Namespace,
    [nullable[bool]]$EmitFailure,
    [nullable[int]]$K,
    [string]$BaseDir,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'episode.record'; $SKILL_VERSION = '0.1.1'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[episode.record] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256Hex([byte[]]$b) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Test-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $v = & $exe -c 'import sys;sys.stdout.write(str(sys.version_info[0]))' 2>$null
        $ErrorActionPreference = $prev
        return ("$v".Trim() -eq '3')
    } catch { return $false }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]

$invDir = Join-Path $ArtifactRoot $InvocationId
try { if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null } } catch { }

try {
    # ---- parse -InputsJson ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code = 'bad_inputs_json'; message = "InputsJson is not valid JSON: $($_.Exception.Message)"; retryable = $false } }
    }

    # ---- resolve op ----
    $opName = $null
    if (-not [string]::IsNullOrWhiteSpace($Op)) { $opName = $Op }
    elseif ($null -ne $p -and (Has $p 'op')) { $opName = [string]$p.op }
    else { $opName = 'record' }
    $validOps = @('record', 'build-failure', 'search-failures', 'validate')
    if ($validOps -notcontains $opName) { throw [PSCustomObject]@{ code = 'bad_op'; message = "op must be one of: $($validOps -join ', ')"; retryable = $false } }

    # ---- carry-through generic keys from InputsJson ----
    if ($null -ne $p) {
        if (-not $bound.ContainsKey('BaseDir') -and (Has $p 'base_dir')) { $BaseDir = [string]$p.base_dir }
        if (-not $bound.ContainsKey('PythonPath') -and (Has $p 'python_path')) { $PythonPath = [string]$p.python_path }
        if (-not $bound.ContainsKey('WorkerPath') -and (Has $p 'worker_path')) { $WorkerPath = [string]$p.worker_path }
        if (-not $bound.ContainsKey('Namespace') -and (Has $p 'namespace')) { $Namespace = [string]$p.namespace }
    }

    # ---- helper: resolve an op input value (named param path > InputsJson value[path|inline] > InputFile) ----
    function Resolve-Input([string]$namedVal, [bool]$namedBound, [string[]]$jsonKeys) {
        if ($namedBound -and -not [string]::IsNullOrWhiteSpace($namedVal)) { return @{ file = $namedVal; inline = $null; kind = 'file' } }
        if ($null -ne $p) {
            foreach ($jk in $jsonKeys) {
                if (Has $p $jk) {
                    $v = $p.$jk
                    if ($v -is [string]) { return @{ file = [string]$v; inline = $null; kind = 'file' } }
                    else { return @{ file = $null; inline = $v; kind = 'inline' } }
                }
            }
        }
        return $null
    }
    function ResolveFilePath([string]$path) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw [PSCustomObject]@{ code = 'input_not_found'; message = "input file not found: $path"; retryable = $false } }
        return (Resolve-Path -LiteralPath $path).Path
    }

    # ---- base_dir ----
    if (-not [string]::IsNullOrWhiteSpace($BaseDir)) {
        if (-not (Test-Path -LiteralPath $BaseDir -PathType Container)) { throw [PSCustomObject]@{ code = 'base_dir_not_found'; message = "base_dir not found: $BaseDir"; retryable = $false } }
        $BaseDir = (Resolve-Path -LiteralPath $BaseDir).Path
    }

    # ---- resolve python ----
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    foreach ($n in @('python3', 'python', 'py')) {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $w = & where.exe $n 2>$null
            $ErrorActionPreference = $prev
            foreach ($line in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($line)) { $cands.Add($line.Trim()) } }
        } catch { }
    }
    $cands.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
    foreach ($n in @('/usr/bin/python3', '/usr/bin/python')) { $cands.Add($n) }
    $python = $null
    foreach ($c in ($cands.ToArray() | Select-Object -Unique)) { if (Test-Python $c) { $python = $c; break } }
    if ([string]::IsNullOrWhiteSpace($python)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = "no python 3 found. Set -PythonPath."; retryable = $false } }

    # ---- resolve worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'episode_record.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'worker_not_found'; message = "episode_record.py not found at '$WorkerPath'"; retryable = $false } }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- build the worker request per op ----
    $req = [ordered]@{ op = $opName; out_dir = $invDir; python = $python }
    if (-not [string]::IsNullOrWhiteSpace($BaseDir)) { $req.base_dir = $BaseDir }
    if (-not [string]::IsNullOrWhiteSpace($Namespace)) { $req.namespace = $Namespace }

    function AddInput([string]$reqKey, [hashtable]$resolved) {
        if ($resolved.kind -eq 'file') { $req[$reqKey] = (ResolveFilePath $resolved.file) }
        else { $req[$reqKey] = $resolved.inline }
    }

    if ($opName -eq 'record') {
        $r = Resolve-Input $Trace ($bound.ContainsKey('Trace')) @('trace', 'input')
        if (-not [string]::IsNullOrWhiteSpace($InputFile) -and $null -eq $r) { $r = @{ file = $InputFile; inline = $null; kind = 'file' } }
        if ($null -eq $r) { throw [PSCustomObject]@{ code = 'no_trace'; message = 'record needs -Trace (a run_trace.json path or inline object) or -InputFile'; retryable = $false } }
        AddInput 'trace' $r
        if ($bound.ContainsKey('EmitFailure') -and $null -ne $EmitFailure) { $req.emit_failure = [bool]$EmitFailure }
        elseif ($null -ne $p -and (Has $p 'emit_failure')) { $req.emit_failure = [bool]$p.emit_failure }
    }
    elseif ($opName -eq 'build-failure') {
        $rl = Resolve-Input $Failures ($bound.ContainsKey('Failures')) @('failures')
        $rs = Resolve-Input $Failure ($bound.ContainsKey('Failure')) @('failure', 'input')
        if ($null -ne $rl) { AddInput 'failures' $rl }
        elseif ($null -ne $rs) { AddInput 'failure' $rs }
        elseif (-not [string]::IsNullOrWhiteSpace($InputFile)) { $req.failures = (ResolveFilePath $InputFile) }
        else { throw [PSCustomObject]@{ code = 'no_failure'; message = 'build-failure needs -Failures (list) or -Failure (one) or -InputFile'; retryable = $false } }
    }
    elseif ($opName -eq 'search-failures') {
        $rt = Resolve-Input $TaskContext ($bound.ContainsKey('TaskContext')) @('task_context', 'input')
        $rc = Resolve-Input $Corpus ($bound.ContainsKey('Corpus')) @('corpus')
        if ($null -eq $rt) { throw [PSCustomObject]@{ code = 'no_task_context'; message = 'search-failures needs -TaskContext'; retryable = $false } }
        if ($null -eq $rc) { throw [PSCustomObject]@{ code = 'no_corpus'; message = 'search-failures needs -Corpus'; retryable = $false } }
        AddInput 'task_context' $rt
        AddInput 'corpus' $rc
        if ($bound.ContainsKey('K') -and $null -ne $K) { $req.k = [int]$K }
        elseif ($null -ne $p -and (Has $p 'k')) { $req.k = [int]$p.k }
    }
    elseif ($opName -eq 'validate') {
        $rr = Resolve-Input $Records ($bound.ContainsKey('Records')) @('records', 'input')
        if (-not [string]::IsNullOrWhiteSpace($InputFile) -and $null -eq $rr) { $rr = @{ file = $InputFile; inline = $null; kind = 'file' } }
        if ($null -eq $rr) { throw [PSCustomObject]@{ code = 'no_records'; message = 'validate needs -Records (a records list/bundle path or inline) or -InputFile'; retryable = $false } }
        AddInput 'records' $rr
    }

    $reqPath = Join-Path $invDir 'request.json'
    [System.IO.File]::WriteAllText($reqPath, ($req | ConvertTo-Json -Depth 60), $utf8)

    # ---- invoke the worker (small stdout -> no pipe-deadlock; stderr captured to a file) ----
    Write-Diag "op=$opName python=$python worker=$WorkerPath out=$invDir"
    $errFile = Join-Path $invDir 'worker-stderr.txt'
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $stdout = & $python $WorkerPath '--request' $reqPath 2>$errFile
    $wexit = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Write-Diag "worker exit=$wexit stdout=$(( [string]($stdout | Out-String)).Trim())"

    $summaryPath = Join-Path $invDir 'worker-summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        $tail = ''
        try { $tail = [string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) } catch { }
        $tail = ($tail -replace '\s+', ' ').Trim()
        if ($tail.Length -gt 400) { $tail = $tail.Substring(0, 400) }
        throw [PSCustomObject]@{ code = 'worker_no_summary'; message = "worker produced no worker-summary.json (exit=$wexit). stderr tail: $tail"; retryable = $false }
    }
    $summary = (Get-Content -LiteralPath $summaryPath -Raw) | ConvertFrom-Json

    $summaryOk = $false; if (Has $summary 'ok') { $summaryOk = [bool]$summary.ok }
    if (-not $summaryOk) {
        $we = if (Has $summary 'error') { $summary.error } else { $null }
        $status = 'error'
        $errorObj = [ordered]@{
            code      = [string]$(if ($null -ne $we -and (Has $we 'code')) { $we.code } else { 'episode_record_failed' })
            message   = [string]$(if ($null -ne $we -and (Has $we 'message')) { $we.message } else { 'worker reported failure' })
            retryable = [bool]$(if ($null -ne $we -and (Has $we 'retryable')) { $we.retryable } else { $false })
        }
    } else {
        # project the summary into the result (op-specific but tolerant of missing keys)
        $result = [ordered]@{ op = $opName }
        foreach ($f in @('namespace', 'episode_record_id', 'episode_version_id', 'episode_final_status',
                'stage_count', 'failure_emitted', 'failure_record_id', 'failure_signature',
                'record_count', 'records_digest', 'all_valid', 'record_ids', 'failure_signatures',
                'corpus_size', 'match_count', 'result_ids', 'top_record_id', 'search_digest',
                'num_records', 'num_valid')) {
            if (Has $summary $f) { $result[$f] = $summary.$f }
        }
        $inputsDigest = [string]$(if (Has $summary 'records_digest') { $summary.records_digest } elseif (Has $summary 'search_digest') { $summary.search_digest } else { $null })
    }
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and ($ex.PSObject.Properties.Name -contains 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
    }
    Write-Diag "ERROR: $($errorObj.message)"
}

# ---- artifacts (absolute paths + sha256; every canonical file the worker wrote + worker-summary.json) ----
try {
    $artList = New-Object System.Collections.Generic.List[object]
    $names = @('episode.json', 'episode_stages.json', 'failure.json', 'failures.json', 'records.json',
        'search.json', 'validation.json', 'worker-summary.json')
    foreach ($n in $names) {
        $fp = Join-Path $invDir $n
        if (Test-Path -LiteralPath $fp -PathType Leaf) {
            $b = [System.IO.File]::ReadAllBytes($fp)
            $artList.Add([ordered]@{ path = (Resolve-Path -LiteralPath $fp).Path; kind = 'json'; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
        }
    }
    $artifacts = $artList.ToArray()
} catch { }

if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }
if ([string]::IsNullOrWhiteSpace($inputsDigest)) { $inputsDigest = 'sha256:' + (Get-Sha256Hex ($utf8.GetBytes(($InvocationId + '|' + $status)))) }

$finishedAt = [DateTime]::UtcNow
$sw.Stop()
$envelope = [ordered]@{
    schema           = $RESULT_SCHEMA
    skill_id         = $SKILL_ID
    skill_version    = $SKILL_VERSION
    contract_version = $CONTRACT
    invocation_id    = $InvocationId
    status           = $status
    started_at_utc   = $startedAt.ToString('o')
    finished_at_utc  = $finishedAt.ToString('o')
    duration_ms      = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest    = $inputsDigest
    result           = $result
    confidence       = $null
    artifacts        = $artifacts
    model_provenance = @()
    diagnostics      = [ordered]@{ log = 'worker-stderr.txt' }
    warnings         = $warnings.ToArray()
    error            = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 40
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
