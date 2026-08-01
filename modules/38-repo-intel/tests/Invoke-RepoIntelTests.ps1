#requires -Version 7.0
<#
  Invoke-RepoIntelTests.ps1 -- tests for repo.intel (Module 38).

  Real-worker & OS-portable (mirrors artifact.search #36 / image.util #15, NOT a mock): the stdlib-only
  Python worker (repo_intel.py) is cross-platform, so the harness runs the REAL Invoke-RepoIntel.ps1 -> the
  REAL repo_intel.py under a resolved python. The SAME harness is the cloud pre-ship gate AND the live
  Windows/executor gate. It uses the committed fixtures/repo, copies it to a temp dir to inject malformed +
  binary files (parse-failure / exclusion surfacing), and indexes a bounded slice of the REAL repo
  (../../modules + ../../core-docs when present) under a file budget.

  -PythonPath <python>  : interpreter to use (stdlib ast/json/hashlib). If omitted, resolved.
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
        & $exe -c "import ast,json,hashlib,re" 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}

if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) { $PwshPath = (Get-Process -Id $PID).Path }
$entry = Join-Path $SkillDir 'Invoke-RepoIntel.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m38-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$fixtureRepo = Join-Path $SkillDir 'fixtures/repo'

Write-Host "=== repo.intel tests ==="
Write-Host "skill=$entry"

# --- resolve python ---
if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    foreach ($c in @('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe',
                     'python3','python','py')) {
        $cc = $c
        if ($c -notmatch '[\\/]') { try { $w = & where.exe $c 2>$null; if ($w) { $cc = (@([string[]]$w))[0].Trim() } } catch { } }
        if (Test-Python $cc) { $PythonPath = $cc; break }
    }
}
if ([string]::IsNullOrWhiteSpace($PythonPath) -or -not (Test-Python $PythonPath)) {
    Write-Host "  [FAIL] no python with stdlib ast/json/hashlib found (set -PythonPath)"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}
Write-Host "python=$PythonPath"
if (-not (Test-Path -LiteralPath $fixtureRepo -PathType Container)) {
    Write-Host "  [FAIL] fixtures/repo missing at $fixtureRepo"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}

