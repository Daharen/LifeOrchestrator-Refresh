#requires -Version 7.0
<#
  Invoke-FsManageTests.ps1 -- drives the REAL Invoke-FsManage.ps1. Deterministic + OS-portable (uses temp
  paths + asserts known-folder resolution lands under the user home). Runs off-GPU on cloud pwsh (pre-ship
  gate) and unchanged live via the executor. ASCII-only. Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh'),
    [string]$SkillPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-FsManage.ps1'),
    [string]$WrapperPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m28-fsm-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$artRoot = Join-Path $work 'art'

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function Run-Fsm([hashtable]$inputs) {
    $ij = ($inputs | ConvertTo-Json -Compress -Depth 8)
    $errF = Join-Path $work ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $out = & $PwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SkillPath -InputsJson $ij -ArtifactRoot $artRoot 2> $errF
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ env=$env; raw=$txt; err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}
function New-File([string]$name, [string]$content) {
    $p = Join-Path $work $name
    [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
    return $p
}

Write-Output "==== fs.manage harness ===="
Write-Output ("skill=" + $SkillPath)
Write-Output ""

# --- S1: copy a file into a target dir (keeps filename) ---
$src = New-File 'a.txt' 'hello'
$dstDir = Join-Path $work 'out1'
$r = Run-Fsm @{ op='copy'; source=$src; dest=$dstDir }
$e = $r.env; $res = if ($e){$e.result}else{$null}
Write-Output "S1 copy-into-dir:"
Ok ($null -ne $e -and $e.schema -eq 'lifeorch.skill.result/0.1' -and $e.status -eq 'ok') 'S1 envelope ok'
Ok ($null -ne $res -and (Test-Path -LiteralPath (Join-Path $dstDir 'a.txt'))) 'S1 file copied into dir keeping name'
Ok ($null -ne $res -and $res.dest_was_dir -eq $true -and (Test-Path -LiteralPath $src)) 'S1 dest treated as dir + source retained (copy)'
Ok ($null -ne $e -and $null -eq $e.confidence -and @($e.model_provenance).Count -eq 0) 'S1 deterministic (null confidence, no provenance)'

# --- S2: move a file to a full file path (rename) ---
$src2 = New-File 'b.txt' 'world'
$dstFile = Join-Path $work 'renamed.txt'
$r = Run-Fsm @{ op='move'; source=$src2; dest=$dstFile }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S2 move-rename:"
Ok ($null -ne $res -and (Test-Path -LiteralPath $dstFile)) 'S2 moved to the file path'
Ok (-not (Test-Path -LiteralPath $src2)) 'S2 source removed (move)'
Ok ($null -ne $res -and $res.dest_was_dir -eq $false) 'S2 dest treated as a file path'

# --- S3: overwrite guard ---
$src3 = New-File 'c.txt' 'v1'
$occupied = Join-Path $work 'occupied.txt'
[System.IO.File]::WriteAllText($occupied, 'old', [System.Text.UTF8Encoding]::new($false))
$r = Run-Fsm @{ op='copy'; source=$src3; dest=$occupied }
Write-Output "S3 overwrite-guard:"
Ok ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'already_exists') 'S3 refuses to overwrite by default'
$r = Run-Fsm @{ op='copy'; source=$src3; dest=$occupied; overwrite=$true }
Ok ($null -ne $r.env -and $r.env.status -eq 'ok') 'S3 overwrites with overwrite=true'
Ok ((Get-Content -LiteralPath $occupied -Raw) -eq 'v1') 'S3 content replaced'

# --- S4: mkdir (nested, parents created) ---
$newDir = Join-Path (Join-Path $work 'x') 'y'
$r = Run-Fsm @{ op='mkdir'; path=$newDir }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S4 mkdir:"
Ok ($null -ne $res -and (Test-Path -LiteralPath $newDir -PathType Container) -and $res.created -eq $true) 'S4 nested dir created'
$r = Run-Fsm @{ op='mkdir'; path=$newDir }
Ok ($null -ne $r.env -and $r.env.result.existed -eq $true -and $r.env.status -eq 'ok') 'S4 mkdir on existing is ok (existed=true)'

# --- S5: known-folder resolution (desktop) lands under the user home ---
$uhome = [Environment]::GetFolderPath('UserProfile'); if([string]::IsNullOrWhiteSpace($uhome)){ $uhome=$env:USERPROFILE }; if([string]::IsNullOrWhiteSpace($uhome)){ $uhome=[string]$HOME }
$srcImg = New-File 'pic.png' 'PNGDATA'
$r = Run-Fsm @{ op='copy'; source=$srcImg; dest='desktop' }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S5 known-folder desktop:"
Ok ($null -ne $r.env -and $r.env.status -eq 'ok') 'S5 ran ok'
$deskFinal = if($res){[string]$res.dest}else{''}
Ok ($deskFinal -match '[\\/]Desktop[\\/]pic\.png$') 'S5 desktop resolved to <home>/Desktop/pic.png'
Ok ($deskFinal.StartsWith($uhome)) 'S5 desktop is under the user home'
if (Test-Path -LiteralPath $deskFinal) { Remove-Item -LiteralPath $deskFinal -Force -ErrorAction SilentlyContinue }

# --- S6: ~ and %ENV% expansion ---
$srcT = New-File 'd.txt' 'z'
$r = Run-Fsm @{ op='copy'; source=$srcT; dest='~/m28-fsm-tilde-test' }
$res = if ($r.env){$r.env.result}else{$null}
Write-Output "S6 tilde/env:"
Ok ($null -ne $res -and ([string]$res.dest).StartsWith($uhome)) 'S6 ~ expands to the user home'
if ($res -and (Test-Path -LiteralPath ([string]$res.dest))) { Remove-Item -LiteralPath ([string]$res.dest) -Recurse -Force -ErrorAction SilentlyContinue }

# --- S7: error paths ---
$r = Run-Fsm @{ op='copy'; source=(Join-Path $work 'nope.txt'); dest=$dstDir }
Write-Output "S7 error-paths:"
Ok ($null -ne $r.env -and $r.env.error.code -eq 'input_not_found') 'S7 missing source -> input_not_found'
$r = Run-Fsm @{ op='frobnicate'; source=$src; dest=$dstDir }
Ok ($null -ne $r.env -and $r.env.error.code -eq 'invalid_op') 'S7 bad op -> invalid_op'
$r = Run-Fsm @{ op='copy'; dest=$dstDir }
Ok ($null -ne $r.env -and $r.env.error.code -eq 'missing_parameter') 'S7 no source -> missing_parameter'

# --- S8: Module 1 wrapper ---
if (-not [string]::IsNullOrWhiteSpace($WrapperPath) -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path -Parent $SkillPath
    $srcW = New-File 'w.txt' 'wrap'
    $ij = [ordered]@{ op='copy'; source=$srcW; dest=(Join-Path $work 'wrapout') } | ConvertTo-Json -Compress
    $wout = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WrapperPath -SkillDir $skillDir -InputsJson $ij -PwshPath $PwshExe 2> (Join-Path $work 'err-wrap.txt')
    $wcode = $LASTEXITCODE
    $rep = $null; try { $rep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
    Write-Output "S8 Module-1 wrapper:"
    Ok ($null -ne $rep -and $rep.manifest_valid -eq $true) 'S8 manifest valid'
    Ok ($null -ne $rep -and $rep.envelope_valid -eq $true -and $rep.exit_code -eq 0 -and $wcode -eq 0) 'S8 envelope valid + exit 0'
} else { Write-Output "S8 Module-1 wrapper: SKIPPED (no -WrapperPath)" }

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
