# Frontier design red-team -- Wave 3 (Collective Agent context compiler + skill retrieval)

**Date:** 2026-08-02 · **Pack:** `d57fead3` (couriered; `read-return` valid, `pack_id_match=true`) ·
**Wave:** i29 (plan `fo-29-87dbfa0b`) · **Decision:** D-0086 · **Follow-on chosen (Nicholas):** i30 CONTRACT-HARDENING.

This is the normative distillate of the off-box frontier review of the Wave-3 design, folded at the i29 close.
The full answer is the pack return file (`modules/31-frontier-bridge/runtime/artifacts/d57fead3-.../
frontier-pack-i29-wave3-design.answer.md`). Governs the i30 hardening scope alongside `MEMORY_CONTRACT.md` +
the directive `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`.

## Verdict

- **GO** for the shipped read-only build (which is exactly what Wave 3 is): context.compiler #40, retrieval.eval
  #37 0.2 + reranker, skill.card #41.
- **NO-GO** for FREEZING the new contracts as written (`context_packet/0.1`, the skill-card format/index, the
  reranker rank semantics, the `skill`-record ownership).
- **NO-GO** for any side-effecting / action-capable integration until the ONE safety-critical fix (P0-1) is
  enforced structurally and tested adversarially. Side-effecting use is a LATER wave (Priority 8+), so this is a
  HARD GATE for the future, not a Wave-3 blocker.
- "The largest architectural risk is not that vector search is deferred. It is that the current contracts could
  make an incomplete or injected packet look fully authoritative merely because it is deterministic, under
  budget, and provenance-shaped. Determinism proves repeatability; it does not prove sufficiency, authority, or
  safety."

## P0 -- contract-freeze blockers (fold into i30 before freeze)

- **P0-1 SAFETY-CRITICAL -- control-plane vs evidence not structurally separated.** A retrieved README/log/note
  could carry imperative text ("run this", "no approval needed") and influence permissions, side-effect
  safety, the completion contract, skill choice, or escalation. `authority_level` alone is insufficient
  (epistemic authority != execution authority). FIX: freeze three packet regions -- `control_plane`
  (policy/permission_grants/request_authority/side_effect_policy/completion_contract; ONLY from the
  coordinator/user-authority store; NEVER from retrieval), `task_input` (user request; requested side effects
  are requests, not authorization), `evidence` (every item `content_role:"evidence"`, `can_instruct:false`,
  trust_domain, epistemic_authority, provenance; rendered in hard delimiters as quoted data). Retrieved records
  cannot create/expand permission grants; skill eligibility + plan validation consult only
  `control_plane.permission_grants`; README/WORK_ORDER prose cannot populate security-critical card fields.
  **Pauses contract-freeze + action-capable integration; read-only compiler/eval work continues behind an
  explicit non-execution boundary.**
- **P0-2 provenance overloaded + underspecified.** `content_hash` has two incompatible meanings across the
  shipped SCHEMA_NOTES (chunk-text hash vs source-version hash); span-reproduction validation cannot say WHAT
  to hash, and derived records (no single source span) don't fit universal span validation. FIX: distinct
  `record_content_hash` / `record_version_id` / `source_version_id` / `source_content_hash` / `excerpt_hash` +
  a `provenance_mode` enum (`direct_span|derived_record|aggregate|tombstone`) with per-mode validation rules.
  **(NOTE: #40 + #37 already kept `content_hash` [source version] vs `chunk_content_hash` [chunk text] as
  DISTINCT fields in their SCHEMA_NOTES -- the i29 D-0077 smoke confirmed provenance reproduces against
  `chunk_content_hash` -- so the split is half-implemented; i30 formalizes it in `MEMORY_CONTRACT` s1/s3 + adds
  the derived/aggregate/tombstone modes.)**
- **P0-3 no fail-closed answerability / evidence-sufficiency.** A packet can be valid, under budget,
  provenance-complete, deterministic, and STILL omit the one required record (dangerous while lexical-only) --
  the 9B then synthesizes from incomplete evidence. FIX: `evidence_requirements[]` + `coverage_results[]` +
  `missing_requirements[]` + `contradictions[]` + a mandatory `packet_disposition`
  (`answerable|needs_expansion|abstain|conflicted|provenance_failed`); a normal answer is permitted ONLY when
  `answerable`; retrieval scores never establish sufficiency.
- **P0-4 "exact" token accounting permits a heuristic.** `ceil(chars/4)` cannot be exact for the 9B tokenizer
  and ignores system/tool/template/delimiter/generation-reserve tokens; transport can exceed context while the
  packet reports "within budget", truncating the completion contract or a required citation. FIX: a mandatory
  `consumer_profile` (model_id/tokenizer_id+fingerprint/chat_template/max_context/reserved_*), count on the
  FINAL RENDERED input, `count_method: exact_tokenizer|conservative_upper_bound` + `count_is_exact`, and
  fail-closed transport.
