# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture, not history. Keep it compact.

History lives elsewhere: **`DECISION_LOG.md`** (read **`DECISION_LOG_INDEX.md`** first, pull by ID), **git**, and
**`archive/`**. **Rule: NEVER grow `[prior]` accretion chains** — replace a stale statement in place, cite `D-####`
if the reason matters. A `CURRENT_STATE.json` counterpart = PCB FO-2 (post-i47-pass).

Owned elsewhere, don't duplicate: `TOOL_MODEL_REGISTRY.md` (tools/models/hardware) · `MODULE_ROADMAP.md` (build
order/status/follow-ons) · `REVIEW_QUEUE.md` (queue) · `FANOUT_ORCHESTRATOR_HANDOFF.md` (orchestrator ops) ·
`ADAPTIVE_RESOURCE_GOVERNOR.md` (governor) · `ARCHITECTURE_MAP.md` (destination).

## Phase + active work

- **Phase (D-0080): building the Collective Agent** on cognitive virtual memory (Nicholas's directive,
  `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`): external authoritative memory
  (repo/SQLite/artifacts) + disposable model contexts; a deterministic coordinator hands a model a small
  task-specific packet; specialists execute; evaluators verify; success becomes reusable procedure. Nicholas is
  manager. RTX 2080 Ti (one ~7 GB resident; a 9B executive) = build target; RTX PRO 6000 (96 GB) = horizon.
  The D-0050 offload/verify-cost AUDIT LOOP still governs: offload only what is cheaper to VERIFY than to do.
- **Memory architecture (D-0090) = the design target:** `MEMORY_ARCHITECTURE.md` + `MEMORY_BENCHMARK.md` + the
  seam audit. Stored memory may grow indefinitely while working context stays BOUNDED. Field authorities:
  `MEMORY_CONTRACT.md` (v0.1.1 + A1-A6) + `CONTEXT_PACKET_CONTRACT.md` (0.2 + i32/i33/i34 + s9 R-1).
- **Memory subsystem BUILT + Tier-1 ACCEPTED.** Waves i25-i39 shipped #35 embedding.local, #36 artifact.search
  (now **0.7.0**, fast-beam ranking), #37 retrieval.eval (eval 0.8.0 + the Tier-1 rehearsal harness), #38
  repo.intel, #39 episode.record 0.1.1, #40 context.compiler (now **0.9.0**: hierarchy port + R-1 router +
  working-memory hydration), #41 skill.card 0.2.0, #42 working.memory 0.1.0. **Project `tier1_accepted` = TRUE**
  (i36, D-0102: 11/11 s10 criteria over a distinct 6-package foreign corpus at 100x leaf span). Fast-beam recall
  lever shipped i39 (D-0108; hpr ~2x; guaranteed+packet recall stay 1e6).
  Arc detail: the index; per-module state: `MODULE_ROADMAP.md`.
