# artifact.search -- SCHEMA_NOTES (Module 36, skill `artifact.search` 0.4.0, schema_version 4)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold. The
orchestrator's fold smoke (repo.intel #38 / episode.memory #39 -> `ingest_records` -> retrieval; the i33
MIXED-NAMESPACE LEAKAGE-PATH fold) depends on it. 0.2 adopts the FROZEN **`core-docs/MEMORY_CONTRACT.md`**
(D-0083); 0.3 realizes Amendment A4 (D-0092, Tier-0 seam repairs) -- section 11; **0.4 realizes Amendment A5
(D-0096, i33 Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING) -- see section 12.** On any conflict that
contract + its gates win, and a divergence is reconciled at fold (never silently). Governing:
MEMORY_CONTRACT s1..s8 + **A4 + A5**; MEMORY_ARCHITECTURE s9/s10;
`research/2026-08-04-tier0-amendment-redteam.md` (changes 1-4); `research/2026-08-03-memory-architecture-seam-audit.md` s3;
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`; D-0080/D-0082/D-0083/D-0090/D-0092/**D-0096**; D-0077.

Worker: `artifact_search.py` (Python stdlib only: `sqlite3` + FTS5, `struct`). Entrypoint:
`Invoke-ArtifactSearch.ps1` (pwsh-file). CPU-only, no model, no network. `worker_version=0.4.0`,
`schema_version=4`. This EXTENDS the shipped 0.3 (schema_version 3), which EXTENDED 0.2 (2) and 0.1 (1);
all shipped ops stay regression-green (the full 0.3 suite is 100% green + the A5 gate tests -- 179/179
off-machine). A5 is ADDITIVE + backward-compatible: a v0.1.1/A4-conformant producer/consumer stays valid.

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
  is a top-level PURE function: `effective_allowed is None` (UNSCOPED) -> True; a `None`/missing candidate
  namespace under a closed set -> False (fail-closed); otherwise `str(candidate_namespace) in effective_allowed`
  -- PURE membership, NO wildcard/prefix/parent/shared, an EMPTY set permits nothing. A5(f) requires this
  predicate be authored ONCE (owned by #37 `lib/`, imported by #40) with #36 implementing the IDENTICAL decision
  and the i33 fold asserting byte-identical accept/reject across the three. **MIRROR NOTE (recorded for the
  fold):** at this worker's build time #37's standalone `ns_permitted` was NOT yet on disk (only
  `modules/37-retrieval-eval/lib/selpol_rrf_v1.py` existed), so per the worker prompt's sanctioned fallback #36
  MIRRORS the A5 semantics exactly, kept intentionally minimal + pure so the fold's byte-identity check is
  trivial. **The fold MUST assert `ns_permitted` decisions are byte-identical between #36's mirror and #37's
  canonical.** If they diverge, #36 adopts #37's (the canonical owner) with no semantic change expected.
- **The effective set is #36's ONLY dual-form site.** `effective_allowed_namespaces(filters)` returns `None`
  (absent `filters.namespace` = UNSCOPED back-compat) or a `frozenset`; an explicit empty set/list stays EMPTY
  (zero hits). The set carries BOTH the raw and the `_slug` form of each requested value because #36 stores TWO
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