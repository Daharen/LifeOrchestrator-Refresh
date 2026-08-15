#requires -Version 7.0
<#
.SYNOPSIS
  decision.intel -- deterministic decision-record producer (Life Orchestrator, Module 45, i56 PB-6 build).
.DESCRIPTION
  Parses the append-only core-docs/DECISION_LOG.md (+ DECISION_LOG_INDEX.md routing rows) and emits TYPED
  record_kind="decision" record-envelope artifacts conforming to core-docs/MEMORY_CONTRACT.md section 1,
  per the FROZEN contract core-docs/research/2026-08-14-pb6-decision-record-schema.md, so the catalog
  (#36 artifact.search) can ingest them as FIRST-CLASS records. Deterministic marker rules (documented in
  SCHEMA_NOTES.md) derive binding_scope / enforced_by / authority / type / affected_modules / planes /
  iteration / date, and full-supersession + partial-supersession + derives_from edges from BOTH the
  DECISION_LOG_INDEX.md bracket annotations (`[superseded by D-####]` / `[folded by D-####]` /
  `[... retired by D-####]`) and explicit "supersedes/replaces D-####" declarations in DECISION_LOG.md
  entry bodies. `ingested_through` (the DECISION_LOG.md HEAD sha for this run) is a REQUIRED CALLER-SUPPLIED
  input -- this worker NEVER shells out to git (mirrors #38 repo.intel's no-git rule; D-0072).

  Ops: index (default) parses both files and emits records + manifest + ingest_records drop-in + coverage;
  validate re-checks an existing records artifact. Canonical artifacts (records.jsonl, records.json,
  ingest_records.json, index_manifest.json, coverage.json) contain NO absolute paths, timestamps, or
  wall-clock ids -> identical DECISION_LOG(.md/_INDEX.md) byte content + the same ingested_through input
  yields byte-identical artifacts across runs AND machines (the double-run byte-identity gate).

  This module EMITS + VALIDATES artifacts only; it does NOT ingest into the real #36 catalog (the
  orchestrator runs `ingest_records` at fold, mirroring the #38->#36 D-0077 pattern).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes the artifacts
  above + decision_intel_meta.json + worker.log + result.json + stderr.txt. Exits 0 when a valid envelope
  is produced (a logical failure is status:error inside the envelope, still exit 0).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 -DecisionLogPath ..\..\core-docs\DECISION_LOG.md `
    -DecisionLogIndexPath ..\..\core-docs\DECISION_LOG_INDEX.md -IngestedThrough 7309520abc...
  pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 -InputsJson '{"op":"validate","records_path":"records.jsonl"}'
#>
[CmdletBinding()]
param(
    [string]$Op = 'index',
    [string]$DecisionLogPath,
    [string]$DecisionLogIndexPath,
    [string]$Namespace,
    [string]$IngestedThrough,
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

$SKILL_ID = 'decision.intel'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[decision.intel] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-SystemPython([string]$FallbackLiteral, [string]$StartDir = $PSScriptRoot) {
    # ADDITIVE portability seam (mirrors #38 repo.intel / #15 / #16): a machine config
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
        & $exe -c 'import json,hashlib,re,os' 2>$null | Out-Null
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
        if ((Has $p 'op')                       -and -not $bound.ContainsKey('Op'))                    { $Op = [string]$p.op }
        if ((Has $p 'decision_log_path')         -and -not $bound.ContainsKey('DecisionLogPath'))       { $DecisionLogPath = [string]$p.decision_log_path }
        if ((Has $p 'decision_log_index_path')   -and -not $bound.ContainsKey('DecisionLogIndexPath'))  { $DecisionLogIndexPath = [string]$p.decision_log_index_path }
        if ((Has $p 'namespace')                 -and -not $bound.ContainsKey('Namespace'))             { $Namespace = [string]$p.namespace }
        if ((Has $p 'ingested_through')          -and -not $bound.ContainsKey('IngestedThrough'))       { $IngestedThrough = [string]$p.ingested_through }
        if ((Has $p 'records_path')              -and -not $bound.ContainsKey('RecordsPath'))           { $RecordsPath = [string]$p.records_path }
        if ((Has $p 'python_path')               -and -not $bound.ContainsKey('PythonPath'))            { $PythonPath = [string]$p.python_path }
        if ((Has $p 'worker_path')               -and -not $bound.ContainsKey('WorkerPath'))             { $WorkerPath = [string]$p.worker_path }
    }

    if ([string]::IsNullOrWhiteSpace($Op)) { $Op = 'index' }
    $Op = $Op.ToLowerInvariant()
    if (@('index','validate') -notcontains $Op) {
        throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' (index|validate)"; retryable=$false }
    }

    # ---- resolve + validate inputs ----
    if ($Op -eq 'index') {
        if ([string]::IsNullOrWhiteSpace($DecisionLogPath)) {
            throw [PSCustomObject]@{ code='missing_decision_log_path'; message='index needs -DecisionLogPath (or InputsJson.decision_log_path)'; retryable=$false }
        }
        if (-not (Test-Path -LiteralPath $DecisionLogPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='decision_log_not_found'; message="decision log not found: $DecisionLogPath"; retryable=$false }
        }
        $DecisionLogPath = (Resolve-Path -LiteralPath $DecisionLogPath).Path
        if ([string]::IsNullOrWhiteSpace($DecisionLogIndexPath)) {
            throw [PSCustomObject]@{ code='missing_decision_log_index_path'; message='index needs -DecisionLogIndexPath (or InputsJson.decision_log_index_path)'; retryable=$false }
        }
        if (-not (Test-Path -LiteralPath $DecisionLogIndexPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='decision_log_index_not_found'; message="decision log index not found: $DecisionLogIndexPath"; retryable=$false }
        }
        $DecisionLogIndexPath = (Resolve-Path -LiteralPath $DecisionLogIndexPath).Path
        if ([string]::IsNullOrWhiteSpace($IngestedThrough) -or $IngestedThrough -notmatch '^[0-9a-f]{7,40}$') {
            throw [PSCustomObject]@{ code='missing_ingested_through'; message='index needs -IngestedThrough (the DECISION_LOG.md HEAD sha for this run) as a 7-40 char lowercase hex string -- the CALLER supplies it; this wrapper never shells out to git (D-0072).'; retryable=$false }
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
        op=$Op; decision_log_path=$DecisionLogPath; decision_log_index_path=$DecisionLogIndexPath;
        namespace=$Namespace; ingested_through=$(if ($Op -eq 'index') { $IngestedThrough } else { $null });
        records_path=$(if ($Op -eq 'validate') { $RecordsPath } else { $null });
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
        throw [PSCustomObject]@{ code='python_not_found'; message="no python (stdlib json/hashlib/re/os) found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'decision_intel.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="decision_intel.py not found at '$WorkerPath' (set -WorkerPath)"; retryable=$false }
    }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- build worker args (args-file hand-off) ----
    $metaPath = Join-Path $invDir 'decision_intel_meta.json'
    $wargs = [ordered]@{ op = $Op; output_dir = $invDir; meta_path = $metaPath }
    if ($Op -eq 'index') {
        $wargs.decision_log_path = $DecisionLogPath
        $wargs.decision_log_index_path = $DecisionLogIndexPath
        $wargs.ingested_through = $IngestedThrough
        if (-not [string]::IsNullOrWhiteSpace($Namespace)) { $wargs.namespace = $Namespace }
    } else {
        $wargs.records_path = $RecordsPath
    }
    $argsFile = Join-Path $invDir 'decision_intel_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 8), $utf8)

    Write-Diag "python=$python worker=$WorkerPath op=$Op"
    $run = Invoke-Worker $python @($WorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='decision_intel_failed'; message="decision_intel worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'decision_intel_failed'); $em = [string](Prop $meta 'error' 'decision_intel worker failed')
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

    # ---- assemble the result payload from meta ----
    $result = [ordered]@{
        op                              = [string](Prop $meta 'op' $Op)
        namespace                       = (Prop $meta 'namespace' $Namespace)
        total_records                   = [int](Prop $meta 'total_records' 0)
        record_kind                     = (Prop $meta 'record_kind' 'decision')
        counts_by_status                = (Prop $meta 'counts_by_status' $null)
        counts_by_binding_scope         = (Prop $meta 'counts_by_binding_scope' $null)
        records_digest                  = (Prop $meta 'records_digest' $null)
        validation                      = (Prop $meta 'validation' $null)
        edge_summary                    = (Prop $meta 'edge_summary' $null)
        coverage                        = (Prop $meta 'coverage' $null)
        ambiguous_count                 = [int](Prop $meta 'ambiguous_count' 0)
        # NOTE: array-typed fields MUST be wrapped in @(...) at the call site -- `Prop` does `return $o.$n`,
        # and PowerShell UNROLLS an array's elements onto the pipeline when a function returns it; an EMPTY
        # array therefore streams zero objects, which a plain `$x = Prop ...` scalar capture collapses to
        # $null (never a proper empty array) -- silently turning a correct `[]` from the python worker's
        # meta.json into a `null` in the emitted envelope. `@(Prop ...)` re-collects the (possibly zero-item)
        # pipeline output into a real array, preserving `[]` on ConvertTo-Json. Caught live: the -Live
        # shipping run hit exactly this on `unresolved_supersession_targets` when it was genuinely empty
        # (see SCHEMA_NOTES.md s14a) -- `ambiguous` is fixed proactively here since it is empty on any
        # corpus with zero ambiguous decisions, the same latent bug, just not yet exercised on this corpus.
        ambiguous                       = @(Prop $meta 'ambiguous' @())
        unresolved_supersession_targets = @(Prop $meta 'unresolved_supersession_targets' @())
        ingest_run_id                   = (Prop $meta 'ingest_run_id' $null)
        checked                         = (Prop $meta 'checked' $null)
        runtime_ms                      = [int](Prop $meta 'runtime_ms' 0)
        worker                          = (Prop $meta 'worker' $null)
    }
    Write-Diag "ok op=$Op records=$($result.total_records) coverage_ok=$(Prop $result.coverage 'ok' '') validation_ok=$(Prop $result.validation 'ok' '') ambiguous=$($result.ambiguous_count)"
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
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[decision.intel] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
