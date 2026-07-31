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

- Read section 2 (orient + verify the box), then run **iteration 23**. Iterations 1-22 are DONE +
  live-confirmed (ledger in section 3; rationale D-0055..D-0077). The 4-lane wave model is VALIDATED (up to 1 GPU
  + 1 CPU + 1 coding + 1 off-box frontier at MaxParallel 3; any lane may be skipped).
- **i22 (D-0077) shipped the Phase C two-lane CPU wave**: `track.objects` #33 **0.2.0** (`b60340c`; the
  reviewed STABLE-IDENTITY tracker is the DEFAULT, greedy retained byte-identical) + NEW **`video.timeline`
  #34** (`e8583d1`, arch pos 21) -> the ORCHESTRATOR FOLD **0.1.1** (`bad9e27`) fixed the 2 consumer-side
  schema divergences the cross-module smoke caught; the #33->#34 chain is PROVEN on real bytes.
- **STANDING RULE (new, D-0077):** when parallel isolated workers build a schema PRODUCER and its CONSUMER
  against a shared design doc, the orchestrator MUST run a cross-module smoke (real producer output fed into
  the consumer) at fold BEFORE close. i22 proved isolated green gates cannot see divergent digest readings.
- **Warm-pool default-ON still gates on (D-0076): the SUPERVISOR-HARDENING wave** (the i21 frontier red-team's
  10 must-fixes; digest `research/2026-07-31-frontier-supervisor-redteam.md`; finding 5 custody RE-OPENED) ->
  an **in-proc res.lease client** -> a **GROWN soak**. The hardening wave was DEFERRED at i22 by Nicholas's
  lane pick -- it remains THE top candidate (section 4); re-offer it first.
- Workers use `docs:[]`; YOU mirror the shared core-docs under the `git` lease (section 7); doc rules in
  `DOC_PROTOCOL.md`. **Doc debt:** CURRENT_STATE + MODULE_ROADMAP are over budget -- a slim pass is a named
  candidate unit (section 4).
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile). Worker
  briefs ALSO go into `core-docs/fanout/FANOUT_AGENT_00N.md` (mirrored to the Project) so Nicholas dispatches
  by telling a fresh session "read `claude/fanout/FANOUT_AGENT_00N.md` and execute it" (section 5). The slots
  were RESET to EMPTY after i22.
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
`core-docs/research/2026-07-31-frontier-supervisor-redteam.md`. For the video spine: the design review
`research/2026-07-30-track-objects-design-review.md` + both modules' `SCHEMA_NOTES.md` (the reconciled
emitter/consumer contract). The gotcha corpus is owned by `CURRENT_STATE.md` -> Known failures -- read it first.

