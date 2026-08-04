# Frontier digest -- i34 Tier-1 hierarchy design red-team (pack b4c90545)

**Date:** 2026-08-04 · **Pack:** `b4c90545-2614-4e53-b43b-6955c5f4201c` (frontier-pack-i34-hierarchy-redteam) ·
**Reviews:** `research/2026-08-04-i34-hierarchy-design.md` (the i34 PART-1 design draft) against
`MEMORY_ARCHITECTURE.md` + the seam audit + MEMORY_CONTRACT A4/A5 + CONTEXT_PACKET i32/i33. **Governs:** the
i34 PART-1 redraft (MEMORY_CONTRACT **A6** + CONTEXT_PACKET **i34 amendment**) BEFORE the build dispatches.

## Verdict

**NO-GO on freezing A6 + the CONTEXT_PACKET i34 amendment AS DRAFTED. GO on the architecture after a narrow
pre-build redraft.** The deterministic-skeleton / provisional-model-content / lossless-substrate /
navigation-vs-evidence choices are correct. Same shape as the i32->i33 precedent: an envelope/first-layer design
hid a load-bearing defect; redraft, then build (here in-place, since no i34 contract is committed yet).

## The load-bearing defect (P0 correctness)

**The draft claims recall preservation while letting a bounded beam PRUNE branches using LOSSY structural
synopses.** `entity_union` (bounded), `lexical_descriptor` (bounded), and a centroid (an averaging heuristic)
can each omit the feature that makes a required leaf relevant. Deterministic construction makes the miss
REPRODUCIBLE, not impossible. Bounded deterministic navigation is NOT automatically recall-preserving
navigation. The reconstructability rule proves a SELECTED synopsis expands to evidence; it does NOT prove an
UNSELECTED synopsis didn't conceal relevant evidence.

## Single highest-leverage change (adopt into A6)

> A navigation-derived value may POSITIVELY prioritize a branch, but may NOT NEGATIVELY exclude a branch unless a
> deterministic, channel-specific, NO-FALSE-NEGATIVE pruning predicate proves the subtree cannot satisfy the
> query or an evidence requirement at the pinned snapshot. Otherwise the compiler must expand / use another
> channel / fall back to the flat path / return `needs_expansion` | `abstain`. A STALE synopsis is NEVER
> eligible to supply a pruning proof.

Channel-specific SAFE pruning: exact ID/path/symbol -> exact index bypass; time/kind/authority -> exact subtree
ranges/histograms may exclude impossible branches; lexical/entity -> only an EXACT membership or no-false-negative
(Bloom-style) filter may establish absence (a bounded top-N descriptor CANNOT); dense-vector -> centroid alone
CANNOT exclude (needs an admissible bound = centroid + covering radius); general/global -> hierarchy ranking is
best-effort, retain expansion/flat fallback.

## Required redraft delta (10, before dispatch)

1. Replace unconditional-recall language with the SAFE-PRUNING / fallback contract (above).
2. Add RETRIEVAL-COMPLETENESS + pruned-frontier lineage to the packet: `retrieval_completeness`,
   `frontier_exhausted`, `pruned_branch_count`, `prune_policy_id/version`, `prune_reasons[]`, `fallback_used`,
   `stale_navigation_encountered`, `unresolved_branch_count`. A hierarchy MISS must not read as proved ABSENCE
   (evidence-coverage vs retrieval-completeness are DISTINCT; a node still never enters `missing_requirements[]`).
3. SEPARATE three state axes: evidence-record `status` (§5), TOPOLOGY state (valid|rebuild_required|corrupt),
   NAVIGATION-synopsis freshness (fresh|stale + generations). A `summary_stale` node is a CURRENT topology object
   with a stale synopsis -- do NOT overload evidence `current_only` hard-exclude onto it.
4. MONOTONIC generations + snapshot-bound CAS regen (Boolean stale flag admits an ABA/lost-update race:
   mark-stale -> regen-from-old-snapshot -> 2nd mutation -> clear-stale -> falsely fresh). Fields:
   `subtree_generation`, `synopsis_generation`, `synopsis_built_from_corpus_version`, `synopsis_input_digest`;
   fresh IFF synopsis_generation covers subtree_generation AND input_digest matches canonical child/member
   versions; clearing freshness is CAS/transactional.
5. **(SAFETY-CRITICAL)** Bind `shortlist`/`descend` to the EFFECTIVE authorized namespace set + hierarchy version
   + corpus snapshot (an arbitrary `node_id` must not make the retriever a confused deputy):
   `shortlist(query, effective_allowed_namespaces, hierarchy_version, corpus_snapshot, k)` /
   `descend(node_id, retrieval_plan_id, effective_allowed_namespaces, hierarchy_version, corpus_snapshot)`.
