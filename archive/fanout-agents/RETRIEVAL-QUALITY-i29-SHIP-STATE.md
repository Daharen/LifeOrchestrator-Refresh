# RETRIEVAL-QUALITY-i29 -- SHIP STATE (worker report; plan fo-29-87dbfa0b)

**Worker:** FANOUT_AGENT_002 (RETRIEVAL-QUALITY-i29) · Wave 3 CODING/CPU lane · **State: DONE**
**Module:** `modules/37-retrieval-eval` (skill `retrieval.eval`) **0.1.0 -> 0.2.0** (contract_version 0.2)
**Commit:** `dc293efd331309583b11db9b5feb70976dfacbde` (native-git verified, D-0072), 20 files, module-only.
**docs:[]** -- no core-doc edited; the orchestrator mirrors + folds from the on-disk report
(`plans/fo-29-87dbfa0b/reports/RETRIEVAL-QUALITY-i29.*.json`). Authoritative interpretations:
`modules/37-retrieval-eval/SCHEMA_NOTES.md`.

## Mission (met)

Adopt MEMORY_CONTRACT **s6 eval-0.2** on `retrieval.eval` AND add a **deterministic reranker** (directive
8.3 / skill-activation Stage 4) that the 0.2 harness MEASURES. Makes retrieval + packet quality measurable so
the Wave-3 context/skill layers can be accepted, and provides the reranker seam the context compiler #40 (this
wave) and a later retrieval wave consume. CONSUMER of the retriever-0.2 hit (s3); no model.

## What shipped (acceptance -> evidence)

- **eval-0.2 label schema** (s6): must_include_all / must_include_any evidence groups, required version/span,
  acceptable-equivalent spans, explicitly-stale versions, forbidden_sources, hard privacy exclusions,
  distractors, no_answer_expected, label rationale/status/reviewer, corpus snapshot. **Chunk-level credit** --
  a file-level hit is NOT sufficient (fixture `b1`: the file appears at rank 1 but the required *chunk* is
  only credited at K=5).
- **Temporal intent** per query: current_only | historical_as_of | version_specific | any_valid_version ("a
  stale required source is always a miss" holds ONLY for current_only; fixture `b7` version-specific).
- **Metrics added** over 0.1 (recall@K/MRR/stale/prov-presence/forbidden kept, values regression-green):
  precision@K, nDCG@K, evidence-group coverage, forbidden/privacy/stale-hit rate, duplicate/near-dup burden,
  source diversity@K, provenance **VALIDITY**, snippet-span correctness, relevant-token ratio, no-answer FP
  rate, hybrid uplift/regression. Each has a KNOWN fixture value (pinned in the tests). Query latency/resource
  -> the volatile `worker-summary.json`, never the canonical report.
- **Negatives/abstention** fixtures; **hybrid attribution** from the s3 per-channel diagnostics with the
  **vector channel EMPTY**, reported cleanly (`vector_channel_status: empty`).
- **Provenance VALIDATION** (not presence): content_hash identifies the source version; source exists or is
  tombstoned; span in bounds; **reading the span reproduces the cited text**; snippet derives from it;
  fingerprint known; status correct. Failing case `mq-c-badspan`: recall@1=1 but provenance INVALID
  (`span_reproduces_cited_text` fails).
- **Deterministic reranker** (retriever-0.2 hit array + descriptor -> SAME shape reordered by relevance /
  authority / freshness / project / component / task-stage / failure / procedural + diversity; NO model),
  **MEASURED** vs the raw order. Fixtures `mq-b`/`mq-d`: rescues a current required source to rank 1 and
  demotes a forbidden/stale hit -> recall@1 / nDCG@1 uplift **+500000 ppm**.
- Reports (`report.json` schema `lifeorch.retrieval_eval_report/0.2` + `report.md`) canonical + byte-identical
  on re-run. skill.json 0.2.0; entrypoint skill_version 0.2.0.

## Gates (fail-closed)

- **Off-machine** (cloud pwsh 7.4.6 + CPython 3.11): **119/119**; reports byte-identical on double-run.
- **-Live** on the executor (Windows, CPython 3.12): **119/119**; cross-env **CANONICAL-HASH byte-identical**
  to the cloud pins (nDCG `log2` determinism holds across CPython 3.11/3.12); **0 UNMANAGED** llama orphans;
  `review_queue.jsonl` **before == after** (`e8288032...`).
- **-Live over a real core-docs slice via the REAL #36 retriever-0.2** (external_command seam through an
  adapter): recall@1 / MRR / nDCG@3 = **1.0** (the seam consumes real retriever-0.2 hits + computes quality);
  provenance **validity = 0** -- the intended D-0077 signal: it flags #36's `content_hash` bare-hex (no
  `sha256:` prefix), raw-CRLF span basis, and missing `chunker_fingerprint` on the hit. **These are the fold
  reconciliation items** (the orchestrator wires #36 behind the harness + scores #40 packets at fold, D-0077).

## Pinned canonical hashes (cross-env, cloud == executor)

- `benchmark.json` (0.1 regression): report.json `598dc1be...`, report.md `6264cb1b...`,
  input_digest `sha256:aff6a477...`. 0.1 numbers preserved (recall@1 857143, MRR 857143, stale 142857,
  forbidden 142857, prov-completeness 1000000); provenance **validity 964286** (validation flags the archived
  stale copy's `current` status).
- `benchmark2.json` (eval-0.2): report.json `06878847...`, input_digest `sha256:58569e41...`.
- `mock-benchmark.json` (0.1): report.json `b5d55da9...`. `mock2-benchmark.json`: report.json `70dc60e5...`,
  input_digest `sha256:7d16bbaa...`.

## Residuals / follow-ons (for the orchestrator fold + later waves)

- **D-0077 fold**: wire the real #36 `artifact.search` behind the `external_command` retriever + score real
  #40 `context_packet/0.1` packets with this 0.2 harness. Reconcile #36's hit `content_hash` prefix (bare hex
  vs `sha256:`), the byte-span basis (raw-CRLF vs EOL-normalized), and surface `chunker_fingerprint` on the
  search hit so provenance VALIDITY reads true (currently flagged as the intended signal).
- Vector channel is scaffolded but EMPTY (the retrieval wave); the harness runs + reports it cleanly.
- Failure-memory trigger-recall + context-packet-size metrics once those layers exist.
