# FANOUT_AGENT_001 -- FILLED (i36, plan fo-36-1a676e4b)

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** FILLED
- **Wave / iteration:** iteration 36 -- plan `fo-36-1a676e4b` (Tier-1 ACCEPTANCE wave, 3-lane CPU, GPU skipped)
- **Lane:** CPU lane -- retrieval.eval #37
- **Worker id / label:** `REHEARSAL-WIRE-DESCEND-i36` -- eval 0.7.0->0.8.0: drive #40 0.7.0's WIRED descend path from rehearsal_eval
- **Module/area (exclusive):** `modules/37-retrieval-eval/` ONLY (#40 is READ-ONLY via the external_command adapter seam)
- **GPU:** false
- **Docs:** `[]`

## Mission
Point #37's `rehearsal_eval.py` at #40 0.7.0's WIRED descend path (shipped i35, `aa2f0fb`). Today the harness measures navigation via #36-direct shortlist/descend and compiles #40 FLAT; you construct scoped DESCEND-class `artifact_search` compile requests (via the overridable `m40_argv` adapter) so #40 0.7.0 runs the real shortlist-and-descend PLAN end-to-end, and you MEASURE the s10 Tier-1 criteria against the WIRED packets. This is the harness half of the Tier-1 flip -- the ORCHESTRATOR runs the FULL ~200MB gate against the FROZEN #40 0.7.0 at fold and owns the `tier1_accepted` flip ('never a silent pass'). Governing: `MEMORY_ARCHITECTURE.md` s10 + `CONTEXT_PACKET_CONTRACT.md` i34 s7 + `MEMORY_CONTRACT.md` A6.

## Unit (the full worker prompt)
**The FULL worker prompt -- mission + rails + the EXACT res.lease acquire/release + `-Action report` command lines bound to plan `fo-36-1a676e4b` -- is the emitted copy at**
`modules/30-orchestrate-fanout/runtime/artifacts/e2415cac-1e7d-4d68-9104-4c57a9ede05c/workers/worker-REHEARSAL-WIRE-DESCEND-i36.prompt.md`
**(also delivered to Nicholas as a file). Dispatch: start a FRESH Cowork session, hand it that prompt file (or say "read that file and execute it"), grant the ONE folder `C:\Users\just_\LifeOrchestrator-Refresh`. READ + execute exactly that unit.**

Scope (compact -- the emitted prompt is authoritative):
- Construct #40 requests that TRIGGER the real hierarchy_port (retriever=artifact_search + catalog db_path + a DESCEND query_class + effective_allowed_namespaces present + pinned hierarchy_version/corpus_snapshot); read the EXACT keys from #40's SCHEMA_NOTES (READ-ONLY).
- Measure s10 against the WIRED packets: bounded cost across >=2 orders of magnitude; cross-namespace contamination below threshold; current-vs-historical; reconstruct-to-source; SUB-LINEAR navigation from #40's OWN plan/stage trace; + dual recall (PATH + end-to-end PACKET-EVIDENCE) / regret / fallback / stale-window.
- Keep the #36-direct-nav/#40-flat path as a LABELED BASELINE (descend-vs-flat deltas). Additive: the non-wired path stays BYTE-IDENTICAL to shipped 0.7.0.
- Update FULL_CORPUS_RECIPE.md with the WIRED invocation; validate the SMALL sample end-to-end vs the REAL #40 0.7.0 CLI.

Acceptance (compact):
(a) a WIRED-descend drive path triggering #40 0.7.0's port via the adapter; (b) s10 measured against WIRED packets incl. sub-linear nav from #40's own trace + dual recall/regret/fallback/stale-window; (c) the flat baseline retained + labeled; (d) FULL_CORPUS_RECIPE updated; (e) tier1_accepted harness-computed, NOT a project claim; (f) shipped 0.7.0 tests GREEN, non-wired path byte-identical, eval/skill 0.7.0->0.8.0.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. CPU lane -> NO gpu lease; take `git` ONLY around the dev.ship commit.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-36-1a676e4b -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
The orchestrator D-0077 fold RUNS this harness against the frozen #40 0.7.0 (sample at fold, then the FULL ~200MB gate) + the i34 `smoke-i34.py` 38/38 regression, and flips project `tier1_accepted` IFF it passes. If #40 0.7.0 cannot be driven into descend without a #40 change -> STOP + report a FOLD RECONCILIATION (do NOT edit #40).

## Report-back record (ORCHESTRATOR fills from `plans/fo-36-1a676e4b/reports/` before archiving)
_empty._
