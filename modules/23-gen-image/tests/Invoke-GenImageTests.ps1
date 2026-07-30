#requires -Version 7.0
<#
  Tests for gen.image (Module 23).
  Default: MOCK mode -- runs the REAL Invoke-GenImage.ps1 against tests/mock-worker.py (stdlib, no torch/
  diffusers/PIL), so the full parse/confidence/review/envelope path runs on the cloud Linux box before any
  bytes ship. -Live: runs the REAL diffusers worker + real registry on the Windows executor (a real SD
  generation). Runs the skill as a child process (async-drained) so the skill's `exit 0` never ends this
  harness and native stderr never trips StrictMode.
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

$wrapper = Join-Path $SkillDir 'Invoke-GenImage.ps1'
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

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("genimg-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'art'
$rqPath = Join-Path $tmpRoot 'review_queue.jsonl'

# ---- resolve python + worker + registry per mode ----
if ($Live) {
    if ([string]::IsNullOrWhiteSpace($Registry)) { $Registry = (Resolve-Path (Join-Path $SkillDir '..\07-model-gateway\models.json')).Path }
    $inferPath = Join-Path $SkillDir 'gen_image_infer.py'
    $usePython = $PythonPath   # empty -> wrapper resolves from registry engine_env
    Write-Host ("=== gen.image tests (LIVE) registry=$Registry ===")
} else {
    # Resolve a WORKING stdlib python for the mock worker. Prefer an explicit -PythonPath; else probe
    # python3 then python and pick the first that actually runs -- on Windows `python3` often resolves to
    # the Microsoft Store App-Execution-Alias stub (WindowsApps\python3.exe) which prints "Python was not
    # found" and exits non-zero, so a plain Get-Command would pick a non-functional interpreter.
    $usePython = $PythonPath
    if ([string]::IsNullOrWhiteSpace($usePython)) {
        $cands = New-Object System.Collections.Generic.List[string]
        foreach ($n in @('python3','python')) { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { $cands.Add($c.Source) } }
        foreach ($cand in $cands) {
            try {
                $global:LASTEXITCODE = 0
                $probe = (& $cand -c 'print(1)' 2>&1 | Out-String).Trim()
                if ($LASTEXITCODE -eq 0 -and $probe -eq '1') { $usePython = $cand; break }
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($usePython)) { throw 'no working python3/python on PATH for the mock gate (Store stub excluded)' }
    }
    $inferPath = $mockWorker
    $fakeModel = Join-Path $tmpRoot 'model\stable-diffusion-v1-5'
    New-Item -ItemType Directory -Path $fakeModel -Force | Out-Null
    $fakeModel35 = Join-Path $tmpRoot 'model\stable-diffusion-3.5-medium'
    New-Item -ItemType Directory -Path $fakeModel35 -Force | Out-Null
    $Registry = Join-Path $tmpRoot 'models.json'
    $regObj = [ordered]@{
        schema='lifeorch.model_registry/0.1'
        defaults=[ordered]@{ image='image.sd15' }
        tiers=[ordered]@{ image=[ordered]@{ sd15='image.sd15'; sd35='image.sd35-medium' } }
        models=@(
            [ordered]@{ model_id='image.sd15'; type='image-gen'; wired=$false; name='SD1.5 (mock)'; family='stable-diffusion'; format='diffusers'; version='sd15-mock'; path=$fakeModel; engine='diffusers'; engine_env=$usePython; license='CreativeML-OpenRAIL-M'; params=[ordered]@{ variant='fp16' } },
            [ordered]@{ model_id='image.sd35-medium'; type='image-gen'; wired=$false; name='SD3.5 Medium (mock)'; family='stable-diffusion-3'; format='diffusers'; version='sd35-mock'; path=$fakeModel35; engine='diffusers'; engine_env=$usePython; license='STABILITY-AI-COMMUNITY'; params=[ordered]@{ pipeline='sd3'; offload='model'; vae_tiling=$true; drop_t5=$false } }
        )
    }
    [System.IO.File]::WriteAllText($Registry, ($regObj | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    Write-Host ("=== gen.image tests (MOCK) python=$usePython ===")
}

# ---- invoke helper: run the real wrapper as a child, return parsed envelope ----
# $over can set Registry/PythonPath/GenInferPath to override the defaults (for error-path cases).
function Invoke-Gen([hashtable]$named, [string]$inputsJson='', [hashtable]$over=@{}) {
    $reg = if ($over.ContainsKey('Registry')) { $over['Registry'] } else { $Registry }
    $pyp = if ($over.ContainsKey('PythonPath')) { $over['PythonPath'] } else { $usePython }
    $inf = if ($over.ContainsKey('GenInferPath')) { $over['GenInferPath'] } else { $inferPath }
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-NoProfile'); $a.Add('-File'); $a.Add($wrapper)
    foreach ($k in $named.Keys) { $a.Add('-' + $k); $a.Add([string]$named[$k]) }
    if ($inputsJson) { $a.Add('-InputsJson'); $a.Add($inputsJson) }
    $a.Add('-Registry'); $a.Add($reg)
    if (-not [string]::IsNullOrWhiteSpace($pyp)) { $a.Add('-PythonPath'); $a.Add($pyp) }
    $a.Add('-GenInferPath'); $a.Add($inf)
    $a.Add('-ReviewQueuePath'); $a.Add($rqPath)
    $a.Add('-ArtifactRoot'); $a.Add($artRoot)
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
$e = Invoke-Gen @{ Prompt='a red apple on a wooden table, studio photo'; Seed='42' }
Assert ($null -ne $e -and $e.status -eq 'ok') 'happy.status_ok' "status=$($e.status)"
Assert ($e.skill_id -eq 'gen.image') 'happy.skill_id' "skill_id=$($e.skill_id)"
Assert ($e.contract_version -eq '0.2') 'happy.contract_version' "cv=$($e.contract_version)"
if ($e -and $e.status -eq 'ok' -and $e.result) {
    $imgPath = [string]$e.result.image.path
    Assert (Test-Path -LiteralPath $imgPath -PathType Leaf) 'happy.image_exists' "path=$imgPath"
    $fh = (Get-FileHash -LiteralPath $imgPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ($fh -eq [string]$e.result.image.sha256) 'happy.sha_matches_file' "$fh vs $($e.result.image.sha256)"
    Assert ([int]$e.result.image.width -ge 1 -and [int]$e.result.image.height -ge 1) 'happy.dims' "$($e.result.image.width)x$($e.result.image.height)"
    Assert ($null -ne $e.confidence -and [double]$e.confidence -ge 0.9) 'happy.confidence_high' "conf=$($e.confidence)"
    Assert (@($e.model_provenance).Count -eq 1) 'happy.provenance_one' "count=$(@($e.model_provenance).Count)"
    Assert ([string]$e.model_provenance[0].engine -eq 'diffusers') 'happy.provenance_engine' "engine=$($e.model_provenance[0].engine)"
} else { Bad 'happy.result' 'no ok result' }

# ---- 3. InputsJson parity ----
$e = Invoke-Gen @{} '{"prompt":"a blue mug on a desk","seed":7}'
Assert ($null -ne $e -and $e.status -eq 'ok' -and $e.result.input.prompt -eq 'a blue mug on a desk') 'inputsjson.parity' "status=$($e.status)"

# ---- 4. named overrides InputsJson ----
$e = Invoke-Gen @{ Prompt='named wins' } '{"prompt":"json loses"}'
Assert ($null -ne $e -and $e.result.input.prompt -eq 'named wins') 'inputsjson.named_wins' "prompt=$($e.result.input.prompt)"

# ---- 5. params echo ----
$e = Invoke-Gen @{ Prompt='echo params'; Width='512'; Height='512'; Steps='12'; Guidance='8'; Seed='123'; Scheduler='euler' }
if ($e -and $e.status -eq 'ok') {
    Assert ([int]$e.result.request.steps -eq 12) 'echo.steps' "steps=$($e.result.request.steps)"
    Assert ([double]$e.result.request.guidance -eq 8.0) 'echo.guidance' "g=$($e.result.request.guidance)"
    Assert ([int]$e.result.request.seed -eq 123) 'echo.seed' "seed=$($e.result.request.seed)"
    Assert ([string]$e.result.request.scheduler -eq 'euler') 'echo.scheduler' "sch=$($e.result.request.scheduler)"
} else { Bad 'echo.params' "status=$($e.status)" }

# ---- 6. seed -1 records a concrete seed ----
$e = Invoke-Gen @{ Prompt='random seed test'; Seed='-1' }
Assert ($null -ne $e -and $e.status -eq 'ok' -and [int]$e.result.request.seed -ge 0) 'seed.random_recorded' "seed=$($e.result.request.seed)"

# ---- 7. format ----
$e = Invoke-Gen @{ Prompt='format test'; Format='jpg' }
Assert ($null -ne $e -and $e.status -eq 'ok' -and [string]$e.result.image.format -eq 'jpg' -and ([string]$e.result.image.path).ToLower().EndsWith('.jpg')) 'format.jpg' "fmt=$($e.result.image.format) path=$($e.result.image.path)"

# ---- 8. error paths (wrapper-level validation; mode-agnostic) ----
$e = Invoke-Gen @{ Prompt='' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'no_prompt') 'err.no_prompt' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Format='gif' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_format') 'err.invalid_format' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Scheduler='nope' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_scheduler') 'err.invalid_scheduler' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Width='513' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_dimensions') 'err.dims_mult8' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Height='2048' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_dimensions') 'err.dims_range' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Steps='0' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_steps') 'err.steps' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Guidance='99' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'invalid_guidance') 'err.guidance' "code=$($e.error.code)"
$e = Invoke-Gen @{ Prompt='x'; Model='image.does-not-exist' }
Assert ($e.status -eq 'error' -and $e.error.code -eq 'model_not_found') 'err.model_not_found' "code=$($e.error.code)"

# ---- 9. python_not_found (bad -PythonPath wins) ----
$e = Invoke-Gen @{ Prompt='x' } '' @{ PythonPath='/definitely/not/a/python-xyz' }
Assert ($null -ne $e -and $e.status -eq 'error' -and $e.error.code -eq 'python_not_found') 'err.python_not_found' "code=$($e.error.code)"

# ---- 10. mock-only: confidence + review branches + generation_failed + model_dir_missing + tier ----
if (-not $Live) {
    $before = RqCount
    $e = Invoke-Gen @{ Prompt='__BLANK__ empty field' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -le 0.15) 'review.blank_conf' "conf=$($e.confidence) status=$($e.status)"
    Assert ($e.result.review.flagged -eq $true) 'review.blank_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before + 1) 'review.blank_queued' "$before -> $(RqCount)"
    if ((RqCount) -gt 0) {
        $last = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json
        Assert ($last.flagged_by -eq 'gen.image' -and $last.requested -eq 'verify_generation' -and $last.reason -eq 'failed_transform') 'review.item_shape' "by=$($last.flagged_by) req=$($last.requested) reason=$($last.reason)"
    }
    $before2 = RqCount
    $e = Invoke-Gen @{ Prompt='__LOWDETAIL__ faint' }
    Assert ($e.status -eq 'partial' -and [double]$e.confidence -eq 0.3) 'review.lowdetail_conf' "conf=$($e.confidence)"
    Assert ((RqCount) -eq $before2 + 1) 'review.lowdetail_queued' "queued"
    if ((RqCount) -gt 0) { $l2 = @(Get-Content -LiteralPath $rqPath)[-1] | ConvertFrom-Json; Assert ($l2.reason -eq 'low_confidence') 'review.lowdetail_reason' "reason=$($l2.reason)" }

    $before3 = RqCount
    $e = Invoke-Gen @{ Prompt='a normal good image' }
    Assert ($e.status -eq 'ok' -and $e.result.review.flagged -eq $false) 'review.good_not_flagged' "flagged=$($e.result.review.flagged)"
    Assert ((RqCount) -eq $before3) 'review.good_no_queue' "no new item"

    $e = Invoke-Gen @{ Prompt='__FAIL__ boom' }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'generation_failed') 'err.generation_failed' "code=$($e.error.code)"

    $badReg = Join-Path $tmpRoot 'models-badpath.json'
    $rb = [ordered]@{ schema='lifeorch.model_registry/0.1'; defaults=[ordered]@{ image='image.sd15' }; tiers=[ordered]@{ image=[ordered]@{ sd15='image.sd15' } };
        models=@([ordered]@{ model_id='image.sd15'; type='image-gen'; wired=$false; name='bad'; family='stable-diffusion'; format='diffusers'; path=(Join-Path $tmpRoot 'no-such-model-dir'); engine='diffusers'; engine_env=$usePython; params=[ordered]@{ variant='fp16' } }) }
    [System.IO.File]::WriteAllText($badReg, ($rb | ConvertTo-Json -Depth 8), ([System.Text.UTF8Encoding]::new($false)))
    $e = Invoke-Gen @{ Prompt='x' } '' @{ Registry=$badReg }
    Assert ($e.status -eq 'error' -and $e.error.code -eq 'model_dir_missing') 'err.model_dir_missing' "code=$($e.error.code)"

    $e = Invoke-Gen @{ Prompt='tier test'; Tier='sd15' }
    Assert ($e.status -eq 'ok' -and $e.result.model.id -eq 'image.sd15') 'tier.resolves' "model=$($e.result.model.id)"

    # ---- sd3 tier (SD 3.5 Medium): model selection, pipeline-family + offload passthrough (mock) ----
    $e = Invoke-Gen @{ Prompt='a coastal town at golden hour'; Model='image.sd35-medium'; Steps='28'; Guidance='4.5'; Width='768'; Height='768' }
    Assert ($e.status -eq 'ok' -and $e.result.model.id -eq 'image.sd35-medium') 'sd3.model_selected' "model=$($e.result.model.id) status=$($e.status)"
    if ($e -and $e.status -eq 'ok') {
        Assert ($e.result.model.family -eq 'stable-diffusion-3') 'sd3.family' "family=$($e.result.model.family)"
        Assert ($e.result.generation.pipeline_family -eq 'sd3') 'sd3.gen_family' "pf=$($e.result.generation.pipeline_family)"
        Assert (-not [string]::IsNullOrWhiteSpace([string]$e.result.generation.offload)) 'sd3.gen_offload' "offload=$($e.result.generation.offload)"
        Assert ($e.result.generation.actual_scheduler -eq 'flow_match_euler') 'sd3.gen_sched' "sched=$($e.result.generation.actual_scheduler)"
        Assert ($e.result.generation.t5 -eq 'cpu_offload') 'sd3.gen_t5' "t5=$($e.result.generation.t5)"
        $adir = [string]$e.diagnostics.artifact_dir
        $ga = Join-Path $adir 'gen_args.json'
        if (Test-Path -LiteralPath $ga) {
            $gargs = (Get-Content -LiteralPath $ga -Raw) | ConvertFrom-Json
            Assert ($gargs.pipeline_family -eq 'sd3' -and $gargs.offload -eq 'model' -and $gargs.vae_tiling -eq $true) 'sd3.args_passthrough' "pf=$($gargs.pipeline_family) off=$($gargs.offload) vt=$($gargs.vae_tiling)"
        } else { Bad 'sd3.args_passthrough' "no gen_args.json at $ga" }
    }
    $e = Invoke-Gen @{ Prompt='sd3 via tier alias'; Tier='sd35' }
    Assert ($e.status -eq 'ok' -and $e.result.model.id -eq 'image.sd35-medium') 'sd3.tier_resolves' "model=$($e.result.model.id)"
}

# ---- 11. Module 1 wrapper integration ----
try {
    $ijObj = [ordered]@{ prompt='wrapper integration test'; registry=$Registry; python_path=$usePython; gen_infer_path=$inferPath; review_queue_path=$rqPath }
    $ij = ($ijObj | ConvertTo-Json -Compress)
    $rw = Run-Proc $pwshExe @('-NoProfile','-File',$invokeSkill,'-SkillDir',$SkillDir,'-InputsJson',$ij,'-PwshPath',$pwshExe)
    $rep = $null; try { $rep = $rw.stdout | ConvertFrom-Json } catch { }
    Assert ($null -ne $rep -and $rep.manifest_valid -eq $true) 'wrapper.manifest_valid' "mv=$($rep.manifest_valid)"
    Assert ($rep.envelope_valid -eq $true) 'wrapper.envelope_valid' ("errs: " + (($rep.envelope_errors) -join '; '))
    Assert ($rep.envelope.skill_id -eq 'gen.image') 'wrapper.skill_id' "id=$($rep.envelope.skill_id)"
} catch { Bad 'wrapper.integration' $_.Exception.Message }

# ---- live-only extras ----
if ($Live) {
    $r1 = Invoke-Gen @{ Prompt='a small green cactus in a clay pot'; Seed='2024'; Steps='15' }
    $r2 = Invoke-Gen @{ Prompt='a small green cactus in a clay pot'; Seed='2024'; Steps='15' }
    if ($r1 -and $r2 -and $r1.status -eq 'ok' -and $r2.status -eq 'ok') {
        $same = ([string]$r1.result.image.sha256 -eq [string]$r2.result.image.sha256)
        Write-Host ("  INFO  live.same_seed_reproducible=$same (std1=$($r1.result.image.pixel_std) std2=$($r2.result.image.pixel_std))")
        Ok 'live.same_seed_ran'
    } else { Bad 'live.same_seed_ran' "r1=$($r1.status) r2=$($r2.status)" }
    $ej = Invoke-Gen @{ Prompt='a lighthouse at dusk'; Format='jpg'; Steps='15' }
    if ($ej -and $ej.status -eq 'ok') {
        $b = [System.IO.File]::ReadAllBytes([string]$ej.result.image.path)
        Assert ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) 'live.jpg_magic' ("bytes: $($b[0]),$($b[1])")
    } else { Bad 'live.jpg' "status=$($ej.status)" }

    # ---- SD 3.5 Medium quality tier (live): fp16 + CPU offload + VAE tiling; VRAM captured; reproducible ----
    $s1 = Invoke-Gen @{ Prompt='a small green cactus in a clay pot, studio photo'; Model='image.sd35-medium'; Seed='2024'; Steps='28'; Guidance='4.5'; Width='768'; Height='768' }
    if ($s1 -and $s1.status -eq 'ok') {
        Ok 'live.sd3_generated'
        Assert ([string]$s1.result.model.id -eq 'image.sd35-medium' -and [string]$s1.result.generation.pipeline_family -eq 'sd3') 'live.sd3_family' "id=$($s1.result.model.id) pf=$($s1.result.generation.pipeline_family)"
        Assert ([double]$s1.result.image.pixel_std -gt 10.0) 'live.sd3_nonblank' "std=$($s1.result.image.pixel_std)"
        Write-Host ("  INFO  sd3 vram_peak_gb=$($s1.result.generation.vram_peak_gb) load_ms=$($s1.result.generation.load_ms) gen_ms=$($s1.result.generation.gen_ms) offload=$($s1.result.generation.offload) t5=$($s1.result.generation.t5)")
        $s2 = Invoke-Gen @{ Prompt='a small green cactus in a clay pot, studio photo'; Model='image.sd35-medium'; Seed='2024'; Steps='28'; Guidance='4.5'; Width='768'; Height='768' }
        if ($s2 -and $s2.status -eq 'ok') {
            $same = ([string]$s1.result.image.sha256 -eq [string]$s2.result.image.sha256)
            Write-Host ("  INFO  sd3.same_seed_reproducible=$same (sha1=$($s1.result.image.sha256.Substring(0,12)) sha2=$($s2.result.image.sha256.Substring(0,12)))")
        }
    } else { Bad 'live.sd3_generated' "status=$($s1.status) err=$($s1.error.code)" }
}

Write-Host ('')
Write-Host ("RESULT gen.image tests: PASS=$pass FAIL=$fail")
if ($fail -gt 0) { foreach ($m in $failMsgs) { Write-Host ("  - $m") } }
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($fail -gt 0) { exit 1 } else { exit 0 }
