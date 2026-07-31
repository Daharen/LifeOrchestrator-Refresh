# SCHEMA_NOTES -- track.objects 0.2.0 stable-mode canonical schema (`lifeorch.track.objects/0.2`)

Records **every place the governing review digest
(`core-docs/research/2026-07-30-track-objects-design-review.md`) under-specified a detail and the
minimal interpretation this implementation chose** (fan-out i22, worker TRACK-STABLE-i22). The parallel
`video.timeline` worker (modules/34) builds against the SAME digest; the orchestrator reconciles both
sides at fold using this file. Field NAMES follow the digest verbatim wherever the digest names one.

## 1. Units and quantization (digest: "fixed-point calculations", "quantization precision stated")

- **Boxes**: integer **milli-pixels** (`box_unit: "milli_pixel"`, scale 1000). `box = {x,y,width,height}`
  in original-source pixel space, half-open `[x, x+width) x [y, y+height)`, clipped to
  `frame_width/frame_height` when those are known (see 6). The digest says "store pixels"; storing
  fixed-point milli-pixel INTEGERS with the unit declared file-level is the all-integer reading
  (divide by 1000 for pixels).
- **Scores**: integer **millionths** (`score_unit: "millionths"`). The observation field keeps the
  digest's name `detection_score` but holds the quantized integer (null when the input had no score);
  the track-level summary names (`mean/min/max_detection_score_q`) are the digest's own `_q` names.
- **Time**: integer **ms** (`timestamp_unit: "ms"`). Input frames must carry `timestamp_ms` (numeric,
  rounded half-up to integer ms) or `timestamp_s`/`timestamp` (SECONDS, x1000 then rounded half-up).
  A stable-mode frame with NO timestamp is an ERROR (`missing_timestamp`) -- the digest: "Real
  timestamps are mandatory". (`-Mode greedy` keeps 0.1.0's optional timestamps.)
- **Rounding**: `round_half_up_toward_positive_infinity` = `floor(v * scale + 0.5)`, applied uniformly
  (also to any negative value: halves round toward +infinity). Quantized ratio values (`iou_q`,
  `normalized_center_distance_q`, `area_ratio_q`, score/link means) use the integer form
  `floor((2n + d) / (2d))` of round-half-up division. The centroid allowance's time growth uses FLOOR
  division (`base_q + floor(growth_q * gap_ms / 1000)`, capped) -- growth, not a measurement, so floor.
- All decision arithmetic is integer (BigInteger for cross-multiplied compares); no sqrt, no float
  epsilon, no NaN/Inf anywhere. The canonical serializer THROWS on any non-integer numeric.

## 2. Canonical JSON (digest: "RFC 8785-style")

UTF-8, no BOM; object keys sorted by ORDINAL comparison at every level; compact separators
(`,` / `:`, no whitespace); minimal escaping (`\"`, `\\`, control chars as `\u00XX`; other characters
raw UTF-8); integers only; arrays in fixed documented order (samples by `sample_index`; tracks by
`track_id`; observations by `(timestamp_ms, frame_index, sample_index)` = build order; gaps
chronological); **exactly one trailing LF**. The full fixed key set is always present (absent optional
values are `null`, never omitted keys). `sha256(tracks.json)` is the cross-environment reproducibility
hash.

## 3. Canonical vs diagnostics split (digest: "separate canonical results from diagnostics")

`tracks.json` = the canonical file: NO absolute paths, invocation ids, wall-clock times, durations,
hostnames, or PIDs. Volatile facts live in `diagnostics.json`
(`lifeorch.track.objects.diagnostics/0.1`: invocation_id, absolute input path, scenes source, artifact
dir, started_at, canonical sha) and in the result envelope. `input_digest`, algorithm + params, and the
optional source-media / detector provenance ARE in the canonical file per the digest.

## 4. `input_digest` (digest names the field but not its preimage)

