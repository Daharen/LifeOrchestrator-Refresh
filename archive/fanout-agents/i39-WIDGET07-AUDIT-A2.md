# FANOUT_AGENT_003 -- READY

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i39 (plan `fo-39-df2e3a67`)
- **Lane:** CODING (CPU)
- **Worker id / label:** `WIDGET07-AUDIT-A2-i39` -- NEW widgets/07 audit-pipeline tier A2 (read-only)
- **Module/area (exclusive):** `widgets/07-audit-timeline-tournament` (NEW; name ratifiable)
- **GPU:** false
- **Docs:** `[]`
- **Convenience copy of the full emitted prompt:** `modules/30-orchestrate-fanout/runtime/artifacts/2fcdbfb0-ff94-48d2-9d81-dc0d028a0212/workers/worker-WIDGET07-AUDIT-A2-i39.prompt.md`

## Mission
The audit-pipeline tier A2 prerequisites are MET (the router shipped WITH R-1 stage-traces i37; #42 was wired into #40 i38), so the cadence authorizes the A2 read-only increment in a spare coding lane (PB-4). Build a STRICTLY READ-ONLY native WinForms renderer -- the s2.6 tool-selection **tournament** pane + the s2.1 cross-context **omniscient stitched timeline**. It trails the build by one tier and makes a GATE cheaper to verify; it does not chase total comprehension. `non_execution:true` holds; it enables no action; it holds NO lease while a human deliberates.

## Unit (self-contained)
EXCLUSIVE to `widgets/07-audit-timeline-tournament`; `docs:[]`; CPU; **NO skill.json** (a widget, like widgets/05 and widgets/06 -- OMIT `skill_id`/`skill_dir`). STRICTLY READ-ONLY: renders EXISTING artifacts, writes NOTHING outside its own runtime dir.

**READ FIRST (governing, do not edit):** `research/2026-08-05-audit-pipeline-target.md` (s2.6 tournament, s2.1 REVEAL/omniscient timeline, s2.7 delegation-trigger vocabulary [FUTURE], s3 binding principles, s4 tier A2 deliverables+acceptance, s6 anti-spiral guardrails) + `research/2026-08-05-interpretability-audit-surface-scoping.md` + `widgets/05-provenance-map` + `widgets/06-compile-trace-console` (the SHIPPED read-only native-WinForms siblings -- MATCH their `launch.bat` + STA SelfTest + strictly-read-only pattern) + `core-docs/CONTEXT_PACKET_CONTRACT.md` (s9 the R-1 `routing_stage_trace`; s6 identity) + the #37 selpol trace shape (`ranked[]`/`reason_codes[]`/`stages[]`).

**BUILD (tier A2 read-only slice).** A native WinForms console (double-click `launch.bat`; native per D-0038):
- **TOURNAMENT pane (s2.6):** render the staged skill/module selection as elimination rounds with per-stage COUNTS + REASON CODES over the router R-1 `routing_stage_trace` (#40 0.8.0+) + the eligibility/selpol stages (classification -> semantic retrieval -> rerank -> preflight -> deterministic plan validation: accepted, or REJECTED with the failed checks named). Counts MUST RECONCILE with the underlying stage traces.
- **CROSS-CONTEXT OMNISCIENT TIMELINE (the s2.1 REVEAL control):** a stitched timeline across contexts from episodes (#39) + plans (`modules/30-orchestrate-fanout/runtime/plans`) + `state_version` chains (#42) + batons (when present; render gracefully when absent). One wave renders end-to-end.
- **OUT OF SCOPE (record as A2 follow-ons, do NOT build):** the ride-along PAUSE / gateway hold hook (s2.2) -- it enters/pauses the pipeline + touches #7, so it is design-first + red-team-gated per s6; and delegation-tree possession (s2.7) -- no local coordinator exists yet.

**ACCEPTANCE (audit-target s4 A2 gates):** stitch a REAL wave end-to-end with ZERO lease-window violations (it holds NO lease); the timeline renders a full wave; tournament counts RECONCILE with the stage traces; byte-identical re-render of a fixed artifact; renders REAL artifacts (a real #40 0.8.0/0.9.0 routed packet's `routing_stage_trace` + real episodes/plans/state_version); the i33 diagnostic-array sanitization is HONORED (no cross-ns identifying metadata surfaced); WRITES NOTHING outside `widgets/07`'s own runtime dir (assert). A native STA SelfTest (widgets/05/06 style: `LAYOUT_OK` + `READONLY` + render-a-real-artifact). A human live-GUI confirm is an ACCEPTED OPEN follow-on (D-0064) -- ship SelfTest-green + FLAG it pending; do not block.

**CONSTRAINTS.** READ-ONLY -- no model calls, no pipeline pause, no lease held while deliberating. Do NOT modify #40/#39/#42/#30/#43 or any core-doc. Match the widgets/05/06 native pattern.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order (this unit: **git** only); release on exit/abort.
- Do ONE unit; never touch modules/areas outside `widgets/07-audit-timeline-tournament`; `docs:[]`.
- Gate off-machine FIRST where possible + the STA SelfTest on the box; ship via `exec-job.sh devship` (NEW widget -- OMIT `skill_id`/`skill_dir`; AST + tests FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-39-df2e3a67 -WorkerId WIDGET07-AUDIT-A2-i39 -State done` + a plain measured summary (negative results are first-class).

## Verification
The panes built; the tournament reconciliation proof; the timeline real-artifact render proof; the writes-nothing-outside-runtime assertion; the STA SelfTest counts; the OPEN human live-GUI confirm follow-on.

## Report-back record (ORCHESTRATOR fills from `plans/fo-39-df2e3a67/reports/` before archiving)
_pending._