- **P0-1 action-authorization gate (#43): `build_status=build_complete | p0_1_gate_status=PASS | activation_status=prohibited`.** #43 0.6.0 (`10d0d1e`, i42) is a RATIFIED DESIGN pass -- round-5 independent review PASS -> s7 `p0_1_gate_status=pass` (D-0118, M2-D, pack `6bb613ea`; arc detail D-0116/18). Verified x2 byte-identical (364/364; bundle `3b5d62f4`); A06 denies every authentic packet; `non_execution:true` holds. **Activation stays PROHIBITED** -- a design pass, NOT an activation grant.
- **i46 CLOSED (D-0130/D-0131, plan `fo-46-6dd32d37`; Nicholas DIRECTIVE-HIJACKED):** SHIPPED NEW **modules/44 `project.map` 0.1.0 -- the Project Comprehension Bootstrap (PCB)**: deterministic fail-closed system map + L1 cards + a generated <=20 KB `BOOT_PACKET.md`; judgment enters ONLY via validated evidence-pointed claims; built ALONGSIDE the untouched legacy handoff. Independent re-verify 49/49 + -Live smoke + selftest; claims folded 0-findings. **i47 = the FROZEN legacy-vs-PCB migration gate** (`modules/44-project-map/eval/I47_EVAL_PACKET.md`) after the mandate-02 sunset report.
- **FROZEN / deferred (D-0080):** durable-supervisor / warm-pool hardening (D-0079 GATE-NO stands; classic
  detached-warm is the trusted default); generator upgrades; `video.interpret` + live composition; deep
  real-time perception (arch 27-49); broad training.
- **Fan-out loop:** 46 iterations run via `orchestrate.fanout` #30 over `res.lease` #29; workers hand-dispatched
  into fresh Cowork sessions. Ledger + wave model: **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **Boundary (D-0051, amended by D-0080):** the orchestrator never drives another *external/frontier* AI session
  (human-couriered only); a deterministic LOCAL coordinator IS authorized to spawn local contexts (Priority 10).
  In-session cloud subagents are PERMITTED inside the boundary (D-0119); frontier access stays human-couriered.

## Adaptive Resource Governor (agent.local #21)

Design + rationale: **`ADAPTIVE_RESOURCE_GOVERNOR.md`**. Runtime facts:

- Phase 1 DONE (D-0043): the DECISION floor is **mid-only (3B)** — a low `[tiny,weak,mid]` floor made the 3B
  judge-and-anchor on weak answers. Phase 2 DONE (D-0057, warm server); Phase 3 Stage-1 (D-0059) + the Stage-2
  slice (D-0060) DONE.
- **`-AutoRamp` is DEFAULT-ON (D-0062).** Monotonic model-affine epochs **M0 -> M1 -> S0**; the deadline-gated
  **X0/27B** one-shot recovery rung is opt-in via **`-AllowLegacy27B`**. `-NoAutoRamp` / `-AutoRamp:$false`
  reproduce the strict floor byte-for-byte.
- Closing: a goal with a **pre-frozen `lifeorch.goal_verification/0.1` success contract** closes on the
  contract; a **contract-less** goal closes via the **D-0046 terminator** (M0 closes once >=1 required
  side-effecting tool succeeds). The D-0061 contract-less loop-to-max_steps regression is FIXED (D-0062).
- **`-Profile floor` is the reliable end-to-end path** (`frugal|floor|max`). **Open residual: `-Profile max` does
  NOT land** — at `gen_tier=strong` the 9B arg-gen returns non-JSON (`arg_parse_failed`) every step (a 9B/gateway
  defect, NOT the terminator; measured on Q4, not re-tested since Q5_K_M — D-0046/D-0062).
- Opt-in logprob-entropy soft signal (clean per-token logprobs on BOTH builds b8661 + b10092, D-0060);
  `-AutoRamp` is exposed in the Local Agent Console (widgets/01) as a toggle + trace render.

## Model stack (full inventory: `TOOL_MODEL_REGISTRY.md`)

- **Strong tier = `llm.strong.qwen3p5-9b` — Qwen3.5-9B Q5_K_M, GPU-resident** (~7.11 GB, `ngl 99`; 2902 MiB free
  @ctx 8192, probe `m10-warmpool-probe-002`) -> **GPU-bound ~68 tok/s** (at Q4), clean terse JSON. Q4->Q5_K_M for
  fidelity + KV headroom (D-0062); live S0 6/6 @2048 tok. **Q4 retained `wired:false`** = one-flip rollback.
- **Engine:** the 9B is a hybrid attention-SSM arch **b8661 cannot load**, so its entry pins `engine_path` to
  a side-by-side **llama.cpp b10092 (CUDA 12.4, self-contained)**; **every other tier stays on b8661**.
- **`no_think: true`** on the 9B entry -> the gateway appends ` /no_think`; without it the default flags leave
  reasoning ON and it returns empty content at `finish=length`.
- **The 27B is RETAINED but validated IMPRACTICAL (D-0061):** no Qwen3.5-27B quant fits GPU-bound on 11 GB —
  confirmed by the couriered frontier report (`core-docs/research/2026-07-28-frontier-local-model-selection.md`).
  Reachable via `-Model` / the X0 rung only; the resident 9B is the effective top rung.
- **Decision floor = mid (3B)**; strong is GENERATION-only.
- Warm multi-model pool: Stage-1.1 hardened (i15, D-0068) + a **DURABLE gateway supervisor (i16, D-0069, skill
  0.4.0; hardened 0.6.0 i23, D-0078) — still DEFAULT-OFF** (see Known failures): `WARM_POOL_DESIGN.md` §6/9/10.
  Measured: one ~7 GB model fits the GPU at a time; swap GPU-upload-bound (~1.6 s->3B, ~4.1 s->9B); same-model
  reuse ~1 ms; all GGUFs (28.5 GiB) fit 64 GB RAM.

## Repo / working dirs

- **Repo (canonical):** `C:\Users\just_\LifeOrchestrator-Refresh\` — git-initialized; `core-docs/` +
  `modules/<NN>-<name>/` + `widgets/<NN>-<name>/` + `archive/`.
- **Large-data home:** `F:\My_Programs\...\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\`; shared
  llama.cpp engines under `_engines\`.
- **Reference sources (NOT built here):** the earlier `LifeOrchestrator\repo` (fold in later) + the **Project
  Proteus** game (`Project-Proteus-src`).
- The attached Claude Project **mirrors** `core-docs/`; disk wins on disagreement.

## Executor status

- MVP complete, **running** (`modules/00-bootstrap-executor/`, pwsh 7.4.6, host `DESKTOP-PF5FFMF`). Verify the
  CURRENT instance via `runtime/control/heartbeat.json` (`at_utc` fresh, `degraded:false`, `poll_error_streak:0`,
  `stuck_finalize_count:0`) — **trust the heartbeat, not the process list** (the pwsh shim shows as `dotnet.exe`).
- Markers: `runtime/control/heartbeat.json` + `last-exit.json`.
- **Watchdog (#00.1) is available but session-scoped, not persistent** (D-0013): launch
  `ops/start-watchdog.bat` before any long unattended wave.
- Crash history: a transient file-lock crash 2026-07-24, self-healed in-process (Known failures); the
  orphaned-llama-server **wedge** (D-0055/D-0056), closed by iter-3 hardening + DETACHED persistent servers.
- **Model servers: `model.gateway` #7 keeps a DETACHED warm `llama-server`** (residency-key match under the
  `res.lease` **gpu** lease; D-0057; warm reuse ~1 ms vs ~1200 ms cold). **Optional durable supervisor (default-
  OFF, `-UseSupervisor`)**. **`image.interpret` #17 is transient.** Any persistent server launches detached + is
  reaped before finalize; assert 0 UNMANAGED orphans every wave.

## Completed modules

Detail + follow-ons per module: `MODULE_ROADMAP.md`; producer status: `REVIEW_QUEUE.md`; invocation +
registry facts: `TOOL_MODEL_REGISTRY.md`. Roster (all MVP-complete unless noted):

- **Infra:** #0 exec.bootstrap (+ `dev.ship`, D-0048) · #00.1 exec.watchdog · #1 skill.bootstrap (contract
  v0.2) · #29 res.lease (gpu/git/doc leases; the GPU-lease-split primitive R1a->R1b->R1b' hardened + consumer-
  adopted + live-proven, D-0071..D-0076) · #30 orchestrate.fanout · #31 frontier.bridge (`pack` takes
  `{prompt, files}`, D-0057).
- **Observation/UIA:** #2 fs.observer · #3 proc.observer · #4 uia.inspector · #5 uia.actor · #6 capture.screen.
- **Model core:** #7 model.gateway (detached warm server; warm pool + durable supervisor default-OFF) · #8
  classify.batch · #9 review.processor · #19 logic.escalator · #20 doc.io (+ portability resolver shim) · #21
  agent.local (`-Route`, D-0046 terminator, `-Profile`, `-AutoRamp`; the closed `tools.json` registry IS the
  sandbox) · #27 route.tools · #28 fs.manage.
- **Audio:** #10 audio.ingest · #11 speech.stt · #12 speech.tts · #13 voice.live.
- **Perception:** #14 ocr.layout · #15 image.util · #16 detect.objects · #17 image.interpret · #18 image.index.
- **Generators (user track):** #22 gen.audio · #23 gen.image (+SD 3.5 Medium fp16 tier, i17) · #24 gen.music ·
  #25 gen.video.
- **Video spine (Phase C, front half BUILT):** #32 media.decompose (arch 19, D-0069) · #33 track.objects 0.2.0
  (stable-identity tracker, arch 20) · #34 video.timeline 0.1.1 (canonical `lifeorch.video_timeline/0.1`;
  consumes #33's contract exactly, proven on real bytes; arch 21). Next: `video.interpret` (pos 22) Proposed;
  the DENSE-STREAM decision gate (Unresolved questions) precedes any live-composition input-contract freeze.
- **Memory subsystem (#35-#43, D-0082..D-0108):** #35 embedding.local 0.1.0 (dim-1024 provider) · #36
  artifact.search **0.7.0** (SQLite catalog + FTS5 + record envelope + Tier-1 hierarchy nodes + `get-record` +
  fast-beam shortlist/descend ranking) · #37 retrieval.eval **0.8.1** (selpol 1.2.0 canonical `selpol_rrf_v1`; eval
  wired-descend; the ~200MB Tier-1 rehearsal harness; version single-source + permanent drift assertion, i40) · #38 repo.intel
  0.1.0 (typed-record producer) · #39 episode.record 0.1.1 · #40 context.compiler **0.9.0** (three-region
  context_packet/0.2; hierarchy port; R-1 born-instrumented router; working-memory hydration; flat compile
  byte-identical back to 0.7.0) · #41 skill.card 0.2.0 · #42 working.memory 0.1.0 (per-task store, CAS heads,
  ns isolation) · **#43 action.authz 0.4.0** (P0-1 deny-by-default reference monitor + injection suite;
  DESIGN-ONLY; exact-closure-complete, gate incomplete pending ratification — see Phase).
- **#44 `project.map` 0.1.0** (i46, D-0130/31) -- the PCB: fail-closed map/claims/boot-packet compiler. `MODULE_ROADMAP.md` #44.
- **NOT built:** #26 agent.coding — designed + DEFERRED (D-0037; no safe code-exec substrate on this box).
- **Widgets (native + `launch.bat`, D-0038):** 01 Local Agent Console · 02 Module Launcher · 03 Verification
  Console (durable verdicts, D-0065) · 04 Fan-out Wave Dashboard (live-GUI confirm DONE) · 05 Provenance Map
  (audit tier A1) · 06 Compile Trace Console (audit A1) · 07 Audit Timeline+Tournament (audit A2) · 08 Live-Run Audit Pathway (LRAP, i45). Widgets
  05/06/07 live-GUI DONE (i43); Widget 08 SHIPPED + verified 87/0/0, NOT yet phenomenological (D-0125; P9 open; poser SHIPPED D-0127; live-click confirm PENDING D-0129).

**Phase A complete** (0-25 + 00.1; #26 deferred); generator track complete; **Phase B Widgets 01-08 shipped;
Phase C video spine front half built; memory subsystem #35-#43 built, Tier-1 accepted.**

## Installed dependencies (verified on this machine)

- **PowerShell 7.4.6** — a .NET global tool at **`C:\Users\just_\.dotnet\tools\pwsh.exe`**. The **latest**
  `PowerShell` global-tool package is malformed (no tool manifest) — **pin a version**.
- **.NET SDK 9.0.100** (`C:\Program Files\dotnet\dotnet.exe`) · **git** on PATH · **winget** present ·
  **choco** absent. **Not admin. No system-wide `pwsh`** — only the user `~\.dotnet\tools` entry.
- **ffmpeg / ffprobe 8.1** (Gyan.dev `full_build`), `ffmpeg` on PATH at
  `C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe`; full encoder set. **`ffprobe` on PATH is
  shadowed by a Python shim — see Known failures.**
- **WinForms + STA runspace** work in the dotnet-tool pwsh (an STA runspace hosts a Form + `Application.Run`).
- **Windows PowerShell 5.1** (5.1.19041.6456) — the ONLY runtime here that can load the WinRT
  `Windows.Media.Ocr` projection (the `ocr.layout` #14 worker). **5.1 reads a BOM-less `.ps1` as ANSI — see
  Known failures.**
- **Windows.Media.Ocr** (system WinRT OCR) — words + `BoundingRect` + reading-order lines + `TextAngle`;
  `en-US`; `MaxImageDimension=10000`; ~74 ms on a 700x220 fixture. No install/admin/GPU/network.
- **Tesseract OCR** at `C:\Program Files\Tesseract-OCR\tesseract.exe` — installed, **declared not wired**
  (`ocr.tesseract`), a future second `ocr.layout` engine.
- **Pillow + numpy** — **system python** `…\Python312\python.exe`: PIL 10.2.0 + numpy 1.26.4 + cv2 4.9.0;
  **speech venv** (F:): PIL 12.2.0 + numpy 2.4.4 — the numpy-DCT pHash is identical across both. `image.util`
  #15 uses the **system python** (CPU-only -> genuinely parallel-safe).
- **onnxruntime** — system python: onnxruntime-gpu 1.17.1 + onnxruntime-directml 1.17.1 + torch 2.2.1 +
  torchvision 0.17.1. `detect.objects` #16 requests **`CPUExecutionProvider`** by default.
- **diffusers 0.35.2 in the speech venv** (torch 2.11+cu128, transformers 4.57.3, + `sentencepiece` 0.2.2 for
  the SD 3.5 T5 tokenizer) powers `gen.image`/`gen.video`. The **system python is torch 2.2.1+cpu (no CUDA)** —
  image/video gen runs under the speech venv only.

## Installed local models (summary)

Full inventory — paths, sha256, licences, quants, tuning: **`TOOL_MODEL_REGISTRY.md`** + `models.json`.
Models live in per-owning-module F: homes (D-0028); engines under `_engines\` (**b8661** = every tier but the
9B; **b10092** = the 9B only). Decision-relevant facts:

- **strong** = Qwen3.5-9B **Q5_K_M**, 7.11 GB, GPU-resident, `no_think`, b10092; Q4 retained `wired:false`.
- **mid (3B) = the decision floor**; tiny 0.5B / weak 1.5B for bulk work.
- The **27B is retained but impractical** (D-0061): `-Model` / `-AllowLegacy27B` only; `-LoadTimeoutSec ~300`.
- Non-LLM models (whisper STT, Qwen3-TTS x2, YOLOX x2, VLM, SD 1.5, MusicGen, AnimateDiff-Lightning,
  embedding) are `wired:false` **for the gateway** by design — each resolved by its owning module.
- **`gen.image` #23 has an SD 3.5 Medium fp16 QUALITY tier (i17, D-0070)**, opt-in `-Tier sd35` (default stays
  `image.sd15`). **NOT a clean 11 GB fit — see Known failures.**

## Available hardware (measured 2026-07-24)

- **CPU** Intel i9-9900KF (8c/16t @3.6 GHz) · **RAM** 64 GB · **GPU** NVIDIA RTX 2080 Ti **11 GB VRAM** (CUDA,
  driver 591.74, cc 7.5) · **OS** Windows 10 Pro 19045 x64. Host `DESKTOP-PF5FFMF`, user `just_`.
- **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**), E: 858 GB (~534 GB free), **F: 3.72 TB
  (~1.78 TB free)** = the large-data home. (No D: on this box.)

## Known working invocation paths

- **Every module:** `pwsh -NoProfile -File modules\<NN>-<name>\Invoke-<Name>.ps1 <named params>` (or
  `-InputsJson '<json>'`), or via the Module 1 wrapper `Invoke-Skill.ps1 -SkillDir <dir>`. Per-module params:
  each module's `README.md` / `skill.json`; model resolution: `TOOL_MODEL_REGISTRY.md`.
- **Through the executor:** submit a task package whose `task.ps1` calls either entrypoint; the envelope lands
  in `runtime/completed/<task_id>/stdout.txt`.
- **Job-runner** (`modules/00-bootstrap-executor/exec-job.sh`): `devship <id> <inputs.json> <timeout>` ships a
  unit; `run <id> <timeout> <task.ps1> <maxwait> "<desc>"`; `wait <id>` re-waits a long/GPU job (device_bash
  caps at ~45 s).
- **Direct pwsh:** `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- **User ops (click-to-run):** `ops/*.bat` (executor start/stop/status; output to `ops/out/`). **Watchdog:**
  `ops/start-watchdog.bat` / `stop-watchdog.bat` / `recover-executor.bat [-Force]`.
- Examples: `07-model-gateway\Invoke-ModelGateway.ps1 [-Model <id>|-Tier tiny|weak|mid|strong] -Prompt '<s>'` ·
  `21-agent-local\Invoke-AgentLocal.ps1 -Goal '<s>' -Route [-Profile frugal|floor|max]` ·
  `32-media-decompose\Invoke-MediaDecompose.ps1 -Path <video> [-Audio] [-Keyframes N] [-Scenes]` ·
  `06-capture-screen\Invoke-CaptureScreen.ps1 [-Target monitor|window|app|region]`.

## Current tests

Standing gates, in order: **(1) the off-machine cloud gate FIRST**, **(2) `-Live` on the Windows executor**,
**(3) `dev.ship`** (sha256 + AST + tests, fail-closed). **Mock/API gates MISS rendered-UI defects and
real-model failures** (D-0049/D-0060/D-0064) — **any UI change needs a human live-GUI confirm before it is
called done.** Every `models.json` change re-verifies Module 7; every live run asserts **0 orphaned
`llama-server`/python** and `review_queue.jsonl` before==after.

Suite = `modules/<NN>-<name>/tests/Invoke-<Name>Tests.ps1` (widgets: `widgets/<NN>-<name>/tests/`; #31 =
`tests/Test-FrontierBridge.ps1`). Latest green per unit (dates 2026):

| unit | last result | task / commit | date |
|---|---|---|---|
| #0 executor / dev.ship / #00.1 | 16/16 · 39/39+24/24 · 33/33 | `e5b93ab`/`5530418` | 07-28 |
| #1 / #2 / #3 / #4 | 11/11 · 16/16 · 16/16 · 16/16 | — | 07-24 |
| #5 / #6 | 26/26 · 39/39 | `m5/m6-test-001` | 07-24 |
| #7 model.gateway | 0.6.0: 366 off-machine + 74 on-box; base 42/42 warm 23/23 pool 43/43 split 63/63 | `d289ba9` | 07-31 |
| #8 / #9 | 33/33 · 34/34 | `m8/m9-test` | 07-24 |
| #10 / #11 / #12 / #13 | 43/43 · 27/27 · 25/25 · 21/21 | `m1x-test-001` | 07-24 |
| #14 / #15 / #16 | 30/30 · 54/54 · 44/44 -Live | `58870fb` | 07-30 |
| #17 / #18 / #19 | 48/48 · 41/41 · 28/28 -Live | `m1x-test` | 07-25 |
| #20 doc.io | 106/106 (+ops/setup 140/140 -Live) | `8274b9f` | 07-30 |
| #21 agent.local | 102/102 + AutoRamp 122/122 + split 22/22 | `0877c70` | 07-31 |
| #22 / #23 / #24 / #25 | 43/43 · 50/50+50/50 · 42/42 · 46/46 | various | 07-25..30 |
| #27 / #28 | 33/33 · 21/21 (+on-target 25/25) | `e444851` | 07-26..28 |
| #29 res.lease | 74/74 + 36/36 v0.3 + 45/45 v0.4 -Live | `0877c70` | 07-31 |
| #30 / #31 | 71/71 -Live · 65/65 | `2afd5de`/`b17a945` | 07-28 |
| #32 / #33 / #34 | 76/76x2 · 169/169 -Live · 138/138x2+recon 20/20 | `5026e2c`/`b60340c`/`bad9e27` | 07-30..31 |
| widgets/01 / 02 / 03 / 04 | 91/91 · 75/75 · 173/173+STA · 91/91 (live-GUI DONE) | various | 07-27..30 |
| #35 embedding.local | 42/42 (26 mock-seam + 16 -Live GPU) | `99b6590` | 08-01 |
| #36 artifact.search | **0.7.0 (i39): fast-beam shortlist/descend ranking (RANKING-ONLY; safe-pruning/port shapes/ns-closure unchanged; flat byte-identical); hpr 58823->117647 ppm; 38/38 + 56/56 A6 + 227/227 -Live + 11/11 wired s10** | `b72dfce` | 08-06 |
| #37 retrieval.eval | **0.8.1 (i40, PB-5 closed): WIRED_STRUCTURAL_DIGEST re-pinned (d0d54aba..e450); version single-source (skill.json) + permanent -Live envelope==manifest assertion (proven-to-fire); full suite ALL PASS on-device x2 (worker + orchestrator; VERSION-TRUTH x6; rehearsal 9/9 + hierarchy 11/11; digests cross-env identical)** | `6c7269d` | 08-06 |
| #38 repo.intel | 65/65 pwsh + 37/37 python + 65/65 -Live | `cd53565` | 08-01 |
| #39 episode.record | 0.1.1: 123/123 cloud + 123/123 -Live | `3dab699` | 08-02 |
| #40 context.compiler | **0.9.0 (i38): working_memory hydrated from #42 (conjunctive ns fail-closed; state_version in identity; flat byte-identical to 0.8.0); 42/42 owned + full regression (322/322 + i35 32/32 + router 35/35 + i34 38/38)** | `52a0381` | 08-05 |
| #41 skill.card | 0.2.0: 81/81 python + 85/85 -Live | `54c2e79` | 08-03 |
| #42 working.memory | 0.1.0: 30/30 + 30/30 live + 14/14 pwsh | `601a2db` | 08-05 |
| #43 action.authz | **0.6.0 (i42): the 3 round-4 exact closures (F5/F4/F2 -- seam detail D-0116/18); suite x2 exit 0 byte-identical (364/364, mutations 69/69, fuzzer 400/0, oracle 152 not_run=0, role 30/30, completion 21/21, views 64/64); empty-dir self-verify VERIFIED (3b5d62f4); taxonomy=`pass` (D-0118 round-5 PASS, pack 6bb613ea; activation prohibited)** | `10d0d1e` | 08-08 |
| widgets/05 / 06 / 07 | 100/100+STA 8/8 · 85/85+98/98 -Live (STA 9/9) · 81 cloud + 93 -Live (STA 8/8) — live-GUI confirm DONE i43 | `3ad71d3`/`c912854`/`855c242` | 08-05..08 |
| widgets/08 LRAP | **87/0/0 -Live (i45): read-only replay pathway; every SELFTEST_*_OK (incl. RECONCILE/DESCEND/INTERACT/READONLY/LAYOUT); five-fixture machine classify 0 FP/FN (mis-route->s3, dropped->s4, wrong-record->s6, clean+quirk consistent); byte-identical re-render; read-only + i33 sanitization fail-closed; real #40 render; orchestrator INDEPENDENT re-verify** | `a88e177`/`6028b9c` | 08-08 |
| #44 project.map | **0.1.0 (i46): 49/49 cloud (negative 33/33 -- every error code) + -Live Skeleton full-repo smoke + selftest OK; independent on-box re-run (py3.12+pwsh); golden digest 0a1deec4 cloud==box; fold ingest 143 entities/98 edges -> validate 0 findings** | `11416a8` | 08-11 |
| D-0077 cross-module folds | i34 smoke 38/38 · i36 Tier-1 11/11 (`tier1_accepted=TRUE`) · i38/i39 18/18 · i40/i41 fold-i39 exit 0 · **i42: fold-i39 vs 0.6.0 exit 0 + i34 38/38 + the independent #43 suite x2 byte-identical (3b5d62f4); i45: widgets/08 pinned 06/07 adapter + cross-widget contract test green in the independent -Live 87/0/0** | `runtime/smoke-i34.py`/`fold-i39.py` | 08-08 |

## Known failures / gotchas

**Highest-value section. Do not compress a live gotcha away.**

- **A WORKER'S DEVICE BRIDGE CAN DIE BEFORE ITS FIRST PUSH (i40).** The worker "finishes" in its session but
  NOTHING lands — and mount mtimes MISLEAD (`ls` shows UTC, git log local PDT; i39-era writes looked like i40
  activity). Verify what LANDED via NATIVE git through the executor, never the mount view. Recovery: Nicholas
  resumes the worker session to re-push (its container persists); the orchestrator runs gates + devship +
  files the report on its behalf, recording the recovery (the i40 Lane-A pattern, D-0112).
- **Cowork `device_stage_files` can return a STALE snapshot.** Re-staging a path already staged this session
  returns the **old** (pre-edit) bytes even though `mtimeMs` looks current — it nearly reverted committed doc
  edits. **Workaround:** copy the file to a **fresh, never-staged path** and stage that, or verify by a marker
  first. **The on-disk repo is canonical** — trust an executor read over a re-stage. Staging can also 403
  (`session_stale_relogin`) — tell Nicholas, don't retry.
- **`ffprobe` on PATH is shadowed by a Python shim.** `where.exe ffprobe` returns
  `…\Python310\Scripts\ffprobe.exe` *before* the real `…\WinGet\Links\ffprobe.exe`. Resolve ffprobe as the
  **sibling of the resolved ffmpeg**, or filter out `\Python*\Scripts\` sources (#10 + #32 both do). The Linux
  mount cannot `stat` the WinGet `Links\*.exe` reparse points — `ls` shows them absent though Windows resolves.
- **Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8.** Any non-ASCII byte corrupts parsing
  and can exit 1 with **no output**. **Rule:** keep 5.1 workers **ASCII-only** (or BOM them); grep
  `[^\x00-\x7F]` before shipping. pwsh 7 is unaffected.
- **PowerShell empty-array unroll (pwsh 7.4.6, StrictMode):** `$x = if(cond){@($y)}else{@()}` assigns **`$null`**
  on the empty branch -> a later `$x.Count` throws. Assign first: `$x=@(); if(cond){$x=@($y)}`.
- **PowerShell array double-wrap:** a helper `return ,$out` collected with `@(helper)` yields a 1-element array
  whose element is the inner array — silent wrong results. Build into a `List[object]` and `return
  $acc.ToArray()` (no leading comma).
- **`@($list)` on a raw `List[object]` of `[pscustomobject]`s throws "Argument types do not match"** — use
  `$list.ToArray()` / `$list.Count`, or `([array]$x).Count` for maybe-null cmdlet output.
- **pwsh 7.4.6 `[System.Array]::Sort` with an `object[]` + a `Comparison[string]` sorts a CONVERTED COPY** — the
  in-place sort is a silent no-op; #33 leaked randomized hash order, caught ONLY by the double-run byte-identity
  gate. Cast to `[string[]]` first; keep double-run byte-identity gates in every canonical-bytes module.
- **`$var:` in a double-quoted string** parses as a scope/drive reference — a syntax error; use `${id}`.
  `dev.ship` AST-parses every shipped `.ps1` to catch this.
- **`llama-cli` on b8661 is interactive-only** — script LLMs via **`llama-server`** (`/v1/chat/completions`),
  as `model.gateway` does.
- **Child-process pipe deadlock:** reading a child's stdout to end while its stderr pipe fills deadlocks.
  Drain both async (`ReadToEndAsync`) or redirect to files; close the child's stdin.
- **`capture.screen` uses screen-pixel copy:** an occluded window captures whatever covers it; a minimized one
  returns `window_minimized` — it does not raise/activate windows. `System.Drawing.Common` is Windows-only.
- **Worker meta must be JSON-serializable.** Coerce exotic Pillow/numpy types explicitly (IFDRational broke
  `image_meta.json` mid-write). Fixed in `image_worker.py` (`safe_dpi`).
- **The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`** — trust the heartbeat, not the
  process list; own warm servers by Job-Object HANDLE, not process-name matching.
- **Skill scripts write ONLY the JSON envelope to stdout** (diagnostics to stderr) — the executor parses
  stdout verbatim.
- **Bare-local WinForms event handlers lose scope** — use `.GetNewClosure()` + a SelfTest guard (D-0060).
- **A live GUI probe window inside a background executor task** can hang that task's UIA calls — prefer
  side-effect-free dry-runs.
- **Executor wedge (D-0055/D-0056):** a task that BLOCKS holding a persistent `llama-server` orphans it; the
  orphan livelocks the poll loop **while the heartbeat stays fresh**. Launch persistent servers **DETACHED**,
  reap the child tree before finalize, assert 0 orphans; if wedged, kill the orphan out-of-band (Task Manager).
  Risk scales with concurrency — re-assert every wave.
- **Executor transient file-lock crash — self-healed** (`Invoke-WithFileRetry` + loop guard; watchdog covers
  externally). **Still live:** avoid holding handles on `runtime/` from the Linux mount while tasks run.
- **Orchestrator/mirror-side gotchas** — git over the read-only mount (CRLF-noise M-list; stale
  `.git/index.lock`; **never `git add -A`**; all git writes through the executor under the `git` lease);
  `device_bash` cannot run Windows pwsh (use `exec-job.sh`); `project_write local_path` must be under the
  working dir; deliver prompts/packets/packs as FILES; core-docs are CRLF (some module docs LF — preserve
  per-file EOL). Owned by **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **WinForms: lay out a `Dock=Top` toolbar's children only AFTER the panel is sized** (widget-04's off-screen
  button, D-0068). Position from the panel's ACTUAL width in a Resize handler + on Shown; add a
  `SELFTEST_LAYOUT_OK` off-screen SelfTest.
