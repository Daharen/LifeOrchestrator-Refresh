# Work Order: Module Launcher & Registry Browser (Widget 02)

**Layer:** Widget (HID / human-interface) · **Contract version referenced:** 0.2 ·
**Author:** Claude (Cowork) / 2026-07-27 · **Roadmap entry:** `MODULE_ROADMAP.md -> Build priority, Phase B #2`
· **Widgets doc:** `widgets/README.md` (item 2) · **Decisions:** D-0029 (Widget layer), D-0038 (native delivery
+ launch convention), D-0039 (Widget 01, the template), **D-00xx** (this widget, this session).

> A **Widget** is a human-interface app that plugs into the Module architecture through the skill contract —
> it **never reimplements** a Module. Widget 01 (Local Agent Console) is the local-model front door; this
> widget is its complement: the **human-directed** front door — browse every Module and run one by hand.

---

## Problem being solved

Phase A built 25+ Modules, each a conforming skill with a `skill.json` manifest and a
`lifeorch.skill.result/0.1` envelope. Widget 01 lets a person drive them *vicariously* through
`agent.local` (the local model decides which tool to use). But there is **no human surface to simply
discover what Modules exist and run one directly**: today you must read the repo, find a module's
`skill.json`, hand-write an `-InputsJson` blob, and invoke `Invoke-Skill.ps1` at a `pwsh` prompt. The
Module Launcher & Registry Browser is that surface: a window that lists every installed Module with
its purpose + inputs, and runs any one directly through the Module 1 wrapper.

## Immediate practical use

The user opens `launch.bat`, sees all 25+ Modules, clicks `gen.image`, reads that it needs a
`prompt`, edits the pre-filled `{"prompt":""}` template, presses **Run module**, and gets the image —
or clicks `fs.observer`, runs `{"path":"core-docs","depth":2}`, and reads the tree. It is the
discoverability + direct-invocation surface that makes the whole `modules/` suite usable by hand,
without the agent in the loop and without hand-typing `pwsh` commands.

## Explicit scope (in)

- A **native Windows desktop window** (WinForms via the dotnet-tool `pwsh 7.4.6`, STA) — native by
  default per D-0038.
- **Registry Browser:** scan `modules/*/skill.json`, list every Module with a manifest (sorted by
  `skill_id`; malformed manifests surfaced, not hidden), a filter box, and a detail pane (purpose,
  inputs with type/required/default/description, requirements, flags).
- **Launcher:** select a Module -> the inputs box pre-fills a JSON template of its **required** inputs
  -> **Run module** spawns the **Module 1 wrapper** `Invoke-Skill.ps1 -SkillDir <module> -InputsJson
  <json> -ArtifactRoot <dir>` as a child (off the UI thread) -> render the returned
  `lifeorch.skill.invocation_report/0.1` (manifest valid? invoked? envelope valid?) + the nested
  module result (status, confidence, result payload, artifacts, provenance, warnings, error) + a raw
  JSON pane. **Cancel** kills the child tree.
- A **`launch.bat`** double-click launcher (D-0038).
- A **driver core** (`ModuleLauncher.psm1`) holding all discovery/spawn/parse/format logic with **no
  WinForms dependency**, fully testable headlessly on the cloud gate against a fixture modules tree +
  a mock `Invoke-Skill.ps1`.
- Tests (dual-mode: cloud fixture/mock + live Windows) + a README.

## Non-goals (out — do NOT build)

