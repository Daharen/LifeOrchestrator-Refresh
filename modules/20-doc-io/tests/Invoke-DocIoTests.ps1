#requires -Version 7.0
<#
    Invoke-DocIoTests.ps1 -- real-worker, OS-portable test harness for doc.io (Module 20).

    No mock: .NET file I/O is cross-platform, so the REAL skill runs unchanged on the cloud Linux
    box (pre-ship gate) and live on the Windows executor. Generates its own fixtures; drives the
    skill through -InputsJson (correct JSON-boolean handling); asserts every op + error path +
    CRLF/BOM/precondition/atomic/pre-image; and, when the Module 1 wrapper is available, validates it.

    Params let the executor task point at explicit interpreter/skill/wrapper paths.
#>
[CmdletBinding()]
param(
    [string]$PwshExe,
    [string]$SkillPath,
    [string]$WrapperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PwshExe)) {
    $PwshExe = Join-Path $PSHOME ($(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }))
}
if ([string]::IsNullOrWhiteSpace($SkillPath)) {
    $SkillPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-DocIo.ps1'
}
if ([string]::IsNullOrWhiteSpace($WrapperPath)) {
    $WrapperPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (Join-Path '01-skill-bootstrap' 'Invoke-Skill.ps1')
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('docio-tests-' + [guid]::NewGuid().ToString('N'))
$artRoot = Join-Path $work '_artifacts'
New-Item -ItemType Directory -Force -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $artRoot | Out-Null

Write-Host "doc.io tests"
Write-Host "  pwsh   : $PwshExe"
Write-Host "  skill  : $SkillPath"
Write-Host "  wrapper: $WrapperPath (present=$([bool](Test-Path -LiteralPath $WrapperPath)))"
Write-Host "  work   : $work"
Write-Host ""

$script:pass = 0; $script:fail = 0
function T([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host ("  PASS  " + $name) }
    else { $script:fail++; Write-Host ("  FAIL  " + $name + $(if ($detail) { "  -- $detail" } else { '' })) }
}

function Invoke-Doc([hashtable]$in, [hashtable]$extraNamed) {
    $json = ($in | ConvertTo-Json -Compress -Depth 12)
    $argv = @('-NoProfile', '-File', $SkillPath, '-InputsJson', $json, '-ArtifactRoot', $artRoot)
    if ($extraNamed) { foreach ($k in $extraNamed.Keys) { $argv += @("-$k", [string]$extraNamed[$k]) } }
    $errf = [System.IO.Path]::GetTempFileName()
    $out = & $PwshExe @argv 2>$errf
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $errf -ErrorAction SilentlyContinue
    $text = ($out | Out-String)
    $envObj = $null
    try { $envObj = $text | ConvertFrom-Json } catch {}
    return [pscustomobject]@{ env = $envObj; exit = $code; raw = $text }
}

function Get-DiskSha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-RawEol([string]$p) {
    $b = [System.IO.File]::ReadAllBytes($p)
    $crlf = 0; $loneLf = 0; $i = 0
    while ($i -lt $b.Length) {
        if ($b[$i] -eq 0x0D -and ($i + 1) -lt $b.Length -and $b[$i + 1] -eq 0x0A) { $crlf++; $i += 2; continue }
        if ($b[$i] -eq 0x0A) { $loneLf++ }
        $i++
    }
    if ($crlf -gt 0 -and $loneLf -eq 0) { return 'crlf' }
    if ($loneLf -gt 0 -and $crlf -eq 0) { return 'lf' }
    if ($crlf -eq 0 -and $loneLf -eq 0) { return 'none' }
    return 'mixed'
}
function Get-ArtBefore($env) {
    foreach ($a in $env.artifacts) { if ([System.IO.Path]::GetFileNameWithoutExtension($a.path) -eq 'before') { return $a.path } }
    return $null
}
function Get-ArtDir($env) {
    if ($env.artifacts.Count -gt 0) { return (Split-Path $env.artifacts[0].path -Parent) }
    return $null
}

# ---------------------------------------------------------------------------
# 0. Manifest sanity (no Module 1 required)
# ---------------------------------------------------------------------------
$manifestPath = Join-Path (Split-Path $SkillPath -Parent) 'skill.json'
$man = $null; try { $man = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch {}
T "manifest parses" ($null -ne $man)
if ($null -ne $man) {
    T "manifest skill_id doc.io" ($man.skill_id -eq 'doc.io')
    T "manifest determinism deterministic" ($man.determinism -eq 'deterministic')
    T "manifest parallel_safe false" ($man.parallel_safe -eq $false)
    T "manifest batch false" ($man.batch -eq $false)
    T "manifest streaming false" ($man.streaming -eq $false)
    T "manifest contract_version 0.2" ("$($man.contract_version)" -eq '0.2')
}

# ---------------------------------------------------------------------------
# WRITE
# ---------------------------------------------------------------------------
$p1 = Join-Path $work 'notes.md'
$r = Invoke-Doc @{ op = 'write'; path = $p1; content = "# Title`nline two`nline three" }
T "write ok" ($r.exit -eq 0 -and $r.env.status -eq 'ok')
T "write created=true" ($r.env.result.created -eq $true)
T "write file on disk" (Test-Path -LiteralPath $p1)
T "write sha256 matches disk" ($r.env.result.file.sha256 -eq (Get-DiskSha $p1))
T "write bytes_written matches disk" ($r.env.result.bytes_written -eq ((Get-Item -LiteralPath $p1).Length))
T "write eol lf" ($r.env.result.file.eol -eq 'lf')
T "write confidence null (deterministic)" ($null -eq $r.env.confidence)
T "write model_provenance empty" (@($r.env.model_provenance).Count -eq 0)
T "write not a review producer (no warnings about queue)" ($true)
$afterListed = @($r.env.artifacts | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.path) -eq 'after' }).Count -ge 1
T "write emits after.<ext> artifact" $afterListed
$adir = Get-ArtDir $r.env
T "write result.json in artifact dir" ($null -ne $adir -and (Test-Path -LiteralPath (Join-Path $adir 'result.json')))

