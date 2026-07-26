# Local Agent Console (Widget 01)

The **human front door** to the local orchestrator. Type a goal, press **Run**, and watch
`agent.local` (Module 21) plan and act — deciding which tool to use through the Local Logic
Escalator (#19), generating the arguments and the final answer through the Model Gateway (#7),
and invoking tools from its closed registry — then read the result and the step-by-step child
transcript. It is the Phase-B keystone: the surface that makes the already-built Phase-A
cost-offload core usable by a person, "vicariously through the local model," the way the
frontier agent drives its own tool loop.

> A **Widget** is the HID (human-interface) layer. It plugs into the Module architecture through
> the skill contract and **never reimplements** a Module. This console only *drives* `agent.local`
> (spawn a child process, parse its `lifeorch.skill.result/0.1` envelope, render it). Nothing else.

## Launch

**Double-click `launch.bat`.** (It runs the WinForms UI under the per-user PowerShell 7 in STA
mode: `pwsh -NoProfile -STA -File Show-AgentConsole.ps1`.)

No install, no admin, no server, no browser — a native window built on the WinForms already
present on this machine (see the delivery decision below).

## Using it

1. **Goal** — type what you want the local agent to do, e.g. `list the markdown files under core-docs`
   or `create notes\hello.txt containing "hi from the console"`.
2. **Working dir** — the base directory the agent operates in (defaults to the repo root).
3. **Max steps** — the hard budget on tool-selection steps (default 4).
4. **Dry run (plan only)** — checked by default: the agent decides + generates arguments but
   invokes **no** tool and writes **no** file. Uncheck it to let the agent actually act.
5. **Run** — submits the goal. The window stays responsive while the local models load (that can
   take a minute or two); the status strip shows elapsed time. **Cancel** stops a run and kills the
   child process tree.
6. **Read the result** — the top pane shows the rendered transcript (final answer + each step's
   decision / args / tool status / observation + a cost summary); the bottom pane shows the raw
   result envelope (and, on failure, the raw stdout + stderr tail).

The agent's capability is exactly `agent.local`'s closed `tools.json` (currently `doc.io` #20 +
`fs.observer` #2) — there is deliberately no arbitrary-shell surface here (the registry is the
sandbox, D-0032).

## Delivery: native (WinForms), zero-install — D-0038

This widget, and the Widget layer by default, is delivered **native** (WinForms via the dotnet-tool
`pwsh 7.4.6`, run STA) rather than as a locally-served web UI. On this box that is zero-install
(WinForms + an STA runspace hosting a Form were probe-verified to work in the existing pwsh),
single-runtime-consistent with the whole spawn-and-parse architecture, and it makes the launch file
a trivial double-click `.bat`. A locally-served web UI remains a **per-widget** option for widgets
that genuinely need rich media or remote access (e.g. Generator Studio previews); it is not the
default. Every widget ships a `launch.bat` so the user can start it directly.

## How it is built (thin, testable)

- **`AgentConsole.psm1`** — the driver core, **no WinForms**: `Start-AgentLocalProcess` /
  `Complete-AgentLocalRun` / `Invoke-AgentLocalRun` (spawn `agent.local` as a child pwsh with
  `-InputsJson`/`-ArtifactRoot`, drain both pipes, parse the envelope) and `Format-AgentTranscript`
  (envelope → readable transcript). Because it is WinForms-free, the whole driver is tested on the
  cloud pre-ship gate against a mock `agent.local`.
- **`Show-AgentConsole.ps1`** — the STA WinForms shell. It uses those exact core functions, starting
  the child off the UI thread and polling it from a `Timer` (so all control updates stay on the UI
  thread — no cross-thread marshaling). `-SelfTest` builds and disposes the form (used by the live gate).
- **`launch.bat`** — the double-click launcher. **`tests/`** — the dual-mode harness + a mock agent.local.

Per-run artifacts (the agent's child output, redirected `child_review.jsonl`, stdout/stderr) land
under `runtime/artifacts/<id>/` (gitignored). This widget is **not** a review-queue producer.

## Tests

- **Cloud gate:** `pwsh -File tests/Invoke-AgentConsoleTests.ps1` — AST-parses every script and drives
  the real core against `tests/mock-agent-local.ps1` (completed / dry-run / stopped / error / noisy
  scenarios) + transcript rendering. WinForms + real-agent tests are skipped off-Windows.
- **Live (Windows):** `... -Live` — adds the WinForms form self-test, `launch.bat` shape, and a real
  `agent.local` dry-run driven end-to-end with no orphaned `llama-server`.

## Not in this MVP (follow-ons)

Multi-turn / conversation history; live per-step streaming; a tool-activity live view; model/tier
pickers in the UI; transcript export; light syntax coloring. See `WORK_ORDER.md`.
