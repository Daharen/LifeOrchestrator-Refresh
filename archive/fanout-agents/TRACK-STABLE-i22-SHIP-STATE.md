# TRACK-STABLE-i22 (plan fo-22-d2c492e7) -- SHIP STATE

**Worker:** FANOUT_AGENT_002 / `TRACK-STABLE-i22` (CPU lane, exclusive area `modules/33-track-objects/`).
**State:** `done` (report filed to `plans/fo-22-d2c492e7/reports/TRACK-STABLE-i22.5bd124aa.json`, 7.0 KB).
**Outcome:** `track.objects` #33 **0.1.0 -> 0.2.0 SHIPPED**: the frontier-reviewed **STABLE-IDENTITY tracker
is the new default** (`-Mode stable`), the i17 greedy baseline **retained byte-identical** as `-Mode greedy`
(verified sha256-equal tracks.json vs the shipped `3264dd5` script), and the module now emits the **richer
canonical `lifeorch.track.objects/0.2` schema** the parallel `video.timeline` #34 worker consumes. The
governing contract (`core-docs/research/2026-07-30-track-objects-design-review.md`) "Recommended MVP scope"
Include list is implemented **in full**. **The acceptance bar was MET.**

## Shipped (committed; real HEAD verified via native git -- D-0072)

- **Commit `b60340c26722e0638e7969c1c0b1aca1229f1de4`** (`master`; parent = the parallel worker's
  video.timeline commit `e8583d1` -- zero file overlap): exactly the 12 named `modules/33-track-objects`
  files, +2839/-692, trailers `Co-Authored-By: Claude Fable 5` + `Claude-Session`. dev.ship fail-closed
  green (sha 12/12 byte-exact, AST 5/5, on-box re-gate 3 suites exit 0, git lease acquired 45 ms inside the
  commit window + released, 0 orphans, `committed:true` AND native-git confirmed).