- **Warm pool manager is OPT-IN / default-OFF (D-0067..D-0069, D-0078/D-0079).** Stage-1.1 closed the red-team
  Criticals; the durable Job-Object supervisor (0.4.0 i16 -> 0.6.0 i23, 10 must-fixes folded, finding 5
  CLOSED/live-proven) is built BUT the as-built red-team returned **GATE = NO** (D-0079): NOT soak-ready.
  Default-ON gates on: i24 deterministic hardening (9 P0/P1 + 18 tests) -> trusted deployment config -> the
  #00.1 recovery driver (MF8) + trusted-hash provisioning (MF10, both HARD blockers) -> an in-proc res.lease
  client -> a grown soak (>=24h, >=1000 transitions). Classic + D-0057 detached-warm stay the trusted default.
  Detail: `WARM_POOL_DESIGN.md` §10 + `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`.
- **SD 3.5 Medium fp16 is NOT a clean 11 GB fit (D-0070):** torch VRAM peaks ~12.06 GB (T5 fp16 spike -> NVIDIA
  driver system-RAM fallback). `gen_image_infer.py` ships a sequential-offload OOM ladder as the guaranteed
  fallback; default stays `image.sd15`.
- **`dev.ship` can FALSE-NEGATIVE the commit (D-0072).** VERIFY the real HEAD via native `git log`/`git show
  --stat`, not the dev.ship `committed` field; clear a stale 0-byte `.git/index.lock` via an executor task
  (assert no `git.exe` running) then re-commit.
