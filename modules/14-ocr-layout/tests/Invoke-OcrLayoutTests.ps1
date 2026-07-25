#requires -Version 7.0
<#
  Invoke-OcrLayoutTests.ps1 — tests for ocr.layout (Module 14).

  Dual-mode & OS-portable (mirrors Modules 8/9/11 mock pattern):
   * -UseMock  : run the REAL wrapper against a mock OCR worker (tests/mock-ocr-worker.ps1 + the captured
                 real meta tests/fixtures/ocr-sample.meta.json) and a temp registry — no Windows/WinRT
                 needed. This is the cloud pre-ship gate. The wrapper spawns $PwshPath to run the mock.
   * default   : resolve the real Windows.Media.Ocr worker (Windows PowerShell 5.1) and OCR a real image
                 fixture (Windows/executor). Same assertions hold in both modes (the meta IS a real capture).

  The fixture (tests/fixtures/ocr-sample.png) contains: "HELLO WORLD" / "The quick brown fox 12345".
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$ImageFile,
    [string]$BlankImage,
    [string]$Registry,
    [string]$Powershell51Path = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe',
    [string]$OcrWorkerPath,
    [string]$CapturePath,
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
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Get-Sha256HexFile([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$entry = Join-Path $SkillDir 'Invoke-OcrLayout.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m14-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'

Write-Host "=== ocr.layout tests (UseMock=$UseMock) ==="
Write-Host "skill=$entry"

if ([string]::IsNullOrWhiteSpace($ImageFile)) { $ImageFile = Join-Path $PSScriptRoot 'fixtures/ocr-sample.png' }
if ([string]::IsNullOrWhiteSpace($BlankImage)) { $BlankImage = Join-Path $PSScriptRoot 'fixtures/ocr-blank.png' }

# --- mock wiring + a temp registry (always self-contained) ---
if ($UseMock) {
    if (-not $PSBoundParameters.ContainsKey('Powershell51Path')) { $Powershell51Path = $PwshPath }
    if ([string]::IsNullOrWhiteSpace($OcrWorkerPath)) { $OcrWorkerPath = Join-Path $PSScriptRoot 'mock-ocr-worker.ps1' }
    $env:MOCK_OCR_META = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'fixtures/ocr-sample.meta.json')).Path
}
if ([string]::IsNullOrWhiteSpace($Registry)) {
    $Registry = Join-Path $tmpRoot 'models.test.json'
    $reg = [ordered]@{
        schema='lifeorch.model_registry/0.1'; host='cloud-test'
        models=@( [ordered]@{ model_id='ocr.windows.media'; type='ocr'; wired=$false; name='Windows.Media.Ocr (system)'; family='windows.media.ocr'; engine='windows.media.ocr' } )
    }
    [System.IO.File]::WriteAllText($Registry, ($reg | ConvertTo-Json -Depth 8), $utf8)
}

