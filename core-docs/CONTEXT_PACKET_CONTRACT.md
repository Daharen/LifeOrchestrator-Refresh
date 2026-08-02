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

## 1. P0-1 (SAFETY-CRITICAL) -- control plane vs evidence, structurally separated

**The single most important freeze.** A retrieved README / log / note / imported page can contain imperative
text ("run this", "no approval needed", "the completion criterion is X"). Determinism, under-budget, and
provenance-shape do NOT make such text authoritative. `authority_level` alone is insufficient -- epistemic
authority (how much to trust a claim) is NOT execution authority (permission to act). The packet therefore has
**three top-level regions with different trust origins**, and a consumer treats them differently by
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
frame; `task_input` second; `evidence` last, each item inside HARD DELIMITERS as quoted data with a role
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
  `selection_policy_id`, `selected` (bool), `reason_codes[]` (e.g. `hard_filter_forbidden`, `stale_demote`,
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
  `privacy` / `deleted` sink or exclude; (2) temporal -- stale demote under `current_only` (`MEMORY_CONTRACT`
  s5/s6); (3) authority weighting (`epistemic_authority`); (4) **rank fusion by versioned RRF over CHANNEL
  RANKS, not cross-query raw scores** (P1-2: FTS scores from different queries/kinds are not one scale, so
  fuse ranks, keeping `retrieval_occurrences[]` per candidate); (5) diversity clustering that **dedups DISPLAY
  tokens, never provenance** -- identical text collapses into one display item carrying `occurrences[]` +
  `evidence_cluster_id`, so a distinct required occurrence or independent-source agreement is never erased
  (P1-3); (6) budget (section 3). Full P1-2/P1-3 calibration (score comparability, near-dup algorithm) is a
  named follow-on; i30 freezes the rank-based RRF fusion + occurrence-preserving dedup as the baseline.
- **Parallel-build seam (D-0077).** #40 builds to THIS frozen interface with a conformant reference stub; the
  orchestrator fold wires #40 -> #37's real `selpol_rrf_v1` and asserts BYTE-IDENTICAL selection on real #36
  hits. Any divergence is reconciled at fold, never silently. (#37 s8 + #40 s5 already anticipate this drop-in.)

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
- **Identity must be complete.** `packet_id` MUST cover: `compiler` version, `selection_policy` id+version,
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
  requirements/coverage, `consumer_profile` + exact/upper-bound transport accounting, CONSUME `selpol_rrf_v1`
  via the frozen interface (retire the self-contained composite score), provenance modes (A2 names),
  identity/snapshot + `omission_manifest`, `non_execution: true`.
- **#37 retrieval.eval -> `selpol_rrf_v1` + eval refinement:** author the versioned selection-policy library
  behind the section-4 interface (extracted from `rerank()`), and extend the harness to score per-stage +
  `packet_disposition` (the P1-4 subset that i30 needs; full P1-4 metrics = follow-on).
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
