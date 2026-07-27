#!/usr/bin/env pwsh
<#
    Test-FrontierBridge.ps1 -- self-contained gate for Module 31 frontier.bridge.

    Runs the REAL skill as a separate process (no mock -- it is pure file I/O), asserts the
    lifeorch.skill.result/0.1 envelope + the pack/return behaviour + the D-0052 boundary, and prints
    a PASS/FAIL summary. Exit 0 iff every check passes.

    Usage:
      pwsh -File tests/Test-FrontierBridge.ps1 -PwshPath <pwsh> [-WrapperPath <Invoke-Skill.ps1>]

    -PwshPath    pwsh used to launch the skill (default 'pwsh'; the ship gate passes an explicit path).
    -WrapperPath optional Module 1 wrapper; when present the skill is also exercised through it.
#>
[CmdletBinding()]
param(
    [string]$PwshPath = 'pwsh',
    [string]$WrapperPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-FrontierBridge.ps1'
if (-not (Test-Path -LiteralPath $entry)) { Write-Host "FATAL: entrypoint not found: $entry"; exit 1 }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("fbridge-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

$script:pass = 0
$script:fail = 0
function Check {
    param([string]$Name, [bool]$Cond, [string]$Detail = '')
    if ($Cond) { $script:pass++; Write-Host "PASS  $Name" }
    else       { $script:fail++; Write-Host "FAIL  $Name $Detail" }
}

function Run-Skill {
    param([string[]]$SkillArgs)
    $errFile = Join-Path $root ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $out = & $PwshPath -NoProfile -File $entry @SkillArgs 2> $errFile
    $exit = $LASTEXITCODE
    $joined = ($out -join "`n")
    $env = $null
    try { $env = $joined | ConvertFrom-Json } catch { $env = $null }
    return [pscustomobject]@{ exit = $exit; envelope = $env; raw = $joined; stderr = (Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue) }
}

function New-Fixture {
    param([string]$Name)
    $d = Join-Path $root $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

# ---------- fixtures ----------
$proj = New-Fixture 'proj'
[System.IO.File]::WriteAllText((Join-Path $proj 'a.txt'), "hello alpha`nline2`n")
[System.IO.File]::WriteAllText((Join-Path $proj 'b.py'),  "def foo():`n    return 1`n")
[System.IO.File]::WriteAllBytes((Join-Path $proj 'c.bin'), ([byte[]](0,1,2,3,0,9,9)))

$tree = New-Fixture 'tree'
[System.IO.File]::WriteAllText((Join-Path $tree 'top.txt'), "top`n")
$sub = Join-Path $tree 'sub'; New-Item -ItemType Directory -Path $sub -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $sub 'deep.txt'), "deep`n")

$big = New-Fixture 'big'
[System.IO.File]::WriteAllText((Join-Path $big 'small.txt'), "small`n")
[System.IO.File]::WriteAllText((Join-Path $big 'huge.txt'), ('x' * 5000))

$cap = New-Fixture 'cap'
[System.IO.File]::WriteAllText((Join-Path $cap 'one.txt'), ('a' * 3000))
[System.IO.File]::WriteAllText((Join-Path $cap 'two.txt'), ('b' * 3000))

# ================= PACK scenarios =================

# T1 -- folder pack, binary skipped
$ar = Join-Path $root 'ar1'
$r = Run-Skill @('-Action','pack','-Prompt','Review this.','-Question','Bugs?','-Folder',$proj,'-ArtifactRoot',$ar)
Check 'T1 exit 0'            ($r.exit -eq 0) "exit=$($r.exit)"
Check 'T1 envelope parsed'   ($null -ne $r.envelope) "raw=$($r.raw.Substring(0,[Math]::Min(200,$r.raw.Length)))"
if ($null -ne $r.envelope) {
    Check 'T1 status ok'         ($r.envelope.status -eq 'ok')
    Check 'T1 skill_id'          ($r.envelope.skill_id -eq 'frontier.bridge')
    Check 'T1 file_count 2'      ($r.envelope.result.file_count -eq 2) "got $($r.envelope.result.file_count)"
    Check 'T1 skipped 1'         ($r.envelope.result.skipped_count -eq 1)
    Check 'T1 confidence null'   ($null -eq $r.envelope.confidence)
    Check 'T1 provenance empty'  (@($r.envelope.model_provenance).Count -eq 0)
    Check 'T1 diag log'          ($r.envelope.diagnostics.log -eq 'stderr.txt')
    Check 'T1 3 artifacts'       (@($r.envelope.artifacts).Count -eq 3)
    $packPath = $r.envelope.result.pack_path
    Check 'T1 pack exists'       (Test-Path -LiteralPath $packPath)
    if (Test-Path -LiteralPath $packPath) {
        $pc = Get-Content -Raw -LiteralPath $packPath
        Check 'T1 pack has file A content' ($pc -match 'hello alpha')
        Check 'T1 pack has file B content' ($pc -match 'def foo')
        Check 'T1 pack has delimiter'      ($pc -match 'FBRIDGE::' )
        Check 'T1 pack states local-only'  ($pc -match 'no network was contacted')
    }
    Check 'T1 return file exists' (Test-Path -LiteralPath $r.envelope.result.return_file)
    # result.json mirrors stdout
    $rj = Join-Path (Split-Path $packPath -Parent) 'result.json'
    Check 'T1 result.json exists' (Test-Path -LiteralPath $rj)
    if (Test-Path -LiteralPath $rj) {
        $rjo = Get-Content -Raw -LiteralPath $rj | ConvertFrom-Json
        Check 'T1 result.json matches stdout' ($rjo.invocation_id -eq $r.envelope.invocation_id)
    }
    # no stray producer artifact
    $rq = Get-ChildItem -LiteralPath (Split-Path $packPath -Parent) -Filter 'review_queue*' -ErrorAction SilentlyContinue
    Check 'T1 not a review producer' (@($rq).Count -eq 0)
}

# T2 -- glob selects only .py
$r = Run-Skill @('-Action','pack','-Prompt','P','-Paths',(Join-Path $proj '*.py'),'-ArtifactRoot',(Join-Path $root 'ar2'))
Check 'T2 file_count 1 (py glob)' ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 1) "got $($r.envelope.result.file_count)"

