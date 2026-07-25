# image.index -- example invocations

## 1. Metadata + hashes only (the deterministic default)

```powershell
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\photo.jpg
```

Runs `image.util meta` only. `confidence: null`, empty `model_provenance`. Produces `index.json` + `index.md` with
`format`/`mode`/dimensions + `sha256`/`pHash`/`dHash`.

## 2. Full fusion (`-All`)

```powershell
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\photo.jpg -All
```

Runs image.util (meta+hash) + ocr.layout + detect.objects + image.interpret. Envelope `confidence` = the minimum of the
three stochastic child confidences; `model_provenance` aggregates all three (each entry tagged with its `stage`). The
children's review flags are redirected to `runtime/artifacts/<id>/child_review.jsonl`; the canonical `review_queue.jsonl`
is untouched.

## 3. Selective stages + VQA + a downscale bound

```powershell
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\chart.png -Detect -Interpret -Prompt "What is the trend in this chart?" -MaxDimension 1280
```

`-MaxDimension 1280` is passed through to detect + interpret (they downscale then rescale boxes back to the original);
`image.util` still hashes the original.

## 4. Index the live screen

```powershell
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -Capture -All -InterpretMode screen
```

Captures the primary monitor **once** via `capture.screen` and feeds that PNG to every stage (`input.source: "capture"`).

## 5. Generic `InputsJson`

```powershell
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputsJson '{"input":"scan.png","ocr":true,"detect":true,"classes":["person","car"]}'
```

## Through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"input":"photo.jpg","all":true}'
```
