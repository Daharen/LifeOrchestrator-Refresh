#requires -Version 7.0
<#
.SYNOPSIS
  media.decompose -- decompose one video/media file into parts via ffmpeg/ffprobe (Life Orchestrator, contract v0.2).
.DESCRIPTION
  The VIDEO analog of audio.ingest #10 and image.util #15, and the first module of the Phase C video spine
  (architectural position 19). Always returns structured ffprobe metadata (container + per-stream
  codec/resolution/fps/pixel-format/bitrate/channels/sample-rate + stream counts). Opt-in flags add:
    -Audio        extract the primary audio track to WAV by COMPOSING audio.ingest #10 (default whisper-ready
                  16 kHz mono s16; -AudioFormat / -Loudness passthrough). Reports no_audio_stream cleanly.
    -Keyframes N  extract up to N representative frames as PNGs -- scene-change preferred (select gt(scene,thr)),
                  else evenly spaced -- with a deterministic frame-index+timestamp sidecar JSON.
    -Scenes       scene-change detection -> a JSON list of {index,start,end,score}.
  Deterministic (a fixed decode of fixed bytes; no model -> confidence null). CPU-only, parallel_safe:true
  (reads an input, writes only to its own invocation artifact dir; no CUDA / model / loopback port).
  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; exits 0 whenever a valid
  envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputFile .\clip.mp4
  pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputFile .\clip.mp4 -Audio -Keyframes 5 -Scenes
  pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputsJson '{"input":"clip.mkv","audio":true,"scenes":true}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [switch]$Audio,
    [string]$AudioFormat = 'wav',
    [string]$Loudness = 'none',
    [int]$Keyframes = 0,
    [switch]$Scenes,
    [double]$SceneThreshold = 0.4,
    [string]$FfmpegPath,
    [string]$FfprobePath,
    [string]$AudioIngestPath,
    [string]$PwshPath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'media.decompose'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[media.decompose] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Fmt([double]$d) { return ([double]$d).ToString($inv) }
function ToDouble($v) { # invariant parse; $null when unparseable
    if ($null -eq $v) { return $null }
    $d = 0.0
    if ([double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { return $d }
    return $null
}
function ToLong($v) {
    if ($null -eq $v) { return $null }
    $l = 0L
    if ([long]::TryParse([string]$v, [ref]$l)) { return $l }
    return $null
}
# Run a child process with both streams drained asynchronously (avoids the pipe-fill deadlock; ffmpeg logs
# plenty to stderr). ArgumentList escapes each argument individually (spaces in paths are safe).
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
    # Prefer the sibling of the resolved ffmpeg (dodges the Python Scripts\ffprobe.exe shim on PATH -- CRITICAL).
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
# Resolve a pwsh to spawn audio.ingest as an ISOLATED process (so its envelope does not pollute our stdout).
function Resolve-Pwsh([string]$override) {
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($override)) { $cands.Add($override) }
    $exe = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    if (-not [string]::IsNullOrWhiteSpace($PSHOME)) { $cands.Add((Join-Path $PSHOME $exe)) }
    $gc = Get-Command 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gc) { $cands.Add($gc.Source) }
    $cands.Add('C:\Users\just_\.dotnet\tools\pwsh.exe')
    foreach ($c in $cands.ToArray()) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}
