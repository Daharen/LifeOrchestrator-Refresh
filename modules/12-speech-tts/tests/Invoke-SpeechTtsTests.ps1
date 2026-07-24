#requires -Version 7.0
<#
  Invoke-SpeechTtsTests.ps1 — tests for speech.tts (Module 12).

  Dual-mode & OS-portable (mirrors Modules 8/9/11):
   * -UseMock : run the REAL Invoke-SpeechTts.ps1 against a mock python worker (tests/mock-tts-infer.py, which
                writes a real PCM16 WAV via stdlib) + a temp registry — no GPU/model/qwen_tts needed. Cloud pre-ship gate.
   * default  : resolve the real speech-venv python + model from models.json and synthesize live (Windows/executor).
  Same assertions hold in both modes.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath,
    [string]$Registry,
    [string]$AudioIngestPath,
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

$entry = Join-Path $SkillDir 'Invoke-SpeechTts.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m12-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'

Write-Host "=== speech.tts tests (UseMock=$UseMock) ==="
Write-Host "skill=$entry"

$ttsInferOverride = $null
if ($UseMock) {
    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        $pyCmd = (Get-Command 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($null -eq $pyCmd) { $pyCmd = (Get-Command 'python' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1) }
        if ($null -eq $pyCmd) { throw "no python3/python found for mock mode" }
        $PythonPath = $pyCmd.Source
    }
    $ttsInferOverride = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'mock-tts-infer.py')).Path
    if ([string]::IsNullOrWhiteSpace($Registry)) {
        $fakeModel = Join-Path $tmpRoot 'fakemodel'; New-Item -ItemType Directory -Path $fakeModel -Force | Out-Null
        $Registry = Join-Path $tmpRoot 'models.test.json'
        $reg = [ordered]@{ schema='lifeorch.model_registry/0.1'; host='cloud-test'
            models=@( [ordered]@{ model_id='tts.weak.qwen3-0p6b'; type='tts'; wired=$false; name='Qwen3-TTS 0.6B (mock)';
                       family='qwen3-tts'; format='safetensors-dir'; version='mock'; engine='transformers';
                       path=$fakeModel; engine_env=$PythonPath } ) }
        [System.IO.File]::WriteAllText($Registry, ($reg | ConvertTo-Json -Depth 8), $utf8)
    }
}

function Run-Tts([hashtable]$inp) {
    if ($PythonPath -and -not $inp.ContainsKey('python_path')) { $inp['python_path'] = $PythonPath }
    if ($Registry -and -not $inp.ContainsKey('registry')) { $inp['registry'] = $Registry }
    if ($ttsInferOverride -and -not $inp.ContainsKey('tts_infer_path')) { $inp['tts_infer_path'] = $ttsInferOverride }
    if ($AudioIngestPath -and -not $inp.ContainsKey('audio_ingest_path')) { $inp['audio_ingest_path'] = $AudioIngestPath }
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

# resolve audio.ingest for conversion tests
if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
    $aic = Join-Path $SkillDir '..\10-audio-ingest\Invoke-AudioIngest.ps1'
    if (Test-Path -LiteralPath $aic -PathType Leaf) { $AudioIngestPath = (Resolve-Path -LiteralPath $aic).Path }
}
$haveFfmpeg = ($null -ne (Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue))

$sentence = 'Hello from Life Orchestrator. This is a text to speech synthesis test.'

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=mixed' ($man.determinism -eq 'mixed')
Check 'manifest parallel_safe=false' ($man.parallel_safe -eq $false)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=speech.tts' ($man.skill_id -eq 'speech.tts')

# ---------- 2) synthesis (native wav) ----------
$r = Run-Tts @{ text = $sentence; speaker = 'Ryan' }
Check 'synth: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'synth: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'synth: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'synth: duration_s > 0' ($null -ne $e.result -and [double]$e.result.audio.duration_s -gt 0) "dur=$($e.result.audio.duration_s)"
Check 'synth: sample_rate 24000' ($null -ne $e.result -and [int]$e.result.audio.sample_rate -eq 24000) "sr=$($e.result.audio.sample_rate)"
Check 'synth: channels 1' ($null -ne $e.result -and [int]$e.result.audio.channels -eq 1)
Check 'synth: confidence in (0,1]' ($null -ne $e.confidence -and [double]$e.confidence -gt 0 -and [double]$e.confidence -le 1) "conf=$($e.confidence)"
Check 'synth: model_provenance[1], engine transformers' (@($e.model_provenance).Count -eq 1 -and (@($e.model_provenance)[0].engine -eq 'transformers')) "n=$(@($e.model_provenance).Count)"
$arts = @($e.artifacts); $paths = @($arts | ForEach-Object { [string]$_.path })
$hasWav = @($paths | Where-Object { $_ -match 'speech\.wav$' }).Count -eq 1
$hasTj = @($paths | Where-Object { $_ -match 'tts\.json$' }).Count -eq 1
$hasTm = @($paths | Where-Object { $_ -match 'tts\.md$' }).Count -eq 1
Check 'synth: artifacts include speech.wav + tts.json + tts.md' ($hasWav -and $hasTj -and $hasTm) "paths=$($paths -join ',')"
$wavArt = @($arts | Where-Object { [string]$_.path -match 'speech\.wav$' })[0]
Check 'synth: speech.wav sha256 matches file' ($null -ne $wavArt -and ((Get-Sha256HexFile ([string]$wavArt.path)) -eq [string]$wavArt.sha256))
Check 'synth: not flagged for a plausible sentence' ($null -ne $e.result -and ($e.result.review.flagged -eq $false)) "flagged=$($e.result.review.flagged)"

