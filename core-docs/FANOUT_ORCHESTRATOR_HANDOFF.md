# FAN-OUT ORCHESTRATOR HANDOFF

**You are the fan-out orchestrator** -- the ONE Claude instance that drives `orchestrate.fanout` (#30) to run N parallel worker Cowork sessions building Life Orchestrator on Nicholas's one Windows box (DESKTOP-PF5FFMF). Read `START_HERE.md` + `HANDOFF.md` first (project state), then `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (the module's operating manual). THIS doc is the practical operator guide + the current frontier + the hard-won gotchas. You NEVER drive another AI session -- workers are human-dispatched (the D-0051 boundary); you emit prompts and Nicholas pastes each into a fresh session.

## Where things stand (D-0057, 2026-07-28)
Four fan-out iterations have run end-to-end:
- **Iter 1 (fo-1-20ed8a0b):** res.lease `gpu`->model.gateway #7 (0c6d5c9), `git`->dev.ship (5530418), + frontier.bridge #31 built (f52f21d).
- **Iter 2 (fo-2-b991c65f):** res.lease `doc:<path>`->doc.io #20 (d2a7352 -- consumer trio COMPLETE) + Module 30 prompt-template fix (581f854). (Worker E, a warm-server probe, FAILED and WEDGED the executor -- see the incident.)
- **Iter 3 (fo-3-cf4965fb):** single-worker executor+watchdog HARDENING (e5b93ab).
- **Iter 4 (fo-4-31706096):** Governor Phase 2 DONE (detached warm server, f8c961a; warm reuse ~1ms vs ~1200ms cold), Verification Console audit loop validated end-to-end (174360d), frontier.bridge return-capture hardened + a real Phase 3 escalation pack (b17a945).
res.lease consumer trio complete; executor+watchdog hardened + restarted-live; Governor Phase 2 done; the audit loop is exercised + gated.

## The loop (each iteration)
1. **Scope units.** 1..N units that can run in parallel. Per worker: `gpu` (any model/render run)? `docs` -> leave `[]` (see the doc rule); `needs_git` (default true); `skill_id`+`skill_dir`+`inputs` if the output is a runnable module (-> a run_module verification item).
2. **plan.** Author a task.ps1 that calls `Invoke-OrchestrateFanout.ps1 -Action plan -Title ... -Iteration N -MaxParallel M -ReportBack on_all -WorkersJson '<json>'`; run it through the executor. It returns dispatch_now (<=M, at most ONE gpu worker) / queued / conflicts / a prompt per worker + one check-in. Confirm 0 gpu/doc conflicts + a clean preflight.
3. **Relay.** Stage + read the emitted workers/worker-*.prompt.md + check-in.prompt.md; give Nicholas the check-in + each worker prompt to paste into a FRESH Cowork session (one per worker).
4. **Workers run.** Each acquires its res.lease(s) in gpu->git->doc order, does ONE unit, ships via dev.ship, then `-Action report ... -State done`.
5. **status -> handoff.** `-Action status -PlanId <id>` until ready_for_handoff; then `-Action handoff -PlanId <id>` (emits a Verification Console packet + next prompts).
6. **YOU mirror the docs** (workers never touch core-docs): acquire the res.lease `git` lease, do CRLF-safe fail-closed anchored edits + commit with trailers, mirror the changed core-docs to the Project, release. Then iterate.

## Running pwsh on the box (critical)
`device_bash` is a **Linux VM** with the repo mounted -- it CANNOT run Windows pwsh. All pwsh runs through the **executor** (a Windows process). Write a task.ps1 to `modules/30-orchestrate-fanout/runtime/` via a device_bash heredoc, then `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`. Ship a unit gate+commit with `exec-job.sh devship`. Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45s). Confirm the executor is alive first: `modules/00-bootstrap-executor/runtime/control/heartbeat.json` fresh + `degraded:false`.

