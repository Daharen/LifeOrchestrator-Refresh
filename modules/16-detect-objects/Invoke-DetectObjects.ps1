#requires -Version 7.0
<#
.SYNOPSIS
  detect.objects -- object detection returning class boxes + real per-detection confidence
  (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Detects objects in one image and returns each as {class, class_id, score, box{x,y,width,height}} with a
  REAL per-detection confidence (YOLOX objectness * class score). Runs a staged ONNX detector via
  onnxruntime inside a Python worker (detect_worker.py) under the system python and reads the worker's meta
  file (worker+meta hand-off), the D-0021 pattern in its ONNX/onnxruntime variant. Resolves the detector
  from the model registry (models.json, type=detector), decoupled from the gateway's `wired` gate (like
  ocr.layout, D-0023). Default CPU execution provider -> no port/VRAM/CUDA binding, so parallel_safe.

  Third image/document perception module. Stochastic/mixed: populates the envelope `confidence` (the best
  detection's score) + `model_provenance` and routes low-confidence / no-object results to the review queue
  (the sixth producer). Can compose capture.screen (Module 6) as its input source (-Capture "detect on
  screen") and image.util (Module 15) to downscale a very large input then rescale boxes back (-MaxDimension).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes detect.json,
  detect.md, detect_args.json, detect_meta.json, worker.log, result.json, stderr.txt (+ capture/... when
  -Capture, image_util/... when -MaxDimension downscales). Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\photo.jpg
  pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\big.png -MaxDimension 1280 -Classes person,car
  pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -Capture -CaptureInputsJson '{"target":"monitor","monitor":"primary"}'
  pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputsJson '{"input":"street.jpg","score_threshold":0.4}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Model,
    [string]$Tier,
    [double]$ScoreThreshold = 0.25,
    [double]$ConfidenceThreshold = 0.5,
    [double]$NmsThreshold = 0.45,
    [int]$MaxDetections = 100,
    [string[]]$Classes,
    [string]$Provider = 'cpu',
    [int]$MaxDimension,
    [int]$MaxReviewDetections = 25,
    [int]$MinImagePixels = 1,
    [switch]$Capture,
    [string]$CaptureInputsJson,
    [string]$Registry,
    [string]$ModelPath,
    [string]$DetectWorkerPath,
    [string]$PythonPath,
    [string]$ImageUtilPath,
    [string]$CapturePath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'detect.objects'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[detect.objects] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-RepoRoot([string]$start) {
    try {
        $d = Get-Item -LiteralPath $start
        for ($i = 0; $i -lt 8 -and $null -ne $d; $i++) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'core-docs')) { return $d.FullName }
            $d = $d.Parent
        }
    } catch { }
    return $null
}
function Test-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c 'import onnxruntime, PIL, numpy' 2>$null | Out-Null
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
# Run a child pwsh entrypoint (capture.screen / image.util) and return its parsed lifeorch envelope.
function Invoke-ChildSkill([string]$exe, [string[]]$argv) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $exe @argv 2> $tmpErr.FullName
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ exit = $code; env = $env; raw = $txt }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    $captureInputsObj = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'input')      -and -not $bound.ContainsKey('InputFile'))            { $InputFile = [string]$p.input }
            if ((Has $p 'model')      -and -not $bound.ContainsKey('Model'))                { $Model = [string]$p.model }
            if ((Has $p 'tier')       -and -not $bound.ContainsKey('Tier'))                 { $Tier = [string]$p.tier }
            if ((Has $p 'score_threshold') -and -not $bound.ContainsKey('ScoreThreshold')) { $ScoreThreshold = [double]$p.score_threshold }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'nms_threshold') -and -not $bound.ContainsKey('NmsThreshold'))     { $NmsThreshold = [double]$p.nms_threshold }
            if ((Has $p 'max_detections') -and -not $bound.ContainsKey('MaxDetections'))   { $MaxDetections = [int]$p.max_detections }
            if ((Has $p 'classes')    -and -not $bound.ContainsKey('Classes'))             { $Classes = @($p.classes | ForEach-Object { [string]$_ }) }
            if ((Has $p 'provider')   -and -not $bound.ContainsKey('Provider'))            { $Provider = [string]$p.provider }
            if ((Has $p 'max_review_detections') -and -not $bound.ContainsKey('MaxReviewDetections')) { $MaxReviewDetections = [int]$p.max_review_detections }
            if ((Has $p 'min_image_pixels') -and -not $bound.ContainsKey('MinImagePixels')) { $MinImagePixels = [int]$p.min_image_pixels }
            if ((Has $p 'capture')    -and -not $bound.ContainsKey('Capture'))             { if ([bool]$p.capture) { $Capture = [switch]$true } }
            if  (Has $p 'capture_inputs') { $captureInputsObj = $p.capture_inputs }
            if ((Has $p 'registry')   -and -not $bound.ContainsKey('Registry'))            { $Registry = [string]$p.registry }
            if ((Has $p 'model_path') -and -not $bound.ContainsKey('ModelPath'))           { $ModelPath = [string]$p.model_path }
            if ((Has $p 'detect_worker_path') -and -not $bound.ContainsKey('DetectWorkerPath')) { $DetectWorkerPath = [string]$p.detect_worker_path }
            if ((Has $p 'python_path') -and -not $bound.ContainsKey('PythonPath'))         { $PythonPath = [string]$p.python_path }
            if ((Has $p 'image_util_path') -and -not $bound.ContainsKey('ImageUtilPath'))  { $ImageUtilPath = [string]$p.image_util_path }
            if ((Has $p 'capture_path') -and -not $bound.ContainsKey('CapturePath'))       { $CapturePath = [string]$p.capture_path }
            if ((Has $p 'pwsh_path')  -and -not $bound.ContainsKey('PwshPath'))            { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $hasMaxDim = $bound.ContainsKey('MaxDimension')
    if ($null -ne $p -and (Has $p 'max_dimension') -and -not $hasMaxDim) { $MaxDimension = [int]$p.max_dimension; $hasMaxDim = $true }
    if ([string]::IsNullOrWhiteSpace($Provider)) { $Provider = 'cpu' }
    if (-not [string]::IsNullOrWhiteSpace($CaptureInputsJson)) { try { $captureInputsObj = $CaptureInputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_capture_inputs'; message='-CaptureInputsJson is not valid JSON'; retryable=$false } } }
    $classList = @(); if ($null -ne $Classes) { $classList = @($Classes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ }) }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ input=$InputFile; model=$Model; tier=$Tier; score_threshold=$ScoreThreshold;
        confidence_threshold=$ConfidenceThreshold; nms_threshold=$NmsThreshold; max_detections=$MaxDetections;
        classes=$classList; provider=$Provider; max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null });
        capture=[bool]$Capture; capture_inputs=$captureInputsObj }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- resolve detector from registry (decoupled from the gateway wired gate) ----
    if ([string]::IsNullOrWhiteSpace($Registry)) {
        $cand = Join-Path $PSScriptRoot '..\07-model-gateway\models.json'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $Registry = (Resolve-Path -LiteralPath $cand).Path }
        else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $Registry = Join-Path $root 'modules\07-model-gateway\models.json' } }
    }
    if ([string]::IsNullOrWhiteSpace($Registry) -or -not (Test-Path -LiteralPath $Registry -PathType Leaf)) {
        throw [PSCustomObject]@{ code='registry_not_found'; message="model registry not found: $Registry"; retryable=$false }
    }
    $reg = (Get-Content -LiteralPath $Registry -Raw) | ConvertFrom-Json
    $models = @(); if (Has $reg 'models') { $models = @($reg.models) }
    # pick the model id: explicit -Model > -Tier via tiers.detector > defaults.detector
    $modelId = $Model
    if ([string]::IsNullOrWhiteSpace($modelId) -and -not [string]::IsNullOrWhiteSpace($Tier)) {
        if ((Has $reg 'tiers') -and (Has $reg.tiers 'detector') -and (Has $reg.tiers.detector $Tier)) { $modelId = [string]$reg.tiers.detector.$Tier }
        else { throw [PSCustomObject]@{ code='tier_not_found'; message="detector tier '$Tier' not in registry tiers.detector"; retryable=$false } }
    }
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        if ((Has $reg 'defaults') -and (Has $reg.defaults 'detector')) { $modelId = [string]$reg.defaults.detector }
        else { throw [PSCustomObject]@{ code='no_default_detector'; message='registry has no defaults.detector and no -Model/-Tier was given'; retryable=$false } }
    }
    $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $modelId) } | Select-Object -First 1
    if ($null -eq $m) {
        $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'detector') } | ForEach-Object { $_.model_id }) -join ', '
        throw [PSCustomObject]@{ code='model_not_found'; message="detector '$modelId' not in registry. Known detectors: $known"; retryable=$false }
    }
    if ([string](Prop $m 'type' '') -ne 'detector') { throw [PSCustomObject]@{ code='unsupported_type'; message="detect.objects runs type=detector only (model '$modelId' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
    $engineName = [string](Prop $m 'engine' '')
    if ($engineName -ne 'onnxruntime') {
        throw [PSCustomObject]@{ code='engine_not_implemented'; message="engine '$engineName' ($modelId) is declared but not wired in this MVP; only onnxruntime is implemented"; retryable=$false }
    }
    # effective model file: -ModelPath override wins over the registry path
    $effModelPath = if (-not [string]::IsNullOrWhiteSpace($ModelPath)) { $ModelPath } else { [string](Prop $m 'path' '') }
    if ([string]::IsNullOrWhiteSpace($effModelPath) -or -not (Test-Path -LiteralPath $effModelPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='model_file_not_found'; message="detector model file not found: '$effModelPath' (registry '$modelId'; set -ModelPath to override)"; retryable=$false }
    }
    $effModelPath = (Resolve-Path -LiteralPath $effModelPath).Path
    $mParams = Prop $m 'params' $null

    # ---- resolve input: explicit file wins; else compose capture.screen ----
    $source = 'file'; $captureInfo = $null; $imagePath = $null
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        if ($Capture) { $warnings.Add('-Capture ignored because an explicit -InputFile was provided') }
        if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
            throw [PSCustomObject]@{ code='input_not_found'; message="input image not found: $InputFile"; retryable=$false }
        }
        $imagePath = (Resolve-Path -LiteralPath $InputFile).Path
    }
    elseif ($Capture) {
        $source = 'capture'
        if ([string]::IsNullOrWhiteSpace($CapturePath)) {
            $cc = Join-Path $PSScriptRoot '..\06-capture-screen\Invoke-CaptureScreen.ps1'
            if (Test-Path -LiteralPath $cc -PathType Leaf) { $CapturePath = (Resolve-Path -LiteralPath $cc).Path }
            else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $CapturePath = Join-Path $root 'modules\06-capture-screen\Invoke-CaptureScreen.ps1' } }
        }
        if ([string]::IsNullOrWhiteSpace($CapturePath) -or -not (Test-Path -LiteralPath $CapturePath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='capture_not_found'; message="capture.screen entrypoint not found (set -CapturePath). got '$CapturePath'"; retryable=$false }
        }
        $capInputs = if ($null -ne $captureInputsObj) { $captureInputsObj } else { [ordered]@{ target='monitor'; monitor='primary'; format='png' } }
        $capRoot = Join-Path $invDir 'capture'
        $capJson = ($capInputs | ConvertTo-Json -Compress -Depth 8)
        Write-Diag "capturing via capture.screen -> $capRoot"
        $capArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$CapturePath,'-InputsJson',$capJson,'-ArtifactRoot',$capRoot)
        $capRun = Invoke-ChildSkill $PwshPath $capArgs
        $capEnv = $capRun.env
        if ($null -eq $capEnv -or -not (Has $capEnv 'status') -or (@('ok','partial') -notcontains [string]$capEnv.status)) {
            $cc2 = if ($null -ne $capEnv -and (Has $capEnv 'error')) { [string](Prop $capEnv.error 'code' 'capture_failed') } else { 'capture_failed' }
            throw [PSCustomObject]@{ code='capture_failed'; message="capture.screen did not produce an image ($cc2)"; retryable=$true }
        }
        $capPath = ''
        if ((Has $capEnv 'result') -and (Has $capEnv.result 'capture')) { $capPath = [string](Prop $capEnv.result.capture 'path' '') }
        if ([string]::IsNullOrWhiteSpace($capPath) -or -not (Test-Path -LiteralPath $capPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='capture_failed'; message='capture.screen envelope carried no image path'; retryable=$true }
        }
        $imagePath = (Resolve-Path -LiteralPath $capPath).Path
        $capW = 0; $capH = 0
        if ((Has $capEnv 'result') -and (Has $capEnv.result 'capture')) { $capW = [int](Prop $capEnv.result.capture 'image_width' 0); $capH = [int](Prop $capEnv.result.capture 'image_height' 0) }
        $captureInfo = [ordered]@{ inputs=$capInputs; artifact_dir=$capRoot; image=[ordered]@{ path=$imagePath; width=$capW; height=$capH } }
    }
    else {
        throw [PSCustomObject]@{ code='input_not_found'; message='no input image specified (-InputFile / InputsJson.input) and -Capture not set'; retryable=$false }
    }

    # ---- optional downscale via image.util (rescale boxes back to original pixels) ----
    $preprocess = [ordered]@{ max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null }); downscaled=$false; scale_x=1.0; scale_y=1.0; original=$null; artifact_dir=$null }
    $workerImage = $imagePath; $boxScaleX = 1.0; $boxScaleY = 1.0; $origW = 0; $origH = 0
    if ($hasMaxDim -and $MaxDimension -gt 0) {
        if ([string]::IsNullOrWhiteSpace($ImageUtilPath)) {
            $iu = Join-Path $PSScriptRoot '..\15-image-util\Invoke-ImageUtil.ps1'
            if (Test-Path -LiteralPath $iu -PathType Leaf) { $ImageUtilPath = (Resolve-Path -LiteralPath $iu).Path }
            else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $ImageUtilPath = Join-Path $root 'modules\15-image-util\Invoke-ImageUtil.ps1' } }
        }
        if ([string]::IsNullOrWhiteSpace($ImageUtilPath) -or -not (Test-Path -LiteralPath $ImageUtilPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='image_util_not_found'; message="image.util entrypoint not found for -MaxDimension downscale (set -ImageUtilPath). got '$ImageUtilPath'"; retryable=$false }
        }
        $iuRoot = Join-Path $invDir 'image_util'
        $iuInputs = [ordered]@{ input=$imagePath; op='resize'; max_dimension=[int]$MaxDimension }
        if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $iuInputs.python_path = $PythonPath }
        $iuJson = ($iuInputs | ConvertTo-Json -Compress -Depth 8)
        Write-Diag "downscaling via image.util (max_dimension=$MaxDimension) -> $iuRoot"
        $iuArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$ImageUtilPath,'-InputsJson',$iuJson,'-ArtifactRoot',$iuRoot)
        $iuRun = Invoke-ChildSkill $PwshPath $iuArgs
        $iuEnv = $iuRun.env
        if ($null -eq $iuEnv -or -not (Has $iuEnv 'status') -or (@('ok','partial') -notcontains [string]$iuEnv.status)) {
            $ic = if ($null -ne $iuEnv -and (Has $iuEnv 'error')) { [string](Prop $iuEnv.error 'code' 'image_util_failed') } else { 'image_util_failed' }
            throw [PSCustomObject]@{ code='downscale_failed'; message="image.util downscale failed ($ic)"; retryable=$true }
        }
        $rz = $null; if ((Has $iuEnv 'result') -and (Has $iuEnv.result 'resize')) { $rz = $iuEnv.result.resize }
        $sx = [double](Prop $rz 'scale_x' 1.0); $sy = [double](Prop $rz 'scale_y' 1.0)
        if ($null -ne $rz -and (Has $rz 'original')) { $origW = [int](Prop $rz.original 'width' 0); $origH = [int](Prop $rz.original 'height' 0) }
        $preprocess.scale_x = $sx; $preprocess.scale_y = $sy; $preprocess.artifact_dir = $iuRoot
        $preprocess.original = [ordered]@{ width=$origW; height=$origH }
        if (($sx -lt 1.0 -or $sy -lt 1.0) -and (Has $iuEnv.result 'outputs')) {
            $outs = @($iuEnv.result.outputs)
            if ($outs.Count -gt 0) {
                $dPath = [string](Prop $outs[0] 'path' '')
                if (-not [string]::IsNullOrWhiteSpace($dPath) -and (Test-Path -LiteralPath $dPath -PathType Leaf)) {
                    $workerImage = (Resolve-Path -LiteralPath $dPath).Path
                    $boxScaleX = if ($sx -ne 0) { 1.0 / $sx } else { 1.0 }
                    $boxScaleY = if ($sy -ne 0) { 1.0 / $sy } else { 1.0 }
                    $preprocess.downscaled = $true
                }
            }
        }
        if (-not $preprocess.downscaled) { $warnings.Add("image was not larger than max_dimension=$MaxDimension; detection ran at full resolution") }
    }

    # ---- resolve python (onnxruntime + PIL + numpy) ----
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    $regEnv = [string](Prop $m 'engine_env' '')
    if (-not [string]::IsNullOrWhiteSpace($regEnv)) { $cands.Add($regEnv) }
    $cands.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
    $cands.Add('F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe')
    foreach ($n in @('python','python3','py')) {
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
        throw [PSCustomObject]@{ code='python_not_found'; message="no python with onnxruntime+PIL+numpy found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve worker ----
    if ([string]::IsNullOrWhiteSpace($DetectWorkerPath)) { $DetectWorkerPath = Join-Path $PSScriptRoot 'detect_worker.py' }
    if (-not (Test-Path -LiteralPath $DetectWorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="detect_worker.py not found at '$DetectWorkerPath' (set -DetectWorkerPath)"; retryable=$false }
    }
    $DetectWorkerPath = (Resolve-Path -LiteralPath $DetectWorkerPath).Path

    # ---- run the worker (meta-file hand-off) ----
    $metaPath = Join-Path $invDir 'detect_meta.json'
    $wargs = [ordered]@{
        image = $workerImage; model = $effModelPath; meta_path = $metaPath; output_dir = $invDir
        score_threshold = [double]$ScoreThreshold; nms_threshold = [double]$NmsThreshold
        max_detections = [int]$MaxDetections; provider = $Provider
        box_scale_x = [double]$boxScaleX; box_scale_y = [double]$boxScaleY
    }
    if ($classList.Count -gt 0) { $wargs.classes = $classList }
    if ($preprocess.downscaled -and $origW -gt 0 -and $origH -gt 0) { $wargs.orig_width = $origW; $wargs.orig_height = $origH }
    $argsFile = Join-Path $invDir 'detect_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 8), $utf8)

    Write-Diag "python=$python worker=$DetectWorkerPath model=$effModelPath image=$workerImage provider=$Provider"
    $run = Invoke-Worker $python @($DetectWorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='detect_failed'; message="detect worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'detect_failed'); $em = [string](Prop $meta 'error' 'detect worker failed')
        throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$false }
    }

    # ---- build detections / confidence / summary ----
    $imgW = [int](Prop $meta.image 'width' 0); $imgH = [int](Prop $meta.image 'height' 0)
    $inSize = @(Prop $meta 'input_size' @(0,0))
    $numClasses = [int](Prop $meta 'num_classes' 0)
    $providerUsed = [string](Prop $meta 'provider_used' $Provider)
    $inferMs = [int](Prop $meta 'infer_ms' 0)
    $workerMs = [int](Prop $meta 'runtime_ms' 0)
    foreach ($w in @(Prop $meta 'warnings' @())) { $warnings.Add([string]$w) }

    $detsOut = New-Object System.Collections.Generic.List[object]
    $scores = New-Object System.Collections.Generic.List[double]
    $summary = [ordered]@{}
    foreach ($d in @(Prop $meta 'detections' @())) {
        $sc = [double](Prop $d 'score' 0)
        $cls = [string](Prop $d 'class' '')
        $box = Prop $d 'box' $null
        $lowc = ($sc -lt $ConfidenceThreshold)
        $detsOut.Add([ordered]@{
            index=[int](Prop $d 'index' 0); class_id=[int](Prop $d 'class_id' -1); class=$cls
            score=[math]::Round($sc,6); low_confidence=$lowc
            box=[ordered]@{ x=[int](Prop $box 'x' 0); y=[int](Prop $box 'y' 0); width=[int](Prop $box 'width' 0); height=[int](Prop $box 'height' 0) }
        })
        $scores.Add($sc)
        if ($summary.Contains($cls)) { $summary[$cls] = [int]$summary[$cls] + 1 } else { $summary[$cls] = 1 }
    }
    $detArr = $detsOut.ToArray()
    $detCount = $detArr.Count
    $overall = $null; $meanC = $null; $minC = $null; $lowCount = 0
    if ($scores.Count -gt 0) {
        $sa = $scores.ToArray()
        $overall = [math]::Round((($sa | Measure-Object -Maximum).Maximum), 6)
        $minC = [math]::Round((($sa | Measure-Object -Minimum).Minimum), 6)
        $meanC = [math]::Round((($sa | Measure-Object -Average).Average), 6)
        $lowCount = @($detArr | Where-Object { $_.low_confidence }).Count
    }
    $overallReason = if ($detCount -eq 0) { 'no_objects' } elseif ($null -ne $overall -and $overall -lt $ConfidenceThreshold) { 'low_confidence' } else { 'confident' }
    # envelope confidence: the best detection's score; 0.1 sentinel when nothing was found (mixed skill must populate it)
    $confidence = if ($null -ne $overall) { [double]$overall } else { 0.1 }

    $result = [ordered]@{
        input = [ordered]@{ path=$imagePath; exists=$true; source=$source; capture=$captureInfo }
        image = [ordered]@{ width=$imgW; height=$imgH }
        model = [ordered]@{ id=$modelId; name=[string](Prop $m 'name' $modelId); family=[string](Prop $m 'family' 'yolox'); engine=$engineName; provider=$providerUsed; input_size=$inSize; num_classes=$numClasses; path=$effModelPath }
        params = [ordered]@{ score_threshold=$ScoreThreshold; confidence_threshold=$ConfidenceThreshold; nms_threshold=$NmsThreshold; max_detections=$MaxDetections; classes=$classList }
        preprocess = $preprocess
        detection_count = $detCount
        class_summary = $summary
        detections = $detArr
        confidence = [ordered]@{ overall=$overall; mean=$meanC; min=$minC; low_confidence_count=$lowCount; reason=$overallReason }
        review = [ordered]@{ threshold=$ConfidenceThreshold; flagged_count=0; truncated=$false; queue_path=$null }
        detect = [ordered]@{ engine_env=$python; provider=$providerUsed; infer_ms=$inferMs; runtime_ms=$workerMs }
    }
    $modelProvenance = @(
        [ordered]@{
            model_id=$modelId; name=[string](Prop $m 'name' $modelId); family=[string](Prop $m 'family' 'yolox')
            engine=$engineName; provider=$providerUsed; engine_env=$python
            input_size=$inSize; num_classes=$numClasses; detection_count=$detCount
            infer_ms=$inferMs; runtime_ms=$workerMs
        }
    )
    Write-Diag "ok detections=$detCount overall=$overall ($overallReason) provider=$providerUsed classes=$($summary.Keys -join ',')"
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

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $dj = [ordered]@{ schema='lifeorch.detect.objects/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            model=$result.model; image=$result.image; params=$result.params; preprocess=$result.preprocess;
            detection_count=$result.detection_count; class_summary=$result.class_summary; detections=$result.detections; confidence=$result.confidence }
        $djPath = Join-Path $invDir 'detect.json'
        [System.IO.File]::WriteAllText($djPath, ($dj | ConvertTo-Json -Depth 20), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# detect.objects -- $($result.model.id) ($($result.model.provider))")
        [void]$mb.AppendLine("image: $($result.input.path)")
        [void]$mb.AppendLine("size: $($result.image.width)x$($result.image.height)  detections=$($result.detection_count)  provider=$($result.model.provider)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  mean=$($result.confidence.mean)  min=$($result.confidence.min)  low_conf=$($result.confidence.low_confidence_count)")
        $keys = @($result.class_summary.PSObject.Properties.Name)
        if ($keys.Count -gt 0) { [void]$mb.AppendLine("classes: " + (($keys | ForEach-Object { "$_=$($result.class_summary.$_)" }) -join ', ')) }
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('| # | class | score | box (x,y,w,h) |')
        [void]$mb.AppendLine('|---|-------|-------|---------------|')
        $rowMax = 300; $rowN = 0
        foreach ($d in @($result.detections)) {
            if ($rowN -ge $rowMax) { [void]$mb.AppendLine("| ... | | | ($($result.detection_count - $rowMax) more -- see detect.json) |"); break }
            $mark = if ($d.low_confidence) { '! ' } else { '' }
            $b = $d.box
            [void]$mb.AppendLine("| $($d.index) | $($d.class) | $mark$($d.score) | $($b.x),$($b.y),$($b.width),$($b.height) |")
            $rowN++
        }
        $dmPath = Join-Path $invDir 'detect.md'
        [System.IO.File]::WriteAllText($dmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$djPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$dmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[detect.objects] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (no-objects guard OR low-confidence page; append-only producer #6) ----
try {
    if ($status -ne 'error' -and $null -ne $result) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $imgPixels = [long]$result.image.width * [long]$result.image.height
        $flagged = 0; $truncated = $false
        if ($result.detection_count -eq 0 -and $imgPixels -ge $MinImagePixels) {
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-noobj"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='uncategorized'
                confidence=$result.confidence.overall; source_ref="artifact://$invDir/detect.json"
                weak_result=[ordered]@{ model=$modelId; image=$result.input.path; width=$result.image.width; height=$result.image.height; score_threshold=$ScoreThreshold; note='no objects detected above score_threshold in a non-empty image' }
                requested='verify_no_objects'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $flagged++
        }
        elseif ($null -ne $confidence -and $null -ne $result.confidence.overall -and $result.confidence.overall -lt $ConfidenceThreshold) {
            $worst = @($result.detections | Sort-Object { [double]$_.score })
            $take = $worst
            if ($worst.Count -gt $MaxReviewDetections) { $take = @($worst[0..($MaxReviewDetections-1)]); $truncated = $true }
            $detDetail = @($take | ForEach-Object { [ordered]@{ index=$_.index; class=$_.class; score=$_.score; box=$_.box } })
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-detect"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='low_confidence'
                confidence=$result.confidence.overall; source_ref="artifact://$invDir/detect.json"
                weak_result=[ordered]@{ model=$modelId; image=$result.input.path; detection_count=$result.detection_count; reason=$overallReason; low_confidence_count=$lowCount; detections=$detDetail }
                requested='verify_detections'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $flagged++
        }
        if ($flagged -gt 0) {
            $result.review.flagged_count = $flagged
            $result.review.truncated = $truncated
            $result.review.queue_path = $rqPath
            $warnings.Add("flagged detection result to review queue ($rqPath): confidence $($result.confidence.overall) < $ConfidenceThreshold or no objects")
            Write-Diag "review-queued: $flagged -> $rqPath"
        }
    }
} catch { Write-Diag "review-queue append failed: $($_.Exception.Message)" }

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
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
