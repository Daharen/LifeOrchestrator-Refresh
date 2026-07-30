# FANOUT_AGENT_001 -- GPU lane: Warm pool Stage-1 (named pool manager, mechanism C)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** DISPATCHED -- iteration 14, plan `fo-14-5ea064b6`. This is the wave's ONLY GPU worker.
- **Wave / iteration:** i14 (plan id `fo-14-5ea064b6`)
- **Lane:** GPU (<=1 per wave -- this is the wave's ONLY GPU worker)
- **Worker id / label:** `WMP-stage1` -- "Warm pool Stage-1: named pool manager (mechanism C) over the D-0057 detached warm server"
- **Module/area (exclusive):** `modules/07-model-gateway` ONLY (+ its tests; `models.json` pool/residency config if needed)
- **GPU:** true
- **Docs:** `[]`

## Mission

Build Stage-1 of the warm multi-model pool per `modules/07-model-gateway/WARM_POOL_DESIGN.md` sections 6
(phased build plan) + 9 (frontier second opinion, folded). Mechanism C is CONFIRMED by the couriered
ChatGPT Pro second opinion (D-0063): extend the shipped D-0057 DETACHED warm/persistent llama-server into a
NAMED POOL MANAGER so `model.gateway` keeps ONE model GPU-active and fast-swaps to a named model on demand.
(The native `--models` router is only a supervisor -- it does NOT remove the ~4 s GPU upload; mechanism B
was rejected; router/slot-save/coding-specialist are Stage-2+, gated.)

## Unit (the full worker prompt)

IMPLEMENT `Ensure-ResidentModel(model_id, config_key)`: (1) if the EXACT config is already resident, reuse it (~1 ms, no reload); (2) else terminate the resident owned server, CONFIRM process exit + VRAM recovery, start the requested model via its registry-selected engine, confirm `/health` + exact model provenance, and publish a new residency manifest. REQUIREMENTS from the design + section 9: (a) an EXPANDED RESIDENCY KEY -- not just model filename, but model_id + model_sha256 + engine build/hash + gpu_layers + context_size + no_think/reasoning + cache_type_k + cache_type_v + flash_attn + parallel-slot-count + chat-template(+args) + mmproj sha256 (VLM) + generation_id; a config change (e.g. KV type / context) is a real swap. (b) a TASK-AFFINITY / model-affine-epoch swap-minimising policy: M0/M1 reuse the same 3B; escalation does ONE 3B->9B switch and STAYS on 9B until the task ends (no intra-task downshift); LRU only as a tie-breaker; default max ONE swap per task. (c) HOLD the res.lease #29 gpu lease across the whole residency check/change (a per-call lease lets another task swap the model between two calls). (d) a 90 s idle KEEP-RESIDENT window (refresh on same-model reuse; a higher-priority contender or another module GPU request may evict immediately). (e) same-model PREFIX REUSE is in-scope for Stage-1 (normal prompt caching, -np 1, explicit id_slot, no cross-task similarity, clear at session boundary); persistent `--slot-save-path` across eviction is Stage-2, DO NOT build it now. (f) DO NOT build the native `--models` router (mechanism A) -- Stage-2+, gated on a direct b8661/b10092 probe + the OOM questions. (g) HARDENED detached lifecycle per the D-0055/56 wedge lesson: launch detached so the task returns, reap before finalize, assert 0 orphaned llama-server. SCOPE: edit ONLY modules/07-model-gateway (the warm-server/pool-manager code + models.json pool/residency config if needed) + its tests; do NOT touch agent.local #21, route.tools #27, or the governor code. GATE off-machine where possible (AST-parse), then dev.ship the named files under the git lease. LIVE-VERIFY a real 3B<->9B swap through the pool manager: same-model reuse ~1 ms, a cross-model swap with load_ms in the probe range (~1.6-4.1 s), residency-key mismatch forces evict+reload, 0 orphaned llama-server, gpu lease released. Report done with the measured swap numbers. If Stage-1 proves impractical, say so plainly (the D-0061/27B ethos).

**Plan-side spec (orchestrator):** in `workers-i14.json` this worker is
`{"id":"WMP-stage1","gpu":true,"docs":[],"needs_git":true,"skill_id":"model.gateway","skill_dir":"modules/07-model-gateway","unit":<the block above>,"notes":"..."}`.
Dispatched in plan `fo-14-5ea064b6` alongside the CPU + coding lanes (`-MaxParallel 3`); emitted convenience copy:
`runtime/artifacts/53985bb5-5c1e-4d62-b7d1-b9a1bf7d60ea/workers/worker-WMP-stage1.prompt.md`.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) **gpu -> git** (whole-task gpu lease -- requirement (c)); release in reverse on exit.
- ONE unit; `modules/07-model-gateway` only; `docs:[]`.
- Gate off-machine first where possible (AST-parse), then `exec-job.sh devship` (FAIL-CLOSED; named files; trailers).
- Persistent llama-server: DETACHED launch, reap before finalize, assert 0 orphans (the D-0055/56 wedge).
- Runtime-behavior change => real-model live check before "done" (D-0060/D-0064 lesson).
- Report: `-Action report -PlanId fo-14-5ea064b6 -WorkerId WMP-stage1 -State done` + measured swap numbers.

## Verification

Live on the box, through the executor: same-model reuse ~1 ms; 3B->9B and 9B->3B swaps with load_ms in the
~1.6-4.1 s probe range; a residency-key mismatch (e.g. changed context_size) forces evict+reload; 0 orphaned
`llama-server` before/after; gpu lease released. Module 7 test suite green (+ new pool-manager tests). A
Verification Console `run_module` packet item (a warm-pool swap) is genuinely useful here -- emit one at handoff.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)

---
*Provenance: renumbered from the retired Project draft `claude/iter11-stage1-DRAFT.md` (archived at
`archive/drafts/iter11-stage1-DRAFT.md`); "iter11" became the Console UX unit, so this dispatches as i14.*
