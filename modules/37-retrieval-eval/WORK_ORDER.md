# Work Order: retrieval.eval -- 0.2.0 -> 0.3.0 (selpol_rrf_v1 + eval-0.3)

**Contract version targeted:** 0.3 · **Author:** FANOUT_AGENT_002 (SELECTION-POLICY-i30) / 2026-08-03 ·
**Roadmap:** Wave 3 CONTRACT-HARDENING, CPU lane (plan fo-30-dd453156; D-0087 CONTEXT_PACKET_CONTRACT s4 +
MEMORY_CONTRACT A2/A3; P1-1). Predecessor: 0.2.0 (RETRIEVAL-QUALITY-i29, plan fo-29-87dbfa0b).

### Problem being solved

Two selection implementations diverged: #37 shipped a standalone deterministic `rerank()`; #40 shipped a
self-contained composite score. The frontier Wave-3 red-team's **P1-1** requires exactly ONE versioned
deterministic selection-policy library, OWNED by #37 and CONSUMED by #40 + #37's own eval A/B. This revision
authors that library (`selpol_rrf_v1`) extracted from `rerank()`, and refines the eval harness to score
per-stage + `packet_disposition` (the P1-4 subset i30 needs).

### Explicit scope (in) -- touch ONLY `modules/37-retrieval-eval`

- **`lib/selpol_rrf_v1.py`** -- the s4 interface `select(candidates, descriptor, policy_id, params) ->
  {selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[]}`. PURE +
  deterministic (stdlib). Stages: hard filters -> temporal stale-demote (s5) -> authority (epistemic_authority)
  -> versioned RRF over CHANNEL RANKS (retrieval_occurrences[]; P1-2) -> occurrence-preserving DISPLAY dedup
  (identical text -> one display item + occurrences[] + evidence_cluster_id; P1-3) -> budget. Output ADDITIVE:
  preserves retrieval_rank/lexical_rank/vector_rank/fused_rank; adds selection_rank/selection_score/
  selection_policy_id/selected/reason_codes; NEVER re-sorts the retrieval array in place.
- **Adopt it in the harness:** `rerank()` becomes a thin wrapper over `selpol_rrf_v1` (the measured A/B measures
  the library). The shipped 0.2 benchmark + reranker A/B stay GREEN (regression -- metric VALUES byte-preserved).
- **Eval refinement (P1-4 subset):** score PER STAGE (raw / post-filter / packet) + `packet_disposition`
  correctness (read from a supplied #40 packet or computed deterministically); mark hybrid metrics
  `not_applicable` (NOT zero) while the vector channel is EMPTY. Full graded-relevance P1-4 is a named follow-on.
- Fixtures proving the library RESCUES a required source out of raw top-K + DEMOTES a stale/forbidden hit (A/B
  delta) PRESERVING retrieval_rank, and occurrence-preserving dedup (identical text -> one display item,
  occurrences kept).

### Non-goals (out -- do NOT build)

The context compiler #40 (consume its packets at fold only); real embeddings / a vector index / real vector
search (the vector channel stays scaffolded but EMPTY); a MODEL-based reranker (deterministic only); the FULL
P1-4 metric set / judged relevance grades (follow-on); P1-2/P1-3 calibration beyond the frozen rank-RRF +
occurrence-dedup baseline; the retriever/catalog #36; skill cards #41; a production router; UI. No model / CUDA
/ network; do NOT touch model modules / models.json.

### Skill contract requirements

`skill_id retrieval.eval`, `version 0.3.0`, `contract_version 0.3`, `determinism deterministic`,
`parallel_safe true`, `batch false`, `streaming false`. `confidence` = null; `model_provenance` = [];
artifact kinds `json` + `markdown`. Report schema `lifeorch.retrieval_eval_report/0.3`.

### Tests

- **Off-machine (cloud python):** `tests/test_selpol.py` (library-direct unit suite: s4 interface, purity,
  determinism, additive output, rescue+demote preserving retrieval_rank, RRF over channel ranks,
  occurrence-preserving dedup, budget) + the worker over every fixture (double-run byte-identical). pwsh in the
  cloud is absent, so the full pwsh harness runs on `-Live`.
- **`-Live` (Windows executor):** `tests/Invoke-RetrievalEvalTests.ps1` -- AST + py_compile gates (incl.
  `lib/selpol_rrf_v1.py` + `tests/test_selpol.py`), the library-direct unit suite, manifest (0.3.0) + envelope
  validation, the KNOWN 0.1/0.2 metric VALUES PRESERVED (regression), the eval-0.3 selpol packet benchmark
  (occurrence dedup, budget -> needs_expansion, packet_disposition 5/6), pinned canonical shas + double-run
  identity, the additive selection fields, hybrid not_applicable, fail-closed error envelopes, the Module 1
  wrapper; plus a real core-docs slice via the real #36 retriever-0.2. Asserts cross-env canonical-hash parity,
  0 orphaned llama-server/python, `review_queue.jsonl` before == after.

### MVP acceptance criteria

- [x] `selpol_rrf_v1` DETERMINISTIC + PURE (byte-identical selection on re-run); signature EXACTLY matches s4.
- [x] A test where the library RESCUES a required source out of raw top-K AND DEMOTES a stale/forbidden hit
      with the A/B delta reported, PRESERVING retrieval_rank (mock2 mq-b/mq-d + test_selpol).
- [x] Occurrence-preserving dedup (identical text -> one display item WITHOUT losing occurrences)
      (benchmark3 d1 + test_selpol).
- [x] The shipped 0.2 benchmark + reranker A/B stay GREEN (regression); reports byte-identical on re-run.
- [x] Per-stage metrics + packet_disposition scoring compute with KNOWN fixture values (benchmark3).
- [ ] `-Live` over a real core-docs slice via the real #36 retriever 0.2 (filled at ship).

### Documentation

`README.md` + `skill.json` (0.3.0) + `SCHEMA_NOTES.md` (D-0077: every interpretation) + `examples/` -- updated.

### Registry / state updates

Worker holds `docs:[]`: the ORCHESTRATOR mirrors + folds all core-docs from this worker's report. This worker
edits NO core-doc.

### STOP conditions

- Acceptance met -> stop; do not build #40, an embedder, a model reranker, or `artifact.search`.
- docs:[] -> never edit a core-doc; report and let the orchestrator fold.
