#requires -Version 7.0
<#
  Invoke-RetrievalEvalTests.ps1 -- regression tests for retrieval.eval (Module 37, Wave 1 CPU lane).

  DUAL-MODE + OS-portable (a REAL-skill gate, not a mock): retrieval.eval is pure deterministic logic
  (a stdlib-only Python worker behind a thin pwsh contract wrapper -- no CUDA, no model, no network, no
  OS-specific API), so the SAME harness runs the REAL Invoke-RetrievalEval.ps1 on the cloud Linux box
  (pre-ship gate) and on the Windows executor (-Live). Fixtures are COMMITTED under tests/fixtures/:
    corpus/                a fully-known doc set (incl. archive/install.v1.md -- a superseded copy)
    benchmark.json         the initial Life Orchestrator benchmark (7 queries, required-source labels,
                           an explicit stale copy, a span-strict query, a forbidden-source query, an
                           organic lexical miss)
    mock-benchmark.json    an external_command benchmark driving the absence / staleness-as-miss /
                           provenance-gap acceptance cases
    mock-retriever.py + mock-plan.json   a contract-conforming external retriever fixture (the seam
                           the orchestrator points at the real artifact.search at fold)

  It exercises: AST parse of the shipped .ps1; a py_compile syntax gate on the Python files; manifest +
  result-envelope contract validation; the KNOWN lexical-baseline numbers; DETERMINISTIC canonical
  report bytes (pinned sha256 + double-run identity); a FAILING-on-absent-required case; a
  version/staleness-as-MISS case (both the explicit-stale-copy and the wrong-version modes); provenance
  completeness (and a provenance-GAP that lowers it); span-strict matching; the external_command seam;
  fail-closed error envelopes; and the Module 1 wrapper. It PRINTS `CANONICAL-HASH <name>=<sha256>` lines
  so the cloud and -Live runs can be compared for cross-environment byte-identity.

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
$benchmark = Join-Path $fxDir 'benchmark.json'
$mockBench = Join-Path $fxDir 'mock-benchmark.json'
$mockRetr  = Join-Path $fxDir 'mock-retriever.py'

