# START_HERE

**You are a fresh Claude instance joining Life Orchestrator (near-term "local skills" track).**
Read this first. It routes you; it does not contain the project's substance.

> **ACTIVE WORK:** the fan-out loop (53 iterations run). **Orchestrator boot = the PCB (D-0146, i53 migration GO).**
> If you are the **fan-out orchestrator** working on disk, boot from
> `modules/44-project-map/generated/BOOT_PACKET.md` FIRST -- run its step-0 (`project_map.py verify` /
> `query stale`), then expand by progressive disclosure (L0 map -> L1 `card:` -> L2 `section:`/`--q` queries).
> `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` is now the FALLBACK + deep-reference (operational mechanics +
> gotchas the packet points into) and the context for Project-mirror / desktop-less sessions that cannot reach
> the generated packet. If you are a dispatched **worker**, read the brief you were pointed at
> (`core-docs/fanout/FANOUT_AGENT_00N.md` / Project `claude/fanout/`) and execute exactly that unit.
> Live status: the PCB overlay + `CURRENT_STATE.md`.

## What this project is (one line)

We are building a suite of small, independently-invokable **local skills** that frontier and
local agents can call to do real work on this Windows machine -- offloading token cost from the
cloud onto the local computer. Backend capabilities live in `modules/` (**Modules**); human-interface
apps that plug into them live in `widgets/` (**Widgets** -- the HID layer; see `widgets/README.md`; every
Widget ships a double-click `launch.bat` and is native by default -- D-0038).
Work proceeds **one scoped Module or Widget per session** (vocabulary + priority in `PROJECT_DIRECTION.md`,
D-0029; the full destination is `ARCHITECTURE_MAP.md`; the current order is `MODULE_ROADMAP.md -> Build priority`).

## What phase we are in

**Phase: MVP module build-out**, driven past-MVP by the OFFLOAD / AUDIT-LOOP spine under the verify-cost
rule (D-0050): Claude offloads only what is cheaper to VERIFY than to do; deterministic modules are
Claude's hands; model modules only where machine- or human-checkable. Module 0 (the executor) is how all
local work runs.

## Source of truth (docs & state)

**The on-disk repo is canonical** -- `C:\Users\just_\LifeOrchestrator-Refresh\` (`core-docs/` + `modules/`
+ `widgets/` + `archive/`). That is what the executor and local models read, and what git tracks.

**The attached Claude Project mirrors `core-docs/`** so desktop-less sessions (scheduled, mobile, or
pre-folder-grant) still have context. Disk wins on any disagreement; the frontier agent re-mirrors at
session end. Full mirror map + doc rules: `DOC_PROTOCOL.md`.

**Doc discipline (D-0066):** every hot doc has a size budget and a REPLACE-don't-append rule
(`DOC_PROTOCOL.md`). History is never deleted -- it moves to `DECISION_LOG.md` (append-only; index doc `DECISION_LOG_INDEX.md`),
git, and `archive/` (indexed by `archive/ARCHIVE_INDEX.md`). There is exactly ONE live handoff doc.

## Reading order (route, don't load everything)

**Always read (hot context for any session):**
1. `PROJECT_DIRECTION.md` -- the doctrine and long-term direction.
2. `CURRENT_STATE.md` -- what actually exists right now (it names the active work).
3. The **active work order**: for module work, `modules/<NN>-<name>/WORK_ORDER.md`; for the fan-out loop, the
   PCB `modules/44-project-map/generated/BOOT_PACKET.md` (orchestrator; the handoff is the fallback) or your
   `fanout/FANOUT_AGENT_00N.md` brief (worker).

**Read only when relevant:**
- `MODULE_ROADMAP.md` -- build order + your module's entry (do not ingest whole).
- `SKILL_CONTRACT.md` -- creating or modifying a skill.
- `TOOL_MODEL_REGISTRY.md` -- selecting/invoking a tool or model.
- `DECISION_LOG_INDEX.md` -- the one-row-per-decision index; pull the specific `D-00NN` entry from
  `DECISION_LOG.md` only when it bears on your task (never ingest the whole log).
- `DOC_PROTOCOL.md` -- before editing any core doc.
- `MODULE_WORK_ORDER_TEMPLATE.md` -- authoring a new work order.
- `REVIEW_QUEUE.md` -- producing or consuming flagged/low-confidence items.
- `ARCHITECTURE_MAP.md` -- long-range orientation only (destination, not build order -- D-0029).
- `ADAPTIVE_RESOURCE_GOVERNOR.md` -- touching agent.local's governor / auto-ramp.

## How you identify the current work

`CURRENT_STATE.md -> Active work` names it; `MODULE_ROADMAP.md` marks module status. Open that unit's work
order or brief and nothing else's.

## What you may modify

- The active module's own files, its work order, and its documentation.
- The shared status/registry docs **only to record your results**: `CURRENT_STATE.md`,
  `MODULE_ROADMAP.md`, `TOOL_MODEL_REGISTRY.md`, `DECISION_LOG.md`, `REVIEW_QUEUE.md` -- per
  `DOC_PROTOCOL.md` (budgets; replace, don't append).
- `SKILL_CONTRACT.md` **only** when your module genuinely exposes a missing contract requirement
  (bump its version and log the change in `DECISION_LOG.md`).
- Fan-out workers: `docs:[]` -- you do NOT touch core-docs; you report and the orchestrator mirrors.

Do **not** rearchitect other modules or expand scope beyond the work order.

## Before you end a work session (mandatory)

Run the **end-of-session doc checklist in `DOC_PROTOCOL.md` section 9** (update-by-replacement, decision
log + index row, unresolved questions, size check, executor commit under the git lease, re-mirror). Then **stop. Do not begin the
next unit.** One scoped Module or Widget (or one orchestrated wave) per session.

## Two rules that override cleverness

- **Useful MVP completion beats speculative architecture.** Ship the smallest thing that works and is
  testable through the executor.
- **One scoped unit at a time.** If you find yourself expanding scope, stop and write the extra work into
  `MODULE_ROADMAP.md` / a new work order instead.
