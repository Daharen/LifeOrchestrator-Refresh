# artifact.search -- example invocations (0.2.0)

All invocations go through `Invoke-ArtifactSearch.ps1` and emit one `lifeorch.skill.result/0.1` envelope on
stdout. Either named params or the generic `-InputsJson` may be used (named params override matching keys).

## 1. Ingest a corpus (creates the db)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op ingest -Source core-docs `
  -Root ..\..\core-docs -DbPath .\runtime\catalog\as.db
```

Walks the root, content-hashes an inventory, Markdown-aware chunks, FTS5-indexes, mock-embeds each chunk as a
float32 BLOB, reconciles new/changed/moved/deleted, runs an integrity check, and emits a deterministic
`catalog_digest` (extended to cover records + edges).

## 2. Search (retriever 0.2 hit shape)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "resource lease" -Mode fts -K 5 `
  -DbPath .\runtime\catalog\as.db
```

Each hit carries `span:{start,end}` + `span_label`, `record_id`/`record_version_id`/`record_kind`, per-channel
diagnostics (`lexical_rank`/`lexical_score`, `vector_rank`/`vector_similarity` [null], `fused_rank`/`fused_score`,
`fusion_algo`/`fusion_version`, `embedding_space_id`, `index_snapshot`, `filter_decisions`, `tie_break_key`),
`status`/`authority_level`, `snippet`, `rank`. The opaque single `score` is RETIRED. See
`example-result.json`. Filter by kind/status: `-InputsJson '{"op":"search","query":"...","db":"...",
"filters":{"record_kind":"symbol","exclude_stale":true}}'`.

## 3. Land TYPED records (the s1 `ingest_records` SINK)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{
  "op":"ingest-records","db":".\\runtime\\catalog\\as.db",
  "ingest_run":{"producer":"repo.intel","producer_version":"0.1","namespace":"core-docs"},
  "records":[
    {"record_id":"sym.frobnicate","record_version_id":"sym.frobnicate@1","record_kind":"symbol",
     "namespace":"core-docs","text":"def frobnicate(flux): return widget(flux)",
     "source_version_id":"ver_...","source_span":{"start":0,"end":41},
     "edges":[{"edge_kind":"relates_to","dst_ref":"rel.frob_widget@1","dst_kind":"record"}]},
    {"record_id":"ep.run1","record_version_id":"ep.run1@1","record_kind":"episode",
     "namespace":"core-docs","text":"goal closed successfully"}
  ]}'
```

Deterministic + idempotent (re-ingesting identical records is a no-op); malformed records are rejected with a
surfaced reason (`missing_required_field`, `unknown_record_kind`, `record_version_conflict`, ...); `edges[]` +
`derivation_refs` become first-class `record_edges`.

## 4. List the record ENVELOPE (source_chunk view + typed records)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op list-records -DbPath .\runtime\catalog\as.db `
  -InputsJson '{"filters":{"record_kind":"symbol"}}'
```

## 5. Migrate a shipped-0.1 db to schema_version 2 (in place)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op migrate -DbPath .\runtime\catalog\as.db
```

Idempotent; no data loss; converts the 0.1 JSON embedding column to float32 BLOB vectors.

## 6. Fold drop-in (export -> real adapter #35 -> store float32 vectors -> round-trip)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op export-chunk-texts -DbPath .\runtime\catalog\as.db
# feed chunks[].text to embedding.local #35, then:
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"store-embeddings","db":"...",
  "chunk_ids":["chk_..."],"vectors":[[...]],"provider_id":"embedding.qwen3-0p6b","dim":1024,
  "embedding_space_id":"esp_..."}'
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op get-vector -TargetKind chunk -TargetId chk_... `
  -DbPath .\runtime\catalog\as.db
```
