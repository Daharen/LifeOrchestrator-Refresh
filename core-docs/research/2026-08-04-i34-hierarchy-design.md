# i34 design draft -- Tier-1 bounded-fanout hierarchy (node layer + tree builder + shortlist-and-descend)

**Status:** DRAFT for the frontier design red-team + Nicholas review. Becomes the i34 PART-1 contract amendment
(MEMORY_CONTRACT **A6** + CONTEXT_PACKET_CONTRACT **i34 amendment**) after the red-team folds. Governing:
`MEMORY_ARCHITECTURE.md` s3 layer 6 / s6 / s9 (Tier 1) + the seam audit U2. Extends the RESERVED A4/A5 seams
(`node` kind, `member_of_node`/`child_of_node` edges, provenance_mode-conditional hit shape, `candidate_role`,
multi-stage retrieval lineage) into a real build. CPU-only, deterministic; no model lane this wave.

## 0. Scope (i34 = the hierarchy slice ONLY)

BUILD: the deterministic node layer + tree builder + deterministic structural node synopsis + staleness
propagation + shortlist-and-descend retrieval + the eval measures that prove sub-linear navigation. DEFER to
i35: the per-task working-memory STORE (region already reserved) + the multi-channel query ROUTER (classifier
stub stays). DEFER to Tier 2: model-generated PROSE synopsis (provisional derivative), automatic node splitting
under live load beyond the initial build, claim/contradiction detection.

## 1. The node record (MEMORY_CONTRACT A6 -- freeze the reserved `node` kind's fields)

A `node` is a DERIVED record (`provenance_mode = derived_record`, `content_role = navigation`,
`candidate_role = navigation`), namespace-homogeneous, one tree per `namespace`. Frozen fields:

