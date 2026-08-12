# KNOWLEDGE SURFACE RE-LAYER PROGRAM (deferred; governing rule D-0141)

**Status: RECORDED deferred-work program (Nicholas directive 2026-08-12; D-0141). Not built now.** This
generalizes the D-0139 DECISION_LOG_INDEX correction into a project-wide rule and consolidates all
cumulative-surface re-layering into ONE program (subsuming PB-6). Router row: PROCESS_BACKLOG PB-7.

## 0. Governing invariant

When legitimate information growth collides with a hot-context cap, **preserve the information, index and
re-layer the representation, and bound what is activated -- never make permanent semantic degradation the
scaling mechanism.** A static cap is an early-warning + enforcement mechanism that should increasingly
function as a **re-layer trigger**, not a permanent demand that ever-growing information occupy the same
bytes forever. This does NOT globally remove budgets: most hot docs stay bounded (budgets catch accidental
bloat); the exception is an information class that is *inherently cumulative* or shows sustained legitimate
growth.

## 1. Cap-pressure as a re-layer signal

Evidence a surface may need re-layering (any of): repeated slimming solely to admit new valid information;
compression of old-but-useful routing descriptions already within local density; a doc chronically near
its cap; growing opaque shorthand to stay under a cap; removal of useful distinctions merely because
aggregate size rose; repeated archiving without a retrieval path back; a growing NUMBER of individually
bounded docs that must all be read together; a router/index whose own size scales with the corpus;
bootstrap/orientation cost rising because new doc objects were added. A single verbose edit is hygiene;
*persistent* legitimate growth is an architectural scaling event.

**i50 is a live instance:** the handoff (an iteration ledger) sat at 99% and admitting the D-0140 lines
forced collapsing i38/i39 ledger rows -- "repeated slimming to admit valid information," the exact signal.

## 2. Two axes + the asymptotic requirement

- **Vertical:** one doc/index grows indefinitely -> shard/index it, retrieve relevant portions.
- **Horizontal:** the NUMBER of acceptable docs/indexes/catalogs grows until an ordinary task must open
  them all -> index and route across the collection itself.

**Requirement:** neither the bytes examined from one doc object NOR the number of doc objects examined by
an ordinary task may scale linearly with total project knowledge. "Give it an index" means give the class a
queryable routing representation *inside the memory hierarchy* -- an index-of-indexes / bounded-fanout
hierarchy -- NOT another mandatory Markdown router the model itself must open.

## 3. Target architecture per cumulative class

A. **Lossless canonical backing** -- complete underlying info retained without destructive compression;
nothing important lives only in the shortened hot view. B. **Indexed representation** -- structured/typed
records with enough semantics to route intelligently and expand to source; prefer the existing
memory/retrieval substrate over a new Markdown file. C. **Bounded hot view** -- the read-whole artifact
becomes a small current-state/router carrying only near-universally-useful material + pointers into the
index. D. **Selective retrieval** -- tasks receive only their relevant subset, routed by typed signals
(identity, module/component, architectural domain, currentness, supersession, lifecycle, lexical,
vector/semantic, graph, temporal, failure-history, authority, prior-usage). E. **Expansion path** -- every
condensed record stays expandable to the complete authority/evidence; compression changes activation cost,
not evidentiary retention.

**Cold history + patterns:** superseded/folded/closed records go COLD (excluded from routine current-state
retrieval, reachable via explicit history / supersession-traversal / diagnosis / regression / precedent
queries), not deleted. Preserve a path to promote recurring cross-history patterns (A->B->A architecture
oscillation; a failure recurring after many iterations; repeated reopening of a settled choice; recurring
cost/reliability tradeoffs; procedural regressions) into provenance-linked failure/reflective/procedural
memories surfaced on relevance -- without loading the whole history.

## 4. Two engines already being built (reuse, don't fork)

