#requires -Version 7.0
<#
  Invoke-ArtifactSearchTests.ps1 -- tests for artifact.search (Module 36).

  Real-worker & OS-portable (mirrors image.util's real-worker gate, NOT a mock): SQLite + FTS5 is stdlib
  and cross-platform, so the harness runs the REAL Invoke-ArtifactSearch.ps1 -> the REAL artifact_search.py
  under a resolved python. The same harness is the cloud pre-ship gate (cloud python + FTS5) AND the live
  Windows/executor test (system python). It uses the committed fixtures/repo and copies it to a temp dir
  for the change/delete/move reconciliation tests; it also indexes a bounded slice of the REAL core-docs
  when present (../../core-docs).

  -PythonPath <python>  : interpreter to use (must have stdlib sqlite3 with FTS5). If omitted, resolved.
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
        & $exe -c "import sqlite3; c=sqlite3.connect(':memory:'); c.execute('CREATE VIRTUAL TABLE t USING fts5(x)')" 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}

if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) { $PwshPath = (Get-Process -Id $PID).Path }
$entry = Join-Path $SkillDir 'Invoke-ArtifactSearch.ps1'
$contractLib = Join-Path $SkillDir '..\01-skill-bootstrap\lib\SkillContract.psm1'
$wrapper = Join-Path $SkillDir '..\01-skill-bootstrap\Invoke-Skill.ps1'
Import-Module (Resolve-Path -LiteralPath $contractLib).Path -Force
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("m36-tests-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$artRoot = Join-Path $tmpRoot 'artifacts'
$fixtureRepo = Join-Path $SkillDir 'fixtures/repo'

Write-Host "=== artifact.search tests ==="
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
    Write-Host "  [FAIL] no python with stdlib sqlite3+FTS5 found (set -PythonPath)"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}
Write-Host "python=$PythonPath"
if (-not (Test-Path -LiteralPath $fixtureRepo -PathType Container)) {
    Write-Host "  [FAIL] fixtures/repo missing at $fixtureRepo"; Write-Host "RESULT: 0/1 passed  (fail=1)"; Write-Host "ALLPASS=false"; exit 1
}

function Run-AS([hashtable]$inp) {
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
function Payload($r) { if ($null -ne $r.env -and (Has $r.env 'result') -and (Has $r.env.result 'result')) { return $r.env.result.result } return $null }

# ---------- 1) manifest ----------
$mf = Join-Path $SkillDir 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest is schema-valid' ([bool]$mv.valid) (($mv.errors) -join '; ')
$man = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest determinism=deterministic' ($man.determinism -eq 'deterministic')
Check 'manifest skill_id=artifact.search' ($man.skill_id -eq 'artifact.search')
Check 'manifest version=0.2.0' ($man.version -eq '0.2.0')
Check 'manifest contract_version=0.2' ($man.contract_version -eq '0.2')
Check 'manifest batch=false & streaming=false' (($man.batch -eq $false) -and ($man.streaming -eq $false))

# ---------- 2) ingest the bundled fixture repo ----------
$db = Join-Path $tmpRoot 'cat.db'
$r = Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$db }
Check 'ingest: exit 0' ($r.exit -eq 0) "exit=$($r.exit) err=$($r.err)"
$ev = Test-SkillResultEnvelope -Json $r.raw
Check 'ingest: envelope schema-valid' ([bool]$ev.valid) (($ev.errors) -join '; ')
$e = $r.env
Check 'ingest: status ok/partial' ($null -ne $e -and @('ok','partial') -contains $e.status) "status=$($e.status)"
Check 'ingest: confidence null (deterministic)' ($null -ne $e -and $null -eq $e.confidence)
Check 'ingest: model_provenance empty' ($null -ne $e -and @($e.model_provenance).Count -eq 0)
$ing = Payload $r
Check 'ingest: counts.added == 5' ($null -ne $ing -and [int]$ing.counts.added -eq 5) "added=$($ing.counts.added)"
Check 'ingest: integrity_ok true' ($null -ne $ing -and [bool]$ing.integrity_ok) "integrity=$($ing.integrity | ConvertTo-Json -Compress -Depth 6)"
Check 'ingest: catalog_digest is 64 hex' ([string]$ing.catalog_digest -match '^[0-9a-f]{64}$') "digest=$($ing.catalog_digest)"
Check 'ingest: total chunks > 5' ($null -ne $ing -and [int]$ing.counts_total.chunks -gt 5) "chunks=$($ing.counts_total.chunks)"
Check 'ingest: embeddings == chunks (mock seam wired)' ([int]$ing.counts_total.embeddings -eq [int]$ing.counts_total.chunks) "emb=$($ing.counts_total.embeddings) chk=$($ing.counts_total.chunks)"
$digest1 = [string]$ing.catalog_digest
# artifacts include ingest_report.json + catalog_digest.txt, each with a matching sha256
$arts = @($e.artifacts); $apaths = @($arts | ForEach-Object { [string]$_.path })
Check 'ingest: artifacts include ingest_report.json' (@($apaths | Where-Object { $_ -match 'ingest_report\.json$' }).Count -eq 1) "paths=$($apaths -join ',')"
$rep = @($arts | Where-Object { [string]$_.path -match 'ingest_report\.json$' })[0]
Check 'ingest: ingest_report.json sha256 matches file' ($null -ne $rep -and (Get-Sha256HexFile ([string]$rep.path)) -eq [string]$rep.sha256)

