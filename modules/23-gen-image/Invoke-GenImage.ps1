#requires -Version 7.0
<#
.SYNOPSIS
  gen.image -- local text-to-image generation via Stable Diffusion (Life Orchestrator, contract v0.2).
.DESCRIPTION
  Wraps a Python inference worker (gen_image_infer.py, run under the speech venv) that drives the diffusers
  StableDiffusionPipeline to turn a text prompt into one image. Resolves the image-gen model + venv python
  from the model registry (models.json, type=image-gen, decoupled from the gateway wired gate). Produces one
  PNG/JPG/WEBP image. Populates confidence (a generation-completeness / non-blank heuristic) + model_provenance,
  and routes failed / blank / low-confidence generations to the review queue (the eighth producer).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes image.<ext> + gen.json +
  gen.md + result.json + stderr.txt + gen_args.json + gen_meta.json + py.log. Exits 0 whenever a valid envelope
  is produced. NOT deterministic (mixed): the diffusion sampler is stochastic, seedable via -Seed.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-GenImage.ps1 -Prompt "a red apple on a wooden table, studio photo" -Seed 42
  pwsh -NoProfile -File .\Invoke-GenImage.ps1 -InputsJson '{"prompt":"a cozy reading nook","width":512,"height":768,"steps":25}'
