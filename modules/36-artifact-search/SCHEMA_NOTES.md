# artifact.search -- SCHEMA_NOTES (Module 36, skill `artifact.search` 0.2.0, schema_version 2)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold. The
orchestrator's fold smoke (repo.intel #38 / episode.memory #39 -> `ingest_records` -> retrieval) depends on
it. 0.2 adopts the FROZEN **`core-docs/MEMORY_CONTRACT.md`** (D-0083); on any conflict that contract + its
gates win, and a divergence is reconciled at fold (never silently). Governing: MEMORY_CONTRACT s1..s8;
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`; D-0080/D-0082/D-0083; D-0077.

Worker: `artifact_search.py` (Python stdlib only: `sqlite3` + FTS5, `struct`). Entrypoint:
`Invoke-ArtifactSearch.ps1` (pwsh-file). CPU-only, no model, no network. `worker_version=0.2.0`,
`schema_version=2`. This EXTENDS the shipped 0.1 (schema_version 1); all shipped ops stay regression-green.

---

## 1. Determinism contract (READ FIRST)

- **The SQLite file is NOT byte-reproducible** (page layout, rowids). The **logical records and the
  `catalog_digest` ARE** reproducible. Do not diff `.db` bytes.
- **`catalog_digest`** = `sha256` over sorted lines (EXTENDED in 0.2 to cover records + edges + chunk
  derivation identity):
  - `CHK\t{rel_path}\t{doc_content_hash}\t{chunk_index}\t{span_start}\t{span_end}\t{chunk_id}\t{chunk_content_hash}\t{chunker_fingerprint}` per current chunk (ordered by `rel_path,chunk_index,chunk_id`);
  - `DOC\t{rel_path}\t{status}\t{serving_status}\t{content_hash}|{parse_status}` per document (ordered by `rel_path`);
  - `REC\t{namespace}\t{record_kind}\t{record_id}\t{record_version_id}\t{content_hash}\t{status}` per record (ordered by `record_kind,record_id,record_version_id`);
  - `REDGE\t{src_ref}\t{src_kind}\t{dst_ref}\t{dst_kind}\t{edge_kind}` per edge (ordered).
  Identical corpus+records **content** => identical digest **across runs AND machines** (repo-relative paths,
  byte spans, content-derived ids only). VERIFIED byte-identical across two fresh dbs (off-machine gate).
- **Ids are content+path derived** (section 2). **Provenance fields are NOT deterministic and never feed an id
  or the digest:** `created_at`, `mtime_utc`, `last_ingest_at`, `deleted_at`, and every **run id**
  (`run_*`/`rrun_*`, exposed as `created_by_ingest_run`). A run id is wall-clock-seeded on purpose (it
  identifies WHICH ingest produced a row); `list-records` therefore legitimately differs run-to-run ONLY in
  `created_by_ingest_run` -- the digest and search ordering are byte-identical.
- Search output order is fully deterministic with a **stable `tie_break_key`** (section 6).

## 2. Identity (deterministic; `x[:24]`/`[:16]` = leading hex of the sha256)

Unchanged from 0.1: `source_id=_slug(label)`; `document_id="doc_"+sha256(source_id\0rel_path)`;
`version_id="ver_"+sha256(document_id\0content_hash)`; `chunk_id="chk_"+sha256(rel_path\0doc_content_hash\0chunk_index)`
(the **physical handle** -- kept stable so FTS/vectors/export/store are unaffected).

**New in 0.2 (MEMORY_CONTRACT s1 two-level chunk identity):**
- `chunk_content_hash = sha256(chunk_text_bytes)` -- the hash of THIS chunk's exact text (== the source byte
  span; utf-8 round-trips). Content-addresses a chunk independent of its document/position.
- `chunk_occurrence_id = "occ_"+sha256(version_id\0chunker_fingerprint\0span_start\0span_end\0chunk_content_hash)`
  -- the s1 IMMUTABLE occurrence identity, derived ONLY from immutable inputs, **NEVER from insertion order /
  chunk_index** (the contract's requirement). This is the `record_version_id` of a `source_chunk` record.
- `record_id (source_chunk) = "srec_"+sha256(document_id\0chunk_index)` -- the s1 LOGICAL id (document +
  position), survives content revisions.
- `edge_id = "edg_"+sha256(src_ref\0src_kind\0dst_ref\0dst_kind\0edge_kind)` -- idempotent edge identity.
- `source_locator_id = "loc_"+sha256(source_id\0casefold(rel_path))` -- physical file-occurrence identity;
  case-folded so Windows path-casing variants dedup to one locator (NTFS file-ids are evidence only, not
  collected -- not portable, s4).

## 3. SQLite schema v2 (as implemented)

Shipped 0.1 tables (`sources`, `documents`, `document_versions`, `chunks`, `chunks_fts`, `ingest_runs`) are
retained and EXTENDED; `chunk_embeddings` (0.1 JSON vector column) is **RETIRED** -> generic `vectors` BLOB.

- **`documents`** += `serving_status` (`active`|`stale_fallback`|`unparsed`|`deleted`, s4),
  `source_locator_id`, `latest_version_id` (newest observed version, may be a failed parse),
  `deleted_at` (tombstone observation time).
- **`document_paths`**(document_id, rel_path, first_seen_at, last_seen_at) -- path history (s4 physical/logical).
- **`document_versions`** += `parser_fingerprint`, `chunker_fingerprint`, `ingest_run_id`.
- **`chunks`** += `record_id`, `chunk_occurrence_id`, `chunk_content_hash`, `parser_fingerprint`,
  `chunker_fingerprint`, `created_by_run`. (`chunk_id` stays the PK/physical handle.)
- **`records`**(`record_version_id` PK, `record_id`, `record_kind`, `namespace`, `content_hash`, `status`,
  `authority_level`, `sensitivity_class`, `valid_from`, `valid_to`, `created_by_ingest_run`,
  `source_version_id`, `source_path`, `source_span_start`, `source_span_end`, `derivation_refs` (json),
  `parser_fingerprint`, `chunker_fingerprint`, `extractor_fingerprint`, `record_schema_version`,
  `token_count`, `embedding_space_id`, `section_path`, `heading`, `title`, `chunk_type`, `attrs_json`,
  `text`, `created_at`) -- the generic s1 typed-record store (symbol/relationship/episode/failure/...).
- **`record_edges`**(`edge_id` PK, `src_ref`, `src_kind`, `dst_ref`, `dst_kind`, `edge_kind`, `attrs_json`,
  `created_by_ingest_run`, `created_at`) -- FIRST-CLASS parent/child + relationship edges (not denormalized
  path fields). Edge kinds seen: `derives_from` (materialized from `derivation_refs`), plus any producer edge
  (`relates_to`, `supersedes`, `references`, ...).
- **`vectors`**(`target_kind` `chunk|record`, `target_id`, `embedding_space_id`, `dim`, `encoding_version`,
  `vector_blob` BLOB, `vector_bytes`, `normalized`, `vector_sha256`, provider/model_* , `created_at`;
  PK(target_kind,target_id,embedding_space_id)) -- the s2 **float32 little-endian BLOB** vector store,
  keyed on `embedding_space_id` (section 5).
- **`records_fts`** = FTS5(text, heading, section_path, record_kind UNINDEXED, record_version_id UNINDEXED,
  record_id UNINDEXED). Records with non-empty text are indexed so they are searchable alongside chunks.
- **`v_records_source_chunk`** = a SQL VIEW mapping `chunks` -> the s1 envelope (section 4). The record
  ENVELOPE ADAPTER is `list_records()` in python (unions this view + the `records` table).
- **`ingest_runs`** += `kind` (`file_ingest`|`record_ingest`), `producer`, `producer_version`, `repo_commit`,
  `worktree_dirty`, `rejected`.
- **`catalog_meta`** += `schema_version=2`, `migrated_from`/`migrated_at` (post-migration), `corpus_version`
  (= the latest catalog_digest; read by `search` as `index_snapshot`/`corpus_version`).

## 4. The MEMORY_CONTRACT s1 record + provenance ENVELOPE (the SHARED fold contract)

Every retrievable object satisfies ONE envelope. A `source_chunk` is ONE `record_kind`; chunks are exposed
through the envelope via `v_records_source_chunk` + `list_records` (NO premature whole-DB generalization, s1).

**source_chunk -> envelope mapping (normative):** `record_id <- srec_(document_id,chunk_index)`;
`record_version_id <- chunk_occurrence_id`; `record_kind='source_chunk'`; `namespace <- source_id`;
`content_hash <- chunk_content_hash` (the record's canonical text hash); `source_version_id <- version_id`;
`source_span <- {span_start,span_end}` (byte offsets); `parser_fingerprint`/`chunker_fingerprint` from the
chunk; `extractor_fingerprint=null` (chunking IS the derivation); `authority_level='source_material'`;
`sensitivity_class='default'`; `status` = `current`, or `source_stale` when the document is a stale fallback;
`parent_edges=[{derives_from -> document_version:version_id}]`.

**`ingest_records` INPUT (I DEFINE this precisely; producers #38/#39 emit it; the orchestrator reconciles any
wrapping divergence at fold):**
```
{ op:"ingest-records", db, ingest_run:{producer, producer_version?, namespace?, repo_commit?, worktree_dirty?},
  records: [ {
     record_id, record_version_id, record_kind,          # REQUIRED (record_kind in the s1 typed enum)
     text | content_hash,                                 # REQUIRED (one of; content_hash defaults to sha256(text))
     namespace?, status?/currentness?(default "current"), authority_level?(default "derived"),
     sensitivity_class?(default "default"), valid_from?, valid_to?,
     source_version_id?, source_path?, source_span?:{start,end}, derivation_refs?:[id|{ref,kind}],
     parser_fingerprint?, chunker_fingerprint?, extractor_fingerprint?, schema_version?,
     token_count?(default len//4), embedding_space_id?, section_path?, heading?, title?, chunk_type?,
     attrs?:{...}, edges?:[{edge_kind, dst_ref, dst_kind?(default "record"), attrs?}]
  } ... ] }
```
Typed `record_kind` enum: `symbol, summary, decision, claim, episode, failure, procedure, skill, reminder,
entity, relationship`. `source_chunk` is RESERVED (produced by the chunk pipeline) -> rejected by the sink.

**Semantics (deterministic + idempotent, s1 item 2):**
- Records processed in a deterministic order (sorted by `record_version_id`). `text` is FTS-indexed when
  non-empty; `derivation_refs` + `edges[]` are materialized as first-class `record_edges` rows.
- **Idempotent:** re-ingesting a record with the SAME `record_version_id` + SAME `content_hash` is a no-op
  (counted `unchanged`). A same `record_version_id` with a DIFFERENT `content_hash` is **rejected**
  `record_version_conflict` (an immutable revision is immutable).
- **Malformed records are REJECTED with a surfaced reason, never silently dropped:** `missing_required_field`,
  `missing_content`, `reserved_record_kind`, `unknown_record_kind`, `invalid_status`, `not_an_object`. Valid
  records in the same batch still land (partial success); the report lists `rejected[{record_version_id,
  reason, detail}]` + a warning (envelope status -> partial).

## 5. Embedding storage (s2) -- float32 LE BLOB keyed on embedding_space_id

- **Storage form:** `vector_blob = struct.pack("<{dim}f", *vec)` (float32 little-endian); `vector_bytes =
  dim*4` (validated); `encoding_version = "f32le/1"`; optional `vector_sha256`. Round-trips exactly
  (`get-vector` unpacks). The 0.1 JSON `vector` column + `provider_id+dim` keying are RETIRED.
- **`embedding_space_id = "esp_"+sha256(canon{model_id,model_version,model_sha256,engine_build,dim,normalized,
  pooling,precision,query_template,doc_template,task_instruction,max_seq,truncation})`** -- storage keys on
  THIS (two providers can share a dim yet be incompatible). Mock provider derives a fixed esp per (dim,
  normalized). `store-embeddings` accepts an explicit `embedding_space_id` or derives one from the provided
  provider/model fields.
- **NO vector index/ANN and NO real embeddings this wave** (out of scope): mock vectors stored in the new
  form prove the storage contract; vector *search* is the retrieval wave. `embed` still returns the mock
  envelope (additively carrying `embedding_space_id`, `input_count`/`vector_count`/`failed_count`,
  `encoding_version` -- the s2 embedding-provider 0.2 shape is #35's adoption item, so `embed` stays
  backward-compatible here).

## 6. Retriever contract 0.2 (I PRODUCE; #37 consumes at its 0.2 revision)

Op `search`: `{query, k, mode(fts|exact), filters?}` -> a ranked hit array in DETERMINISTIC order; a consumer
treats `rank=index+1` and NEVER re-sorts. Searches chunks (`source_chunk`) AND typed records, unified.
`filters`: `source`/`namespace`, `type`(chunk_type), `path_prefix`, `content_hash`, **`record_kind`**,
**`status`/`currentness`** (exact), **`exclude_stale`** (drop non-`current`).

**Frozen hit fields (s3):** `record_id`, `record_version_id`, `record_kind`, `chunk_id` (null for records),
`source_path` (repo-relative), `abs_path` (nullable), `content_hash` (**the SOURCE VERSION identity** = the
document/file bytes sha256 for a source_chunk -- what provenance validation checks; the chunk's own text hash
is `chunk_content_hash`), **`span`** always an OBJECT `{start,end}` of byte offsets **+ `span_label`** string
(section path, else `bytes:S-E`, else `record:<kind>`), `section_path`, `heading`, `chunk_type`, `status` +
`currentness` + `authority_level`, `namespace`, `source_version_id`, `embedding_space_id`; PER-CHANNEL
diagnostics: `retrieval_channels`, `lexical_rank`+`lexical_score`, `vector_rank`+`vector_similarity` (BOTH
`null` until vectors participate), `fused_rank`+`fused_score`, `fusion_algo`(`lexical_only`)+`fusion_version`,
`index_snapshot`+`corpus_version` (= the catalog_digest at write time), `filter_decisions`, `tie_break_key`;
plus `snippet`, `rank`. **The single opaque `score` is RETIRED.**

**Deterministic order:** fused sort key `(-lexical_score, tie_break_key)`. `tie_break_key` = the
`record_version_id` (fts) or `{0|1}\0{path|kind}\0{index|}\0{record_version_id}` (exact). Lexical-only this
wave => `fused_score==lexical_score`, `fused_rank==lexical_rank==rank`; cross-channel calibration is the
hybrid eval wave (#37 0.2). `content_hash` + `span` + reading the span reproduce the cited text (provenance
chain, VERIFIED by the harness against the source file).

## 7. s4 fingerprints + s5 staleness + s4 catalog hardening

- **Fingerprints on every derived record.** `parser_fingerprint = "pf:{parser}/{ver}"`.
  `chunker_fingerprint = "ck:md1:mcc{max}:{sha256(spec)[:12]}"` over {name, version, overlap, max_chunk_chars,
  hard_cut_multiple, tokenizer, token_estimate, newline_norm, unicode_norm, code_fence_policy,
  heading_context_policy}. **`max_chunk_chars` is embedded** -> a chunk-size change INVALIDATES derived chunks
  even when the source hash is unchanged: ingest treats a file as `unchanged` ONLY if BOTH the document bytes
  AND the chunker_fingerprint match; otherwise it re-derives. `extractor_fingerprint` = producer-supplied on
  records; null on source chunks.
- **Staleness ENUM (not a boolean):** `status`/`currentness` in {`current`, `source_stale`,
  `derivation_stale`, `embedding_stale`, `relationship_stale`, `summary_stale`, `authority_stale`,
  `temporal_expiry`, `deleted`, `unverified`}. Sweep at end of ingest: records whose `source_version_id`
  points to a now-non-current version are marked `source_stale`; a `stale_fallback` document renders its
  chunks `source_stale` via the view. Retrieval filters current-source queries (`exclude_stale`/`status`)
  WITHOUT erasing history (the stale record stays retrievable).
- **Catalog hardening (as budget allowed):**
  - *Transactional current-version swap / explicit stale fallback:* a CHANGED source whose new content FAILS
    to parse keeps the last-good version + chunks and flags the document `serving_status='stale_fallback'`
    (`latest_version_id` = the failed version) -- NEVER silently serves old-as-current, NEVER blanks the doc;
    the served chunks show `status=source_stale`. A brand-new unparseable file is `serving_status='unparsed'`
    (nothing to serve; surfaced as a parse failure).
  - *Tombstones:* a deleted source -> `status='deleted'`, `serving_status='deleted'`, `deleted_at` set,
    version rows retained (`is_current=0`), path history kept. (Move detection is report-only, as in 0.1.)
  - *Physical vs logical identity:* `source_locator_id` (case-folded) + `document_paths` history.
  - *Crash-safety:* the whole ingest / ingest_records runs in ONE transaction and commits once at the end.
    Fault-injection (`_fault` = `after_files_before_reconcile` | `before_ingest_commit` |
    `before_records_commit`) raises BEFORE the commit; the transaction rolls back on close, so a fresh open
    sees the prior consistent state (no half-written FTS/vectors/current-pointers) -- VERIFIED by the harness
    (digest unchanged, integrity ok, faulted content absent).
  - *Integrity invariants (extended):* the 0.1 set PLUS `no_duplicate_chunk_occurrence_ids`,
    `no_orphan_vectors`, `vectors_f32le_bytes_valid` (vector_bytes==dim*4==len(blob), esp not null),
    `records_fts_matches_textful_records`, `no_duplicate_record_version_ids`, `records_status_in_enum`,
    `serving_docs_point_at_parsed_version`.

## 8. s4 forward MIGRATION (shipped-0.1 -> 0.2, IN PLACE, no full re-ingest)

Opening a `schema_version=1` db auto-migrates (also exposed as op `migrate`, reporting `migration_actions`):
additive ALTERs add the new columns to `documents`/`document_versions`/`chunks`/`ingest_runs`; new tables
(`records`, `record_edges`, `records_fts`, `vectors`, `document_paths`) are created; existing chunks are
backfilled with `chunk_content_hash` + `chunk_occurrence_id` + fingerprints (a `ck:legacy-migrated` chunker fp
since the original `max_chunk_chars` is unknown at 0.1 -- the occurrence id is stable post-migration and the
real fp lands on the next real ingest of a changed file); `chunk_embeddings` rows are converted to `vectors`
BLOBs then `chunk_embeddings` is DROPPED. Migration is IDEMPOTENT (a re-open reports no actions), preserves
all chunks/embeddings (no data loss), and leaves integrity green. VERIFIED: a v1 db seeded by the FROZEN
`fixtures/artifact_search_v1.py` migrates to v2 with chunk/embedding counts preserved and shipped
search/integrity regression-green. `PRIOR_SCHEMA_VERSIONS=("1",)`; a newer/unknown version fails closed
(`schema_version_unsupported`).

## 9. D-0077 CONTRACT reconciliations (record every interpretation)

- **`span` object-vs-string (i25 divergence):** RESOLVED per s3 -- `span` is ALWAYS `{start,end}` byte
  offsets PLUS a derived `span_label` string. The 0.1 fold adapter is retired.
- **hit `content_hash` = SOURCE VERSION identity (file hash), NOT chunk text hash.** The retriever hit's
  `content_hash` identifies the expected source version (provenance validation, s4); the chunk's own canonical
  hash is exposed separately as `chunk_content_hash` and IS the `content_hash` of the source_chunk ENVELOPE
  (list-records). Two roles, two fields -- documented so the fold does not conflate them.
- **Opaque `score` retired.** #37 0.1 consumed `score`; at #37's 0.2 revision it reads `fused_score` (+
  per-channel diagnostics). The orchestrator reconciles this at the fold if #37 0.1 is exercised.
- **`created_by_ingest_run` is provenance** (wall-clock-seeded run id) -> excluded from every id + the digest;
  `list-records` may differ run-to-run ONLY in this field (canonical outputs -- digest, search order -- are
  byte-identical).

## 10. Concurrency + non-goals

`parallel_safe=false`: reads (search/integrity/catalog/export/list-records/get-vector) are concurrency-safe;
writes (ingest/ingest-records/store-embeddings) serialize on the db (busy_timeout=30s). DISTINCT db paths are
independent. **NOT built (later waves):** vector index/ANN/vector search, real embeddings (#35), #38 parsers /
#39 episode+failure schemas, hierarchical summaries, the context compiler, UI, web search, filesystem watcher.