function ParseRate([string]$r) { # "30/1" -> 30.0 ; "0/0" -> $null
    if ([string]::IsNullOrWhiteSpace($r)) { return $null }
    if ($r -match '^\s*(-?\d+(?:\.\d+)?)\s*/\s*(-?\d+(?:\.\d+)?)\s*$') {
        $n = [double]$Matches[1]; $d = [double]$Matches[2]
        if ($d -eq 0) { return $null }
        return [math]::Round($n / $d, 6)
    }
    $one = ToDouble $r; return $one
}
# Detect scene-change boundaries: returns an array of [pscustomobject]{ time; score } in chronological order.
function Get-SceneChanges([string]$ffmpeg, [string]$file, [double]$thr) {
    $acc = New-Object System.Collections.Generic.List[object]
    $vf = "select='gt(scene,$(Fmt $thr))',metadata=print"
    $r = Invoke-Proc $ffmpeg @('-hide_banner','-nostdin','-loglevel','info','-i',$file,'-an','-vf',$vf,'-f','null','-')
    $pendingTime = $null
    foreach ($ln in ($r.stderr -split "`n")) {
        if ($ln -match 'pts_time:([0-9]+(?:\.[0-9]+)?)') { $pendingTime = [double]$Matches[1]; continue }
        if ($ln -match 'lavfi\.scene_score=([0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)') {
            $score = [double]$Matches[1]
            if ($null -ne $pendingTime) { $acc.Add([pscustomobject]@{ time = [math]::Round($pendingTime,6); score = [math]::Round($score,6) }); $pendingTime = $null }
        }
    }
    return $acc.ToArray()
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$confidence = $null; $modelProvenance = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validAudioFormats = @('wav','mp3','flac','opus','ogg','m4a')
$validLoudness = @('none','peak','ebu')
$ffmpeg = $null; $ffprobe = $null; $ffVersion = ''
$metaObj = $null; $audioObj = $null; $keyframesObj = $null; $scenesObj = $null
$kfSidecarPath = $null; $scenesJsonPath = $null; $metaJsonPath = $null
$producedFiles = New-Object System.Collections.Generic.List[object]  # {p;k}

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
    }
    if ($null -ne $p) {
        if ((Has $p 'input')             -and -not $bound.ContainsKey('InputFile'))       { $InputFile = [string]$p.input }
        if ((Has $p 'audio')             -and -not $bound.ContainsKey('Audio'))           { if ([bool]$p.audio) { $Audio = [switch]$true } }
        if ((Has $p 'audio_format')      -and -not $bound.ContainsKey('AudioFormat'))     { $AudioFormat = [string]$p.audio_format }
        if ((Has $p 'loudness')          -and -not $bound.ContainsKey('Loudness'))        { $Loudness = [string]$p.loudness }
        if ((Has $p 'keyframes')         -and -not $bound.ContainsKey('Keyframes'))       { $Keyframes = [int]$p.keyframes }
        if ((Has $p 'scenes')            -and -not $bound.ContainsKey('Scenes'))          { if ([bool]$p.scenes) { $Scenes = [switch]$true } }
        if ((Has $p 'scene_threshold')   -and -not $bound.ContainsKey('SceneThreshold'))  { $SceneThreshold = [double]$p.scene_threshold }
        if ((Has $p 'ffmpeg_path')       -and -not $bound.ContainsKey('FfmpegPath'))      { $FfmpegPath = [string]$p.ffmpeg_path }
        if ((Has $p 'ffprobe_path')      -and -not $bound.ContainsKey('FfprobePath'))     { $FfprobePath = [string]$p.ffprobe_path }
        if ((Has $p 'audio_ingest_path') -and -not $bound.ContainsKey('AudioIngestPath')) { $AudioIngestPath = [string]$p.audio_ingest_path }
        if ((Has $p 'pwsh_path')         -and -not $bound.ContainsKey('PwshPath'))        { $PwshPath = [string]$p.pwsh_path }
    }

    # ---- normalize simple fields ----
    $afmt = 'wav'; if (-not [string]::IsNullOrWhiteSpace($AudioFormat)) { $afmt = $AudioFormat.Trim().ToLowerInvariant() }
    $loud = 'none'; if (-not [string]::IsNullOrWhiteSpace($Loudness)) { $loud = $Loudness.Trim().ToLowerInvariant() }
    if ($Keyframes -lt 0) { $Keyframes = 0 }

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{
        input=$InputFile; audio=[bool]$Audio; audio_format=$afmt; loudness=$loud;
        keyframes=[int]$Keyframes; scenes=[bool]$Scenes; scene_threshold=[double]$SceneThreshold
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- validate ----
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        throw [PSCustomObject]@{ code='input_not_found'; message='no input file specified (-InputFile or InputsJson.input)'; retryable=$false }
    }
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        throw [PSCustomObject]@{ code='input_not_found'; message="input file not found: $InputFile"; retryable=$false }
    }
    if ($validAudioFormats -notcontains $afmt) {
        throw [PSCustomObject]@{ code='invalid_audio_format'; message="unknown audio_format '$afmt'; expected one of: $($validAudioFormats -join ', ')"; retryable=$false }
    }
    if ($validLoudness -notcontains $loud) {
        throw [PSCustomObject]@{ code='invalid_loudness'; message="loudness must be one of: $($validLoudness -join ', '); got '$loud'"; retryable=$false }
    }
    if ($SceneThreshold -lt 0 -or $SceneThreshold -gt 1) {
        throw [PSCustomObject]@{ code='invalid_scene_threshold'; message="scene_threshold must be within 0..1; got $SceneThreshold"; retryable=$false }
    }

    $inFull = (Resolve-Path -LiteralPath $InputFile).Path
    $inBytes = (Get-Item -LiteralPath $inFull).Length
    $ffmpeg = Resolve-Ffmpeg $FfmpegPath
    if ([string]::IsNullOrWhiteSpace($ffmpeg)) {
        throw [PSCustomObject]@{ code='ffmpeg_not_found'; message='ffmpeg could not be resolved (not on PATH, no -FfmpegPath, no known install)'; retryable=$false }
    }
    $ffprobe = Resolve-Ffprobe $FfprobePath $ffmpeg
    if ([string]::IsNullOrWhiteSpace($ffprobe)) {
        throw [PSCustomObject]@{ code='ffprobe_not_found'; message='ffprobe could not be resolved (sibling of ffmpeg / non-Python-shim ffprobe)'; retryable=$false }
    }
    $ffVersion = Get-FfVersion $ffmpeg

    # ================= META (always) =================
    $probe = Invoke-Proc $ffprobe @('-v','error','-print_format','json','-show_format','-show_streams',$inFull)
    if ($probe.exit -ne 0) {
        $tail = [string]$probe.stderr; if ($tail.Length -gt 600) { $tail = $tail.Substring($tail.Length - 600) }
        throw [PSCustomObject]@{ code='ffprobe_failed'; message="ffprobe exited $($probe.exit): $($tail.Trim())"; retryable=$true }
    }
    $pj = $null
    try { $pj = $probe.stdout | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='ffprobe_parse_failed'; message='ffprobe JSON did not parse'; retryable=$false } }

    $fmtO = Prop $pj 'format'
    $container = [ordered]@{
        format_name      = [string](Prop $fmtO 'format_name' '')
        format_long_name = [string](Prop $fmtO 'format_long_name' '')
        duration_s       = (ToDouble (Prop $fmtO 'duration'))
        size_bytes       = (ToLong (Prop $fmtO 'size'))
        bit_rate         = (ToLong (Prop $fmtO 'bit_rate'))
        nb_streams       = [int](Prop $fmtO 'nb_streams' 0)
    }
    $streamList = New-Object System.Collections.Generic.List[object]
    $cV=0;$cA=0;$cS=0;$cD=0;$cO=0
    foreach ($s in @(Prop $pj 'streams' @())) {
        $ct = [string](Prop $s 'codec_type' '')
        $entry = [ordered]@{
            index      = [int](Prop $s 'index' 0)
            codec_type = $ct
            codec_name = [string](Prop $s 'codec_name' '')
            codec_long_name = [string](Prop $s 'codec_long_name' '')
        }
        switch ($ct) {
            'video' {
                $cV++
                $entry.width      = [int](Prop $s 'width' 0)
                $entry.height     = [int](Prop $s 'height' 0)
                $entry.pix_fmt    = [string](Prop $s 'pix_fmt' '')
                $entry.r_frame_rate   = [string](Prop $s 'r_frame_rate' '')
                $entry.avg_frame_rate = [string](Prop $s 'avg_frame_rate' '')
                $entry.fps        = (ParseRate ([string](Prop $s 'r_frame_rate' '')))
                $entry.nb_frames  = (ToLong (Prop $s 'nb_frames'))
                $entry.bit_rate   = (ToLong (Prop $s 'bit_rate'))
                $entry.duration_s = (ToDouble (Prop $s 'duration'))
            }
            'audio' {
                $cA++
                $entry.sample_rate    = [int]((ToLong (Prop $s 'sample_rate')) ?? 0)
                $entry.channels       = [int](Prop $s 'channels' 0)
                $entry.channel_layout = [string](Prop $s 'channel_layout' '')
                $entry.sample_fmt     = [string](Prop $s 'sample_fmt' '')
                $entry.bit_rate       = (ToLong (Prop $s 'bit_rate'))
                $entry.duration_s     = (ToDouble (Prop $s 'duration'))
            }
            'subtitle' {
                $cS++
                $tags = Prop $s 'tags'
                $entry.language = [string](Prop $tags 'language' '')
            }
            'data' { $cD++ }
            default { $cO++ }
        }
        $streamList.Add($entry)
    }
    $durationS = $container.duration_s
    if ($null -eq $durationS) {
        foreach ($e in $streamList.ToArray()) { if ($e.codec_type -eq 'video' -and $null -ne $e.duration_s) { $durationS = $e.duration_s; break } }
    }
    $metaObj = [ordered]@{
        container     = $container
        streams       = $streamList.ToArray()
        stream_counts = [ordered]@{ video=$cV; audio=$cA; subtitle=$cS; data=$cD; other=$cO; total=$streamList.Count }
        duration_s    = $durationS
    }
    $metaJsonPath = Join-Path $invDir 'meta.json'
    [System.IO.File]::WriteAllText($metaJsonPath, ([ordered]@{ schema='lifeorch.media.meta/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); meta=$metaObj } | ConvertTo-Json -Depth 20), $utf8)
    $producedFiles.Add([pscustomobject]@{ p=$metaJsonPath; k='json' })

    # ================= -Audio (compose audio.ingest #10) =================
    if ($Audio) {
        if ($cA -lt 1) {
            $audioObj = [ordered]@{ requested=$true; extracted=$false; reason='no_audio_stream' }
            $warnings.Add('no_audio_stream: input has no audio track; audio extraction skipped')
        }
        else {
            if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
                $AudioIngestPath = Join-Path (Split-Path -Parent $PSScriptRoot) '10-audio-ingest/Invoke-AudioIngest.ps1'
            }
            $pwsh = Resolve-Pwsh $PwshPath
            if (-not (Test-Path -LiteralPath $AudioIngestPath -PathType Leaf)) {
                $audioObj = [ordered]@{ requested=$true; extracted=$false; reason='audio_ingest_not_found'; audio_ingest_path=$AudioIngestPath }
                $warnings.Add("audio.ingest entrypoint not found at '$AudioIngestPath'; audio extraction skipped")
            }
            elseif ([string]::IsNullOrWhiteSpace($pwsh)) {
                $audioObj = [ordered]@{ requested=$true; extracted=$false; reason='pwsh_not_found' }
                $warnings.Add('pwsh could not be resolved to spawn audio.ingest; audio extraction skipped (pass -PwshPath)')
            }
            else {
                $auArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AudioIngestPath,
                    '-InputFile',$inFull,'-Format',$afmt,'-SampleRate','16000','-Channels','1','-SampleFormat','s16',
                    '-Loudness',$loud,'-FfmpegPath',$ffmpeg,'-FfprobePath',$ffprobe,'-ArtifactRoot',$invDir,'-InvocationId','audio')
                Write-Diag "composing audio.ingest via $pwsh (fmt=$afmt loud=$loud)"
                $auRun = Invoke-Proc $pwsh $auArgs
                $auEnv = $null
                try { $auEnv = ([string]$auRun.stdout).Trim() | ConvertFrom-Json } catch { $auEnv = $null }
                if ($null -ne $auEnv -and (@('ok','partial') -contains [string](Prop $auEnv 'status')) -and (Has $auEnv 'result') -and $null -ne $auEnv.result) {
                    $ao = $auEnv.result.output
                    $wavPath = [string]$ao.path
                    $audioObj = [ordered]@{
                        requested = $true; extracted = $true
                        path = $wavPath; format = [string]$ao.format; codec = [string]$ao.codec
                        sample_rate = [int]$ao.sample_rate; channels = [int]$ao.channels
                        duration_s = (ToDouble $ao.duration_s); bytes = [long]$ao.bytes; sha256 = [string]$ao.sha256
                        composed_skill = 'audio.ingest'; composed_invocation_id = [string]$auEnv.invocation_id; composed_status = [string]$auEnv.status
                    }
                    if (-not [string]::IsNullOrWhiteSpace($wavPath) -and (Test-Path -LiteralPath $wavPath -PathType Leaf)) {
                        $producedFiles.Add([pscustomobject]@{ p=$wavPath; k=$afmt })
                    }
                }
                else {
                    $note = 'audio.ingest returned no usable envelope'
                    if ($null -ne $auEnv -and (Has $auEnv 'error') -and $null -ne $auEnv.error) { $note = "audio.ingest error: $([string]$auEnv.error.code) -- $([string]$auEnv.error.message)" }
                    $audioObj = [ordered]@{ requested=$true; extracted=$false; reason='audio_ingest_failed'; note=$note; composed_exit=$auRun.exit }
                    $warnings.Add($note)
                }
            }
        }
    }

    # ================= scene changes (shared by -Scenes and scene-preferred -Keyframes) =================
    $sceneChanges = $null
    $needScenes = ($Scenes -or ($Keyframes -gt 0))
    if ($needScenes -and $cV -ge 1) {
        $sceneChanges = Get-SceneChanges $ffmpeg $inFull $SceneThreshold
    }

    # ================= -Scenes =================
    if ($Scenes) {
        if ($cV -lt 1) {
            $scenesObj = [ordered]@{ threshold=[double]$SceneThreshold; count=0; reason='no_video_stream'; scenes=@() }
            $warnings.Add('no_video_stream: scene detection skipped')
        }
        else {
            $sc = @($sceneChanges)
            $sceneRows = New-Object System.Collections.Generic.List[object]
            for ($i = 0; $i -lt $sc.Count; $i++) {
                $startT = [double]$sc[$i].time
                $endT = if ($i -lt ($sc.Count - 1)) { [double]$sc[$i+1].time } elseif ($null -ne $durationS) { [double]$durationS } else { $startT }
                $sceneRows.Add([ordered]@{ index=$i; start=[math]::Round($startT,6); end=[math]::Round($endT,6); score=[double]$sc[$i].score })
            }
            $scenesObj = [ordered]@{ threshold=[double]$SceneThreshold; count=$sceneRows.Count; duration_s=$durationS; scenes=$sceneRows.ToArray() }
            $scenesJsonPath = Join-Path $invDir 'scenes.json'
            [System.IO.File]::WriteAllText($scenesJsonPath, ([ordered]@{ schema='lifeorch.media.scenes/0.1'; invocation_id=$InvocationId; threshold=[double]$SceneThreshold; count=$sceneRows.Count; duration_s=$durationS; scenes=$sceneRows.ToArray() } | ConvertTo-Json -Depth 12), $utf8)
            $scenesObj.path = $scenesJsonPath
            $producedFiles.Add([pscustomobject]@{ p=$scenesJsonPath; k='json' })
        }
    }

    # ================= -Keyframes N =================
    if ($Keyframes -gt 0) {
        if ($cV -lt 1) {
            $keyframesObj = [ordered]@{ requested_n=[int]$Keyframes; source=$null; count=0; reason='no_video_stream'; frames=@() }
            $warnings.Add('no_video_stream: keyframe extraction skipped')
        }
        elseif ($null -eq $durationS -or $durationS -le 0) {
            $keyframesObj = [ordered]@{ requested_n=[int]$Keyframes; source=$null; count=0; reason='unknown_duration'; frames=@() }
            $warnings.Add('unknown_duration: cannot place keyframes')
        }
        else {
            # Build a deterministic, chronological pick list. Scene-change frames preferred; fill with evenly spaced.
            $picks = New-Object System.Collections.Generic.List[object]  # {t;source;score}
            $sc = @($sceneChanges)
            $eps = [math]::Max(0.05, $durationS / 1000.0)
            foreach ($chg in $sc) {
                if ($picks.Count -ge $Keyframes) { break }
                $picks.Add([pscustomobject]@{ t=[double]$chg.time; source='scene'; score=[double]$chg.score })
            }
            if ($picks.Count -lt $Keyframes) {
                for ($i = 0; $i -lt $Keyframes; $i++) {
                    if ($picks.Count -ge $Keyframes) { break }
                    $t = [double]$durationS * ($i + 0.5) / $Keyframes
                    if ($t -ge $durationS) { $t = $durationS - $eps }
                    $dup = $false
                    foreach ($ex in $picks.ToArray()) { if ([math]::Abs([double]$ex.t - $t) -lt $eps) { $dup = $true; break } }
                    if (-not $dup) { $picks.Add([pscustomobject]@{ t=$t; source='even'; score=$null }) }
                }
            }
            # sort chronologically, stable
            $ordered = @($picks.ToArray() | Sort-Object -Property @{ Expression = { [double]$_.t } })
            $srcSummary = if (@($ordered | Where-Object { $_.source -eq 'scene' }).Count -gt 0) { 'scene' } else { 'even' }
            $frameRows = New-Object System.Collections.Generic.List[object]
            $idx = 0
            foreach ($pk in $ordered) {
                $png = Join-Path $invDir ("keyframe_{0:000}.png" -f $idx)
                $tstr = Fmt ([double]$pk.t)
                $kr = Invoke-Proc $ffmpeg @('-hide_banner','-nostdin','-y','-ss',$tstr,'-i',$inFull,'-frames:v','1','-update','1',$png)
                if ($kr.exit -eq 0 -and (Test-Path -LiteralPath $png -PathType Leaf)) {
                    $b = [System.IO.File]::ReadAllBytes($png)
                    $row = [ordered]@{ index=$idx; timestamp_s=[math]::Round([double]$pk.t,6); source=[string]$pk.source; score=$pk.score; path=$png; bytes=$b.Length; sha256=(Get-Sha256Hex $b) }
                    $frameRows.Add($row)
                    $producedFiles.Add([pscustomobject]@{ p=$png; k='png' })
                    $idx++
                }
                else {
                    $warnings.Add("keyframe at t=$tstr failed (ffmpeg exit $($kr.exit))")
                }
            }
            $vw = 0; $vh = 0
            foreach ($e in $streamList.ToArray()) { if ($e.codec_type -eq 'video') { $vw=[int]$e.width; $vh=[int]$e.height; break } }
            $kfSidecarPath = Join-Path $invDir 'keyframes.json'
            $kfDoc = [ordered]@{ schema='lifeorch.media.keyframes/0.1'; invocation_id=$InvocationId; requested_n=[int]$Keyframes; source=$srcSummary; threshold=[double]$SceneThreshold; width=$vw; height=$vh; count=$frameRows.Count; frames=$frameRows.ToArray() }
            [System.IO.File]::WriteAllText($kfSidecarPath, ($kfDoc | ConvertTo-Json -Depth 12), $utf8)
            $producedFiles.Add([pscustomobject]@{ p=$kfSidecarPath; k='json' })
            $keyframesObj = [ordered]@{ requested_n=[int]$Keyframes; source=$srcSummary; count=$frameRows.Count; threshold=[double]$SceneThreshold; sidecar_path=$kfSidecarPath; frames=$frameRows.ToArray() }
        }
    }

    $result = [ordered]@{
        input      = [ordered]@{ path=$inFull; exists=$true; bytes=$inBytes }
        meta       = $metaObj
        operations = [ordered]@{ audio=[bool]$Audio; keyframes=[int]$Keyframes; scenes=[bool]$Scenes }
        audio      = $audioObj
        keyframes  = $keyframesObj
        scenes     = $scenesObj
        ffmpeg     = [ordered]@{ path=$ffmpeg; version=$ffVersion }
        ffprobe    = [ordered]@{ path=$ffprobe }
    }
    Write-Diag "ok streams=$($streamList.Count) v=$cV a=$cA s=$cS audio=$([bool]$Audio) kf=$Keyframes scenes=$([bool]$Scenes)"
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

# ---- artifacts + human summary ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# media.decompose")
        [void]$mb.AppendLine("input: $($result.input.path)  ($($result.input.bytes) bytes)")
        $c = $result.meta.container; $sc2 = $result.meta.stream_counts
        [void]$mb.AppendLine("container: $($c.format_name)  dur=$($result.meta.duration_s)s  streams: v=$($sc2.video) a=$($sc2.audio) s=$($sc2.subtitle) (total $($sc2.total))")
        foreach ($st in @($result.meta.streams)) {
            if ($st.codec_type -eq 'video') { [void]$mb.AppendLine("  [$($st.index)] video $($st.codec_name) $($st.width)x$($st.height) $($st.pix_fmt) fps=$($st.fps)") }
            elseif ($st.codec_type -eq 'audio') { [void]$mb.AppendLine("  [$($st.index)] audio $($st.codec_name) $($st.sample_rate)Hz $($st.channels)ch $($st.channel_layout)") }
            else { [void]$mb.AppendLine("  [$($st.index)] $($st.codec_type) $($st.codec_name)") }
        }
        if ($null -ne $result.audio) {
            if ([bool](Prop $result.audio 'extracted' $false)) { [void]$mb.AppendLine("audio: extracted -> $($result.audio.path)  ($($result.audio.codec) $($result.audio.sample_rate)Hz $($result.audio.channels)ch, via audio.ingest)") }
            else { [void]$mb.AppendLine("audio: not extracted ($((Prop $result.audio 'reason' '')))") }
        }
        if ($null -ne $result.keyframes) { [void]$mb.AppendLine("keyframes: $($result.keyframes.count)/$($result.keyframes.requested_n) ($((Prop $result.keyframes 'source' '')))  sidecar=$((Prop $result.keyframes 'sidecar_path' ''))") }
        if ($null -ne $result.scenes) { [void]$mb.AppendLine("scenes: $($result.scenes.count) at threshold $($result.scenes.threshold)  -> $((Prop $result.scenes 'path' ''))") }
        [void]$mb.AppendLine("ffmpeg: $($result.ffmpeg.path)")
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $mdPath = Join-Path $invDir 'decompose.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        $producedFiles.Add([pscustomobject]@{ p=$mdPath; k='markdown' })

        foreach ($a in $producedFiles.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[media.decompose] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

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
$json = $envelope | ConvertTo-Json -Depth 25
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
