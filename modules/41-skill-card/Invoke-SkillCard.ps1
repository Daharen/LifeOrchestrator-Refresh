#requires -Version 7.0
<#
.SYNOPSIS
  skill.card -- deterministic skill-card generator + skill index + Stage-1 eligibility + Stage-2
  lexical-retrieval seam (Life Orchestrator, Module 41, Wave 3).
.DESCRIPTION
  The skill-ACTIVATION substrate (directive Priority 6 / section 9 "Skill card format"): turns each
  module's skill.json (+ sibling README/WORK_ORDER) into a COMPACT, model-facing SKILL CARD, emits each
  card as a MEMORY_CONTRACT s1 `skill` record-envelope artifact (a drop-in for #36 0.2 `ingest_records`),
  and ships a DETERMINISTIC Stage-1 eligibility filter + a DETERMINISTIC Stage-2 lexical retrieval baseline
  over the card index (the semantic-retrieval SEAM; real embeddings fold in at the retrieval wave). It lets
  the coordinator decide WHICH skill applies without loading every command into the 9B. CPU-only,
  stdlib-only Python worker (skill_card.py), no model, no network -> determinism=deterministic,
  confidence=null, empty model_provenance. PRODUCER of `skill` records; the #38 boundary (this is the RICHER
  ACTIVATION card, distinct id namespace `sklcard_` + authority_level `derived`) is recorded in SCHEMA_NOTES.

  Ops:
    cards    (default) walk roots, generate cards + emit s1 records + ingest_records drop-in + validate.
    eligible Stage-1 deterministic eligibility filtering of the card set under a task descriptor.
    retrieve Stage-2 lexical retrieval of candidate skills for a task-intent query (+ the semantic seam).
    validate check an existing records artifact against MEMORY_CONTRACT s1.

  Canonical artifacts (cards.json/jsonl, records.json/jsonl, ingest_records.json, index_manifest.json,
  eligible.json, retrieval.json, summary.md) contain NO absolute paths, timestamps, or wall-clock ids ->
  identical corpus content yields byte-identical artifacts across runs AND machines.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes result.json +
  stderr.txt + worker.log. Exits 0 when a valid envelope is produced (a logical failure is status:error
  inside the envelope, still exit 0).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Root .\fixtures\modules -Namespace fixture
  pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Roots ..\..\modules -Namespace life-orchestrator
  pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op eligible -Root ..\..\modules -TaskJson '{"gpu_available":false}'
  pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op retrieve -Root ..\..\modules -Query "transcribe audio to text"
  pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -InputsJson '{"op":"validate","records_path":"records.jsonl"}'
