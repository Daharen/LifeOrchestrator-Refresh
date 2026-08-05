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
Check 'manifest version=0.6.0' ($man.version -eq '0.6.0')
Check 'manifest contract_version=0.6' ($man.contract_version -eq '0.6')
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
# migrate op is the FIRST op to touch the v1 db (so it reports the migration actions); 0.4 chains 1->2->3->4
$mg = Payload (Run-AS @{ op='migrate'; db=$v1db })
Check 'migrate: schema_version 1 -> 5 in place (chained), migrated=true' ($null -ne $mg -and [bool]$mg.migrated -and [string]$mg.schema_version -eq '5')
Check 'migrate: reports from:1 + the A4 + A5 reserved-seam actions' ($null -ne $mg -and (@($mg.migration_actions) -contains 'from:1') -and (@($mg.migration_actions | Where-Object { $_ -match 'reserve_a4' }).Count -ge 1) -and (@($mg.migration_actions | Where-Object { $_ -match 'reserve_a5' }).Count -ge 1))
Check 'migrate: integrity ok + NO chunk loss' ($null -ne $mg -and [bool]$mg.integrity.ok -and [int]$mg.counts.chunks -eq $v1chunks) "chunks=$($mg.counts.chunks) v1=$v1chunks"
Check 'migrate: chunk_embeddings JSON retired -> float32 BLOB vectors (count preserved)' ([int]$mg.counts.embeddings -eq $v1emb) "emb=$($mg.counts.embeddings) v1=$v1emb"
$mg2 = Payload (Run-AS @{ op='migrate'; db=$v1db })
Check 'migrate: idempotent (second migrate is a no-op)' ($null -ne $mg2 -and (-not [bool]$mg2.migrated) -and [string]$mg2.schema_version -eq '5')
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

# ================= 0.3 (MEMORY_CONTRACT Amendment A4 / D-0092 Tier-0 seams) additions =================

# ---------- 25) A4/U1 GATE TEST 1: namespace is a HARD retrieval boundary (+ all-hits-match assertion) ----------
$nsdb = Join-Path $tmpRoot 'ns.db'
$recsA = @( [ordered]@{ record_id='a.1'; record_version_id='a.1@1'; record_kind='claim'; namespace='ns-a'; text='OVERLAP_TOKEN alpha claim in A' } )
$recsB = @( [ordered]@{ record_id='b.1'; record_version_id='b.1@1'; record_kind='claim'; namespace='ns-b'; text='OVERLAP_TOKEN beta claim in B' } )
Run-AS @{ op='ingest-records'; db=$nsdb; ingest_run=@{ producer='p' }; records=$recsA } | Out-Null
Run-AS @{ op='ingest-records'; db=$nsdb; ingest_run=@{ producer='p' }; records=$recsB } | Out-Null
# two ingested SOURCES sharing a chunk token (a chunk's namespace == its source_id)
$nsSrcA = Join-Path $tmpRoot 'nsSrcA'; $nsSrcB = Join-Path $tmpRoot 'nsSrcB'
New-Item -ItemType Directory -Path $nsSrcA -Force | Out-Null; New-Item -ItemType Directory -Path $nsSrcB -Force | Out-Null
Set-Content -LiteralPath (Join-Path $nsSrcA 'f.md') -Value "# A`n`nCHUNKOVERLAP token in source A`n"
Set-Content -LiteralPath (Join-Path $nsSrcB 'f.md') -Value "# B`n`nCHUNKOVERLAP token in source B`n"
Run-AS @{ op='ingest'; source='ns-a'; root=$nsSrcA; db=$nsdb } | Out-Null
Run-AS @{ op='ingest'; source='ns-b'; root=$nsSrcB; db=$nsdb } | Out-Null
# a no-namespace query returns BOTH namespaces
$allq = Payload (Run-AS @{ op='search'; query='OVERLAP_TOKEN'; mode='fts'; k=10; db=$nsdb })
$nsAll = @(@($allq.results) | ForEach-Object { [string]$_.namespace } | Select-Object -Unique)
Check 'A4/U1: no-namespace query returns BOTH namespaces' (($nsAll -contains 'ns-a') -and ($nsAll -contains 'ns-b')) "seen=$($nsAll -join ',')"
# scoped to ns-a returns ZERO ns-b hits (the hard boundary)
$qa = Payload (Run-AS @{ op='search'; query='OVERLAP_TOKEN'; mode='fts'; k=10; db=$nsdb; filters=@{ namespace='ns-a' } })
$qaNs = @(@($qa.results) | ForEach-Object { [string]$_.namespace })
Check 'A4/U1: scoped ns-a returns >=1 hit, ALL namespace==ns-a (zero ns-b leakage)' ([int]$qa.count -ge 1 -and (@($qaNs | Where-Object { $_ -ne 'ns-a' }).Count -eq 0)) "ns=$($qaNs -join ',')"
Check 'A4/U1: filter_decisions.namespace_enforced true when scoped' ([bool](@($qa.results)[0].filter_decisions.namespace_enforced))
# an explicit SET returns both
$qset = Payload (Run-AS @{ op='search'; query='OVERLAP_TOKEN'; mode='fts'; k=10; db=$nsdb; filters=@{ namespace=@('ns-a','ns-b') } })
$qsetNs = @(@($qset.results) | ForEach-Object { [string]$_.namespace } | Select-Object -Unique)
Check 'A4/U1: explicit set {ns-a,ns-b} returns both' (($qsetNs -contains 'ns-a') -and ($qsetNs -contains 'ns-b')) "ns=$($qsetNs -join ',')"
# chunk-namespace: scoped to ns-a returns zero ns-b chunk hits
$qc = Payload (Run-AS @{ op='search'; query='CHUNKOVERLAP'; mode='fts'; k=10; db=$nsdb; filters=@{ namespace='ns-a' } })
$qcNs = @(@($qc.results) | ForEach-Object { [string]$_.namespace })
Check 'A4/U1(chunks): scoped ns-a returns only ns-a chunk hits' ([int]$qc.count -ge 1 -and (@($qcNs | Where-Object { $_ -ne 'ns-a' }).Count -eq 0)) "ns=$($qcNs -join ',')"

