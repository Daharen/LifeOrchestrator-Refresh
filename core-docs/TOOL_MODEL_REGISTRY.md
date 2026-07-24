# TOOL_MODEL_REGISTRY

Owns **what already exists and can actually be used** — tools, executables, models, services, skills.
Prevents every fresh instance from rediscovering the machine; later becomes the basis for task routing.
Read only when selecting or invoking a tool/model. Add an entry the moment you install or verify something.

**Entry fields:** id · status · type · location · invocation · supported tasks · I/O formats ·
quality tier · speed · CPU/GPU/mem · network · cost · limitations · last successful test · skill ids.
**Status vocab:** installed · available · inactive · broken · planned · retired.

---

### `exec.bootstrap` — Trusted High-Risk Bootstrap Executor
- **status:** installed, running (crashed once 2026-07-24T06:26:36Z on a transient file-sharing violation, since
  restarted; now **auto-recovered by Module 00.1 `exec.watchdog`**). Emits `control/heartbeat.json` +
  `control/last-exit.json` for supervision (additive; 12/12 unaffected). · **type:** skill/service (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (canonical. The original at `proteus_repo/tools/trusted-bootstrap-executor/` was stopped and is pending removal from the game repo.)
  · **NOTE:** restart the live executor once (`ops/restart-executor.bat`) so it begins emitting the new markers.
- **invocation:** `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` (+ `Submit-`/`Stop-`); tasks are
  directories atomically published into `runtime/pending/`.
- **supported tasks:** run arbitrary local PowerShell task packages with concurrency, timeout,
  output/exit/timing capture, restart recovery.
- **I/O:** in = task dir (`task.json` + `task.ps1`); out = `result.json` + `stdout.txt`/`stderr.txt`.
- **quality:** n/a (deterministic harness) · **speed:** poll-bounded (30s queue poll in the running instance) ·
  **CPU/GPU/mem:** low / none / low · **network:** none · **cost:** local only.
- **limitations:** trust-based (not a sandbox); Windows-focused (`taskkill`); no orphan-child reaping
  after crash; polling latency. **File-sharing violations are now self-healed in-process** (`Invoke-WithFileRetry`
  around state-writes + finalization moves, + a per-loop `IOException`/`UnauthorizedAccessException` guard) and
  also externally recovered by the watchdog. · **last test:** 2026-07-24, 12/12 (pwsh 7.4.6, with markers +
  self-heal). · **skills:** `exec.bootstrap`.

### `pwsh` — PowerShell 7.4.6 (runtime)
- **status:** installed · **type:** executable ·
  **location:** `C:\Users\just_\.dotnet\tools\pwsh.exe` (.NET global tool; user PATH `~\.dotnet\tools`).
- **invocation:** `pwsh -NoProfile -ExecutionPolicy Bypass -File <script>` (new shells) or the full path.
- **supported tasks:** primary scripting/execution runtime for skills and the executor. Loads managed UI
  Automation (`UIAutomationClient`/`UIAutomationTypes`), `System.Windows.Forms`/`System.Drawing`, and can host
  a WinForms message loop on an STA runspace (verified 2026-07-24 for the Module 5 probe test).
- **limitations:** shim reports process path as `dotnet.exe` (pass explicit `-PwshPath`); pinned version
  because the latest tool package is broken; not on system PATH (per-user only). · **last test:** 2026-07-24.

### `dotnet` — .NET SDK 9.0.100
- **status:** installed · **type:** executable · **location:** `C:\Program Files\dotnet\dotnet.exe`
- **supported tasks:** build/run .NET & C++ interop tooling; installs .NET global tools (no admin).
- **network:** yes (NuGet). · **last test:** 2026-07-24 (installed the pwsh tool).

### `git` — version control
- **status:** installed · **type:** executable · **location:** on PATH ·
  **supported tasks:** repo ops in `LifeOrchestrator-Refresh` (and the game repo). · **last test:** 2026-07-24 (Module 4 commit).

### `winget` — Windows Package Manager
- **status:** installed · **type:** executable ·
  **location:** `C:\Users\just_\AppData\Local\Microsoft\WindowsApps\winget.exe`
- **supported tasks:** install software. **limitation:** system-wide installs need a UAC/admin approval
  the automation cannot click. · **last test:** availability confirmed 2026-07-24.

### `ref.echo` — Reference Echo Skill (Module 1)
- **status:** installed · **type:** skill (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/01-skill-bootstrap/skills/ref.echo/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-RefEcho.ps1 -Message <s> -Repeat <n>` (or
  `-InputsJson '<json>'`); wrapped `pwsh -File ..\..\Invoke-Skill.ps1 -SkillDir . -InputsJson '<json>'`;
  or as an `exec.bootstrap` task package.
- **supported tasks:** trivial echo / skill-channel health-check + canonical contract worked example.
- **I/O:** in = `{message:string, repeat:int}`; out = `lifeorch.skill.result/0.1` envelope on stdout +
  `runtime/artifacts/<invocation_id>/{echo.txt,result.json,stderr.txt}`.
- **quality:** deterministic (confidence null) · **speed:** ~0.1s · **CPU/GPU/mem:** low/none/~64MB ·
  **network:** none · **cost:** local only. · **last test:** 2026-07-24 via executor. · **skills:** `ref.echo`.

### `skill.bootstrap` — Skill contract tooling (Module 1)
- **status:** installed · **type:** library/tooling (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/01-skill-bootstrap/` (`lib/SkillContract.psm1`, `Invoke-Skill.ps1`)
- **invocation:** `Import-Module .\lib\SkillContract.psm1` → `Test-SkillManifest` / `Test-SkillResultEnvelope`;
  generic runner `pwsh -File .\Invoke-Skill.ps1 -SkillDir <dir> [-InputsJson '<json>']`.
- **supported tasks:** validate a `lifeorch.skill.manifest/0.1` manifest and a `lifeorch.skill.result/0.1`
  envelope; run any conforming skill and emit a `lifeorch.skill.invocation_report/0.1`.
- **I/O:** in = skill dir + optional inputs JSON; out = invocation-report JSON.
- **limitations:** field/type/enum checks (not full JSON-Schema); pwsh path defaults to the pinned
  dotnet-tool build. · **last test:** 2026-07-24 (reused by Modules 2–5). · **skills:** n/a (harness).

### `fs.observer` — Filesystem Observer (Module 2)
- **status:** installed · **type:** skill (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/02-fs-observer/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path <dir> -Depth <n> [-Pattern <glob>]`
  (or `-InputsJson '<json>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** deterministic depth-bounded directory tree + metadata + name/glob search; no screenshots.
- **I/O:** in = `{path, depth, pattern, include_hidden, max_entries}`; out = `lifeorch.skill.result/0.1` envelope +
  `runtime/artifacts/<id>/{tree.md,index.json,stderr.txt,result.json}`.
- **quality:** deterministic (confidence null) · **speed:** sub-second for small trees · **CPU/GPU/mem:** low/none/~128MB ·
  **network:** none · **cost:** local only. · **last test:** 2026-07-24 via executor (tests 16/16). · **skills:** `fs.observer`.

### `proc.observer` — Process & Window Observer (Module 3)
- **status:** installed · **type:** skill (PowerShell + Win32 via Add-Type) ·
  **location:** `LifeOrchestrator-Refresh/modules/03-proc-observer/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 [-NameFilter <glob>] [-VisibleOnly <bool>]`
  (or `-InputsJson '<json>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** snapshot running processes + top-level windows (titles, owning pid/name, bounds, min/max, foreground); no screenshots.
- **I/O:** in = `{visible_only, name_filter, max_items}`; out = `lifeorch.skill.result/0.1` envelope +
  `runtime/artifacts/<id>/{report.md,processes.json,windows.json,stderr.txt,result.json}`.
- **quality:** deterministic read of live state (confidence null; snapshot) · **speed:** ~1–3s · **CPU/GPU/mem:** low/none/~128MB ·
  **network:** none · **cost:** local only. · **last test:** 2026-07-24 via executor (tests 16/16). · **skills:** `proc.observer`.

### `uia.inspector` — UI Automation Inspector (Module 4)
- **status:** installed · **type:** skill (PowerShell + managed UI Automation) ·
  **location:** `LifeOrchestrator-Refresh/modules/04-uia-inspector/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 [-Hwnd <n>|-ProcessId <n>|-Title <glob>] [-Depth <n>] [-NameFilter <glob>]`
  (else the desktop root; or `-InputsJson '<json>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** read-only UIA control-tree walk of a target window (control type, name, automation id, class, bounds, patterns, state).
- **I/O:** in = `{hwnd, pid, title, depth, max_elements, name_filter}`; out = `lifeorch.skill.result/0.1` envelope +
  `runtime/artifacts/<id>/{tree.md,elements.json,stderr.txt,result.json}`.
- **quality:** deterministic read of live UI state (confidence null) · **speed:** ~1–5s · **CPU/GPU/mem:** low/none/~256MB ·
  **network:** none · **cost:** local only.
- **limitations:** read-only (acting is Module 5 `uia.actor`); point-in-time; some apps (e.g. Unity games) expose no UIA tree; bounded by depth/max_elements.
  · **last test:** 2026-07-24 via executor (tests 16/16). · **skills:** `uia.inspector`.

### `uia.actor` — UI Automation Actor (Module 5)
- **status:** installed · **type:** skill (PowerShell + managed UI Automation) ·
  **location:** `LifeOrchestrator-Refresh/modules/05-uia-actor/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-UiaActor.ps1 [-Hwnd <n>|-ProcessId <n>|-Title <glob>]
  -Action <invoke|toggle|select|expand|collapse|setvalue|focus> [-AutomationId <exact>] [-Name <glob>]
  [-ControlType <exact>] [-Path <child-index path>] [-Value <s>] [-DryRun]` (or `-InputsJson '<json>'`);
  wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** perform ONE UIA control-pattern action on a single element located by automation id /
  name / control type / inspector child-path: invoke, toggle, select, expand, collapse, setvalue, focus.
  UIA patterns only (no synthetic mouse/keyboard). `-DryRun`/`-WhatIf` resolves + reports the intended action
  without performing it; before/after control state captured on real actions.
- **I/O:** in = `{hwnd,pid,title,action,automation_id,name,control_type,path,value,dry_run,depth,max_elements}`;
  out = `lifeorch.skill.result/0.1` envelope (result = `{target, action, dry_run, performed, actionable,
  requested_pattern, pattern_supported, locator, resolved_element, candidate_count, candidates[],
  before_state, after_state, blockers[]}`) + `runtime/artifacts/<id>/{action.md,action.json,stderr.txt,result.json}`.
- **quality:** deterministic (confidence null) · **speed:** ~1–5s (bounded property search when no path) ·
  **CPU/GPU/mem:** low/none/~256MB · **network:** none · **cost:** local only.
- **limitations:** **side-effecting** (`parallel_safe:false`); one action per invocation; no window
  management (move/resize/close), no scroll/range-value/multi-select, no keyboard text where no ValuePattern,
  no wait-for-element retries; ambiguous locators error with a candidate list (refine or use path); targets
  that expose no usable pattern return `pattern_unsupported`.
  · **last test:** 2026-07-24 via executor (tests **26/26**; live invoke/toggle/setvalue on a WinForms probe). · **skills:** `uia.actor`.

### `capture.screen` — Screenshot & Region Capture (Module 6)
- **status:** installed · **type:** skill (PowerShell + WinForms/GDI + Win32 via Add-Type) ·
  **location:** `LifeOrchestrator-Refresh/modules/06-capture-screen/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 [-Target <monitor|window|app|region>]
  [-Monitor <index|all|primary>] [-Hwnd <n>|-ProcessId <n>|-Title <glob>] [-App <glob>] [-X -Y -Width -Height]
  [-Format <png|jpg>]` (target inferred from the locator when omitted; or `-InputsJson '<json>'`); wrapped via
  `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** capture a monitor / a top-level window (hwnd/pid/title) / an app's main window (process
  name) / an explicit screen rectangle to a PNG (or JPG q90). The visual-capture complement to the UIA skills —
  use when a target exposes no usable UIA tree (Unity/game/canvas) or visual verification is needed.
- **I/O:** in = `{target,monitor,hwnd,pid,title,app,x,y,width,height,format}`; out = `lifeorch.skill.result/0.1`
  envelope (result = `{mode, requested, capture{rectangle,format,image_width,image_height,path,bytes,sha256},
  window, monitor, environment{virtual_screen,monitors[]}}`) + `runtime/artifacts/<id>/{capture.png|jpg,
  capture.json,capture.md,stderr.txt,result.json}`.
- **quality:** deterministic pixel copy of live screen state (confidence null) · **speed:** ~1–2s ·
  **CPU/GPU/mem:** low/none/~256MB · **network:** none · **cost:** local only.
- **limitations:** **read-only, screen-pixel copy** — captures whatever is on screen at the target's rect; an
  occluded window captures what covers it, a minimized window is `window_minimized`; it does **not**
  raise/activate/move windows and uses no synthetic input (`parallel_safe:true`). No image post-processing
  (resize/crop/OCR/base64 → Module 15), no off-screen `PrintWindow` compositing, no video/batch. Per-Monitor-V2
  DPI awareness set once per process. · **last test:** 2026-07-24 via executor (tests **39/39**; smoke
  `m6-smoke-001` captured a real dual-monitor primary). · **skills:** `capture.screen`.

### `exec.watchdog` — Executor Watchdog & Recovery (Module 00.1)
- **status:** installed · **type:** service + tool (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/00.1-exec-watchdog/`
- **invocation:** `ops/start-watchdog.bat` (supervise) · `ops/stop-watchdog.bat` · `ops/recover-executor.bat [-Force]`;
  direct `pwsh -File .\Watch-Executor.ps1` / `.\Recover-Executor.ps1`.
- **supported tasks:** **cooperative** auto-recovery of the executor — restart on crash / hard-kill, kill+restart
  on hang; **stand down** on an authorized graceful stop (`last-exit` reason `stop_requested`/`signal`). On-demand
  force kill+restart via `Recover-Executor.ps1 -Force`. Crash-loop backoff.
- **I/O:** reads `control/{executor.lock,heartbeat.json,last-exit.json}`; writes `control/watchdog.json`,
  `logs/watchdog.log`; honors `control/watchdog.stop.requested`. `Recover-Executor.ps1` prints a
  `lifeorch.exec.recovery/0.1` JSON summary.
- **quality:** deterministic decision logic (`Get-WatchdogDecision`, pure) · **speed:** poll ~10s · **CPU/GPU/mem:** low/none/low ·
  **network:** none · **cost:** local only.
- **limitations:** **cooperative, not perpetual** by design (honors manual stop — a `taskkill /F`/power-loss looks
  like a crash and is recovered); **no** boot/OS persistence, does not survive logout/reboot, does not self-revive;
  session-scoped and user-launched; single host. Window-close is honored best-effort via a C# console-ctrl handler
  (verify on your machine; else stop via Ctrl+C / `stop-executor.bat`). · **last test:** 2026-07-24 via executor
  (tests **22/22**; Module 0 regression re-run 12/12). · **skills:** `exec.watchdog`. See DECISION_LOG D-0013.

### `model.gateway` — Local Model Gateway (Module 7)
- **status:** installed · **type:** skill (PowerShell wrapping llama.cpp `llama-server`) ·
  **location:** `LifeOrchestrator-Refresh/modules/07-model-gateway/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 [-Model <id>|-Tier <tiny|weak|mid|strong>]
  -Prompt <s> [-System <s>] [-MaxTokens -Temperature -TopP -TopK -Seed -Stop] [-Registry -Port -GpuLayers -Context
  -LoadTimeoutSec -ReviewQueuePath]` (or `-InputsJson '<json {…,messages[]}>'`); wrapped via
  `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** run a local **LLM** (GGUF text) and return the completion + token counts + timings +
  finish_reason, with full `model_provenance` and a `confidence`. Model chosen from `models.json` by id/tier/default.
  Declares STT/TTS/embedding (staged) but returns `model_not_wired` for them (wired in Modules 11/12/23).
- **I/O:** in = `{model|tier, prompt|messages, system, max_tokens, temperature, top_p, top_k, seed, stop, …}`;
  out = `lifeorch.skill.result/0.1` envelope (result = `{model, engine, mode, selected_from, request, output{text},
  generation{finish_reason,prompt_tokens,completion_tokens,total_tokens,timings}, server{port,health_ms,gpu_layers,
  context}}`) + `runtime/artifacts/<id>/{output.txt,exchange.json,result.json,stderr.txt,server.*.log}`.
- **determinism:** **mixed** (deterministic wrapping; stochastic output) · **confidence:** heuristic
  (stop→0.7, length→0.4, empty→0.1; `<0.5` → review queue) · **speed:** small models load+gen in ~1–2 s
  (GPU); 27B slower (partial offload) · **CPU/GPU/mem:** low / **CUDA (RTX 2080 Ti)** / ~2 GB+model ·
  **network:** none (loopback only) · **cost:** local only.
- **limitations:** **`parallel_safe:false`** (per-call server binds a port + most of VRAM); one server per call
  (no warm worker — D-0002); LLM text only in the MVP; no streaming; no auto model selection (routing = Module 24).
  · **last test:** 2026-07-24 via executor (**tests 28/28**, live 0.5B/1.5B). · **skills:** `model.gateway`. See D-0016.

---

## Hardware profile (measured 2026-07-24 — DESKTOP-PF5FFMF)
- **CPU:** Intel Core i9-9900KF — 8 cores / 16 threads @ 3.6 GHz.
- **RAM:** 64 GB (63.9 GB total; ~38 GB free at measure).
- **GPU:** **NVIDIA GeForce RTX 2080 Ti, 11 GB VRAM** (11264 MiB), driver 591.74, compute cap 7.5, CUDA present
  (nvidia-smi). (Two DisplayLink USB "adapters" are not compute GPUs.)
- **OS:** Windows 10 Pro 19045 (x64). **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**);
  E: "Game Drive" 858 GB (~534 GB free); **F: "Storage space" 3.72 TB (~1.78 TB free)** — large-data home. (No D:.)

## Local model runtimes (verified on this machine)
- **llama.cpp `llama-server` / `llama-cli`** — CUDA build **b8661 (b7ad48ebd)**, at
  `F:\Qwen3.5-27B\llama.cpp\build\bin\`; **portable copy staged** at
  `F:\…\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\_engines\llama.cpp\bin\` (runs standalone;
  needs a system CUDA runtime). `model.gateway` uses `llama-server` (chat completions). Note: this build's
  `llama-cli` is interactive-only (rejects `-no-cnv`); use `llama-server` for scripting.
- **whisper.cpp** — CUDA + CPU builds with `whisper-cli.exe`/`whisper-server.exe` under
  `F:\Local_TTS_Large_Data\external\whisper.cpp_{cuda,cpu_backup_2026_04_17}\build\bin\Release\`. *For Module 11.*
- **Speech Python venv** — `F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\` (Python 3.12.10; torch
  2.11.0+cu128, torchaudio, transformers 4.57.3, accelerate, safetensors, soundfile, librosa, onnxruntime). *For Module 12.*
- **System Python** 3.12.10 (`…\AppData\Local\Programs\Python\Python312`) with torch 2.2.1 + onnxruntime-gpu/directml.
- Ollama / LM Studio: **not installed.** git / winget / .NET SDK 9 / node: present (see above).

## Installed local models (inventory — DO NOT re-download; portable copies staged on F:)
All staged under `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\` (see that folder's
`MIGRATION.md`). `wired` = runnable by `model.gateway` today.

| model_id | type | file/dir (staged) | size | engine | wired |
|---|---|---|---|---|---|
| `llm.weak.qwen2p5-0p5b` | llm | `llm\Qwen2.5-0.5B-Instruct-Q4_K_M\…gguf` | 0.38 GB | llama-server | **yes** |
| `llm.weak.qwen2p5-1p5b` | llm | `llm\Qwen2.5-1.5B-Instruct-Q4_K_M\…gguf` | 0.94 GB | llama-server | **yes** (default) |
| `llm.weak.qwen2p5-3b` | llm | `llm\Qwen2.5-3B-Instruct-IQ4_XS\…gguf` | 1.66 GB | llama-server | **yes** |
| `llm.strong.qwen3p5-27b` | llm | `llm\Qwen3.5-27B-Q4_K_M\…gguf` | 16.3 GB | llama-server | **yes** (partial GPU) |
| `stt.whisper.base-en` | stt | `stt\whisper-ggml-base.en\ggml-base.en.bin` | 0.14 GB | whisper.cpp | no → M11 |
| `tts.tokenizer.qwen3-12hz` | tts-comp | `tts\Qwen3-TTS-Tokenizer-12Hz\` | 0.65 GB | transformers | no → M12 |
| `tts.weak.qwen3-0p6b` | tts | `tts\Qwen3-TTS-12Hz-0.6B-CustomVoice\` | 2.38 GB | transformers | no → M12 |
| `tts.strong.qwen3-1p7b` | tts | `tts\Qwen3-TTS-12Hz-1.7B-CustomVoice\` | 4.31 GB | transformers | no → M12 |
| `embedding.qwen3-0p6b` | embedding | `embedding\Qwen3-Embedding-0.6B\` | 1.12 GB | transformers | no → M23 |

Tiers (`models.json`): `tiny`=0.5B, `weak`=1.5B (default), `mid`=3B, `strong`=27B. Source originals (may be
removed by the user) are listed in `_pending-model-storage\MIGRATION.md`.

## Large-data storage (F:)
- **Root:** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` — home for all module data >~50 MB (D-0015).
  Contains `_engines\` (staged llama.cpp), `_pending-model-storage\` (~27.4 GB, all models pending relocation),
  `README.md`, and a `.lnk` back to the repo `modules\`. A `.lnk` in the repo `modules\` folder points here.
- **Rule:** the C: repo never stores model weights; skills reference models by absolute F: paths in their registry.
  As owning modules are built, models move into `…_Large_Data\<NN>-<module>\` and `_pending-model-storage\` shrinks
  (delete it when empty). See `_pending-model-storage\MIGRATION.md`.

### Planned / not yet present (do not assume these exist)
- **Vision / multimodal** models — none yet (Modules 16–17). C++ toolchain for native modules — verify
  (CMake/MSVC) before the first C++ module; register when confirmed.

**Discipline:** never list a tool as `installed` you have not actually invoked on this machine. Prefer
`planned` until verified, and record the `last successful test` date on every status change.
