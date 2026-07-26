#requires -Version 7.0
<#
.SYNOPSIS
  gen.video -- local text-to-video generation via AnimateDiff (Life Orchestrator, contract v0.2).
.DESCRIPTION
  Wraps a Python inference worker (video_gen_infer.py, run under the speech venv) that drives a diffusers
  AnimateDiffPipeline -- an SD-1.5 base (reused from gen.image #23) plus an AnimateDiff-Lightning MotionAdapter
  (4-step, fp16, CUDA) -- to turn a text prompt into one short silent clip. Resolves the video-gen model
  (base + adapter + venv python) from the model registry (models.json, type=video-gen, decoupled from the
  gateway wired gate). Produces an MP4 (H.264 via the present ffmpeg) or an animated GIF. Populates confidence
  (a generation-completeness / non-blank + non-static heuristic) + model_provenance, and routes failed / blank /
  static / low-confidence generations to the review queue (the tenth producer).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes video.<mp4|gif> +
  gen.json + gen.md + result.json + stderr.txt + gen_args.json + gen_meta.json + py.log. Exits 0 whenever a
  valid envelope is produced. NOT deterministic (mixed): the diffusion sampler is stochastic, seedable via -Seed.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-GenVideo.ps1 -Prompt "a drone shot over a misty forest at sunrise" -Seed 42
  pwsh -NoProfile -File .\Invoke-GenVideo.ps1 -InputsJson '{"prompt":"a candle flame flickering","format":"gif","num_frames":16}'
#>
[CmdletBinding()]
param(
    [string]$Prompt,
    [string]$NegativePrompt = 'bad quality, worst quality, low resolution, blurry',
    [int]$NumFrames = 16,
    [int]$Width = 512,
    [int]$Height = 512,
    [int]$Steps = 4,
    [double]$Guidance = 1.0,
    [int]$Fps = 8,
    [int]$Seed = -1,
    [string]$Format = 'mp4',
    [double]$ConfidenceThreshold = 0.5,
    [string]$Model = 'video.animatediff-lightning',
    [string]$Tier,
    [string]$Registry,
    [string]$PythonPath,
    [string]$VideoInferPath,
    [string]$FfmpegPath,
    [bool]$Offload = $false,
    [string]$ReviewQueuePath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'gen.video'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[gen.video] $m") }
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
function Resolve-Ffmpeg([string]$explicit) {
    if (-not [string]::IsNullOrWhiteSpace($explicit) -and (Test-Path -LiteralPath $explicit -PathType Leaf)) { return $explicit }
    try { $c = Get-Command ffmpeg -ErrorAction SilentlyContinue; if ($null -ne $c -and $c.Source) { return $c.Source } } catch { }
    foreach ($cand in @(
        'C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe',
        'C:\Windows\System32\ffmpeg.exe')) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) { return $cand }
    }
    return 'ffmpeg'
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validFormats = @('mp4','gif')

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'prompt')          -and -not $bound.ContainsKey('Prompt'))          { $Prompt = [string]$p.prompt }
            if ((Has $p 'negative_prompt')  -and -not $bound.ContainsKey('NegativePrompt'))  { $NegativePrompt = [string]$p.negative_prompt }
            if ((Has $p 'num_frames')       -and -not $bound.ContainsKey('NumFrames'))       { $NumFrames = [int]$p.num_frames }
            if ((Has $p 'width')            -and -not $bound.ContainsKey('Width'))           { $Width = [int]$p.width }
            if ((Has $p 'height')           -and -not $bound.ContainsKey('Height'))          { $Height = [int]$p.height }
            if ((Has $p 'steps')            -and -not $bound.ContainsKey('Steps'))           { $Steps = [int]$p.steps }
            if ((Has $p 'guidance')         -and -not $bound.ContainsKey('Guidance'))        { $Guidance = [double]$p.guidance }
            if ((Has $p 'fps')              -and -not $bound.ContainsKey('Fps'))             { $Fps = [int]$p.fps }
            if ((Has $p 'seed')             -and -not $bound.ContainsKey('Seed'))            { $Seed = [int]$p.seed }
            if ((Has $p 'format')           -and -not $bound.ContainsKey('Format'))          { $Format = [string]$p.format }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'model')            -and -not $bound.ContainsKey('Model'))           { $Model = [string]$p.model }
            if ((Has $p 'tier')             -and -not $bound.ContainsKey('Tier'))            { $Tier = [string]$p.tier }
            if ((Has $p 'offload')          -and -not $bound.ContainsKey('Offload'))         { $Offload = [bool]$p.offload }
            if ((Has $p 'registry')         -and -not $bound.ContainsKey('Registry'))        { $Registry = [string]$p.registry }
            if ((Has $p 'python_path')      -and -not $bound.ContainsKey('PythonPath'))      { $PythonPath = [string]$p.python_path }
            if ((Has $p 'video_infer_path') -and -not $bound.ContainsKey('VideoInferPath'))  { $VideoInferPath = [string]$p.video_infer_path }
            if ((Has $p 'ffmpeg_path')      -and -not $bound.ContainsKey('FfmpegPath'))      { $FfmpegPath = [string]$p.ffmpeg_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
            if ((Has $p 'pwsh_path')        -and -not $bound.ContainsKey('PwshPath'))        { $PwshPath = [string]$p.pwsh_path }
        }
    }
    $fmt = 'mp4'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ prompt=$Prompt; negative_prompt=$NegativePrompt; num_frames=$NumFrames; width=$Width;
        height=$Height; steps=$Steps; guidance=$Guidance; fps=$Fps; seed=$Seed; format=$fmt; model=$Model }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        $status = 'error'; $errorObj = [ordered]@{ code='no_prompt'; message='no prompt specified (-Prompt or InputsJson.prompt)'; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    elseif ($NumFrames -lt 2 -or $NumFrames -gt 64) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_num_frames'; message="num_frames must be 2..64; got ${NumFrames}"; retryable=$false }
    }
    elseif ($Width -lt 128 -or $Width -gt 1024 -or ($Width % 8) -ne 0 -or $Height -lt 128 -or $Height -gt 1024 -or ($Height % 8) -ne 0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_size'; message="width/height must be multiples of 8 in [128,1024]; got ${Width}x${Height}"; retryable=$false }
    }
    elseif ($Steps -lt 1 -or $Steps -gt 12) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_steps'; message="steps must be 1..12 (AnimateDiff-Lightning is 4/8-step); got ${Steps}"; retryable=$false }
    }
    elseif ($Guidance -lt 0.0 -or $Guidance -gt 15.0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_guidance'; message="guidance must be 0..15 (Lightning uses ~1.0); got ${Guidance}"; retryable=$false }
    }
    elseif ($Fps -lt 1 -or $Fps -gt 30) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_fps'; message="fps must be 1..30; got ${Fps}"; retryable=$false }
    }
    else {
        # ---- resolve model registry ----
        if ([string]::IsNullOrWhiteSpace($Registry)) {
            $cand = Join-Path $PSScriptRoot '..\07-model-gateway\models.json'
            if (Test-Path -LiteralPath $cand -PathType Leaf) { $Registry = (Resolve-Path -LiteralPath $cand).Path }
            else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $Registry = Join-Path $root 'modules\07-model-gateway\models.json' } }
        }
        if ([string]::IsNullOrWhiteSpace($Registry) -or -not (Test-Path -LiteralPath $Registry -PathType Leaf)) {
            throw [PSCustomObject]@{ code='registry_not_found'; message="model registry not found: $Registry"; retryable=$false }
        }
        $reg = (Get-Content -LiteralPath $Registry -Raw) | ConvertFrom-Json
        # tier alias resolution (an explicit -Model wins)
        if (-not [string]::IsNullOrWhiteSpace($Tier) -and -not $bound.ContainsKey('Model') -and -not ($InputsJson -and ($InputsJson -match '"model"'))) {
            $tiers = Prop $reg 'tiers'
            $vidTiers = Prop $tiers 'video'
            $mapped = Prop $vidTiers $Tier
            if (-not [string]::IsNullOrWhiteSpace([string]$mapped)) { $Model = [string]$mapped }
            else { throw [PSCustomObject]@{ code='tier_not_found'; message="video tier '$Tier' not in registry tiers.video"; retryable=$false } }
        }
        $models = @(); if (Has $reg 'models') { $models = @($reg.models) }
        $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $Model) } | Select-Object -First 1
        if ($null -eq $m) {
            $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'video-gen') } | ForEach-Object { $_.model_id }) -join ', '
            throw [PSCustomObject]@{ code='model_not_found'; message="video-gen model '$Model' not in registry. Known video-gen: $known"; retryable=$false }
        }
        if ([string](Prop $m 'type' '') -ne 'video-gen') { throw [PSCustomObject]@{ code='unsupported_type'; message="gen.video runs type=video-gen only (model '$Model' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
        if ([string](Prop $m 'engine' '') -ne 'diffusers') { throw [PSCustomObject]@{ code='unsupported_engine'; message="gen.video supports engine=diffusers only (got '$([string](Prop $m 'engine' ''))')"; retryable=$false } }
        $basePath = [string](Prop $m 'base' '')
        if ([string]::IsNullOrWhiteSpace($basePath) -or -not (Test-Path -LiteralPath $basePath -PathType Container)) {
            throw [PSCustomObject]@{ code='base_dir_missing'; message="video-gen base (SD-1.5) directory not found at '$basePath'"; retryable=$true }
        }
        $adapterCkpt = [string](Prop $m 'adapter' '')
        if ([string]::IsNullOrWhiteSpace($adapterCkpt) -or -not (Test-Path -LiteralPath $adapterCkpt -PathType Leaf)) {
            throw [PSCustomObject]@{ code='adapter_missing'; message="video-gen motion adapter checkpoint not found at '$adapterCkpt'"; retryable=$true }
        }
        $dtype = [string](Prop (Prop $m 'params') 'dtype' 'float16')

        # ---- resolve venv python ----
        $python = $PythonPath
        if ([string]::IsNullOrWhiteSpace($python)) { $python = [string](Prop $m 'engine_env' '') }
        if ([string]::IsNullOrWhiteSpace($python) -or -not (Test-Path -LiteralPath $python -PathType Leaf)) {
            throw [PSCustomObject]@{ code='python_not_found'; message="speech venv python not found (set -PythonPath or the registry engine_env). got '$python'"; retryable=$false }
        }

        # ---- resolve inference script + ffmpeg ----
        if ([string]::IsNullOrWhiteSpace($VideoInferPath)) { $VideoInferPath = Join-Path $PSScriptRoot 'video_gen_infer.py' }
        if (-not (Test-Path -LiteralPath $VideoInferPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='infer_script_not_found'; message="video_gen_infer.py not found at '$VideoInferPath' (set -VideoInferPath)"; retryable=$false }
        }
        $ffmpeg = Resolve-Ffmpeg $FfmpegPath
        if ($fmt -eq 'mp4' -and ($ffmpeg -eq 'ffmpeg') -and ($null -eq (Get-Command ffmpeg -ErrorAction SilentlyContinue))) {
            $warnings.Add('ffmpeg not resolved to an explicit path; the worker will try PATH for the mp4 mux')
        }

        # ---- build args + run python worker ----
        $ext = if ($fmt -eq 'gif') { 'gif' } else { 'mp4' }
        $outVideo = Join-Path $invDir ("video.$ext")
        $framesDir = Join-Path $invDir 'frames'
        $metaPath = Join-Path $invDir 'gen_meta.json'
        $argsObj = [ordered]@{
            prompt=$Prompt; negative_prompt=$NegativePrompt; num_frames=$NumFrames; width=$Width; height=$Height;
            steps=$Steps; guidance=$Guidance; seed=$Seed; fps=$Fps; format=$fmt;
            base_path=$basePath; adapter_ckpt=$adapterCkpt; device='cuda'; dtype=$dtype; offload=$Offload;
            ffmpeg_path=$ffmpeg; out_video=$outVideo; frames_dir=$framesDir; meta_path=$metaPath
        }
        $argsFile = Join-Path $invDir 'gen_args.json'
        [System.IO.File]::WriteAllText($argsFile, ($argsObj | ConvertTo-Json -Depth 6), $utf8)

        $pyLog = Join-Path $invDir 'py.log'
        Write-Diag "python=$python model=$Model frames=$NumFrames ${Width}x${Height} steps=$Steps fmt=$fmt -> $outVideo"
        $pySw = [System.Diagnostics.Stopwatch]::StartNew()
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $pyArgs = @($VideoInferPath, $argsFile)
        $pyOut = & $python @pyArgs 2>&1
        $pyExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        $pySw.Stop()
        try { [System.IO.File]::WriteAllText($pyLog, (($pyOut | Out-String)), $utf8) } catch { }

        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            $tail = ($pyOut | Out-String); if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
            throw [PSCustomObject]@{ code='generation_failed'; message="video_gen_infer produced no meta (exit $pyExit): $($tail.Trim())"; retryable=$true }
        }
        $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
        if (-not [bool](Prop $meta 'ok' $false)) {
            $ec = [string](Prop $meta 'error_code' 'generation_failed'); $em = [string](Prop $meta 'error' 'generation failed')
            throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$true }
        }
        if (-not (Test-Path -LiteralPath $outVideo -PathType Leaf)) {
            throw [PSCustomObject]@{ code='generation_failed'; message='worker reported ok but no video was written'; retryable=$true }
        }

        $nFrames = [int](Prop $meta 'num_frames' $NumFrames)
        $vidFmt = [string](Prop $meta 'format' $fmt)
        $codec = [string](Prop $meta 'codec' '')
        $vw = [int](Prop $meta 'width' $Width)
        $vh = [int](Prop $meta 'height' $Height)
        $vfps = [int](Prop $meta 'fps' $Fps)
        $durS = [double](Prop $meta 'duration_s' 0.0)
        $pixelStd = [double](Prop $meta 'pixel_std' 0.0)
        $motionDiff = [double](Prop $meta 'mean_interframe_diff' 0.0)
        $perFrameStdMin = [double](Prop $meta 'per_frame_std_min' 0.0)
        $offloadUsed = [bool](Prop $meta 'offload' $false)
        $loadMs = [int](Prop $meta 'load_ms' 0)
        $genMs = [int](Prop $meta 'gen_ms' 0)
        $pyRuntimeMs = [int](Prop $meta 'runtime_ms' ([int]$pySw.Elapsed.TotalMilliseconds))
        $diffV = [string](Prop $meta 'diffusers' '')
        $torchV = [string](Prop $meta 'torch' '')
        $vramPeak = Prop $meta 'vram_peak_gb'

        # ---- confidence (generation-completeness / non-blank + non-static heuristic; NOT aesthetic quality) ----
        $confReason = 'has_content'
        if ($pixelStd -le 2.0) { $confidence = 0.1; $confReason = 'blank_or_failed' }
        elseif ($pixelStd -lt 8.0) { $confidence = 0.3; $confReason = 'very_low_detail' }
        elseif ($pixelStd -lt 15.0) { $confidence = 0.5; $confReason = 'low_detail' }
        else { $confidence = 0.9; $confReason = 'has_content' }
        # motion guard: an AnimateDiff clip that does not move is a failed video (a still image)
        if ($confidence -gt 0.3 -and $motionDiff -le 0.5) { $confidence = 0.3; $confReason = 'static_no_motion' }
        elseif ($confidence -gt 0.5 -and $motionDiff -lt 1.5) { $confidence = 0.5; $confReason = 'low_motion' }

        $vidBytes = [System.IO.File]::ReadAllBytes($outVideo)

        $result = [ordered]@{
            input = [ordered]@{ prompt=$Prompt; negative_prompt=$NegativePrompt; chars=($Prompt.Length) }
            model = [ordered]@{ id=$Model; name=[string](Prop $m 'name' $Model); family=[string](Prop $m 'family' 'animatediff'); engine='diffusers'; engine_env=$python; device='cuda'; dtype=$dtype; base=$basePath; adapter=$adapterCkpt; path=[string](Prop $m 'path' $basePath) }
            request = [ordered]@{ num_frames=$NumFrames; width=$Width; height=$Height; steps=$Steps; guidance=$Guidance; seed=[int](Prop $meta 'seed' $Seed); fps=$Fps; format=$fmt }
            video = [ordered]@{ path=$outVideo; format=$vidFmt; codec=$codec; width=$vw; height=$vh; num_frames=$nFrames; fps=$vfps; duration_s=$durS; bytes=$vidBytes.Length; sha256=(Get-Sha256Hex $vidBytes) }
            motion = [ordered]@{ mean_abs_interframe_diff=$motionDiff; per_frame_std_min=$perFrameStdMin; pixel_std=$pixelStd }
            confidence = [ordered]@{ overall=$confidence; reason=$confReason }
            review = [ordered]@{ threshold=$ConfidenceThreshold; flagged=$false; queue_path=$null }
            generation = [ordered]@{ load_ms=$loadMs; gen_ms=$genMs; runtime_ms=$pyRuntimeMs; vram_peak_gb=$vramPeak; offload=$offloadUsed; diffusers=$diffV; torch=$torchV }
        }

        $modelProvenance = @(
            [ordered]@{
                model_id = $Model
                name = [string](Prop $m 'name' $Model)
                family = [string](Prop $m 'family' 'animatediff')
                format = [string](Prop $m 'format' 'diffusers+motion-adapter')
                version = [string](Prop $m 'version' '')
                engine = 'diffusers'
                engine_env = $python
                device = 'cuda'
                dtype = $dtype
                params = [ordered]@{ num_frames=$NumFrames; width=$Width; height=$Height; steps=$Steps; guidance=$Guidance; seed=[int](Prop $meta 'seed' $Seed); fps=$Fps; offload=$offloadUsed }
                frames = $nFrames
                video_seconds = $durS
                runtime_ms = $pyRuntimeMs
            }
        )
        Write-Diag "ok frames=$nFrames ${vw}x${vh} std=$pixelStd motion=$motionDiff conf=$confidence offload=$offloadUsed"
    }
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
        $gj = [ordered]@{ schema='lifeorch.gen.video/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); model=$result.model.id; engine='diffusers'; prompt=$result.input.prompt; request=$result.request; video=$result.video; motion=$result.motion; confidence=$result.confidence }
        $gjPath = Join-Path $invDir 'gen.json'
        [System.IO.File]::WriteAllText($gjPath, ($gj | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# gen.video -- $($result.model.id)")
        [void]$mb.AppendLine("video: $($result.video.path)")
        [void]$mb.AppendLine("format=$($result.video.format)  codec=$($result.video.codec)  ${vw}x${vh}  frames=$($result.video.num_frames)  fps=$($result.video.fps)  duration=$($result.video.duration_s)s  bytes=$($result.video.bytes)")
        [void]$mb.AppendLine("sha256=$($result.video.sha256)")
        [void]$mb.AppendLine("request: frames=$($result.request.num_frames)  size=$($result.request.width)x$($result.request.height)  steps=$($result.request.steps)  guidance=$($result.request.guidance)  seed=$($result.request.seed)  fps=$($result.request.fps)")
        [void]$mb.AppendLine("motion: interframe_diff=$($result.motion.mean_abs_interframe_diff)  pixel_std=$($result.motion.pixel_std)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  gen_ms=$($result.generation.gen_ms)  load_ms=$($result.generation.load_ms)  offload=$($result.generation.offload)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("prompt: $($result.input.prompt)")
        $gmPath = Join-Path $invDir 'gen.md'
        [System.IO.File]::WriteAllText($gmPath, $mb.ToString(), $utf8)

        $artKind = @{ 'mp4'='mp4'; 'gif'='gif' }
        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$result.video.path; k=([string]$artKind[[string]$result.video.format]) })
        $artList.Add([pscustomobject]@{ p=$gjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$gmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $kk = $a.k; if ([string]::IsNullOrWhiteSpace($kk)) { $kk = 'video' }
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$kk; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[gen.video] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (failed / blank / static / low-confidence generation; append-only producer, the tenth) ----
try {
    if ($status -ne 'error' -and $null -ne $result -and $null -ne $confidence -and $confidence -lt $ConfidenceThreshold) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $reason = if ($confidence -le 0.15) { 'failed_transform' } else { 'low_confidence' }
        $pprev = [string]$Prompt; if ($pprev.Length -gt 200) { $pprev = $pprev.Substring(0,200) }
        $rqItem = [ordered]@{
            schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-genvid"
            created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$reason
            confidence=$confidence; source_ref="artifact://$invDir/gen.json"
            weak_result=[ordered]@{ model=$Model; prompt_preview=$pprev; num_frames=$result.video.num_frames; pixel_std=$result.motion.pixel_std; interframe_diff=$result.motion.mean_abs_interframe_diff; confidence_reason=$result.confidence.reason }
            requested='verify_generation'; status='open'; resolution=$null; escalated_to=$null
        }
        [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
        $result.review.flagged = $true
        $result.review.queue_path = $rqPath
        $warnings.Add("flagged generation to review queue ($rqPath): confidence $confidence < $ConfidenceThreshold ($($result.confidence.reason))")
        Write-Diag "review-queued: conf=$confidence -> $rqPath"
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
