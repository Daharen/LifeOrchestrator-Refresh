#requires -Version 7.0
<#
.SYNOPSIS
  ocr.layout — OCR with per-word bounding boxes and reading order (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Recognizes the text in one image and returns the text plus per-word pixel bounding boxes and lines in
  reading order. Runs the system Windows.Media.Ocr engine inside a Windows PowerShell 5.1 worker
  (ocr_worker.ps1) — pwsh 7 cannot load the WinRT projection on this box — and reads the worker's meta file
  (robust to any WinRT/console chatter), the D-0021 worker+meta pattern in its PS-5.1 variant. Resolves the
  OCR engine from the model registry (models.json), decoupled from the gateway's `wired` gate (D-0020).

  First image/document perception module and the first genuinely parallel-safe perception skill (no port/
  VRAM/CUDA binding). Stochastic/mixed: populates a documented legibility `confidence` + `model_provenance`
  and routes low-confidence / no-text results to the review queue (the fifth producer). Can compose
  capture.screen (Module 6) as its input source ("OCR the screen").

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes ocr.json, ocr.md,
  ocr_args.json, ocr_meta.json, worker.log, result.json, stderr.txt (+ capture/… when -Capture ran).
  Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputFile .\screenshot.png
  pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -Capture -CaptureInputsJson '{"target":"window","title":"*Notepad*"}'
  pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputsJson '{"input":"receipt.jpg","confidence_threshold":0.6}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Language = '',
    [string]$Engine = 'ocr.windows.media',
    [string]$Model,
    [double]$ConfidenceThreshold = 0.5,
    [int]$MaxReviewLines = 25,
    [switch]$Capture,
    [string]$CaptureInputsJson,
    [int]$MinImagePixels = 1,
    [string]$Registry,
    [string]$OcrWorkerPath,
    [string]$Powershell51Path = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe',
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

$SKILL_ID = 'ocr.layout'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[ocr.layout] $m") }
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
# A "clean" word contains at least one letter/digit and is otherwise letters/digits/punctuation/symbols,
# length <= 40. The fraction of clean words is the legibility proxy behind the (NOT calibrated) confidence.
function Test-CleanWord([string]$w) {
    if ($null -eq $w) { return $false }
    $t = $w.Trim()
    if ($t.Length -eq 0 -or $t.Length -gt 40) { return $false }
    if ($t -notmatch '[\p{L}\p{Nd}]') { return $false }
    return ($t -match '^[\p{L}\p{Nd}\p{P}\p{Sc}\p{Sm}\s]+$')
}
function Get-CleanConfidence([string[]]$words) {
    $n = $words.Count
    if ($n -eq 0) { return @{ conf = 0.1; ratio = 0.0; reason = 'no_text' } }
    $clean = 0
    foreach ($w in $words) { if (Test-CleanWord $w) { $clean++ } }
    $ratio = [double]$clean / [double]$n
    $c = [math]::Round([math]::Max(0.1, [math]::Min(0.9, (0.4 + 0.5 * $ratio))), 4)
    $reason = if ($ratio -ge 0.85) { 'clean' } elseif ($ratio -ge 0.5) { 'mixed_legibility' } else { 'low_legibility' }
    return @{ conf = $c; ratio = $ratio; reason = $reason }
}
# Run a child pwsh/powershell entrypoint and return its parsed lifeorch envelope (or $null).
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
    $captureInputsObj = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'input')      -and -not $bound.ContainsKey('InputFile'))    { $InputFile = [string]$p.input }
            if ((Has $p 'language')   -and -not $bound.ContainsKey('Language'))     { $Language = [string]$p.language }
            if ((Has $p 'engine')     -and -not $bound.ContainsKey('Engine'))       { $Engine = [string]$p.engine }
            if ((Has $p 'model')      -and -not $bound.ContainsKey('Model'))        { $Model = [string]$p.model }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'max_review_lines') -and -not $bound.ContainsKey('MaxReviewLines')) { $MaxReviewLines = [int]$p.max_review_lines }
            if ((Has $p 'capture')    -and -not $bound.ContainsKey('Capture'))      { if ([bool]$p.capture) { $Capture = [switch]$true } }
            if  (Has $p 'capture_inputs') { $captureInputsObj = $p.capture_inputs }
            if ((Has $p 'min_image_pixels') -and -not $bound.ContainsKey('MinImagePixels')) { $MinImagePixels = [int]$p.min_image_pixels }
            if ((Has $p 'registry')   -and -not $bound.ContainsKey('Registry'))     { $Registry = [string]$p.registry }
            if ((Has $p 'ocr_worker_path') -and -not $bound.ContainsKey('OcrWorkerPath')) { $OcrWorkerPath = [string]$p.ocr_worker_path }
            if ((Has $p 'powershell51_path') -and -not $bound.ContainsKey('Powershell51Path')) { $Powershell51Path = [string]$p.powershell51_path }
            if ((Has $p 'capture_path') -and -not $bound.ContainsKey('CapturePath')) { $CapturePath = [string]$p.capture_path }
            if ((Has $p 'pwsh_path')  -and -not $bound.ContainsKey('PwshPath'))     { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    if ($bound.ContainsKey('Model') -and -not [string]::IsNullOrWhiteSpace($Model)) { $Engine = $Model }
    if (-not [string]::IsNullOrWhiteSpace($CaptureInputsJson)) { try { $captureInputsObj = $CaptureInputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_capture_inputs'; message='-CaptureInputsJson is not valid JSON'; retryable=$false } } }
    if ([string]::IsNullOrWhiteSpace($Language)) { $Language = '' }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ input=$InputFile; language=$Language; engine=$Engine; confidence_threshold=$ConfidenceThreshold;
        capture=[bool]$Capture; capture_inputs=$captureInputsObj; max_review_lines=$MaxReviewLines }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- resolve engine from registry (decoupled from the gateway wired gate) ----
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
    $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $Engine) } | Select-Object -First 1
    if ($null -eq $m) {
        $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'ocr') } | ForEach-Object { $_.model_id }) -join ', '
        throw [PSCustomObject]@{ code='engine_not_found'; message="ocr engine '$Engine' not in registry. Known ocr: $known"; retryable=$false }
    }
    if ([string](Prop $m 'type' '') -ne 'ocr') { throw [PSCustomObject]@{ code='unsupported_type'; message="ocr.layout runs type=ocr only (engine '$Engine' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
    $engineName = [string](Prop $m 'engine' '')
    if ($engineName -ne 'windows.media.ocr') {
        throw [PSCustomObject]@{ code='engine_not_implemented'; message="engine '$engineName' ($Engine) is declared in the registry but not wired in this MVP; only windows.media.ocr is implemented (Tesseract is a follow-on)"; retryable=$false }
    }

    # ---- resolve input: an explicit file wins; else compose capture.screen ----
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

    # ---- resolve PowerShell 5.1 + the OCR worker ----
    if ([string]::IsNullOrWhiteSpace($Powershell51Path) -or -not (Test-Path -LiteralPath $Powershell51Path -PathType Leaf)) {
        throw [PSCustomObject]@{ code='powershell51_not_found'; message="Windows PowerShell 5.1 not found at '$Powershell51Path' (set -Powershell51Path); required for the Windows.Media.Ocr WinRT worker"; retryable=$false }
    }
    if ([string]::IsNullOrWhiteSpace($OcrWorkerPath)) { $OcrWorkerPath = Join-Path $PSScriptRoot 'ocr_worker.ps1' }
    if (-not (Test-Path -LiteralPath $OcrWorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="ocr_worker.ps1 not found at '$OcrWorkerPath' (set -OcrWorkerPath)"; retryable=$false }
    }

    # ---- run the worker (meta-file hand-off) ----
    $metaPath = Join-Path $invDir 'ocr_meta.json'
    $argsObj = [ordered]@{ image_path=$imagePath; meta_path=$metaPath; language=$Language }
    $argsFile = Join-Path $invDir 'ocr_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($argsObj | ConvertTo-Json -Depth 6), $utf8)

    Write-Diag "worker=$Powershell51Path ocr_worker=$OcrWorkerPath image=$imagePath lang='$Language'"
    $wSw = [System.Diagnostics.Stopwatch]::StartNew()
    $wArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$OcrWorkerPath,'-ArgsFile',$argsFile)
    $wRun = Invoke-ChildSkill $Powershell51Path $wArgs
    $wSw.Stop()
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($wRun.exit)`n" + $wRun.raw + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$wRun.raw; if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='ocr_failed'; message="ocr worker produced no meta (exit $($wRun.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'ocr_failed'); $em = [string](Prop $meta 'error' 'ocr worker failed')
        throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$false }
    }

    # ---- build lines / words / boxes / reading order (engine order) ----
    $imgW = [int](Prop $meta 'image_w' 0); $imgH = [int](Prop $meta 'image_h' 0)
    $angle = Prop $meta 'text_angle' $null
    $maxDim = [int](Prop $meta 'max_image_dimension' 0)
    $engLang = [string](Prop $meta 'engine_language' '')
    $availLangs = @(Prop $meta 'available_languages' @())
    $ocrMs = [int](Prop $meta 'ocr_ms' ([int]$wSw.Elapsed.TotalMilliseconds))

    $linesOut = New-Object System.Collections.Generic.List[object]
    $allWords = New-Object System.Collections.Generic.List[string]
    $lineConfs = New-Object System.Collections.Generic.List[double]
    $idx = 0
    foreach ($ln in @(Prop $meta 'lines' @())) {
        $wordsOut = New-Object System.Collections.Generic.List[object]
        $lineWordTexts = New-Object System.Collections.Generic.List[string]
        $minX = [double]::MaxValue; $minY = [double]::MaxValue; $maxX = [double]::MinValue; $maxY = [double]::MinValue
        foreach ($w in @(Prop $ln 'words' @())) {
            $wt = [string](Prop $w 'text' '')
            $wx = [double](Prop $w 'x' 0); $wy = [double](Prop $w 'y' 0); $ww = [double](Prop $w 'w' 0); $wh = [double](Prop $w 'h' 0)
            $wordsOut.Add([ordered]@{ text=$wt; x=[int][math]::Round($wx); y=[int][math]::Round($wy); width=[int][math]::Round($ww); height=[int][math]::Round($wh) })
            $lineWordTexts.Add($wt); $allWords.Add($wt)
            if ($wx -lt $minX) { $minX = $wx }; if ($wy -lt $minY) { $minY = $wy }
            if (($wx + $ww) -gt $maxX) { $maxX = $wx + $ww }; if (($wy + $wh) -gt $maxY) { $maxY = $wy + $wh }
        }
        $lineText = [string](Prop $ln 'text' '')
        $lc = Get-CleanConfidence $lineWordTexts.ToArray()
        $lineConf = [double]$lc.conf
        if ($lineWordTexts.Count -gt 0) { $lineConfs.Add($lineConf) }
        $box = if ($lineWordTexts.Count -gt 0) {
            [ordered]@{ x=[int][math]::Round($minX); y=[int][math]::Round($minY); width=[int][math]::Round($maxX - $minX); height=[int][math]::Round($maxY - $minY) }
        } else { [ordered]@{ x=0; y=0; width=0; height=0 } }
        $linesOut.Add([ordered]@{ index=$idx; text=$lineText; confidence=$lineConf; low_confidence=($lineConf -lt $ConfidenceThreshold); bounding_rect=$box; words=$wordsOut.ToArray() })
        $idx++
    }
    $lineArr = $linesOut.ToArray()
    $wordCount = $allWords.Count
    $fullText = [string](Prop $meta 'text' '')
    if ([string]::IsNullOrWhiteSpace($fullText)) { $fullText = (($lineArr | ForEach-Object { $_.text }) -join "`n") }

    $oc = Get-CleanConfidence $allWords.ToArray()
    $confidence = [double]$oc.conf
    $overallReason = [string]$oc.reason
    $minLine = $null; if ($lineConfs.Count -gt 0) { $minLine = [math]::Round((($lineConfs.ToArray() | Measure-Object -Minimum).Minimum), 4) }
    $lowLines = @($lineArr | Where-Object { $_.low_confidence }); $lowLineCount = $lowLines.Count

    $result = [ordered]@{
        input = [ordered]@{ path=$imagePath; exists=$true; source=$source; capture=$captureInfo }
        image = [ordered]@{ width=$imgW; height=$imgH; text_angle=$angle }
        engine = [ordered]@{ id=$Engine; name=[string](Prop $m 'name' $Engine); engine=$engineName; recognizer_language=$engLang; available_languages=$availLangs }
        params = [ordered]@{ language=$Language; confidence_threshold=$ConfidenceThreshold }
        text = $fullText
        word_count = $wordCount
        line_count = $lineArr.Count
        lines = $lineArr
        confidence = [ordered]@{ overall=$confidence; min_line=$minLine; low_confidence_lines=$lowLineCount; reason=$overallReason }
        review = [ordered]@{ threshold=$ConfidenceThreshold; flagged_count=0; truncated=$false; queue_path=$null }
        ocr = [ordered]@{ engine_env=$Powershell51Path; runtime_ms=$ocrMs; max_image_dimension=$maxDim }
    }

    $modelProvenance = @(
        [ordered]@{
            model_id = $Engine
            name = [string](Prop $m 'name' $Engine)
            family = [string](Prop $m 'family' 'windows.media.ocr')
            engine = $engineName
            engine_env = $Powershell51Path
            recognizer_language = $engLang
            available_languages = $availLangs
            image_width = $imgW
            image_height = $imgH
            text_angle = $angle
            word_count = $wordCount
            line_count = $lineArr.Count
            runtime_ms = $ocrMs
        }
    )
    Write-Diag "ok words=$wordCount lines=$($lineArr.Count) conf=$confidence ($overallReason) angle=$angle"
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code=[string]$ex.code; message=[string]$ex.message; retryable=[bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) — $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $oj = [ordered]@{ schema='lifeorch.ocr.layout/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            engine=$result.engine; image=$result.image; text=$result.text; word_count=$result.word_count; line_count=$result.line_count;
            lines=$result.lines; confidence=$result.confidence }
        $ojPath = Join-Path $invDir 'ocr.json'
        [System.IO.File]::WriteAllText($ojPath, ($oj | ConvertTo-Json -Depth 20), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# ocr.layout — $($result.engine.id) ($($result.engine.recognizer_language))")
        [void]$mb.AppendLine("image: $($result.input.path)")
        [void]$mb.AppendLine("size: $($result.image.width)x$($result.image.height)  text_angle=$($result.image.text_angle)  words=$($result.word_count)  lines=$($result.line_count)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  min_line=$($result.confidence.min_line)  low_conf_lines=$($result.confidence.low_confidence_lines)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('## text')
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('```')
        [void]$mb.AppendLine([string]$result.text)
        [void]$mb.AppendLine('```')
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('| # | box (x,y,w,h) | conf | text |')
        [void]$mb.AppendLine('|---|---------------|------|------|')
        $rowMax = 300; $rowN = 0
        foreach ($ln in @($result.lines)) {
            if ($rowN -ge $rowMax) { [void]$mb.AppendLine("| … | | | ($($result.line_count - $rowMax) more lines — see ocr.json) |"); break }
            $mark = if ($ln.low_confidence) { '⚠ ' } else { '' }
            $b = $ln.bounding_rect
            $txt = ([string]$ln.text).Replace('|','\|')
            [void]$mb.AppendLine("| $($ln.index) | $($b.x),$($b.y),$($b.width),$($b.height) | $mark$($ln.confidence) | $txt |")
            $rowN++
        }
        $omPath = Join-Path $invDir 'ocr.md'
        [System.IO.File]::WriteAllText($omPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$ojPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$omPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[ocr.layout] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (no-text guard OR low-confidence page; append-only producer) ----
try {
    if ($status -ne 'error' -and $null -ne $result) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $imgPixels = [long]$result.image.width * [long]$result.image.height
        $flagged = 0; $truncated = $false
        if ($result.word_count -eq 0 -and $imgPixels -ge $MinImagePixels) {
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-notext"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='uncategorized'
                confidence=$result.confidence.overall; source_ref="artifact://$invDir/ocr.json"
                weak_result=[ordered]@{ engine=$Engine; image=$result.input.path; width=$result.image.width; height=$result.image.height; note='no text recognized from a non-empty image' }
                requested='verify_no_text'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $flagged++
        }
        elseif ($null -ne $confidence -and $confidence -lt $ConfidenceThreshold) {
            $worst = @($result.lines | Sort-Object { [double]$_.confidence })
            $take = $worst
            if ($worst.Count -gt $MaxReviewLines) { $take = @($worst[0..($MaxReviewLines-1)]); $truncated = $true }
            $lineDetail = @($take | ForEach-Object { [ordered]@{ index=$_.index; text=$_.text; confidence=$_.confidence; bounding_rect=$_.bounding_rect } })
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-ocr"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='low_confidence'
                confidence=$confidence; source_ref="artifact://$invDir/ocr.json"
                weak_result=[ordered]@{ engine=$Engine; image=$result.input.path; word_count=$result.word_count; line_count=$result.line_count; reason=$overallReason; low_confidence_lines=$lowLineCount; lines=$lineDetail }
                requested='verify_ocr'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $flagged++
        }
        if ($flagged -gt 0) {
            $result.review.flagged_count = $flagged
            $result.review.truncated = $truncated
            $result.review.queue_path = $rqPath
            $warnings.Add("flagged OCR result to review queue ($rqPath): confidence $confidence < $ConfidenceThreshold or no text")
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
