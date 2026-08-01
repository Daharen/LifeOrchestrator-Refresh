#requires -Version 7.0
<#
  Invoke-EpisodeRecordTests.ps1 -- regression tests for episode.record (Module 39, Wave 2 PRODUCER lane).

  DUAL-MODE + OS-portable (a REAL-skill gate, not a mock): episode.record is pure deterministic logic
  (a stdlib-only Python worker behind a thin pwsh contract wrapper -- no CUDA, no model, no network, no
  OS-specific API), so the SAME harness runs the REAL Invoke-EpisodeRecord.ps1 on the cloud Linux box
  (pre-ship gate) and on the Windows executor (-Live). Fixtures are COMMITTED under tests/fixtures/:
    trace-success.json          a fully-known SUCCESS run trace (3 stages)
    trace-failure.json          a FAILED + TRUNCATED trace (last stage has no stage_end) + a failure descriptor
    failure-corpus.json         5 curated failure descriptors seeded from real CURRENT_STATE gotchas
    task-context-queries.json   the failure-signature retrieval query suite (expected top + must-exclude)
    ingest_records-fixture.schema.json  the FIXTURE #36 0.2 sink contract this producer builds to

  It exercises: AST parse + ASCII-only gate on the shipped .ps1; a py_compile syntax gate; manifest +
  result-envelope contract validation; the RECORDER on a SUCCESS trace AND a FAILED/TRUNCATED trace
  (a failed run still yields a COMPLETE episode + stages + a candidate failure); s1 record validation
  INCLUDING provenance recomputation (a tampered record is REJECTED); the deterministic failure-signature
  SEAM (right failure on top, unrelated failures EXCLUDED, a zero-match negative); DETERMINISTIC canonical
  bytes (pinned sha256 + records_digest + double-run identity); fail-closed error envelopes; and the
  Module 1 wrapper. It PRINTS `CANONICAL-HASH <name>=<sha256>` lines so cloud and -Live runs compare for
  cross-environment byte-identity.

  -PwshPath <pwsh>   : the interpreter used to invoke the skill (passed through explicitly).
  -PythonPath <py>   : forwarded to the skill as -PythonPath (default '' -> the skill auto-resolves).
  -Live              : informational banner only (assertions are identical in both modes).
#>
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [string]$PythonPath = '',
    [switch]$Live
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-EpisodeRecord.ps1'
$worker  = Join-Path $moduleRoot 'episode_record.py'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$fxDir   = Join-Path $moduleRoot 'tests/fixtures'
$traceSucc = Join-Path $fxDir 'trace-success.json'
$traceFail = Join-Path $fxDir 'trace-failure.json'
$corpus    = Join-Path $fxDir 'failure-corpus.json'
$querySuite = Join-Path $fxDir 'task-context-queries.json'

# ---- KNOWN pins (hand-verified off-machine; the cross-env byte-identity anchors) ----
# v0.1.1 (D-0085): ALL record ids/versions/digests/shas change vs 0.1.0 BY DESIGN -- the extractor bumped
# 0.1.0 -> 0.1.1 AND the envelope status became a string + stages fold into episode.body.stage_sequence
# (episode_stage retired). The LOGICAL ids (episode ep_..., failure fail_..., failure_signature) are
# UNCHANGED (derived from ns/task/attempt and descriptor facets, not the extractor fingerprint).
$SUCC_RECORDS_DIGEST   = 'sha256:ecfb7517a43f69acb63290251b769c8c28b1e1cdb3e66fdf7589ef55fddd2fbd'
$SUCC_EPISODE_SHA      = 'ec0b62da00abb429def46f2f51acb95b8bf4634e6ad538e63e0d90bcefbc5389'
$SUCC_EPISODE_ID       = 'ep_9416e689572bcc33ae38db45'
$FAIL_RECORDS_DIGEST   = 'sha256:7696727d240e740f04706938cef2ab20789c1ecd27561bf11073f160529a7739'
$FAIL_EPISODE_SHA      = '6136a93313bcf450f4df10cb107fd1c4ed1d9155bf1c5a1b400a631e61d0be56'
$FAIL_FAILURE_SHA      = 'fa973326493aaf1bb80f762ed9d351ef490519245593beb70cf851849d658b30'
$FAIL_FAILURE_ID       = 'fail_da6b51ac7cb6ad22b2b2dc0c'
$FAIL_FAILURE_SIG      = 'fsig1:media-decompose:a05ab6b03ecf365c454a'
$CORPUS_RECORDS_DIGEST = 'sha256:e9ef0b854824e878c6dcdae0017e4395e8142b2e01f720354704c0ba1b4085fd'

