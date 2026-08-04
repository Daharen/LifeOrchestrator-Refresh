# SELECTION-POLICY-i30 -- SHIP STATE (FANOUT_AGENT_002, plan fo-30-dd453156)

**Status: SHIPPED + COMMITTED + REPORTED done. HEAD `99bb627`.** Author: FANOUT_AGENT_002
(SELECTION-POLICY-i30). Lane: CPU, module `modules/37-retrieval-eval` 0.2.0 -> 0.3.0. Closed 2026-08-03.

## Outcome

- **Commit `99bb627`** ("i30 retrieval.eval 0.2.0 -> 0.3.0: selpol_rrf_v1 selection-policy library (P1-1) +
  eval-0.3"), parent `f06e6e7` (#40 context-compiler i30). Native `git show --stat` = exactly 12 files,
  +1325/-277. Working tree clean. (D-0072 verified via native git, not just the dev.ship `committed` field.)
- **dev.ship gate GREEN:** sha 12/12 ok, AST 2/2 ok, tests exit 0 = "ALL PASS (retrieval.eval eval-0.2)",
  git lease `00bd0acf` acquired (waited 75ms) + released, orphans llama-server 0 / python 0.
- **review_queue.jsonl before == after** (`e8288032...`, 20 lines). 0 UNMANAGED orphans (no model this wave).
- **Report recorded:** plan `fo-30-dd453156` worker `SELECTION-POLICY-i30` state `done`
  (reports/SELECTION-POLICY-i30.c2f4106f.json). No leases held (dev.ship owns the git lease; CPU lane = no
  gpu lease; docs:[] = no doc lease).

## What shipped

The ONE versioned deterministic selection-policy library `selpol_rrf_v1`
(`modules/37-retrieval-eval/lib/selpol_rrf_v1.py`, CONTEXT_PACKET_CONTRACT s4 / P1-1) -- PURE, stdlib,
`select(candidates, descriptor, policy_id, params) -> {selected[], ranked[], policy_id, policy_version,
features_by_candidate, omission_manifest[], stages}`. Stages: hard filters -> temporal (s5) -> authority ->
versioned RRF over CHANNEL RANKS (retrieval_occurrences[]; P1-2) -> occurrence-preserving DISPLAY dedup
(evidence_cluster_id + occurrences[], provenance NEVER erased; P1-3) -> budget. Output ADDITIVE (preserves
retrieval_rank + channel ranks; adds selection_rank/selection_score/selection_policy_id/selected/reason_codes);
never re-sorts in place. The shipped `rerank()` is now a THIN WRAPPER (`selpol.rerank_compat`) -- proven
behavior-preserving (aggregate/rerank_ab/rerank_diagnostics/hybrid/per_query byte-identical after refactor;
only report schema 0.2->0.3 + additive fields changed). Eval-0.3: per-stage metrics (raw/post_filter/packet),
packet_disposition scoring (supplied #40 packet OR computed), hybrid marked not_applicable (not zero) while the
vector channel is EMPTY. New: tests/test_selpol.py (27 library-unit checks), tests/fixtures/benchmark3.json.

## For the D-0077 fold (#40 <-> #37 byte-identical selection)

#40 loads `selpol_rrf_v1` by a resolved path (self-contained stdlib) and calls `select(..., dedup_display=True,
budget)` to build its packet excerpts + omission_manifest + additive selection fields; `hard_filter` comes from
`control_plane.permission_grants`/`permission_context`, temporal from candidate `status`. The fold asserts
#40-with-its-reference-impl == #40-with-this-canonical-`selpol_rrf_v1`. Interface + stage order + RRF + dedup +
baseline-compat + the label->policy-signal mapping are recorded in `modules/37-retrieval-eval/SCHEMA_NOTES.md`
sections 9-13.

## Deferred (named follow-ons, NOT i30)

P1-2 score-comparability calibration (replacing raw-score direct-relevance with pure rank-RRF as the PRIMARY
sort -- changes ordering); P1-3 near-dup algorithm calibration; full P1-4 graded-relevance / judged-result
metrics; P1-8 held-out fresh-9B suite; P1-9 synthetic precomputed-vector fixture (would exercise multi-channel
RRF + vector-rescue end-to-end). The eval accepts the extra labels additively so these are plumbing, not a break.

## Gotcha logged (for future device writes)

An existing repo file (`Invoke-RetrievalEval.ps1`) carried the Windows **ReadOnly attribute**, which denied ALL
writes (bridge device_commit_files, VM bash, AND executor `[IO.File]::WriteAllText`) with "Access denied" that
looked like a handle lock / Controlled Folder Access. CFA was OFF and ACLs were FullControl -- the cause was
the RO attribute. Fix: an executor task `Set-ItemProperty -Name IsReadOnly -Value $false` (or `attrib -R`),
then the write succeeds. If a device write is denied but reads work, check `(Get-Item -Force).IsReadOnly` first.
