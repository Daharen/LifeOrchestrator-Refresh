# Frontier direction review (folded) -- self-tasking sequential-orchestration trajectory + the GPU-lease-split keystone (R1)

**Provenance:** off-box GPT-5.x review couriered by Nicholas via frontier.bridge #31 (pack 42ad8308), folded at fan-out iteration 18 close-out (D-0072, 2026-07-30). Reviews research/2026-07-30-self-tasking-orchestration-trajectory-review.md + research/2026-07-30-work-order-gpu-lease-split.md. The verbatim answer follows; the actionable R1b/R4 guidance is folded into those two work orders + D-0072.

---

<<<FRONTIER-BRIDGE-ANSWER-BEGIN pack=42ad8308>>>
## Verdict

**Yes—pull the sequential single-GPU baton-pass forward, but only as a narrow architecture proof, not yet as a general self-directing workflow engine.**

The trajectory review is substantially correct. The GPU-lease split is the right infrastructure keystone, and **R1a primitive-first / R1b consumer-second is a sound seam**—provided R1a is treated as a provisional protocol implementation rather than evidence that the handoff problem has been solved.

The work order is not unsafe in concept, but it is **underspecified at exactly the dangerous boundary: revoking an owner while work is in flight and transferring authority across asynchronous process termination and VRAM reclamation.** That needs tightening before R1a freezes the contract.

My direction call is:

> **R1a → R1b → minimal opt-in A→B→A baton proof → operational soak → warm-pool default-ON.**

Strong preflight can be developed independently and inserted into the proof, but it should not be coupled to the lease rollout.

---

## 1. Trajectory assessment

The central conclusions are right:

* One large resident model is the correct physical invariant on this machine.
* Same-model residency is vastly more valuable than speculative RAM staging.
* Cross-model continuation requires prompt reconstruction rather than magical state restoration.
* The missing component is a deterministic sequential orchestration layer, not another model-loading primitive.

Those conclusions follow cleanly from the measured 2,902 MiB remaining with the 9B resident, approximately 1.6–4.1-second swaps, approximately 1 ms same-model reuse, and incompatible cross-model KV state. 

I would make four corrections or additions.

### “Self-tasking” must not mean the LLM owns the control loop

The model can propose stages, revise plans, and evaluate results. It should **not** be the sole holder of workflow progress, lease authority, or recovery state.

A small CPU-resident deterministic coordinator must remain alive while every model comes and goes. It owns:

* The authoritative stage journal.
* The current stage and attempt number.
* Idempotency keys.
* Lease and fencing credentials.
* Artifact references and hashes.
* Retry and cancellation decisions.
* The compact context that will be supplied to the returning orchestrator model.

The LLM relinquishes **GPU residency**, not system control. This distinction should be explicit in the architecture and terminology.

### “Distinct agents” need not mean distinct processes

Multiple executor agents using the same model can be separate logical contexts, instruction packs, or slots while sharing one resident server. A process unload/reload is needed only when the model or GPU-consuming runtime actually changes.

That avoids turning conceptual agent boundaries into unnecessary four-second swaps.

### The swap-overhead estimate excludes the larger scaling risk

The review is mathematically correct that 20–30 full LLM swaps contribute roughly 1–2 minutes. 

However, repeated full-transcript re-ingestion can become more expensive than swapping. If every returning orchestrator receives an ever-growing transcript, cumulative prompt evaluation approaches quadratic growth across the workflow.

The planner therefore needs **checkpoint compaction from the first baton proof**, not as a later optimization. Persist a bounded structured state rather than replaying every prior conversation and tool log.

### The RAM-warmth result should remain scoped

The negative result appears valid for the measured GGUF LLM swaps. It should not be generalized to generator runtimes. The same review reports materially different cold and warm generator initialization times, so generator reuse and batching remain important even though RAM warmth did not materially improve the 3B↔9B LLM transition.

---

## 2. Lease split correctness

The conceptual split is correct:

* **Execution/transition lease:** exclusive right to perform a GPU operation or mutate residency.
* **Residency pin:** revocable preference allowing a compatible server to remain resident while idle.
* **Fencing:** prevents stale owners from acting after authority changes.
* **Prepared acquisition:** provides usable GPU capacity, not merely an unlocked lease record.

That directly addresses the current condition in which releasing the lock would still leave insufficient VRAM for the successor. 

But the safe unit is not merely `revoke pin → evict → grant`. It must be one scheduler-owned transition:

1. Reserve the handoff for the requester.
2. Fence the old owner against acquiring any new execution lease.
3. Drain or cancel its active execution.
4. Invalidate its publication authority.
5. Shut down the managed resident.
6. Confirm the complete process tree is gone.
7. Confirm usable headroom remains stable.
8. Grant execution authority to the requester.
9. Start and health-check the new resident.
10. Publish the new resident generation.

There must be no interval in which the old owner can reacquire execution, and no interval in which the new owner receives an ordinary lease while eviction is merely “in progress.”

### Separate three identities

The work order currently risks overloading a single fencing token. I recommend three distinct values:

* `gpu_authority_epoch`: monotonically increments whenever exclusive GPU authority changes.
* `resident_generation`: increments whenever a server is started, replaced, or invalidated.
* `exec_lease_id`: unique identifier for one execution acquisition.

Every inference and externally visible publication should carry:

`owner_id + gpu_authority_epoch + resident_generation + exec_lease_id`

The gateway checks these before dispatch. It checks the authority epoch and resident generation again before accepting or publishing the result.

I would **not** increment one global fencing token on every kill, start, publish, and evict operation. That makes a legitimate owner continually invalidate its own prior credentials and creates difficult propagation rules. Issue a new authority epoch when authority changes; side effects assert that epoch rather than advancing it.

### Define in-flight revocation explicitly

A residency pin can be revoked immediately. An active GPU execution generally cannot be treated as though it vanished immediately.

The protocol needs this rule:

> Revocation blocks all new execution grants to the old owner. An existing execution receives a bounded drain period, followed by cancellation and supervisor-owned process-tree termination if it does not complete.

Any result arriving after fencing must be discarded even when the underlying model call technically succeeded.

Without this, a stale call can finish after the new model is loaded and either publish an obsolete result or have a delayed callback kill or overwrite the new resident.

### Do not call the evictor under the lease-state mutex

`AcquirePreparedGpu` should record a transition intent and transaction ID under the mutex, then release the mutex before waiting on processes, querying telemetry, or invoking the gateway.

After the external work completes, it reacquires the mutex and commits only if the transaction’s fencing epoch is still current.

Calling the evictor, process supervisor, or telemetry commands while holding the state mutex is a lock-order and re-entry hazard even if the public lease order is otherwise correct.

---

## 3. WDDM and the 2080 Ti

On Windows, the prepared-GPU guarantee can only cover **cooperating managed workloads**. It cannot prevent another desktop application, browser, game, or compositor from allocating VRAM after the check.

WDDM manages residency through changing per-process budgets and GPU virtual-memory residency rather than treating reported free VRAM as a permanently reserved physical block. ([Microsoft Learn][1])

Therefore:

* Confirm the managed process tree has exited.
* Poll headroom until it is stable across multiple observations.
* Recheck immediately before model loading.
* Handle an allocation failure as a normal failed prepare, not an impossible state.
* Never kill an unidentified process merely because it consumes VRAM.

A reasonable initial confirmation rule is:

> Three passing observations approximately 250 ms apart, after process-tree exit, followed by another check immediately before load.

`required_vram` must also mean **measured peak requirement**, not GGUF file size or steady-state weight usage. It should include weights, context/KV allocation, compute buffers, runtime overhead, and a configurable safety margin. I would initially use the larger of approximately **512 MiB or 10%**, then replace that estimate with per-`config_key` measured high-water marks.

### Executor re-wedge protection

To avoid the D-0055/56 class:

* Only the durable supervisor may start or terminate model servers.
* The requester must never directly kill a PID.
* The entire process tree must enter the supervisor Job Object before it can become the published resident.
* Startup should follow `spawn → job assignment → resume/start → health check → fenced publication`.
* Shutdown should follow `graceful request → bounded wait → Job Object termination → tree-exit confirmation → VRAM confirmation`.
* A crash in `PREPARING`, `DRAINING`, or `STARTING` must be reconciled from the transaction journal.

If suspended creation is difficult from the current PowerShell layer, use a small launcher owned by the Job Object rather than accepting a spawn-before-assignment orphan window.

---

## 4. R1a / R1b split

**The split is good, with one important governance change: R1a must not close findings 1/13/14 or declare that only soak remains.**

The current work order’s state-update language says those findings become closed and the remaining default-ON gate becomes soak.  That is valid only after R1b.

Use this status division:

### R1a: protocol implemented, hardware behavior unproven

R1a may establish:

* Lease kinds and schema.
* Authority epochs and resident generations.
* The transition state machine.
* Lock-order enforcement.
* Mock evictor contract.
* Crash recovery and stale-operation rejection.
* Compatibility with the disabled legacy path.

Its mock must be adversarial. It should simulate:

* Eviction completing late.
* A stale idle callback arriving after a new grant.
* Partial process-tree termination.
* Headroom never reaching the target.
* Headroom reaching the target and then falling.
* Cancellation during preparation.
* Lease expiry during execution.
* A result arriving after revocation.
* A crash after start but before resident publication.
* Equal-priority simultaneous acquisition.

R1a should ship as additive, default-off, and explicitly **provisional for consumer validation**.

### R1b: findings closed

R1b must integrate `PoolManager` and the governor and perform the live GPU proof already contemplated by the work order. 

Add two tests that are currently not explicit enough:

1. Revoke while the old owner has an active inference, not merely an idle pin.
2. Deliver a deliberately late old-generation result and prove it cannot publish, alter the resident manifest, or terminate the new server.

Only after those pass should findings 1/13/14 be marked closed.

---

## 5. Sequencing and the soak

I disagree with the strict sequence:

> R1 → default-ON → strong preflight → orchestrator.

**Default-ON is not logically required for an opt-in orchestrator proof.** It is an operational deployment choice.

Use:

1. **R1a:** primitive and hostile mocks.
2. **R1b:** real consumer adoption and live GPU handoff.
3. **Minimal baton proof:** explicit opt-in, fixed plan.
4. **Soak:** exercise the split and baton paths.
5. **R2:** warm-pool default-ON after soak.
6. **Expanded #26:** dynamic planning, retries, and larger workflows.

Strong preflight can be implemented and evaluated alongside steps 2–4 because it does not alter the GPU ownership protocol. Do not combine it into the same release wave, because a routing-quality regression and a lease-liveness regression would then be difficult to distinguish.

### The soak remains the real default-ON gate

Closing findings 1/13/14 is necessary but not sufficient. The soak should prove that the new protocol survives repetition and idle time.

A suitable minimum for this machine would be:

* At least 200 acquire/reuse/swap transitions.
* At least 25 forced pin revocations.
* At least 25 injected crash, expiry, or cancellation cases.
* Multiple long idle/resume intervals.
* Zero stale publications.
* Zero grants before confirmed headroom.
* Zero orphaned managed server processes.
* Zero unreconciled transition records.
* Recorded p50/p95 handoff and headroom-confirmation latency.
* No increase in failed ordinary single-agent runs.

The pool should remain opt-in until that evidence exists.

---

## 6. Minimal baton-pass proof

Do **not** use `strong preflight → gen.image → fs.manage` exactly as proposed. That proves the first model can leave, but it does not prove that the orchestrator model can return and resume.

The minimum meaningful chain is **A→B→A**:

### Stage A1 — 9B planner/preflight

While the 9B is resident:

* Produce a fixed-schema stage plan.
* Select the image-generation tool and parameters.
* Write a compact checkpoint.
* Commit the plan and stage idempotency keys.
* Release execution and the residency pin.

The initial proof should use a constrained or partially fixed plan schema rather than arbitrary autonomous decomposition.

### Stage B — image generation