# T3 -- folder include filter (*.txt -> a.txt only)
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$proj,'-Include','*.txt','-ArtifactRoot',(Join-Path $root 'ar3'))
Check 'T3 include *.txt -> 1' ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 1) "got $($r.envelope.result.file_count)"

# T4 -- recurse on/off
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$tree,'-Recurse','true','-ArtifactRoot',(Join-Path $root 'ar4a'))
Check 'T4 recurse true -> 2' ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 2) "got $($r.envelope.result.file_count)"
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$tree,'-Recurse','false','-ArtifactRoot',(Join-Path $root 'ar4b'))
Check 'T4 recurse false -> 1' ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 1) "got $($r.envelope.result.file_count)"

# T5 -- max_file_bytes skips the huge file
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$big,'-MaxFileBytes','100','-ArtifactRoot',(Join-Path $root 'ar5'))
$reasons5 = @()
if ($null -ne $r.envelope) { $reasons5 = @($r.envelope.result) ; }
$skReasons = if ($null -ne $r.envelope) { (Get-Content -Raw -LiteralPath (Join-Path (Split-Path $r.envelope.result.pack_path -Parent) 'manifest.json') | ConvertFrom-Json).skipped.reason } else { @() }
Check 'T5 huge skipped too_large' ($skReasons -contains 'too_large') "reasons=$skReasons"
Check 'T5 small included'         ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 1)

# T6 -- max_total_bytes cap
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$cap,'-MaxTotalBytes','4000','-ArtifactRoot',(Join-Path $root 'ar6'))
$sk6 = if ($null -ne $r.envelope) { (Get-Content -Raw -LiteralPath (Join-Path (Split-Path $r.envelope.result.pack_path -Parent) 'manifest.json') | ConvertFrom-Json).skipped.reason } else { @() }
Check 'T6 one file capped'  ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 1) "got $($r.envelope.result.file_count)"
Check 'T6 reason total_cap' ($sk6 -contains 'total_cap') "reasons=$sk6"

# T7 -- no match (selection requested) -> partial
$r = Run-Skill @('-Action','pack','-Prompt','P','-Paths',(Join-Path $proj 'nope-*.zzz'),'-ArtifactRoot',(Join-Path $root 'ar7'))
Check 'T7 partial on no match' ($null -ne $r.envelope -and $r.envelope.status -eq 'partial') "status=$($r.envelope.status)"
Check 'T7 warns no match'      ($null -ne $r.envelope -and (($r.envelope.warnings -join ' ') -match 'no files matched'))