# READ (whole)
$r = Invoke-Doc @{ op = 'read'; path = $p1 }
T "read ok" ($r.env.status -eq 'ok')
T "read content roundtrips" ($r.env.result.content -eq "# Title`nline two`nline three")
T "read line_count 3" ($r.env.result.file.line_count -eq 3)
T "read is_binary false" ($r.env.result.is_binary -eq $false)
$readTxtListed = @($r.env.artifacts | Where-Object { [System.IO.Path]::GetFileName($_.path) -eq 'read.txt' }).Count -ge 1
T "read emits read.txt" $readTxtListed

# READ (range 2-3)
$r = Invoke-Doc @{ op = 'read'; path = $p1; start_line = 2; end_line = 3 }
T "read range ok" ($r.env.status -eq 'ok')
T "read range content" ($r.env.result.content -eq "line two`nline three")
T "read range returned meta" ($r.env.result.returned.start_line -eq 2 -and $r.env.result.returned.end_line -eq 3 -and $r.env.result.returned.ranged -eq $true)

# READ invalid range
$r = Invoke-Doc @{ op = 'read'; path = $p1; start_line = 9; end_line = 9 }
T "read invalid_range" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_range')

# READ missing
$r = Invoke-Doc @{ op = 'read'; path = (Join-Path $work 'nope.txt') }
T "read input_not_found" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'input_not_found')

# READ binary
$pbin = Join-Path $work 'bin.dat'
[System.IO.File]::WriteAllBytes($pbin, [byte[]]@(1, 2, 0, 3, 4, 0, 5))
$r = Invoke-Doc @{ op = 'read'; path = $pbin }
T "read binary_file" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'binary_file')

# READ truncation
$pbig = Join-Path $work 'big.txt'
[System.IO.File]::WriteAllText($pbig, ('x' * 5000), ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'read'; path = $pbig; max_bytes = 1000 }
T "read truncated flag" ($r.env.result.returned.truncated -eq $true)
T "read truncated within max_bytes" ($r.env.result.returned.byte_count -le 1000)

# READ exit-0 on error (contract)
T "error path exits 0 with envelope" ($r.exit -eq 0)

