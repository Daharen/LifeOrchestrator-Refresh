#requires -Version 7.0
<#
.SYNOPSIS
  retrieval.eval -- run a retrieval-quality BENCHMARK against ANY retriever satisfying the D-0077
  retriever interface, and emit deterministic machine- + human-readable reports (Life Orchestrator
  module 37, contract v0.2, Wave 1 CPU lane). Thin contract wrapper over the deterministic Python
  worker retrieval_eval.py -- the worker owns all metric/report logic (integer-only canonical output).
.DESCRIPTION
  Inputs (named or via -InputsJson '<json>'):
    input / benchmark  a benchmark JSON (a file path, or an inline benchmark object) --
                       schema lifeorch.retrieval_benchmark/0.1: {benchmark_id, corpus_dir?, retriever?,
                       k_values?, retrieval_depth?, queries:[{query_id, query, required_sources[],
                       stale_sources?[], forbidden_sources?[], filters?}]}.
    corpus_dir         override the baseline corpus dir (else benchmark.retriever.corpus_dir / benchmark.corpus_dir).
    retriever          override the retriever spec (an object, or a JSON string via -RetrieverJson).
    k_values           override the K set (array of ints).
    retrieval_depth    override the max hits requested from the retriever (>= max(k_values)).
    base_dir           dir used to resolve a relative corpus_dir / external-retriever argv paths
                       (default = the benchmark file's directory).
  A required source is MATCHED only when source_path AND (if labelled) content_hash match -- a right
  path with a STALE/superseded hash is a MISS (and is reported). Metrics: recall@K, MRR, stale-source
  rate, provenance completeness, forbidden-hit rate. The report artifacts (report.json + report.md) are
  CANONICAL and byte-identical on a re-run (this envelope carries the volatile diagnostics).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json
  pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputsJson '{"benchmark":"tests/fixtures/benchmark.json"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$InputsJson,
    [string]$Op,
    [string]$CorpusDir,
    [string]$RetrieverJson,
    [int[]]$KValues,
    [int]$RetrievalDepth,
    [string]$BaseDir,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'retrieval.eval'; $SKILL_VERSION = '0.7.0'; $CONTRACT = '0.7'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[retrieval.eval] $m") }
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

# artifact dir
$invDir = Join-Path $ArtifactRoot $InvocationId
try { if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null } } catch { }

