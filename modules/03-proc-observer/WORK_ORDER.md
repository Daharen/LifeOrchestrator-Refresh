# Work Order: Process & Window Observer (`proc.observer`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork), 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#proc.observer`

### Problem being solved
Agents need to know what is running and on screen — which processes exist and which windows are open,
where they are, and which one is active — without taking screenshots or doing image processing. This is
the structured-observation counterpart to `fs.observer` and the substrate for later UIA/capture modules.

### Immediate practical use
Answers "what apps/windows are open right now, where, and what's focused?" — a human-readable report plus
machine-readable process/window lists a weaker local model or router can consume.

### Explicit scope (in)
- Process snapshot: pid, name, path (best-effort), start time (best-effort), working set, main window title/handle.
- Top-level window snapshot via Win32 `EnumWindows`: title, owning pid + process name, bounds (x/y/w/h),
  visible/minimized/maximized, and which window is foreground.
- Optional `name_filter` glob (narrows both processes and windows); `visible_only` toggle; `max_items` cap.
- Artifacts: `report.md` (human), `processes.json`, `windows.json`. Contract-valid envelope; direct/wrapped/executor.

### Non-goals (out — do NOT build)
- Screenshots or any pixel/image processing (Module 6 `capture.screen`).
- UI Automation control tree / element info (Modules 4–5).
- Control actions (focus/move/close/type) — observation only, no side effects.
- Change detection / streaming across time (later; this is a point-in-time snapshot).

### Dependencies
- Modules: Module 1 (`skill.bootstrap`) — reuse `lib/SkillContract.psm1` and `Invoke-Skill.ps1`.
- Tools/models: `pwsh>=7.4` with `Add-Type` (bundled Roslyn) for the Win32 P/Invoke. No installs.

### Skill contract requirements
- `skill_id` `proc.observer`, `version` `0.1.0`, `determinism` `deterministic` (deterministic read of
  current state; snapshot volatility is environmental), `parallel_safe` true, `batch`/`streaming` false.
- `result` = `{ host, generated_at_utc, name_filter, visible_only, process_count, window_count, foreground,
  windows[] }`; `confidence` null; artifact kinds `markdown` + `json` + `json`.

### Inputs and outputs
- **Inputs:** `visible_only` (bool, default true), `name_filter` (string glob, optional), `max_items` (int, default 2000).
- **Outputs:** result summary above; artifacts `report.md`, `processes.json`, `windows.json` (+ stderr.txt, result.json).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `report.md`, `processes.json`, `windows.json`, `stderr.txt`, `result.json`.

### Proposed implementation
- **Language:** PowerShell 7 (language policy — fast correct MVP; runs natively through the executor).
- `Get-Process` for processes (per-process try/catch on Path/StartTime); a small Win32 class via `Add-Type`
  (`EnumWindows`/`GetWindowText`/`GetWindowRect`/`IsIconic`/`IsZoomed`/`GetForegroundWindow`/
  `GetWindowThreadProcessId`) for windows. Enrich windows with process name via a pid→name map. Sort
  deterministically (processes by name,pid; windows by pid,hwnd). Reuse Module 1 envelope conventions.
- Window enumeration failure is caught → warning + empty windows + `status:partial` (processes still returned).

### External tools or models
- None beyond `pwsh` + its bundled C# compiler. Verified via a smoke test (16 windows, foreground, 314 procs, session 1).

### Installation steps
- None. Files added under `modules/03-proc-observer/`.

### Tests
- **Direct:** run with no args → schema-valid envelope, `process_count`/`window_count` > 0, three artifacts
  present with hashes, `processes.json.count` == `result.process_count`.
- **Name filter:** `-NameFilter 'pwsh*'` → non-empty; a no-match filter → `process_count` 0 but still a valid `ok` envelope.
- **Wrapped:** via `Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'` → manifest+envelope valid.
- **Through the executor:** submit a task package → `completed` + valid envelope + artifacts.

### MVP acceptance criteria
- [ ] `proc.observer` manifest passes `Test-SkillManifest`.
- [ ] Contract-valid envelope; processes + windows + foreground captured; three artifacts with hashes.
- [ ] `name_filter` narrows correctly; runs through the executor and via the wrapper.
- [ ] `TOOL_MODEL_REGISTRY.md` has a `proc.observer` entry.

### Manual verification procedure
- Submit an executor task; open `report.md` (foreground + visible windows + top processes); confirm a known
  running app (e.g. the executor's own pwsh window) appears with plausible bounds.

### Documentation requirements
- Module `README.md`, `skill.json`, `examples/` (invocation + a real captured result).

### Registry updates
- Add `proc.observer` to `TOOL_MODEL_REGISTRY.md`.

### State updates
- Update `CURRENT_STATE.md` and `MODULE_ROADMAP.md` (Module 3 → MVP complete; Module 4 next).

### Known follow-on work (future work orders — NOT this session)
- Change detection / streaming; per-monitor / DPI-aware coordinates; window→UIA bridge (Module 4).

### STOP conditions
- Scope would exceed the "Explicit scope" list.
- A dependency is missing/broken and installing it is non-trivial.
- The contract lacks something this module needs (stop; propose the change; do not freelance).
- MVP acceptance is met — **stop; do not start Module 4.**
