# FANOUT_AGENT_001 -- i33 Lane A (modules/36-artifact-search (skill `artifact.search`))

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i33 (plan `fo-33-d7b55e46`)
- **Lane:** CPU
- **Worker id / label:** ARTIFACT-SEARCH-CLOSURE-i33
- **Module/area (exclusive):** modules/36-artifact-search (skill `artifact.search`), 0.3.0 -> 0.4.0
- **GPU:** false
- **Docs:** `[]`

## Mission
CLOSE the Tier-0 namespace boundary and make supersession CANDIDATE-INDEPENDENT (MEMORY_CONTRACT Amendment A5, D-0096), hardening the i32 envelope-level layer the frontier red-team (159e9cb5) found incomplete. Enforce ONE canonical `ns_permitted` at EVERY stage + graph hop; scope-check every returned/reachable object; reject cross-namespace derivations; sanitized fail-closed rejection (violation_count + abort, detail to a local security log). Add the `superseded` s5 value + `superseded_by`/`supersedes` edges + catalog-computed pool-independent `effective_current`. Reserve provenance_mode-conditional hit fields + `candidate_role`/retrieval-stage lineage; reserve the working-state store fields + REJECT `record_kind=working` from ordinary search. schema_version 3->4 additive migration. You OWN the hardened gate tests. Import #37's canonical `ns_permitted` READ-ONLY. CPU-only, deterministic, no model. Governing: `core-docs/MEMORY_CONTRACT.md` A5 (+ s1/s3/s5); `core-docs/research/2026-08-04-tier0-amendment-redteam.md` (changes 1-4).

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease + report
commands for plan `fo-33-d7b55e46` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/593db407-1d58-4738-af6c-587e19b6e8d8/workers/worker-ARTIFACT-SEARCH-CLOSURE-i33.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0096 (the re-amendment) / D-0095
(the red-team digest) / D-0092 (i32/A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module (except the READ-ONLY import of #37's ns_permitted) or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-33-d7b55e46 -WorkerId ARTIFACT-SEARCH-CLOSURE-i33 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
The HARDENED gate tests: (1) namespace CLOSURE on a mixed-ns fixture -- per-hop + derived-record + diagnostic-array + ingest rejection, only `namespace_violation_count` surfaces; (2) POOL-INDEPENDENT current_only -- a superseded record excluded even when its successor is ABSENT from the fetched pool; (3) working search-rejection -- ordinary search never returns `record_kind=working`, only the exact conjunctive task_id+namespace op does. schema_version 3->4 additive in-place migration (no re-ingest; shipped tables byte-identical). All shipped 0.3 tests green; deterministic catalog_digest. skill.json 0.3.0->0.4.0. SCHEMA_NOTES records every A5 interpretation (REQUIRED for the D-0077 fold).

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i33 fold._
