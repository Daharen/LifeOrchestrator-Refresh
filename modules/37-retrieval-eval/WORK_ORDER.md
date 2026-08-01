# Work Order: Retrieval Evaluation Harness (`retrieval.eval`)

**Contract version targeted:** 0.2 · **Author:** FANOUT_AGENT_003 (RETRIEVAL-EVAL-i25) / 2026-08-01 ·
**Roadmap entry:** Wave 1 CPU lane (plan fo-25-3b718a13; D-0080 Priority 2)

### Problem being solved

Wave 1 builds the memory/retrieval substrate (embedding adapter, `artifact.search`). Before any vector
integration is trusted, retrieval quality must be MEASURABLE. This module makes it measurable: a benchmark
of queries with known required-source labels, a deterministic lexical baseline for a known floor, and
recall@K / MRR / stale-source / provenance metrics with deterministic machine + human reports.

### Immediate practical use

The orchestrator runs this at the Wave 1 fold (D-0077 smoke): point the harness's `external_command`
retriever at the real `artifact.search`, run the benchmark, and read measured retrieval quality (vs the
baseline floor) with source-resolved provenance -- the gate that "no retrieval system is accepted without
measured retrieval quality" (design doc Priority 2).

### Explicit scope (in)

- Benchmark schema `lifeorch.retrieval_benchmark/0.1`: query + required-source labels (+ optional
  stale/superseded + forbidden sources), version-aware matching.
- A fully-known fixture corpus + an initial Life Orchestrator benchmark question set.
- A deterministic lexical baseline retriever (BM25-lite) satisfying the D-0077 retriever interface.
- Metrics: recall@K, MRR, stale-source rate, provenance completeness (+ forbidden-hit rate).
- Reports: `report.json` (machine, `lifeorch.retrieval_eval_report/0.1`) + `report.md` (human), both
  canonical/deterministic.
- An `external_command` retriever adapter (the fold seam) + a conforming mock retriever fixture.

### Non-goals (out -- do NOT build)

- A production router / reranker; the real embedding provider; `artifact.search` itself; a UI; summaries.
- Any model / CUDA / network dependency.

### Dependencies

- Modules: #0 executor + #0 dev.ship (ship path), #1 skill contract (manifest/envelope validators + generic
  wrapper), #29 res.lease (git lease at ship). Tools: `pwsh>=7.4`, `python>=3.8` (stdlib only).
- Contract features: `lifeorch.skill.manifest/0.1`, `lifeorch.skill.result/0.1`, `-InputsJson`,
  skill-relative artifact root with absolute paths in the envelope.

### Skill contract requirements

`skill_id retrieval.eval`, `version 0.1.0`, `determinism deterministic`, `parallel_safe true`, `batch
false`, `streaming false`. `result` = the aggregate + report pointers (see skill.json outputs).
`confidence` = null (deterministic); `model_provenance` = []; artifact kinds `json` + `markdown`.

### Inputs and outputs

- **Inputs:** `benchmark` (file path or inline object; required), `corpus_dir?`, `retriever?`, `k_values?`,
  `retrieval_depth?`, `base_dir?` (per skill.json).
- **Outputs:** `result` aggregate + `report_json`/`report_md` pointers + `input_digest`; artifacts
  `report.json`, `report.md`, `worker-summary.json`.

### Artifact structure

- `runtime/artifacts/<invocation_id>/` -> `report.json`, `report.md`, `worker-summary.json`, `request.json`,
  `worker-stderr.txt`, `result.json`.

### Proposed implementation

- **Language:** thin pwsh contract wrapper over a stdlib-only Python worker (mirrors the #15/#16 pattern).
  Python carries the determinism-critical logic (stable sort, canonical JSON, integer-only ppm/millionths)
  where determinism is easiest to guarantee; pwsh owns the contract envelope + the executor/dev.ship rails.

### External tools or models

- None beyond `pwsh` + any `python3`. No model, no embedding provider (mock only), no network.

### Installation steps

- None. The worker imports only the Python standard library.

### Tests

- **Direct/off-machine:** `tests/Invoke-RetrievalEvalTests.ps1` runs the REAL entrypoint on the cloud box
  (pwsh 7.4.6 + system python) -- AST gate, py_compile gate, manifest + envelope validation, known-baseline
  numbers, pinned canonical sha + double-run identity, absence / staleness-as-miss / provenance-gap cases,
  span-strict matching, the external_command seam, fail-closed error envelopes, the Module 1 wrapper.
- **Through the executor (`-Live`):** the same harness on the Windows executor; assert cross-env
  CANONICAL-HASH parity, 0 orphaned llama-server/python, `review_queue.jsonl` before == after.

### MVP acceptance criteria

- [x] Deterministic benchmark run: same corpus+queries+retriever -> byte-identical `report.json`/`report.md`
      (pinned sha256 + double-run identity).
- [x] The known lexical-baseline numbers are reproduced.
- [x] A test that FAILS when a required source is ABSENT from results (mq2-absent -> recall 0 +
      missing_required + all_required_present false).
- [x] A version/staleness test: a stale/superseded source is counted as a MISS (mq3 wrong-version + baseline
      q1 explicit stale copy).
- [x] Machine- and human-readable reports emitted.

### Manual verification procedure

- Run the baseline; open `report.md`; confirm recall/MRR/stale/forbidden/provenance match the README and
  that per-query MISSING/STALE/FORBIDDEN annotations read correctly.

### Documentation requirements

- `README.md` + `skill.json` + `SCHEMA_NOTES.md` (D-0077) + `examples/` -- all present.

### Registry / state updates

- Worker holds `docs:[]`: the ORCHESTRATOR mirrors + folds all core-docs (TOOL_MODEL_REGISTRY / CURRENT_STATE
  / MODULE_ROADMAP / DECISION_LOG) from this worker's report. This worker edits NO core-doc.

### Known follow-on work

- Failure-memory trigger-recall metric (design doc 11.1) once failure memory exists (Wave 2).
- Context-packet-size + task-success-with/without-retrieval metrics once the context compiler exists.
- Wire the real `artifact.search` behind the `external_command` retriever at the orchestrator fold.

### STOP conditions

- MVP acceptance met -> stop; do not build a router, an embedder, or `artifact.search`.
- docs:[] -> never edit a core-doc; report and let the orchestrator fold.
