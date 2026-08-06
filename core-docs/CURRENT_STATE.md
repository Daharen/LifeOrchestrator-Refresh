# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture, not history. Keep it compact.

History lives elsewhere: **`DECISION_LOG.md`** (read **`DECISION_LOG_INDEX.md`** first, pull by ID), **git**, and
**`archive/`**. **Rule: NEVER grow `[prior]` accretion chains** — replace a stale statement in place, cite `D-####`
if the reason matters. A `CURRENT_STATE.json` counterpart is planned, not yet created.

Owned elsewhere, don't duplicate: `TOOL_MODEL_REGISTRY.md` (tools/models/hardware) · `MODULE_ROADMAP.md` (build
order/status/follow-ons) · `REVIEW_QUEUE.md` (queue) · `FANOUT_ORCHESTRATOR_HANDOFF.md` (orchestrator ops) ·
`ADAPTIVE_RESOURCE_GOVERNOR.md` (governor) · `ARCHITECTURE_MAP.md` (destination).

## Phase + active work

- **Phase (D-0080): building the Collective Agent.** On Nicholas's directive
  (`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`) the project pivots from
  breadth-first Module/Widget expansion to connecting the existing ~35 Modules + 4 Widgets into ONE persistent
  agent on **cognitive virtual memory**: external authoritative memory (repo/SQLite/artifacts) + disposable
  model contexts; a deterministic coordinator hands a model a small task-specific packet; specialists execute;
  evaluators verify; success becomes reusable procedure. Nicholas is manager. RTX 2080 Ti (one ~7 GB resident; a
  9B executive) = build target; RTX PRO 6000 (96 GB) = horizon.
- **Direction (extends D-0050):** the offload / verify-cost AUDIT LOOP still holds -- offload only what is
  cheaper to VERIFY than to do; deterministic modules are Claude's hands, model modules only where machine- or
  human-checkable. D-0080 adds the memory/retrieval/context substrate that makes it cumulative.
- **Long-horizon MEMORY ARCHITECTURE adopted as the DESIGN TARGET (D-0090):** `MEMORY_ARCHITECTURE.md` (governing) + `MEMORY_BENCHMARK.md` (validation) + the seam audit `research/2026-08-03-memory-architecture-seam-audit.md`. Total stored memory may grow indefinitely while ordinary working context stays BOUNDED -- via an immutable lossless substrate + typed memory + a bounded-fanout hierarchy + multi-path query-aware retrieval + consolidation + procedural promotion, all reconstructable to source; the 9B supplies only PROVISIONAL validated content over a DETERMINISTIC skeleton. EVIDENCE-STAGED (Tiers 0-3; design-now vs build-now). Tier 0 = design-now invariants + seam repairs (URGENT lock-in: namespace-as-hard-boundary; the hierarchy seam; a per-task working-memory store; current-over-stale + supersession-aware ranking -- seam audit s3). This SUBSUMES the earlier index/hot-doc compression framing: the ceiling is removed structurally, not by shrinking budgets.
- **Wave 1 (memory substrate) SHIPPED (i25, D-0082); CONTRACT FREEZE (i26, D-0083, `core-docs/MEMORY_CONTRACT.md`).** #35 embedding.local + #36 artifact.search + #37 retrieval.eval; the record+provenance envelope v0.1 + embedding 0.2 + retriever 0.2 + gates are frozen.
- **Wave 2 (memory RECORDS) SHIPPED (i27, plan fo-27-bab47060, D-0084), built to MEMORY_CONTRACT 0.2:** #36 artifact.search 0.1.0->**0.2.0** (record-envelope + generic `ingest_records` SINK + records/record_edges + schema_version 2 in-place migration + parser/chunker/extractor fingerprints + retriever-0.2 hits [span object+label, per-channel scores, opaque score retired] + s5 staleness enum + float32 LE BLOB vectors keyed on embedding_space_id + catalog hardening) + NEW #38 repo.intel (deterministic typed-record PRODUCER: symbol/entity/relationship/skill/summary) + NEW #39 episode.record (episode+failure schemas + deterministic recorder + failure-signature seam). The D-0077 fold smoke PASSED (repo.intel 198 records + episode/failure -> #36 0.2 ingest_records -> retrieval + provenance [content_hash==file sha256; cited span reproduces source] + idempotent re-ingest, catalog_digest stable) and CAUGHT+BRIDGED 2 producer/consumer divergences (episode.record `episode_stage` kind not in the frozen s1 enum; status object-vs-string -- see Unresolved questions). **i28 (D-0085) SETTLED the contract:** episode.record #39 -> 0.1.1 (status -> the s5 string; `episode_stage` retired -> stages in `episode.body.stage_sequence` + `has_stage` edges) + MEMORY_CONTRACT Amendment A1 (v0.1.1); the D-0077 re-smoke PASSED 30/30 (0 bridging, 0 rejections). **Wave 3 (context compiler + skill retrieval) SHIPPED (i29, plan fo-29-87dbfa0b, D-0086):** NEW context.compiler #40 `context.compile` 0.1.0 (`b89eda0`; deterministic `lifeorch.context_packet/0.1`) + retrieval.eval #37 0.1.0->**0.2.0** (`dc293ef`; s6 eval-0.2 + a deterministic reranker) + NEW skill.card #41 0.1.0 (`1eafd2c`; section-9 cards + `sklcard_` s1 skill index + Stage-1 eligibility + Stage-2 lexical seam). The D-0077 fold smoke PASSED on real data (#41->#36 ingest-records 40 accepted/0 rejected; #36 retriever-0.2->#40 packet 3 excerpts all provenance-reproduced, budget 1190/1200; #36->#37 -Live recall@1/MRR/nDCG@3=1.0; P0-5 sklcard_/derived vs skl_/canonical_source coexist NO collision). The frontier design red-team (pack d57fead3) FOLDED: GO for the read-only build, NO-GO for FREEZING the new contracts, NO-GO for side-effecting until the SAFETY-CRITICAL P0-1 (control-plane-vs-evidence separation) is enforced. **i30 CONTRACT-HARDENING SHIPPED (D-0087 contract + D-0088 wave, plan fo-30-dd453156):** the context_packet/0.2 contract (NEW `core-docs/CONTEXT_PACKET_CONTRACT.md` + MEMORY_CONTRACT A2/A3) + the conformance wave -- #40 context.compiler 0.2.0 (`f06e6e7`; three-region control/evidence packet + disposition + consumer profile + selpol seam + identity/lineage) + #37 retrieval.eval 0.3.0 (`99bb627`; the `selpol_rrf_v1` selection-policy library) + #41 skill.card 0.2.0 (`54c2e79`; record_kind skill->summary). The D-0077 fold PASSED the #41->#36->#40 chain (40/40 summary ingested; #38 sole skill owner; a valid context_packet/0.2 with P0-1/P0-3/P0-4) but CAUGHT a selpol producer/consumer divergence (#40 reference vs #37 canonical select differently). **i31 SELECTION-POLICY SETTLE (D-0089/D-0091), i32/i33 TIER-0 SEAM REPAIRS (namespace-closure + supersession; D-0092/95/96/97), then i34 TIER-1 SLICE CLOSED (D-0098/D-0099, HEAD `ad20fa6`; the D-0077 hierarchy fold smoke PASSED 38/38):** shipped the bounded-fanout HIERARCHY nav layer (#36 0.5.0 `356ab64` + #40 0.6.0 `3968c96` + #37 eval 0.6.0 `ad20fa6`) PLUS the per-task WORKING-MEMORY store (NEW #42 0.1.0 `601a2db`, realizes A5 U3'); Tier-1 ACCEPTANCE gated on the ~200MB real-corpus rehearsal (scaffolded+FLAGGED OPEN, #37 tier1_accepted=false on synthetic). **i35 CONSUMER WIRING CLOSED (D-0100, HEAD `58eedcb`):** #40 0.7.0 (`aa2f0fb`) wired the REAL hierarchy_port into the PUBLIC `-Retriever artifact_search` path (SEAM1 hydration + SEAM2 prune-cert) + #37 0.7.0 (`58eedcb`) shipped the RUNNABLE ~200MB Tier-1 acceptance-gate rehearsal harness; the D-0077 fold PASSED (wired public port 32/32 + i34 regression 38/38 + rehearsal 35/35). Project `tier1_accepted` stays FALSE -- the FULL run against #40's WIRED descend path is an i36 flip. **i36 TIER-1 ACCEPTED (D-0102, plan `fo-36-1a676e4b`):** Lane A #37 eval 0.8.0 (`0e466bc`; wired-descend drive) + Lane B #36 0.6.0 (`16c27a8`; `get-record` by-rvid) + Lane C NEW widgets/05 Provenance Map (`3ad71d3`; D-0101 audit A1). The orchestrator ran the FULL wired-descend rehearsal vs the FROZEN #40 0.7.0 over a DISTINCT 6-package foreign corpus at a 100x leaf span -> **11/11 s10 criteria, project `tier1_accepted` FLIPPED TRUE** (honest caveat: the descend fast-beam is lossy, the indexed #36-flat fallback preserves recall -- a follow-on). The action-authorization contract freeze design is IN HAND (couriered frontier answer, CONDITIONAL GO). **i37 CLOSED (D-0104):** the born-instrumented query ROUTER (#40 0.8.0, R-1; flat byte-identical to 0.7.0) + the P0-1 action reference monitor + injection SUITE MVP (NEW #43; 66/66 mutation-kills, 192/192; built to the FROZEN ACTION_AUTHORIZATION_CONTRACT, design-only, non_execution holds) shipped; the D-0077 cross-module fold PASSED 13/13; the frontier freeze red-team folded GO-WITH-AMENDMENTS (the MVP is build_complete / gate incomplete -- 7 i38 amendments -> a full gate). **NEXT = i38** (see Next expected action).
- **FROZEN / deferred (D-0080):** further durable-supervisor / warm-pool hardening (keep classic detached-warm
  as the trusted default; the D-0079 GATE-NO stands -- revisit only if a defect threatens the baseline or it
  blocks the memory work); generator upgrades; model-heavy `video.interpret` + live composition; deep real-time
  perception (arch 27-49); broad training.
