# Frontier design review -- `track.objects` (#20) tracker design + track schema for `video.timeline` (#21)

**Provenance:** couriered frontier answer, iteration 17, frontier.bridge pack `794dbdfe-dba4-402d-b11a-43e2f3951715`
(design-review prompt; GPT-5.x via ChatGPT, couriered back by Nicholas 2026-07-30; `read-return` valid,
`pack_id_match`=true, 23,089 chars). This is a faithful DIGEST (every actionable recommendation preserved). It
reviews the MVP shipped as `modules/33-track-objects` (i17, D-0070) and defines the refinement roadmap for the
real "stable-identity" tracker + the `video.timeline` #21 fuse it feeds.

## Executive verdict

**Deterministic per-class IoU tracking is appropriate as a BASELINE and regression fixture, but greedy IoU alone
is NOT the right shipped design if the module promises stable identity over SPARSE, IRREGULAR keyframes.** #32
`media.decompose` supplies scene-oriented, irregularly-timed keyframes -- not consecutive frames -- which directly
violates the assumption that the same object still overlaps its previous box. The shipped i17 MVP (greedy per-class
IoU, birth/coast/death, monotonic ids) should be kept as a baseline / regression oracle / debugging mode; the real
tracker should be described as a **deterministic geometric association tracker**, not "SORT without Kalman" (SORT's
two protections -- motion prediction AND global assignment -- were both removed).

**For a searchable timeline: over-births are inconvenient; FALSE CONTINUITY is semantically corrupting.** When
uncertain, end the track and create a new one -- `video.timeline` can group fragments later, but cannot undo a
false merge.

## Minimum credible shipped design (the target beyond the MVP baseline)

1. **Hard separation at scene boundaries** (P0) -- never associate across a known scene cut; `media.decompose`
   already emits scenes, so this is cheap + high-value. On a cut, terminate active tracks
   (`death_reason=scene_boundary`). If scene info is absent, warn + use a more conservative max gap.
2. **Elapsed-TIME aging** (P0), not frame-count -- terminate on `max_gap_ms` (real elapsed since last observation)
   OR `max_missed_samples` (sampled frames with no match), whichever first. Keep time in integer ms/us; do NOT
   synthesize frame counts. `frame_index` stays as provenance only.
3. **Exact-class matching** -- one immutable class per track; separate cost matrix per class; no cross-class
   association (car/truck, couch/chair flicker fragments -- acceptable for MVP; alias families are a versioned
   follow-on).
4. **IoU as the preferred association signal.**
5. **Tightly-gated normalized-centroid FALLBACK** (P0) when IoU==0 from displacement -- candidate allowed only if:
   class matches, scene matches, elapsed <= `max_gap_ms`, centers close after normalization, box-scale change
   within `max_area_ratio` (`max(prevA/newA, newA/prevA) <= bound`), other geometric sanity holds. Normalize
   squared center displacement by a box-scale term (larger area or squared diagonal); compare squared values (no
   sqrt); grow the allowance with elapsed time up to a HARD cap. IoU-qualified edges outrank fallback edges -- do
   NOT silently blend IoU and distance into an undocumented float weighted sum. Two explicit tiers.
6. **Deterministic GLOBAL one-to-one assignment** (P0), not greedy -- minimum-cost bipartite (Hungarian) per class
   per scene. Detections are capped at 100 and split by class, so O(n^3) is negligible here. Avoid adding SciPy
   just for this (a small pinned integer-cost Hungarian is preferable to a new binary dep); the contract MUST
   define the tie rule: *among equal-min-total-cost assignments, pick the lexicographically smallest ordered list
   of `(track_id, detection_rank)` pairs* (test with symmetric matrices -- a solver's arbitrary equal-cost choice
   is NOT a determinism spec).
7. **Explicitly recorded gaps + association evidence** (do NOT invent coast bounding boxes -- a coast is tracker
   state, not an observed location).
8. **Fixed-point calculations + canonical serialization.**

## Failure modes of the greedy-IoU baseline under sparse keyframes

- **Track fragmentation from zero overlap (SEVERE, likely dominant):** a modest real move during a long gap yields
  a non-overlapping box -> IoU 0 -> old track dies, new track born -> one object becomes several short tracks ->
  timeline reports several appearances instead of one presence.
- **Irregular-time aging (SEVERE):** frame-count `MaxAge` is meaningless when one "missed frame" may be 200 ms or
  45 s.
