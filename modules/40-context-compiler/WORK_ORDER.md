# Work Order: Context Compiler (`context.compile`)

**Contract version targeted:** 0.2 (MEMORY_CONTRACT v0.1.1) · **Author:** CONTEXT-COMPILER-i29 (2026-08-02) ·
**Roadmap entry:** `MODULE_ROADMAP.md#40-context-compiler` · **Wave:** i29 Wave 3 (plan `fo-29-87dbfa0b`)

### Problem being solved
The Collective Agent must give a fresh 9B a small, task-specific working set instead of a 200 MB project in
one prompt (directive section 3, 16.3). Nothing yet turns a task into a bounded, provenance-carrying,
token-budgeted context. This module is that translator -- the architectural centerpiece (directive
Priority 4 / section 8): task descriptor -> `normalize` -> retrieve via the FROZEN retriever-0.2 seam ->
deterministic rerank + diversity -> token budget -> `lifeorch.context_packet/0.1` with full source
provenance, an omitted-context record, a deterministic `expand` seam, and packet-evaluation hooks.

### Immediate practical use
The orchestrator feeds this compiler's REAL packets into retrieval.eval #37 0.2 + a fresh 9B at the D-0077
fold; a later read-only Collective Agent slice (Priority 8) and the local coordinator (Priority 10) call
`compile` per task and `expand` on demand.

### Explicit scope (in)
- Task normalization (8.1) -> a deterministic query set (lexical terms + record_kind/namespace/path filters).
- Candidate retrieval (8.2) via a DEFINED retriever-0.2 seam: a deterministic MOCK off-machine + the REAL
  artifact.search #36 `search` on `-Live`; MUST NOT depend on the vector channel being populated.
- Deterministic rerank + diversity (8.3): relevance/authority/freshness (DEMOTE stale, s5)/namespace/
  component/kind-priority; content_hash dedup + a source-diversity cap; deterministic tie-break.
- Token budget (8.4/16.3): a fixed heuristic token count, EXACT accounting, explicit truncation detection.
- `lifeorch.context_packet/0.1` (8.4): immutable goal, normalized task, state refs, constraints/permissions,
  source EXCERPTS WITH PROVENANCE, skill/procedure/failure/episode REFS, open questions, completion contract,
  token accounting, OMITTED-CONTEXT summary, escalation conditions, deterministic packet_id, retrieval
  provenance.
- Adaptive-expansion seam (8.5): the `expand` op + request shape (deterministic, bounded).
- Packet-evaluation hooks / context-quality signals (8.6) -- the #37 seam.

### Non-goals (out -- do NOT build)
Real embeddings / vector search (consume retriever 0.2 as-is; vector channel may be null); the retriever or
catalog DB (#36); the skill-CARD content/format (#41); the MEASURED reranker + eval metrics (#37); running
the 9B or ANY model; episode RECORDING (#39); skill routing / plan validation (Priority 7); UI; web search.
Do NOT touch model modules / models.json or any core-doc (`docs:[]`).

### Dependencies
- Modules: artifact.search #36 (the real retriever-0.2 `search` seam on `-Live`); res.lease #29 (git lease
  around dev.ship). Contract features consumed: MEMORY_CONTRACT s1 envelope, s3 retriever-0.2 hit, s5
  staleness enum. Tools: `pwsh>=7.4`, `python>=3.8` (stdlib only). Models: none.

### Skill contract requirements
- `skill_id=context.compile`, `version=0.1.0`, `contract_version=0.2`, `determinism=deterministic`,
  `parallel_safe=true`, `batch=false`, `streaming=false`. `confidence=null`, empty `model_provenance`.
  Artifact kinds: `json` (`context_packet.json` / `context_expansion.json`).

### Inputs and outputs
See `skill.json` (inputs) + `SCHEMA_NOTES.md` s2/s3/s7 (packet + expansion shapes). Ops: `compile`
(default), `normalize`, `expand`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/{compile|normalize|expand}/` -> `cc_args.json`, `cc_meta.json`,
  `worker.log`, and the canonical `context_packet.json` / `context_expansion.json`.

### Proposed implementation
- **Language:** Python (stdlib only) for ALL packet logic -- deterministic hashing + canonical JSON, and it
  sidesteps the pwsh-7.4.6 determinism traps. A thin pwsh entrypoint wraps it (worker+meta handoff, mirrors
  #36) and owns the retriever seam (mock fixture off-machine; real #36 on `-Live`).

### External tools or models
Only pwsh + python (both present -- `TOOL_MODEL_REGISTRY.md`). No install. No model, no network.

### Tests
- **Direct (off-machine):** `python tests/context_compiler_tests.py` (46 assertions) + `pwsh
  tests/Invoke-ContextCompilerTests.ps1` (entrypoint end-to-end, mock retriever).
- **Through the executor (`-Live`):** ingest a bounded core-docs slice via #36, then
  `pwsh tests/Invoke-ContextCompilerTests.ps1 -DbPath <catalog.db> -RepoRoot <repo>` (real retriever-0.2).

### MVP acceptance criteria
(a) a packet within the configured token budget with EXACT accounting; (b) every excerpt's cited span
reproduces its source text (validated against `chunk_content_hash`); (c) omitted context + expansion
affordances recorded; (d) byte-identical on re-run (deterministic `packet_id`); (e) a diversity test where
10 near-dup chunks do NOT crowd out a distinct required source. `-Live`: the real #36 retriever over a
core-docs slice for >=3 LO benchmark questions -> required spans present + provenance-valid; `expand`
returns bounded raw source; deterministic re-run byte-identical.

### Manual verification procedure
Run the two off-machine suites (expect all green); on the box, ingest core-docs into a #36 catalog and run
the harness with `-DbPath/-RepoRoot`; open a produced `context_packet.json` and confirm an excerpt's
`source_path[span]` reproduces its `text`.

### Documentation requirements
`README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json` +
`SCHEMA_NOTES.md` (the D-0077 fold contract).

### Registry / state updates
`docs:[]` -- the worker reports; the ORCHESTRATOR mirrors `CURRENT_STATE.md` / `MODULE_ROADMAP.md` /
`TOOL_MODEL_REGISTRY.md` at fold.

### Known follow-on work
Consume #37's MEASURED reranked retriever-0.2 array in place of the self-contained rerank; carry real skill
cards (#41) + episode/failure bodies (#39) once those land; a real tokenizer if the ceil(chars/4) heuristic
proves too coarse; wire `compile`/`expand` into the read-only Collective Agent slice (Priority 8).

### STOP conditions
Scope would exceed the list above; a dependency is missing/broken; the contract lacks something needed
(stop + propose an amendment, do not freelance); MVP acceptance met -- stop; do not start the next module.
