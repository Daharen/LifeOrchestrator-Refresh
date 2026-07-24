# PROJECT_DIRECTION

Stable doctrine for the near-term track. Concise by design. This document owns **project purpose
and direction**; it does not own status (`CURRENT_STATE.md`), module order (`MODULE_ROADMAP.md`),
or interface rules (`SKILL_CONTRACT.md`).

## Present goal

Create **useful local capabilities that frontier and local agents can invoke** on this machine.
Each capability is a *skill*: independently usable, testable on its own, and runnable through the
bootstrap executor. Success is measured in working MVPs, not architectural completeness.

## Current-phase priorities

- **Speed and practical usefulness first.** A working, testable MVP beats an elegant unfinished design.
- **Modularity.** Skills must be independently usable *before* any integrated orchestration is built.
- **Offload cost locally.** The system should increasingly move remote token consumption onto the
  local computer — cheap local work done locally, expensive judgment reserved for capable models.

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

The broader Proteus vision may eventually incorporate: canonical collapse, deterministic replay,
structured memory, coordinated local + remote model orchestration, world simulation, and the
progressive replacement of stochastic processes with deterministic systems. **None of that is
near-term work.** Its detailed architecture lives in `cold-reference/` and must not be loaded into
ordinary module sessions.
