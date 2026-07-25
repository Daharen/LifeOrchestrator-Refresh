# ocr.layout — example invocation

OCR a screenshot or scanned page (words + boxes + reading order):

```powershell
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputFile 'C:\Users\just_\Pictures\receipt.png'
```

Read text straight off the screen by composing `capture.screen` (Module 6) — no temp file:

```powershell
# a specific window
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -Capture `
    -CaptureInputsJson '{"target":"window","title":"*Notepad*"}'

# the primary monitor
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -Capture
```

Via `-InputsJson` (the generic channel the wrapper uses), lowering the confidence bar and flagging a poor
scan to the review queue:

```powershell
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Downloads\\fax-page-3.jpg",
  "language": "en-US",
  "confidence_threshold": 0.6
}'
```

Through the Module 1 wrapper:

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
    -InputsJson '{"input":"tests/fixtures/ocr-sample.png"}'
```

Through the executor: submit a task package whose `task.ps1` calls `Invoke-OcrLayout.ps1` and read the
envelope from `runtime/completed/<task_id>/stdout.txt`.

The envelope goes to **stdout** (single JSON object); diagnostics go to **stderr**. The structured result is
also written as `ocr.json` / `ocr.md` under `runtime/artifacts/<invocation_id>/`. See `example-result.json`
for a real result.
