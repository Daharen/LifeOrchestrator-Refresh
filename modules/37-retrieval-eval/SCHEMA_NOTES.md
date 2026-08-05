# SCHEMA_NOTES -- retrieval.eval (Module 37, contract v0.5 / eval-0.5 + selpol_rrf_v1 1.2.0, plan fo-33-d7b55e46, RETRIEVAL-EVAL-PREDICATE-i33; prior: v0.4 / eval-0.4 + selpol 1.1.0, fo-32-0fb25203, s14; v0.3 / SELECTION-POLICY-i30, s9-13)

**REQUIRED by D-0077.** This module is BOTH the CONSUMER side of a retriever pair (it calls the real
`artifact.search` #36 retriever-0.2 at fold / its own lexical baseline now, and scores the ranked hits + #40's
packets) AND, as of i30, the PRODUCER of the ONE versioned selection-policy library `selpol_rrf_v1`
(CONTEXT_PACKET_CONTRACT s4 / P1-1) that the context compiler #40 consumes. This doc records EVERY schema +
interface interpretation the harness + library code against, so the orchestrator's cross-module fold can wire
the real `artifact.search` behind this harness, consume the reranker seam, and assert
#40-with-its-reference-impl == #40-with-this-canonical-`selpol_rrf_v1` (byte-identical selection) without
guessing. **i30 sections 9-13 (selpol_rrf_v1 + eval-0.3) are the load-bearing D-0087 record; sections 1-8 are
the shipped eval-0.2 record, unchanged in behavior.**

