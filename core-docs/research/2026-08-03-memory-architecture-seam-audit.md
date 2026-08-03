# Seam audit -- current memory implementation vs the long-horizon target

**Date:** 2026-08-03 - **Governs:** the Tier-0 scope of `MEMORY_ARCHITECTURE.md` (D-0090) - **Method:** classify
each intended layer against the shipped contracts + modules (`MEMORY_CONTRACT.md` v0.1.1, `CONTEXT_PACKET_CONTRACT.md`
0.2, #36 artifact.search 0.2, #37 retrieval.eval 0.3, #38 repo.intel, #39 episode.record 0.1.1, #40
context.compiler 0.2, #41 skill.card 0.2). This is a point-in-time gap analysis; the target + tiers live in
`MEMORY_ARCHITECTURE.md`, the validation in `MEMORY_BENCHMARK.md`.

Classification legend: **[CLEAN]** already supported cleanly - **[AWKWARD]** supported but awkward - **[ADD]**
additive with a small contract amendment - **[LATER-$]** expensive to add later if we harden against it now -
**[FORECLOSED]** currently absent/incompatible, needs new structure.

## 1. Per-layer classification

- **Lossless canonical substrate + retained originals** -- **[CLEAN].** #36 keeps sources/documents/versions/
  chunks + records; content-addressed; A2 hash split. Ingested originals are retained as sources. This is a
  strength; nothing higher can overwrite it.
- **Stable identity + versioning** -- **[CLEAN].** `record_id`/`record_version_id`/`source_version_id`, monotonic
  version chains, idempotent re-ingest (catalog_digest stable). Good.
- **Provenance + derivation lineage + reconstructability** -- **[CLEAN].** A2 modes
  (direct_span/derived_record/aggregate/tombstone) + `record_edges` (`derives_from`, `describes_structural_skill`,
  `has_stage`); the packet reproduces spans against `chunk_content_hash`. Strong; the reconstructability invariant
  is essentially met at the record level.
- **Rebuildable derived views** -- **[CLEAN].** Embeddings, FTS, records, ranks are all rebuildable from sources;
  #36 reconcile + re-ingest is idempotent. Drop-and-rebuild is available.
- **Schema evolution** -- **[CLEAN].** #36 shipped a `schema_version` 1->2 in-place migration; the precedent +
  mechanism exist.
- **Bounded context packet + expansion-to-source** -- **[CLEAN].** #40 has fixed budgets, `omission_manifest`,
  `packet_disposition`, `consumer_profile`, exact/upper-bound transport, identity/lineage, and an immutable
  `expand` delta with a locked corpus snapshot. The bounded hot set is real today.
- **Typed records (record_kind)** -- **[ADD]** for new kinds. The enum is CLOSED (by design); adding `semantic`/
  `reflective`/`procedure`/`claim` kinds (some already present) is an additive `MEMORY_CONTRACT` s1 amendment +
  the D-0077 smoke. The PRINCIPLE (per-kind ingestion/retention/validity) is only partly honored end-to-end today
  (kinds mostly differ in payload, not in retrieval/retention policy) -- **[AWKWARD]** for per-kind policy.
- **Multiple orthogonal retrieval channels** -- **[AWKWARD].** retriever-0.2 carries per-candidate
  `retrieval_occurrences[]` with an OPEN `channel` field (lexical/vector/... as DATA, not hard-coded) -- so adding
  graph/temporal/statistics channels is additive at the interface. But only lexical is live (vector channel
  empty; no graph-traversal retrieval, no temporal-partition index, no prior-use statistics). The seam is open;
  the channels are unbuilt.
- **Currentness / staleness** -- **[CLEAN]** as state (s5 enum, machine-readable). **Supersession/derivation
  edges** -- **[CLEAN]** as structure (`record_edges`). Using them in RANKING -- **[AWKWARD]:** selpol applies a
  SOFT `stale_penalty` + hard-filter for deleted, but there is no hard current-only retrieval MODE and no
  supersession-aware ranking (a superseded-but-similar record can still surface). **Contradiction** -- **[ADD]:**
  no `contradicts` edge in active use + no contradiction detection.
- **Consolidation (episode->claim->synopsis->procedure)** -- **[ADD] (Tier 2).** #39 records episodes+failures;
  the derivation edges + record kinds are present as seams; the promotion pipeline itself is unbuilt.
- **Procedural promotion** -- **[ADD] (Tier 2).** #38 structural `skill` records + #41 activation cards + the
  module registry are strong seeds; verified-success->procedure->module promotion is unbuilt.

## 2. Gaps that are new structure

- **Bounded-fanout hierarchy (index of indexes)** -- **[ADD structurally / LATER-$ behaviorally].** #36's catalog
  is FLAT (sources/documents/versions/chunks/records/record_edges); there is no node table, no bounded-fanout
  tree, no node synopses. A `node` record_kind + `member_of_node`/`child_of` edges + node synopses can be added
  ADDITIVELY (schema bump + new kind + new edges). The COST is behavioral: retrieval + selpol + the compiler
  currently assume flat candidate pools and top-k. If we keep hardening flat-top-k assumptions, adding
  shortlist-and-descend later gets expensive -- hence the seam is urgent to protect even though the tree is a
  Tier-1 build.
- **Namespace enforcement** -- **[LATER-$ / partially FORECLOSED].** The envelope HAS `namespace`, but retrieval
  treats it as a SOFT descriptor boost (project-match points), not a HARD partition/boundary. Nothing prevents
  cross-namespace records from entering a packet. If indexes, the hierarchy, and packets are built without
  namespace as a hard boundary, cross-project bleed is baked into every derived layer and is expensive to
  retrofit. This is the single highest-risk foreclosure for the multi-project end-state.
- **Working memory (per-task iterative state)** -- **[FORECLOSED].** Packets are stateless per-compile; there is
  no per-`task_id` store that carries a task's evolving state across its iterative turns. A deepening task cannot
  distinguish its own current intermediate state from stale earlier state -- the mechanical cause of
  "deteriorates on iterative prompts." Needs a new working-memory store; design the seam now.
- **Query-type-aware retrieval planner** -- **[ADD / FORECLOSED as a stage].** #40 builds a descriptor but does
  not CLASSIFY the information need to route (exact vs current-state vs historical vs global vs causal vs
  procedure). A planner stage in front of retrieval is new; nothing forecloses it, but it must exist before
  diverse query types are served without flat-top-k degradation.
- **Fast/slow path split** -- **[ADD].** The fast path (classify->retrieve->rerank->compile) is largely present
  minus the planner; the explicit slow path (descend/traverse/inspect-files/parallel-gather/map-reduce/abstain)
  is unbuilt. Disposable subagents/baton artifacts already exist as the mechanism.
- **Foreign-corpus intake + interpretation** -- **[ADD over a CLEAN substrate].** #36 ingestion + hashing +
  chunking works on arbitrary text and retains originals; #38 repo.intel is tuned to OUR structure, not arbitrary
  discovery. Boundary/namespace/entity/type discovery from foreign material is a new interpretation side; the
  substrate supports it additively.
- **Hot/warm/cold/archival tiers** -- **[ADD] (Tier 2).** The packet is the hot set; store-level tiering by
  recency/priority is unbuilt.
- **Memory-quality lifecycle benchmark** -- **[ADD over a CLEAN seed].** #37 retrieval.eval scores retrieval +
  packet deterministically; the foreign-corpus mutation harness + the discovery/consolidation/reconstruction/
  continued-learning measures are new (`MEMORY_BENCHMARK.md`).

## 3. Urgent corrections (Tier-0 -- do now, even though the full capability is later)

Ranked by lock-in cost if deferred:

1. **Namespace as a HARD boundary (U1, highest).** Amend `MEMORY_CONTRACT`/retriever + selpol so `namespace` is an
   enforced hard filter (and a first-class catalog + future-hierarchy partition), not a soft boost. Every index,
   node, and packet built after this inherits isolation; every one built before it must be retrofitted. A
   contract test must prove zero cross-namespace leakage on a mixed fixture.
2. **Protect the hierarchy seam (U2).** Verify -- and freeze as a seam -- that #36's schema, the retriever channel
   model, and the selpol/compiler admit a `node` layer + `member_of_node` edges + shortlist-and-descend WITHOUT a
   rewrite, and stop hardening flat-top-k as the only path (keep candidate pooling + selection hierarchy-agnostic
   at the interface). No tree is built at Tier 0; the seam is guaranteed.
3. **Working-memory seam (U3).** Define the per-`task_id` working-memory store contract now (state records,
   promote/demote, strict exclusion from evidence/execution authority) even if the store is built at Tier 1, so
   the compiler + retrieval learn to consult it as a distinct region rather than re-deriving task state from
   long-term memory.
4. **Current-over-stale + supersession-aware ranking (U4).** Promote current-only from a soft `stale_penalty` to a
   real retrieval MODE, and make supersession edges rank-affecting (a superseded record is demoted below its
   successor by construction, not by score luck). Add a `contradicts` edge to the s1 edge set (detection is
   later). This is the iterative-deterioration guard.
5. **Query-classification + open-channel seam (U5).** Keep the retriever channel model explicitly open
   (graph/temporal/statistics as additive channels) and reserve a query-classification stage in the compiler's
   front so query-aware routing is not foreclosed by a single hard-coded lexical path.

Items 1-2 are true lock-in risks (cheap now, expensive after the derived layers exist). Items 3-5 are foreseeable
anti-deterioration foundation to land before substantial autonomous external work. Everything in section 1 marked
[CLEAN] is a genuine strength the target builds ON, not around.
