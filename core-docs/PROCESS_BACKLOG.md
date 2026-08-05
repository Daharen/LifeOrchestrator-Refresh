# PROCESS_BACKLOG -- cross-cutting process / tooling / doc-hygiene debt (router, not a spec)

Owns the deferred **process / orchestration / doc-hygiene** work that is NOT a single module's follow-on (those
live per-module in `MODULE_ROADMAP.md`) and NOT a runtime review item (`REVIEW_QUEUE.md`). ONE terse row per open
item: an id, one line, a deterministic **Trigger** (when to act), and a `D-ref` for the full rationale. Keep it a
ROUTER -- detail goes in the D-entry, NEVER here (same per-row discipline as `DECISION_LOG_INDEX.md`; budget in
`DOC_PROTOCOL.md` s2).

**Capture rule (ongoing):** anyone -- Nicholas, an orchestrator, a worker, a frontier reviewer -- who defers a
cross-cutting process/tooling/hygiene fix ADDS a one-line row here + a D-entry, instead of leaving it as a handoff
"named residual" (rewritten every session -> drifts) or a scattered "doc debt" mention. Close a row with `DONE
(D-00xx)` and move detail to the D-entry; compact closed rows periodically.

**Forcing function (honest):** a prose "revisit the backlog" checklist step is NOT reliable -- `DOC_PROTOCOL` s9
step 5 already mandates a size check and it was skipped for several iterations (PB-1 evidence). The durable pawl is
the **mechanical commit gate (PB-1)**: it refuses a commit that violates a budget/brevity rule, forcing the matching
item at the moment it bites. The backlog is the memory; the gate is the alarm. Triggers below are for the JUDGMENT
items the gate can only DETECT, not FIX.

## Open

| id | item | trigger | D-ref |
|---|---|---|---|
| PB-1 | Doc-hygiene commit GATE (deterministic, fail-closed) -- the archetype scope gate + the forcing function for the rest. THREE parts (D-0094): (a) a DENSITY check = fail if bytes-per-state rises above a per-doc cap (e.g. an index decision cell > ~160 chars) -- the BLOAT signal; (b) a PROPORTIONAL budget = density_cap x state_count x headroom, recomputed from the real state count -- NOT a static constant (a fixed cap is the "ceiling at the start" anti-pattern that fires on legitimate growth and trains dismissal); (c) a RE-LAYER trigger at the bounded-read threshold (max a hot doc may cost to ingest whole, pegged to the 9B) -> shard + index-the-index + route to retrieval (#36, the memory hierarchy), NOT endless slimming. Fires on BLOAT, never on GROWTH. | Next doc-tooling / executor touch -- highest-priority process item. Evidence: handoff 51/24, CURRENT_STATE 53/34, MODULE_ROADMAP 44/37 over budget; the D-0090/91/92 index re-bloat one session after a slim; DOC_PROTOCOL s9 step 5 (a prose size check) was skipped this session. | D-0093 / D-0094 |
| PB-2 | Reserved delegation seam: a `DELEGATION_PROTOCOL` + a bounded delegation-index + subagent brief templates for recurring JUDGMENT doc-hygiene (handoff slim, producer/consumer divergence reconcile). RESERVE now, BUILD later (Tier-1-style). **+ (D-0101):** whenever this seam OR the D-0080 local coordinator spawns a CONTEXT, it MUST emit a versioned DELEGATION-DECISION event `{delegation_policy_id, policy_version, trigger_class, reason_codes[], spawned_context_refs[]}` as a #39 episode STAGE (record_kind stays CLOSED) -- every spawn as auditable as every selection. | Subagents are available in the orchestrator workflow AND >= ~3 recurring judgment-hygiene tasks have accumulated. Until then PB-1 is the guardrail -- do NOT build a router to a capability that does not exist yet. | D-0093 |
| PB-3 | Slim the over-budget hot docs (FANOUT_ORCHESTRATOR_HANDOFF 51/24, CURRENT_STATE 53/34, MODULE_ROADMAP 44/37) back under DOC_PROTOCOL budget (snapshot pre-slim per DOC_PROTOCOL s5; compress history to D-refs). The long-drifting "doc debt". | The i32 fold/close (handoff + CURRENT_STATE already named there) + the next MODULE_ROADMAP touch; OR forced by PB-1 once it lands. | D-0093 |
| PB-4 | AUDIT_PIPELINE increment (D-0101): consult `research/2026-08-05-audit-pipeline-target.md` (the staged A0-A5 target; promotes to `core-docs/AUDIT_PIPELINE.md` at tier A1); when a coding lane is spare, scope the next increment as ONE unit (docs:[], exclusive widget/module area, normal dev.ship + fold); the target doc's cadence header (last_reviewed/review_due/current_tier/next_increment) is the machine-checkable state. R-1 stage-trace on the router is the standing A0 invariant (born instrumented). NON-DISPLACING: the rehearsal/tier1-flip, the P0-1 suite/action-authz freeze, the #40 unit-2/3 sequencing, and PB-3 always outrank increments. | Every wave scoping: is review_due (i39, = last_reviewed i35 +4) reached OR a tier-gate flipped (router shipped w/ R-1 / #42 wired into #40 / i40 report done / PB-2 opened) OR a new artifact class appeared? If a lane is spare, scope it; else bump review_due 1-2 + record why (the cadence bends, never silently drops). | D-0101 |

## Closed

_(none yet)_
