# Work Order: Local Image Generation (`gen.image`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork — Module 23 build session) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority, Phase A #5 (generators, cheapest-first: gen.audio → gen.image → gen.music → gen.video)`

### Problem being solved
The generator track has its cheapest, deterministic member (`gen.audio` #22, procedural ffmpeg). The next generator is the first **neural** one: turning a text prompt into an image, entirely on the local machine. Nothing in the stack can do this today. `gen.image` closes that gap with **one skill that generates a single image from a text prompt** via a local Stable-Diffusion pipeline, and reports exactly what it produced — the neural counterpart of `image.util` (deterministic pixels) and the generation counterpart of `image.interpret` (#17, which *reads* an image; this one *writes* one). It is the #44 architectural family (`Qwen-Image` / `FLUX.1-schnell` / `Stable Diffusion XL`) built early as a standalone Phase-A generator (D-0029).

**Design decision (probe-driven, `m23-probe-001/002`, 2026-07-25):** the MVP is **Stable Diffusion 1.5 via the `diffusers` `StableDiffusionPipeline`**, fp16, on CUDA, driven by a **Python worker under the speech venv** with a **meta-file hand-off** to a PowerShell wrapper — the D-0021 pattern established by `speech.tts` (#12). The probe measured this end-to-end on the real box before any code was written:
- `m23-probe-001` (inventory): **no** image-gen model or diffusion checkpoint exists on F:/E: (0 hits); `diffusers` is **absent** from both pythons; the **speech venv** has torch 2.11.0+cu128 (CUDA 12.8, RTX 2080 Ti, cc 7.5, 11 GB, ~9 GB free), transformers 4.57.3, accelerate 1.12, safetensors 0.7, torchvision 0.26 — everything `diffusers` needs except `diffusers` itself; the **system python** is torch **2.2.1+cpu** (no CUDA), so it is unusable for GPU generation. F: has 1.75 TB free; C: is constrained (~64 GB).
- `m23-probe-002` (install + stage + live-generate): `pip install "diffusers<0.36"` added **diffusers 0.35.2** to the speech venv **without disturbing** torch/transformers, and **qwen_tts still imports** (Module 12 safe). SD 1.5 (fp16 variant, ~2.13 GB) downloaded to F: and a **live 512×512 generation** ran in **2.8 s** (8-step DPM++), pipeline load 1.9 s, **VRAM peak 2.61 GB** (huge headroom), producing a real non-blank image (pixel std 60.6).

So the whole path is proven on-machine. **FLUX.1-schnell** (12B, Apache-2.0) and **SDXL / SDXL-Turbo** are **documented follow-on tiers** — FLUX would need CPU-offload or a GGUF loader to fit 11 GB (the opposite of cheapest-first), and the Turbo models carry a non-commercial license. SD 1.5 is the smallest, fastest, most Turing-compatible, best-documented `diffusers` path, and it runs comfortably here.

### Immediate practical use
This week: the **Widget** layer (Phase B) and any agent can call `gen.image -Prompt "a cozy reading nook, warm light"` to produce a real PNG locally — thumbnails, placeholder/mock art, icons, test fixtures, illustration drafts — without spending the frontier image allotment. It is the cheap local "make me a picture" primitive the rest of the system can assume, exactly as `gen.audio` is the "make me a sound" primitive.

### Explicit scope (in)
- **One prompt → one image** per invocation (`batch:false`, `num_images` MVP = 1). Text-to-image only.
- **Prompt controls:** `-Prompt` (**required**), `-NegativePrompt`.
- **Image controls:** `-Width`/`-Height` (default 512×512; multiples of 8; bounded 128..1024 and `w*h <= 1024*1024` to protect VRAM), `-Steps` (default 20; 1..150), `-Guidance` (CFG scale, default 7.5; 0..30), `-Seed` (default -1 = random; a fixed seed ≥ 0 is reproducible on this GPU; the **actual** seed used is always recorded), `-Scheduler` (`dpm++` default | `euler` | `euler_a` | `ddim`).
- **Output:** `-Format png|jpg|webp` (default png). Writes `image.<ext>` + `gen.json` (machine) + `gen.md` (human).
- **Model resolution:** registry-driven from `models.json` (`type=image-gen`, decoupled from the gateway `wired` gate, mirroring `speech.tts`/`image.interpret`). Default `image.sd15`; `-Model <id>` / `-Tier <alias>` select others.
- **Stochastic/mixed producer:** populate `confidence` (a documented generation-completeness / non-blank heuristic) + `model_provenance`; route failed / blank / low-confidence generations to `review_queue.jsonl` — the **eighth** review-queue producer.
- Emit one contract-valid `lifeorch.skill.result/0.1` envelope on stdout; accept the generic `-InputsJson` + `-ArtifactRoot`/`-InvocationId`; reuse the Module 1 validators / `Invoke-Skill.ps1`; run through the executor. `determinism:"mixed"`, `parallel_safe:false` (binds CUDA/VRAM), `batch:false`.

### Non-goals (out — do NOT build)
- **No image-to-image / inpainting / outpainting / ControlNet / img2img / upscaling / LoRA / DreamBooth adaptation** — MVP is text-to-image only; each is a scoped follow-on.
- **No FLUX / SDXL / Qwen-Image tiers in this MVP** — documented follow-on tiers (FLUX needs offload/quant to fit 11 GB; Turbo models are non-commercial). SD 1.5 only.
- **No batch / grid / multi-image (`num_images>1`) output** (`batch:false`) — a follow-on.
- **No prompt-safety / NSFW classifier wiring** — the pipeline's safety_checker is disabled (it blackout-replaces images, breaking a deterministic generator); content responsibility stays with the caller. (A real safety pass is a separate, deliberate module, not silent image destruction.)
- **No animation / video** (that is `gen.video`, later) and **no music/audio** (that is `gen.audio` #22 / `gen.music`).
- **No warm/persistent pipeline server** — per-call cold load (cheap here: ~2 s). A warm-worker pool is the shared follow-on with #7/#8/#12/#17/#19.
- **No concealment / persistence / propagation / monitoring-evasion** (executor hard prohibition). Runs once, foreground, as ordinary visible activity.

### Dependencies
- Modules: **1** (`SkillContract.psm1` validators, `Invoke-Skill.ps1` wrapper). Runs through Module **0** (executor). Resolves its model from **`07-model-gateway/models.json`** (registry-decoupled, like `speech.tts`/`image.interpret`).
- Tools/models: **`diffusers` 0.35.2** (installed into the speech venv this session, `m23-probe-002`), **torch 2.11+cu128 / transformers / accelerate / safetensors / torchvision** (already in the speech venv), the **speech venv python** as `engine_env`; the staged **`image.sd15`** model (SD 1.5 diffusers fp16, downloaded + staged this session). `pwsh>=7.4`.
- Contract features: manifest `lifeorch.skill.manifest/0.1`; result `lifeorch.skill.result/0.1`; the `-InputsJson` generic-arg + artifact-root conventions (v0.2 §3.1; D-0009); review item `lifeorch.review.item/0.1`.

### Skill contract requirements
- `skill_id` = `gen.image`; `name` = `Local Image Generation (Stable Diffusion)`; `version` = `0.1.0`; `contract_version` = `0.2`.
- `determinism` = **`mixed`** (deterministic orchestration; the diffusion sampler is stochastic, seedable via `-Seed`). `confidence` populated (generation-completeness heuristic); `model_provenance` populated.
- **Eighth review-queue producer**: below-`-ConfidenceThreshold` (0.5) / blank / failed generation → one `verify_generation` item (`flagged_by:"gen.image"`, reason `failed_transform` ≤ 0.15 else `low_confidence`).
- `parallel_safe` = **false** (binds the CUDA context + loads a model, like `speech.tts`/`image.interpret`). `batch` = false; `streaming` = false.
- `requirements`: `executables:["pwsh>=7.4","python (speech venv) + diffusers 0.35.2"]`, `models:["image.sd15 (Stable Diffusion 1.5 diffusers fp16; CreativeML OpenRAIL-M)"]`, `gpu:"cuda (RTX 2080 Ti; SD runs on GPU)"`, `memory_mb:6144`, `filesystem:"read-write"`, `network:false`.
- `result` shape `{ input, model, request, image, confidence, review, generation }` (below). `confidence` a float.

### Inputs and outputs
- **Inputs** (named params and/or `-InputsJson` keys): `prompt` (**required**); `negative_prompt` (string); `width`/`height` (int, def 512; 128..1024, mult of 8); `steps` (int, def 20; 1..150); `guidance` (double, def 7.5; 0..30); `seed` (int, def -1 = random; recorded); `scheduler` (`dpm++`|`euler`|`euler_a`|`ddim`, def `dpm++`); `format` (`png`|`jpg`|`webp`, def png); `confidence_threshold` (double, def 0.5); `model` (id) / `tier` (alias); overrides `registry`/`python_path`/`gen_infer_path`/`pwsh_path`/`review_queue_path`.
- **Outputs:** the `result` object + artifacts under `runtime/artifacts/<invocation_id>/`:
  - `input` = `{ prompt, negative_prompt, chars }`.
  - `model` = `{ id, name, family, engine, engine_env, device, dtype, path }`.
  - `request` = `{ width, height, steps, guidance, seed, scheduler, format }` (seed = the actual seed used).
  - `image` = `{ path, format, width, height, mode, bytes, sha256, pixel_std, pixel_mean }`.
  - `confidence` = `{ overall, reason }`; `review` = `{ threshold, flagged, queue_path }`.
  - `generation` = `{ load_ms, gen_ms, runtime_ms, diffusers, torch }`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/image.<png|jpg|webp>` — the generated image.
- `runtime/artifacts/<invocation_id>/gen.json` — machine record (`lifeorch.gen.image/0.1` tag + full result).
- `runtime/artifacts/<invocation_id>/gen.md` — human summary (prompt, params, model, output stats).
- `runtime/artifacts/<invocation_id>/{gen_args.json, gen_meta.json, py.log, stderr.txt, result.json}` — per contract / worker hand-off.

### Proposed implementation
- **Language:** a **Python worker** (`gen_image_infer.py`, run under the speech venv; language policy: Python for the model ecosystem) + a **pwsh-7 wrapper** (`Invoke-GenImage.ps1`) with a **meta-file hand-off** (the D-0021 `speech.tts` pattern: the wrapper reads the worker's meta JSON, never its stdout, so `diffusers`/torch console chatter can never corrupt the parsed result). The wrapper owns the contract envelope, registry resolution, confidence, review-queue, and artifacts (all PowerShell); the worker owns model load + sampling + saving the image + reporting `pixel_std`/dims/timings in meta.
- Approach: merge `-InputsJson` with named params (named win when explicitly set). Validate prompt/dims/steps/guidance/format/scheduler. Resolve `image.sd15` (`type=image-gen`, `engine=diffusers`) + the venv python (`engine_env`) from `models.json`. Build `gen_args.json`, run the worker, read `gen_meta.json`. Worker: `StableDiffusionPipeline.from_pretrained(path, torch_dtype=float16, safety_checker=None, variant="fp16", local_files_only=True)` → chosen scheduler → `.to("cuda")` + attention/VAE slicing → `pipe(prompt, negative_prompt, num_inference_steps, guidance_scale, width, height, generator=Generator("cuda").manual_seed(seed))` → save image → compute pixel std/mean (numpy) → write meta. Wrapper computes **confidence** from `pixel_std` (empty/blank 0.1, near-uniform 0.3, low 0.5, has-content 0.9 — a completeness/non-blank heuristic, NOT aesthetic quality, NOT calibrated), populates `model_provenance`, and appends a `verify_generation` review item when confidence < threshold. Build the shared-shape envelope (UTF-8 no BOM; only the envelope on stdout; `${var}` interpolation; guard `.Count`; PSCustomObject error hand-off).

### External tools or models
- `diffusers` 0.35.2 (installed `m23-probe-002`; pinned `<0.36`). The speech venv python + its torch/transformers/torchvision. The staged **`image.sd15`** SD 1.5 diffusers fp16 model on F: (`23-gen-image\stable-diffusion-v1-5\`). All verified live this session.

### Installation steps
- Done in `m23-probe-002`: `pip install "diffusers>=0.30,<0.36"` into the speech venv (added diffusers 0.35.2 + importlib_metadata + zipp only; torch/transformers/qwen_tts unchanged — re-verified). SD 1.5 fp16 downloaded to `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\23-gen-image\stable-diffusion-v1-5\` (self-contained, `local_files_only=True`). `models.json` gains `image.sd15` + `defaults.image`/`tiers.image` (additive; Module 7 to be re-verified 28/28).

### Tests (`tests/Invoke-GenImageTests.ps1`; mock worker off-machine first, then live on the executor)
- **Cloud pre-ship gate = a stdlib mock worker** (`tests/mock-worker.py`, no torch/diffusers/PIL) that honours the `gen_image_infer.py` arg/meta contract: it writes a **real valid PNG** (hand-rolled via zlib/struct) + a meta JSON whose `pixel_std` is driven by the prompt (so the harness can exercise the high-confidence and the blank→review branches) or `ok:false` for the failure branch. The **real** `Invoke-GenImage.ps1` runs against it (parse/confidence/review/envelope path) — the `speech.tts` mock-python-worker gate in its image variant, since a GPU diffusion model cannot run on the Linux cloud box.
- **Manifest** validates (`Test-SkillManifest`).
- **Happy path** (mock high-std): valid envelope, status ok, exit 0, `image.png` on disk, `result.image.{width,height,mode,bytes,sha256}` populated, sha256 matches the file, confidence 0.9, `model_provenance` has one entry.
- **InputsJson** parity + **named-param-overrides-InputsJson** contract rule.
- **Params echoed:** width/height/steps/guidance/seed/scheduler/format flow to `gen_args.json` and back into `result.request`; a fixed seed is recorded; `-Seed -1` records a concrete chosen seed.
- **Format:** png/jpg/webp each produce a file with the right extension + magic bytes (mock writes PNG bytes; extension/format branch asserted on args).
- **Confidence + review:** a blank (low-std) mock result → confidence ≤ 0.3, a `verify_generation` item appended (`flagged_by:"gen.image"`), `result.review.flagged=true`; a good result appends **nothing**; canonical-queue producer attribution correct.
- **Error paths** (valid error envelopes, exit 0, never a crash): `no_prompt`; `invalid_dimensions` (not mult of 8 / out of range / over max pixels); `invalid_steps`; `invalid_guidance`; `invalid_format`; `invalid_scheduler`; `model_not_found` (bad `-Model`); `model_dir_missing`; `python_not_found`; worker `ok:false` → `generation_failed`.
- **Wrapper** integration: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{"prompt":"..."}'` ⇒ `manifest_valid` & `envelope_valid` true.
- **Live (executor):** a real SD 1.5 generation (default 512×512) → a real PNG, confidence 0.9, `model_provenance` device `cuda:0`; a second same-seed generation for reproducibility observation; a blank/again-review spot check; **0 orphaned python**; shipped-file sha256 byte-exact; `models.json` re-verify of Module 7 (28/28).

### MVP acceptance criteria
- [ ] Manifest validates; entrypoint accepts named params **and** `-InputsJson` (named wins).
- [ ] A real text-to-image generation produces a valid PNG on disk; envelope valid; exit 0; sha matches the file; `confidence` + `model_provenance` populated.
- [ ] width/height/steps/guidance/seed/scheduler/format controls all take effect and are echoed; the actual seed is always recorded.
- [ ] A blank/failed generation is flagged to the review queue (`verify_generation`, `flagged_by:"gen.image"`); a good one is not — producer set becomes **eight**.
- [ ] Every failure mode returns a **valid** `lifeorch.skill.result/0.1` error envelope (exit 0), never a crash.
- [ ] Runs direct, wrapped, and through the executor; artifacts written; all tests pass off-machine (mock) **and** live; 0 orphaned python; Module 12 (speech.tts) still works (diffusers install did not disturb the venv).

### Manual verification procedure
- `gen.image -Prompt "a red apple on a wooden table, studio photo" -Seed 42` → open `image.png`; confirm a coherent apple. Re-run with the same seed → confirm the same (or near-identical) image. `-Prompt "..." -Width 512 -Height 768 -Steps 25 -Guidance 8` → confirm a taller image. `-Format jpg` → confirm a JPEG.

### Documentation requirements
- Skill `README.md`, `skill.json` manifest, `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- `TOOL_MODEL_REGISTRY.md`: a `gen.image` skill entry (status installed, location, invocation, I/O, limitations, last test) + an `image.sd15` model row + a `diffusers`/speech-venv runtime note. `models.json`: add `image.sd15` (type `image-gen`, engine `diffusers`, engine_env speech venv, `wired:false`) + `defaults.image`/`tiers.image` (additive).

### State updates
- `CURRENT_STATE.md` (Module 23 complete, diffusers install, model staged, tests, next action) and `MODULE_ROADMAP.md` (Phase A #5 `gen.image` → MVP complete; expand its entry). Log the gen.image decisions (SD 1.5 via diffusers Python-worker+meta; mixed + eighth review producer; probe-driven model choice + neural-vs-cheapest reasoning; venv-install safety for Module 12) in `DECISION_LOG.md` (**D-0034**). Mirror core-docs → the Project.

### i17 addendum — SD 3.5 Medium quality tier (GPU-lane, plan fo-17-3a115347, worker GEN-image-sd35)
Added `image.sd35-medium` (Stable Diffusion 3.5 Medium, `StableDiffusion3Pipeline`, diffusers-native — no new
engine/venv; reuses the speech venv's diffusers 0.35.2 / torch 2.11+cu128) as a **second tier alongside the
unchanged SD 1.5 fast legacy default**. FP16-only (Turing cc7.5); `enable_model_cpu_offload()` +
`enable_vae_tiling()`, T5‑XXL CPU-side; the worker's VRAM safety ladder retries `enable_sequential_cpu_offload()`
on CUDA OOM (measured free VRAM at build time ~9.6 GB, so the fit is guarded, not assumed). Native FlowMatchEuler
scheduler. `gen_image_infer.py` gained an `sd`/`sd3` `pipeline_family` branch; `Invoke-GenImage.ps1` threads
`pipeline_family/offload/vae_tiling/drop_t5` from the model entry and echoes what actually ran into `generation`;
`models.json` gained the entry + `tiers.image.sd35` (default `image.sd15` unchanged). Weights staged on-device
from the gated `stabilityai/stable-diffusion-3.5-medium` (Stability Community License — free under $1M rev).

### Known follow-on work (defer — not this session)
- **Heavier/faster tiers:** the frontier *lead* `Z-Image-Turbo Q8` (needs the `stable-diffusion.cpp` engine + a
  parallel venv — a separate wave), FLUX.1-schnell (Apache-2.0; needs offload/quant on 11 GB) and SDXL / SDXL-Turbo (non-commercial) as additional `image-gen` tiers. The other generator upgrades (#22/#24/#25) each their own GPU-lane wave.
- img2img / inpainting / ControlNet / upscaling / LoRA / DreamBooth; `num_images>1` grids / batch; a warm/persistent pipeline worker (shared with #7/#8/#12/#17/#19); calibrated/aesthetic-model confidence (vs. the completeness heuristic); a real prompt-safety pass; prompt-weighting / long-prompt (compel); more schedulers / Karras sigmas.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g. adding img2img, ControlNet, SDXL/FLUX, or batch) — stop; write it into the roadmap.
- The diffusers install had disturbed the speech venv / broken `speech.tts` (Module 12) — stop; roll back the install. (Resolved: `m23-probe-002` re-verified torch/transformers/qwen_tts intact.)
- The GPU cannot fit / run the model — stop; note it. (Resolved: VRAM peak 2.61 GB, gen 2.8 s, `m23-probe-002`.)
- The contract lacks something needed — stop; propose the change in DECISION_LOG; do not freelance.
- **MVP acceptance met — stop; do not start the next module (`gen.music`).**
