# Work Order: Local Model Gateway (`model.gateway`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 7 session, 2026-07-24) · **Roadmap entry:** `MODULE_ROADMAP.md#7`

### Problem being solved
Frontier and local agents have no common way to *run a local model* on this machine. Every downstream
capability that wants cheap local inference (batch classification, review adjudication, later perception/
speech) would otherwise hard-code a different engine, path, and output format. This module closes that gap
with **one skill that takes a model selector + inputs, runs the model through a wrapped local engine, and
returns a contract-valid envelope** with full `model_provenance` and a `confidence` — the first stochastic/
mixed skill in the suite.

### Immediate practical use
This week: Modules 8 (`classify.batch`) and 9 (`review.processor`) call `model.gateway` to get text out of a
**local LLM** — a weak model for bulk labeling, a strong model for adjudication — without knowing anything
about llama.cpp. A caller submits `{model, prompt}` (or `{model, messages}`) and gets back `{text, tokens,
finish_reason, ...}` plus provenance. Selecting *which* model/strength is a one-line change in a config
registry, so if a tier proves too weak it is swapped without touching callers or code.

### Explicit scope (in)
- **Run local LLMs (text) via `llama-server`** (the built llama.cpp CUDA server): start → wait for `/health`
  → POST `/v1/chat/completions` → parse → stop the server. One isolated server process per invocation
  (D-0002), no persistent worker yet.
- **A declarative model registry** (`models.json`) that **declares every discovered local model**
  (LLM × 4, STT × 1, TTS × 2 + tokenizer, embedding × 1) with id / type / family / format / path / engine /
  wired-flag / resource hints — the single source of truth the gateway resolves against. Config-driven so
  model selection/strength is trivially switchable.
- **Selection by** explicit `model` (a `model_id`) **or** a `tier` alias (`weak`/`strong`) that maps to a
  default LLM per the registry. No automatic "pick the best model" logic (that is routing — Module 24).
- **Generation controls:** `max_tokens`, `temperature`, `top_p`, `top_k`, `seed`, optional `stop`, optional
  `system` string; input as a `prompt` string or a `messages` array. The model's own chat template is applied
  by the engine (`--jinja`).
- **Provenance + confidence:** populate `model_provenance[]` (model id/version/quant/params, engine + build,
  device/gpu-layers, token counts, timings, finish_reason) and `confidence` (0..1) via a **documented
  generation-completeness heuristic**; below threshold → append a `REVIEW_QUEUE` item.
- **Artifacts:** the model output + a request/response record + stderr, under `runtime/artifacts/<id>/`.

### Non-goals (out — do NOT build)
- **Wiring STT / TTS / embedding execution.** They are **declared** in the registry (with staged copies +
  the roadmap module that will wire them) but calling them returns a structured `model_not_wired` error.
  STT → Module 11, TTS → Module 12, embeddings → Module 23. (Engines exist: whisper.cpp + the speech venv.)
- **Streaming / token callbacks** (`streaming:false`). Synchronous full completion only.
- **A persistent/warm model server** shared across calls (revisit per D-0002 if load latency dominates).
- **Task routing / auto model selection / quality scoring** (Module 24 `route.tasks`).
- **Prompt engineering, batching, multi-turn memory, tool-calling orchestration** (later modules).
- **Model installation/downloading.** Everything needed is already on disk (see registry).
- **Semantic-correctness confidence** (logprob/self-consistency scoring) — heuristic only for the MVP;
  logprob-based confidence is a documented follow-on.

### Dependencies
- Modules: 1 (`skill.bootstrap` — `lib/SkillContract.psm1` validators + `Invoke-Skill.ps1` wrapper), 0
  (executor, for testing/running). · Tools/models: `pwsh` 7.4.6; the llama.cpp `llama-server.exe` (CUDA
  build b8661); the GGUF LLMs (staged copies). · Contract features: `model_provenance`, `confidence`,
  `determinism:"mixed"`, artifact envelope.

### Skill contract requirements
- `skill_id` `model.gateway` · `name` "Local Model Gateway" · `version` `0.1.0` · `determinism` **`mixed`**
  (deterministic wrapping mechanics; stochastic model output) · `parallel_safe` **`false`** (a per-call
  llama-server binds a port and consumes most of VRAM; concurrent runs would contend the GPU/port) ·
  `batch` `false` · `streaming` `false`.
- `result` shape (object): `{ model, engine, mode, request{...}, output{ text, role }, generation{
  finish_reason, prompt_tokens, completion_tokens, total_tokens, timings }, server{ port, health_ms,
  load_ms }, selected_from }`.
- `confidence` populated (0..1). `model_provenance[]` populated with one entry per model run.
- Artifact kinds: `text` (the completion), `json` (request+response record), plus `result.json` + `stderr.txt`.

### Inputs and outputs
- **Inputs** (named params + `-InputsJson`): `model` (string, optional — model_id; else `tier`/default),
  `tier` (string, optional — `weak`|`strong`), `prompt` (string), `messages` (array, optional — overrides
  prompt), `system` (string, optional), `max_tokens` (int, default 256), `temperature` (number, default 0.7),
  `top_p` (number, default 0.95), `top_k` (int, default 40), `seed` (int, default -1), `stop` (string[],
  optional), `registry` (string, optional — path to models.json), `port` (int, optional — else auto-pick),
  `gpu_layers` (int, optional — overrides registry), `context` (int, optional — overrides registry),
  `load_timeout_s` (int, default 120).
- **Outputs:** the `result` object above; artifacts `output.txt`, `exchange.json`, `stderr.txt`, `result.json`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `output.txt` (raw completion), `exchange.json` (normalized
  request + full engine response + timings), `result.json` (the envelope), `stderr.txt` (diagnostics).