- **No agent / no decision loop.** This widget does not drive `agent.local` or `route.tools`; it runs
  exactly the one Module you pick. (That is Widget 01's job.)
- **No form-generated input editor** in the MVP — inputs are a raw JSON box pre-filled from the
  manifest. A per-input typed form is a follow-on.
- **No editing manifests / no installing or scaffolding new Modules** from the UI.
- **No batch / multi-module runs**, no pipelines, no run history/re-run (single-shot MVP).
- **No artifact preview** (opening a produced image/file) in the MVP — the artifact paths are shown.
- **No reimplementation** of any Module or of `Invoke-Skill.ps1` — discovery reads `skill.json`;
  running spawns the wrapper and parses its report.
- **No web server / browser / port.**

## Delivery decision

Native (WinForms via the dotnet-tool pwsh, STA), per the project default **D-0038** — zero-install,
single-runtime-consistent with the spawn-and-parse architecture, trivial double-click `launch.bat`.
All non-UI logic lives in `ModuleLauncher.psm1` (WinForms-free) so the cloud gate runs the real driver
against a fixture + mock; only the thin Form layer is Windows-only.

## Dependencies

- **Modules:** the Module 1 generic wrapper `Invoke-Skill.ps1` (the run mechanism) + every Module's
  `skill.json` (the browse source). It drives no model itself; a launched Module may.
- **Tools/runtimes:** the dotnet-tool `pwsh 7.4.6` (`$PSHOME\pwsh.exe`), .NET WinForms — all present.
- **Contract features consumed:** `skill.json` manifest (§1), the `-InputsJson`/`-ArtifactRoot`
  generic args (§3.1), the `lifeorch.skill.invocation_report/0.1` wrapper report (§3.2), and the
  nested `lifeorch.skill.result/0.1` envelope (§2).

## Architecture (thin, DRY, testable)

**1. Driver core — `ModuleLauncher.psm1` (pure PowerShell, NO WinForms):**
- `Resolve-ModuleLauncherPaths` — repo root (widget `../..`), `modules/` dir, the `Invoke-Skill.ps1`
  path, and the pwsh exe (`$PSHOME\pwsh.exe` — dodges the `dotnet.exe` locator gotcha), each overridable.
- `Get-ModuleRegistry` — scan `<modules>/*/skill.json`, parse each, return sorted entries
  `{folder, skill_id, name, purpose, determinism, parallel_safe, batch, streaming, entrypoint,
  entrypoint_exists, inputs, required_inputs, requirements, timeout, manifest_ok, manifest_error,
  skill_dir}`; folders without a manifest are skipped, malformed manifests are kept + flagged.
- `Format-ModuleListLine` / `Format-ModuleDetail` / `Get-ModuleInputTemplate` — the browse renderers.
- `Start-ModuleProcess` / `Complete-ModuleRun` / `Invoke-ModuleRun` — spawn `Invoke-Skill.ps1` with
  `-SkillDir/-InputsJson/-ArtifactRoot/-PwshPath`, drain both pipes async, parse the tolerant JSON
  report, and return `{ok, report, skill_envelope, skill_status, manifest_valid, invoked,
  envelope_valid, error, ...}`.
- `Format-ModuleResult` — the render model for a run (wrapper flags + module status/result/artifacts/
  provenance/error). Plain text; fully testable.

**2. UI layer — `Show-ModuleLauncher.ps1` (STA WinForms):**
`New-ModuleLauncherForm` builds a left browser (filter + list + detail) and a right run area (inputs
JSON + working dir + Run/Cancel + a result/raw split), returns the form **without** `Application.Run`
so `-SelfTest` can construct + dispose it. Run wiring: on click, validate the inputs JSON, disable
Run / enable Cancel, `Start-ModuleProcess`, start the timer; on tick, when the child exits,
`Complete-ModuleRun` -> `Format-ModuleResult` -> render. Cancel kills the child tree.

## Inputs and outputs

- **Inputs (UI):** a selected Module + an inputs JSON object (required fields pre-filled) + a working
  directory (defaults to repo root).
- **Outputs:** an on-screen rendered result + raw report; each run's artifacts (the wrapper's
  stdout/stderr and the launched module's own outputs) under `runtime/artifacts/<id>/` in this widget
  folder (via `-ArtifactRoot`). The widget writes no model output and is not a review-queue producer.

## Tests

- **Cloud pre-ship gate (off-machine, cloud pwsh 7.4.6):** AST-parse every script; build a fixture
  `modules/` tree (a valid doc.io + fs.observer, a malformed manifest, a no-manifest folder) and
  assert `Get-ModuleRegistry` discovers/sorts/flags correctly + `Get-ModuleInputTemplate` /
  `Format-ModuleDetail` render; drive the real core against `tests/mock-invoke-skill.ps1` across
  ok / manifest-invalid / skill-error / envelope-invalid / noisy scenarios and assert
  `Format-ModuleResult` renders each. WinForms + real-Module tests skipped off-Windows.
- **Live (Windows, via the executor):** the same harness `-Live` — WinForms form self-test,
  `launch.bat` shape, a **real** `Get-ModuleRegistry` scan of the actual `modules/` tree (>= 20
  modules, doc.io + fs.observer present + manifest_ok), and a **real** `fs.observer` run driven
  end-to-end through the real `Invoke-Skill.ps1`, parsed + rendered, 0 orphaned `llama-server`.

## MVP acceptance criteria

- [ ] `launch.bat` opens a native window with a filterable module list, a detail pane, an inputs box,
      Run/Cancel, and a result/raw split.
- [ ] The list is populated from `modules/*/skill.json` on open + Refresh; selecting a module shows its
      detail and pre-fills the inputs template.
- [ ] Run spawns `Invoke-Skill.ps1` off the UI thread; the window stays responsive; on completion the
      result renders (wrapper flags + module status/result/artifacts) and the raw report shows.
- [ ] Errors (bad manifest, invalid inputs JSON, module error, no envelope) are surfaced structurally.
- [ ] Cancel kills the child process tree.
- [ ] The core has no WinForms dependency and passes the cloud gate against the fixture + mock.
- [ ] Live: a real `fs.observer` run is driven, parsed, and rendered; 0 orphaned model servers.
- [ ] All shipped files sha256 byte-exact + AST-parse OK on the target.

## Manual verification procedure

1. Double-click `widgets\02-module-launcher\launch.bat`.
2. Confirm the list fills with every module (filter to find `fs.observer`).
3. Select `fs.observer`, run `{"path":"core-docs","depth":1}`, read the tree result.
4. Select `doc.io`, run `{"op":"read","path":"core-docs\\START_HERE.md"}`, read the content.
5. Select `gen.image`, run `{"prompt":"a photograph of a dog"}`, confirm an image artifact appears.
6. Start a slow (GPU) run and press **Cancel**; confirm the window returns to idle and no
   `pwsh`/`llama-server`/`python` is left running.

## Documentation requirements

- Widget `README.md` (what it is, how to launch, the two halves, how it maps to `Invoke-Skill.ps1`,
  the manual steps) + this work order.

## Registry / doc updates (end of session)

- `CURRENT_STATE.md` (Widget track: this widget), `MODULE_ROADMAP.md` (Phase B #2 -> MVP complete),
  `DECISION_LOG.md` (this widget), `widgets/README.md` (mark #2 built), `HANDOFF.md` (next unit ->
  Widget #3). Then mirror core-docs disk -> the Project.

## Known follow-on work (NOT this session)

- A per-input typed form generated from the manifest inputs (instead of raw JSON).
- Run history + re-run / edit-and-re-run; a favourites / recents list.
- Artifact preview (open a produced image/text file from the result pane).
- Also list Widgets (needs a `widget.json` manifest convention).
- Surface `agent.local`'s curated `tools.json` subset (which modules the agent can pick).
- Light syntax coloring / export a run.

## STOP conditions

- Scope would exceed the "Explicit scope" list (e.g. an agent loop, a form editor, batch runs) ->
  stop, write it into `widgets/README.md` / a new work order.
- `Invoke-Skill.ps1` or a Module needs a change to be drivable -> stop, propose it, do not freelance.
- MVP acceptance is met -> **stop; do not start Widget #3.**
