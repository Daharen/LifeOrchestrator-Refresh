# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP build-out — **re-prioritized 2026-07-25 (D-0029)** to a usable-local-core-first order (see `MODULE_ROADMAP.md → Build priority`). Two build tracks: **Modules** (`modules/`, backend capability) and **Widgets** (`widgets/`, the human-interface layer); the full long-horizon destination is `ARCHITECTURE_MAP.md`.
- **Active module:** _none in progress._ **Modules 0–19 complete** (0 executor · 1 `skill.bootstrap` · 2
  `fs.observer` · 3 `proc.observer` · 4 `uia.inspector` · 5 `uia.actor` · 6 `capture.screen` · 7 `model.gateway` ·
  8 `classify.batch` · 9 `review.processor` · 10 `audio.ingest` · 11 `speech.stt` · 12 `speech.tts` · 13 `voice.live` ·
  14 `ocr.layout` · 15 `image.util` · 16 `detect.objects` · 17 `image.interpret` · 18 `image.index` · **19 `logic.escalator`**), plus **Module 00.1 — Executor Watchdog & Recovery (`exec.watchdog`)** (infrastructure). **The full
  audio track (10–13) is complete; the image/document perception block (14–18) is COMPLETE — Modules 14 `ocr.layout`,
  15 `image.util`, 16 `detect.objects`, 17 `image.interpret`, and 18 `image.index` (the fusion capstone) are all done.**
  **Module 8 — Batch Classification & Sorting (`classify.batch`) is MVP complete** — the **first real
  consumer of `model.gateway`**: for each item in a batch it calls the gateway (default `-Tier weak` = 1.5B) with a
  mode-specific prompt (`classify` one-label / `multilabel` / `extract` fields), parses the completion, computes a
  classification confidence (completeness+validity heuristic), groups the items, and routes below-threshold items to
  `review_queue.jsonl` (`flagged_by:"classify.batch"`; it **suppresses** the gateway's own review writes to keep the
  canonical queue correctly attributed). `determinism:"mixed"`, `batch:true`, `parallel_safe:false`. **Tests 33/33 via
  the executor** (`m8-test-001`, exit 0, ~26s). Note: **the review queue now has two producers** — `model.gateway` and
  `classify.batch`.
  **Module 9 — Review Queue Processor (`review.processor`) is MVP complete this session** — the **first consumer/
  drainer** of `review_queue.jsonl`. It selects OPEN items (bounded by `-MaxItems`; `-FlaggedBy`/`-Reason`/`-Ids`
  filters; both producers handled) and, per item, feeds a **stronger** local model (default `-Tier mid`=3B; `strong`=27B)
  via `model.gateway` **only** the distilled item — `reason`/`requested`/`weak_result` + a bounded fragment resolved
  from `source_ref` (classify.batch `classified.json#id` → the closed label set + that item; model.gateway
  `exchange.json` → bounded request/output) — **never the whole batch** (D-0007). It parses a small JSON verdict,
  computes a structural reviewer confidence, and either **resolves** the item (fills `resolution`+`status`) or
  **escalates** it (`status:"escalated"`, `escalated_to:"frontier"` — a status transition, NOT a frontier call) when
  unsure/unparseable/below `-EscalateThreshold`. Writes the live queue **in place** (re-read-before-atomic-replace;
  original flagging fields preserved; producer/malformed lines verbatim) **plus** an append-only `review_resolved.jsonl`
  (`lifeorch.review.resolution/0.1`); `-DryRun` writes nothing; suppresses the child gateway's own review writes.
  `determinism:"mixed"`, `batch:true`, `parallel_safe:false`. **Tests 34/34 via the executor** (`m9-test-003`, exit 0,
  ~150s incl. the 27B) — live `mid`(3B) resolve-in-place + history preservation + resolution log, forced escalation,
  `-DryRun` no-op, source-ref resolver, wrapper, and a live `strong`(27B) end-to-end at the **tuned `gpu_layers=32`**.
  Also **tuned the 27B** (`gpu_layers` 28→32; `model.gateway` now supports a `-LoadTimeoutSec` passthrough via
  `review.processor` for the slow strong tier — see REVIEW_QUEUE). See D-0018.
