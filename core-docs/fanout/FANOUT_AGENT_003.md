# FANOUT_AGENT_003 -- READY (i40 Lane A: P01-EXACT-CLOSURE-43-i40)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i40 (plan id `fo-40-d42fd1ac`)
- **Lane:** CODING (CPU)
- **Worker id / label:** `P01-EXACT-CLOSURE-43-i40` -- action.authz #43 0.3.0->0.4.0: the 7 D-0109 exact closures
- **Module/area (exclusive):** `modules/43-action-authz`
- **GPU:** false
- **Docs:** `[]`

## Mission (2-4 lines)

Build the 7 EXACT CLOSURES from the i39 frontier as-built re-review of the P0-1 deny-by-default gate
(`research/2026-08-06-i39-p01gate-recheck-redteam.md`, D-0109) -- to the letter of each per-finding
"Exact closure" block. The gate has been over-claimed twice (D-0107, D-0109); under mandate-02 M2-D the worker
does NOT claim pass: the independent frontier re-review, couriered at fold, is the only path to ratification.

## Unit

**EXECUTE VERBATIM the emitted worker prompt at:**
`modules/30-orchestrate-fanout/runtime/artifacts/73041f89-714b-4112-8a70-919ffe77be82/workers/worker-P01-EXACT-CLOSURE-43-i40.prompt.md`
(11.4 KB -- the complete instruction: the 7 exact closures, the gate-status rule, constraints, gates, report format.
It exceeds this slot's 8 KB budget, so the emitted file is the authoritative copy; Nicholas also receives it as a
chat file at dispatch.) Condensed map of the 7 closures (the prompt + the review doc govern; numbers = the review's
Finding numbers):

1. Completion IMMUTABLE at issue: cc.packet_id present + == permit.packet_id; issue-time binding present + id/version/digest match; immutable NO_COMPLETION_CONTRACT sentinel; late-insertion / missing-field / deleted-binding / changed-binding vectors.
2. Boundary-D POST-claim fault hook: one fault per independent mutable surface (incl. matched-grant revocation + approval expiry); every row accepted==false + state_diff==[] + permit_state==rejected_no_effect (terminal) + 2nd attempt rejected; issue snapshot MANDATORY; captured target = a trusted HANDLE OBJECT the effect ledger CONSUMES; mutation before AND after claim.
3. Role matrix over ALL 15 frozen R1-ROLE-1 sinks (add manifest + working_memory; wm->wm prohibited conversion defined precisely; defects sink-isolated + separately observable).
4. GrantView limit algebra IMPLEMENTED + pinned: effective_limit = min(manifest ceiling, conjunctive grant max_quantity AND limits[], policy, approval); ordered matching algorithm + closed result shape AS DATA; A23 multi-source; 8 golden-vector classes; if the FROZEN intersection rule itself would need changing -> STOP + report (orchestrator-owned).
5. Suite-owned EXACT context_packet/0.2 adapter: all identity-covered fields + grant-snapshot identity + full routed trace / wm envelopes / evidence / provenance / ns metadata / state_version preserved; corpus_version preserved (A07 EXERCISED); overlay flips ONLY non_execution; benign + adversarial 0.9.0 through the exact seam; inertness at EVERY R1 sink.
6. Decisive oracles: no_path via a stdlib-ast CALL GRAPH over every module (boundary/stores/schemas included) + capability instrumentation; A36 = exactly one correctly-shaped bounded audit event + no attacker payload + deletion/corruption faults; Boundary-B real-render mutation observed on rendered bytes OR explicitly reclassified non-decisive; independent surfaces paired per A-check where feasible.
7. COMPLETE independently-runnable review tree (all package + test files incl. __init__.py and tests/{harness,fixtures_suite,properties,fuzzer,report}, all 0.7.0 + 0.9.0 packet fixtures, report bundle, oracle_matrix / fixture_manifest / mutation_defs / source_digests / MANIFEST) -- SELF-VERIFIED from an EMPTY temp dir before shipping (exit 0; suite + oracle rows + digests reproduced; byte-identical report manifest; transcript committed).

**THE GATE-STATUS RULE (M2-D, D-0110 -- non-negotiable):** `p0_1_gate_status` stays **`incomplete`** in EVERY
artifact you emit (runner output, SCHEMA_NOTES, report JSON, status fields). Your claim is carried by per-finding
`exact_closure_built: true|false` flags + the suite evidence. The orchestrator ratifies contract s7 ONLY when the
independent as-built re-review returns PASS. An honest incomplete-with-evidence IS the deliverable.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Leases in **gpu -> git -> doc** order (this unit: `git` only); holder `P01-EXACT-CLOSURE-43-i40`, TTL 1800, wait 900; release on exit.
- Do ONE unit; EXCLUSIVE to `modules/43-action-authz`; do NOT modify #36/#37/#40/#42 or any core-doc (`docs:[]`); no frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT field reopened.
- Pure Python stdlib; deterministic; integer-only JSON; DOUBLE-RUN byte-identical on every canonical-bytes path; `non_execution:true` holds; A06 still denies every authentic packet; nothing action-capable.
- Gate off-machine first (cloud python), then `exec-job.sh devship` (module modules/43-action-authz; FAIL-CLOSED; named files only; trailers). VERIFY real HEAD via native git (D-0072). Assert 0 orphans.
- Report: `-Action report -PlanId fo-40-d42fd1ac -WorkerId P01-EXACT-CLOSURE-43-i40 -State done -Summary "..."` (+ plain summary; negative/partial results first-class).

## Verification

Suite NN/NN + oracle-matrix coverage with not_run count; per-finding exact_closure_built flags + evidence pointers; the Finding-7 empty-dir self-verification transcript; double-run byte-identity; emitted taxonomy `build_complete / p0_1_gate_status=incomplete / activation prohibited`. At fold the orchestrator runs fold-i40 (real #40 0.9.0 routed+wm + adversarial -> A06 DENY chain) + an independent run_suite + i34 38/38, then couriers the frontier re-review pack.

## Report-back record (ORCHESTRATOR fills from `plans/fo-40-d42fd1ac/reports/` before archiving)

_(empty until fold)_
