# SCHEMA_NOTES -- video.timeline 0.1.0

Every interpretation this module makes where the governing digest
(`core-docs/research/2026-07-30-track-objects-design-review.md`) under-specifies a detail. The digest is
the contract; a PARALLEL worker is upgrading `track.objects` #33 to EMIT the reviewed schema, so the
orchestrator reconciles both sides at fold against this list. Numbered for reference from the fold report.

## Canonical serialization (concretizing "RFC 8785-style")

1. **One line + one trailing LF.** The canonical `timeline.json` is a single-line JSON document followed by
   exactly one `\n` (no CR anywhere, UTF-8 without BOM). "Fixed newline" is realized as this one terminator.
2. **Key order = ordinal** (`StringComparer.Ordinal`) at every object level. Compact separators (`,` / `:`).
3. **String escapes are minimal:** `\"`, `\\`, `\b \t \n \f \r`, `\u00xx` (lowercase hex) for other
   controls < 0x20; non-ASCII characters are emitted literally as UTF-8, never `\u`-escaped.
4. **Integers only.** No floating-point value may reach the canonical document -- the serializer THROWS on
   a double/decimal (`canonical_float_leak`), which is a self-check, not an input error path.
5. **Rounding rule** (the only two places non-integers are accepted and converted): seconds -> ms and
   score -> q both use non-negative round-half-up (`floor(x + 0.5)`). Everything already in ms must be
   integral -- a fractional `*_ms` input is a VIOLATION, not a rounding opportunity.
6. **`_q` units = integer millionths** (score/IoU x 1,000,000), per the review's "scores to integer
   millionths" quantization.

## input_digest

7. `input_digest = "sha256:" + sha256(canonical bytes of the NORMALIZED inputs document)` -- i.e. the hash
   is over content after validation, canonical ordering, and unit conversion, so two presentations of the
   same content (scrambled arrays, different key order) share one digest. It doubles as the envelope's
   `inputs_digest`. It is NOT a hash of the raw manifest file bytes (EOL/indentation-immune by design).

## media

8. `media.meta` accepts three forms: the #32 `meta.json` document (`{schema, meta:{...}}`), its inner
   object (`{container, streams, duration_s}`), or inline `{frame_width?, frame_height?, duration_ms}`.
   Duration resolution order: `duration_ms` > `duration_s` > `container.duration_s`. Dims come from inline
   fields or the FIRST `codec_type == "video"` stream; audio-only media yields null dims (valid).
9. **`media_id` is never derived from a path.** Absent `media.id` -> canonical `media_id: null`. Deriving
   an id from a filename would import environment-specific filesystem naming into the canonical bytes.
   `media.path` is diagnostics-only (envelope), never canonical. `media.sha256` is accepted as an alias
   for `media.source_media_sha256`; the manifest's value wins over the track file's.

## samples / coverage

10. Per-sample REQUIRED fields: `sample_index`, `frame_index`, `timestamp_ms` (all integer, >= 0);
    `scene_index` / `detection_count` are optional and pass through as given or null (never derived).
    Duplicate `sample_index` -> violation. Canonical order: `sample_index` ascending.
11. **Sample-manifest source precedence: manifest `samples` > the track file's own `samples`** (the review
    lists `samples` at track-file level; the manifest may also carry it directly). `coverage.samples_source`
    records which one fed the timeline (`"manifest"` | `"tracks"` | null).
12. **Coverage embeds the full normalized sample manifest** (`coverage.samples`) -- the strongest form of
    "sampled vs not-sampled distinguishable": every sampled instant, with its `detection_count`, is in the
    timeline itself. `coverage.span.coverage_ms` (= `summary.coverage_ms`) is the observed EXTENT
    (last_sample_ms - first_sample_ms), not an integral of sampled time -- samples are instants, and
    inventing per-sample dwell windows would fabricate data.
13. **Present-but-empty vs absent:** `samples: []` -> `status:"sampled"`, `sample_count:0`, `span:null`
    (we KNOW nothing was sampled); samples absent entirely -> `status:"unknown"` +
    `presence_semantics:"downgraded_no_sample_manifest"`. The explicit downgrade WARNING (-> envelope
    status `partial`) fires only when tracks are present without any sample manifest -- that is the case
    where "sampled with no detection" vs "not sampled" actually becomes indistinguishable.

## tracks