# ---------- 3) deterministic re-ingest into a SECOND fresh db ----------
$db2 = Join-Path $tmpRoot 'cat2.db'
$r2 = Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$db2 }
$ing2 = Payload $r2
Check 'deterministic: catalog_digest identical across two fresh dbs' ($null -ne $ing2 -and [string]$ing2.catalog_digest -eq $digest1) "d2=$($ing2.catalog_digest)"

# ---------- 4) idempotent re-ingest into SAME db ----------
$r3 = Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$db }
$ing3 = Payload $r3
Check 'idempotent: unchanged==5 added==0 changed==0' ($null -ne $ing3 -and [int]$ing3.counts.unchanged -eq 5 -and [int]$ing3.counts.added -eq 0 -and [int]$ing3.counts.changed -eq 0) "counts=$($ing3.counts | ConvertTo-Json -Compress)"
Check 'idempotent: digest unchanged' ([string]$ing3.catalog_digest -eq $digest1)

# ---------- 5) FTS search + provenance ----------
$r = Run-AS @{ op='search'; query='frobnicator flux'; mode='fts'; k=10; db=$db }
Check 'search(fts): exit 0 + envelope valid' ($r.exit -eq 0 -and [bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$sp = Payload $r
Check 'search(fts): returns hits' ($null -ne $sp -and [int]$sp.count -gt 0) "count=$($sp.count)"
$h0 = @($sp.results)[0]
Check 'search(fts): hit has 0.2 provenance + per-channel diagnostics (score retired)' ($null -ne $h0 -and (Has $h0 'source_path') -and (Has $h0 'content_hash') -and (Has $h0 'chunk_id') -and (Has $h0 'span') -and (Has $h0 'span_label') -and (Has $h0 'record_version_id') -and (Has $h0 'lexical_score') -and (Has $h0 'fused_score') -and (Has $h0 'fused_rank') -and (Has $h0 'snippet') -and (-not (Has $h0 'score')))
Check 'search(fts): span start<end' ($null -ne $h0 -and [int]$h0.span.start -lt [int]$h0.span.end) "span=$($h0.span | ConvertTo-Json -Compress)"

# ---------- 6) FTS deterministic order (run twice) ----------
$ra = Run-AS @{ op='search'; query='widget retrieval'; mode='fts'; k=10; db=$db }
$rb = Run-AS @{ op='search'; query='widget retrieval'; mode='fts'; k=10; db=$db }
$ida = @(@((Payload $ra).results) | ForEach-Object { [string]$_.chunk_id })
$idb = @(@((Payload $rb).results) | ForEach-Object { [string]$_.chunk_id })
Check 'search(fts): order is deterministic' (($ida -join ',') -eq ($idb -join ','))

# ---------- 7) exact search: unique marker + filename ----------
$r = Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=10; db=$db }
$sp = Payload $r
Check 'search(exact): unique marker returns exactly 1' ($null -ne $sp -and [int]$sp.count -eq 1) "count=$($sp.count)"
if ($null -ne $sp -and [int]$sp.count -ge 1) {
    Check 'search(exact): marker resolves to README.md' (([string](@($sp.results)[0].source_path)) -match 'README\.md$') "path=$(@($sp.results)[0].source_path)"
}
$r = Run-AS @{ op='search'; query='config.json'; mode='exact'; k=10; db=$db }
$sp = Payload $r
Check 'search(exact): filename search ranks config.json first' ($null -ne $sp -and [int]$sp.count -ge 1 -and ([string](@($sp.results)[0].source_path)) -match 'config\.json$') "first=$(@($sp.results)[0].source_path)"

# ---------- 8) provenance: span bytes map back to source ----------
$r = Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$db }
$h = @((Payload $r).results)[0]
$srcFile = Join-Path $fixtureRepo ([string]$h.source_path)
$raw = [System.IO.File]::ReadAllBytes($srcFile)
$slice = $raw[([int]$h.span.start)..(([int]$h.span.end)-1)]
$sliceText = $utf8.GetString($slice)
Check 'provenance: span slice of source contains the marker' ($sliceText -match 'QUOKKA_MARKER_7')
Check 'provenance: content_hash matches the source file' ([string]$h.content_hash -eq (Get-Sha256HexFile $srcFile))
Check 'provenance: markdown section_path names Retrieval layer' ([string]$h.section_path -match 'Retrieval layer') "section=$($h.section_path)"

# ---------- 9) fenced pseudo-heading not split into a section ----------
$r = Run-AS @{ op='search'; query='Not A Heading'; mode='exact'; k=5; db=$db }
$sp = Payload $r
$badHeading = $false
foreach ($hh in @($sp.results)) { if (([string]$hh.heading) -eq 'Not A Heading' -or ([string]$hh.section_path) -eq 'Not A Heading') { $badHeading = $true } }
Check 'chunking: fenced ## line did NOT become a heading/section' ((-not $badHeading) -and [int]$sp.count -ge 1) "count=$($sp.count) bad=$badHeading"