# T8 -- prompt-only pack (no selection)
$r = Run-Skill @('-Action','pack','-Prompt','Just a question.','-Question','What is 2+2?','-ArtifactRoot',(Join-Path $root 'ar8'))
Check 'T8 prompt-only ok'   ($null -ne $r.envelope -and $r.envelope.status -eq 'ok')
Check 'T8 zero files'       ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 0)
Check 'T8 warns prompt-only' ($null -ne $r.envelope -and (($r.envelope.warnings -join ' ') -match 'prompt-only'))

# T9 -- missing prompt -> error, exit 0
$r = Run-Skill @('-Action','pack','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar9'))
Check 'T9 exit 0 on logical error' ($r.exit -eq 0)
Check 'T9 status error'            ($null -ne $r.envelope -and $r.envelope.status -eq 'error')
Check 'T9 code missing_input'      ($null -ne $r.envelope -and $r.envelope.error.code -eq 'missing_input')

# ================= READ-RETURN scenarios =================

# Build a pack to obtain a return file, then populate it.
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar10'))
$rf = $r.envelope.result.return_file
$existing = Get-Content -Raw -LiteralPath $rf
[System.IO.File]::WriteAllText($rf, ($existing + "`nThis is the model answer line.`nSecond line."))
$r = Run-Skill @('-Action','read-return','-ReturnFile',$rf,'-ArtifactRoot',(Join-Path $root 'ar10b'))
Check 'T10 read-return ok'      ($null -ne $r.envelope -and $r.envelope.status -eq 'ok')
Check 'T10 captured true'       ($null -ne $r.envelope -and $r.envelope.result.captured -eq $true)
Check 'T10 content present'     ($null -ne $r.envelope -and ($r.envelope.result.content -match 'model answer line'))
Check 'T10 no stub in content'  ($null -ne $r.envelope -and -not ($r.envelope.result.content -match 'RETURN FILE'))
Check 'T10 sha present'         ($null -ne $r.envelope -and $r.envelope.result.sha256.Length -eq 64)

# T11 -- empty return (stub only) -> partial, captured false
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar11'))
$rf2 = $r.envelope.result.return_file
$r = Run-Skill @('-Action','read-return','-ReturnFile',$rf2,'-ArtifactRoot',(Join-Path $root 'ar11b'))
Check 'T11 empty -> partial'    ($null -ne $r.envelope -and $r.envelope.status -eq 'partial')
Check 'T11 captured false'      ($null -ne $r.envelope -and $r.envelope.result.captured -eq $false)

# T12 -- read-return missing arg / missing file
$r = Run-Skill @('-Action','read-return','-ArtifactRoot',(Join-Path $root 'ar12'))
Check 'T12 missing return_file' ($null -ne $r.envelope -and $r.envelope.error.code -eq 'missing_input')
$r = Run-Skill @('-Action','read-return','-ReturnFile',(Join-Path $root 'does-not-exist.md'),'-ArtifactRoot',(Join-Path $root 'ar12b'))
Check 'T12 not_found'           ($null -ne $r.envelope -and $r.envelope.error.code -eq 'not_found')

# ================= contract / boundary =================

# T13 -- InputsJson equivalence + named override
$ij = '{"prompt":"FROM_JSON","folder":"' + ($proj -replace '\\','\\\\') + '"}'
$r = Run-Skill @('-InputsJson',$ij,'-ArtifactRoot',(Join-Path $root 'ar13'))
Check 'T13 InputsJson pack ok'  ($null -ne $r.envelope -and $r.envelope.result.file_count -eq 2) "got $($r.envelope.result.file_count)"
$pj = Get-Content -Raw -LiteralPath $r.envelope.result.pack_path
Check 'T13 uses json prompt'    ($pj -match 'FROM_JSON')
# named overrides json key
$r = Run-Skill @('-InputsJson','{"prompt":"FROM_JSON"}','-Prompt','FROM_NAMED','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar13b'))
$pj2 = Get-Content -Raw -LiteralPath $r.envelope.result.pack_path
Check 'T13 named overrides json' (($pj2 -match 'FROM_NAMED') -and -not ($pj2 -match 'FROM_JSON'))

# T14 -- determinism: same inputs -> same digest + same manifest file set
$rA = Run-Skill @('-Action','pack','-Prompt','Deterministic','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar14a'))
$rB = Run-Skill @('-Action','pack','-Prompt','Deterministic','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar14b'))
Check 'T14 inputs_digest stable' ($rA.envelope.inputs_digest -eq $rB.envelope.inputs_digest)
$mA = Get-Content -Raw -LiteralPath (Join-Path (Split-Path $rA.envelope.result.pack_path -Parent) 'manifest.json') | ConvertFrom-Json
$mB = Get-Content -Raw -LiteralPath (Join-Path (Split-Path $rB.envelope.result.pack_path -Parent) 'manifest.json') | ConvertFrom-Json
$shaA = ($mA.files.sha256 -join ',')
$shaB = ($mB.files.sha256 -join ',')
Check 'T14 same file shas + order' ($shaA -eq $shaB -and $shaA.Length -gt 0)

