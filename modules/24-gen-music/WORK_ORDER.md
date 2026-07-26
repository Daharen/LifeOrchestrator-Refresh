# Work Order: Local Music Generation (`gen.music`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority Phase A #4 (generators, cheapest-first) → gen.music` · **On-disk folder:** `modules/24-gen-music/`

### Problem being solved
The generator track has procedural sound (`gen.audio` #22) and neural images (`gen.image` #23) but no **music**. `gen.music` closes that gap: it turns a text prompt into one short instrumental clip with a local model, so an agent (a Widget, the local orchestrator #21, an unattended executor task) can produce music on this machine without a frontier call or a cloud service.

### Immediate practical use
Notification/《theme》 stingers, background beds for the Generator Studio Widget, mood loops, quick musical sketches from a text idea — all generated locally, cheaply, and reproducibly (fixed seed → identical bytes).

### Explicit scope (in)
- One text `-Prompt` → one **32 kHz mono** clip via **MusicGen Small** (transformers `MusicgenForConditionalGeneration`, CUDA).
- Controls: `-Duration` (1..30 s), `-Guidance`, `-Temperature`, `-TopK`, `-TopP`, `-Seed` (-1=random, recorded; ≥0 reproducible), `-Normalize` (peak-normalize to avoid clipping).
- Output `music.wav`; optional `-Format` (mp3/flac/opus/ogg/m4a) + `-SampleRate` via composing **`audio.ingest` (#10)**.
- Python worker (`music_gen_infer.py`, speech venv) + PowerShell wrapper (`Invoke-GenMusic.ps1`) with a **meta-file hand-off** (the D-0021 `speech.tts` / D-0034 `gen.image` pattern).
- Registry-driven (`music.musicgen-small`, `type=music-gen`, `engine=transformers`, decoupled from the gateway `wired` gate); add `defaults.music`/`tiers.music`.
- Confidence = generation-completeness / non-silent heuristic (audio RMS); **ninth review-queue producer** (`verify_generation`, `flagged_by:"gen.music"`).

### Non-goals (out — do NOT build)
- **Vocals / lyrics** (MusicGen is instrumental) and **melody-conditioned** generation (`MusicgenMelody`) — follow-ons.
- Larger tiers (MusicGen Medium/Large) or a different family (Stable Audio Open, Mer) — documented follow-on tiers.
- Batch / multi-clip, a warm/persistent pipeline worker, calibrated/aesthetic confidence, a prompt-safety pass, streaming.
- Installing `audiocraft` (not needed — transformers ships MusicGen natively).

### Dependencies
- Modules: `audio.ingest` (#10, optional non-wav conversion); `skill.bootstrap` (#1, wrapper); resolves the registry from `model.gateway` (#7) `models.json`.
- Tools/models: `music.musicgen-small` (staged to F:); the speech venv python (transformers 4.57.3, torch 2.11+cu128, soundfile); ffmpeg (only for non-wav `-Format`, via audio.ingest).
- Contract features: `-InputsJson`, `-ArtifactRoot`, absolute artifact paths, `confidence`/`model_provenance`, review-queue producer.

### Skill contract requirements
- `skill_id=gen.music`, `name="Local Music Generation (MusicGen)"`, `version=0.1.0`, `determinism=mixed`, `parallel_safe=false`, `batch=false`, `streaming=false`.
- `result` shape: `{input, model, request, audio, confidence, review, generation}`. `confidence` populated (mixed). `model_provenance[1]` = one aggregate entry. Artifacts: the audio file (`wav`/`mp3`/…), `gen.json` (json), `gen.md` (markdown).

### Inputs and outputs
- **Inputs:** as the scope list (all optional but `prompt`).
- **Outputs:** `result.audio{path,format,sample_rate,channels,samples,duration_s,bytes,sha256,rms,peak,normalized,native_sample_rate,converted}`; artifact files `music.<ext>` + `gen.json` + `gen.md`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `music.<ext>`, `gen.json`, `gen.md`, `result.json`, `gen_args.json`, `gen_meta.json`, `py.log`, `stderr.txt` (+ `convert/` when a format/rate conversion runs).

### Proposed implementation
- **Language:** Python worker (the transformers/torch ecosystem) + PowerShell wrapper (the contract envelope), per the language policy (D-0004) and the D-0021 worker+meta pattern.
- **Backend:** transformers `MusicgenForConditionalGeneration.from_pretrained(path, local_files_only=True).to("cuda")` + `AutoProcessor`; `model.generate(do_sample=temp>0, guidance_scale, max_new_tokens=round(duration*frame_rate), temperature/top_k/top_p)`; `torch.manual_seed(seed)` for reproducibility; peak-normalize; write 32 kHz mono PCM16 WAV via soundfile.

### External tools or models
- **MusicGen Small** — `facebook/musicgen-small`, transformers folder format, CC-BY-NC-4.0. **No library install** (transformers 4.57 already has MusicGen — confirmed by `m24-probe-001`).

### Installation steps
- Download `facebook/musicgen-small` to `F:\...\24-gen-music\musicgen-small\` via `huggingface_hub.snapshot_download` under the speech venv (done: `m24-probe-002`); prune the redundant `pytorch_model.bin`/`state_dict.bin`/`compression_state_dict.bin` (keep `model.safetensors` + configs + tokenizer; `m24-prune-001`, reload-verified). Final ~2.37 GB; `model.safetensors` sha256 `1bdc99d4…`.
- Add `music.musicgen-small` + `defaults.music`/`tiers.music` to `models.json` (additive → re-verify Module 7 28/28).

### Tests
- **Direct/mock (cloud pre-ship):** `tests/Invoke-GenMusicTests.ps1` runs the **real** wrapper against `tests/mock-worker.py` (stdlib `wave`; no torch/transformers) on cloud pwsh 7.4.6 — validation, confidence/review branches, error paths, Module 1 wrapper.
- **Through the executor (`-Live`):** the real MusicGen worker + real registry — a real generation, same-seed byte-reproducibility, and mp3/resample via the real `audio.ingest`; assert canonical `review_queue.jsonl` before==after, 0 orphaned python.

### MVP acceptance criteria
- Mock gate green on cloud pwsh 7.4.6; all `.ps1` AST-parse + all `.py` `py_compile` clean.
- Files shipped byte-exact (sha256 verified on target) + AST-parse OK via an executor read.
- `-Live` green via the executor: real 32 kHz WAV, same-seed reproducible, mp3 conversion, review routing, canonical queue before==after, 0 orphans.
- **Module 7 re-verified 28/28** after the additive `models.json` change. (No venv install → Module 12 unaffected.)

### Manual verification procedure
- Run `Invoke-GenMusic.ps1 -Prompt "upbeat 8-bit chiptune" -Duration 8 -Seed 42`; open `music.wav` and confirm it plays audible instrumental music; re-run same seed → identical sha256.

### Documentation requirements
- `README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json` (all present).

### Registry updates
- `TOOL_MODEL_REGISTRY.md`: add `music.musicgen-small` (music-gen; F: path; sha; license) + a `gen.music` skill entry + the MusicGen/transformers runtime note.

### State updates
- `CURRENT_STATE.md` (active module → none; Module 24 complete; installed models), `MODULE_ROADMAP.md` (Module 24 entry + Build priority status), `DECISION_LOG.md` (D-0035), `REVIEW_QUEUE.md` (ninth producer note). Mirror all changed core-docs to the Project.

### Known follow-on work
- Melody-conditioned generation (`MusicgenMelody`); larger tiers (Medium/Large) / Stable Audio Open; batch/multi-clip; a warm/persistent worker (shared with #7/#8/#12/#17/#19); calibrated/aesthetic confidence; a prompt-safety pass; stereo; longer-than-30 s via sliding-window continuation.

### STOP conditions
- Scope would exceed the "Explicit scope" list. · A dependency is missing/broken and installing it is non-trivial. · The contract lacks something this module needs. · **MVP acceptance is met — stop; do not start the next module (`gen.video`).**
