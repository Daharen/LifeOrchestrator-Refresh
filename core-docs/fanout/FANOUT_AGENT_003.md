# FANOUT_AGENT_003 -- i33 Lane C (modules/40-context-compiler (skill `context.compile`))

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i33 (plan `fo-33-d7b55e46`)
- **Lane:** CPU
- **Worker id / label:** CONTEXT-COMPILER-CLOSURE-i33
- **Module/area (exclusive):** modules/40-context-compiler (skill `context.compile`), 0.4.0 -> 0.5.0
- **GPU:** false
- **Docs:** `[]`

## Mission
Plumb the CLOSED namespace boundary + candidate-independent supersession + the query_class/temporal_intent split THROUGH the packet, per the CONTEXT_PACKET_CONTRACT i33 amendment (D-0096). Compute `effective_allowed_namespaces = intersection(task_input.namespace request, control_plane grant)` and pass it BOTH ways (empty -> fail-closed); import #37's canonical `ns_permitted` and scope-check EVERY packet-visible object (evidence + working_memory + all provenance/derivation refs + every diagnostic array); sanitized abort. Pass #36's catalog `effective_current` to selpol; consume `candidate_role` (navigation routes, never answer-evidence); harden the `working_memory` region (conjunctive access + `state_version` in packet identity); split query_class/temporal_intent + import the versioned classifier map; packet identity covers it all. Import #37 selpol 1.2.0 READ-ONLY. CONSUMER; CPU-only, deterministic, no model. Governing: `CONTEXT_PACKET_CONTRACT.md` i33 (+ s1/s2/s4/s6); `MEMORY_CONTRACT.md` A5; `research/2026-08-04-tier0-amendment-redteam.md` (changes 1, 3, 4, 5).

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease + report
commands for plan `fo-33-d7b55e46` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/593db407-1d58-4738-af6c-587e19b6e8d8/workers/worker-CONTEXT-COMPILER-CLOSURE-i33.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0096 (the re-amendment) / D-0095
(the red-team digest) / D-0092 (i32/A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module (except the READ-ONLY import of #37's lib) or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-33-d7b55e46 -WorkerId CONTEXT-COMPILER-CLOSURE-i33 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
effective_allowed_namespaces = intersection(request, grant) computed + passed both ways; an empty intersection fails closed; EVERY packet-visible object scope-checked; a mixed-ns fixture proves NO cross-ns item (evidence OR diagnostic) reaches the packet -- only a `namespace_violation_count`. Catalog `effective_current` passed to selpol (absent-successor superseded filtered); branch -> `packet_disposition=conflicted`. `candidate_role` consumed; working_memory conjunctive access + `state_version` in packet identity (NO store built); query_class/temporal_intent split with explicit-time override + versioned classifier in packet identity. P0-1 three-region + non_execution:true + P0-3/P0-4/P1-5/A2 stay green; GATE TEST 3 (provenance-expansion + sanitized-abort on a namespaced fixture) passes; deterministic packet_id. skill.json 0.4.0->0.5.0. SCHEMA_NOTES records every A5/i33 interpretation (REQUIRED for the D-0077 fold).

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i33 fold._
