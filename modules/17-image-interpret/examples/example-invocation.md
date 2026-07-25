# image.interpret — example invocation

## Describe a photo (default mode for a file input)

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile C:\Users\just_\Pictures\photo.jpg -Mode describe
```

## Ask a question about an image (VQA)

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\chart.png -Prompt "What is the overall trend, and what is the highest value?"
```

## Interpret the live screen (composes capture.screen, Module 6)

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -Capture -Mode screen
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -Capture -CaptureInputsJson '{"target":"window","title":"*Settings*"}' -Prompt "What options are shown?"
```

## Downscale a huge screenshot first (composes image.util, Module 15)

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\4k-screenshot.png -MaxDimension 1280 -Prompt "What error dialog is shown?"
```

## InputsJson form (all parameters in one object)

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputsJson '{"input":"ui.png","prompt":"Summarize the visible text and controls.","max_tokens":300,"temperature":0.2}'
```

## Notes

- Resolves the VLM from `..\07-model-gateway\models.json` (`type=vlm`, default `vlm.qwen2p5-vl-3b`) and the
  staged `llama-server` engine; override with `-Model`/`-Tier` or `-Registry`/`-ModelPath`/`-MmprojPath`/
  `-EnginePath`.
- Emits the `lifeorch.skill.result/0.1` envelope on stdout; writes `interpret.json`, `interpret.md`,
  `server.out.log`, `server.err.log`, `result.json` under `runtime/artifacts/<invocation_id>/`.
- `parallel_safe:false` — it starts a `llama-server` bound to a loopback port + the GPU; run one at a time.
- A low-confidence / refusal / empty interpretation is flagged to the review queue
  (`flagged_by:"image.interpret"`, `requested:"verify_interpretation"`).
- `examples/example-result.json` is a real seam-mode envelope (paths shown as representative Windows paths).
```