# The EXACT sets #36 0.2 `ingest_records` enforces (artifact_search STATUS_ENUM + TYPED_RECORD_KINDS) --
# so a local #36-shape self-check proves the emitted records ingest with ZERO rejections (D-0077 fold).
$S5_STATUS_ENUM = @('current','source_stale','derivation_stale','embedding_stale','relationship_stale',
    'summary_stale','authority_stale','temporal_expiry','deleted','unverified')
$TYPED_RECORD_KINDS = @('symbol','summary','decision','claim','episode','failure','procedure','skill',
    'reminder','entity','relationship')

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== episode.record tests ($mode); pwsh=$PwshPath python=$([string]::IsNullOrEmpty($PythonPath) ? '(auto)' : $PythonPath) ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function RunOp([string[]]$a) {
    $args2 = $a
    if (-not [string]::IsNullOrEmpty($PythonPath)) { $args2 = $args2 + @('-PythonPath', $PythonPath) }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @args2
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function ParseEnv([string]$s) { try { return ($s | ConvertFrom-Json) } catch { return $null } }
function Artifact([object]$env, [string]$suffix) {
    if (-not (Has $env 'artifacts')) { return $null }
    return (@($env.artifacts | Where-Object { ([string]$_.path) -match ([regex]::Escape($suffix) + '$') }) | Select-Object -First 1)
}
function ReadArt([object]$env, [string]$name) {
    $a = Artifact $env $name
    if ($null -eq $a) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes([string]$a.path)
    $sha = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    $obj = $null; if ($name -match '\.json$') { $obj = ([System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json) }
    return [pscustomobject]@{ path = [string]$a.path; bytes = $bytes.Length; sha = $sha; declared_sha = [string]$a.sha256; obj = $obj }
}

# ---- LOCAL #36 0.2 `ingest_records` shape self-check (mirrors artifact_search._validate_record + the
# status/kind gates EXACTLY, so a record that would be REJECTED by the real #36 is rejected here too).
# Returns an array of { record_version_id, reason } rejections; empty == would ingest with 0 rejections.
function Test-Ingest36Shape([object[]]$records) {
    $rej = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($records)) {
        $rvid = if (Has $r 'record_version_id') { [string]$r.record_version_id } else { $null }
        $missing = $false
        foreach ($req in @('record_id', 'record_version_id', 'record_kind')) {
            if (-not (Has $r $req) -or [string]::IsNullOrWhiteSpace([string]$r.$req)) {
                $rej.Add([pscustomobject]@{ record_version_id = $rvid; reason = 'missing_required_field' }); $missing = $true; break
            }
        }
        if ($missing) { continue }
        $kind = [string]$r.record_kind
        if ($kind -eq 'source_chunk') { $rej.Add([pscustomobject]@{ record_version_id = $rvid; reason = 'reserved_record_kind' }); continue }
        if ($TYPED_RECORD_KINDS -notcontains $kind) { $rej.Add([pscustomobject]@{ record_version_id = $rvid; reason = 'unknown_record_kind' }); continue }
        $hasText = (Has $r 'text') -and -not [string]::IsNullOrWhiteSpace([string]$r.text)
        $hasHash = (Has $r 'content_hash') -and -not [string]::IsNullOrWhiteSpace([string]$r.content_hash)
        if (-not $hasText -and -not $hasHash) { $rej.Add([pscustomobject]@{ record_version_id = $rvid; reason = 'missing_content' }); continue }
        # status is a SINGLE STRING from the s5 enum (an object stringifies to a non-enum value -> reject)
        $st = if (Has $r 'status') { $r.status } elseif (Has $r 'currentness') { $r.currentness } else { 'current' }
        if ($st -isnot [string] -or ($S5_STATUS_ENUM -notcontains [string]$st)) { $rej.Add([pscustomobject]@{ record_version_id = $rvid; reason = 'invalid_status' }); continue }
    }
    return $rej.ToArray()
}

# ---- resolve a python for the py_compile gate ----
$py = $null
foreach ($c in @($PythonPath, 'python3', 'python', 'py')) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $v = & $c -c 'import sys;sys.stdout.write(str(sys.version_info[0]))' 2>$null
        $ErrorActionPreference = $prev
        if ("$v".Trim() -eq '3') { $py = $c; break }
    } catch { }
}

