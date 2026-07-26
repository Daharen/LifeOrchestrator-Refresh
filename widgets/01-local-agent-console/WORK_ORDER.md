# Work Order: Local Agent Console (Widget 01)

**Layer:** Widget (HID / human-interface) · **Contract version referenced:** 0.2 ·
**Author:** Claude (Cowork) / 2026-07-26 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority, Phase B #1`
· **Widgets doc:** `widgets/README.md` (item 1) · **Decisions:** D-0029 (Widget layer), **D-0038** (native delivery
+ launch convention, this session), **D-0039** (this widget, this session).

> A **Widget** is a human-interface app that plugs into the Module architecture through the skill contract —
> it **never reimplements** a Module. This is the Phase-B keystone: the surface that makes the already-built
> Phase-A cost-offload core (escalator #19 / doc.io #20 / **agent.local #21**) usable by a *person*.

---

## Problem being solved

Phase A built a local orchestrator, `agent.local` (#21): give it a natural-language goal and it plans + invokes
Modules locally (deciding through the escalator #19, generating args + the final answer through the gateway #7,
running tools from a closed registry). But the **only way to drive it today is a raw `pwsh` invocation** — a
human has to hand-write an `-InputsJson` blob and then read a dense `lifeorch.skill.result/0.1` envelope by eye.
There is no human surface. The Local Agent Console is that surface: type a goal, press Run, watch the local
agent work, and read its result + step-by-step transcript in a real window.

## Immediate practical use

This week, the user (a human, not an AI) opens `launch.bat`, types "list the .md files under core-docs" or
"create notes/today.txt containing my plan", presses Run, and sees the agent choose a tool through the escalator,
generate the args, invoke the tool, and report back — the whole Phase-A cost-offload loop, driven vicariously
through the local model the way the frontier agent drives its own tool loop. It is the milestone that makes the
system usable locally without the frontier in the loop.

## Explicit scope (in)

- A **native Windows desktop window** (WinForms via the dotnet-tool `pwsh 7.4.6`, STA) — see the delivery
  decision below.
- **One input:** a goal (multiline text) + a small options row: working directory, max steps, a **Dry run
  (plan only)** checkbox. Advanced (optional, collapsed/defaulted): decision tiers, gen tier.
- **Run** submits the goal to **`agent.local` (#21)** as a child process (`-InputsJson` + `-ArtifactRoot`),
  off the UI thread, so the window stays responsive during the (minutes-long, GPU-bound) run.
- **Render** the returned `lifeorch.skill.result/0.1` envelope: overall status, final answer,
  `needs_frontier`, and the **child transcript** — per step: the decision (chosen tool, confidence, which tier
  accepted it), the generated args, the tool's status, and the bounded observation — plus a cost summary
  (gateway calls / tokens / runtime). A raw-JSON view for debugging.
- **Cancel/Stop** a running goal (kill the child process tree).
- A **`launch.bat`** so the user starts it with a double-click (the D-0038 convention).
- A **driver core** (`AgentConsole.psm1`) holding all spawn/parse/format logic with **no WinForms dependency**,
  so it is fully testable headlessly on the cloud pre-ship gate against a mock `agent.local`.
- Tests (dual-mode: cloud mock + live Windows) + a README.

## Non-goals (out — do NOT build)

- **Not an IDE / not a full agent workbench.** One goal in → one run → one rendered result. No project
  explorer, no code editor, no file tree.
- **No other skills.** It drives `agent.local` only. (The Module Launcher / Registry Browser is Widget #2;
  the Review Dashboard is #3; Voice Console #4; Generator Studio #5; etc. — each its own later work order.)
- **No multi-turn conversation / history / memory** across runs (single-shot MVP; a transcript log is a
  follow-on).
- **No streaming** token-by-token render (agent.local is not a streaming skill; render on completion).
- **No editing the agent's tool registry** from the UI, no new tools, no arbitrary-shell surface — the agent's
  capability set stays exactly `agent.local`'s closed `tools.json` (the registry-is-the-sandbox property, D-0032).
- **No reimplementation** of agent.local / the escalator / the gateway — spawn-and-parse only.
- **No web server / browser / port** (that is the non-default delivery; see the decision).

## Delivery decision (resolves D-0029's open "native vs web" item — recorded as D-0038)

**Project-wide default = native (WinForms via the dotnet-tool pwsh), zero-install. A locally-served web UI is a
per-widget override, permitted when a widget genuinely needs rich media or remote access.** For this console,
native, because on this box:

- **Zero install, probe-verified.** `m27-probe-001`: WinForms + an STA runspace hosting a `Form` with a
  `RichTextBox`/`TextBox`/`SplitContainer` load and construct in the existing `pwsh 7.4.6` (`winforms=ok`,
  `sta_form=form_ok apt=STA`). No admin, no dependency, no browser, no server, no port — matching the doctrine
  "offload with what's already there".
- **Single-runtime consistency.** The whole system is pwsh + child-process + parse-envelope; a native console
  spawns `agent.local` the exact way the executor and the orchestrator skills already do. Thinnest widget.
- **The launch file is trivial** (`pwsh -NoProfile -STA -File Show-AgentConsole.ps1`), directly satisfying the
  D-0038 launch-file convention; a web widget's launcher must start a server, manage a port, and open a browser.
- **Testability.** All non-UI logic lives in `AgentConsole.psm1` (WinForms-free), so the cloud gate runs the
  real driver against a mock agent.local; only the thin Form layer is Windows-only.

Web is deferred, not rejected: the Generator Studio (previews) and dashboards may adopt it per their own work
orders. The default stays native.

## Dependencies

- **Modules:** `agent.local` (#21) — the sole skill this widget drives (which itself composes #19/#7/#20/#2).
- **Tools/runtimes:** the dotnet-tool `pwsh 7.4.6` (`$PSHOME\pwsh.exe`), .NET WinForms (`System.Windows.Forms`,
  `System.Drawing`) — all present, no install.
- **Contract features consumed:** the `lifeorch.skill.result/0.1` envelope (§2) + agent.local's documented
  `result` shape (its `skill.json` outputs) + the generic `-InputsJson` / `-ArtifactRoot` arguments (§3, §3.1).

## Architecture (thin, DRY, testable)

Two layers, so the UI is a shell over a headless-testable core:

**1. Driver core — `AgentConsole.psm1` (pure PowerShell, NO WinForms):**
- `Resolve-AgentConsolePaths` — resolve the repo root (widget's `../..`), the `agent.local` entrypoint, and the
  pwsh exe (`Join-Path $PSHOME 'pwsh.exe'` — the self-referential path that dodges the `dotnet.exe`-shim locator
  gotcha), each overridable.
- `Start-AgentLocalProcess` — build the child argument list and `Start-Process -PassThru -WindowStyle Hidden`
  with stdout/stderr redirected to temp files under the invocation dir; return `{process, stdout_path,
  stderr_path, args, invocation_dir}`. Writes `child_pid` into an optional caller `-Sync` hashtable (enables the
  UI's Cancel).
- `Complete-AgentLocalRun` — given the finished process + paths, read stdout, extract + parse the single JSON
  envelope (tolerant of trailing/leading noise), return a structured
  `{ok, status, envelope, result, exit_code, stderr_tail, error, raw_stdout, elapsed_ms}`.
- `Invoke-AgentLocalRun` — synchronous convenience = `Start-AgentLocalProcess` → `WaitForExit` →
  `Complete-AgentLocalRun` (used by the tests headlessly and available for scripting).
- `Format-AgentTranscript` — the render model: parsed result → a readable transcript string (header: goal /
  status / final answer / needs_frontier / steps used / dry-run / confidence / duration; per-step: decision,
  args, tool status, observation; a cost line; error surfacing). Plain text (RichTextBox-ready); fully testable.

The UI uses `Start-AgentLocalProcess` (async) + a UI `Timer` that polls `process.HasExited` **on the UI thread**
(so every control update is thread-safe with no cross-thread marshaling) + `Complete-AgentLocalRun` +
`Format-AgentTranscript` — the same core functions the tests exercise synchronously via `Invoke-AgentLocalRun`.

**2. UI layer — `Show-AgentConsole.ps1` (STA WinForms):**
- `New-AgentConsoleForm` — build and return the Form (goal box, options row, Run/Cancel buttons, a
  `SplitContainer` with the transcript `RichTextBox` on top and a raw-JSON/log `RichTextBox` below, a status
  strip: state + elapsed + cost). Returns the form **without** calling `Application.Run`, so a headless
  self-test can construct + dispose it to prove the UI code parses and builds.
- Run wiring: on click, disable Run / enable Cancel, `Start-AgentLocalProcess`, start the timer; on tick update
  elapsed and, when the child exits, `Complete-AgentLocalRun` → render → re-enable Run. Cancel kills the child
  tree (`taskkill /T /F /PID`). `-SelfTest` builds+disposes the form and exits 0 (used by the live gate);
  `Application.Run` otherwise.

## Inputs and outputs

- **Inputs (UI):** goal (string, required), working_dir (string, optional — defaults to the repo root),
  max_steps (int, default 4), dry_run (bool, default **true** for a safe first-touch — the user unchecks it to
  let the agent actually act), decision_tiers/gen_tier (optional advanced).
- **Outputs:** an on-screen rendered transcript + raw envelope; each run's artifacts (agent.local's
  `child_review.jsonl`, per-step dirs, `result.json`) under `runtime/artifacts/<invocation_id>/` in this widget
  folder (via `-ArtifactRoot`), so runs are self-contained and inspectable. The widget itself writes no model
  output and is not a review-queue producer.

## Artifact / folder structure

```
widgets/01-local-agent-console/
  WORK_ORDER.md
  README.md
  AgentConsole.psm1            # driver core (no WinForms)
  Show-AgentConsole.ps1        # STA WinForms UI entrypoint (+ -SelfTest)
  launch.bat                   # double-click launcher (D-0038 convention)
  .gitignore                   # ignores runtime/
  tests/
    Invoke-AgentConsoleTests.ps1   # dual-mode: cloud mock + live Windows
    mock-agent-local.ps1           # stub emitting a canned lifeorch.skill.result/0.1
  examples/
    example-transcript.txt         # a rendered transcript sample
  runtime/artifacts/<id>/      # per-run (gitignored)
```

## Proposed implementation

- **Language:** PowerShell (the project's HID + orchestration language; WinForms via .NET). Rationale: zero
  install, single-runtime consistency, and the child-spawn/parse-envelope pattern is already the house style.
- **Approach:** spawn `agent.local` as a child pwsh with `-InputsJson`/`-ArtifactRoot`; poll from a UI timer;
  parse + render its envelope. Reimplement nothing.

## External tools or models

- None to install. Uses the present pwsh 7.4.6 + WinForms; drives the already-built `agent.local`.

## Installation steps

- None. `launch.bat` runs the UI in place.

## Tests

- **Cloud pre-ship gate (off-machine, cloud pwsh 7.4.6):** AST-parse every `.ps1`/`.psm1`; run the **real**
  `AgentConsole.psm1` core against `tests/mock-agent-local.ps1` (a stub emitting a canned envelope) — assert
  `Invoke-AgentLocalRun` spawns + parses correctly; assert `Format-AgentTranscript` renders every section for a
  matrix of canned envelopes (completed / stopped+needs_frontier / dry-run / error). The WinForms
  form-construction test is **skipped off-Windows** (WinForms is Windows-only) with a clear SKIP note.
- **Live (Windows, via the executor, `m27-*`):** the same harness `-Live` — adds `New-AgentConsoleForm` builds +
  disposes a real Form headlessly (proves the UI code constructs), `launch.bat` exists and has the right shape,
  and a **real `agent.local` dry-run** driven end-to-end through the core (real escalator/gateway model loads),
  its envelope parsed and rendered, 0 orphaned `llama-server`/pwsh, the canonical `review_queue.jsonl`
  untouched (this widget is not a producer).

## MVP acceptance criteria

- [ ] `launch.bat` opens a native window titled for the Local Agent Console with a goal box, options, Run/Cancel,
      a transcript pane, a raw-JSON pane, and a status strip.
- [ ] Submitting a goal spawns `agent.local` off the UI thread; the window stays responsive; elapsed time ticks.
- [ ] On completion the transcript renders the envelope + per-step child transcript + cost; the raw pane shows
      the JSON; errors are surfaced structurally (never a stack dump).
- [ ] Cancel kills the child process tree and returns the UI to idle.
- [ ] The core (`AgentConsole.psm1`) has no WinForms dependency and passes the cloud gate against the mock.
- [ ] Live: a real `agent.local` dry-run is driven, parsed, and rendered; 0 orphaned model servers; canonical
      review queue before==after.
- [ ] All shipped files sha256 byte-exact + AST-parse OK on the target.

## Manual verification procedure

1. Double-click `widgets\01-local-agent-console\launch.bat`.
2. Type a goal (e.g. `list the markdown files under core-docs`), leave **Dry run** checked, press **Run**.
3. Watch the status strip go Running (elapsed ticking) → Done; read the decision/args transcript.
4. Uncheck **Dry run**, try `create notes\hello.txt containing "hi from the console"`, press Run, confirm the
   file appears on disk and the transcript shows the `doc.io` tool invoked.
5. Start a goal and press **Cancel** mid-run; confirm the window returns to idle and no `pwsh`/`llama-server`
   is left running (Task Manager).

## Documentation requirements

- Widget `README.md` (what it is, how to launch, the native-delivery decision, how it maps to `agent.local`,
  the manual steps) + this work order + an example transcript.

## Registry / doc updates (end of session)

- `CURRENT_STATE.md` (new Widget track section + this widget), `MODULE_ROADMAP.md` (Phase B #1 → MVP complete),
  `DECISION_LOG.md` (D-0038 delivery+launch convention, D-0039 this widget), `widgets/README.md` (mark #1 built;
  the launch-file convention), `START_HERE.md` (widget deliverables incl. the launch file). Then mirror
  core-docs disk → the Project.

## Known follow-on work (NOT this session)

- Multi-turn / conversation history + a persistent transcript log; re-run / edit-and-re-run.
- Live per-step streaming render (needs a streaming agent.local or a progress side-channel).
- A tool-activity live view (watch `child_review.jsonl` / per-step dirs as they are written).
- Model/tier pickers surfaced in the UI; a warm-worker toggle once agent.local gains one.
- A shared widget chrome/theme + a `widget.json` manifest once Widget #2 (Launcher) needs discovery.
- Light syntax coloring of the transcript; export a run to a file.

## STOP conditions

- Scope would exceed the "Explicit scope" list (e.g. adding other skills, an editor, or multi-turn) → stop,
  write it into `widgets/README.md` / a new work order.
- `agent.local` needs a change to be drivable → stop, propose the change, do not freelance it.
- MVP acceptance is met → **stop; do not start Widget #2.**
