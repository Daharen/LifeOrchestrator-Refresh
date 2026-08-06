# i38 P0-1 action-authorization FULL-gate AS-BUILT red-team -- couriered frontier answer (pack 24190087)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match, captured/valid); D-0052 human-courier lane. DESIGN ONLY -- `non_execution:true` holds; this changes no shipped memory/packet field and enables no execution. **Verdict: FAIL -- `p0_1_gate_status=pass` is OVER-CLAIMED; the honest status is `incomplete`.** `build_status=build_complete` + `activation_status=prohibited` are UNCHANGED, and deny-by-default HOLDS (the orchestrator D-0077 fold 18/18 + the independent #43 suite re-run stand; A06 denies every authentic packet; nothing is action-capable). The 7 findings below are the i39 path to a TRUE pass; folded into `ACTION_AUTHORIZATION_CONTRACT.md` section 7 (D-0107). Companion: the i37 freeze red-team `research/2026-08-05-i37-action-authz-freeze-redteam.md`.

---

# P0-1 Action-Authorization Full-Gate As-Built Red-Team

## Verdict: FAIL — `p0_1_gate_status=pass` is over-claimed

Keep:

```text
build_status = build_complete
activation_status = prohibited
```

Change:

```text
p0_1_gate_status = incomplete
```

The underlying design remains strong, and the i38 build appears to have closed much of the i37 gap. This is not a rejection of the architecture or the build. It is a rejection of the **full-gate pass claim**.

The supplied as-built record does not fully implement several frozen section-6 requirements:

1. the oracle matrix covers mutations only, not every A-check, boundary obligation, U-property, and mutation;
2. the suite’s real integration remains on #40 0.7.0 rather than the current routed and working-memory-hydrated 0.9.0 producer path;
3. the supposedly byte-exact test-facing authority views are not actually specified byte-exactly in `SCHEMA_NOTES.md`;
4. completion remains documented as selected through the packet’s **task**, rather than immutably through its exact `packet_id`;
5. the executor recheck list is narrower than the frozen “all mutable epochs” requirement;
6. M-R11 tests one diagnostic sink, while R1-ROLE-1 prohibits many distinct role-conversion sinks; and
7. the pack contains summaries of test results, but not the implementation, oracle matrix, fixture corpus, mutation definitions, or machine-readable report needed to independently verify the claimed 204/204 result despite expressly asking the reviewer not to take it on trust.

Any one of Findings 1–4 is enough to prevent a full gate pass.

---

## Ranked Finding 1 — The oracle-matrix amendment was not implemented at its frozen scope

### Hole

The frozen amendment requires:

> One row per A-check, boundary obligation, U-property, and M-mutation.

It also specifically requires:

* an independent observable for each obligation;
* an unforgeable authority-constructor capability;
* import/call-graph inspection for `no_path`;
* A35 verification through the privileged disclosure surface;
* A36 verification through the audit surface; and
* no reliance on check-trace presence as proof.

The as-built documentation instead says:

> `tests/oracle_matrix.py` commits one row per mandatory mutation.

It reports exactly 67 rows—the same number as the 67 mandatory mutations.

That cannot simultaneously be one row per:

* A01–A36;
* Boundary A/B/C/D obligations;
* four U-properties; and
* 67 mutations.

Even before counting the individual boundary sub-obligations, the required set is substantially larger than 67.

### Why this matters

A mutation-kill oracle and an obligation oracle are not interchangeable.

For example:

* deleting A35 may leave the authorization decision unchanged while disclosing a permit through the wrong channel;
* deleting A36 may leave the decision unchanged while omitting or corrupting the privileged audit event;
* a `no_path` property cannot be established merely because M-A07 failed to obtain a permit in one runtime fixture;
* A08 and A30 may affect later trusted state rather than the immediate final decision;
* U-EFFECT needs an effect ledger independent of executor-produced status.

