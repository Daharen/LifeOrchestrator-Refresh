# FANOUT_AGENT_002 -- i33 Lane B (modules/37-retrieval-eval (skill `retrieval.eval`))

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i33 (plan `fo-33-d7b55e46`)
- **Lane:** CPU
- **Worker id / label:** RETRIEVAL-EVAL-PREDICATE-i33
- **Module/area (exclusive):** modules/37-retrieval-eval (skill `retrieval.eval`), 0.4.0 -> 0.5.0
- **GPU:** false
- **Docs:** `[]`

## Mission
AUTHOR the ONE canonical namespace predicate + rejection/sanitization policy (`ns_permitted`) in `lib/` -- the single owner #36 and #40 import (MEMORY_CONTRACT A5 risk-6). Make selpol supersession CANDIDATE-INDEPENDENT (1.1.0->1.2.0): demote/hard-filter on #36's catalog-computed `effective_current` even when a successor is absent; propagate a `conflicted` branch; scope-check selpol's own diagnostic arrays. Split `query_class` (semantic) from `temporal_intent` and author the VERSIONED class->temporal_mode map (classifier_policy_id/version, + composite/unclassified). eval 0.4->0.5 adds stages that TEST the leakage paths + supersession + the split. PURE + deterministic, no model. Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` s4 (PINNED) + the i33 amendment; `MEMORY_CONTRACT.md` A5; `research/2026-08-04-tier0-amendment-redteam.md` (changes 1, 2, 5 + risk 6).

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease + report
commands for plan `fo-33-d7b55e46` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/593db407-1d58-4738-af6c-587e19b6e8d8/workers/worker-RETRIEVAL-EVAL-PREDICATE-i33.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0096 (the re-amendment) / D-0095
(the red-team digest) / D-0092 (i32/A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-33-d7b55e46 -WorkerId RETRIEVAL-EVAL-PREDICATE-i33 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
The canonical `ns_permitted` + rejection/sanitization policy live in `lib/`, pure + unit-tested (accept/reject/empty/sanitization) -- the single owner #36+#40 import. selpol 1.2.0: current_only hard-filters on catalog `effective_current` with an ABSENT successor; `superseded_demote` orders successor above superseded; branch -> conflicted flag; diagnostics carry no cross-ns identifying data; absent-param selection BYTE-IDENTICAL to 1.1.0 (regression proof). query_class/temporal_intent split with explicit-time override; the class->mode map versioned. eval 0.5 measures the leakage paths + supersession + the split + reason_codes; deterministic. All shipped 0.4 tests green. POLICY_VERSION 1.2.0; skill.json 0.5.0. SCHEMA_NOTES records every A5/i33 interpretation (REQUIRED for the D-0077 fold).

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i33 fold._
