# MODULE_ROADMAP

Owns **build order, per-module status, and the deferred follow-on menu** (the project's future-work list).
Not technical specs — each active module gets a `WORK_ORDER.md` in its own folder.
**Provisional beyond the first few items on purpose:** we do not lock thirty modules before using the
first five. Reorder freely as MVPs teach us what matters.

**Memory-subsystem build order (D-0090):** the Collective Agent memory subsystem follows the tiered plan in `MEMORY_ARCHITECTURE.md` s10 -- Tier 0 (invariants + seam repairs, DESIGN NOW: namespace-as-hard-boundary, hierarchy seam, working-memory seam, current-over-stale ranking; see `research/2026-08-03-memory-architecture-seam-audit.md` s3), Tier 1 (anti-deterioration foundation; the hierarchy nav layer + working-memory store BUILT i34, acceptance pending the ~200MB rehearsal), Tier 2 (operational memory formation), Tier 3 (advanced scale mechanisms, activate on measured need). Memory waves draw from that plan; this menu holds the rest.

**Status vocabulary:** Proposed · Ready · In progress · Blocked · MVP complete · Active · Needs refactor ·
Deprecated · Replaced.

**Owned elsewhere — pointers, not duplicated:** model/tool/hardware inventory → `TOOL_MODEL_REGISTRY.md` ·
now-summary + test table → `CURRENT_STATE.md` · review-queue schema + producer/consumer table →
`REVIEW_QUEUE.md` · orchestrator ops + wave model → `FANOUT_ORCHESTRATOR_HANDOFF.md` · governor design →
`ADAPTIVE_RESOURCE_GOVERNOR.md` · rationale → `DECISION_LOG.md` (index: `DECISION_LOG_INDEX.md`) · pre-consolidation
full text → `archive/`. Per-module params/artifacts → `modules/<NN>-*/README.md`.

---

## Build priority (2026-07-25 pivot — D-0029)

> **2026-07-31 (D-0080) -- REPRIORITIZED to the Collective Agent (cognitive virtual memory).** On Nicholas's
> directive (`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`) the build order pivots
> to the memory + retrieval + context + skill-activation + episodic/failure/procedure substrate that connects
> the existing Modules into one persistent agent. **PULLED FORWARD:** embedding adapter -> `artifact.search` MVP
> -> retrieval eval -> repo intelligence -> context compiler -> episodic/failure memory -> skill+procedure
> registry -> skill routing -> read-only Collective Agent slice -> sandbox coding worker -> sequential LOCAL
> orchestrator -> domain slices -> unified UI. **FROZEN/deferred:** supervisor/warm-pool hardening (D-0079
> GATE-NO stands; classic detached-warm is the trusted default), generators, `video.interpret` + live
> composition, real-time perception (27-49), broad training. **Wave 1 SHIPPED i25 (D-0082): #35 embedding.local + #36 artifact.search + #37 retrieval.eval; D-0077 smoke PASSED; memory red-team GO -> the record/provenance contract freeze (i26, D-0083). **Wave 2 (memory RECORDS) SHIPPED i27 (D-0084):** #36 artifact.search 0.2.0 (record-envelope + ingest_records SINK) + NEW #38 repo.intel + NEW #39 episode.record; D-0077 PASSED (2 bridged). **Wave-2 divergences RESOLVED i28 (D-0085): episode.record #39 -> 0.1.1 + MEMORY_CONTRACT Amendment A1 (v0.1.1); the re-smoke PASSED 0-bridging.** **Wave 3 (context compiler + skill retrieval) SHIPPED i29 (D-0086):** NEW #40 context.compile 0.1.0 (`b89eda0`) + #37 retrieval.eval ->0.2.0 (`dc293ef`; deterministic reranker) + NEW #41 skill.card 0.1.0 (`1eafd2c`); D-0077 PASSED on real data; design red-team (d57fead3) FOLDED (GO read-only, NO-GO freeze contracts). **i30 CONTRACT-HARDENING SHIPPED (D-0087/D-0088):** the context_packet/0.2 contract (NEW `CONTEXT_PACKET_CONTRACT.md` + MEMORY_CONTRACT A2/A3) + #40 0.2.0 (`f06e6e7`) + #37 0.3.0 (`99bb627`; `selpol_rrf_v1`) + #41 0.2.0 (`54c2e79`). D-0077 PASSED the #41->#36->#40 chain but CAUGHT a selpol divergence -> **i31 SELECTION-POLICY SETTLE** (D-0091) -> **i32/i33 TIER-0 SEAM REPAIRS** (namespace-closure + supersession; D-0092/95/96/97) -> **i34 TIER-1 SLICE SHIPPED (D-0098/D-0099, HEAD `ad20fa6`; the D-0077 hierarchy fold smoke PASSED 38/38):** the bounded-fanout HIERARCHY nav layer -- #36 artifact.search **0.5.0** (`356ab64`; node layer + shortlist/descend + safe-pruning Bloom presence_filter) + #40 context.compile **0.6.0** (`3968c96`; shortlist-and-descend PLAN + safe-pruning + retrieval_completeness; 322/322) + #37 retrieval.eval **eval 0.6.0** (`ad20fa6`; a SEPARATE hierarchy-eval, ADDITIVE; the ~200MB real-corpus rehearsal scaffolded+FLAGGED **OPEN** = the Tier-1 acceptance gate) -- PLUS NEW **#42 working.memory 0.1.0** (`601a2db`; the per-task working-memory STORE, realizes MEMORY_CONTRACT A5 U3'). **i35 CONSUMER WIRING CLOSED (D-0100, HEAD `58eedcb`; the D-0077 fold PASSED 32/32 + 38/38 + 35/35):** #40 context.compile **0.7.0** (`aa2f0fb`; the REAL hierarchy_port into the PUBLIC -Retriever artifact_search path + SEAM1 hydration + SEAM2 prune-cert; flat byte-identical to 0.6) + #37 retrieval.eval **eval 0.7.0** (`58eedcb`; NEW rehearsal_eval.py -- the RUNNABLE ~200MB Tier-1 acceptance-gate harness over a real click-8.1.7 sample + FULL_CORPUS_RECIPE). Project tier1_accepted STAYS FALSE (the full run vs #40's WIRED descend path is the i36 flip). **i36 TIER-1 ACCEPTED + CLOSED (D-0102, plan `fo-36-1a676e4b`, 3-lane CPU):** #37 retrieval.eval **eval 0.8.0** (`0e466bc`; opt-in `wired_descend` drives #40 0.7.0's WIRED descend port READ-ONLY + s10 vs the WIRED packets) + #36 artifact.search **0.6.0** (`16c27a8`; NEW `get-record` by-rvid READ op, closes i35's fold reconciliation) + NEW **widgets/05 Provenance Map** (`3ad71d3`; D-0101 audit tier A1, read-only construction map; human live-GUI confirm = OPEN). The orchestrator ran the FULL wired-descend rehearsal vs the FROZEN #40 0.7.0 over a DISTINCT hash-verified 6-package foreign corpus at a 100x leaf span -> **11/11 s10 criteria, 0 fold reconciliation -> project `tier1_accepted` FLIPPED TRUE** (evidence `research/2026-08-05-i36-tier1-acceptance-rehearsal.md`; honest caveat -- descend fast-beam lossy, the #36-flat fallback preserves recall, a follow-on). **i37 SAFETY + ROUTER wave CLOSED (D-0104, plan `fo-37-9995475a`, 2-lane CPU):** #40 context.compiler **0.8.0** (`392837a`; the OPT-IN multi-channel query ROUTER, BORN INSTRUMENTED per CONTEXT_PACKET_CONTRACT s9 / R-1; a flat/legacy compile BYTE-IDENTICAL to 0.7.0) + NEW **#43 action.authz** (`2ad0c6e`; the FROZEN `ACTION_AUTHORIZATION_CONTRACT.md` (D-0103) P0-1 deny-by-default reference monitor A01-A36 + injection SUITE MVP -- 66/66 M-* mutation-kills, 192/192, real #40 0.7.0 deterministic-denial; DESIGN-ONLY, non_execution holds). The D-0077 cross-module fold PASSED 13/13 (a real 0.8.0 routed + adversarial-stage-trace packet -> #43 monitor -> deterministic A06 DENY); the frontier freeze red-team folded GO-WITH-AMENDMENTS (the MVP is build_complete / `p0_1_gate_status=incomplete`; 7 amendments in `ACTION_AUTHORIZATION_CONTRACT.md` s6 -> a full gate). **i38 = the 7 P0-1 freeze amendments -> a full gate + the #40<->#42 working_memory wiring + the fast-beam recall follow-on + Widget 06 Compile Trace Console.** digest `research/2026-08-02-frontier-wave3-design-redteam.md`. Original scope: embedding adapter + `artifact.search`
> MVP + retrieval-eval harness** (+ optional memory red-team; `FANOUT_ORCHESTRATOR_HANDOFF.md` s4). 2080 Ti =
> build target, RTX PRO 6000 = horizon. Modules 0-34 + 00.1 + Widgets 01-04 remain BUILT; live status
> `CURRENT_STATE.md`.

**The per-module numbers are architectural positions, not a build sequence.** The full 0–49 spine (+ the
real-time autonomic layer 45–49 and the 6-level operating hierarchy) lives in `ARCHITECTURE_MAP.md`.
**Modules 0–34 + 00.1 are built; Widgets 01–04 are built.** The near-term order delivers a **locally usable
core** (cost-offload + a human interface) before the deep-research spine.

**Phase A — utility & cost-offload Modules — COMPLETE except the deferred coding agent:**
1. **`logic.escalator`** (D-0030) — generalizes `review.processor` #9 + `route.tasks` #24: the weakest model
   answers; each higher tier judges the tier below and either accepts it or produces its own for the next
   tier; stop when the step up would add no substantial gain. **Must** anchor rungs with deterministic
   ground-truth gates (schema / unit-test / retrieval / self-consistency), not LLM-judges-LLM alone, and be
   **empirically calibrated** before it is trusted — a ladder of N tiers can cost more than one correct call
   unless most tasks resolve low; target ~95% confidence, **not reached at MVP** (see #19). The single
   highest-leverage budget item — every task a local model finishes end-to-end is one the frontier
   allotment never pays for.
2. **`doc.io`** (D-0031) — cheap, deterministic, high-utility read/write/edit/append.
3. **`agent.local`** (D-0032) — a scoped #26: a local model that plans and invokes any Module through the
   escalator; the frontier agent's job, done locally.
4. **Generators, cheapest-first:** `gen.audio` (D-0033) → `gen.image` (D-0034) → `gen.music` (D-0035) →
   `gen.video` (D-0036). **Upgrade leads received (D-0068): image=Z-Image-Turbo Q8, music=ACE-Step 1.5, video=LTX-Video 2B Distilled, audio=Stable Audio 3 Small SFX; Diffusers-native starts SD3.5 Medium / Wan2.1 1.3B / Stable Audio Open 1.0 -- `research/2026-07-30-generator-model-leads.md`. Each upgrade is a follow-on GPU-lane wave. FIRST upgrade SHIPPED i17 (D-0070): SD 3.5 Medium fp16 quality tier in gen.image #23 (Diffusers-native runner-up); Z-Image-Turbo Q8 lead still needs stable-diffusion.cpp.**
5. **`agent.coding`** — **DEFERRED (D-0037**, work order authored, not built): last here; the frontier
   already codes well, and the useful slice is exactly the arbitrary-exec capability `agent.local`
   deliberately excluded. See #26.

**Phase B — Widget layer (`widgets/`)** — led by the Local Agent Console (the usability keystone). #1
Console (D-0039), #2 Module Launcher (D-0049), #3 Verification Console (D-0050/51) are MVP complete.
Backlog: **Voice Console · Generator Studio · Document Workspace · System/Executor Monitor** (the old
"Review / Escalation Dashboard" was reoriented into Widget #3, D-0050). Full list in `widgets/README.md`.

**Phase C — canonical spine UNDERWAY (D-0077):** video (19–22; #32 media.decompose + #33 track.objects (stable 0.2.0) + #34 video.timeline DONE; video.interpret pos 22 remains) → search/routing/orchestration (23–26) →
general-screen-perception + self-improving (27–44) → the real-time autonomic layer (45–49).

**Direction (D-0050):** past MVP the project drives ONE spine — the **offload / audit loop** under the
verify-cost rule (Claude offloads only what is cheaper to verify than to do; deterministic modules =
Claude's hands; model modules only where machine- or human-checkable). The multi-instance buildout needed a
resource-arbitration layer first: it shipped as `res.lease` #29 + `orchestrate.fanout` #30.

---

## BACKLOG — portability / new-machine bring-up

**Deferred; do when it earns it** (e.g. before a future PC upgrade) — captured now so it is READY to
execute then. **Goal:** relocate the whole stack to a fresh Windows 11 box in ONE setup pass.

**STATUS (i15, D-0068):** Stage-1 SHIPPED i14 (`ops/setup/` config layer + `setup.ps1` + CPU-verify + emitted download plan + `VERIFY-RUNBOOK.md`; `821da16`). i15 (`c0f8be0`) added a staging-plan URL/sha CONFIRM (`Confirm-StagingPlan.ps1`; 2/2 VLM reachable, 4 LLM + SD1.5 `TODO_CONFIRM`, 2 missing sha) and wired the additive+fallback `Resolve-LifeorchConfig` shim into `modules/14` + `16` (byte-identical on-box; cloud 119/119 + live 131/131). KEY FINDING: repo-root is ALREADY portable (every leaf uses a `$PSScriptRoot` walk-up; no hard-coded repo-root literal; data-root lives centrally in `modules/07/models.json`). RESIDUALS: (1) extend the shim to the remaining walk-up leaf modules (MANY model/GPU-bound -> non-CPU-lane waves); (2) apply `out/models.machine.json` into `modules/07/models.json` under the gpu lease; (3) confirm the `TODO_CONFIRM` URLs + add sha for the 1.5B/3B; (4) re-run `setup.ps1 -Action gen` on the real F: target (i14 gen used a mock `G:` root) + finalize partial-offload `gpu_layers` on a real new box. **i17 (D-0070): wired the additive+fallback interpreter-path resolver (system python) into `image.util` #15 + `detect.objects` #16 (`58870fb`; + `ops/setup/config.schema.json`); byte-identical on-box. Remaining: `$PwshPath` across model-bound entrypoints; core-infra (single-worker); the speech-venv interpreter (GPU-lane ride).**

- **Already travels:** the repo (modules/widgets/docs — plain pwsh + .NET + JSON, git-tracked) is fully
  portable.
- **Machine-wired today, must be handled:** (1) the model + engine **DATA on F:** (gitignored, tens of GB —
  re-staged/re-downloaded, never in git); (2) **HARD-CODED ABSOLUTE PATHS** —
  `C:/Users/just_/LifeOrchestrator-Refresh` and `F:/My_Programs/LifeOrchestrator-Refresh_Large_Data` are
  baked into the executor, `models.json`, the calibration/lease/plan dirs, and the generated worker prompts
  (a different Windows username or drive layout breaks them); (3) **GPU/CUDA SPECIFICS** — the RTX 2080 Ti
  11 GB tuning (quant choices, `gpu_layers`, context) + the two llama.cpp CUDA builds (**b8661** default,
  **b10092** for the 9B strong tier).
- **SCOPE (a scoped bring-up module, NOT a rewrite):** (a) a single configurable **REPO-ROOT + DATA-ROOT**
  (a `config.json` / env the modules resolve, replacing the scattered absolute paths); (b) a **`setup.ps1`
  bootstrap** that checks prereqs (pwsh ≥ 7.4, git, CUDA driver/toolkit, `curl.exe`), stages/downloads the
  models + engines to the data-root, detects the GPU, and writes a machine-specific `models.json` (paths +
  `gpu_layers` + quant sized to the card VRAM); (c) a **VERIFY pass** (executor heartbeat + a strong-tier
  smoke gen + the S0 6/6 calibration) confirming the new box is live.
- **Effort scales with box similarity:** same username + F: layout + similar-VRAM GPU ≈ copy the repo +
  F: data → start the executor → re-verify; a very different machine is path-surgery + re-download +
  re-tune — still a bring-up, not a redesign.

---

## Built modules

Format: number · id · status (D-ref / commit) · terse scope + load-bearing gotchas · **follow-ons**
(deferred, not built). **Model ids, quants, licenses, engine builds and staging paths are owned by
`TOOL_MODEL_REGISTRY.md`;** params/flags/artifacts → `modules/<NN>-*/README.md` + `skill.json`; test counts
→ `CURRENT_STATE.md`; pre-consolidation detail → `archive/`.

**0 `exec.bootstrap`** — Bootstrap Executor · MVP complete (P0). Filesystem-queue task packages: concurrent
isolated execution, restart recovery, single-instance lock. `modules/00-bootstrap-executor/`; running original
`proteus_repo/tools/trusted-bootstrap-executor/` `c4e90c4`. `control/heartbeat.json` +
`control/last-exit.json` (`stop_requested`|`signal`|`fatal_error`) let a supervisor tell hang/crash from an
authorized stop (D-0013). **Job-runner (D-0047/48):** `dev.ship` (`Invoke-DevShip.ps1`) = ONE fail-closed job
— sha256 → AST-parse → `test_argv` → commit only if green AND no unrelated staged files; + the `exec-job.sh`
client. **Gotcha:** `device_bash` caps at ~45 s and the executor cannot notify the harness — long GPU jobs
still need polls. **Follow-on:** emit a compact `CURRENT_STATE.json` byproduct.

**00.1 `exec.watchdog`** — Watchdog & Recovery · MVP complete (P0; D-0013, honors D-0001). **Cooperative,
session-scoped, user-launched:** restarts the executor on **crash or hang with no approval**, **stands down**
on a deliberate stop (honors `last-exit`); + `Recover-Executor` / `ops/*.bat`. **Not perpetual** — no boot
persistence, visible, self-killable. Hardened iter 3 (`e5b93ab`, TZ parse fix).

**1 `skill.bootstrap`** — Skill Contract & Registry · MVP complete (P0; D-0028). `SKILL_CONTRACT.md` **v0.2**,
the `skill.json` manifest, the `lifeorch.skill.result/0.1` envelope, artifact location, registry format, and
the wrapper `Invoke-Skill.ps1`. **Must not become a plugin framework.**

**2 `fs.observer`** — Filesystem Observer · MVP complete. Listings, discovery, change detection, metadata,
`tree.md`, `index.json` with hashes — no screenshots.

**3 `proc.observer`** — Process & Window Observer · MVP complete. Processes + top-level windows + foreground.

**4 `uia.inspector`** — UIA Inspector · MVP complete. Read-only UIA tree walk.

**5 `uia.actor`** — UIA Actor · MVP complete (D-0011). invoke/toggle/select/expand/collapse/setvalue/focus on
an element located by automation id / name / control type / inspector child-path. **UIA control patterns only
— no synthetic input**; kept separate from inspection; `-DryRun`/`-WhatIf`; `parallel_safe:false` (first
side-effecting skill).

**6 `capture.screen`** — Screenshot & Region Capture · MVP complete (D-0014). monitor / window / app / rect →
one virtual-desktop rect → GDI → PNG (or JPG q90). Read-only, Per-Monitor-V2 DPI aware.

**7 `model.gateway`** — Local Model Gateway · MVP complete (D-0015/16). Local LLMs (GGUF) via llama.cpp
`llama-server` (start → `/health` → `/v1/chat/completions` → kill), chosen from `models.json` by `-Model` id
or `-Tier` alias; `parallel_safe:false`. **Warm/persistent DETACHED server shipped** (Governor Phase 2, D-0057
`f8c961a`; warm reuse ~1 ms vs ~1200 ms cold); `res.lease` gpu wired (`0c6d5c9`); `-Logprobs` on both engine
builds (D-0060 `830efcc`). **Follow-ons:** the **warm multi-model pool + router — Stage-1 (mechanism C) SHIPPED opt-in/default-OFF i14 (D-0067, `09a7e71`, 0.3.0); Stage-1.1 hardening i15 (D-0068, `121a0fc`); the durable Job-Object gateway SUPERVISOR i16 (D-0069, `cc296fc`, `-UseSupervisor`); the res.lease fencing PRIMITIVE R1a 0.2.0 i18 -> R1b 0.3.0 i19 -> R1b' 0.4.0 i20 (D-0075); the R1b CONSUMER wave i21 (D-0076: #7 0.5.0 `-UsePoolLeaseSplit` + real evictor `lib/PoolEvictor.ps1` + live-GPU proof); the SUPERVISOR-HARDENING wave i23 (D-0078, `d289ba9`, #7 0.6.0 — the 10 i21-red-team must-fixes folded into the durable supervisor, MF10 partial, MF1+2 per-resident Job custody LIVE-PROVEN, finding 5 CLOSED). Warm-pool default-ON now gates ONLY on an in-proc res.lease client + a grown soak (MF8 #00.1 relaunch driver + MF10 ACL'd app-data/trusted-hash-manifest named residuals); native router still Stage-2+**
(`WARM_POOL_DESIGN.md`, D-0063 `c07125f`, + a couriered ChatGPT Pro second opinion as §9): Stage-1 =
**mechanism C** (the detached server becomes a NAMED POOL MANAGER `Ensure-ResidentModel` + residency-key +
task-affinity swap-minimising policy + whole-task gpu lease + a 90 s keep-resident window); Stage-2+ GATED
(native `--models`/`--alias` router probe, `--slot-save-path` save/restore, a coding specialist behind a
≥30-task benchmark). Headline constraints (that doc §6+§9): **only ONE ~7 GB model fits the 11 GB GPU at a
time**, swaps are GPU-upload-bound, `--models-max` is **not** a VRAM oracle (OOM risk).

**8 `classify.batch`** — Batch Classification & Sorting · MVP complete (D-0017). First gateway consumer:
`classify`/`multilabel`/`extract`, one call per item (`-Tier weak`, temp 0, fixed seed); routes
below-threshold items to the review queue and **suppresses** the gateway's own review writes; confidence is a
heuristic, **NOT calibrated**. **Follow-ons:** warm-worker / intra-batch prompt for throughput; calibrated
confidence; a `sort.files` mover.

**9 `review.processor`** — Review Queue Processor · MVP complete (D-0018). First queue drainer: feeds a
**stronger** tier (default `-Tier mid`) **only** the distilled item + a bounded `source_ref` fragment, **never
the whole batch** (D-0007), then resolves or escalates (`escalated_to:"frontier"` = a status transition, not a
frontier call); rewrites the queue **in place** (re-read-before-atomic-replace; flagging fields + malformed
lines verbatim) + append-only `review_resolved.jsonl`. `strong` is now the resident 9B (D-0062), not the 27B
it was tuned against. **Follow-ons:** a frontier drain of `escalated` items (routing #24); resolved-item
compaction; a warm worker; strong-tier prompt/`max_tokens` tuning for parseable verdicts.

**10 `audio.ingest`** — Audio Ingest / Normalize · MVP complete (D-0019). First skill to **wrap an external
binary** (`ffmpeg`/`ffprobe`): → wav/mp3/flac/opus/ogg/m4a + rate/channels/format + `-Loudness`
(`none`/`peak`/`ebu` R128); **defaults = whisper-ready 16 kHz mono s16 WAV**. **Gotcha:** `ffprobe` resolves
as the **sibling of the resolved `ffmpeg`** (dodges the Python `Scripts\ffprobe.exe` shim). **Follow-ons:**
batch/directory ingest; trimming/segmentation/VAD (→ #13); denoise/high-pass.

**11 `speech.stt`** — Speech-to-Text, timestamped · MVP complete (D-0020). Wraps `whisper-cli -ojf` (CUDA
build preferred, CPU fallback); **normalizes via `audio.ingest`** (`-Normalize auto|always|never`);
**confidence = mean whisper token probability `p`**; `parallel_safe:false` (binds CUDA). **Follow-ons:** a
warm whisper-server; batch/directory; VAD/diarization (→ #13); calibrated/semantic confidence; a
larger/multilingual model + `tiers.stt`.

**12 `speech.tts`** — Text-to-Speech (Qwen3-TTS CustomVoice) · MVP complete (D-0021). First skill to drive a
**Python model**: a venv worker + a pwsh wrapper reading the worker's **meta file** (robust to ML-library
stdout chatter) — **the D-0021 meta-file hand-off pattern, reused by #14/#15/#16/#23/#24/#25**.
**Follow-ons:** a warm TTS worker; voice clone/design; batch/long-form; the strong 1.7B tier; calibrated
confidence; SSML.

**13 `voice.live`** — Voice Interaction Loop · MVP complete (D-0022). Audio capstone: speech file → STT (zero
segments → `speech_detected:false`) → optional gateway answer (`-Respond`) → optional TTS reply
(`-Speak`/`-ReadbackTranscript`); children spawned as pwsh — **reimplements nothing**. **Live mic capture /
streaming is a non-goal** (file-driven MVP); standalone VAD deferred (no VAD ggml model staged).
**Follow-ons:** a mic `audio.capture` + streaming loop; standalone VAD (stage a model); multi-turn + memory; a
warm-worker pool so a turn avoids three cold model loads.

**14 `ocr.layout`** — OCR + boxes + reading order · MVP complete (D-0023). Per-word pixel boxes + lines in
reading order via system `Windows.Media.Ocr` (`MaxImageDimension=10000`); composes #6; `parallel_safe:true`;
confidence = a legibility heuristic (no per-word confidence exists). **Gotcha: pwsh 7 cannot load the WinRT
projection here** (`m14-probe-001`) — it runs in a **Windows PowerShell 5.1 worker**. **Tesseract is
installed** but declared-not-wired. **Follow-ons:** wire Tesseract or a VLM (#17) as a second engine; an
overlay PNG; `MaxImageDimension` downscale; multi-column reflow; batch/PDF OCR; calibrated confidence.

**15 `image.util`** — resize/crop/convert/meta/hash/similarity/tile · MVP complete (D-0024). First
**deterministic** perception skill: metadata + **sha256 + pHash + dHash** (64-bit, version-stable) always plus
one optional op; Pillow+numpy under the **system python**; `parallel_safe:true`. **NOT a `model.gateway`
model** — a tool, like ffmpeg for `audio.ingest`. **Follow-ons:** a draw/annotate op (**blocks** the #16
overlay and the #18 overlay card); batch/directory; rotate/flip/auto-orient.

**16 `detect.objects`** — object detection → class boxes + confidence · MVP complete (D-0025). First
**onnxruntime**-backed perception skill, with a **real** per-detection confidence (YOLOX objectness × class
prob); composes #6 and #15 (`-MaxDimension` downscale-then-rescale-boxes). `parallel_safe:true` on CPU —
**`-Provider cuda|dml` is NOT**. **Follow-ons:** an overlay/annotated image (needs the #15 draw op);
batch/directory; larger tiers / RT-DETR; GPU/warm worker; calibrated confidence; tracking (#20).

**17 `image.interpret`** — local VLM caption / VQA / screen interpretation · MVP complete (D-0026). Modes
`caption`|`describe`|`vqa`|`screen` on the same `llama-server` #7 drives, in **multimodal mode** (`--mmproj`
projector + an OpenAI-style base64 `image_url`), so the wrapper is **pure PowerShell**;
**`parallel_safe:false`** (binds a loopback port + CUDA/VRAM, unlike #14–#16). **Follow-ons:** a warm VLM
server; logprob/calibrated confidence; batch/directory; multi-image/multi-turn; open-vocab grounding boxes (a
#16 follow-on); a 7B tier / the transformers-venv backend; wiring the VLM as a second `ocr.layout` engine.

**18 `image.index`** — fuse #14–#17 → machine index + human card · MVP complete (D-0027). **#15 ALWAYS** +
optional `-Ocr`/`-Detect`/`-Interpret` (`-All`; `-Capture` via #6); children run **sequentially** (avoids VLM
VRAM/port contention); envelope confidence = the **min** stochastic-stage confidence (weakest link).
**Follow-ons:** concurrent children / a shared warm-worker pool; batch/directory; cross-stage grounding
(detections ↔ OCR ↔ caption); an overlay card image (needs the #15 draw op); persisting indices into
`artifact.search` (#23).

**19 `logic.escalator`** — Local Logic Escalator · MVP complete 2026-07-25 (Phase A #1; D-0030). A ladder of
local tiers via #7: the weakest answers, each higher tier judges and either accepts (stop; that layer is
fixed) or produces its own. **Guardrails honored:** deterministic gates anchor every rung (classify in-set
hard + self-consistency; extract JSON-schema + all-fields hard + source-grounding; generic ungated +
self-consistency); a hard-fail overrides an LLM-judge accept. **KNOWN LIMIT (`m19-calib-002/003`, still
true):** 3-tier K=1 = 78.6% acc / **0.20 false-approval** / −89% cost; 4-tier K=1 = 57.1%; **does NOT reach
the ~95% target** (always-mid baseline 92.9%) — see `CALIBRATION.md`. **Follow-ons:** raise strong-tier
`max_tokens` / a no-reasoning directive (D-0018); a self-consistency **veto** + skeptical judges (cut the 0.20
false-approval); a higher floor / cost-aware early-stop; live-calibrate K>1; `unit_test` + retrieval gates; a
`route.tasks` (#24) drain of `needs_frontier`.

**20 `doc.io`** — Local Document I/O · MVP complete 2026-07-25 (Phase A #2; D-0031). The
read/write/edit/append **text-document primitive** local callers use to do real file work; one op per
invocation (`read` takes a 1-indexed inclusive line range + `max_bytes` cap; `edit` is exact-string, default
exactly-one + `replace_all`/`expect_count`); `parallel_safe:false`; `res.lease` `doc:<path>` consumer wired
(`d2a7352`). **Safety (load-bearing):** atomic temp+rename writes; optional `expect_sha256` precondition; a
recoverable `before.<ext>` pre-image; **EOL preservation — a CRLF file stays CRLF** (the D-0018/core-docs
gotcha, generalized); UTF-8 default + UTF-16 BOM detect/preserve; binary refused. **Follow-ons:**
batch/directory/glob; a regex or unified-diff apply mode; structured-format (JSON/YAML/CSV) field edits; a
sibling `fs.manage` (**partly delivered as #28** — copy/move/mkdir; rename/delete still open); more encodings;
a read-only or per-file-lock `parallel_safe:true` mode + a tail/follow read; insert-at-line /
replace-line-range ops.

**21 `agent.local`** — Local Orchestrator / Agent · MVP complete 2026-07-25 (Phase A #3; D-0032). A **bounded
ReAct loop** — decide a Module, generate args, invoke, observe, repeat until `finish` or `max_steps`; a scoped
slice of `skill.orchestrator` (#26), not the video-block "21". Decisions go through #19 as a closed-set
`classify` whose deterministic **in-set gate** guarantees a valid action or surfaces `needs_frontier`; args +
final answer via #7; tools come from a **declarative closed registry** (`tools.json`) — **the registry IS the
sandbox, no arbitrary-shell / code-exec tool**. **Guardrails:** hard `max_steps` (default 4→**8**, D-0043);
`-DryRun` plan-preview; `needs_frontier` never triggers a frontier call. `-Route` (D-0041) =
route-then-constrained loop + a curated 10-tool registry; per-tool `resolve_paths:false` (D-0042). **The
D-0032 finding (weak/mid models UNDER-USE `finish` and run to `max_steps`) is FIXED** by the D-0046
deterministic terminator, reused by the contract-less `-AutoRamp` close (D-0062). Governor status: below.
**Follow-ons:** richer planning (sub-goals, reflection-retry, a planning DAG); more registry tools (perception
/ audio / generator Modules) with per-tool arg schemas; a `route.tasks` (#24) drain of `needs_frontier` goals;
registry auto-discovery from module manifests; a `batch` multi-goal mode; calibrated decision confidence;
persistent working-memory.

**22 `gen.audio`** — Local Audio Generation · MVP complete 2026-07-25 (Phase A #4; D-0033). Cheapest
generator: one **non-speech, non-music** primitive — `tone`/`chord`, colored `noise` (seeded → reproducible),
a linear `sweep`, or `silence` — as a **deterministic procedural ffmpeg synthesizer** (`-f lavfi`; codec map
== `audio.ingest`), `parallel_safe:true`. **Probe finding: no neural audio-gen stack is staged.**
**Follow-ons:** a **neural text-to-audio SFX tier** (AudioGen / AudioLDM / Stable Audio Open — install a stack
+ stage a model on F:; adds provenance + a real confidence + review-producer behaviour); batch / multi-signal
output; ADSR envelopes / per-partial amplitudes / detune; DTMF & Morse & metronome presets; a waveform option
for `sweep`; a guarded arbitrary-`aevalsrc` expression; stereo panning / binaural beats; a direct pipe into
`audio.ingest` for one-call loudness-normalized output.

**23 `gen.image`** — Local Image Generation · MVP complete 2026-07-25 (Phase A #4; D-0034). **First neural
generator**: prompt → one image via **Stable Diffusion 1.5** (`diffusers`, fp16, CUDA) through a Python
worker; fixed seed byte-reproducible on this GPU; `parallel_safe:false`. `diffusers` 0.35.2 went into the
speech venv **gated on a Module 12 safety re-verify**. An early standalone build of the #44 family — the
architectural "23" (`artifact.search`) is a different, later slot. **SHIPPED i17 (D-0070):** an SD 3.5 Medium fp16 quality tier (`-Tier sd35`; Diffusers-native; ~12 GB torch peak w/ offload, NOT a clean 11 GB fit — sequential-offload ladder fallback); SD1.5 kept the fast default. **Follow-ons:** heavier/faster tiers —
**FLUX.1-schnell** (Apache-2.0; needs offload/quant on 11 GB) and **SDXL / SDXL-Turbo** (non-commercial);
img2img / inpainting / ControlNet / upscaling / LoRA / DreamBooth; `num_images>1` batch + grids; a
warm/persistent pipeline worker; calibrated / aesthetic-model confidence; a real prompt-safety pass; more
schedulers / Karras sigmas.

**24 `gen.music`** — Local Music Generation · MVP complete 2026-07-26 (Phase A #4; D-0035). Prompt → one short
**instrumental** clip via **MusicGen Small**; **NO new library install** (transformers 4.57 already ships
MusicGen → Module 12 unaffected); 32 kHz mono PCM16 WAV, 1..30 s (~50 tokens/s), fixed seed byte-reproducible;
`parallel_safe:false`. **Follow-ons:** MusicGen **Medium/Large** or **Stable Audio Open**; **MusicgenMelody**
(melody-conditioned); batch / multi-clip; a warm/persistent pipeline worker; calibrated / aesthetic-model
confidence; a prompt-safety pass; stereo; **>30 s** via sliding-window continuation; fp16.

**25 `gen.video`** — Local Video Generation · MVP complete 2026-07-26 (Phase A #4; D-0036). Prompt → one short
**silent** clip via **AnimateDiff-Lightning** — a 4-step motion adapter on top of the staged SD 1.5 reused
from #23; **NO new library install** (MP4 via ffmpeg, GIF via Pillow); fixed seed byte-reproducible;
`parallel_safe:false`. Text-to-video folds into the #44 family — the ARCHITECTURE_MAP "19–22 video" block is
perception, NOT generation. **Follow-ons:** AnimateDiff full 25-step / SVD image-to-video / CogVideoX / LTX
(bf16 — **need newer HW**); img2video / video2video; ControlNet / motion-LoRA; frame interpolation +
upscaling; >~2 s via sliding-window; an audio track; a warm/persistent pipeline worker; calibrated /
motion-quality confidence; a prompt-safety pass.

**26 `agent.coding`** — Coding Agent · **DEFERRED 2026-07-26** (Phase A #5; D-0037; work order only —
build-ready design, NOT built). A bounded local coding loop (draft → statically check → (gated) run in a
scratch dir → read the error → fix → repeat), a specialization of #21.
- **Designed tools:** `code.write` (via #20, path forced under the scratch dir); `code.check` (a NEW
  deterministic static verifier — `py_compile`/`ast.parse`, PowerShell `Parser::ParseFile`, `node --check`; no
  execution); `code.run` (**GATED**: confined to the scratch dir, hard timeout, no network, needs an
  `-AllowRun` opt-in AND a resolvable safe substrate, else `execution_not_permitted`). No arbitrary-shell.
- **Why deferred:** (1) **no safe code-execution substrate exists on this box** (`m26-probe-001`: WSL launcher
  but no distro; Windows Sandbox absent + needs elevation on this non-admin box; Docker absent) — running
  local-model-authored code at full Windows-user authority is a safety escalation, and a real sandbox is a
  large, admin-gated, separate effort (D-0001); (2) lowest near-term ROI (weak local tiers are poor at code);
  (3) without `code.run` it is ~= #21 + a lint tool.
- **Revisit-if (any of):** a safe execution substrate (a WSL distro / Windows Sandbox enabled / a container
  runtime / a vetted restricted-runspace or job-object sandbox Module); a code-specialized local model staged
  + wired via #7; a warm gateway worker; Phase-B pull demand; the user asks. **Interim option (no module):**
  add the deterministic `code.check` tool to #21's `tools.json` — today's agent can then draft + syntax-check
  a script without the execution risk.

**27 `route.tools`** — Tool Router · MVP complete 2026-07-26 (D-0040). Request + the attachable-tools registry
→ the minimal tool-id set; fast, **NON-executing**: #7 at the **MID** tier with the validated router prompt
(`m27-router-001`), then a **deterministic GATE against the catalog** (injection-resistant — the request is
text and the gate drops any non-catalog id). The which-tools pass of `route.tasks` #24. **Note:** the original
hard refusal of `tier=strong` (the 27B emitted empty output) became a warn in D-0043; strong is now the
resident 9B (D-0062).

**28 `fs.manage`** — File Manage · MVP complete 2026-07-26 (D-0042). Deterministic last-mile placement —
**copy | move | mkdir** (one op/call); known folders
(desktop/downloads/documents/pictures/music/videos/home/temp via `[Environment]::GetFolderPath`, **so a
OneDrive-redirected Desktop resolves correctly**), `~`, `%ENV%`, absolute, relative; folder dest keeps the
source filename; overwrite-guarded. Wired into #21 via `resolve_paths:false` (a bare `desktop` is not prefixed
with `working_dir`) + a `route.tools` few-shot teaching "generate a file AND place it → two tools".
**Follow-ons:** `delete` / `rename` (gated); directory ops.

**29 `res.lease`** — Resource Arbitration Lock/Lease · MVP complete 2026-07-27 (D-0053, `36d7e0be`). **v0.2.0 R1a lease-split keystone i18 (D-0072, `e701328`, 74/74):** monotonic `fencing_token` + CAS; `exec` vs revocable `residency_pin` split with priority-revocation; a prepared-handoff/evict-before-grant PROTOCOL with a `none`/`mock`/`command` evictor seam (res.lease stays pure -- real nvidia-smi eviction = R1b); lock-order-inversion rejection + `-AllowLockOrder`; additive/default-off. Findings 13/14 primitive landed, primitive HARDENED across R1a 0.2.0 i18 -> R1b 0.3.0 i19 (three-identity fencing + scheduler-owned atomic transition + mock evictor) -> R1b' 0.4.0 i20 (D-0075, `f6df675`, red-team-driven: incarnation ids + two-phase transition-capability + target-fenced `fence-op` + idempotent saga journal + adversarial matrix A-K 45/45); **findings 1/13/14 CLOSE-ELIGIBLE at the lease/consumer layer (i21, D-0076)** -- the R1b CONSUMER wave shipped #7 0.5.0 (`-UsePoolLeaseSplit` + real evictor `lib/PoolEvictor.ps1`) + #21 0.2.0 (`-SplitLease`) + #29 0.4.1 + the live-GPU proof; warm-pool default-ON, after the SUPERVISOR-HARDENING wave shipped (i23, D-0078, `d289ba9`, #7 0.6.0; finding 5 CLOSED), now gates only on an in-proc res.lease client + a grown soak. A general
filesystem lease with a TTL — the multi-instance primitive: a **GPU lease** + a **git/commit lock** +
**`doc:<path>` ownership**. Consumer trio COMPLETE: gpu → #7 (`0c6d5c9`), git → `dev.ship` (`5530418`), doc →
#20 (`d2a7352`).

**30 `orchestrate.fanout`** — Fan-out Orchestrator · MVP complete 2026-07-27 (D-0054, `2ffe162e`). Runs
parallel Cowork worker sessions over #29 — plan / dispatch / collect with gpu + doc conflict accounting;
hardened by the iter-2 prompt-template fix (`581f854`) + iter-5 packet-input validation (`2afd5de`).
**Operations, the wave model and the ≤1-GPU-worker clamp are owned by `FANOUT_ORCHESTRATOR_HANDOFF.md`.**

**31 `frontier.bridge`** — Frontier Escalation Courier · MVP complete 2026-07-27 (D-0055, `f52f21d`). Packages
an escalation pack the human couriers to an off-box frontier model, and reads the answer back — the D-0052
manual bridge, automated. Hardened iter 4 (`b17a945`); used for the D-0061 model-selection report and the
D-0063 warm-pool second opinion.

**32 `media.decompose`** — Video Decompose · MVP complete 2026-07-30 (Phase C video spine STARTED; D-0069, `5026e2c`). NEW deterministic ffmpeg/ffprobe module — the video analog of `audio.ingest` #10 / `image.util` #15; `parallel_safe:true` (no CUDA/model/port). Ops: **meta** always (ffprobe show_format+show_streams -> container + per-stream codec/res/fps/pix_fmt/bitrate/channels/sample_rate); **-Audio** (composes #10 -> whisper-ready 16k mono s16 WAV); **-Keyframes N** (scene-preferred else evenly-spaced PNGs + sidecar); **-Scenes** (`{index,start,end,score}` + `-SceneThreshold`). **Gotcha reused:** ffprobe resolved as the ffmpeg SIBLING (the Python `Scripts\ffprobe.exe` shim). Gates 76/76 cloud + 76/76 `-Live`. Arch position 19. **Follow-ons (named, not built):** subtitle-stream extraction (srt/vtt); clip segmentation by scene; low-res proxy transcode; batch/directory; VAD segmentation; contact-sheet; ANY model/VLM frame interpretation (= `video.interpret`, arch #22).

**33 `track.objects`** — Object Tracking · MVP complete 2026-07-30 (Phase C video spine #20; D-0070, `3264dd5`). NEW deterministic module — per-class greedy IoU association over `detect.objects` #16-shape per-frame detections -> identity tracks (birth / coast [constant-position] / death lifecycle, monotonic ids); CPU-only, `parallel_safe:true` (no model/CUDA/port), byte-identical for identical input. MVP runs on JSON fixtures (decoupled — no live #16/#32). Gates 79/79 cloud + 79/79 `-Live`. Arch position 20. **0.2.0 (i22, D-0077, `b60340c`): the reviewed STABLE-IDENTITY tracker is the DEFAULT (`-Mode stable`); greedy retained BYTE-IDENTICAL as `-Mode greedy` (regression oracle).** Scene-boundary hard separation (`scene_boundary` deaths; #32 seconds-shape scenes; pre-first-scene `scene_index -1`); elapsed-TIME aging (`max_gap_ms` / `max_missed_samples`; timestamps REQUIRED in stable mode); deterministic GLOBAL per-class-per-scene integer-Hungarian assignment (pure pwsh, no SciPy; **the lexicographic tie rule is contract**); tightly-gated normalized-centroid fallback (two explicit tiers, IoU strictly outranks); fixed-point throughout (milli-pixel boxes, `score_unit millionths`, integer ms) + canonical JSON split from a diagnostics envelope; the richer schema (sample manifest + first-class gaps, never coast boxes + separated detection/association evidence; no aggregate confidence). Labeled 10-fixture probe: stable **0 false merges / 0 id switches**, beats greedy on within-scene gaps. Gates: greedy 78 + stable 76 + probe 15 cloud; 169/169 `-Live`; 11 cross-env hashes equal. `video.timeline` #34 0.1.1 consumes this contract exactly (i22 fold). **Follow-ons (named):** Kalman/constant-velocity; learned re-ID; optical flow; camera-motion compensation; cross-class alias families; interpolated coast boxes; cross-video identity; ByteTrack low-score recovery; a versioned `quality_score/N`; live `#32 -> #16 -> #33` composition; **the dense low-res tracking-stream decision gate (OPEN — decide before live-composition/`video.interpret` contracts freeze).**

**34 `video.timeline`** — Searchable Timeline Fuse · MVP complete 2026-07-31 (Phase C pos 21; D-0077, `e8583d1` + orchestrator fold `bad9e27` = 0.1.1). NEW deterministic CPU fuse: a per-source artifact MANIFEST (media meta REQUIRED; optional #32 scenes, reviewed sample manifest, reviewed-schema #33 tracks (`score_unit millionths` honored verbatim; `scene_index -1` valid; float mode fail-closes at score > 1), #11 transcript, #14 OCR (frame_index maps via samples else REFUSED), #16 detections) -> ONE canonical `lifeorch.video_timeline/0.1` timeline: coverage with sampled vs not-sampled vs tracker-gap DISTINGUISHABLE; per-track APPEARANCE SEGMENTATION split at first-class `track_gap` intervals (NEVER merged across a gap); content-canonical events (speech/ocr_text/detection_sample/scene_cut); a by_class/by_track/by_scene/by_kind index; separated detection/association evidence in q units; NO `confidence` field; canonical bytes split from a diagnostics envelope; byte-identical cross-machine. Strict fail-closed validation (19+ refusal paths); honest documented degradation modes; `parallel_safe:true`; pwsh-only. Gates: 138/138 cloud + 138/138 `-Live` + recon 20/20 (fixtures embed REAL #33 0.2.0 canonical bytes); 9 cross-env hashes equal. **Follow-ons (named):** live `#32->#16->#33->#34` composition; `video.interpret` pos 22 (model lane); `artifact.search` #23 integration; rendering/export; cross-video identity; `quality_score` (versioned); the dense-stream input-contract gate (shared with #33).

## Widgets (Phase B, `widgets/`)

- **01 Local Agent Console** — MVP complete 2026-07-26 (D-0039). Native WinForms (D-0038), drives #21;
  Plan/Run via #27 (D-0041); opt-in **Auto-ramp** toggle + a pre-frozen success-contract path field +
  governor-trace rendering (D-0060 `33da9a5`). **UI gotcha (D-0060, fix `b1f36f0`):** WinForms fires event
  scriptblocks OUTSIDE the form-builder scope, so controls referenced as bare function locals resolve to
  `$null` — use `$script:ConsoleState` or `.GetNewClosure()`. **Mock/API gates do NOT catch rendered-UI
  bugs** (the D-0049/D-0060/D-0064 lesson) — a human live-GUI pass is required.
- **02 Module Launcher / Registry Browser** — MVP complete 2026-07-27 (D-0049, `a699ac6`). Browses
  `modules/*/skill.json` + runs any Module through the Module 1 wrapper.
- **03 Verification Console** — MVP complete 2026-07-27 (D-0050/51, `f7e7b289`). The human-AUDIT surface of
  the offload/verify-cost spine (it replaced the old "Review / Escalation Dashboard" framing): Claude writes
  a verification packet, Nicholas runs + checks it locally through `Invoke-Skill.ps1` and exports a result
  Claude reads back. Iterated: teardown orphan-sweep (`033fd6f`), audit loop validated end-to-end
  (`174360d`), UX — packet discovery / by-kind item render / output locations (`206b2dd`, D-0064), verdict
  persistence moved from the untested shell into the WinForms-free core (`49f7feb`, D-0065), **durable
  verdicts** — autosave to a `runtime/results/` sidecar keyed by `packet_id` + auto-load the newest saved
  result on open, **the packet file NEVER modified (packet = spec, result = verdicts)** (`f3c1ec7`, D-0065).
  Live-confirmed working. **Residual noted in D-0060, never recorded as closed:** the widget-03
  `model.gateway` **GPU** live-GUI pass (open since D-0060, never closed).
- **04 Fan-out Wave Dashboard** — MVP shipped 2026-07-29 (D-0067, `333dac6`). Native read-only wave-status surface (WinForms-free core `WaveDashboard.psm1` + thin STA shell + dual-mode tests + `launch.bat`); parses the #30 plan dir + #29 leases dir; zero side effects. Gates: core 80/80 cloud + 90/90 `-Live` (STA SelfTest). **Human live-GUI confirm PENDING** (the D-0049/D-0060/D-0064 rendered-UI lesson).
- **05 Provenance Map** -- Proposed (D-0101; the audit-surface ENTRY VEHICLE, tier A1). Read-only native WinForms construction map that JOINS the canonical docs (MODULE_ROADMAP/CURRENT_STATE/DECISION_LOG_INDEX) + git dev.ship trailers + the HANDOFF ledger + `runtime/plans/<id>/` reports + Verification-Console verdicts: what exists (module->version->iteration->D-entry->commit->files) / what changed since iteration N / verification state / planned-but-unbuilt (+ auto-flags over-budget hot docs = PB-3 debt). Exclusive `widgets/05-provenance-map/`, docs:[], STRICTLY read-only (no doc/git/executor/model writes). A NON-DISPLACING i36 coding-lane candidate (the #40/#37/#36 memory sequencing keeps priority). Gates: renders from canonical on-disk docs + read-only git; deterministic parses w/ graceful degradation; "new since last visit" diff in its own runtime dir only. Design: `research/2026-08-05-interpretability-audit-surface-scoping.md` s4.
- **06 Compile Trace Console** -- Proposed (D-0101, tier A1; sequence i38 -- the R-1 router stage-trace it renders now EXISTS as of i37/D-0104, plus the i37 fold artifacts). Read-only renderer over compile/eval artifacts (the packet's 4 regions + trust banners; selpol ranked[]/reason_codes[]/stages[]/omission_manifest + R-1 router traces once they exist; classifier + temporal_intent incl. the override path; retrieval plan/stage lineage + V3 completeness/prune; consumer_profile token ledger; #42 state_version timeline) PLUS a compile-layer COUNTERFACTUAL runner (deterministic re-compile on the SAME pinned corpus/tree with ONE varied input -- channel mask / selpol version / namespace set / temporal_intent / budget / excluded rvid -- then diff packets; ZERO model calls). Exclusive `widgets/06-compile-trace-console/`, docs:[], read-only. Gates: byte-identical re-render; ablation reconciles with #37 hybrid attribution; renders REAL artifacts; i33 sanitization honored. Design: scoping s5 + `research/2026-08-05-audit-pipeline-target.md` (A1).
- **Doc-Health Monitor (audit tier A0.5) -- SHIPPED (D-0101).** `ops/audit/gen-doc-health.py` (+ `ops/gen-doc-health.bat` click-to-run) -- a READ-ONLY generator that reads `wc -c core-docs/*.md` + the DOC_PROTOCOL s2 budgets + `workers-i*.json` / frontier-pack sizes and emits `ops/out/doc-health-monitor.html` (color-coded doc size-vs-quota per Nicholas's green/yellow/red rule + per-iteration worker-context growth) + appends a snapshot row to `ops/out/doc-health-log.jsonl`. Zero doc-upkeep; the orchestrator regenerates it at each close (HANDOFF wave-loop); folds into the audit sub-agent wrap when memory/audit matures. The pre-native-Widget-07 stopgap.
- **Backlog:** Voice Console · Generator Studio · Document Workspace · System/Executor Monitor.

---

## Modules 19–22 — Video (architectural positions; deferred to Phase C)

**Architectural positions** (`ARCHITECTURE_MAP.md`), NOT build-order folder numbers — Phase A pulled
`logic.escalator` into `modules/19-logic-escalator/`. The video block takes its own next-free folder numbers
when built. **19 `media.decompose`** audio/subs/scenes/keyframes/clips/meta/proxies (**BUILT i16 as `modules/32-media-decompose`, D-0069**) · **20 `track.objects`** identity across frames (**BUILT i17 as `modules/33-track-objects`, D-0070** — greedy-IoU MVP baseline; roadmap in `research/2026-07-30-track-objects-design-review.md`) · **21 `video.timeline`** transcription + scenes + OCR + keyframes + detections +
tracks → a searchable timeline (**BUILT i22 as `modules/34-video-timeline`, D-0077**) · **22 `video.interpret`**
selective frames/clips → local VLM (the LAST unbuilt video-block position).

## Modules 23–26 — Higher integration (provisional, later)

**23 `artifact.search`** search over all local-skill artifacts · **24 `route.tasks`** model/tool task router
(type/confidence/quality/cost/time) · **25 `observe.broker`** route a desktop-observation question across
fs/proc/UIA/OCR/recognition/screenshot · **26 `skill.orchestrator`** compose skills into workflows without
embedding each implementation in frontier context.

---

## Adaptive Resource Governor (agent.local #21)

A behavior track over #21/#19/#7/#27, not a module. Live status: `CURRENT_STATE.md`. Design + measured
truth (phases, epochs, calibration, ceilings, open items): `ADAPTIVE_RESOURCE_GOVERNOR.md` — read it before
touching the governor, `-AutoRamp`, or `-Profile` behavior.
