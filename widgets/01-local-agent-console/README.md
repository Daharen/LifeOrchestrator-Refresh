# Local Agent Console (Widget 01)

The **human front door** to the local orchestrator. Type a goal, press **Plan** to see which tools
it needs, or **Run** to plan *and* act — `agent.local` (Module 21) decides which tool to use through
the Local Logic Escalator (#19), generates the arguments and the final answer through the Model
Gateway (#7), and invokes tools from its curated closed registry — then read the result and the
step-by-step child transcript. It is the Phase-B keystone: the surface that makes the already-built
Phase-A cost-offload core usable by a person, "vicariously through the local model," the way the
frontier agent drives its own tool loop.

> A **Widget** is the HID (human-interface) layer. It plugs into the Module architecture through the
> skill contract and **never reimplements** a Module. This console only *drives* `agent.local` and
> `route.tools` (spawn a child process, parse its `lifeorch.skill.result/0.1` envelope, render it).
> Nothing else.

## Plan and Run (route.tools #27)

The console is Module-capable **through the Tool Router intermediary** (`route.tools` #27):

- **Plan** runs `route.tools` only — a fast, non-executing "router pass" that names the minimal set of
  tools the goal needs (from `agent.local`'s curated `tools.json`) and renders them. Nothing is invoked.
- **Run** = **route + execute**: `agent.local` is launched with `-Route`, so it first calls
  `route.tools` to pre-select the toolset and then runs its ReAct loop **constrained to that subset**
  (a smaller decision space -> the weak local tiers decide and terminate better; it falls back to the
  full set if the router returns nothing). The transcript shows the planned tools, whether the
  selection was applied, and which tools actually ran.

## Launch

**Double-click `launch.bat`.** (It runs the WinForms UI under the per-user PowerShell 7 in STA
mode: `pwsh -NoProfile -STA -File Show-AgentConsole.ps1`.)

No install, no admin, no server, no browser — a native window built on the WinForms already
present on this machine (see the delivery decision below).

## Using it

1. **Goal** — type what you want the local agent to do, e.g. `make an image of a dog`,
   `list the markdown files under core-docs`, or `create notes\hello.txt containing "hi"`.
2. **Working dir** — the base directory the agent operates in (defaults to the repo root).
3. **Max steps** — the hard budget on tool-selection steps (default 10).
4. **Dry run (plan only)** — the agent decides + generates arguments but invokes **no** tool and
   writes **no** file. Uncheck it to let the agent actually act.
5. **Plan** — runs `route.tools` and shows the selected tools + the catalog considered (fast, no
   execution). **Run** — routes then executes. **Cancel** stops either and kills the child tree.
6. **Read the result** — the top pane shows the rendered transcript (for Run: the planned tools,
   final answer, each step's decision / args / tool status / observation, which tools ran, and a cost
   summary; for Plan: the selected tools + catalog); the bottom pane shows the raw envelope.

The agent's capability is exactly `agent.local`'s curated closed `tools.json` (`doc.io`, `fs.observer`,
`capture.screen`, `ocr.layout`, `detect.objects`, `image.interpret`, `speech.stt`, `audio.ingest`,
`gen.image`, `gen.music`) — there is deliberately no arbitrary-shell surface (the registry is the
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
  `-InputsJson`/`-ArtifactRoot`, drain both pipes, parse the envelope) + `Format-AgentTranscript`;
  and the Plan path `Start-RouteToolsProcess` / `Complete-RouteToolsRun` / `Invoke-RouteToolsRun` +
  `Format-RoutePlan` (drive `route.tools` #27 the same way). Because it is WinForms-free, the whole
  driver is tested on the cloud pre-ship gate against mock `agent.local` + `route.tools`.
- **`Show-AgentConsole.ps1`** — the STA WinForms shell. It uses those exact core functions, starting
  the child off the UI thread and polling it from a `Timer` (so all control updates stay on the UI
  thread — no cross-thread marshaling); a `mode` flag selects the Plan vs Run render. `-SelfTest`
  builds and disposes the form (used by the live gate).
- **`launch.bat`** — the double-click launcher. **`tests/`** — the dual-mode harness + mock
  `agent.local` + mock `route.tools`.

Per-run artifacts (the child output, redirected `child_review.jsonl`, stdout/stderr) land under
`runtime/artifacts/<id>/` (gitignored). This widget is **not** a review-queue producer.

## Tests

- **Cloud gate:** `pwsh -File tests/Invoke-AgentConsoleTests.ps1` — AST-parses every script and drives
  the real core against `tests/mock-agent-local.ps1` + `tests/mock-route-tools.ps1` (completed /
  dry-run / stopped / error / noisy scenarios + the Plan path + a `-Route` run's planned-tools
  rendering). WinForms + real-child tests are skipped off-Windows.
- **Live (Windows):** `... -Live` — adds the WinForms form self-test, `launch.bat` shape, a real
  `route.tools` Plan, and a real `agent.local` run driven end-to-end with no orphaned `llama-server`.

## Not in this MVP (follow-ons)

Multi-turn / conversation history; live per-step streaming; a tool-activity live view; model/tier
pickers in the UI; transcript export; light syntax coloring. See `WORK_ORDER.md`.