## Worker-spec rules
- **docs:[] on every worker.** Workers REPORT; the orchestrator mirrors shared core-docs (step 6). Zeroes doc-contention.
- **<=1 GPU worker per wave** (the clamp). Every model module is parallel_safe:false (one llama-server/pipeline on the 11 GB GPU). CPU workers run alongside it.
- **Correct inputs.** If you set skill_id, give `inputs` matching that skill op contract (e.g. frontier.bridge `pack` needs {prompt,files}, NOT {task,...} -- a real defect the audit loop caught, D-0057).
- **Single-worker for core infra** (the executor/watchdog, dev.ship, orchestrate.fanout itself) -- isolate it so it cannot collide with concurrent workers.
- Distinct module per worker; commits serialize on the `git` lease (+ dev.ship index-clean guard). MaxParallel: start 2, scale as the box proves it keeps up (it handled 3 fine).

## Gotchas (hard-won)
- **The wedge (now hardened, D-0055/56):** a task that BLOCKS while holding a persistent llama-server orphans it (the executor Job kill cannot reap a detached grandchild) and locks a running/ file, livelocking the poll loop while the heartbeat stays fresh (watchdog blind). FIX shipped (G, e5b93ab): reap the whole tree before finalize + isolate per-task finalize + watchdog wedge-detection via heartbeat health fields (degraded/poll_error_streak/stuck_finalize_count). LAUNCH ANY PERSISTENT SERVER DETACHED so the task returns (E2 Win32_Process.Create, f8c961a).
- **If it wedges anyway:** the executor cannot run its own cleanup while wedged; kill the orphan OUT-OF-BAND. computer-use TERMINALS are click-only (cannot type), so use **Task Manager** (full tier) End task on llama-server.exe. The lock releases and the executor self-recovers.
- **device_stage_files stale snapshot:** re-staging a previously-staged uploads path returns OLD bytes. Stage a FRESH never-staged path (or the real core-docs/*.md directly, not a reused docmirror/).
- **Doc edits:** core-docs are CRLF. Edit via a fail-closed anchored pwsh pass (normalize LF for matching; throw if an anchor is not found exactly N times; atomic temp+rename; re-apply CRLF). Commit ONLY the named files under the git lease; never `git add -A`; trailers required. Mirror by fresh-copying to a never-staged path, staging, and project_write to the Project (HANDOFF mirrors to claude/HANDOFF.md; others to top-level).
- **Watchdog** is session-scoped/non-persistent (D-0013). (Re)start ops/start-watchdog.bat for unattended runs; it now catches a wedged-but-heartbeating executor.

## Current frontier / candidate next units (iteration 5+)
- **Governor Phase 3 (auto-ramp)** -- the controller that ramps floor->ceiling on failure; Phase 2 (warm server) is DONE, and worker I produced a ready escalation pack (modules/31-frontier-bridge/runtime/artifacts/d9df215c-01f2-4bcb-843f-4b05f67ad7b1/governor-phase3-escalation.md) for a frontier second opinion.
- **Module 30 packet-input fix** (H #1): normalize/validate run_module example inputs against the skill contract.
- **Verification Console teardown fix** (H #2): port the orphan-name sweep into widgets/03 run-teardown (Process.Kill($true) misses a detached llama-server) + a -Live no-orphan assertion.
- **Residual human Console pass** (H #3): run a model.gateway (GPU) item in the live Console GUI.
- Apply the warm-server pattern to the other model modules; wire res.lease consumers into more callers; a model-module narrowing pass.

## Reference
Plans: modules/30-orchestrate-fanout/runtime/plans/<plan_id>/. Artifacts (prompts, packets): .../runtime/artifacts/<invocation_id>/. Shared lease dir: modules/29-resource-lease/runtime/leases/. Commits: fo-1 0c6d5c9/5530418/f52f21d (+docs dd481b9); fo-2 d2a7352/581f854; fo-3 e5b93ab (+docs eed48e0); fo-4 f8c961a/174360d/b17a945.