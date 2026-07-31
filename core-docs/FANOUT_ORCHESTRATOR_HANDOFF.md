# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** It is rewritten IN PLACE at the end of every orchestrator session
(snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` first --
`DOC_PROTOCOL.md` section 5). Dated `ORCHESTRATOR_HANDOFF_*.md` docs are retired; their content lives here, in
`CURRENT_STATE.md`, and in `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives
`orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH
Cowork session. You NEVER drive another AI session (the hard D-0051 boundary) -- every lane is human-dispatched,
including the frontier lane (a human-couriered pack, not a driven session).

## 0. TL;DR

- Read section 2 (orient + verify the box), then run **iteration 22**. Iterations 1-21 are DONE +
  live-confirmed (ledger in section 3; rationale D-0055..D-0076). The 4-lane wave model is VALIDATED (up to 1 GPU
  + 1 CPU + 1 coding + 1 off-box frontier at MaxParallel 3; any lane may be skipped).
- **i21 (D-0076) shipped the R1b CONSUMER wave** (single GPU worker, plan `fo-21-61c7597b`): `model.gateway` #7
  0.4.0->**0.5.0** (`0877c70`+`00e5912`; `-UsePoolLeaseSplit` + the NEW real supervisor-routed nvidia-smi evictor
  `lib/PoolEvictor.ps1` + supervisor target-fenced evict), `agent.local` #21 autoramp 0.1.0->**0.2.0**
  (`-SplitLease`), `res.lease` #29 0.4.0->**0.4.1** (command-evictor `tree_gone` passthrough). ALL default-OFF,
  0 regression (off-machine res.lease 74/36/45 + #7 228 + NEW lease-split 63 + #21 122 + NEW split 22), plus a
  FULL live-GPU proof on the 2080 Ti (swap chain, second-owner revoke -> prepared eviction, revoke-during-ACTIVE-
  inference discard, late-stale-result refused, fail-closed prep, real-OOM=driver-spill negative, OFF==ON
  equality, 0 orphans). Ship state: Project `claude/fanout/RESLEASE-R1b-consumers-i21-SHIP-STATE.md`.
- **Findings 1/13/14 are CLOSE-ELIGIBLE at the res.lease/consumer LEASE layer** (13 whole-task-lease starvation +
  14 lock-order cleanly closed by the proven exec/pin split; 1 fencing closed at the res.lease layer).
- **BUT warm-pool default-ON is NOT "soak-only" anymore.** A PARALLEL off-box frontier SECURITY red-team of the
  durable supervisor + real evictor (pack `5cbe8913`, captured `.answer.md`; digest
  `research/2026-07-31-frontier-supervisor-redteam.md`) returned **NO** with 7 structural must-fix blockers, which
  the orchestrator **VERIFIED against live HEAD `00e5912`** (6 in code i21 never restructured; 1 IPC-fencing
  partial). Default-ON now gates on a **SUPERVISOR-HARDENING wave** (the 10 must-fixes) -> an **in-proc res.lease
  client** (the i21 split-overhead finding) -> a **GROWN soak** -> default-ON. **finding 5 (durable Job-Object
  custody) is RE-OPENED** at the custody layer. This is THE new top candidate (section 4).
- Workers use `docs:[]`; YOU mirror the shared core-docs under the `git` lease (section 7). Doc rules live in
  `DOC_PROTOCOL.md`; follow them or the docs re-bloat.
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile), never as
  GUID paths. Worker briefs ALSO go into `core-docs/fanout/FANOUT_AGENT_00N.md` (mirrored to the Project) so
  Nicholas dispatches by telling a fresh session "read `claude/fanout/FANOUT_AGENT_00N.md` and execute it"
  (section 5). The slots were RESET to EMPTY after i21.
- Box state at handoff: section 11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock,
`doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). The module emits
prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors the core-docs.
<=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. The orchestrator NEVER drives another AI session
(D-0051) -- the frontier lane is a couriered pack (D-0052); automated external-AI access stays OUT.

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md`, THIS
doc, `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (the module manual; MaxParallel 3 = 1 GPU + 2 CPU is the
validated ceiling for this box). When editing docs: `core-docs/DOC_PROTOCOL.md`. For the warm pool:
`modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10 + the i21 supervisor red-team digest
`core-docs/research/2026-07-31-frontier-supervisor-redteam.md`. The gotcha corpus is owned by
`CURRENT_STATE.md` -> Known failures -- read it before touching the box.

Verify the box (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`,
  `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> expect no LIVE `<res>.json` lease (durable
  `gpu-*.fence`/`.state`/`.txn` SIBLINGS persist by design after the R1b' primitive -- they are NOT a held lease).
- `git log -1 --format='%h %s'` -> confirm HEAD matches section 11 (read-only git over the mount is fine; ALL
  git writes go through the executor).
- `pgrep -x llama-server; pgrep -x python` -> expect none (0 UNMANAGED orphans).
`device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor (`exec-job.sh`,
section 7).

