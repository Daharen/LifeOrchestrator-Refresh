# MODULE_ROADMAP

Owns **build order, per-module status, and the deferred follow-on menu** (the project's future-work list).
Not technical specs — each active module gets a `WORK_ORDER.md` in its own folder.
**Provisional beyond the first few items on purpose:** we do not lock thirty modules before using the
first five. Reorder freely as MVPs teach us what matters.

**Memory-subsystem build order (D-0090):** the Collective Agent memory subsystem follows the tiered plan in
`MEMORY_ARCHITECTURE.md` s10 — Tier 0 (invariants + seam repairs; SHIPPED i32/i33), Tier 1 (anti-deterioration
foundation; hierarchy nav + working-memory store; **ACCEPTED i36, D-0102**), Tier 2 (operational memory
formation), Tier 3 (advanced scale mechanisms, activate on measured need). Memory waves draw from that plan;
this menu holds the rest.

**Status vocabulary:** Proposed · Ready · In progress · Blocked · MVP complete · Active · Needs refactor ·
Deprecated · Replaced.

**Owned elsewhere — pointers, not duplicated:** model/tool/hardware inventory → `TOOL_MODEL_REGISTRY.md` ·
now-summary + test table → `CURRENT_STATE.md` · review-queue schema + producer/consumer table →
`REVIEW_QUEUE.md` · orchestrator ops + wave model → `FANOUT_ORCHESTRATOR_HANDOFF.md` · governor design →
`ADAPTIVE_RESOURCE_GOVERNOR.md` · rationale → `DECISION_LOG.md` (index: `DECISION_LOG_INDEX.md`) ·
pre-consolidation full text → `archive/`. Per-module params/artifacts → `modules/<NN>-*/README.md`.

---

## Build priority (2026-07-25 pivot D-0029; 2026-07-31 repivot D-0080)

> **D-0080 — REPRIORITIZED to the Collective Agent (cognitive virtual memory).** The build order pivots to the
> memory + retrieval + context + skill-activation + episodic/failure/procedure substrate that connects the
> existing Modules into one persistent agent. **PULLED FORWARD:** embedding adapter -> `artifact.search` MVP ->
> retrieval eval -> repo intelligence -> context compiler -> episodic/failure memory -> skill+procedure
> registry -> skill routing -> read-only Collective Agent slice -> sandbox coding worker -> sequential LOCAL
> orchestrator -> domain slices -> unified UI. **FROZEN/deferred:** supervisor/warm-pool hardening (D-0079
> GATE-NO stands; classic detached-warm is the trusted default), generators, `video.interpret` + live
> composition, real-time perception (27-49), broad training.
>
> **Executed i25-i39 (one line each; detail = the D-entry):** Wave 1 substrate #35/#36/#37 (i25, D-0082) ->
> MEMORY_CONTRACT freeze (i26, D-0083) -> Wave 2 records #36 0.2.0 + NEW #38/#39 (i27, D-0084; settled i28,
> D-0085/A1) -> Wave 3 NEW #40 + #37 0.2.0 + NEW #41 (i29, D-0086) -> context_packet/0.2 hardening (i30,
> D-0087/88) -> selpol settle (i31, D-0089/91) -> Tier-0 seam repairs: ns-closure + supersession (i32/i33,
> D-0092..97) -> Tier-1 hierarchy slice + NEW #42 (i34, D-0098/99) -> consumer wiring #40 0.7.0 + the
> rehearsal harness (i35, D-0100) -> **Tier-1 ACCEPTED** + #36 0.6.0 + NEW widgets/05 (i36, D-0102) ->
> ACTION_AUTHORIZATION_CONTRACT freeze (D-0103) + the R-1 router #40 0.8.0 + NEW #43 P0-1 monitor (i37,
> D-0104) -> the P0-1 full-gate build #43 0.2.0 + #40 0.9.0 wm-hydration + NEW widgets/06 (i38, D-0105/06;
> pass over-claimed -> walked back, D-0107) -> the gate-completion build #43 0.3.0 + #36 0.7.0 fast-beam +
> NEW widgets/07 (i39, D-0108; pass over-claimed again -> walked back, D-0109). **i40 in flight:** #43 0.4.0
> exact closures + #37 reconcile (D-0111); mandate-01 sunset -> mandate 02 (D-0110).
>
> 2080 Ti = build target, RTX PRO 6000 = horizon. Live status: `CURRENT_STATE.md`.

**The per-module numbers are architectural positions, not a build sequence.** The full 0-49 spine lives in
`ARCHITECTURE_MAP.md`. **Modules 0-34 + 00.1 + the memory subsystem #35-#43 are built; Widgets 01-08 are
built.**

