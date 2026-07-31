# FANOUT_AGENT_001 -- GPU lane: SUPERVISOR-HARDENING (i23) -- ARCHIVED (done)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** ARCHIVED (dispatched -> done -> folded D-0078)
- **Wave / iteration:** i23 (plan id `fo-23-36f97a35`)
- **Lane:** GPU (<=1 per wave) -- the ONLY worker this wave (single-worker)
- **Worker id / label:** `SUPERVISOR-HARDENING-i23-live`
- **Module/area (exclusive):** `modules/07-model-gateway/` (#7) -- `lib/Supervisor.psm1` + `Start-GatewaySupervisor.ps1` + `lib/PoolManager.psm1` + `lib/PoolEvictor.ps1` + `Invoke-ModelGateway.ps1` client-side liveness (+ its tests). Consumes res.lease #29 0.4.1 UNCHANGED.
- **GPU:** true
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors + folds)

## Dispatch

Nicholas: start a FRESH Cowork session, grant the ONE folder `C:\Users\just_\LifeOrchestrator-Refresh`, and say: *"Read the Project doc `claude/fanout/FANOUT_AGENT_001.md` and execute it."*

## Mission

Fold the i21 frontier security red-team's **10 must-fixes** into the durable Windows Job-Object gateway supervisor + integrity layer + real evictor, so the DEFAULT-OFF warm-pool supervisor becomes safe to eventually run default-ON. Governing spec: `core-docs/research/2026-07-31-frontier-supervisor-redteam.md`. On success **finding 5 (durable Job-Object custody) CLOSES**, leaving warm-pool default-ON gated only on the in-proc res.lease client + a grown soak. The whole supervisor surface stays DEFAULT-OFF this wave -- additive hardening under `-UseSupervisor`/pool flags; the classic-cold + D-0057-warm default paths stay byte-for-byte unchanged.

## Unit -- AUTHORITATIVE PROMPT

Your complete, self-contained unit prompt (20 KB) is on disk at:
`modules/30-orchestrate-fanout/runtime/artifacts/873bf0a3-7207-4a0c-98cb-bf7dd5db499c/workers/worker-SUPERVISOR-HARDENING-i23-live.prompt.md`
**Read it IN FULL and execute it exactly** -- it carries the READ-FIRST list, the priority-ordered scope, the gates, scope-out, and the report command. The 10 must-fixes fold into 9 priority-ordered scope items (orientation only; the prompt file is authoritative):