## 3. Where things stand

**Now:** modules 0-33 + widgets 01-04 built; the fan-out loop has run 21 iterations; the Verification Console is
the trusted audit surface; the Governor's `-AutoRamp` is DEFAULT-ON (M0->M1->S0); the strong tier is Qwen3.5-9B
Q5_K_M GPU-resident on b10092; the 27B is validated impractical on 11 GB. **The res.lease GPU-lease split is
shipped, hardened, AND consumer-adopted + live-proven** (R1a i18 -> R1b i19 -> R1b' i20 -> R1b CONSUMER i21). The
warm pool + durable supervisor stay **default-OFF**: default-ON now gates on the supervisor-hardening wave (the
i21 frontier verdict) + an in-proc lease client + a grown soak. The Phase C video spine is UNDERWAY (#32
media.decompose + #33 track.objects).

**Iteration ledger** (one line each; detail = the D-entry; commits verifiable in git):

- i1-i13 (D-0055..D-0065): res.lease consumers wired; frontier.bridge #31; executor/watchdog hardening;
  Governor Phase 2/3 (`-AutoRamp` default-ON, 9B Q5_K_M); WARM_POOL_DESIGN + Verification Console durable
  verdicts. Full lines: `archive/handoffs/`.
- i14-i17 (D-0067..D-0070): the 4-lane wave model. Warm-pool Stage-1 (`09a7e71`) -> Stage-1.1 hardening
  (`121a0fc`) -> the DURABLE Job-Object gateway supervisor (`cc296fc`, finding 5 "durable" = closed at the time);
  portability shims; widget-04; NEW #32 media.decompose (`5026e2c`) + #33 track.objects (`3264dd5`); SD 3.5
  Medium image tier (`77f1628`+`980dd6d`); folded frontier generator leads + tracker design review.
- i18 `fo-18-c2d73598` (D-0072): **R1a** res.lease GPU-lease-split PRIMITIVE (0.2.0, `e701328`; fencing_token +
  CAS, exec vs revocable residency_pin, prepared-handoff mock/command evictor seam, lock-order rejection; 74/74).
  Worker ship/report lost to a bridge collapse -> orchestrator verified + shipped. Folded frontier direction
  review: R1a PROVISIONAL, findings 1/13/14 close at R1b not R1a.
- i19 `fo-19-3aa34fe9` (D-0073): the **R1b PRIMITIVE** (0.3.0, `2d45ffe`; three-identity fencing + scheduler-owned
  atomic transition + adversarial mock evictor; 74/74 + 36/36). Folded concurrency/safety red-team (pack
  `b823d9db`) -> identities necessary-but-insufficient, transition unsafe-as-ordered -> i20 = R1b'.
- i20 `fo-20-a28f65da` (D-0075): the **R1b' PRIMITIVE HARDENING** (0.4.0, `f6df675`, red-team-driven: incarnation
  ids + exec_lease UUID (closes ABA) + two-phase transition-capability (no grant-before-ready) + target-fenced
  `fence-op` + idempotent saga journal + oplock renew + durable state_version; adversarial matrix A-K 45/45;
  74/74+36/36+45/45, 0 regression). Primitive safe to build on; findings 1/13/14 stay OPEN pending the consumers.
- i21 `fo-21-61c7597b` (D-0076): the **R1b CONSUMER wave** (single GPU worker). `model.gateway` #7 **0.5.0**
  (`0877c70`+`00e5912`; `-UsePoolLeaseSplit` + NEW `lib/PoolEvictor.ps1` + supervisor target-fenced evict),
  `agent.local` #21 autoramp **0.2.0** (`-SplitLease`), `res.lease` #29 **0.4.1**. All default-OFF, 0 regression
  + a full live-GPU proof (swap chain, second-owner revoke->prepared-evict, revoke-during-ACTIVE-inference
  discard, late-stale-result refused, fail-closed prep, real-OOM=driver-spill, OFF==ON equality, 0 orphans).
  Findings 1/13/14 CLOSE-ELIGIBLE at the lease/consumer layer. A PARALLEL off-box supervisor+evictor SECURITY
  red-team (pack `5cbe8913`, digest `research/2026-07-31-frontier-supervisor-redteam.md`) returned NO with 7
  must-fix blockers (orchestrator-verified vs HEAD `00e5912`) -> warm-pool default-ON now gates on a
  SUPERVISOR-HARDENING wave + an in-proc lease client + a GROWN soak; finding 5 RE-OPENED at the custody layer.

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/`
· leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is
iteration 22.**

## 4. Current frontier: iteration 22 -- pick lanes with Nicholas, then run the 4-lane model

Nicholas's directive: up to FOUR lanes per wave; any lane may be skipped. Every lane is human-dispatched.

- **GPU lane (<=1 per wave -- HARD CLAMP).** One worker on a GPU-bound unit. ONLY this lane touches model modules
  / `models.json`. Leases gpu->git.
- **CPU lane (>=1).** One worker on a CPU-only module/infra unit. Lease git.
- **Coding lane (CPU, >=1).** A broad-remit CPU worker in a DISTINCT module/area from the CPU lane. Lease git.
- **Frontier-review lane (off-box, OPTIONAL).** NOT a Cowork worker: emit a frontier.bridge #31 `pack`
  (`{prompt, question?, paths?}`); Nicholas couriers it to GPT-5.x + pastes the answer back; run `read-return`,
  fold it. No lease; fully parallel.

**Clamps.** <=1 GPU worker always. **1 GPU + 2 CPU = MaxParallel 3** is the validated ceiling. The `git` lease
serialises commits; `docs:[]` on all workers -> doc contention 0. Persistent llama-servers MUST launch DETACHED
(via the supervisor) + be reaped before finalize; reassert the 0-UNMANAGED-orphan check every wave.

**Wave loop:** scope lanes (distinct modules) + an optional frontier topic -> fill `FANOUT_AGENT_00N` slots
(section 5) -> author `workers-i22.json` + `task-plan-i22.ps1` (copy `task-plan-i21.ps1`; `-Iteration 22
-MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now`, exactly <=1 gpu, 0
doc contention, clean preflight -> emit any frontier pack separately -> relay the check-in + every worker prompt +
the pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId fo-22-<id>` until
`ready_for_handoff` -> `-Action handoff` -> fold, mirror the core-docs under the `git` lease, archive the used
briefs + reset the slots -> iterate.

**Candidate-unit menu** (pick with Nicholas each wave):
- **GPU / core-infra (THE top candidate): the SUPERVISOR-HARDENING wave** -- fold the i21 frontier red-team's 10
  must-fixes into `model.gateway` #7 (`lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1` + `PoolManager.psm1`
  + `PoolEvictor.ps1`): per-resident suspended-create Job custody + assignment-fatal; lifetime supervisor
  singleton; exact-target + authenticated IPC; no-launch-after-failed/partial-evict-or-CAS; pool-lock replace
  (nonce, no stale-age steal); hard probe deadlines + `unmanaged_vram_pressure`; heartbeat-stale watchdog recovery
  (no live-but-unresponsive fallback); kill/reload restart reconcile; real exe/model verification. Governing doc:
  `research/2026-07-31-frontier-supervisor-redteam.md`. This is the hard gate to warm-pool default-ON. It touches
  a model module + the durable supervisor -> a SINGLE-worker wave (section 8); much of it is off-machine-provable
  (mock supervisor/nvidia-smi seams) but the custody + live fault-injection needs the GPU.
