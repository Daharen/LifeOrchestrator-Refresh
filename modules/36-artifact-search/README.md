# Module 36 -- artifact.search (0.6.0)

**Deterministic SQLite catalog + typed-record memory substrate + hybrid LEXICAL (FTS5) search + a
bounded-fanout navigation HIERARCHY.** The Collective Agent's authoritative catalog (D-0080 Wave 1/2, arch
position 23), built to the FROZEN **`core-docs/MEMORY_CONTRACT.md`** (D-0083) + **Amendment A4** (D-0092) +
**Amendment A5** (D-0096, Tier-0 namespace-closure + supersession-hardening) + **Amendment A6** (D-0098, i34
Tier-1 bounded-fanout hierarchy). A thin PowerShell entrypoint (`Invoke-ArtifactSearch.ps1`,
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

**0.5 realizes MEMORY_CONTRACT Amendment A6 (D-0098, i34 Tier-1 BOUNDED-FANOUT HIERARCHY; ADDITIVE +
backward-compatible; `schema_version 4->5`)** -- turns the A4/A5 RESERVED `node` seam into a real DETERMINISTIC
build (NO model). (H1) a `node` derived record + `nodes`/`hierarchies` tables + CANONICAL
`member_of_node`/`child_of_node` edges (the stored child/member lists are a rebuildable PROJECTION == the edges)
with a deterministic structural synopsis (bounded entity_union/lexical_descriptor + exact ranges/histograms + a
no-false-negative Bloom presence filter + a sufficient-statistics vector aggregate that is topology-independent +
byte-reproducible, ABSENT while the vector channel is empty). (H4) a BALANCED even-partition bulk-builder
(`MAX_FANOUT` default 16) whose balance is INDEPENDENT of the grouping key (no deep thin chains); live split is
deferred to i35 -- a corpus mutation sets `topology_state=rebuild_required` + flat-fallback. (H3) hierarchy
identity + ATOMIC tree-version publication (a compile pins one `tree_version`). (H2) THREE separated state axes
(evidence status / topology_state / synopsis freshness) with monotonic generations + CAS-cleared regen (closes
the ABA stale-clear race); `summary_stale` ROUTES but never ANSWERS. (H5, safety-critical) write-time +
transitive namespace HOMOGENEITY (separate roots for a multi-namespace compile). (H6, safety-critical)
authorization-bound `shortlist`/`descend` (`ns_permitted` at every hop; a foreign/out-of-scope `node_id` fails
closed count-only). **The load-bearing SAFE-PRUNING invariant** (frontier red-team `b4c90545`): navigation may
prioritize but MUST NOT exclude a branch without a channel-specific NO-FALSE-NEGATIVE proof (Bloom absence /
exact set / exact range); a bounded descriptor, a centroid, and a STALE synopsis NEVER prune. Node edges are
EXCLUDED from `catalog_digest` (the corpus fingerprint stays stable; zero nodes == flat retrieval byte-for-byte);
the hierarchy has its own `tree_digest`. Full record: `SCHEMA_NOTES.md` section 13.

**0.6 (i36, FANOUT_AGENT_002) adds the clean by-`record_version_id` `get-record` body-fetch op -- the i35 Lane A
FOLD RECONCILIATION (D-0100; ADDITIVE, READ-ONLY, NO migration, `schema_version` STAYS 5).** #40's leaf
HYDRATION read #36's `records` table directly because #36 had NO by-rvid op; `get-record` is the clean seam so a
future i37 #40 change can stop reaching into #36's internals. It takes rvid(s) (`-TargetId`, or an `rvids[]` /
`record_version_ids[]` array via `-InputsJson`) + the CALLER-SUPPLIED CLOSED `effective_allowed_namespaces`, and
returns per rvid the FULL s1 ENVELOPE (the shipped `_source_chunk_envelope` / `_record_envelope`) PLUS an
evidence hydration body (the shipped `_chunk_hit_base` / `_record_hit_base` provenance derivation + the full
`text`), **reusing the shipped provenance derivation -- no second path** (provenance holds: `content_hash` == the
source sha256; the span reproduces the source bytes). An rvid is EITHER a typed-record `record_version_id` (the
`records` table) OR a source_chunk `chunk_occurrence_id` (the `v_records_source_chunk` view) -- the SAME id space
`search` hits + `descend` leaf_members use. A5-CLOSED (identical DECISIONS to `search`): (U1') `ns_permitted` on
EVERY returned record; a foreign/out-of-scope rvid FAILS CLOSED count-only (`namespace_violation_count`;
identifying detail ONLY to the privileged security log) and a record reaching `records[]` outside scope is a
`namespace_leak` ABORT; (U3') a `working` record is returned ONLY under CONJUNCTIVE access (an in-scope namespace
authorization AND an exact `task_id`) else count-only `working_denied_count`; (U4') VERSION-EXACT by default (the
supersession flags `effective_current`/`superseded_by`/`supersession_conflicted` surfaced), with an optional
`current_only` that excludes a predecessor whose in-scope LIVE successor exists (`current_excluded_count`,
pool-independent). Deterministic + envelope-only (`records[]` sorted by `record_version_id`; unresolved rvids
surface count-only as `unresolved_count`); absent set = unscoped back-compat, an explicit EMPTY set = zero
results. **#40 ADOPTS it in i37** (this wave only SHIPS the op). Full record: `SCHEMA_NOTES.md` section 14.

Contract: `SKILL_CONTRACT.md` + `MEMORY_CONTRACT.md` (D-0083 + A4/D-0092 + A5/D-0096 + A6/D-0098). Schema + every
interpretation: `SCHEMA_NOTES.md` (authoritative for the fold). Work order: `WORK_ORDER.md`.

## Ops

| op | purpose |
|---|---|
| `ingest` | walk a root, content-hash inventory, detect new/changed/moved/deleted, Markdown-aware chunk (+ text fallback), FTS5 index, MOCK-embed as float32 BLOB, reconcile with NO dup chunks, explicit stale-fallback on unparseable change, tombstone deletions, integrity check, deterministic `catalog_digest` (extended to records) |
| `ingest-records` | the s1 typed-record SINK: land externally-produced records (from #38/#39) deterministically + idempotently; validate ids/required fields; reject malformed with a surfaced reason; materialize first-class edges |
| `list-records` | the s1 record ENVELOPE adapter (`source_chunk` via a view + typed records), with parent/child edges (A5: scoped edges redacted when a namespace filter is active); `working` records task-scoped-only, with the reserved store fields |
| `migrate` | forward-migrate a shipped-0.1/0.2/0.3/0.4 db to schema_version 5 IN PLACE, version-chained 1->2->3->4->5 (idempotent, no data loss, shipped tables byte-identical, catalog_digest unchanged) |
| `search` | retriever 0.2 + A4 + A5: ranked, provenance-complete hits across chunks AND records in DETERMINISTIC order -- span object + span_label, per-channel diagnostics; `score` retired. A5: `ns_permitted` enforced at every stage + graph hop (sanitized `namespace_violation_count`; leaked hit -> `namespace_leak` abort); `current_only` on catalog-computed `effective_current` (pool-independent); provenance_mode-conditional hits + reserved `candidate_role`/stage-lineage; `working` retrievable only via CONJUNCTIVE `task_id`+in-scope-namespace (#37/#40 consume) |
| `embed` | the MOCK embedding-provider envelope (shape matches the real adapter #35) |
| `integrity` | PRAGMA integrity_check + catalog invariants (extended: occurrence ids, vectors, records, staleness, serving) |
| `catalog` | `catalog_digest` + counts |
| `export-chunk-texts` / `store-embeddings` / `get-vector` | fold drop-in: export ordered chunk texts -> real adapter -> store float32 BLOB vectors by id -> round-trip |
| `get-record` | **i36/D-0100 (READ-ONLY, ADDITIVE):** by-`record_version_id` body-fetch for #40 leaf hydration -- rvid(s) + `effective_allowed_namespaces` -> per rvid the full s1 ENVELOPE + the evidence hydration body (text + provenance), reusing the shipped provenance derivation. A5-closed (`ns_permitted` per record -> foreign count-only; `working` needs CONJUNCTIVE `task_id`+namespace; version-exact default + optional `current_only`). An rvid is a typed-record `record_version_id` OR a source_chunk `chunk_occurrence_id`. NO writes / NO migration |
| `build-hierarchy` | A6: DETERMINISTIC balanced (re)build of the bounded-fanout tree (one per namespace, kind `source_module`); `max_fanout` default 16; atomic tree-version publication; `all_valid`/`topology_state`/`tree_digest` per namespace |
| `shortlist` | A6/H6: rank the AUTHORIZED hierarchy roots (the navigation frontier) by structural-synopsis match; `effective_allowed_namespaces` enforced on every node; navigation candidates only (never evidence) |
| `descend` | A6/H6: expand ONE frontier node into its direct children + leaf members; `ns_permitted` per hop; a foreign/out-of-scope `node_id` FAILS CLOSED count-only (no metadata) |
| `hierarchy` | A6: hierarchy status (identity, tree_version, topology_state, tree_digest, node/leaf counts, stale-node count; `include_nodes` for the full node projections) |
| `refresh-hierarchy` | A6/H2: lazily regenerate all stale node synopses bottom-up (CAS-cleared) |
| `hierarchy-mark-changed` / `hierarchy-regen` / `prune-verdict` | A6: the staleness-propagation, CAS-regen, and SAFE-PRUNING oracle entry points (mutation-path + ABA-race + no-false-negative gates) |

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

# i36 (D-0100): by-rvid get-record -- fetch a record's full envelope + evidence body for hydration
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op get-record -TargetId "sym.x@1" -DbPath .\runtime\catalog\as.db -InputsJson '{"effective_allowed_namespaces":["core-docs"]}'
# a batch of leaf rvids from a descend (the #40 hydration path), optionally current-only:
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"get-record","db":"...","rvids":["occ_...","sym.x@1"],"effective_allowed_namespaces":["core-docs"],"current_only":true}'
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
shipped-0.3 worker `fixtures/artifact_search_v3.py` (shipped tables byte-identical, catalog_digest unchanged);
the **A6 gates** (bounded-fanout build, balanced depth, safe-pruning, three-axis staleness + ABA, 4->5
migration; `tests/test_hierarchy_a6.py` off-machine = 56/56); and the **i36 get-record gate** (D-0100 fold:
envelope+evidence hydration, provenance holds, A5 namespace closure + working conjunctive scope, version-exact +
`current_only`, read-only/no-migration, determinism; `tests/test_get_record_i36.py` off-machine = 38/38). The
same pwsh harness is the cloud off-machine gate and the live Windows/executor gate.

## Layout

```
Invoke-ArtifactSearch.ps1     entrypoint (pwsh-file)
artifact_search.py            worker (SQLite + FTS5, stdlib only; schema v5)
skill.json                    manifest (0.6.0, contract v0.6)
SCHEMA_NOTES.md               schema + s1..s8 + A4 (s11) + A5 (s12) + A6 (s13) + i36 get-record (s14) interpretations (fold-authoritative)
WORK_ORDER.md                 work order
fixtures/repo/                bundled fixture corpus (markdown + text)
fixtures/artifact_search_v1.py  FROZEN shipped-0.1 worker (seeds a v1 db for the 1->2->..->5 migration test; do NOT edit)
fixtures/artifact_search_v2.py  FROZEN shipped-0.2 worker (seeds a v2 db for the 2->..->5 migration test; do NOT edit)
fixtures/artifact_search_v3.py  FROZEN shipped-0.3 worker (seeds a v3 db for the A5 3->4 migration GATE; do NOT edit)
fixtures/artifact_search_v4.py  FROZEN shipped-0.4 worker (seeds a v4 db for the A6 4->5 migration GATE; do NOT edit)
tests/                        Invoke-ArtifactSearchTests.ps1 (pwsh gate); test_hierarchy_a6.py (A6 off-machine); test_get_record_i36.py (i36 get-record off-machine)
examples/                     example-invocation.md, example-result.json
runtime/                      gitignored: catalog/*.db, artifacts/<id>/
```

## Non-goals (later waves)

A vector index / ANN / vector search; REAL embeddings (#35 ships the real adapter); #38 parsers / #39 episode
+ failure schemas; hierarchical summaries; the context compiler; UI; web search; a filesystem watcher. **A4
Tier-0 reserves the seams but does NOT build them:** the bounded-fanout tree / node synopses / shortlist-and-
descend; the working-memory store lifecycle; contradiction detection; the query-classification stage; the
selection policy (#37/#40).
