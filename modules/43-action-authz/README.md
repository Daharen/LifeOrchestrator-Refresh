
---

## i38 FULL GATE (VERSION 0.2.0, worker P01-GATE-FULL-i38)

Extended from the i37 MVP to the full P0-1 gate against the 7 frozen red-team amendments
(`ACTION_AUTHORIZATION_CONTRACT.md` s6). Run: `python -X utf8 -B tests/run_suite.py`.

Result taxonomy (amendment 1): **build_status = build_complete | p0_1_gate_status = pass |
activation_status = prohibited** (`non_execution:true` holds; nothing action-capable).

- Suite 204/204; **67/67 mandatory mutations killed** (M-A01..M-E36 + M-R11); all 10 fixture families;
  fixed-seed fuzzer (400 iterations, 0 violations); oracle matrix 67 rows; double-run byte-identical.
- Executor TOCTOU order corrected (claim -> recheck -> re-resolve-after-claim -> bind); completion scope
  binding; R-1 router-diagnostic isolation (M-R11); split Blocker 9 (constant bytes + no step oracle).
- Real #40 chain: 4/4 authentic 0.7.0 packets -> deterministic A06 DENY; 0.8.0 router carrier proven inert.
- ONE canonical implementation (`canon.py`), cross-validated byte-equivalent to an independent second
  implementation (`p01gate`) over parse/serialize/digest/ns (Blocker-8 differential check).

Still staged to ACTIVATION (recorded, not attempted): Blockers 3/4/6/7 + the activation portions of 5/9
(production Windows permit-store IPC/ACL/crash, per-tool OS profiles, freshness relaxation, the
`non_execution` activation transition, production status/log ownership). Activation additionally requires
the separate Blocker-7 decision and stays prohibited regardless of gate status.
