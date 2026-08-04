# Module 36 -- artifact.search (0.4.0)

**Deterministic SQLite catalog + typed-record memory substrate + hybrid LEXICAL (FTS5) search.** The
Collective Agent's authoritative catalog (D-0080 Wave 1/2, arch position 23), built to the FROZEN
**`core-docs/MEMORY_CONTRACT.md`** (D-0083) + **Amendment A4** (D-0092) + **Amendment A5** (D-0096, Tier-0
namespace-closure + supersession-hardening). A thin PowerShell entrypoint (`Invoke-ArtifactSearch.ps1`,
`pwsh-file`) over a stdlib-only Python worker (`artifact_search.py`) that owns a SQLite database with FTS5.
CPU-only, no model, no network, `determinism=deterministic`.

0.2 adopts the MEMORY_CONTRACT s1 record+provenance ENVELOPE, adds the generic **`ingest_records` SINK** so
Wave-2 producers (repo.intel #38, episode.memory #39) can land TYPED records (symbol / relationship / episode
/ failure / summary / ...) -- not chunks, forward-migrates a shipped-0.1 db in place, stores vectors as a
**float32 LE BLOB** keyed on `embedding_space_id`, and returns the **retriever-0.2 hit shape** (span object +
span_label + per-channel diagnostics; the opaque `score` is retired).

**0.3 realizes MEMORY_CONTRACT Amendment A4 (D-0092, Tier-0 seam repairs; ADDITIVE + backward-compatible):**
(U1) `filters.namespace` is a HARD retrieval boundary (a single value OR an explicit set) enforced before
ranking with an all-hits-match assertion (a cross-namespace hit is a fail-closed `namespace_leak`); (U4) a
`current_only` retrieval MODE hard-excludes any non-`current` record; (U2) the CLOSED `record_kind` enum
RESERVES `node` (hierarchy seam) + `working` (per-`task_id` working memory, excluded from ordinary retrieval)
and the edge set RESERVES `member_of_node`/`child_of_node`/`contradicts` -- all admitted via a
`schema_version 2->3` in-place migration that rewrites NONE of the shipped tables (NO tree/store/detection
built). Full record: `SCHEMA_NOTES.md` section 11.

