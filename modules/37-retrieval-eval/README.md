# Module 37 -- retrieval.eval (Retrieval Evaluation Harness)

Make retrieval quality **measurable before any vector integration** (Wave 1 of the Collective Agent
memory substrate, D-0080; governing doc
`core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`, Priority 2 / section
11.1). No retrieval system is accepted without measured retrieval quality.

## What it does

Runs a **benchmark** -- a set of queries, each carrying the REQUIRED-SOURCE label(s) a correct retrieval
must surface (plus optional stale/superseded and forbidden sources) -- against **any retriever satisfying
the D-0077 retriever interface**, and emits deterministic machine- and human-readable reports with
recall@K, MRR, stale-source rate, and provenance completeness.

It ships two retrievers so it is useful in isolation now and at the fold later:

- a deterministic **lexical baseline** (BM25-lite over a fully-known fixture corpus) -> a KNOWN baseline;
- an **external_command** adapter -> the seam the orchestrator points at the real `artifact.search` at fold.

A required source is matched only when its `source_path` and (when labelled) `content_hash` match, so a
right path with a **stale/superseded** hash is a **miss** (and is reported) -- retrieval quality is
version-aware, per section 4.2 of the design doc.

## Run it

```powershell
# built-in lexical baseline over the fixture corpus
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json

# generic caller form
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputsJson '{"benchmark":"tests/fixtures/benchmark.json"}'

# point at an external retriever (the fold seam; mock fixture shown)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\mock-benchmark.json
```

Outputs land in `runtime/artifacts/<invocation_id>/`: `report.json` (machine, schema
`lifeorch.retrieval_eval_report/0.1`), `report.md` (human), `worker-summary.json`, and the
`lifeorch.skill.result/0.1` envelope on stdout. The two reports are **canonical and byte-identical on a
re-run across machines** (integer-only: scores in millionths, ratios in ppm; no timestamps / invocation
ids / absolute paths). `content_hash` is EOL-normalized so a CRLF vs LF checkout hashes identically.

## Known baseline (fixture corpus, 7 queries)

recall@K = 857143 ppm (6/7; one organic lexical miss) · MRR = 857143 · stale-source rate = 142857 (1/7; an
archived superseded copy) · forbidden-hit rate = 142857 (1/7) · provenance completeness = 1000000.

## Shape

- `Invoke-RetrievalEval.ps1` -- thin contract wrapper (pwsh): validates inputs, resolves python, invokes
  the worker, emits the envelope. Exits 0; logical failures are `status:"error"` envelopes.
- `retrieval_eval.py` -- the deterministic core (Python stdlib only): retriever interface + lexical
  baseline + external adapter + metrics + canonical report writers.
- `tests/Invoke-RetrievalEvalTests.ps1` -- the dual-mode real-skill gate (cloud + `-Live`).
- `tests/fixtures/` -- the corpus, the benchmark, and the mock external retriever.
- `SCHEMA_NOTES.md` -- the D-0077 record of the benchmark schema + retriever interface. Read it before
  wiring a new retriever.

## Boundaries (non-goals)

No production router, no embedding provider, no `artifact.search` itself, no UI, no summaries. This module
only MEASURES; it consumes a retriever, it does not build one (beyond its own baseline). CPU-only, no model,
no CUDA, no network -> `parallel_safe: true`.

## Requirements

`pwsh >= 7.4` and any `python >= 3.8` (the worker uses only the standard library -- no Pillow/numpy/etc.).