A suite can kill all 67 seeded mutants yet still lack an independent assertion for one of the frozen checks or structural properties.

### Exact closure

Expand `oracle_matrix.py` to contain separately identified rows for:

```text
A01-A36
Boundary A1-A7
Boundary B1-B4
Boundary C1-C6
Boundary D1-D8
U-AUTHORITY
U-SCOPE
U-ROLE
U-EFFECT
M-A01 through M-R11 / M-E36
```

Each row must name:

```text
obligation_id
fixture_id
mutant_or_fault_id
baseline_expected
observable_surface
independent_oracle
expected_fault_difference
```

For A35 and A36, inspect their own surfaces:

* privileged executor channel;
* ordinary caller channel;
* privileged security log.

For `no_path`, include both:

1. authority-constructor capability/event instrumentation; and
2. deterministic import/call-graph reachability inspection.

The suite report must mark every frozen obligation `pass | fail | not_run`; any `not_run` yields `p0_1_gate_status=incomplete`.

### Classification

**SUITE-BUILD fix required before pass.**

No additional freeze amendment is needed; section 6 already specifies the correct requirement.

---

## Ranked Finding 2 — The current real #40 producer path is not inside the suite gate

### Hole

The README and schema notes state that the suite’s real chain consists of four authentic **#40 0.7.0** packets. The notes merely recommend capturing an authentic routed packet later and rely on a synthetic F3b/M-R11 carrier for the router feature.
The actual current seam is #40 0.9.0, which adds:

* routed stage traces;
* working-memory hydration;
* `state_version` in packet identity; and
* new packet-visible carrier structures.

The orchestrator did run a 0.9.0 fold, but every monitor case denied at A06 because the authentic packet retained `non_execution:true`. That proves:

* authentic packet lookup works;
* A06 cannot be overridden by authority-shaped working-memory text;
* the caller receives constant denial;
* no permit or effect occurs.

It does **not** prove what happens at:

* A09 authority-snapshot isolation;
* A11 namespace closure;
* A30 completion isolation;
* A31 evidence-dependency and packet-disposition handling;
* completion evaluation; or
* target/effect derivation.

A06 short-circuits before those obligations.

### Why 0.7.0 byte identity is insufficient

The claim that 0.8.0 or 0.9.0 **flat** compiles are byte-identical to 0.7.0 only validates the flat path. It says nothing about the new routed and hydrated path, which is the path introducing the exact attack carriers under review.

The frozen gate requires producer-to-consumer tests over real #36/#37/#40 outputs, not merely synthetic representations of later fields. The current producer version and current non-flat output shape are therefore load-bearing.

### Exact closure

Bake a real #40 0.9.0 routed and working-memory-hydrated artifact into `tests/integration.py`.

Run at least two modes:

1. **Authentic production-state packet**

   ```text
   non_execution=true
   expected: A06 deny
   constant caller bytes
   no permit
   no state diff
   ```

2. **Explicit TEST-ONLY authority variant**

   Preserve the real compiler-produced:

   * routing trace;
   * working-memory region;
   * state version;
   * evidence and coverage structures;
   * packet identity inputs.

   Change only the trusted test authority state needed to set `non_execution=false`, using the already authorized test-only mechanism. Then allow execution to reach A09/A11/A30/A31 and the completion evaluator.

Add adversarial cases where real 0.9.0 structures contain authority-shaped or role-confusing data, while preserving structurally valid packet boundaries.

The orchestrator fold may remain as an additional cross-module smoke, but the suite must own and run the current authentic-chain fixture before emitting `pass`.

### Classification

**SUITE-BUILD fix required before pass.**

---

## Ranked Finding 3 — The test-facing views are named, not frozen byte-exactly

### Hole

The frozen amendment requires exact test-facing definitions for:

* `GrantView`;
* `PolicyView`;
* `ApprovalView`; and
* status/validator views.

For grants and policies, the frozen language specifically requires:

* field types and canonicalization;
* validity and revocation;
* exact tool and operation matching;
* target-predicate semantics;
* namespace semantics;
* effect and externality matching;
* quantitative limit intersection;
* risk and approval escalation;
* conjunction versus alternative rules; and
* complete matcher output.

The as-built `SCHEMA_NOTES.md` does not provide those definitions. It says only:

```text
GrantView (GrantSnapshot) + PolicyView consumed by A26/A27
ApprovalStore + approval fixtures
mock structured executor status + mock validator/status store
```

Its full-gate section then points to `stores.py` rather than reproducing or digest-pinning the closed interfaces.

Consequently, the claim that these views are “recorded byte-exactly in `SCHEMA_NOTES.md`” is not supported by the bundled `SCHEMA_NOTES.md`.

### Decidability failure

Without a frozen matching language, two implementations can disagree about:

* whether grants are alternatives or conjuncts;
* whether scopes from different grants may be combined;
* whether one grant may provide target authority while another provides effect authority;
* target-predicate intersection;
* limit minima;
* empty grant arrays;
* epoch and revocation comparison;
* policy conflicts;
* approval reuse; and
* status supersession.

Both implementations could pass tests generated from their own assumptions.

The use of one implementation inside #43 prevents runtime differential behavior within that module, but it does not make the contract independently decidable. It merely makes the implementation self-consistent.

### Exact closure

Place the complete closed test-view contracts in a frozen artifact, preferably `SCHEMA_NOTES.md` or a named sibling contract referenced by digest.

At minimum, define:

```text
lifeorch.grant_view/0.1-test
lifeorch.policy_view/0.1-test
lifeorch.approval_view/0.1-test
lifeorch.status_view/0.1-test
lifeorch.validator_view/0.1-test
```

Include:

* exact field lists and types;
* canonical serialization;
* immutable identity and digest;
* epoch/currentness rules;
* revocation and supersession;
* matching algorithm in ordered deterministic steps;
* conjunction/alternative semantics;
* target-predicate algebra;
* limit intersection;
* conflict behavior;
* closed matcher result; and
* malformed/unknown/ambiguous → deny or indeterminate rules.

Pin the implementing source digest and include independent golden vectors whose expected results are manually or separately derived.

Production storage formats may remain activation-gating if they must prove exact conversion or byte-equivalence to these views.

### Classification

**SUITE-BUILD fix required before pass.**

The necessary freeze amendment already exists; the fix is conformance to it.

---

## Ranked Finding 4 — Completion binding still has the task-level substitution hole

### Hole

The frozen amendment requires two independent things:

1. `completion_scope = task | action | permit | object`, with minimum scope rules by leaf kind; and
2. the completion contract must be bound through either:

   * explicit permit fields, or
   * the authentic immutable `packet_id`.

It expressly says executor-status and state-diff leaves may not be task-only.

The as-built notes instead say:

> Completion leaves are bound to their subject … and the contract is selected by the authentic packet’s **task**.

They further describe M-E36 as testing status from another “task/action,” without documenting permit, object, validator-version, or contract-substitution cases.

Selecting a contract by `task_id` is not equivalent to selecting the exact contract embedded in or referenced by the authentic `packet_id`.

A task may have:

* multiple packets;
* a superseded completion contract;
* a new grant snapshot;
* multiple actions or permits; or
* changed object expectations.

A completion evaluator that asks “what is the current contract for this task?” can substitute a later contract for the one under which the action was authorized.

### Task-only scope

The notes do not include a closed leaf-kind/minimum-scope table.

Thus, “bound to their subject” remains compatible with:

```text
executor_status:
  completion_scope = task
```

That would allow status from one action or permit to satisfy another action under the same task unless another undocumented check happens to reject it.

### Exact closure

Normatively bind completion through the exact packet:

```text
permit.packet_id
    -> immutable trusted packet
    -> exact completion_contract_id/version/digest
```

