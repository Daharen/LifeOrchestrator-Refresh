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

## Conventional resources

- **`gpu`** -- hold before starting a `llama-server` / diffusers pipeline / any model run; release after. Keeps two
  instances off the GPU at once (every model module is `parallel_safe:false`).
- **`git`** -- hold around `git add`/`commit` (dev.ship + any git write) so two commits never collide on `.git/index.lock`.
- **`doc:<path>`** -- hold before editing a shared core-doc, e.g. `doc:CURRENT_STATE.md`.

Any string is a valid resource. **Acquire-order rule** (to avoid deadlock across multiple held resources): acquire
in a fixed documented order -- `gpu` before `git` before `doc:*` -- and release in reverse.

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

## Not in scope (follow-ons)

Wiring `gpu`/`git`/`doc:*` into `model.gateway`/`dev.ship`/the doc-edit flow (done per-consumer next); the
**fan-out orchestrator** (built on top); fair FIFO/priority queuing; reader-writer locks; cross-machine locks.
It is **not** a review-queue producer.

## Tests

`tests/Invoke-ResLeaseTests.ps1` drives the REAL skill (OS-portable, ASCII-only) -- acquire/release/renew/status/list,
the overwrite/mismatch guards, **TTL expiry -> stale reclaim**, blocking acquire, **N-way concurrency (exactly one
winner)**, error paths, and the Module 1 wrapper. It runs on the cloud pre-ship gate and unchanged live via the executor.
