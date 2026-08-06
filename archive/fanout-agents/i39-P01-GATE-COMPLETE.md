# FANOUT_AGENT_001 -- READY

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i39 (plan `fo-39-df2e3a67`)
- **Lane:** CODING (CPU)
- **Worker id / label:** `P01-GATE-COMPLETE-i39` -- action.authz #43 0.2.0 -> 0.3.0: complete the P0-1 gate to a TRUE pass
- **Module/area (exclusive):** `modules/43-action-authz` (ONLY)
- **GPU:** false
- **Docs:** `[]`
- **Convenience copy of the full emitted prompt:** `modules/30-orchestrate-fanout/runtime/artifacts/2fcdbfb0-ff94-48d2-9d81-dc0d028a0212/workers/worker-P01-GATE-COMPLETE-i39.prompt.md`

## Mission
i38 shipped #43 0.2.0 and reported `p0_1_gate_status=pass`, but the couriered AS-BUILT re-review returned **FAIL -- over-claimed** and the gate was walked back to `incomplete` (D-0107). `build_status=build_complete` + `activation_status=prohibited` are UNCHANGED and deny-by-default still holds. Close the **7 as-built findings** so the gate reaches an HONEST pass. Any of Findings 1-4 alone blocks the pass. `non_execution:true` holds throughout; nothing becomes action-capable; A06 must still deny every authentic packet.

## Unit (self-contained; the exact per-finding closure is in the red-team doc you MUST read)
EXCLUSIVE to `modules/43-action-authz`; `docs:[]`; CPU; pure Python **standard library only**; deterministic; integer-only JSON; DOUBLE-RUN byte-identical on every canonical-bytes path. EXTEND the 0.2.0 build -> 0.3.0.

**READ FIRST (governing, do not edit):** `research/2026-08-06-i38-p01gate-asbuilt-redteam.md` (**THE 7 FINDINGS + the exact closure per finding -- this is your spec**) + `core-docs/ACTION_AUTHORIZATION_CONTRACT.md` (s6 the 7 amendments, s7 the D-0107 fold-block, s1-s5 schemas/algorithm, s8 acceptance) + `research/2026-08-05-i37-action-authz-freeze-redteam.md` + `research/2026-08-05-i36-action-authz-freeze-frontier.md` + your OWN `modules/43-action-authz` + its `SCHEMA_NOTES.md` + `tests/oracle_matrix.py` + `tests/integration.py` + `tests/run_suite.py` + `action_authz/boundary.py`.

