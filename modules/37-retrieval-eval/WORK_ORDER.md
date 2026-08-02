# Work Order: Retrieval Evaluation Harness (`retrieval.eval`) -- 0.1.0 -> 0.2.0 (eval-0.2)

**Contract version targeted:** 0.2 (eval-0.2 gates) · **Author:** FANOUT_AGENT_002 (RETRIEVAL-QUALITY-i29) /
2026-08-02 · **Roadmap:** Wave 3 CPU lane (plan fo-29-87dbfa0b; D-0083 MEMORY_CONTRACT s6; directive 8.3/11.1;
Priority 2). Predecessor: 0.1.0 (RETRIEVAL-EVAL-i25, plan fo-25-3b718a13).

### Problem being solved

Wave 3 builds the context compiler (#40) and skill retrieval. Before those layers are accepted, retrieval +
packet quality must be MEASURABLE against the FROZEN MEMORY_CONTRACT s6 evaluation gates, and there must be a
deterministic reranker seam #40 (and a later retrieval wave) can consume. This revision adopts eval-0.2 and
adds that reranker.

### Immediate practical use

At the Wave-3 fold (D-0077): point the `external_command` retriever at the real `artifact.search` #36
retriever-0.2, run the benchmark, and read measured retrieval quality (raw + reranked) with source-resolved
provenance VALIDITY. The orchestrator also scores REAL #40 `context_packet/0.1` packets with this 0.2 harness
at fold (D-0077) -- the packet's selected hits are retriever-0.2 hits, so the same metrics + validation apply.

### Explicit scope (in) -- touch ONLY `modules/37-retrieval-eval`

- Benchmark schema `lifeorch.retrieval_benchmark/0.2`: evidence groups (must_include_all / must_include_any),
  required version/span, acceptable-equivalent spans, explicitly-stale versions, forbidden sources, hard
  privacy exclusions, distractors, no_answer_expected, temporal intent, label rationale/status/reviewer,
  corpus snapshot. Chunk/span-level credit (a file-level hit is not sufficient). The 0.1 schema is still
  accepted (compat/migration).
- Temporal intent per query: current_only | historical_as_of | version_specific | any_valid_version.
- Metrics added over 0.1: precision@K, nDCG@K, evidence-group coverage, forbidden/privacy/stale-hit rate,
  duplicate/near-dup burden, source diversity, provenance VALIDITY, snippet-span correctness, relevant-token
  ratio, no-answer FP rate, hybrid uplift/regression. (recall@K / MRR / stale-source / provenance-presence /
  forbidden-hit rate kept, values regression-green.)
- Negatives / abstention fixtures; hybrid attribution (lexical / vector / hybrid) with the vector channel
  EMPTY, reported cleanly; provenance VALIDATION (not presence).
- A DETERMINISTIC reranker (retriever-0.2 hit array + descriptor -> the same shape reordered) MEASURED by the
  harness (uplift/regression vs the raw order + rescue/demote). NO model.
- Reports (machine `report.json` `lifeorch.retrieval_eval_report/0.2` + human `report.md`), canonical.

### Non-goals (out -- do NOT build)

- Real embeddings / a vector index / real vector search (the vector channel is scaffolded but EMPTY -- the
  retrieval wave); a MODEL-based reranker; the context compiler #40; the retriever/catalog #36; skill cards
  #41; a production router (Priority 7); UI. No model / CUDA / network; do NOT touch model modules / models.json.

### Dependencies

- Modules: #0 executor + dev.ship (ship path), #1 skill contract (manifest/envelope validators + generic
  wrapper), #29 res.lease (git lease at ship). Consumes the #36 retriever-0.2 hit shape (MEMORY_CONTRACT s3).
  Tools: `pwsh>=7.4`, `python>=3.8` (stdlib only).

### Skill contract requirements

`skill_id retrieval.eval`, `version 0.2.0`, `contract_version 0.2`, `determinism deterministic`,
`parallel_safe true`, `batch false`, `streaming false`. `confidence` = null (deterministic);
`model_provenance` = []; artifact kinds `json` + `markdown`.

### Tests

- **Off-machine (cloud pwsh/python):** `tests/Invoke-RetrievalEvalTests.ps1` -- AST + py_compile gates,
  manifest + envelope validation (0.2.0), the KNOWN 0.1 baseline numbers PRESERVED, the eval-0.2 metrics with
  KNOWN fixture values, pinned canonical sha + double-run identity, the three ACCEPTANCE failing cases
  (required ABSENT; forbidden RETURNED; a returned span that does NOT reproduce the cited text), the reranker
  A/B (rescue + demote), hybrid attribution with the vector channel EMPTY, fail-closed error envelopes, the
  Module 1 wrapper. Prints `CANONICAL-HASH` lines for cross-env parity.
- **`-Live` (Windows executor):** the same harness + a real core-docs slice via the real #36 retriever-0.2;
  assert cross-env canonical-hash parity, 0 orphaned llama-server/python, `review_queue.jsonl` before == after.

### MVP acceptance criteria

- [x] eval-0.2 runs DETERMINISTICALLY on a fixture corpus with the richer labels + temporal intent + negatives.
- [x] Each new metric computes with a KNOWN fixture value (precision@K, nDCG@K, evidence-group coverage,
      forbidden/stale-hit rate, provenance validity, no-answer FP).
- [x] A FAILING test when a required source is ABSENT (mock2 mq-a; baseline q7; mock mq2).
- [x] A FAILING test when a FORBIDDEN source is returned (mock2 mq-b/mq-d; benchmark2 b3).
- [x] A FAILING test when a returned span does NOT reproduce the cited text (mock2 mq-c -> provenance INVALID).
- [x] Hybrid attribution runs with the vector channel EMPTY and reports it.
- [x] The deterministic reranker measurably RESCUES a required source out of the raw top-K OR DEMOTES a
      stale/forbidden hit, with the A/B delta reported (mock2 mq-b/mq-d; +500000 ppm recall@1 / nDCG@1).
- [x] The shipped 0.1 benchmark + metrics stay GREEN (regression); reports byte-identical on re-run.
- [ ] `-Live` over a real core-docs slice via the real #36 retriever 0.2 (filled at ship).

### Documentation

`README.md` + `skill.json` (0.2.0) + `SCHEMA_NOTES.md` (D-0077: every interpretation) + `examples/` -- updated.

### Registry / state updates

Worker holds `docs:[]`: the ORCHESTRATOR mirrors + folds all core-docs from this worker's report. This worker
edits NO core-doc.

### STOP conditions

- Acceptance met -> stop; do not build a router, an embedder, a model reranker, #40, or `artifact.search`.
- docs:[] -> never edit a core-doc; report and let the orchestrator fold.
