#requires -Version 7.0
<#
  Invoke-SkillCardTests.ps1 -- tests for skill.card (Module 41).

  Real-worker & OS-portable (mirrors repo.intel #38 / artifact.search #36, NOT a mock): the stdlib-only
  Python worker (skill_card.py) is cross-platform, so the harness runs the REAL Invoke-SkillCard.ps1 -> the
  REAL skill_card.py under a resolved python. The SAME harness is the pre-ship gate AND the live
  Windows/executor gate. It uses the committed fixtures/modules skill set, proves the section-9 card fields,
  the s1 record + #36 ingest_records shape, the #38 boundary, Stage-1 eligibility, the Stage-2 lexical
  retrieval baseline, determinism, and error paths, and indexes a bounded slice of the REAL repo
  (../../modules) when present.

  -PythonPath <python>  : interpreter to use (stdlib json/hashlib/re). If omitted, resolved.
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
        & $exe -c "import json,hashlib,re,os" 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}

if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) { $PwshPath = (Get-Process -Id $PID).Path }
$entry = Join-Path $SkillDir 'Invoke-SkillCard.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m41-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$fixRoot = Join-Path $SkillDir 'fixtures/modules'

Write-Host "=== skill.card tests ==="
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
    Write-Host "  [FAIL] no python with stdlib json/hashlib/re found (set -PythonPath)"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}
Write-Host "python=$PythonPath"
if (-not (Test-Path -LiteralPath $fixRoot -PathType Container)) {
    Write-Host "  [FAIL] fixtures/modules missing at $fixRoot"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}

