#requires -Version 7.0
<#
.SYNOPSIS
  voice.live — a local voice-turn loop composing speech.stt + model.gateway + speech.tts (Life Orchestrator, v0.1).
.DESCRIPTION
  The capstone of the audio track (10-13). Takes one input audio file and runs a voice turn:
    (1) STT     — speech.stt transcribes the audio (whisper segmentation = utterance/voice-activity detection);
    (2) Respond — model.gateway answers the transcript (optional, -Respond);
    (3) Speak   — speech.tts synthesizes the answer to reply.wav (optional, -Speak).
  It reimplements nothing: it spawns the child skills as pwsh processes and parses their result envelopes. Children's
  review-queue writes are aggregated into an in-artifact child_review.jsonl by default (a transient turn does not flood
  the canonical queue). Envelope confidence = the STT transcript confidence; model_provenance = the aggregate of every
  child model used. Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr. Exits 0 on a valid envelope.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile .\question.wav
  pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputsJson '{"input":"q.wav","respond":true,"speak":true,"speaker":"Aiden"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [bool]$Respond = $true,
    [bool]$Speak = $true,
    [bool]$ReadbackTranscript = $false,
    [string]$System = 'You are a helpful voice assistant. Answer the user concisely in one or two spoken sentences.',
    [string]$Tier = 'weak',
    [int]$MaxTokens = 200,
    [string]$Speaker = 'Ryan',
    [string]$Language = 'English',
    [string]$SttModel = 'stt.whisper.base-en',
    [string]$GatewayModel,
    [string]$TtsModel = 'tts.weak.qwen3-0p6b',
    [string]$Format = 'wav',
    [string]$SttPath,
    [string]$GatewayPath,
    [string]$TtsPath,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$ReviewQueuePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'voice.live'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[voice.live] $m") }
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
            $o = [ordered]@{ stage = $stage }
            foreach ($pn in $mp.PSObject.Properties.Name) { $o[$pn] = $mp.$pn }
            $agg.Add([pscustomobject]$o)
        }
    }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null
