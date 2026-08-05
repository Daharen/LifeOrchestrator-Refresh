# FANOUT_AGENT_002 -- FILLED (i35 Lane B)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** FILLED
- **Wave / iteration:** i35 -- plan `fo-35-0a5bf334`
- **Lane:** CPU
- **Worker id / label:** REHEARSAL-HARNESS-i35
- **Module/area (exclusive):** modules/37-retrieval-eval (skill `retrieval.eval`)
- **GPU:** false
- **Docs:** `[]`

## Mission
BUILD the ~200MB real foreign-corpus REHEARSAL (scaffolded + FLAGGED in i34) into a RUNNABLE Tier-1
ACCEPTANCE-GATE harness: ingest a foreign-corpus slice into a #36 hierarchy, run manually-labeled queries, measure
the MEMORY_ARCHITECTURE s10 acceptance criteria. Measures #36/#40 via the adapter seam (READ-ONLY). The
ORCHESTRATOR runs the FULL gate vs Lane A's WIRED #40 CLI at fold and owns the project-level tier1_accepted flip.

## Unit (the full worker prompt)
**Your authoritative full brief is the plan-emitted prompt on disk -- READ IT IN FULL and execute EXACTLY that:**
`modules/30-orchestrate-fanout/runtime/artifacts/f16580a4-caa4-41e3-adbd-7a42faebf8ae/workers/worker-REHEARSAL-HARNESS-i35.prompt.md`
It embeds: the READ-FIRST gotcha corpus, the governing docs (MEMORY_ARCHITECTURE s10 + MEMORY_BENCHMARK,
CONTEXT_PACKET_CONTRACT i34 s7, MEMORY_CONTRACT A6/s7, the i34 design + red-team digest), SCOPE IN/OUT, ACCEPTANCE
(a)-(f), GATES, and the exact res.lease (git) acquire/release + `-Action report` lines for plan `fo-35-0a5bf334`.

Compressed summary (the disk brief governs on any conflict): turn the i34 `hierarchy_eval.py` scaffold into a
runnable harness that ingests a REAL FOREIGN corpus slice (NOT the project's own repo) into a #36 hierarchy, runs
committed manually-labeled queries (cross-cutting / rare-decisive-term / current-vs-historical / exact-reference /
global-synthesis), and MEASURES s10: bounded context cost across >=2 orders of magnitude, cross-namespace
contamination below threshold, current-vs-historical correctness, every excerpt reconstructs to source, sub-linear
navigation (p50/p95), + dual recall / regret / fallback-frequency / stale-window recall. Commit a SMALL real-corpus
SAMPLE + a hash-verified full-corpus fetch/prep recipe + a manifest; VALIDATE end-to-end on the sample. ADDITIVE
(prior eval + hierarchy_eval byte-identical). Do NOT claim project Tier-1 acceptance -- emit a computed
tier1_accepted over the corpus+CLI you are pointed at; the orchestrator runs the full ~200MB gate at fold.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order (this lane: git ONLY, around the dev.ship commit); release on exit.
- Do ONE unit; never touch modules/areas outside the exclusive claim (#37 only; measure #36/#40 READ-ONLY via the adapter seam); `docs:[]`.
- Gate off-machine FIRST, then ship via `dev.ship`; VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-35-0a5bf334 -WorkerId REHEARSAL-HARNESS-i35 -State done` + a plain measured summary.

## Verification
Per ACCEPTANCE (a)-(f) in the disk brief: a runnable ingest->label->measure harness (CLI-agnostic via the adapter
seam); the s10 criteria + thresholds; a committed small SAMPLE + a hash-verified full-corpus recipe + manifest;
labeled query fixtures with pinned outcomes; tier1_accepted is harness-computed (not a project claim); shipped eval
+ hierarchy_eval tests byte-identical (regression). Off-machine FIRST, then -Live. SCHEMA_NOTES updated for the fold.