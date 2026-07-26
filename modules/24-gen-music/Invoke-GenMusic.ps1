#requires -Version 7.0
<#
.SYNOPSIS
  gen.music -- local text-to-music generation via MusicGen (Life Orchestrator, contract v0.2).
.DESCRIPTION
  Wraps a Python inference worker (music_gen_infer.py, run under the speech venv) that drives the transformers
  MusicgenForConditionalGeneration model to turn a text prompt into one short instrumental clip. Resolves the
  music-gen model + venv python from the model registry (models.json, type=music-gen, decoupled from the gateway
  wired gate). Produces a 32 kHz mono WAV; an optional non-wav -Format / -SampleRate is produced by composing
  audio.ingest (#10). Populates confidence (a generation-completeness / non-silent heuristic) + model_provenance,
  and routes failed / silent / low-confidence generations to the review queue (the ninth producer).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes music.<ext> + gen.json +
  gen.md + result.json + stderr.txt + gen_args.json + gen_meta.json + py.log. Exits 0 whenever a valid envelope
  is produced. NOT deterministic (mixed): the MusicGen sampler is stochastic, seedable via -Seed.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-GenMusic.ps1 -Prompt "upbeat 8-bit chiptune, energetic" -Duration 8 -Seed 42
  pwsh -NoProfile -File .\Invoke-GenMusic.ps1 -InputsJson '{"prompt":"calm ambient piano","duration":10,"format":"mp3"}'
#>
[CmdletBinding()]
param(
    [string]$Prompt,
    [double]$Duration = 8.0,
    [double]$Guidance = 3.0,
    [double]$Temperature = 1.0,
    [int]$TopK = 250,
    [double]$TopP = 0.0,
    [int]$Seed = -1,
    [bool]$Normalize = $true,
    [string]$Format = 'wav',
    [int]$SampleRate = 0,
    [double]$ConfidenceThreshold = 0.5,
    [string]$Model = 'music.musicgen-small',
    [string]$Tier,
    [string]$Registry,
    [string]$PythonPath,
    [string]$MusicInferPath,
    [string]$AudioIngestPath,
    [string]$ReviewQueuePath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'gen.music'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[gen.music] $m") }
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
$validFormats = @('wav','mp3','flac','opus','ogg','m4a')
$MAX_DURATION = 30.0

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'prompt')       -and -not $bound.ContainsKey('Prompt'))       { $Prompt = [string]$p.prompt }
            if ((Has $p 'duration')     -and -not $bound.ContainsKey('Duration'))     { $Duration = [double]$p.duration }
            if ((Has $p 'guidance')     -and -not $bound.ContainsKey('Guidance'))     { $Guidance = [double]$p.guidance }
            if ((Has $p 'temperature')  -and -not $bound.ContainsKey('Temperature'))  { $Temperature = [double]$p.temperature }
            if ((Has $p 'top_k')        -and -not $bound.ContainsKey('TopK'))         { $TopK = [int]$p.top_k }
            if ((Has $p 'top_p')        -and -not $bound.ContainsKey('TopP'))         { $TopP = [double]$p.top_p }
            if ((Has $p 'seed')         -and -not $bound.ContainsKey('Seed'))         { $Seed = [int]$p.seed }
            if ((Has $p 'normalize')    -and -not $bound.ContainsKey('Normalize'))    { $Normalize = [bool]$p.normalize }
            if ((Has $p 'format')       -and -not $bound.ContainsKey('Format'))       { $Format = [string]$p.format }
            if ((Has $p 'sample_rate')  -and -not $bound.ContainsKey('SampleRate'))   { $SampleRate = [int]$p.sample_rate }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'model')        -and -not $bound.ContainsKey('Model'))        { $Model = [string]$p.model }
            if ((Has $p 'tier')         -and -not $bound.ContainsKey('Tier'))         { $Tier = [string]$p.tier }
            if ((Has $p 'registry')     -and -not $bound.ContainsKey('Registry'))     { $Registry = [string]$p.registry }
            if ((Has $p 'python_path')  -and -not $bound.ContainsKey('PythonPath'))   { $PythonPath = [string]$p.python_path }
            if ((Has $p 'music_infer_path') -and -not $bound.ContainsKey('MusicInferPath')) { $MusicInferPath = [string]$p.music_infer_path }
            if ((Has $p 'audio_ingest_path') -and -not $bound.ContainsKey('AudioIngestPath')) { $AudioIngestPath = [string]$p.audio_ingest_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
            if ((Has $p 'pwsh_path')    -and -not $bound.ContainsKey('PwshPath'))     { $PwshPath = [string]$p.pwsh_path }
        }
    }
    $fmt = 'wav'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ prompt=$Prompt; duration=$Duration; guidance=$Guidance; temperature=$Temperature;
        top_k=$TopK; top_p=$TopP; seed=$Seed; normalize=$Normalize; format=$fmt; sample_rate=$SampleRate; model=$Model }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        $status = 'error'; $errorObj = [ordered]@{ code='no_prompt'; message='no prompt specified (-Prompt or InputsJson.prompt)'; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    elseif ($Duration -le 0.0 -or $Duration -gt $MAX_DURATION) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_duration'; message="duration must be in (0, $MAX_DURATION] seconds; got ${Duration}"; retryable=$false }
    }
    elseif ($Guidance -lt 0.0 -or $Guidance -gt 15.0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_guidance'; message="guidance must be 0..15; got ${Guidance}"; retryable=$false }
    }
    elseif ($Temperature -lt 0.0 -or $Temperature -gt 2.0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_temperature'; message="temperature must be 0..2; got ${Temperature}"; retryable=$false }
    }
    elseif ($TopK -lt 0 -or $TopP -lt 0.0 -or $TopP -gt 1.0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_sampling'; message="top_k must be >=0 and top_p 0..1; got top_k=${TopK} top_p=${TopP}"; retryable=$false }
    }
    elseif ($SampleRate -ne 0 -and ($SampleRate -lt 8000 -or $SampleRate -gt 192000)) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_sample_rate'; message="sample_rate must be 0 (native) or 8000..192000; got ${SampleRate}"; retryable=$false }
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
            $musTiers = Prop $tiers 'music'
            $mapped = Prop $musTiers $Tier
            if (-not [string]::IsNullOrWhiteSpace([string]$mapped)) { $Model = [string]$mapped }
            else { throw [PSCustomObject]@{ code='tier_not_found'; message="music tier '$Tier' not in registry tiers.music"; retryable=$false } }
        }
        $models = @(); if (Has $reg 'models') { $models = @($reg.models) }
        $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $Model) } | Select-Object -First 1
        if ($null -eq $m) {
            $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'music-gen') } | ForEach-Object { $_.model_id }) -join ', '
            throw [PSCustomObject]@{ code='model_not_found'; message="music-gen model '$Model' not in registry. Known music-gen: $known"; retryable=$false }
        }
        if ([string](Prop $m 'type' '') -ne 'music-gen') { throw [PSCustomObject]@{ code='unsupported_type'; message="gen.music runs type=music-gen only (model '$Model' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
        if ([string](Prop $m 'engine' '') -ne 'transformers') { throw [PSCustomObject]@{ code='unsupported_engine'; message="gen.music supports engine=transformers only (got '$([string](Prop $m 'engine' ''))')"; retryable=$false } }
        $modelPath = [string](Prop $m 'path' '')
        if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Container)) {
            throw [PSCustomObject]@{ code='model_dir_missing'; message="music-gen model directory not found at '$modelPath'"; retryable=$true }
        }
        $dtype = [string](Prop (Prop $m 'params') 'dtype' 'float32')

        # ---- resolve venv python ----
        $python = $PythonPath
        if ([string]::IsNullOrWhiteSpace($python)) { $python = [string](Prop $m 'engine_env' '') }
        if ([string]::IsNullOrWhiteSpace($python) -or -not (Test-Path -LiteralPath $python -PathType Leaf)) {
            throw [PSCustomObject]@{ code='python_not_found'; message="speech venv python not found (set -PythonPath or the registry engine_env). got '$python'"; retryable=$false }
        }

        # ---- resolve inference script ----
        if ([string]::IsNullOrWhiteSpace($MusicInferPath)) { $MusicInferPath = Join-Path $PSScriptRoot 'music_gen_infer.py' }
        if (-not (Test-Path -LiteralPath $MusicInferPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='infer_script_not_found'; message="music_gen_infer.py not found at '$MusicInferPath' (set -MusicInferPath)"; retryable=$false }
        }

        # ---- build args + run python worker ----
        $outWav = Join-Path $invDir 'music.wav'
        $metaPath = Join-Path $invDir 'gen_meta.json'
        $argsObj = [ordered]@{
            prompt=$Prompt; duration=$Duration; guidance=$Guidance; temperature=$Temperature; top_k=$TopK; top_p=$TopP;
            seed=$Seed; normalize=$Normalize; model_path=$modelPath; device='cuda:0'; dtype=$dtype;
            out_wav=$outWav; meta_path=$metaPath
        }
        $argsFile = Join-Path $invDir 'gen_args.json'
        [System.IO.File]::WriteAllText($argsFile, ($argsObj | ConvertTo-Json -Depth 6), $utf8)

        $pyLog = Join-Path $invDir 'py.log'
        Write-Diag "python=$python model=$Model dur=${Duration}s guidance=$Guidance -> $outWav"
        $pySw = [System.Diagnostics.Stopwatch]::StartNew()
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $pyArgs = @($MusicInferPath, $argsFile)
        $pyOut = & $python @pyArgs 2>&1
        $pyExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        $pySw.Stop()
        try { [System.IO.File]::WriteAllText($pyLog, (($pyOut | Out-String)), $utf8) } catch { }

        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            $tail = ($pyOut | Out-String); if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
            throw [PSCustomObject]@{ code='generation_failed'; message="music_gen_infer produced no meta (exit $pyExit): $($tail.Trim())"; retryable=$true }
        }
        $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
        if (-not [bool](Prop $meta 'ok' $false)) {
            $ec = [string](Prop $meta 'error_code' 'generation_failed'); $em = [string](Prop $meta 'error' 'generation failed')
            throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$true }
        }
        if (-not (Test-Path -LiteralPath $outWav -PathType Leaf)) {
            throw [PSCustomObject]@{ code='generation_failed'; message='worker reported ok but no WAV was written'; retryable=$true }
        }

        $nativeSr = [int](Prop $meta 'sr' 32000)
        $samples = [int](Prop $meta 'samples' 0)
        $durS = [double](Prop $meta 'duration_s' 0.0)
        $rms = [double](Prop $meta 'rms' 0.0)
        $peak = [double](Prop $meta 'peak_final' 0.0)
        $normApplied = [bool](Prop $meta 'normalized' $false)
        $maxNewTokens = [int](Prop $meta 'max_new_tokens' 0)
        $loadMs = [int](Prop $meta 'load_ms' 0)
        $genMs = [int](Prop $meta 'gen_ms' 0)
        $pyRuntimeMs = [int](Prop $meta 'runtime_ms' ([int]$pySw.Elapsed.TotalMilliseconds))
        $tfV = [string](Prop $meta 'transformers' '')
        $torchV = [string](Prop $meta 'torch' '')
        $vramPeak = Prop $meta 'vram_peak_gb'

        # ---- optional format/rate conversion via audio.ingest ----
        $finalAudio = $outWav; $finalFmt = 'wav'; $finalSr = $nativeSr; $finalCh = 1; $converted = $false
        $needConvert = (($fmt -ne 'wav') -or (($SampleRate -gt 0) -and ($SampleRate -ne $nativeSr)))
        if ($needConvert) {
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
                $aic = Join-Path $PSScriptRoot '..\10-audio-ingest\Invoke-AudioIngest.ps1'
                if (Test-Path -LiteralPath $aic -PathType Leaf) { $AudioIngestPath = (Resolve-Path -LiteralPath $aic).Path }
                else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $AudioIngestPath = Join-Path $root 'modules\10-audio-ingest\Invoke-AudioIngest.ps1' } }
            }
            $pexe = $PwshPath
            if ([string]::IsNullOrWhiteSpace($pexe) -or -not (Test-Path -LiteralPath $pexe -PathType Leaf)) {
                $pexe = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
            }
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath) -or -not (Test-Path -LiteralPath $AudioIngestPath -PathType Leaf)) {
                $warnings.Add('format/rate conversion requested but audio.ingest not found; returning native 32 kHz WAV')
            } elseif (-not (Test-Path -LiteralPath $pexe -PathType Leaf)) {
                $warnings.Add('format/rate conversion requested but pwsh not found; returning native 32 kHz WAV')
            } else {
                $convRoot = Join-Path $invDir 'convert'
                $aiObj = [ordered]@{ input=$outWav; format=$fmt; channels=1 }
                if ($SampleRate -gt 0) { $aiObj.sample_rate = $SampleRate } else { $aiObj.sample_rate = 0 }
                $aiJson = ($aiObj | ConvertTo-Json -Compress)
                $prevEAP2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                $aiArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AudioIngestPath,'-InputsJson',$aiJson,'-ArtifactRoot',$convRoot)
                $tmpErr = New-TemporaryFile
                $aiOut = & $pexe @aiArgs 2> $tmpErr.FullName
                $ErrorActionPreference = $prevEAP2
                Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
                $aiEnv = $null; try { $aiEnv = ($aiOut | Out-String).Trim() | ConvertFrom-Json } catch { }
                if ($null -ne $aiEnv -and (Has $aiEnv 'status') -and (@('ok','partial') -contains [string]$aiEnv.status) -and (Has $aiEnv 'result')) {
                    $op = [string](Prop $aiEnv.result.output 'path' '')
                    if (-not [string]::IsNullOrWhiteSpace($op) -and (Test-Path -LiteralPath $op -PathType Leaf)) {
                        $finalAudio = (Resolve-Path -LiteralPath $op).Path; $finalFmt = $fmt; $converted = $true
                        $finalSr = [int](Prop $aiEnv.result.output 'sample_rate' $(if ($SampleRate -gt 0) { $SampleRate } else { $nativeSr }))
                        $finalCh = [int](Prop $aiEnv.result.output 'channels' 1)
                    } else { $warnings.Add('audio.ingest conversion produced no output; returning native WAV') }
                } else { $warnings.Add('audio.ingest conversion failed; returning native WAV') }
            }
        }

        # ---- confidence (generation-completeness / non-silent heuristic; NOT musical quality) ----
        $confReason = 'has_content'
        if ($rms -le 0.005) { $confidence = 0.1; $confReason = 'silent_or_failed' }
        elseif ($rms -lt 0.02) { $confidence = 0.3; $confReason = 'very_low_level' }
        elseif ($rms -lt 0.05) { $confidence = 0.5; $confReason = 'low_level' }
        else { $confidence = 0.9; $confReason = 'has_content' }
        # duration-shortfall guard (a truncated/failed generation)
        if ($confidence -gt 0.5 -and $Duration -gt 0 -and $durS -lt (0.5 * $Duration)) {
            $confidence = 0.5; $confReason = 'short_for_request'
        }

        $audioBytes = [System.IO.File]::ReadAllBytes($finalAudio)
        $rtf = $null; if ($durS -gt 0) { $rtf = [math]::Round((($pyRuntimeMs / 1000.0) / $durS), 4) }

        $result = [ordered]@{
            input = [ordered]@{ prompt=$Prompt; chars=($Prompt.Length) }
            model = [ordered]@{ id=$Model; name=[string](Prop $m 'name' $Model); family=[string](Prop $m 'family' 'musicgen'); engine='transformers'; engine_env=$python; device='cuda:0'; dtype=$dtype; path=$modelPath }
            request = [ordered]@{ duration_s=$Duration; guidance=$Guidance; temperature=$Temperature; top_k=$TopK; top_p=$TopP; seed=[int](Prop $meta 'seed' $Seed); max_new_tokens=$maxNewTokens; format=$fmt; sample_rate=$SampleRate }
            audio = [ordered]@{ path=$finalAudio; format=$finalFmt; sample_rate=$finalSr; channels=$finalCh; samples=$samples; duration_s=$durS; bytes=$audioBytes.Length; sha256=(Get-Sha256Hex $audioBytes); rms=$rms; peak=$peak; normalized=$normApplied; native_sample_rate=$nativeSr; converted=$converted }
            confidence = [ordered]@{ overall=$confidence; reason=$confReason }
            review = [ordered]@{ threshold=$ConfidenceThreshold; flagged=$false; queue_path=$null }
            generation = [ordered]@{ load_ms=$loadMs; gen_ms=$genMs; runtime_ms=$pyRuntimeMs; real_time_factor=$rtf; vram_peak_gb=$vramPeak; transformers=$tfV; torch=$torchV }
        }

        $modelProvenance = @(
            [ordered]@{
                model_id = $Model
                name = [string](Prop $m 'name' $Model)
                family = [string](Prop $m 'family' 'musicgen')
                format = [string](Prop $m 'format' 'transformers-dir')
                version = [string](Prop $m 'version' '')
                engine = 'transformers'
                engine_env = $python
                device = 'cuda:0'
                dtype = $dtype
                params = [ordered]@{ duration_s=$Duration; guidance=$Guidance; temperature=$Temperature; top_k=$TopK; top_p=$TopP; seed=[int](Prop $meta 'seed' $Seed); max_new_tokens=$maxNewTokens }
                sample_rate = $nativeSr
                audio_samples = $samples
                audio_seconds = $durS
                runtime_ms = $pyRuntimeMs
                real_time_factor = $rtf
            }
        )
        Write-Diag "ok dur=$durS sr=$nativeSr rms=$rms conf=$confidence rtf=$rtf converted=$converted"
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
        $gj = [ordered]@{ schema='lifeorch.gen.music/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); model=$result.model.id; engine='transformers'; prompt=$result.input.prompt; request=$result.request; audio=$result.audio; confidence=$result.confidence }
        $gjPath = Join-Path $invDir 'gen.json'
        [System.IO.File]::WriteAllText($gjPath, ($gj | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# gen.music -- $($result.model.id)")
        [void]$mb.AppendLine("audio: $($result.audio.path)")
        [void]$mb.AppendLine("format=$($result.audio.format)  sample_rate=$($result.audio.sample_rate)  channels=$($result.audio.channels)  duration=$($result.audio.duration_s)s  bytes=$($result.audio.bytes)")
        [void]$mb.AppendLine("sha256=$($result.audio.sha256)")
        [void]$mb.AppendLine("request: duration=$($result.request.duration_s)s  guidance=$($result.request.guidance)  temperature=$($result.request.temperature)  top_k=$($result.request.top_k)  top_p=$($result.request.top_p)  seed=$($result.request.seed)  tokens=$($result.request.max_new_tokens)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  rms=$($result.audio.rms)  peak=$($result.audio.peak)  gen_ms=$($result.generation.gen_ms)  load_ms=$($result.generation.load_ms)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("prompt: $($result.input.prompt)")
        $gmPath = Join-Path $invDir 'gen.md'
        [System.IO.File]::WriteAllText($gmPath, $mb.ToString(), $utf8)

        $artKind = @{ 'wav'='wav'; 'mp3'='mp3'; 'flac'='flac'; 'opus'='opus'; 'ogg'='ogg'; 'm4a'='m4a' }
        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$result.audio.path; k=([string]$artKind[[string]$result.audio.format]) })
        $artList.Add([pscustomobject]@{ p=$gjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$gmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $kk = $a.k; if ([string]::IsNullOrWhiteSpace($kk)) { $kk = 'audio' }
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$kk; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[gen.music] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (failed / silent / low-confidence generation; append-only producer, the ninth) ----
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
            schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-genmus"
            created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$reason
            confidence=$confidence; source_ref="artifact://$invDir/gen.json"
            weak_result=[ordered]@{ model=$Model; prompt_preview=$pprev; duration_s=$result.audio.duration_s; rms=$result.audio.rms; confidence_reason=$result.confidence.reason }
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
