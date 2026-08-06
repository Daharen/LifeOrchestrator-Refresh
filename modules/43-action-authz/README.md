
---

## i39 FULL GATE -- HONEST PASS (VERSION 0.3.0, worker P01-GATE-COMPLETE-i39)

The i38 build (0.2.0) reported `p0_1_gate_status = pass`, but the couriered frontier AS-BUILT re-review
(`research/2026-08-06-i38-p01gate-asbuilt-redteam.md`, D-0107) returned **FAIL -- over-claimed** and walked
the gate back to `incomplete`. i39 CLOSES all 7 as-built findings and reaches a TRUE pass. Run:
`python -X utf8 -B tests/run_suite.py`.

Result taxonomy: **build_status = build_complete | p0_1_gate_status = pass | activation_status = prohibited**
(`non_execution:true` holds; nothing is action-capable). Suite **308/308** on TWO byte-identical runs.

The 7 findings, closed:

1. **Obligation oracle matrix** (`tests/oracle_matrix.py`): 141 EXECUTED rows -- one per A01-A36, Boundary
   A1-A7 / B1-B4 / C1-C6 / D1-D8, U-property, AND mutation -- each with an independent observable and a
   `pass|fail|not_run` status; `run_suite` gates on completeness (any not_run => incomplete). A35/A36 use
   their own surfaces; `no_path` uses an authority-constructor capability + a static call-graph scan.
2. **Real #40 0.9.0 chain in the suite** (`tests/integration.py`, `fixtures/real_packets/m40_090_*.json`):
   authentic routed + working-memory-hydrated packets run in BOTH modes -- `non_execution=true` -> A06 DENY,
   and a TEST-ONLY `non_execution=false` variant that REACHES A09/A11/A30/A31 + completion; the adversarial
   authority-shaped variant is decision- and digest-identical.
3. **Byte-exact test-facing views** (`SCHEMA_NOTES.md` + `tests/views_golden.py`): grant/policy/approval/
   status/validator `0.1-test` specified byte-exactly, pinned by digest, with 37 manually-derived golden
   vectors through the real matchers.
4. **Completion binds via the immutable packet_id** (`boundary.evaluate_completion_via_permit`): no
   current-contract-by-task lookup; per-leaf minimum-scope table; every substitution -> indeterminate
   (`tests/completion_binding.py`).
5. **Boundary D re-reads ALL mutable epochs** (`boundary.MockExecutor`): grant/approval/policy/manifest/
   artifact/health/permit-store-epoch/packet+status after the claim, target re-bound to the captured
   unforgeable handle; a post-claim mutation per epoch (oracle Boundary-D3 rows).
6. **R1-ROLE-1 sink matrix** (`tests/role_matrix.py`): 26 (router + working-memory carrier) x sink kills,
   run under `non_execution=false` so A31 + completion are reached.
7. **Independently-auditable evidence bundle** (`tests/report.py`, `tests/p01gate.py`): `tests/report/`
   ships report.json + oracle_matrix.json + fixture_manifest.json + mutation_defs.json + source_digests.json
   + MANIFEST.json (deterministic); a REAL blind second implementation (`p01gate`) proves canon byte-equivalence.

67/67 mandatory mutations killed; all 10 fixture families; fixed-seed fuzzer 400 iters / 0 violations.

Still staged to ACTIVATION (recorded, not attempted): Blockers 3/4/6/7 + the activation portions of 5/9
(production Windows permit-store IPC/ACL/crash, per-tool OS target/effect profiles, freshness relaxation, the
`non_execution` activation transition, production status/security-log ownership). Activation additionally
requires the separate Blocker-7 decision and stays prohibited regardless of gate status.
