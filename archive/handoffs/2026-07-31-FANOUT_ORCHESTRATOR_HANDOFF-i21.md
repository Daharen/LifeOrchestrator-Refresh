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

- Read section 2 (orient + verify the box), then run **iteration 21** (section 4) -- the R1b CONSUMER wave (GPU, single-worker). Iterations 1-20 are DONE +
  live-confirmed (ledger in section 3; rationale D-0055..D-0070). The 4-lane wave model is VALIDATED (up to 1 GPU
  + 1 CPU + 1 coding + 1 off-box frontier at MaxParallel 3; any lane may be skipped -- i17 ran 3 on-box lanes + a
  folded frontier design review).
- **i17 (D-0070) shipped:** the FIRST generator upgrade -- an **SD 3.5 Medium fp16 quality tier** in `gen.image`
  #23 (`77f1628`+`980dd6d`; `image.sd35-medium` / `-Tier sd35`; Diffusers-native, reuses the speech venv 0.35.2, NO
  new engine; legacy SD1.5 kept the fast default) -- **CAVEAT: NOT a clean 11 GB fit** (torch peaks ~12.06 GB, the
  T5 fp16 spike leans on the driver system-RAM fallback; a sequential-offload OOM ladder is the guaranteed
  fallback); the CPU **interpreter-path** portability shim (config-resolvable system python) into `image.util` #15 +
  `detect.objects` #16 (`58870fb`); and the NEW module **#33 `track.objects`** (`3264dd5`) -- a deterministic
  per-class greedy-IoU tracker (Phase C video position 20). A folded frontier DESIGN review of the tracker
  (`research/2026-07-30-track-objects-design-review.md`) judges greedy-IoU a BASELINE and defines the real
  stable-identity tracker + the track schema `video.timeline` #21 must consume.
- **Warm pool is STILL default-OFF.** With the supervisor done, default-ON now awaits ONLY a **soak** + the
  **res.lease fencing wave** (findings 13/14, single-worker) -- `WARM_POOL_DESIGN.md` section 10. Pick the i18
  units with Nicholas from the section-4 menu.
- Workers use `docs:[]`; YOU mirror the shared core-docs under the `git` lease (section 7). Doc rules --
  budgets, replace-don't-append, archive -- live in `DOC_PROTOCOL.md`; follow them or the docs re-bloat.
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile), never
  as on-disk GUID paths. Worker briefs ALSO go into the numbered
  `core-docs/fanout/FANOUT_AGENT_00N.md` slots (mirrored to the Project) so Nicholas can dispatch a worker by
  telling a fresh session "read claude/fanout/FANOUT_AGENT_00N.md and execute it" (section 5). The slots were
  RESET to EMPTY after i17.
- Box state at handoff: section 11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit
lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize).
The module emits prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors
the core-docs. <=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. The orchestrator NEVER drives
another AI session (D-0051) -- the frontier lane is a couriered pack (D-0052); automated external-AI access
stays OUT.

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md`,
THIS doc, `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (the module manual; its "start MaxParallel 2" sizing is
superseded for this box -- 3 = 1 GPU + 2 CPU is validated, section 4). When editing docs:
`core-docs/DOC_PROTOCOL.md`. For the warm-pool build: `WARM_POOL_DESIGN.md` §6/9/10 (§10 = Stage-1.1 SHIPPED +
the durable-supervisor residual now CLOSED + the residuals still gating default-ON). The gotcha corpus is owned
by `CURRENT_STATE.md` -> Known failures -- read it before touching the box.

