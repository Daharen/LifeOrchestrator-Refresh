# FAN-OUT ORCHESTRATOR HANDOFF -- EXPANDED WAVE MODEL (2026-07-29)

For the NEXT Claude instance acting as the fan-out orchestrator (fresh session; Nicholas is handing off to keep context small). Read THIS first, then `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` (the enduring operator guide -- its "Expanded wave model" section mirrors section 4 here) and the enduring docs in section 2. This handoff sets up an EXPANDED, parallel "4-lane" wave model to accelerate the build (Nicholas's directive).

Repo HEAD at handoff: `f3c1ec7` (branch `master`), box `DESKTOP-PF5FFMF`. Executor healthy (degraded:false). No res.lease held. Bridge connected.

## 0. TL;DR
- You are the fan-out orchestrator: you SCOPE units, run `orchestrate.fanout` (#30) to emit worker prompts, and Nicholas pastes each into a FRESH Cowork session. You NEVER drive another AI session (the hard D-0051 boundary). Workers `docs:[]`; YOU mirror the shared core-docs.
- NEW (D-0065): run up to FOUR LANES per wave to accelerate parallel work -- **1 GPU worker + 1 CPU worker + 1 broad coding worker + 1 externalized frontier-GPT review/audit lane**. Full model in section 4. The GPU lane is HARD-CLAMPED to <=1 per wave (one 11 GB GPU).
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile), never as on-disk GUID paths (the #1 UX lesson).
- Iterations 12-13 are DONE + live-confirmed (Verification Console verdict fix + durable verdicts; D-0065). The core-docs mirror is DONE (this session). Your first build wave is the EXPANDED wave = iteration 14 (section 3).

## 1. Role + hard boundary (unchanged, non-negotiable)
`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). Human-dispatched workers: the module emits prompts; Nicholas starts a fresh session per worker and pastes it. The orchestrator mirrors the shared core-docs under the `git` lease. <=1 GPU worker per wave. Ship every unit via `dev.ship` (Module 0 job-runner). The orchestrator NEVER drives another AI session -- INCLUDING the frontier lane, which is a human-couriered pack, not a driven session.

## 2. First 10 minutes: orient + verify the box
Read (the Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/HANDOFF.md`, `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` (operator guide + the "Expanded wave model" section), `core-docs/CURRENT_STATE.md`, `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md`, `modules/31-frontier-bridge/` (the frontier courier). For the standing GPU build: `modules/07-model-gateway/WARM_POOL_DESIGN.md` sections 6 + 9 + DECISION_LOG D-0063/D-0065.
Verify the executor (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`): `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh + `degraded:false`. `device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor via `modules/00-bootstrap-executor/exec-job.sh`. Confirm HEAD `f3c1ec7` + no res.lease held (`ls modules/29-resource-lease/runtime/leases`).

## 3. YOUR IMMEDIATE WORK
### 3.1 -- Mirror is DONE (D-0065). Nothing owed here.
Core-docs are current through iteration 13 (HEAD f3c1ec7): DECISION_LOG D-0065 covers iteration 12 (verdict fix, 49f7feb) + the iteration-13 ad-hoc follow-on (durable verdicts, f3c1ec7); CURRENT_STATE + FANOUT_ORCHESTRATOR_HANDOFF updated + re-mirrored to the Project. The formal fo-12 `-Action handoff` verification packet was skipped (Nicholas live-confirmed the Console WORKING; the packet is optional and can be emitted with `-Action handoff -PlanId fo-12-e93a4cdd` if wanted).
### 3.2 -- Run the FIRST EXPANDED WAVE (iteration 14).
With Nicholas, pick from the section-4 candidate menu: 1 GPU unit + 1 CPU unit + 1 coding unit + 1 frontier review/audit topic. (The GPU-lane unit was intentionally left open at handoff -- decide it with Nicholas; the standing candidate is warm-pool Stage-1.) Then:
1. Author `workers-i14.json` (per-worker `{id,label,unit,gpu?,docs:[],needs_git?,notes}`; `gpu:true` ONLY on the GPU worker; `docs:[]` on all; each worker a DISTINCT module/area) + a `task-plan-i14.ps1` (copy `task-plan-i12.ps1`).
2. Run `plan` with `-MaxParallel 3` (1 GPU + 2 CPU). Confirm `dispatch_now` <= 3, exactly <=1 gpu, `doc_contention` 0, `gpu_serialized` 0, clean preflight.
3. Emit the frontier pack separately: `frontier.bridge` #31 `pack` op `{prompt, files}` for the review/audit topic.
4. Relay the check-in + EVERY worker prompt + the frontier pack to Nicholas as FILES (SendUserFile). Nicholas dispatches each on-box worker in a fresh Cowork session and couriers the frontier pack to the external GPT.
### 3.3 -- Collect + close the wave.
As workers report, poll `-Action status -PlanId fo-14-<id>` until `ready_for_handoff`, then `-Action handoff`. Fold the frontier answer into the relevant doc/decision. Mirror the core-docs (D-0066+) under the git lease. Iterate the next wave.

## 4. The EXPANDED wave model (the acceleration plan, D-0065)
Nicholas's directive: accelerate parallel work by running up to FOUR lanes per wave. The orchestrator still NEVER drives another AI session (D-0051) -- every lane is human-dispatched.

- **GPU lane (<=1 per wave -- HARD CLAMP).** One Cowork worker on a GPU-bound unit (any llama-server / CUDA pipeline on the 11 GB GPU). Physically capped at 1 concurrent (every model module is `parallel_safe:false`). More GPU work = serialize across waves, never parallelize. ONLY this lane may touch model modules / `models.json`. Acquires gpu -> git leases.
- **CPU lane (>=1).** One Cowork worker on a CPU-only module/infra unit; runs alongside the GPU lane. Acquires git.
- **Coding lane (CPU, >=1).** A broad-remit CPU worker -- refinement, expansion, interfaces, widgets, tests, anything non-GPU. A DISTINCT module/area from the CPU lane (never two workers in one module). Acquires git.
- **Frontier-review lane (off-box, external GPT -- frontier.bridge #31).** NOT a Cowork worker and NOT box/GPU-bound. The orchestrator emits a pack `{prompt, files}`; Nicholas couriers it to ChatGPT Pro / GPT-5.x and pastes the answer back; the orchestrator folds it into docs. Consumes NO gpu/git/doc lease -> fully parallel and free; ideal for audit / review / second-opinion / research. Audit-and-review-only is a perfectly good use (Nicholas's words).

**Clamps + concurrency.** <=1 GPU worker, always. The box has PROVEN 3 concurrent Cowork sessions OK, so **1 GPU + 2 CPU = MaxParallel 3** is the validated on-box ceiling; scale CPU/coding workers up only while the executor heartbeat stays `degraded:false` / `poll_error_streak:0` / `stuck_finalize_count:0` under load. The `git` lease serialises ALL commits across lanes (commits are fast -- fine). Workers use `docs:[]`, so doc contention is 0 by design (the orchestrator mirrors core-docs). The frontier lane is off-box (bounded only by Nicholas's courier bandwidth). Wedge risk scales with concurrency -- any persistent llama-server MUST launch DETACHED and be reaped before finalize (D-0055/56); reassert the 0-orphan check every wave.

**Wave loop.** Scope 1 GPU + 1-2 CPU/coding units (distinct modules) + 1 frontier review topic -> `plan` (MaxParallel = on-box worker count; `gpu` only on the GPU worker; `docs:[]` on all) -> confirm dispatch_now <= MaxParallel / exactly <=1 gpu / 0 doc contention / clean preflight -> emit the frontier pack separately (frontier.bridge `pack`) -> relay the check-in + every worker prompt + the frontier pack as FILES -> workers run + report; frontier answer couriered back -> `status` until ready_for_handoff -> `handoff` -> fold the frontier answer + mirror the core-docs under the git lease -> iterate.

**Anti-collision rules (critical at 3+ concurrent).** Distinct module/widget per on-box worker (never two workers in one module -- commits serialise on the git lease, but logically they would clobber). The GPU worker is the ONLY one allowed to touch model modules / `models.json`. All workers `docs:[]`; the orchestrator owns core-docs. Start MaxParallel at 3; grow CPU workers only after watching the executor stay healthy under load.

**Candidate-unit menu (the fresh session + Nicholas pick each wave):**
- **GPU:** (a) warm-pool Stage-1 = the NAMED POOL MANAGER (mechanism C) per WARM_POOL_DESIGN sections 6 + 9 (READY draft `claude/iter11-stage1-DRAFT.md`, renumber on dispatch) -- the standing candidate; (b) warm-pool Stage-2 probes (native `--models` router on b8661/b10092, slot save/restore, a coding-specialist behind its >=30-task benchmark; gated after Stage-1); (c) a generator build #22-#25 (BLOCKED on the frontier model-leads); (d) the b10092 universal-engine probe across all 5 fixtures (VLM = the gating test).
- **CPU:** (a) portability / new-machine bring-up (a scoped `setup.ps1`: config-driven repo-root + data-root, prereq check, model/engine staging, GPU detect, machine-specific `models.json`, a verify pass -- do before a hardware upgrade); (b) wire res.lease consumers into more callers; (c) a model-module narrowing / hardening pass; (d) executor / watchdog resilience follow-ups.
- **Coding (broad, CPU):** (a) Verification Console polish/expansion (it is the audit surface now -- a results browser, a diff view, batch verdicts); (b) Local Agent Console (widgets/01) refinements; (c) a NEW widget (e.g. a fan-out wave dashboard = plan/worker/lease state at a glance); (d) test-coverage + interface cleanups; (e) Module Launcher (widget 02) enhancements.
- **Frontier (audit/review/research):** (a) request the audio/image/video MODEL LEADS from the frontier report (unblocks generators #22-#25 -- outstanding + high-value); (b) a design/impl audit of warm-pool Stage-1 (mechanism C) -- red-team the residency-key / whole-task-lease / keep-resident policy; (c) a correctness/security review of a shipped module (executor, res.lease, or the Console durable-verdicts sidecar); (d) a second opinion on any risky decision.

## 5. Mechanics cheat-sheet
- **Loop:** scope -> `plan` -> relay the ONE check-in + each worker prompt + the frontier pack as FILES -> workers run in fresh sessions (acquire leases gpu->git->doc, one unit, `dev.ship`, `-Action report -State done`) -> poll `-Action status -PlanId <id>` until `ready_for_handoff` -> `-Action handoff` -> fold the frontier answer + mirror the core-docs.
- **Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1` under `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`. Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s). Ship a unit: `exec-job.sh devship <id> <inputs.json> <timeout>`.
- **Author a plan:** write `workers-i<N>.json` + a `task-plan-i<N>.ps1` (copy `task-plan-i12.ps1`), run it, confirm `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. MaxParallel = on-box worker count (start 3 = 1 GPU + 2 CPU).
- **Frontier pack (the review lane):** frontier.bridge #31 `pack` op needs `{prompt, files}` (NOT `{task,...}` -- a real defect the audit loop caught, D-0057). Emit the pack, stage it, SendUserFile it; Nicholas couriers it to the external GPT and pastes the answer back; capture the answer under `modules/31-frontier-bridge/runtime/artifacts/<id>/...answer.md` and fold it into the relevant doc/decision.
- **Doc mirror (CRLF-safe, fail-closed):** the core-docs are CRLF. Edit on-device with a fail-closed Python pass (assert each anchor occurs exactly once; write; preserve per-file EOL). Then commit via an executor `task.ps1` that acquires the `git` lease -> `git reset -q` -> `git add -- <named docs>` -> assert only those staged (Compare-Object) -> `git commit -F <msg>` -> release. Trailers required: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: <url>`. NEVER `git add -A`. Then re-mirror to the Project: `device_stage_files` the edited core-docs FRESH (copy them into a never-staged `docmirror-i<N>/` dir first -- re-staging a prior path returns STALE bytes), copy into the working dir, `project_write` with `local_path`. Project paths: `CURRENT_STATE.md` / `DECISION_LOG.md` / `MODULE_ROADMAP.md` top-level; `HANDOFF.md`, `FANOUT_ORCHESTRATOR_HANDOFF.md`, `ADAPTIVE_RESOURCE_GOVERNOR.md`, `ORCHESTRATOR_HANDOFF_*.md` under `claude/`.
- **Deliver prompts / packets / packs to Nicholas as FILES** (SendUserFile), not on-disk GUID paths -- the #1 UX lesson.

## 6. Gotchas (don't relearn)
- Deliver prompts/packets/packs as FILES (section 5) -- the #1 UX lesson.
- The wedge SCALES with concurrency: a task that BLOCKS holding a persistent llama-server orphans it and can livelock the executor. Launch persistent servers DETACHED; reap before finalize; assert 0 orphans. If wedged, kill the orphan out-of-band (Task Manager -> End task `llama-server.exe`).
- `device_stage_files` stale snapshot: re-staging a previously-staged path returns OLD bytes. Copy the edited docs into a fresh `docmirror-i<N>/` dir and stage THAT.
- `project_write local_path` must be inside the working directory (e.g. `/home/claude/...`), not `/tmp`.
- `-Action status` once returned no artifact via `exec-job.sh run`; the worker's report under `plans/<id>/reports/` is the source of truth -- read it directly.
- Rendered-UI bugs slip mock/API gates (D-0049/D-0060 + the D-0064 verdict bug). ANY UI change needs a human live-GUI confirm before "done" in the docs.
- The executor process shows as `dotnet.exe`; trust the heartbeat, not the process list.
- The large Linux-mount `git status` M-list is CRLF noise -- authoritative state is clean on Windows; do ALL git writes through the executor; never `git add -A`.
- Numbering: iteration 13 was an AD-HOC follow-on (no fan-out plan). Fanned-out waves + ad-hoc commits share the counter; the next fanned-out wave is iteration 14.

## 7. Box state at handoff
HEAD `f3c1ec7` (master). Executor healthy (`degraded:false`). No res.lease held (gpu/git free). Iterations done through 13 (Verification Console: UX D-0064, verdict fix + durable verdicts D-0065). Access to resume: connect the repo folder `C:\Users\just_\LifeOrchestrator-Refresh` (one grant), verify the heartbeat, then start at section 3.2.
