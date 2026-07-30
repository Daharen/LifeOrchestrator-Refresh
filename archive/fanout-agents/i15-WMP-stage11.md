# FANOUT_AGENT_001 -- GPU lane: Warm pool Stage-1.1 hardening (mechanism C)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** DISPATCHED -- iteration 15, plan `fo-15-27a03513`. This is the wave's ONLY GPU worker.
- **Wave / iteration:** i15 (plan id `fo-15-27a03513`)
- **Lane:** GPU (<=1 per wave -- this is the wave's ONLY GPU worker)
- **Worker id / label:** WMP-stage11 -- "Warm pool Stage-1.1 hardening: close the frontier red-team's Critical integrity invariants (fencing / GPU-handoff eviction / crash-atomic reconcile / verified-generation endpoint / Job-Object ownership) + CanServe() + drop LRU/idle-timer/prefix-reuse from the correctness path; pool stays default-OFF"
- **Module/area (exclusive):** `modules/07-model-gateway` ONLY (+ its tests; `models.json` pool/residency config if needed)
- **GPU:** true -- `gpu:true` ONLY on the GPU lane
- **Docs:** `[]` (always -- workers never edit core-docs; the orchestrator mirrors)

## Mission

Harden the i14 warm multi-model pool (mechanism C, OPT-IN / default-OFF, commit 09a7e71, skill 0.3.0) to Stage-1.1 per
`modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10 (the folded frontier red-team's ranked findings) so it can be
enabled by default: close the CRITICAL integrity invariants + `CanServe()` + the config-hash/generation split, and drop
LRU / the idle-timer / prefix-reuse from the correctness path. The pool STAYS default-OFF until these + a fault-injection
suite pass (D-0067).

## Unit (the full worker prompt)

HARDEN the i14 warm pool (mechanism C, OPT-IN / default-OFF) to Stage-1.1 so it can be ENABLED BY DEFAULT. Your detailed spec is `modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10 (the red-team's 15 ranked findings) -- READ IT; this brief scopes which to close now.

CLOSE (edit ONLY modules/07-model-gateway + its tests + models.json pool/residency config if needed) -- the CRITICAL integrity invariants:
(1) FENCING: a monotonic per-acquire FENCING TOKEN, CAS on every kill/start/publish/evict; short renewable TTL (~90-120 s, renew ~30 s, NOT 1800 s); a task whose renewal lapses loses ALL authority; every inference call carries its expected resident generation and is REJECTED on mismatch.
(2) GPU-HANDOFF EVICTION: an enforced AcquirePreparedGpu(owner, required_vram) or evict-before-release; no blind co-load -- releasing the gpu lease with the 9B resident does NOT free VRAM for another consumer (~2902 MiB free vs ~6.7 GiB needed -> OOM).
(3) CRASH-ATOMIC TRANSITIONS: a durable state machine EMPTY -> STOPPING -> EMPTY_CONFIRMED -> STARTING -> RESIDENT via atomic replace; the manifest is a CLAIM to VERIFY; reconcile on EVERY gateway startup under a MACHINE-GLOBAL named mutex.
(4) VERIFIED-GENERATION ENDPOINT: unique nonce + unique port + recorded PID/creation-time + exe/backend hashes; VERIFY the listening socket's owner before publish (a /v1/models alias is NOT proof) -- a fixed port + /health can validate the WRONG generation.
(5) JOB-OBJECT OWNERSHIP: own the whole child tree with a Windows Job Object held by the persistent gateway supervisor; never kill by PID alone; 'assert 0 orphaned llama-server' means 0 UNMANAGED servers AND must never kill the intended warm resident.
Plus the ENABLING fixes: (6) SPLIT resident_config_hash (deterministic; hash file CONTENTS, not paths) vs instance_generation (per-launch nonce) -- generation_id must NOT be in the config fingerprint or reuse dies. (7) replace exact-equality with CanServe(resident, request): exact for identity fields, '>=' for capacity (a 32K resident serves 16K; a resident 9B serves an M0 request -- run M0/M1 on the resident 9B, do NOT downshift to the 3B for the floor).
DROP from the correctness path (findings 10/11/12): LRU (meaningless at capacity 1); the fixed 90 s idle-unload timer (leave resident until an incompatible demand / another GPU owner / explicit shutdown); same-model PREFIX REUSE (cross-task KV-bleed risk -- returns later with erase-on-checkout + on-check-in).
FRAMING: the pool is an OPTIONAL layer, never the sole execution authority -- keep a legacy --bypass-pool-manager escape; new GUARDS are override-safe, the INTEGRITY invariants are NON-bypassable.

DO NOT (this wave): the native --models router / --slot-save-path / any coding specialist (Stage-2); res.lease #29 changes (findings 13 + 14 are a SEPARATE single-worker infra wave); agent.local #21 / route.tools #27 / governor code; finding-7's extra key-field long tail (name as a follow-on). FOLD finding 15 (target-headroom + WDDM-async eviction confirmation) into the eviction work. models.json otherwise UNCHANGED; pool ships DEFAULT-OFF.

GATE off-machine FIRST (cloud pwsh 7.4.6 + mock/seam): fencing CAS, state-machine, CanServe(), the hash split, reconcile + parsers unit-tested with mocks; Windows-only probes (Job Object, nvidia-smi, socket-owner) degrade to 'unknown' off-Windows, never throw. AST-parse all .ps1/.psm1; dev.ship named modules/07 files under the git lease (fail-closed; trailers). REQUIRED before 'done': the section-10 FAULT-INJECTION suite (crash at each transition + reconcile; forced fence/lease expiry mid-request; stale idle-callback vs fresh request; Job-Object reap + PID-reuse; KV isolation across crash/cancel; GPU-handoff eviction). If a Critical invariant can't close in one slot: ship what's solid, keep the pool default-OFF, say what remains (D-0061).

**Plan-side spec (orchestrator):** dispatched in plan `fo-15-27a03513` at `-MaxParallel 3` (workers-i15.json id `WMP-stage11`, `gpu:true`, `docs:[]`, `needs_git:true`, `skill_id:model.gateway`); emitted convenience copy:
`modules\30-orchestrate-fanout\runtime\artifacts\dc1cc706-3e18-48f0-a48c-4ea501bbf9a2\workers\worker-WMP-stage11.prompt.md`.

## Rails (standing rules -- keep in every brief)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine first (cloud pwsh 7.4.6 + a mock/seam harness), then `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire res.lease(s): **gpu -> git**, but apply the finding-14 discipline WITHOUT changing #29: do the edit+test under the **git** lease, RELEASE git, then take the **gpu** lease ONLY for the live fault-injection verify -- never hold the GPU idle waiting on git, never nest gpu-under-git. Release in reverse on exit.
- Persistent `llama-server` launches **DETACHED**, is reaped via the Job Object before finalize, assert 0 UNMANAGED orphans (the D-0055/56 wedge).
- Runtime-behavior change => a **real-model live check** (the fault-injection suite + a real 3B<->9B swap) before "done" (D-0060/D-0064).
- The pool ships **default-OFF**; `models.json` otherwise UNCHANGED (any change re-verifies Module 7 28/28).
- Report back: `-Action report -PlanId fo-15-27a03513 -WorkerId WMP-stage11 -State done` + a plain summary of measured results; negative results are first-class (the D-0061 ethos).

## Verification

Live on the box, through the executor: the **fault-injection suite** passes (crash at each transition + reconcile; a
forced fence/lease expiry mid-request REJECTED with no wrong-generation call landing; a stale idle-callback vs a fresh
request; Job-Object reap + PID-reuse; KV isolation across crash/cancel; the GPU-handoff eviction frees VRAM for a second
consumer). A real 3B<->9B swap still reuses (~1 ms) / swaps (~1.6-4.1 s) / evicts on a `CanServe()` miss; 0 unmanaged
`llama-server` before/after; leases released. Module 7 suite green (base 42/42 + warm 23/23 + pool + new Stage-1.1
tests). Emit a Verification Console `run_module` item (a swap + a fence-expiry rejection) at handoff. If a Critical
invariant can't close in one slot: ship what's solid, keep the pool default-OFF, name what remains (D-0061).

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)
