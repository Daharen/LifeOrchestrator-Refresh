# WAVE 1 (Collective Agent memory substrate) -- SHIP STATE (i25, plan fo-25-3b718a13, D-0082)

**Shipped 2026-08-01.** Three NEW modules; docs:[] workers; named-files-only dev.ship; native-git verified. 0 UNMANAGED orphans.

## Modules

- **#35 embedding.local 0.1.0** (`99b6590`, GPU lane) -- wires `embedding.qwen3-0p6b` (dim 1024) as a transient CUDA transformers worker (last-token + L2; NOT a persistent server); DEFINES the embedding-provider interface; det cos_dist 2.2e-16, batch==single 8.7e-13, peak VRAM 2.39 GB, CPU-fallback feasible; models.json wired (gateway `wired:false` kept) -> #7 42/42; tests 42/42 (26 off + 16 `-Live`).
- **#36 artifact.search 0.1.0** (`30ef7bd`, coding lane) -- SQLite catalog + FTS5 hybrid-lexical; Markdown-aware chunking; provenance (source_path + content_hash + byte span); deterministic incremental reconcile (no dup chunks) + DB integrity; MOCK embedding seam + export-chunk-texts/store-embeddings fold drop-ins; PRODUCES the retriever interface; 69/69 cloud + 69/69 `-Live`.
- **#37 retrieval.eval 0.1.0** (`687edcd`, CPU lane) -- benchmark schema (query + required-source labels, version-aware) + BM25-lite baseline + external_command seam; recall@K/MRR/stale/provenance; canonical JSON + MD byte-identical; CONSUMES the retriever interface; 69/69 cloud + 69/69 `-Live`.

## D-0077 cross-module smoke -- PASSED

artifact.search ingest (13 chunks) -> export-chunk-texts -> #35 real embed (1024-dim, cuda) -> store-embeddings (13/13, provider qwen3-0p6b-real) -> integrity OK (mock dim=64 + real dim=1024 coexist) -> search resolves to real spans -> retrieval.eval THROUGH real artifact.search hits (recall@1/3/5 = 1.0, provenance = 1.0, MRR 0.667) -> repeat digest STABLE -> changed-file re-index detected. 0 orphans. **Finding:** span object (producer) vs string (consumer) -> bridged by the fold adapter -> a Wave-2 contract-freeze item.

## Shared contracts (D-0077)

- **Embedding-provider:** op embed; texts/text + normalize; result{model_*, engine_build, dim, normalized, count, vectors in input order, per-input status}.
- **Retriever:** op search; {query,k,filters} -> ranked {source_path, content_hash, chunk_id, span, score, snippet}; deterministic order. (span shape to be frozen: object vs string.)

## Frontier red-team (12c8f539): GO

Conditional on a retrieval-record/provenance contract amendment (not a redesign/delay). Digest: `research/2026-08-01-frontier-memory-redteam.md`. Wave-2 agenda: record+provenance contract, embedding 0.2, retriever 0.2, catalog/eval/scale/privacy gates.

## Next

A contract freeze (embedding 0.2 + retriever 0.2 + gates) then Wave 2 (repo intelligence + episode/failure schema + recorder). Frozen (D-0079/D-0080): supervisor/warm-pool hardening, generators, video.interpret, real-time perception, broad training.
