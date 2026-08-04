#requires -Version 7.0
<#
  Invoke-RetrievalEvalTests.ps1 -- regression + eval-0.2 tests for retrieval.eval (Module 37, contract v0.2).

  DUAL-MODE + OS-portable (a REAL-skill gate, not a mock): retrieval.eval is pure deterministic logic
  (a stdlib-only Python worker behind a thin pwsh contract wrapper -- no CUDA, no model, no network, no
  OS-specific API), so the SAME harness runs the REAL Invoke-RetrievalEval.ps1 on the cloud Linux box
  (pre-ship gate) and on the Windows executor (-Live). Fixtures are COMMITTED under tests/fixtures/:
    corpus/ + benchmark.json            the shipped 0.1 Life Orchestrator benchmark (regression-green)
    corpus2/ + benchmark2.json          the eval-0.2 lexical benchmark: evidence groups (all/any),
                                        temporal intent, privacy/forbidden, no-answer (clean + FP),
                                        duplicates+diversity, chunk-level credit, version-specific intent
    mock-benchmark.json + mock-plan.json + mock-retriever.py   the shipped 0.1 external_command seam
    mock2-benchmark.json + mock2-plan.json                     eval-0.2 external retriever-0.2 canned hits:
                                        required-absent, forbidden-returned, span-does-not-reproduce
                                        (provenance-validity FAIL), and the deterministic reranker A/B

  It exercises: AST parse of the shipped .ps1; a py_compile syntax gate on the Python files; manifest +
  result-envelope contract validation (skill.json 0.2.0); the KNOWN 0.1 baseline numbers PRESERVED
  (regression); the eval-0.2 metrics with KNOWN fixture values (precision@K, nDCG@K, evidence-group
  coverage, forbidden/privacy/stale-hit rate, provenance VALIDITY, snippet-span correctness, source
  diversity, duplicate burden, no-answer FP); DETERMINISTIC canonical report bytes (pinned sha256 +
  double-run identity); the three ACCEPTANCE failing cases (required ABSENT; forbidden RETURNED; a
  returned span that does NOT reproduce the cited text -> provenance INVALID); the deterministic reranker
  MEASURED (rescue a required source into top-1 + demote a forbidden/stale hit, A/B delta reported);
  hybrid attribution with the vector channel EMPTY; fail-closed error envelopes; and the Module 1 wrapper.
  It PRINTS `CANONICAL-HASH <name>=<sha256>` lines so the cloud and -Live runs can be compared for
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
$entry   = Join-Path $moduleRoot 'Invoke-RetrievalEval.ps1'
$worker  = Join-Path $moduleRoot 'retrieval_eval.py'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$fxDir   = Join-Path $moduleRoot 'tests/fixtures'
$benchmark  = Join-Path $fxDir 'benchmark.json'
$benchmark2 = Join-Path $fxDir 'benchmark2.json'
$benchmark3 = Join-Path $fxDir 'benchmark3.json'
$benchmark4 = Join-Path $fxDir 'benchmark4.json'
$mockBench  = Join-Path $fxDir 'mock-benchmark.json'
$mock2Bench = Join-Path $fxDir 'mock2-benchmark.json'
$benchmark5 = Join-Path $fxDir 'benchmark5.json'
$mockRetr   = Join-Path $fxDir 'mock-retriever.py'
$selpolLib  = Join-Path $moduleRoot 'lib/selpol_rrf_v1.py'
$nsPolicyLib = Join-Path $moduleRoot 'lib/namespace_policy.py'
$clsPolicyLib = Join-Path $moduleRoot 'lib/classifier_policy.py'
$selpolTest = Join-Path $moduleRoot 'tests/test_selpol.py'