# ---------- 10) mock embedding contract (shape + input-order + dim + batch==single + determinism) ----------
$r = Run-AS @{ op='embed'; texts=@('hello world','','second text'); dim=32; normalize=$true }
$em = Payload $r
Check 'embed: count == 3' ($null -ne $em -and [int]$em.count -eq 3) "count=$($em.count)"
Check 'embed: vectors length == 3' (@($em.vectors).Count -eq 3)
Check 'embed: each vector dim == 32' (@(@($em.vectors) | Where-Object { @($_).Count -eq 32 }).Count -eq 3)
Check 'embed: provider fields present' ((Has $em 'provider_id') -and (Has $em 'model_id') -and (Has $em 'model_version') -and (Has $em 'model_sha256') -and (Has $em 'engine_build') -and (Has $em 'dim') -and (Has $em 'normalized'))
$stat = @{}; foreach ($s in @($em.input_status)) { $stat[[int]$s.index] = [string]$s.status }
Check 'embed: empty input flagged skipped_empty at index 1' ($stat.ContainsKey(1) -and $stat[1] -eq 'skipped_empty') "status=$($em.input_status | ConvertTo-Json -Compress)"
Check 'embed: ok status at index 0 and 2' ($stat[0] -eq 'ok' -and $stat[2] -eq 'ok')
$v0 = @(@($em.vectors)[0] | ForEach-Object { [double]$_ })
$norm0 = [math]::Sqrt((($v0 | ForEach-Object { $_ * $_ }) | Measure-Object -Sum).Sum)
Check 'embed: normalized vector ~unit norm' ([math]::Abs($norm0 - 1.0) -lt 1e-6) "norm=$norm0"
$ea = Run-AS @{ op='embed'; texts=@('alpha','beta'); dim=32 }
$eb = Run-AS @{ op='embed'; texts=@('alpha','beta'); dim=32 }
$va = ((Payload $ea).vectors | ConvertTo-Json -Compress -Depth 6)
$vb = ((Payload $eb).vectors | ConvertTo-Json -Compress -Depth 6)
Check 'embed: deterministic (same inputs -> same vectors)' ($va -eq $vb)
$single = Run-AS @{ op='embed'; text='beta'; dim=32 }
$vBetaBatch = (@((Payload $ea).vectors)[1] | ConvertTo-Json -Compress -Depth 6)
$vBetaSingle = (@((Payload $single).vectors)[0] | ConvertTo-Json -Compress -Depth 6)
Check 'embed: batch==single (input-order preserved)' ($vBetaBatch -eq $vBetaSingle)

# ---------- 11) change/delete/move reconcile (on a temp mutable copy) ----------
$mut = Join-Path $tmpRoot 'mutrepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $mut -Recurse -Force
$dbm = Join-Path $tmpRoot 'mut.db'
$r = Run-AS @{ op='ingest'; source='mut'; root=$mut; db=$dbm }
$base = Payload $r
# change a file
Add-Content -LiteralPath (Join-Path $mut 'docs/guide.md') -Value "`n## New Section`n`nAdded token CHANGED_TOKEN_X here.`n"
$r = Run-AS @{ op='ingest'; source='mut'; root=$mut; db=$dbm }
$chg = Payload $r
Check 'reconcile(change): changed==1' ($null -ne $chg -and [int]$chg.counts.changed -eq 1) "counts=$($chg.counts | ConvertTo-Json -Compress)"
Check 'reconcile(change): digest changed' ([string]$chg.catalog_digest -ne [string]$base.catalog_digest)
Check 'reconcile(change): integrity_ok' ([bool]$chg.integrity_ok)
$r = Run-AS @{ op='search'; query='CHANGED_TOKEN_X'; mode='exact'; db=$dbm }
Check 'reconcile(change): new token searchable' ([int](Payload $r).count -eq 1)
# no duplicate chunks after change
$r = Run-AS @{ op='integrity'; db=$dbm }
$integ = Payload $r
Check 'reconcile: integrity ok after change' ([bool]$integ.ok) ("failed=" + (@($integ.checks | Where-Object { -not $_.ok } | ForEach-Object { $_.name }) -join ','))
$ndc = @($integ.checks | Where-Object { $_.name -eq 'no_duplicate_chunk_ids' })[0]
Check 'reconcile: no_duplicate_chunk_ids ok' ([bool]$ndc.ok) "$($ndc.detail)"
# delete a file
Remove-Item -LiteralPath (Join-Path $mut 'docs/notes.txt') -Force
$r = Run-AS @{ op='ingest'; source='mut'; root=$mut; db=$dbm }
$del = Payload $r
Check 'reconcile(delete): deleted==1' ($null -ne $del -and [int]$del.counts.deleted -eq 1) "counts=$($del.counts | ConvertTo-Json -Compress)"
$r = Run-AS @{ op='search'; query='PLAINTEXT_ONLY_TOKEN'; mode='exact'; db=$dbm }
Check 'reconcile(delete): deleted content no longer searchable' ([int](Payload $r).count -eq 0)
$r = Run-AS @{ op='integrity'; db=$dbm }
Check 'reconcile: integrity ok after delete' ([bool](Payload $r).ok)
# move a file
Move-Item -LiteralPath (Join-Path $mut 'src/hello.py') -Destination (Join-Path $mut 'src/hello2.py') -Force
$r = Run-AS @{ op='ingest'; source='mut'; root=$mut; db=$dbm }
$mv = Payload $r
Check 'reconcile(move): 1 move detected hello.py->hello2.py' (@($mv.moved).Count -eq 1 -and ([string](@($mv.moved)[0].from)) -match 'hello\.py$' -and ([string](@($mv.moved)[0].to)) -match 'hello2\.py$') "moved=$($mv.moved | ConvertTo-Json -Compress -Depth 5)"