# ---------- 26) A4/U4: current_only retrieval MODE (superseded twin) ----------
$codb = Join-Path $tmpRoot 'co.db'
Run-AS @{ op='ingest'; source='co'; root=$fixtureRepo; db=$codb } | Out-Null
$coVer = [string](@((Payload (Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$codb })).results)[0].source_version_id)
$twins = @(
  [ordered]@{ record_id='sum.cur'; record_version_id='sum.cur@1'; record_kind='summary'; namespace='co'; text='TWIN_TOKEN current summary'; source_version_id=$coVer; status='current' },
  [ordered]@{ record_id='sum.old'; record_version_id='sum.old@1'; record_kind='summary'; namespace='co'; text='TWIN_TOKEN superseded summary'; source_version_id=$coVer; status='source_stale' }
)
Run-AS @{ op='ingest-records'; db=$codb; ingest_run=@{ producer='p'; namespace='co' }; records=$twins } | Out-Null
Check 'A4/U4: default mode returns BOTH twins' ([int](Payload (Run-AS @{ op='search'; query='TWIN_TOKEN'; mode='exact'; db=$codb; filters=@{ record_kind='summary' } })).count -eq 2)
$conly = Payload (Run-AS @{ op='search'; query='TWIN_TOKEN'; mode='exact'; db=$codb; filters=@{ record_kind='summary'; mode='current_only' } })
Check 'A4/U4: filters.mode=current_only returns ONLY the current twin' ([int]$conly.count -eq 1 -and [string](@($conly.results)[0].status) -eq 'current') "count=$($conly.count)"
$conly2 = Payload (Run-AS @{ op='search'; query='TWIN_TOKEN'; mode='current_only'; db=$codb; filters=@{ record_kind='summary' } })
Check 'A4/U4: top-level mode=current_only shim works (lexical backend fts)' ([int]$conly2.count -eq 1 -and [string]$conly2.mode -eq 'fts')

# ---------- 27) A4/U3: working-memory record isolation (task-scoped only) ----------
$wkdb = Join-Path $tmpRoot 'wk.db'
Run-AS @{ op='ingest'; source='w'; root=$fixtureRepo; db=$wkdb } | Out-Null
$work = @(
  [ordered]@{ record_id='wk.t1'; record_version_id='wk.t1@1'; record_kind='working'; namespace='w'; task_id='task-1'; text='WORKING_TOKEN state for task 1' },
  [ordered]@{ record_id='wk.t2'; record_version_id='wk.t2@1'; record_kind='working'; namespace='w'; attrs=@{ task_id='task-2' }; text='WORKING_TOKEN state for task 2' },
  [ordered]@{ record_id='wk.bad'; record_version_id='wk.bad@1'; record_kind='working'; namespace='w'; text='WORKING_TOKEN no task id' }
)
$wr = Payload (Run-AS @{ op='ingest-records'; db=$wkdb; ingest_run=@{ producer='p'; namespace='w' }; records=$work })
Check 'A4/U3: working without task_id rejected (working_requires_task_id)' ([int]$wr.counts.accepted -eq 2 -and (@($wr.rejected | ForEach-Object { [string]$_.reason }) -contains 'working_requires_task_id')) "counts=$($wr.counts | ConvertTo-Json -Compress)"
Check 'A4/U3: ordinary retrieval EXCLUDES working records' ([int](Payload (Run-AS @{ op='search'; query='WORKING_TOKEN'; mode='exact'; db=$wkdb })).count -eq 0)
# A5/U3': working access is CONJUNCTIVE -- a task_id ALONE (no in-scope namespace authorization) is too weak.
Check 'A5/U3prime: task_id ALONE (no namespace) still EXCLUDES working' ([int](Payload (Run-AS @{ op='search'; query='WORKING_TOKEN'; mode='exact'; db=$wkdb; filters=@{ task_id='task-1' } })).count -eq 0)
$t1 = Payload (Run-AS @{ op='search'; query='WORKING_TOKEN'; mode='exact'; db=$wkdb; filters=@{ task_id='task-1'; namespace='w' } })
Check 'A5/U3prime: task_id AND in-scope namespace surfaces ONLY that task_id' ([int]$t1.count -eq 1 -and [string](@($t1.results)[0].record_version_id) -eq 'wk.t1@1') "count=$($t1.count)"
Check 'A4/U3: list-records(working) without scope returns none' ([int](Payload (Run-AS @{ op='list-records'; db=$wkdb; filters=@{ record_kind='working' } })).count -eq 0)
Check 'A4/U3: list-records(working, task-2) returns only task-2' ([int](Payload (Run-AS @{ op='list-records'; db=$wkdb; filters=@{ record_kind='working'; task_id='task-2' } })).count -eq 1)