# ---- KNOWN pins (hand-verified; also the cross-env byte-identity pins). eval-0.5 / report schema 0.5
#      (i33 / D-0096): selpol_rrf_v1 1.2.0 (NAMESPACE-CLOSURE + candidate-independent supersession + the
#      query_class/temporal_intent split) + the canonical lib/namespace_policy.py predicate + versioned
#      lib/classifier_policy.py map + the eval-0.5 selection_conformance block MEASURING the leakage paths
#      (namespace CLOSURE drop+sanitize, pool-independent current_only, supersession-chain + branch, the
#      class/intent split, reason-code coverage). Every shipped-0.4 RAW/reranked/packet metric VALUE is
#      PRESERVED (asserted below); the report SHAPE grew (version string + the i33 conformance fields + the
#      sanitized drop of the cross-namespace distractor) so the SHA/input_digest pins are re-computed.
#      Verified byte-identical cloud CPython 3.11 == the pinned values (double-run + the -Live executor
#      re-assert cross-env). ----
$BASELINE_REPORT_JSON_SHA = '36df27d446f4f47d1a1043325c32a544beddfa749cacc9299799149004b73baa'
$BASELINE_REPORT_MD_SHA   = '666314feb725ac93ec8cdf41cf11e97fd93679beee15a5112f4ae39145a50f60'
$BASELINE_INPUT_DIGEST    = 'sha256:b338ff864874863cb511f7a749ce3278ff1560e949c273a6f051e7ab601cdf14'
$B2_REPORT_JSON_SHA       = '80d79fd09deff3cdd17eb3e1e7c8a9ad009cc116ebe19df06ef565e82da5dcbc'
$B2_REPORT_MD_SHA         = '0b43565cf3b43c7f6779c0152da9f3e2e03a57468690a4dc3506ad424e37f6c2'
$B2_INPUT_DIGEST          = 'sha256:f04b209c69a2fbb3cc85eed1093c2a010c08610d98b9665bac0045622c83eee1'
$MOCK_REPORT_JSON_SHA     = 'c90f13f92e117adde281f6de00ca88060f275fdcff20fcd665e34c27616404da'
$MOCK2_REPORT_JSON_SHA    = '75f63539b644d179d2f17034abcde16bfa0a6e41c7144669ead3264a43ec80b9'
$MOCK2_INPUT_DIGEST       = 'sha256:c1216332c2ad15ec982b449b131dd0a8fb2b44343bf29067cc25c9055a242b19'
$B3_REPORT_JSON_SHA       = 'cea873052d9f2400764c045e04eb629e17e19ca2bb55891d28c6303ff8996689'
$B3_REPORT_MD_SHA         = 'c24b15549bc9e8ab84cf5a754824e11daefc227d098829240f321fe308e350da'
$B3_INPUT_DIGEST          = 'sha256:c85859774a6ff5ad739c7928c2b126dc93f18fb3afdf6af9c30d1cb61ea2b781'
$B4_REPORT_JSON_SHA       = 'a20ea2ff207c155da8967d062fd8fba66cef1ae39e021d7c1f45d0208d856502'
$B4_REPORT_MD_SHA         = 'ace94e6a265de5b994ac4e84f0ee501e2f42b7476845a363598c406babdba667'
$B4_INPUT_DIGEST          = 'sha256:5ed9131b49fabf688fca7111e383de675bda237c1daa273cf9866e8e53b2f96a'
$B5_REPORT_JSON_SHA       = 'c63abbdc9263c5f1719427a0a87146bde5cd41e8f85541acd83c9a211419216f'
$B5_REPORT_MD_SHA         = 'ca51f02934af320930c7cefc48ea6d04108e9426955162fd12db21b7fac7cc83'
$B5_INPUT_DIGEST          = 'sha256:21cb279c002478aec4fc7a2cdfdf2ae1f714ae82d6d868b5954c7a3fc93cc660'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
$pyLabel = if ([string]::IsNullOrEmpty($PythonPath)) { '(auto)' } else { $PythonPath }
[Console]::Out.WriteLine("== retrieval.eval eval-0.2 tests ($mode); pwsh=$PwshPath python=$pyLabel ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function RunEntry([string[]]$a) {
    $args2 = @('-InputFile') + $a
    if (-not [string]::IsNullOrEmpty($PythonPath)) { $args2 += @('-PythonPath', $PythonPath) }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @args2
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function ParseEnv([string]$s) { try { return ($s | ConvertFrom-Json) } catch { return $null } }
function ReportArtifact([object]$env, [string]$suffix) {
    if (-not (Has $env 'artifacts')) { return $null }
    return (@($env.artifacts | Where-Object { ([string]$_.path) -match ([regex]::Escape($suffix) + '$') }) | Select-Object -First 1)
}
function ReadReport([object]$env, [string]$name) {
    $a = ReportArtifact $env $name
    if ($null -eq $a) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes([string]$a.path)
    $sha = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    $obj = $null; if ($name -match '\.json$') { $obj = ([System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json) }
    return [pscustomobject]@{ path = [string]$a.path; bytes = $bytes.Length; sha = $sha; declared_sha = [string]$a.sha256; obj = $obj }
}
function QById([object]$report, [string]$id) { return (@($report.per_query_raw | Where-Object { $_.query_id -eq $id }) | Select-Object -First 1) }
function QReById([object]$report, [string]$id) { return (@($report.per_query_reranked | Where-Object { $_.query_id -eq $id }) | Select-Object -First 1) }
function HybById([object]$report, [string]$id) { return (@($report.hybrid_attribution | Where-Object { $_.query_id -eq $id }) | Select-Object -First 1) }

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
Check 'AST parses: Invoke-RetrievalEval.ps1' (($null -eq $errs) -or (@($errs).Count -eq 0))
[void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$toks, [ref]$errs)
Check 'AST parses: this test harness' (($null -eq $errs) -or (@($errs).Count -eq 0))

Check 'python 3 available for py_compile' ($null -ne $py)
if ($null -ne $py) {
    foreach ($pyf in @($worker, $mockRetr, $selpolLib, $nsPolicyLib, $clsPolicyLib, $selpolTest)) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $py -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" $pyf 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev
        Check "py_compile OK: $(Split-Path -Leaf $pyf)" $ok
    }
}

# ================================================================= selpol_rrf_v1 library-direct unit gate
# The ONE selection-policy library (CONTEXT_PACKET_CONTRACT s4 / P1-1): s4 interface, purity, determinism,
# ADDITIVE output, rescue+demote preserving retrieval_rank, RRF over channel ranks, occurrence-preserving
# display dedup, budget. Pure stdlib -> runs identically in the cloud gate and on -Live.
if ($null -ne $py) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $selOut = & $py $selpolTest 2>&1 | Out-String
    $selOk = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev
    Check 'selpol_rrf_v1: library-direct unit suite passes' $selOk
    if (-not $selOk) { ($selOut -split "`r?`n" | Select-Object -Last 8) | ForEach-Object { [Console]::Out.WriteLine("      $_") } }
    Check 'selpol_rrf_v1: unit suite reports ALL PASS' ($selOut -match 'ALL PASS \(selpol_rrf_v1 unit\)')
}

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id retrieval.eval' ($manifest.skill_id -eq 'retrieval.eval')
Check 'manifest version 0.5.0' ($manifest.version -eq '0.5.0')
Check 'manifest contract_version 0.5' ($manifest.contract_version -eq '0.5')
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest parallel_safe' ([bool]$manifest.parallel_safe)

