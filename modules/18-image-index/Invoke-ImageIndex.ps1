#requires -Version 7.0
<#
.SYNOPSIS
  image.index -- fuse the perception block (14-17) into one per-image machine index + human card (Life Orchestrator, contract v0.1).
.DESCRIPTION
  The capstone of the image/document perception block (14-18). Given one image it runs the perception children and
  fuses their results into a single record:
    (1) image.util (#15)      -- ALWAYS: metadata + sha256/pHash/dHash (the deterministic backbone).
    (2) ocr.layout (#14)      -- optional (-Ocr):       text + per-word/line boxes + reading order.
    (3) detect.objects (#16)  -- optional (-Detect):    class boxes + real per-detection scores + class summary.
    (4) image.interpret (#17) -- optional (-Interpret): a local-VLM free-text interpretation (caption/describe/vqa/screen).
  -All enables the three optional stages. -Capture sources the image ONCE via capture.screen (#6) and feeds it to every
  stage. -MaxDimension is passed through to detect + interpret (they downscale-then-rescale boxes).

  It is an ORCHESTRATOR and reimplements nothing: it spawns each child as a child pwsh process, parses its
  lifeorch.skill.result/0.1 envelope, aggregates every child's model_provenance (stage-tagged), and REDIRECTS each
  child's review-queue writes to an in-artifact child_review.jsonl (a transient index run does not flood the canonical
  review_queue.jsonl). image.index is NOT itself a review producer and does not re-flag. Children run SEQUENTIALLY
  (capture -> image.util -> ocr -> detect -> interpret) to avoid VRAM/loopback-port contention from image.interpret.

  Envelope confidence = the MINIMUM confidence across the stochastic stages that actually ran (the weakest-link signal
  for the fused record), or null when only image.util ran. determinism=mixed, parallel_safe=false (can bind CUDA/VRAM +
  a loopback port via -Interpret), batch=false, streaming=false. Emits one envelope on stdout; diagnostics to stderr;
  writes index.json, index.md, child_review.jsonl (when a child flags), result.json, stderr.txt (+ per-stage sub-roots).
  Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\photo.jpg -All
  pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\scan.png -Ocr -Detect
  pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -Capture -All -InterpretMode screen
  pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputsJson '{"input":"chart.png","interpret":true,"prompt":"What is the trend?"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [switch]$Ocr,
    [switch]$Detect,
    [switch]$Interpret,
    [switch]$All,
    [switch]$Capture,
    [string]$CaptureInputsJson,
    [int]$MaxDimension,
    [string]$Language,
    [string[]]$Classes,
    [string]$InterpretMode = 'describe',
    [string]$Prompt,
    [string]$Tier,
    [string]$InterpretModel,
    [double]$ConfidenceThreshold = 0.5,
    [string]$ImageUtilPath,
    [string]$OcrPath,
    [string]$DetectPath,
    [string]$InterpretPath,
    [string]$CapturePath,
    [string]$PythonPath,
    [string]$Powershell51Path,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'image.index'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[image.index] $m") }
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
function Resolve-Child([string]$override, [string]$relPath) {
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if (Test-Path -LiteralPath $override -PathType Leaf) { return (Resolve-Path -LiteralPath $override).Path }
        return $null
    }
    $cand = Join-Path $PSScriptRoot $relPath
    if (Test-Path -LiteralPath $cand -PathType Leaf) { return (Resolve-Path -LiteralPath $cand).Path }
    $root = Resolve-RepoRoot $PSScriptRoot
    if ($null -ne $root) {
        $cand2 = Join-Path $root ($relPath -replace '\.\.[\\/]', 'modules\')
        if (Test-Path -LiteralPath $cand2 -PathType Leaf) { return (Resolve-Path -LiteralPath $cand2).Path }
    }
    return $null
}
# Run a child pwsh entrypoint (-InputsJson / -ArtifactRoot) and return its parsed lifeorch envelope.
function Invoke-Child([string]$entry, [string]$inputsJson, [string]$subRoot) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-InputsJson',$inputsJson,'-ArtifactRoot',$subRoot)
    $out = & $PwshPath @callArgs 2> $tmpErr.FullName
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $errTxt = ''; try { $errTxt = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ exit = $code; env = $env; raw = $txt; err = $errTxt }
}
function Add-Provenance($agg, $env, [string]$stage) {
    if ($null -ne $env -and (Has $env 'model_provenance')) {
        foreach ($mp in @($env.model_provenance)) {
            if ($null -eq $mp) { continue }
            $o = [ordered]@{ stage = $stage }
            foreach ($pn in $mp.PSObject.Properties.Name) { $o[$pn] = $mp.$pn }
            $agg.Add([pscustomobject]$o)
        }
    }
}
function Test-ChildOk($env) { return ($null -ne $env -and (Has $env 'status') -and (@('ok','partial') -contains [string]$env.status)) }
function Get-ChildErrCode($env) {
    if ($null -ne $env -and (Has $env 'error') -and $null -ne $env.error) { return [string](Prop $env.error 'code' 'child_error') }
    return 'child_error'
}
function Get-ChildConf($env) {
    if ($null -ne $env -and (Has $env 'confidence') -and $null -ne $env.confidence) { return [double]$env.confidence }
    return $null
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null
$modelProvenance = New-Object System.Collections.Generic.List[object]
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null; $captureInputsObj = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'input')     -and -not $bound.ContainsKey('InputFile'))  { $InputFile = [string]$p.input }
            if ((Has $p 'ocr')       -and -not $bound.ContainsKey('Ocr'))        { if ([bool]$p.ocr) { $Ocr = [switch]$true } }
            if ((Has $p 'detect')    -and -not $bound.ContainsKey('Detect'))     { if ([bool]$p.detect) { $Detect = [switch]$true } }
            if ((Has $p 'interpret') -and -not $bound.ContainsKey('Interpret'))  { if ([bool]$p.interpret) { $Interpret = [switch]$true } }
            if ((Has $p 'all')       -and -not $bound.ContainsKey('All'))        { if ([bool]$p.all) { $All = [switch]$true } }
            if ((Has $p 'capture')   -and -not $bound.ContainsKey('Capture'))    { if ([bool]$p.capture) { $Capture = [switch]$true } }
            if  (Has $p 'capture_inputs') { $captureInputsObj = $p.capture_inputs }
            if ((Has $p 'language')  -and -not $bound.ContainsKey('Language'))   { $Language = [string]$p.language }
            if ((Has $p 'classes')   -and -not $bound.ContainsKey('Classes'))    { $Classes = @($p.classes | ForEach-Object { [string]$_ }) }
            if ((Has $p 'interpret_mode') -and -not $bound.ContainsKey('InterpretMode')) { $InterpretMode = [string]$p.interpret_mode }
            if ((Has $p 'mode')      -and -not $bound.ContainsKey('InterpretMode') -and -not (Has $p 'interpret_mode')) { $InterpretMode = [string]$p.mode }
            if ((Has $p 'prompt')    -and -not $bound.ContainsKey('Prompt'))     { $Prompt = [string]$p.prompt }
            if ((Has $p 'tier')      -and -not $bound.ContainsKey('Tier'))       { $Tier = [string]$p.tier }
            if ((Has $p 'interpret_model') -and -not $bound.ContainsKey('InterpretModel')) { $InterpretModel = [string]$p.interpret_model }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'image_util_path') -and -not $bound.ContainsKey('ImageUtilPath')) { $ImageUtilPath = [string]$p.image_util_path }
            if ((Has $p 'ocr_path')  -and -not $bound.ContainsKey('OcrPath'))    { $OcrPath = [string]$p.ocr_path }
            if ((Has $p 'detect_path') -and -not $bound.ContainsKey('DetectPath')) { $DetectPath = [string]$p.detect_path }
            if ((Has $p 'interpret_path') -and -not $bound.ContainsKey('InterpretPath')) { $InterpretPath = [string]$p.interpret_path }
            if ((Has $p 'capture_path') -and -not $bound.ContainsKey('CapturePath')) { $CapturePath = [string]$p.capture_path }
            if ((Has $p 'python_path') -and -not $bound.ContainsKey('PythonPath')) { $PythonPath = [string]$p.python_path }
            if ((Has $p 'powershell51_path') -and -not $bound.ContainsKey('Powershell51Path')) { $Powershell51Path = [string]$p.powershell51_path }
            if ((Has $p 'pwsh_path') -and -not $bound.ContainsKey('PwshPath')) { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $hasMaxDim = $bound.ContainsKey('MaxDimension')
    if ($null -ne $p -and (Has $p 'max_dimension') -and -not $hasMaxDim) { $MaxDimension = [int]$p.max_dimension; $hasMaxDim = $true }
    if (-not [string]::IsNullOrWhiteSpace($CaptureInputsJson)) { try { $captureInputsObj = $CaptureInputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_capture_inputs'; message='-CaptureInputsJson is not valid JSON'; retryable=$false } } }

    # ---- effective stage switches ----
    $doOcr = ($Ocr -or $All); $doDetect = ($Detect -or $All); $doInterpret = ($Interpret -or $All)
    $imode = if ([string]::IsNullOrWhiteSpace($InterpretMode)) { 'describe' } else { $InterpretMode.ToLowerInvariant() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ input=$InputFile; capture=[bool]$Capture; ocr=[bool]$doOcr; detect=[bool]$doDetect; interpret=[bool]$doInterpret;
        max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null }); language=$Language; classes=$Classes;
        interpret_mode=$imode; prompt=$Prompt; tier=$Tier; interpret_model=$InterpretModel; confidence_threshold=$ConfidenceThreshold }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $childReviewPath = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $ReviewQueuePath } else { Join-Path $invDir 'child_review.jsonl' }
    $reviewMode = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { 'redirected_explicit' } else { 'redirected_in_artifact' }

    # ---- resolve child entrypoints (image.util always; others only when requested) ----
    $imageUtilEntry = Resolve-Child $ImageUtilPath '..\15-image-util\Invoke-ImageUtil.ps1'
    if ([string]::IsNullOrWhiteSpace($imageUtilEntry)) { throw [PSCustomObject]@{ code='image_util_not_found'; message='image.util entrypoint not found (set -ImageUtilPath)'; retryable=$false } }
    $ocrEntry = $null; $detectEntry = $null; $interpretEntry = $null
    if ($doOcr)       { $ocrEntry = Resolve-Child $OcrPath '..\14-ocr-layout\Invoke-OcrLayout.ps1';       if ([string]::IsNullOrWhiteSpace($ocrEntry)) { throw [PSCustomObject]@{ code='ocr_not_found'; message='ocr.layout entrypoint not found (set -OcrPath)'; retryable=$false } } }
    if ($doDetect)    { $detectEntry = Resolve-Child $DetectPath '..\16-detect-objects\Invoke-DetectObjects.ps1'; if ([string]::IsNullOrWhiteSpace($detectEntry)) { throw [PSCustomObject]@{ code='detect_not_found'; message='detect.objects entrypoint not found (set -DetectPath)'; retryable=$false } } }
    if ($doInterpret) { $interpretEntry = Resolve-Child $InterpretPath '..\17-image-interpret\Invoke-ImageInterpret.ps1'; if ([string]::IsNullOrWhiteSpace($interpretEntry)) { throw [PSCustomObject]@{ code='interpret_not_found'; message='image.interpret entrypoint not found (set -InterpretPath)'; retryable=$false } } }

    # ---- resolve the source image: explicit file wins; else capture.screen ONCE ----
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
        $capEntry = Resolve-Child $CapturePath '..\06-capture-screen\Invoke-CaptureScreen.ps1'
        if ([string]::IsNullOrWhiteSpace($capEntry)) { throw [PSCustomObject]@{ code='capture_not_found'; message='capture.screen entrypoint not found (set -CapturePath)'; retryable=$false } }
        $capInputs = if ($null -ne $captureInputsObj) { $captureInputsObj } else { [ordered]@{ target='monitor'; monitor='primary'; format='png' } }
        $capJson = ($capInputs | ConvertTo-Json -Compress -Depth 8)
        Write-Diag "capturing via capture.screen -> $(Join-Path $invDir 'capture')"
        $capR = Invoke-Child $capEntry $capJson (Join-Path $invDir 'capture')
        $capEnv = $capR.env
        if (-not (Test-ChildOk $capEnv)) { throw [PSCustomObject]@{ code='capture_failed'; message="capture.screen did not produce an image ($(Get-ChildErrCode $capEnv))"; retryable=$true } }
        $capPath = ''
        if ((Has $capEnv 'result') -and (Has $capEnv.result 'capture')) { $capPath = [string](Prop $capEnv.result.capture 'path' '') }
        if ([string]::IsNullOrWhiteSpace($capPath) -or -not (Test-Path -LiteralPath $capPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='capture_failed'; message='capture.screen envelope carried no image path'; retryable=$true }
        }
        $imagePath = (Resolve-Path -LiteralPath $capPath).Path
        $cw = 0; $ch = 0
        if ((Has $capEnv 'result') -and (Has $capEnv.result 'capture')) { $cw = [int](Prop $capEnv.result.capture 'image_width' 0); $ch = [int](Prop $capEnv.result.capture 'image_height' 0) }
        $captureInfo = [ordered]@{ inputs=$capInputs; artifact_dir=(Join-Path $invDir 'capture'); image=[ordered]@{ path=$imagePath; width=$cw; height=$ch } }
    }
    else {
        throw [PSCustomObject]@{ code='input_not_found'; message='no input image specified (-InputFile / InputsJson.input) and -Capture not set'; retryable=$false }
    }

    $stages = [ordered]@{}
    $imgMeta = $null; $imgHashes = $null; $imgW = $null; $imgH = $null

    # ================= Stage 1: image.util meta (ALWAYS) =================
    $iuObj = [ordered]@{ input=$imagePath; op='meta' }
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $iuObj.python_path = $PythonPath }
    $iuJson = ($iuObj | ConvertTo-Json -Compress -Depth 8)
    $swS = [System.Diagnostics.Stopwatch]::StartNew()
    $iuR = Invoke-Child $imageUtilEntry $iuJson (Join-Path $invDir 'image_util')
    $swS.Stop(); $iuEnv = $iuR.env
    $iuStage = [ordered]@{ ran=$true; status=$(if ($null -ne $iuEnv -and (Has $iuEnv 'status')) { [string]$iuEnv.status } else { 'error' }); confidence=$null; reason=$null;
        ms=[int]$swS.Elapsed.TotalMilliseconds; artifact_dir=(Join-Path $invDir 'image_util'); error=$null }
    if (Test-ChildOk $iuEnv) {
        if (Has $iuEnv 'result') {
            $imgMeta = (Prop $iuEnv.result 'metadata' $null)
            $imgHashes = (Prop $iuEnv.result 'hashes' $null)
            if ($null -ne $imgMeta) { $imgW = [int](Prop $imgMeta 'width' 0); $imgH = [int](Prop $imgMeta 'height' 0) }
        }
        Write-Diag "image.util: sha256=$(Prop $imgHashes 'sha256' '') dims=${imgW}x${imgH}"
    } else {
        $iuStage.error = (Get-ChildErrCode $iuEnv)
        $warnings.Add("image.util (meta) failed ($($iuStage.error)); index has no metadata/hashes")
        Write-Diag "image.util FAILED: $($iuStage.error) -- $($iuR.err)"
    }
    $stages.image_util = $iuStage

    # ================= Stage 2: ocr.layout (optional) =================
    $ocrText = $null; $ocrWordCount = $null; $ocrLineCount = $null; $ocrLines = $null
    if ($doOcr) {
        $ocrObj = [ordered]@{ input=$imagePath; review_queue_path=$childReviewPath; confidence_threshold=$ConfidenceThreshold; pwsh_path=$PwshPath }
        if (-not [string]::IsNullOrWhiteSpace($Language)) { $ocrObj.language = $Language }
        if (-not [string]::IsNullOrWhiteSpace($Powershell51Path)) { $ocrObj.powershell51_path = $Powershell51Path }
        if (-not [string]::IsNullOrWhiteSpace($CapturePath)) { $ocrObj.capture_path = $CapturePath }
        $ocrJson = ($ocrObj | ConvertTo-Json -Compress -Depth 8)
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $ocrR = Invoke-Child $ocrEntry $ocrJson (Join-Path $invDir 'ocr')
        $swS.Stop(); $ocrEnv = $ocrR.env
        $ocrConf = Get-ChildConf $ocrEnv
        $ocrStage = [ordered]@{ ran=$true; status=$(if ($null -ne $ocrEnv -and (Has $ocrEnv 'status')) { [string]$ocrEnv.status } else { 'error' }); confidence=$ocrConf; reason=$null;
            ms=[int]$swS.Elapsed.TotalMilliseconds; artifact_dir=(Join-Path $invDir 'ocr'); error=$null;
            word_count=$null; line_count=$null; text=$null; lines=$null }
        if (Test-ChildOk $ocrEnv) {
            if (Has $ocrEnv 'result') {
                $ocrText = [string](Prop $ocrEnv.result 'text' '')
                $ocrWordCount = [int](Prop $ocrEnv.result 'word_count' 0)
                $ocrLineCount = [int](Prop $ocrEnv.result 'line_count' 0)
                if (Has $ocrEnv.result 'lines') { $ocrLines = @($ocrEnv.result.lines) }
                if (Has $ocrEnv.result 'confidence') { $ocrStage.reason = [string](Prop $ocrEnv.result.confidence 'reason' '') }
            }
            $ocrStage.word_count = $ocrWordCount; $ocrStage.line_count = $ocrLineCount; $ocrStage.text = $ocrText; $ocrStage.lines = $ocrLines
            Add-Provenance $modelProvenance $ocrEnv 'ocr'
            Write-Diag "ocr: words=$ocrWordCount lines=$ocrLineCount conf=$ocrConf"
        } else {
            $ocrStage.error = (Get-ChildErrCode $ocrEnv)
            $warnings.Add("ocr.layout failed ($($ocrStage.error))")
            Write-Diag "ocr FAILED: $($ocrStage.error) -- $($ocrR.err)"
        }
        $stages.ocr = $ocrStage
    } else { $stages.ocr = [ordered]@{ ran=$false; status='skipped'; confidence=$null; reason=$null; ms=0; artifact_dir=$null; error=$null } }

    # ================= Stage 3: detect.objects (optional) =================
    $detCount = $null; $detSummary = $null; $detections = $null
    if ($doDetect) {
        $detObj = [ordered]@{ input=$imagePath; review_queue_path=$childReviewPath; confidence_threshold=$ConfidenceThreshold; pwsh_path=$PwshPath }
        if ($null -ne $Classes -and @($Classes).Count -gt 0) { $detObj.classes = @($Classes) }
        if ($hasMaxDim -and $MaxDimension -gt 0) { $detObj.max_dimension = [int]$MaxDimension }
        if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $detObj.python_path = $PythonPath }
        $detJson = ($detObj | ConvertTo-Json -Compress -Depth 8)
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $detR = Invoke-Child $detectEntry $detJson (Join-Path $invDir 'detect')
        $swS.Stop(); $detEnv = $detR.env
        $detConf = Get-ChildConf $detEnv
        $detStage = [ordered]@{ ran=$true; status=$(if ($null -ne $detEnv -and (Has $detEnv 'status')) { [string]$detEnv.status } else { 'error' }); confidence=$detConf; reason=$null;
            ms=[int]$swS.Elapsed.TotalMilliseconds; artifact_dir=(Join-Path $invDir 'detect'); error=$null;
            detection_count=$null; class_summary=$null; detections=$null }
        if (Test-ChildOk $detEnv) {
            if (Has $detEnv 'result') {
                $detCount = [int](Prop $detEnv.result 'detection_count' 0)
                $detSummary = (Prop $detEnv.result 'class_summary' $null)
                if (Has $detEnv.result 'detections') { $detections = @($detEnv.result.detections) }
                if (Has $detEnv.result 'confidence') { $detStage.reason = [string](Prop $detEnv.result.confidence 'reason' '') }
            }
            $detStage.detection_count = $detCount; $detStage.class_summary = $detSummary; $detStage.detections = $detections
            Add-Provenance $modelProvenance $detEnv 'detect'
            Write-Diag "detect: count=$detCount conf=$detConf"
        } else {
            $detStage.error = (Get-ChildErrCode $detEnv)
            $warnings.Add("detect.objects failed ($($detStage.error))")
            Write-Diag "detect FAILED: $($detStage.error) -- $($detR.err)"
        }
        $stages.detect = $detStage
    } else { $stages.detect = [ordered]@{ ran=$false; status='skipped'; confidence=$null; reason=$null; ms=0; artifact_dir=$null; error=$null } }

    # ================= Stage 4: image.interpret (optional) =================
    $interpText = $null; $interpFinish = $null; $interpTokens = $null
    if ($doInterpret) {
        $intObj = [ordered]@{ input=$imagePath; mode=$imode; review_queue_path=$childReviewPath; confidence_threshold=$ConfidenceThreshold; pwsh_path=$PwshPath }
        if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $intObj.prompt = $Prompt }
        if (-not [string]::IsNullOrWhiteSpace($InterpretModel)) { $intObj.model = $InterpretModel } elseif (-not [string]::IsNullOrWhiteSpace($Tier)) { $intObj.tier = $Tier }
        if ($hasMaxDim -and $MaxDimension -gt 0) { $intObj.max_dimension = [int]$MaxDimension }
        if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $intObj.python_path = $PythonPath }
        $intJson = ($intObj | ConvertTo-Json -Compress -Depth 8)
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $intR = Invoke-Child $interpretEntry $intJson (Join-Path $invDir 'interpret')
        $swS.Stop(); $intEnv = $intR.env
        $intConf = Get-ChildConf $intEnv
        $intStage = [ordered]@{ ran=$true; status=$(if ($null -ne $intEnv -and (Has $intEnv 'status')) { [string]$intEnv.status } else { 'error' }); confidence=$intConf; reason=$null;
            ms=[int]$swS.Elapsed.TotalMilliseconds; artifact_dir=(Join-Path $invDir 'interpret'); error=$null;
            mode=$imode; text=$null; finish_reason=$null; completion_tokens=$null }
        if (Test-ChildOk $intEnv) {
            if ((Has $intEnv 'result') -and (Has $intEnv.result 'interpretation')) {
                $interpText = [string](Prop $intEnv.result.interpretation 'text' '')
                $interpFinish = [string](Prop $intEnv.result.interpretation 'finish_reason' '')
                $interpTokens = (Prop $intEnv.result.interpretation 'completion_tokens' $null)
            }
            if ((Has $intEnv 'result') -and (Has $intEnv.result 'confidence')) { $intStage.reason = [string](Prop $intEnv.result.confidence 'reason' '') }
            $intStage.text = $interpText; $intStage.finish_reason = $interpFinish; $intStage.completion_tokens = $interpTokens
            Add-Provenance $modelProvenance $intEnv 'interpret'
            Write-Diag "interpret: mode=$imode finish=$interpFinish conf=$intConf chars=$(if ($null -ne $interpText) { $interpText.Length } else { 0 })"
        } else {
            $intStage.error = (Get-ChildErrCode $intEnv)
            $warnings.Add("image.interpret failed ($($intStage.error))")
            Write-Diag "interpret FAILED: $($intStage.error) -- $($intR.err)"
        }
        $stages.interpret = $intStage
    } else { $stages.interpret = [ordered]@{ ran=$false; status='skipped'; confidence=$null; reason=$null; ms=0; artifact_dir=$null; error=$null } }

    # ---- envelope confidence = min stochastic child confidence (weakest link); null if none ran ----
    $stochConfs = New-Object System.Collections.Generic.List[double]
    foreach ($sn in @('ocr','detect','interpret')) {
        $st = $stages.$sn
        if ($st.ran -and (@('ok','partial') -contains [string]$st.status) -and $null -ne $st.confidence) { $stochConfs.Add([double]$st.confidence) }
    }
    if ($stochConfs.Count -gt 0) { $confidence = ($stochConfs.ToArray() | Measure-Object -Minimum).Minimum } else { $confidence = $null }

    # ---- summary (compact fusion) ----
    $ranNames = New-Object System.Collections.Generic.List[string]
    $okNames = New-Object System.Collections.Generic.List[string]
    $errNames = New-Object System.Collections.Generic.List[string]
    foreach ($sn in @('image_util','ocr','detect','interpret')) {
        $st = $stages.$sn
        if ($st.ran) {
            $ranNames.Add($sn)
            if (@('ok','partial') -contains [string]$st.status) { $okNames.Add($sn) } else { $errNames.Add($sn) }
        }
    }
    $topObjects = @()
    if ($null -ne $detSummary -and $null -ne $detSummary.PSObject) {
        $pairs = New-Object System.Collections.Generic.List[object]
        foreach ($pn in $detSummary.PSObject.Properties.Name) { $pairs.Add([pscustomobject]@{ class=$pn; count=[int]$detSummary.$pn }) }
        $topObjects = @($pairs.ToArray() | Sort-Object -Property count -Descending | Select-Object -First 8)
    }
    $captionPreview = $null
    if (-not [string]::IsNullOrWhiteSpace($interpText)) { $captionPreview = if ($interpText.Length -gt 400) { $interpText.Substring(0,400) } else { $interpText } }

    # ---- child review count (in-artifact aggregate only) ----
    $childReviewCount = 0
    if (Test-Path -LiteralPath $childReviewPath -PathType Leaf) {
        try { $childReviewCount = @(Get-Content -LiteralPath $childReviewPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }).Count } catch { }
    }

    $result = [ordered]@{
        input = [ordered]@{ path=$imagePath; source=$source; capture=$captureInfo }
        image = [ordered]@{ width=$imgW; height=$imgH; format=[string](Prop $imgMeta 'format' ''); mode=[string](Prop $imgMeta 'mode' '');
            has_alpha=[bool](Prop $imgMeta 'has_alpha' $false); dpi=(Prop $imgMeta 'dpi' $null); metadata=$imgMeta }
        hashes = $imgHashes
        stages = $stages
        summary = [ordered]@{
            caption=$captionPreview
            ocr_text=$ocrText
            ocr_word_count=$ocrWordCount
            top_objects=$topObjects
            detection_count=$detCount
            stochastic_confidence_min=$confidence
            stages_ran=$ranNames.ToArray()
            stages_ok=$okNames.ToArray()
            stages_error=$errNames.ToArray()
        }
        review = [ordered]@{ mode=$reviewMode; child_review_path=$childReviewPath; child_review_count=$childReviewCount; is_producer=$false }
        config = [ordered]@{ ocr=$doOcr; detect=$doDetect; interpret=$doInterpret; capture=[bool]$Capture;
            max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null }); interpret_mode=$imode; language=$Language; classes=$Classes; confidence_threshold=$ConfidenceThreshold }
    }

    if ($errNames.Count -gt 0 -or $warnings.Count -gt 0) { $status = 'partial' }
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

