# RESLEASE-R1bprime-primitive-hardening (i20, plan fo-20-a28f65da) -- SHIP STATE

**Worker:** FANOUT_AGENT_001 / `RESLEASE-R1bprime-primitive-hardening` (CPU lane, single-worker core-infra wave).
**State:** `done` (report filed to `plans/fo-20-a28f65da/reports/RESLEASE-R1bprime-primitive-hardening.f15bb059.json`; `status` -> `ready_for_handoff: true`, 1/1 done).
**Outcome:** the **R1b' res.lease #29 PRIMITIVE HARDENING shipped + committed + verified**. Folds the i19 frontier
concurrency/safety red-team (pack `b823d9db`) MUST-BLOCK changes into the primitive so the GPU-lease split is
**safe to build on**. Does **NOT** close findings 1/13/14 (the later #7/#21 consumer + live-GPU wave does).

## Shipped (committed, verified real HEAD)

- **Commit `f6df675fc3c9e1a131f17e06f5a4843284870d78`** on `master` (parent `430beee`) -- verified via native
  `git log` + `git show --stat` (D-0072: not the dev.ship `committed` field). 5 NAMED module-29 files only,
  **+887/-65**, trailers present (`Co-Authored-By: Claude Opus 4.8` + `Claude-Session`).
- **res.lease #29 -> v0.4.0** (contract 0.4), 5 files: `Invoke-ResLease.ps1`, `skill.json`, `README.md`,
  `tests/Invoke-ResLeaseR1bPrimeTests.ps1` (NEW, the v0.4 adversarial gate), `tests/Invoke-ResLeaseR1bTests.ps1`
  (version-pin T0 0.3.0->0.4.0; the 36 behavioral assertions unchanged).
- **Gate green BOTH off-machine (cloud pwsh 7.4.6) AND on-box (Windows pwsh 7.4.6 via the executor):**
  v0.1/v0.2 baseline **74/74** (0 regression; on-box **77/77** with the Module-1 wrapper live) + v0.3 R1b
  **36/36** + NEW v0.4 R1b' adversarial **45/45**. dev.ship fail-closed ALL GREEN (sha 5/5 byte-exact, AST 3/3,
  tests exit 0). **0 orphaned llama-server/python** (dev.ship on-box + `pgrep -x` = 0). `review_queue.jsonl`
  **20 == 20** (non-producer). Leases dir empty. Heartbeat `degraded:false`.
- **Backward-compat proven LIVE:** dev.ship acquired + released its OWN `git` lease via the NEW v0.4 res.lease
  (`git_lease.acquired=true`, `waited_ms=66`, released) -- a plain `git` acquire stays byte-identical.

## What shipped (ADDITIVE + DEFAULT-OFF + backward-compatible; a plain / v0.2 / v0.3 call is byte-identical)

1. **Incarnation identities close ABA (finding 1, blockers 2/3).** `owner_incarnation_id` (random per
   owning-process/supervisor-client RESTART) + `resident_instance_id` (random per actual server process TREE,
   the **target of every destructive op**, never reused). `resident_generation` stays a human counter, never a
   destructive-op target; `exec_lease_id` is a UUID. Folded into `check.authority_ok`
   (`owner_incarnation_current` + `resident_instance_current`). A restarted owner (new incarnation) OR a callback
   captured against the old instance is **fenced out**.
2. **Two-phase transition (blocker 1 -- no grant-before-ready).** `-Transition -TwoPhaseCommit` issues a
   **NON-usable** `transition_capability` (`usable:false`; the new server starts under scheduler authority, not
   an ordinary exec lease); `-Action commit -HealthOk` publishes + issues the first **usable** exec lease AFTER
   health (`STARTING -> HEALTHY_UNPUBLISHED -> COMMITTED`). Default single-shot `-Transition` stays
   byte-compatible (36/36). Fail-closed prep semantics (headroom-never/fell, partial-tree, `-HealthFailed`/OOM,
   capability expiry, `superseded_during_transition`) -- never "the exec lease already belongs to the
   requester"; `-HealthFailed` drops the exact tentative instance + leaves the GPU **empty**.
