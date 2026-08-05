# FANOUT_AGENT_001 -- i34 Lane A (modules/36-artifact-search (skill `artifact.search`))

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i34 (plan `fo-34-584fd656`)
- **Lane:** CPU
- **Worker id / label:** HIERARCHY-BUILDER-i34
- **Module/area (exclusive):** modules/36-artifact-search (skill `artifact.search`), 0.4.0 -> 0.5.0
- **GPU:** false
- **Docs:** `[]`

## Mission
BUILD the Tier-1 bounded-fanout HIERARCHY (MEMORY_CONTRACT Amendment A6, D-0098): the `node` layer + `member_of_node`/`child_of_node` canonical edges + a DETERMINISTIC BALANCED bulk-builder (MAX_FANOUT, min-occupancy, deterministic split, flat-fallback + `rebuild_required`; live split -> i35) + a deterministic structural synopsis (sufficient-statistics vector aggregate) + generations/CAS staleness (kills the ABA stale-clear race) + write-time+transitive namespace HOMOGENEITY (SAFETY-CRITICAL) + authorization-bound `shortlist`/`descend` frontier ops (SAFETY-CRITICAL) + the SAFE-PRUNING no-false-negative channel predicates (the frontier red-team's load-bearing fix: navigation prioritizes, NEVER excludes a branch without a proof) + atomic tree-version publication + schema_version 4->5. You OWN the hierarchy gate tests. Import #37's canonical ns_permitted READ-ONLY. CPU-only, deterministic, no model. Governing: `core-docs/MEMORY_CONTRACT.md` A6; `research/2026-08-04-i34-hierarchy-design.md` + `-redteam.md`.

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-34-584fd656` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/1e8f4363-630e-4b29-b895-5bdf0096828c/workers/worker-HIERARCHY-BUILDER-i34.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0098 (A6/i34) / D-0096 (A5) /
D-0092 (A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module (except a READ-ONLY import where the brief allows) or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-34-584fd656 -WorkerId HIERARCHY-BUILDER-i34 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
The hierarchy gate tests: STRUCTURAL (deterministic byte-identical rebuild; no cycles/orphans; fanout+occupancy; one parent; projection==canonical edges; atomic publication); SECURITY (zero cross-ns aggregate/metadata leakage; unauthorized descend fails closed; mixed-ns build inputs rejected); MUTATION/FRESHNESS (every mutation dirties the ancestor paths; no lost-update stale-clear race; a stale node cannot supply a pruning proof); SAFE-PRUNING (a bounded descriptor NEVER prunes; only exact/range/membership predicates prune a provably-empty branch). schema_version 4->5 additive in-place (no re-ingest; shipped tables byte-identical; zero nodes = flat behavior). All shipped 0.4 tests green; deterministic (double-run byte-identical catalog_digest + tree_digest). skill.json 0.4.0->0.5.0. SCHEMA_NOTES records every A6 interpretation (REQUIRED for the D-0077 hierarchy fold).

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i34 fold._