# ---------- 3) review routing (forced too-short / failed) ----------
$rq = Join-Path $tmpRoot 'review_queue.jsonl'
if (Test-Path -LiteralPath $rq) { Remove-Item -LiteralPath $rq -Force }
$restoreDur = $env:MOCK_TTS_DUR
if ($UseMock) { $env:MOCK_TTS_DUR = '0.02' }
$r2 = Run-Tts @{ text = $sentence; speaker = 'Ryan'; review_queue_path = $rq; confidence_threshold = $(if ($UseMock) { 0.5 } else { 0.999 }) }
if ($UseMock) { if ($null -ne $restoreDur) { $env:MOCK_TTS_DUR = $restoreDur } else { Remove-Item Env:MOCK_TTS_DUR -ErrorAction SilentlyContinue } }
$e2 = $r2.env
Check 'review: flagged' ($null -ne $e2.result -and ($e2.result.review.flagged -eq $true)) "flagged=$($e2.result.review.flagged) conf=$($e2.confidence)"
$rqOk = $false
if (Test-Path -LiteralPath $rq) {
    $line = (Get-Content -LiteralPath $rq -TotalCount 1)
    if ($line) { $ri = $line | ConvertFrom-Json; $rqOk = (($ri.schema -eq 'lifeorch.review.item/0.1') -and ($ri.flagged_by -eq 'speech.tts') -and ($ri.requested -eq 'verify_synthesis') -and ($ri.status -eq 'open')) }
}
Check 'review: queue line is a valid speech.tts review item' $rqOk

# ---------- 4) format conversion via audio.ingest ----------
if ($haveFfmpeg -and -not [string]::IsNullOrWhiteSpace($AudioIngestPath) -and (Test-Path -LiteralPath $AudioIngestPath)) {
    $r3 = Run-Tts @{ text = $sentence; speaker = 'Ryan'; format = 'mp3'; audio_ingest_path = $AudioIngestPath }
    Check 'convert: format=mp3' ($null -ne $r3.env.result -and ([string]$r3.env.result.audio.format -eq 'mp3')) "fmt=$($r3.env.result.audio.format)"
    Check 'convert: audio.converted=true' ($null -ne $r3.env.result -and ($r3.env.result.audio.converted -eq $true)) "converted=$($r3.env.result.audio.converted)"
    $mp3Art = @($r3.env.artifacts | Where-Object { [string]$_.kind -eq 'mp3' })
    Check 'convert: mp3 artifact present' ($mp3Art.Count -ge 1)
} else {
    Write-Host "  [SKIP] format conversion (ffmpeg/audio.ingest unavailable)"
}

# ---------- 5) error paths ----------
$rErr1 = Run-Tts @{ text = '' }
Check 'error: no_text' ($null -ne $rErr1.env -and $rErr1.env.status -eq 'error' -and $rErr1.env.error.code -eq 'no_text')
$ev1 = Test-SkillResultEnvelope -Json $rErr1.raw
Check 'error: envelope still schema-valid' ([bool]$ev1.valid)
$rErr2 = Run-Tts @{ text = $sentence; model = 'tts.nonexistent.model' }
Check 'error: model_not_found' ($null -ne $rErr2.env -and $rErr2.env.status -eq 'error' -and $rErr2.env.error.code -eq 'model_not_found')

# ---------- 6) Module 1 wrapper ----------
$wrapInp = [ordered]@{ text = $sentence; speaker = 'Ryan'; pwsh_path = $PwshPath }
if ($PythonPath) { $wrapInp['python_path'] = $PythonPath }
if ($Registry) { $wrapInp['registry'] = $Registry }
if ($ttsInferOverride) { $wrapInp['tts_infer_path'] = $ttsInferOverride }
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
