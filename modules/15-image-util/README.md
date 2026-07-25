# image.util (Module 15)

Deterministic image plumbing for the perception block (Modules 14-18) and beyond. One image in ->
metadata + hashes always, plus one optional operation out. The image counterpart to `audio.ingest`
(Module 10) in the audio track: small, boring, reliable, CPU-only, and composable.

- **skill_id:** `image.util` · **determinism:** `deterministic` (`confidence:null`, no `model_provenance`,
  **not** a review-queue producer) · **parallel_safe:** `true` · **batch:** `false` · **streaming:** `false`.
- **Backend:** a Pillow + numpy **Python worker** (`image_worker.py`) run under the system python, with a
  **meta-file hand-off** to the PowerShell 7 wrapper (`Invoke-ImageUtil.ps1`) -- the D-0021 worker+meta
  pattern in its deterministic Python variant. No `model.gateway` model; no `models.json` entry.

## Operations (`-Op`)

- **meta** (default) -- `format, mode, width, height, has_alpha, dpi, n_frames, EXIF-lite` + hashes. Every op
  also returns this block, so any invocation doubles as a probe.
- **resize** -- `-Mode fit|fill|exact` with `-Width`/`-Height`, or a single `-MaxDimension` (longest side <= N).
  `fit` keeps aspect within the box (no upscale unless `-AllowUpscale`); `fill` covers the box then center-crops
  to exact size; `exact` ignores aspect. The result reports `original`, `result`, and `scale_x`/`scale_y` (so a
  caller can rescale coordinates -- e.g. `ocr.layout` word boxes -- by `1/scale`).
- **crop** -- an explicit pixel rect (`-X -Y -CropWidth -CropHeight`), a `-Normalized` (0..1) rect, or a named
  `-Region` (`center|top|bottom|left|right|top-left|...`) sized by `-RegionFraction`. Out-of-bounds is clamped
  (with a warning -> `status:"partial"`).
- **convert** -- re-encode to `-Format png|jpg|webp|bmp|tiff` with `-Quality` (jpg/webp). Alpha is flattened
  onto white for formats without an alpha channel.
- **tile** -- split into a `-TileCols` x `-TileRows` grid, or fixed `-TileWidth` x `-TileHeight` (with optional
  `-TileOverlap`). Each tile is written as its own image artifact (bounded to 400 tiles).
- **similarity** -- `-CompareTo` a second image; returns pHash/dHash Hamming distances + a `similarity` score
  (`1 - hamming_phash/hash_bits`). Good for dedup / near-duplicate detection.

## Hashes

Every invocation returns `sha256` (exact file content) plus a perceptual **pHash** (64-bit DCT hash) and
**dHash** (64-bit gradient hash) unless `-NoPerceptualHash`. The perceptual hashes are deterministic and
**stable across Pillow/numpy versions** (verified by `m15-probe-001`: identical on PIL 10.2/numpy 1.26 and
PIL 12.2/numpy 2.4), so they are safe to store and compare across machines.

## Result shape

```
{ input{path,exists,bytes,sha256,format,mode,width,height,has_alpha}, op, params{...},
  metadata{format,mode,width,height,has_alpha,dpi,n_frames,exif{...}},
  hashes{sha256,phash,dhash,hash_bits},
  outputs[{path,format,mode,width,height,bytes,sha256}],
  resize{mode,requested,original,result,scale_x,scale_y}|null,
  crop{requested,applied}|null,
  tile{mode,cols,rows,tile_width,tile_height,overlap,count,tiles[{index,row,col,x,y,width,height,path}]}|null,
  similarity{compare_to,hash_bits,phash_a,phash_b,hamming_phash,dhash_a,dhash_b,hamming_dhash,similarity}|null,
  runtime_ms, worker{python,pillow_version,numpy_version} }
```

Artifacts under `runtime/artifacts/<invocation_id>/`: `image.json` (structured), `image.md` (human summary),
`image_args.json` + `image_meta.json` (worker hand-off), `worker.log`, `result.json`, `stderr.txt`, and any
produced image file(s).

## Requirements

- `pwsh >= 7.4` (the wrapper) and a **python with Pillow >= 10 + numpy** (the worker). The wrapper resolves the
  interpreter from `-PythonPath` -> the system Python312 -> the speech venv -> `python`/`python3`/`py` on PATH,
  picking the first that imports both. CPU-only; no GPU, no network.

## Invocation

```powershell
# metadata + hashes
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\photo.png -Op meta
# downscale over a max dimension (reports scale factors)
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\big.png -Op resize -MaxDimension 1024
# via the generic channel / Module 1 wrapper
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"input":"photo.png","op":"meta"}'
```

See `examples/` for more and a real `example-result.json`.

## Tests

`tests/Invoke-ImageUtilTests.ps1 [-PythonPath <python>]` runs the **real** worker (Pillow is portable and
version-stable, so no mock is needed -- the same real-engine-on-cloud gate as `audio.ingest`), generating its
fixtures with Pillow at runtime. It covers the manifest, meta+hashes, resize (fit/fill/exact/max_dimension +
scale factors), crop (rect/normalized/region), convert to all five formats, tile (grid + fixed size),
similarity (self/near-dup/different), the error paths, and the Module 1 wrapper. It is green on the cloud Linux
box (pre-ship) and live on the Windows executor.

## Known follow-ons (not in this MVP)

- The `ocr.layout` compositions this unblocks: downscale over `MaxImageDimension` then **rescale boxes** by
  `1/scale`, and a **box-overlay PNG** (needs a draw op).
- A **draw/annotate/overlay** op; **batch/directory/glob**; rotate/flip/EXIF auto-orient; denoise/sharpen;
  multi-frame (GIF) handling. See `WORK_ORDER.md` and DECISION_LOG D-0024.
