# res.lease -- Resource Lease / Lock

The **multi-instance coordination primitive** for Life Orchestrator (D-0050/D-0051). A filesystem lease/lock so
several processes on this one box -- multiple Claude instances, the executor, `dev.ship`, Widgets, `agent.local`
-- can arbitrate contended resources without clobbering each other. Pure PowerShell + .NET; no external
binary/model; deterministic; **`parallel_safe:true`** (it is designed to be called concurrently -- that is the point).

## Why

Concurrency on this box is otherwise unsafe: every model module is `parallel_safe:false` (the 11 GB GPU hosts one
`llama-server`/pipeline at a time), git `index.lock` collisions have bitten (D-0048/D-0049), and two instances
editing a shared core-doc would clobber each other. `res.lease` is the smallest coordination layer that fixes all
three, via one general primitive and three conventional resource names.

## Model

A **lease** is a named lock with a **TTL**. Acquiring writes a lease file atomically (`File.Open(..CreateNew..)` =
`open(O_CREAT|O_EXCL)` / `CREATE_NEW`, atomic-fail-if-exists on both Linux and Windows). The file's existence =
the lease is held; its `expires_at_utc` = when it becomes reclaimable. Because a lease **expires**, a crashed
holder never deadlocks the resource -- the next acquirer reclaims it (race-safe: reclaim renames the stale file
aside, a source-rename CAS that exactly one reclaimer wins). Releasing deletes the file. This mirrors the
project's existing coordination doctrine (D-0003: atomic filesystem ops on one volume; no network listener).

## Actions (one per invocation)

| Action | What it does |
|--------|--------------|
| `acquire` | Reserve a resource. Returns `{acquired, lease_id, expires_at_utc}`. If held live -> `acquired:false` + `held_by` (a normal outcome, not an error). Reclaims an expired lease (`reclaimed_stale:true`). `-WaitSeconds N` blocks up to N s; 0 = try once. Re-acquiring a live lease you already hold (same `holder`) re-attaches (`already_held:true`). |
| `release` | Drop a lease you hold. Needs the `lease_id` (or a matching `holder`). A wrong `lease_id` is refused (`reason:lease_mismatch`) so you can never release a lease that was already reclaimed from you. |
| `renew` | Extend `expires_at` by `ttl_seconds` (needs the `lease_id`). A lost lease -> `renewed:false, reason:lease_lost`. |
| `status` | Report `{exists, held, stale, holder, lease_id, expires_at_utc, seconds_remaining}` for one resource. |
| `list` | Report every lease in the lease dir. |
| `check` | **(v0.2)** Validate a fencing token + report `{fencing_token, lease_kind, revocable, revoked_by, token_current, fence_status}` -- the surface a holder polls to learn it has been **fenced out** or its **residency_pin was revoked**. **(v0.3/v0.4)** also reports the full-tuple `authority_ok` (folding `owner_id`/`resident_generation`/`gpu_authority_epoch` and, when engaged, `owner_incarnation_id`/`resident_instance_id`/`state_version`). |
| `commit` | **(v0.4)** Two-phase transition PHASE-2: publish the started resident + issue the first **usable** exec lease only AFTER health (`-HealthOk`), or terminate the exact tentative instance and grant nothing (`-HealthFailed`, fail-closed). Idempotent on `request_id`. |
| `fence-op` | **(v0.4)** The **target-fenced side-effect gate**: an external stop/kill/publish/release names an exact `-ResidentInstanceId` (+ optional epoch/exec-lease/state-version) and gets `{fenced_op_ok, reason}` -- a stale target is refused. "Stop whatever serves this resource" is impossible. |

## Conventional resources

- **`gpu`** -- hold before starting a `llama-server` / diffusers pipeline / any model run; release after. Keeps two
  instances off the GPU at once (every model module is `parallel_safe:false`).
