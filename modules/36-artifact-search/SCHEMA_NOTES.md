# artifact.search -- SCHEMA_NOTES (Module 36, skill `artifact.search` 0.6.0, schema_version 5)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold. The
orchestrator's fold smoke (repo.intel #38 / episode.memory #39 -> `ingest_records` -> retrieval; the i33
MIXED-NAMESPACE LEAKAGE-PATH fold) depends on it. 0.2 adopts the FROZEN **`core-docs/MEMORY_CONTRACT.md`**
(D-0083); 0.3 realizes Amendment A4 (D-0092, Tier-0 seam repairs) -- section 11; 0.4 realizes Amendment A5
(D-0096, i33 Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING) -- section 12; 0.5 realizes Amendment A6
(D-0098, i34 Tier-1 BOUNDED-FANOUT HIERARCHY) -- section 13; **0.6 (i36) adds the by-`record_version_id`
`get-record` body-fetch -- the i35 Lane A FOLD RECONCILIATION (D-0100) -- see section 14.** On any conflict
the contract + its gates win, and a divergence is reconciled at fold (never silently). Governing:
MEMORY_CONTRACT s1..s8 + **A4 + A5 + A6**; MEMORY_ARCHITECTURE s9/s10;
`research/2026-08-04-tier0-amendment-redteam.md` (changes 1-4); `research/2026-08-03-memory-architecture-seam-audit.md` s3;
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`; D-0080/D-0082/D-0083/D-0090/D-0092/**D-0096**/**D-0098**/**D-0100**; D-0077.

Worker: `artifact_search.py` (Python stdlib only: `sqlite3` + FTS5, `struct`). Entrypoint:
`Invoke-ArtifactSearch.ps1` (pwsh-file). CPU-only, no model, no network. `worker_version=0.6.0`,
`schema_version=5`. This EXTENDS the shipped 0.5 (schema_version 5), which EXTENDED 0.4 (4), 0.3 (3), 0.2 (2)
and 0.1 (1); all shipped ops stay regression-green. **0.6 (get-record) is ADDITIVE + READ-ONLY + NO migration
(schema_version STAYS 5)** -- existing paths byte-identical (`catalog_digest` + `shipped_tables_schema_sha`
unchanged); a v0.1.1/A4/A5/A6-conformant producer/consumer stays valid.

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
  **`task_id`** (A4/D-0092: per-task_id working-memory scope; NULL for non-working records),
  **`content_role`** (A4: `evidence` baseline; a `working` record is `working`, never evidence),
  `text`, `created_at`) -- the generic s1 typed-record store (symbol/relationship/episode/failure/node/working).
  `idx_records_task(task_id)` backs the working-memory scope (created in `_ensure_views` AFTER migration).
- **`record_edges`**(`edge_id` PK, `src_ref`, `src_kind`, `dst_ref`, `dst_kind`, `edge_kind`, `attrs_json`,
  `created_by_ingest_run`, `created_at`) -- FIRST-CLASS parent/child + relationship edges (not denormalized
  path fields). Edge kinds seen: `derives_from` (materialized from `derivation_refs`), plus any producer edge
  (`relates_to`, `supersedes`, `references`, ...) **and the A4 reserved-additive `member_of_node` /
  `child_of_node` / `contradicts`** (accepted as-is -- edge_kind is free text; no rewrite needed).
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
entity, relationship`, **plus A4 (D-0092): `node` + `working`** (section 11). `source_chunk` is RESERVED
(produced by the chunk pipeline) -> rejected by the sink. A `working` record MUST carry a `task_id` (top-level
or `attrs.task_id`) or it is rejected `working_requires_task_id` (A4/U3). `edges[].edge_kind` is free text;
the DOCUMENTED canonical set adds **`member_of_node`** (record->node), **`child_of_node`** (node->node),
**`contradicts`** (A4/U2+U4).

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
**`status`/`currentness`** (exact), **`exclude_stale`** (drop non-`current`). **A4 (D-0092, section 11):
`filters.namespace` is now a HARD boundary (a single value OR an explicit set/array), enforced BEFORE ranking
with an all-hits-match assertion; `filters.mode=current_only` (also top-level `mode=current_only`, or the
`current_only`/`exclude_stale` aliases) HARD-EXCLUDES non-`current`; `filters.task_id` scopes `working`
records.** `filter_decisions` gains `temporal_mode`, `current_only`, `namespace_enforced`,
`namespace_allowed`, `task_id`.

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

## 8. s4 forward MIGRATION (IN PLACE, no full re-ingest) -- now version-CHAINED 1 -> 2 -> 3

Opening an older db auto-migrates (also exposed as op `migrate`, reporting `migration_actions`). `_migrate`
is a version-chained DISPATCHER: from `1` it runs `_migrate_1_to_2()` then `_migrate_2_to_3()`; from `2` it
runs ONLY `_migrate_2_to_3()`. It stamps `schema_version`, `migrated_at`, `migrated_from` ONCE at the end.

- **1 -> 2 (D-0083):** additive ALTERs add the new columns to `documents`/`document_versions`/`chunks`/
  `ingest_runs`; new tables (`records`, `record_edges`, `records_fts`, `vectors`, `document_paths`) are
  created; existing chunks are backfilled with `chunk_content_hash` + `chunk_occurrence_id` + fingerprints (a
  `ck:legacy-migrated` chunker fp since the original `max_chunk_chars` is unknown at 0.1 -- the occurrence id
  is stable post-migration and the real fp lands on the next real ingest of a changed file); `chunk_embeddings`
  rows are converted to `vectors` BLOBs then `chunk_embeddings` is DROPPED.
