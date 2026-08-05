# MEMORY_ARCHITECTURE -- the Collective Agent long-horizon memory design (governing, versioned)

Owns the **target memory architecture** for the Collective Agent: the structure that lets stored knowledge grow
for an effectively indefinite operating life while the working context compiled for an ordinary task stays
bounded. This is the north-star design (stable doctrine, like `ARCHITECTURE_MAP.md`), not an iteration ledger.
It is adopted as the DESIGN TARGET (D-0090); implementation is staged by evidence (section 10). The two existing
memory contracts are subordinate to this doc and remain the authoritative field-level specs:
`MEMORY_CONTRACT.md` (record + provenance + embedding + retriever) and `CONTEXT_PACKET_CONTRACT.md` (selection +
packet). The point-in-time gap analysis is `research/2026-08-03-memory-architecture-seam-audit.md`; the
validation design is `MEMORY_BENCHMARK.md`. Rationale thread: D-0080 (the Collective Agent pivot), D-0050 (the
offload/verify-cost doctrine), and the 2026-08 frontier memory-architecture review folded here.

## 0. What "functionally limitless" formally means

No finite system answers an arbitrary question about an arbitrarily large history in constant time. The goal is
therefore not constant cost for every query; it is a **decoupling**: total stored memory may grow without bound
while the material examined for an ordinary task stays bounded, and only explicitly-global questions pay a
larger, deliberate traversal cost. The architecture is "functionally limitless" when these hold:

- routine queries cost approximately the same whether the corpus holds 10^4 or 10^7 memories;
- global questions enter an explicit slower path (section 5), not a silent blowup;
- every compressed representation expands back toward its evidence (section 8);
- no summary, embedding, or model inference is the only remaining copy of anything important (section 2).

The ceiling we keep hitting -- index bloat, ever-harsher hot-doc compression -- is the symptom of a system whose
examined-per-task cost scales with corpus size. The cure is structural (bounded hot set + bounded-fanout
hierarchy + a slow path), not a bigger budget. This doc specifies that structure.

## 1. The load-bearing principle: deterministic skeleton, provisional model content, lossless substrate

The single design rule that makes an intelligent memory also a robust one on this hardware:

- **The skeleton is deterministic.** Identities, versions, edges, node structure, hierarchy splits, namespaces,
  routing, budgets, tier assignment, staleness/supersession propagation, index maintenance -- all produced by
  deterministic code, never by the model. This is what keeps the system auditable, reproducible, and cheap.
- **The content may be model-generated, but is always provisional and validated.** Synopses, extracted claims,
  reflections, proposed procedures, ambiguity resolutions -- the 9B produces these, but they are stored as
  **versioned derived views** that (a) resolve back to deterministic source records and (b) are gated by a
  deterministic validator (section 8, `MEMORY_BENCHMARK.md`) before anything trusts them. A bad model pass can
  only emit a view that fails validation and is discarded or regenerated; it can never corrupt the substrate.
- **The substrate is lossless.** Every original artifact, message, decision, execution trace, result, and
  document version is retained. Everything above it -- summaries, embeddings, graphs, extracted claims,
  hierarchies -- is a **rebuildable materialized view**. Compression may fail without memory being lost.