- **GPU: a GENERATOR UPGRADE** #22-#25 (SD 3.5 image DONE; next Wan2.1 1.3B video / Stable Audio Open 1.0, or the
  new-engine leads Z-Image-Turbo Q8 / ACE-Step / LTX-Video -- `research/2026-07-30-generator-model-leads.md`); or
  the widget-03 `model.gateway` GPU live-GUI pass (open since D-0060).
- **CPU: the in-proc res.lease client** (the i21 split-overhead finding: ~6-9 child-pwsh spawns/call dominate;
  batched/in-process ops) -- strongly recommended BEFORE any default-ON; or a portability follow-on
  (`$PwshPath` across model-bound entrypoints; core-infra 00.1 + `ops/*.bat`); or a non-model hardening pass.
- **Coding: the Phase C video spine** -- `video.timeline` #21 (consume the frontier-reviewed track schema in
  `research/2026-07-30-track-objects-design-review.md`) or `video.interpret` #22; or the `track.objects` #33
  refinement wave; or Verification Console / widget polish; or test-coverage.
- **Frontier: a design review** of `video.timeline` #21; a generator-engine sanity check; or a SECOND red-team of
  the supervisor-hardening wave AS BUILT (the analogue of i19->i20).

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`;
mirrored at `claude/fanout/`) decouple "what a worker must do" from chat pasting: fill a slot at wave scoping
(paste the `plan`-emitted worker prompt into its Unit section, or a tight summary pointing to the emitted copy +
the governing design doc; keep the slot within its 8 KB budget), mirror it, and Nicholas dispatches a fresh
session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant
(section 10). Slot docs also travel to Nicholas as FILES. **The slots were RESET to EMPTY after i21** (used brief
archived to `archive/fanout-agents/i21-RESLEASE-R1b-consumers-live.md`). Lifecycle: `DOC_PROTOCOL.md` section 6.

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/`
  + `ops/` + `archive/`. Disk is canonical; the attached Claude Project mirrors `core-docs/` (mirror map in
  `DOC_PROTOCOL.md` section 8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-owning-module model
  homes; `_engines\llama.cpp` (b8661, default) + `_engines\llama.cpp-b10092` (CUDA 12.4; ONLY the 9B pins it).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat:
  `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Warm pool / supervisor** (`modules/07-model-gateway/`): `lib/PoolManager.psm1` + `lib/Supervisor.psm1` +
  `Start-GatewaySupervisor.ps1` + `lib/PoolEvictor.ps1` (the R1b real evictor) + `WARM_POOL_DESIGN.md`.
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (CC 7.5), i9-9900KF 8c/16t, 64 GB RAM, Win10 Pro; C: ~67 GB
  free, F: 3.72 TB. Full profile: `TOOL_MODEL_REGISTRY.md`.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1` under
  `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id>
  <timeout> <task.ps1> <maxwait> "<desc>"`. Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps
  ~45 s). Verbs: `submit|wait|run|devship|status`; `EXEC_RT` overrides the runtime dir.
