# image.index (Module 18)

**Fuse the image/document perception block (14-17) into one per-image record.** The capstone of the perception block
(14-18). Given one image, `image.index` runs the perception children and fuses their results into a single machine
`index.json` + a human `index.md` card:

- **`image.util` (#15) -- ALWAYS**: metadata (format/mode/dims/alpha/dpi) + `sha256`/`pHash`/`dHash` (the deterministic
  backbone; every indexed image gets meta + hashes even with no other flag).
- **`ocr.layout` (#14) -- `-Ocr`**: text + per-word/line pixel boxes + reading order.
- **`detect.objects` (#16) -- `-Detect`**: class boxes + **real** per-detection scores + a class summary.
- **`image.interpret` (#17) -- `-Interpret`**: a local-VLM free-text interpretation (caption / describe / VQA / screen).
- **`-All`** enables the three optional stages. **`-Capture`** sources the image **once** via `capture.screen` (#6).

It is an **orchestrator** and reimplements nothing: it spawns each child as a child `pwsh` process, parses its
`lifeorch.skill.result/0.1` envelope, aggregates every child's `model_provenance` (stage-tagged), and **redirects** each
child's review-queue writes to an in-artifact `child_review.jsonl`. `image.index` is **not itself a review producer** and
does not re-flag (mirrors `voice.live` #13). Children run **sequentially** (capture -> image.util -> ocr -> detect ->
interpret) to avoid VRAM/loopback-port contention from `image.interpret`.

- `determinism`: **mixed** (deterministic when only `image.util` runs; stochastic when any optional stage runs).
- Envelope `confidence` = the **minimum** confidence across the stochastic stages that actually ran (the weakest-link
  signal for the fused record), or `null` when only `image.util` ran.
- `parallel_safe`: **false** (conservatively -- can bind CUDA/VRAM + a loopback port via `-Interpret`). `batch`/`streaming`: false.

## Invocation

```powershell
# hash + metadata only (fast, deterministic, the default)
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\photo.jpg

# the full fusion (meta+hash + OCR + objects + VLM interpretation)
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\photo.jpg -All

# selective + a VQA question + a downscale bound for the heavy stages
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputFile .\chart.png -Detect -Interpret -Prompt "What is the trend?" -MaxDimension 1280

# index the live screen (captured once, fed to every stage)
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -Capture -All -InterpretMode screen

# generic InputsJson form
pwsh -NoProfile -File .\Invoke-ImageIndex.ps1 -InputsJson '{"input":"scan.png","ocr":true,"detect":true}'
```

## Inputs (named params / `InputsJson` keys)

`input`/`-InputFile` (required unless `-Capture`); `-Ocr`/`-Detect`/`-Interpret`/`-All`; `-Capture` +
`-CaptureInputsJson`; `-MaxDimension <n>` (passed to detect + interpret); `-Language` (ocr); `-Classes c1,c2` (detect
filter); `-InterpretMode caption|describe|vqa|screen` (default `describe`); `-Prompt` (interpret VQA);
`-Tier`/`-InterpretModel` (interpret model); `-ConfidenceThreshold` (passed to the stochastic children for their own
flagging); path overrides `-ImageUtilPath`/`-OcrPath`/`-DetectPath`/`-InterpretPath`/`-CapturePath`;
`-PwshPath`/`-PythonPath`/`-Powershell51Path`; `-ReviewQueuePath`; `-InputsJson`; `-ArtifactRoot`; `-InvocationId`.

## Output (`result`, schema `lifeorch.image.index/0.1`)

`input{path,source,capture}`, `image{width,height,format,mode,has_alpha,dpi,metadata}`, `hashes{sha256,phash,dhash}`,
`stages{ image_util, ocr, detect, interpret }` -- each `{ran,status,confidence,reason,ms,artifact_dir,error,+payload}`
(ocr: text/word_count/line_count/lines; detect: detection_count/class_summary/detections; interpret:
mode/text/finish_reason/completion_tokens), `summary{caption,ocr_text,ocr_word_count,top_objects[],detection_count,
stochastic_confidence_min,stages_ran,stages_ok,stages_error}`, `review{mode,child_review_path,child_review_count,
is_producer:false}`, `config{...}`. Envelope `confidence` = min stochastic child confidence; `model_provenance` =
stage-tagged aggregate of all children.

## Artifacts (`runtime/artifacts/<invocation_id>/`)

`index.json` (fused machine record), `index.md` (human card), `result.json` (envelope), `child_review.jsonl` (redirected
child flags, when any), `stderr.txt`, and per-stage sub-roots `image_util/` `ocr/` `detect/` `interpret/` `capture/`.

## Dependencies

`image.util` (#15), `ocr.layout` (#14), `detect.objects` (#16), `image.interpret` (#17), `capture.screen` (#6),
`skill.bootstrap` (#1). **No new model / no `models.json` change** -- it wires nothing new; the children own their models.

## Tests

`tests/Invoke-ImageIndexTests.ps1` -- **dual-mode / OS-portable** (mirrors #13/#16/#17):

- `-UseMock`: runs the **real** `Invoke-ImageIndex.ps1` with every child pointed at `tests/mock-child.ps1` (branches on
  the `-ArtifactRoot` leaf; canned envelopes; capture writes a real 1x1 PNG; image.util emits a real sha256; the
  stochastic children append a review item to the passed `review_queue_path`). The cloud pre-ship gate -- no GPU/models.
- default / `-Live`: resolves the real children and runs a live index over `tests/fixtures/dog.jpg` on the Windows
  executor (image.util always; `-All`; the `-Capture` compose), asserting real fusion, the child-review redirect, and no
  orphaned processes.

## Non-goals (see `WORK_ORDER.md`)

No concurrent/parallel child execution; no batch/directory; no cross-stage grounding (detection<->OCR<->caption); no
overlay image; no new perception logic; no persistence (that is `artifact.search` #23). See `DECISION_LOG.md` D-0027.
