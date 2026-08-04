# FANOUT_AGENT_003 -- i34 Lane C (modules/40-context-compiler (skill `context.compile`))

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i34 (plan `fo-34-584fd656`)
- **Lane:** CPU
- **Worker id / label:** SHORTLIST-DESCEND-i34
- **Module/area (exclusive):** modules/40-context-compiler (skill `context.compile`), 0.5.0 -> 0.6.0
- **GPU:** false
- **Docs:** `[]`

## Mission
BUILD the shortlist-and-descend retrieval PLAN + enforce SAFE-PRUNING (CONTEXT_PACKET_CONTRACT i34, D-0098): a deterministic descend-decision (query_class stub; router -> i35) routes global/overview/precedent to shortlist authorized roots -> descend the frontier (bounded B/D) -> leaf candidates -> the existing selpol/budget/packet; local/exact stays flat-top-k. ENFORCE V2 safe-pruning (prune ONLY via a no-false-negative predicate; else expand/switch-channel/flat-fallback/needs_expansion|abstain; a stale synopsis never prunes) + V3 retrieval_completeness (a hierarchy miss != proved absence; distinct from evidence coverage) + navigation_refs (nodes route, NEVER evidence) + V4 hierarchy in packet identity + V5 navigation-vs-evidence closure. CONSUMER of #36's shortlist/descend + #37's selpol_rrf_v1/ns_permitted (READ-ONLY import). CPU-only, deterministic, no model. Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` i34 + `core-docs/MEMORY_CONTRACT.md` A6.

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-34-584fd656` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/1e8f4363-630e-4b29-b895-5bdf0096828c/workers/worker-SHORTLIST-DESCEND-i34.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0098 (A6/i34) / D-0096 (A5) /
D-0092 (A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module (except a READ-ONLY import where the brief allows) or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-34-584fd656 -WorkerId SHORTLIST-DESCEND-i34 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
the multi-stage plan (bounded B/D; descend-decision routes global->descend, local->flat; nodes via navigation_refs, never evidence); (P0) safe-pruning enforced -- a bounded-descriptor-only branch triggers fallback (proven by a test), a stale synopsis never prunes; retrieval_completeness fields correct (a miss != proved absence; navigation/summary_stale never in missing_requirements[]); packet identity covers hierarchy_id + tree_version + builder/prune policy + the stage trace (one pinned tree_version/compile); navigation-vs-evidence closure (no cast to evidence; every nav-visible object namespace-closure-checked + fail-closed no-metadata); the shipped P0-1/P0-3/P0-4/P1-5/A2 + i32/i33 closure + working_memory stay green; non_execution:true unchanged; deterministic. skill.json 0.5.0->0.6.0. SCHEMA_NOTES records every i34 interpretation.

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i34 fold._