# ================================================================= baseline run (0.1 regression)
$env1 = ParseEnv (RunEntry @($benchmark))
Check 'baseline: envelope parses' ($null -ne $env1)
Check 'baseline: entrypoint exit 0' ($script:code -eq 0)
if ($null -ne $env1) {
    $ev = Test-SkillResultEnvelope -Envelope $env1
    Check 'baseline: envelope validates against contract' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    Check 'baseline: status ok' ($env1.status -eq 'ok')
    Check 'baseline: skill_version 0.5.0' ($env1.skill_version -eq '0.5.0')
    Check 'baseline: retriever_kind lexical_baseline' ($env1.result.retriever_kind -eq 'lexical_baseline')
    Check 'baseline: input_digest pinned' ($env1.result.input_digest -eq $BASELINE_INPUT_DIGEST)
    Check 'baseline: vector_channel_status empty' ($env1.result.vector_channel_status -eq 'empty')
    Check 'baseline: provenance_validated true' ([bool]$env1.result.provenance_validated)

    $rep = ReadReport $env1 'report.json'
    $repMd = ReadReport $env1 'report.md'
    Check 'baseline: report.json artifact present' ($null -ne $rep)
    Check 'baseline: report.md artifact present' ($null -ne $repMd)
    if ($null -ne $rep) {
        [Console]::Out.WriteLine("CANONICAL-HASH baseline-report.json=$($rep.sha)")
        [Console]::Out.WriteLine("CANONICAL-HASH baseline-report.md=$($repMd.sha)")
        Check 'baseline: report.json declared sha == file sha' ($rep.sha -eq $rep.declared_sha)
        Check 'baseline: report.json sha == pinned (deterministic + known bytes)' ($rep.sha -eq $BASELINE_REPORT_JSON_SHA)
        Check 'baseline: report.md sha == pinned' ($repMd.sha -eq $BASELINE_REPORT_MD_SHA)
        Check 'baseline: report schema 0.5' ($rep.obj.schema -eq 'lifeorch.retrieval_eval_report/0.5')
        # eval-0.3 additive surface present + selection library stamped
        Check 'baseline: selection_policy selpol_rrf_v1' ($rep.obj.selection_policy.policy_id -eq 'selpol_rrf_v1')
        Check 'baseline: hybrid_applicability not_applicable (vector channel empty; P1-4)' ($rep.obj.hybrid_applicability.status -eq 'not_applicable')
        Check 'baseline: per-stage metrics present (raw/post_filter/packet)' ((Has $rep.obj.stage_metrics 'raw') -and (Has $rep.obj.stage_metrics 'post_filter') -and (Has $rep.obj.stage_metrics 'packet'))
        Check 'baseline: aggregate_packet present' (Has $rep.obj 'aggregate_packet')

        $agg = $rep.obj.aggregate_raw
        # KNOWN 0.1 numbers PRESERVED (regression-green)
        Check 'baseline: num_queries 7' ($agg.num_queries -eq 7)
        Check 'baseline: recall@1 macro 857143 ppm (6/7)' ($agg.recall_at_k_ppm.'1' -eq 857143)
        Check 'baseline: recall@5 macro 857143 ppm' ($agg.recall_at_k_ppm.'5' -eq 857143)
        Check 'baseline: recall@10 macro 857143 ppm' ($agg.recall_at_k_ppm.'10' -eq 857143)
        Check 'baseline: MRR 857143 ppm' ($agg.mrr_ppm -eq 857143)
        Check 'baseline: stale-source rate 142857 ppm (1/7)' ($agg.stale_source_rate_ppm -eq 142857)
        Check 'baseline: forbidden-hit rate 142857 ppm (1/7)' ($agg.forbidden_hit_rate_ppm -eq 142857)
        Check 'baseline: provenance completeness 1000000 ppm' ($agg.provenance_completeness_ppm -eq 1000000)
        Check 'baseline: queries_all_required_present 6' ($agg.queries_all_required_present -eq 6)
        # NEW eval-0.2 metrics with KNOWN values
        Check 'baseline: precision@1 857143 ppm' ($agg.precision_at_k_ppm.'1' -eq 857143)
        Check 'baseline: nDCG@5 857143 ppm' ($agg.ndcg_at_k_ppm.'5' -eq 857143)
        Check 'baseline: source-diversity@5 607143 ppm' ($agg.source_diversity_at_k_ppm.'5' -eq 607143)
        Check 'baseline: snippet-span correctness 1000000 ppm' ($agg.snippet_span_correctness_ppm -eq 1000000)
        # provenance VALIDITY < completeness: the lexical baseline mislabels the archived stale copy as
        # current, so validation (status_correct) flags exactly one hit -> 27/28 = 964286 ppm.
        Check 'baseline: provenance validity 964286 ppm (validation catches the stale-copy status error)' ($agg.provenance_validity_ppm -eq 964286)

        # span-strict query q3: the required span matched at rank 1 (span_label carries the heading path)
        $q3 = QById $rep.obj 'q3-retrieval-span'
        Check 'baseline q3: span-strict required source matched at rank 1' ($q3.recall_at_k_ppm.'1' -eq 1000000)
        $q3span = (@($q3.returned | Where-Object { $_.source_path -eq 'guides/retrieval.md' }) | Select-Object -First 1)
        Check 'baseline q3: matched hit carries the required span_label' ($null -ne $q3span -and $q3span.span_label -eq 'Retrieval and embeddings > Recall and provenance')
        Check 'baseline q3: forbidden glossary flagged' (@($q3.forbidden_hits).Count -ge 1)

        # explicit stale COPY: q1 flags the archived superseded copy WITHOUT harming the correct hit
        $q1 = QById $rep.obj 'q1-install'
        Check 'baseline q1: current install.md still matched (recall@1 = 1)' ($q1.recall_at_k_ppm.'1' -eq 1000000)
        Check 'baseline q1: archived stale copy flagged (explicit_stale_hits)' (@($q1.explicit_stale_hits | Where-Object { $_.source_path -eq 'archive/install.v1.md' }).Count -ge 1)

        # organic lexical miss: q7 required source absent -> detected (ACCEPTANCE: required absent -> miss)
        $q7 = QById $rep.obj 'q7-organic-miss'
        Check 'baseline q7: organic miss detected (recall@10 = 0)' ($q7.recall_at_k_ppm.'10' -eq 0)
        Check 'baseline q7: all_required_present false' (-not $q7.all_required_present)
        Check 'baseline q7: missing_required lists the absent source' (@($q7.missing_required | Where-Object { $_.source_path -eq 'reference/contract.md' }).Count -ge 1)
    }
}

# double-run byte identity (same machine)
$env1b = ParseEnv (RunEntry @($benchmark))
if ($null -ne $env1b) {
    $repB = ReadReport $env1b 'report.json'
    Check 'baseline: double-run report.json byte-identical' ($null -ne $repB -and $repB.sha -eq $BASELINE_REPORT_JSON_SHA)
}

