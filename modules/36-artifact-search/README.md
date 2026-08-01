# Module 36 -- artifact.search (0.2.0)

**Deterministic SQLite catalog + typed-record memory substrate + hybrid LEXICAL (FTS5) search.** The
Collective Agent's authoritative catalog (D-0080 Wave 1/2, arch position 23), built to the FROZEN
**`core-docs/MEMORY_CONTRACT.md`** (D-0083). A thin PowerShell entrypoint (`Invoke-ArtifactSearch.ps1`,
`pwsh-file`) over a stdlib-only Python worker (`artifact_search.py`) that owns a SQLite database with FTS5.
CPU-only, no model, no network, `determinism=deterministic`.

0.2 adopts the MEMORY_CONTRACT s1 record+provenance ENVELOPE, adds the generic **`ingest_records` SINK** so
Wave-2 producers (repo.intel #38, episode.memory #39) can land TYPED records (symbol / relationship / episode
/ failure / summary / ...) -- not chunks, forward-migrates a shipped-0.1 db in place, stores vectors as a
**float32 LE BLOB** keyed on `embedding_space_id`, and returns the **retriever-0.2 hit shape** (span object +
span_label + per-channel diagnostics; the opaque `score` is retired).

Contract: `SKILL_CONTRACT.md` (v0.2) + `MEMORY_CONTRACT.md` (D-0083). Schema + every interpretation:
`SCHEMA_NOTES.md` (authoritative for the fold). Work order: `WORK_ORDER.md`.

## Ops

| op | purpose |
|---|---|
| `ingest` | walk a root, content-hash inventory, detect new/changed/moved/deleted, Markdown-aware chunk (+ text fallback), FTS5 index, MOCK-embed as float32 BLOB, reconcile with NO dup chunks, explicit stale-fallback on unparseable change, tombstone deletions, integrity check, deterministic `catalog_digest` (extended to records) |
| `ingest-records` | the s1 typed-record SINK: land externally-produced records (from #38/#39) deterministically + idempotently; validate ids/required fields; reject malformed with a surfaced reason; materialize first-class edges |
| `list-records` | the s1 record ENVELOPE adapter (`source_chunk` via a view + typed records), with parent/child edges |
| `migrate` | forward-migrate a shipped-0.1 db to schema_version 2 IN PLACE (idempotent, no data loss) |
| `search` | retriever 0.2: ranked, provenance-complete hits across chunks AND records in DETERMINISTIC order -- span object + span_label, record fields, per-channel diagnostics; `score` retired (#37 consumes) |
| `embed` | the MOCK embedding-provider envelope (shape matches the real adapter #35) |
| `integrity` | PRAGMA integrity_check + catalog invariants (extended: occurrence ids, vectors, records, staleness, serving) |
| `catalog` | `catalog_digest` + counts |
| `export-chunk-texts` / `store-embeddings` / `get-vector` | fold drop-in: export ordered chunk texts -> real adapter -> store float32 BLOB vectors by id -> round-trip |

## Invocation

```powershell
# index a corpus (creates the db)
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op ingest -Source core-docs -Root ..\..\core-docs -DbPath .\runtime\catalog\as.db

# search it (retriever 0.2 hit shape)
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "resource lease" -Mode fts -K 5 -DbPath .\runtime\catalog\as.db

# land typed records (the s1 SINK) + list the envelope
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"ingest-records","db":"...","ingest_run":{"producer":"repo.intel","namespace":"core-docs"},"records":[{"record_id":"sym.x","record_version_id":"sym.x@1","record_kind":"symbol","namespace":"core-docs","text":"def x(): ..."}]}'
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"list-records","db":"...","filters":{"record_kind":"symbol"}}'

# migrate a shipped-0.1 db in place
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op migrate -DbPath .\runtime\catalog\as.db
```

Also callable through the Module 1 wrapper. Every invocation emits one `lifeorch.skill.result/0.1` envelope on
stdout and writes `result.json` + op artifacts under `runtime/artifacts/<invocation_id>/`. Exits 0 whenever a
valid envelope is produced.

## Requirements

- `pwsh >= 7.4`.
- A `python >= 3.8` whose stdlib `sqlite3` has **FTS5** (probed by the wrapper). On this box that is
  `C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe`; the wrapper resolves it (config shim ->
  literal -> `where.exe` fallbacks) or takes `-PythonPath`.

## Determinism

Chunk/document/version ids are content+path derived; the s1 `chunk_occurrence_id` derives ONLY from immutable
inputs (never insertion order); `catalog_digest` (extended to records + edges) is byte-identical for identical
corpus+records **content** across runs AND machines. The SQLite file itself is NOT byte-reproducible. Run ids
(`created_by_ingest_run`) are provenance and never feed an id or the digest. See `SCHEMA_NOTES.md` section 1.

## Tests

```
pwsh -NoProfile -File tests\Invoke-ArtifactSearchTests.ps1 [-PythonPath <python>] [-PwshPath <pwsh>]
```

Runs the REAL wrapper -> worker over `fixtures/repo` + a bounded real `core-docs` slice, plus the 0.2 gates:
migration from a FROZEN shipped-0.1 worker (`fixtures/artifact_search_v1.py`), `ingest_records` (kinds /
idempotent / reject / edges / provenance), the retriever-0.2 hit shape, the staleness enum, float32 BLOB
round-trip, stale-fallback + crash-safety fault injection, and digest-extended determinism. The same harness
is the cloud off-machine gate and the live Windows/executor gate. **113/113 off-machine.**

## Layout

```
Invoke-ArtifactSearch.ps1     entrypoint (pwsh-file)
artifact_search.py            worker (SQLite + FTS5, stdlib only; schema v2)
skill.json                    manifest (0.2.0, contract v0.2)
SCHEMA_NOTES.md               schema + s1..s8 interpretations (fold-authoritative)
WORK_ORDER.md                 work order
fixtures/repo/                bundled fixture corpus (markdown + text)
fixtures/artifact_search_v1.py  FROZEN shipped-0.1 worker (seeds a v1 db for the migration test; do NOT edit)
tests/                        Invoke-ArtifactSearchTests.ps1
examples/                     example-invocation.md, example-result.json
runtime/                      gitignored: catalog/*.db, artifacts/<id>/
```

## Non-goals (later waves)

A vector index / ANN / vector search; REAL embeddings (#35 ships the real adapter); #38 parsers / #39 episode
+ failure schemas; hierarchical summaries; the context compiler; UI; web search; a filesystem watcher.