- **Fan-out loop: iterations 1-23 DONE + the i24 frontier lane** (D-0055..D-0080) via `orchestrate.fanout` #30
  over `res.lease` #29, workers hand-dispatched into fresh Cowork sessions. Ledger + wave model:
  **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **Boundary (D-0051, amended by D-0080):** the orchestrator never drives another *external/frontier* AI session
  (that stays human-couriered); a future deterministic LOCAL coordinator IS authorized to spawn fresh local
  contexts + invoke local models (Priority 10).

## Adaptive Resource Governor (agent.local #21)

Design + rationale: **`ADAPTIVE_RESOURCE_GOVERNOR.md`**. Runtime facts:

- Phase 1 DONE (D-0043): the DECISION floor is **mid-only (3B)** — a low `[tiny,weak,mid]` floor made the 3B
  judge-and-anchor on weak answers. Phase 2 DONE (D-0057, warm server); Phase 3 Stage-1 (D-0059) + the Stage-2
  slice (D-0060) DONE.
- **`-AutoRamp` is DEFAULT-ON (D-0062).** Monotonic model-affine epochs **M0 -> M1 -> S0**; the deadline-gated
  **X0/27B** one-shot recovery rung is opt-in via **`-AllowLegacy27B`**. `-NoAutoRamp` / `-AutoRamp:$false`
  reproduce the strict floor byte-for-byte.
- Closing: a goal with a **pre-frozen `lifeorch.goal_verification/0.1` success contract** closes on the
  contract; a **contract-less** goal closes via the **D-0046 terminator** (M0 closes once >=1 required
  side-effecting tool succeeds). The D-0061 contract-less loop-to-max_steps regression is FIXED (D-0062).
- **`-Profile floor` is the reliable end-to-end path** (`frugal|floor|max`). **Open residual: `-Profile max` does
  NOT land** — at `gen_tier=strong` the 9B arg-gen returns non-JSON (`arg_parse_failed`) every step (a 9B/gateway
  defect, NOT the terminator; measured on Q4, not re-tested since Q5_K_M — D-0046/D-0062).
- Opt-in logprob-entropy soft signal (clean per-token logprobs on BOTH builds b8661 + b10092, D-0060);
  `-AutoRamp` is exposed in the Local Agent Console (widgets/01) as a toggle + trace render.

## Model stack (full inventory: `TOOL_MODEL_REGISTRY.md`)

- **Strong tier = `llm.strong.qwen3p5-9b` — Qwen3.5-9B Q5_K_M, GPU-resident** (~7.11 GB, `ngl 99`; 2902 MiB free
  @ctx 8192, probe `m10-warmpool-probe-002`) -> **GPU-bound ~68 tok/s** (at Q4), clean terse JSON. Q4->Q5_K_M for
  fidelity + KV headroom (D-0062); live S0 6/6 @2048 tok. **Q4 retained `wired:false`** = one-flip rollback.
- **Engine:** the 9B is a hybrid attention-SSM arch **b8661 cannot load**, so its entry pins `engine_path` to
  a side-by-side **llama.cpp b10092 (CUDA 12.4, self-contained)**; **every other tier stays on b8661**.
- **`no_think: true`** on the 9B entry -> the gateway appends ` /no_think`; without it the default flags leave
  reasoning ON and it returns empty content at `finish=length`.
- **The 27B is RETAINED but validated IMPRACTICAL (D-0061):** no Qwen3.5-27B quant fits GPU-bound on 11 GB —
  confirmed by the couriered frontier report (`core-docs/research/2026-07-28-frontier-local-model-selection.md`).
  Reachable via `-Model` / the X0 rung only; the resident 9B is the effective top rung.
- **Decision floor = mid (3B)**; strong is GENERATION-only.
- Warm multi-model pool: Stage-1.1 hardened (i15, D-0068) + a **DURABLE gateway supervisor shipped i16 (D-0069,
  `cc296fc`, skill 0.4.0) — still DEFAULT-OFF** (see Known failures): `WARM_POOL_DESIGN.md` (mechanism C; §6/9/10).
  Measured: one ~7 GB model fits the GPU at a time; swap GPU-upload-bound (~1.6 s->3B, ~4.1 s->9B); same-model
  reuse ~1 ms; all GGUFs (28.5 GiB) fit 64 GB RAM.

## Repo / working dirs

