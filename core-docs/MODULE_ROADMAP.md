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

## Module 1 — Skill Contract & Registry Bootstrap
- **id:** `skill.bootstrap` · **Priority:** P0 · **Status:** **MVP complete**
- **Purpose:** Establish the smallest common interface for invokable skills: finalize `SKILL_CONTRACT.md`,
  the `skill.json` manifest format, the standard result envelope, standard artifact location, the
  registry entry format, and a **simple invocation wrapper** (validate manifest → run → validate envelope).
  Must **not** become a plugin framework.
- **Dependencies:** Module 0; `SKILL_CONTRACT.md` (v0.1 already drafted in this pack).
- **MVP acceptance:** one trivial reference skill validates against the contract and runs both directly
  and through the executor, emitting a schema-valid envelope; registry entry format proven by that skill.
- **Implementation:** `modules/01-skill-bootstrap/` — validators (`lib/SkillContract.psm1`), generic
  wrapper (`Invoke-Skill.ps1`), reference skill (`skills/ref.echo/`).
- **MVP acceptance:** **Met — `ref.echo` validates and runs directly + through the executor, emitting a
  schema-valid `lifeorch.skill.result/0.1`; the wrapper validates manifest+envelope; module tests 11/11
  (2026-07-24).** Contract-finalization of the adopted conventions deferred (DECISION_LOG D-0009).
- **Work order:** `modules/01-skill-bootstrap/WORK_ORDER.md`. **Blockers:** none.

## Module 2 — Filesystem Observer
- **id:** `fs.observer` · **Priority:** P1 · **Status:** **MVP complete**
- **Purpose:** Inspect, search, compare, and index the filesystem without screenshots — listings,
  discovery, change detection, metadata, markdown trees, project/artifact indexing.
- **Dependencies:** Module 1. **MVP acceptance:** deterministic tree + search over a target dir,
  contract-valid envelope, markdown + JSON artifacts. **Met — manifest valid; `tree.md` + `index.json`
  with hashes; glob search; error path; direct/wrapped/executor; tests 16/16 (2026-07-24).**
- **Implementation:** `modules/02-fs-observer/` (`Invoke-FsObserver.ps1`, `skill.json`, tests). **Work
  order:** `modules/02-fs-observer/WORK_ORDER.md`.

## Modules 3–6 — Desktop observation & control (provisional)  ← Module 4 (`uia.inspector`) next
- **3 `proc.observer`** — Process & Window Observer: running apps, windows, active window, positions,
  titles, state changes (no image processing). ***MVP complete*** — processes + top-level windows +
  foreground; `report.md`/`processes.json`/`windows.json`; tests 16/16 (2026-07-24). Work order:
  `modules/03-proc-observer/WORK_ORDER.md`.
- **4 `uia.inspector`** — UI Automation Inspector: read accessible controls, return stable element info.
  *Proposed, P1.*
- **5 `uia.actor`** — UI Automation Actor: invoke/select/expand/type on identified elements. Kept
  **separate** from inspection. *Proposed, P2. Depends on 4.*
- **6 `capture.screen`** — Screenshot & Region Capture: monitor/window/app/rectangle → artifact, for
  when structured inspection is unavailable or visual verification is genuinely required. *Proposed, P2.*

## Modules 7–9 — Local model foundation (provisional)
- **7 `model.gateway`** — Local Model Gateway: common interface to installed local LLM/vision/speech/
  embedding models; may wrap existing servers/CLIs; records model id/version/params/io/runtime/resources/
  failure. *Proposed, P1.*
- **8 `classify.batch`** — Batch Classification & Sorting: weak-local-model categorization/labeling/
  extraction/routing; early proof that local models do useful unattended work. *Proposed, P2. Depends on 7.*
- **9 `review.processor`** — Review Queue Processor: stronger local model adjudicates only flagged/
  low-confidence/contradictory items from the queue. *Proposed, P2. Depends on 7, 8, `REVIEW_QUEUE`.*

## Modules 10–13 — Audio (provisional, unlocked)
- **10 `audio.ingest`** normalize/convert · **11 `speech.stt`** transcription (timestamped) ·
  **12 `speech.tts`** local TTS · **13 `voice.live`** compose record+VAD+STT+TTS (after 10–12 work).

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