#>
[CmdletBinding()]
param(
    [string]$Prompt,
    [string]$NegativePrompt,
    [int]$Width = 512,
    [int]$Height = 512,
    [int]$Steps = 20,
    [double]$Guidance = 7.5,
    [int]$Seed = -1,
    [string]$Scheduler = 'dpm++',
    [string]$Format = 'png',
    [double]$ConfidenceThreshold = 0.5,
    [string]$Model = 'image.sd15',
    [string]$Tier,
    [string]$Registry,
    [string]$PythonPath,
    [string]$GenInferPath,
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'gen.image'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[gen.image] $m") }
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

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validFormats = @('png','jpg','jpeg','webp')
$validSchedulers = @('dpm++','euler','euler_a','ddim')
$extByFmt = @{ 'png'='png'; 'jpg'='jpg'; 'jpeg'='jpg'; 'webp'='webp' }
$MAX_PIXELS = 1024 * 1024

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'prompt')          -and -not $bound.ContainsKey('Prompt'))          { $Prompt = [string]$p.prompt }
            if ((Has $p 'negative_prompt') -and -not $bound.ContainsKey('NegativePrompt'))  { $NegativePrompt = [string]$p.negative_prompt }
            if ((Has $p 'width')           -and -not $bound.ContainsKey('Width'))           { $Width = [int]$p.width }
            if ((Has $p 'height')          -and -not $bound.ContainsKey('Height'))          { $Height = [int]$p.height }
            if ((Has $p 'steps')           -and -not $bound.ContainsKey('Steps'))           { $Steps = [int]$p.steps }
            if ((Has $p 'guidance')        -and -not $bound.ContainsKey('Guidance'))        { $Guidance = [double]$p.guidance }
            if ((Has $p 'seed')            -and -not $bound.ContainsKey('Seed'))            { $Seed = [int]$p.seed }
            if ((Has $p 'scheduler')       -and -not $bound.ContainsKey('Scheduler'))       { $Scheduler = [string]$p.scheduler }
            if ((Has $p 'format')          -and -not $bound.ContainsKey('Format'))          { $Format = [string]$p.format }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'model')           -and -not $bound.ContainsKey('Model'))           { $Model = [string]$p.model }
            if ((Has $p 'tier')            -and -not $bound.ContainsKey('Tier'))            { $Tier = [string]$p.tier }
            if ((Has $p 'registry')        -and -not $bound.ContainsKey('Registry'))        { $Registry = [string]$p.registry }
            if ((Has $p 'python_path')     -and -not $bound.ContainsKey('PythonPath'))      { $PythonPath = [string]$p.python_path }
            if ((Has $p 'gen_infer_path')  -and -not $bound.ContainsKey('GenInferPath'))    { $GenInferPath = [string]$p.gen_infer_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $fmt = 'png'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }
    $sch = 'dpm++'; if (-not [string]::IsNullOrWhiteSpace($Scheduler)) { $sch = $Scheduler.Trim().ToLowerInvariant() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ prompt=$Prompt; negative_prompt=$NegativePrompt; width=$Width; height=$Height;
        steps=$Steps; guidance=$Guidance; seed=$Seed; scheduler=$sch; format=$fmt; model=$Model }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        $status = 'error'; $errorObj = [ordered]@{ code='no_prompt'; message='no prompt specified (-Prompt or InputsJson.prompt)'; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    elseif ($validSchedulers -notcontains $sch) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_scheduler'; message="scheduler must be one of: $($validSchedulers -join ', '); got '$sch'"; retryable=$false }
    }
    elseif ($Width -lt 128 -or $Width -gt 1024 -or $Height -lt 128 -or $Height -gt 1024 -or ($Width % 8 -ne 0) -or ($Height % 8 -ne 0)) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_dimensions'; message="width/height must be multiples of 8 in [128,1024]; got ${Width}x${Height}"; retryable=$false }
    }
    elseif (($Width * $Height) -gt $MAX_PIXELS) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_dimensions'; message="width*height must be <= $MAX_PIXELS ($([int][math]::Sqrt($MAX_PIXELS)) sq); got $($Width*$Height)"; retryable=$false }
    }
    elseif ($Steps -lt 1 -or $Steps -gt 150) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_steps'; message="steps must be 1..150; got $Steps"; retryable=$false }
    }
    elseif ($Guidance -lt 0.0 -or $Guidance -gt 30.0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_guidance'; message="guidance must be 0..30; got $Guidance"; retryable=$false }
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
            $imgTiers = Prop $tiers 'image'
            $mapped = Prop $imgTiers $Tier
            if (-not [string]::IsNullOrWhiteSpace([string]$mapped)) { $Model = [string]$mapped }
            else { throw [PSCustomObject]@{ code='tier_not_found'; message="image tier '$Tier' not in registry tiers.image"; retryable=$false } }
        }
        $models = @(); if (Has $reg 'models') { $models = @($reg.models) }
        $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $Model) } | Select-Object -First 1
        if ($null -eq $m) {
            $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'image-gen') } | ForEach-Object { $_.model_id }) -join ', '
            throw [PSCustomObject]@{ code='model_not_found'; message="image-gen model '$Model' not in registry. Known image-gen: $known"; retryable=$false }
        }
        if ([string](Prop $m 'type' '') -ne 'image-gen') { throw [PSCustomObject]@{ code='unsupported_type'; message="gen.image runs type=image-gen only (model '$Model' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
        if ([string](Prop $m 'engine' '') -ne 'diffusers') { throw [PSCustomObject]@{ code='unsupported_engine'; message="gen.image supports engine=diffusers only (got '$([string](Prop $m 'engine' ''))')"; retryable=$false } }
        $modelPath = [string](Prop $m 'path' '')
        if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Container)) {
            throw [PSCustomObject]@{ code='model_dir_missing'; message="image-gen model directory not found at '$modelPath'"; retryable=$true }
        }
        $variant = [string](Prop (Prop $m 'params') 'variant' 'fp16')
        # pipeline family + VRAM strategy (SD 3.5 Medium tier). Absent params -> the SD1.5 legacy path
        # (pipeline_family 'sd'), so image.sd15 is byte-for-byte unchanged.
        $pipeFamily = [string](Prop (Prop $m 'params') 'pipeline' 'sd')
        $offloadMode = [string](Prop (Prop $m 'params') 'offload' '')
        $vaeTiling = [bool](Prop (Prop $m 'params') 'vae_tiling' $false)
        $dropT5 = [bool](Prop (Prop $m 'params') 'drop_t5' $false)

        # ---- resolve venv python ----
        $python = $PythonPath
        if ([string]::IsNullOrWhiteSpace($python)) { $python = [string](Prop $m 'engine_env' '') }
        if ([string]::IsNullOrWhiteSpace($python) -or -not (Test-Path -LiteralPath $python -PathType Leaf)) {
            throw [PSCustomObject]@{ code='python_not_found'; message="speech venv python not found (set -PythonPath or the registry engine_env). got '$python'"; retryable=$false }
        }

        # ---- resolve inference script ----
        if ([string]::IsNullOrWhiteSpace($GenInferPath)) { $GenInferPath = Join-Path $PSScriptRoot 'gen_image_infer.py' }
        if (-not (Test-Path -LiteralPath $GenInferPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='infer_script_not_found'; message="gen_image_infer.py not found at '$GenInferPath' (set -GenInferPath)"; retryable=$false }
        }

        # ---- build args + run python worker ----
        $ext = $extByFmt[$fmt]
        $outImage = Join-Path $invDir ("image." + $ext)
        $metaPath = Join-Path $invDir 'gen_meta.json'
        $argsObj = [ordered]@{
            prompt=$Prompt; negative_prompt=$NegativePrompt; width=$Width; height=$Height; steps=$Steps;
            guidance=$Guidance; seed=$Seed; scheduler=$sch; model_path=$modelPath; device='cuda:0';
            dtype='float16'; variant=$variant; format=$fmt; out_image=$outImage; meta_path=$metaPath
            pipeline_family=$pipeFamily; offload=$offloadMode; vae_tiling=$vaeTiling; drop_t5=$dropT5
        }
        $argsFile = Join-Path $invDir 'gen_args.json'
        [System.IO.File]::WriteAllText($argsFile, ($argsObj | ConvertTo-Json -Depth 6), $utf8)

        $pyLog = Join-Path $invDir 'py.log'
        Write-Diag "python=$python model=$Model ${Width}x${Height} steps=$Steps sched=$sch -> $outImage"
        $pySw = [System.Diagnostics.Stopwatch]::StartNew()
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $pyArgs = @($GenInferPath, $argsFile)
        $pyOut = & $python @pyArgs 2>&1
        $pyExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        $pySw.Stop()
        try { [System.IO.File]::WriteAllText($pyLog, (($pyOut | Out-String)), $utf8) } catch { }

        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            $tail = ($pyOut | Out-String); if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
            throw [PSCustomObject]@{ code='generation_failed'; message="gen_image_infer produced no meta (exit $pyExit): $($tail.Trim())"; retryable=$true }
        }
        $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
        if (-not [bool](Prop $meta 'ok' $false)) {
            $ec = [string](Prop $meta 'error_code' 'generation_failed'); $em = [string](Prop $meta 'error' 'generation failed')
            throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$true }
        }
        if (-not (Test-Path -LiteralPath $outImage -PathType Leaf)) {
            throw [PSCustomObject]@{ code='generation_failed'; message='worker reported ok but no image was written'; retryable=$true }
        }

        $imgW = [int](Prop $meta 'width' $Width)
        $imgH = [int](Prop $meta 'height' $Height)
        $imgMode = [string](Prop $meta 'mode' 'RGB')
        $actualSeed = [int](Prop $meta 'seed' $Seed)
        $pixelStd = [double](Prop $meta 'pixel_std' 0.0)
        $pixelMean = [double](Prop $meta 'pixel_mean' 0.0)
        $loadMs = [int](Prop $meta 'load_ms' 0)
        $genMs = [int](Prop $meta 'gen_ms' 0)
        $pyRuntimeMs = [int](Prop $meta 'runtime_ms' ([int]$pySw.Elapsed.TotalMilliseconds))
        $diffV = [string](Prop $meta 'diffusers' '')
        $torchV = [string](Prop $meta 'torch' '')
        $vramPeak = Prop $meta 'vram_peak_gb'
        # what the worker actually ran (SD3 uses a native flow-match scheduler + a CPU-offload mode)
        $pipeUsed = [string](Prop $meta 'pipeline_family' $pipeFamily)
        $offloadUsed = [string](Prop $meta 'offload' $offloadMode)
        $schedUsed = [string](Prop $meta 'scheduler' $sch)
        $t5Used = [string](Prop $meta 't5' '')

        # ---- confidence (generation-completeness / non-blank heuristic; NOT aesthetic quality) ----
        $confReason = 'has_content'
        if ($pixelStd -le 2.0) { $confidence = 0.1; $confReason = 'blank_or_uniform' }
        elseif ($pixelStd -lt 8.0) { $confidence = 0.3; $confReason = 'very_low_detail' }
        elseif ($pixelStd -lt 15.0) { $confidence = 0.5; $confReason = 'low_detail' }
        else { $confidence = 0.9; $confReason = 'has_content' }

        $imgBytes = [System.IO.File]::ReadAllBytes($outImage)

        $result = [ordered]@{
            input = [ordered]@{ prompt=$Prompt; negative_prompt=$NegativePrompt; chars=($Prompt.Length) }
            model = [ordered]@{ id=$Model; name=[string](Prop $m 'name' $Model); family=[string](Prop $m 'family' 'stable-diffusion'); engine='diffusers'; engine_env=$python; device='cuda:0'; dtype='float16'; path=$modelPath }
            request = [ordered]@{ width=$imgW; height=$imgH; steps=$Steps; guidance=$Guidance; seed=$actualSeed; scheduler=$sch; format=$fmt }
            image = [ordered]@{ path=(Resolve-Path -LiteralPath $outImage).Path; format=$fmt; width=$imgW; height=$imgH; mode=$imgMode; bytes=$imgBytes.Length; sha256=(Get-Sha256Hex $imgBytes); pixel_std=$pixelStd; pixel_mean=$pixelMean }
            confidence = [ordered]@{ overall=$confidence; reason=$confReason }
            review = [ordered]@{ threshold=$ConfidenceThreshold; flagged=$false; queue_path=$null }
            generation = [ordered]@{ load_ms=$loadMs; gen_ms=$genMs; runtime_ms=$pyRuntimeMs; vram_peak_gb=$vramPeak; diffusers=$diffV; torch=$torchV; pipeline_family=$pipeUsed; offload=$offloadUsed; actual_scheduler=$schedUsed; t5=$t5Used }
        }

        $modelProvenance = @(
            [ordered]@{
                model_id = $Model
                name = [string](Prop $m 'name' $Model)
                family = [string](Prop $m 'family' 'stable-diffusion')
                format = [string](Prop $m 'format' 'diffusers')
                version = [string](Prop $m 'version' '')
                engine = 'diffusers'
                engine_env = $python
                device = 'cuda:0'
                dtype = 'float16'
                params = [ordered]@{ width=$imgW; height=$imgH; steps=$Steps; guidance=$Guidance; seed=$actualSeed; scheduler=$sch }
                image_pixels = ($imgW * $imgH)
                runtime_ms = $pyRuntimeMs
            }
        )
        Write-Diag "ok ${imgW}x${imgH} seed=$actualSeed std=$pixelStd conf=$confidence gen_ms=$genMs"
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
        $gj = [ordered]@{ schema='lifeorch.gen.image/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); model=$result.model.id; engine='diffusers'; prompt=$result.input.prompt; request=$result.request; image=$result.image; confidence=$result.confidence }
        $gjPath = Join-Path $invDir 'gen.json'
        [System.IO.File]::WriteAllText($gjPath, ($gj | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# gen.image -- $($result.model.id)")
        [void]$mb.AppendLine("image: $($result.image.path)")
        [void]$mb.AppendLine("size=$($result.image.width)x$($result.image.height)  format=$($result.image.format)  mode=$($result.image.mode)  bytes=$($result.image.bytes)  sha256=$($result.image.sha256)")
        [void]$mb.AppendLine("request: steps=$($result.request.steps)  guidance=$($result.request.guidance)  seed=$($result.request.seed)  scheduler=$($result.request.scheduler)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  pixel_std=$($result.image.pixel_std)  gen_ms=$($result.generation.gen_ms)  load_ms=$($result.generation.load_ms)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("prompt: $($result.input.prompt)")
        if (-not [string]::IsNullOrWhiteSpace([string]$result.input.negative_prompt)) { [void]$mb.AppendLine("negative: $($result.input.negative_prompt)") }
        $gmPath = Join-Path $invDir 'gen.md'
        [System.IO.File]::WriteAllText($gmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$result.image.path; k=$result.image.format })
        $artList.Add([pscustomobject]@{ p=$gjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$gmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[gen.image] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (failed / blank / low-confidence generation; append-only producer, the eighth) ----
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
            schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-genimg"
            created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$reason
            confidence=$confidence; source_ref="artifact://$invDir/gen.json"
            weak_result=[ordered]@{ model=$Model; prompt_preview=$pprev; width=$result.image.width; height=$result.image.height; pixel_std=$result.image.pixel_std; confidence_reason=$result.confidence.reason }
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