- **Repo (canonical):** `C:\Users\just_\LifeOrchestrator-Refresh\` — git-initialized; `core-docs/` +
  `modules/<NN>-<name>/` + `widgets/<NN>-<name>/` + `archive/`.
- **Large-data home:** `F:\My_Programs\...\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\`; shared
  llama.cpp engines under `_engines\`.
- **Reference sources (NOT built here):** the earlier `LifeOrchestrator\repo` (fold in later) + the **Project
  Proteus** game (`Project-Proteus-src`).
- The attached Claude Project **mirrors** `core-docs/`; disk wins on disagreement.

## Executor status

- MVP complete, **running**. `modules/00-bootstrap-executor/` (pwsh 7.4.6, host `DESKTOP-PF5FFMF`). Current
  instance **`f74a3ebb…` (pid 37260)**, continuously up, **`degraded:false`**.
- Markers: `runtime/control/heartbeat.json` (health fields `degraded` / `poll_error_streak` /
  `stuck_finalize_count`) + `last-exit.json`. **Trust the heartbeat, not the process list.**
- **Watchdog (#00.1) is available but session-scoped, not persistent** (D-0013): launch
  `ops/start-watchdog.bat` before any long unattended wave.
- Crash history: a transient file-lock crash 2026-07-24, now **self-healed in-process** (Known failures);
  and a **wedge** from an orphaned llama-server holding a `running/` file (D-0055/D-0056), closed by iter-3
  hardening + launching persistent servers DETACHED (D-0057).
- **Model servers: `model.gateway` #7 keeps a DETACHED warm `llama-server`** (residency-key match under the
  `res.lease` **gpu** lease; D-0057; warm reuse ~1 ms vs ~1200 ms cold) — not torn down per call. **Optional durable
  supervisor (i16, D-0069, default-OFF):** `Start-GatewaySupervisor.ps1` owns the tree in a Windows Job Object,
  surviving across invocations (`-UseSupervisor`). **`image.interpret` #17 is still transient.** Any persistent
  server launches detached + is reaped before finalize; assert 0 UNMANAGED orphans every wave.

## Completed modules

Detail + follow-ons per module: `MODULE_ROADMAP.md`; producer status: `REVIEW_QUEUE.md`; invocation +
registry facts: `TOOL_MODEL_REGISTRY.md`. Roster (all MVP-complete unless noted):

- **Infra:** #0 exec.bootstrap (+ the `dev.ship` job-runner, D-0048) · #00.1 exec.watchdog · #1
  skill.bootstrap (contract v0.2) · #29 res.lease (gpu/git/doc leases; consumer trio complete; **v0.2.0 R1a (i18) -> v0.3.0 R1b (i19) -> v0.4.0 R1b' primitive hardening (i20)** -- fencing/three-identity fencing + exec/revocable residency_pin split + incarnation ids (owner_incarnation_id/resident_instance_id) + exec_lease UUID + two-phase transition-capability (no grant-before-ready) + target-fenced `fence-op` + idempotent saga journal + lock-order rejection; findings 13/14 primitive HARDENED, still OPEN pending the R1b CONSUMER wave) · #30
  orchestrate.fanout · #31 frontier.bridge (`pack` takes `{prompt, files}` — NOT `{task,...}`, D-0057).
- **Observation/UIA:** #2 fs.observer · #3 proc.observer · #4 uia.inspector · #5 uia.actor · #6 capture.screen.
- **Model core:** #7 model.gateway (detached warm server D-0057; warm pool Stage-1.1 hardened + durable supervisor default-OFF, D-0068/D-0069) · #8 classify.batch · #9 review.processor ·
  #19 logic.escalator · #20 doc.io (+ additive portability resolver shim, i16 D-0069) · #21 agent.local (`-Route`, D-0046 terminator, `-Profile`, `-AutoRamp`;
  the closed `tools.json` registry IS the sandbox) · #27 route.tools · #28 fs.manage.
- **Audio:** #10 audio.ingest · #11 speech.stt · #12 speech.tts · #13 voice.live.
- **Perception:** #14 ocr.layout · #15 image.util · #16 detect.objects · #17 image.interpret · #18 image.index.
- **Generators (user track):** #22 gen.audio · #23 gen.image (+SD 3.5 Medium fp16 tier, i17) · #24 gen.music · #25 gen.video.
- **Video spine (Phase C, UNDERWAY):** **#32 media.decompose** (deterministic ffmpeg/ffprobe decompose —
  meta/audio/keyframes/scenes; composes #10; `parallel_safe:true`; arch 19, D-0069) · **#33 track.objects**
  (deterministic per-class greedy-IoU tracker over #16-shape detections -> identity tracks, birth/coast/death +
  monotonic ids; `parallel_safe:true`; MVP on fixtures; arch 20, D-0070). **#34 video.timeline** (deterministic per-source fuse: manifest ->
  canonical searchable `lifeorch.video_timeline/0.1` timeline; appearance segmentation split at first-class
  gaps; sampled/not-sampled/tracker-gap distinguishable; `parallel_safe:true`; arch pos 21, i22 D-0077).
  **#33 0.2.0 (i22) IS the reviewed stable-identity tracker** (`-Mode stable` default; greedy = `-Mode greedy`
  oracle; `score_unit millionths`; pre-first-scene `scene_index -1`; #34 0.1.1 consumes that contract
  exactly -- proven on real bytes). Next: `video.interpret` (pos 22), Proposed; the dense-stream decision
  gate (Unresolved questions) precedes any live-composition input-contract freeze.
- **Collective Agent memory substrate (Wave 1, D-0080/D-0082 — NEW):** **#35 embedding.local** (wires `embedding.qwen3-0p6b`, dim 1024, transient CUDA transformers worker; DEFINES the embedding-provider interface) · **#36 artifact.search** (deterministic SQLite catalog + FTS5 hybrid-lexical search; Markdown-aware chunking; result->source+content_hash+span provenance; incremental reconcile + DB integrity; mock+real embedding seam; PRODUCES the retriever interface) · **#37 retrieval.eval** (retrieval-quality benchmark: recall@K/MRR/stale/provenance; BM25-lite baseline; external-retriever fold seam). The D-0077 embedding->artifact.search->benchmark cross-module smoke PASSED. Governing: `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`; **contract `MEMORY_CONTRACT.md` (0.2 freeze, D-0083)**; red-team `research/2026-08-01-frontier-memory-redteam.md`; ship-states `fanout/WAVE1-MEMORY-i25-SHIP-STATE.md` + `fanout/WAVE2-MEMORY-i27-SHIP-STATE.md`. **Wave 2 (i27, D-0084):** #36 -> **0.2.0** (record-envelope + `ingest_records` SINK + retriever-0.2 hits + float32 BLOB vectors + catalog hardening) + NEW **#38 repo.intel** (deterministic typed-record producer: symbol/entity/relationship/skill/summary; emits s1 record-envelope artifacts) + NEW **#39 episode.record** (episode+failure schema + deterministic recorder + failure-signature seam); the D-0077 Wave-2 fold PASSED (2 divergences bridged); **i28 (D-0085) conformed #39 -> 0.1.1 (status s5 string; `episode_stage` retired -> stages in-body) + MEMORY_CONTRACT A1 (v0.1.1); the re-smoke PASSED 0-bridging.** **Wave 3 (i29, D-0086):** NEW **#40 context.compiler** (`context.compile`; deterministic `lifeorch.context_packet/0.1` -- normalize/retrieve/rerank/budget/packet+expand+eval-hooks) + **#37 retrieval.eval 0.2.0** (s6 eval gates + a deterministic reranker, MEASURED vs raw order) + NEW **#41 skill.card** (section-9 cards + `sklcard_` s1 skill index + Stage-1 eligibility + Stage-2 lexical seam; #38 boundary). The D-0077 fold smoke PASSED on real data; the frontier design red-team (pack d57fead3) FOLDED (D-0086) -- GO for the read-only build; i30 CONTRACT-HARDENING SHIPPED (D-0087/D-0088; #40 0.2.0 + #37 0.3.0 + #41 0.2.0; context_packet/0.2 + selpol_rrf_v1); the D-0077 fold caught a selpol divergence -> NEXT = i31 selection-policy settle. Digest `research/2026-08-02-frontier-wave3-design-redteam.md`.
- **NOT built:** #26 agent.coding — designed + DEFERRED (D-0037; no safe code-exec substrate on this box).
- **Widgets (native + `launch.bat`, D-0038):** 01 Local Agent Console · 02 Module Launcher · 03 Verification
  Console (**durable verdicts** — results sidecar keyed by `packet_id`; the packet file is never modified, D-0065) · **04 Fan-out Wave Dashboard** (read-only plan/worker/lease view; D-0067; live-GUI confirm DONE i15 D-0068).

**Phase A complete** (0–25 + 00.1; #26 deferred); generator track #22–#25 complete; **Phase B Widgets 01–04
shipped; Phase C video spine STARTED (#32).**

## Installed dependencies (verified on this machine)

- **PowerShell 7.4.6** — a .NET global tool at **`C:\Users\just_\.dotnet\tools\pwsh.exe`**. The **latest**
  `PowerShell` global-tool package is malformed (no tool manifest) — **pin a version**.
- **.NET SDK 9.0.100** (`C:\Program Files\dotnet\dotnet.exe`) · **git** on PATH · **winget** present ·
  **choco** absent. **Not admin. No system-wide `pwsh`** — only the user `~\.dotnet\tools` entry.
- **ffmpeg / ffprobe 8.1** (Gyan.dev `full_build`), `ffmpeg` on PATH at
  `C:\Users\just_\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe`; full encoder set (libmp3lame, aac,
  flac, libopus, libvorbis, pcm_*). **`ffprobe` on PATH is shadowed by a Python shim — see Known failures.**
- **WinForms + STA runspace** work in the dotnet-tool pwsh (an STA runspace hosts a Form + `Application.Run`).
- **Windows PowerShell 5.1** (`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`, 5.1.19041.6456)
  — the ONLY runtime here that can load the WinRT `Windows.Media.Ocr` projection (pwsh 7.4.6 cannot); the
  `ocr.layout` #14 worker. **5.1 reads a BOM-less `.ps1` as ANSI — see Known failures.**
- **Windows.Media.Ocr** (system WinRT OCR) — words + `BoundingRect` + reading-order lines + `TextAngle`;
  `en-US`; `MaxImageDimension=10000`; ~74 ms on a 700x220 fixture. No install/admin/GPU/network.
- **Tesseract OCR** at `C:\Program Files\Tesseract-OCR\tesseract.exe` — **installed**, **declared not
  wired** (`ocr.tesseract`), a future second `ocr.layout` engine. No Python OCR libs in either venv.
- **Pillow + numpy** — **system python** `…\Python312\python.exe`: PIL 10.2.0 + numpy 1.26.4 + cv2 4.9.0;
  **speech venv** (F:): PIL 12.2.0 + numpy 2.4.4 — the numpy-DCT pHash is identical across both. `image.util`
  #15 uses the **system python** (CPU-only -> genuinely parallel-safe, not CUDA/venv-bound).
- **onnxruntime** — system python: onnxruntime-gpu 1.17.1 + onnxruntime-directml 1.17.1 + torch 2.2.1 +
  torchvision 0.17.1. `detect.objects` #16 requests **`CPUExecutionProvider`** by default.
- **diffusers 0.35.2 in the speech venv** (`F:\...Local_Computer_Speech_Large_Data\python_env`: torch 2.11+cu128,
  transformers 4.57.3, accelerate, safetensors, torchvision 0.26, `qwen_tts`) powers `gen.image`/`gen.video`; added
  only diffusers+importlib_metadata+zipp (Module 12 safe). The **system python is torch 2.2.1+cpu (no CUDA)** —
  image/video gen runs under the speech venv only. **i17 added `sentencepiece` 0.2.2** to the speech venv for the SD 3.5
  T5 tokenizer (torch/transformers/diffusers/qwen_tts UNCHANGED — Module 12 safe).

## Installed local models (summary)

Full inventory — paths, sha256, licences, quants, tuning: **`TOOL_MODEL_REGISTRY.md`** + `models.json`.
Models live in per-owning-module F: homes under `…_Large_Data\` (D-0028); engines under `_engines\`
(**b8661** = every tier but the 9B; **b10092** = the 9B only). Decision-relevant facts:

- **strong** = `llm.strong.qwen3p5-9b` — Qwen3.5-9B **Q5_K_M**, 7.11 GB, GPU-resident, `no_think`, b10092;
  the Q4 entry is retained `wired:false` = one-flip rollback (D-0062).
- **mid (3B) = the decision floor**; tiny 0.5B / weak 1.5B for bulk work.
- The **27B is retained but impractical** (D-0061): `-Model` / `-AllowLegacy27B` only; `-LoadTimeoutSec ~300`;
  `gpu_layers` tuned 32 (see `TOOL_MODEL_REGISTRY.md`).
- Non-LLM models (whisper STT, Qwen3-TTS x2, YOLOX x2, VLM, SD 1.5, MusicGen, AnimateDiff-Lightning,
  embedding) are `wired:false` **for the gateway** by design — each resolved by its owning module
  (D-0020/23/25). The embedding model is staged but **unwired** (awaits artifact.search).
- **`gen.image` #23 gained an SD 3.5 Medium fp16 QUALITY tier (i17, D-0070)** alongside legacy SD1.5 (default stays
  `image.sd15`): Diffusers-native `StableDiffusion3Pipeline` on the speech venv 0.35.2 (NO new engine); fp16 + model
  CPU offload + VAE tiling, T5-XXL CPU-side, seed-reproducible; 15.16 GB on F: (6 safetensors sha256-verified;
  `image.sd35-medium`, `-Tier sd35`). **CAVEAT: NOT a clean 11 GB fit** — torch VRAM peaks ~12.06 GB (T5 fp16 spike ->
  NVIDIA driver system-RAM fallback); the sequential-offload OOM ladder is the guaranteed fallback. ~92 s cold / ~43 s
  warm @768². Paths/sha in `models.json` + `TOOL_MODEL_REGISTRY.md`.

## Available hardware (measured 2026-07-24)

- **CPU** Intel i9-9900KF (8c/16t @3.6 GHz) · **RAM** 64 GB · **GPU** NVIDIA RTX 2080 Ti **11 GB VRAM** (CUDA,
  driver 591.74, cc 7.5) · **OS** Windows 10 Pro 19045 x64. Host `DESKTOP-PF5FFMF`, user `just_`.
- **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**), E: "Game Drive" 858 GB (~534 GB free),
  **F: "Storage space" 3.72 TB (~1.78 TB free)** = the large-data home. (No D: on this box.)
- Full profile + runtimes in `TOOL_MODEL_REGISTRY.md` (Hardware profile).

## Known working invocation paths

- **Every module:** `pwsh -NoProfile -File modules\<NN>-<name>\Invoke-<Name>.ps1 <named params>` (or
  `-InputsJson '<json>'`), or via the Module 1 wrapper `pwsh -NoProfile -File
  modules\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir <dir> [-InputsJson '<json>']`. Per-module parameters:
  each module's `README.md` / `skill.json`; model resolution: `TOOL_MODEL_REGISTRY.md`.
- **Through the executor:** submit a task package whose `task.ps1` calls either entrypoint; the envelope lands
  in `runtime/completed/<task_id>/stdout.txt`.
- **Executor control** (from `modules/00-bootstrap-executor/`): `Start-BootstrapExecutor.ps1` /
  `Submit-BootstrapTask.ps1` / `Stop-BootstrapExecutor.ps1`.
- **Job-runner** (`modules/00-bootstrap-executor/exec-job.sh`): `devship <id> <inputs.json> <timeout>` ships a
  unit; `run <id> <timeout> <task.ps1> <maxwait> "<desc>"`; `wait <id>` re-waits a long/GPU job (device_bash
  caps at ~45 s).
- **Direct pwsh:** `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- **User ops (click-to-run):** `ops/*.bat` — start/stop/restart/status the executor, run tests; output to
  `ops/out/`. **Watchdog:** `ops/start-watchdog.bat` / `stop-watchdog.bat` / `recover-executor.bat [-Force]`,
  or `modules\00.1-exec-watchdog\Watch-Executor.ps1` / `Recover-Executor.ps1`.
