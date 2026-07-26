#requires -Version 7.0
<#
  Tests for gen.music (Module 24).
  Default: MOCK mode -- runs the REAL Invoke-GenMusic.ps1 against tests/mock-worker.py (stdlib, no torch/
  transformers/soundfile), so the full parse/confidence/review/envelope path runs on the cloud Linux box before
  any bytes ship. -Live: runs the REAL transformers MusicGen worker + real registry on the Windows executor (a
  real MusicGen generation + mp3 conversion via the real audio.ingest). Runs the skill as a child process
  (async-drained) so the skill's `exit 0` never ends this harness and native stderr never trips StrictMode.
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath,
    [string]$Registry
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wrapper = Join-Path $SkillDir 'Invoke-GenMusic.ps1'
$mockWorker = Join-Path $PSScriptRoot 'mock-worker.py'
$module1Dir = (Resolve-Path (Join-Path $SkillDir '..\01-skill-bootstrap')).Path
$invokeSkill = Join-Path $module1Dir 'Invoke-Skill.ps1'
$contractPsm = Join-Path $module1Dir 'lib\SkillContract.psm1'
# Resolve the current pwsh robustly: GetCurrentProcess().MainModule can be dotnet.exe when launched via
# the .dotnet tools pwsh shim on Windows, so use $PSHOME (the real pwsh install dir) instead.
$pwshExe = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) {
    $gc = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($gc) { $pwshExe = $gc.Source } else { $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
}

$pass = 0; $fail = 0; $failMsgs = New-Object System.Collections.Generic.List[string]
function Ok([string]$name) { $script:pass++; Write-Host ("  PASS  $name") }
function Bad([string]$name, [string]$why) { $script:fail++; $script:failMsgs.Add("$name :: $why"); Write-Host ("  FAIL  $name -- $why") }
function Assert([bool]$c, [string]$name, [string]$why='') { if ($c) { Ok $name } else { Bad $name $why } }

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

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("genmus-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'art'
$rqPath = Join-Path $tmpRoot 'review_queue.jsonl'

# ---- resolve python + worker + registry per mode ----
if ($Live) {
    if ([string]::IsNullOrWhiteSpace($Registry)) { $Registry = (Resolve-Path (Join-Path $SkillDir '..\07-model-gateway\models.json')).Path }
    $inferPath = Join-Path $SkillDir 'music_gen_infer.py'
    $usePython = $PythonPath   # empty -> wrapper resolves from registry engine_env
    Write-Host ("=== gen.music tests (LIVE) registry=$Registry ===")
} else {
    $py = Get-Command python3 -ErrorAction SilentlyContinue; if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $py) { throw 'no python3/python on PATH for the mock gate' }
    $usePython = $py.Source
    $inferPath = $mockWorker
    $fakeModel = Join-Path $tmpRoot 'model\musicgen-small'
    New-Item -ItemType Directory -Path $fakeModel -Force | Out-Null
    $Registry = Join-Path $tmpRoot 'models.json'
    $regObj = [ordered]@{
        schema='lifeorch.model_registry/0.1'
        defaults=[ordered]@{ music='music.musicgen-small' }
        tiers=[ordered]@{ music=[ordered]@{ small='music.musicgen-small' } }
        models=@(
            [ordered]@{ model_id='music.musicgen-small'; type='music-gen'; wired=$false; name='MusicGen Small (mock)'; family='musicgen'; format='transformers-dir'; version='musicgen-small-mock'; path=$fakeModel; engine='transformers'; engine_env=$usePython; license='CC-BY-NC-4.0'; sampling_rate=32000; frame_rate=50; params=[ordered]@{ dtype='float32'; max_duration_s=30 } }
        )
    }
    [System.IO.File]::WriteAllText($Registry, ($regObj | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    Write-Host ("=== gen.music tests (MOCK) python=$usePython ===")
}

# ---- invoke helper: run the real wrapper as a child, return parsed envelope ----
function Invoke-Gen([hashtable]$named, [string]$inputsJson='', [hashtable]$over=@{}) {
    $reg = if ($over.ContainsKey('Registry')) { $over['Registry'] } else { $Registry }
    $pyp = if ($over.ContainsKey('PythonPath')) { $over['PythonPath'] } else { $usePython }
    $inf = if ($over.ContainsKey('MusicInferPath')) { $over['MusicInferPath'] } else { $inferPath }
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-NoProfile'); $a.Add('-File'); $a.Add($wrapper)
    foreach ($k in $named.Keys) { $a.Add('-' + $k); $a.Add([string]$named[$k]) }
    if ($inputsJson) { $a.Add('-InputsJson'); $a.Add($inputsJson) }
    $a.Add('-Registry'); $a.Add($reg)
    if (-not [string]::IsNullOrWhiteSpace($pyp)) { $a.Add('-PythonPath'); $a.Add($pyp) }
    $a.Add('-MusicInferPath'); $a.Add($inf)
    $a.Add('-ReviewQueuePath'); $a.Add($rqPath)
    $a.Add('-ArtifactRoot'); $a.Add($artRoot)
    if ($pwshExe) { $a.Add('-PwshPath'); $a.Add($pwshExe) }
    $r = Run-Proc $pwshExe $a.ToArray()
    $env = $null
    try { $env = $r.stdout | ConvertFrom-Json } catch { }
    return $env
}
function RqCount { if (Test-Path -LiteralPath $rqPath) { return @(Get-Content -LiteralPath $rqPath).Count } return 0 }

# ---- 1. manifest validates ----
try {
    Import-Module $contractPsm -Force
    $mv = Test-SkillManifest -Path (Join-Path $SkillDir 'skill.json')
    Assert ([bool]$mv.valid) 'manifest.validates' ("errors: " + (($mv.errors) -join '; '))
} catch { Bad 'manifest.validates' $_.Exception.Message }

# ---- 2. happy path ----
$e = Invoke-Gen @{ Prompt='upbeat 8-bit chiptune, energetic'; Duration='2'; Seed='42' }
Assert ($null -ne $e -and $e.status -eq 'ok') 'happy.status_ok' "status=$($e.status)"
Assert ($e.skill_id -eq 'gen.music') 'happy.skill_id' "skill_id=$($e.skill_id)"
Assert ($e.contract_version -eq '0.2') 'happy.contract_version' "cv=$($e.contract_version)"
if ($e -and $e.status -eq 'ok' -and $e.result) {
    $ap = [string]$e.result.audio.path
    Assert (Test-Path -LiteralPath $ap -PathType Leaf) 'happy.audio_exists' "path=$ap"
    $fh = (Get-FileHash -LiteralPath $ap -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ($fh -eq [string]$e.result.audio.sha256) 'happy.sha_matches_file' "$fh vs $($e.result.audio.sha256)"
    Assert ([int]$e.result.audio.sample_rate -eq 32000) 'happy.sample_rate' "sr=$($e.result.audio.sample_rate)"
    Assert ([double]$e.result.audio.duration_s -gt 0) 'happy.duration' "dur=$($e.result.audio.duration_s)"
    Assert ([string]$e.result.audio.format -eq 'wav') 'happy.format_wav' "fmt=$($e.result.audio.format)"
    Assert ($null -ne $e.confidence -and [double]$e.confidence -ge 0.9) 'happy.confidence_high' "conf=$($e.confidence)"
    Assert (@($e.model_provenance).Count -eq 1) 'happy.provenance_one' "count=$(@($e.model_provenance).Count)"
    Assert ([string]$e.model_provenance[0].engine -eq 'transformers') 'happy.provenance_engine' "engine=$($e.model_provenance[0].engine)"
    Assert ([int]$e.result.request.max_new_tokens -gt 0) 'happy.tokens' "tokens=$($e.result.request.max_new_tokens)"
} else { Bad 'happy.result' 'no ok result' }

# ---- 3. WAV magic (RIFF/WAVE) ----
if ($e -and $e.status -eq 'ok') {
    $b = [System.IO.File]::ReadAllBytes([string]$e.result.audio.path)
    Assert ($b.Length -ge 12 -and $b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46 -and $b[8] -eq 0x57 -and $b[9] -eq 0x41 -and $b[10] -eq 0x56 -and $b[11] -eq 0x45) 'happy.wav_magic' "bytes: $($b[0]),$($b[1]),$($b[2]),$($b[3])"
}

# ---- 4. InputsJson parity ----
$e = Invoke-Gen @{} '{"prompt":"calm ambient piano","duration":2,"seed":7}'
Assert ($null -ne $e -and $e.status -eq 'ok' -and $e.result.input.prompt -eq 'calm ambient piano') 'inputsjson.parity' "status=$($e.status)"

# ---- 5. named overrides InputsJson ----
$e = Invoke-Gen @{ Prompt='named wins'; Duration='2' } '{"prompt":"json loses"}'
Assert ($null -ne $e -and $e.result.input.prompt -eq 'named wins') 'inputsjson.named_wins' "prompt=$($e.result.input.prompt)"

# ---- 6. params echo (accept ok|partial: a real low-RMS generation may legitimately flag to review) ----
$e = Invoke-Gen @{ Prompt='a bright cheerful acoustic guitar melody'; Duration='3'; Guidance='4.5'; Temperature='0.8'; TopK='100'; TopP='0.9'; Seed='123' }
if ($e -and (@('ok','partial') -contains $e.status)) {
    Assert ([double]$e.result.request.duration_s -eq 3.0) 'echo.duration' "dur=$($e.result.request.duration_s)"
    Assert ([double]$e.result.request.guidance -eq 4.5) 'echo.guidance' "g=$($e.result.request.guidance)"
    Assert ([double]$e.result.request.temperature -eq 0.8) 'echo.temperature' "t=$($e.result.request.temperature)"
    Assert ([int]$e.result.request.top_k -eq 100) 'echo.top_k' "k=$($e.result.request.top_k)"
    Assert ([double]$e.result.request.top_p -eq 0.9) 'echo.top_p' "p=$($e.result.request.top_p)"
    Assert ([int]$e.result.request.seed -eq 123) 'echo.seed' "seed=$($e.result.request.seed)"
} else { Bad 'echo.params' "status=$($e.status)" }

# ---- 7. seed -1 records a concrete seed ----
$e = Invoke-Gen @{ Prompt='random seed test'; Duration='2'; Seed='-1' }
Assert ($null -ne $e -and $e.status -eq 'ok' -and [int]$e.result.request.seed -ge 0) 'seed.random_recorded' "seed=$($e.result.request.seed)"

# ---- 8. error paths (wrapper-level validation; mode-agnostic) ----
$e = Invoke-Gen @{ Prompt='' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'no_prompt') 'err.no_prompt' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Format='aiff' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_format') 'err.invalid_format' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Duration='0' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_duration') 'err.duration_zero' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Duration='60' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_duration') 'err.duration_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Guidance='99' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_guidance') 'err.guidance' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Temperature='5' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_temperature') 'err.temperature' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; TopP='2' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_sampling') 'err.sampling' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; SampleRate='100' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_sample_rate') 'err.sample_rate' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Model='music.does-not-exist' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'model_not_found') 'err.model_not_found' "code=$($e.error.code)"