6. **(SAFETY-CRITICAL)** WRITE-TIME + transitive namespace HOMOGENEITY for every node aggregate AND every
   navigation-visible object (per-hop filtering alone is insufficient -- a permitted node's STORED aggregate could
   already be contaminated): edge insert asserts parent.ns==child.ns==member.ns; synopsis recompute asserts all
   immediate inputs + transitive derivation closure homogeneous; entity_union/lexical/ranges/histograms/centroid/
   counts/hashes are protected derived info; `navigation_refs`/stage traces/pruned-branch diagnostics/node ids/
   paths/scores/descriptors/expand hints all get the closure check; a multi-namespace authorized compile
   traverses SEPARATE roots and fuses later -- never a mixed root/aggregate.
7. Add hierarchy IDENTITY now (avoid the "one tree per namespace" foreclosure -- future source/entity/temporal/
   semantic/code-symbol hierarchies): `hierarchy_id`, `hierarchy_kind`, `builder_policy_id/version`,
   `tree_version`/`tree_generation`, `root_node_id`. i34 still builds ONE hierarchy per namespace; a leaf may join
   multiple hierarchies later. Publish trees as ATOMIC versions (build+validate+atomic root swap; packet identity
   + stage lineage include hierarchy_id + policy version + tree_version alongside corpus_version).
8. BALANCED deterministic bulk-build/split (path/entity refinement can degenerate to deep thin chains even with
   every node <= MAX_FANOUT): total order `(coarse_group_key, stable_secondary_key, record_id)` -> balanced pages
   (max occupancy F, min non-root occupancy, deterministic median split, stable tie-break, fallback from
   semantic/path refinement to stable ordering when a partition isn't balanced+nonempty). Plus DETERMINISTIC
   rebuild/flat-fallback TRIGGERS (invariant fail; policy-version change; depth >> balanced ideal; occupancy/
   tombstone fragmentation; unrepairable overflow; stale fraction/age; measured recall below baseline; tree
   digest != canonical edge projection). Rebuild = shadow-build + validate + atomic root-swap; prior version stays
   for pinned compiles.
9. RESOLVE the scope contradiction (the draft DEFERS live auto-split to Tier 2 but DESCRIBES incremental split as
   the fast path): red-team recommends the MINIMAL i34 option -- bulk-build a balanced tree; allow simple updates
   only while invariants hold; on overflow / grouping-changing re-parent -> mark the namespace tree
   `rebuild_required` + flat-fallback until a deterministic rebuild completes (full transactional B-tree split is
   the larger, less scope-consistent option).
10. Synthetic ADVERSARIAL scale fixtures (identical path prefixes; one dominant entity; rare decisive term;
    cross-cutting concepts; multimodal/absent vectors; insert/delete/tombstone/move/split/collapse; mutation
    DURING lazy regen; cross-namespace contamination attempts; exact+global mixtures) PLUS the real ~200MB
    foreign-corpus rehearsal before freeze/activation. Measure BOTH hierarchy-path recall AND end-to-end
    PACKET-evidence recall (reached != retained). Complexity is O(B*log_F N) -- report p50/p95 nodes-examined vs
    leaf count; the draft's "B*D independent of leaf count" is internally inconsistent with "depth grows with N".

Centroid: preserve associative sufficient statistics (vector SUM + count + missing-count + embedding_space_id +
canonical child/member order + specified accumulation precision/algorithm + canonical quantization before hash),
NOT a mean-of-normalized-child-centroids (topology-dependent + FP-repro-breaking). Reserve covering-radius/medoids
for later. Lexical+entity-only initial shortlist is fine (doesn't foreclose vectors/prose) as long as it's never
presented as a no-false-negative oracle.

## Ranked risks

- P0 correctness -- silent false-negative pruning (a bounded lossy synopsis drops the sole required branch; the
  packet looks well-formed + provenance-valid + answerable having never exposed the evidence).
- P0 correctness -- stale-clear lost-update / mixed-generation traversal.
- P0 safety -- namespace leakage via aggregate construction or an unauthorized `descend(node_id)`.
- P1 -- skewed topology + false complexity claim; "one tree per namespace" foreclosure; centroid instability /
  multimodal collapse; acceptance-suite false confidence ("required leaf reached" + synthetic-only).

## What it means for i34

REDRAFT the design + PART-1 contract per the 10 deltas (no separate iteration needed -- nothing is committed
yet), THEN dispatch the 3-lane build against the HARDENED contract, with the safe-pruning + retrieval-completeness
+ generations + authorization-bound-ops + write-time-homogeneity + hierarchy-identity + balanced-build/fallback
semantics first-class. The wave stays appropriately scoped + minimal for i34 (no i35 store/router, no Tier-2
model-prose synopsis / claim detection) after these narrow additions.
