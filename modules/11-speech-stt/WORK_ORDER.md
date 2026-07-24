# Work Order: Speech-to-Text Transcription (`speech.stt`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 11 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#11`

### Problem being solved
The audio track (Modules 10–13) needs a reliable **timestamped transcription** primitive: turn a spoken-audio
file into text segments with start/end times and a usable per-segment confidence, entirely locally and cheaply.
Module 10 (`audio.ingest`) already produces whisper-ready 16 kHz mono s16 WAV; this module consumes that (or
normalizes arbitrary input through `audio.ingest` first) and runs **whisper.cpp** to produce the transcript.
It is the second audio module and the first **stochastic/mixed** skill that wraps an external **model** binary
(vs. Module 7's server): it must populate `confidence` + `model_provenance` and route low-confidence segments
to the review queue (the pattern established by D-0007 / D-0016).

### Immediate practical use
Any agent (frontier or local) that has an audio/voice file and needs its words + timings: meeting/『voice-memo』
transcription, captioning, feeding a transcript to `classify.batch`/`review.processor`, or as the STT half of a
future `voice.live` (Module 13). Callable this week directly, wrapped, or through the executor.

### Explicit scope (in)
- One input audio/media file → one transcript. Resolve the STT model + whisper.cpp CLI from `models.json`
  (`stt.whisper.base-en`, engine `whisper.cpp`, CUDA build preferred, CPU build fallback).
- **Input normalization** via `audio.ingest`: `-Normalize auto` (default) probes the input and only re-encodes
  when it is not already whisper-ready (WAV / 16000 Hz / mono / pcm_s16le); `always` forces it; `never` feeds the
  input straight to whisper (caller asserts it is ready).
- Run `whisper-cli.exe -ojf` (full JSON incl. per-token probabilities) + `-osrt` + `-otxt` (deliverable formats).
- Parse into **timestamped segments** `{index, t0_ms, t1_ms, t0, t1, text, confidence, token_count, low_confidence}`.
- **Confidence** = mean whisper per-token linear probability `p` over content tokens (per segment and overall);
  a real acoustic signal, not a completeness heuristic. Populate envelope `confidence` (overall) + per-segment.
- **`model_provenance`** = one entry (model id/version/engine/build/device, decode params, audio duration,
  segment/token counts, runtime, real-time factor, whisper systeminfo string).
- **Review-queue producer**: append one `lifeorch.review.item/0.1` per **low-confidence segment**
  (`confidence < -SegmentConfidenceThreshold`, default 0.5), bounded by `-MaxReviewSegments` (default 25, worst
  first); one `uncategorized` item if zero segments were produced from non-trivial-duration audio (silent-fail
  guard). `reason:"low_confidence"`, `flagged_by:"speech.stt"`, `requested:"verify_transcription"`,
  `source_ref:"artifact://<invDir>/transcript.json#seg<index>"`.
- Options: `-Language` (default `en`; base.en is English-only), `-Translate`, `-Threads`, `-NoGpu`,
  `-BeamSize`, `-BestOf`, `-MaxLen`, `-SplitOnWord`, `-OffsetMs`, `-DurationMs`.
- Standard contract surface: `-InputsJson` generic args, `$PSScriptRoot/runtime/artifacts/<id>/`, absolute
  artifact paths, envelope to stdout / diagnostics to stderr, exit 0 on any valid envelope.

### Non-goals (out — do NOT build)
- Trimming / segmentation / VAD-driven splitting / silence removal / diarization → Module 13 (`voice.live`) or
  a follow-on (whisper's own `--vad`/`-di` stay off in the MVP).
- Batch / directory transcription (one file per invocation; a batch mode mirrors the `audio.ingest` follow-on).
- Streaming / live transcription, word-karaoke video (`-owts`), translation quality tuning.
- Multilingual / language auto-detect beyond passing `-l` through (the staged model is `base.en`, monolingual).
- Wiring STT into `model.gateway` (the gateway MVP runs `type=llm` only; `stt.whisper.base-en` stays
  `wired:false` there — speech.stt reads the entry's `path`/`engine_candidates` itself). Do **not** flip that
  flag: Module 7's tests assert `model_not_wired` for it.
- A semantic/calibrated confidence (mean-token-`p` is honest but not calibrated; harden later).

### Dependencies
- Modules: 1 (`skill.bootstrap` contract + wrapper), 10 (`audio.ingest`, spawned as a child for normalization).
- Tools/models: `whisper.cpp` CLI (CUDA + CPU builds, verified via `m11-probe-001/002`); model
  `stt.whisper.base-en` (ggml, 0.14 GB); `ffmpeg`/`ffprobe` (via `audio.ingest` and for `auto` probe).
- Contract features: `confidence`, `model_provenance`, artifacts[], review-queue producer.

### Skill contract requirements
- `skill_id:"speech.stt"`, `name:"Speech-to-Text Transcription"`, `version:"0.1.0"`,
  `determinism:"mixed"`, `parallel_safe:false` (binds the CUDA context, like `model.gateway`),
  `batch:false`, `streaming:false`.
- Result `result` shape (below); `confidence` populated (null only when zero content tokens);
  `model_provenance` populated; artifact kinds: json / srt / text / markdown.

### Inputs and outputs
- **Inputs:** `input` (string, required), `normalize` (auto|always|never, def auto), `language` (def en),
  `translate` (bool), `threads` (int, def 4), `no_gpu` (bool), `beam_size` (int, def 5), `best_of` (int, def 5),
  `max_len` (int, def 0), `split_on_word` (bool), `offset_ms` (int, def 0), `duration_ms` (int, def 0),
  `segment_confidence_threshold` (def 0.5), `max_review_segments` (def 25), `model` (def stt.whisper.base-en),
  `registry`, `whisper_cli_path`, `audio_ingest_path`, `pwsh_path`, `review_queue_path`.
- **Outputs — `result`:**
  `{ input{path,exists,normalized,normalize_mode,source_probe}, audio{path,sample_rate,channels,duration_s},
     model{id,name,engine,engine_path,build,device,multilingual}, params{language,translate,beam_size,best_of,
     threads,no_gpu,max_len,split_on_word,offset_ms,duration_ms}, language, text, segment_count, token_count,
     confidence{overall,min_segment,low_confidence_segments}, segments[{index,t0_ms,t1_ms,t0,t1,text,confidence,
     token_count,low_confidence}], review{threshold,flagged_count,truncated,queue_path}, whisper{cli,systeminfo,
     runtime_ms,real_time_factor} }`

### Artifact structure
- `runtime/artifacts/<invocation_id>/`
  - `whisper.json` — raw whisper `-ojf` output (token-level; the source_ref target detail).
  - `whisper.srt`, `whisper.txt` — SubRip + plain text deliverables.
  - `transcript.json` — `lifeorch.stt.transcript/0.1` compact segments (+ per-seg confidence); primary structured out.
  - `transcript.md` — human summary (duration, language, segment table, low-conf markers).
  - `normalize/<id>/audio.wav` (+ audio.ingest artifacts) — only when normalization ran.
  - `result.json`, `stderr.txt`, `whisper.log`.

### Proposed implementation
- **Language:** PowerShell wrapping the whisper.cpp `whisper-cli.exe` (language policy: wrap the existing binary;
  mirrors `audio.ingest`). Reuse `audio.ingest`'s async `Invoke-Proc` (drains both child streams — avoids the
  pipe-fill deadlock) and its sibling-ffprobe resolution; mirror `classify.batch`'s child-`pwsh` spawn to call
  `audio.ingest`.
- Flow: merge `-InputsJson` → resolve model/CLI from `models.json` → resolve/normalize input (auto/always/never)
  → run `whisper-cli -ojf -osrt -otxt -of <base> -np -l <lang> [knobs]` via `Invoke-Proc` → parse `whisper.json`
  → build segments + confidence → write artifacts → append review items → emit envelope (exit 0).

### External tools or models
- whisper.cpp CLI — `F:\Local_TTS_Large_Data\external\whisper.cpp_cuda\build\bin\Release\whisper-cli.exe`
  (CUDA; CPU backup sibling). Both load headless (`m11-probe-001`), support `-oj/-ojf/-osrt/-otxt/-of/-np/-l/-ng`.
- Model — `stt.whisper.base-en` ggml at the staged `_pending-model-storage\stt\...\ggml-base.en.bin` (in `models.json`).

### Installation steps
- None to install — whisper.cpp + model already present and verified (probes `m11-probe-001/002`). Register the
  skill (and flip the model registry `notes`/add `defaults.stt`) in `TOOL_MODEL_REGISTRY.md` + `models.json`.

### Tests
- **Cloud pre-ship (off-machine):** pwsh 7.4.6 on the Linux box AST-parse-checks every `.ps1`; a mock harness
  feeds the **captured real `whisper.json`** (from `m11-probe-002`) through the parse/confidence/segment/
  review-write/envelope logic and asserts a schema-valid envelope — no GPU needed.
- **Direct + through the executor (Windows):** manifest validity; a **live** transcription of the bundled
  `samples\jfk.wav` (base.en, CUDA) → assert text contains "country", ≥1 segment with timestamps, overall
  confidence in (0,1], `model_provenance` populated, `whisper.json`/`.srt`/`.txt`/`transcript.json` artifacts
  with sha256; a forced low threshold (0.999) → review items appear; a `normalize always` path from a non-16k
  input (generated by ffmpeg) that runs `audio.ingest` first; error paths (`input_not_found`, `model/cli not
  found`); the Module 1 wrapper; no orphaned `whisper-cli`/`llama-server`.

### MVP acceptance criteria
- Schema-valid `lifeorch.skill.result/0.1` envelope with `determinism:"mixed"`, `confidence` populated,
  `model_provenance[1]`.
- Live jfk.wav transcript is correct (contains the JFK line), segments carry `t0/t1` + per-segment confidence.
- `whisper.json` + `whisper.srt` + `whisper.txt` + `transcript.json` + `transcript.md` produced, hashed.
- `normalize auto` feeds a whisper-ready WAV directly; `always` invokes `audio.ingest` and transcribes its output.
- Low-confidence segments append valid `lifeorch.review.item/0.1` records (`flagged_by:"speech.stt"`), bounded.
- All tests pass through the executor (exit 0); cloud pre-ship harness green first.

### Manual verification procedure
- Submit an executor task transcribing `samples\jfk.wav`; open `transcript.md` and confirm the line + timings;
  open `transcript.json` and confirm per-segment confidence; if a low threshold was set, confirm new
  `review_queue.jsonl` lines with `flagged_by:"speech.stt"`.

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `speech.stt` skill entry to `TOOL_MODEL_REGISTRY.md`; update the `stt.whisper.base-en` model row
  (last test date, "consumed by speech.stt"); add a whisper.cpp runtime line (verified). Add `defaults.stt`/
  `tiers.stt` to `models.json` (additive; leave the entry `wired:false` for the gateway).

### State updates
- Update `CURRENT_STATE.md` (Module 11 complete, active module none), `MODULE_ROADMAP.md` (#11 MVP complete),
  `REVIEW_QUEUE.md` (third producer wired), a new `DECISION_LOG.md` D-entry.

### Known follow-on work
- Batch/directory transcription; VAD/segmentation/diarization (→ Module 13); larger/multilingual models &
  a `tiers.stt`; calibrated/semantic confidence; word-level artifacts; a warm whisper-server worker if load
  latency dominates; wiring STT into a unified gateway if that consolidation is ever wanted.

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above.
- whisper.cpp CLI/model resolution fails and fixing it is non-trivial (stop, report).
- The contract lacks something this module needs (stop, propose the change, do not freelance).
- MVP acceptance is met — **stop; do not start Module 12.**