Governing (FROZEN, D-0083; on any conflict this contract + its live gates win, never silently edited):
`core-docs/MEMORY_CONTRACT.md` -- **s6 (evaluation gates)** = the primary spec here, plus **s3** (the
retriever-0.2 hit I consume + my reranker emits) and **s5** (the staleness enum). Design doc:
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` s8.3 (reranking + diversity),
8.6 (context-quality signals), 9 Stage 4 (reranker), 11.1 (retrieval verification), Priority 2. Decisions:
D-0080/D-0082/D-0083/D-0084/D-0085, D-0077 (the cross-module smoke rule).

This 0.2 EXTENDS the shipped 0.1 (recall@K / MRR / stale-source / provenance-presence + forbidden-hit
rate). The shipped 0.1 benchmark + metric VALUES stay regression-green; the report gains fields (new
canonical bytes, re-pinned). Both the shipped 0.1 and the eval-0.2 benchmark run through the SAME code path.

---

## 1. The retriever-0.2 hit I CONSUME (MEMORY_CONTRACT s3; and my reranker RE-EMITS)

Op `search`: `{ query, k, filters? }` -> a **ranked hit array in DETERMINISTIC order**; the consumer treats
array position as rank (`rank = index + 1`) and NEVER re-sorts. I consume the s3 frozen hit and, where a
field is absent, coerce it (a retriever-0.1 hit is still accepted -- see section 2). `normalize_hit()`
produces one canonical internal hit carrying:

| field | source (0.2) | 0.1 fallback / coercion |
|---|---|---|
| `source_path` | s3 (POSIX-normalized: `\`->`/`, leading `./` stripped) | same |
| `content_hash` | s3 = the **SOURCE VERSION identity** (the document/file bytes hash) -- what provenance validation checks | `content_hash`, else `source_version_id`/`version_id` |
| `chunk_id` | s3 physical handle | same |
| `chunk_content_hash` | s3 (the chunk's own text hash) | `""` (then near-dup detection falls back to path+span) |
| `span_start` / `span_end` | s3 `span:{start,end}` BYTE offsets | a 0.1 string span -> null offsets |
| `span_label` | s3 `span_label` (section path, else `bytes:S-E`) | the 0.1 `span` string, else `bytes:S-E`, else `""` |
| `record_id` / `record_version_id` / `record_kind` | s3 | null |
| `status` / `currentness` | s3 (the s5 STRING enum) | null (unknown) |
| `authority_level` | s3 | null |
| `namespace`, `source_version_id`, `embedding_space_id`, `section_path`, `heading`, `chunk_type` | s3 | null / coerced |
| PER-CHANNEL: `retrieval_channels`, `lexical_rank`+`lexical_score`, `vector_rank`+`vector_similarity`, `fused_rank`+`fused_score`, `fusion_algo`+`fusion_version`, `index_snapshot`/`corpus_version`, `filter_decisions`, `tie_break_key` | s3 | absent -> the vector channel reads EMPTY; ordering score falls back to the retired opaque `score` |
| `token_count`, `snippet` | s3 | coerced |

The **ordering score** the harness uses is `fused_score` (else `lexical_score`, else the retired opaque
`score`). It is used ONLY to feed the reranker's direct-relevance feature; the harness never re-sorts the raw
order. `content_hash` = SOURCE VERSION identity is the field required-source labels match on and provenance
validation checks (NOT the chunk text hash `chunk_content_hash`) -- the two #36 roles are kept distinct here.

### How the harness reaches a retriever

- **`lexical_baseline`** (shipped; the KNOWN floor) -- BM25-lite over a fixture corpus, now emitting FULL
  retriever-0.2 hits: `span:{start,end}` BYTE offsets + `span_label` (heading path / line range), record ids
  (`srec_`/`occ_` derived from immutable inputs), `content_hash` = the EOL-normalized FILE version hash,
  `chunk_content_hash` = the chunk-text hash, `status='current'`, `authority_level='source_material'`,
  `retrieval_channels=['lexical']`, `lexical_rank/score`, `vector_rank/vector_similarity=null`,
  `fused==lexical`, `fusion_algo='lexical_only'`, `chunker_fingerprint='ck:md1txt1:bm25lite/1'`. Rank key
  `(-score_millionths, source_path, chunk_id)`. Chunks with zero query-term overlap are never returned.
- **`external_command`** (the FOLD seam -> the real #36 `search`): invoke a conforming retriever as a
  subprocess; `{query,k,filters}` via stdin|file|arg; stdout parsed as JSON; `hits_pointer` (default
  `result.hits`) navigates to the ranked array. `tests/fixtures/mock-retriever.py` is a conforming example;
  `mock2-plan.json` carries canned retriever-0.2 hits.

---

## 2. Benchmark schema `lifeorch.retrieval_benchmark/0.2` (eval-0.2 LABELS, s6) + 0.1 compat

The 0.1 schema (required_sources/stale_sources/forbidden_sources; span as a string) is STILL accepted and
migrated (temporal_intent defaults to `current_only`). New in 0.2, per query (all optional; a 0.1 query runs
unchanged):

- **`temporal_intent`** (s6): `current_only` | `historical_as_of` | `version_specific` | `any_valid_version`.
  The shipped rule "a stale required source is always a miss" holds ONLY for `current_only`; version-specific
  / historical intent treats an archived/superseded version as the WANTED answer (labelled at its hash), not a
  miss. Invalid values fail closed.
- **`evidence_groups`**: `[{group_id, mode:"all"|"any", members:[member]}]`. `all` = must_include_all (every
  member must be matched somewhere in depth); `any` = must_include_any (>=1). Coverage = satisfied/total.
- **`required_sources`** (kept, 0.1): the recall/MRR label set. Each is a MEMBER (below).
- **member** = `{ source_path, content_hash?, chunk_id?, span?:{start,end}|"string", span_label?,
  require_span?, span_start?, span_end?, acceptable_spans?:[...], must_reproduce_text? }`. A hit MATCHES a
  member iff `source_path` == AND (if `content_hash`) version == AND (if `chunk_id`) chunk == AND (if a span
  is constrained) the byte span or `span_label` equals one of {the member span} + `acceptable_spans`.
  **CHUNK-LEVEL CREDIT (s6): a FILE-level hit is NOT sufficient -- a wrong chunk from the right file does not
  score** (fixture `b1-deploy-current`: the file appears at rank 1 but the required *chunk* is only credited
  at K=5).
- **`stale_sources`** / **`forbidden_sources`** (kept) + **`privacy_exclusions`** (new: a hard privacy label
  -- a source that must NEVER surface; reported as a distinct privacy-hit rate) + **`distractors`** (new:
  attractive-but-wrong sources; a returned distractor is judged irrelevant / a no-answer false positive).
- **`no_answer_expected`** (new): the corpus lacks an answer; a good system abstains. no-answer FALSE POSITIVE
  = returning a labelled distractor (or, if none labelled, any hit) within depth.
- **`rerank_descriptor`** (new): `{namespace?, component?, task_stage?, seeking_failures?}` -- the deterministic
  task/query descriptor fed to the reranker (section 6). Absent -> a query-only descriptor.
- metadata (recorded, echoed, non-numeric): `label_rationale`, `label_status`, `reviewer`, `corpus_snapshot`.
- top-level `tombstones:[{source_path}]` (a deleted source is validatable via a tombstone, s4).
- top-level `provenance_corpus_dir` -- the source-of-truth corpus hits are validated against (section 5).

---

## 3. The lexical baseline (deterministic, KNOWN) + byte spans

Unchanged BM25-lite scoring (`k1`,`b`; non-negative BM25+ idf; score_unit millionths; stable tie-break). NEW:
- **byte spans.** Markdown chunks (ATX heading; a preamble is its own chunk) and text chunks (blank-line
  paragraph) now carry `span:{start,end}` = the BYTE offsets of the segment in the file's UTF-8 EOL-normalized
  bytes, plus `span_label` (the heading path / `(lines a-b)`). `_line_byte_offsets` + `_seg_byte_span` compute
  them; reading `bytes[start:end]` reproduces the segment (the basis of provenance validation).
- **content_hash is EOL-normalized** (BOM stripped, CRLF/CR->LF) so a Windows (CRLF) vs cloud (LF) checkout
  hashes IDENTICALLY -- the labelled hashes are stable regardless of git EOL handling.

---

## 4. Metrics (s6 / 11.1) -- definitions. All ratios are integer **ppm**, round-half-up. NO float in output.

Kept (0.1, values regression-green): **recall@K** (macro = mean of per-query ppm; micro = sum matched / sum
required), **MRR**, **stale-source rate** (fraction of queries with >=1 explicit-stale/wrong-version hit),
**provenance completeness** (fraction of returned hits with source_path+content_hash+chunk_id+span all
present), **forbidden-hit rate** (fraction of queries with >=1 forbidden hit in depth).

Added (0.2):
- **precision@K** = relevant-in-topK / min(K, returned); relevant = matches a required source or an
  evidence-group member (version + chunk correct), each positive label credited once (a duplicate hit earns
  no extra relevance).
- **nDCG@K** = DCG@K / IDCG@K; DCG uses a fixed module-level millionths log2 discount table (computed once at
  import; `gain_i * PPM / log2_millionths(i+1)`), IDCG over min(K, distinct relevant labels). Binary gain.
  Determinism: the ratio rounds to ppm and is covered by the SAME cross-env byte-identity gate that pins the
  BM25 baseline (verified byte-identical cloud CPython 3.11 == the pinned values; the -Live executor
  re-asserts it).
- **evidence-group coverage** = satisfied groups / total groups (aggregate = mean over queries with groups).
- **stale-hit rate** = fraction of returned HITS that are stale (status in the s5 stale enum, or an
  explicit-stale/wrong-version match). Distinct from the query-level stale-source rate.
- **duplicate / near-dup burden** = fraction of returned hits that repeat an already-seen `chunk_content_hash`
  (else path+span) -- catches "ten near-duplicate results crowding out distinct evidence" (8.3).
- **source diversity@K** = distinct source_paths in top-K / K.
- **provenance VALIDITY** (section 5) = fraction of returned hits that pass ALL validation checks (distinct
  from presence).
- **snippet-span correctness** = fraction of hits whose snippet derives from the span AND whose span
  reproduces the cited text.
- **judged-irrelevant rate** = fraction of returned hits matching a distractor/forbidden/privacy/stale label.
- **relevant-token ratio** = relevant-hit tokens / total returned-hit tokens.
- **no-answer false-positive rate** = fraction of `no_answer_expected` queries that surfaced a distractor
  (else any hit).
- **hybrid uplift / regression** (section 7) + the **reranker A/B** (section 6).
- Query **latency + resource** (s6) are measured into the VOLATILE `worker-summary.json`
  (`resource.eval_wall_ms`), NEVER the canonical report (determinism forbids wall-clock in report.json).

`report.json` (`lifeorch.retrieval_eval_report/0.2`) = `{ schema, generator, benchmark_id, benchmark_schema,
retriever{kind}, input_digest, provenance_validated, vector_channel_status, corpus?, aggregate_raw{...},
aggregate_reranked{...}, rerank_ab{queries_with_rescue, queries_with_demote, deltas, per_query},
rerank_diagnostics[], hybrid_attribution[], per_query_raw[...], per_query_reranked[...] }`. Canonical: UTF-8
no BOM, sorted keys, compact, one trailing LF, integer-only, NO volatile fields; byte-identical on re-run
cross-machine. `input_digest` = sha256 of the canonical {report_schema, benchmark queries, retriever spec
(minus corpus_dir), corpus source hashes, k_values, retrieval_depth}.

---

## 5. Provenance VALIDATION (s6, not presence)

For every scored hit, validated against the `provenance_corpus_dir` (the source-of-truth files; defaults to
corpus_dir / the baseline's corpus). `validate_provenance()` returns a hit `provenance_valid` bool + the list
of failed checks. Checks:
1. **presence** -- source_path + content_hash + chunk_id + span all non-empty.
2. **fingerprint_known** -- the hit carries a `chunker_fingerprint`.
3. **status_in_enum** -- status is null or in the s5 enum.
4. **source_exists_or_tombstoned** -- the source_path exists in the corpus, or is tombstoned, or status=deleted.
5. **content_hash_matches_source** -- the hit's content_hash == the corpus file's EOL-normalized version hash.
6. **span_in_bounds** -- `0 <= start <= end <= len(bytes)`.
7. **snippet_derives_from_span** -- `collapse_ws(bytes[start:end])` starts with the hit's snippet.
8. **span_reproduces_cited_text** -- if a member gives `must_reproduce_text`, it appears in the span text.
9. **status_correct** -- a labelled explicit-stale hit must NOT claim `current`; a current corpus version must
   be `current`; a wrong/superseded version must be stale. (This is why the lexical baseline -- which labels
   everything `current` -- scores provenance validity 964286 ppm on the shipped benchmark: validation
   correctly flags the archived stale copy's status.)
When no validation corpus is available at all, the file-dependent checks degrade to presence + format and the
report sets `provenance_validated=false`. Fixture `mq-c-badspan` proves check 7/8 FAIL when a returned span
does not reproduce the cited text (provenance INVALID even though recall@1=1).

---

## 6. The DETERMINISTIC RERANKER (directive 8.3 / Stage 4; NO model) -- I/O = the retriever-0.2 hit array

`rerank(hits, descriptor, q)` takes the retriever-0.2 hit array + a task/query descriptor and returns the SAME
hit-array shape REORDERED (a drop-in for #40's selection + a later retrieval wave). Per-hit deterministic
feature score (fixed integer weights, documented in `retrieval_eval.py` `RERANK_W`), combined then diversified:

- **direct relevance** = the hit's fused/lexical score (millionths), weight 1.
- **authority** = `AUTHORITY_RANK{authoritative/governing:4, curated:3, source_material:2, derived:1}`, x3 PPM.
- **freshness/currentness** = `current:3`, stale enums:1, `deleted`/`unverified`:0, unknown:2, x6 PPM.
- **project match** = descriptor.namespace == hit.namespace, x2 PPM.
- **component match** = hit.source_path startswith descriptor.component (path prefix), x2 PPM.
- **task-stage match** = hit.record_kind in `TASK_STAGE_KINDS[descriptor.task_stage]`, x2 PPM.
- **failure likelihood** = descriptor.seeking_failures AND record_kind==failure, x2 PPM.
- **procedural applicability** = descriptor.task_stage in {act,implement} AND record_kind==procedure, x2 PPM.
- HARD demote (`-1000 PPM`): a forbidden / privacy / `deleted` hit sinks to the bottom.
- stale penalty (`-20 PPM`, current_only only): a stale / wrong-version hit is demoted below current.
- **DIVERSITY** (8.3): greedy MMR-style selection -- repeatedly pick the highest
  `base - 8*PPM*(already-selected hits from the same source_path)`, ties broken by the ORIGINAL rank (lower
  first). Prevents near-duplicates from one source crowding out distinct evidence. Fully deterministic.

The harness MEASURES it: it evaluates BOTH the raw retriever order and the reranked order and reports
`aggregate_reranked` + `rerank_ab` = per-metric deltas (nDCG@K, precision@K, recall@K, evidence-group
coverage, forbidden/stale-hit rate) + `queries_with_rescue` (a required source pulled INTO the smallest
top-K) + `queries_with_demote` (a forbidden/stale hit pushed out of top-1). Fixtures `mq-b`/`mq-d`: raw top-1
is forbidden with the current required source lower; reranking RESCUES the required source to rank 1 (recall@1
0 -> 1, nDCG@1 delta +500000 ppm) and DEMOTES the forbidden hit out of top-1.

---

## 7. Hybrid attribution (s6, MANDATORY) -- from the retriever-0.2 per-channel diagnostics

`hybrid_attribution()` reads each hit's `retrieval_channels` + `lexical_rank` / `vector_rank` / `fused_rank`
(it NEVER re-runs retrieval -- the retriever owns channels + fusion; the s3 per-channel diagnostics exist for
exactly this). Per query it reports: lexical/vector hit counts; results unique to each channel; required
sources rescued by vectors (present in the vector channel but not lexical); lexical exact-match harmed by
fusion (`fused_rank > lexical_rank`); stale/forbidden introduced by a channel; whether fusion reordered vs the
pure-lexical order. **The vector channel runs EMPTY today** (no vectors this wave, per MEMORY_CONTRACT s2/s6
and #36 s5): every `vector_rank`/`vector_similarity` is null, so `vector_hit_count=0`, rescued-by-vector=0,
and the run reports top-level `vector_channel_status: "empty"` cleanly -- the scaffolding is ready for the
retrieval wave without blocking on real vectors.

---

## 8. Fold notes (for the orchestrator's D-0077 smoke, D-0077)

To point this harness at the real `artifact.search` #36 retriever-0.2: author a benchmark whose `retriever`
is an `external_command` spec invoking #36's `search` op with `hits_pointer` at its ranked hits, required
labels using #36's `content_hash` (the SOURCE VERSION identity) + byte spans, and `provenance_corpus_dir` =
the real corpus root. The harness needs NO change: baseline + real retriever run the same code path; the
deterministic report compares retrieval quality (raw + reranked) with source-resolved provenance validity.
The orchestrator also scores REAL #40 `context_packet/0.1` packets with this 0.2 harness at fold (D-0077):
the packet's selected hits are retriever-0.2 hits -> the same metrics + provenance validation apply. If #36's
hit omits a byte span or mislabels status, provenance validity reports it below 1.0 -- the intended signal.
The reranker seam (`rerank()`; retriever-0.2 hit array in -> reordered out) is the drop-in #40's selection and
a later retrieval wave consume.

---

## 9. `selpol_rrf_v1` -- the ONE selection-policy library (CONTEXT_PACKET_CONTRACT s4, P1-1) -- i30

**File:** `lib/selpol_rrf_v1.py` (self-contained; stdlib `hashlib` only). **Owner:** #37. **Consumers:** #40
(the context compiler) + this harness's own reranker A/B. This removes the two-reranker problem: there is
exactly ONE selection implementation.

**Frozen s4 signature (verbatim):**
`select(candidates, descriptor, policy_id="selpol_rrf_v1", params=None) -> { selected[], ranked[], policy_id,
policy_version, features_by_candidate, omission_manifest[], stages }`. `policy_id='selpol_rrf_v1'`,
`policy_version='1.0.0'`; an unknown `policy_id` fails closed (ValueError).

- **Inputs.** `candidates` = the MEMORY_CONTRACT s3 retriever-0.2 hit array (normalized: each hit carries
  `rank` [retrieval rank], `lexical_rank`, `vector_rank`, `fused_rank` + scores, `status`, `authority_level`,
  `namespace`, `record_kind`, `source_path`, `chunk_id`, `chunk_content_hash`, `span_start/end`, `token_count`,
  `snippet`, `retrieval_channels`). `descriptor` = the UNIFIED selection descriptor (the s4 reconciliation of
  #40's task fields + #37's `rerank_descriptor`): `{namespace?, component?, relevant_paths?, task_type?,
  task_stage?, time_horizon?, seeking_failures?, permission_context?}`.
- **PURITY (load-bearing).** No model, no I/O, no state, no wall-clock, no randomness. `candidates` is NEVER
  mutated -- every returned hit is a COPY. The library reads ONLY its arguments, so it stays pure: the caller's
  POLICY SIGNALS (what it is permitted / labelled to demote) come in via `params`, NOT via a scan of ground
  truth. #40 supplies `hard_filter` from `control_plane.permission_grants` / `permission_context` and relies on
  the candidate's OWN s5 `status` for temporal demote; #37's eval wrapper maps its benchmark labels into the
  same `params` (section 11). Determinism is byte-verified (double-run identity + the cross-env pins).
- **`params` (policy knobs + signals):** `rrf_k(int=60)`, `weights{}`, `authority_rank{}`, `hard_demote`,
  `stale_penalty`, `diversity_penalty`, `current_only(bool)`, `dedup_display(bool=False)`,
  `hard_filter[{source_path, content_hash?, reason}]`, `stale[{source_path, content_hash?}]`,
  `required_versions[{source_path, content_hash}]`, `budget{max_selected?, max_tokens?, per_item_overhead?}`.
  `descriptor.time_horizon == "current_only"` also enables the temporal stage.

**STAGES (deterministic, versioned baseline), in order, each accruing `reason_codes[]` + features:**
1. **hard filters** -- a candidate matching `hard_filter` (forbidden/privacy) OR `status=="deleted"` is
   hard-demoted (`-hard_demote`, default 1000 ppm-points) and `selected=False`; reason `hard_filter_<reason>`.
2. **temporal** -- under `current_only`, a candidate whose `status` is in the s5 stale enum, OR matches
   `stale`, OR is a wrong version of a `required_versions` source, is demoted (`-stale_penalty`, 20 ppm-points);
   reason `stale_demote`.
3. **authority** -- `epistemic_authority` weighting via `AUTHORITY_RANK` (a TRUST signal, never execution
   authority); reason `authority_boost`.
4. **rank fusion (RRF over CHANNEL RANKS -- P1-2).** `retrieval_occurrences[]` = the candidate's per-channel
   ranks (`lexical`/`vector`; else one `retrieval` occurrence from `fused_rank`/`rank`). `rrf_score` =
   sum over occurrences of round-half-up(`PPM / (rrf_k + rank)`), integer. Reason `fusion_rrf` on every
   candidate. When a candidate carries >1 occurrence (multi-channel, or the dedup cluster of stage 5) the RRF
   genuinely fuses multiple ranks -- the P1-2 problem (raw FTS scores from different queries/kinds are not one
   scale, so fuse RANKS, keeping occurrences).
5. **diversity + occurrence-preserving dedup (P1-3).** Greedy source-diversity ordering (a per-source penalty,
   `diversity_penalty` 8 ppm-points per already-selected same-source hit; ties -> original rank). When
   `dedup_display=True`, identical TEXT (`dedup_key` = `chunk_content_hash`, else source+span) collapses into
   ONE display item carrying `occurrences[]` (each folded member's `{record_version_id, source_path, chunk_id,
   content_hash, retrieval_rank, channels}`) + a stable `evidence_cluster_id` (`ec_`+sha16(dedup_key)); the
   cluster's `rrf_score` is re-fused over the UNION of member channel ranks. **Provenance is NEVER erased** --
   folded members stay in `ranked[]` flagged `selected=False` + reason `display_duplicate`, and their
   provenance lives in the head's `occurrences[]`.
6. **budget.** `max_selected` / `max_tokens` (cost = `token_count` or ceil(chars/4) of the snippet +
   `per_item_overhead`); overflow -> `selected=False` + reason `budget_omitted` + an `omission_manifest[]`
   entry `{record_version_id, source_path, chunk_id, reason(max_selected|token_budget), selection_rank}`.

**ADDITIVE output (never re-sorts the retrieval array in place).** Each `ranked[]` item is a COPY that
PRESERVES `retrieval_rank` + `lexical_rank`/`vector_rank`/`fused_rank` and ADDS `selection_rank`,
`selection_score` (= the effective score = base - diversity penalty; integer, monotonic with selection_rank),
`selection_policy_id`, `selected`(bool), `reason_codes[]` (deterministic, de-duplicated, stable stage order:
`rescued, hard_filter_*, stale_demote, authority_boost, fusion_rrf, diversity_capped, display_duplicate,
budget_omitted, selected`), `retrieval_occurrences[]`, `rrf_score`, and (a cluster head) `occurrences[]` +
`evidence_cluster_id`. `reason_codes` gains `rescued` when `selection_rank < retrieval_rank`. `selected[]` =
the display items within budget, in selection order. `features_by_candidate[key]` = the per-hit feature
breakdown (`relevance, authority, freshness, project, component, task_stage, failure, procedural, hard_demote,
stale, rrf_score, occurrence_count, base_score, diversity_penalty, effective_score, selection_rank, selected,
reason_codes`) -- what #40's eval hooks + this A/B consume.

## 10. How the shipped `rerank()` maps onto the library (baseline-compat -- the regression freeze)

The shipped standalone `rerank()` is RETIRED and re-expressed as `selpol.rerank_compat(candidates, descriptor,
params)` = `select(..., dedup_display=False)` adapted back to `(reordered_hits, diagnostics)`. The DEFAULT
policy scoring IS the shipped `_rerank_base` composite EXACTLY: direct relevance = the retriever's `fused_score`
(else `lexical_score`/`score`), weight 1; + authority x3 ppm x `AUTHORITY_RANK`; + freshness x6 ppm x
`_fresh_rank(status)`; + project/component/task_stage/failure/procedural x2 ppm each; - hard_demote (forbidden/
privacy/deleted); - stale_penalty (current_only); greedy source-diversity. Because that scoring, the greedy
loop, and the tie-break `(-effective, original_rank)` are ported byte-for-byte, `select(dedup_display=False)`
reproduces the shipped reranked ORDER, and `rerank_compat` reconstructs `rerank_diagnostics`
(`source_path, chunk_id, from_rank, to_rank, features{the 9 legacy keys}, base_score, diversity_penalty,
effective_score`) IDENTICALLY. VERIFIED: the shipped-0.2 `aggregate_raw / aggregate_reranked / rerank_ab /
rerank_diagnostics / hybrid_attribution / per_query_raw / per_query_reranked` are byte-identical after the
refactor (only the report SCHEMA version + additive fields changed).

**Baseline-compat interpretation (recorded for the fold).** i30 freezes the rank-based RRF fusion +
occurrence-preserving dedup as the BASELINE; the DEFAULT policy's direct-relevance term stays the retriever's
`fused_score` (itself the retriever's fused output per s3) so the frozen baseline order is preserved and the
regression is green. `rrf_score` is emitted as a first-class feature + `fusion_rrf` reason code and IS the
fusion rule when a candidate carries >1 occurrence (multi-channel or a dedup cluster); in the single-occurrence
lexical-only wave it is a strictly rank-monotonic restatement of the retriever order, so it never contradicts
the baseline. **Replacing the raw-score direct-relevance term with pure rank-RRF as the PRIMARY sort -- which
changes ordering -- is the named P1-2 score-comparability follow-on**, exactly as CONTEXT_PACKET_CONTRACT s4
defers it (with P1-3 near-dup calibration + P1-9 the synthetic precomputed-vector fixture that would exercise
multi-channel RRF end-to-end).

## 11. The eval wrapper's label -> policy-signal mapping (`_policy_params_from_query`)

The eval reranker measures an oracle-ish upper bound off the benchmark LABELS, so the harness maps them into the
library's pure `params` (it does NOT leak labels into the library): `forbidden_sources`+`privacy_exclusions`
-> `hard_filter` (with `reason`); `stale_sources` -> `stale`; each `required_source` with a `content_hash` ->
`required_versions` (wrong-version staleness); `temporal_intent=="current_only"` -> `current_only`. `deleted`
staleness comes from the candidate's own `status`. This is the ONLY place benchmark ground truth touches
selection; #40 will instead pass `hard_filter` from `control_plane.permission_grants` and rely on candidate
`status` -- the SAME library, a different signal source, so the D-0077 fold's byte-identity assertion holds.

## 12. eval-0.3 refinement -- per-stage + `packet_disposition` (P0-3 / P1-4 subset)

- **Per-stage metrics.** `stage_metrics{raw, post_filter, packet}` + full `aggregate_packet`. `raw` = the raw
  retriever order (`aggregate_raw`); `post_filter` = the reranked order (`aggregate_reranked` -- hard filter +
  temporal + authority + RRF + diversity, NO display dedup, NO budget); `packet` = the PACKET-stage selection
  (`select_packet` = `select(dedup_display=True, budget)` -> `selected[]`). The packet stage is where the
  occurrence dedup + budget bite: e.g. two byte-identical near-duplicates score `duplicate_burden > 0` at raw
  and `0` at packet.
- **`packet_disposition` (P0-3).** `PACKET_DISPOSITIONS = answerable | needs_expansion | abstain | conflicted |
  provenance_failed`. `packet_disposition_eval` scores the disposition against a query's
  `expected_packet_disposition` label. The `actual` disposition is READ from a supplied #40 packet
  (`query.context_packet.packet_disposition`) when present -- the fold path -- ELSE computed deterministically
  from the packet-stage selection (CONTEXT_PACKET_CONTRACT s2 mapping, i30 subset): any provenance-invalid
  selected hit -> `provenance_failed`; a `no_answer_expected` query with a non-empty packet -> `needs_expansion`
  (empty -> `abstain`); an unmet required requirement -> `needs_expansion` when the source appears in raw
  retrieval (expandable) else `abstain`; otherwise `answerable`. `conflicted` is a reserved hook (no
  current-vs-current contradiction labels in the i30 fixtures). Aggregate = `{scored, num_labeled, num_correct,
  accuracy_ppm, per_query[{query_id, expected, actual, computed, supplied, source, correct}]}`.
- **Hybrid `not_applicable` (P1-4).** `hybrid_applicability = {vector_channel, status:
  not_applicable|applicable, note}`. While the vector channel is EMPTY the status is `not_applicable` (NOT zero
  uplift) -- the existing per-query `hybrid_attribution` counts stay (vector_hit_count=0) so the shipped VALUE
  assertions are preserved; the applicability marker is additive.
- **Report schema.** `lifeorch.retrieval_eval_report/0.3`. Additive top-level fields over 0.2:
  `selection_policy`, `hybrid_applicability`, `aggregate_packet`, `stage_metrics`, `packet_disposition_eval`,
  `per_query_packet`; `returned[]` gains the additive selection fields (`retrieval_rank`, `selection_rank`,
  `selection_score`, `selection_policy_id`, `selected`, `reason_codes`, `evidence_cluster_id`,
  `occurrence_count`). Every shipped-0.2 metric VALUE is unchanged; the canonical pins are re-computed for the
  larger shape (byte-identical cross-env; double-run gate).

## 13. Fold + #40 consumption recipe (D-0077)

- **#40 imports the library by a resolved path** (it is self-contained stdlib): e.g.
  `importlib.util.spec_from_file_location("selpol_rrf_v1", "<repo>/modules/37-retrieval-eval/lib/selpol_rrf_v1.py")`.
  #40 retires its i29 self-contained composite score and calls `select(candidates, descriptor,
  'selpol_rrf_v1', params)` with `dedup_display=True` + its token budget to build the packet's `excerpts[]` +
  `omitted_context`/`omission_manifest` + the additive selection fields; `descriptor` carries #40's task fields
  (namespace/component/relevant_paths/task_type/time_horizon/permission_context) and `hard_filter` comes from
  `control_plane.permission_grants`. The fold asserts BYTE-IDENTICAL selection between #40's reference impl and
  this canonical library on real #36 hits.
- **What P1-4 is DEFERRED (named follow-on, not i30):** graded `relevance_grade` / judged `judgment_status`
  precision + nDCG; the `required_stage` / `provenance_mode` label plumbing beyond the i30 subset; the held-out
  fresh-9B acceptance suite (P1-8); the synthetic precomputed-vector fixture that would exercise multi-channel
  RRF + vector-rescue end-to-end (P1-9). The eval accepts these labels additively (ignored when absent) so the
  follow-on is plumbing, not a schema break.

## 14. i32 (D-0092) -- folding the CONTEXT_PACKET_CONTRACT amendment into `selpol_rrf_v1` 1.0.0 -> 1.1.0 + eval 0.3 -> 0.4

The Tier-0 memory-architecture seam repairs. selpol is the PRODUCER of the selection semantics; #40 IMPORTS the
canonical library and the orchestrator runs the D-0077 selpol byte-identity smoke at fold. Governing:
`CONTEXT_PACKET_CONTRACT.md` s4 (PINNED, D-0089) + its i32 amendment (s0), `MEMORY_CONTRACT.md` Amendment A4,
`MEMORY_ARCHITECTURE.md` s5 (query classes) + s9 (Tier-0 invariants). Every change is ADDITIVE; a 1.0.0 caller
that supplies NONE of the new signals gets BYTE-IDENTICAL selection (proof below).

**Stage list (i32).** `POLICY_VERSION 1.0.0 -> 1.1.0`; `STAGES` grows to eight:
`namespace_filter -> hard_filter -> temporal -> supersession -> authority -> rank_fusion_rrf -> diversity -> budget`
(namespace_filter + supersession are the i32 additions). The `select()` result adds `contradicts_pairs[]`,
`temporal_mode`, and `allowed_namespaces` (additive; the frozen `selected/ranked/policy_id/policy_version/
features_by_candidate/omission_manifest/stages` surface is unchanged). New reason_codes fold into the stable
sort order additively: `hard_filter_namespace`, `hard_filter_stale`, `superseded_demote` (inserted so the
relative order of the pre-i32 codes is preserved -> default-path reason_codes are byte-identical).

**(U1) `hard_filter_namespace` + soft-bonus retirement.** `params.allowed_namespaces` (a set/list/str; normalized
to a `frozenset`, or `None`) is a HARD boundary: a candidate whose `namespace` is not in the set is SUNK
(`base -= hard_demote`, `selected=False`, reason `hard_filter_namespace`), exactly like `hard_filter_forbidden`.
An explicit EMPTY set fails closed (filters everything). **The soft namespace/'project-match' descriptor bonus is
RETIRED the moment allowed_namespaces is supplied** (the `project` feature weight contributes 0;
component/task_stage/failure/procedural descriptor matches REMAIN, intra-namespace). Interpretation resolving the
"retire the soft boost" vs "absent-param byte-identical to 1.0.0" tension: the retirement is CONDITIONAL on the
hard boundary being engaged -- **absent `allowed_namespaces`, the 1.0.0 soft project bonus is preserved
byte-for-byte** (back-compat). #40 ALWAYS supplies `allowed_namespaces` (from `task_input.namespace` / the
`control_plane` grant naming the namespaces), so in production the soft boost is always retired and namespace is a
hard packet+selection boundary (a cross-namespace item reaching selection is a fail-closed contract violation).

**(U4) `current_only` HARD stale filter + `prefer_current` soft relocation.** selpol resolves an effective
temporal MODE (below) instead of a bare boolean. Under `current_only`, a candidate that is stale -- its own s5
`status` in `STALE_STATUSES`, OR matched by an eval `stale[]` label, OR a `required_versions` content_hash
mismatch -- is HARD-filtered (`hard_filter_stale`, excluded), NOT soft-demoted. **The 1.0.0 soft `stale_penalty`/
`stale_demote` SURVIVES ONLY for the non-current_only `prefer_current` mode** (it reproduces the old
current_only-soft arithmetic, so a caller wanting the pre-i32 behavior selects `temporal_mode="prefer_current"`).
`any`/`historical_as_of`/`version_specific`/`any_valid_version` apply NO temporal action (stale allowed).
**Intended semantic change, documented:** a 1.0.0 caller that passed `current_only=True` AND had a stale
candidate now gets HARD exclusion where 1.0.0 soft-demoted -- this is the A4 semantic and what the D-0077 fold
requires. It is the ONLY divergence from 1.0.0; a current_only call on all-`current` candidates is byte-identical.
(Shipped selpol unit test 5's stale assertion was updated from `stale_demote` to `hard_filter_stale`
accordingly; a new prefer_current test covers the surviving soft path.)

**(U4) `superseded_demote` (rank-affecting).** A separate stage AFTER greedy diversity ordering: a STABLE
topological reorder of the surviving (non-hard-filtered) candidates so that whenever a superseded candidate AND
its live successor BOTH survive, the successor precedes the superseded one (reason `superseded_demote` on the
superseded), independent of `selection_score`. The base (stage-5 diversity) order is the tie-break, so with NO
supersession edges the reorder is the IDENTITY permutation (byte-identical). Supersession is read from the
candidate/hit, channel-agnostically: `superseded_by` (str|list of successor ids) and/or `supersedes` (str|list of
records THIS supersedes) and/or `edges`/`record_edges` entries `{type: "superseded_by"|"supersedes", target|
target_record_version_id|target_record_id}`. Identities match on `record_version_id` then `record_id`. Cycles
(should not occur) are broken deterministically by base order.

**(U4) `contradicts` PROPAGATION (not detection).** selpol reads `contradicts` (str|list) / an `{type:
"contradicts", target}` edge and surfaces every unordered pair of SELECTED items linked by it in the result's
`contradicts_pairs[]` (sorted; ids are `record_version_id`/`record_id`) and stamps `contradicts_with` on the
involved features. This drives #40's `packet_disposition = conflicted`. selpol PROPAGATES the edge only --
detection is Tier 2 and is NOT done here. (The eval's `compute_packet_disposition` keeps `conflicted` as a
reserved hook -- the disposition is #40's job; the eval only MEASURES `queries_with_contradicts`.)

**(U5) `query_class` -> temporal mode (deterministic Tier-0 stub) + OPEN channels.** `descriptor.query_class`
(or `params.query_class`) maps to the temporal mode as the deterministic DEFAULT when `current_only`/
`temporal_mode` are not explicitly set. `QUERY_CLASS_TEMPORAL_MODE` (the 9 `MEMORY_ARCHITECTURE` s5 classes):
`current_state -> current_only` and `procedure_selection -> current_only` (ask for the current truth / a current
healthy procedure -> HARD-exclude stale); `local_factual -> prefer_current` and `global_synthesis ->
prefer_current` (prefer current facts but do not exclude -> SOFT demote); `exact_reference -> version_specific`,
`historical_reconstruction -> historical_as_of`, `temporal_change -> any_valid_version`, `causal_diagnosis ->
any_valid_version`, `precedent_search -> any_valid_version` (identity-pinned or inherently historical -> allow
stale). Rationale: only classes that inherently ask "what is true NOW" hard-exclude; the historical/temporal/
identity classes must not drop the stale sources they need; the two "scope" classes soft-prefer current. This is
an explicit Tier-0 STUB -- the multi-channel query-aware ROUTER is Tier 1 -- so the map is small, auditable, and
easily refined. **Channels stay OPEN (U5):** `_occurrences_of` now honors an explicit `retrieval_occurrences[]`
(`[{channel,rank}]`) channel-AGNOSTICALLY, so a novel graph/temporal/statistics channel FUSES through RRF with
NO code change (lexical+vector are no longer hard-coded); a hit WITHOUT `retrieval_occurrences` derives exactly
the 1.0.0 set (byte-identical).

**Temporal-mode resolution precedence (pure):** explicit `params.current_only is True` > explicit
`params.temporal_mode` (a known mode string) > `descriptor.time_horizon == "current_only"` > the `query_class`
map > a direct `descriptor.time_horizon` mode string > `any` (the byte-identical default).

**1.0.0 -> 1.1.0 REGRESSION PROOF (selpol unit test 13, pins captured from selpol 1.0.0).** The SELECTION output
(`ranked`/`selected`/`omission_manifest`) is BYTE-IDENTICAL for: the default path with descriptor bonuses
(ranked sha `47179d1d...`); `current_only=True` on all-`current` candidates (ranked sha `ca885642...`); and a
forbidden+dedup+budget mix (ranked sha `d364068b...`, omission sha `4f53cda1...`). `features_by_candidate` grows
three ADDITIVE diagnostic keys (`namespace_filtered`, `temporal_mode`, `is_stale`); the pre-existing feature
keys are unchanged and the 9 legacy keys the shipped A/B report emits are unchanged, so the shipped eval
reports stay regression-green at the metric-value level (`rerank_compat` is the same thin wrapper).

**eval 0.3 -> 0.4 (the SCORING).** `GENERATOR_VERSION 0.4.0`, report schema `lifeorch.retrieval_eval_report/0.4`,
skill.json `0.4.0`/contract `0.4`. The wiring: `_policy_params_from_query` + `default_descriptor` +
`normalize_query` pass `allowed_namespaces` (U1) and `query_class` (U5) through to selpol when the benchmark
supplies them (absent -> back-compat: the soft project path + no namespace filter). `temporal_intent` forces
`current_only` ONLY when NO `query_class` is present, so a `query_class` (the #40-aligned path) DRIVES the mode.
`normalize_hit` now PRESERVES `superseded_by`/`supersedes`/`contradicts`/`record_edges` (U4). A NEW
`selection_conformance` report block (aggregate + `per_query_selection_conformance`) MEASURES, integer-only +
byte-identical on re-run: **namespace isolation** (a labeled cross-namespace distractor must NOT be selected ->
`namespace_isolation_violations`), **current_only correctness** (a status-stale candidate must not be selected
under current_only -> `current_only_stale_leaks`), **supersession ordering** (a selected successor above its
superseded twin -> `supersession_order_violations` / `supersession_pairs_correct`/`_total`), and **reason-code
coverage** (`reason_code_coverage`). NEW fixture `benchmark4.json` (+ `benchmark4-plan.json`, a canned
retriever-0.2 stream via `mock-retriever.py`) exercises all four with real cross-namespace / status-stale /
supersession-edge / contradicts candidates; the existing fixtures report the new metrics trivially (0 violations)
and every shipped RAW/reranked/packet metric VALUE is PRESERVED (the current_only hard filter did not move any
pinned K-window metric -- verified). Report SHA + input_digest pins were re-computed (the version string + the
new block change the bytes); `REPORT_SCHEMA` is part of `input_digest`, so all input_digests changed too.

**Fold notes for #40 (D-0077 selpol byte-identity smoke, i32 mixed-namespace).** #40 imports the canonical
`selpol_rrf_v1` (per D-0089, path-resolved) and must pass: `params.allowed_namespaces` (from
`task_input.namespace` + any `control_plane` grant) so namespace is a HARD boundary; `descriptor.query_class`
(from its query-classification front) OR an explicit `current_only`/`temporal_mode` so the temporal mode is
resolved; and rely on each candidate's own s5 `status` + `superseded_by`/`supersedes`/`contradicts` edges (from
#36's retriever-0.2 hits) for the temporal + supersession + contradicts stages. The fold asserts #40-via-canonical
selects BYTE-IDENTICALLY to a direct `select()` on the same real #36 hits: zero cross-namespace leakage,
superseded ordered below successor, stale excluded under current_only, a `node`/reserved kind additively
ingested + never selected out-of-namespace, deterministic `packet_id`. selpol carries NO catalog/packet logic --
it consumes the hit array + descriptor + params only.

## 15. i33 (D-0096) -- NAMESPACE-CLOSURE + SUPERSESSION-HARDENING: selpol 1.1.0 -> 1.2.0 + eval 0.4 -> 0.5

The frontier Tier-0 red-team (pack `159e9cb5`, `research/2026-08-04-tier0-amendment-redteam.md`) found the i32
amendments were a correct ENVELOPE-level FIRST layer but INCOMPLETE. i33 hardens the selection/predicate half.
selpol is the PRODUCER of the ONE canonical namespace predicate + the selection semantics + the versioned
class->intent map; #36 (retriever) + #40 (compiler) CONSUME them; the orchestrator runs the D-0077
mixed-namespace leakage-path smoke at fold. Governing: `CONTEXT_PACKET_CONTRACT.md` s4 (PINNED, D-0089) + its
i33 amendment (s0); `MEMORY_CONTRACT.md` Amendment A5 (U1'..U5' + risk 6); `MEMORY_ARCHITECTURE.md` s5 (query
classes) + s9. Every change is ADDITIVE; a 1.1.0 caller that supplies NONE of the new signals gets
BYTE-IDENTICAL selection (the s13 regression pins stay green for 1.2.0 -- proof below). `POLICY_VERSION
1.1.0 -> 1.2.0`; `GENERATOR_VERSION 0.5.0`; report schema `lifeorch.retrieval_eval_report/0.5`; skill.json
`0.5.0`/contract `0.5`.

**(U1' risk-6) The ONE canonical namespace predicate + rejection/sanitization policy -- NEW `lib/namespace_policy.py`.**
Authored ONCE here (owned by #37), IMPORTED by #40, and MIRRORED by #36's retriever (the D-0077 fold asserts
byte-identical accept/reject across the three); NEVER re-implemented per module. It is PURE + stdlib-only.
- `ns_permitted(candidate_namespace, effective_allowed) -> bool`: CLOSED-SET membership ONLY. True IFF the
  candidate namespace is EXACTLY a member of the caller-supplied closed set. NO wildcard / prefix / parent /
  child / shared / `all` expansion. A `None` or EMPTY `effective_allowed` permits NOTHING (fail-closed). A
  candidate with no namespace (`None`) is never permitted (cannot be proven in-scope).
- `effective_allowed_namespaces(request, grant) -> frozenset`: the ONE scope computation =
  `intersection(REQUEST, GRANT)`. `task_input.namespace` is a REQUEST (never authorization); the control_plane
  grant is the authority; neither widens the other; a `None`/empty request OR grant OR intersection => the EMPTY
  set (fail-closed). #40 computes this and passes the RESULT as `params.allowed_namespaces` (selpol treats it as
  a closed set and never widens it).
- `NamespaceRejectionPolicy`: the sanitized rejection policy. Its caller-visible surface is ONLY
  `violation_count` + `caller_summary()` (`{namespace_violation_count, namespace_closure_violated}`); the
  identifying detail (namespace, ids, paths, the effective set, stage) accumulates in the privileged
  `security_log`, intended for a PRIVILEGED LOCAL security sink and MUST NOT reach a packet/caller.
selpol ENGAGES closure whenever `params.allowed_namespaces` is supplied: a candidate that fails `ns_permitted`
is DROPPED BEFORE scoring and NEVER enters `scored[]`/`ranked[]`/`selected[]`/`features_by_candidate`/
`omission_manifest` -- so no cross-namespace identifying data can leak through ANY selection-output diagnostic
array (the i32 "sink to the bottom but keep in ranked[]" was the leak; i33 REPLACES it). The result carries the
SANITIZED surface `namespace_violation_count` + `namespace_closure_violated` + `namespace_policy_id/version`;
a caller (#40) may pass `params.rejection_policy` (a `NamespaceRejectionPolicy`) to CAPTURE the privileged log,
else the detail is discarded (safe default). ABSENT `allowed_namespaces` = the unscoped back-compat path (no
closure, soft project bonus preserved) -> byte-identical to 1.1.0.

**(U4' candidate-INDEPENDENT supersession).** The temporal stage consumes a per-candidate `effective_current`
BOOLEAN that #36 computes from the CATALOG (`status == current` AND no valid reachable live successor within
scope at the pinned snapshot) -- POOL-INDEPENDENT. When present it is AUTHORITATIVE: under `current_only` a
candidate with `effective_current == False` is HARD-filtered (`hard_filter_stale`) EVEN when its successor is
ABSENT from the candidate pool (the i32 by-construction demote was pool-DEPENDENT -- the defect). Absent the
signal, selpol falls back to the 1.1.0 `is_stale` test (byte-identical). A NEW s5 value `superseded` is added to
`STALE_STATUSES` (a 1.1.0 corpus never carried it -> additive). The demote-ORDERING (non-current_only modes)
prefers the catalog successor ref `effective_current_successor` (falling back to the `superseded_by`/`supersedes`
edges) so a surviving live successor is ordered STRICTLY ABOVE its surviving superseded predecessor
(`superseded_demote`). A branch -- `effective_current_branch == True` (the catalog saw TWO live successors) --
is surfaced (never a silent pick) in the result's `supersession_conflicts[]` + a `conflicted` reason on the
branch candidate + the top-level `conflicted` flag, for #40's `packet_disposition = conflicted`. The pool-dependent
supersession EXCLUSION is RETIRED; the reorder + branch engage only when their signals are present (byte-identical
otherwise). selpol scope-checks its OWN diagnostics: `contradicts_pairs`/`supersession_conflicts`/`features` only
reference SURVIVING in-scope candidates (cross-namespace candidates are dropped before they can be referenced);
selpol relies on the A5 no-cross-namespace-edge invariant (#36-enforced) for pass-through edge fields.

**(U5' query_class vs temporal_intent split) -- NEW `lib/classifier_policy.py`.** `query_class` (SEMANTIC) and
`temporal_intent` (TEMPORAL: `current_only | historical_as_of | version_specific | any_valid_version`) are
INDEPENDENT dimensions. The versioned `CLASS_TO_TEMPORAL_INTENT` map (`classifier_policy_id = clsmap_v1` /
`classifier_policy_version = 1.0.0`) is the DEFAULT; `resolve_temporal_intent(query_class, explicit_temporal_intent,
explicit_version)` makes an EXPLICIT user `temporal_intent` (one of the 4-value enum) OUTRANK the class default,
and an explicit version request -> `version_specific`. `composite` + `unclassified` are first-class FALLBACK
classes (-> `any_valid_version`). The class->intent map: `current_state`/`procedure_selection -> current_only`;
`exact_reference -> version_specific`; `historical_reconstruction -> historical_as_of`; every other class + the
two fallbacks -> `any_valid_version` (stale ALLOWED). Rationale: ONLY a class that inherently asks "what is true
NOW" defaults to the HARD current_only exclude; temporal is NOT a security boundary (namespace is), so the other
classes never silently drop a valid record -- the red-team's caution against over-freezing current_only as the
universal mode. #40's compiler front owns the task_type -> query_class STAGE; this module owns the class -> intent
MAP + the resolver (#40 imports them). selpol maps the resolved CONTRACT intent to its INTERNAL action mode
(`current_only` -> HARD exclude; the 1.1.0 soft `prefer_current` survives as an EXPLICIT-ONLY `params.temporal_mode`
back-compat, no longer a class default). The result stamps `temporal_intent` + `temporal_intent_source` +
`classifier_policy_id/version` for #40's packet identity (CONTEXT_PACKET_CONTRACT s6). Channels stay OPEN
(U5, unchanged): `retrieval_occurrences[].channel` is DATA; an explicit list fuses a novel channel with no code
change. Temporal-mode resolution precedence (pure): explicit `params.current_only is True` > explicit
`params.temporal_mode` (a known INTERNAL mode incl. `prefer_current`) > `descriptor.time_horizon == 'current_only'`
> the versioned intent resolver (explicit `temporal_intent` > explicit version > `query_class` default) engaged
ONLY when a class/intent/version signal is present > a raw `descriptor.time_horizon` mode > `any` (the
byte-identical default).

**eval 0.4 -> 0.5 (the MEASUREMENT).** `normalize_hit` PRESERVES the A5 catalog signals
(`effective_current`/`effective_current_successor`/`effective_current_successors`/`effective_current_branch`).
`_policy_params_from_query` + `normalize_query` pass `allowed_namespaces` (the CALLER-computed effective set),
`query_class` (the class default), and an explicit `explicit_temporal_intent`/`version_specific` (the U5' override,
which outranks the class); `temporal_intent` forces `current_only` ONLY when NEITHER a query_class NOR an
explicit_temporal_intent is present. The `selection_conformance` block (aggregate + `per_query_selection_conformance`)
MEASURES, integer-only + byte-identical on re-run: **U1' namespace CLOSURE** (`cross_namespace_candidates` present
BUT `cross_namespace_selected == 0` AND `cross_namespace_in_ranked == 0` -- the diagnostic-array leak check the i32
sink-in-place failed -- plus the sanitized `namespace_violation_count`/`namespace_closure_violated`); **U4'
pool-INDEPENDENT current_only** (`noncurrent_selected_under_current_only == 0` over `noncurrent_candidates`, using
the pool-independent `effective_current` verdict); **U4' supersession ordering + branch** (`supersession_order_ok`,
`supersession_conflicts`); **U5' the class/intent split** (`temporal_intent` + `temporal_intent_source` +
`classifier_policy_id/version`); and **reason-code coverage**. NEW fixture `benchmark5.json` (+ `benchmark5-plan.json`,
a canned retriever-0.2 stream via `mock-retriever.py`) exercises all five paths with a cross-namespace distractor
that OUTSCORES the answer (dropped), a superseded high-scorer whose successor is ABSENT (excluded under
current_only), a supersession chain (successor above predecessor), a two-successor branch (conflicted), and a
`query_class=current_state` + `explicit_temporal_intent=any_valid_version` override (stale not excluded). The
report `selection_policy` block additionally stamps `namespace_policy_id/version` + `classifier_policy_id/version`
(packet-identity fields #40 imports). The shipped 0.4 fixtures report the new metrics with 0 violations and every
RAW/reranked/packet metric VALUE is PRESERVED (the closure DROP does not move a pinned K-window metric --
verified; the only shape change is the cross-namespace distractor no longer appearing in `benchmark4`'s ranked[]
+ `reason_code_coverage`, i.e. `hard_filter_namespace` is no longer a surfaced code because the candidate is now
DROPPED, sanitized). All report SHA + input_digest pins were re-computed (the version string + the new fields +
the sanitized drop change the bytes; `REPORT_SCHEMA` is part of `input_digest`).

**1.1.0 -> 1.2.0 REGRESSION PROOF (selpol unit test s13, pins captured from selpol 1.0.0, verified for 1.2.0).**
The SELECTION output (`ranked`/`selected`/`omission_manifest`) is BYTE-IDENTICAL for: the default path with
descriptor bonuses (ranked sha `47179d1d...`); `current_only=True` on all-`current` candidates (ranked sha
`ca885642...`); a forbidden+dedup+budget mix (ranked sha `d364068b...`, omission sha `4f53cda1...`). Every i33
stage engages ONLY when its signal is present (allowed_namespaces / effective_current / a resolved current_only /
supersession refs / effective_current_branch / query_class / temporal_intent), so the no-signal call reproduces
1.1.0 exactly. `features_by_candidate` grows two ADDITIVE diagnostic keys (`effective_current_supplied`,
`not_current`) -- not hashed by the s13 pins; the result grows the additive i33 keys listed in the module header.

**Fold notes for #40 (D-0077 selpol byte-identity + mixed-namespace LEAKAGE smoke, i33).** #40 imports the
canonical `selpol_rrf_v1` AND `lib/namespace_policy.py` (path-resolved). It MUST: compute
`effective_allowed_namespaces = intersection(task_input.namespace, control_plane grant)` via the canonical helper
and pass the RESULT as `params.allowed_namespaces` (never the raw request); pass its resolved `query_class` +
any explicit user `temporal_intent`/version so the temporal mode resolves; rely on each candidate's #36-supplied
`effective_current` (+ `effective_current_successor`/`_branch`) for the pool-independent temporal + supersession
stages; and route `params.rejection_policy.security_log` to a privileged local sink (NEVER into the packet). The
fold asserts #40-via-canonical selects BYTE-IDENTICALLY to a direct `select()` on the same real #36 hits AND, on
a mixed-namespace catalog (ns-A + ns-B + a superseded/absent-successor pair + a reserved `node` + a `working`
record), that ZERO ns-B data appears in evidence OR any diagnostic array, the superseded predecessor is excluded
pool-independently under current_only, a branch drives `conflicted`, and the `packet_id` is deterministic. selpol
carries NO catalog/packet logic -- it consumes the hit array + descriptor + params only.

---

## i34 Tier-1 HIERARCHY eval (D-0098, plan fo-34-584fd656, HIERARCHY-EVAL-i34) -- 0.5.0 -> 0.6.0

ADDITIVE: `retrieval_eval.py` + `selpol_rrf_v1`/`namespace_policy`/`classifier_policy` are UNCHANGED (the
shipped benchmark path is byte-identical -- the pinned report shas hold). The hierarchy eval is a SEPARATE
self-contained worker `hierarchy_eval.py`, invoked via the wrapper `-Op hierarchy-eval` (an isolated branch;
the benchmark path is untouched) or directly (`python hierarchy_eval.py --request`). Report schema
`lifeorch.hierarchy_eval_report/0.1` (integer-only ppm; byte-identical on re-run). skill/contract 0.6.0/0.6.

**Governing:** `CONTEXT_PACKET_CONTRACT` i34 s7 (the eval seam) + `MEMORY_CONTRACT` A6 (node layer / generations
/ safe-pruning) + `MEMORY_ARCHITECTURE` s10 (the Tier-1 gate) + `research/2026-08-04-i34-hierarchy-design-redteam.md`
(pack b4c90545). We MEASURE #36 (shortlist/descend + node build) + #40 (plan + `retrieval_completeness`)
READ-ONLY via the external_command/adapter seam; the orchestrator wires the REAL #36/#40 behind these measures
at the D-0077 fold. This wave ships the DETERMINISTIC SYNTHETIC model + the seam (the `external_command` adapter
here fails closed with `external_command_deferred` -- it is the fold's step, not this worker's).

**The defect defended (b4c90545 P0):** bounded deterministic navigation is NOT automatically recall-preserving --
a bounded lossy synopsis (`entity_union`/`lexical_descriptor`/centroid) or a bounded beam can silently exclude the
sole required branch, yielding a packet that looks answerable having never exposed the evidence. Interpretations:

- **navigation-cost (measure 1).** NODES EXAMINED (shortlist frontier + descend expansions) vs LEAF COUNT across
  `scales` spanning >=2 orders of magnitude (default 16..4096). For LOCALIZED decisive-term queries, safe-pruning
  proves absence in sibling branches, so the frontier stays ~`B*depth ~ log_F N`. Asserted: p50 GROWS with N
  (NOT constant -- the draft's "B*D independent of leaf count" is wrong; depth grows with N), the nodes/leaf ratio
  STRICTLY DECREASES (sub-linear), and growth is log-shaped. Reported p50 AND p95 (pinned: p50 = 2,3,4,5,6 for
  N=16,64,256,1024,4096 at fanout 4).
- **DUAL recall (measure 2).** (i) hierarchy-PATH recall = the fast beam EXPOSED the required leaf; (ii)
  end-to-end PACKET-EVIDENCE recall = the modeled #40 packet RETAINED the required span OR correctly returned
  `needs_expansion`/`abstain`. On AMBIGUOUS queries the fast beam is PARTIAL (pinned 250000 ppm), the GUARANTEED
  (explore-all-non-safe-pruned) path is 100%, and PACKET recall is 100% because the SAFE-PRUNING + FALLBACK
  contract injects the flat batch when the frontier is NOT exhausted -- a hierarchy MISS is NEVER a false
  `answerable`. `frontier_exhausted` is True ONLY when a SOUND predicate proved absence for every unexplored
  branch. Also: shortlist REGRET (guaranteed-minus-fast), fallback FREQUENCY, STALE-WINDOW recall (a stale
  synopsis ROUTES but never PRUNES -> recall preserved while stale-serving).
- **SAFE-PRUNING (s13.7 mirror).** `lexical|entity|path|id` -> a SOUND Bloom `presence_filter` ("definitely
  absent" = a valid prune; "maybe" = keep; NO false negatives); `time_range` -> range exclusion; bounded
  `descriptor` (entity_union/lexical) -> NEVER prunes (RANKING only); `vector` centroid alone -> CANNOT prune.
  A STALE synopsis is NEVER eligible to prune. `naive_descend` (beam-exclusion-as-proved-absence) is shipped ONLY
  to DEMONSTRATE the silent-miss defect the safe model prevents.
- **adversarial fixtures (measure 3), pinned outcomes:** rare-decisive-term/ambiguous (SAFE falls back +
  preserves; NAIVE silently misses); cross-namespace contamination (`descend` of an out-of-scope root FAILS
  CLOSED, 0 nodes examined, 0 leakage; per-namespace homogeneous trees, delta 6); mutation-during-regen ABA
  (a Boolean stale-clear goes falsely fresh; MONOTONIC `subtree_generation`/`synopsis_generation` + input-digest
  CAS DETECTS it, delta 4); stale-node-no-false-negative-prune; exact-cheap/global-slow (the global query is the
  explicit SLOW path, not constant). 5/5 pinned.
- **Tier-1 gate set (measure 4)** as deterministic checks: STRUCTURAL (byte-identical rebuild digest; fanout
  bound; one parent; projection==edges) -- consumed from #36; SECURITY (0 cross-ns leakage; unauthorized descend
  fails closed); MUTATION/FRESHNESS (no lost-update stale-clear; stale never false-negative-prunes); RETRIEVAL
  (guaranteed/fallback preserves recall; end-to-end packet recall; stale-window recall); COMPLEXITY (sub-linear
  p50/p95). 11/11 pinned across all 5 dimensions.
- **rehearsal (measure 5).** The ~200MB real foreign-corpus rehearsal is SCAFFOLDED + FLAGGED `status:OPEN` --
  synthetic scale is NECESSARY but NOT SUFFICIENT (synthetic generation can accidentally align vocabulary/grouping
  keys/labels). `tier1_acceptance.accepted = false` on synthetic-only; the rehearsal (wiring the REAL #36/#40 via
  the external_command adapter) is the pre-FREEZE/pre-ACTIVATION gate the orchestrator / a later wave runs.

**Fold hooks (D-0077):** the orchestrator points the `external_command` adapter at the REAL #36 `shortlist`/`descend`
+ #40 packet and RE-RUNS these measures on real data; the synthetic pins here are the recall-preservation +
sub-linearity + isolation invariants the real run must also satisfy.