function Run-RI([hashtable]$inp) {
    if (-not $inp.ContainsKey('python_path')) { $inp['python_path'] = $PythonPath }
    $j = ($inp | ConvertTo-Json -Compress -Depth 30)
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
function Payload($r) { if ($null -ne $r.env -and (Has $r.env 'result')) { return $r.env.result } return $null }
function ArtifactPath($r, [string]$suffix) {
    foreach ($a in @($r.env.artifacts)) { if ([string]$a.path -match ([regex]::Escape($suffix) + '$')) { return [string]$a.path } }
    return $null
}

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=deterministic' ($man.determinism -eq 'deterministic')
Check 'manifest skill_id=repo.intel' ($man.skill_id -eq 'repo.intel')
Check 'manifest version=0.1.0' ($man.version -eq '0.1.0')
Check 'manifest parallel_safe=true & batch=false' (($man.parallel_safe -eq $true) -and ($man.batch -eq $false))

# ---------- 2) index the bundled fixture repo ----------
$r = Run-RI @{ op='index'; root=$fixtureRepo; namespace='fixture' }
Check 'index: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'index: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'index: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'index: confidence null (deterministic)' ($null -ne $e -and $null -eq $e.confidence)
Check 'index: model_provenance empty' ($null -ne $e -and @($e.model_provenance).Count -eq 0)
$ix = Payload $r
Check 'index: >=4 record_kinds' ($null -ne $ix -and @($ix.record_kinds).Count -ge 4) "kinds=$(@($ix.record_kinds) -join ',')"
foreach ($k in @('symbol','relationship','skill','summary','entity')) {
    Check "index: kind '$k' present" (@($ix.record_kinds) -contains $k)
}
Check 'index: validation.ok true' ($null -ne $ix -and [bool]$ix.validation.ok) "errors=$($ix.validation.errors -join '; ')"
Check 'index: parse_failures==0 on clean fixture' ([int]$ix.parse_failure_count -eq 0) "pf=$($ix.parse_failure_count)"
Check 'index: records_digest is 64 hex' ([string]$ix.records_digest -match '^[0-9a-f]{64}$') "digest=$($ix.records_digest)"
Check 'index: >=1 symbol' ([int]$ix.record_counts_by_kind.symbol -ge 1)
Check 'index: >=1 skill' ([int]$ix.record_counts_by_kind.skill -ge 1)
$digest1 = [string]$ix.records_digest
# edge summary: every edge resolved internally or external (no unresolved -> validation.ok already asserts)
Check 'index: edge_summary present (total>0)' ($null -ne $ix.edge_summary -and [int]$ix.edge_summary.total -gt 0) "edges=$($ix.edge_summary | ConvertTo-Json -Compress)"
# artifacts include records.jsonl + ingest_records.json with matching sha256
$rjl = ArtifactPath $r 'records.jsonl'
Check 'index: artifacts include records.jsonl' ($null -ne $rjl)
$rjlArt = @($e.artifacts | Where-Object { [string]$_.path -match 'records\.jsonl$' })[0]
Check 'index: records.jsonl sha256 matches file' ($null -ne $rjlArt -and (Get-Sha256HexFile ([string]$rjlArt.path)) -eq [string]$rjlArt.sha256)
$ingP = ArtifactPath $r 'ingest_records.json'
Check 'index: ingest_records.json emitted' ($null -ne $ingP)
if ($null -ne $ingP) {
    $ingObj = (Get-Content -LiteralPath $ingP -Raw) | ConvertFrom-Json
    Check 'ingest_records: shape {schema,namespace,records[]}' ((Has $ingObj 'schema') -and (Has $ingObj 'namespace') -and (Has $ingObj 'records') -and [int]$ingObj.record_count -eq @($ingObj.records).Count)
    $r0 = @($ingObj.records)[0]
    Check 'ingest_records: record carries s1 fields' ((Has $r0 'record_id') -and (Has $r0 'record_version_id') -and (Has $r0 'record_kind') -and (Has $r0 'content_hash') -and (Has $r0 'parser_fingerprint') -and (Has $r0 'parent_edges') -and (Has $r0 'chunker_fingerprint'))
    Check 'ingest_records: chunker_fingerprint is null (typed record not chunk)' ($null -eq $r0.chunker_fingerprint)
}

# ---------- 3) deterministic re-index (byte-identical records.jsonl + identical digest) ----------
$r2 = Run-RI @{ op='index'; root=$fixtureRepo; namespace='fixture' }
$ix2 = Payload $r2
Check 'deterministic: records_digest identical across runs' ([string]$ix2.records_digest -eq $digest1) "d2=$($ix2.records_digest)"
$rjl2 = ArtifactPath $r2 'records.jsonl'
Check 'deterministic: records.jsonl BYTE-identical across runs' ((Get-Sha256HexFile $rjl) -eq (Get-Sha256HexFile $rjl2)) "a=$(Get-Sha256HexFile $rjl) b=$(Get-Sha256HexFile $rjl2)"
$man1 = ArtifactPath $r 'index_manifest.json'; $man2 = ArtifactPath $r2 'index_manifest.json'
Check 'deterministic: index_manifest.json BYTE-identical' ((Get-Sha256HexFile $man1) -eq (Get-Sha256HexFile $man2))

# ---------- 4) provenance: a symbol span slices back to the source containing the symbol name ----------
$recs = @(Get-Content -LiteralPath $rjl | ForEach-Object { $_ | ConvertFrom-Json })
$sym = @($recs | Where-Object { $_.record_kind -eq 'symbol' -and $_.payload.name -eq 'Get-Thing' })[0]
Check 'provenance: Get-Thing symbol emitted' ($null -ne $sym)
if ($null -ne $sym) {
    $srcFile = Join-Path $fixtureRepo ([string]$sym.source_path)
    $raw = [System.IO.File]::ReadAllBytes($srcFile)
    $slice = $raw[([int]$sym.source_span.start)..(([int]$sym.source_span.end)-1)]
    $sliceText = $utf8.GetString($slice)
    Check 'provenance: symbol span slice contains the symbol name' ($sliceText -match 'Get-Thing') "slice=$($sliceText.Trim())"
    Check 'provenance: symbol carries source_version_id + parser_fingerprint' ((Has $sym 'source_version_id') -and ($null -ne $sym.source_version_id) -and ([string]$sym.parser_fingerprint -match 'pwsh'))
}
# file entity content_hash == sha256 of the file
$feHelper = @($recs | Where-Object { $_.record_kind -eq 'entity' -and $_.payload.entity_type -eq 'file' -and ([string]$_.payload.path) -match 'Helper\.psm1$' })[0]
if ($null -ne $feHelper) {
    $hf = Join-Path $fixtureRepo ([string]$feHelper.payload.path)
    Check 'provenance: file entity content_hash == sha256(file)' ([string]$feHelper.payload.content_hash -eq (Get-Sha256HexFile $hf))
}

# ---------- 5) relationships: resolvable import + external import + test<->module + schema producer ----------
$rels = @($recs | Where-Object { $_.record_kind -eq 'relationship' })
$imp = @($rels | Where-Object { $_.payload.relationship_type -eq 'imports' })
Check 'rel: a resolvable import resolves in-corpus (dot-source Helper.psm1)' (@($imp | Where-Object { (-not $_.payload.external) -and ([string]$_.payload.to) -match 'Helper\.psm1$' }).Count -ge 1)
Check 'rel: an external import is flagged external (ExternalHelper/os/Pester)' (@($imp | Where-Object { $_.payload.external -eq $true }).Count -ge 1)
Check 'rel: test<->module edge present' (@($rels | Where-Object { $_.payload.relationship_type -eq 'tests' }).Count -ge 1)
Check 'rel: schema producer edge present' (@($rels | Where-Object { $_.payload.relationship_type -eq 'produces_schema' }).Count -ge 1)
Check 'rel: file->module (in_module) edges present' (@($rels | Where-Object { $_.payload.relationship_type -eq 'in_module' }).Count -ge 1)

# ---------- 6) markdown: fenced pseudo-heading NOT a section; breadcrumbs correct ----------
$secs = @($recs | Where-Object { $_.record_kind -eq 'summary' -and $_.payload.summary_type -eq 'markdown_section' })
Check 'md: sections emitted' (@($secs).Count -ge 3)
Check 'md: fenced "## Not A Heading" did NOT become a section' (@($secs | Where-Object { ([string]$_.payload.heading) -eq 'Not A Heading' }).Count -eq 0)
Check 'md: nested breadcrumb present (Guide > Setup > Detailed Steps)' (@($secs | Where-Object { ([string]$_.payload.section_path) -eq 'Guide > Setup > Detailed Steps' }).Count -eq 1)

# ---------- 7) validate op on the emitted records.jsonl ----------
$rv = Run-RI @{ op='validate'; records_path=$rjl }
Check 'validate: exit 0 + envelope valid' ($rv.exit -eq 0 -and [bool](Test-SkillResultEnvelope -Json $rv.raw).valid)
$vp = Payload $rv
Check 'validate: ok=true on clean records' ($null -ne $vp -and [bool]$vp.validation.ok) "errors=$($vp.validation.errors -join '; ')"
Check 'validate: edge_summary external are declared refs only' ($null -ne $vp.edge_summary)

# ---------- 8) tamper detection: corrupt a record -> validate ok=false ----------
$tamperFile = Join-Path $tmpRoot 'tampered.jsonl'
$lines = @(Get-Content -LiteralPath $rjl)
$obj0 = $lines[0] | ConvertFrom-Json
$obj0.content_hash = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
$lines[0] = ($obj0 | ConvertTo-Json -Compress -Depth 30)
[System.IO.File]::WriteAllLines($tamperFile, $lines, $utf8)
$rt = Run-RI @{ op='validate'; records_path=$tamperFile }
$tp = Payload $rt
Check 'validate: tampered content_hash is DETECTED (ok=false)' ($null -ne $tp -and (-not [bool]$tp.validation.ok))

# ---------- 9) parse-failure surfacing + exclusion (inject into a temp copy) ----------
$mut = Join-Path $tmpRoot 'mutrepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $mut -Recurse -Force
[System.IO.File]::WriteAllBytes((Join-Path $mut 'blob.bin'), [byte[]](0,1,2,66,73,78,255,254))
[System.IO.File]::WriteAllText((Join-Path $mut 'modules/50-sample/data/broken.json'), "{ `"bad`": [1,2, }", $utf8)
[System.IO.File]::WriteAllText((Join-Path $mut 'modules/50-sample/src_broken.py'), "def oops(`n    return 1`n", $utf8)
[System.IO.File]::WriteAllBytes((Join-Path $mut 'notes_bad.txt'), [byte[]](103,111,111,100,32,255,254,32,98,97,100))
$rm = Run-RI @{ op='index'; root=$mut; namespace='mut' }
$mp = Payload $rm
Check 'parse-failure: status partial + warnings' ($rm.env.status -eq 'partial' -and @($rm.env.warnings).Count -ge 1)
Check 'parse-failure: >=3 surfaced (json+py+utf8)' ([int]$mp.parse_failure_count -ge 3) "pf=$($mp.parse_failure_count)"
$pfreasons = @($mp.parse_failures | ForEach-Object { [string]$_.reason })
Check 'parse-failure: invalid_json surfaced' ($pfreasons -contains 'invalid_json')
Check 'parse-failure: python_syntax_error surfaced' ($pfreasons -contains 'python_syntax_error')
Check 'parse-failure: not_utf8 surfaced' ($pfreasons -contains 'not_utf8')
Check 'exclusion: blob.bin excluded (excluded_count>=1)' ([int]$mp.excluded_count -ge 1)
$invP = ArtifactPath $rm 'inventory.json'
$invObj = (Get-Content -LiteralPath $invP -Raw) | ConvertFrom-Json
Check 'exclusion: blob.bin NOT in inventory' (@($invObj.files | Where-Object { ([string]$_.path) -match 'blob\.bin$' }).Count -eq 0)
Check 'parse-failure: validation still ok (records for good files emitted)' ([bool]$mp.validation.ok)

# ---------- 10) bounded REAL slice (../../modules + ../../core-docs under a budget) ----------
$realRoots = @()
foreach ($rr in @('..\..\modules', '..\..\core-docs')) {
    $rp = Join-Path $SkillDir $rr
    if (Test-Path -LiteralPath $rp -PathType Container) {
        $cnt = @(Get-ChildItem -LiteralPath $rp -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).Count
        if ($cnt -ge 1) { $realRoots += (Resolve-Path -LiteralPath $rp).Path }
    }
}
if ($realRoots.Count -ge 1) {
    $rr1 = Run-RI @{ op='index'; roots=$realRoots; namespace='life-orchestrator'; file_budget=30 }
    $rip = Payload $rr1
    Check 'real-slice: index ok + validation ok' ($rr1.exit -eq 0 -and $null -ne $rip -and [bool]$rip.validation.ok) "err=$($rr1.err) verr=$($rip.validation.errors -join '; ')"
    Check 'real-slice: records emitted (>0) with >=3 kinds' ($null -ne $rip -and [int]$rip.total_records -gt 0 -and @($rip.record_kinds).Count -ge 3) "records=$($rip.total_records) kinds=$(@($rip.record_kinds) -join ',')"
    Check 'real-slice: file_count > 0 (budget-bounded)' ([int]$rip.file_count -gt 0)
    # deterministic re-run of the real slice on the same machine
    $rr2 = Run-RI @{ op='index'; roots=$realRoots; namespace='life-orchestrator'; file_budget=30 }
    $rip2 = Payload $rr2
    Check 'real-slice: re-index digest identical (deterministic)' ([string]$rip2.records_digest -eq [string]$rip.records_digest) "d1=$($rip.records_digest) d2=$($rip2.records_digest)"
} else {
    Check 'real-slice: [skipped: no ../../modules or ../../core-docs in this tree]' $true
}

# ---------- 11) error paths ----------
$r = Run-RI @{ op='index' }
Check 'error: missing_root when no root/roots' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_root')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-RI @{ op='index'; root=(Join-Path $tmpRoot 'no-such-dir') }
Check 'error: root_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'root_not_found')
$r = Run-RI @{ op='frobnicate' }
Check 'error: invalid_op' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_op')
$r = Run-RI @{ op='validate'; records_path=(Join-Path $tmpRoot 'missing.jsonl') }
Check 'error: records_not_found (validate missing file)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'records_not_found')

# ---------- 12) Module 1 generic wrapper ----------
$wrapInp = [ordered]@{ op='index'; root=$fixtureRepo; namespace='fixture'; python_path=$PythonPath }
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