Verify the box (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`,
  `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> expect empty (no lease held).
- `git log -1 --format='%h %s'` -> confirm HEAD matches section 11 (read-only git over the mount is fine;
  ALL git writes go through the executor).
`device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor (`exec-job.sh`,
section 7).

## 3. Where things stand

**Now:** modules 0-33 + widgets 01-04 built (one-liners in `CURRENT_STATE.md`); the fan-out loop has run 17
iterations; the Verification Console is the trusted audit surface (durable verdicts); the Governor's
`-AutoRamp` is DEFAULT-ON (M0->M1->S0); the strong tier is Qwen3.5-9B Q5_K_M, GPU-resident on b10092; the 27B
is validated impractical on 11 GB. **Warm-pool Stage-1.1 + the DURABLE Job-Object gateway supervisor are BUILT
but the pool stays opt-in / default-OFF (D-0069).** The Phase C video spine is UNDERWAY (#32 media.decompose + #33 track.objects).
Generator leads for #22-#25 are IN; the FIRST upgrade -- SD 3.5 Medium image tier -- SHIPPED i17
(`research/2026-07-30-generator-model-leads.md`; tracker design review `research/2026-07-30-track-objects-design-review.md`).

**Iteration ledger** (one line each; detail = the D-entry; commits verifiable in git):

- i1-i5 (D-0055..D-0058): res.lease consumers wired (gpu->#7, git->dev.ship, doc:<path>->#20); frontier.bridge #31 built; worker E WEDGED the executor -> single-worker executor+watchdog hardening `e5b93ab`; Governor Phase 2 DETACHED warm server `f8c961a`; Console audit loop validated + #30 packet-input validation `2afd5de`. (Full lines: `archive/handoffs/`.)
- i6-i9 (D-0059..D-0062): Governor Phase 3 -- opt-in `-AutoRamp` (i6 `0005e41`) -> X0/27B rung + logprob-entropy + Console toggle (i7 `830efcc`/`b1f36f0`) -> default-on TRIED then REVERTED + 27B quant NEGATIVE (i8) -> contract-less closing FIXED + `-AutoRamp` DEFAULT-ON `e444851` + 9B Q4->Q5_K_M `0bd2733` (i9). Commits in git.
- i10-i13 (D-0063..D-0065): WARM_POOL_DESIGN.md shipped `c07125f` (mechanism C + a couriered second opinion) -> Verification Console UX `206b2dd` -> verdict save/restore into the WinForms-free core `49f7feb` -> DURABLE verdicts (sidecar keyed by packet_id + auto-load `f3c1ec7`, Console live-confirmed). Full lines: `archive/handoffs/`.
- i14-i15 (D-0067/D-0068): the first two 4-lane waves (3/3 on-box + a folded frontier lane each). i14 `fo-14-5ea064b6`: warm-pool Stage-1 (mech C) `09a7e71` + portability bring-up `ops/setup` `821da16` + widget-04 dashboard `333dac6` + a frontier red-team -> the Stage-1.1 backlog. i15 `fo-15-27a03513`: warm-pool Stage-1.1 hardening `121a0fc` (red-team Criticals closed) + portability follow-ons `c0f8be0` (resolver shim into 14/16) + widget-04 live-GUI confirm+fix `8c1da2e` + folded generator model-leads (`research/2026-07-30-generator-model-leads.md`). Full lines: `archive/handoffs/`.
- i16 `fo-16-f125365c` (D-0069): 3-lane wave. GPU warm-pool **DURABLE Job-Object gateway supervisor** `cc296fc` (owns the server tree in a Job Object ACROSS invocations -> finding 5 durable CLOSED; default-OFF); CPU resolver shim into `doc.io` #20 `8274b9f` (last non-model/non-infra leaf); coding NEW module **#32 `media.decompose`** `5026e2c` (deterministic ffmpeg/ffprobe decompose -> STARTED Phase C video). Full line: `archive/handoffs/`.
- i17 `fo-17-3a115347` (D-0070): **3-lane wave, 3/3 on-box + a folded frontier DESIGN review.** GPU FIRST generator upgrade -- **SD 3.5 Medium fp16 tier** in `gen.image` #23 `77f1628`+`980dd6d` (`-Tier sd35`; Diffusers-native, SD1.5 kept default; ~12 GB torch peak = NOT a clean 11 GB fit, sequential-offload ladder fallback; 50/50 mock + Module 7 42/42 x2); CPU interpreter-path shim into `image.util` #15 + `detect.objects` #16 `58870fb` (#15 54/54, #16 40/44 live, ops/setup 161/175); coding NEW module **#33 `track.objects`** `3264dd5` (deterministic greedy-IoU tracker, Phase C video #20; 79/79 + 79/79); frontier GPT-5.x tracker DESIGN review (pack `794dbdfe`) -> `research/2026-07-30-track-objects-design-review.md` (greedy-IoU = BASELINE; defines the stable-identity tracker + the #21 schema). MaxParallel 3, 0 conflicts, 0 orphans.
- i18 `fo-18-c2d73598` (D-0072): a SINGLE-WORKER core-infra wave -- **R1a**, the res.lease #29 GPU-lease-split KEYSTONE at the PRIMITIVE layer (`e701328`, res.lease 0.2.0: a monotonic `fencing_token` + CAS check/validate; the `exec` vs revocable `residency_pin` split with priority-revocation; a prepared-handoff/evict-before-grant PROTOCOL with a `none`/`mock`/`command` evictor seam; lock-order-inversion rejection + `-AllowLockOrder`; additive/default-off; 74/74). The worker built it but a device-bridge collapse cut off its dev.ship+report -> the orchestrator VERIFIED (74/74) + shipped it. Folded off-box frontier direction review (pack `42ad8308` -> `research/2026-07-30-frontier-review-self-tasking-orchestration.md`): R1a-primitive / R1b-consumer split is SOUND but PROVISIONAL -- **findings 1/13/14 close at R1b, NOT R1a**; R1b needs three-identity fencing (gpu_authority_epoch / resident_generation / exec_lease_id) + one atomic scheduler-owned transition + an adversarial mock + WDDM headroom discipline; R4 -> an ABA proof. #7/#21 consumers + the real evictor + the live-GPU proof = **R1b** (deferred).
- i19 `fo-19-3aa34fe9` (D-0073): a single-worker wave -- the **R1b PRIMITIVE** layer (res.lease 0.3.0, `2d45ffe`; three-identity fencing `gpu_authority_epoch`/`resident_generation`/`exec_lease_id` + the scheduler-owned atomic `-Transition` + an adversarial mock evictor; 74/74 baseline 0-regression + 36/36 adversarial). Worker took the fallback -- #7/#21 consumers + the real evictor + the live-GPU proof did NOT ship. A folded frontier concurrency/safety red-team (pack `b823d9db`) GREW the remainder: the identities are necessary-but-insufficient + the transition is unsafe-as-ordered (grants an ordinary lease before the new resident is healthy/published; side effects must be fenced AT THE TARGET) -> **i20 = R1b'** (primitive hardening: incarnation ids + transition-capability + target-fenced callback CAS + idempotent saga journal + Job-Object contract + adversarial matrix A-K, single-worker CPU). #7/#21 consumers + live proof = a later wave; **findings 1/13/14 stay OPEN.**
- i20 `fo-20-a28f65da` (D-0075): a single-worker CPU wave -- the **R1b' PRIMITIVE HARDENING** (res.lease 0.4.0, `f6df675`; red-team-driven, folding the i19 concurrency/safety red-team pack `b823d9db`): incarnation ids (`owner_incarnation_id`/`resident_instance_id` + `exec_lease_id` as a never-reused UUID -> closes ABA); the hand-off transition re-cast as a two-phase durable saga (the new server starts under a scheduler-only transition capability, NOT an ordinary exec lease; the first usable exec lease publishes only AFTER health = no grant-before-ready); target-fenced side effects (`-Action fence-op` refuses a stale stop/kill/publish that names the wrong `resident_instance_id`); an idempotent saga journal + commit-response idempotency; an oplock-serialized renew that cannot resurrect a revoked lease; a durable per-resource `state_version` for waiters; the off-machine adversarial matrix A-K 45/45. 74/74 baseline + 36/36 v0.3 + 45/45 v0.4, 0 regression, additive/default-off/backward-compatible. The primitive is now SAFE to build on; **#7/#21 consumer adoption + the real evictor + the live-GPU proof = the R1b CONSUMER wave (i21); findings 1/13/14 STAY OPEN until then.**

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts
`.../runtime/artifacts/<invocation_id>/` · leases `.../29-resource-lease/runtime/leases/`.

Waves + ad-hoc commits share one counter; **the next wave is iteration 21 -- the R1b CONSUMER wave (i20 shipped the R1b' primitive hardening `f6df675`, res.lease 0.4.0).**

## 4. Current frontier: iteration 21 -- the R1b CONSUMER wave, then back to the 4-lane model (validated at i14-i17, D-0067..D-0070)

Nicholas's directive: up to FOUR lanes per wave; any lane may be skipped (i16 skipped frontier; i17 ran all four). Every lane is
human-dispatched.

- **GPU lane (<=1 per wave -- HARD CLAMP).** One Cowork worker on a GPU-bound unit (any llama-server / CUDA
  pipeline on the 11 GB GPU; every model module is `parallel_safe:false`). More GPU work = serialize across
  waves. ONLY this lane may touch model modules / `models.json`. Leases gpu->git.
- **CPU lane (>=1).** One Cowork worker on a CPU-only module/infra unit. Lease git.
- **Coding lane (CPU, >=1).** A broad-remit CPU worker -- refinement, interfaces, widgets, tests, or a NEW
  deterministic module -- in a DISTINCT module/area from the CPU lane (never two workers in one module). Lease git.
- **Frontier-review lane (off-box, OPTIONAL).** NOT a Cowork worker: the orchestrator emits a frontier.bridge
  #31 `pack` (`{prompt, question?, paths?}`); Nicholas couriers it to ChatGPT Pro / GPT-5.x and pastes the
  answer back; the orchestrator runs `read-return`, captures it under
  `modules/31-frontier-bridge/runtime/artifacts/<id>/` and folds it into docs. No lease; fully parallel.

**Clamps.** <=1 GPU worker, always. **1 GPU + 2 CPU = MaxParallel 3** is the validated ceiling (held clean
under real 3-worker load at i14 AND i15; i16 ran 3 lanes clean); grow CPU workers only while the executor
heartbeat stays healthy. The `git` lease serialises all commits (fast). `docs:[]` on all workers -> doc
contention 0 by design. Wedge risk scales with concurrency: persistent llama-servers MUST launch DETACHED and
be reaped before finalize (D-0055/56); reassert the 0-orphan check every wave.

**Wave loop:** scope the lanes you want (distinct modules) + an optional frontier topic -> fill the
`FANOUT_AGENT_00N` slots (section 5) -> author `workers-i18.json` + `task-plan-i18.ps1` (copy
`task-plan-i17.ps1`; `-Iteration 18 -MaxParallel 3`; `gpu:true` only on the GPU worker) -> run `plan` via the
executor; confirm `dispatch_now` <= 3, exactly <=1 gpu, 0 doc contention, clean preflight -> emit any
frontier pack separately -> relay the check-in + every worker prompt + the pack as FILES + slot docs ->
workers run + report -> poll `-Action status -PlanId fo-18-<id>` until `ready_for_handoff` -> `-Action
handoff` (emits the Verification Console packet) -> fold any frontier answer, mirror the core-docs under the
`git` lease, archive the used briefs + reset the slots -> iterate.

**Candidate-unit menu** (pick with Nicholas each wave):
- GPU: (a) **warm-pool SOAK -> flip default-ON** (supervisor DONE; needs the soak + the res.lease fencing wave
  first) -- THE standing candidate; (b) **a GENERATOR UPGRADE** #22-#25 (SD 3.5 Medium image tier DONE i17;
  next Diffusers-native Wan2.1 1.3B video / Stable Audio Open 1.0 audio, or the leads Z-Image-Turbo Q8 / ACE-Step /
  LTX-Video which need a new engine/venv -- `research/2026-07-30-generator-model-leads.md`); (c) the b10092 universal-engine probe (VLM = the gating test).
- CPU: (a) **the res.lease #29 fencing infra wave** (findings 13/14: a monotonic fencing token + lock-order-inversion
  rejection) -- a SINGLE-worker wave (section 8), the OTHER gate to default-ON; (b) a remaining portability
  follow-on, each its own wave (`$PwshPath` resolution across ~15 model-bound entrypoints + harnesses; core-infra
  paths 00.1 + `ops/*.bat`; an interpreter-path config-schema for #15/#16); (c) a non-model hardening pass (doc.io
  #20 / route.tools #27 / fs.manage #28).
- Coding: (a) **continue the Phase C video spine** -- **`video.timeline` #21** (arch 21: fuse
  transcription+scenes+OCR+keyframes+detections+tracks -> searchable timeline; it should CONSUME the frontier-reviewed
  track schema in `research/2026-07-30-track-objects-design-review.md`) or **`video.interpret` #22**; OR the
  **`track.objects` #33 refinement wave** (scene-boundary reset + elapsed-time aging + global Hungarian assignment +
  gated centroid fallback + canonical-JSON determinism, per the folded frontier review); or #32/#33 follow-ons; (b) the
  widget-03 `model.gateway` GPU live-GUI pass (open since D-0060; needs the GPU, so run it AS the GPU lane, not
  alongside one); (c) Verification Console / widget-04 polish; (d) test-coverage + interface cleanups.
- Frontier: (a) a **red-team / security review of the shipped durable supervisor** (`lib/Supervisor.psm1` +
  `Start-GatewaySupervisor.ps1`) before default-ON; (b) a generator-upgrade engine sanity check
  (stable-diffusion.cpp vs ComfyUI vs Diffusers; venv isolation; Turing FP16-only); (c) a design review of `video.timeline` #21 (schema +
  fusion), building on the i17 tracker review; (d) a second opinion on any risky call.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`core-docs/fanout/FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template
`FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`) decouple "what a worker must do" from chat
pasting: fill a slot at wave scoping (paste the `plan`-emitted worker prompt into its Unit section -- for a
very long unit, a tight summary pointing to the emitted copy + the governing design doc is fine; keep the slot
within its 8 KB budget), mirror it, and Nicholas dispatches a fresh Cowork session with "Read the Project doc
`claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (section 10). Slot docs also
travel to Nicholas as FILES. **The slots were RESET to EMPTY after i16** (used briefs archived to
`archive/fanout-agents/i16-<id>.md`). Lifecycle (READY/DISPATCHED/EMPTY): `DOC_PROTOCOL.md` section 6.

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` +
  `widgets/` + `ops/` + `archive/`. Disk is canonical; the attached Claude Project mirrors `core-docs/` for
  desktop-less sessions (mirror map in `DOC_PROTOCOL.md` section 8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-owning-module
  model homes; `_engines\llama.cpp` (b8661, default) + `_engines\llama.cpp-b10092` (CUDA 12.4,
  self-contained; ONLY the 9B strong tier pins it via `engine_path`).
- **Executor:** `modules\00-bootstrap-executor\runtime\` (staging -> pending -> running -> completed/failed);
  driven via `exec-job.sh`. Heartbeat: `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Portability toolkit:** `ops/setup/` (`LifeorchConfig.psm1` + `setup.ps1` + `Confirm-StagingPlan.ps1` +
  `VERIFY-RUNBOOK.md`; out under `ops/setup/out/`, gitignored). **Warm pool** (`modules/07-model-gateway/`):
  `lib/PoolManager.psm1` (integrity) + `lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1` (durable supervisor)
  + `WARM_POOL_DESIGN.md`.
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
  `commit_message`-with-trailers, `check_orphans`. Full schema: `Invoke-DevShip.ps1` header + `00-bootstrap-executor/README.md`.
- **Author a plan:** write `workers-i<N>.json` (per-worker `{id,label,unit,gpu?,docs:[],needs_git?,skill_id?,
  skill_dir?,inputs?,notes}`) + a `task-plan-i<N>.ps1` (copy `task-plan-i16.ps1`), run it, confirm
  `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. `-Action status -PlanId <id>` polls;
  `-Action handoff` emits the Verification Console packet + next prompts. If `status` returns no artifact,
  read the worker reports under `plans/<id>/reports/` directly -- they are the source of truth.
- **Frontier pack:** frontier.bridge #31 `pack` op takes `{prompt, question?, paths?}`. Emit, stage,
  SendUserFile; Nicholas couriers + pastes the answer into the pack's `.answer.md` return file; run `-Action
  read-return -ReturnFile <path> -ExpectPackId <id>` to capture; fold into the relevant doc/decision.
- **Doc edits + mirror (EOL-safe, fail-closed; full rules in DOC_PROTOCOL.md):** core-docs are CRLF; SOME MODULE
  DOCS ARE LF (e.g. `WARM_POOL_DESIGN.md`) -- PRESERVE PER-FILE EOL. Edit fail-closed (assert each anchor occurs
  exactly once; atomic write) -- a JSON-driven `[IO.File]` applier asserting anchor-count==1 per edit is the
  low-risk pattern (i16). For LIVE bytes of an already-staged path, copy to a FRESH never-staged dir first (the
  stale-stage gotcha) or read via an executor task / device_bash cat. Commit via an executor `task.ps1`: acquire
  the `git` lease -> `git reset -q` -> `git add -- <named files>` -> assert exactly those staged -> `git commit
  -F <msg>` -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session:
  <url>`. NEVER `git add -A`. Re-mirror via `project_write` `local_path` (inside the working dir).
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
  `{prompt,question?,paths?}`; a mismatch surfaces as `input_warning`). A brand-new module has no skill.json
  yet -- OMIT `skill_id`/`skill_dir` for it (like the i16 coding lane) to avoid a preflight resolution warning.
- Single-worker waves for core infra (executor/watchdog, dev.ship, orchestrate.fanout itself, res.lease #29).
- Workers acquire leases in gpu -> git -> doc order, do ONE unit, ship via dev.ship, then
  `-Action report -State done`. (A build-then-verify GPU unit may take git for the commit, RELEASE it, then
  take gpu ONLY for the live verify -- never hold the GPU idle waiting on git.)

## 9. Gotchas (the load-bearing five -- full corpus: `CURRENT_STATE.md` -> Known failures)

- **The wedge (hardened D-0055/56 -- respect it anyway):** a task that BLOCKS holding a persistent llama-server
  orphans it and can livelock the executor while the heartbeat stays fresh. Launch persistent servers DETACHED;
  reap before finalize; assert 0 orphans every wave (the i16 durable supervisor owns its tree in a Job Object, so
  "0 orphaned" = 0 UNMANAGED). If wedged: kill the orphan OUT-OF-BAND (Task Manager -> `llama-server.exe`); the
  executor self-recovers.
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes. Always
  stage a FRESH never-staged path (copy to an `editsrc/` or `docmirror-i<N>/` dir first), or read via an
  executor task / device_bash cat.
- **Per-file EOL:** core-docs are CRLF; some module docs (e.g. `WARM_POOL_DESIGN.md`) are LF. Match the
  existing EOL when editing; assert no mixed EOL before committing.
- **Git discipline:** read-only git over the Linux mount only (it shows a huge CRLF-noise M-list -- ignore it,
  the executor's native git sees the true state); ALL git writes through the executor under the `git` lease;
  NEVER `git add -A`; `project_write local_path` must be inside the working dir, not /tmp. A stale
  `.git/index.lock` (orphaned, 0 bytes, no git.exe running) can be cleared via an executor task under the lease.
- **Deliver files, not paths** (SendUserFile) -- and keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh`** (desktop app "Add folder", or approve a
device_request_folder_access). That covers reading the repo, driving the executor, staging, and committing.
F: is reached natively by the Windows executor, not by the session. Machine prerequisite (not per-session):
the executor process running (`ops/start-executor.bat` or the watchdog), heartbeat fresh + `degraded:false`.
Computer-use (Task Manager) is only for out-of-band wedge recovery.

## 11. Box state at handoff (2026-07-31, iteration 20 close-out, D-0075)

**i18-i20 update (authoritative = section 3 ledger + CURRENT_STATE):** i18 shipped R1a (res.lease 0.2.0, `e701328`), i19 the R1b primitive (0.3.0, `2d45ffe`), i20 the R1b' primitive hardening (0.4.0, `f6df675`; red-team-driven, 74/74 + 36/36 + 45/45, 0 regression). HEAD = the D-0075 i20 close-out docs commit (`master`; confirm `git log -1`). The res.lease primitive is now hardened + safe to build on; **findings 1/13/14 STAY OPEN** -> they close at the **R1b CONSUMER wave** (i21, GPU single-worker: #7 PoolManager + #21 governor adoption + the real nvidia-smi evictor + the live-GPU swap/eviction proof), then a soak, then warm-pool default-ON. The paragraphs below predate i18 and are retained as history.

Iterations done through 17; i17 was a clean 3-lane wave (3/3 on-box) + a folded off-box frontier design review. No
res.lease held; heartbeat `degraded:false`; post-wave recon confirmed 0 orphaned `llama-server`/python and
`ready_for_handoff=true`. HEAD = the D-0070 i17 close-out docs commit (worker parents `3264dd5` track.objects ->
`58870fb` interpreter shim -> `77f1628`+`980dd6d` gen.image SD3.5 -> `7d68c58` i17 slots, `master`) -- confirm with
`git log -1`. **Warm-pool Stage-1.1 + the DURABLE Job-Object supervisor are BUILT but the pool STAYS default-OFF**
-- do NOT enable until a soak + the res.lease fencing wave (13/14) land (`WARM_POOL_DESIGN.md` s10). **finding 5
durable = CLOSED.** The **Phase C video spine is UNDERWAY** -- #32 `media.decompose` + #33 `track.objects` built
(next: `video.timeline` #21 + `video.interpret` #22; the i17 frontier review defines the track schema #21 must
consume + the track.objects refinement roadmap). **First generator upgrade SHIPPED:** SD 3.5 Medium fp16 image tier
in `gen.image` #23 (opt-in `-Tier sd35`; NOT a clean 11 GB fit, ~12 GB torch peak). PENDING human live-GUI confirm:
the widget-03 `model.gateway` GPU pass (D-0060). (This section's body predates i18; see the i18-i20 update at the top of section 11 + section 3's ledger. Start at section 2, then run iteration 21 -- the R1b CONSUMER wave.)
