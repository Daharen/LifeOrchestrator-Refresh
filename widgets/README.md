# widgets/ — the Widget (human-interface) layer

A **Widget** is a human-interface tool — a real window / application — that connects a *person* into the
Life Orchestrator module architecture, usually by driving the local orchestrator + Local Logic Escalator
so a Widget can reach every `modules/` capability without embedding each one. Widgets are how the whole
package becomes usable by a **human**, not only by an AI agent. They are the HID (human-interface) layer;
"Widget" keeps it colloquial and modular while signalling these are full apps that plug into the
architecture — **not** lesser sub-windows.

- **Module** (`modules/`) = a backend capability an agent invokes through `SKILL_CONTRACT.md`.
- **Widget** (here) = a human-facing app that plugs into those Modules.

## Layout & rules
- Each Widget lives in `widgets/<NN>-<name>/` (mirroring the module layout): code + a `WORK_ORDER.md` +
  `README.md` + tests, self-contained.
- A Widget reaches Modules **through** the local orchestrator / escalator and the skill contract — it must
  **never reimplement** a Module (same discipline as the orchestrator skills `voice.live` / `image.index`).
- Widgets are the human surface; the intelligence and capability stay in `modules/`. Keep each Widget thin.
- Delivery per Widget (a native window — WinForms/WPF — or a locally-served web UI) is decided in its own
  work order.

## Buildout order (see `core-docs/MODULE_ROADMAP.md → Build priority`, Phase B)
Built once the utility / cost-offload Modules exist (Local Logic Escalator, a local orchestrator, doc I/O,
and a couple of generators). Ordered most usability-per-effort first:

1. **Local Agent Console** — the keystone: a human <-> local-LLM chat/agent window that runs the Local
   Logic Escalator and can invoke any Module. Delivers the whole package "vicariously through the local
   model," the way the frontier agent does today. This is the milestone that makes the system usable locally.
2. **Module Launcher & Registry Browser** — discover + run any installed Module directly (discoverability).
3. **Review / Escalation Dashboard** — a human surface over the review queue + the escalation ladder
   (watch / approve / adjudicate flagged items and escalation ladders).
4. **Voice Console** — push-to-talk / live loop over `voice.live` (Module 13).
5. **Generator Studio** — prompt -> preview -> save over the image / audio / music / video generators.
6. **Document Workspace** — browse / edit local docs with model assist over the Local Model Doc I/O Module.
7. **System / Executor Monitor** — executor + watchdog + task-queue health, running tasks, logs.
8. **Screen / Perception Inspector** — later, a surface over the screen-perception stack (Modules 28+).

See `core-docs/ARCHITECTURE_MAP.md` for the full architecture and where the backing Modules sit.
