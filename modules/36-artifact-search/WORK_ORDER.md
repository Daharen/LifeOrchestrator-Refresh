# Work Order: Artifact Search (`artifact.search`) -- 0.2.0 -> 0.3.0 (i32, MEMORY_CONTRACT A4 Tier-0 seams)

**Contract version targeted:** 0.3 (SKILL_CONTRACT) + **MEMORY_CONTRACT Amendment A4 (D-0092, Tier-0 seams)** |
**Author:** FANOUT_AGENT_001 (i32, plan fo-32-0fb25203) / 2026-08-04 |
**Prior revisions:** 0.1.0 (i25, MVP) -> 0.2.0 (i27, MEMORY_CONTRACT 0.2/D-0083 record envelope + ingest_records) |
**Roadmap entry:** `MODULE_ROADMAP.md#artifact.search` (arch position 23); governed by `MEMORY_ARCHITECTURE.md`
(D-0090) + `research/2026-08-03-memory-architecture-seam-audit.md` s3 (U1/U2/U4).

### i32 problem being solved (A4 Tier-0 seams)
The seam audit ranks the highest lock-in risks if the derived layers (indexes, hierarchy, packets) are built
WITHOUT them. artifact.search owns the record/retriever half: (U1) namespace must be a HARD partition, not a
soft boost, or cross-project bleed is baked into every derived layer; (U4) current-over-stale must be a real
retrieval MODE (the iterative-deterioration guard); (U2/U3) the flat catalog must ADMIT a `node` layer + a
per-`task_id` `working` record ADDITIVELY (no rewrite) so the Tier-1 tree/store drop in without a migration.
No tree/store/detection is BUILT here -- the kinds/edges/modes/isolation are RESERVED + enforced.

### i32 scope (in) -- all DONE (0.2.0 -> 0.3.0, ADDITIVE)
- (U1) `filters.namespace` a HARD retrieval boundary (single value OR explicit set), enforced before ranking +
  an all-hits-match assertion (`namespace_leak` fail-closed). OWNS **GATE TEST 1**.
- (U4) a `current_only` retrieval MODE (hard-exclude non-`current`); the `contradicts` edge reserved.
- (U2) reserve `node` kind + `member_of_node`/`child_of_node` edges; `SCHEMA_VERSION 2->3` in-place migration
  rewriting NONE of the shipped tables. OWNS **GATE TEST 2** (schema-evolution, byte-identical proof).
- (U3) reserve `working` kind (per-`task_id`, `content_role!=evidence`), EXCLUDED from ordinary retrieval
  unless task-scoped.
- (U5) confirm the retriever channel set stays FROZEN OPEN (no `{lexical,vector}` hard-coding).