# T15 -- NO-NETWORK static assertion on the entrypoint source (D-0052 boundary)
$src = Get-Content -Raw -LiteralPath $entry
$forbidden = @('Invoke-WebRequest','Invoke-RestMethod','System.Net.WebClient','New-Object Net.WebClient',
               'Net.Sockets','Start-BitsTransfer','System.Net.Http','HttpClient','[System.Net.Http','Net.HttpWebRequest',
               'wget ','curl ')
$hits = @()
foreach ($f in $forbidden) { if ($src -match [regex]::Escape($f)) { $hits += $f } }
Check 'T15 no network cmdlets in source' (@($hits).Count -eq 0) "hits=$($hits -join ',')"

# T16 -- envelope schema completeness
$r = Run-Skill @('-Action','pack','-Prompt','P','-Folder',$proj,'-ArtifactRoot',(Join-Path $root 'ar16'))
$req = @('schema','skill_id','skill_version','contract_version','invocation_id','status','started_at_utc',
         'finished_at_utc','duration_ms','inputs_digest','result','confidence','artifacts','model_provenance',
         'diagnostics','warnings','error')
$missing = @()
$names = $r.envelope.PSObject.Properties.Name
foreach ($k in $req) { if ($names -notcontains $k) { $missing += $k } }
Check 'T16 envelope has all fields' (@($missing).Count -eq 0) "missing=$($missing -join ',')"
Check 'T16 schema id'               ($r.envelope.schema -eq 'lifeorch.skill.result/0.1')
Check 'T16 inputs_digest sha form'  ($r.envelope.inputs_digest -match '^sha256:[0-9a-f]{64}$')

# T17 -- skill.json manifest self-check
$mf = Join-Path (Split-Path $PSScriptRoot -Parent) 'skill.json'
Check 'T17 skill.json exists' (Test-Path -LiteralPath $mf)
if (Test-Path -LiteralPath $mf) {
    $m = Get-Content -Raw -LiteralPath $mf | ConvertFrom-Json
    Check 'T17 skill_id'          ($m.skill_id -eq 'frontier.bridge')
    Check 'T17 deterministic'     ($m.determinism -eq 'deterministic')
    Check 'T17 parallel_safe'     ($m.parallel_safe -eq $true)
    Check 'T17 batch false'       ($m.batch -eq $false)
    Check 'T17 streaming false'   ($m.streaming -eq $false)
    Check 'T17 network false'     ($m.requirements.network -eq $false)
    Check 'T17 entrypoint'        ($m.invocation.entrypoint -eq 'Invoke-FrontierBridge.ps1')
    $exDir = Split-Path $PSScriptRoot -Parent
    Check 'T17 example inv exists' (Test-Path -LiteralPath (Join-Path $exDir $m.example_invocation_file))
    Check 'T17 example res exists' (Test-Path -LiteralPath (Join-Path $exDir $m.example_result_file))
}

# T18 -- optional: run through the Module 1 wrapper if provided
if ($WrapperPath -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path $PSScriptRoot -Parent
    $wij = '{"action":"pack","prompt":"via wrapper","folder":"' + ($proj -replace '\\','\\\\') + '"}'
    $wout = & $PwshPath -NoProfile -File $WrapperPath -SkillDir $skillDir -InputsJson $wij 2> (Join-Path $root 'wrap.err')
    $wrep = $null; try { $wrep = ($wout -join "`n") | ConvertFrom-Json } catch {}
    Check 'T18 wrapper manifest valid' ($null -ne $wrep -and $wrep.manifest_valid -eq $true) "$($wrep | ConvertTo-Json -Depth 4)"
    Check 'T18 wrapper envelope valid' ($null -ne $wrep -and $wrep.envelope_valid -eq $true)
} else {
    Write-Host "SKIP  T18 wrapper (no -WrapperPath; exercised on the live box gate)"
}

# ---------- summary ----------
Write-Host ""
Write-Host ("RESULT  pass={0}  fail={1}  total={2}" -f $script:pass, $script:fail, ($script:pass + $script:fail))
try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