### Proposed implementation
- **Language: PowerShell** (per policy: fastest correct MVP; wraps an existing binary; Windows-native HTTP).
  `Invoke-ModelGateway.ps1`.
- **Engine wrap:** resolve model → find a free `127.0.0.1` port → `Start-Process llama-server.exe -m <gguf>
  -ngl <n> -c <ctx> --host 127.0.0.1 --port <p> --no-warmup` (stdout/stderr → temp logs) → poll `GET /health`
  until 200 (bounded by `load_timeout_s`) → `POST /v1/chat/completions` `{messages, max_tokens, temperature,
  top_p, top_k, seed, stop}` → parse OpenAI-shape JSON (`choices[0].message.content`, `finish_reason`,
  `usage`, `timings`) → **always** stop the server in `finally` (`taskkill /PID <id> /T /F`).
- **Confidence heuristic (documented):** `finish_reason=="stop"` (natural EOS) → `0.7`;
  `finish_reason=="length"` (hit `max_tokens`, likely truncated) → `0.4` + warning; empty content →
  `status:"partial"`, `0.1`, warning. Threshold `< 0.5` → append `lifeorch.review.item/0.1` to
  `review_queue.jsonl`. This confidence is **generation completeness, not semantic correctness** (stated in
  README + envelope diagnostics).
- **Robustness:** async stream draining (no pipe deadlock); closed stdin; port-in-use retry; structured
  errors (`model_not_found`, `model_not_wired`, `engine_not_found`, `model_file_missing`, `server_start_failed`,
  `health_timeout`, `completion_failed`).

### External tools or models (already present — do NOT reinstall)
- `llama-server.exe` — llama.cpp CUDA build b8661, staged to
  `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\_engines\llama.cpp\bin\`
  (source `F:\Qwen3.5-27B\llama.cpp\build\bin\`). Registry `engine_path` points at the staged copy if it runs
  standalone, else the source path (verified during staging).
- GGUF LLMs — staged copies under `..._pending-model-storage\llm\` (source `F:\Qwen3.5-27B\...`).

### Installation steps
- None. Detection (this session) confirmed the engine + models exist; staging makes portable copies. Record
  versions/paths in `TOOL_MODEL_REGISTRY.md`.

### Tests
- **Direct:** `Invoke-ModelGateway.ps1 -Tier weak -Prompt "Reply with exactly one word: PONG" -MaxTokens 16`
  → assert schema-valid `lifeorch.skill.result/0.1`, `status ok`, non-empty `output.text`, `confidence` in
  0..1, `model_provenance[0]` populated (tokens+timings+finish_reason), artifacts on disk with sha256.
- **Through the executor:** submit a task package calling the harness; assert `result.json` + artifacts.
- Error paths (no model load needed, fast): `model_not_found` (bogus id), `model_not_wired` (an STT id),
  `engine`/`registry` missing. Manifest validates; wrapper (`Invoke-Skill.ps1`) reports manifest+envelope valid.
- One **live** generation against a **staged small LLM** (0.5B/1.5B) — fast, GPU-offloaded.

### MVP acceptance criteria
- [ ] `skill.json` validates (`Test-SkillManifest`).
- [ ] A live call to a wired LLM returns `status:"ok"`, non-empty text, a schema-valid envelope, `confidence`
      set, and `model_provenance[0]` with token counts + timings + finish_reason.
- [ ] `tier` alias and explicit `model_id` both resolve and run.
- [ ] Non-wired model type returns a clean `model_not_wired` envelope (still `exit 0`, valid envelope).
- [ ] Bad model id returns `model_not_found`; all error paths emit valid error envelopes.
- [ ] Runs direct, wrapped (`Invoke-Skill.ps1`), and through the executor; artifacts written with sha256.
- [ ] A low-confidence/truncated result appends a `review_queue.jsonl` item.
- [ ] Full regression suite green through the executor.

### Manual verification procedure
- Submit a gateway task through the executor with `{tier:"weak", prompt:"Name three primary colors."}`;
  confirm `completed`, read `stdout.txt` envelope, open `output.txt` and `exchange.json`, confirm the server
  was stopped (no lingering `llama-server.exe`).

### Documentation requirements
- Skill `README.md` (invocation, registry format, confidence semantics, wired vs declared, how to add/swap a
  model), `skill.json`, `examples/example-invocation.md` + `examples/example-result.json`, and `models.json`
  with inline `_comment` fields.

### Registry updates
- Add `model.gateway` to `TOOL_MODEL_REGISTRY.md`; add the hardware profile; add every discovered model as an
  inventory entry (status `staged`/`declared`, real sizes) so future sessions **don't re-download** what exists;
  register the F: large-data root + `_pending-model-storage` as a known source.

### State updates
- `CURRENT_STATE.md` (active module, models, hardware, tests, next action), `MODULE_ROADMAP.md#7` → MVP complete,
  `DECISION_LOG.md` (large-data/staging policy; gateway engine/confidence design), `REVIEW_QUEUE.md`
  (tokenizer triplication; heuristic-confidence follow-on; engine-portability check).

### Known follow-on work (NOT this session)
- Wire STT (Module 11, whisper.cpp), TTS (Module 12, speech venv), embeddings (Module 23).
- Persistent/warm model workers if per-call load latency dominates (D-0002 revisit).
- Logprob/self-consistency **semantic** confidence to replace the completeness heuristic.
- Relocate each staged model from `_pending-model-storage` into its owning module's F: folder; delete the
  pending folder when empty (see `MIGRATION.md`).
- Stage/verify remaining engines (whisper.cpp already built; speech venv) for portability.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g., wiring a second modality) → stop, write it to the roadmap.
- The staged engine cannot run standalone AND the source engine is unavailable → stop, report.
- MVP acceptance met → **stop; do not start Module 8.**
