# Work Order: OCR + Layout (`ocr.layout`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 14 build session) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md#14`

### Problem being solved
The image/document perception block (Modules 14–18) needs a reliable, local **OCR** primitive: turn one
image of text (a screenshot, a scanned page, a photographed document) into the **recognized text plus
per-word bounding boxes and reading order**, entirely on this machine and cheaply. It is the first
perception module and the entry point every later perception module builds on (`image.index` #18 will
integrate it; `observe.broker` #25 will route screen-text questions to it). Like `speech.stt` it is a
**stochastic/mixed** perception skill: it must populate `confidence` + `model_provenance` and route
low-confidence results to the review queue.

### Immediate practical use
Any agent (frontier or local) that has an image and needs its text with positions: reading text off a
screenshot or a UI region that exposes no UIA tree (Unity/game/canvas — the exact gap `capture.screen`
#6 was built for), extracting a document/receipt/label's text + layout, or feeding OCR text to
`classify.batch`/`review.processor`. Callable this week directly, wrapped, or through the executor —
and, composed with `capture.screen`, as a one-shot "read the text on my screen right now."

### Probe result that grounds this design (`m14-probe-001`, 2026-07-25)
Probe-first, before any code (per the discipline; do **not** assume an OCR engine exists):
- **Windows.Media.Ocr is present and works** — a Windows PowerShell **5.1** (5.1.19041.6456) worker using
  the WinRT reflection-`AsTask`/`Await` pattern OCR'd a generated fixture to `"HELLO WORLD The quick
  brown fox 12345"` (100% correct incl. digits) with **per-word bounding boxes**, **line grouping
  (reading order)**, and `TextAngle`, in **74 ms**. `MaxImageDimension=10000`; recognizer language
  `en-US` installed. Zero install, no admin, native to Windows 10.
- **pwsh 7.4.6 cannot load the WinRT projection** ("RuntimeException") → the skill must run OCR in a
  **PowerShell 5.1 worker** and hand back a **meta file** (the D-0021 worker+meta pattern, PS-5.1 variant).
- **Tesseract IS installed** (`C:\Program Files\Tesseract-OCR\tesseract.exe`) — a real alternative that
  additionally yields calibrated per-word confidence. Registered as a **declared, not-yet-wired** second
  engine; not built in this MVP (keeps scope to one engine, per the one-module rule).
- No Python OCR libs (easyocr/paddleocr/rapidocr/pytesseract) in either venv; `onnxruntime` + `PIL` present.

### Explicit scope (in)
- One input image (png/jpg/bmp/tif/gif — whatever `BitmapDecoder` accepts) → one OCR result. Resolve the
  OCR engine from `models.json` (`ocr.windows.media`, type `ocr`, engine `windows.media.ocr`) — registry-
  driven, **decoupled from the gateway's `wired` gate** (mirrors D-0020: the entry stays `wired:false`
  for `model.gateway`, which runs `type=llm` only).
- Run **Windows.Media.Ocr** in a Windows PowerShell 5.1 worker (`ocr_worker.ps1`); the pwsh-7 wrapper
  (`Invoke-OcrLayout.ps1`) reads the worker's **meta file** (robust to any WinRT/console chatter) and
  builds the contract envelope.
- Emit **words with pixel bounding boxes**, **lines in reading order** (engine order; each line = union
  box + its words), the full `text`, `word_count`, `line_count`, `text_angle`, and `image{width,height}`.
- **Confidence** = a documented OCR-legibility heuristic (Windows.Media.Ocr exposes **no** per-word
  confidence, unlike whisper token-`p`): per-line and overall, from the fraction of recognized words that
  are clean/plausible tokens; a no-text result scores lowest. **NOT** calibrated correctness.
- **`model_provenance`** = one entry (engine id/name, recognizer + available languages, OS build, image
  dims, word/line counts, text angle, runtime).
- **Review-queue producer** (the **fifth**, after `model.gateway`/`classify.batch`/`speech.stt`/
  `speech.tts`): if `word_count==0` from a non-trivial image → one `verify_no_text` item (silent-fail
  guard); else if overall `confidence < -ConfidenceThreshold` (default 0.5) → one page-level `verify_ocr`
  item carrying the worst lines (bounded by `-MaxReviewLines`, default 25). `flagged_by:"ocr.layout"`.
- **Compose `capture.screen` (Module 6)** as an optional input source: with `-Capture` (and an optional
  `-CaptureInputsJson` describing monitor/window/app/region) and no `-InputFile`, spawn `capture.screen`
  as a child pwsh, take its PNG artifact, and OCR that — the same child-spawn pattern as
  `speech.stt`→`audio.ingest`. "OCR the screen" without a temp file.
- `-Language` (BCP-47; default = the engine's user-profile / first available recognizer language).
- Standard contract surface: `-InputsJson` generic args, `$PSScriptRoot/runtime/artifacts/<id>/`, absolute
  artifact paths, envelope to stdout / diagnostics to stderr, exit 0 on any valid envelope.

### Non-goals (out — do NOT build)
- A **second OCR engine** (Tesseract) — declared in the registry as `ocr.tesseract` for a follow-on; the
  `-Engine`/`-Model` seam exists but only `windows.media.ocr` is wired this module. Tesseract gives real
  per-word confidence and multi-language and is the natural next engine + calibrated-confidence source.
- Image pre-processing (resize / crop / deskew / binarize / denoise) → Module 15 (`image.util`); an image
  **larger than `MaxImageDimension` (10000 px)** returns a structured `image_too_large` (downscale-then-
  rescale-boxes is a documented follow-on that pairs with #15).
- A drawn **overlay PNG** of the boxes (nice for verification) → follow-on (cheap once #15 exists).
- Object/region **detection**, captioning, VQA, screen *interpretation* → Modules 16/17.
- **Batch / directory / multi-page PDF** OCR (one image per invocation) → a follow-on / #18 integrates.
- Multi-column reading-order reflow beyond the engine's own line order (single-column is exact; multi-
  column is a documented heuristic follow-on).
- Wiring OCR into `model.gateway` (leave `ocr.windows.media` `wired:false`; the skill reads the entry itself).

### Dependencies
- Modules: 1 (`skill.bootstrap` contract + wrapper); 6 (`capture.screen`, spawned as a child only when
  `-Capture`). No Module-10-style hard dependency — file-driven is the default path.
- Tools/models: **Windows.Media.Ocr** (system WinRT API; `en-US` recognizer present) via **Windows
  PowerShell 5.1** (`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`). No model file, no GPU,
  no network. (Registry also declares `ocr.tesseract` → `C:\Program Files\Tesseract-OCR\tesseract.exe`.)
- Contract features: `confidence`, `model_provenance`, artifacts[], review-queue producer.

### Skill contract requirements
- `skill_id:"ocr.layout"`, `name:"OCR + Layout"`, `version:"0.1.0"`, `determinism:"mixed"`,
  `parallel_safe:true` (CPU/GPU-light system API — binds no port/VRAM/CUDA context; the first genuinely
  parallel-safe perception skill; the only shared-state write is the append-only review queue),
  `batch:false`, `streaming:false`.
- Result `result` shape (below); `confidence` populated (0.0–1.0); `model_provenance` populated; artifact
  kinds: json / markdown.

### Inputs and outputs
- **Inputs:** `input` (string, image path; required unless `capture`), `language` (BCP-47, def ""=auto),
  `engine`/`model` (def `ocr.windows.media`), `confidence_threshold` (def 0.5), `max_review_lines` (def 25),
  `capture` (bool, def false) + `capture_inputs` (object, capture.screen inputs), `min_image_pixels`
  (def 1 — the no-text guard only fires for a real image), `registry`, `ocr_worker_path`,
  `powershell51_path`, `capture_path`, `pwsh_path`, `review_queue_path`.
- **Outputs — `result`:**
  `{ input{path,exists,source,capture?}, image{width,height,text_angle}, engine{id,name,engine,
     recognizer_language,available_languages}, params{language,confidence_threshold}, text, word_count,
     line_count, lines[{index,text,confidence,low_confidence,bounding_rect{x,y,width,height},
     words[{text,x,y,width,height}]}], confidence{overall,min_line,low_confidence_lines,reason},
     review{threshold,flagged_count,truncated,queue_path}, ocr{engine_env,runtime_ms} }`

### Artifact structure
- `runtime/artifacts/<invocation_id>/`
  - `ocr.json` — `lifeorch.ocr.layout/0.1` full structured result (text + lines + words + boxes).
  - `ocr.md` — human summary (text; a table of lines with box + per-line confidence + ⚠ low-conf markers).
  - `ocr_args.json`, `ocr_meta.json` — the worker hand-off (args in, meta out).
  - `worker.log` — worker stdout/stderr (diagnostics).
  - `capture/<id>/…` — only when `-Capture` ran (the `capture.screen` artifacts, incl. the source PNG).
  - `result.json`, `stderr.txt`.

### Proposed implementation
- **Language:** PowerShell — a pwsh-7.4.6 **wrapper** (`Invoke-OcrLayout.ps1`, contract + orchestration)
  driving a Windows PowerShell **5.1 worker** (`ocr_worker.ps1`, the only place WinRT is reachable on this
  box). Meta-file hand-off (D-0021), PS-5.1-worker variant. Reuse Module 1's `SkillContract.psm1` +
  `Invoke-Skill.ps1`; mirror `speech.stt`'s helper set (`Has`/`Prop`/`Get-Sha256Hex`/`Resolve-RepoRoot`)
  and its InputsJson-merge / structured-error / review-producer scaffolding; mirror `speech.stt`→
  `audio.ingest`'s child-`pwsh` spawn for the optional `capture.screen` compose.
- Flow: merge `-InputsJson` → resolve engine from `models.json` → resolve input (file, or spawn
  `capture.screen` when `-Capture`) → resolve PS 5.1 + worker → write `ocr_args.json` → run worker →
  read `ocr_meta.json` → build lines/words/boxes + reading order + confidence → write artifacts →
  append review item(s) → emit envelope (exit 0).
- Worker: read args JSON → load WinRT (`System.Runtime.WindowsRuntime` `AsTask`/`Await`) → create
  `OcrEngine` (by `-Language`, else `TryCreateFromUserProfileLanguages`, else first
  `AvailableRecognizerLanguages`) → `BitmapDecoder` the image → guard `MaxImageDimension` → `RecognizeAsync`
  → write `ocr_meta.json` (`ok` + lines/words/boxes/angle/dims/languages), or `{ok:false,error_code,error}`.

### External tools or models
- Windows.Media.Ocr (system) — verified live 2026-07-25 (`m14-probe-001`): words + boxes + lines + angle,
  `MaxImageDimension=10000`, `en-US` recognizer, ~74 ms on a 700×220 fixture. Reached only via PS 5.1.
- Tesseract 5 at `C:\Program Files\Tesseract-OCR\tesseract.exe` — **declared** (`ocr.tesseract`), not wired here.

### Installation steps
- None to install — Windows.Media.Ocr + the `en-US` recognizer + PS 5.1 are already present (probe
  `m14-probe-001`). Register the engine(s) in `models.json` (additive `defaults.ocr`/`tiers.ocr` + two
  `type:"ocr"` model entries, both `wired:false`) and the skill in `TOOL_MODEL_REGISTRY.md`.

### Tests
- **Cloud pre-ship (off-machine):** cloud pwsh 7.4.6 AST-parse-checks every `.ps1`; a dual-mode harness
  (`-UseMock`) runs the **real wrapper** against a **mock worker** (`tests/mock-ocr-worker.ps1`) that emits
  a **captured real meta** (`tests/fixtures/ocr-sample.meta.json`, from the probe) + a temp registry — so
  the full parse / reading-order / confidence / review-write / envelope path runs with no Windows/WinRT.
- **Direct + through the executor (Windows):** manifest validity; a **live** OCR of a committed fixture
  (`tests/fixtures/ocr-sample.png`) → assert text contains the known words, `word_count`/`line_count`≥
  expected, each word has a `bounding_rect`, lines in reading order, overall `confidence` in (0,1],
  `model_provenance[1]` engine `windows.media.ocr`, `ocr.json`/`ocr.md` artifacts with sha256; a forced
  high threshold → a valid `ocr.layout` review item; the optional `-Capture` compose (structural: a
  `capture.screen` child runs and its PNG is OCR'd, status ok); error paths (`input_not_found`,
  `image_too_large`, `engine_not_found`); the Module 1 wrapper; no orphaned processes.

### MVP acceptance criteria
- Schema-valid `lifeorch.skill.result/0.1` envelope, `determinism:"mixed"`, `confidence` in [0,1],
  `model_provenance[1]`.
- Live fixture OCR is correct: `text` contains the fixture's known words; every word carries an integer
  pixel `bounding_rect`; lines are returned in reading order; `text_angle` present.
- `ocr.json` + `ocr.md` produced and hashed; `ocr.json` sha256 matches its artifact entry.
- A forced high `-ConfidenceThreshold` appends a valid `lifeorch.review.item/0.1` (`flagged_by:"ocr.layout"`,
  `requested:"verify_ocr"`); a text-free image yields `verify_no_text`.
- The `-Capture` path runs `capture.screen` and OCRs its output (status ok/partial).
- All tests pass through the executor (exit 0); the cloud pre-ship harness is green first.

### Manual verification procedure
- Submit an executor task OCR'ing `tests/fixtures/ocr-sample.png`; open `ocr.md` and confirm the text +
  the per-line boxes; open `ocr.json` and confirm each word's `bounding_rect`. Optionally run with
  `-Capture` and confirm it read text off the live screen.

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add an `ocr.layout` skill entry to `TOOL_MODEL_REGISTRY.md`; add a Windows.Media.Ocr runtime line and a
  Tesseract (declared) line. Add `defaults.ocr`/`tiers.ocr` + `ocr.windows.media` (default) and
  `ocr.tesseract` (declared) model entries to `models.json` (additive; both `wired:false` — re-verify the
  gateway stays green).

### State updates
- Update `CURRENT_STATE.md` (Module 14 complete, active module none), `MODULE_ROADMAP.md` (#14 MVP
  complete), `REVIEW_QUEUE.md` (fifth producer wired), a new `DECISION_LOG.md` D-entry.

### Known follow-on work
- Wire **Tesseract** as a second engine (calibrated per-word confidence, multi-language) behind the
  `-Engine` seam; a **calibrated/semantic** confidence.
- `MaxImageDimension` **downscale-then-rescale-boxes** (pairs with `image.util` #15); a drawn **overlay
  PNG** of the boxes; multi-column reading-order reflow.
- **Batch / directory / PDF-page** OCR; word-level confidence artifacts; language auto-detect / multi-lang.
- Deeper `capture.screen` composition (region-follow, per-window OCR loop) once #18/#25 exist.

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above (e.g. building the Tesseract engine or an overlay).
- Windows.Media.Ocr / PS 5.1 resolution fails and fixing it is non-trivial (stop, report).
- The contract lacks something this module needs (stop, propose the change, do not freelance).
- MVP acceptance is met — **stop; do not start Module 15.**
