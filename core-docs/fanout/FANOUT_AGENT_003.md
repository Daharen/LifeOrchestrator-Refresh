# FANOUT_AGENT_003 -- i38 wave (plan fo-38-2b1efe73)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i38 (plan id `fo-38-2b1efe73`)
- **Lane:** CODING (CPU)
- **Worker id / label:** `WIDGET06-COMPILE-TRACE-i38`
- **Module/area (exclusive):** `widgets/06-compile-trace-console`
- **GPU:** false
- **Docs:** `[]`

## Mission
Build Widget 06 Compile Trace Console (audit-pipeline tier A1, PB-4): a STRICTLY READ-ONLY native WinForms renderer over compile/eval artifacts (s2.1 panes 1-4,6 -- the 4 packet regions + trust banners; #37 selpol ranked[]/reason_codes[]/stages[] + the R-1 router stage-trace now that it EXISTS; retrieval plan/stage lineage + V3 completeness; consumer_profile; #42 state_version) + the s2.5a compile-layer counterfactual runner (one varied input, ZERO model calls). NO skill.json; matches the widgets/05 native pattern. Governs: research/2026-08-05-audit-pipeline-target.md (tier A1).

## Unit (the full worker prompt)
Dispatch a fresh Cowork session with the one folder grant (`C:\Users\just_\LifeOrchestrator-Refresh`) and execute the unit below. The EXACT `orchestrate.fanout`-emitted prompt (with the res.lease acquire/release commands) is delivered as a file and lives at `modules/30-orchestrate-fanout/runtime/artifacts/c7243036-624d-4819-b5dd-89bf3c024aa8/workers/worker-WIDGET06-COMPILE-TRACE-i38.prompt.md` -- if dispatched by prompt-paste, paste that file; the unit text here is the same mission.

BUILD a NEW read-only widget widgets/06-compile-trace-console -- the "Compile Trace Console" (audit-pipeline tier A1). EXCLUSIVE to widgets/06-compile-trace-console; docs:[]; CPU (no GPU); NO skill.json (a widget, like widgets/05 -- OMIT skill_id/skill_dir). STRICTLY READ-ONLY: it renders existing artifacts and writes NOTHING outside its own runtime dir. non_execution:true holds; it enables no action.

READ FIRST (governing, do not edit): research/2026-08-05-audit-pipeline-target.md (the tier ladder; s2.1 the six panes/four controls, s2.5a the compile-layer counterfactual, s2.9 provenance, s3 the binding principles, s4 tier A1 deliverables+acceptance, s6 anti-spiral guardrails) + research/2026-08-05-interpretability-audit-surface-scoping.md (the R-1 + Unit A/B entry vehicle) + widgets/05-provenance-map (the shipped read-only native-WinForms sibling -- MATCH its launch.bat + STA SelfTest + strictly-read-only pattern) + core-docs/CONTEXT_PACKET_CONTRACT.md (the 4 packet regions + s9 R-1 stage-trace + s6 identity) + the #37 selpol trace shape (ranked[]/reason_codes[]/stages[]).

BUILD (tier A1 = s2.1 panes 1-4,6 + the s2.5a counterfactual runner). A native WinForms console (double-click launch.bat, native by default per D-0038) rendering REAL compile/eval artifacts:
- Pane 1 TASK TIMELINE (the compile's stages in order).
- Pane 2 EXACT MODEL VIEW: the context_packet's FOUR regions (control_plane / evidence / working_memory / consumer_profile) each with a TRUST BANNER naming its trust class + source; the packet's own mapping table names each source.
- Pane 3 RETRIEVAL + SELECTION TRACE: the #37 selpol ranked[]/reason_codes[]/stages[] AND the R-1 router stage-trace (evaluation_hooks.routing_stage_trace -- now that it EXISTS, #40 0.8.0) + retrieval plan/stage lineage + V3 completeness fields.
- Pane 4 RULE / EXCEPTION STACK: fired/excluded/overridden rules with inputs+outputs (e.g. current_only FIRED; superseded candidate EXCLUDED hard_filter_superseded; historical_as_of override).
- Pane 6 TOKEN + STATE LEDGER: the budget ledger + the consumer_profile ledger + #42 state_version.
- (Pane 5 tool+sub-agent tree is OUT -- deferred to A2, no delegation yet.)
- The s2.5a COMPILE-LAYER COUNTERFACTUAL RUNNER: re-run the compile on the SAME pinned snapshot with ONE varied input (channel mask / selection-policy version / effective namespace set / temporal_intent / budget / an excluded record_version_id / a synopsis-staleness toggle / a state_version rollback) and DIFF the two packets. ZERO model calls -- deterministic re-compile only.

ACCEPTANCE (the audit-target s4 A1 gates): byte-identical re-render of a fixed artifact; renders REAL fold/rehearsal artifacts (drive it with a real #40 0.8.0/0.9.0 packet + the i36 rehearsal report + a fold smoke output); a counterfactual/ablation line reconciles with #37's hybrid attribution; the i33 diagnostic-array sanitization is HONORED (no cross-ns identifying metadata surfaced); it WRITES NOTHING outside widgets/06's own runtime dir (assert). A native STA SelfTest (widgets/05 style: LAYOUT_OK + READONLY + a render-a-real-packet check) is the off-GUI gate.

HARD SCOPE. READ-ONLY -- no compile of new inputs beyond the deterministic counterfactual re-compile, no model, NO lease held while a human deliberates (pause/possession is A2+, NOT this unit). Do NOT modify #40/#37/#42/#43 or any core-doc. A human live-GUI confirm is an ACCEPTED OPEN follow-on (D-0064) -- ship the SelfTest-green widget + FLAG the live-GUI confirm as pending; do not block on it.

GATES.
- Off-machine FIRST where possible (the pure-logic artifact readers + the counterfactual differ as a cloud python/pwsh gate) + the STA SelfTest on the box. Ship via exec-job.sh devship (NEW widget -- OMIT skill_id/skill_dir; AST + tests FAIL-CLOSED; named files only). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.

REPORT (`-Action report ... -State done` + plain summary): the panes built, the counterfactual runner's varied-input set, the real-artifact render proof, the writes-nothing-outside-runtime assertion, the SelfTest counts, and the OPEN human live-GUI confirm follow-on. Negative/partial results are first-class.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release in reverse. No GPU this wave (CPU lane) -- take `git` for the commit only.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-38-2b1efe73 -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
Native STA SelfTest green (widgets/05 style: LAYOUT_OK + READONLY + a render-a-real-packet check); byte-identical re-render of a fixed artifact; renders a REAL #40 0.8.0/0.9.0 packet + the i36 rehearsal report + a fold smoke output; a counterfactual/ablation line reconciles with #37 hybrid attribution; the i33 sanitization is honored; WRITES NOTHING outside widgets/06's own runtime dir (assert). Human live-GUI confirm = an ACCEPTED OPEN follow-on (D-0064) -- ship SelfTest-green + flag it pending.

## Report-back record (ORCHESTRATOR fills from `plans/fo-38-2b1efe73/reports/` before archiving)
_empty -- filled at fold._
