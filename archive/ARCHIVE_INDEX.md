# ARCHIVE_INDEX -- what is in archive/ and why

Append one line per addition (path | what it was | why archived | date | D-ref). Rules:
`core-docs/DOC_PROTOCOL.md` section 7. Nothing here is ever edited; recovery = copy OUT.

## handoffs/

- `2026-07-28-ORCHESTRATOR_HANDOFF.md` | dated session handoff (post-iterations 7-8, HEAD c1763c1) | superseded; single-live-handoff rule | 2026-07-29 | D-0066
- `2026-07-29-ORCHESTRATOR_HANDOFF.md` | dated session handoff (post-iterations 10-11, HEAD 206b2dd; existed only as the Project mirror `claude/ORCHESTRATOR_HANDOFF_2026-07-29.md`) | superseded; single-live-handoff rule | 2026-07-29 | D-0066
- `2026-07-29-ORCHESTRATOR_HANDOFF-expanded.md` | dated handoff introducing the 4-lane expanded wave model (post-iterations 12-13, HEAD f3c1ec7) | content folded into FANOUT_ORCHESTRATOR_HANDOFF.md sections 3-4 | 2026-07-29 | D-0066
- `2026-07-29-HANDOFF-go-forward-map.md` | the enduring `core-docs/HANDOFF.md` "go-forward map" | absorbed: locations + job-runner -> FANOUT_ORCHESTRATOR_HANDOFF sections 6-7; disclaimers/known-issues -> CURRENT_STATE; portability spec -> MODULE_ROADMAP | 2026-07-29 | D-0066
- `2026-07-29-FANOUT_ORCHESTRATOR_HANDOFF-pre-D0066.md` | the pre-consolidation live handoff (iteration-by-iteration prose) | snapshot before the D-0066 rewrite; iteration detail compressed to the ledger | 2026-07-29 | D-0066

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

(empty -- used worker briefs land here as `i<N>-<slot-id>.md`)
