# RESLEASE-R1b-consumers-live (i21, plan fo-21-61c7597b) -- SHIP STATE

**Worker:** FANOUT_AGENT_001 / `RESLEASE-R1b-consumers-live` (the SINGLE on-box GPU worker this wave).
**State:** `done` (report filed to `plans/fo-21-61c7597b/reports/RESLEASE-R1b-consumers-live.0c74d30f.json`, 14.2 KB).
**Outcome:** the **R1b CONSUMER wave SHIPPED + LIVE-PROVEN**. model.gateway #7 and agent.local #21 adopt the
res.lease 0.4.x GPU-lease split behind default-off flags, the REAL supervisor-routed nvidia-smi evictor
(`lib/PoolEvictor.ps1`) plugs into `-EvictorMode command`, and the full live-GPU proof passed on the 2080 Ti.
**Findings 1/13/14 are CLOSE-ELIGIBLE** (the orchestrator folds WARM_POOL_DESIGN section 10 -> CLOSED). The only
remaining warm-pool default-ON gate is the **SOAK** (plus one strongly recommended follow-on below).

## Shipped (committed, verified real HEAD via native git -- D-0072)

- **Commit `0877c70a2924f794fc1ecf394cebac27f2cfe8b0`** (parent `5be6008`, `master`): the wave -- 16 named
  files, +1808/-73, trailers `Co-Authored-By: Claude Fable 5` + `Claude-Session`. dev.ship fail-closed green
  (sha 16/16 byte-exact, AST 9/9, on-box suites exit 0, git lease via the NEW 0.4.1 res.lease acquired 82 ms +
  released, 0 orphans).
- **Commit `00e5912bcb2d9d5260635f72b90e2a9e80591d2c`**: fix -- bind the supervisor-launched
  `instance_generation` to the split transition capability (2 files). **Found BY the live proof** (P2: every
  supervisor-routed swap failed the post-commit full-tuple gate `authority_mismatch` because the supervisor
  minted its own generation); invisible off-machine (the cloud gate exercises the per-call launch).
- Modules: **model.gateway 0.4.0 -> 0.5.0** (`-UsePoolLeaseSplit` + `lib/PoolEvictor.ps1` NEW + supervisor
  target-fenced evict + manifest `resident_instance_id` stamped at every launch), **agent.local autoramp
  0.1.0 -> 0.2.0** (`-SplitLease`), **res.lease 0.4.0 -> 0.4.1** (command-evictor `tree_gone` passthrough to
  the transition result + txn journal -- a partial-tree ABORT was journaled `tree_gone:true`; grant was already
  fail-closed on `confirmed`; surfaced by wiring the real evictor; T0 pins track 0.4.1, behavioral assertions
  unchanged; NOTE: modules/29 skill.json cosmetically re-serialized, content-identical except version).

## Gate (0 regression)

**Off-machine (cloud pwsh 7.4.6):** res.lease 74/74 + 36/36 + 45/45 · model.gateway 228/228 (23+49+48+37+46+25)
+ **NEW `tests/Invoke-ModelGatewayLeaseSplitTests.ps1` 63/63** (default-off byte-identity incl. gpu_lease
key-set equality; the PoolEvictor fail-closed ladder vs mock supervisor/nvidia-smi seams; the FULL two-phase
composition with a real revoked pin + killed sleeper + commit; adoption pin/exec/swap/commit/repin; both
revocation paths; the late-stale-result refusals; the supervisor target-fenced evict) · agent.local 102/102 +
autoramp 122/122 + **NEW `tests/Invoke-AutoRampSplitTests.ps1` 22/22** (byte-identity, pin plumbing, split keys
threaded to every LLM child, OFF==ON equality). **On-box (inside dev.ship):** the res.lease trio + both new
suites, exit 0.

## The live-GPU proof (evidence: `modules/07-model-gateway/runtime/proof-i21/` -- step JSONs, txn journals, evictor receipts)

- **(a) Swap chain under the split:** cold 3B 1490 ms -> reuse x3 at 0/1/1 ms -> 9B 3675 ms -> 3B 1456 ms ->
  9B 3638 ms, every load `RESERVED_FENCED -> DRAINING -> HEADROOM/STARTING (capability usable:false) ->
  commit COMMITTED` (no grant-before-ready); lease+manifest+tuple agree on `resident_instance_id` +
  `instance_generation` at every step; epochs monotonic; NO managed-resident overlap. 9B swap p50 ~3650 ms
  [3372..3675], 3B ~1455 ms, reuse ~1 ms-class.
- **(b) Second-owner revocation -> a PREPARED GPU:** a prio-99 transition revoked the prio-40 pin by exact
  lease, PoolEvictor fence-consulted (authority_revoked on the EXACT target accepted), drained (slots idle
  52 ms), supervisor-TARGETED stop (9B dead), headroom STABLE [10299,10299,10302,10302], capability -> 3B
  1453 ms -> commit epoch 29. free 3591 -> 10302 -> 8026.
- **(c) Adversarial live A (revoke during ACTIVE inference):** drain receipt `active_seen:true` on a real
  1600-token 9B generation; cooperative drain expired (1574 ms) -> cancel -> supervisor Job-Object TREE-KILL
  mid-inference; the in-flight call returned `completion_failed`, output ABSENT -- **discarded, never
  published**; the preemptor's 3B committed.
