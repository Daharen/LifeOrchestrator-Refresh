# Work Order: Object Detection (`detect.objects`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 16 session, 2026-07-25) ·
**Roadmap entry:** `MODULE_ROADMAP.md#16`

### Problem being solved
The perception block can OCR text (`ocr.layout`, #14) and do deterministic image plumbing (`image.util`,
#15), but nothing tells an agent **what objects are in an image and where**. `detect.objects` closes that:
one image in → a list of `{class, box, confidence}` with a **real per-detection score**, so downstream
skills (screen understanding, indexing #18, video #19–22) can reason about scene contents.

### Immediate practical use
A local or frontier agent points this at a photo or a screenshot (`-Capture`) and gets bounded, labeled
regions with confidences — to route/crop/annotate, to answer "is there a person/car/… here", or to feed
`image.index` (#18). Cheap, local, CPU-only, parallel-safe.

### Explicit scope (in)
- Detect objects in **one** image → `detections[{index,class_id,class,score,low_confidence,box{x,y,width,height}}]`.
- **Real** per-detection confidence (YOLOX objectness × class prob), overall/mean/min, per-detection
  `low_confidence` marking.
- Staged **ONNX** detector via **onnxruntime**, resolved from `models.json` (`type=detector`), decoupled
  from the gateway `wired` gate. Default `detect.yolox.nano` (COCO-80, Apache-2.0).
- CPU execution provider by default (`parallel_safe`); `-Provider cuda|dml` opt-in.
- Optional COCO class filter; score/NMS/max-detections controls.
- **Sixth review-queue producer**: below-threshold best score → `verify_detections`; no objects on a
  non-empty image → `verify_no_objects`.
- Compose **capture.screen** (#6) via `-Capture`; compose **image.util** (#15) via `-MaxDimension`
  (downscale-then-rescale-boxes).
- Artifacts `detect.json` / `detect.md`; contract-valid `lifeorch.skill.result/0.1` envelope.
- Dual-mode/OS-portable test harness green on the cloud box before shipping; live via the executor.

### Non-goals (out — do NOT build)
- Annotated/overlay output image (needs an `image.util` draw op — D-0024 follow-on).
- Batch/directory; segmentation masks; oriented/rotated boxes; pose/keypoints.
- Open-vocabulary / VLM detection (that is `image.interpret`, #17).
- Object tracking across frames (#20); video (#19–22).
- Making GPU the default; a warm/persistent detector worker.

### Dependencies
- Modules: 1 (contract/wrapper), 7 (registry `models.json`), 6 (capture.screen, only `-Capture`),
  15 (image.util, only `-MaxDimension`). Tools/models: `detect.yolox.nano` (new registry entry).
  Contract features: `confidence`, `model_provenance`, review queue.

### Skill contract requirements
- `skill_id=detect.objects`, `name`, `version 0.1.0`, `determinism=mixed`, `parallel_safe=true`,
  `batch=false`, `streaming=false`.
- `result` = object (see Inputs/outputs). `confidence` populated (best detection score; 0.1 sentinel when
  empty). `model_provenance` = one entry (model/engine/provider/timings/detection_count). Artifact kinds:
  `json`, `markdown`.

### Inputs and outputs
- **Inputs:** `input` (image; required unless `capture`), `model`/`tier`, `score_threshold` (0.25),
  `confidence_threshold` (0.5), `nms_threshold` (0.45), `max_detections` (100), `classes[]`, `provider`
  (cpu), `max_dimension`, `max_review_detections` (25), `min_image_pixels` (1), `capture`,
  `capture_inputs`, plus path overrides. `-InputsJson` mirror.
- **Outputs:** `result{input,image,model,params,preprocess,detection_count,class_summary,detections[],
  confidence{overall,mean,min,low_confidence_count,reason},review,detect}`. Files `detect.json`,
  `detect.md`, `result.json` (+ `detect_args.json`, `detect_meta.json`, `worker.log`, `stderr.txt`;
  `capture/…`, `image_util/…` when composed).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `detect.json`, `detect.md`, `detect_args.json`,
  `detect_meta.json`, `worker.log`, `result.json`, `stderr.txt` (+ `capture/`, `image_util/`).

### Proposed implementation
- **Language:** Python worker (`detect_worker.py`, onnxruntime + Pillow + numpy) under the **system python**
  + a **pwsh-7 wrapper** (`Invoke-DetectObjects.ps1`) with a **meta-file hand-off** — the D-0021 pattern in
  its ONNX variant, mirroring `image.util`. **Why:** onnxruntime/vision is a Python ecosystem; CPU inference
  is deterministic + portable (so the real worker runs on the cloud pre-ship gate); no exclusive resource →
  parallel-safe. Reuses the `image.util`/`ocr.layout` scaffolding (Has/Prop/Get-Sha256Hex/InputsJson-merge/
  structured errors/review producer/child-skill compose).
- YOLOX: letterbox-416 (pad 114, BGR, raw 0–255, CHW) → onnxruntime → decode strides {8,16,32} →
  `obj×cls` → class-aware NMS → boxes to original pixels.

### External tools or models
- **onnxruntime** (system python has onnxruntime-gpu 1.17.1 + directml 1.17.1 — `detect-001`/`m16-probe-001`),
  **Pillow**, **numpy** — all present in the system python (no install).
- **detect.yolox.nano**: YOLOX-Nano ONNX (416×416, COCO-80), Apache-2.0, staged to
  `F:\...\_pending-model-storage\detector\yolox-nano\yolox_nano.onnx` (~3.66 MB). `detect.yolox.tiny`
  declared as a drop-in tier.

### Installation steps
- Download `yolox_nano.onnx` (GitHub release, Apache-2.0) on the cloud box; ship byte-exact to the repo;
  executor copies it to F: and verifies sha256 (`m16-probe-001`). Register additively in `models.json`
  (`defaults.detector`, `tiers.detector`, `detect.yolox.nano`/`detect.yolox.tiny`); re-verify Module 7 28/28.

### Tests
- **Direct/cloud gate:** `tests/Invoke-DetectObjectsTests.ps1 -PythonPath <cloud py> -ModelPath <onnx>` runs
  the real wrapper→real worker on the committed `dog.jpg` (deterministic). Asserts manifest flags, detection
  correctness (finds a dog, boxes in-bounds, real scores), class filter, score-floor monotonicity, both
  review paths, the image.util downscale composition, five error paths, and the Module 1 wrapper.
- **Through the executor:** same harness live (system python, model from registry on F:) + the Windows-only
  capture.screen composition + a real-registry smoke.

### MVP acceptance criteria
- Manifest schema-valid; `determinism=mixed`, `parallel_safe=true`, `batch/streaming=false`.
- Live detection on `dog.jpg`: ≥3 detections incl. `dog`, integer boxes within image bounds, scores in
  (0,1], envelope `confidence` = best score, provenance engine `onnxruntime`.
- Both review producers fire correctly (`verify_detections`, `verify_no_objects`) with valid items.
- image.util `-MaxDimension` composition downscales and reports boxes in original space; capture composition
  produces `source=capture`.
- Error paths return schema-valid error envelopes (`input_not_found`, `model_file_not_found`,
  `registry_not_found`, `model_not_found`).
- Green on the cloud pre-ship gate **and** live via the executor; no orphaned processes.
- `models.json` additive; Module 7 re-verified 28/28.

### Manual verification procedure
- Run `-InputFile` on a real photo; open `detect.md`; confirm the classes/boxes match the image. Run
  `-Capture` and confirm it detects on-screen windows.

### Registry updates
- `TOOL_MODEL_REGISTRY.md`: add YOLOX-Nano/-Tiny detectors + the onnxruntime detector runtime.

### State updates
- `CURRENT_STATE.md`, `MODULE_ROADMAP.md#16`, `DECISION_LOG.md` (D-0025), `REVIEW_QUEUE.md` (sixth producer),
  `models.json`. Note the image.util dpi JSON-safety fix surfaced by this module (Module 15 re-verified 48/48).

### Known follow-on work
- Overlay/annotated image (needs image.util draw op); batch/directory; larger YOLOX tiers / RT-DETR; a VLM
  open-vocab detector (#17); GPU/warm-worker; calibrated confidence; tracking (#20).

### STOP conditions
- Scope beyond the "Explicit scope" list. MVP acceptance met → stop; do not start Module 17.
