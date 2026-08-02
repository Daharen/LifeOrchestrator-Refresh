# context.compile -- example invocations

`context.compile` (Module 40) turns a task descriptor into a versioned, token-budgeted
`lifeorch.context_packet/0.1`. It is DETERMINISTIC, CPU-only, no model, no network. The retriever is a
seam: off-machine it consumes deterministic fixture 0.2 hits; `-Live` it wires the real
`artifact.search` #36 `search` op.

## compile (mock retriever -- off-machine / deterministic fixture hits)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 `
  -Op compile -Retriever mock -CaseFile .\fixtures\compile_case.json
```

The case file carries `{ task, retrieval_batches, source_texts, retrieval_meta }`. `retrieval_batches`
is one entry per derived query, each holding an array of MEMORY_CONTRACT retriever-0.2 hits.

## compile (real artifact.search #36 retriever -- `-Live`)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 `
  -Op compile -Retriever artifact_search `
  -Task .\fixtures\live_task.json `
  -DbPath ..\36-artifact-search\runtime\catalog\as.db `
  -RepoRoot ..\..
```

Flow: `normalize` the task -> a deterministic query set -> run the real #36 `search` per query ->
`compile` over the gathered retriever-0.2 hits. Excerpt text is read from `RepoRoot/source_path[span]`
so the cited span reproduces the source and provenance is validated against `chunk_content_hash`.

## normalize (inspect the derived query set)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op normalize -Task .\fixtures\task_only.json
```

## expand (8.5 -- bounded raw source behind a summary excerpt)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 `
  -Op expand -Retriever artifact_search `
  -PacketFile .\packet.json -Request '{"type":"raw_source","target":{"record_version_id":"occ_..."},"budget":{"max_tokens":400}}' `
  -DbPath ..\36-artifact-search\runtime\catalog\as.db -RepoRoot ..\..
```

Every invocation emits one `lifeorch.skill.result/0.1` envelope on stdout; the packet is also written
as a canonical (byte-identical on re-run) `context_packet.json` artifact. See `example-result.json`.