- Examples: `07-model-gateway\Invoke-ModelGateway.ps1 [-Model <id>|-Tier tiny|weak|mid|strong] -Prompt '<s>' [-MaxTokens -Temperature -TopP -TopK -Seed]` · `21-agent-local\Invoke-AgentLocal.ps1 -Goal '<s>' -Route [-Profile frugal|floor|max] [-NoAutoRamp] [-AllowLegacy27B] [-DryRun]` · `32-media-decompose\Invoke-MediaDecompose.ps1 -Path <video> [-Audio] [-Keyframes N] [-Scenes] [-SceneThreshold f]` · `06-capture-screen\Invoke-CaptureScreen.ps1 [-Target monitor|window|app|region] [-Monitor index|all|primary] [-Format png|jpg]`.

## Current tests

Standing gates, in order: **(1) the off-machine cloud gate FIRST** (pwsh 7.4.6 on Linux; the real skill where
portable, a mock worker/child where not), **(2) `-Live` on the Windows executor**, **(3) `dev.ship`** (sha256 +
AST + tests, fail-closed). **Mock/API gates MISS rendered-UI defects and real-model failures**
(D-0049/D-0060/D-0064) — **any UI change needs a human live-GUI confirm before it is called done.** Every
`models.json` change re-verifies Module 7 (28/28); every live run asserts **0 orphaned `llama-server`/python**
and `review_queue.jsonl` before==after.

