#requires -Version 7.0
<#
  Invoke-SpeechSttTests.ps1 — tests for speech.stt (Module 11).

  Dual-mode & OS-portable (mirrors Module 10's pre-ship-on-cloud approach + Modules 8/9 mock pattern):
   * -UseMock  : run the REAL skill against a mock whisper-cli (tests/mock-whisper.ps1 + the captured
                 jfk fixture) and a temp registry — no GPU/model needed. This is the cloud pre-ship gate.
   * default   : resolve the real whisper-cli from models.json and transcribe a real speech WAV (Windows/
                 executor). Same assertions hold in both modes (the fixture IS a real jfk transcription).

  The caller supplies -WavFile (Windows: the bundled samples\jfk.wav; cloud: a generated wav — the mock
  ignores audio content). -ExpectText defaults to 'country' (present in the JFK line).
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$WavFile,
    [string]$ExpectText = 'country',
    [string]$WhisperCli,
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

$entry = Join-Path $SkillDir 'Invoke-SpeechStt.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m11-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'

Write-Host "=== speech.stt tests (UseMock=$UseMock) ==="
Write-Host "skill=$entry"

# --- resolve ffmpeg (for generating a WAV when none supplied) ---
$ffmpeg = (Get-Command 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($WavFile)) {
    if ($null -ne $ffmpeg) {
        $WavFile = Join-Path $tmpRoot 'tone16k.wav'
        & $ffmpeg.Source -hide_banner -nostdin -y -f lavfi -i 'sine=frequency=440:duration=2' -ar 16000 -ac 1 -c:a pcm_s16le $WavFile 2>$null | Out-Null
    } else { throw "no -WavFile and no ffmpeg to generate one" }
}
if (-not (Test-Path -LiteralPath $WavFile -PathType Leaf)) { throw "WavFile not found: $WavFile" }

# --- mock shim + temp registry when -UseMock ---
if ($UseMock) {
    $mockPs1 = Join-Path $PSScriptRoot 'mock-whisper.ps1'
    $env:MOCK_WHISPER_JSON = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'fixtures/jfk.whisper.json')).Path
    if ($IsWindows) {
        $WhisperCli = Join-Path $tmpRoot 'mock-whisper.cmd'
        [System.IO.File]::WriteAllText($WhisperCli, "@`"$PwshPath`" -NoProfile -File `"$mockPs1`" %*`r`n", $utf8)
    } else {
        $WhisperCli = Join-Path $tmpRoot 'mock-whisper.sh'
        [System.IO.File]::WriteAllText($WhisperCli, "#!/usr/bin/env bash`nexec `"$PwshPath`" -NoProfile -File `"$mockPs1`" `"`$@`"`n", $utf8)
        & chmod +x $WhisperCli
    }
    if ([string]::IsNullOrWhiteSpace($Registry)) {
        $Registry = Join-Path $tmpRoot 'models.test.json'
        $modelFile = $env:MOCK_WHISPER_JSON   # any existing file satisfies the model-file check
        $reg = [ordered]@{
            schema='lifeorch.model_registry/0.1'; host='cloud-test'
            models=@( [ordered]@{ model_id='stt.whisper.base-en'; type='stt'; wired=$false; name='Whisper base.en (mock)';
                       family='whisper'; format='ggml-bin'; version='ggml-base.en'; engine='whisper.cpp';
                       path=$modelFile; engine_candidates=@($WhisperCli) } )
        }
        [System.IO.File]::WriteAllText($Registry, ($reg | ConvertTo-Json -Depth 8), $utf8)
    }
}

function Run-Stt([hashtable]$inp) {
    if ($WhisperCli -and -not $inp.ContainsKey('whisper_cli_path')) { $inp['whisper_cli_path'] = $WhisperCli }
    if ($Registry -and -not $inp.ContainsKey('registry')) { $inp['registry'] = $Registry }
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
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=mixed' ($man.determinism -eq 'mixed')
Check 'manifest parallel_safe=false' ($man.parallel_safe -eq $false)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=speech.stt' ($man.skill_id -eq 'speech.stt')

# ---------- 2) main transcription (normalize=never) ----------
$r = Run-Stt @{ input = $WavFile; normalize = 'never' }
Check 'transcribe: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'transcribe: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'transcribe: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check "transcribe: text contains '$ExpectText'" ($null -ne $e -and $null -ne $e.result -and ([string]$e.result.text) -match [Regex]::Escape($ExpectText)) "text=$($e.result.text)"
Check 'transcribe: >=1 segment' ($null -ne $e.result -and [int]$e.result.segment_count -ge 1) "segs=$($e.result.segment_count)"
$seg0 = $null; if ($null -ne $e.result -and (@($e.result.segments).Count -gt 0)) { $seg0 = @($e.result.segments)[0] }
Check 'transcribe: seg0 has timestamps' ($null -ne $seg0 -and -not [string]::IsNullOrWhiteSpace([string]$seg0.t0) -and ([long]$seg0.t1_ms -ge [long]$seg0.t0_ms)) "t0=$($seg0.t0) t1=$($seg0.t1)"
Check 'transcribe: overall confidence in (0,1]' ($null -ne $e.confidence -and [double]$e.confidence -gt 0 -and [double]$e.confidence -le 1) "conf=$($e.confidence)"
Check 'transcribe: seg0 has per-segment confidence' ($null -ne $seg0 -and $null -ne $seg0.confidence -and [double]$seg0.confidence -gt 0) "segconf=$($seg0.confidence)"
Check 'transcribe: model_provenance[1], engine whisper.cpp' (@($e.model_provenance).Count -eq 1 -and (@($e.model_provenance)[0].engine -eq 'whisper.cpp')) "n=$(@($e.model_provenance).Count)"
$arts = @($e.artifacts)
$kinds = @($arts | ForEach-Object { $_.kind })
$paths = @($arts | ForEach-Object { [string]$_.path })
$hasWj = @($paths | Where-Object { $_ -match 'whisper\.json$' }).Count -eq 1
$hasSrt = @($paths | Where-Object { $_ -match 'whisper\.srt$' }).Count -eq 1
$hasTxt = @($paths | Where-Object { $_ -match 'whisper\.txt$' }).Count -eq 1
$hasTj = @($paths | Where-Object { $_ -match 'transcript\.json$' }).Count -eq 1
$hasTm = @($paths | Where-Object { $_ -match 'transcript\.md$' }).Count -eq 1
Check 'transcribe: artifacts include whisper.json/.srt/.txt + transcript.json/.md' ($hasWj -and $hasSrt -and $hasTxt -and $hasTj -and $hasTm) "kinds=$($kinds -join ',')"
$wjArt = @($arts | Where-Object { [string]$_.path -match 'whisper\.json$' })[0]
$shaOk = $false; if ($null -ne $wjArt) { $shaOk = ((Get-Sha256HexFile ([string]$wjArt.path)) -eq [string]$wjArt.sha256) }
Check 'transcribe: whisper.json artifact sha256 matches file' $shaOk

# ---------- 3) review-queue routing (forced low threshold) ----------
$rq = Join-Path $tmpRoot 'review_queue.jsonl'
if (Test-Path -LiteralPath $rq) { Remove-Item -LiteralPath $rq -Force }
$r2 = Run-Stt @{ input = $WavFile; normalize = 'never'; segment_confidence_threshold = 0.999; review_queue_path = $rq }
$e2 = $r2.env
Check 'review: flagged_count >= 1' ($null -ne $e2.result -and [int]$e2.result.review.flagged_count -ge 1) "flagged=$($e2.result.review.flagged_count)"
$rqOk = $false
if (Test-Path -LiteralPath $rq) {
    $line = (Get-Content -LiteralPath $rq -TotalCount 1)
    if ($line) { $ri = $line | ConvertFrom-Json; $rqOk = (($ri.schema -eq 'lifeorch.review.item/0.1') -and ($ri.flagged_by -eq 'speech.stt') -and ($ri.requested -eq 'verify_transcription') -and ($ri.status -eq 'open')) }
}
Check 'review: queue line is a valid speech.stt review item' $rqOk

# ---------- 4) normalization: auto-on-ready feeds direct; always re-encodes via audio.ingest ----------
# resolve audio.ingest for the 'always' path
if ([string]::IsNullOrWhiteSpace($AudioIngestPath)) {
    $aic = Join-Path $SkillDir '..\10-audio-ingest\Invoke-AudioIngest.ps1'
    if (Test-Path -LiteralPath $aic -PathType Leaf) { $AudioIngestPath = (Resolve-Path -LiteralPath $aic).Path }
}
$isReadyWav = $false
$fp = (Get-Command 'ffprobe' -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch '[\\/][Pp]ython[^\\/]*[\\/][Ss]cripts[\\/]' } | Select-Object -First 1)
if ($null -eq $fp -and $null -ne $ffmpeg) { $sib = Join-Path (Split-Path -Parent $ffmpeg.Source) (( Split-Path -Leaf $ffmpeg.Source) -replace 'ffmpeg','ffprobe'); if (Test-Path -LiteralPath $sib) { $fp = @{ Source = $sib } } }
$rAuto = Run-Stt @{ input = $WavFile; normalize = 'auto' }
# a 16k mono s16 wav should feed directly (normalized=false); jfk.wav qualifies too
Check 'normalize auto: ready WAV fed directly (normalized=false)' ($null -ne $rAuto.env.result -and ($rAuto.env.result.input.normalized -eq $false)) "normalized=$($rAuto.env.result.input.normalized)"
if (-not [string]::IsNullOrWhiteSpace($AudioIngestPath) -and (Test-Path -LiteralPath $AudioIngestPath)) {
    $rAlways = Run-Stt @{ input = $WavFile; normalize = 'always'; audio_ingest_path = $AudioIngestPath }
    Check 'normalize always: input.normalized=true' ($null -ne $rAlways.env.result -and ($rAlways.env.result.input.normalized -eq $true)) "normalized=$($rAlways.env.result.input.normalized)"
    Check 'normalize always: output is 16 kHz' ($null -ne $rAlways.env.result -and ([int]$rAlways.env.result.audio.sample_rate -eq 16000)) "sr=$($rAlways.env.result.audio.sample_rate)"
    Check 'normalize always: still transcribes' ($null -ne $rAlways.env.result -and [int]$rAlways.env.result.segment_count -ge 1) "segs=$($rAlways.env.result.segment_count)"
} else {
    Write-Host "  [SKIP] normalize-always (audio.ingest not resolvable)"
}

# ---------- 5) error paths ----------
$rErr1 = Run-Stt @{ input = (Join-Path $tmpRoot 'does-not-exist.wav'); normalize = 'never' }
Check 'error: input_not_found' ($null -ne $rErr1.env -and $rErr1.env.status -eq 'error' -and $rErr1.env.error.code -eq 'input_not_found')
$ev1 = Test-SkillResultEnvelope -Json $rErr1.raw
Check 'error: envelope still schema-valid' ([bool]$ev1.valid)
$rErr2 = Run-Stt @{ input = $WavFile; normalize = 'never'; whisper_cli_path = (Join-Path $tmpRoot 'no-whisper.exe') }
Check 'error: whisper_cli_not_found' ($null -ne $rErr2.env -and $rErr2.env.status -eq 'error' -and $rErr2.env.error.code -eq 'whisper_cli_not_found')

# ---------- 6) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $WavFile; normalize = 'never'; pwsh_path = $PwshPath }
if ($WhisperCli) { $wrapInp['whisper_cli_path'] = $WhisperCli }
if ($Registry) { $wrapInp['registry'] = $Registry }
$wrapJson = ($wrapInp | ConvertTo-Json -Compress -Depth 8)
$tmpErr = New-TemporaryFile
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$wrapArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Resolve-Path -LiteralPath $wrapper).Path,'-SkillDir',$SkillDir,'-InputsJson',$wrapJson,'-ArtifactRoot',$artRoot,'-PwshPath',$PwshPath)
$wout = & $PwshPath @wrapArgs 2> $tmpErr.FullName
$wec = $LASTEXITCODE
$ErrorActionPreference = $prev
Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
$wrep = $null; try { $wrep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
Check 'wrapper: report manifest_valid + invoked + envelope_valid' ($null -ne $wrep -and $wrep.manifest_valid -and $wrep.invoked -and $wrep.envelope_valid) "exit=$wec"

# ---------- 7) no orphaned processes ----------
$orphans = @()
try { $orphans = @(Get-Process -Name 'whisper-cli','llama-server' -ErrorAction SilentlyContinue) } catch { }
Check 'no orphaned whisper-cli/llama-server' ($orphans.Count -eq 0) "orphans=$($orphans.Count)"

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
