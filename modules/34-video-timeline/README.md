# video.timeline — Searchable Video Timeline (Module 34)

Fuses the per-source artifacts of the Phase C video spine into **ONE canonical, deterministic, searchable
timeline JSON**. Third module of the video block (architectural position 21), downstream of
`media.decompose` #32 (pos 19) and `track.objects` #33 (pos 20), governed by the folded frontier design
review `core-docs/research/2026-07-30-track-objects-design-review.md` (the reviewed track schema, the
sample-manifest semantics, and the canonical-serialization discipline).

It is **fixture-driven** in this MVP: inputs arrive as a per-source artifact **manifest** (JSON), not from
live invocations of #32/#16/#33/#11/#14 (live composition is a named follow-on). It is pure deterministic
CPU logic — no model, no CUDA, no network, no randomness → `parallel_safe:true`, byte-identical output for
identical input **across machines** (the tests print `CANONICAL-HASH` lines so the cloud and `-Live` runs
are compared hash-for-hash).

## What it consumes (the manifest)

```jsonc
{
  "media":      { "id?": "...", "path?": "...", "source_media_sha256?": "hex64",
                  "meta": <#32 meta.json | its inner object | {frame_width?, frame_height?, duration_ms}> },   // REQUIRED
  "scenes":     <#32 scenes doc or bare [{index, start, end, score}]>,          // seconds -> integer ms (round-half-up)
  "samples":    [{sample_index, frame_index, timestamp_ms, scene_index?, detection_count?}],   // the reviewed sample manifest
  "tracks":     <path or inline reviewed-schema track file>,                    // {schema, identity_scope?, timestamp_unit?, samples?, tracks:[...]}
  "transcript": <{segments:[{t0_ms, t1_ms, text}]} or bare array>,              // #11 shape (start_ms/end_ms aliases accepted)
  "ocr":        [{timestamp_ms | frame_index, lines:[{text, ...}]}],            // #14 lines per keyframe
  "detections": [{timestamp_ms, sample_index?, detections:[{class, class_id?, score?, box{x,y,width,height}}]}]   // #16 shape
}
```

Only `media` (with a resolvable duration) is required. Every **provided** input is validated **strictly**;
any violation produces a fail-closed `status:"error"` envelope with `result.violations[{path, why}]`
enumerating every one, and **no timeline is written**. Unknown extra fields are tolerated, never repaired.
Cross-source consistency is enforced fail-closed too: when a sample manifest exists, every track
observation (and every detections entry carrying `sample_index`) must agree with it.

## What it emits

`timeline.json` — schema `lifeorch.video_timeline/0.1`, canonical bytes (UTF-8 no BOM, one line + one
trailing LF, ordinal-sorted keys, compact separators, integer ms everywhere, no NaN/Inf, **no absolute
paths / invocation ids / wall-clock**), carrying:

- **`coverage`** — the normalized sample manifest embedded (`samples`, `sample_count`, `span`,
  `samples_source`), `status: sampled|unknown`, and `presence_semantics`. This is what keeps
  **"sampled with no detection" vs "not sampled" vs "tracker gap" distinguishable**.
- **`scenes[]`** — normalized `{scene_index, start_ms, end_ms}`.
- **`intervals[]`** — per-track **appearance segmentation**: contiguous observed spans split at recorded
  gaps. Each `track_presence` span carries `observation_count` + **separated evidence**
  (`evidence.detection`: `mean/min/max_detection_score_q`, `low_confidence_count`;
  `evidence.association`: `iou_link_count`, `centroid_link_count`, `reacquisition_count`,
  `weakest_link_quality_q`, `maximum_gap_ms`). Each recorded gap is its own first-class
  `track_gap` interval (`elapsed_ms`, `missed_samples`, `reacquired_by`). **Spans are never merged across
  a gap** — false continuity is semantically corrupting; a consumer may group fragments later, but a merge
  cannot be undone.
