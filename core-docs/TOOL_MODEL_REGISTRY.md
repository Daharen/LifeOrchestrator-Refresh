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

---

### Planned / not yet present (do not assume these exist)
- Local LLM / vision / speech / embedding models — **none registered.** Add under Module 7
  (`model.gateway`) as they are installed, with real quality/speed/resource numbers.
- A C++ toolchain for native modules — verify (CMake/MSVC) before the first C++ module; register when confirmed.

**Discipline:** never list a tool as `installed` you have not actually invoked on this machine. Prefer
`planned` until verified, and record the `last successful test` date on every status change.