3. **Target-fenced side effects (blockers 4/8, finding 14).** NEW `-Action fence-op`: a stop/kill/result-publish/
   manifest-write/lease-release/renew/health-fail/idle-evict/complete MUST name an exact `-ResidentInstanceId`
   (+ optional epoch/exec-lease/state-version); a stale target is REFUSED. "Stop whatever serves this resource"
   -> `target_instance_required`. This is the authority the real supervisor consults BEFORE any destructive op.
4. **Idempotent saga journal (blocker 5).** The `<resource>.txn` journal carries the red-team field set
   (`request_id`, requester owner/incarnation, epoch_from/to, phase, state_version, old/new resident_instance_id,
   target_config_key, `operations[]` + receipts, deadline, cancel_requested, last_error, retry_count,
   grant_lease_id). `request_id` **commit-response idempotency**: a retry returns the SAME grant (single-shot AND
   two-phase), never a 2nd epoch/lease/resident. Reconcile recognizes every durable phase.
5. **An oplock-serialized (fail-closed) renew can NEVER resurrect a revoked lease.** The fenced renew + the pin
   revoke serialize on a per-resource oplock; the renew re-reads under the lock and refuses to write without it.
   (Fixed a real resurrection race in the prior renew; the renew now preserves the FULL v0.3/v0.4 identity ext.)
6. **A durable per-resource `state_version`** bumps on grant/renew/revoke/release/commit; waiters re-read it
   (never a one-shot signal); a stale captured `state_version` is fenced out (finding 14 / test K).
7. **Job-Object contract (blocker 6) -- PRIMITIVE side only.** The primitive DEFINES the contract; the mock
   supervisor seam ENFORCES target-fenced stop. The real launcher chain is the consumer wave.

## Adversarial matrix (tests/Invoke-ResLeaseR1bPrimeTests.ps1, 45/45, MOCK)

**A** ABA recovery, **B** commit-response loss (single-shot + two-phase), **C** stale side-effect matrix (all 8
late ops from an old instance refused), **D** superseded external op, **E** reentrant evictor (no deadlock /
lock-order inversion / second transition), **F** renewal/revocation race, **G** active preemption liveness, **H**
partial-alloc-fail (later clean transition succeeds), **J** lease expiry in every durable phase, **K** waiter
sequencing. **DEFERRED (NOT faked; listed in the suite + README):** real GPU OOM on a real partial load, a real
supervisor/descendant escape + PID reuse, real WDDM external-consumer pressure, and the real 3B<->9B swap/
pin-revocation/prepared-eviction proof. "3 obs ~250ms apart" documented as a HEURISTIC, not a guarantee.

## NOT shipped -- findings 1/13/14 STAY OPEN

They close ONLY after the later **consumer + live-GPU wave**: model.gateway #7 PoolManager + agent.local #21
governor adoption of the split (behind a default-off flag) + the real nvidia-smi/eviction evictor
(`-EvictorMode command`) + the live-GPU 3B<->9B swap / pin-revocation / prepared-eviction proof + the live-only
tests (real OOM, real supervisor/descendant, real WDDM pressure). Then a soak, then flip the warm pool
default-ON. This wave made the primitive safe to build on.

## Orchestrator to mirror/fold (worker used docs:[] -- touched only #29 files)

`CURRENT_STATE.md` + `MODULE_ROADMAP.md` (res.lease -> 0.4.0) + `TOOL_MODEL_REGISTRY.md` + a `DECISION_LOG`
D-entry + `WARM_POOL_DESIGN.md` section 10 (the R1b' primitive-hardening note; default-ON still gated on the
consumer wave + soak). Verification Console item: a mock two-phase transition showing the atomic hand-off +
a target-fenced stale stop REFUSED (`fence-op`) + an ABA-recovered stale callback REFUSED (`check`
`authority_ok=false`).

## Rails honored

`docs:[]` (touched ONLY modules/29-resource-lease/ own files). git lease holder
`RESLEASE-R1bprime-primitive-hardening`, released after. Build + off-machine gate FIRST; landed byte-exact
(sha 5/5); dev.ship under the git lease; verified real HEAD via native git. Never held `gpu` (no live-GPU work).
Executor healthy throughout (`degraded:false`).
