# Work Order: Voice Interaction Loop (`voice.live`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 13 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#13`

### Problem being solved
The **capstone of the audio track (10–13)**: turn a spoken-audio input into a spoken (and/or textual) response by
**composing the modules already built** — `speech.stt` (Module 11, transcription with whisper segmentation =
utterance/voice-activity detection), `model.gateway` (Module 7, the local LLM), and `speech.tts` (Module 12,
synthesis) — into one **voice-turn** primitive. It reimplements nothing; it orchestrates. This is the first skill
that composes multiple stochastic model skills end-to-end, and it validates that the contract/envelope pattern makes
skills cleanly composable.

### Immediate practical use
Any agent that wants a one-shot **voice turn** this week: hand it a spoken question (a WAV) and get back a transcript,
a concise answer, and a spoken reply WAV — a local, offline voice assistant turn. Also the building block a future
interactive/streaming loop and desktop-observation broker (#25/#26) will call.

### Explicit scope (in)
- One input audio file → one voice turn. Pipeline: **(1) STT** — run `speech.stt` on the input (it normalizes via
  `audio.ingest` internally); its whisper segments are the detected speech/utterances. If **zero** segments →
  `no_speech` (skip respond/speak, status ok). **(2) Respond** (`-Respond`, default on) — feed the transcript text to
  `model.gateway` (default `-Tier weak`) with a concise voice-assistant system prompt → response text. **(3) Speak**
  (`-Speak`, default on) — `speech.tts` the text to speak (the response, or the transcript when `-ReadbackTranscript`)
  → `reply.wav`.
- Children are spawned as **child pwsh** processes (the established composition pattern) with **overridable
  entrypoint paths** (`-SttPath` / `-GatewayPath` / `-TtsPath`) so the pipeline can be tested off-GPU against mock
  children.
- **Child review aggregation**: children's low-confidence review writes are pointed at an in-artifact
  `child_review.jsonl` by default (a transient turn should not flood the canonical queue); `-ReviewQueuePath` routes
  them to a canonical queue instead. voice.live is an **orchestrator, not itself a review producer**.
- Envelope `confidence` = the STT transcript confidence (the "did we understand the user" signal);
  `model_provenance` = the **aggregate** of every child model used (stt + gateway + tts).
- Standard contract surface: `-InputsJson`, `$PSScriptRoot/runtime/artifacts/<id>/`, absolute artifact paths,
  envelope to stdout / diagnostics to stderr, exit 0 on any valid envelope.

### Non-goals (out — do NOT build)
- **Live microphone capture / real-time streaming** ("record"). No mic can be assumed on this headless desktop, and
  the executor is not a realtime audio path. The MVP is a **file-driven offline turn**; a mic/streaming front-end is a
  clearly-scoped follow-on (a separate `audio.capture` skill + a streaming loop).
- **Standalone VAD pre-segmentation.** whisper's `whisper-vad-speech-segments.exe` exists but **no VAD ggml model is
  staged** (`m13-probe-001`), so a dedicated `--vad` pass is deferred; whisper's own segmentation (via `speech.stt`) is
  the utterance detector for the MVP.
- Multi-turn dialogue/state, barge-in, wake-word, diarization, or re-implementing any child's internals.
- Making voice.live its own review producer (children already flag; voice.live aggregates, it does not double-flag).

### Dependencies
- Modules: 1 (contract/wrapper), 11 (`speech.stt`), 7 (`model.gateway`), 12 (`speech.tts`) — all MVP complete and
  verified. (10 `audio.ingest` is used transitively by `speech.stt`.)
- Tools/models: whisper.cpp + `stt.whisper.base-en`; a wired LLM (default weak 1.5B); Qwen3-TTS + the speech venv —
  all present/verified. Nothing to install.
- Contract features: `confidence`, `model_provenance` (aggregate), artifacts[].

### Skill contract requirements
- `skill_id:"voice.live"`, `name:"Voice Interaction Loop"`, `version:"0.1.0"`, `determinism:"mixed"`,
  `parallel_safe:false` (children bind the GPU/CUDA sequentially), `batch:false`, `streaming:false`.
- Result `result` shape (below); `confidence` = STT overall; `model_provenance` = aggregate; artifact kinds wav/json/markdown.

### Inputs and outputs
- **Inputs:** `input` (req, audio path), `respond` (bool, def true), `speak` (bool, def true),
  `readback_transcript` (bool, def false), `system` (LLM system prompt override), `tier` (LLM tier, def weak),
  `max_tokens` (def 200), `speaker` (TTS, def Ryan), `language` (def English), `stt_model`/`gateway_model`/`tts_model`,
  `format` (reply audio format, def wav), overrides `stt_path`/`gateway_path`/`tts_path`/`pwsh_path`/`review_queue_path`.
- **Outputs — `result`:** `{ input{path}, transcript{text,utterance_count,confidence,segments_ref,language},
  response{text,model,confidence,finish_reason}|null, reply{path,format,sample_rate,duration_s,bytes,sha256}|null,
  stages[{name,status,ms,error}], config{respond,speak,readback_transcript,tier,speaker}, child_review_path,
  child_review_count }`

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `voice.json` (`lifeorch.voice.turn/0.1`), `voice.md`, `reply.wav`
  (when speaking), `result.json`, `stderr.txt`, `child_review.jsonl`, and child artifact subdirs `stt/`, `gateway/`,
  `tts/` (each child's own `runtime/artifacts/<id>/…`).

### Proposed implementation
- **Language:** PowerShell orchestrator (`Invoke-VoiceLive.ps1`) — no new model code, only composition (language
  policy: PowerShell for integration glue). Spawns each child via `& $PwshPath -File <childEntry> -InputsJson <json>
  -ArtifactRoot <sub>` and parses the returned `lifeorch.skill.result/0.1` envelope (mirrors `classify.batch` →
  gateway and `speech.stt` → audio.ingest). A stage that errors short-circuits to a structured `stage_failed` with the
  failing stage named; partial progress (e.g. transcript but LLM failed) is still reported.

### External tools or models
- None new. Reuses whisper.cpp / LLM / Qwen3-TTS via the child skills' own registry resolution.

### Installation steps
- None. Register the `voice.live` skill in `TOOL_MODEL_REGISTRY.md`.

### Tests
- **Cloud pre-ship (off-machine):** pwsh 7.4.6 AST-parse every `.ps1`; a **mock-children** harness (tiny pwsh scripts
  emitting canned `lifeorch.skill.result/0.1` envelopes for stt/gateway/tts, pointed to via the override paths) drives
  the *real* `Invoke-VoiceLive.ps1` so the pipeline/parse/aggregate/envelope logic runs off-GPU. Same assertions.
- **Live via the executor (Windows):** manifest validity; a **live** full turn on the bundled `samples\jfk.wav` →
  transcript contains "country", a non-empty LLM response, a real `reply.wav` (ffprobe: 24 kHz mono, duration > 0),
  `model_provenance` with ≥3 entries (stt+gateway+tts), stages all ok; `-Respond:$false -Speak:$true
  -ReadbackTranscript` path; a `no_speech` path (silent/tone input → no response/reply, status ok); error path
  (`input_not_found`); the Module 1 wrapper; no orphaned processes.

### MVP acceptance criteria
- Schema-valid `lifeorch.skill.result/0.1` with `determinism:"mixed"`, `confidence` populated (STT), aggregate
  `model_provenance` (≥3 on a full turn).
- Live jfk turn: correct transcript, a coherent short answer, an audible `reply.wav`; artifacts hashed.
- `no_speech` and respond/speak toggles behave; children resolve from their default sibling paths.
- All tests pass through the executor (exit 0); cloud pre-ship harness green first.

### Manual verification procedure
- Submit an executor task with `samples\jfk.wav`; open `voice.md` (transcript + answer + reply info) and play
  `reply.wav`.

### Documentation requirements
- Skill `README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `voice.live` skill entry to `TOOL_MODEL_REGISTRY.md` (composes 11/7/12).

### State updates
- Update `CURRENT_STATE.md` (Module 13 complete → **audio track 10–13 complete**), `MODULE_ROADMAP.md` (#13 MVP
  complete), a new `DECISION_LOG.md` D-entry. `REVIEW_QUEUE.md`: note voice.live aggregates child flags (not a new
  producer). Note: `core-docs` → attached Claude Project mirroring must be done from a Project-connected session.

### Known follow-on work
- A mic-capture `audio.capture` skill + a streaming/interactive loop; standalone VAD (stage a VAD ggml model);
  multi-turn dialogue + memory; barge-in/wake-word; a warm-worker pool so a turn doesn't pay three cold model loads;
  routing (#24) to pick tiers per turn; a desktop-observation broker (#25) feeding voice answers.

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above (esp. do NOT add live mic/streaming).
- A child skill fails to resolve/compose and fixing it is non-trivial (stop, report).
- The contract lacks something this module needs (stop, propose the change).
- MVP acceptance is met — **stop.** (This is the last module for this agent instance.)