The completion evaluator must not perform an independent current-contract lookup by task.

Define the minimum scope matrix, for example:

| Leaf kind         | Minimum binding                          |
| ----------------- | ---------------------------------------- |
| `executor_status` | permit                                   |
| `state_diff`      | permit + canonical action                |
| `artifact_hash`   | object; action/permit if action-produced |
| `test_suite`      | action or object, as declared            |
| `object_state`    | object                                   |
| `human_approval`  | exact approval reference                 |
| `postcondition`   | action or permit                         |

Add explicit fixtures for:

* same task, different action;
* same task/action, different permit;
* wrong object under the same task;
* old completion contract versus new packet;
* same packet id claim with mismatching packet content;
* omitted required action/permit/object bindings;
* wrong validator version;
* superseded or revoked status;
* status valid under another completion contract.

### Classification

**SUITE-BUILD fix required before pass.**

No MEMORY_CONTRACT or CONTEXT_PACKET_CONTRACT field must be reopened. The existing packet identity can be used.

---

## Ranked Finding 5 — Boundary D closes the modeled target race, but not all frozen executor-side races

### Hole

The corrected sequence is directionally right:

```text
verify permit
atomic claim
re-read mutable epochs
re-resolve targets after claim
bind stable identity
verify before first effect
```

The as-built notes, however, identify the reread set only as:

```text
manifest / artifact / revocation
```

The frozen amendment requires rereading **all mutable epochs**, including:

* grant;
* approval;
* side-effect policy;
* manifest and installed artifact;
* health;
* permit revocation/store epoch;
* relevant packet or status currentness; and
* any mutable resolver snapshot on which target identity depends.

The M-E29 post-claim-drift kill proves one modeled target-substitution case. It does not prove:

* grant revoked after claim;
* approval revoked after claim;
* policy tightened after claim;
* tool health changes after claim;
* manifest registry epoch changes;
* permit-store epoch changes;
* target changes after the final verification but before effect; or
* a purported “canonical identity” is actually a stable handle rather than a re-resolvable name.

### Sound claim

The current evidence supports:

> The mock closes the modeled post-claim target-substitution mutation.

It does not support:

> Boundary D is race-free.

Actual race freedom on Windows depends on per-operation stable-handle semantics and the real permit store, both properly staged to activation.

### Exact closure before the logical gate passes

In the mock boundary, model and test every frozen mutable dependency after claim.

Add mutations for post-claim:

* grant revocation;
* approval revocation;
* policy escalation;
* manifest/artifact replacement;
* health transition;
* permit/store epoch transition;
* packet/status invalidation; and
* resolver snapshot drift.

Require `rejected_no_effect`, terminal non-reusable permit state, and an empty independent effect ledger.

Document whether the mock’s “stable handle” is an unforgeable object captured at resolution or merely a string identifier. The executor must consume the captured handle itself, not resolve the name again during effect execution.

### Activation remainder

The following correctly remain activation-gating:

* Windows handle and reparse semantics;
* filesystem, registry, recipient, and redirect profiles;
* real CAS/IPC/ACL behavior;
* crash recovery; and
* operation-specific atomicity.

### Classification

**SUITE-BUILD fix for the complete abstract epoch model; ACTIVATION-gate for real Windows race-freedom.**

---

## Ranked Finding 6 — R-1 and working-memory role isolation are only partially exercised

### Hole

The frozen R1-ROLE-1 amendment forbids diagnostics from populating or satisfying:

* `control_plane`;
* evidence;
* evidence requirements;
* coverage results;
* packet disposition;
* working memory;
* grants/policy/approval/manifest/health;
* trusted status;
* completion;
* target resolution; and
* effect derivation.

The as-built notes describe M-R11 more narrowly:

> cast the router stage-trace into evidence coverage.

That proves one important sink but not the complete role-isolation obligation.

