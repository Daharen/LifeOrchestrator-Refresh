# SCHEMA_NOTES -- embedding.local (Module 35)

Records EVERY schema/interface interpretation for the embedding adapter. The D-0077 cross-module fold smoke
(embedding -> artifact.search -> benchmark) depends on this file. Governing: `research/2026-07-31-roadmap-
reprioritization-cognitive-virtual-memory.md` sec 6.3 (embeddings are semantic ADDRESSES, not compressed docs),
16.1/16.2 (one heavyweight resident; embedding is batchable + a CPU-fallback candidate). Decisions D-0080/D-0081.

## 1. The EMBEDDING-PROVIDER INTERFACE (the shared contract; artifact.search / Module 36 mocks THIS)

**op:** `embed`

**Inputs** (via named params OR `-InputsJson`):
- `texts` : `array<string>` (batch)  -- OR --  `text` : `string` (single). Order is preserved exactly.
- `normalize` : `bool`, default **true** (L2-normalize each vector -> unit length; cosine == dot).
- `instruction` : `string|null`, default **null**. Optional Qwen3-Embedding query-instruct prefix
  (`"Instruct: {instruction}\nQuery: {text}"`). Default null = **document / raw** embedding. (See sec 5.)
- `max_tokens` : `int`, default **32768** (= the model's `max_position_embeddings`). Oversize threshold.

**Result** (the `result` field of the standard `lifeorch.skill.result/0.1` envelope):
```
{
  "op": "embed",
  "model_id": "embedding.qwen3-0p6b",
  "model_version": "0.6B",
  "model_sha256": "<sha256 of model.safetensors>",   // 0437e45c...e23fd (see sec 3)
  "engine_build": "transformers-<v>/torch-<v>/cuda-<v> (qwen3 last_token L2)",
  "pooling": "last_token",
  "dim": 1024,                       // Qwen3-Embedding-0.6B hidden_size
  "normalized": true,
  "count": <N>,                      // == number of inputs
  "vectors": [ [float x dim] | null, ... ],   // EXACT input order: result[i] <-> input[i]; null for skipped
  "per_input": [ {"index": i, "status": "ok"|"empty"|"oversize", "n_tokens": int}, ... ],
  "instruction": <string|null>,
  "max_tokens": <int>,
  "device": "cuda"|"cpu",
  "dtype": "fp32"|"fp16"|"bf16",
  "timings": {"load_ms": int, "embed_ms": int},
  "peak_vram_bytes": int|null,       // torch allocator peak (see sec 6)
  "peak_ram_bytes": int|null,
  "lease": { "requested": bool, "acquired": bool, "owned": bool, "already_held": bool, "lease_id": str|null, ... }
}
```
`model_provenance[]` also carries `{model_id, version:"0.6B", sha256, engine_build, params{pooling,normalize,dtype,device,max_tokens}}`.

**Envelope status:** `ok` when all inputs embedded; `partial` when >=1 input was skipped (empty/oversize);
`error` only on a real failure (never for a skipped input).

### Index alignment rule (load-bearing for the consumer)
`vectors` is ALWAYS length `count`, in input order. A skipped input (empty/oversize) is `null` at its index,
and `per_input[index].status` says why. The consumer MUST zip `vectors[i]` with `per_input[i]` and treat a
`null` vector as "no embedding for this input" -- **never** fall back to a zero/garbage vector.

## 2. Failure modes (clean, per-input; never a crash, never a silent bad vector)
- **empty / whitespace-only** input -> `status:"empty"`, `n_tokens:0`, `vectors[i]=null`.
- **oversize** (real token count > `max_tokens`) -> `status:"oversize"`, `vectors[i]=null`. The input is
  **skipped, not truncated** -- a truncated vector would be a silent semantic lie, so we refuse it.
- A worker-level failure (model won't load, cuda unavailable, etc.) -> envelope `status:"error"` with
  `error{code,message,retryable}`; no partial garbage.

## 3. Model + provenance
- `embedding.qwen3-0p6b` = **Qwen3-Embedding-0.6B**, HuggingFace **safetensors dir** (NOT GGUF), arch
  `Qwen3Model`, `hidden_size` **1024**, `max_position_embeddings` **32768**, native dtype bf16, tie_word_embeddings.
- Home: `F:\...\LifeOrchestrator-Refresh_Large_Data\23-artifact-search\embedding\Qwen3-Embedding-0.6B`.
- `model_sha256` is defined as **sha256(model.safetensors)** = `0437e45c94563b09e13cb7a64478fc406947a93cb34a7e05870fc8dcd48e23fd`
  (config.json `bb23c16...`, tokenizer.json `def76fb...`). The skill re-verifies it every real run (fail-closed on mismatch).

## 4. Engine choice (why transformers, not llama-server) -- D-0061 rationale
The brief anticipated `llama-server --embedding`. The model on disk is a **safetensors dir** with declared
`engine: transformers`; there is **no GGUF**, the `gguf` python package is absent, and the b8661 engine folder is
binary-only (no `convert_hf_to_gguf.py`). b8661 llama-server DOES support `--embedding --pooling last`, so the
GGUF route is viable but requires a conversion sub-project. The idiomatic, lower-risk path (matching detect.objects
#16 / image.util #15 / gen.image #23: a transient Python worker under a venv, emits JSON meta, pwsh wraps the
envelope) is **transformers under the CUDA speech venv** (`F:\...\Local_Computer_Speech_Large_Data\python_env`,
transformers 4.57.3 + torch 2.11.0+cu128 + CUDA 12.8, RTX 2080 Ti). `engine_build` therefore names the
transformers/torch/cuda versions, not a llama.cpp build. **Follow-on (documented, not built):** a GGUF-conversion +
llama-server `--embedding --pooling last` backend for a warm resident embedding server if batch throughput demands it.

## 5. Pooling, normalization, position ids, and the instruction prefix
- **Pooling = last-token** (Qwen3-Embedding uses the last token's final hidden state). Tokenizer `padding_side=left`
  so the last column is always a real token; batch uses attention-mask-derived `position_ids`
  (`cumsum(mask)-1`, pad->0) so a batched real token gets the SAME RoPE position as in a single call -> **batch ==
  single within fp tolerance** (measured, sec 7).
- **Normalization = L2** (default). `normalize:false` returns the raw pooled vector.
- **Instruction prefix:** Qwen3-Embedding is trained for asymmetric retrieval -- queries get
  `"Instruct: {task}\nQuery: {text}"`, documents stay raw. This adapter embeds **raw/document-style by default**
  (`instruction:null`). A retrieval QUERY-side caller should pass the query instruction; the artifact.search corpus
  should be embedded raw. Both sides must be consistent; this is a CONSUMER concern -- the adapter just exposes the knob.

## 6. Memory measurement caveat (driver 591.74 spill)
`peak_vram_bytes` is the **torch allocator** peak (`torch.cuda.max_memory_allocated`), not the driver/process peak.
Driver 591.74 SPILLS an over-budget model to system RAM ("it loaded" != "it fits"). For a 0.6B fp32 model the peak
is ~2.39 GB -- far below the 11 GB limit -- so no spill risk and admission control is not tight here. `peak_ram_bytes`
is best-effort (Linux `ru_maxrss`; a Windows PeakWorkingSet probe); on the CUDA-venv Windows build it currently
returns null (a documented minor residual -- RAM is not the constraint on this box; VRAM is).

## 7. MEASURED (live proof on the 2080 Ti, 2026-08-01; tests 42/42 -Live)
- dim **1024** · pooling **last_token** · normalized unit length **YES** (L2 norm 0.99999997).
- engine_build: **transformers-4.57.3/torch-2.11.0+cu128/cuda-12.8 (qwen3 last_token L2)**.
- model_sha256(model.safetensors) = **0437e45c94563b09e13cb7a64478fc406947a93cb34a7e05870fc8dcd48e23fd** (re-verified live).
- **Determinism** (same text + params, two separate invocations): max cosine distance = **2.22e-16**, max abs diff = **0**
  (fp32 with TF32 disabled is effectively exact on this box). Documented tolerance: **cos_dist < 1e-3** (measured ~2e-16).
- **batch == single** (per input): max cosine distance = **8.66e-13** (documented tolerance cos_dist < 1e-3).
- **Similarity order**: cos(query, near) = **0.7219** > cos(query, far) = **0.1987** (near pair ranks above far).
- Latency (fresh process each call): first-ever cold load_ms ~6502 (incl. torch import); steady load_ms ~1970;
  single embed_ms ~250; CPU-fallback embed_ms ~118, load_ms ~1271.
- Peak VRAM (torch alloc) = **2,394,757,120 B (~2.39 GB)**; peak_ram = null on this Windows build (see sec 6).
- **CPU-fallback feasibility** (device=cpu): status ok, dim 1024, embed_ms ~118 -- **FEASIBLE** (not shipped as the default; governing sec 16.2).
- **0 UNMANAGED embed_worker orphans** (before==after; gpu lease released; `review_queue.jsonl` untouched -- not a producer).

## 8. NON-GOALS (not built here -- later waves / lanes)
No vector DB / index, no artifact ingestion, no chunking, no retrieval, no routing, no re-embedding pipeline, no
warm persistent embedding server. Just the adapter + its contract. (artifact.search #36 owns the store + FTS;
the retrieval-eval harness owns quality metrics; the orchestrator runs the real cross-module smoke at fold.)