- **2 -> 3 (A4/D-0092, section 11):** ADDITIVE ONLY. Two `ALTER TABLE records ADD COLUMN` (`task_id`,
  `content_role`) + the `idx_records_task` index (created in `_ensure_views`, after the column exists). The
  `node`/`working` kinds and `member_of_node`/`child_of_node`/`contradicts` edges need NO new tables (records
  + record_edges already carry free-text `record_kind`/`edge_kind`). **It rewrites NONE of the shipped
  `sources`/`documents`/`document_versions`/`chunks` tables** -- proven by `shipped_tables_schema_sha` (sha256
  of the four tables' CREATE sql), which is byte-identical between a v2->v3-migrated db and a fresh v3 db
  (GATE TEST 2). `migration_actions` reports `from:2` + `reserve_a4:...` + `add_col:records.task_id/.content_role`.

Migration is IDEMPOTENT (a re-open of a current db reports no actions), preserves all chunks/embeddings/records
(no data loss), and leaves integrity green. VERIFIED off-machine: a v1 db seeded by FROZEN
`fixtures/artifact_search_v1.py` migrates 1->3 (chunk/embedding counts preserved, shipped search/integrity
regression-green), AND a v2 db seeded by FROZEN `fixtures/artifact_search_v2.py` migrates 2->3 with the four
shipped tables byte-identical pre/post + a `node` record + edges ingested and retrieved additively.
`PRIOR_SCHEMA_VERSIONS=("1","2")`; a newer/unknown version fails closed (`schema_version_unsupported`).

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
- **A4 (D-0092) Tier-0 reconciliations (section 11 is authoritative):** namespace is a HARD boundary (single
  OR set) with a fail-closed `namespace_leak` assertion; `current_only` is a real MODE (located at
  `filters.mode`, with top-level `mode=current_only` + `current_only`/`exclude_stale` aliases); `node`+`working`
  kinds and `member_of_node`/`child_of_node`/`contradicts` edges are RESERVED-additive via a v2->v3 in-place
  migration that leaves the four shipped tables byte-identical; `working` records are task-scoped-only. These
  are the items the i32 MIXED-NAMESPACE fold smoke exercises against #40 (importing #37's selpol 1.1.0).

## 10. Concurrency + non-goals

`parallel_safe=false`: reads (search/integrity/catalog/export/list-records/get-vector) are concurrency-safe;
writes (ingest/ingest-records/store-embeddings) serialize on the db (busy_timeout=30s). DISTINCT db paths are
independent. **NOT built (later waves):** vector index/ANN/vector search, real embeddings (#35), #38 parsers /
#39 episode+failure schemas, hierarchical summaries, the context compiler, UI, web search, filesystem watcher.
**A4 Tier-0 NON-goals (RESERVED, not built here):** the bounded-fanout TREE / node-synopsis generation /
shortlist-and-descend retrieval; the working-memory STORE lifecycle (promote/demote/archive); contradiction
DETECTION; the query-classification stage; the selection policy (#37/#40); real embeddings/vector search. Tier
0 RESERVES the kinds/edges/columns/modes + the isolation; the capabilities are Tier 1-2.

## 11. A4 (D-0092) Tier-0 architectural-seam repairs -- EVERY interpretation (REQUIRED for the D-0077 fold)

0.3 realizes the record/retriever half of MEMORY_CONTRACT Amendment A4 (the packet/selection half is
`CONTEXT_PACKET_CONTRACT` + #37/#40). ADDITIVE + backward-compatible; the new semantics bind where named.

- **(U1) `namespace` is a HARD retrieval boundary + all-hits-match assertion.** `search`'s `filters.namespace`
  accepts a single value OR an explicit set/array. The retriever computes an allowed set carrying BOTH the raw
  and the `_slug`-normalized form of each requested value (`_namespace_request`), and a candidate whose
  effective namespace is not in that set is EXCLUDED **before ranking** (`_namespace_ok` in
  `_chunk_passes`/`_record_passes`) -- namespace is a PARTITION, never a score boost. A chunk's namespace is
  its `source_id`; a record's is its envelope `namespace`. After building hits, the retriever ASSERTS every
  returned hit matches (the SAME `_namespace_ok` predicate); a mismatch raises the fail-closed internal error
  **`namespace_leak`** (defense in depth -- it can only fire on a real invariant break, never a low-ranked
  hit). Absent `filters.namespace` = today's behavior (back-compat; the compiler now always supplies it).
  `filter_decisions` records `namespace_enforced` + `namespace_allowed`. **GATE TEST 1** (mixed 2-namespace
  fixture, records AND chunk sources sharing lexical text): a ns-A-scoped query returns ZERO ns-B hits; an
  explicit set returns both; a no-namespace query returns all.
- **(U4) `current_only` is a real retrieval MODE.** The shipped op-level `mode` stays the LEXICAL backend
  (`fts|exact`); the retrieval TEMPORAL mode is `filters.mode` (canonical: `default|current_only|...`), with a
  compat shim accepting `current_only` in the top-level `mode` slot (-> lexical backend `fts`) to honor the
  contract's literal `mode: current_only`, plus the aliases `filters.current_only:true` and the shipped
  `filters.exclude_stale:true`. When current_only is active, a candidate whose s5 `status`/`currentness` is
  not `current` is HARD-EXCLUDED **before ranking** (not demoted). `historical_as_of`/`version_specific`/
  `any_valid_version` are accepted as `temporal_mode` values but behave as `default` here (temporal intent is
  the #37/#40 eval side). Supersession-AWARE RANKING (a superseded record ordered below its live successor) is
  the SELECTION policy (#37/#40), NOT #36. The **`contradicts`** edge is RESERVED-additive (detection is Tier
  2). Test: a `current` + a `source_stale` twin -> current_only returns only the current; default returns both.
- **(U2) hierarchy seam (reserved-additive; NO tree built).** The CLOSED `record_kind` enum gains **`node`** (a
  navigation node). Its structure -- synopsis / bounded child list / time+authority ranges / key entities /
  child ids / counts / lexical descriptors / embedding / synopsis provenance -- rides the EXISTING envelope:
  the synopsis in `text` (FTS-indexed), the rest in `attrs` (JSON) + `record_edges`; NO shipped table is
  restructured. The edge set gains **`member_of_node`** (record->node) + **`child_of_node`** (node->node),
  accepted as-is (free-text `edge_kind`). Retrieval + selection stay hierarchy-AGNOSTIC at the candidate-pool
  interface (no new flat-top-k hardening). **GATE TEST 2** (schema-evolution): a v2 fixture db migrates to v3,
  a `node` record + `member_of_node`/`child_of_node`/`contradicts` edges ingest via `ingest-records`, the node
  RETRIEVES through the normal envelope (`list-records`) + the retriever hit shape (`search`), and the
  `sources`/`documents`/`document_versions`/`chunks` table schema is BYTE-IDENTICAL pre/post (asserted two
  ways: the raw `sqlite_master.sql` compared directly off-machine, AND `shipped_tables_schema_sha` equal to a
  fresh v3 db's).
- **(U3) working-memory seam (reserved-additive; store at Tier 1).** The enum gains **`working`** -- a
  per-`task_id` record carrying a task's evolving state. Isolation: a `working` record is EXCLUDED from
  ordinary retrieval and `list-records` UNLESS the request scopes to its own `task_id` (`filters.task_id`);
  when scoped, only that task's working records surface (non-working records unaffected). `task_id` lives in a
  NEW additive `records.task_id` column (top-level `task_id` or `attrs.task_id`); a `working` record without a
  task_id is REJECTED `working_requires_task_id` (it could never be scoped). `content_role` (NEW additive
  column) is `working` for a working record, `evidence` otherwise -- a working record is NEVER evidence /
  control-plane authority (the compiler consults it as a DISTINCT packet region; that's #40).
- **(U5) the retriever channel set stays FROZEN OPEN.** `retrieval_occurrences[].channel` / `retrieval_channels`
  remain DATA (currently `["lexical"]`); no consumer-visible interface change. The query-classification stage
  that routes across channels is the compiler front (#40), NOT #36. (No code change was needed here -- recorded
  so the fold confirms #36 did not hard-code `{lexical, vector}`.)
- **Migration + determinism.** `SCHEMA_VERSION "2"->"3"`, `PRIOR_SCHEMA_VERSIONS=("1","2")`,
  `WORKER_VERSION 0.3.0` (wrapper `$SKILL_VERSION 0.3.0`/`$CONTRACT 0.3`; `skill.json` 0.3.0/0.3). The
  `catalog_digest` FORMAT is UNCHANGED (node/working records appear as ordinary `REC` rows; `task_id` is not
  in the digest -- it is covered by `record_version_id`/`content_hash`), so identical-corpus determinism holds
  across the version bump (a fresh v3 ingest yields the SAME digest as a v2 ingest of the same corpus --
  VERIFIED). New records-table columns are accessed by NAME, so column-order differences between a fresh v3 db
  and a migrated one are irrelevant.

---

## 12. A5 (D-0096) Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING -- EVERY interpretation (REQUIRED for the D-0077 fold)

0.4 realizes the record/retriever half of MEMORY_CONTRACT Amendment A5 (the packet/selection half is
`CONTEXT_PACKET_CONTRACT` i33 + #37/#40). #36 is the retriever/catalog ENFORCEMENT POINT. It folds the frontier
Tier-0 red-team (`research/2026-08-04-tier0-amendment-redteam.md`, changes 1-4): the A4 (0.3) seams were a
correct ENVELOPE-level FIRST layer but INCOMPLETE. A5 is ADDITIVE + backward-compatible; the new semantics bind
where named. `SCHEMA_VERSION "3"->"4"`, `PRIOR_SCHEMA_VERSIONS=("1","2","3")`, `WORKER_VERSION 0.4.0` (wrapper
`$SKILL_VERSION 0.4.0`/`$CONTRACT 0.4`; `skill.json` 0.4.0/0.4).

### 12.1 (U1') namespace CLOSURE -- the canonical predicate, per-hop + all-object, sanitized rejection, homogeneous derivations

- **ONE canonical predicate (the A5 mirror; risk 6).** `ns_permitted(candidate_namespace, effective_allowed)`
  is a top-level PURE function with EXACT-string membership -- NO wildcard/prefix/parent/child/shared/`all`:
  `effective_allowed is None` (the UNSCOPED SENTINEL) -> **False** (permit NOTHING); an EMPTY closed set ->
  False; a `None`/missing candidate namespace -> False; otherwise `str(candidate_namespace) in effective_allowed`
  (a `_ns_normalize_allowed` mirror handles a raw list/str input). A5(f) requires this predicate be authored
  ONCE (owned by #37 `lib/`, imported by #40) with #36 implementing the IDENTICAL decision and the i33 fold
  asserting byte-identical accept/reject across the three. **MIRROR NOTE (recorded for the fold):** #37's
  canonical is now on disk at **`modules/37-retrieval-eval/lib/namespace_policy.py`** (`ns_policy_id
  ns_closed_v1`); #36's `ns_permitted` is a byte-identical-DECISION MIRROR of it (verify: both fail-close on
  `None`, empty set, and a missing candidate; both do exact-string membership otherwise). Per #37's documented
  design the `None` UNSCOPED case is handled by a SEPARATE caller GUARD that BYPASSES the predicate, NOT by the
  predicate inventing "permit all": every #36 enforcement site (the FTS + exact chunk/record scope-checks,
  `_chunk_passes`/`_record_passes`, the supersession-walk per-hop, the `list-records` edge walk, the all-hits
  assertion) enforces `ns_permitted` ONLY when `effective_allowed is not None`; when it is `None` (no namespace
  filter supplied) #36 skips enforcement (its standalone/admin/eval back-compat -- the compiler always supplies
  the effective set, so the compiled path never hits this branch). **The fold's byte-identity assertion holds
  unconditionally** (identical decisions on every `(candidate, set)` input, including `None`).
- **The effective set is #36's ONLY dual-form site.** `effective_allowed_namespaces(filters)` returns `None`
  (absent `filters.namespace` = UNSCOPED back-compat -> enforcement BYPASSED per the guard above) or a
  `frozenset`; an explicit empty set/list stays EMPTY (zero hits -- the predicate fail-closes). The set carries
  BOTH the raw and the `_slug` form of each requested value because #36 stores TWO
  namespace representations (records = raw envelope value; chunks = slugged `source_id`). This dual-form
  expansion is on the SET, not the predicate -- the predicate stays byte-identical to #37/#40 (the fold checks
  identical accept/reject on identical `(candidate, set)` inputs).
- **Per-hop + all-object scope-check.** The predicate is applied at EVERY retrieval stage (`_search_fts` /
  `_search_exact` scope-check every candidate before any other filter) AND every graph hop: the `superseded_by`
  chain walk (`_supersession_info`) enforces `ns_permitted` AND same-namespace-only per hop (a cross-namespace
  successor edge is IGNORED, never followed -- so an edge-walk that would reach an out-of-scope node is blocked
  per-hop); the `list-records` edge walk (`_edges_for`) drops any edge whose OTHER endpoint resolves to an
  out-of-scope record and surfaces only `out_of_scope_edges_dropped` (a count). No returned/reachable object
  (hit envelope, walked edges, diagnostic arrays) carries out-of-scope data.
- **Sanitized fail-closed rejection.** A cross-namespace candidate is EXCLUDED before ranking; only a
  **`namespace_violation_count`** surfaces (on the `search` result AND in `filter_decisions`). Identifying detail
  (ids/paths/namespaces) is written to a PRIVILEGED local security log -- a DB `security_log` table (EXCLUDED
  from `catalog_digest` + never returned by any op) AND an append-only JSONL file (default `security/
  namespace_violations.log` beside the db; overridable via `security_log_path`). A returned hit outside the
  effective set is the fail-closed ERROR **`namespace_leak`** that ABORTS the query; its message carries NO
  cross-namespace identifying detail (that goes to the security log). The exact-scan violation count is only
  incremented for a candidate that WOULD otherwise match the query (so an unscoped-corpus scan is not inflated).
- **Homogeneous derivations (rejected at ingest).** `_homogeneity_violation` fails-closed any persisted
  derivative whose provenance spans >1 namespace: it checks `source_version_id` (the source's namespace via
  `chunks.source_id`), every `derivation_refs` entry, and every DERIVATION/MEMBERSHIP/SUPERSESSION edge
  (`derives_from` / `member_of_node` / `child_of_node` / `superseded_by` / `supersedes`) that RESOLVES to a
  known record (in-batch map or catalog). A cross-namespace resolvable parent -> reject reason
  **`cross_namespace_derivation`** (+ a security-log entry). Only RESOLVABLE refs are judged (an unresolved
  forward ref is not proof); transitive closure holds by induction (parents ingest first / are in the batch
  map). `relates_to` / `references` / `contradicts` are non-derivational cross-references and are NOT constrained
  (not a laundering path). Representation-tolerant compare (`_slug`) so a record ns vs a chunk source_id matches.
- **`effective_allowed` is CALLER-SUPPLIED** and never widened. #36 (a standalone retriever) treats absent
  `filters.namespace` as UNSCOPED (the compiler computes `intersection(request, grant)` upstream and always
  supplies it). `filter_decisions` records `namespace_enforced`, `namespace_allowed`, `namespace_violation_count`.
- **GATE TEST 1** (section 29): a mixed ns-A/ns-B fixture; a ns-A-scoped query returns >=1 hit with ZERO ns-B
  leakage; `namespace_violation_count >= 1`; the SERIALIZED result contains NO ns-B identifying token (hits +
  every diagnostic array sanitized); a cross-ns DERIVATION and a cross-ns SUPERSESSION edge are both REJECTED at
  ingest; a forward-ref cross-ns successor is IGNORED per-hop (the predecessor stays effective_current under
  scope with no ns-B leak).

### 12.2 (U4') candidate-INDEPENDENT supersession

- **New s5 value `superseded`** (in `STATUS_ENUM`; the `records_status_in_enum` integrity check covers it) and
  **new first-class edges** `superseded_by` (predecessor -> live successor; canonical forward) + `supersedes`
  (inverse), both in `RECORD_EDGE_KINDS`.
- **`effective_current(record)` is computed from the CATALOG/graph**, NOT the retrieved pair:
  `status == current` AND no reachable LIVE (status==current) successor within scope at the snapshot
  (`_effective_current` -> `_supersession_info`). So `current_only` (`filters.mode=current_only` / the
  `current_only`/`exclude_stale` aliases / the top-level `mode=current_only` shim) HARD-EXCLUDES a predecessor
  **even when its successor is ABSENT from the returned pool** -- the i32 pool-dependence defect fixed. A
  `source_chunk` has no record supersession graph -> its stored status is authoritative. Each hit carries
  `effective_current` + `supersession_conflicted` + `superseded_by` (its in-scope live successors).
- **Chain invariants.** The walk is transitive with an ACYCLIC guard; it follows only same-namespace hops
  (cross-ns supersession IGNORED at walk time AND rejected at ingest -- U1'/U4'); a non-live successor is
  walked THROUGH to a live terminal (immediate-vs-terminal distinguished); a **branch** (>=2 distinct immediate
  live in-scope successors) sets `supersession_conflicted=true` on the hit (SURFACED, never a silent pick).
  Integrity gains **`no_cross_namespace_supersession`** (both endpoints resolvable, different ns) and
  **`supersession_chain_acyclic`** (DFS cycle detection over the canonical direction). A stale/deleted successor
  does not silently resurrect its predecessor (the predecessor's stored status governs; a superseded record
  stays superseded). `contradicts` stays RESERVED (detection is Tier 2; absence of the edge is not proof).
- **GATE TEST 2** (section 30): a predecessor (token PRETOKEN) `superseded_by` a successor (disjoint token
  SUCTOKEN, so ABSENT from the PRETOKEN pool) -> `current_only` STILL excludes the predecessor; the successor is
  `effective_current`; a branch of two live successors is flagged `supersession_conflicted`; the two integrity
  checks pass on a clean db.

### 12.3 (U2') provenance_mode-conditional hit shape + reserved candidate_role / retrieval-stage lineage

- **`provenance_mode`** is a new additive `records` column (A2): `direct_span | derived_record | aggregate |
  tombstone`. A producer value wins; else it is inferred (`_infer_provenance_mode`: `deleted`->tombstone;
  `node`->aggregate; a real source span->direct_span; else derived_record). Every `search` hit and `list-records`
  envelope carries `provenance_mode` + a per-mode **`provenance`** block: direct_span `{source_path, span}`;
  derived_record `{record_content_hash, derivation_refs, span?}` (span OPTIONAL -- a node/summary/symbol has no
  single source span); aggregate `{record_content_hash, constituent_refs}`; tombstone `{record_content_hash,
  deleted, derivation_refs}`. The top-level `span`/`content_hash` are RETAINED for back-compat; A2 hash names are
  added additively (`record_content_hash`/`source_content_hash`/`excerpt_hash`: a source_chunk's own bytes ARE
  the cited span so record==excerpt==chunk_content_hash, source==doc bytes).
- **Reserved** `candidate_role` (`navigation` for a `node`, else `evidence`) + retrieval-stage lineage
  (`retrieval_stage_id` = `"stage:lexical:1"`, `parent_stage_id`=null, `retrieval_plan_id`=null) on every hit --
  DATA only; a compile is MULTI-STAGE (shortlist -> descend) but #36's flat lexical retrieval is a single
  reserved stage this wave (the router is Tier 1; no new flat-top-k hardening).
- **GATE** (section 32): a source_chunk hit is `direct_span`/`evidence`; a `node` hit is `aggregate`/
  `navigation`; the stage-lineage fields are present; `superseded` is a queryable first-class status.

### 12.4 (U3') working-state STORE seam HARDENED

- **Reserved store fields** on the `working` kind as additive `records` columns: `working_state_id`,
  `state_version`, `parent_state_version`, `namespace_scope` (defaults to the record's own namespace for a
  working record), `grant_snapshot_ref`, `created_from_packet_id`, `lifecycle_state` (defaults `active` for a
  working record), `writer_authority` (`task_id`/`content_role`/`content_hash` already existed). Read from
  top-level or `attrs`. NO store lifecycle (immutable snapshots / CAS / one-active-head / promotion) is BUILT --
  that is Tier 1; these are reservations, surfaced on the `list-records` envelope.
- **Ordinary `search` REJECTS `record_kind=working` by DEFAULT.** A working record is retrievable ONLY under
  CONJUNCTIVE access (`_record_passes`): the request scopes to its exact `task_id` AND supplies an in-scope
  namespace authorization (`effective_allowed is not None` and the record's namespace is permitted).
  "Excluded by default" (A4) was too weak -- absent EITHER, the working record is hidden. `list-records`
  (record_kind=working, task_id) remains the explicit enumeration op (task-scoped; not "ordinary search").
- **GATE TEST 3** (sections 27 + 31): a working record without task_id is rejected `working_requires_task_id`;
  ordinary search returns zero; a `task_id` ALONE (no namespace) still returns zero; `task_id` + in-scope
  namespace surfaces ONLY that task; the reserved store fields round-trip on the envelope.

### 12.5 Migration + determinism (schema_version 3 -> 4)

- **`_migrate_3_to_4` is ADDITIVE ONLY.** It adds the provenance_mode + working-store columns to `records`
  (`ALTER TABLE records ADD COLUMN`) and ensures the new privileged `security_log` table; the `superseded`
  status + `superseded_by`/`supersedes` edges need NO column (status/edge_kind are free text). It rewrites NONE
  of `sources`/`documents`/`document_versions`/`chunks` -- `shipped_tables_schema_sha` is BYTE-IDENTICAL pre/post
  (asserted vs a fresh v4 db). Version-chained 1->2->3->4; idempotent; migration action `reserve_a5:...`.
- **`catalog_digest` FORMAT is UNCHANGED** (the new columns are not in the digest; `superseded_by`/`supersedes`
  edges appear as ordinary `REDGE` rows only when a corpus has them), so a v3->v4 migration does NOT change the
  digest (no re-ingest) and identical-corpus determinism holds across the bump (VERIFIED: a v3 seed migrates
  with digest UNCHANGED; two fresh dbs with supersession edges yield identical digests). The `security_log`
  table is NOT in the digest (it holds timestamped privileged rows). New columns are accessed by NAME.
- **GATE** (section 33): a v3 seed (built by the frozen `fixtures/artifact_search_v3.py`) migrates 3->4 in place
  with migrated=true / `from:3` / `reserve_a5`; NO chunk or record loss; shipped tables byte-identical (migrated
  sha == fresh v4 sha); catalog_digest UNCHANGED; idempotent re-open; shipped search regression-green.

## 13. A6 (D-0098) Tier-1 bounded-fanout HIERARCHY -- EVERY interpretation (REQUIRED for the D-0077 fold)

0.5 turns the A4/A5 RESERVED `node` seam into a real DETERMINISTIC build (schema_version 4 -> 5). The builder is
CODE, never the model; the frontier design red-team (pack `b4c90545`) NO-GO'd the first draft's recall claim, so
the **SAFE-PRUNING invariant is load-bearing** (13.7). The packet/selection + navigation-plan half is #40/#37
(i35). Everything below is what a consumer + the D-0077 fold must rely on.

### 13.1 (H1) the `node` record + `nodes`/`hierarchies` tables + CANONICAL edges vs PROJECTION
- A `node` is a DERIVED record: `record_kind=node`, `provenance_mode=derived_record`, `content_role=navigation`,
  `candidate_role=navigation`, namespace-homogeneous, exactly one parent, acyclic. Nodes live in the NEW `nodes`
  table and are **NOT inserted into `records`** -- the flat `search`/`list-records` stay hierarchy-agnostic; a
  node NEVER enters `evidence[]` (navigation is the SEPARATE `shortlist`/`descend` ops).
- **`child_of_node` (node->parent node) + `member_of_node` (leaf->node) are CANONICAL edges in `record_edges`**;
  the node's stored `child_ids_json`/`member_ids_json` are a rebuildable PROJECTION whose set MUST equal the
  canonical edges (integrity `tree_digest_matches_canonical`; the fold + `_validate_tree` assert equality).
- Deterministic structural synopsis: `child_count`, `member_count`, `subtree_record_count`, bounded
  `entity_union` (top-N by subtree frequency, tie-break by key -- RANKING ONLY, never prunes), bounded
  `lexical_descriptor` {term: df} (RANKING ONLY), EXACT `time_range` {valid_from_min, valid_to_max}, EXACT
  `authority_set` (sorted distinct), EXACT `kind_histogram`, and a **no-false-negative Bloom `presence_filter`**
  (m=2048, k=7, over subtree paths/record-ids/entity+lexical terms -- the ONLY lexical/entity/path/id ABSENCE
  proof; see 13.7).
- **Vector aggregate = SUFFICIENT STATISTICS, not a mean-of-normalized-child-centroids**: `{vector_sum,
  vector_count, missing_vector_count, embedding_space_id, dim, canonical_member_order, accumulation_precision,
  accumulation_algo}`. Accumulated in f64 by summing child sums (associative -> TOPOLOGY-INDEPENDENT) then
  QUANTIZED (round 1e-6) BEFORE hashing -> byte-reproducible. **ABSENT (NULL) while no subtree leaf has a
  vector** (lexical+entity shortlist stands alone; the aggregate is NEVER a pruning oracle). `synopsis_text` +
  `covering_radius`/`medoids` are RESERVED (Tier 2), not built.
- `record_content_hash` = sha256 over the canonical (quantized, sorted) synopsis bytes; `synopsis_input_digest`
  = digest over the IMMEDIATE child/member canonical (id, hash) pairs (transitive reconstruction follows the
  bounded-fanout graph, not a flattened leaf list). `record_version_id = ndv_<sha(node_id+record_content_hash)>`.

### 13.2 (H4) the DETERMINISTIC BALANCED bulk-builder (MINIMAL i34; live split -> i35)
- Leaves = all level-0 EVIDENCE (`source_chunk` + typed records; `node`/`working` EXCLUDED) in ONE canonical
  namespace (keyed by `_slug` so a source's chunks [source_id] + its typed records [namespace] unify). Total
  order = `(coarse_group_key, content_hash, leaf_id)` (coarse = parent dir else kind bucket).
- **Balanced even-partition**: `_even_partition_sizes(n, MAX_FANOUT)` = fewest groups each <= fanout, sizes as
  even as possible; recurse level-up until one root. Balance is INDEPENDENT of the grouping key's distribution
  (a low-cardinality/dominant key CANNOT produce deep thin chains -- the key only sets the order). Depth is
  logarithmic; `node_id = nd_<sha(hierarchy_id + level + sorted child/member ids)>` is CONTENT-ADDRESSED (NO
  tree_version) so an identical corpus rebuilds byte-identical node_ids + tree_digest.
- `MAX_FANOUT` default 16 (ratifiable; `max_fanout` arg). `builder_policy_id=balanced-even-partition`, version 1.
- **Rebuild/flat-fallback triggers (H4)**: a corpus mutation (ingest/ingest-records/store-embeddings) sets any
  CURRENT tree whose `built_from_corpus_version != corpus_version` to `topology_state=rebuild_required`
  (`mark_stale_hierarchies`, run after every corpus-changing op) -- flat retrieval serves until a deterministic
  rebuild + atomic swap. `_validate_tree` failure -> `topology_state=corrupt` (NOT published). Live incremental
  in-place split is DEFERRED to i35 (this wave rebuilds).

### 13.3 (H3) hierarchy IDENTITY + ATOMIC tree-version publication
- `hierarchies` row = {`hierarchy_id` (STABLE per (namespace, kind)), `tree_version` (tv1, tv2, ... per build),
  `hierarchy_kind=source_module`, namespace, builder_policy_id/version, max_fanout, root_node_id, `tree_digest`,
  topology_state, node_count, leaf_count, depth, built_from_corpus_version, build_generation, is_current}.
- **Atomic publication**: a (re)build shadow-builds all nodes in memory, deletes the prior tree's nodes + node
  edges + hierarchy row, inserts the new ones, and COMMITS ONCE -- a reader (compile) therefore sees EITHER the
  whole old OR the whole new tree, never a mix ("a compile pins one tree_version"). i34 keeps exactly ONE current
  version per hierarchy (multi-version retention for concurrent long compiles = i35; the single-writer executor
  makes mixed-generation reads impossible). `shortlist`/`descend` pinning a NON-current `hierarchy_version` are
  NOT served (fail-safe). Fault injection `before_hierarchy_commit` rolls back -> the prior tree is intact.
- `tree_digest` = deterministic sha over this version's node rows + their canonical `member_of_node`/
  `child_of_node` edges (the atomic-publish + projection==edges + determinism proof).

### 13.4 (H2) THREE separated state axes + monotonic generations + CAS-cleared regen
- Do NOT overload evidence `status` (s5). Distinct axes: evidence `status`/`currentness` (s5, unchanged);
  `topology_state` {valid|rebuild_required|corrupt}; navigation-synopsis `synopsis_freshness` {fresh|stale} via
  MONOTONIC `subtree_generation`/`synopsis_generation` (+ `synopsis_built_from_corpus_version`,
  `synopsis_input_digest`). A node is FRESH iff `synopsis_generation` covers `subtree_generation` AND the input
  digest matches the current canonical children/members. A node can be topology-VALID + synopsis-STALE at once.
- **Deterministic propagation** (`propagate_leaf_change(leaf_id)`): mark the UNION of affected ancestor-path
  synopses `synopsis_freshness=stale` + `status=summary_stale` and bump their `subtree_generation` (local update
  -- nodes off the path stay fresh). **CAS regen** (`regen_node(node_id, expected_generation?)`): recompute the
  synopsis from CURRENT children, then `UPDATE ... synopsis_generation=subtree_generation, freshness=fresh WHERE
  node_id=? AND subtree_generation=<expected>` -- if the generation advanced since it was observed the clear is
  REFUSED (rowcount 0) and the node stays stale. **This closes the ABA/lost-update stale-clear race** (a Boolean
  flag is insufficient). `refresh-hierarchy` lazily regens all stale nodes bottom-up.
- **`summary_stale` ROUTES but never ANSWERS**: a stale node still appears in `shortlist` (which flags
  `stale_navigation_encountered`) but a node never enters `evidence[]`, and `current_only` evidence `search` is
  unaffected by node staleness (the axes are decoupled). A STALE synopsis is NEVER eligible to prune (13.7).

### 13.5 (H5, SAFETY-CRITICAL) write-time + transitive namespace HOMOGENEITY
- Leaves are collected per canonical `_slug(namespace)`; every leaf is asserted slug-homogeneous with the
  hierarchy (a mismatch -> `cross_namespace_member` fail-closed + a privileged security-log line). Every node's
  namespace == its hierarchy's namespace (integrity `node_namespace_matches_hierarchy`); no cross-namespace
  `child_of_node` edge (integrity `no_cross_namespace_node_edge`). Every aggregate (entity_union / lexical /
  ranges / histograms / vector-aggregate / counts / hashes / bloom) is PROTECTED derived info built ONLY from
  same-namespace members. A multi-namespace authorized compile gets SEPARATE roots (one per namespace) -- NEVER
  a merged root/aggregate.

### 13.6 (H6, SAFETY-CRITICAL) authorization-bound frontier ops
- `shortlist(query, effective_allowed_namespaces, hierarchy_version, corpus_snapshot, k)` ranks the AUTHORIZED
  hierarchy ROOTS (the initial navigation frontier) by structural-synopsis match -- a FRONTIER-EXPANSION op, NOT
  a flat scan of every node. `descend(node_id, retrieval_plan_id, effective_allowed_namespaces, hierarchy_version,
  corpus_snapshot)` expands ONE node into its direct children + leaf members. The canonical `ns_permitted`
  (A5; the same predicate the retriever uses) is enforced at EVERY hop AND on every returned object; `shortlist`
  re-asserts all returned nodes in-scope (a leak -> fail-closed abort, count only). **An arbitrary / foreign /
  out-of-scope `node_id` NEVER makes the retriever a confused deputy** -- `descend` FAILS CLOSED with an
  identical opaque `{authorized:false, reason:not_authorized, child_count:0, children:[], leaf_members:[]}` (NO
  namespace/id/metadata; the detail goes to the privileged security log). Hits carry the reserved
  `retrieval_stage_id`/`parent_stage_id`/`retrieval_plan_id` lineage (a compile is multi-stage).

### 13.7 the load-bearing SAFE-PRUNING channel predicates (`prune_verdict`; frontier red-team `b4c90545`)
- A navigation-derived value may POSITIVELY prioritize a branch but MUST NOT NEGATIVELY exclude one unless a
  deterministic, channel-specific, NO-FALSE-NEGATIVE predicate PROVES the subtree cannot satisfy the requirement
  at the pinned snapshot; else `keep` (the compiler expands / switches channel / flat-falls-back). Verdicts:
  `lexical|entity|path|id` -> the Bloom `presence_filter` ("definitely absent" = SOUND prune; "maybe" = keep);
  `kind` -> exact `kind_histogram` membership; `authority` -> exact `authority_set` membership; `time` -> exact
  `time_range`; **`descriptor` (bounded entity_union/lexical_descriptor) NEVER prunes**; **`vector` (centroid
  alone) NEVER prunes** (needs the reserved covering-radius); **a STALE synopsis NEVER prunes** (any channel).

### 13.8 Migration + determinism + catalog_digest (schema_version 4 -> 5)
- **`_migrate_4_to_5` is ADDITIVE ONLY**: it ensures the NEW `nodes` + `hierarchies` tables (SCHEMA_SQL is
  idempotent on open) and adds NO column to any table. It rewrites NONE of `sources`/`documents`/
  `document_versions`/`chunks`/`records` -- `shipped_tables_schema_sha` BYTE-IDENTICAL pre/post (asserted vs a
  fresh v5 db). Version-chained 1->2->3->4->5; idempotent; action `a6:hierarchies+nodes_tables;...`.
- **`catalog_digest` EXCLUDES `member_of_node`/`child_of_node` edges** so the CORPUS fingerprint stays stable
  across a tree build (a tree is DERIVED navigation state) and **zero nodes == today's flat retrieval
  byte-for-byte**. The hierarchy has its OWN `tree_digest`. Building or rebuilding a tree does NOT change
  `catalog_digest`/`corpus_version`.
- **GATE** (D-0077, this module owns the hierarchy gate tests): STRUCTURAL (deterministic byte-identical rebuild
  tree_digest; no cycles/orphans; fanout+occupancy; one parent; projection==canonical edges; atomic publication);
  SECURITY (zero cross-ns aggregate/metadata leakage; unauthorized/foreign descend fails closed count-only;
  mixed-ns build inputs rejected); MUTATION/FRESHNESS (every mutation dirties the ancestor path; the ABA
  stale-clear race is refused; a stale synopsis cannot supply a prune proof); SAFE-PRUNING (a bounded descriptor
  NEVER prunes; exact/range/membership prune only a provably-empty branch). Off-machine gate:
  `tests/test_hierarchy_a6.py` (cloud python, 56 checks) + `tests/Invoke-ArtifactSearchTests.ps1` A6 section
  (real-worker via the entrypoint, 36 checks); full suite 210/210.

## 14. i36 (D-0100 fold reconciliation) the by-`record_version_id` `get-record` body-fetch -- EVERY interpretation (REQUIRED for the future #40 fold)

0.6 adds the clean, ADDITIVE, **READ-ONLY** `get-record` op. **NO migration** -- `SCHEMA_VERSION` STAYS `"5"`,
`WORKER_VERSION 0.6.0` (wrapper `SKILL_VERSION 0.6.0` / `CONTRACT 0.6`). Origin: i35 Lane A recorded that #40's
context-compile leaf HYDRATION reads #36's Catalog `records` table DIRECTLY because #36 shipped NO by-rvid
body-fetch op (D-0100). `get-record` is that op, so a future i37 #40 change can stop reaching into #36's
internals. **#40 ADOPTS it in i37 -- this wave only SHIPS the op** (no in-wave consumer; the orchestrator's fold
smoke over a real catalog + this module's gate suffice).

### 14.1 The rvid id space (what get-record resolves)
A `record_version_id` handed to get-record is EITHER:
- a **typed-record** `record_version_id` (the `records` table primary key -- e.g. `sym.x@1`, `dv1`), OR
- a **source_chunk** `chunk_occurrence_id` (`occ_...`), which IS the `record_version_id` column of the
  `v_records_source_chunk` view (`c.chunk_occurrence_id AS record_version_id`).

This is the SAME id space `search` hits (`hit.record_version_id`) and `descend` leaf_members
(`{record_version_id, candidate_role:evidence}`) already refer to, so the #40 flow is exactly
`descend(node) -> leaf_members[].record_version_id -> get-record(those rvids, effective_allowed)`. Resolution
order is `records` FIRST, then the source_chunk view (a typed rvid wins a collision; occurrence ids are
`occ_`-prefixed so a real collision is not reachable).

### 14.2 Output shape (`op: get-record`, READ-ONLY)
```
{ requested, found_count,
  records: [ { record_version_id, record_id, record_kind, namespace, found:true,
               effective_current, supersession_conflicted, superseded_by[],
               envelope: <the FULL s1 ENVELOPE -- byte-identical to list-records:
                          `_source_chunk_envelope(row)` for a chunk / `_record_envelope(row, eff)` for a
                          typed record (edges scope-redacted with `out_of_scope_edges_dropped` when scoped)>,
               evidence: <the HYDRATION body -- the shipped search hit-base derivation
                          (`_chunk_hit_base` / `_record_hit_base`) PLUS the full `text`:
                          text, content_hash, chunk_content_hash?, record_content_hash, source_content_hash?,
                          excerpt_hash?, span{start,end}, span_label, section_path, heading, chunk_type,
                          status, currentness, authority_level, namespace, source, source_path, abs_path,
                          source_version_id, provenance_mode, provenance{}, embedding_space_id> } ],  // sorted by record_version_id
  unresolved_count,                 // rvid resolved to NO catalog record -- count-only, NO metadata
  namespace_enforced, namespace_allowed[],
  namespace_violation_count,        // A5/U1' foreign/out-of-scope -- count-only (detail -> privileged security_log)
  working_denied_count,             // A5/U3' not conjunctively task_id+namespace scoped -- count-only
  current_only, current_excluded_count,   // A5/U4' current_only exclusions -- count-only
  schema_version, db }
```
- **`envelope` REUSES the shipped `list-records` derivation; `evidence` REUSES the shipped `search` hit-base
  derivation -- NO second provenance path** (acceptance a). The retrieval-stage lineage
  (`retrieval_stage_id`/`parent_stage_id`/`retrieval_plan_id`) is STRIPPED from `evidence`: a by-rvid fetch is a
  direct fetch, not a staged retrieval. The top-level `record_version_id`/`record_kind`/`namespace` are a quick
  index for #40; `envelope` is the s1 metadata; `evidence` is the hydration body.

### 14.3 Provenance holds (acceptance b)
- **source_chunk:** `evidence.content_hash` = the document-version sha256 (the SOURCE identity);
  `evidence.chunk_content_hash` = `record_content_hash` = `excerpt_hash` = `sha256(canonical chunk text)`; the
  `span{start,end}` reproduces the source bytes. get-record's chunk evidence (`text` / `chunk_content_hash` /
  `span`) is BYTE-IDENTICAL to the `export-chunk-texts` entry for the same chunk (the shipped byte-reproducing
  path) -- the gate asserts this equality.
- **typed record:** `evidence.content_hash` = `record_content_hash` = `sha256(text)` (as `ingest_records`
  computed it); a record with a real source span carries `provenance_mode=direct_span` + the span, else the
  provenance-mode-conditional shape (`derived_record`/`aggregate`/`tombstone`, U2').

### 14.4 A5 closure (acceptance c) -- identical DECISIONS to `search`
- **(U1') namespace CLOSURE.** `effective_allowed` is the CALLER-SUPPLIED CLOSED set (`_eff_from_args`:
  `effective_allowed_namespaces` / `filters.namespace` / a top-level `namespace`; **None = unscoped back-compat**,
  an **explicit EMPTY set = zero results** fail-closed). The canonical `ns_permitted` is enforced on EVERY
  returned record. A foreign/out-of-scope rvid FAILS CLOSED **count-only** -- the caller sees only
  `namespace_violation_count`; the identifying detail (`{candidate_kind, id, namespace}`) goes to the PRIVILEGED
  `security_log` (event `namespace_violation`), NEVER to the caller. Defense-in-depth: a record that reaches
  `records[]` outside the effective set is a fail-closed **`namespace_leak` ABORT** (detail to the security_log;
  the caller-visible error carries NO cross-namespace identity) -- the SAME assertion `search` makes.
- **(U3') working-kind.** A `record_kind=working` record is returned ONLY under **CONJUNCTIVE** access -- an
  in-scope namespace authorization (`effective_allowed` present AND `ns_permitted`) **AND** an exact `task_id`
  match (top-level `task_id`, or `filters.task_id`/`filters.working_task_id`). Absent EITHER -> count-only
  `working_denied_count` (event `working_kind_denied` to the security_log). Mirrors `_record_passes` -- "excluded
  by default" is too weak.
- **unresolved.** An rvid that resolves to no catalog record increments `unresolved_count` only (no id list, no
  metadata). The caller already holds its own requested rvids and diffs them against `records[].record_version_id`
  -- so an id list would be redundant AND a mild existence oracle; only the COUNT surfaces.

### 14.5 Version semantics (acceptance d)
- A by-rvid fetch is **VERSION-EXACT by nature** -- it returns the exact rvid as stored. The catalog-computed
  supersession flags are surfaced (never a silent pick): `effective_current` (`status==current` AND no reachable
  live in-scope successor), `superseded_by` (the immediate live successors), `supersession_conflicted`
  (`>=2` live successors). These reuse `_supersession_info` / `_effective_current` (U4', catalog/graph-computed,
  pool-independent).
- **`current_only`** (top-level `current_only`, or `filters.mode=current_only` / `filters.current_only` /
  `filters.exclude_stale`) EXCLUDES a record whose in-scope LIVE successor exists (as `current_excluded_count`),
  EVEN WHEN that successor is not in the requested rvid batch. DEFAULT is exact-fetch.

### 14.6 Determinism + read-only (acceptance d/e)
- **Deterministic + envelope-only:** `records[]` is sorted by `record_version_id` (input-permutation-independent);
  requested rvids are de-duplicated (first occurrence); NO timestamps in the result -> byte-identical on re-run.
- **READ-ONLY:** NO corpus writes, NO new table, NO migration. The ONLY side effect is the PRIVILEGED
  `security_log` (a DB table EXCLUDED from `catalog_digest` + an append-only file) on a violation -- the SAME
  behavior `search` has; it never changes `catalog_digest` / `corpus_version` / `shipped_tables_schema_sha`, so
  existing paths stay byte-identical and the double-run RESULT is byte-identical.
- **Input (wrapper -> worker):** `-TargetId` (single `target_id`), or via `-InputsJson` `rvids[]` /
  `record_version_ids[]` / a single `record_version_id`; `effective_allowed_namespaces[]`; `task_id`;
  `current_only`. The wrapper + worker BOTH fail closed with `missing_rvid` when none is supplied. get-record is a
  db-op (requires an existing db; NOT a create-op).

### 14.7 GATE (D-0077; this module owns the get-record gate)
Off-machine: `tests/test_get_record_i36.py` (cloud python, **38 checks**) -- envelope+evidence for both an rvid
kind; the `descend -> get-record` hydration FOLD flow; provenance (chunk_content_hash==sha256(text) &
== export-chunk-texts; typed content_hash==sha256(text)); A5 closure (foreign count-only + NO metadata leak;
unknown -> unresolved; working conjunctive matrix; empty-set fail-closed; unscoped back-compat); version-exact +
`current_only` (predecessor excluded, live successor kept, batch); read-only (catalog_digest + shipped-sha
unchanged) + determinism (byte-identical re-run + permutation-independent order) + integrity green; the
`missing_rvid` guard. Live: `tests/Invoke-ArtifactSearchTests.ps1` get-record section (real-worker via the
entrypoint) + the 0.6.0/0.6 version assertions. Shipped A6 regression stays green
(`tests/test_hierarchy_a6.py` 56/56).