# CONTEXT_PACKET_CONTRACT -- the Collective Agent context-packet + selection contract (versioned)

Owns the **context packet** (the small, task-specific bundle a deterministic coordinator hands a disposable
model context) and the **selection layer** between retrieval and the packet. This is the second governing
contract of the memory substrate, named alongside `MEMORY_CONTRACT.md` for the D-0077 cross-module-smoke rule.
`MEMORY_CONTRACT.md` owns the record / embedding / retriever / evaluation layer; THIS doc owns everything from
"a ranked retriever-0.2 hit array + a task" to "the packet the model actually consumes". Rationale: the
Wave-3 frontier design red-team `research/2026-08-02-frontier-wave3-design-redteam.md` (P0-1..P0-5, P1-1) and
the directive `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` (sections 4, 8, 9).
This doc is the normative distillate.

## 0. Status, versioning, scope

- **`context_packet/0.2` is the i30 BUILD TARGET (D-0087), not yet a full freeze.** It folds the frontier
  Wave-3 red-team's contract-freeze blockers: **P0-1** (control/evidence separation -- SAFETY-CRITICAL),
  **P0-3** (answerability disposition), **P0-4** (consumer/tokenizer profile + exact transport accounting),
  **P1-1** (one versioned selection-policy library), **P1-5** (packet identity / snapshot / expansion
  lineage). The record-layer blockers **P0-2** (provenance hash split + modes) and **P0-5** (skill.card ->
  `summary` activation card) live in `MEMORY_CONTRACT.md` Amendment A2/A3 and are cross-referenced here.
  `context_packet/0.1` (i29, #40 `b89eda0`) is SUPERSEDED as the target; #40 conforms this wave.
- **Why "target" and not "frozen".** The frontier verdict was NO-GO on freezing the Wave-3 contracts *as
  written*; i30 produces the HARDENED contract and conforms the modules to it, with the D-0077 fold smoke
  catching + reconciling divergences (the i22/i27 pattern). A FULL freeze is gated on the later
  P1-2..P1-9 + P2 items and the adversarial fold suite (a named follow-on) -- until then 0.2 is normative for
  the i30 conformance build and amendable via section 0's protocol.
- **Amendment protocol** (mirrors `MEMORY_CONTRACT.md` s0): change a field frozen here only via a new
  `DECISION_LOG` entry that bumps the packet/selection version, then re-verify each affected module (its
  `SCHEMA_NOTES.md` records the interpretation). Never silently edit a frozen field.
- **The non-execution boundary (load-bearing).** Every `context_packet/0.2` carries `non_execution: true`
  until P0-1 is enforced structurally AND proven by the adversarial injection suite. No side-effecting /
  action-capable consumer may execute from a packet while `non_execution` is true. Read-only compilation +
  evaluation (this wave) proceed behind that flag. This is the HARD GATE named in section 1.
- **i31 (D-0089) PINS the s4 selection scoring** (section 4): the composite relevance-primary score, the
  `epistemic_authority`/freshness RANKS, greedy source-diversity + occurrence-preserving display dedup, and the
  additive output shape are FROZEN as #37's canonical `selpol_rrf_v1`/`1.0.0`; #40 IMPORTS it and its
  `selpol_reference.py` stub is RETIRED. Pure-rank-RRF as the PRIMARY sort stays the deferred P1-2 follow-on.
- **i32 (D-0092) Tier-0 seam repairs.** Realizes the packet/selection half of the seam-audit s3 Tier-0 urgent
  corrections (the record/retriever half = `MEMORY_CONTRACT` Amendment A4); ADDITIVE over 0.2; #40 + #37 conform
  this wave. **(U1) `namespace` is a HARD packet + selection boundary.** `task_input.namespace` (s1) is the
  authoritative compile namespace; the compiler passes it as `params.allowed_namespaces` (a hard filter) to
  `selpol_rrf_v1` AND as `filters.namespace` to the retriever (`MEMORY_CONTRACT` A4). selpol stage 1 (s4) gains
  `hard_filter_namespace` (SINK a cross-namespace candidate); the soft namespace / 'project-match' descriptor
  bonus is RETIRED (component/task_stage/failure/procedural matches remain, intra-namespace). A packet MUST NOT
  carry an evidence item outside `task_input.namespace` (a multi-namespace compile requires an explicit
  `control_plane` grant naming the namespaces); a cross-namespace item reaching selection is a fail-closed
  contract violation. **(U4) `current_only` + supersession-aware selection.** selpol stage 2 (s4, temporal):
  under `current_only` a non-`current` candidate (`MEMORY_CONTRACT` s5) is HARD-filtered (`hard_filter_stale`),
  not soft-demoted (the `stale_penalty` soft demote survives ONLY for the non-current_only modes); supersession
  is rank-affecting -- a superseded candidate whose live successor also survives is ordered strictly below it
  (`superseded_demote`), independent of `selection_score`. A current-vs-current `contradicts` pair (the A4 edge)
  among selected evidence drives `packet_disposition = conflicted` (s2). **(U3) the `working_memory` packet
  region.** The packet gains a FOURTH top-level region **`working_memory`** (distinct from
  `control_plane`/`task_input`/`evidence`): the per-`task_id` evolving state the compiler consults so a deepening
  task distinguishes its own current intermediate state from stale earlier state. Trust: task-authoritative for
  STATE, but NOT execution authority (permissions stay ONLY in `control_plane`) and NOT general evidence; items
  carry `content_role: working_state`, `can_instruct: false`. Render order (s1): `control_plane` -> `task_input`
  -> `working_memory` -> `evidence`. The STORE is Tier 1; Tier 0 RESERVES the region (present in the packet
  shape, empty/absent until the store exists). **(U5) the query-classification stage (seam; router is Tier 1).**
  The compiler front gains a deterministic stage mapping `task_input` (task_type + descriptor) to `query_class`
  in {`exact_reference`, `current_state`, `historical_reconstruction`, `temporal_change`, `local_factual`,
  `global_synthesis`, `causal_diagnosis`, `procedure_selection`, `precedent_search`} (`MEMORY_ARCHITECTURE` s5);
  `query_class` is stamped into `task_input` + the selection descriptor + packet identity (s6) and DRIVES
  selpol's temporal mode (e.g. `current_state`->`current_only`; `historical_reconstruction`->historical). At
  Tier 0 it is a deterministic task_type->class map (a stub); the multi-channel query-aware ROUTER is Tier 1.
  `non_execution: true` (s0) is UNCHANGED -- none of these regions relax the P0-1 gate.
- **i33 (D-0096) NAMESPACE-CLOSURE + SUPERSESSION-HARDENING.** Hardens the packet/selection half after the
  frontier Tier-0 red-team (159e9cb5) found the i32 amendments were an ENVELOPE-level first layer only
  (record/retriever half = `MEMORY_CONTRACT` A5). ADDITIVE over the i32 amendment; #40 + #37 conform this wave.
  **(U1' namespace CLOSURE -- SAFETY-CRITICAL):** `task_input.namespace` is a REQUEST, NOT authorization -- it can
  never WIDEN scope (reconciles P0-1: `control_plane` is the only authority). The compiler computes
  `effective_allowed_namespaces = intersection(task_input.namespace REQUEST, control_plane.permission_grants
  GRANT)` and passes THAT (never raw `task_input.namespace`) to selpol (`params.allowed_namespaces`) and the
  retriever (`filters.namespace`, `MEMORY_CONTRACT` A5); an empty intersection FAILS CLOSED (no compile); no
  implicit all/wildcard/prefix/parent/shared namespace. The scope check covers EVERY packet-visible object, not
  just `evidence[]`: `working_memory`, all provenance/derivation refs, and every diagnostic array -- `ranked[]`,
  `features_by_candidate`, `stages[]`, `retrieval_occurrences[]`, `omission_manifest[]` entries, `expand_hint`s,
  and `evaluation_hooks.retrieved[]`. A cross-namespace item reaching selection or the packet is a fail-closed
  contract violation: the compile ABORTS with `compile_status = failed_closed` + a `namespace_violation_count` and
  NO identifying metadata in the packet (ids/paths/snippets -> a privileged local security log). The one canonical
  `ns_permitted` predicate + rejection policy is IMPORTED (owned by #37, `MEMORY_CONTRACT` A5 risk-6), never
  re-implemented. **(U4' candidate-independent supersession):** selpol's supersession demote uses `MEMORY_CONTRACT`
  A5 `effective_current` computed from the CATALOG (the `superseded_by` chain), not the retrieved pair -- a
  superseded candidate is HARD-filtered under `current_only` even when its successor is absent from the pool; a
  branch (two live successors) -> `packet_disposition = conflicted`; the `superseded_demote` code survives only for
  the non-`current_only` modes where both are shown. `current_only` applies only AFTER temporal intent resolves to
  it (U5'), not universally. **(U2' navigation vs evidence):** selection/compile reserve `candidate_role`
  (`navigation | evidence`) -- a `node`/navigation candidate may ROUTE (multi-stage shortlist -> descend) but is
  NEVER emitted as answer-evidence, and NAVIGATIONAL staleness (`summary_stale`) does not fail an evidence coverage
  requirement (s2); evidence provenance follows `provenance_mode` (A2/A5), so a derived/aggregate item needs no
  single source span. **(U3' working_memory hardening):** the `working_memory` region (i32) is
  CONTINUITY-authoritative (recorded current state of THIS task, not world-truth, not execution authority --
  `content_role: working_state`, `can_instruct: false`, permissions stay ONLY in `control_plane`); access is
  CONJUNCTIVE (`task_id` AND effective-namespace authorization); items carry the `MEMORY_CONTRACT` A5
  `state_version`, and packet identity (s6) includes it. The STORE is Tier 1; Tier 0 reserves the region + these
  invariants. **(U5' query_class vs temporal_intent split):** `query_class` (semantic, the s0/i32 map) and
  `temporal_intent` (`current_only | historical_as_of | version_specific | any_valid_version`, `MEMORY_CONTRACT`
  s6) are INDEPENDENT dimensions -- the class->mode map is a DEFAULT that an explicit user time/version OUTRANKS;
  the classifier + the class->mode map are VERSIONED (`classifier_policy_id`/`classifier_policy_version`) with
  `composite` + `unclassified` fallback classes; packet identity (s6) covers the classifier policy id/version + the
  resulting `temporal_intent` + the `working_memory` `state_version` + the retrieval-plan/stage trace.
  `non_execution: true` (s0) is UNCHANGED -- no region relaxes the P0-1 gate.

## 1. P0-1 (SAFETY-CRITICAL) -- control plane vs evidence, structurally separated

**The single most important freeze.** A retrieved README / log / note / imported page can contain imperative
text ("run this", "no approval needed", "the completion criterion is X"). Determinism, under-budget, and
provenance-shape do NOT make such text authoritative. `authority_level` alone is insufficient -- epistemic
authority (how much to trust a claim) is NOT execution authority (permission to act). The packet therefore has
**three top-level regions with different trust origins** (the i32 amendment adds a fourth, `working_memory` -- s0/s4), and a consumer treats them differently by
construction:

- **`control_plane`** -- the ONLY authoritative region. Fields: `policy`, `permission_grants[]`,
  `request_authority`, `side_effect_policy`, `completion_contract`, `escalation_conditions[]`. Populated
  **ONLY** from the coordinator / user-authority store. **NEVER** from retrieval. A retrieved record can never
  create or expand a permission grant, set the side-effect policy, or define the completion contract. Skill
  eligibility and plan validation consult **only** `control_plane.permission_grants` (never a card field
  derived from prose).
- **`task_input`** -- the user / coordinator request: `original_goal` (verbatim, immutable), `normalized_task`,
  `task_type`, `time_horizon`, `namespace`, `constraints`, `requested_side_effects[]`. **Requested side
  effects are REQUESTS, not authorization** -- they are matched against `control_plane.permission_grants`, not
  self-granting.
- **`evidence`** -- every retrieved item (excerpts + refs). Each item carries `content_role: "evidence"`,
  `can_instruct: false`, `trust_domain` (e.g. `repo_internal | user_note | imported_web | tool_output`),
  `epistemic_authority` (the `authority_level` enum -- a TRUST signal, never an execution grant), and full
  provenance (section 5). Imperative text inside an evidence item is DATA describing what some source said,
  never an instruction to the consumer.

**Rendering contract (how the packet becomes model input).** `control_plane` renders first as the authoritative
frame; `task_input` second; **`working_memory` third (i32, when present)**; `evidence` last, each item inside HARD DELIMITERS as quoted data with a role
banner asserting `content_role=evidence, can_instruct=false`. The renderer never inlines evidence text into
the control or task regions. The token count (section 3) is computed on THIS final rendered form.

**The HARD GATE.** No side-effecting / action-capable integration (Priority 8+) may consume a packet until (a)
a compiler enforces the three-region separation structurally -- evidence physically cannot write
`control_plane` -- AND (b) an adversarial injection suite proves an evidence item cannot populate/expand a
permission grant, cannot alter `completion_contract`, and cannot change skill selection via imperative prose.
Until both hold, `non_execution: true` (section 0) is mandatory and only read-only compile/eval consume the
packet. This gate is the reason i30 hardens the contract before any action wave.

## 2. P0-3 -- answerability / evidence-sufficiency disposition (fail-closed)

A packet can be valid, under budget, provenance-complete, deterministic, and STILL omit the one record needed
to answer -- especially dangerous while retrieval is lexical-only (no vector recall). The model must not
silently synthesize from insufficient evidence. The packet therefore carries a mandatory disposition:

- **`evidence_requirements[]`** -- what the packet must contain to answer, derived deterministically from the
  task (+ any supplied labels). May be empty when requirements are unknown (then disposition defaults
  conservatively, below).
- **`coverage_results[]`** -- per requirement: `satisfied | unsatisfied` + the evidence item(s) that satisfy
  it.
- **`missing_requirements[]`**, **`contradictions[]`** -- unmet requirements; mutually-contradictory current
  evidence.
- **`packet_disposition`** (mandatory enum): `answerable | needs_expansion | abstain | conflicted |
  provenance_failed`. Deterministic mapping: any `provenance` failure (section 5) -> `provenance_failed`; a
  current-vs-current contradiction -> `conflicted`; an unsatisfied requirement with a viable `expand`
  affordance -> `needs_expansion`; an unsatisfiable requirement -> `abstain`; otherwise `answerable`.
- **A normal answer is permitted ONLY when `packet_disposition == answerable`.** Retrieval scores NEVER
  establish sufficiency (a high `fused_score` is not coverage). While the vector channel is EMPTY
  (`MEMORY_CONTRACT` s2/s6), the compiler biases conservative: an unmatched required requirement yields
  `needs_expansion` (if expandable) or `abstain`, never `answerable`.

## 3. P0-4 -- consumer / tokenizer profile + exact transport accounting

`ceil(chars/4)` cannot be exact for the 9B's tokenizer and ignores system / tool / chat-template / delimiter /
generation-reserve tokens; a packet can report "within budget" and still overflow the real context window,
truncating the completion contract or a required citation in transport. The packet therefore carries:

- **`consumer_profile`** (mandatory): `{ model_id, tokenizer_id, tokenizer_fingerprint, chat_template_id,
  max_context, reserved_system_tokens, reserved_tool_tokens, reserved_generation_tokens }`. It names exactly
  which consumer the budget was computed for.
- **Count on the FINAL RENDERED input** (control_plane + task_input + delimited evidence + template scaffolding
  + reserves), not just excerpt bodies.
- **`count_method`** enum: `exact_tokenizer | conservative_upper_bound`, plus **`count_is_exact`** (bool).
  `ceil(chars/4)` is a `conservative_upper_bound` and MUST NOT be labelled exact. When the real tokenizer is
  available (a later wave) `exact_tokenizer` is used; until then the upper-bound is honest and fail-closed.
- **Fail-closed transport.** If `rendered_tokens + reserves > consumer_profile.max_context`, the packet does
  NOT ship as `answerable`: the budget stage drops evidence (recording each in the `omission_manifest`,
  section 6) and re-evaluates disposition (`needs_expansion`/`abstain`), or, if the control_plane +
  task_input alone overflow, the packet is `provenance_failed`-adjacent `abstain` with an explicit
  `transport_overflow` reason. It NEVER silently truncates the completion contract or a required citation.
- The `context_packet/0.1` `token_budget` block (`{token_fn, budget, used, ...}`) is RETAINED for the
  excerpt-fill accounting, but `token_fn` is documented as a heuristic upper bound; the `consumer_profile` +
  final-rendered count is the authority that gates `answerable`.

## 4. P1-1 -- ONE versioned selection-policy library

**The problem the freeze removes: two rerankers.** #40 (context.compiler) shipped a self-contained composite
score; #37 (retrieval.eval) shipped a deterministic `rerank()` measured A/B. Two selection implementations
diverge. The fix is **one versioned deterministic selection-policy library, OWNED by #37, CONSUMED by #40 and
by #37's own eval A/B** -- there is exactly one selection owner.

- **Interface (frozen).** `select(candidates, descriptor, policy_id, params) -> { selected[], ranked[],
  policy_id, policy_version, features_by_candidate }`. Inputs: the retriever-0.2 hit array (`MEMORY_CONTRACT`
  s3) + a unified **selection descriptor** `{ namespace?, component?, relevant_paths?, task_type?, task_stage?,
  time_horizon?, seeking_failures?, permission_context? }` (the reconciliation of #40's task fields and #37's
  `rerank_descriptor`). PURE + deterministic: no model, no I/O, no state.
- **Output is ADDITIVE -- it never destroys the retrieval order.** The library preserves each candidate's
  channel ranks and adds selection fields; per candidate: `retrieval_rank`, `lexical_rank`, `vector_rank`,
  `fused_rank` (from s3, PRESERVED), `selection_rank`, `selection_score` (integer millionths/points),
  `selection_policy_id`, `selected` (bool), `reason_codes[]` (e.g. `hard_filter_forbidden`, `hard_filter_namespace` (i32), `hard_filter_stale` (i32), `superseded_demote` (i32), `namespace_closure_violation` (i33), `stale_demote`,
  `authority_boost`, `fusion_rrf`, `diversity_capped`, `budget_omitted`, `rescued`, `selected`). This resolves
  the P1-1 conflict with "`rank = index+1`, never re-sort": the ORIGINAL retrieval array keeps `rank=index+1`
  untouched; selection produces a SEPARATE `selection_rank` ordering -- reordering is expressed as new fields,
  not by mutating the retrieval array.
- **Ownership + versioning.** `policy_id` is namespaced + versioned, e.g. `selpol_rrf_v1`; the library is a
  single self-contained deterministic module authored in #37 (`modules/37-retrieval-eval/lib/`). #40 imports
  it via a resolved (portable) path and no longer computes its own composite score -- #40's i29 self-contained
  selection is RETIRED and its features fold into the library. `policy_version` is stamped into packet
  identity (section 6) and every eval report.
- **Selection stages (deterministic, versioned baseline).** In order: (1) hard filters -- `forbidden` /
  `privacy` / `deleted` sink or exclude; (2) temporal -- stale demote under `current_only` **(i33: a HARD filter on `MEMORY_CONTRACT` A5 catalog-computed `effective_current`, excluding a superseded candidate even when its successor is absent from the pool)** (`MEMORY_CONTRACT`
  s5/s6); (3) authority weighting (`epistemic_authority`); (4) **rank fusion by versioned RRF over CHANNEL
  RANKS, not cross-query raw scores** (P1-2: FTS scores from different queries/kinds are not one scale, so
  fuse ranks, keeping `retrieval_occurrences[]` per candidate); (5) diversity clustering that **dedups DISPLAY
  tokens, never provenance** -- identical text collapses into one display item carrying `occurrences[]` +
  `evidence_cluster_id`, so a distinct required occurrence or independent-source agreement is never erased
  (P1-3); (6) budget (section 3). i31 (D-0089) PINS this baseline as #37's canonical (the Scoring bullet below);
  near-dup-algorithm calibration (P1-3) + pure-rank-RRF-primary (P1-2) stay named follow-ons.
- **Scoring (PINNED, D-0089).** s4 now pins #37's canonical `selpol_rrf_v1`/`1.0.0` as the one policy (the i30
  fold caught #40's reference and #37's canonical selecting differently -- neither a defect: s4 had frozen the
  interface + stages but not the scoring). PINNED: (a) **relevance-primary = the composite base** `1*raw_relevance
  + 3e6*authority_rank + 6e6*freshness_rank + 2e6*each descriptor match (project/component/task_stage/failure/
  procedural) - 1e9*hard_demote - 2e7*stale_penalty`, ordered by descending `effective = base - 8e6*prior_same_
  source_hits` with the original retrieval rank as tie-break; `raw_relevance` is the retriever's fused/lexical/
  score (MEMORY_CONTRACT s3), NOT rank-RRF. RRF-over-channel-ranks is the `rrf_score` FEATURE + `fusion_rrf` code
  and the fusion rule for a multi-occurrence candidate / dedup cluster ONLY; **pure-rank-RRF as the PRIMARY sort
  is the deferred P1-2.** (b) **authority** = `epistemic_authority` -> AUTHORITY_RANK {authoritative/governing:4,
  curated:3, source_material:2, derived:1}; #40's AUTHORITY_POINTS(40-320) scale RETIRED. **freshness** =
  {current:3, unknown:2, stale:1, deleted/unverified:0}; #40's FRESHNESS_POINTS(0-200) RETIRED. (c) **diversity**
  = greedy source-MMR (the `-8e6*prior_same_source` above) + optional occurrence-preserving DISPLAY dedup by
  `chunk_content_hash` (`evidence_cluster_id` + `occurrences[]`, provenance NEVER erased); #40's excerpt-hash-only
  clustering (no source-MMR) RETIRED. (d) **output** = `select()` -> `{ selected[]=hit COPIES, ranked[]=copies
  preserving retrieval/lexical/vector/fused_rank + selection_rank/selection_score(int millionths)/
  selection_policy_id/selected/reason_codes[]/retrieval_occurrences[]/rrf_score, features_by_candidate,
  omission_manifest[], stages[] }`; #40's id-string `selected[]` + new-row output RETIRED.
- **One owner, imported not reimplemented (D-0089).** #40 IMPORTS #37's canonical `selpol_rrf_v1` by a resolved
  portable path (the i30 `selpol_reference.py` stub is RETIRED) and supplies `params.hard_filter` from
  `control_plane.permission_grants` (+ forbidden/privacy) + relies on candidate `status` for temporal. The D-0077
  fold asserts #40-via-canonical selects byte-identically to a direct `select()` on the same real #36 hits.

## 5. Provenance inside the packet -- modes + hash discipline (P0-2 cross-ref)

The packet's excerpts + refs carry provenance per `MEMORY_CONTRACT.md` Amendment A2 (P0-2), which replaces the
overloaded single `content_hash` with distinct fields: **`record_content_hash`** (the record's own canonical
bytes), **`record_version_id`**, **`source_version_id`**, **`source_content_hash`** (the source file version),
**`excerpt_hash`** (the cited span bytes), and a **`provenance_mode`** enum: `direct_span | derived_record |
aggregate | tombstone`. Per-mode validation:

- `direct_span` -- reading `source[span]` reproduces the excerpt; `excerpt_hash` matches the span bytes; this
  is the i29 packet's reproduction check, now named. (#40 already keeps `content_hash` [source version] vs
  `chunk_content_hash` [chunk text] DISTINCT -- 0.2 renames to A2's canonical names + adds the mode.)
- `derived_record` -- no single source span; validate `derivation_refs` resolve + `record_content_hash`
  matches the record payload (skill cards, summaries, symbols).
- `aggregate` -- lists its constituent record/version ids; validity = all constituents valid.
- `tombstone` -- carries last-known version + deletion-observation provenance; a deleted source resolves here,
  never as a silent miss.

A `provenance` failure on any packet-carried item drives `packet_disposition = provenance_failed` (section 2).

## 6. P1-5 -- packet identity, snapshot, and expansion lineage

- **Distinct ids.** `task_id` (the task) vs `packet_id` (`cpkt_` + content hash -- retained from 0.1) vs
  `packet_content_hash` vs `parent_packet_id` / `expansion_id` (for an expansion delta). Canonical
  serialization + excluded volatile fields are retained from 0.1 (no wall-clock, no `abs_path`, integer-only,
  sorted keys, trailing `\n`).
- **Identity must be complete.** `packet_id` MUST cover: `compiler` version, `selection_policy` id+version, `query_class` + `allowed_namespaces` (i32), **(i33)** `classifier_policy` id+version + the resolved `temporal_intent` + the `working_memory` `state_version` + the retrieval-plan/stage trace,
  `consumer_profile` (tokenizer) id+fingerprint, budget, the `control_plane` grant-snapshot ref,
  `corpus_version`, the selected `record_version_id`s, and the `omission_manifest`. Same task + same corpus
  snapshot + same grants + same profile => identical `packet_id`.
- **One corpus snapshot per compilation.** A single `corpus_version` is pinned for the whole compile; drift
  detected mid-compile ABORTS (no half-snapshot packet).
- **Expansion.** `expand` returns an IMMUTABLE delta (`lifeorch.context_expansion/0.2`) with the corpus
  snapshot LOCKED to the parent packet, `parent_packet_id` + `expansion_id`, namespace + sensitivity limits,
  and a depth bound. It never mutates the parent.
- **`omission_manifest`.** The 0.1 `omitted_context[]` is RENAMED `omission_manifest` -- a deterministic list
  (already a list in 0.1; the name makes it canonical), each entry naming the dropped record, the drop reason
  (`deleted | duplicate_content | source_diversity_cap | max_excerpts | token_budget | transport_overflow |
  hard_filter`), and an `expand_hint`. It is part of packet identity.

## 7. Evaluation seam (retained + extended)

The `evaluation_hooks` block (the #37 seam -- `retrieved[]` per-candidate features + `packet_metrics`) is
retained. 0.2 extends it so #37 can score PER STAGE (raw retrieval / post-filter / packet), score
`packet_disposition` correctness, and run an injection probe asserting no evidence item populated
`control_plane` (the P0-1 read-only check). Metrics remain integer-only, byte-identical on re-run.

## 8. Applies-to + i30 conformance

- **#40 context.compiler -> `context_packet/0.2`:** three-region separation (control_plane / task_input /
  evidence with `content_role`/`can_instruct`/`trust_domain`/`epistemic_authority`), `packet_disposition` +
  requirements/coverage, `consumer_profile` + exact/upper-bound transport accounting, IMPORT the canonical `selpol_rrf_v1`
  directly (D-0089; the i30 `selpol_reference.py` stub RETIRED), provenance modes (A2 names),
  identity/snapshot + `omission_manifest`, `non_execution: true`.
- **#37 retrieval.eval -> `selpol_rrf_v1` (the PINNED canonical, D-0089):** the versioned selection-policy
  library (`modules/37-retrieval-eval/lib/`) is the s4-pinned one owner -- NO behavioral change at i31; #40
  imports it. The harness scores per-stage + `packet_disposition` (the P1-4 subset i30 needs; full P1-4 = follow-on).
- **#41 skill.card -> `summary` activation card** (`MEMORY_CONTRACT` A3 / P0-5): emit `record_kind = summary`
  with `attrs.summary_type = "skill_activation_card"` + a `derives_from` edge to #38's structural `skl_`
  record, so a `record_kind = skill` search no longer returns two owners. Cards surface as EVIDENCE refs in the
  packet, never as a control-plane authority.
- **Each producer/consumer split names THIS doc + `MEMORY_CONTRACT.md` as its shared contract and gets the
  D-0077 orchestrator cross-module smoke at fold.** The i30 smoke exercises: #37 `selpol_rrf_v1` <-> #40
  consumer (identical selection); #41 summary cards -> #36 `ingest_records` -> #40 packet with control/evidence
  separation + `packet_disposition` + provenance reproduced; the P0-1 injection probe (an evidence item with
  imperative text cannot reach `control_plane`).
- **Deferred to a named follow-on (NOT i30):** P0-1 adversarial injection SUITE + the action-capable gate
  release; P1-2/P1-3 calibration (score comparability, near-dup algorithm); P1-4 full eval metric set; P1-6
  richer skill-card fields + three-valued eligibility + degraded-card fail-closed; P1-7/P1-8/P1-9 (inline
  activation cards, the held-out fresh-9B acceptance suite, the synthetic precomputed-vector fixture); the
  P2 hardening; the shared cross-module fixture; a FULL 0.2 freeze.
