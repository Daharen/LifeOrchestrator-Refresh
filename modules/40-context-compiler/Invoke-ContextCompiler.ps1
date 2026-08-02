#requires -Version 7.0
<#
.SYNOPSIS
  context.compile -- deterministic context-packet compiler (Life Orchestrator, Module 40, contract v0.2).
  The Collective Agent's context-compilation centerpiece (directive Priority 4 / section 8).
.DESCRIPTION
  A thin PowerShell entrypoint over a stdlib-only Python worker (context_compiler.py) that turns a task
  descriptor into a versioned, token-budgeted lifeorch.context_packet/0.1 artifact:

    normalize (8.1) -> candidate retrieval via a DEFINED seam (8.2) -> deterministic rerank + diversity
    (8.3) -> token budget with exact accounting (8.4/16.3) -> context_packet/0.1 with full source
    provenance + omitted-context + eval hooks (8.4/8.6); a deterministic `expand` seam (8.5).

  The RETRIEVER is a seam, never called from the deterministic worker:
    -Retriever mock            reads a case file / -InputsJson carrying {task, retrieval_batches,
                               source_texts, retrieval_meta} -- deterministic fixture 0.2 hits (off-machine).
    -Retriever artifact_search wires the REAL artifact.search #36 `search` op (-Live): normalize -> run
                               #36 per derived query -> compile over the gathered retriever-0.2 hits.

  Ops: compile | normalize | expand. CPU-only, no model, no network -> determinism=deterministic,
  confidence=null, empty model_provenance. Emits one lifeorch.skill.result/0.1 envelope on stdout;
  diagnostics to stderr. The context_packet.json artifact is byte-identical across runs (canonical JSON).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever mock -CaseFile .\fixtures\compile_case.json
  pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever artifact_search -Task .\task.json -Db ..\36-artifact-search\runtime\catalog\as.db -RepoRoot ..\..
