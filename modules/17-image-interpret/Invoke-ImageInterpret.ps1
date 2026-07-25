#requires -Version 7.0
<#
.SYNOPSIS
  image.interpret -- local VLM captions / VQA / screen interpretation (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Interprets one image with a local vision-language model and returns a free-text interpretation
  (caption / detailed description / answer to a question / screen summary). Runs the already-staged
  llama.cpp `llama-server` (b8661) in MULTIMODAL mode (-m <vlm.gguf> --mmproj <projector.gguf> ->
  /v1/chat/completions with an OpenAI-style image_url base64 data URI), the same engine model.gateway
  (#7) drives, extended with the projector. Resolves the VLM from the model registry (models.json,
  type=vlm), decoupled from the gateway `wired` gate (like ocr.layout/detect.objects). Binds a loopback
  port + CUDA/VRAM, so parallel_safe:false.

  Fourth image/document perception module. Stochastic/mixed: populates the envelope `confidence` (a
  documented generation-completeness + refusal + non-empty heuristic) + `model_provenance` and routes
  low-confidence / refusal / empty interpretations to the review queue (the seventh producer). Can compose
  capture.screen (#6) as its input source (-Capture "interpret my screen") and image.util (#15) to
  downscale a very large input before sending (-MaxDimension), to bound vision tokens.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes interpret.json,
  interpret.md, interpret_args.json, server.out.log, server.err.log, result.json, stderr.txt (+ capture/...
  when -Capture, image_util/... when -MaxDimension downscales). Exits 0 whenever a valid envelope is produced.

  Test seam: -VlmResponsePath <captured.json> skips the server launch and feeds a captured-real llama-server
  chat-completion response into the same parse/confidence/review/envelope path (the cloud pre-ship gate).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\photo.jpg -Mode describe
  pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\chart.png -Prompt "What is the trend in this chart?"
  pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -Capture -Mode screen
  pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputsJson '{"input":"ui.png","prompt":"What dialog is shown?"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Prompt,
    [string]$Mode,
    [string]$System,
    [string]$Model,
    [string]$Tier,
    [int]$MaxTokens = 512,
    [double]$Temperature = 0.2,
    [double]$TopP = 0.9,
    [int]$Seed = -1,
    [double]$ConfidenceThreshold = 0.5,
    [int]$MaxDimension,
    [switch]$Capture,
    [string]$CaptureInputsJson,
    [int]$Context = 0,
    [int]$GpuLayers = -1,
    [int]$Port = 0,
    [int]$LoadTimeoutSec = 180,
    [string]$Registry,
    [string]$ModelPath,
    [string]$MmprojPath,
    [string]$EnginePath,
    [string]$ImageUtilPath,
    [string]$CapturePath,
    [string]$PythonPath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$VlmResponsePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'image.interpret'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[image.interpret] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Get-FreePort([int]$start) {
    for ($p = $start; $p -lt ($start + 300); $p++) {
        try { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p); $l.Start(); $l.Stop(); return $p } catch { }
    }
    return 0
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
function Get-ImageMime([byte[]]$b) {
    if ($b.Length -ge 4 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'image/png' }
    if ($b.Length -ge 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'image/jpeg' }
    if ($b.Length -ge 6 -and $b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46) { return 'image/gif' }
    if ($b.Length -ge 2 -and $b[0] -eq 0x42 -and $b[1] -eq 0x4D) { return 'image/bmp' }
    if ($b.Length -ge 12 -and $b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46 -and $b[8] -eq 0x57 -and $b[9] -eq 0x45 -and $b[10] -eq 0x42 -and $b[11] -eq 0x50) { return 'image/webp' }
    return 'image/jpeg'
}
# Refusal detector (documented heuristic; not calibrated). Matches common VLM refusal openings.
function Test-Refusal([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return $false }
    return ($t -match "(?i)\bI\s+(?:cannot|can'?t|am unable to|am not able to)\s+(?:assist|help|provide|comply|process|identify|analyze|describe)\b" `
        -or $t -match "(?i)\bas an AI(?:\s+language)?\s+model\b" `
        -or $t -match "(?i)\bI'?m sorry,?\s+but I\s+(?:can'?t|cannot)\b" `
        -or $t -match "(?i)\bI'?m unable to\b")
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null; $captureInputsObj = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
        if ($null -ne $p) {
            if ((Has $p 'input')     -and -not $bound.ContainsKey('InputFile'))   { $InputFile = [string]$p.input }
            if ((Has $p 'prompt')    -and -not $bound.ContainsKey('Prompt'))      { $Prompt = [string]$p.prompt }
            if ((Has $p 'mode')      -and -not $bound.ContainsKey('Mode'))        { $Mode = [string]$p.mode }
            if ((Has $p 'system')    -and -not $bound.ContainsKey('System'))      { $System = [string]$p.system }
            if ((Has $p 'model')     -and -not $bound.ContainsKey('Model'))       { $Model = [string]$p.model }
            if ((Has $p 'tier')      -and -not $bound.ContainsKey('Tier'))        { $Tier = [string]$p.tier }
            if ((Has $p 'max_tokens')  -and -not $bound.ContainsKey('MaxTokens'))   { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'temperature') -and -not $bound.ContainsKey('Temperature')) { $Temperature = [double]$p.temperature }
            if ((Has $p 'top_p')       -and -not $bound.ContainsKey('TopP'))        { $TopP = [double]$p.top_p }
            if ((Has $p 'seed')        -and -not $bound.ContainsKey('Seed'))        { $Seed = [int]$p.seed }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'capture')   -and -not $bound.ContainsKey('Capture'))     { if ([bool]$p.capture) { $Capture = [switch]$true } }
            if  (Has $p 'capture_inputs') { $captureInputsObj = $p.capture_inputs }
            if ((Has $p 'context')     -and -not $bound.ContainsKey('Context'))     { $Context = [int]$p.context }
            if ((Has $p 'gpu_layers')  -and -not $bound.ContainsKey('GpuLayers'))   { $GpuLayers = [int]$p.gpu_layers }
            if ((Has $p 'port')        -and -not $bound.ContainsKey('Port'))        { $Port = [int]$p.port }
            if ((Has $p 'load_timeout_sec') -and -not $bound.ContainsKey('LoadTimeoutSec')) { $LoadTimeoutSec = [int]$p.load_timeout_sec }
            if ((Has $p 'registry')    -and -not $bound.ContainsKey('Registry'))    { $Registry = [string]$p.registry }
            if ((Has $p 'model_path')  -and -not $bound.ContainsKey('ModelPath'))   { $ModelPath = [string]$p.model_path }
            if ((Has $p 'mmproj_path') -and -not $bound.ContainsKey('MmprojPath'))  { $MmprojPath = [string]$p.mmproj_path }
            if ((Has $p 'engine_path') -and -not $bound.ContainsKey('EnginePath'))  { $EnginePath = [string]$p.engine_path }
            if ((Has $p 'image_util_path') -and -not $bound.ContainsKey('ImageUtilPath')) { $ImageUtilPath = [string]$p.image_util_path }
            if ((Has $p 'capture_path') -and -not $bound.ContainsKey('CapturePath')) { $CapturePath = [string]$p.capture_path }
            if ((Has $p 'python_path') -and -not $bound.ContainsKey('PythonPath')) { $PythonPath = [string]$p.python_path }
            if ((Has $p 'pwsh_path')   -and -not $bound.ContainsKey('PwshPath'))    { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
            if ((Has $p 'vlm_response_path') -and -not $bound.ContainsKey('VlmResponsePath')) { $VlmResponsePath = [string]$p.vlm_response_path }
        }
    }
    $hasMaxDim = $bound.ContainsKey('MaxDimension')
    if ($null -ne $p -and (Has $p 'max_dimension') -and -not $hasMaxDim) { $MaxDimension = [int]$p.max_dimension; $hasMaxDim = $true }
    if (-not [string]::IsNullOrWhiteSpace($CaptureInputsJson)) { try { $captureInputsObj = $CaptureInputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_capture_inputs'; message='-CaptureInputsJson is not valid JSON'; retryable=$false } } }
    $seam = (-not [string]::IsNullOrWhiteSpace($VlmResponsePath))

    # ---- resolve mode + effective prompt + system ----
    $promptGiven = -not [string]::IsNullOrWhiteSpace($Prompt)
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        if ($promptGiven) { $Mode = 'vqa' } elseif ($Capture) { $Mode = 'screen' } else { $Mode = 'describe' }
    }
    $Mode = $Mode.ToLowerInvariant()
    if (@('caption','describe','vqa','screen') -notcontains $Mode) {
        throw [PSCustomObject]@{ code='invalid_mode'; message="mode '$Mode' not in caption|describe|vqa|screen"; retryable=$false }
    }
    $defaultPrompts = @{
        caption  = 'Describe this image in one clear sentence.'
        describe = 'Describe this image in detail. Include the main objects, the setting, and any visible text.'
        vqa      = 'Describe this image.'
        screen   = 'This is a screenshot of a computer screen. Describe what application or content is shown, and summarize the key visible text and UI elements.'
    }
    $effPrompt = if ($promptGiven) { $Prompt } else { $defaultPrompts[$Mode] }
    if ($Mode -eq 'vqa' -and -not $promptGiven) { throw [PSCustomObject]@{ code='no_prompt'; message='mode=vqa requires -Prompt (the question)'; retryable=$false } }
    $effSystem = if (-not [string]::IsNullOrWhiteSpace($System)) { $System } else { 'You are a precise visual assistant. Answer based only on what is visible in the image. Be concise and factual.' }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ input=$InputFile; prompt=$effPrompt; mode=$Mode; system=$effSystem; model=$Model; tier=$Tier;
        max_tokens=$MaxTokens; temperature=$Temperature; top_p=$TopP; seed=$Seed;
        max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null }); capture=[bool]$Capture; capture_inputs=$captureInputsObj }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- resolve VLM from registry (decoupled from the gateway wired gate) ----
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
    $modelId = $Model
    if ([string]::IsNullOrWhiteSpace($modelId) -and -not [string]::IsNullOrWhiteSpace($Tier)) {
        if ((Has $reg 'tiers') -and (Has $reg.tiers 'vlm') -and (Has $reg.tiers.vlm $Tier)) { $modelId = [string]$reg.tiers.vlm.$Tier }
        else { throw [PSCustomObject]@{ code='tier_not_found'; message="vlm tier '$Tier' not in registry tiers.vlm"; retryable=$false } }
    }
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        if ((Has $reg 'defaults') -and (Has $reg.defaults 'vlm')) { $modelId = [string]$reg.defaults.vlm }
        else { throw [PSCustomObject]@{ code='no_default_vlm'; message='registry has no defaults.vlm and no -Model/-Tier was given'; retryable=$false } }
    }
    $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $modelId) } | Select-Object -First 1
    if ($null -eq $m) {
        $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'vlm') } | ForEach-Object { $_.model_id }) -join ', '
        throw [PSCustomObject]@{ code='model_not_found'; message="vlm '$modelId' not in registry. Known vlms: $known"; retryable=$false }
    }
    if ([string](Prop $m 'type' '') -ne 'vlm') { throw [PSCustomObject]@{ code='unsupported_type'; message="image.interpret runs type=vlm only (model '$modelId' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
    $engineName = [string](Prop $m 'engine' '')
    if ($engineName -ne 'llama-server') { throw [PSCustomObject]@{ code='engine_not_implemented'; message="engine '$engineName' ($modelId) is declared but not wired in this MVP; only llama-server is implemented"; retryable=$false } }

    # resolve engine exe (override > registry engines.llama-server) + model + mmproj files
    $effEngine = if (-not [string]::IsNullOrWhiteSpace($EnginePath)) { $EnginePath } elseif ((Has $reg 'engines') -and (Has $reg.engines 'llama-server')) { [string]$reg.engines.'llama-server' } else { '' }
    $effModelPath = if (-not [string]::IsNullOrWhiteSpace($ModelPath)) { $ModelPath } else { [string](Prop $m 'path' '') }
    $effMmproj = if (-not [string]::IsNullOrWhiteSpace($MmprojPath)) { $MmprojPath } else { [string](Prop $m 'mmproj' '') }
    if (-not $seam) {
        if ([string]::IsNullOrWhiteSpace($effEngine) -or -not (Test-Path -LiteralPath $effEngine -PathType Leaf)) {
            throw [PSCustomObject]@{ code='engine_not_found'; message="llama-server engine not found: '$effEngine' (set -EnginePath or registry engines.llama-server)"; retryable=$false }
        }
        if ([string]::IsNullOrWhiteSpace($effModelPath) -or -not (Test-Path -LiteralPath $effModelPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='model_file_not_found'; message="VLM model file not found: '$effModelPath' (registry '$modelId'; set -ModelPath)"; retryable=$false }
        }
        if ([string]::IsNullOrWhiteSpace($effMmproj) -or -not (Test-Path -LiteralPath $effMmproj -PathType Leaf)) {
            throw [PSCustomObject]@{ code='mmproj_not_found'; message="VLM mmproj projector not found: '$effMmproj' (registry '$modelId'.mmproj; set -MmprojPath)"; retryable=$false }
        }
        $effEngine = (Resolve-Path -LiteralPath $effEngine).Path
        $effModelPath = (Resolve-Path -LiteralPath $effModelPath).Path
        $effMmproj = (Resolve-Path -LiteralPath $effMmproj).Path
    }
    $ngl = if ($GpuLayers -ge 0) { $GpuLayers } elseif (Has $m 'gpu_layers') { [int]$m.gpu_layers } else { 99 }
    $ctx = if ($Context -gt 0) { $Context } elseif (Has $m 'context') { [int]$m.context } else { 8192 }

    # ---- resolve input image: explicit file wins; else compose capture.screen ----
    $source = 'file'; $captureInfo = $null; $imagePath = $null; $imgW = $null; $imgH = $null
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
        if ((Has $capEnv 'result') -and (Has $capEnv.result 'capture')) { $imgW = [int](Prop $capEnv.result.capture 'image_width' 0); $imgH = [int](Prop $capEnv.result.capture 'image_height' 0) }
        $captureInfo = [ordered]@{ inputs=$capInputs; artifact_dir=$capRoot; image=[ordered]@{ path=$imagePath; width=$imgW; height=$imgH } }
    }
    else {
        throw [PSCustomObject]@{ code='input_not_found'; message='no input image specified (-InputFile / InputsJson.input) and -Capture not set'; retryable=$false }
    }

    # ---- optional downscale via image.util (bound vision tokens on a huge input) ----
    $preprocess = [ordered]@{ max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null }); downscaled=$false; scale_x=1.0; scale_y=1.0; original=$null; artifact_dir=$null }
    $sendImage = $imagePath
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
        $oW = 0; $oH = 0
        if ($null -ne $rz -and (Has $rz 'original')) { $oW = [int](Prop $rz.original 'width' 0); $oH = [int](Prop $rz.original 'height' 0) }
        if ($oW -gt 0) { $imgW = $oW; $imgH = $oH }
        $preprocess.scale_x = $sx; $preprocess.scale_y = $sy; $preprocess.artifact_dir = $iuRoot
        $preprocess.original = [ordered]@{ width=$oW; height=$oH }
        if (($sx -lt 1.0 -or $sy -lt 1.0) -and (Has $iuEnv.result 'outputs')) {
            $outs = @($iuEnv.result.outputs)
            if ($outs.Count -gt 0) {
                $dPath = [string](Prop $outs[0] 'path' '')
                if (-not [string]::IsNullOrWhiteSpace($dPath) -and (Test-Path -LiteralPath $dPath -PathType Leaf)) {
                    $sendImage = (Resolve-Path -LiteralPath $dPath).Path
                    $preprocess.downscaled = $true
                }
            }
        }
        if (-not $preprocess.downscaled) { $warnings.Add("image was not larger than max_dimension=$MaxDimension; sent at full resolution") }
    }

    # ---- build the chat request (base64 image data URI) ----
    $imgBytes = [System.IO.File]::ReadAllBytes($sendImage)
    $mime = Get-ImageMime $imgBytes
    $dataUri = "data:$mime;base64," + [Convert]::ToBase64String($imgBytes)
    $userContent = @(
        [ordered]@{ type='text'; text=$effPrompt },
        [ordered]@{ type='image_url'; image_url=[ordered]@{ url=$dataUri } }
    )
    $msgs = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($effSystem)) { $msgs.Add([ordered]@{ role='system'; content=$effSystem }) }
    $msgs.Add([ordered]@{ role='user'; content=$userContent })
    $bodyObj = [ordered]@{ messages=$msgs.ToArray(); max_tokens=$MaxTokens; temperature=$Temperature; top_p=$TopP; seed=$Seed }

    # ---- get the VLM response: captured-real seam OR live llama-server ----
    $resp = $null; $usePort = $null; $healthMs = $null
    if ($seam) {
        if (-not (Test-Path -LiteralPath $VlmResponsePath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='vlm_response_not_found'; message="captured -VlmResponsePath not found: $VlmResponsePath"; retryable=$false }
        }
        Write-Diag "SEAM: using captured llama-server response $VlmResponsePath (server launch skipped)"
        $resp = (Get-Content -LiteralPath $VlmResponsePath -Raw) | ConvertFrom-Json
    }
    else {
        $usePort = if ($Port -gt 0) { $Port } else { Get-FreePort 8180 }
        if ($usePort -le 0) { throw [PSCustomObject]@{ code='no_free_port'; message='could not find a free loopback port'; retryable=$true } }
        $srvOut = Join-Path $invDir 'server.out.log'; $srvErr = Join-Path $invDir 'server.err.log'
        $srvArgs = @('-m',$effModelPath,'--mmproj',$effMmproj,'-ngl',"$ngl",'-c',"$ctx",'--host','127.0.0.1','--port',"$usePort",'--no-warmup')
        Write-Diag "starting llama-server port=$usePort model=$modelId ngl=$ngl ctx=$ctx"
        $spv = $null; $healthOk = $false; $loadSw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $spv = Start-Process -FilePath $effEngine -ArgumentList $srvArgs -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr -PassThru -WindowStyle Hidden
            $deadline = (Get-Date).AddSeconds($LoadTimeoutSec)
            while ((Get-Date) -lt $deadline) {
                if ($spv.HasExited) { throw [PSCustomObject]@{ code='server_start_failed'; message="llama-server exited during load (code $($spv.ExitCode)); see server.err.log"; retryable=$true } }
                try { $h = Invoke-WebRequest -Uri "http://127.0.0.1:$usePort/health" -UseBasicParsing -TimeoutSec 2; if ($h.StatusCode -eq 200) { $healthOk = $true; break } } catch { }
                Start-Sleep -Milliseconds 600
            }
            $loadSw.Stop(); $healthMs = [int]$loadSw.Elapsed.TotalMilliseconds
            if (-not $healthOk) { throw [PSCustomObject]@{ code='health_timeout'; message="llama-server did not become healthy within $LoadTimeoutSec s"; retryable=$true } }
            $body = $bodyObj | ConvertTo-Json -Depth 12
            try {
                $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$usePort/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec ([Math]::Max(60, $LoadTimeoutSec))
            } catch {
                throw [PSCustomObject]@{ code='completion_failed'; message="chat completion request failed: $($_.Exception.Message)"; retryable=$true }
            }
        }
        finally {
            if ($null -ne $spv) {
                try { & taskkill /PID $spv.Id /T /F 2>$null | Out-Null } catch { }
                try { if (-not $spv.HasExited) { $spv.Kill($true) } } catch { }
                try { $spv.WaitForExit(3000) | Out-Null } catch { }
            }
        }
    }

    # ---- parse the response ----
    $content = ''; $finish = 'unknown'; $usage = $null; $timings = $null
    if ($null -ne $resp -and (Has $resp 'choices')) {
        $ch = @($resp.choices)
        if ($ch.Count -gt 0) {
            $c0 = $ch[0]
            if ((Has $c0 'message') -and (Has $c0.message 'content')) { $content = [string]$c0.message.content }
            if (Has $c0 'finish_reason') { $finish = [string]$c0.finish_reason }
        }
    }
    if (Has $resp 'usage') { $usage = $resp.usage }
    if (Has $resp 'timings') { $timings = $resp.timings }
    $content = ([string]$content).Trim()

    # ---- confidence heuristic (completeness + refusal + non-empty; NOT calibrated) ----
    $isRefusal = Test-Refusal $content
    $confReason = 'ok'
    if ([string]::IsNullOrWhiteSpace($content)) { $confidence = 0.1; $confReason = 'empty'; $warnings.Add('VLM returned empty content') }
    elseif ($isRefusal)          { $confidence = 0.3; $confReason = 'refusal'; $warnings.Add('VLM output looks like a refusal') }
    elseif ($finish -eq 'length') { $confidence = 0.4; $confReason = 'truncated'; $warnings.Add("output truncated at max_tokens=$MaxTokens (finish_reason=length)") }
    elseif ($finish -eq 'stop')   { $confidence = 0.7; $confReason = 'ok' }
    else                          { $confidence = 0.5; $confReason = 'unknown_finish'; $warnings.Add("unrecognized finish_reason '$finish'") }

    $ptok = if ($null -ne $usage -and (Has $usage 'prompt_tokens')) { [int]$usage.prompt_tokens } else { $null }
    $ctok = if ($null -ne $usage -and (Has $usage 'completion_tokens')) { [int]$usage.completion_tokens } else { $null }
    $ttok = if ($null -ne $usage -and (Has $usage 'total_tokens')) { [int]$usage.total_tokens } else { $null }

    $result = [ordered]@{
        input = [ordered]@{ path=$imagePath; exists=$true; source=$source; capture=$captureInfo }
        image = [ordered]@{ width=$imgW; height=$imgH; mime=$mime }
        model = [ordered]@{ id=$modelId; name=[string](Prop $m 'name' $modelId); family=[string](Prop $m 'family' 'vlm'); engine=$engineName; format=[string](Prop $m 'format' 'gguf'); quant=[string](Prop $m 'quant' ''); context=$ctx; gpu_layers=$ngl; path=$effModelPath; mmproj=$effMmproj }
        request = [ordered]@{ mode=$Mode; system=$effSystem; prompt=$effPrompt; max_tokens=$MaxTokens; temperature=$Temperature; top_p=$TopP; seed=$Seed }
        preprocess = $preprocess
        interpretation = [ordered]@{ text=$content; finish_reason=$finish; prompt_tokens=$ptok; completion_tokens=$ctok; total_tokens=$ttok; timings=$timings }
        confidence = [ordered]@{ value=$confidence; reason=$confReason; refusal=$isRefusal }
        review = [ordered]@{ threshold=$ConfidenceThreshold; flagged_count=0; queue_path=$null }
        server = [ordered]@{ mode=$(if ($seam) { 'captured_response' } else { 'live' }); port=$usePort; health_ms=$healthMs; gpu_layers=$ngl; context=$ctx }
    }
    $modelProvenance = @(
        [ordered]@{
            model_id=$modelId; name=[string](Prop $m 'name' $modelId); family=[string](Prop $m 'family' 'vlm')
            version=[string](Prop $m 'version' (Prop $m 'quant' 'unknown')); format=[string](Prop $m 'format' 'gguf')
            engine=$engineName; engine_build=[string](Prop $reg 'engine_build' ''); device=$(if ($seam) { 'captured' } else { 'cuda:0' })
            params=[ordered]@{ gpu_layers=$ngl; context=$ctx; max_tokens=$MaxTokens; temperature=$Temperature; top_p=$TopP; seed=$Seed }
            mode=$Mode; prompt_tokens=$ptok; completion_tokens=$ctok; total_tokens=$ttok
            finish_reason=$finish; timings=$timings; runtime_ms=$healthMs
        }
    )
    Write-Diag "ok model=$modelId mode=$Mode finish=$finish ctok=$ctok conf=$confidence ($confReason) chars=$($content.Length)"
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
        $ij = [ordered]@{ schema='lifeorch.image.interpret/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            model=$result.model; input=$result.input; image=$result.image; request=$result.request; preprocess=$result.preprocess;
            interpretation=$result.interpretation; confidence=$result.confidence }
        $ijPath = Join-Path $invDir 'interpret.json'
        [System.IO.File]::WriteAllText($ijPath, ($ij | ConvertTo-Json -Depth 20), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# image.interpret -- $($result.model.id) ($($result.request.mode))")
        [void]$mb.AppendLine("image: $($result.input.path)  (source=$($result.input.source))")
        $dimStr = if ($null -ne $result.image.width -and $result.image.width) { "$($result.image.width)x$($result.image.height)" } else { 'unknown' }
        [void]$mb.AppendLine("size: $dimStr  mime=$($result.image.mime)")
        [void]$mb.AppendLine("prompt: $($result.request.prompt)")
        [void]$mb.AppendLine("confidence: $($result.confidence.value) ($($result.confidence.reason))  finish=$($result.interpretation.finish_reason)  tokens=$($result.interpretation.completion_tokens)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('## Interpretation')
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine([string]$result.interpretation.text)
        $imPath = Join-Path $invDir 'interpret.md'
        [System.IO.File]::WriteAllText($imPath, $mb.ToString(), $utf8)

        foreach ($a in @([pscustomobject]@{ p=$ijPath; k='json' }, [pscustomobject]@{ p=$imPath; k='markdown' })) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[image.interpret] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (seventh producer: low-confidence / refusal / empty interpretation) ----
try {
    if ($status -ne 'error' -and $null -ne $result) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $cval = [double]$result.confidence.value
        if ($cval -lt $ConfidenceThreshold) {
            $reason = if ($result.confidence.reason -eq 'empty') { 'failed_transform' } elseif ($result.confidence.reason -eq 'refusal') { 'needs_strong_review' } else { 'low_confidence' }
            $preview = [string]$result.interpretation.text; if ($preview.Length -gt 300) { $preview = $preview.Substring(0,300) }
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-interp"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$reason
                confidence=$cval; source_ref="artifact://$invDir/interpret.json"
                weak_result=[ordered]@{ model=$modelId; mode=$Mode; image=$result.input.path; prompt=$effPrompt; finish_reason=$result.interpretation.finish_reason; confidence_reason=$result.confidence.reason; answer_preview=$preview }
                requested='verify_interpretation'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $result.review.flagged_count = 1
            $result.review.queue_path = $rqPath
            $warnings.Add("flagged interpretation to review queue ($rqPath): confidence $cval < $ConfidenceThreshold ($($result.confidence.reason))")
            Write-Diag "review-queued: 1 ($reason) -> $rqPath"
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
