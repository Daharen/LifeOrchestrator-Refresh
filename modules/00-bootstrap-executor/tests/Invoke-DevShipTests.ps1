#requires -Version 7.0
<#
  Invoke-DevShipTests.ps1 -- drives the REAL Invoke-DevShip.ps1 against throwaway temp git repos.
  Runs OFF-machine on any box with pwsh 7 + git (the cloud pre-ship gate) and, unchanged, live via the
  executor. ASCII-only. Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$DevShipPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DevShip.ps1'),
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$DevShipPath = (Resolve-Path -LiteralPath $DevShipPath).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Sha([string]$p) { $s = [System.Security.Cryptography.SHA256]::Create(); try { ([System.BitConverter]::ToString($s.ComputeHash([System.IO.File]::ReadAllBytes($p)))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() } }

function New-Repo {
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("devship-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    & git -C $repo init -q | Out-Null
    & git -C $repo config user.email 'test@local' | Out-Null
    & git -C $repo config user.name 'DevShip Test' | Out-Null
    & git -C $repo config commit.gpgsign false | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), "seed`n", $utf8)
    & git -C $repo add README.md | Out-Null
    & git -C $repo commit -q -m 'seed' | Out-Null
    return $repo
}
function Add-File([string]$repo, [string]$rel, [string]$content) {
    $full = Join-Path $repo $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force -ErrorAction SilentlyContinue | Out-Null
    [System.IO.File]::WriteAllText($full, $content, $utf8)
    return $full
}
function Run-DevShip([string]$repo, $inputsObj, [switch]$NoCommit) {
    $json = ($inputsObj | ConvertTo-Json -Depth 12 -Compress)
    $args = @('-NoLogo', '-NoProfile', '-File', $DevShipPath, '-InputsJson', $json, '-RepoRoot', $repo)
    if ($NoCommit) { $args += '-NoCommit' }
    $out = & $PwshExe @args
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ env = $env; raw = $txt }
}
function Head([string]$repo) { return ((& git -C $repo rev-parse HEAD) | Out-String).Trim() }

$GOOD_PS = "param()`nWrite-Output 'ok'`n"
$BAD_PS  = "param(`nWrite-Output 'oops'`n"   # unclosed param( -> parse error
$TRAILERS = "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`nClaude-Session: https://claude.ai/code/session_test"

Write-Output "==== dev.ship temp-repo harness ===="
Write-Output ("pwsh=" + $PwshExe); Write-Output ("devship=" + $DevShipPath)
Write-Output ("git=" + ((& git --version) | Out-String).Trim()); Write-Output ""

# --- S1: all green + commit ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$t = Add-File $repo 'mod/a.txt' "hello`n"
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = (Sha $g) }, @{ path = 'mod/a.txt'; sha256 = (Sha $t) })
    ast_check = $true
    test_argv = @('{PWSH}', '-NoProfile', '-Command', 'Write-Output hi; exit 0')
    commit = $true
    commit_files = @('mod/good.ps1', 'mod/a.txt')
    commit_message = "devship test: all green`n`n$TRAILERS"
    check_orphans = @()
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S1 all-green + commit:"
Ok ($null -ne $e -and $e.schema -eq 'lifeorch.devship.result/0.1') 'S1 emits a devship result envelope'
Ok ($null -ne $e -and $e.ok -eq $true) 'S1 ok=true'
Ok ($null -ne $e -and $e.sha.ok -eq $true -and $e.sha.checked -eq 2) 'S1 sha verified (2 files)'
Ok ($null -ne $e -and $e.ast.ok -eq $true -and $e.ast.checked -eq 1) 'S1 ast parsed the 1 ps1'
Ok ($null -ne $e -and $e.tests.ran -eq $true -and $e.tests.pass -eq $true -and $e.tests.exit_code -eq 0) 'S1 tests ran + passed (exit 0)'
Ok ($null -ne $e -and $e.commit.committed -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$e.commit.head_sha)) 'S1 commit landed with a head sha'
Ok ($null -ne $e -and (@($e.commit.staged) -contains 'mod/good.ps1') -and (@($e.commit.staged) -contains 'mod/a.txt')) 'S1 commit staged exactly the two files'
Ok ((Head $repo) -ne $h0) 'S1 repo HEAD advanced'
Ok (((& git -C $repo log -1 --format='%b') | Out-String) -match 'Co-Authored-By') 'S1 trailers present in commit body'

