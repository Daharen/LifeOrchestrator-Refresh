# SUPERVISOR-HARDENING i23 -- SHIP STATE (D-0078)

**Wave:** fan-out iteration 23, plan `fo-23-36f97a35` (single-worker GPU). **Shipped:** `model.gateway` #7
0.5.0 -> **0.6.0**, commit **`d289ba9`** (HEAD verified via native git, D-0072). **Governing spec:**
`core-docs/research/2026-07-31-frontier-supervisor-redteam.md` (the i21 frontier red-team's 10 must-fixes).

## What shipped

The i21 frontier red-team's 10 MUST-FIXES folded into the DEFAULT-OFF durable Windows Job-Object gateway
supervisor + integrity layer + real evictor. ADDITIVE + default-off; the classic-cold + D-0057-warm
(non-supervisor) default paths are byte-for-byte unchanged. Files: `lib/Supervisor.psm1` (+531),
`Start-GatewaySupervisor.ps1`, `lib/PoolManager.psm1`, `lib/PoolEvictor.ps1`, `Invoke-ModelGateway.ps1`,
`skill.json` (0.6.0), NEW `tests/Invoke-ModelGatewayHardeningTests.ps1` (478), `Invoke-ModelGatewaySupervisorCoreTests.ps1`.

- **MF1+2 per-resident suspended-create Job custody + FATAL assignment** -- CreateProcess suspended ->
  AssignProcessToJobObject -> IsProcessInJob verify -> resume; no publish on `job_owned:false`; `tree_gone` =
  per-resident Job zero-members. **LIVE-PROVEN on the box** (real Job Objects, member-count, zero-members tree-gone).
- **MF3** lifetime supervisor singleton (named-mutex claim before publish).
- **MF4** authenticated exact-`resident_instance_id`-target-fenced IPC (path-containment + replay rejection +
  separated admin `shutdown`).
- **MF5** no launch after a failed/partial evict or a failed CAS.
- **MF6** abandonment-aware nonce'd pool lock (no live-owner stale-age steal).
- **MF7** hard pinned-`nvidia-smi` probe deadlines + `unmanaged_vram_pressure` (never a blind kill).
- **MF8** heartbeat-stale => UNRESPONSIVE with NO split-brain fallback (SAFETY half). NAMED residual: the
  exec.watchdog #00.1 -> supervisor relaunch DRIVER (availability half).
- **MF9** no manifest-only survivor adoption on restart.
- **MF10 (PARTIAL)** content-verify primitives + a fail-closed pre-launch hook. NAMED residuals: the ACL'd
  app-data state-dir move + the trusted expected-hash-manifest provisioning.

## Gates

366 off-machine + 74 on-box Windows real-custody green; `res.lease` 74/74 + 36/36 + 45/45 UNCHANGED (not
touched); 0 UNMANAGED orphans; leases dir empty; queue before == after; defaults byte-identical. Single-worker
wave, no producer/consumer schema pair -> no cross-module smoke required (D-0077 N/A).

## Consequence

**Finding 5 (durable Job-Object custody) is CLOSED / live-proven.** Warm-pool default-ON now gates on ONLY
(1) an **in-proc `res.lease` client** (the i21 ~6-9 child-pwsh-spawns/call finding) and (2) a **GROWN soak**
(>=24h, >=1000 transitions, >=25-each of the 5 fault classes + the 15 live tests + p99/max/handle-leak/
lock-hold/unmanaged-pressure metrics; the full real-model fault-injection sweep folds here).

## Frontier lane (as-built red-team)

An AS-BUILT supervisor red-team pack was emitted at fold: `frontier.bridge` pack **`ff24d3a4`** (10 files,
verified vs shipped HEAD `d289ba9`) -- the decisive design gate before the grown soak. **Answer PENDING**
`read-return`; it folds into a research digest and governs any i24 hardening-follow-on (the i19->i20 / i21->i23
analogue).