# ================================================================= eval-0.2 lexical benchmark (benchmark2)
$env2 = ParseEnv (RunEntry @($benchmark2))
Check 'eval02: envelope parses' ($null -ne $env2)
if ($null -ne $env2) {
    Check 'eval02: status ok' ($env2.status -eq 'ok')
    Check 'eval02: input_digest pinned' ($env2.result.input_digest -eq $B2_INPUT_DIGEST)
    $rep2 = ReadReport $env2 'report.json'
    $rep2Md = ReadReport $env2 'report.md'
    if ($null -ne $rep2) {
        [Console]::Out.WriteLine("CANONICAL-HASH eval02-report.json=$($rep2.sha)")
        [Console]::Out.WriteLine("CANONICAL-HASH eval02-report.md=$($rep2Md.sha)")
        Check 'eval02: report.json sha == pinned (deterministic)' ($rep2.sha -eq $B2_REPORT_JSON_SHA)
        Check 'eval02: report.md sha == pinned' ($rep2Md.sha -eq $B2_REPORT_MD_SHA)
        $a2 = $rep2.obj.aggregate_raw
        Check 'eval02: num_queries 7' ($a2.num_queries -eq 7)
        Check 'eval02: precision@1 571429 ppm' ($a2.precision_at_k_ppm.'1' -eq 571429)
        Check 'eval02: nDCG@5 849557 ppm' ($a2.ndcg_at_k_ppm.'5' -eq 849557)
        Check 'eval02: evidence-group coverage 500000 ppm (b1 all=miss, b2 any=hit)' ($a2.evidence_group_coverage_ppm -eq 500000)
        Check 'eval02: forbidden-hit rate 142857 ppm' ($a2.forbidden_hit_rate_ppm -eq 142857)
        Check 'eval02: privacy-hit rate 142857 ppm' ($a2.privacy_hit_rate_ppm -eq 142857)
        Check 'eval02: no-answer FP rate 500000 ppm (1 of 2 abstains, 1 false-positives)' ($a2.no_answer_false_positive_rate_ppm -eq 500000)
        Check 'eval02: duplicate burden 61905 ppm' ($a2.duplicate_burden_ppm -eq 61905)
        Check 'eval02: source-diversity@5 828571 ppm' ($a2.source_diversity_at_k_ppm.'5' -eq 828571)
        Check 'eval02: provenance validity 979592 ppm' ($a2.provenance_validity_ppm -eq 979592)

        # chunk-level credit: b1 required is a SPECIFIC section; the file appears but the required chunk is
        # not top-K=1 (recall@1=0) yet is found by K=5 -> a wrong chunk from the right file does not score.
        $b1 = QById $rep2.obj 'b1-deploy-current'
        Check 'eval02 b1: chunk-level credit -> required chunk not at rank 1 (recall@1 = 0)' ($b1.recall_at_k_ppm.'1' -eq 0)
        Check 'eval02 b1: required chunk found by K=5 (recall@5 = 1)' ($b1.recall_at_k_ppm.'5' -eq 1000000)
        Check 'eval02 b1: must_include_all group NOT satisfied here (coverage 0)' ($b1.evidence_group_coverage_ppm -eq 0)

        # evidence group ANY satisfied
        $b2q = QById $rep2.obj 'b2-policy-any'
        Check 'eval02 b2: must_include_any group satisfied (coverage 1.0)' ($b2q.evidence_group_coverage_ppm -eq 1000000)

        # privacy/forbidden best-lexical-match is flagged
        $b3 = QById $rep2.obj 'b3-privacy-forbidden'
        Check 'eval02 b3: forbidden personal source flagged' (@($b3.forbidden_hits).Count -ge 1)
        Check 'eval02 b3: privacy-exclusion flagged' (@($b3.privacy_hits).Count -ge 1)

        # no-answer: clean abstain vs false-positive
        $b4 = QById $rep2.obj 'b4-no-answer-clean'
        Check 'eval02 b4: clean abstention (no hits, no FP)' ($b4.abstained -and -not $b4.no_answer_false_positive)
        $b5 = QById $rep2.obj 'b5-no-answer-fp'
        Check 'eval02 b5: no-answer FALSE POSITIVE (attractive-but-wrong distractor surfaced)' ($b5.no_answer_false_positive -and (@($b5.distractor_hits).Count -ge 1))

        # version-specific historical intent: an archived version IS the wanted answer (not a miss)
        $b7 = QById $rep2.obj 'b7-version-specific'
        Check 'eval02 b7: version-specific intent -> archived version matched (recall@1 = 1)' ($b7.recall_at_k_ppm.'1' -eq 1000000)

        # hybrid attribution: the vector channel is EMPTY and reported cleanly
        Check 'eval02: vector channel reported empty' ($rep2.obj.vector_channel_status -eq 'empty')
        $hb2 = HybById $rep2.obj 'b2-policy-any'
        Check 'eval02: hybrid attribution present + vector channel has 0 hits' ($null -ne $hb2 -and $hb2.vector_hit_count -eq 0 -and $hb2.lexical_hit_count -ge 1)
    }
    # double-run identity
    $env2b = ParseEnv (RunEntry @($benchmark2))
    $rep2b = ReadReport $env2b 'report.json'
    Check 'eval02: double-run report.json byte-identical' ($null -ne $rep2b -and $rep2b.sha -eq $B2_REPORT_JSON_SHA)
}

# ================================================================= mock external_command run (0.1 regression)
$env3 = ParseEnv (RunEntry @($mockBench))
Check 'mock: envelope parses' ($null -ne $env3)
if ($null -ne $env3) {
    Check 'mock: status ok' ($env3.status -eq 'ok')
    Check 'mock: external_command retriever seam works' ($env3.result.retriever_kind -eq 'external_command')
    $rep3 = ReadReport $env3 'report.json'
    if ($null -ne $rep3) {
        [Console]::Out.WriteLine("CANONICAL-HASH mock-report.json=$($rep3.sha)")
        Check 'mock: report.json sha == pinned (deterministic)' ($rep3.sha -eq $MOCK_REPORT_JSON_SHA)
        $agg3 = $rep3.obj.aggregate_raw
        Check 'mock: num_queries 4' ($agg3.num_queries -eq 4)
        Check 'mock: recall@1 macro 500000 ppm (2/4)' ($agg3.recall_at_k_ppm.'1' -eq 500000)
        Check 'mock: MRR 500000 ppm' ($agg3.mrr_ppm -eq 500000)
        Check 'mock: stale-source rate 250000 ppm (1/4)' ($agg3.stale_source_rate_ppm -eq 250000)
        Check 'mock: provenance completeness 800000 ppm (4/5)' ($agg3.provenance_completeness_ppm -eq 800000)

        $mq2 = QById $rep3.obj 'mq2-absent'
        Check 'mock mq2 (ABSENT): recall@1 = 0' ($mq2.recall_at_k_ppm.'1' -eq 0)
        Check 'mock mq2 (ABSENT): all_required_present false' (-not $mq2.all_required_present)
        $mq3 = QById $rep3.obj 'mq3-stale-miss'
        Check 'mock mq3 (STALE): recall@1 = 0 (stale hash not a match)' ($mq3.recall_at_k_ppm.'1' -eq 0)
        Check 'mock mq3 (STALE): wrong_version_hits lists docs/e.md' (@($mq3.wrong_version_hits | Where-Object { $_.source_path -eq 'docs/e.md' }).Count -ge 1)
        $mq4 = QById $rep3.obj 'mq4-prov-gap'
        Check 'mock mq4 (PROV-GAP): matched but hit provenance incomplete' ($mq4.recall_at_k_ppm.'1' -eq 1000000 -and @($mq4.returned | Where-Object { -not $_.provenance_complete }).Count -ge 1)
    }
}

