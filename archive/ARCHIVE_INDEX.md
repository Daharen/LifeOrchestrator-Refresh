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