The 0.9.0 D-0077 fold also cannot fill the gap because its cases stop at A06. An attacker-shaped diagnostic can be harmless at A06 and still affect A31 if a later test packet permits evaluation to continue.

### Residual role-conversion paths

Uncovered or undocumented cases include:

* diagnostic reason code changes `packet_disposition`;
* diagnostic candidate id enters `coverage_results`;
* diagnostic value becomes trusted validator status;
* diagnostic policy id is interpreted as manifest or health authority;
* diagnostic target id enters target resolution;
* diagnostic counts affect actual-effect derivation;
* working-memory `is_evidence=true` is honored by A31;
* working-memory “approval received” affects completion rather than authorization;
* diagnostic or working-memory content modifies an absence/completeness predicate.

Namespace closure does not prevent any of these when the malicious object remains in the allowed namespace.

### Exact closure

Turn M-R11 into a parameterized sink matrix, or add dedicated mutations:

```text
diagnostic -> evidence
diagnostic -> evidence_requirement
diagnostic -> coverage_result
diagnostic -> packet_disposition
diagnostic -> control_plane
diagnostic -> grant/policy/approval/health
diagnostic -> TrustedStatus
diagnostic -> completion
diagnostic -> target
diagnostic -> effect
```

Repeat the relevant cases for working memory, complementing M-R02/M-A03 rather than assuming they cover the real #40 0.9.0 representation.

Run these against the real routed/hydrated packet under the test-only `non_execution=false` mechanism so A31 and completion are actually reached.

### Classification

**SUITE-BUILD fix required before pass.**

---

## Ranked Finding 7 — The as-built pass is not independently auditable from the supplied pack

### Hole

The request explicitly says to verify the results rather than take them on trust. The included pack contains:

* contracts;
* the prior red-team;
* README;
* SCHEMA_NOTES.

It does not contain:

* `monitor.py`;
* `boundary.py`;
* `stores.py`;
* `canon.py`;
* `oracle_matrix.py`;
* `integration.py`;
* mutation implementations;
* fixture bodies and canonical hashes;
* the independent `p01gate` implementation;
* the machine-readable 204/204 report; or
* the two-run reports whose signature is quoted.

The README asserts the pass and the schema notes describe it, but those are produced by the same implementation owner whose work is under review.

This makes it impossible to verify:

* whether a mutant really changes production code rather than a test-only branch;
* whether the independent oracle imports the implementation under test;
* whether the second canonicalizer is genuinely independent;
* whether all fixtures ran;
* whether report aggregation marks missing tests as pass;
* whether the 0.9.0 fold used an authentic or manually reconstructed packet; or
* whether the quoted signature covers the source, fixtures, and report.

### Exact closure

A future as-built pass-review packet should include at least:

1. source files implementing the monitor, mock executor, stores, canonicalizer, and completion evaluator;
2. complete test-facing schema definitions;
3. the oracle matrix;
4. mutation source or exact patches;
5. fixture manifest with hashes and family mapping;
6. integration test source;
7. machine-readable reports from both runs;
8. source-tree and report digests;
9. independent implementation source and provenance; and
10. the D-0077 fold report and exact packet hashes.

This is not necessarily a defect in the local suite, but it prevents an external reviewer from issuing `CONFIRM-PASS`. In this case, the other documented inconsistencies independently establish that the pass is over-claimed.

### Classification

**SUITE-REPORT / REVIEW-PACK fix required for independently confirmed pass.**

---

## Direct Answers

### Are the test-facing views sufficient?

**No, not as supplied or documented.**

They are implementation names pointing to `stores.py`, not frozen byte-exact schemas and algorithms. Conjunction, alternative grants, target-predicate composition, limit intersection, revocation/epoch handling, and complete matcher output are not specified in the bundled normative record.

### Is `completion_scope` plus packet binding sufficient?

**Conceptually yes, if implemented exactly. As documented, no.**

