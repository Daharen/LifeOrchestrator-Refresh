# FANOUT_AGENT_001 -- i18 SOLE worker: R1a, the res.lease #29 lease-split keystone

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i18 -- plan id `fo-18-c2d73598`
- **Lane:** CPU core-infra -- **SINGLE-WORKER wave** (res.lease #29 is core infra, live-exercised by this wave's own executor/git-lease machinery; NO co-lanes -- slots 002/003 stay EMPTY)
- **Worker id / label:** `RESLEASE-R1a-split` (spec: `modules/30-orchestrate-fanout/runtime/workers-i18.json`; verbatim emitted prompt: `modules/30-orchestrate-fanout/runtime/artifacts/5c4c71bb-e09d-47ba-baad-6108bb627ffb/workers/worker-RESLEASE-R1a-split.prompt.md`)
- **Module/area (exclusive):** `modules/29-resource-lease` ONLY
- **GPU:** false -- no GPU, no model
- **Docs:** `[]` (the orchestrator mirrors all core-docs; you REPORT results)

## Mission

Build **R1a** -- the GPU-lease-split KEYSTONE at the **res.lease #29 PRIMITIVE layer**. It turns mid-task
GPU hand-off from a hazard into a first-class, safe op (the literal answer to
"relinquish-to-execute-then-reacquire") and closes `modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10
findings 1/13/14 -- one of the two remaining gates (with a soak) to warm-pool default-ON. **GOVERNING work
order (read it IN FULL first):** `core-docs/research/2026-07-30-work-order-gpu-lease-split.md` (R1) -- this
wave is its **res.lease-primitive slice**. The `model.gateway` #7 PoolManager + `agent.local` #21 governor
consumer adoption + the live real-model swap/eviction proof are **DEFERRED to R1b** (a GPU-lane follow-on) --
NOT this wave.

## Unit (self-contained scope; the R1 doc + WARM_POOL_DESIGN section 10 carry the exhaustive detail)

READ FIRST: `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` (pwsh 7.4.6 gotchas: empty-array-unroll
-> assign `$x=@()` first; array-double-wrap `,$out` with `@()`; `@($list)` on a `List[object]` -> use
`.ToArray()`/`.Count`; `${var}` not `$var:` in double-quoted strings; JSON-serializable meta; atomic-write /
stale-stage discipline; "trust the heartbeat, not the process list") + the **R1 work order**
(`core-docs/research/2026-07-30-work-order-gpu-lease-split.md` -- the two lease kinds, AcquirePreparedGpu,
the exact schema fields, the STOP conditions) + `core-docs/research/2026-07-30-self-tasking-orchestration-trajectory-review.md`
sections 2 + 6 (WHY the split) + `modules/29-resource-lease` (`Invoke-ResLease.ps1`, `skill.json`,
`README.md`, `WORK_ORDER.md`, `tests/Invoke-ResLeaseTests.ps1` -- the acquire/release/renew/status/list
surface, the `File.Open` CreateNew atomic primitive, the rename-CAS stale reclaim, the holder + `lease_id`
model, same-holder re-attach) + `modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10 (findings 1, 2, 13,
14, 15 verbatim + the Stage-1.1 residuals paragraph naming THIS wave) + `FANOUT_ORCHESTRATOR_HANDOFF.md`
section 8 (the gpu -> git -> doc acquire order + the build-then-verify rule). Obey `SKILL_CONTRACT.md`.

SCOPE IN -- edit ONLY `modules/29-resource-lease/` (`Invoke-ResLease.ps1` + `skill.json` + `README.md` +
tests + examples). Build these FOUR, all ADDITIVE + DEFAULT-OFF:

1. **Monotonic fencing token (finding 1).** A strictly-increasing PER-RESOURCE integer `fencing_token`
   minted on every FRESH grant (new acquire, or an acquire that wins a stale reclaim), PERSISTED per
   resource (a durable sibling counter, e.g. `<sanitized-resource>-<hash8>.fence`, under the same
   atomic-replace discipline as the lease) so it is monotonic even across the lease file being deleted on
   release. Return it on acquire/renew/status. Same-holder re-attach + renew keep the SAME token; a fresh
   grant after release/stale-reclaim is STRICTLY GREATER; the racing winner's token exceeds the prior
   holder's. Add a CAS surface -- a `check`/`validate` action or a `-FencingToken <n>` guard on
   renew/release that REJECTS `fence_stale` when the caller's token is not current (so a superseded holder
   is FENCED OUT, not merely TTL-abandoned).

