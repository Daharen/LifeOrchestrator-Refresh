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
| `check` | **(v0.2)** Validate a fencing token + report `{fencing_token, lease_kind, revocable, revoked_by, token_current, fence_status}` -- the surface a holder polls to learn it has been **fenced out** or its **residency_pin was revoked**. |

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
acquire are unchanged). Baseline: v0.1/v0.2 74/74 + v0.3 36/36, both green off-machine on cloud pwsh 7.4.6.