The required mechanism is exact `packet_id` → exact permit-time completion contract. The notes instead say the contract is selected through the packet’s `task`, which leaves same-task contract substitution possible. The minimum scope rules by leaf type are also not documented.

### Is Boundary D race-free?

**No such general claim is justified.**

The reordered mock closes a modeled post-claim target substitution. It does not yet demonstrate all mutable-epoch rereads, and real Windows stable-handle and crash semantics correctly remain activation-gating.

### Are the oracle observables independent?

**Not established, and the matrix is incomplete by its own description.**

It contains one row per mutation rather than one row per frozen obligation. The supplied pack also omits the matrix and oracle implementations, so circular imports or shared computations cannot be inspected.

### Does M-R11 plus the fold close role laundering?

**No.**

M-R11 covers diagnostic-to-evidence-coverage. R1-ROLE-1 covers many additional sinks. The authentic 0.9.0 fold stops at A06 and therefore cannot prove A31, completion, target, or effect isolation.

### Is 0.7.0 suite integration sufficient?

**No.**

It is sufficient for the legacy flat packet and A06. It is not sufficient for the current routed and hydrated 0.9.0 producer-consumer seam. The real 0.9.0 path must be owned by and executed within the suite gate.

---

## Staged-vs-Load-Bearing Disposition

### Must move into the suite before `pass`

* complete obligation-level oracle matrix;
* exact normative test-facing views;
* exact completion-contract/packet binding and leaf-scope table;
* full mock post-claim epoch rechecks;
* expanded R-1 and working-memory sink coverage;
* current authentic #40 0.9.0 routed/hydrated integration;
* machine-readable evidence that all frozen criteria ran.

### May remain activation-gating

* real Windows permit-store IPC/ACL/CAS/crash recovery;
* production grant/policy/approval storage schemas, once proven equivalent to exact test views;
* real per-tool target/effect and stable-handle profiles;
* production executor/status ownership;
* freshness-policy relaxation beyond latest-current-only;
* `non_execution=false` production transition;
* production security-log ACL, retention, and redaction;
* physical timing-channel hardening;
* operation-specific rollback and crash recovery; and
* activation of any real manifest.

These staged items do not invalidate a **logical design-suite pass** so long as the pass explicitly does not claim operational readiness. The present failure is that several logical suite requirements themselves remain incomplete.

---

## Frozen-Contract Consistency

The required corrections do not need to reopen MEMORY_CONTRACT or CONTEXT_PACKET_CONTRACT fields.

* Current #40 integration consumes existing 0.9.0 fields.
* R-1 role tests enforce existing diagnostic restrictions.
* Working-memory tests enforce existing `working_state`, `can_instruct:false`, task, namespace, and state-version rules. The packet contract already requires namespace closure over working memory and every diagnostic carrier.
* Exact completion binding can use the already authentic `packet_id`.
* Grant/policy/status views are action-layer test contracts.
* Oracle expansion changes only the suite/report.
* Executor epoch tests change only the mock action boundary.

No lossless evidence rewriting or sanitization is required.

---

## Required Result State

Until Findings 1–6 are closed:

```text
build_status = build_complete
p0_1_gate_status = incomplete
activation_status = prohibited
```

After closure, a new double run should require:

* all frozen criteria explicitly present;
* no `not_run` mandatory criterion;
* current #40 0.9.0 real-chain tests inside the suite;
* all obligation and mutation oracles green;
* byte-identical property results and fixture hashes; and
* a report digest covering source, fixtures, matrix, and results.

## Final Decision

**FAIL — the current `p0_1_gate_status=pass` is over-claimed.**

The i38 work appears to be a substantial and valid advance over the i37 MVP. The correct response is not to discard it, reopen the substrate, or delay unrelated work. The correct response is to preserve `build_complete`, return the gate to `incomplete`, close the remaining suite-level requirements, and rerun the full deterministic gate while `non_execution:true` continues to prohibit every authentic action.