# ---------- 28) A4/U2 GATE TEST 2: schema-evolution (v2->v3; node+edges additive; shipped tables byte-identical) ----------
$v2worker = Join-Path $SkillDir 'fixtures/artifact_search_v2.py'
Check 'A4/U2: frozen shipped-0.2 worker fixture present' (Test-Path -LiteralPath $v2worker -PathType Leaf)
# a fresh v3 db -> the EXPECTED shipped-tables schema sha (unchanged by a 2->3 migration)
$freshv3 = Join-Path $tmpRoot 'fresh_v3.db'
Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$freshv3 } | Out-Null
$freshSha = [string](Payload (Run-AS @{ op='catalog'; db=$freshv3 })).shipped_tables_schema_sha
Check 'A4/U2: fresh v3 exposes shipped_tables_schema_sha (64 hex)' ($freshSha -match '^[0-9a-f]{64}$')
# build a v2 seed db with the FROZEN v2 worker (mirrors the v1 migration fixture)
$v2db = Join-Path $tmpRoot 'v2seed.db'
$v2args = Join-Path $tmpRoot 'v2args.json'; $v2meta = Join-Path $tmpRoot 'v2meta.json'
[System.IO.File]::WriteAllText($v2args, ([ordered]@{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$v2db; meta_path=$v2meta; output_dir=(Join-Path $tmpRoot 'v2out') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v2worker $v2args 2>$null | Out-Null
$v2m = $null; try { $v2m = (Get-Content -LiteralPath $v2meta -Raw) | ConvertFrom-Json } catch { }
Check 'A4/U2: v2 seed db built at schema_version 2' ($null -ne $v2m -and [bool]$v2m.ok -and [string]$v2m.worker.schema_version -eq '2')
$v2chunks = [int]$v2m.result.counts_total.chunks
# migrate v2 -> v3 in place (additive; no shipped-table rewrite)
$mg3 = Payload (Run-AS @{ op='migrate'; db=$v2db })
Check 'A4/U2: migrate 2 -> 5 in place (chained 2->3->4->5), migrated=true' ($null -ne $mg3 -and [bool]$mg3.migrated -and [string]$mg3.schema_version -eq '5')
Check 'A4/U2: migrate reports from:2 + the A4 + A5 reserved-seam actions' ((@($mg3.migration_actions) -contains 'from:2') -and (@($mg3.migration_actions | Where-Object { $_ -match 'reserve_a4' }).Count -ge 1) -and (@($mg3.migration_actions | Where-Object { $_ -match 'reserve_a5' }).Count -ge 1)) "acts=$($mg3.migration_actions -join ',')"
Check 'A4/U2: NO chunk loss across 2->4 migration' ([int]$mg3.counts.chunks -eq $v2chunks) "chunks=$($mg3.counts.chunks) v2=$v2chunks"
Check 'A4/U2: shipped tables BYTE-IDENTICAL pre/post (migrated sha == fresh v4 sha)' ([string]$mg3.shipped_tables_schema_sha -eq $freshSha) "migrated=$($mg3.shipped_tables_schema_sha) fresh=$freshSha"
Check 'A4/U2: migrate integrity ok' ([bool]$mg3.integrity.ok)
# INGEST a node record + member_of_node (record->node) + child_of_node (node->node) + contradicts edges
$ndVer = [string](@((Payload (Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$v2db })).results)[0].source_version_id)
$nodeRecs = @(
  [ordered]@{ record_id='nd.root'; record_version_id='nd.root@1'; record_kind='node'; namespace='fixture'; text='NODE_TOKEN root navigation node'; attrs=@{ synopsis='root'; child_ids=@('nd.child@1') }; edges=@(@{ edge_kind='child_of_node'; dst_ref='nd.child@1'; dst_kind='record' }) },
  [ordered]@{ record_id='nd.child'; record_version_id='nd.child@1'; record_kind='node'; namespace='fixture'; text='NODE_TOKEN child navigation node'; attrs=@{ synopsis='child' } },
  [ordered]@{ record_id='mem.sym'; record_version_id='mem.sym@1'; record_kind='symbol'; namespace='fixture'; text='NODE_MEMBER_TOKEN a member symbol'; source_version_id=$ndVer; edges=@(@{ edge_kind='member_of_node'; dst_ref='nd.child@1'; dst_kind='record' }, @{ edge_kind='contradicts'; dst_ref='mem.other@1'; dst_kind='record' }) }
)
$nr = Payload (Run-AS @{ op='ingest-records'; db=$v2db; ingest_run=@{ producer='repo.intel'; namespace='fixture' }; records=$nodeRecs })
Check 'A4/U2: node + edges ingest additively (3 accepted, 0 rejected)' ([int]$nr.counts.accepted -eq 3 -and [int]$nr.counts.rejected -eq 0) "counts=$($nr.counts | ConvertTo-Json -Compress)"
Check 'A4/U2: integrity ok after node ingest on migrated db' ([bool]$nr.integrity_ok)
# node RETRIEVES through the normal envelope (list-records) + the retriever hit shape (search)
$ln = Payload (Run-AS @{ op='list-records'; db=$v2db; filters=@{ record_kind='node' } })
Check 'A4/U2: node retrievable via envelope (2 nodes, all record_kind=node)' ([int]$ln.count -eq 2 -and (@($ln.records | Where-Object { [string]$_.record_kind -ne 'node' }).Count -eq 0))
$ndRoot = @($ln.records | Where-Object { [string]$_.record_id -eq 'nd.root' })[0]
Check 'A4/U2: node envelope carries the child_of_node edge' (@($ndRoot.parent_edges | Where-Object { [string]$_.edge_kind -eq 'child_of_node' }).Count -ge 1)
$sn = @((Payload (Run-AS @{ op='search'; query='NODE_TOKEN'; mode='fts'; db=$v2db; filters=@{ record_kind='node' } })).results)[0]
Check 'A4/U2: node retrievable via retriever hit shape (span + fused_score)' ($null -ne $sn -and [string]$sn.record_kind -eq 'node' -and (Has $sn 'span') -and (Has $sn 'fused_score'))
$mem = @((Payload (Run-AS @{ op='list-records'; db=$v2db; filters=@{ record_kind='symbol' } })).records | Where-Object { [string]$_.record_id -eq 'mem.sym' })[0]
$memEdges = @(@($mem.parent_edges) | ForEach-Object { [string]$_.edge_kind })
Check 'A4/U2: member_of_node + contradicts edges materialized' (($memEdges -contains 'member_of_node') -and ($memEdges -contains 'contradicts')) "edges=$($memEdges -join ',')"
# re-ingest idempotent (digest stable)
$predig = [string](Payload (Run-AS @{ op='catalog'; db=$v2db })).digest
Run-AS @{ op='ingest-records'; db=$v2db; ingest_run=@{ producer='repo.intel'; namespace='fixture' }; records=$nodeRecs } | Out-Null
Check 'A4/U2: node re-ingest idempotent (digest stable)' ([string](Payload (Run-AS @{ op='catalog'; db=$v2db })).digest -eq $predig)

# ================= 0.4 (MEMORY_CONTRACT Amendment A5 / D-0096 Tier-0 NAMESPACE-CLOSURE + SUPERSESSION) =====

# ---------- 29) A5/U1' GATE TEST 1: namespace CLOSURE (per-hop + derived + diagnostic + ingest rejection) ----------
$g1 = Join-Path $tmpRoot 'a5g1.db'
$g1recs = @(
  [ordered]@{ record_id='ca.1'; record_version_id='ca.1@1'; record_kind='claim'; namespace='ns-a'; text='OVERLAP_A5 alpha claim in A' },
  [ordered]@{ record_id='cb.1'; record_version_id='cb.1@1'; record_kind='claim'; namespace='ns-b'; text='OVERLAP_A5 beta claim in B' }
)
$g1r = Payload (Run-AS @{ op='ingest-records'; db=$g1; ingest_run=@{ producer='p' }; records=$g1recs })
Check 'A5/U1prime: mixed-ns fixture ingested (2 accepted)' ([int]$g1r.counts.accepted -eq 2) "counts=$($g1r.counts | ConvertTo-Json -Compress)"
$qa5 = Payload (Run-AS @{ op='search'; query='OVERLAP_A5'; mode='fts'; k=10; db=$g1; filters=@{ namespace='ns-a' } })
$qa5ns = @(@($qa5.results) | ForEach-Object { [string]$_.namespace })
Check 'A5/U1prime: scoped ns-a returns >=1 hit, ZERO ns-b leakage' ([int]$qa5.count -ge 1 -and (@($qa5ns | Where-Object { $_ -ne 'ns-a' }).Count -eq 0)) "ns=$($qa5ns -join ',')"
Check 'A5/U1prime: namespace_violation_count >=1 surfaces (ns-b excluded)' ([int]$qa5.namespace_violation_count -ge 1) "count=$($qa5.namespace_violation_count)"
# ONLY the sanitized COUNT surfaces -- NO ns-b identifying data anywhere in the serialized result (incl every diagnostic array)
$blob = ($qa5 | ConvertTo-Json -Depth 40 -Compress)
Check 'A5/U1prime: NO ns-b identifying metadata in output (hits + diagnostics sanitized)' (($blob -notmatch 'ns-b') -and ($blob -notmatch 'cb\.1')) "leak in output"
Check 'A5/U1prime: filter_decisions carries only the count (no rejected-candidate detail)' ($null -ne (@($qa5.results)[0].filter_decisions.namespace_violation_count))
# (c) a DERIVED record whose provenance spans a foreign namespace is REJECTED at ingest (fail-closed)
$derv = Payload (Run-AS @{ op='ingest-records'; db=$g1; ingest_run=@{ producer='p' }; records=@(
  [ordered]@{ record_id='lnd'; record_version_id='lnd@1'; record_kind='summary'; namespace='ns-a'; text='launder attempt'; derivation_refs=@('cb.1@1') }) })
Check 'A5/U1prime: cross-namespace DERIVATION rejected at ingest' (@($derv.rejected | ForEach-Object { [string]$_.reason }) -contains 'cross_namespace_derivation') "rej=$($derv.rejected | ConvertTo-Json -Compress -Depth 6)"
# (c2) a cross-namespace SUPERSESSION edge (resolvable) is likewise rejected at ingest
$xsup = Payload (Run-AS @{ op='ingest-records'; db=$g1; ingest_run=@{ producer='p' }; records=@(
  [ordered]@{ record_id='xs'; record_version_id='xs@1'; record_kind='claim'; namespace='ns-a'; text='xs'; edges=@(@{ edge_kind='superseded_by'; dst_ref='cb.1@1'; dst_kind='record' }) }) })
Check 'A5/U1prime: cross-namespace SUPERSESSION edge rejected at ingest' (@($xsup.rejected | ForEach-Object { [string]$_.reason }) -contains 'cross_namespace_derivation')
# (d) per-hop WALK guard: a forward-ref cross-ns successor that slipped in as an unresolved ref is IGNORED per-hop
$g1b = Join-Path $tmpRoot 'a5g1b.db'
Run-AS @{ op='ingest-records'; db=$g1b; ingest_run=@{ producer='p' }; records=@(
  [ordered]@{ record_id='hop'; record_version_id='hop@1'; record_kind='claim'; namespace='ns-a'; status='current'; text='HOPTOKEN a5 predecessor';
              edges=@(@{ edge_kind='superseded_by'; dst_ref='ghost@1'; dst_kind='record' }) }) } | Out-Null
Run-AS @{ op='ingest-records'; db=$g1b; ingest_run=@{ producer='p' }; records=@(
  [ordered]@{ record_id='ghost'; record_version_id='ghost@1'; record_kind='claim'; namespace='ns-b'; status='current'; text='GHOSTONLY successor in B' }) } | Out-Null
$hop = Payload (Run-AS @{ op='search'; query='HOPTOKEN'; mode='exact'; db=$g1b; filters=@{ namespace='ns-a'; mode='current_only' } })
Check 'A5/U1prime: cross-ns successor IGNORED per-hop (predecessor stays effective_current under scope)' ([int]$hop.count -eq 1 -and [bool](@($hop.results)[0].effective_current)) "count=$($hop.count)"
Check 'A5/U1prime: per-hop walk leaks NO ns-b data' ((($hop | ConvertTo-Json -Depth 40 -Compress) -notmatch 'ns-b') -and (($hop | ConvertTo-Json -Depth 40 -Compress) -notmatch 'ghost'))

# ---------- 30) A5/U4' GATE TEST 2: POOL-INDEPENDENT current_only (superseded even when successor is ABSENT) ----------
$g2 = Join-Path $tmpRoot 'a5g2.db'
# predecessor matches PRETOKEN; successor matches SUCTOKEN (disjoint) so the successor is ABSENT from a PRETOKEN pool
$g2recs = @(
  [ordered]@{ record_id='pre'; record_version_id='pre@1'; record_kind='summary'; namespace='co'; status='current'; text='PRETOKEN predecessor summary';
              edges=@(@{ edge_kind='superseded_by'; dst_ref='suc@1'; dst_kind='record' }) },
  [ordered]@{ record_id='suc'; record_version_id='suc@1'; record_kind='summary'; namespace='co'; status='current'; text='SUCTOKEN successor summary' }
)
Run-AS @{ op='ingest-records'; db=$g2; ingest_run=@{ producer='p'; namespace='co' }; records=$g2recs } | Out-Null
$g2def = Payload (Run-AS @{ op='search'; query='PRETOKEN'; mode='exact'; db=$g2 })
Check 'A5/U4prime: default mode returns the predecessor' ([int]$g2def.count -eq 1 -and [string](@($g2def.results)[0].record_version_id) -eq 'pre@1') "count=$($g2def.count)"
$g2co = Payload (Run-AS @{ op='search'; query='PRETOKEN'; mode='exact'; db=$g2; filters=@{ mode='current_only' } })
Check 'A5/U4prime: current_only EXCLUDES the predecessor EVEN WHEN its successor is ABSENT from the pool' ([int]$g2co.count -eq 0) "count=$($g2co.count)"
$g2cs = Payload (Run-AS @{ op='search'; query='SUCTOKEN'; mode='exact'; db=$g2; filters=@{ mode='current_only' } })
Check 'A5/U4prime: the live successor IS effective_current' ([int]$g2cs.count -eq 1 -and [bool](@($g2cs.results)[0].effective_current))
# branch: two live successors of one predecessor -> conflicted flagged (surfaced, never a silent pick)
$g2b = Join-Path $tmpRoot 'a5g2b.db'
Run-AS @{ op='ingest-records'; db=$g2b; ingest_run=@{ producer='p'; namespace='co' }; records=@(
  [ordered]@{ record_id='br'; record_version_id='br@1'; record_kind='summary'; namespace='co'; status='current'; text='BRANCHTOKEN root';
              edges=@(@{ edge_kind='superseded_by'; dst_ref='s1@1'; dst_kind='record' }, @{ edge_kind='superseded_by'; dst_ref='s2@1'; dst_kind='record' }) },
  [ordered]@{ record_id='s1'; record_version_id='s1@1'; record_kind='summary'; namespace='co'; status='current'; text='BRANCHTOKEN successor one' },
  [ordered]@{ record_id='s2'; record_version_id='s2@1'; record_kind='summary'; namespace='co'; status='current'; text='BRANCHTOKEN successor two' }) } | Out-Null
$brh = @((Payload (Run-AS @{ op='search'; query='BRANCHTOKEN'; mode='exact'; db=$g2b })).results | Where-Object { [string]$_.record_version_id -eq 'br@1' })[0]
Check 'A5/U4prime: a branch (>=2 live successors) is FLAGGED conflicted (surfaced)' ([bool]$brh.supersession_conflicted) "conflicted=$($brh.supersession_conflicted)"
# integrity: cross-namespace supersession + cycle checks are present + pass on a clean db
$g2int = Payload (Run-AS @{ op='integrity'; db=$g2 })
Check 'A5/U4prime: integrity includes no_cross_namespace_supersession (passes on clean db)' ((@($g2int.checks | Where-Object { [string]$_.name -eq 'no_cross_namespace_supersession' -and [bool]$_.ok }).Count -eq 1))
Check 'A5/U4prime: integrity includes supersession_chain_acyclic (passes on clean db)' ((@($g2int.checks | Where-Object { [string]$_.name -eq 'supersession_chain_acyclic' -and [bool]$_.ok }).Count -eq 1))

# ---------- 31) A5/U3' GATE TEST 3: working search-rejection (conjunctive task_id + in-scope namespace) ----------
# (core coverage in section 27; here the exact-op path proves list-records is NOT ordinary search)
$g3 = Join-Path $tmpRoot 'a5g3.db'
Run-AS @{ op='ingest-records'; db=$g3; ingest_run=@{ producer='p'; namespace='wns' }; records=@(
  [ordered]@{ record_id='wk'; record_version_id='wk@1'; record_kind='working'; namespace='wns'; task_id='T9'; text='WK9TOKEN working state';
              state_version='3'; parent_state_version='2'; writer_authority='task-agent' }) } | Out-Null
Check 'A5/U3prime: ordinary search never returns a working record' ([int](Payload (Run-AS @{ op='search'; query='WK9TOKEN'; mode='exact'; db=$g3 })).count -eq 0)
Check 'A5/U3prime: conjunctive (task_id + namespace) EXACT op surfaces the working record' ([int](Payload (Run-AS @{ op='search'; query='WK9TOKEN'; mode='exact'; db=$g3; filters=@{ task_id='T9'; namespace='wns' } })).count -eq 1)
$we2 = @((Payload (Run-AS @{ op='list-records'; db=$g3; filters=@{ record_kind='working'; task_id='T9' } })).records)[0]
Check 'A5/U3prime: working envelope reserves the store fields (state_version/writer_authority)' ([string]$we2.state_version -eq '3' -and [string]$we2.writer_authority -eq 'task-agent' -and [string]$we2.lifecycle_state -eq 'active')

# ---------- 32) A5/U2' provenance_mode-conditional hit shape + candidate_role + retrieval-stage lineage ----------
$g4 = Join-Path $tmpRoot 'a5g4.db'
Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$g4 } | Out-Null
Run-AS @{ op='ingest-records'; db=$g4; ingest_run=@{ producer='p'; namespace='fixture' }; records=@(
  [ordered]@{ record_id='nd2'; record_version_id='nd2@1'; record_kind='node'; namespace='fixture'; text='NAV2TOKEN navigation node'; attrs=@{ synopsis='s' } },
  [ordered]@{ record_id='sup2'; record_version_id='sup2@1'; record_kind='claim'; namespace='fixture'; status='superseded'; text='SUP2TOKEN a superseded claim' }) } | Out-Null
$chit = @((Payload (Run-AS @{ op='search'; query='QUOKKA_MARKER_7'; mode='exact'; k=1; db=$g4 })).results)[0]
Check 'A5/U2prime: source_chunk hit provenance_mode=direct_span' ([string]$chit.provenance_mode -eq 'direct_span' -and [string]$chit.candidate_role -eq 'evidence')
Check 'A5/U2prime: hit reserves retrieval-stage lineage (retrieval_stage_id + null plan/parent)' ((Has $chit 'retrieval_stage_id') -and (Has $chit 'parent_stage_id') -and (Has $chit 'retrieval_plan_id') -and [string]$chit.retrieval_stage_id -ne '')
Check 'A5/U2prime: hit provenance block carries the per-mode fields' ((Has $chit 'provenance') -and [string]$chit.provenance.mode -eq 'direct_span')
$nhit = @((Payload (Run-AS @{ op='search'; query='NAV2TOKEN'; mode='exact'; db=$g4; filters=@{ record_kind='node' } })).results)[0]
Check 'A5/U2prime: node hit candidate_role=navigation + provenance_mode=aggregate' ([string]$nhit.candidate_role -eq 'navigation' -and [string]$nhit.provenance_mode -eq 'aggregate')
Check 'A5/U2prime: superseded is a first-class s5 status (accepted + queryable)' ([int](Payload (Run-AS @{ op='search'; query='SUP2TOKEN'; mode='exact'; db=$g4; filters=@{ status='superseded' } })).count -eq 1)

# ---------- 33) A5 GATE: schema_version 3 -> 4 additive in-place migration (shipped tables byte-identical) ----------
$v3worker = Join-Path $SkillDir 'fixtures/artifact_search_v3.py'
Check 'A5: frozen shipped-0.3 (v3) worker fixture present' (Test-Path -LiteralPath $v3worker -PathType Leaf)
$freshv4 = Join-Path $tmpRoot 'fresh_v4.db'
Run-AS @{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$freshv4 } | Out-Null
$freshSha4 = [string](Payload (Run-AS @{ op='catalog'; db=$freshv4 })).shipped_tables_schema_sha
$v3db = Join-Path $tmpRoot 'v3seed.db'
$v3args = Join-Path $tmpRoot 'v3args.json'; $v3meta = Join-Path $tmpRoot 'v3meta.json'
[System.IO.File]::WriteAllText($v3args, ([ordered]@{ op='ingest'; source='fixture'; root=$fixtureRepo; db=$v3db; meta_path=$v3meta; output_dir=(Join-Path $tmpRoot 'v3out') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v3worker $v3args 2>$null | Out-Null
$v3m = $null; try { $v3m = (Get-Content -LiteralPath $v3meta -Raw) | ConvertFrom-Json } catch { }
Check 'A5: v3 seed db built at schema_version 3' ($null -ne $v3m -and [bool]$v3m.ok -and [string]$v3m.worker.schema_version -eq '3')
# a typed record into the v3 seed (via the frozen v3 worker) so the migration preserves records too
$v3rargs = Join-Path $tmpRoot 'v3rargs.json'; $v3rmeta = Join-Path $tmpRoot 'v3rmeta.json'
[System.IO.File]::WriteAllText($v3rargs, ([ordered]@{ op='ingest-records'; db=$v3db; ingest_run=@{ producer='repo.intel'; namespace='fixture' }; records=@([ordered]@{ record_id='sy3'; record_version_id='sy3@1'; record_kind='symbol'; namespace='fixture'; text='SY3TOKEN sym' }); meta_path=$v3rmeta; output_dir=(Join-Path $tmpRoot 'v3rout') } | ConvertTo-Json -Depth 10), $utf8)
& $PythonPath $v3worker $v3rargs 2>$null | Out-Null
# capture the v3 baseline with the FROZEN v3 worker (opening the v3 db with the NEW worker would migrate it in
# place BEFORE the migrate op runs). migrate must be the FIRST new-worker op to touch the v3 db.
$v3cargs = Join-Path $tmpRoot 'v3cargs.json'; $v3cmeta = Join-Path $tmpRoot 'v3cmeta.json'
[System.IO.File]::WriteAllText($v3cargs, ([ordered]@{ op='catalog'; db=$v3db; meta_path=$v3cmeta; output_dir=(Join-Path $tmpRoot 'v3cout') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v3worker $v3cargs 2>$null | Out-Null
$v3cm = $null; try { $v3cm = (Get-Content -LiteralPath $v3cmeta -Raw) | ConvertFrom-Json } catch { }
$v3cat = $v3cm.result; $v3digest = [string]$v3cat.digest; $v3chunks = [int]$v3cat.counts.chunks; $v3recs = [int]$v3cat.counts.records
Check 'A5: v3 baseline read at schema_version 3 (frozen worker)' ([string]$v3cat.schema_version -eq '3') "sv=$($v3cat.schema_version)"
$mg4 = Payload (Run-AS @{ op='migrate'; db=$v3db })
Check 'A5: migrate 3 -> 5 in place, migrated=true' ($null -ne $mg4 -and [bool]$mg4.migrated -and [string]$mg4.schema_version -eq '5')
Check 'A5: migrate reports from:3 + reserve_a5 action' ((@($mg4.migration_actions) -contains 'from:3') -and (@($mg4.migration_actions | Where-Object { $_ -match 'reserve_a5' }).Count -ge 1)) "acts=$($mg4.migration_actions -join ',')"
Check 'A5: NO chunk loss across 3->4' ([int]$mg4.counts.chunks -eq $v3chunks) "chunks=$($mg4.counts.chunks) v3=$v3chunks"
Check 'A5: NO record loss across 3->4' ([int]$mg4.counts.records -eq $v3recs) "recs=$($mg4.counts.records) v3=$v3recs"
Check 'A5: shipped tables BYTE-IDENTICAL pre/post 3->4 (migrated sha == fresh v4 sha)' ([string]$mg4.shipped_tables_schema_sha -eq $freshSha4) "migrated=$($mg4.shipped_tables_schema_sha) fresh=$freshSha4"
Check 'A5: catalog_digest UNCHANGED across 3->4 (no re-ingest)' ([string]$mg4.catalog_digest -eq $v3digest) "post=$($mg4.catalog_digest) pre=$v3digest"
Check 'A5: migrate 3->4 integrity ok' ([bool]$mg4.integrity.ok)
$mg4b = Payload (Run-AS @{ op='migrate'; db=$v3db })
Check 'A5: 3->5 migration idempotent (re-open is a no-op)' ((-not [bool]$mg4b.migrated) -and [string]$mg4b.schema_version -eq '5')
Check 'A5: shipped search regression-green on the 3->4 migrated db' ([int](Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; db=$v3db })).count -ge 1)

# ---------- 34) A5 determinism: double-run byte-identical catalog_digest WITH supersession edges ----------
$dd1 = Join-Path $tmpRoot 'a5d1.db'; $dd2 = Join-Path $tmpRoot 'a5d2.db'
$ddrecs = @(
  [ordered]@{ record_id='d1'; record_version_id='d1@1'; record_kind='summary'; namespace='d'; status='current'; text='det one'; edges=@(@{ edge_kind='superseded_by'; dst_ref='d2@1'; dst_kind='record' }) },
  [ordered]@{ record_id='d2'; record_version_id='d2@1'; record_kind='summary'; namespace='d'; status='current'; text='det two' }
)
Run-AS @{ op='ingest-records'; db=$dd1; ingest_run=@{ producer='p'; namespace='d' }; records=$ddrecs } | Out-Null
Run-AS @{ op='ingest-records'; db=$dd2; ingest_run=@{ producer='p'; namespace='d' }; records=$ddrecs } | Out-Null
Check 'A5: identical corpus (with supersession) -> identical catalog_digest across fresh dbs' ([string](Payload (Run-AS @{ op='catalog'; db=$dd1 })).digest -eq [string](Payload (Run-AS @{ op='catalog'; db=$dd2 })).digest)

# ================= 0.5 (MEMORY_CONTRACT Amendment A6 / D-0098 Tier-1 BOUNDED-FANOUT HIERARCHY) =====
Write-Host "--- A6 (D-0098) bounded-fanout hierarchy ---"
$hsrc = Join-Path $tmpRoot 'hsrc'
New-Item -ItemType Directory -Path (Join-Path $hsrc 'docs') -Force | Out-Null
foreach ($i in 0..11) { [System.IO.File]::WriteAllText((Join-Path $hsrc "docs/f$i.md"), "# H$i`n`nalpha$i frobnicator beta gamma`n", $utf8) }
$hdb = Join-Path $tmpRoot 'hier.db'
Run-AS @{ op='ingest'; source='projA'; root=$hsrc; db=$hdb; embed_provider='mock' } | Out-Null
Run-AS @{ op='ingest-records'; db=$hdb; ingest_run=@{ producer='t'; namespace='projB' }; records=@([ordered]@{ record_id='b1'; record_version_id='b1@1'; record_kind='decision'; namespace='projB'; text='projb decision zeta' }) } | Out-Null
$digBefore = [string](Payload (Run-AS @{ op='catalog'; db=$hdb })).digest
$sBefore = Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; db=$hdb; k=50 })
Check 'A6: flat search returns NO node records (pre-build)' (@($sBefore.results | Where-Object { $_.record_kind -eq 'node' }).Count -eq 0)

$bh = Payload (Run-AS @{ op='build-hierarchy'; db=$hdb; max_fanout=2 })
Check 'A6: build-hierarchy ok + all_valid' ($null -ne $bh -and [bool]$bh.all_valid)
Check 'A6: two separate hierarchies built (projA + projB, separate roots)' (@($bh.built).Count -ge 2)
$hA = @($bh.built | Where-Object { $_.namespace -eq 'proja' })[0]
Check 'A6: projA has a root + tree_digest + multi-level (depth>=2)' ($null -ne $hA -and $hA.root_node_id -and $hA.tree_digest -and [int]$hA.depth -ge 2) "depth=$($hA.depth)"
Check 'A6: catalog_digest UNCHANGED by the build (node edges excluded; corpus stable)' ([string](Payload (Run-AS @{ op='catalog'; db=$hdb })).digest -eq $digBefore)
Check 'A6: schema_version 5 after build' ([string](Payload (Run-AS @{ op='catalog'; db=$hdb })).schema_version -eq '5')
Check 'A6: integrity all green (incl hierarchy invariants)' ([bool](Payload (Run-AS @{ op='integrity'; db=$hdb })).ok)
$sAfter = Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; db=$hdb; k=50 })
Check 'A6: flat search count identical after build (flat retrieval unaffected)' (@($sAfter.results).Count -eq @($sBefore.results).Count)

$bh2 = Payload (Run-AS @{ op='build-hierarchy'; db=$hdb; max_fanout=2 })
$hA2 = @($bh2.built | Where-Object { $_.namespace -eq 'proja' })[0]
Check 'A6: deterministic rebuild -> identical tree_digest' ([string]$hA2.tree_digest -eq [string]$hA.tree_digest)

$st = Payload (Run-AS @{ op='hierarchy'; db=$hdb; namespace='projA'; include_nodes=$true })
$hh = @($st.hierarchies)[0]
Check 'A6: hierarchy status: nodes + tree_digest + topology valid' ($null -ne $hh -and @($hh.nodes).Count -ge 1 -and $hh.topology_state -eq 'valid')
$rootId = [string]$hh.root_node_id
Check 'A6: no node exceeds max_fanout (child+member <= 2)' ((@($hh.nodes | Where-Object { (@($_.entity_union).Count -ge 0) -and ((([int]$_.child_count) + ([int]$_.member_count)) -gt 2) }).Count) -eq 0)

$sl = Payload (Run-AS @{ op='shortlist'; db=$hdb; query='frobnicator'; effective_allowed_namespaces=@('projA') })
Check 'A6: shortlist scoped -> only projA navigation nodes' ([int]$sl.count -ge 1 -and (@($sl.nodes | Where-Object { $_.namespace -ne 'proja' -or $_.candidate_role -ne 'navigation' }).Count -eq 0))

$de = Payload (Run-AS @{ op='descend'; db=$hdb; node_id=$rootId; effective_allowed_namespaces=@('projA'); retrieval_plan_id='p1' })
Check 'A6: descend authorized -> direct children (frontier-expansion)' ([bool]$de.authorized -and [int]$de.child_count -ge 1)
Check 'A6: descend carries stage lineage + retrieval_plan_id' ([string]$de.retrieval_plan_id -eq 'p1' -and [string]$de.parent_stage_id -eq 'stage:shortlist:1')
$deX = Payload (Run-AS @{ op='descend'; db=$hdb; node_id=$rootId; effective_allowed_namespaces=@('projB'); retrieval_plan_id='p' })
Check 'A6: descend out-of-scope FAILS CLOSED (count-only, no metadata)' ((-not [bool]$deX.authorized) -and [int]$deX.child_count -eq 0 -and (-not (Has $deX 'namespace')))
$deB = Payload (Run-AS @{ op='descend'; db=$hdb; node_id='nd_deadbeefdeadbeefdeadbeef'; effective_allowed_namespaces=@('projA'); retrieval_plan_id='p' })
Check 'A6: descend foreign node_id FAILS CLOSED' ((-not [bool]$deB.authorized) -and [int]$deB.child_count -eq 0)

# safe-pruning on the root (subtree = whole namespace)
Check 'A6: safe-prune DESCRIPTOR never prunes' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='descriptor'; key='x' })).verdict -eq 'keep')
Check 'A6: safe-prune VECTOR never prunes' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='vector'; key='x' })).verdict -eq 'keep')
Check 'A6: safe-prune lexical present -> keep (no false negative)' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='lexical'; key='frobnicator' })).verdict -eq 'keep')
Check 'A6: safe-prune lexical absent -> prune (Bloom absence proof)' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='lexical'; key='zzzabsentxyz9931' })).verdict -eq 'prune')
Check 'A6: safe-prune kind absent -> prune' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='kind'; key='episode' })).verdict -eq 'prune')
Check 'A6: safe-prune kind present -> keep' ([string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='kind'; key='source_chunk' })).verdict -eq 'keep')