Verify the box (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`,
  `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> expect no LIVE `<res>.json` lease (durable
  `gpu-*.fence`/`.state`/`.txn` SIBLINGS persist by design -- they are NOT a held lease).
- `git log -1 --format='%h %s'` -> confirm HEAD matches section 11 (read-only git over the mount is fine; ALL
  git writes go through the executor).
- `pgrep -x llama-server; pgrep -x python` -> expect none (0 UNMANAGED orphans).
`device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor (`exec-job.sh`,
section 7).

## 3. Where things stand

**Now:** modules 0-34 + widgets 01-04 built; the fan-out loop has run 22 iterations; the Verification Console is
the trusted audit surface; the Governor's `-AutoRamp` is DEFAULT-ON (M0->M1->S0); the strong tier is Qwen3.5-9B
Q5_K_M GPU-resident on b10092. The res.lease GPU-lease split is shipped, hardened, consumer-adopted +
live-proven (i18-i21; findings 1/13/14 CLOSE-ELIGIBLE at the lease/consumer layer). The warm pool + durable
supervisor stay **default-OFF**: default-ON gates on the supervisor-hardening wave + an in-proc lease client + a
grown soak (D-0076). **The Phase C video spine front half is BUILT** (#32 media.decompose + #33 track.objects
0.2.0 stable + #34 video.timeline 0.1.1, contract-proven end-to-end); `video.interpret` (pos 22), the live
composition wave, and the DENSE-STREAM decision gate remain.

**Iteration ledger** (one line each; detail = the D-entry; commits verifiable in git):

- i1-i13 (D-0055..D-0065): res.lease consumers wired; frontier.bridge #31; executor/watchdog hardening;
  Governor Phase 2/3 (`-AutoRamp` default-ON, 9B Q5_K_M); WARM_POOL_DESIGN + Verification Console durable
  verdicts. Full lines: `archive/handoffs/`.
- i14-i17 (D-0067..D-0070): the 4-lane wave model; warm-pool Stage-1/1.1 + the DURABLE supervisor (`cc296fc`);
  portability shims; widget-04; NEW #32 (`5026e2c`) + #33 greedy MVP (`3264dd5`); SD 3.5 image tier; folded
  generator leads + the track/tracker design review.
- i18-i20 (D-0072/73/75): the res.lease GPU-lease-split PRIMITIVE arc -- R1a 0.2.0 `e701328` (74/74; worker
  report lost to a bridge collapse -> orchestrator verified + shipped) -> R1b 0.3.0 `2d45ffe` (three-identity
  fencing + atomic transition; +36/36; folded red-team pack `b823d9db`) -> R1b' 0.4.0 `f6df675` (incarnation
  ids + exec_lease UUID + two-phase capability + target-fenced `fence-op` + saga journal; matrix A-K 45/45).
- i21 `fo-21-61c7597b` (D-0076): the **R1b CONSUMER wave** (single GPU worker): model.gateway #7 **0.5.0**
  (`0877c70`+`00e5912`; `-UsePoolLeaseSplit` + the real evictor `lib/PoolEvictor.ps1`), agent.local #21
  autoramp **0.2.0**, res.lease **0.4.1**; 0 regression + a FULL live-GPU proof; findings 1/13/14
  CLOSE-ELIGIBLE. PARALLEL frontier SECURITY red-team (pack `5cbe8913`) returned NO with 7 verified must-fix
  blockers -> default-ON re-gated on the SUPERVISOR-HARDENING wave; finding 5 RE-OPENED.
- i22 `fo-22-d2c492e7` (D-0077): the **Phase C TWO-LANE CPU wave** (hardening deferred by Nicholas).
  `track.objects` #33 **0.2.0** (`b60340c`; STABLE-IDENTITY tracker default; greedy byte-identical oracle;
  probe 0 false merges; 169/169 -Live) + NEW **video.timeline #34 0.1.0** (`e8583d1`; 138/138 both envs) ->
  the orchestrator cross-module smoke caught 2 consumer-side divergences -> **#34 0.1.1** (`bad9e27`;
  score_unit honored; scene_index -1; recon 20/20; chain proven on real bytes). Standing smoke rule adopted.

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/`
· leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is
iteration 23.**

## 4. Current frontier: iteration 23 -- pick lanes with Nicholas, then run the 4-lane model

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
(via the supervisor) + be reaped before finalize; reassert the 0-UNMANAGED-orphan check every wave. **Schema
producer/consumer pairs split across isolated workers REQUIRE the orchestrator cross-module smoke at fold
(D-0077) -- budget close-out time for it.**

**Wave loop:** scope lanes (distinct modules) + an optional frontier topic -> fill `FANOUT_AGENT_00N` slots
(section 5) -> author `workers-i23.json` + `task-plan-i23.ps1` (copy `task-plan-i22.ps1`; `-Iteration 23
-MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now`, <=1 gpu, 0 doc
contention, clean preflight -> emit any frontier pack separately -> relay the check-in + every worker prompt +
the pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId fo-23-<id>` until
`ready_for_handoff` -> `-Action handoff` -> verify commits via NATIVE git -> run any cross-module smoke the
wave's shape demands -> fold, mirror the core-docs under the `git` lease, archive the used briefs + reset the
slots -> iterate.

**Candidate-unit menu** (pick with Nicholas each wave):
- **GPU / core-infra (THE top candidate -- re-offer it first): the SUPERVISOR-HARDENING wave** -- fold the i21
  frontier red-team's 10 must-fixes into `model.gateway` #7 (`lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1`
  + `PoolManager.psm1` + `PoolEvictor.ps1`): per-resident suspended-create Job custody + assignment-fatal;
  lifetime supervisor singleton; exact-target + authenticated IPC; no-launch-after-failed/partial-evict-or-CAS;
  pool-lock replace (nonce, no stale-age steal); hard probe deadlines + `unmanaged_vram_pressure`;
  heartbeat-stale watchdog recovery (no live-but-unresponsive fallback; the #00.1 wire-up); kill/reload restart
  reconcile; real exe/model verification. Governing doc: `research/2026-07-31-frontier-supervisor-redteam.md`.
  The hard gate to warm-pool default-ON. SINGLE-worker wave (section 8); mostly off-machine-provable (mock
  supervisor/nvidia-smi seams) but custody + live fault-injection needs the GPU.
- **GPU: a GENERATOR UPGRADE** #22-#25 (SD 3.5 image DONE; next Wan2.1 1.3B video / Stable Audio Open 1.0, or
  the new-engine leads Z-Image-Turbo Q8 / ACE-Step / LTX-Video -- `research/2026-07-30-generator-model-leads.md`);
  or the widget-03 `model.gateway` GPU live-GUI pass (open since D-0060).
- **CPU: the in-proc res.lease client** (the i21 split-overhead finding: ~6-9 child-pwsh spawns/call dominate;
  batched/in-process ops) -- strongly recommended BEFORE any default-ON; single-worker (res.lease is core
  infra). Or the **core-docs SLIM pass** (CURRENT_STATE + MODULE_ROADMAP over budget -- snapshot + compress to
  D-refs; orchestrator-adjacent, can be an orchestrator ad-hoc unit). Or a portability follow-on (core-infra
  00.1 + `ops/*.bat` = single-worker; `$PwshPath` across model-bound entrypoints = GPU-lane ride).
- **Coding: the Phase C video spine** -- the **live `#32->#16->#33->#34` composition wave** (CPU; settle the
  dense-stream gate first) or #33 follow-ons or Verification Console / widget polish / test-coverage.
  (`video.interpret`, pos 22, is model-bound -> a GPU-lane unit.)
- **Frontier: the DENSE-STREAM decision** (sparse-keyframe identity vs a dense low-res tracking stream from
  #32 -- decides the #33/#34/live-composition input contracts; cheap, high-leverage); or a `video.interpret`
  design review; or the as-built supervisor-hardening red-team (AFTER it ships -- the i19->i20 analogue).

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`;
mirrored at `claude/fanout/`) decouple "what a worker must do" from chat pasting: fill a slot at wave scoping
(paste the `plan`-emitted worker prompt into its Unit section, or a tight summary pointing to the emitted copy +
the governing design doc; keep the slot within its 8 KB budget), mirror it, and Nicholas dispatches a fresh
session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant
(section 10). Slot docs also travel to Nicholas as FILES. **The slots were RESET to EMPTY after i22** (used
briefs archived to `archive/fanout-agents/i22-*.md`). Lifecycle: `DOC_PROTOCOL.md` section 6.

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/`
  + `ops/` + `archive/`. Disk is canonical; the attached Claude Project mirrors `core-docs/` (mirror map in
  `DOC_PROTOCOL.md` section 8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-owning-module model
  homes; `_engines\llama.cpp` (b8661, default) + `_engines\llama.cpp-b10092` (CUDA 12.4; ONLY the 9B pins it).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat:
  `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Warm pool / supervisor** (`modules/07-model-gateway/`): `lib/PoolManager.psm1` + `lib/Supervisor.psm1` +
  `Start-GatewaySupervisor.ps1` + `lib/PoolEvictor.ps1` + `WARM_POOL_DESIGN.md`.
- **Video spine:** `modules/32-media-decompose/` + `modules/33-track-objects/` (0.2.0; `SCHEMA_NOTES.md` = the
  emitter contract) + `modules/34-video-timeline/` (0.1.1; `SCHEMA_NOTES.md` notes 34-35 = the reconciliation).
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (CC 7.5), i9-9900KF 8c/16t, 64 GB RAM, Win10 Pro; C: ~67 GB
  free, F: 3.72 TB. Full profile: `TOOL_MODEL_REGISTRY.md`.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1` under
  `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id>
  <timeout> <task.ps1> <maxwait> "<desc>"`. Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps
  ~45 s). Verbs: `submit|wait|run|devship|status`; `EXEC_RT` overrides the runtime dir.
- **Cloud -> device:** gate off-machine FIRST, then `SendUserFile` + `device_commit_files` the changed files onto
  the repo (byte-exact; <=20 MB/file). Large binaries download ON the device via an executor `curl.exe` task.
  `device_bash` cannot delete -- `mv` unwanted files into a `_to_delete\` folder.
- **Device -> cloud bulk reads (i22 tradecraft):** `device_stage_files` can 403 (`session_stale_relogin` -- a
  desktop re-sign-in banner: tell Nicholas, don't retry staging). Fallback: `tar` + `base64 -w0` + cat on-device
  -- any device_bash output over ~60 K chars lands in a local tool-result FILE you slice/decode in cloud bash
  (cap ~262 K chars/call; chunk with `head -c`/`tail -c +N`). Cloud has NO pwsh by default -- a GitHub tarball
  install (`/opt/pwsh/pwsh`, chmod +x) runs the off-machine gates.
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` -- dev.ship verifies sha256 + AST + tests
  FAIL-CLOSED, then commits ONLY the named files under the `git` lease with trailers. **VERIFY the real HEAD via
  native `git log`/`git show --stat`, NOT the dev.ship `committed` field** (D-0072).
- **Author a plan:** write `workers-i<N>.json` + a `task-plan-i<N>.ps1` (copy `task-plan-i22.ps1`), run it,
  confirm `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. `-Action status -PlanId <id>` polls;
  `-Action handoff` emits the Verification Console packet + next prompts. If `status` returns no artifact, read
  the worker reports under `plans/<id>/reports/` directly -- they are the source of truth.
- **Frontier pack:** #31 `pack` op takes `{prompt, question?, paths?}`. Emit, stage, SendUserFile; Nicholas
  couriers + pastes the answer BETWEEN the pack's two `<<<FRONTIER-BRIDGE-ANSWER-...>>>` markers (keep the
  `<!-- pack_id: ... -->` line) into the `.answer.md` return file; run `-Action read-return -ReturnFile <path>
  -ExpectPackId <id>` (expect `captured/valid`, `pack_id_match`) to capture; fold into a research digest + docs.
- **Doc edits + mirror (EOL-safe, fail-closed; full rules in DOC_PROTOCOL.md):** core-docs are CRLF; SOME MODULE
  DOCS ARE LF (e.g. `WARM_POOL_DESIGN.md`, the #34 docs) -- PRESERVE PER-FILE EOL. Either the line-oriented JSON
  applier (i21: `apply-i21-docedits.ps1`) or the i22 pattern: pull byte-exact doc bytes via the tar/base64 path
  above, apply anchored replacements in cloud (assert each anchor count == 1), sha-compare against disk first,
  and `device_commit_files` the whole file back. For LIVE bytes of an already-staged path, NEVER re-stage (the
  stale-stage gotcha) -- read via tar/base64 or an executor task. Commit via an executor `task.ps1`: acquire the
  `git` lease -> `git reset -q` -> `git add -- <named files>` -> assert the staged set -> `git commit -F <msg>`
  -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session: <url>`.
  NEVER `git add -A`. Re-mirror via `project_write` `local_path` (inside the working dir).
- **DECISION_LOG upkeep:** append the new `D-00NN` entry at the bottom of `DECISION_LOG.md` AND append its one-row
  line to `DECISION_LOG_INDEX.md`; mark a superseded predecessor in its INDEX row only. Update `CURRENT_STATE.md`
  by REPLACING sections -- never append `[prior]` chains.
- **Deliver everything to Nicholas as FILES** (SendUserFile) -- prompts, packets, packs.

## 8. Worker-spec rules

- `docs:[]` on EVERY worker (the orchestrator mirrors core-docs; zeroes doc contention).
- <=1 GPU worker per wave; every model module is `parallel_safe:false`; ONLY the GPU lane touches `models.json` /
  model modules.
- Distinct module/area per worker -- never two workers in one module. **A schema PRODUCER and its CONSUMER may
  run as parallel isolated workers ONLY with (a) one governing design doc named as the shared contract, (b)
  per-module SCHEMA_NOTES.md recording every interpretation, and (c) the orchestrator cross-module smoke at
  fold (D-0077).**
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
  never-staged path, or read via tar/base64 / an executor task / device_bash cat. Staging can also 403
  (`session_stale_relogin`) -- section 7 has the full fallback path.
- **Per-file EOL:** core-docs CRLF; some module docs (e.g. `WARM_POOL_DESIGN.md`, modules/34 docs) LF. Match the
  existing EOL.
- **Git discipline:** read-only git over the mount only (huge CRLF-noise M-list -- ignore it); ALL git writes
  through the executor under the `git` lease; NEVER `git add -A`; `project_write local_path` must be inside the
  working dir. `dev.ship` can FALSE-NEGATIVE `committed` (verify real HEAD via native git; clear a stale 0-byte
  `.git/index.lock` via an executor task, assert no `git.exe` running, then re-commit).
- **pwsh 7.4.6 determinism trap (i22):** `[System.Array]::Sort(object[], Comparison[string])` sorts a CONVERTED
  COPY -- the in-place sort is a silent no-op (hashtable-order nondeterminism leaks). Cast to a real `[string[]]`
  first; keep double-run byte-identity gates in every canonical-bytes module. Also: function pipeline output
  pollutes return values (`Write-Host` for progress inside value-returning functions).
- **i21 live-found (supervisor):** consumer identity params must pin BOTH `resident_instance_id` AND
  `instance_generation` through the supervisor launch; a LONG-RUNNING supervisor keeps OLD module code (RESTART
  after shipping supervisor-side changes); `[Console]::Out` bypasses in-process pipeline capture; the 9B returns
  empty content at tiny `-MaxTokens` (use >=64). Driver 591.74 SPILLS a too-big model to system RAM -- "it
  loaded" != "it fits"; the measured-PEAK `required_vram` gate is the only real admission control.
- **Deliver files, not paths** (SendUserFile) -- and keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh`** (desktop app "Add folder", or approve a
device_request_folder_access). That covers reading the repo, driving the executor, staging, and committing. F: is
reached natively by the Windows executor. Machine prerequisite: the executor running (`ops/start-executor.bat` or
the watchdog), heartbeat fresh + `degraded:false`. Computer-use (Task Manager) is only for out-of-band wedge
recovery.

## 11. Box state at handoff (2026-07-31, iteration 22 close-out, D-0077)

Iterations done through 22; i22 was a clean two-lane CPU wave (the Phase C video spine) + an orchestrator
cross-module reconciliation fold. No LIVE res.lease held (durable `gpu-*.fence/.state/.txn` siblings persist by
design -- NOT a held lease); heartbeat `degraded:false`; post-wave recon confirmed 0 UNMANAGED
`llama-server`/python and `ready_for_handoff=true`. **HEAD = the D-0077 i22 close-out docs commit** (worker
parents `e8583d1` #34 0.1.0 -> `b60340c` #33 0.2.0 -> `bad9e27` #34 0.1.1 fold; `master`) -- confirm with
`git log -1`.

**Warm pool + durable supervisor stay DEFAULT-OFF** -- default-ON gates on **(1) the SUPERVISOR-HARDENING wave**
(D-0076; digest `research/2026-07-31-frontier-supervisor-redteam.md`; deferred at i22, re-offer FIRST), **(2)
an in-proc res.lease client**, **(3) a GROWN soak.** The Phase C video spine front half is BUILT + contract-
proven (#32 -> #33 0.2.0 -> #34 0.1.1); remaining: `video.interpret` (pos 22, model-bound), the live composition
wave, and the DENSE-STREAM decision gate (a strong frontier-lane topic). PENDING human live-GUI confirm: the
widget-03 `model.gateway` GPU pass (D-0060). Doc debt: CURRENT_STATE + MODULE_ROADMAP over budget (a named slim
unit). Start at section 2, then run iteration 23 -- pick lanes with Nicholas from the section-4 menu.
