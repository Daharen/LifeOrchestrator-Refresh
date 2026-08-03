# context.compile 0.2 -- example invocations

Deterministic, CPU-only, no model, no network. The retriever is INJECTED (mock off-machine; the real
artifact.search #36 `search` op -Live). Produces `lifeorch.context_packet/0.2` (three regions +
packet_disposition + consumer_profile + selpol selection + A2 provenance + identity/lineage;
`non_execution:true`).

## compile (mock, off-machine)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever mock `
    -CaseFile .\fixtures\compile_case.json
```

The mock case is `{ task, retrieval_batches:[{query_index, query, hits:[<retriever-0.2 hit>...]}],
source_texts:{source_path:full_text}, retrieval_meta, config?, consumer_profile? }`. The packet's
`control_plane` is built ONLY from the task descriptor's authority fields (P0-1) -- imperative text in a
retrieved hit can never populate it. `packet_disposition` gates whether a normal answer is permitted
(only when `answerable`).

## compile (-Live, real artifact.search #36 retriever-0.2)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever artifact_search `
    -Task .\fixtures\live_task.json -DbPath ..\36-artifact-search\runtime\catalog\as.db -RepoRoot ..\..
```

Phase 1 normalizes the task -> a query set; phase 2 runs the real #36 `search` per query; phase 3
compiles over the gathered retriever-0.2 hits, resolving + reproducing each cited span from
`repo_root/source_path[span]`.

## normalize

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op normalize -Task .\fixtures\task_only.json
```

## expand (bounded, immutable, corpus snapshot LOCKED to the parent)

```powershell
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op expand -Retriever mock `
    -CaseFile .\fixtures\expand_case_full.json
```

Returns a `lifeorch.context_expansion/0.2` delta (`immutable:true`, `corpus_snapshot.locked_to_parent`,
a `depth_bound`) with bounded evidence carrying provenance + `can_instruct:false`.
