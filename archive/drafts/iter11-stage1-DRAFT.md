# Iteration 11 — READY dispatch package (Warm pool Stage-1: named pool manager)

**Status: READY TO DISPATCH.** Both preconditions are now met (updated 2026-07-29, HEAD `4f295d6`):
1. **Iteration 10 is closed on-box.** DECISION_LOG D-0063 + CURRENT_STATE / HANDOFF /
   FANOUT_ORCHESTRATOR_HANDOFF committed (`4f295d6`) and mirrored to the Project.
2. **The frontier second opinion is in and folded.** ChatGPT Pro answer captured at
   `modules/31-frontier-bridge/runtime/artifacts/12da1fca-…/frontier-pack-warmpool.answer.md` and folded into
   `modules/07-model-gateway/WARM_POOL_DESIGN.md` **section 9**. It **confirms mechanism C** (native router A
   is only a supervisor — it does NOT remove the ~4 s GPU upload; `--models-max` is not a VRAM oracle; B
   rejected), so no mechanism change is needed.

Companion: `claude/ORCHESTRATOR_HANDOFF_2026-07-29.md` (iteration-10 verified state).

## What Stage-1 is (mechanism C, confirmed)

A **named pool manager** that extends the shipped D-0057 detached warm server so `model.gateway` keeps ONE
model GPU-active and fast-swaps to a named model on demand — `Ensure-ResidentModel(model_id, config_key)`:
reuse if the exact config is resident (~1 ms); else terminate the resident server, confirm process exit +
VRAM recovery, start the requested model via its registry engine, confirm health + provenance, publish the
new residency manifest. Native `--models` router, persistent slot save/restore, and any coding specialist are
**Stage-2+**.

## Plan command (on the box, from `~/mnt/LifeOrchestrator-Refresh`)

Write `modules/30-orchestrate-fanout/runtime/workers-i11.json` (the array below), then a `task-plan-i11.ps1`
mirroring `task-plan-i10.ps1` (`-Title` = the iter-11 title, `-Iteration 11`, `-MaxParallel 1`, read
`workers-i11.json`). Run via `exec-job.sh run i11-plan-001 …`, confirm `dispatch_now=[WMP-stage1]`, 0
conflicts, clean preflight, then **relay the emitted worker prompt to Nicholas as a FILE** (SendUserFile —
the iter-10 lesson: he could not grab the on-disk prompt md).

## `workers-i11.json` (single GPU worker)

```json
[
 {
  "id": "WMP-stage1",
  "label": "Warm pool Stage-1: named pool manager (mechanism C) over the D-0057 detached warm server",
  "gpu": true,
  "docs": [],
  "needs_git": true,
  "skill_id": "model.gateway",
  "skill_dir": "modules/07-model-gateway",
  "unit": "Build Stage-1 of the warm multi-model pool per modules/07-model-gateway/WARM_POOL_DESIGN.md sections 6 (Phased build plan) + 9 (frontier second opinion, folded). MECHANISM = C (confirmed by the ChatGPT Pro second opinion): extend the shipped D-0057 DETACHED warm/persistent llama-server into a NAMED POOL MANAGER so model.gateway keeps ONE model GPU-active and fast-swaps to a named model on demand. IMPLEMENT Ensure-ResidentModel(model_id, config_key): (1) if the EXACT config is already resident, reuse it (~1 ms, no reload); (2) else terminate the resident owned server, CONFIRM process exit + VRAM recovery, start the requested model via its registry-selected engine, confirm /health + exact model provenance, and publish a new residency manifest. REQUIREMENTS from the design + section 9: (a) an EXPANDED RESIDENCY KEY -- not just model filename, but model_id + model_sha256 + engine build/hash + gpu_layers + context_size + no_think/reasoning + cache_type_k + cache_type_v + flash_attn + parallel-slot-count + chat-template(+args) + mmproj sha256 (VLM) + generation_id; a config change (e.g. KV type / context) is a real swap. (b) a TASK-AFFINITY / model-affine-epoch swap-minimising policy: M0/M1 reuse the same 3B; escalation does ONE 3B->9B switch and STAYS on 9B until the task ends (no intra-task downshift); LRU only as a tie-breaker; default max ONE swap per task. (c) HOLD the res.lease #29 gpu lease across the whole residency check/change (a per-call lease lets another task swap the model between two calls). (d) a 90 s idle KEEP-RESIDENT window (refresh on same-model reuse; a higher-priority contender or another module GPU request may evict immediately). (e) same-model PREFIX REUSE is in-scope for Stage-1 (normal prompt caching, -np 1, explicit id_slot, no cross-task similarity, clear at session boundary); persistent --slot-save-path across eviction is Stage-2, DO NOT build it now. (f) DO NOT build the native --models router (mechanism A) -- Stage-2+, gated on a direct b8661/b10092 probe + the OOM questions. (g) HARDENED detached lifecycle per the D-0055/56 wedge lesson: launch detached so the task returns, reap before finalize, assert 0 orphaned llama-server. SCOPE: edit ONLY modules/07-model-gateway (the warm-server/pool-manager code + models.json pool/residency config if needed) + its tests; do NOT touch agent.local #21, route.tools #27, or the governor code. GATE off-machine where possible (AST-parse), then dev.ship the named files under the git lease. LIVE-VERIFY a real 3B<->9B swap through the pool manager: same-model reuse ~1 ms, a cross-model swap with load_ms in the probe range (~1.6-4.1 s), residency-key mismatch forces evict+reload, 0 orphaned llama-server, gpu lease released. Report done with the measured swap numbers. If Stage-1 proves impractical, say so plainly (the D-0061/27B ethos).",
  "notes": "Verification = run_module (a model.gateway warm-pool swap). Single GPU worker. No core-doc edits (orchestrator mirrors). Mechanism C confirmed by the frontier second opinion (section 9); no reconciliation needed."
 }
]
```

Suggested title: `iteration 11 -- warm pool Stage-1: named pool manager (mechanism C) over the D-0057
detached warm server`.

## After dispatch

Relay the worker prompt as a FILE, poll `status` until `ready_for_handoff`, verify the commit + a real swap
against disk, close it (skip the Console packet unless a run_module verification is wanted — a warm-pool swap
IS a natural run_module item here, so a Verification Console packet is genuinely useful this time), then
mirror the core-docs (D-0064). Stage-2 after: native `--models` router probe on b8661/b10092, persistent
`--slot-save-path`, and a coding specialist behind its ≥30-task admission benchmark (≥15 pp verify gain, ≥10%
median-time gain, ≥3-call/2k-token residencies). Also outstanding: request the report's audio/image/video
model leads (generators #22–#25).
