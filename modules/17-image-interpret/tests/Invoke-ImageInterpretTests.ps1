#requires -Version 7.0
<#
  Invoke-ImageInterpretTests.ps1 -- tests for image.interpret (Module 17).

  Dual-mode / OS-portable (mirrors speech.stt/ocr.layout's mock-engine gate, since a VLM's real weights
  cannot run on the Linux cloud box):
    * SEAM MODE (default, and the cloud pre-ship gate): the REAL wrapper runs with -VlmResponsePath pointing
      at a CAPTURED-REAL llama-server chat-completion response (tests/fixtures/*.vlm-response.json, captured
      live in m17-probe-003). This exercises the whole parse/confidence/review/compose/envelope path off-GPU.
      The image.util -MaxDimension composition runs for REAL on the cloud box (Pillow is portable).
    * LIVE MODE (-Live, Windows/executor only): also runs a real llama-server + the staged VLM end-to-end,
      plus the Windows-only capture.screen composition.

  -PythonPath <python> : interpreter for the image.util child (must import PIL+numpy). Required on the cloud
                         box (image.util cannot resolve a python via where.exe on Linux). Auto on Windows.
  -Live                : also run real VLM inference + capture.screen (Windows/executor).
  -PwshPath <pwsh>     : pwsh used to launch the skill + its child skills.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath,
    [switch]$Live,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name $detail" }
}
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256HexFile([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$entry = Join-Path $SkillDir 'Invoke-ImageInterpret.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m17-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$queue = Join-Path $tmpRoot 'review_queue.jsonl'
$fixDir = Join-Path $SkillDir 'tests\fixtures'
$img = Join-Path $fixDir 'dog.jpg'
$fxDescribe  = Join-Path $fixDir 'dog.describe.vlm-response.json'
$fxVqa       = Join-Path $fixDir 'dog.vqa.vlm-response.json'
$fxRefusal   = Join-Path $fixDir 'refusal.vlm-response.json'
$fxEmpty     = Join-Path $fixDir 'empty.vlm-response.json'
$fxTrunc     = Join-Path $fixDir 'truncated.vlm-response.json'

# real F: locations of the staged VLM (used by the temp registry; unchecked in seam mode)
$fEngine = 'F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\_engines\llama.cpp\bin\llama-server.exe'
$fModel  = 'F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\vlm\Qwen2.5-VL-3B-Instruct-GGUF\Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf'
$fMmproj = 'F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\vlm\Qwen2.5-VL-3B-Instruct-GGUF\mmproj-Qwen2.5-VL-3B-Instruct-f16.gguf'
$reg = [ordered]@{
    schema = 'lifeorch.model_registry/0.1'
    engines = [ordered]@{ 'llama-server' = $fEngine }
    defaults = [ordered]@{ vlm = 'vlm.qwen2p5-vl-3b' }
    tiers = [ordered]@{ vlm = [ordered]@{ '3b' = 'vlm.qwen2p5-vl-3b' } }
    engine_build = 'llama.cpp b8661 (b7ad48ebd), CUDA'
    models = @(
        [ordered]@{ model_id='vlm.qwen2p5-vl-3b'; type='vlm'; wired=$false; name='Qwen2.5-VL-3B-Instruct (GGUF)';
            family='qwen2.5-vl'; format='gguf'; quant='Q4_K_M'; path=$fModel; mmproj=$fMmproj; engine='llama-server';
            context=8192; gpu_layers=99; license='Apache-2.0' }
    )
}
$regPath = Join-Path $tmpRoot 'models.json'
[System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 12), $utf8)

Write-Host "=== image.interpret tests ==="
Write-Host "skill=$entry  mode=$(if ($Live) { 'LIVE (+seam)' } else { 'SEAM' })"
if (-not (Test-Path -LiteralPath $img)) { Write-Host "  [FAIL] fixture image missing: $img"; Write-Host "RESULT: 0/1 passed (fail=1)"; Write-Host "ALLPASS=false"; exit 1 }

function Run-Interp([hashtable]$inp) {
    if (-not $inp.ContainsKey('pwsh_path'))         { $inp['pwsh_path'] = $PwshPath }
    if (-not $inp.ContainsKey('review_queue_path')) { $inp['review_queue_path'] = $queue }
    if (-not $inp.ContainsKey('registry'))          { $inp['registry'] = $regPath }
    if ($PythonPath -and -not $inp.ContainsKey('python_path')) { $inp['python_path'] = $PythonPath }
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
function Last-Queue() {
    if (-not (Test-Path -LiteralPath $queue)) { return $null }
    $lines = @(Get-Content -LiteralPath $queue | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) { return $null }
    return ($lines[-1] | ConvertFrom-Json)
}

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=mixed' ($man.determinism -eq 'mixed')
Check 'manifest parallel_safe=false' ($man.parallel_safe -eq $false)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=image.interpret' ($man.skill_id -eq 'image.interpret')

# ---------- 2) seam: describe on dog.jpg ----------
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxDescribe }
Check 'describe: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'describe: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env; $rr = $null; if ($null -ne $e) { $rr = $e.result }
Check 'describe: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'describe: confidence == 0.7 (stop)' ($null -ne $e -and [double]$e.confidence -eq 0.7) "conf=$($e.confidence)"
Check 'describe: text mentions dog' ($null -ne $rr -and ([string]$rr.interpretation.text) -match '(?i)dog') "text=$($rr.interpretation.text)"
Check 'describe: mode=describe, source=file' ($null -ne $rr -and $rr.request.mode -eq 'describe' -and $rr.input.source -eq 'file')
Check 'describe: server.mode=captured_response' ($null -ne $rr -and $rr.server.mode -eq 'captured_response')
Check 'describe: completion_tokens carried through (62)' ($null -ne $rr -and [int]$rr.interpretation.completion_tokens -eq 62)
Check 'describe: provenance engine=llama-server, model_id vlm' ($null -ne $e -and @($e.model_provenance).Count -eq 1 -and [string]$e.model_provenance[0].engine -eq 'llama-server' -and [string]$e.model_provenance[0].model_id -match 'vlm')
$arts = @($e.artifacts); $paths = @($arts | ForEach-Object { [string]$_.path })
$hasIj = @($paths | Where-Object { $_ -match 'interpret\.json$' }).Count -eq 1
$hasIm = @($paths | Where-Object { $_ -match 'interpret\.md$' }).Count -eq 1
Check 'describe: artifacts include interpret.json + interpret.md' ($hasIj -and $hasIm) "paths=$($paths -join ',')"
$ijArt = @($arts | Where-Object { [string]$_.path -match 'interpret\.json$' })[0]
Check 'describe: interpret.json sha256 matches file' ($null -ne $ijArt -and (Get-Sha256HexFile ([string]$ijArt.path)) -eq [string]$ijArt.sha256)
Check 'describe: no review flag (conf 0.7 >= 0.5)' ($null -ne $rr -and [int]$rr.review.flagged_count -eq 0)

# ---------- 3) seam: vqa (prompt selects mode=vqa) ----------
$r = Run-Interp @{ input = $img; prompt = 'How many animals are in this image?'; vlm_response_path = $fxVqa }
$rr = $r.env.result
Check 'vqa: mode auto-resolves to vqa from -Prompt' ($null -ne $rr -and $rr.request.mode -eq 'vqa')
Check 'vqa: prompt used verbatim' ($null -ne $rr -and ([string]$rr.request.prompt) -match 'How many animals')
Check 'vqa: answer mentions animal/1' ($null -ne $rr -and ([string]$rr.interpretation.text) -match '(?i)animal|1')

# ---------- 4) mode defaulting (no prompt, no capture -> describe) ----------
$r = Run-Interp @{ input = $img; vlm_response_path = $fxDescribe }
Check 'default mode = describe' ($null -ne $r.env.result -and $r.env.result.request.mode -eq 'describe')

# ---------- 5) review: truncated -> low_confidence ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxTrunc }
$rr = $r.env.result
Check 'truncated: confidence 0.4' ($null -ne $rr -and [double]$rr.confidence.value -eq 0.4) "conf=$($rr.confidence.value)"
Check 'truncated: flagged_count 1' ($null -ne $rr -and [int]$rr.review.flagged_count -eq 1)
$q = Last-Queue
Check 'truncated: review item low_confidence + verify_interpretation' ($null -ne $q -and $q.flagged_by -eq 'image.interpret' -and $q.reason -eq 'low_confidence' -and $q.requested -eq 'verify_interpretation')

# ---------- 6) review: refusal -> needs_strong_review ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxRefusal }
$rr = $r.env.result
Check 'refusal: confidence 0.3 + reason refusal' ($null -ne $rr -and [double]$rr.confidence.value -eq 0.3 -and $rr.confidence.reason -eq 'refusal') "conf=$($rr.confidence.value) reason=$($rr.confidence.reason)"
$q = Last-Queue
Check 'refusal: review item needs_strong_review' ($null -ne $q -and $q.flagged_by -eq 'image.interpret' -and $q.reason -eq 'needs_strong_review' -and $q.requested -eq 'verify_interpretation')

# ---------- 7) review: empty -> failed_transform ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxEmpty }
$rr = $r.env.result
Check 'empty: confidence 0.1 + reason empty' ($null -ne $rr -and [double]$rr.confidence.value -eq 0.1 -and $rr.confidence.reason -eq 'empty')
$q = Last-Queue
Check 'empty: review item failed_transform' ($null -ne $q -and $q.reason -eq 'failed_transform' -and $q.requested -eq 'verify_interpretation')

# ---------- 8) confidence_threshold gating ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxDescribe; confidence_threshold = 0.99 }
$rr = $r.env.result
Check 'threshold 0.99: describe (0.7) now flagged low_confidence' ($null -ne $rr -and [int]$rr.review.flagged_count -eq 1 -and (Last-Queue).reason -eq 'low_confidence')

# ---------- 9) image.util -MaxDimension downscale composition ----------
$r = Run-Interp @{ input = $img; mode = 'describe'; vlm_response_path = $fxDescribe; max_dimension = 320 }
$rr = $r.env.result
Check 'maxdim: exit 0 + status ok/partial' ($r.exit -eq 0 -and $null -ne $rr -and @('ok','partial') -contains $r.env.status) "err=$($r.err)"
Check 'maxdim: preprocess.downscaled == true' ($null -ne $rr -and [bool]$rr.preprocess.downscaled)
Check 'maxdim: original dims reported (768x576)' ($null -ne $rr -and [int]$rr.preprocess.original.width -eq 768 -and [int]$rr.preprocess.original.height -eq 576) "orig=$($rr.preprocess.original.width)x$($rr.preprocess.original.height)"
Check 'maxdim: still produced an interpretation' ($null -ne $rr -and -not [string]::IsNullOrWhiteSpace([string]$rr.interpretation.text))

# ---------- 10) error paths ----------
$r = Run-Interp @{ input = (Join-Path $tmpRoot 'nope.png'); vlm_response_path = $fxDescribe }
Check 'error: input_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'input_not_found')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-Interp @{ input = $img; registry = (Join-Path $tmpRoot 'noreg.json'); vlm_response_path = $fxDescribe }
Check 'error: registry_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'registry_not_found')
$r = Run-Interp @{ input = $img; model = 'vlm.does.not.exist'; vlm_response_path = $fxDescribe }
Check 'error: model_not_found (bad -Model)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'model_not_found')
$r = Run-Interp @{ input = $img; mode = 'nonsense'; vlm_response_path = $fxDescribe }
Check 'error: invalid_mode' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_mode')
$r = Run-Interp @{ input = $img; mode = 'vqa'; vlm_response_path = $fxDescribe }
Check 'error: no_prompt (mode=vqa without -Prompt)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'no_prompt')

# ---------- 11) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $img; mode = 'describe'; vlm_response_path = $fxDescribe; registry = $regPath; review_queue_path = $queue; pwsh_path = $PwshPath }
if ($PythonPath) { $wrapInp.python_path = $PythonPath }
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

# ---------- 12) LIVE: real VLM inference + capture.screen (Windows/executor only) ----------
if ($Live) {
    Write-Host "  -- LIVE: real llama-server VLM inference --"
    $r = Run-Interp @{ input = $img; mode = 'describe'; load_timeout_sec = 240 }
    $rr = $r.env.result
    Check 'live: exit 0 + status ok/partial' ($r.exit -eq 0 -and $null -ne $rr -and @('ok','partial') -contains $r.env.status) "err=$($r.err)"
    Check 'live: server.mode=live' ($null -ne $rr -and $rr.server.mode -eq 'live')
    Check 'live: non-empty interpretation mentioning the scene' ($null -ne $rr -and ([string]$rr.interpretation.text) -match '(?i)dog|bicycle|porch|van') "text=$($rr.interpretation.text)"
    Check 'live: confidence 0.7 (stop) + provenance device cuda:0' ($null -ne $rr -and [double]$r.env.confidence -eq 0.7 -and [string]$r.env.model_provenance[0].device -eq 'cuda:0')
    $r2 = Run-Interp @{ input = $img; prompt = 'What color is the dog?'; load_timeout_sec = 240 }
    Check 'live: VQA answers about the dog' ($null -ne $r2.env.result -and -not [string]::IsNullOrWhiteSpace([string]$r2.env.result.interpretation.text))
    if ($IsWindows) {
        Write-Host "  -- LIVE: capture.screen composition --"
        $r = Run-Interp @{ capture = $true; capture_inputs = @{ target='monitor'; monitor='primary'; format='png' }; mode = 'screen'; load_timeout_sec = 240 }
        Check 'capture: exit 0 + source=capture' ($r.exit -eq 0 -and $null -ne $r.env.result -and [string]$r.env.result.input.source -eq 'capture') "err=$($r.err)"
        Check 'capture: produced a screen interpretation' ($null -ne $r.env.result -and -not [string]::IsNullOrWhiteSpace([string]$r.env.result.interpretation.text))
    }
    Start-Sleep -Milliseconds 1200
    $orphans = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
    Check 'live: no orphaned llama-server' ($orphans.Count -eq 0) "count=$($orphans.Count)"
}

try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
