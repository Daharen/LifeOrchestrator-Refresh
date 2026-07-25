# gen.image — example invocations

## Direct (named params)
```powershell
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -Prompt "a red apple on a wooden table, studio photo" -Seed 42
```

## Direct (a taller image, more steps, JPEG)
```powershell
pwsh -NoProfile -File .\Invoke-GenImage.ps1 `
  -Prompt "a lighthouse at dusk, dramatic sky" `
  -NegativePrompt "blurry, lowres, watermark" `
  -Width 512 -Height 768 -Steps 25 -Guidance 8 -Scheduler dpm++ -Format jpg
```

## Generic `-InputsJson` (a router / the executor / an orchestrator skill)
```powershell
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -InputsJson '{
  "prompt": "a small green cactus in a clay pot on a windowsill",
  "negative_prompt": "blurry, extra limbs",
  "width": 512, "height": 512, "steps": 20, "guidance": 7.5,
  "seed": 2024, "scheduler": "dpm++", "format": "png"
}'
```

## Through the Module 1 generic wrapper (manifest → run → envelope validation)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"prompt":"a bowl of ramen, top-down"}'
```

## Through the executor (task package)
`task.ps1`:
```powershell
pwsh -NoProfile -File C:\Users\just_\LifeOrchestrator-Refresh\modules\23-gen-image\Invoke-GenImage.ps1 `
  -InputsJson '{"prompt":"a mountain lake at sunrise","steps":20}'
```

Notes:
- `-Seed -1` (default) picks a random seed and records the actual seed used in `result.request.seed`.
- The image is written to `runtime/artifacts/<invocation_id>/image.<png|jpg|webp>`; its absolute path,
  bytes, and sha256 are in `result.image`.
- A blank or failed generation is flagged to the review queue (`verify_generation`, `flagged_by:"gen.image"`).