- **P0-5 two modules own the same logical `skill` record.** #38 repo.intel emits a STRUCTURAL `skill`
  (`skl_...`, `canonical_source`); #41 skill.card emits an ACTIVATION `skill` (`sklcard_...`, `derived`). Both
  are `record_kind=skill`, so a `record_kind=skill` search returns both. FIX (reviewer's preference): #41 emits
  `record_kind=summary` with `attrs.summary_type="skill_activation_card"` + a `derives_from` edge to #38's
  record (fits the CLOSED enum; summaries are navigational derivatives). Alternative: make #41 the sole `skill`
  producer and stop #38. **(NOTE: the i29 D-0077 smoke CONFIRMED no id collision / no supersession -- distinct
  prefixes [joinable suffix], distinct authority, an explicit `describes_structural_skill` cross-link -- so
  this is a record-KIND duplication refinement, not a shipped defect.)**

## P1 -- must fix before "robust"

- **P1-1 reranker vs frozen rank.** Reordering the retriever-0.2 hit array conflicts with "rank=index+1, never
  re-sort". FIX: additive `retrieval_rank`/`fused_rank`/`selection_rank`/`selection_score`/`selection_policy_id`
  + `selected` + reason codes; preserve all channel ranks; ONE selection owner (prefer #40 calling a versioned
  selection-policy library supplied by #37 rather than two rerankers).
- **P1-2 cross-query lexical scores are not one scale.** FTS scores from different queries/kinds aren't
  comparable; a large-magnitude scorer can dominate the packet. FIX: keep `retrieval_occurrences[]` per
  candidate + rank-based deterministic fusion (versioned RRF) until calibration exists; separate hard filters /
  temporal / aggregation / authority / diversity+budget stages; freeze an `epistemic_authority` enum.
- **P1-3 dedup/diversity can erase provenance.** `content_hash` dedup + a hard source cap can drop a distinct
  required occurrence or hide agreement between independent sources (MEMORY_CONTRACT already requires identical
  text to dedup WITHOUT losing occurrences). FIX: cluster (`evidence_cluster_id` + `occurrences[]`), dedup
  DISPLAY tokens not provenance; soft diversity quota with overrides for required/exact/governing/conflicting/
  multi-span; a versioned near-dup algorithm (exact hash != near-dup).
- **P1-4 several eval-0.2 metrics underdefined / wrong stage.** nDCG needs graded relevance; precision@K needs
  judged results; "no-answer FP" is an answer-gen metric; a forbidden hit in the pool != in the packet != shown
  to the model; span reproduction doesn't fit derived records. FIX: add `relevance_grade`/`judgment_status`/
  `required_stage`/`provenance_mode` labels; report metrics per stage (raw retrieval / post-filter / packet /
  answer); mark hybrid metrics `not_applicable` when the vector channel is absent (not zero uplift).
- **P1-5 packet identity / snapshot / expansion lineage incomplete.** Define `task_id` vs `packet_id` vs
  `packet_content_hash` vs `parent_packet_id`/`expansion_id`; canonical serialization + excluded volatile
  fields; identity must include compiler/selection-policy/tokenizer/budget/grant/corpus-snapshot versions +
  selected record-version ids + omission manifest; require one `corpus_version` per compilation (abort on
  drift); expansion returns an immutable delta with a locked snapshot + namespace/sensitivity limits + depth
  bound; rename "omitted-context summary" -> `omission_manifest` (a deterministic list, not prose).
- **P1-6 skill card insufficient for safe selection.** Add `applicability`/`non_applicability`/
  `required_permission_scopes`/`input_schema_refs`/`output_schema_refs`/`effect_set`/`risk_class`/`idempotency`/
  `rollback`/`sandbox_class`/`dependency_constraints`/`health_ref`. Stage-1 must be three-valued
  (`eligible|ineligible|indeterminate`; indeterminate -> ineligible for side-effecting tasks); a degraded card
  must fail closed, not remain selectable; dynamic health referenced live, not baked in.
- **P1-7 skill REFS alone insufficient for a fresh-9B preflight.** Inline compact activation cards
  (`skill_ref`+`activation_card_snapshot`+card hash+eligibility result) for the small eligible candidate set;
  full docs behind expansion. **(NOTE: the i29 D-0077 smoke showed #40 carries skill REFS only + candidate_skills
  was empty for a doc-centric task -- consistent with this finding.)**
- **P1-8 the fresh-9B acceptance gate is too easy.** A model can pass by guessing / answering despite missing
  evidence / obeying an injected instruction. FIX: a held-out deterministic suite (exact-id, paraphrase,
  multi-span, stale-vs-current, conflicting, no-answer, permission-excluded, prompt-injection, expansion-rescue,
  expansion-then-abstain, skill-routing negatives) with synthetic counterfactual facts; grade deterministic
  PROPERTIES (supported claims, correct citations, correct abstention, no execution-authority-from-evidence),
  not model prose; compare correct / empty / missing-group / wrong-source / injected packets.
- **P1-9 an empty vector channel doesn't validate the hybrid interface.** Add a deterministic PRECOMPUTED
  vector-result fixture (known vector ranks) to exercise fusion / vector-rescue / lexical regression /
  stale-forbidden insertion; mark real hybrid quality unmeasured until real vectors exist; don't freeze
  relevance weights on lexical-only results.

## P2 -- hardening

- **P2-1** Use the reranker as a POLICY layer (hard filters, temporal, dedup clustering, diversity, rank
  aggregation), not a tuned relevance model; keep authority/failure/stage weights provisional + versioned;
  per-query regression + held-out set (aggregate uplift must not hide exact-string / safety-query failure).
- **P2-2** Field-aware skill lexical index (purpose/ops high; examples/failure-prose low); return per-field
  match explanations; Stage-2 ranks a broad eligible set, does not promise categorical exclusion.
- **P2-3** Freeze benchmark hooks now (unload/reload, GPU-lease wait, CPU/GPU tok/s, RAM/VRAM peaks, query +
  end-to-end latency, resident-vs-evicted) so the later CPU-vs-GPU-embedding decision (MEMORY_CONTRACT s8) is
  made on total workflow cost.

## What the reviewer would reverse / add

- **Reverse:** the two semi-independent rerankers -> ONE versioned deterministic selection-policy library that
  #40 invokes (P1-1). And #41 emitting another canonical `skill` record -> a derived `summary` activation card
  linked to #38's structural record (P0-5).
- **Add now:** a `context_packet/0.1 -> 0.2` amendment (control/evidence separation; answerability disposition;
  consumer/tokenizer profile; snapshot + expansion lineage; unambiguous provenance hashes+modes); a
  cross-module schema FIXTURE shared by #36/#37/#38/#40/#41 (one canonical sample set, not five restatements);
  an adversarial fold suite (injection / no-answer / stale-current / multi-query aggregation / direct-vs-derived
  provenance / skill-record identity / degraded-card fail-closed / synthetic vector fusion / transport token
  counting).

## i29 D-0077 fold smoke result (orchestrator, real data)

Real chain over a live #36 catalog (core-docs slice, MaxFiles 40): **PASS on the essential interop, no hard
break, no re-ship.** #41 -> #36 `ingest-records`: 40 skill records ACCEPTED, 0 rejected, populated FTS `text`
(via the `ingest_records.json` drop-in), stored `record_kind=skill`, listable + searchable. #36 retriever 0.2
-> #40 `compile`: a real `context_packet/0.1` (3 excerpts, ALL provenance-reproduced against
`chunk_content_hash`, token budget 1190/1200 respected, byte-identical schema). #36 -> #37 0.2: proven by the
worker `-Live` (real slice; recall@1/MRR/nDCG@3=1.0; provenance-VALIDITY flags on #36 `content_hash`-prefix /
CRLF-span / no-chunker-fp = the P0-2 signal). P0-5 coexistence confirmed non-colliding (`sklcard_`/`derived`
vs `skl_`/`canonical_source`). `candidate_skills` empty is CORRECT for the doc-centric fixture task (no skill
card relevant); skill-card retrieval strength is a tuning item (P1-6/P1-7 + the retrieval wave). 0 UNMANAGED
orphans throughout.

## i30 CONTRACT-HARDENING (the chosen follow-on)

Fold P0-1..P0-5 + P1-1 into (a) a `MEMORY_CONTRACT` amendment (formalize the provenance hash split + a packet
contract with control/evidence separation, answerability disposition, consumer/tokenizer profile, snapshot +
expansion lineage) and (b) targeted module revisions: #40 `context_packet/0.1 -> 0.2`; #41 `skill` ->
`summary` activation card (P0-5); one selection-policy library shared by #40/#37 (P1-1). Name **P0-1 a HARD
GATE before ANY side-effecting integration**. Then the P1-2..P1-9 + P2 items, the shared cross-module fixture,
and the adversarial fold suite. Shape (orchestrator-only amendment like i26/i28, vs a small worker wave) TBD at
i30 scoping.
