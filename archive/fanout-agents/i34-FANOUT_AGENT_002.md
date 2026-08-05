# FANOUT_AGENT_002 -- i34 Lane B (modules/37-retrieval-eval (skill `retrieval.eval`))

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i34 (plan `fo-34-584fd656`)
- **Lane:** CPU
- **Worker id / label:** HIERARCHY-EVAL-i34
- **Module/area (exclusive):** modules/37-retrieval-eval (skill `retrieval.eval`), eval + fixtures
- **GPU:** false
- **Docs:** `[]`

## Mission
MEASURE the Tier-1 hierarchy (CONTEXT_PACKET_CONTRACT i34 s7 + MEMORY_ARCHITECTURE Tier-1 gate, D-0098): navigation-cost (nodes examined vs leaf count -> sub-linear O(B*log_F N), p50/p95, NOT constant) + DUAL recall (hierarchy-PATH recall AND end-to-end PACKET-EVIDENCE recall) + shortlist regret + fallback frequency + stale-window recall + adversarial scale/mutation fixtures (identical path prefixes, dominant entity, rare decisive term, cross-cutting, multimodal/absent vectors, insert/delete/tombstone/move/split/collapse, mutation-during-regen, cross-namespace contamination, exact+global mixtures) + the Tier-1 gate set; scaffold + FLAG the ~200MB real-corpus rehearsal as the pre-freeze gate (synthetic scale is necessary, NOT sufficient). CPU-only, deterministic, no model; measures #36/#40 via the external_command/adapter seam (READ-ONLY). Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` i34 s7 + `research/2026-08-04-i34-hierarchy-design-redteam.md`.

## Unit (the full worker prompt)
The complete, self-contained worker prompt -- scope IN/OUT, acceptance, gates, and the appended res.lease +
report commands for plan `fo-34-584fd656` -- is at:
`modules/30-orchestrate-fanout/runtime/artifacts/1e8f4363-630e-4b29-b895-5bdf0096828c/workers/worker-HIERARCHY-EVAL-i34.prompt.md`
(also delivered to Nicholas as a file). READ IT IN FULL AND EXECUTE IT. Pull D-0098 (A6/i34) / D-0096 (A5) /
D-0092 (A4) / D-0077 (the cross-module smoke) from `core-docs/DECISION_LOG_INDEX.md`.

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- docs:[] -> no doc lease; CPU lane -> no gpu lease; take the `git` lease ONLY around your dev.ship commit, release after.
- Do ONE unit; never touch another module (except a READ-ONLY import where the brief allows) or ANY core-doc (the orchestrator mirrors). Gate off-machine FIRST,
  then dev.ship (named files, FAIL-CLOSED); VERIFY the real HEAD via native git (D-0072). 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-34-584fd656 -WorkerId HIERARCHY-EVAL-i34 -State done` + a plain measured summary
  (negative results are first-class, the D-0061 ethos).

## Verification
navigation-cost across >=2 orders of magnitude asserted sub-linear (log-shaped, p50+p95, not constant); DUAL recall (path + packet-evidence) both reported; shortlist regret + fallback frequency + stale-window recall; the adversarial fixtures with KNOWN pinned outcomes (incl mutation-during-regen + cross-ns contamination + rare-decisive-term); the Tier-1 gate set (structural/security/mutation/retrieval/complexity) as deterministic checks; the ~200MB rehearsal harness scaffolded + FLAGGED as an open pre-freeze gate (not claimed passed on synthetic). All shipped eval tests green; deterministic byte-identical; eval/skill version bumped.

## Report-back record (ORCHESTRATOR fills from plans/<id>/reports/ at fold)
_pending -- filled at the i34 fold._
