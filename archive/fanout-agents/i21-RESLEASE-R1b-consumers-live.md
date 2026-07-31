# FANOUT_AGENT_001 -- GPU lane: R1b CONSUMER wave (lease-split adoption + real evictor + live-GPU proof)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY -- dispatch into a fresh Cowork session with the one folder grant
  (`C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i21 (plan id `fo-21-<TBD>`; single-worker GPU wave + a parallel off-box frontier lane)
- **Lane:** GPU -- and the ONLY on-box worker this wave (model module #7 is `parallel_safe:false` + the live
  proof needs the real GPU => single-worker, handoff section 8).
- **Worker id / label:** `RESLEASE-R1b-consumers-live`
- **Module/area (EXCLUSIVE):** `modules/07-model-gateway/` + `modules/21-agent-local/` (+ NEW
  `modules/07-model-gateway/lib/PoolEvictor.ps1`). `modules/29-resource-lease/` ONLY on a genuine contract gap
  (prefer none -- consume the hardened primitive, do not rework it).
- **GPU:** **true** (the live 3B<->9B swap / pin-revocation / prepared-eviction proof on the 2080 Ti).
- **Docs:** `[]` (the orchestrator mirrors + folds all core-docs).

## Mission

Complete R1: the res.lease #29 primitive is hardened through v0.4.0 (R1a `e701328` i18 -> R1b `2d45ffe` i19 ->
R1b' `f6df675` i20; 74/74 + 36/36 + 45/45, 0 regression). This wave wires the split into its REAL consumers --
`model.gateway` #7 PoolManager (`-UsePoolLeaseSplit`, default-off) + `agent.local` #21 governor (`-SplitLease`,
default-off) -- builds the REAL supervisor-routed nvidia-smi evictor (`lib/PoolEvictor.ps1`, the
`-EvictorMode command` seam, fence-op target-fenced), and runs the LIVE-GPU proof (real 3B<->9B swap under
pin + short exec leases; a second owner revokes + safely evicts; adversarial live A: revoke during an ACTIVE
inference -> drain/cancel/tree-kill + result discarded; adversarial live B: a late stale result refused by
`check authority_ok:false` AND `fence-op`). ON SUCCESS warm-pool findings 1/13/14 become CLOSE-ELIGIBLE
(orchestrator folds); the only remaining default-ON gate is then the SOAK.

## Unit (the full worker prompt)

The complete prompt is the `plan`-emitted copy:
`modules/30-orchestrate-fanout/runtime/artifacts/<invocation_id>/workers/worker-RESLEASE-R1b-consumers-live.prompt.md`
(also delivered to Nicholas as a file; source of truth = `runtime/workers-i21.json` `unit`). Governing docs, in
reading order:

1. `modules/29-resource-lease/R1b-consumer-adoption-spec.md` -- THE code-level spec (delivered i19, recovered
   i21) **including its i21 addendum**: the body is v0.3-era; the v0.4.0 surface (two-phase
   `-Transition -TwoPhaseCommit` -> `commit -HealthOk`, `fence-op` target-fencing, incarnation ids,
   `request_id` idempotency, `state_version`) SUPERSEDES it; `modules/29-resource-lease/README.md` +
   `skill.json` (0.4.0) win on any conflict.
2. res.lease 0.4.0: `README.md` + `skill.json` + `tests/Invoke-ResLeaseR1bTests.ps1` (36) +
   `tests/Invoke-ResLeaseR1bPrimeTests.ps1` (45) -- the primitive's behavioral truth. i20 ship state: Project
   `claude/fanout/RESLEASE-R1bprime-i20-SHIP-STATE.md` / D-0075 (lists exactly what was deferred to THIS wave).
3. The captured i19 red-team answer
   `modules/31-frontier-bridge/runtime/artifacts/b823d9db-72c1-4a05-aeaf-867e39f5330c/frontier-pack-i19-r1b-redteam.answer.md`
   + `core-docs/research/2026-07-30-work-order-gpu-lease-split.md` (with its folded i18 frontier section) +
   `.../2026-07-30-frontier-review-self-tasking-orchestration.md`.
4. `modules/07-model-gateway/` (Invoke-ModelGateway.ps1, lib/PoolManager.psm1 pure helpers, lib/Supervisor.psm1 +
   Start-GatewaySupervisor.ps1, WARM_POOL_DESIGN.md sections 4/6/9/10) + `modules/21-agent-local/Invoke-AutoRamp.ps1`
   (the whole-task lease block ~469-500) + `core-docs/ADAPTIVE_RESOURCE_GOVERNOR.md` sections 5/6.
5. `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` (Known failures IN FULL) +
   `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` section 8 + `core-docs/SKILL_CONTRACT.md`.

Key clamps: all defaults BYTE-IDENTICAL with the flags off; every destructive op targets an exact
`resident_instance_id` + consults `fence-op` first; ALL server start/stop through the durable supervisor
(DETACHED; reap before finalize; 0 UNMANAGED orphans); same-model reuse stays ~1 ms-class; no models.json change
expected (re-verify Module 7 42/42 if unavoidable); the proof harness's simulated owners acquire the real gpu
exec/pin leases THEMSELVES (no outer whole-task gpu lease wrapped around the proof); leases dir EMPTY after.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`. `docs:[]`.
- Lease order gpu -> git -> doc. BUILD-THEN-VERIFY: build + off-machine gate FIRST (0 regression: #7 228/228,
  #21 122/122, #29 74/74+36/36+45/45 + NEW adoption/evictor mock tests); take `git` ONLY for the dev.ship
  commit and release it; THEN the live-GPU proof.
- Ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). VERIFY the
  real HEAD via native `git log`/`git show --stat`, NOT the dev.ship `committed` field (D-0072).
- Persistent llama-servers DETACHED via the supervisor; reap before finalize; `review_queue.jsonl` before ==
  after; heartbeat `degraded:false` throughout.
- Report: `-Action report -PlanId <plan> -WorkerId RESLEASE-R1b-consumers-live -State done` (+ plain measured
  results; negative results are first-class, D-0061). FALLBACK: ship the solid default-off subset, keep
  defaults byte-identical, do NOT declare findings 1/13/14 close-eligible, report plainly what remains.

## Verification

Off-machine: all existing suites green (0 regression) + new adoption/evictor mock tests green. Live: the
transition phase trace (RESERVED_FENCED -> ... -> COMMITTED, no grant-before-ready), swap ~4.1 s-class / reuse
~1 ms-class + p50/p95, pin revocation + prepared eviction (headroom via nvidia-smi), live tests A+B evidence
(drain/cancel/tree-kill + discard; `authority_ok:false` + `fence-op` refusal), liveA/liveB single-agent
equality, 0 orphans, queue unchanged, a Verification Console `run_module` item.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(pending)