- `node_id`, `record_version_id`, `namespace`, `record_kind = node`, `level` (0 = leaf-parent, increasing to root).
- `child_of_node` parent edge (to one parent node) + `child_of_node` inverse to children; `member_of_node`
  edges from leaf records at level 0. **The edges are CANONICAL; the node's stored `child_ids[]` / `member_ids[]`
  are a rebuildable PROJECTION** (A5 U2'). Acyclic; no cross-namespace membership.
- **Deterministic structural synopsis** (the part shortlist-and-descend actually routes on):
  `child_count`, `subtree_record_count`, `entity_union[]` (bounded, deterministic top-N by subtree frequency
  with stable tie-break), `lexical_descriptor` (bounded term->df map over the subtree, deterministic),
  `time_range {valid_from_min, valid_to_max}`, `authority_range {min,max}`, `kind_histogram`,
  `centroid_embedding` (a DETERMINISTIC aggregate = renormalized mean of member/child vectors in one
  `embedding_space_id`; ABSENT while the vector channel is empty -- lexical+entity shortlist stands alone).
- **Reserved (NOT built i34):** `synopsis_text` (model-generated prose, a Tier-2 provisional derived view that
  must resolve back via `derives_from` + a validator; the deterministic structural synopsis is authoritative for
  routing meanwhile), `synopsis_embedding` (of that prose).
- `status`/`currentness` (§5 enum) -- a node carries **`summary_stale`** when any subtree leaf changed (below).
- `synopsis_provenance` = `derives_from` edges to the children/leaves the synopsis was computed from +
  `record_content_hash` over the deterministic synopsis bytes (so a node reconstructs to its constituents).

## 2. The deterministic tree BUILDER (the skeleton is code, never the model)

- **Bounded fanout `MAX_FANOUT`** (proposed default 16, ratifiable): a node holds at most MAX_FANOUT children;
  it SPLITS when full. Depth grows, the hot surface does not; the root never accumulates 1000 children.
- **Deterministic grouping.** Leaves (level-0 records in a namespace) group by a DETERMINISTIC key, NOT model
  judgement: proposed = a stable coarse-to-fine key (primary: source/module path prefix or entity cluster;
  secondary: `chunk_content_hash`-stable ordering) so the same corpus always builds the same tree. Grouping is
  the OPEN design question the red-team must stress (lexical/path vs embedding-centroid clustering; both must be
  deterministic + reproducible + namespace-homogeneous).
- **Split rule.** When a node exceeds MAX_FANOUT, partition its children deterministically into <=MAX_FANOUT
  sub-nodes by the same key at the next granularity; re-parent; recompute the two ancestors' structural
  synopses. A rebuild (drop + rebuild the whole namespace tree) is ALWAYS available (the tree is a rebuildable
  derived view); incremental split is the fast path.
- **Local-update invariant (A9 in the arch doc).** A new leaf normally touches ONE leaf-parent node, a bounded
  ancestor path, and the relevant secondary indexes -- never a global rebuild.
- schema_version 4 -> 5, additive in-place migration (new `nodes` + node-edge rows; sources/documents/versions/
  chunks/records UNTOUCHED; an un-built tree = zero nodes = today's flat behavior exactly).

## 3. Synopsis-staleness propagation (the single most important loop -- deterministic invalidation)

- A changed/added/deleted leaf marks its **ancestor-path node synopses `summary_stale`** by walking the
  `child_of_node` chain to the root (deterministic, bounded by depth).
- A `summary_stale` node's structural synopsis regenerates LAZILY on next access (recompute is pure/deterministic
  from current children); until regenerated it is served **stale-but-provenance-intact** and MAY ROUTE but MUST
  NOT ANSWER (A5 U2' -- navigational staleness never fails an evidence coverage requirement; a node is never
  answer-evidence anyway).
- Invariant the red-team must confirm: no path by which a leaf change fails to stamp an ancestor stale (the tree
  rotting into silent inconsistency is the named failure mode -- §6 of the arch doc).

## 4. Shortlist-and-descend retrieval (multi-stage; MEMORY_CONTRACT retriever + CONTEXT_PACKET compiler)

- Retriever (#36) gains two ops/modes over the SAME hit shape (A5 U2' already reserves `candidate_role` +
  `retrieval_stage_id`/`parent_stage_id`/`retrieval_plan_id`): **`shortlist(query, namespace, k)`** -> top-K
  `node` candidates (`candidate_role = navigation`), ranked by structural-synopsis match (lexical_descriptor +
  entity_union + ranges + centroid when present); **`descend(node_id)`** -> the node's children (nodes or leaf
  records), namespace-checked per hop (`ns_permitted` at EVERY hop, A5 U1'). A stage-local ranking per level; no
  new flat-top-k-only hardening.
- Compiler (#40) runs a **retrieval PLAN**: classify (the i32 `query_class` stub) -> for a global/overview/
  precedent class (the deterministic **descend-decision**, a stub this wave; the real router is i35) run
  shortlist -> descend relevant branches (bounded: <=B nodes per level, <=D depth) -> collect leaf candidates ->
  the EXISTING selpol/budget/packet path; for a local/exact class, flat-top-k as today. **Navigation nodes NEVER
  enter `evidence[]`** -- they appear in `navigation_refs` + the packet-identity retrieval-plan/stage trace only
  (`candidate_role = navigation`). Bounded navigation cost = B*D nodes examined, INDEPENDENT of leaf count ->
  sub-linear. context_packet stays 0.2 (additive); #40 imports #37's canonical `ns_permitted`/`selpol`
  READ-ONLY (unchanged).

## 5. Lane decomposition (i34 PART 2 -- 3-lane CPU, GPU lane SKIPPED, MaxParallel 3)

- **Lane A -- #36 artifact.search (schema 4->5):** the `nodes` table + `node` record emission + `member_of_node`/
  `child_of_node` edges + the deterministic tree BUILDER (group/split/recompute) + deterministic structural
  synopsis + centroid-when-available + `summary_stale` propagation + the `shortlist`/`descend` retriever ops
  (candidate_role=navigation, per-hop ns_permitted, multi-stage lineage). Owns the hierarchy gate tests +
  SCHEMA_NOTES for the A6 interpretation. CPU-only, deterministic, no model.
- **Lane C -- #40 context.compiler:** the shortlist-and-descend retrieval PLAN + the descend-decision stub +
  `navigation_refs` + candidate_role handling (nodes route, never evidence; navigational staleness doesn't fail
  coverage) + bounded navigation cost + the retrieval-plan/stage trace in packet identity. Imports #37
  READ-ONLY. context_packet/0.2 additive.
- **Lane B -- #37 retrieval.eval:** navigation-cost (nodes examined vs leaf count -> assert sub-linear across a
  SCALED fixture corpus spanning >=2 orders of magnitude of leaves), hierarchy-recall (the required leaf is
  reached via descend, i.e. no synopsis routes AWAY from a required source), shortlist quality, and the
  MEMORY_BENCHMARK Tier-1 "bounded context cost as corpus grows" measure. eval version bump.
- **Frontier lane (off-box, parallel):** the design red-team on THIS draft (§6).
- **Orchestrator fold (D-0077):** real #36 tree over a real multi-namespace catalog -> #40 shortlist-and-descend
  compile -> packet; assert navigation sub-linear in leaf count, required leaf recalled via descend, zero nodes
  in evidence[], navigational-staleness routes-but-doesn't-answer, namespace-homogeneous nodes + no
  cross-namespace hop, every excerpt reconstructs to source, deterministic packet_id, byte-identical
  #40-vs-direct, 0 orphans.

## 6. Open design questions the red-team must stress (ranked)

1. **Tree-builder determinism + recall vs grouping choice.** Is a deterministic path/entity grouping key
   sufficient, or does it route a required leaf into the wrong branch (a synopsis that hides its own evidence)?
   Does the invariant "no derived view outranks its sources" hold when descend prunes branches? What guards
   recall when the grouping is lexically misleading?
2. **Staleness propagation completeness.** Any path by which a leaf mutation (add/edit/delete/tombstone/
   re-parent on split) fails to mark an ancestor `summary_stale`? Interaction of split + stale propagation
   (a split recomputes synopses -- does it ever clear a stale flag it shouldn't)?
3. **Bounded-fanout under incremental growth.** Does incremental split keep navigation sub-linear, or does it
   degenerate (skew, deep thin chains) so a rebuild is periodically required? What triggers rebuild deterministically?
4. **Namespace homogeneity under real ingest.** Can a node ever acquire cross-namespace members/children (A5
   forbids it); is the per-hop ns_permitted on descend sufficient; centroid/entity_union leakage across scope?
5. **Navigation-vs-evidence boundary.** Is "a node may route but never answer" airtight -- can a node synopsis
   or its entity_union leak into evidence/coverage; can navigational `summary_stale` mask a real evidence gap?
6. **Centroid-embedding-as-deterministic-aggregate.** Is a renormalized mean a sound shortlist signal, or does
   it need the reserved model-prose-synopsis embedding to route well? Acceptable to ship lexical+entity-only
   shortlist while the vector channel is empty?
7. **Acceptance-gate realism.** Is "sub-linear navigation cost + preserved recall across >=2 orders of magnitude
   on a foreign corpus" the right Tier-1 gate, and is a synthetic scaled corpus a valid stand-in for the ~200MB
   real rehearsal?

GO / NO-GO requested on: freezing A6 + the CONTEXT_PACKET i34 amendment as drafted; the deterministic-grouping
tree-builder; the lazy stale-regen loop; the shortlist-and-descend recall guarantee; and any SAFETY-CRITICAL
namespace/authority foreclosure (the i32->i33 precedent: an envelope-level design can hide a closure defect).
