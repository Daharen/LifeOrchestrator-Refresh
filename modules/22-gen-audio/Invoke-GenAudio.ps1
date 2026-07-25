#requires -Version 7.0
<#
.SYNOPSIS
  gen.audio -- generate one synthetic audio signal via ffmpeg lavfi (Life Orchestrator, contract v0.2).
.DESCRIPTION
  Deterministic, procedural audio generation (no model). One -Kind per invocation:
    tone    single sine partial (-Frequency or -Note; -Waveform sine|square|triangle|sawtooth)
    chord   several partials summed (-Frequencies or -Notes)
    noise   colored noise (-Color white|pink|brown|blue|violet|velvet; seeded, reproducible)
    sweep   linear sine chirp (-FreqStart -> -FreqEnd)
    silence digital silence
  Shaping (all): -Duration -SampleRate -Channels -Amplitude -FadeInMs -FadeOutMs.
  Output: -Format wav|mp3|flac|opus|ogg|m4a (encoded in the one ffmpeg pass; codec map == audio.ingest).
  Emits one lifeorch.skill.result/0.1 envelope on stdout; writes audio.<ext> + gen.json + gen.md.
  Diagnostics -> stderr. Exits 0 whenever a valid envelope is produced. NOT a review-queue producer.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind tone -Note A4 -Duration 1
  pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind chord -Notes "C4,E4,G4" -Format mp3
  pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -InputsJson '{"kind":"noise","color":"pink","duration":3}'
