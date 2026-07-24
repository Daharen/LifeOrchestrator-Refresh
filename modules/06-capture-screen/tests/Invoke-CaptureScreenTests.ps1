#requires -Version 7.0
# Regression tests for Module 6 (capture.screen). Run directly or via the executor.
# Core checks (manifest, monitor/region capture, error paths, wrapper) need only a desktop session. The
# window-capture check spins up a self-contained WinForms probe window (Start-CaptureProbe.ps1) and captures
# it by title, verifying geometry/metadata (not pixel content), with guaranteed teardown.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-CaptureScreen.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$probe   = Join-Path $PSScriptRoot 'Start-CaptureProbe.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function WaitFile([string]$p, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) { if (Test-Path -LiteralPath $p) { return $true }; Start-Sleep -Milliseconds 300 }
    return (Test-Path -LiteralPath $p)
}
function PngMagic([string]$p) {
    try { $b = [System.IO.File]::ReadAllBytes($p); return ($b.Length -gt 8 -and $b[0] -eq 137 -and $b[1] -eq 80 -and $b[2] -eq 78 -and $b[3] -eq 71) } catch { return $false }
}
function JpgMagic([string]$p) {
    try { $b = [System.IO.File]::ReadAllBytes($p); return ($b.Length -gt 3 -and $b[0] -eq 255 -and $b[1] -eq 216 -and $b[2] -eq 255) } catch { return $false }
}

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

# ---- monitor: primary ----
$m = RunEntry @('-Target','monitor','-Monitor','primary')
Check 'monitor exit 0' ($script:code -eq 0)
$evm = Test-SkillResultEnvelope -Json $m
Check 'monitor envelope validates' ([bool]$evm.valid)
if (-not $evm.valid) { $evm.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$om = $m | ConvertFrom-Json
Check 'monitor status ok/partial' (@('ok','partial') -contains $om.status)
Check 'monitor mode=monitor' ($om.result.mode -eq 'monitor')
Check 'monitor capture present' ($null -ne $om.result.capture)
Check 'monitor image dims > 0' ($om.result.capture.image_width -gt 0 -and $om.result.capture.image_height -gt 0)
Check 'monitor image file exists' ($null -ne $om.result.capture -and (Test-Path -LiteralPath $om.result.capture.path))
Check 'monitor PNG magic' ($null -ne $om.result.capture -and (PngMagic $om.result.capture.path))
if ($null -ne $om.result.capture -and (Test-Path -LiteralPath $om.result.capture.path)) {
    $bytes = [System.IO.File]::ReadAllBytes($om.result.capture.path)
    $sha = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    Check 'monitor sha256 matches file' ($sha -eq $om.result.capture.sha256)
}
Check 'monitor environment monitors listed' ($null -ne $om.result.environment -and @($om.result.environment.monitors).Count -ge 1)

# ---- monitor: all == virtual screen ----
$ma = RunEntry @('-Target','monitor','-Monitor','all') | ConvertFrom-Json
Check 'monitor all captured' ($null -ne $ma.result.capture)
if ($null -ne $ma.result.capture) {
    $vs = $ma.result.environment.virtual_screen
    Check 'monitor all == virtual screen' ($ma.result.capture.rectangle.width -eq $vs.width -and $ma.result.capture.rectangle.height -eq $vs.height)
}

# ---- region: exact dimensions + PNG magic ----
$rg = RunEntry @('-Target','region','-X','0','-Y','0','-Width','120','-Height','80')
$evr = Test-SkillResultEnvelope -Json $rg
Check 'region envelope validates' ([bool]$evr.valid)
$org = $rg | ConvertFrom-Json
Check 'region mode=region' ($org.result.mode -eq 'region')
Check 'region image is 120x80' ($null -ne $org.result.capture -and $org.result.capture.image_width -eq 120 -and $org.result.capture.image_height -eq 80)
Check 'region PNG magic' ($null -ne $org.result.capture -and (PngMagic $org.result.capture.path))

# ---- region: jpg ----
$jg = RunEntry @('-Target','region','-X','0','-Y','0','-Width','100','-Height','60','-Format','jpg') | ConvertFrom-Json
Check 'jpg format reported' ($null -ne $jg.result.capture -and $jg.result.capture.format -eq 'jpg')
Check 'jpg file exists + JPEG magic' ($null -ne $jg.result.capture -and (Test-Path -LiteralPath $jg.result.capture.path) -and (JpgMagic $jg.result.capture.path))

# ---- error paths (all side-effect free, must be valid error envelopes, exit 0) ----
$e1txt = RunEntry @('-Target','frobnicate')
$ev1 = Test-SkillResultEnvelope -Json $e1txt
$e1 = $e1txt | ConvertFrom-Json
Check 'invalid_target valid envelope' ([bool]$ev1.valid)
Check 'invalid_target error' ($e1.status -eq 'error' -and $e1.error.code -eq 'invalid_target')

$e2 = RunEntry @('-Target','monitor','-Format','bmp') | ConvertFrom-Json
Check 'invalid_format error' ($e2.status -eq 'error' -and $e2.error.code -eq 'invalid_format')

$e3txt = RunEntry @('-Target','region','-Width','0','-Height','0')
$ev3 = Test-SkillResultEnvelope -Json $e3txt
$e3 = $e3txt | ConvertFrom-Json
Check 'invalid_region valid envelope' ([bool]$ev3.valid)
Check 'invalid_region error' ($e3.status -eq 'error' -and $e3.error.code -eq 'invalid_region')

$e4 = RunEntry @('-Target','monitor','-Monitor','999') | ConvertFrom-Json
Check 'monitor_not_found error' ($e4.status -eq 'error' -and $e4.error.code -eq 'monitor_not_found')

$e5 = RunEntry @('-Target','window') | ConvertFrom-Json
Check 'no_target error' ($e5.status -eq 'error' -and $e5.error.code -eq 'no_target')

$e6txt = RunEntry @('-Target','window','-Title','zzz-no-such-window-zzz')
$ev6 = Test-SkillResultEnvelope -Json $e6txt
$e6 = $e6txt | ConvertFrom-Json
Check 'target_not_found valid envelope' ([bool]$ev6.valid)
Check 'target_not_found error' ($e6.status -eq 'error' -and $e6.error.code -eq 'target_not_found')

# ---- wrapper (Module 1) ----
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson '{"target":"region","x":0,"y":0,"width":64,"height":48}'
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)

