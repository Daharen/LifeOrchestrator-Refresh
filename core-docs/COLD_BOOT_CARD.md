# COLD_BOOT_CARD -- Life Orchestrator (generator-INDEPENDENT recovery survivor)

Hand-maintained; NOT generated. Read this when the PCB packet is unavailable (read-only mount / mobile /
Project-mirror / generator down) -- Mode B of the START_HERE boot kernel. Bounded + fixed-slot: the only
fields that change per close are the mechanical stamps (`as_of`, doc COUNT, last-good SHA); no per-wave prose.

- **as_of:** i62 (authored in the i62 close; the live packet epoch is the i62 N7 map/generated commit). If your
  HEAD is past i62, the STAMPED slots (doc count, last-good SHA) may be stale -- identity / SoT / pinned /
  read-order slots do not. Active work is a redirect, so it is never stale here.
- **Identity:** a suite of small, independently-invokable LOCAL skills (backend `modules/`, human-interface
  `widgets/`) that frontier + local agents call to do real work on this Windows box, offloading token cost from
  the cloud. Phase (D-0080): building the Collective Agent on cognitive virtual memory. Manager: Nicholas.
- **Source of truth:** the on-disk repo `C:\Users\just_\LifeOrchestrator-Refresh` is CANONICAL. The Claude
  Project MIRRORS core-docs/ for desktop-less sessions. On any disagreement, DISK WINS.

## PINNED CONSTRAINTS -- 7 as of i61 (never-spill; safety-critical / irreversible -- carried inline so Mode B never drops them)

1. **P0-1 / action.authz ACTIVATION is PROHIBITED** -- the gate is a ratified DESIGN pass only;
   `non_execution:true` holds; retrieved memory is EVIDENCE, never an action grant (D-0118).
2. **NEVER `git add -A`.** All git writes go through the executor under the `git` lease; ship named files via
   `dev.ship` (fail-closed: sha256 + AST + tests); VERIFY the real HEAD with native git (D-0048 / D-0072).
3. **Lease order gpu -> git -> doc** (release in reverse); **<=1 GPU worker per wave (HARD)**; MaxParallel 3
   (D-0071).
4. **The orchestrator NEVER drives an external/frontier AI session** -- frontier material is human-couriered;
   in-session cloud subagents ARE permitted (D-0051 / D-0119).
5. **ANY UI change needs a HUMAN live-GUI confirm BEFORE it is called done** -- mock/API gates miss rendered-UI
   defects (D-0064).
6. **Persistent llama-servers launch DETACHED and are reaped before finalize; assert 0 UNMANAGED orphans every
   wave** (the wedge, D-0055 / D-0056).
7. **FROZEN (D-0080):** warm-pool durable-supervisor default-ON (D-0079 GATE-NO; classic detached-warm is the
   trusted default), generator upgrades, `video.interpret` + live composition, deep real-time perception,
   broad training.

## CANONICAL DOC LIST -- 23 core-docs as of i62 (count-asserted; == `ls core-docs/*.md`; machine-verified at close; N <= K_max=30)

- START_HERE.md -- the boot kernel (routing only)
- COLD_BOOT_CARD.md -- this generator-independent recovery survivor
- PROJECT_DIRECTION.md -- doctrine + long-term direction
- CURRENT_STATE.md -- reality NOW (phase, active work, box, tests, gotchas)
- FANOUT_ORCHESTRATOR_HANDOFF.md -- the one live orchestrator handoff + frontier
- DECISION_LOG.md -- append-only rationale (pull by ID)
- DECISION_LOG_INDEX.md -- one routing row per decision
- DOC_PROTOCOL.md -- the anti-bloat doc contract
- MODULE_ROADMAP.md -- build order / per-module status / follow-ons
- PROCESS_BACKLOG.md -- cross-cutting process / tooling backlog
- REVIEW_QUEUE.md -- producer/consumer queue schema
- ARCHITECTURE_MAP.md -- long-horizon spine (destination)
- TOOL_MODEL_REGISTRY.md -- tool / model / hardware registry
- SKILL_CONTRACT.md -- the skill interface (versioned)
- MODULE_WORK_ORDER_TEMPLATE.md -- work-order template
- MEMORY_ARCHITECTURE.md -- long-horizon memory design (doctrine)
- MEMORY_CONTRACT.md -- Collective Agent memory/retrieval contract
- MEMORY_BENCHMARK.md -- memory-quality + foreign-corpus validation
- CONTEXT_PACKET_CONTRACT.md -- context-packet + selection contract
- ACTION_AUTHORIZATION_CONTRACT.md -- the P0-1 gate freeze (versioned)
- ADAPTIVE_RESOURCE_GOVERNOR.md -- governor design + measured truth
- AUDIT_PIPELINE.md -- the human-in-the-loop audit + interpretability program
- SEALED_CHECK_47.md -- sealed metastability predicates (evaluate i>=54)

## ACTIVE WORK + FRONTIER -- frozen redirect (not summarized here)

Owned by `CURRENT_STATE.md -> Phase + active work` and the PCB packet OVERLAY (`modules/44-project-map/generated/
BOOT_PACKET.md -> OVERLAY`). Read the owner for the live frontier; this card does not restate it.

## LAST-GOOD CLOSE -- `6ec0b20` (i61 FINAL close fold, D-0160; 0-stale on boot_read)

A known-good commit to verify/checkout against. (The card trails the packet by one commit: this updates to the
i61 packet-commit SHA at the i62 close.)

## GENERATOR-FREE RAW READ ORDER (when no packet is available)

`PROJECT_DIRECTION.md` -> `CURRENT_STATE.md` -> `FANOUT_ORCHESTRATOR_HANDOFF.md` -> `DECISION_LOG_INDEX.md` (read
the index, then pull individual `D-00NN` entries from `DECISION_LOG.md` by ID -- never whole-ingest the log).
