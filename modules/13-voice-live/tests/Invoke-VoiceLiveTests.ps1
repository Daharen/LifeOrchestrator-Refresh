#requires -Version 7.0
<#
  Invoke-VoiceLiveTests.ps1 — tests for voice.live (Module 13).

  Dual-mode & OS-portable (mirrors Modules 8/9/11/12):
   * -UseMock : run the REAL Invoke-VoiceLive.ps1 with all three children pointed at tests/mock-child.ps1
                (canned envelopes; the tts branch writes a real WAV) — no GPU/models needed. Cloud pre-ship gate.
   * default  : resolve the real child skills (speech.stt/model.gateway/speech.tts) and run a live turn on a real
                speech WAV (Windows/executor). Same assertions.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$InputFile,
    [string]$ExpectHeard = 'country',
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$UseMock
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name $detail" }
}
function Get-Sha256HexFile([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

$entry = Join-Path $SkillDir 'Invoke-VoiceLive.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m13-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'

Write-Host "=== voice.live tests (UseMock=$UseMock) ==="
Write-Host "skill=$entry"

$mockPath = $null
if ($UseMock) { $mockPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'mock-child.ps1')).Path }

# input wav: real speech on Windows; a generated tone on cloud (mock ignores content)
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $ffmpeg = (Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($null -ne $ffmpeg) {
        $InputFile = Join-Path $tmpRoot 'tone.wav'
        & $ffmpeg.Source -hide_banner -nostdin -y -f lavfi -i 'sine=frequency=440:duration=2' -ar 16000 -ac 1 -c:a pcm_s16le $InputFile 2>$null | Out-Null
    } else { throw "no -InputFile and no ffmpeg to generate one" }
}

function Run-Voice([hashtable]$inp) {
    if ($mockPath) {
        if (-not $inp.ContainsKey('stt_path')) { $inp['stt_path'] = $mockPath }
        if (-not $inp.ContainsKey('gateway_path')) { $inp['gateway_path'] = $mockPath }
        if (-not $inp.ContainsKey('tts_path')) { $inp['tts_path'] = $mockPath }
    }
    if (-not $inp.ContainsKey('pwsh_path')) { $inp['pwsh_path'] = $PwshPath }
    $j = ($inp | ConvertTo-Json -Compress -Depth 8)
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-InputsJson',$j,'-ArtifactRoot',$artRoot)
    $out = & $PwshPath @callArgs 2> $tmpErr.FullName
    $ec = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $err = ''; try { $err = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ exit = $ec; env = $env; raw = $txt; err = $err }
}

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=mixed' ($man.determinism -eq 'mixed')
Check 'manifest parallel_safe=false' ($man.parallel_safe -eq $false)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=voice.live' ($man.skill_id -eq 'voice.live')

# ---------- 2) full turn ----------
$r = Run-Voice @{ input = $InputFile }
Check 'turn: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'turn: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'turn: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'turn: speech_detected' ($null -ne $e.result -and ($e.result.speech_detected -eq $true)) "detected=$($e.result.speech_detected)"
Check "turn: transcript contains '$ExpectHeard'" ($null -ne $e.result -and ([string]$e.result.transcript.text) -match [Regex]::Escape($ExpectHeard)) "text=$($e.result.transcript.text)"
Check 'turn: response text non-empty' ($null -ne $e.result -and $null -ne $e.result.response -and -not [string]::IsNullOrWhiteSpace([string]$e.result.response.text)) "resp=$($e.result.response.text)"
Check 'turn: reply audio present' ($null -ne $e.result -and $null -ne $e.result.reply -and (Test-Path -LiteralPath ([string]$e.result.reply.path) -PathType Leaf)) "reply=$($e.result.reply.path)"
Check 'turn: confidence populated (STT)' ($null -ne $e.confidence -and [double]$e.confidence -gt 0)
Check 'turn: model_provenance >= 3 (stt+gateway+tts)' (@($e.model_provenance).Count -ge 3) "n=$(@($e.model_provenance).Count)"
$stageNames = @($e.result.stages | ForEach-Object { [string]$_.name })
Check 'turn: stages stt+respond+speak present' (($stageNames -contains 'stt') -and ($stageNames -contains 'respond') -and ($stageNames -contains 'speak')) "stages=$($stageNames -join ',')"
$replyArt = @($e.artifacts | Where-Object { [string]$_.path -match 'reply\.' })
Check 'turn: reply artifact sha256 matches file' ($replyArt.Count -ge 1 -and ((Get-Sha256HexFile ([string]$replyArt[0].path)) -eq [string]$replyArt[0].sha256))

# ---------- 3) readback (respond off, speak transcript) ----------
$r2 = Run-Voice @{ input = $InputFile; respond = $false; speak = $true; readback_transcript = $true }
$e2 = $r2.env
Check 'readback: no response' ($null -ne $e2.result -and $null -eq $e2.result.response)
Check 'readback: reply audio present' ($null -ne $e2.result -and $null -ne $e2.result.reply -and (Test-Path -LiteralPath ([string]$e2.result.reply.path) -PathType Leaf))

# ---------- 4) no-speech (mock only) ----------
if ($UseMock) {
    $env:MOCK_STT_NOSPEECH = '1'
    $r3 = Run-Voice @{ input = $InputFile }
    Remove-Item Env:MOCK_STT_NOSPEECH -ErrorAction SilentlyContinue
    $e3 = $r3.env
    Check 'no_speech: speech_detected=false' ($null -ne $e3.result -and ($e3.result.speech_detected -eq $false)) "detected=$($e3.result.speech_detected)"
    Check 'no_speech: no response, no reply' ($null -ne $e3.result -and $null -eq $e3.result.response -and $null -eq $e3.result.reply)
} else {
    Write-Host "  [SKIP] no_speech (mock-only)"
}

# ---------- 5) error path ----------
$rErr = Run-Voice @{ input = (Join-Path $tmpRoot 'nope.wav') }
Check 'error: input_not_found' ($null -ne $rErr.env -and $rErr.env.status -eq 'error' -and $rErr.env.error.code -eq 'input_not_found')
$evE = Test-SkillResultEnvelope -Json $rErr.raw
Check 'error: envelope still schema-valid' ([bool]$evE.valid)

# ---------- 6) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $InputFile; pwsh_path = $PwshPath }
if ($mockPath) { $wrapInp['stt_path'] = $mockPath; $wrapInp['gateway_path'] = $mockPath; $wrapInp['tts_path'] = $mockPath }
$wrapJson = ($wrapInp | ConvertTo-Json -Compress -Depth 8)
$tmpErr = New-TemporaryFile
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$wrapArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Resolve-Path -LiteralPath $wrapper).Path,'-SkillDir',$SkillDir,'-InputsJson',$wrapJson,'-ArtifactRoot',$artRoot,'-PwshPath',$PwshPath)
$wout = & $PwshPath @wrapArgs 2> $tmpErr.FullName
$ErrorActionPreference = $prev
Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
$wrep = $null; try { $wrep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
Check 'wrapper: report manifest_valid + invoked + envelope_valid' ($null -ne $wrep -and $wrep.manifest_valid -and $wrep.invoked -and $wrep.envelope_valid)

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
