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
$mockBench  = Join-Path $fxDir 'mock-benchmark.json'
$mock2Bench = Join-Path $fxDir 'mock2-benchmark.json'
$mockRetr   = Join-Path $fxDir 'mock-retriever.py'

# ---- KNOWN pins (hand-verified; also the cross-env byte-identity pins) ----
$BASELINE_REPORT_JSON_SHA = '598dc1be78f97bfff06f1784f16f1a01d3ac3dbe2398c2818f726575d726779a'
$BASELINE_REPORT_MD_SHA   = '6264cb1b31ac173ccbd085313a11d5ef29a6711aac9f9180e6819021c30ff481'
$BASELINE_INPUT_DIGEST    = 'sha256:aff6a477f6be0ca7c7cc2ed174a9e28ff72c34683fa6dd4464a52ceb6ea6d1ae'
$B2_REPORT_JSON_SHA       = '06878847284bd93743c85d2e8768170f62cb666c1f78e69961a2f6d3371fd51e'
$B2_REPORT_MD_SHA         = '1c9ae9314a60a5b7f081a73d67b037c0f964d37e99e84fe1a9682e2529c287b5'
$B2_INPUT_DIGEST          = 'sha256:58569e41667d07d660ec6f842b120e140d26362fc2830da43ac872aeb566bc79'
$MOCK_REPORT_JSON_SHA     = 'b5d55da9277ecc2922df2827a9439abc618aba2e5d2301d9795388de670cea3a'
$MOCK2_REPORT_JSON_SHA    = '70dc60e53e0d9668201a4373fe0b851b126100eb972f4716d2531cb22ce4f9b8'
$MOCK2_INPUT_DIGEST       = 'sha256:7d16bbaafe1568eee9ee211d8ad2ed1d0da45037692090dd0222a189d583c613'

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
    foreach ($pyf in @($worker, $mockRetr)) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $py -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" $pyf 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev
        Check "py_compile OK: $(Split-Path -Leaf $pyf)" $ok
    }
}

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id retrieval.eval' ($manifest.skill_id -eq 'retrieval.eval')
Check 'manifest version 0.2.0' ($manifest.version -eq '0.2.0')
Check 'manifest contract_version 0.2' ($manifest.contract_version -eq '0.2')
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
    Check 'baseline: skill_version 0.2.0' ($env1.skill_version -eq '0.2.0')
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
        Check 'baseline: report schema 0.2' ($rep.obj.schema -eq 'lifeorch.retrieval_eval_report/0.2')

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

        # hybrid attribution: vector channel empty; a stale hit is attributed as lexical-introduced
        Check 'mock2: vector channel reported empty' ($rep4.obj.vector_channel_status -eq 'empty')
    }
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
