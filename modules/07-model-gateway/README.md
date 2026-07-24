# model.gateway — Local Model Gateway (Module 7)

A common interface for local and frontier agents to **run a local model** on this machine without knowing
the engine. The MVP runs local **LLMs** (GGUF text models) through the built llama.cpp **`llama-server`**,
chosen from a declarative registry by id or tier. It is the first **stochastic/mixed** skill: it records
full `model_provenance` and a `confidence`, and flags low-confidence results to the review queue.

## What it does (MVP)

- Resolves a requested model from `models.json` by **`-Model <id>`**, a **`-Tier`** alias
  (`tiny|weak|mid|strong`), or the registry default.
- Starts one isolated `llama-server` on a free loopback port → waits for `/health` → `POST
  /v1/chat/completions` → parses the OpenAI-shape response → **always stops the server**.
- Returns a contract-valid `lifeorch.skill.result/0.1` envelope with the completion, token counts, timings,
  `finish_reason`, `model_provenance[]`, and a `confidence`.

Only **wired LLMs** execute. STT / TTS / embedding models are **declared** in the registry (staged and
ready) but return a structured `model_not_wired` error until their own modules wire them (STT → 11,
TTS → 12, embeddings → 23).

## Invocation

Direct:

```
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Tier weak -Prompt "Name three primary colors." -MaxTokens 64
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Model llm.weak.qwen2p5-0p5b -System "You are terse." -Prompt "Ping?" -MaxTokens 16 -Seed 42
```

Via `-InputsJson` (supports a full `messages` array):

```
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -InputsJson '{"tier":"weak","messages":[{"role":"system","content":"You label text."},{"role":"user","content":"Category of: invoice #42"}],"max_tokens":8,"temperature":0}'
```

Through the Module 1 wrapper or the executor: same as any skill (see `CURRENT_STATE.md`).

## Selecting / swapping models

Model selection is **config, not code**. `models.json` holds:

- `tiers.llm` — alias → model_id (`tiny`→0.5B, `weak`→1.5B, `mid`→3B, `strong`→27B).
- `defaults.llm` — the model used when neither `-Model` nor `-Tier` is given.
- `models[]` — every declared model with `path`, `engine`, `wired`, `context`, `gpu_layers`, params.

To make a tier use a different/stronger model, edit one line in `tiers`/`defaults`. To add a model, add a
`models[]` entry. Callers never change.

## Confidence semantics (read this)

`confidence` here is **generation completeness, not semantic correctness**:

- `finish_reason == "stop"` (natural end-of-turn) → **0.7**
- `finish_reason == "length"` (hit `max_tokens`, likely truncated) → **0.4** + warning
- empty output → status `partial`, **0.1** + warning

Below **0.5** the skill appends a `lifeorch.review.item/0.1` to `review_queue.jsonl` (repo root, or
`-ReviewQueuePath`). A logprob/self-consistency **semantic** confidence is a documented follow-on
(see `REVIEW_QUEUE.md`). The real signal for consumers is in `model_provenance[]` (finish_reason, token
counts, timings).

## Result shape

`result = { model, engine, mode, selected_from, request{messages,sampling}, output{role,text},
generation{finish_reason, prompt_tokens, completion_tokens, total_tokens, timings},
server{port, health_ms, gpu_layers, context} }`

Artifacts (under `runtime/artifacts/<invocation_id>/`): `output.txt` (raw completion), `exchange.json`
(request + response), `result.json` (the envelope), `stderr.txt`, plus `server.out.log`/`server.err.log`.

## Engine + models (portable copies)

- Engine: llama.cpp **`llama-server`** (CUDA build b8661), staged at
  `…\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\_engines\llama.cpp\bin\` (verified to run
  standalone; depends on a system CUDA runtime).
- Models: GGUF LLMs staged under `…\_pending-model-storage\llm\`. These are **portable copies** decoupled
  from the original (possibly-obsolete) source folders. See `_pending-model-storage\MIGRATION.md`.

## Limits (MVP)

Synchronous only (no streaming); `parallel_safe:false` (a per-call server binds a port + most of VRAM); one
server per call (no warm worker yet — D-0002); LLM text only; no routing/auto-selection (Module 24). The 27B
uses **partial** GPU offload (11 GB VRAM) — `gpu_layers` is a conservative starting value; tune it.

See `WORK_ORDER.md` for full scope and `TOOL_MODEL_REGISTRY.md` for the model inventory.
