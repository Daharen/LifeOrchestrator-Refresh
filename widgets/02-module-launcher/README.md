# Module Launcher & Registry Browser (Widget 02)

The **discoverability surface** for the Life Orchestrator module suite. Where the Local Agent
Console (Widget 01) drives `agent.local` and lets the *local model* decide which tool to use, this
widget puts **you** in charge: it lists every installed Module from its `skill.json` manifest, shows
you what each one does and what inputs it takes, and lets you **run any single Module directly** —
no agent, no decision loop, no escalator.

> A **Widget** is the HID (human-interface) layer. It plugs into the Module architecture through the
> skill contract and **never reimplements** a Module. This launcher only *reads* each `skill.json`
> (to browse) and *drives* the Module 1 generic wrapper `Invoke-Skill.ps1` (to run) — spawn a child
> process, parse its `lifeorch.skill.invocation_report/0.1`, render it. Nothing else.

## Two halves

**Registry Browser** — on open (and on **Refresh**) it scans `modules/*/skill.json` and lists every
Module that ships a manifest, sorted by `skill_id`. Select one to see its purpose, its full input
list (name / type / required / default / description), its requirements (GPU, filesystem, network,
screen, models), and its flags (`determinism`, `parallel_safe`, `batch`, `streaming`). A module whose
manifest can't be parsed is still listed (flagged) rather than hidden. Type in the filter box to
narrow the list by id / name / folder.

**Launcher** — with a Module selected, the inputs box is pre-filled with a JSON template of that
module's **required** inputs. Edit it, set the working directory (defaults to the repo root), and
press **Run module**. The widget runs the Module **through the canonical Module 1 wrapper**
(`Invoke-Skill.ps1 -SkillDir <module> -InputsJson <your json>`), which validates the manifest, runs
the entrypoint in an isolated process, and validates the returned envelope. The result pane renders
the wrapper report (manifest valid? invoked? envelope valid?) plus the module's own result: status,
confidence, the result payload, artifacts produced, model provenance, warnings, and any error. The
raw pane shows the full `invocation_report` JSON. **Cancel** kills the child process tree.

## Launch

**Double-click `launch.bat`.** (It runs the WinForms UI under the per-user PowerShell 7 in STA
mode: `pwsh -NoProfile -STA -File Show-ModuleLauncher.ps1`.) No install, no admin, no server, no
browser — a native window built on the WinForms already present on this machine (native-by-default,
D-0038).

## Using it

1. Pick a Module from the list on the left (filter to narrow it).
2. Read its detail (purpose / inputs / requirements) in the panel below the list.
3. Edit the **Inputs (JSON)** box — the required fields are pre-filled as a template; add optional
   ones from the detail as needed.
4. Set **Working dir** if the module resolves relative paths (defaults to the repo root).
5. Press **Run module**. Watch the status strip; read the rendered result + raw report when it finishes.

A red caution line appears for modules that can modify files (`filesystem=write`/`read-write`) — the
launcher runs the module **for real**, not as a dry run. GPU-bound modules (`gen.image`, `gen.music`,
`image.interpret`, `speech.stt`, …) can take a minute or two to load their model on the first run.

## How it is built (thin, testable)

- **`ModuleLauncher.psm1`** — the driver core, **no WinForms**. Registry half:
  `Get-ModuleRegistry` (scan + parse every `skill.json`), `Format-ModuleListLine`,
  `Format-ModuleDetail`, `Get-ModuleInputTemplate`. Launcher half:
  `Start-ModuleProcess` / `Complete-ModuleRun` / `Invoke-ModuleRun` (spawn `Invoke-Skill.ps1` as a
  child, drain both pipes, parse the invocation report + nested envelope) + `Format-ModuleResult`.
  Because it is WinForms-free, the whole driver is tested on the cloud pre-ship gate against a fixture
  modules tree + a mock `Invoke-Skill.ps1`.
- **`Show-ModuleLauncher.ps1`** — the STA WinForms shell. It uses those exact core functions,
  starting the child off the UI thread and polling it from a `Timer` (so all control updates stay on
  the UI thread — no cross-thread marshaling). `-SelfTest` builds and disposes the form (used by the
  live gate).
- **`launch.bat`** — the double-click launcher. **`tests/`** — the dual-mode harness + a mock
  `Invoke-Skill.ps1`.

Per-run artifacts (the wrapper's stdout/stderr and each launched module's output) land under
`runtime/artifacts/<id>/` (gitignored). This widget is **not** a review-queue producer.

## Tests

- **Cloud gate:** `pwsh -File tests/Invoke-ModuleLauncherTests.ps1` — AST-parses every script; drives
  the real core over a generated fixture modules tree (valid + malformed + no-manifest folders) and
  against `tests/mock-invoke-skill.ps1` across a scenario matrix (ok / manifest-invalid / skill-error
  / envelope-invalid / noisy). WinForms + real-Module tests are skipped off-Windows.
- **Live (Windows):** `... -Live` — adds the WinForms form self-test, `launch.bat` shape, a **real**
  registry scan of the actual `modules/` tree, and a **real** `fs.observer` run driven end-to-end
  through the real `Invoke-Skill.ps1`, with no orphaned `llama-server`.

## Not in this MVP (follow-ons)

Run history / re-run; a form-based input editor generated from the manifest inputs (instead of raw
JSON); artifact preview (open a produced image/file); listing Widgets too; a favourites / recents
list; surfacing `agent.local`'s curated `tools.json` subset. See `WORK_ORDER.md`.