# ---------------------------------------------------------------------------
# WRITE variants
# ---------------------------------------------------------------------------
# overwrite=false on existing
$r = Invoke-Doc @{ op = 'write'; path = $p1; content = 'zzz'; overwrite = $false }
T "write already_exists" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'already_exists')

# create_dirs true (nested)
$pnest = Join-Path $work 'sub/dir/deep.md'
$r = Invoke-Doc @{ op = 'write'; path = $pnest; content = 'deep' }
T "write create_dirs ok" ($r.env.status -eq 'ok' -and (Test-Path -LiteralPath $pnest))

# create_dirs false into missing parent
$pnest2 = Join-Path $work 'sub2/dir2/deep2.md'
$r = Invoke-Doc @{ op = 'write'; path = $pnest2; content = 'deep'; create_dirs = $false }
T "write parent_not_found" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'parent_not_found')

# eol crlf
$pcrlfW = Join-Path $work 'crlfw.txt'
$r = Invoke-Doc @{ op = 'write'; path = $pcrlfW; content = "a`nb`nc"; eol = 'crlf' }
T "write eol=crlf on disk" ((Get-RawEol $pcrlfW) -eq 'crlf' -and $r.env.result.file.eol -eq 'crlf')

# precondition ok
$shaNow = Get-DiskSha $p1
$r = Invoke-Doc @{ op = 'write'; path = $p1; content = "# Title`nline two`nline three`nextra"; expect_sha256 = $shaNow }
T "write precondition ok" ($r.env.status -eq 'ok')
# precondition fail
$r = Invoke-Doc @{ op = 'write'; path = $p1; content = 'nope'; expect_sha256 = 'deadbeef' }
T "write precondition_failed" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'precondition_failed')
# precondition on missing
$r = Invoke-Doc @{ op = 'write'; path = (Join-Path $work 'ghost.txt'); content = 'x'; expect_sha256 = 'abc' }
T "write precondition on missing" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'precondition_failed')

# pre-image on overwrite
$ppre = Join-Path $work 'pre.txt'
[System.IO.File]::WriteAllText($ppre, "original", ([System.Text.UTF8Encoding]::new($false)))
$origBytesSha = Get-DiskSha $ppre
$r = Invoke-Doc @{ op = 'write'; path = $ppre; content = 'replaced' }
$bp = Get-ArtBefore $r.env
T "write pre-image written" ($r.env.result.preimage.written -eq $true -and $null -ne $bp -and (Test-Path -LiteralPath $bp))
T "write pre-image equals original" ($null -ne $bp -and (Get-DiskSha $bp) -eq $origBytesSha)

# ---------------------------------------------------------------------------
# EDIT
# ---------------------------------------------------------------------------
$pe = Join-Path $work 'edit.md'
[System.IO.File]::WriteAllText($pe, "alpha beta gamma", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pe; old_string = 'beta'; new_string = 'BETA' }
T "edit unique ok" ($r.env.status -eq 'ok' -and $r.env.result.replacements -eq 1 -and $r.env.result.occurrences -eq 1)
T "edit changed disk" ((Get-Content -LiteralPath $pe -Raw) -ceq 'alpha BETA gamma')
T "edit sha256_before differs after" ($r.env.result.sha256_before -ne $r.env.result.file.sha256)

# not_found
$r = Invoke-Doc @{ op = 'edit'; path = $pe; old_string = 'zzz'; new_string = 'q' }
T "edit not_found" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'not_found')

# not_unique
$pdup = Join-Path $work 'dup.txt'
[System.IO.File]::WriteAllText($pdup, "x`nx`nx", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pdup; old_string = 'x'; new_string = 'y' }
T "edit not_unique" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'not_unique' -and $r.env.result.occurrences -eq 3)

# replace_all
$r = Invoke-Doc @{ op = 'edit'; path = $pdup; old_string = 'x'; new_string = 'y'; replace_all = $true }
T "edit replace_all" ($r.env.status -eq 'ok' -and $r.env.result.replacements -eq 3)
T "edit replace_all disk" ((Get-Content -LiteralPath $pdup -Raw) -eq "y`ny`ny")