# staleness (H2): mark a leaf changed -> ancestors stale -> routes-but-never-answers -> refresh clears
$lr = Payload (Run-AS @{ op='list-records'; db=$hdb; filters=@{ namespace='projA'; record_kind='source_chunk' }; limit=1 })
$leafId = [string](@($lr.records)[0].record_version_id)
$mc = Payload (Run-AS @{ op='hierarchy-mark-changed'; db=$hdb; leaf_id=$leafId })
Check 'A6: mark-changed dirties the ancestor path' (@($mc.dirtied).Count -ge 1)
$st2 = Payload (Run-AS @{ op='hierarchy'; db=$hdb; namespace='projA' })
Check 'A6: stale nodes surfaced in status (synopsis freshness axis)' ([int](@($st2.hierarchies)[0].stale_node_count) -ge 1)
$slS = Payload (Run-AS @{ op='shortlist'; db=$hdb; query='frobnicator'; effective_allowed_namespaces=@('projA') })
Check 'A6: summary_stale node still ROUTES + flags stale_navigation (never answers)' ([int]$slS.count -ge 1 -and [bool]$slS.stale_navigation_encountered)
$stalePrune = [string](Payload (Run-AS @{ op='prune-verdict'; db=$hdb; node_id=$rootId; channel='lexical'; key='zzzabsentxyz9931' })).verdict
Check 'A6: a STALE synopsis never supplies a prune proof (keep)' ($stalePrune -eq 'keep')
$rf = Payload (Run-AS @{ op='refresh-hierarchy'; db=$hdb; namespace='projA' })
Check 'A6: refresh regenerates all stale nodes (CAS clear)' ([int]$rf.cleared -eq [int]$rf.stale)

