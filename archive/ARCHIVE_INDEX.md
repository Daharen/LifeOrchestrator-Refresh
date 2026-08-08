# ARCHIVE_INDEX -- what is in archive/ and why

Append one line per addition (path | what it was | why archived | date | D-ref). Rules:
`core-docs/DOC_PROTOCOL.md` section 7. Nothing here is ever edited; recovery = copy OUT.

## handoffs/

- `2026-07-28-ORCHESTRATOR_HANDOFF.md` | dated session handoff (post-iterations 7-8, HEAD c1763c1) | superseded; single-live-handoff rule | 2026-07-29 | D-0066
- `2026-07-29-ORCHESTRATOR_HANDOFF.md` | dated session handoff (post-iterations 10-11, HEAD 206b2dd; existed only as the Project mirror `claude/ORCHESTRATOR_HANDOFF_2026-07-29.md`) | superseded; single-live-handoff rule | 2026-07-29 | D-0066
- `2026-07-29-ORCHESTRATOR_HANDOFF-expanded.md` | dated handoff introducing the 4-lane expanded wave model (post-iterations 12-13, HEAD f3c1ec7) | content folded into FANOUT_ORCHESTRATOR_HANDOFF.md sections 3-4 | 2026-07-29 | D-0066
- `2026-07-29-HANDOFF-go-forward-map.md` | the enduring `core-docs/HANDOFF.md` "go-forward map" | absorbed: locations + job-runner -> FANOUT_ORCHESTRATOR_HANDOFF sections 6-7; disclaimers/known-issues -> CURRENT_STATE; portability spec -> MODULE_ROADMAP | 2026-07-29 | D-0066
- `2026-07-29-FANOUT_ORCHESTRATOR_HANDOFF-pre-D0066.md` | the pre-consolidation live handoff (iteration-by-iteration prose) | snapshot before the D-0066 rewrite; iteration detail compressed to the ledger | 2026-07-29 | D-0066
- `2026-07-29-FANOUT_ORCHESTRATOR_HANDOFF-i14.md` | the live handoff snapshotted before the i14 close-out rewrite (HEAD 74d6c86) | snapshot-then-rewrite each orchestrator session (DOC_PROTOCOL s5) | 2026-07-29 | D-0067
- `2026-07-30-FANOUT_ORCHESTRATOR_HANDOFF-i15.md` | the live handoff snapshotted before the i15 close-out rewrite (HEAD 8c1da2e) | snapshot-then-rewrite each orchestrator session (DOC_PROTOCOL s5) | 2026-07-30 | D-0068
- `2026-07-30-FANOUT_ORCHESTRATOR_HANDOFF-i16.md` | the live handoff snapshotted before the i16 close-out rewrite (HEAD d106ed7) | snapshot-then-rewrite each orchestrator session (DOC_PROTOCOL s5) | 2026-07-30 | D-0069
- `2026-07-30-FANOUT_ORCHESTRATOR_HANDOFF-i17.md` | the live handoff snapshotted before the i17 close-out rewrite (HEAD 980dd6d) | snapshot-then-rewrite each orchestrator session (DOC_PROTOCOL s5) | 2026-07-30 | D-0070

## doc-snapshots/2026-07-29/

Pre-slim full snapshots taken before the D-0066 consolidation (byte-exact from disk at HEAD 6e27ba3):

- `CURRENT_STATE.md` | 159,958 bytes, with all `[prior]` accretion chains | slimmed to budget | 2026-07-29 | D-0066
- `MODULE_ROADMAP.md` | 75,366 bytes, per-module build narratives | slimmed to budget | 2026-07-29 | D-0066
- `TOOL_MODEL_REGISTRY.md` | 91,742 bytes, narrative registry entries | slimmed to budget | 2026-07-29 | D-0066
- `REVIEW_QUEUE.md` | 29,400 bytes, ten sequential producer narratives | slimmed to a producer/consumer table | 2026-07-29 | D-0066
- `START_HERE.md` | 7,982 bytes, with the stale ACTIVE-WORK banner | banner replaced by routing; checklist -> DOC_PROTOCOL | 2026-07-29 | D-0066

## doc-snapshots/2026-08-03/

- `DECISION_LOG_INDEX.md` | 25,605 bytes, one detailed paragraph per decision (had become a second decision log) | reduced to routing-only labels + a maintenance-rules header | 2026-08-03 | DOC_PROTOCOL s2

## drafts/

