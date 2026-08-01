# embedding.local -- example invocations

## Single text (GPU, normalized)
```powershell
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'The Life Orchestrator indexes its own repository.'
```

## Batch (order preserved; result[i] <-> input[i])
```powershell
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -InputsJson '{"texts":["semantic memory","vector index over chunks","the quick brown fox"],"normalize":true}'
```

## Query with an instruction prefix (asymmetric retrieval; documents stay raw)
```powershell
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'How does the executor detect a wedge?' -Instruction 'Given a question, retrieve relevant repository passages'
```

## CPU fallback (no gpu lease)
```powershell
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'idle-time batch' -Device cpu -GpuLease off
```

## Off-machine / portable seam (deterministic numpy stub -- no torch/model/GPU/lease)
```powershell
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -InputsJson '{"texts":["a","","b"]}' -Mock -PythonExe python3
```

The result is a `lifeorch.skill.result/0.1` envelope; its `result` field is documented in `../SCHEMA_NOTES.md`
sec 1. `example-result.json` in this folder is a captured **mock** run (small dim for readability); a production
run returns **1024-dim** last-token vectors with real `model_sha256` + `engine_build` provenance.
