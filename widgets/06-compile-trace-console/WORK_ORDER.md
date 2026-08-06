# WORK ORDER - Widget 06: Compile Trace Console

- **id:** `widgets/06-compile-trace-console` - **Phase:** B (Widget layer) #6 - **Status:** MVP (this session, i38)
- **Realizes:** the audit-surface program tier **A1** (the compile/eval-trace console). Brief:
  `core-docs/fanout/FANOUT_AGENT_003.md` (i38 plan `fo-38-2b1efe73`, worker `WIDGET06-COMPILE-TRACE-i38`).
  Governing design: `research/2026-08-05-audit-pipeline-target.md` s2.1 (the six panes / four controls), s2.5a
  (the compile-layer counterfactual), s3 (readers over artifacts; strictly read-only), s4-A1 (deliverables +
  acceptance), s6 (anti-spiral guardrails) + `research/2026-08-05-interpretability-audit-surface-scoping.md` s5
  (Unit B). Delivery per **D-0038** (native WinForms + `launch.bat`); architecture per the Widget 01/02/03/04/05
  pattern (**D-0039 / D-0049 / D-0060 / D-0064**).

## Purpose

The trace altitude of the audit funnel (map -> gates -> **trace** -> possession): render exactly what a `#40`
compile produced so Nicholas can audit ONE compile's behavior at bounded cost, and ablate its inputs
deterministically. It RENDERS artifacts the contracts already mandate (the packet's four regions + deterministic
identity; the selpol `ranked[]`/`reason_codes[]`/`stages[]`; the R-1 router stage-trace; the `consumer_profile` +
transport ledger; the `#42` `state_version`; the i34 V3 completeness fields) -- ZERO new instrumentation, ZERO
new doc-upkeep. It is a READER (+ a deterministic re-compile for the counterfactual).

## Scope (tight MVP)

Panes 1-4 + 6 (pane 5 tool/sub-agent tree is A2) + the s2.5a compile-layer counterfactual runner. STRICTLY
READ-ONLY over existing compile/eval artifacts; the ONLY write is the counterfactual re-compile scratch + diffs
under the widget's OWN `runtime/` (write-guarded). Deterministic parses with **graceful degradation**: a
malformed/missing artifact becomes a VISIBLE FLAG, never a throw.

**Non-goals (do NOT build):** any write to a doc / git / a runtime dir outside its own; executor jobs; model
calls; the roll-forward (live-model) counterfactual (A4, batch-only, red-team-gated); pane 5 (A2); any
ride-along / possession / side-by-side (Phase 2, post-i40, red-team-gated); modifying `#40`/`#37`/`#42`/`#43`
or any core-doc. A brand-new widget -> **no `skill.json`** (OMIT skill_id/skill_dir). Non-displacing: the
memory sequencing + the P0-1 gate keep priority.

## Architecture (mirrors Widget 05)

- `CompileTraceConsole.psm1` -- WinForms-free driver core (the cloud gate tests it for real): `Read-ContextPacket`
  (three packet carriers), `Read-EvalReport`, `Read-FoldSmoke`, the five pane builders (`Get-Pane1Timeline` ..
  `Get-Pane6TokenLedger`), `Test-TraceSanitized` (i33 diagnostic-array closure), `Get-CompileTraceModel` +
  `Format-CompileTraceHeader`/`Format-CompanionRows`, and the counterfactual layer (`Get-PacketDiff`,
  `New-CounterfactualCase`, `Invoke-CompileCounterfactual`, `Assert-UnderRuntime`, `Resolve-Python`,
  `Invoke-CtcCompileWorker`, `Get-CounterfactualVariations`).
- `Show-CompileTraceConsole.ps1` -- thin STA WinForms shell (toolbar laid out from actual width in a Resize
  handler + `.GetNewClosure()`; `-SelfTest` drives off-screen and prints `SELFTEST_*_OK`).
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-CompileTraceConsole.ps1 %*`.

## Data contracts (consumed, read-only)

- `lifeorch.context_packet/0.2` (a `#40` 0.8.0 packet), in any carrier: a raw packet, a `lifeorch.skill.result/0.1`
  envelope (`.result.result.packet`), or a worker `cc_meta.json` (`.result.packet`). CONTEXT_PACKET_CONTRACT s1
  (four regions), s4 (selpol), s6 (identity), s9 (R-1 router stage-trace), i34 V3 completeness.
- `lifeorch.rehearsal_eval_report/0.1` (the i36 rehearsal report) + a `#37` eval report (hybrid attribution).
- A D-0077 fold-smoke TEXT log (`[PASS]/[FAIL]` lines + `FOLD RESULT: N/M` + `FOLD PASSED/FAILED`).
- `modules/40-context-compiler/context_compiler.py` -- re-invoked READ-ONLY by the counterfactual runner (the
  deterministic compile worker the `#40` CLI wraps); zero model calls, mock retriever.

## Test plan

Dual-mode `tests/Invoke-CompileTraceConsoleTests.ps1` -- cloud gate **85/0/3** (Linux, over committed REAL
fixtures incl. the counterfactual RUNNER end-to-end via the real `#40` worker + the vector-mask reconciliation);
`-Live` adds launch.bat shape + the WinForms `-SelfTest` markers + a real-artifact render.

## Ship

Through the job-runner (`exec-job.sh devship`): sha-verify the shipped files, AST-parse + ASCII-guard, run the
tests `-Live`, commit exactly the `widgets/06-compile-trace-console/` files under the `git` lease with trailers
(CPU lane -- git lease only, no GPU). A brand-new widget -> no `skill.json`. VERIFY the real HEAD via native git
(D-0072). Assert 0 UNMANAGED orphans. **A human live-GUI confirm is an ACCEPTED OPEN follow-on (D-0064)** -- ship
the SelfTest-green widget + FLAG the confirm as pending; do not block on it.

## Acceptance (audit-target s4 A1)

Byte-identical re-render of a fixed artifact; renders REAL fold/rehearsal artifacts (a real `#40` 0.8.0 packet +
the i36 rehearsal report + a fold smoke output); a counterfactual/ablation line reconciles with `#37`'s hybrid
attribution (vector-mask = zero delta while the vector channel is empty); the i33 diagnostic-array sanitization
is honored (the router trace is channel-only; no cross-ns identifying metadata); WRITES NOTHING outside the
widget's own `runtime/` dir (asserted). Native STA SelfTest green (LAYOUT_OK + READONLY + render-a-real-packet).

## Follow-ons (not this session)

The human live-GUI confirm (D-0064); pane 5 tool/sub-agent tree (A2); wiring `#42`'s real `state_version`
timeline once the store is hydrated (i38 unit-2); the roll-forward (live-model) counterfactual (A4, batch-only,
red-team-gated); colour/status highlighting + a per-excerpt drill-down.
