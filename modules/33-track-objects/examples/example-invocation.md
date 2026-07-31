# track.objects -- example invocation (0.2.0)

Associate a sequence of per-frame `detect.objects` #16 detections into stable identity tracks.
`-Mode stable` (the default since 0.2.0) is the scene-bounded, elapsed-time-aged, globally-assigned
geometric tracker with the canonical `lifeorch.track.objects/0.2` output; `-Mode greedy` is the
byte-identical 0.1.0 baseline.

## Direct (stable, the default)

```powershell
# default stable association (scenes read from the input doc)
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json

# widen the elapsed-time aging; scenes from a media.decompose #32 scenes.json
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json `
  -MaxGapMs 8000 -MaxMissedSamples 2 -ScenesFile ..\32-media-decompose\runtime\artifacts\<id>\scenes.json

# the retained greedy baseline (regression oracle / debug)
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -Mode greedy -MaxAge 3
```

## Input file (the #16 shape + timestamps + scenes; stable REQUIRES timestamps)

`detections.json`:

```json
{
  "frames": [
    { "frame": 0, "timestamp_ms": 0, "detections": [
      { "class": "car", "class_id": 2, "score": 0.90, "box": { "x": 20, "y": 20, "width": 40, "height": 40 } },
      { "class": "car", "class_id": 2, "score": 0.85, "box": { "x": 95, "y": 190, "width": 40, "height": 40 } }
    ] },
    { "frame": 1, "timestamp_ms": 500, "detections": [
      { "class": "car", "class_id": 2, "score": 0.90, "box": { "x": 35, "y": 20, "width": 40, "height": 40 } },
      { "class": "car", "class_id": 2, "score": 0.85, "box": { "x": 80, "y": 190, "width": 40, "height": 40 } }
    ] }
  ],
  "scenes": [ { "index": 0, "start": 0.0, "end": 4.0, "score": 0.9 } ]
}
```

Each detection matches `detect.objects` #16 exactly; the `scenes` list is the `media.decompose` #32
seconds shape (`{index,start,end,score}`), so both upstream modules feed straight in. `timestamp_s`
(seconds) is accepted and rounded half-up to ms; per-frame `scene_index` overrides derivation. Scene
info absent entirely -> a warning + the documented conservative max gap (status `partial`). A bare
array of frames / `{sequence:[...]}` / a single `{detections:[...]}` object are also accepted
(greedy-compatible; stable still needs timestamps).

## Via -InputsJson (how a local/frontier caller or an orchestrator invokes it)

```powershell
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{
  "input": "detections.json",
  "max_gap_ms": 5000,
  "max_missed_samples": 3,
  "scenes": [ { "index": 0, "start": 0.0, "end": 4.0 } ],
  "source_media_id": "clip-001",
  "detector_provenance": { "model_id": "detect.yolox.nano" }
}'
```

Inline frames (no file) via the `frames` key work as before; add `"mode":"greedy"` for the baseline.

## Wrapped (Module 1 generic runner)

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"input":"detections.json"}'
```

## Through the executor (task package)

`task.ps1`:

```powershell
pwsh -NoProfile -File 'C:\Users\just_\LifeOrchestrator-Refresh\modules\33-track-objects\Invoke-TrackObjects.ps1' `
  -InputsJson '{"input":"C:\\Users\\just_\\detections.json","max_gap_ms":5000}'
```

The single `lifeorch.skill.result/0.1` JSON envelope is written to stdout (captured by the executor
into `stdout.txt`). Stable artifacts under `runtime/artifacts/<invocation_id>/`: `tracks.json` -- the
CANONICAL track file (sorted keys, compact, integers only, one trailing LF; `sha256` reproducible
across machines) -- plus `diagnostics.json` (every volatile field) and `tracks.md`. A representative
stable envelope is in `example-result.json`; the committed canonical fixture is
`tests/fixtures/probe-moderate-gap.json`.
