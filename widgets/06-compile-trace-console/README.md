# Widget 06 - Compile Trace Console

A native WinForms window (double-click `launch.bat`, D-0038) that RENDERS a real `#40` context-packet compile
artifact across the audit-pipeline **panes 1-4,6** and runs the **s2.5a compile-layer counterfactual runner**.
It is the compile/eval-trace altitude of the audit funnel (`research/2026-08-05-audit-pipeline-target.md`
tier A1), one altitude below Widget 05's construction map.

**STRICTLY READ-ONLY.** It parses existing compile/eval artifacts and drives NOTHING: no doc write, no git
write, no executor job, no model call, no lease held. `non_execution` holds; it enables no action. The ONLY
thing it writes is the counterfactual re-compile scratch + diffs under its OWN `runtime/` dir, guarded
(`Assert-UnderRuntime`) so it can never escape that dir. There is **no `skill.json`** -- it is a Widget (the
HID layer), like Widget 05.

## What it shows

Load a packet (a `#40` 0.8.0/0.9.0 `lifeorch.context_packet/0.2` artifact -- `-PacketFile`, else the newest
under `modules/40-context-compiler/runtime/artifacts/`, else the bundled fixture) and it renders:

- **Pane 1 - Task Timeline:** the compile's stages in order (normalize -> retrieve -> [route] -> select
  raw/post_filter/packet -> budget -> packet) with per-stage candidate counts.
- **Pane 2 - Exact Model View:** the four packet regions -- `control_plane` (AUTHORITATIVE), `task_input`
  (REQUEST), `working_memory` (CONTINUITY-authoritative; reserved at Tier 0), `evidence` (EVIDENCE;
  `can_instruct=false`) -- each with a TRUST banner, in the contract render order, under the `non_execution`
  frame. The packet IS the model's whole context.
- **Pane 3 - Retrieval + Selection Trace:** the selpol `ranked[]` / `reason_codes[]` / `stages[]`, the **R-1
  router stage-trace** (`evaluation_hooks.routing_stage_trace` -- classification / routing / channel_selection,
  now that the i37 router EXISTS), the retrieval plan / lineage (`retrieval_provenance`, vector-channel status),
  and the i34 **V3 retrieval-completeness** fields (on a descend compile).
- **Pane 4 - Rule / Exception Stack:** fired / excluded / overridden rules with inputs + outputs --
  `current_only`, the namespace-closure intersection, the temporal-intent override (i33 U5'), the per-reason-code
  candidate tally, and the disposition rule.
- **Pane 6 - Token + State Ledger:** the token budget, the transport accounting (the P0-4 authority that gates
  `answerable`), the `consumer_profile`, the `#42` working-memory `state_version` ledger, and the omission
  manifest.
- **Eval / Rehearsal / Fold tab:** the i36 rehearsal report (tier-1 criteria), a `#37` eval report (hybrid
  attribution -- the counterfactual reconcile source), and a real D-0077 fold-smoke log.

(Pane 5, the tool + sub-agent tree, is OUT -- deferred to A2; no delegation exists yet.)

## The compile-layer counterfactual runner (s2.5a)

Pick a variation, press **Run counterfactual**: it re-runs `#40`'s deterministic compile worker on the **SAME
pinned mock snapshot** with **exactly ONE varied input** and diffs the two packets (`packet_id`, disposition,
ranked/selected, omission, identity deltas). **ZERO model calls** -- a deterministic re-compile only. Variations
(`Get-CounterfactualVariations`): `budget`, `temporal_intent`, `namespace`, `channel_mask`, `route`,
`exclude_record` (+ `selection_policy_version`, NAMED but pinned at A1 since `#40` imports `#37`'s canonical
`selpol_rrf_v1`). A `channel_mask vector` masks the vector CONTRIBUTION and -- because the vector channel is
empty -- shows a **zero packet delta**, reconciling with `#37`'s hybrid attribution (vector rescued 0).

## Architecture (mirrors Widget 05)

- `CompileTraceConsole.psm1` -- the **WinForms-free driver core** (so the cloud gate tests it for real): the
  artifact readers (`Read-ContextPacket` handles the raw-packet / `skill.result` envelope / worker `cc_meta`
  carriers; `Read-EvalReport`; `Read-FoldSmoke`), the five pane builders, `Test-TraceSanitized` (the i33
  diagnostic-array closure check), `Get-CompileTraceModel` + `Format-*`, and the counterfactual layer
  (`Get-PacketDiff` pure differ, `New-CounterfactualCase`, `Invoke-CompileCounterfactual`, `Assert-UnderRuntime`
  write-guard). Defensive throughout: every source degrades to a well-formed shape + a flag, never a throw.
- `Show-CompileTraceConsole.ps1` -- the **thin STA WinForms shell**: a toolbar (packet path + Browse; the
  counterfactual variation combo + value + Run; Refresh -- laid out from the toolbar's ACTUAL width in a Resize
  handler + `.GetNewClosure()`, the widget-04 lesson), a read-only header, and a TabControl of monospace lists.
  `-SelfTest` builds + drives + disposes the form OFF-SCREEN and prints `SELFTEST_*_OK`.
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-CompileTraceConsole.ps1 %*`.

## Tests

Dual-mode `tests/Invoke-CompileTraceConsoleTests.ps1`:

- **Cloud gate (no `-Live`):** AST-parse + ASCII-guard all scripts; the readers in all three carrier shapes;
  the five pane builders (content asserted); the sanitization check (+ an injected-key fail-closed); byte-identical
  re-render; the pure differ + `New-CounterfactualCase` write-guard; the counterfactual RUNNER end-to-end via the
  REAL `#40` worker when resolvable (a budget delta + the vector-mask reconciliation + determinism); the
  read-only guarantees; graceful degradation. **85/0 in cloud pwsh 7.4.6 (Linux)** over committed REAL fixtures.
- **Live (`-Live`, Windows/executor):** launch.bat shape; the WinForms `-SelfTest` (`SELFTEST_FORM_OK` /
  `MODEL_OK` / `PANES_OK` / `SANITIZE_OK` / `COMPANION_OK` / `COUNTERFACTUAL_OK` / `REFRESH_OK` / `READONLY_OK` /
  `LAYOUT_OK`); and a render of the newest REAL `#40` runtime artifact with no throw.

## Status / follow-ons

**A human live-GUI confirm is an ACCEPTED OPEN follow-on (D-0064)** -- the SelfTest-green widget ships and the
live-GUI confirm is carried as pending (mock/self-test gates miss rendered-UI defects). Follow-ons (not this
session): colour/status highlighting; a per-excerpt drill-down; the roll-forward (live-model) counterfactual
(A4, batch-only, red-team-gated); wiring `#42`'s real `state_version` timeline once the store is hydrated (i38);
the pane-5 tool/sub-agent tree (A2).
