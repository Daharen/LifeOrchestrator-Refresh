# FANOUT_AGENT_003 -- i32 Tier-0 Lane C (modules/40-context-compiler)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i32 (plan `fo-32-0fb25203`)
- **Lane:** CPU
- **Worker id / label:** CONTEXT-COMPILER-TIER0-i32
- **Module/area (exclusive):** modules/40-context-compiler (skill `context.compile`), 0.3.0 -> 0.4.0
- **GPU:** false
- **Docs:** `[]`

## Mission
The CONSUMER: plumb the Tier-0 seams through the packet (CONTEXT_PACKET_CONTRACT i32, D-0092). Pass `task_input.namespace` as `filters.namespace` to the retriever AND `params.allowed_namespaces` to `selpol_rrf_v1` (U1, fail-closed on any cross-namespace evidence item); add a deterministic query-classification STAGE stamping `query_class` that drives the temporal mode (U5); RESERVE the FOURTH `working_memory` packet region (seam, NO store) (U3); propagate `current_only` (U4); import #37's `selpol_rrf_v1` 1.1.0; re-assert provenance-expansion (gate test 3). CPU-only, deterministic, no model. If the canonical select() cannot serve the new params without a #37 change, STOP + report a fold reconciliation. Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` (i32 + s1/s2/s4/s6), `core-docs/MEMORY_CONTRACT.md` A4, `core-docs/MEMORY_ARCHITECTURE.md` s5.

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-32-0fb25203` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/8f4146d5-9472-4a62-a144-6b7673c0766d/workers/worker-CONTEXT-COMPILER-TIER0-i32.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0092 (the amendment) / D-0090
(architecture) / D-0083 / D-0077 from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST, then
  dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-32-0fb25203 -WorkerId CONTEXT-COMPILER-TIER0-i32 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
namespace passed both ways + a packet never carries a cross-namespace evidence item (fail-closed, mixed fixture); the query-classification stage stamps `query_class` (all 9 classes) into task_input+descriptor+packet_id; the `working_memory` region present (empty) + rendered + documented; imports selpol_rrf_v1 1.1.0 + carries the new reason_codes; P0-1/P0-3/P0-4/P1-5/A2 + non_execution:true stay green; GATE TEST 3 (provenance-expansion on a namespaced fixture); the #40-vs-direct-select byte-identity; deterministic. skill.json 0.3.0->0.4.0. SCHEMA_NOTES records every i32 interpretation.

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i32 fold._
