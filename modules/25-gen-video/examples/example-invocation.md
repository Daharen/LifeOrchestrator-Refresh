# gen.video — example invocations

## Direct (named params)
```powershell
pwsh -NoProfile -File .\Invoke-GenVideo.ps1 -Prompt "a drone shot over a misty forest at sunrise" -Seed 42
```

## Direct (a looping GIF, more frames)
```powershell
pwsh -NoProfile -File .\Invoke-GenVideo.ps1 `
  -Prompt "a candle flame flickering in the dark, close up" `
  -NumFrames 16 -Fps 10 -Format gif
```

## Generic `-InputsJson` (a router / the executor / an orchestrator skill)
```powershell
pwsh -NoProfile -File .\Invoke-GenVideo.ps1 -InputsJson '{
  "prompt": "timelapse of clouds rolling over a mountain range, cinematic",
  "num_frames": 16, "width": 512, "height": 512,
  "steps": 4, "guidance": 1.0, "fps": 8, "seed": 2024, "format": "mp4"
}'
```

## Through the Module 1 generic wrapper (manifest → run → envelope validation)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"prompt":"gentle ocean waves rolling onto a beach"}'
```

## Through the executor (task package)
`task.ps1`:
```powershell
pwsh -NoProfile -File C:\Users\just_\LifeOrchestrator-Refresh\modules\25-gen-video\Invoke-GenVideo.ps1 `
  -InputsJson '{"prompt":"a neon city street at night, rain, reflections","num_frames":16}'
```

Notes:
- `-Seed -1` (default) picks a random seed and records the actual seed used in `result.request.seed`.
  A fixed seed >= 0 is byte-reproducible on this GPU.
- The default 16-frame 512×512 clip peaks **~4.75 GB VRAM** full-GPU on the RTX 2080 Ti (no offload needed);
  warm generation is ~57 s (a cold first run is ~120 s incl. CUDA warmup). AnimateDiff-Lightning is a **4-step**
  distilled model, so keep `-Steps` at 4 (or 8) and `-Guidance` near 1.0.
- The clip is written to `runtime/artifacts/<invocation_id>/video.<mp4|gif>`; its absolute path, format, codec,
  frame count, fps, duration, bytes, and sha256 are in `result.video`. `result.motion` reports how much the
  frames actually move.
- **MP4** uses the present `ffmpeg` (H.264, yuv420p); **GIF** uses Pillow. No new library is installed.
- A blank / static / failed generation is flagged to the review queue (`verify_generation`,
  `flagged_by:"gen.video"`).
- The clip is **silent** (no audio track) — pair with `gen.music` (#24) / `gen.audio` (#22) if sound is wanted.