- **`events[]`** — `speech {start_ms,end_ms,text}`, `ocr_text {timestamp_ms,text,line_count}`,
  `detection_sample {timestamp_ms,sample_index,class_counts}`, `scene_cut {timestamp_ms,scene_index}`,
  sorted by `(time, kind, content)` — fully presentation-order-free.
- **`index`** — `by_class / by_track / by_scene / by_kind`, refs = stable positions into
  `intervals[]`/`events[]`.
- **`summary`** — counts per kind + per class, `track_count`, `span_count`, `coverage_ms`.
- **`identity_scope`** — carried **verbatim** from the track file (track ids are scoped to
  source + scene + tracker invocation; nothing here ever implies cross-video identity).
- `generator {name, version, params}` + `input_digest` (sha256 of the canonical normalized inputs; also
  the envelope's `inputs_digest`).

**No field named `confidence` appears anywhere in the canonical timeline** (the tests grep the bytes).

The `lifeorch.skill.result/0.1` envelope is the separate diagnostics/invocation side (paths, timestamps,
warnings, artifact hashes); `timeline.md` is a small human summary. Every digest interpretation this
module makes is recorded in **`SCHEMA_NOTES.md`** (33 numbered notes).

## Honest degradation modes (documented + tested)

| inputs present | behavior |
|---|---|
| meta only | valid timeline; sections empty; `coverage.status = "unknown"`; status `ok` |
| tracks, no samples | spans + gaps still emitted; `coverage "unknown"` + `presence_semantics "downgraded_no_sample_manifest"` + explicit warning → status `partial` |
| transcript only | speech events only; status `ok` |
| ocr by `frame_index` + samples | timestamps mapped through the sample manifest (exact frame match) |
| ocr by `frame_index`, no samples | **REFUSED** with a violation — timestamps are never invented |
| sections present but empty (`[]`) | valid; `samples:[]` → `status "sampled"`, `sample_count 0` (we *know* nothing was sampled — distinct from unknown) |

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputFile .\manifest.json
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputsJson '{"input":"manifest.json"}'
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputsJson '{"media":{"id":"clip","meta":{"duration_ms":12000}}}'
```

Precedence: `-InputFile` > `InputsJson.input` > `InputsJson.manifest` > InputsJson-as-manifest (recognized
by its `media` key). The manifest's `tracks` value may be a path (resolved relative to the manifest file)
or inline. Optional `-ArtifactRoot`, `-InvocationId`. Wrapped (Module 1) or as an `exec.bootstrap` task
package, exactly like the other skills.

## Determinism

Identical canonical input content + generator version + params → identical canonical bytes, on any
machine: double-run byte-identity, an order-scrambled twin fixture that must hash identically, and
cross-environment `CANONICAL-HASH` comparison (cloud Linux pwsh vs the Windows executor) are all asserted
in the tests. All decision arithmetic is integer (ms, q-millionths); floats exist only at the two
documented conversion points (seconds→ms, score→q, round-half-up) and a float reaching the canonical
serializer throws.

## Tests

`tests/Invoke-VideoTimelineTests.ps1` — dual-mode, OS-portable, the real skill in both modes (no mock);
138 assertions over 13 committed fixtures (`tests/fixtures/`): the full fuse + scrambled twin, every
degradation mode, adversarial inputs (overlapping/out-of-order scenes, gap-heavy track, zero-observation
track, unlisted sample, out-of-order everything), 19 strict-validation refusal paths, canonical byte
discipline, double-run identity, and the Module 1 wrapper.

## Not in this MVP (named follow-ons)

Live composition of `#32 → #16 → #33 → video.timeline` (+ #11/#14 side feeds) once the upgraded #33
emitter lands; `video.interpret` (position 22 — any VLM/model semantics); full-text search /
`artifact.search` #23 integration; rendering (overlay video, HTML/markdown export); cross-video/global
identity; a `quality_score` ranking value (versioned formula); and the review's open **decision-gate
question** — whether sparse #32 keyframes carry enough continuity for identity at all, or whether the
input contract must add a **dense low-res tracking-sample stream** (sparse keyframes for semantics,
denser lightweight frames for temporal identity) — is restated here unresolved and belongs to the #33
refinement track.
