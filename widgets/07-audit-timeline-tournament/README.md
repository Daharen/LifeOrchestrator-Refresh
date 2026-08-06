# Widget 07 - Audit Timeline + Tournament

A native WinForms window (double-click `launch.bat`, D-0038) that RENDERS the audit-pipeline **tier A2**
read-only slice (`research/2026-08-05-audit-pipeline-target.md`): the **s2.6 tool-selection tournament** and
the **s2.1 cross-context omniscient stitched timeline**. It is the stepping / stitched-visibility altitude of
the audit funnel, one altitude below Widget 06's compile trace.

**STRICTLY READ-ONLY.** It parses existing compile / fan-out / episode / working-memory artifacts and drives
NOTHING: no doc write, no git write, no executor job, no model call, **no lease held, no pause point**.
`non_execution` holds; it enables no action. Because it holds no lease and defines no pause point, it commits
**ZERO lease-window violations** by construction (the D-0055/56 wedge, with a person as the orphan, is
structurally impossible here). The render path writes **NOTHING**; the `runtime/` dir is reserved +
write-guarded (`Assert-UnderRuntime`) for a FUTURE "new since last wave" marker only. There is **no
`skill.json`** -- it is a Widget (the HID layer), like Widgets 05/06.

## What it shows

### Tournament (s2.6) -- the staged selection as elimination brackets, with a reconciliation proof

Load a `#40` routed packet (+ the wave's `#30` plan) and it renders three brackets, each with per-stage COUNTS
+ REASON CODES and a machine RECONCILIATION verdict (the counts must reconcile with the underlying stage
traces):

- **Bracket A - ROUTER** (`evaluation_hooks.routing_stage_trace`, R-1): `classification -> routing ->
  channel_selection`, each round `candidates_in -N eliminated -> candidates_out`, naming each removed channel +
  its reason codes. Reconcile: `in - |removed| == out` per round, and `out[n] == in[n+1]` along the chain.
- **Bracket B - SELECTION** (`evaluation_hooks.stages`): `raw_retrieval -> post_filter -> packet` (semantic
  retrieval -> rerank -> select), with the omit reason for every dropped candidate. Reconcile: post is a subset
  of raw, packet a subset of post, every drop carries an `omit_reason`.
- **Bracket C - PLAN VALIDATION** (`#30` plan.json): the deterministic fan-out dispatch gate -- workers ->
  ACCEPTED (dispatch_now) / DEFERRED (queued) / REJECTED (conflicts: the named `gpu_serialized` /
  `doc_contention` checks). Reconcile: `|workers| == accepted + deferred + rejected`.
- (s2.6 PREFLIGHT over activation cards is FUTURE -- no skill-selection module emits R-1 traces yet; it is
  rendered as a labeled not-yet-emitted stage, never faked.)

A flat compile (no router) shows no router bracket and still reconciles.

### Timeline (s2.1) -- one wave, stitched across every context, in order

A single deterministically-sorted timeline that REVEALS a whole wave end-to-end:

- **WAVE** (`#30` plan + reports): `plan_created` -> a `worker_reported` event per report, plus a
  dispatched-vs-reported reconciliation (missing / orphan / plan_id-mismatch flagged).
- **EPISODES** (`#39`): each episode's `episode_open -> stage:* -> episode_close`; stage timestamps are derived
  from `valid_from` + cumulative stage duration (episodes carry durations, not absolute per-stage stamps).
- **WORKING-MEMORY** (`#42`): the per-task `state_version` CAS chain (`parent_state_version` linkage),
  rendered even without absolute timestamps (CAS-ordered).
- **BATONS**: rendered when present; a graceful absence note otherwise (delegation / possession is unbuilt --
  s2.7 / A3 FUTURE).

All timestamps are normalized to canonical ISO-8601 UTC (culture-stable), so the render is byte-identical
across machines regardless of locale.

## Architecture (mirrors Widget 05/06)

- `AuditTimelineTournament.psm1` -- the **WinForms-free driver core** (so the cloud gate tests it for real):
  the artifact readers, the tournament brackets + reconciliation, the timeline stitch (a total order over an
  integer `(sort_key, seq)` composite -- no reliance on Sort-Object stability), the sanitization guards
  (`Test-TraceSanitized` the i33 channel-only check + `Test-TimelineSanitized` the no-content event allowlist),
  `ConvertTo-IsoUtc`, `Get-AuditModel` + `Format-AuditHeader`, and the `Assert-UnderRuntime` write-guard.
  Defensive throughout: every source degrades to a well-formed shape + a flag, never a throw.
- `Show-AuditTimelineTournament.ps1` -- the **thin STA WinForms shell**: a toolbar (packet + Browse; wave +
  Browse-wave; Refresh -- laid out from the toolbar's ACTUAL width in a Resize handler + `.GetNewClosure()`,
  the widget-04 lesson), a read-only header, and a TabControl of monospace lists. `-SelfTest` builds + drives +
  disposes the form OFF-SCREEN and prints `SELFTEST_*_OK`.
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-AuditTimelineTournament.ps1 %*`.

## Tests

Dual-mode `tests/Invoke-AuditTimelineTournamentTests.ps1`:

- **Cloud gate (no `-Live`):** AST-parse + ASCII-guard all scripts; the readers; the three tournament brackets
  + reconciliation (incl. a corrupted-count MISMATCH catch); the wave stitch + cross-context episode/state
  events + the deterministic order + the dispatched-vs-reported reconciliation; the i33 sanitization (+ an
  injected cross-ns key + an injected episode body/snippet that never leaks into a rendered line); byte-identical
  re-render; culture-stable ISO timestamps; the read-only guarantees; graceful degradation. **81/0 in cloud
  pwsh 7.4.6 (Linux)** over committed REAL fixtures.
- **Live (`-Live`, Windows/executor):** launch.bat shape; the WinForms `-SelfTest` (`SELFTEST_FORM_OK` /
  `MODEL_OK` / `TOURNAMENT_OK` / `TIMELINE_OK` / `SANITIZE_OK` / `REFRESH_OK` / `READONLY_OK` / `LAYOUT_OK`);
  and a render of a real on-box wave with no throw.

## Status / follow-ons

**A human live-GUI confirm is an ACCEPTED OPEN follow-on (D-0064)** -- the SelfTest-green widget ships and the
live-GUI confirm is carried as pending (mock/self-test gates miss rendered-UI defects). Follow-ons (not this
session): the ride-along PAUSE / gateway hold hook (s2.2, design-first + red-team-gated); delegation-tree
possession (s2.7 / A3); a richer `#42` state_version chain once the store is hydrated; colour/status
highlighting; a per-context drill-down; a persisted "new since last wave" diff.
