# FANOUT_AGENT_001 -- i32 Tier-0 Lane A (modules/36-artifact-search)

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i32 (plan `fo-32-0fb25203`)
- **Lane:** CPU
- **Worker id / label:** ARTIFACT-SEARCH-TIER0-i32
- **Module/area (exclusive):** modules/36-artifact-search (skill `artifact.search`), 0.2.0 -> 0.3.0
- **GPU:** false
- **Docs:** `[]`

## Mission
Enforce/reserve the Tier-0 RECORD/RETRIEVER seams (MEMORY_CONTRACT Amendment A4, D-0092) in the retriever + catalog: namespace as a HARD retrieval boundary + all-hits-match assertion (U1); a `current_only` retrieval MODE hard-excluding non-`current` (U4); RESERVE `node`/`working` record_kinds + `member_of_node`/`child_of_node`/`contradicts` edges via an ADDITIVE `schema_version` 2->3 in-place migration, NO table rewrite (U2/U3/U4). You OWN Tier-0 gate tests 1 (namespace isolation) + 2 (schema-evolution). CPU-only, deterministic, no model. Governing: `core-docs/MEMORY_CONTRACT.md` A4 + s1/s3/s5, `core-docs/MEMORY_ARCHITECTURE.md` s9/s10, `core-docs/research/2026-08-03-memory-architecture-seam-audit.md` s3 (U1/U2/U4).

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-32-0fb25203` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/8f4146d5-9472-4a62-a144-6b7673c0766d/workers/worker-ARTIFACT-SEARCH-TIER0-i32.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0092 (the amendment) / D-0090
(architecture) / D-0083 / D-0077 from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST, then
  dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-32-0fb25203 -WorkerId ARTIFACT-SEARCH-TIER0-i32 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
GATE TEST 1 (zero cross-namespace leakage on a mixed fixture) + GATE TEST 2 (a `node` record + `member_of_node`/`child_of_node`/`contradicts` edges ingest + retrieve additively with sources/documents/versions/chunks byte-identical pre/post) + the `current_only` superseded-twin test; all shipped 0.2 tests green; deterministic catalog_digest. skill.json 0.2.0->0.3.0. SCHEMA_NOTES records every A4 interpretation (REQUIRED for the D-0077 fold).

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i32 fold._
