# FANOUT_AGENT_001 -- READY (i34 wave scoping)

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i34 (plan id `fo-34-45fcbd0d` once planned)
- **Lane:** CODING (CPU; GPU lane skipped this wave)
- **Worker id / label:** w1-hierarchy (`36-artifact-search`)
- **Module/area (exclusive):** `modules/36-artifact-search/` ONLY (artifact.search 0.4.0 -> 0.5.0)
- **GPU:** false
- **Docs:** `[]`

## Mission
Build the MEMORY_ARCHITECTURE **Tier 1** bounded-fanout hierarchy into #36: turn the A4/A5 reserved
`node` record_kind + `member_of_node`/`child_of_node` edges into a REAL deterministic navigation tree with
node synopses, and add a **shortlist-and-descend** retrieval entrypoint -- WITHOUT rewriting the flat catalog
and WITHOUT hardening flat-top-k as the only path. This is the deterministic SKELETON of the hierarchy (the
model-generated synopsis + node embedding are later; the node structure, splits, membership, and staleness are
code). Governs: `MEMORY_ARCHITECTURE.md` s3 (layer 6), s6 (hierarchy maintenance), s9-s10 (Tier 1);
`MEMORY_CONTRACT.md` A4 (U2), A5 (U1'/U2'/U4'), s1/s3/s4/s5; seam audit s2-s3 (U2). #36 is the PRODUCER in this
wave's D-0077 cross-module smoke (consumer = #40, slot 003).

## Unit (the full worker prompt)
You are the #36 artifact.search worker for i34. Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md`
(esp. Known failures) + `MEMORY_ARCHITECTURE.md` + `MEMORY_CONTRACT.md` (A4/A5) first; obey `SKILL_CONTRACT.md`.
Do ONE unit in `modules/36-artifact-search/` only; `docs:[]`; ship via `dev.ship`; report via `-Action report`.

**SCOPE IN (artifact.search 0.4.0 -> 0.5.0, additive; schema_version 4 -> 5 with an in-place forward migration):**
1. **`node` records (MEMORY_CONTRACT s1 + A4 U2 + `MEMORY_ARCHITECTURE` s3 layer 6).** Materialize the `node`
   record_kind through the existing envelope + `record_edges` -- NO rewrite of sources/documents/versions/chunks.
   A node carries: a synopsis (see 2), a bounded child list (a rebuildable PROJECTION; the EDGES are canonical),
   time/authority ranges, key entities, child ids + subtree counts, lexical descriptors, a nullable
   `embedding_space_id` (node embedding is a deferred seam -- leave absent), and synopsis provenance
   (`provenance_mode = derived_record`; A2/A5 U2'). Namespaced: a node is namespace-HOMOGENEOUS across its
   transitive membership closure (A5 U1'(c)); NO cross-namespace membership; the tree is per-namespace.
2. **Deterministic node synopsis (skeleton only).** Generate the synopsis DETERMINISTICALLY (extractive: bounded
   lexical descriptors + aggregated key entities + child summaries/counts/ranges) -- NO 9B this wave. Reserve a
   `synopsis_source` seam (`deterministic_extractive` now; `model_generated` later, Tier 2). Node
   `provenance_mode = derived_record`: validate `derivation_refs` (the child/member records) + `record_content_hash`.
3. **`member_of_node` (record->node) + `child_of_node` (node->node) edges** as first-class `record_edges`
   (A4 U2). Acyclic; single canonical direction; canonical edges, the stored child list is the projection.
4. **Deterministic bounded-fanout build + split (`MEMORY_ARCHITECTURE` s6).** A node splits when it exceeds
   `max_fanout` (a config knob) -- structure is CODE, not model judgement. Build the tree over existing records
   for a fixture + a bounded real slice; a new/changed leaf updates ONE leaf + a BOUNDED ancestor path + the
   relevant indexes (invariant s9-5), never a global rebuild. Marking a changed leaf sets its ancestor-path node
   synopses to `summary_stale` (MEMORY_CONTRACT s5); stale synopses are served stale-but-provenance-intact and
   regenerated lazily (regeneration mechanism can be a stub returning the deterministic synopsis this wave).
5. **`search` op: `shortlist_and_descend` mode (A5 U2').** A MULTI-STAGE retrieval: start at root/high-level node
   synopses (shortlist), descend ONLY relevant branches to leaves, return leaf candidates. Each hit reserves
   `candidate_role` (`navigation | evidence`) + retrieval-stage lineage (`retrieval_stage_id` / `parent_stage_id`
   / `retrieval_plan_id`) with STAGE-LOCAL rankings. A `node`/navigation hit MAY route but is NEVER answer-evidence;
   NAVIGATIONAL staleness (`summary_stale`) may route but must not answer. Provenance fields are CONDITIONAL on
   `provenance_mode` (A2/A5 U2'): a node/derived hit needs no single source span. **Keep the flat top-k `search`
   path unchanged and hierarchy-AGNOSTIC at the candidate-pool interface** -- shortlist-and-descend is ADDITIVE,
   selected by mode; do NOT add flat-top-k-only assumptions.
6. **Namespace closure holds through the tree (A5 U1').** The canonical `ns_permitted` predicate is enforced at
   EVERY descend hop + edge-walk (not just the seed); every returned/reachable object (node, member, edge,
   diagnostic array) is scope-checked; a cross-namespace object is a fail-closed abort leaving no identifying
   metadata (count only; detail -> the privileged local security log). Align #36's `ns_permitted` implementation
   byte-identically to #37's canonical `lib/namespace_policy.py` (A5 risk-6; the fold asserts identical accept/reject).
7. **`effective_current` on the catalog (A5 U4') is UNCHANGED from 0.4.0** -- confirm nodes participate correctly
   (a node is not itself superseded content; do not break the `superseded_by` chain computation).

**SCOPE OUT:** NO 9B / model synopsis (deterministic only). NO node embeddings (nullable seam). NO vector/graph/
temporal channels beyond what 0.4.0 ships. NO consolidation/promotion (Tier 2). NO packet/selection changes (that
is #40, slot 003). NO working-memory store (that is #42, slot 002). Do not touch any module but #36.

**GATES.** Off-machine cloud gate FIRST (pwsh 7.4.6 on the real skill where portable) -> `-Live` on the Windows
executor -> `dev.ship` (sha256 + AST + tests, fail-closed, named files only, trailers). schema_version 4->5
migration is in-place + reversible; keep the crash-safety + transactional-swap invariants (MEMORY_CONTRACT s4).
Double-run byte-identity gate on any canonical-bytes output (the pwsh determinism traps -- CURRENT_STATE). Record
every contract interpretation in `modules/36-artifact-search/SCHEMA_NOTES.md` (the D-0077 shared-contract requirement).
Report plainly if a seam proves impractical -- negative results are first-class (D-0061).

## Rails
Standing rules: `core-docs/fanout/FANOUT_AGENT_TEMPLATE.md`. Acquire res.lease in gpu->git->doc order (git only
this wave); release on exit. ONE unit, module-exclusive, `docs:[]`. Gate off-machine first, then `exec-job.sh
devship`; files reach the box via SendUserFile + device_commit_files. 0 orphaned llama-server/python. Runtime-
behavior change -> a real `-Live` check. Report: `-Action report -PlanId fo-34-45fcbd0d -WorkerId w1-hierarchy -State
done` + a plain measured summary.

## Verification
- schema_version 4->5 migration proven in-place + idempotent re-ingest stable (catalog_digest unchanged for
  unchanged inputs).
- Tree over a fixture + a bounded real slice: bounded fanout enforced (a split fires at `max_fanout`); a
  single-leaf change updates one leaf + a bounded ancestor path (NOT a global rebuild); ancestor synopses flip to
  `summary_stale`.
- `shortlist_and_descend` returns leaf evidence via node navigation; `candidate_role`/stage-lineage present;
  navigation hits never emitted as answer-evidence; navigation cost SUB-LINEAR in leaf count (measured).
- Namespace closure: a mixed-namespace fixture yields ZERO cross-namespace nodes/members/edges/diagnostics; a
  cross-namespace descend hop fail-closes with count-only. `ns_permitted` byte-identical to #37 canonical.
- Flat top-k `search` byte-identical to 0.4.0 (additive proof).
- Full suite green cloud + `-Live`; `SCHEMA_NOTES.md` updated; expected artifacts under `modules/36-artifact-search/`.

## Report-back record
_(Orchestrator fills from `plans/fo-34-45fcbd0d/reports/` before archiving.)_
