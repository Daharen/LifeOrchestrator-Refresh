# WORK ORDER - Widget 07: Audit Timeline + Tournament

- **id:** `widgets/07-audit-timeline-tournament` - **Phase:** B (Widget layer) #7 - **Status:** MVP (this session, i39)
- **Realizes:** the audit-surface program tier **A2** (the read-only slice: the s2.6 tool-selection tournament
  pane + the s2.1 cross-context omniscient stitched timeline). Brief: `core-docs/fanout/FANOUT_AGENT_003.md`
  (i39 plan `fo-39-df2e3a67`, worker `WIDGET07-AUDIT-A2-i39`). Governing design:
  `research/2026-08-05-audit-pipeline-target.md` s2.6 (tournament), s2.1 (REVEAL / omniscient timeline), s3
  (readers over artifacts; strictly read-only; leases outrank ergonomics), s4-A2 (deliverables + acceptance),
  s6 (anti-spiral guardrails) + `research/2026-08-05-interpretability-audit-surface-scoping.md`. Delivery per
  **D-0038** (native WinForms + `launch.bat`); architecture per the Widget 05/06 pattern (**D-0039 / D-0049 /
  D-0060 / D-0064**).

## Purpose

The A2 (stepping / stitched-visibility) altitude of the audit funnel, built as READERS only (the pause /
possession controls are A3+, design-first + red-team-gated). It answers two audit questions at bounded cost:
(1) "why did the staged tool/module selection keep or drop each candidate, and do the counts add up?" -- the
TOURNAMENT; (2) "what happened across every context in one wave, in order?" -- the cross-context TIMELINE. It
RENDERS artifacts the contracts + the fan-out runtime already mandate (the R-1 `routing_stage_trace`, the
selpol `stages[]`, the #30 plan/dispatch validation, #39 episodes, #42 `state_version` chains) -- ZERO new
instrumentation, ZERO new doc-upkeep. It trails the build by one tier and makes a GATE cheaper to verify.

## Scope (tight A2 read-only slice)

The TOURNAMENT pane (s2.6) + the OMNISCIENT stitched TIMELINE (s2.1). STRICTLY READ-ONLY over existing
artifacts; the render path writes NOTHING (the `runtime/` dir is reserved + write-guarded for a FUTURE
"new since last wave" marker only). Deterministic parses with **graceful degradation**: a malformed / missing
artifact becomes a VISIBLE FLAG, never a throw. It holds NO lease and defines NO pause point -> ZERO
lease-window violations by construction (the D-0055/56 wedge with a person as the orphan is structurally
impossible here).

**Non-goals (do NOT build):** any write to a doc / git / a runtime dir outside its own; executor jobs; model
calls; the ride-along PAUSE / gateway hold hook (s2.2 -- enters/pauses the pipeline + touches #7, so A2
records it as a follow-on: design-first + red-team-gated per s6); delegation-tree possession (s2.7 -- no local
coordinator exists yet); modifying `#40`/`#39`/`#42`/`#30`/`#43` or any core-doc. A brand-new widget -> **no
`skill.json`** (OMIT skill_id/skill_dir). Non-displacing: the memory sequencing + the P0-1 gate keep priority.

## Architecture (mirrors Widget 05/06)

- `AuditTimelineTournament.psm1` -- the WinForms-free driver core (the cloud gate tests it for real): the
  artifact readers (`Read-ContextPacket` in three carriers, `Read-FanoutPlan`, `Read-FanoutReport`,
  `Read-Episode`, `Read-WorkingState`); the tournament brackets (`Get-RouterTournament`,
  `Get-SelectionTournament`, `Get-PlanValidationTournament`, `Get-TournamentPane`) each with a machine
  RECONCILIATION proof; the timeline stitch (`Get-WaveEvents`, `Get-EpisodeEvents`, `Get-WorkingStateEvents`,
  `Get-StitchedTimeline`) with a deterministic total order; `Test-TraceSanitized` + `Test-TimelineSanitized`
  (i33 diagnostic-array closure + the no-content event allowlist); `ConvertTo-IsoUtc` (culture-stable
  timestamps); `Get-AuditModel` + `Format-AuditHeader`; the `Assert-UnderRuntime` write-guard (defense-in-depth
  -- the render path writes nothing). Defensive throughout: every source degrades to a well-formed shape + a
  flag, never a throw.
- `Show-AuditTimelineTournament.ps1` -- the thin STA WinForms shell: a toolbar (packet path + Browse; a wave
  path + Browse-wave; Refresh -- laid out from the toolbar's ACTUAL width in a Resize handler +
  `.GetNewClosure()`, the widget-04 lesson), a read-only header, and a TabControl (Tournament / Timeline /
  Flags) of monospace lists. `-SelfTest` builds + drives + disposes the form OFF-SCREEN and prints
  `SELFTEST_*_OK`.
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-AuditTimelineTournament.ps1 %*`.

## Data contracts (consumed, read-only)

- `lifeorch.context_packet/0.2` (a `#40` 0.8.0/0.9.0 packet) -- `evaluation_hooks.routing_stage_trace` (R-1;
  the router bracket), `evaluation_hooks.stages` raw_retrieval/post_filter/packet + `retrieved[]` (the
  selection bracket), `identity.namespace_closure` (sanitization). CONTEXT_PACKET_CONTRACT s6/s9.