#>
[CmdletBinding()]
param(
    [string]$Op = 'compile',
    [ValidateSet('mock','artifact_search')]
    [string]$Retriever = 'mock',
    [string]$CaseFile,
    [string]$Task,
    [string]$Request,
    [string]$PacketFile,
    [string]$DbPath,
    [string]$RepoRoot,
    [int]$K = 20,
    [string]$ArtifactSearchEntry,
    [string]$InputsJson,
    [string]$PythonPath,
    [string]$PwshPath,
    [string]$WorkerPath,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'context.compile'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[context.compile] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Read-JsonArg([string]$v) {
    # accept a path to a .json OR an inline JSON string
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    if (Test-Path -LiteralPath $v -PathType Leaf) {
        return (Get-Content -LiteralPath $v -Raw) | ConvertFrom-Json -Depth 60
    }
    return $v | ConvertFrom-Json -Depth 60
}
function Test-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c "import json,hashlib,re,math" 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}
function Invoke-Proc([string]$exe, [string[]]$argv) {
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
$VALID_OPS = @('compile','normalize','expand')

# ---- resolve python (stdlib only) ----
function Resolve-Python {
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    $cands.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
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
    foreach ($c in ($cands.ToArray() | Select-Object -Unique)) { if (Test-Python $c) { return $c } }
    return $null
}

# ---- invoke our deterministic worker with an args object; return the parsed meta ----
function Invoke-CCWorker([hashtable]$argsObj, [string]$python, [string]$worker, [string]$tag) {
    $subDir = Join-Path $invDir $tag
    New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    $argsObj['output_dir'] = $subDir
    $metaPath = Join-Path $subDir 'cc_meta.json'
    $argsObj['meta_path'] = $metaPath
    $argsFile = Join-Path $subDir 'cc_args.json'
    [System.IO.File]::WriteAllText($argsFile, (($argsObj | ConvertTo-Json -Depth 60)), $utf8)
    $run = Invoke-Proc $python @($worker, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $subDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='worker_no_meta'; message="worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json -Depth 60
    if (-not [bool](Prop $meta 'ok' $false)) {
        throw [PSCustomObject]@{ code=[string](Prop $meta 'error_code' 'worker_error'); message=[string](Prop $meta 'error' 'context_compiler worker failed'); retryable=$false }
    }
    return @{ meta = $meta; dir = $subDir }
}

# ---- resolve a usable pwsh to launch the #36 entrypoint (the dotnet-tool shim reports as dotnet.exe) ----
function Resolve-Pwsh {
    if (-not [string]::IsNullOrWhiteSpace($PwshPath) -and (Test-Path -LiteralPath $PwshPath -PathType Leaf)) { return $PwshPath }
    foreach ($c in @((Join-Path $PSHOME 'pwsh.exe'), (Join-Path $PSHOME 'pwsh'),
                     'C:\Users\just_\.dotnet\tools\pwsh.exe')) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return 'pwsh'
}

# ---- the RETRIEVER SEAM: run the REAL artifact.search #36 `search` for one derived query -> 0.2 hits ----
function Invoke-ArtifactSearchQuery([pscustomobject]$q, [string]$db, [string]$asEntry) {
    $inObj = [ordered]@{ op = 'search'; db = $db; query = [string](Prop $q 'query'); mode = [string](Prop $q 'mode' 'fts'); k = [int](Prop $q 'k' $K) }
    $filters = Prop $q 'filters' $null
    if ($null -ne $filters -and $null -ne $filters.PSObject) {
        # build directly (NEVER `.Properties.Name.Count`: a single-property object makes `.Name` a
        # scalar string and `.Count` throws under StrictMode -- the scalar-.Count trap).
        $fh = [ordered]@{}
        foreach ($pr in $filters.PSObject.Properties) { $fh[$pr.Name] = $pr.Value }
        if ($fh.Count -gt 0) { $inObj['filters'] = $fh }
    }
    $inJson = $inObj | ConvertTo-Json -Depth 30 -Compress
    $pwsh = Resolve-Pwsh
    $run = Invoke-Proc $pwsh @('-NoProfile','-File',$asEntry,'-InputsJson',$inJson)
    $envText = ([string]$run.out).Trim()
    if ([string]::IsNullOrWhiteSpace($envText)) {
        throw [PSCustomObject]@{ code='artifact_search_no_output'; message="#36 search returned no envelope (exit $($run.exit)): $([string]$run.err)"; retryable=$true }
    }
    $env = $envText | ConvertFrom-Json -Depth 60
    if ([string](Prop $env 'status' 'error') -eq 'error') {
        $e = Prop $env 'error' $null
        throw [PSCustomObject]@{ code='artifact_search_error'; message="#36 search error: $([string](Prop $e 'message' 'unknown'))"; retryable=$false }
    }
    $payload = Prop (Prop $env 'result' $null) 'result' $null
    $hits = @(Prop $payload 'results' @())
    # return the array PLAIN (no comma-wrap); every call site captures with @(...) so 0/1/many hits
    # all yield a correct flat array (comma-wrap + @() would DOUBLE-wrap -- the array double-wrap trap).
    return $hits
}

try {
    $Op = $Op.ToLowerInvariant()
    if ($VALID_OPS -notcontains $Op) { throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' ($($VALID_OPS -join '|'))"; retryable=$false } }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $python = Resolve-Python
    if ([string]::IsNullOrWhiteSpace($python)) { throw [PSCustomObject]@{ code='python_not_found'; message='no usable python (stdlib) found; set -PythonPath'; retryable=$false } }
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'context_compiler.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) { throw [PSCustomObject]@{ code='worker_not_found'; message="context_compiler.py not found at '$WorkerPath'"; retryable=$false } }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path
    if ([string]::IsNullOrWhiteSpace($ArtifactSearchEntry)) { $ArtifactSearchEntry = Join-Path $PSScriptRoot '..\36-artifact-search\Invoke-ArtifactSearch.ps1' }

    # ---- assemble the case (generic InputsJson / CaseFile) ----
    $case = $null
    if (-not [string]::IsNullOrWhiteSpace($CaseFile)) { $case = Read-JsonArg $CaseFile }
    elseif (-not [string]::IsNullOrWhiteSpace($InputsJson)) { $case = $InputsJson | ConvertFrom-Json -Depth 60 }

    # ---- resolve the task descriptor ----
    $taskObj = $null
    if (-not [string]::IsNullOrWhiteSpace($Task)) { $taskObj = Read-JsonArg $Task }
    elseif ($null -ne $case -and (Has $case 'task')) { $taskObj = $case.task }

    # NOTE (pwsh 7.4.6 array-unroll trap): NEVER pipe an extracted array through ConvertTo-Json (a
    # single-element array unrolls to one object). We assign PSCustomObjects/arrays DIRECTLY into the
    # args hashtable; Invoke-CCWorker serialises the TOP-LEVEL hashtable, which preserves nested arrays.

    $finalMeta = $null
    if ($Op -eq 'normalize') {
        if ($null -eq $taskObj) { throw [PSCustomObject]@{ code='missing_task'; message='op=normalize needs -Task or a CaseFile with .task'; retryable=$false } }
        $r = Invoke-CCWorker @{ op='normalize'; task=$taskObj } $python $WorkerPath 'normalize'
        $finalMeta = $r.meta
    }
    elseif ($Op -eq 'compile') {
        if ($Retriever -eq 'mock') {
            if ($null -eq $case) { throw [PSCustomObject]@{ code='missing_case'; message='compile+mock needs -CaseFile or -InputsJson with {task, retrieval_batches, ...}'; retryable=$false } }
            $argsObj = @{ op = 'compile' }
            foreach ($pr in $case.PSObject.Properties) { $argsObj[$pr.Name] = $pr.Value }
            $r = Invoke-CCWorker $argsObj $python $WorkerPath 'compile'
            $finalMeta = $r.meta
        }
        else {
            if ($null -eq $taskObj) { throw [PSCustomObject]@{ code='missing_task'; message='compile+artifact_search needs -Task'; retryable=$false } }
            if ([string]::IsNullOrWhiteSpace($DbPath)) { throw [PSCustomObject]@{ code='missing_db'; message='compile+artifact_search needs -DbPath (the #36 catalog)'; retryable=$false } }
            if (-not (Test-Path -LiteralPath $DbPath -PathType Leaf)) { throw [PSCustomObject]@{ code='db_not_found'; message="#36 catalog not found: $DbPath"; retryable=$false } }
            if (-not (Test-Path -LiteralPath $ArtifactSearchEntry -PathType Leaf)) { throw [PSCustomObject]@{ code='artifact_search_entry_missing'; message="#36 entrypoint not found: $ArtifactSearchEntry"; retryable=$false } }
            $asEntry = (Resolve-Path -LiteralPath $ArtifactSearchEntry).Path
            # phase 1: normalize -> query_set
            $rn = Invoke-CCWorker @{ op='normalize'; task=$taskObj } $python $WorkerPath 'normalize'
            $querySet = @(Prop $rn.meta.result 'query_set' @())
            Write-Diag "derived $($querySet.Count) queries; running real #36 search"
            # phase 2: run #36 per query -> retrieval_batches
            $batches = New-Object System.Collections.Generic.List[object]
            $corpusVersion = $null; $fusionAlgo = $null; $fusionVersion = $null
            for ($i = 0; $i -lt $querySet.Count; $i++) {
                $q = $querySet[$i]
                # @() coerces a zero-hit query (which emits nothing) to an empty array, NOT $null
                # (StrictMode: `.Count` on $null throws -- the empty-array-unroll trap).
                $hits = @(Invoke-ArtifactSearchQuery $q $DbPath $asEntry)
                if ($hits.Count -gt 0 -and $null -eq $corpusVersion) {
                    $corpusVersion = [string](Prop $hits[0] 'corpus_version' $null)
                    $fusionAlgo = [string](Prop $hits[0] 'fusion_algo' $null)
                    $fusionVersion = [string](Prop $hits[0] 'fusion_version' $null)
                }
                $batches.Add([ordered]@{ query_index = [int](Prop $q 'query_index' $i); query = [string](Prop $q 'query'); hits = $hits })
            }
            $retrievalMeta = [ordered]@{ retriever='artifact.search'; retriever_version='0.2.0'; corpus_version=$corpusVersion; index_snapshot=$corpusVersion; embedding_space_id=$null; fusion_algo=$fusionAlgo; fusion_version=$fusionVersion }
            # phase 3: compile over the gathered real hits (direct assignment; no lossy JSON round-trip)
            $compileArgs = @{ op='compile'; task=$taskObj; query_set=$querySet; retrieval_batches=$batches.ToArray(); retrieval_meta=$retrievalMeta }
            if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $compileArgs['repo_root'] = (Resolve-Path -LiteralPath $RepoRoot).Path }
            $rc = Invoke-CCWorker $compileArgs $python $WorkerPath 'compile'
            $finalMeta = $rc.meta
        }
    }
    elseif ($Op -eq 'expand') {
        $packetObj = $null
        if (-not [string]::IsNullOrWhiteSpace($PacketFile)) { $packetObj = Read-JsonArg $PacketFile }
        elseif ($null -ne $case -and (Has $case 'packet')) { $packetObj = $case.packet }
        $reqObj = $null
        if (-not [string]::IsNullOrWhiteSpace($Request)) { $reqObj = Read-JsonArg $Request }
        elseif ($null -ne $case -and (Has $case 'request')) { $reqObj = $case.request }
        elseif ($null -ne $case -and (Has $case 'expand_request')) { $reqObj = $case.expand_request }
        if ($null -eq $reqObj) { throw [PSCustomObject]@{ code='missing_request'; message='op=expand needs -Request or a CaseFile with .request'; retryable=$false } }
        $argsObj = @{ op='expand'; request=$reqObj }
        if ($null -ne $packetObj) { $argsObj['packet'] = $packetObj }
        if ($null -ne $case -and (Has $case 'expansion_candidates')) { $argsObj['expansion_candidates'] = $case.expansion_candidates }
        if ($null -ne $case -and (Has $case 'source_texts')) { $argsObj['source_texts'] = $case.source_texts }
        if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $argsObj['repo_root'] = (Resolve-Path -LiteralPath $RepoRoot).Path }
        # -Live evidence expansions gather candidates via #36 (raw_source resolves from repo_root directly)
        if ($Retriever -eq 'artifact_search' -and -not (Has $case 'expansion_candidates') -and -not [string]::IsNullOrWhiteSpace($DbPath)) {
            $rtype = [string](Prop $reqObj 'type' 'raw_source')
            if ($rtype -ne 'raw_source' -and (Test-Path -LiteralPath $DbPath -PathType Leaf)) {
                $asEntry = (Resolve-Path -LiteralPath $ArtifactSearchEntry).Path
                $kindMap = @{ failure_record='failure'; prior_episode='episode'; related_symbol='symbol'; tool_contract='skill' }
                $target = Prop $reqObj 'target' $null
                $qtext = [string](Prop $target 'query' (Prop $target 'record_id' ''))
                $qobj = [pscustomobject]@{ query=$qtext; mode='fts'; k=$K; filters=([pscustomobject]@{ record_kind=$kindMap[$rtype] }) }
                if (-not [string]::IsNullOrWhiteSpace($qtext)) { $argsObj['expansion_candidates'] = @(Invoke-ArtifactSearchQuery $qobj $DbPath $asEntry) }
            }
        }
        $r = Invoke-CCWorker $argsObj $python $WorkerPath 'expand'
        $finalMeta = $r.meta
    }

    foreach ($w in @(Prop $finalMeta 'warnings' @())) { $warnings.Add([string]$w) }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($finalMeta | ConvertTo-Json -Depth 60 -Compress)))
    $result = [ordered]@{
        op         = [string](Prop $finalMeta 'op' $Op)
        retriever  = $Retriever
        result     = (Prop $finalMeta 'result' $null)
        worker     = (Prop $finalMeta 'worker' $null)
        runtime_ms = [int](Prop $finalMeta 'runtime_ms' 0)
    }
    # collect artifacts (the worker wrote canonical json files); wrapper owns sha256
    foreach ($a in @(Prop $finalMeta 'artifacts' @())) {
        $ap = [string](Prop $a 'path' ''); $ak = [string](Prop $a 'kind' 'json')
        if (-not [string]::IsNullOrWhiteSpace($ap) -and (Test-Path -LiteralPath $ap -PathType Leaf)) {
            $b = [System.IO.File]::ReadAllBytes($ap)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $ap).Path; kind=$ak; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    Write-Diag "ok op=$Op retriever=$Retriever warnings=$($warnings.Count)"
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

try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[context.compile] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { }

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
$json = $envelope | ConvertTo-Json -Depth 60
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