# ---- 9. python_not_found (bad -PythonPath wins) ----
$e = Invoke-Gen @{ Prompt='x' } '' @{ PythonPath='/definitely/not/a/python-xyz' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'python_not_found') 'err.python_not_found' "code=$($e.error.code)"

# ---- 10. mock-only: confidence + review branches + generation_failed + model_dir_missing + tier ----
if (-not $Live) {
    $before = RqCount
    $e = Invoke-Gen @{ Prompt='__SILENT__ nothing here'; Duration='2' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -le 0.15) 'review.silent_conf' "conf=$($e.confidence) status=$($e.status)"
    Assert ($e.result.review.flagged -eq $true) 'review.silent_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before + 1) 'review.silent_queued' "$before -> $(RqCount)"
    if ((RqCount) -gt 0) {
        $last = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json
        Assert ($last.flagged_by -eq 'gen.music' -and $last.requested -eq 'verify_generation' -and $last.reason -eq 'failed_transform') 'review.item_shape' "by=$($last.flagged_by) req=$($last.requested) reason=$($last.reason)"
    }
    $before2 = RqCount
    $e = Invoke-Gen @{ Prompt='__LOWRMS__ faint'; Duration='2' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -eq 0.3) 'review.lowrms_conf' "conf=$($e.confidence)"
    Assert ((RqCount) -eq $before2 + 1) 'review.lowrms_queued' "queued"
    if ((RqCount) -gt 0) { $l2 = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json; Assert ($l2.reason -eq 'low_confidence') 'review.lowrms_reason' "reason=$($l2.reason)" }

    $before3 = RqCount
    $e = Invoke-Gen @{ Prompt='a normal good tune'; Duration='2' }
    Assert ($e.status -eq 'ok' -and $e.result.review.flagged -eq $false) 'review.good_not_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before3) 'review.good_no_queue' "no new item"

    $e = Invoke-Gen @{ Prompt='__FAIL__ boom'; Duration='2' }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'generation_failed') 'err.generation_failed' "code=$($e.error.code)"

    $badReg = Join-Path $tmpRoot 'models-badpath.json'
    $rb = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ music='music.musicgen-small' }; tiers=[ordered]@{ music=[ordered]@{ small='music.musicgen-small' } };
        models=@([ordered]@{ model_id='music.musicgen-small'; type='music-gen'; wired=$false; name='bad'; family='musicgen'; format='transformers-dir'; path=(Join-Path $tmpRoot 'no-such-model-dir'); engine='transformers'; engine_env=$usePython; params=[ordered]@{ dtype='float32' } }) }
    [System.IO.File]::WriteAllText($badReg, ($rb | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badReg }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'model_dir_missing') 'err.model_dir_missing' "code=$($e.error.code)"

    $e = Invoke-Gen @{ Prompt='tier test'; Duration='2'; Tier='small' }
    Assert ($e.status -eq 'ok' -and $e.result.model.id -eq 'music.musicgen-small') 'tier.resolves' "model=$($e.result.model.id)"

    # unsupported engine (registry says something else)
    $badEng = Join-Path $tmpRoot 'models-badeng.json'
    $reb = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ music='music.musicgen-small' }; tiers=[ordered]@{ music=[ordered]@{ small='music.musicgen-small' } };
        models=@([ordered]@{ model_id='music.musicgen-small'; type='music-gen'; wired=$false; name='bad'; family='musicgen'; format='x'; path=$fakeModel; engine='audiocraft'; engine_env=$usePython; params=[ordered]@{} }) }
    [System.IO.File]::WriteAllText($badEng, ($reb | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badEng }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'unsupported_engine') 'err.unsupported_engine' "code=$($e.error.code)"
}

