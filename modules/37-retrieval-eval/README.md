# Module 37 -- retrieval.eval (Retrieval Evaluation Harness) -- contract v0.2 / eval-0.2

Make retrieval + packet quality **measurable** against the FROZEN `core-docs/MEMORY_CONTRACT.md` **s6
evaluation gates** (D-0083; eval-0.2, i29). No retrieval system -- and no Wave-3 context/skill layer -- is
accepted without measured retrieval quality (design doc Priority 2 / section 11.1).

## What it does

Runs a **benchmark** -- queries carrying rich labels (required version/span, must_include_all /
must_include_any evidence groups, acceptable-equivalent spans, explicitly-stale versions, forbidden sources,
hard privacy exclusions, distractors, no-answer-expected, temporal intent) -- against **any retriever
satisfying the MEMORY_CONTRACT s3 retriever-0.2 interface**, and emits deterministic machine- and
human-readable reports. A **file-level hit is NOT credit**: a wrong chunk from the right file does not score.

It ships two retrievers so it is useful in isolation now and at the fold later:

- a deterministic **lexical baseline** (BM25-lite over a fully-known fixture corpus, emitting retriever-0.2
  hits) -> a KNOWN floor;
- an **external_command** adapter -> the seam the orchestrator points at the real `artifact.search` #36
  retriever-0.2 at fold.

### Metrics (s6 / 11.1)

Kept from 0.1: **recall@K, MRR, stale-source rate, provenance completeness, forbidden-hit rate**. Added in
0.2: **precision@K, nDCG@K, evidence-group coverage, stale-hit rate, privacy-hit rate, duplicate/near-dup
burden, source diversity@K, provenance VALIDITY** (not presence), **snippet-span correctness, relevant-token
ratio, no-answer false-positive rate, hybrid uplift/regression**. Query latency/resource are measured into the
volatile `worker-summary.json`, never the canonical report.

### Provenance validation (not presence)

For every scored hit: the `content_hash` identifies the expected source version; the source exists or is
tombstoned; the span is in bounds; **reading the span reproduces the cited text**; the snippet derives from
it; the parser+chunker fingerprint is known; the current/stale status is correct.

### Deterministic reranker (directive 8.3 / skill-activation Stage 4; NO model)

`rerank()` takes the retriever-0.2 hit array + a task/query descriptor and returns the **same hit-array shape
reordered** by deterministic features (direct relevance, authority, freshness/currentness, project/component
match, task-stage match, failure likelihood, procedural applicability) + **diversity** (dedup + source
diversity). The harness MEASURES it: rerank uplift/regression vs the raw order + per-query rescue/demote. It
is the drop-in seam the context compiler #40 and a later retrieval wave consume.

### Hybrid attribution (vector channel empty today)

From the retriever-0.2 per-channel diagnostics (lexical-only / vector-only / hybrid): unique-to-channel,
required rescued by vectors, lexical exact-match harmed by fusion, stale/forbidden introduced by a channel,
fusion contribution. **The vector channel runs EMPTY this wave** (no vectors) and is reported cleanly.

## Run it

```powershell
# built-in lexical baseline over the shipped 0.1 fixture corpus (regression-green)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json

# the eval-0.2 lexical benchmark (evidence groups, temporal intent, privacy, no-answer, duplicates)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark2.json

# an external retriever-0.2 (the fold seam; canned retriever-0.2 hits -> provenance + reranker A/B)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\mock2-benchmark.json
```

Outputs land in `runtime/artifacts/<invocation_id>/`: `report.json` (machine, schema
`lifeorch.retrieval_eval_report/0.2`), `report.md` (human), `worker-summary.json`, and the
`lifeorch.skill.result/0.1` envelope on stdout. The two reports are **canonical and byte-identical on a
re-run across machines** (integer-only: scores in millionths, ratios in ppm; no timestamps / invocation ids /
absolute paths / wall-clock). `content_hash` is EOL-normalized so a CRLF vs LF checkout hashes identically.

## Known baselines (fixtures)

- **benchmark.json** (shipped 0.1, 7 queries): recall@K = 857143 ppm (6/7) · MRR = 857143 · stale-source rate
  = 142857 · forbidden-hit rate = 142857 · provenance completeness = 1000000 · provenance **validity** =
  964286 (validation flags the archived stale copy's `current` status) · precision@1 = 857143 · nDCG@5 =
  857143 · source-diversity@5 = 607143.
- **benchmark2.json** (eval-0.2, 7 queries): precision@1 = 571429 · nDCG@5 = 849557 · evidence-group coverage
  = 500000 (an `any` group hit, an `all` group missed) · forbidden = privacy = 142857 · no-answer FP rate =
  500000 (one clean abstain, one false positive) · duplicate burden = 61905 · provenance validity = 979592.
- **mock2-benchmark.json** (external retriever-0.2): a required-absent miss, a forbidden hit, a bad-span
  provenance-INVALID hit, and the reranker A/B (rescue a required source to rank 1 + demote a forbidden hit;
  recall@1 / nDCG@1 uplift +500000 ppm).

## Shape

- `Invoke-RetrievalEval.ps1` -- thin contract wrapper (pwsh): validates inputs, resolves python, invokes the
  worker, emits the envelope. Exits 0; logical failures are `status:"error"` envelopes.
- `retrieval_eval.py` -- the deterministic core (Python stdlib only): the retriever-0.2 interface + hit
  normalization + lexical baseline + external adapter + eval-0.2 labels/metrics + provenance validation +
  the deterministic reranker + hybrid attribution + canonical report writers.
- `tests/Invoke-RetrievalEvalTests.ps1` -- the dual-mode real-skill gate (cloud + `-Live`).
- `tests/fixtures/` -- `corpus/` + `benchmark.json` (0.1), `corpus2/` + `benchmark2.json` (eval-0.2), the
  mock external retriever + `mock2-plan.json` (canned retriever-0.2 hits).
- `SCHEMA_NOTES.md` -- the D-0077 record of every schema/interface interpretation. Read it before wiring a
  new retriever or consuming the reranker seam.

## Boundaries (non-goals)

No real embeddings / vector index / vector search (the vector channel is scaffolded but EMPTY -- the
retrieval wave); no MODEL-based reranker (deterministic only); no context compiler #40, retriever/catalog #36,
or skill cards #41; no production router; no UI. This module only MEASURES + reranks deterministically; it
does not build a retriever (beyond its own baseline). Does NOT touch model modules / models.json. CPU-only,
no model, no CUDA, no network -> `parallel_safe: true`.

## Requirements

`pwsh >= 7.4` and any `python >= 3.8` (the worker uses only the standard library).