- **Camera motion (SEVERE in handheld/edited):** pan/zoom/crop/stabilize shifts every box; IoU collapses; a
  permissive centroid fallback then risks linking to whichever same-class object now occupies that region.
- **Same-class crossings (MODERATE-SEVERE):** greedy consumes the locally-best detection for the wrong track ->
  ID swaps/splits; global assignment prevents the avoidable order-dependent errors (not the genuine ambiguity).
- **Detector jitter / scale variation (MODERATE):** a fixed IoU ~0.3 is too strict in some cases, too loose in
  crowds.
- **Missed / low-score detections (MODERATE):** #16 applies a default detection floor (~0.25); ByteTrack-style
  low-score recovery needs those boxes and is a follow-on requiring coordinated detector output, NOT a hidden
  MVP feature.
- **Class-label flicker (MODERATE):** strict per-class matching prevents catastrophic merges but fragments on
  related-label flips -- acceptable for MVP.
- **Scene cuts (CATASTROPHIC unless blocked):** must never associate across a cut.

## Track schema for `video.timeline` #21 (the proposed MVP schema is under-specified)

- **File-level:** `schema, tracker_version, algorithm, source_media_id, source_media_sha256, frame_width,
  frame_height, coordinate_space, box_format, timestamp_unit, identity_scope, detector_provenance,
  tracker_params, input_digest, samples, tracks, summary`. `identity_scope = source_media + scene + tracker
  invocation` -- a `track_id` is NOT a persistent real-world identity across videos/runs.
- **Sample manifest (ESSENTIAL):** a root-level list of EVERY processed sample `{sample_index, frame_index,
  timestamp_ms, scene_index, detection_count}` -- without it `video.timeline` cannot distinguish "sampled, no
  detection" from "not sampled" from "detector miss" from "tracker gap".
- **Track-level:** `track_id, scene_index, class_id, class, first_frame_index, last_frame_index, start_ms, end_ms,
  duration_ms, observation_count, spanned_sample_count, gap_count, termination, score_summary,
  association_summary, observations, gaps`.
- **Observation:** `sample_index, frame_index, timestamp_ms, detection_index, box, detection_score,
  low_confidence, association{kind: birth|iou|centroid, previous_frame_index, gap_ms, missed_samples, iou_q,
  normalized_center_distance_q, area_ratio_q}` (birth -> previous-link metrics null).
- **Box semantics:** original-source pixel `x,y,width,height`; half-open `[x,x+width)`/`[y,y+height)`; clipped to
  source dims; quantization precision stated. Store pixels only (timeline derives normalized).
- **Gaps (do NOT fabricate boxes):** `{after_sample_index, before_sample_index, start_ms, end_ms, elapsed_ms,
  missed_samples, reacquired_by: iou|centroid}`.
- **Termination:** `{reason: max_gap|max_missed_samples|scene_boundary|end_of_input, last_observed_ms,
  terminated_at_ms, missed_samples_at_termination}`.
- **Confidence: do NOT present a single aggregate as a calibrated "track confidence."** #16's score is YOLOX
  objectness x class prob (a ranking signal, not calibrated). Separate **detection evidence**
  (`mean/min/max_detection_score_q, low_confidence_observation_count`) from **association evidence**
  (`iou_link_count, centroid_link_count, reacquisition_count, mean/weakest_link_quality_q, maximum_gap_ms`). If a
  single ranking value is required, call it `quality_score` (versioned formula), never `confidence`; keep
  components auditable.
- **Replace the ambiguous `length`** with `observation_count` + `spanned_sample_count` + `duration_ms`. Real
  timestamps are mandatory (frame indices insufficient).

## Determinism / byte-identical output

- Guarantee correctly: *identical canonical input bytes + tracker version + params -> identical canonical output
  bytes* (cannot guarantee equality if upstream detector bytes differ).
- **Quantize immediately** -- boxes to fixed-point integer units (e.g. milli-pixels), scores to integer millionths,
  timestamps to integer ms/us. Integer intersection/union; IoU ordering via integer ratios; center gates via
  squared integer distance; area gates via cross-multiplication. AVOID: epsilon float compares, sqrt, NaN/Inf,
  unspecified midpoint rounding, raw floats in assignment. Specify rounding (e.g. non-negative round-half-up).
