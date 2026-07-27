# orchestrate.fanout -- Fan-out Orchestrator (Module 30)

The deterministic **scaffolding** for running N parallel worker Cowork sessions that build Life Orchestrator
on this one box (D-0050 multi-instance direction, D-0051 fan-out orchestrator), built **on top of `res.lease`
(#29)**. A skill cannot spawn or drive Claude sessions -- and it must not (automating an external AI UI is the
prohibited-access boundary, D-0051/D-0052). What it *can* do is produce and manage every deterministic
artifact around the workers: the schedule, the per-worker leases and prompts, the one check-in prompt for
Nicholas, the collected reports, and the final handoff + a Verification Console packet.

It composes two things it does not reimplement: **`res.lease` #29** (each worker's ordered
gpu->git->doc:\<path\> lease commands are embedded in its prompt; an optional read-only `res.lease list`
preflight snapshots current holdings) and the **Verification Console** widget #03 (its
`lifeorch.verification.packet/0.1` is what `handoff` emits as the orchestrator's human-I/O).

Deterministic, `parallel_safe:true`, orchestrator/**non-producer** (no review-queue writes). Pure PowerShell +
.NET -- no external binary / Python / model / `models.json` change.

## Actions (one per invocation)

- **plan** -- worker specs -> a collision-safe plan. Per worker: the ordered lease set (acquire-order
  **gpu -> git -> doc:\<path\>**, release reverse) + the exact `res.lease` command lines. Plan-level:
  `dispatch_now` (trial of `-MaxParallel`, default 2, **clamped to at most one GPU worker**) vs. `queued`;
  `conflicts` (gpu serialization + doc-ownership contention); one `workers/worker-<id>.prompt.md` per worker
  + one `check-in.prompt.md`; an optional res.lease preflight. Persists the plan.
- **report** -- a worker records `{state: started|progress|blocked|done|failed, summary, needs}`. One file
  per report, so N workers report concurrently with no contention.
- **status** -- the roster + each worker's latest state + `ready_for_handoff` (per the `report_back` cadence).
- **handoff** -- a summary + next-iteration worker prompts + one check-in prompt + a
  `lifeorch.verification.packet/0.1` (one `run_module`/`human_action` item per worker output).
- **list** -- every persisted plan.

## The fan-out loop (see `FANOUT_PROTOCOL.md`)

`plan` -> Nicholas dispatches the worker prompts into fresh Cowork sessions -> workers hold their leases via
`res.lease`, do one scoped unit, ship via `dev.ship`, and `report` -> `status` until `ready_for_handoff` ->
`handoff` emits a verification packet Nicholas audits in the Verification Console -> the next `plan`.

## Inputs / outputs

See `skill.json` for the full input list and `examples/` for representative invocations + a real result
envelope. Plans live in the shared `-PlansDir` (`$env:LIFEORCH_FANOUT_DIR`, else `runtime/plans`) as
`plans/<plan_id>/plan.json` + `reports/<worker>.<guid8>.json`; artifacts (prompts, packet, handoff) under
`runtime/artifacts/<invocation_id>/`.

## What it does NOT do

Spawn/drive any AI session; acquire leases *for* the workers (each worker holds its own via `res.lease`; the
orchestrator acquires `git`/`doc:` for its OWN doc mirroring by calling `res.lease` directly); edit shared
core-docs or commit (that is dev.ship + the orchestrator). Follow-ons: auto-renew for long leases, live
worker monitoring, a fair/priority scheduler, per-worker tool-scoping.

## Tests

`tests/Invoke-OrchestrateFanoutTests.ps1` -- dual-mode, OS-portable, ASCII-only; drives the REAL skill with a
mock `res.lease` (`tests/mock-reslease.ps1`) for the preflight seam and the optional Module 1 wrapper
(`-WrapperPath`). **51/51** off-machine (cloud pwsh 7.4.6). See the module `WORK_ORDER.md` + DECISION_LOG D-0054.