# ---- window capture against a self-contained WinForms probe ----
$token = [Guid]::NewGuid().ToString('N').Substring(0,8)
$signalDir = Join-Path $env:TEMP "lo-cap-probe-$token"
$titleGlob = "LO Capture Probe $token*"
$proc = $null
try {
    $proc = Start-Process -FilePath $PwshPath -PassThru -ArgumentList @('-NoLogo','-NoProfile','-File',$probe,'-Token',$token,'-SignalDir',$signalDir,'-Seconds','120')
    $ready = WaitFile (Join-Path $signalDir 'ready.txt') 25
    Check 'probe window ready' $ready
    if ($ready) {
        Start-Sleep -Milliseconds 600
        $wtxt = RunEntry @('-Target','window','-Title',$titleGlob)
        $evw = Test-SkillResultEnvelope -Json $wtxt
        Check 'window envelope validates' ([bool]$evw.valid)
        $ow = $wtxt | ConvertFrom-Json
        Check 'window status ok/partial' (@('ok','partial') -contains $ow.status)
        Check 'window mode=window' ($ow.result.mode -eq 'window')
        Check 'window record present' ($null -ne $ow.result.window -and $ow.result.window.hwnd -ne 0)
        Check 'window title matches probe' ($null -ne $ow.result.window -and ($ow.result.window.title -like $titleGlob))
        Check 'window capture dims > 0' ($null -ne $ow.result.capture -and $ow.result.capture.image_width -gt 0 -and $ow.result.capture.image_height -gt 0)
        Check 'window bounds_source known' ($null -ne $ow.result.window -and @('dwm','getwindowrect') -contains $ow.result.window.bounds_source)
        Check 'window PNG on disk' ($null -ne $ow.result.capture -and (Test-Path -LiteralPath $ow.result.capture.path) -and (PngMagic $ow.result.capture.path))
    }
}
finally {
    try { if ($null -ne $proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
    Start-Sleep -Milliseconds 300
    try { if (Test-Path -LiteralPath $signalDir) { Remove-Item -LiteralPath $signalDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
