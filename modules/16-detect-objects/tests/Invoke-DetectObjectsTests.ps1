#requires -Version 7.0
<#
  Invoke-DetectObjectsTests.ps1 -- tests for detect.objects (Module 16).

  Real-worker & OS-portable (mirrors image.util's real-worker gate, NOT a mock): because onnxruntime CPU
  inference on a fixed ONNX model + fixed image is deterministic across versions/OSes (verified in
  m16-probe-001: identical dog/car/bicycle scores on cloud onnxruntime 1.25 and Windows onnxruntime 1.17.1),
  the harness runs the REAL Invoke-DetectObjects.ps1 -> the REAL detect_worker.py under a resolved python
  against the committed fixture (tests/fixtures/dog.jpg). The same harness is the cloud pre-ship gate
  (cloud python + onnxruntime, model via -ModelPath) and the live Windows/executor test (system python,
  model resolved from the registry on F:).

  -PythonPath <python>  : interpreter to use (must import onnxruntime + PIL + numpy). Auto-resolved if omitted.
  -ModelPath <onnx>     : detector .onnx to use. If omitted, the wrapper resolves detect.yolox.nano from the
                          registry (F: on Windows). Pass it explicitly on the cloud box.
  -PwshPath <pwsh>      : pwsh used to launch the skill + its child skills (image.util/capture.screen).
  Capture composition is Windows-only (System.Drawing) and is exercised only when running on Windows.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath,
    [string]$ModelPath,
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
function Test-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c 'import onnxruntime, PIL, numpy' 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}

$entry = Join-Path $SkillDir 'Invoke-DetectObjects.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m16-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$queue = Join-Path $tmpRoot 'review_queue.jsonl'
$fixture = Join-Path $SkillDir 'tests\fixtures\dog.jpg'

Write-Host "=== detect.objects tests ==="
Write-Host "skill=$entry"

if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    foreach ($c in @('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe',
                     'F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe',
                     'python3','python','py')) {
        $cc = $c
        if ($c -notmatch '[\\/]') { try { $w = & where.exe $c 2>$null; if ($w) { $cc = (@([string[]]$w))[0].Trim() } } catch { } }
        if (Test-Python $cc) { $PythonPath = $cc; break }
    }
}
if ([string]::IsNullOrWhiteSpace($PythonPath) -or -not (Test-Python $PythonPath)) {
    Write-Host "  [FAIL] no python with onnxruntime+PIL+numpy found (set -PythonPath)"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}
Write-Host "python=$PythonPath"
Write-Host "model=$(if ($ModelPath) { $ModelPath } else { '(registry detect.yolox.nano)' })"
if (-not (Test-Path -LiteralPath $fixture)) { Write-Host "  [FAIL] fixture missing: $fixture"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1 }

