# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture, not history. Keep it compact.

History lives elsewhere: **`DECISION_LOG.md`** (rationale — read **`DECISION_LOG_INDEX.md`** first, then pull entries by ID), **git history**, and **`archive/`**
(byte-exact pre-consolidation snapshots). **Rule: this doc must NEVER grow `[prior]` accretion chains again** —
replace a stale statement in place, cite `D-####` if the reason matters. A `CURRENT_STATE.json` counterpart is
planned, not yet created.

Owned elsewhere, do not duplicate: `TOOL_MODEL_REGISTRY.md` (tool/model/hardware inventory) ·
`MODULE_ROADMAP.md` (build order, status, follow-ons) · `REVIEW_QUEUE.md` (queue schema, producers) ·
`FANOUT_ORCHESTRATOR_HANDOFF.md` (orchestrator ops) · `ADAPTIVE_RESOURCE_GOVERNOR.md` (governor design) ·
`ARCHITECTURE_MAP.md` (destination).

## Phase + active work

- **Phase:** MVP build-out on the D-0029 usable-local-core-first build priority (`MODULE_ROADMAP.md → Build
  priority`). Two tracks: **Modules** (`modules/`) + **Widgets** (`widgets/`, the human-interface layer).
- **Direction (D-0050):** past MVP the project drives ONE spine — the **OFFLOAD / AUDIT LOOP** under the
  **verify-cost rule**: offload only what is cheaper to VERIFY than to do; deterministic modules are Claude's
  hands, model modules only where machine- or human-checkable.
- **ACTIVE = the fan-out loop. Iterations 1–14 are DONE** (D-0055..D-0067) via `orchestrate.fanout` #30 over
  `res.lease` #29, workers hand-dispatched into fresh Cowork sessions. Ledger:
  **`FANOUT_ORCHESTRATOR_HANDOFF.md`**; rationale: **DECISION_LOG D-0055..D-0067**. Do not re-narrate here.