- **A long-running supervisor keeps OLD module code (i21).** RESTART the supervisor after shipping any
  supervisor-side change before the live check; consumer identity params must pin BOTH `resident_instance_id`
  AND `instance_generation` through the supervisor launch.
- **Driver 591.74 SPILLS a too-big model to system RAM instead of hard CUDA OOM (i21).** "It loaded" != "it
  fits" — the measured-PEAK `required_vram` + stable-headroom gate is the ONLY real admission control.
- **The res.lease split adds ~6-9 child-pwsh spawns per call (~0.9-1.3 s each) (i21).** An in-process res.lease
  client is a named follow-on before any warm-pool default-ON. `[Console]::Out` bypasses in-process capture —
  emit via `Write-Output`.

## Unresolved questions

- **Install pwsh system-wide** (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- **Unattended scheduled orchestrator = IMPOSSIBLE on this build (D-0074):** a scheduled Cowork fire has no
  device bridge. The future home for unattended fan-out is the local baton-pass agent (R4/#26) when strong.
- **`model.gateway` semantic confidence** — today a completeness heuristic, not semantic, not calibrated.
- **`-Profile max` 9B arg-gen returns non-JSON** (`arg_parse_failed`) — floor is the reliable path (D-0046).
- **The executor file-lock crash root cause was never reproduced** — self-healed, not explained.
- **Widget 03 `model.gateway` GPU live-GUI pass still open** (since D-0060).
- **Audit surface -- LRAP v1 NOT phenomenological (D-0125):** P9 open; poser SHIPPED (D-0127; live-click PENDING D-0129); next = front-step/ride-along/output (`core-docs/AUDIT_PIPELINE.md`).
- **Portability:** `$PwshPath` defaults across ~15 model-bound entrypoints; core-infra (00.1 + `ops/*.bat`);
  interpreter paths #15/#16; model-bound F: literals — each its own follow-on wave (D-0069).
- **Generator upgrades (D-0068 leads):** image Z-Image-Turbo Q8 (needs stable-diffusion.cpp), music ACE-Step,
  video LTX-Video/Wan2.1, audio Stable Audio — each a GPU-lane wave. SD 3.5 tier shipped (D-0070).
- **The video-spine DENSE-STREAM decision gate is OPEN (D-0077):** sparse semantic keyframes may lack temporal
  continuity for identity — decide (dense low-res tracking stream vs sparse keyframes) BEFORE freezing
  `video.interpret` (pos 22) / live-composition input contracts.
- **Warm-pool default-ON gate:** see Known failures (D-0079 sequence).

## Next expected action

**i46 CLOSED (D-0130/D-0131):** the PCB shipped -- NEW modules/44 `project.map` 0.1.0 (map + claims folded + BOOT_PACKET rendered) ALONGSIDE the untouched legacy handoff; the I47 evaluation packet is FROZEN (EVAL_SHA `0bcb5e7`).

**NEXT = i47** (seat: Opus 4.8 Extra): (1) DONE: mandate 02 SUNSET -- verdict YES, SEALED_CHECK_47 armed (open i>=54), report in research/ (D-0132); (2) the legacy-vs-PCB side-by-side dry run per **`modules/44-project-map/eval/I47_EVAL_PACKET.md`** (MANIFEST-verify, Nicholas picks T1/T2/T3, dispatches A/B/C1/C2); (3) apply the packet s7 verdict rules -> GO / CONDITIONAL / NO-GO for i48 migration. Post-gate menu: AUDIT_PIPELINE next_increment (front step + ride-along + output side); M2-C first increment (PCB design s6; FO-3); #40 beam-width. P0-1 activation stays FROZEN.

**Standing (still open):** FROZEN/deferred per D-0080 (supervisor/warm-pool D-0079 GATE-NO; generator upgrades; `video.interpret` + live composition; deep real-time perception; broad training).

---

**Last updated:** 2026-08-11 -- i46 CLOSED (D-0130/D-0131): the Project Comprehension Bootstrap (modules/44 project.map 0.1.0) shipped + independently verified + folded (claims 0-findings; BOOT_PACKET rendered); the I47 legacy-vs-PCB migration-gate packet FROZEN (EVAL_SHA 0bcb5e7); i47: mandate 02 SUNSET, verdict YES, sealed check armed (D-0132).
*(Rule: REPLACE this line, never append. No `[prior]` chain here or anywhere else in this doc.)*
