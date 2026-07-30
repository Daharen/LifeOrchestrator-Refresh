# FANOUT_AGENT_001 -- CPU lane: R1b' (res.lease primitive hardening, red-team-driven)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY -- dispatch into a fresh Cowork session with the one folder grant
  (`C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i20 (plan id `fo-20-<TBD>`; single-worker core-infra wave)
- **Lane:** CPU -- and the ONLY worker this wave (res.lease #29 is core infra => single-worker, D-0055/section 8).
- **Worker id / label:** `RESLEASE-R1bprime-primitive-hardening`
- **Module/area (EXCLUSIVE):** `modules/29-resource-lease/` ONLY. Do NOT touch #7/#21 -- consumer wiring +
  the live-GPU proof are a SEPARATE later wave.
- **GPU:** **false** (pure logic + adversarial MOCK tests; provable off-machine. No llama-server, no CUDA.)
- **Docs:** `[]` (the orchestrator mirrors + folds all core-docs).

## Why this wave exists

i19 shipped the R1b PRIMITIVE (res.lease `0.3.0`, `2d45ffe`: three-identity fencing +
scheduler-owned `-Transition` + adversarial mock evictor; 74/74 baseline + 36/36 adversarial, 0 regression).
The i19 frontier concurrency/safety red-team (pack `b823d9db`, captured under
`modules/31-frontier-bridge/runtime/artifacts/b823d9db-.../frontier-pack-i19-r1b-redteam.answer.md` --
**READ IT IN FULL**) found the identities **necessary but NOT sufficient** and the transition **unsafe as
ordered**. Findings 1/13/14 CANNOT close on the planned live proof until these are corrected. This wave folds
the **blocking** design changes into the primitive + adds the off-machine-provable adversarial tests. It does
NOT close 1/13/14 (that needs the later consumer + live-GPU wave); it makes the primitive safe to build on.

## Unit -- res.lease `0.3.0` -> `0.4.0` (ADDITIVE, DEFAULT-OFF; a plain acquire/release/renew/status/list stays BYTE-IDENTICAL to v0.1; v0.2/v0.3-engaged calls unchanged unless a blocker below requires a contract fix)

Fold the red-team's **must-block** items (its section 8 + closure lists). Each maps to a concrete change:

1. **Incarnation identity (blockers 2/3, finding 1 / ABA).** Add `owner_incarnation_id` (random, minted per
   owning-process/supervisor-client restart) and `resident_instance_id` (random, minted per actual server
   process tree). `resident_generation` stays a human-readable monotonic counter but is NEVER the target of a
   destructive op. `exec_lease_id` -> a UUID / large random, **never reused** (not a restartable counter).
   Every async op carries `owner_id + owner_incarnation_id + gpu_authority_epoch + resident_generation +
   resident_instance_id + exec_lease_id + transition_id`. Epochs + counters crash-durable BEFORE the
   corresponding operation is exposed. A stale owner restarting with the same logical `owner_id` gets a NEW
   incarnation and does NOT regain authority.

2. **Transition = linearizable durable saga (blockers 1/7/9).** Reserve + fence + block-new-grants + revoke
   old pin + invalidate old publication authority + record exact old `resident_instance_id` + enter DRAINING =
   **ONE atomic commit under the mutex** (no externally visible gap where the old owner can reacquire an exec
   lease). The new server starts under a scheduler-only **transition capability**, NOT an ordinary exec lease.
   Publish-new-resident + issue-first-usable-lease = **one atomic commit AFTER health**. Durable phases, kept
   distinguishable: `RESERVED_FENCED / DRAINING / TERMINATING / TREE_GONE / HEADROOM_CONFIRMED / STARTING /
   HEALTHY_UNPUBLISHED / COMMITTED / ABORTING / ABORTED`. Define fail-closed preparation-failure semantics for
   headroom-never / headroom-fell / OOM / health-fail / requester-gone / superseded (answer is NEVER "the
   exec lease already belongs to the requester"). **Commit-response idempotency:** a retry on the original
   acquisition idempotency key returns the SAME committed grant, never a second epoch/lease/resident.

3. **Target-fenced side effects (blockers 4/8, finding 14).** Every callback/eviction/stop is a fenced
   command: capture immutable identity at dispatch; before ANY state mutation, CAS on
   `transition_id + gpu_authority_epoch + resident_instance_id + exec_lease_id + state_version` **in the same
   critical section** (a check-then-release-then-write is still a race). The mock evictor/supervisor seam MUST
   reject a stop/mutation unless its immutable target matches the captured old instance -- never
   "stop whatever currently serves this config_key". Callbacks idempotent + one-shot. NO evictor/supervisor/
   telemetry/health call occurs while the lease mutex is held.

4. **Idempotent journal (blocker 5).** Journal carries the red-team's field set (`transition_id, resource_id,
   request_id/idempotency key, requester_owner_id, requester_incarnation_id, authority_epoch_from/to, phase,
   state_version, old/new_resident_instance_id, target_config_key, required_vram_mib, per-op operation_id +
   status + receipt, deadline, cancel_requested, last_error, retry_count`). Recommit checks
   `transition_id + phase + state_version + expected target instance + expected epoch` (NOT epoch alone).
   Recovery replays every external op idempotently and continues from every phase.

5. **Job-Object contract (blocker 6) -- PRIMITIVE side only.** The primitive DEFINES the contract the real
   #7 supervisor must honor (suspended-create -> assign-to-Job -> resume, or supervisor-already-inside-Job with
   breakaway disabled + verified; `KILL_ON_JOB_CLOSE`; published resident records Job-Object identity + exact
   instance) and the mock supervisor ENFORCES target-fenced stop. The real launcher chain is the later
   consumer wave -- do not build it here; just make the seam + contract correct.

6. **WDDM (finding via section 5).** The primitive must NOT grant ordinary exec authority before load + a
   real health/admission check. On final-headroom-fail: stay PREPARING, issue no lease, retry with bounded
   jitter + deadline, then abort clean -> `prepared_gpu_unavailable`. Document "3 obs ~250ms apart" as a
   heuristic for managed-tree reclamation, explicitly NOT a guarantee against outside allocation.

### Tests (the off-machine-provable subset of the red-team's matrix A-K -- adversarial MOCK)

Add a `0.4` adversarial suite covering: **A** ABA recovery (stale manifest/counter + restarted owner => new
incarnations; stale callbacks cannot publish/mutate/release/kill), **B** commit-response loss (retry on
idempotency key returns same grant), **C** stale side-effect matrix (result/manifest/lease-release/lease-renew/
stop/health-fail/idle-evict/duplicate-completion all fail vs the new instance), **D** superseded external op
(stall T1 outside mutex, supersede, complete T2, release T1's delayed actions => T2 unaffected), **E**
reentrant evictor (mock evictor synchronously calls lease status/acquire/cancel/reconcile => no deadlock, no
lock-order violation, no second transition), **F** renewal/revocation race (exactly one CAS wins; renewal
can't resurrect a revoked lease), **H(mock)** partial-alloc-fail via the mock start seam (partial tree
reclaimed; nothing published/granted; later transition succeeds), **J** lease expiry in EVERY phase, **K**
waiter sequencing (notify-before-register / spurious / duplicate / multi-waiter / cancel => waiters re-read a
durable state version, never depend on a one-shot signal). **G** active priority-preemption liveness = mock as
far as possible. LIVE-only cases (real GPU OOM, real supervisor/descendant escape, real WDDM pressure) are
DEFERRED to the consumer wave -- list them explicitly as deferred, do NOT fake them.

### Gate (fail-closed)

- v0.1/v0.2 baseline **74/74** + v0.3 adversarial **36/36** stay green = **0 regression**, off-machine
  (cloud pwsh 7.4.6) AND on-box (Windows pwsh 7.4.6 via the executor).
- New v0.4 adversarial suite green both places.
- `dev.ship` fail-closed (sha256 + AST + tests), commit ONLY #29's own files under the `git` lease, **0
  orphaned llama-server/python**, `review_queue.jsonl` before == after.
- **VERIFY the real HEAD via native `git log`/`git show --stat`, NOT the dev.ship `committed` field**
  (D-0072); if a stale 0-byte `.git/index.lock` appears, clear it via an executor task (assert no `git.exe`
  running) then re-commit.

### Rails

`docs:[]` (touch ONLY `modules/29-resource-lease/` + write your report state). Build + off-machine gate FIRST.
Single-worker wave; never hold the `gpu` lease (there is no live-GPU work here). **findings 1/13/14 STAY
OPEN** -- they close only after the later consumer wave (#7 PoolManager + #21 governor adoption + the live-GPU
3B<->9B swap / pin-revocation / prepared-eviction proof + the live-only tests). On done: `dev.ship` then
`-Action report -State done`.

## Governing docs (READ IN FULL before coding)

- The captured red-team return: `modules/31-frontier-bridge/runtime/artifacts/b823d9db-72c1-4a05-aeaf-867e39f5330c/frontier-pack-i19-r1b-redteam.answer.md` (THE spec for this wave).
- `core-docs/research/2026-07-30-work-order-gpu-lease-split.md` + `.../frontier-review-self-tasking-orchestration.md` (R1a/R1b framing).
- `modules/29-resource-lease/README.md` + `skill.json` (current 0.3.0 contract) + `tests/Invoke-ResLeaseR1bTests.ps1`.
