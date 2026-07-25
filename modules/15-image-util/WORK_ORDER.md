# Work Order: Image Utilities (`image.util`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md#15`

### Problem being solved
Perception and downstream skills keep needing the same small, boring image operations and have nowhere
deterministic to get them: resize an image, crop a region, convert a format, read its dimensions/mode/EXIF,
hash it (exactly and perceptually), or split it into tiles. Today `ocr.layout` (Module 14) returns a
structured `image_too_large` when an input exceeds the engine's `MaxImageDimension` (10000 px) because
nothing can downscale it and report the scale factor to rescale boxes; and there is no primitive to draw or
compose. This module closes the "cheap, deterministic pixel plumbing" gap for the whole perception block
(14-18) and beyond, running locally on the machine with what is already installed.

### Immediate practical use
Called this week by a human or a frontier/local agent to: downscale a huge screenshot before OCR (and get
back `scale_x`/`scale_y` so word boxes can be rescaled), make a JPEG/WebP thumbnail of a PNG, crop the
center or a pixel rectangle out of a capture, read an image's real dimensions/format/EXIF without opening an
app, dedupe near-identical images by perceptual hash, or tile a large page into pieces. It is the deterministic
image counterpart to `audio.ingest` (Module 10) in the audio track.

### Explicit scope (in)
- **meta / probe** - always compute and return `format, mode, width, height, has_alpha, dpi, EXIF-lite`, plus
  content hashes for every invocation (cheap, universally useful).
- **hash** - `sha256` (exact file content) + a perceptual `phash` (DCT, 64-bit) + `dhash` (64-bit) for
  similarity/dedup. Deterministic and stable across Pillow/numpy versions (confirmed by `m15-probe-001`).
- **resize** - modes `fit` (scale within a box, keep aspect, no upscale by default), `fill` (cover + center-crop
  to exact box), `exact` (ignore aspect); or a single `max_dimension` (longest side <= N - the OCR downscale
  case). Result reports `original`, `result`, and `scale_x`/`scale_y`.
- **crop** - an explicit pixel rectangle `(x,y,crop_width,crop_height)`, a `normalized` (0..1 fraction) rectangle,
  or a named `region` (`center|top|bottom|left|right|top-left|...`) sized by `region_fraction`. Clamped to bounds.
- **convert** - re-encode to `png|jpg|webp|bmp|tiff` with `quality` (jpg/webp); alpha flattened to white for
  formats without alpha.
- **tile / split** - a `cols x rows` grid or a fixed `tile_width x tile_height` with optional `overlap`; each tile
  written as its own image artifact (bounded count).
- **similarity** - `compare_to` a second image; returns pHash/dHash Hamming distances + a `similarity` score.
- One image in -> zero or more image artifacts out + one structured result. `determinism:"deterministic"`,
  `confidence:null`, `parallel_safe:true`, `batch:false`.

