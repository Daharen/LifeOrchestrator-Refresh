# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP module build-out.
- **Active module:** _none in progress._ **Module 1 — Skill Contract & Registry Bootstrap (`skill.bootstrap`)
  is Ready and next.** (Module 0 complete.)
- **Repo / working dir:** **`C:\Users\just_\Project-Proteus-Refresh\`** — the clean standalone home for
  this track (git-initialized). Layout: `core-docs/` (these docs) and `modules/<NN>-<name>/` (one per
  module). The old `Project-Proteus-src\proteus_repo` holds the *original* executor and the defunct legacy
  Proteus; treat it as legacy and do not build there.
- **Executor status:** MVP complete. **Running instance:** the original at
  `proteus_repo/tools/trusted-bootstrap-executor/` (commit `c4e90c4`), kept running for continuity.
  **Working copy for this repo:** `Project-Proteus-Refresh/modules/00-bootstrap-executor/` — run future
  instances from here. Launch/submit/stop via `pwsh` (see registry).

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.

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

## Active model servers
- None known.

## Known working invocation paths
- Executor: `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` /
  `...\Submit-BootstrapTask.ps1` / `...\Stop-BootstrapExecutor.ps1` (from the module dir).
- Direct pwsh (any script): `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).

## Known failures / gotchas
- The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`, so `(Get-Process -Id $PID).Path`
  is **not** a reliable pwsh locator. Pass explicit pwsh paths. Executor/harness already accept `-PwshPath`.
- The **latest** `PowerShell` .NET global-tool package is malformed (missing tool manifest); pin a
  version (7.4.6 used).
- Executor `Start-Process` argument quoting for paths **containing spaces** is untested — the refresh repo
  uses a hyphenated, space-free path deliberately.

## Unresolved questions
- Exact GPU/CPU/RAM; which local models (LLM/vision/speech/embedding) are installed or wanted.
- Install pwsh system-wide (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- Whether to also mirror `core-docs/` into a Claude Project for hot-context loading (recommended).

## Next expected action
Author the **Module 1 work order** (`modules/01-skill-bootstrap/WORK_ORDER.md`) from the template and
implement its MVP (reference skill + invocation wrapper + registry entry), tested through the executor.

- **Last updated:** 2026-07-24 (UTC) · **Last updating agent:** Claude (control-plane bootstrap session).