# ---- KNOWN baseline constants (hand-verified; also the cross-env byte-identity pins) ----
$BASELINE_REPORT_JSON_SHA = '93af1960a80e00400dd0d9514459817176acdce070044612d14ce59c829a85c7'
$BASELINE_REPORT_MD_SHA   = '57e94a581adc3a9087cfa912c5677a09b57c8a8ffdf4980fff30ed382c07ac3c'
$BASELINE_INPUT_DIGEST    = 'sha256:5d9ceb3b8e98ecf9ef4504e87827f80cf81d935070b4797e79ec623c8a999aa9'
$MOCK_REPORT_JSON_SHA     = '07e1ed3d676a5bb916bf28ba1749e25f74b828dee41a9494b9b88b7b03262e36'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== retrieval.eval tests ($mode); pwsh=$PwshPath python=$([string]::IsNullOrEmpty($PythonPath) ? '(auto)' : $PythonPath) ==")

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
function RunEntryRaw([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
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
function QById([object]$report, [string]$id) { return (@($report.per_query | Where-Object { $_.query_id -eq $id }) | Select-Object -First 1) }

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
Check 'manifest version 0.1.0' ($manifest.version -eq '0.1.0')
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest parallel_safe' ([bool]$manifest.parallel_safe)

# ================================================================= baseline run
$env1 = ParseEnv (RunEntry @($benchmark))
Check 'baseline: envelope parses' ($null -ne $env1)
Check 'baseline: entrypoint exit 0' ($script:code -eq 0)
if ($null -ne $env1) {
    $ev = Test-SkillResultEnvelope -Envelope $env1
    Check 'baseline: envelope validates against contract' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    Check 'baseline: status ok' ($env1.status -eq 'ok')
    Check 'baseline: retriever_kind lexical_baseline' ($env1.result.retriever_kind -eq 'lexical_baseline')
    Check 'baseline: input_digest pinned' ($env1.result.input_digest -eq $BASELINE_INPUT_DIGEST)

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

        $agg = $rep.obj.aggregate
        # KNOWN lexical-baseline numbers (hand-verified over the fixture corpus)
        Check 'baseline: num_queries 7' ($agg.num_queries -eq 7)
        Check 'baseline: recall@1 macro 857143 ppm (6/7)' ($agg.recall_at_k_ppm.'1' -eq 857143)
        Check 'baseline: recall@5 macro 857143 ppm' ($agg.recall_at_k_ppm.'5' -eq 857143)
        Check 'baseline: recall@10 macro 857143 ppm' ($agg.recall_at_k_ppm.'10' -eq 857143)
        Check 'baseline: MRR 857143 ppm' ($agg.mrr_ppm -eq 857143)
        Check 'baseline: stale-source rate 142857 ppm (1/7)' ($agg.stale_source_rate_ppm -eq 142857)
        Check 'baseline: forbidden-hit rate 142857 ppm (1/7)' ($agg.forbidden_hit_rate_ppm -eq 142857)
        Check 'baseline: provenance completeness 1000000 ppm' ($agg.provenance_completeness_ppm -eq 1000000)
        Check 'baseline: queries_all_required_present 6' ($agg.queries_all_required_present -eq 6)

        # every returned hit fully attributable (provenance completeness == 1.0 => all true)
        $allProv = $true
        foreach ($q in $rep.obj.per_query) { foreach ($r in $q.returned) { if (-not $r.provenance_complete) { $allProv = $false } } }
        Check 'baseline: every returned hit has complete provenance' $allProv

        # span-strict query q3: required has require_span -> matched with the correct span
        $q3 = QById $rep.obj 'q3-retrieval-span'
        Check 'baseline q3: span-strict required source matched at rank 1' ($q3.recall_at_k_ppm.'1' -eq 1000000)
        $q3span = (@($q3.returned | Where-Object { $_.source_path -eq 'guides/retrieval.md' }) | Select-Object -First 1)
        Check 'baseline q3: matched hit carries the required span' ($null -ne $q3span -and $q3span.span -eq 'Retrieval and embeddings > Recall and provenance')
        Check 'baseline q3: forbidden glossary flagged' (@($q3.forbidden_hits).Count -ge 1)

        # explicit stale COPY: q1 flags the archived superseded copy WITHOUT harming the correct hit
        $q1 = QById $rep.obj 'q1-install'
        Check 'baseline q1: current install.md still matched (recall@1 = 1)' ($q1.recall_at_k_ppm.'1' -eq 1000000)
        Check 'baseline q1: archived stale copy flagged (explicit_stale_hits)' (@($q1.explicit_stale_hits | Where-Object { $_.source_path -eq 'archive/install.v1.md' }).Count -ge 1)

        # organic lexical miss: q7 required source absent -> detected
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

# ================================================================= mock external_command run
$env2 = ParseEnv (RunEntry @($mockBench))
Check 'mock: envelope parses' ($null -ne $env2)
if ($null -ne $env2) {
    $ev2 = Test-SkillResultEnvelope -Envelope $env2
    Check 'mock: envelope validates against contract' ([bool]$ev2.valid)
    Check 'mock: status ok' ($env2.status -eq 'ok')
    Check 'mock: external_command retriever seam works' ($env2.result.retriever_kind -eq 'external_command')

    $rep2 = ReadReport $env2 'report.json'
    if ($null -ne $rep2) {
        [Console]::Out.WriteLine("CANONICAL-HASH mock-report.json=$($rep2.sha)")
        Check 'mock: report.json sha == pinned (deterministic)' ($rep2.sha -eq $MOCK_REPORT_JSON_SHA)
        $agg2 = $rep2.obj.aggregate
        Check 'mock: num_queries 4' ($agg2.num_queries -eq 4)
        Check 'mock: recall@1 macro 500000 ppm (2/4)' ($agg2.recall_at_k_ppm.'1' -eq 500000)
        Check 'mock: MRR 500000 ppm' ($agg2.mrr_ppm -eq 500000)
        Check 'mock: stale-source rate 250000 ppm (1/4)' ($agg2.stale_source_rate_ppm -eq 250000)
        Check 'mock: provenance completeness 800000 ppm (4/5)' ($agg2.provenance_completeness_ppm -eq 800000)
        Check 'mock: queries_all_required_present 2' ($agg2.queries_all_required_present -eq 2)

        # ACCEPTANCE: a required source ABSENT from results -> the harness fails that query
        $mq2 = QById $rep2.obj 'mq2-absent'
        Check 'mock mq2 (ABSENT): recall@1 = 0' ($mq2.recall_at_k_ppm.'1' -eq 0)
        Check 'mock mq2 (ABSENT): all_required_present false' (-not $mq2.all_required_present)
        Check 'mock mq2 (ABSENT): missing_required lists docs/b.md' (@($mq2.missing_required | Where-Object { $_.source_path -eq 'docs/b.md' }).Count -ge 1)

        # ACCEPTANCE: a stale/superseded version counted as a MISS (wrong-version mode)
        $mq3 = QById $rep2.obj 'mq3-stale-miss'
        Check 'mock mq3 (STALE): recall@1 = 0 (stale hash not a match)' ($mq3.recall_at_k_ppm.'1' -eq 0)
        Check 'mock mq3 (STALE): wrong_version_hits lists docs/e.md' (@($mq3.wrong_version_hits | Where-Object { $_.source_path -eq 'docs/e.md' }).Count -ge 1)
        Check 'mock mq3 (STALE): stale_affected true' ([bool]$mq3.stale_affected)
        Check 'mock mq3 (STALE): required source counted missing' (@($mq3.missing_required | Where-Object { $_.source_path -eq 'docs/e.md' }).Count -ge 1)

        # provenance GAP lowers completeness independently of recall
        $mq4 = QById $rep2.obj 'mq4-prov-gap'
        Check 'mock mq4 (PROV-GAP): matched (recall@1 = 1) but hit provenance incomplete' ($mq4.recall_at_k_ppm.'1' -eq 1000000 -and @($mq4.returned | Where-Object { -not $_.provenance_complete }).Count -ge 1)
    }
}

# ================================================================= fail-closed error paths
$missing = Join-Path $fxDir 'does-not-exist.json'
$env3 = ParseEnv (RunEntry @($missing))
Check 'error: missing benchmark -> status error' ($null -ne $env3 -and $env3.status -eq 'error')
Check 'error: missing benchmark -> code benchmark_not_found' ($null -ne $env3 -and $null -ne $env3.error -and $env3.error.code -eq 'benchmark_not_found')
Check 'error: missing benchmark -> exit 0 (envelope still produced)' ($script:code -eq 0)
if ($null -ne $env3) { $ev3 = Test-SkillResultEnvelope -Envelope $env3; Check 'error: error envelope still validates' ([bool]$ev3.valid) }

# a structurally-invalid benchmark (no queries) -> worker error surfaced fail-closed
$badBench = Join-Path ([System.IO.Path]::GetTempPath()) ("re-bad-" + [Guid]::NewGuid().ToString('N') + '.json')
[System.IO.File]::WriteAllText($badBench, '{"schema":"lifeorch.retrieval_benchmark/0.1","benchmark_id":"bad","retriever":{"kind":"lexical_baseline","corpus_dir":"corpus"},"queries":[]}', [System.Text.UTF8Encoding]::new($false))
$env4 = ParseEnv (RunEntry @($badBench))
Check 'error: empty-queries benchmark -> status error' ($null -ne $env4 -and $env4.status -eq 'error')
Remove-Item -LiteralPath $badBench -Force -ErrorAction SilentlyContinue

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
if ($script:fail -eq 0) { [Console]::Out.WriteLine("ALL PASS (retrieval.eval)"); exit 0 }
else { [Console]::Out.WriteLine("FAILURES: $script:fail"); exit 1 }
