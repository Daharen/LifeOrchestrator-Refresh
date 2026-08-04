# FANOUT_AGENT_002 -- i32 Tier-0 Lane B (modules/37-retrieval-eval)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i32 (plan `fo-32-0fb25203`)
- **Lane:** CPU
- **Worker id / label:** RETRIEVAL-EVAL-SELPOL-TIER0-i32
- **Module/area (exclusive):** modules/37-retrieval-eval (skill `retrieval.eval`), selpol_rrf_v1 1.0.0 -> 1.1.0 / eval 0.3 -> 0.4
- **GPU:** false
- **Docs:** `[]`

## Mission
The SELECTION-POLICY OWNER: fold the CONTEXT_PACKET_CONTRACT i32 amendment (D-0092) into `lib/selpol_rrf_v1.py` (1.0.0->1.1.0, additive stages) + score it (eval 0.3->0.4). stage-1 `hard_filter_namespace` (retire the namespace soft boost, U1); stage-2 `current_only` HARD stale filter + `superseded_demote` (U4); `query_class`-driven temporal mode + channels kept OPEN (U5). PURE + deterministic, no model. #40 IMPORTS your lib; the orchestrator runs the D-0077 selpol byte-identity smoke at fold. Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` s4 (PINNED) + the i32 amendment, `core-docs/MEMORY_CONTRACT.md` A4.

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-32-0fb25203` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/8f4146d5-9472-4a62-a144-6b7673c0766d/workers/worker-RETRIEVAL-EVAL-SELPOL-TIER0-i32.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0092 (the amendment) / D-0090
(architecture) / D-0083 / D-0077 from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST, then
  dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-32-0fb25203 -WorkerId RETRIEVAL-EVAL-SELPOL-TIER0-i32 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
`hard_filter_namespace` sinks cross-namespace + the soft boost is gone; absent-param selection BYTE-IDENTICAL to 1.0.0 (regression proof); `current_only`->`hard_filter_stale`; `superseded_demote` orders successor above superseded; `query_class`->temporal mode; a synthetic 3rd channel fuses with no code change; eval 0.4 measures namespace/current_only/supersession + reason_codes; deterministic. POLICY_VERSION 1.1.0; skill.json 0.4.0. SCHEMA_NOTES records every i32 interpretation.

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i32 fold._
