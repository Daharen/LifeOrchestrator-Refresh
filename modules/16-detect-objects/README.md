# detect.objects — Object Detection (YOLOX / ONNX)

Third module of the image/document perception block (14–18). Detects objects in one image and returns each
as `{class, class_id, score, box{x,y,width,height}}` with a **real per-detection confidence** (YOLOX
objectness × class probability, not a heuristic), plus `model_provenance` and a review-queue hand-off for
low-confidence / empty results.

## What it does

- Runs a staged **ONNX** detector (default `detect.yolox.nano`, COCO-80, Apache-2.0) via **onnxruntime** in a
  Python worker (`detect_worker.py`) under the system python, and reads the worker's meta file
  (worker+meta hand-off — the D-0021 pattern in its ONNX/onnxruntime variant).
- Resolves the detector from `models.json` (`type=detector`), **decoupled from the gateway's `wired` gate**
  (like `ocr.layout`, D-0023).
- Default **CPU** execution provider → no port/VRAM/CUDA binding → **`parallel_safe`**.
- **Stochastic/mixed**: populates the envelope `confidence` (the best detection's score) + `model_provenance`,
  and is the **sixth review-queue producer** — a below-threshold best score → `verify_detections`
  (`low_confidence`); zero detections on a non-empty image → `verify_no_objects` (`uncategorized`).
- Composes **capture.screen** (Module 6) via `-Capture` ("detect on screen") and **image.util** (Module 15)
  via `-MaxDimension` (downscale a very large input, then rescale boxes back to original pixels).

## Pipeline (YOLOX)

Letterbox to the model's input square (pad 114, BGR, raw 0–255, CHW) → onnxruntime inference → decode the
grid/stride output (strides {8,16,32}: `xy=(raw+grid)*stride`, `wh=exp(raw)*stride`) → `score = obj × class`
→ class-aware NMS → map boxes to original pixels (÷ letterbox ratio, × any image.util downscale factor).

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\photo.jpg
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputFile .\big.png -MaxDimension 1280 -Classes person,car
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -Capture -CaptureInputsJson '{"target":"monitor","monitor":"primary"}'
pwsh -NoProfile -File .\Invoke-DetectObjects.ps1 -InputsJson '{"input":"street.jpg","score_threshold":0.4}'
```

Key parameters: `-Model`/`-Tier`, `-ScoreThreshold` (detection floor, 0.25), `-ConfidenceThreshold` (review +
low_confidence mark, 0.5), `-NmsThreshold` (0.45), `-MaxDetections` (100), `-Classes`, `-Provider`
(cpu|cuda|dml), `-MaxDimension`, `-Capture`/`-CaptureInputsJson`. See `skill.json` for the full list.

## Outputs

- `detect.json` — full structured result (model, image, params, preprocess, detections, class_summary, confidence).
- `detect.md` — a human table (class · score · box).
- `result.json` — the `lifeorch.skill.result/0.1` envelope (also emitted on stdout).
- Diagnostics: `detect_args.json`, `detect_meta.json`, `worker.log`, `stderr.txt`; `capture/` when `-Capture`;
  `image_util/` when `-MaxDimension` downscales.

## Model

`detect.yolox.nano` — YOLOX-Nano exported to ONNX (input 416×416, COCO-80), staged to
`F:\...\_pending-model-storage\detector\yolox-nano\yolox_nano.onnx`, ~3.66 MB, Apache-2.0 (Megvii YOLOX).
`detect.yolox.tiny` is declared as a more-accurate drop-in tier (`-Tier tiny`). Deterministic CPU inference:
identical detections on the cloud box (onnxruntime 1.25) and the Windows executor (onnxruntime 1.17.1)
— see `m16-probe-001`.

## Tests

`tests/Invoke-DetectObjectsTests.ps1` runs the **real** wrapper → **real** `detect_worker.py` against the
committed fixture `tests/fixtures/dog.jpg` (real-worker gate, like image.util — no mock). It is OS-portable:
the same harness is the cloud pre-ship gate (cloud python + onnxruntime, model via `-ModelPath`) and the live
Windows/executor test (system python, model from the registry on F:). The capture.screen composition is
Windows-only and runs only in the live pass.

## Not in this MVP (follow-ons)

Box-overlay/annotated image (needs an image.util draw op — see D-0024); batch/directory; segmentation/masks;
oriented boxes; a VLM open-vocabulary detector; GPU as the default provider; object tracking across frames
(Module 20). YOLOX-Tiny/-S larger tiers are a drop-in (declare + stage).