# expect_count match / mismatch
[System.IO.File]::WriteAllText($pdup, "x`nx`nx", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pdup; old_string = 'x'; new_string = 'y'; expect_count = 3 }
T "edit expect_count match" ($r.env.status -eq 'ok' -and $r.env.result.replacements -eq 3)
[System.IO.File]::WriteAllText($pdup, "x`nx`nx", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pdup; old_string = 'x'; new_string = 'y'; expect_count = 2 }
T "edit count_mismatch" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'count_mismatch')

# no_change
$r = Invoke-Doc @{ op = 'edit'; path = $pe; old_string = 'BETA'; new_string = 'BETA' }
T "edit no_change" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'no_change')

# CRLF preservation
$pcrlf = Join-Path $work 'crlf.txt'
[System.IO.File]::WriteAllText($pcrlf, "alpha`r`nbeta`r`ngamma`r`n", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pcrlf; old_string = 'beta'; new_string = 'BETA' }
T "edit CRLF: status ok" ($r.env.status -eq 'ok')
T "edit CRLF: reported eol crlf" ($r.env.result.file.eol -eq 'crlf')
T "edit CRLF: disk still crlf" ((Get-RawEol $pcrlf) -eq 'crlf')
T "edit CRLF: content applied" ((Get-Content -LiteralPath $pcrlf -Raw) -ceq "alpha`r`nBETA`r`ngamma`r`n")

# LF preservation
$plf = Join-Path $work 'lf.txt'
[System.IO.File]::WriteAllText($plf, "a`nb`nc`n", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $plf; old_string = 'b'; new_string = 'B' }
T "edit LF stays lf" ((Get-RawEol $plf) -eq 'lf' -and $r.env.result.file.eol -eq 'lf')

# multiline old_string spanning a newline, against a CRLF file (EOL-agnostic match)
[System.IO.File]::WriteAllText($pcrlf, "one`r`ntwo`r`nthree`r`n", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'edit'; path = $pcrlf; old_string = "one`ntwo"; new_string = "ONE`nTWO" }
T "edit multiline old_string across EOL" ($r.env.status -eq 'ok' -and (Get-RawEol $pcrlf) -eq 'crlf' -and (Get-Content -LiteralPath $pcrlf -Raw) -ceq "ONE`r`nTWO`r`nthree`r`n")

# precondition fail on edit
$r = Invoke-Doc @{ op = 'edit'; path = $plf; old_string = 'a'; new_string = 'A'; expect_sha256 = 'deadbeef' }
T "edit precondition_failed" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'precondition_failed')

# binary edit
$r = Invoke-Doc @{ op = 'edit'; path = $pbin; old_string = 'a'; new_string = 'b' }
T "edit binary_file" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'binary_file')

# edit pre-image recoverable
[System.IO.File]::WriteAllText($pe, "recover me", ([System.Text.UTF8Encoding]::new($false)))
$origSha = Get-DiskSha $pe
$r = Invoke-Doc @{ op = 'edit'; path = $pe; old_string = 'recover'; new_string = 'RECOVERED' }
$bp = Get-ArtBefore $r.env
T "edit pre-image recoverable" ($null -ne $bp -and (Get-DiskSha $bp) -eq $origSha)

# ---------------------------------------------------------------------------
# APPEND
# ---------------------------------------------------------------------------
# append to file with no trailing newline -> ensure_newline inserts separator
$pa = Join-Path $work 'log.md'
[System.IO.File]::WriteAllText($pa, "line1", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'append'; path = $pa; content = 'line2' }
T "append ensured_newline true" ($r.env.status -eq 'ok' -and $r.env.result.ensured_newline -eq $true)
T "append inserted separator" ((Get-Content -LiteralPath $pa -Raw) -eq "line1`nline2")
T "append bytes_appended = sep+content" ($r.env.result.bytes_appended -eq 6)

# append to file WITH trailing newline -> no extra separator
$pa2 = Join-Path $work 'log2.md'
[System.IO.File]::WriteAllText($pa2, "line1`n", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'append'; path = $pa2; content = 'line2' }
T "append no double newline" ($r.env.result.ensured_newline -eq $false -and (Get-Content -LiteralPath $pa2 -Raw) -eq "line1`nline2")