14. **File-level validation floor:** only `schema` (string) and `tracks` (array) are REQUIRED here;
    `timestamp_unit` must equal `"ms"` IF present; `frame_width`/`frame_height` must MATCH the media dims
    if both sides carry them (violation otherwise); `identity_scope` is carried VERBATIM into the
    canonical top level (null when absent -- tolerated, since the emitter owns that field's presence).
    The full review file-level field list is the EMITTER's contract (#33 upgrade), not re-enforced here --
    enforcing presence of e.g. `detector_provenance` would couple this fuse to fields it does not consume.
15. Track-level REQUIRED: `track_id` (int, unique), `class` (non-empty string), `observations` (NON-EMPTY).
    A zero-observation track is REFUSED (`must be non-empty`): presence cannot be fabricated without
    observations. `scene_index` optional (null tolerated).
16. Observation REQUIRED: `sample_index`, `timestamp_ms`; optional: `frame_index`, `detection_score`
    (raw 0..1 float -> quantized to `_q` here), `low_confidence` (bool), `association{kind, iou_q, gap_ms}`
    with `kind` in {birth, iou, centroid}. Canonical observation order: `(timestamp_ms, frame_index,
    sample_index)` per the review.
17. **Cross-source checks are FAIL-CLOSED** (the review makes the sample manifest authoritative -- it lists
    EVERY processed sample): when an effective sample manifest exists, every observation's `sample_index`
    must be listed in it AND its `timestamp_ms` must equal the manifest's for that sample; a `detections[]`
    entry carrying `sample_index` is checked the same way. Disagreement is producer-side corruption, not
    something a fuse may paper over.
18. **Gap alignment:** a recorded gap is bound to a specific boundary between CONSECUTIVE observations --
    preferentially by `(after_sample_index, before_sample_index)`, else (when those fields are absent) by
    timestamp bracketing (`obs[k].timestamp_ms <= start_ms` and `obs[k+1].timestamp_ms >= end_ms`). An
    unalignable gap, or two gaps on one boundary, is a violation. `elapsed_ms` / `missed_samples` /
    `reacquired_by` pass through verbatim (null when absent -- never derived, e.g. elapsed is NOT
    recomputed as end-start).

## intervals (appearance segmentation)

19. Segmentation splits a track's canonical observation sequence at its recorded gaps ONLY. Every
    contiguous run becomes one `track_presence` interval spanning `[first_obs.timestamp_ms,
    last_obs.timestamp_ms]` -- a single-observation run is an instant (`start_ms == end_ms`). Nothing is
    coalesced across a gap under any parameterization (there are no knobs). Interval array order:
    `(track_id asc, per-track chronological)` -- gaps interleave presence spans in construction order.
20. `track_gap` intervals carry exactly the prompt's field set `{kind, track_id, start_ms, end_ms,
    elapsed_ms, missed_samples, reacquired_by}` -- no class/scene duplication (resolvable via track_id;
    the INDEX still lists gap intervals under the track's scene).
21. **Per-interval evidence is computed from that interval's OWN observations** (the digest defines these
    aggregates at track level; a segmented timeline owes each segment its own honest aggregates):
    - detection: `mean/min/max_detection_score_q` (mean = round-half-up of the q mean; all three null
      when no observation in the segment carries a score) + `low_confidence_count`.
    - association: `iou_link_count` / `centroid_link_count` count the segment's non-birth links --
      INCLUDING the segment's first observation when it carries the reacquisition link that crossed the
      preceding recorded gap (that link is evidence about how THIS appearance attached to the identity);
      `reacquisition_count` is therefore 0 or 1 per segment (1 iff the segment follows a recorded gap);
      `maximum_gap_ms` = max `association.gap_ms` over those links (the reacquisition link's crossing gap
      included -- it intentionally mirrors the adjacent `track_gap.elapsed_ms`).
22. **`link_quality` of a link = its `iou_q`, and 0 for a centroid link without one** -- the centroid
    fallback fires precisely when IoU == 0, so a centroid link's quality floor IS 0 in q units.
    `weakest_link_quality_q` = min over the segment's links; null when the segment has no links (pure
    birth). The review names `weakest_link_quality_q` without defining link quality; this is the minimal
    interpretation that needs no new formula (`normalized_center_distance_q` is a distance, not a quality,
    and inverting it would invent a versioned formula this MVP does not own).

## events

23. `scene_cut` = one event per scene at its `start_ms` (the #32 scene semantics: a scene begins at a
    detected cut; a scene starting at 0 still emits its cut -- uniformity beats special-casing t=0).
24. `speech` from #11 segments (`t0_ms`/`t1_ms`; `start_ms`/`end_ms` accepted as documented aliases --
    the digest speaks in start/end terms). `text` is required (empty string allowed).
25. `ocr_text.text` = the entry's line texts joined with `\n` in the given order (#14 lines are already
    reading-ordered; re-sorting them would repair, not canonicalize). `line_count` = number of lines.
    Frame-index-keyed entries map through the sample manifest by EXACT `frame_index` match; `timestamp_ms`
    wins when both keys are present; unmappable -> REFUSED (timestamps are never invented).
26. `detection_sample.sample_index` passes through as given or null -- it is NOT back-derived from the
    manifest by timestamp equality (derivation would blur the provenance the cross-checks enforce).
    `class_counts` keys are ordinal-sorted; an entry with `detections: []` is VALID and yields `{}` --
    that is the honest "sampled, nothing found" event.
27. **Event order = `(time, kind ordinal, canonical-bytes ordinal)`** where time is `start_ms` for speech
    and `timestamp_ms` otherwise. The prompt's "(start_ms, kind, stable id)" third key is realized as the
    event's own canonical serialization -- fully content-derived, so presentation order can never leak in;
    identical duplicate events sort adjacently and interchangeably (byte-equal either way).

## index / summary

28. Refs are 0-based positions into the FINAL `intervals[]` / `events[]` arrays. `by_kind` always carries
    all six kinds (empty arrays included) for shape stability; `by_track` keys are decimal strings (JSON
    object keys); `by_class` lists presence intervals of the class + detection_sample events whose
    `class_counts` contain it; `by_scene` lists presence intervals by the track's `scene_index` (gap
    intervals under the same track's scene) and events by half-open `[start_ms, end_ms)` containment --
    with overlapping (adversarial) scenes an event indexes under EACH containing scene; an event outside
    every scene is simply not in `by_scene`.
29. `summary.class_track_counts` counts TRACKS per class (like #33's class_summary), not intervals;
    `span_count` == `interval_counts.track_presence`.

## envelope / behavior

30. Warnings promote envelope status `ok -> partial` (the #33 convention). Current warning sources: the
    tracks-without-samples downgrade, and scene overlaps. Scene overlap / out-of-order presentation is
    tolerated + surfaced + canonically ordered by `scene_index`; duplicate scene indexes are violations.
31. On ANY violation: fail-closed `status:"error"`, `error.code = "input_validation_failed"`,
    `result.violations = [{path, why}]` enumerating every violation, and NO timeline.json is written.
32. Unknown extra fields are tolerated silently at every level (per the prompt), never copied into the
    canonical output, never "repaired".
33. **No field named `confidence` exists anywhere in the canonical timeline** (the tests grep the bytes);
    detection evidence stays under review names (`detection_score` -> `*_detection_score_q`,
    `low_confidence` -> `low_confidence_count`), association evidence under its own block, and no single
    ranking value is emitted at all (nothing to name `quality_score` yet -- if one is added later it takes
    that name plus a versioned formula, per the review).

## i22 orchestrator-fold reconciliation (video.timeline 0.1.1, vs the track.objects 0.2.0 emitter)

The two i22 workers were built in deliberate isolation against the same design digest; the orchestrator's
cross-module smoke (plan `fo-22-d2c492e7`: real `#33 -Mode stable` canonical output fed into this module)
found the two divergent readings below. Both are reconciled CONSUMER-SIDE here -- the emitter's canonical
bytes (and its shipped cross-env hashes) are untouched.

