# MODULE_ROADMAP

Owns **module order and status**. Not technical specs — each active module gets a work order.
**Provisional beyond the first few items on purpose:** we do not lock thirty modules before using
the first five. Reorder freely as MVPs teach us what matters.

**Status vocabulary:** Proposed · Ready · In progress · Blocked · MVP complete · Active ·
Needs refactor · Deprecated · Replaced.

---

## Build priority (2026-07-25 pivot — D-0029)

> **2026-07-27 (D-0047) -- correction arc COMPLETE; capability expansion RESUMED.** D-0043 (mid decision floor), D-0044 (9B strong tier), and D-0046 (deterministic terminator -- the D-0032 premature-`finish` bug is fixed; multi-tool goals finish reliably at the floor default) closed the reliability corrections. **ONE infrastructure unit comes first, before the next capability item:** the executor JOB-RUNNER (Module 0 expansion) + a `dev.ship` unit harness (collapses the per-unit ship/verify/test/commit/mirror ceremony to cut frontier token overhead). After it, resume this Build priority -- next capability unit = **Phase B Widget #2 (Module Launcher / Registry Browser)**; multi-tool agent runs are reliable at the floor default now, so a Widget driving `agent.local` is safe. **UPDATE 2026-07-27 (D-0049): Widget #2 SHIPPED** (`widgets/02-module-launcher/`; browse `modules/*/skill.json` + run any Module through the Module 1 wrapper `Invoke-Skill.ps1`; 62/62 cloud + 71/71 live via the job-runner, commit `a699ac6`); the next unit is **Phase B Widget #3 -- the Verification Console** (D-0050: the human-AUDIT surface for the offload/verify-cost spine, reorienting the old "Review / Escalation Dashboard" -- Claude writes a verification packet, Nicholas runs + checks it locally through Invoke-Skill.ps1 and exports a result Claude reads back). Deferred substrate follow-ons: Governor Phase 2 (warm server), 9B arg-gen hardening (unblocks -Profile max), Governor Phase 3. **Direction (D-0050):** past MVP the project drives ONE spine -- the OFFLOAD / AUDIT LOOP under the verify-cost rule (Claude offloads only what is cheaper to verify than to do; deterministic modules = Claude's hands; model modules only where machine- or human-checkable). MULTI-INSTANCE buildout (several Claudes driving the box) is a live goal that first needs a resource-arbitration layer: a GPU lease + a git/commit lock + doc-ownership.

**The per-module numbers in this doc are architectural positions, not a build sequence.** The full 0-49
spine (+ the real-time autonomic layer 45-49 and the 6-level operating hierarchy) lives in
`ARCHITECTURE_MAP.md`. **Modules 0-18 + 00.1 are built.** The near-term order is re-prioritized to deliver a
**locally usable core** (cost-offload + a human interface) before the deep-research spine:

**Phase A — Utility & cost-offload Modules (build next, in this order):**
1. **`logic.escalator` — Local Logic Escalator** — **MVP COMPLETE 2026-07-25 (folder `modules/19-logic-escalator/`; D-0030; empirically calibrated — see the Module 19 entry below).** (generalizes `review.processor` #9 + `route.tasks` #24):
   the weakest model answers; each higher tier judges the tier below and either accepts it or produces its
   own answer for the next tier to judge; stop when the step up would add no substantial gain (that fixes
   the accepted layer). **Must** anchor rungs with deterministic ground-truth gates (schema / unit-test /
   retrieval / self-consistency), not LLM-judges-LLM alone, and be **empirically calibrated** (sandbox:
   measure the resolve-level distribution + the false-approval rate; a ladder of N tiers can cost more than
   one correct call unless most tasks resolve low; target ~95% confidence) before it is trusted. The single
   highest-leverage budget item — every task a local model finishes end-to-end is one the frontier allotment never pays for.
2. **`doc.io` — Local Model Doc Read/Write/Edit/Append** — **MVP COMPLETE 2026-07-25 (folder `modules/20-doc-io/`; D-0031; deterministic; tests 88/88 cloud + 88/88 live).** (cheap, mostly deterministic; high utility): read (whole / line-range) + write + exact-string edit + append, with atomic writes, EOL preservation (CRLF-safe), an `expect_sha256` precondition, and a recoverable pre-image. Pure PowerShell + .NET; not a review producer; no `models.json` change.
3. **`agent.local` — Local Orchestrator / Agent core** — **MVP COMPLETE 2026-07-25 (folder `modules/21-agent-local/`; D-0032; orchestrator/non-producer; tests 39/39 cloud + 39/39 live + a real end-to-end run).** (a scoped #26): a local model that plans and invokes
   any Module through the escalator — the frontier agent's job, done locally. A bounded ReAct loop: the tool-selection decision routes through `logic.escalator` (#19) as a closed-set classify (in-set gate); args + final answer via `model.gateway` (#7); tools are conforming Modules from a declarative closed registry (`tools.json`: `doc.io` #20 + `fs.observer` #2). Guardrails: hard `max_steps` budget, `-DryRun` plan-preview, `needs_frontier` as status. See the Module 21 entry below.
4. **Generators, cheapest-first:** `gen.audio` (**MVP COMPLETE 2026-07-25, D-0033**) → `gen.image` (**MVP COMPLETE 2026-07-25, D-0034**; SD 1.5 via diffusers) → `gen.music` (**MVP COMPLETE 2026-07-26, D-0035**; MusicGen Small via transformers) → `gen.video` (**MVP COMPLETE 2026-07-26, D-0036**; AnimateDiff-Lightning on SD 1.5 via diffusers).
5. **`agent.coding` -- Coding Agent** -- **DEFERRED 2026-07-26 (D-0037; folder `modules/26-agent-coding/`, WORK_ORDER authored, not built)** (last here -- the frontier already codes well; lowest near-term ROI). A full build-ready MVP is designed in the work order (a specialization of `agent.local` #21 + a GATED code-execution tool); deferred because no safe code-execution substrate exists on this box (`m26-probe-001`: WSL no distro / Windows Sandbox absent+elevation / Docker absent) and the useful slice is the arbitrary-exec capability agent.local deliberately excluded (D-0032). See the Module 26 entry below + D-0037.

**Phase B — Widget layer (human interface; `widgets/`):** led by the **Local Agent Console** (the usability
keystone) -- **#1 MVP COMPLETE 2026-07-26 (D-0039; `widgets/01-local-agent-console/`; native WinForms, delivered per D-0038; drives `agent.local` #21)** -- **#2 Module Launcher / Registry Browser MVP COMPLETE 2026-07-27 (D-0049; `widgets/02-module-launcher/`; browses `modules/*/skill.json` + runs any Module through the Module 1 wrapper)** -- then Review/Escalation Dashboard, Voice Console, Generator Studio,
Document Workspace, System/Executor Monitor. Full list + rationale in `widgets/README.md`.

**Phase C — resume the canonical spine (deferred):** video (19-22) → search/routing/orchestration (23-26) →
the general-screen-perception + self-improving stack (27-44) → the real-time autonomic layer (45-49).

The per-module entries below remain the canonical position/status records. **Read this Build priority for
what to do next**: pick up a Phase-A item (or, if video capability is specifically wanted now, #19
`media.decompose`) as the next scoped unit. New Phase-A/B ids (`logic.escalator`, `doc.io`, `agent.local`,
`gen.*`, `agent.coding`, the Widgets) get expanded entries + work orders when they become active.

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
- **Dependencies:** Module 0; `SKILL_CONTRACT.md` (drafted v0.1; finalized to **v0.2** by the 2026-07-25 housekeeping pass, D-0028).
- **MVP acceptance:** **Met — `ref.echo` validates and runs directly + through the executor, emitting a
  schema-valid `lifeorch.skill.result/0.1`; the wrapper validates manifest+envelope; module tests 11/11
  (2026-07-24).** Contract-finalization of the adopted conventions **done 2026-07-25 — folded into `SKILL_CONTRACT.md` v0.2 (DECISION_LOG D-0009/D-0011 → D-0028).**
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

## Module 19 (build order) — Local Logic Escalator (`logic.escalator`)
- **id:** `logic.escalator` · **Priority:** Phase A #1 (D-0029) · **Status:** **MVP complete (2026-07-25)**
- **Folder-number note:** on-disk `modules/19-logic-escalator/`. The `NN-` prefix is a **monotonic build-order counter**
  (0, 00.1, 1..18, then 19); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 **architectural positions**.
  `logic.escalator` has no dedicated spine slot (it generalizes `route.tasks` #24 + `review.processor` #9, pulled forward).
  The video block's "19 media.decompose" below is an architectural label (deferred to Phase C), not this folder.
- **Purpose:** an escalating ladder of local model tiers (tiny→weak→mid→strong via `model.gateway`): the weakest answers;
  each higher tier judges the current answer and either accepts it (stop; accepted layer fixed) or produces its own for the
  next tier; the top tier's answer is accepted if reached. **Composes the gateway; reimplements nothing.**
- **Guardrails honored:** (1) **deterministic ground-truth gates anchor every rung** — classify in-set (hard) +
  self-consistency; extract JSON-schema + all-fields (hard) + source-grounding; generic ungated + self-consistency. A
  hard-fail overrides an LLM-judge accept; strong self-consistency short-circuits to accept. (2) **Empirically calibrated**
  (`m19-calib-002/003`): 3-tier K=1 = 78.6% acc / **0.20 false-approval** / −89% cost; 4-tier K=1 = 57.1% (the 27B emits
  empty verdicts at MVP token caps → fail-safe `needs_frontier`). **Does NOT reach ~95%** with the naive K=1 config —
  reported plainly; always-mid baseline 92.9%.
- **Flags:** `determinism:"mixed"`, `parallel_safe:false`, `batch:true`, `streaming:false`. **Orchestrator, NOT a
  review-queue producer** (suppresses child gateway review writes; surfaces `needs_frontier`; canonical queue untouched;
  producer set stays at seven). No new model / no `models.json` change / no Module 7 re-verify.
- **Tests:** **24/24 mock (cloud pre-ship) + 28/28 `-Live`** (`m19-test-001`, exit 0, 0 orphaned `llama-server`). Files
  sha256 byte-exact + AST-parse OK on the target (`m19-verify-001`).
- **Implementation:** `modules/19-logic-escalator/` (`Invoke-LogicEscalator.ps1`, `skill.json`, `eval/classify-eval.json`,
  `tests/{mock-gateway,Invoke-LogicEscalatorTests,Invoke-EscalatorCalibration}.ps1`, `CALIBRATION.md`). **Work order:**
  `modules/19-logic-escalator/WORK_ORDER.md`. See **D-0030**.
- **Follow-ons (measured, NOT this session):** raise strong-tier `max_tokens` / no-reasoning directive (D-0018);
  self-consistency **veto** + skeptical judges (cut the 0.20 false-approval); higher floor / cost-aware early-stop;
  live-calibrate K>1; `unit_test`/retrieval gates; a `route.tasks` (#24) drain of `needs_frontier`.

## Module 20 (build order) — Local Document I/O (`doc.io`)
- **id:** `doc.io` · **Priority:** Phase A #2 (D-0029) · **Status:** **MVP complete (2026-07-25)**
- **Folder-number note:** on-disk `modules/20-doc-io/`. The `NN-` prefix is a **monotonic build-order counter**
  (0, 00.1, 1..19, then 20); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 architectural positions.
  `doc.io` has no dedicated spine slot — a Phase-A utility Module (the cheap, high-utility document primitive).
- **Purpose:** the read/write/edit/append **text-document primitive** a local model (the escalator #19, a future
  `agent.local`, Widgets, unattended executor tasks) calls to do real file work — the local counterpart to the
  frontier agent's Read/Write/Edit tools. One skill, **one op per invocation** (`-Op read|write|edit|append`).
- **Ops:** **read** (whole file or a 1-indexed inclusive `start_line..end_line` range + `max_bytes` cap → content +
  `{encoding,bom,eol,line_count,byte_count,char_count,sha256}`); **write** (create/overwrite; `overwrite`/`create_dirs`/
  `eol lf|crlf`); **edit** (exact-string `old_string`→`new_string`; default exactly-one, `replace_all`/`expect_count`
  variants); **append** (`ensure_newline`/`create`).
- **Deterministic + tool-not-model:** `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`,
  **NOT a review-queue producer** (the seven-producer set is untouched); pure PowerShell + .NET only — **no external
  binary / Python / model / `models.json` change / Module 7 re-verify** (the leanest skill yet).
- **Safety:** atomic temp+rename writes (no torn files / no leftover `.docio-*.tmp`); optional `expect_sha256`
  optimistic-concurrency precondition; recoverable `before.<ext>` pre-image; **EOL preservation** (a CRLF file stays
  CRLF — the D-0018/core-docs gotcha, generalized); UTF-8 default + UTF-16 BOM detect/preserve; binary refused.
- **Flags:** `determinism:"deterministic"`, `parallel_safe:false` (first general external-file mutator; conservative —
  see D-0031), `batch:false`, `streaming:false`.
- **Tests:** **88/88 off-machine (cloud pwsh 7.4.6, real skill + real Module 1 wrapper — no mock) + 88/88 `-Live` via
  the executor** (`m20-test-001`, exit 0); 8 files sha256 byte-exact + AST-parse OK on the target.
- **Implementation:** `modules/20-doc-io/` (`Invoke-DocIo.ps1`, `skill.json`, `README.md`, `WORK_ORDER.md`,
  `.gitignore`, `tests/Invoke-DocIoTests.ps1`, `examples/`). **Work order:** `modules/20-doc-io/WORK_ORDER.md`. See **D-0031**.
- **Follow-ons (NOT this session):** batch/directory/glob; a regex or unified-diff apply mode; structured-format
  (JSON/YAML/CSV) field edits; a sibling `fs.manage` (move/copy/rename/delete/mkdir); more encodings; a read-only or
  per-file-lock `parallel_safe:true` mode + a tail/follow read; insert-at-line / replace-line-range ops.

## Module 21 (build order) — Local Orchestrator / Agent (`agent.local`)
- **id:** `agent.local` · **Priority:** Phase A #3 (D-0029) · **Status:** **MVP complete (2026-07-25)**
- **Folder-number note:** on-disk `modules/21-agent-local/`. The `NN-` prefix is a **monotonic build-order counter**
  (0, 00.1, 1..20, then 21); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `agent.local` is a **scoped
  slice of `skill.orchestrator` (#26)** pulled forward as the local-orchestrator cost-offload keystone — not the video-block "21".
- **Purpose:** a **bounded, ReAct-style local agent loop** — the frontier agent's tool loop, done locally. Given a
  natural-language **goal** it decides which Module (tool) to call, generates that tool's arguments, invokes it, observes
  the result, and repeats until it decides `finish` or the `max_steps` budget is hit. Every goal a local agent finishes
  end-to-end is orchestration the frontier allotment never pays for.
- **Composition (reimplements nothing):** DECISIONS route **through `logic.escalator` (#19)** as a closed-set `classify`
  task (labels = the registered tool names + `finish`) — the escalator's deterministic **in-set gate** guarantees a valid
  action (or surfaces `needs_frontier`) and its tiny→weak→mid ladder is the cost-offload; ARG-GENERATION + the FINAL ANSWER
  use **`model.gateway` (#7)**; TOOLS are conforming Modules spawned as child skills (the `image.index` #18 pattern) from a
  **declarative closed registry** (`tools.json`, ships **`doc.io` #20 + `fs.observer` #2**). The registry **is** the sandbox
  — no arbitrary-shell / code-exec tool.
- **Guardrails (first skill where a local model chooses side-effecting actions):** a **hard `max_steps` budget** (default 4;
  exhausting → `status:"stopped"` + `needs_frontier:true`); a **`-DryRun` plan-preview** (records the intended tool+args per
  step, invokes nothing); `needs_frontier` surfaced as a status field (never a frontier call / queue write).
- **Flags:** `determinism:"mixed"`, `parallel_safe:false` (drives the gateway → GPU/port, can invoke `doc.io` mutations),
  `batch:false`, `streaming:false`. **Orchestrator, NOT a review-queue producer** (redirects child review writes to an
  in-artifact `child_review.jsonl`; canonical queue + the seven-producer set untouched). No new model / no `models.json`
  change / no Module 7 re-verify.
- **Tests:** **39/39 mock off-machine (cloud pwsh 7.4.6, real orchestrator + mock-children harness + real Module 1 wrapper)
  + 39/39 the same harness `-Live`** (`m21-test-001`, exit 0) **+ a REAL end-to-end run** (`m21-live-001`): "create hello.txt
  containing 'hi from agent.local'" → chose `doc.io` via the escalator, the 3B produced the args, **the file was written on
  disk with the exact content**; a second goal invoked `fs.observer`; 0 orphaned `llama-server`; canonical queue 1→1. 10
  files sha256 byte-exact + AST-parse OK on the target (`m21-verify-001`).
- **Honest finding (D-0032):** the tiny/weak/mid models **under-use the `finish` action** — both live goals ran to
  `max_steps` (re-doing the completed action) instead of self-terminating; the hard budget caught it every time (`stopped` +
  `needs_frontier`, final answer still correct). Better termination (a deterministic goal-satisfied / repeat-action check, or
  a dedicated "are-we-done?" gate) is the **#1 measured follow-on**, not built here.
- **Implementation:** `modules/21-agent-local/` (`Invoke-AgentLocal.ps1`, `skill.json`, `tools.json`, `README.md`,
  `WORK_ORDER.md`, `.gitignore`, `tests/{mock-child,Invoke-AgentLocalTests}.ps1`, `examples/`). **Work order:**
  `modules/21-agent-local/WORK_ORDER.md`. See **D-0032**.
- **Follow-ons (NOT this session):** better termination (above); a warm/persistent gateway worker (shared with
  #7/#8/#12/#14/#16/#17/#19) to kill the per-step cold-load cost; richer planning (sub-goals, reflection-retry, a planning
  DAG); more tools in the registry (perception / audio / generator Modules) with per-tool arg schemas; a `route.tasks` (#24)
  drain of `needs_frontier` goals; registry auto-discovery from module manifests; a `batch` multi-goal mode; calibrated
  decision confidence; persistent working-memory across invocations.

## Module 22 (build order) -- Local Audio Generation (`gen.audio`)
- **id:** `gen.audio` · **Priority:** Phase A #4 (generators, cheapest-first; D-0029) · **Status:** **MVP complete (2026-07-25)**
- **Folder-number note:** on-disk `modules/22-gen-audio/`. The `NN-` prefix is a **monotonic build-order counter** (0, 00.1, 1..21, then 22); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `gen.audio` is the first of the generator set (`gen.audio` → `gen.image` → `gen.music` → `gen.video`), pulled forward as the *cheapest* generator; the video-block "22 video.interpret" below is an architectural label (Phase C), not this folder.
- **Purpose:** the cheapest generator -- synthesize one **non-speech, non-music** audio primitive from a compact spec: a `tone`/`chord` (sine/square/triangle/sawtooth, by Hz or equal-temperament note name), colored `noise` (white/pink/brown/blue/violet/velvet; seeded → reproducible), a linear `sweep` (chirp), or `silence`. The audio counterpart of `image.util` (deterministic pixels).
- **Design (probe-driven, D-0033):** a **deterministic, procedural ffmpeg synthesizer** -- one `-f lavfi` source per kind (`aevalsrc` waveform expressions / `anoisesrc` / `anullsrc`) encoded to wav/mp3/flac/opus/ogg/m4a in a single ffmpeg pass (codec map == `audio.ingest`). Pure PowerShell wrapping the present ffmpeg 8.1; reuses `audio.ingest`'s process/resolution/envelope machinery. **Probe-first** (`m22-probe-001`: ffmpeg lavfi synthesis verified end-to-end; **no** neural audio-gen stack staged -> neural text-to-audio SFX deferred as a follow-on).
- **Flags:** `determinism:"deterministic"` (confidence null, model_provenance empty; seeded noise), `parallel_safe:true` (CPU-only, no GPU/port/shared state), `batch:false`, `streaming:false`. **NOT a review-queue producer** (the seven-producer set + canonical queue untouched). No new model / no `models.json` change / no Module 7 re-verify.
- **Tests:** **41/41 off-machine** (cloud pwsh 7.4.6 + real cloud ffmpeg 6.1.1, real skill + real harness -- no mock) + **43/43 `-Live`** via the executor (`m22-test-001`, exit 0) incl. the Module 1 manifest-validator + wrapper; canonical `review_queue.jsonl` before==after (1->1). 8 files sha256 byte-exact + AST-parse OK on the target.
- **Implementation:** `modules/22-gen-audio/` (`Invoke-GenAudio.ps1`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/Invoke-GenAudioTests.ps1`, `examples/`). **Work order:** `modules/22-gen-audio/WORK_ORDER.md`. See **D-0033**.
- **Follow-ons (NOT this session):** a **neural text-to-audio SFX tier** (AudioGen/AudioLDM/Stable Audio Open -- install a stack + stage a model on F:; adds `model_provenance` + a real `confidence` + review-producer behaviour); batch/multi-signal output; ADSR envelopes / per-partial amplitudes / detune; DTMF & Morse & metronome presets; a waveform option for sweep; a guarded arbitrary-`aevalsrc` expression; stereo panning / binaural beats; a direct pipe into `audio.ingest` for one-call loudness-normalized output.

## Module 23 (build order) -- Local Image Generation (`gen.image`)
- **id:** `gen.image` · **Priority:** Phase A #5 (generators, cheapest-first; D-0029) · **Status:** **MVP complete (2026-07-25)**
- **Folder-number note:** on-disk `modules/23-gen-image/`. The `NN-` prefix is a **monotonic build-order counter** (0, 00.1, 1..22, then 23); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `gen.image` is the second generator (`gen.audio` → `gen.image` → `gen.music` → `gen.video`) and an early standalone build of the #44 family (Qwen-Image / FLUX.1-schnell / SDXL); the higher-integration architectural "23" (`artifact.search`) is a different, later slot.
- **Purpose:** the **first neural generator** -- turn a text prompt into one image with a local **Stable Diffusion 1.5** pipeline (`diffusers` `StableDiffusionPipeline`, fp16, CUDA), driven by a Python worker + meta-file hand-off (the D-0021 `speech.tts` pattern). The generation counterpart of `image.interpret` (#17, which reads an image).
- **Design (probe-driven, D-0034):** SD 1.5 (diffusers fp16, CreativeML OpenRAIL-M) staged on F:, resolved from `models.json` (`image.sd15`, `type=image-gen`, decoupled from the gateway `wired` gate); `diffusers` 0.35.2 installed into the speech venv (torch 2.11+cu128), gated on a **Module 12 safety re-verify** (torch/transformers/`qwen_tts` intact). Controls: prompt/negative, width/height (512; mult 8, 128..1024), steps (20, DPM++), guidance (7.5), seed (-1=random, recorded), scheduler (dpm++|euler|euler_a|ddim), format (png|jpg|webp). **Probe-first** (`m23-probe-001/002`: no checkpoint existed; installed diffusers + staged SD1.5 + live-generated 512x512 in 2.8 s, VRAM peak 2.61 GB).
- **Flags:** `determinism:"mixed"` (stochastic sampler, seedable; a fixed seed is byte-reproducible on this GPU), `parallel_safe:false` (binds CUDA/VRAM), `batch:false`, `streaming:false`. **Eighth review-queue producer** (below-threshold / blank / failed -> `verify_generation`, `flagged_by:"gen.image"`; producer set 7/8/11/12/14/16/17/**23**). Confidence = a generation-completeness / non-blank heuristic (pixel std).
- **Tests:** **42/42 off-machine** (cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper) + **32/32 `-Live`** via the executor (`m23-test-005`, real SD generations, same-seed byte-reproducible, real JPEG, canonical queue 1->1, 0 orphans); 10 files sha256 byte-exact + AST-parse OK on the target; **Module 7 re-verified 28/28** (`m23-m7regress-001`).
- **Implementation:** `modules/23-gen-image/` (`Invoke-GenImage.ps1`, `gen_image_infer.py`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/{Invoke-GenImageTests.ps1,mock-worker.py}`, `examples/`). **Work order:** `modules/23-gen-image/WORK_ORDER.md`. See **D-0034**.
- **Follow-ons (NOT this session):** heavier/faster tiers -- **FLUX.1-schnell** (Apache-2.0; needs offload/quant on 11 GB) + **SDXL / SDXL-Turbo** (non-commercial); img2img / inpainting / ControlNet / upscaling / LoRA / DreamBooth; `num_images>1` batch / grids; a warm/persistent pipeline worker (shared with #7/#8/#12/#17/#19); calibrated / aesthetic-model confidence; a real prompt-safety pass; more schedulers / Karras sigmas.

## Module 24 (build order) -- Local Music Generation (`gen.music`)
- **id:** `gen.music` - **Priority:** Phase A #4 (generators, cheapest-first; D-0029) - **Status:** **MVP complete (2026-07-26)**
- **Folder-number note:** on-disk `modules/24-gen-music/`. The `NN-` prefix is a **monotonic build-order counter** (0, 00.1, 1..23, then 24); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `gen.music` is the third generator (`gen.audio` -> `gen.image` -> `gen.music` -> `gen.video`) and the second neural one; music generation is folded into the #44 generator family (no dedicated spine slot).
- **Purpose:** turn a text prompt into one short **instrumental** clip with a local **MusicGen Small** model (transformers `MusicgenForConditionalGeneration`, CUDA), driven by a Python worker + meta-file hand-off (the D-0021/D-0034 pattern). The music sibling of `gen.audio` (#22, procedural sound) and the audio counterpart of `gen.image` (#23, neural pixels).
- **Design (probe-driven, D-0035):** MusicGen Small (`facebook/musicgen-small`, transformers folder, CC-BY-NC-4.0) staged on F: (~2.37 GB after pruning redundant weights), resolved from `models.json` (`music.musicgen-small`, `type=music-gen`, `engine=transformers`, decoupled from the gateway `wired` gate); **NO new library install** (transformers 4.57 already ships MusicGen -> Module 12 unaffected). Produces 32 kHz mono PCM16 WAV (peak-normalized); optional non-wav `-Format`/`-SampleRate` via `audio.ingest` (#10). Controls: prompt, duration (1..30 s -> ~50 tokens/s), guidance (3.0), temperature/top_k/top_p, seed (-1=random, recorded; fixed seed byte-reproducible), format. **Probe-first** (`m24-probe-001/002`: transformers has MusicGen; no music model staged; downloaded + staged + live-generated a 5.06 s clip in 7.6 s, VRAM peak 2.4 GB, seed byte-reproducible before coding).
- **Flags:** `determinism:"mixed"` (stochastic sampler, seedable), `parallel_safe:false` (binds CUDA/VRAM), `batch:false`, `streaming:false`. **Ninth review-queue producer** (below-threshold / silent / failed -> `verify_generation`, `flagged_by:"gen.music"`; producer set 7/8/11/12/14/16/17/23/**24**). Confidence = a generation-completeness / non-silent heuristic (audio RMS).
- **Tests:** **49/49 off-machine** (cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper) + **42/42 `-Live`** via the executor (`m24-test-002`: real MusicGen generations, same-seed byte-reproducible, mp3 + resample via the real audio.ingest, canonical queue 1->1, 0 orphaned python/llama-server); 10 files sha256 byte-exact + AST-parse OK on the target (`m24-verify-001`); **Module 7 re-verified 28/28** (`m24-m7regress-001`).
- **Implementation:** `modules/24-gen-music/` (`Invoke-GenMusic.ps1`, `music_gen_infer.py`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/{Invoke-GenMusicTests.ps1,mock-worker.py}`, `examples/`). **Work order:** `modules/24-gen-music/WORK_ORDER.md`. See **D-0035**.
- **Follow-ons (NOT this session):** MusicGen **Medium/Large** tiers or **Stable Audio Open**; **MusicgenMelody** (melody-conditioned); batch / multi-clip; a warm/persistent pipeline worker (shared with #7/#8/#12/#17/#19/#23); calibrated / aesthetic-model confidence; a prompt-safety pass; stereo; **>30 s** via sliding-window continuation; fp16.

## Module 25 (build order) -- Local Video Generation (`gen.video`)
- **id:** `gen.video` - **Priority:** Phase A #4 (generators, cheapest-first; D-0029) - **Status:** **MVP complete (2026-07-26)**
- **Folder-number note:** on-disk `modules/25-gen-video/`. The `NN-` prefix is a **monotonic build-order counter** (0, 00.1, 1..24, then 25); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `gen.video` is the fourth (last) generator (`gen.audio` -> `gen.image` -> `gen.music` -> **`gen.video`**) and the third neural one; text-to-video is folded into the #44 generator family (the ARCHITECTURE_MAP "19-22 video" block below is the perception/decompose stack, NOT generation).
- **Purpose:** turn a text prompt into one short **silent** clip with a local **AnimateDiff-Lightning** pipeline -- an SD-1.5 base (reused from `gen.image` #23) + a 4-step motion adapter -- driven by a Python worker + meta-file hand-off (the D-0021/D-0034/D-0035 pattern). The motion sibling of `gen.image` (#23, neural stills).
- **Design (probe-driven, D-0036):** diffusers `AnimateDiffPipeline` (fp16, CUDA): a `MotionAdapter` from `ByteDance/AnimateDiff-Lightning` (`animatediff_lightning_4step_diffusers.safetensors`, ~907 MB, CreativeML-OpenRAIL-M) staged to F: under `25-gen-video\animatediff-lightning\`, loaded ON TOP OF the staged SD 1.5 (`variant="fp16"`), EulerDiscreteScheduler(trailing/linear), vae slicing, `.to("cuda")`. Resolved from `models.json` (`video.animatediff-lightning`, `type=video-gen`, `engine=diffusers`, decoupled from the gateway `wired` gate); added `defaults.video`/`tiers.video`. **NO new library install** (diffusers 0.35.2 already present; MP4 via the present ffmpeg, GIF via Pillow). **Probe-first** (`m25-probe-001/002`): no video model staged; downloaded + staged the adapter + live-generated 16 frames 512x512 4-step in ~57 s warm, **VRAM peak 4.75 GB full-GPU (no offload)**, pixel_std 44.4 / mean interframe diff 41.6, seed byte-reproducible, before coding.
- **Flags:** `determinism:"mixed"` (stochastic sampler, seedable), `parallel_safe:false` (binds CUDA/VRAM), `batch:false`, `streaming:false`. **Tenth review-queue producer** (blank / static / failed -> `verify_generation`, `flagged_by:"gen.video"`; producer set 7/8/11/12/14/16/17/23/24/**25**). Confidence = a generation-completeness / non-blank + non-static heuristic (frame pixel std + inter-frame difference).
- **Tests:** **54/54 off-machine** (cloud pwsh 7.4.6 + a stdlib mock worker driving the *real* wrapper) + **46/46 `-Live`** via the executor (`m25-test-002`: real AnimateDiff generations non-blank + motion + VRAM-fit, same-seed byte-reproducible, mp4 magic + gif, canonical queue before==after, 0 orphaned python); 10 files sha256 byte-exact + AST-parse OK on target (`m25-verify-001`); **Module 7 re-verified 28/28** (`m25-m7regress-001`).
- **Implementation:** `modules/25-gen-video/` (`Invoke-GenVideo.ps1`, `video_gen_infer.py`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/{Invoke-GenVideoTests.ps1,mock-worker.py}`, `examples/`). **Work order:** `modules/25-gen-video/WORK_ORDER.md`. See **D-0036**.
- **Follow-ons (NOT this session):** AnimateDiff full 25-step / SVD image-to-video / CogVideoX / LTX (bf16, need newer HW); img2video / video2video; ControlNet / motion-LoRA; frame interpolation + upscaling; >~2 s via sliding-window; an audio track; a warm/persistent pipeline worker; calibrated / motion-quality confidence; a prompt-safety pass.

## Module 26 (build order) -- Coding Agent (`agent.coding`)
- **id:** `agent.coding` · **Priority:** Phase A #5 (last) · **Status:** **DEFERRED (2026-07-26, D-0037; WORK_ORDER authored, NOT built)**
- **Folder-number note:** on-disk `modules/26-agent-coding/` (WORK_ORDER.md only). The `NN-` prefix is a monotonic build-order counter (0, 00.1, 1..25, then 26); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `agent.coding` is the coding specialization of `agent.local` (#21) / a scoped slice of `skill.orchestrator` (#26 architectural).
- **Purpose (as designed):** a bounded local coding loop -- draft code -> statically check -> (gated) run in a scratch dir -> read the error -> fix -> repeat -- the frontier's write/run/fix loop, done locally. A specialization of `agent.local` (#21): the same ReAct loop + hard `max_steps` budget, DECISIONS through `logic.escalator` (#19), codegen + final answer via `model.gateway` (#7), tools from a closed registry.
- **Designed MVP tools (`tools.json`):** `code.write` (via `doc.io` #20, path forced under the invocation scratch dir); `code.check` (a NEW deterministic static verifier -- Python `py_compile`/`ast.parse`, PowerShell `Parser::ParseFile`, `node --check` -- no execution); `code.run` (GATED: child process confined to the scratch dir, hard timeout, no network, requires an `-AllowRun` opt-in AND a resolvable safe substrate, else `execution_not_permitted`). NO arbitrary-shell tool (the registry IS the sandbox, D-0032).
- **Deferred (D-0037), because:** (1) NO safe code-execution substrate exists on this box (`m26-probe-001`: WSL launcher but no distro; Windows Sandbox absent + needs elevation on this non-admin box; Docker absent; PowerShell FullLanguage) -- the useful slice needs `code.run`, and running local-model-authored code at full Windows-user authority is a safety escalation (the arbitrary-exec capability agent.local deliberately excluded); a real sandbox is a large, admin-gated, separate effort (D-0001). (2) Lowest near-term ROI (the frontier already codes well; the weak local tiers are poor at code -- D-0030 sub-95%/0.20 false-approval, D-0032 poor termination). (3) A coding agent WITHOUT `code.run` is ~`agent.local` + a lint tool (better a tool addition than a module).
- **Tests / flags (as designed):** the agent.local mock-children + `-Live` harness pattern; `determinism:"mixed"`, `parallel_safe:false`, `batch:false`, `streaming:false`; orchestrator/non-producer (redirects child review writes; the ten-producer set + canonical queue untouched); no `models.json` change / no Module 7 re-verify.
- **Implementation:** `modules/26-agent-coding/WORK_ORDER.md` (the build-ready design + the deferral). See **D-0037**.
- **Revisit-if (build when any lands):** a safe execution substrate (a WSL distro installed / Windows Sandbox enabled / a container runtime / a vetted restricted-runspace/job-object sandbox Module); a code-specialized local model staged + wired via `model.gateway`; a warm/persistent gateway worker; Phase B pull demand (a Widget needs a local coding loop); or the user explicitly wants it.
- **Interim option (no module):** add a deterministic `code.check` (static parse/lint) tool to `agent.local`'s `tools.json` -- safe, cheap, lets the existing agent draft + syntax-check a script today without the execution risk.

## Module 27 (build order) -- Tool Router (`route.tools`)
- **id:** `route.tools` - **Priority:** Phase B (Module-capable widgets; a scoped slice of `route.tasks` #24) - **Status:** **MVP complete (2026-07-26, D-0040)**
- **Folder-number note:** on-disk `modules/27-route-tools/`; the `NN-` prefix is a monotonic build-order counter (0, 00.1, 1..26, then 27). `route.tools` is the which-tools pass of `route.tasks` (#24), pulled forward so `agent.local` (#21) + the Local Agent Console can USE/ATTACH Modules through one intermediary.
- **Purpose:** given a request + the attachable-tools registry (agent.local's `tools.json`), emit the minimal set of tool ids needed -- fast, NON-executing. Calls `model.gateway` (#7) at the MID tier with the validated router prompt (m27-router-001), parses the JSON array, and DETERMINISTICALLY GATES it against the catalog -> `result.tools`. MID/non-thinking tier only -- `tier=strong` is REFUSED (the 27B thinking model emits empty output). Injection-resistant (treats the request as text + the gate drops any non-catalog id).
- **Flags:** `determinism:"mixed"`, `parallel_safe:false`, `batch:false`, `streaming:false`. Orchestrator, NOT a review producer (redirects the child gateway's review writes; the ten-producer set is untouched).
- **Tests:** 34/34 off-machine (cloud pwsh 7.4.6 + a mock gateway) -> `m28-verify-001` 37/37 + `m28-harness-001` 34/34 + `m28-live-001` REAL 3B routing on target. **Implementation:** `modules/27-route-tools/` (`Invoke-RouteTools.ps1`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/{mock-gateway,Invoke-RouteToolsTests}.ps1`, `examples/`). See **D-0040**.
- **Also this session (D-0041):** `agent.local` (#21) gained `-Route` (route-then-constrained ReAct loop) + a curated 10-tool registry + a grounded final answer; the Local Agent Console (Widget 01) gained Plan (route-only) / Run (route+execute). REAL e2e (`m28-e2e-001` 9/9): "make an image of a dog" -> [gen.image] -> a real image.png on disk. `fs.manage` (copy/move/mkdir) deferred as the next gap.

## Module 28 (build order) -- File Manage (`fs.manage`)
- **id:** `fs.manage` - **Priority:** the deferred "deposit on the desktop" last-mile (D-0041) - **Status:** **MVP complete (2026-07-26, D-0042)**
- **Folder-number note:** on-disk `modules/28-fs-manage/`; the `NN-` prefix is a monotonic build-order counter (0, 00.1, 1..27, then 28). The `doc.io` (#20) `fs.manage` sibling named there, scoped to copy/move/mkdir.
- **Purpose:** the deterministic last-mile file placement -- **copy | move | mkdir** (one op/call). Smart path resolution: known folders (desktop/downloads/documents/pictures/music/videos/home/temp via `[Environment]::GetFolderPath`, so a OneDrive-redirected Desktop resolves correctly), `~`, `%ENV%`, absolute, relative; a folder dest keeps the source filename; overwrite-guarded. Pure PowerShell + .NET; `determinism:"deterministic"`, `parallel_safe:false`, NOT a review producer.
- **Wired into agent.local (#21):** a new per-tool `resolve_paths:false` flag (the agent passes fs.manage's path args verbatim, so a bare `desktop` is not prefixed with working_dir), `Get-Observation` surfaces gen.image's `image.path`, the arg-gen steers resolve_paths:false tools to a known-folder name, and a `route.tools` few-shot teaches "generate a file AND place it -> two tools".
- **Tests:** 21/21 off-machine + agent.local 54/54 (incl. the resolve_paths S13) -> `m29-verify-001` 25/25 on target -> **REAL e2e `m29-after-003` 6/6: "Generate an image of a dog and place it on my desktop" -> router `[gen.image, fs.manage]` -> a real 606 KB dog image on the REAL Desktop.** **Implementation:** `modules/28-fs-manage/` (`Invoke-FsManage.ps1`, `skill.json`, `README.md`, `WORK_ORDER.md`, `.gitignore`, `tests/Invoke-FsManageTests.ps1`, `examples/`). See **D-0042**. **Follow-on:** `delete`/`rename` (gated), directory ops, better agent termination (D-0032, the models still under-use `finish`).
## Modules 19–22 — Video (architectural positions; deferred to Phase C)
**Note:** the `19–22` here are **architectural positions** (`ARCHITECTURE_MAP.md`), NOT build-order folder numbers — the
Phase-A build pulled `logic.escalator` forward into the on-disk folder `modules/19-logic-escalator/` (entry just above).
The video block is deferred to Phase C and takes its own next-free folder numbers when built.
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

## Adaptive Resource Governor (agent.local #21) -- Phases 2-3 (upcoming; D-0043)

Not a new module -- a behavior track over `agent.local` #21 / `logic.escalator` #19 / `model.gateway` #7 / `route.tools` #27. **Phase 1 is DONE (D-0043):** the decision floor was raised to MID (dropping the tiny/weak ladder that anchored the competent tier on weak answers), a `-Profile` knob (frugal|floor|max) was added as the governor's rungs, and the 27B was un-refused in route.tools. The two remaining units:

- **Phase 2 -- warm / persistent model server (the enabler).** `model.gateway` #7 starts a TRANSIENT `llama-server` per call and evicts on model change (~60-90 s cold load every tier switch). Keep a RESIDENT server: reuse it across calls, evict+load only on an actual model change, measure warm-vs-cold. This is what makes escalating to the 27B (and the Phase-3 ramp) cheap enough to use by default. Design note: it is why the cold `max` runs take minutes today.
- **Phase 3 -- auto-ramp resource governor (the goal).** A controller that starts at the `floor` rung and RAMPS toward the machine ceiling only when the run is not succeeding: run at floor -> on unsolved / failed-verification, ramp the envelope (escalate generation to the 27B, raise tokens/steps, add a strong VERIFICATION pass) -> stop at verified-success OR local ceiling. The `-Profile` rungs are the ramp steps; the warm server (Phase 2) makes each rung affordable. **Design input already measured (D-0043):** decision-escalation to the 27B must be a DIRECT classify call with adequate budget (the escalator judge re-breaks it with empty output), and/or the escalator must prefer a lower tier's valid answer over a higher tier's empty one.
