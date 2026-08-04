#requires -Version 7.0
<#
.SYNOPSIS
  working.memory -- the Tier-1 per-task WORKING-MEMORY STORE (Life Orchestrator module 42, 0.1.0, contract
  v0.2; MEMORY_CONTRACT A5 U3' / CONTEXT_PACKET_CONTRACT i33 U3', D-0096/D-0090). A thin contract wrapper over
  the deterministic stdlib-only Python worker working_memory.py (SQLite store; the worker owns all schema / CAS
  / one-active-head / conjunctive-access / promotion logic).
.DESCRIPTION
  Ops (-Op, or op in -InputsJson):
    put_state       -TaskId <id> [-NamespaceScope <ns> (required for a task's v1)] -Body <json|path>
                    [-ParentStateVersion <n> (CAS: must equal the current head; null/0 for v1)]
                    -> append an immutable new version as the single active head (stale parent FAILS CLOSED).
    get_active_head -TaskId <id>                 -> the single active head (only if lifecycle=active).
    list_by_task    -TaskId <id>                 -> all versions for the task (exact task_id only).
    fork            -SourceTaskId <id> -NewTaskId <id> -> a new branch whose v1 derives from the source head.
    close|archive   -TaskId <id>                 -> demote the task's head out of get_active_head.
    promote         -TaskId <id>                 -> emit a NEW derived long-term `summary` record (derives_from
                                                    the working version); the working record is NOT re-labeled.
    search          [-RecordKind working]        -> proves ordinary search REJECTS record_kind=working.
  Conjunctive access (A5 U3'): every op takes the caller's namespace authorization -- -AllowedNamespaces
  (the request) AND -PermissionGrants (the control-plane grant); the effective set = intersection, and the
  namespace half uses #37's ONE canonical ns_permitted (imported READ-ONLY). A wrong-namespace access is
  fail-closed + sanitized (a violation COUNT only; no leakage). Inputs may also be passed generically via
  -InputsJson '<json {op, task_id, namespace_scope, body, parent_state_version, source_task_id, new_task_id,
  allowed_namespaces, permission_grants, record_kind, grant_snapshot_ref, created_from_packet_id,
  writer_authority, store_path, ns_policy_path, python_path, worker_path}>'. The store PERSISTS across
  invocations (that is the point) at -StorePath (default runtime/store/working_memory.db). CPU-only, no model,
  no network -> parallel_safe:true (per-store; one store is single-writer under SQLite's transaction).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -Op put_state -TaskId T1 -NamespaceScope projA -Body '{"step":1}' -AllowedNamespaces projA -PermissionGrants projA
  pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -InputsJson '{"op":"get_active_head","task_id":"T1","allowed_namespaces":["projA"],"permission_grants":["projA"]}'
#>
[CmdletBinding()]
param(
    [string]$Op,
    [string]$InputsJson,
    [string]$TaskId,
    [string]$NamespaceScope,
    [string]$Body,
    [nullable[int]]$ParentStateVersion,
    [string]$SourceTaskId,
    [string]$NewTaskId,
    [string[]]$AllowedNamespaces,
    [string[]]$PermissionGrants,
    [string]$RecordKind,
    [string]$GrantSnapshotRef,
    [string]$CreatedFromPacketId,
    [string]$WriterAuthority,
    [string]$StorePath,
    [string]$NsPolicyPath,
    [string]$PythonPath,
    [string]$WorkerPath,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'working.memory'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[working.memory] $m") }
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
function Parse-BodyValue([string]$v) {
    # a body/value may be a path to a .json file OR an inline JSON string
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    if (Test-Path -LiteralPath $v -PathType Leaf) { return ((Get-Content -LiteralPath $v -Raw) | ConvertFrom-Json) }
    return ($v | ConvertFrom-Json)
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
    $opName = if (-not [string]::IsNullOrWhiteSpace($Op)) { $Op } elseif ($null -ne $p -and (Has $p 'op')) { [string]$p.op } else { $null }
    $validOps = @('put_state', 'get_active_head', 'list_by_task', 'fork', 'close', 'archive', 'promote', 'search')
    if ([string]::IsNullOrWhiteSpace($opName) -or ($validOps -notcontains $opName)) {
        throw [PSCustomObject]@{ code = 'bad_op'; message = "op must be one of: $($validOps -join ', ')"; retryable = $false }
    }

    # ---- carry-through generic keys ----
    if ($null -ne $p) {
        if (-not $bound.ContainsKey('StorePath') -and (Has $p 'store_path')) { $StorePath = [string]$p.store_path }
        if (-not $bound.ContainsKey('NsPolicyPath') -and (Has $p 'ns_policy_path')) { $NsPolicyPath = [string]$p.ns_policy_path }
        if (-not $bound.ContainsKey('PythonPath') -and (Has $p 'python_path')) { $PythonPath = [string]$p.python_path }
        if (-not $bound.ContainsKey('WorkerPath') -and (Has $p 'worker_path')) { $WorkerPath = [string]$p.worker_path }
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
    if ([string]::IsNullOrWhiteSpace($python)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = 'no python 3 found. Set -PythonPath.'; retryable = $false } }

    # ---- resolve worker ----
    if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $PSScriptRoot 'working_memory.py' }
    if (-not (Test-Path -LiteralPath $WorkerPath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'worker_not_found'; message = "working_memory.py not found at '$WorkerPath'"; retryable = $false } }
    $WorkerPath = (Resolve-Path -LiteralPath $WorkerPath).Path

    # ---- resolve the PERSISTENT store path (survives across invocations) ----
    if ([string]::IsNullOrWhiteSpace($StorePath)) { $StorePath = Join-Path $PSScriptRoot 'runtime/store/working_memory.db' }
    $storeDir = Split-Path -Parent $StorePath
    if (-not [string]::IsNullOrWhiteSpace($storeDir) -and -not (Test-Path -LiteralPath $storeDir)) { New-Item -ItemType Directory -Path $storeDir -Force | Out-Null }

    # ---- build the worker request (named params override InputsJson keys) ----
    $req = [ordered]@{ op = $opName; out_dir = $invDir; store_path = $StorePath }
    if (-not [string]::IsNullOrWhiteSpace($NsPolicyPath)) { $req.ns_policy_path = $NsPolicyPath }

    function Pick([string]$named, [bool]$isBound, [string]$jsonKey) {
        if ($isBound -and -not [string]::IsNullOrWhiteSpace($named)) { return $named }
        if ($null -ne $p -and (Has $p $jsonKey)) { return $p.$jsonKey }
        return $null
    }
    $v = Pick $TaskId ($bound.ContainsKey('TaskId')) 'task_id';                 if ($null -ne $v) { $req.task_id = [string]$v }
    $v = Pick $NamespaceScope ($bound.ContainsKey('NamespaceScope')) 'namespace_scope'; if ($null -ne $v) { $req.namespace_scope = [string]$v }
    $v = Pick $SourceTaskId ($bound.ContainsKey('SourceTaskId')) 'source_task_id';      if ($null -ne $v) { $req.source_task_id = [string]$v }
    $v = Pick $NewTaskId ($bound.ContainsKey('NewTaskId')) 'new_task_id';                if ($null -ne $v) { $req.new_task_id = [string]$v }
    $v = Pick $RecordKind ($bound.ContainsKey('RecordKind')) 'record_kind';              if ($null -ne $v) { $req.record_kind = [string]$v }
    $v = Pick $GrantSnapshotRef ($bound.ContainsKey('GrantSnapshotRef')) 'grant_snapshot_ref'; if ($null -ne $v) { $req.grant_snapshot_ref = [string]$v }
    $v = Pick $CreatedFromPacketId ($bound.ContainsKey('CreatedFromPacketId')) 'created_from_packet_id'; if ($null -ne $v) { $req.created_from_packet_id = [string]$v }
    $v = Pick $WriterAuthority ($bound.ContainsKey('WriterAuthority')) 'writer_authority'; if ($null -ne $v) { $req.writer_authority = [string]$v }

    if ($bound.ContainsKey('ParentStateVersion') -and $null -ne $ParentStateVersion) { $req.parent_state_version = [int]$ParentStateVersion }
    elseif ($null -ne $p -and (Has $p 'parent_state_version') -and $null -ne $p.parent_state_version) { $req.parent_state_version = [int]$p.parent_state_version }

    if ($bound.ContainsKey('AllowedNamespaces')) { $req.allowed_namespaces = @($AllowedNamespaces) }
    elseif ($null -ne $p -and (Has $p 'allowed_namespaces')) { $req.allowed_namespaces = @($p.allowed_namespaces) }
    if ($bound.ContainsKey('PermissionGrants')) { $req.permission_grants = @($PermissionGrants) }
    elseif ($null -ne $p -and (Has $p 'permission_grants')) { $req.permission_grants = @($p.permission_grants) }
    if ($null -ne $p -and (Has $p 'effective_allowed_namespaces')) { $req.effective_allowed_namespaces = @($p.effective_allowed_namespaces) }

    # body: named -Body (path|inline) or InputsJson.body (object)
    if ($bound.ContainsKey('Body') -and -not [string]::IsNullOrWhiteSpace($Body)) { $req.body = (Parse-BodyValue $Body) }
    elseif ($null -ne $p -and (Has $p 'body')) { $req.body = $p.body }

    $reqPath = Join-Path $invDir 'request.json'
    [System.IO.File]::WriteAllText($reqPath, ($req | ConvertTo-Json -Depth 60), $utf8)

    # ---- invoke the worker ----
    Write-Diag "op=$opName python=$python store=$StorePath out=$invDir"
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
        $tail = ($tail -replace '\s+', ' ').Trim(); if ($tail.Length -gt 400) { $tail = $tail.Substring(0, 400) }
        throw [PSCustomObject]@{ code = 'worker_no_summary'; message = "worker produced no worker-summary.json (exit=$wexit). stderr tail: $tail"; retryable = $false }
    }
    $summary = (Get-Content -LiteralPath $summaryPath -Raw) | ConvertFrom-Json

    $summaryOk = $false; if (Has $summary 'ok') { $summaryOk = [bool]$summary.ok }
    if (-not $summaryOk) {
        $we = if (Has $summary 'error') { $summary.error } else { $null }
        $status = 'error'
        $errorObj = [ordered]@{
            code      = [string]$(if ($null -ne $we -and (Has $we 'code')) { $we.code } else { 'working_memory_failed' })
            message   = [string]$(if ($null -ne $we -and (Has $we 'message')) { $we.message } else { 'worker reported failure' })
            retryable = [bool]$(if ($null -ne $we -and (Has $we 'retryable')) { $we.retryable } else { $false })
        }
    } else {
        $result = [ordered]@{ op = $opName }
        foreach ($f in @('task_id', 'namespace_scope', 'working_state_id', 'record_version_id', 'state_version',
                'parent_state_version', 'active_head_version', 'content_hash', 'found', 'reason', 'count',
                'versions', 'source_task_id', 'new_task_id', 'forked_from', 'changed', 'lifecycle_state',
                'promoted_record_id', 'promoted_record_version_id', 'derives_from', 'promoted_record_kind',
                'working_record_unchanged', 'working_excluded_from_search', 'requested_record_kind', 'results',
                'ns_policy_id', 'ns_policy_version', 'namespace_violation_count', 'namespace_closure_violated',
                'records_digest', 'store_schema_version', 'artifacts_written')) {
            if (Has $summary $f) { $result[$f] = $summary.$f }
        }
        $inputsDigest = [string]$(if (Has $summary 'records_digest') { $summary.records_digest } else { $null })
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

# ---- artifacts ----
try {
    $artList = New-Object System.Collections.Generic.List[object]
    foreach ($n in @('state.json', 'records.json', 'promoted.json', 'source_working_state.json', 'worker-summary.json')) {
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
