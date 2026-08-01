# repo.intel -- example invocations

Index a single root (a fixture repo) under a logical namespace:

```powershell
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Root .\fixtures\repo -Namespace fixture
```

Index the real repo slice (modules/ + core-docs/) under a per-root file budget:

```powershell
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Roots ..\..\modules,..\..\core-docs -FileBudget 200
```

Generic `-InputsJson` form (any generic caller / the executor / an orchestrator skill):

```powershell
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -InputsJson '{"op":"index","root":"fixtures/repo","namespace":"fixture","file_budget":0}'
```

Re-validate an emitted records artifact against MEMORY_CONTRACT s1:

```powershell
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Op validate -RecordsPath .\runtime\artifacts\<invocation_id>\records.jsonl
```

The primary artifact is `records.jsonl` (one canonical MEMORY_CONTRACT s1 record per line, in
deterministic order) -- the drop-in payload for #36 artifact.search 0.2 `ingest_records`
(also emitted wrapped as `ingest_records.json`). All canonical artifacts are byte-identical across
re-runs of identical corpus content.