`sha256:` over the CANONICAL serialization (section 2 rules, no trailing LF) of the normalized,
quantized, FILTERED input actually consumed: the array of samples
`{detections, frame_index, sample_index, scene_index, timestamp_ms}` with each detection
`{box{height,width,x,y} (milli-px, clipped), class, class_id, detection_index, detection_score (q)}`,
in canonical detection order. Scene derivation is baked in as `scene_index`; class/min-score filtering
has been applied. Params are NOT part of the digest preimage (they are recorded separately in
`tracker_params`); the guarantee is: identical `input_digest` + `tracker_version` + `tracker_params`
=> byte-identical canonical output.

## 5. Scenes (digest: accept what #32 emits; under-specified derivation)

- Sources, in precedence order: `-ScenesFile` > `-InputsJson.scenes` > input doc top-level `scenes`.
  Accepted shapes: a bare array of entries or `{scenes:[...]}` (covers the #32 `scenes.json` artifact
  and its result subobject). Entry keys: `start`/`end` are SECONDS (the #32 shape, rounded half-up to
  ms); `start_ms`/`end_ms` are ms. Only `index` + start are used; `end`/`score` are accepted and
  ignored for derivation.
- **Derived scene_index** = the `index` of the LAST entry (sorted by `(start_ms, index, position)`)
  whose `start_ms <= timestamp_ms`; a sample EARLIER than every entry gets `(first index - 1)` -- the
  implicit scene before the first detected cut (can be -1; only EQUALITY of scene_index matters to
  association). Entries missing `index` default to their array position.
- A per-frame explicit `scene_index` (integral) ALWAYS wins over derivation for that frame.
- Explicit `scene_index` on SOME frames but not all, with no scenes[] to derive the rest -> ERROR
  `invalid_scene` (ambiguous input beats a silent guess).
- **Scene info absent entirely** (digest P0): warn + all samples get `scene_index 0` + the effective
  max gap becomes `min(max_gap_ms, no_scene_max_gap_ms)` (defaults 5000 -> 2000 ms). Recorded in
  `tracker_params.scene_info = "absent"` + `max_gap_ms_effective`. The warning makes the envelope
  status `partial` (existing 0.1.0 warning semantics kept).

## 6. Frame dimensions / clipping