- **`git`** -- hold around `git add`/`commit` (dev.ship + any git write) so two commits never collide on `.git/index.lock`.
- **`doc:<path>`** -- hold before editing a shared core-doc, e.g. `doc:CURRENT_STATE.md`.

Any string is a valid resource. **Acquire-order rule** (to avoid deadlock across multiple held resources): acquire
in a fixed documented order -- `gpu` before `git` before `doc:*` -- and release in reverse.

**Build-then-verify (v0.2, finding 14).** That deadlock-avoidance order governs the case where you genuinely need
several leases *at once*. For **GPU build work it is wasteful** to hold the expensive `gpu` lease while blocking on
the cheaper `git` lock -- the GPU sits idle. So a GPU build unit should **sequence**: take `git` for the commit,
**release `git`**, then take `gpu` *only* for the live verify. To enforce this, v0.2 **rejects the lock-order
inversion**: acquiring a later/cheaper-ranked resource (`git`, then `doc:*`) while THIS holder already holds an
earlier-ranked one (canonical rank `gpu(0) -> git(1) -> doc:<path>(2)`) fails closed with `lock_order_violation`.
Pass `-AllowLockOrder -LockOrderReason '<why>'` for the rare genuine multi-hold (override-safe, records the reason;
it is **not** a hard wall). A plain acquire that is **not** holding an earlier-ranked lease is byte-identical to v0.1.

## Lifecycle (the intended pattern)

```
acquire gpu (holder = my stable instance id, ttl = expected run length)
  -> if not acquired: back off / wait / do other work
  -> if acquired: do the model run  (renew if it runs longer than the ttl)
release gpu (with the lease_id)
```

Set a **stable holder** per instance (`$env:LIFEORCH_INSTANCE`, or pass `-Holder`) so re-attach and release-by-holder
work; keep the returned `lease_id` for release/renew. All processes must resolve the **same lease dir**
(`$env:LIFEORCH_LEASE_DIR`, else `runtime/leases/` under this skill).

## v0.2 -- the GPU-lease-split surface (additive, DEFAULT-OFF)

