# WORK ORDER (research-staged) — split the GPU lease: execution/transition lease + revocable residency pin

**Staged in `claude/research/` at Nicholas's instruction** (2026-07-30), not yet in a module folder. This is
revision **R1** of the self-tasking-orchestration trajectory review
(`claude/research/2026-07-30-self-tasking-orchestration-trajectory-review.md`). It is the **keystone** for
that direction AND the standing **CPU candidate** already on the i18 menu (`FANOUT_ORCHESTRATOR_HANDOFF.md`
§4 → "the res.lease #29 fencing infra wave, findings 13/14"), so it does double duty. Single-worker wave
(core-infra rule, §8). When promoted, copy into `modules/29-resource-lease/WORK_ORDER.md` (+ the consumer
notes into #7/#21).

---

## Work Order: GPU lease split (`res.lease` #29 + `model.gateway` #7 pool manager + `agent.local` #21 governor)

**Contract version targeted:** 0.1 · **Author:** Claude (Opus, review session) 2026-07-30 ·
**Roadmap entry:** `MODULE_ROADMAP.md#29` (res.lease) + `WARM_POOL_DESIGN.md` §10 findings 1/13/14

### Problem being solved

Today the `gpu` `res.lease` is acquired **once for the whole ramped task** and held to the end — a
deliberate rule (`ADAPTIVE_RESOURCE_GOVERNOR.md` §6; `WARM_POOL_DESIGN.md` §4) to stop another process
swapping the resident model mid-task. That single behavior blocks two things at once: **(a)** it starves
higher-priority GPU work while a long task sits idle between model calls (Stage-1.1 red-team **finding #13**),
and **(b)** it structurally prevents the *relinquish-to-execute-then-reacquire* hand-off that a sequential,
single-GPU, multi-agent baton-pass orchestrator needs (trajectory review §2). Releasing the lease while the
model stays GPU-resident is also unsafe today: it frees the *lock* but not the *VRAM* (~2902 MiB free vs
~6.7 GiB needed → OOM for the next owner — **finding #2**).

This unit replaces "one whole-task lock" with **two concerns**: a short-held **execution/transition lease**
(held only while loading, unloading, or generating) and a separate **revocable residency pin** (the right to
*stay* GPU-resident, which a higher-priority demand can revoke). It carries the fencing (**finding #1**) and
lock-order-inversion (**finding #14**) invariants the same wave needs.

### Immediate practical use

- **Warm-pool default-ON gate.** `WARM_POOL_DESIGN.md` §10 names findings 13/14 as a remaining gate to
  enabling the pool by default. This closes them.
- **Baton-pass keystone.** Makes mid-task GPU hand-off a first-class, safe operation — the prerequisite for
  R2–R4 (pool default-ON → strong preflight → the sequential local orchestrator).
- This week: the governor (`agent.local -AutoRamp`) and the pool manager (`Ensure-ResidentModel`) switch from
  "hold the lock end-to-end" to "hold the execution lease only around GPU ops; hold a revocable pin between
  them," with **no behavior regression** on the single-agent path.

### Explicit scope (in)

- **`res.lease` #29:** add a monotonic **fencing token** per acquire (finding #1); a **residency pin** lease
  kind distinct from the execution lease, revocable by a higher-priority acquire; **compare-and-swap the
  token** on every kill/start/publish/evict; a task whose renewal lapses loses all authority. Reject
  **lock-order inversions** (gpu acquired while holding git, etc. — finding #14).
- **`AcquirePreparedGpu(owner, required_vram)` handoff (finding #2):** an acquire that inspects the current
  resident + free VRAM, evicts if incompatible, and confirms headroom (WDDM-async-safe confirmation interval,
  target-headroom invariant — finding #15) **before** granting. Evict-before-release semantics.
- **`model.gateway` #7 pool manager:** consume the split — hold the **execution lease** only across
  load/evict/generate; hold the **residency pin** between calls; honor pin revocation (evict cleanly on
  demand); every inference call carries its expected resident **generation** and is **rejected on mismatch**
  (finding #1, already partly shipped in Stage-1.1).
- **`agent.local` #21 governor:** the ramped task takes a residency pin for its model-affine segment and the
  execution lease only around each LLM call; a build-then-verify unit may release the pin between phases.
- **Tests + live verify** on the box (below).

### Non-goals (out — do NOT build)

- The **sequential local orchestrator** (#26 baton-pass mode) — that is R4, a later wave.
- **Strong-tier preflight** (`route.tools`) — R3, separate.
- **Flipping the warm pool to default-ON** — that is the orchestrator's call after a soak; this unit only
  removes one of its gates.
- Native `llama-server` router / `--slot-save-path` — Stage-2+ (WARM_POOL_DESIGN §6).
- Any change that lets two ~7 GB models co-reside — physically impossible on 11 GB; the one-active-model
  invariant stays non-bypassable.

### Dependencies

- Modules: `res.lease` #29 (primary), `model.gateway` #7 (`lib/PoolManager.psm1`, `Start-GatewaySupervisor.ps1`),
  `agent.local` #21 (governor). Tools/models: the resident 3B/9B tiers (`models.json`, unchanged). Contract
  features: lease acquire/release/renew/status + the new token + pin fields.
- Prereq state: the durable Job-Object supervisor (finding #5, shipped i16) — the pin must be owned by the
  supervisor's Job Object, not a per-call PID.

### Skill contract requirements

- `res.lease`: determinism det; `parallel_safe:true`; new result fields `fencing_token`, `lease_kind`
  (`exec`|`residency_pin`), `revocable`, `revoked_by`. Manifest version bump; log the contract change in
  `DECISION_LOG.md`.
- No change to model.gateway's public envelope beyond a `server.warm.pool.lease` sub-block reporting
  token + pin state.

### Inputs and outputs

- **Inputs:** `res.lease <acquire|release|renew|status|list>` gains `-Kind exec|residency_pin`,
  `-RequiredVramMiB <n>` (for `AcquirePreparedGpu`), `-FencingToken <n>` (renew/CAS), `-Priority <n>`.
- **Outputs:** the lease record + monotonic `fencing_token`; on a revoked pin, `revoked_by` + the evict
  confirmation; on `AcquirePreparedGpu`, the confirmed free-VRAM headroom.

### Artifact structure

- `modules/29-resource-lease/runtime/leases/` — the lease files gain the token + kind + pin fields.
- `modules/07-model-gateway/runtime/warmpool-*/` — residency manifest records pin generation + token.

### Proposed implementation

- **Language:** PowerShell (matches #29/#7). Reuse the crash-atomic state machine + machine-global mutex
  from Stage-1.1 (`lib/PoolManager.psm1`). The token is a monotonic counter persisted under an atomic
  replace; CAS = read-verify-write under the mutex.
- Keep every new guard **override-safe** (explain / recommend / override-with-recorded-reason / safe
  degraded path), while the **integrity invariants stay non-bypassable** (fencing, single-endpoint
  ownership, verified-model routing, no cross-task KV, no blind co-load) — the Stage-1.1 framing
  (`WARM_POOL_DESIGN.md` §10).

### External tools or models

- None new. All present (`TOOL_MODEL_REGISTRY.md`).

### Installation steps

- None (code-only). Ship via `dev.ship` (sha256 + AST + tests, fail-closed, named files, under the `git` lease).

### Tests

- **Off-machine first (cloud pwsh 7.4.6 + mock/seam):** token monotonicity; CAS rejects a stale token;
  `AcquirePreparedGpu` evicts an incompatible resident + confirms headroom before granting; pin revocation
  path; lock-order-inversion rejection; renewal-lapse revokes authority; **no regression** on the classic
  single whole-task path (byte-for-byte with the split disabled).
- **Fault injection (reuse the Stage-1.1 suite):** crash at each transition then reconcile; forced
  lease-expiry during a live request; stale idle-callback vs a fresh request; Job-Object tree reap +
  PID-reuse; KV isolation across crash/cancel; the GPU-handoff eviction.
- **Live on the box (executor):** a real M0→S0 ramp holds a pin + short exec leases (3B→9B swap ~4.1 s,
  reuse ~1 ms), a second simulated owner **revokes the pin and safely evicts** (≥ target headroom recovered,
  0 orphaned `llama-server`), lease + pin released, heartbeat `degraded:false`.

### MVP acceptance criteria

- Exec lease vs residency pin are distinct and independently held/released. ✅
- A higher-priority acquire revokes a pin and gets a **prepared** GPU (confirmed headroom, not just a freed
  lock). ✅
- Fencing token rejects a stale owner's kill/publish/inference. ✅ Lock-order inversion rejected. ✅
- The single-agent governor path is unchanged in outcome (same completions, same swap counts) with the split
  ON. ✅ 0 orphans, lease+pin released, every wave. ✅

### Manual verification procedure

- Run the governor liveA/liveB gates with the split ON; confirm identical epochs/completions to the
  pre-split baseline. Then run two overlapping GPU tasks and confirm the second revokes + safely evicts the
  first's pin.

### Documentation requirements

- `res.lease` `README.md` + `skill.json` (new fields + the two lease kinds); `WARM_POOL_DESIGN.md` §10
  (findings 1/13/14 → CLOSED); a `DECISION_LOG.md` D-entry + index row.

### Registry updates

- `TOOL_MODEL_REGISTRY.md` #29 entry: the split, the token, `AcquirePreparedGpu`, last test.

### State updates

- `CURRENT_STATE.md` (governor + warm-pool residuals: findings 1/13/14 closed; note remaining default-ON
  gate = soak only); `MODULE_ROADMAP.md` #29 status.

### Known follow-on work

- R2 pool default-ON (after a soak). R3 strong preflight. R4 the sequential local orchestrator (#26
  baton-pass). Contention-driven eviction over any timed idle (finding #11). A fair GPU scheduler /
  admission by resident-affinity (finding #10).

### STOP conditions

- Scope would exceed the in-list (do NOT start R2/R3/R4 here).
- The split cannot be made regression-free on the single-agent path → stop, report, keep the whole-task
  lease as the default and gate the split behind an opt-in flag.
- Any path would allow two big models to co-load, or a pin to be non-revocable → stop; those invariants are
  non-negotiable.
- MVP acceptance met → stop; do not start the next unit.
