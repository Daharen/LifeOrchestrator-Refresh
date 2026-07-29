# FANOUT_AGENT_003 -- Coding lane: Fan-out wave dashboard (widgets/04, new)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** DISPATCHED -- iteration 14, plan `fo-14-5ea064b6`.
- **Wave / iteration:** i14 (plan id `fo-14-5ea064b6`)
- **Lane:** CODING (CPU; a DISTINCT module/area from slot 002 -- `widgets/04` vs `ops/setup`)
- **Worker id / label:** `WAVE-dash` -- "Fan-out wave dashboard: new read-only widget (widgets/04) over plan/worker/lease runtime state"
- **Module/area (exclusive):** `widgets/04-fanout-wave-dashboard/` (NEW -- created this wave) + its tests.
- **GPU:** false
- **Docs:** `[]`

## Mission

Build a NEW native, READ-ONLY widget `widgets/04-fanout-wave-dashboard/` -- the wave-status analogue of the
Verification Console -- that shows a fan-out wave's plan + per-worker state + lease map at a glance by parsing
the `orchestrate.fanout` plan dir + the `res.lease` leases dir. Follows the shipped widget pattern
(WinForms-free core + thin STA shell + dual-mode tests + `launch.bat`, D-0038). Read-only: zero side effects,
no lease-driving.

## Unit (the full worker prompt)

BUILD a NEW read-only widget widgets/04-fanout-wave-dashboard/ that visualises the live state of a fan-out wave (plan + workers + leases) for the orchestrator. It is the wave-status analogue of the Verification Console: a native double-click surface answering 'where is this wave right now?' at a glance. READ-ONLY -- it parses runtime state and NEVER writes, drives, or mutates anything, so it needs NO lease.

FOLLOW THE ESTABLISHED WIDGET PATTERN (copy the structure of widgets/03-verification-console + widgets/01-local-agent-console; read widgets/README.md + widgets/01 + widgets/03 first): a WinForms-FREE CORE WaveDashboard.psm1 (pure functions over plain inputs, fully unit-testable in cloud pwsh with NO WinForms) + a THIN STA SHELL Show-WaveDashboard.ps1 (a WinForms Form + Application.Run; .GetNewClosure() on EVERY event handler -- the D-0060 bare-local-handler null-ref lesson) + a dual-mode test harness tests/Invoke-WaveDashboardTests.ps1 (cloud mock core tests + an on-device -Live STA SelfTest emitting a SELFTEST_*_OK line) + a double-click launch.bat (native, D-0038) + a README.md.

DATA SOURCES (READ-ONLY, parse the files directly -- the reports ARE the source of truth): the plan dir modules/30-orchestrate-fanout/runtime/plans/<plan_id>/ (the plan record + the per-worker reports/ files) and the lease dir modules/29-resource-lease/runtime/leases/ (active gpu / git / doc lease files). Do NOT invoke orchestrate.fanout or res.lease to get state -- read their runtime files, so the dashboard has zero side effects.

CORE FUNCTIONS (WaveDashboard.psm1, pure + tested): Get-WaveState(planDir, leaseDir) -> a plain object { iteration, title, plan_id, dispatch_now, queued, workers:[{id, lane, gpu, state, summary, updated}], leases:[{kind, path, holder, age_s}], ready_for_handoff }; parse the plan JSON + each report file + each lease file DEFENSIVELY (a missing/partial file must yield a well-formed 'unknown' row, never throw -- mind the pwsh 7.4.6 empty-array-unroll and array-double-wrap StrictMode gotchas: build with List[object] + .ToArray(), guard @() on maybe-null). Format-WaveRows(state) -> display rows/strings. The SHELL renders a worker table (id / lane / GPU / state / summary), a lease panel (who holds gpu / git / doc:<path> and for how long), the dispatch_now vs queued counts, ready_for_handoff, and a Refresh button that re-reads the dirs. A plan picker (list the plans dir, newest first) selects which wave to show; default to the newest plan.

SCOPE IN: edit ONLY widgets/04-fanout-wave-dashboard/ (+ its tests + launch.bat + README). SCOPE OUT: no edits to orchestrate.fanout #30, res.lease #29, any module, any other widget, or any core-doc; no writes to the plans/leases dirs; no driving of anything; no GPU/model calls.

GATE off-machine FIRST: the core (.psm1) must be fully unit-tested in cloud pwsh 7.4.6 over FIXTURE plan/lease dirs you create under tests/fixtures/ (a sample plan with 3 workers in mixed states + sample gpu / git / doc lease files) -- assert Get-WaveState maps every state correctly, handles a missing report as 'unknown', and computes ready_for_handoff. On-device add a -Live STA SelfTest. AST-parse all shipped .ps1/.psm1. dev.ship the named widgets/04 files under the git lease.

VERIFY / REPORT: cloud mock + on-device -Live test counts; a live-GUI screenshot-or-confirm note (a rendered-UI widget REQUIRES a human live-GUI confirm before it is called done -- the D-0049/D-0060/D-0064 lesson; mock gates miss rendered-UI defects). Report done via -Action report with the counts + the explicit 'human live-GUI confirm still required' note. If the widget cannot faithfully read a real plan dir, say so plainly with the gap. NO GPU, no model calls, not a review-queue producer.

**Emitted convenience copy:** `runtime/artifacts/53985bb5-5c1e-4d62-b7d1-b9a1bf7d60ea/workers/worker-WAVE-dash.prompt.md`.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` + `widgets/README.md` first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease **git** for the dev.ship commit; release on exit. NO gpu lease.
- ONE unit; `widgets/04-fanout-wave-dashboard/` only; `docs:[]`; do NOT edit #30/#29 or any other widget/module.
- READ-ONLY over the plans/leases dirs -- never write to or drive anything.
- Gate off-machine first (cloud pwsh core tests over fixtures), then `exec-job.sh devship` (FAIL-CLOSED; named files; trailers).
- Rendered-UI change => a human live-GUI confirm before "done" (D-0049/D-0060/D-0064). `.GetNewClosure()` on every handler.
- Report: `-Action report -PlanId fo-14-5ea064b6 -WorkerId WAVE-dash -State done` + test counts + the live-GUI-confirm-required note.

## Verification

Cloud mock core tests over `tests/fixtures/` + on-device `-Live` STA SelfTest (`SELFTEST_*_OK`) green;
`Get-WaveState` maps every worker state, treats a missing report as `unknown`, and computes
`ready_for_handoff`; the widget renders a real plan dir (e.g. `fo-14-5ea064b6`). A human live-GUI confirm is
REQUIRED before this is called done (mock gates miss rendered-UI defects).

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)