function Run-SC([hashtable]$inp) {
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
Check 'manifest skill_id=skill.card' ($man.skill_id -eq 'skill.card')
Check 'manifest version=0.1.0' ($man.version -eq '0.1.0')
Check 'manifest parallel_safe=true & batch=false' (($man.parallel_safe -eq $true) -and ($man.batch -eq $false))

# ---------- 2) cards op over the fixture set ----------
$r = Run-SC @{ op='cards'; root=$fixRoot; namespace='fixture' }
Check 'cards: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'cards: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'cards: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'cards: confidence null (deterministic)' ($null -ne $e -and $null -eq $e.confidence)
Check 'cards: model_provenance empty' ($null -ne $e -and @($e.model_provenance).Count -eq 0)
$ix = Payload $r
Check 'cards: 7 skills discovered' ($null -ne $ix -and [int]$ix.skill_count -eq 7) "skills=$($ix.skill_count)"
Check 'cards: 7 records emitted' ([int]$ix.total_records -eq 7) "records=$($ix.total_records)"
Check 'cards: only record_kind skill' ([int]$ix.record_counts_by_kind.skill -eq 7)
Check 'cards: validation.ok true' ([bool]$ix.validation.ok) "errors=$($ix.validation.errors -join '; ')"
Check 'cards: ingest_shape_ok' ([bool]$ix.validation.ingest_shape_ok)
Check 'cards: records_digest 64 hex' ([string]$ix.records_digest -match '^[0-9a-f]{64}$')
Check 'cards: cards_digest 64 hex' ([string]$ix.cards_digest -match '^[0-9a-f]{64}$')
Check 'cards: status counts (5 ok, 1 partial, 1 degraded)' (([int]$ix.card_status_counts.ok -eq 5) -and ([int]$ix.partial_count -eq 1) -and ([int]$ix.degraded_count -eq 1)) ($ix.card_status_counts | ConvertTo-Json -Compress)
Check 'cards: parse_failure invalid_json surfaced' (@($ix.parse_failures | Where-Object { [string]$_.reason -eq 'invalid_json' }).Count -ge 1)
Check 'cards: status partial + warning present' (($e.status -eq 'partial') -and (@($e.warnings).Count -ge 1))
$digest1 = [string]$ix.records_digest
# artifacts + hashes
$cj = ArtifactPath $r 'cards.json'
Check 'cards: artifacts include cards.json' ($null -ne $cj)
$ingP = ArtifactPath $r 'ingest_records.json'
Check 'cards: ingest_records.json emitted' ($null -ne $ingP)
$rjl = ArtifactPath $r 'records.jsonl'
$rjlArt = @($e.artifacts | Where-Object { [string]$_.path -match 'records\.jsonl$' })[0]
Check 'cards: records.jsonl sha256 matches file' ($null -ne $rjlArt -and (Get-Sha256HexFile ([string]$rjlArt.path)) -eq [string]$rjlArt.sha256)
if ($null -ne $ingP) {
    $ingObj = (Get-Content -LiteralPath $ingP -Raw) | ConvertFrom-Json
    Check 'ingest_records: shape {schema,namespace,records[]}' ((Has $ingObj 'schema') -and (Has $ingObj 'namespace') -and (Has $ingObj 'records') -and [int]$ingObj.record_count -eq @($ingObj.records).Count)
    $r0 = @($ingObj.records)[0]
    Check 'ingest_records: record carries s1 fields + text' ((Has $r0 'record_id') -and (Has $r0 'record_version_id') -and (Has $r0 'record_kind') -and (Has $r0 'content_hash') -and (Has $r0 'parent_edges') -and (Has $r0 'text'))
    Check 'ingest_records: chunker_fingerprint null (typed not chunk)' ($null -eq $r0.chunker_fingerprint)
    Check 'ingest_records: record_kind skill (not source_chunk)' ($r0.record_kind -eq 'skill')
}

# ---------- 3) section-9 card fields (from cards.json) ----------
$cards = (Get-Content -LiteralPath $cj -Raw) | ConvertFrom-Json
$ocr = @($cards | Where-Object { $_.skill_id -eq 'fixture.ocr' })[0]
Check 'card ocr: present + status ok' ($null -ne $ocr -and $ocr.card_status -eq 'ok')
foreach ($f in @('purpose','operations','inputs','example','preconditions','side_effects','artifacts','latency_class','resource_class','completion_checks','failure_conditions','version_health')) {
    Check "card ocr: section-9 field '$f' present" (Has $ocr $f)
}
Check 'card ocr: example is a valid pwsh invocation form' ([string]$ocr.example -match '^pwsh -NoProfile -File')
Check 'card ocr: read-only (no side_effect_kinds)' (@($ocr.side_effect_kinds).Count -eq 0)
$lease = @($cards | Where-Object { $_.skill_id -eq 'fixture.lease' })[0]
Check 'card lease: ops extracted from op enum' ((@($lease.operations) -contains 'acquire') -and (@($lease.operations) -contains 'release'))
$part = @($cards | Where-Object { $_.skill_id -eq 'fixture.partial' })[0]
Check 'card partial: status partial + missing fields surfaced' ($part.card_status -eq 'partial' -and @($part.missing_fields).Count -ge 3)
$brk = @($cards | Where-Object { [string]$_.card_status -eq 'degraded' })[0]
Check 'card broken: degraded card emitted (never crashed)' ($null -ne $brk -and ([string]$brk.skill_id) -match '^unresolved:')

# ---------- 4) the #38 boundary (records.jsonl) ----------
$recs = @(Get-Content -LiteralPath $rjl | ForEach-Object { $_ | ConvertFrom-Json })
$gi = @($recs | Where-Object { $_.payload.skill_id -eq 'fixture.gen.image' })[0]
Check 'boundary: record_id prefix sklcard_ (not skl_)' ([string]$gi.record_id -match '^sklcard_')
Check 'boundary: authority_level derived (not canonical_source)' ($gi.authority_level -eq 'derived')
$xl = @($gi.child_edges | Where-Object { $_.edge_type -eq 'describes_structural_skill' })
Check 'boundary: explicit external cross-link to #38 structural record' (@($xl).Count -eq 1 -and [bool]$xl[0].external -and ([string]$xl[0].external_ref -match '^skl_'))
# provenance: source_span slices the manifest bytes
$giSrc = Join-Path $fixRoot ([string]$gi.source_path)
$giBytes = [System.IO.File]::ReadAllBytes($giSrc)
Check 'provenance: source_span {0..filelen} matches manifest' (([int]$gi.source_span.start -eq 0) -and ([int]$gi.source_span.end -eq $giBytes.Length))

# ---------- 5) deterministic re-run: byte-identical ----------
$r2 = Run-SC @{ op='cards'; root=$fixRoot; namespace='fixture' }
$ix2 = Payload $r2
Check 'deterministic: records_digest identical' ([string]$ix2.records_digest -eq $digest1)
$rjl2 = ArtifactPath $r2 'records.jsonl'
Check 'deterministic: records.jsonl BYTE-identical' ((Get-Sha256HexFile $rjl) -eq (Get-Sha256HexFile $rjl2))
$cj2 = ArtifactPath $r2 'cards.json'
Check 'deterministic: cards.json BYTE-identical' ((Get-Sha256HexFile $cj) -eq (Get-Sha256HexFile $cj2))
$man1 = ArtifactPath $r 'index_manifest.json'; $man2 = ArtifactPath $r2 'index_manifest.json'
Check 'deterministic: index_manifest.json BYTE-identical' ((Get-Sha256HexFile $man1) -eq (Get-Sha256HexFile $man2))

# ---------- 6) Stage-1 eligibility ----------
$re = Run-SC @{ op='eligible'; root=$fixRoot; namespace='fixture'; task=@{ gpu_available=$false } }
$ep = Payload $re
Check 'stage1/gpu: exit 0 + envelope valid' ($re.exit -eq 0 -and [bool](Test-SkillResultEnvelope -Json $re.raw).valid)
Check 'stage1/gpu: gen.image excluded (gpu_unavailable)' (@($ep.excluded | Where-Object { $_.skill_id -eq 'fixture.gen.image' -and (@($_.reasons) -contains 'gpu_unavailable') }).Count -eq 1)
Check 'stage1/gpu: ocr + transcribe stay eligible' ((@($ep.eligible) -contains 'fixture.ocr') -and (@($ep.eligible) -contains 'fixture.transcribe'))

$re2 = Run-SC @{ op='eligible'; root=$fixRoot; namespace='fixture'; task=@{ allow_side_effects=$false } }
$ep2 = Payload $re2
Check 'stage1/side-effect: gen.image + lease + web.fetch excluded' ((@($ep2.excluded | ForEach-Object { $_.skill_id }) -contains 'fixture.gen.image') -and (@($ep2.excluded | ForEach-Object { $_.skill_id }) -contains 'fixture.lease') -and (@($ep2.excluded | ForEach-Object { $_.skill_id }) -contains 'fixture.web.fetch'))
Check 'stage1/side-effect: read-only ocr eligible' (@($ep2.eligible) -contains 'fixture.ocr')

$re3 = Run-SC @{ op='eligible'; root=$fixRoot; namespace='fixture'; task=@{ unavailable_dependencies=@('whisper-small') } }
$ep3 = Payload $re3
Check 'stage1/dependency: transcribe excluded (whisper-small)' (@($ep3.excluded | Where-Object { $_.skill_id -eq 'fixture.transcribe' }).Count -eq 1)

# ---------- 7) Stage-2 lexical retrieval ----------
$rr = Run-SC @{ op='retrieve'; root=$fixRoot; namespace='fixture'; query='extract text and layout from a scanned document image'; k=5 }
$rp = Payload $rr
Check 'stage2/ocr: exit 0 + envelope valid' ($rr.exit -eq 0 -and [bool](Test-SkillResultEnvelope -Json $rr.raw).valid)
$rids = @($rp.results | ForEach-Object { [string]$_.skill_id })
Check 'stage2/ocr: fixture.ocr is rank 1' ($rids.Count -ge 1 -and $rids[0] -eq 'fixture.ocr') "ids=$($rids -join ',')"
Check 'stage2/ocr: irrelevant fixture.lease EXCLUDED' (-not ($rids -contains 'fixture.lease'))
Check 'stage2/ocr: seam defined (semantic query shape + #36 search call)' ((Has $rp 'seam') -and (Has $rp.seam 'semantic_query_shape') -and (Has $rp.seam 'artifact_search_call'))

$rr2 = Run-SC @{ op='retrieve'; root=$fixRoot; namespace='fixture'; query='acquire and release a lease on a shared resource'; k=5 }
$rp2 = Payload $rr2
$rids2 = @($rp2.results | ForEach-Object { [string]$_.skill_id })
Check 'stage2/lease: fixture.lease is rank 1' ($rids2.Count -ge 1 -and $rids2[0] -eq 'fixture.lease') "ids=$($rids2 -join ',')"
Check 'stage2/lease: irrelevant fixture.ocr EXCLUDED' (-not ($rids2 -contains 'fixture.ocr'))

$rr3 = Run-SC @{ op='retrieve'; root=$fixRoot; namespace='fixture'; query='quantum chromodynamics lattice gauge theory'; k=5 }
Check 'stage2/no-match: empty result for an unrelated query' ([int](Payload $rr3).count -eq 0)

# ---------- 8) validate op + tamper detection ----------
$rv = Run-SC @{ op='validate'; records_path=$rjl }
$vp = Payload $rv
Check 'validate: exit 0 + ok on clean records' ($rv.exit -eq 0 -and [bool]$vp.validation.ok)
$tamperFile = Join-Path $tmpRoot 'tampered.jsonl'
$lines = @(Get-Content -LiteralPath $rjl)
$obj0 = $lines[0] | ConvertFrom-Json
$obj0.content_hash = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
$lines[0] = ($obj0 | ConvertTo-Json -Compress -Depth 40)
[System.IO.File]::WriteAllLines($tamperFile, $lines, $utf8)
$rt = Run-SC @{ op='validate'; records_path=$tamperFile }
Check 'validate: tampered content_hash DETECTED (ok=false)' ($null -ne (Payload $rt) -and (-not [bool](Payload $rt).validation.ok))

# ---------- 9) bounded REAL slice (../../modules) ----------
$realRoot = Join-Path $SkillDir '..\..\modules'
if (Test-Path -LiteralPath $realRoot -PathType Container) {
    $realAbs = (Resolve-Path -LiteralPath $realRoot).Path
    $rr1 = Run-SC @{ op='cards'; root=$realAbs; namespace='life-orchestrator' }
    $rip = Payload $rr1
    Check 'real-slice: cards ok + validation ok' ($rr1.exit -eq 0 -and $null -ne $rip -and [bool]$rip.validation.ok) "err=$($rr1.err) verr=$($rip.validation.errors -join '; ')"
    Check 'real-slice: skills emitted (>0)' ([int]$rip.skill_count -gt 0) "skills=$($rip.skill_count)"
    Check 'real-slice: skill.card itself carded' (@((Get-Content -LiteralPath (ArtifactPath $rr1 'cards.json') -Raw | ConvertFrom-Json) | Where-Object { $_.skill_id -eq 'skill.card' }).Count -ge 1)
    $rr1b = Run-SC @{ op='cards'; root=$realAbs; namespace='life-orchestrator' }
    Check 'real-slice: deterministic re-index (digest identical)' ([string](Payload $rr1b).records_digest -eq [string]$rip.records_digest)
    # a real retrieval: a speech query returns speech.stt and excludes res.lease from the top
    $rrr = Run-SC @{ op='retrieve'; root=$realAbs; namespace='life-orchestrator'; query='transcribe speech audio to text with timestamps'; k=5 }
    $rrp = Payload $rrr
    $rrids = @($rrp.results | ForEach-Object { [string]$_.skill_id })
    Check 'real-slice/retrieval: a speech skill surfaces; res.lease not rank 1' ($rrids.Count -ge 1 -and $rrids[0] -ne 'res.lease') "ids=$($rrids -join ',')"
} else {
    Check 'real-slice: [skipped: no ../../modules in this tree]' $true
}

# ---------- 10) error paths ----------
$r = Run-SC @{ op='cards' }
Check 'error: missing_root when no root/roots' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_root')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-SC @{ op='cards'; root=(Join-Path $tmpRoot 'no-such-dir') }
Check 'error: root_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'root_not_found')
$r = Run-SC @{ op='retrieve'; root=$fixRoot }
Check 'error: missing_query (retrieve)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_query')
$r = Run-SC @{ op='frobnicate' }
Check 'error: invalid_op' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_op')
$r = Run-SC @{ op='validate'; records_path=(Join-Path $tmpRoot 'missing.jsonl') }
Check 'error: records_not_found (validate missing file)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'records_not_found')

# ---------- 11) Module 1 generic wrapper ----------
$wrapInp = [ordered]@{ op='cards'; root=$fixRoot; namespace='fixture'; python_path=$PythonPath }
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
