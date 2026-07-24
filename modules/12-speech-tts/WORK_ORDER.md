# Work Order: Text-to-Speech Synthesis (`speech.tts`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 12 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#12`

### Problem being solved
The audio track (Modules 10–13) needs a **local text-to-speech** primitive: turn text into speech audio, entirely on
this machine, callable by frontier or local agents. This is the inverse of Module 11 (`speech.stt`) and, with it, the
two halves a future `voice.live` (Module 13) composes. It wraps the **Qwen3-TTS CustomVoice** models (transformers /
the `qwen_tts` package) — the first skill to drive a **Python model** under the speech venv (vs. whisper.cpp/llama.cpp
binaries).

### Immediate practical use
Any agent that needs spoken audio from text this week: reading out a summary/answer, generating voice prompts, TTS for
notifications, or the synthesis half of a voice loop. Produces a standard WAV artifact, callable directly, wrapped, or
through the executor.

### Explicit scope (in)
- One text input → one speech WAV. Resolve the TTS model + venv python from the registry (`tts.weak.qwen3-0p6b`
  default; `tts.strong.qwen3-1p7b`; engine `transformers`, `engine_env` = the speech venv python).
- Drive `qwen_tts.Qwen3TTSModel.generate_custom_voice(text, speaker, language, instruct)` (confirmed via
  `m12-probe-002`: returns `(List[np.ndarray], int sr=24000)`; loads bf16 + `sdpa` on the RTX 2080 Ti; flash-attn
  absent → sdpa). A small **Python inference script** (`tts_infer.py`) does the load+synthesis and prints a one-line
  JSON result; a **PowerShell wrapper** (`Invoke-SpeechTts.ps1`) builds the contract envelope.
- Inputs: `text` (required), `speaker` (default `Ryan`, English), `language` (default `English`), `instruct` (optional
  natural-language style), `model`/tier, `seed` (reproducibility; -1 = random), `dtype` (`bfloat16` default, `float16`
  fallback), `sample_rate`/`format` (optional post-convert via `audio.ingest`).
- Output: a 24 kHz mono PCM16 `speech.wav` (native model rate) + a machine/human record; optional format/rate conversion
  via `audio.ingest` when requested.
- **Confidence** = a documented **synthesis-completeness heuristic** (audio produced, and plausible duration vs. input
  length): empty/near-silent → low; far-too-short-for-the-text → low; plausible → high. NOT audio quality.
- **`model_provenance`** = one entry (model id/engine/engine_env/device/dtype/attn, speaker/language/instruct/seed,
  sample rate, audio seconds/samples, runtime).
- **Review-queue producer** on low confidence (the **fourth** producer): a suspiciously-short/empty synthesis emits one
  `lifeorch.review.item/0.1` (`flagged_by:"speech.tts"`, `requested:"verify_synthesis"`) — a synthesis-failure guard.
- Standard contract surface: `-InputsJson`, `$PSScriptRoot/runtime/artifacts/<id>/`, absolute artifact paths, envelope
  to stdout / diagnostics to stderr, exit 0 on any valid envelope.

### Non-goals (out — do NOT build)
- Voice cloning / voice design (`generate_voice_clone`/`generate_voice_design` exist — deferred to a follow-on/Module 13
  work; MVP is preset-speaker CustomVoice only).
- Batch/multi-text synthesis (`generate_custom_voice` accepts lists — deferred; one text per invocation).
- Streaming / real-time synthesis; SSML; long-form chunking/concatenation.
- Wiring TTS into `model.gateway` (the gateway MVP runs `type=llm` only; the TTS entries stay `wired:false` there —
  speech.tts reads their `path` + `engine_env` directly, mirroring speech.stt / D-0020).
- Installing new Python packages (the venv already has `qwen_tts` + torch + soundfile — confirmed; do not `pip install`).
- A calibrated audio-quality/confidence model (the duration heuristic is honest but not calibrated).

