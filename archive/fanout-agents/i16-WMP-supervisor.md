# FANOUT_AGENT_001 -- GPU lane: WMP-supervisor (warm-pool durable supervisor)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i16 (plan id `fo-16-f125365c`)
- **Lane:** GPU (<=1 per wave)
- **Worker id / label:** `WMP-supervisor` -- warm-pool DURABLE Job-Object gateway supervisor
- **Module/area (exclusive):** `modules/07-model-gateway` ONLY
- **GPU:** true
- **Docs:** `[]`

## Mission

Build the PERSISTENT gateway supervisor for the warm multi-model pool -- the DURABLE form of red-team
finding 5 and the LAST Stage-1.1 residual (a) that gates enabling the pool BY DEFAULT
(`modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10). Stage-1.1 shipped at i15 (`121a0fc`, integrity
core `lib/PoolManager.psm1`, pool DEFAULT-OFF); the gateway is invoked PER-CALL so a per-call Job Object
dies on process exit. A persistent supervisor lets the resident llama-server + its Job-Object tree ownership
SURVIVE across per-call invocations. The pool STAYS default-OFF this wave (enable-by-default is the
orchestrator's post-soak call and still awaits the res.lease fencing wave, findings 13/14).

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/b6ef5fb3-88a7-4dab-8bad-058bc1d90e03/workers/worker-WMP-supervisor.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (edit ONLY `modules/07-model-gateway` + its tests; avoid `models.json` -- any change re-verifies M7 28/28):**
1. A **persistent supervisor process** launched DETACHED (e.g. `Start-GatewaySupervisor.ps1` + `Supervisor.psm1`)
   that creates a **Windows Job Object**, assigns every llama-server it starts to it (own the WHOLE tree,
   never kill-by-PID-alone), and exposes a **control channel** (named pipe / file-protocol control dir /
   loopback endpoint) so per-call gateway invocations request `Ensure-ResidentModel` / inference-routing /
   status from the RUNNING supervisor instead of spawning+killing their own server.
2. **Durability across invocations:** a fresh per-call gateway ATTACHES to the running supervisor and reuses
   the resident model (~1 ms, no respawn). This is the headline result vs the per-call Stage-1.1 path.
3. **Integrate `lib/PoolManager.psm1`** (fencing token + generation, `CanServe()`, the crash-atomic state
   machine, reconcile-on-startup under the machine-global mutex, verified socket-owner publish, GPU-handoff
   evict-before-grant) so the supervisor is the single owner running those transitions. Integrity invariants
   NON-bypassable; keep the `-BypassPoolManager` cold-isolated escape.
4. **Lifecycle:** start/stop/status; if the supervisor dies the Job Object reaps the whole tree
   (`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`); on restart RECONCILE the manifest as a claim to VERIFY. Name (do
   NOT build) the exec.watchdog #00.1 relaunch integration as a follow-on.
5. **Wedge discipline (D-0055/56):** supervisor + servers launch DETACHED; "0 orphaned llama-server" = 0
   UNMANAGED servers (the intended warm resident is NOT an orphan). Job Object via P/Invoke; own by HANDLE,
   not process-name (pwsh + executor both show as `dotnet.exe`).

**SCOPE OUT:** do NOT enable the pool by default; do NOT touch res.lease #29 (findings 13/14 = a separate
single-worker infra wave); do NOT touch #0 / #00.1 / any other module / any core-doc; no native `--models`
router, no `--slot-save-path`, no specialist. Pool STAYS DEFAULT-OFF; classic + D-0057 warm paths unchanged.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (the wedge; pwsh 7.4.6
  empty-array-unroll / array-double-wrap / `@()`-on-List / `$var:` gotchas; child-pipe-deadlock; trust the
  heartbeat, not the process list); + `WARM_POOL_DESIGN.md` sections 6+9+10 (section 10 residual (a) IS your
  spec) + `lib/PoolManager.psm1`; obey `SKILL_CONTRACT.md`.
- **Lease discipline (finding 14):** edit+test under the GIT lease, RELEASE git, then take the GPU lease ONLY
  for the live verify -- never hold the GPU idle waiting on git, never nest gpu-under-git. Reap via the Job
  Object before finalize; assert 0 UNMANAGED orphans.
- Gate off-machine FIRST (cloud pwsh 7.4.6 + mock/seam; Windows-only probes degrade to reported 'unknown',
  never throw). AST-parse every shipped `.ps1/.psm1`. `dev.ship` named `modules/07` files (FAIL-CLOSED; named
  files; trailers). Do ONE unit; `docs:[]`; report and let the orchestrator mirror core-docs.
- Report: `-Action report -PlanId fo-16-f125365c -WorkerId WMP-supervisor -State done -Summary "<one line>"`
  (`progress`/`blocked -Needs`/`failed` as needed). Negative results are first-class (D-0061 ethos).

## Verification

Required before "done": a **fault-injection suite** -- kill the supervisor mid-residency -> Job Object reaps
the whole tree (0 unmanaged orphans); restart -> reconcile (verify, not trust); **two separate gateway
invocations reuse the same resident server via the supervisor (the durable-across-invocations proof)**; a
forced fence/generation expiry mid-request REJECTED; GPU-handoff eviction frees VRAM. Live: real 3B<->9B
reuse (~1 ms) / swap (~1.6-4.1 s) / evict through the supervisor; Module 7 green (base 42/42 + warm 23/23 +
pool 48/48 + the new supervisor tests). Emit a **Verification Console `run_module`** item (two-invocation
warm reuse + a supervisor-kill tree-reap). Report which residual is CLOSED (finding 5 durable) vs still open
(findings 13/14 infra wave; the enable-by-default soak).

## Report-back record (ORCHESTRATOR fills from `plans/fo-16-f125365c/reports/` before archiving)

_(pending)_