**Phase A — utility & cost-offload Modules — COMPLETE except the deferred coding agent:** `logic.escalator`
#19 (D-0030) · `doc.io` #20 (D-0031) · `agent.local` #21 (D-0032) · generators cheapest-first #22-#25
(D-0033..36; upgrade leads D-0068 — image Z-Image-Turbo Q8 [needs stable-diffusion.cpp], music ACE-Step,
video LTX-Video/Wan2.1, audio Stable Audio; SD 3.5 fp16 tier shipped i17, D-0070; each further upgrade = a
GPU-lane wave) · `agent.coding` DEFERRED (D-0037; see #26).

**Phase B — Widget layer:** 01-08 shipped. Backlog: **Voice Console · Generator Studio · Document Workspace ·
System/Executor Monitor**. Full list in `widgets/README.md`.

**Phase C — canonical spine:** video 19-22 front half BUILT (#32/#33/#34); `video.interpret` (pos 22) remains,
gated on the DENSE-STREAM decision (see #33). Then search/routing/orchestration (23-26) → general screen
perception + self-improving (27-44) → the real-time autonomic layer (45-49).

**Direction (D-0050):** past MVP the project drives ONE spine — the **offload / audit loop** under the
verify-cost rule (Claude offloads only what is cheaper to verify than to do; deterministic modules =
Claude's hands; model modules only where machine- or human-checkable).

---

## BACKLOG — portability / new-machine bring-up

**Deferred; do when it earns it** (e.g. before a future PC upgrade). **Goal:** relocate the whole stack to a
fresh Windows 11 box in ONE setup pass.

**STATUS (D-0068/D-0069/D-0070):** Stage-1 SHIPPED (`ops/setup/` config layer + `setup.ps1` + CPU-verify +
emitted download plan + `VERIFY-RUNBOOK.md`); the staging-plan URL/sha CONFIRM tool exists (2/2 VLM reachable;
4 LLM + SD1.5 `TODO_CONFIRM`; 2 missing sha); the additive+fallback `Resolve-LifeorchConfig` shim is wired
into #14/#16 and the interpreter-path resolver into #15/#16 (byte-identical on-box). KEY FINDING: repo-root is
ALREADY portable (every leaf uses a `$PSScriptRoot` walk-up; data-root lives centrally in
`modules/07/models.json`). RESIDUALS, each its own follow-on wave: (1) the shim across the remaining
model/GPU-bound leaves + `$PwshPath` defaults (~15 entrypoints); (2) apply `out/models.machine.json` into
`modules/07/models.json` under the gpu lease; (3) confirm the `TODO_CONFIRM` URLs + sha; (4) re-run
`setup.ps1 -Action gen` on a real target + finalize partial-offload `gpu_layers`; (5) core-infra (00.1 +
`ops/*.bat`) = single-worker.

- **Already travels:** the repo (modules/widgets/docs — plain pwsh + .NET + JSON, git-tracked).
- **Machine-wired, must be handled:** (1) the model + engine **DATA on F:** (gitignored, tens of GB); (2)
  **hard-coded absolute paths** (`C:/Users/just_/...` + `F:/My_Programs/...` in the executor, `models.json`,
  calibration/lease/plan dirs, generated worker prompts); (3) **GPU/CUDA specifics** (11 GB tuning, quants,
  `gpu_layers`, the b8661 + b10092 builds).
- **SCOPE (a scoped bring-up module, NOT a rewrite):** (a) a single configurable REPO-ROOT + DATA-ROOT; (b) a
  `setup.ps1` bootstrap (prereqs, stage/download models + engines, GPU detect, machine-specific
  `models.json`); (c) a VERIFY pass (heartbeat + strong-tier smoke + S0 6/6 calibration).
- **Effort scales with box similarity** — same layout ≈ copy + verify; a different machine is path-surgery +
  re-download + re-tune, still a bring-up, not a redesign.

---

## Built modules

Format: number · id · status (D-ref / commit) · terse scope + load-bearing gotchas · **follow-ons**
(deferred, not built). **Model ids, quants, licenses, engine builds, staging paths → `TOOL_MODEL_REGISTRY.md`;**
params/flags/artifacts → `modules/<NN>-*/README.md` + `skill.json`; test counts → `CURRENT_STATE.md`.

**0 `exec.bootstrap`** — Bootstrap Executor · MVP complete (P0). Filesystem-queue task packages: concurrent
isolated execution, restart recovery, single-instance lock. `control/heartbeat.json` + `control/last-exit.json`
let a supervisor tell hang/crash from an authorized stop (D-0013). **Job-runner (D-0047/48):** `dev.ship` =
ONE fail-closed job — sha256 → AST-parse → `test_argv` → commit only if green AND no unrelated staged files;
+ the `exec-job.sh` client. **Gotcha:** `device_bash` caps at ~45 s — long GPU jobs need `wait` re-polls.
**Follow-on:** emit a compact `CURRENT_STATE.json` byproduct.

**00.1 `exec.watchdog`** — Watchdog & Recovery · MVP complete (P0; D-0013). **Cooperative, session-scoped,
user-launched:** restarts the executor on crash/hang, **stands down** on a deliberate stop; + `ops/*.bat`.
Not perpetual — no boot persistence, visible, self-killable.

**1 `skill.bootstrap`** — Skill Contract & Registry · MVP complete (P0; D-0028). `SKILL_CONTRACT.md` v0.2, the
`skill.json` manifest, the result envelope, the wrapper `Invoke-Skill.ps1`. **Must not become a plugin
framework.**

**2 `fs.observer`** · **3 `proc.observer`** · **4 `uia.inspector`** — MVP complete. Listings/hashes/tree;
processes+windows; read-only UIA walk.

**5 `uia.actor`** — MVP complete (D-0011). UIA control patterns only — no synthetic input; `-DryRun`;
`parallel_safe:false` (first side-effecting skill).

**6 `capture.screen`** — MVP complete (D-0014). monitor/window/app/rect → GDI → PNG/JPG; read-only,
Per-Monitor-V2 DPI aware.

**7 `model.gateway`** — Local Model Gateway · MVP complete (D-0015/16). Local GGUF LLMs via `llama-server`
(`-Model`/`-Tier` from `models.json`); `parallel_safe:false`. Warm DETACHED server (D-0057; reuse ~1 ms);
`res.lease` gpu wired; `-Logprobs` both builds (D-0060). **Warm-pool arc (all default-OFF):** Stage-1 pool
manager (D-0067) -> Stage-1.1 hardening (D-0068) -> durable Job-Object supervisor (D-0069) -> the res.lease
GPU-lease-split primitive R1a/R1b/R1b' (D-0072/75) -> the R1b consumer wave + live proof (#7 0.5.0, D-0076)
-> the supervisor-hardening wave (#7 0.6.0, 10 must-fixes, D-0078) -> **as-built red-team GATE = NO (D-0079):
default-ON gates on i24 deterministic hardening + trusted deployment config + the #00.1 recovery driver (MF8)
+ trusted-hash provisioning (MF10) + an in-proc res.lease client + a grown soak.** Headline constraints
(`WARM_POOL_DESIGN.md` §6/§9): only ONE ~7 GB model fits the 11 GB GPU; swaps are GPU-upload-bound;
`--models-max` is NOT a VRAM oracle. **Native router = Stage-2+** (probe gated).

**8 `classify.batch`** — MVP complete (D-0017). classify/multilabel/extract via the gateway (`-Tier weak`,
temp 0); routes below-threshold to the review queue; confidence NOT calibrated. **Follow-ons:** warm-worker
batching; calibrated confidence; a `sort.files` mover.

**9 `review.processor`** — MVP complete (D-0018). Queue drainer: distilled item + bounded `source_ref` to a
stronger tier (never the whole batch, D-0007); in-place queue rewrite + `review_resolved.jsonl`.
**Follow-ons:** a frontier drain of `escalated`; compaction; warm worker; strong-tier prompt tuning.

**10 `audio.ingest`** — MVP complete (D-0019). ffmpeg/ffprobe wrap; whisper-ready defaults; `-Loudness`.
**Gotcha:** ffprobe = the SIBLING of resolved ffmpeg (Python-shim dodge). **Follow-ons:** batch; VAD/trim;
denoise.

**11 `speech.stt`** — MVP complete (D-0020). whisper-cli CUDA; normalizes via #10; confidence = mean token
`p`; `parallel_safe:false`. **Follow-ons:** warm server; batch; VAD/diarization; larger model + `tiers.stt`.

**12 `speech.tts`** — MVP complete (D-0021). Qwen3-TTS venv worker + **the D-0021 meta-file hand-off pattern
(reused by #14/#15/#16/#23/#24/#25)**. **Follow-ons:** warm worker; clone/design; batch; 1.7B tier; SSML.

**13 `voice.live`** — MVP complete (D-0022). File-driven STT → optional answer → optional TTS; live mic /
streaming is a non-goal. **Follow-ons:** mic capture + streaming; standalone VAD; multi-turn memory; a
warm-worker pool.

**14 `ocr.layout`** — MVP complete (D-0023). System `Windows.Media.Ocr` via a **Windows PowerShell 5.1
worker** (pwsh 7 cannot load the WinRT projection); per-word boxes + reading order; `parallel_safe:true`.
Tesseract installed, declared-not-wired. **Follow-ons:** second engine (Tesseract/VLM); overlay PNG;
multi-column reflow; batch/PDF.

**15 `image.util`** — MVP complete (D-0024). Deterministic metadata + sha256/pHash/dHash + resize/crop/
convert/tile; system python; `parallel_safe:true`. **Follow-ons:** a draw/annotate op (**blocks** the #16
overlay + #18 card); batch; rotate/auto-orient.

**16 `detect.objects`** — MVP complete (D-0025). YOLOX via onnxruntime; real per-detection confidence;
`parallel_safe:true` on CPU (`-Provider cuda|dml` is NOT). **Follow-ons:** overlay (needs #15 draw); batch;
RT-DETR; GPU/warm worker; tracking (#33).

**17 `image.interpret`** — MVP complete (D-0026). Local VLM caption/VQA/screen via #7's server in multimodal
mode; pure PowerShell wrapper; `parallel_safe:false`. **Follow-ons:** warm VLM server; calibrated confidence;
batch; multi-image; grounding boxes; 7B tier; second `ocr.layout` engine.

**18 `image.index`** — MVP complete (D-0027). Fuses #14-#17 (#15 ALWAYS); sequential children; envelope
confidence = min stage confidence. **Follow-ons:** concurrent children/warm pool; batch; cross-stage
grounding; overlay card; persist into #36.

**19 `logic.escalator`** — MVP complete (D-0030). Tier ladder with deterministic gates anchoring every rung;
a hard-fail overrides an LLM-judge accept. **KNOWN LIMIT (`m19-calib-002/003`):** 3-tier K=1 = 78.6% acc /
0.20 false-approval — does NOT reach the ~95% target (always-mid baseline 92.9%); see `CALIBRATION.md`.
**Follow-ons:** self-consistency veto + skeptical judges; higher floor / cost-aware early-stop; K>1 live
calibration; `unit_test` + retrieval gates.

**20 `doc.io`** — MVP complete (D-0031). read/write/edit/append primitive; atomic temp+rename; optional
`expect_sha256`; `before.<ext>` pre-image; **EOL preservation (CRLF stays CRLF)**; UTF-16 BOM detect; binary
refused; `doc:<path>` lease consumer. **Follow-ons:** batch/glob; regex/diff apply; structured-format edits;
rename/delete (gated); insert-at-line ops.

**21 `agent.local`** — MVP complete (D-0032). Bounded ReAct loop; decisions via #19 closed-set classify with
the in-set gate; **the closed `tools.json` registry IS the sandbox** (no arbitrary shell). `-Route` (D-0041);
the D-0046 deterministic terminator; `-AutoRamp` (D-0062). Governor: `ADAPTIVE_RESOURCE_GOVERNOR.md`.
**Follow-ons:** richer planning (sub-goals, reflection, DAG); more registry tools + per-tool schemas;
registry auto-discovery; batch multi-goal; calibrated decision confidence; persistent working-memory (wire
#42).

**22 `gen.audio`** — MVP complete (D-0033). Deterministic procedural ffmpeg synth (tone/chord/noise/sweep/
silence); `parallel_safe:true`; no neural stack staged. **Follow-ons:** a neural SFX tier (Stable Audio /
AudioGen — new stack); batch; envelopes; DTMF/Morse presets; stereo/binaural; pipe into #10.

**23 `gen.image`** — MVP complete (D-0034). SD 1.5 via diffusers venv worker; seed-reproducible;
`parallel_safe:false`. **SD 3.5 Medium fp16 quality tier shipped i17 (D-0070; `-Tier sd35`; NOT a clean 11 GB
fit — OOM ladder fallback).** **Follow-ons:** Z-Image-Turbo Q8 (needs stable-diffusion.cpp); FLUX.1-schnell;
SDXL; img2img/inpaint/ControlNet/LoRA; batch grids; warm pipeline worker; aesthetic confidence.

**24 `gen.music`** — MVP complete (D-0035). MusicGen Small (transformers-native, no new install); 1..30 s;
seed-reproducible; `parallel_safe:false`. **Follow-ons:** Medium/Large or Stable Audio Open; ACE-Step lead;
melody-conditioned; batch; warm worker; stereo; >30 s sliding-window; fp16.

**25 `gen.video`** — MVP complete (D-0036). AnimateDiff-Lightning 4-step on staged SD 1.5; silent clips;
seed-reproducible; `parallel_safe:false`. **Follow-ons:** LTX-Video/Wan2.1 leads (need newer HW for some);
img2video; ControlNet/motion-LoRA; interpolation+upscale; audio track; warm worker.

**26 `agent.coding`** — **DEFERRED (D-0037; work order authored, not built).** Bounded local coding loop
(draft → static-check → gated run). **Why deferred:** no safe code-exec substrate on this box (no WSL distro /
Sandbox / Docker; non-admin); lowest near-term ROI; without `code.run` it ≈ #21 + a lint tool. **Revisit-if:**
a safe substrate appears; a code-specialized local model is staged; Phase-B pull demand; the user asks.
**Interim:** add the deterministic `code.check` tool to #21's `tools.json`.

**27 `route.tools`** — MVP complete (D-0040). Request → minimal tool-id set; #7 MID tier + a deterministic
catalog GATE (injection-resistant). The which-tools pass of `route.tasks`.

**28 `fs.manage`** — MVP complete (D-0042). copy | move | mkdir; known-folder resolution (OneDrive-redirected
Desktop safe); overwrite-guarded; wired into #21 (`resolve_paths:false`). **Follow-ons:** delete/rename
(gated); directory ops.

**29 `res.lease`** — Resource Arbitration Lock/Lease · MVP complete (D-0053). Filesystem lease + TTL: the
**gpu lease** + **git/commit lock** + **`doc:<path>` ownership**; consumer trio complete (gpu→#7, git→dev.ship,
doc→#20). **The GPU-lease-split primitive is HARDENED + consumer-adopted + live-proven:** R1a 0.2.0 (fencing
tokens + exec/residency_pin split + evictor seam, D-0072) -> R1b 0.3.0 (three-identity fencing + atomic
transition) -> R1b' 0.4.0 (incarnation ids + two-phase transition-capability + target-fenced `fence-op` +
saga journal; adversarial matrix A-K 45/45; D-0075) -> the consumer wave (#7 0.5.0 + #21 0.2.0 + 0.4.1;
D-0076). Warm-pool default-ON gating: see #7.

**30 `orchestrate.fanout`** — MVP complete (D-0054). Plan/dispatch/collect over #29 with gpu+doc conflict
accounting. **Wave model + clamps owned by `FANOUT_ORCHESTRATOR_HANDOFF.md`.**

**31 `frontier.bridge`** — MVP complete (D-0055). The D-0052 human-courier bridge, automated: `pack` takes
`{prompt, files}`; `read-return` captures answers between markers.

**32 `media.decompose`** — MVP complete (Phase C pos 19; D-0069). Deterministic ffmpeg/ffprobe decompose:
meta always; `-Audio` (whisper-ready via #10); `-Keyframes N`; `-Scenes`; `parallel_safe:true`; ffprobe
sibling-resolution gotcha honored. **Follow-ons:** subtitle extraction; clip segmentation; low-res proxy;
batch; VAD; contact-sheet; any model/VLM frame interpretation (= `video.interpret`, pos 22).

**33 `track.objects`** — MVP complete 0.2.0 (Phase C pos 20; D-0070/D-0077). Deterministic per-class tracker
over #16-shape detections → identity tracks. **0.2.0 = the reviewed STABLE-IDENTITY tracker (default
`-Mode stable`; greedy retained byte-identical as the `-Mode greedy` oracle):** scene-boundary hard separation
(pre-first-scene `scene_index -1`); elapsed-time aging; deterministic global integer-Hungarian per class+scene
(**the lexicographic tie rule is contract**); gated centroid fallback; fixed-point (`score_unit millionths`,
integer ms); canonical JSON split from diagnostics. Probe: 0 false merges / 0 id switches. **Follow-ons:**
Kalman/constant-velocity; learned re-ID; optical flow; camera-motion compensation; interpolated coast boxes;
ByteTrack low-score recovery; live `#32->#16->#33` composition; **the dense low-res tracking-stream decision
gate (OPEN — decide before live-composition / `video.interpret` contracts freeze).**

**34 `video.timeline`** — MVP complete 0.1.1 (Phase C pos 21; D-0077). Deterministic per-source fuse of
manifest inputs (#32 scenes, #33 reviewed-schema tracks honored verbatim, #11 transcript, #14 OCR, #16
detections) → ONE canonical `lifeorch.video_timeline/0.1`: sampled / not-sampled / tracker-gap
distinguishable; appearance segmentation split at first-class gaps (never merged); canonical bytes split from
diagnostics; strict fail-closed validation (19+ refusal paths); `parallel_safe:true`. **Follow-ons:** live
composition; #36 integration; rendering/export; cross-video identity; versioned `quality_score`; the
dense-stream gate (shared with #33).

**35 `embedding.local`** — MVP complete 0.1.0 (i25, D-0082). Wires `embedding.qwen3-0p6b` (dim 1024) via a
transient CUDA transformers worker; DEFINES the embedding-provider interface (mock + real seam).
**Follow-ons:** batch throughput; a warm worker; alternate spaces (the space id is first-class in #36).

**36 `artifact.search`** — MVP complete **0.7.0** (i25→i39; D-0082/84/92/96/98/102/108). Deterministic SQLite
catalog + FTS5 hybrid retrieval + the s1 record envelope (`ingest_records` sink; typed records; float32 BLOB
vectors by embedding_space_id) + retriever-0.2 hits (span provenance) + the Tier-1 hierarchy node layer
(shortlist/descend/prune_verdict; safe-pruning no-false-negative certificates; ONE canonical `ns_permitted`)
+ `get-record` by-rvid + **fast-beam query-aware shortlist/descend ranking (0.7.0, RANKING-ONLY; hpr
58823->117647 ppm; flat byte-identical)**. **Follow-ons:** real-vector ANN search over stored embeddings;
docs-corpus onboarding (mandate-02 M2-C re-layer path); upper-level Bloom saturation is #40-beam-width-bound
(a #40 follow-on, NOT #36).

**37 `retrieval.eval`** — MVP complete (selpol 1.2.0 + eval 0.8.0; i25→i36; D-0082/86/89/91/96/100/102). The
canonical `selpol_rrf_v1` selection-policy library (CONTEXT_PACKET_CONTRACT s4 pins it); the retrieval-quality
benchmark (recall@K/MRR/stale/provenance); hierarchy-eval; the RUNNABLE ~200MB Tier-1 rehearsal harness
(op `rehearsal`, wired_descend drives #40's public port READ-ONLY; s10 criteria; FULL_CORPUS_RECIPE).
**IN FLIGHT (i40 Lane B, PB-5/D-0108):** the WIRED_STRUCTURAL_DIGEST re-pin + the manifest-version single
source of truth (skill.json 0.8.0 vs envelope 0.7.0 literals) + a permanent -Live drift assertion.
**Follow-ons:** scheduled rehearsal re-runs; corpus growth per FULL_CORPUS_RECIPE.

**38 `repo.intel`** — MVP complete 0.1.0 (i27, D-0084). Deterministic typed-record PRODUCER
(symbol/entity/relationship/skill/summary) emitting s1 envelopes; the sole `record_kind=skill` owner.
**Follow-ons:** more languages/extractors; incremental re-scan; edge enrichment.

**39 `episode.record`** — MVP complete 0.1.1 (i27/i28, D-0084/85). Episode + failure schemas + deterministic
recorder + the failure-signature seam; stages in `episode.body.stage_sequence` + `has_stage` edges.
**Follow-ons:** auto-recording from the executor/orchestrator paths; failure clustering; PB-2 delegation-
decision events as episode stages (D-0101).

**40 `context.compiler`** — MVP complete **0.9.0** (i29→i38; D-0086/87/91/98/100/104/106). Deterministic
three-region `context_packet/0.2` (control/evidence separation; disposition; consumer profile; identity/
lineage); imports the canonical selpol; the Tier-1 shortlist-and-descend PLAN + safe pruning + the REAL
hierarchy_port on the PUBLIC `-Retriever artifact_search` path (SEAM1 hydration + SEAM2 prune-cert); the
**R-1 born-instrumented multi-channel query ROUTER** (`multichannel_route_v1/1.0.0`, opt-in `-Route`;
integer-only ns-sanitized stage-trace; routing_policy id/ver + plan digest in packet identity); the
**working_memory region hydrated from #42** (conjunctive ns fail-closed byte-identical to absence;
state_version in identity; evidence-ineligible + can_instruct:false). A flat/legacy compile stays
byte-identical back through 0.7.0. **Follow-ons:** beam WIDTH (the fast-beam residual scale lever — Lane B
i39 measured upper-level Bloom saturation); router channel growth; consumer adoption (#21 wiring).

**41 `skill.card`** — MVP complete 0.2.0 (i29/i30, D-0086/88). Section-9 skill-activation cards
(`record_kind summary`/`summary_type skill_activation_card` + derives_from edges); `sklcard_` index; Stage-1
eligibility + Stage-2 lexical seam. **Follow-ons:** Stage-2 semantic retrieval; procedure promotion wiring.

**42 `working.memory`** — MVP complete 0.1.0 (i34, D-0099). Per-task working-memory STORE (MEMORY_CONTRACT A5
U3'): immutable versioned snapshots + CAS on parent_state_version (stale fails closed) + exactly-one active
head + fork/close/archive/promote + task_id+namespace isolation; search rejects `record_kind=working`.
**Follow-ons:** #21 consumer wiring; promote-to-durable flows; retention policy.

**43 `action.authz`** — **0.4.0 -> 0.6.0 SHIPPED; the P0-1 design gate is RATIFIED** (i37→i42; D-0103/104/106/107/109/111/113/115/116/117/118; the round-5 independent review returned PASS -> `p0_1_gate_status=pass`, activation still prohibited). The P0-1
deny-by-default action-authorization reference monitor (A01-A36 + Boundary A-D + U-properties) + injection
suite, built to the FROZEN `ACTION_AUTHORIZATION_CONTRACT.md`. DESIGN-ONLY: `non_execution:true` holds; A06
denies every authentic packet; `activation_status=prohibited`. **Taxonomy: `build_complete /
p0_1_gate_status=incomplete` — 0.5.0 (i41, `107c925`) builds the 7 D-0109 + 4 round-3 (D-0113) exact closures;
per mandate-02 M2-D, s7 ratifies ONLY on a ratification-review PASS; round-4 (pack `678163b1`) returned FAIL --
F1/F7 CLOSED (the manifest-derived pack rule proven), 3 seam findings -> the 0.6.0 unit (D-0116).**
**Follow-ons (activation-gating, staged):** real Windows permit-store IPC/ACL/CAS + crash recovery; per-tool
reparse/ADS/junction profiles; production store formats; freshness relaxation; the real
`non_execution=false` transition; timing-channel hardening; rollback.

**44 `project.map`** — MVP complete **0.2.0** (i48 D-0135; i46 base D-0130/D-0131; Nicholas's comprehension/bootstrap
reconstruction directive). The Project Comprehension Bootstrap (PCB): deterministic stdlib-Python+pwsh
compiler over canonical JSON map state (closed namespaces `module:`/`widget:`/`arch:`/`plane:`/`contract:`/
`doc:`/`store:`/..., per-FIELD provenance, coverage/staleness/conflicts FAIL-CLOSED) -> validated
`generated/BOOT_PACKET.md` (<=20 KB, section budgets + recorded ladder) + L0/L1/alias views; agent judgment
enters ONLY via versioned evidence-pointed claims (`claims/`); render refuses dirty/stale/skeleton/over-budget.
Built ALONGSIDE the legacy handoff (control); the i47 gate = **CONDITIONAL** (D-0133) -> the i48 CD closures
shipped (OPERATIONS boot canon; short-form/alias queries + evidence currency; the harvest sunset-fix); the
re-check (CD-1 probe -> CD-2 A/B) is pending; legacy default until pass (`eval/results/I47_RESULTS.md`). **Follow-ons:** FO-1 richer changed-since (git-driven
touch lists); FO-2 CURRENT_STATE.json generated from the overlay (post-pass); FO-3 map->#36 records (the
M2-C re-layer build); FO-4 shared-identity flow map->memory->packet->authz->audit (directive s13); FO-5
doc-gate rows if views promote into core-docs.

## Widgets (Phase B, `widgets/`)

- **01 Local Agent Console** — MVP complete (D-0039/D-0060). Drives #21; Auto-ramp toggle + governor trace.
  **Gotcha:** WinForms event scriptblocks lose builder scope — `$script:` state or `.GetNewClosure()`;
  mock/API gates do NOT catch rendered-UI bugs (human live-GUI pass required).
- **02 Module Launcher** — MVP complete (D-0049). Browses `modules/*/skill.json`; runs via the #1 wrapper.
- **03 Verification Console** — MVP complete (D-0050/51/64/65). The human-AUDIT surface: packet in, verdicts
  out; **durable verdicts** (results sidecar keyed by `packet_id`; the packet file is NEVER modified).
  **Residual:** the `model.gateway` GPU live-GUI pass (open since D-0060).
- **04 Fan-out Wave Dashboard** — MVP complete (D-0067/68). Read-only plan/worker/lease view; live-GUI
  confirm DONE (i15).
- **05 Provenance Map** — MVP complete (i36, D-0101/D-0102, `3ad71d3`; audit tier A1). Read-only construction
  map joining canonical docs + git trailers + plans + verdicts (what exists / new-since / verification /
  planned-but-unbuilt / over-budget flags). **Live-GUI confirm DONE (i43, D-0120).**
- **06 Compile Trace Console** — MVP complete (i38, D-0106, `c912854`; audit tier A1). Read-only renderer over
  compile/eval artifacts (4 packet regions + trust banners; selpol + R-1 router stage-traces; retrieval
  lineage; consumer_profile ledger; #42 state_version) + the compile-layer counterfactual runner (one varied
  input, zero model calls). **Live-GUI confirm DONE (i43, D-0120).**
- **07 Audit Timeline + Tournament** — MVP complete (i39, D-0108, `855c242`; audit tier A2). The s2.6
  tool-selection TOURNAMENT pane (elimination rounds + per-stage counts/reason-codes over the R-1 stage-trace
  + eligibility/selpol; counts reconcile) + the s2.1 cross-context OMNISCIENT stitched TIMELINE (episodes +
  plans + #42 state_version chains + batons-when-present). Read-only; holds no lease. **Live-GUI confirm
  DONE (i43, D-0120).** **i43 finding (D-0120):** 05/06/07 render but are expert-forensic + post-hoc, not
  the phenomenological pathway Nicholas needs to audit a live run -> the **Live-Run Audit Pathway (LRAP)** is
  the audit program's reprioritized next target (`research/2026-08-08-i43-live-run-audit-pathway-design.md`;
  the unbuilt A2 ride-along pause [s2.2] + A3 possession/side-by-side [s2.3/2.4] are its core, pulled
  forward; delegation possession still needs the local coordinator). **LRAP v1 (Widget 08, assembly-side replay) SHIPPED i45 (D-0122); the ride-along + OUTPUT side is the next increment.**
- **08 Live-Run Audit Pathway (LRAP)** — MVP complete (i45, D-0122, `a88e177`+`6028b9c`; audit phenomenological
  TOP surface, P9). Read-only STA WinForms over a REPLAYED #40 compile: steps 1-6 (normalize/retrieve/route/
  select/budget/packet) as ONE chronological plain-language INTENT/INPUT/OUTPUT/RECONCILE narrative; RECONCILE
  re-expresses ONLY a substrate-computed set/count/arithmetic verdict (no semantic judgment, F1), collapsed on
  first pass; the fixed per-step x per-lane HONESTY MAP renders every P2 cell as a visible "not emitted yet"
  lane (never faked); a pinned 06/07 reader ADAPTER + cross-widget contract test (recompute EXCLUDED); plain-
  language descend. Independently re-verified **87/0/0 -Live** (five-fixture machine classify 0 FP/FN).
  **Leveled Nicholas accept (D-0122): buttons + plausible-improvement/foundation PASS; whole-system + complete
  inclusion NOT YET** — v1 is assembly-side (input steps 1-6) only; the ride-along PAUSE hook + captured OUTPUT /
  instruction<->output reconciliation + possession/side-by-side are the deferred OUT set = the audit program's
  next increment. 05/06/07 are its expert-forensic descend target.
- **Doc-Health Monitor (audit tier A0.5)** — SHIPPED (D-0101). `ops/audit/gen-doc-health.py` → color-coded
  size-vs-quota HTML + a jsonl log row per close; zero doc-upkeep; regenerated each wave close. Feeds the
  mandate-02 M2-A gate (the monitor detects; the gate will refuse).
- **Backlog:** Voice Console · Generator Studio · Document Workspace · System/Executor Monitor.

---

## Architectural positions (pointers)

- **Video block 19-22:** positions 19/20/21 BUILT as `modules/32/33/34`; **22 `video.interpret`** is the LAST
  unbuilt video position (model lane; gated on the dense-stream decision, see #33).
- **Higher integration 23-26:** 23 `artifact.search` REALIZED as #36 · 24 `route.tasks` (partial: #27 is the
  which-tools pass) · 25 `observe.broker` (Proposed) · 26 `skill.orchestrator` (scoped slice built as #21;
  the full composer remains Proposed). The 0-49 spine + the autonomic layer: `ARCHITECTURE_MAP.md`.

## Adaptive Resource Governor (agent.local #21)

A behavior track over #21/#19/#7/#27, not a module. Live status: `CURRENT_STATE.md`. Design + measured truth:
`ADAPTIVE_RESOURCE_GOVERNOR.md` — read it before touching the governor, `-AutoRamp`, or `-Profile` behavior.
