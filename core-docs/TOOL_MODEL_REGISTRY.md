# TOOL_MODEL_REGISTRY

Owns **what already exists and can actually be used** — tools, executables, models, services, skills.
Prevents every fresh instance from rediscovering the machine; later becomes the basis for task routing.
Read only when selecting or invoking a tool/model. Add an entry the moment you install or verify something.

**Entry fields:** id · status · type · location · invocation · supported tasks · I/O formats ·
quality tier · speed · CPU/GPU/mem · network · cost · limitations · last successful test · skill ids.
**Status vocab:** installed · available · inactive · broken · planned · retired.

---

### `exec.bootstrap` — Trusted High-Risk Bootstrap Executor
- **status:** installed · **type:** skill/service (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (canonical; running instance `0a1f8e69…`. The original at `proteus_repo/tools/trusted-bootstrap-executor/` was stopped and is pending removal from the game repo.)
- **invocation:** `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` (+ `Submit-`/`Stop-`); tasks are
  directories atomically published into `runtime/pending/`.
- **supported tasks:** run arbitrary local PowerShell task packages with concurrency, timeout,
  output/exit/timing capture, restart recovery.
- **I/O:** in = task dir (`task.json` + `task.ps1`); out = `result.json` + `stdout.txt`/`stderr.txt`.
- **quality:** n/a (deterministic harness) · **speed:** poll-bounded (default 1s/200ms in tests) ·
  **CPU/GPU/mem:** low / none / low · **network:** none · **cost:** local only.
- **limitations:** trust-based (not a sandbox); Windows-focused (`taskkill`); no orphan-child reaping
  after crash; polling latency. · **last test:** 2026-07-24, 12/12 (pwsh 7.4.6). · **skills:** `exec.bootstrap`.

### `pwsh` — PowerShell 7.4.6 (runtime)
- **status:** installed · **type:** executable ·
  **location:** `C:\Users\just_\.dotnet\tools\pwsh.exe` (.NET global tool; user PATH `~\.dotnet\tools`).
- **invocation:** `pwsh -NoProfile -ExecutionPolicy Bypass -File <script>` (new shells) or the full path.
- **supported tasks:** primary scripting/execution runtime for skills and the executor.
- **limitations:** shim reports process path as `dotnet.exe` (pass explicit `-PwshPath`); pinned version
  because the latest tool package is broken; not on system PATH (per-user only). · **last test:** 2026-07-24.

### `dotnet` — .NET SDK 9.0.100
- **status:** installed · **type:** executable · **location:** `C:\Program Files\dotnet\dotnet.exe`
- **supported tasks:** build/run .NET & C++ interop tooling; installs .NET global tools (no admin).
- **network:** yes (NuGet). · **last test:** 2026-07-24 (installed the pwsh tool).

### `git` — version control
- **status:** installed · **type:** executable · **location:** on PATH ·
  **supported tasks:** repo ops in `proteus_repo`. · **last test:** 2026-07-24 (committed `c4e90c4`).

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
  **network:** none · **cost:** local only.
- **limitations:** reference/demo only; writes under its own module dir. · **last test:** 2026-07-24 via
  executor (`m1-direct-001`/`m1-wrapped-001` completed exit 0; module tests 11/11). · **skills:** `ref.echo`.

### `skill.bootstrap` — Skill contract tooling (Module 1)
- **status:** installed · **type:** library/tooling (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/01-skill-bootstrap/` (`lib/SkillContract.psm1`, `Invoke-Skill.ps1`)
- **invocation:** `Import-Module .\lib\SkillContract.psm1` → `Test-SkillManifest` / `Test-SkillResultEnvelope`;
  generic runner `pwsh -File .\Invoke-Skill.ps1 -SkillDir <dir> [-InputsJson '<json>']`.
- **supported tasks:** validate a `lifeorch.skill.manifest/0.1` manifest and a `lifeorch.skill.result/0.1`
  envelope; run any conforming skill and emit a `lifeorch.skill.invocation_report/0.1`.
- **I/O:** in = skill dir + optional inputs JSON; out = invocation-report JSON.
- **limitations:** field/type/enum checks (not full JSON-Schema); pwsh path defaults to the pinned
  dotnet-tool build. · **last test:** 2026-07-24 (11/11 module tests via executor). · **skills:** n/a (harness).

### `fs.observer` — Filesystem Observer (Module 2)
- **status:** installed · **type:** skill (PowerShell) ·
  **location:** `LifeOrchestrator-Refresh/modules/02-fs-observer/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path <dir> -Depth <n> [-Pattern <glob>]`
  (or `-InputsJson '<json>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** deterministic depth-bounded directory tree + metadata + name/glob search; no screenshots.
- **I/O:** in = `{path, depth, pattern, include_hidden, max_entries}`; out = `lifeorch.skill.result/0.1` envelope +
  `runtime/artifacts/<id>/{tree.md,index.json,stderr.txt,result.json}`.
- **quality:** deterministic (confidence null) · **speed:** sub-second for small trees · **CPU/GPU/mem:** low/none/~128MB ·
  **network:** none · **cost:** local only.
- **limitations:** point-in-time snapshot (no diffing); symlinks listed but not traversed; name-glob only (no content grep).
  · **last test:** 2026-07-24 via executor (tests 16/16; capture over the repo = 27 entries / 10 md matches). · **skills:** `fs.observer`.

### `proc.observer` — Process & Window Observer (Module 3)
- **status:** installed · **type:** skill (PowerShell + Win32 via Add-Type) ·
  **location:** `LifeOrchestrator-Refresh/modules/03-proc-observer/`
- **invocation:** direct `pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 [-NameFilter <glob>] [-VisibleOnly <bool>]`
  (or `-InputsJson '<json>'`); wrapped via `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`; or an `exec.bootstrap` task.
- **supported tasks:** snapshot running processes + top-level windows (titles, owning pid/name, bounds, min/max, foreground); no screenshots.
- **I/O:** in = `{visible_only, name_filter, max_items}`; out = `lifeorch.skill.result/0.1` envelope +
  `runtime/artifacts/<id>/{report.md,processes.json,windows.json,stderr.txt,result.json}`.
- **quality:** deterministic read of live state (confidence null; snapshot) · **speed:** ~1–3s (Win32 compile on first Add-Type) · **CPU/GPU/mem:** low/none/~128MB ·
  **network:** none · **cost:** local only.
- **limitations:** point-in-time (no diffing/stream); interactive session only (sees the desktop it runs in);
  protected-process Path/StartTime may be null. · **last test:** 2026-07-24 via executor (tests 16/16; capture = 319 procs / 16 windows). · **skills:** `proc.observer`.

---

### Planned / not yet present (do not assume these exist)
- Local LLM / vision / speech / embedding models — **none registered.** Add under Module 7
  (`model.gateway`) as they are installed, with real quality/speed/resource numbers.
- A C++ toolchain for native modules — verify (CMake/MSVC) before the first C++ module; register when confirmed.

**Discipline:** never list a tool as `installed` you have not actually invoked on this machine. Prefer
`planned` until verified, and record the `last successful test` date on every status change.