- **NEXT = iteration 15** (D-0067); the first 4-lane wave (i14) shipped 3/3 on-box + a folded frontier red-team: **1 GPU worker (HARD-CLAMPED <=1/wave) + 1 CPU +
  1 broad coding + 1 externalized frontier-GPT review/audit lane**. Validated on-box ceiling `MaxParallel 3`
  (1 GPU + 2 CPU); the frontier lane is off-box, takes no lease. Wave model, candidate menu + anti-collision
  rules: **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **Hard boundary (D-0051, non-negotiable):** the orchestrator NEVER drives another AI session — including the
  frontier lane, a human-couriered pack (`frontier.bridge` #31).
- Repo HEAD at last mirror: the **i14 close-out docs commit** (D-0067, `master`) — confirm live
  with `git log -1` (read-only over the mount is fine).

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
- **`-Profile floor` is the reliable end-to-end path** (`frugal|floor|max`). **Open residual: `-Profile max`
  does NOT land** — at `gen_tier=strong` the 9B arg-gen returns non-JSON (`arg_parse_failed`) every step, so
  tools never get valid args. A 9B/gateway defect, NOT the terminator (D-0046). *(Measured on the Q4 9B; not
  re-tested since the Q5_K_M swap, D-0062.)*
- Opt-in logprob-entropy soft signal (clean per-token logprobs on BOTH builds b8661 + b10092, D-0060);
  `-AutoRamp` is exposed in the Local Agent Console (widgets/01) as a toggle + trace render.

## Model stack (full inventory: `TOOL_MODEL_REGISTRY.md`)

- **Strong tier = `llm.strong.qwen3p5-9b` — Qwen3.5-9B Q5_K_M, fully GPU-resident** (~**7.11 GB**, `ngl 99`; **2902 MiB free
  at ctx 8192** — probe `m10-warmpool-probe-002`) -> **GPU-bound ~68 tok/s** (measured at Q4), clean terse JSON. Q4_K_M -> Q5_K_M for fidelity + KV headroom
  (D-0062); live S0 6/6 @2048 tok. **Q4 retained `wired:false`** = one-flip rollback.
- **Engine:** the 9B is a hybrid attention-SSM arch **b8661 cannot load**, so its entry pins `engine_path` to
  a side-by-side **llama.cpp b10092 (CUDA 12.4, self-contained)**; **every other tier stays on b8661**.
- **`no_think: true`** on the 9B entry -> the gateway appends ` /no_think`; without it the default flags leave
  reasoning ON and it returns empty content at `finish=length`.
- **The 27B is RETAINED but validated IMPRACTICAL (D-0061):** no Qwen3.5-27B quant fits GPU-bound on 11 GB —
  confirmed by the couriered frontier report (`core-docs/research/2026-07-28-frontier-local-model-selection.md`).
  Reachable via `-Model` / the X0 rung only; the resident 9B is the effective top rung.
- **Decision floor = mid (3B)**; strong is GENERATION-only.
- Warm multi-model pool Stage-1 (mechanism C) is BUILT opt-in/default-OFF (D-0067, i14; skill 0.3.0), Stage-1.1 hardening pending (WARM_POOL_DESIGN §10): `modules/07-model-gateway/WARM_POOL_DESIGN.md`
  (mechanism C = a named pool manager; sections 6 + 9; D-0063). Measured: one ~7 GB model fits the GPU at a
  time; swap is GPU-upload-bound (~1.6 s -> 3B, ~4.1 s -> 9B); same-model reuse ~1 ms; page-cache warmth does
  NOT cut swap cost; all GGUFs (28.5 GiB) fit the 64 GB RAM.

## Repo / working dirs

- **Repo (canonical):** `C:\Users\just_\LifeOrchestrator-Refresh\` — git-initialized; `core-docs/` +
  `modules/<NN>-<name>/` + `widgets/<NN>-<name>/` + `archive/`.
- **Large-data home:** `F:\My_Programs\...\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\`; shared
  llama.cpp engines under `_engines\`.
- **Reference sources (separate, NOT built here):** the earlier assistant codebase `LifeOrchestrator\repo`
  (fold in later) and the **Project Proteus** game (`Project-Proteus-src`).
- The attached Claude Project **mirrors** `core-docs/`; disk wins on disagreement.

## Executor status

- MVP complete, **running**. `modules/00-bootstrap-executor/` (pwsh 7.4.6, host `DESKTOP-PF5FFMF`). Current
  instance **`f74a3ebb…` (pid 37260)**, continuously up, **`degraded:false`**.
- Markers: `runtime/control/heartbeat.json` (health fields `degraded` / `poll_error_streak` /
  `stuck_finalize_count`) + `last-exit.json`. **Trust the heartbeat, not the process list.**
- **Watchdog (#00.1) is available but session-scoped, not persistent** (D-0013): launch
  `ops/start-watchdog.bat` before any long unattended wave.
- Crash history: a transient file-lock crash 2026-07-24, now **self-healed in-process** (Known failures);
  and a **wedge** from an orphaned llama-server holding a `running/` file (D-0055/D-0056), closed by iter-3
  hardening + launching persistent servers DETACHED (D-0057).
- **Model servers: `model.gateway` #7 keeps a DETACHED warm/persistent `llama-server`** with residency-key
  matching under the `res.lease` **gpu** lease (D-0057; warm reuse ~1 ms vs ~1200 ms cold) — NOT torn down per
  call. **`image.interpret` #17 is still transient** (multimodal `llama-server` with `--mmproj` per call). Any
  persistent server MUST launch detached and be reaped before finalize; assert 0 orphans every wave.

## Completed modules

Detail + follow-ons per module: `MODULE_ROADMAP.md`; producer status: `REVIEW_QUEUE.md`; invocation +
registry facts: `TOOL_MODEL_REGISTRY.md`. Roster (all MVP-complete unless noted):

- **Infra:** #0 exec.bootstrap (+ the `dev.ship` job-runner, D-0048) · #00.1 exec.watchdog · #1
  skill.bootstrap (contract v0.2) · #29 res.lease (gpu/git/doc leases; consumer trio complete) · #30
  orchestrate.fanout · #31 frontier.bridge (`pack` takes `{prompt, files}` — NOT `{task,...}`, D-0057).
- **Observation/UIA:** #2 fs.observer · #3 proc.observer · #4 uia.inspector · #5 uia.actor · #6 capture.screen.
- **Model core:** #7 model.gateway (detached warm server, D-0057) · #8 classify.batch · #9 review.processor ·
  #19 logic.escalator · #20 doc.io · #21 agent.local (`-Route`, D-0046 terminator, `-Profile`, `-AutoRamp`;
  the closed `tools.json` registry IS the sandbox) · #27 route.tools · #28 fs.manage.
- **Audio:** #10 audio.ingest · #11 speech.stt · #12 speech.tts · #13 voice.live.
- **Perception:** #14 ocr.layout · #15 image.util · #16 detect.objects · #17 image.interpret · #18 image.index.
- **Generators (user track):** #22 gen.audio · #23 gen.image · #24 gen.music · #25 gen.video.
- **NOT built:** #26 agent.coding — designed + DEFERRED (D-0037; no safe code-exec substrate on this box).
- **Widgets (native + `launch.bat`, D-0038):** 01 Local Agent Console · 02 Module Launcher · 03 Verification
  Console (**durable verdicts** — results sidecar keyed by `packet_id`; the packet file is never modified, D-0065) · **04 Fan-out Wave Dashboard** (read-only plan/worker/lease view; NEW i14 D-0067 — human live-GUI confirm pending).

**Phase A complete** (0–25 + 00.1; #26 deferred); generator track #22–#25 complete; **Phase B Widgets 01–04
shipped.**

## Installed dependencies (verified on this machine)

- **PowerShell 7.4.6** — a .NET global tool at **`C:\Users\just_\.dotnet\tools\pwsh.exe`**. The **latest**
  `PowerShell` global-tool package is malformed (no tool manifest) — **pin a version**.
- **.NET SDK 9.0.100** (`C:\Program Files\dotnet\dotnet.exe`) · **git** on PATH · **winget** present ·
  **choco** absent. **Not admin. No system-wide `pwsh`** — only the user `~\.dotnet\tools` entry.
- **ffmpeg / ffprobe 8.1** (Gyan.dev `full_build`), `ffmpeg` on PATH at
  `C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe`; full encoder set (libmp3lame, aac,
  flac, libopus, libvorbis, pcm_*). **`ffprobe` on PATH is shadowed by a Python shim — see Known failures.**
- **WinForms + STA runspace** work in the dotnet-tool pwsh (an STA runspace hosts a Form + `Application.Run`).
- **Windows PowerShell 5.1** (`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`, 5.1.19041.6456)
  — the ONLY runtime here that can load the WinRT `Windows.Media.Ocr` projection (pwsh 7.4.6 cannot); the
  `ocr.layout` #14 worker. **5.1 reads a BOM-less `.ps1` as ANSI — see Known failures.**
- **Windows.Media.Ocr** (system WinRT OCR) — words + `BoundingRect` + reading-order lines + `TextAngle`;
  `en-US`; `MaxImageDimension=10000`; ~74 ms on a 700x220 fixture. No install/admin/GPU/network.
- **Tesseract OCR** at `C:\Program Files\Tesseract-OCR\tesseract.exe` — **installed**, **declared not
  wired** (`ocr.tesseract`), a future second `ocr.layout` engine. No Python OCR libs in either venv.
- **Pillow + numpy** — **system python** `…\Python312\python.exe`: PIL 10.2.0 + numpy 1.26.4 + cv2 4.9.0;
  **speech venv** (F:): PIL 12.2.0 + numpy 2.4.4 — the numpy-DCT pHash is identical across both. `image.util`
  #15 uses the **system python** (CPU-only -> genuinely parallel-safe, not CUDA/venv-bound).
- **onnxruntime** — system python: onnxruntime-gpu 1.17.1 + onnxruntime-directml 1.17.1 + torch 2.2.1 +
  torchvision 0.17.1. `detect.objects` #16 requests **`CPUExecutionProvider`** by default.
- **diffusers 0.35.2 in the speech venv** — venv
  `F:\My_Programs\Local_Computer_Speech_Large_Data\python_env` (torch 2.11+cu128, transformers 4.57.3,
  accelerate, safetensors, torchvision 0.26, `qwen_tts`); powers `gen.image`/`gen.video`. It added only
  diffusers + importlib_metadata + zipp (Module 12 safe). The **system python is torch 2.2.1+cpu (no CUDA)** —
  image/video generation runs under the speech venv only.

## Installed local models (summary)

Full inventory — paths, sha256, licences, quants, tuning: **`TOOL_MODEL_REGISTRY.md`** + `models.json`.
Models live in per-owning-module F: homes under `…_Large_Data\` (D-0028); engines under `_engines\`
(**b8661** = every tier but the 9B; **b10092** = the 9B only). Decision-relevant facts:

- **strong** = `llm.strong.qwen3p5-9b` — Qwen3.5-9B **Q5_K_M**, 7.11 GB, GPU-resident, `no_think`, b10092;
  the Q4 entry is retained `wired:false` = one-flip rollback (D-0062).
- **mid (3B) = the decision floor**; tiny 0.5B / weak 1.5B for bulk work.
- The **27B is retained but impractical** (D-0061): `-Model` / `-AllowLegacy27B` only; `-LoadTimeoutSec ~300`;
  `gpu_layers` tuned 32 (see `TOOL_MODEL_REGISTRY.md`).
- Non-LLM models (whisper STT, Qwen3-TTS x2, YOLOX x2, VLM, SD 1.5, MusicGen, AnimateDiff-Lightning,
  embedding) are `wired:false` **for the gateway** by design — each resolved by its owning module
  (D-0020/23/25). The embedding model is staged but **unwired** (awaits artifact.search).

## Available hardware (measured 2026-07-24)

- **CPU** Intel i9-9900KF (8c/16t @3.6 GHz) · **RAM** 64 GB · **GPU** NVIDIA RTX 2080 Ti **11 GB VRAM** (CUDA,
  driver 591.74, cc 7.5) · **OS** Windows 10 Pro 19045 x64. Host `DESKTOP-PF5FFMF`, user `just_`.
- **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**), E: "Game Drive" 858 GB (~534 GB free),
  **F: "Storage space" 3.72 TB (~1.78 TB free)** = the large-data home. (No D: on this box.)
- Full profile + runtimes in `TOOL_MODEL_REGISTRY.md` (Hardware profile).

## Known working invocation paths

- **Every module:** `pwsh -NoProfile -File modules\<NN>-<name>\Invoke-<Name>.ps1 <named params>` (or
  `-InputsJson '<json>'`), or via the Module 1 wrapper `pwsh -NoProfile -File
  modules\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir <dir> [-InputsJson '<json>']`. Per-module parameters:
  each module's `README.md` / `skill.json`; model resolution: `TOOL_MODEL_REGISTRY.md`.
- **Through the executor:** submit a task package whose `task.ps1` calls either entrypoint; the envelope lands
  in `runtime/completed/<task_id>/stdout.txt`.
- **Executor control** (from `modules/00-bootstrap-executor/`): `Start-BootstrapExecutor.ps1` /
  `Submit-BootstrapTask.ps1` / `Stop-BootstrapExecutor.ps1`.
- **Job-runner** (`modules/00-bootstrap-executor/exec-job.sh`): `devship <id> <inputs.json> <timeout>` ships a
  unit; `run <id> <timeout> <task.ps1> <maxwait> "<desc>"`; `wait <id>` re-waits a long/GPU job (device_bash
  caps at ~45 s).
- **Direct pwsh:** `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- **User ops (click-to-run):** `ops/*.bat` — start/stop/restart/status the executor, run tests; output to
  `ops/out/`. **Watchdog:** `ops/start-watchdog.bat` / `stop-watchdog.bat` / `recover-executor.bat [-Force]`,
  or `modules\00.1-exec-watchdog\Watch-Executor.ps1` / `Recover-Executor.ps1`.
- Examples: `07-model-gateway\Invoke-ModelGateway.ps1 [-Model <id>|-Tier tiny|weak|mid|strong] -Prompt '<s>' [-MaxTokens -Temperature -TopP -TopK -Seed]` · `21-agent-local\Invoke-AgentLocal.ps1 -Goal '<s>' -Route [-Profile frugal|floor|max] [-NoAutoRamp] [-AllowLegacy27B] [-DryRun]` · `06-capture-screen\Invoke-CaptureScreen.ps1 [-Target monitor|window|app|region] [-Monitor index|all|primary] [-Format png|jpg]`.

## Current tests

Standing gates, in order: **(1) the off-machine cloud gate FIRST** (pwsh 7.4.6 on Linux; the real skill where
portable, a mock worker/child where not), **(2) `-Live` on the Windows executor**, **(3) `dev.ship`** (sha256 +
AST + tests, fail-closed). **Mock/API gates MISS rendered-UI defects and real-model failures**
(D-0049/D-0060/D-0064) — **any UI change needs a human live-GUI confirm before it is called done.** Every
`models.json` change re-verifies Module 7 (28/28); every live run asserts **0 orphaned `llama-server`/python**
and `review_queue.jsonl` before==after.

Suite = `modules/<NN>-<name>/tests/Invoke-<Name>Tests.ps1` (widgets: `widgets/<NN>-<name>/tests/`; one
exception: #31 = `tests/Test-FrontierBridge.ps1`). Dates 2026.

| unit | last result | task / commit | date |
|---|---|---|---|
| #0 executor | 16/16 | `e5b93ab` | 07-28 |
| #0 dev.ship / exec-job | 39/39 + 24/24 | `5530418` | 07-27 |
| #00.1 exec.watchdog | 33/33 | `e5b93ab` | 07-28 |
| #1 / #2 / #3 / #4 | 11/11 · 16/16 · 16/16 · 16/16 | — | 07-24 |
| #5 uia.actor | 26/26 | `m5-test-001` | 07-24 |
| #6 capture.screen | 39/39 | `m6-test-001` | 07-24 |
| #7 model.gateway | 42/42 + warm 23/23 + pool 43/43 | `0c6d5c9`/`f8c961a`/`09a7e71` | 07-29 |
| #8 classify.batch | 33/33 | `m8-test-001` | 07-24 |
| #9 review.processor | 34/34 | `m9-test-003` | 07-24 |
| #10 audio.ingest | 43/43 | `m10-test-001` | 07-24 |
| #11 speech.stt | 27/27 | `m11-test-001` | 07-24 |
| #12 speech.tts | 25/25 | `m12-test-001` | 07-24 |
| #13 voice.live | 21/21 | `m13-test-001` | 07-24 |
| #14 ocr.layout | 30/30 | `m14-test-003` | 07-25 |
| #15 image.util | 48/48 | `m15-test-001` (re-verified `m16-test-001`) | 07-25 |
| #16 detect.objects | 38/38 | `m16-test-001` | 07-25 |
| #17 image.interpret | 48/48 `-Live` | `m17-test-001/002` | 07-25 |
| #18 image.index | 41/41 `-Live` (40/40 cloud) | `m18-test-002` | 07-25 |
| #19 logic.escalator | 28/28 `-Live` (24/24 cloud) | `m19-test-001` | 07-25 |
| #20 doc.io | 106/106 | `d2a7352` | 07-28 |
| #21 agent.local | 102/102 (+122/122 off-machine) | `e444851` | 07-28 |
| #22 gen.audio | 43/43 (41/41 cloud) | `m22-test-001` | 07-25 |
| #23 gen.image | 32/32 `-Live` (42/42 cloud) | `m23-test-005` | 07-25 |
| #24 gen.music | 42/42 `-Live` (49/49 cloud) | `m24-test-002` | 07-26 |
| #25 gen.video | 46/46 `-Live` (54/54 cloud) | `m25-test-002` | 07-26 |
| #26 agent.coding | not built (designed, D-0037) | — | 07-26 |
| #27 route.tools | 33/33 | `e444851` | 07-28 |
| #28 fs.manage | 21/21 off-machine (on-target verify `m29-verify-001` 25/25) | `m29-after-003` | 07-26 |
| #29 res.lease | 41/41 `-Live` (38/38 cloud) | `36d7e0be` | 07-27 |
| #30 orchestrate.fanout | 71/71 `-Live` | `2afd5de` | 07-28 |
| #31 frontier.bridge | 65/65 + hardened return-capture | `f52f21d`/`b17a945` | 07-28 |
| widgets/01 Agent Console | 91/91 `-Live` (89/89 cloud) | `b1f36f0` | 07-28 |
| widgets/02 Module Launcher | 75/75 `-Live` (64/64 cloud) | `c509e571` | 07-27 |
| widgets/03 Verification Console | 173/173 cloud mock + live STA SelfTests (`SELFTEST_VERDICT_PERSIST_OK`, `SELFTEST_AUTOLOAD_OK`) | `f3c1ec7` | 07-29 |
| ops/setup portability | 78/78 cloud + 88/88 `-Live` | `821da16` | 07-29 |
| widgets/04 Fan-out Wave Dashboard | 80/80 cloud + 90/90 `-Live` (STA SelfTest); live-GUI confirm PENDING | `333dac6` | 07-29 |

## Known failures / gotchas

**Highest-value section. Do not compress a live gotcha away.**

- **Cowork `device_stage_files` can return a STALE snapshot.** Re-staging a path already staged this session
  returns the **old** (pre-edit) bytes even though `mtimeMs` looks current — it nearly reverted committed doc
  edits. **Workaround:** copy the file to a **fresh, never-staged path** (e.g. `docmirror-i<N>/`) and stage
  that, or verify by a marker first. **The on-disk repo is canonical** — trust an executor read over a re-stage.
- **`ffprobe` on PATH is shadowed by a Python shim.** `where.exe ffprobe` returns
  `…\Python310\Scripts\ffprobe.exe` *before* the real `…\WinGet\Links\ffprobe.exe`. Resolve ffprobe as the
  **sibling of the resolved ffmpeg**, or filter out any `\Python*\Scripts\` source. Also: the Linux mount
  cannot `stat` the WinGet `Links\*.exe` reparse points, so `ls` shows them absent though Windows resolves them.
- **Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8.** Any non-ASCII byte corrupts parsing: a
  UTF-8 em dash in `ocr_worker.ps1` made 5.1 fail ("Unexpected token" / "The hash literal was incomplete") and
  exit 1 with **no output** — and the wrapper discarded stderr, so it only saw "produced no meta". **Rule:**
  keep 5.1 workers **ASCII-only** (or BOM them); grep `[^\x00-\x7F]` before shipping. pwsh 7 is unaffected.
- **PowerShell empty-array unroll (pwsh 7.4.6, StrictMode):** `$x = if(cond){@($y)}else{@()}` assigns **`$null`**
  on the empty branch, so a later `$x.Count` throws "The property 'Count' cannot be found." Assign first:
  `$x=@(); if(cond){$x=@($y)}`. Hit + fixed in `model.gateway` (empty `-Stop`).
- **PowerShell array double-wrap (pwsh 7.4.6):** a helper that does `return ,$out`, collected with `@(helper)`,
  yields a **1-element array whose element is the inner array** — a later `foreach`/lookup silently iterates
  once over the whole array (no error; wrong results). Fix: build into a `List[object]` and `return
  $acc.ToArray()` (no leading comma). Hit in `classify.batch` (label matching) and in Widget 02's
  `Get-ModuleRegistry` (the module list rendered as one unreadable row).
- **`@($list)` on a raw `System.Collections.Generic.List[object]` throws "Argument types do not match"**
  (pwsh 7.4.6) when it holds `[pscustomobject]`s — use `$list.ToArray()` / `$list.Count`, or
  `([array]$x).Count` for maybe-null cmdlet output (StrictMode Latest).
- **`$var:` in a double-quoted string** (e.g. `"item $id: done"`) parses `$id:` as a scope/drive reference —
  a **syntax error**; delimit with `${id}`. Catch it by AST-parsing every shipped `.ps1` with
  `[System.Management.Automation.Language.Parser]::ParseFile` before submitting (`dev.ship` does).
- **`llama-cli` on build b8661 is interactive-only** — it rejects `-no-cnv` ("use llama-completion instead",
  not built) and decorates stdout with a banner/`>`/timing footer. Script LLMs via **`llama-server`**
  (`/v1/chat/completions` -> clean JSON with `finish_reason`/`usage`/`timings`), as `model.gateway` does.
- **Child-process pipe deadlock:** reading a child's stdout to end while its stderr pipe fills (llama.cpp logs
  a lot) deadlocks. Drain both async (`ReadToEndAsync`) or redirect to files, and close the child's stdin.
- **`capture.screen` uses screen-pixel copy (`CopyFromScreen`):** an **occluded** window captures whatever
  covers it and a **minimized** one returns `window_minimized` — it does **not** raise/activate windows.
  Per-Monitor-V2 DPI is set once per process; off-screen/`PrintWindow` compositing is deferred.
  `System.Drawing.Common` is Windows-only, so it cannot even be dry-run off-Windows.
- **Worker meta must be JSON-serializable.** Pillow returns a JPEG's `dpi` as `(IFDRational, IFDRational)`,
  which `json.dump` cannot serialize — it raised **mid-write**, leaving a truncated `image_meta.json` and a
  cryptic `ConvertFrom-Json ... Unexpected end ... Path 'metadata.dpi'`. **Rule:** coerce exotic Pillow/numpy
  types explicitly (or `json.dump(default=...)`). Fixed in `image_worker.py` (`safe_dpi`).
- **The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`** — `(Get-Process -Id $PID).Path` is
  not a reliable pwsh locator; pass explicit `-PwshPath`, resolve via `$PSHOME` in harnesses. The **executor
  likewise shows as `dotnet.exe`** — trust the heartbeat, not the process list.
- **Skill scripts must write ONLY the JSON envelope to stdout** (diagnostics to stderr); the executor captures
  stdout verbatim into `stdout.txt` and parses it as the envelope.
- **Bare-local WinForms event handlers lose scope** — a toggle handler threw a null-ref (`'Enabled' on $null`)
  live though the mock gate was green. Use `.GetNewClosure()` + a SelfTest guard (D-0060).
- **A live GUI probe window launched from INSIDE a background executor task** can hang that task's UIA calls if
  the window's UI thread stops pumping. Prefer side-effect-free dry-runs when capturing examples.
- **Executor wedge (the concurrency hazard, D-0055/D-0056):** a task that BLOCKS while holding a persistent
  `llama-server` orphans it; the orphan locks a `running/` file and livelocks the poll loop **while the
  heartbeat stays fresh** (the watchdog was blind). Launch persistent servers **DETACHED**, reap the whole
  child tree before finalize, assert 0 orphans. If wedged, kill the orphan out-of-band (Task Manager -> End
  task `llama-server.exe`). Risk **scales with concurrency** — re-assert every wave. Hardened by `e5b93ab`.
- **Executor transient file-lock crash (2026-07-24) — self-healed:** a directory-move/state-write collided with
  an open handle and killed the executor; now wrapped by `Invoke-WithFileRetry` + a per-iteration
  `IOException`/`UnauthorizedAccessException` loop guard (D-0013 watchdog covers it externally). **Still live:**
  avoid holding handles on `runtime/` from the Linux mount while tasks run.
- **Orchestrator/mirror-side gotchas** — git over the read-only device mount (CRLF-noise M-list, the stale
  `.git/index.lock`, **never `git add -A`**, all git writes through the executor / `dev.ship`); `device_bash`
  is a Linux VM and cannot run Windows pwsh (everything goes through `exec-job.sh`); `project_write local_path`
  must be under the working dir, not `/tmp`; deliver prompts/packets/packs as FILES; core-docs are CRLF, edit
  fail-closed and commit only named files under the `git` lease. Owned by **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **Warm pool manager is OPT-IN / default-OFF (D-0067).** Stage-1 shipped, but the frontier red-team found 4 Critical hardening gaps (TTL-is-not-fencing; releasing the lease does NOT free VRAM for another module; non-crash-atomic transitions; port+`/health` can validate the WRONG generation). Do NOT enable the pool by default until Stage-1.1 closes them (WARM_POOL_DESIGN §10); the classic + D-0057 warm paths remain the trusted default.

## Unresolved questions

- **Install pwsh system-wide** (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- **`model.gateway` semantic confidence** — confidence today is a *completeness* heuristic (stop/length/empty),
  not semantic, not calibrated; the same gap exists in every downstream producer.
- **`-Profile max` 9B arg-gen returns non-JSON** (`arg_parse_failed`) — blocks the max profile end-to-end
  (D-0046). Floor is the reliable path.
- **The executor file-lock crash root cause was never reproduced** — the class is self-healed, not explained.
- **The 27B needs a long `-LoadTimeoutSec`** via `-Model`/X0 (a cold load ~90 s approaches the gateway's 120 s
  default); its `gpu_layers` is tuned to 32 (Module 9 sweep — see `TOOL_MODEL_REGISTRY.md`).
- **`embedding.qwen3-0p6b` is staged but unwired** — awaits its owning module (artifact.search).
- **Widget 03 Verification Console `model.gateway` GPU live-GUI pass is still open** (residual first noted
  in D-0060, never closed) — exercised CPU-only + live-GUI so far.
- **Portability / new-machine bring-up: Stage-1 SHIPPED (i14, `ops/setup/`, D-0067); residuals open** (a config-driven `setup.ps1`: repo-root + data-root, prereq
  check, model/engine staging, GPU detect, machine-specific `models.json`, a verify pass) — wanted **before** a
  hardware upgrade.
- **Frontier audio/image/video MODEL LEADS for generators #22–#25 are outstanding** — upgrades blocked on them.
- **Warm-pool Stage-1.1 hardening REQUIRED before enabling the pool by default** — the frontier red-team's 15 findings (4 Critical: fencing token vs TTL, crash-atomic transitions + reconciliation, enforced GPU-handoff eviction, Job-Object process ownership) + `CanServe()` + dropping prefix-reuse/LRU/timed-eviction from the correctness path (WARM_POOL_DESIGN §10, D-0067).
- **Widget 04 (Fan-out Wave Dashboard) needs a human live-GUI confirm** — shipped i14 (mock + SelfTest green), rendered-UI unverified (D-0067).

## Next expected action

**Run iteration 15** per **`FANOUT_ORCHESTRATOR_HANDOFF.md`**: scope 1 GPU + 1 CPU
+ 1 coding unit from its candidate menu + 1 frontier review/audit topic -> `plan` at `MaxParallel 3` -> confirm
`dispatch_now <= 3`, <=1 gpu, 0 doc contention, clean preflight -> relay every worker prompt + the frontier
pack as FILES -> `status` until `ready_for_handoff` -> `handoff` -> fold the answer -> mirror the core-docs
under the `git` lease. Standing GPU-lane candidate: **warm-pool Stage-1.1 HARDENING** (the frontier red-team's Critical blockers) per
`WARM_POOL_DESIGN.md` section 10 — the FANOUT_AGENT_001 brief must be RE-AUTHORED for Stage-1.1 (the Stage-1 brief is archived).

Outstanding asks, open until closed: **(1)** frontier audio/image/video **model leads** to unblock generators
#22–#25; **(2)** the **widget-03 GPU Console pass** (open since D-0060); **(3)** the **portability / new-machine bring-up**
unit. NEW: warm-pool Stage-1.1 hardening (WARM_POOL_DESIGN §10) + a widget-04 live-GUI confirm; portability Stage-1 shipped i14 (residuals open).

---

**Last updated:** 2026-07-29 — fan-out iteration 14 close-out (D-0067).
*(Rule: REPLACE this line, never append. No `[prior]` chain here or anywhere else in this doc.)*
