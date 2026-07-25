# PROJECT_DIRECTION

Stable doctrine for the near-term track. Concise by design. This document owns **project purpose
and direction**; it does not own status (`CURRENT_STATE.md`), module order (`MODULE_ROADMAP.md`),
or interface rules (`SKILL_CONTRACT.md`).

## Present goal

Create **useful local capabilities that frontier and local agents can invoke** on this machine.
Each capability is a *skill*: independently usable, testable on its own, and runnable through the
bootstrap executor. Success is measured in working MVPs, not architectural completeness.

## Modules and Widgets (vocabulary — D-0029)

We build two kinds of thing. A **Module** (under `modules/`) is a backend capability that AI agents — and
Widgets — invoke through `SKILL_CONTRACT.md`; it is modular because it satisfies the contract, not because
of its language. A **Widget** (under `widgets/`) is a human-interface tool — a real window/application —
that connects a *person* into the Module architecture, usually by driving the local orchestrator + Local
Logic Escalator so it reaches every Module without embedding each one. Modules give the system capability;
Widgets make it usable by a human. (Widget is the adopted name for the HID / human-interface layer.)

## Current-phase priorities

- **Speed and practical usefulness first.** A working, testable MVP beats an elegant unfinished design.
- **Modularity.** Skills must be independently usable *before* any integrated orchestration is built.
- **Offload cost locally.** The system should increasingly move remote token consumption onto the
  local computer — cheap local work done locally, expensive judgment reserved for capable models.
- **Usable local core before deep research (D-0029).** The near-term build order is prioritized, not
  strictly sequential: build the cost-offload keystones (the Local Logic Escalator + a local orchestrator),
  a few utility Modules (doc I/O, generators), and the Widget layer that makes them human-usable **before**
  resuming the slower architecture spine. Every task a local model finishes end-to-end is a task the weekly
  frontier allotment never pays for. The current build order lives in `MODULE_ROADMAP.md → Build priority`.

## Perception and reasoning policy

- **Stochastic perception and reasoning are acceptable.** Deterministic canonical collapse is a
  long-term aim, **not** an admission requirement for a module today.
- Successful stochastic workflows may **later** be converted into cheaper deterministic tools. Build
  the working stochastic version first; harden it only when it earns the effort.

## Model-tier policy (who does what)

- **Frontier models:** difficult judgment, planning, ambiguous adjudication, and correction of flagged
  results. Their time is the scarce resource — spend it only where it matters.
- **Weaker local models:** classification, sorting, labeling, extraction, indexing, and repetitive
  bulk work where "good enough" is adequate.
- **Stronger local models:** review of uncertain, contradictory, or flagged outputs from weaker models —
  ideally running slowly in the background against the review queue.
- Route the smallest sufficient tier to each task; escalate only on low confidence or conflict.
  (Routing is a future module — see `MODULE_ROADMAP.md` #24 — not something to hand-build now.)

## Implementation-language policy

Priority order for any module: **(1) working & useful, (2) independently testable, (3) contract-compliant,
(4) replaceable, (5) observable & documented, (6) reasonably efficient, (7) portable where cheap,
(8) C++ where it provides durable value.** The **skill contract, not the language, provides modularity.**

- **C++ preferred** for long-running hosts, scheduling, registries, IPC, resource management, stable
  interfaces, high-throughput processing, and components likely to remain central.
- **Python acceptable** for model ecosystems, vision, speech, rapid experimentation, and libraries with
  no sensible C++ equivalent.
- **PowerShell acceptable** for Windows inspection, filesystem work, process management, installation,
  integration glue, and initial MVPs.
- **Wrap existing executables** rather than reimplementing them when they already solve the problem well.

## Execution channel

The **Trusted High-Risk Bootstrap Executor** (Module 0) is the initial execution channel: authorized
agents submit PowerShell task packages to a filesystem queue and receive machine-readable results.

- It is **trust-based, not a sandbox.** Anything that can write to its queue runs with the Windows
  user's authority. That is intentional for this phase.
- **Modules must not add** concealment, shutdown resistance, unauthorized propagation, monitoring
  evasion, or covert persistence — and must not attempt to preserve access after authorization is
  revoked. These are hard prohibitions, not stylistic preferences.

## Long-horizon note (deliberately brief)

Life Orchestrator's own long-horizon aims may include a persistent structured memory, coordinated
local + remote model orchestration, and the progressive replacement of stochastic workflows with cheaper
deterministic tools where they earn it. **None of that is near-term work.** The full destination — the
canonical 0-49 Module spine, the real-time autonomic control layer (45-49), and the 6-level operating
hierarchy — is mapped in `ARCHITECTURE_MAP.md` (a reference for orientation, **not** a build order).

Two things this project is explicitly **not**: the earlier assistant codebase in `LifeOrchestrator\repo`
(kept as reference material to fold in later, not a dependency now) and the separate **Project Proteus**
game (a systemic RPG with its own deterministic player-identity engine — no overlap with this project).
