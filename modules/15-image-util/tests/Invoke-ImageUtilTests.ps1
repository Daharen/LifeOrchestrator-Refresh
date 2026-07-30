#requires -Version 7.0
<#
  Invoke-ImageUtilTests.ps1 -- tests for image.util (Module 15).

  Real-worker & OS-portable (mirrors audio.ingest's real-ffmpeg gate, NOT a mock): because Pillow is
  cross-platform AND version-stable (m15-probe-001 showed identical perceptual hashes on PIL 10.2/numpy 1.26
  and PIL 12.2/numpy 2.4), the harness runs the REAL Invoke-ImageUtil.ps1 -> the REAL image_worker.py under a
  resolved python. It generates its fixtures with Pillow at runtime (no committed binary). The same harness is
  the cloud pre-ship gate (cloud python + Pillow) and the live Windows/executor test (system python).

  -PythonPath <python>  : the interpreter to use (must import PIL + numpy). If omitted, the harness resolves
                          one from the same candidates the wrapper uses.
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath,
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
        & $exe -c 'import PIL, numpy' 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}

$entry = Join-Path $SkillDir 'Invoke-ImageUtil.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m15-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$fxDir = Join-Path $tmpRoot 'fixtures'
New-Item -ItemType Directory -Path $fxDir -Force | Out-Null

Write-Host "=== image.util tests ==="
Write-Host "skill=$entry"

# --- resolve python ---
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
    Write-Host "  [FAIL] no python with Pillow+numpy found (set -PythonPath)"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}
Write-Host "python=$PythonPath"

# --- generate fixtures with Pillow ---
$genPy = @'
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
im = Image.new("RGB", (800, 600), (245, 245, 245))
g = ImageDraw.Draw(im)
g.rectangle([40, 40, 320, 260], fill=(200, 40, 40))
g.ellipse([420, 180, 720, 520], fill=(40, 90, 200))
g.line([0, 0, 800, 600], fill=(20, 20, 20), width=6)
g.text((60, 300), "image util fixture 12345", fill=(0, 0, 0))
im.save(d + "/fixture.png")
im.save(d + "/fixture.jpg", "JPEG", quality=85)   # near-duplicate (re-encoded)
o = Image.new("RGB", (800, 600), (10, 60, 10))
go = ImageDraw.Draw(o)
for i in range(0, 800, 40):
    go.line([i, 0, i - 300, 600], fill=(180, 40, 180), width=10)
go.ellipse([100, 100, 300, 300], fill=(240, 240, 40))
o.save(d + "/other.png")
print("FIXTURES_OK")
'@
$genPath = Join-Path $fxDir 'gen.py'
[System.IO.File]::WriteAllText($genPath, $genPy, $utf8)
& $PythonPath $genPath $fxDir | Out-Null
$fixture = Join-Path $fxDir 'fixture.png'
$fixtureJpg = Join-Path $fxDir 'fixture.jpg'
$other = Join-Path $fxDir 'other.png'
if (-not (Test-Path -LiteralPath $fixture)) { Write-Host "  [FAIL] fixture generation failed"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1 }

function Run-Img([hashtable]$inp) {
    if (-not $inp.ContainsKey('python_path')) { $inp['python_path'] = $PythonPath }
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
Check 'manifest determinism=deterministic' ($man.determinism -eq 'deterministic')
Check 'manifest parallel_safe=true' ($man.parallel_safe -eq $true)
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))
Check 'manifest skill_id=image.util' ($man.skill_id -eq 'image.util')

