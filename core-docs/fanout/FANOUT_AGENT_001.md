# FANOUT_AGENT_001 -- PB-7 knowledge-surface re-layer (DESIGN-FIRST) -- READY

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i55 (plan id `fo-55-<id>` once planned; may run orchestrator-inline with cloud subagents, D-0119)
- **Lane:** CODING/DESIGN (no GPU)
- **Worker id / label:** PB7-relayer-design
- **Module/area (exclusive):** the PB-7 program design (no build this wave)
- **GPU:** false
- **Docs:** `[]` (worker reports; the orchestrator mirrors core-docs)
- **Recommended model:** Opus 4.8 Extra (design-vs-closure + core-retrieval semantics)

## Mission

Design the **knowledge-surface re-layer** (D-0141 / PB-7) -- the token-endurance spine and the system-wide analogue of collapsible memory. As the project grows, cumulative documents grow without bound; the goal is a DECOUPLING: total stored knowledge may grow arbitrarily while the WORKING (hot) surface a session must read stays BOUNDED. The i53 canon (F-i53-eff: prefer `section:`/`card:` over whole-doc opens) steers retrieval BEHAVIOR; PB-7 shrinks WHAT there is to retrieve. (Live symptom: the handoff + CURRENT_STATE sit pinned at their caps -- every close is a byte-squeeze.)

## Unit (design-first -> red-team-gated; DO NOT build the re-layer this wave)

Author a **design doc** (`core-docs/research/2026-08-<dd>-pb7-relayer-design.md`; research budget 10 KB each -- split into 2 digests if needed) specifying bounded-hot + indexed-cold for the cumulative surfaces:
- **Targets:** `DECISION_LOG.md` (~640 KB, append-only), `CURRENT_STATE.md` (34 KB cap), `DECISION_LOG_INDEX.md` (growth-exempt router, ~22 KB); and how the TWO built engines participate -- the PCB #44 (HORIZONTAL bootstrap-doc axis) + the memory subsystem #35-43 / #36 artifact.search FTS5 / #40 context.compile / MEMORY_ARCHITECTURE (VERTICAL registries). NOT a parallel arch; prefer the shared catalog over per-class routers.
- **Specify:** what stays HOT (a bounded always-loaded view), what moves COLD (typed-indexed, retrieved on demand via `section:`/`card:`/FTS), the promotion/demotion rule, how currency holds (the N7 close-refold restamps the map), and the read path (hot first, cold on anomaly -- the AUDIT_PIPELINE / MEMORY_ARCHITECTURE funnel). PB-6 (decision re-layer) = the FIRST increment.
- **Asymptotic requirement (D-0141):** neither bytes-per-doc NOR docs-per-task scales linearly with total knowledge. Bound, don't degrade -- a cumulative surface RE-LAYERS, it is never merely compressed; genuinely read-whole artifacts still slim.
- **Guardrails:** no loss of history (git + archive + the lossless ledger remain complete); the doc-commit-gate + budgets survive; P0-1 activation stays FROZEN.
- **Gate:** design-first -> red-team (a #31 frontier-couriered pack OR an in-session cloud-subagent adversary, D-0119) that tries to BREAK the decoupling claim (a query the hot view cannot answer without a whole-doc open; a currency hole; an unbounded-growth path). Output findings + a proposed FIRST build increment (one scoped unit).

## Rails (standing)
- Boot from the PCB `modules/44-project-map/generated/BOOT_PACKET.md` (step-0 verify / query stale); read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Prefer bounded `section:`/`card:`/`--q` fetches over whole-doc opens; charged retrieval bytes are the cost (D-0146 F-i53-eff).
- Do ONE unit; `docs:[]`; report via `-Action report -State done` (negative results first-class -- say plainly if the re-layer is not yet worth building and why).

## Inputs to read
`core-docs/PROCESS_BACKLOG.md` (PB-7 + PB-6 rows), `DECISION_LOG.md` D-0141 (+ D-0139/D-0134), `core-docs/research/2026-08-12-knowledge-surface-relayer-program.md` (the target-arch register), `MEMORY_ARCHITECTURE.md` (the adopt-full-design/build-by-evidence template + T0-T3), `AUDIT_PIPELINE.md` s0/s3 (the same bounded-audit decoupling), `modules/44-project-map/` (the PCB as the existing bounded-hot instrument).

## Verification / report-back
A design doc sufficient for a future builder to implement WITHOUT these chats; an explicit decoupling claim + the red-team's attempt to break it; a proposed first build increment (one scoped unit). Report-back record (orchestrator fills from `plans/<id>/reports/` before archiving).
