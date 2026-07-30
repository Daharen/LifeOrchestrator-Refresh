# FANOUT_AGENT_001 -- GPU lane: GEN-image-sd35 (SD 3.5 Medium tier for gen.image #23)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i17 (plan id `fo-17-3a115347`)
- **Lane:** GPU (<=1 per wave)
- **Worker id / label:** `GEN-image-sd35` -- add a Stable Diffusion 3.5 Medium FP16 tier to gen.image #23
- **Module/area (exclusive):** `modules/23-gen-image` ONLY (+ its `models.json` entry -- the SOLE models.json-touching lane this wave)
- **GPU:** true
- **Docs:** `[]`

## Mission

Ship the FIRST generator upgrade -- a Stable Diffusion 3.5 Medium (FP16) tier in gen.image #23, keeping the
incumbent SD 1.5 as the fast legacy tier. SD3.5 Medium is the Diffusers-NATIVE image pick (diffusers 0.35.2
is already in the speech venv -> NO new engine/venv) and the lowest-integration first upgrade (leads doc
D-0068, `core-docs/research/2026-07-30-generator-model-leads.md`). Turing cc7.5 -> FP16 ONLY; fp16 + model
CPU offload + VAE tiling; T5-XXL on CPU; ~8-10.5 GB VRAM @1024. Establishes the generator-upgrade GPU-lane
wave pattern with minimal risk.

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/6dd619e0-8a9c-4cf8-a110-642f18ab7f0d/workers/worker-GEN-image-sd35.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (edit ONLY `modules/23-gen-image` + its worker/tests + the new model's `models.json`/model-home
wiring -- you are the ONLY lane that may touch models.json or a model module this wave):**
1. STAGE the SD 3.5 Medium weights into the #23 F: model home via an executor `curl.exe` task (large binaries
   download ON the device, NEVER through the bridge). Confirm source repo + files + sha256
   (`stabilityai/stable-diffusion-3.5-medium`; Stability Community License, free < $1M rev -- PRESERVE the
   note). Prefer keeping T5-XXL on CPU. Record staged paths + sha for the orchestrator to mirror (`docs:[]`).
2. WIRE a model/tier selector so a caller picks SD3.5-Medium vs the legacy SD1.5, consistent with the
   module's EXISTING surface. Do NOT regress SD1.5 (the fast legacy path).
3. PIPELINE: `StableDiffusion3Pipeline`, `torch_dtype` fp16, `enable_model_cpu_offload()` +
   `enable_vae_tiling()`, T5-XXL on CPU; fixed seed byte-reproducible on THIS GPU (the D-0021 meta-file
   worker hand-off); `parallel_safe:false`. GUARD VRAM -- VERIFY it fits with offload, do not assume.
4. LIVE VRAM-fit + smoke-gen: one deterministic prompt -> one image @768/1024; PNG produced,
   seed-reproducible, 0 orphaned python/llama-server after.

**SCOPE OUT (name as follow-ons):** Z-Image-Turbo Q8 (needs stable-diffusion.cpp -- a separate wave);
img2img/inpaint/ControlNet/upscaling/LoRA; batch/grids; a warm pipeline worker; the OTHER generator upgrades
(#22 audio / #24 music / #25 video -- each its own GPU-lane wave). Do NOT touch modules/15 or /16 (CPU lane),
modules/33 (coding lane), modules/07, core-infra, or any core-doc.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (speech venv: diffusers 0.35.2 / torch
  2.11+cu128; the D-0021 meta-file hand-off; child-pipe-deadlock, JSON-serializable-meta, pwsh 7.4.6
  empty-array-unroll / array-double-wrap / `@()`-on-List / `$var:` gotchas; detached-server + 0-orphan
  discipline) + `core-docs/research/2026-07-30-generator-model-leads.md` (the SD3.5 row + FP16-only Turing) +
  `modules/23-gen-image` (existing SD1.5 worker `gen_image_infer.py`); obey `SKILL_CONTRACT.md`.
- Lease order **gpu -> git**; release reverse. Edit+test under the GIT lease, RELEASE git, THEN take the GPU
  lease ONLY for the live VRAM-fit / smoke-gen -- never hold the GPU idle waiting on git, never nest
  gpu-under-git. Reap children before finalize; assert 0 orphaned python/llama-server.
- Gate off-machine FIRST (cloud pwsh + mock/seam): all non-CUDA logic green in cloud; the CUDA gen + VRAM
  probe degrade to 'unknown/unsupported' off-GPU, never throw. AST-parse `.ps1`; syntax-check `.py`. Then
  `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). EVERY `models.json`
  change RE-VERIFIES Module 7 (28/28).
- Do ONE unit; `docs:[]` -- report and let the orchestrator mirror. If SD3.5 proves impractical to fit even
  with offload, SHIP the wiring behind the selector, keep SD1.5 the default, and say plainly what remains
  (the D-0061 ethos).
- Report: `-Action report -PlanId fo-17-3a115347 -WorkerId GEN-image-sd35 -State done -Summary "<one line>"`
  (`-State blocked -Needs '<what>'` if stuck; `-State failed` if you cannot finish).

## Verification

Cloud mock + on-device `-Live` counts; live: SD3.5 loads fp16 with offload + VAE tiling, one seed-fixed image
(VRAM via nvidia-smi, PNG artifact, reproducible), SD1.5 STILL works, Module 7 28/28 (models.json changed), 0
orphans, `review_queue.jsonl` before==after. A Verification Console `run_module` item (one SD3.5 gen + one
SD1.5 gen). Report measured VRAM + gen time + artifact paths + staged model paths/sha.

## Report-back record (ORCHESTRATOR fills at close-out from `plans/fo-17-3a115347/reports/`)

_(pending)_