v0.2 is the **res.lease-primitive slice of R1** (the GPU-lease split;
`core-docs/research/2026-07-30-work-order-gpu-lease-split.md`) -- it turns mid-task GPU hand-off from a hazard into
a first-class, safe op and closes `WARM_POOL_DESIGN.md` section 10 findings 1/13/14 (with 2/15 at the primitive
layer). **Every piece is additive and default-off: an acquire/release/renew/status/list that supplies NONE of the
new inputs behaves byte-identically to v0.1** -- same result fields, same values, same lease semantics (in
particular `dev.ship`'s plain `git` acquire and plain `gpu`/`doc:*` acquires). The new fields appear only when the
new surface is engaged.

- **Monotonic fencing token (finding 1).** Every FRESH grant mints a strictly-increasing, per-resource
  `fencing_token`, persisted in a durable sibling `<resource>.fence` counter so it stays monotonic **across the
  lease file being deleted on release** and across a stale reclaim (the racing/reclaiming winner's token exceeds
  the prior holder's). Same-holder re-attach + `renew` keep the SAME token. `-FencingToken <n>` is a **CAS guard**
  on `renew`/`release`/`check`: a token that is not current is refused (`fence_stale`) -- a superseded holder is
  **fenced out**, not merely TTL-abandoned.
- **Two lease kinds (finding 13).** `-Kind exec` (default = today's short execution/transition lease) vs
  `-Kind residency_pin` (the **revocable right to STAY resident** between exec ops). A higher-`-Priority` acquire
  **REVOKES** a lower-priority pin: it writes `revoked_by` + the new holder's `fencing_token` into the pin, and the
  pinned holder learns on its next `renew`/`check` that it has **lost authority** (cooperative, fencing-backed
  revocation). A pin is **always revocable** (`-Kind residency_pin -Revocable:$false` is a hard STOP).
- **Prepared / evict-before-grant handoff (findings 2/15).** `-RequiredVramMiB <n> [-Priority <n>]` drives an
  `AcquirePreparedGpu`-style acquire: detect an incompatible/lower-priority resident pin, drive its revocation, and
  grant **only AFTER** a **pluggable evictor seam** confirms free headroom `>= RequiredVramMiB + TargetHeadroomMiB`
  (the target-headroom invariant + a WDDM-async `ConfirmIntervalMs`). **res.lease stays PURE** -- it never inspects
  VRAM or kills a server. `-EvictorMode mock` (built-in, for tests: `confirm`/`needs_evict`/`timeout`) or
  `-EvictorMode command -EvictorCommand <script.ps1>` (the seam a consumer plugs the real evictor into). The
  handshake context (`required_vram_mib`, `target_headroom_mib`, `confirm_interval_ms`, resident holder/priority)
  is passed to the seam as JSON; the seam returns `{confirmed, free_vram_mib, evicted, outcome}`.
- **Lock-order-inversion rejection (finding 14).** See **Build-then-verify** above.

## v0.3 -- the R1b three-identity + atomic-transition surface (additive, DEFAULT-OFF)

v0.3 is the **res.lease-primitive slice of R1b** (folds the i18 frontier review,
`core-docs/research/2026-07-30-frontier-review-self-tasking-orchestration.md` sections 2/3/4). Still **additive +
default-off**: a call supplying none of the v0.2/v0.3 inputs is byte-identical to v0.1, and a v0.2-engaged call is
unchanged. The primitive the real consumers build on:

- **Three-identity fencing (frontier review section 2).** The single v0.2 `fencing_token` is joined by three
  explicit identities: **`gpu_authority_epoch`** (= the per-resource fencing token; bumps ONLY when exclusive GPU
  authority changes -- side effects **assert** it, never advance it; `fencing_token` stays exposed as its alias),
  **`resident_generation`** (the PoolManager-owned per-launch generation, supplied via `-ResidentGeneration`,
  stamped + asserted -- res.lease carries + validates it, the PoolManager owns when it increments), and
  **`exec_lease_id`** (the exec acquire's `lease_id`). `check` reports `owner_current` + `generation_current` +
  `token_current` and the single **`authority_ok`** full-tuple assertion (`owner_id + gpu_authority_epoch +
  resident_generation + exec_lease_id`) a consumer polls before publishing. `-AuthorityEpoch <n>` is an alias-CAS
  on renew/release/check.
- **The single scheduler-owned ATOMIC transition (`-Transition`, frontier review section 2/3).** One indivisible
  hand-off, not `revoke -> evict -> grant`: **reserve** (serialized -- exactly one transition per resource; equal
  priority does NOT preempt) **-> mint a new `gpu_authority_epoch`** (fence the old owner off any new exec)
  **-> revoke a lower-priority pin -> drive the evictor OUTSIDE the lease mutex** (record intent + txn id in a
  `<resource>.txn` journal, run the external drain/cancel/tree-kill/headroom work, then re-enter) **-> confirm the
  managed tree is gone -> confirm headroom STABLE across `-HeadroomObservations` observations** (WDDM discipline)
  **-> grant ONLY if the reserved epoch is still current** (else `superseded_during_transition` -- fenced out).
  There is no interval where the old owner can reacquire exec, and none where the new owner holds an ordinary lease
  while eviction is merely "in progress." A crash in `PREPARING`/`DRAINING`/`STARTING` is **reconciled** from the
  txn journal (auto on the next transition, or on demand via `check -Reconcile`).
- **In-flight revocation + the adversarial evictor.** A pin revokes immediately; an ACTIVE exec gets a bounded
  `-DrainTimeoutMs` drain -> cancel -> supervisor tree-kill, and any result arriving after fencing is DISCARDED (a
  stale-epoch actor's `authority_ok` is false). The mock evictor is **adversarial**: `late_evict`,
  `partial_tree_term`, `headroom_never`, `headroom_fell`, `cancel_during_prepare` (+ v0.2 `confirm`/`needs_evict`/
  `timeout`) -- only `late_evict`/`confirm`/`needs_evict` may grant, and only after tree-gone + stable headroom.
- **res.lease stays PURE.** It never runs nvidia-smi or kills a server; the real evictor (drain/cancel/tree-kill/
  headroom-confirm, composing the #7 supervisor Job Object) plugs into `-EvictorMode command -EvictorCommand`.

**R1b consumer adoption + live proof -- NOT built here (the remaining R1b work).** `model.gateway` #7 PoolManager
holds an `exec` lease only around GPU ops and a revocable `residency_pin` between them, honors pin revocation, and
rejects per-call generation mismatches; `agent.local` #21 governor takes the pin for its model-affine segment and
the exec lease only around each LLM call, with **NO single-agent regression** (liveA/liveB byte-identical with the
split off); the **real nvidia-smi/eviction evictor** plugs into `-EvictorMode command`; and the live real-model
3B->9B swap + pin-revocation + prepared-eviction proof (plus the two new adversarial live tests: revoke while an
inference is ACTIVE, and a late old-generation result proven unable to publish/kill) runs on the box. Findings
1/13/14 close **only after that live proof**; then a soak + flipping the warm pool default-ON (the orchestrator's
call). This wave ships the res.lease primitive those consumers build on.

## v0.4 -- the R1b' primitive hardening (additive, DEFAULT-OFF; red-team-driven)

v0.4 folds the **blocking** primitive changes the i19 frontier concurrency/safety red-team (pack `b823d9db`)
found the three v0.3 identities + the ten-step transition were **not sufficient** without. Still **additive +
default-off**: a plain / v0.2 / v0.3 call is byte-identical, and the 74/74 + 36/36 gates stay green. The v0.4
fields appear only when a v0.4 input is supplied (or on `-Action commit`/`fence-op`). It does **NOT** close
findings 1/13/14 -- it makes the primitive *safe to build on* for the later consumer + live-GPU wave.

- **Incarnation identities -- ABA close (finding 1, blockers 2/3).** The v0.3 tuple is joined by
  **`owner_incarnation_id`** (a random minted per owning-process/supervisor-client **RESTART**) and
  **`resident_instance_id`** (a random per **actual server process tree**, the **target of every destructive
  op**, never reused). `resident_generation` stays a human-readable counter but is **never** the target of a
  stop/kill. A stale owner restarting with the same logical `owner_id` gets a **new incarnation** and does **not**
  regain authority; a callback captured against the old `resident_instance_id` cannot act on the replacement.
  `check` folds both into `authority_ok`. (Closes the ABA cycle where `resident_generation`/`exec_lease_id`/
  `owner_id` reuse let a stale server or callback become valid again after a crash.)
- **The two-phase transition -- no exec authority before health (blocker 1).** `-Transition -TwoPhaseCommit`
  reserves -> fences -> evicts -> confirms tree-gone + stable headroom, then issues a **NON-USABLE transition
  capability** (`usable:false`, `lease_kind:transition_capability`): the new server starts under **scheduler
  authority**, not an ordinary exec lease. The first **usable** exec lease is published only by the phase-2
  `-Action commit -HealthOk` **after health** (`STARTING -> HEALTHY_UNPUBLISHED -> COMMITTED`, one atomic
  publish+grant). Default single-shot `-Transition` (the collapsed form -- caller is both scheduler and resident,
  no separate health gate) stays byte-compatible with v0.3. Fail-closed prep semantics are defined for
  headroom-never/fell, partial-tree, OOM/`-HealthFailed`, requester-gone (capability expiry), and
  `superseded_during_transition` -- the answer is **never** "the exec lease already belongs to the requester";
  on `-HealthFailed` the tentative instance is dropped and the GPU is left **empty** (a new scheduled acquisition
  is required; the old resident is not silently restored).
- **Target-fenced side effects (blockers 4/8, finding 14).** `-Action fence-op -OpKind <k> -ResidentInstanceId
  <id>` is the authority an external side effect (stop/kill/result-publish/manifest-write/lease-release/renew/
  health-fail/idle-evict/complete) **must consult before it acts**. It answers `fenced_op_ok` in one read against
  the CURRENT live resident: a stale target (wrong instance/epoch/exec-lease/state-version, or a superseded/
  revoked/expired resident) is **refused**. The op **must name an exact instance** -- "stop whatever currently
  serves this resource" returns `target_instance_required`. (A state-level recommit alone cannot un-kill a
  process, so the kill is gated *here*.)
- **Idempotent journal + commit-response idempotency (blocker 5).** The `<resource>.txn` journal carries the
  red-team field set (`request_id`, `requester_owner_id/incarnation_id`, `authority_epoch_from/to`, `phase`,
  `state_version`, `old/new_resident_instance_id`, `target_config_key`, per-op `operations[]` + receipts,
  `deadline`, `cancel_requested`, `last_error`, `retry_count`, `grant_lease_id`). A transition/commit **retry on
  the same `request_id` returns the SAME grant** -- never a second epoch/lease/resident (recovers a lost commit
  response). Recovery/reconcile continues from every durable phase.
- **A renewal can never resurrect a revoked lease (test F).** The fenced renew and the pin revoke serialize on a
  per-resource **oplock** (an atomic claim); the renew re-reads under the lock and **fails closed** if it can't
  hold it, so exactly one CAS wins and a renew cannot clobber a concurrent revoke.
- **Waiter sequencing (finding 14 / test K).** A durable per-resource **`state_version`** bumps on every
  authority/residency change (grant/renew/revoke/release/commit); waiters re-read it rather than depending on a
  one-shot signal, and a stale captured `state_version` is fenced out.
- **Job-Object contract (blocker 6) -- PRIMITIVE side only.** The primitive **defines** the contract the real #7
  supervisor must honor (suspended-create -> assign-to-Job -> resume, or a supervisor already inside the Job with
  breakaway disabled + verified; `KILL_ON_JOB_CLOSE`; the published resident records the Job-Object identity +
  exact `resident_instance_id`) and the mock supervisor seam **enforces target-fenced stop**. The real launcher
  chain is the later consumer wave -- not built here.

**v0.4.1 (i21, the R1b consumer wave):** one truthful-telemetry fix surfaced by wiring the REAL evictor
(`modules/07-model-gateway/lib/PoolEvictor.ps1`): the command-mode evictor's `tree_gone` is now passed through
to the transition result + txn journal instead of silently defaulting to `true` (a partial-tree ABORT must
never be journaled as `tree_gone:true`). Additive: a v0.2-shape command evictor without the field behaves
exactly as before, and the grant decision was already fail-closed on `confirmed`. Behavior otherwise unchanged
(74/74 + 36/36 + 45/45 re-verified; T0 version pins track 0.4.1).

**Still-open + DEFERRED (NOT faked here).** Findings **1/13/14 stay OPEN** -- they close only after the later
consumer wave (#7 PoolManager + #21 governor adoption + the real nvidia-smi/eviction evictor + the live-GPU
3B<->9B swap / pin-revocation / prepared-eviction proof). The **live-only** red-team cases -- real GPU OOM on a
real partial load, a real supervisor/descendant escape + PID reuse, real WDDM external-consumer pressure after
headroom sampling -- are **deferred to that wave and listed explicitly** in the v0.4 adversarial suite, not
mocked. "Three observations ~250ms apart" is a **heuristic** for managed-tree reclamation, explicitly **not** a
guarantee against outside VRAM allocation.

## Not in scope (follow-ons)

Wiring the v0.2 split into `model.gateway`/`agent.local` + the real evictor + the live-GPU proof = **R1b** (above);
the **fan-out orchestrator** (built on top); fair FIFO/priority queuing; reader-writer / re-entrant locks;
cross-machine leases; an auto-renew daemon. It is **not** a review-queue producer.

## Tests

`tests/Invoke-ResLeaseTests.ps1` drives the REAL skill (OS-portable, ASCII-only). v0.1 core (S0-S11):
acquire/release/renew/status/list, the overwrite/mismatch guards, **TTL expiry -> stale reclaim**, blocking acquire,
**N-way concurrency (exactly one winner)**, error paths, the Module 1 wrapper. v0.2 surface (S12-S20): a
**byte-identical** default path (plain `git`/`gpu`/`doc:*` acquire carries EXACTLY the v0.1 keys), fencing-token
**monotonicity** (re-attach/renew keep it; strictly-greater after release + stale reclaim), **cross-process fencing**
(one winner, its token exceeds the prior holder's), the **CAS `fence_stale`** guard on check/renew/release, the two
**lease kinds**, **pin revocation** (`revoked_by` + the holder learning it lost authority) + the non-revocable-pin
STOP, the **prepared handshake** (mock confirm/needs_evict/timeout + the command-mode evictor seam), and the
**`lock_order_violation`** rejection + `-AllowLockOrder` override. It runs on the cloud pre-ship gate (the evictor is
mocked; res.lease is pure pwsh + .NET, identical on Linux + Windows) and unchanged live via the executor.

`tests/Invoke-ResLeaseR1bTests.ps1` is the **v0.3 (R1b) adversarial gate** (36 assertions): three-identity fencing
(`gpu_authority_epoch`/`resident_generation`/`exec_lease_id` + the `authority_ok` full-tuple), the scheduler-owned
`-Transition` (free-slot grant, lower-priority-pin preemption, `held_incompatible` on exec/equal-priority), every
adversarial evictor scenario (only `late_evict` grants, after waiting for stable headroom), **commit-if-epoch-current**
(a command evictor that bumps the fence mid-eviction -> `superseded_during_transition`, no grant), single-winner
serialization, crash **reconcile** of a stale `PREPARING`/`DRAINING` txn, **result-after-revocation** + **expiry-during-exec**
(a stale-epoch actor's `authority_ok` is false), and the **additive/default-off guards** (a plain acquire and a v0.2-engaged
acquire are unchanged).

`tests/Invoke-ResLeaseR1bPrimeTests.ps1` is the **v0.4 (R1b') adversarial gate** (45 assertions) -- the
off-machine-provable subset of the red-team's matrix: **A** ABA recovery (restarted owner + stale callbacks
fenced out of publish/mutate/release/kill), **B** commit-response loss (single-shot + two-phase idempotent
replay), **C** stale side-effect matrix (all 8 late ops from an old instance refused vs the new one), **D**
superseded external op (a T1's delayed actions cannot touch the winner T2), **E** reentrant evictor (a command
evictor that calls back into res.lease -> no deadlock, no lock-order inversion, no second transition), **F**
renewal/revocation race (concurrent renewers vs a revoker -> the revoke is never lost, a renew never resurrects),
**G** active preemption liveness, **H** partial-alloc-fail (partial-tree + phase-2 `-HealthFailed` publish/grant
nothing, then a later clean transition succeeds), **J** lease expiry in every durable phase (capability expiry +
crashed-txn reconcile per phase), **K** waiter sequencing (a durable monotonic `state_version`, stale-version
fenced). The **live-only** cases (real GPU OOM, real supervisor/descendant escape + PID reuse, real WDDM
pressure) are listed as **DEFERRED to the consumer wave**, not mocked.

Baseline: **v0.1/v0.2 74/74 + v0.3 36/36 + v0.4 45/45 (155 assertions, 0 regression)**, all green off-machine on
cloud pwsh 7.4.6 and unchanged live via the executor.