function Run-Det([hashtable]$inp) {
    if (-not $inp.ContainsKey('python_path')) { $inp['python_path'] = $PythonPath }
    if (-not $inp.ContainsKey('pwsh_path'))   { $inp['pwsh_path'] = $PwshPath }
    if (-not $inp.ContainsKey('review_queue_path')) { $inp['review_queue_path'] = $queue }
    if ($ModelPath -and -not $inp.ContainsKey('model_path')) { $inp['model_path'] = $ModelPath }
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
Check 'manifest parallel_safe=true' ($man.parallel_safe -eq $true)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=detect.objects' ($man.skill_id -eq 'detect.objects')

# ---------- 2) basic detection ----------
$r = Run-Det @{ input = $fixture }
Check 'detect: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'detect: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'detect: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'detect: confidence in (0,1]' ($null -ne $e -and $null -ne $e.confidence -and [double]$e.confidence -gt 0 -and [double]$e.confidence -le 1) "conf=$($e.confidence)"
$rr = $null; if ($null -ne $e) { $rr = $e.result }
Check 'detect: >=3 detections' ($null -ne $rr -and [int]$rr.detection_count -ge 3) "n=$($rr.detection_count)"
$classes = @(); if ($null -ne $rr) { $classes = @($rr.detections | ForEach-Object { [string]$_.class }) }
Check 'detect: found a dog' ($classes -contains 'dog') "classes=$($classes -join ',')"
Check 'detect: model engine=onnxruntime' ($null -ne $rr -and $rr.model.engine -eq 'onnxruntime')
Check 'detect: provenance model_id present' ($null -ne $e -and @($e.model_provenance).Count -eq 1 -and [string]$e.model_provenance[0].model_id -match 'yolox')
# boxes valid + integer + within bounds; scores in (0,1]
$W = [int]$rr.image.width; $H = [int]$rr.image.height
$allBoxesOk = $true; $allScoresOk = $true
foreach ($d in @($rr.detections)) {
    $b = $d.box
    if (-not ([int]$b.x -ge 0 -and [int]$b.y -ge 0 -and ([int]$b.x + [int]$b.width) -le $W -and ([int]$b.y + [int]$b.height) -le $H -and [int]$b.width -gt 0 -and [int]$b.height -gt 0)) { $allBoxesOk = $false }
    if (-not ([double]$d.score -gt 0 -and [double]$d.score -le 1)) { $allScoresOk = $false }
}
Check 'detect: all boxes integer + within image bounds' $allBoxesOk "img=${W}x${H}"
Check 'detect: all scores in (0,1]' $allScoresOk
Check 'detect: overall == max detection score' ($null -ne $rr -and [double]$rr.confidence.overall -eq ([double](@($rr.detections | ForEach-Object { [double]$_.score }) | Measure-Object -Maximum).Maximum))
$arts = @($e.artifacts); $paths = @($arts | ForEach-Object { [string]$_.path })
$hasDj = @($paths | Where-Object { $_ -match 'detect\.json$' }).Count -eq 1
$hasDm = @($paths | Where-Object { $_ -match 'detect\.md$' }).Count -eq 1
Check 'detect: artifacts include detect.json + detect.md' ($hasDj -and $hasDm) "paths=$($paths -join ',')"
$djArt = @($arts | Where-Object { [string]$_.path -match 'detect\.json$' })[0]
Check 'detect: detect.json artifact sha256 matches file' ($null -ne $djArt -and (Get-Sha256HexFile ([string]$djArt.path)) -eq [string]$djArt.sha256)

# ---------- 3) class filter ----------
$r = Run-Det @{ input = $fixture; classes = @('dog') }
$rr = $r.env.result
$fc = @(); if ($null -ne $rr) { $fc = @($rr.detections | ForEach-Object { [string]$_.class }) }
Check 'class filter(dog): >=1 and all are dog' ($fc.Count -ge 1 -and (@($fc | Where-Object { $_ -ne 'dog' }).Count -eq 0)) "classes=$($fc -join ',')"

# ---------- 4) score threshold raises the floor ----------
$rLow = Run-Det @{ input = $fixture; score_threshold = 0.05 }
$rHigh = Run-Det @{ input = $fixture; score_threshold = 0.8 }
Check 'score_threshold: high floor yields fewer detections than low' ([int]$rHigh.env.result.detection_count -le [int]$rLow.env.result.detection_count) "high=$($rHigh.env.result.detection_count) low=$($rLow.env.result.detection_count)"

# ---------- 5) low-confidence review producer ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Det @{ input = $fixture; confidence_threshold = 0.999 }
$rr = $r.env.result
Check 'review(low-conf): flagged_count == 1' ($null -ne $rr -and [int]$rr.review.flagged_count -eq 1) "flagged=$($rr.review.flagged_count)"
$qok = $false; $qverb = ''
if (Test-Path -LiteralPath $queue) {
    $lines = @(Get-Content -LiteralPath $queue | Where-Object { $_.Trim() })
    $last = $lines[-1] | ConvertFrom-Json
    $qok = ($last.schema -eq 'lifeorch.review.item/0.1' -and $last.flagged_by -eq 'detect.objects' -and $last.reason -eq 'low_confidence')
    $qverb = [string]$last.requested
}
Check 'review(low-conf): valid detect.objects item, requested=verify_detections' ($qok -and $qverb -eq 'verify_detections') "verb=$qverb"

# ---------- 6) no-objects review producer ----------
if (Test-Path -LiteralPath $queue) { Remove-Item -LiteralPath $queue -Force }
$r = Run-Det @{ input = $fixture; score_threshold = 0.999 }
$rr = $r.env.result
Check 'no-objects: detection_count == 0' ($null -ne $rr -and [int]$rr.detection_count -eq 0)
$qok = $false; $qverb = ''
if (Test-Path -LiteralPath $queue) {
    $lines = @(Get-Content -LiteralPath $queue | Where-Object { $_.Trim() })
    $last = $lines[-1] | ConvertFrom-Json
    $qok = ($last.flagged_by -eq 'detect.objects' -and $last.reason -eq 'uncategorized')
    $qverb = [string]$last.requested
}
Check 'no-objects: verify_no_objects review item' ($qok -and $qverb -eq 'verify_no_objects') "verb=$qverb"

# ---------- 7) image.util downscale composition (-MaxDimension) ----------
$r = Run-Det @{ input = $fixture; max_dimension = 320 }
$rr = $r.env.result
Check 'maxdim: exit 0 + status ok/partial' ($r.exit -eq 0 -and $null -ne $rr -and @('ok','partial') -contains $r.env.status) "err=$($r.err)"
Check 'maxdim: preprocess.downscaled == true' ($null -ne $rr -and [bool]$rr.preprocess.downscaled)
Check 'maxdim: boxes reported in ORIGINAL space (image 768x576)' ($null -ne $rr -and [int]$rr.image.width -eq 768 -and [int]$rr.image.height -eq 576) "img=$($rr.image.width)x$($rr.image.height)"
$mdClasses = @(); if ($null -ne $rr) { $mdClasses = @($rr.detections | ForEach-Object { [string]$_.class }) }
Check 'maxdim: still detects a dog after downscale' ($mdClasses -contains 'dog') "classes=$($mdClasses -join ',')"

# ---------- 8) error paths ----------
$r = Run-Det @{ input = (Join-Path $tmpRoot 'nope.png') }
Check 'error: input_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'input_not_found')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-Det @{ input = $fixture; model_path = (Join-Path $tmpRoot 'nomodel.onnx') }
Check 'error: model_file_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'model_file_not_found')
$r = Run-Det @{ input = $fixture; registry = (Join-Path $tmpRoot 'noreg.json') }
Check 'error: registry_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'registry_not_found')
$r = Run-Det @{ input = $fixture; model = 'detect.does.not.exist' }
Check 'error: model_not_found (bad -Model)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'model_not_found')

# ---------- 9) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $fixture; python_path = $PythonPath; pwsh_path = $PwshPath; review_queue_path = $queue }
if ($ModelPath) { $wrapInp.model_path = $ModelPath }
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

# ---------- 10) capture.screen composition (Windows-only) ----------
if ($IsWindows) {
    $r = Run-Det @{ capture = $true; capture_inputs = @{ target = 'monitor'; monitor = 'primary'; format = 'png' } }
    Check 'capture: exit 0 + status ok/partial' ($r.exit -eq 0 -and $null -ne $r.env -and @('ok','partial') -contains $r.env.status) "err=$($r.err)"
    Check 'capture: result.input.source == capture' ($null -ne $r.env -and $null -ne $r.env.result -and [string]$r.env.result.input.source -eq 'capture')
    Check 'capture: detection_count is a number (>=0)' ($null -ne $r.env -and [int]$r.env.result.detection_count -ge 0)
    # no orphaned python
    $orphans = @(Get-Process -Name 'python','python3' -ErrorAction SilentlyContinue)
    Check 'capture: (info) python processes after run' ($true) "count=$($orphans.Count)"
} else {
    Write-Host "  [skip] capture.screen composition (Windows-only)"
}

try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