**BUILD (each maps to red-team Finding N):**
1. **Obligation oracle matrix** (blocks pass). Expand `tests/oracle_matrix.py` from one-row-per-mutation (67) to one row per OBLIGATION: every A01-A36, Boundary A1-A7 / B1-B4 / C1-C6 / D1-D8, U-AUTHORITY/SCOPE/ROLE/EFFECT, AND every mutation. Fields: `{obligation_id, fixture_id, mutant_or_fault_id, baseline_expected, observable_surface, independent_oracle, expected_fault_difference}`. Separate independent observable per obligation; A35/A36 inspect their OWN surfaces; `no_path` needs an unforgeable authority-constructor capability AND import/call-graph reachability. Mark each pass|fail|not_run; ANY not_run -> gate incomplete. WIRE completeness into `run_suite.py` as a GATING criterion.
2. **Real #40 0.9.0 authentic chain in the suite** (blocks pass). Capture a REAL #40 0.9.0 ROUTED + working-memory-hydrated packet (commit under `fixtures/real_packets/`) and run TWO modes in `integration.py`: (a) authentic `non_execution=true` -> A06 DENY + constant bytes + no permit + no diff; (b) a TEST-ONLY `non_execution=false` variant preserving the real trace/wm/state_version/evidence/identity that REACHES A09/A11/A30/A31 + completion. Add adversarial authority-shaped/role-confusing variants with valid boundaries. The SUITE must own+run it before `pass`.
3. **Byte-exact test-facing views** (blocks pass). Write the closed contracts BYTE-EXACTLY in `SCHEMA_NOTES.md` (or a digest-referenced sibling): `lifeorch.grant_view/policy_view/approval_view/status_view/validator_view 0.1-test` -- field types, canonical serialization, immutable identity+digest, epoch/currentness, revocation/supersession, ordered matching algorithm, conjunction-vs-alternative, target-predicate algebra, limit intersection, conflict behavior, closed matcher output, malformed/unknown/ambiguous -> deny|indeterminate. Pin the source digest + independent golden vectors.
4. **Completion binds via `packet_id`** (blocks pass). Bind completion through the immutable `packet_id` -> exact permit-time `completion_contract_id/version/digest`; NO current-contract-by-task lookup. Add `completion_scope` (task|action|permit|object) + the per-leaf-kind minimum-scope table + substitution fixtures (cross-action/permit/object, old-contract-vs-new-packet, mismatching content, omitted bindings, wrong validator version, superseded status). Make M-E36 decidable.
5. **Boundary D -- ALL mutable epochs.** After the atomic claim re-read grant/approval/policy/manifest+artifact/health/permit-revocation+store-epoch/packet+status-currentness/resolver-snapshot; re-resolve targets AFTER claim; bind + consume a captured UNFORGEABLE stable handle (never re-resolve the name); verify before first effect else `rejected_no_effect` + terminal permit + EMPTY effect ledger. Add a post-claim mutation per epoch. Real Windows handle/reparse/crash race-freedom stays activation-gating (record).
6. **R1-ROLE-1 sink matrix.** Turn M-R11 into a parameterized sink matrix over EVERY sink: diagnostic + working-memory -> evidence / evidence_requirement / coverage_result / packet_disposition / control_plane / grant/policy/approval/health / TrustedStatus / completion / target / effect. RUN under the test-only `non_execution=false` path so A31 + completion are REACHED. Kill every sink.
7. **Independently-auditable evidence bundle.** Emit (under e.g. `tests/report/`) the machine-readable report (both runs) + oracle matrix + fixture manifest with per-fixture canonical hashes + family map + mutation source/patches + integration source + tree/report digests + the independent `p01gate` impl source+provenance. (The orchestrator adds the fold report + packet hashes and bundles this into the frontier re-review pack.)

**FLIP:** set `p0_1_gate_status = pass` ONLY when every obligation AND mutation oracle is green with NO not_run, the 0.9.0 chain (both modes) runs in-suite, views are byte-exact with golden vectors, completion binds via `packet_id`, Boundary D covers all epochs, and every R1-ROLE-1 sink is killed. **An honest INCOMPLETE beats a false PASS.** If any mandatory element can't be completed, leave it incomplete and say so.

**CONSTRAINTS.** Do NOT modify #36/#37/#40/#42 or any core-doc. Do NOT reopen/widen any frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT field (all additive action-layer). Do NOT freeze/disposition a Blocker or edit the contract -- the orchestrator re-ratifies s7 + pins the views + flips the taxonomy at fold.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order (this unit: **git** only); release on exit/abort.
- Do ONE unit; never touch modules/areas outside `modules/43-action-authz`; `docs:[]`.
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-39-df2e3a67 -WorkerId P01-GATE-COMPLETE-i39 -State done` + a plain measured summary (negative results are first-class).

## Verification
Full result taxonomy (build_status / p0_1_gate_status / activation_status); suite NN/NN; the FULL obligation-oracle coverage (every A-check/boundary/U-property/mutation pass|fail|not_run); the 0.9.0 authentic-chain result BOTH modes; the byte-exact views digest + golden vectors; the completion-by-`packet_id` proof; the all-epochs Boundary-D proof; the R1-ROLE-1 sink-matrix kills; double-run byte-identity; the evidence-bundle paths; a plain PASS/INCOMPLETE statement + why.

## Report-back record (ORCHESTRATOR fills from `plans/fo-39-df2e3a67/reports/` before archiving)
_pending._
