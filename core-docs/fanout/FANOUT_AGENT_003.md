# FANOUT_AGENT_003 -- READY (i34 wave scoping)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i34 (plan id `fo-34-45fcbd0d` once planned)
- **Lane:** CODING (CPU; GPU lane skipped this wave)
- **Worker id / label:** w3-router (`40-context-compiler`)
- **Module/area (exclusive):** `modules/40-context-compiler/` ONLY (context.compile 0.5.0 -> 0.6.0)
- **GPU:** false
- **Docs:** `[]`

## Mission
Build the MEMORY_ARCHITECTURE **Tier 1** multi-channel **query ROUTER** into #40's compiler front: turn the
i32/i33 query-classification STUB into a real query-aware routing planner that classifies the information need and
routes across retrieval channels + the #36 hierarchy (shortlist-and-descend) + current-only/supersession modes +
the new `working_memory` region -- keeping the P0-1 non-execution gate + namespace closure intact. Governs:
`MEMORY_ARCHITECTURE.md` s5 (planner + channels + fast/slow), s9-s10 (Tier 1); `CONTEXT_PACKET_CONTRACT.md`
i32 (U5 classification stage), i33 (U5' query_class vs temporal_intent split, U2' navigation-vs-evidence, U3'
working_memory region), s4 (selpol import), s6 (packet identity); `MEMORY_CONTRACT.md` A5 (U5'). #40 is the
CONSUMER in this wave's D-0077 cross-module smoke -- it consumes #36's shortlist-and-descend (slot 001) + #42's
working-memory store (slot 002) + #37's shipped canonical libs (READ-ONLY).

## Unit (the full worker prompt)
You are the #40 context.compiler worker for i34. Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md`
(esp. Known failures) + `CONTEXT_PACKET_CONTRACT.md` (i32/i33) + `MEMORY_ARCHITECTURE.md` s5 first; obey
`SKILL_CONTRACT.md`. Do ONE unit in `modules/40-context-compiler/` only; `docs:[]`; ship via `dev.ship`.

**SCOPE IN (context.compile 0.5.0 -> 0.6.0, additive; `context_packet/0.2` shape unchanged; `non_execution: true`
STAYS):**
1. **Query classification -> `query_class` (CONTEXT_PACKET_CONTRACT i32 U5 / i33 U5').** Consume #37's SHIPPED
   canonical `lib/classifier_policy.py` (IMPORT READ-ONLY by a resolved portable path -- do NOT re-implement, do
   NOT modify #37) to map `task_input` (task_type + descriptor) to `query_class` in {`exact_reference`,
   `current_state`, `historical_reconstruction`, `temporal_change`, `local_factual`, `global_synthesis`,
   `causal_diagnosis`, `procedure_selection`, `precedent_search`} with `composite` + `unclassified` fallbacks.
2. **`query_class` vs `temporal_intent` SPLIT (i33 U5').** They are INDEPENDENT dimensions: the class->temporal-mode
   map is a DEFAULT that an explicit user time/version (`temporal_intent` in {`current_only`, `historical_as_of`,
   `version_specific`, `any_valid_version`}, MEMORY_CONTRACT s6) OUTRANKS. Stamp `classifier_policy_id` +
   `classifier_policy_version` + the resolved `temporal_intent` into `task_input` + the selection descriptor +
   **packet identity (s6)** (packet_id MUST cover classifier id/version + resolved temporal_intent + the
   `working_memory` `state_version` + the retrieval-plan/stage trace).
3. **The ROUTER (the new Tier-1 build).** A deterministic, VERSIONED routing planner (the router policy is #40-
   owned; #37 owns the classifier only) that, per `query_class`, selects the retrieval STRATEGY: which channels to
   request (channel set FROZEN-OPEN -- request by NAME, never hard-code `{lexical, vector}`), whether to use #36's
   **`shortlist_and_descend`**
   (e.g. `global_synthesis` -> descend the hierarchy; `local_factual`/`exact_reference` -> flat/ID) and what
   temporal mode to pass (`current_state` -> `current_only`; `historical_reconstruction` -> historical). Emit the
   `retrieval_plan_id` + per-stage trace (multi-stage: shortlist -> descend), NOT one flat top-k. Keep selection
   hierarchy-AGNOSTIC at the candidate-pool interface (no new flat-top-k-only hardening).
4. **`candidate_role` navigation vs evidence (i33 U2').** A `node`/navigation candidate from #36 MAY ROUTE the
   descend but is NEVER emitted as answer-evidence; NAVIGATIONAL staleness (`summary_stale`) does not fail an
   evidence-coverage requirement (s2). Evidence provenance follows `provenance_mode` (A2/A5) -- a derived/aggregate
   item needs no single source span.
5. **The `working_memory` packet REGION (i32 U3 / i33 U3').** Consult #42's working-memory store (slot 002) via its
   `get_active_head` read op, CONJUNCTIVE (`task_id` AND effective namespace). Render it as the FOURTH region in
   order `control_plane -> task_input -> working_memory -> evidence`; items carry `content_role: working_state`,
   `can_instruct: false`; permissions stay ONLY in `control_plane`. Include the working `state_version` in packet
   identity. Until the store returns state, the region is empty/absent (do not fabricate).
6. **Namespace closure intact (i33 U1').** `effective_allowed_namespaces = intersection(task_input.namespace
   REQUEST, control_plane.permission_grants GRANT)`; pass THAT (never raw request) to selpol + the retriever; empty
   intersection FAILS CLOSED. The scope check covers EVERY packet-visible object incl `working_memory` + all
   diagnostic arrays + the retrieval-plan trace. Import #37's canonical `ns_permitted` (do NOT re-implement).
   selpol import (`selpol_rrf_v1`, READ-ONLY) is UNCHANGED from 0.5.0.

**SCOPE OUT:** NO changes to #37 (import its classifier + namespace + selpol libs READ-ONLY) or #36 or #42 (build
to their DESIGNED interfaces + mock/seam them for the off-machine gate; the orchestrator fold proves the real
chain). NO new retrieval CHANNELS actually implemented (route by name; only the live channels + #36 descend
execute). NO relaxing `non_execution: true`. NO action-capable / side-effecting use.

**GATES.** Off-machine cloud gate FIRST (mock #36 descend + #42 read + real #37 libs) -> `-Live` on the executor
-> `dev.ship`. Prove packet identity determinism (same task + corpus snapshot + grants + profile -> identical
packet_id) WITH the new identity coverage; prove a routing decision per query_class is deterministic + versioned;
prove the working_memory region renders in order + never as control-plane authority; prove namespace closure holds
across the plan trace. Record every interpretation in `modules/40-context-compiler/SCHEMA_NOTES.md` (D-0077 shared
contract). Report plainly if a seam is impractical (D-0061).

## Rails
Standing rules: `core-docs/fanout/FANOUT_AGENT_TEMPLATE.md`. Acquire res.lease in gpu->git->doc order (git only);
release on exit. ONE unit, module-exclusive, `docs:[]`. Import #36/#37/#42 interfaces READ-ONLY; never edit them.
Gate off-machine first, then `exec-job.sh devship`; 0 orphaned llama-server/python. Report: `-Action report
-PlanId fo-34-45fcbd0d -WorkerId w3-router -State done` + a plain measured summary.

## Verification
- `query_class` derived from #37's canonical classifier; `temporal_intent` overrides the class default when a user
  time/version is explicit; classifier id/version + resolved temporal_intent stamped into packet identity.
- Router: a deterministic, versioned `retrieval_plan` per query_class; `global_synthesis` routes to
  `shortlist_and_descend`, `local_factual`/`exact_reference` to flat/ID; channels requested by NAME (no
  `{lexical,vector}` hard-code); multi-stage trace + `retrieval_plan_id` present.
- `candidate_role`: navigation hits route but never appear as evidence; `summary_stale` navigation does not fail
  coverage.
- `working_memory` region: consulted conjunctively from #42, rendered third, `can_instruct:false`,
  `state_version` in packet identity; empty when the store is empty.
- Namespace closure: intersection(request,grant) passed everywhere; empty -> fail-closed; every packet-visible
  object + diagnostic array + plan trace scope-checked; `ns_permitted` byte-identical to #37 canonical.
- packet_id deterministic + covers the new identity fields; `non_execution:true`; suite green (mock producers
  off-machine) + `-Live`; `SCHEMA_NOTES.md` updated.

## Report-back record
_(Orchestrator fills from `plans/fo-34-45fcbd0d/reports/` before archiving.)_
