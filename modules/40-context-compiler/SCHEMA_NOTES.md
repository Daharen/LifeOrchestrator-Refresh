# context.compile -- SCHEMA_NOTES (Module 40, skill `context.compile` 0.1.0)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold.
The orchestrator's fold smoke (this compiler's REAL packets -> retrieval.eval #37 0.2 + a fresh 9B)
depends on it. context.compile CONSUMES the FROZEN `core-docs/MEMORY_CONTRACT.md` retriever-0.2 hit shape
(s3) + s5 staleness enum + s1 provenance envelope, and PRODUCES `lifeorch.context_packet/0.1`. On any
conflict that contract + its live gates win; a divergence is reconciled at fold, never silently.
Governing: MEMORY_CONTRACT s1/s3/s5; directive `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`
sections 4.1/4.2, 8.1-8.6, 16.3, Priority 4; SKILL_CONTRACT 0.2; D-0080/D-0083/D-0085/D-0077.

Worker: `context_compiler.py` (Python stdlib only: `json, hashlib, re, math, os, sys`). Entrypoint:
`Invoke-ContextCompiler.ps1` (pwsh-file). CPU-only, no model, no network. `worker_version=0.1.0`,
`compiler_version=0.1.0`, `packet_schema=lifeorch.context_packet/0.1`.

---

## 1. Determinism contract (READ FIRST)

- **All packet logic lives in Python** (not pwsh) specifically to avoid the pwsh-7.4.6 determinism traps
  (sort-copy no-op, empty-array unroll, array double-wrap, hashtable ordering, `$var:` parsing). The
  entrypoint is a thin wrapper.
- **Canonical bytes:** every artifact + the `packet_id` are computed over
  `json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",",":"))`. The `context_packet.json`
  / `context_expansion.json` files are written with that canonical form + a trailing `\n`, UTF-8, LF ->
  **byte-identical on re-run** (VERIFIED off-machine: python gate + the entrypoint harness compare the
  artifact sha256 across two runs).
- **NO floats in the deterministic packet.** Incoming retriever scores (`fused_score`,`lexical_score`,
  `vector_similarity`) are folded to integer millionths (`to_micros = int(round(x*1e6))`, None->None)
  and stored as `*_micros`; raw floats are never serialized (float->JSON formatting is not portable).
  Every rerank feature is INTEGER.
- **NO volatile fields in the packet.** Wall-clock timestamps and run ids
  (`created_by_ingest_run`, etc.) are NEVER copied into the packet, and `abs_path` (machine-specific) is
  EXCLUDED so packets are byte-identical across machines. The skill.result ENVELOPE (entrypoint) carries
  timestamps; the PACKET ARTIFACT does not.
- **`packet_id = "cpkt_" + sha256(canonical_json(packet_body_without_id))[:32]`** -- a content hash. Same
  task + same injected hits (same corpus_version) => identical packet_id.

## 2. The context packet schema `lifeorch.context_packet/0.1` (I DEFINE; #37 + the 9B CONSUME)

Top-level packet fields (all deterministic):

- `packet_id` -- `cpkt_`+content hash (above).
- `schema` = `lifeorch.context_packet/0.1`; `compiler{name,version,worker,worker_version}`.
- `task_descriptor_digest` -- `sha256:` over a STABLE projection of the descriptor (excludes injected
  retrieval material).
- `original_goal` -- the descriptor's `original_goal` **verbatim, immutable** (never rewritten; 4.1).
- `normalized_task` -- deterministic `"[{task_type}] {whitespace-normalized request_text}"` (8.1).
- `task_type`, `time_horizon`, `namespace`.
- `constraints`, `permissions{requested_side_effects, authority}`.
- `current_state_refs[]` -- refs to authoritative decision/summary records (authority >= source_material).
- `excerpts[]` -- the selected source evidence WITH PROVENANCE (section 3).
- `candidate_skills[]` / `relevant_procedures[]` / `relevant_failures[]` / `similar_episodes[]` -- REFS
  ONLY (record_id/record_version_id/record_kind/source_path/currentness/authority + rank/score +
  `included_as_excerpt`). Skill-card CONTENT is #41's lane; episode/failure CONTENT is #39's. Drawn from
  the whole ranked pool (capped) so a relevant ref that lost an excerpt slot is still surfaced.