# ================================================================= eval-0.2 external retriever (mock2)
$env4 = ParseEnv (RunEntry @($mock2Bench))
Check 'mock2: envelope parses' ($null -ne $env4)
if ($null -ne $env4) {
    Check 'mock2: status ok' ($env4.status -eq 'ok')
    Check 'mock2: input_digest pinned' ($env4.result.input_digest -eq $MOCK2_INPUT_DIGEST)
    Check 'mock2: provenance_validated true (validated against corpus2)' ([bool]$env4.result.provenance_validated)
    $rep4 = ReadReport $env4 'report.json'
    if ($null -ne $rep4) {
        [Console]::Out.WriteLine("CANONICAL-HASH mock2-report.json=$($rep4.sha)")
        Check 'mock2: report.json sha == pinned (deterministic)' ($rep4.sha -eq $MOCK2_REPORT_JSON_SHA)
        $a4 = $rep4.obj.aggregate_raw

        # ACCEPTANCE 1: a required source ABSENT from results -> that query fails
        $mqa = QById $rep4.obj 'mq-a-absent'
        Check 'mock2 mq-a (ABSENT): recall@1 = 0 + missing required' ($mqa.recall_at_k_ppm.'1' -eq 0 -and -not $mqa.all_required_present)

        # ACCEPTANCE 2: a FORBIDDEN source returned -> flagged
        $mqb = QById $rep4.obj 'mq-b-forbidden'
        Check 'mock2 mq-b (FORBIDDEN returned): forbidden_hits >= 1' (@($mqb.forbidden_hits).Count -ge 1)

        # ACCEPTANCE 3: a returned span that does NOT reproduce the cited text -> provenance INVALID
        $mqc = QById $rep4.obj 'mq-c-badspan'
        $mqcHit = (@($mqc.returned) | Select-Object -First 1)
        Check 'mock2 mq-c (BAD SPAN): hit matched (recall@1 = 1) but provenance INVALID' ($mqc.recall_at_k_ppm.'1' -eq 1000000 -and $mqc.provenance_valid -eq 0)
        Check 'mock2 mq-c (BAD SPAN): failed check names span-does-not-reproduce' ($null -ne $mqcHit -and (@($mqcHit.provenance_failed_checks | Where-Object { $_ -eq 'span_reproduces_cited_text' }).Count -ge 1))
        Check 'mock2: provenance validity 875000 ppm (7/8 hits valid)' ($a4.provenance_validity_ppm -eq 875000)

        # DETERMINISTIC RERANKER measured: rescue a required source into top-1 + demote forbidden/stale
        $ab = $rep4.obj.rerank_ab
        Check 'mock2: reranker rescues required into top-1 (>=1 query)' ($ab.queries_with_rescue -ge 1)
        Check 'mock2: reranker demotes forbidden/stale out of top-1 (>=1 query)' ($ab.queries_with_demote -ge 1)
        Check 'mock2: reranker A/B recall@1 uplift +500000 ppm' ($ab.deltas.recall_at_1_ppm -eq 500000)
        Check 'mock2: reranker A/B nDCG@1 uplift +500000 ppm' ($ab.deltas.ndcg_at_1_ppm -eq 500000)

        # per-query rescue+demote on mq-d specifically
        $mqdRaw = QById $rep4.obj 'mq-d-rerank'
        $mqdRe  = QReById $rep4.obj 'mq-d-rerank'
        Check 'mock2 mq-d: RAW recall@1 = 0 (forbidden at rank 1, required lower)' ($mqdRaw.recall_at_k_ppm.'1' -eq 0)
        Check 'mock2 mq-d: RERANKED recall@1 = 1 (required promoted to top)' ($mqdRe.recall_at_k_ppm.'1' -eq 1000000)
        Check 'mock2 mq-d: RERANKED top-1 not forbidden' (@($mqdRe.forbidden_hits | Where-Object { $_.rank -eq 1 }).Count -eq 0)

        # ADDITIVE selection fields (CONTEXT_PACKET_CONTRACT s4 / P1-1): the reranked hit PRESERVES its
        # retrieval_rank and ADDS selection_rank/selection_policy_id/reason_codes -- the retrieval array is
        # never re-sorted in place. mq-d's promoted required source was at retrieval_rank 3.
        $mqdTop = (@($mqdRe.returned) | Where-Object { $_.rank -eq 1 } | Select-Object -First 1)
        Check 'mock2 mq-d: reranked top-1 preserves retrieval_rank 3 (additive, not re-sorted)' ($null -ne $mqdTop -and $mqdTop.retrieval_rank -eq 3 -and $mqdTop.selection_rank -eq 1)
        Check 'mock2 mq-d: reranked top-1 stamped selection_policy_id selpol_rrf_v1' ($mqdTop.selection_policy_id -eq 'selpol_rrf_v1')
        Check 'mock2 mq-d: reranked top-1 reason_codes include rescued + selected' (@($mqdTop.reason_codes | Where-Object { $_ -eq 'rescued' }).Count -ge 1 -and @($mqdTop.reason_codes | Where-Object { $_ -eq 'selected' }).Count -ge 1)

        # hybrid attribution: vector channel empty; a stale hit is attributed as lexical-introduced
        Check 'mock2: vector channel reported empty' ($rep4.obj.vector_channel_status -eq 'empty')
        Check 'mock2: hybrid_applicability not_applicable (P1-4)' ($rep4.obj.hybrid_applicability.status -eq 'not_applicable')
    }
}

