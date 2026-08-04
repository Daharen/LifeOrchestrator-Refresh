# SELECTION-POLICY-SETTLE-i31 -- SHIP STATE (FANOUT_AGENT_002, plan fo-31-eca37c08)

**Status: SHIPPED + COMMITTED + FOLDED. #40 `b541df6`; fold docs = the D-0091 commit.** Author: FANOUT_AGENT_002
(CONTEXT-COMPILER-SELPOL-i31). Lane: CPU (single-worker wave; GPU/coding/frontier lanes skipped). Closed
2026-08-03. Decision: D-0089 (s4 pin) + D-0091 (wave + fold).

## Outcome

- **#40 context.compile 0.2.0 -> 0.3.0 (`b541df6`):** realizes P1-1 'one selection owner'. DELETED the in-module
  `selpol_reference.py` stub (290 lines); IMPORTS #37's canonical `modules/37-retrieval-eval/lib/selpol_rrf_v1.py`
  (`policy_version=1.0.0`) by a path resolved from `__file__`; builds `params.hard_filter` from
  `control_plane.permission_grants` (+ descriptor forbidden/privacy), NEVER from an evidence field (the P0-1
  boundary); keeps #40's own excerpt-fill + fail-closed transport budget (P0-4); regenerated fixtures to the
  canonical selection (only `expand_case_full.json` changed); skill.json + entrypoint 0.2.0 -> 0.3.0 (contract 0.3).
  10 files changed, +535/-504 (native `git show --stat` verified; selpol_reference.py deleted).
- **Worker gate:** off-machine 162/162 python (incl. acceptance (e): the #40-vs-direct-`select()` byte-identity,
  importing the REAL #37 lib) + entrypoint 34/34; deterministic (byte-identical packet on re-run). `-Live`
  DEFERRED by the worker (no #36 catalog ingested -- a #36 dependency) -> run at the orchestrator fold.
- **s4 pin (D-0089, `b5e58ec`):** CONTEXT_PACKET_CONTRACT s4 PINNED #37's canonical selpol_rrf_v1/1.0.0 --
  relevance-primary = the raw-fused-score composite base; AUTHORITY_RANK{1-4} + freshness ranks{0-3}; greedy
  source-MMR + occurrence-preserving display dedup; additive hit-copy output. AUTHORITY_POINTS(40-320) +
  FRESHNESS_POINTS(0-200) + the rank-RRF-primary reference RETIRED. Pure-rank-RRF-primary stays the DEFERRED P1-2.

## Orchestrator D-0077 selpol fold (real #36 data -- also the deferred -Live)

Built a real #36 catalog (core-docs slice, 40 files, 688 chunks) + ingested #41 summary cards + ran #40 compile
(`smoke-i31.ps1`). **PASSED:**

- #40's OWN compile stamps `selection.policy_id=selpol_rrf_v1` + `policy_version=1.0.0`
  (owner=`modules/37-retrieval-eval/lib/selpol_rrf_v1.py`); NO `0.2.0-ref` anywhere -> the reference is fully
  retired (no orchestrator swap needed, unlike i30).
- a valid `context_packet/0.2`: P0-1 three regions + `non_execution=true`; P0-3 `disposition=needs_expansion`
  (conservative, correct while the vector channel is empty); P0-4 `consumer_profile`.
- `evaluation_hooks.retrieved=49` candidates with canonical reason_codes
  [authority_boost, diversity_capped, fusion_rrf, rescued, selected]; re-run `packet_id` byte-identical
  (deterministic); 0 UNMANAGED llama-server/python.
- P0-5 re-confirmed (`record_kind=skill` search returns NO #41 sklcard_); the #41->#36 chain re-confirmed
  (40 accepted / 0 rejected, integrity 15/15, catalog records=41 chunks=688).

**One cosmetic smoke miss (NOT a defect):** the STEP-3 count assertion read `ingested` where the #36
ingest-records response nests the count under `counts.accepted`; verified out-of-band that the ingest succeeded
(accepted, 0 rejected, integrity 15/15). A harness field-name bug in the smoke, not a #36/#41 regression (i31
touched neither). The i30 pair-1 divergence is RESOLVED.

## Deferred (named follow-ons, NOT i31)

The P0-1 adversarial injection SUITE + the action-capable gate release; P1-2 (pure-rank-RRF as the PRIMARY sort);
P1-3..P1-9 + P2; the shared cross-module fixture. Direction: **NEXT = i32 = Tier-0 MEMORY-ARCHITECTURE seam
repairs** (D-0090; `MEMORY_ARCHITECTURE.md` s10 + `research/2026-08-03-memory-architecture-seam-audit.md` s3).
