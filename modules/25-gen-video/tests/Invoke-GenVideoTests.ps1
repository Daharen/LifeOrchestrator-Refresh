#requires -Version 7.0
<#
  Tests for gen.video (Module 25).
  Default: MOCK mode -- runs the REAL Invoke-GenVideo.ps1 against tests/mock-worker.py (stdlib, no torch/
  diffusers/ffmpeg), so the full parse/confidence/review/envelope path runs on the cloud Linux box before any
  bytes ship. -Live: runs the REAL AnimateDiff worker + real registry on the Windows executor (a real
  AnimateDiff-Lightning generation, mp4 via ffmpeg + gif via Pillow, seed reproducibility). Runs the skill as a
  child process (async-drained) so the skill's `exit 0` never ends this harness and native stderr never trips
  StrictMode.
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

$wrapper = Join-Path $SkillDir 'Invoke-GenVideo.ps1'
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

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("genvid-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'art'
$rqPath = Join-Path $tmpRoot 'review_queue.jsonl'

# ---- resolve python + worker + registry per mode ----
if ($Live) {
    if ([string]::IsNullOrWhiteSpace($Registry)) { $Registry = (Resolve-Path (Join-Path $SkillDir '..\07-model-gateway\models.json')).Path }
    $inferPath = Join-Path $SkillDir 'video_gen_infer.py'
    $usePython = $PythonPath   # empty -> wrapper resolves from registry engine_env
    Write-Host ("=== gen.video tests (LIVE) registry=$Registry ===")
} else {
    $py = Get-Command python3 -ErrorAction SilentlyContinue; if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $py) { throw 'no python3/python on PATH for the mock gate' }
    $usePython = $py.Source
    $inferPath = $mockWorker
    $fakeBase = Join-Path $tmpRoot 'model\sd15'
    New-Item -ItemType Directory -Path $fakeBase -Force | Out-Null
    $fakeAdapter = Join-Path $tmpRoot 'model\adapter.safetensors'
    Set-Content -LiteralPath $fakeAdapter -Value 'mock' -NoNewline
    $Registry = Join-Path $tmpRoot 'models.json'
    $regObj = [ordered]@{
        schema='lifeorch.model_registry/0.1'
        defaults=[ordered]@{ video='video.animatediff-lightning' }
        tiers=[ordered]@{ video=[ordered]@{ lightning='video.animatediff-lightning' } }
        models=@(
            [ordered]@{ model_id='video.animatediff-lightning'; type='video-gen'; wired=$false; name='AnimateDiff-Lightning (mock)'; family='animatediff'; format='diffusers+motion-adapter'; version='animatediff-lightning-mock'; base=$fakeBase; adapter=$fakeAdapter; path=$fakeBase; engine='diffusers'; engine_env=$usePython; license='CreativeML-OpenRAIL-M'; params=[ordered]@{ dtype='float16'; native_resolution=512 } }
        )
    }
    [System.IO.File]::WriteAllText($Registry, ($regObj | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    Write-Host ("=== gen.video tests (MOCK) python=$usePython ===")
}

# ---- invoke helper: run the real wrapper as a child, return parsed envelope ----
function Invoke-Gen([hashtable]$named, [string]$inputsJson='', [hashtable]$over=@{}) {
    $reg = if ($over.ContainsKey('Registry')) { $over['Registry'] } else { $Registry }
    $pyp = if ($over.ContainsKey('PythonPath')) { $over['PythonPath'] } else { $usePython }
    $inf = if ($over.ContainsKey('VideoInferPath')) { $over['VideoInferPath'] } else { $inferPath }
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-NoProfile'); $a.Add('-File'); $a.Add($wrapper)
    foreach ($k in $named.Keys) { $a.Add('-' + $k); $a.Add([string]$named[$k]) }
    if ($inputsJson) { $a.Add('-InputsJson'); $a.Add($inputsJson) }
    $a.Add('-Registry'); $a.Add($reg)
    if (-not [string]::IsNullOrWhiteSpace($pyp)) { $a.Add('-PythonPath'); $a.Add($pyp) }
    $a.Add('-VideoInferPath'); $a.Add($inf)
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
$e = Invoke-Gen @{ Prompt='a drone shot over a misty forest at sunrise'; Seed='42' }
Assert ($null -ne $e -and $e.status -eq 'ok') 'happy.status_ok' "status=$($e.status)"
Assert ($e.skill_id -eq 'gen.video') 'happy.skill_id' "skill_id=$($e.skill_id)"
Assert ($e.contract_version -eq '0.2') 'happy.contract_version' "cv=$($e.contract_version)"
if ($e -and $e.status -eq 'ok' -and $e.result) {
    $vp = [string]$e.result.video.path
    Assert (Test-Path -LiteralPath $vp -PathType Leaf) 'happy.video_exists' "path=$vp"
    $fh = (Get-FileHash -LiteralPath $vp -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ($fh -eq [string]$e.result.video.sha256) 'happy.sha_matches_file' "$fh vs $($e.result.video.sha256)"
    Assert ([string]$e.result.video.format -eq 'mp4') 'happy.format_mp4' "fmt=$($e.result.video.format)"
    Assert ([int]$e.result.video.num_frames -eq 16) 'happy.num_frames' "nf=$($e.result.video.num_frames)"
    Assert ([double]$e.result.video.duration_s -gt 0) 'happy.duration' "dur=$($e.result.video.duration_s)"
    Assert ($null -ne $e.confidence -and [double]$e.confidence -ge 0.9) 'happy.confidence_high' "conf=$($e.confidence)"
    Assert (@($e.model_provenance).Count -eq 1) 'happy.provenance_one' "count=$(@($e.model_provenance).Count)"
    Assert ([string]$e.model_provenance[0].engine -eq 'diffusers') 'happy.provenance_engine' "engine=$($e.model_provenance[0].engine)"
    Assert ([double]$e.result.motion.mean_abs_interframe_diff -gt 1.5) 'happy.has_motion' "motion=$($e.result.motion.mean_abs_interframe_diff)"
} else { Bad 'happy.result' 'no ok result' }

# ---- 3. InputsJson parity ----
$e = Invoke-Gen @{} '{"prompt":"a candle flame flickering","seed":7}'
Assert ($null -ne $e -and $e.status -eq 'ok' -and $e.result.input.prompt -eq 'a candle flame flickering') 'inputsjson.parity' "status=$($e.status)"

# ---- 4. named overrides InputsJson ----
$e = Invoke-Gen @{ Prompt='named wins' } '{"prompt":"json loses"}'
Assert ($null -ne $e -and $e.result.input.prompt -eq 'named wins') 'inputsjson.named_wins' "prompt=$($e.result.input.prompt)"

# ---- 5. params echo (NumFrames kept at 16: AnimateDiff temporal attention scales with frames; >16 risks OOM on 11 GB) ----
$e = Invoke-Gen @{ Prompt='a bright cheerful sunrise timelapse'; NumFrames='16'; Width='512'; Height='384'; Steps='4'; Guidance='1.5'; Fps='12'; Seed='123' }
if ($e -and (@('ok','partial') -contains $e.status)) {
    Assert ([int]$e.result.request.num_frames -eq 16) 'echo.num_frames' "nf=$($e.result.request.num_frames)"
    Assert ([int]$e.result.request.width -eq 512 -and [int]$e.result.request.height -eq 384) 'echo.size' "$($e.result.request.width)x$($e.result.request.height)"
    Assert ([int]$e.result.request.steps -eq 4) 'echo.steps' "steps=$($e.result.request.steps)"
    Assert ([double]$e.result.request.guidance -eq 1.5) 'echo.guidance' "g=$($e.result.request.guidance)"
    Assert ([int]$e.result.request.fps -eq 12) 'echo.fps' "fps=$($e.result.request.fps)"
    Assert ([int]$e.result.request.seed -eq 123) 'echo.seed' "seed=$($e.result.request.seed)"
} else { Bad 'echo.params' "status=$($e.status)" }

# ---- 6. seed -1 records a concrete seed ----
$e = Invoke-Gen @{ Prompt='random seed test'; Seed='-1' }
Assert ($null -ne $e -and $e.status -eq 'ok' -and [int]$e.result.request.seed -ge 0) 'seed.random_recorded' "seed=$($e.result.request.seed)"

# ---- 7. error paths (wrapper-level validation; mode-agnostic) ----
$e = Invoke-Gen @{ Prompt='' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'no_prompt') 'err.no_prompt' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Format='avi' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_format') 'err.invalid_format' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; NumFrames='0' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_num_frames') 'err.num_frames_zero' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; NumFrames='200' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_num_frames') 'err.num_frames_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Width='513' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_size') 'err.size_mult8' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Height='2048' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_size') 'err.size_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Steps='0' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_steps') 'err.steps_zero' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Steps='50' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_steps') 'err.steps_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Guidance='99' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_guidance') 'err.guidance' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Fps='0' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_fps') 'err.fps_zero' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Fps='60' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_fps') 'err.fps_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Model='video.does-not-exist' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'model_not_found') 'err.model_not_found' "code=$($e.error.code)"

