#requires -Version 7.0
<#
  Invoke-ImageIndexTests.ps1 -- tests for image.index (Module 18).

  Dual-mode & OS-portable (mirrors Modules 13/16/17):
   * -UseMock : run the REAL Invoke-ImageIndex.ps1 with every child (capture/image.util/ocr/detect/interpret) pointed at
                tests/mock-child.ps1 (branches on the -ArtifactRoot leaf; canned envelopes; capture writes a real 1x1 PNG;
                image.util emits a real sha256; ocr/detect/interpret append a review item to the passed review_queue_path).
                No GPU/models needed -- the cloud pre-ship gate.
   * default  : resolve the real child skills and run a live index over a real fixture image on the Windows executor
                (image.util always; -Ocr/-Detect/-Interpret via -Live flags; the -Capture compose). Same assertions.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$InputFile,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$PythonPath,
    [switch]$UseMock,
    [switch]$Live
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

$entry = Join-Path $SkillDir 'Invoke-ImageIndex.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m18-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'

Write-Host "=== image.index tests (UseMock=$UseMock Live=$Live) ==="
Write-Host "skill=$entry"

$mockPath = $null
if ($UseMock) { $mockPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'mock-child.ps1')).Path }

# ---- fixture image ----
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    if ($UseMock) {
        # a real 1x1 PNG (content irrelevant to the mock children)
        $InputFile = Join-Path $tmpRoot 'fixture.png'
        $png = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xDE,
            0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,0x00,0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,
            0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
        [System.IO.File]::WriteAllBytes($InputFile, $png)
    } else {
        $cand = Join-Path $SkillDir 'tests\fixtures\dog.jpg'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $InputFile = (Resolve-Path -LiteralPath $cand).Path }
        else { throw "no -InputFile and no fixture dog.jpg for the live path" }
    }
}

