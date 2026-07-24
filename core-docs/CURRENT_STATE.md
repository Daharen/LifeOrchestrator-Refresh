# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP module build-out.
- **Active module:** _none in progress._ **Modules 0–5 complete** (0 executor · 1 `skill.bootstrap` · 2
  `fs.observer` · 3 `proc.observer` · 4 `uia.inspector` · 5 `uia.actor`), plus **Module 00.1 — Executor
  Watchdog & Recovery (`exec.watchdog`)** (infrastructure, MVP complete this session). **Module 6 — Screenshot
  & Region Capture (`capture.screen`) is next** (author its work order next session).
- **Repo / working dir:** **`C:\Users\just_\LifeOrchestrator-Refresh\`** — the clean standalone home for
  **Life Orchestrator** (near-term local-skills track; git-initialized). Layout: `core-docs/` (these docs)
  and `modules/<NN>-<name>/` (one per module). **Reference sources (separate, not built here):** the earlier
  assistant codebase `LifeOrchestrator\repo` (fold in later) and the separate **Project Proteus** game
  (`Project-Proteus-src`).
- **Executor status:** MVP complete, **running.** **Canonical instance:** the Life Orchestrator executor at
  `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (pwsh 7.4.6, host `DESKTOP-PF5FFMF`). It crashed
  once mid-session (2026-07-24T06:26:36Z, instance `0a1f8e69…`, transient file-lock — see Known failures), was
  **restarted** and is now instance `857d7251…` (up 13:52Z); restart recovery correctly marked the orphaned
  `m5-example-001` as `abandoned_after_restart`. The original at `proteus_repo/tools/trusted-bootstrap-executor/`
  was stopped earlier; the physical `proteus_repo/tools/` leftover removal is still pending
  (`ops/finish-game-cleanup.bat`). **Now covered by the watchdog (Module 00.1):** launch `ops/start-watchdog.bat`
  for unattended resilience — it auto-restarts the executor on crash/hang and stands down on a graceful stop.
  **The live executor (instance `857d7251…`) is running the pre-marker code; restart it once
  (`ops/restart-executor.bat`) so it begins emitting `heartbeat.json`/`last-exit.json` that the watchdog reads.**

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.
- **Module 1** — Skill Contract & Registry Bootstrap (`skill.bootstrap`). Reference skill `ref.echo`,
  contract validators (`lib/SkillContract.psm1`), and a generic wrapper (`Invoke-Skill.ps1`). Runs directly
  and through the executor; emits schema-valid `lifeorch.skill.result/0.1`. Module tests 11/11 (2026-07-24).
- **Module 2** — Filesystem Observer (`fs.observer`). Deterministic depth-bounded tree + name/glob search;
  `tree.md` + `index.json` artifacts; contract-valid envelope; runs direct/wrapped/executor. Tests 16/16 (2026-07-24).
- **Module 3** — Process & Window Observer (`proc.observer`). Snapshot of processes + top-level windows +
  foreground (Win32); `report.md` + `processes.json` + `windows.json`. Tests 16/16 (2026-07-24).
- **Module 4** — UI Automation Inspector (`uia.inspector`). Read-only UIA control-tree walk of a target
  window/desktop (control type, name, automation id, bounds, patterns, state); `tree.md` + `elements.json`. Tests 16/16 (2026-07-24).
- **Module 5** — UI Automation Actor (`uia.actor`). **Acting** half of UIA: invoke/toggle/select/expand/
  collapse/setvalue/focus on an element located by automation id / name / control type / inspector child-path.
  UIA control patterns only (no synthetic input); `-DryRun`/`-WhatIf` preview; `parallel_safe:false` (first
  side-effecting skill). `action.md` + `action.json` artifacts. **Tests 26/26 via executor (2026-07-24)** —
  incl. real invoke/toggle/setvalue self-verified against a self-contained WinForms probe window. Committed `1691d16`.
