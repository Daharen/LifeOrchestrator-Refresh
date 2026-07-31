# Frontier red-team (AS-BUILT): the i23 hardened supervisor is NOT soak-ready -- GATE = NO (i24)

**Staged 2026-07-31 (D-0079).** Off-box GPT-5.x AS-BUILT code-path red-team of the i23
SUPERVISOR-HARDENING wave (`model.gateway` #7 0.6.0, commit `d289ba9`): the durable Windows Job-Object
gateway supervisor (`lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1`), the integrity layer
`lib/PoolManager.psm1`, the R1b real evictor `lib/PoolEvictor.ps1`. Human-couriered via `frontier.bridge`
#31 (pack `ff24d3a4`, 10 files / 476 KB vs HEAD `d289ba9`). Answer captured/valid, `pack_id_match=true`,
sha256 `eb9daafb...`, 26360 chars. Reviewer did NOT rerun the Windows live proofs -- code-path review.
Full answer on disk: `modules/31-frontier-bridge/runtime/artifacts/ff24d3a4-.../*.answer.md`.

## Verdict: NO

`d289ba9` does **not** reduce the warm-pool default-ON gates to only a grown soak + an in-proc
`res.lease` client. The suspended-launch primitive is materially improved and several primitives are
real, but deterministic **custody, fencing, transition, liveness, and recovery** failures remain and
must be fixed BEFORE the formal gating soak. The i21->i23 analogue: each pass closes the last red-team's
Criticals and surfaces the next layer's.

## Must-fix disposition (the i21 red-team's 10, re-judged as-built)

MF1 suspended-create custody = PARTIAL (launch order correct; `tree_gone` accounting unreliable). MF2
"every default-ON resident custodied" = only in the direct launcher (fallback + legacy launch paths
remain). MF3 singleton = NOT global (mutex names a `SupervisorRoot`, not the GPU/pool). MF4 authenticated
mutation = NOT achieved (generation binding optional; exact targets optional; lease tuple absent; replay
receipts process-local). MF5 fail-closed transition = PARTIAL (legacy non-split path fail-open; evict
ignores its STOPPING CAS; `PrepareGpu` grants on unknown VRAM). MF6 short pool lock = primitive partial
(slow work still inside the lock). MF7 bounded probe = primitive only (unknown VRAM can be `ready:true`).
MF8 availability/recovery = NOT achieved (alive-supervisor fallback; false-stale heartbeats; #00.1
driver absent). MF9 boot reconcile = NOT achieved (can clear a live survivor + serve). MF10 trusted
integrity = NOT achieved (verification off by default; partial hashes accepted).

## The prioritized i24 must-fix list (all HARD BLOCKERS before the soak)

- **P0.1 Durable mandatory authority-tuple IPC binding.** Normal routing sends a BLANK generation, which
  authorizes `ensure_resident`/`prepare_gpu`/`evict`/`reconcile`; handlers take no exact target;
  `force_reload` needs no live `fence-op` receipt; the replay guard is process-local + written only
  AFTER the side effect (crash -> replay); the client accepts any parseable `ok` (G1 request answered by
  G2). Require + server-validate on every mutation: exact `supervisor_generation` + `resident_instance_id`
  (incl. explicit EMPTY) + `gpu_authority_epoch` + durable `state_version` + op kind + a live `fence-op`
  receipt. Add a durable per-`(gen,request_id)` journal (RECEIVED->AUTHORIZED->SIDE_EFFECT_STARTED->
  COMMITTED/FAILED); a same-id retry resumes/returns, never re-executes. (`PoolEvictor` captures both
  epochs but never compares them.) The lexical `request_id` check is fine -- the gap is authority+durability.
- **P0.2 Fail-closed Job custody.** `Get-ResidentJobMemberCount` returns `-1` on absent/exception and
  `Close-ResidentJobTree` treats every `<=0` (and no-tracked-Job) as zero -- a failed query becomes
  proof-of-empty; the split evictor's `tree_gone` is only (PID dead AND socket not occupied); `PrepareGpu`
  never queries the Job. Outcomes must be `known_zero`/`known_nonzero`/`unknown` (never `-1<=0`); a
  `job_owned:true` resident with no tracked job id is FATAL; never close the handle until a valid query =
  exactly zero; emit a state-signed eviction RECEIPT and make `PoolEvictor` REQUIRE it.
- **P0.3 Delete every fail-open non-split transition.** The default path ignores its STOPPING CAS, clears
  the manifest even when termination failed, launches anyway, and only warns on the final CAS failure;
  `PrepareGpu` reads VRAM outside the lock (plans vs R1, stops R2); unknown VRAM grants. ONE authoritative
  state machine; lock-timeout = structured ERROR (never lockless proceed); check every CAS before the next
  side effect; bind every stop to the exact planned instance; unknown VRAM always `ready:false`.
- **P0.4 Alive-supervisor fallback + heartbeat, THEN build #00.1.** Fallback is allowed whenever
  `live.running` is false even if the process is ALIVE (split-brain during graceful STOPPING drain);
  the heartbeat is written only after the synchronous handler returns, so a healthy 90-120 s load reads as
  wedged after 30 s. Forbid fallback whenever the recorded process is alive + identity-matched; move
  heartbeat/progress off the handler thread; generation-bind the stop sentinel. Then build #00.1 (fence
  old gen -> block grants -> kill the exact old supervisor after revalidating PID/start-time/gen -> wait
  all Jobs=0 -> reconcile -> one successor). **MF8 recovery driver = HARD BLOCKER before the soak** (the
  soak cannot measure recovery without it), not soak-deferred.
