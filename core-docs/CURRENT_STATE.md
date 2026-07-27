# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP build-out — **re-prioritized 2026-07-25 (D-0029)** to a usable-local-core-first order (see `MODULE_ROADMAP.md → Build priority`). Two build tracks: **Modules** (`modules/`, backend capability) and **Widgets** (`widgets/`, the human-interface layer); the full long-horizon destination is `ARCHITECTURE_MAP.md`.
- **Adaptive Resource Governor (agent.local #21) -- Phase 1 DONE (D-0043):** the local DECISION floor was raised from the `[tiny,weak,mid]` ladder to a **mid-only floor**. Measured root cause (m30-exp3-001): the low-floor escalator ladder makes the competent 3B JUDGE the weak tiers' answer and ANCHOR on it (both runs accepted at `mid`, yet the ladder looped `gen.image` 6 steps/140 s and never finished; mid-only finished 3 steps/clean). Live default now: dog goal `-Route` -> completed 3/8 steps / **48 s** / one gen.image / **dog on the real Desktop** (`m31-p1-default-001`). Added a **`-Profile` knob (frugal|floor|max)** = the governor's rungs, **un-refused the 27B** in `route.tools` (soft-warn, not throw), default `max_steps` 4->8. `max` = mid decisions + **27B generation** (escalating the DECISION classifier to the 27B re-broke it with empty output, `m31-p1-max-001` -- a Phase 3 concern). **Phase 2 (warm/persistent model server)** and **Phase 3 (auto-ramp controller)** are the next two units. See `ADAPTIVE_RESOURCE_GOVERNOR.md`.
- **Strong tier is now Qwen3.5-9B, fully GPU-resident (D-0044).** Replaced the split-brain 27B (partial offload, ~2 tok/s, timed out at 30 min) with **Qwen3.5-9B Q4_K_M** -- loads fully on the RTX 2080 Ti at **~6.9 GB VRAM** (ngl 99, ~4.3 GB headroom) -> **GPU-bound ~68 tok/s**, clean terse JSON output. It is a hybrid attention-SSM arch the default engine b8661 cannot load, so a side-by-side **llama.cpp b10092 (CUDA 12.4, self-contained)** was staged and the 9B entry pins `engine_path` to it (every other tier stays on b8661 -- zero blast radius). A general gateway **`no_think`** hook (append `/no_think`) makes the 9B emit non-thinking output (default flags left reasoning ON -> empty). Strong is GENERATION-only; decisions stay at the mid floor. **Residual (D-0032) -- RESOLVED (D-0046):** a deterministic terminator + repeat-action guard in agent.local now blocks a premature `finish` until every routed planned tool has succeeded (and never re-runs a done tool). Live: the dog goal `-Route` at the FLOOR default landed on the real Desktop 3/3 (the terminator fired once, forcing fs.manage after the model tried to finish early); 87/87 tests. NEW residual: `-Profile max` still does NOT land -- the 9B (gen_tier=strong) arg-gen returns non-JSON (`arg_parse_failed`) every step so tools never get valid args (a 9B/gateway defect, NOT the terminator; floor with gen_tier=mid is reliable). See D-0046. The 27B entry is retained (reachable via -Model) but is no longer the tier. See D-0044 + ADAPTIVE_RESOURCE_GOVERNOR.md.
- **Active module:** **Widget #3 -- the Verification Console (in progress, D-0050)** -- the human-AUDIT surface for the offload / verify-cost spine; Claude writes a verification packet and Nicholas runs + checks it locally through Invoke-Skill.ps1, exporting a verification-result JSON Claude reads back. Recent history: **Module 0 job-runner SHIPPED (D-0048): `Invoke-DevShip.ps1` + `exec-job.sh`** -- one executor job gate+commits a unit (sha + AST + tests, fail-closed) and returns a compact JSON; dogfood-committed by dev.ship itself (`5644b9ba`), 27/27 + 24/24. **Widget #2 (Module Launcher / Registry Browser) SHIPPED 2026-07-27 (D-0049, commit `a699ac6`; 62/62 cloud + 71/71 `-Live` via the job-runner; **post-ship UI fix `c509e571` -- registry double-wrap + splitter layout, 64/64 + 75/75**). Next unit = Phase B Widget #3 -- the Verification Console (D-0050)** (`MODULE_ROADMAP.md -> Build priority`). **Modules 0–25 complete** (0 executor · 1 `skill.bootstrap` · 2
  `fs.observer` · 3 `proc.observer` · 4 `uia.inspector` · 5 `uia.actor` · 6 `capture.screen` · 7 `model.gateway` ·
  8 `classify.batch` · 9 `review.processor` · 10 `audio.ingest` · 11 `speech.stt` · 12 `speech.tts` · 13 `voice.live` ·
  14 `ocr.layout` · 15 `image.util` · 16 `detect.objects` · 17 `image.interpret` · 18 `image.index` · 19 `logic.escalator` · 20 `doc.io` · 21 `agent.local` · **22 `gen.audio`** · 23 `gen.image` · 24 `gen.music` · 25 `gen.video`), plus **Module 00.1 — Executor Watchdog & Recovery (`exec.watchdog`)** (infrastructure). **The full
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
- **Module 22 -- Local Audio Generation (`gen.audio`) is MVP complete this session (Phase A #4, D-0033)** -- the **cheapest generator** and the audio counterpart of `image.util`: a **deterministic, procedural ffmpeg synthesizer** (no model, no download, CPU-only, `parallel_safe:true`). One `-Kind` per call -- `tone`/`chord` (sine/square/triangle/sawtooth, by Hz or equal-temperament note name), `noise` (white/pink/brown/blue/violet/velvet; seeded → reproducible), `sweep` (linear chirp), `silence` -- with duration/sample-rate/channels/amplitude/fade shaping, encoded directly to wav/mp3/flac/opus/ogg/m4a (codec map == `audio.ingest`, reusing its ffmpeg machinery). Pure PowerShell over the present ffmpeg 8.1; **NOT a review producer** (canonical queue before==after 1→1); no `models.json` change / no Module 7 re-verify. **Probe-first** (`m22-probe-001`: ffmpeg lavfi synthesis verified end-to-end; **no** neural audio-gen stack staged -- audiocraft/diffusers/stable_audio_tools/audioldm/TTS/bark all absent → neural text-to-audio deferred). Pre-shipped off-machine (cloud pwsh 7.4.6 + real cloud ffmpeg 6.1.1, **41/41**) → 8 files sha256 byte-exact + AST-parse OK on target → **43/43 live** via the executor (`m22-test-001`) incl. the Module 1 wrapper. See D-0033.
- **Module 23 -- Local Image Generation (`gen.image`) is MVP complete this session (Phase A #5, D-0034)** -- the generator track's **first neural** member and an early standalone build of the #44 family: it turns a text prompt into one image with a local **Stable Diffusion 1.5** pipeline (`diffusers` `StableDiffusionPipeline`, fp16, CUDA) driven by a **Python worker** (`gen_image_infer.py`, under the speech venv) with a **meta-file hand-off** to a PowerShell wrapper (`Invoke-GenImage.ps1`) -- the D-0021 `speech.tts` pattern. Registry-driven (`image.sd15`, `type=image-gen`, `engine=diffusers`, decoupled from the gateway `wired` gate); `determinism:"mixed"`, `parallel_safe:false` (binds CUDA/VRAM), `batch:false`. **Confidence** = a generation-completeness / non-blank heuristic from the image pixel std; **eighth review-queue producer** (below-threshold / blank / failed -> `verify_generation`, `flagged_by:"gen.image"`). Controls: `-Prompt`/`-NegativePrompt`, `-Width`/`-Height` (512; mult 8, 128..1024), `-Steps` (20, DPM++), `-Guidance` (7.5), `-Seed` (-1=random, recorded; a fixed seed is byte-reproducible on this GPU), `-Scheduler` (dpm++|euler|euler_a|ddim), `-Format` (png|jpg|webp). **Probe-first** (`m23-probe-001/002`): no diffusion checkpoint existed on F:/E:; **installed `diffusers` 0.35.2 into the speech venv** (torch 2.11+cu128 already there; the install added only diffusers+importlib_metadata+zipp; **Module 12 re-verified** -- torch/transformers unchanged, `qwen_tts` still imports) and **staged SD 1.5 fp16** (~2.13 GB) to F:, then **live-generated** a 512x512 image in 2.8 s (VRAM peak 2.61 GB) before coding. Pre-shipped off-machine (cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper, **42/42**) -> 10 files sha256 byte-exact + AST-parse OK on target -> **32/32 `-Live`** via the executor (`m23-test-005`: real SD generations, same-seed byte-reproducible (std 64.987==64.987), real JPEG, canonical `review_queue.jsonl` 1->1, 0 orphaned python) -> **Module 7 re-verified 28/28** (`m23-m7regress-001`). `models.json` gained `defaults.image`/`tiers.image` + `image.sd15`. SD 1.5 is CreativeML OpenRAIL-M (FLUX.1-schnell / SDXL are documented follow-on tiers). **Harness fix:** the live test's pwsh resolution now uses `$PSHOME` (`GetCurrentProcess().MainModule` returns `dotnet.exe` under the .dotnet tools pwsh shim). See D-0034.
- **Module 24 -- Local Music Generation (`gen.music`) is MVP complete this session (Phase A #4, D-0035)** -- the generator track's music slot and the **second neural** generator: it turns a text prompt into one short **instrumental** clip with a local **MusicGen Small** (transformers `MusicgenForConditionalGeneration`, CUDA) driven by a **Python worker** (`music_gen_infer.py`, under the speech venv) with a **meta-file hand-off** to a PowerShell wrapper (`Invoke-GenMusic.ps1`) -- the D-0021/D-0034 pattern. Registry-driven (`music.musicgen-small`, `type=music-gen`, `engine=transformers`, decoupled from the gateway `wired` gate); `determinism:"mixed"`, `parallel_safe:false`, `batch:false`. Produces 32 kHz mono PCM16 WAV (peak-normalized to <=0.99); optional non-wav `-Format`/`-SampleRate` via a child `audio.ingest` (#10). **Confidence** = a generation-completeness / non-silent heuristic from the audio RMS; **ninth review-queue producer** (below-threshold / silent / failed -> `verify_generation`, `flagged_by:"gen.music"`; set 7/8/11/12/14/16/17/23/24). Controls: `-Prompt`, `-Duration` (1..30 s -> ~50 tok/s), `-Guidance` (3.0), `-Temperature`/`-TopK`/`-TopP`, `-Seed` (-1=random, recorded; a fixed seed is byte-reproducible on this GPU), `-Normalize`. **NO new library install** (transformers 4.57.3 already ships MusicGen) -> the speech venv is untouched, so **Module 12 is unaffected by construction** (not re-run) -- cheaper + lower-risk than gen.image's diffusers install. **Probe-first** (`m24-probe-001/002`): transformers has MusicGen, no music model staged; **downloaded + staged `facebook/musicgen-small` to F:** (~2.37 GB after pruning the redundant audiocraft-format weights; `m24-prune-001`) and **live-generated a 5.06 s clip in 7.6 s** (VRAM peak 2.4 GB, 32 kHz mono, seed byte-reproducible) before coding. Pre-shipped off-machine (cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper, **49/49**) -> 10 files sha256 byte-exact + AST-parse OK on target (`m24-verify-001`) -> **42/42 `-Live`** via the executor (`m24-test-002`: real MusicGen, same-seed byte-reproducible, mp3 + resample via the real `audio.ingest`, canonical `review_queue.jsonl` 1->1, 0 orphaned python) -> **Module 7 re-verified 28/28** (`m24-m7regress-001`). `models.json` gained `defaults.music`/`tiers.music` + `music.musicgen-small`. CC-BY-NC-4.0 (a precedented deviation, like SD 1.5's OpenRAIL-M). See D-0035.
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
- **Module 20 — Local Document I/O (`doc.io`) is MVP complete this session** — **Phase A #2 (D-0029)**, the cheap,
  high-utility **document primitive** a local model (the escalator #19, a future `agent.local`, Widgets, unattended
  executor tasks) calls to do real file work — the local counterpart to the frontier's Read/Write/Edit tools. **One
  skill, one op per invocation** (`-Op read|write|edit|append`): **read** (whole file or a 1-indexed inclusive
  `start_line..end_line` range + `max_bytes` cap → content + `{encoding,bom,eol,line_count,byte_count,char_count,
  sha256}`), **write** (create/overwrite; `overwrite`/`create_dirs`/`eol lf|crlf`), **edit** (exact-string
  `old_string`→`new_string`; default **exactly one** occurrence — `not_found`/`not_unique` otherwise — with
  `replace_all`/`expect_count` variants), **append** (`ensure_newline`/`create`). **Deterministic + a tool, not a
  model**: `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`, **NOT a review-queue producer**
  (the canonical `review_queue.jsonl` and the **seven-producer set (7/8/11/12/14/16/17) are untouched** — verified live,
  before==after); **pure PowerShell over cross-platform .NET — no external binary / Python / model / `models.json`
  change / Module 7 re-verify** (the leanest skill yet). **Safety model** on every mutation: **atomic** temp+rename
  writes (no torn files; no leftover `.docio-*.tmp`), an optional **`expect_sha256`** optimistic-concurrency
  precondition (`precondition_failed` — makes a local model's read→reason→edit loop safe against a lost update), a
  recoverable **`before.<ext>` pre-image** (+ `after.<ext>`; skipped >~8 MB / `-NoPreimage`), and **EOL preservation**
  (a CRLF file — like these core-docs — stays CRLF, by matching on an LF-normalized view and re-applying the file's EOL;
  `write` writes `eol`, default lf). **Encoding:** UTF-8 default; read auto-detects/strips a UTF-8/UTF-16LE/UTF-16BE BOM
  (reported); write = UTF-8 no BOM (contract §3); edit/append preserve the detected encoding+BOM; a binary (NUL) file is
  refused for read/edit/append (`binary_file`). Byte-level I/O (never `Environment.NewLine`/`Set-Content`/`Out-File`)
  keeps behavior identical on Windows and Linux. `parallel_safe:false` (first general external-file mutator — writes
  arbitrary caller-chosen paths; conservative MVP, D-0031), `batch:false`, `streaming:false`. **Tests 88/88 off-machine
  (cloud pwsh 7.4.6, the **real** skill + the **real** Module 1 wrapper — no mock, `.NET` file I/O is cross-platform,
  the strongest gate) + 88/88 `-Live` via the executor** (`m20-test-001`, exit 0) — every op + error path (`invalid_op`/
  `missing_parameter`/`input_not_found`/`path_is_directory`/`parent_not_found`/`already_exists`/`binary_file`/`not_found`/
  `not_unique`/`count_mismatch`/`precondition_failed`/`invalid_range`/`no_change`) + CRLF/LF/BOM/UTF-16 preservation +
  atomic (0 stray tmp) + pre-image recoverable + the named-param-overrides-`InputsJson` contract rule + the Module 1
  wrapper; 8 files sha256 byte-exact + AST-parse OK on the target. See **D-0031**.
- **Module 21 — Local Orchestrator / Agent (`agent.local`) is MVP complete this session** — **Phase A #3 (D-0029/D-0032)**,
  the local-orchestrator cost-offload keystone (the tight, useful MVP slice of `skill.orchestrator` #26). A **bounded,
  ReAct-style local agent loop**: given a natural-language **goal** it decides which Module (tool) to call, generates that
  tool's arguments, invokes it, observes the result, and repeats until it decides `finish` or a hard step budget is hit —
  **the frontier agent's tool loop, done locally.** **Decisions ("which tool next, or `finish`?") route THROUGH
  `logic.escalator` (#19)** as a closed-set `classify` task (labels = the registered tool names + `finish`), so the
  escalator's deterministic **in-set gate** guarantees a valid action (or surfaces `needs_frontier`) and its tiny→weak→mid
  ladder is the cost-offload; **argument generation + the final answer use `model.gateway` (#7)**; **tools are conforming
  Modules invoked as child skills** (the `image.index` #18 spawn-and-parse-envelope pattern) from a **declarative closed
  registry** (`tools.json`, ships **`doc.io` #20 + `fs.observer` #2**) — the registry **is** the sandbox (no arbitrary-shell
  tool). Guardrails (first skill where a local model chooses side-effecting actions): a **hard `max_steps` budget** (default
  4; exhausting → `status:"stopped"` + `needs_frontier:true`), a **`-DryRun` plan-preview** (invokes nothing), and
  `needs_frontier` surfaced as a status field (never a frontier call / queue write). **Orchestrator, NOT a review-queue
  producer** (like #13/#18/#19): redirects every child's review writes to an in-artifact `child_review.jsonl`; the canonical
  `review_queue.jsonl` and the **seven-producer set are untouched** (verified live, before==after). `determinism:"mixed"`,
  `parallel_safe:false`, `batch:false`, `streaming:false`; **no new model / no `models.json` change / no Module 7 re-verify**
  (it composes the wired tiers). **Tests 39/39 off-machine (cloud pwsh 7.4.6, the **real** orchestrator + a mock-children
  harness branching on the `-ArtifactRoot` leaf + the **real** Module 1 wrapper) + 39/39 the same harness `-Live` on Windows
  (`m21-test-001`, exit 0) + a REAL end-to-end run** (`m21-live-001`): goal "create hello.txt containing 'hi from
  agent.local'" → the agent chose `doc.io` **through the escalator**, the 3B generated the args, and **the file was written
  on disk with the exact content**; a second goal invoked `fs.observer`; **0 orphaned `llama-server`**, canonical queue
  untouched (1→1). 10 files sha256 byte-exact + AST-parse OK on the target (`m21-verify-001`). **Honest finding (reported
  plainly, per the escalator's ethos):** the tiny/weak/mid models **under-use the `finish` action** — both live goals ran to
  `max_steps` (re-doing the completed action) rather than self-terminating; the **hard `max_steps` budget caught it every
  time** (`stopped` + `needs_frontier`; the final answer still correctly reported the goal as achieved). This is exactly why
  the budget guardrail exists; **better termination (a deterministic goal-satisfied / repeat-action check, or a dedicated
  "are-we-done?" gate) is the #1 measured follow-on**, not expanded here. See **D-0032**.
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
- **diffusers (speech venv) -- installed 2026-07-25 (Module 23).** `diffusers` **0.35.2** added to the **speech venv** (`F:\My_Programs\Local_Computer_Speech_Large_Data\python_env`; torch 2.11+cu128, transformers 4.57, accelerate, safetensors, torchvision 0.26). Powers `gen.image` via the `StableDiffusionPipeline` (fp16, CUDA). The install added only diffusers + importlib_metadata + zipp; **torch/transformers/`qwen_tts` unchanged** (Module 12 safe). The system python is torch 2.2.1+**cpu** (no CUDA), so image generation runs under the speech venv only.
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

- **Image generator added 2026-07-25 (Module 23).** `image.sd15` -- **Stable Diffusion 1.5** in the diffusers **fp16** folder format (~2.13 GB: unet 1.64 GB + vae 0.16 GB + text_encoder 0.23 GB + tokenizer/scheduler/config), CreativeML OpenRAIL-M, downloaded from `stable-diffusion-v1-5/stable-diffusion-v1-5` (fp16 variant) and staged to `F:\...\LifeOrchestrator-Refresh_Large_Data\23-gen-image\stable-diffusion-v1-5\` (unet sha256 `c8390825...`). Type `image-gen`, engine `diffusers`, `engine_env` = the speech venv python, `wired:false` for the gateway; run via `gen.image` (M23). Staged + **load-and-generate verified live** (`m23-probe-002`: 512x512 in 2.8 s, VRAM peak 2.61 GB, non-blank).

- **Music generator added 2026-07-26 (Module 24).** `music.musicgen-small` -- **MusicGen Small** (transformers folder format, ~2.37 GB after pruning the redundant audiocraft-format weights: `model.safetensors` 2.36 GB + configs + tokenizer; `model.safetensors` sha256 `1bdc99d4...`), CC-BY-NC-4.0, downloaded from `facebook/musicgen-small` and staged to `F:\...\LifeOrchestrator-Refresh_Large_Data\24-gen-music\musicgen-small\`. Type `music-gen`, engine `transformers`, `engine_env` = the speech venv python, `wired:false` for the gateway; run via `gen.music` (M24). **No new library install** -- transformers 4.57.3 already ships `MusicgenForConditionalGeneration` (so the speech venv is unchanged and Module 12 is unaffected). Staged + **load-and-generate verified live** (`m24-probe-002`: a 5.06 s clip in 7.6 s, VRAM peak 2.4 GB, 32 kHz mono, seed byte-reproducible).

- **Video generator added 2026-07-26 (Module 25).** `video.animatediff-lightning` -- **AnimateDiff-Lightning 4-step** motion adapter (`animatediff_lightning_4step_diffusers.safetensors`, 907702248 bytes, sha256 `8f3330914edd8fc2ee5659e6944323858feb0ec21cc913789202d043f69b5e17`, CreativeML-OpenRAIL-M) downloaded from `ByteDance/AnimateDiff-Lightning` and staged to `F:\...\LifeOrchestrator-Refresh_Large_Data\25-gen-video\animatediff-lightning\`, run ON TOP OF the **SD 1.5 base reused from `gen.image` #23** (`23-gen-image\stable-diffusion-v1-5`, fp16). Type `video-gen`, engine `diffusers`, `engine_env` = the speech venv python, `wired:false` for the gateway; run via `gen.video` (M25). **No new library install** -- diffusers 0.35.2 already ships `AnimateDiffPipeline`/`MotionAdapter` (speech venv unchanged, Module 12 unaffected); MP4 via the present ffmpeg 8.1, GIF via Pillow. Staged + **load-and-generate verified live** (`m25-probe-002`: 16 frames 512x512 4-step in ~57 s warm, VRAM peak 4.75 GB full-GPU no offload, non-blank + strong motion, seed byte-reproducible).

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
- gen.audio (direct): `pwsh -NoProfile -File modules\22-gen-audio\Invoke-GenAudio.ps1 -Kind <tone|chord|noise|sweep|silence> [-Frequency <hz>|-Note <A4>] [-Frequencies|-Notes <csv>] [-Waveform <sine|square|triangle|sawtooth>] [-Color <white|pink|brown|blue|violet|velvet>] [-Seed <n>] [-FreqStart -FreqEnd] [-Duration <s>] [-SampleRate <hz>] [-Channels <1|2>] [-Amplitude <0..1>] [-FadeInMs -FadeOutMs] [-Format <wav|mp3|flac|opus|ogg|m4a>] [-SampleFormat <s16|s24|s32|flt>] [-Bitrate <e.g. 192k>]` (or `-InputsJson '<json {kind,...}>'`). Deterministic ffmpeg lavfi synthesis; writes `audio.<ext>`/`gen.json`/`gen.md`.
- User ops (click-to-run): `ops/*.bat` — start/stop/restart/status the executor and run tests; each writes
  output to `ops/out/` for the agent to read.
- Watchdog: `ops/start-watchdog.bat` (supervise), `ops/stop-watchdog.bat`, `ops/recover-executor.bat [-Force]`;
  direct `pwsh -NoProfile -File modules\00.1-exec-watchdog\Watch-Executor.ps1` / `...\Recover-Executor.ps1`.

## Current tests
- Module 25 (`gen.video`): `modules/25-gen-video/tests/Invoke-GenVideoTests.ps1` -- **46/46 `-Live` via the executor** (`m25-test-002`, exit 0) -- real AnimateDiff-Lightning generations (16 frames 512x512, non-blank pixel_std ~44 + strong motion, VRAM peak 4.75 GB full-GPU), same-seed byte-reproducible (identical sha256), mp4 (H.264 via ffmpeg) magic + a gif run, params echo, all validation error paths, review branches, the Module 1 wrapper; canonical `review_queue.jsonl` before==after, 0 orphaned python/llama-server. **Pre-shipped off-machine** on cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper (**54/54**). 10 files sha256 byte-exact + AST-parse OK on target (`m25-verify-001`); **Module 7 re-verified 28/28** (`m25-m7regress-001`).
- Module 24 (`gen.music`): `modules/24-gen-music/tests/Invoke-GenMusicTests.ps1` -- **42/42 `-Live` via the executor** (`m24-test-002`, exit 0) -- real MusicGen generations (32 kHz mono, seed byte-reproducible), params echo, error paths, review branches, the Module 1 wrapper, and live mp3 + resample via the real `audio.ingest`; canonical `review_queue.jsonl` before==after (1->1), 0 orphaned python/llama-server. **Pre-shipped off-machine** on cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper (**49/49**). 10 files sha256 byte-exact + AST-parse OK on target; **Module 7 re-verified 28/28** (`m24-m7regress-001`).
- Module 22 (`gen.audio`): `modules/22-gen-audio/tests/Invoke-GenAudioTests.ps1` — **43/43 via the executor** (`m22-test-001`, exit 0) — every kind, determinism (byte-identical re-runs), note mapping, all four waveforms, all six noise colors, the wav/mp3/flac/opus/ogg/m4a matrix, shaping, all error paths, the Module 1 manifest-validator + wrapper; **pre-shipped off-machine** on cloud pwsh 7.4.6 + real cloud ffmpeg 6.1.1 (41/41). 8 files sha256 byte-exact + AST-parse OK on target.
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
- Module 20: `modules/20-doc-io/tests/Invoke-DocIoTests.ps1` — **88/88 pass (cloud) / 88/88 (live)** (manifest +
  deterministic/parallel_safe=false/batch/streaming flags; write create/overwrite + sha256==disk + `already_exists` +
  `create_dirs` + `parent_not_found` + eol=crlf; read whole/range/`invalid_range`/`input_not_found`/`binary_file`/
  truncation; edit unique/`not_found`/`not_unique`/`replace_all`/`expect_count`/`count_mismatch`/`no_change` + **CRLF
  preserved** + LF preserved + multiline-old_string-across-EOL + `binary_file` + pre-image recoverable; append
  ensure-newline/no-double-newline/create/`input_not_found`/CRLF; write-then-edit precondition (`expect_sha256` ok +
  `precondition_failed`); UTF-8-BOM + UTF-16LE detect/preserve; `invalid_op`/`missing_parameter`/`path_is_directory`;
  named-param-overrides-`InputsJson`; envelope schema/artifact-sha256; **no leftover `.docio-*.tmp`**; and the Module 1
  wrapper). The harness is **real-worker & OS-portable** (no mock — .NET file I/O is cross-platform): it generates its
  own fixtures and ran the **real** skill + **real** Module 1 wrapper on the cloud Linux box (88/88) as the pre-ship gate
  before the identical harness ran live on the Windows executor (`m20-test-001`, 88/88, exit 0; canonical review queue
  before==after; 0 stray tmp; 8 shipped files sha256 byte-exact).

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

- **DIRECTION (2026-07-27, D-0050):** past MVP the project drives ONE spine -- the OFFLOAD / AUDIT LOOP under the verify-cost rule (Claude offloads only what is cheaper to VERIFY than to do; deterministic modules = Claude's hands; model modules only where machine- or human-checkable). Active unit = **Widget #3, the Verification Console** (the human-audit surface). Cadence = housekeeping -> implement one unit -> housekeeping -> handoff, run HOT. Multi-instance buildout is a live direction (needs a GPU-lease / commit-lock / doc-ownership layer first). See `DECISION_LOG.md` D-0050.

- **Widget 02 `Module Launcher & Registry Browser` (Phase B #2) is MVP COMPLETE this session (D-0049) -- SHIPPED end-to-end through the job-runner (commit `a699ac6`).** The discoverability + direct-run surface for the whole `modules/` suite: it scans `modules/*/skill.json` to list every installed Module (id/purpose/inputs/requirements/flags; malformed manifests surfaced, not hidden) and runs any one **directly through the Module 1 wrapper `Invoke-Skill.ps1`**, rendering the returned `lifeorch.skill.invocation_report/0.1` + the nested `lifeorch.skill.result/0.1`. A **WinForms-free driver core** (`ModuleLauncher.psm1`: `Get-ModuleRegistry`/`Format-ModuleDetail`/`Get-ModuleInputTemplate` + `Start/Complete/Invoke-ModuleRun`/`Format-ModuleResult`) + a **thin STA shell** (`Show-ModuleLauncher.ps1`) polled from a UI `Timer` + `launch.bat` + a dual-mode harness (a generated fixture modules tree + a mock `Invoke-Skill.ps1`), mirroring Widget 01 (D-0039). Reimplements nothing; NOT a review-queue producer; no new model / no `models.json` change / no Module 7 re-verify. **62/62 off-machine** (cloud pwsh 7.4.6) -> shipped 9 files byte-exact -> **71/71 `-Live`** in ONE `dev.ship` call (`w2-module-launcher-ship-001`): sha 9/9 + AST 3/3 + the WinForms form builds (SelfTest under STA) + a real registry scan (>=20 modules; doc.io + fs.observer manifest_ok, entrypoints on disk) + a **real `fs.observer` run driven end-to-end through the real `Invoke-Skill.ps1`** (rendered) + **0 orphaned llama-server/python**; committed exactly the 9 files. **The next unit is Phase B Widget #3 -- the Verification Console (D-0050)** (`widgets/README.md` item 3). **Op note:** a `git status` over the read-only-delete device mount left a stale `.git/index.lock` (device_bash cannot unlink) that had to be cleared with a Windows-side executor task; use git plumbing (`git rev-parse`) for read-only checks over the mount and let the executor / dev.ship do all writing git ops.
- **fs.manage (Module 28) is MVP COMPLETE this session (D-0042) -- "place it on my desktop" now works BY DEFAULT.** Driven by the real goal *"Generate an image of a dog and place it on my desktop"*: the prior build generated the image but never placed it (`m29-before-001` -- the router picked only `[gen.image]`; the grounded answer said the placement "was not achieved"). Fix: **`fs.manage`** -- a deterministic **copy/move/mkdir** skill with smart path resolution (known folders via `[Environment]::GetFolderPath` so a OneDrive-redirected Desktop is found; `~`/`%ENV%`/absolute/relative; a folder dest keeps the source filename; overwrite-guarded; non-producer; 21/21) -- **wired into `agent.local`**: a new per-tool **`resolve_paths:false`** flag (the agent passes fs.manage's path args verbatim, so a bare `desktop` is not prefixed with working_dir), `Get-Observation` now surfaces `gen.image`'s produced `image.path` for the next step, the arg-gen steers `resolve_paths:false` tools to a known-folder name, and a **`route.tools` few-shot** teaches "generate a file AND place it -> two tools". **Verified end-to-end (`m29-after-003` 6/6): the router picked `[gen.image, fs.manage]`, gen.image generated, and fs.manage copied a real 606 KB dog image to the REAL Desktop (`C:\Users\just_\OneDrive\Desktop\image.png`)** -- 0 orphaned llama-server/python, canonical queue untouched. Off-machine fs.manage 21/21 + agent.local 54/54 + route.tools 34/34 -> `m29-verify-001` 25/25 on target. **Honest residual:** the weak tiers still under-use `finish` (ran extra gen.image steps to max_steps after placing, D-0032) and the final-answer prose can mis-summarize -- the deliverable + the structured `outcome` are correct; better termination is the #1 follow-on. No new model / no `models.json` change / no Module 7 re-verify.

- **route.tools (Module 27) + agent.local `-Route` + Local Agent Console Plan/Run are MVP COMPLETE this session (D-0040/D-0041).** The **Tool Router intermediary** (`route.tools` #27) reads the attachable-tools registry, calls `model.gateway` at the **MID** tier with the validated router prompt (m27-router-001; the 27B thinking tier is REFUSED), parses the JSON array, and **deterministically gates** it against the catalog -> `result.tools` (fast, non-executing, injection-resistant, orchestrator/non-producer). **agent.local** gained **`-Route`** (route FIRST, then run the ReAct loop CONSTRAINED to the routed subset, falling back to the full set on empty; surfaces `result.planned_tools`) + a **curated 10-tool `tools.json`** (doc.io/fs.observer/capture.screen/ocr.layout/detect.objects/image.interpret/speech.stt/audio.ingest/gen.image/gen.music) + a **grounded final answer** (a deterministic `result.outcome` caveats over-claiming). The **Local Agent Console** gained **Plan** (route.tools only) and **Run** (route+execute). **Tests:** off-machine route 34/34 + agent 50/50 + console 55/55 -> on target `m28-verify-001` 37/37 (byte-exact + AST + manifests) + `m28-harness-001` (34/50/55) + `m28-live-001` (REAL 3B routing dog->[gen.image] / screen->[ocr.layout] / transcribe->[speech.stt]; + console -Live 61/61; 0 orphans; queue untouched) -> **REAL end-to-end `m28-e2e-001` 9/9: "make an image of a dog" -Route -> [gen.image] -> a real 402 KB image.png on disk**, 0 orphaned llama-server/python, canonical `review_queue.jsonl` untouched, the grounded answer did not over-claim (models under-used `finish` -> ran to max_steps, D-0032, caught by the budget). **The `fs.manage` (copy/move/mkdir) "deposit on the desktop" last-mile is the recommended next unit** (deferred this session -- the demo did not need it). No new model / no `models.json` change / no Module 7 re-verify.

- **Phase B #1 -- Widget 01 `Local Agent Console` is MVP COMPLETE this session (D-0039).** The first Widget + the Phase-B usability keystone: a native WinForms window (STA) that submits a goal to `agent.local` #21 and renders its result envelope + child transcript (thin: spawns agent.local as a child, reimplements nothing; a WinForms-free driver core `AgentConsole.psm1` + a thin STA shell `Show-AgentConsole.ps1` polled from a UI `Timer`). Delivered **native** + a double-click `launch.bat` per **D-0038** (native-by-default delivery + the launch-file convention, resolving D-0029's open native-vs-web item). Cloud gate **37/37** -> 9 files sha256 byte-exact + AST OK (`m27-verify-001`) -> **41/41 `-Live`** (`m27-test-001`: WinForms form builds + a REAL `agent.local` dry-run driven+parsed+rendered + 0 orphaned `llama-server`). No module / `models.json` / `TOOL_MODEL_REGISTRY` model / `REVIEW_QUEUE` change (a Widget over an existing skill; not a producer). **The next scoped unit is Phase B Widget #2 -- Module Launcher & Registry Browser** (`widgets/README.md` item 2). See D-0038 + D-0039.
- **Phase A #5 `agent.coding` (Coding Agent) is DEFERRED this session (D-0037) -- NOT built.** After a read-only probe (`m26-probe-001`) + a from-the-docs analysis, agent.coding is deferred: **no safe code-execution substrate exists** on this box (WSL launcher but no distro; Windows Sandbox absent + needs elevation on this non-admin box; Docker absent; PowerShell FullLanguage), the useful slice needs a GATED `code.run` (running local-model-authored code -- the arbitrary-exec capability `agent.local` #21 deliberately excluded, D-0032), the roadmap rates it lowest near-term ROI (the frontier already codes well; the weak local tiers are poor at code -- D-0030/D-0032), and a coding agent WITHOUT execution is ~agent.local + a lint tool. A full build-ready MVP is designed in `modules/26-agent-coding/WORK_ORDER.md` (a specialization of `agent.local` #21 + `logic.escalator` #19 + `doc.io` #20 + `model.gateway` #7). **Phase A is now COMPLETE (Modules 0-25 + 00.1 built; #26 designed + deferred). The next scoped unit is Phase B -- the Widget layer (`widgets/`), led by the Local Agent Console.** See D-0037.

- **Module 25 `gen.video` (Local Video Generation, Phase A #4, D-0036) is MVP complete this session** -- AnimateDiff-Lightning 4-step on the reused SD 1.5 base via diffusers (Python worker + meta hand-off; **tenth** review producer; `parallel_safe:false`; **NO new library install** -> Module 12 unaffected; MP4 via ffmpeg / GIF via Pillow; **VRAM peak 4.75 GB full-GPU, no offload**; 54/54 off-machine + 46/46 live, `m25-test-002`; Module 7 28/28). **The generator track (gen.audio -> gen.image -> gen.music -> gen.video) is now COMPLETE.** **The next unit per `MODULE_ROADMAP.md → Build priority` is `agent.coding` (Phase A #5, last), then the Widget layer (`widgets/`, Phase B).** **`gen.video` follow-ons (NOT next session unless wanted):** AnimateDiff full 25-step / SVD image-to-video / CogVideoX / LTX (need newer bf16 HW); img2video/video2video; ControlNet/motion-LoRA; frame interpolation/upscaling; >~2 s via sliding-window; an audio track; a warm/persistent worker; calibrated/motion-quality confidence; a prompt-safety pass. See D-0036.
- **Module 24 `gen.music` (Local Music Generation, Phase A #4, D-0035) is MVP complete this session** -- MusicGen Small via transformers (worker+meta; ninth review producer; `parallel_safe:false`; **NO new library install** -> Module 12 unaffected; 49/49 off-machine + 42/42 live, `m24-test-002`; Module 7 28/28). **The next generator per `MODULE_ROADMAP.md → Build priority` is `gen.video`** (then `agent.coding`, then the **Widget** layer, `widgets/`). **`gen.music` follow-ons (NOT next session unless wanted):** MusicGen Medium/Large or Stable Audio Open tiers; MusicgenMelody (melody-conditioned); batch/multi-clip; a warm/persistent worker; calibrated/aesthetic confidence; a prompt-safety pass; stereo; >30 s via sliding-window continuation; fp16. See D-0035.

0. **Module 22 `gen.audio` (Local Audio Generation, Phase A #4, D-0033) is MVP complete this session** -- the cheapest generator: a **deterministic procedural ffmpeg synthesizer** (tone/chord/noise/sweep/silence; deterministic + `parallel_safe:true`; non-producer; no `models.json` change; 41/41 off-machine + 43/43 live, `m22-test-001`). **The next Phase-A unit per `MODULE_ROADMAP.md → Build priority` is `gen.image`** -- the next generator (the #44 family: Qwen-Image / FLUX.1-schnell / Stable Diffusion XL) -- then `gen.music` → `gen.video`, then `agent.coding`, then the **Widget** layer (`widgets/`). **`gen.audio` follow-ons (NOT next session unless wanted):** a **neural text-to-audio SFX tier** (AudioGen/AudioLDM/Stable Audio -- a library install + a staged model on F:); batch/multi-signal; ADSR envelopes / DTMF / Morse / metronome presets; sweep waveforms; a direct `audio.ingest` loudness pipe. See D-0033.
- **[prior] Module 20 `doc.io` (Local Document I/O, Phase A #2) is MVP complete (D-0031).** The read/write/edit/append
   deterministic text-document primitive (pure PowerShell + .NET; atomic writes, EOL preservation, `expect_sha256`, recoverable
   pre-image; not a review producer; no `models.json` change; 88/88 cloud + 88/88 live, `m20-test-001`). **The next Phase-A unit
   per `MODULE_ROADMAP.md → Build priority` is `agent.local`** — the Local Orchestrator / Agent core (a local model that plans and
   invokes any Module through the escalator #19), then the generators cheapest-first (`gen.audio`→`gen.image`→`gen.music`→`gen.video`),
   then `agent.coding`, then the **Widget** layer (`widgets/`). **`doc.io` follow-ons (NOT next session unless wanted):** batch/
   directory/glob; a regex or unified-diff apply mode; structured-format (JSON/YAML/CSV) field edits; a sibling `fs.manage`
   (move/copy/rename/delete/mkdir); more encodings; a read-only or per-file-lock `parallel_safe:true` mode + a tail/follow read;
   insert-at-line / replace-line-range ops. See D-0031. **Prior: Module 19 `logic.escalator` (Phase A #1, D-0030)** — top escalator follow-ons
   (measured, NOT this session):** raise the strong-tier `max_tokens` / add a no-reasoning directive so the 27B returns a parseable
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

- **Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **Housekeeping / direction D-0050**: recorded the past-MVP offload / verify-cost doctrine + the audit-loop spine, reoriented Widget #3 to the Verification Console, set the iterate-loop cadence (housekeeping -> implement -> housekeeping -> handoff) + the multi-instance direction; appended DECISION_LOG D-0050; re-pointed START_HERE / PROJECT_DIRECTION / MODULE_ROADMAP / HANDOFF / this file. No code this pass.) - **[prior] Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **Widget 02 post-ship UI fix (D-0049, commit `c509e571`)**: the first live UI run showed the module list as a single "unreadable manifest" row + mis-sized panes -- two defects the 71/71 gate missed by exercising the API path, not the rendered UI. Fixed `Get-ModuleRegistry`'s `return ,$sorted` double-wrap (the UI's `@(Get-ModuleRegistry)` got a 1-element array wrapping the whole array -- the documented pwsh 7.4.6 gotcha; dropped the comma) and moved SplitContainer `SplitterDistance` into `Add_Shown` (set at construction it was out of range on the ~150px container and silently swallowed) + word-wrapped the detail/result panes. Added regression tests for the UI's `@()`-collected path (fixture + the real default-resolution scan). Cloud 64/64 -> **75/75 `-Live`** (`w2-fix-ship-001`), 0 orphans. Docs re-mirrored.) - **[prior] Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **Widget 02 Module Launcher & Registry Browser SHIPPED (D-0049)**: the Phase-B #2 discoverability + direct-run surface -- browse every installed Module from its `skill.json` and run any one through the Module 1 wrapper `Invoke-Skill.ps1`, rendering the invocation_report + nested envelope; WinForms-free core (`ModuleLauncher.psm1`) + thin STA shell (`Show-ModuleLauncher.ps1`) + launch.bat + a fixture/mock dual-mode harness. 62/62 cloud -> 9 files byte-exact + **71/71 `-Live`** in ONE dev.ship call (`w2-module-launcher-ship-001`, commit `a699ac6`): WinForms self-test + real registry scan (>=20 modules) + a real fs.observer run through the wrapper + 0 orphaned llama-server/python. FIRST unit shipped entirely through the job-runner. Cleared a stale `.git/index.lock` (from a git-status over the device mount) via a Windows-side executor task. Docs mirrored to the Project.) - **[prior] Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **Module 0 job-runner SHIPPED (D-0048)**: built `dev.ship` (Invoke-DevShip.ps1) + `exec-job.sh` -- one executor job verifies shipped sha256 + AST-parses *.ps1 + runs tests, then FAIL-CLOSED + index-clean-guarded git-adds ONLY the named files + commits with trailers, emitting one compact lifeorch.devship.result/0.1; exec-job.sh is the device-side submit/wait/devship client. Collapses the ~40-call per-unit ceremony to a few calls. 27/27 dev.ship + 24/24 exec-job off-machine (cloud pwsh 7.4.6 + git); shipped byte-exact; live dogfood self-verify on target (sha 4/4, ast 2/2, tests 27/27, 0 orphans) and the unit was COMMITTED BY dev.ship ITSELF (5644b9ba, exactly the 4 files, Show-AgentConsole untouched). Next = Widget #2. Docs mirrored to the Project.) - **[prior] Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **Housekeeping + direction (D-0047)**: correction arc closed (D-0043/44/46; the D-0032 reliability bug is RESOLVED -- multi-tool goals finish reliably at the floor default). Re-pointed the nav docs (START_HERE banner, HANDOFF rewritten as the go-forward map, this file, MODULE_ROADMAP + PROJECT_DIRECTION) to the go-forward direction: resume capability expansion per the original plan, with ONE immediate infra unit first -- the executor JOB-RUNNER (Module 0 expansion) + a dev.ship unit harness that collapses the per-unit ship/verify/test/commit/mirror ceremony (~40 hand-driven calls + ~30 polls today) to cut ongoing frontier token overhead. The retained-context agent builds the job-runner next (this session); the handoff after is to capability expansion (Phase B Widget #2). Docs mirrored to the Project.) - **[prior] Last updated:** 2026-07-27 (UTC) - **Last updating agent:** Claude (Cowork -- **agent.local D-0032 fix (D-0046)**: built a deterministic terminator + repeat-action guard -- a `finish` decision is blocked until every routed planned tool has succeeded (force-select the first unsatisfied one, capped by the step budget), and an already-succeeded (tool,args) is never re-run (kills the loop-to-max_steps); new `-RequirePlannedToolsBeforeFinish` default-ON under -Route, surfaced as `result.terminator`. Non-routed behaviour unchanged. Tests 58->87, 87/87 off-machine (cloud pwsh 7.4.6) + 87/87 on target (m21-d0032-tests-001). LIVE dog goal -Route: floor x3 landed on the real Desktop EVERY run (m21-d0032-dog-floor-002; RUN 1 shows the terminator firing -- finish_blocked=1 forcing fs.manage), 0 orphans. Honest residual: -Profile max does NOT land -- the 9B strong arg-gen returns non-JSON every step (arg_parse_failed x10; m21-d0032-maxdiag-001), a 9B/gateway defect NOT the terminator (floor gen_tier=mid is reliable); the terminator still refused to over-claim (stopped/succeeded=[]). 3 files shipped byte-exact; committed with trailers. No models.json change; agent.local remains a non-producer.) - **[prior] Last updated:** 2026-07-26 (UTC) - **Last updating agent:** Claude (Cowork -- fs.manage #28 + the wiring that makes "place it on my desktop" work by default (D-0042): built a deterministic copy/move/mkdir skill (smart known-folder/~/env path resolution, OneDrive-safe Desktop, overwrite guard, non-producer, 21/21) + wired it into agent.local (a resolve_paths:false per-tool flag, gen.image image-path in the observation, an arg-gen known-folder hint) + a route.tools few-shot for generate+place. Empirical loop (execute -> evaluate -> fix): m29-before-001 (image made, NOT on desktop) -> m29-after-001/002 (router + placement fixes) -> m29-after-003 6/6: a real 606 KB dog image landed on the REAL desktop (OneDrive\Desktop\image.png), 0 orphans, queue untouched. No models.json change.) - **[prior] Last updated:** 2026-07-26 (UTC) - **Last updating agent:** Claude (Cowork -- route.tools #27 + agent.local -Route + Console Plan/Run (D-0040/D-0041): built the Tool Router intermediary (mid-tier router pass + deterministic catalog gate + strong-27B refusal + injection-resistant, orchestrator/non-producer), added agent.local -Route (route-then-constrained ReAct loop, curated 10-tool registry, grounded final answer) + the Console Plan/Run path. Off-machine 34/50/55 -> m28-verify-001 37/37 + m28-harness-001 (34/50/55) + m28-live-001 (REAL 3B routing + console -Live 61/61, 0 orphans, queue untouched) -> REAL e2e m28-e2e-001 9/9 (make an image of a dog -Route -> gen.image ran -> a real 402 KB image.png on disk). fs.manage deferred as the next gap. No models.json change.) - **[prior] Last updated:** 2026-07-26 (UTC) - **Last updating agent:** Claude (Cowork -- **Widget 01 `Local Agent Console` (Phase B #1, D-0039)**: built the Phase-B usability keystone -- a native WinForms window (STA) that submits a goal to `agent.local` #21 and renders its `lifeorch.skill.result/0.1` envelope + child transcript; thin (spawns agent.local as a child, reimplements nothing) via a WinForms-free driver core (`AgentConsole.psm1`) + a thin STA shell (`Show-AgentConsole.ps1`) polled from a UI `Timer`; delivered native + a double-click `launch.bat` per **D-0038** (native-default + launch-file convention, resolving D-0029's open native-vs-web item). Cloud gate 37/37 -> 9 files sha256 byte-exact + AST OK (`m27-verify-001`) -> **41/41 `-Live`** (`m27-test-001`: WinForms form builds + a REAL agent.local dry-run driven+parsed+rendered + 0 orphaned llama-server). Installed pwsh 7.4.6 on the fresh cloud box. No module / models.json / producer change.) - **[prior] Last updated:** 2026-07-26 (UTC) · **Last updating agent:** Claude (Cowork -- **Module 26 `agent.coding` (Coding Agent, Phase A #5, D-0037): DEFERRED, not built.** Probe `m26-probe-001` (read-only): git authoritative-clean on Windows (HEAD b9c6ca7; the Linux-mount "106 modified" was pure CRLF noise; a stale index.lock was cleaned), the composition substrate (escalator/doc.io/agent.local/gateway) present, and NO safe code-execution substrate (WSL no distro / Windows Sandbox absent+elevation / Docker absent / PowerShell FullLanguage). Authored `modules/26-agent-coding/WORK_ORDER.md` -- a build-ready tight-MVP design (a specialization of `agent.local` #21: the ReAct loop + decisions THROUGH `logic.escalator` #19 + codegen via `model.gateway` #7 + a closed 3-tool registry: `code.write` via `doc.io` #20 into a scratch dir, a NEW deterministic `code.check` static verifier, and a GATED `code.run`) + the deferral rationale. Deferred because: no safe exec substrate (the useful slice needs `code.run` = the arbitrary-exec capability agent.local deliberately excluded, D-0032; a real sandbox is a separate admin-gated effort, D-0001), lowest near-term ROI (roadmap; frontier already codes well; the weak local tiers are poor at code -- D-0030/D-0032), and the safe slice is ~agent.local + a lint tool. **Phase A COMPLETE; next = Phase B Widgets (Local Agent Console).** No code / no models.json / no producer change. Committed with trailers.) · **[prior] Last updated:** 2026-07-26 (UTC) · **Last updating agent:** Claude (Cowork — **Module 25 `gen.video` (Local Video Generation, Phase A #4, D-0036)**: built the generator track's motion slot (the fourth + last generator, third neural) -- text-to-video via a local **AnimateDiff-Lightning 4-step** pipeline (diffusers `AnimateDiffPipeline` = an SD-1.5 base REUSED from gen.image #23 + a ~907 MB motion adapter, fp16, CUDA) driven by a **Python worker + meta-file hand-off** (the D-0021/D-0034/D-0035 pattern). Registry-driven (`video.animatediff-lightning`, `type=video-gen`, decoupled from the gateway `wired` gate); `determinism:"mixed"`, `parallel_safe:false`; generation-completeness/non-blank + non-static confidence; **tenth review producer** (`verify_generation`). **NO new library install** (diffusers already present; MP4 via the present ffmpeg, GIF via Pillow) -> speech venv unchanged -> Module 12 unaffected. **Probe-first** (`m25-probe-001/002`): no video model staged; downloaded + staged the AnimateDiff-Lightning adapter to F: and **live-generated 16 frames 512x512 4-step in ~57 s** (VRAM peak **4.75 GB full-GPU, no offload**, pixel_std 44.4 / interframe diff 41.6, seed byte-reproducible, real MP4+GIF) before coding; probe-001's only failure was a missing `variant="fp16"` (fixed in probe-002). Pre-shipped off-machine (cloud pwsh 7.4.6 + a stdlib mock worker driving the real wrapper, **54/54**) -> 10 files byte-exact (sha256 + AST-parse OK on target, `m25-verify-001`) -> **46/46 `-Live`** via the executor (`m25-test-002`: real AnimateDiff generations, same-seed byte-reproducible, mp4 magic + gif, canonical queue before==after, 0 orphans) -> **Module 7 re-verified 28/28** (`m25-m7regress-001`). Added `models.json` `video.animatediff-lightning` + `defaults.video`/`tiers.video`. Added `Invoke-GenVideo.ps1`/`video_gen_infer.py`/`skill.json`/`README.md`/`WORK_ORDER.md`/`.gitignore`/tests/examples. Committed with trailers.) · **[prior] Last updated:** 2026-07-26 (UTC) · **Last updating agent:** Claude (Cowork — **Module 24 `gen.music` (Local Music Generation, Phase A #4, D-0035)**: built the generator track's music slot -- text-to-music via a local **MusicGen Small** (transformers `MusicgenForConditionalGeneration`, CUDA) driven by a **Python worker + meta-file hand-off** (the D-0021/D-0034 pattern). Registry-driven (`music.musicgen-small`, `type=music-gen`, decoupled from the gateway `wired` gate); `determinism:"mixed"`, `parallel_safe:false`; generation-completeness/non-silent confidence; **ninth review producer** (`verify_generation`). **NO new library install** (transformers already ships MusicGen) -> speech venv unchanged -> Module 12 unaffected by construction. **Probe-first** (`m24-probe-001/002`): transformers has MusicGen, no checkpoint staged; **downloaded + staged `facebook/musicgen-small` to F:** (~2.37 GB after pruning redundant weights; `m24-prune-001`) and **live-generated a 5.06 s clip in 7.6 s** (VRAM peak 2.4 GB, 32 kHz mono, seed byte-reproducible) before coding. Pre-shipped off-machine (cloud pwsh 7.4.6 + a stdlib mock worker driving the real wrapper, **49/49**) -> 10 files byte-exact (sha256 + AST-parse OK on target, `m24-verify-001`) -> **42/42 `-Live`** via the executor (`m24-test-002`: real MusicGen, same-seed byte-reproducible, mp3 + resample via the real `audio.ingest`, canonical queue 1->1, 0 orphans) -> **Module 7 re-verified 28/28** (`m24-m7regress-001`). Added `models.json` `music.musicgen-small` + `defaults.music`/`tiers.music`. Added `Invoke-GenMusic.ps1`/`music_gen_infer.py`/`skill.json`/`README.md`/`WORK_ORDER.md`/`.gitignore`/tests/examples. Fixed one test assertion (echo.params accepts ok|partial). Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 23 `gen.image` (Local Image Generation, Phase A #5, D-0034)**: built the first neural generator -- text-to-image via a local **Stable Diffusion 1.5** pipeline (`diffusers` `StableDiffusionPipeline`, fp16, CUDA) driven by a **Python worker + meta-file hand-off** (the `speech.tts` D-0021 pattern). Registry-driven (`image.sd15`, `type=image-gen`, decoupled from the gateway `wired` gate); `determinism:"mixed"`, `parallel_safe:false`; generation-completeness/non-blank confidence; **eighth review producer** (`verify_generation`). **Probe-first** (`m23-probe-001/002`): no checkpoint existed; **installed `diffusers` 0.35.2 into the speech venv** (Module 12 safety re-verified -- torch/transformers/`qwen_tts` intact) and **staged SD 1.5 fp16** (~2.13 GB) to F:, live-generating a 512x512 image in 2.8 s (VRAM peak 2.61 GB) before coding. Pre-shipped off-machine (cloud pwsh 7.4.6 + a stdlib mock worker driving the real wrapper, **42/42**) -> 10 files byte-exact (sha256 + AST-parse OK on target) -> **32/32 `-Live`** (`m23-test-005`: real SD generations, same-seed byte-reproducible, real JPEG, canonical queue 1->1, 0 orphans) -> **Module 7 re-verified 28/28** (`m23-m7regress-001`). Added `models.json` `image.sd15` + `defaults.image`/`tiers.image`. Fixed a harness pwsh-shim bug (`$PSHOME` resolution). Added `Invoke-GenImage.ps1`/`gen_image_infer.py`/`skill.json`/`README.md`/`WORK_ORDER.md`/`.gitignore`/tests/examples. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 22 `gen.audio` (Local Audio Generation, Phase A #4, D-0033)**: built the cheapest generator — a **deterministic, procedural ffmpeg synthesizer**: one `-Kind` per call (tone/chord by Hz or note name with sine/square/triangle/sawtooth; colored noise seeded→reproducible; linear sweep; silence), shaping (duration/rate/channels/amplitude/fade), direct encode to wav/mp3/flac/opus/ogg/m4a (codec map == `audio.ingest`, reusing its ffmpeg/resolution/envelope machinery). Pure PowerShell over ffmpeg 8.1; `determinism:"deterministic"`, `parallel_safe:true`, **NOT a review producer** (canonical queue before==after 1→1); no `models.json` change / no Module 7 re-verify. **Probe-first** (`m22-probe-001`): ffmpeg lavfi synthesis verified end-to-end + **no** neural audio-gen stack staged (audiocraft/diffusers/stable_audio_tools/audioldm/TTS/bark all absent; no model on disk) → neural text-to-audio deferred as a follow-on. Pre-shipped off-machine (cloud pwsh 7.4.6 + real cloud ffmpeg 6.1.1, real skill + harness, **41/41**) → shipped 8 files byte-exact (`m22-test-001` sha256 + AST-parse OK on target) → **43/43 live** via the executor incl. the Module 1 manifest-validator + wrapper; canonical `review_queue.jsonl` before==after. Added `WORK_ORDER.md`/`README.md`/`skill.json`/`.gitignore`/tests/examples. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 21 `agent.local` (Local Orchestrator / Agent, Phase A #3, D-0032)**: built the bounded ReAct local agent loop — decisions ("which tool next, or `finish`?") route **through `logic.escalator` (#19)** as a closed-set classify (in-set gate → a valid tool or `needs_frontier`), args + final answer via **`model.gateway` (#7)**, tools invoked as child skills from a declarative closed registry (`tools.json`: **`doc.io` #20 + `fs.observer` #2**; no arbitrary-shell tool). Guardrails: hard `max_steps` budget, `-DryRun` plan-preview, `needs_frontier` as status. Orchestrator/**non-producer** (redirects child review writes; canonical queue + seven-producer set untouched, before==after). `determinism:"mixed"`, `parallel_safe:false`, `batch:false`; no new model / no `models.json` change / no Module 7 re-verify. Pre-shipped off-machine (cloud pwsh 7.4.6, real orchestrator + mock-children harness + real Module 1 wrapper, **39/39**) → shipped 10 files byte-exact (`m21-verify-001` sha256 + AST-parse OK) → **39/39 the same harness `-Live`** (`m21-test-001`) + a **REAL end-to-end run** (`m21-live-001`): "create hello.txt with 'hi from agent.local'" → chose `doc.io` via the escalator, the 3B generated the args, **the file was written on disk with the exact content**; a second goal invoked `fs.observer`; 0 orphaned `llama-server`; queue 1→1. **Honest finding:** the tiny/weak/mid models under-use `finish` (both live goals ran to `max_steps`); the hard budget caught it every time — better termination is the #1 follow-on, reported plainly not hidden. Added `WORK_ORDER.md`/`README.md`/`skill.json`/`tools.json`/`.gitignore`/tests/examples. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 20 `doc.io` (Local Document I/O, Phase A #2, D-0031)**: built the deterministic **read/write/edit/append** text-document primitive — pure PowerShell over cross-platform .NET (no external binary / Python / model / `models.json` change / Module 7 re-verify), with **atomic** temp+rename writes, **EOL preservation** (CRLF-safe), an **`expect_sha256`** optimistic-concurrency precondition, and a recoverable **`before.<ext>` pre-image**; `determinism:"deterministic"`, **NOT a review producer** (the seven-producer set + canonical `review_queue.jsonl` untouched, verified before==after). Pre-shipped off-machine on cloud pwsh 7.4.6 (the **real** skill + the **real** Module 1 wrapper, **no mock** — 88/88) → shipped 8 files byte-exact (sha256 + AST-parse OK on the target) → **88/88 `-Live`** via the executor (`m20-test-001`, exit 0; 0 stray `.docio-*.tmp`; canonical queue before==after). Added `WORK_ORDER.md`/`README.md`/`skill.json`/`.gitignore`/examples. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — **Module 19 `logic.escalator` (Local Logic Escalator, Phase A #1, D-0030)**: built the escalating tier ladder composing `model.gateway` (tiny→weak→mid→strong) with deterministic ground-truth gates (in-set / JSON-schema+grounding / self-consistency) anchoring every rung — a hard-fail overrides an LLM-judge accept, strong self-consistency short-circuits; orchestrator/non-producer (suppresses child gateway review writes, surfaces `needs_frontier`; canonical queue untouched). Pre-shipped off-machine on cloud pwsh 7.4.6 (24/24 mock-gateway scenarios) → shipped 10 files byte-exact (`m19-verify-001` sha256 + AST-parse OK) → 28/28 with `-Live` (`m19-test-001`, 0 orphans). **Empirically calibrated (`m19-calib-002/003`, the D-0029 experiment):** 3-tier K=1 = 78.6% acc / 0.20 false-approval / −89% cost; 4-tier K=1 = 57.1% (the 27B emits empty verdicts at MVP token caps → fail-safe `needs_frontier`); **does NOT reach the 95% target — reported plainly** with prioritized follow-ons. Added `CALIBRATION.md` + `.gitignore`. Committed with trailers.) · **[prior] Last updated:** 2026-07-25 (UTC) · **Last updating agent:** Claude (Cowork — housekeeping pass, D-0028: (A) folded the three D-0009/D-0011 conventions into SKILL_CONTRACT.md v0.2 (skill-relative artifact roots + absolute paths §3, generic -InputsJson §3.1, lifeorch.skill.invocation_report/0.1 §3.2), keeping the wire schema ids at /0.1 — additive + backward-compatible, so the validators and all existing manifests were untouched; (B) relocated every staged model out of _pending-model-storage into per-owning-module F: homes (LLMs→07-model-gateway, whisper→11-speech-stt, TTS voices→12-speech-tts, detectors→16-detect-objects, VLM→17-image-interpret, embedding→23-artifact-search) + the shared llama.cpp engine→_engines, rewrote models.json (13 models, byte-exact sha256 5aed38db…), de-duplicated the 12 Hz TTS tokenizer (deleted the standalone copy + its declared-only registry entry — each voice keeps its bundled speech_tokenizer), and deleted the emptied _pending-model-storage + its MIGRATION.md; (C) removed the proteus_repo/tools leftover. Re-verified live via the executor (hk-verify-001): all 4 LLM tiers + whisper STT + Qwen3-TTS (bundled tokenizer) + ONNX detector + VLM caption each load from their new homes, 0 orphaned servers. Refreshed the Module 1 README; no skill code changed). · **2026-07-25 (later) — direction pivot D-0029 (docs only, no code):** adopted the Module/Widget vocabulary, created the `widgets/` folder + README, added the `ARCHITECTURE_MAP.md` core-doc (canonical 0-49 spine + the real-time autonomic layer 45-49 + the 6-level operating hierarchy; model names annotated as non-binding candidates), and re-prioritized the build order to a usable-local-core-first sequence (Phase A utility/cost-offload led by the Local Logic Escalator; Phase B the Widget layer; Phase C the deferred research spine). Updated START_HERE / PROJECT_DIRECTION / MODULE_ROADMAP / CURRENT_STATE accordingly.
