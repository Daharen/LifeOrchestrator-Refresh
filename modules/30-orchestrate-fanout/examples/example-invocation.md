# orchestrate.fanout -- example invocations

All actions emit one `lifeorch.skill.result/0.1` envelope on stdout. Plans persist under the shared
plans dir (`-PlansDir`, else `$env:LIFEORCH_FANOUT_DIR`, else `runtime/plans`). Run from the repo root.

## 1. plan -- turn worker unit-specs into a collision-safe fan-out plan

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 `
  -Action plan -Title "iteration 5" -MaxParallel 2 `
  -WorkersJson '[
    {"id":"w-image","unit":"add an SDXL tier to gen.image","gpu":true,"skill_id":"gen.image","skill_dir":"modules/23-gen-image"},
    {"id":"w-docio","unit":"add a regex edit mode to doc.io","docs":["CURRENT_STATE.md"]}
  ]'
```

Produces: `result.dispatch_now` / `result.queued` (trial of `MaxParallel`, clamped to one GPU worker),
`result.conflicts` (gpu_serialized + doc_contention), one `workers/worker-<id>.prompt.md` per worker (each
embedding its ordered `res.lease acquire/release` commands + the report-back command), and one
`check-in.prompt.md` for Nicholas. A read-only `res.lease list` preflight warns if a needed resource is
already held live (add `-NoPreflight` to skip, or `-ResLeasePath <path>` to point at res.lease).

## 2. report -- a worker records progress (run by the worker session)

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 `
  -Action report -PlanId fo-5-1a2b3c4d -WorkerId w-docio -State done -Summary "shipped doc.io regex mode, 90/90"
```

`-State` is `started | progress | blocked | done | failed`; add `-Needs "<what>"` when blocked.

## 3. status -- roll up worker reports + the handoff-ready check

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action status -PlanId fo-5-1a2b3c4d
```

Returns each worker's latest state, `counts`, and `ready_for_handoff` (per the plan's `report_back`
cadence: `on_all` = every worker terminal; `on_each` = at least one terminal).

## 4. handoff -- assemble the verification packet + next-iteration prompts

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 `
  -Action handoff -PlanId fo-5-1a2b3c4d `
  -NextWorkersJson '[{"id":"w-next","unit":"the next scoped unit"}]'
```

Writes `verification-packet.json` (a `lifeorch.verification.packet/0.1` -- one `run_module`/`human_action`
item per worker output, for the Verification Console), the next-iteration worker prompts under
`next-workers/`, and exactly one `check-in.prompt.md`. Omit `-NextWorkersJson` to re-emit this plan's
workers as an editable template.

## 5. list -- every persisted plan

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action list
```

## Generic form (any action)

```powershell
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 `
  -InputsJson '{"action":"handoff","plan_id":"fo-5-1a2b3c4d"}'
```