function Run-Ocr([hashtable]$inp) {
    if (-not $inp.ContainsKey('registry')) { $inp['registry'] = $Registry }
    if (-not $inp.ContainsKey('powershell51_path')) { $inp['powershell51_path'] = $Powershell51Path }
    if ($OcrWorkerPath -and -not $inp.ContainsKey('ocr_worker_path')) { $inp['ocr_worker_path'] = $OcrWorkerPath }
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
Check 'manifest parallel_safe=true' ($man.parallel_safe -eq $true)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=ocr.layout' ($man.skill_id -eq 'ocr.layout')

# ---------- 2) main OCR ----------
$r = Run-Ocr @{ input = $ImageFile }
Check 'ocr: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'ocr: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'ocr: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
$rr = $null; if ($null -ne $e) { $rr = $e.result }
Check "ocr: text contains 'HELLO'" ($null -ne $rr -and ([string]$rr.text) -match 'HELLO') "text=$($rr.text)"
Check "ocr: text contains 'WORLD'" ($null -ne $rr -and ([string]$rr.text) -match 'WORLD')
Check "ocr: text contains 'quick'" ($null -ne $rr -and ([string]$rr.text) -match 'quick')
Check 'ocr: word_count >= 5' ($null -ne $rr -and [int]$rr.word_count -ge 5) "words=$($rr.word_count)"
Check 'ocr: line_count >= 2' ($null -ne $rr -and [int]$rr.line_count -ge 2) "lines=$($rr.line_count)"
$line0 = $null; if ($null -ne $rr -and (@($rr.lines).Count -gt 0)) { $line0 = @($rr.lines)[0] }
Check 'ocr: reading order — line0 is the HELLO WORLD line' ($null -ne $line0 -and ([string]$line0.text) -match 'HELLO') "line0=$($line0.text)"
$w0 = $null; if ($null -ne $line0 -and (@($line0.words).Count -gt 0)) { $w0 = @($line0.words)[0] }
$boxOk = ($null -ne $w0 -and (Has $w0 'x') -and (Has $w0 'y') -and (Has $w0 'width') -and (Has $w0 'height') -and ([int]$w0.width -gt 0) -and ([int]$w0.height -gt 0))
Check 'ocr: first word has an integer pixel bounding box (width/height>0)' $boxOk "w0=$($w0 | ConvertTo-Json -Compress)"
$lboxOk = ($null -ne $line0 -and (Has $line0 'bounding_rect') -and ([int]$line0.bounding_rect.width -gt 0))
Check 'ocr: line has a bounding_rect' $lboxOk
Check 'ocr: overall confidence in (0,1]' ($null -ne $e.confidence -and [double]$e.confidence -gt 0 -and [double]$e.confidence -le 1) "conf=$($e.confidence)"
Check 'ocr: model_provenance[1], engine windows.media.ocr' (@($e.model_provenance).Count -eq 1 -and (@($e.model_provenance)[0].engine -eq 'windows.media.ocr')) "n=$(@($e.model_provenance).Count)"
$arts = @($e.artifacts)
$paths = @($arts | ForEach-Object { [string]$_.path })
$hasOj = @($paths | Where-Object { $_ -match 'ocr\.json$' }).Count -eq 1
$hasOm = @($paths | Where-Object { $_ -match 'ocr\.md$' }).Count -eq 1
Check 'ocr: artifacts include ocr.json + ocr.md' ($hasOj -and $hasOm) "paths=$($paths -join ',')"
$ojArt = @($arts | Where-Object { [string]$_.path -match 'ocr\.json$' })[0]
$shaOk = $false; if ($null -ne $ojArt) { $shaOk = ((Get-Sha256HexFile ([string]$ojArt.path)) -eq [string]$ojArt.sha256) }
Check 'ocr: ocr.json artifact sha256 matches file' $shaOk

# ---------- 3) review routing (forced high threshold) ----------
$rq = Join-Path $tmpRoot 'review_queue.jsonl'
if (Test-Path -LiteralPath $rq) { Remove-Item -LiteralPath $rq -Force }
$r2 = Run-Ocr @{ input = $ImageFile; confidence_threshold = 0.999; review_queue_path = $rq }
$e2 = $r2.env
Check 'review: flagged_count >= 1' ($null -ne $e2.result -and [int]$e2.result.review.flagged_count -ge 1) "flagged=$($e2.result.review.flagged_count)"
$rqOk = $false
if (Test-Path -LiteralPath $rq) {
    $line = (Get-Content -LiteralPath $rq -TotalCount 1)
    if ($line) { $ri = $line | ConvertFrom-Json; $rqOk = (($ri.schema -eq 'lifeorch.review.item/0.1') -and ($ri.flagged_by -eq 'ocr.layout') -and ($ri.requested -eq 'verify_ocr') -and ($ri.status -eq 'open')) }
}
Check 'review: queue line is a valid ocr.layout review item' $rqOk

# ---------- 4) no-text guard ----------
$rq2 = Join-Path $tmpRoot 'review_queue_notext.jsonl'
$prevMeta = $env:MOCK_OCR_META
if ($UseMock) {
    $notextMeta = Join-Path $tmpRoot 'notext.meta.json'
    $nm = [ordered]@{ ok=$true; engine_language='en-US'; available_languages=@('en-US'); max_image_dimension=10000; image_w=120; image_h=120; text=''; text_angle=0; ocr_ms=4; line_count=0; lines=@() }
    [System.IO.File]::WriteAllText($notextMeta, ($nm | ConvertTo-Json -Depth 8), $utf8)
    $env:MOCK_OCR_META = $notextMeta
    $rNo = Run-Ocr @{ input = $ImageFile; review_queue_path = $rq2 }
    $env:MOCK_OCR_META = $prevMeta
} else {
    if (Test-Path -LiteralPath $BlankImage -PathType Leaf) { $rNo = Run-Ocr @{ input = $BlankImage; review_queue_path = $rq2 } }
    else { $rNo = $null; Write-Host "  [SKIP] no-text (blank fixture missing)" }
}
if ($null -ne $rNo) {
    Check 'no-text: word_count = 0' ($null -ne $rNo.env.result -and [int]$rNo.env.result.word_count -eq 0) "words=$($rNo.env.result.word_count)"
    $ntOk = $false
    if (Test-Path -LiteralPath $rq2) { $l = (Get-Content -LiteralPath $rq2 -TotalCount 1); if ($l) { $ri2 = $l | ConvertFrom-Json; $ntOk = (($ri2.flagged_by -eq 'ocr.layout') -and ($ri2.requested -eq 'verify_no_text')) } }
    Check 'no-text: emits a verify_no_text review item' $ntOk
}

# ---------- 5) error paths ----------
$rErr1 = Run-Ocr @{ input = (Join-Path $tmpRoot 'does-not-exist.png') }
Check 'error: input_not_found' ($null -ne $rErr1.env -and $rErr1.env.status -eq 'error' -and $rErr1.env.error.code -eq 'input_not_found')
$ev1 = Test-SkillResultEnvelope -Json $rErr1.raw
Check 'error: envelope still schema-valid' ([bool]$ev1.valid)
$rErr2 = Run-Ocr @{ input = $ImageFile; engine = 'ocr.nope' }
Check 'error: engine_not_found' ($null -ne $rErr2.env -and $rErr2.env.status -eq 'error' -and $rErr2.env.error.code -eq 'engine_not_found')

# ---------- 6) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $ImageFile; registry = $Registry; powershell51_path = $Powershell51Path; pwsh_path = $PwshPath }
if ($OcrWorkerPath) { $wrapInp['ocr_worker_path'] = $OcrWorkerPath }
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

# ---------- 7) capture.screen composition (live only) ----------
if (-not $UseMock) {
    $capEntry = $CapturePath
    if ([string]::IsNullOrWhiteSpace($capEntry)) { $capEntry = Join-Path $SkillDir '..\06-capture-screen\Invoke-CaptureScreen.ps1' }
    if (Test-Path -LiteralPath $capEntry -PathType Leaf) {
        $rCap = Run-Ocr @{ capture = $true; capture_inputs = @{ target='monitor'; monitor='primary'; format='png' }; capture_path = (Resolve-Path -LiteralPath $capEntry).Path }
        $capStatus = if ($null -ne $rCap.env -and (Has $rCap.env 'status')) { [string]$rCap.env.status } else { 'null' }
        $capErr = ''
        if ($null -ne $rCap.env -and (Has $rCap.env 'error') -and $null -ne $rCap.env.error) { $capErr = [string]$rCap.env.error.code }
        Check 'capture: status ok/partial' ($null -ne $rCap.env -and @('ok','partial') -contains $capStatus) "status=$capStatus err=$capErr"
        $capSrc = ''
        if ($null -ne $rCap.env -and (Has $rCap.env 'result') -and $null -ne $rCap.env.result) { $capSrc = [string]$rCap.env.result.input.source }
        Check 'capture: source=capture' ($capSrc -eq 'capture') "source=$capSrc"
    } else { Write-Host "  [SKIP] capture.screen composition (entrypoint not found)" }
}

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