- `lifeorch.fanout.plan/0.1` (`#30` plan.json) -- workers / dispatch_now / queued / conflicts (the
  plan-validation bracket + the wave timeline).
- `lifeorch.fanout.report/0.1` (`#30` worker reports) -- worker_id / state / reported_at_utc (the wave
  timeline + the dispatched-vs-reported reconciliation).
- `lifeorch.episode/0.1` (a `#39` episode record) -- valid_from/to + stage_sequence (the episode context lane).
- a `#42` working-state envelope (MEMORY_CONTRACT s1, record_kind=working) -- task_id / state_version /
  parent_state_version / lifecycle_state (the state_version chain lane); also read from a hydrated packet's
  working_memory region when present.

## Test plan

Dual-mode `tests/Invoke-AuditTimelineTournamentTests.ps1` -- cloud gate **81/0/3** (Linux, over committed REAL
fixtures: a real routed packet with a 3-stage router trace, a flat packet, the REAL i38 wave = plan + its 3
reports, a real #39 episode, a real #42 working-state) covering the readers, the three tournament brackets +
reconciliation (incl. a corrupted-count MISMATCH catch), the wave stitch + cross-context episode/state events +
the deterministic order + the dispatched-vs-reported reconciliation, the i33 sanitization (+ an injected
cross-ns key + an injected episode body/snippet that never leaks), byte-identical re-render, culture-stable ISO
timestamps, the read-only guarantees, and graceful degradation; `-Live` adds launch.bat shape + the WinForms
`-SelfTest` markers + a real on-box wave render.

## Ship

Through the job-runner (`exec-job.sh devship`): sha-verify the shipped files, AST-parse + ASCII-guard, run the
tests `-Live`, commit exactly the `widgets/07-audit-timeline-tournament/` files under the `git` lease with
trailers (CPU lane -- git lease only, no GPU). A brand-new widget -> no `skill.json`. VERIFY the real HEAD via
native git (D-0072). Assert 0 UNMANAGED orphans. **A human live-GUI confirm is an ACCEPTED OPEN follow-on
(D-0064)** -- ship the SelfTest-green widget + FLAG the confirm as pending; do not block on it.

## Acceptance (audit-target s4 A2)

Stitch a REAL wave end-to-end with ZERO lease-window violations (it holds NO lease); the timeline renders a
full wave; tournament counts RECONCILE with the underlying stage traces; byte-identical re-render of a fixed
artifact; renders REAL artifacts (a real `#40` routed packet's `routing_stage_trace` + real episodes / plan /
state_version); the i33 diagnostic-array sanitization is honored (the router trace is channel-only; no cross-ns
identifying metadata surfaced); WRITES NOTHING outside the widget's own `runtime/` dir (asserted). Native STA
SelfTest green (LAYOUT_OK + READONLY_OK + TOURNAMENT_OK + TIMELINE_OK + render-a-real-artifact).

## Follow-ons (not this session)

The human live-GUI confirm (D-0064); the ride-along PAUSE / gateway hold hook (s2.2, A2 remainder -- design-first
+ red-team-gated, touches #7); delegation-tree possession (s2.7 / A3 -- no coordinator yet); wiring a richer
`#42` `state_version` chain once the store is hydrated with multi-version tasks; colour/status highlighting +
a per-context drill-down + a persisted "new since last wave" diff.