# ================================================================= static gates
$errs = $null; $toks = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$toks, [ref]$errs)
Check 'AST parses: Invoke-EpisodeRecord.ps1' (($null -eq $errs) -or (@($errs).Count -eq 0))
[void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$toks, [ref]$errs)
Check 'AST parses: this test harness' (($null -eq $errs) -or (@($errs).Count -eq 0))

foreach ($psf in @($entry, $PSCommandPath)) {
    $raw = [System.IO.File]::ReadAllBytes($psf)
    $nonAscii = @($raw | Where-Object { $_ -gt 127 }).Count
    Check "ASCII-only: $(Split-Path -Leaf $psf)" ($nonAscii -eq 0)
}

Check 'python 3 available for py_compile' ($null -ne $py)
if ($null -ne $py) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $py -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" $worker 2>$null | Out-Null
    $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev
    Check 'py_compile OK: episode_record.py' $ok
}

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id episode.record' ($manifest.skill_id -eq 'episode.record')
Check 'manifest version 0.1.1' ($manifest.version -eq '0.1.1')
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest parallel_safe' ([bool]$manifest.parallel_safe)

# ================================================================= RECORDER: success trace
$e1 = ParseEnv (RunOp @('-Op', 'record', '-Trace', $traceSucc))
Check 'succ: envelope parses' ($null -ne $e1)
Check 'succ: entrypoint exit 0' ($script:code -eq 0)
if ($null -ne $e1) {
    $ev = Test-SkillResultEnvelope -Envelope $e1
    Check 'succ: envelope validates against contract' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    Check 'succ: status ok' ($e1.status -eq 'ok')
    Check 'succ: episode_record_id pinned' ($e1.result.episode_record_id -eq $SUCC_EPISODE_ID)
    Check 'succ: final_status ok' ($e1.result.episode_final_status -eq 'ok')
    Check 'succ: 3 stages' ($e1.result.stage_count -eq 3)
    Check 'succ: no candidate failure (clean run)' (-not $e1.result.failure_emitted)
    Check 'succ: record_count 1 (episode only; stages fold in-body, v0.1.1)' ($e1.result.record_count -eq 1)
    Check 'succ: all records valid' ([bool]$e1.result.all_valid)
    Check 'succ: records_digest pinned (deterministic + known)' ($e1.result.records_digest -eq $SUCC_RECORDS_DIGEST)
    [Console]::Out.WriteLine("CANONICAL-HASH succ-records_digest=$($e1.result.records_digest)")

    $ep = ReadArt $e1 'episode.json'
    Check 'succ: episode.json artifact present' ($null -ne $ep)
    if ($null -ne $ep) {
        [Console]::Out.WriteLine("CANONICAL-HASH succ-episode.json=$($ep.sha)")
        Check 'succ: episode.json declared sha == file sha' ($ep.sha -eq $ep.declared_sha)
        Check 'succ: episode.json sha == pinned (canonical bytes)' ($ep.sha -eq $SUCC_EPISODE_SHA)
        # s1 envelope fields present on the episode record
        foreach ($f in @('record_id', 'record_version_id', 'record_kind', 'namespace', 'content_hash',
                'status', 'authority_level', 'sensitivity_class', 'source_version_id', 'derivation_refs',
                'parser_fingerprint', 'extractor_fingerprint', 'schema_version', 'embedding_space_id',
                'parent_edges', 'child_edges', 'body')) {
            Check "succ: episode envelope has s1 field '$f'" (Has $ep.obj $f)
        }
        Check 'succ: episode record_kind episode' ($ep.obj.record_kind -eq 'episode')
        # v0.1.1 (D-0085): envelope status is a SINGLE STRING from the s5 enum, NOT a {state,...} object
        Check 'succ: episode status is a string in the s5 enum (not an object)' (($ep.obj.status -is [string]) -and ($S5_STATUS_ENUM -contains [string]$ep.obj.status))
        Check 'succ: episode status == current (healthy baseline)' ($ep.obj.status -eq 'current')
        Check 'succ: episode body.complete true' ([bool]$ep.obj.body.complete)
        # v0.1.1: stage_sequence carries FULL in-body stage detail (was lightweight refs -> separate records)
        Check 'succ: episode stage_sequence has 3 full stage detail objects' (@($ep.obj.body.stage_sequence).Count -eq 3)
        $s4 = @('stage_index','stage_name','role','status','closed_explicitly','duration_ms','tool_invocations','state_changes','test_results','reviewer_outcomes','human_interventions','errors','notes','model_provenance')
        $allS4 = $true; foreach ($stg in @($ep.obj.body.stage_sequence)) { foreach ($sf in $s4) { if (-not (Has $stg $sf)) { $allS4 = $false } } }
        Check 'succ: EVERY per-stage s4 field survives IN-BODY (no field lost vs 0.1.0)' $allS4
        # the s4 VALUES survive too: the verify stage keeps its test_result + reviewer_outcome + model_provenance
        $verify = (@($ep.obj.body.stage_sequence | Where-Object { $_.stage_name -eq 'verify' }) | Select-Object -First 1)
        Check 'succ: verify stage retains test_results + reviewer_outcomes + model_provenance in-body' ($null -ne $verify -and @($verify.test_results).Count -ge 1 -and @($verify.reviewer_outcomes).Count -ge 1 -and @($verify.model_provenance).Count -ge 1)
        Check 'succ: episode child_edges has_stage x3 (by in-body ordinal, not a stage record_id)' (@($ep.obj.child_edges | Where-Object { $_.edge_kind -eq 'has_stage' -and (Has $_ 'ordinal') -and -not (Has $_ 'child_record_id') }).Count -eq 3)
        Check 'succ: embedding_space_id null (unembedded)' ($null -eq $ep.obj.embedding_space_id)
    }
    # episode_stages.json is now a HUMAN/DEBUG VIEW of the in-body stage detail (NOT separate records / NOT ingested)
    $st = ReadArt $e1 'episode_stages.json'
    $stS4 = $false
    if ($null -ne $st -and @($st.obj).Count -eq 3) {
        $s4b = @('stage_index','stage_name','role','status','closed_explicitly','duration_ms','tool_invocations','state_changes','test_results','reviewer_outcomes','human_interventions','errors','notes','model_provenance')
        $stS4 = $true; foreach ($stg in @($st.obj)) { foreach ($sf in $s4b) { if (-not (Has $stg $sf)) { $stS4 = $false } }; if (Has $stg 'record_kind') { $stS4 = $false } }
    }
    Check 'succ: episode_stages.json = 3 debug stage detail objects (no record envelope; not ingested)' $stS4

    # ---- LOCAL #36 0.2 ingest_records self-check: the success bundle is episode-only, 0 rejections ----
    $succBundle = ReadArt $e1 'records.json'
    Check 'succ: ingest bundle is episode ONLY (no episode_stage records)' ($null -ne $succBundle -and (@($succBundle.obj.records | Where-Object { $_.record_kind -eq 'episode' }).Count -eq 1) -and (@($succBundle.obj.records).Count -eq 1))
    if ($null -ne $succBundle) {
        $rej = Test-Ingest36Shape @($succBundle.obj.records)
        Check 'succ: emitted records ingest into a #36-shape sink with ZERO rejections' (@($rej).Count -eq 0)
    }
}

