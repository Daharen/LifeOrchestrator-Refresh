# ARCHITECTURE_MAP

Owns the **long-horizon architecture spine** — the full module map we are building toward, the real-time
control layers, and the operating hierarchy. This is the "where we are going" reference.

**Read this only for orientation / long-range planning.** It is **not** the build order — the current,
re-prioritized build order lives in `MODULE_ROADMAP.md` (see its "Build priority" section, D-0029). The
module numbers below are **architectural positions, not a build sequence.**

## Two kinds of thing we build (vocabulary — D-0029)
- **Module** — a backend capability/tool that AI agents (and Widgets) invoke through the skill contract.
  Everything under `modules/` (0-49 below). A Module is modular because it satisfies `SKILL_CONTRACT.md`,
  not because of its language.
- **Widget** — a human-interface tool (a real window/application) that connects a *person* into the module
  architecture, usually by driving the local orchestrator + Local Logic Escalator so it can reach every
  Module without embedding each one. Widgets live under `widgets/` and are how the whole package becomes
  usable by a human, not only by an agent. (The HID / human-interface layer; "Widget" keeps it colloquial
  and modular while signalling these are full apps that plug in, not lesser sub-windows.) See `widgets/README.md`.

## Model-candidate annotation (read before trusting any model name below)
Model names are **non-binding, open-weight candidates** listed to show feasibility and rough sizing —
**not commitments.** This machine currently runs only the models recorded in `TOOL_MODEL_REGISTRY.md`; a
model named here becomes real only when it is downloaded, invoked on this box, and recorded there with its
exact checkpoint + license. **"Deterministic - no model"** means the Module is primarily software (an LLM
may help build or supervise it but does not run in its hot path). Repeated models are intentional: one
local model can back several Modules.

---

## The canonical spine (0-49)

### Foundation & local-agent infrastructure (0-9) — BUILT
- **0 `exec.bootstrap`** — Trusted High-Risk Bootstrap Executor. Deterministic. **BUILT.**
- **00.1 `exec.watchdog`** — cooperative executor recovery. Deterministic. **BUILT.**
- **1 `skill.bootstrap`** — skill contract + registry + generic wrapper. Deterministic. **BUILT (contract v0.2).**
- **2 `fs.observer`** — filesystem inspect/search/index. Deterministic (optional summarizer: small Qwen3 / Granite 4.0). **BUILT.**
- **3 `proc.observer`** — process + window snapshot. Deterministic. **BUILT.**
- **4 `uia.inspector`** — read-only UI Automation tree. Deterministic. **BUILT.**
- **5 `uia.actor`** — UIA control-pattern actions. Deterministic. **BUILT.**
- **6 `capture.screen`** — screenshot / region capture. Deterministic. **BUILT.**
- **7 `model.gateway`** — hosts + normalizes every local model. Infra (no model of its own). **BUILT.**
- **8 `classify.batch`** — batch classify / label / extract. Weak LLM (Qwen2.5/Qwen3 0.6-8B; + embedding + reranker). **BUILT.**
- **9 `review.processor`** — review-queue adjudication. Stronger LLM (Qwen3 8-30B-A3B / Granite 4.0 / Mistral Small 3.1). **BUILT.**

### Audio (10-13) — BUILT
- **10 `audio.ingest`** — decode/resample/normalize/segment. Deterministic (ffmpeg). **BUILT.**
- **11 `speech.stt`** — transcription + timestamps. whisper.cpp today; candidates Qwen3-ASR, + Silero VAD for segmentation. **BUILT.**
- **12 `speech.tts`** — synthesis. Qwen3-TTS today; candidates Kokoro-82M, Piper, Silero TTS. **BUILT.**
- **13 `voice.live`** — one voice turn (STT -> LLM -> TTS). Composition; + VAD for true live. **BUILT (file-driven).**

### Image & document perception (14-18) — BUILT
- **14 `ocr.layout`** — OCR + word boxes + reading order. Windows.Media.Ocr today; candidates PP-OCRv5 / PaddleOCR-VL / PP-StructureV3, OmniParser V2 for screens. **BUILT.**
- **15 `image.util`** — resize/crop/hash/tile/similarity/meta. Deterministic (Pillow); candidates DINOv2/3, VL-embeddings for semantic dedup. **BUILT.**
- **16 `detect.objects`** — object boxes + real scores. YOLOX/ONNX today; candidates RTMDet, Grounding DINO, YOLO26/YOLOE-26, SAM 2 (masks). **BUILT.**
- **17 `image.interpret`** — VLM caption/VQA/screen. Qwen2.5-VL-3B today; candidates Qwen3-VL, InternVL3.5, MiniCPM-V 4.5. **BUILT.**
- **18 `image.index`** — fuse 14-17 into one per-image record. Composition. **BUILT.**