- **Module 00.1** — Executor Watchdog & Recovery (`exec.watchdog`). **Cooperative** supervisor: autonomously
  restarts the executor on crash/hang (no approval), stands down on an authorized graceful stop; on-demand
  `Recover-Executor.ps1 -Force`. Not perpetual, no boot persistence, visible + self-killable (D-0013, honors
  D-0001). Adds `heartbeat.json`/`last-exit.json` to Module 0 (additive; 12/12 unaffected). Tests 22/22 (2026-07-24).

## Installed dependencies (verified this machine)
- **PowerShell 7.4.6** — installed as a .NET global tool at
  `C:\Users\just_\.dotnet\tools\pwsh.exe`. (Was **not** present before; installed 2026-07-24.)
- **.NET SDK 9.0.100** — `C:\Program Files\dotnet\dotnet.exe`.
- **git** — on PATH. **winget** — present (user WindowsApps). **choco** — not installed.
- **WinForms + STA runspace** work in the dotnet-tool pwsh (`System.Windows.Forms` loads; an STA runspace
  can host a Form + `Application.Run`) — verified 2026-07-24 (used by the Module 5 probe test).
- Not admin. No system-wide `pwsh` (only the user `~\.dotnet\tools` entry — resolves in new shells).

## Installed local models
- **None registered yet.** (To be discovered/registered — see Unresolved questions and Module 7.)

## Available hardware (partly inferred — needs a detection pass)
- Windows 10 x64 workstation; fixed drives **C, D, E** and **F** (F: used for large-data storage).
- **NVIDIA GPU present** (inferred: NVIDIA Ansel + GPU-class apps installed); exact model, VRAM, CPU,
  and RAM **not yet measured**. A hardware-detection step should populate these.
- Host confirmed this session: `DESKTOP-PF5FFMF`, user `just_`.

## Active model servers
- None known.

## Known working invocation paths
- Executor: `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` /
  `...\Submit-BootstrapTask.ps1` / `...\Stop-BootstrapExecutor.ps1` (from the module dir).
