#requires -Version 7.0
<#
.SYNOPSIS
  speech.stt — timestamped speech-to-text transcription via whisper.cpp (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Wraps the whisper.cpp `whisper-cli.exe` to transcribe one audio/media file into timestamped segments with a
  per-segment and overall confidence (mean whisper per-token probability). Resolves the STT model + whisper CLI
  from the model registry (models.json). Consumes whisper-ready 16 kHz mono s16 WAV directly; for other inputs
  it can normalize first through Module 10 (audio.ingest). First stochastic/mixed skill that wraps a local model
  binary: populates `confidence` + `model_provenance` and routes low-confidence segments to the review queue.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes whisper.json/.srt/.txt,
  transcript.json, transcript.md, result.json, stderr.txt (+ normalize/ artifacts when normalization ran).
  Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputFile .\meeting.wav
  pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputsJson '{"input":"clip.mp3","normalize":"always","language":"en"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Normalize = 'auto',            # auto | always | never
    [string]$Language = 'en',
    [switch]$Translate,
    [int]$Threads = 4,
    [switch]$NoGpu,
    [int]$BeamSize = 5,
    [int]$BestOf = 5,
    [int]$MaxLen = 0,
    [switch]$SplitOnWord,
    [int]$OffsetMs = 0,
    [int]$DurationMs = 0,
    [double]$SegmentConfidenceThreshold = 0.5,
    [int]$MaxReviewSegments = 25,
    [double]$MinSpeechSeconds = 1.0,
    [string]$Model = 'stt.whisper.base-en',
    [string]$Registry,
    [string]$WhisperCliPath,
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

$SKILL_ID = 'speech.stt'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[speech.stt] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Format-Ts([long]$ms) {
    if ($ms -lt 0) { $ms = 0 }
    $ts = [TimeSpan]::FromMilliseconds([double]$ms)
    return ('{0:00}:{1:00}:{2:00}.{3:000}' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds, $ts.Milliseconds)
}
# Run a child process with both streams drained asynchronously (avoids the pipe-fill deadlock).
function Invoke-Proc([string]$exe, [string[]]$argv) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    foreach ($a in $argv) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::new(); $p.StartInfo = $psi
    [void]$p.Start()
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $out = $so.GetAwaiter().GetResult(); $err = $se.GetAwaiter().GetResult()
    $code = $p.ExitCode; $p.Dispose()
    return @{ exit = $code; stdout = $out; stderr = $err }
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
function Resolve-Ffmpeg {
    $gc = Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gc) { return $gc.Source }
    $cands = @(
        (Join-Path ([string]$env:LOCALAPPDATA) 'Microsoft\WinGet\Links\ffmpeg.exe'),
        'C:\Program Files\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($c in $cands) { if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path } }
    return $null
}
function Resolve-Ffprobe([string]$ffmpegPath) {
    if (-not [string]::IsNullOrWhiteSpace($ffmpegPath)) {
        $leaf = Split-Path -Leaf $ffmpegPath
        $sib = Join-Path (Split-Path -Parent $ffmpegPath) ($leaf -replace 'ffmpeg', 'ffprobe')
        if (Test-Path -LiteralPath $sib -PathType Leaf) { return (Resolve-Path -LiteralPath $sib).Path }
    }
    $cmds = @(Get-Command 'ffprobe' -CommandType Application -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) { if ($c.Source -notmatch '[\\/][Pp]ython[^\\/]*[\\/][Ss]cripts[\\/]') { return $c.Source } }
    if ($cmds.Count -gt 0) { return $cmds[0].Source }
    return $null
}
function Get-AudioProbe([string]$ffprobe, [string]$file) {
    if ([string]::IsNullOrWhiteSpace($ffprobe)) { return $null }
    $r = Invoke-Proc $ffprobe @('-v','error','-print_format','json','-show_format','-show_streams', $file)
    if ($r.exit -ne 0) { return $null }
    $j = $null; try { $j = $r.stdout | ConvertFrom-Json } catch { return $null }
    if ($null -eq $j) { return $null }
    $astream = $null
    foreach ($s in @(Prop $j 'streams' @())) { if ((Prop $s 'codec_type') -eq 'audio') { $astream = $s; break } }
    $audio = $null
    if ($null -ne $astream) {
        $sr = 0; [void][int]::TryParse([string](Prop $astream 'sample_rate' '0'), [ref]$sr)
        $audio = [ordered]@{
            codec = [string](Prop $astream 'codec_name' '')
            sample_rate = $sr
            channels = [int](Prop $astream 'channels' 0)
        }
    }
    $fmtObj = Prop $j 'format'
    $dur = $null; $td = 0.0
    if ([double]::TryParse([string](Prop $fmtObj 'duration' ''), [Globalization.NumberStyles]::Float, $inv, [ref]$td)) { $dur = [math]::Round($td, 3) }
    return [ordered]@{
        audio_stream_present = ($null -ne $astream)
        format_name = [string](Prop $fmtObj 'format_name' '')
        duration_s = $dur
        audio = $audio
    }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validNormalize = @('auto','always','never')
$reviewItems = New-Object System.Collections.Generic.List[object]

try {
    # ---- merge -InputsJson (explicit named params win) ----
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            if ((Has $p 'input')        -and -not $bound.ContainsKey('InputFile'))     { $InputFile = [string]$p.input }
            if ((Has $p 'normalize')    -and -not $bound.ContainsKey('Normalize'))     { $Normalize = [string]$p.normalize }
            if ((Has $p 'language')     -and -not $bound.ContainsKey('Language'))      { $Language = [string]$p.language }
            if ((Has $p 'translate')    -and -not $bound.ContainsKey('Translate'))     { if ([bool]$p.translate) { $Translate = [switch]$true } }
            if ((Has $p 'threads')      -and -not $bound.ContainsKey('Threads'))       { $Threads = [int]$p.threads }
            if ((Has $p 'no_gpu')       -and -not $bound.ContainsKey('NoGpu'))         { if ([bool]$p.no_gpu) { $NoGpu = [switch]$true } }
            if ((Has $p 'beam_size')    -and -not $bound.ContainsKey('BeamSize'))      { $BeamSize = [int]$p.beam_size }
            if ((Has $p 'best_of')      -and -not $bound.ContainsKey('BestOf'))        { $BestOf = [int]$p.best_of }
            if ((Has $p 'max_len')      -and -not $bound.ContainsKey('MaxLen'))        { $MaxLen = [int]$p.max_len }
            if ((Has $p 'split_on_word')-and -not $bound.ContainsKey('SplitOnWord'))   { if ([bool]$p.split_on_word) { $SplitOnWord = [switch]$true } }
            if ((Has $p 'offset_ms')    -and -not $bound.ContainsKey('OffsetMs'))      { $OffsetMs = [int]$p.offset_ms }
            if ((Has $p 'duration_ms')  -and -not $bound.ContainsKey('DurationMs'))    { $DurationMs = [int]$p.duration_ms }
            if ((Has $p 'segment_confidence_threshold') -and -not $bound.ContainsKey('SegmentConfidenceThreshold')) { $SegmentConfidenceThreshold = [double]$p.segment_confidence_threshold }
            if ((Has $p 'max_review_segments') -and -not $bound.ContainsKey('MaxReviewSegments')) { $MaxReviewSegments = [int]$p.max_review_segments }
            if ((Has $p 'min_speech_seconds')  -and -not $bound.ContainsKey('MinSpeechSeconds'))  { $MinSpeechSeconds = [double]$p.min_speech_seconds }
            if ((Has $p 'model')        -and -not $bound.ContainsKey('Model'))         { $Model = [string]$p.model }
            if ((Has $p 'registry')     -and -not $bound.ContainsKey('Registry'))      { $Registry = [string]$p.registry }
            if ((Has $p 'whisper_cli_path') -and -not $bound.ContainsKey('WhisperCliPath')) { $WhisperCliPath = [string]$p.whisper_cli_path }
            if ((Has $p 'audio_ingest_path') -and -not $bound.ContainsKey('AudioIngestPath')) { $AudioIngestPath = [string]$p.audio_ingest_path }
            if ((Has $p 'pwsh_path')    -and -not $bound.ContainsKey('PwshPath'))      { $PwshPath = [string]$p.pwsh_path }
            if ((Has $p 'review_queue_path') -and -not $bound.ContainsKey('ReviewQueuePath')) { $ReviewQueuePath = [string]$p.review_queue_path }
        }
    }
    $normMode = 'auto'; if (-not [string]::IsNullOrWhiteSpace($Normalize)) { $normMode = $Normalize.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($Language)) { $Language = 'en' }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{
        input=$InputFile; normalize=$normMode; language=$Language; translate=[bool]$Translate; threads=$Threads;
        no_gpu=[bool]$NoGpu; beam_size=$BeamSize; best_of=$BestOf; max_len=$MaxLen; split_on_word=[bool]$SplitOnWord;
        offset_ms=$OffsetMs; duration_ms=$DurationMs; model=$Model
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate simple inputs ----
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message='no input file specified (-InputFile or InputsJson.input)'; retryable=$false }
    }
    elseif (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message="input file not found: $InputFile"; retryable=$false }
    }
    elseif ($validNormalize -notcontains $normMode) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_normalize'; message="normalize must be one of: $($validNormalize -join ', '); got '$normMode'"; retryable=$false }
    }
    else {
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path

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
            $known = ($models | Where-Object { (Has $_ 'type') -and ($_.type -eq 'stt') } | ForEach-Object { $_.model_id }) -join ', '
            throw [PSCustomObject]@{ code='model_not_found'; message="stt model '$Model' not in registry. Known stt: $known"; retryable=$false }
        }
        $mType = [string](Prop $m 'type' 'unknown')
        if ($mType -ne 'stt') { throw [PSCustomObject]@{ code='unsupported_type'; message="speech.stt runs type=stt only (model '$Model' is type=$mType)"; retryable=$false } }
        $mEngine = [string](Prop $m 'engine' '')
        if ($mEngine -ne 'whisper.cpp') { throw [PSCustomObject]@{ code='unsupported_engine'; message="speech.stt supports engine=whisper.cpp only (got '$mEngine')"; retryable=$false } }
        $modelPath = [string](Prop $m 'path' '')
        if ([string]::IsNullOrWhiteSpace($modelPath) -or -not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
            throw [PSCustomObject]@{ code='model_file_missing'; message="whisper model file not found at '$modelPath'"; retryable=$true }
        }

        # ---- resolve whisper CLI (override > registry engine_candidates) ----
        $cli = $null
        if (-not [string]::IsNullOrWhiteSpace($WhisperCliPath)) {
            if (Test-Path -LiteralPath $WhisperCliPath -PathType Leaf) { $cli = (Resolve-Path -LiteralPath $WhisperCliPath).Path }
            else { throw [PSCustomObject]@{ code='whisper_cli_not_found'; message="-WhisperCliPath does not exist: $WhisperCliPath"; retryable=$false } }
        } else {
            foreach ($c in @(Prop $m 'engine_candidates' @())) { if ((-not [string]::IsNullOrWhiteSpace($c)) -and (Test-Path -LiteralPath ([string]$c) -PathType Leaf)) { $cli = (Resolve-Path -LiteralPath ([string]$c)).Path; break } }
        }
        if ([string]::IsNullOrWhiteSpace($cli)) { throw [PSCustomObject]@{ code='whisper_cli_not_found'; message="no whisper-cli.exe found (set -WhisperCliPath or fix registry engine_candidates)"; retryable=$false } }
        $device = if ($NoGpu) { 'cpu' } elseif ($cli -match '(?i)cuda') { 'cuda:0' } else { 'cpu' }

        # ---- resolve ffmpeg/ffprobe (for auto-probe + audio.ingest sibling) ----
        $ffmpeg = Resolve-Ffmpeg
        $ffprobe = Resolve-Ffprobe $ffmpeg

        # ---- decide + perform normalization ----
        $sourceProbe = Get-AudioProbe $ffprobe $inFull
        if (($null -ne $sourceProbe) -and (-not [bool]$sourceProbe.audio_stream_present)) {
            throw [PSCustomObject]@{ code='no_audio_stream'; message="input has no audio stream: $inFull"; retryable=$false }
        }
        $isReady = $false
        if ($null -ne $sourceProbe -and $null -ne $sourceProbe.audio) {
            $isReady = (($sourceProbe.audio.codec -eq 'pcm_s16le') -and ([int]$sourceProbe.audio.sample_rate -eq 16000) -and ([int]$sourceProbe.audio.channels -eq 1) -and ($sourceProbe.format_name -match 'wav'))
        }
        $doNormalize = $false
        switch ($normMode) {
            'never'  { $doNormalize = $false }
            'always' { $doNormalize = $true }
            'auto'   { if ($null -eq $sourceProbe) { $doNormalize = $true; $warnings.Add('could not probe input (ffprobe unavailable); normalizing via audio.ingest to be safe') } else { $doNormalize = (-not $isReady) } }
        }

        $feedWav = $inFull; $normalized = $false
        if ($doNormalize) {
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
                $aic = Join-Path $PSScriptRoot '..\10-audio-ingest\Invoke-AudioIngest.ps1'
                if (Test-Path -LiteralPath $aic -PathType Leaf) { $AudioIngestPath = (Resolve-Path -LiteralPath $aic).Path }
                else { $root = Resolve-RepoRoot $PSScriptRoot; if ($null -ne $root) { $AudioIngestPath = Join-Path $root 'modules\10-audio-ingest\Invoke-AudioIngest.ps1' } }
            }
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath) -or -not (Test-Path -LiteralPath $AudioIngestPath -PathType Leaf)) {
                throw [PSCustomObject]@{ code='audio_ingest_not_found'; message="audio.ingest entrypoint not found (set -AudioIngestPath). got '$AudioIngestPath'"; retryable=$false }
            }
            $normRoot = Join-Path $invDir 'normalize'
            $aiJson = ([ordered]@{ input=$inFull; format='wav'; sample_rate=16000; channels=1; sample_fmt='s16' } | ConvertTo-Json -Compress)
            $aiArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AudioIngestPath,'-InputsJson',$aiJson,'-ArtifactRoot',$normRoot)
            Write-Diag "normalizing via audio.ingest -> $normRoot"
            $tmpErr = New-TemporaryFile
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $aiOut = & $PwshPath @aiArgs 2> $tmpErr.FullName
            $aiExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
            $aiText = ($aiOut | Out-String).Trim()
            $aiEnv = $null; try { $aiEnv = $aiText | ConvertFrom-Json } catch { }
            if ($null -eq $aiEnv -or -not (Has $aiEnv 'status')) {
                throw [PSCustomObject]@{ code='normalize_failed'; message="audio.ingest produced no valid envelope (exit $aiExit)"; retryable=$true }
            }
            if (@('ok','partial') -notcontains [string]$aiEnv.status) {
                $aiCode = if (Has $aiEnv 'error') { [string](Prop $aiEnv.error 'code' 'error') } else { 'error' }
                throw [PSCustomObject]@{ code='normalize_failed'; message="audio.ingest failed: $aiCode"; retryable=$true }
            }
            $outPath = $null; if ((Has $aiEnv 'result') -and (Has $aiEnv.result 'output')) { $outPath = [string](Prop $aiEnv.result.output 'path' '') }
            if ([string]::IsNullOrWhiteSpace($outPath) -or -not (Test-Path -LiteralPath $outPath -PathType Leaf)) {
                throw [PSCustomObject]@{ code='normalize_failed'; message='audio.ingest did not yield an output WAV'; retryable=$true }
            }
            $feedWav = (Resolve-Path -LiteralPath $outPath).Path; $normalized = $true
        }

        # ---- probe the fed WAV (duration/rate/channels) ----
        $feedProbe = Get-AudioProbe $ffprobe $feedWav
        $audioDur = $null; $audioSr = $null; $audioCh = $null
        if ($null -ne $feedProbe) {
            $audioDur = $feedProbe.duration_s
            if ($null -ne $feedProbe.audio) { $audioSr = [int]$feedProbe.audio.sample_rate; $audioCh = [int]$feedProbe.audio.channels }
        }

        # ---- build whisper argv ----
        $base = Join-Path $invDir 'whisper'
        $wargv = New-Object System.Collections.Generic.List[string]
        $wargv.Add('-m'); $wargv.Add($modelPath)
        $wargv.Add('-f'); $wargv.Add($feedWav)
        $wargv.Add('-ojf'); $wargv.Add('-osrt'); $wargv.Add('-otxt')
        $wargv.Add('-of'); $wargv.Add($base)
        $wargv.Add('-np')
        $wargv.Add('-l'); $wargv.Add($Language)
        $wargv.Add('-t'); $wargv.Add([string]$Threads)
        if ($BeamSize -ge 0) { $wargv.Add('-bs'); $wargv.Add([string]$BeamSize) }
        if ($BestOf -ge 0)   { $wargv.Add('-bo'); $wargv.Add([string]$BestOf) }
        if ($Translate)      { $wargv.Add('-tr') }
        if ($NoGpu)          { $wargv.Add('-ng') }
        if ($MaxLen -gt 0)   { $wargv.Add('-ml'); $wargv.Add([string]$MaxLen) }
        if ($SplitOnWord)    { $wargv.Add('-sow') }
        if ($OffsetMs -gt 0) { $wargv.Add('-ot'); $wargv.Add([string]$OffsetMs) }
        if ($DurationMs -gt 0){ $wargv.Add('-d'); $wargv.Add([string]$DurationMs) }
        $wargvArr = $wargv.ToArray()

        Write-Diag "whisper cli=$cli model=$Model device=$device feed=$feedWav"
        $wSw = [System.Diagnostics.Stopwatch]::StartNew()
        $run = Invoke-Proc $cli $wargvArr
        $wSw.Stop()
        $whisperMs = [int]$wSw.Elapsed.TotalMilliseconds
        try { [System.IO.File]::WriteAllText((Join-Path $invDir 'whisper.log'), "STDOUT`n$($run.stdout)`n`nSTDERR`n$($run.stderr)`n", $utf8) } catch { }

        $wjPath = "$base.json"
        if ($run.exit -ne 0 -or -not (Test-Path -LiteralPath $wjPath -PathType Leaf)) {
            $tail = ''; if ($run.stderr) { $tail = if ($run.stderr.Length -gt 700) { $run.stderr.Substring($run.stderr.Length - 700) } else { $run.stderr } }
            throw [PSCustomObject]@{ code='whisper_failed'; message="whisper-cli exited $($run.exit): $($tail.Trim())"; retryable=$true }
        }

        # ---- parse whisper.json (-ojf) ----
        $wj = (Get-Content -LiteralPath $wjPath -Raw) | ConvertFrom-Json
        $wLang = [string](Prop (Prop $wj 'result') 'language' $Language)
        $wModel = Prop $wj 'model'
        $multilingual = [bool](Prop $wModel 'multilingual' $false)
        $systeminfo = [string](Prop $wj 'systeminfo' '')
        if ((-not $multilingual) -and ($Language -ne 'en')) { $warnings.Add("model is English-only (multilingual=false) but language='$Language' was requested; whisper used its default") }

        $transcription = @(Prop $wj 'transcription' @())
        $segsOut = New-Object System.Collections.Generic.List[object]
        $allP = New-Object System.Collections.Generic.List[double]
        $idx = 0
        foreach ($seg in $transcription) {
            $off = Prop $seg 'offsets'
            $t0ms = [long](Prop $off 'from' 0)
            $t1ms = [long](Prop $off 'to' 0)
            $segText = ([string](Prop $seg 'text' '')).Trim()
            $segP = New-Object System.Collections.Generic.List[double]
            foreach ($tk in @(Prop $seg 'tokens' @())) {
                $tkText = [string](Prop $tk 'text' '')
                if ($tkText -match '^\s*\[_') { continue }   # skip whisper special tokens ([_BEG_], [_EOT_], ...)
                $segP.Add([double](Prop $tk 'p' 0.0))
            }
            $segConf = $null
            if ($segP.Count -gt 0) { $segConf = [math]::Round((($segP.ToArray() | Measure-Object -Average).Average), 4); foreach ($pp in $segP.ToArray()) { $allP.Add($pp) } }
            $low = ($null -ne $segConf -and $segConf -lt $SegmentConfidenceThreshold)
            $segsOut.Add([ordered]@{ index=$idx; t0_ms=$t0ms; t1_ms=$t1ms; t0=(Format-Ts $t0ms); t1=(Format-Ts $t1ms); text=$segText; confidence=$segConf; token_count=$segP.Count; low_confidence=$low })
            $idx++
        }
        $segArr = $segsOut.ToArray()

        $overall = $null
        if ($allP.Count -gt 0) { $overall = [math]::Round((($allP.ToArray() | Measure-Object -Average).Average), 4) }
        $confidence = $overall
        $segConfVals = @($segArr | Where-Object { $null -ne $_.confidence } | ForEach-Object { [double]$_.confidence })
        $minSeg = $null; if ($segConfVals.Count -gt 0) { $minSeg = [math]::Round((($segConfVals | Measure-Object -Minimum).Minimum), 4) }
        $lowSegs = @($segArr | Where-Object { $_.low_confidence }); $lowCount = $lowSegs.Count
        $fullText = (($segArr | ForEach-Object { $_.text }) -join ' ').Trim()
        $tokenCount = $allP.Count

        if ($null -eq $audioDur -and $segArr.Count -gt 0) { $audioDur = [math]::Round(([long]$segArr[-1].t1_ms / 1000.0), 3) }
        $rtf = $null; if ($null -ne $audioDur -and [double]$audioDur -gt 0) { $rtf = [math]::Round((($whisperMs / 1000.0) / [double]$audioDur), 4) }
        if ($segArr.Count -eq 0) { $warnings.Add('whisper produced no transcription segments (no speech detected or decode failure)') }

        # ---- result ----
        $result = [ordered]@{
            input = [ordered]@{ path=$inFull; exists=$true; normalized=$normalized; normalize_mode=$normMode; source_probe=$sourceProbe }
            audio = [ordered]@{ path=$feedWav; sample_rate=$audioSr; channels=$audioCh; duration_s=$audioDur }
            model = [ordered]@{ id=$Model; name=[string](Prop $m 'name' $Model); engine='whisper.cpp'; engine_path=$cli; build=([string](Prop $reg 'host' '')); device=$device; multilingual=$multilingual }
            params = [ordered]@{ language=$Language; translate=[bool]$Translate; beam_size=$BeamSize; best_of=$BestOf; threads=$Threads; no_gpu=[bool]$NoGpu; max_len=$MaxLen; split_on_word=[bool]$SplitOnWord; offset_ms=$OffsetMs; duration_ms=$DurationMs }
            language = $wLang
            text = $fullText
            segment_count = $segArr.Count
            token_count = $tokenCount
            confidence = [ordered]@{ overall=$overall; min_segment=$minSeg; low_confidence_segments=$lowCount }
            segments = $segArr
            review = [ordered]@{ threshold=$SegmentConfidenceThreshold; flagged_count=0; truncated=$false; queue_path=$null }
            whisper = [ordered]@{ cli=$cli; systeminfo=$systeminfo; runtime_ms=$whisperMs; real_time_factor=$rtf }
        }

        $modelProvenance = @(
            [ordered]@{
                model_id = $Model
                name = [string](Prop $m 'name' $Model)
                family = [string](Prop $m 'family' 'whisper')
                format = [string](Prop $m 'format' 'ggml-bin')
                version = [string](Prop $m 'version' 'ggml-base.en')
                engine = 'whisper.cpp'
                engine_path = $cli
                engine_build = $systeminfo
                device = $device
                params = [ordered]@{ language=$Language; translate=[bool]$Translate; beam_size=$BeamSize; best_of=$BestOf; threads=$Threads; no_gpu=[bool]$NoGpu; max_len=$MaxLen; split_on_word=[bool]$SplitOnWord; offset_ms=$OffsetMs; duration_ms=$DurationMs; temperature=0.0 }
                audio_duration_s = $audioDur
                segments = $segArr.Count
                tokens = $tokenCount
                avg_token_p = $overall
                runtime_ms = $whisperMs
                real_time_factor = $rtf
            }
        )
        Write-Diag "ok segs=$($segArr.Count) tokens=$tokenCount conf=$overall rtf=$rtf"
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
        $tj = [ordered]@{ schema='lifeorch.stt.transcript/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); model=$result.model.id; engine='whisper.cpp'; language=$result.language; duration_s=$result.audio.duration_s; segment_count=$result.segment_count; token_count=$result.token_count; confidence=$result.confidence; text=$result.text; segments=$result.segments }
        $tjPath = Join-Path $invDir 'transcript.json'
        [System.IO.File]::WriteAllText($tjPath, ($tj | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# speech.stt transcript — $($result.model.id) ($($result.language))")
        [void]$mb.AppendLine("audio: $($result.audio.path)")
        [void]$mb.AppendLine("duration: $($result.audio.duration_s)s  segments: $($result.segment_count)  tokens: $($result.token_count)")
        [void]$mb.AppendLine("confidence: overall=$($result.confidence.overall)  min_segment=$($result.confidence.min_segment)  low_conf_segments=$($result.confidence.low_confidence_segments)")
        [void]$mb.AppendLine("whisper: rtf=$($result.whisper.real_time_factor)  runtime_ms=$($result.whisper.runtime_ms)  device=$($result.model.device)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('| # | start | end | conf | text |')
        [void]$mb.AppendLine('|---|-------|-----|------|------|')
        $rowMax = 200; $rowN = 0
        foreach ($s in @($result.segments)) {
            if ($rowN -ge $rowMax) { [void]$mb.AppendLine("| … | | | | ($($result.segment_count - $rowMax) more segments — see transcript.json) |"); break }
            $mark = if ($s.low_confidence) { '⚠ ' } else { '' }
            $txt = ([string]$s.text).Replace('|','\|')
            [void]$mb.AppendLine("| $($s.index) | $($s.t0) | $($s.t1) | $mark$($s.confidence) | $txt |")
            $rowN++
        }
        $tmPath = Join-Path $invDir 'transcript.md'
        [System.IO.File]::WriteAllText($tmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $whisperBase = Join-Path $invDir 'whisper'
        foreach ($pair in @(@("$whisperBase.json",'json'), @("$whisperBase.srt",'srt'), @("$whisperBase.txt",'text'))) {
            if (Test-Path -LiteralPath $pair[0] -PathType Leaf) { $artList.Add([pscustomobject]@{ p=$pair[0]; k=$pair[1] }) }
        }
        $artList.Add([pscustomobject]@{ p=$tjPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$tmPath; k='markdown' })
        if ($result.input.normalized -and (Test-Path -LiteralPath $result.audio.path -PathType Leaf)) { $artList.Add([pscustomobject]@{ p=$result.audio.path; k='wav' }) }
        foreach ($a in $artList.ToArray()) {
            $b = [System.IO.File]::ReadAllBytes($a.p)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[speech.stt] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

# ---- review queue (low-confidence segments; append-only producer) ----
try {
    if ($status -ne 'error' -and $null -ne $result) {
        $rqPath = $ReviewQueuePath
        if ([string]::IsNullOrWhiteSpace($rqPath)) {
            $root = Resolve-RepoRoot $PSScriptRoot
            $rqPath = if ($null -ne $root) { Join-Path $root 'review_queue.jsonl' } else { Join-Path $invDir 'review_queue.jsonl' }
        }
        $flagged = 0; $truncated = $false
        $lows = @($result.segments | Where-Object { $_.low_confidence } | Sort-Object { [double]$_.confidence })
        if ($lows.Count -gt 0) {
            $take = $lows
            if ($lows.Count -gt $MaxReviewSegments) { $take = @($lows[0..($MaxReviewSegments-1)]); $truncated = $true }
            foreach ($s in $take) {
                $rqItem = [ordered]@{
                    schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-seg$($s.index)"
                    created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='low_confidence'
                    confidence=$s.confidence; source_ref="artifact://$invDir/transcript.json#seg$($s.index)"
                    weak_result=[ordered]@{ model=$result.model.id; t0_ms=$s.t0_ms; t1_ms=$s.t1_ms; text=$s.text; token_count=$s.token_count }
                    requested='verify_transcription'; status='open'; resolution=$null; escalated_to=$null
                }
                [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
                $flagged++
            }
        }
        elseif ($result.segment_count -eq 0 -and $null -ne $result.audio.duration_s -and [double]$result.audio.duration_s -ge $MinSpeechSeconds) {
            $rqItem = [ordered]@{
                schema='lifeorch.review.item/0.1'; id="rq-$($InvocationId.Substring(0,8))-nospeech"
                created_at_utc=([DateTime]::UtcNow).ToString('o'); flagged_by=$SKILL_ID; reason='uncategorized'
                confidence=$null; source_ref="artifact://$invDir/transcript.json"
                weak_result=[ordered]@{ model=$result.model.id; duration_s=$result.audio.duration_s; note='no speech segments from non-trivial-duration audio' }
                requested='verify_no_speech'; status='open'; resolution=$null; escalated_to=$null
            }
            [System.IO.File]::AppendAllText($rqPath, (($rqItem | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8)
            $flagged++
        }
        if ($flagged -gt 0) {
            $result.review.flagged_count = $flagged
            $result.review.truncated = $truncated
            $result.review.queue_path = $rqPath
            $warnings.Add("flagged $flagged low-confidence segment(s) to review queue ($rqPath)$(if($truncated){' (truncated to '+$MaxReviewSegments+')'}else{''})")
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