# ---- i34 HIERARCHY-EVAL op (D-0098): a SELF-CONTAINED, isolated path. It fires ONLY on -Op hierarchy-eval
#      (or InputsJson.op == hierarchy-eval); the benchmark path below is UNCHANGED + byte-identical otherwise. ----
$opRequested = $Op
if ([string]::IsNullOrWhiteSpace($opRequested) -and -not [string]::IsNullOrWhiteSpace($InputsJson)) {
    try { $ppo0 = $InputsJson | ConvertFrom-Json; if ($null -ne $ppo0 -and (Has $ppo0 'op')) { $opRequested = [string]$ppo0.op } } catch {}
}
if ($opRequested -eq 'hierarchy-eval') {
    $hstatus = 'ok'; $herr = $null; $hresult = $null; $hInputsDigest = $null
    try {
        $ppo = $null
        if (-not [string]::IsNullOrWhiteSpace($InputsJson)) { $ppo = $InputsJson | ConvertFrom-Json }
        $hc = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $hc.Add($PythonPath) }
        foreach ($n in @('python3', 'python', 'py')) { try { $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $w = & where.exe $n 2>$null; $ErrorActionPreference = $prev; foreach ($l in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($l)) { $hc.Add($l.Trim()) } } } catch {} }
        $hc.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
        foreach ($n in @('/usr/bin/python3', '/usr/bin/python')) { $hc.Add($n) }
        $hpy = $null; foreach ($c in ($hc.ToArray() | Select-Object -Unique)) { if (Test-Python $c) { $hpy = $c; break } }
        if ([string]::IsNullOrWhiteSpace($hpy)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = 'no python 3 found. Set -PythonPath.'; retryable = $false } }
        $hworker = if (-not [string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath } else { Join-Path $PSScriptRoot 'hierarchy_eval.py' }
        if (-not (Test-Path -LiteralPath $hworker -PathType Leaf)) { throw [PSCustomObject]@{ code = 'worker_not_found'; message = "hierarchy_eval.py not found at '$hworker'"; retryable = $false } }
        $hworker = (Resolve-Path -LiteralPath $hworker).Path
        $hreq = [ordered]@{ op = 'hierarchy-eval'; out_dir = $invDir }
        if ($null -ne $ppo) { foreach ($k in @('scales', 'seed', 'fanout', 'beam', 'adapter', 'ns_policy_path')) { if (Has $ppo $k) { $hreq[$k] = $ppo.$k } } }
        $hreqPath = Join-Path $invDir 'request.json'
        [System.IO.File]::WriteAllText($hreqPath, ($hreq | ConvertTo-Json -Depth 30), $utf8)
        Write-Diag "op=hierarchy-eval python=$hpy worker=$hworker out=$invDir"
        $herrFile = Join-Path $invDir 'worker-stderr.txt'
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $hout = & $hpy $hworker '--request' $hreqPath 2>$herrFile
        $hexit = $LASTEXITCODE; $ErrorActionPreference = $prev
        $hsumPath = Join-Path $invDir 'worker-summary.json'
        if (-not (Test-Path -LiteralPath $hsumPath -PathType Leaf)) { $t = ''; try { $t = [string](Get-Content -LiteralPath $herrFile -Raw -ErrorAction SilentlyContinue) } catch {}; $t = ($t -replace '\s+', ' ').Trim(); if ($t.Length -gt 400) { $t = $t.Substring(0, 400) }; throw [PSCustomObject]@{ code = 'worker_no_summary'; message = "hierarchy worker produced no summary (exit=$hexit). stderr: $t"; retryable = $false } }
        $hsum = (Get-Content -LiteralPath $hsumPath -Raw) | ConvertFrom-Json
        if (-not ([bool]$hsum.ok)) { $we = if (Has $hsum 'error') { $hsum.error } else { $null }; $hstatus = 'error'; $herr = [ordered]@{ code = [string]$(if ($null -ne $we -and (Has $we 'code')) { $we.code } else { 'hierarchy_eval_failed' }); message = [string]$(if ($null -ne $we -and (Has $we 'message')) { $we.message } else { 'worker failed' }); retryable = $false } }
        else {
            $hInputsDigest = [string]$hsum.input_digest
            $hresult = [ordered]@{}
            foreach ($f in @('op', 'hierarchy_eval_version', 'scales', 'sublinear', 'not_constant', 'hierarchy_path_recall_ppm', 'guaranteed_path_recall_ppm', 'packet_evidence_recall_ppm', 'fallback_frequency_ppm', 'stale_window_recall_ppm', 'adversarial_passed', 'adversarial_total', 'tier1_gates_passed', 'tier1_gates_total', 'rehearsal_gate_status', 'tier1_accepted', 'report_digest')) { if (Has $hsum $f) { $hresult[$f] = $hsum.$f } }
        }
    }
    catch {
        $ex = $_.TargetObject
        if ($null -ne $ex -and ($ex.PSObject.Properties.Name -contains 'code')) { $hstatus = 'error'; $herr = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable } }
        else { $hstatus = 'error'; $herr = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false } }
        Write-Diag "hierarchy ERROR: $($herr.message)"
    }
    $hart = New-Object System.Collections.Generic.List[object]
    foreach ($n in @('hierarchy_report.json', 'hierarchy_report.md', 'worker-summary.json')) { $fp = Join-Path $invDir $n; if (Test-Path -LiteralPath $fp -PathType Leaf) { $b = [System.IO.File]::ReadAllBytes($fp); $hart.Add([ordered]@{ path = (Resolve-Path -LiteralPath $fp).Path; kind = $(if ($n -like '*.md') { 'markdown' } else { 'json' }); bytes = $b.Length; sha256 = (Get-Sha256Hex $b) }) } }
    if ([string]::IsNullOrWhiteSpace($hInputsDigest)) { $hInputsDigest = 'sha256:' + (Get-Sha256Hex ($utf8.GetBytes(($InvocationId + '|' + $hstatus)))) }
    $sw.Stop()
    $henv = [ordered]@{ schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT; invocation_id = $InvocationId; status = $hstatus; started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o'); duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $hInputsDigest; result = $hresult; confidence = $null; artifacts = $hart.ToArray(); model_provenance = @(); diagnostics = [ordered]@{ log = 'worker-stderr.txt' }; warnings = @(); error = $herr }
    $hjson = $henv | ConvertTo-Json -Depth 30
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $hjson, $utf8) } catch {}
    [Console]::Out.WriteLine($hjson)
    exit 0
}