# double-run byte identity (same machine)
$e1b = ParseEnv (RunOp @('-Op', 'record', '-Trace', $traceSucc))
if ($null -ne $e1b) {
    $epB = ReadArt $e1b 'episode.json'
    Check 'succ: double-run episode.json byte-identical' ($null -ne $epB -and $epB.sha -eq $SUCC_EPISODE_SHA)
    Check 'succ: double-run records_digest identical' ($e1b.result.records_digest -eq $SUCC_RECORDS_DIGEST)
}

# ================================================================= RECORDER: FAILED + TRUNCATED trace
$e2 = ParseEnv (RunOp @('-Op', 'record', '-Trace', $traceFail))
Check 'fail: envelope parses' ($null -ne $e2)
if ($null -ne $e2) {
    Check 'fail: skill status ok (the recorder itself succeeded)' ($e2.status -eq 'ok')
    Check 'fail: episode final_status failed' ($e2.result.episode_final_status -eq 'failed')
    Check 'fail: 2 stages (open probe stage still closed)' ($e2.result.stage_count -eq 2)
    Check 'fail: candidate failure EMITTED' ([bool]$e2.result.failure_emitted)
    Check 'fail: failure_record_id pinned' ($e2.result.failure_record_id -eq $FAIL_FAILURE_ID)
    Check 'fail: failure_signature pinned (deterministic)' ($e2.result.failure_signature -eq $FAIL_FAILURE_SIG)
    Check 'fail: all records valid (COMPLETE episode from a failed run)' ([bool]$e2.result.all_valid)
    Check 'fail: records_digest pinned' ($e2.result.records_digest -eq $FAIL_RECORDS_DIGEST)
    [Console]::Out.WriteLine("CANONICAL-HASH fail-records_digest=$($e2.result.records_digest)")

    $ep2 = ReadArt $e2 'episode.json'
    if ($null -ne $ep2) {
        [Console]::Out.WriteLine("CANONICAL-HASH fail-episode.json=$($ep2.sha)")
        Check 'fail: episode.json sha == pinned' ($ep2.sha -eq $FAIL_EPISODE_SHA)
        Check 'fail: episode body.complete true (even though the run failed)' ([bool]$ep2.obj.body.complete)
        Check 'fail: episode carries failure_reasons' (@($ep2.obj.body.failure_reasons).Count -ge 1)
        # the truncated last stage is closed with status failed/incomplete
        $probe = (@($ep2.obj.body.stage_sequence | Where-Object { $_.stage_name -eq 'probe' }) | Select-Object -First 1)
        Check 'fail: truncated probe stage present + not ok' ($null -ne $probe -and $probe.status -ne 'ok')
    }
    $fl = ReadArt $e2 'failure.json'
    Check 'fail: failure.json present' ($null -ne $fl)
    if ($null -ne $fl) {
        [Console]::Out.WriteLine("CANONICAL-HASH fail-failure.json=$($fl.sha)")
        Check 'fail: failure.json sha == pinned' ($fl.sha -eq $FAIL_FAILURE_SHA)
        Check 'fail: failure record_kind failure' ($fl.obj.record_kind -eq 'failure')
        Check 'fail: failure authority proposed (auto-derived candidate)' ($fl.obj.authority_level -eq 'proposed')
        Check 'fail: failure body has a failure_signature' (Has $fl.obj.body 'failure_signature')
        Check 'fail: failure body has match_keys (the retrieval seam surface)' (Has $fl.obj.body 'match_keys')
        Check 'fail: failure body confidence_ppm is an integer' ($fl.obj.body.confidence_ppm -is [int] -or $fl.obj.body.confidence_ppm -is [long])
        Check 'fail: failure links back to the episode (derivation ref)' (@($fl.obj.derivation_refs | Where-Object { $_.ref_kind -eq 'episode' }).Count -ge 1)
    }
}