- **Cloud -> device:** gate off-machine FIRST, then `SendUserFile` + `device_commit_files` the changed files onto
  the repo (byte-exact; <=20 MB/file). Large binaries download ON the device via an executor `curl.exe` task.
  `device_bash` cannot delete -- `mv` unwanted files into a `_to_delete\` folder (or `cp` for archive snapshots).
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` -- dev.ship verifies sha256 + AST + tests
  FAIL-CLOSED, then commits ONLY the named files under the `git` lease with trailers. **VERIFY the real HEAD via
  native `git log`/`git show --stat`, NOT the dev.ship `committed` field** (D-0072).
- **Author a plan:** write `workers-i<N>.json` + a `task-plan-i<N>.ps1` (copy `task-plan-i21.ps1`), run it,
  confirm `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. `-Action status -PlanId <id>` polls;
  `-Action handoff` emits the Verification Console packet + next prompts. If `status` returns no artifact, read
  the worker reports under `plans/<id>/reports/` directly -- they are the source of truth.
- **Frontier pack:** #31 `pack` op takes `{prompt, question?, paths?}`. Emit, stage, SendUserFile; Nicholas
  couriers + pastes the answer BETWEEN the pack's two `<<<FRONTIER-BRIDGE-ANSWER-...>>>` markers (keep the
  `<!-- pack_id: ... -->` line) into the `.answer.md` return file; run `-Action read-return -ReturnFile <path>
  -ExpectPackId <id>` (expect `captured/valid`, `pack_id_match`) to capture; fold into a research digest + docs.
- **Doc edits + mirror (EOL-safe, fail-closed; full rules in DOC_PROTOCOL.md):** core-docs are CRLF; SOME MODULE
  DOCS ARE LF (e.g. `WARM_POOL_DESIGN.md`) -- PRESERVE PER-FILE EOL. A line-oriented JSON applier (unique
  single-line anchors; whole-line/span replace; detect + rejoin the file's EOL) is the low-risk pattern (i21:
  `apply-i21-docedits.ps1` + `edits-i21.json`). For LIVE bytes of an already-staged path, copy to a FRESH
  never-staged dir first (the stale-stage gotcha) or read via an executor task / device_bash cat. Commit via an
  executor `task.ps1`: acquire the `git` lease -> `git reset -q` -> `git add -- <named files>` -> assert the
  staged set -> `git commit -F <msg>` -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>`
  + `Claude-Session: <url>`. NEVER `git add -A`. Re-mirror via `project_write` `local_path` (inside the working dir).