Suite = `modules/<NN>-<name>/tests/Invoke-<Name>Tests.ps1` (widgets: `widgets/<NN>-<name>/tests/`; one
exception: #31 = `tests/Test-FrontierBridge.ps1`). Dates 2026.

| unit | last result | task / commit | date |
|---|---|---|---|
| #0 executor | 16/16 | `e5b93ab` | 07-28 |
| #0 dev.ship / exec-job | 39/39 + 24/24 | `5530418` | 07-27 |
| #00.1 exec.watchdog | 33/33 | `e5b93ab` | 07-28 |
| #1 / #2 / #3 / #4 | 11/11 · 16/16 · 16/16 · 16/16 | — | 07-24 |
| #5 uia.actor | 26/26 | `m5-test-001` | 07-24 |
| #6 capture.screen | 39/39 | `m6-test-001` | 07-24 |
| #7 model.gateway | supervisor-hardening (i23, 0.6.0): 366 off-machine + 74 on-box real-custody green; + base 42/42 warm 23/23 pool 43/43 lease-split 63/63 + live split proof (i21) | `d289ba9` | 07-31 |
| #8 classify.batch | 33/33 | `m8-test-001` | 07-24 |
| #9 review.processor | 34/34 | `m9-test-003` | 07-24 |
| #10 audio.ingest | 43/43 | `m10-test-001` | 07-24 |
| #11 speech.stt | 27/27 | `m11-test-001` | 07-24 |
| #12 speech.tts | 25/25 | `m12-test-001` | 07-24 |
| #13 voice.live | 21/21 | `m13-test-001` | 07-24 |
| #14 ocr.layout | 30/30 | `m14-test-003` | 07-25 |
| #15 image.util | 54/54 (48 + interpreter-shim) | `58870fb` | 07-30 |
| #16 detect.objects | 44/44 `-Live` (40 cloud; +interpreter-shim) | `58870fb` | 07-30 |
| #17 image.interpret | 48/48 `-Live` | `m17-test-001/002` | 07-25 |
| #18 image.index | 41/41 `-Live` (40/40 cloud) | `m18-test-002` | 07-25 |
| #19 logic.escalator | 28/28 `-Live` (24/24 cloud) | `m19-test-001` | 07-25 |
| #20 doc.io | 106/106 (+ portability resolver shim, ops/setup 140/140 `-Live`) | `d2a7352` / `8274b9f` | 07-30 |
| #21 agent.local | 102/102 + AutoRamp 122/122 + **autoramp-split 22/22** (`-SplitLease`, i21, autoramp 0.2.0) | `0877c70` | 07-31 |
| #22 gen.audio | 43/43 (41/41 cloud) | `m22-test-001` | 07-25 |
| #23 gen.image | 50/50 mock cloud + 50/50 on-device (SD3.5 fp16 + SD1.5 live) | `980dd6d` | 07-30 |
| #24 gen.music | 42/42 `-Live` (49/49 cloud) | `m24-test-002` | 07-26 |
| #25 gen.video | 46/46 `-Live` (54/54 cloud) | `m25-test-002` | 07-26 |
| #26 agent.coding | not built (designed, D-0037) | — | 07-26 |
| #27 route.tools | 33/33 | `e444851` | 07-28 |
| #28 fs.manage | 21/21 off-machine (on-target verify `m29-verify-001` 25/25) | `m29-after-003` | 07-26 |
| #29 res.lease | 74/74 + 36/36 v0.3 + 45/45 v0.4 `-Live` (0.4.1 i21: command-evictor `tree_gone` passthrough to the transition result + txn journal; behavioral assertions unchanged) | `0877c70` | 07-31 |
| #30 orchestrate.fanout | 71/71 `-Live` | `2afd5de` | 07-28 |
| #31 frontier.bridge | 65/65 + hardened return-capture | `f52f21d`/`b17a945` | 07-28 |
| #32 media.decompose | 76/76 cloud + 76/76 `-Live` | `5026e2c` | 07-30 |
| #33 track.objects | 0.2.0: greedy 78 (0.1.0 assertion set, `-Mode greedy` pinned) + stable 76 + probe 15 cloud; 169/169 `-Live`; 11 cross-env hashes equal | `b60340c` | 07-31 |
| #34 video.timeline | 0.1.1: 138/138 cloud + 138/138 `-Live` + recon 20/20 (cloud + `-Live`); 9 cross-env hashes equal | `e8583d1`/`bad9e27` | 07-31 |
| widgets/01 Agent Console | 91/91 `-Live` (89/89 cloud) | `b1f36f0` | 07-28 |
| widgets/02 Module Launcher | 75/75 `-Live` (64/64 cloud) | `c509e571` | 07-27 |
| widgets/03 Verification Console | 173/173 cloud mock + live STA SelfTests (`SELFTEST_VERDICT_PERSIST_OK`, `SELFTEST_AUTOLOAD_OK`) | `f3c1ec7` | 07-29 |
| ops/setup portability | 161/161 cloud + 175/175 `-Live` (+interpreter shim) | `58870fb` | 07-30 |
| widgets/04 Fan-out Wave Dashboard | 80/80 cloud + 91/91 `-Live` (+SELFTEST_LAYOUT_OK); live-GUI confirm DONE | `8c1da2e` | 07-30 |
| #35 embedding.local | 0.1.0: 42/42 (26 off-machine mock-seam + 16 `-Live` GPU); det cos_dist 2.2e-16, batch==single 8.7e-13; 0 orphans; Module 7 re-verified 42/42 | `99b6590` | 08-01 |
| #36 artifact.search | **0.6.0 (i36): NEW `get-record` by-record_version_id READ op (full s1 envelope + evidence hydration body for #40 leaf hydration; provenance holds; A5-closed -- foreign rvid fails closed count-only, working-kind conjunctive task_id+namespace, version-exact default + optional current_only; NO migration, schema stays 5, existing paths byte-identical); closes i35's fold reconciliation. 38/38 + 56/56 A6-regression off-machine + 227/227 -Live. 0.5.0 Tier-1 hierarchy node layer retained** | `16c27a8` | 08-05 |
| #37 retrieval.eval | **eval 0.8.0 (i36): opt-in `wired_descend` DRIVES #40 0.7.0's WIRED public artifact_search shortlist-and-descend port READ-ONLY via the adapter + MEASURES s10 against the WIRED packets (nav SUB-LINEAR from #40's OWN plan trace; DUAL recall PATH+PACKET; regret/fallback/stale-window); #36-direct/#40-flat retained as a labeled baseline; non-wired path BYTE-IDENTICAL to 0.7.0. 55/55 off-machine + hierarchy 26/26 + -Live. NEW eval 0.7.0 (i35): rehearsal_eval.py (op rehearsal) -- the RUNNABLE ~200MB Tier-1 acceptance-gate harness: drives REAL #36/#40 via the external_command adapter over a committed real-foreign SAMPLE (BSD click-8.1.7, MANIFEST + per-file sha256) + labeled fixtures (5 kinds) + a supersession pair; measures s10 (bounded-cost / 0-contamination / current-vs-historical / reconstruct-to-source / sub-linear-nav) + dual recall/regret/fallback; computes tier1_accepted over the sample (NOT a project claim); + FULL_CORPUS_RECIPE.md. ADDITIVE (hierarchy_eval/retrieval_eval/lib byte-identical). off-machine test_rehearsal_eval 35/35 + hierarchy 26/26; -Live dev.ship ALL PASS** | `58eedcb` | 08-05 |
| #38 repo.intel | 0.1.0: 65/65 pwsh + 37/37 python cloud + 65/65 `-Live`; deterministic typed-record producer (symbol/entity/relationship/skill/summary); s1 validator; edges resolve; byte-identical cross-env | `cd53565` | 08-01 |
| #39 episode.record | **0.1.1 (i28): 123/123 cloud + 123/123 `-Live`** -- conformed to MEMORY_CONTRACT A1 (envelope status = the s5 string; `episode_stage` retired -> full per-stage detail in `episode.body.stage_sequence` + `has_stage` edges; D-0077 re-smoke 0-bridging/0-rejections); episode+failure schemas + deterministic recorder + failure-signature seam; byte-identical cross-env (0.1.0 was 114) | `3dab699` | 08-02 |
| #40 context.compiler | **0.7.0 (i35): the REAL ArtifactSearchHierarchyPort WIRED into the PUBLIC -Retriever artifact_search path (constructs a port over #36 Catalog/shortlist/descend/prune_verdict; injected port still wins) + SEAM1 leaf hydration (rvid -> evidence via export_chunk_texts + Catalog records) + SEAM2 no-false-negative prune-cert from #36 prune_verdict; V2-V5 + non_execution green; a flat/non-descend/unscoped compile BYTE-IDENTICAL to 0.6; off-machine 322/322 + NEW public-port gate test_i35_public_port.py 32/32 over a REAL #36 tree + -Live** | `aa2f0fb` | 08-05 |
| #41 skill.card | **0.2.0 (i30): A3 record_kind skill->summary** (summary_type=skill_activation_card) + derives_from edge to #38 -> #38 sole record_kind=skill owner; envelope-only, ids stable; 81/81 python + 85/85 -Live | `54c2e79` | 08-03 |
| #42 working.memory | **0.1.0 (i34, NEW): per-task working-memory STORE (realizes A5 U3'); immutable versioned snapshots + CAS on parent_state_version (stale fails closed) + exactly-one active head (partial UNIQUE index + BEGIN IMMEDIATE) + fork/close/archive/promote + task_id+namespace isolation (imports #37 ns_permitted READ-ONLY) + search rejects record_kind=working; off-machine 30/30 + live 30/30 python + 14/14 pwsh; 0 orphans** | `601a2db` | 08-05 |
| D-0077 hierarchy fold smoke | **38/38 deterministic (i34, off-machine pure-python)**: a real #36 tree driving the real #40 run_hierarchy_plan via a port adapter (imports the real #37 lib); required-leaf recall, sub-linear nav, zero nodes in evidence[], no-false-negative prune certificates, namespace closure both ways, deterministic packet_id, flat compile byte-identical, 0 orphans | `modules/30-orchestrate-fanout/runtime/smoke-i34.py` | 08-05 |
| i35 consumer-wiring fold (orchestrator) | **PASSED at HEAD `58eedcb`, independently re-run:** the #40 WIRED public-port gate test_i35_public_port.py 32/32 over a REAL #36 tree (mixed-corpus ns closure -- no nsb/SECRET metadata; descend-class + no catalog -> flat; flat packet BYTE-IDENTICAL with vs without catalog_db_path; deterministic packet_id covers the hierarchy body) + i34 smoke-i34.py 38/38 (regression) + #37 test_rehearsal_eval 35/35 (harness fail-closed; orchestrator owns the tier1 flip); 0 llama orphans (1 pre-existing python pid 10312, not i35) | `modules/40-context-compiler/tests/test_i35_public_port.py` | 08-05 |
| widgets/05 Provenance Map | **0.1.0 (i36, NEW): read-only native WinForms construction map (D-0101 audit tier A1) -- joins MODULE_ROADMAP + CURRENT_STATE tests/Known-failures + DECISION_LOG_INDEX + HANDOFF ledger + git dev.ship trailers + runtime/plans + Verification-Console verdicts -> what-exists / iteration-N build / new-since / verification / planned-but-unbuilt / over-budget-doc flags; STRICTLY read-only. 100/100 cloud + STA SelfTest 8/8 (incl. LAYOUT_OK + READONLY). NO skill.json. HUMAN LIVE-GUI CONFIRM = OPEN follow-on (D-0064)** | `3ad71d3` | 08-05 |
| i36 TIER-1 ACCEPTANCE gate (orchestrator) | **PASSED -> project `tier1_accepted`=TRUE:** the FULL wired-descend rehearsal (harness 0.8.0 x FROZEN #40 0.7.0) over a DISTINCT 6-package foreign corpus (637 files, 6 namespaces) at a 100x leaf span (248->24800) scored **11/11 s10 criteria, 0 fold reconciliation** (bounded cost; nav sub-linear 36->100 nodes; 0 contamination; provenance 29/29; temporal 2/2; disposition 8/8; packet+guaranteed recall 1000000 ppm). Honest caveat: descend fast-beam hierarchy_path_recall=0 (indexed #36-flat fallback preserves recall) -- a follow-on, not a blocker. + i34 smoke 38/38 regression. Evidence: `research/2026-08-05-i36-tier1-acceptance-rehearsal.md` (+ report json) | `modules/37-retrieval-eval/rehearsal_eval.py` | 08-05 |
| #40 context.compiler | **0.8.0 (i37, `392837a`): the multi-channel query ROUTER `multichannel_route_v1/1.0.0`, OPT-IN via `-Route`, BORN INSTRUMENTED per CONTEXT_PACKET_CONTRACT s9 (R-1) -- 3 integer-only stage-trace records (classification->routing->channel_selection) in evaluation_hooks.routing_stage_trace, ns-closure-sanitized (channel-only); routes lexical_fts+flat_index+hierarchy_descend, working_memory NAMED but NOT hydrated (#42=i38); routing_policy id/ver + routing_plan_digest enter packet identity; a FLAT/legacy compile BYTE-IDENTICAL to 0.7.0. off-machine 35/35 new + 322/322 + i35 32/32 + i34 38/38 + harness 45/45; -Live via dev.ship all green** | `392837a` | 08-05 |
| #43 action.authz | **0.1.0 (i37, NEW, `2ad0c6e`): the P0-1 deny-by-default action reference monitor (A01-A36) + injection SUITE MVP, built to FROZEN ACTION_AUTHORIZATION_CONTRACT.md -- strict parse/serialize/canonical_action_digest + 4 closed schemas + U-AUTHORITY/SCOPE/ROLE/EFFECT + fixture family 10 + subset 1/2/6/7/9 + mock coord/exec boundary (C/D) + 66/66 M-A01..M-E36 mutation-kills + real #40 0.7.0 deterministic-denial. SUITE 192/192; double-run byte-identical; DESIGN-ONLY (non_execution holds, A06 denies every authentic packet). build_complete / p0_1_gate_status=incomplete (7 i38 amendments -> a full gate). OMIT skill_id; pure python stdlib** | `2ad0c6e` | 08-05 |
| i37 D-0077 cross-module fold (orchestrator) | **PASSED 13/13:** a REAL #40 0.8.0 ROUTED packet + an ADVERSARIAL variant (authority-shaped reason_codes + cross-ns channel_id injected into the routing_stage_trace) fed through #43's OWN consumer path -> deterministic A06 DENY + constant caller bytes + no permit + no state diff for EVERY one (the new carrier cannot launder authority / cross ns -- family 4); a flat compile carries no trace. + i34 smoke 38/38 + #43 suite 192/192 (independent re-run). Reproducer `modules/30-orchestrate-fanout/runtime/fold-i37.py` | `fold-i37.py` | 08-05 |

## Known failures / gotchas

**Highest-value section. Do not compress a live gotcha away.**

- **Cowork `device_stage_files` can return a STALE snapshot.** Re-staging a path already staged this session
  returns the **old** (pre-edit) bytes even though `mtimeMs` looks current — it nearly reverted committed doc
  edits. **Workaround:** copy the file to a **fresh, never-staged path** (e.g. `docmirror-i<N>/`) and stage
  that, or verify by a marker first. **The on-disk repo is canonical** — trust an executor read over a re-stage.
- **`ffprobe` on PATH is shadowed by a Python shim.** `where.exe ffprobe` returns
  `…\Python310\Scripts\ffprobe.exe` *before* the real `…\WinGet\Links\ffprobe.exe`. Resolve ffprobe as the
  **sibling of the resolved ffmpeg**, or filter out any `\Python*\Scripts\` source (audio.ingest #10 +
  media.decompose #32 both do this). Also: the Linux mount cannot `stat` the WinGet `Links\*.exe` reparse
  points, so `ls` shows them absent though Windows resolves them.
- **Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8.** Any non-ASCII byte corrupts parsing: a
  UTF-8 em dash in `ocr_worker.ps1` made 5.1 fail ("Unexpected token" / "The hash literal was incomplete") and
  exit 1 with **no output** — and the wrapper discarded stderr, so it only saw "produced no meta". **Rule:**
  keep 5.1 workers **ASCII-only** (or BOM them); grep `[^\x00-\x7F]` before shipping. pwsh 7 is unaffected.
- **PowerShell empty-array unroll (pwsh 7.4.6, StrictMode):** `$x = if(cond){@($y)}else{@()}` assigns **`$null`**
  on the empty branch, so a later `$x.Count` throws "The property 'Count' cannot be found." Assign first:
  `$x=@(); if(cond){$x=@($y)}`. Hit + fixed in `model.gateway` (empty `-Stop`).
- **PowerShell array double-wrap (pwsh 7.4.6):** a helper that does `return ,$out`, collected with `@(helper)`,
  yields a **1-element array whose element is the inner array** — a later `foreach`/lookup silently iterates
  once over the whole array (no error; wrong results). Fix: build into a `List[object]` and `return
  $acc.ToArray()` (no leading comma). Hit in `classify.batch` (label matching) and in Widget 02's
  `Get-ModuleRegistry` (the module list rendered as one unreadable row).
- **`@($list)` on a raw `System.Collections.Generic.List[object]` throws "Argument types do not match"**
  (pwsh 7.4.6) when it holds `[pscustomobject]`s — use `$list.ToArray()` / `$list.Count`, or
  `([array]$x).Count` for maybe-null cmdlet output (StrictMode Latest).
- **pwsh 7.4.6 `[System.Array]::Sort` with an `object[]` + a `Comparison[string]` sorts a CONVERTED COPY,**
  not the original array (generic-overload binding converts first; the intended in-place sort is a silent
  no-op). #33's canonical key sort no-op'd and `class_summary` leaked per-process RANDOMIZED hashtable order
  (string-hash seed) -- caught ONLY by the double-run byte-identity gate (i22). Cast to a real `[string[]]`
  before an in-place sort; keep double-run byte-identity gates in every canonical-bytes module.
- **`$var:` in a double-quoted string** (e.g. `"item $id: done"`) parses `$id:` as a scope/drive reference —
  a **syntax error**; delimit with `${id}`. Catch it by AST-parsing every shipped `.ps1` with
  `[System.Management.Automation.Language.Parser]::ParseFile` before submitting (`dev.ship` does).
- **`llama-cli` on build b8661 is interactive-only** — it rejects `-no-cnv` ("use llama-completion instead",
  not built) and decorates stdout with a banner/`>`/timing footer. Script LLMs via **`llama-server`**
  (`/v1/chat/completions` -> clean JSON with `finish_reason`/`usage`/`timings`), as `model.gateway` does.
- **Child-process pipe deadlock:** reading a child's stdout to end while its stderr pipe fills (llama.cpp / ffmpeg log
  a lot) deadlocks. Drain both async (`ReadToEndAsync`) or redirect to files, and close the child's stdin.
- **`capture.screen` uses screen-pixel copy (`CopyFromScreen`):** an **occluded** window captures whatever
  covers it and a **minimized** one returns `window_minimized` — it does **not** raise/activate windows.
  Per-Monitor-V2 DPI is set once per process; off-screen/`PrintWindow` compositing is deferred.
  `System.Drawing.Common` is Windows-only, so it cannot even be dry-run off-Windows.
- **Worker meta must be JSON-serializable.** Pillow returns a JPEG's `dpi` as `(IFDRational, IFDRational)`,
  which `json.dump` cannot serialize — it raised **mid-write**, leaving a truncated `image_meta.json` and a
  cryptic `ConvertFrom-Json ... Unexpected end ... Path 'metadata.dpi'`. **Rule:** coerce exotic Pillow/numpy
  types explicitly (or `json.dump(default=...)`). Fixed in `image_worker.py` (`safe_dpi`).
- **The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`** — `(Get-Process -Id $PID).Path` is
  not a reliable pwsh locator; pass explicit `-PwshPath`, resolve via `$PSHOME` in harnesses. The **executor
  likewise shows as `dotnet.exe`** — trust the heartbeat, not the process list. (Own warm servers by Job-Object
  HANDLE, not by process-name matching — the i16 supervisor lesson.)
- **Skill scripts must write ONLY the JSON envelope to stdout** (diagnostics to stderr); the executor captures
  stdout verbatim into `stdout.txt` and parses it as the envelope.
- **Bare-local WinForms event handlers lose scope** — a toggle handler threw a null-ref (`'Enabled' on $null`)
  live though the mock gate was green. Use `.GetNewClosure()` + a SelfTest guard (D-0060).
- **A live GUI probe window launched from INSIDE a background executor task** can hang that task's UIA calls if
  the window's UI thread stops pumping. Prefer side-effect-free dry-runs when capturing examples.
- **Executor wedge (the concurrency hazard, D-0055/D-0056):** a task that BLOCKS while holding a persistent
  `llama-server` orphans it; the orphan locks a `running/` file and livelocks the poll loop **while the
  heartbeat stays fresh** (the watchdog was blind). Launch persistent servers **DETACHED**, reap the whole
  child tree before finalize, assert 0 orphans. If wedged, kill the orphan out-of-band (Task Manager -> End
  task `llama-server.exe`). Risk **scales with concurrency** — re-assert every wave. Hardened by `e5b93ab`.
- **Executor transient file-lock crash (2026-07-24) — self-healed:** a directory-move/state-write collided with
  an open handle and killed the executor; now wrapped by `Invoke-WithFileRetry` + a per-iteration
  `IOException`/`UnauthorizedAccessException` loop guard (D-0013 watchdog covers it externally). **Still live:**
  avoid holding handles on `runtime/` from the Linux mount while tasks run.
- **Orchestrator/mirror-side gotchas** — git over the read-only device mount (CRLF-noise M-list, the stale
  `.git/index.lock`, **never `git add -A`**, all git writes through the executor / `dev.ship`); `device_bash`
  is a Linux VM and cannot run Windows pwsh (everything goes through `exec-job.sh`); `project_write local_path`
  must be under the working dir, not `/tmp`; deliver prompts/packets/packs as FILES; core-docs are CRLF, edit
  fail-closed and commit only named files under the `git` lease. Owned by **`FANOUT_ORCHESTRATOR_HANDOFF.md`**.
- **WinForms: lay out a `Dock=Top` toolbar's children only AFTER the panel is sized.** Children added while
  the panel still has its default ~200 px width anchor against the wrong width -- a Right-anchored button lands
  off-screen (widget-04's Refresh went to X=1788, off the 1104 px client; the mock + SelfTest gates missed it,
  D-0068). Register controls, DROP L/R anchors, position from the panel's ACTUAL width in a Resize handler
  (`.GetNewClosure()`) + on Shown; add a SelfTest that shows the form off-screen (`SELFTEST_LAYOUT_OK`).
- **Warm pool manager is OPT-IN / default-OFF (D-0067/D-0068/D-0069).** Stage-1.1 (`121a0fc`) closed the red-team
  Criticals (fencing, generation-mismatch rejection, GPU-handoff evict-before-grant, crash-atomic reconcile,
  verified socket-owner publish, CanServe, KV isolation; `-BypassPoolManager` escape; invariants non-bypassable).
  i16 (`cc296fc`) added the **DURABLE Job-Object gateway supervisor** (`Start-GatewaySupervisor.ps1` +
  `lib/Supervisor.psm1`, `-UseSupervisor`): resident + Job-Object tree survive ACROSS invocations — **finding 5
  durable = CLOSED** (228/228 off-machine + live tree-reap / two-invocation reuse / 3B->9B swap / 0 orphans).
  DEFAULT-OFF. the res.lease GPU-lease split is shipped + HARDENED (R1a 0.2.0 i18 -> R1b 0.3.0 i19 -> R1b' 0.4.0 i20) + consumer-adopted + LIVE-PROVEN (R1b CONSUMER wave i21, D-0076); the **SUPERVISOR-HARDENING wave SHIPPED i23 (D-0078, `d289ba9`, #7 0.6.0)** folded the i21 frontier red-team's 10 must-fixes into the DEFAULT-OFF durable supervisor + integrity layer + evictor (MF1+2 per-resident suspended-create Job custody LIVE-PROVEN; MF3-9 done; MF8 #00.1 relaunch driver + MF10 ACL'd app-data/trusted-hash-manifest named/not built) -> **finding 5 (durable Job-Object custody) CLOSED/live-proven for the launch primitive; the as-built red-team (pack `ff24d3a4`, verified vs `d289ba9`) RETURNED GATE = NO -> warm-pool default-ON is RE-GATED (D-0079).** The i23 supervisor is NOT soak-ready: 9 P0/P1 must-fixes + 18 tests precede a gating soak (i24 deterministic hardening + trusted deployment config + the #00.1 recovery driver first; MF8+MF10 now hard blockers; the in-proc client demoted to perf). Classic + D-0057 warm paths stay the trusted default. Detail: `WARM_POOL_DESIGN.md` §10 + `research/2026-07-31-frontier-supervisor-redteam.md`.
- **SD 3.5 Medium fp16 is NOT a clean 11 GB VRAM fit (i17, D-0070).** With `enable_model_cpu_offload` + VAE tiling the
  torch VRAM peak is ~12.06 GB — the T5-XXL fp16 spike overflows the 11 GB 2080 Ti and leans on the NVIDIA driver
  system-RAM fallback (works, slower, not guaranteed under memory pressure). `gen_image_infer.py` ships a
  **sequential-offload OOM ladder** as the guaranteed fallback. `gen.image` default stays `image.sd15` (~2.6 GB);
  SD3.5 is opt-in `-Tier sd35`. The clean-fit image upgrade is Z-Image-Turbo Q8 (needs the stable-diffusion.cpp
  engine — a separate wave).

- **`dev.ship` can FALSE-NEGATIVE the commit (i18, D-0072).** dev.ship shipped res.lease 0.2.0 correctly (`e701328`, 6 files) but reported `committed:false` because a post-commit git check tripped on an untracked `_to_delete/write_probe_tmp` ("nothing added to commit but untracked files present"). **VERIFY the real HEAD via native `git log`/`git show --stat`, not the dev.ship `committed` field.** That path also left a stale 0-byte `.git/index.lock` that blocked the next `git add` (rc=128) -- clear it via an executor task (assert no `git.exe` running) then re-commit.

- **A long-running warm-pool supervisor keeps the OLD module code (i21).** After shipping any supervisor-side change (`lib/Supervisor.psm1` / `Start-GatewaySupervisor.ps1`), RESTART the supervisor before the live check -- the first i21 proof rerun failed on the stale in-memory module. Also: consumer identity params must pin BOTH `resident_instance_id` AND `instance_generation` through the supervisor launch (`00e5912`), or the post-commit full-tuple gate rejects every supervisor-routed swap (`authority_mismatch`).
- **Driver 591.74 SPILLS a too-big model to system RAM instead of a hard CUDA OOM (i21).** The 9B @ctx131072 and even the 27B @ngl99 went RESIDENT (free 249 / 329 MiB) rather than failing to load -- "it loaded" != "it fits". The measured-PEAK `required_vram` + stable-headroom gate is the ONLY real admission control on this box; never treat a successful load as proof of fit.
- **The res.lease split adds ~6-9 child-pwsh spawns per call (~0.9-1.3 s each) (i21).** A split reuse-generate is ~6.6-7.2 s wall vs ~1-2 s classic; the pwsh-spawn cost dominates, NOT the protocol. An **in-process res.lease client** (batched ops) is a NAMED follow-on before any warm-pool default-ON. `[Console]::Out` bypasses in-process pipeline capture -- emit via `Write-Output`, capture via child-process redirection.

## Unresolved questions

- **Install pwsh system-wide** (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- **Unattended scheduled orchestrator = IMPOSSIBLE on this build (D-0074):** a scheduled Cowork fire is a fresh session with no device bridge to the box (live gate FAILED 2026-07-30). Dropped; the future home for unattended iterative fan-out is the local baton-pass agent (R4/#26) when strong enough, not the scheduler.
- **`model.gateway` semantic confidence** — confidence today is a *completeness* heuristic (stop/length/empty),
  not semantic, not calibrated; the same gap exists in every downstream producer.
- **`-Profile max` 9B arg-gen returns non-JSON** (`arg_parse_failed`) — blocks the max profile end-to-end
  (D-0046). Floor is the reliable path.
- **The executor file-lock crash root cause was never reproduced** — the class is self-healed, not explained.
- **The 27B needs a long `-LoadTimeoutSec`** via `-Model`/X0 (a cold load ~90 s approaches the gateway's 120 s
  default); its `gpu_layers` is tuned to 32 (Module 9 sweep — see `TOOL_MODEL_REGISTRY.md`).
- **`embedding.qwen3-0p6b` is WIRED (i25, D-0082)** into #35 embedding.local (dim 1024; the gateway entry stays `wired:false` by design). Vector/ANN search over the stored embeddings is a Wave-2 item (the artifact.search MVP is lexical/FTS + a real-vector store).
- **The selpol producer/consumer divergence is RESOLVED (i31, D-0089 s4 pin + D-0091 wave).** CONTEXT_PACKET_CONTRACT s4 PINNED #37's canonical `selpol_rrf_v1`/1.0.0 (raw-fused-score-primary composite; AUTHORITY_RANK/freshness ranks; source-MMR + display dedup; additive hit-copy output; AUTHORITY_POINTS + the rank-RRF-primary reference RETIRED; pure-rank-RRF-primary = deferred P1-2) and #40 0.3.0 (`b541df6`) now IMPORTS the canonical (its selpol_reference.py deleted). The D-0077 selpol fold PASSED on real #36 data (canonical selection stamped, deterministic, 0 orphans). P1-1 'one selection owner' is realized.
- **Widget 03 Verification Console `model.gateway` GPU live-GUI pass is still open** (residual first noted
  in D-0060, never closed) — exercised CPU-only + live-GUI so far.
- **Portability (i16, D-0069): `doc.io` #20 wired — the LAST non-model/non-infra walk-up leaf** (pure CPU leaves
  02/03/04/05/06/10/15/22/28 already `$PSScriptRoot`-portable). Remaining path sites, each its own follow-on wave:
  the `$PwshPath` default across ~15 model-bound entrypoints + harnesses; core-infra (00.1 + `ops/*.bat`) =
  single-worker; interpreter paths in #15/#16 = a config-schema extension; model-bound F: literals (#17/#21, #25) =
  GPU-lane rides. Also pending: apply `models.machine.json` (gpu lease); confirm `TODO_CONFIRM` URLs + sha; re-gen
  the plan on real F:. Detail: PORT-shim report / D-0069.
- **Generator model leads for #22–#25: RECEIVED (D-0068, `core-docs/research/2026-07-30-generator-model-leads.md`).**
  image=Z-Image-Turbo Q8, music=ACE-Step 1.5, video=LTX-Video 2B Distilled, audio=Stable Audio 3 Small SFX;
  Diffusers-native starts SD3.5 Medium / Wan2.1 1.3B / Stable Audio Open 1.0. Each upgrade = a follow-on
  GPU-lane wave (most need a new engine/venv). **FIRST upgrade SHIPPED i17 (D-0070): SD 3.5 Medium fp16 image tier
  (Diffusers-native runner-up). Remaining: image lead Z-Image-Turbo Q8 (stable-diffusion.cpp), music ACE-Step, video
  LTX-Video / Wan2.1, audio Stable Audio — each its own GPU-lane wave.**
- **The video-spine DENSE-STREAM decision gate is OPEN (i17 review, restated i22 D-0077).** #33 0.2.0 IS the
  reviewed stable-identity tracker and #34 0.1.1 consumes its schema exactly (contract reconciled + proven on
  real bytes), but the review's deepest question stands: sparse semantic keyframes may lack recoverable temporal
  continuity for identity AT ALL — the likely eventual architecture is a DENSE low-res tracking-sample stream
  from `media.decompose` for identity + sparse keyframes for semantics. Decide BEFORE freezing `video.interpret`
  (pos 22) / live-composition input contracts.
- **Warm-pool default-ON gate (D-0069/D-0076/D-0078):** the res.lease split is shipped + hardened + consumer-adopted + live-proven (i21) AND the **SUPERVISOR-HARDENING wave shipped i23 (D-0078, `d289ba9`, #7 0.6.0)** — all 10 i21-red-team must-fixes folded (MF10 partial), **finding 5 (durable Job-Object custody) CLOSED/live-proven**. The as-built red-team (pack `ff24d3a4`) RETURNED **GATE = NO** (D-0079, `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`): the i23 supervisor is NOT soak-ready. Default-ON now gates on the FULL sequence -- **i24 deterministic hardening (9 P0/P1 fixes + 18 deterministic tests) -> mandatory trusted deployment config -> the #00.1 recovery driver -> an in-proc res.lease client -> a GROWN soak (>=24h, >=1000 transitions, the 5 fault classes + 15 live tests + p99/max/leak/lock-hold metrics) -> default-ON**. MF8 (recovery driver) + MF10 (trusted-hash provisioning) are now HARD BLOCKERS before the soak, not residuals; the in-proc client is demoted to a perf/integration improvement.

## Next expected action

**i38 P0-1 FULL-GATE + WORKING-MEMORY + AUDIT-WIDGET wave CLOSED (D-0106; plan `fo-38-2b1efe73`).** The 3-lane CPU wave shipped + was VERIFIED (GPU skipped): Lane A **#43 action.authz 0.2.0** (`0a82975`; the 7 FROZEN s6 amendments + promoted staged items -> **`p0_1_gate_status=pass`**; SUITE 204/204, all 10 fixture families, fuzzer 400 iters/0, 67/67 mandatory mutations killed incl. NEW M-R11, 67-row oracle matrix, ONE canon cross-validated byte-equivalent to a blind 2nd impl). Lane B **#40 context.compiler 0.9.0** (`52a0381`; the packet working_memory region HYDRATED from #42.get_active_head -- conjunctive task_id+namespace, cross-ns fail-closed BYTE-IDENTICAL to genuine-absence [no existence oracle], state_version in packet identity, evidence-ineligible + can_instruct:false, flat/no-wm byte-identical to 0.8.0). Lane C NEW **widgets/06 Compile Trace Console** (`c912854`; read-only audit tier A1, panes 1-4,6 + the compile-layer counterfactual runner). **The orchestrator VERIFIED:** an independent #43 `run_suite` re-run = PASS + the **D-0077 cross-module fold 18/18** (`fold-i38.py`: a REAL #40 0.9.0 routed + working-memory-hydrated packet + an ADVERSARIAL authority-shaped wm / cross-ns stage-trace / injected-control variant -> deterministic A06 DENY + constant caller bytes + no permit + no state diff -- the new working_memory region + router diagnostics CANNOT launder authority; A31 / R1-ROLE-1) + i34 38/38; 0 orphans. **Contract s7 ratifies the gate flip + PINS #43's byte-exact test-views** (SCHEMA_NOTES canonical); `activation_status` stays **prohibited** (Blockers 3/4/6/7 + activation portions of 5/9 remain; `non_execution:true` holds; nothing action-capable). A frontier AS-BUILT re-review of the pass was couriered (pack `24190087`; non-blocking; folds i39).

**NEXT = i39:** the fast-beam recall follow-on (#36/#40; i36 measured hierarchy_path_recall=0); bake the 0.9.0 routed+wm authentic chain into #43 `integration.py` (self-flagged); the Widget 05/06 human live-GUI confirms (D-0064); PB-3 hot-doc slim (deadline i40). Candidate menu: **`FANOUT_ORCHESTRATOR_HANDOFF.md`** section 4.

**Standing (still open):** FROZEN/deferred (D-0080) -- supervisor/warm-pool hardening (D-0079 GATE-NO stands; classic detached-warm is the trusted default), generator upgrades, `video.interpret` + live composition, deep real-time perception, broad training; the widget-03 `model.gateway` GPU live-GUI pass (open since D-0060); the Widget 05 human live-GUI confirm; doc debt -- CURRENT_STATE + MODULE_ROADMAP + the handoff over budget, a hot-doc slim pass is a named unit (PB-3, deadline i40).

---

**Last updated:** 2026-08-06 -- i38 CLOSED (D-0106; plan `fo-38-2b1efe73`): the 3-lane CPU wave shipped + VERIFIED -- Lane A #43 action.authz 0.2.0 the P0-1 FULL gate (`p0_1_gate_status=pass`; 204/204 + the orchestrator D-0077 fold 18/18 over a real #40 0.9.0 routed+working-memory packet -> deterministic A06 DENY) + Lane B #40 context.compiler 0.9.0 (working_memory region HYDRATED from #42.get_active_head; conjunctive ns fail-closed; state_version in identity; flat byte-identical to 0.8.0) + Lane C NEW widgets/06 Compile Trace Console (read-only audit tier A1). Contract s7 ratifies the gate flip + pins #43's test-views; activation stays prohibited; `non_execution:true` holds. Frontier as-built re-review couriered (folds i39). NEXT = i39 (fast-beam recall; Widget 05/06 live-GUI confirms; bake the 0.9.0 chain into #43 integration.py; PB-3 slim). PROCESS_MANDATE 01 countdown 38 / iterations_to_sunset 2 (sunset i40).
*(Rule: REPLACE this line, never append. No `[prior]` chain here or anywhere else in this doc.)*