- **The stable tracker (every review P0):** scene-boundary HARD separation (`scene_boundary` deaths; #32
  seconds-shape `scenes[]` accepted, per-frame `scene_index` override, absent -> warn + conservative
  `min(max_gap_ms, no_scene_max_gap_ms)` = 5000->2000); elapsed-TIME aging (`max_gap_ms` OR
  `max_missed_samples`, integer ms; timestamps REQUIRED; `frame_index` provenance only); exact-class;
  two tiers (quantized-integer IoU >= threshold; the TIGHTLY-GATED centroid fallback ONLY at integer
  IoU==0 -- elapsed + time-grown hard-capped displacement allowance (0.25 + 0.25/s cap 1.0, normalized by
  the larger-area box's squared diagonal) + cross-multiplied area-ratio gate (<= 4.0); IoU edges strictly
  outrank fallback: two cost bands, no blended sum); deterministic GLOBAL per-class-per-scene assignment
  (pinned integer-cost Hungarian in pure pwsh, NO SciPy; **the tie rule is contract** -- lexicographically
  smallest `(track_id, detection_rank)` list via residual re-solves, symmetric-matrix tested); fixed-point
  throughout (milli-px boxes, millionth scores, ms; BigInteger cross-multiplied compares; no
  sqrt/epsilon/NaN).
- **The richer schema:** file metadata + `identity_scope` + quantized `tracker_params` + `input_digest`;
  the ESSENTIAL `samples[]` manifest; track lifecycle + termination
  (`max_gap|max_missed_samples|scene_boundary|end_of_input`) + SEPARATED `score_summary` vs
  `association_summary`; per-link association records; first-class `gaps[]` (coast boxes NEVER
  fabricated); NO aggregate confidence (`quality_score` intentionally not emitted -- additive later);
  canonical JSON (ordinal-sorted keys, compact, integers only, one trailing LF) SPLIT from
  `diagnostics.json`; monotonic never-reused ids. **Every digest interpretation recorded in
  `modules/33-track-objects/SCHEMA_NOTES.md`** for the fold against video.timeline.

## Gate (0 regression)

**Cloud pwsh 7.4.6:** greedy regression suite exit 0 with its assertion set UNCHANGED (78 PASS lines,
line-for-line identical to the pristine 0.1.0 suite on the same box; the ledger's "79" was a
count-at-ship-time artifact -- no assertion added or removed; every tracking call pinned `-Mode greedy`)
+ NEW stable suite **76/76** + NEW labeled probe **15/15**. **On-box -Live (executor):** **169/169**
(78+76+15), exits 0. **Cross-environment:** canonical fixture sha256 **EQUAL cloud vs -Live on ALL 11
hashes** (e.g. `moderate_gap ffed64f2c751d730...`). `review_queue.jsonl` before == after
(`e82880321b2c...`, 20 lines -- non-producer). 0 orphan `llama-server`/`python`. No gpu/doc lease ever
held; git only inside dev.ship's window; `docs:[]` honored (no core-doc touched).

## The labeled probe (greedy vs stable; ACCEPTANCE BAR MET)

| fixture | mode | tracks | false_merges | id_switches | fragments/object | correct_links |
|---|---|---|---|---|---|---|
| static | greedy | 1 | 0 | 0 | 1.00 | 4/4 |
| static | stable | 1 | 0 | 0 | 1.00 | 4/4 |
| zero_iou_move | greedy | 5 | 0 | 0 | 5.00 | 0/0 |
| zero_iou_move | stable | 1 | 0 | 0 | 1.00 | 4/4 |
| crossing | greedy | 3 | **1** | 1 | 2.00 | 2/3 |
| crossing | stable | 2 | 0 | 0 | 1.00 | 4/4 |
| occlusion_miss | greedy | 1 | 0 | 0 | 1.00 | 3/3 |
| occlusion_miss | stable | 1 | 0 | 0 | 1.00 | 3/3 |
| camera_shift | greedy | 4 | 0 | 0 | 2.00 | 4/4 |
| camera_shift | stable | 4 | 0 | 0 | 2.00 | 4/4 |
| zoom_reframe | greedy | 3 | 0 | 0 | 1.00 | 3/3 |
| zoom_reframe | stable | 3 | 0 | 0 | 1.00 | 3/3 |
| scene_cut | greedy | 1 | **1** | 1 | 1.00 | 5/6 |
| scene_cut | stable | 2 | 0 | 0 | 1.00 | 5/5 |
| label_flip | greedy | 2 | 0 | 0 | 2.00 | 2/2 |
| label_flip | stable | 2 | 0 | 0 | 2.00 | 2/2 |
| long_gap | greedy | 1 | **1** | 1 | 1.00 | 2/3 |
| long_gap | stable | 2 | 0 | 0 | 1.00 | 2/2 |
| moderate_gap | greedy | 2 | 0 | 0 | 2.00 | 2/2 |
| moderate_gap | stable | 1 | 0 | 0 | 1.00 | 3/3 |

**Stable: ZERO false merges + ZERO id switches across the set.** Fragmentation exceeds greedy's ONLY where
the review names it the correct trade (camera pan refused by the hard cap; label flip under exact-class).
Stable **beats greedy on within-scene moderate-gap fragmentation** (`moderate_gap` 1 vs 2 tracks;
`zero_iou_move` 1 vs 5). Greedy's characteristic false merges are demonstrated by labels: crossing
order-dependence (global assignment resolves it), a merge straight across the hard scene cut, and a merge
across a 6.5 s absence its frame-count aging cannot see.

## Live-found build gotcha (candidate for Known failures)

**pwsh 7.4.6 `[System.Array]::Sort` with an `object[]` + a `Comparison[string]` sorts a CONVERTED COPY**
(generic-overload binding converts the array) **and silently leaves the original unsorted.** The canonical
serializer's key sort was a no-op and `class_summary` leaked per-process randomized hashtable order
(string-hash seed) -- caught precisely by the review-mandated double-run byte-identity gate (label_flip
hashed two ways across processes), fixed by casting to a real `[string[]]` before the in-place sort. The
determinism gates earned their keep; keep them.

## Verification Console

`examples/verification-packet.json` -> `vp-track-objects-i22-stable`: a `run_module` item exercising
`-Mode stable` on the committed canonical fixture `tests/fixtures/probe-moderate-gap.json` (expect 1
track, iou 2 + centroid 1 links, gap {missed 2, 1500 ms, reacquired_by centroid}, byte-identical rerun)
+ a human canonical-bytes/diagnostics-split inspection item.

## Follow-ons (named, NOT built) + the open question

Kalman/constant-velocity; learned re-ID; optical flow; camera-motion compensation; cross-class alias
families; interpolated coast boxes; cross-video/scene identity; ByteTrack low-score recovery (needs
coordinated detector output); a versioned `quality_score/N`; live #32->#16->#33 composition; a faster
uniqueness-aware tie-rule refinement if profiling demands. **Open question restated (the review's
deepest):** sparse semantic keyframes may lack recoverable continuity for identity AT ALL; the likely
eventual architecture is a **dense low-res tracking-sample stream** from media.decompose for identity +
sparse keyframes for semantics -- `video.timeline` #21's input contract should not be frozen before that
call is made.

## Orchestrator to mirror/fold (docs:[] honored -- worker touched ONLY modules/33 + runtime scratch)

`CURRENT_STATE.md` tests row #33 -> "greedy 78 (assertion set unchanged, -Mode greedy pinned) + stable 76
+ probe 15 cloud; 169/169 -Live; commit `b60340c`" + Known-failures adds the Array.Sort copy-not-in-place
gotcha; skill 0.2.0 everywhere; `MODULE_ROADMAP.md` #33 refinement wave DONE + follow-ons; the
`track.objects`-is-a-baseline Unresolved-questions entry can now point at 0.2.0 (the open dense-stream
question REMAINS); `TOOL_MODEL_REGISTRY.md` #33 row. SCHEMA_NOTES.md is the reconciliation source vs the
video.timeline worker's schema reading.