### Problem being solved
Wave 2 producers (repo.intel #38, episode.memory #39) must land TYPED memory records -- symbols, relationships,
episodes, failures, summaries -- not just file chunks, and every retrievable object must satisfy ONE shared
provenance envelope so file-chunks do not silently become the universal memory abstraction. artifact.search is
the CONSUMER half: it adopts the FROZEN MEMORY_CONTRACT and exposes the generic `ingest_records` SINK.

### Immediate practical use
The orchestrator's D-0077 fold runs repo.intel/episode -> `ingest_records` -> retrieval smoke. The
retrieval-eval harness (#37) points at `search` (retriever 0.2). The context compiler + skill router later
consume `search` + `list-records`.

### Prior scope (0.2, i27) -- DONE
- The s1 record+provenance ENVELOPE + a `source_chunk` view/adapter (two-level chunk identity:
  chunk_content_hash vs chunk_occurrence_id, occurrence id index-free).
- The generic `ingest_records` SINK + `records`/`record_edges` tables + FTS; deterministic + idempotent;
  malformed-record rejection surfaced.
- schema_version 2 + forward MIGRATION of a shipped-0.1 db IN PLACE (no full re-ingest).
- parser + chunker + extractor fingerprints on every derived record.
- retriever 0.2 hit shape (span object + span_label; per-channel lexical/vector/fused ranks+scores; record
  fields; opaque `score` retired).
- s5 staleness ENUM (not a boolean).
- s2 float32 LE BLOB vectors keyed on `embedding_space_id` (JSON vector column retired).
- catalog hardening: transactional current-version swap + explicit stale fallback; tombstones;
  physical/logical identity; crash-safety fault-injection.

### Non-goals (out -- do NOT build)
A vector index / ANN / vector *search*; REAL embeddings (#35 owns; mock only); #38 parsers / #39 schemas; model
summaries; the context compiler; UI; web search; models.json / model modules. **A4 Tier-0 RESERVES (does NOT
build):** the bounded-fanout tree / node-synopsis generation / shortlist-and-descend; the working-memory store
lifecycle; contradiction DETECTION; the query-classification stage; the selection policy (#37/#40).

### Dependencies
Modules: none at build (Module 1 wrapper + SkillContract for tests). Tools: `pwsh>=7.4`, `python>=3.8` with
stdlib `sqlite3`+FTS5. Contracts: `lifeorch.skill.manifest/0.1` + `lifeorch.skill.result/0.1`; **MEMORY_CONTRACT
s1..s8**.

### Skill contract requirements
`skill_id=artifact.search`, `version=0.3.0`, `contract_version=0.3`, `determinism=deterministic`,
`parallel_safe=false`, `batch=false`, `streaming=false`. `result`=object; `confidence=null`;
`model_provenance=[]`; artifact kinds json/text.

### Inputs and outputs
See `skill.json` (inputs, incl. `records`/`ingest_run`/`filters`/`limit`/`target_kind`/`target_id`) and
`SCHEMA_NOTES.md` (schema + envelope + `ingest_records` input + retriever-0.2 hit shape + migration +
fingerprints).

### i32 (A4) acceptance criteria -- all VERIFIED (137/137 off-machine; +55/55 python harness)
- [x] (U1) `filters.namespace` an enforced HARD filter (single OR set) + all-hits-match assertion; GATE TEST 1
      proves ZERO cross-namespace leakage on a mixed 2-namespace fixture (records + chunk sources); no-namespace
      unchanged; `namespace_enforced` in `filter_decisions`.
- [x] (U4) `filters.mode=current_only` (+ top-level `mode=current_only` shim + `current_only`/`exclude_stale`
      aliases) HARD-excludes non-`current`; default mode unchanged; superseded-twin test passes.
- [x] (U2) `node` kind + `member_of_node`/`child_of_node`/`contradicts` edges accepted; `SCHEMA_VERSION 3` with
      a version-chained forward migration (1->2->3, no re-ingest); GATE TEST 2 proves a node + edges ingest +
      retrieve additively with `sources`/`documents`/`document_versions`/`chunks` BYTE-IDENTICAL pre/post
      (raw sqlite_master.sql AND `shipped_tables_schema_sha` == fresh v3).
- [x] (U3) `working` kind excluded from ordinary retrieval + `list-records` unless task-scoped; a working
      record without `task_id` is rejected `working_requires_task_id`.
- [x] ALL shipped 0.2 tests stay GREEN (regression); deterministic double-run digest; provenance holds; 0 orphans.

### Prior (0.2) MVP acceptance -- VERIFIED (regression-green under 0.3)
- [x] migrate a shipped-0.1 db to 0.2 (idempotent, no data loss; chunk_embeddings JSON -> float32 BLOB).
- [x] `ingest_records` stores >=3 record_kinds deterministically + idempotently, retrievable by kind with
      resolving provenance (record_version_id + source_version_id + span); malformed rejected with a reason.
- [x] the `source_chunk` view reproduces the shipped chunk provenance.
- [x] retriever-0.2 hits carry span{start,end}+span_label + per-channel diagnostics + record fields;
      deterministic order preserved; `score` retired.
- [x] float32 BLOB round-trips (byte-length validated) keyed on `embedding_space_id`.
- [x] the staleness ENUM is exercised (source change -> source_stale; exclude_stale filters).
- [x] catalog hardening: explicit stale-fallback; crash-safety fault-injection rolls back; integrity extended.
- [x] shipped ingest/search/embed/integrity/catalog/export/store ops stay GREEN (regression).
- [x] catalog_digest deterministic across a repeat run AND extended to cover records; canonical outputs
      double-run byte-identical (digest + search order; run ids are provenance).

### Tests
`tests/Invoke-ArtifactSearchTests.ps1` runs the REAL wrapper -> worker (fixtures/repo + core-docs slice) plus
the 0.2 sections (17-24) AND the A4 sections (**25** U1 GATE TEST 1 namespace, **26** U4 current_only, **27**
U3 working isolation, **28** U2 GATE TEST 2 schema-evolution). Off-machine (cloud pwsh 7.4.6 + python FTS5)
FIRST, then `-Live` on the Windows executor; canonical outputs double-run byte-identical. Migration tests seed
a v1 db from FROZEN `fixtures/artifact_search_v1.py` (1->3) and a v2 db from FROZEN
`fixtures/artifact_search_v2.py` (2->3, byte-identical proof). 137/137 off-machine (pwsh) + a standalone
python harness (55/55) exercised the same gates directly against `run()`.

### Registry / state updates
`docs:[]` -- the worker reports; the ORCHESTRATOR mirrors + folds all core-docs (MODULE_ROADMAP /
CURRENT_STATE / MEMORY_CONTRACT adoption note / DECISION_LOG) at fold. Do NOT edit any core-doc here.

### Known follow-on work
Vector index / ANN + real-embedding fold (#35, D-0077); #38 repo intelligence + #39 episode/failure producers
building to this `ingest_records` sink; hierarchical summaries; the context compiler; a filesystem watcher;
full-corpus (~200 MB) CPU-only rehearsal (MEMORY_CONTRACT s7); the embedding-provider 0.2 `embed` envelope
(#35's adoption item).

### STOP conditions
Scope beyond the list above; a missing dependency; a contract gap -> stop + propose (amend MEMORY_CONTRACT via
its s0 protocol), don't freelance. MVP acceptance met -> stop.