# --- S2: sha mismatch -> fail-closed, no commit ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = ('0' * 64) })
    commit = $true; commit_files = @('mod/good.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S2 sha mismatch:"
Ok ($null -ne $e -and $e.ok -eq $false -and $e.sha.ok -eq $false) 'S2 ok=false, sha.ok=false'
Ok ($null -ne $e -and @($e.sha.mismatches).Count -ge 1) 'S2 mismatch recorded'
Ok ($null -ne $e -and $e.commit.committed -eq $false -and $e.commit.reason_skipped -eq 'gate_failed') 'S2 commit skipped (gate_failed)'
Ok ((Head $repo) -eq $h0) 'S2 HEAD unchanged (no commit)'

# --- S3: AST parse failure -> fail-closed ---
$repo = New-Repo
$b = Add-File $repo 'mod/bad.ps1' $BAD_PS
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/bad.ps1'; sha256 = (Sha $b) })
    commit = $true; commit_files = @('mod/bad.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S3 AST failure:"
Ok ($null -ne $e -and $e.ast.ok -eq $false -and @($e.ast.errors).Count -ge 1) 'S3 ast.ok=false with errors'
Ok ($null -ne $e -and $e.ok -eq $false -and $e.commit.committed -eq $false) 'S3 ok=false, no commit'
Ok ((Head $repo) -eq $h0) 'S3 HEAD unchanged'

# --- S4: test command fails -> fail-closed ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = (Sha $g) })
    test_argv = @('{PWSH}', '-NoProfile', '-Command', 'exit 3')
    commit = $true; commit_files = @('mod/good.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S4 test failure:"
Ok ($null -ne $e -and $e.tests.ran -eq $true -and $e.tests.pass -eq $false -and $e.tests.exit_code -eq 3) 'S4 tests ran, failed (exit 3)'
Ok ($null -ne $e -and $e.ok -eq $false -and $e.commit.committed -eq $false) 'S4 ok=false, no commit'
Ok ((Head $repo) -eq $h0) 'S4 HEAD unchanged'

# --- S5: index-not-clean guard (never fold in an unrelated staged file) ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$o = Add-File $repo 'mod/other.txt' "unrelated`n"
& git -C $repo add mod/other.txt | Out-Null    # pre-stage an unrelated file
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = (Sha $g) })
    commit = $true; commit_files = @('mod/good.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S5 index-not-clean guard:"
Ok ($null -ne $e -and $e.commit.committed -eq $false -and ([string]$e.commit.reason_skipped) -match 'index_not_clean') 'S5 refuses commit when an unrelated file is staged'
Ok ((Head $repo) -eq $h0) 'S5 HEAD unchanged (no accidental fold-in)'

# --- S6: NoCommit (gates run, nothing committed) ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = (Sha $g) })
    commit = $true; commit_files = @('mod/good.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in -NoCommit; $e = $r.env
Write-Output "S6 NoCommit switch:"
Ok ($null -ne $e -and $e.commit.requested -eq $false -and $e.commit.committed -eq $false) 'S6 -NoCommit forces commit off'
Ok ($null -ne $e -and $e.ok -eq $true -and $e.sha.ok -eq $true) 'S6 gates still evaluated + green'
Ok ((Head $repo) -eq $h0) 'S6 HEAD unchanged'

# --- S7: orphan process count (informational) ---
$repo = New-Repo
$g = Add-File $repo 'mod/good.ps1' $GOOD_PS
$in = [ordered]@{
    files = @(@{ path = 'mod/good.ps1'; sha256 = (Sha $g) })
    commit = $false
    check_orphans = @('lo-no-such-process-xyz')
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S7 orphan check:"
Ok ($null -ne $e -and (Has $e.orphans 'lo-no-such-process-xyz') -and ([int]$e.orphans.'lo-no-such-process-xyz' -eq 0)) 'S7 orphan count = 0 for a nonexistent process'

# --- S8: missing file -> mismatch(missing), fail-closed ---
$repo = New-Repo
$h0 = Head $repo
$in = [ordered]@{
    files = @(@{ path = 'mod/nope.ps1'; sha256 = ('a' * 64) })
    commit = $true; commit_files = @('mod/nope.ps1'); commit_message = "x`n`n$TRAILERS"
}
$r = Run-DevShip $repo $in; $e = $r.env
Write-Output "S8 missing file:"
Ok ($null -ne $e -and $e.sha.ok -eq $false -and (@($e.sha.mismatches) | Where-Object { $_.reason -eq 'missing' }).Count -ge 1) 'S8 missing file recorded as a mismatch'
Ok ($null -ne $e -and $e.ok -eq $false -and $e.commit.committed -eq $false) 'S8 ok=false, no commit'

Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
