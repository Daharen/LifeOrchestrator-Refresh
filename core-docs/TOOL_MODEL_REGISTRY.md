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

### `ffmpeg` / `ffprobe` — media transcode + probe (Gyan.dev full build)
- **status:** installed · **type:** executable · **location:** `ffmpeg` on PATH at
  `C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe` (WinGet `Gyan.FFmpeg`; real package bin
  `…\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-8.1-full_build\bin\`). **Version 8.1-full_build.**
- **invocation:** `ffmpeg -hide_banner -nostdin -y -i <in> [filters] [-ar -ac -c:a -b:a] -map_metadata -1 <out>`;
  `ffprobe -v error -print_format json -show_format -show_streams <file>`.
- **supported tasks:** decode/encode/transcode/resample/rechannel/loudness-normalize audio (and general A/V); probe
  media metadata. Full encoder set: libmp3lame, aac, flac, libopus, libvorbis, pcm_s16le/s24le/s32le/f32le, +video.
- **quality:** deterministic transcode · **speed:** fast (CPU; NVENC/CUDA available) · **network:** none · **cost:** local only.
- **limitation / gotcha:** **`ffprobe` on PATH is shadowed** — `where.exe ffprobe` returns a Python
  `…\Python310\Scripts\ffprobe.exe` shim *before* the real `…\WinGet\Links\ffprobe.exe`. Resolve ffprobe as the
  **sibling of the resolved ffmpeg** (or exclude `\Python*\Scripts\`). The Linux device-mount cannot `stat` the
  WinGet `Links\*.exe` reparse points (Windows `Test-Path`/`where.exe` resolve them fine). · **last test:**
  2026-07-24 (`m10-ffprobe-001`; used by Module 10). · **skills:** `audio.ingest`.

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

### `classify.batch` — Batch Classification & Sorting (Module 8)
- **status:** installed · **type:** skill (PowerShell; **consumes `model.gateway`**) ·
  **location:** `LifeOrchestrator-Refresh/modules/08-classify-batch/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '<json {mode,tier|model,
  labels|fields,items|items_path,max_tokens,temperature,seed,max_input_chars,confidence_threshold,...}>'` (or named
  params `-Mode -Tier -Labels -Fields -Items ...`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`;
  or an `exec.bootstrap` task. Spawns the gateway child with `-PwshPath` (default the dotnet-tool pwsh).
- **supported tasks:** batch **categorize / label / extract** over a list of `{id?,text}` items. `mode=classify`
  (exactly one label from a closed `labels` set — also routing/sorting), `multilabel` (zero+ labels), `extract`
  (named `fields` → JSON object). Calls `model.gateway` once per item (default `-Tier weak`=1.5B), groups results
  (`label→[ids]`), routes low-confidence items to the review queue.
- **I/O:** in = the JSON above (items inline or via `items_path` .jsonl/.json); out = `lifeorch.skill.result/0.1`
  envelope (result = `{mode, model, selected_from, labels?|fields?, count, ok_count, flagged_count, error_count,
  confidence_threshold, items[{id,label?|labels?|extracted?,confidence,finish_reason,in_set,flagged,flag_reason,
  review_id,...}], groups{}, review_queue_path, review_count}`) + `runtime/artifacts/<id>/{classified.json,
  classified.md,result.json,stderr.txt, gateway/…, _gateway_review_suppressed.jsonl}`.
- **determinism:** **mixed** (deterministic orchestration/parsing/grouping; stochastic model labels) ·
  **confidence:** per-item completeness+validity **heuristic** (classify in-set+stop 0.8 / fuzzy 0.6 / out-of-set 0.2;
  multilabel 0.75/0.7/0.5/0.15; extract 0.75/0.5/0.3/0.1; `length` caps ≤0.4); envelope confidence = mean per-item;
  `<threshold` (default 0.5) → `review_queue.jsonl` (`flagged_by:"classify.batch"`) · **speed:** per-item ×
  gateway per-call model load (small models ~2–5 s/item) · **CPU/GPU/mem:** low / CUDA (via gateway) / ~2 GB+model ·
  **network:** none · **cost:** local only.
- **limitations:** **`parallel_safe:false`** (drives the gateway → GPU/port contention); **one gateway call per item**
  with per-call model load (no warm worker — throughput caveat; D-0002/D-0016); closed label/field sets only (no
  open-vocabulary/taxonomy learning); heuristic (not calibrated) confidence; grouping/index only — **no physical file
  moving** (a `sort.files` mover is a follow-on); suppresses the gateway's own review-queue writes to the artifact dir.
  · **last test:** 2026-07-24 via executor (**tests 33/33**; `m8-test-001`, exit 0, ~26s). · **skills:**
  `classify.batch`. See D-0017.

### `review.processor` — Review Queue Processor (Module 9)
- **status:** installed · **type:** skill (PowerShell; **consumes `model.gateway`**) ·
  **location:** `LifeOrchestrator-Refresh/modules/09-review-processor/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 [-QueuePath <file> | -ReviewQueuePath]
  [-MaxItems <n>] [-FlaggedBy <model.gateway|classify.batch>] [-Reason <s>] [-Tier <tiny|weak|mid|strong> | -Model <id>]
  [-GpuLayers <n>] [-LoadTimeoutSec <s>] [-EscalateThreshold <0..1>] [-DryRun] [-ResolutionLogPath <file>]` (or
  `-InputsJson '<json {queue_path,max_items,flagged_by,reason,ids,tier,model,gpu_layers,load_timeout_s,max_tokens,
  temperature,seed,escalate_threshold,max_fragment_chars,dry_run,resolution_log_path,registry,gateway_path,pwsh_path}>'`);
  wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** **drain `review_queue.jsonl`** — select OPEN flagged items (both producers) and adjudicate each
  **single** item with a **stronger** local model (default `-Tier mid`=3B; `strong`=27B) via `model.gateway`, consuming
  only the item + its `source_ref` fragment + `weak_result`. Resolves (`resolution`+`status:"resolved"`) or escalates
  (`status:"escalated"`, `escalated_to:"frontier"`). Updates the queue **in place** (history preserved) + appends
  `review_resolved.jsonl` (`lifeorch.review.resolution/0.1`); `-DryRun` writes nothing.
