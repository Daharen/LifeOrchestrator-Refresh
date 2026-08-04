# RESLEASE-R1b-consumers (i19, plan fo-19-3aa34fe9) -- SHIP STATE

**Worker:** FANOUT_AGENT_001 / `RESLEASE-R1b-consumers` (GPU lane, single-worker wave).
**State:** `done` (report filed to `plans/fo-19-3aa34fe9/reports/RESLEASE-R1b-consumers.1c9c859d.json`).
**Outcome:** the **R1b res.lease #29 PRIMITIVE layer shipped + committed**; the **consumer wiring (#7/#21) + real
evictor + live-GPU proof did NOT ship** (the work order's fallback -- shipped the solid subset behind the
additive/default-off surface; findings 1/13/14 stay OPEN). Negative results first-class (D-0061 ethos).
**A frontier concurrency/safety red-team was folded (below) -> it GREW the R1b remainder and set i20 = R1b'.**

## Shipped (committed, verified real HEAD)

- **Commit `2d45ffe4c8e64baa3ffe3450ea750541eec9780b`** on `master` -- verified via native `git log` (D-0072:
  dev.ship `committed:true` AND native HEAD confirmed; no stale `.git/index.lock`; git lease acquired+released).
  Re-confirmed at i19 close-out: HEAD == `2d45ffe`, 4 files +526/-17, trailers present; box `degraded:false`,
  leases dir empty.
- **res.lease #29 -> v0.3.0** (contract 0.3), 4 named files (+526/-17): `Invoke-ResLease.ps1`, `skill.json`,
  `README.md`, `tests/Invoke-ResLeaseR1bTests.ps1` (new).
- **What it adds (ADDITIVE, DEFAULT-OFF; a plain call is BYTE-IDENTICAL to v0.1, a v0.2-engaged call unchanged):**
  three-identity fencing (`gpu_authority_epoch` / `resident_generation` / `exec_lease_id` + the `authority_ok`
  full-tuple gate), the single scheduler-owned atomic `-Transition` (reserve -> mint epoch -> revoke pin ->
  drive the evictor OUTSIDE the lease mutex via a `<resource>.txn` journal -> confirm tree gone -> confirm
  headroom STABLE across N obs ~250ms apart -> grant ONLY if the reserved epoch is still current), in-flight
  revocation (late/stale-epoch result DISCARDED), an adversarial MOCK evictor + crash reconcile. res.lease
  stays PURE (real evictor plugs into `-EvictorMode command`).
- **Gate (green BOTH off-machine cloud pwsh 7.4.6 AND on-box):** v0.1/v0.2 baseline **74/74** (0 regression);
  v0.3 R1b adversarial **36/36**; dev.ship fail-closed, **0 orphaned llama-server/python**, `review_queue.jsonl`
  before == after.

## Frontier red-team folded (pack `b823d9db`, captured `modules/31-frontier-bridge/runtime/artifacts/b823d9db-72c1-4a05-aeaf-867e39f5330c/frontier-pack-i19-r1b-redteam.answer.md`; read-return `captured/valid`, sha256 `f607fc88...`)

**Verdict:** the three identities are conceptually necessary but **NOT sufficient**, and the transition is
**unsafe as ordered** -- it grants an ordinary execution lease before the new resident is loaded / healthy /
published. Deepest hole: R1b fences state *transitions* under the mutex, but the dangerous *side effects*
(process kill, manifest write, stop callback, server start) happen OUTSIDE it, and rejecting a stale txn at
recommit does not undo a kill that already fired -> **every async side effect must be fenced AT THE TARGET.**
**Findings 1/13/14 cannot close even on the planned live proof** (this VINDICATES the worker's fallback).

**Must-block changes (its section 8 + closure lists) -> the i20 R1b' spec:** (1) grant-before-ready ->
start under a scheduler-only *transition capability*, publish+grant atomically only after health; (2) add
`owner_incarnation_id` + `resident_instance_id` (random, never reused; target destructive ops at
`resident_instance_id`, never generation/PID/port/config_key), exec_lease_id -> UUID -> closes ABA;
(3) target-fenced callbacks (CAS transition_id+epoch+instance+lease+state_version in the SAME critical section;
supervisor rejects a stop unless the immutable target matches); (4) idempotent saga journal (recommit checks
transition_id+phase+state_version+target+epoch, not epoch alone) + distinguishable STARTING/HEALTHY_UNPUBLISHED/
COMMITTED phases + commit-response idempotency; (5) Job-Object spawn-before-assignment fix (suspended-create ->
assign -> resume); (6) reserve+fence = one atomic commit; + the adversarial matrix A-K. Long-run repetition /
latency stay for the soak. **Acceptable default-off residuals** (its list): WDDM prep-failure, empty-GPU abort,
suboptimal timeouts, basic same-priority fairness, supervisor-crash service interruption, unproven long-tail --
warm-pool default-ON stays prohibited regardless.

## NOT shipped -- remaining R1b (findings 1/13/14 stay OPEN); now split into R1b' + the consumer wave

- **i20 = R1b' (single-worker, CPU, gpu:false):** fold the red-team's must-block changes into the res.lease
  PRIMITIVE (0.3.0 -> 0.4.0) + the off-machine-provable adversarial matrix (A-K mock). Brief:
  `claude/fanout/FANOUT_AGENT_001.md`. Does NOT close 1/13/14; makes the primitive safe to build on.
- **A later wave (GPU, single-worker):** #7 PoolManager + #21 governor adoption (behind `-UsePoolLeaseSplit` /
  `-SplitLease`, default-off) + the real `PoolEvictor.ps1` (nvidia-smi) + the live-GPU 3B<->9B swap /
  pin-revocation / prepared-eviction proof + the live-only tests (real OOM, real supervisor/descendant, real
  WDDM pressure). **Only then** findings 1/13/14 -> CLOSED, then a soak, then R2 default-ON.

## Rails honored

`docs:[]` (touched only #29's own files + this report state doc + the delivered spec; did NOT edit shared
core-docs -- the orchestrator mirrors/folds). Build + off-machine gate FIRST; landed files byte-exact; dev.ship
under the `git` lease (holder `RESLEASE-R1b-consumers`), released after; verified real HEAD via native git; never
held `gpu` idle (no live-GPU work attempted this wave). Executor healthy throughout (`degraded:false`).