# ---------- A6 GATE: schema_version 4 -> 5 additive in-place migration (shipped tables byte-identical) ----------
$v4worker = Join-Path $SkillDir 'fixtures/artifact_search_v4.py'
Check 'A6: frozen shipped-0.4 (v4) worker fixture present' (Test-Path -LiteralPath $v4worker -PathType Leaf)
$v4db = Join-Path $tmpRoot 'v4seed.db'
$v4iargs = Join-Path $tmpRoot 'v4iargs.json'; $v4imeta = Join-Path $tmpRoot 'v4imeta.json'
[System.IO.File]::WriteAllText($v4iargs, ([ordered]@{ op='ingest'; source='projA'; root=$hsrc; db=$v4db; embed_provider='mock'; meta_path=$v4imeta; output_dir=(Join-Path $tmpRoot 'v4iout') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v4worker $v4iargs 2>$null | Out-Null
$v4cargs = Join-Path $tmpRoot 'v4cargs.json'; $v4cmeta = Join-Path $tmpRoot 'v4cmeta.json'
[System.IO.File]::WriteAllText($v4cargs, ([ordered]@{ op='catalog'; db=$v4db; meta_path=$v4cmeta; output_dir=(Join-Path $tmpRoot 'v4cout') } | ConvertTo-Json -Depth 8), $utf8)
& $PythonPath $v4worker $v4cargs 2>$null | Out-Null
$v4cm = $null; try { $v4cm = (Get-Content -LiteralPath $v4cmeta -Raw) | ConvertFrom-Json } catch { }
$v4cat = $v4cm.result; $v4digest = [string]$v4cat.digest
Check 'A6: v4 baseline read at schema_version 4 (frozen worker)' ([string]$v4cat.schema_version -eq '4') "sv=$($v4cat.schema_version)"
$mg5 = Payload (Run-AS @{ op='migrate'; db=$v4db })
Check 'A6: migrate 4 -> 5 in place, migrated=true' ($null -ne $mg5 -and [bool]$mg5.migrated -and [string]$mg5.schema_version -eq '5')
Check 'A6: migrate reports from:4 + a6 action' ((@($mg5.migration_actions) -contains 'from:4') -and (@($mg5.migration_actions | Where-Object { $_ -match 'a6' }).Count -ge 1)) "acts=$($mg5.migration_actions -join ',')"
Check 'A6: shipped tables BYTE-IDENTICAL pre/post 4->5 (migrated sha == fresh v5 sha)' ([string]$mg5.shipped_tables_schema_sha -eq $freshSha4) "migrated=$($mg5.shipped_tables_schema_sha) fresh=$freshSha4"
Check 'A6: catalog_digest UNCHANGED across 4->5 (zero nodes = flat, no re-ingest)' ([string]$mg5.catalog_digest -eq $v4digest) "post=$($mg5.catalog_digest) pre=$v4digest"
Check 'A6: migrate 4->5 integrity ok' ([bool]$mg5.integrity.ok)
$mg5b = Payload (Run-AS @{ op='migrate'; db=$v4db })
Check 'A6: 4->5 migration idempotent (re-open is a no-op)' ((-not [bool]$mg5b.migrated) -and [string]$mg5b.schema_version -eq '5')
Check 'A6: shipped search regression-green on the 4->5 migrated db' ([int](Payload (Run-AS @{ op='search'; query='frobnicator'; mode='fts'; db=$v4db })).count -ge 1)

# ---------- i36 (D-0100 fold): the ADDITIVE READ-ONLY by-rvid get-record body-fetch op ----------
# $hdb has projA source_chunks + a projB typed 'decision' record (b1@1). get-record returns the full s1
# envelope + the evidence hydration body #40 needs, A5-closed. Uses the SAME id space descend leaf_members use.
$digBeforeGr = [string](Payload (Run-AS @{ op='catalog'; db=$hdb })).digest
$grLr = Payload (Run-AS @{ op='list-records'; db=$hdb; filters=@{ namespace='projA'; record_kind='source_chunk' }; limit=1 })
$scRvid = [string](@($grLr.records)[0].record_version_id)
# (a) a source_chunk rvid -> envelope + evidence with text/span/hashes
$grc = Payload (Run-AS @{ op='get-record'; db=$hdb; target_id=$scRvid; effective_allowed_namespaces=@('projA') })
$grcRec = @($grc.records)[0]
Check 'i36 get-record: source_chunk rvid found (envelope + evidence)' ([int]$grc.found_count -eq 1 -and $grcRec.record_kind -eq 'source_chunk' -and (Has $grcRec 'envelope') -and (Has $grcRec 'evidence'))
Check 'i36 get-record: evidence carries text + span + chunk_content_hash + content_hash (hydration body)' (-not [string]::IsNullOrEmpty([string]$grcRec.evidence.text) -and (Has $grcRec.evidence 'span') -and -not [string]::IsNullOrEmpty([string]$grcRec.evidence.chunk_content_hash) -and -not [string]::IsNullOrEmpty([string]$grcRec.evidence.content_hash))
Check 'i36 get-record: evidence is a DIRECT fetch (no retrieval-stage lineage)' (-not (Has $grcRec.evidence 'retrieval_stage_id'))
# (b) provenance holds: evidence matches export-chunk-texts for the same chunk
$grExAll = @((Payload (Run-AS @{ op='export-chunk-texts'; db=$hdb })).chunks)
$grExMatch = @($grExAll | Where-Object { [string]$_.chunk_id -eq [string]$grcRec.evidence.chunk_id })[0]
Check 'i36 get-record: provenance holds (evidence text+hash+span == export-chunk-texts)' ($null -ne $grExMatch -and [string]$grExMatch.text -eq [string]$grcRec.evidence.text -and [string]$grExMatch.chunk_content_hash -eq [string]$grcRec.evidence.chunk_content_hash)
# (a) a typed record rvid (projB decision) scoped to projB
$grB = Payload (Run-AS @{ op='get-record'; db=$hdb; target_id='b1@1'; effective_allowed_namespaces=@('projB') })
Check 'i36 get-record: typed record (projB) found scoped to projB' ([int]$grB.found_count -eq 1 -and [string](@($grB.records)[0].evidence.text).Length -ge 1)
# (c) namespace closure: the projB record is FOREIGN to a projA-scoped caller -> count-only, no leak
$grF = Payload (Run-AS @{ op='get-record'; db=$hdb; target_id='b1@1'; effective_allowed_namespaces=@('projA') })
$grFJson = ($grF | ConvertTo-Json -Depth 20 -Compress)
Check 'i36 get-record: foreign rvid FAILS CLOSED (count-only, no record)' ([int]$grF.found_count -eq 0 -and [int]$grF.namespace_violation_count -eq 1 -and @($grF.records).Count -eq 0)
Check 'i36 get-record: foreign rvid leaks NO identifying metadata (no projB text/ns)' (($grFJson -notmatch 'projb') -and ($grFJson -notmatch 'zeta'))
# (c) unknown rvid -> unresolved count-only
$grU = Payload (Run-AS @{ op='get-record'; db=$hdb; rvids=@('occ_deadbeefdeadbeefdeadbeef'); effective_allowed_namespaces=@('projA') })
Check 'i36 get-record: unknown rvid -> unresolved_count only' ([int]$grU.found_count -eq 0 -and [int]$grU.unresolved_count -eq 1 -and [int]$grU.namespace_violation_count -eq 0)
# (c) mixed-scope batch: an in-scope chunk + a FOREIGN record -> partial found + count-only violation
$grMix = Payload (Run-AS @{ op='get-record'; db=$hdb; rvids=@($scRvid, 'b1@1'); effective_allowed_namespaces=@('projA') })
Check 'i36 get-record: mixed batch -> in-scope hydrated, foreign count-only' ([int]$grMix.found_count -eq 1 -and [int]$grMix.namespace_violation_count -eq 1 -and [string](@($grMix.records)[0].record_version_id) -eq $scRvid)
# (d) determinism: identical re-run -> identical records[] order
$grD1 = Payload (Run-AS @{ op='get-record'; db=$hdb; target_id=$scRvid; effective_allowed_namespaces=@('projA') })
$grD2 = Payload (Run-AS @{ op='get-record'; db=$hdb; target_id=$scRvid; effective_allowed_namespaces=@('projA') })
Check 'i36 get-record: deterministic (byte-identical re-run)' (($grD1 | ConvertTo-Json -Depth 40 -Compress) -eq ($grD2 | ConvertTo-Json -Depth 40 -Compress))
# (e) read-only: catalog_digest unchanged by all the get-record activity
Check 'i36 get-record: READ-ONLY (catalog_digest unchanged; schema stays 5)' ([string](Payload (Run-AS @{ op='catalog'; db=$hdb })).digest -eq $digBeforeGr -and [string]$grc.schema_version -eq '5')
# (f) missing rvid -> clean fail-closed error
$grMiss = (Run-AS @{ op='get-record'; db=$hdb; effective_allowed_namespaces=@('projA') }).env
Check 'i36 get-record: missing rvid -> clean error (missing_rvid)' ($null -ne $grMiss -and [string]$grMiss.status -eq 'error' -and [string]$grMiss.error.code -eq 'missing_rvid')

# ---------- cleanup ----------
try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
Write-Host "RESULT: $($script:pass)/$($script:pass + $script:fail) passed  (fail=$($script:fail))"
if ($script:fail -gt 0) { Write-Host "ALLPASS=false" } else { Write-Host "ALLPASS=true" }
exit $script:fail
