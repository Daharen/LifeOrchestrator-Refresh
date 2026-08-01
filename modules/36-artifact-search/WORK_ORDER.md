# Work Order: Artifact Search (`artifact.search`) -- 0.1.0 -> 0.2.0

**Contract version targeted:** 0.2 (SKILL_CONTRACT) + **MEMORY_CONTRACT 0.2 (D-0083)** |
**Author:** FANOUT_AGENT_001 (i27, plan fo-27-bab47060) / 2026-08-01 |
**Roadmap entry:** `MODULE_ROADMAP.md#artifact.search` (Wave 2 CONSUMER lane, arch position 23)

### Problem being solved
Wave 2 producers (repo.intel #38, episode.memory #39) must land TYPED memory records -- symbols, relationships,
episodes, failures, summaries -- not just file chunks, and every retrievable object must satisfy ONE shared
provenance envelope so file-chunks do not silently become the universal memory abstraction. artifact.search is
the CONSUMER half: it adopts the FROZEN MEMORY_CONTRACT and exposes the generic `ingest_records` SINK.

### Immediate practical use
The orchestrator's D-0077 fold runs repo.intel/episode -> `ingest_records` -> retrieval smoke. The
retrieval-eval harness (#37) points at `search` (retriever 0.2). The context compiler + skill router later
consume `search` + `list-records`.

### Explicit scope (in) -- all DONE
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
summaries; the context compiler; UI; web search; models.json / model modules.

### Dependencies
Modules: none at build (Module 1 wrapper + SkillContract for tests). Tools: `pwsh>=7.4`, `python>=3.8` with
stdlib `sqlite3`+FTS5. Contracts: `lifeorch.skill.manifest/0.1` + `lifeorch.skill.result/0.1`; **MEMORY_CONTRACT
s1..s8**.

### Skill contract requirements
`skill_id=artifact.search`, `version=0.2.0`, `contract_version=0.2`, `determinism=deterministic`,
`parallel_safe=false`, `batch=false`, `streaming=false`. `result`=object; `confidence=null`;
`model_provenance=[]`; artifact kinds json/text.

### Inputs and outputs
See `skill.json` (inputs, incl. `records`/`ingest_run`/`filters`/`limit`/`target_kind`/`target_id`) and
`SCHEMA_NOTES.md` (schema + envelope + `ingest_records` input + retriever-0.2 hit shape + migration +
fingerprints).

### MVP acceptance criteria -- all VERIFIED (113/113 off-machine)
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
the 0.2 sections (17-24). Off-machine (cloud pwsh 7.4.6 + python FTS5) FIRST, then `-Live` on the Windows
executor; canonical outputs double-run byte-identical. Migration test seeds a v1 db from the FROZEN
`fixtures/artifact_search_v1.py`.

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
