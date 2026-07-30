#requires -Version 7.0
<#
.SYNOPSIS
  Deterministic test-fixture generator for media.decompose (Life Orchestrator).
.DESCRIPTION
  Builds tiny, reproducible media files with ffmpeg lavfi -- no committed binary asset, so the same fixtures
  regenerate identically in the cloud (ffmpeg 6.x) and on the Windows executor (ffmpeg 8.x):
    * the MAIN fixture: two concatenated video segments (testsrc2 then smptebars) that create ONE hard
      scene cut at the midpoint, plus a 440 Hz sine audio track (mpeg4 video + aac audio in an mp4 container).
      Universal encoders (mpeg4/aac) are used so it builds anywhere ffmpeg is present.
    * an optional NO-AUDIO fixture: a single testsrc2 video segment, video stream only.
  Emits one JSON line to stdout: { ok, ffmpeg, output, no_audio, width, height, rate, duration_s, scene_cut_s }.
.EXAMPLE
  pwsh -NoProfile -File .\New-MediaFixture.ps1 -OutputPath .\fixture.mp4 -NoAudioPath .\noaudio.mp4
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$NoAudioPath,
    [string]$FfmpegPath,
    [int]$Width = 160,
    [int]$Height = 120,
    [int]$Rate = 15,
    [double]$SegDuration = 2.0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$inv = [Globalization.CultureInfo]::InvariantCulture
function Fmt([double]$d) { return ([double]$d).ToString($inv) }

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
    $out = $so.GetAwaiter().GetResult(); $err = $se.GetAwaiter().GetResult(); $code = $p.ExitCode
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
    foreach ($c in @((Join-Path ([string]$env:LOCALAPPDATA) 'Microsoft\WinGet\Links\ffmpeg.exe'),'C:\Program Files\ffmpeg\bin\ffmpeg.exe','C:\ffmpeg\bin\ffmpeg.exe')) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$ff = Resolve-Ffmpeg $FfmpegPath
if ([string]::IsNullOrWhiteSpace($ff)) { [Console]::Out.WriteLine(([ordered]@{ ok=$false; error='ffmpeg_not_found' } | ConvertTo-Json -Compress)); exit 1 }

$total = 2.0 * $SegDuration
$sceneCut = $SegDuration
$madeMain = $false; $madeNoAudio = $false

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $dir = Split-Path -Parent $OutputPath; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $fc = "[0:v]format=yuv420p[v0];[1:v]format=yuv420p[v1];[v0][v1]concat=n=2:v=1:a=0[v]"
    $argv = @(
        '-hide_banner','-nostdin','-y',
        '-f','lavfi','-i',("testsrc2=s={0}x{1}:r={2}:d={3}" -f $Width,$Height,$Rate,(Fmt $SegDuration)),
        '-f','lavfi','-i',("smptebars=s={0}x{1}:r={2}:d={3}" -f $Width,$Height,$Rate,(Fmt $SegDuration)),
        '-f','lavfi','-i',("sine=frequency=440:sample_rate=44100:duration={0}" -f (Fmt $total)),
        '-filter_complex',$fc,'-map','[v]','-map','2:a',
        '-c:v','mpeg4','-q:v','3','-c:a','aac','-shortest',$OutputPath
    )
    $r = Invoke-Proc $ff $argv
    $madeMain = ($r.exit -eq 0 -and (Test-Path -LiteralPath $OutputPath -PathType Leaf))
    if (-not $madeMain) {
        $tail = [string]$r.stderr; if ($tail.Length -gt 800) { $tail = $tail.Substring($tail.Length - 800) }
        [Console]::Error.WriteLine("[New-MediaFixture] main fixture failed (exit $($r.exit)): $tail")
    }
}
if (-not [string]::IsNullOrWhiteSpace($NoAudioPath)) {
    $dir = Split-Path -Parent $NoAudioPath; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $argv2 = @('-hide_banner','-nostdin','-y','-f','lavfi','-i',("testsrc2=s={0}x{1}:r={2}:d={3}" -f $Width,$Height,$Rate,(Fmt $total)),'-c:v','mpeg4','-q:v','3',$NoAudioPath)
    $r2 = Invoke-Proc $ff $argv2
    $madeNoAudio = ($r2.exit -eq 0 -and (Test-Path -LiteralPath $NoAudioPath -PathType Leaf))
    if (-not $madeNoAudio) { [Console]::Error.WriteLine("[New-MediaFixture] no-audio fixture failed (exit $($r2.exit))") }
}

$ok = $true
if (-not [string]::IsNullOrWhiteSpace($OutputPath) -and -not $madeMain) { $ok = $false }
if (-not [string]::IsNullOrWhiteSpace($NoAudioPath) -and -not $madeNoAudio) { $ok = $false }
[Console]::Out.WriteLine(([ordered]@{
    ok=$ok; ffmpeg=$ff
    output=$(if ($madeMain) { (Resolve-Path -LiteralPath $OutputPath).Path } else { $null })
    no_audio=$(if ($madeNoAudio) { (Resolve-Path -LiteralPath $NoAudioPath).Path } else { $null })
    width=$Width; height=$Height; rate=$Rate; duration_s=$total; scene_cut_s=$sceneCut
} | ConvertTo-Json -Compress))
if ($ok) { exit 0 } else { exit 1 }
