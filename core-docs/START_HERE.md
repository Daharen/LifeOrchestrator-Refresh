# START_HERE

**You are a fresh Claude instance joining Project Proteus (near-term "local skills" track).**
Read this first. It routes you; it does not contain the project's substance.

## What this project is (one line)

We are building a suite of small, independently-invokable **local skills** that frontier and
local agents can call to do real work on this Windows machine — offloading token cost from the
cloud onto the local computer. Skills are built and run **one module at a time**.

## What phase we are in

**Phase: MVP module build-out.** Speed, practical usefulness, and modularity come first.
Deterministic/canonical "Proteus" architecture is a long-term goal, **not** a current requirement.
Module 0 (the Trusted High-Risk Bootstrap Executor) is complete; it is how your work gets run
locally.

## Source of truth (docs & state)

**The on-disk repo is canonical** — `C:\Users\just_\Project-Proteus-Refresh\` (`core-docs/` + `modules/`).
That is what the executor and local models read, and what we commit to git.

**The attached Claude Project mirrors `core-docs/`.** The frontier agent keeps it current (via the Project
tools) so sessions with no desktop connected — scheduled, mobile, or before the folder is granted — still
have full context. Rules:

- Edit the **on-disk** docs first; they are what git tracks.
- Before ending a session, **refresh the Project from disk** so the two match (see the end-of-session checklist).
- If the two ever disagree, **disk wins** — re-mirror disk → Project.
- The executor can maintain on-disk files (PowerShell tasks) but **cannot** touch the Project; only the
  frontier agent updates the Project.

## Reading order (route, don't load everything)

**Always read (hot context for any module session):**
1. `PROJECT_DIRECTION.md` — the doctrine and long-term direction.
2. `CURRENT_STATE.md` — what actually exists right now (machine, deps, models, executor status).
3. `MODULE_ROADMAP.md` — module order and status; tells you which module is active.
4. `SKILL_CONTRACT.md` — the interface every skill must satisfy (read when creating/modifying a skill).
5. The **active module work order** (see `CURRENT_STATE.md → Active module`).

**Read only when relevant:**
- `TOOL_MODEL_REGISTRY.md` — only when selecting/invoking a tool or model.
- `DECISION_LOG.md` — only when a prior architectural decision may bear on your task.
- `MODULE_WORK_ORDER_TEMPLATE.md` — only when authoring a new work order.
- `REVIEW_QUEUE.md` — only when producing or consuming flagged/low-confidence items.
- `cold-reference/` (long-horizon Proteus: simulation, canonicalization, projection) — **do not load**
  unless your active work concerns those systems.

## How you identify the current module

The single active module is named in `CURRENT_STATE.md` (`Active module`) and marked `In progress`
or `Active` in `MODULE_ROADMAP.md`. Open **that module's work order** (`modules/<NN>-<name>/WORK_ORDER.md`) and nothing else's.

## What you may modify

- The active module's own files, its work order, and its documentation.
- The shared status/registry docs **only to record your results**: `CURRENT_STATE.md`,
  `MODULE_ROADMAP.md`, `TOOL_MODEL_REGISTRY.md`, `DECISION_LOG.md`, `REVIEW_QUEUE.md`.
- `SKILL_CONTRACT.md` **only** when your module genuinely exposes a missing contract requirement
  (bump its version and log the change in `DECISION_LOG.md`).

Do **not** rearchitect other modules, expand scope beyond the work order, or import the cold-reference
Proteus architecture into near-term work.

## Before you end a work session (mandatory)

1. Update `CURRENT_STATE.md` (active module, executor status, deps/models, tests, failures, next action,
   last-update time + agent).
2. Update `MODULE_ROADMAP.md` (status of the module you touched).
3. Update `TOOL_MODEL_REGISTRY.md` (anything you installed, wrapped, or verified).
4. Record any significant architectural decision in `DECISION_LOG.md`.
5. Add unresolved uncertainties to `REVIEW_QUEUE.md`.
6. **Mirror `core-docs/` → the attached Claude Project** (`project_write` each changed doc) so the Project
   matches disk — disk is canonical; the Project is a mirror for desktop-less (scheduled/mobile) sessions.
7. **Stop. Do not begin the next module.** One scoped module or work order per session.

## Two rules that override cleverness

- **Useful MVP completion beats speculative architecture.** Ship the smallest thing that works and is
  testable through the executor.
- **One module at a time.** If you find yourself expanding scope, stop and write the extra work into
  `MODULE_ROADMAP.md` / a new work order instead.
