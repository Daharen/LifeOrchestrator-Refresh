# WORK ORDER - Widget 04: Fan-out Wave Dashboard

- **id:** `widgets/04-fanout-wave-dashboard` · **Phase:** B (Widget layer) #4 · **Status:** MVP (this session)
- **Realizes:** the fan-out loop's missing human *status* surface (iteration 14 coding lane; brief
  `core-docs/fanout/FANOUT_AGENT_003.md`). Delivery per **D-0038** (native WinForms + `launch.bat`),
  architecture per the Widget 01/02/03 pattern (**D-0039 / D-0049 / D-0060 / D-0064**).

## Purpose

The wave-status analogue of the Verification Console. The Console (Widget 03) audits a wave's *outputs*; this
dashboard shows a wave *in flight* -- "where is this wave right now?" -- so the orchestrator (and Nicholas) can
see at a glance which workers are running / done / blocked, who holds the gpu / git / doc leases and for how
long, dispatch_now vs queued, and whether the wave is ready for handoff. It replaces squinting at GUID-named
runtime JSON by hand.

## Scope (tight MVP)

READ-ONLY. Pick a wave (newest first) -> render its worker table + lease panel + counts + ready state ->
Refresh to re-read. Parses the plan dir + lease dir files DIRECTLY; **never** invokes `orchestrate.fanout` /
`res.lease`, drives a worker, or writes to the plans / leases dirs. Needs **no lease** at run time.

**Non-goals:** no driving / dispatching / handoff (that is the orchestrator, and a skill must not drive an AI
session -- D-0051); no editing plans, reports, or leases; no packet authoring or verdicts (that is Widget 03);
no auto-refresh timer this MVP (a manual Refresh button); no cross-machine or historical trend view. Not a
review-queue producer.

## Architecture (mirrors Widget 01/02/03)

- `WaveDashboard.psm1` -- **WinForms-free driver core** (so the cloud gate tests it for real):
  - `Get-WaveState (planDir, leaseDir [, now])` -> the whole model `{ ok, error, plan_id, iteration, title,
    report_back, max_parallel, created_at, dispatch_now, queued, dispatch_now_ids[], queued_ids[], counts,
    workers[{id,lane,gpu,state,summary,updated,needs}], leases[{kind,path,holder,age_s,expires_at,remaining_s,
    expired,note}], ready_for_handoff }`. Defensive throughout: a missing/partial plan/report/lease file yields
    a well-formed `unknown` / `ok=false` shape, never a throw.
  - `Format-WaveRows (state)` -> display strings (header lines, worker table, lease panel, summary line).
  - `Get-WavePlans` (the newest-first plan picker), `Get-WorkerLane` (lane classification),
    `Get-LatestWorkerReports` (latest report per worker), `Get-WaveLeases` (parse the lease dir + ages/expiry),
    `Get-LeaseKindRank`, `Format-Age`, and the defensive helpers `Read-JsonFileSafe`, `ConvertTo-Array`,
    `ConvertTo-UtcTime`, `Get-Prop`, `Limit-Text`, `Resolve-WavePaths`.
- `Show-WaveDashboard.ps1` -- **thin STA WinForms shell**: a plan-picker combo (top) + a Refresh button, a
  read-only header box, and two monospace lists (workers over leases in a horizontal split). It only marshals
  the core's `Get-WaveState` / `Format-WaveRows` output into controls. `.GetNewClosure()` on handlers (D-0060).
  `-SelfTest` builds + drives + disposes the form over the fixtures and prints `SELFTEST_*_OK` markers.
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-WaveDashboard.ps1 %*`.

## Data contracts (consumed, read-only)

- `lifeorch.fanout.plan/0.1` (`plan.json`): plan_id, iteration, title, report_back, max_parallel, workers[]
  (id, gpu, notes, ...), dispatch_now[], queued[]. NB: a worker's `leases`/`acquire_commands` may be a string
  OR an array in the wild -- the dashboard does not depend on those fields, and reads scalars defensively.
- `lifeorch.fanout.report/0.1` (`reports/<worker>.<hash>.json`): worker_id, state
  (`started|progress|blocked|done|failed`), summary, needs, reported_at_utc. Latest per worker wins.
- `lifeorch.res.lease/0.1` (`*.lease`): resource, holder, acquired_at_utc, expires_at_utc, note, ...

`ready_for_handoff` matches `orchestrate.fanout -Action status` exactly: terminal = done + failed; `on_each` ->
terminal >= 1; `on_all` -> total > 0 AND terminal == total.

## Test plan

Dual-mode `tests/Invoke-WaveDashboardTests.ps1`:
- **Cloud gate (no `-Live`):** AST-parse + ASCII-guard all scripts; plan discovery (newest-first); lane
  classification; latest-report-per-worker; `Get-WaveState` state mapping for every worker state + missing ->
  `unknown`; both `ready_for_handoff` rules (on_all + on_each); lease parsing (age / remaining / expired + a
  mid-write partial); defensive missing/malformed plan.json + a garbage report file; `Format-WaveRows`
  rendering. Fixtures + synthetic temp dirs. **80/80 green** in cloud pwsh 7.4.6 (Linux).
- **Live (`-Live`, Windows/executor):** launch.bat shape; the WinForms `-SelfTest`
  (`SELFTEST_FORM_OK` / `PICKER_OK` / `RENDER_OK` / `READY_OK` / `REFRESH_OK`); and a render of a **real**
  `orchestrate.fanout` plan dir (e.g. `fo-14-5ea064b6`) with no throw.

## Ship

Through the job-runner (`dev.ship`): sha-verify the shipped files, AST-parse, run the tests `-Live`, commit
exactly the `widgets/04-fanout-wave-dashboard/` files under the `git` lease with trailers.
**A human live-GUI confirm is REQUIRED before this is called done** (D-0049/D-0060/D-0064 -- mock/self-test
gates miss rendered-UI defects).

## Follow-ons (not this session)

An opt-in auto-refresh timer; colour/status highlighting (blocked = red, ready = green); a "reveal in Explorer"
affordance for a worker's prompt / a lease file (like the Console's Open affordance); a compact all-waves
overview; surfacing `conflicts` (gpu_serialized / doc_contention) and the preflight snapshot; and a worker
`needs` drill-down for a blocked worker.