# ---------- 12) parse-failure surfacing (binary file, never silently dropped) ----------
$binRepo = Join-Path $tmpRoot 'binrepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $binRepo -Recurse -Force
[System.IO.File]::WriteAllBytes((Join-Path $binRepo 'blob.bin'), [byte[]](0,1,2,66,73,78,255,254))
$dbb = Join-Path $tmpRoot 'bin.db'
$r = Run-AS @{ op='ingest'; source='bin'; root=$binRepo; db=$dbb }
$bp = Payload $r
Check 'parse-failure: 1 surfaced (not silently dropped)' ($null -ne $bp -and [int]$bp.counts.parse_failures -eq 1) "pf=$($bp.counts.parse_failures)"
Check 'parse-failure: names blob.bin' (@($bp.parse_failures | Where-Object { ([string]$_.rel_path) -match 'blob\.bin$' }).Count -eq 1) "pf=$($bp.parse_failures | ConvertTo-Json -Compress -Depth 5)"
Check 'parse-failure: surfaced as a warning + status partial' ($r.env.status -eq 'partial' -and @($r.env.warnings).Count -ge 1)
Check 'parse-failure: integrity still ok' ([bool]$bp.integrity_ok)

# ---------- 13) export-chunk-texts + store-embeddings (D-0077 fold drop-in) ----------
$r = Run-AS @{ op='export-chunk-texts'; db=$db }
$ex = Payload $r
Check 'export-chunk-texts: returns chunks with provenance' ($null -ne $ex -and [int]$ex.count -gt 0 -and (Has (@($ex.chunks)[0]) 'chunk_id') -and (Has (@($ex.chunks)[0]) 'text'))
$cids = @(@($ex.chunks) | ForEach-Object { [string]$_.chunk_id })
$texts = @(@($ex.chunks) | ForEach-Object { [string]$_.text })
$emb = Payload (Run-AS @{ op='embed'; texts=$texts; dim=16 })
$r = Run-AS @{ op='store-embeddings'; db=$db; chunk_ids=$cids; vectors=$emb.vectors; provider_id='external-test'; dim=16; model_id='x'; model_version='1' }
$st = Payload $r
Check 'store-embeddings: stored all exported chunks' ($null -ne $st -and [int]$st.stored -eq $cids.Count) "stored=$($st.stored) of $($cids.Count)"

# ---------- 14) error paths ----------
$r = Run-AS @{ op='search'; query=''; mode='fts'; db=$db }
Check 'error: missing_query on empty query' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'missing_query')
Check 'error: envelope still schema-valid' ([bool](Test-SkillResultEnvelope -Json $r.raw).valid)
$r = Run-AS @{ op='frobnicate'; db=$db }
Check 'error: invalid_op' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'invalid_op')
$r = Run-AS @{ op='ingest'; source='x'; root=(Join-Path $tmpRoot 'no-such-dir'); db=(Join-Path $tmpRoot 'z.db') }
Check 'error: root_not_found' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'root_not_found')
$r = Run-AS @{ op='search'; query='x'; db=(Join-Path $tmpRoot 'missing.db') }
Check 'error: db_not_found (search before ingest)' ($null -ne $r.env -and $r.env.status -eq 'error' -and $r.env.error.code -eq 'db_not_found')

