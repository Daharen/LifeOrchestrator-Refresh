# Module 33 -- Object Tracking (`track.objects`)

The **second module of the Phase C video spine** (architectural position 20, "identity across frames"),
following `media.decompose` #32 (position 19). It gives objects a **stable identity across a sequence of
frames**: given per-frame object detections in the `detect.objects` #16 output shape, it associates them
into tracks so the same object keeps **one `track_id`** from frame to frame. It emits a contract-valid
`lifeorch.skill.result/0.1` envelope plus a `tracks.json` artifact and a human summary. It is
**deterministic** (a pure function of the input bytes; no model -> `confidence` is null) and
`parallel_safe:true` (reads a JSON input, writes only to its own invocation artifact dir; **no CUDA, no
model, no loopback port, no randomness**).

## What it does

It runs a **deterministic, per-class, frame-by-frame greedy IoU association**:

1. For each frame, build candidate `(active track, detection)` pairs **of the same class** whose IoU
   (of the track's last-known box and the detection's box) is `>= -IouThreshold`.
2. Resolve assignments by a **total order** -- IoU **descending**, ties broken by **detection order**
   then **track_id** -- so the greedy result is unambiguous and seedless-stable.
3. Apply lifecycle transitions:
   - **matched** -> extend the track; its box becomes the new last-known box;
   - **unmatched detection** -> **BIRTH** a new track with the next monotonic `track_id` (births are
     assigned in detection order);
   - **unmatched track** -> **COAST** (a simple constant-position predictor keeps its last box) for up to
     `-MaxAge` frames, then **DEATH** -- once dead it can no longer be revived, so a later detection in the
     same place **births a new id** (aged-out => new identity).

Same input -> **byte-identical** tracks.

## Decoupled MVP (no live detection this wave)

Input is a JSON **detection sequence** read from a file (`-InputFile`) or passed inline
(`-InputsJson.frames`). The module does **not** call `detect.objects` #16 or `media.decompose` #32 live --
it is a pure association primitive over provided/fixture detections. Live composition
(`#32` keyframes -> `#16` detections -> `track.objects`) is a **named follow-on**, not this wave.

## Input shape (matches detect.objects #16 exactly)

Each detection is the #16 shape -- `{ "class": <str>, "class_id": <int?>, "score": <num?>, "box": { "x", "y", "width", "height" } }`
(`box` is a top-left corner + size, the #16 representation) -- so the two modules **compose later without a
shim**. Accepted top-level shapes: a bare array of frames, `{frames:[...]}`, `{sequence:[...]}`, or a single
`#16` result (`{detections:[...]}`) treated as one frame. Each frame is either a bare array of detections or
`{ frame|index, timestamp_s|timestamp, detections:[...] }`; a missing frame index defaults to the sequence
position.

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -IouThreshold 0.4 -MaxAge 3
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -Classes person,car -MinScore 0.5
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{"input":"detections.json","max_age":1}'
```

Key parameters: `-IouThreshold` (0..1, match floor, default 0.3), `-MaxAge` (coast frames before death,
default 2; 0 disables coasting), `-MinScore` (drop detections scored below this, default 0), `-Classes`
(class-name filter). See `skill.json` for the full list.

## Result shape

```
result = {
  input:   { source: "file"|"inline", path, frames },
  params:  { iou_threshold, max_age, min_score, classes },
  summary: { input_frames, input_detections, tracked_detections, track_count, births, deaths,
             coast_frames, max_concurrent_tracks, class_summary:{ class: count } },
  tracks:  [ { track_id, class, class_id,
               frames:[ { frame, timestamp_s, box:{x,y,width,height}, score, det_index } ],
               first_frame, last_frame, length, aged_out } ]   # ordered by track_id
}
```

Artifacts land in `runtime/artifacts/<invocation_id>/`: `tracks.json`, `tracks.md`, `result.json`,
`stderr.txt`. Every artifact path in the envelope is absolute. **`tracks.json` deliberately omits volatile
fields** (invocation_id / timestamps live in the envelope), so it is **byte-identical for identical input** --
the determinism guarantee, provable by a repeated-run `sha256` compare.

## Errors (always a valid envelope, exit 0)

`no_input`, `input_not_found`, `input_parse_failed`, `invalid_input_shape`, `invalid_frame`,
`invalid_detection`, `invalid_iou_threshold`, `invalid_max_age`, `invalid_min_score`, `invalid_inputs_json`,
`unhandled_exception`. A detection with a degenerate box (`width`/`height <= 0`) is **not** an error -- it is
a warning + status `partial` (it simply cannot match by IoU).

## Scope

**In (this MVP):** a deterministic, CPU-only, `parallel_safe:true` IoU-association tracker over per-frame
`#16`-format detections -> identity tracks, with a constant-position coast/age-out lifecycle.

**Out (named follow-ons, NOT built here):**

- a **live-composition** convenience mode (`#32` keyframes -> `#16` detections -> `track.objects`);
- a **Kalman / constant-velocity** motion model (the coast predictor is constant-position);
- **appearance / embedding re-ID** (to survive long occlusions and hard crossings where IoU alone switches
  identity);
- the searchable **`video.timeline` #21** fuse (architectural position 21) that **consumes** these tracks;
- an **overlay / annotated video**; **batch / directory** input.

This module is **not** a review-queue producer.

## Tests

`tests/Invoke-TrackObjectsTests.ps1` is **dual-mode + OS-portable** (uses `[IO.Path]::GetTempPath()`), so
the same harness is both the cloud pre-ship gate and the live Windows/executor test (`-Live`). Because the
tracker is pure logic (no CUDA / model / binary), the assertions are identical in both modes. Fixtures are
generated at runtime by `New-TrackFixture.ps1` (pure PowerShell) -- crossing paths, an occlusion-coast, a
mid-sequence birth, an aged-out death (+ new-id rebirth), a per-class no-merge, an empty sequence, and a
combined 6-frame `scenario` (also committed as `tests/fixtures/scenario.json`). It AST-parses the shipped
`.ps1` files, validates the manifest, exercises every lifecycle transition, the param knobs, determinism
(byte-identical `tracks.json` across two runs), every error path, `-InputsJson` inline frames, and the
Module 1 wrapper.