- **Module 10 — Audio Ingest / Normalize & Convert (`audio.ingest`) is MVP complete this session** — the
  **first module of the audio track (10–13)** and the first skill to **wrap an external executable**
  (`ffmpeg`/`ffprobe`). It normalizes+converts one audio/media file (first audio stream; audio extracted from
  video via `-vn -map 0:a:0`) to a requested `-Format` (wav/mp3/flac/opus/ogg/m4a) + `-SampleRate` + `-Channels`
  + `-SampleFormat` (wav) with optional `-Loudness` (`none` / `peak` two-pass volumedetect→gain / `ebu` R128
  loudnorm). **Defaults = whisper-ready 16 kHz mono s16 WAV**, so Module 11 (`speech.stt`) consumes its output
  directly. `ffmpeg` resolved from `-FfmpegPath`→PATH→known dirs; **`ffprobe` resolved as the sibling of the
  resolved `ffmpeg`** (dodges the Python `Scripts\ffprobe.exe` shim that shadows the real one on PATH — confirmed:
  it picked `…\WinGet\Links\ffprobe.exe`). `determinism:"deterministic"` (confidence null), `parallel_safe:true`,
  `batch:false`. Artifacts `audio.<ext>`/`ingest.json`/`ingest.md`. **Tests 43/43 via the executor** (`m10-test-001`,
  exit 0, ~17s) — real conversions across all six formats (codec + magic-byte verified), keep-source, EBU + peak
  loudness, five error paths, and the Module 1 wrapper; a smoke run (`m10-smoke-001`) produced a real 16 kHz mono
  s16 WAV. **Pre-shipped off-machine**: pwsh 7.4.6 on the cloud Linux box AST-parse-checked both scripts and ran the
  *same* portable harness against cloud ffmpeg 6.1 (43/43) before any bytes hit Windows. See D-0019.
  **Module 11 — Speech-to-Text Transcription (`speech.stt`) is MVP complete this session** — the **second audio-track
  module** and the **first stochastic/mixed skill to wrap a local model binary** (whisper.cpp `whisper-cli`, vs. Module
  7's server). **Probe-first** (`m11-probe-001/002`): confirmed this build's exact flags + JSON before writing code — both
  CUDA + CPU builds load headless (CUDA sees the RTX 2080 Ti) and support `-oj/-ojf/-osrt/-otxt/-of/-np/-l/-ng`. It
  resolves the model (`stt.whisper.base-en`) + CLI (CUDA preferred, CPU fallback) from `models.json`; **normalizes input
  via `audio.ingest`** (`-Normalize auto|always|never` — `auto` re-encodes only when not already WAV/16 kHz/mono/s16,
  spawning Module 10 as a child `pwsh`); runs `whisper-cli -ojf` and parses timestamped segments. **Confidence = mean
  whisper token probability `p`** over content tokens (special tokens excluded), per-segment + overall → populates
  `confidence` + `model_provenance`; **third review-queue producer** — flags low-confidence segments
  (`flagged_by:"speech.stt"`, `requested:"verify_transcription"`, bounded by `-MaxReviewSegments`=25; a `verify_no_speech`
  item guards silent failures). `determinism:"mixed"`, `parallel_safe:false` (binds CUDA), `batch:false`. Artifacts
  `whisper.json`/`.srt`/`.txt` + `transcript.json`/`.md`. **Tests 27/27 via the executor** (`m11-test-001`, exit 0, ~14 s)
  — live jfk.wav transcription (base.en on CUDA, rtf ≈ 0.07, confidence 0.8707), per-segment confidence, review routing,
  both normalization branches (real `audio.ingest` child), error paths, and the Module 1 wrapper; live smoke
  `m11-smoke-001` transcribed jfk.wav on CUDA (`device=cuda:0`). **Pre-shipped off-machine**: pwsh 7.4.6 on the cloud
  Linux box AST-parse-checked all three `.ps1` and ran the *real* skill against a mock `whisper-cli` + a **captured real
  jfk fixture** (27/27) before any bytes hit Windows. `models.json` gained `defaults.stt`/`tiers.stt` (additive; Module 7
  re-verified 28/28). See D-0020.
  **Module 12 — Text-to-Speech Synthesis (`speech.tts`) is MVP complete this session** — the **third audio-track module**
  and the **first skill to drive a Python model** (Qwen3-TTS CustomVoice via the `qwen_tts` package, vs. the whisper.cpp/
  llama.cpp binaries). **Probe-first** (`m12-probe-001/002`): confirmed the speech venv (torch 2.11+cu128, transformers
  4.57.3, `qwen_tts`, CUDA on the RTX 2080 Ti) and the real inference API by doing a **live synthesis** before coding —
  `qwen_tts.Qwen3TTSModel.generate_custom_voice(text, speaker, language, instruct)` → `(wavs, sr=24000)`, loaded bf16 +
  `sdpa` (flash-attn absent). A **Python worker** (`tts_infer.py`, under the venv) loads+synthesizes and writes a WAV +
  meta file; a **PowerShell wrapper** (`Invoke-SpeechTts.ps1`) reads the **meta file** (robust to ML-library stdout
  chatter) and builds the envelope. Produces 24 kHz mono PCM16 `speech.wav`; optional `-Format`/`-SampleRate` via a
  child `audio.ingest`. Registry-driven (`tts.weak.qwen3-0p6b` default / `tts.strong.qwen3-1p7b`; engine `transformers`,
  `engine_env`=venv python). **Confidence** = a synthesis-completeness heuristic (duration vs. input length);
  **fourth review-queue producer** (flags failed/too-short synthesis, `verify_synthesis`). `determinism:"mixed"`,
  `parallel_safe:false` (binds CUDA), `batch:false`. Artifacts `speech.wav` + `tts.json`/`tts.md`. **Tests 25/25 via the
  executor** (`m12-test-001`, exit 0, ~132 s) — live English synthesis (speaker Ryan, 24 kHz mono, conf 0.9), review
  routing, mp3 conversion via the real `audio.ingest` child, error paths, Module 1 wrapper; live smoke `m12-smoke-001`
  synthesized 5.52 s on CUDA (`device=cuda:0`, rtf ≈ 5.2). **Pre-shipped off-machine**: pwsh 7.4.6 AST-parse + `py_compile`,
  then the *real* skill against a stdlib mock python worker (25/25) before any bytes hit Windows. `models.json` gained
  `defaults.tts`/`tiers.tts` (additive; Module 7 re-verified 28/28). See D-0021.
  **Module 13 — Voice Interaction Loop (`voice.live`) is MVP complete this session** — the **capstone of the audio track
  (10–13)** and the **first skill to compose several stochastic model skills end-to-end**. Given one input speech file it
  runs a voice turn: **`speech.stt`** transcribes (whisper segments = utterance/VAD) → optional **`model.gateway`** answer
  (`-Respond`) → optional **`speech.tts`** reply to `reply.wav` (`-Speak`/`-ReadbackTranscript`). Children are spawned as
  child pwsh with **overridable paths** and their `lifeorch.skill.result/0.1` envelopes parsed — **it reimplements
  nothing** (the payoff of the shared contract: a local voice assistant turn is pure orchestration). Envelope
  `confidence` = the STT transcript confidence; `model_provenance` = the **aggregate** of all child models (stage-tagged).
  **Orchestrator, not a review producer** — it redirects children's review writes to an in-artifact `child_review.jsonl`
  by default (canonical queue unchanged). `determinism:"mixed"`, `parallel_safe:false`, `batch:false`; **no new model /
  no `models.json` change.** **Live mic capture / streaming is a non-goal** (no mic assumed; file-driven MVP); standalone
  VAD deferred (whisper VAD tool exists but no VAD ggml model is staged — `m13-probe-001`). **Tests 21/21 via the
  executor** (`m13-test-001`, exit 0) — a live full turn on `samples\jfk.wav` (transcript "…country…" → LLM answer →
  `reply.wav`, `model_provenance` ≥ 3, all stages ok), readback, error path, Module 1 wrapper; live smoke
  `m13-smoke-001` heard the JFK line, answered via the 1.5B, and produced a 12.56 s reply (stt 1.8 s / respond 2.7 s /
  speak 54 s). **Pre-shipped off-machine** on cloud pwsh 7.4.6 with a mock-children harness driving the *real*
  orchestrator (23/23). See D-0022.
- **Module 14 — OCR + Layout (`ocr.layout`) is MVP complete this session** — the **first module of the image/document
  perception block (14–18)** and the first **parallel-safe** stochastic/mixed perception skill. It recognizes the text in
  one image and returns it with **per-word pixel bounding boxes + lines in reading order** (+ text angle, image dims).
  **Probe-first** (`m14-probe-001`; do not assume an OCR engine): the system **`Windows.Media.Ocr`** engine works — zero
  install, native, `en-US` recognizer, `MaxImageDimension=10000` — OCR'ing a generated fixture to "HELLO WORLD The quick
  brown fox 12345" (100% correct incl. digits) with word boxes + line grouping + `TextAngle` in ~74 ms. Crucially **pwsh
  7.4.6 cannot load the WinRT projection** here, so OCR runs in a **Windows PowerShell 5.1 worker** (`ocr_worker.ps1`, the
  `AsTask`/`Await` reflection pattern) with a **meta-file hand-off** to the pwsh-7 wrapper (`Invoke-OcrLayout.ps1`) — the
  D-0021 worker+meta pattern in its PS-5.1 variant. **Registry-driven, decoupled from the gateway `wired` gate** (D-0020):
  resolves `ocr.windows.media` (type `ocr`) from `models.json`, which stays `wired:false` for the gateway. **Confidence** =
  a documented **legibility heuristic** (Windows.Media.Ocr exposes no per-word confidence); **fifth review-queue producer**
  (`flagged_by:"ocr.layout"`, page-level `verify_ocr` / `verify_no_text` guard). **Composes `capture.screen` (M6)** via
  `-Capture` to OCR the live screen. `determinism:"mixed"`, `parallel_safe:true`, `batch:false`. Artifacts
  `ocr.json`/`ocr.md`. **Tests 30/30 via the executor** (`m14-test-003`, exit 0) — live OCR (words+boxes+reading order),
  review routing, no-text guard, error paths, Module 1 wrapper, **and the live `capture.screen` composition**; real-registry
  smoke `m14-smoke-001` (7 words, conf 0.9, correct text); no orphaned processes. **Pre-shipped off-machine**: cloud pwsh
  7.4.6 AST-parse + a mock-worker harness driving the *real* wrapper against a **captured real meta** (28/28) before any
  bytes hit Windows. `models.json` gained `defaults.ocr`/`tiers.ocr` + `ocr.windows.media` (default) / `ocr.tesseract`
  (declared) — **additive; Module 7 re-verified 28/28** (`m14-final-001`). **Tesseract is installed** (`C:\Program
  Files\Tesseract-OCR\`) and declared as a future second engine. See D-0023.
- **Module 15 — Image Utilities (`image.util`) is MVP complete this session** — the **second module of the image/document
  perception block (14–18)** and the **first deterministic perception skill** (like `audio.ingest`/`fs.observer`:
  `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`, **not** a review-queue producer). One image
  in -> metadata + hashes always, plus one optional op: **resize** (fit/fill/exact or a single `max_dimension`, reporting
  `scale_x`/`scale_y`), **crop** (pixel rect / normalized 0..1 / named region), **convert** (png/jpg/webp/bmp/tiff +
  quality; alpha flattened to white where unsupported), **tile** (grid or fixed size + overlap, bounded to 400), and
  **similarity** (pHash/dHash Hamming distance + score vs a second image). Metadata = format/mode/dims/has_alpha/dpi/
  n_frames/EXIF-lite; hashes = **sha256** (exact) + a DCT **pHash** + **dHash** (64-bit, deterministic and **stable across
  Pillow/numpy versions** — `m15-probe-001`). **Probe-first** (`m15-probe-001`): the **system python**
  (`…\Python312\python.exe`, PIL 10.2.0 + numpy 1.26.4) round-trips all five formats + LANCZOS + EXIF + a numpy-DCT pHash;
  chosen over the speech venv (PIL 12.2) because it is CPU-only (so genuinely `parallel_safe`, no CUDA/venv binding) and
  not tied to the speech stack. Implemented as a **Pillow+numpy Python worker** (`image_worker.py`) + a **pwsh-7 wrapper**
  (`Invoke-ImageUtil.ps1`) with a **meta-file hand-off** (the D-0021 worker+meta pattern in its deterministic variant).
  **NOT a `model.gateway` model — no `models.json` change, no Module 7 re-verify** (a tool, like ffmpeg for `audio.ingest`).
  `parallel_safe:true`, `batch:false`. Artifacts `image.json`/`image.md` + produced image file(s). **Tests 48/48 via the
  executor** (`m15-test-001`, exit 0) — manifest, meta+hashes, resize fit/fill/exact + `max_dimension` scale factors, crop
  rect/normalized/region, convert to all five formats, tile grid + fixed-size, similarity self/near-dup/different, six
  error paths, and the Module 1 wrapper; no orphaned processes; shipped-file sha256 verified byte-exact on disk.
  **Pre-shipped off-machine**: because Pillow is portable AND version-stable (unlike the WinRT/CUDA engines that forced
  mock workers in M11/12/14), the harness ran the **real** worker on the cloud Linux box (pwsh 7.4.6 + cloud python +
  Pillow 12.2, 48/48) as the pre-ship gate — the same real-engine-on-cloud gate as `audio.ingest`. Directly unblocks two
  `ocr.layout` follow-ons (documented, not built here): `MaxImageDimension` downscale-then-rescale-boxes, and a box-overlay
  PNG. See D-0024.
- **Module 16 — Object Detection (`detect.objects`) is MVP complete this session** — the **third module of the image/document
  perception block (14–18)** and the **first onnxruntime-backed** stochastic/mixed perception skill; **parallel-safe** (default
  CPU provider, no port/VRAM/CUDA binding). One image in -> `detections[{index,class_id,class,score,low_confidence,
  box{x,y,width,height}}]` with a **REAL per-detection confidence** (YOLOX objectness x class prob — not a heuristic), plus
  overall/mean/min and a `class_summary`. Runs a staged **ONNX** detector (default `detect.yolox.nano`, COCO-80, Apache-2.0,
  ~3.66 MB, staged to F:) via **onnxruntime** in a **Python worker** (`detect_worker.py`, letterbox-416 -> decode strides
  {8,16,32} -> obj*cls -> class-aware NMS -> boxes in original pixels) under the **system python** + a **pwsh-7 wrapper**
  (`Invoke-DetectObjects.ps1`) with a **meta-file hand-off** (the D-0021 pattern in its ONNX variant). **Registry-driven,
  decoupled from the gateway `wired` gate** (D-0020/D-0023): resolves `detect.yolox.nano` (type `detector`) from `models.json`,
  which stays `wired:false` for the gateway. **Confidence** = the best detection's real score (0.1 sentinel when empty);
  **sixth review-queue producer** (`flagged_by:"detect.objects"`; below-threshold best score -> `verify_detections`; zero
  objects on a non-empty image -> `verify_no_objects`). **Composes `capture.screen` (M6)** via `-Capture` and **`image.util`
  (M15)** via `-MaxDimension` (downscale-then-rescale-boxes). `determinism:"mixed"`, `parallel_safe:true` (CPU default;
  `-Provider cuda|dml` is not), `batch:false`. Artifacts `detect.json`/`detect.md`. **Probe-first** (`m16-probe-001`): no
  detector was staged; picked a staged ONNX YOLOX via onnxruntime (system python has onnxruntime-gpu 1.17.1) over a torch/venv
  model — staged the model to F: (sha256 byte-exact) and confirmed **live CPU inference** reproducing the cloud detections
  exactly (dog/car/bicycle). **Tests 38/38 via the executor** (`m16-test-001`, exit 0) — live detection (boxes+scores+classes),
  class filter, both review paths, the **image.util downscale** + live **capture.screen** compositions, five error paths, and
  the Module 1 wrapper; real-registry smoke (default nano from F:); no orphaned processes; shipped-file sha256 verified
  byte-exact (13 files). **Pre-shipped off-machine**: because onnxruntime CPU inference is deterministic + portable, the
  harness ran the **real** worker on the cloud Linux box (onnxruntime 1.25, 34/34) as the pre-ship gate — the same
  real-engine-on-cloud gate as `image.util`. `models.json` gained `defaults.detector`/`tiers.detector` +
  `detect.yolox.nano`/`detect.yolox.tiny` (additive; **Module 7 re-verified 28/28**). **Side fix:** composing `image.util` on
  a real JPEG surfaced + fixed a latent Module 15 bug (JPEG `dpi` `IFDRational` was not JSON-serializable and truncated the
  worker meta; `image_worker.py` now coerces `dpi` to float) — **Module 15 re-verified 48/48**, no regression. See D-0025.
- **Module 17 — Image Interpretation (`image.interpret`) is MVP complete this session** — the **fourth module of the
  image/document perception block (14–18)** and the block's first **semantic/free-text** perception skill; the **first skill to
  drive a local VLM**. One image (+ an optional prompt) in -> a free-text `interpretation.text` (modes `caption`/`describe`/
  `vqa`/`screen`). **Probe-first** (`m17-probe-001/002/003`; no VLM was staged): confirmed the already-staged llama.cpp
  **`llama-server` (b8661) has full multimodal support** (`--mmproj`/mtmd/`--image-max-tokens`), chose it over a transformers
  VLM in the speech venv (also viable, heavier) / an ONNX VLM, then **downloaded + staged** `vlm.qwen2p5-vl-3b`
  (Qwen2.5-VL-3B-Instruct GGUF Q4_K_M ~1.8 GB + `mmproj-f16` ~1.3 GB, Apache-2.0, from `ggml-org/...-GGUF`) to F: and
  **live-verified** an accurate `dog.jpg` caption at ~111 tok/s (full GPU offload). Implemented as a **pure-PowerShell wrapper**
  (`Invoke-ImageInterpret.ps1`, **no python worker**): base64-encodes the image, reuses `model.gateway`'s `llama-server`
  lifecycle (free-port -> `Start-Process` w/ redirected logs -> `/health` -> `/v1/chat/completions` with an OpenAI-style
  `image_url` data URI -> synchronous `taskkill`+`WaitForExit` teardown). **Registry-driven, decoupled from the gateway `wired`
  gate** (D-0020/D-0023/D-0025): resolves `vlm.qwen2p5-vl-3b` (type `vlm`) from `models.json`, which stays `wired:false` for
  the gateway. **Confidence** = a documented completeness+refusal+non-empty heuristic (stop 0.7 / length 0.4 / refusal 0.3 /
  empty 0.1); **seventh review-queue producer** (`flagged_by:"image.interpret"`, `verify_interpretation`; reason
  `low_confidence`/`needs_strong_review`(refusal)/`failed_transform`(empty)). **Composes `capture.screen` (#6)** via `-Capture`
  ("interpret my screen") and **`image.util` (#15)** via `-MaxDimension` (downscale before sending). `determinism:"mixed"`,
  **`parallel_safe:false`** (binds a loopback port + CUDA/VRAM — unlike the parallel-safe #14–16), `batch:false`. Artifacts
  `interpret.json`/`interpret.md`. **Tests 48/48 via the executor** (`m17-test-001/002`, exit 0) — seam tests (a **captured-real
  llama-server response**) + real VLM describe/VQA (device `cuda:0`, conf 0.7) + the **image.util downscale** + the live
  **capture.screen** compositions + all three review paths + error paths + the Module 1 wrapper; no orphaned `llama-server`;
  13 shipped files sha256-verified byte-exact. **Pre-shipped off-machine**: because a VLM's real weights can't run on the Linux
  cloud box, the harness ran the **real** wrapper against a captured-real response seam (+ the real `image.util` downscale)
  on the cloud box (40/40) as the pre-ship gate. `models.json` gained `defaults.vlm`/`tiers.vlm` + `vlm.qwen2p5-vl-3b`
  (additive; **Module 7 re-verified 28/28**). See D-0026.
- **Module 18 — Image Index (`image.index`) is MVP complete this session** — the **capstone of the image/document
  perception block (14–18)** and the **second skill to compose several stochastic perception skills end-to-end** (after
  `voice.live` #13 for audio). Given one image it fuses the perception children into a single per-image record: **`image.util`
  (#15) ALWAYS** (metadata + `sha256`/`pHash`/`dHash` — the deterministic backbone), plus optional **`ocr.layout` (#14, `-Ocr`)**
  text + boxes, **`detect.objects` (#16, `-Detect`)** class boxes + scores, and **`image.interpret` (#17, `-Interpret`)** a VLM
  free-text interpretation; **`-All`** runs the three, **`-Capture`** sources the image **once** via `capture.screen` (#6), and
  **`-MaxDimension`** is passed through to detect + interpret. It is an **orchestrator** and **reimplements nothing**: it spawns
  each child as a child pwsh, parses its `lifeorch.skill.result/0.1` envelope, **aggregates every child's `model_provenance`
  (stage-tagged)**, and runs the children **sequentially** (capture → image.util → ocr → detect → interpret) to avoid the VLM's
  VRAM/loopback-port contention. **Orchestrator, NOT a review producer** (like #13): it **redirects** children's review-queue
  writes to an in-artifact **`child_review.jsonl`** and does **not** re-flag — so the **review-queue producer set stays at seven**
  and the canonical `review_queue.jsonl` is untouched. Envelope `confidence` = the **minimum** confidence across the stochastic
  stages that ran (the weakest-link signal; `null` when only image.util ran); `determinism:"mixed"`, **`parallel_safe:false`**
  (can bind CUDA/VRAM + a port via `-Interpret`), `batch:false`. Artifacts `index.json` (machine) + `index.md` (human per-image
  card). **No new model / no `models.json` change / no Module 7 re-verify** (it composes existing skills; a pure orchestrator).
  **Tests 41/41 via the executor** (`m18-test-002`, exit 0, ~44 s) — live full index on `dog.jpg` (image.util meta+hashes +
  OCR + 5 detections + a real VLM description, `model_provenance` = 3 stage-tagged, min-confidence fusion), the default
  image.util-only path, selective/`-All`/error paths, the child-review **redirect** with the **canonical queue verified
  untouched (0→0)**, the Module 1 wrapper, and **no orphaned `llama-server`/python**; shipped-file sha256 byte-exact (9 files).
  **Pre-shipped off-machine**: cloud pwsh 7.4.6 AST-parse + a **mock-children** harness (`tests/mock-child.ps1` branching on the
  `-ArtifactRoot` leaf) driving the **real** orchestrator (40/40) — the M13 mock-children gate, since #17's VLM can't run on the
  cloud box. See D-0027.
- **Module 19 — Local Logic Escalator (`logic.escalator`) is MVP complete this session** — **Phase A #1 (D-0029)**, the
  cost-offload keystone and the first Phase-A build. A **new module composing `model.gateway` (#7)** across its wired LLM
  tiers (`tiny`=0.5B → `weak`=1.5B → `mid`=3B → `strong`=27B) — it **reimplements nothing** (spawns the gateway as a child,
  parses its `lifeorch.skill.result/0.1` envelope, reuses the #8/#9 child-spawn scaffolding). **The escalating ladder:** the
  weakest tier answers; each higher tier **judges** the current answer and either ACCEPTs it (stop — the accepted layer is the
  tier that produced the current answer) or produces its own answer for the next tier; the top tier's answer is accepted if
  reached. **Every rung is anchored with deterministic ground-truth gates** (guardrail 1, D-0029): classify = in-set membership
  (hard) + self-consistency across K samples; extract = JSON-schema validity + all-fields-present (hard) + source-grounding;
  generic = ungated + self-consistency. **A hard-fail overrides an LLM-judge ACCEPT** (the anti-rubber-stamp defense) and
  **strong self-consistency + hard-pass short-circuits to accept with no judge call** (the cost saver). **Orchestrator, NOT a
  review-queue producer** (like #13/#18): it suppresses the child gateway's review writes to an in-artifact file and surfaces
  `needs_frontier` per task in its own result — the canonical `review_queue.jsonl` is untouched and the producer set stays at
  seven. `determinism:"mixed"`, `parallel_safe:false`, `batch:true`, `streaming:false`; **no new model / no `models.json`
  change / no Module 7 re-verify** (it composes the four already-wired tiers). **Tests 24/24 mock (cloud pre-ship gate on pwsh
  7.4.6) + 28/28 with `-Live` via the executor** (`m19-test-001`, exit 0, no orphaned `llama-server`) — the mock scenarios prove
  the short-circuit, escalate-and-resolve, the deterministic in-set gate overriding a judge ACCEPT, needs_frontier, and the
  child-review suppression. **Empirically calibrated via the executor** (guardrail 2 — the experiment, run not assumed;
  `m19-calib-002/003`): on a labeled closed-set eval, the 3-tier ladder `[tiny,weak,mid]` K=1 reaches **78.6% accuracy at 2.86
  params_b-weighted cost/item (−89% vs always-strong)**, resolve distribution tiny 10 / mid 4, **false-approval rate 0.20** (the
  weak 1.5B judge rubber-stamps 2 in-set-but-wrong tiny answers — the exact D-0029 failure mode, now measured); the 4-tier
  ladder `[+strong]` K=1 **drops to 57.1%** because the thinking-style 27B emits **empty verdicts at the MVP token caps** (the
  D-0018 issue, confirmed here) → those 4 escalated items degrade to flagged `needs_frontier` (fail-safe, NOT false approvals).
  **It does NOT reach the ~95% target** with the naive K=1 config (said plainly); the always-mid baseline (92.9%) shows the
  capability exists. Measured, prioritized follow-ons: raise strong-tier `max_tokens` / add a no-reasoning directive; a
  self-consistency **veto** + skeptical judges to cut the 0.20 false-approval; a higher floor / cost-aware early-stop;
  live-calibrate K>1. Full numbers in `modules/19-logic-escalator/CALIBRATION.md` (+ `runtime/calibration/`). See **D-0030**.
- **Repo / working dir:** **`C:\Users\just_\LifeOrchestrator-Refresh\`** — the clean standalone home for
  **Life Orchestrator** (near-term local-skills track; git-initialized). Layout: `core-docs/` (these docs)
  and `modules/<NN>-<name>/` (one per module). **Reference sources (separate, not built here):** the earlier
  assistant codebase `LifeOrchestrator\repo` (fold in later) and the separate **Project Proteus** game
  (`Project-Proteus-src`).
- **Executor status:** MVP complete, **running.** **Canonical instance:** the Life Orchestrator executor at
  `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (pwsh 7.4.6, host `DESKTOP-PF5FFMF`). It crashed
  once mid-session (2026-07-24T06:26:36Z, instance `0a1f8e69…`, transient file-lock — see Known failures), was
  **restarted** and is now instance `857d7251…` (up 13:52Z); restart recovery correctly marked the orphaned
  `m5-example-001` as `abandoned_after_restart`. The original at `proteus_repo/tools/trusted-bootstrap-executor/`
  was stopped earlier; the physical `proteus_repo/tools/` leftover was **removed 2026-07-25** (housekeeping D-0028;
  `proteus_repo` itself untouched). **Now covered by the watchdog (Module 00.1):** launch `ops/start-watchdog.bat`
  for unattended resilience — it auto-restarts the executor on crash/hang and stands down on a graceful stop.
  **The live executor was restarted onto the marker code and is now instance `51061264…` (pid 4844), emitting
  `control/heartbeat.json`/`last-exit.json` (heartbeat fresh 2026-07-24T17:26Z; it has since run the Module 7 and
  Module 8 tasks — `m8-smoke-001`/`m8-test-001`, both `completed` exit 0). The earlier "restart it once" action is resolved.**

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.
- **Module 1** — Skill Contract & Registry Bootstrap (`skill.bootstrap`). Reference skill `ref.echo`,
  contract validators (`lib/SkillContract.psm1`), and a generic wrapper (`Invoke-Skill.ps1`). Runs directly
  and through the executor; emits schema-valid `lifeorch.skill.result/0.1`. Module tests 11/11 (2026-07-24).
- **Module 2** — Filesystem Observer (`fs.observer`). Deterministic depth-bounded tree + name/glob search;
  `tree.md` + `index.json` artifacts; contract-valid envelope; runs direct/wrapped/executor. Tests 16/16 (2026-07-24).
- **Module 3** — Process & Window Observer (`proc.observer`). Snapshot of processes + top-level windows +
  foreground (Win32); `report.md` + `processes.json` + `windows.json`. Tests 16/16 (2026-07-24).
- **Module 4** — UI Automation Inspector (`uia.inspector`). Read-only UIA control-tree walk of a target
  window/desktop (control type, name, automation id, bounds, patterns, state); `tree.md` + `elements.json`. Tests 16/16 (2026-07-24).
- **Module 5** — UI Automation Actor (`uia.actor`). **Acting** half of UIA: invoke/toggle/select/expand/
  collapse/setvalue/focus on an element located by automation id / name / control type / inspector child-path.
  UIA control patterns only (no synthetic input); `-DryRun`/`-WhatIf` preview; `parallel_safe:false` (first
  side-effecting skill). `action.md` + `action.json` artifacts. **Tests 26/26 via executor (2026-07-24)** —
  incl. real invoke/toggle/setvalue self-verified against a self-contained WinForms probe window. Committed `1691d16`.
- **Module 6** — Screenshot & Region Capture (`capture.screen`). **Visual-capture** complement to the UIA
  skills: resolve a target (monitor `index|all|primary` / window by hwnd|pid|title / app by process name /
  explicit rectangle) to one virtual-desktop rectangle, then GDI `CopyFromScreen` → **PNG** (or JPG q90) image
  artifact + `capture.json`/`capture.md`. Read-only (`parallel_safe:true`, `screen:true`), Per-Monitor-V2 DPI
  aware, multi-monitor. **Tests 39/39 via executor (2026-07-24)** — monitor(primary/all), region(png+jpg),
  window (self-verified against a WinForms probe), all error paths, wrapper; smoke `m6-smoke-001` captured a
  real dual-monitor primary (1920×1080).
- **Module 00.1** — Executor Watchdog & Recovery (`exec.watchdog`). **Cooperative** supervisor: autonomously
  restarts the executor on crash/hang (no approval), stands down on an authorized graceful stop; on-demand
  `Recover-Executor.ps1 -Force`. Not perpetual, no boot persistence, visible + self-killable (D-0013, honors
  D-0001). Adds `heartbeat.json`/`last-exit.json` to Module 0 (additive; 12/12 unaffected). Tests 22/22 (2026-07-24).
- **Module 7** — Local Model Gateway (`model.gateway`). Common interface that runs local **LLMs** (GGUF) via the
  llama.cpp **`llama-server`** (start → `/health` → `/v1/chat/completions` → kill), model chosen from a declarative
  `models.json` by `-Model` id / `-Tier` alias (tiny/weak/mid/strong) / default. Declares STT/TTS/embedding (staged;
  `model_not_wired` until Modules 11/12/23). **First stochastic/mixed skill:** populates `model_provenance` (tokens/
  timings/finish_reason/device) + a generation-completeness `confidence` (stop→0.7, length→0.4, empty→0.1; `<0.5` →
  `review_queue.jsonl`). `parallel_safe:false`. Artifacts `output.txt`/`exchange.json`. **Tests 28/28 via executor
  (2026-07-24)** — live gen on staged 0.5B/1.5B, truncation→review-queue, error paths, wrapper, clean server teardown.
  See D-0015 (large-data), D-0016 (gateway design).
- **Module 8** — Batch Classification & Sorting (`classify.batch`). **First real consumer of `model.gateway`.** Three
  modes over a list of `{id?,text}` items: `classify` (exactly one label from a closed set — also routing/sorting),
  `multilabel` (zero+ labels), `extract` (named fields → JSON). Calls the gateway **once per item** (`-Tier weak`
  default) with a mode-specific prompt at temp 0 / fixed seed; parses the completion; computes a per-item
  classification **confidence** (documented completeness+validity heuristic, NOT calibrated — classify: in-set+stop
  0.8 / fuzzy 0.6 / out-of-set 0.2; multilabel 0.75/0.7/0.5/0.15; extract 0.75/0.5/0.3/0.1; `length` caps ≤0.4);
  groups items (`label→[ids]`); appends below-threshold items (default 0.5) to `review_queue.jsonl` as
  `lifeorch.review.item/0.1` `flagged_by:"classify.batch"` with per-item `source_ref`. **Suppresses the gateway's own
  review writes** to an in-artifact `_gateway_review_suppressed.jsonl`. Envelope `confidence` = mean per-item;
  `model_provenance[]` = one aggregate entry (summed tokens, call count, total runtime). `determinism:"mixed"`,
  `batch:true`, `parallel_safe:false`. Artifacts `classified.json`/`classified.md`. **Tests 33/33 via executor
  (2026-07-24)** — five error paths, live classify(0.5B)/extract, explicit-model(1.5B) resolve, review routing +
  gateway suppression, wrapper, no orphaned `llama-server`; smoke `m8-smoke-001` labeled animal/vehicle correctly.
  See D-0017. **Throughput caveat:** one gateway call per item × per-call model load (D-0002/D-0016) — fine for
  small/unattended batches; warm-worker/intra-batch-prompt is a follow-on.
- **Module 9** — Review Queue Processor (`review.processor`). **First consumer/drainer of the review queue.** Selects
  OPEN items (bounded `-MaxItems`; `-FlaggedBy`/`-Reason`/`-Ids` filters; both `flagged_by` producers) and adjudicates
  each **single** item with a **stronger** local model (default `-Tier mid`=3B; `strong`=27B) via `model.gateway`,
  consuming only `reason`/`requested`/`weak_result` + a bounded `source_ref` fragment — **not** the whole batch (D-0007).
  Parses a JSON verdict → **resolves** (`resolution`+`status`) or **escalates** (`escalated_to:"frontier"` — a status
  transition, not a frontier call). Writes the live queue **in place** (re-read-before-atomic-replace; original flagging
  fields preserved; producer/malformed lines verbatim) **plus** an append-only `review_resolved.jsonl`
  (`lifeorch.review.resolution/0.1`); `-DryRun` writes nothing; suppresses the child gateway's own review writes;
  `-LoadTimeoutSec` passthrough for the slow strong tier. `determinism:"mixed"`, `batch:true`, `parallel_safe:false`.
  **Tests 34/34 via the executor (2026-07-24, `m9-test-003`, exit 0)** incl. live `mid`(3B) and a live `strong`(27B)
  end-to-end at the tuned `gpu_layers=32`; a cloud-only mock-gateway harness validated the select/parse/adjudicate/
  queue-rewrite/escalation logic off-GPU first. **Tuned the 27B `gpu_layers` 28→32** (see REVIEW_QUEUE). See D-0018.

## Installed dependencies (verified this machine)
- **PowerShell 7.4.6** — installed as a .NET global tool at
  `C:\Users\just_\.dotnet\tools\pwsh.exe`. (Was **not** present before; installed 2026-07-24.)
- **.NET SDK 9.0.100** — `C:\Program Files\dotnet\dotnet.exe`.
- **git** — on PATH. **winget** — present (user WindowsApps). **choco** — not installed.
- **ffmpeg / ffprobe 8.1** (Gyan.dev `full_build`) — `ffmpeg` on PATH at
  `C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe` (WinGet `Gyan.FFmpeg`); full encoder set
  (libmp3lame, aac, flac, libopus, libvorbis, pcm_*). **Gotcha:** `ffprobe` on PATH resolves *first* to a Python
  `…\Python310\Scripts\ffprobe.exe` shim — resolve the real one as the **sibling of `ffmpeg`**. Verified
  2026-07-24 (`m10-ffprobe-001`); used by Module 10.
- **WinForms + STA runspace** work in the dotnet-tool pwsh (`System.Windows.Forms` loads; an STA runspace
  can host a Form + `Application.Run`) — verified 2026-07-24 (used by the Module 5 probe test).
- **Windows PowerShell 5.1** (`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`, 5.1.19041.6456) — present
  alongside pwsh 7. **The only runtime that can load the WinRT `Windows.Media.Ocr` projection on this box** (pwsh 7.4.6
  cannot — `m14-probe-001`). Used by `ocr.layout` (Module 14) as a worker. **Gotcha:** 5.1 reads a BOM-less `.ps1` as
  ANSI, not UTF-8 — keep any 5.1 worker **ASCII-only** (a UTF-8 em dash broke `ocr_worker.ps1` once; see Known failures).
- **Windows.Media.Ocr** (system WinRT OCR) — verified live 2026-07-25 (`m14-probe-001`): words + `BoundingRect` + lines
  (reading order) + `TextAngle`; recognizer `en-US`; `MaxImageDimension=10000`; ~74 ms on a 700x220 fixture. No install,
  no admin, no GPU, no network. Wired by `ocr.layout` (Module 14); registry id `ocr.windows.media`.
- **Tesseract OCR** at `C:\Program Files\Tesseract-OCR\tesseract.exe` — **installed** (found by `m14-probe-001`),
  **declared not wired** (`ocr.tesseract`) as a future `ocr.layout` engine (calibrated per-word confidence + multi-lang).
  No Python OCR libs (easyocr/paddleocr/rapidocr/pytesseract) in either venv (`onnxruntime`/`PIL`/`cv2` present).
- **Pillow (PIL) + numpy** — the imaging backend for `image.util` (Module 15). **System python**
  (`C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe`): **PIL 10.2.0 + numpy 1.26.4 + cv2 4.9.0**;
  **speech venv** (F:): PIL 12.2.0 + numpy 2.4.4. Verified live 2026-07-25 (`m15-probe-001`): round-trips png/jpg/webp/
  bmp/tiff, LANCZOS + all format features, EXIF api, and a numpy-DCT pHash **identical across both** PIL/numpy versions.
  `image.util` uses the **system python** (CPU-only, not tied to the CUDA/speech venv). No install needed.
- **onnxruntime** — the detection runtime for `detect.objects` (Module 16). **System python**: **onnxruntime-gpu 1.17.1** +
  onnxruntime-directml 1.17.1 (providers: Tensorrt/CUDA/CPU) + torch 2.2.1 + torchvision 0.17.1. `detect.objects` requests
  **`CPUExecutionProvider`** by default (deterministic + parallel-safe). Verified live 2026-07-25 (`m16-probe-001`: CPU-provider
  session load + YOLOX-Nano inference reproducing the cloud detections byte-for-byte). No install needed.
- Not admin. No system-wide `pwsh` (only the user `~\.dotnet\tools` entry — resolves in new shells).

## Installed local models
- **Discovered + registered (2026-07-24); relocated + tokenizer-deduped 2026-07-25 (D-0028).** 4 LLM GGUF
  (Qwen2.5 0.5B/1.5B/3B + Qwen3.5-27B; all `wired` via `model.gateway`), 1 STT (Whisper base.en), 2 TTS voices
  (Qwen3-TTS 0.6B/1.7B; the redundant standalone 12 Hz tokenizer was **de-duplicated/removed** — each voice keeps its
  own bundled `speech_tokenizer\`), 1 embedding (Qwen3-Embedding-0.6B). **Relocated out of the `_pending-model-storage\`
  staging area into per-owning-module F: homes** (`…\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\`; the shared
  llama.cpp engine under `_engines\`); the staging area and its `MIGRATION.md` are **deleted**. Full inventory + new
  paths in `TOOL_MODEL_REGISTRY.md` / `models.json`. **STT (Whisper base.en) is wired via `speech.stt` (M11); the TTS
  voices (Qwen3-TTS 0.6B/1.7B) are wired via `speech.tts` (M12)** (they run under the speech venv, not the gateway).
  Only the **embedding** model remains declared-but-unwired (its own Module 23; pre-provisioned at `23-artifact-search\`).
- **Object detectors added 2026-07-25 (Module 16).** `detect.yolox.nano` (3.66 MB, default) + `detect.yolox.tiny` (20.2 MB)
  — COCO-80 YOLOX ONNX (Apache-2.0), downloaded then (2026-07-25) relocated to `16-detect-objects\detector\{yolox-nano,yolox-tiny}\`
  (sha256 byte-exact). Type `detector`, engine `onnxruntime`, `wired:false` for the gateway; run under the **system python**
  (CPU) via `detect.objects`. Both staged + verified (`m16-probe-001` nano live; `m16-test-001` tiny staged).
- **VLM added 2026-07-25 (Module 17).** `vlm.qwen2p5-vl-3b` — Qwen2.5-VL-3B-Instruct GGUF (`Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf`
  ~1.80 GB + `mmproj-Qwen2.5-VL-3B-Instruct-f16.gguf` ~1.25 GB), Apache-2.0, downloaded from `ggml-org/Qwen2.5-VL-3B-Instruct-GGUF`
  and (2026-07-25) relocated to `17-image-interpret\vlm\Qwen2.5-VL-3B-Instruct-GGUF\` (sha256 recorded in `models.json`). Type `vlm`, engine
  `llama-server` (multimodal, carries a `mmproj` path), `wired:false` for the gateway; run via the shared `llama-server` by
  `image.interpret`. Staged + **load-and-caption verified live** (`m17-probe-002`: accurate `dog.jpg` caption, ~111 tok/s, full
  GPU offload on the RTX 2080 Ti).

## Available hardware (measured 2026-07-24)
- **CPU** Intel i9-9900KF (8c/16t @3.6GHz) · **RAM** 64 GB · **GPU** NVIDIA RTX 2080 Ti **11 GB VRAM** (CUDA,
  driver 591.74, cc 7.5) · **OS** Windows 10 Pro 19045 x64. Host `DESKTOP-PF5FFMF`, user `just_`.
- **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**), E: "Game Drive" 858 GB (~534 GB free),
  **F: "Storage space" 3.72 TB (~1.78 TB free)** = the large-data home. (No D: on this box.)
- Full profile + runtimes in `TOOL_MODEL_REGISTRY.md` (Hardware profile).

## Active model servers
- None persistent. `model.gateway` starts a **transient `llama-server`** on a free loopback port per call and kills
  it when done (no warm/persistent worker yet — D-0002). **`image.interpret` (Module 17) does the same with a transient
  multimodal `llama-server`** (`--mmproj`), also `parallel_safe:false`.

## Known working invocation paths
- Executor: `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` /
  `...\Submit-BootstrapTask.ps1` / `...\Stop-BootstrapExecutor.ps1` (from the module dir).
- Direct pwsh (any script): `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- Skill (direct): `pwsh -NoProfile -File modules\01-skill-bootstrap\skills\ref.echo\Invoke-RefEcho.ps1 -Message <s> -Repeat <n>`.
- Skill (wrapped): `pwsh -NoProfile -File modules\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir <skill dir> [-InputsJson '<json>']`.
- Skill (through executor): submit a task package whose `task.ps1` calls either entrypoint; read the
  envelope from `runtime/completed/<task_id>/stdout.txt`.
- uia.actor (direct): `pwsh -NoProfile -File modules\05-uia-actor\Invoke-UiaActor.ps1 -Title '<glob>' -Action <invoke|toggle|select|expand|collapse|setvalue|focus> [-AutomationId|-Name|-ControlType|-Path <loc>] [-Value <s>] [-DryRun]`.
- capture.screen (direct): `pwsh -NoProfile -File modules\06-capture-screen\Invoke-CaptureScreen.ps1 [-Target <monitor|window|app|region>] [-Monitor <index|all|primary>] [-Hwnd|-ProcessId|-Title <loc>] [-App <glob>] [-X -Y -Width -Height] [-Format <png|jpg>]` (or `-InputsJson '<json>'`).
- model.gateway (direct): `pwsh -NoProfile -File modules\07-model-gateway\Invoke-ModelGateway.ps1 [-Model <id>|-Tier <tiny|weak|mid|strong>] -Prompt '<s>' [-System '<s>'] [-MaxTokens -Temperature -TopP -TopK -Seed]` (or `-InputsJson '<json {…,messages[]}>'`). Registry: `modules\07-model-gateway\models.json`.
- speech.stt (direct): `pwsh -NoProfile -File modules\11-speech-stt\Invoke-SpeechStt.ps1 -InputFile <audio> [-Normalize <auto|always|never>] [-Language <code>] [-Translate] [-NoGpu] [-SegmentConfidenceThreshold <0..1>] [-Model <id>]` (or `-InputsJson '<json {input,normalize,language,...}>'`). Resolves whisper.cpp + `stt.whisper.base-en` from `modules\07-model-gateway\models.json`; normalizes non-ready input via `audio.ingest`.
- speech.tts (direct): `pwsh -NoProfile -File modules\12-speech-tts\Invoke-SpeechTts.ps1 -Text '<text>' [-Speaker <Ryan|Aiden|...>] [-Language <name>] [-Instruct '<style>'] [-Seed <n>] [-Format <wav|mp3|...>] [-SampleRate <hz>] [-Model <id>]` (or `-InputsJson '<json {text,speaker,language,instruct,...}>'`). Runs the Qwen3-TTS worker `tts_infer.py` under the speech venv (registry `engine_env`); 24 kHz mono WAV, optional format/rate via `audio.ingest`.
- voice.live (direct): `pwsh -NoProfile -File modules\13-voice-live\Invoke-VoiceLive.ps1 -InputFile <audio> [-Respond <bool>] [-Speak <bool>] [-ReadbackTranscript <bool>] [-Tier <weak|mid|...>] [-Speaker <name>] [-Format <wav|mp3|...>]` (or `-InputsJson '<json {input,respond,speak,...}>'`). Composes speech.stt → model.gateway → speech.tts; writes `voice.json`/`voice.md`/`reply.wav`.
- image.interpret (direct): `pwsh -NoProfile -File modules\17-image-interpret\Invoke-ImageInterpret.ps1 -InputFile <image> [-Prompt '<q>'] [-Mode <caption|describe|vqa|screen>] [-MaxTokens <n>] [-Temperature <n>] [-MaxDimension <n>] [-Capture] [-Model <id>|-Tier <3b>]` (or `-InputsJson '<json {input,prompt,mode,system,max_tokens,temperature,max_dimension,capture,...}>'`). Resolves `vlm.qwen2p5-vl-3b` (type `vlm`) + the staged multimodal `llama-server` from `modules\07-model-gateway\models.json`; composes capture.screen (`-Capture`) + image.util (`-MaxDimension`); writes `interpret.json`/`interpret.md`.
- User ops (click-to-run): `ops/*.bat` — start/stop/restart/status the executor and run tests; each writes
  output to `ops/out/` for the agent to read.
- Watchdog: `ops/start-watchdog.bat` (supervise), `ops/stop-watchdog.bat`, `ops/recover-executor.bat [-Force]`;
  direct `pwsh -NoProfile -File modules\00.1-exec-watchdog\Watch-Executor.ps1` / `...\Recover-Executor.ps1`.

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).
- Module 1: `modules/01-skill-bootstrap/tests/Invoke-SkillBootstrapTests.ps1` — 11/11 pass (2026-07-24).
- Module 2: `modules/02-fs-observer/tests/Invoke-FsObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 3: `modules/03-proc-observer/tests/Invoke-ProcObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 4: `modules/04-uia-inspector/tests/Invoke-UiaInspectorTests.ps1` — 16/16 pass (2026-07-24).
- Module 5: `modules/05-uia-actor/tests/Invoke-UiaActorTests.ps1` — **26/26 pass** (manifest, dry-run,
  five error paths, wrapper, and live setvalue/toggle/invoke + dry-run-invoke against a WinForms probe;
  run 2026-07-24 via the executor as `m5-test-001`, exit 0, 13s).
- Module 00.1: `modules/00.1-exec-watchdog/tests/Invoke-WatchdogTests.ps1` — **22/22 pass** (pure decision
  logic; `Test-ExecutorAlive`; `Get-ExecutorState`; Module 0 heartbeat/last-exit markers; and integration on
  temp runtimes: watchdog auto-restarts a crash and stands down on an authorized stop; `wd-test-002` 2026-07-24).
  Module 0 regression re-run **12/12** with the additive markers (`wd-precheck-001`).
- Module 6: `modules/06-capture-screen/tests/Invoke-CaptureScreenTests.ps1` — **39/39 pass** (manifest;
  monitor primary/all; region png+jpg with PNG/JPEG magic-byte + sha256 checks; six error paths; wrapper; and
  a live window capture self-verified against a WinForms probe; run 2026-07-24 via the executor as
  `m6-test-001`, exit 0, ~138s).
- Module 7: `modules/07-model-gateway/tests/Invoke-ModelGatewayTests.ps1` — **28/28 pass** (manifest; registry
  declares all modalities + 4 wired LLMs; five error paths incl. `model_not_found`/`model_not_wired`/
  `registry_not_found`; **live** generation on the staged 0.5B via `-Tier tiny` — status ok, finish_reason stop,
  confidence 0.7, provenance with token counts, artifact sha256 verified; wrapper ran the 1.5B; a forced
  truncation → confidence 0.4 → a valid review-queue item; no orphaned `llama-server`; run 2026-07-24 via the
  executor as `m7-test-002`, exit 0, ~15s).
- Module 8: `modules/08-classify-batch/tests/Invoke-ClassifyBatchTests.ps1` — **33/33 pass** (manifest +
  batch/parallel_safe/determinism flags; five setup error paths `no_labels`/`no_items`/`invalid_mode`/`no_fields`/
  `gateway_not_found`; **live** `classify` batch of 3 on `-Tier tiny` (each item labeled in-set, groups partition,
  aggregate provenance calls=3, `classified.json` sha256 verified); explicit `-Model` 1.5B resolves; **live**
  `extract` returns the requested keys; review routing at threshold 0.99 → a `classify.batch` review item with
  per-item `source_ref` and the gateway's writes suppressed from the canonical queue; Module 1 wrapper; no orphaned
  `llama-server`; run 2026-07-24 via the executor as `m8-test-001`, exit 0, ~26s). A cloud-only mock-gateway harness
  (`tests/mock-gateway.ps1`) validated the parse/confidence/group logic off-GPU before shipping.
- Module 9: `modules/09-review-processor/tests/Invoke-ReviewProcessorTests.ps1` — **34/34 pass** (manifest +
  `batch`/`parallel_safe`/`determinism` flags; missing-queue→ok-empty; `gateway_not_found` error path w/o queue
  mutation; **live** `mid`(3B) adjudication that resolves a seeded classify.batch item **in place** — `resolution.by`=
  `review.processor:llm.weak.qwen2p5-3b`, in-set `decision`, original `weak_result`/`source_ref` preserved, malformed
  line preserved, already-resolved item untouched, `review.json` sha256 verified — + an append-only
  `review_resolved.jsonl` `lifeorch.review.resolution/0.1`; forced **escalation** (`escalate_threshold` 0.99) →
  `escalated_to:"frontier"`; `-DryRun` no-op (queue+log byte-identical); source-ref resolver true/false; Module 1
  wrapper; a live **`strong`(27B)** end-to-end at `gpu_layers=32` with `-LoadTimeoutSec 300`; no orphaned
  `llama-server`; run 2026-07-24 via the executor as `m9-test-003`, exit 0, ~150s). A cloud-only mock-gateway harness
  (`tests/mock-gateway.ps1`) validated the select/parse/adjudicate/queue-rewrite/escalation/log logic off-GPU first.
- Module 10: `modules/10-audio-ingest/tests/Invoke-AudioIngestTests.ps1` — **43/43 pass** (manifest;
  a real default WAV — codec pcm_s16le / 16000 Hz / mono / ~2 s via ffprobe, WAV magic, sha256 == file; the full
  format matrix mp3/flac/opus/ogg/m4a with per-codec magic bytes; keep-source 44100/stereo; EBU + peak loudness;
  five error paths `input_not_found`/`invalid_format`/`invalid_channels`/`no_audio_stream`/`ffmpeg_not_found`; the
  Module 1 wrapper). The harness is **OS-portable** (`[IO.Path]::GetTempPath()` + `Get-Command ffmpeg`, fixtures
  generated by ffmpeg): it ran on the cloud Linux box (ffmpeg 6.1, 43/43) as the pre-ship gate and unchanged on
  the Windows executor (ffmpeg 8.1) — `m10-test-001`, exit 0, ~17s.
- Module 11: `modules/11-speech-stt/tests/Invoke-SpeechSttTests.ps1` — **27/27 pass** (manifest + mixed/parallel_safe/
  batch flags; a **live** jfk.wav transcription — text contains "country", ≥1 timestamped segment, overall confidence
  0.8707 in (0,1], per-segment confidence, `model_provenance[1]` engine whisper.cpp, whisper.json/.srt/.txt +
  transcript.json/.md artifacts with sha256, whisper.json sha == file; review routing at threshold 0.999 → a valid
  `speech.stt` review item; `normalize auto` feeds a ready WAV directly / `always` re-encodes via the real `audio.ingest`
  child to 16 kHz and still transcribes; `input_not_found` + `whisper_cli_not_found` error paths with schema-valid
  envelopes; the Module 1 wrapper; no orphaned `whisper-cli`/`llama-server`; `m11-test-001`, exit 0, ~14s). The harness is
  **dual-mode / OS-portable**: `-UseMock` runs the *real* skill against a mock `whisper-cli` (`tests/mock-whisper.ps1` +
  the captured real `tests/fixtures/jfk.whisper.json`) — it ran on the cloud Linux box (27/27) as the pre-ship gate before
  the identical harness ran live on the Windows executor.
- Module 12: `modules/12-speech-tts/tests/Invoke-SpeechTtsTests.ps1` — **25/25 pass** (manifest + mixed/parallel_safe/
  batch flags; a **live** English synthesis (speaker Ryan) → a real 24 kHz mono WAV with duration > 0, overall confidence
  0.9 in (0,1], `model_provenance[1]` engine transformers, speech.wav/tts.json/tts.md artifacts with sha256; review
  routing (forced threshold) → a valid `speech.tts` review item; **mp3 conversion** via the real `audio.ingest` child
  (`converted=true`, mp3 artifact); `no_text` + `model_not_found` error paths with schema-valid envelopes; the Module 1
  wrapper; `m12-test-001`, exit 0, ~132 s). The harness is **dual-mode / OS-portable**: `-UseMock` runs the *real* skill
  against a stdlib mock python worker (`tests/mock-tts-infer.py`, writes a real PCM16 WAV) + a temp registry — it ran on
  the cloud Linux box (25/25) as the pre-ship gate before the identical harness ran live on the Windows executor.
- Module 13: `modules/13-voice-live/tests/Invoke-VoiceLiveTests.ps1` — **21/21 pass** (manifest + mixed/parallel_safe/
  batch flags; a **live** full voice turn on `samples\jfk.wav` — transcript contains "country", a non-empty LLM answer,
  a real `reply.wav`, `model_provenance` ≥ 3 (stt+gateway+tts), all stages ok, reply artifact sha256; a
  respond-off/readback path; `input_not_found` error path with a schema-valid envelope; the Module 1 wrapper;
  `m13-test-001`, exit 0). The harness is **dual-mode / OS-portable**: `-UseMock` points all three children at a single
  `tests/mock-child.ps1` (canned envelopes; the tts branch writes a real WAV) so the whole compose/aggregate/envelope
  pipeline runs off-GPU — it ran on the cloud Linux box (23/23) as the pre-ship gate before the identical harness ran
  live on the Windows executor.
- Module 14: `modules/14-ocr-layout/tests/Invoke-OcrLayoutTests.ps1` — **30/30 pass** (manifest + mixed/parallel_safe=true/
  batch flags; a **live** OCR of `tests/fixtures/ocr-sample.png` — text contains HELLO/WORLD/quick, `word_count`≥5,
  `line_count`≥2, lines in reading order, each word an integer pixel `bounding_rect`, overall confidence in (0,1],
  `model_provenance[1]` engine `windows.media.ocr`, `ocr.json`/`ocr.md` artifacts with sha256; review routing at a forced
  0.999 threshold → a valid `ocr.layout` `verify_ocr` item; a blank image → `verify_no_text`; `input_not_found` +
  `engine_not_found` error paths; the Module 1 wrapper; **and the live `capture.screen` composition** (`-Capture` → OCR the
  primary monitor, source=capture); `m14-test-003`, exit 0; no orphaned processes). The harness is **dual-mode / OS-
  portable**: `-UseMock` runs the *real* wrapper against a mock worker (`tests/mock-ocr-worker.ps1` + captured real
  `tests/fixtures/ocr-sample.meta.json`) + a temp registry — it ran on the cloud Linux box (28/28) as the pre-ship gate
  before the identical harness ran live on the Windows executor. Real-registry smoke `m14-smoke-001` (7 words, conf 0.9).
- Module 15: `modules/15-image-util/tests/Invoke-ImageUtilTests.ps1` — **48/48 pass** (manifest + deterministic/parallel_safe=true/
  batch flags; `meta` -> correct 800x600/PNG/RGB + sha256==file + 16-hex pHash/dHash + `confidence` null + empty
  `model_provenance` + image.json/image.md artifacts with sha256; `resize max_dimension`=400 -> 400x300 with `scale_x==scale_y==0.5`
  and the output file reopened at 400x300; resize exact/fit/fill; crop rect/normalized(0.5)/region(center) -> 400x300; convert to
  png/jpg/webp/bmp/tiff each reopened with the right format/mode/dims; tile grid 2x2 -> count 4 (+sha256) and fixed-size 300 -> count 6;
  similarity self (Hamming 0, score 1.0) / near-dup jpg (small) / different (larger); six error paths `input_not_found`/`invalid_op`/
  `missing_params`/`unsupported_format`/`compare_not_found` + schema-valid error envelope; the Module 1 wrapper; `m15-test-001`, exit 0,
  no orphaned python). The harness is **real-worker & OS-portable** (no mock — Pillow is portable + version-stable): it generates its
  fixtures with Pillow at runtime and ran the *real* worker on the cloud Linux box (pwsh 7.4.6 + cloud python + Pillow 12.2, 48/48) as
  the pre-ship gate before the identical harness ran live on the Windows executor (system python, PIL 10.2). **Re-verified
  48/48 in `m16-test-001`** after the JPEG-`dpi` JSON-safety fix (below) — no regression.
- Module 16: `modules/16-detect-objects/tests/Invoke-DetectObjectsTests.ps1` — **38/38 pass** (manifest + mixed/parallel_safe=true/
  batch flags; a **live** detection of `tests/fixtures/dog.jpg` — ≥3 detections incl. `dog`, every box integer + within image
  bounds, every score in (0,1], envelope `confidence` = the max detection score, `model_provenance[0]` engine `onnxruntime`,
  `detect.json`/`detect.md` artifacts with sha256; a COCO **class filter** (`dog` only); score-floor monotonicity; **both
  review paths** — a forced 0.999 `confidence_threshold` → a valid `detect.objects` `verify_detections` item, a 0.999
  `score_threshold` → 0 detections → `verify_no_objects`; the **image.util `-MaxDimension` downscale** composition (boxes back
  in original 768×576 space, still finds a dog); five error paths `input_not_found`/`model_file_not_found`/`registry_not_found`/
  `model_not_found`; the Module 1 wrapper; **and the live `capture.screen` composition** (`-Capture` → source=capture);
  `m16-test-001`, exit 0; no orphaned processes; 13 shipped files sha256-verified byte-exact). The harness is **real-worker &
  OS-portable** (no mock — onnxruntime CPU inference is deterministic): the same harness ran the *real* worker on the cloud
  Linux box (onnxruntime 1.25, model via `-ModelPath`, 34/34 — capture skipped off-Windows) as the pre-ship gate before it
  ran live on the Windows executor (system python onnxruntime 1.17.1, model from the registry on F:, 38/38). Real-registry
  smoke: default `detect.yolox.nano` on `dog.jpg` → dog 0.83 / car 0.81 / bicycle 0.81.
- Module 17: `modules/17-image-interpret/tests/Invoke-ImageInterpretTests.ps1` — **48/48 pass** (manifest + mixed/
  parallel_safe=false/batch/streaming flags; a **seam** describe on `dog.jpg` via a captured-real `llama-server` response —
  confidence 0.7, text mentions the dog, `server.mode=captured_response`, completion_tokens carried through, provenance engine
  `llama-server`, `interpret.json`/`interpret.md` sha256; VQA mode auto-resolves from `-Prompt`; mode defaulting; all three
  **review paths** — truncated→`low_confidence`, refusal→`needs_strong_review`, empty→`failed_transform`, each a valid
  `image.interpret` `verify_interpretation` item; a forced-0.99 threshold flags the describe; the **image.util `-MaxDimension`
  downscale** composition (real on Linux, original dims 768×576); five error paths `input_not_found`/`registry_not_found`/
  `model_not_found`/`invalid_mode`/`no_prompt`; the Module 1 wrapper; and — with `-Live` on the executor — **real
  `llama-server` VLM** describe (device `cuda:0`) + VQA + the **capture.screen** composition (`source=capture`) + no orphaned
  `llama-server`; `m17-test-001/002`, exit 0). The harness is **dual-mode / OS-portable**: seam mode (the captured-real-response
  `-VlmResponsePath` + the real `image.util`) ran on the cloud Linux box (40/40) as the pre-ship gate before the identical
  harness ran live (`-Live`) on the Windows executor (48/48).
- Module 18: `modules/18-image-index/tests/Invoke-ImageIndexTests.ps1` — **41/41 pass (live) / 40/40 (cloud mock)** (manifest +
  mixed/parallel_safe=false/batch/streaming flags; the **default** run fuses image.util meta+hashes only — `confidence` null,
  empty `model_provenance`, `index.json`/`index.md` sha256; the **`-All`** run fuses all four stages — every stage `ran`, the
  stochastic stages ok/partial, envelope `confidence` = the **min of the per-stage confidences**, `model_provenance` ≥ 3 tagged
  ocr+detect+interpret, `summary.caption`/`top_objects` populated, `summary.ocr_text` mirrors the ocr stage; the child-review
  **redirect** — `review.is_producer=false`, `child_review_path` under the invocation dir; selective `-Ocr`-only; two error
  paths `input_not_found` + `ocr_not_found` (requested child entrypoint missing); the Module 1 wrapper; **live extras** — a real
  full index on `dog.jpg` (image.util hashes, detect found objects, interpret text, `model_provenance` ≥ 2, **no orphaned
  `llama-server`**). The harness is **dual-mode / OS-portable**: `-UseMock` points every child (capture/image.util/ocr/detect/
  interpret) at `tests/mock-child.ps1` (branches on the `-ArtifactRoot` leaf; canned envelopes; capture writes a real 1×1 PNG;
  image.util emits a real sha256; the stochastic children append a review item to the passed `review_queue_path`) so the **real**
  orchestrator's fuse/aggregate/redirect/envelope logic runs off-GPU on the cloud box (40/40) as the pre-ship gate before the
  identical harness ran live (`-Live`) on the Windows executor (41/41, `m18-test-002`). The two live-only assertion adjustments
  (envelope confidence = min-of-stages; `ocr_text` mirrors the stage) were made mode-robust after the first live run showed OCR
  correctly finds **no text** on a photo (conf 0.1 = the fused record's weakest link). Live smoke: `dog.jpg -All` → 5 detections
  + a full VLM description + min-confidence 0.1, canonical queue **untouched (0→0)**.

## Known failures / gotchas
- **image.util truncated its worker meta on a real JPEG `dpi` (2026-07-25, Module 15, fixed).** Pillow returns a JPEG's
  `dpi` as `(IFDRational, IFDRational)`, which `json.dump` cannot serialize — it raised **mid-write**, leaving a truncated
  `image_meta.json`, so `image.util` failed with `ConvertFrom-Json ... Unexpected end ... Path 'metadata.dpi'`. Surfaced the
  first time a consumer (`detect.objects` `-MaxDimension`) composed `image.util` on a real photo (the module's own fixtures
  were dpi-less generated PNGs). **Fix:** `image_worker.py` coerces `dpi` to plain floats (`safe_dpi`). **Rule:** any value
  written into a worker meta must be JSON-serializable; exotic Pillow/numpy types (IFDRational, numpy scalars) need explicit
  coercion or a `json.dump(default=...)`. Module 15 re-verified 48/48.
- **Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8 (2026-07-25, Module 14).** Any non-ASCII byte in a
  script run under `powershell.exe` (5.1) corrupts parsing: a UTF-8 em dash in `ocr_worker.ps1` made 5.1 fail with
  "Unexpected token" / "The hash literal was incomplete" and exit 1 with **no output** (`m14-diag-002`). Because the
  `ocr.layout` wrapper discarded the worker's stderr, the wrapper only saw "produced no meta". **Rule:** keep any Windows
  PowerShell 5.1 worker **ASCII-only** (or give it a UTF-8 BOM). pwsh 7 is unaffected (it reads BOM-less as UTF-8), so the
  pwsh-7 wrapper may keep non-ASCII. Grep `[^\x00-\x7F]` before shipping a 5.1 script.
- **Cowork `device_stage_files` can return a STALE snapshot (2026-07-24, Module 12).** Re-staging a file to an uploads
  path that was already staged earlier in the session returned the **old** bytes (pre-edit) even though the reported
  `mtimeMs` was current — nearly caused a revert of Module 11's committed doc edits. **Fix/workaround:** to reliably read
  the *current* on-disk content into the cloud, first copy it (via the executor) to a **fresh, never-staged path** (e.g.
  `modules\<mod>\runtime\docsrc\`) and stage that; or verify staged content by a marker (grep) before editing. The
  on-disk repo is always canonical — trust a direct executor read over a re-stage.
- **`ffprobe` on PATH is shadowed by a Python shim (2026-07-24).** `where.exe ffprobe` returns
  `…\Python310\Scripts\ffprobe.exe` *before* the real `…\WinGet\Links\ffprobe.exe`; the Python shim is not the
  real ffprobe. Resolve ffprobe as the **sibling of the resolved ffmpeg** (as `audio.ingest` does), or filter out any
  `\Python*\Scripts\` source. Also: the Linux device-mount cannot `stat` the WinGet `Links\*.exe` reparse points, so
  `ls` on the mount shows them absent though Windows `where.exe`/`Test-Path` resolve them fine.
- **Executor fatal-crashed on a transient file lock (2026-07-24T06:26:36Z).** While task `m5-example-001`
  was running (a task that launched a GUI subprocess and where the agent was also reading `runtime/` over
  the device-bridge mount), the executor died with `The process cannot access the file because it is being
  used by another process` and `Error during cancellation: ...`, then `Executor stopped`. Likely a
  directory-move (running→completed/failed) or state-write colliding with an open handle (possibly the
  Linux-mount reader, or the task's own child process). **Fixed two ways (2026-07-24):** (1) externally
  auto-recovered by the watchdog (Module 00.1); (2) **in-process self-heal** — `Invoke-WithFileRetry` now
  wraps the atomic state-writes (`Write-JsonAtomic`) and the queue finalization move (`Move-FinalizedTask`),
  and a per-iteration loop guard catches `IOException`/`UnauthorizedAccessException` and continues, so this
  crash class no longer kills the executor. Module 0 tests remain **12/12** with the self-heal. Operational
  note still worth keeping: avoid holding handles on `runtime/` from the mount while tasks run; keep polls brief.
- The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`, so `(Get-Process -Id $PID).Path`
  is **not** a reliable pwsh locator. Pass explicit pwsh paths. Executor/harness already accept `-PwshPath`.
- **`@($list)` on a raw `System.Collections.Generic.List[object]` throws "Argument types do not match"**
  (pwsh 7.4.6) when it holds `[pscustomobject]`s — use `$list.ToArray()`. Module 5 uses `.ToArray()` throughout.
- The **latest** `PowerShell` .NET global-tool package is malformed (missing tool manifest); pin a
  version (7.4.6 used).
- Launching a live GUI probe window from *inside* a background executor task can hang that task's UIA calls
  if the window's UI thread stops pumping (observed once with `m5-example-001`). The Module 5 **test** harness
  drives a probe reliably; prefer side-effect-free dry-runs when capturing examples to avoid GUI-in-task risk.
- Skill scripts must write **only** the JSON envelope to stdout (diagnostics to stderr); the executor
  captures stdout verbatim into `stdout.txt`, which is parsed as the envelope.
- **PowerShell empty-array unroll (pwsh 7.4.6, StrictMode):** `$x = if(cond){@($y)}else{@()}` assigns **`$null`**
  when the empty-array branch is taken (an empty array written from a block unrolls to nothing), so a later
  `$x.Count` throws "The property 'Count' cannot be found." Assign the array first (`$x=@(); if(cond){$x=@($y)}`).
  Hit + fixed in `model.gateway` (empty `-Stop`).
- **PowerShell array double-wrap (pwsh 7.4.6):** a helper that does `return ,$out` (comma to prevent unrolling) and
  is then collected with `@(helper)` yields a **1-element array whose single element is the inner array**, not the
  N elements — so a later `foreach`/lookup silently iterates once over the whole array (no error; wrong results). In
  `classify.batch` this made label matching quietly fail while the labels list still *looked* right in the envelope.
  Fix: build into a `List[object]` and `return $acc.ToArray()` (no leading comma); let `@(...)` re-collect normally.
- **`$var:` in a double-quoted string** (e.g. `"item $id: done"`) parses `$id:` as a scope/drive reference and is a
  **syntax error** — delimit with `${id}` (`"item ${id}: done"`). Cheap to catch: parse every shipped `.ps1` with
  `[System.Management.Automation.Language.Parser]::ParseFile` before submitting (the cloud agent installed pwsh 7.4.6
  on Linux purely to parse-check + run a mock-gateway logic harness off-GPU before shipping Module 8).
- **This llama.cpp build (b8661) `llama-cli` is interactive-only** — it rejects `-no-cnv` ("use llama-completion
  instead", which isn't built) and decorates stdout with a banner/`>`/timing footer. Script LLMs via **`llama-server`**
  (`/v1/chat/completions` → clean JSON with `finish_reason`/`usage`/`timings`), as `model.gateway` does.
- **Child-process pipe deadlock:** reading a child's stdout to end while its stderr pipe fills (llama.cpp logs a lot)
  deadlocks. Drain both streams async (`ReadToEndAsync`) or redirect to files, and close the child's stdin. (The
  gateway uses `Start-Process` with file-redirected server logs; probes used async reads.)
- `capture.screen` uses screen-pixel copy (`CopyFromScreen`): an **occluded** window captures whatever covers
  it and a **minimized** window returns a `window_minimized` error — it does **not** raise/activate windows
  (read-only). Per-Monitor-V2 DPI awareness is set once per process (ignored if already set). Off-screen /
  `PrintWindow` compositing is deferred (Module 6 follow-on). Note (Linux only, does not affect the Windows
  executor): `System.Drawing.Common` is Windows-only, so `capture.screen` cannot even be dry-run on a
  non-Windows host — the cloud agent validated it by pwsh syntax-parse + Roslyn compile of the embedded C#,
  then ran it on the Windows executor.

## Unresolved questions
- Root cause of the executor file-lock crash (see Known failures) — reproduce and harden Module 0.
- Install pwsh system-wide (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- ~~Contract finalization~~ and ~~model relocation~~ — **both resolved 2026-07-25 (D-0028):** the D-0009/D-0011
  conventions are folded into `SKILL_CONTRACT.md` v0.2, and every staged model is relocated into its owning-module
  F: home (the 12 Hz TTS tokenizer de-duplicated) with `_pending-model-storage\` deleted.
- **model.gateway follow-ons:** semantic (not just completeness) confidence; a warm/persistent server if load
  latency dominates. The 27B `gpu_layers` is now **tuned to 32** (Module 9 sweep — see REVIEW_QUEUE.md); a cold
  27B load (~90s) approaches the gateway's 120s default, so callers pass a longer `-LoadTimeoutSec` for the strong tier.

## Next expected action
0. **Module 19 `logic.escalator` (Local Logic Escalator, Phase A #1) is MVP complete + empirically calibrated this session (D-0030).**
   The next Phase-A unit per `MODULE_ROADMAP.md → Build priority` is **`doc.io`** (Local Model Doc Read/Write/Edit/Append), then a
   local orchestrator (`agent.local`), then the generators, then the **Widget** layer (`widgets/`). **Top escalator follow-ons
   (measured, NOT this session):** raise the strong-tier `max_tokens` / add a no-reasoning directive so the 27B returns a parseable
   verdict instead of an empty one (D-0018, confirmed in `m19-calib-003`); a **self-consistency veto** + more skeptical judge prompts
   to cut the measured **0.20 false-approval** rate; a higher floor / cost-aware early-stop (always-mid beat the ladder on the hard
   eval); live-calibrate K>1 self-consistency; a `route.tasks` (#24) drain of `needs_frontier` tasks; a `unit_test`/retrieval gate.
   See D-0030 + `modules/19-logic-escalator/CALIBRATION.md`.
1. **The image/document perception block (14–18) is COMPLETE** — #14 `ocr.layout`, #15 `image.util`, #16 `detect.objects`,
   #17 `image.interpret`, and now #18 `image.index` (the fusion capstone) are all MVP complete. **The housekeeping pass is done (D-0028), and the build order was re-prioritized (D-0029): the next
   unit is Phase A of `MODULE_ROADMAP.md → Build priority` — start with the **Local Logic Escalator**
   (`logic.escalator`, the cost-offload keystone), then `doc.io` / a local orchestrator / the generators,
   then the **Widget** layer (`widgets/`). The video block (#19-22) is deferred to Phase C — build it now
   only if video capability is specifically wanted.** **`image.index` follow-ons (NOT this session):** **concurrent** child
   execution (a warm-worker pool shared with #7/#8/#12/#14/#16/#17; run the parallel-safe children together); **batch/directory/
   glob** indexing; **cross-stage grounding** (associate detections ↔ OCR words ↔ caption phrases; open-vocab boxes); an
   **overlay/annotated card image** (needs the `image.util` draw op); persisting indices into `artifact.search` (#23); a
   frontier/`route.tasks` (#24) drain of the redirected `child_review.jsonl`. See D-0027. **`image.interpret` follow-ons (NOT
   this session):** a **warm/persistent VLM server** (shared worker-pool pressure with #7/#8/#12/#14/#16/#18); **logprob/calibrated
   semantic** confidence; **batch/directory**; **multi-image / multi-turn**; **open-vocab grounding boxes**; a **7B VLM tier** or
   the **transformers-venv backend**; wiring the VLM as a **second `ocr.layout` engine**. See D-0026. **`detect.objects` follow-ons
   (NOT this session):** an **overlay/annotated image** (needs an `image.util` draw op); **batch/directory**; a larger tier /
   RT-DETR / a VLM open-vocab detector (#17); **GPU-by-default** or a warm detector worker; **calibrated** confidence; object
   **tracking** across frames (#20). See D-0025. **`image.util` follow-ons (NOT this session):** the **box-overlay/draw** op;
   **batch/directory/glob**; rotate/flip/EXIF auto-orient; denoise/sharpen; multi-frame (GIF); an operation pipeline. See D-0024.
   **`ocr.layout` follow-ons (NOT this session):** wire **Tesseract** (`ocr.tesseract`, installed) or a VLM as a second `-Engine`;
   the box-overlay + `MaxImageDimension` downscale compositions; multi-column reading-order reflow; **batch/directory/PDF-page**
   OCR. See D-0023.
2. **Audio-track follow-ons (NOT this session):** a mic `audio.capture` skill + a streaming/interactive loop; standalone
   VAD (stage a VAD ggml model); multi-turn dialogue + memory; a **warm-worker pool** so a voice turn avoids three cold
   model loads (the shared pressure point with #7/#8/#12/#14 per-call worker spawns). See D-0022.
3. `review.processor` follow-ons (NOT this session): a frontier/`route.tasks` (#24) drain of `escalated` items;
   compaction/archival of `resolved` items to keep the live queue small; a warm/persistent gateway worker (shared
   with #8); calibrated/semantic reviewer confidence; **strong-tier prompt/max_tokens tuning** so the 27B emits a
   parseable JSON verdict instead of being escalated on truncated reasoning (observed in `m9-test-003`).
4. Housekeeping — **contract finalization (v0.2), model relocation + tokenizer de-dup, and the `proteus_repo/tools/`
   removal are DONE 2026-07-25 (D-0028).** Remaining lower-priority follow-ons: classify.batch (warm-worker /
   intra-batch prompt for throughput; calibrated confidence; a side-effecting `sort.files` mover — D-0017);
   audio.ingest (batch/directory ingest; trimming/segmentation → Module 13; denoise/high-pass — D-0019).

- **Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 19 `logic.escalator` (Local Logic Escalator, Phase A #1, D-0030)**: built the escalating tier ladder composing `model.gateway` (tiny→weak→mid→strong) with deterministic ground-truth gates (in-set / JSON-schema+grounding / self-consistency) anchoring every rung — a hard-fail overrides an LLM-judge accept, strong self-consistency short-circuits; orchestrator/non-producer (suppresses child gateway review writes, surfaces `needs_frontier`; canonical queue untouched). Pre-shipped off-machine on cloud pwsh 7.4.6 (24/24 mock-gateway scenarios) → shipped 10 files byte-exact (`m19-verify-001` sha256 + AST-parse OK) → 28/28 with `-Live` (`m19-test-001`, 0 orphans). **Empirically calibrated (`m19-calib-002/003`, the D-0029 experiment):** 3-tier K=1 = 78.6% acc / 0.20 false-approval / −89% cost; 4-tier K=1 = 57.1% (the 27B emits empty verdicts at MVP token caps → fail-safe `needs_frontier`); **does NOT reach the 95% target — reported plainly** with prioritized follow-ons. Added `CALIBRATION.md` + `.gitignore`. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — housekeeping pass, D-0028: (A) folded the three D-0009/D-0011 conventions into SKILL_CONTRACT.md v0.2 (skill-relative artifact roots + absolute paths §3, generic -InputsJson §3.1, lifeorch.skill.invocation_report/0.1 §3.2), keeping the wire schema ids at /0.1 — additive + backward-compatible, so the validators and all existing manifests were untouched; (B) relocated every staged model out of _pending-model-storage into per-owning-module F: homes (LLMs→07-model-gateway, whisper→11-speech-stt, TTS voices→12-speech-tts, detectors→16-detect-objects, VLM→17-image-interpret, embedding→23-artifact-search) + the shared llama.cpp engine→_engines, rewrote models.json (13 models, byte-exact sha256 5aed38db…), de-duplicated the 12 Hz TTS tokenizer (deleted the standalone copy + its declared-only registry entry — each voice keeps its bundled speech_tokenizer), and deleted the emptied _pending-model-storage + its MIGRATION.md; (C) removed the proteus_repo/tools leftover. Re-verified live via the executor (hk-verify-001): all 4 LLM tiers + whisper STT + Qwen3-TTS (bundled tokenizer) + ONNX detector + VLM caption each load from their new homes, 0 orphaned servers. Refreshed the Module 1 README; no skill code changed). · **2026-07-25 (later) — direction pivot D-0029 (docs only, no code):** adopted the Module/Widget vocabulary, created the `widgets/` folder + README, added the `ARCHITECTURE_MAP.md` core-doc (canonical 0-49 spine + the real-time autonomic layer 45-49 + the 6-level operating hierarchy; model names annotated as non-binding candidates), and re-prioritized the build order to a usable-local-core-first sequence (Phase A utility/cost-offload led by the Local Logic Escalator; Phase B the Widget layer; Phase C the deferred research spine). Updated START_HERE / PROJECT_DIRECTION / MODULE_ROADMAP / CURRENT_STATE accordingly.
