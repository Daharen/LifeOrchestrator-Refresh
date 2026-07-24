# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP module build-out.
- **Active module:** _none in progress._ **Module 1 — Skill Contract & Registry Bootstrap (`skill.bootstrap`)
  is MVP complete.** **Module 2 — Filesystem Observer (`fs.observer`) is next** (author its work order next
  session). (Modules 0 and 1 complete.)
- **Repo / working dir:** **`C:\Users\just_\Project-Proteus-Refresh\`** — the clean standalone home for
  this track (git-initialized). Layout: `core-docs/` (these docs) and `modules/<NN>-<name>/` (one per
  module). The old `Project-Proteus-src\proteus_repo` holds the *original* executor and the defunct legacy
  Proteus; treat it as legacy and do not build there.
- **Executor status:** MVP complete. **Running instance:** the original at
  `proteus_repo/tools/trusted-bootstrap-executor/` (commit `c4e90c4`), kept running for continuity — used
  this session to run Module 1's tests (instance `98b7f774…`, pwsh 7.4.6, host `DESKTOP-PF5FFMF`).
  **Working copy for this repo:** `Project-Proteus-Refresh/modules/00-bootstrap-executor/` — run future
  instances from here. Launch/submit/stop via `pwsh` (see registry).

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.
- **Module 1** — Skill Contract & Registry Bootstrap (`skill.bootstrap`). Reference skill `ref.echo`,
  contract validators (`lib/SkillContract.psm1`), and a generic wrapper (`Invoke-Skill.ps1`). Runs directly
  and through the executor; emits schema-valid `proteus.skill.result/0.1`. Module tests 11/11 (2026-07-24).

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

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).
- Module 1: `modules/01-skill-bootstrap/tests/Invoke-SkillBootstrapTests.ps1` — 11/11 pass
  (manifest, direct, wrapper, and error-path envelope validation; run 2026-07-24 via the executor).

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
  generic arg passing, `proteus.skill.invocation_report/0.1`) into `SKILL_CONTRACT.md` once a second skill
  (Module 2) confirms them, then bump the contract version. (See DECISION_LOG D-0009.)

## Next expected action
Author the **Module 2 work order** (`modules/02-fs-observer/WORK_ORDER.md`) from the template and implement
its MVP (deterministic tree + search over a target dir, contract-valid envelope, markdown + JSON artifacts),
tested through the executor. Reuse `Test-SkillManifest` / `Test-SkillResultEnvelope` and `Invoke-Skill.ps1`.

- **Last updated:** 2026-07-24 (UTC) · **Last updating agent:** Claude (Cowork — Module 1 build session).
