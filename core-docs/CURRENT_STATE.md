# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP module build-out.
- **Active module:** _none in progress._ **Modules 0–3 complete** (0 executor · 1 `skill.bootstrap` · 2
  `fs.observer` · 3 `proc.observer`). **Module 4 — UI Automation Inspector (`uia.inspector`) is next**
  (author its work order next session).
- **Repo / working dir:** **`C:\Users\just_\LifeOrchestrator-Refresh\`** — the clean standalone home for
  **Life Orchestrator** (near-term local-skills track; git-initialized). Layout: `core-docs/` (these docs)
  and `modules/<NN>-<name>/` (one per module). **Reference sources (separate, not built here):** the earlier
  assistant codebase `LifeOrchestrator\repo` (fold in later) and the separate **Project Proteus** game
  (`Project-Proteus-src`).
- **Executor status:** MVP complete. **Running instance (canonical):** the Life Orchestrator executor at
  `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (instance `0a1f8e69…`, pwsh 7.4.6, host
  `DESKTOP-PF5FFMF`) — started this session; the only executor we operate. The original at
  `proteus_repo/tools/trusted-bootstrap-executor/` (was `98b7f774…`) has been **stopped**, and the game repo
  `proteus_repo` was reset to `51fbd0d` (its last game commit — working tree clean, executor untracked).
  **Pending:** the physical `proteus_repo/tools/` leftover couldn't be deleted this session (this bridge session
  holds it open); remove it via `ops/finish-game-cleanup.bat` after closing the desktop app, or from a session
  that does not mount that folder. Launch/submit/stop via `pwsh` or the `ops/` batch files.

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.
- **Module 1** — Skill Contract & Registry Bootstrap (`skill.bootstrap`). Reference skill `ref.echo`,
  contract validators (`lib/SkillContract.psm1`), and a generic wrapper (`Invoke-Skill.ps1`). Runs directly
  and through the executor; emits schema-valid `lifeorch.skill.result/0.1`. Module tests 11/11 (2026-07-24).
- **Module 2** — Filesystem Observer (`fs.observer`). Deterministic depth-bounded tree + name/glob search;
  `tree.md` + `index.json` artifacts; contract-valid envelope; runs direct/wrapped/executor. Tests 16/16 (2026-07-24).
- **Module 3** — Process & Window Observer (`proc.observer`). Snapshot of processes + top-level windows +
  foreground (Win32); `report.md` + `processes.json` + `windows.json`. Tests 16/16 (2026-07-24).

## Installed dependencies (verified this machine)
- **PowerShell 7.4.6** — installed as a .NET global tool at
  `C:\Users\just_\.dotnet\tools\pwsh.exe`. (Was **not** present before; installed 2026-07-24.)
- **.NET SDK 9.0.100** — `C:\Program Files\dotnet\dotnet.exe`.
- **git** — on PATH. **winget** — present (user WindowsApps). **choco** — not installed.
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
- User ops (click-to-run): `ops/*.bat` — start/stop/restart/status the executor and run tests; each writes
  output to `ops/out/` for the agent to read.

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).
- Module 1: `modules/01-skill-bootstrap/tests/Invoke-SkillBootstrapTests.ps1` — 11/11 pass
  (manifest, direct, wrapper, and error-path envelope validation; run 2026-07-24 via the executor).
- Module 2: `modules/02-fs-observer/tests/Invoke-FsObserverTests.ps1` — 16/16 pass
  (manifest, tree, artifacts, search, error path, wrapper; run 2026-07-24 via the executor).
- Module 3: `modules/03-proc-observer/tests/Invoke-ProcObserverTests.ps1` — 16/16 pass
  (manifest, processes+windows+foreground, artifacts, name filter, wrapper; run 2026-07-24 via the executor).

## Known failures / gotchas
- The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`, so `(Get-Process -Id $PID).Path`
  is **not** a reliable pwsh locator. Pass explicit pwsh paths. Executor/harness already accept `-PwshPath`.
- The **latest** `PowerShell` .NET global-tool package is malformed (missing tool manifest); pin a
  version (7.4.6 used).
- Executor `Start-Process` argument quoting for paths **containing spaces** is untested — the refresh repo
  uses a hyphenated, space-free path deliberately.
- Skill scripts must write **only** the JSON envelope to stdout (diagnostics to stderr); the executor
  captures stdout verbatim into `stdout.txt`, which is parsed as the envelope.

## Unresolved questions
- Exact GPU/CPU/RAM; which local models (LLM/vision/speech/embedding) are installed or wanted.
- Install pwsh system-wide (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- Contract finalization: fold Module 1's provisional conventions (artifact-root resolution, `-InputsJson`
  generic arg passing, `lifeorch.skill.invocation_report/0.1`) into `SKILL_CONTRACT.md` once a second skill
  (Module 2) confirms them, then bump the contract version. (See DECISION_LOG D-0009.)

## Next expected action
Author the **Module 4 work order** (`modules/04-uia-inspector/WORK_ORDER.md`) from the template and implement
its MVP (UI Automation inspector: read accessible controls for a target window/app, return stable element
info — read-only, no actions), tested through the executor. Reuse `Test-SkillManifest` /
`Test-SkillResultEnvelope` and `Invoke-Skill.ps1`.

- **Last updated:** 2026-07-24 (UTC) · **Last updating agent:** Claude (Cowork — Module 3 build session).
