# FANOUT_AGENT_002 -- CPU lane: track.objects #33 STABLE-IDENTITY refinement (i22)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** DISPATCHED -> done -> ARCHIVED (i22 close-out, D-0077)
- **Wave / iteration:** i22 (plan `fo-22-d2c492e7`)
- **Lane:** CPU
- **Worker id / label:** `TRACK-STABLE-i22`
- **Module/area (exclusive):** `modules/33-track-objects/` -- nothing else, anywhere
- **GPU:** false
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors)

## Mission

Upgrade `track.objects` #33 from the shipped greedy-IoU BASELINE (i17, `3264dd5`, 0.1.0) to the
frontier-reviewed STABLE-IDENTITY tracker, and emit the richer track schema that `video.timeline`
(arch position 21, being built in PARALLEL this wave as `modules/34-video-timeline`) consumes.
Governing contract: `core-docs/research/2026-07-30-track-objects-design-review.md` -- implement its
"Recommended MVP scope" Include list in full. Skill 0.1.0 -> 0.2.0.

## Unit (the full worker prompt)

**READ AND EXECUTE THE FULL EMITTED PROMPT** (it is the complete unit; disk is canonical):
`modules/30-orchestrate-fanout/runtime/artifacts/fc5b10db-bacf-43d4-b226-d052eb09717b/workers/worker-TRACK-STABLE-i22.prompt.md`

Condensed scope (the prompt is authoritative; on any doubt the prompt + the governing review digest win):

- **Modes:** the new deterministic geometric association tracker = `-Mode stable`, the DEFAULT; the shipped
  greedy tracker RETAINED byte-identical as `-Mode greedy` (baseline/regression oracle). Existing tests stay
  green (pin `-Mode greedy` where behavior legitimately differs).
- **Stable tracker P0s:** scene-boundary HARD separation (`death_reason=scene_boundary`; scenes absent ->
  warn + documented conservative max gap); elapsed-TIME aging (`max_gap_ms` OR `max_missed_samples`,
  integer ms, `frame_index` = provenance only); exact-class matching; two explicit association tiers (IoU on
  quantized integer boxes, then the TIGHTLY-GATED normalized-centroid fallback -- class+scene match, elapsed
  bound, squared-integer normalized displacement with a hard-capped time-growing allowance, cross-multiplied
  area-ratio gate; IoU edges STRICTLY outrank fallback; NO blended float sum); deterministic GLOBAL
  per-class-per-scene assignment via a small pinned integer-cost Hungarian IN pure pwsh (NO SciPy; tie rule =
  lexicographically smallest ordered `(track_id, detection_rank)` list, tested on symmetric matrices);
  canonical detection ordering `(class_id, qx, qy, qw, qh, -qscore, original_index)`; fixed-point throughout
  (milli-pixel boxes, score millionths, ms timestamps; no sqrt/float-epsilon/NaN).
- **Richer schema (the video.timeline contract):** file-level metadata + `identity_scope` + `tracker_params`
  + `input_digest`; the ESSENTIAL sample manifest `samples[] {sample_index, frame_index, timestamp_ms,
  scene_index, detection_count}`; track-level lifecycle + termination reasons + SEPARATED detection evidence
  vs association evidence; observations with per-link association records; gaps as first-class records
  (NEVER fabricate coast boxes); NO aggregate "confidence" (a single ranking value = `quality_score`,
  versioned); canonical JSON (sorted keys, fixed order, no NaN, integers) SPLIT from a diagnostics envelope
  (no abs paths/UUIDs/wall-clock in canonical bytes); monotonic never-reused ids.
- **Labeled probe:** hand-authored identity-labeled fixtures (static / zero-IoU move / same-class crossing /
  occlusion-miss / camera shift / zoom / hard scene cut / label flip / long gap); `-Mode greedy` vs `-Mode
  stable`; report false_merges / id_switches / fragments_per_object / correct_links per fixture.
  **Acceptance bar: stable = ZERO false merges; fragmentation may exceed greedy's ONLY where the review says
  that is the correct trade; stable beats greedy on within-scene moderate-gap fragmentation.**
