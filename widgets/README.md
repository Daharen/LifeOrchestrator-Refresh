# widgets/ -- the Widget (human-interface) layer

A **Widget** is a human-interface tool -- a real window / application -- that connects a *person* into the
Life Orchestrator module architecture, usually by driving the local orchestrator + Local Logic Escalator
so a Widget can reach every `modules/` capability without embedding each one. Widgets are how the whole
package becomes usable by a **human**, not only by an AI agent. They are the HID (human-interface) layer;
"Widget" keeps it colloquial and modular while signalling these are full apps that plug into the
architecture -- **not** lesser sub-windows.

- **Module** (`modules/`) = a backend capability an agent invokes through `SKILL_CONTRACT.md`.
- **Widget** (here) = a human-facing app that plugs into those Modules.

## Layout & rules
- Each Widget lives in `widgets/<NN>-<name>/` (mirroring the module layout): code + a `WORK_ORDER.md` +
  `README.md` + tests + **a `launch.bat` launcher**, self-contained.
- **Every Widget ships a launch file (`launch.bat`)** so the user can start it with a double-click, without
  hand-typing a `pwsh` command. Native Widgets launch `pwsh -NoProfile -STA -File <entry>.ps1`; a web Widget's
  launcher starts its local server and opens the browser. This is a standing convention (**D-0038**) -- future
  Widget sessions ship it without being re-prompted.
- A Widget reaches Modules **through** the local orchestrator / escalator and the skill contract -- it must
  **never reimplement** a Module (same discipline as the orchestrator skills `voice.live` / `image.index`).
- Widgets are the human surface; the intelligence and capability stay in `modules/`. Keep each Widget thin.

## Delivery: native by default (D-0038)
The **project-wide default is native** -- a real Windows window built with **WinForms via the dotnet-tool
`pwsh 7.4.6`, run STA** -- because on this box it is zero-install (probe-verified), single-runtime-consistent
with the whole spawn-and-parse architecture, and makes the launch file a trivial double-click `.bat`. A
**locally-served web UI is a per-widget override**, permitted when a Widget genuinely needs rich media or
remote access (e.g. Generator Studio previews); it is decided in that Widget's own work order. Either way the
Widget ships a `launch.bat`. See **D-0038** for the rationale (it resolves D-0029's open native-vs-web item).

## Buildout order (see `core-docs/MODULE_ROADMAP.md -> Build priority`, Phase B)
Built once the utility / cost-offload Modules exist (Local Logic Escalator, a local orchestrator, doc I/O,
and a couple of generators). Ordered most usability-per-effort first:

1. **Local Agent Console** -- **BUILT: MVP complete 2026-07-26 (D-0039; `widgets/01-local-agent-console/`).**
   The keystone: a human <-> local-LLM goal/agent window that drives `agent.local` (#21) -- which decides
   through the Local Logic Escalator and can invoke any registered Module -- and renders its result envelope +
   child transcript. Delivers the whole package "vicariously through the local model," the way the frontier
   agent does today. This is the milestone that makes the system usable locally.
2. **Module Launcher & Registry Browser** -- **BUILT: MVP complete 2026-07-27 (D-0049; `widgets/02-module-launcher/`).**
   Discover + run any installed Module directly (discoverability): browse every `modules/*/skill.json` (id / purpose /
   inputs / requirements / flags; malformed manifests surfaced) and run any one **through the Module 1 wrapper
   `Invoke-Skill.ps1`**, rendering its invocation report + result envelope. Native WinForms over a WinForms-free driver
   core -- the Widget #1 pattern (D-0039). Reimplements nothing; not a review-queue producer.
3. **Review / Escalation Dashboard** -- a human surface over the review queue + the escalation ladder
   (watch / approve / adjudicate flagged items and escalation ladders).
4. **Voice Console** -- push-to-talk / live loop over `voice.live` (Module 13).
5. **Generator Studio** -- prompt -> preview -> save over the image / audio / music / video generators.
6. **Document Workspace** -- browse / edit local docs with model assist over the Local Model Doc I/O Module.
7. **System / Executor Monitor** -- executor + watchdog + task-queue health, running tasks, logs.
8. **Screen / Perception Inspector** -- later, a surface over the screen-perception stack (Modules 28+).

See `core-docs/ARCHITECTURE_MAP.md` for the full architecture and where the backing Modules sit.
