# RESLEASE-R1a-split (i18 fo-18-c2d73598) -- SHIPPED (DONE)

**Completed 2026-07-30 by FANOUT_AGENT_001 (worker RESLEASE-R1a-split).** The mid-ship bridge drop was
transient; the bridge reconnected and the ship finished cleanly. This doc is now a record, not a checklist.

## Result

- **res.lease #29 shipped 0.1.0 -> 0.2.0.** Commit **`e701328`** (parent `07fe698`, `master`), 6 files,
  +775/-99, NAMED FILES ONLY, trailers `Co-Authored-By: Claude Opus 4.8` + `Claude-Session`.
- **dev.ship gate all green (fail-closed):** sha 6/6 byte-exact, AST 2/2 ps1 clean, **tests 77/77 live
  ALL PASS** (74 off-machine cloud [38 v0.1 baseline preserved + 36 new] + 3 the Module-1 wrapper live),
  committed=true, **0 orphaned llama-server/python**.
- **Backward-compat proven LIVE:** dev.ship acquired + released its OWN `git` lease via the NEW v0.2
  res.lease (a plain `git` acquire -> byte-identical, `git_lease.acquired=true`, `released=true`).
- **`review_queue.jsonl` = 20 before and after** (res.lease is a non-producer). Leases dir empty. Report
  recorded to the orchestrator (`-State done`, `reports/RESLEASE-R1a-split.3484a80a.json`).

## What shipped (all ADDITIVE + DEFAULT-OFF; a plain acquire/release/renew/status/list is BYTE-IDENTICAL to v0.1)

- **Finding 1 -- monotonic fencing token.** Per-resource, minted on every fresh grant, persisted in a durable
  sibling `<resource>.fence` counter (monotonic across lease deletion on release AND across stale reclaim;
  a racing/reclaiming winner's token exceeds the prior holder's). Same-holder re-attach + renew keep the SAME
  token. `-FencingToken <n>` is a CAS guard on renew/release/check -> `fence_stale` fences out a superseded holder.
- **Finding 13 -- two lease kinds.** `-Kind exec` (default) vs `residency_pin` (revocable right to stay
  resident). A higher `-Priority` acquire REVOKES a lower-priority pin (writes `revoked_by` + the new
  `fencing_token`); the pin holder learns it lost authority on its next `renew`/`check` (reason `revoked`).
  A pin is ALWAYS revocable (`-Revocable:$false` on a pin = hard STOP `non_revocable_pin_forbidden`).
- **Findings 2/15 -- prepared / evict-before-grant.** `-RequiredVramMiB <n> [-Priority <n>]` detects an
  incompatible/lower-priority resident pin, drives its revocation, and grants ONLY AFTER a PLUGGABLE evictor
  seam confirms free headroom >= required + target (WDDM-async confirm interval). res.lease stays PURE (no
  nvidia-smi, no server kill). `-EvictorMode mock` (confirm/needs_evict/timeout) for tests; `-EvictorMode
  command -EvictorCommand <script.ps1>` is the R1b integration point.
- **Finding 14 -- lock-order-inversion rejection.** Canonical rank `gpu(0)->git(1)->doc:<path>(2)`; holding an
  earlier-ranked lease while acquiring a later/cheaper one (gpu then git) is rejected fail-closed
  (`lock_order_violation`); `-AllowLockOrder -LockOrderReason` overrides with a recorded reason. Build-then-verify
  documented (git for the commit, RELEASE git, then gpu for the live verify).
- New **`check`** action; `skill.json`/README/examples updated; contract stays 0.2 (additive fields).

## R1b (a GPU-lane follow-on -- NOT this wave)

`model.gateway` #7 PoolManager holds an `exec` lease only around GPU ops + a revocable `residency_pin` between
them + honors pin revocation + rejects per-call generation mismatch; `agent.local` #21 governor takes the pin
for its model-affine segment + the exec lease per LLM call; the REAL nvidia-smi/eviction evictor plugs into
`-EvictorMode command`; the live real-model 3B<->9B swap + pin-revocation + prepared-eviction PROOF on the GPU;
then a soak + flip the warm pool default-ON. res.lease 0.2.0 is the primitive those consumers build on.