### Dependencies
- Modules: 1 (`skill.bootstrap`), 10 (`audio.ingest`, optional child for format/rate conversion).
- Tools/models: the **speech venv** python (`F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\
  python.exe`; torch 2.11+cu128, transformers 4.57.3, `qwen_tts`, soundfile — verified `m12-probe-001/002`); models
  `tts.weak.qwen3-0p6b` (1.8 GB) / `tts.strong.qwen3-1p7b` (3.8 GB) staged under `_pending-model-storage\tts\`.
- Contract features: `confidence`, `model_provenance`, artifacts[], review-queue producer.

### Skill contract requirements
- `skill_id:"speech.tts"`, `name:"Text-to-Speech Synthesis"`, `version:"0.1.0"`, `determinism:"mixed"`
  (deterministic orchestration; stochastic sampling generation — `do_sample=true`, seedable), `parallel_safe:false`
  (binds the CUDA context + loads a model), `batch:false`, `streaming:false`.
- Result `result` shape (below); `confidence` populated; `model_provenance` populated; artifact kinds wav/json/markdown.

### Inputs and outputs
- **Inputs:** `text` (req), `speaker` (def `Ryan`), `language` (def `English`), `instruct` (opt), `seed` (def -1),
  `dtype` (def `bfloat16`), `sample_rate` (def 0=native 24000), `format` (def `wav`), `model` (def `tts.weak.qwen3-0p6b`),
  `registry`, `python_path`, `tts_infer_path`, `audio_ingest_path`, `pwsh_path`, `review_queue_path`,
  `confidence_threshold` (def 0.5), `max_new_tokens` (opt).
- **Outputs — `result`:** `{input{text,chars}, model{id,name,engine,engine_env,device,dtype,attn}, params{speaker,
  language,instruct,seed,max_new_tokens}, audio{path,sample_rate,channels,samples,duration_s,bytes,sha256,format},
  confidence{overall,reason}, review{threshold,flagged,queue_path}, synthesis{runtime_ms,real_time_factor}}`

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `speech.wav` (24 kHz mono PCM16; or converted), `tts.json`
  (`lifeorch.tts.synthesis/0.1`), `tts.md`, `result.json`, `stderr.txt`, `py.log`, and `convert/…` when `audio.ingest`
  post-conversion ran.

### Proposed implementation
- **Language:** a **Python inference script** (`tts_infer.py`, run under the venv) + a **PowerShell wrapper**
  (`Invoke-SpeechTts.ps1`). Fits the language policy (Python for the model ecosystem; PowerShell glue/contract).
  The wrapper spawns python with a JSON args file, reads a one-line JSON result from stdout (mirrors `classify.batch`'s
  child spawn), builds the envelope, computes confidence, writes artifacts, appends review items. `HF_HUB_OFFLINE=1`
  set so the local model path never hits the network. dtype bf16 → float16 fallback; attn `sdpa` (flash-attn absent).

### External tools or models
- Speech venv python + `qwen_tts` (present). Qwen3-TTS CustomVoice 0.6B/1.7B (staged). ffmpeg via `audio.ingest` for
  optional conversion. All verified present — nothing to install.

### Installation steps
- None (venv + models + `qwen_tts` already present; verified `m12-probe-001/002`). Register the skill + add
  `defaults.tts`/`tiers.tts` to `models.json` (additive; entries stay `wired:false` for the gateway).

### Tests
- **Cloud pre-ship (off-machine):** pwsh 7.4.6 AST-parse every `.ps1`; `py_compile` `tts_infer.py`; a **mock python**
  (`tests/mock-tts-infer.py` — writes a real short WAV via `wave`/stdlib and prints the result JSON) drives the *real*
  `Invoke-SpeechTts.ps1` so the parse/confidence/review/envelope/artifact + optional `audio.ingest` conversion logic run
  off-GPU (the pre-ship gate). Same assertions as the live run.
- **Live via the executor (Windows):** manifest validity; a **live** English synthesis (`speaker=Ryan`) → assert a real
  WAV (ffprobe: 24 kHz mono, duration > 0), overall confidence in (0,1], `model_provenance[1]`, artifacts with sha256;
  a forced-empty/short case → review item; a `format=mp3` post-convert via `audio.ingest`; error paths (`no_text`,
  `model/python not found`); the Module 1 wrapper; no leftover python/GPU processes.

### MVP acceptance criteria
- Schema-valid `lifeorch.skill.result/0.1` with `determinism:"mixed"`, `confidence` populated, `model_provenance[1]`.
- Live synthesis produces an audible 24 kHz mono WAV of plausible duration; artifacts hashed.
- Low-confidence (empty/too-short) path appends a valid `lifeorch.review.item/0.1` (`flagged_by:"speech.tts"`).
- Optional `audio.ingest` conversion produces the requested format/rate.
- All tests pass through the executor (exit 0); cloud pre-ship harness green first.

### Manual verification procedure
- Submit an executor task synthesizing a sentence with `speaker=Ryan`; open `speech.wav` and confirm intelligible
  speech; open `tts.md` for duration/speaker/confidence.

### Documentation requirements
- Skill `README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `speech.tts` skill entry to `TOOL_MODEL_REGISTRY.md`; mark the TTS model rows consumed by Module 12; add a
  `qwen_tts`/speech-venv runtime note (verified). Add `defaults.tts`/`tiers.tts` to `models.json` (leave entries
  `wired:false` for the gateway).

### State updates
- Update `CURRENT_STATE.md` (Module 12 complete), `MODULE_ROADMAP.md` (#12 MVP complete), `REVIEW_QUEUE.md` (fourth
  producer), a new `DECISION_LOG.md` D-entry. Note: `core-docs` → attached Claude Project mirroring must be done from a
  Project-connected session (this Cowork/device-bridge session lacks those tools).

### Known follow-on work
- Voice cloning / voice design; batch/multi-text; long-form chunking + concat; streaming; a warm/persistent TTS worker
  (per-call model load ≈ 30–40 s cold — the pressure point); the strong 1.7B tier tuning; SSML/prosody controls;
  calibrated confidence; de-duplicate the triplicated speech tokenizer (REVIEW_QUEUE note) when relocating models.

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above.
- The venv/model/`qwen_tts` resolution fails and fixing it is non-trivial (stop, report — do NOT pip-install blindly).
- The contract lacks something this module needs (stop, propose the change).
- MVP acceptance is met — **stop; do not start Module 13.**
