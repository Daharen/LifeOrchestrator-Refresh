#requires -Version 7.0
<#
  gen.audio test harness (Module 22). OS-portable + real-engine: it generates its own fixtures via the
  skill, so the SAME file runs off-machine on the cloud ffmpeg (pre-ship gate) and live on the Windows
  executor. No mock. Runs the skill as a child process (captures the clean stdout envelope) so the skill's
  `exit 0` never terminates this harness.
#>
[CmdletBinding()]
param([string]$FfmpegPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

$here      = $PSScriptRoot
$moduleDir = (Resolve-Path (Join-Path $here '..')).Path
$skill     = Join-Path $moduleDir 'Invoke-GenAudio.ps1'
$manifest  = Join-Path $moduleDir 'skill.json'
$wrapper   = Join-Path $moduleDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
$pwshExe   = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$artRoot   = Join-Path ([IO.Path]::GetTempPath()) ("m22-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $artRoot -Force | Out-Null

$pass = 0; $fail = 0; $caseNo = 0
function Ok([bool]$cond, [string]$label) {
    $script:caseNo++
    if ($cond) { $script:pass++; Write-Host ("  [PASS] {0}" -f $label) }
    else       { $script:fail++; Write-Host ("  [FAIL] {0}" -f $label) -ForegroundColor Red }
}
function Run-Proc([string]$exe, [string[]]$argv) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    foreach ($a in $argv) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::new(); $p.StartInfo = $psi
    [void]$p.Start()
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    return @{ exit=$p.ExitCode; stdout=$so.GetAwaiter().GetResult(); stderr=$se.GetAwaiter().GetResult() }
}
# Invoke the skill with a hashtable of -InputsJson keys; returns @{exit; env(parsed envelope)}.
function Invoke-Gen([hashtable]$inputs, [string[]]$extra = @()) {
    $iid = 'c' + [Guid]::NewGuid().ToString('N').Substring(0,10)
    $json = ($inputs | ConvertTo-Json -Compress -Depth 6)
    $argv = @('-NoProfile','-File',$skill,'-InputsJson',$json,'-ArtifactRoot',$artRoot,'-InvocationId',$iid)
    if ($FfmpegPath) { $argv += @('-FfmpegPath',$FfmpegPath) }
    $argv += $extra
    $r = Run-Proc $pwshExe $argv
    $env = $null
    try { $env = $r.stdout | ConvertFrom-Json } catch {}
    return @{ exit=$r.exit; env=$env; raw=$r.stdout; err=$r.stderr }
}
function Get-Codec($env) {
    if ($null -eq $env -or $null -eq $env.result) { return '' }
    $o = $env.result.output
    if ($o.probe -and $o.probe.audio -and $o.probe.audio.codec) { return [string]$o.probe.audio.codec }
    return [string]$o.codec
}

Write-Host "gen.audio tests -- skill=$skill"
Write-Host "  pwsh=$pwshExe"
Write-Host "  artRoot=$artRoot"

# ---- ffmpeg presence ----
$ff = if ($FfmpegPath) { $FfmpegPath } else { (Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
Ok ([bool]$ff) "ffmpeg resolvable ($ff)"

# ---- 1. manifest structural validity ----
try {
    $mf = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $req = @('schema','skill_id','name','version','contract_version','purpose','determinism','invocation','inputs','outputs','requirements','artifacts','timeout','batch','streaming','parallel_safe')
    $missing = @($req | Where-Object { -not ($mf.PSObject.Properties.Name -contains $_) })
    Ok (($mf.schema -eq 'lifeorch.skill.manifest/0.1') -and ($mf.skill_id -eq 'gen.audio') -and ($missing.Count -eq 0)) "manifest valid (skill_id=gen.audio, no missing required fields)"
} catch { Ok $false "manifest parse ($($_.Exception.Message))" }
# Module 1 validator if importable
try {
    $psm = Join-Path $moduleDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
    if (Test-Path -LiteralPath $psm) {
        Import-Module $psm -Force -ErrorAction Stop
        if (Get-Command Test-SkillManifest -ErrorAction SilentlyContinue) {
            $v = Test-SkillManifest -Path $manifest
            $okv = if ($v -is [bool]) { $v } elseif ($v.PSObject.Properties.Name -contains 'valid') { [bool]$v.valid } else { $true }
            Ok $okv "Module 1 Test-SkillManifest passes"
        }
    }
} catch { Write-Host "  (note: Module 1 validator not exercised: $($_.Exception.Message))" }

# ---- 2. tone default (A4, 1 s, wav) ----
$r = Invoke-Gen @{ kind='tone'; note='A4'; duration=1 }
$okTone = ($r.exit -eq 0) -and $r.env -and ($r.env.status -eq 'ok') -and ((Get-Codec $r.env) -like 'pcm_s16*') `
    -and ([int]$r.env.result.output.sample_rate -eq 44100) -and ([int]$r.env.result.output.channels -eq 1) `
    -and ([double]$r.env.result.output.duration_s -ge 0.9) -and ([double]$r.env.result.output.duration_s -le 1.1) `
    -and (Test-Path -LiteralPath $r.env.result.output.path) -and ($r.env.result.output.sha256.Length -eq 64) `
    -and ([math]::Abs([double]($r.env.result.generation.frequencies[0]) - 440.0) -lt 0.5)
Ok $okTone "tone A4 -> ok, pcm_s16 44100/1ch ~1s, sha present, freq~440"

# ---- 3. determinism: tone twice ----
$a = Invoke-Gen @{ kind='tone'; frequency=440; duration=0.5 }
$b = Invoke-Gen @{ kind='tone'; frequency=440; duration=0.5 }
Ok (($a.env.result.output.sha256) -and ($a.env.result.output.sha256 -eq $b.env.result.output.sha256)) "determinism: identical tone -> equal sha256"

# ---- 4. determinism: seeded noise twice ----
$a = Invoke-Gen @{ kind='noise'; color='white'; seed=7; duration=0.5 }
$b = Invoke-Gen @{ kind='noise'; color='white'; seed=7; duration=0.5 }
Ok (($a.env.result.output.sha256) -and ($a.env.result.output.sha256 -eq $b.env.result.output.sha256)) "determinism: identical seeded noise -> equal sha256"

# ---- 5. note mapping + bad note ----
$r = Invoke-Gen @{ kind='tone'; note='C#3'; duration=0.3 }
Ok ($r.env.status -eq 'ok') "note C#3 parses -> ok"
$r = Invoke-Gen @{ kind='tone'; note='H9'; duration=0.3 }
Ok (($r.env.status -eq 'error') -and ($r.env.error.code -eq 'invalid_note')) "bad note H9 -> invalid_note"

# ---- 6. chord notes ----
$r = Invoke-Gen @{ kind='chord'; notes='C4,E4,G4'; duration=0.4 }
Ok (($r.env.status -eq 'ok') -and (@($r.env.result.generation.frequencies).Count -eq 3) -and ($r.env.result.source.lavfi -like '*aevalsrc*')) "chord C4,E4,G4 -> ok, 3 partials"

# ---- 7. chord requires partials ----
$r = Invoke-Gen @{ kind='chord'; duration=0.3 }
Ok (($r.env.status -eq 'error') -and ($r.env.error.code -eq 'invalid_frequencies')) "chord with no partials -> invalid_frequencies"

# ---- 8. waveforms ----
foreach ($w in @('sine','square','triangle','sawtooth')) {
    $r = Invoke-Gen @{ kind='tone'; frequency=330; waveform=$w; duration=0.3 }
    Ok (($r.env.status -eq 'ok') -and (Test-Path -LiteralPath $r.env.result.output.path)) "waveform $w -> ok"
}

# ---- 9. noise colors ----
foreach ($c in @('white','pink','brown','blue','violet','velvet')) {
    $r = Invoke-Gen @{ kind='noise'; color=$c; duration=0.3 }
    Ok ($r.env.status -eq 'ok') "noise color $c -> ok"
}

# ---- 10. sweep ----
$r = Invoke-Gen @{ kind='sweep'; freq_start=200; freq_end=4000; duration=0.6 }
Ok (($r.env.status -eq 'ok') -and (Test-Path -LiteralPath $r.env.result.output.path)) "sweep 200->4000 -> ok"

# ---- 11. silence ----
$r = Invoke-Gen @{ kind='silence'; duration=0.5 }
Ok (($r.env.status -eq 'ok') -and ([double]$r.env.result.output.duration_s -ge 0.4) -and ([double]$r.env.result.output.duration_s -le 0.6)) "silence 0.5s -> ok"

# ---- 12. channels 2 ----
$r = Invoke-Gen @{ kind='tone'; frequency=440; channels=2; duration=0.3 }
Ok ([int]$r.env.result.output.channels -eq 2) "channels=2 -> stereo output"

# ---- 13. duration 0.25 ----
$r = Invoke-Gen @{ kind='tone'; frequency=440; duration=0.25 }
Ok (([double]$r.env.result.output.duration_s -ge 0.2) -and ([double]$r.env.result.output.duration_s -le 0.3)) "duration 0.25 -> ~0.25s"

# ---- 14. fades ----
$r = Invoke-Gen @{ kind='tone'; frequency=440; duration=0.6; fade_in_ms=50; fade_out_ms=50 }
Ok (($r.env.status -eq 'ok') -and ($r.env.result.ffmpeg.argv -contains '-af')) "fades -> ok, afade in argv"

# ---- 15. amplitude 0.1 ----
$r = Invoke-Gen @{ kind='tone'; frequency=440; amplitude=0.1; duration=0.3 }
Ok ($r.env.status -eq 'ok') "amplitude 0.1 -> ok"

# ---- 16. format matrix ----
$expect = @{ wav='pcm'; mp3='mp3'; flac='flac'; opus='opus'; ogg='vorbis'; m4a='aac' }
foreach ($fm in @('wav','mp3','flac','opus','ogg','m4a')) {
    $r = Invoke-Gen @{ kind='tone'; frequency=440; duration=0.3; format=$fm }
    $codec = Get-Codec $r.env
    $stOk = ($r.env.status -eq 'ok') -or ($r.env.status -eq 'partial')
    Ok ($stOk -and ($codec -like "*$($expect[$fm])*")) "format $fm -> $codec"
}

# ---- 17. error paths ----
$errCases = @(
    @{ i=@{ kind='foo' };                                     code='invalid_kind' }
    @{ i=@{ kind='tone'; format='xyz' };                      code='invalid_format' }
    @{ i=@{ kind='tone'; waveform='buzz' };                   code='invalid_waveform' }
    @{ i=@{ kind='noise'; color='rainbow' };                  code='invalid_color' }
    @{ i=@{ kind='tone'; channels=3 };                        code='invalid_channels' }
    @{ i=@{ kind='tone'; amplitude=2 };                       code='invalid_amplitude' }
    @{ i=@{ kind='tone'; duration=0 };                        code='invalid_duration' }
    @{ i=@{ kind='tone'; duration=99999 };                    code='invalid_duration' }
    @{ i=@{ kind='tone'; frequency=999999; sample_rate=44100 }; code='frequency_out_of_range' }
)
foreach ($ec in $errCases) {
    $r = Invoke-Gen $ec.i
    Ok (($r.exit -eq 0) -and ($r.env.status -eq 'error') -and ($r.env.error.code -eq $ec.code)) "error path -> $($ec.code)"
}
# ffmpeg_not_found needs an explicit bogus path (bypass -FfmpegPath default)
$iid = 'cbad' + [Guid]::NewGuid().ToString('N').Substring(0,6)
$rf = Run-Proc $pwshExe @('-NoProfile','-File',$skill,'-InputsJson','{"kind":"tone","duration":0.2}','-ArtifactRoot',$artRoot,'-InvocationId',$iid,'-FfmpegPath','Z:\no\such\ffmpeg.exe')
$ev = $null; try { $ev = $rf.stdout | ConvertFrom-Json } catch {}
Ok (($rf.exit -eq 0) -and $ev -and ($ev.status -eq 'error') -and ($ev.error.code -eq 'ffmpeg_not_found')) "error path -> ffmpeg_not_found"

# ---- 18. Module 1 wrapper ----
if (Test-Path -LiteralPath $wrapper) {
    $rw = Run-Proc $pwshExe @('-NoProfile','-File',(Resolve-Path $wrapper).Path,'-SkillDir',$moduleDir,'-InputsJson','{"kind":"tone","duration":0.3}')
    $rep = $null; try { $rep = $rw.stdout | ConvertFrom-Json } catch {}
    Ok ($rep -and ([bool]$rep.manifest_valid) -and ([bool]$rep.envelope_valid)) "Module 1 wrapper -> manifest_valid & envelope_valid"
} else {
    Write-Host "  (note: Module 1 wrapper not found at $wrapper -- skipping wrapper test)"
}

# ---- cleanup ----
try { Remove-Item -LiteralPath $artRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}

$total = $pass + $fail
Write-Host ""
Write-Host ("gen.audio tests: {0}/{1} passed" -f $pass, $total) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 } else { exit 0 }