# ================================================================= s1 VALIDATOR incl. provenance recomputation
# the records bundle from the failed run must validate; then a TAMPERED record must be REJECTED.
$recBundle = Artifact $e2 'records.json'
Check 'validate: records.json bundle present' ($null -ne $recBundle)
if ($null -ne $recBundle) {
    $ev5 = ParseEnv (RunOp @('-Op', 'validate', '-Records', ([string]$recBundle.path)))
    Check 'validate: clean bundle all_valid true' ($null -ne $ev5 -and [bool]$ev5.result.all_valid)
    Check 'validate: num_records 2 (episode + failure; NO episode_stage, v0.1.1)' ($null -ne $ev5 -and $ev5.result.num_records -eq 2)

    # ---- LOCAL #36 0.2 ingest_records self-check on the FAILED-run bundle (episode + failure) ----
    $failBundle = ReadArt $e2 'records.json'
    if ($null -ne $failBundle) {
        $kinds = @($failBundle.obj.records | ForEach-Object { $_.record_kind }) | Sort-Object -Unique
        Check 'fold: failed-run bundle kinds are exactly {episode, failure}' (($kinds -join ',') -eq 'episode,failure')
        $rejF = Test-Ingest36Shape @($failBundle.obj.records)
        Check 'fold: episode + failure ingest into a #36-shape sink with ZERO rejections' (@($rejF).Count -eq 0)
        # REGRESSION GUARD: the retired 0.1.0 shapes MUST be rejected by the same #36-shape gate.
        $badKind = ($failBundle.obj.records[0] | ConvertTo-Json -Depth 60 | ConvertFrom-Json); $badKind.record_kind = 'episode_stage'
        $rejK = Test-Ingest36Shape @($badKind)
        Check 'fold guard: an episode_stage record IS rejected (unknown_record_kind)' (@($rejK | Where-Object { $_.reason -eq 'unknown_record_kind' }).Count -ge 1)
        $badStatus = ($failBundle.obj.records[0] | ConvertTo-Json -Depth 60 | ConvertFrom-Json)
        $badStatus.status = [pscustomobject]@{ state = 'current'; stale_reasons = @(); verified = $true }
        $rejS = Test-Ingest36Shape @($badStatus)
        Check 'fold guard: an OBJECT status IS rejected (invalid_status)' (@($rejS | Where-Object { $_.reason -eq 'invalid_status' }).Count -ge 1)
    }

    # tamper: flip the episode final_status -> content_hash must no longer recompute
    $ep2obj = (ReadArt $e2 'episode.json').obj
    $ep2obj.body.final_status = 'ok'   # was 'failed'
    $tamperPath = Join-Path ([System.IO.Path]::GetTempPath()) ("epi-tamper-" + [Guid]::NewGuid().ToString('N') + '.json')
    [System.IO.File]::WriteAllText($tamperPath, (@($ep2obj) | ConvertTo-Json -Depth 60), [System.Text.UTF8Encoding]::new($false))
    $ev6 = ParseEnv (RunOp @('-Op', 'validate', '-Records', $tamperPath))
    Check 'validate: TAMPERED record rejected (all_valid false)' ($null -ne $ev6 -and -not [bool]$ev6.result.all_valid)
    $valArt = ReadArt $ev6 'validation.json'
    $mismatch = $false
    if ($null -ne $valArt) { $mismatch = (@($valArt.obj.records | Where-Object { ($_.errors -join ' ') -match 'content_hash MISMATCH' }).Count -ge 1) }
    Check 'validate: rejection cites a content_hash MISMATCH (provenance validation)' $mismatch
    Remove-Item -LiteralPath $tamperPath -Force -ErrorAction SilentlyContinue
}

