# Module 35 -- embedding.local

Local text embedding for the Collective Agent memory substrate. Turns the pre-provisioned
**Qwen3-Embedding-0.6B** (safetensors dir; arch `Qwen3Model`, hidden_size **1024**, max seq **32768**) into a
versioned, tested `embed` skill: single or batch text in, **L2-normalized** dense vectors out, in **exact input
order**, with full `model_id/version/sha256/engine_build` provenance and clean empty/oversize handling.

This is the Wave 1 GPU lane (D-0080). It DEFINES the embedding-provider interface that `artifact.search`
(Module 36) consumes -- the precise contract is in **`SCHEMA_NOTES.md`** (the D-0077 fold depends on it).

## What it is / isn't
- **Is:** an embedding ADAPTER -- text -> vector (semantic address), governing sec 6.3.
- **Isn't:** a vector store, ingestion, chunking, retrieval, router, or a persistent embedding server. Those are
  later waves / other lanes.

## How it serves the model
A **transient** Python worker (`embed_worker.py`) under the CUDA speech venv (`transformers` + `torch`) loads the
model, embeds, and **exits** -- the detect.objects/image.util pattern, not a persistent llama-server. So there is no
detached warm resident and the executor "wedge" class does not apply; the skill still asserts 0 UNMANAGED orphans.
GPU work runs under the res.lease **`gpu`** mutex (one heavyweight resident, governing sec 16.1), self-managed by
the skill (`-GpuLease`). Pooling is **last-token** (Qwen3-Embedding's design), with mask-derived position ids so a
batched vector equals its single-call vector within a measured tolerance. Engine rationale (transformers vs the
llama-server GGUF route): `SCHEMA_NOTES.md` sec 4.

## Invocation
```powershell
# single
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'index my repository'
# batch (order preserved; result[i] <-> input[i])
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -InputsJson '{"texts":["a","b","c"],"normalize":true}'
# CPU fallback (no gpu lease)
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'idle batch' -Device cpu -GpuLease off
# off-machine / portable seam (deterministic numpy stub, no torch/model/GPU)
pwsh -NoProfile -File .\Invoke-EmbeddingLocal.ps1 -Text 'seam' -Mock -PythonExe python3
```
Key params: `-Text`/`-Texts`/`-InputsJson`, `-Normalize` (default true), `-Instruction` (query prefix; default
none = document/raw), `-MaxTokens` (default 32768), `-Dtype fp32|fp16|bf16` (default fp32), `-Device cuda|cpu`,
`-Mock`, `-GpuLease auto|off|require`. Full list: `skill.json`.

## Output
A `lifeorch.skill.result/0.1` envelope whose `result` carries `{op, model_id, model_version, model_sha256,
engine_build, pooling, dim, normalized, count, vectors[[float]|null], per_input[{index,status,n_tokens}], ...}`.
See `examples/example-result.json` and `SCHEMA_NOTES.md` sec 1.

## Tests
```powershell
# off-machine (portable, mock): schema/shape/normalize/input-order/empty/oversize/batch==single/determinism
pwsh -File .\tests\Invoke-EmbeddingLocalTests.ps1 -PythonExe python3
# live (2080 Ti): + real dim/normalize/provenance, batch==single & determinism tolerance, similarity order,
#                 CPU-fallback probe, 0 orphans
pwsh -File .\tests\Invoke-EmbeddingLocalTests.ps1 -Live -PythonExe 'F:\...\python_env\Scripts\python.exe'
```

## Determinism
fp32 by default with TF32 disabled. Same text + params reproduces the vector within a documented tolerance
(measured in `SCHEMA_NOTES.md` sec 7; GPU has minor nondeterminism, CPU is exact).
