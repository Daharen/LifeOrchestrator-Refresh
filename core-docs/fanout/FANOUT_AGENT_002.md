# FANOUT_AGENT_002 -- i30 CONTRACT-HARDENING SELECTION-POLICY lane

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i30 (plan id `fo-30-dd453156`)
- **Lane:** CPU -- the GPU lane is SKIPPED this wave (deterministic, no model)
- **Worker id / label:** SELECTION-POLICY-i30
- **Module/area (exclusive):** modules/37-retrieval-eval (skill id `retrieval.eval`) 0.2.0 -> 0.3.0
- **GPU:** false
- **Docs:** `[]`

## Mission

Author the ONE versioned DETERMINISTIC selection-policy library `selpol_rrf_v1` (`core-docs/CONTEXT_PACKET_CONTRACT.md`
s4 / P1-1) -- OWNED here, CONSUMED by the context compiler #40 and by your own eval A/B -- extracted from the
shipped `rerank()`, so there is exactly ONE selection owner (removing the two-reranker problem). Plus refine the
eval harness to score PER-STAGE + `packet_disposition` (the P1-4 subset i30 needs). PRODUCER of the library #40 consumes.

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/e0626255-ae62-4a28-acf5-b14c6d48e845/workers/worker-SELECTION-POLICY-i30.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan.)

Scope digest (orientation only -- the emitted prompt governs):

- selpol_rrf_v1 (s4): implement `select(candidates, descriptor, policy_id, params) -> {selected[], ranked[], policy_id, policy_version, features_by_candidate}` under `modules/37-retrieval-eval/lib/` (python, stdlib). Stages: hard filters -> temporal (stale demote) -> authority -> rank-based RRF fusion over CHANNEL RANKS (not cross-query raw scores; keep retrieval_occurrences[]) -> occurrence-preserving dedup (dedup DISPLAY tokens, never provenance) -> budget. PURE, deterministic.
- Output ADDITIVE: preserve retrieval_rank/lexical_rank/vector_rank/fused_rank; add selection_rank/selection_score/selection_policy_id/selected/reason_codes. NEVER re-sort the retrieval array in place.
- Adopt in the harness: the shipped rerank() becomes a thin wrapper calling selpol_rrf_v1 (the measured A/B now measures the library; shipped 0.2 benchmark + A/B stay green).
- Eval refinement: per-stage metrics (raw/post-filter/packet) + packet_disposition correctness scoring; hybrid metrics not_applicable (not zero) when the vector channel is empty. Full P1-4 graded relevance = follow-on.
- NON-goals: #40, real vectors, a model reranker, full P1-4, P1-2/P1-3 calibration beyond the rank-RRF + occurrence-dedup baseline, models.json.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md`.
- Read `core-docs/CONTEXT_PACKET_CONTRACT.md` (D-0087; context_packet/0.2 + the s4 selection interface) + `core-docs/MEMORY_CONTRACT.md` (A2/A3) IN FULL -- the governing contracts for this wave. Pull the frontier digest `core-docs/research/2026-08-02-frontier-wave3-design-redteam.md` for the P0/P1 rationale.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY your module.
- Gate OFF-MACHINE first (cloud pwsh/python + mock/seam), THEN `-Live` on the executor; ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire the `git` lease ONLY around your dev.ship commit (release after). VERIFY the real HEAD via native `git log`/`git show --stat`, NOT the dev.ship `committed` field (D-0072).
- Any persistent llama-server launches DETACHED + is reaped before finalize (N/A this wave -- no model); assert 0 UNMANAGED orphans. Report via `-Action report -PlanId fo-30-dd453156 -WorkerId <id> -State done` (negative results are first-class, D-0061).

## Verification

`selpol_rrf_v1` is deterministic + pure (byte-identical selection on re-run); its signature exactly matches CONTEXT_PACKET_CONTRACT s4; a test where it RESCUES a required source out of raw top-K AND DEMOTES a stale/forbidden hit (A/B delta reported), preserving retrieval_rank; occurrence-preserving dedup (identical text -> one display item, occurrences kept); the shipped 0.2 benchmark + reranker A/B stay GREEN; per-stage + packet_disposition scoring compute with known fixture values; reports byte-identical cross-env. `-Live` over a real core-docs slice via the real #36 retriever. skill.json 0.3.0 + docs to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-30-dd453156/reports/`)

(commit, test counts, measurements, residuals -- filled at handoff.)