### Non-goals (out - do NOT build)
- OCR (#14), object detection (#16), captioning/VQA/VLM interpretation (#17), image indexing (#18), video (#19+).
- **Batch / directory / glob** processing (one image per invocation for the MVP - a scoped follow-on).
- **Draw / annotate / overlay** (rectangles, text, the `ocr.layout` box-overlay PNG) - a follow-on op; this
  module unblocks it but does not build it here.
- Animated-GIF/multi-frame editing beyond reading `n_frames` and operating on frame 0.
- ICC color management, denoise/sharpen/filters, rotate/flip/EXIF-auto-orient (cheap follow-ons), and any OCR
  wiring (the `ocr.layout` downscale + box-overlay compositions are *documented here* but built in a later
  `ocr.layout` follow-on, not now).

### Dependencies
- Modules: Module 1 (`skill.bootstrap` - `lib/SkillContract.psm1` validators + `Invoke-Skill.ps1` wrapper).
  No runtime dependency on other modules (unlike `speech.stt`/`ocr.layout`, it composes nothing).
- Tools/models: **Pillow (PIL) + numpy under the system python** - NOT a `model.gateway` model, so **no
  `models.json` change and no Module 7 re-verify** (it is a tool, like `ffmpeg` for `audio.ingest`). Registered
  in `TOOL_MODEL_REGISTRY.md` as a tool.
- Contract features: standard envelope; `confidence:null`, empty `model_provenance`, artifact kinds `json`,
  `markdown`, `image`.

### Skill contract requirements
- `skill_id="image.util"`, `name="Image Utilities (Pillow)"`, `version="0.1.0"`, `determinism="deterministic"`,
  `parallel_safe=true`, `batch=false`, `streaming=false`.
- `result` shape per "Inputs and outputs" below; `confidence=null`; `model_provenance=[]`; artifacts:
  `image.json` (json), `image.md` (markdown), and each produced image (`image`).

### Inputs and outputs
- **Inputs** (named params OR `-InputsJson`; named wins on conflict):
  - `input` (string, required) - source image path.
  - `op` (string, default `meta`) - `meta|resize|crop|convert|tile|similarity`.
  - resize: `width`,`height` (int), `mode` (`fit|fill|exact`, default `fit`), `max_dimension` (int),
    `resample` (`lanczos|bicubic|bilinear|box|hamming|nearest`, default `lanczos`), `allow_upscale` (bool, default false).
  - crop: `x`,`y`,`crop_width`,`crop_height` (int), `normalized` (bool - treat those as 0..1 fractions),
    `region` (named), `region_fraction` (0..1, default 0.5).
  - convert/output: `format` (`png|jpg|jpeg|webp|bmp|tiff`; default = keep input format), `quality` (1..100, default 90),
    `output_name` (base name for outputs).
  - tile: `tile_cols`,`tile_rows` (grid) OR `tile_width`,`tile_height` (fixed); `tile_overlap` (px, default 0).
  - similarity: `compare_to` (path).
  - hashing: `hash_size` (int, default 8 -> 64-bit), `no_perceptual_hash` (bool, sha256 still computed).
  - overrides: `python_path`, `image_worker_path`; plus `-ArtifactRoot`, `-InvocationId`.
- **Outputs** (`result`): `{ input{path,exists,bytes,sha256,format,mode,width,height,has_alpha}, op, params{...},
  metadata{format,mode,width,height,has_alpha,dpi,n_frames,exif{...}}, hashes{sha256,phash,dhash,hash_bits},
  outputs[{path,format,mode,width,height,bytes,sha256}], resize{mode,requested,original,result,scale_x,scale_y}|null,
  crop{requested,applied}|null, tile{mode,cols,rows,tile_width,tile_height,overlap,count,tiles[...]}|null,
  similarity{compare_to,hash_bits,phash_a,phash_b,hamming_phash,dhash_a,dhash_b,hamming_dhash,similarity}|null,
  runtime_ms, worker{python,pillow_version,numpy_version} }`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` -> `image.json` (structured result), `image.md` (human summary),
  `image_args.json` + `image_meta.json` (worker hand-off), `worker.log`, `result.json`, `stderr.txt`, and the
  produced image file(s): `<name>.<ext>` (resize/crop/convert) or `<name>_tile_r{r}_c{c}.<ext>` (tile).

### Proposed implementation
- **Language:** a **Python worker** (`image_worker.py`, Pillow + numpy) + a **PowerShell 7 wrapper**
  (`Invoke-ImageUtil.ps1`) - the D-0021 worker+meta hand-off pattern (as `speech.tts`), here **deterministic**.
  Pillow is the richest, most portable image library and is already installed; numpy (a Pillow/cv2 dependency)
  gives a clean DCT for pHash. Per the language policy: Python for the imaging ecosystem, PowerShell owns the
  contract envelope.
- The wrapper validates inputs, resolves the python interpreter (`-PythonPath` -> known system Python312 ->
  `python`/`py` on PATH, first one that imports PIL), writes an args JSON, spawns the worker, reads its
  **meta file** (never stdout - robust to any library chatter), then builds the envelope + `image.json`/`image.md`
  and hashes every artifact. The worker does all pixel work and writes `image_meta.json` on success and failure.
- **Why the system python** (`C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe`): PIL 10.2 +
  numpy 1.26, CPU-only (so genuinely `parallel_safe`, no CUDA/venv binding), and NOT tied to the speech venv.
  The speech venv (PIL 12.2) is a documented fallback and produces **identical** perceptual hashes (`m15-probe-001`).

### External tools or models
- **Pillow (PIL) 10.2.0 + numpy 1.26.4** under the system python - **verified present and round-tripping**
  png/jpg/webp/bmp/tiff + EXIF + LANCZOS + numpy-DCT pHash by `m15-probe-001` (2026-07-25). No install needed.
  Check `TOOL_MODEL_REGISTRY.md` before assuming; this module adds the tool entry.

### Installation steps
- None on the target machine (Pillow + numpy already present in the system python). For the off-machine gate:
  `pip install --break-system-packages Pillow numpy` on the cloud Linux box + pwsh 7.4.6 (already installed).

### Tests
- **Direct / off-machine gate (cloud):** because Pillow is portable AND version-stable (unlike the WinRT/CUDA
  engines that forced mock workers in M11/12/14), the harness runs the **real** `image_worker.py` under a
  resolved python - the same "green on the cloud box before shipping" guarantee as `audio.ingest`'s real-ffmpeg
  gate, but exercising the actual worker. `Invoke-ImageUtilTests.ps1 -PythonPath <python>` generates its
  fixtures via Pillow at runtime (no committed binary) and asserts a schema-valid envelope for every op.
- **Through the executor (Windows):** submit a task package running the identical harness against the system
  python; assert `result.json` + artifacts. A real-registry-free smoke run OCRs nothing - it just proves live
  Pillow ops on the real machine.
- Coverage: manifest flags; meta+hashes; resize `fit`/`exact`/`fill` + `max_dimension` downscale with correct
  `scale_x`/`scale_y`; crop pixel-rect + `normalized` + named `region`; convert to all five formats (reopen +
  verify format/mode/dims); tile grid + fixed-size (+ overlap, bounded count); similarity (self-distance 0,
  near-duplicate small, different larger); error paths (`input_not_found`, `invalid_op`, `missing_params`,
  `unsupported_format`, `compare_not_found`); the Module 1 wrapper.

### MVP acceptance criteria
- [ ] `skill.json` is schema-valid; `determinism="deterministic"`, `parallel_safe=true`, `batch=false`.
- [ ] Every op returns a schema-valid `lifeorch.skill.result/0.1` envelope with `confidence=null` and empty
      `model_provenance`, exit 0.
- [ ] `meta` returns correct `width/height/format/mode/has_alpha` and `sha256`+`phash`+`dhash`.
- [ ] `resize max_dimension` downscales the longest side to <= N and reports `scale_x==scale_y` == the true ratio.
- [ ] `crop` (rect + region) produces an image of the applied size; out-of-bounds is clamped with a warning.
- [ ] `convert` writes a reopenable file in each of png/jpg/webp/bmp/tiff with the requested format.
- [ ] `tile` writes `count == cols*rows` (grid) tiles, each a valid image artifact with correct sha256.
- [ ] `similarity` reports Hamming 0 for identical input and a small distance for a re-encoded near-duplicate.
- [ ] Tests green on the cloud box (real worker) AND live via the executor on the system python.

### Manual verification procedure
- Run `Invoke-ImageUtil.ps1 -InputFile <a.png> -Op resize -MaxDimension 256`; open the output and confirm the
  longest side is 256 and aspect is preserved; confirm `result.resize.scale_x` matches `256/max(orig_w,orig_h)`.
- Run `-Op meta` on a phone photo and confirm the EXIF-lite block shows Make/Model/DateTime/Orientation.
- Run `-Op similarity -CompareTo <same-image-resaved.jpg>` and confirm `similarity` is high (Hamming small).

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `TOOL_MODEL_REGISTRY.md` **tool** entry for Pillow+numpy-under-system-python (status/location/invocation/
  last test) and refine the existing "System Python" runtime line with the confirmed PIL/cv2/numpy versions +
  "wired by image.util". **No `models.json` change** (not a gateway model).

### State updates
- Update `CURRENT_STATE.md` (active module -> none; Module 15 MVP complete; tests; deps) and `MODULE_ROADMAP.md`
  (#15 -> MVP complete). Add `DECISION_LOG.md` **D-0024**. **No `REVIEW_QUEUE.md` change** (deterministic; not a
  producer). Mirror `core-docs/` -> the attached Claude Project.

### Known follow-on work (deferred -> future work orders / roadmap, NOT this session)
- **`ocr.layout` compositions this module unblocks** (build in an `ocr.layout` follow-on, not here): (1)
  downscale an image over `MaxImageDimension` via `op=resize,max_dimension=10000` then **rescale word boxes** by
  `1/scale_x`,`1/scale_y`; (2) a **box-overlay PNG** once a draw/annotate op exists.
- A **draw/annotate/overlay** op (rectangles, text) - the primitive behind the OCR overlay.
- **Batch/directory/glob** processing; **rotate/flip/EXIF auto-orient**; denoise/sharpen/filters; multi-frame
  (GIF/animated) handling; thumbnails-with-padding; a side-effecting in-place mode.

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above (e.g. drawing, batch, OCR wiring).
- Pillow/numpy turn out to be missing or broken on the system python (they are not - `m15-probe-001`).
- The contract lacks something this module needs (stop, propose the change; do not freelance it).
- MVP acceptance is met - **stop; do not start Module 16.**
