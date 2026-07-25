# MODULE_ROADMAP

Owns **module order and status**. Not technical specs — each active module gets a work order.
**Provisional beyond the first few items on purpose:** we do not lock thirty modules before using
the first five. Reorder freely as MVPs teach us what matters.

**Status vocabulary:** Proposed · Ready · In progress · Blocked · MVP complete · Active ·
Needs refactor · Deprecated · Replaced.

---

## Module 0 — Trusted High-Risk Bootstrap Executor
- **id:** `exec.bootstrap` · **Priority:** P0 · **Status:** **MVP complete**
- **Purpose:** Authorized agents submit PowerShell task packages to a filesystem queue; concurrent
  isolated execution, output/exit/timing capture, restart recovery, single-instance lock.
- **Dependencies:** PowerShell 7.
- **MVP acceptance:** 12/12 integration checks (success, failure, timeout kill, concurrency,
  staging-ignored, atomic claim, no double-exec, abandoned-after-restart, duplicate rejection,
  orderly stop, single-instance lock, file preservation). **Met — 12/12 on Windows (pwsh 7.4.6).**
- **Current implementation:** working copy at `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/`;
  original (running) at `proteus_repo/tools/trusted-bootstrap-executor/`, commit `c4e90c4`.
- **Work order:** n/a (built ahead of this doc set). **Blockers:** none. **Deprecation:** none.
- **Known issue (2026-07-24), now fixed:** fatal-crashed once on a transient file-sharing violation during a
  task run (`CURRENT_STATE.md → Known failures`). Addressed two ways — **externally recovered** by Module 00.1
  (watchdog) **and** an **in-process self-heal** (`Invoke-WithFileRetry` around state-writes + finalization
  moves, plus a per-loop `IOException`/`UnauthorizedAccessException` guard). Module 0 tests remain 12/12.
- **Additive (2026-07-24):** now emits `control/heartbeat.json` (each loop) and `control/last-exit.json`
  (`stop_requested`|`signal`|`fatal_error`, in `finally`) so a supervisor can tell a hang/crash from an
  authorized stop. Module 0 tests remain 12/12 with these. See Module 00.1 and DECISION_LOG D-0013.

## Module 00.1 — Executor Watchdog & Recovery
- **id:** `exec.watchdog` · **Priority:** P0 (infrastructure) · **Status:** **MVP complete**
- **Purpose:** a **cooperative, session-scoped, user-launched** supervisor that autonomously restarts the
  executor on **crash or hang with no approval**, but **stands down** on a deliberate stop (honors the
  `last-exit` marker). Plus an on-demand `Recover-Executor` / `recover-executor.bat` (force kill+restart).
  Cooperative, **not** perpetual — no boot persistence, visible, self-killable (DECISION_LOG D-0013, honors D-0001).
- **Dependencies:** Module 0 (+ its additive heartbeat/last-exit markers). **MVP acceptance:** **Met** — pure
  `Get-WatchdogDecision` unit tests; real integration on temp runtimes (auto-restart a crash, stand down on an
  authorized stop); Module 0 markers verified; **tests 22/22 (2026-07-24)**; Module 0 regression re-run 12/12.
- **Implementation:** `modules/00.1-exec-watchdog/` (`Watch-Executor.ps1`, `Recover-Executor.ps1`, tests) +
  `ops/{start-watchdog,stop-watchdog,recover-executor}.bat`. **Work order:** `modules/00.1-exec-watchdog/WORK_ORDER.md`.

## Module 1 — Skill Contract & Registry Bootstrap
- **id:** `skill.bootstrap` · **Priority:** P0 · **Status:** **MVP complete**
- **Purpose:** Establish the smallest common interface for invokable skills: finalize `SKILL_CONTRACT.md`,
  the `skill.json` manifest format, the standard result envelope, standard artifact location, the
  registry entry format, and a **simple invocation wrapper** (validate manifest → run → validate envelope).
  Must **not** become a plugin framework.
