# Module 37 -- retrieval.eval (Retrieval Evaluation Harness + Selection Policy + Namespace Predicate) -- contract v0.5 / eval-0.5

**i33 (D-0096) -- NAMESPACE-CLOSURE + SUPERSESSION-HARDENING, `selpol_rrf_v1` 1.1.0 -> 1.2.0 (ADDITIVE) + eval 0.4 -> 0.5.**
Folds `MEMORY_CONTRACT` A5 + the `CONTEXT_PACKET_CONTRACT` i33 amendment after the frontier Tier-0 red-team
(`159e9cb5`) found the i32 amendments were an ENVELOPE-level first layer only. **(U1')** the ONE canonical
namespace predicate + rejection policy now live in **`lib/namespace_policy.py`** (`ns_permitted` closed-set
membership + `effective_allowed_namespaces` = intersection(request, grant) + `NamespaceRejectionPolicy`),
authored here + IMPORTED by #40 + mirrored by #36 (A5 risk-6); a cross-namespace candidate is **DROPPED** before
scoring and leaves NO identifying metadata in any output array (the ONLY caller-visible surface is
`namespace_violation_count`; detail -> a privileged security log). **(U4')** candidate-INDEPENDENT supersession --
the temporal stage consumes a per-candidate catalog `effective_current` boolean, so a superseded record is
excluded under `current_only` EVEN when its successor is absent from the pool; a branch (two live successors) ->
`supersession_conflicts`/`conflicted`. **(U5')** `query_class` (semantic) and `temporal_intent` (temporal) are
INDEPENDENT -- the versioned **`lib/classifier_policy.py`** maps class->intent (with `composite`/`unclassified`
fallbacks) and an explicit user `temporal_intent`/version OUTRANKS the class default. A 1.1.0 caller supplying
none of the new signals gets BYTE-IDENTICAL selection (regression-proven). eval 0.5 extends `selection_conformance`
to MEASURE the leakage paths (closure drop+sanitize, pool-independent current_only, supersession chain+branch,
the class/intent split). Full interpretation record: `SCHEMA_NOTES.md` **s15**.

**i32 (D-0092) -- Tier-0 seam repairs, `selpol_rrf_v1` 1.0.0 -> 1.1.0 (ADDITIVE) + eval 0.3 -> 0.4 (superseded by i33).** Folds the
`CONTEXT_PACKET_CONTRACT` i32 amendment into the selection library: **(U1)** `allowed_namespaces` is a HARD
boundary -- a cross-namespace candidate is SUNK (`hard_filter_namespace`) and the soft namespace/project bonus is
retired when it is engaged; **(U4)** under the resolved `current_only` mode a non-`current` candidate is
HARD-filtered (`hard_filter_stale`; the soft `stale_penalty` survives only for the `prefer_current` mode),
supersession is rank-affecting (`superseded_demote` orders a superseded record below its live successor), and a
`contradicts` edge between two selected current items is PROPAGATED for #40's `conflicted`; **(U5)** a
`query_class` drives the temporal mode deterministically (a Tier-0 stub) and the retriever channel set stays OPEN
(an explicit `retrieval_occurrences[]` fuses a novel channel with no code change). A 1.0.0 caller supplying none
of these signals gets BYTE-IDENTICAL selection (regression-proven). eval 0.4 adds a `selection_conformance` block
measuring namespace isolation, current_only correctness, supersession ordering, and reason-code coverage. Full
interpretation record: `SCHEMA_NOTES.md` s14.

Two jobs, ONE module:

1. **Owns the ONE versioned deterministic selection-policy library `selpol_rrf_v1`** (`lib/selpol_rrf_v1.py`;
   `core-docs/CONTEXT_PACKET_CONTRACT.md` **s4** / P1-1, D-0087) -- consumed by the context compiler #40 AND by
   this harness's own reranker A/B, so there is exactly **one selection owner** (removing the two-reranker
   problem).
2. Makes retrieval + packet quality **measurable** against the FROZEN `core-docs/MEMORY_CONTRACT.md` **s6
   evaluation gates** (D-0083; eval-0.2/0.3, i29/i30). No retrieval system -- and no Wave-3 context/skill layer
   -- is accepted without measured retrieval quality (design doc Priority 2 / section 11.1).

## The selection-policy library `selpol_rrf_v1` (s4 -- the freeze)

```
select(candidates, descriptor, policy_id="selpol_rrf_v1", params=None)
  -> { selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[],
       stages, contradicts_pairs[], temporal_mode, allowed_namespaces,        # i32 additive
       supersession_conflicts[], conflicted, temporal_intent,                 # i33 additive (U4'/U5')
       classifier_policy_id, classifier_policy_version,                       # i33 additive (U5')
       namespace_policy_id, namespace_policy_version,                         # i33 additive (U1')
       namespace_violation_count, namespace_closure_violated }               # i33 additive (U1', SANITIZED)
```

**PURE + DETERMINISTIC** (no model, no I/O, no state, no wall-clock, no randomness; byte-identical on re-run,
cross-machine). `candidates` = the MEMORY_CONTRACT s3 retriever-0.2 hit array; `descriptor` = the unified
selection descriptor `{namespace?, component?, relevant_paths?, task_type?, task_stage?, time_horizon?,
seeking_failures?, permission_context?}`. Stages, in order:

1. **hard filters** -- forbidden / privacy / deleted sink (hard demote, `selected=false`);
2. **temporal** -- stale demote under `current_only` (s5);
3. **authority** -- `epistemic_authority` weighting (a TRUST signal, never execution authority);
4. **rank fusion** -- versioned **RRF over CHANNEL RANKS** (`retrieval_occurrences[]`), NOT cross-query raw
   scores (P1-2); a candidate seen via >1 channel (or a dedup cluster) fuses its ranks by RRF;
5. **diversity** -- greedy source-diversity + occurrence-preserving **display dedup**: identical text collapses
   to ONE display item carrying `occurrences[]` + `evidence_cluster_id`, so provenance is **never erased** (P1-3);
6. **budget** -- a max-selected / max-tokens hook; overflow -> `omission_manifest`.

**Output is ADDITIVE -- it never re-sorts the retrieval array in place.** Every ranked candidate is a COPY of
its input hit that PRESERVES `retrieval_rank` / `lexical_rank` / `vector_rank` / `fused_rank` and ADDS
`selection_rank`, `selection_score`, `selection_policy_id`, `selected`, `reason_codes[]`,
`retrieval_occurrences[]`, `rrf_score` (and, in a cluster, `occurrences[]` + `evidence_cluster_id`).

The shipped standalone `rerank()` is now a **thin wrapper** over this library (`selpol.rerank_compat`), so the
measured A/B measures the library and there is a single implementation. `dedup_display=False` + no budget
reproduce the shipped reranked order + diagnostics **byte-identically** -- the shipped benchmark + A/B stay
regression-green. #40 loads the same library by a resolved path and builds its packet to the s4 interface; the
orchestrator asserts #40-with-its-reference-impl == #40-with-this-canonical-`selpol_rrf_v1` at the D-0077 fold.

## Evaluation harness (s6 / 11.1)

Runs a **benchmark** -- queries carrying rich labels (required version/span, must_include_all /
must_include_any evidence groups, acceptable-equivalent spans, explicitly-stale versions, forbidden sources,
hard privacy exclusions, distractors, no-answer-expected, temporal intent) -- against **any retriever
satisfying the s3 retriever-0.2 interface**, and emits deterministic reports. A **file-level hit is NOT
credit**: a wrong chunk from the right file does not score. Two retrievers ship: a deterministic **lexical
baseline** (BM25-lite over a fully-known fixture corpus) -> a KNOWN floor; an **external_command** adapter ->
the seam the orchestrator points at the real `artifact.search` #36 retriever-0.2 at fold.

### Metrics

Kept from 0.1: **recall@K, MRR, stale-source rate, provenance completeness, forbidden-hit rate**. Added in
0.2: **precision@K, nDCG@K, evidence-group coverage, stale-hit rate, privacy-hit rate, duplicate/near-dup
burden, source diversity@K, provenance VALIDITY** (not presence), **snippet-span correctness, relevant-token
ratio, no-answer false-positive rate, hybrid uplift/regression**. New in **0.3**: **per-stage metrics** (raw
retrieval / post-filter / packet -- the packet stage measures the deduped+budgeted selection), **packet_disposition
correctness** (`answerable | needs_expansion | abstain | conflicted | provenance_failed` -- read from a supplied
#40 packet or computed deterministically per CONTEXT_PACKET_CONTRACT s2), and **hybrid metrics marked
`not_applicable`** (NOT zero) while the vector channel is EMPTY (P1-4). Full graded-relevance / judged-result
P1-4 is a named follow-on (label plumbing is in place). Query latency/resource go to the volatile
`worker-summary.json`, never the canonical report.

### Provenance validation (not presence)

For every scored hit: the `content_hash` identifies the expected source version; the source exists or is
tombstoned; the span is in bounds; **reading the span reproduces the cited text**; the snippet derives from
it; the parser+chunker fingerprint is known; the current/stale status is correct.

## Run it

```powershell
# built-in lexical baseline over the shipped 0.1 fixture corpus (regression-green)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json

# the eval-0.2 lexical benchmark (evidence groups, temporal intent, privacy, no-answer, duplicates)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark2.json

# the eval-0.3 selpol packet benchmark (occurrence dedup, budget -> needs_expansion, packet_disposition)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark3.json

# an external retriever-0.2 (the fold seam; canned retriever-0.2 hits -> provenance + reranker A/B)
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\mock2-benchmark.json
```

Outputs land in `runtime/artifacts/<invocation_id>/`: `report.json` (machine, schema
`lifeorch.retrieval_eval_report/0.3`), `report.md` (human), `worker-summary.json`, and the
`lifeorch.skill.result/0.1` envelope on stdout. The two reports are **canonical and byte-identical on a
re-run across machines** (integer-only: scores in millionths, ratios in ppm; no timestamps / invocation ids /
absolute paths / wall-clock). `content_hash` is EOL-normalized so a CRLF vs LF checkout hashes identically.

## Known baselines (fixtures)

- **benchmark.json** (shipped 0.1, 7 queries): recall@K = 857143 ppm (6/7) · MRR = 857143 · stale-source rate
  = 142857 · forbidden-hit rate = 142857 · provenance completeness = 1000000 · provenance **validity** =
  964286 · precision@1 = 857143 · nDCG@5 = 857143 · source-diversity@5 = 607143. **(values unchanged from 0.2.)**
- **benchmark2.json** (eval-0.2, 7 queries): precision@1 = 571429 · nDCG@5 = 849557 · evidence-group coverage
  = 500000 · forbidden = privacy = 142857 · no-answer FP rate = 500000 · duplicate burden = 61905 · provenance
  validity = 979592. **(values unchanged from 0.2; the packet stage collapses the near-duplicates -> packet
  duplicate burden 0.)**
- **benchmark3.json** (eval-0.3 selpol packet stage, 6 queries): packet_disposition accuracy = 833333 ppm
  (5/6 -- a supplied packet that WRONGLY claims `answerable` for an absent required source is caught);
  occurrence-preserving dedup collapses two byte-identical sources to one display item carrying both
  occurrences; a `max_selected=1` budget drops the required chunk -> `needs_expansion`.
- **mock2-benchmark.json** (external retriever-0.2): a required-absent miss, a forbidden hit, a bad-span
  provenance-INVALID hit, and the reranker A/B (rescue a required source to rank 1 + demote a forbidden hit;
  recall@1 / nDCG@1 uplift +500000 ppm; the promoted hit PRESERVES its `retrieval_rank`).

## Shape

- `lib/selpol_rrf_v1.py` -- the ONE selection-policy library (s4; self-contained stdlib; #40 loads it by path).
- `Invoke-RetrievalEval.ps1` -- thin contract wrapper (pwsh): validates inputs, resolves python, invokes the
  worker, emits the envelope. Exits 0; logical failures are `status:"error"` envelopes.
- `retrieval_eval.py` -- the deterministic core (Python stdlib only): the retriever-0.2 interface + hit
  normalization + lexical baseline + external adapter + eval labels/metrics + provenance validation + the
  `rerank()` wrapper over `selpol_rrf_v1` + the packet stage + per-stage/packet_disposition scoring + hybrid
  attribution + canonical report writers.
- `tests/Invoke-RetrievalEvalTests.ps1` -- the dual-mode real-skill gate (cloud + `-Live`); it runs the
  library-direct unit suite `tests/test_selpol.py` too.
- `tests/fixtures/` -- `corpus/` + `benchmark.json` (0.1), `corpus2/` + `benchmark2.json` (eval-0.2) +
  `benchmark3.json` (eval-0.3 selpol), the mock external retriever + `mock2-plan.json` (canned retriever-0.2 hits).
- `SCHEMA_NOTES.md` -- the D-0077 record of every schema/interface interpretation. Read it before wiring a
  new retriever, consuming the reranker seam, or importing `selpol_rrf_v1`.

## Boundaries (non-goals)

No real embeddings / vector index / vector search (the vector channel is scaffolded but EMPTY -- the retrieval
wave); no MODEL-based reranker (deterministic only); no context compiler #40 (consumes this library; not built
here), retriever/catalog #36, or skill cards #41; no production router; no UI; full graded-relevance P1-4 /
P1-2/P1-3 calibration beyond the frozen rank-RRF + occurrence-dedup baseline is a named follow-on. Does NOT
touch model modules / models.json. CPU-only, no model, no CUDA, no network -> `parallel_safe: true`.

## Requirements

`pwsh >= 7.4` and any `python >= 3.8` (the worker + `selpol_rrf_v1` use only the standard library).

## i34 Tier-1 hierarchy eval (0.6.0, D-0098)

`-Op hierarchy-eval` (or `python hierarchy_eval.py --request`) runs the Tier-1 hierarchy evaluation -- a
SEPARATE self-contained worker (`hierarchy_eval.py`); the benchmark path + `retrieval_eval.py` are unchanged.
It MEASURES the bounded-fanout hierarchy #36/#40 build, defending the frontier red-team's concern (pack
b4c90545) that bounded deterministic navigation is not automatically recall-preserving: navigation-cost
(sub-linear nodes-examined vs leaf count, p50/p95), DUAL recall (hierarchy-path reached vs end-to-end
packet-evidence retained -- the safe-pruning + fallback contract preserves packet recall where a naive beam
silently misses), adversarial scale/mutation fixtures (pinned), the Tier-1 gate set, and the ~200MB real-corpus
rehearsal SCAFFOLDED + FLAGGED as the OPEN pre-freeze gate. Report: `hierarchy_report.json`
(`lifeorch.hierarchy_eval_report/0.1`, integer-only, byte-identical on re-run) + `hierarchy_report.md`. The
`external_command` adapter is the D-0077 fold seam for the real #36/#40. CPU-only, deterministic, no model.