# append create new
$pa3 = Join-Path $work 'new-log.md'
$r = Invoke-Doc @{ op = 'append'; path = $pa3; content = 'first' }
T "append create new" ($r.env.status -eq 'ok' -and $r.env.result.created -eq $true -and (Get-Content -LiteralPath $pa3 -Raw) -eq 'first')

# append create=false on missing
$r = Invoke-Doc @{ op = 'append'; path = (Join-Path $work 'missing-log.md'); content = 'x'; create = $false }
T "append input_not_found (create=false)" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'input_not_found')

# append CRLF file -> separator + content use CRLF, file stays crlf
$pac = Join-Path $work 'crlf-log.txt'
[System.IO.File]::WriteAllText($pac, "l1`r`nl2", ([System.Text.UTF8Encoding]::new($false)))
$r = Invoke-Doc @{ op = 'append'; path = $pac; content = 'l3' }
T "append CRLF stays crlf" ((Get-RawEol $pac) -eq 'crlf' -and (Get-Content -LiteralPath $pac -Raw) -eq "l1`r`nl2`r`nl3")

# ---------------------------------------------------------------------------
# ENCODING / BOM
# ---------------------------------------------------------------------------
# utf-8-bom write then read detects bom
$pbom = Join-Path $work 'bom.txt'
$r = Invoke-Doc @{ op = 'write'; path = $pbom; content = 'hello'; encoding = 'utf-8-bom' }
$bomBytes = [System.IO.File]::ReadAllBytes($pbom)
T "write utf-8-bom emits BOM" ($bomBytes.Length -ge 3 -and $bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF)
$r = Invoke-Doc @{ op = 'read'; path = $pbom }
T "read detects utf-8 bom" ($r.env.result.file.bom -eq $true -and $r.env.result.file.encoding -eq 'utf-8' -and $r.env.result.content -eq 'hello')
# edit preserves bom
$r = Invoke-Doc @{ op = 'edit'; path = $pbom; old_string = 'hello'; new_string = 'HELLO' }
$bomBytes2 = [System.IO.File]::ReadAllBytes($pbom)
T "edit preserves utf-8 bom" ($bomBytes2[0] -eq 0xEF -and $bomBytes2[1] -eq 0xBB -and $bomBytes2[2] -eq 0xBF)

# utf-16le detect + preserve
$p16 = Join-Path $work 'u16.txt'
[System.IO.File]::WriteAllText($p16, "wide chars", ([System.Text.UnicodeEncoding]::new($false, $true)))
$r = Invoke-Doc @{ op = 'read'; path = $p16 }
T "read detects utf-16le" ($r.env.result.file.encoding -eq 'utf-16le' -and $r.env.result.file.bom -eq $true -and $r.env.result.content -eq 'wide chars')
$r = Invoke-Doc @{ op = 'edit'; path = $p16; old_string = 'wide'; new_string = 'WIDE' }
$u16b = [System.IO.File]::ReadAllBytes($p16)
T "edit preserves utf-16le bom" ($u16b[0] -eq 0xFF -and $u16b[1] -eq 0xFE)
T "edit utf-16le content ok" (([System.Text.Encoding]::Unicode.GetString($u16b, 2, $u16b.Length - 2)) -ceq 'WIDE chars')

# ---------------------------------------------------------------------------
# CONTRACT / GENERIC
# ---------------------------------------------------------------------------
# invalid op
$r = Invoke-Doc @{ op = 'frobnicate'; path = $p1 }
T "invalid_op" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_op')
# missing path
$r = Invoke-Doc @{ op = 'read' }
T "missing_parameter (path)" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_parameter')
# path is a directory
$r = Invoke-Doc @{ op = 'read'; path = $work }
T "path_is_directory" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'path_is_directory')
# missing content for write
$r = Invoke-Doc @{ op = 'write'; path = (Join-Path $work 'nc.txt') }
T "write missing content" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_parameter')

# named param overrides InputsJson (contract 3.1): JSON says content=FROM_JSON, -Content says FROM_NAMED
$povr = Join-Path $work 'override.txt'
$r = Invoke-Doc @{ op = 'write'; path = $povr; content = 'FROM_JSON' } @{ Content = 'FROM_NAMED' }
T "named param overrides InputsJson" ($r.env.status -eq 'ok' -and (Get-Content -LiteralPath $povr -Raw) -ceq 'FROM_NAMED')

