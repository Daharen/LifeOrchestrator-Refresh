# Work Order: Artifact Search (`artifact.search`)

**Contract version targeted:** 0.2 · **Author:** FANOUT_AGENT_002 (i25, plan fo-25-3b718a13) / 2026-08-01 ·
**Roadmap entry:** `MODULE_ROADMAP.md#artifact.search` (Wave 1 coding lane, arch position 23)

### Problem being solved
The Collective Agent (D-0080) needs an authoritative, queryable catalog of the repo's content with full
provenance, before any vector integration or context compiler. Nothing today can answer "which file/section
contains X" deterministically with a span back to the source.

### Immediate practical use
The retrieval-eval harness (#37) points at `search` to measure retrieval quality; the fold smoke feeds real
embeddings (#35) via `store-embeddings`. Later, the context compiler and skill router consume `search`.

### Explicit scope (in)
- SQLite schema: sources / documents / document_versions / chunks / chunk_embeddings + provenance
  (source_path, content_hash, byte span, parser, parser_version, created_at) -- SQLite owns ids/versions/hashes/status.
- File inventory + content hash; new/changed/moved/deleted detection; parse failures SURFACED.
- Markdown-aware chunking (headings/sections/code-fence-aware) + generic-text fallback.
- SQLite FTS5 over chunk text; metadata filters (source/type/path/content_hash).
- Embedding-provider seam with a DETERMINISTIC MOCK (D-0077 contract 1; provider_id + dim on every vector).
- Result -> source_path + content_hash + span provenance (D-0077 contract 2, the retriever interface).
- Incremental, DETERMINISTIC ingest (id/order stable), reconcile with NO dup chunks, a DB integrity check.
- CLI/skill contract exposing at least `ingest` and `search` (+ embed/integrity/catalog/export/store).

### Non-goals (out -- do NOT build)
AST/call-graph/symbol index; hierarchical summaries; episodes; failure memory; context compiler; UI; web
search; REAL embeddings (mock only -- #35 ships the real adapter); filesystem watcher.

### Dependencies
- Modules: none at build (Module 1 wrapper + SkillContract for tests). Tools: `pwsh>=7.4`, a `python>=3.8`
  with stdlib `sqlite3`+FTS5. Contract features: `lifeorch.skill.manifest/0.1` + `lifeorch.skill.result/0.1`.

### Skill contract requirements
`skill_id=artifact.search`, `version=0.1.0`, `determinism=deterministic`, `parallel_safe=false` (shared-db
writes serialize; reads safe; distinct dbs independent), `batch=false`, `streaming=false`. `result` = object;
`confidence=null`; `model_provenance=[]`; artifact kinds json/text.

### Inputs and outputs
See `skill.json` (inputs) and `SCHEMA_NOTES.md` (schema + both interfaces + result shapes).

### Artifact structure
`runtime/artifacts/<invocation_id>/`: `result.json`, `as_meta.json`, `as_args.json`, `worker.log`,
`stderr.txt`, + per-op (`ingest_report.json`+`catalog_digest.txt` / `search_results.json` / `embeddings.json`
/ `integrity.json` / `catalog.json` / `chunk_texts.json`). Catalog db: `runtime/catalog/artifact_search.db`.

### Proposed implementation
**Language:** PowerShell entrypoint + Python worker (the D-0021 worker+meta hand-off, as image.util #15).
Python owns SQLite/FTS5/chunking/hashing (clean + deterministic); pwsh owns the envelope + artifact hashing +
python resolution. Stdlib only -> no install.

### External tools or models
None to install. System python (Python312) already present (`CURRENT_STATE.md`).

### Tests
Direct + through the wrapper: `tests/Invoke-ArtifactSearchTests.ps1` runs the REAL wrapper -> worker over
`fixtures/repo` + a bounded real `core-docs` slice. Off-machine (cloud pwsh 7.4.6 + python FTS5) FIRST, then
`-Live` on the Windows executor.

### MVP acceptance criteria
- [x] index the bundled fixture repo AND a bounded real core-docs slice.
- [x] exact + FTS retrieval, both provenance-complete (source_path + content_hash + span).
- [x] DETERMINISTIC re-ingest (id/order stable; identical `catalog_digest` across fresh dbs; idempotent same-db).
- [x] changed + deleted reconciliation with NO duplicate chunks; moved detection (report).
- [x] a DB integrity check passes (PRAGMA + catalog invariants).
- [x] provenance from every result to its source span (byte offsets verified against the file).
- [x] mock-embedding contract tests (shape + input-order + dim + batch==single + determinism) that also pass
      against the real adapter (shape-level).
- [x] parse failures surfaced (never silently dropped).

### Manual verification procedure
Ingest core-docs; `search -Mode exact -Query "D-0080"`; open the returned `source_path` at `span` and confirm
the text; re-ingest and confirm `unchanged` + identical digest.

### Registry / state updates
`docs:[]` -- the worker reports; the ORCHESTRATOR mirrors + folds all core-docs (MODULE_ROADMAP /
CURRENT_STATE / TOOL_MODEL_REGISTRY / DECISION_LOG) at fold. Do NOT edit any core-doc here.

### Known follow-on work
Repository intelligence (symbols/AST, Wave 2/3); the real embedding adapter fold (#35, D-0077); summaries;
context compiler; a filesystem watcher for continuous update.

### STOP conditions
Scope beyond the list above; a missing dependency; a contract gap -> stop + propose, don't freelance. MVP
acceptance met -> stop.