- **Dependencies:** Module 0; `SKILL_CONTRACT.md` (v0.1 already drafted in this pack).
- **MVP acceptance:** **Met — `ref.echo` validates and runs directly + through the executor, emitting a
  schema-valid `lifeorch.skill.result/0.1`; the wrapper validates manifest+envelope; module tests 11/11
  (2026-07-24).** Contract-finalization of the adopted conventions deferred (DECISION_LOG D-0009).
- **Implementation:** `modules/01-skill-bootstrap/` — validators (`lib/SkillContract.psm1`), generic
  wrapper (`Invoke-Skill.ps1`), reference skill (`skills/ref.echo/`).
- **Work order:** `modules/01-skill-bootstrap/WORK_ORDER.md`. **Blockers:** none.

## Module 2 — Filesystem Observer
- **id:** `fs.observer` · **Priority:** P1 · **Status:** **MVP complete**
- **Purpose:** Inspect, search, compare, and index the filesystem without screenshots — listings,
  discovery, change detection, metadata, markdown trees, project/artifact indexing.
- **Dependencies:** Module 1. **MVP acceptance:** **Met — `tree.md` + `index.json` with hashes; glob
  search; error path; direct/wrapped/executor; tests 16/16 (2026-07-24).**
- **Implementation:** `modules/02-fs-observer/`. **Work order:** `modules/02-fs-observer/WORK_ORDER.md`.

## Modules 3–6 — Desktop observation & control (provisional)  ← all MVP complete
- **3 `proc.observer`** — Process & Window Observer. ***MVP complete*** — processes + top-level windows +
  foreground; `report.md`/`processes.json`/`windows.json`; tests 16/16 (2026-07-24). Work order:
  `modules/03-proc-observer/WORK_ORDER.md`.
- **4 `uia.inspector`** — UI Automation Inspector. ***MVP complete*** — read-only UIA tree walk (control
  type/name/automation id/bounds/patterns/state); `tree.md`/`elements.json`; tests 16/16 (2026-07-24). Work
  order: `modules/04-uia-inspector/WORK_ORDER.md`.
- **5 `uia.actor`** — UI Automation Actor: invoke/toggle/select/expand/collapse/setvalue/focus on an
  element located by automation id / name / control type / inspector child-path. Kept **separate** from
  inspection; UIA control patterns only (no synthetic input); `-DryRun`/`-WhatIf`; `parallel_safe:false`
  (first side-effecting skill). ***MVP complete*** — `action.md`/`action.json`; tests **26/26** incl. live
  invoke/toggle/setvalue self-verified against a WinForms probe (2026-07-24). Work order:
  `modules/05-uia-actor/WORK_ORDER.md`. See DECISION_LOG D-0011.
- **6 `capture.screen`** — Screenshot & Region Capture: resolve monitor (`index|all|primary`) / window
  (hwnd|pid|title) / app (process name) / explicit rectangle → one virtual-desktop rect, then GDI capture →
  **PNG** (or JPG q90) + `capture.json`/`capture.md`. Read-only (`parallel_safe:true`, `screen:true`),
  Per-Monitor-V2 DPI aware, multi-monitor. ***MVP complete*** — tests **39/39** via the executor incl. a live
  window capture self-verified against a WinForms probe (2026-07-24). Work order:
  `modules/06-capture-screen/WORK_ORDER.md`. See DECISION_LOG D-0014.

## Modules 7–9 — Local model foundation (provisional)  ← all MVP complete
- **7 `model.gateway`** — Local Model Gateway. ***MVP complete*** — common interface that runs local **LLMs**
  (GGUF) via the llama.cpp **`llama-server`** (start→/health→/v1/chat/completions→kill), selected from a
  declarative `models.json` by `-Model` id or a `-Tier` alias. Declares STT/TTS/embedding (staged, wired in
  their own modules; `model_not_wired` otherwise). First **stochastic/mixed** skill — populates
  `model_provenance` + a generation-completeness `confidence` (→ review queue when < 0.5). `parallel_safe:false`.
  **Tests 28/28 via executor (2026-07-24)** incl. live generation on staged 0.5B/1.5B, truncation→review-queue,
  wrapper, and clean server teardown. Work order: `modules/07-model-gateway/WORK_ORDER.md`. See D-0015, D-0016.
