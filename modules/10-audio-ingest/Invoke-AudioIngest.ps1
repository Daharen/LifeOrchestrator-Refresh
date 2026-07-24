#requires -Version 7.0
<#
.SYNOPSIS
  audio.ingest — normalize & convert one audio/media file via ffmpeg (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Wraps ffmpeg/ffprobe to turn a single input (any container ffmpeg can decode; first audio stream) into
  a requested format + sample rate + channel count + sample format, with optional loudness normalization
  (peak or EBU R128). Defaults produce whisper-ready 16 kHz mono s16 WAV. Deterministic (no model):
  emits one lifeorch.skill.result/0.1 envelope on stdout and writes audio.<ext> + ingest.json + ingest.md.
  Diagnostics go to stderr. Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile .\clip.mp3
  pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile .\clip.wav -Format mp3 -Bitrate 192k
  pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputsJson '{"input":"clip.m4a","format":"flac","loudness":"ebu"}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Format = 'wav',
    [int]$SampleRate = 16000,
    [int]$Channels = 1,
    [string]$SampleFormat = 's16',
    [string]$Loudness = 'none',
    [double]$PeakDb = -1.0,
    [double]$LoudnessI = -16.0,
    [double]$LoudnessTP = -1.5,
    [double]$LoudnessLRA = 11.0,
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

$SKILL_ID = 'audio.ingest'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[audio.ingest] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Fmt([double]$d) { return ([double]$d).ToString($inv) }
function Prop($o, [string]$n, $d = $null) {
    if ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) { return $o.$n }
    return $d
}
# Run a child process with both streams drained asynchronously (avoids the pipe-fill deadlock);
# ProcessStartInfo.ArgumentList escapes each argument individually (spaces in paths are safe).
function Invoke-Proc([string]$exe, [string[]]$argv) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    foreach ($a in $argv) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $out = $so.GetAwaiter().GetResult()
    $err = $se.GetAwaiter().GetResult()
    $code = $p.ExitCode
    $p.Dispose()
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
    # Prefer the sibling of the resolved ffmpeg (dodges the Python Scripts\ffprobe.exe shim on PATH).
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
        $brRaw = Prop $astream 'bit_rate'
        $br = $null; if ($null -ne $brRaw) { $tmp = 0L; if ([long]::TryParse([string]$brRaw, [ref]$tmp)) { $br = $tmp } }
        $audio = [ordered]@{
            codec = [string](Prop $astream 'codec_name' '')
            sample_rate = $sr
            channels = [int](Prop $astream 'channels' 0)
            channel_layout = [string](Prop $astream 'channel_layout' '')
            bit_rate = $br
        }
    }
    $fmtObj = Prop $j 'format'
    $durRaw = Prop $fmtObj 'duration'
    $dur = $null; if ($null -ne $durRaw) { $td = 0.0; if ([double]::TryParse([string]$durRaw, [Globalization.NumberStyles]::Float, $inv, [ref]$td)) { $dur = [math]::Round($td, 3) } }
    $sizeRaw = Prop $fmtObj 'size'
    $size = $null; if ($null -ne $sizeRaw) { $ts = 0L; if ([long]::TryParse([string]$sizeRaw, [ref]$ts)) { $size = $ts } }
    $fbrRaw = Prop $fmtObj 'bit_rate'
    $fbr = $null; if ($null -ne $fbrRaw) { $tb = 0L; if ([long]::TryParse([string]$fbrRaw, [ref]$tb)) { $fbr = $tb } }
    return [ordered]@{
        audio_stream_present = ($null -ne $astream)
        format_name = [string](Prop $fmtObj 'format_name' '')
        duration_s = $dur
        size_bytes = $size
        bit_rate = $fbr
        audio = $audio
    }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validFormats = @('wav','mp3','flac','opus','ogg','m4a')
$validSampleFmts = @('s16','s24','s32','flt')
$validLoudness = @('none','peak','ebu')
$pcmByFmt = @{ 's16'='pcm_s16le'; 's24'='pcm_s24le'; 's32'='pcm_s32le'; 'flt'='pcm_f32le' }
$extByFmt = @{ 'wav'='wav'; 'mp3'='mp3'; 'flac'='flac'; 'opus'='opus'; 'ogg'='ogg'; 'm4a'='m4a' }
$outFull = $null; $ffmpeg = $null; $ffprobe = $null; $ffArgv = @(); $ffVersion = ''