# ---------- 1b) interpreter portability shim (i17, FANOUT_AGENT_002) ----------
# ADDITIVE config-resolvable SYSTEM python with FALLBACK to the literal. Pure logic (no python needed).
# Proves: shim wired + AST-clean + resolves BYTE-IDENTICALLY to the literal on THIS box + a config
# override genuinely wins (mock). Model-bound speech venv is out of scope (role 'system' only).
$entrySrc = Get-Content -LiteralPath $entry -Raw
Check 'interp: Resolve-LifeorchInterpreter wired into entrypoint' ($entrySrc -match 'Resolve-LifeorchInterpreter')
Check 'interp: additive-shim provenance marker present' ($entrySrc -match 'FANOUT_AGENT_002')
$tk0 = $null; $er0 = $null
$ast0 = [System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$tk0, [ref]$er0)
Check 'interp: entrypoint AST-parses clean' (($null -eq $er0) -or ($er0.Count -eq 0)) (($er0 | ForEach-Object { $_.Message }) -join '; ')
$fnAst = $null
if ($null -ne $ast0) { $fnAst = $ast0.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-SystemPython' }, $true) | Select-Object -First 1 }
Check 'interp: Resolve-SystemPython extractable' ($null -ne $fnAst)
$sysLit = 'C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe'
if ($null -ne $fnAst) {
    . ([scriptblock]::Create($fnAst.Extent.Text))
    # byte-identical: the real config.json system == the literal (or is absent) -> literal returned unchanged
    $resolvedHere = Resolve-SystemPython $sysLit $SkillDir
    Check 'interp: resolves == the current literal on THIS box (byte-identical)' ($resolvedHere -eq $sysLit) "got=$resolvedHere"
    # override honored (mock): a temp repo config.json pointing python_interpreters.system at a DIFFERENT
    # existing interpreter -> the shim returns that path (proves config is genuinely consulted)
    $cfgMod = Join-Path $SkillDir '..\..\ops\setup\LifeorchConfig.psm1'
    if (Test-Path -LiteralPath $cfgMod) {
        $ovrI = Join-Path ([IO.Path]::GetTempPath()) ('m15-interp-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Force -Path (Join-Path $ovrI 'ops/setup') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $ovrI 'modules/99-x') | Out-Null
        Copy-Item (Resolve-Path -LiteralPath $cfgMod).Path (Join-Path $ovrI 'ops/setup/LifeorchConfig.psm1')
        $sentinel = New-TemporaryFile
        $ovrCfg = [pscustomobject]@{ schema='lifeorch.setup.config/0.1'; repo_root=$ovrI; data_root='x'; machine=[pscustomobject]@{}; python_interpreters=[pscustomobject]@{ system=$sentinel.FullName } }
        [System.IO.File]::WriteAllText((Join-Path $ovrI 'ops/setup/config.json'), ($ovrCfg | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
        $modX = (Resolve-Path (Join-Path $ovrI 'modules/99-x')).Path
        $ovrResolved = Resolve-SystemPython $sysLit $modX
        Check 'interp: config override honored (mock)' ($ovrResolved -eq $sentinel.FullName) "got=$ovrResolved"
        try { Remove-Item -LiteralPath $sentinel.FullName -Force -ErrorAction SilentlyContinue } catch {}
        try { Remove-Item -LiteralPath $ovrI -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    } else {
        Check 'interp: config override honored (mock) [skipped: ops/setup not in test tree]' $true
    }
}

# ---------- 2) meta + hashes ----------
$r = Run-Img @{ input = $fixture; op = 'meta' }
Check 'meta: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'meta: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'meta: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'meta: confidence is null (deterministic)' ($null -ne $e -and $null -eq $e.confidence)
Check 'meta: model_provenance empty' ($null -ne $e -and @($e.model_provenance).Count -eq 0)
$rr = $null; if ($null -ne $e) { $rr = $e.result }
Check 'meta: metadata 800x600' ($null -ne $rr -and [int]$rr.metadata.width -eq 800 -and [int]$rr.metadata.height -eq 600) "size=$($rr.metadata.width)x$($rr.metadata.height)"
Check 'meta: format PNG mode RGB' ($null -ne $rr -and $rr.metadata.format -eq 'PNG' -and $rr.metadata.mode -eq 'RGB')
$sha = ''; if ($null -ne $rr) { $sha = [string]$rr.hashes.sha256 }
Check 'meta: sha256 is 64 hex' ($sha -match '^[0-9a-f]{64}$') "sha=$sha"
$ph = ''; if ($null -ne $rr) { $ph = [string]$rr.hashes.phash }
$dh = ''; if ($null -ne $rr) { $dh = [string]$rr.hashes.dhash }
Check 'meta: phash is 16 hex' ($ph -match '^[0-9a-f]{16}$') "phash=$ph"
Check 'meta: dhash is 16 hex' ($dh -match '^[0-9a-f]{16}$') "dhash=$dh"
Check 'meta: sha256 matches the input file' ($sha -eq (Get-Sha256HexFile $fixture))
$arts = @($e.artifacts); $paths = @($arts | ForEach-Object { [string]$_.path })
$hasIj = @($paths | Where-Object { $_ -match 'image\.json$' }).Count -eq 1
$hasIm = @($paths | Where-Object { $_ -match 'image\.md$' }).Count -eq 1
Check 'meta: artifacts include image.json + image.md' ($hasIj -and $hasIm) "paths=$($paths -join ',')"
$ijArt = @($arts | Where-Object { [string]$_.path -match 'image\.json$' })[0]
Check 'meta: image.json artifact sha256 matches file' ($null -ne $ijArt -and (Get-Sha256HexFile ([string]$ijArt.path)) -eq [string]$ijArt.sha256)

# ---------- 3) resize: max_dimension downscale + scale factors ----------
$r = Run-Img @{ input = $fixture; op = 'resize'; max_dimension = 400 }
$rr = $r.env.result
Check 'resize(max_dim): result 400x300' ($null -ne $rr -and [int]$rr.resize.result.width -eq 400 -and [int]$rr.resize.result.height -eq 300) "res=$($rr.resize.result.width)x$($rr.resize.result.height)"
Check 'resize(max_dim): scale_x == scale_y == 0.5' ($null -ne $rr -and [double]$rr.resize.scale_x -eq 0.5 -and [double]$rr.resize.scale_y -eq 0.5) "sx=$($rr.resize.scale_x) sy=$($rr.resize.scale_y)"
$o0 = $null; if ($null -ne $rr -and @($rr.outputs).Count -gt 0) { $o0 = @($rr.outputs)[0] }
Check 'resize(max_dim): output file is 400x300' ($null -ne $o0 -and [int]$o0.width -eq 400 -and [int]$o0.height -eq 300)
Check 'resize(max_dim): one output artifact with sha256' ($null -ne $o0 -and ([string]$o0.sha256) -match '^[0-9a-f]{64}$' -and (Get-Sha256HexFile ([string]$o0.path)) -eq [string]$o0.sha256)

# ---------- 4) resize exact / fit / fill ----------
$r = Run-Img @{ input = $fixture; op = 'resize'; mode = 'exact'; width = 100; height = 120 }
$rr = $r.env.result
Check 'resize(exact): output 100x120' ($null -ne $rr -and [int](@($rr.outputs)[0].width) -eq 100 -and [int](@($rr.outputs)[0].height) -eq 120)
$r = Run-Img @{ input = $fixture; op = 'resize'; mode = 'fit'; width = 400; height = 400 }
$rr = $r.env.result
Check 'resize(fit): keeps aspect -> 400x300' ($null -ne $rr -and [int](@($rr.outputs)[0].width) -eq 400 -and [int](@($rr.outputs)[0].height) -eq 300)
$r = Run-Img @{ input = $fixture; op = 'resize'; mode = 'fill'; width = 200; height = 200 }
$rr = $r.env.result
Check 'resize(fill): exact box 200x200' ($null -ne $rr -and [int](@($rr.outputs)[0].width) -eq 200 -and [int](@($rr.outputs)[0].height) -eq 200)

# ---------- 5) crop: rect / normalized / region ----------
$r = Run-Img @{ input = $fixture; op = 'crop'; x = 10; y = 20; crop_width = 100; crop_height = 50 }
$rr = $r.env.result
Check 'crop(rect): applied 100x50' ($null -ne $rr -and [int]$rr.crop.applied.width -eq 100 -and [int]$rr.crop.applied.height -eq 50)
Check 'crop(rect): output file 100x50' ($null -ne $rr -and [int](@($rr.outputs)[0].width) -eq 100 -and [int](@($rr.outputs)[0].height) -eq 50)
$r = Run-Img @{ input = $fixture; op = 'crop'; normalized = $true; x = 0; y = 0; crop_width = 0.5; crop_height = 0.5 }
$rr = $r.env.result
Check 'crop(normalized 0.5): applied 400x300' ($null -ne $rr -and [int]$rr.crop.applied.width -eq 400 -and [int]$rr.crop.applied.height -eq 300)
$r = Run-Img @{ input = $fixture; op = 'crop'; region = 'center'; region_fraction = 0.5 }
$rr = $r.env.result
Check 'crop(region center 0.5): applied 400x300' ($null -ne $rr -and [int]$rr.crop.applied.width -eq 400 -and [int]$rr.crop.applied.height -eq 300)

# ---------- 6) convert to each format ----------
$fmtMap = @{ png='PNG'; jpg='JPEG'; webp='WEBP'; bmp='BMP'; tiff='TIFF' }
foreach ($f in @('png','jpg','webp','bmp','tiff')) {
    $r = Run-Img @{ input = $fixture; op = 'convert'; format = $f }
    $rr = $r.env.result
    $o = $null; if ($null -ne $rr -and @($rr.outputs).Count -gt 0) { $o = @($rr.outputs)[0] }
    $ok = ($null -ne $o -and [string]$o.format -eq $fmtMap[$f] -and [int]$o.width -eq 800 -and [int]$o.height -eq 600 -and [int]$o.bytes -gt 0)
    Check "convert($f): reopenable $($fmtMap[$f]) 800x600" $ok "got format=$($o.format) size=$($o.width)x$($o.height)"
}

# ---------- 7) tile: grid + fixed size ----------
$r = Run-Img @{ input = $fixture; op = 'tile'; tile_cols = 2; tile_rows = 2 }
$rr = $r.env.result
Check 'tile(grid 2x2): count == 4' ($null -ne $rr -and [int]$rr.tile.count -eq 4) "count=$($rr.tile.count)"
$tileImgs = @($rr.outputs)
Check 'tile(grid 2x2): 4 image artifacts with sha256' ($tileImgs.Count -eq 4 -and (@($tileImgs | Where-Object { ([string]$_.sha256) -match '^[0-9a-f]{64}$' }).Count -eq 4))
$r = Run-Img @{ input = $fixture; op = 'tile'; tile_width = 300; tile_height = 300 }
$rr = $r.env.result
Check 'tile(size 300): count == 6 (ceil 800/300 * ceil 600/300)' ($null -ne $rr -and [int]$rr.tile.count -eq 6) "count=$($rr.tile.count)"

# ---------- 8) similarity ----------
$r = Run-Img @{ input = $fixture; op = 'similarity'; compare_to = $fixture }
$rr = $r.env.result
Check 'similarity(self): hamming_phash == 0' ($null -ne $rr -and [int]$rr.similarity.hamming_phash -eq 0) "ham=$($rr.similarity.hamming_phash)"
Check 'similarity(self): similarity == 1.0' ($null -ne $rr -and [double]$rr.similarity.similarity -eq 1.0)
$rNear = Run-Img @{ input = $fixture; op = 'similarity'; compare_to = $fixtureJpg }
$near = [int]$rNear.env.result.similarity.hamming_phash
Check 'similarity(near-dup jpg): small hamming (<=8)' ($near -le 8) "ham=$near"
$rDiff = Run-Img @{ input = $fixture; op = 'similarity'; compare_to = $other }
$diff = [int]$rDiff.env.result.similarity.hamming_phash
Check 'similarity(different): hamming(different) > hamming(near-dup)' ($diff -gt $near) "diff=$diff near=$near"

# ---------- 9) error paths ----------
$r = Run-Img @{ input = (Join-Path $fxDir 'nope.png'); op = 'meta' }
Check 'error: input_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'input_not_found')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-Img @{ input = $fixture; op = 'frobnicate' }
Check 'error: invalid_op' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_op')
$r = Run-Img @{ input = $fixture; op = 'resize' }
Check 'error: missing_params (resize with no dims)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_params')
$r = Run-Img @{ input = $fixture; op = 'convert'; format = 'gif' }
Check 'error: unsupported_format' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'unsupported_format')
$r = Run-Img @{ input = $fixture; op = 'similarity'; compare_to = (Join-Path $fxDir 'nope2.png') }
Check 'error: compare_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'compare_not_found')

# ---------- 10) Module 1 wrapper ----------
$wrapInp = [ordered]@{ input = $fixture; op = 'meta'; python_path = $PythonPath }
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

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