#>
[CmdletBinding()]
param(
    [string]$Op = 'cards',
    [string[]]$Roots,
    [string]$Root,
    [string]$Namespace,
    [string]$SourceLabel,
    [string]$CardsPath,
    [string]$RecordsPath,
    [string]$Query,
    [int]$K,
    [string]$TaskJson,
    [string[]]$ExcludeDirs,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'skill.card'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[skill.card] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-SystemPython([string]$FallbackLiteral, [string]$StartDir = $PSScriptRoot) {
    # ADDITIVE portability seam (mirrors repo.intel #38 / image.util #15): a machine config
    # (ops\setup\LifeorchConfig.psm1 -> role 'system') MAY relocate the SYSTEM python on a fresh box.
    # Return the CONFIGURED interpreter ONLY when it came from config, DIFFERS, and exists; else the
    # literal UNCHANGED. Fail-closed to the literal on ANY error. Pure lookup, ASCII-only.
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
$taskObj = $null

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
        if ((Has $p 'cards_path')    -and -not $bound.ContainsKey('CardsPath'))    { $CardsPath = [string]$p.cards_path }
        if ((Has $p 'records_path')  -and -not $bound.ContainsKey('RecordsPath'))  { $RecordsPath = [string]$p.records_path }
        if ((Has $p 'query')         -and -not $bound.ContainsKey('Query'))        { $Query = [string]$p.query }
        if ((Has $p 'k')             -and -not $bound.ContainsKey('K'))            { $K = [int]$p.k }
        if ((Has $p 'python_path')   -and -not $bound.ContainsKey('PythonPath'))   { $PythonPath = [string]$p.python_path }
        if ((Has $p 'worker_path')   -and -not $bound.ContainsKey('WorkerPath'))   { $WorkerPath = [string]$p.worker_path }
        if ((Has $p 'roots')         -and -not $bound.ContainsKey('Roots'))        { $Roots = @([string[]]($p.roots)) }
        if ((Has $p 'exclude_dirs')  -and -not $bound.ContainsKey('ExcludeDirs'))  { $ExcludeDirs = @([string[]]($p.exclude_dirs)) }
        if ((Has $p 'task')          -and -not $bound.ContainsKey('TaskJson'))     { $taskObj = $p.task }
    }
    if ([string]::IsNullOrWhiteSpace($Op)) { $Op = 'cards' }
    $Op = $Op.ToLowerInvariant()
    if (@('cards','eligible','retrieve','validate') -notcontains $Op) {
        throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' (cards|eligible|retrieve|validate)"; retryable=$false }
    }

    # ---- -TaskJson (named) overrides InputsJson.task ----
    if (-not [string]::IsNullOrWhiteSpace($TaskJson)) {
        try { $taskObj = $TaskJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_task_json'; message='-TaskJson is not valid JSON'; retryable=$false } }
    }

    # ---- resolve + validate inputs per op ----
    $rootAbs = @()
    if ($Op -in @('cards','eligible','retrieve')) {
        $needRoots = ($Op -eq 'cards') -or [string]::IsNullOrWhiteSpace($CardsPath)
        if ($needRoots) {
            $rootList = New-Object System.Collections.Generic.List[string]
            if ($null -ne $Roots) { foreach ($r in @([string[]]$Roots)) { if (-not [string]::IsNullOrWhiteSpace($r)) { $rootList.Add($r) } } }
            if (-not [string]::IsNullOrWhiteSpace($Root)) { $rootList.Add($Root) }
            if ($rootList.Count -eq 0) {
                throw [PSCustomObject]@{ code='missing_root'; message="$Op needs -Root/-Roots (or -CardsPath for eligible/retrieve)"; retryable=$false }
            }
            foreach ($r in $rootList.ToArray()) {
                if (-not (Test-Path -LiteralPath $r -PathType Container)) {
                    throw [PSCustomObject]@{ code='root_not_found'; message="root not found: $r"; retryable=$false }
                }
                $rootAbs += (Resolve-Path -LiteralPath $r).Path
            }
        } else {
            if (-not (Test-Path -LiteralPath $CardsPath -PathType Leaf)) {
                throw [PSCustomObject]@{ code='cards_not_found'; message="cards_path not found: $CardsPath"; retryable=$false }
            }
            $CardsPath = (Resolve-Path -LiteralPath $CardsPath).Path
        }
        if ($Op -eq 'retrieve' -and [string]::IsNullOrWhiteSpace($Query)) {
            throw [PSCustomObject]@{ code='missing_query'; message='retrieve needs -Query'; retryable=$false }
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
    $taskCompact = $null; if ($null -ne $taskObj) { $taskCompact = ($taskObj | ConvertTo-Json -Compress -Depth 12) }
    $normInputs = [ordered]@{
        op=$Op; roots=$rootAbs; namespace=$Namespace; source_label=$SourceLabel;
        cards_path=$CardsPath; records_path=$(if ($Op -eq 'validate') { $RecordsPath } else { $null });
        query=$Query; k=$(if ($bound.ContainsKey('K') -or ($null -ne $p -and (Has $p 'k'))) { [int]$K } else { $null });
        task=$taskCompact;
        exclude_dirs=$(if ($null -ne $ExcludeDirs) { @([string[]]$ExcludeDirs) } else { $null });
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 10)))

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
        throw [PSCustomObject]@{ code='python_not_found'; message="no python (stdlib json/hashlib/re) found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'skill_card.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="skill_card.py not found at '$WorkerPath' (set -WorkerPath)"; retryable=$false }
    }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- build worker args (args-file hand-off) ----
    $metaPath = Join-Path $invDir 'skill_card_meta.json'
    $wargs = [ordered]@{ op = $Op; output_dir = $invDir; meta_path = $metaPath }
    if ($Op -in @('cards','eligible','retrieve')) {
        if ($rootAbs.Count -gt 0) { $wargs.roots = @($rootAbs) }
        if (-not [string]::IsNullOrWhiteSpace($CardsPath)) { $wargs.cards_path = $CardsPath }
        if (-not [string]::IsNullOrWhiteSpace($Namespace))   { $wargs.namespace = $Namespace }
        if (-not [string]::IsNullOrWhiteSpace($SourceLabel)) { $wargs.source_label = $SourceLabel }
        if ($null -ne $ExcludeDirs) { $wargs.exclude_dirs = @([string[]]$ExcludeDirs) }
        if ($Op -eq 'retrieve') {
            $wargs.query = $Query
            if ($bound.ContainsKey('K') -or ($null -ne $p -and (Has $p 'k'))) { $wargs.k = [int]$K }
        }
        if ($null -ne $taskObj -and ($Op -eq 'eligible' -or $Op -eq 'retrieve')) { $wargs.task = $taskObj }
    } else {
        $wargs.records_path = $RecordsPath
    }
    $argsFile = Join-Path $invDir 'skill_card_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 20), $utf8)

    Write-Diag "python=$python worker=$WorkerPath op=$Op roots=$($rootAbs -join ';') cards_path=$CardsPath"
    $run = Invoke-Worker $python @($WorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='skill_card_failed'; message="skill_card worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'skill_card_failed'); $em = [string](Prop $meta 'error' 'skill_card worker failed')
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

    # ---- assemble the result payload from meta (pass the op payload through; drop internal keys) ----
    $result = [ordered]@{}
    foreach ($pr in $meta.PSObject.Properties) {
        if (@('ok','outputs','warnings') -contains $pr.Name) { continue }
        $result[$pr.Name] = $pr.Value
    }
    Write-Diag "ok op=$Op skills=$(Prop $meta 'skill_count' '-') validation_ok=$(Prop (Prop $meta 'validation' $null) 'ok' '')"
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
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[skill.card] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
$json = $envelope | ConvertTo-Json -Depth 40
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
