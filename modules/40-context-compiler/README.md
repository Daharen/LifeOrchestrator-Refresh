# Module 40 -- context.compile (Context Compiler)

The Collective Agent's context-compilation centerpiece (D-0080 directive Priority 4 / section 8). A
**deterministic, CPU-only, no-model, no-network** skill that turns a task descriptor into a versioned,
token-budgeted `lifeorch.context_packet/0.1`:

```
normalize (8.1) -> retrieve via the retriever-0.2 seam (8.2) -> deterministic rerank + diversity (8.3)
-> token budget with EXACT accounting (8.4/16.3) -> context_packet/0.1 with full provenance,
   omitted-context, an expand seam (8.5), and packet-evaluation hooks (8.6)
```

It **consumes** the FROZEN `MEMORY_CONTRACT` retriever-0.2 hit shape (s3) + s5 staleness enum + s1
provenance envelope, and **produces** packets that retrieval.eval #37 0.2 and a fresh 9B consume at the
orchestrator fold (D-0077). The 9B is NOT run here -- this module is deterministic; the model consumes the
packet downstream.

## Layout
- `context_compiler.py` -- the deterministic worker (all packet logic; stdlib only).
- `Invoke-ContextCompiler.ps1` -- the thin entrypoint + the retriever seam (mock off-machine; real #36 `-Live`).
- `skill.json` -- the `lifeorch.skill.manifest/0.1` manifest (contract 0.2).
- `SCHEMA_NOTES.md` -- **the D-0077 fold contract** (every schema/interface interpretation).
- `WORK_ORDER.md`, `examples/`, `fixtures/`, `tests/`.

## Ops
- **compile** (default) -- task descriptor -> `context_packet/0.1` (+ a byte-identical `context_packet.json`).
- **normalize** -- task descriptor -> the deterministic query set (used by the `-Live` retriever seam).
- **expand** (8.5) -- packet + an expansion request -> bounded additional evidence WITH provenance
  (`raw_source | more_evidence | related_symbol | failure_record | tool_contract | prior_episode`). A
  deterministic seam, NOT a live agent loop.

## Retriever seam
The deterministic worker never calls another process; the retriever is INJECTED.
- **mock** (off-machine): deterministic fixture 0.2 hits (`-Retriever mock -CaseFile ...`).
- **artifact_search** (`-Live`): `normalize` -> run the REAL artifact.search #36 `search` per derived query
  -> `compile` over the gathered retriever-0.2 hits (`-Retriever artifact_search -DbPath ... -RepoRoot ...`).
The compiler MUST NOT depend on the vector channel being populated (lexical-only today; `vector_similarity`
may be null).

## Run
```powershell
# off-machine (deterministic mock)
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever mock -CaseFile .\fixtures\compile_case.json

# -Live (real #36 retriever-0.2 over an ingested core-docs catalog)
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever artifact_search `
  -Task .\fixtures\live_task.json -DbPath ..\36-artifact-search\runtime\catalog\as.db -RepoRoot ..\..
```
See `examples/example-invocation.md`. Every invocation emits one `lifeorch.skill.result/0.1` envelope on
stdout; the packet is also a canonical `context_packet.json` artifact (byte-identical on re-run).

## Determinism + provenance
Canonical JSON (`sort_keys`, compact, UTF-8/LF) + a content-derived `packet_id`; integer-only rerank
features (scores folded to `*_micros`); no floats, timestamps, run ids, or `abs_path` in the packet.
Excerpt text is read from the SOURCE BYTE SPAN and validated against `chunk_content_hash` so the cited span
reproduces the text (`provenance.reproduced`).

## Tests
```bash
python tests/context_compiler_tests.py                 # 46 assertions (acceptance a-e + more)
pwsh   tests/Invoke-ContextCompilerTests.ps1           # entrypoint end-to-end (mock)
pwsh   tests/Invoke-ContextCompilerTests.ps1 -DbPath <#36 catalog> -RepoRoot <repo>   # -Live
```

Non-goals (owned elsewhere): real embeddings/vector search, the retriever/catalog DB (#36), skill-card
content (#41), the measured reranker/eval (#37), the 9B / any model, episode recording (#39), skill
routing (Priority 7), UI, web search.