- `open_questions[]`, `completion_contract` (the descriptor's, or a `lifeorch.goal_verification/0.1`
  scaffold naming the goal + a note that a closing predicate is required), `escalation_conditions[]`.
- `token_budget` -- exact accounting (section 4).
- `omitted_context[]` -- what was retrieved-but-dropped + why + an expand hint (section 5).
- `retrieval_provenance{retriever, retriever_version, corpus_version, index_snapshot, embedding_space_id,
  fusion_algo, fusion_version, query_set[], per_query_hit_counts, candidate_count}` (8.2/8.6).
- `evaluation_hooks{retrieved[], packet_metrics}` -- the #37 seam (section 6).
- `expansion_affordances` -- the declared `expand` request shape (section 7).

## 3. The retriever-0.2 hit I CONSUME + the excerpt provenance I PRODUCE (MEMORY_CONTRACT s3/s1)

**Consumed hit (s3, from #36 `search.results[]`; rank = index+1, NEVER re-sorted):** `record_id`,
`record_version_id`, `record_kind`, `chunk_id`, `source_path`(repo-relative)+`abs_path?`, `content_hash`
(the SOURCE VERSION identity), `chunk_content_hash` (the chunk text hash), `span`={start,end} byte
offsets + `span_label`, `section_path`/`heading`/`chunk_type`, `status`/`currentness` (the s5 STRING) +
`authority_level`, `namespace`, `source_version_id`, `embedding_space_id`, per-channel diagnostics
(`retrieval_channels`, `lexical_rank`+`lexical_score`, `vector_rank`+`vector_similarity` [null until
vectors participate], `fused_rank`+`fused_score`, `fusion_algo`+`fusion_version`, `index_snapshot`/
`corpus_version`, `filter_decisions`, `tie_break_key`), `snippet`, `rank`. The compiler MUST NOT depend
on the vector channel being populated (lexical-only today) -- it consumes `fused_rank`/`fused_score` as
given and rank as authoritative.

**Excerpt provenance I emit (s1):** each excerpt carries `record_id`, `record_version_id`, `record_kind`,
`source_path`, `content_hash`, `chunk_content_hash`, `source_version_id`, `span{start,end}`, `span_label`,
`section_path`, `heading`, `chunk_type`, `namespace`, `currentness` (s5 string), `authority_level`,
`text`, `token_estimate`, and a `provenance` block.

**Provenance reproduction (acceptance b -- reading the cited span reproduces the text).** Excerpt `text`
is resolved by reading the SOURCE BYTE SPAN, priority: injected `source_texts[source_path]` (mock) ->
`repo_root/source_path` (-Live) -> the hit's `abs_path` -> (fallback) the hit's `snippet`. When the span
is read, `provenance.reproduced` is set by hashing the span bytes and comparing:
`source_chunk` -> `chunk_content_hash` (== the span bytes hash, per #36 s1); records -> `content_hash`.
`provenance = {text_source, reproduced(bool), checked_against, span_sha256}`. The snippet fallback sets
`reproduced=false` + a warning (never a silent claim of reproduction). `chunk_content_hash` (chunk text
identity) and `content_hash` (source version identity) are kept as DISTINCT fields -- the #36 SCHEMA_NOTES
s9 reconciliation is honored, not conflated.

## 4. Token budget + EXACT accounting (8.4 / 16.3)

- **Token-count function (fixed heuristic; NO tokenizer, NO model):** `est_tokens(text) =
  ceil(len(text)/4)` over Unicode code points; `token_fn` string = `"ceil(chars/4)"`. Documented so #37
  can recompute.
- **Per-excerpt cost** = `token_estimate + per_excerpt_overhead_tokens` (default 12, the provenance
  wrapper cost). **Greedy best-first fill** in ranked order; a candidate that would exceed the budget is
  omitted `token_budget` (a later smaller one may still fit) and sets `truncated = budget_exhausted =
  true`. Explicit truncation detection.
- **`token_budget` accounting block:** `{token_fn, budget, used, remaining (= budget-used),
  per_excerpt_overhead_tokens, excerpt_body_tokens, overhead_tokens, excerpt_count, truncated,
  budget_exhausted, omitted_count, per_source_cap, max_excerpts}`. INVARIANT (tested): `used <= budget`
  and `used == sum(excerpt token_estimate) + overhead*excerpt_count`.

## 5. Rerank + diversity feature order (8.3) + the omitted-context model

**Candidate pool (8.2):** injected `retrieval_batches` are merged by `record_version_id`; per candidate
we keep `best_rank` (min across queries), `matched_queries` (sorted distinct), `best_fused_micros` (max).

**Composite score (integer; feature order):** `relevance` (`max(0, 1000 - (best_rank-1)*40)`) +
`query_coverage` (`(matched-1)*30`) + `authority` (level->points: governing/authoritative/canonical
320/300/280, source_material 150, derived 100, default 80, low 40) + `freshness` (s5 currentness->points:
current 200; embedding/relationship_stale 60; source/derivation/summary_stale 40; authority_stale 30;
unverified 30; temporal_expiry 20; deleted 0) + `kind_priority` (a documented (task_type x record_kind)
matrix, default 60) + `namespace_match` (+120 if hit.namespace==task.namespace) + `component_match`
(+100 source_path under a relevant_path prefix, else +60 basename match). Order = `(-composite_score,
tie_break_key, record_version_id)` -- the hit's `tie_break_key` is the deterministic tie-break; a fully
deterministic total order. This selection is SELF-CONTAINED (the MEASURED reranker is #37's lane) but the
pool is shaped so #37's reranked retriever-0.2 array can be dropped in later.

**Diversity + selection order (per candidate, in rank order):** (1) DROP `deleted` (s5) -> omitted
`deleted`; (2) content dedup by `dedup_key = chunk_content_hash or content_hash` -> omitted
`duplicate_content` (`duplicate_of` recorded); (3) **source-diversity cap** -- at most `per_source_cap`
(default 3) excerpts per `source_path` -> overflow omitted `source_diversity_cap` (this is what stops N
near-duplicate chunks from crowding out a distinct required source -- acceptance e); (4) `max_excerpts`
cap (default 40) -> omitted `max_excerpts`; (5) token budget (section 4) -> omitted `token_budget`.

**omitted_context[]** entries: `{record_version_id, record_id, record_kind, source_path, currentness,
rank_in_pool, composite_score, reason, [duplicate_of], [token_estimate], [expand_hint]}`. `expand_hint`
names the `expand` op + target so a caller can recover the dropped evidence.

## 6. Packet-evaluation hooks / context-quality signals (8.6 -- the #37 seam)

`evaluation_hooks.retrieved[]` records EVERY candidate: `{record_version_id, record_id, record_kind,
source_path, content_hash, currentness, authority_level, rank_in_pool, composite_score, feature_points,
matched_queries, fused_score_micros, included(bool), omit_reason}`. `evaluation_hooks.packet_metrics`:
`{candidate_count, excerpt_count, omitted_count, packet_tokens, budget, distinct_source_count,
distinct_kind_count, provenance_reproduced_count, provenance_reproduced_all, dropped_duplicate,
dropped_diversity, dropped_budget, dropped_deleted}`. This lets #37 0.2 score required-source coverage,
provenance VALIDITY (s6), packet tokens, and the irrelevant-context ratio directly off the packet.

## 7. Adaptive-expansion seam (8.5) -- deterministic `expand`, NOT a live loop

**Request shape:** `{type, target, budget?{max_tokens}}` with `type in {raw_source, more_evidence,
related_symbol, failure_record, tool_contract, prior_episode}`; `target in {record_version_id | record_id
| source_path + span}`. **Semantics:** `raw_source` resolves the target's source span (via the same
`source_texts`/`repo_root` seam) and returns the bounded raw text behind a summary/excerpt WITH
provenance; the evidence-style types pull bounded refs/excerpts from an injected `expansion_candidates`
pool (real #36 hits filtered by kind, or a fixture), deterministically ordered by (rank,
record_version_id). Text is bounded to `max_tokens*4` chars (`truncated` flagged). Result =
`lifeorch.context_expansion/0.1 { expansion_id (deterministic), packet_id, request, evidence[], 
evidence_count, token_estimate, budget_tokens, bounded, truncated }`. The worker never runs a model or a
loop -- it is the deterministic seam a caller (or a later local coordinator) invokes.

## 8. The retriever SEAM (mock off-machine + real #36 on -Live)

The DETERMINISTIC worker NEVER calls another process; the retriever is INJECTED as `retrieval_batches`.
- **mock (off-machine):** the entrypoint reads a case file `{task, retrieval_batches, source_texts,
  retrieval_meta}`; the fixtures carry 0.2-shape hits whose `chunk_content_hash == sha256(span bytes)`
  so provenance genuinely reproduces.
- **artifact_search (-Live):** the entrypoint (1) calls the worker `normalize` -> the query set, (2) runs
  the REAL `artifact.search` #36 `search` op per query (`-InputsJson {op:search, db, query, mode, k,
  filters}`) parsing `envelope.result.result.results` as retriever-0.2 hits, (3) calls the worker
  `compile` with `{task, query_set, retrieval_batches, repo_root, retrieval_meta}`. Excerpt text is read
  from `repo_root/source_path[span]` and validated against `chunk_content_hash`. Any wrapping/precedence
  divergence vs #36's real `search` output is reconciled HERE at fold, never silently.

**pwsh array-unroll note:** the entrypoint assigns PSCustomObjects/arrays DIRECTLY into the worker-args
hashtable and serializes the TOP-LEVEL hashtable (nested arrays preserved); it NEVER pipes an extracted
array through `ConvertTo-Json` (a single-element array unrolls to one object -- the i25/#36-class trap).

## 9. Query derivation (8.1, deterministic; bounded)

`salient_terms` = lowercased alnum tokens of request_text+entities minus a fixed stopword list, deduped,
capped (12). `literals` = decision ids (`D-\d{3,5}`), module/issue refs (`#\d+`), dotted skill ids, and
quoted phrases -> EXACT queries (cap 6). Queries: Q0 primary = AND of the top-6 salient terms (fts,
`exclude_stale` when time_horizon current_only); one exact query per literal; per relevant_path an exact
basename query + a path_prefix-scoped fts query; kind-targeted fts queries for the task_type's high-value
kinds (e.g. coding -> failure/procedure/skill) so non-chunk kinds are not drowned by chunks. Dedup by
`(mode, query, filters)`; cap total at `max_queries` (12); `query_index` assigned in order. The #36
unified `search` returns chunks AND typed records together, so kind coverage comes from filters + the
rerank kind_priority, not from separate per-kind passes.

## 10. Non-goals + parallel-safety

`parallel_safe=true` (distinct module; read-only). NOT built (owned elsewhere, consumed via a seam / a
later wave): real embeddings + vector search (retriever 0.2 vector channel may be null); the retriever /
catalog DB (#36); skill-card content (#41); the measured reranker + eval metrics (#37); the 9B / any
model (the fold's consumer, not here); episode recording (#39); skill routing / plan validation
(Priority 7); UI; web search. Does NOT touch model modules / models.json.