# ---- 11. Module 1 wrapper integration ----
try {
    $ijObj = [ordered]@{ prompt='wrapper integration tune'; duration=2; registry=$Registry; python_path=$usePython; music_infer_path=$inferPath; review_queue_path=$rqPath }
    $ij = ($ijObj | ConvertTo-Json -Compress)
    $rw = Run-Proc $pwshExe @('-NoProfile','-File',$invokeSkill,'-SkillDir',$SkillDir,'-InputsJson',$ij,'-PwshPath',$pwshExe)
    $rep = $null; try { $rep = $rw.stdout | ConvertFrom-Json } catch { }
    Assert ($null -ne $rep -and $rep.manifest_valid -eq $true) 'wrapper.manifest_valid' "mv=$($rep.manifest_valid)"
    Assert ($rep.envelope_valid -eq $true) 'wrapper.envelope_valid' ("errs: " + (($rep.envelope_errors) -join '; '))
    Assert ($rep.envelope.skill_id -eq 'gen.music') 'wrapper.skill_id' "id=$($rep.envelope.skill_id)"
} catch { Bad 'wrapper.integration' $_.Exception.Message }

# ---- live-only extras ----
if ($Live) {
    $r1 = Invoke-Gen @{ Prompt='a gentle lofi hip hop beat'; Duration='4'; Seed='2024' }
    $r2 = Invoke-Gen @{ Prompt='a gentle lofi hip hop beat'; Duration='4'; Seed='2024' }
    if ($r1 -and $r2 -and $r1.status -eq 'ok' -and $r2.status -eq 'ok') {
        $same = ([string]$r1.result.audio.sha256 -eq [string]$r2.result.audio.sha256)
        Assert $same 'live.same_seed_reproducible' "sha1=$($r1.result.audio.sha256) sha2=$($r2.result.audio.sha256)"
        Assert ([double]$r1.result.audio.rms -gt 0.02) 'live.audible' "rms=$($r1.result.audio.rms)"
        Assert ($r1.result.review.flagged -eq $false) 'live.good_not_flagged' "flagged=$($r1.result.review.flagged)"
    } else { Bad 'live.same_seed_ran' "r1=$($r1.status) r2=$($r2.status)" }
    $em = Invoke-Gen @{ Prompt='a warm jazz piano trio'; Duration='4'; Format='mp3' }
    if ($em -and $em.status -eq 'ok') {
        Assert ([string]$em.result.audio.format -eq 'mp3' -and [bool]$em.result.audio.converted -eq $true) 'live.mp3_converted' "fmt=$($em.result.audio.format) conv=$($em.result.audio.converted)"
        $mb = [System.IO.File]::ReadAllBytes([string]$em.result.audio.path)
        $isMp3 = ($mb[0] -eq 0x49 -and $mb[1] -eq 0x44 -and $mb[2] -eq 0x33) -or ($mb[0] -eq 0xFF -and ($mb[1] -band 0xE0) -eq 0xE0)
        Assert $isMp3 'live.mp3_magic' ("bytes: $($mb[0]),$($mb[1])")
    } else { Bad 'live.mp3' "status=$($em.status)" }
    $er = Invoke-Gen @{ Prompt='resample test'; Duration='3'; SampleRate='16000' }
    if ($er -and $er.status -eq 'ok') {
        Assert ([int]$er.result.audio.sample_rate -eq 16000 -and [bool]$er.result.audio.converted -eq $true) 'live.resample' "sr=$($er.result.audio.sample_rate) conv=$($er.result.audio.converted)"
    } else { Bad 'live.resample' "status=$($er.status)" }
}

Write-Host ('')
Write-Host ("RESULT gen.music tests: PASS=$pass FAIL=$fail")
if ($fail -gt 0) { foreach ($m in $failMsgs) { Write-Host ("  - $m") } }
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($fail -gt 0) { exit 1 } else { exit 0 }