- **P0.5 Fail-closed exclusive boot reconcile.** Publishes RUNNING before reconciling + ignores reconcile
  exceptions; a live survivor that fails `StopProbe` is cleared to EMPTY; the IPC reconcile omits
  `RequireCustodian`. Publish RECOVERING first; install no mutating handlers until reconcile is terminal-
  safe; a stop-failure leaves `ORPHAN_PRESENT`/`RECOVERY_BLOCKED` (never EMPTY) + blocks launch/grant;
  RUNNING only after all old Jobs=0 + no unidentified survivor + manifest reconciled + VRAM known.
- **P0.6 Scope the singleton to the physical authority.** The mutex hashes only `GetFullPath(Root)` (a
  test confirms two roots -> two singletons on one registry/GPU). Derive identity from canonical
  `WarmRegistryPath`/pool id + GPU device id; reject reparse aliases; a second root on the same GPU/pool
  must FAIL startup.
- **P0.7 Short pool lock; no lockless degradation.** `EnsureResident`/`PrepareGpu` hold the lock through
  eviction + launch + the up-to-120 s health poll + final CAS (priority inversion + the heartbeat
  false-positive); the legacy path proceeds unserialized after a 15 s timeout. Hold the short lock only
  for read-state / validate state_version / reserve / record-intent / commit; do drain, probes,
  termination, Job waits, model load OUTSIDE it; revalidate before each irreversible step.
- **P1.8 Mandatory trusted-hash provisioning (MF10).** `trusted-hashes.json` is optional (absent -> no
  verification), blank entries skipped, and it lives in the mutable source tree. Provision from an
  independently-generated deployment-pinned manifest; require an entry per exe/script/model/mmproj; a
  missing manifest/entry/hash or reparse trust-root is launch-FATAL; move control state out of the source
  checkout. **Trusted-hash provisioning AND the app-data/ACL relocation are hard blockers before the
  final production-config soak** (the app-data move may be deferred during unit-level dev, not past it).
- **P1.9 Revalidate identity before any forced supervisor kill.** `-Action stop` reads the PID once then
  kills after a wait without rereading start-ticks/generation (PID-reuse kills the wrong process). Reread
  start-ticks + generation + singleton state immediately before every forced PID op; on mismatch, refuse.

## 18 deterministic tests required before the soak (make each defect a unit test, not a duration bet)

`-1` count -> `tree_gone:false`; no-tracked-Job blocks replacement; root-dead+1-descendant blocks
replacement; blank `expect_generation` refused; crash-after-side-effect -> restart no-repeat; wrong
schema/request-id/op/gen response rejected; delayed evictor + wrong epoch refused; alive STOPPING/
RECOVERING -> `no_fallback:true`; healthy 90-120 s load not watchdog-killed; unknown VRAM -> `ready:false`;
plan-vs-R1/lock-after-R2 must not stop R2; reconcile stop-failure retains `ORPHAN_PRESENT` + blocks
launch; two roots -> one singleton; pool-lock timeout does no mutation; final non-split CAS failure kills
the launched Job; forced-stop PID reuse refused; stale stop sentinel does not stop a new generation;
missing/partial trusted-hash manifest blocks launch.

## What may remain FOR the soak (empirical residuals only)

Unmanaged external VRAM after the final headroom sample; a watchdog failure that leaves service
unavailable while still preventing overlap; WDDM reclamation latency; handle/process/Job/journal leaks;
transition/lock-wait/recovery latency; sleep/resume timing; long-run cleanup. Blank authority fields,
replay, false Job-zero, fail-open manifest clearing, alive-supervisor fallback, and disabled integrity
are NOT soak residuals -- they are visible code defects.

## Revised gate sequence (supersedes the D-0078 "in-proc client + grown soak" conclusion)

**i24 deterministic hardening (P0.1-P0.7 + 18 tests) -> mandatory trusted deployment config (P1.8) ->
#00.1 recovery driver (P0.4/MF8) -> in-proc `res.lease` client -> grown soak -> default-ON decision.**
The in-proc client is DEMOTED to a perf/integration improvement (it cannot repair an IPC protocol lacking
the authority tuple/durable receipts/exact fencing). MF8 + MF10 move from "named residuals" to hard
blockers before the soak. Finding 5 stays live-proven for the suspended-create launch primitive, but
custody ACCOUNTING (P0.2) is not yet fail-closed.

## What this changes for the project

Default-ON is materially further out than the D-0078 snapshot implied: a full i24 deterministic-hardening
wave (single-worker GPU core-infra; ~9 P0/P1 fixes + 18 tests) + trusted-deployment config + the #00.1
recovery driver all precede the grown soak. Decision-relevant to the whole-project direction review (the
frontier project-direction pack emitted the same session): the supervisor line is the project's deepest
recurring sink (i14-i23, now i24), each frontier pass validating real progress AND reopening the next
layer. Nicholas's call: run i24 as that hardening wave; OR freeze the durable supervisor and keep the
classic detached-warm path as the trusted default; OR reprioritize toward the video spine / other lanes.