- **Canonical detection ordering** before association: `(class_id, qx, qy, qw, qh, -qscore, original_index)`; birth
  in that order.
- **Canonical track ordering:** globally monotonic ids, never reused; tracks by `track_id`; observations by
  `(timestamp_ms, frame_index, sample_index)`; gaps chronological; map keys sorted.
- **Canonical JSON (RFC 8785-style):** UTF-8, no BOM, fixed newline, no trailing whitespace, sorted keys, fixed
  array order, compact separators, `allow_nan=false`, integers where practical (Python json defaults permit
  NaN/Inf + do NOT sort keys -- must disable/enable explicitly).
- **Separate canonical results from diagnostics** -- keep absolute paths, invocation UUIDs, wall-clock times,
  hostnames, durations, PIDs, artifact-dir paths, env-specific exe paths OUT of the byte-reproducible track file;
  put them in a diagnostics/invocation envelope. Include in the canonical result: algorithm version, canonical
  params, source-media hash, canonical-input hash, detector model id + label-map hash.
- Tests: equal IoU, symmetric layouts, identical boxes, duplicate scores, rectangular matrices, multiple equal
  optima; run canonical fixtures on both intended environments and compare SHA-256.

## Highest-risk assumption + first probe

**Highest risk: that sparse keyframes contain enough temporal/spatial continuity for identity to be recoverable
AT ALL.** Threshold tuning cannot repair missing information; a fancier assignment only makes ambiguity look
authoritative. **First probe:** build a small IDENTITY-LABELED fixture set from ACTUAL `media.decompose` output
(not only evenly-spaced synthetic frames) covering static/moving object, same-class crossing, occlusion/miss,
handheld motion, zoom/reframe, a hard scene cut, a related-class label change, a long within-scene gap. Compare
(1) greedy IoU, (2) optimal IoU, (3) +elapsed-time gating, (4) +centroid fallback, (5) +scene resets; measure
false merges / ID switches / fragments-per-object / singleton rate / correct links, grouped by gap duration +
camera condition. **Prioritize FALSE MERGES over fragmentation in acceptance criteria.**

**Decision gate:** if the hybrid tracker stays badly fragmented at the real keyframe cadence, do NOT keep loosening
centroid thresholds -- change the INPUT CONTRACT: ask `media.decompose` for a denser tracking-sample stream (or
track over low-res intermediate frames), keep sparse keyframes for semantic interpretation. The likely eventual
architecture: **sparse keyframes = semantic understanding; denser lightweight frames = temporal identity
continuity**, with `video.timeline` referencing dense observations while storing only selected representative
images.

## Recommended MVP scope (for the refinement wave)

**Include:** fixture JSON input + strict validation; scene-aware partitioning; exact-class association; real-time
+ missed-sample aging; IoU gate; gated normalized-centroid fallback; area-ratio sanity gate; deterministic global
assignment; monotonic ids; observation + gap evidence; explicit termination reasons; fixed-point decision
arithmetic; canonical output file; separate diagnostics file; cross-machine hash fixtures.

**Exclude (named follow-ons):** Kalman; learned re-ID; torch/CUDA; optical flow; camera-motion compensation;
cross-class association; interpolated coast boxes; global identity across scenes/videos; ByteTrack low-score
recovery (until detector integration exposes the boxes); a probabilistic aggregate "track confidence"; live
`#32 -> #16 -> #20` composition (until the fixture contract is stable).

## Orchestrator's read (folded)

The i17 shipped MVP (`modules/33-track-objects`, greedy per-class IoU, `3264dd5`) is a VALID baseline + regression
oracle -- keep it as a `-Mode greedy` debug path. This review defines the **refinement roadmap**, which splits
into two tracks: (A) the `track.objects` upgrade (scene-aware partitioning, elapsed-time aging, centroid fallback,
global assignment, fixed-point + canonical JSON, richer schema) -- a CPU coding-lane wave; (B) the `video.timeline`
#21 design -- it should CONSUME this exact schema (sample manifest + gaps + separated detection/association
evidence). The single highest-value cheap win is **scene-boundary hard separation** (media.decompose already emits
scenes). The deepest finding -- sparse keyframes may lack recoverable continuity -- argues that `video.timeline` /
the video block may eventually need a dense low-res tracking stream distinct from the sparse semantic keyframes; capture
that before committing #21's input contract.
