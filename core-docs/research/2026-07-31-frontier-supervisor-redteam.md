# Frontier red-team: the durable gateway supervisor + real evictor are NOT default-ON-safe yet (i21)

**Staged 2026-07-31 (D-0076).** Off-box GPT-5.x security/robustness red-team of the durable Windows Job-Object
gateway supervisor (`modules/07-model-gateway/lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1`), the
integrity layer `lib/PoolManager.psm1`, and the R1b real-evictor contract, run in PARALLEL with the i21 R1b
CONSUMER wave. Pack `5cbe8913` (`frontier.bridge`); captured answer
`modules/31-frontier-bridge/runtime/artifacts/5cbe8913-.../frontier-pack-i21-supervisor-redteam.answer.md`
(read-return `captured/valid`, `pack_id_match`). This digest is the GOVERNING doc for the future
**supervisor-hardening wave** (the analogue of how the i19 red-team governed the i20 R1b' brief).

## Provenance note -- the review predates the i21 worker's commits

The pack was generated at i21 SCOPING (the supervisor as of `59bdfb7`/`5be6008`), BEFORE the worker shipped
`0877c70` + `00e5912`. The orchestrator therefore **re-verified every blocker against the live HEAD
`00e5912`**. Result: the verdict holds -- the i21 wave was consumer-adoption + the fenced-evictor LAYER, NOT a
supervisor rewrite, so 6 of 7 blockers live in code the worker never restructured; 1 (IPC target-fencing) is
partially addressed. Per-blocker verification below.

## Verdict (frontier)

**NO -- the supervisor is not safe to run default-ON after the currently specified R1b proof + soak.** Seven
structural blockers; until all are implemented AND directly fault-injected, the warm pool stays default-OFF.

## The 7 blockers, verified against HEAD `00e5912`

1. **Server executes before Job-Object custody; failed assignment is non-fatal.** VERIFIED OPEN.
   `New-RealLauncher` does `Start-Process` -> pid -> THEN `Add-ProcessToGatewayJob`; on failure `job_owned=$false`
   and it returns anyway; `Invoke-SupervisorEnsureResident` publishes the STARTING manifest with `job_owned=$false`
   and proceeds. A child spawned pre-assignment (or via `Win32_Process.Create`) is not inherited into the job, so
   on a supervisor crash `KILL_ON_JOB_CLOSE` leaves it unmanaged. The forced supervisor-stop also `taskkill`s a
   recorded pid after ~25 s with no immediate re-validation (PID-reuse window).
2. **Control surface not authenticated / not target-fenced.** VERIFIED PARTIAL (the one place i21 touched).
   The `evict` IPC handler now threads `target_resident_instance_id` and `Invoke-SupervisorEvict` refuses
   `target_instance_mismatch` / `manifest_instance_unknown` -- but the target is OPTIONAL (no target => legacy
   stop), and there is still no caller-identity / epoch / state-version / consumed-request journal; `shutdown` is
   accepted directly; `prepare_gpu`/`reconcile`/`ensure_resident(force_reload)` are dispatched by op-name only;
   response files are not schema/generation-validated; `request_id` is used in a response filename with no
   path-containment; there is no lifetime singleton (a two-`start` race can launch two supervisors).
3. **One supervisor-wide Job Object cannot do exact per-resident eviction; `tree_gone` is only a heuristic.**
   VERIFIED OPEN (structural). `Start-GatewaySupervisor.ps1`/`Supervisor.psm1` create ONE `KILL_ON_JOB_CLOSE`
   job and assign every server to it. **Precision correction to the frontier:** the normal evict kills by
   `taskkill /PID <pid> /T /F` on the exact (now target-fenced) pid tree, NOT by closing/terminating the shared
   job -- so its "T1 closes J and kills R2" wrong-tree interleaving is not the live kill path; the shared job is
   only the crash-time backstop reaper. The stands-as-real part: `tree_gone` is confirmed by pid-death +
   socket-gone, which does NOT prove a detached child released VRAM; and the single job gives no per-resident
   isolation on supervisor crash.
4. **Pool lock can be stolen from a LIVE owner after 60 s; release has no ownership nonce.** VERIFIED OPEN.
   `Enter-PoolLock` (`StaleMs=60000`) breaks a lock whose holder pid is alive once `acquired_utc` age > StaleMs;
   `Exit-PoolLock` `Remove-Item`s the path with no nonce check -> a resumed wedged owner can delete a replacement
   owner's lock (split-brain). Untouched by i21.
5. **Failed eviction still clears the manifest + launches a replacement (fail-open).** VERIFIED OPEN on the
   DEFAULT path (`PoolManager` `EnsureResident`: `evict_confirmed:false` then swap-count++ / clear-manifest /
   launch; ignores the STOPPING CAS; a failed final CAS is a note not a fatal supersession). The i21
   `-UsePoolLeaseSplit` transition IS fail-closed (defers eviction to the two-phase transition; grant only on
   `confirmed`), but that flag is default-OFF.
6. **A wedged supervisor stays "running" -> unsafe fallback + split-brain.** VERIFIED OPEN. `Test-SupervisorLiveness`
   excludes heartbeat freshness from the `running` decision; a hang during a handler stops IPC + heartbeat while
   liveness still says running, the client degrades to the per-call path (a second server), and (4) then lets the
   lock be stolen. This is the already-named-but-unbuilt `exec.watchdog #00.1 -> supervisor relaunch` residual.
7. **Process identity + executable provenance weaker than the v0.4 contract claims.** VERIFIED OPEN. Engine hash
   cached by path+size+mtime (not compared to a trusted expected hash); the model SHA is copied from registry
   metadata, not computed from the launched file; `nvidia-smi`/`pwsh` resolved via PATH; `.ps1` engines run
   `-ExecutionPolicy Bypass`; `Test-ResidentIdentity` proves only pid + creation-time (+-2 s), not exe path/hash
   or Job membership. In `PoolManager`, untouched by i21.

## MUST-FIX before default-ON (the supervisor-hardening wave scope)

1. **Per-resident Job Objects** with suspended-create -> assign -> `IsProcessInJob` verify -> resume; persist
   `job_instance_id + resident_instance_id`; terminate-and-fail if any step fails.
2. **Job assignment / support failure is FATAL** (no publish on `job_owned:false`; `job_supported:false` is a
   startup failure on Windows default-ON).
3. **Lifetime supervisor singleton** (a named mutex / exclusive claim in `run` before publishing; a second
   supervisor exits).
4. **Exact `resident_instance_id` target-fencing on EVERY mutation + IPC request** (op kind + expected epoch +
   expected state_version + a current `fence-op` receipt; strict `request_id` format + path containment; bind to
   `supervisor_generation`; idempotent request receipts; validate response schema/gen; separate admin shutdown).
5. **No launch after a failed / partial eviction or a failed CAS** (fail the transition, leave the GPU
   ungranted; `tree_gone` = per-resident Job accounting shows zero members, not pid+socket).
6. **Replace the stale-age pool lock + nonce-less release** (abandonment-aware named mutex, or an exclusively-held
   lock file with a random ownership nonce; never break a live owner's lock on a time bound; move
   load/probe/drain/kill OUT of the short manifest lock under the durable journal).
7. **Hard probe deadlines** (pinned absolute `nvidia-smi`; kill on timeout -> `unknown` -> `confirmed:false`;
   never hold the pool lock across it; low headroom with no exact managed target -> `unmanaged_vram_pressure`,
   never a blind kill).
8. **Heartbeat-stale watchdog recovery, no live-but-unresponsive fallback** (stale heartbeat => UNRESPONSIVE;
   an out-of-process watchdog fences the old `owner_incarnation_id`, blocks grants, kills the old supervisor,
   waits every old per-resident job to zero members, reconciles the journal, starts ONE new generation;
   an old in-flight op must re-validate its token immediately before any irreversible side effect).
9. **Kill/reload restart reconcile -- no manifest-only adoption** of a survivor (a survivor is evidence of failed
   custody; adopt only via a durable custodian that retained the job handle + verified membership/identity).
10. **Real executable/model content verification + stronger process identity** (trusted expected-hash manifest;
    verify contents immediately before launch; canonicalize paths + reject reparse points on trust roots; move
    runtime state out of the source repo into an ACL-restricted app-data dir).

**Acceptable named residuals after those fixes:** an unmanaged external process allocating VRAM after headroom
confirm; a watchdog failure leaving the GPU service unavailable IF it fails closed (no fallback overlap); a fully
compromised same-user process (outside the attainable boundary). **Theater (do NOT build):** same-user-secret
HMACs, same-SID pipe/dir ACLs as a hostile-user boundary, hashes trusted only because they sit in the mutable
`models.json`.

## Soak -- grown (the current spec is insufficient)

>=24 h continuous supervisor lifetime; >=1 real sleep/resume + >=1 multi-hour idle; **>=1000 transitions** (handle/
process/state-leak coverage); **separate** fault counts (>=25 EACH of supervisor-crash / probe-hang-timeout /
cancel-revoke race / assignment-or-partial-tree fail / external-pressure-OOM). Record beyond p50/p95: p99 + max
transition, heartbeat-stale detection latency, watchdog recovery latency, max pool-lock hold + wait, grant->launch
interval, per-job active-member count, process/job handle counts over time, stale req/resp count, probe-timeout
count, `unmanaged_vram_pressure` count, and ANY interval with >1 managed-or-fallback server. Add the 15
deterministic live tests the answer enumerates (suspended-until-in-job; forced assignment fail; earliest-child
reap; delayed-evict-after-replacement; partial-tree-no-launch; two-supervisor race; IPC-wedge-no-fallback;
crash-at-every-boundary; nvidia-smi hang/malformed/gone; post-sample external alloc; child-survives-root-exit;
PID-reuse at forced-kill; replayed destructive request refused; >60 s op with a waiter = no lock theft;
sleep/resume clock movement).

## Sequencing

**R1b CONSUMER wave (i21, DONE)** -> **supervisor-hardening wave (the 10 must-fixes)** -> **in-proc res.lease
client** (from the i21 split-overhead finding: ~6-9 child-pwsh spawns/call dominate wall time) -> **grown soak**
-> **warm-pool default-ON**. Findings 1/13/14 are close-eligible at the res.lease/consumer LEASE layer (i21 live
proof); **finding 5 (durable Job-Object custody) is effectively RE-OPENED** at the supervisor custody layer by
this review. The baton-pass direction (R1b -> ABA proof -> R2 -> #26) remains Nicholas's call.
