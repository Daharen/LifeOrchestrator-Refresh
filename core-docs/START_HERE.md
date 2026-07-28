# START_HERE

**You are a fresh Claude instance joining Life Orchestrator (near-term "local skills" track).**
Read this first. It routes you; it does not contain the project's substance.

> **ACTIVE WORK -- iterate loop, running HOT (2026-07-27, D-0050/D-0051).** The correction arc is CLOSED
> (D-0043/44/46), the ship ceremony is automated (D-0048 job-runner), and the project drives ONE spine -- the
> OFFLOAD / AUDIT LOOP under the **verify-cost rule** (Claude offloads only what is cheaper to VERIFY than to
> do; deterministic modules are Claude's hands; model modules only where machine- or human-checkable).
> **Widget #3 -- the Verification Console -- SHIPPED (D-0051, commit `f7e7b289`; 73/73 cloud + 80/80 live):**
> the human-AUDIT surface where Claude hands Nicholas a verification packet and he runs + checks it locally and
> exports a result Claude reads back. **The FAN-OUT ORCHESTRATOR SHIPPED (D-0054: `orchestrate.fanout`, Module 30; commit `2ffe162e`; 51/51 cloud + 51/51 live) -- built on res.lease #29; both multi-instance primitives now exist.** **Fan-out DOGFOOD iteration 1 COMPLETE (D-0055, plan fo-1-20ed8a0b): 3 workers shipped -- res.lease gpu->model.gateway #7 (0c6d5c9, 42/42), res.lease git->dev.ship (5530418, 39/39), frontier.bridge #31 built (f52f21d, 65/65); 0 conflicts, 3/3 done, handoff emitted a verification packet.** Iterations 2-3 followed (D-0056): iter 2 shipped doc:<path>->doc.io (d2a7352, 106/106) + the Module 30 template fix (581f854); E (warm-server) failed + wedged the executor (recovered); iter 3 single-worker G shipped executor+watchdog hardening (e5b93ab, 16/16 + 33/33) + the executor was restarted onto it; res.lease consumer trio complete. Iteration 4 followed (D-0057, fo-4, 3/3): E2 shipped the DETACHED warm server (Governor Phase 2 DONE, f8c961a), H validated the Verification Console audit loop end-to-end (174360d), I hardened frontier.bridge + produced a real Phase 3 escalation pack (b17a945). Iteration 5 shipped the two Console-dogfood follow-ons (D-0058: Console teardown orphan-sweep 033fd6f + Module 30 packet-input validation 2afd5de). Iteration 6 shipped the Governor Phase 3 Stage-1 auto-ramp controller (D-0059, fo-6-b918dbb8: agent.local #21 opt-in `-AutoRamp`, monotonic model-affine epochs M0->M1->S0 + a pre-frozen lifeorch.goal_verification/0.1 success contract, 0005e41; calibration 9B 6/6 vs 3B 4/6; off-machine 50/50 + agent.local 87/87 green; live floor->M0 + ramp M0->M1->S0, 0 orphans). Next unit: **iteration 7** -- Governor Phase 3 Stage-2 / wire `-AutoRamp` into a caller / the residual live-GUI Console pass. **If you are the fan-out orchestrator, read core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md.** Cadence: **housekeeping -> implement one unit -> housekeeping -> handoff**, repeat. Read
> `core-docs/HANDOFF.md` + `DECISION_LOG.md` D-0050/D-0051 before picking work.

## What this project is (one line)

We are building a suite of small, independently-invokable **local skills** that frontier and
local agents can call to do real work on this Windows machine — offloading token cost from the
cloud onto the local computer. Backend capabilities live in `modules/` (**Modules**); human-interface
apps that plug into them live in `widgets/` (**Widgets** — the HID layer; see `widgets/README.md`; every Widget ships a double-click `launch.bat` so the user can run it directly, and Widgets are native by default -- D-0038).
Work proceeds **one scoped Module or Widget per session** (vocabulary + priority in `PROJECT_DIRECTION.md`,
D-0029; the full destination is `ARCHITECTURE_MAP.md`, the current order is `MODULE_ROADMAP.md → Build priority`).

## What phase we are in

**Phase: MVP module build-out.** Speed, practical usefulness, and modularity come first.
A deterministic control-plane architecture is a long-term goal, **not** a current requirement.
Module 0 (the Trusted High-Risk Bootstrap Executor) is complete; it is how your work gets run
locally.

## Source of truth (docs & state)

**The on-disk repo is canonical** — `C:\Users\just_\LifeOrchestrator-Refresh\` (`core-docs/` + `modules/` + `widgets/`).
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
- `ARCHITECTURE_MAP.md` — only for long-range orientation (the canonical 0-49 spine + the real-time
  autonomic layer + the operating hierarchy). It is the **destination, not the build order** — the current
  order is `MODULE_ROADMAP.md → Build priority` (D-0029).

## How you identify the current module

The single active module is named in `CURRENT_STATE.md` (`Active module`) and marked `In progress`
or `Active` in `MODULE_ROADMAP.md`. Open **that module's work order** (`modules/<NN>-<name>/WORK_ORDER.md`) and nothing else's.

## What you may modify

- The active module's own files, its work order, and its documentation.
- The shared status/registry docs **only to record your results**: `CURRENT_STATE.md`,
  `MODULE_ROADMAP.md`, `TOOL_MODEL_REGISTRY.md`, `DECISION_LOG.md`, `REVIEW_QUEUE.md`.
- `SKILL_CONTRACT.md` **only** when your module genuinely exposes a missing contract requirement
  (bump its version and log the change in `DECISION_LOG.md`).

Do **not** rearchitect other modules or expand scope beyond the work order.

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
- **One scoped unit at a time (a Module or a Widget).** If you find yourself expanding scope, stop and write
  the extra work into `MODULE_ROADMAP.md` / a new work order instead.