* Acquire a prepared GPU for the generator.
* Prove the old 9B generation is fenced.
* Load the generator.
* Produce exactly one artifact under an idempotency key.
* Write an authoritative result manifest containing path, hash, parameters, status, and attempt.
* Release the generator’s pin.

### Stage A2 — 9B resume and verification

* Reacquire a prepared GPU.
* Reload the same 9B configuration.
* Restore compatible same-model state or ingest the compact checkpoint.
* Validate the stage-B manifest.
* Invoke deterministic `fs.manage` placement.
* Mark the workflow complete.

Then deliberately terminate the coordinator after stage B and prove it resumes A2 from disk without regenerating or duplicating the image.

Acceptance should require:

* Observed resident sequence `9B generation N → generator generation M → 9B generation N+1`.
* No overlap between managed heavyweight residents.
* A stale A1 request rejected after B receives authority.
* Stable headroom before both model loads.
* Exactly-once artifact placement.
* Successful crash recovery between stages.
* No human courier step.

This proves the architectural hinge without committing to a general-purpose autonomous planner.

---

## 7. Context cold-store reality

The review is correct: a KV snapshot belongs to a particular model/runtime context. It is not a portable reasoning state that can be restored into a different model.

Official `llama-server` documentation exposes slot save and restore for persistent prompt caches, including saved-token counts, bytes written, and timing. ([GitHub][2]) That makes it useful for an exact same-model return when the build, model, quantization, context configuration, template, and related runtime parameters remain compatible.

It is not the correct cross-model baton format.

The cheapest robust cross-model option is:

* Immutable original goal.
* Current normalized plan.
* Completed-stage summaries.
* Artifact references and hashes.
* Open questions.
* Decisions and their supporting evidence.
* Current constraints.
* Next-stage instruction.
* A bounded selection of raw tool output only where verification requires it.

Do not persist or attempt to recreate hidden reasoning. Persist the decision-relevant state.

Also benchmark slot save/restore before assuming it is worthwhile. Long KV snapshots can be large, and for a several-thousand-token checkpoint, prompt re-ingestion may be cheaper and simpler than serializing and restoring hundreds of megabytes of cache. Recent upstream work also describes host-memory prompt caching, but that is still same-model cache reuse, not cross-model transfer, and should not be placed on the critical path without confirming behavior on the pinned builds. ([GitHub][3])

---

## Final direction call

**Proceed with R1a now.** It is independently useful infrastructure and aligns with the existing fencing backlog.

**Proceed immediately to R1b afterward.** Do not let R1a become a long-lived abstraction with no real consumer validation.

**Then pull forward a narrow #26 A→B→A proof under an explicit opt-in flag.** That is wise on this hardware because it tests the central intended operating model using already-built capabilities.

Do **not** yet pull forward:

* Open-ended self-generated workflows.
* Recursive replanning.
* Multiple simultaneous workflow owners.
* Shared or stacked residency pins.
* Fair scheduling beyond deterministic priority and tie-breaking.
* Default-ON deployment before soak.

The lease split is the right keystone, but the actual safety invariant is broader:

> At every moment there is one deterministic authority for GPU transition, one current residency generation, no stale path capable of publishing or killing, and an authoritative CPU-resident workflow journal that survives every model unload.

With that invariant made explicit, the direction is technically sound and appropriately matched to an 11 GB Turing machine.

[1]: https://learn.microsoft.com/en-us/windows-hardware/drivers/display/gpu-virtual-memory-in-wddm-2-0?utm_source=chatgpt.com "GPU Virtual Memory in WDDM 2.0 - Windows drivers"
[2]: https://github.com/ggml-org/llama.cpp/discussions/13606?utm_source=chatgpt.com "Tutorial: KV cache reuse with llama-server · ggml-org llama.cpp · Discussion #13606 · GitHub"
[3]: https://github.com/ggml-org/llama.cpp/discussions/20574?utm_source=chatgpt.com "[Tutorial] Mastering Host-Memory Prompt Caching in llama-server · ggml-org llama.cpp · Discussion #20574 · GitHub"

<<<FRONTIER-BRIDGE-ANSWER-END pack=42ad8308>>>