# ---- i35 REHEARSAL op (plan fo-35-0a5bf334): the Tier-1 ACCEPTANCE-GATE rehearsal harness. A SELF-CONTAINED,
#      isolated path firing ONLY on -Op rehearsal (or InputsJson.op == rehearsal); the benchmark + hierarchy-eval
#      paths are UNCHANGED + byte-identical otherwise. Ingests a REAL foreign corpus into a #36 hierarchy, runs the
#      labeled query set, measures the MEMORY_ARCHITECTURE s10 criteria via the external_command adapter, and emits
#      a computed tier1_accepted (over the corpus+CLI it is pointed at -- NOT a project-level claim). ----
if ($opRequested -eq 'rehearsal') {
    $rstatus = 'ok'; $rerr = $null; $rresult = $null; $rInputsDigest = $null
    try {
        $ppo = $null
        if (-not [string]::IsNullOrWhiteSpace($InputsJson)) { $ppo = $InputsJson | ConvertFrom-Json }
        $rc = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $rc.Add($PythonPath) }
        foreach ($n in @('python3', 'python', 'py')) { try { $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $w = & where.exe $n 2>$null; $ErrorActionPreference = $prev; foreach ($l in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($l)) { $rc.Add($l.Trim()) } } } catch {} }
        $rc.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
        foreach ($n in @('/usr/bin/python3', '/usr/bin/python')) { $rc.Add($n) }
        $rpy = $null; foreach ($c in ($rc.ToArray() | Select-Object -Unique)) { if (Test-Python $c) { $rpy = $c; break } }
        if ([string]::IsNullOrWhiteSpace($rpy)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = 'no python 3 found. Set -PythonPath.'; retryable = $false } }
        $rworker = if (-not [string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath } else { Join-Path $PSScriptRoot 'rehearsal_eval.py' }
        if (-not (Test-Path -LiteralPath $rworker -PathType Leaf)) { throw [PSCustomObject]@{ code = 'worker_not_found'; message = "rehearsal_eval.py not found at '$rworker'"; retryable = $false } }
        $rworker = (Resolve-Path -LiteralPath $rworker).Path
        $rreq = [ordered]@{ op = 'rehearsal'; out_dir = $invDir }
        if ($null -ne $ppo) { foreach ($k in @('benchmark', 'corpus_root', 'fixtures_dir', 'adapter', 'scales', 'fanout', 'config')) { if (Has $ppo $k) { $rreq[$k] = $ppo.$k } } }
        $rreqPath = Join-Path $invDir 'request.json'
        [System.IO.File]::WriteAllText($rreqPath, ($rreq | ConvertTo-Json -Depth 30), $utf8)
        Write-Diag "op=rehearsal python=$rpy worker=$rworker out=$invDir"
        $rerrFile = Join-Path $invDir 'worker-stderr.txt'
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $rout = & $rpy $rworker '--request' $rreqPath 2>$rerrFile
        $rexit = $LASTEXITCODE; $ErrorActionPreference = $prev
        $rsumPath = Join-Path $invDir 'worker-summary.json'
        if (-not (Test-Path -LiteralPath $rsumPath -PathType Leaf)) { $t = ''; try { $t = [string](Get-Content -LiteralPath $rerrFile -Raw -ErrorAction SilentlyContinue) } catch {}; $t = ($t -replace '\s+', ' ').Trim(); if ($t.Length -gt 400) { $t = $t.Substring(0, 400) }; throw [PSCustomObject]@{ code = 'worker_no_summary'; message = "rehearsal worker produced no summary (exit=$rexit). stderr: $t"; retryable = $false } }
        $rsum = (Get-Content -LiteralPath $rsumPath -Raw) | ConvertFrom-Json
        if (-not ([bool]$rsum.ok)) { $we = if (Has $rsum 'error') { $rsum.error } else { $null }; $rstatus = 'error'; $rerr = [ordered]@{ code = [string]$(if ($null -ne $we -and (Has $we 'code')) { $we.code } else { 'rehearsal_eval_failed' }); message = [string]$(if ($null -ne $we -and (Has $we 'message')) { $we.message } else { 'worker failed' }); retryable = $false } }
        else {
            $rInputsDigest = [string]$rsum.report_digest
            $rresult = [ordered]@{}
            foreach ($f in @('op', 'rehearsal_harness_version', 'benchmark_id', 'adapter_kind', 'tier1_criteria_passed', 'tier1_criteria_total', 'tier1_accepted', 'fold_reconciliation', 'navigation_sublinear', 'bounded_context_cost', 'scale_packet_evidence_recall_ppm', 'adapter_calls', 'report_digest')) { if (Has $rsum $f) { $rresult[$f] = $rsum.$f } }
        }
    }
    catch {
        $ex = $_.TargetObject
        if ($null -ne $ex -and ($ex.PSObject.Properties.Name -contains 'code')) { $rstatus = 'error'; $rerr = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable } }
        else { $rstatus = 'error'; $rerr = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false } }
        Write-Diag "rehearsal ERROR: $($rerr.message)"
    }
    $rart = New-Object System.Collections.Generic.List[object]
    foreach ($n in @('rehearsal_report.json', 'rehearsal_report.md', 'worker-summary.json')) { $fp = Join-Path $invDir $n; if (Test-Path -LiteralPath $fp -PathType Leaf) { $b = [System.IO.File]::ReadAllBytes($fp); $rart.Add([ordered]@{ path = (Resolve-Path -LiteralPath $fp).Path; kind = $(if ($n -like '*.md') { 'markdown' } else { 'json' }); bytes = $b.Length; sha256 = (Get-Sha256Hex $b) }) } }
    if ([string]::IsNullOrWhiteSpace($rInputsDigest)) { $rInputsDigest = 'sha256:' + (Get-Sha256Hex ($utf8.GetBytes(($InvocationId + '|' + $rstatus)))) }
    $sw.Stop()
    $renv = [ordered]@{ schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT; invocation_id = $InvocationId; status = $rstatus; started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o'); duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $rInputsDigest; result = $rresult; confidence = $null; artifacts = $rart.ToArray(); model_provenance = @(); diagnostics = [ordered]@{ log = 'worker-stderr.txt' }; warnings = @(); error = $rerr }
    $rjson = $renv | ConvertTo-Json -Depth 30
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $rjson, $utf8) } catch {}
    [Console]::Out.WriteLine($rjson)
    exit 0
}

