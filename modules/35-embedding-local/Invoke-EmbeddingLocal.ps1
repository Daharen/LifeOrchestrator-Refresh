#requires -Version 7.0
<#
.SYNOPSIS
  embedding.local (Life Orchestrator, Module 35) -- a versioned, testable LOCAL text-embedding capability.
  Turns the pre-provisioned Qwen3-Embedding-0.6B (safetensors dir, arch Qwen3Model, hidden_size 1024) into a
  conforming `embed` skill: batch + single text in, L2-normalized vectors + full model/version/sha256/engine
  provenance out, EXACT input-order preservation, clean empty/oversize handling. Defines the EMBEDDING-PROVIDER
  INTERFACE the Wave 1 memory substrate (artifact.search, Module 36) consumes (D-0077 shared contract).

.DESCRIPTION
  op `embed`. Serves the model through a TRANSIENT Python worker (embed_worker.py) under the CUDA speech venv
  (transformers + torch; last-token pooling + L2 normalize). NOT a persistent server -> no detached warm
  resident, no port, no reap-across-calls: the worker loads, embeds, and EXITS (the detect.objects/image.util
  pattern), so the wedge class does not apply; we still assert 0 UNMANAGED orphans. GPU work runs under the
  res.lease `gpu` mutex (one heavyweight resident, governing sec 16.1), self-managed here (-GpuLease). A -Mock
  seam + a -Device cpu path make the schema/shape/normalization/input-order/empty-oversize logic testable
  OFF-MACHINE. Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes result.json
  + the raw worker meta to the artifact dir. Exits 0 whenever a valid envelope is produced.
#>
[CmdletBinding()]
param(
    [string]$Text,
    [string[]]$Texts,
    [bool]$Normalize = $true,
    [string]$Instruction,
    [int]$MaxTokens = 32768,
    [string]$Dtype = 'fp32',
    [string]$Device = 'cuda',
    [switch]$Mock,
    [string]$ModelId = 'embedding.qwen3-0p6b',
    [string]$ModelPath,
    [string]$ModelSha256,
    [string]$Registry,
    [string]$PythonExe,
    [string]$WorkerPath,
    [string]$GpuLease = 'auto',
    [string]$GpuLeaseHolder,
    [int]$GpuTtlSeconds = 1800,
    [int]$GpuWaitSeconds = 900,
    [string]$ResLeasePath,
    [string]$PwshPath,
    [string]$ArtifactRoot,
    [string]$InvocationId,
    [int]$MockDim = 1024,
    [int]$MockSeed = 0,
    [string]$InputsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- constants ----------
$SKILL_ID = 'embedding.local'
$SKILL_VERSION = '0.1.0'
$CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------- helpers ----------
function Has($o, [string]$n) {
    if ($null -eq $o) { return $false }
    if ($o -is [System.Collections.IDictionary]) { return $o.Contains($n) }
    return $null -ne ($o.PSObject.Properties[$n])
}
function Prop($o, [string]$n, $d = $null) {
    if (Has $o $n) {
        if ($o -is [System.Collections.IDictionary]) { return $o[$n] }
        return $o.PSObject.Properties[$n].Value
    }
    return $d
}
function Write-Diag([string]$m) { [Console]::Error.WriteLine($m) }
function Get-Sha256HexFile([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Sha256HexString([string]$s) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($utf8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}
function Run-Capture([string]$exe, [string[]]$argv) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $exe @argv 2> $tmpErr.FullName; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    $err = ''
    try { $err = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    return @{ exit = $code; out = ($out | Out-String); err = $err }
}

# ---------- state (all envelope-referenced vars initialized up front) ----------
$scriptDir = $PSScriptRoot
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$status = 'ok'
$errorObj = $null
$result = $null
$artifacts = @()
$modelProvenance = @()
$inputsDigest = 'sha256:'
$leaseState = [ordered]@{ requested = $false; acquired = $false; owned = $false; already_held = $false; lease_id = $null; holder = $null; held_by = $null }
$isMock = $false

if ([string]::IsNullOrWhiteSpace($WorkerPath)) { $WorkerPath = Join-Path $scriptDir 'embed_worker.py' }
if ([string]::IsNullOrWhiteSpace($Registry)) { $Registry = Join-Path (Split-Path $scriptDir -Parent) '07-model-gateway/models.json' }
if ([string]::IsNullOrWhiteSpace($ResLeasePath)) { $ResLeasePath = Join-Path (Split-Path $scriptDir -Parent) '29-resource-lease/Invoke-ResLease.ps1' }
if ([string]::IsNullOrWhiteSpace($PwshPath)) {
    # (Get-Process).Path reports 'dotnet.exe' for the dotnet-tool pwsh (gotcha) -> resolve the real shim.
    $exeName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $pcands = [System.Collections.Generic.List[string]]::new()
    $gc = Get-Command pwsh -ErrorAction SilentlyContinue; if ($gc -and $gc.Source) { $pcands.Add([string]$gc.Source) }
    if ($IsWindows) { $pcands.Add('C:\Users\just_\.dotnet\tools\pwsh.exe') }
    if ($PSHOME) { $pcands.Add((Join-Path $PSHOME $exeName)) }
    foreach ($pc in $pcands.ToArray()) { if (-not [string]::IsNullOrWhiteSpace($pc) -and (Test-Path -LiteralPath $pc -ErrorAction SilentlyContinue)) { $PwshPath = $pc; break } }
    if ([string]::IsNullOrWhiteSpace($PwshPath)) { $PwshPath = 'pwsh' }
}
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString('N') }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = Join-Path $scriptDir 'runtime/artifacts' }
$invDir = Join-Path $ArtifactRoot $InvocationId
[void](New-Item -ItemType Directory -Path $invDir -Force)

# ---------- merge -InputsJson (named params win when explicitly bound) ----------
$inObj = $null
if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
    try { $inObj = $InputsJson | ConvertFrom-Json } catch { throw "invalid -InputsJson: $($_.Exception.Message)" }
}
$bound = $PSBoundParameters
function FromJson([string]$key, $default) { if ($null -ne $inObj -and (Has $inObj $key)) { return (Prop $inObj $key) } return $default }
function Merge([string]$paramName, [string]$jsonKey, $current, $default) {
    if ($bound.ContainsKey($paramName)) { return $current }
    return (FromJson $jsonKey $default)
}