# ================================================================= build-failure corpus (deterministic)
$e3 = ParseEnv (RunOp @('-Op', 'build-failure', '-Failures', $corpus, '-Namespace', 'life-orchestrator'))
Check 'corpus: envelope parses' ($null -ne $e3)
if ($null -ne $e3) {
    Check 'corpus: status ok' ($e3.status -eq 'ok')
    Check 'corpus: 5 failure records' ($e3.result.record_count -eq 5)
    Check 'corpus: all valid' ([bool]$e3.result.all_valid)
    Check 'corpus: records_digest pinned (deterministic)' ($e3.result.records_digest -eq $CORPUS_RECORDS_DIGEST)
    [Console]::Out.WriteLine("CANONICAL-HASH corpus-records_digest=$($e3.result.records_digest)")
}

# ================================================================= FAILURE-SIGNATURE SEAM (the acceptance test)
$suite = (Get-Content -LiteralPath $querySuite -Raw) | ConvertFrom-Json
foreach ($q in $suite.queries) {
    $tcPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tc-" + $q.query_id + '-' + [Guid]::NewGuid().ToString('N') + '.json')
    [System.IO.File]::WriteAllText($tcPath, ($q.task_context | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $es = ParseEnv (RunOp @('-Op', 'search-failures', '-TaskContext', $tcPath, '-Corpus', $corpus))
    Check "seam[$($q.query_id)]: envelope parses" ($null -ne $es)
    if ($null -ne $es) {
        $sr = ReadArt $es 'search.json'
        [Console]::Out.WriteLine("CANONICAL-HASH search-$($q.query_id)=$($sr.sha)")
        $comps = @($sr.obj.results | ForEach-Object { $_.component })
        $top = if ($comps.Count -gt 0) { $comps[0] } else { $null }
        # expected top
        if ($null -ne $q.expect_top_component) {
            Check "seam[$($q.query_id)]: top == $($q.expect_top_component)" ($top -eq $q.expect_top_component)
        }
        # expected match count (e.g. the zero-match negative)
        if (Has $q 'expect_match_count') {
            Check "seam[$($q.query_id)]: match_count == $($q.expect_match_count)" ($es.result.match_count -eq [int]$q.expect_match_count)
        }
        # MUST-EXCLUDE: the test FAILS if any unrelated failure surfaces
        foreach ($x in @($q.must_exclude_components)) {
            Check "seam[$($q.query_id)]: EXCLUDES unrelated '$x'" ($comps -notcontains $x)
        }
        # deterministic double-run of the search
        $es2 = ParseEnv (RunOp @('-Op', 'search-failures', '-TaskContext', $tcPath, '-Corpus', $corpus))
        $sr2 = ReadArt $es2 'search.json'
        Check "seam[$($q.query_id)]: search.json double-run byte-identical" ($null -ne $sr2 -and $sr2.sha -eq $sr.sha)
    }
    Remove-Item -LiteralPath $tcPath -Force -ErrorAction SilentlyContinue
}

# ================================================================= fail-closed error paths
$e7 = ParseEnv (RunOp @('-Op', 'record', '-Trace', (Join-Path $fxDir 'does-not-exist.json')))
Check 'error: missing trace -> status error' ($null -ne $e7 -and $e7.status -eq 'error')
Check 'error: missing trace -> exit 0 (envelope still produced)' ($script:code -eq 0)
if ($null -ne $e7) { $ev7 = Test-SkillResultEnvelope -Envelope $e7; Check 'error: error envelope still validates' ([bool]$ev7.valid) }
$e8 = ParseEnv (RunOp @('-Op', 'bogus-op', '-Trace', $traceSucc))
Check 'error: unknown op -> status error code bad_op' ($null -ne $e8 -and $e8.status -eq 'error' -and $e8.error.code -eq 'bad_op')

# ================================================================= Module 1 wrapper
if (Test-Path -LiteralPath $wrapper -PathType Leaf) {
    $inputsJson = (@{ op = 'record'; trace = $traceSucc } | ConvertTo-Json -Compress)
    $wargs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $wrapper, '-SkillDir', $moduleRoot, '-InputsJson', $inputsJson, '-PwshPath', $PwshPath)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $wout = & $PwshPath @wargs
    $wcode = $LASTEXITCODE; $ErrorActionPreference = $prev
    $wrep = ParseEnv (([string]($wout | Out-String)).Trim())
    Check 'wrapper: invocation_report parses' ($null -ne $wrep)
    if ($null -ne $wrep) {
        Check 'wrapper: manifest_valid' ([bool]$wrep.manifest_valid)
        Check 'wrapper: invoked' ([bool]$wrep.invoked)
        Check 'wrapper: envelope_valid' ([bool]$wrep.envelope_valid)
        Check 'wrapper: nested envelope status ok' ($null -ne $wrep.envelope -and $wrep.envelope.status -eq 'ok')
    }
}

[Console]::Out.WriteLine("")
if ($script:fail -eq 0) { [Console]::Out.WriteLine("ALL PASS (episode.record)"); exit 0 }
else { [Console]::Out.WriteLine("FAILURES: $script:fail"); exit 1 }
