# track.objects -- example invocation

Associate a sequence of per-frame `detect.objects` #16 detections into stable identity tracks.

## Direct

```powershell
# default association (IoU >= 0.3, coast up to 2 frames)
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json

# stricter match + longer occlusion tolerance, only people and cars
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json `
  -IouThreshold 0.4 -MaxAge 3 -Classes person,car
```

## Input file (a detection sequence in the #16 output shape)

`detections.json`:

```json
{
  "frames": [
    { "frame": 0, "timestamp_s": 0.0, "detections": [
      { "class": "car", "class_id": 2, "score": 0.90, "box": { "x": 20, "y": 20, "width": 40, "height": 40 } },
      { "class": "car", "class_id": 2, "score": 0.85, "box": { "x": 95, "y": 190, "width": 40, "height": 40 } }
    ] },
    { "frame": 1, "timestamp_s": 0.5, "detections": [
      { "class": "car", "class_id": 2, "score": 0.90, "box": { "x": 35, "y": 20, "width": 40, "height": 40 } },
      { "class": "car", "class_id": 2, "score": 0.85, "box": { "x": 80, "y": 190, "width": 40, "height": 40 } }
    ] }
  ]
}
```

Each detection matches `detect.objects` #16 exactly (`{class, class_id, score, box{x,y,width,height}}`), so
`#16` output feeds straight in. A bare array of frames, `{sequence:[...]}`, or a single `#16` result
(`{detections:[...]}`, one frame) are also accepted.

## Via -InputsJson (how a local/frontier caller or an orchestrator invokes it)

```powershell
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{
  "input": "detections.json",
  "iou_threshold": 0.3,
  "max_age": 2,
  "classes": ["car"]
}'
```

Detections can also be passed **inline** (no file) via the `frames` key:

```powershell
pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{"frames":[{"frame":0,"detections":[{"class":"dog","class_id":16,"score":0.9,"box":{"x":10,"y":10,"width":40,"height":40}}]}]}'
```

## Wrapped (Module 1 generic runner)

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"input":"detections.json"}'
```

## Through the executor (task package)

`task.ps1`:

```powershell
pwsh -NoProfile -File 'C:\Users\just_\LifeOrchestrator-Refresh\modules\33-track-objects\Invoke-TrackObjects.ps1' `
  -InputsJson '{"input":"C:\\Users\\just_\\detections.json","iou_threshold":0.3,"max_age":2}'
```

The single `lifeorch.skill.result/0.1` JSON envelope is written to stdout (captured by the executor into
`stdout.txt`); `tracks.json` (byte-identical for identical input) + `tracks.md` land under
`runtime/artifacts/<invocation_id>/`. A representative envelope is in `example-result.json`.