1. Per-resident **suspended-create Job custody** (assign -> IsProcessInJob verify -> resume; no child runs before it is in its job); job-assignment/support failure is **FATAL** (no publish on `job_owned:false`).
2. **Lifetime supervisor singleton** (named-mutex claim in `run` before publish; a second supervisor exits cleanly).
3. **Exact target-fenced + authenticated IPC** on every mutation (REQUIRED resident_instance_id + expected epoch + state_version + fence-op receipt; strict request_id + path containment; idempotent receipts; separate admin `shutdown`).
4. **No launch after a failed/partial evict or a failed CAS** (fail the transition, leave the GPU ungranted; `tree_gone` = per-resident Job zero-members, not pid+socket).
5. **Abandonment-aware nonce'd pool lock** (never steal a LIVE owner's lock on a time bound; release checks the nonce; move load/probe/drain/kill out of the short manifest lock).
6. **Hard nvidia-smi probe deadlines** (pinned absolute path; timeout -> unknown -> `confirmed:false`; low headroom w/ no managed target -> `unmanaged_vram_pressure`, never a blind kill).
7. **Heartbeat-stale => UNRESPONSIVE, NO live-but-unresponsive fallback** (supervisor-side incarnation-fence / zero-members-wait / journal-reconcile hooks IN; the exec.watchdog #00.1 out-of-process relaunch driver NAMED if it does not fit; the safety half -- no unsafe fallback -- is non-negotiable).
8. **Restart reconcile -- no manifest-only survivor adoption** (a survivor is evidence of failed custody; adopt only via a durable custodian holding the retained job handle + verified membership/identity).
9. **Real expected-hash content verification** + stronger process identity (verify engine+model bytes immediately before launch; canonicalize paths + reject reparse points; move runtime state to an ACL'd app-data dir). No THEATER (no same-user HMAC/ACL "security"; no hashes trusted only because they sit in a mutable `models.json`).

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` (Known failures IN FULL) first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease in **gpu -> git -> doc** order; build + gate off-machine first, take git ONLY for the dev.ship commit and RELEASE it, THEN run the live proof (the proof harness itself is the lease consumer -- NO outer whole-task gpu lease). **RESTART the durable supervisor after every supervisor-side change** before any live check (the i21 stale-in-memory-module lesson).
- Do ONE unit; touch ONLY `modules/07-model-gateway/` (+ res.lease #29 only on a genuine additive-and-logged gap, prefer none); `docs:[]`.
- Gate off-machine FIRST (mock supervisor/nvidia-smi/Job seams; #7 228/228 + res.lease 74/74+36/36+45/45 zero-regression + a seam test per must-fix), THEN dev.ship (sha256 + AST + tests, fail-closed, named files, trailers) -> **verify real HEAD via native git** (D-0072), THEN the live fault-injection proof (executor; all server ops through the supervisor, DETACHED, reaped; **0 UNMANAGED orphans**; leases dir empty; queue unchanged). Bump `skill.json` 0.5.0 -> 0.6.0.
- **SCOPE OUT (name as follow-ons):** the grown soak; the in-proc res.lease client; flipping default-ON; the #00.1 relaunch driver if it does not fit; any two-model co-residency (hard STOP).
- Report: `-Action report -PlanId fo-23-36f97a35 -WorkerId SUPERVISOR-HARDENING-i23-live -State done` (+ a plain summary; negative results are first-class -- the D-0061 ethos).

## Verification

Off-machine seam suite (per must-fix) + #7 228/228 + res.lease 74/74+36/36+45/45 all green, 0 regression; on-box dev.ship green + the on-box subset of the digest's 15 deterministic live fault-injection tests; byte-identical defaults with every flag OFF; 0 UNMANAGED orphans; leases dir empty; queue before==after; and the EXPLICIT statement of whether finding 5 is CLOSED and what default-ON now gates on.

## Report-back record (ORCHESTRATOR fills from `plans/fo-23-36f97a35/reports/` before archiving)

**Worker:** SUPERVISOR-HARDENING-i23-live · **State:** done · reported 2026-07-31T16:56:20Z · plan `fo-23-36f97a35`.

- **Commit:** `d289ba9` — model.gateway 0.5.0 -> **0.6.0**; 8 files (Supervisor.psm1 +531, Start-GatewaySupervisor.ps1, PoolManager.psm1, PoolEvictor.ps1, Invoke-ModelGateway.ps1, skill.json, NEW tests/Invoke-ModelGatewayHardeningTests.ps1 +478, SupervisorCoreTests). HEAD verified via native git (D-0072).
- **Result:** all 10 must-fixes folded (MF10 partial); defaults byte-identical. MF1+2 per-resident suspended-create Job custody **LIVE-PROVEN** on the box (real Job Objects, member-count, zero-members tree-gone). MF3 singleton; MF4 authenticated fenced IPC (path-containment + replay + admin shutdown); MF5 no-launch-after-failed-evict/CAS; MF6 abandonment-aware nonce lock; MF7 hard probe deadlines + unmanaged_vram_pressure; MF8 heartbeat-stale UNRESPONSIVE + no split-brain fallback (safety half); MF9 no manifest-only survivor adoption.
- **Gates:** 366 off-machine + 74 on-box Windows real-custody green; res.lease 74/36/45 UNCHANGED; 0 UNMANAGED orphans; leases dir empty; queue before==after.
- **Finding 5 (durable Job-Object custody) CLOSED/live-proven.** Default-ON now gates ONLY on: an in-proc res.lease client + a GROWN soak.
- **NAMED residuals (follow-on):** MF8 exec.watchdog #00.1 -> supervisor relaunch DRIVER; MF10 ACL'd app-data state-dir move + trusted expected-hash-manifest provisioning. The full real-model 15-test fault-injection sweep folds into the grown soak.
- **Frontier (orchestrator):** as-built supervisor red-team pack `ff24d3a4` emitted for GPT-5.x (answer PENDING read-return).