- **I/O:** in = the JSON above (queue on disk); out = `lifeorch.skill.result/0.1` envelope (result = `{queue_path,
  dry_run, tier, reviewer_model, selected_from, escalate_threshold, selected_count, resolved_count, escalated_count,
  error_count, skipped_malformed, open_remaining, queue_written, items[{id,flagged_by,reason,requested,kind,
  prior_status,new_status,verdict,decision,reviewer_confidence,model_self_confidence,escalated_to,finish_reason,
  source_fragment_resolved,error}], resolution_log_path, resolution_count}`) + `runtime/artifacts/<id>/{review.json,
  review.md,result.json,stderr.txt, gateway/…, _gateway_review_suppressed.jsonl}`.
- **determinism:** **mixed** (deterministic select/parse/queue-rewrite; stochastic reviewer output) · **confidence:**
  structural reviewer heuristic (valid JSON verdict + in-set corrected answer + generation completeness; `length` caps
  ≤0.4; envelope = mean over adjudicated items) · **speed:** `mid`(3B) ~5s load + fast; `strong`(27B) slow (~2 tok/s,
  cold load ~90s — pass `-LoadTimeoutSec 300`) · **CPU/GPU/mem:** low / CUDA (via gateway) / ~2–4 GB+model ·
  **network:** none · **cost:** local only.
