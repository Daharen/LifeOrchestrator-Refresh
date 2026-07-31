# Module 33 -- Object Tracking (`track.objects`)

The **second module of the Phase C video spine** (architectural position 20, "identity across frames"),
following `media.decompose` #32 (position 19). Given per-frame object detections in the `detect.objects`
#16 output shape, it associates them into identity tracks so the same object keeps **one `track_id`**.
It emits a contract-valid `lifeorch.skill.result/0.1` envelope plus a `tracks.json` artifact and a human
summary. It is **deterministic** (a pure function of the input bytes; no model -> `confidence` is null)
and `parallel_safe:true` (**no CUDA, no model, no loopback port, no randomness**).

## 0.2.0: `-Mode stable` is the DEFAULT (the design-review refinement)

**Why the default flipped:** the folded frontier design review
(`core-docs/research/2026-07-30-track-objects-design-review.md`) found that greedy IoU alone is NOT the
right shipped design for the module's promise. `media.decompose` #32 supplies **sparse,
irregularly-timed, scene-oriented keyframes** -- not consecutive frames -- which breaks greedy-IoU's core
assumption (the same object still overlaps its previous box) and makes frame-count aging meaningless
(one "missed frame" may be 200 ms or 45 s). And for a searchable timeline, **over-births are
inconvenient but FALSE CONTINUITY is semantically corrupting**: when uncertain, END the track --
`video.timeline` can group fragments later; it cannot undo a false merge. The i17 greedy tracker is
therefore **retained byte-identical as `-Mode greedy`** (baseline / regression oracle / debug path), and
the default is the review's **deterministic geometric association tracker**:

1. **Scene-boundary HARD separation** -- never associate across a known cut. Scenes come from per-frame
   `scene_index` and/or a `scenes[]` list (the #32 seconds shape `{index,start,end,score}` accepted and
   rounded half-up to ms; also `-ScenesFile` pointing at a #32 `scenes.json`). A sample from a new scene
   terminates every other-scene track (`termination.reason = "scene_boundary"`). **Scene info absent**
   -> a warning (status `partial`) + a documented conservative effective gap:
   `min(max_gap_ms, no_scene_max_gap_ms)` (defaults 5000 -> 2000 ms).
2. **Elapsed-TIME aging** -- a track terminates on `max_gap_ms` (real elapsed integer ms since its last
   observation, checked when the next sample arrives; `reason = "max_gap"`) OR `max_missed_samples`
   (processed samples of its scene with no match; `reason = "max_missed_samples"`), whichever first.
   Stable-mode frames MUST carry `timestamp_ms` (or `timestamp_s`, rounded half-up); `frame_index` is
   provenance only. Frame counts are never synthesized from time.
3. **Exact-class matching** -- one immutable class (string) per track; a separate cost matrix per class;
   no cross-class association (related-label flicker fragments -- the review's accepted MVP trade).
4. **Two explicit association tiers.** Tier 1: IoU on quantized integer boxes
   (`iou_q >= iou_threshold_q`). Tier 2: a **tightly-gated normalized-centroid fallback ONLY when
   integer IoU == 0** -- admitted only if class + scene match, elapsed <= the effective max gap, the
   squared integer center displacement normalized by the larger-area box's squared diagonal fits within
   an allowance that grows with elapsed time (`0.25 + 0.25/s`) up to a HARD cap (`1.0`), and the
   cross-multiplied area-ratio sanity gate holds (`max(prevA/newA, newA/prevA) <= 4.0`). IoU edges
   STRICTLY outrank fallback edges (two cost bands, no blended float sum). A pair with
   `0 < IoU < threshold` qualifies for NEITHER tier: uncertainty ends tracks.
5. **Deterministic GLOBAL one-to-one assignment** per class per scene -- a small pinned integer-cost
   Hungarian implemented in pure PowerShell (no SciPy, no binary dep; detections cap at 100/frame so
   O(n^3) is negligible). **The tie rule is CONTRACT:** among equal-min-total-cost assignments, the
   lexicographically smallest ordered `(track_id, detection_rank)` list wins -- implemented by residual
   re-solves, not solver whim, and tested on symmetric matrices. Canonical detection ordering before
   association: `(class_id, qx, qy, qw, qh, -qscore, original_index)`; births in that order.
6. **Fixed-point throughout** -- boxes quantized immediately to integer milli-pixels, scores to integer
   millionths, timestamps to integer ms; integer intersection/union; squared integer distances;
   cross-multiplied ratio compares (BigInteger); **no sqrt, no float epsilon, no NaN**; non-negative
   round-half-up documented in `SCHEMA_NOTES.md`.

Same input -> **byte-identical canonical output** in both modes, on both environments (the cloud gate
and the Windows executor hash-compare `tracks.json`).

## The richer track schema (what `video.timeline` #21 consumes)

Stable mode writes `tracks.json` as **canonical JSON** (`lifeorch.track.objects/0.2`: UTF-8 no BOM,
ordinal-sorted keys, compact separators, integers only, fixed array order, one trailing LF) with:

- **file-level metadata**: `schema, tracker_version, algorithm, source_media_id?, source_media_sha256?,
  frame_width?, frame_height?, coordinate_space, box_format, box_unit, score_unit, timestamp_unit,
  identity_scope ("source_media+scene+tracker_invocation"), detector_provenance?, tracker_params
  (quantized canonical params), input_digest`;
- the **sample manifest** (ESSENTIAL): `samples[]` lists EVERY processed sample
  `{sample_index, frame_index, timestamp_ms, scene_index, detection_count}` -- so a consumer can
  distinguish "sampled, no detection" from "not sampled" from "tracker gap";
- **tracks**: lifecycle (`first/last_frame_index, start/end/duration_ms, observation_count,
  spanned_sample_count, gap_count`), explicit `termination
  {reason: max_gap|max_missed_samples|scene_boundary|end_of_input, last_observed_ms, terminated_at_ms,
  missed_samples_at_termination}`, and **separated evidence**: `score_summary` (detection evidence:
  `mean/min/max_detection_score_q, low_confidence_observation_count, scored_observation_count`) vs
  `association_summary` (association evidence: `iou_link_count, centroid_link_count,
  reacquisition_count, mean/weakest_link_quality_q, maximum_gap_ms`);
- **observations** with per-link association records
  `{kind: birth|iou|centroid, previous_frame_index, gap_ms, missed_samples, iou_q,
  normalized_center_distance_q, area_ratio_q}` (birth -> null metrics);
- **gaps as first-class records** `{after/before_sample_index, start/end/elapsed_ms, missed_samples,
  reacquired_by}` -- stable mode NEVER fabricates coast boxes;
- **NO aggregate "confidence"** anywhere (and no `quality_score` yet -- the evidence components are
  auditable; a versioned `quality_score/N` would be additive). Monotonic never-reused ids.

Volatile facts (invocation id, absolute paths, wall-clock, artifact dirs) live ONLY in
`diagnostics.json` + the envelope -- never in the canonical bytes. Every interpretation the review
digest left open is recorded in **`SCHEMA_NOTES.md`** (units, rounding, scene derivation,
tie-rule mechanics, gate readings, digest preimage).

## `-Mode greedy` (the retained 0.1.0 baseline)

The i17 frame-by-frame greedy IoU matcher, byte-identical: per-class candidate pairs `IoU >= threshold`
resolved greedily (IoU desc, detection order, track_id), constant-position COAST up to `-MaxAge` missed
frames then death, monotonic ids, the `lifeorch.track.objects/0.1` tracks.json. Timestamps optional.
Use it as the regression oracle and for A/B probes (`tests/Invoke-TrackObjectsProbe.ps1` runs both
modes over an identity-labeled fixture set and scores false merges / id switches / fragments /
correct links).

## Invocation

```powershell
# stable (default): scenes in the input doc, richer canonical output
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json

# stable knobs: widen the elapsed-time gap, allow 2 missed samples
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -MaxGapMs 8000 -MaxMissedSamples 2

# scenes from a media.decompose #32 scenes.json artifact
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -ScenesFile .\scenes.json

# the byte-identical 0.1.0 baseline
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -Mode greedy -MaxAge 3

# via -InputsJson (orchestrator path)
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{"input":"detections.json","scenes":[{"index":0,"start":0.0,"end":4.0}],"max_gap_ms":5000}'
```

Key stable params: `-MaxGapMs` (5000), `-MaxMissedSamples` (3), `-NoSceneMaxGapMs` (2000),
`-CentroidBaseAllowance`/`-CentroidAllowancePerSecond`/`-CentroidMaxAllowance` (0.25/0.25/1.0),
`-MaxAreaRatio` (4.0), `-LowConfidenceThreshold` (0.5), `-ScenesFile`, `-FrameWidth`/`-FrameHeight`
(clipping), `-SourceMediaId`/`-SourceMediaSha256`, InputsJson `detector_provenance`. Shared:
`-IouThreshold` (0.3), `-MinScore`, `-Classes`. Greedy-only: `-MaxAge` (2). See `skill.json`.

## Input shape (matches detect.objects #16 + media.decompose #32)

Detections are the #16 shape `{class, class_id, score, box{x,y,width,height}}`. Accepted top-level
shapes: a bare array of frames, `{frames:[...]}`, `{sequence:[...]}`, or a single `{detections:[...]}`
object. Each frame: `{frame|index|frame_index, timestamp_ms|timestamp_s|timestamp, scene_index?,
detections:[...]}` -- **stable mode requires the timestamp** (`missing_timestamp` otherwise). The input
doc top level may carry `scenes` (the #32 shape), `frame_width`/`frame_height`, `source_media_id`,
`source_media_sha256`, `detector_provenance`.

## Result / artifacts

Stable result: `{mode, canonical (the full canonical doc), canonical_path, canonical_sha256,
diagnostics_path}`; artifacts `tracks.json` (canonical bytes), `diagnostics.json`, `tracks.md`,
`result.json`, `stderr.txt`. Greedy result + artifacts: unchanged from 0.1.0. Errors (always a valid
envelope, exit 0): the 0.1.0 set plus `invalid_mode`, `missing_timestamp`, `invalid_scene`,
`scenes_file_not_found`, `scenes_parse_failed`, `invalid_max_gap_ms`, `invalid_max_missed_samples`,
`invalid_no_scene_max_gap_ms`, `invalid_centroid_allowance`, `invalid_area_ratio`,
`invalid_low_confidence_threshold`, `invalid_frame_dims`.

## Scope

**In (0.2.0):** the stable deterministic geometric association tracker (scene-bounded,
elapsed-time-aged, globally-assigned, gated centroid fallback, fixed-point + canonical JSON, the richer
schema) as the default, over provided/fixture detections; the greedy baseline retained byte-identical.

**Out (named follow-ons, NOT built here):** Kalman / constant-velocity prediction; learned
re-ID/embeddings; optical flow; **camera-motion compensation** (the pan fixture documents the
conservative refusal); cross-class alias families; interpolated coast boxes; global identity across
scenes/videos; ByteTrack low-score recovery (needs coordinated detector output); any probabilistic
aggregate track confidence; live `#32 -> #16 -> #33` composition; the searchable `video.timeline` #21
fuse (being built against this schema); an overlay/annotated video; batch/directory input. **Open
question restated (the review's deepest):** sparse semantic keyframes may not carry enough continuity
for identity at all -- the likely eventual architecture is a dense low-res tracking-sample stream from
`media.decompose` for identity + sparse keyframes for semantics; `video.timeline`'s input contract
should stay open to that.

This module is **not** a review-queue producer.

## Tests

Three dual-mode + OS-portable suites (same assertions in the cloud pre-ship gate and on the Windows
executor via `-Live`):

- `tests/Invoke-TrackObjectsTests.ps1` -- the 0.1.0 regression suite, every tracking invocation now
  pinned `-Mode greedy` (assertion set unchanged; the greedy baseline must stay byte-identical).
- `tests/Invoke-TrackObjectsStableTests.ps1` -- the stable suite: the canonical schema + byte rules,
  scene derivation/override/absent handling, elapsed-time + missed-sample aging, tier gates (dead zone,
  allowance growth, area-ratio rejection), the Hungarian tie-rule contract (symmetric / duplicate /
  rectangular / multiple-optima layouts), double-run byte identity over all fixtures, passthrough
  metadata + clipping, every new error path, the Module 1 wrapper; prints `CANONHASH` lines for the
  cross-environment sha256-equality gate.
- `tests/Invoke-TrackObjectsProbe.ps1` -- the identity-LABELED probe (fixtures from
  `New-ProbeFixture.ps1`): greedy vs stable per fixture on false_merges / id_switches /
  fragments_per_object / correct_links, with the review's acceptance bar asserted (stable = ZERO false
  merges; fragmentation only where that is the documented correct trade; stable beats greedy on
  within-scene moderate-gap fragmentation).

Committed canonical fixture: `tests/fixtures/probe-moderate-gap.json` (the Verification Console
`run_module` item); `tests/fixtures/scenario.json` remains the greedy fixture.