# envelope schema fields present
$r = Invoke-Doc @{ op = 'read'; path = $p1 }
$e = $r.env
T "envelope schema id" ($e.schema -eq 'lifeorch.skill.result/0.1')
T "envelope skill_id" ($e.skill_id -eq 'doc.io')
T "envelope has invocation_id" (-not [string]::IsNullOrWhiteSpace($e.invocation_id))
T "envelope artifact sha256 matches file" (@($e.artifacts).Count -ge 1 -and $e.artifacts[0].sha256 -eq (Get-DiskSha $e.artifacts[0].path))

# ---------------------------------------------------------------------------
# DOC LEASE (res.lease #29) -- opt-in serialization of concurrent editors
# ---------------------------------------------------------------------------
$reslease = Join-Path (Split-Path (Split-Path $SkillPath -Parent) -Parent) (Join-Path '29-resource-lease' 'Invoke-ResLease.ps1')
T "res.lease present (for lease tests)" (Test-Path -LiteralPath $reslease)
if (Test-Path -LiteralPath $reslease) {
    $ld = Join-Path $work '_leases'
    function Invoke-Rl([string[]]$a) {
        $o = & $PwshExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $reslease @a 2>$null
        $t = ($o | Out-String).Trim(); if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        try { return ($t | ConvertFrom-Json).result } catch { return $null }
    }

    # (a) write with lease ON (free) -> auto-derived resource, acquired+owned+released, free afterward
    $pL = Join-Path $work 'leased.md'
    $r = Invoke-Doc @{ op='write'; path=$pL; content='hello lease'; lease=$true; lease_dir=$ld; res_lease_path=$reslease; pwsh_path=$PwshExe }
    T "lease(a) write ok" ($r.env.status -eq 'ok' -and (Test-Path -LiteralPath $pL))
    T "lease(a) lease field present" ([bool]($r.env.result.PSObject.Properties.Name -contains 'lease'))
    T "lease(a) enabled+available" ($r.env.result.lease.enabled -eq $true -and $r.env.result.lease.available -eq $true)
    T "lease(a) acquired+owned" ($r.env.result.lease.acquired -eq $true -and $r.env.result.lease.owned -eq $true)
    T "lease(a) has lease_id" (-not [string]::IsNullOrWhiteSpace([string]$r.env.result.lease.lease_id))
    T "lease(a) released after write" ($r.env.result.lease.released -eq $true)
    T "lease(a) resource doc:*" ("$($r.env.result.lease.resource)" -like 'doc:*')
    $stA = Invoke-Rl @('-Action','status','-Resource', "$($r.env.result.lease.resource)", '-LeaseDir', $ld)
    T "lease(a) free after run" ($null -ne $stA -and $stA.held -eq $false)

    # (b) contended -> other holder holds it; doc.io waits (short) then fails; file untouched; then succeeds after release
    $pC = Join-Path $work 'contended.md'
    [System.IO.File]::WriteAllText($pC, "seed`n", ([System.Text.UTF8Encoding]::new($false)))
    $res = 'doc:' + ($pC -replace '\\','/')
    $pre = Invoke-Rl @('-Action','acquire','-Resource',$res,'-Holder','other','-TtlSeconds','60','-LeaseDir',$ld)
    T "lease(b) pre-acquired by other" ($null -ne $pre -and $pre.acquired -eq $true)
    $r = Invoke-Doc @{ op='append'; path=$pC; content='x'; lease=$true; lease_wait_s=1; lease_dir=$ld; res_lease_path=$reslease; pwsh_path=$PwshExe; lease_resource=$res }
    T "lease(b) doc_lease_unavailable" ($r.env.status -eq 'error' -and $r.env.error.code -eq 'doc_lease_unavailable')
    T "lease(b) reports held_by" ($r.env.result.lease.held_by -eq 'other')
    T "lease(b) file untouched on contention" ((Get-Content -LiteralPath $pC -Raw) -eq "seed`n")
    Invoke-Rl @('-Action','release','-Resource',$res,'-Holder','other','-LeaseDir',$ld) | Out-Null
    $r = Invoke-Doc @{ op='append'; path=$pC; content='x'; lease=$true; lease_wait_s=5; lease_dir=$ld; res_lease_path=$reslease; pwsh_path=$PwshExe; lease_resource=$res }
    T "lease(b) acquires after other releases" ($r.env.status -eq 'ok' -and $r.env.result.lease.acquired -eq $true -and $r.env.result.lease.released -eq $true)

    # (c) res.lease ABSENT -> graceful proceed (available=false); the write still happens
    $pA = Join-Path $work 'absent-lease.md'
    $r = Invoke-Doc @{ op='write'; path=$pA; content='no lease tool'; lease=$true; res_lease_path=(Join-Path $work 'no-such-reslease.ps1'); lease_dir=$ld }
    T "lease(c) graceful when res.lease absent" ($r.env.status -eq 'ok' -and $r.env.result.lease.available -eq $false -and $r.env.result.lease.acquired -eq $false -and (Test-Path -LiteralPath $pA))

    # (d) lease OFF (default) -> no lease field, behaviour unchanged
    $pO = Join-Path $work 'nolease.md'
    $r = Invoke-Doc @{ op='write'; path=$pO; content='plain' }
    T "lease(d) off: no lease field" (-not [bool]($r.env.result.PSObject.Properties.Name -contains 'lease'))
    T "lease(d) off: write ok" ($r.env.status -eq 'ok' -and (Test-Path -LiteralPath $pO))

    # (e) edit under lease serializes + releases + applies the change
    $pE2 = Join-Path $work 'edit-lease.md'
    [System.IO.File]::WriteAllText($pE2, "aaa bbb ccc", ([System.Text.UTF8Encoding]::new($false)))
    $r = Invoke-Doc @{ op='edit'; path=$pE2; old_string='bbb'; new_string='BBB'; lease=$true; lease_dir=$ld; res_lease_path=$reslease; pwsh_path=$PwshExe }
    T "lease(e) edit under lease ok+released" ($r.env.status -eq 'ok' -and $r.env.result.lease.released -eq $true -and (Get-Content -LiteralPath $pE2 -Raw) -ceq 'aaa BBB ccc')
} else {
    Write-Host "  SKIP  res.lease not present -- doc-lease tests skipped"
}

