# Tier-0 amendment red-team (frontier, pack 159e9cb5) -- FOLDED

**Date:** 2026-08-04 - **Pack:** 159e9cb5 (frontier.bridge #31) - **Reviews:** the i32 Tier-0 amendments
(MEMORY_CONTRACT A4 + CONTEXT_PACKET_CONTRACT i32, D-0092) vs MEMORY_ARCHITECTURE + the seam audit. **Rationale:**
D-0095. **Verdict: RE-AMEND, THEN SHIP** -- NO-GO to fold/close i32 as-written; CONDITIONAL GO after a NARROW
re-amendment. The architecture + prioritization are substantially correct; the fixes are contract clarifications,
NOT new capabilities. Two defects force a re-amendment BEFORE i32 closes -> **i33 NAMESPACE-CLOSURE +
SUPERSESSION-HARDENING**.

## Confirmed strengths (build on; do not revisit)
Hard namespace filtering (not a relevance bonus); retriever + packet-level isolation; a real current_only mode;
preserved historical records; the contradicts edge; the open channel field; a separate working_memory region;
node/hierarchy edge reservations; tree/router/store kept OUT of Tier 0; non_execution:true preserved. The problem
is NOT overbuilding -- it is UNEVEN seam definition (U1/U4 omit closure semantics; U2 reserves storage nouns but
not retrieval-stage structure; U3 adds a record kind but omits the state-version seam; U5 over-freezes the
class->mode identity while omitting policy/version fields).

## Required pre-fold changes (the i33 re-amendment)

### 1. SAFETY-CRITICAL -- namespace-scope CLOSURE (U1')
- effective_allowed_namespaces = intersection(task_input REQUEST, control_plane GRANT). task_input.namespace is a
  REQUEST, NOT authorization (reconciles P0-1); cannot widen scope; empty intersection fails closed; no implicit
  all/wildcard/prefix/parent/shared namespace.
- Enforce the predicate at EVERY retrieval stage + graph hop (not just the seed candidate).
- Scope-check EVERY packet-visible object: evidence, working state, provenance/derivation refs, diagnostic arrays
  (ranked[]/features_by_candidate/stages[]/retrieval_occurrences), omission entries, expansion hints, eval hooks.
- Derived records / aggregates / dedup-clusters / nodes must be namespace-HOMOGENEOUS across transitive provenance
  closure. Forbid persisted cross-namespace derivatives at Tier 0 (a shared-scope contract is later).
- A cross-namespace REJECTED candidate leaves NO identifying metadata in the packet (only namespace_violation_count
  + compile_status=failed_closed; details -> a privileged local security log). Recommend ABORT the compile on a
  retriever contract violation.
- Working-state access requires task_id AND current namespace authorization (CONJUNCTIVE; task_id-isolation and
  namespace-isolation are DIFFERENT mechanisms). Expansion never widens parent scope.
- ONE canonical namespace predicate + error policy shared by retriever/selpol/compiler (else byte-identical
  cross-module behavior is unlikely -- risk 6).

### 2. Candidate-INDEPENDENT supersession (U4')
- effective_current(record) = status==current AND no valid reachable live successor in the chain at the snapshot
  within scope -- computed from the CATALOG/graph, NOT the retrieved pair.
- Add a literal `superseded` currentness state (the s5 enum lacks it).
- Chain invariants: acyclic; canonical direction; NO cross-namespace supersession; branching -> conflicted/abstain;
  terminal vs immediate successor; stale/deleted successor handling.
- current_only as a HARD filter is correct AFTER temporal intent resolves to current_only -- not the universal
  mode. contradicts: reserve with extensible attributes; ABSENCE of the edge != no contradiction (detection
  deferred -> incomplete graph).

### 3. Hierarchy hit-shape (U2')
- Make retriever provenance fields CONDITIONAL on provenance_mode: direct_span (path+span), derived_record
  (record_content_hash+derivation_refs; span optional), aggregate (constituent refs), tombstone (deletion prov).
  Node/aggregate/synopsis records have no single source span.
- Reserve candidate_role (navigation | evidence) + retrieval-stage lineage (retrieval_stage_id/parent_stage_id/
  retrieval_plan_id). Freeze MULTI-STAGE retrieval (a packet compile is NOT one flat top-k; rankings stage-local).
- Separate NAVIGATIONAL staleness from EVIDENTIARY staleness (a summary_stale node may ROUTE but not ANSWER).
- Child-list authority: edges canonical, node child-list a materialized projection; no cross-ns membership; acyclic.

### 4. Working-state seam (U3')
- Rename "task-authoritative for STATE" -> "CONTINUITY-authoritative" (recorded current state of THIS task, not
  truth about the world). Not execution authority; can_instruct:false (kept).
- Reserve the store fields NOW: working_state_id, task_id, state_version, parent_state_version, namespace_scope,
  grant_snapshot_ref, created_from_packet_id, content_hash, lifecycle_state (active|closed|archived),
  content_role:working_state, writer_authority.
- Freeze: immutable/versioned snapshots; CAS/parent-version on update; one active head; fork semantics; a SEPARATE
  fixed working-memory budget; closed state not ordinarily retrievable; archive != evidence; promotion creates a
  NEW derived long-term record with provenance + validation; packet identity includes the working-state version.
- Ordinary search() MUST REJECT record_kind=working by default (exact task_id op only) -- "default excluded" is too
  weak. Prefer a small working_state/0.1 contract.

### 5. Classifier seam (U5')
- Separate query_class (semantic) from temporal_intent (independent dimensions); explicit user time/version
  OUTRANKS the stub. Version the classifier + the class->mode mapping (classifier_policy_id/version). Add
  `composite` + `unclassified` fallback states. Packet identity includes classifier policy id/version + the
  resulting temporal mode + routing-policy version + working-state version + retrieval-plan/stage trace.

## Ranked risks
1. Namespace laundering + diagnostic leakage -- SAFETY-CRITICAL (a permitted-envelope summary/node/aggregate/
   working-state/omission entry/candidate diagnostic discloses forbidden-namespace info even when evidence[] is
   clean). 2. Superseded records survive current_only (U4 guarantee not yet delivered). 3. Hierarchy insertion
   still needs a retriever/selection rewrite (the hidden flat-top-k assumption). 4. Working memory as an
   unversioned authority-shaped blob. 5. Query classification forecloses composite/temporally-ambiguous tasks.
   6. Three namespace-enforcement layers diverge without one canonical predicate + error policy.

## What this means for the roadmap
i32's conformance wave shipped the ENVELOPE-level namespace/current_only/seams (a correct FIRST layer). The
committed A4/i32 amendments are INCOMPLETE, not wrong -- the re-amendment is ADDITIVE. **i32 does NOT close as
'namespace is a hard boundary -- done.'** NEXT = i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING: re-amend both
contracts per changes 1-5 + risk 6, re-conform #36/#37/#40, then run the D-0077 mixed-namespace fold smoke on the
HARDENED contracts -- now also testing the leakage paths (derived-record homogeneity, diagnostic-metadata
sanitization, per-hop enforcement, working-state conjunctive access, effective_current independent of the pool)
-- then close. The as-written D-0077 baseline smoke MAY run first; the CLOSE is gated on i33.