# ---------- 15) bounded slice of the REAL repo (core-docs) ----------
$coreDocs = Join-Path $SkillDir '..\..\core-docs'
if (Test-Path -LiteralPath $coreDocs -PathType Container) {
    $cd = (Resolve-Path -LiteralPath $coreDocs).Path
    $dbc = Join-Path $tmpRoot 'coredocs.db'
    $r = Run-AS @{ op='ingest'; source='core-docs'; root=$cd; db=$dbc; max_files=40 }
    $cdi = Payload $r
    Check 'real-slice: core-docs ingest ok + integrity' ($r.exit -eq 0 -and $null -ne $cdi -and [bool]$cdi.integrity_ok) "err=$($r.err)"
    Check 'real-slice: added > 0 docs' ($null -ne $cdi -and [int]$cdi.counts.added -gt 0) "added=$($cdi.counts.added)"
    Check 'real-slice: chunks > docs (markdown split into sections)' ($null -ne $cdi -and [int]$cdi.counts_total.chunks -gt [int]$cdi.counts.added)
    # re-ingest stable
    $r2c = Run-AS @{ op='ingest'; source='core-docs'; root=$cd; db=$dbc; max_files=40 }
    $cdi2 = Payload $r2c
    Check 'real-slice: re-ingest is unchanged-stable (digest identical)' ([string]$cdi2.catalog_digest -eq [string]$cdi.catalog_digest -and [int]$cdi2.counts.changed -eq 0)
    # a lexical hit on a stable token with full provenance
    $r = Run-AS @{ op='search'; query='SKILL_CONTRACT'; mode='exact'; k=5; db=$dbc }
    $sp = Payload $r
    Check 'real-slice: exact search returns a provenance-complete hit' ($null -ne $sp -and [int]$sp.count -ge 1 -and (Has (@($sp.results)[0]) 'content_hash') -and (Has (@($sp.results)[0]) 'span'))
    $r = Run-AS @{ op='search'; query='resource lease'; mode='fts'; k=5; db=$dbc }
    Check 'real-slice: fts search returns hits' ([int](Payload $r).count -ge 1)
} else {
    Check 'real-slice: core-docs slice [skipped: ../../core-docs not in this tree]' $true
}

# ---------- 16) Module 1 generic wrapper ----------
$wrapInp = [ordered]@{ op='search'; query='frobnicator'; mode='fts'; db=$db; python_path=$PythonPath }
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

# ================= 0.2 (MEMORY_CONTRACT D-0083) additions =================

# ---------- 17) schema v2 + in-place migration from a shipped-0.1 db ----------
$v1worker = Join-Path $SkillDir 'fixtures/artifact_search_v1.py'
Check 'migrate: frozen shipped-0.1 worker fixture present' (Test-Path -LiteralPath $v1worker -PathType Leaf)
$v1db = Join-Path $tmpRoot 'v1seed.db'
$v1args = Join-Path $tmpRoot 'v1args.json'
$v1meta = Join-Path $tmpRoot 'v1meta.json'
[System.IO.File]::WriteAllText($v1args, ([ordered]@{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$v1db; meta_path=$v1meta; output_dir=(Join-Path $tmpRoot 'v1out') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v1worker $v1args 2>$null | Out-Null
$v1m = $null; try { $v1m = (Get-Content -LiteralPath $v1meta -Raw) | ConvertFrom-Json } catch { }
Check 'migrate: v1 seed db built at schema_version 1' ($null -ne $v1m -and [bool]$v1m.ok -and [string]$v1m.worker.schema_version -eq '1' -and (Test-Path -LiteralPath $v1db))
$v1chunks = [int]$v1m.result.counts_total.chunks
$v1emb = [int]$v1m.result.counts_total.embeddings
# migrate op is the FIRST op to touch the v1 db (so it reports the migration actions)
$mg = Payload (Run-AS @{ op='migrate'; db=$v1db })
Check 'migrate: schema_version 1 -> 2 in place, migrated=true' ($null -ne $mg -and [bool]$mg.migrated -and [string]$mg.schema_version -eq '2')
Check 'migrate: integrity ok + NO chunk loss' ($null -ne $mg -and [bool]$mg.integrity.ok -and [int]$mg.counts.chunks -eq $v1chunks) "chunks=$($mg.counts.chunks) v1=$v1chunks"
Check 'migrate: chunk_embeddings JSON retired -> float32 BLOB vectors (count preserved)' ([int]$mg.counts.embeddings -eq $v1emb) "emb=$($mg.counts.embeddings) v1=$v1emb"
$mg2 = Payload (Run-AS @{ op='migrate'; db=$v1db })
Check 'migrate: idempotent (second migrate is a no-op)' ($null -ne $mg2 -and (-not [bool]$mg2.migrated) -and [string]$mg2.schema_version -eq '2')
Check 'migrate: shipped search regression-green on migrated db' ([int](Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; db=$v1db })).count -ge 1)
Check 'migrate: shipped integrity regression-green on migrated db' ([bool](Payload (Run-AS @{ op='integrity'; db=$v1db })).ok)
Check 'migrate: source_chunk view works on migrated db' ([int](Payload (Run-AS @{ op='list-records'; db=$v1db; filters=@{ record_kind='source_chunk' }; limit=3 })).count -ge 1)

# ---------- 18) ingest_records SINK (typed records + first-class edges) ----------
$recdb = Join-Path $tmpRoot 'records.db'
Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$recdb } | Out-Null
$srcVer = [string](@((Payload (Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$recdb })).results)[0].source_version_id)
Check 'ingest_records: a source_version_id is resolvable from a search hit' ($srcVer -match '^ver_')
$recs = @(
  [ordered]@{ record_id='sym.frob'; record_version_id='sym.frob@1'; record_kind='symbol'; namespace='fixture'; text='def frobnicate(): SYMBOL_TOKEN_QX'; source_version_id=$srcVer; source_span=@{ start=0; end=12 }; authority_level='derived'; edges=@(@{ edge_kind='relates_to'; dst_ref='rel.fb@1'; dst_kind='record' }); derivation_refs=@($srcVer) },
  [ordered]@{ record_id='rel.fb'; record_version_id='rel.fb@1'; record_kind='relationship'; namespace='fixture'; text='frob relates bar RELATION_TOKEN_QX' },
  [ordered]@{ record_id='ep.1'; record_version_id='ep.1@1'; record_kind='episode'; namespace='fixture'; text='goal closed successfully EPISODE_TOKEN_QX' },
  [ordered]@{ record_id='fl.1'; record_version_id='fl.1@1'; record_kind='failure'; namespace='fixture'; text='arg_parse_failed at step 3 FAILURE_TOKEN_QX' },
  [ordered]@{ record_id='bad'; record_version_id='bad@1'; record_kind='not_a_kind'; text='x' },
  [ordered]@{ record_id=''; record_version_id=''; record_kind='symbol'; text='y' }
)
$ir = Payload (Run-AS @{ op='ingest-records'; db=$recdb; ingest_run=@{ producer='repo.intel'; producer_version='0.1'; namespace='fixture' }; records=$recs })
Check 'ingest_records: 4 accepted across >=3 record_kinds' ($null -ne $ir -and [int]$ir.counts.accepted -eq 4 -and (@($ir.counts.kinds.PSObject.Properties.Name).Count -ge 3)) "accepted=$($ir.counts.accepted) kinds=$($ir.counts.kinds | ConvertTo-Json -Compress)"
$rejReasons = @(@($ir.rejected) | ForEach-Object { [string]$_.reason })
Check 'ingest_records: 2 malformed records rejected with surfaced reasons' ([int]$ir.counts.rejected -eq 2 -and ($rejReasons -contains 'missing_required_field') -and ($rejReasons -contains 'unknown_record_kind')) "reasons=$($rejReasons -join ',')"
Check 'ingest_records: integrity ok after record ingest' ([bool]$ir.integrity_ok)
Check 'ingest_records: first-class edges materialized (derives_from + relates_to)' ([int]$ir.counts_total.record_edges -ge 2) "edges=$($ir.counts_total.record_edges)"
$recDigest = [string]$ir.catalog_digest
# retrievable by kind with resolving provenance
$hSym = @((Payload (Run-AS @{ op='search'; query='SYMBOL_TOKEN_QX'; mode='exact'; db=$recdb; filters=@{ record_kind='symbol' } })).results)[0]
Check 'ingest_records: symbol retrievable by kind, provenance resolves to source_version' ($null -ne $hSym -and [string]$hSym.record_kind -eq 'symbol' -and [string]$hSym.source_version_id -eq $srcVer -and (Has $hSym 'span') -and (Has $hSym 'record_version_id'))
# idempotent re-ingest
$ir2 = Payload (Run-AS @{ op='ingest-records'; db=$recdb; ingest_run=@{ producer='repo.intel'; producer_version='0.1'; namespace='fixture' }; records=$recs })
Check 'ingest_records: idempotent (0 accepted, 4 unchanged, digest stable)' ($null -ne $ir2 -and [int]$ir2.counts.accepted -eq 0 -and [int]$ir2.counts.unchanged -eq 4 -and [string]$ir2.catalog_digest -eq $recDigest)
# immutable revision conflict rejected
$conf = @( [ordered]@{ record_id='sym.frob'; record_version_id='sym.frob@1'; record_kind='symbol'; text='DIFFERENT CONTENT NOW' } )
$cir = Payload (Run-AS @{ op='ingest-records'; db=$recdb; records=$conf })
Check 'ingest_records: immutable-revision conflict rejected' ([int]$cir.counts.rejected -eq 1 -and (@($cir.rejected)[0].reason) -eq 'record_version_conflict')