- **DECISION_LOG upkeep:** append the new `D-00NN` entry at the bottom of `DECISION_LOG.md` AND append its one-row
  line to `DECISION_LOG_INDEX.md`; mark a superseded predecessor in its INDEX row only. Update `CURRENT_STATE.md`
  by REPLACING sections -- never append `[prior]` chains.
- **Deliver everything to Nicholas as FILES** (SendUserFile) -- prompts, packets, packs.

## 8. Worker-spec rules

- `docs:[]` on EVERY worker (the orchestrator mirrors core-docs; zeroes doc contention).
- <=1 GPU worker per wave; every model module is `parallel_safe:false`; ONLY the GPU lane touches `models.json` /
  model modules.
- Distinct module/area per worker -- never two workers in one module.
- Correct `inputs` for any skill_id (match the skill.json op contract). A brand-new module has no skill.json yet
  -- OMIT `skill_id`/`skill_dir` for it.
- **Single-worker waves for core infra** (executor/watchdog, dev.ship, orchestrate.fanout itself, res.lease #29,
  AND the model.gateway durable supervisor -- the supervisor-hardening wave is single-worker).
- Workers acquire leases in gpu -> git -> doc order, do ONE unit, ship via dev.ship, then `-Action report -State
  done`. A build-then-verify GPU unit may take git for the commit, RELEASE it, then take gpu ONLY for the live
  verify (never hold the GPU idle waiting on git). A live proof whose harness itself acquires the real gpu
  exec/pin leases must NOT wrap an outer whole-task gpu lease around the proof (i21 lesson).

## 9. Gotchas (the load-bearing set -- full corpus: `CURRENT_STATE.md` -> Known failures)

