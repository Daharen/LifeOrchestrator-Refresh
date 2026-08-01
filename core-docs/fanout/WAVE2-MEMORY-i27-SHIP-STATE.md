# WAVE 2 (Collective Agent memory RECORDS) -- SHIP STATE (i27, plan fo-27-bab47060, D-0084)

**Shipped 2026-08-01.** Built to MEMORY_CONTRACT 0.2 (D-0083). 3 CPU lanes (GPU + frontier lanes skipped); docs:[] workers; named-files-only dev.ship; native-git verified. 0 UNMANAGED orphans.

## Modules

- **#36 artifact.search 0.1.0 -> 0.2.0** (`b57d328`, CONSUMER) -- the s1 record+provenance envelope + a `source_chunk` view; a generic `ingest_records` SINK (records/record_edges + FTS; deterministic + idempotent; malformed-reject; first-class edges); schema_version 2 + an in-place 0.1->0.2 migration (chunk_embeddings JSON -> float32 LE BLOB, no data loss); parser/chunker/extractor fingerprints; retriever-0.2 hits (span object+span_label, per-channel lexical/vector/fused ranks+scores, opaque score RETIRED); s5 staleness ENUM + exclude_stale; float32 LE BLOB vectors keyed on embedding_space_id; catalog hardening (stale-fallback, tombstones, physical/logical identity, crash-safety fault injection). NEW ops: ingest-records / list-records / migrate / get-vector. 113/113 cloud + 113/113 -Live.
- **#38 repo.intel 0.1.0** (`cd53565`, PRODUCER, NEW) -- deterministic type-aware repo parser -> TYPED s1 record-envelope artifacts (symbol/entity/relationship/skill/summary); Markdown hierarchy + pwsh/python symbols + imports + skill.json manifests + relationship edges + deterministic structural summaries; allowlisted roots + tested exclusions; s1 validator; records.jsonl / ingest_records.json drop-ins. 65/65 pwsh + 37/37 python cloud + 65/65 -Live.
- **#39 episode.record 0.1.0** (`b381686`, PRODUCER, NEW) -- episode + failure s1 record schemas + a deterministic recorder (complete episode even on a failed/truncated trace) + a task-conditioned failure-signature retrieval seam + an s1 validator (content_hash provenance recompute). 114/114 cloud + 114/114 -Live.

## D-0077 cross-module smoke -- PASSED

repo.intel index (198 records, all 5 kinds; deterministic re-run) + episode.record (episode + failure) -> artifact.search 0.2 ingest-records (repo.intel 198 accepted / 0 rejected; episode+failure accepted) -> list-records by kind resolves the s1 envelope + provenance (episode derivation_refs) -> search returns the retriever-0.2 hit shape (span object+label, per-channel diagnostics, tie_break_key, no opaque score) -> provenance validated (chunk hit content_hash == file sha256; cited span reproduces source) -> re-ingest idempotent (catalog_digest stable) -> chunk path coexists (6 chunks) -> integrity OK. 0 orphans.

## 2 producer/consumer divergences (BRIDGED at fold; follow-on)

1. episode.record emits `record_kind: "episode_stage"`, NOT in the frozen MEMORY_CONTRACT s1 record_kind enum -> #36 0.2 rejects (`unknown_record_kind`). Stages also live in episode.body.stage_sequence -> the fold dropped the redundant episode_stage records.
2. episode.record emits `status` as an OBJECT `{state, stale_reasons, verified}`; #36 0.2 enforces the s5 STRING enum -> rejects (`invalid_status`). The fold coerced status -> status.state.

repo.intel conformed (string status; in-enum kinds). NEITHER is a #36 defect. FOLLOW-ON: episode.record 0.1.1 conformance (status -> s5 string; stages as edges/body) AND/OR a MEMORY_CONTRACT s0 amendment (add `episode_stage`; freeze the status representation).

## Next

Wave 3 (context compiler + skill-card/registry + retrieval reranker) OR the episode.record 0.1.1 conformance + contract amendment first -- Nicholas's call. Residual: #35 embedding 0.2 adoption + real vector SEARCH (retrieval wave); the ~200 MB full-corpus CPU rehearsal (MEMORY_CONTRACT s7).