- Direct pwsh (any script): `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- Skill (direct): `pwsh -NoProfile -File modules\01-skill-bootstrap\skills\ref.echo\Invoke-RefEcho.ps1 -Message <s> -Repeat <n>`.
- Skill (wrapped): `pwsh -NoProfile -File modules\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir <skill dir> [-InputsJson '<json>']`.
- Skill (through executor): submit a task package whose `task.ps1` calls either entrypoint; read the
  envelope from `runtime/completed/<task_id>/stdout.txt`.
- uia.actor (direct): `pwsh -NoProfile -File modules\05-uia-actor\Invoke-UiaActor.ps1 -Title '<glob>' -Action <invoke|toggle|select|expand|collapse|setvalue|focus> [-AutomationId|-Name|-ControlType|-Path <loc>] [-Value <s>] [-DryRun]`.
- User ops (click-to-run): `ops/*.bat` — start/stop/restart/status the executor and run tests; each writes
  output to `ops/out/` for the agent to read.
- Watchdog: `ops/start-watchdog.bat` (supervise), `ops/stop-watchdog.bat`, `ops/recover-executor.bat [-Force]`;
  direct `pwsh -NoProfile -File modules\00.1-exec-watchdog\Watch-Executor.ps1` / `...\Recover-Executor.ps1`.

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).
- Module 1: `modules/01-skill-bootstrap/tests/Invoke-SkillBootstrapTests.ps1` — 11/11 pass (2026-07-24).
- Module 2: `modules/02-fs-observer/tests/Invoke-FsObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 3: `modules/03-proc-observer/tests/Invoke-ProcObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 4: `modules/04-uia-inspector/tests/Invoke-UiaInspectorTests.ps1` — 16/16 pass (2026-07-24).
- Module 5: `modules/05-uia-actor/tests/Invoke-UiaActorTests.ps1` — **26/26 pass** (manifest, dry-run,
  five error paths, wrapper, and live setvalue/toggle/invoke + dry-run-invoke against a WinForms probe;
  run 2026-07-24 via the executor as `m5-test-001`, exit 0, 13s).
- Module 00.1: `modules/00.1-exec-watchdog/tests/Invoke-WatchdogTests.ps1` — **22/22 pass** (pure decision
  logic; `Test-ExecutorAlive`; `Get-ExecutorState`; Module 0 heartbeat/last-exit markers; and integration on
  temp runtimes: watchdog auto-restarts a crash and stands down on an authorized stop; `wd-test-002` 2026-07-24).
  Module 0 regression re-run **12/12** with the additive markers (`wd-precheck-001`).

## Known failures / gotchas
- **Executor fatal-crashed on a transient file lock (2026-07-24T06:26:36Z).** While task `m5-example-001`
  was running (a task that launched a GUI subprocess and where the agent was also reading `runtime/` over
  the device-bridge mount), the executor died with `The process cannot access the file because it is being
  used by another process` and `Error during cancellation: ...`, then `Executor stopped`. Likely a
  directory-move (running→completed/failed) or state-write colliding with an open handle (possibly the
  Linux-mount reader, or the task's own child process). **Fixed two ways (2026-07-24):** (1) externally
  auto-recovered by the watchdog (Module 00.1); (2) **in-process self-heal** — `Invoke-WithFileRetry` now
  wraps the atomic state-writes (`Write-JsonAtomic`) and the queue finalization move (`Move-FinalizedTask`),
  and a per-iteration loop guard catches `IOException`/`UnauthorizedAccessException` and continues, so this
  crash class no longer kills the executor. Module 0 tests remain **12/12** with the self-heal. Operational
  note still worth keeping: avoid holding handles on `runtime/` from the mount while tasks run; keep polls brief.
- The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`, so `(Get-Process -Id $PID).Path`
  is **not** a reliable pwsh locator. Pass explicit pwsh paths. Executor/harness already accept `-PwshPath`.
- **`@($list)` on a raw `System.Collections.Generic.List[object]` throws "Argument types do not match"**
  (pwsh 7.4.6) when it holds `[pscustomobject]`s — use `$list.ToArray()`. Module 5 uses `.ToArray()` throughout.
- The **latest** `PowerShell` .NET global-tool package is malformed (missing tool manifest); pin a
  version (7.4.6 used).
- Launching a live GUI probe window from *inside* a background executor task can hang that task's UIA calls
  if the window's UI thread stops pumping (observed once with `m5-example-001`). The Module 5 **test** harness
  drives a probe reliably; prefer side-effect-free dry-runs when capturing examples to avoid GUI-in-task risk.
- Skill scripts must write **only** the JSON envelope to stdout (diagnostics to stderr); the executor
  captures stdout verbatim into `stdout.txt`, which is parsed as the envelope.

## Unresolved questions
- Exact GPU/CPU/RAM; which local models (LLM/vision/speech/embedding) are installed or wanted.
- Root cause of the executor file-lock crash (see Known failures) — reproduce and harden Module 0.
- Install pwsh system-wide (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- Contract finalization: fold the provisional Module 1 conventions (artifact-root resolution, `-InputsJson`
  generic arg passing, `lifeorch.skill.invocation_report/0.1`) into `SKILL_CONTRACT.md` and bump the version —
  now exercised by Modules 2–5. (See DECISION_LOG D-0009.)

## Next expected action
1. **Restart the live executor once** (`ops/restart-executor.bat`) so it emits the new heartbeat/last-exit
   markers, then optionally launch `ops/start-watchdog.bat` for unattended resilience. (Optional now; required
   before the watchdog can supervise the live instance.)
2. Author the **Module 6 work order** (`modules/06-capture-screen/WORK_ORDER.md`) from the template and implement
   its MVP (screenshot / region capture: monitor / window / app / rectangle → image artifact + contract-valid
   envelope), tested through the executor. Reuse `Test-SkillManifest` / `Test-SkillResultEnvelope` and `Invoke-Skill.ps1`.
3. ~~Module 0 in-process self-heal~~ — **done this session** (retry-on-IOException + per-loop guard; 12/12).

- **Last updated:** 2026-07-24 (UTC) · **Last updating agent:** Claude (Cowork — Module 00.1 watchdog build session).