# ================================================================= eval-0.3 selpol packet stage (benchmark3)
# selpol_rrf_v1 PACKET stage through the harness: occurrence-preserving DISPLAY dedup, budget -> needs_expansion,
# and packet_disposition scoring (computed + a supplied #40 packet). KNOWN fixture values.
$env8 = ParseEnv (RunEntry @($benchmark3))
Check 'eval03: envelope parses' ($null -ne $env8)
if ($null -ne $env8) {
    Check 'eval03: status ok' ($env8.status -eq 'ok')
    Check 'eval03: input_digest pinned' ($env8.result.input_digest -eq $B3_INPUT_DIGEST)
    $rep8 = ReadReport $env8 'report.json'
    $rep8Md = ReadReport $env8 'report.md'
    if ($null -ne $rep8) {
        [Console]::Out.WriteLine("CANONICAL-HASH eval03-report.json=$($rep8.sha)")
        [Console]::Out.WriteLine("CANONICAL-HASH eval03-report.md=$($rep8Md.sha)")
        Check 'eval03: report.json sha == pinned (deterministic)' ($rep8.sha -eq $B3_REPORT_JSON_SHA)
        Check 'eval03: report.md sha == pinned' ($rep8Md.sha -eq $B3_REPORT_MD_SHA)

        # packet_disposition scoring: 6 labelled, 5 correct (the supplied wrong-answerable packet is caught)
        $de = $rep8.obj.packet_disposition_eval
        Check 'eval03: packet_disposition scored' ([bool]$de.scored)
        Check 'eval03: 6 labelled dispositions' ($de.num_labeled -eq 6)
        Check 'eval03: 5 correct dispositions' ($de.num_correct -eq 5)
        Check 'eval03: disposition accuracy 833333 ppm (5/6)' ($de.accuracy_ppm -eq 833333)
        $d6 = (@($de.per_query | Where-Object { $_.query_id -eq 'd6-supplied-wrong' }) | Select-Object -First 1)
        Check 'eval03 d6: supplied packet disposition scored from the packet (source=packet)' ($null -ne $d6 -and $d6.source -eq 'packet')
        Check 'eval03 d6: WRONG answerable caught (expected abstain, correct=false)' ($d6.expected -eq 'abstain' -and $d6.actual -eq 'answerable' -and (-not $d6.correct))
        $d1 = (@($de.per_query | Where-Object { $_.query_id -eq 'd1-dedup-answerable' }) | Select-Object -First 1)
        Check 'eval03 d1: computed disposition answerable (source=computed)' ($d1.source -eq 'computed' -and $d1.actual -eq 'answerable')
        $d3 = (@($de.per_query | Where-Object { $_.query_id -eq 'd3-needsexp-budget' }) | Select-Object -First 1)
        Check 'eval03 d3: budget -> computed needs_expansion' ($d3.actual -eq 'needs_expansion')

        # occurrence-preserving DISPLAY dedup: raw duplicate burden > 0 collapses to 0 at the packet stage,
        # and the display head carries occurrences[] of BOTH byte-identical members (provenance NOT erased).
        $d1raw = QById $rep8.obj 'd1-dedup-answerable'
        $d1pk  = (@($rep8.obj.per_query_packet | Where-Object { $_.query_id -eq 'd1-dedup-answerable' }) | Select-Object -First 1)
        Check 'eval03 d1: RAW duplicate burden > 0 (both byte-identical dupes retrieved)' ($d1raw.duplicate_burden_ppm -gt 0)
        Check 'eval03 d1: PACKET duplicate burden 0 (occurrence-preserving dedup collapsed them)' ($d1pk.duplicate_burden_ppm -eq 0)
        $dupeHit = (@($d1pk.returned | Where-Object { $_.evidence_cluster_id -and $_.occurrence_count -ge 2 }) | Select-Object -First 1)
        Check 'eval03 d1: one display item carries occurrences of 2 members (dedup DISPLAY, keep provenance)' ($null -ne $dupeHit -and $dupeHit.occurrence_count -eq 2)

        # budget -> omission_manifest (max_selected=1 drops the required Approval chunk)
        $d3pk = (@($rep8.obj.per_query_packet | Where-Object { $_.query_id -eq 'd3-needsexp-budget' }) | Select-Object -First 1)
        Check 'eval03 d3: packet size 1 + omitted (budget)' ($null -ne $d3pk -and $d3pk.packet_size -eq 1 -and @($d3pk.omission_manifest).Count -ge 1)

        # per-stage metrics computed for the packet stage
        Check 'eval03: stage_metrics packet present' (Has $rep8.obj.stage_metrics 'packet')
    }
    # double-run identity
    $env8b = ParseEnv (RunEntry @($benchmark3))
    $rep8b = ReadReport $env8b 'report.json'
    Check 'eval03: double-run report.json byte-identical' ($null -ne $rep8b -and $rep8b.sha -eq $B3_REPORT_JSON_SHA)
}

