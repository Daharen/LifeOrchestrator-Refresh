
---

## i40 EXACT CLOSURES (VERSION 0.4.0, worker P01-EXACT-CLOSURE-43-i40)

The i39 build (0.3.0) reported `p0_1_gate_status = pass`, but the couriered frontier AS-BUILT RE-REVIEW
(`research/2026-08-06-i39-p01gate-recheck-redteam.md`, D-0109) returned **FAIL -- over-claimed** (the gate
has now been over-claimed TWICE: D-0107, D-0109) and walked it back to `incomplete`. i40 builds the 7
per-finding EXACT CLOSURES from that re-review, to the letter of each "Exact closure" block. Run:
`python -X utf8 -B tests/run_suite.py` then `python -X utf8 -B tests/selfverify.py`.

**The gate-status rule (M2-D, D-0110 -- non-negotiable).** The worker does NOT claim pass. The result
taxonomy stays **build_status = build_complete | p0_1_gate_status = `incomplete` | activation_status =
prohibited** in EVERY emitted artifact. The claim is carried by per-finding `exact_closure_built:
true|false` flags + the suite evidence; the orchestrator ratifies contract s7 ONLY when the independent
as-built RE-REVIEW returns PASS. An honest incomplete-with-evidence IS the deliverable. Suite **334/334**
on TWO byte-identical runs; **149** obligation rows; **30** role-sink kills; **7/7** exact closures built.

The 7 exact closures (i39 finding numbering):

1. **Completion IMMUTABLE at issue** (`boundary.evaluate_completion_via_permit`, `stores.py`): the
   issue-time binding is MANDATORY (fail-closed if absent); `cc.packet_id` must be PRESENT and ==
   `permit.packet_id`; a permit issued with NO contract records the immutable `NO_COMPLETION_CONTRACT`
   sentinel and can NEVER become completable via a later contract insertion. New vectors: late insertion,
   missing packet_id, deleted binding, sentinel, binding-changed-after-issue (`tests/completion_binding.py`).
2. **Boundary-D POST-claim hook** (`boundary.MockExecutor`): a deterministic hook fires in the window AFTER
   the atomic claim and BEFORE each recheck; one fault per independent mutable surface (14, incl.
   matched-grant revocation + approval EXPIRY as its own row); every row requires `accepted==false AND
   state_diff==[] AND permit_state==rejected_no_effect (TERMINAL) AND a 2nd attempt rejected`; the issue
   snapshot is MANDATORY; the effect ledger CONSUMES the captured target handle (never a blind
   authorized_effect_set copy); target mutation tested BOTH before and after claim.
3. **Role matrix = ALL 15 frozen sinks** (`tests/role_matrix.py`, `monitor.py`): adds `manifest` (A12/A32
   installed-drift bypass) and `working_memory` (A05 task-binding bypass) -> 15 sinks x 2 carriers = **30**
   killed pairs; each defect modifies ONLY its sink and is separately observable.
4. **GrantView limit algebra IMPLEMENTED + pinned** (`stores.GrantSnapshot.match` + `effective_permit_limits`):
   the matcher READS `limits[]` AND `max_quantity` (min), returns a CLOSED result
   `(matched_grant_ids, ok, effective_grant_limits)`; A23 intersects manifest ∩ grant (∩ policy/approval);
   the ordered algorithm + result shape are pinned AS DATA; 8 golden-vector classes (`tests/views_golden.py`).
   The FROZEN MIN intersection rule is UNCHANGED (implemented, not amended).
5. **Suite-owned EXACT context_packet/0.2 adapter** (`tests/adapter_090.py`): preserves corpus_version (A07
   EXERCISED -- the `current_corpus_version=None` bypass is gone), the packet's grant-snapshot identity, and
   the full routed trace / wm envelope+items / evidence / ns metadata / state_version as DATA (the
   two-boolean reduction is retired); the overlay flips ONLY `non_execution`; carriers proven INERT at
   EVERY R1 sink through the exact seam (`tests/integration.py`).
6. **Decisive oracles** (`tests/callgraph.py`, `tests/render.py`, `monitor.py`): `no_path` is a real
   stdlib-ast import/CALL-GRAPH over EVERY action_authz module (boundary/stores/schemas included) proving
   `canon.authority_construct` unreachable + an AST-verified guard; A36 asserts EXACTLY ONE correctly-shaped
   bounded audit event with audit-emission DELETION + CORRUPTION faults; Boundary-B rows mutate the ACTUAL
   render path and observe rendered-bytes/order/delimiter deltas (defense-in-depth; C decisive).
7. **Complete runnable review tree + empty-dir self-verify** (`tests/selfverify.py`): the pack contains ALL
   package + test + fixture + report files; extracted into an EMPTY temp dir the documented command exits 0,
   reproduces the suite + all 149 oracle rows + source/fixture digests + a BYTE-IDENTICAL report MANIFEST;
   the transcript is committed at `tests/report/self_verify.json`.

Still staged to ACTIVATION (unchanged): Blockers 3/4/6/7 + the activation portions of 5/9. `non_execution:true`
holds throughout; A06 denies every authentic packet; nothing is action-capable.

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
