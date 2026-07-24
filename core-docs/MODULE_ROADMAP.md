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

## Modules 10–13 — Audio (provisional; Module 10 MVP complete)
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
- **12 `speech.tts`** local TTS · **13 `voice.live`** compose record+VAD+STT+TTS (after 10–12 work). *(provisional)*

## Modules 14–18 — Image & document perception (provisional)
- **14 `ocr.layout`** OCR + boxes + reading order · **15 `image.util`** resize/crop/meta/hash/similarity/
  convert/tile/region · **16 `detect.objects`** class boxes + confidence · **17 `image.interpret`** local
  multimodal captions/VQA/screen interpretation · **18 `image.index`** integrate 14–17 → markdown + machine index.

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