# ---------- 19) record envelope adapter (list-records) ----------
$lrEp = Payload (Run-AS @{ op='list-records'; db=$recdb; filters=@{ record_kind='episode' } })
$ep = @($lrEp.records)[0]
Check 'list-records: episode envelope carries s1 fields' ($null -ne $ep -and (Has $ep 'record_id') -and (Has $ep 'record_version_id') -and (Has $ep 'namespace') -and (Has $ep 'status') -and (Has $ep 'authority_level') -and (Has $ep 'sensitivity_class') -and (Has $ep 'parent_edges') -and (Has $ep 'child_edges'))
$lrSym = Payload (Run-AS @{ op='list-records'; db=$recdb; filters=@{ record_kind='symbol' } })
$symE = @($lrSym.records)[0]
Check 'list-records: symbol edges resolve (derives_from source_version + relates_to)' ($null -ne $symE -and @($symE.parent_edges).Count -ge 2)
$lrSC = Payload (Run-AS @{ op='list-records'; db=$recdb; filters=@{ record_kind='source_chunk' }; limit=3 })
$sc = @($lrSC.records)[0]
Check 'list-records: source_chunk view reproduces chunk provenance (envelope)' ($null -ne $sc -and [string]$sc.record_kind -eq 'source_chunk' -and (Has $sc 'source_version_id') -and (Has $sc 'source_span') -and (Has $sc 'chunker_fingerprint') -and @($sc.parent_edges).Count -eq 1)