- `iter11-stage1-DRAFT.md` | the READY warm-pool Stage-1 dispatch package (existed only as a Project doc; filename predates the iter-11 renumbering) | renumbered + reformatted into `core-docs/fanout/FANOUT_AGENT_001.md` | 2026-07-29 | D-0066

## fanout-agents/

- `i14-WMP-stage1.md` | the filled GPU-lane brief (warm-pool Stage-1, mechanism C) dispatched in i14 (plan fo-14-5ea064b6) | used brief archived on wave completion | 2026-07-29 | D-0067
- `i14-PORT-setup.md` | the filled CPU-lane brief (portability / new-machine bring-up) dispatched in i14 | used brief archived on wave completion | 2026-07-29 | D-0067
- `i14-WAVE-dash.md` | the filled coding-lane brief (fan-out wave dashboard, widgets/04) dispatched in i14 | used brief archived on wave completion | 2026-07-29 | D-0067
- `i15-WMP-stage11.md` | the filled GPU-lane brief (warm-pool Stage-1.1 hardening) dispatched in i15 (plan fo-15-27a03513) | used brief archived on wave completion | 2026-07-30 | D-0068
- `i15-PORT-wire.md` | the filled CPU-lane brief (portability follow-ons: staging-plan confirm + resolver shim) dispatched in i15 | used brief archived on wave completion | 2026-07-30 | D-0068
- `i15-WAVE-confirm.md` | the filled coding-lane brief (widget-04 live-GUI confirm + polish) dispatched in i15 | used brief archived on wave completion | 2026-07-30 | D-0068
- `i16-WMP-supervisor.md` | the filled GPU-lane brief (warm-pool durable Job-Object gateway supervisor) dispatched in i16 (plan fo-16-f125365c) | used brief archived on wave completion | 2026-07-30 | D-0069
- `i16-PORT-shim.md` | the filled CPU-lane brief (portability resolver shim into doc.io #20) dispatched in i16 | used brief archived on wave completion | 2026-07-30 | D-0069
- `i16-MEDIA-decompose.md` | the filled coding-lane brief (NEW module #32 media.decompose) dispatched in i16 | used brief archived on wave completion | 2026-07-30 | D-0069
- `i17-GEN-image-sd35.md` | the filled GPU-lane brief (SD 3.5 Medium fp16 tier for gen.image #23) dispatched in i17 (plan fo-17-3a115347) | used brief archived on wave completion | 2026-07-30 | D-0070
- `i17-PORT-interp.md` | the filled CPU-lane brief (config-resolvable Python interpreter path for #15/#16) dispatched in i17 | used brief archived on wave completion | 2026-07-30 | D-0070
- `i17-TRACK-objects.md` | the filled coding-lane brief (NEW module #33 track.objects) dispatched in i17 | used brief archived on wave completion | 2026-07-30 | D-0070
- `i21-RESLEASE-R1b-consumers-live.md` | the filled GPU-lane brief (R1b CONSUMER wave: lease-split adoption + real evictor + live-GPU proof) dispatched in i21 (plan fo-21-61c7597b) | used brief archived on wave completion | 2026-07-31 | D-0076
- `2026-07-31-FANOUT_ORCHESTRATOR_HANDOFF-i21.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i21 close-out (before the i22 rewrite) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-07-31 | D-0076
- `i22-TRACK-STABLE-i22.md` | the filled CPU-lane brief (track.objects #33 stable-identity refinement) dispatched in i22 (plan fo-22-d2c492e7) | used brief archived on wave completion | 2026-07-31 | D-0077
- `i22-VIDEO-TIMELINE-i22.md` | the filled coding-lane brief (NEW module #34 video.timeline) dispatched in i22 (plan fo-22-d2c492e7) | used brief archived on wave completion | 2026-07-31 | D-0077
- `2026-07-31-FANOUT_ORCHESTRATOR_HANDOFF-i22.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i22 close-out (before the i23 rewrite) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-07-31 | D-0077
- `2026-08-01-FANOUT_ORCHESTRATOR_HANDOFF-i25.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i25 close-out (before the i26 rewrite; HEAD 98c2cd7) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-08-01 | D-0083
- `i28-EPISODE-CONFORM.md` | the filled CPU-lane brief (episode.record #39 0.1.1 conformance to MEMORY_CONTRACT Amendment A1) dispatched in i28 (plan fo-28-45c4ad65) | used brief archived on wave completion | 2026-08-02 | D-0085
- `2026-08-02-FANOUT_ORCHESTRATOR_HANDOFF-i27-D0084.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i27/D-0084 state (before the i28 rewrite; HEAD b57d328) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-08-02 | D-0085
- `i30-CONTEXT-COMPILER.md` | the filled coding-lane brief (context.compiler #40 0.1.0->0.2.0, context_packet/0.2) dispatched in i30 (plan fo-30-dd453156) | used brief archived on wave completion | 2026-08-03 | D-0088
- `i30-SELECTION-POLICY.md` | the filled CPU-lane brief (retrieval.eval #37 0.2.0->0.3.0, the selpol_rrf_v1 selection-policy library) dispatched in i30 | used brief archived on wave completion | 2026-08-03 | D-0088
- `i30-SKILL-SUMMARY.md` | the filled CPU-lane brief (skill.card #41 0.1.0->0.2.0, A3 record_kind skill->summary) dispatched in i30 | used brief archived on wave completion | 2026-08-03 | D-0088
- `2026-08-03-FANOUT_ORCHESTRATOR_HANDOFF-i29.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i29/D-0086 state (before the i30 rewrite; HEAD a4830f4) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-08-03 | D-0088
- `2026-08-03-FANOUT_ORCHESTRATOR_HANDOFF-i30.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i30/D-0088 state (before the i31 rewrite; HEAD 5af613d) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-08-03 | D-0091
- `i31-SELECTION-POLICY-SETTLE.md` | the filled CPU-lane brief (context.compiler #40 0.2.0->0.3.0: retire selpol_reference.py + import #37 canonical selpol_rrf_v1, P1-1/D-0089) dispatched in i31 (plan fo-31-eca37c08) | used brief archived on wave completion | 2026-08-03 | D-0091
- `i32-ARTIFACT-SEARCH-TIER0.md` | the filled Lane-A brief (artifact.search #36 0.2.0->0.3.0; Tier-0 A4 namespace/current_only + reserved node/working/edges) dispatched in i32 (plan fo-32-0fb25203) | used brief archived at the i33 re-scoping | 2026-08-04 | D-0092
- `i32-RETRIEVAL-EVAL-SELPOL-TIER0.md` | the filled Lane-B brief (retrieval.eval #37 selpol 1.0->1.1 / eval 0.3->0.4; Tier-0 namespace/current_only/supersession stages) dispatched in i32 (plan fo-32-0fb25203) | used brief archived at the i33 re-scoping | 2026-08-04 | D-0092
- `i32-CONTEXT-COMPILER-TIER0.md` | the filled Lane-C brief (context.compiler #40 0.3->0.4; namespace plumbing + query-classification + working_memory region) dispatched in i32 (plan fo-32-0fb25203) | used brief archived at the i33 re-scoping | 2026-08-04 | D-0092
- `2026-08-04-FANOUT_ORCHESTRATOR_HANDOFF-i32-i33.md` | snapshot of the FANOUT_ORCHESTRATOR_HANDOFF at the i32-complete/i33-open state (before the i33 rewrite; HEAD 41410d8) | handoff snapshot per DOC_PROTOCOL section 5 | 2026-08-04 | D-0096
- `i33-ARTIFACT-SEARCH-NSCLOSURE.md` | the filled Lane-A brief (artifact.search #36 0.3.0->0.4.0; namespace CLOSURE + candidate-independent supersession + hardened gate tests, A5/D-0096) dispatched in i33 (plan fo-33-d7b55e46) | used brief archived at the i34 re-scoping | 2026-08-04 | D-0096
- `i33-RETRIEVAL-EVAL-NSCLOSURE.md` | the filled Lane-B brief (retrieval.eval #37 eval 0.4->0.5 / selpol 1.1->1.2; the canonical ns_permitted + classifier_policy owner) dispatched in i33 (plan fo-33-d7b55e46) | used brief archived at the i34 re-scoping | 2026-08-04 | D-0096
- `i33-CONTEXT-COMPILER-NSCLOSURE.md` | the filled Lane-C brief (context.compiler #40 0.4.0->0.5.0; effective-namespace closure + all-object scope-check + query_class/temporal_intent split) dispatched in i33 (plan fo-33-d7b55e46) | used brief archived at the i34 re-scoping | 2026-08-04 | D-0096
- `i31-SELECTION-POLICY-SETTLE-SHIP-STATE.md` | the i31 FANOUT_AGENT_002 SHIP-STATE (context.compiler #40 0.3.0, selpol settle) left stale in the live core-docs/fanout/ dir | moved to archive (stale-file cleanup) at the i34 re-scoping | 2026-08-04 | D-0091
- `i23-SHIP-STATE.md` | the i23 SUPERVISOR-HARDENING wave ship-state (model.gateway #7 0.6.0, d289ba9) | committed to archive (was untracked on disk) at the i34 mirror-hygiene cleanup | 2026-08-04 | D-0078
- `i25-SHIP-STATE.md` | the i25 WAVE-1 memory-substrate ship-state (#35/#36/#37 0.1.0) | committed to archive (was untracked) at the i34 cleanup | 2026-08-04 | D-0082
- `i27-SHIP-STATE.md` | the i27 WAVE-2 memory-records ship-state (#36 0.2 + #38 + #39) | committed to archive (was untracked) at the i34 cleanup | 2026-08-04 | D-0084
- `i28-SHIP-STATE.md` | the i28 CONTRACT-SETTLE ship-state (MEMORY_CONTRACT A1 + #39 0.1.1) | committed to archive (was untracked) at the i34 cleanup | 2026-08-04 | D-0085
- `RESLEASE-R1a-split-SHIP-STATE.md` | the i18 res.lease 0.2.0 ship-state | preserved from the stale Project mirror to disk archive at the i34 cleanup | 2026-08-04 | D-0072
- `RESLEASE-R1b-consumers-i19-SHIP-STATE.md` | the i19 res.lease 0.3.0 + red-team fold ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0073
- `RESLEASE-R1bprime-i20-SHIP-STATE.md` | the i20 res.lease 0.4.0 primitive-hardening ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0075
- `RESLEASE-R1b-consumers-i21-SHIP-STATE.md` | the i21 R1b consumer + live-GPU proof ship-state (#7 0.5.0) | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0076
- `TRACK-STABLE-i22-SHIP-STATE.md` | the i22 track.objects #33 0.2.0 ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0077
- `VIDEO-TIMELINE-i22-SHIP-STATE.md` | the i22 video.timeline #34 0.1.0 ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0077
- `VIDEO-TIMELINE-i22-FOLD-ADDENDUM.md` | the i22 video.timeline 0.1.1 orchestrator fold addendum | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0077
- `RETRIEVAL-QUALITY-i29-SHIP-STATE.md` | the i29 retrieval.eval #37 0.2.0 ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0086
- `SELECTION-POLICY-i30-SHIP-STATE.md` | the i30 retrieval.eval #37 0.3.0 selpol_rrf_v1 ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0088
- `SKILL-SUMMARY-i30-SHIP-STATE.md` | the i30 skill.card #41 0.2.0 (A3 skill->summary) ship-state | preserved from the stale Project mirror at the i34 cleanup | 2026-08-04 | D-0088
- `2026-08-04-FANOUT_ORCHESTRATOR_HANDOFF-i33.md` | snapshot of the handoff at the i33-in-flight state (before the D-0097 close rewrite; from git 33a8158^) | backfilled the missing DOC_PROTOCOL s5 snapshot at the i34 cleanup | 2026-08-04 | D-0097
- `2026-08-05-FANOUT_ORCHESTRATOR_HANDOFF.md` | snapshot of the handoff at the i34-in-flight state (before the D-0099 close rewrite, 63->28 KB) | DOC_PROTOCOL s5 handoff snapshot at the i34 close | 2026-08-05 | D-0099
- `i34-FANOUT_AGENT_001.md` | the used i34 Lane A brief (HIERARCHY-BUILDER-i34; #36 artifact.search 0.5.0) | DOC_PROTOCOL s6 used-brief archive at the i34 close | 2026-08-05 | D-0099
- `i34-FANOUT_AGENT_002.md` | the used i34 Lane B brief (HIERARCHY-EVAL-i34; #37 retrieval.eval eval 0.6.0) | DOC_PROTOCOL s6 used-brief archive at the i34 close | 2026-08-05 | D-0099
- `i34-FANOUT_AGENT_003.md` | the used i34 Lane C brief (SHORTLIST-DESCEND-i34; #40 context.compile 0.6.0) | DOC_PROTOCOL s6 used-brief archive at the i34 close | 2026-08-05 | D-0099

- 2026-08-05 -- `archive/handoffs/2026-08-05-FANOUT_ORCHESTRATOR_HANDOFF-i35-close.md` -- the pre-i35-close handoff snapshot (D-0100).
- 2026-08-05 -- `archive/fanout-agents/i35-HIERARCHY-PORT.md` + `i35-REHEARSAL-HARNESS.md` -- the i35 filled worker briefs (plan fo-35-0a5bf334).

## mandates/

- `mandate-01-i32-i40.md` | the sunsetted process-hygiene mandate 01 (opened i32, D-0094; header finalized 40/0/SUNSET) | s4 self-archive at report delivery; the durable record is `core-docs/research/2026-08-06-process-mandate-01-report.md`; the live doc was replaced in place by the LICENSED mandate 02 | 2026-08-06 | D-0110

## doc-snapshots/2026-08-06/ (PB-3 slim, i40)

- `doc-snapshots/2026-08-06/CURRENT_STATE.md` | the pre-slim CURRENT_STATE (63,108 B, 185% of budget) | PB-3 hot-doc slim at its i40 deadline (DOC_PROTOCOL s2/s5; mandate-02 M2-B); slimmed to 32,532 B | 2026-08-06 | D-0110
- `doc-snapshots/2026-08-06/MODULE_ROADMAP.md` | the pre-slim MODULE_ROADMAP (48,983 B, 132% of budget; widgets/05-06 still marked Proposed, memory modules #35-#43 rowless) | PB-3 slim + per-module currency (#35-#43 rows added, widgets 05/06/07 current) ; slimmed to 28,594 B | 2026-08-06 | D-0110

- `handoffs/2026-08-06-FANOUT_ORCHESTRATOR_HANDOFF-i40-close.md` | the pre-i40-close live handoff (47,286 B, 197% of budget; i39-era TL;DR/menus) | DOC_PROTOCOL s5 snapshot before the i40 close rewrite (slimmed under the 24 KB budget) | 2026-08-06 | D-0112
- `fanout-agents/i40-FANOUT_AGENT_002.md` | the used i40 Lane B brief (M37-RECONCILE-i40; #37 0.8.1, PB-5) | DOC_PROTOCOL s6 used-brief archive at the i40 close | 2026-08-06 | D-0112
- `fanout-agents/i40-FANOUT_AGENT_003.md` | the used i40 Lane A brief (P01-EXACT-CLOSURE-43-i40; #43 0.4.0 exact closures) | DOC_PROTOCOL s6 used-brief archive at the i40 close | 2026-08-06 | D-0112
- `handoffs/2026-08-07-FANOUT_ORCHESTRATOR_HANDOFF-i41-close.md` | the pre-i41-close live handoff (23,931 B; i40-close TL;DR + the new s12 model tiering) | DOC_PROTOCOL s5 snapshot before the i41 close rewrite | 2026-08-07 | D-0115
- `fanout-agents/i41-FANOUT_AGENT_003.md` | the used i41 Lane A brief (P01-R3-CLOSURE-43-i41; #43 0.5.0 round-3 closures; report-back filled) | DOC_PROTOCOL s6 used-brief archive at the i41 close | 2026-08-07 | D-0115
| archive/handoffs/2026-08-08-FANOUT_ORCHESTRATOR_HANDOFF-i42.md | the outgoing i41-shaped handoff snapshotted at the i42 close | 2026-08-08 | D-0117 |
| archive/fanout-agents/i42-M2A-DOCGATE.md | i42 Lane A brief (M2-A doc-gate) | 2026-08-08 | D-0117 |
| archive/fanout-agents/i42-P01-R4-CLOSURE-43.md | i42 Lane B brief (#43 0.6.0 round-4 closures) | 2026-08-08 | D-0117 |
| archive/handoffs/2026-08-08-FANOUT_ORCHESTRATOR_HANDOFF-i43-close.md | i43 handoff snapshot (pre-close) | 2026-08-08 | D-0120 |
| archive/handoffs/2026-08-08-FANOUT_ORCHESTRATOR_HANDOFF-i44.md | the outgoing i43-shaped live handoff snapshotted at the i44 close | 2026-08-08 | D-0121 |
| archive/handoffs/2026-08-08-FANOUT_ORCHESTRATOR_HANDOFF-i45.md | the outgoing i44-shaped live handoff snapshotted at the i45 close | 2026-08-08 | D-0122 |
| archive/fanout-agents/i45-003.md | i45 CODING-lane brief (LRAP-WIDGET08-i45; NEW widgets/08 Live-Run Audit Pathway) | 2026-08-08 | D-0122 |