This is why the system can keep adding capability without deterioration and be re-run every sweep without cost
anxiety: the expensive, risky, non-deterministic work is always provisional over an evidence base that cannot be
damaged. It is also the reconciliation of "intelligent" (model in the loop) with "deterministic and robust"
(Nicholas's constraint) and "always provisional" (safe to re-run).

## 2. Authorities -- what is canonical vs derived

Two authority axes, kept strictly separate (the second is inherited from `CONTEXT_PACKET_CONTRACT.md` P0-1):

- **Evidentiary authority (canonical vs derived).** CANONICAL: the immutable substrate -- source files/versions,
  raw events, execution traces, the append-only decision ledger, retained originals of ingested foreign
  material. DERIVED (rebuildable, versioned, never the sole copy): records extracted from sources, embeddings,
  lexical/graph/temporal indexes, hierarchy nodes + synopses, claims, reflections, consolidated procedures,
  rankings. Rule: a consolidation process MAY retire or replace a derived view; it may NOT destroy the evidence
  the view was built from.
- **Execution authority (control plane vs evidence).** Retrieved memory is EVIDENCE (`content_role=evidence`,
  `can_instruct=false`); it never grants permission, sets a side-effect policy, or defines a completion
  contract. Only the coordinator/user-authority store populates the control plane. Epistemic authority (how much
  to trust a claim) is not execution authority (permission to act). This is already frozen in
  `CONTEXT_PACKET_CONTRACT.md` s1 and is a hard gate before any action-capable use.

## 3. The layer stack

From the immutable bottom to the temporary working set at the top. Each layer's output is the next layer's input;
each derived layer is rebuildable from the one below it.

1. **Canonical substrate (immutable, lossless).** Source files + versions (content-addressed), raw event/trace
   records, the append-only decision ledger, retained originals of ingested corpora. Stable IDs, content hashes,
   version IDs, source spans, timestamps, parent/derivation references, append-only where practical.
2. **Identity + versioning.** Stable `record_id` / `record_version_id` / `source_version_id`; content hashes
   split by role (`record_content_hash` / `source_content_hash` / `excerpt_hash`, per `MEMORY_CONTRACT` A2);
   monotonic version chains; supersession/derivation edges.
3. **Typed records.** One record ENVELOPE, many `record_kind`s with per-kind ingestion/retention/validity/
   promotion semantics (section 4). Chunks are one kind via a view -- not the universal abstraction.
4. **Relationships (edges).** `derives_from`, `supersedes`, `contradicts`, `has_stage`, `describes_*`,
   `depends_on`, `member_of_node`, temporal-adjacency. Edges are first-class and carry provenance.
5. **Indexes (multiple, orthogonal).** Exact-ID, lexical FTS, dense-vector, entity/relationship graph, temporal,
   type/status filters, authority/provenance filters, code-symbol/module indexes, prior-use/success statistics
   (section 5). Each is a rebuildable view; none is THE architecture.
6. **Bounded-fanout hierarchy (index of indexes).** A semantic tree/DAG whose internal nodes hold a synopsis +
   bounded child list + time/authority ranges + key entities + child IDs + counts + lexical descriptors + an
   embedding + synopsis provenance. Depth grows, not the hot surface. Nodes split at max fanout (section 6). The
   root never accumulates a thousand children.
7. **Retrieval (query-type-aware, fast + slow).** A retrieval PLANNER classifies the information need and routes
   across channels + hierarchy + graph, fusing deterministically (section 5).
8. **Context compilation (bounded working set).** The deterministic compiler (`CONTEXT_PACKET_CONTRACT.md`)
   assembles the three-region packet with disposition, consumer profile, exact transport accounting,
   omission manifest, identity/lineage, and an expansion seam. The packet is the ONLY thing the model's context
   holds -- the activation layer, not "the memory".
9. **Consolidation + memory formation.** Deterministic triggers promote raw events -> episodes -> claims/
   synopses/failure-patterns -> procedures/skills, each as a NEW derived memory with lineage (section 6).
10. **Procedural / skill layer.** Verified repeatable behavior becomes an executable module/skill with
    activation conditions -- durable learning without weight training (section 6).
11. **Intake + interpretation (the write side for foreign material).** Converts heterogeneous external corpora
    into the substrate + derived layers while retaining originals (section 7).

## 4. Memory types

"Memory" is not one universal class with proliferating optional fields. Distinguish kinds, each with different
ingestion rules, retrieval scoring, retention policy, validity semantics, promotion criteria, and rendering:

- **episodic** -- what happened during a specific execution/period (retains temporal context; #39 episode.record
  is the seed).
- **semantic** -- claims believed generally true, independent of one episode (consolidated; section 6).
- **procedural** -- how to accomplish something; promotes to an executable skill when verified.
- **decision** -- authoritative choices + governing constraints (the decision ledger; supersession-aware).
- **failure** -- recognized failure patterns + recovery methods (#39 failure schema is the seed).
- **skill** -- executable capabilities + activation conditions (#38 structural skill records; #41 activation
  cards are `summary` derivatives).
- **reflective** -- higher-order conclusions derived from multiple records (model-generated, provisional).
- **working** -- temporary per-task state that survives across the iterative turns of ONE task; keyed by
  `task_id`; demoted/archived at task close. Distinct from long-term storage and from the packet.

Design rule: adopt the typing PRINCIPLE (per-kind semantics), not necessarily eight rigid subsystems. Most kinds
ride the shared envelope via `record_kind` + `namespace` + edges; only working memory (ephemeral, task-scoped)
and reflective memory (provisional, multi-source) need care that they are not forced into the stored-record mold
prematurely. A successful trace is not forever only a trace: it may yield an episode, extracted claims, a
recognized pattern, a proposed procedure, and eventually a verified skill or governing rule. That is how new
memories form -- rather than the system merely accumulating more documents.

## 5. Retrieval architecture -- planner, channels, fast + slow paths

Embeddings are ONE access path, not the architecture. Dense vectors do not reliably encode identity, negation,
supersession, temporal validity, authority, contradiction, causality, or procedural preconditions; those need
symbolic fields or graph edges.

**Channels (independent, compensating):** exact-ID/reference; lexical FTS; dense-vector similarity; entity/
relationship graph expansion; temporal partitions; type/status filters; authority/currentness filters; code-
symbol/module indexes; prior-use/success statistics.

**The retrieval PLANNER classifies the need first,** then routes:
- exact reference -> ID/symbol lookup;
- current-state question -> current-doctrine + authoritative records, current-only filter;
- historical reconstruction -> supersession/derivation edges traversed backward;
- temporal change -> temporal partitions + episode synopses;
- local factual -> lexical + vector candidates, shallow;
- global synthesis/overview -> high-level hierarchy node synopses first, descend only relevant branches;
- causal/diagnosis -> episodes + failures + relevant decisions + source traces;
- procedure selection -> skill/procedure index + activation-condition match + health;
- precedent search -> episodic + decision + prior-use statistics.

**Pipeline (fast path, deterministic + cheap):** hard eligibility filters (namespace/forbidden/privacy/deleted)
-> lexical + vector + temporal candidates -> graph expansion -> authority/currentness filtering -> deterministic
fusion + diversity selection (`selpol_rrf_v1`) -> evidence budgeting -> packet. No single channel must be perfect;
the others cover its failure modes.

**The slow path (explicit, uncertainty-triggered):** expand neighboring records -> descend another hierarchy
level -> traverse graph edges -> inspect original files -> launch parallel evidence-gathering contexts (the
disposable subagents / baton artifacts -- page-fault handlers, not memory) -> global map-reduce -> abstain or
request authority. Global questions are IDENTIFIED and ALLOWED to cost more; a flat top-k call is never expected
to serve all query types. A large external evidence-gathering path (file-based search) is retained even though it
is slower than the vector index, because for genuinely global questions it is more correct.

## 6. Consolidation, hierarchy maintenance, and procedural promotion

**Memory-formation pipeline (each step a NEW derived memory with lineage, never a destructive replacement):**
raw event -> episode -> entities + claims -> linked relationships -> reflection / cluster synopsis -> procedure
candidate -> verified procedure or skill.

**Deterministic consolidation triggers:** enough related episodes accumulate; repeated successes share a method;
several failures share a signature; a topic node exceeds its record/token budget; contradictory claims appear; an
often-retrieved cluster lacks an adequate synopsis. The trigger is deterministic; the synthesis it schedules may
use the model, but its output is provisional + validated.

**Hierarchy maintenance (the part that actually bites -- keep it deterministic):** a node splits when it exceeds
max fanout (structure is code, not model judgement). A changed leaf marks its ancestor-path synopses STALE (reuse
the `currentness` enum); stale synopses are regenerated LAZILY on next access and served stale-but-provenance-
intact until regenerated. Local update rule: a new record normally changes one leaf, a bounded ancestry path, and
the relevant secondary indexes -- never a global rebuild. Synopsis staleness propagation is the single most
important loop to get right; it is where a tree rots into inconsistency if the model, not deterministic code,
owns invalidation.

**Procedural promotion (the durable-learning path):** a verified procedure carries activation conditions,
preconditions, required tools, ordered/partial steps, expected outputs, invariants, failure modes, recovery
branches, verification tests, and provenance from the successful episodes. When stable + verified it becomes an
executable module/skill. This is far more deterministic than hoping the 9B "remembers how" in prose, and it is
how the SAME model becomes more capable: more verified procedures + better routing + better retrieval + better
compilation. External retrieval lets a smaller model use a datastore far beyond its parametric capacity; weight
training is reserved for stable, high-frequency patterns (section 12), never changing facts or project state.

## 7. Intake + interpretation -- foreign-corpus absorption as a core capability

The canonical formats are INTERNAL PRODUCTS of memory formation. They must not be prerequisites imposed on
incoming information. The system must be able to ingest substantial corpora built by other people that were never
shaped for our schemas -- source code, docs, issues/discussions, decisions, informal notes, obsolete versions,
conflicting explanations, duplicates, inconsistent terminology, config, tests, structured and unstructured
formats -- and construct its own view of them.

**The intake side is a first-class subsystem** (a write/interpretation counterpart to retrieval). It:
- retains the ORIGINAL material losslessly (substrate) before any interpretation;
- discovers corpus/project boundaries, namespaces, entities, memory types, hierarchies, temporal + supersession
  relationships, claims, synopses, procedures, indexes, and provenance links;
- emits all of the above as DERIVED, versioned, provenance-linked views over the retained originals;
- is deterministic where structure allows (file inventory, hashing, chunking, symbol extraction, dedup, version
  chaining) and model-assisted only where judgement is required (boundary/entity/type inference, claim
  extraction, synopsis) -- with model output provisional + validated.

Intake produces the same substrate + derived layers as internal memory formation; nothing downstream needs to
know whether a record originated from our own operation or from a foreign corpus. This is what lets the assistant
take on a new external project: it absorbs the project's material into bounded, navigable, reconstructable memory
rather than depending on a human to pre-structure it.

## 8. Reconstructability model

Every substantive derived memory expands through intermediate records back to retained source evidence:

- a hierarchy node synopsis -> its child nodes -> leaf records -> source spans/versions;
- a consolidated procedure -> the episodes/claims it was promoted from -> the traces + sources;
- a claim -> `supported_by` / `derived_from` records -> sources; a supersession -> both the current and the
  superseded record, both retained;
- a packet excerpt -> `record_version_id` + provenance mode (`direct_span` reproduces bytes; `derived_record`
  validates `derivation_refs` + `record_content_hash`; `aggregate` lists constituents; `tombstone` carries
  deletion provenance).

Invariants: no derived view outranks its sources merely because it is concise; a provenance failure on any
packet-carried item forces `packet_disposition = provenance_failed`; a summary that cannot expand to evidence is
invalid. "Reconstruction impossible from remaining evidence" is a first-class, correctly-abstaining answer -- not
an invitation to invent.

## 9. Tier-0 architectural invariants + extension seams (non-negotiable, verify now)

These are the properties that CREATE the headroom. They are design-now: the substrate must satisfy them or admit
them additively, regardless of which higher capability is built later.

1. **Bounded hot set** -- startup + ordinary task packets have fixed budgets independent of corpus size.
2. **Bounded fanout** -- no navigation node accumulates unlimited children; it splits when full.
3. **Lossless substrate** -- every derived memory resolves to retained source evidence.
4. **Replaceable derivatives** -- embeddings, summaries, graphs, rankings, hierarchies are versioned + rebuildable.
5. **Local updates** -- a new record normally changes one leaf, a bounded ancestry path, and relevant secondary
   indexes; never a global rebuild.
6. **Explicit slow path** -- corpus-wide questions are identified and allowed to cost more.
7. **Typed validity** -- current / stale / superseded / contradicted / hypothetical / historical are explicit,
   machine-readable states, not prose.
8. **Promotion through evidence** -- episodes become claims/reflections/procedures/skills only through defined
   gates; nothing self-certifies.
9. **Measured retrieval** -- recall, precision, temporal correctness, provenance fidelity, contradiction
   handling, cross-project isolation, abstention, and token/latency cost are continuously tested
   (`MEMORY_BENCHMARK.md`).
10. **No hidden authority** -- model-generated summaries/reflections never outrank sources; evidence never grants
    execution authority.

**Extension seams the present contracts MUST preserve** (foreclosing any of these is the urgent failure): a
`namespace` that is ENFORCED as a hard retrieval boundary; a `record_kind` set that is additively extensible; a
catalog schema that admits a hierarchy/node layer + node-membership edges WITHOUT a rewrite; a retriever
interface whose CHANNEL set is open (graph/temporal/statistics added additively, not hard-coded to
lexical+vector); provenance/derivation lineage on every derived record; a working-memory store keyed by
`task_id`; and consolidation outputs that always carry `derives_from` back to source. The seam audit
(`research/2026-08-03-memory-architecture-seam-audit.md`) classifies each against today's implementation.

## 10. Tiered roadmap -- design now, build by evidence

Adopt the FULL architecture as the design target now. "Build by evidence" does NOT mean waiting until a real
project visibly deteriorates -- it means building the foreseeable anti-deterioration foundation BEFORE relying on
the assistant for substantial autonomous external work, and reserving only genuinely scale-dependent or
empirically-uncertain implementations for later activation. Each tier states prerequisites, deliverables,
acceptance gates, activation thresholds, migration, rollback, and what stays deliberately unimplemented.

### Tier 0 -- Architectural invariants + extension seams (DESIGN NOW; verify + repair immediately)
- **Prerequisites:** the shipped substrate (#36/#37/#38/#39/#40/#41), `MEMORY_CONTRACT`, `CONTEXT_PACKET_CONTRACT`.
- **Deliverables:** verify + (where needed) amend the contracts so all section-9 invariants + seams hold: lossless
  substrate; stable identities/versions; enforced namespaces; extensible typed records + edges; provenance +
  derivation lineage; currentness + supersession as machine-readable states; schema evolution; rebuildable
  derived views; bounded packets; expansion-to-source; additive support for future types/indexes/consolidation/
  retrieval. The seam audit's "foreclosed" + "expensive-later" items are Tier-0 repairs.
- **Acceptance gate:** a written seam audit with every intended layer classified; every "foreclosed" item either
  repaired or converted to a costed additive amendment with a migration path; a contract test proving namespace
  isolation + schema-evolution + provenance-expansion on a fixture.
- **Activation:** immediate (this planning pass opens it).
- **Migration/rollback:** contract amendments follow the existing amendment protocol (a D-entry + per-module
  SCHEMA_NOTES + the D-0077 cross-module smoke); each is additive + backward-compatible or ships with an in-place
  migration + a rollback flag.
- **Deliberately unimplemented:** no new runtime capability -- Tier 0 is contracts + seams only.

### Tier 1 -- Immediate anti-deterioration foundation (BUILD NOW, before substantial production dependence)
- **STATUS (i34; D-0098 contract + D-0099 close; HEAD `ad20fa6`) -- core layers BUILT, acceptance pending:** the bounded-fanout HIERARCHY navigation layer is BUILT -- #36 artifact.search 0.5.0 (`356ab64`; the node layer + member_of_node/child_of_node edges + shortlist/descend + a safe-pruning no-false-negative presence_filter + schema 4->5 where zero nodes = today's flat behavior), #40 context.compile 0.6.0 (`3968c96`; the shortlist-and-descend PLAN + SAFE-PRUNING enforcement + retrieval_completeness + navigation-vs-evidence closure), #37 retrieval.eval eval 0.6.0 (`ad20fa6`; navigation-cost + dual-recall hierarchy eval, ADDITIVE); the D-0077 hierarchy fold smoke PASSED 38/38 on a real multi-namespace tree (the SAFE-PRUNING invariant holds end-to-end). The per-task WORKING-MEMORY STORE is BUILT -- #42 working.memory 0.1.0 (`601a2db`; immutable versioned snapshots + CAS + exactly-one active head + fork/close/archive/promote + task_id+namespace isolation), realizing MEMORY_CONTRACT A5 U3'. **Tier-1 ACCEPTANCE is NOT yet claimed:** the acceptance gate below (bounded context cost across >=2 orders of magnitude on a FOREIGN corpus) is exercised by a ~200MB real-corpus rehearsal that is scaffolded + FLAGGED OPEN by #37 (tier1_accepted=false on synthetic-only) -- it is the pre-activation gate. Consumer WIRING is deferred to i35: ship the real hierarchy_port into #40's `-Retriever artifact_search` CLI (today FLAT-only; the plan is proven only via an injected port); wire #40's packet working_memory region to #42's get_active_head (today rendered "reserved; empty"); the multi-channel query ROUTER (query_class still a stub). The remaining Tier-1 deliverables below stay design-intent.
- **Prerequisites:** Tier 0 gate passed.
- **Deliverables:** enforced project isolation (hard namespace boundary in retrieval + packets); current-over-
  stale retrieval discipline (a real current-only default + supersession-aware ranking, not only a soft demote);
  working-memory boundaries (per-`task_id` state store, promote/demote, never leaked into evidence authority);
  basic memory typing (per-kind ingestion/retention/validity honored end-to-end); bounded hierarchical navigation
  (the node layer + shortlist-and-descend retrieval); query classification + query-aware retrieval routing;
  reconstruction + provenance validation surfaced as gates; the memory-quality benchmark v1 (`MEMORY_BENCHMARK.md`
  Tiers 1-2 measures); initial episode->stable-derived consolidation.
- **Acceptance gate:** the benchmark shows bounded context cost as corpus size grows across >=2 orders of
  magnitude on a foreign corpus; cross-project contamination below threshold; current-vs-historical correctness
  above threshold; every packet excerpt reconstructs to source; navigation cost sub-linear in leaf count.
- **Activation:** before onboarding the first substantial external project.
- **Migration/rollback:** each capability ships behind a flag with the prior flat path reproducible; the hierarchy
  is a rebuildable derived view (drop + rebuild is always available).
- **Deliberately unimplemented:** full claim engine, procedural auto-promotion, global map-reduce.

### Tier 2 -- Operational memory formation (BUILD as sustained workloads begin)
- **Prerequisites:** Tier 1 gate passed + >=1 real external workload running.
- **Deliverables:** claim + relationship extraction; semantic-memory formation; failure-pattern consolidation;
  repeated-success-to-procedure promotion + procedure verification; automatic synopsis regeneration; hot/warm/
  cold movement; automatic hierarchy splitting; richer contradiction + temporal handling; learning from real-task
  outcomes.
- **Acceptance gate:** procedures promoted from real successes pass external verification; consolidation reduces
  working-set cost without provenance loss; contradiction + temporal measures improve on the benchmark; no
  derived view becomes a sole copy.
- **Activation thresholds:** driven by measured triggers (episode volume per topic; repeated-success counts;
  failure-signature recurrence; node budget breaches; retrieved-cluster-without-synopsis rate).
- **Migration/rollback:** consolidation is provisional + rebuildable; a bad consolidation policy is reverted by
  dropping its derived views and re-running.
- **Deliberately unimplemented:** full bitemporal claims; large-scale graph propagation; specialist training.

### Tier 3 -- Advanced scale mechanisms (ACTIVATE when measured scale warrants)
- **Prerequisites:** Tier 2 stable + benchmark evidence that a scale mechanism is needed.
- **Deliverables:** full bitemporal claim management (valid-time + record-time); global recursive / map-reduce
  traversal; large-scale graph propagation (multi-hop associative retrieval); parallel corpus analysis; advanced
  cross-domain synthesis; specialist training derived from stable, repeatedly-validated procedures.
- **Acceptance gate:** each mechanism justified by a benchmark curve showing the cheaper tier has hit its
  measured limit; the mechanism improves the relevant curve without violating a section-9 invariant.
- **Activation thresholds:** corpus size / query-globality / graph-density / update-rate crossing measured points.
- **Migration/rollback:** each is additive over the Tier-0 seams (no substrate redesign, per the seam guarantee);
  each ships with its prior path retained.
- **Deliberately unimplemented until justified:** anything whose benchmark case does not yet exist.

## 11. Limitations that cannot be eliminated

State them so the design is not oversold: (1) a truly global question over a huge history must inspect or
summarize more material -- the slow path bounds the blast radius, it does not make global queries free; (2) a
model-generated synopsis is a lossy view -- it is corrected by regeneration + expansion to source, not by being
trusted; (3) when the remaining evidence is insufficient, the correct output is abstention, and no architecture
turns missing evidence into knowledge; (4) the benchmark DETECTS regressions and demonstrates headroom -- it does
NOT guarantee non-deterioration; (5) determinism bounds the substrate + structure, not the model's judgement,
which is why judgement outputs are always provisional + validated; (6) embeddings + lexical scores are candidate-
discovery signals, not truth -- identity/negation/temporal/authority relationships live in symbolic fields/edges
or they are unreliable.

## 12. The 9B model's role + hardware

The 2080 Ti (11 GB) + Qwen3.5-9B-Q5_K_M remain the active engineering target. Durable intelligence lives in
external evidence, typed memory, deterministic retrieval, the hierarchy, procedures, modules/skills, verification,
and context compilation -- NOT parametrically in the model. The memory fabric consumes disk, system RAM, a local
database (SQLite), CPU indexing, small embedding passes, and one model invocation at a time. The 9B is used only
where judgement is required: interpreting ambiguous material; proposing claims/relationships; generating
reflections/synopses; proposing procedures; resolving uncertainty; reasoning over compiled evidence; planning +
synthesis. It must not spend context manually scanning catalogs, maintaining indexes, or rereading raw history
that deterministic code can serve. A larger future GPU improves model quality, concurrency, and speed -- it is a
configuration change, NOT a new memory architecture (consistent with the standing 2080-Ti-is-the-target rule).

## 13. Relationship to the rest of the system

`MEMORY_CONTRACT.md` and `CONTEXT_PACKET_CONTRACT.md` remain the field-level authorities and are amended (not
replaced) to satisfy the Tier-0 seams. `MEMORY_BENCHMARK.md` is the validation architecture that supplies the
evidence for every tier gate. The seam audit is the current-state gap analysis whose urgent items open Tier 0.
`PROJECT_DIRECTION.md` / `ARCHITECTURE_MAP.md` / `MODULE_ROADMAP.md` point here for the memory design; this doc
does not restate their content. This is doctrine: it describes the target + invariants + gates, and is amended
via a D-entry -- it is never an iteration ledger.