# ---------- 20) retriever 0.2 hit shape (every s3 field; opaque score retired) ----------
$hh = @((Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; k=5; db=$recdb })).results)[0]
$need = @('record_id','record_version_id','record_kind','source_path','content_hash','span','span_label','section_path','heading','chunk_type','status','authority_level','retrieval_channels','lexical_rank','lexical_score','vector_rank','vector_similarity','fused_rank','fused_score','fusion_algo','fusion_version','embedding_space_id','index_snapshot','corpus_version','filter_decisions','tie_break_key','snippet','rank')
$missing = @($need | Where-Object { -not (Has $hh $_) })
Check 'retriever 0.2: hit carries every s3 field' ($missing.Count -eq 0) "missing=$($missing -join ',')"
Check 'retriever 0.2: opaque score retired' (-not (Has $hh 'score'))
Check 'retriever 0.2: span is object {start,end} + span_label string' ((Has $hh.span 'start') -and (Has $hh.span 'end') -and ([string]$hh.span_label).Length -gt 0)
Check 'retriever 0.2: vector channel null (no vector search this wave)' ($null -eq $hh.vector_rank -and $null -eq $hh.vector_similarity)
Check 'retriever 0.2: fused_rank == rank, fusion_algo lexical_only' ([int]$hh.fused_rank -eq [int]$hh.rank -and [string]$hh.fusion_algo -eq 'lexical_only')

# ---------- 21) staleness taxonomy (enum, not a boolean) ----------
$stmut = Join-Path $tmpRoot 'stalerepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $stmut -Recurse -Force
$stdb = Join-Path $tmpRoot 'stale.db'
Run-AS @{ op='ingest'; source='st'; root=$stmut; db=$stdb } | Out-Null
$stVer = [string](@((Payload (Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$stdb })).results)[0].source_version_id)
Run-AS @{ op='ingest-records'; db=$stdb; ingest_run=@{ producer='p'; namespace='st' }; records=@( [ordered]@{ record_id='sum.x'; record_version_id='sum.x@1'; record_kind='summary'; namespace='st'; text='STALE_PROBE_TOKEN summary of readme'; source_version_id=$stVer; status='current' } ) } | Out-Null
Add-Content -LiteralPath (Join-Path $stmut 'README.md') -Value "`n`n## More`n`nchanged content STALE_CHANGE_MARK`n"
$sw = Payload (Run-AS @{ op='ingest'; source='st'; root=$stmut; db=$stdb })
Check 'staleness: >=1 record marked source_stale after its source version changed' ([int]$sw.counts.records_marked_source_stale -ge 1) "marked=$($sw.counts.records_marked_source_stale)"
$stHit = @((Payload (Run-AS @{ op='search'; query='STALE_PROBE_TOKEN'; mode='exact'; db=$stdb; filters=@{ record_kind='summary' } })).results)[0]
Check 'staleness: stale record retained + retrievable with status=source_stale' ($null -ne $stHit -and [string]$stHit.status -eq 'source_stale')
Check 'staleness: exclude_stale drops the stale record (current-source query)' ([int](Payload (Run-AS @{ op='search'; query='STALE_PROBE_TOKEN'; mode='exact'; db=$stdb; filters=@{ record_kind='summary'; exclude_stale=$true } })).count -eq 0)

# ---------- 22) float32 LE BLOB vector storage (round-trip, keyed on embedding_space_id) ----------
$cid0 = [string](@((Payload (Run-AS @{ op='export-chunk-texts'; db=$recdb; limit=1 })).chunks)[0].chunk_id)
$vv = (Payload (Run-AS @{ op='get-vector'; db=$recdb; target_kind='chunk'; target_id=$cid0 })).vector
Check 'float32: mock ingest vector round-trips (dim*4 bytes, f32le/1, esp key)' ($null -ne $vv -and [int]$vv.vector_bytes -eq ([int]$vv.dim * 4) -and [string]$vv.encoding_version -eq 'f32le/1' -and @($vv.vector).Count -eq [int]$vv.dim -and ([string]$vv.embedding_space_id) -match '^esp_')
$exAll = Payload (Run-AS @{ op='export-chunk-texts'; db=$recdb })
$cids = @(@($exAll.chunks) | ForEach-Object { [string]$_.chunk_id })
$texts = @(@($exAll.chunks) | ForEach-Object { [string]$_.text })
$emb8 = Payload (Run-AS @{ op='embed'; texts=$texts; dim=8 })
$st8 = Payload (Run-AS @{ op='store-embeddings'; db=$recdb; chunk_ids=$cids; vectors=$emb8.vectors; provider_id='ext'; dim=8; model_id='m'; model_version='1'; embedding_space_id='esp_teststore' })
Check 'store-embeddings: external vectors stored as f32 BLOB keyed on embedding_space_id' ($null -ne $st8 -and [int]$st8.stored -eq $cids.Count -and [string]$st8.embedding_space_id -eq 'esp_teststore' -and [string]$st8.encoding_version -eq 'f32le/1')
$vv8 = (Payload (Run-AS @{ op='get-vector'; db=$recdb; target_kind='chunk'; target_id=$cids[0]; embedding_space_id='esp_teststore' })).vector
Check 'store-embeddings: stored BLOB round-trips at dim 8 (byte-length validated)' ($null -ne $vv8 -and [int]$vv8.dim -eq 8 -and @($vv8.vector).Count -eq 8 -and [int]$vv8.vector_bytes -eq 32)
Check 'store-embeddings: integrity ok after external vectors' ([bool](Payload (Run-AS @{ op='integrity'; db=$recdb })).ok)