- **Horizontal axis -> the PCB (#44 `project.map`).** BOOT_PACKET = the bounded-hot boot view; `map/` +
  `claims/` + the L2 narrative queries (N1/N3) = the indexed representation; selective retrieval = the
  query surface. The core-doc SET / bootstrap surface re-layers HERE. (Active; the legacy-vs-PCB gate,
  D-0140, is the migration path.)
- **Vertical axis -> the memory subsystem (#35-43) + M2-C + `MEMORY_ARCHITECTURE` (T0-T3).** Typed records
  (#38 repo.intel, #36 artifact.search catalog), query-aware selective retrieval (#37 selpol, #40
  context.compiler), bounded hot sets + bounded-fanout hierarchy (Tier-1), supersession-aware records.
  Cumulative registries (decisions, contracts, module/tool catalogs, research, failures) re-layer HERE via
  the M2-C "docs-into-memory" re-layer.

The program is the ROUTING of each class to one of these engines + the typed schema per class. It does NOT
authorize a parallel architecture, and it prefers the shared generic catalog over per-class bespoke routers.

## 5. Surface register (cumulative classes under pressure -- first pass)

Fields per row: current rep · cap/status · growth evidence · authoritative backing · intended indexed form
· intended bounded-hot replacement · candidate retrieval metadata · engine · trigger. Terse; detail rides
each increment's design.

| class | current rep (usage) | backing | intended indexed form | bounded-hot replacement | key retrieval signals | engine |
|---|---|---|---|---|---|---|
| Decision routing/history | DECISION_LOG_INDEX (growth-exempt) + DECISION_LOG 615 KB | DECISION_LOG.md (lossless) | selective decision index-of-index (M2-C records) | compiled task-relevant decision set | module/plane/status/type/authority/lexical/vector/graph/temporal/supersession | memory (PB-6) |
| Bootstrap doc SET / orientation | 22 core-docs (many 90-118%) + START_HERE + handoff | the core-docs themselves | PCB map + L2 queries | BOOT_PACKET | plane/component/currency/pointer | PCB #44 |
| Iteration/history ledger | handoff s3 (99%) + archive/handoffs (40) | archive/handoffs + git + D-entries | episodic/iteration records | last-N window + pointer | iteration/date/module/outcome | memory (#39 episode) |
| Module/capability catalog | MODULE_ROADMAP (85%) + per-module docs | module docs + skill.json | typed module records | roster + pointer | module/status/capability/domain | memory / PCB |
| Tool/model/hardware registry | TOOL_MODEL_REGISTRY (95%) + models.json | models.json + registry | typed tool/model records | lookup view | tool/model/tier/hardware | memory / PCB |
| Contracts / arch inventories | MEMORY/CPC/ACTION/SKILL contracts (89-94%), MEMORY_ARCHITECTURE (100%), ARCHITECTURE_MAP (109%) | versioned contracts | clause-level typed records | contract current-view + pointer | contract/version/clause/component/supersession | memory (M2-C) |
| Research catalog | 37 research/*.md (no router) | the digests | indexed research records | (none needed hot) | topic/date/module/question/vector | memory |
| Failure history | CURRENT_STATE "Known failures" + gotcha corpus | CURRENT_STATE + D-entries | typed failure records + recurrence links | load-bearing gotcha window | component/symptom/recurrence/authority | memory (patterns) |
| Archive / provenance indexes | ARCHIVE_INDEX + archive/* (120 files) | archive/ + git | cold provenance index | (cold only) | path/why/date/D-ref/supersession | memory / PCB |

## 6. Acceptance principle (a re-layer is done when, NOT "the doc got smaller")

Complete information stays recoverable; routine tasks examine only a bounded relevant subset; adding large
irrelevant history does NOT materially raise routine context cost; adding many new doc objects does NOT
materially raise routine orientation cost; relevant cold info stays discoverable; provenance permits
expansion to authority; and NO progressively harsher compression is required as total knowledge grows.

## 7. Sequencing (non-displacing)

Per the directive item 10: this does not derail the active PCB/bootstrap-consolidation sequence. Immediate
scope = (1) stop destructive over-compression on outgrown surfaces (D-0141 + the DOC_PROTOCOL rule); (2)
this register identifies the pressured surfaces; (3) PB-7 records the eventual conversions; (4) active
bootstrap/memory work continues; (5) increments land coherently on the shared memory + PCB architecture.
First increment = PB-6 (decisions). The PCB gate (D-0140) is the horizontal-axis migration already in
flight. Each increment is design-first -> red-team, NON-DISPLACING (gate ratification + core memory
sequencing outrank it). Superseded predecessors here: PB-3's ">40 KB -> re-layer plan" clause and PB-6 are
absorbed into PB-7.
