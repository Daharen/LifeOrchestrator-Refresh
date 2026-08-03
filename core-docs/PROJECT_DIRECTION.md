# PROJECT_DIRECTION

Stable doctrine for the near-term track. Concise by design. This document owns **project purpose
and direction**; it does not own status (`CURRENT_STATE.md`), module order (`MODULE_ROADMAP.md`),
or interface rules (`SKILL_CONTRACT.md`). The long-horizon **memory architecture** that realizes cognitive virtual memory is `MEMORY_ARCHITECTURE.md` (governing design, D-0090), validated by `MEMORY_BENCHMARK.md`.

## Present goal (D-0080): the Collective Agent

Build a **persistent local managerial and construction system** -- a *Collective Agent* -- in which Nicholas is
the manager, product owner, and final authority, and the system retrieves its own relevant knowledge, activates
the right skills, delegates bounded work, verifies results, learns reusable procedures from experience, and
iteratively constructs Life Orchestrator and other projects.

The design principle is **cognitive virtual memory**: external stores (repo, SQLite, artifacts) are the
authoritative memory; a model context is a disposable working set. A deterministic coordinator hands a model a
small, task-specific packet; specialist Modules execute; evaluators verify; successful experience becomes
structured memory and reusable procedure. The active reasoner is only one component -- this is not a better
chatbot, it is an apprentice organization.

This EXTENDS, and does not discard, the offload / verify-cost doctrine (D-0050) and the usable-local-core build
order (D-0029): the existing ~35 Modules + 4 Widgets are the substrate; the reprioritization (D-0080; directive
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`) connects them into the architecture
that makes them cumulatively useful. Success = retrieved-and-verified work Nicholas did not have to decompose,
not module count.

**Hardware framing.** The **RTX 2080 Ti** (one ~7 GB heavyweight resident at a time; a 9B executive + many fresh
contexts) is the active build target. An **RTX PRO 6000-class 96 GB** box is the horizon upgrade -- a stronger
executive + more concurrency, a configuration change, NOT an architecture prerequisite. The architecture must not
depend on 96 GB VRAM to function.

## Modules and Widgets (vocabulary — D-0029)

We build two kinds of thing. A **Module** (under `modules/`) is a backend capability that AI agents — and
Widgets — invoke through `SKILL_CONTRACT.md`; it is modular because it satisfies the contract, not because
of its language. A **Widget** (under `widgets/`) is a human-interface tool — a real window/application —
that connects a *person* into the Module architecture, usually by driving the local orchestrator + Local
Logic Escalator so it reaches every Module without embedding each one. Modules give the system capability;
Widgets make it usable by a human. (Widget is the adopted name for the HID / human-interface layer.)

## Current-phase priorities

- **Collective Agent first (D-0080).** The immediate priority is the memory / retrieval / context-compilation /
  skill-activation / episodic-failure-procedure substrate that turns the existing Modules into one persistent
  agent. Further durable-supervisor / warm-pool hardening (the D-0079 GATE-NO stands), generator upgrades,
  model-heavy video interpretation, deep real-time perception, and broad training are FROZEN or deferred. Build
  order + Wave 1: `MODULE_ROADMAP.md -> Build priority` + `FANOUT_ORCHESTRATOR_HANDOFF.md` section 4.
- **Speed and practical usefulness first.** A working, testable MVP beats an elegant unfinished design.
- **Modularity.** Skills must be independently usable *before* any integrated orchestration is built.
- **Offload cost locally.** The system should increasingly move remote token consumption onto the
  local computer — cheap local work done locally, expensive judgment reserved for capable models.
- **Usable local core before deep research (D-0029).** The near-term build order is prioritized, not
  strictly sequential: build the cost-offload keystones (the Local Logic Escalator + a local orchestrator),
  a few utility Modules (doc I/O, generators), and the Widget layer that makes them human-usable **before**
  resuming the slower architecture spine. Every task a local model finishes end-to-end is a task the weekly
  frontier allotment never pays for. The current build order lives in `MODULE_ROADMAP.md → Build priority`.
- **Cut the frontier''s own operating overhead (2026-07-27, D-0047).** Offloading work locally only nets out if DRIVING the local system is cheap too. The per-unit ship/verify/test/commit/mirror ceremony is now the dominant frontier-token sink, so an executor JOB-RUNNER + a `dev.ship` unit harness (Module 0 expansion) is the immediate infra unit before the next capability Module/Widget. Corrections complete (D-0043/44/46); capability expansion resumes per `MODULE_ROADMAP.md → Build priority`.

## Offload economics & phase (2026-07-27, D-0050)

- **Verify-cost offload rule.** Claude offloads a task to a local module ONLY when verifying the module's output is cheaper than Claude producing it itself. The DETERMINISTIC modules (fs/doc/image/audio/ocr/capture) have verify-cost ~0 and do what Claude cannot (touch this box) -> always offload; they are Claude's hands. The local-MODEL modules have HIGH verify-cost on current hardware, so Claude offloads only their MACHINE-checkable or cheaply HUMAN-checkable slices -- expanding their input contracts does NOT fix this (the ceiling is the model tier, not the interface). Quality is rarely why Claude delegates; LOCALITY and cheap BULK are.
- **Two audiences.** "Useful to the user" = a personal local-capability suite Nicholas drives himself (Widgets + generators + local models). "Useful to Claude" = offload (deterministic hands + a reliable spine + cheap-to-audit bulk). The generators are the USER track, not offload.
- **Phase.** NOW = a Claude-leads BRIDGE: Claude leads, minimizes its own tokens, offloads the cheap-to-verify parts, keeps local tasks NARROW / specialized. NORTH STAR (~2-3 yrs, on a 6090 / A100-class box): a local model strong enough to act autonomously, frontier only via API.
- **Spine = the AUDIT LOOP.** Crush verify-cost two ways: deterministic ground-truth gates + Nicholas as a human auditor (the Verification Console, Widget #3). See `MODULE_ROADMAP.md -> Build priority` and `DECISION_LOG.md` D-0050.

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

**Local coordination authority (D-0080, amends D-0051).** The orchestrator's hard "never drive another AI
session" boundary is SCOPED, not removed: the external / frontier fan-out stays human-couriered (D-0051/D-0052
intact; automated external-AI access stays out), but a future deterministic LOCAL coordinator IS authorized to
create fresh local logical contexts and invoke local models with no human courier -- the substrate for planner /
worker / reviewer roles sharing one resident model across disposable contexts.

## Long-horizon note (deliberately brief)

Life Orchestrator's own long-horizon aims may include a persistent structured memory, coordinated
local + remote model orchestration, and the progressive replacement of stochastic workflows with cheaper
deterministic tools where they earn it. **Per D-0080 the persistent structured memory + coordinated local orchestration are now NEAR-TERM (the Collective Agent); the full 27-49 real-time-perception spine + the 45-49 autonomic layer remain long-horizon.** The full destination — the
canonical 0-49 Module spine, the real-time autonomic control layer (45-49), and the 6-level operating
hierarchy — is mapped in `ARCHITECTURE_MAP.md` (a reference for orientation, **not** a build order).

Two things this project is explicitly **not**: the earlier assistant codebase in `LifeOrchestrator\repo`
(kept as reference material to fold in later, not a dependency now) and the separate **Project Proteus**
game (a systemic RPG with its own deterministic player-identity engine — no overlap with this project).
