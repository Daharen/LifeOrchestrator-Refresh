# Work Order: Image Interpretation (`image.interpret`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 17 session, 2026-07-25) ·
**Roadmap entry:** `MODULE_ROADMAP.md#17`

### Problem being solved
The perception block can read text (`ocr.layout`, #14), do deterministic pixel plumbing (`image.util`,
#15), and name+locate objects (`detect.objects`, #16) — but nothing gives an agent a **semantic, free-text
understanding** of an image: a caption, an answer to a question about it, or an interpretation of what is on
the screen. `image.interpret` closes that with a **local vision-language model (VLM)**: one image (+ an
optional prompt) in → a natural-language interpretation out. It is the fourth module of the image/document
perception block (14–18) and the last perception primitive #18 (`image.index`) needs before it can fuse
text + pixels + objects + meaning into one index.

### Immediate practical use
A local or frontier agent points this at a photo (`-InputFile`) or the live screen (`-Capture`) and gets a
caption, a detailed description, or an answer to a specific question ("what error dialog is shown?", "how
many people are in this photo?", "summarize this chart"). It runs entirely locally on the RTX 2080 Ti,
offloading interpretation cost off the frontier model. Feeds `image.index` (#18).

### Explicit scope (in)
- Interpret **one** image with a **local VLM** → `interpretation.text` (free-text), plus finish_reason /
  token counts / timings.
- Modes via `-Mode`: `caption` (one sentence), `describe` (detailed, the default for a file), `vqa`
  (answer a supplied `-Prompt`/question), `screen` (screen-oriented default prompt, the default with
  `-Capture`). An explicit `-Prompt` is used verbatim and selects `vqa` unless a mode is named.
- Backend = the **already-staged llama.cpp `llama-server` (b8661)** run in **multimodal** mode
  (`-m <vlm.gguf> --mmproj <projector.gguf>` → `/v1/chat/completions` with an OpenAI-style `image_url`
  base64 data URI) — the same engine `model.gateway` (#7) drives, extended with the projector. Default model
  `vlm.qwen2p5-vl-3b` (Qwen2.5-VL-3B-Instruct GGUF Q4_K_M + mmproj, Apache-2.0), staged on F:.
- Registry-driven (`models.json`, `type=vlm`), **decoupled from the gateway `wired` gate** (like
  `ocr.layout`/`detect.objects`, D-0020/D-0023): the entry is `wired:false` for the gateway (which runs
  `type=llm` only) and read directly by this skill.
- **Confidence** = a documented generation-completeness + refusal + non-empty **heuristic** (like
  `model.gateway`/`ocr.layout` — NOT calibrated/semantic): `stop`→0.7, `length` (truncated)→0.4, refusal→0.3,
  empty→0.1. Populates `confidence` + `model_provenance`.
- **Seventh review-queue producer**: a low-confidence / refusal / empty interpretation → **one page-level**
  item (`flagged_by:"image.interpret"`, `requested:"verify_interpretation"`, reason ∈
  `low_confidence`|`needs_strong_review`(refusal)|`failed_transform`(empty)).
- Compose **capture.screen** (#6) via `-Capture` ("interpret my screen"); compose **image.util** (#15) via
  `-MaxDimension` (downscale a huge screenshot before sending, to bound vision tokens).
- Artifacts `interpret.json` / `interpret.md`; contract-valid `lifeorch.skill.result/0.1` envelope.
- Dual-mode test harness green on the cloud box before shipping (real wrapper + a **captured-real
  llama-server response** seam, since the VLM's real weights can't run on the Linux cloud box); live via the
  executor.

### Non-goals (out — do NOT build)
- Batch/directory/multi-image; video (#19–22); multi-turn/conversational VLM sessions.
- **Grounding / bounding-box output** from the VLM (open-vocab detection is a `detect.objects` follow-on;
  boxes are #16 / #22).
- OCR-quality text extraction (that is `ocr.layout` #14 — the VLM may read text but is not the OCR path).
- A warm/persistent VLM server; streaming tokens; logprob/calibrated/semantic confidence.
- The **transformers-venv** backend (viable per the probe — speech venv has transformers 4.57.3 + CUDA +
  Qwen2-VL/2.5-VL classes — but heavier/bf16; documented as the alternative in D-0026, not built).
- Runtime model download (the model is **pre-staged** on F:; the skill never fetches weights).
- Fine-tuning / prompt-library expansion beyond the four MVP modes.

### Dependencies
- Modules: 1 (contract/wrapper), 7 (registry `models.json` + the staged `llama-server` engine),
  6 (capture.screen, only `-Capture`), 15 (image.util, only `-MaxDimension`). Tools/models:
  `vlm.qwen2p5-vl-3b` (new registry entry: model gguf + mmproj). Contract features: `confidence`,
  `model_provenance`, review queue.

### Skill contract requirements
- `skill_id=image.interpret`, `name`, `version 0.1.0`, `determinism=mixed`, **`parallel_safe=false`**
  (binds a loopback port + CUDA/VRAM via `llama-server` — unlike #14–16), `batch=false`, `streaming=false`.
- `result` = object (see Inputs/outputs). `confidence` populated (completeness heuristic). `model_provenance`
  = one entry (model/engine/build/device/tokens/timings/finish_reason). Artifact kinds: `json`, `markdown`.

### Inputs and outputs
- **Inputs:** `input` (image; required unless `capture`), `prompt` (question/instruction; optional),
  `mode` (`caption`|`describe`|`vqa`|`screen`; default resolved from prompt/capture), `system` (optional
  system prompt), `model`/`tier`, `max_tokens` (512), `temperature` (0.2), `top_p` (0.9), `seed` (-1),
  `confidence_threshold` (0.5), `max_dimension` (downscale via image.util), `capture`, `capture_inputs`,
  `context`/`gpu_layers`/`port`/`load_timeout_sec` (server knobs), plus path overrides
  (`registry`/`model_path`/`mmproj_path`/`engine_path`/`image_util_path`/`capture_path`/`pwsh_path`/
  `review_queue_path`) and the **`vlm_response_path`** test seam. `-InputsJson` mirror.
- **Outputs:** `result{input,image,model,request,preprocess,interpretation{text,finish_reason,prompt_tokens,
  completion_tokens,total_tokens,timings},confidence{value,reason},review,server}`. Files `interpret.json`,
  `interpret.md`, `result.json` (+ `interpret_args.json`, `server.out.log`/`server.err.log`, `stderr.txt`;
  `capture/…`, `image_util/…` when composed).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `interpret.json`, `interpret.md`, `interpret_args.json`,
  `server.out.log`, `server.err.log`, `result.json`, `stderr.txt` (+ `capture/`, `image_util/`).

### Proposed implementation
- **Language:** a single **pwsh-7 wrapper** (`Invoke-ImageInterpret.ps1`) — **no python worker**. The image
  is base64-encoded in PowerShell; the VLM call reuses `model.gateway`'s proven `llama-server` lifecycle
  (free-port pick → `Start-Process` with redirected logs → `/health` poll → `POST /v1/chat/completions` →
  `taskkill` teardown), extended with `--mmproj` and an `image_url` content part. **Why:** it reuses the
  project's blessed engine (no new runtime/venv), a quantized GGUF is VRAM-light and loads fast, and
  PowerShell already owns the HTTP+envelope path in #7. Reuses the #16 scaffolding (Has/Prop/Get-Sha256Hex/
  InputsJson-merge/structured errors/review producer/child-skill compose).
- **Cloud gate seam:** `-VlmResponsePath <captured.json>` short-circuits the server launch and feeds a
  **captured-real** `llama-server` chat-completion response into the same parse/confidence/review/envelope
  path — the analog of `speech.stt`'s captured `whisper.json` mock. The real HTTP + server lifecycle is
  covered only live (executor), like every stochastic module 11/12/14.

### External tools or models
- **llama.cpp `llama-server` b8661** — already staged (`_engines\llama.cpp\bin\llama-server.exe`), driven by
  #7. Probe `m17-probe-001` confirmed this build has full multimodal support (`--mmproj`, mtmd, image-token
  controls).
- **`vlm.qwen2p5-vl-3b`** — Qwen2.5-VL-3B-Instruct GGUF (Q4_K_M model + f16 mmproj), Apache-2.0, downloaded
  from Hugging Face and staged to `F:\...\_pending-model-storage\vlm\Qwen2.5-VL-3B-Instruct-GGUF\`
  (`m17-probe-002`), sha256 recorded, load+caption live-verified with this exact server build before coding.

### Installation steps
- `m17-probe-002` (executor): `huggingface_hub` (speech venv) downloads the model + mmproj GGUFs directly to
  F: (cache on F: to spare C:); then a live server launch + a real caption of `dog.jpg` confirms the backend.
  Register additively in `models.json` (`defaults.vlm`, `tiers.vlm`, `vlm.qwen2p5-vl-3b`); re-verify Module 7
  28/28 (any registry change is gateway-visible).

### Tests
- **Direct/cloud gate:** `tests/Invoke-ImageInterpretTests.ps1` runs the **real** wrapper with
  `-VlmResponsePath <captured real response>` on the committed fixture. Asserts manifest flags, a valid
  interpretation envelope (non-empty text, confidence in (0,1], provenance engine `llama-server`), mode
  defaulting, the review producer (forced low confidence → `verify_interpretation`; a refusal fixture →
  `needs_strong_review`; an empty fixture → `failed_transform`), the **image.util `-MaxDimension`**
  composition (real on Linux), five error paths, and the Module 1 wrapper.
- **Through the executor:** the same harness **live** (real `llama-server` + the staged VLM, no
  `-VlmResponsePath`) — a real caption/VQA of `dog.jpg`; the Windows-only **capture.screen** composition
  (`-Capture` → `source=capture`); a real-registry smoke; no orphaned `llama-server`.

### MVP acceptance criteria
- Manifest schema-valid; `determinism=mixed`, `parallel_safe=false`, `batch/streaming=false`.
- Live interpretation of `dog.jpg`: non-empty `interpretation.text` that references the visible content
  (dog/bicycle/…), envelope `confidence` set by the heuristic, provenance engine `llama-server` + device
  `cuda:0`, `interpret.json`/`interpret.md` artifacts sha256-verified.
- Review producer fires for low-confidence / refusal / empty with valid `image.interpret`
  `verify_interpretation` items.
- image.util `-MaxDimension` composition downscales before sending; capture composition yields
  `source=capture`.
- Error paths return schema-valid error envelopes (`input_not_found`, `registry_not_found`,
  `model_not_found`, `model_file_not_found`, `mmproj_not_found`, `engine_not_found`).
- Green on the cloud pre-ship gate (captured-response seam) **and** live via the executor; no orphaned
  `llama-server`.
- `models.json` additive; Module 7 re-verified 28/28.

### Manual verification procedure
- Run `-InputFile` on a real photo with `-Mode describe`; open `interpret.md`; confirm the description
  matches. Run `-Capture -Mode screen` and confirm it summarizes the visible screen. Run `-Prompt "…"` VQA.

### Registry updates
- `TOOL_MODEL_REGISTRY.md`: add `vlm.qwen2p5-vl-3b` (VLM) + note the `llama-server` multimodal capability of
  the staged engine.

### State updates
- `CURRENT_STATE.md`, `MODULE_ROADMAP.md#17`, `DECISION_LOG.md` (D-0026), `REVIEW_QUEUE.md` (seventh
  producer), `models.json`.

### Known follow-on work
- A warm/persistent VLM server (shared worker-pool pressure with #7/#8/#12/#14/#16); logprob/calibrated
  semantic confidence; batch/directory; multi-image + multi-turn; open-vocab grounding boxes (a #16
  follow-on); a larger VLM tier (7B) / the transformers-venv backend; wiring the VLM as a second `ocr.layout`
  engine; `image.index` (#18) consuming this + #14/#15/#16.

### STOP conditions
- Scope beyond the "Explicit scope" list. A dependency missing/broken beyond a simple stage. MVP acceptance
  met → stop; do not start Module 18.
