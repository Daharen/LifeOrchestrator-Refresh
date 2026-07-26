# MODULE_WORK_ORDER

## Work Order: Local Video Generation (`gen.video`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-26 · **Roadmap entry:** `MODULE_ROADMAP.md#gen.video` (Phase A #4 — generators, cheapest-first: `gen.audio`→`gen.image`→`gen.music`→**`gen.video`**)

**Folder-number note:** on-disk `modules/25-gen-video/`. The `NN-` prefix is a **monotonic build-order counter** (0, 00.1, 1..24, then 25); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions. `gen.video` is the fourth (last) generator and the third neural one; text-to-video is folded into the #44 generator family (no dedicated spine slot — the ARCHITECTURE_MAP "19-22 video" block is the *perception/decompose* stack, not generation).

### Problem being solved
The generator track (`gen.audio` #22 procedural sound → `gen.image` #23 neural images → `gen.music` #24 neural music) has no **motion/video** member. This module closes it: turn a text prompt into one short **silent video clip** with a local diffusion model, so a Widget (the Generator Studio) or a local agent can make placeholder/mock motion, animated icons, mood loops, and test fixtures **locally** instead of on the frontier allotment. It is the motion sibling of `gen.image` (neural pixels) and the video counterpart of `image.interpret` (#17, which reads an image).

### Immediate practical use
The Generator Studio Widget (Phase B) and `agent.local`/executor tasks call it to produce a short MP4/GIF from a prompt. This week it gives the project a working local text-to-video primitive with the same envelope/registry/review contract as the other generators.

### The hard constraint (why this is the most demanding generator)
The RTX 2080 Ti has **11 GB VRAM** and **compute capability 7.5 (Turing)** — it drives the Windows desktop too, so usable VRAM is < 11 GB. Turing has **native fp16 but only emulated (slow) bf16**, so bf16-first DiT text-to-video models (CogVideoX, LTX-Video, Wan, Mochi, HunyuanVideo) are effectively out — most also exceed 11 GB. Full text-to-video foundation models generally will not fit or will require heavy CPU-offload/quant. The viable envelope on this box is a **small, short, fp16 SD-1.5-based** approach.

### Chosen approach (probe-gated — see the probe below)
**Primary candidate: AnimateDiff-Lightning on the already-staged Stable Diffusion 1.5.** AnimateDiff injects a temporal **motion module** into an SD-1.5 UNet; **AnimateDiff-Lightning** (ByteDance, distilled) generates in **4 steps**, so it is fast and fp16-native. It **reuses the SD 1.5 checkpoint already staged for `gen.image` (#23)** — the only new download is the ~1.7 GB motion adapter. diffusers 0.35.2 (already in the speech venv) ships `AnimateDiffPipeline` + `MotionAdapter`. VRAM is bounded with `enable_vae_slicing()` and, if needed, `enable_model_cpu_offload()`, at 16 frames / 512×512.

**The build proceeds only if the probe confirms a real generation fits in VRAM and produces a non-blank, moving clip.** Documented fallbacks if AnimateDiff does not fit: a lower-res / fewer-frame config; or a dedicated small T2V model (ModelScope T2V `damo-vilab/text-to-video-ms-1.7b` at 256×256, or Zeroscope v2). **Deferral (a documented WORK_ORDER + DECISION_LOG D-0036 rationale) is a legitimate outcome** if nothing viable fits — the precedent is D-0033 (the neural audio-SFX tier was deferred).

### Probe outcome & decision (2026-07-26) — **BUILD**
Two probes settled it. **`m25-probe-001`** (recon + download): diffusers 0.35.2 exposes `AnimateDiffPipeline` + `MotionAdapter`; torch 2.11+cu128 on the RTX 2080 Ti; **9.87 GB VRAM free** of 11; no video model was staged; downloaded the **AnimateDiff-Lightning 4-step diffusers adapter (907 MB)** to `F:\...\25-gen-video\animatediff-lightning\`; `imageio`/`cv2` are **absent** (so `diffusers.utils.export_to_video` can't run) but `export_to_gif` (Pillow 12.2) works and **ffmpeg 8.1 is present** → MP4 via ffmpeg. The first probe's generation failed only because it omitted `variant="fp16"` when loading the fp16-only SD 1.5 folder (its `text_encoder` ships only `model.fp16.safetensors`) — a probe bug, not a feasibility limit. **`m25-probe-002`** (fixed load, real generation): AnimateDiff-Lightning on the staged SD 1.5, 16 frames @ 512×512, 4 steps, guidance 1.0 → **VRAM peak 4.75 GB (no offload needed)**, **pixel_std 44.4 / mean interframe diff 41.6** (non-blank, strong motion), a fixed seed **byte-reproducible** (identical, max_abs_diff 0), and both a **712 KB MP4 (ffmpeg, rc 0)** and a **3.3 MB GIF** exported cleanly. Warm generation ~57 s (first ~120 s incl. CUDA warmup). **No library install** (diffusers already present; ffmpeg present). License: **CreativeML-OpenRAIL-M** (both the SD 1.5 base and the AnimateDiff-Lightning adapter — a precedented local-generation deviation, exactly like SD 1.5 in D-0034). **→ Decision: build with AnimateDiff-Lightning on SD 1.5, full-GPU, MP4 via ffmpeg / GIF via PIL** (the worker keeps a CUDA-OOM → cpu-offload auto-retry as a safety valve, though the probe shows it is not needed here).

### Explicit scope (in)
- One prompt → one short **silent** clip (MP4 and/or animated GIF), text-to-video only.
- Backend = the D-0021/D-0034/D-0035 pattern: a **Python worker** (`video_gen_infer.py`, speech venv) + **meta-file hand-off** to a **PowerShell wrapper** (`Invoke-GenVideo.ps1`) that reads the worker's meta JSON (never its stdout), builds the `lifeorch.skill.result/0.1` envelope.
- Registry-driven model resolution from `models.json` (`type=video-gen`, `engine=diffusers`, `engine_env`=speech venv, **decoupled from the gateway `wired` gate**, D-0020). Adds `defaults.video` / `tiers.video` + the model entry (additive; **re-verify Module 7 28/28**).
- Controls: `-Prompt`, `-NegativePrompt`, `-NumFrames`, `-Width`/`-Height`, `-Steps`, `-Guidance`, `-Fps`, `-Seed` (-1=random, recorded), `-Format` (mp4|gif), `-Model`/`-Tier`.
- **Confidence** = a generation-completeness / non-blank **and non-static** heuristic (per-frame pixel std + mean inter-frame difference → motion present). **Tenth review-queue producer** (below-threshold / blank / static / failed → `verify_generation`, `flagged_by:"gen.video"`; set 7/8/11/12/14/16/17/23/24/**25**).
- Model + any HF cache staged to **F:** (per D-0015; C: is space-constrained). No weights in the C: repo.

### Non-goals (out — do NOT build)
- Image-to-video / video-to-video, ControlNet/motion-LoRA conditioning, interpolation/upscaling, longer clips via sliding-window continuation (documented follow-ons).
- Audio tracks / lip-sync / talking-head (that is a later, separate concern).
- Multiple clips per call / grids / batch (`batch:false`).
- A warm/persistent pipeline worker; larger tiers (AnimateDiff full 25-step, SVD img2vid, CogVideoX/LTX if a bf16-capable GPU ever arrives).
- Any bf16-first foundation T2V model on this hardware.

### Dependencies
- Modules: `skill.bootstrap` (#1 wrapper/validators); reuses the **staged SD 1.5** from `gen.image` (#23); optionally composes `audio.ingest` (#10) only if a container needs re-mux (not expected). · Tools/models: the **speech venv** python (torch 2.11+cu128, diffusers 0.35.2, transformers 4.57, accelerate, safetensors, Pillow), **ffmpeg 8.1** (present, for MP4 mux if needed) · Contract features: `-InputsJson`, `-ArtifactRoot`, `model_provenance`, `confidence`, review queue.

### Skill contract requirements
- `skill_id`=`gen.video`, `name`="Local Video Generation", `version`=`0.1.0`, `determinism`=`mixed`, `parallel_safe`=`false` (binds CUDA/VRAM), `batch`=`false`, `streaming`=`false`.
- `result` shape: `{input{prompt,negative_prompt,chars}, model{id,name,family,engine,engine_env,device,dtype,base,adapter,path}, request{num_frames,width,height,steps,guidance,seed,fps,format}, video{path,format,codec,width,height,num_frames,fps,duration_s,bytes,sha256}, motion{mean_abs_interframe_diff,per_frame_std_min}, confidence{overall,reason}, review{threshold,flagged,queue_path}, generation{load_ms,gen_ms,runtime_ms,vram_peak_gb,offload,diffusers,torch}}`.
- `confidence` populated (0..1); `model_provenance[1]` populated (the video model). Artifact kinds: `video/mp4` or `image/gif`, `application/json`, `text/markdown`.

### Inputs and outputs
- **Inputs:** `prompt`(string, required), `negative_prompt`(string), `num_frames`(int, default 16), `width`/`height`(int, default 512), `steps`(int, default 4), `guidance`(float, default 1.0), `fps`(int, default 8), `seed`(int, default -1), `format`(mp4|gif, default mp4), `confidence_threshold`(float, default 0.5), `model`/`tier`.
- **Outputs:** the envelope above + `runtime/artifacts/<id>/{video.mp4|video.gif, gen.json, gen.md, gen_args.json, gen_meta.json, py.log, result.json, stderr.txt}`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `video.<mp4|gif>`, `gen.json` (machine), `gen.md` (human card), `gen_args.json` (worker input), `gen_meta.json` (worker output for the hand-off), `py.log` (worker stderr), `result.json`, `stderr.txt`.

### Proposed implementation
- **Language:** PowerShell wrapper + Python worker (per policy: the neural pipeline is Python/diffusers; the wrapper does resolution, spawning, meta-parse, envelope, review — the D-0034/D-0035 pattern). **Why:** identical to `gen.image`/`gen.music`, so it inherits their proven robustness against ML-library stdout chatter.
- Worker: resolve model from an args JSON → `AnimateDiffPipeline.from_pretrained(SD15_base, motion_adapter=MotionAdapter(load lightning ckpt), torch_dtype=fp16, local_files_only, safety_checker=None)` → `EulerDiscreteScheduler(trailing, linear)` → `enable_vae_slicing()` (+ `enable_model_cpu_offload()` if the probe requires it) → generate → write MP4 (frames→ffmpeg, or `export_to_video` if the probe confirms imageio/cv2) and/or GIF (`export_to_gif`, Pillow) → write `gen_meta.json`.
- Wrapper: `Invoke-GenVideo.ps1` mirrors `Invoke-GenMusic.ps1` — resolves the venv python + model from `models.json`, spawns the worker, reads `gen_meta.json`, computes confidence, routes review, builds the envelope; optional non-mp4 handled in-worker.

### External tools or models
- **AnimateDiff-Lightning 4-step** motion adapter (ByteDance/AnimateDiff-Lightning, `animatediff_lightning_4step_diffusers.safetensors`, ~1.7 GB) staged to `F:\...\LifeOrchestrator-Refresh_Large_Data\25-gen-video\`. License: **check in the probe** (AnimateDiff-Lightning is openrail-ish / CreativeML lineage via SD 1.5 — record the exact license, precedented deviation like SD 1.5 OpenRAIL-M / MusicGen CC-BY-NC).
- Reuses staged **SD 1.5** (`23-gen-image\stable-diffusion-v1-5\`). **No library install expected** (diffusers already present; MP4 via ffmpeg-mux or export_to_video). If MP4 export needs `imageio-ffmpeg`, prefer the **frames→ffmpeg 8.1** mux path to avoid touching the venv (keeps Module 12 unaffected by construction, like #24).

### Installation steps
- Probe stages the motion adapter to F: and live-generates before any skill code is written (the D-0034/D-0035 discipline). Record diffusers/torch versions + the exact model path/sha in `models.json` and the registry.

### Tests
- **Off-machine (cloud pre-ship gate):** cloud pwsh 7.4.6 AST-parse both scripts (`py_compile` the worker) + run the **real wrapper** against a **stdlib mock worker** that writes a real tiny MP4/GIF + `gen_meta.json` (the #23/#24 mock-worker gate — a real diffusion pipeline can't run on the cloud Linux box). Assert a schema-valid envelope, review routing, error paths, the Module 1 wrapper.
- **Through the executor (`-Live`):** real AnimateDiff generation (non-blank + non-static), same-seed reproducibility, mp4 + gif, canonical `review_queue.jsonl` before==after, 0 orphaned python. Then **Module 7 re-verify 28/28** (additive `models.json`).

### MVP acceptance criteria
- A real prompt → a real short MP4 (and/or GIF) on disk, non-blank and showing motion, within VRAM.
- Schema-valid `lifeorch.skill.result/0.1`; `confidence` + `model_provenance` populated; tenth review producer wired; canonical queue untouched on a healthy run.
- Off-machine mock gate green + `-Live` executor tests green + Module 7 28/28.
- Files placed byte-exact (sha256 + AST-parse verified on target); committed with trailers; core-docs updated (CRLF-safe) + Project mirrored.

### Manual verification procedure
- Open the produced MP4/GIF; confirm it is a coherent, moving clip matching the prompt; confirm a fixed seed reproduces it.

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + `examples/` invocation/result.

### Registry updates
- `models.json`: add `video.animatediff-lightning` (`type=video-gen`, `engine=diffusers`, `engine_env`=venv, `wired:false`) + `defaults.video`/`tiers.video`. `TOOL_MODEL_REGISTRY.md`: a `gen.video` skill entry + the model row + a diffusers-runtime note.

### State updates
- `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (Module 25 entry + Build priority), `DECISION_LOG.md` (**D-0036**), `REVIEW_QUEUE.md` (tenth producer note).

### Known follow-on work (NOT this session)
- Heavier/longer tiers (AnimateDiff full/25-step, SVD img2vid, CogVideoX/LTX on future bf16 HW); img2video / video2video; motion-LoRA / ControlNet conditioning; frame interpolation + upscaling; >~2 s via sliding-window; a warm pipeline worker; calibrated/aesthetic + motion-quality confidence; a prompt-safety pass; audio track.

### STOP conditions
- Scope would exceed the list above.
- The probe shows **no** config fits 11 GB VRAM / produces a usable clip → **defer**: finalize this WORK_ORDER as deferred + log **D-0036** with the measured rationale (the D-0033 precedent). Do not force a broken build.
- The contract lacks something needed (stop, propose a change).
- MVP acceptance met — **stop; do not start the next module** (the next unit is `agent.coding`, then the Widget layer).
