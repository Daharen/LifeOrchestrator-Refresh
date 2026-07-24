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
  **location:** `Project-Proteus-Refresh/modules/00-bootstrap-executor/` (working copy; original running instance still at `proteus_repo/tools/trusted-bootstrap-executor/`)
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

---

### Planned / not yet present (do not assume these exist)
- Local LLM / vision / speech / embedding models — **none registered.** Add under Module 7
  (`model.gateway`) as they are installed, with real quality/speed/resource numbers.
- A C++ toolchain for native modules — verify (CMake/MSVC) before the first C++ module; register when confirmed.

**Discipline:** never list a tool as `installed` you have not actually invoked on this machine. Prefer
`planned` until verified, and record the `last successful test` date on every status change.