# ================================================================= eval-0.4 selection conformance (benchmark4, i32 D-0092)
# selpol_rrf_v1 1.1.0 through the harness on a canned retriever-0.2 stream: U1 namespace isolation (a
# cross-namespace distractor SUNK), U4 current_only correctness (a status-stale candidate HARD-excluded) +
# supersession ordering (a live successor above its superseded twin) + contradicts propagation, and the
# selection_conformance measurement block. KNOWN fixture values; deterministic (pinned + double-run).
function QSelConf([object]$report, [string]$id) { return (@($report.per_query_selection_conformance | Where-Object { $_.query_id -eq $id }) | Select-Object -First 1) }
$env9 = ParseEnv (RunEntry @($benchmark4))
Check 'eval04: envelope parses' ($null -ne $env9)
if ($null -ne $env9) {
    Check 'eval04: status ok' ($env9.status -eq 'ok')
    Check 'eval04: skill_version 0.5.0' ($env9.skill_version -eq '0.5.0')
    Check 'eval04: external_command retriever seam works' ($env9.result.retriever_kind -eq 'external_command')
    Check 'eval04: input_digest pinned' ($env9.result.input_digest -eq $B4_INPUT_DIGEST)
    $rep9 = ReadReport $env9 'report.json'
    $rep9Md = ReadReport $env9 'report.md'
    if ($null -ne $rep9) {
        [Console]::Out.WriteLine("CANONICAL-HASH eval04-report.json=$($rep9.sha)")
        [Console]::Out.WriteLine("CANONICAL-HASH eval04-report.md=$($rep9Md.sha)")
        Check 'eval04: report.json sha == pinned (deterministic)' ($rep9.sha -eq $B4_REPORT_JSON_SHA)
        Check 'eval04: report.md sha == pinned' ($rep9Md.sha -eq $B4_REPORT_MD_SHA)
        Check 'eval04: report schema 0.5' ($rep9.obj.schema -eq 'lifeorch.retrieval_eval_report/0.5')
        Check 'eval04: selection policy version 1.2.0' ($rep9.obj.selection_policy.policy_version -eq '1.2.0')
        Check 'eval04: selection policy stamps the canonical ns + classifier policies (i33)' ($rep9.obj.selection_policy.namespace_policy_id -eq 'ns_closed_v1' -and $rep9.obj.selection_policy.classifier_policy_id -eq 'clsmap_v1')
        Check 'eval04: stages include namespace_filter + supersession' ((@($rep9.obj.selection_policy.stages | Where-Object { $_ -eq 'namespace_filter' }).Count -ge 1) -and (@($rep9.obj.selection_policy.stages | Where-Object { $_ -eq 'supersession' }).Count -ge 1))

        # the selection_conformance aggregate: ZERO violations; the i33 CLOSURE now DROPS the cross-namespace
        # distractor (sanitized) so it no longer appears as a hard_filter_namespace reason code -- the leak fix.
        $sc = $rep9.obj.selection_conformance
        Check 'eval04: selection_conformance present' ($null -ne $sc)
        Check 'eval04 U1'' closure: 0 isolation + 0 diagnostic-array leaks; the cross-ns candidate DROPPED (sanitized count >=1)' ($sc.namespace_isolation_violations -eq 0 -and $sc.namespace_closure_violations -eq 0 -and $sc.cross_namespace_candidates_total -ge 1 -and $sc.cross_namespace_in_ranked_total -eq 0 -and $sc.namespace_violations_total -ge 1)
        Check 'eval04 U4: current_only_stale_leaks == 0 (with a status-stale candidate present)' ($sc.current_only_stale_leaks -eq 0 -and $sc.stale_candidates_total -ge 1)
        Check 'eval04 U4'' pool-independent: 0 not-effective-current leaks' ($sc.pool_independent_current_only_leaks -eq 0)
        Check 'eval04 U4: supersession_order_violations == 0 over >=1 pair' ($sc.supersession_order_violations -eq 0 -and $sc.supersession_pairs_total -ge 1 -and $sc.supersession_pairs_correct -eq $sc.supersession_pairs_total)
        Check 'eval04 U4: 1 query surfaced a contradicts pair' ($sc.queries_with_contradicts -eq 1)
        Check 'eval04: reason-code coverage includes the temporal + supersession codes' ((@($sc.reason_code_coverage | Where-Object { $_ -eq 'hard_filter_stale' }).Count -ge 1) -and (@($sc.reason_code_coverage | Where-Object { $_ -eq 'superseded_demote' }).Count -ge 1))

        # per-query proofs
        $n1 = QSelConf $rep9.obj 'n1-namespace-isolation'
        Check 'eval04 n1 (U1''): a cross-namespace candidate exists, 0 selected, 0 in ranked[] (DROPPED, sanitized)' ($null -ne $n1 -and $n1.cross_namespace_candidates -ge 1 -and $n1.cross_namespace_selected -eq 0 -and $n1.cross_namespace_in_ranked -eq 0 -and $n1.namespace_closure_ok -and $n1.namespace_violation_count -ge 1)
        $n2 = QSelConf $rep9.obj 'n2-current-only'
        Check 'eval04 n2 (U4): current_only mode; no stale leaked into selection' ($null -ne $n2 -and $n2.current_only -and $n2.stale_selected_under_current_only -eq 0)
        $n3 = QSelConf $rep9.obj 'n3-supersession'
        Check 'eval04 n3 (U4): the selected superseded/successor pair is correctly ordered' ($null -ne $n3 -and $n3.supersession_pairs_total -eq 1 -and $n3.supersession_order_ok)
        $n4 = QSelConf $rep9.obj 'n4-contradiction'
        Check 'eval04 n4 (U4): a contradicts pair is surfaced (propagated, not detected)' ($null -ne $n4 -and @($n4.contradicts_pairs).Count -eq 1)
    }
    # double-run identity
    $env9b = ParseEnv (RunEntry @($benchmark4))
    $rep9b = ReadReport $env9b 'report.json'
    Check 'eval04: double-run report.json byte-identical' ($null -ne $rep9b -and $rep9b.sha -eq $B4_REPORT_JSON_SHA)
}