### Video (19-22) — planned
- **19 `media.decompose`** — audio / subs / scene cuts / keyframes / clips / proxies. Deterministic (ffmpeg; optional embedded STT/OCR).
- **20 `track.objects`** — identity across frames. SAM 2 + ByteTrack over a detector (16).
- **21 `video.timeline`** — fuse transcription + scenes + OCR + detections + tracks -> searchable timeline. Composition.
- **22 `video.interpret`** — selective frames/clips -> VLM. Qwen3-VL / InternVL3.5 / MiniCPM-V; InternVideo for action features.

### Search, routing, orchestration (23-26) — planned
- **23 `artifact.search`** — retrieval over all local-skill artifacts. Embeddings + reranker (Qwen3-Embedding/Reranker, BGE-M3, Granite Embedding). Owns the staged `embedding.qwen3-0p6b`.
- **24 `route.tasks`** — model/tool task router by type/confidence/cost/time. Mostly deterministic policy + benchmarking; a small LLM for the fuzzy part. **The near-term Local Logic Escalator generalizes this + #9 (pulled forward — see roadmap).**
- **25 `observe.broker`** — route one desktop-observation question across fs / proc / UIA / OCR / capture. Small LLM + deterministic policy.
- **26 `skill.orchestrator`** — compose skills into workflows; scheduling / locking / retries / gates / state persistence are programmed. **Redefined by the real-time layer as the *slow deliberative planner*, not the frame-to-frame executor.**

### General screen-world perception & the self-improving loop (27-44) — long-horizon, deferred
- **27** Network knowledge & media acquisition — deterministic fetch/provenance/parse; small LLM for query expansion + result ranking.
- **28** Hierarchical screen parser — OmniParser V2 / ShowUI-2B / PP-OCRv5 + a VLM for unresolved regions.
- **29** Open-vocabulary grounding & segmentation — Grounding DINO + SAM 2 + YOLOE-26 + a VLM.
- **30** Visual asset & instance registry — DINOv2/3 + VL-embeddings + VL-reranker; persistent identities (custom registry).
- **31** Application ontology & schema learner — VLM + LLM; the graph + evidence system is custom. *(least pre-solved)*
- **32** Active annotation & dataset builder — Grounding DINO + SAM 2 + DINOv2 + VLM; versioning / leakage / splits custom.
- **33** Specialist model training & distillation — LoRA / QLoRA / teacher-student pipelines (RTMDet / YOLO / ShowUI / VLM / SAM 2).
- **34** Specialist evaluation & calibration gate — deterministic metrics / calibration / held-out; optional VLM / DINO reviewers.
- **35** Temporal screen state graph — SAM 2 / ByteTrack / VL-embeddings; persistent identity + causality (custom). **Gains a fast mutable state layer (real-time).** *(least pre-solved)*
- **36** Interaction trace reconstruction — UI-TARS-1.5-7B / ShowUI / CogAgent / VLM; temporal causal logic custom. *(least pre-solved)*
- **37** Active exploration & affordance learner — UI-TARS / ShowUI / CogAgent / VLM; exploration policy + safe experimentation custom. *(least pre-solved)*
- **38** Visual-only action executor — UI-TARS / ShowUI / CogAgent / OmniParser; input injection + coordinate reconciliation deterministic.
- **39** Outcome verification, recovery & rollback — VLM + UI-TARS / ShowUI; state-diff / retries / rollback custom. **Gains multi-timescale verification (real-time).** *(least pre-solved)*
- **40** Demonstration & procedure learner — ShowUI-Aloha / UI-TARS / VLM; durable verified procedures custom. *(least pre-solved)*
- **41** Screen-only diagnostic reasoner — VLM 8B+ (Qwen3-VL / InternVL3.5) + strong LLM; evidence + diagnostic-test generation custom. *(least pre-solved)*
- **42** Retrospective screen forensics orchestrator — VLM + ASR + OmniParser + Grounding DINO + SAM 2 + DINO + embeddings; composition. *(least pre-solved)*
- **43** Opaque computer operator — UI-TARS / ShowUI / CogAgent / OmniParser / VLM; the closed-loop operator is an engineered composite. *(least pre-solved)*
- **44** Synthetic screen & asset generator — Qwen-Image / FLUX.1-schnell / Stable Diffusion XL (+ DreamBooth / LoRA as adaptation methods). **The near-term Image Generator is an early standalone build of this family (see roadmap).**

