# Frontier research -- best local escalation model under the 11 GB VRAM ceiling

**Provenance:** deep-research report produced by Nicholas in ChatGPT (GPT-5.6 "Sol"),
couriered back 2026-07-28. Scope: the best local LLM for the "last-resort" escalation tier
given DESKTOP-PF5FFMF's hard ceiling of ~9,867 MiB (~9.64 GiB) free VRAM (RTX 2080 Ti 11 GB).
This is a faithful DIGEST of the couriered report (every actionable fact preserved). The report
also mentioned audio/image/video model leads that were NOT included in the couriered text --
flagged TBD below; request them from Nicholas to fold into the generator modules (#22-25).

## Verdict
- **Best overall escalation model: Qwen3.5-9B** (the tier we already run). Strong-for-size:
  MMLU-Pro 82.5, GPQA-Diamond 81.7, IFEval 91.5, LiveCodeBench-v6 65.6, BFCL-V4 66.1 (tool use),
  TAU2-Bench 79.1 (agent), DeepPlanning 18.0; multimodal (image+video) with documented agentic paths.
- **Best deployable quant for our ceiling: Qwen3.5-9B-Q5_K_M.gguf (7.11 GB)** -- upgrade from our
  current Q4_K_M (~6.9 GB) for better fidelity while KEEPING real KV/context headroom.
- **Higher-fidelity alt profile: Qwen3.5-9B-Q6_K.gguf (7.96 GB)** for text-heavy sessions.
- Quant sizes (imatrix): Q4_K_M 6.17 GB, Q5_K_M 7.11 GB, Q6_K 7.96 GB.

## Why weight-fit alone is the wrong test (the core technical point)
- The binding budget is the **KV cache / inference state**, not raw token IDs. llama.cpp offloads
  KV to VRAM by default (K/V dtypes default f16; compressible to q8_0 or q4). A model can fit "on
  paper" as weights and still be a bad choice once real context is allocated.
- Qwen3.5-9B's **hybrid architecture** makes KV tiny: 32 layers = 8 x (3x Gated DeltaNet->FFN,
  1x Gated Attention->FFN); only the 8 gated-attention blocks use the KV path (4 KV heads @ 256 dim)
  -> ~**32 KiB/token** F16 KV -> ~128 MiB@4K, 256 MiB@8K, 512 MiB@16K, ~1.0 GiB@32K (halve w/ Q8 KV,
  quarter w/ Q4 KV).
- Contrast: dense Qwen3-14B (40 layers, 8 KV heads, 128 dim) ~160 KiB/token -> ~640 MiB@4K,
  1.25 GiB@8K, 2.5 GiB@16K; its Q4_K_M is 9.00 GB (~8.38 GiB) before any context -> "fits" only as a
  weight file, collapses under a real session. This is exactly our 27B failure mode.

## This project's negative result (independently confirms the report)
- Worker B (fo-8, iteration 8) measured live: ~9.9 GB free VRAM; NO Qwen3.5-27B quant fits GPU-bound
  -- smallest IQ2_XXS 9.61 GB (+KV/compute exceeds free at usable ctx, and 2-bit collapses quality);
  IQ3_XXS 12.8, Q2_K 12.1, Q3_K_M 14.8 GB all far over. Incumbent 27B Q4 decides correctly but
  2.1 tok/s partial-offload (~88s warm / ~170s cold per one-rung decision). => the 27B is NOT a
  practical rung on this GPU; the resident 9B (~68 tok/s, decides 6/6) is the effective top.
  Probe table: modules/07-model-gateway/runtime/x0quant/probe-table.md.

## Specialist pool (optional role-specialists, if ever wanted)
| Role | Model (quant) | Note |
| --- | --- | --- |
| Overall escalation | Qwen3.5-9B-Q5_K_M (7.11 GB) | broadest evidence + headroom |
| Highest-fidelity | Qwen3.5-9B-Q6_K (7.96 GB) | better quant, moderate ctx / compressed KV |
| Coding | Gemma-4-12B-it-Q4_K_M (7.38 GB) | best coding of the fits; native function calling; multimodal |
| Math-heavy | Ministral-3-14B-Reasoning-2512-Q4_K_M (8.24 GB) | best AIME-style; native JSON/function calling; tighter fit |
| Efficiency backup | Gemma-4-E4B-it-Q6_K/Q8_0 (6.22/8.03 GB) | safe fit; weaker as a final tier |
- Rejected as over-budget/too-tight: Qwen3-14B (KV collapse), gpt-oss-20b (needs 16 GB; Q4 ~11.6 GB),
  Devstral Small 24B (32 GB class).

## Architecture suggestion: one active GPU model + warm RAM pool + cheap routing
- Cannot keep two of these resident in 9.64 GiB with useful context (Q5_K_M 7.11 + Gemma12B 7.38 +
  Ministral14B 8.24 -- any two exceed the cap). Design = ONE active GPU model, several warm
  RAM-backed candidates, cheap routing.
- Mechanisms the report verified: **llama-cpp-python** OpenAI server with a multi-model JSON config
  (routes by the "model" field; auto load/unload; only one model resident); OR raw **llama.cpp server**
  with `--models-dir` + `--models-preset` + `--alias` (multiple logical models, one active on GPU).
  Keep conversation warm via llama.cpp **slot save/restore/erase** (`--slot-save-path`) +
  **host-memory prompt caching** (prefix reuse in system RAM -> lower TTFT).
- Suggested routing: a small everyday model triages -> escalate to Qwen3.5-9B -> if code-centric swap
  Gemma-4-12B, if formal-math swap Ministral-14B -> send the artifact/plan back through Qwen3.5-9B for
  final instruction-following/interaction (9B stays "captain"; specialists earn the swap cost).

## Deployment recommendation (report's bottom line)
- Anchor: **Qwen3.5-9B**. Production quant: **Q5_K_M** (16K safe default; 32K w/ compressed KV / lean
  runtime). Alt: **Q6_K** (8K-16K; 32K only w/ compressed KV). Add Gemma-4-12B-Q4_K_M for code-dominant
  jobs, Ministral-3-14B-Reasoning-Q4_K_M only for demonstrable Olympiad-math need. Qwen3.5-9B has a
  **text-only serving mode** (skips the vision encoder) to free VRAM for KV when vision isn't needed.

## Implications for Life Orchestrator (orchestrator's read)
- **Confirms the Governor design:** the resident 9B is the correct top rung; X0/27B is validated as
  impractical on this GPU (keep it opt-in/rare per D-0060, or retire it to a documented-unavailable note).
- **Actionable next unit (iteration 9 candidate):** stage Qwen3.5-9B-**Q5_K_M** and repoint the strong
  tier in models.json (from Q4_K_M) -- a fidelity upgrade WITH headroom; re-verify the S0 6/6 calibration
  + agent.local/gateway gates. Low-risk, high-value. (Optional companion profile: Q6_K.)
- **Bigger direction (design candidate):** evolve model.gateway #7 Phase 2 (single warm server) into a
  **warm multi-model pool + router** (one active on GPU; RAM-warm specialists; res.lease #29 already
  arbitrates the GPU; slot save/restore + host-memory prompt cache for warmth). Aligns with the "ramp
  toward capacity" governor philosophy. Substantial module change -- scope carefully.
- **TBD:** the report's audio/image/video model leads were not in the couriered text -- request them
  from Nicholas to fold into the generator modules (#22 gen.audio / #23 gen.image / #24 gen.music /
  #25 gen.video).