try {
    # ---- merge -InputsJson (named params still win where explicitly set) ----
    $sfProvided = $PSBoundParameters.ContainsKey('SampleFormat')
    $brProvided = $PSBoundParameters.ContainsKey('Bitrate')
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $n = $p.PSObject.Properties.Name
            if ($n -contains 'input')         { $InputFile = [string]$p.input }
            if ($n -contains 'format')        { $Format = [string]$p.format }
            if ($n -contains 'sample_rate')   { $SampleRate = [int]$p.sample_rate }
            if ($n -contains 'channels')      { $Channels = [int]$p.channels }
            if ($n -contains 'sample_fmt')    { $SampleFormat = [string]$p.sample_fmt; $sfProvided = $true }
            if ($n -contains 'loudness')      { $Loudness = [string]$p.loudness }
            if ($n -contains 'peak_db')       { $PeakDb = [double]$p.peak_db }
            if ($n -contains 'loudness_i')    { $LoudnessI = [double]$p.loudness_i }
            if ($n -contains 'loudness_tp')   { $LoudnessTP = [double]$p.loudness_tp }
            if ($n -contains 'loudness_lra')  { $LoudnessLRA = [double]$p.loudness_lra }
            if ($n -contains 'bitrate')       { $Bitrate = [string]$p.bitrate; $brProvided = $true }
            if ($n -contains 'ffmpeg_path')   { $FfmpegPath = [string]$p.ffmpeg_path }
            if ($n -contains 'ffprobe_path')  { $FfprobePath = [string]$p.ffprobe_path }
        }
    }

    # ---- normalize simple fields ----
    $fmt = ''; if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }
    if ($fmt -eq 'jpeg') { }  # (no-op guard; formats normalized below)
    if ($fmt -eq 'oga') { $fmt = 'ogg' }
    $sf = 's16'; if (-not [string]::IsNullOrWhiteSpace($SampleFormat)) { $sf = $SampleFormat.Trim().ToLowerInvariant() }
    $loud = 'none'; if (-not [string]::IsNullOrWhiteSpace($Loudness)) { $loud = $Loudness.Trim().ToLowerInvariant() }
    $br = ''; if (-not [string]::IsNullOrWhiteSpace($Bitrate)) { $br = $Bitrate.Trim() }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{
        input=$InputFile; format=$fmt; sample_rate=$SampleRate; channels=$Channels; sample_fmt=$sf;
        loudness=$loud; peak_db=$PeakDb; loudness_i=$LoudnessI; loudness_tp=$LoudnessTP; loudness_lra=$LoudnessLRA;
        bitrate=$br
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message='no input file specified (-InputFile or InputsJson.input)'; retryable=$false }
    }
    elseif (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        $status = 'error'; $errorObj = [ordered]@{ code='input_not_found'; message="input file not found: $InputFile"; retryable=$false }
    }
    elseif ($validFormats -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="unknown format '$fmt'; expected one of: $($validFormats -join ', ')"; retryable=$false }
    }
    elseif (@(0,1,2) -notcontains $Channels) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_channels'; message="channels must be 1, 2, or 0 (keep source); got $Channels"; retryable=$false }
    }
    elseif ($SampleRate -lt 0) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_sample_rate'; message="sample_rate must be >= 0 (0 keeps source); got $SampleRate"; retryable=$false }
    }
    elseif (($fmt -eq 'wav') -and ($validSampleFmts -notcontains $sf)) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_sample_format'; message="sample_fmt must be one of: $($validSampleFmts -join ', '); got '$sf'"; retryable=$false }
    }
    elseif ($validLoudness -notcontains $loud) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_loudness'; message="loudness must be one of: $($validLoudness -join ', '); got '$loud'"; retryable=$false }
    }
    else {
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path
        $ffmpeg = Resolve-Ffmpeg $FfmpegPath
        if ([string]::IsNullOrWhiteSpace($ffmpeg)) {
            $status = 'error'; $errorObj = [ordered]@{ code='ffmpeg_not_found'; message='ffmpeg could not be resolved (not on PATH, no -FfmpegPath, no known install)'; retryable=$false }
        }
        else {
            $ffprobe = Resolve-Ffprobe $FfprobePath $ffmpeg
            $ffVersion = Get-FfVersion $ffmpeg
            if ([string]::IsNullOrWhiteSpace($ffprobe)) { $warnings.Add('ffprobe not found; input/output metadata will be limited') }

            # ---- probe input ----
            $inProbe = Get-AudioProbe $ffprobe $inFull
            $audioPresent = $true
            if ($null -ne $inProbe) { $audioPresent = [bool]$inProbe.audio_stream_present }

            if (($null -ne $inProbe) -and (-not $audioPresent)) {
                $status = 'error'; $errorObj = [ordered]@{ code='no_audio_stream'; message="input has no audio stream: $inFull"; retryable=$false }
            }
            else {
                # ---- ignored-parameter warnings ----
                if (($fmt -ne 'wav') -and $sfProvided) { $warnings.Add("sample_fmt '$sf' ignored for format '$fmt' (applies to wav only)") }
                if ((@('wav','flac') -contains $fmt) -and $brProvided -and $br) { $warnings.Add("bitrate '$br' ignored for lossless format '$fmt'") }

                # ---- optional peak measurement pass ----
                $measuredMax = $null; $appliedGain = $null
                if ($loud -eq 'peak') {
                    $vd = Invoke-Proc $ffmpeg @('-hide_banner','-nostdin','-i',$inFull,'-map','0:a:0','-af','volumedetect','-f','null','-')
                    foreach ($ln in ($vd.stderr -split "`n")) {
                        if ($ln -match 'max_volume:\s*(-?\d+(?:\.\d+)?)\s*dB') { $measuredMax = [double]$Matches[1] }
                    }
                    if ($null -ne $measuredMax) { $appliedGain = [math]::Round(($PeakDb - $measuredMax), 3) }
                    else { $warnings.Add('could not measure peak (volumedetect); skipping peak gain') }
                }

                # ---- build ffmpeg argument vector ----
                $argv = New-Object System.Collections.Generic.List[string]
                $argv.Add('-hide_banner'); $argv.Add('-nostdin'); $argv.Add('-y')
                $argv.Add('-i'); $argv.Add($inFull)
                $argv.Add('-vn')
                $argv.Add('-map'); $argv.Add('0:a:0')

                $afParts = New-Object System.Collections.Generic.List[string]
                if ($loud -eq 'ebu') {
                    $afParts.Add("loudnorm=I=$(Fmt $LoudnessI):TP=$(Fmt $LoudnessTP):LRA=$(Fmt $LoudnessLRA)")
                }
                elseif (($loud -eq 'peak') -and ($null -ne $appliedGain)) {
                    $afParts.Add("volume=$(Fmt $appliedGain)dB")
                }
                if ($afParts.Count -gt 0) { $argv.Add('-af'); $argv.Add(($afParts.ToArray() -join ',')) }

                if ($SampleRate -gt 0) { $argv.Add('-ar'); $argv.Add([string]$SampleRate) }
                if ($Channels -gt 0)   { $argv.Add('-ac'); $argv.Add([string]$Channels) }

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

                Write-Diag "ffmpeg=$ffmpeg fmt=$fmt sr=$SampleRate ch=$Channels loud=$loud -> $outFull"
                $run = Invoke-Proc $ffmpeg $ffArgv

                if ($run.exit -ne 0 -or -not (Test-Path -LiteralPath $outFull -PathType Leaf)) {
                    $tail = ''
                    if ($run.stderr) { $tail = if ($run.stderr.Length -gt 700) { $run.stderr.Substring($run.stderr.Length - 700) } else { $run.stderr } }
                    $status = 'error'; $errorObj = [ordered]@{ code='ffmpeg_failed'; message="ffmpeg exited $($run.exit): $($tail.Trim())"; retryable=$true }
                    Write-Diag "ffmpeg_failed exit=$($run.exit)"
                }
                else {
                    $outBytes = [System.IO.File]::ReadAllBytes($outFull)
                    $outProbe = Get-AudioProbe $ffprobe $outFull
                    $outCodec = $codec; $outSr = $(if ($SampleRate -gt 0) { $SampleRate } else { 0 }); $outCh = $(if ($Channels -gt 0) { $Channels } else { 0 }); $outDur = $null
                    if ($null -ne $outProbe -and $null -ne $outProbe.audio) {
                        if ($outProbe.audio.codec)       { $outCodec = $outProbe.audio.codec }
                        if ($outProbe.audio.sample_rate) { $outSr = [int]$outProbe.audio.sample_rate }
                        if ($outProbe.audio.channels)    { $outCh = [int]$outProbe.audio.channels }
                        $outDur = $outProbe.duration_s
                    }

                    $loudObj = [ordered]@{ mode = $loud }
                    if ($loud -eq 'ebu') { $loudObj.i = $LoudnessI; $loudObj.tp = $LoudnessTP; $loudObj.lra = $LoudnessLRA }
                    elseif ($loud -eq 'peak') { $loudObj.peak_db = $PeakDb; $loudObj.measured_max_volume_db = $measuredMax; $loudObj.applied_gain_db = $appliedGain }

                    $result = [ordered]@{
                        input = [ordered]@{
                            path = $inFull
                            exists = $true
                            audio_stream_present = $audioPresent
                            probe = $inProbe
                        }
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
                        normalization = [ordered]@{
                            sample_rate = $(if ($SampleRate -gt 0) { $SampleRate } else { 'source' })
                            channels = $(if ($Channels -gt 0) { $Channels } else { 'source' })
                            sample_fmt = $(if ($fmt -eq 'wav') { $sf } else { $null })
                            loudness = $loudObj
                        }
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
        $ingestJson = [ordered]@{ schema='lifeorch.audio.ingest/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $ijPath = Join-Path $invDir 'ingest.json'
        [System.IO.File]::WriteAllText($ijPath, ($ingestJson | ConvertTo-Json -Depth 15), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# audio.ingest — $($result.output.format)  ($($result.output.sample_rate) Hz / $($result.output.channels) ch)")
        [void]$mb.AppendLine("input:  $($result.input.path)")
        if ($null -ne $result.input.probe) {
            $ip = $result.input.probe
            $ia = $ip.audio
            $iaStr = if ($null -ne $ia) { "$($ia.codec) $($ia.sample_rate)Hz $($ia.channels)ch" } else { '(no audio stream)' }
            [void]$mb.AppendLine("  in probe: $($ip.format_name)  dur=$($ip.duration_s)s  $iaStr")
        }
        [void]$mb.AppendLine("output: $($result.output.path)")
        [void]$mb.AppendLine("  codec=$($result.output.codec)  sample_fmt=$($result.output.sample_fmt)  bitrate=$($result.output.bitrate)  dur=$($result.output.duration_s)s  bytes=$($result.output.bytes)")
        $ln = $result.normalization.loudness
        [void]$mb.AppendLine("  loudness: $($ln.mode)")
        [void]$mb.AppendLine("ffmpeg: $($result.ffmpeg.path)")
        [void]$mb.AppendLine("argv:   ffmpeg $((@($result.ffmpeg.argv)) -join ' ')")
        if ($null -ne $errorObj) { [void]$mb.AppendLine("error: $($errorObj.code) — $($errorObj.message)") }
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $imPath = Join-Path $invDir 'ingest.md'
        [System.IO.File]::WriteAllText($imPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        if ($null -ne $outFull -and (Test-Path -LiteralPath $outFull -PathType Leaf)) {
            $artList.Add([pscustomobject]@{ p=$outFull; k=$result.output.format })
        }
        $artList.Add([pscustomobject]@{ p=$imPath; k='markdown' })
        $artList.Add([pscustomobject]@{ p=$ijPath; k='json' })
        foreach ($a in $artList.ToArray()) {
            $b = [System.IO.File]::ReadAllBytes($a.p)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[audio.ingest] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