- **(d) Adversarial live B (late stale result):** the captured stale tuple -> `check authority_ok:false`
  (fence_stale) AND `fence-op` result_publish/manifest_write/stop ALL refused `target_instance_mismatch`
  naming stale-vs-current AND the supervisor refused a stale targeted evict -- the current resident survived
  and kept serving (positive control "PONG").
- **(e) Fail-closed prep (red-team H, live):** a REAL dying tentative server (invalid `--cache-type-k`) after
  the capability -> `commit -HealthFailed` -> **GPU left EMPTY** (manifest null, 0 procs, no usable lease; old
  resident NOT restored) -> a later clean transition succeeded.
- **(f) Real-OOM = an environmental NEGATIVE (first-class):** on driver 591.74 a hard CUDA alloc failure is
  UNREACHABLE -- the driver spills to system RAM (9B @ctx131072 loaded, free 249 MiB; even the 27B @ngl99 went
  RESIDENT, free 329). **"It loaded" != "it fits"**: the measured-PEAK `required_vram` + stable-headroom gate
  is the only real admission control (vindicated). WDDM pressure treated as environment throughout (the
  mid-proof game-closure moved free-empty 7400 -> ~10200 and the proof rode through it).
- **(g) Equality (normalized preconditions):** liveA (M0-only) and liveB (engineered M0->S0, ONE real 3B->9B
  swap) each **IDENTICAL** with `-SplitLease` off vs on (final_status/accepted_epoch/epochs/swaps/artifact).
  A first liveA attempt diverged on a DIRTY precondition (a foreign 9B resident correctly HARD-triggered the
  OFF run) -- real behavior, not a split defect; rerun normalized.
- **(h) Teardown asserts:** supervisor stopped + tree reaped; **0 llama-server / 0 python**; live lease files
  **EMPTY** (durable `.fence/.state/.txn` siblings persist by design); **review_queue.jsonl 20 == 20** (6
  harness low-confidence flags -- the KNOWN 9B empty-content-at-tiny-max-tokens nuance -- removed with
  per-line validation, preserved in `proof-i21/removed-review-lines.jsonl`); heartbeat `degraded:false`
  throughout.
- **(i) Verification Console packet:** `modules/30-orchestrate-fanout/runtime/artifacts/i21-rsplit-vp/
  verification-packet.json` (`vp-i21-rsplit-001`) -- run_module two-phase capability + commit + a target-fenced
  stale-stop refusal on a scratch resource + a human review item over the live bundle.

## Measured overhead (feeds the soak/default-ON decision)

A split call adds ~6-9 res.lease child-pwsh spawns (~0.9-1.3 s each on this box): reuse-generate wall
~6.6-7.2 s vs classic ~1-2 s; a split ensure+swap ~12-15 s (swap itself 1.5-3.7 s). The **pwsh-spawn cost
dominates, not the protocol**. NAMED follow-on: an **in-process res.lease client** (batched ops) before any
default-ON.

## Live-found gotchas (fold into Known failures)

1. Consumer identity params must pin BOTH `resident_instance_id` AND `instance_generation` through the
   supervisor launch (commit `00e5912`).
2. A long-running supervisor keeps OLD module code -- **restart the supervisor after shipping
   supervisor-side changes** (the first P2 rerun failed on the stale module).
3. `[Console]::Out` bypasses in-process pipeline capture (`& script | Out-String` gets nothing) -- the same
   class as the dictionary-property trap; PoolEvictor emits via `Write-Output`, harnesses capture via
   child-process redirection.
4. The 9B returns empty content at tiny `-MaxTokens` (known) -> low-confidence review-queue flags; harnesses
   use >=64 tokens + a redirected review path.

## Close-eligibility + what remains

**Findings 1/13/14: CLOSE-ELIGIBLE** (evidence per finding in the report; the orchestrator folds
WARM_POOL_DESIGN section 10 -> CLOSED). **Remaining default-ON gate: the SOAK** (>=200 transitions, >=25 forced
revocations, >=25 injected crash/expiry/cancel, long idle/resume, zero stale publications, zero
grants-before-confirmed-headroom, zero orphaned managed servers, zero unreconciled transitions, p50/p95) --
with the in-proc lease client strongly recommended first. Also named, NOT built: R3 strong preflight; R4/#26
baton-pass; native router/`--slot-save-path`; contention-driven idle eviction (finding 11); fair scheduler
(finding 10); exec.watchdog #00.1 -> supervisor relaunch.

## Rails honored

`docs:[]` (no core-doc touched). Lease order: git only for the two dev.ship commits (acquired+released inside
dev.ship); the proof harness's simulated owners acquired the real gpu exec/pin leases THEMSELVES through the
surfaces under test -- no outer whole-task gpu lease. All server start/stop through the durable supervisor
(DETACHED; targeted, fence-op-gated stops; reaped before finalize); 0 UNMANAGED orphans at every checkpoint.
BUILD-THEN-VERIFY: off-machine gate FIRST, then dev.ship, then the live proof. Negative results reported
first-class (the driver-spill OOM finding, the dirty-precondition equality divergence, the overhead numbers).