- **The wedge (D-0055/56):** a task that BLOCKS holding a persistent llama-server orphans it + can livelock the
  executor while the heartbeat stays fresh. Launch persistent servers DETACHED (via the supervisor); reap before
  finalize; assert 0 UNMANAGED orphans. If wedged: kill the orphan OUT-OF-BAND (Task Manager -> `llama-server.exe`).
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes. Stage a FRESH
  never-staged path (copy to `editsrc/` / `docmirror-i<N>/` first), or read via an executor task / device_bash cat.
- **Per-file EOL:** core-docs CRLF; some module docs (e.g. `WARM_POOL_DESIGN.md`) LF. Match the existing EOL.
- **Git discipline:** read-only git over the mount only (huge CRLF-noise M-list -- ignore it); ALL git writes
  through the executor under the `git` lease; NEVER `git add -A`; `project_write local_path` must be inside the
  working dir. `dev.ship` can FALSE-NEGATIVE `committed` (verify real HEAD via native git; clear a stale 0-byte
  `.git/index.lock` via an executor task, assert no `git.exe` running, then re-commit).
- **i21 live-found (supervisor):** (1) consumer identity params must pin BOTH `resident_instance_id` AND
  `instance_generation` through the supervisor launch (`00e5912`); (2) a LONG-RUNNING supervisor keeps the OLD
  module code -- RESTART it after shipping supervisor-side changes; (3) `[Console]::Out` bypasses in-process
  pipeline capture (emit via `Write-Output`, capture via child-process redirection); (4) the 9B returns empty
  content at tiny `-MaxTokens` -> spurious review-queue flags (use >=64 tokens). Driver 591.74 SPILLS a too-big
  model to system RAM instead of a hard OOM -> "it loaded" != "it fits"; the measured-PEAK `required_vram` +
  stable-headroom gate is the only real admission control.
- **Deliver files, not paths** (SendUserFile) -- and keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh`** (desktop app "Add folder", or approve a
device_request_folder_access). That covers reading the repo, driving the executor, staging, and committing. F: is
reached natively by the Windows executor. Machine prerequisite: the executor running (`ops/start-executor.bat` or
the watchdog), heartbeat fresh + `degraded:false`. Computer-use (Task Manager) is only for out-of-band wedge
recovery.

## 11. Box state at handoff (2026-07-31, iteration 21 close-out, D-0076)

Iterations done through 21; i21 was a clean single-worker GPU wave (the R1b CONSUMER wave) + a folded off-box
supervisor SECURITY red-team. No LIVE res.lease held (durable `gpu-*.fence/.state/.txn` siblings persist by
design -- NOT a held lease); heartbeat `degraded:false`; post-wave recon confirmed 0 UNMANAGED
`llama-server`/python and `ready_for_handoff=true`. **HEAD = the D-0076 i21 close-out docs commit** (worker
parents `0877c70` R1b consumer wave -> `00e5912` gen-binding fix; `master`) -- confirm with `git log -1`.

**Warm pool + durable supervisor stay DEFAULT-OFF.** The res.lease GPU-lease split is shipped, hardened, AND
consumer-adopted + live-proven (findings 1/13/14 CLOSE-ELIGIBLE at the lease/consumer layer). **Default-ON now
gates on: (1) the SUPERVISOR-HARDENING wave** (the i21 frontier red-team's 10 must-fixes -- digest
`research/2026-07-31-frontier-supervisor-redteam.md`; **finding 5 durable-custody RE-OPENED**), **(2) an in-proc
res.lease client** (the split-overhead finding), **(3) a GROWN soak.** The Phase C video spine is UNDERWAY (#32 +
#33; next video.timeline #21 / video.interpret #22). PENDING human live-GUI confirm: the widget-03
`model.gateway` GPU pass (D-0060). Start at section 2, then run iteration 22 -- pick lanes with Nicholas from the
section-4 menu (the supervisor-hardening wave is the top gate to default-ON).
