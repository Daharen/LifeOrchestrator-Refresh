#requires -Version 7.0
<#
  Invoke-MediaDecomposeTests.ps1 -- regression tests for media.decompose (Module 32).

  DUAL-MODE + OS-portable (mirrors audio.ingest's real-ffmpeg gate, NOT a mock): ffmpeg/ffprobe are portable,
  so the SAME harness runs the REAL Invoke-MediaDecompose.ps1 on the cloud Linux box (ffmpeg 6.x, pre-ship
  gate) and on the Windows executor (-Live, ffmpeg 8.x). Fixtures are generated at runtime by New-MediaFixture.ps1
  via ffmpeg lavfi (a 4 s two-segment video with ONE scene cut + a sine audio track, plus a no-audio variant) --
  no committed binary. It exercises meta, -Audio (composing audio.ingest #10), -Keyframes, -Scenes, the
  no-audio path, every error path, an AST parse of the shipped .ps1 files, and the Module 1 wrapper.

  -PwshPath <pwsh>  : the interpreter used to invoke the skill + spawn audio.ingest (Linux: pwsh; Windows:
                      the dotnet-tool pwsh). Passed through to the entrypoint for the -Audio composition.
  -Live             : informational banner only (the assertions are identical in both modes).
#>
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$Live
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-MediaDecompose.ps1'
$genr    = Join-Path $moduleRoot 'New-MediaFixture.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== media.decompose tests ($mode); pwsh=$PwshPath ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function Sha256File([string]$p) {
    $b = [System.IO.File]::ReadAllBytes($p); $s = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function PngMagic([string]$p) { try { $b = [System.IO.File]::ReadAllBytes($p); return ($b.Length -ge 8 -and $b[0] -eq 137 -and $b[1] -eq 80 -and $b[2] -eq 78 -and $b[3] -eq 71) } catch { return $false } }
function WavMagic([string]$p) { try { $b = [System.IO.File]::ReadAllBytes($p); return ($b.Length -ge 12 -and $b[0] -eq 82 -and $b[1] -eq 73 -and $b[2] -eq 70 -and $b[3] -eq 70 -and $b[8] -eq 87 -and $b[9] -eq 65 -and $b[10] -eq 86 -and $b[11] -eq 69) } catch { return $false } }

# ---- ffmpeg present ----
$ff = Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
Check 'ffmpeg available for fixtures' ($null -ne $ff)
if ($null -eq $ff) { [Console]::Out.WriteLine('cannot generate fixtures without ffmpeg'); [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }

# ---- AST parse of shipped .ps1 (fail closed on a syntax error) ----
foreach ($f in @($entry, $genr)) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Check "AST parses: $(Split-Path -Leaf $f)" (($null -eq $errs) -or (@($errs).Count -eq 0))
}

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id media.decompose' ($manifest.skill_id -eq 'media.decompose')
Check 'manifest parallel_safe true' ($manifest.parallel_safe -eq $true)
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest gpu none' ($manifest.requirements.gpu -eq 'none')
Check 'manifest models empty' (@($manifest.requirements.models).Count -eq 0)

# ---- fixtures ----
$token = [Guid]::NewGuid().ToString('N').Substring(0,8)
$fxDir = Join-Path ([System.IO.Path]::GetTempPath()) "lo-media-fx-$token"
New-Item -ItemType Directory -Path $fxDir -Force | Out-Null
$fixture = Join-Path $fxDir 'fixture.mp4'
$noaudio = Join-Path $fxDir 'noaudio.mp4'
$artRoot = Join-Path $fxDir 'art'

try {
    $genTxt = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $genr -OutputPath $fixture -NoAudioPath $noaudio -FfmpegPath $ff.Source
    $genObj = ([string]($genTxt | Out-String)).Trim() | ConvertFrom-Json
    Check 'fixture generator ok' ($genObj.ok -eq $true)
    Check 'fixture.mp4 created' (Test-Path -LiteralPath $fixture)
    Check 'noaudio.mp4 created' (Test-Path -LiteralPath $noaudio)

    # ---- meta (default, no ops) ----
    $mTxt = RunEntry @('-InputFile', $fixture, '-ArtifactRoot', $artRoot)
    Check 'meta exit 0' ($script:code -eq 0)
    $ev = Test-SkillResultEnvelope -Json $mTxt
    Check 'meta envelope validates' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    $m = $mTxt | ConvertFrom-Json
    Check 'meta status ok' ($m.status -eq 'ok')
    Check 'meta contract 0.2' ($m.contract_version -eq '0.2')
    Check 'meta confidence null' ($null -eq $m.result.meta -or $null -eq $m.confidence)
    Check 'meta stream_counts video=1' ([int]$m.result.meta.stream_counts.video -eq 1)
    Check 'meta stream_counts audio=1' ([int]$m.result.meta.stream_counts.audio -eq 1)
    Check 'meta total streams=2' ([int]$m.result.meta.stream_counts.total -eq 2)
    Check 'meta duration ~4s' ($null -ne $m.result.meta.duration_s -and [double]$m.result.meta.duration_s -ge 3.5 -and [double]$m.result.meta.duration_s -le 4.5)
    $vstream = @($m.result.meta.streams) | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $astream = @($m.result.meta.streams) | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1
    Check 'meta video codec mpeg4' ($vstream.codec_name -eq 'mpeg4')
    Check 'meta video 160x120' ([int]$vstream.width -eq 160 -and [int]$vstream.height -eq 120)
    Check 'meta video fps 15' ($null -ne $vstream.fps -and [math]::Abs([double]$vstream.fps - 15.0) -lt 0.01)
    Check 'meta video pix_fmt set' (-not [string]::IsNullOrWhiteSpace([string]$vstream.pix_fmt))
    Check 'meta audio codec aac' ($astream.codec_name -eq 'aac')
    Check 'meta audio sample_rate 44100' ([int]$astream.sample_rate -eq 44100)
    Check 'meta meta.json artifact present' (@($m.artifacts | Where-Object { $_.path -match 'meta\.json$' }).Count -eq 1)
    Check 'meta no audio object (op off)' ($null -eq $m.result.audio)
    Check 'meta no keyframes object (op off)' ($null -eq $m.result.keyframes)
    Check 'meta no scenes object (op off)' ($null -eq $m.result.scenes)
    Check 'meta ffprobe not python shim' ($m.result.ffprobe.path -notmatch '[\\/][Pp]ython')

    # ---- -Audio (compose audio.ingest #10) ----
    $aTxt = RunEntry @('-InputFile', $fixture, '-Audio', '-PwshPath', $PwshPath, '-ArtifactRoot', $artRoot)
    $a = $aTxt | ConvertFrom-Json
    Check 'audio envelope validates' ([bool](Test-SkillResultEnvelope -Json $aTxt).valid)
    Check 'audio status ok/partial' (@('ok','partial') -contains $a.status)
    Check 'audio extracted true' ($null -ne $a.result.audio -and $a.result.audio.extracted -eq $true)
    Check 'audio composed_skill audio.ingest' ($a.result.audio.composed_skill -eq 'audio.ingest')
    Check 'audio codec pcm_s16le' ($a.result.audio.codec -eq 'pcm_s16le')
    Check 'audio sample_rate 16000' ([int]$a.result.audio.sample_rate -eq 16000)
    Check 'audio channels 1' ([int]$a.result.audio.channels -eq 1)
    Check 'audio wav exists' ((Test-Path -LiteralPath $a.result.audio.path) -and (WavMagic $a.result.audio.path))
    Check 'audio sha256 matches file' ((Test-Path -LiteralPath $a.result.audio.path) -and ((Sha256File $a.result.audio.path) -eq $a.result.audio.sha256))
    Check 'audio wav is an artifact' (@($a.artifacts | Where-Object { $_.path -eq $a.result.audio.path }).Count -eq 1)

    # ---- -Keyframes 3 ----
    $kTxt = RunEntry @('-InputFile', $fixture, '-Keyframes', '3', '-ArtifactRoot', $artRoot)
    $k = $kTxt | ConvertFrom-Json
    Check 'keyframes envelope validates' ([bool](Test-SkillResultEnvelope -Json $kTxt).valid)
    Check 'keyframes count 3' ($null -ne $k.result.keyframes -and [int]$k.result.keyframes.count -eq 3)
    Check 'keyframes requested_n 3' ([int]$k.result.keyframes.requested_n -eq 3)
    Check 'keyframes all PNG on disk' ((@($k.result.keyframes.frames).Count -eq 3) -and (@($k.result.keyframes.frames | Where-Object { (Test-Path -LiteralPath $_.path) -and (PngMagic $_.path) }).Count -eq 3))
    Check 'keyframes chronological + indexed' ((@($k.result.keyframes.frames)[0].index -eq 0) -and ([double](@($k.result.keyframes.frames)[0].timestamp_s) -le [double](@($k.result.keyframes.frames)[2].timestamp_s)))
    Check 'keyframes source scene-preferred' ($k.result.keyframes.source -eq 'scene')
    Check 'keyframes sidecar exists + parses' ((Test-Path -LiteralPath $k.result.keyframes.sidecar_path) -and ($null -ne ((Get-Content -LiteralPath $k.result.keyframes.sidecar_path -Raw) | ConvertFrom-Json)))
    Check 'keyframes frame sha256 matches' ((Sha256File (@($k.result.keyframes.frames)[0].path)) -eq (@($k.result.keyframes.frames)[0].sha256))

    # ---- -Scenes ----
    $sTxt = RunEntry @('-InputFile', $fixture, '-Scenes', '-SceneThreshold', '0.3', '-ArtifactRoot', $artRoot)
    $s = $sTxt | ConvertFrom-Json
    Check 'scenes envelope validates' ([bool](Test-SkillResultEnvelope -Json $sTxt).valid)
    Check 'scenes count >= 1' ($null -ne $s.result.scenes -and [int]$s.result.scenes.count -ge 1)
    Check 'scenes threshold recorded' ([double]$s.result.scenes.threshold -eq 0.3)
    Check 'scenes have index/start/end/score' (($null -ne @($s.result.scenes.scenes)[0]) -and (Has (@($s.result.scenes.scenes)[0]) 'start') -and (Has (@($s.result.scenes.scenes)[0]) 'end') -and (Has (@($s.result.scenes.scenes)[0]) 'score'))
    Check 'scenes first score > threshold' ([double](@($s.result.scenes.scenes)[0].score) -gt 0.3)
    Check 'scenes last end == duration' ([math]::Abs([double](@($s.result.scenes.scenes)[-1].end) - [double]$s.result.meta.duration_s) -lt 0.2)
    Check 'scenes.json exists + parses' ((Test-Path -LiteralPath $s.result.scenes.path) -and ($null -ne ((Get-Content -LiteralPath $s.result.scenes.path -Raw) | ConvertFrom-Json)))

    # ---- combined: all three ops ----
    $cTxt = RunEntry @('-InputFile', $fixture, '-Audio', '-Keyframes', '2', '-Scenes', '-PwshPath', $PwshPath, '-ArtifactRoot', $artRoot)
    $co = $cTxt | ConvertFrom-Json
    Check 'combined envelope validates' ([bool](Test-SkillResultEnvelope -Json $cTxt).valid)
    Check 'combined audio+keyframes+scenes all present' (($co.result.audio.extracted -eq $true) -and ([int]$co.result.keyframes.count -eq 2) -and ([int]$co.result.scenes.count -ge 1))
    Check 'combined operations flags' (($co.result.operations.audio -eq $true) -and ([int]$co.result.operations.keyframes -eq 2) -and ($co.result.operations.scenes -eq $true))

    # ---- no-audio input + -Audio -> clean no_audio_stream ----
    $naTxt = RunEntry @('-InputFile', $noaudio, '-Audio', '-Keyframes', '2', '-PwshPath', $PwshPath, '-ArtifactRoot', $artRoot)
    $na = $naTxt | ConvertFrom-Json
    Check 'no-audio envelope validates' ([bool](Test-SkillResultEnvelope -Json $naTxt).valid)
    Check 'no-audio status partial' ($na.status -eq 'partial')
    Check 'no-audio audio.extracted false' ($na.result.audio.extracted -eq $false)
    Check 'no-audio reason no_audio_stream' ($na.result.audio.reason -eq 'no_audio_stream')
    Check 'no-audio stream_counts audio=0' ([int]$na.result.meta.stream_counts.audio -eq 0)
    Check 'no-audio keyframes still work' ([int]$na.result.keyframes.count -eq 2)

    # ---- error paths (valid error envelope, exit 0) ----
    $e1Txt = RunEntry @('-InputFile', (Join-Path $fxDir 'does-not-exist.mp4'))
    $ev1 = Test-SkillResultEnvelope -Json $e1Txt
    $e1 = $e1Txt | ConvertFrom-Json
    Check 'input_not_found valid envelope' ([bool]$ev1.valid)
    Check 'input_not_found error' ($e1.status -eq 'error' -and $e1.error.code -eq 'input_not_found')
    Check 'input_not_found exit 0' ($script:code -eq 0)

    $e2 = RunEntry @('-InputFile', $fixture, '-AudioFormat', 'xyz') | ConvertFrom-Json
    Check 'invalid_audio_format error' ($e2.status -eq 'error' -and $e2.error.code -eq 'invalid_audio_format')

    $e3 = RunEntry @('-InputFile', $fixture, '-SceneThreshold', '5') | ConvertFrom-Json
    Check 'invalid_scene_threshold error' ($e3.status -eq 'error' -and $e3.error.code -eq 'invalid_scene_threshold')

    $e4 = RunEntry @('-InputFile', $fixture, '-FfmpegPath', (Join-Path $fxDir 'nope-ffmpeg.exe')) | ConvertFrom-Json
    Check 'ffmpeg_not_found error' ($e4.status -eq 'error' -and $e4.error.code -eq 'ffmpeg_not_found')

    # ---- InputsJson path ----
    $jTxt = RunEntry @('-InputsJson', ([ordered]@{ input=$fixture; scenes=$true; scene_threshold=0.3 } | ConvertTo-Json -Compress), '-ArtifactRoot', $artRoot)
    $j = $jTxt | ConvertFrom-Json
    Check 'InputsJson scenes ran' ($null -ne $j.result.scenes -and [int]$j.result.scenes.count -ge 1)

    # ---- Module 1 wrapper (meta-only) ----
    $wjson = ([ordered]@{ input=$fixture } | ConvertTo-Json -Compress)
    $rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $wjson -PwshPath $PwshPath -ArtifactRoot $artRoot
    $repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
    Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
    Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
    Check 'wrapper skill_id' ($repObj.skill_id -eq 'media.decompose')
}
finally {
    try { if (Test-Path -LiteralPath $fxDir) { Remove-Item -LiteralPath $fxDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
