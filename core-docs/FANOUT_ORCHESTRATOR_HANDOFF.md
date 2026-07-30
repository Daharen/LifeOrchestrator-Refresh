# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** There are no other handoff files: this doc is rewritten IN PLACE at the
end of every orchestrator session (snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md`
first -- rule in `DOC_PROTOCOL.md` section 5). Dated `ORCHESTRATOR_HANDOFF_*.md` / `HANDOFF.md` docs are retired;
their content lives here, in `CURRENT_STATE.md`, and in `archive/handoffs/` (D-0066).

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives
`orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a
FRESH Cowork session. You NEVER drive another AI session (the hard D-0051 boundary) -- every lane is
human-dispatched, including the frontier lane (a human-couriered pack, not a driven session).

## 0. TL;DR

- Read section 2 (orient + verify the box), then run **iteration 15** (section 4). Iterations 1-14 are DONE +
  live-confirmed (ledger in section 3; rationale D-0055..D-0067). The EXPANDED 4-lane wave model is VALIDATED
  (i14 ran 1 GPU + 1 CPU + 1 coding + 1 off-box frontier at MaxParallel 3, clean, 0 orphans).
- **The standing GPU candidate is now warm-pool Stage-1.1 HARDENING** (`WARM_POOL_DESIGN.md` section 10 -- the
  frontier red-team's 4 Critical blockers). Stage-1 SHIPPED at i14 but is **opt-in / default-OFF**; do NOT
  enable the pool by default until Stage-1.1 closes those blockers. **RE-AUTHOR `FANOUT_AGENT_001` for
  Stage-1.1** (the i14 Stage-1 brief is archived at `archive/fanout-agents/i14-WMP-stage1.md`). Pick the CPU +
  coding + frontier units with Nicholas from the section-4 menu.
- Workers use `docs:[]`; YOU mirror the shared core-docs under the `git` lease (section 7). Doc rules --
  budgets, replace-don't-append, archive -- live in `DOC_PROTOCOL.md`; follow them or the docs re-bloat.
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile), never
  as on-disk GUID paths (the #1 UX lesson). Worker briefs ALSO go into the numbered
  `core-docs/fanout/FANOUT_AGENT_00N.md` slots (mirrored to the Project) so Nicholas can dispatch a worker by
  telling a fresh session "read claude/fanout/FANOUT_AGENT_00N.md and execute it" (section 5). The slots were
  RESET to EMPTY after i14.
- Box state at handoff: section 11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit
lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize).
Human-dispatched workers: the module emits prompts; Nicholas starts a fresh session per worker. Workers
report; the orchestrator mirrors the core-docs. <=1 GPU worker per wave, ALWAYS. Ship every unit via
`dev.ship` (Module 0 job-runner). The orchestrator NEVER drives another AI session (D-0051) -- the frontier
lane is a couriered pack (D-0052), automated access to any external AI stays OUT.

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md`,
THIS doc, `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (the module manual; its "start MaxParallel 2" sizing is
superseded for this box -- 3 = 1 GPU + 2 CPU is validated, section 4). When editing docs:
`core-docs/DOC_PROTOCOL.md`. For the standing GPU build: `modules/07-model-gateway/WARM_POOL_DESIGN.md`
sections 6 + 9 + 10 (section 10 = the shipped-Stage-1 status + the Stage-1.1 hardening backlog).
The gotcha corpus is owned by `CURRENT_STATE.md` -> Known failures -- read it before touching the box.

Verify the box (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`,
  `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> expect empty (no lease held).
- `git log -1 --format='%h %s'` -> confirm HEAD matches section 11 (read-only git over the mount is fine;
  ALL git writes go through the executor).
`device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor via
`modules/00-bootstrap-executor/exec-job.sh` (section 7).

## 3. Where things stand

**Now:** modules 0-31 + widgets 01-04 built (one-liners in `CURRENT_STATE.md`); the fan-out loop has run 14
iterations end-to-end; the Verification Console is the trusted audit surface (durable verdicts,
live-confirmed); the Governor's `-AutoRamp` is DEFAULT-ON (M0->M1->S0, opt-in deadline-gated X0/27B); the
strong tier is Qwen3.5-9B Q5_K_M, fully GPU-resident on engine b10092; the 27B is validated impractical on
the 11 GB GPU. **Warm-pool Stage-1 (mechanism C) is BUILT -- opt-in / default-OFF (model.gateway skill 0.3.0,
D-0067)** pending Stage-1.1 hardening (`WARM_POOL_DESIGN.md` section 10). NEW at i14: `ops/setup/` portability
Stage-1 (a standalone bring-up toolkit) + `widgets/04` fan-out wave dashboard (read-only; a human live-GUI
confirm is still pending).

**Iteration ledger** (one line each; detail = the D-entry; commits verifiable in git):

- i1-i5 (D-0055..D-0058): res.lease consumers wired (gpu->#7, git->dev.ship, doc:<path>->#20); frontier.bridge #31 built; worker E WEDGED the executor -> single-worker executor+watchdog hardening `e5b93ab`; Governor Phase 2 DETACHED warm server `f8c961a`; Console audit loop validated + #30 packet-input validation `2afd5de`. (Full lines: `archive/handoffs/`.)
- i6 `fo-6-b918dbb8` (D-0059): Governor Phase 3 Stage-1 opt-in `-AutoRamp` `0005e41` (S0 needs >=~1024 tok or the 9B returns empty -- a HARD trigger).
- i7 `fo-7-5a4c227d` (D-0060): X0/27B one-shot rung + logprob-entropy signal `830efcc`; Console `-AutoRamp` toggle + `.GetNewClosure()` fix `b1f36f0`.
- i8 `fo-8-e6f2d44f` (D-0061): `-AutoRamp` default-on TRIED `278c088` then REVERTED byte-exact `fbacf69`; 27B quant NEGATIVE RESULT (no GPU-bound fit on 11 GB).
- i9 `fo-9-d4139304` (D-0062): contract-less closing FIXED + `-AutoRamp` DEFAULT-ON `e444851`; 9B strong tier Q4_K_M -> Q5_K_M `0bd2733` (Q4 kept `wired:false`).
- i10 `fo-10-fbfbae02` (D-0063): WARM_POOL_DESIGN.md shipped `c07125f` + a real-box probe + a couriered second opinion CONFIRMING mechanism C.
- i11 `fo-11-4dbc8dce` (D-0064): Verification Console UX `206b2dd`; left an open verdict-persistence display bug.
- i12 `fo-12-e93a4cdd` (D-0065): verdict save/restore moved into the tested WinForms-free core `49f7feb` (the D-0064 reset was VIEW-ONLY).
- i13 ad-hoc (D-0065): DURABLE verdicts -- results sidecar keyed by packet_id + auto-load `f3c1ec7`; Nicholas live-confirmed the Console WORKING.
- i14 `fo-14-5ea064b6` (D-0067): **FIRST 4-lane wave, 3/3 on-box + a folded frontier red-team.** GPU warm-pool Stage-1 (mech C, opt-in) `09a7e71`; CPU portability bring-up `ops/setup` `821da16`; coding fan-out wave dashboard `widgets/04` `333dac6`; off-box frontier red-team (pack 3edf7218) -> the Stage-1.1 hardening backlog. MaxParallel 3, 0 conflicts, 0 orphans.
- docs: consolidation (D-0066); i14 close-out (D-0067).

Runtime paths: plans `modules/30-orchestrate-fanout/runtime/plans/<plan_id>/` · emitted prompts/packets
`.../runtime/artifacts/<invocation_id>/` · leases `modules/29-resource-lease/runtime/leases/`.

Numbering: fanned-out waves + ad-hoc commits share one counter; **the next wave is iteration 15.**

## 4. Current frontier: iteration 15 -- the 4-lane wave (validated at i14, D-0067)

Nicholas's directive: accelerate by running up to FOUR lanes per wave. Every lane is human-dispatched.

- **GPU lane (<=1 per wave -- HARD CLAMP).** One Cowork worker on a GPU-bound unit (any llama-server / CUDA
  pipeline on the 11 GB GPU; every model module is `parallel_safe:false`). More GPU work = serialize across
  waves. ONLY this lane may touch model modules / `models.json`. Leases gpu->git.
- **CPU lane (>=1).** One Cowork worker on a CPU-only module/infra unit. Lease git.
- **Coding lane (CPU, >=1).** A broad-remit CPU worker -- refinement, interfaces, widgets, tests -- in a
  DISTINCT module/area from the CPU lane (never two workers in one module). Lease git.
- **Frontier-review lane (off-box).** NOT a Cowork worker: the orchestrator emits a frontier.bridge #31
  `pack` (`{prompt, files}` -- NOT `{task,...}`, D-0057); Nicholas couriers it to ChatGPT Pro / GPT-5.x and
  pastes the answer back; the orchestrator runs `read-return`, captures it under
  `modules/31-frontier-bridge/runtime/artifacts/<id>/` and folds it into docs. No lease; fully parallel.
  (i14 proved its value: the red-team of the GPU build surfaced 4 Critical hardening gaps.)

**Clamps.** <=1 GPU worker, always. **1 GPU + 2 CPU = MaxParallel 3** is the validated ceiling (held clean
under a real 3-worker load at i14); grow CPU workers only while the executor heartbeat stays healthy. The
`git` lease serialises all commits (fast). `docs:[]` on all workers -> doc contention 0 by design. Wedge risk
scales with concurrency: persistent llama-servers MUST launch DETACHED and be reaped before finalize
(D-0055/56); reassert the 0-orphan check every wave.

**Wave loop:** scope 1 GPU + 1-2 CPU/coding units (distinct modules) + 1 frontier topic -> fill the
`FANOUT_AGENT_00N` slots (section 5) -> author `workers-i15.json` + `task-plan-i15.ps1` (copy
`task-plan-i14.ps1`; `-Iteration 15 -MaxParallel 3`; `gpu:true` only on the GPU worker) -> run `plan` via the
executor; confirm `dispatch_now` <= 3, exactly <=1 gpu, 0 doc contention, clean preflight -> emit the
frontier pack separately -> relay the check-in + every worker prompt + the pack as FILES + slot docs ->
workers run + report -> poll `-Action status -PlanId fo-15-<id>` until `ready_for_handoff` -> `-Action
handoff` (emits the Verification Console packet) -> `read-return` + fold the frontier answer, mirror the
core-docs under the `git` lease, archive the used briefs + reset the slots -> iterate.

**Candidate-unit menu** (pick with Nicholas each wave):
- GPU: (a) **warm-pool Stage-1.1 HARDENING (mechanism C) per WARM_POOL_DESIGN section 10** -- the STANDING
  candidate: the 4 Critical blockers (a monotonic fencing token vs the TTL; crash-atomic transitions +
  startup reconciliation + a global mutex; an enforced GPU-handoff eviction for non-gateway consumers;
  Windows Job-Object process ownership) + `CanServe()` compatibility + dropping prefix-reuse/LRU/timed-eviction
  from the correctness path + a legacy `--bypass-pool-manager` escape -- BEFORE enabling the pool by default.
  **RE-AUTHOR `FANOUT_AGENT_001` for this** (the Stage-1 brief is archived at `archive/fanout-agents/i14-WMP-stage1.md`).
  (b) warm-pool Stage-2 probes (native `--models` router, slot save/restore, a coding specialist behind a
  >=30-task benchmark) -- gated AFTER Stage-1.1. (c) a generator build #22-#25 (BLOCKED on the frontier
  model-leads). (d) the b10092 universal-engine probe across all 5 fixtures (VLM = the gating test).
- CPU: (a) **portability follow-ons** (wire `Resolve-LifeorchConfig` into `modules/*` path resolution; confirm
  the `ops/setup/out/staging-plan.txt` URLs + download; NOTE: applying `out/models.machine.json` into
  `modules/07/models.json` touches a MODEL module -> that sub-unit belongs to the GPU lane, not a CPU worker);
  (b) wire res.lease consumers into more callers; (c) a non-model module hardening pass (doc.io #20 /
  route.tools #27 / fs.manage #28); (d) executor / watchdog resilience follow-ups (SINGLE-worker wave -- section 8).
- Coding: (a) **a human live-GUI confirm + polish of widget-04 (fan-out wave dashboard)** -- shipped i14,
  confirm still pending; (b) the widget-03 `model.gateway` GPU live-GUI pass (open since D-0060); (c)
  Verification Console polish (results browser, diff view, batch verdicts); (d) Local Agent Console / Module
  Launcher enhancements; (e) test-coverage + interface cleanups.
- Frontier: (a) **request the audio/image/video MODEL LEADS** from the report (unblocks generators #22-#25 --
  still outstanding + high-value); (b) a red-team of the Stage-1.1 hardening DESIGN before/while building it;
  (c) a correctness/security review of a shipped module (executor, res.lease, the pool manager, the Console
  sidecar); (d) a second opinion on any risky decision.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`core-docs/fanout/FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template
`FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`) decouple "what a worker must do" from chat
pasting: fill a slot at wave scoping (usually by pasting the `plan`-emitted worker prompt into its Unit
section), mirror it, and Nicholas dispatches a fresh Cowork session with "Read the Project doc
`claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (section 10). Slot docs still
travel to Nicholas as FILES too. **The slots were RESET to EMPTY after i14** (used briefs archived to
`archive/fanout-agents/i14-<id>.md`). Lifecycle + archiving (READY/DISPATCHED/EMPTY): `DOC_PROTOCOL.md`
section 6.

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` +
  `widgets/` + `ops/` + `archive/`. Disk is canonical; the attached Claude Project mirrors `core-docs/` for
  desktop-less sessions (mirror map in `DOC_PROTOCOL.md` section 8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-owning-module
  model homes; `_engines\llama.cpp` (b8661, default) + `_engines\llama.cpp-b10092` (CUDA 12.4,
  self-contained; ONLY the 9B strong tier pins it via `engine_path`).
- **Executor:** `modules\00-bootstrap-executor\runtime\` (staging -> pending -> running -> completed/failed);
  driven via `exec-job.sh`. Heartbeat: `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Portability toolkit (i14):** `ops/setup/` -- `LifeorchConfig.psm1` + `setup.ps1` + `config.json` +
  `VERIFY-RUNBOOK.md`; generated output under `ops/setup/out/` (gitignored).
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (CC 7.5), i9-9900KF 8c/16t, 64 GB RAM, Win10 Pro; C:
  constrained (~67 GB free), F: 3.72 TB large-data home. Full profile: TOOL_MODEL_REGISTRY.md.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1`
  under `modules/30-orchestrate-fanout/runtime/`, then
  `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`.
  Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s per call). Verbs:
  `submit|wait|run|devship|status`; `EXEC_RT` overrides the runtime dir.
- **Cloud -> device:** gate off-machine FIRST (cloud pwsh 7.4.6 on Linux + a mock/seam harness), then
  `SendUserFile` + `device_commit_files` the changed files onto the repo (byte-exact; <=20 MB/file). Large
  binaries (models/engines) download ON the device via an executor `curl.exe` task -- never through the
  bridge. `device_bash` cannot delete files -- `mv` unwanted ones into a `_to_delete\` folder.
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` -- dev.ship verifies sha256 + AST +
  tests FAIL-CLOSED, then commits ONLY the named files under the `git` lease with trailers. Inputs = `files:[{path,sha256}]`,
  `ast_check`, `test_argv` (with the `{PWSH}`/`{REPO}` tokens), `commit` + `commit_files` +
  `commit_message`-with-trailers, `check_orphans`. Full schema: the `Invoke-DevShip.ps1` header + `modules/00-bootstrap-executor/README.md`.
- **Author a plan:** write `workers-i<N>.json` (per-worker `{id,label,unit,gpu?,docs:[],needs_git?,skill_id?,
  skill_dir?,inputs?,notes}`) + a `task-plan-i<N>.ps1` (copy `task-plan-i14.ps1`), run it, confirm
  `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. `-Action status -PlanId <id>` polls;
  `-Action handoff` emits the Verification Console packet + next prompts. If `status` returns no artifact,
  read the worker reports under `plans/<id>/reports/` directly -- they are the source of truth.
- **Frontier pack:** frontier.bridge #31 `pack` op takes `{prompt, question?, paths?}`. Emit, stage,
  SendUserFile; Nicholas couriers + pastes the answer into the pack's `.answer.md` return file; run `-Action
  read-return -ReturnFile <path> -ExpectPackId <id>` to capture; fold into the relevant doc/decision.
- **Doc edits + mirror (EOL-safe, fail-closed; full rules in DOC_PROTOCOL.md):** core-docs are CRLF; SOME
  MODULE DOCS ARE LF (e.g. `WARM_POOL_DESIGN.md`) -- PRESERVE PER-FILE EOL (assert no mixed EOL before
  committing). Edit fail-closed (assert each anchor occurs exactly once; atomic write); to get LIVE bytes for
  an already-staged path, copy it to a FRESH never-staged dir first (the stale-stage gotcha). Commit via an
  executor `task.ps1`: acquire the `git` lease -> `git reset -q` -> `git add -- <named files>` -> assert
  exactly those staged (Compare-Object) -> `git commit -F <msg>` -> release. Trailers required:
  `Co-Authored-By: <the acting Claude model> <noreply@anthropic.com>` + `Claude-Session: <url>`. NEVER
  `git add -A`. Then re-mirror to the Project: `project_write` with `local_path` (inside the working dir).
- **DECISION_LOG upkeep:** append the new `D-00NN` entry at the bottom of `DECISION_LOG.md` AND append its
  one-row line to `DECISION_LOG_INDEX.md` (two files, one anchored edit each; mark a superseded predecessor
  in its INDEX row only). Update `CURRENT_STATE.md` by REPLACING sections -- never append `[prior]` chains.
- **Deliver everything to Nicholas as FILES** (SendUserFile) -- prompts, packets, packs. Never GUID paths.

## 8. Worker-spec rules

- `docs:[]` on EVERY worker (the orchestrator mirrors core-docs; zeroes doc contention).
- <=1 GPU worker per wave; every model module is `parallel_safe:false`; ONLY the GPU lane touches
  `models.json` / model modules.
- Distinct module/area per worker -- never two workers in one module.
- Correct `inputs` for any skill_id (match the skill.json op contract -- e.g. frontier.bridge `pack` =
  `{prompt,question?,paths?}`; a mismatch surfaces as `input_warning`).
- Single-worker waves for core infra (executor/watchdog, dev.ship, orchestrate.fanout itself).
- Workers acquire leases in gpu -> git -> doc order, do ONE unit, ship via dev.ship, then
  `-Action report -State done`.

## 9. Gotchas (the load-bearing five -- full corpus: `CURRENT_STATE.md` -> Known failures)

- **The wedge (hardened D-0055/56 -- respect it anyway):** a task that BLOCKS holding a persistent
  llama-server orphans it and can livelock the executor while the heartbeat stays fresh. Launch persistent
  servers DETACHED; reap before finalize; assert 0 orphans every wave. If wedged: kill the orphan OUT-OF-BAND
  (Task Manager -> End task `llama-server.exe`); the executor then self-recovers.
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes. Always
  stage a FRESH never-staged path (copy to an `editsrc/` or `docmirror-i<N>/` dir first).
- **Per-file EOL:** core-docs are CRLF; some module docs (e.g. `WARM_POOL_DESIGN.md`) are LF. Match the
  existing EOL when editing; assert no mixed EOL before committing.
- **Git discipline:** read-only git over the Linux mount only; ALL git writes through the executor under the
  `git` lease; NEVER `git add -A`; `project_write local_path` must be inside the working dir, not /tmp.
- **Deliver files, not paths** (SendUserFile) -- and keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh`** (desktop app "Add folder", or approve a
device_request_folder_access). That covers reading the repo, driving the executor, staging, and committing.
F: is reached natively by the Windows executor, not by the session. Machine prerequisite (not per-session):
the executor process running (`ops/start-executor.bat` or the watchdog), heartbeat fresh + `degraded:false`.
Computer-use (Task Manager) is only for out-of-band wedge recovery.

## 11. Box state at handoff (2026-07-29, fan-out iteration 14 close-out, D-0067)

Iterations done through 14; the first EXPANDED 4-lane wave shipped 3/3 on-box + a folded frontier red-team.
No res.lease held (gpu/git free); heartbeat `degraded:false`; post-wave recon confirmed 0 orphaned
`llama-server`/python and `ready_for_handoff=true`. HEAD = the D-0067 i14 close-out docs commit (parent
`09a7e71`, branch `master`) -- confirm live with `git log -1`. **Warm-pool Stage-1 is BUILT but OPT-IN /
default-OFF -- do NOT enable the pool by default until Stage-1.1 (`WARM_POOL_DESIGN.md` section 10).** PENDING
human live-GUI confirms: widget-04 (new i14) + the widget-03 `model.gateway` GPU pass (open since D-0060).
Executor identity + health: `CURRENT_STATE.md` + the live heartbeat (section 2). **Start at section 2, then
run iteration 15 (section 4).**
