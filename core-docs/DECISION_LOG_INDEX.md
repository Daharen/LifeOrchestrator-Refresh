# DECISION_LOG_INDEX

One row per decision; full entries live in `DECISION_LOG.md` (append-only -- pull entries by ID, never
ingest the whole log). Every new decision appends its entry there AND its row here (DOC_PROTOCOL.md
section 4).

| id | date | state | decision |
|---|---|---|---|
| D-0001 | 2026-07-24 | locked | Trusted bootstrap executor, not a sandbox |
| D-0002 | 2026-07-24 | provisional | Isolated skill processes before persistent sessions |
| D-0003 | 2026-07-24 | provisional | Filesystem queue before any local HTTP service |
| D-0004 | 2026-07-24 | locked | Skill contract provides modularity; language does not |
| D-0005 | 2026-07-24 | locked | Contract starts minimal; grows only on real need |
| D-0006 | 2026-07-24 | superseded (was locked) | Long-horizon Proteus deferred to cold reference [superseded by D-0010] |
| D-0007 | 2026-07-24 | provisional | Two-tier local model use with a review queue |
| D-0008 | 2026-07-24 | provisional | PowerShell 7 installed per-user via .NET global tool (pinned 7.4.6) |
| D-0009 | 2026-07-24 | folded (was provisional) | Module 1 skill conventions, pending contract absorption [superseded by D-0028] |
| D-0010 | 2026-07-24 | locked | Disentangle: this project is Life Orchestrator, separate from the Proteus game |
| D-0011 | 2026-07-24 | folded (was provisional) | Module 2 confirms the D-0009 skill conventions [superseded by D-0028] |
| D-0012 | 2026-07-24 | locked | First side-effecting skill (uia.actor): UIA patterns only, dry-run, not parallel-safe |
| D-0013 | 2026-07-24 | locked | Executor watchdog is COOPERATIVE, not perpetual (Module 00.1) |
| D-0014 | 2026-07-24 | locked | Screenshot capture (capture.screen): read-only screen-pixel copy, parallel-safe, PNG-first |
| D-0015 | 2026-07-24 | locked | Large model/data lives on F: as portable per-module copies; C: repo stays small |
| D-0016 | 2026-07-24 | locked / provisional | model.gateway wraps llama-server per call; declares all modalities, wires LLM |
| D-0017 | 2026-07-24 | locked / provisional | classify.batch: per-item gateway calls, suppress the gateway's review writes |
| D-0018 | 2026-07-24 | locked / provisional | review.processor: single-item adjudication, update-in-place + append-log |
| D-0019 | 2026-07-24 | locked / provisional | audio.ingest wraps ffmpeg/ffprobe; deterministic; whisper-ready defaults |
| D-0020 | 2026-07-24 | locked / provisional | speech.stt wraps whisper.cpp; token-probability confidence; per-segment review producer |
| D-0021 | 2026-07-24 | locked / provisional | speech.tts wraps Qwen3-TTS via a Python worker; 4th review producer |
| D-0022 | 2026-07-24 | locked | voice.live composes STT+LLM+TTS; orchestrator not a producer; file-driven turn |
| D-0023 | 2026-07-25 | locked / provisional | ocr.layout wraps Windows.Media.Ocr via a PowerShell 5.1 worker; 5th review producer |
| D-0024 | 2026-07-25 | locked / provisional | image.util is a deterministic Pillow+numpy Python worker; not a review producer |
| D-0025 | 2026-07-25 | locked / provisional | detect.objects wraps a staged ONNX YOLOX via onnxruntime (CPU); 6th review producer |
| D-0026 | 2026-07-25 | locked / provisional | image.interpret is a local VLM via llama.cpp + mmproj (Qwen2.5-VL-3B GGUF) |
| D-0027 | 2026-07-25 | locked / provisional | image.index fuses 14-17 into one per-image index; NOT a review producer |
| D-0028 | 2026-07-25 | locked | Housekeeping: fold D-0009/D-0011 into contract v0.2; relocate staged models to F: homes |
| D-0029 | 2026-07-25 | locked / provisional | Pivot to a usable-local-core-first build order; Module/Widget vocabulary; widgets/ layer |
| D-0030 | 2026-07-25 | locked / provisional | logic.escalator: escalating tier ladder with deterministic ground-truth gates |
| D-0031 | 2026-07-25 | locked / provisional | doc.io: deterministic read/write/edit/append text primitive; atomic writes + precondition |
| D-0032 | 2026-07-25 | locked / provisional | agent.local: a bounded ReAct loop; decisions via logic.escalator; closed tool registry |
| D-0033 | 2026-07-25 | locked / provisional | gen.audio: procedural audio generation via ffmpeg lavfi; deterministic; neural deferred |
| D-0034 | 2026-07-25 | locked / provisional | gen.image: local text-to-image via Stable Diffusion 1.5; 8th review producer |
| D-0035 | 2026-07-26 | locked / provisional | gen.music: local text-to-music via MusicGen Small; 9th review producer |
| D-0036 | 2026-07-26 | locked / provisional | gen.video: local text-to-video via AnimateDiff-Lightning on SD 1.5; 10th review producer |
| D-0037 | 2026-07-26 | locked / provisional | agent.coding: DEFERRED (no safe execution substrate; lowest near-term ROI) |
| D-0038 | 2026-07-26 | locked / provisional | Widget delivery: native (WinForms/PowerShell) by default; every Widget ships a launcher |
| D-0039 | 2026-07-26 | locked / provisional | Widget 01 Local Agent Console: WinForms shell over a WinForms-free driver core |
| D-0040 | 2026-07-26 | locked / provisional | route.tools (Module 27): a mid-tier Tool Router; deterministic catalog gate |
| D-0041 | 2026-07-26 | locked / provisional | agent.local -Route (router-constrained ReAct) + a curated 10-tool registry; Plan/Run |
| D-0042 | 2026-07-26 | locked / provisional | fs.manage (Module 28): the deterministic copy/move/mkdir last-mile + agent wiring |
| D-0043 | 2026-07-26 | locked / provisional | Adaptive Resource Governor Phase 1: decision floor raised to MID + -Profile rungs |
| D-0044 | 2026-07-26 | locked / provisional | Strong tier swap: Qwen3.5-9B (GPU-resident) replaces the partial-offload 27B |
| D-0045 | 2026-07-26 | superseded (was locked) | Housekeeping + handoff: core-docs/HANDOFF.md + START_HERE pointer + location audit [HANDOFF.md retired to archive by D-0066] |
| D-0046 | 2026-07-27 | locked / provisional | agent.local D-0032 fix: deterministic terminator + repeat-action guard |
| D-0047 | 2026-07-27 | locked / provisional | Direction: resume expansion; next unit = the executor JOB-RUNNER + a dev.ship harness |
| D-0048 | 2026-07-27 | locked | Module 0 job-runner SHIPPED: dev.ship (Invoke-DevShip.ps1) + exec-job.sh client |
| D-0049 | 2026-07-27 | locked / provisional | Widget 02 Module Launcher & Registry Browser: browse + run any installed Module |
| D-0050 | 2026-07-27 | locked / provisional | Past-MVP doctrine: the verify-cost offload rule; the audit-loop spine; a Claude-leads bridge |
| D-0051 | 2026-07-27 | locked / provisional | Widget 03 (Verification Console) SHIPPED; + the fan-out orchestrator design |
| D-0052 | 2026-07-27 | locked / provisional | Manual frontier bridge (human-couriered): IN-BOUNDS as a local context-packager |
| D-0053 | 2026-07-27 | locked / provisional | res.lease (Module 29): an atomic filesystem lease with a TTL for multi-instance work |
| D-0054 | 2026-07-27 | locked / provisional | orchestrate.fanout (Module 30): the fan-out orchestrator, built on res.lease #29 |
| D-0055 | 2026-07-27 | locked / provisional | Fan-out DOGFOOD (iteration 1): #30 driven end-to-end; 3 parallel workers shipped |
| D-0056 | 2026-07-28 | locked / provisional | Fan-out iterations 2-3: doc lease consumer; E WEDGED the executor; executor hardened |
| D-0057 | 2026-07-28 | locked / provisional | Fan-out iteration 4: Governor Phase 2 (detached warm server) DONE; audit loop validated |
| D-0058 | 2026-07-28 | locked / provisional | Fan-out iteration 5: Console teardown sweep + packet-input validation; Phase 3 opinion |
| D-0059 | 2026-07-28 | locked / provisional | Fan-out iteration 6: Governor Phase 3 Stage-1 auto-ramp controller (-AutoRamp) SHIPPED |
| D-0060 | 2026-07-28 | locked / provisional | Fan-out iteration 7: Phase 3 Stage-2 slice (X0/27B + logprobs) + -AutoRamp in Console |
| D-0061 | 2026-07-28 | locked | Fan-out iteration 8: -AutoRamp default-on TRIED then REVERTED (closing fix -> D-0062); 27B/X0 quant NEGATIVE RESULT — no quant fits GPU-bound on 11 GB; couriered frontier model-selection report (9B Q5_K_M) |
| D-0062 | 2026-07-28 | locked | Fan-out iteration 9: contract-less -AutoRamp closing FIXED + default-on; 9B -> Q5_K_M |
| D-0063 | 2026-07-29 | locked | Fan-out iteration 10: warm multi-model pool + router, design-first |
| D-0064 | 2026-07-29 | locked | Fan-out iteration 11: Verification Console UX (packet discovery + by-kind render) [its iter11-stage1-DRAFT pointer: renumbered to core-docs/fanout/FANOUT_AGENT_001.md by D-0066] |
| D-0065 | 2026-07-29 | locked | Fan-out iteration 12 (verdict-persistence fix) + iteration-13 follow-on (durable verdicts) [its expanded-handoff pointer: retired to archive by D-0066 -> FANOUT_ORCHESTRATOR_HANDOFF.md §4] |
| D-0066 | 2026-07-29 | locked | Core-docs consolidation: one live handoff, doc budgets, this index doc, fanout-agent slots, archive/ tree |
| D-0067 | 2026-07-29 | locked | Fan-out iteration 14 (first 4-lane wave): warm-pool Stage-1 opt-in/default-OFF + portability bring-up (ops/setup) + wave dashboard (widgets/04) + frontier red-team -> Stage-1.1 hardening backlog |
| D-0068 | 2026-07-30 | locked | Fan-out iteration 15 (4-lane wave): warm-pool Stage-1.1 hardening (Criticals closed, pool still default-OFF) + portability follow-ons (staging-plan confirm + additive resolver shim; repo-root already portable) + widget-04 live-GUI confirm+fix + folded frontier generator model leads |
| D-0069 | 2026-07-30 | locked | Fan-out iteration 16 (3-lane wave): warm-pool durable Job-Object gateway supervisor (finding 5 CLOSED; pool still default-OFF) + portability resolver shim into doc.io #20 (last non-model/non-infra leaf) + NEW module #32 media.decompose (Phase C video spine STARTED) |
| D-0070 | 2026-07-30 | locked | Fan-out iteration 17 (3-lane video-spine + generators wave): SD 3.5 Medium fp16 image tier in gen.image #23 (first generator upgrade; SD1.5 kept default; ~12 GB not-a-clean-fit) + config-resolvable Python interpreter path for #15/#16 + NEW module #33 track.objects (Phase C video #20, greedy-IoU baseline) + folded frontier tracker design review |
| D-0071 | 2026-07-30 | locked | Out-of-band direct provision (Cowork review session): trajectory review + R1–R4 work orders + frontier pack mirrored to core-docs/research/; i18 reshaped to R1 (res.lease lease-split keystone, primitive layer this wave); R1b/R3/R4 + baton-pass direction = Nicholas's call |