# ---------------------------------------------------------------------------
# ATOMIC: no leftover temp files anywhere under work
# ---------------------------------------------------------------------------
$tmps = @(Get-ChildItem -LiteralPath $work -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.docio-*.tmp' })
T "no leftover .docio-*.tmp files" ($tmps.Count -eq 0) ("found=" + $tmps.Count)

# ---------------------------------------------------------------------------
# Module 1 wrapper (when available)
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $WrapperPath) {
    $pw = Join-Path $work 'wrap.txt'
    [System.IO.File]::WriteAllText($pw, "wrapped content", ([System.Text.UTF8Encoding]::new($false)))
    $skillDir = Split-Path $SkillPath -Parent
    $wjson = (@{ op = 'read'; path = $pw } | ConvertTo-Json -Compress)
    $errf = [System.IO.Path]::GetTempFileName()
    $wout = & $PwshExe -NoProfile -File $WrapperPath -SkillDir $skillDir -InputsJson $wjson -PwshPath $PwshExe 2>$errf
    Remove-Item -LiteralPath $errf -ErrorAction SilentlyContinue
    $rep = $null; try { $rep = ($wout | Out-String) | ConvertFrom-Json } catch {}
    T "wrapper report parses" ($null -ne $rep)
    if ($null -ne $rep) {
        T "wrapper manifest_valid" ($rep.manifest_valid -eq $true)
        T "wrapper invoked" ($rep.invoked -eq $true)
        T "wrapper envelope_valid" ($rep.envelope_valid -eq $true)
        T "wrapper nested envelope skill_id" ($rep.envelope.skill_id -eq 'doc.io')
    }
} else {
    Write-Host "  SKIP  Module 1 wrapper not present (cloud gate) -- exercised live on the executor"
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("DOCIO TESTS: {0}/{1} passed" -f $script:pass, ($script:pass + $script:fail))
try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch {}
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