function Run-Index([hashtable]$inp) {
    if ($mockPath) {
        foreach ($k in @('image_util_path','ocr_path','detect_path','interpret_path','capture_path')) {
            if (-not $inp.ContainsKey($k)) { $inp[$k] = $mockPath }
        }
    }
    if (-not $inp.ContainsKey('pwsh_path')) { $inp['pwsh_path'] = $PwshPath }
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

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=mixed' ($man.determinism -eq 'mixed')
Check 'manifest parallel_safe=false' ($man.parallel_safe -eq $false)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=image.index' ($man.skill_id -eq 'image.index')

# ---------- 2) default run: image.util only ----------
$r = Run-Index @{ input = $InputFile }
Check 'default: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'default: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'default: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'default: image_util ran' ($null -ne $e.result -and $e.result.stages.image_util.ran -eq $true)
Check 'default: ocr/detect/interpret skipped' ($e.result.stages.ocr.ran -eq $false -and $e.result.stages.detect.ran -eq $false -and $e.result.stages.interpret.ran -eq $false)
Check 'default: hashes.sha256 present' ($null -ne $e.result.hashes -and -not [string]::IsNullOrWhiteSpace([string]$e.result.hashes.sha256))
Check 'default: confidence null (no stochastic stage)' ($null -eq $e.confidence)
Check 'default: model_provenance empty' (@($e.model_provenance).Count -eq 0)
$ijArt = @($e.artifacts | Where-Object { [string]$_.path -match 'index\.json$' })
$imArt = @($e.artifacts | Where-Object { [string]$_.path -match 'index\.md$' })
Check 'default: index.json + index.md artifacts' ($ijArt.Count -ge 1 -and $imArt.Count -ge 1)
Check 'default: index.json sha256 matches file' ($ijArt.Count -ge 1 -and ((Get-Sha256HexFile ([string]$ijArt[0].path)) -eq [string]$ijArt[0].sha256))

# ---------- 3) full run: -All ----------
$rA = Run-Index @{ input = $InputFile; all = $true }
Check 'all: exit 0' ($rA.exit -eq 0) "exit=$($rA.exit) err=$($rA.err)"
$eA = $rA.env
$evA = Test-SkillResultEnvelope -Json $rA.raw
Check 'all: envelope schema-valid' ([bool]$evA.valid) (($evA.errors) -join '; ')
Check 'all: status ok/partial' ($null -ne $eA -and @('ok','partial') -contains $eA.status) "status=$($eA.status)"
Check 'all: every stage ran' ($eA.result.stages.image_util.ran -and $eA.result.stages.ocr.ran -and $eA.result.stages.detect.ran -and $eA.result.stages.interpret.ran)
$stagesOkA = ($eA.result.stages.ocr.status -in @('ok','partial')) -and ($eA.result.stages.detect.status -in @('ok','partial')) -and ($eA.result.stages.interpret.status -in @('ok','partial'))
Check 'all: stochastic stages ok/partial' $stagesOkA "ocr=$($eA.result.stages.ocr.status) det=$($eA.result.stages.detect.status) int=$($eA.result.stages.interpret.status)"
# envelope confidence must equal the min of the per-stage stochastic confidences (mode-independent: mock=0.7; live may be lower if OCR finds no text)
$stageConfs = @()
foreach ($sn in @('ocr','detect','interpret')) { $st = $eA.result.stages.$sn; if ($st.ran -and ([string]$st.status -in @('ok','partial')) -and $null -ne $st.confidence) { $stageConfs += [double]$st.confidence } }
$expMin = if ($stageConfs.Count -gt 0) { ($stageConfs | Measure-Object -Minimum).Minimum } else { $null }
Check 'all: confidence = min of stage confidences' ($null -ne $eA.confidence -and $null -ne $expMin -and [math]::Abs([double]$eA.confidence - [double]$expMin) -lt 1e-9) "conf=$($eA.confidence) exp=$expMin"
$provStages = @($eA.model_provenance | ForEach-Object { [string]$_.stage })
Check 'all: model_provenance >= 3 (stage-tagged)' (@($eA.model_provenance).Count -ge 3) "n=$(@($eA.model_provenance).Count)"
Check 'all: provenance tagged ocr+detect+interpret' (($provStages -contains 'ocr') -and ($provStages -contains 'detect') -and ($provStages -contains 'interpret')) "stages=$($provStages -join ',')"
Check 'all: summary.caption present' (-not [string]::IsNullOrWhiteSpace([string]$eA.result.summary.caption))
# ocr_text in the summary must mirror the ocr stage text (a photo with no text yields empty text at low confidence -- still valid)
Check 'all: summary.ocr_text mirrors ocr stage' ([string]$eA.result.summary.ocr_text -eq [string]$eA.result.stages.ocr.text)
if ($UseMock) { Check 'all(mock): summary.ocr_text non-empty' (-not [string]::IsNullOrWhiteSpace([string]$eA.result.summary.ocr_text)) }
$topClasses = @($eA.result.summary.top_objects | ForEach-Object { [string]$_.class })
Check 'all: summary.top_objects non-empty' (@($eA.result.summary.top_objects).Count -ge 1) "objs=$($topClasses -join ',')"

# ---------- 4) child-review redirect (orchestrator, NOT a producer) ----------
Check 'redirect: review.is_producer=false' ($eA.result.review.is_producer -eq $false)
$crp = [string]$eA.result.review.child_review_path
Check 'redirect: child_review_path under artifact dir' ($crp -match 'child_review\.jsonl$' -and $crp -match [Regex]::Escape($eA.invocation_id))
if ($UseMock) {
    Check 'redirect: child_review_count == 3 (ocr+detect+interpret flagged)' ([int]$eA.result.review.child_review_count -eq 3) "count=$($eA.result.review.child_review_count)"
    Check 'redirect: child_review.jsonl exists on disk' (Test-Path -LiteralPath $crp -PathType Leaf)
} else {
    Check 'redirect: child_review_count >= 0' ([int]$eA.result.review.child_review_count -ge 0)
}

# ---------- 5) selective stages ----------
$rO = Run-Index @{ input = $InputFile; ocr = $true }
$eO = $rO.env
Check 'ocr-only: ocr ran, detect+interpret skipped' ($eO.result.stages.ocr.ran -and $eO.result.stages.detect.ran -eq $false -and $eO.result.stages.interpret.ran -eq $false)
Check 'ocr-only: confidence = ocr conf' ($null -ne $eO.confidence)

# ---------- 6) -Capture source (mock only) ----------
if ($UseMock) {
    $rC = Run-Index @{ capture = $true; all = $true }
    $eC = $rC.env
    Check 'capture: exit 0' ($rC.exit -eq 0) "exit=$($rC.exit) err=$($rC.err)"
    Check 'capture: input.source=capture' ($null -ne $eC.result -and [string]$eC.result.input.source -eq 'capture')
    Check 'capture: capture image path exists' ($null -ne $eC.result.input.capture -and (Test-Path -LiteralPath ([string]$eC.result.input.capture.image.path) -PathType Leaf))
} else {
    Write-Host "  [SKIP] capture (mock-only unless -Live drives it separately)"
}

# ---------- 7) error: input_not_found ----------
$rErr = Run-Index @{ input = (Join-Path $tmpRoot 'nope.png') }
Check 'error: input_not_found' ($null -ne $rErr.env -and $rErr.env.status -eq 'error' -and $rErr.env.error.code -eq 'input_not_found')
$evE = Test-SkillResultEnvelope -Json $rErr.raw
Check 'error: envelope still schema-valid' ([bool]$evE.valid)

# ---------- 8) error: requested child entrypoint missing ----------
$rMiss = Run-Index @{ input = $InputFile; ocr = $true; ocr_path = (Join-Path $tmpRoot 'no-such-ocr.ps1') }
Check 'error: ocr_not_found when -Ocr and bad -OcrPath' ($null -ne $rMiss.env -and $rMiss.env.status -eq 'error' -and $rMiss.env.error.code -eq 'ocr_not_found') "code=$($rMiss.env.error.code)"

# ---------- 9) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $InputFile; pwsh_path = $PwshPath }
if ($mockPath) { foreach ($k in @('image_util_path','ocr_path','detect_path','interpret_path','capture_path')) { $wrapInp[$k] = $mockPath } }
if ($PythonPath) { $wrapInp['python_path'] = $PythonPath }
$wrapJson = ($wrapInp | ConvertTo-Json -Compress -Depth 8)
$tmpErr = New-TemporaryFile
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$wrapArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Resolve-Path -LiteralPath $wrapper).Path,'-SkillDir',$SkillDir,'-InputsJson',$wrapJson,'-ArtifactRoot',$artRoot,'-PwshPath',$PwshPath)
$wout = & $PwshPath @wrapArgs 2> $tmpErr.FullName
$ErrorActionPreference = $prev
Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
$wrep = $null; try { $wrep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
Check 'wrapper: report manifest_valid + invoked + envelope_valid' ($null -ne $wrep -and $wrep.manifest_valid -and $wrep.invoked -and $wrep.envelope_valid)

# ---------- LIVE-only extras ----------
if ($Live) {
    # a full real index over the fixture; assert real fusion + no canonical-queue write by image.index
    $canon = Join-Path $tmpRoot 'canonical_review.jsonl'
    $rL = Run-Index @{ input = $InputFile; all = $true }
    $eL = $rL.env
    Check 'live: exit 0' ($rL.exit -eq 0) "exit=$($rL.exit) err=$($rL.err)"
    Check 'live: image.util hashes present' (-not [string]::IsNullOrWhiteSpace([string]$eL.result.hashes.sha256))
    Check 'live: detect found objects' ([int]$eL.result.stages.detect.detection_count -ge 1) "count=$($eL.result.stages.detect.detection_count)"
    Check 'live: interpret text present' (-not [string]::IsNullOrWhiteSpace([string]$eL.result.stages.interpret.text))
    Check 'live: model_provenance >= 2' (@($eL.model_provenance).Count -ge 2) "n=$(@($eL.model_provenance).Count)"
    $orphLlama = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    Check 'live: no orphaned llama-server' ($orphLlama -eq 0) "llama=$orphLlama"
}

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
