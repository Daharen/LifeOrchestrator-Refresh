# i36 Tier-1 ACCEPTANCE -- the full wired-descend rehearsal gate (the `tier1_accepted` flip evidence)

**Date:** 2026-08-05. **Wave:** i36 (plan `fo-36-1a676e4b`, D-0102). **Owner:** the fan-out orchestrator (the
project-level flip is the orchestrator's, per "never a silent pass"). **Verdict: PROJECT `tier1_accepted` = TRUE.**

This digest records the acceptance gate the orchestrator ran at the i36 fold to flip project-level Tier-1
acceptance -- the gate the memory architecture (`MEMORY_ARCHITECTURE.md` s10) and i35 (D-0100) explicitly deferred
to "the FULL run against #40's WIRED descend path." The runnable evidence is committed alongside as
`2026-08-05-i36-tier1-acceptance-rehearsal-report.json` (the harness's canonical `lifeorch.rehearsal_eval_report/0.1`).

## What was run (a genuinely independent gate, not the sample)

- **Harness:** #37 retrieval.eval **eval 0.8.0** (`0e466bc`, i36 Lane A) -- `rehearsal_eval.py` with `wired_descend:true`,
  driving **#40 context.compile 0.7.0** (`aa2f0fb`, FROZEN this wave) through its PUBLIC `-Retriever artifact_search`
  shortlist-and-descend port READ-ONLY via the external_command adapter (the default adapter resolves #40's shipped
  python core; no override needed).
- **Corpus:** a DISTINCT, real, permissively-licensed FOREIGN corpus -- **6 packages** (click 8.1.7 / flask 3.0.3 /
  jinja2 3.1.4 / requests 2.32.3 / rich 13.7.1 / werkzeug 3.0.3), sdists fetched + **sha256-verified fail-closed**
  against `FULL_CORPUS_RECIPE.md` s1, extracted, LF-normalized, **deduped to 637 distinct-content files** across
  **6 namespaces** (corpus manifest_digest `dc687a43...`). NOT the project's own repo, NOT synthetic (the
  "synthetic necessary but not sufficient" rule), NOT the click-only i35 sample.
- **Benchmark:** auto-VERIFIED labels (`build_benchmark.py`) -- 8 queries: 4 unique-token + 2 cross-cutting
  DESCEND-class (`global_synthesis`) queries whose anchors were computed to localize to exactly one corpus file
  (packet + guaranteed recall correct by construction; zero foreign leak), plus a controlled supersession pair
  (`HISTFACT` tmo_v1 superseded by current tmo_v2, namespace `clicklog`) for current-vs-historical.
- **Scale sweep:** `scales=[1,10,100]` -- a **100x leaf span** (248 -> 2,480 -> 24,800 leaves; >=2 orders of
  magnitude, `leaf_span_ok`), the harness's auto-localized scale queries.

## Result: 11 / 11 s10 criteria PASS -> `tier1_accepted = True` (0 fold reconciliation)

| s10 criterion | result |
|---|---|
| wired_descend_path_ran (a/b) | PASS -- 6 labeled descend-class + 17 scale descend queries; #40's real port constructed + emits nav / retrieval_completeness / stage_trace |
| bounded_context_cost (a) | PASS -- packet within budget at every scale (used 1807 / 957 / 1978 <= 2000 tokens; excerpts bounded) |
| cross_namespace_contamination (b) | PASS -- 0 contamination hits across all labeled queries + navigation refs |
| current_vs_historical (c) | PASS -- 2/2 temporal honored (current_only returns tmo_v2, excludes tmo_v1; historical retrieves tmo_v1) |
| provenance_reconstruction (d) | PASS -- 29/29 source-chunk excerpts reproduced + valid (1,000,000 ppm) |
| navigation_sublinear_from_plan (e) | PASS -- from #40's OWN plan trace: nav nodes 36 -> 69 -> 100 over a 100x leaf span; nav_over_leaves 145161 -> 27822 -> 4032 ppm (strictly decreasing, log-shaped) |
| packet_evidence_recall (dual) | PASS -- 1,000,000 ppm labeled + 1,000,000 ppm scale |
| guaranteed_path_recall (dual) | PASS -- 1,000,000 ppm labeled + 1,000,000 ppm scale (the exhaustive baseline) |
| packet_disposition_correct (P0-3) | PASS -- 8/8 dispositions correct (all `answerable`) |
| stale_window_recall_preserved (seam) | PASS -- stale encountered + recall preserved; pruned-branch count not increased under staleness |
| no_fold_reconciliation (seam) | PASS -- #40 0.7.0's WIRED CLI fully drivable; 0 absent required fields |

Regression at fold: the i34 `smoke-i34.py` hierarchy fold smoke **38/38** (frozen #40 0.7.0 unchanged); 0 unmanaged
orphans; the #36 `get-record` op confirmed running at HEAD (its correctness gated by the worker's 38/38 + 227/227).

## The honest caveat (a named follow-on, NOT a Tier-1 blocker)

The WIRED descend **fast-beam** is **bounded-beam LOSSY** -- measured `hierarchy_path_recall = 0 ppm`: on these
queries the shortlist/descend fast-path reaches NONE of the required leaves on its OWN. End-to-end recall is
100% ONLY because the **exhaustive #36-flat fallback** (an indexed FTS top-k, not a linear scan) preserves
packet + guaranteed recall -- exactly the SAFE-PRUNING design (b4c90545 red-team): a navigation value may
prioritize but never negatively exclude without a sound no-false-negative predicate; where none applies, fall
back. So Tier-1's promise -- BOUNDED context cost + sub-linear navigation + correctness + NO recall loss -- is
met, with the recall carried by the fallback, not the fast-beam. **Follow-on (i37+): strengthen the shortlist/
descend beam ranking so the hierarchy fast-path itself contributes recall and the flat fallback fires less.**
This does not block acceptance (the s10 bounded-cost + guaranteed-recall + correctness criteria all hold), but it
is the next quality lever and is recorded so it is never silently forgotten.

## Reproduce

`FULL_CORPUS_RECIPE.md` (fetch + hash-verify + prep) + the committed builders under
`modules/30-orchestrate-fanout/runtime/` (`prep_full_corpus.py` dedup prep, `build_benchmark.py` auto-verified
labels) -> `Invoke-RetrievalEval.ps1 -Op rehearsal -InputsJson '{...,"scales":[1,10,100],"wired_descend":true}'`
over the F: corpus. The harness computes `tier1_accepted` over whatever corpus + CLI it is pointed at; the
orchestrator ran it against the FROZEN #40 0.7.0 and owns this project-level flip.