## The real-time autonomic layer (45-49) — long-horizon, deferred
**Rationale.** Real-time operation (games, live work) cannot be "capture -> ask an LLM -> act -> repeat":
too slow, expensive, and brittle. It needs a hybrid reactive-deliberative architecture — an *autonomic
nervous system*: fast local loops perceive and act continuously while a slow reasoner revises goals only
when routine expectations fail. A pile of weak models is **not** automatically autonomic; the autonomic
quality comes from the control architecture *around* them.
- **45** Real-Time Perception & Control Runtime — persistent async loops at different frequencies (capture, trackers, detectors, state, reactive policies, occasional planning) that do not block each other (a tracker at 30-60 fps while a VLM spends seconds on an unfamiliar menu).
- **46** Event, Salience & Interrupt Broker — converts continuous change into *sparse meaningful events*; only above-threshold events interrupt higher layers (attention / autonomic interrupt).
- **47** Reactive Skill & Reflex Runtime — very fast bounded policies (state machines, behavior trees, tiny classifiers / compact policies, controller scripts) — mostly **not** LLM calls.
- **48** Skill Arbitration & Action Inhibition — decides which policy owns each input channel, priorities, concurrency, inhibition, and when control returns to the planner. (Without it, many fast models are worse than one slow model — they issue conflicting actions.)
- **49** Predictive State & Short-Horizon World Model — predicts near-future state changes to select behavior (world-model style, e.g. DreamerV3 lineage) — useful state, not full-frame video.

**Modules extended by this layer:** **#26** becomes the *slow deliberative planner* (goals, procedures,
control authority, novel-failure handling, commissioning specialists) — not the frame-to-frame executor;
**#35** gains a fast mutable state layer distinguishing raw / confirmed / predicted / hypothesis / goals /
running reflexes / expected transitions / interrupt conditions, updatable without an LLM; **#39** gains
multi-timescale verification (frame / seconds / minutes / whole session), correcting short failures locally
instead of escalating.

## Operating hierarchy (how the layers run together)
- **L0 Deterministic signal processing** (us-ms): capture, input events, image diffing, coordinate transforms, timers, resource monitoring. No model.
- **L1 Reflexive perception/control** (~10-100 ms): compact detectors, optical flow, trackers, cursor localization, tiny state classifiers, immediate inhibition, learned micro-policies. Continuous on GPU/CPU.
- **L2 Reactive skills** (~100 ms-s): navigation, camera, menus, following, known recovery. Behavior trees / FSMs / small learned policies.
- **L3 Tactical coordination** (s-min): choose a target / procedure, sequence reactive skills, decide what to inspect. A small local reasoner, much of it compiled to deterministic procedures over time.
- **L4 Deliberative reasoning** (s-many min): understand an unfamiliar interface, diagnose, plan, search docs, revise the ontology, commission a specialist. Strong local LLM or frontier.
- **L5 Offline consolidation** (min-hr): analyze recordings, retrain / distill specialists, mine recurring patterns, improve procedures, evaluate new models. Learning / consolidation, not immediate action.

## The long-term mechanism (why this converges to cheap + fast)
Progressively move competence *downward*: **strong model reasons through a novel situation -> strong model
names a recurring pattern and defines a procedure -> weak model selects that procedure -> a deterministic
or compact learned controller executes + verifies it automatically.** This is the project's
stochastic-discovery-then-deterministic/specialized-collapse doctrine applied to real-time behavior. On
consumer hardware it forces: one shared visual encoder where possible, persistent light detectors, cached
embeddings, ROI processing, event-driven inference, dynamic frame sampling, quantized specialists, model
load/evict, async CPU/GPU work, and teacher-to-student distillation.

---

## Status & build order
0-18 + 00.1 are **built**. The **near-term build order is re-prioritized** (D-0029) to deliver a locally
usable core — cost-offload (the Local Logic Escalator + a local orchestrator) plus a human interface (the
Widget layer) — **before** the deep-research spine (27-49). See `MODULE_ROADMAP.md → Build priority`.
**This map is the destination; the roadmap is the route.**
