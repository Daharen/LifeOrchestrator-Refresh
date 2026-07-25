# detect.objects — example invocations

Detect objects in one image and get class boxes + real per-detection confidence.

## Direct (named params)

```powershell
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\dog.jpg
```

## Filter to specific COCO classes, downscale a huge image first

```powershell
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\street_8k.png -MaxDimension 1280 -Classes person,car,truck
```

`-MaxDimension` composes **image.util** (Module 15) to downscale before inference and rescales the
returned boxes back into original-image pixels.

## Detect on the live screen (composes capture.screen, Module 6)

```powershell
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -Capture -CaptureInputsJson '{"target":"window","title":"*Chrome*"}'
```

## Via -InputsJson (how the executor / wrapper call it)

```powershell
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputsJson '{"input":"street.jpg","score_threshold":0.4,"confidence_threshold":0.5}'
```

## Through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"input":"dog.jpg"}'
```

## Notes

- Default model is `detect.yolox.nano` (COCO-80, Apache-2.0), resolved from `models.json` (type=detector),
  decoupled from the gateway's `wired` gate. Use `-Tier tiny` or `-Model <id>` to switch.
- Default execution provider is **cpu** → no GPU/port binding, so the skill is `parallel_safe`.
  `-Provider cuda` binds the GPU and is not parallel-safe.
- `confidence` in the result envelope is the best detection's score. A result whose best score falls
  below `-ConfidenceThreshold` (default 0.5), or that finds **no** objects on a non-empty image, is routed
  to the review queue (`flagged_by:"detect.objects"`, `verify_detections` / `verify_no_objects`).