# ================================================================= eval-0.5 NAMESPACE-CLOSURE leakage paths (benchmark5, i33 D-0096)
# selpol_rrf_v1 1.2.0 through the harness on a canned retriever-0.2 stream: U1' namespace CLOSURE (a
# cross-namespace distractor that OUTSCORES the answer is DROPPED + sanitized -- 0 in ranked[], only the
# violation count surfaces), U4' pool-INDEPENDENT current_only (a superseded high-scorer whose successor is
# ABSENT is still excluded), U4' supersession-chain ordering + branch->conflicted, and U5' the query_class/
# temporal_intent split with an explicit override. KNOWN fixture values; deterministic (pinned + double-run).
$env10 = ParseEnv (RunEntry @($benchmark5))
Check 'eval05: envelope parses' ($null -ne $env10)
if ($null -ne $env10) {
    Check 'eval05: status ok' ($env10.status -eq 'ok')
    Check 'eval05: skill_version 0.5.0' ($env10.skill_version -eq '0.5.0')
    Check 'eval05: input_digest pinned' ($env10.result.input_digest -eq $B5_INPUT_DIGEST)
    $rep10 = ReadReport $env10 'report.json'
    $rep10Md = ReadReport $env10 'report.md'
    if ($null -ne $rep10) {
        [Console]::Out.WriteLine("CANONICAL-HASH eval05-report.json=$($rep10.sha)")
        [Console]::Out.WriteLine("CANONICAL-HASH eval05-report.md=$($rep10Md.sha)")
        Check 'eval05: report.json sha == pinned (deterministic)' ($rep10.sha -eq $B5_REPORT_JSON_SHA)
        Check 'eval05: report.md sha == pinned' ($rep10Md.sha -eq $B5_REPORT_MD_SHA)
        Check 'eval05: report schema 0.5' ($rep10.obj.schema -eq 'lifeorch.retrieval_eval_report/0.5')

        $sc5 = $rep10.obj.selection_conformance
        # U1' NAMESPACE CLOSURE: the distractor is DROPPED (sanitized) -- 0 in any diagnostic array, count surfaces
        Check 'eval05 U1'' closure: a cross-ns distractor present but 0 selected AND 0 in ranked[] (leak closed)' ($sc5.cross_namespace_candidates_total -ge 1 -and $sc5.cross_namespace_selected_total -eq 0 -and $sc5.cross_namespace_in_ranked_total -eq 0)
        Check 'eval05 U1'' closure: the drop surfaces ONLY as a sanitized violation count (>=1) + a drop query' ($sc5.namespace_violations_total -ge 1 -and $sc5.queries_with_namespace_drop -ge 1 -and $sc5.namespace_closure_violations -eq 0)
        # U4' POOL-INDEPENDENT current_only: a not-effective-current candidate (absent successor) never selected
        Check 'eval05 U4'' pool-independent: 0 leaks over >=1 not-effective-current candidate' ($sc5.pool_independent_current_only_leaks -eq 0 -and $sc5.noncurrent_candidates_total -ge 1)
        # U4' supersession chain + branch
        Check 'eval05 U4'' supersession: >=1 pair correctly ordered; 0 violations' ($sc5.supersession_pairs_total -ge 1 -and $sc5.supersession_order_violations -eq 0)
        Check 'eval05 U4'' branch: >=1 query surfaced a supersession branch conflict (conflicted)' ($sc5.queries_with_supersession_branch -ge 1 -and $sc5.queries_conflicted -ge 1)
        Check 'eval05: reason-code coverage includes conflicted + superseded_demote' ((@($sc5.reason_code_coverage | Where-Object { $_ -eq 'conflicted' }).Count -ge 1) -and (@($sc5.reason_code_coverage | Where-Object { $_ -eq 'superseded_demote' }).Count -ge 1))

        # per-query proofs
        $c1 = QSelConf $rep10.obj 'c1-closure-drop'
        Check 'eval05 c1 (U1''): the higher-scoring nsB distractor is DROPPED, the nsA answer wins' ($null -ne $c1 -and $c1.cross_namespace_in_ranked -eq 0 -and $c1.namespace_violation_count -eq 1 -and $c1.namespace_closure_ok)
        $c1pk = (@($rep10.obj.per_query_packet | Where-Object { $_.query_id -eq 'c1-closure-drop' }) | Select-Object -First 1)
        Check 'eval05 c1: the in-namespace required answer is selected at rank 1 (recall@1 = 1)' ($null -ne $c1pk -and $c1pk.recall_at_k_ppm.'1' -eq 1000000)
        $c2 = QSelConf $rep10.obj 'c2-pool-independent-current-only'
        Check 'eval05 c2 (U4''): current_only; the superseded absent-successor high-scorer is NOT selected (pool-independent)' ($null -ne $c2 -and $c2.current_only -and $c2.noncurrent_candidates -ge 1 -and $c2.noncurrent_selected_under_current_only -eq 0 -and $c2.pool_independent_current_only_ok)
        $c3 = QSelConf $rep10.obj 'c3-supersession-chain'
        Check 'eval05 c3 (U4''): the live successor ordered above its superseded predecessor' ($null -ne $c3 -and $c3.supersession_pairs_total -eq 1 -and $c3.supersession_order_ok)
        $c4 = QSelConf $rep10.obj 'c4-supersession-branch'
        Check 'eval05 c4 (U4''): a two-successor branch is surfaced (supersession_conflicts) + conflicted' ($null -ne $c4 -and @($c4.supersession_conflicts).Count -eq 1 -and $c4.conflicted)
        $c5 = QSelConf $rep10.obj 'c5-split-explicit-override'
        Check 'eval05 c5 (U5''): an explicit temporal_intent OUTRANKS the query_class default (any_valid_version, not current_only)' ($null -ne $c5 -and $c5.temporal_intent -eq 'any_valid_version' -and (-not $c5.current_only) -and $c5.temporal_intent_source -eq 'intent:explicit_temporal_intent')
    }
    # double-run identity
    $env10b = ParseEnv (RunEntry @($benchmark5))
    $rep10b = ReadReport $env10b 'report.json'
    Check 'eval05: double-run report.json byte-identical' ($null -ne $rep10b -and $rep10b.sha -eq $B5_REPORT_JSON_SHA)
}

# ================================================================= fail-closed error paths
$missing = Join-Path $fxDir 'does-not-exist.json'
$env5 = ParseEnv (RunEntry @($missing))
Check 'error: missing benchmark -> status error' ($null -ne $env5 -and $env5.status -eq 'error')
Check 'error: missing benchmark -> code benchmark_not_found' ($null -ne $env5 -and $null -ne $env5.error -and $env5.error.code -eq 'benchmark_not_found')
Check 'error: missing benchmark -> exit 0 (envelope still produced)' ($script:code -eq 0)
if ($null -ne $env5) { $ev5 = Test-SkillResultEnvelope -Envelope $env5; Check 'error: error envelope still validates' ([bool]$ev5.valid) }

$badBench = Join-Path ([System.IO.Path]::GetTempPath()) ("re-bad-" + [Guid]::NewGuid().ToString('N') + '.json')
[System.IO.File]::WriteAllText($badBench, '{"schema":"lifeorch.retrieval_benchmark/0.2","benchmark_id":"bad","retriever":{"kind":"lexical_baseline","corpus_dir":"corpus"},"queries":[]}', [System.Text.UTF8Encoding]::new($false))
$env6 = ParseEnv (RunEntry @($badBench))
Check 'error: empty-queries benchmark -> status error' ($null -ne $env6 -and $env6.status -eq 'error')
Remove-Item -LiteralPath $badBench -Force -ErrorAction SilentlyContinue

# a bad temporal_intent -> fail-closed
$badTi = Join-Path ([System.IO.Path]::GetTempPath()) ("re-badti-" + [Guid]::NewGuid().ToString('N') + '.json')
[System.IO.File]::WriteAllText($badTi, '{"schema":"lifeorch.retrieval_benchmark/0.2","benchmark_id":"badti","retriever":{"kind":"lexical_baseline","corpus_dir":"corpus2"},"queries":[{"query_id":"x","query":"deploy","temporal_intent":"whenever","required_sources":[]}]}', [System.Text.UTF8Encoding]::new($false))
# corpus2 is relative to the temp dir here, so this fails either on temporal_intent or corpus_dir -- both are fail-closed error envelopes.
$env7 = ParseEnv (RunEntry @($badTi))
Check 'error: invalid temporal_intent / bad corpus -> status error' ($null -ne $env7 -and $env7.status -eq 'error')
Remove-Item -LiteralPath $badTi -Force -ErrorAction SilentlyContinue

# ================================================================= Module 1 wrapper
if (Test-Path -LiteralPath $wrapper -PathType Leaf) {
    $inputsJson = (@{ benchmark = $benchmark } | ConvertTo-Json -Compress)
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
if ($script:fail -eq 0) { [Console]::Out.WriteLine("ALL PASS (retrieval.eval eval-0.2)"); exit 0 }
else { [Console]::Out.WriteLine("FAILURES: $script:fail"); exit 1 }