- **8 `classify.batch`** — Batch Classification & Sorting. ***MVP complete*** — the **first real consumer of
  `model.gateway`**. Three modes over a list of `{id?,text}` items: `classify` (exactly one label from a closed set,
  = routing/sorting), `multilabel` (zero+ labels), `extract` (named fields → JSON). Calls the gateway **once per
  item** (`-Tier weak` default) at temp 0 / fixed seed; parses the completion; computes a per-item classification
  **confidence** (documented completeness+validity heuristic, NOT calibrated); groups items (`label→[ids]`); appends
  below-threshold items to `review_queue.jsonl` (`flagged_by:"classify.batch"`, per-item `source_ref`) and
  **suppresses** the gateway's own review writes. `determinism:"mixed"`, `batch:true`, `parallel_safe:false`.
  **Tests 33/33 via executor (2026-07-24)** — error paths, live classify/extract, tier+explicit-model resolve,
  review routing + suppression, wrapper, no orphaned server. Work order: `modules/08-classify-batch/WORK_ORDER.md`.
  See D-0017. Follow-on: warm-worker/intra-batch prompt for throughput; calibrated confidence; a `sort.files` mover.
- **9 `review.processor`** — Review Queue Processor. ***MVP complete*** — the **first consumer/drainer** of the
  review queue (now fed by both `model.gateway` and `classify.batch`). Selects OPEN items (bounded by `-MaxItems`;
  `-FlaggedBy`/`-Reason`/`-Ids` filters) and, for each, feeds a **stronger** local model (default `-Tier mid`=3B;
  `strong`=27B) via `model.gateway` **only** the distilled item — its `reason`/`requested`/`weak_result` plus a
  bounded fragment resolved from `source_ref` (classify.batch `classified.json#id` → the closed label set + that
  item; model.gateway `exchange.json` → bounded request/output) — **never the whole batch** (D-0007). Parses a
  small JSON verdict, computes a structural reviewer confidence, then **resolves** the item (fills `resolution`+
  `status`) or **escalates** it (`status:"escalated"`, `escalated_to:"frontier"` — a status transition, not a
  frontier call) when unsure/unparseable. Writes the live queue **in place** (re-read-before-atomic-replace;
  original flagging fields preserved; producer/malformed lines verbatim) **plus** an append-only
  `review_resolved.jsonl` (`lifeorch.review.resolution/0.1`); `-DryRun` writes nothing. Suppresses the child
  gateway's own review writes. `determinism:"mixed"`, `batch:true`, `parallel_safe:false`. **Tests 34/34 via the
  executor (2026-07-24)** incl. live `mid`(3B) adjudication, forced escalation, dry-run no-op, source-ref
  resolver, and a live `strong`(27B) end-to-end at the tuned `gpu_layers=32`. Also **tuned the 27B**
  (`gpu_layers` 28→32; sweep + timings recorded). Work order: `modules/09-review-processor/WORK_ORDER.md`.
  See D-0018. Follow-on: frontier drain of `escalated` items (routing #24); resolved-item compaction; warm worker;
  strong-tier prompt/max_tokens tuning for parseable verdicts.

## Modules 10–13 — Audio (**all MVP complete** — the full audio track: ingest → STT → TTS → voice loop)
- **10 `audio.ingest`** — Audio Ingest / Normalize & Convert. ***MVP complete*** — the **first audio-track
  module** and the first skill to **wrap an external binary** (`ffmpeg`/`ffprobe`). Normalizes+converts one
  audio/media file (first audio stream; audio extracted from video) to a requested `-Format` (wav/mp3/flac/opus/
  ogg/m4a) + `-SampleRate` + `-Channels` + `-SampleFormat` (wav) with optional `-Loudness` (`none`/`peak`/`ebu`
  R128). **Defaults = whisper-ready 16 kHz mono s16 WAV** (so Module 11 consumes it directly). `ffprobe` resolved
  as the **sibling of the resolved `ffmpeg`** to dodge the Python `Scripts\ffprobe.exe` shim.
  `determinism:"deterministic"` (confidence null), `parallel_safe:true`, `batch:false`. `audio.<ext>`/`ingest.json`/
  `ingest.md` artifacts. **Tests 43/43 via the executor** (`m10-test-001`, exit 0, ~17s) incl. all six formats
  (codec + magic verified), keep-source, EBU + peak loudness, five error paths, and the Module 1 wrapper;
  pre-shipped off-machine on cloud ffmpeg 6.1 (same portable harness, 43/43). Work order:
  `modules/10-audio-ingest/WORK_ORDER.md`. See D-0019. Follow-on: batch/directory ingest; trimming/segmentation/VAD
  (→ #13); denoise/high-pass.
- **11 `speech.stt`** — Speech-to-Text Transcription (timestamped, whisper.cpp). ***MVP complete*** — the **second audio
  module** and the first **stochastic/mixed** skill to wrap a local **model binary**. Wraps `whisper-cli -ojf` to turn one
  audio file into timestamped segments `{index,t0_ms,t1_ms,t0,t1,text,confidence,token_count,low_confidence}`; resolves the
  model (`stt.whisper.base-en`) + CLI (CUDA build preferred, CPU fallback) from `models.json`; **normalizes input via
  `audio.ingest`** (`-Normalize auto|always|never` — `auto` re-encodes only when not already WAV/16 kHz/mono/s16).
  **Confidence = mean whisper token probability `p`** over content tokens (per-segment + overall); populates
  `confidence` + `model_provenance`. **Third review-queue producer** — flags low-confidence segments
  (`flagged_by:"speech.stt"`, bounded by `-MaxReviewSegments`; `verify_no_speech` guard on empty results).
  `determinism:"mixed"`, `parallel_safe:false` (binds CUDA), `batch:false`. Artifacts `whisper.json`/`.srt`/`.txt` +
  `transcript.json`/`.md`. **Tests 27/27 via the executor** (`m11-test-001`, exit 0, ~14 s) — live jfk.wav transcription
  (base.en on CUDA, rtf ≈ 0.07), per-segment confidence, review routing, both normalization branches (real `audio.ingest`
  child), error paths, and the Module 1 wrapper; **pre-shipped off-machine** on the cloud Linux box (pwsh 7.4.6 AST-parse
  + a mock-whisper harness driving the *real* skill against a captured jfk fixture, 27/27) before any bytes shipped.
  Work order: `modules/11-speech-stt/WORK_ORDER.md`. See D-0020. Follow-on: warm whisper-server; batch/directory;
  VAD/diarization (→ #13); calibrated/semantic confidence; larger/multilingual model + `tiers.stt`.
- **12 `speech.tts`** — Text-to-Speech Synthesis (Qwen3-TTS CustomVoice). ***MVP complete*** — the **third audio module**
  and the **first skill to drive a Python model** (vs. the whisper.cpp / llama.cpp binaries). A Python worker
  (`tts_infer.py`, under the speech venv) drives `qwen_tts.Qwen3TTSModel.generate_custom_voice(text, speaker, language,
  instruct)` (bf16 + `sdpa` on the RTX 2080 Ti → `(wavs, sr=24000)`); a PowerShell wrapper (`Invoke-SpeechTts.ps1`)
  reads the worker's **meta file** (robust to ML-library stdout chatter) and builds the envelope. Produces a 24 kHz mono
  PCM16 `speech.wav` (optional `-Format`/`-SampleRate` via `audio.ingest`). Registry-driven model resolution
  (`tts.weak.qwen3-0p6b` default, `tts.strong.qwen3-1p7b`; engine `transformers`, `engine_env` = venv python).
  **Confidence** = a synthesis-completeness heuristic (duration vs. input length); **fourth review-queue producer**
  (flags failed/too-short synthesis, `verify_synthesis`). `determinism:"mixed"`, `parallel_safe:false` (binds CUDA),
  `batch:false`. Artifacts `speech.wav` + `tts.json`/`tts.md`. **Tests 25/25 via the executor** (`m12-test-001`, exit 0,
  ~132 s) — live English synthesis (speaker Ryan, 24 kHz mono, conf 0.9), review routing, mp3 conversion via the real
  `audio.ingest` child, error paths, and the Module 1 wrapper; live smoke `m12-smoke-001` (5.52 s, rtf ≈ 5.2, cuda:0).
  **Pre-shipped off-machine** on cloud pwsh 7.4.6 (AST-parse + `py_compile`) with a stdlib mock python worker driving the
  *real* skill (25/25) before any bytes shipped. Probe-first (`m12-probe-001/002`) confirmed the venv + inference API by
  a live synthesis before coding. `models.json` gained `defaults.tts`/`tiers.tts` (additive; Module 7 re-verified 28/28).
  Work order: `modules/12-speech-tts/WORK_ORDER.md`. See D-0021. Follow-on: warm TTS worker; voice clone/design;
  batch/long-form; the strong 1.7B tier; calibrated confidence; SSML.
- **13 `voice.live`** — Voice Interaction Loop. ***MVP complete*** — the **capstone of the audio track** and the first
  skill to **compose several stochastic model skills end-to-end**. Given one input speech file it runs a voice turn:
  `speech.stt` transcribes (whisper segmentation = utterance/VAD; zero segments → `speech_detected:false`) → optional
  `model.gateway` answer (`-Respond`) → optional `speech.tts` reply to `reply.wav` (`-Speak`/`-ReadbackTranscript`).
  Children are spawned as pwsh with overridable paths and their envelopes parsed — **it reimplements nothing**. Envelope
  `confidence` = STT transcript confidence; `model_provenance` = the aggregate of all child models (stage-tagged).
  **Orchestrator, not a review producer** — it redirects children's review writes to an in-artifact `child_review.jsonl`
  by default. `determinism:"mixed"`, `parallel_safe:false`, `batch:false`; no new model / no `models.json` change.
  **Live mic capture / streaming is a non-goal** (no mic assumed; file-driven MVP); standalone VAD deferred (no VAD ggml
  model staged). **Tests 21/21 via the executor** (`m13-test-001`, exit 0) — a live full turn on `samples\jfk.wav`
  (transcript → LLM answer → `reply.wav`, `model_provenance` ≥ 3, all stages ok), readback, error path, Module 1
  wrapper; live smoke `m13-smoke-001` (heard the JFK line, answered, 12.56 s reply; stt 1.8 s / respond 2.7 s / speak
  54 s). **Pre-shipped off-machine** on cloud pwsh 7.4.6 with a mock-children harness driving the real orchestrator
  (23/23). Work order: `modules/13-voice-live/WORK_ORDER.md`. See D-0022. Follow-on: mic `audio.capture` + streaming
  loop; standalone VAD (stage a model); multi-turn + memory; a warm-worker pool so a turn avoids three cold model loads.

## Modules 14–18 — Image & document perception (**all MVP complete** — OCR + pixels/hashes + objects + VLM interpretation, fused by #18)
- **14 `ocr.layout`** — OCR + bounding boxes + reading order. ***MVP complete (2026-07-25)*** — the **first perception
  module** and the first **parallel-safe** stochastic/mixed perception skill. Recognizes the text in one image and returns
  it with **per-word pixel bounding boxes** and **lines in reading order** (+ text angle, image dims). Drives the system
  **`Windows.Media.Ocr`** engine (zero install, native, `en-US` recognizer, `MaxImageDimension=10000`) inside a **Windows
  PowerShell 5.1 worker** (`ocr_worker.ps1`) — pwsh 7 cannot load the WinRT projection here (`m14-probe-001`) — with a
  **meta-file hand-off** to the pwsh-7 wrapper (`Invoke-OcrLayout.ps1`), the D-0021 pattern in its PS-5.1 variant.
  Registry-driven (`ocr.windows.media`, `wired:false` for the gateway — decoupled per D-0020). **Confidence** = a
  documented legibility heuristic (Windows.Media.Ocr exposes no per-word confidence); **fifth review-queue producer**
  (`verify_ocr` page-level / `verify_no_text` guard, `flagged_by:"ocr.layout"`). **Composes `capture.screen` (Module 6)**
  via `-Capture` to OCR the live screen. `determinism:"mixed"`, `parallel_safe:true`, `batch:false`. Artifacts
  `ocr.json`/`ocr.md`. **Tests 30/30 via the executor** (`m14-test-003`, exit 0) — live OCR of a text fixture (words+boxes
  +reading order), review routing, no-text guard, error paths, the Module 1 wrapper, and the live `capture.screen`
  composition; real-registry smoke `m14-smoke-001` (7 words, conf 0.9, correct text); **pre-shipped off-machine** on cloud
  pwsh 7.4.6 (AST-parse + a mock-worker harness driving the *real* wrapper against a captured real meta, 28/28) before any
  bytes shipped. `models.json` gained `defaults.ocr`/`tiers.ocr` + `ocr.windows.media`/`ocr.tesseract` (additive; Module 7
  re-verified 28/28). Work order: `modules/14-ocr-layout/WORK_ORDER.md`. See D-0023. **Tesseract** (installed) is declared
  as `ocr.tesseract` for a second-engine + calibrated-confidence follow-on. Follow-on: wire Tesseract/a VLM (#17) engine;
  overlay PNG; `MaxImageDimension` downscale; multi-column reflow; batch/PDF OCR.
- **15 `image.util`** — resize/crop/convert/meta/hash/similarity/tile. ***MVP complete (2026-07-25)*** — the **second
  perception module** and the **first deterministic perception skill** (like `audio.ingest`/`fs.observer`:
  `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`, **not** a review-queue producer). One image
  in -> metadata + hashes always, plus one optional op: **resize** (fit/fill/exact or a single `max_dimension`, reporting
  `scale_x`/`scale_y`), **crop** (pixel rect / normalized / named region), **convert** (png/jpg/webp/bmp/tiff + quality),
  **tile** (grid or fixed size + overlap), **similarity** (pHash/dHash Hamming + score). Metadata = format/mode/dims/
  has_alpha/dpi/EXIF-lite; hashes = **sha256** + **pHash** + **dHash** (64-bit, version-stable). A **Pillow+numpy Python
  worker** (`image_worker.py`) under the **system python** + a pwsh-7 wrapper (`Invoke-ImageUtil.ps1`) with a meta-file
  hand-off (D-0021 pattern, deterministic variant). **Probe-first** (`m15-probe-001`). **NOT a `model.gateway` model — no
  `models.json` change** (a tool, like ffmpeg for `audio.ingest`). `parallel_safe:true`, `batch:false`. Artifacts
  `image.json`/`image.md` + produced image(s). **Tests 48/48 via the executor** (`m15-test-001`, exit 0) — resize scale
  factors, crop rect/normalized/region, all five convert formats, tile grid+size, similarity, six error paths, wrapper;
  **pre-shipped off-machine** on the cloud box (real worker, Pillow 12.2, 48/48 — the real-engine-on-cloud gate, like
  `audio.ingest`). Work order: `modules/15-image-util/WORK_ORDER.md`. See D-0024. Follow-on: the `ocr.layout` downscale-
  then-rescale-boxes + box-overlay compositions (now unblocked); a draw/annotate op; batch/directory; rotate/flip/auto-orient.
- **16 `detect.objects`** — object detection → class boxes + confidence. ***MVP complete (2026-07-25)*** — the **third
  perception module** and the **first onnxruntime-backed** stochastic/mixed perception skill; **parallel-safe** (default CPU
  provider). Detects objects in one image → `detections[{class,class_id,score,low_confidence,box{x,y,width,height}}]` with a
  **real per-detection confidence** (YOLOX objectness × class prob). Runs a staged **ONNX** detector (default
  `detect.yolox.nano`, COCO-80, Apache-2.0, staged on F:) via **onnxruntime** in a Python worker (`detect_worker.py`) under
  the system python + a pwsh-7 wrapper (`Invoke-DetectObjects.ps1`) with a meta-file hand-off. Registry-driven
  (`type=detector`, `wired:false` for the gateway — decoupled per D-0020/D-0023). **Confidence** = the best detection's real
  score; **sixth review-queue producer** (`verify_detections` low-confidence / `verify_no_objects` guard,
  `flagged_by:"detect.objects"`). **Composes `capture.screen` (#6)** via `-Capture` and **`image.util` (#15)** via
  `-MaxDimension` (downscale-then-rescale-boxes). `determinism:"mixed"`, `parallel_safe:true` (CPU; `-Provider cuda|dml` is
  not), `batch:false`. Artifacts `detect.json`/`detect.md`. **Probe-first** (`m16-probe-001`: staged the model to F: +
  confirmed live CPU inference, detections identical to the cloud box). **Tests 38/38 via the executor** (`m16-test-001`,
  exit 0) — live detection (boxes/scores/classes), class filter, both review paths, the image.util downscale + capture
  compositions, five error paths, the Module 1 wrapper; **pre-shipped off-machine** on the cloud box (real worker,
  onnxruntime 1.25, 34/34 — the real-engine-on-cloud gate, like `image.util`). `models.json` gained `defaults.detector`/
  `tiers.detector` + `detect.yolox.nano`/`detect.yolox.tiny` (additive; Module 7 re-verified 28/28). **Side fix:** surfaced +
  fixed a latent `image.util` JPEG-`dpi` JSON bug (Module 15 re-verified 48/48). Work order:
  `modules/16-detect-objects/WORK_ORDER.md`. See D-0025. Follow-on: overlay/annotated image (needs an image.util draw op);
  batch/directory; larger tiers / RT-DETR; GPU/warm worker; calibrated confidence; tracking (#20).
- **17 `image.interpret`** — local VLM captions / VQA / screen interpretation. ***MVP complete (2026-07-25)*** — the **fourth
  perception module** and the block's first **semantic/free-text** skill. Interprets one image with a local **VLM** →
  `interpretation.text` (modes `caption`|`describe`|`vqa`|`screen`). Backend = the already-staged llama.cpp **`llama-server`
  (b8661) in multimodal mode** (`-m <vlm.gguf> --mmproj <projector.gguf>` → `/v1/chat/completions` with an OpenAI-style
  `image_url` base64 data URI) — the same engine `model.gateway` (#7) drives, extended with the projector, so the wrapper is
  **pure PowerShell** (no python worker). Registry-driven (`type=vlm`, **decoupled from the gateway `wired` gate** per
  D-0020/D-0023/D-0025); default `vlm.qwen2p5-vl-3b` (Qwen2.5-VL-3B-Instruct GGUF Q4_K_M + mmproj-f16, **Apache-2.0**, staged
  to F:). **`parallel_safe:false`** (binds a loopback port + CUDA/VRAM — unlike the parallel-safe #14–16). **Confidence** = a
  documented completeness + refusal + non-empty heuristic (stop 0.7 / length 0.4 / refusal 0.3 / empty 0.1); **seventh
  review-queue producer** (`verify_interpretation`: `low_confidence`/`needs_strong_review`(refusal)/`failed_transform`(empty),
  `flagged_by:"image.interpret"`). **Composes `capture.screen` (#6)** via `-Capture` and **`image.util` (#15)** via
  `-MaxDimension` (downscale before sending). `determinism:"mixed"`, `batch:false`, `streaming:false`. Artifacts
  `interpret.json`/`interpret.md`. **Probe-first** (`m17-probe-001` mmproj support; `m17-probe-002` staged the VLM to F: +
  live-verified an accurate dog.jpg caption at ~111 tok/s; `m17-probe-003` captured a real response for the test seam).
  **Tests 48/48 via the executor** (`m17-test-001/002`) — seam tests (captured-real response) + real `llama-server` VLM
  describe/VQA + the image.util downscale + the capture.screen compositions + the review paths + error paths + the Module 1
  wrapper; **pre-shipped off-machine** on the cloud box (real wrapper + captured-real-response seam + real image.util,
  40/40). `models.json` gained `defaults.vlm`/`tiers.vlm` + `vlm.qwen2p5-vl-3b` (additive; **Module 7 re-verified 28/28**).
  Work order: `modules/17-image-interpret/WORK_ORDER.md`. See D-0026. Follow-on: warm VLM server; logprob/calibrated
  confidence; batch/directory; multi-image/multi-turn; open-vocab grounding boxes (#16 follow-on); a 7B tier / the
  transformers-venv backend; wiring the VLM as a second `ocr.layout` engine.
- **18 `image.index`** — fuse 14–17 → per-image machine index + human card. ***MVP complete (2026-07-25)*** — the **capstone of
  the perception block (14–18)** and the **second skill to compose several stochastic perception skills end-to-end** (after
  `voice.live` #13). Given one image it fuses the children into one record: **`image.util` (#15) ALWAYS** (metadata + `sha256`/
  `pHash`/`dHash`, the deterministic backbone), + optional **`ocr.layout` (#14, `-Ocr`)** text+boxes, **`detect.objects` (#16,
  `-Detect`)** class boxes+scores, **`image.interpret` (#17, `-Interpret`)** a VLM interpretation; **`-All`** runs the three,
  **`-Capture`** sources the image once via `capture.screen` (#6), **`-MaxDimension`** passes through to detect+interpret. An
  **orchestrator** that **reimplements nothing**: spawns each child as pwsh, parses its envelope, **aggregates stage-tagged
  `model_provenance`**, runs children **sequentially** (avoids the VLM's VRAM/port contention). **Orchestrator, NOT a review
  producer** (like #13): **redirects** children's review writes to an in-artifact `child_review.jsonl` and does not re-flag — the
  **producer set stays at seven** and the canonical queue is untouched. Envelope `confidence` = the **min** stochastic-stage
  confidence (weakest link; `null` when only image.util ran); `determinism:"mixed"`, **`parallel_safe:false`** (binds CUDA/VRAM +
  a port via `-Interpret`), `batch:false`, `streaming:false`. Artifacts `index.json`/`index.md`. **No new model / no `models.json`
  change / no Module 7 re-verify** (it composes existing skills). **Tests 41/41 via the executor** (`m18-test-002`, exit 0) —
  live full index on `dog.jpg` (meta+hashes + OCR + 5 detections + a real VLM description, 3 stage-tagged provenance,
  min-confidence fusion), default image.util-only, selective/`-All`/error paths, the child-review **redirect** with the canonical
  queue **verified untouched (0→0)**, the Module 1 wrapper, no orphaned `llama-server`/python; **pre-shipped off-machine** on the
  cloud box (a **mock-children** harness — `tests/mock-child.ps1` branching on the `-ArtifactRoot` leaf — driving the *real*
  orchestrator, 40/40). Work order: `modules/18-image-index/WORK_ORDER.md`. See D-0027. Follow-on: concurrent children / a shared
  warm-worker pool; batch/directory; cross-stage grounding (detections↔OCR↔caption); an overlay card image (needs an image.util
  draw op); persisting indices into `artifact.search` (#23).

## Modules 19–22 — Video (provisional)
- **19 `media.decompose`** audio/subs/scenes/keyframes/clips/meta/proxies · **20 `track.objects`** identity
  across frames · **21 `video.timeline`** transcription+scenes+OCR+keyframes+detections+tracks → searchable
  timeline · **22 `video.interpret`** selective frames/clips → local VLM.

## Modules 23–26 — Higher integration (provisional, later)
- **23 `artifact.search`** search over all local-skill artifacts · **24 `route.tasks`** model/tool task
  router (type/confidence/quality/cost/time) · **25 `observe.broker`** route a desktop-observation question
  across fs/proc/UIA/OCR/recognition/screenshot · **26 `skill.orchestrator`** compose skills into workflows
  without embedding each implementation in frontier context.

---

**Layout:** each module lives in `modules/<NN>-<short-name>/` (number-prefixed for ordering),
self-contained: code + `skill.json` + `WORK_ORDER.md` + `README` + tests in the one folder.

**Rule:** only **one** module is `In progress`/`Active` at a time (see `CURRENT_STATE.md`). When an entry
becomes active, expand it and give it a work order; leave the rest provisional until reached.