try {
    # ---- parse -InputsJson ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code = 'bad_inputs_json'; message = "InputsJson is not valid JSON: $($_.Exception.Message)"; retryable = $false } }
    }
    if ($null -ne $p) {
        if (-not $bound.ContainsKey('CorpusDir') -and (Has $p 'corpus_dir')) { $CorpusDir = [string]$p.corpus_dir }
        if (-not $bound.ContainsKey('BaseDir') -and (Has $p 'base_dir')) { $BaseDir = [string]$p.base_dir }
        if (-not $bound.ContainsKey('RetrievalDepth') -and (Has $p 'retrieval_depth')) { $RetrievalDepth = [int]$p.retrieval_depth }
        if (-not $bound.ContainsKey('PythonPath') -and (Has $p 'python_path')) { $PythonPath = [string]$p.python_path }
        if (-not $bound.ContainsKey('WorkerPath') -and (Has $p 'worker_path')) { $WorkerPath = [string]$p.worker_path }
    }

    # ---- resolve the benchmark input (precedence: -InputFile > InputsJson.benchmark/input) ----
    $benchmarkValue = $null   # either an absolute file path (string) or an inline object
    $benchmarkIsFile = $false
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        $benchmarkValue = $InputFile; $benchmarkIsFile = $true
    } elseif ($null -ne $p -and (Has $p 'benchmark')) {
        if ($p.benchmark -is [string]) { $benchmarkValue = [string]$p.benchmark; $benchmarkIsFile = $true }
        else { $benchmarkValue = $p.benchmark }
    } elseif ($null -ne $p -and (Has $p 'input')) {
        if ($p.input -is [string]) { $benchmarkValue = [string]$p.input; $benchmarkIsFile = $true }
        else { $benchmarkValue = $p.input }
    }
    if ($null -eq $benchmarkValue) { throw [PSCustomObject]@{ code = 'no_benchmark'; message = 'provide -InputFile or InputsJson.benchmark (a path or inline object)'; retryable = $false } }
    if ($benchmarkIsFile) {
        if (-not (Test-Path -LiteralPath $benchmarkValue -PathType Leaf)) { throw [PSCustomObject]@{ code = 'benchmark_not_found'; message = "benchmark file not found: $benchmarkValue"; retryable = $false } }
        $benchmarkValue = (Resolve-Path -LiteralPath $benchmarkValue).Path
        if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = Split-Path -Parent $benchmarkValue }
    }
    if (-not [string]::IsNullOrWhiteSpace($BaseDir)) {
        if (-not (Test-Path -LiteralPath $BaseDir -PathType Container)) { throw [PSCustomObject]@{ code = 'base_dir_not_found'; message = "base_dir not found: $BaseDir"; retryable = $false } }
        $BaseDir = (Resolve-Path -LiteralPath $BaseDir).Path
    }

    # ---- retriever spec override ----
    $retrieverSpec = $null
    if (-not [string]::IsNullOrWhiteSpace($RetrieverJson)) {
        try { $retrieverSpec = $RetrieverJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code = 'bad_retriever_json'; message = "RetrieverJson is not valid JSON: $($_.Exception.Message)"; retryable = $false } }
    } elseif ($null -ne $p -and (Has $p 'retriever')) {
        $retrieverSpec = $p.retriever
    }

    # ---- k_values override ----
    $kv = $null
    if ($bound.ContainsKey('KValues') -and $null -ne $KValues) { $kv = @($KValues) }
    elseif ($null -ne $p -and (Has $p 'k_values')) { $kv = @($p.k_values | ForEach-Object { [int]$_ }) }

    # ---- resolve python (worker uses only the stdlib -> any python3 works) ----
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
    if ([string]::IsNullOrWhiteSpace($python)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = "no python 3 found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable = $false } }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'retrieval_eval.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'worker_not_found'; message = "retrieval_eval.py not found at '$WorkerPath'"; retryable = $false } }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- build the worker request ----
    $req = [ordered]@{ benchmark = $benchmarkValue; out_dir = $invDir; python = $python }
    if (-not [string]::IsNullOrWhiteSpace($BaseDir)) { $req.base_dir = $BaseDir }
    if (-not [string]::IsNullOrWhiteSpace($CorpusDir)) { $req.corpus_dir = $CorpusDir }
    if ($null -ne $retrieverSpec) { $req.retriever = $retrieverSpec }
    if ($null -ne $kv) { $req.k_values = $kv }
    if ($bound.ContainsKey('RetrievalDepth') -or ($null -ne $p -and (Has $p 'retrieval_depth'))) { if ($RetrievalDepth -gt 0) { $req.retrieval_depth = [int]$RetrievalDepth } }
    $reqPath = Join-Path $invDir 'request.json'
    [System.IO.File]::WriteAllText($reqPath, ($req | ConvertTo-Json -Depth 30), $utf8)

    # ---- invoke the worker (tiny output -> no pipe-deadlock risk; stderr captured to a file) ----
    Write-Diag "python=$python worker=$WorkerPath out=$invDir"
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
            code      = [string]$(if ($null -ne $we -and (Has $we 'code')) { $we.code } else { 'retrieval_eval_failed' })
            message   = [string]$(if ($null -ne $we -and (Has $we 'message')) { $we.message } else { 'worker reported failure' })
            retryable = [bool]$(if ($null -ne $we -and (Has $we 'retryable')) { $we.retryable } else { $false })
        }
    } else {
        $inputsDigest = [string]$summary.input_digest
        $agg = $summary.aggregate
        $result = [ordered]@{
            benchmark_id         = $(if (Has $summary 'benchmark_id') { [string]$summary.benchmark_id } else { $null })
            benchmark_schema     = $(if (Has $summary 'benchmark_schema') { [string]$summary.benchmark_schema } else { $null })
            retriever_kind       = [string]$summary.retriever_kind
            num_queries          = [int]$summary.num_queries
            k_values             = @($summary.k_values)
            retrieval_depth      = [int]$summary.retrieval_depth
            ratio_unit           = [string]$summary.ratio_unit
            provenance_validated = $(if (Has $summary 'provenance_validated') { [bool]$summary.provenance_validated } else { $null })
            vector_channel_status = $(if (Has $summary 'vector_channel_status') { [string]$summary.vector_channel_status } else { $null })
            aggregate            = $agg
            aggregate_reranked   = $(if (Has $summary 'aggregate_reranked') { $summary.aggregate_reranked } else { $null })
            rerank_ab            = $(if (Has $summary 'rerank_ab') { $summary.rerank_ab } else { $null })
            report_json          = [ordered]@{ path = [string]$summary.report_json.path; sha256 = [string]$summary.report_json.sha256; bytes = [int]$summary.report_json.bytes }
            report_md            = [ordered]@{ path = [string]$summary.report_md.path; sha256 = [string]$summary.report_md.sha256; bytes = [int]$summary.report_md.bytes }
            input_digest         = $inputsDigest
        }
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

# ---- artifacts (absolute paths + sha256; report.json, report.md, worker-summary.json) ----
try {
    $artList = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @(
        @{ name = 'report.json'; kind = 'json' },
        @{ name = 'report.md'; kind = 'markdown' },
        @{ name = 'worker-summary.json'; kind = 'json' }
    )) {
        $fp = Join-Path $invDir $spec.name
        if (Test-Path -LiteralPath $fp -PathType Leaf) {
            $b = [System.IO.File]::ReadAllBytes($fp)
            $artList.Add([ordered]@{ path = (Resolve-Path -LiteralPath $fp).Path; kind = $spec.kind; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
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
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
