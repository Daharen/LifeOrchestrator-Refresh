#requires -Version 7.0
<#
.SYNOPSIS
  speech.tts — local text-to-speech synthesis via Qwen3-TTS CustomVoice (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Wraps a Python inference worker (tts_infer.py, run under the speech venv) that drives
  qwen_tts.Qwen3TTSModel.generate_custom_voice to turn text into a speech WAV. Resolves the TTS model + venv
  python from the model registry (models.json). Produces a 24 kHz mono PCM16 WAV (optionally re-encoded to a
  requested format/rate via audio.ingest). First skill to drive a Python model; populates confidence
  (synthesis-completeness heuristic) + model_provenance, and routes failed/too-short synthesis to the review queue.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes speech.wav + tts.json +
  tts.md + result.json + stderr.txt + py.log (+ convert/… when re-encoding). Exits 0 whenever a valid envelope
  is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -Text "Hello from Life Orchestrator." -Speaker Ryan
  pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -InputsJson '{"text":"Good morning.","speaker":"Aiden","instruct":"Cheerful tone.","format":"mp3"}'
#>
[CmdletBinding()]
param(
    [string]$Text,
    [string]$Speaker = 'Ryan',
    [string]$Language = 'English',
    [string]$Instruct,
    [int]$Seed = -1,
    [string]$Dtype = 'bfloat16',
    [int]$SampleRate = 0,
    [string]$Format = 'wav',
    [int]$MaxNewTokens = 0,
    [double]$ConfidenceThreshold = 0.5,
    [string]$Model = 'tts.weak.qwen3-0p6b',
    [string]$Registry,
    [string]$PythonPath,
    [string]$TtsInferPath,
    [string]$AudioIngestPath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'speech.tts'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[speech.tts] $m") }
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

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'text')       -and -not $bound.ContainsKey('Text'))       { $Text = [string]$p.text }
            if ((Has $p 'speaker')    -and -not $bound.ContainsKey('Speaker'))    { $Speaker = [string]$p.speaker }
            if ((Has $p 'language')   -and -not $bound.ContainsKey('Language'))   { $Language = [string]$p.language }
            if ((Has $p 'instruct')   -and -not $bound.ContainsKey('Instruct'))   { $Instruct = [string]$p.instruct }
            if ((Has $p 'seed')       -and -not $bound.ContainsKey('Seed'))       { $Seed = [int]$p.seed }
            if ((Has $p 'dtype')      -and -not $bound.ContainsKey('Dtype'))      { $Dtype = [string]$p.dtype }
            if ((Has $p 'sample_rate')-and -not $bound.ContainsKey('SampleRate')) { $SampleRate = [int]$p.sample_rate }
            if ((Has $p 'format')     -and -not $bound.ContainsKey('Format'))     { $Format = [string]$p.format }
            if ((Has $p 'max_new_tokens') -and -not $bound.ContainsKey('MaxNewTokens')) { $MaxNewTokens = [int]$p.max_new_tokens }
            if ((Has $p 'confidence_threshold') -and -not $bound.ContainsKey('ConfidenceThreshold')) { $ConfidenceThreshold = [double]$p.confidence_threshold }
            if ((Has $p 'model')      -and -not $bound.ContainsKey('Model'))      { $Model = [string]$p.model }
            if ((Has $p 'registry')   -and -not $bound.ContainsKey('Registry'))   { $Registry = [string]$p.registry }
            if ((Has $p 'python_path')-and -not $bound.ContainsKey('PythonPath')) { $PythonPath = [string]$p.python_path }
            if ((Has $p 'tts_infer_path') -and -not $bound.ContainsKey('TtsInferPath')) { $TtsInferPath = [string]$p.tts_infer_path }
            if ((Has $p 'audio_ingest_path') -and -not $bound.ContainsKey('AudioIngestPath')) { $AudioIngestPath = [string]$p.audio_ingest_path }
            if ((Has $p 'pwsh_path')  -and -not $bound.ContainsKey('PwshPath'))   { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $fmt = 'wav'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }
    $dtype = 'bfloat16'; if (-not [string]::IsNullOrWhiteSpace($Dtype)) { $dtype = $Dtype.Trim().ToLowerInvariant() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ text=$Text; speaker=$Speaker; language=$Language; instruct=$Instruct; seed=$Seed;
        dtype=$dtype; sample_rate=$SampleRate; format=$fmt; max_new_tokens=$MaxNewTokens; model=$Model }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $status = 'error'; $errorObj = [ordered]@{ code='no_text'; message='no text specified (-Text or InputsJson.text)'; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    elseif (@('bfloat16','float16','float32') -notcontains $dtype) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_dtype'; message="dtype must be bfloat16|float16|float32; got '$dtype'"; retryable=$false }
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
        $models = @(); if (Has $reg 'models') { $models = @($reg.models) }
        $m = $models | Where-Object { (Has $_ 'model_id') -and ($_.model_id -eq $Model) } | Select-Object -First 1
        if ($null -eq $m) {
            $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'tts') } | ForEach-Object { $_.model_id }) -join ', '
            throw [PSCustomObject]@{ code='model_not_found'; message="tts model '$Model' not in registry. Known tts: $known"; retryable=$false }
        }
        if ([string](Prop $m 'type' '') -ne 'tts') { throw [PSCustomObject]@{ code='unsupported_type'; message="speech.tts runs type=tts only (model '$Model' is type=$([string](Prop $m 'type' '')))"; retryable=$false } }
        if ([string](Prop $m 'engine' '') -ne 'transformers') { throw [PSCustomObject]@{ code='unsupported_engine'; message="speech.tts supports engine=transformers only (got '$([string](Prop $m 'engine' ''))')"; retryable=$false } }
        $modelPath = [string](Prop $m 'path' '')
        if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Container)) {
            throw [PSCustomObject]@{ code='model_dir_missing'; message="tts model directory not found at '$modelPath'"; retryable=$true }
        }

        # ---- resolve venv python ----
        $python = $PythonPath
        if ([string]::IsNullOrWhiteSpace($python)) { $python = [string](Prop $m 'engine_env' '') }
        if ([string]::IsNullOrWhiteSpace($python) -or -not (Test-Path -LiteralPath $python -PathType Leaf)) {
            throw [PSCustomObject]@{ code='python_not_found'; message="speech venv python not found (set -PythonPath or the registry engine_env). got '$python'"; retryable=$false }
        }

        # ---- resolve inference script ----
        if ([string]::IsNullOrWhiteSpace($TtsInferPath)) { $TtsInferPath = Join-Path $PSScriptRoot 'tts_infer.py' }
        if (-not (Test-Path -LiteralPath $TtsInferPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='infer_script_not_found'; message="tts_infer.py not found at '$TtsInferPath' (set -TtsInferPath)"; retryable=$false }
        }

        # ---- build args + run python worker ----
        $outWav = Join-Path $invDir 'speech.wav'
        $metaPath = Join-Path $invDir 'tts_meta.json'
        $argsObj = [ordered]@{
            text=$Text; speaker=$Speaker; language=$Language; instruct=$Instruct; model_path=$modelPath;
            device='cuda:0'; dtype=$dtype; attn='sdpa'; seed=$Seed; max_new_tokens=$(if ($MaxNewTokens -gt 0) { $MaxNewTokens } else { $null });
            out_wav=$outWav; meta_path=$metaPath
        }
        $argsFile = Join-Path $invDir 'tts_args.json'
        [System.IO.File]::WriteAllText($argsFile, ($argsObj | ConvertTo-Json -Depth 6), $utf8)

        $pyLog = Join-Path $invDir 'py.log'
        Write-Diag "python=$python model=$Model speaker=$Speaker dtype=$dtype -> $outWav"
        $pySw = [System.Diagnostics.Stopwatch]::StartNew()
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $pyArgs = @($TtsInferPath, $argsFile)
        $pyOut = & $python @pyArgs 2>&1
        $pyExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        $pySw.Stop()
        try { [System.IO.File]::WriteAllText($pyLog, (($pyOut | Out-String)), $utf8) } catch { }

        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
            $tail = ($pyOut | Out-String); if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
            throw [PSCustomObject]@{ code='synthesis_failed'; message="tts_infer produced no meta (exit $pyExit): $($tail.Trim())"; retryable=$true }
        }
        $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
        if (-not [bool](Prop $meta 'ok' $false)) {
            $ec = [string](Prop $meta 'error_code' 'synthesis_failed'); $em = [string](Prop $meta 'error' 'synthesis failed')
            throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$true }
        }
        if (-not (Test-Path -LiteralPath $outWav -PathType Leaf)) {
            throw [PSCustomObject]@{ code='synthesis_failed'; message='worker reported ok but no WAV was written'; retryable=$true }
        }

        $nativeSr = [int](Prop $meta 'sr' 24000)
        $samples = [int](Prop $meta 'samples' 0)
        $durS = [double](Prop $meta 'duration_s' 0.0)
        $pyRuntimeMs = [int](Prop $meta 'runtime_ms' ([int]$pySw.Elapsed.TotalMilliseconds))
        $attnUsed = [string](Prop $meta 'attn' 'sdpa')

        # ---- optional format/rate conversion via audio.ingest ----
        $finalAudio = $outWav; $finalFmt = 'wav'; $finalSr = $nativeSr; $finalCh = 1; $converted = $false
        $needConvert = (($fmt -ne 'wav') -or (($SampleRate -gt 0) -and ($SampleRate -ne $nativeSr)))
        if ($needConvert) {
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
                $aic = Join-Path $PSScriptRoot '..\10-audio-ingest\Invoke-AudioIngest.ps1'
                if (Test-Path -LiteralPath $aic -PathType Leaf) { $AudioIngestPath = (Resolve-Path -LiteralPath $aic).Path }
                else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $AudioIngestPath = Join-Path $root 'modules\10-audio-ingest\Invoke-AudioIngest.ps1' } }
            }
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath) -or -not (Test-Path -LiteralPath $AudioIngestPath -PathType Leaf)) {
                $warnings.Add('format/rate conversion requested but audio.ingest not found; returning native 24 kHz WAV')
            } else {
                $convRoot = Join-Path $invDir 'convert'
                $aiObj = [ordered]@{ input=$outWav; format=$fmt; channels=1 }
                if ($SampleRate -gt 0) { $aiObj.sample_rate = $SampleRate } else { $aiObj.sample_rate = 0 }
                $aiJson = ($aiObj | ConvertTo-Json -Compress)
                $prevEAP2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                $aiArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AudioIngestPath,'-InputsJson',$aiJson,'-ArtifactRoot',$convRoot)
                $tmpErr = New-TemporaryFile
                $aiOut = & $PwshPath @aiArgs 2> $tmpErr.FullName
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

        # ---- confidence (synthesis-completeness heuristic; NOT audio quality) ----
        $chars = ($Text -replace '\s','').Length
        $confReason = 'plausible_duration'
        if ($durS -le 0.05) { $confidence = 0.1; $confReason = 'empty_or_near_silent' }
        elseif ($chars -gt 0 -and $durS -lt (0.5 * 0.03 * $chars)) { $confidence = 0.3; $confReason = 'far_too_short_for_text' }
        elseif ($chars -gt 0 -and $durS -lt (0.03 * $chars)) { $confidence = 0.5; $confReason = 'short_for_text' }
        else { $confidence = 0.9; $confReason = 'plausible_duration' }

        $audioBytes = [System.IO.File]::ReadAllBytes($finalAudio)
        $rtf = $null; if ($durS -gt 0) { $rtf = [math]::Round((($pyRuntimeMs / 1000.0) / $durS), 4) }

        $result = [ordered]@{
            input = [ordered]@{ text=$Text; chars=$chars }
            model = [ordered]@{ id=$Model; name=[string](Prop $m 'name' $Model); engine='transformers'; engine_env=$python; device='cuda:0'; dtype=$dtype; attn=$attnUsed }
            params = [ordered]@{ speaker=$Speaker; language=$Language; instruct=$Instruct; seed=$Seed; max_new_tokens=$(if ($MaxNewTokens -gt 0) { $MaxNewTokens } else { $null }) }
            audio = [ordered]@{ path=$finalAudio; sample_rate=$finalSr; channels=$finalCh; samples=$samples; duration_s=$durS; bytes=$audioBytes.Length; sha256=(Get-Sha256Hex $audioBytes); format=$finalFmt; native_sample_rate=$nativeSr; converted=$converted }
            confidence = [ordered]@{ overall=$confidence; reason=$confReason }
            review = [ordered]@{ threshold=$ConfidenceThreshold; flagged=$false; queue_path=$null }
            synthesis = [ordered]@{ runtime_ms=$pyRuntimeMs; real_time_factor=$rtf }
        }

        $modelProvenance = @(
            [ordered]@{
                model_id = $Model
                name = [string](Prop $m 'name' $Model)
                family = [string](Prop $m 'family' 'qwen3-tts')
                format = [string](Prop $m 'format' 'safetensors-dir')
                version = [string](Prop $m 'version' '')
                engine = 'transformers'
                engine_env = $python
                device = 'cuda:0'
                dtype = $dtype
                attn = $attnUsed
                params = [ordered]@{ speaker=$Speaker; language=$Language; instruct=$Instruct; seed=$Seed; max_new_tokens=$(if ($MaxNewTokens -gt 0) { $MaxNewTokens } else { $null }) }
                sample_rate = $nativeSr
                audio_samples = $samples
                audio_seconds = $durS
                runtime_ms = $pyRuntimeMs
                real_time_factor = $rtf
            }
        )
        Write-Diag "ok dur=$durS sr=$nativeSr conf=$confidence rtf=$rtf converted=$converted"
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
    Write-Diag "ERROR: $($errorObj.code) — $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $tj = [ordered]@{ schema='lifeorch.tts.synthesis/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); model=$result.model.id; engine='transformers'; text=$result.input.text; params=$result.params; audio=$result.audio; confidence=$result.confidence }
        $tjPath = Join-Path $invDir 'tts.json'
        [System.IO.File]::WriteAllText($tjPath, ($tj | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# speech.tts synthesis — $($result.model.id)")
        [void]$mb.AppendLine("speaker: $($result.params.speaker)  language: $($result.params.language)")
        if (-not [string]::IsNullOrWhiteSpace([string]$result.params.instruct)) { [void]$mb.AppendLine("instruct: $($result.params.instruct)") }
        [void]$mb.AppendLine("audio: $($result.audio.path)")
        [void]$mb.AppendLine("format=$($result.audio.format)  sample_rate=$($result.audio.sample_rate)  channels=$($result.audio.channels)  duration=$($result.audio.duration_s)s  bytes=$($result.audio.bytes)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall) ($($result.confidence.reason))  rtf=$($result.synthesis.real_time_factor)  runtime_ms=$($result.synthesis.runtime_ms)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("text: $($result.input.text)")
        $tmPath = Join-Path $invDir 'tts.md'
        [System.IO.File]::WriteAllText($tmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $afmt = [string]$result.audio.format
        $artList.Add([pscustomobject]@{ p=$result.audio.path; k=$afmt })
        $artList.Add([pscustomobject]@{ p=$tjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$tmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[speech.tts] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (failed / too-short synthesis; append-only producer) ----
try {
    if ($status -ne 'error' -and $null -ne $result -and $null -ne $confidence -and $confidence -lt $ConfidenceThreshold) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $reason = if ($confidence -le 0.15) { 'failed_transform' } else { 'low_confidence' }
        $tprev = [string]$Text; if ($tprev.Length -gt 200) { $tprev = $tprev.Substring(0,200) }
        $rqItem = [ordered]@{
            schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-tts"
            created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason=$reason
            confidence=$confidence; source_ref="artifact://$invDir/tts.json"
            weak_result=[ordered]@{ model=$Model; speaker=$Speaker; text_preview=$tprev; duration_s=$result.audio.duration_s; chars=$result.input.chars; confidence_reason=$result.confidence.reason }
            requested='verify_synthesis'; status='open'; resolution=$null; escalated_to=$null
        }
        [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
        $result.review.flagged = $true
        $result.review.queue_path = $rqPath
        $warnings.Add("flagged synthesis to review queue ($rqPath): confidence $confidence < $ConfidenceThreshold ($($result.confidence.reason))")
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
