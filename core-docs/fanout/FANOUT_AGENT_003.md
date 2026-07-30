# FANOUT_AGENT_003 -- Coding lane: TRACK-objects (NEW module modules/33-track-objects, Phase C video #20)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i17 (plan id `fo-17-3a115347`)
- **Lane:** CODING (CPU; a DISTINCT module from slot 002)
- **Worker id / label:** `TRACK-objects` -- NEW module `modules/33-track-objects` (track.objects, Phase C video position 20)
- **Module/area (exclusive):** `modules/33-track-objects` (NEW folder) ONLY
- **GPU:** false
- **Docs:** `[]`

## Mission

Build the SECOND Phase C video-spine module (ARCHITECTURE_MAP position 20 = `track.objects` = "identity across
frames"), following `media.decompose` #32 (position 19, shipped i16). Given per-frame object detections (the
detect.objects #16 output shape), associate them into stable identity tracks so an object keeps ONE track_id
across frames. CPU-only, DETERMINISTIC (no model/CUDA/port/randomness), `parallel_safe:true`. MVP runs on
detection FIXTURES so it is fully DECOUPLED from the CPU lane's #16 edits.

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/6dd619e0-8a9c-4cf8-a110-642f18ab7f0d/workers/worker-TRACK-objects.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (create ONLY `modules/33-track-objects/` + its tests/fixtures):**
- `skill.json` (id `track.objects`; `parallel_safe:true`) + `Invoke-TrackObjects.ps1`
  (`lifeorch.skill.result/0.1` envelope) + `README.md` + dual-mode tests + deterministic fixtures.
- INPUT (MVP, decoupled): a sequence of per-frame detections in the #16 output shape (`{class, box, score}`
  matching #16's EXACT schema) + frame index/timestamp, from a JSON file/param. Do NOT call #16/#32 live this
  wave (live composition is a NAMED follow-on).
- ALGORITHM (deterministic, pure): frame-by-frame greedy IoU association PER-CLASS (configurable
  `-IouThreshold`, default ~0.3), deterministic assignment (descending IoU, stable tie-break by detection
  order); matched -> extend; unmatched detection -> BIRTH (monotonic track_id); unmatched track -> COAST up
  to `-MaxAge` then DEATH. NO Kalman/torch/re-ID for MVP. Same input -> byte-identical tracks.
- OUTPUT: tracks JSON `[{track_id, class, frames:[{frame,box,score}], first_frame, last_frame, length}]`
  + summary; ordered by track_id; JSON-serializable.
- REUSE: SKILL_CONTRACT envelope; pwsh 7.4.6 array gotchas (List[object] + `.ToArray()`); match #16's EXACT
  detection schema so they compose later WITHOUT a shim.

**SCOPE OUT (name as follow-ons):** a live-composition mode (#32 keyframes -> #16 -> track.objects);
Kalman/constant-velocity motion; appearance/embedding re-ID; the `video.timeline` #21 fuse that CONSUMES
tracks; an overlay video; batch/directory. Do NOT touch modules/23/15/16/ops-setup/07, core-infra, or any
core-doc. Not a review-queue producer.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (pwsh 7.4.6 array gotchas +
  JSON-serializable-meta) + `core-docs/SKILL_CONTRACT.md` + `core-docs/MODULE_ROADMAP.md` (Phase C 19-22 + the
  #32 entry) + `modules/16-detect-objects` (its EXACT detection schema you consume) +
  `modules/32-media-decompose` (the i16 NEW-module reference: folder structure, dual-mode tests, on-the-fly
  deterministic fixtures) + `modules/15-image-util` (the deterministic-primitive pattern); obey
  `SKILL_CONTRACT.md`.
- Lease: **git** only. BRAND-NEW module -> no `skill.json` yet; run with NO skill_id. Gate off-machine FIRST
  (cloud pwsh, REAL skill vs synthetic fixtures: crossing / occlusion-coast / birth / death). AST-parse
  `.ps1`. Then `exec-job.sh devship` (FAIL-CLOSED, named files only, trailers).
- Do ONE unit; `docs:[]` -- the MODULE_ROADMAP / CURRENT_STATE / ARCHITECTURE_MAP / TOOL_MODEL_REGISTRY
  updates are the ORCHESTRATOR's job; just REPORT what you built.
- Report: `-Action report -PlanId fo-17-3a115347 -WorkerId TRACK-objects -State done -Summary "<one line>"`.

## Verification

Cloud + on-device `-Live` counts; a tracks artifact for a fixture covering crossing / occlusion-coast / birth
/ death; confirm `parallel_safe:true` (no CUDA/port/model bind) + determinism (same input twice ->
byte-identical); a Verification Console `run_module` item (track a fixture -> tracks JSON). Continues the
Phase C video spine (position 20, after #32).

## Report-back record (ORCHESTRATOR fills at close-out from `plans/fo-17-3a115347/reports/`)

_(pending)_