2. **The two lease kinds -- exec vs revocable residency pin (finding 13, THE KEYSTONE).** Add
   `-Kind exec|residency_pin` (DEFAULT `exec` = today's behavior) + result fields `lease_kind`,
   `revocable`, `revoked_by`. `exec` = a short execution/transition lease (held only while
   loading/unloading/generating). `residency_pin` = the revocable right to STAY resident between exec ops;
   a higher-`-Priority <n>` acquire REVOKES a lower-priority pin (write `revoked_by` + the new holder's
   `fencing_token` into it) so the pinned holder learns on its next renew/`check` that it has LOST
   AUTHORITY (cooperative, fencing-backed revocation). A pin must ALWAYS be revocable (non-revocable pin =
   STOP).

3. **Prepared-handoff / evict-before-grant PROTOCOL (findings 2/15) -- primitive layer only, MOCK-EVICTOR
   seam.** res.lease is a pure filesystem lease and CANNOT inspect VRAM or kill a llama-server (that is
   PoolManager's job = R1b, DEFERRED). Implement the res.lease-level HANDSHAKE: an AcquirePreparedGpu-style
   variant (`-Kind exec -Resource gpu -RequiredVramMiB <n> -Priority <n>`) that (a) detects an
   incompatible/lower-priority resident pin, (b) drives the revocation signal from (2), (c) exposes a
   PLUGGABLE evictor-callback / confirmation-handshake SEAM (a scriptblock/command hook + a target-headroom
   + WDDM-async confirmation-interval contract) supplied by a consumer, and (d) grants ONLY AFTER the seam
   confirms headroom. Ship a MOCK evictor for the tests (confirm / needs-evict / timeout). Keep res.lease
   PURE (no nvidia-smi, no server kill in #29); document the real PoolManager evictor as the R1b integration
   point.

4. **Lock-order-inversion rejection (finding 14).** Canonical rank `gpu -> git -> doc:<path>`. On acquire,
   scan the lease dir for leases held by THIS holder and REJECT fail-closed (`lock_order_violation`) the
   starvation inversion: a holder already holding `gpu` (block-)acquiring the cheaper `git`. Reconcile with
   the documented gpu->git->doc order (that governs deadlock-avoidance when multiple leases are needed at
   once; the point here is GPU-build work should SEQUENCE -- git for the commit, release git, then gpu for
   the live verify -- not hold gpu idle on git). Provide `-AllowLockOrder` + a recorded reason (override-safe,
   NOT a hard wall). Document the order + the build-then-verify pattern in README.

BACKWARD-COMPATIBILITY IS MANDATORY (the reason it's single-worker). res.lease is LIVE-exercised by this
wave's own executor/dev.ship git lease. Callers passing NONE of the new params (`-Kind` defaults `exec`; no
`-Priority`/`-RequiredVramMiB`/`-FencingToken`/`-AllowLockOrder`; not holding gpu-then-git) MUST behave
BYTE-IDENTICALLY -- in particular dev.ship's plain `git` acquire and plain gpu/doc acquires. Bump res.lease
`0.1.0 -> 0.2.0` (skill.json inputs/outputs/contract).

SCOPE OUT (NAME as R1b/follow-ons in README + report, do NOT build): PoolManager #7 + governor #21 consumer
adoption (hold exec-only around GPU ops, hold a revocable pin between them, honor revocation, per-call
generation-mismatch rejection); the REAL nvidia-smi/eviction evictor + the LIVE real-model 3B->9B swap +
pin-revocation + prepared-eviction PROOF on the GPU (R1b, GPU lane); flipping the pool default-ON + the soak;
fair FIFO / priority / reader-writer / re-entrant locks; cross-machine leases; an auto-renew daemon. Do NOT
touch `modules/07-model-gateway`, `modules/30-orchestrate-fanout`, `modules/00-bootstrap-executor`/dev.ship,
`doc.io` #20, `agent.local` #21, or ANY core-doc/other module. NEVER co-load two big models or make a pin
non-revocable (hard STOP conditions).

GATES: off-machine FIRST -- res.lease is pure pwsh 7.4.6 + .NET System.IO (CreateNew + rename-CAS identical
on Linux + Windows), so the REAL skill runs on the cloud gate with the evictor MOCKED. Extend
`tests/Invoke-ResLeaseTests.ps1` (dual-mode cloud + on-device `-Live`): fencing monotonicity across
release/re-acquire; token preserved on re-attach + renew; strictly-greater after stale reclaim; a real
CROSS-PROCESS concurrency run (background pwsh jobs, N>=5) -- exactly one winner AND winner's token exceeds
the prior holder's; CAS `fence_stale`; exec vs residency_pin distinct + independently held; higher-priority
acquire REVOKING a pin (revoked_by + fencing set); the prepared-acquire mock-evict handshake
(confirm/needs-evict/timeout); `lock_order_violation` + the `-AllowLockOrder` override; AND a plain
gpu/git/doc acquire with no new params is BYTE-IDENTICAL. Keep the harness ASCII-only; AST-parse every
shipped `.ps1`. Then `dev.ship` the named `modules/29` files under the git lease (FAIL-CLOSED; named files
only; trailers Co-Authored-By + Claude-Session). Baseline res.lease 41/41 `-Live` must STILL pass.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease in **gpu -> git -> doc** order; you need only **`git`** (for the dev.ship commit) --
  no gpu, no model. Release on exit.
- Do ONE unit; touch NOTHING outside `modules/29-resource-lease`; `docs:[]` (report; the orchestrator
  mirrors core-docs).
- 0 orphaned processes; `review_queue.jsonl` before == after (res.lease is a NON-producer).
- If a piece can't be made regression-free at the primitive layer, SHIP the solid subset behind the
  additive/default-off surface, keep default behavior byte-identical, and report PLAINLY what remains (the
  R1 STOP condition + the D-0061 ethos -- negative results are first-class).
- Report: `pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report
  -PlanId "fo-18-c2d73598" -WorkerId "RESLEASE-R1a-split" -State done -Summary "<one line>" -PlansDir
  "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"` (use `-State
  progress|blocked|failed` as needed).

## Verification (what proves the unit worked -- REPORT these for the orchestrator to fold)

- Baseline res.lease 41/41 `-Live` STILL green + the new fencing/kind/prepared/lock-order tests; cloud real
  + on-device `-Live` counts.
- The EXACT new schema: `fencing_token`; `-Kind`/`lease_kind`/`revocable`/`revoked_by`;
  `-RequiredVramMiB`/`-Priority`/`-FencingToken`; the check/validate action; `lock_order_violation` +
  `fence_stale` typed errors; `-AllowLockOrder`.
- Concrete traces: fencing monotonicity (acquire -> release -> re-acquire -> stale-reclaim), a pin
  revocation, a prepared-acquire(mock-evict), a lock-order rejection.
- Confirmation dev.ship's own git-lease acquire + a plain gpu/doc acquire are byte-identical (no new params).
- The NAMED R1b follow-on (PoolManager/governor wiring + real evictor + live-GPU proof); 0 orphans; queue
  unchanged; res.lease 0.2.0 byte-exact. A Verification Console `run_module` item (an exec acquire showing
  the `fencing_token` + a residency_pin revoked by a higher-priority acquire + a rejected lock-order acquire).

## Report-back record (ORCHESTRATOR fills from `plans/fo-18-c2d73598/reports/` before archiving)

_(pending worker report)_
