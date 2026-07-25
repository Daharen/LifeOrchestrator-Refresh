# ocr.layout — OCR + Layout (Module 14)

Local optical character recognition for Life Orchestrator. Turns one **image** of text into the
recognized **text plus per-word pixel bounding boxes and lines in reading order**, emitting a
contract-valid `lifeorch.skill.result/0.1` envelope.

It is the first module of the image/document perception block (14–18) and the first **stochastic/mixed**
perception skill that is also **parallel-safe** (it binds no port, no VRAM, no CUDA context). It drives the
**system `Windows.Media.Ocr` engine** — zero install, native to Windows 10, `en-US` recognizer present —
and composes cleanly with `capture.screen` (Module 6) to read text straight off the screen.

## Why a PowerShell 5.1 worker

`Windows.Media.Ocr` is a WinRT API. On this machine **pwsh 7.4.6 cannot load the WinRT projection**
(confirmed by probe `m14-probe-001`), but **Windows PowerShell 5.1** can, via the classic
`System.Runtime.WindowsRuntime` `AsTask`/`Await` pattern. So the skill is a two-part unit:

- `Invoke-OcrLayout.ps1` — the pwsh-7 **wrapper**: contract, registry resolution, orchestration, envelope.
- `ocr_worker.ps1` — the Windows PowerShell **5.1 worker**: the only place the OCR engine is reachable. It
  writes a **meta file**; the wrapper reads only that (robust to any WinRT/console chatter). This is the
  Module 12 (`speech.tts`) worker+meta hand-off (D-0021), in its PowerShell-5.1 variant.

## What it does

1. Resolves the OCR engine from the model registry (`models.json`: `ocr.windows.media`, type `ocr`, engine
   `windows.media.ocr`) — registry-driven, **decoupled from the gateway's `wired` gate** (D-0020).
2. Resolves the input: an explicit `-InputFile`, or — with `-Capture` — spawns `capture.screen` (Module 6)
   to grab a monitor/window/app/region and OCRs that PNG.
3. Runs the 5.1 worker → `Windows.Media.Ocr` → words with `BoundingRect`, lines (reading order), text angle.
4. Builds `lines[]` (each with a union `bounding_rect` + its `words[]` boxes), the full `text`, counts, and
   a **legibility confidence** (per-line + overall).
5. Routes a low-confidence / no-text result to the review queue (`lifeorch.review.item/0.1`,
   `flagged_by:"ocr.layout"`), then emits the envelope with `confidence` + `model_provenance`.

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputFile .\screenshot.png
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -Capture -CaptureInputsJson '{"target":"window","title":"*Notepad*"}'
pwsh -NoProfile -File .\Invoke-OcrLayout.ps1 -InputsJson '{"input":"receipt.jpg","confidence_threshold":0.6}'
```

Wrapped (Module 1) or as an `exec.bootstrap` task package, exactly like the other skills.

Key parameters: `-InputFile` (required unless `-Capture`), `-Language` (BCP-47; default = user-profile /
first recognizer), `-Engine`/`-Model` (default `ocr.windows.media`), `-ConfidenceThreshold` (def 0.5),
`-MaxReviewLines` (def 25), `-Capture` + `-CaptureInputsJson`, plus `-Registry` / `-OcrWorkerPath` /
`-Powershell51Path` / `-CapturePath` / `-PwshPath` / `-ReviewQueuePath` overrides. Any may be passed inside
`-InputsJson`.

## Output

`result` shape (see `skill.json`): `input{path,exists,source,capture?}`, `image{width,height,text_angle}`,
`engine{id,name,engine,recognizer_language,available_languages}`, `params`, `text`, `word_count`,
`line_count`, `lines[{index,text,confidence,low_confidence,bounding_rect{x,y,width,height},
words[{text,x,y,width,height}]}]`, `confidence{overall,min_line,low_confidence_lines,reason}`,
`review{threshold,flagged_count,truncated,queue_path}`, `ocr{engine_env,runtime_ms,max_image_dimension}`.

Artifacts under `runtime/artifacts/<invocation_id>/`: `ocr.json` (`lifeorch.ocr.layout/0.1`), `ocr.md`
(human summary + per-line box/confidence table), `ocr_args.json` / `ocr_meta.json` (the worker hand-off),
`worker.log`, `result.json`, `stderr.txt`, and `capture/…` when `-Capture` ran.

## Confidence (heuristic, NOT calibrated)

`Windows.Media.Ocr` exposes **no** per-word confidence (unlike whisper's token-`p`). So `confidence` here is
a documented **legibility proxy**: the fraction of recognized words that are clean, plausible tokens
(letter/digit-bearing, sane length), mapped to `[0.1, 0.9]` per line and overall; a no-text result scores
lowest. Treat it as triage, not correctness. Results below `-ConfidenceThreshold` (default 0.5) are flagged
(`verify_ocr`); a text-free non-empty image flags `verify_no_text`. **Tesseract** (also installed) is the
natural follow-on engine for calibrated per-word confidence — declared in the registry as `ocr.tesseract`,
not wired in this MVP.

## Determinism / safety

`determinism:"mixed"` (deterministic orchestration; perception output), `parallel_safe:true` (no exclusive
resource; the only shared-state write is the append-only review queue), `batch:false`, `streaming:false`.

## Tests

`tests/Invoke-OcrLayoutTests.ps1` — dual-mode: `-UseMock` runs the **real wrapper** against a mock worker
(`tests/mock-ocr-worker.ps1` + the captured real `tests/fixtures/ocr-sample.meta.json`) and a temp registry,
validating the full parse/reading-order/confidence/review/envelope path off-Windows (the cloud pre-ship
gate); the default mode resolves the real 5.1 worker and OCRs `tests/fixtures/ocr-sample.png` on Windows/the
executor. Same assertions in both modes.

See `WORK_ORDER.md` for scope and `DECISION_LOG.md` (D-0023) for rationale.