- **Determinism gates:** assignment edge cases (equal costs, symmetric, duplicates, rectangular, multiple
  optima); double-run byte-identity; sha256 fixture hashes EQUAL cloud vs on-box `-Live`.
- **Scope OUT (name as follow-ons):** Kalman; re-ID; optical flow; camera-motion compensation; cross-class
  aliases; interpolated coast boxes; cross-video identity; ByteTrack recovery; aggregate confidence; live
  #32->#16->#33 composition; the dense tracking-stream contract (RESTATE the open question).

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` (Known failures IN FULL) first; obey
  `core-docs/SKILL_CONTRACT.md`.
- No gpu lease anywhere in this unit. Acquire `git` ONLY for the dev.ship commit window; release after.
  `docs:[]`.
- Gate off-machine FIRST (cloud pwsh 7.4.6: existing 79 stays green + the new suites), THEN on-box `-Live`
  via the executor (`exec-job.sh`; device_bash cannot run Windows pwsh), THEN `dev.ship` ONLY the named
  `modules/33-track-objects` files (sha256 + AST + tests FAIL-CLOSED; trailers; never `git add -A`).
- VERIFY the real HEAD via native `git log` / `git show --stat`, NOT dev.ship's `committed` field (D-0072).
- `review_queue.jsonl` before == after (non-producer). No models, no network, no new deps.
- Report: `-Action report -PlanId fo-22-d2c492e7 -WorkerId TRACK-STABLE-i22 -State done` (or
  blocked/failed with what+why). Negative results are first-class (D-0061): if the full design cannot land
  regression-free, ship the largest coherent subset behind `-Mode stable`, keep greedy the default, say so
  plainly.

## Verification

Cloud: existing suite green + new stable-mode/probe/determinism suites (report exact counts). On-box:
`-Live` counts + EQUAL canonical fixture hashes vs cloud. dev.ship commit verified via native git. The probe
comparison table (greedy vs stable per fixture). `SCHEMA_NOTES.md` records every digest interpretation.
A Verification Console `run_module` item exercising `-Mode stable` on a canonical fixture.

## Report-back record (filled by the orchestrator at i22 close-out, D-0077)

- **State:** done. **Commit `b60340c`** (verified native git; exactly the 12 named modules/33 files, +2839/-692;
  parent = the parallel #34 commit `e8583d1`, zero overlap). Skill 0.2.0; stable default; greedy byte-identical
  (sha-equal vs `3264dd5` output).
- **Gates:** cloud greedy 78 (assertion set unchanged, `-Mode greedy` pinned) + stable 76 + probe 15;
  `-Live` 169/169; 11 cross-env canonical hashes EQUAL; review_queue byte-identical; 0 orphans; git lease only
  inside dev.ship (45 ms).
- **Acceptance bar MET:** stable 0 false merges + 0 id switches across the 10-fixture labeled set; beats greedy
  on within-scene gaps (moderate_gap 1 vs 2 tracks; zero_iou_move 1 vs 5); greedy's crossing/scene-cut/long-gap
  false merges demonstrated by labels.
- **Live-found gotcha (folded to CURRENT_STATE Known failures):** `[System.Array]::Sort(object[],
  Comparison[string])` sorts a converted COPY -- silent no-op; caught by the double-run byte-identity gate.
- **Fold note:** the orchestrator cross-module smoke validated this emitter's bytes against #34 -- the two
  divergences found were CONSUMER-side (fixed as #34 0.1.1, `bad9e27`); this module needed NO change.
- **Follow-ons + the open dense-stream question:** folded into MODULE_ROADMAP #33 + CURRENT_STATE Unresolved
  questions (D-0077).
