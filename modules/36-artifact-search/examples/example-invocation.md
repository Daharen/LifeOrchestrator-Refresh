# artifact.search -- example invocations

## Ingest a corpus (creates the SQLite catalog)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 `
  -Op ingest -Source core-docs -Root ..\..\core-docs `
  -DbPath .\runtime\catalog\as.db -MaxFiles 200
```

`result.result` (abridged):

```json
{
  "op": "ingest",
  "result": {
    "source_id": "core-docs",
    "counts": { "seen": 32, "added": 32, "changed": 0, "deleted": 0, "unchanged": 0, "parse_failures": 0, "moved": 0 },
    "catalog_digest": "….",
    "integrity_ok": true,
    "counts_total": { "documents_active": 32, "chunks": 411, "embeddings": 411 }
  }
}
```

## Search (retriever interface)

```powershell
# lexical / FTS5
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "resource lease" -Mode fts -K 5 -DbPath .\runtime\catalog\as.db

# exact / literal (filenames, symbols, ids, error strings)
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "D-0077" -Mode exact -DbPath .\runtime\catalog\as.db
```

Each `results[]` item carries full provenance: `source_path`, `content_hash`, `chunk_id`,
`span:{start,end}` (byte offsets), `section_path`, `score`, `snippet` -- see `example-result.json`.

## Embedding-provider seam (mock now; real adapter #35 at fold)

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"embed","texts":["alpha","beta"],"dim":64,"normalize":true}'
```

Returns `{ provider_id, model_id, model_version, model_sha256, engine_build, dim, normalized, count, vectors, input_status }`
with `vectors[i]` aligned to `texts[i]`.

## Integrity + fold drop-in

```powershell
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op integrity -DbPath .\runtime\catalog\as.db
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op export-chunk-texts -DbPath .\runtime\catalog\as.db
# ... feed exported chunk texts (in order) to the real embedding adapter #35, then:
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"store-embeddings","db":"…","chunk_ids":["chk_…"],"vectors":[[…]],"provider_id":"embedding.qwen3-0p6b","dim":1024}'
```
