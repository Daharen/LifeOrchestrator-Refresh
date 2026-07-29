# Widget 04 - Fan-out Wave Dashboard

The **wave-status** surface for the fan-out loop (`orchestrate.fanout` #30 over `res.lease` #29). Where the
Verification Console (Widget 03) is the human-*audit* surface for a wave's *outputs*, this dashboard is the
human-*status* surface for a wave *in flight*: it answers **"where is this wave right now?"** at a glance --
which workers are running / done / blocked, who holds the gpu / git / doc leases and for how long, how many
workers are dispatched vs queued, and whether the wave is ready for handoff.

It is **READ-ONLY**. It parses the orchestrator's + lease manager's runtime files directly -- the reports ARE
the source of truth -- and **never** invokes `orchestrate.fanout` or `res.lease`, drives a worker, or writes to
the plans / leases dirs. It needs **no lease** to run. (Its own build was committed under the `git` lease.)

## What it shows

1. **A plan picker** (top) listing every wave in the plans dir, **newest first**; it defaults to the newest.
2. A **header** with the wave's plan id, iteration, title, `report_back` cadence, the **dispatch_now vs queued**
   counts, and **ready_for_handoff**.
3. A **worker table** -- one row per plan worker: **id / lane / GPU / state / summary**. `state` is the latest
   report the worker filed (`started` / `progress` / `blocked` / `done` / `failed`), or **`unknown`** when it
   has not reported yet. `lane` is classified from the worker spec (a "`<x> lane`" hint in its notes, else
   gpu/cpu).
4. A **lease panel** -- one row per active `res.lease` file: **resource / holder / held-for / remaining /
   expires**, with an **(EXPIRED)** marker for a lease past its TTL and a `<writing>` row for a lease caught
   mid-write.
5. A **status line** with the roster counts (done / running / blocked / failed / no_report) and the ready state.
6. A **Refresh** button that re-reads both dirs (and picks up any newly-created wave).

`ready_for_handoff` is computed by the **same rule** as `orchestrate.fanout -Action status`: `terminal = done +
failed`; `on_each` -> `terminal >= 1`; `on_all` -> `total > 0 AND terminal == total`. It reimplements nothing
else -- it reads the same files the orchestrator writes. It is **not** a review-queue producer.

## Data sources (read-only)

- **Plan dir:** `modules/30-orchestrate-fanout/runtime/plans/<plan_id>/` -- `plan.json` (the
  `lifeorch.fanout.plan/0.1` record) + `reports/*.json` (each `lifeorch.fanout.report/0.1`; latest per worker
  by `reported_at_utc` wins).
- **Lease dir:** `modules/29-resource-lease/runtime/leases/` -- each `*.lease` (`lifeorch.res.lease/0.1`).

Both default from the repo layout and honour the same env overrides the producers use
(`$env:LIFEORCH_FANOUT_DIR`, `$env:LIFEORCH_LEASE_DIR`), so it always reads the dirs the live wave uses.

## Run it

Double-click **`launch.bat`** (runs `Show-WaveDashboard.ps1` under the per-user PowerShell 7, STA).
Options: `launch.bat -PlanDir <plan dir>` opens a specific wave on start; `-PlansDir` / `-LeaseDir` override the
data-source dirs (e.g. to point at a test tree).

## Files

- `WaveDashboard.psm1` -- WinForms-free driver core: `Get-WaveState` (plan + reports + leases -> the whole
  model), `Format-WaveRows` (display strings), plus `Get-WavePlans` (the newest-first picker), `Get-WorkerLane`,
  `Get-LatestWorkerReports`, `Get-WaveLeases`, and defensive helpers (`Read-JsonFileSafe`, `ConvertTo-Array`,
  `ConvertTo-UtcTime`). Every bit of parsing + the ready rule lives here, so it is unit-tested off-machine.
- `Show-WaveDashboard.ps1` -- thin STA WinForms shell (picker + header + worker/lease lists + Refresh);
  `-SelfTest` builds + drives + disposes the form over the fixtures and prints `SELFTEST_*_OK` markers.
- `launch.bat` -- double-click launcher.
- `tests/Invoke-WaveDashboardTests.ps1` -- dual-mode harness (cloud gate + `-Live` on Windows).
- `tests/fixtures/plans/` -- two sample waves (`fo-99-testwave`: 3 workers in mixed states; `fo-98-oldwave`:
  fully done -> ready) + their reports. `tests/fixtures/leases/` -- gpu / git / doc leases + a mid-write partial.

## Verification

Cloud pre-ship gate: `pwsh -NoProfile -File tests/Invoke-WaveDashboardTests.ps1` (Linux; drives the real core
over the fixtures + synthetic temp dirs; AST-parses every shipped script). On Windows add `-Live` for the STA
form self-test + a render of a real plan dir. **A rendered-UI widget requires a human live-GUI confirm before it
is called done** (D-0049/D-0060/D-0064): mock/self-test gates miss rendered-UI defects.
