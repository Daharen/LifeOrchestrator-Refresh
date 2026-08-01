# artifact.search -- SCHEMA_NOTES (Module 36, skill `artifact.search` 0.1.0)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold
(embedding adapter #35 -> `artifact.search` #36 -> retrieval-eval harness #37). The orchestrator's fold
smoke depends on it. Governing design: `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`
sections 6/7/8; D-0080/D-0081; the cross-module-smoke rule D-0077.

Worker: `artifact_search.py` (Python stdlib only: `sqlite3` + FTS5). Entrypoint: `Invoke-ArtifactSearch.ps1`
(pwsh-file). CPU-only, no model, no network. `parser_version` and `schema_version` are both `"1"`;
`worker_version` = `0.1.0`.

---

## 1. Determinism contract (READ FIRST)

- **The SQLite file is NOT byte-reproducible** (page layout, rowids, freelist depend on write history).
  Do not diff `.db` bytes. The **logical records and the `catalog_digest` ARE** reproducible.
- **`catalog_digest`** = `sha256` over sorted lines: one `CHK\t{rel_path}\t{content_hash}\t{chunk_index}\t{span_start}\t{span_end}\t{chunk_id}`
  per current chunk (ordered by `rel_path,chunk_index,chunk_id`), then one `DOC\t{rel_path}\t{status}\t{content_hash}|{parse_status}`
  per document (ordered by `rel_path`). Identical corpus **content** => identical digest **across runs AND
  machines** (it uses repo-relative paths + byte spans, never absolute paths, rowids, or timestamps).
  CRLF vs LF is handled: spans are BYTE offsets and `content_hash` is over raw bytes, so the digest is
  EOL-faithful (a CRLF core-doc and its LF copy are legitimately different content -> different digest).
- **Ids are content+path derived** (see section 2). Same inputs => same ids + same order. `created_at` /
  `mtime_utc` / `last_ingest_at` / `run_id` are provenance ONLY and never feed an id or the digest.
- Search output order is fully deterministic with a **stable `chunk_id` tie-break** (section 4).

## 2. SQLite schema (as implemented)

Identity ids (deterministic; `x[:24]` = first 24 hex of the sha256):

- `source_id`   = `_slug(label)` (lowercased, `[^a-z0-9._-]->-`) -- the LOGICAL corpus identity (stable,
  machine-independent). Absolute `root_path` is stored on `sources` as provenance only.
- `document_id` = `"doc_" + sha256(source_id "\0" rel_path)[:24]`
- `version_id`  = `"ver_" + sha256(document_id "\0" content_hash)[:24]`
- `chunk_id`    = `"chk_" + sha256(rel_path "\0" content_hash "\0" chunk_index)[:24]`

Tables:

- **`catalog_meta`**(key PK, value) -- `schema_version`, `created_at`.
- **`sources`**(source_id PK, label, root_path, created_at, last_ingest_at).
- **`documents`**(document_id PK, source_id, rel_path, abs_path, ext, source_type, **status** `active|deleted`,
  current_version_id, first_seen_at, last_seen_at; UNIQUE(source_id, rel_path)). `rel_path` is
  forward-slash, root-relative (the canonical path). `abs_path` is machine-specific provenance.
- **`document_versions`**(version_id PK, document_id, content_hash, size_bytes, mtime_utc, parser,
  parser_version, **parse_status** `ok|failed`, parse_error, chunk_count, **is_current** 0/1, created_at;
  UNIQUE(document_id, content_hash)). History: on change the OLD version row is kept with `is_current=0`
  (its derived rows are purged -- see section 3); a reverted content_hash re-activates its version row.
- **`chunks`**(chunk_id PK, version_id, document_id, source_id, rel_path, content_hash, chunk_index,
  span_start, span_end, section_path, heading, chunk_type, token_estimate, text, created_at).
  **Provenance is complete on every chunk**: `rel_path` + `content_hash` + byte `span` + `parser`(via its
  version) + `section_path`/`heading`. `text` = `raw_bytes[span_start:span_end].decode('utf-8')` (stored for
  FTS + snippet + provenance verification; files remain canonical -- the span re-derives the text exactly).
  `chunk_type` in {`markdown_section`, `text_block`}.
- **`chunk_embeddings`**(chunk_id, provider_id, dim, normalized, model_id, model_version, model_sha256,
  engine_build, vector(json float array), created_at; PRIMARY KEY(chunk_id, provider_id)). The `provider_id`
  + `dim` are stored on EVERY vector row so re-embedding on a model/dim change is possible and multiple
  providers can coexist per chunk (mock now; real #35 at fold).
- **`chunks_fts`** = FTS5 virtual table `fts5(text, heading, section_path, rel_path UNINDEXED, chunk_id
  UNINDEXED, tokenize='unicode61')`. Standalone (NOT external-content) -> no trigger/rowid coupling; exactly
  one FTS row per current chunk (an integrity invariant).
- **`ingest_runs`**(run_id PK, source_id, started_at, finished_at, added, changed, deleted, unchanged,
  parse_failures, moved, file_budget_hit) -- a lightweight per-ingest episode record.

## 3. Incremental ingest / reconcile (as implemented)

Walk order is deterministic (sorted dirs + files). Exclusions: default `exclude_dirs`
(`.git,node_modules,__pycache__,runtime,artifacts,.vs,.idea,bin,obj,.pytest_cache,_to_delete`) by path
segment + default `exclude` globs (`*.db,*.db-wal,*.db-shm,*.sqlite,*.sqlite3`); optional `include` globs
restrict inclusion. `max_files` truncates the sorted list and surfaces `file_budget_hit` + a warning.

Per file, keyed by `(source_id, rel_path)`:
- **unchanged**: current version's `content_hash` matches -> skip (no reprocessing).
- **new** / **changed**: purge the OLD current version's derived rows (chunks + FTS + embeddings), mark old
  version `is_current=0`, insert the new version + chunks + FTS + embeddings, point `current_version_id` at it.
- **deleted**: an `active` document not seen this walk -> purge derived rows, `status='deleted'`,
  `current_version_id=NULL` (version rows retained with `is_current=0`).
- **moved** (report-only): a deleted path's last content_hash reappears at a newly-added path -> reported in
  `moved[{from,to}]`. Mechanically a delete + add (chunk_ids include `rel_path`, so a move yields NEW ids at
  the new path -- correct provenance).

**No duplicate chunks** is guaranteed by: `chunk_id` PK + purge-before-reinsert + the integrity invariants
`no_duplicate_chunk_ids`, `no_duplicate_chunk_positions`, `no_chunks_on_noncurrent_versions`,
`no_chunks_on_deleted_documents`, `fts_row_count_equals_chunks`.

**Parse failures are SURFACED, never silently dropped**: a file that is oversize (`> max_file_bytes`, default
5 MB), binary (contains NUL) or non-UTF-8 is recorded as a document + version with `parse_status='failed'` +
`parse_error`, `chunk_count=0`, and listed in `ingest_report.parse_failures[]` + a warning (envelope status
-> `partial`).

**Chunking.** Markdown (`.md/.markdown/.mdown/.mkd`): segment at ATX headings `^#{1,6}\s+` (NOT inside a
```/~~~ code fence); `section_path` = ` / `-joined heading breadcrumb (a stack popped to the new level);
a section larger than `max_chunk_chars` (default 4000) is split at blank-line boundaries, never inside a
fence. Generic text (everything else decodable): blank-line-preferred grouping up to `max_chunk_chars`,
`section_path=null`, `chunk_type='text_block'`. Whitespace-only chunks are dropped. Spans are exact byte
offsets (terminator bytes included) -> EOL-agnostic.

## 4. D-0077 CONTRACT 1 -- embedding-provider interface (I CONSUME; mock now, real #35 at fold)

Op `embed`. Inputs: `texts` (array<string>, batch) and/or `text` (single) + optional `normalize` (bool,
default true) + `dim` (int, default 64). Result (inside the `lifeorch.skill.result/0.1` envelope's `result`):

```
{ provider_id, model_id, model_version, model_sha256, engine_build,
  dim:int, normalized:bool, count:int,
  vectors: [[float,...], ...],          # length == count, EXACT input order: vectors[i] <-> input[i]
  input_status: [ {index:int, status:"ok"|"skipped_empty"|"skipped_oversize", chars?:int}, ... ] }  # one per input
```

Mock (`provider_id="mock-hash-v1"`, `model_id="mock.embedding.hashvec"`): a DETERMINISTIC hashed
pseudo-vector -- `seed=sha256("mock-hash-v1\0{dim}\0{text}")`, then `dim` floats in [-1,1] from
`sha256(seed + i_le32)[:4]`, L2-normalized when `normalize`, rounded to 8 dp. Skipped inputs (empty/oversize)
get a **zero vector** so `vectors` stays length- and dim-aligned; `input_status` carries the exception WITH
its input index. `INTERPRETATION FOR THE FOLD`: the real adapter #35 MUST emit this EXACT shape (same field
set, `vectors` in input order, one `input_status` per input, `dim`/`normalized`/provider fields present). The
mock's per-input **zero-vector-for-skipped** convention is the consumed contract; if #35 instead OMITS
skipped vectors, the fold must reconcile alignment via `input_status.index` (record any divergence here at
fold). `store-embeddings` (below) accepts external vectors keyed by `chunk_id`, so #35's vectors drop in
without artifact.search calling #35 directly.

## 5. D-0077 CONTRACT 2 -- retriever interface (I PRODUCE; #37 consumes)

Op `search`. Inputs: `query:string`, `k:int` (default 10), `mode` `fts|exact` (default fts),
`filters?:{source, type(chunk_type), path_prefix(rel_path prefix), content_hash}`. Result:

```
{ query, mode, k, count, filters,
  results: [ { source_path,        # rel_path -- the canonical provenance path
               abs_path,           # machine-specific provenance (may be null)
               content_hash,       # the version identity (== sha256 of the source file bytes)
               chunk_id,
               span: {start,end},  # BYTE offsets into the source file
               section_path, heading, chunk_type, source,
               score,              # higher = better (fts: -bm25; exact: occurrences + 100 for a filename hit)
               snippet, rank } ... ] }
```

**Deterministic order** (stable tie-break): FTS -> `(-score, chunk_id)`; exact -> `(-score, rel_path,
chunk_index, chunk_id)`. Every result resolves to `source_path` + `content_hash` + `span` (the acceptance
provenance chain). FTS query is sanitized to word tokens AND-ed (avoids FTS5 syntax errors from raw input);
`exact` is a literal case-insensitive substring over chunk text AND `rel_path` (filename search ranks first).

## 6. Fold drop-in (export -> real embed -> store)

- `export-chunk-texts` -> `{count, chunks:[{chunk_id, rel_path, content_hash, span, text}]}` in deterministic
  order (`rel_path,chunk_index,chunk_id`) -- the ordered input for an external embedder.
- feed `chunks[].text` (in that order) to #35's `embed` -> vectors in the same order.
- `store-embeddings` `{chunk_ids[], vectors[][], provider_id, dim, normalized, model_*}` writes
  `chunk_embeddings` keyed by `chunk_id` (validates `len(vec)==dim`; unknown chunk_ids skipped + counted).

So the fold smoke is: `ingest` (embed_provider=none or mock) -> `export-chunk-texts` -> #35 `embed` ->
`store-embeddings` -> verify `chunk_embeddings` populated with #35 provenance -> `search` resolves to real
source spans -> re-`ingest` after a file change updates results -> `catalog_digest` stable on a repeat run.

## 7. Concurrency

`parallel_safe=false`: **reads** (search/integrity/catalog/export) are concurrency-safe; **writes**
(ingest/store-embeddings) serialize on the db (busy_timeout=30s). DISTINCT db paths are fully independent.
(The wave-level "parallel-safe (distinct module)" in the brief is about the fan-out -- this worker touches
only `modules/36-artifact-search` -- a DIFFERENT meaning than this manifest field.)

## 8. Non-goals (NOT built -- later waves)

AST/call-graph/symbol index, hierarchical summaries, episodes, failure memory, the context compiler, any UI,
web search, REAL embeddings (mock only; #35 ships the real adapter). Continuous filesystem watcher (7.5) is
out; ingest is invoked, incremental, and idempotent.