try {
    # ---------- resolve inputs (texts / text) ----------
    $inputTexts = @()
    if ($bound.ContainsKey('Texts')) { $inputTexts = @($Texts) }
    elseif ($bound.ContainsKey('Text')) { $inputTexts = @($Text) }
    elseif ($null -ne $inObj -and (Has $inObj 'texts')) { $inputTexts = @((Prop $inObj 'texts')) }
    elseif ($null -ne $inObj -and (Has $inObj 'text')) { $inputTexts = @([string](Prop $inObj 'text')) }
    else { throw [PSCustomObject]@{ code = 'no_input'; message = "supply -Text, -Texts, or -InputsJson with 'text'/'texts'"; retryable = $false } }
    $inputTexts = @($inputTexts | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } })

    $Normalize = [bool](Merge 'Normalize' 'normalize' $Normalize $Normalize)
    $Instruction = [string](Merge 'Instruction' 'instruction' $Instruction $Instruction)
    $MaxTokens = [int](Merge 'MaxTokens' 'max_tokens' $MaxTokens $MaxTokens)
    $Dtype = [string](Merge 'Dtype' 'dtype' $Dtype $Dtype)
    $Device = [string](Merge 'Device' 'device' $Device $Device)
    $ModelId = [string](Merge 'ModelId' 'model_id' $ModelId $ModelId)
    $ModelPath = [string](Merge 'ModelPath' 'model_path' $ModelPath $ModelPath)
    $ModelSha256 = [string](Merge 'ModelSha256' 'model_sha256' $ModelSha256 $ModelSha256)
    $MockDim = [int](Merge 'MockDim' 'mock_dim' $MockDim $MockDim)
    $MockSeed = [int](Merge 'MockSeed' 'mock_seed' $MockSeed $MockSeed)
    $isMock = [bool]($Mock -or [bool](FromJson 'mock' $false))

    $inputsDigest = 'sha256:' + (Get-Sha256HexString (($inputTexts -join "`u{1}") + "|norm=$Normalize|instr=$Instruction|max=$MaxTokens|dtype=$Dtype|dev=$Device|mock=$isMock"))

    # ---------- resolve model (skip in mock) ----------
    $modelPathResolved = $null
    $modelSha = $null
    if (-not $isMock) {
        if (-not [string]::IsNullOrWhiteSpace($ModelPath)) { $modelPathResolved = $ModelPath }
        else {
            if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) { throw [PSCustomObject]@{ code = 'registry_not_found'; message = "models.json not found at '$Registry'"; retryable = $false } }
            $reg = Get-Content -LiteralPath $Registry -Raw | ConvertFrom-Json
            $entry = $null
            foreach ($mm in @(Prop $reg 'models' @())) { if ([string](Prop $mm 'model_id') -eq $ModelId) { $entry = $mm; break } }
            if ($null -eq $entry) { throw [PSCustomObject]@{ code = 'model_not_registered'; message = "model_id '$ModelId' not in $Registry"; retryable = $false } }
            $modelPathResolved = [string](Prop $entry 'path')
            if ([string]::IsNullOrWhiteSpace($ModelSha256)) { $ModelSha256 = [string](Prop $entry 'model_sha256' $null) }
        }
        if ([string]::IsNullOrWhiteSpace($modelPathResolved) -or -not (Test-Path -LiteralPath $modelPathResolved -PathType Container)) {
            throw [PSCustomObject]@{ code = 'model_dir_not_found'; message = "embedding model dir not found: '$modelPathResolved'"; retryable = $false }
        }
        $weights = Join-Path $modelPathResolved 'model.safetensors'
        if (Test-Path -LiteralPath $weights -PathType Leaf) {
            $modelSha = Get-Sha256HexFile $weights
            if (-not [string]::IsNullOrWhiteSpace($ModelSha256) -and ($ModelSha256.ToLowerInvariant() -ne $modelSha)) {
                throw [PSCustomObject]@{ code = 'model_sha_mismatch'; message = "model.safetensors sha256 mismatch: expected $ModelSha256 got $modelSha"; retryable = $false }
            }
        } else { $warnings.Add("model.safetensors not found under '$modelPathResolved'; model_sha256 unset") }
    }

    # ---------- resolve python ----------
    $python = $null
    if (-not [string]::IsNullOrWhiteSpace($PythonExe)) { $python = $PythonExe }
    elseif ($null -ne $inObj -and (Has $inObj 'python_exe')) { $python = [string](Prop $inObj 'python_exe') }
    else {
        $cands = [System.Collections.Generic.List[string]]::new()
        if (-not $isMock) { $cands.Add('F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe') }
        foreach ($n in @('python3', 'python')) { $cands.Add($n) }
        foreach ($c in $cands.ToArray()) {
            try { $rr = Run-Capture $c @('--version'); if ($rr.exit -eq 0) { $python = $c; break } } catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($python)) { throw [PSCustomObject]@{ code = 'python_not_found'; message = 'no python interpreter found; set -PythonExe'; retryable = $false } }

    # ---------- GPU lease (res.lease #29): skill self-manages the real gpu mutex ----------
    $glMode = if ([string]::IsNullOrWhiteSpace($GpuLease)) { 'auto' } else { $GpuLease.ToLowerInvariant() }
    if (@('off', 'auto', 'require') -notcontains $glMode) { $warnings.Add("unknown -GpuLease '$GpuLease'; using 'auto'"); $glMode = 'auto' }
    $wantLease = (-not $isMock) -and ($Device.ToLowerInvariant() -eq 'cuda') -and ($glMode -ne 'off')
    $glHolder = if (-not [string]::IsNullOrWhiteSpace($GpuLeaseHolder)) { $GpuLeaseHolder }
    elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE }
    else { "embedding.local:$PID" }
    $leaseState.requested = $wantLease
    $leaseState.holder = $glHolder

    if ($wantLease) {
        if (-not (Test-Path -LiteralPath $ResLeasePath -PathType Leaf)) { throw [PSCustomObject]@{ code = 'reslease_not_found'; message = "res.lease not found at '$ResLeasePath'"; retryable = $false } }
        $rl = Run-Capture $PwshPath (@('-NoProfile', '-NonInteractive', '-File', $ResLeasePath, '-Action', 'acquire', '-Resource', 'gpu', '-Holder', $glHolder, '-TtlSeconds', "$GpuTtlSeconds", '-WaitSeconds', "$GpuWaitSeconds"))
        $env0 = $null; try { $env0 = ($rl.out | ConvertFrom-Json) } catch { }
        $res0 = if ($null -ne $env0) { Prop $env0 'result' } else { $null }
        $acquired = [bool](Prop $res0 'acquired' $false)
        $already = [bool](Prop $res0 'already_held' $false)
        if ($acquired -or $already) {
            $leaseState.acquired = $true
            $leaseState.owned = ($acquired -and -not $already)
            $leaseState.already_held = $already
            $leaseState.lease_id = [string](Prop $res0 'lease_id' $null)
            Write-Diag "gpu lease: acquired=$acquired already_held=$already lease_id=$($leaseState.lease_id)"
        } else {
            $leaseState.held_by = [string](Prop $res0 'held_by' 'unknown')
            throw [PSCustomObject]@{ code = 'gpu_lease_unavailable'; message = "gpu lease held by '$($leaseState.held_by)' after ${GpuWaitSeconds}s wait"; retryable = $true }
        }
    }

    # ---------- run the worker ----------
    $metaPath = Join-Path $invDir 'worker_out.json'
    $workerArgs = [ordered]@{
        texts       = [string[]]$inputTexts
        normalize   = $Normalize
        instruction = if ([string]::IsNullOrWhiteSpace($Instruction)) { $null } else { $Instruction }
        max_tokens  = $MaxTokens
        dtype       = $Dtype
        device      = $Device
        model_path  = $modelPathResolved
        mock        = $isMock
        dim         = $MockDim
        seed        = $MockSeed
        meta_path   = $metaPath
    }
    $argsFile = Join-Path $invDir 'worker_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($workerArgs | ConvertTo-Json -Depth 6), $utf8)

    Write-Diag "python=$python worker=$WorkerPath mock=$isMock device=$Device dtype=$Dtype count=$($inputTexts.Count)"
    $run = Run-Capture $python @($WorkerPath, $argsFile)
    [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("--stdout--`n" + $run.out + "`n--stderr--`n" + $run.err), $utf8)
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code = 'worker_no_meta'; message = "worker produced no meta (exit=$($run.exit)); see worker.log"; retryable = $true }
    }
    $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $we = Prop $meta 'error' $null
        throw [PSCustomObject]@{ code = [string](Prop $we 'code' 'worker_failed'); message = [string](Prop $we 'message' 'worker reported failure'); retryable = $true }
    }

    # ---------- build the embed result payload (the D-0077 embedding-provider interface) ----------
    $prov = Prop $meta 'provenance' $null
    if ($isMock) { $engineBuild = "mock/numpy-$([string](Prop $prov 'numpy' '?'))" }
    else { $engineBuild = "transformers-$([string](Prop $prov 'transformers' '?'))/torch-$([string](Prop $prov 'torch' '?'))/cuda-$([string](Prop $prov 'cuda' '?')) (qwen3 last_token L2)" }

    $vectors = @(Prop $meta 'vectors' @())
    $perInput = @(Prop $meta 'per_input' @())
    $dim = [int](Prop $meta 'dim' 0)
    $skipCount = @($perInput | Where-Object { [string](Prop $_ 'status') -ne 'ok' }).Count
    if ($skipCount -gt 0) { $status = 'partial'; $warnings.Add("$skipCount of $($perInput.Count) input(s) skipped (empty/oversize)") }

    $result = [ordered]@{
        op              = 'embed'
        model_id        = $ModelId
        model_version   = if ($isMock) { 'mock' } else { '0.6B' }
        model_sha256    = $modelSha
        engine_build    = $engineBuild
        pooling         = [string](Prop $meta 'pooling' 'last_token')
        dim             = $dim
        normalized      = [bool](Prop $meta 'normalized' $Normalize)
        count           = [int](Prop $meta 'count' $inputTexts.Count)
        vectors         = $vectors
        per_input       = $perInput
        instruction     = if ([string]::IsNullOrWhiteSpace($Instruction)) { $null } else { $Instruction }
        max_tokens      = $MaxTokens
        device          = [string](Prop $meta 'device' $Device)
        dtype           = [string](Prop $meta 'dtype' $Dtype)
        timings         = (Prop $meta 'timings' $null)
        peak_vram_bytes = (Prop $meta 'peak_vram_bytes' $null)
        peak_ram_bytes  = (Prop $meta 'peak_ram_bytes' $null)
        lease           = $leaseState
    }
    if (-not $isMock) {
        $modelProvenance = @(
            [ordered]@{ model_id = $ModelId; version = '0.6B'; sha256 = $modelSha; engine_build = $engineBuild;
                params = [ordered]@{ pooling = 'last_token'; normalize = $Normalize; dtype = $Dtype; device = $Device; max_tokens = $MaxTokens } }
        )
    }
} catch {
    $status = 'error'
    $e = $_.TargetObject
    if ($null -ne $e -and (Has $e 'code')) { $errorObj = [ordered]@{ code = [string](Prop $e 'code'); message = [string](Prop $e 'message'); retryable = [bool](Prop $e 'retryable' $false) } }
    else { $errorObj = [ordered]@{ code = 'unhandled'; message = "$($_.Exception.Message)"; retryable = $false } }
    Write-Diag "ERROR [$($errorObj.code)]: $($errorObj.message)"
} finally {
    # release gpu lease (only if WE owned the fresh acquire)
    if ($leaseState.owned -and -not [string]::IsNullOrWhiteSpace($leaseState.lease_id)) {
        try { [void](Run-Capture $PwshPath (@('-NoProfile', '-NonInteractive', '-File', $ResLeasePath, '-Action', 'release', '-Resource', 'gpu', '-Holder', $leaseState.holder, '-LeaseId', $leaseState.lease_id))); Write-Diag "gpu lease released ($($leaseState.lease_id))" }
        catch { $warnings.Add("gpu lease release failed: $($_.Exception.Message)") }
    }
    # orphan sweep: the transient worker is synchronous; assert none linger
    if (-not $isMock -and $IsWindows) {
        try {
            $orphans = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match 'embed_worker\.py' })
            if ($orphans.Count -gt 0) {
                foreach ($o in $orphans) { try { Stop-Process -Id ([int]$o.ProcessId) -Force -ErrorAction SilentlyContinue } catch { } }
                $warnings.Add("reaped $($orphans.Count) lingering embed_worker process(es)")
            }
        } catch { }
    }
}

# ---------- artifacts manifest ----------
foreach ($fn in @('worker_out.json', 'worker_args.json', 'worker.log')) {
    $fp = Join-Path $invDir $fn
    if (Test-Path -LiteralPath $fp -PathType Leaf) {
        $fi = Get-Item -LiteralPath $fp
        $kind = if ($fn -like '*.json') { 'json' } else { 'log' }
        $artifacts += [ordered]@{ path = $fi.FullName; kind = $kind; bytes = [int]$fi.Length; sha256 = (Get-Sha256HexFile $fi.FullName) }
    }
}

# ---------- emit envelope ----------
$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest = $inputsDigest
    result = $result; confidence = $null; artifacts = $artifacts; model_provenance = $modelProvenance
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