`frame_width`/`frame_height` from named params > InputsJson > input doc top level; must be given
together; when absent both are `null` in the canonical file and NO clipping occurs (fixture inputs
often have no real frame). Clipping happens in milli-pixel space AFTER quantization; a box clipped (or
quantized) to zero width/height stays a detection (warning, like 0.1.0's degenerate-box path) but can
never IoU-match, cannot centroid-match (zero area fails the gates), and can still birth a track.

## 7. Association tiers (digest P0s, exact readings)

- Tier 1 (`kind: "iou"`): quantized `iou_q >= iou_threshold_q` with positive integer intersection.
  `iou_q = round_half_up(inter * 1e6 / union)` on milli-pixel integer areas. The GATE uses the
  quantized value ("quantize immediately, then compare") -- not an exact rational compare.
- Tier 2 (`kind: "centroid"`): ONLY when integer intersection == 0 (the digest: "when IoU==0 from
  displacement"). A pair with 0 < IoU < threshold qualifies for NEITHER tier by design (uncertainty ->
  end the track; fragmentation is the accepted failure). Gates, all integer: same class + same scene
  (grouping), `elapsed <= max_gap_ms_effective`, squared-center displacement (doubled-center trick, so
  centers stay integral) normalized by the **squared diagonal of the LARGER-AREA box** (tie -> the
  track's previous box) within `min(cap, base + floor(growth * gap_ms / 1000))`, and the
  cross-multiplied area-ratio gate `max(prevA/newA, newA/prevA) <= max_area_ratio` (both areas must be
  > 0). The digest offered "larger area or squared diagonal" as the normalizer; squared diagonal of the
  larger-area box was chosen (same units as the squared displacement, scale-honest for elongated
  boxes).
- Strict outranking: every tier-1 edge costs `1e6 - iou_q` (0..1e6); every tier-2 edge costs
  `2e6 + normalized_center_distance_q` (>= 2e6); no blended float sum exists.
- `iou_threshold 0` edge case: a zero-overlap pair then satisfies `iou_q >= 0` and is admitted as
  TIER 1 (greedy parity with 0.1.0's `>=` compare); tier 2 never fires at threshold 0.

## 8. Global assignment + THE TIE RULE (digest P0)

Per class per scene per sample: minimum-cost bipartite assignment (a pinned integer Hungarian,
potentials/augmenting-path form, pure pwsh, no SciPy) over rows = live tracks in track_id order,
cols = detections in canonical order. Forbidden pairs carry a uniform INF cost (1e12) >> any real
total, so the optimum is MAX real-edge cardinality first, then min real cost. **Tie rule (contract):
among equal-(cardinality, total-cost) optima, the lexicographically smallest ordered
`(track_id, detection_rank)` list wins** -- implemented by incremental fixing (rows in track_id order,
candidate ranks ascending, each candidate verified by re-solving the residual), NOT by trusting solver
whim; symmetric matrices are part of the test gate. Matching a track always lexicographically beats
leaving it unmatched, so unmatched only happens when no detection preserves the optimum. The
refinement is O(rows * cols) Hungarian re-solves per (class, scene, sample) group -- negligible at
fixture scale and acceptable at the #16 100-detection cap; a faster uniqueness-aware refinement is a
named follow-on if profiling ever demands it.

## 9. Aging + termination semantics

- **max_gap**: evaluated when the next sample of the track's scene arrives (a file-driven tracker has
  no clock between samples): `elapsed = sample_ts - last_observed_ms > max_gap_ms_effective` ->
  terminate BEFORE association (an over-gap track can never link; `terminated_at_ms` = that sample's
  ts). A gap EXACTLY equal to the cap stays alive (`<=` admits, `>` kills).
- **max_missed_samples**: every processed sample in the track's scene after its last observation that
  does not match it (regardless of which classes that sample contains -- "sampled frames with no
  match") increments `missed`; `missed > max_missed_samples` terminates at that sample's ts.
- **scene_boundary**: the first sample of a DIFFERENT scene terminates every active track of any other
  scene (checked before max_gap; a track crossing both conditions reads `scene_boundary`).
  `terminated_at_ms` = the triggering sample's ts.
- **end_of_input**: remaining actives terminate with `terminated_at_ms` = the FINAL sample's ts (equal
  to `last_observed_ms` for a track observed at that final sample).
- `missed_samples_at_termination` = the track's missed counter when terminated.

## 10. Observations, gaps, links

- Observation `association` records `{kind, previous_frame_index, gap_ms, missed_samples, iou_q,
  normalized_center_distance_q, area_ratio_q}`; birth -> ALL previous-link metrics null. `gap_ms` is
  the elapsed ms since the previous observation for EVERY link (also ordinary consecutive-sample
  links); `missed_samples` is the track's missed count consumed by that link (0 for a next-sample
  link). For iou links the geometric fallback metrics are still reported when defined
  (`normalized_center_distance_q` null only if both boxes are degenerate; `area_ratio_q` null if
  either area is 0).
- A GAP record exists IFF a link consumed `missed_samples >= 1`: `{after_sample_index,
  before_sample_index, start_ms, end_ms, elapsed_ms, missed_samples, reacquired_by}`. No coast
  pseudo-observations exist in stable mode; nothing fabricates boxes.
- `detection_index` = the detection's ORIGINAL index within its input frame (provenance to re-find it
  in #16 output); canonical ordering lives only in processing (`detection_rank` is not persisted).
- `low_confidence` = the input detection's own `low_confidence` field when present, else
  `detection_score < low_confidence_threshold` (quantized compare; default 0.5 = #16's default
  confidence threshold); score-less detections are NOT low_confidence (unknown != low).

## 11. Evidence separation; NO aggregate confidence; quality_score NOT emitted

`score_summary` (detection evidence) and `association_summary` (association evidence) are separate per
the digest. `mean/min/max_detection_score_q` are over SCORED observations only
(`scored_observation_count` added for auditability; a scoreless track has null mean/min/max).
`association_summary.maximum_gap_ms` = max `gap_ms` over the track's links (0 with no links).
`mean/weakest_link_quality_q` use the versioned formula **`link_quality/1`** (recorded in
`tracker_params.link_quality_formula`): iou link -> `iou_q`; centroid link -> `max(0, 1e6 -
normalized_center_distance_q)`; null with no links. **The optional single ranking value
`quality_score` is NOT emitted in 0.2.0** -- the digest says "if a single ranking value is required";
none is yet, and the auditable components are all present, so video.timeline can rank from evidence
(emitting a versioned `quality_score/N` later is additive).

## 12. Identity + classes

- `identity_scope = "source_media+scene+tracker_invocation"`; `track_id` is a monotonic never-reused
  non-negative integer within the invocation, NOT a cross-video identity.
- Class identity is the exact class STRING (case-sensitive ordinal), immutable per track; `class_id`
  is recorded from the birth detection (integral or null; a non-integral class_id is an ERROR in
  stable mode). Canonical detection ordering keys on `(class_id [null -> -1], class, ...)` -- the class
  string is the added tiebreak for null/duplicated class_id families.
- `class_filter` in `tracker_params` is the applied `-Classes` filter, sorted ordinal ([] = none).

## 13. Sample manifest

`samples[]` lists EVERY processed sample `{sample_index, frame_index, timestamp_ms, scene_index,
detection_count}`. `detection_count` = detections the TRACKER saw (after class/min-score filtering and
quantization) -- the count that explains gaps/births; raw pre-filter counts stay in diagnostics.
Samples are ordered `(timestamp_ms, frame_index, input position)`; duplicate timestamps are legal and
process in that order with `gap_ms 0` between them.

## 14. Stable-mode input strictness (beyond 0.1.0)

Stable mode ERRORS on: bare-array frames (no timestamps), missing timestamps (`missing_timestamp`),
non-finite box/score/timestamp values, non-integral frame index / scene_index / class_id
(`invalid_detection` / `invalid_frame` / `invalid_scene`), values whose quantization would overflow
(|v * scale| > 9e15), and partial per-frame scene coverage without a scenes list. Greedy mode keeps
0.1.0's permissiveness byte-for-byte.

## 15. Envelope-level notes

The result envelope's `inputs_digest` equals the canonical `input_digest` in stable mode (greedy keeps
0.1.0's tracks-doc digest). The stable `result` = `{mode, canonical (the full canonical doc),
canonical_path, canonical_sha256, diagnostics_path}`. `MaxAge` is greedy-only and ignored (not
validated) in stable mode; the stable aging knobs are ignored by greedy likewise. Artifacts:
`tracks.json` (canonical), `diagnostics.json`, `tracks.md` (human table), `result.json`, `stderr.txt`.

## 16. Named exclusions (digest "Exclude" list -- NOT built, restated for the fold)

Kalman/constant-velocity prediction; learned re-ID/embeddings; optical flow; camera-motion
compensation; cross-class alias families; interpolated coast boxes; global identity across
scenes/videos; ByteTrack low-score recovery (needs coordinated detector output); any probabilistic
aggregate track confidence; live #32 -> #16 -> #33 composition; **and the review's deepest OPEN
QUESTION: whether sparse semantic keyframes carry enough continuity for identity at all -- the likely
eventual architecture needs a dense low-res tracking-sample stream from media.decompose (sparse
keyframes = semantics; dense lightweight frames = temporal identity), and `video.timeline` #21's input
contract should not be frozen before that call is made.**
