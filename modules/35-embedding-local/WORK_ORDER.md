# MODULE_WORK_ORDER -- embedding.local (Module 35)

## Work Order: Local Text Embedding (`embedding.local`)

**Contract version targeted:** 0.2 · **Author:** EMBED-ADAPTER-i25 (fan-out Wave 1 GPU lane, plan fo-25-3b718a13) / 2026-08-01
· **Roadmap entry:** Wave 1 GPU lane (D-0080); governing `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` sec 6.3/16.2, Priority 1.

### Problem being solved
The Collective Agent needs semantic ADDRESSES (embeddings) for hybrid retrieval, but the pre-provisioned
Qwen3-Embedding-0.6B is staged-but-UNWIRED. This module turns it into a conforming, versioned, testable local
`embed` capability AND pins the embedding-provider interface the rest of Wave 1 consumes.

### Immediate practical use
`artifact.search` (Module 36) calls `embed` to vector-index repository chunks and to embed queries; the Wave 1
fold runs the real embedding -> artifact.search -> benchmark smoke (D-0077). Lane B mocks this exact shape.

### Explicit scope (in)
- Resolve `embedding.qwen3-0p6b` from models.json (path + sha256 verified); wire it for THIS module.
- Serve embeddings (transient Python worker, transformers, last-token pool, L2 normalize) under the gpu lease.
- `embed`: single + batch; normalized by default; dims + full model/version/sha256/engine provenance;
  EXACT input-order preservation; empty/oversize -> clean per-input flag + null vector.
- Off-machine seam (mock/stub) FIRST, then a live GPU proof (real vectors, latency, VRAM, determinism, similarity order).
- A CPU-fallback feasibility probe (device=cpu). Measure + record latency + peak VRAM/RAM.

### Non-goals (out -- do NOT build)
- A vector DB / index, ingestion, chunking, retrieval, routing, re-embedding pipeline (lane B / later waves).
- A persistent/warm embedding server (documented follow-on; transient worker is sufficient for MVP).
- The GGUF + llama-server `--embedding` backend (viable follow-on; see SCHEMA_NOTES sec 4).

### Dependencies
- Models: `embedding.qwen3-0p6b` (type=embedding). Tools: CUDA speech venv python (transformers/torch), res.lease #29 (gpu lease).
- Contract features: `lifeorch.skill.result/0.1` envelope; `-InputsJson`; `-ArtifactRoot`.

### Skill contract requirements
- `skill_id embedding.local`, `version 0.1.0`, `determinism mixed`, `batch true`, `streaming false`, `parallel_safe false` (GPU + gpu lease).
- `result` = the embedding payload (SCHEMA_NOTES sec 1); `model_provenance` populated; `confidence` null; artifact kinds json/log.

### Inputs and outputs
- **Inputs:** text|texts, normalize(=true), instruction(=null), max_tokens(=32768), dtype(=fp32), device(=cuda), mock(=false). (skill.json)
- **Outputs:** `{op,model_id,model_version,model_sha256,engine_build,pooling,dim,normalized,count,vectors,per_input,...}`; artifacts worker_out.json/worker_args.json/worker.log.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` -> worker_args.json (worker input), worker_out.json (authoritative meta), worker.log, result.json (envelope).

### Proposed implementation
- **Language:** PowerShell entrypoint + Python worker. Why: the model is a HF safetensors dir served by
  transformers (the house python-worker-under-venv pattern); pwsh owns the contract envelope + gpu lease.

### External tools or models
- CUDA speech venv (present: transformers 4.57.3, torch 2.11.0+cu128, safetensors, numpy). No new install.

### Installation steps
- None. `models.json` gains `model_sha256` on the `embedding.qwen3-0p6b` entry (GPU lane may edit models.json); Module 7 re-verified.

### Tests
- **Direct / off-machine:** `tests/Invoke-EmbeddingLocalTests.ps1 -PythonExe python3` (mock; portable seams).
- **Live:** `... -Live -PythonExe <speech venv python>` on the executor (real model, gpu lease).

### MVP acceptance criteria (ALL MET -- -Live 42/42 on the 2080 Ti, 2026-08-01)
- [x] Stable documented embed schema (SCHEMA_NOTES sec 1).
- [x] Repeated-input consistency within a stated tolerance (cos_dist 2.2e-16; documented < 1e-3).
- [x] batch result == single-call result per input (cos_dist 8.7e-13).
- [x] 0 orphaned model procs (0 UNMANAGED embed_worker; gpu lease released).
- [x] model_id/version/sha256 + engine_build recorded.
- [x] latency + peak VRAM measured (load ~1970ms, embed ~250ms; VRAM ~2.39 GB; peak_ram best-effort/null on Windows).
- [x] fixture vectors (examples/example-result.json) + similarity-ORDER test (cos_near 0.72 > cos_far 0.20).
- [x] clean empty/oversize failure modes.

### Manual verification procedure
- Run the -Live tests on the box; confirm ALL PASS + the printed MEASURE lines; `pgrep`/Task Manager shows no `embed_worker` python.

### Documentation requirements
- `README.md` + `skill.json` + `examples/*` + `SCHEMA_NOTES.md` (the D-0077 contract). Done.

### Registry / state updates (ORCHESTRATOR folds these; worker is docs:[])
- `models.json`: add `model_sha256` + `wired` note to `embedding.qwen3-0p6b` (this module wires it). Module 7 re-verified base 42/42.
- The orchestrator mirrors CURRENT_STATE / MODULE_ROADMAP / TOOL_MODEL_REGISTRY from this worker's report.

### Known follow-on work
- GGUF + llama-server `--embedding --pooling last` backend (warm resident) for batch throughput.
- Matryoshka/truncated-dim output; query-instruction presets; a persistent embedding server; re-embed-on-model-change hooks (lane B / later waves).

### STOP conditions
- Scope would exceed the list above (no store/ingestion/retrieval here).
- The gpu lease cannot be acquired (report blocked, don't run GPU without the mutex).
- MVP acceptance met -- stop.