# ---- artifacts: index.json + index.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $ij = [ordered]@{ schema='lifeorch.image.index/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            input=$result.input; image=$result.image; hashes=$result.hashes; stages=$result.stages; summary=$result.summary;
            review=$result.review; config=$result.config; model_provenance=$modelProvenance.ToArray() }
        $ijPath = Join-Path $invDir 'index.json'
        [System.IO.File]::WriteAllText($ijPath, ($ij | ConvertTo-Json -Depth 25), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        $fn = Split-Path -Leaf $result.input.path
        [void]$mb.AppendLine("# image.index -- $fn")
        $dimStr = if ($null -ne $result.image.width -and $result.image.width) { "$($result.image.width)x$($result.image.height)" } else { 'unknown' }
        [void]$mb.AppendLine("source: $($result.input.source)   size: $dimStr   format: $($result.image.format)   mode: $($result.image.mode)")
        [void]$mb.AppendLine("sha256: $(Prop $result.hashes 'sha256' 'n/a')")
        [void]$mb.AppendLine("phash: $(Prop $result.hashes 'phash' 'n/a')   dhash: $(Prop $result.hashes 'dhash' 'n/a')")
        $stageLine = @()
        foreach ($sn in @('image_util','ocr','detect','interpret')) {
            $st = $result.stages.$sn
            if (-not $st.ran) { continue }
            $c = if ($null -ne $st.confidence) { "/$($st.confidence)" } else { '' }
            $stageLine += "$sn=$($st.status)$c"
        }
        $minc = if ($null -ne $confidence) { $confidence } else { 'n/a' }
        [void]$mb.AppendLine("stages: " + ($stageLine -join '  ') + "   (min_stochastic_conf=$minc)")
        [void]$mb.AppendLine('')
        if (-not [string]::IsNullOrWhiteSpace($result.summary.caption)) {
            [void]$mb.AppendLine("## Interpretation ($($result.stages.interpret.mode))")
            [void]$mb.AppendLine('')
            [void]$mb.AppendLine([string]$result.stages.interpret.text)
            [void]$mb.AppendLine('')
        }
        if ($result.stages.ocr.ran -and (@('ok','partial') -contains [string]$result.stages.ocr.status)) {
            [void]$mb.AppendLine("## Text (ocr.layout -- $($result.stages.ocr.word_count) words, $($result.stages.ocr.line_count) lines, conf $($result.stages.ocr.confidence))")
            [void]$mb.AppendLine('')
            [void]$mb.AppendLine('```')
            [void]$mb.AppendLine([string]$result.stages.ocr.text)
            [void]$mb.AppendLine('```')
            [void]$mb.AppendLine('')
        }
        if ($result.stages.detect.ran -and (@('ok','partial') -contains [string]$result.stages.detect.status)) {
            [void]$mb.AppendLine("## Objects (detect.objects -- $($result.stages.detect.detection_count) detections, conf $($result.stages.detect.confidence))")
            [void]$mb.AppendLine('')
            if (@($result.summary.top_objects).Count -gt 0) {
                [void]$mb.AppendLine('| class | count |')
                [void]$mb.AppendLine('| --- | --- |')
                foreach ($to in @($result.summary.top_objects)) { [void]$mb.AppendLine("| $($to.class) | $($to.count) |") }
                [void]$mb.AppendLine('')
            }
        }
        [void]$mb.AppendLine('## Provenance')
        [void]$mb.AppendLine('')
        if (@($modelProvenance.ToArray()).Count -gt 0) {
            foreach ($mp in $modelProvenance.ToArray()) { [void]$mb.AppendLine("- [$($mp.stage)] $((Prop $mp 'model_id' '?')) ($((Prop $mp 'engine' '?')))") }
        } else { [void]$mb.AppendLine('- (deterministic; no models used)') }
        $imPath = Join-Path $invDir 'index.md'
        [System.IO.File]::WriteAllText($imPath, $mb.ToString(), $utf8)

        foreach ($a in @([pscustomobject]@{ p=$ijPath; k='json' }, [pscustomobject]@{ p=$imPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[image.index] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$confidence; artifacts=$artifacts; model_provenance=$modelProvenance.ToArray()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 25
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