34. **`tracks.score_unit` is honored (was: silent x1e6 inflation).** The 0.2.0 emitter declares
    `score_unit: "millionths"` file-level and stores `observation.detection_score` as the ALREADY-quantized
    integer (its note #interpretations: "the digest's names kept"). 0.1.0 assumed a 0..1 float and
    re-quantized -- a real 900000 became 900000000000 in evidence q fields (an "ok" timeline with corrupt
    evidence). Now: `score_unit 'millionths'` => detection_score must be an integer 0..1000000, used
    verbatim as q; absent/'unit_float' => a 0..1 float (x1e6 round-half-up) and a score > 1 is a
    fail-closed violation instead of a silent scaling; any other declared unit is refused.
35. **`scene_index: -1` is valid on samples and tracks (was: refused `must be >= 0`).** The 0.2.0 emitter
    assigns pre-first-scene samples `firstIndex-1` (can be -1: "before the first listed scene"). Consumed
    as an opaque partition label: presence intervals carry it verbatim; `-1` is not a listed scene, so it
    never gains an `index.by_scene` bucket and scene_cut events are unaffected.

Verification: `tests/Invoke-VideoTimelineReconTests.ps1` + `tests/fixtures/tracks-millionths.json` /
`tracks-prescene.json` (REAL 0.2.0 canonical outputs embedded verbatim) / `tracks-scoreunit-refuse.json` /
`tracks-floatscore-refuse.json`.