# ---------- 23) catalog hardening: stale-fallback + crash-safety fault injection ----------
# a CHANGED source whose new content fails to parse -> serve last-good as an EXPLICIT stale fallback
$sfmut = Join-Path $tmpRoot 'sfrepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $sfmut -Recurse -Force
$sfdb = Join-Path $tmpRoot 'sf.db'
Run-AS @{ op='ingest'; source='sf'; root=$sfmut; db=$sfdb } | Out-Null
$before = [int](Payload (Run-AS @{ op='search'; query='PLAINTEXT_ONLY_TOKEN'; mode='exact'; db=$sfdb })).count
[System.IO.File]::WriteAllBytes((Join-Path $sfmut 'docs/notes.txt'), [byte[]](80,76,65,0,1,2,255))  # was a good text file; now binary
$sf = Payload (Run-AS @{ op='ingest'; source='sf'; root=$sfmut; db=$sfdb })
Check 'stale-fallback: changed-but-unparseable source served as explicit stale fallback' ([int]$sf.counts.stale_fallbacks -ge 1 -and [int]$sf.counts_total.documents_stale_fallback -ge 1)
Check 'stale-fallback: integrity ok (old good chunks retained, not blanked)' ([bool]$sf.integrity_ok)
$afterHit = @((Payload (Run-AS @{ op='search'; query='PLAINTEXT_ONLY_TOKEN'; mode='exact'; db=$sfdb; filters=@{ record_kind='source_chunk' } })).results)[0]
Check 'stale-fallback: old content still searchable, flagged status=source_stale' ($before -ge 1 -and $null -ne $afterHit -and [string]$afterHit.status -eq 'source_stale')

# crash-safety: an injected PRE-COMMIT fault must roll the whole transaction back (no partial state)
$fdb = Join-Path $tmpRoot 'fault.db'
$fmut = Join-Path $tmpRoot 'faultrepo'
Copy-Item -LiteralPath $fixtureRepo -Destination $fmut -Recurse -Force
$fbase = Payload (Run-AS @{ op='ingest'; source='fx'; root=$fmut; db=$fdb })
$fbaseDigest = [string]$fbase.catalog_digest
Add-Content -LiteralPath (Join-Path $fmut 'docs/guide.md') -Value "`nFAULT_CHANGE_TOKEN here`n"
$fr = Run-AS @{ op='ingest'; source='fx'; root=$fmut; db=$fdb; _fault='before_ingest_commit' }
Check 'crash-safety: injected pre-commit fault fails the ingest op' ($null -ne $fr.env -and $fr.env.status -eq 'error' -and $fr.env.error.code -eq 'fault_injected')
Check 'crash-safety: db integrity ok after rollback' ([bool](Payload (Run-AS @{ op='integrity'; db=$fdb })).ok)
Check 'crash-safety: catalog digest unchanged (transaction rolled back, no partial writes)' ([string](Payload (Run-AS @{ op='catalog'; db=$fdb })).digest -eq $fbaseDigest)
Check 'crash-safety: faulted change is absent after rollback' ([int](Payload (Run-AS @{ op='search'; query='FAULT_CHANGE_TOKEN'; mode='exact'; db=$fdb })).count -eq 0)
$frr = Run-AS @{ op='ingest-records'; db=$fdb; ingest_run=@{ producer='p' }; records=@( [ordered]@{ record_id='z'; record_version_id='z@1'; record_kind='symbol'; text='ZFAULT_TOKEN' } ); _fault='before_records_commit' }
Check 'crash-safety: injected fault in ingest_records fails the op' ($null -ne $frr.env -and $frr.env.status -eq 'error')
Check 'crash-safety: ingest_records rollback left no record' ([int](Payload (Run-AS @{ op='search'; query='ZFAULT_TOKEN'; mode='exact'; db=$fdb })).count -eq 0)

# ---------- 24) catalog_digest extended to records + deterministic across fresh dbs ----------
$dg1 = [string](Payload (Run-AS @{ op='catalog'; db=$recdb })).digest
$dg2 = [string](Payload (Run-AS @{ op='catalog'; db=$recdb })).digest
Check 'digest: catalog_digest stable across repeat reads (records folded in)' ($dg1 -eq $dg2)
$recdbB = Join-Path $tmpRoot 'recordsB.db'
Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$recdbB } | Out-Null
Run-AS @{ op='ingest-records'; db=$recdbB; ingest_run=@{ producer='repo.intel'; producer_version='0.1'; namespace='fixture' }; records=$recs } | Out-Null
$dgB = [string](Payload (Run-AS @{ op='catalog'; db=$recdbB })).digest
Check 'digest: identical corpus+records -> identical digest across fresh dbs' ($dgB -eq $recDigest) "B=$dgB expected=$recDigest"

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
