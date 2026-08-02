# SCHEMA_NOTES -- retrieval.eval (Module 37, contract v0.2 / eval-0.2, plan fo-29-87dbfa0b, RETRIEVAL-QUALITY-i29)

**REQUIRED by D-0077.** This module is the CONSUMER side of a schema producer/consumer pair: it calls a
retriever (the producer -- the real `artifact.search` #36 retriever-0.2 at fold; its own lexical baseline
now) and scores its ranked hits + (at fold) the context compiler #40's packets. This doc records EVERY
schema + interface interpretation the harness codes against, so the orchestrator's cross-module fold can
wire the real `artifact.search` behind this harness and consume the reranker seam without guessing.

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