- **limitations:** **`parallel_safe:false`** (drives the gateway + rewrites the shared queue file); **one gateway call
  per item** with per-call model load (no warm worker — D-0002/D-0016); heuristic (not calibrated) reviewer confidence;
  escalation is a **status transition**, not a frontier call (the frontier / #24 drains `escalated`); the in-place
  write re-reads immediately before an atomic replace but is not a full concurrency protocol (single background drainer
  assumed); a thinking-style `strong` model may exhaust `max_tokens` before the JSON verdict → safely escalated (tune
  follow-on); no compaction/archival of resolved items (follow-on). · **last test:** 2026-07-24 via executor
  (**tests 34/34**; `m9-test-003`, exit 0, ~150s incl. the 27B). · **skills:** `review.processor`. See D-0018.

### `audio.ingest` — Audio Ingest / Normalize & Convert (Module 10)
- **status:** installed · **type:** skill (PowerShell wrapping `ffmpeg`/`ffprobe`) ·
  **location:** `LifeOrchestrator-Refresh/modules/10-audio-ingest/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile <path> [-Format <wav|mp3|flac|
  opus|ogg|m4a>] [-SampleRate <hz|0>] [-Channels <1|2|0>] [-SampleFormat <s16|s24|s32|flt>] [-Loudness <none|peak|
  ebu>] [-PeakDb -LoudnessI -LoudnessTP -LoudnessLRA] [-Bitrate <e.g. 192k>] [-FfmpegPath -FfprobePath]` (or
  `-InputsJson '<json {input,format,sample_rate,channels,sample_fmt,loudness,peak_db,loudness_i,loudness_tp,
  loudness_lra,bitrate,ffmpeg_path,ffprobe_path}>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`;
  or an `exec.bootstrap` task.
- **supported tasks:** normalize+convert one audio/media file (first audio stream; audio extracted from video) to a
  target format/rate/channels/sample-format with optional peak or EBU R128 loudness. **Defaults produce whisper-ready
  16 kHz mono s16 WAV** — the front door for the audio track (feeds Module 11 `speech.stt`).
- **I/O:** in = a file path + options; out = `lifeorch.skill.result/0.1` envelope (result = `{input{path,exists,
  audio_stream_present,probe}, output{path,format,container,codec,sample_rate,channels,sample_fmt,bitrate,duration_s,
  bytes,sha256,probe}, normalization{sample_rate,channels,sample_fmt,loudness}, ffmpeg{path,version,argv[]},
  ffprobe{path}}`) + `runtime/artifacts/<id>/{audio.<ext>,ingest.json,ingest.md,result.json,stderr.txt}`.
- **determinism:** deterministic (confidence null; no model) · **speed:** ~0.5–2 s for short clips (CPU) ·
  **CPU/GPU/mem:** CPU / none / ~256 MB · **network:** none · **cost:** local only.
- **limitations:** one input → one output (`batch:false`; no directory/batch); audio only (video dropped, `-vn`); no
  trimming/segmentation/VAD/concat/mix/denoise/EQ (→ Module 13 / follow-ons); `sample_fmt` applies to wav only;
  requires `ffmpeg`/`ffprobe` (present). `parallel_safe:true` (CPU-bound; heavy fan-out contends CPU only). · **last
  test:** 2026-07-24 via executor (**tests 43/43**; `m10-test-001`, exit 0, ~17s; pre-shipped on cloud ffmpeg 6.1
  43/43). · **skills:** `audio.ingest`. See D-0019.

### `speech.stt` — Speech-to-Text Transcription (Module 11)
- **status:** installed · **type:** skill (PowerShell wrapping the whisper.cpp `whisper-cli`) ·
  **location:** `LifeOrchestrator-Refresh/modules/11-speech-stt/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputFile <path> [-Normalize <auto|always|never>]
  [-Language <code>] [-Translate] [-Threads <n>] [-NoGpu] [-BeamSize <n>] [-BestOf <n>] [-MaxLen <n>] [-SplitOnWord]
  [-OffsetMs <ms>] [-DurationMs <ms>] [-SegmentConfidenceThreshold <0..1>] [-MaxReviewSegments <n>] [-Model <id>]
  [-Registry|-WhisperCliPath|-AudioIngestPath|-PwshPath|-ReviewQueuePath <override>]` (or `-InputsJson '<json {input,
  normalize,language,translate,threads,no_gpu,beam_size,best_of,max_len,split_on_word,offset_ms,duration_ms,
  segment_confidence_threshold,max_review_segments,min_speech_seconds,model,registry,whisper_cli_path,audio_ingest_path,
  pwsh_path,review_queue_path}>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an
  `exec.bootstrap` task.
- **supported tasks:** timestamped transcription of one audio/media file. Resolves the STT model + whisper CLI from
  `models.json`; consumes whisper-ready 16 kHz mono s16 WAV directly and **normalizes other inputs via `audio.ingest`**
  (Module 10). Emits timestamped segments with per-segment + overall confidence (mean whisper token probability).
- **I/O:** in = a file path + options; out = `lifeorch.skill.result/0.1` envelope (result = `{input,audio,model,params,
  language,text,segment_count,token_count,confidence{overall,min_segment,low_confidence_segments},
  segments[{index,t0_ms,t1_ms,t0,t1,text,confidence,token_count,low_confidence}],review{threshold,flagged_count,truncated,
  queue_path},whisper{cli,systeminfo,runtime_ms,real_time_factor}}`) + `runtime/artifacts/<id>/{whisper.json,whisper.srt,
  whisper.txt,transcript.json,transcript.md,result.json,stderr.txt,whisper.log, normalize/…}`.
- **determinism:** **mixed** (deterministic orchestration/parse; stochastic model output) · **confidence:** mean whisper
  per-token probability over content tokens (per-segment + overall); `< -SegmentConfidenceThreshold` (0.5) → `review_queue.jsonl`
  (`flagged_by:"speech.stt"`, bounded by `-MaxReviewSegments`) · **speed:** base.en on **CUDA (RTX 2080 Ti)** ≈ 0.07
  real-time factor (11 s audio in ~0.7 s) · **CPU/GPU/mem:** low / CUDA (CPU fallback via `-NoGpu`/CPU build) / ~1 GB.
- **limitations:** **`parallel_safe:false`** (binds the CUDA context, like `model.gateway`); one file per invocation
  (`batch:false` — no directory/batch); no VAD/segmentation/diarization/word-level artifacts (→ Module 13 / follow-ons);
  `base.en` is English-only; per-call CLI spawn (no warm whisper-server yet); confidence is a token-probability signal,
  not calibrated correctness. · **last test:** 2026-07-24 via executor (**tests 27/27**; `m11-test-001`, exit 0, ~14 s;
  live smoke `m11-smoke-001` transcribed jfk.wav on CUDA). · **skills:** `speech.stt`. See D-0020.

### `speech.tts` — Text-to-Speech Synthesis (Module 12)
- **status:** installed · **type:** skill (PowerShell wrapper + Python worker `tts_infer.py` under the speech venv) ·
  **location:** `LifeOrchestrator-Refresh/modules/12-speech-tts/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -Text <string> [-Speaker <name>] [-Language <name>]
  [-Instruct <style>] [-Seed <int>] [-Dtype <bfloat16|float16|float32>] [-SampleRate <hz|0>] [-Format <wav|mp3|flac|opus|
  ogg|m4a>] [-MaxNewTokens <n>] [-ConfidenceThreshold <0..1>] [-Model <id>] [-Registry|-PythonPath|-TtsInferPath|
  -AudioIngestPath|-PwshPath|-ReviewQueuePath <override>]` (or `-InputsJson '<json {text,speaker,language,instruct,seed,
  dtype,sample_rate,format,max_new_tokens,confidence_threshold,model,registry,python_path,tts_infer_path,audio_ingest_path,
  pwsh_path,review_queue_path}>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** synthesize one utterance of speech from text using Qwen3-TTS CustomVoice (preset speakers).
  Resolves the TTS model + venv python from `models.json`; produces 24 kHz mono PCM16 WAV; optional format/rate conversion
  via `audio.ingest`. English speakers Ryan/Aiden (+ Chinese/Japanese/Korean voices — use the text's native language).
- **I/O:** in = text + options; out = `lifeorch.skill.result/0.1` envelope (result = `{input{text,chars}, model{id,name,
  engine,engine_env,device,dtype,attn}, params{speaker,language,instruct,seed,max_new_tokens}, audio{path,sample_rate,
  channels,samples,duration_s,bytes,sha256,format,native_sample_rate,converted}, confidence{overall,reason}, review{
  threshold,flagged,queue_path}, synthesis{runtime_ms,real_time_factor}}`) + `runtime/artifacts/<id>/{speech.wav,tts.json,
  tts.md,result.json,stderr.txt,py.log,tts_args.json,tts_meta.json, convert/…}`.
- **determinism:** **mixed** (deterministic orchestration; the model samples with `do_sample=true`, seedable via `-Seed`) ·
  **confidence:** synthesis-completeness heuristic (audio produced + duration vs. input length; `< -ConfidenceThreshold`
  0.5 → `review_queue.jsonl`, `flagged_by:"speech.tts"`) · **speed:** per-call model load ~30–40 s cold; synthesis ~5×
  real-time on the RTX 2080 Ti (rtf ≈ 5.2 for the 0.6B) · **CPU/GPU/mem:** low / **CUDA (RTX 2080 Ti)** / ~2–4 GB+model.
- **limitations:** **`parallel_safe:false`** (binds the CUDA context + loads a model); one utterance per invocation
  (`batch:false`); per-call model load (no warm worker yet); GPU (CUDA) required; preset-speaker CustomVoice only (no
  voice clone/design in the MVP); confidence is a completeness signal, not audio quality. · **last test:** 2026-07-24 via
  executor (**tests 25/25**; `m12-test-001`, exit 0, ~132 s; live smoke `m12-smoke-001` synthesized 5.52 s on CUDA). ·
  **skills:** `speech.tts`. See D-0021.

### `voice.live` — Voice Interaction Loop (Module 13)
- **status:** installed · **type:** skill (PowerShell orchestrator; composes other skills) ·
  **location:** `LifeOrchestrator-Refresh/modules/13-voice-live/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile <audio> [-Respond <bool>] [-Speak <bool>]
  [-ReadbackTranscript <bool>] [-System <prompt>] [-Tier <tiny|weak|mid|strong>] [-MaxTokens <n>] [-Speaker <name>]
  [-Language <name>] [-Format <wav|mp3|...>] [-SttModel|-GatewayModel|-TtsModel <id>] [-SttPath|-GatewayPath|-TtsPath|
  -PwshPath|-ReviewQueuePath <override>]` (or `-InputsJson '<json {input,respond,speak,readback_transcript,system,tier,
  max_tokens,speaker,language,stt_model,gateway_model,tts_model,format,stt_path,gateway_path,tts_path,pwsh_path,
  review_queue_path}>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** one **voice turn** from an audio file — transcribe (`speech.stt`; whisper segments = utterance/VAD)
  → optionally answer (`model.gateway`) → optionally speak the answer/transcript (`speech.tts`) to `reply.wav`. Composes
  the child skills (spawned as pwsh; overridable paths) and parses their envelopes; reimplements nothing.
- **I/O:** in = an audio path + options; out = `lifeorch.skill.result/0.1` envelope (result = `{input{path},
  speech_detected, transcript{text,utterance_count,confidence,language,artifact_dir}, response{text,model,confidence,
  finish_reason}|null, reply{path,format,sample_rate,duration_s,bytes,sha256}|null, stages[{name,status,ms,error}],
  config{…}, child_review_path, child_review_count}`) + `runtime/artifacts/<id>/{voice.json,voice.md,reply.wav,
  result.json,stderr.txt,child_review.jsonl, stt/,gateway/,tts/}`.
- **determinism:** **mixed** (deterministic orchestration; stochastic children) · **confidence:** = the STT transcript
  confidence · **model_provenance:** aggregate of all child models (stt+gateway+tts), stage-tagged · **speed:** a full
  turn pays three cold model loads (~1–2 min; observed ~58 s — stt ~1.8 s / respond ~2.7 s / speak ~54 s) · **CPU/GPU/mem:**
  low / **CUDA** (via children) / ~2–4 GB+models.
- **limitations:** **`parallel_safe:false`** (children bind CUDA sequentially); one turn per invocation (`batch:false`);
  three cold model loads (no warm worker); **file-driven only** — no live mic capture / streaming (non-goal); standalone
  VAD deferred (no VAD ggml model staged); it is an **orchestrator, not a review producer** (aggregates child flags to
  an in-artifact file by default). · **last test:** 2026-07-24 via executor (**tests 21/21**; `m13-test-001`, exit 0; live
  smoke `m13-smoke-001` — full JFK turn, 12.56 s reply). · **skills:** `voice.live`. See D-0022.

### `ocr.layout` — OCR + Layout (Module 14)
- **status:** installed · **type:** skill (pwsh-7 wrapper + Windows PowerShell 5.1 WinRT worker `ocr_worker.ps1`) ·
  **location:** `LifeOrchestrator-Refresh/modules/14-ocr-layout/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputFile <image> [-Language <bcp47>]
  [-Engine <model_id>|-Model <id>] [-ConfidenceThreshold <0..1>] [-MaxReviewLines <n>] [-Capture]
  [-CaptureInputsJson '<json>'] [-Registry|-OcrWorkerPath|-Powershell51Path|-CapturePath|-PwshPath|-ReviewQueuePath
  <override>]` (or `-InputsJson '<json {input,language,engine,model,confidence_threshold,max_review_lines,capture,
  capture_inputs,min_image_pixels,registry,ocr_worker_path,powershell51_path,capture_path,pwsh_path,review_queue_path}>'`);
  wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** OCR one image → recognized **text + per-word pixel bounding boxes + lines in reading order**
  (+ text angle). The visual text-extraction complement to `capture.screen`; use for screenshots, scanned pages, UI/canvas
  text, or — with `-Capture` — text read straight off the live screen (composes `capture.screen`, Module 6).
- **I/O:** in = an image path (png/jpg/bmp/tif/gif) or a `-Capture` spec; out = `lifeorch.skill.result/0.1` envelope
  (result = `{input{path,exists,source,capture?}, image{width,height,text_angle}, engine{id,name,engine,
  recognizer_language,available_languages}, params, text, word_count, line_count, lines[{index,text,confidence,
  low_confidence,bounding_rect{x,y,width,height},words[{text,x,y,width,height}]}], confidence{overall,min_line,
  low_confidence_lines,reason}, review{...}, ocr{engine_env,runtime_ms,max_image_dimension}}`) +
  `runtime/artifacts/<id>/{ocr.json,ocr.md,ocr_args.json,ocr_meta.json,worker.log,result.json,stderr.txt, capture/…}`.
- **determinism:** **mixed** (deterministic orchestration; perception output) · **confidence:** legibility **heuristic**
  (fraction of clean words → [0.1,0.9] per line + overall; NOT calibrated; `<threshold` 0.5 → `review_queue.jsonl`
  `flagged_by:"ocr.layout"`, `verify_ocr`/`verify_no_text`) · **speed:** ~0.5–1 s (per-call `powershell.exe` spawn; the
  OCR itself ~74 ms) · **CPU/GPU/mem:** low / none / ~256 MB · **network:** none · **cost:** local only.
- **limitations:** **`parallel_safe:true`** (binds no port/VRAM/CUDA; only shared write is the append-only review queue);
  one image per invocation (`batch:false`); **Windows.Media.Ocr only** in the MVP (Tesseract declared, not wired);
  no per-word confidence from the engine (heuristic); an image over `MaxImageDimension` (10000 px) returns
  `image_too_large` (downscale → Module 15 follow-on); no overlay PNG / multi-column reflow / PDF (follow-ons);
  **`ocr_worker.ps1` must stay ASCII-only** (Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8). ·
  **last test:** 2026-07-25 via executor (**tests 30/30**; `m14-test-003`, exit 0; real-registry smoke `m14-smoke-001`).
  · **skills:** `ocr.layout`. See D-0023.

### `Windows.Media.Ocr` — system OCR engine (used by ocr.layout)
- **status:** installed (system) · **type:** WinRT API (`Windows.Media.Ocr.OcrEngine`) · **location:** OS component;
  reached via **Windows PowerShell 5.1** at `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe` (5.1.19041.6456).
- **supported tasks:** printed-text OCR → words with `BoundingRect`, lines (reading order), `TextAngle`. Recognizer
  languages present: **en-US**. `MaxImageDimension = 10000`. Zero install, no admin, no GPU, no network, no model file.
- **gotcha:** **pwsh 7.4.6 cannot load the WinRT projection** on this box (`m14-probe-001`); reach it only from Windows
  PowerShell 5.1 via the `System.Runtime.WindowsRuntime` `AsTask`/`Await` reflection pattern (as `ocr_worker.ps1` does).
  Also: 5.1 parses a BOM-less `.ps1` as ANSI — keep any 5.1 worker ASCII-only. · **last test:** 2026-07-25
  (`m14-probe-001` live; `m14-test-003`). · **skills:** `ocr.layout`. Registry id `ocr.windows.media` (models.json, `wired:false`).

### `tesseract` — Tesseract OCR (declared; a future ocr.layout engine)
- **status:** installed, **not yet wired** · **type:** executable · **location:** `C:\Program Files\Tesseract-OCR\tesseract.exe`
  (found by `m14-probe-001`). · **supported tasks (when wired):** OCR with **calibrated per-word confidence** + hOCR/TSV
  boxes + multi-language. · **why declared:** the natural second engine behind `ocr.layout -Engine` and the calibrated-
  confidence follow-on; not built in the Module 14 MVP (one engine, per the one-module rule). Registry id `ocr.tesseract`.

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
  `F:\Local_TTS_Large_Data\external\whisper.cpp_{cuda,cpu_backup_2026_04_17}\build\bin\Release\`. **Verified + wired by
  `speech.stt` (Module 11), 2026-07-24.** Both builds load headless (`m11-probe-001`; the CUDA build initializes the RTX
  2080 Ti); flags confirmed on this build: `-oj`/`-ojf` (full JSON incl. per-token `p`), `-osrt`/`-otxt`, `-of <base>`,
  `-np`, `-l <lang>`, `-ng`, `-t`, `-bs`/`-bo` (`m11-probe-002` transcribed the bundled `samples\jfk.wav`, base.en on
  CUDA ≈ 0.07 rtf). `whisper-cli` accepts flac/mp3/ogg/wav; `speech.stt` still normalizes to 16 kHz mono s16 WAV via
  `audio.ingest` by default for determinism. `llama-cli`-style interactive gotchas do **not** apply here.
- **Speech Python venv** — `F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe` (Python
  3.12.10; torch 2.11.0+cu128, torchaudio, transformers 4.57.3, accelerate, safetensors, soundfile 0.13.1, librosa 0.11,
  onnxruntime, **`qwen_tts`**). **Verified + wired by `speech.tts` (Module 12), 2026-07-24** (`m12-probe-001/002`): CUDA
  available on the RTX 2080 Ti; `qwen_tts.Qwen3TTSModel.generate_custom_voice(...)` loads bf16 + `sdpa` (flash-attn absent)
  and returns `(List[np.ndarray], sr=24000)`. This is the venv the TTS models run under (registry `engine_env`).
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
| `llm.strong.qwen3p5-27b` | llm | `llm\Qwen3.5-27B-Q4_K_M\…gguf` | 16.3 GB | llama-server | **yes** (partial GPU, ngl=32 tuned M9) |
| `stt.whisper.base-en` | stt | `stt\whisper-ggml-base.en\ggml-base.en.bin` | 0.14 GB | whisper.cpp | **via `speech.stt`** (M11) |
| `tts.tokenizer.qwen3-12hz` | tts-comp | `tts\Qwen3-TTS-Tokenizer-12Hz\` | 0.65 GB | transformers | via bundle (M12) |
| `tts.weak.qwen3-0p6b` | tts | `tts\Qwen3-TTS-12Hz-0.6B-CustomVoice\` | 2.38 GB | transformers | **via `speech.tts`** (M12, default) |
| `tts.strong.qwen3-1p7b` | tts | `tts\Qwen3-TTS-12Hz-1.7B-CustomVoice\` | 4.31 GB | transformers | **via `speech.tts`** (M12) |
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