# ---- 8. python_not_found (bad -PythonPath wins) ----
$e = Invoke-Gen @{ Prompt='x' } '' @{ PythonPath='/definitely/not/a/python-xyz' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'python_not_found') 'err.python_not_found' "code=$($e.error.code)"

# ---- 9. mock-only: confidence + review branches + failure + missing base/adapter + unsupported engine + tier ----
if (-not $Live) {
    $before = RqCount
    $e = Invoke-Gen @{ Prompt='__BLANK__ nothing here' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -le 0.15) 'review.blank_conf' "conf=$($e.confidence) status=$($e.status)"
    Assert ($e.result.review.flagged -eq $true) 'review.blank_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before + 1) 'review.blank_queued' "$before -> $(RqCount)"
    if ((RqCount) -gt 0) {
        $last = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json
        Assert ($last.flagged_by -eq 'gen.video' -and $last.requested -eq 'verify_generation' -and $last.reason -eq 'failed_transform') 'review.item_shape' "by=$($last.flagged_by) req=$($last.requested) reason=$($last.reason)"
    }
    $before2 = RqCount
    $e = Invoke-Gen @{ Prompt='__STATIC__ a frozen still' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -eq 0.3 -and [string]$e.result.confidence.reason -eq 'static_no_motion') 'review.static_conf' "conf=$($e.confidence) reason=$($e.result.confidence.reason)"
    Assert ((RqCount) -eq $before2 + 1) 'review.static_queued' "queued"
    if ((RqCount) -gt 0) { $l2 = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json; Assert ($l2.reason -eq 'low_confidence') 'review.static_reason' "reason=$($l2.reason)" }

    # low_detail yields confidence exactly 0.5 == threshold, so it is NOT flagged (0.5 -lt 0.5 is false) -> status ok
    $e = Invoke-Gen @{ Prompt='__LOWDETAIL__ muddy' }
    Assert ($e.status -eq 'ok' -and [double]$e.confidence -eq 0.5 -and [string]$e.result.confidence.reason -eq 'low_detail' -and $e.result.review.flagged -eq $false) 'review.lowdetail_boundary' "conf=$($e.confidence) reason=$($e.result.confidence.reason) status=$($e.status)"

    $before3 = RqCount
    $e = Invoke-Gen @{ Prompt='a normal good clip of waves' }
    Assert ($e.status -eq 'ok' -and $e.result.review.flagged -eq $false) 'review.good_not_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before3) 'review.good_no_queue' "no new item"

    $e = Invoke-Gen @{ Prompt='__FAIL__ boom' }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'generation_failed') 'err.generation_failed' "code=$($e.error.code)"

    # missing base dir
    $badBase = Join-Path $tmpRoot 'models-badbase.json'
    $rb = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ video='video.animatediff-lightning' }; tiers=[ordered]@{ video=[ordered]@{ lightning='video.animatediff-lightning' } };
        models=@([ordered]@{ model_id='video.animatediff-lightning'; type='video-gen'; wired=$false; name='bad'; family='animatediff'; format='x'; base=(Join-Path $tmpRoot 'no-such-base'); adapter=$fakeAdapter; path=$fakeBase; engine='diffusers'; engine_env=$usePython; params=[ordered]@{ dtype='float16' } }) }
    [System.IO.File]::WriteAllText($badBase, ($rb | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badBase }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'base_dir_missing') 'err.base_dir_missing' "code=$($e.error.code)"

    # missing adapter
    $badAd = Join-Path $tmpRoot 'models-badadapter.json'
    $ra = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ video='video.animatediff-lightning' }; tiers=[ordered]@{ video=[ordered]@{ lightning='video.animatediff-lightning' } };
        models=@([ordered]@{ model_id='video.animatediff-lightning'; type='video-gen'; wired=$false; name='bad'; family='animatediff'; format='x'; base=$fakeBase; adapter=(Join-Path $tmpRoot 'no-such-adapter.safetensors'); path=$fakeBase; engine='diffusers'; engine_env=$usePython; params=[ordered]@{ dtype='float16' } }) }
    [System.IO.File]::WriteAllText($badAd, ($ra | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badAd }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'adapter_missing') 'err.adapter_missing' "code=$($e.error.code)"

    # unsupported engine
    $badEng = Join-Path $tmpRoot 'models-badeng.json'
    $reb = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ video='video.animatediff-lightning' }; tiers=[ordered]@{ video=[ordered]@{ lightning='video.animatediff-lightning' } };
        models=@([ordered]@{ model_id='video.animatediff-lightning'; type='video-gen'; wired=$false; name='bad'; family='animatediff'; format='x'; base=$fakeBase; adapter=$fakeAdapter; path=$fakeBase; engine='modelscope'; engine_env=$usePython; params=[ordered]@{} }) }
    [System.IO.File]::WriteAllText($badEng, ($reb | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badEng }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'unsupported_engine') 'err.unsupported_engine' "code=$($e.error.code)"

    # tier resolves
    $e = Invoke-Gen @{ Prompt='tier test'; Tier='lightning' }
    Assert ($e.status -eq 'ok' -and $e.result.model.id -eq 'video.animatediff-lightning') 'tier.resolves' "model=$($e.result.model.id)"

    # gif format path (mock writes a GIF89a stub)
    $e = Invoke-Gen @{ Prompt='a looping gif of clouds'; Format='gif' }
    Assert ($e.status -eq 'ok' -and [string]$e.result.video.format -eq 'gif') 'format.gif' "fmt=$($e.result.video.format)"
}