$modelProvenance = New-Object System.Collections.Generic.List[object]
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$stages = New-Object System.Collections.Generic.List[object]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validFormats = @('wav','mp3','flac','opus','ogg','m4a')

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'input')       -and -not $bound.ContainsKey('InputFile'))          { $InputFile = [string]$p.input }
            if ((Has $p 'respond')     -and -not $bound.ContainsKey('Respond'))            { $Respond = [bool]$p.respond }
            if ((Has $p 'speak')       -and -not $bound.ContainsKey('Speak'))              { $Speak = [bool]$p.speak }
            if ((Has $p 'readback_transcript') -and -not $bound.ContainsKey('ReadbackTranscript')) { $ReadbackTranscript = [bool]$p.readback_transcript }
            if ((Has $p 'system')      -and -not $bound.ContainsKey('System'))             { $System = [string]$p.system }
            if ((Has $p 'tier')        -and -not $bound.ContainsKey('Tier'))               { $Tier = [string]$p.tier }
            if ((Has $p 'max_tokens')  -and -not $bound.ContainsKey('MaxTokens'))          { $MaxTokens = [int]$p.max_tokens }
            if ((Has $p 'speaker')     -and -not $bound.ContainsKey('Speaker'))            { $Speaker = [string]$p.speaker }
            if ((Has $p 'language')    -and -not $bound.ContainsKey('Language'))           { $Language = [string]$p.language }
            if ((Has $p 'stt_model')   -and -not $bound.ContainsKey('SttModel'))           { $SttModel = [string]$p.stt_model }
            if ((Has $p 'gateway_model') -and -not $bound.ContainsKey('GatewayModel'))     { $GatewayModel = [string]$p.gateway_model }
            if ((Has $p 'tts_model')   -and -not $bound.ContainsKey('TtsModel'))           { $TtsModel = [string]$p.tts_model }
            if ((Has $p 'format')      -and -not $bound.ContainsKey('Format'))             { $Format = [string]$p.format }
            if ((Has $p 'stt_path')    -and -not $bound.ContainsKey('SttPath'))            { $SttPath = [string]$p.stt_path }
            if ((Has $p 'gateway_path') -and -not $bound.ContainsKey('GatewayPath'))       { $GatewayPath = [string]$p.gateway_path }
            if ((Has $p 'tts_path')    -and -not $bound.ContainsKey('TtsPath'))            { $TtsPath = [string]$p.tts_path }
            if ((Has $p 'pwsh_path')   -and -not $bound.ContainsKey('PwshPath'))           { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $fmt = 'wav'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }

    $normInputs = [ordered]@{ input=$InputFile; respond=$Respond; speak=$Speak; readback=$ReadbackTranscript; system=$System; tier=$Tier; max_tokens=$MaxTokens; speaker=$Speaker; language=$Language; stt_model=$SttModel; gateway_model=$GatewayModel; tts_model=$TtsModel; format=$fmt }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    $childReviewPath = if (-not [string]::IsNullOrWhiteSpace($ReviewQueuePath)) { $ReviewQueuePath } else { Join-Path $invDir 'child_review.jsonl' }

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message='no input file specified (-InputFile or InputsJson.input)'; retryable=$false }
    }
    elseif (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message="input file not found: $InputFile"; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    else {
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path

        # ---- resolve child entrypoints ----
        $sttEntry = Resolve-Child $SttPath '..\11-speech-stt\Invoke-SpeechStt.ps1'
        $gwEntry  = Resolve-Child $GatewayPath '..\07-model-gateway\Invoke-ModelGateway.ps1'
        $ttsEntry = Resolve-Child $TtsPath '..\12-speech-tts\Invoke-SpeechTts.ps1'
        if ([string]::IsNullOrWhiteSpace($sttEntry)) { throw [PSCustomObject]@{ code='stt_not_found'; message='speech.stt entrypoint not found (set -SttPath)'; retryable=$false } }
        if ($Respond -and [string]::IsNullOrWhiteSpace($gwEntry)) { throw [PSCustomObject]@{ code='gateway_not_found'; message='model.gateway entrypoint not found (set -GatewayPath)'; retryable=$false } }
        if ($Speak -and [string]::IsNullOrWhiteSpace($ttsEntry)) { throw [PSCustomObject]@{ code='tts_not_found'; message='speech.tts entrypoint not found (set -TtsPath)'; retryable=$false } }

        # ---- Stage 1: STT ----
        $sttInputs = [ordered]@{ input=$inFull; model=$SttModel; review_queue_path=$childReviewPath; pwsh_path=$PwshPath } | ConvertTo-Json -Compress
        $swS = [System.Diagnostics.Stopwatch]::StartNew()
        $sttR = Invoke-Child $sttEntry $sttInputs (Join-Path $invDir 'stt')
        $swS.Stop()
        $sttEnv = $sttR.env
        if ($null -eq $sttEnv -or -not (Has $sttEnv 'status') -or ($sttEnv.status -eq 'error')) {
            $ec = if ($null -ne $sttEnv -and (Has $sttEnv 'error') -and $null -ne $sttEnv.error) { [string](Prop $sttEnv.error 'code' 'stt_failed') } else { 'stt_failed' }
            $stages.Add([ordered]@{ name='stt'; status='error'; ms=[int]$swS.Elapsed.TotalMilliseconds; error=$ec })
            throw [PSCustomObject]@{ code='stage_failed'; message="STT stage failed ($ec); see $invDir\stt"; retryable=$true }
        }
        Add-Provenance $modelProvenance $sttEnv 'stt'
        $stages.Add([ordered]@{ name='stt'; status=[string]$sttEnv.status; ms=[int]$swS.Elapsed.TotalMilliseconds; error=$null })
        $transcriptText = ''
        $utterances = 0; $sttConf = $null; $lang = $Language; $sttArtDir = (Join-Path $invDir 'stt')
        if (Has $sttEnv 'result') {
            $transcriptText = ([string](Prop $sttEnv.result 'text' '')).Trim()
            $utterances = [int](Prop $sttEnv.result 'segment_count' 0)
            $lang = [string](Prop $sttEnv.result 'language' $Language)
        }
        if (Has $sttEnv 'confidence') { $sttConf = $sttEnv.confidence }
        if (Has $sttEnv 'diagnostics') { $sttArtDir = [string](Prop $sttEnv.diagnostics 'artifact_dir' $sttArtDir) }
        $confidence = $sttConf
        $speechDetected = ($utterances -gt 0 -and -not [string]::IsNullOrWhiteSpace($transcriptText))
        Write-Diag "stt: utterances=$utterances conf=$sttConf detected=$speechDetected"

        # ---- Stage 2: Respond ----
        $responseObj = $null; $responseText = ''
        if ($Respond -and $speechDetected) {
            $gwObj = [ordered]@{ prompt=$transcriptText; system=$System; max_tokens=$MaxTokens; review_queue_path=$childReviewPath; pwsh_path=$PwshPath }
            if (-not [string]::IsNullOrWhiteSpace($GatewayModel)) { $gwObj.model = $GatewayModel } else { $gwObj.tier = $Tier }
            $gwInputs = $gwObj | ConvertTo-Json -Compress
            $swG = [System.Diagnostics.Stopwatch]::StartNew()
            $gwR = Invoke-Child $gwEntry $gwInputs (Join-Path $invDir 'gateway')
            $swG.Stop()
            $gwEnv = $gwR.env
            if ($null -eq $gwEnv -or -not (Has $gwEnv 'status') -or ($gwEnv.status -eq 'error')) {
                $ec = if ($null -ne $gwEnv -and (Has $gwEnv 'error') -and $null -ne $gwEnv.error) { [string](Prop $gwEnv.error 'code' 'gateway_failed') } else { 'gateway_failed' }
                $stages.Add([ordered]@{ name='respond'; status='error'; ms=[int]$swG.Elapsed.TotalMilliseconds; error=$ec })
                $warnings.Add("respond stage failed ($ec); continuing without a response")
            } else {
                Add-Provenance $modelProvenance $gwEnv 'gateway'
                $stages.Add([ordered]@{ name='respond'; status=[string]$gwEnv.status; ms=[int]$swG.Elapsed.TotalMilliseconds; error=$null })
                if (Has $gwEnv 'result') { $responseText = ([string](Prop $gwEnv.result.output 'text' '')).Trim() }
                $responseObj = [ordered]@{
                    text = $responseText
                    model = $(if (Has $gwEnv 'result') { [string](Prop $gwEnv.result 'model' '') } else { '' })
                    confidence = $(if (Has $gwEnv 'confidence') { $gwEnv.confidence } else { $null })
                    finish_reason = $(if ((Has $gwEnv 'result') -and (Has $gwEnv.result 'generation')) { [string](Prop $gwEnv.result.generation 'finish_reason' '') } else { '' })
                }
                Write-Diag "respond: chars=$($responseText.Length) model=$($responseObj.model)"
            }
        }

        # ---- decide what to speak ----
        $textToSpeak = ''
        if (-not [string]::IsNullOrWhiteSpace($responseText)) { $textToSpeak = $responseText }
        elseif ($ReadbackTranscript -and $speechDetected) { $textToSpeak = $transcriptText }

        # ---- Stage 3: Speak ----
        $replyObj = $null; $replyLocal = $null
        if ($Speak -and -not [string]::IsNullOrWhiteSpace($textToSpeak)) {
            $ttsInputs = [ordered]@{ text=$textToSpeak; speaker=$Speaker; language=$Language; model=$TtsModel; format=$fmt; review_queue_path=$childReviewPath; pwsh_path=$PwshPath } | ConvertTo-Json -Compress
            $swT = [System.Diagnostics.Stopwatch]::StartNew()
            $ttsR = Invoke-Child $ttsEntry $ttsInputs (Join-Path $invDir 'tts')
            $swT.Stop()
            $ttsEnv = $ttsR.env
            if ($null -eq $ttsEnv -or -not (Has $ttsEnv 'status') -or ($ttsEnv.status -eq 'error')) {
                $ec = if ($null -ne $ttsEnv -and (Has $ttsEnv 'error') -and $null -ne $ttsEnv.error) { [string](Prop $ttsEnv.error 'code' 'tts_failed') } else { 'tts_failed' }
                $stages.Add([ordered]@{ name='speak'; status='error'; ms=[int]$swT.Elapsed.TotalMilliseconds; error=$ec })
                $warnings.Add("speak stage failed ($ec); no reply audio produced")
            } else {
                Add-Provenance $modelProvenance $ttsEnv 'tts'
                $stages.Add([ordered]@{ name='speak'; status=[string]$ttsEnv.status; ms=[int]$swT.Elapsed.TotalMilliseconds; error=$null })
                $srcAudio = $null; $rfmt = $fmt; $rsr = $null; $rdur = $null
                if (Has $ttsEnv 'result') {
                    $srcAudio = [string](Prop $ttsEnv.result.audio 'path' '')
                    $rfmt = [string](Prop $ttsEnv.result.audio 'format' $fmt)
                    $rsr = [int](Prop $ttsEnv.result.audio 'sample_rate' 24000)
                    $rdur = (Prop $ttsEnv.result.audio 'duration_s' $null)
                }
                if (-not [string]::IsNullOrWhiteSpace($srcAudio) -and (Test-Path -LiteralPath $srcAudio -PathType Leaf)) {
                    $replyLocal = Join-Path $invDir ("reply." + $rfmt)
                    Copy-Item -LiteralPath $srcAudio -Destination $replyLocal -Force
                    $rb = [System.IO.File]::ReadAllBytes($replyLocal)
                    $replyObj = [ordered]@{ path=(Resolve-Path -LiteralPath $replyLocal).Path; format=$rfmt; sample_rate=$rsr; duration_s=$rdur; bytes=$rb.Length; sha256=(Get-Sha256Hex $rb) }
                    Write-Diag "speak: reply=$replyLocal dur=$rdur"
                } else { $warnings.Add('speak stage reported ok but no reply audio file was found') }
            }
        }

        if (-not $speechDetected) { Write-Diag 'no speech detected in input; skipped respond/speak' }

        # ---- child review count (only meaningful for the in-artifact aggregate) ----
        $childReviewCount = 0
        if ((Test-Path -LiteralPath $childReviewPath -PathType Leaf)) {
            try { $childReviewCount = @(Get-Content -LiteralPath $childReviewPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }).Count } catch { }
        }

        $result = [ordered]@{
            input = [ordered]@{ path=$inFull }
            speech_detected = $speechDetected
            transcript = [ordered]@{ text=$transcriptText; utterance_count=$utterances; confidence=$sttConf; language=$lang; artifact_dir=$sttArtDir }
            response = $responseObj
            reply = $replyObj
            stages = $stages.ToArray()
            config = [ordered]@{ respond=$Respond; speak=$Speak; readback_transcript=$ReadbackTranscript; tier=$Tier; speaker=$Speaker; language=$Language }
            child_review_path = $childReviewPath
            child_review_count = $childReviewCount
        }
    }

    if ($status -eq 'ok') {
        $anyStageErr = @($stages.ToArray() | Where-Object { $_.status -eq 'error' }).Count -gt 0
        if ($anyStageErr -or $warnings.Count -gt 0) { $status = 'partial' }
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
        $vj = [ordered]@{ schema='lifeorch.voice.turn/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $vjPath = Join-Path $invDir 'voice.json'
        [System.IO.File]::WriteAllText($vjPath, ($vj | ConvertTo-Json -Depth 15), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# voice.live turn")
        [void]$mb.AppendLine("input: $($result.input.path)")
        [void]$mb.AppendLine("speech_detected: $($result.speech_detected)  utterances: $($result.transcript.utterance_count)  stt_confidence: $($result.transcript.confidence)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("heard: $($result.transcript.text)")
        if ($null -ne $result.response) { [void]$mb.AppendLine(''); [void]$mb.AppendLine("answered ($($result.response.model)): $($result.response.text)") }
        if ($null -ne $result.reply) { [void]$mb.AppendLine(''); [void]$mb.AppendLine("reply audio: $($result.reply.path)  ($($result.reply.format), $($result.reply.sample_rate) Hz, $($result.reply.duration_s)s)") }
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine("stages: " + ((@($result.stages) | ForEach-Object { "$($_.name)=$($_.status)/$($_.ms)ms" }) -join '  '))
        $vmPath = Join-Path $invDir 'voice.md'
        [System.IO.File]::WriteAllText($vmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        if ($null -ne $result.reply -and (Test-Path -LiteralPath $result.reply.path -PathType Leaf)) { $artList.Add([pscustomobject]@{ p=$result.reply.path; k=$result.reply.format }) }
        $artList.Add([pscustomobject]@{ p=$vjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$vmPath; k='markdown' })
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[voice.live] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
$json = $envelope | ConvertTo-Json -Depth 22
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