**0.4 realizes MEMORY_CONTRACT Amendment A5 (D-0096, i33 Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING;
ADDITIVE + backward-compatible)** -- #36 is the retriever/catalog ENFORCEMENT POINT: (U1') ONE canonical
`ns_permitted` predicate enforced at EVERY stage + graph hop with EVERY returned/reachable object scope-checked;
a cross-namespace candidate is EXCLUDED before ranking leaving only a `namespace_violation_count` (identifying
detail -> a privileged local security log, never the caller); a persisted cross-namespace derivative is REJECTED
at ingest (`cross_namespace_derivation`); a leaked hit is a fail-closed `namespace_leak` abort. (U4')
candidate-INDEPENDENT supersession: a `superseded` s5 value + `superseded_by`/`supersedes` edges +
catalog-computed `effective_current`, so `current_only` excludes a predecessor even when its successor is ABSENT
from the pool; a branch of >=2 live successors is flagged conflicted. (U2') provenance_mode-conditional hits +
reserved `candidate_role`/retrieval-stage lineage. (U3') working-store field reservations + hardened CONJUNCTIVE
working access (exact `task_id` AND an in-scope namespace). All via a `schema_version 3->4` in-place migration
that rewrites NONE of the shipped tables. Full record: `SCHEMA_NOTES.md` section 12.

Contract: `SKILL_CONTRACT.md` + `MEMORY_CONTRACT.md` (D-0083 + A4/D-0092 + A5/D-0096). Schema + every
interpretation: `SCHEMA_NOTES.md` (authoritative for the fold). Work order: `WORK_ORDER.md`.

## Ops

| op | purpose |
|---|---|
| `ingest` | walk a root, content-hash inventory, detect new/changed/moved/deleted, Markdown-aware chunk (+ text fallback), FTS5 index, MOCK-embed as float32 BLOB, reconcile with NO dup chunks, explicit stale-fallback on unparseable change, tombstone deletions, integrity check, deterministic `catalog_digest` (extended to records) |
| `ingest-records` | the s1 typed-record SINK: land externally-produced records (from #38/#39) deterministically + idempotently; validate ids/required fields; reject malformed with a surfaced reason; materialize first-class edges |
| `list-records` | the s1 record ENVELOPE adapter (`source_chunk` via a view + typed records), with parent/child edges (A5: scoped edges redacted when a namespace filter is active); `working` records task-scoped-only, with the reserved store fields |
| `migrate` | forward-migrate a shipped-0.1/0.2/0.3 db to schema_version 4 IN PLACE, version-chained 1->2->3->4 (idempotent, no data loss, shipped tables byte-identical, catalog_digest unchanged) |
| `search` | retriever 0.2 + A4 + A5: ranked, provenance-complete hits across chunks AND records in DETERMINISTIC order -- span object + span_label, per-channel diagnostics; `score` retired. A5: `ns_permitted` enforced at every stage + graph hop (sanitized `namespace_violation_count`; leaked hit -> `namespace_leak` abort); `current_only` on catalog-computed `effective_current` (pool-independent); provenance_mode-conditional hits + reserved `candidate_role`/stage-lineage; `working` retrievable only via CONJUNCTIVE `task_id`+in-scope-namespace (#37/#40 consume) |
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

Runs the REAL wrapper -> worker over `fixtures/repo` + a bounded real `core-docs` slice, plus the 0.2 gates
(migration from a FROZEN shipped-0.1 worker, `ingest_records` kinds/idempotent/reject/edges/provenance, the
retriever-0.2 hit shape, the staleness enum, float32 BLOB round-trip, stale-fallback + crash-safety fault
injection, digest-extended determinism), the **A4 gates** (namespace envelope filter, current_only twin,
working isolation, schema-evolution v2->v3), and the **A5 gates**: GATE TEST 1 (U1' namespace CLOSURE --
per-hop + all-object scope-check + sanitized `namespace_violation_count` + cross-namespace derivation/
supersession rejection at ingest + per-hop walk block), GATE TEST 2 (U4' POOL-INDEPENDENT `current_only` +
branch-conflict flag + supersession integrity), GATE TEST 3 (U3' CONJUNCTIVE working access), U2'
provenance_mode/candidate_role/stage-lineage, and the schema_version 3->4 in-place migration from a FROZEN
shipped-0.3 worker `fixtures/artifact_search_v3.py` (shipped tables byte-identical, catalog_digest unchanged).
The same harness is the cloud off-machine gate and the live Windows/executor gate. **179/179 off-machine.**

## Layout

```
Invoke-ArtifactSearch.ps1     entrypoint (pwsh-file)
artifact_search.py            worker (SQLite + FTS5, stdlib only; schema v4)
skill.json                    manifest (0.4.0, contract v0.4)
SCHEMA_NOTES.md               schema + s1..s8 + A4 (section 11) + A5 (section 12) interpretations (fold-authoritative)
WORK_ORDER.md                 work order
fixtures/repo/                bundled fixture corpus (markdown + text)
fixtures/artifact_search_v1.py  FROZEN shipped-0.1 worker (seeds a v1 db for the 1->2->3->4 migration test; do NOT edit)
fixtures/artifact_search_v2.py  FROZEN shipped-0.2 worker (seeds a v2 db for the 2->3->4 migration test; do NOT edit)
fixtures/artifact_search_v3.py  FROZEN shipped-0.3 worker (seeds a v3 db for the A5 3->4 migration GATE; do NOT edit)
tests/                        Invoke-ArtifactSearchTests.ps1
examples/                     example-invocation.md, example-result.json
runtime/                      gitignored: catalog/*.db, artifacts/<id>/
```

## Non-goals (later waves)

A vector index / ANN / vector search; REAL embeddings (#35 ships the real adapter); #38 parsers / #39 episode
+ failure schemas; hierarchical summaries; the context compiler; UI; web search; a filesystem watcher. **A4
Tier-0 reserves the seams but does NOT build them:** the bounded-fanout tree / node synopses / shortlist-and-
descend; the working-memory store lifecycle; contradiction detection; the query-classification stage; the
selection policy (#37/#40).