# ---- 10. Module 1 wrapper integration ----
try {
    $ijObj = [ordered]@{ prompt='wrapper integration clip'; registry=$Registry; python_path=$usePython; video_infer_path=$inferPath; review_queue_path=$rqPath }
    $ij = ($ijObj | ConvertTo-Json -Compress)
    $rw = Run-Proc $pwshExe @('-NoProfile','-File',$invokeSkill,'-SkillDir',$SkillDir,'-InputsJson',$ij,'-PwshPath',$pwshExe)
    $rep = $null; try { $rep = $rw.stdout | ConvertFrom-Json } catch { }
    Assert ($null -ne $rep -and $rep.manifest_valid -eq $true) 'wrapper.manifest_valid' "mv=$($rep.manifest_valid)"
    Assert ($rep.envelope_valid -eq $true) 'wrapper.envelope_valid' ("errs: " + (($rep.envelope_errors) -join '; '))
    Assert ($rep.envelope.skill_id -eq 'gen.video') 'wrapper.skill_id' "id=$($rep.envelope.skill_id)"
} catch { Bad 'wrapper.integration' $_.Exception.Message }

# ---- live-only extras ----
if ($Live) {
    $r1 = Invoke-Gen @{ Prompt='a cinematic drone shot over a misty pine forest at sunrise'; Seed='2024' }
    $r2 = Invoke-Gen @{ Prompt='a cinematic drone shot over a misty pine forest at sunrise'; Seed='2024' }
    if ($r1 -and $r2 -and $r1.status -eq 'ok' -and $r2.status -eq 'ok') {
        $same = ([string]$r1.result.video.sha256 -eq [string]$r2.result.video.sha256)
        Assert $same 'live.same_seed_reproducible' "sha1=$($r1.result.video.sha256) sha2=$($r2.result.video.sha256)"
        Assert ([double]$r1.result.motion.pixel_std -gt 15) 'live.nonblank' "std=$($r1.result.motion.pixel_std)"
        Assert ([double]$r1.result.motion.mean_abs_interframe_diff -gt 1.5) 'live.has_motion' "motion=$($r1.result.motion.mean_abs_interframe_diff)"
        Assert ($r1.result.review.flagged -eq $false) 'live.good_not_flagged' "flagged=$($r1.result.review.flagged)"
        # MP4 magic: ....ftyp
        $mb = [System.IO.File]::ReadAllBytes([string]$r1.result.video.path)
        Assert ($mb.Length -ge 12 -and $mb[4] -eq 0x66 -and $mb[5] -eq 0x74 -and $mb[6] -eq 0x79 -and $mb[7] -eq 0x70) 'live.mp4_magic' ("bytes4-7: $($mb[4]),$($mb[5]),$($mb[6]),$($mb[7])")
        Assert ([double]$r1.result.generation.vram_peak_gb -gt 0 -and [double]$r1.result.generation.vram_peak_gb -lt 11) 'live.vram_fits' "vram=$($r1.result.generation.vram_peak_gb)"
    } else { Bad 'live.same_seed_ran' "r1=$($r1.status) r2=$($r2.status)" }
    # GIF path
    $eg = Invoke-Gen @{ Prompt='a looping clip of gentle ocean waves'; Format='gif'; NumFrames='16' }
    if ($eg -and $eg.status -eq 'ok') {
        Assert ([string]$eg.result.video.format -eq 'gif') 'live.gif_format' "fmt=$($eg.result.video.format)"
        $gb = [System.IO.File]::ReadAllBytes([string]$eg.result.video.path)
        Assert ($gb.Length -ge 6 -and $gb[0] -eq 0x47 -and $gb[1] -eq 0x49 -and $gb[2] -eq 0x46 -and $gb[3] -eq 0x38) 'live.gif_magic' ("bytes: $($gb[0]),$($gb[1]),$($gb[2]),$($gb[3])")
    } else { Bad 'live.gif' "status=$($eg.status)" }
}

Write-Host ('')
Write-Host ("RESULT gen.video tests: PASS=$pass FAIL=$fail")
if ($fail -gt 0) { foreach ($m in $failMsgs) { Write-Host ("  - $m") } }
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($fail -gt 0) { exit 1 } else { exit 0 }