#>
[CmdletBinding()]
param(
    [string]$Kind,
    [double]$Frequency = 440.0,
    [string]$Note,
    [string]$Frequencies,
    [string]$Notes,
    [string]$Waveform = 'sine',
    [string]$Color = 'white',
    [double]$FreqStart = 200.0,
    [double]$FreqEnd = 2000.0,
    [int]$Seed = 0,
    [double]$Duration = 1.0,
    [int]$SampleRate = 44100,
    [int]$Channels = 1,
    [double]$Amplitude = 0.5,
    [int]$FadeInMs = 0,
    [int]$FadeOutMs = 0,
    [string]$Format = 'wav',
    [string]$SampleFormat = 's16',
    [string]$Bitrate,
    [string]$FfmpegPath,
    [string]$FfprobePath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'gen.audio'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[gen.audio] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Fmt($d) { return ([double]$d).ToString($inv) }
function Prop($o, [string]$n, $d = $null) {
    if ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) { return $o.$n }
    return $d
}
# Async-drained child process (avoids the pipe-fill deadlock); ArgumentList escapes each arg.
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
function Resolve-Ffmpeg([string]$override) {
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if (Test-Path -LiteralPath $override -PathType Leaf) { return (Resolve-Path -LiteralPath $override).Path }
        return $null
    }
    $gc = Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gc) { return $gc.Source }
    $cands = @(
        (Join-Path ([string]$env:LOCALAPPDATA) 'Microsoft\WinGet\Links\ffmpeg.exe'),
        'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
        'C:\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($c in $cands) { if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path } }
    return $null
}
function Resolve-Ffprobe([string]$override, [string]$ffmpegPath) {
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if (Test-Path -LiteralPath $override -PathType Leaf) { return (Resolve-Path -LiteralPath $override).Path }
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($ffmpegPath)) {
        $leaf = Split-Path -Leaf $ffmpegPath
        $probeLeaf = $leaf -replace 'ffmpeg', 'ffprobe'
        $sib = Join-Path (Split-Path -Parent $ffmpegPath) $probeLeaf
        if (Test-Path -LiteralPath $sib -PathType Leaf) { return (Resolve-Path -LiteralPath $sib).Path }
    }
    $cmds = @(Get-Command 'ffprobe' -CommandType Application -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) { if ($c.Source -notmatch '[\\/][Pp]ython[^\\/]*[\\/][Ss]cripts[\\/]') { return $c.Source } }
    if ($cmds.Count -gt 0) { return $cmds[0].Source }
    return $null
}
function Get-FfVersion([string]$exe) {
    try { $r = Invoke-Proc $exe @('-hide_banner','-version'); $first = (($r.stdout -split "`n") | Select-Object -First 1); return ([string]$first).Trim() } catch { return '' }
}
function Get-AudioProbe([string]$ffprobe, [string]$file) {
    if ([string]::IsNullOrWhiteSpace($ffprobe)) { return $null }
    $r = Invoke-Proc $ffprobe @('-v','error','-print_format','json','-show_format','-show_streams', $file)
    if ($r.exit -ne 0) { return $null }
    $j = $null
    try { $j = $r.stdout | ConvertFrom-Json } catch { return $null }
    if ($null -eq $j) { return $null }
    $astream = $null
    $streams = Prop $j 'streams' @()
    foreach ($s in @($streams)) { if ((Prop $s 'codec_type') -eq 'audio') { $astream = $s; break } }
    $audio = $null
    if ($null -ne $astream) {
        $srRaw = Prop $astream 'sample_rate'
        $sr = 0; if ($null -ne $srRaw) { [void][int]::TryParse([string]$srRaw, [ref]$sr) }
        $audio = [ordered]@{
            codec = [string](Prop $astream 'codec_name' '')
            sample_rate = $sr
            channels = [int](Prop $astream 'channels' 0)
            channel_layout = [string](Prop $astream 'channel_layout' '')
        }
    }
    $fmtObj = Prop $j 'format'
    $durRaw = Prop $fmtObj 'duration'
    $dur = $null; if ($null -ne $durRaw) { $td = 0.0; if ([double]::TryParse([string]$durRaw, [Globalization.NumberStyles]::Float, $inv, [ref]$td)) { $dur = [math]::Round($td, 3) } }
    return [ordered]@{
        format_name = [string](Prop $fmtObj 'format_name' '')
        duration_s = $dur
        audio = $audio
    }
}
# Equal-temperament note name (e.g. A4, C#3, Bb5) -> Hz. Throws on a malformed name.
function ConvertTo-NoteFreq([string]$note) {
    $t = ([string]$note).Trim()
    $m = [regex]::Match($t, '^([A-Ga-g])([#bB]?)(-?\d{1,2})$')
    if (-not $m.Success) { throw "bad note '$note'" }
    $letter = $m.Groups[1].Value.ToUpperInvariant()
    $acc = $m.Groups[2].Value
    $oct = [int]$m.Groups[3].Value
    $semi = @{ 'C'=0; 'D'=2; 'E'=4; 'F'=5; 'G'=7; 'A'=9; 'B'=11 }[$letter]
    $adj = 0
    if ($acc -eq '#') { $adj = 1 } elseif ($acc -eq 'b' -or $acc -eq 'B') { $adj = -1 }
    $midi = ($oct + 1) * 12 + $semi + $adj
    return [double](440.0 * [math]::Pow(2.0, ($midi - 69) / 12.0))
}
# Waveform expression for a single frequency f (aeval domain: t, PI, sin, floor, abs, sgn).
function Get-WaveExpr([string]$wf, [double]$f) {
    $ff = Fmt $f
    switch ($wf) {
        'sine'     { return "sin(2*PI*${ff}*t)" }
        'square'   { return "sgn(sin(2*PI*${ff}*t))" }
        'sawtooth' { return "2*(${ff}*t-floor(0.5+${ff}*t))" }
        'triangle' { return "2*abs(2*(${ff}*t-floor(${ff}*t+0.5)))-1" }
        default    { return "sin(2*PI*${ff}*t)" }
    }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validKinds = @('tone','chord','noise','sweep','silence')
$validWaveforms = @('sine','square','triangle','sawtooth')
$validColors = @('white','pink','brown','blue','violet','velvet')
$validFormats = @('wav','mp3','flac','opus','ogg','m4a')
$validSampleFmts = @('s16','s24','s32','flt')
$pcmByFmt = @{ 's16'='pcm_s16le'; 's24'='pcm_s24le'; 's32'='pcm_s32le'; 'flt'='pcm_f32le' }
$extByFmt = @{ 'wav'='wav'; 'mp3'='mp3'; 'flac'='flac'; 'opus'='opus'; 'ogg'='ogg'; 'm4a'='m4a' }
$MAX_DURATION = 3600.0
$outFull = $null; $ffmpeg = $null; $ffprobe = $null; $ffArgv = @(); $ffVersion = ''; $lavfi = $null

try {
    # ---- merge -InputsJson (named params still win where explicitly set) ----
    $sfProvided = $PSBoundParameters.ContainsKey('SampleFormat')
    $brProvided = $PSBoundParameters.ContainsKey('Bitrate')
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $pj = $InputsJson | ConvertFrom-Json
        if ($null -ne $pj) {
            $n = $pj.PSObject.Properties.Name
            if ($n -contains 'kind')        { $Kind = [string]$pj.kind }
            if ($n -contains 'frequency')   { $Frequency = [double]$pj.frequency }
            if ($n -contains 'note')        { $Note = [string]$pj.note }
            if ($n -contains 'frequencies') { $Frequencies = [string]$pj.frequencies }
            if ($n -contains 'notes')       { $Notes = [string]$pj.notes }
            if ($n -contains 'waveform')    { $Waveform = [string]$pj.waveform }
            if ($n -contains 'color')       { $Color = [string]$pj.color }
            if ($n -contains 'freq_start')  { $FreqStart = [double]$pj.freq_start }
            if ($n -contains 'freq_end')    { $FreqEnd = [double]$pj.freq_end }
            if ($n -contains 'seed')        { $Seed = [int]$pj.seed }
            if ($n -contains 'duration')    { $Duration = [double]$pj.duration }
            if ($n -contains 'sample_rate') { $SampleRate = [int]$pj.sample_rate }
            if ($n -contains 'channels')    { $Channels = [int]$pj.channels }
            if ($n -contains 'amplitude')   { $Amplitude = [double]$pj.amplitude }
            if ($n -contains 'fade_in_ms')  { $FadeInMs = [int]$pj.fade_in_ms }
            if ($n -contains 'fade_out_ms') { $FadeOutMs = [int]$pj.fade_out_ms }
            if ($n -contains 'format')      { $Format = [string]$pj.format }
            if ($n -contains 'sample_fmt')  { $SampleFormat = [string]$pj.sample_fmt; $sfProvided = $true }
            if ($n -contains 'bitrate')     { $Bitrate = [string]$pj.bitrate; $brProvided = $true }
            if ($n -contains 'ffmpeg_path') { $FfmpegPath = [string]$pj.ffmpeg_path }
            if ($n -contains 'ffprobe_path'){ $FfprobePath = [string]$pj.ffprobe_path }
        }
    }

    # ---- normalize simple fields ----
    $knd = ''; if (-not [string]::IsNullOrWhiteSpace($Kind)) { $knd = $Kind.Trim().ToLowerInvariant() }
    $wf = 'sine'; if (-not [string]::IsNullOrWhiteSpace($Waveform)) { $wf = $Waveform.Trim().ToLowerInvariant() }
    $col = 'white'; if (-not [string]::IsNullOrWhiteSpace($Color)) { $col = $Color.Trim().ToLowerInvariant() }
    $fmt = 'wav'; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }
    if ($fmt -eq 'oga') { $fmt = 'ogg' }
    $sf = 's16'; if (-not [string]::IsNullOrWhiteSpace($SampleFormat)) { $sf = $SampleFormat.Trim().ToLowerInvariant() }
    $br = ''; if (-not [string]::IsNullOrWhiteSpace($Bitrate)) { $br = $Bitrate.Trim() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{
        kind=$knd; frequency=$Frequency; note=$Note; frequencies=$Frequencies; notes=$Notes; waveform=$wf;
        color=$col; freq_start=$FreqStart; freq_end=$FreqEnd; seed=$Seed; duration=$Duration;
        sample_rate=$SampleRate; channels=$Channels; amplitude=$Amplitude; fade_in_ms=$FadeInMs;
        fade_out_ms=$FadeOutMs; format=$fmt; sample_fmt=$sf; bitrate=$br
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- resolve frequencies (from notes/frequencies/note/frequency) ----
    $freqList = New-Object System.Collections.Generic.List[double]
    $notesEcho = $null; $noteEcho = $null
    $nyquist = $SampleRate / 2.0

    # ---- validate (order matters: cheap structural checks first) ----
    if ($validKinds -notcontains $knd) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_kind'; message="kind must be one of: $($validKinds -join ', '); got '$knd'"; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_format'; message="format must be one of: $($validFormats -join ', '); got '$fmt'"; retryable=$false }
    }
    elseif (($fmt -eq 'wav') -and ($validSampleFmts -notcontains $sf)) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_sample_format'; message="sample_fmt must be one of: $($validSampleFmts -join ', '); got '$sf'"; retryable=$false }
    }
    elseif (@(1,2) -notcontains $Channels) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_channels'; message="channels must be 1 or 2; got $Channels"; retryable=$false }
    }
    elseif ($SampleRate -lt 8000 -or $SampleRate -gt 192000) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_sample_rate'; message="sample_rate must be 8000..192000; got $SampleRate"; retryable=$false }
    }
    elseif ($Amplitude -lt 0.0 -or $Amplitude -gt 1.0) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_amplitude'; message="amplitude must be 0..1; got $(Fmt $Amplitude)"; retryable=$false }
    }
    elseif ($Duration -le 0.0 -or $Duration -gt $MAX_DURATION) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_duration'; message="duration must be > 0 and <= $([int]$MAX_DURATION) s; got $(Fmt $Duration)"; retryable=$false }
    }
    elseif ($FadeInMs -lt 0 -or $FadeOutMs -lt 0) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_fade'; message="fade_in_ms/fade_out_ms must be >= 0"; retryable=$false }
    }
    elseif (($knd -in @('tone','chord','sweep')) -and ($validWaveforms -notcontains $wf)) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_waveform'; message="waveform must be one of: $($validWaveforms -join ', '); got '$wf'"; retryable=$false }
    }
    elseif (($knd -eq 'noise') -and ($validColors -notcontains $col)) {
        $status='error'; $errorObj=[ordered]@{ code='invalid_color'; message="color must be one of: $($validColors -join ', '); got '$col'"; retryable=$false }
    }
    else {
        # ---- kind-specific frequency resolution + Nyquist checks ----
        try {
            if ($knd -eq 'tone') {
                $f = $Frequency
                if (-not [string]::IsNullOrWhiteSpace($Note)) { $f = ConvertTo-NoteFreq $Note; $noteEcho = $Note.Trim() }
                $freqList.Add([double]$f)
            }
            elseif ($knd -eq 'chord') {
                if (-not [string]::IsNullOrWhiteSpace($Notes)) {
                    $notesEcho = @()
                    foreach ($nm in ($Notes -split ',')) { $t = $nm.Trim(); if ($t) { $freqList.Add((ConvertTo-NoteFreq $t)); $notesEcho += $t } }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($Frequencies)) {
                    foreach ($fs in ($Frequencies -split ',')) { $t = $fs.Trim(); if ($t) { $fv=0.0; if (-not [double]::TryParse($t,[Globalization.NumberStyles]::Float,$inv,[ref]$fv)) { throw "bad frequency '$t'" }; $freqList.Add($fv) } }
                }
                else { throw '__no_partials__' }
            }
            elseif ($knd -eq 'sweep') {
                $freqList.Add([double]$FreqStart); $freqList.Add([double]$FreqEnd)
            }
        } catch {
            $em = $_.Exception.Message
            if ($em -eq '__no_partials__') {
                $status='error'; $errorObj=[ordered]@{ code='invalid_frequencies'; message='chord requires -Notes or -Frequencies'; retryable=$false }
            } elseif ($em -like 'bad note*') {
                $status='error'; $errorObj=[ordered]@{ code='invalid_note'; message=$em; retryable=$false }
            } else {
                $status='error'; $errorObj=[ordered]@{ code='invalid_frequencies'; message=$em; retryable=$false }
            }
        }

        if ($status -eq 'ok' -and $knd -in @('tone','chord','sweep')) {
            if ($freqList.Count -eq 0) {
                $status='error'; $errorObj=[ordered]@{ code='invalid_frequencies'; message='no frequency resolved'; retryable=$false }
            } elseif ($freqList.Count -gt 24) {
                $status='error'; $errorObj=[ordered]@{ code='invalid_frequencies'; message="too many partials ($($freqList.Count)); max 24"; retryable=$false }
            } else {
                foreach ($fv in $freqList.ToArray()) {
                    if ($fv -le 0.0 -or $fv -ge $nyquist) {
                        $status='error'; $errorObj=[ordered]@{ code='frequency_out_of_range'; message="frequency $(Fmt $fv) Hz must be > 0 and < Nyquist ($(Fmt $nyquist) Hz)"; retryable=$false }
                        break
                    }
                }
            }
        }

        if ($status -eq 'ok') {
            $ffmpeg = Resolve-Ffmpeg $FfmpegPath
            if ([string]::IsNullOrWhiteSpace($ffmpeg)) {
                $status='error'; $errorObj=[ordered]@{ code='ffmpeg_not_found'; message='ffmpeg could not be resolved (not on PATH, no -FfmpegPath, no known install)'; retryable=$false }
            }
            else {
                $ffprobe = Resolve-Ffprobe $FfprobePath $ffmpeg
                $ffVersion = Get-FfVersion $ffmpeg
                if ([string]::IsNullOrWhiteSpace($ffprobe)) { $warnings.Add('ffprobe not found; output metadata will be limited') }

                # ---- build the lavfi source string ----
                $durS = Fmt $Duration
                switch ($knd) {
                    { $_ -in @('tone','chord') } {
                        $n = $freqList.Count
                        $ampOverN = Fmt ($Amplitude / [double]$n)
                        $terms = @(); foreach ($fv in $freqList.ToArray()) { $terms += (Get-WaveExpr $wf $fv) }
                        $expr = "${ampOverN}*(" + ($terms -join '+') + ")"
                        $lavfi = "aevalsrc=exprs=${expr}:s=${SampleRate}:d=${durS}"
                        break
                    }
                    'sweep' {
                        $ampS = Fmt $Amplitude; $f0 = Fmt $FreqStart; $f1 = Fmt $FreqEnd; $T = $durS
                        $expr = "${ampS}*sin(2*PI*(${f0}*t+(${f1}-${f0})/(2*${T})*t*t))"
                        $lavfi = "aevalsrc=exprs=${expr}:s=${SampleRate}:d=${durS}"
                        break
                    }
                    'noise' {
                        $ampS = Fmt $Amplitude
                        $lavfi = "anoisesrc=color=${col}:amplitude=${ampS}:seed=${Seed}:duration=${durS}:sample_rate=${SampleRate}"
                        break
                    }
                    'silence' {
                        $cl = if ($Channels -eq 2) { 'stereo' } else { 'mono' }
                        $lavfi = "anullsrc=r=${SampleRate}:cl=${cl}"
                        break
                    }
                }

                # ---- build ffmpeg argv ----
                $argv = New-Object System.Collections.Generic.List[string]
                $argv.Add('-hide_banner'); $argv.Add('-nostdin'); $argv.Add('-y')
                $argv.Add('-f'); $argv.Add('lavfi'); $argv.Add('-i'); $argv.Add($lavfi)
                $argv.Add('-t'); $argv.Add($durS)

                # fades
                if ($FadeInMs -gt 0 -or $FadeOutMs -gt 0) {
                    $afParts = @()
                    if ($FadeInMs -gt 0)  { $afParts += "afade=t=in:st=0:d=$(Fmt ($FadeInMs/1000.0))" }
                    if ($FadeOutMs -gt 0) {
                        $st = $Duration - ($FadeOutMs/1000.0); if ($st -lt 0) { $st = 0 }
                        $afParts += "afade=t=out:st=$(Fmt $st):d=$(Fmt ($FadeOutMs/1000.0))"
                    }
                    $argv.Add('-af'); $argv.Add(($afParts -join ','))
                }

                # libopus only accepts a fixed set of rates; resample the output to 48 kHz otherwise.
                $arRate = $SampleRate
                if ($fmt -eq 'opus' -and (@(8000,12000,16000,24000,48000) -notcontains $SampleRate)) {
                    $arRate = 48000
                    $warnings.Add("opus requires sample_rate in {8000,12000,16000,24000,48000}; output resampled to 48000 (requested $SampleRate)")
                }
                $argv.Add('-ar'); $argv.Add([string]$arRate)
                $argv.Add('-ac'); $argv.Add([string]$Channels)

                $codec = ''
                switch ($fmt) {
                    'wav'  { $codec = $pcmByFmt[$sf]; $argv.Add('-c:a'); $argv.Add($codec) }
                    'flac' { $codec = 'flac'; $argv.Add('-c:a'); $argv.Add($codec) }
                    'mp3'  { $codec = 'libmp3lame'; $argv.Add('-c:a'); $argv.Add($codec); if (-not $br) { $br = '192k' }; $argv.Add('-b:a'); $argv.Add($br) }
                    'm4a'  { $codec = 'aac';        $argv.Add('-c:a'); $argv.Add($codec); if (-not $br) { $br = '192k' }; $argv.Add('-b:a'); $argv.Add($br) }
                    'opus' { $codec = 'libopus';    $argv.Add('-c:a'); $argv.Add($codec); if (-not $br) { $br = '96k' };  $argv.Add('-b:a'); $argv.Add($br) }
                    'ogg'  { $codec = 'libvorbis';  $argv.Add('-c:a'); $argv.Add($codec); if ($br) { $argv.Add('-b:a'); $argv.Add($br) } else { $argv.Add('-q:a'); $argv.Add('5') } }
                }
                $argv.Add('-map_metadata'); $argv.Add('-1')
                if ($fmt -eq 'wav') { $argv.Add('-bitexact') }

                $ext = $extByFmt[$fmt]
                $outFull = Join-Path $invDir ("audio." + $ext)
                $argv.Add($outFull)
                $ffArgv = $argv.ToArray()

                Write-Diag "kind=$knd fmt=$fmt sr=$SampleRate ch=$Channels dur=$durS -> $outFull"
                Write-Diag "lavfi=$lavfi"
                $run = Invoke-Proc $ffmpeg $ffArgv

                if ($run.exit -ne 0 -or -not (Test-Path -LiteralPath $outFull -PathType Leaf)) {
                    $tail = ''
                    if ($run.stderr) { $tail = if ($run.stderr.Length -gt 700) { $run.stderr.Substring($run.stderr.Length - 700) } else { $run.stderr } }
                    $status='error'; $errorObj=[ordered]@{ code='ffmpeg_failed'; message="ffmpeg exited $($run.exit): $($tail.Trim())"; retryable=$true }
                    Write-Diag "ffmpeg_failed exit=$($run.exit)"
                }
                else {
                    $outBytes = [System.IO.File]::ReadAllBytes($outFull)
                    $outProbe = Get-AudioProbe $ffprobe $outFull
                    $outCodec = $codec; $outSr = $SampleRate; $outCh = $Channels; $outDur = $null
                    if ($null -ne $outProbe -and $null -ne $outProbe.audio) {
                        if ($outProbe.audio.codec)       { $outCodec = $outProbe.audio.codec }
                        if ($outProbe.audio.sample_rate) { $outSr = [int]$outProbe.audio.sample_rate }
                        if ($outProbe.audio.channels)    { $outCh = [int]$outProbe.audio.channels }
                        $outDur = $outProbe.duration_s
                    }

                    # ---- generation echo (kind-specific) ----
                    $gen = [ordered]@{ kind = $knd }
                    if ($knd -in @('tone','chord')) {
                        $gen.waveform = $wf
                        $gen.frequencies = @($freqList.ToArray() | ForEach-Object { [math]::Round($_, 4) })
                        if ($null -ne $noteEcho) { $gen.note = $noteEcho }
                        if ($null -ne $notesEcho) { $gen.notes = @($notesEcho) }
                    }
                    elseif ($knd -eq 'sweep') { $gen.waveform = 'sine'; $gen.freq_start = $FreqStart; $gen.freq_end = $FreqEnd }
                    elseif ($knd -eq 'noise') { $gen.color = $col; $gen.seed = $Seed }
                    $gen.duration_s = $Duration
                    $gen.sample_rate = $SampleRate
                    $gen.channels = $Channels
                    $gen.amplitude = $Amplitude
                    $gen.fade_in_ms = $FadeInMs
                    $gen.fade_out_ms = $FadeOutMs

                    $result = [ordered]@{
                        generation = $gen
                        output = [ordered]@{
                            path = (Resolve-Path -LiteralPath $outFull).Path
                            format = $fmt
                            container = $ext
                            codec = $outCodec
                            sample_rate = $outSr
                            channels = $outCh
                            sample_fmt = $(if ($fmt -eq 'wav') { $sf } else { $null })
                            bitrate = $(if ($br) { $br } else { $null })
                            duration_s = $outDur
                            bytes = $outBytes.Length
                            sha256 = (Get-Sha256Hex $outBytes)
                            probe = $outProbe
                        }
                        source = [ordered]@{ lavfi = $lavfi }
                        ffmpeg = [ordered]@{ path = $ffmpeg; version = $ffVersion; argv = $ffArgv }
                        ffprobe = [ordered]@{ path = $ffprobe }
                    }
                }
            }
        }
    }

    if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }
}
catch {
    $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $genJson = [ordered]@{ schema='lifeorch.gen.audio/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $gjPath = Join-Path $invDir 'gen.json'
        [System.IO.File]::WriteAllText($gjPath, ($genJson | ConvertTo-Json -Depth 15), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# gen.audio - $($result.generation.kind)  ($($result.output.format) / $($result.output.sample_rate) Hz / $($result.output.channels) ch)")
        [void]$mb.AppendLine("output: $($result.output.path)")
        [void]$mb.AppendLine("  codec=$($result.output.codec)  dur=$($result.output.duration_s)s  bytes=$($result.output.bytes)  sha256=$($result.output.sha256)")
        [void]$mb.AppendLine("source: $($result.source.lavfi)")
        [void]$mb.AppendLine("ffmpeg: $($result.ffmpeg.path)")
        [void]$mb.AppendLine("argv:   ffmpeg $((@($result.ffmpeg.argv)) -join ' ')")
        if ($null -ne $errorObj) { [void]$mb.AppendLine("error: $($errorObj.code) - $($errorObj.message)") }
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $gmPath = Join-Path $invDir 'gen.md'
        [System.IO.File]::WriteAllText($gmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        if ($null -ne $outFull -and (Test-Path -LiteralPath $outFull -PathType Leaf)) {
            $artList.Add([pscustomobject]@{ p=$outFull; k=$result.output.format })
        }
        $artList.Add([pscustomobject]@{ p=$gmPath; k='markdown' })
        $artList.Add([pscustomobject]@{ p=$gjPath; k='json' })
        foreach ($a in $artList.ToArray()) {
            $b = [System.IO.File]::ReadAllBytes($a.p)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[gen.audio] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds; inputs_digest=$inputsDigest
    result=$result; confidence=$null; artifacts=$artifacts; model_provenance=@()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
