# R1b consumer-adoption spec -- #7 PoolManager + #21 governor + the real evictor + the live-GPU proof

**Provenance:** Iteration 19 FANOUT_AGENT_001 (`RESLEASE-R1b-consumers`), 2026-07-30. Companion to the shipped
**res.lease #29 v0.3.0** primitive (that wave). Delivered to Nicholas as a courier file at i19 close; recovered
into the repo at i21 scoping. The body below is the i19 text verbatim (reflowed); only this provenance note and
the **i21 orchestrator addendum** at the bottom were added. The body's lease-surface calls are **v0.3.0-era and
partially superseded by v0.4.0 (R1b', i20, `f6df675`)** -- read the addendum; on any conflict
`modules/29-resource-lease/README.md` + `skill.json` (0.4.0) win.

---

This doc is the precise, code-level design for the parts of R1b that require **live-GPU iteration** and
therefore were NOT blind-edited this wave (the work order's fallback: "ship the solid subset behind the
additive/default-off surface... report PLAINLY what remains" -- keeping the single-agent path byte-identical is
non-negotiable, and #7/#21 are model-bound so they cannot be regression-proven off-machine). Findings 1/13/14
close **only** after the live proof below passes.

The res.lease primitive this builds on is DONE + off-machine-gated (74/74 v0.1/v0.2 + 36/36 v0.3 adversarial,
green on cloud pwsh 7.4.6; additive + default-off; classic path byte-identical). The surfaces the consumers call:

- Three identities: `gpu_authority_epoch` (= the per-resource fencing token; the consumer treats it as opaque and
  ASSERTS it), `resident_generation` (the PoolManager's `instance_generation` -- pass it in via
  `-ResidentGeneration`), `exec_lease_id` (the exec acquire's `lease_id`).
- `check -Resource gpu -OwnerId <o> -ResidentGeneration <g> -AuthorityEpoch <e>` -> `authority_ok` (the single
  full-tuple gate a consumer calls right before publishing an inference result or a manifest update).
- `acquire -Resource gpu -Transition -RequiredVramMiB <peak> -Priority <p> -EvictorMode command -EvictorCommand
  <PoolEvictor.ps1> -OwnerId <o> -ResidentGeneration <g>` -> the single scheduler-owned atomic hand-off.
- `acquire -Resource gpu -Kind residency_pin -Priority <p>` / `-Kind exec` -> the pin/exec split.
- `check -Resource gpu -Reconcile` -> crash-reconcile a stale transition (for the watchdog).

---

## 1. The real evictor: `modules/07-model-gateway/lib/PoolEvictor.ps1` (the `-EvictorCommand` seam)

res.lease stays PURE (no nvidia-smi, no server kill). The transition drives this script OUTSIDE the res.lease
mutex and grants only if the reserved epoch is still current. Contract:

**Invoked as:** `& PoolEvictor.ps1 -ContextJson <json>` where the JSON carries `{resource, lease_dir, txn_id,
owner_id, authority_epoch, required_vram_mib, target_headroom_mib, resident_holder, resident_generation,
drain_timeout_ms, state}`.

**Must emit (stdout, one JSON object):** `{confirmed:<bool>, free_vram_mib:<int>, evicted:<bool>,
tree_gone:<bool>, outcome:<string>, detail:<string>}`. `confirmed` may be true ONLY when `tree_gone` is true
AND headroom is stable.

**Must do, in order (fail-closed -- any step failing => `confirmed:false`):**
1. If `state=occupied`: request a **graceful** stop of the resident via the durable supervisor
   (`Start-GatewaySupervisor.ps1` / `Supervisor.psm1` Job Object) -- NOT a PID kill from here.
2. Bounded **drain** (`drain_timeout_ms`) of any ACTIVE inference; then **cancel**; then the supervisor
   **Job-Object tree-kill**. (Only the durable supervisor starts/terminates servers -- D-0055/56 re-wedge class.)
3. **Confirm the managed tree is gone** (`Test-ResidentIdentity` says the pid is dead + the socket owner is gone).
   If a child survived, return `tree_gone:false` (=> `partial_tree_term`; the transition will NOT grant).
4. **Confirm headroom STABLE**: poll `nvidia-smi --query-gpu=memory.free` **3 times ~250 ms apart** (the res.lease
   transition also enforces this via `-HeadroomObservations`); every reading must be `>= required + target`.
   `required_vram_mib` is the **measured PEAK** for the config_key (weights + KV + compute buffers + overhead +
   margin, initially `max(512 MiB, 10%)`, later per-config high-water marks) -- NOT the GGUF file size.
   Re-check once more immediately before returning `confirmed:true`. NEVER kill an unidentified VRAM consumer.
5. Off-Windows / nvidia-smi absent: the VRAM probe is a SEAM that returns `unknown` -> `confirmed:false` (a normal
   failed prepare), never a throw. (This is why the mock, not this script, runs in the off-machine gate.)

Reuse `PoolManager.psm1`'s pure helpers: `Get-GpuHandoffPlan` (grant / evict_then_grant / insufficient),
`Test-ResidentIdentity`, `Test-SocketOwner`, `Enter-PoolLock`. Wire the nvidia-smi + `Get-NetTCPConnection`
seams the gateway already defines.

## 2. `model.gateway` #7 PoolManager adoption (`Ensure-ResidentModel` / the warm path)

Switch from "hold one whole-task `gpu` lease" to the split. All ADDITIVE behind `-UsePoolLeaseSplit`
(default-OFF; OFF == today's D-0057 warm path byte-for-byte). When ON:

- **Load / evict / generate**: hold an **`exec`** lease only across the GPU op. Acquire it via the transition
  (`-Transition -RequiredVramMiB <peak> -EvictorCommand PoolEvictor.ps1 -ResidentGeneration <instance_generation>`)
  when a swap/eviction is needed; a same-model reuse takes a plain short `exec` lease (must stay ~1 ms).
- **Between calls**: hold a revocable **`residency_pin`** (priority = the task's tier) so a higher-priority demand
  can preempt. Honor revocation: on each entry, `check` the pin; `authority_ok:false`/`fence_status:revoked` =>
  stop serving, let the transition evict cleanly.
- **Every inference + publication** carries + asserts `owner_id + gpu_authority_epoch + resident_generation +
  exec_lease_id`. Bind `resident_generation` to the manifest's `instance_generation`; bump it on
  start/replace/invalidate (already `New-InstanceGeneration`). Reject a generation/epoch mismatch BEFORE any
  completion (extend `Test-GenerationMatch` to also take the res.lease epoch). A late old-generation result is
  DISCARDED (its epoch is stale -> `authority_ok:false`).
- Keep `-BypassPoolManager` + the classic D-0057 warm path working unchanged.

## 3. `agent.local` #21 governor adoption (`Invoke-AutoRamp.ps1`)

Today (lines ~469-495) it acquires ONE whole-task `gpu` lease (`acquire`/`renew`/`release`). Add `-SplitLease`
(default-OFF; OFF == byte-for-byte today, incl. `$env:LIFEORCH_INSTANCE` re-attach). When ON:

- Take a **`residency_pin`** (priority = profile tier) for the model-affine segment instead of the whole-task lease.
- Take the **`exec`** lease only around each LLM call (through the gateway, which already re-attaches to this
  holder via `$env:LIFEORCH_INSTANCE`); release it between calls; a build-then-verify unit may drop the pin
  between phases.
- Pass `-ResidentGeneration`/`-OwnerId` through so the gateway can assert the full tuple.

**Non-negotiable:** with `-SplitLease` OFF the governor is byte-for-byte identical; with it ON, `liveA`/`liveB`
must produce IDENTICAL epochs/completions/swap counts on the single-agent path (the D-0060/D-0064 live gate).

## 4. The live-GPU proof (closes findings 1/13/14) -- run on the 2080 Ti via the executor

1. A real **M0->S0 3B->9B swap** holding a pin + short exec leases (target: swap ~4.1 s, reuse ~1 ms).
2. A **second owner revokes the pin + safely evicts** (>= target headroom via nvidia-smi, 0 orphans).
3. **NEW adversarial live test A:** revoke while the old owner has an **ACTIVE inference** -- bounded
   drain -> cancel -> Job-Object tree-kill, and the in-flight result is **discarded** (its epoch is fenced).
4. **NEW adversarial live test B:** a deliberately **late old-generation result** PROVEN unable to publish / alter
   the resident manifest / kill the new server (`authority_ok:false` blocks it).
5. Resident-sequence trace `9B gen N -> 3B/gen M -> 9B gen N+1` with NO managed-resident overlap; swap +
   headroom-confirm p50/p95; single-agent liveA/liveB unchanged; 0 orphaned `llama-server`/python;
   `review_queue.jsonl` before == after.
6. A Verification Console `run_module` item: a live prepared exec acquire showing the atomic hand-off + a pin
   revoked-and-evicted + a fenced stale result refused.

**Only after 1-6 pass** do WARM_POOL_DESIGN section 10 findings 1/13/14 flip to CLOSED; then the remaining
default-ON gate is the soak (>=200 transitions, >=25 forced revocations, >=25 injected crash/expiry/cancel,
long idle/resume, zero stale publications, zero grants-before-confirmed-headroom, zero orphaned servers, zero
unreconciled transitions; record p50/p95). Sequencing (frontier review section 5): R1a -> **R1b (this + the
primitive)** -> minimal opt-in A->B->A baton proof -> soak -> R2 default-ON -> expanded #26.

---

## i21 orchestrator addendum -- v0.4.0 (R1b', i20, `f6df675`) deltas that SUPERSEDE the body above

Added at i21 scoping (orchestrator, not part of the i19 delivery). The i20 R1b' hardening changed the primitive
surface the consumers call. Where the body and this addendum differ, the addendum -- and ultimately the 0.4.0
`README.md`/`skill.json` + `tests/Invoke-ResLeaseR1bPrimeTests.ps1` -- wins.

1. **Two-phase transition (no grant-before-ready).** A swap should use `-Transition -TwoPhaseCommit`: it yields
   a NON-usable `transition_capability` (`usable:false`) -- the new server starts under **scheduler authority**,
   NOT an ordinary exec lease. `-Action commit -HealthOk` AFTER health publishes + issues the FIRST usable exec
   lease (`STARTING -> HEALTHY_UNPUBLISHED -> COMMITTED`, one atomic publish+grant); `-Action commit
   -HealthFailed` terminates the exact tentative instance and grants NOTHING (GPU left EMPTY, fail-closed). The
   body's single-shot `-Transition` + commit-if-epoch-current remains only as the collapsed form.
2. **The identity tuple grew.** Add `owner_incarnation_id` (minted per owning-process/supervisor-client RESTART)
   and `resident_instance_id` (minted per actual server process TREE -- **the target of every destructive op**,
   never reused). `resident_generation` stays a human-readable counter and is NEVER a destructive-op target;
   `exec_lease_id` is a never-reused UUID. Consumers carry + assert the FULL tuple `owner_id +
   owner_incarnation_id + gpu_authority_epoch + resident_generation + resident_instance_id + exec_lease_id`;
   `-Action check` folds it all into `authority_ok`.
3. **Target-fenced side effects.** Before ANY stop / kill / result-publish / manifest-write / lease-release /
   renew / health-fail / idle-evict / complete, the evictor/supervisor consults `-Action fence-op -OpKind <k>
   -ResidentInstanceId <exact id>` (+ optional epoch / exec-lease / state-version) and obeys
   `{fenced_op_ok, reason}`. A stale target is REFUSED; omitting the target returns `target_instance_required`
   ("stop whatever serves this resource" is impossible). Live test B must evidence BOTH `check
   authority_ok:false` AND a `fence-op` refusal naming the stale `resident_instance_id`.
4. **Idempotency + waiters.** A transition/commit retry on the same `request_id` returns the SAME grant (never a
   second epoch/lease/resident). A durable per-resource `state_version` bumps on every authority/residency
   change; waiters re-read it (never a one-shot signal); a stale captured `state_version` is fenced out.
5. **Evictor context.** Thread `resident_instance_id` through the evictor context for destructive targeting
   (`resident_generation` is reporting-only). The renew path is oplock-serialized and can NEVER resurrect a
   revoked lease -- do not build consumer retry loops that assume it can.
6. **Authoritative sources on any conflict:** `modules/29-resource-lease/README.md` + `skill.json` (0.4.0);
   `tests/Invoke-ResLeaseR1bTests.ps1` (36) + `tests/Invoke-ResLeaseR1bPrimeTests.ps1` (45) as behavioral truth;
   the i20 ship state (Project `claude/fanout/RESLEASE-R1bprime-i20-SHIP-STATE.md`; `DECISION_LOG.md` D-0075).
