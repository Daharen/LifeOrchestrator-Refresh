# i37 action-authorization FREEZE red-team -- couriered frontier answer (pack 2121775f)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match, captured/valid); D-0052 human-courier lane. DESIGN ONLY -- `non_execution:true` holds; this authorizes NO execution and changes no shipped memory/packet field. Verdict **GO-WITH-AMENDMENTS**: GO on the freeze as the design target + on continuing the i37 build; NO-GO on calling the reduced i37 MVP scope a full `P0-1 gate pass`. The 7 required amendments are folded into `ACTION_AUTHORIZATION_CONTRACT.md` s6 (D-0104) as the i38 build set. Companion (the freeze itself): `research/2026-08-05-i36-action-authz-freeze-frontier.md`.

---

# FROZEN Action-Authorization Contract Red-Team

## Verdict: GO-WITH-AMENDMENTS

The central architecture is sound enough to remain the normative **design target**, and the i37 implementation work may continue. The decisive reference monitor remains outside the model, authority is store-sourced, effects are independently derived, permits are one-shot and store-backed, and authentic shipped packets still deterministically deny at A06 because `non_execution:true`.

However:

> **i37 may report `MVP_BUILD_COMPLETE`; it must not report `P0_1_GATE_PASS` unless the amendments and minimum acceptance artifacts below are present.**

The current freeze combines a full acceptance gate—ten mandatory fixture families, fixed-seed fuzzing, every seeded mutation killed, canonical implementation equivalence, and real-module integration—with an MVP that stages several of those exact requirements.
That is not a reason to halt the build. It is a reason to make the build-status/gate-status distinction normative before the suite can emit a misleading green result.

---

## Ranked Finding 1 — The frozen gate and the i37 MVP do not currently denote the same pass condition

### Hole

The frozen acceptance language requires:

* all mandatory fixtures;
* the fixed-seed mutational fuzzer;
* every seeded mutation killed;
* canonical or byte-equivalent implementations; and
* real #36/#37/#40 producer-to-consumer tests.

The i37 build instead includes family 10 plus only a representative subset of families 1–9, only mutations the mock monitor/executor can exercise, and stages the full ten-family corpus and fixed-seed fuzzer to i38.

A harness may therefore be internally green while the frozen P0-1 gate remains incomplete. This is a false-assurance risk if both states are called “pass.”

### Existing catch

Section 8.7 does catch this normatively: it says the gate passes only if all ten criteria hold.

### Does it catch it now?

**Only if the reporting layer refuses to call the i37 subset a gate pass.** The build-vs-activation section distinguishes implementation scope, but it does not define a machine-readable result taxonomy preventing `MVP PASS` from being confused with the frozen gate’s `PASS`.

### Required closure

Add a freeze amendment defining at least:

```text
build_status:
  incomplete | build_complete

p0_1_gate_status:
  not_run | incomplete | pass | fail

activation_status:
  prohibited | eligible | activated
```

Normative rules:

1. `build_complete` does not imply `p0_1_gate_status=pass`.
2. A skipped fixture family, unrun fuzzer, surviving/unimplemented mutation, or absent real-chain test yields `p0_1_gate_status=incomplete`, never `pass`.
3. Activation requires `p0_1_gate_status=pass`, all activation blockers resolved, and the separate activation decision.
4. The test report lists every criterion as `pass | fail | not_run | not_applicable`, with `not_applicable` forbidden for a frozen mandatory criterion.

If i37 is intended to produce an actual **MVP gate pass**, move into i37:

* at least one canonical fixture from **each** of the ten families;
* a small bounded fixed-seed fuzzer;
* a kill result for every mandatory mutation; and
* the real-chain test.

The larger/deeper fixture corpus can remain staged.

### Classification

**Freeze amendment and suite-build requirement.**

---

## Ranked Finding 2 — Blocker 1 is partly BUILD-gating, exactly as the prior freeze analysis stated

### Hole

A26 requires exact matching over tool, operation, namespace, canonical targets, effects, quantities, limits, externality, risk, validity, and approval mode. A27 applies the current side-effect policy.

But the freeze still does not define:

* the closed grant and policy input shape;
* conjunction versus alternative-grant semantics;
* how target predicates compose;
* whether two individually insufficient grants may jointly authorize;
* limit aggregation;
* revocation/version matching;
* empty-scope behavior; or
* conflict resolution.

The prior blocker text explicitly concludes that without a defined grant/policy view, grant matching is implementation-defined and the gate is not decidable.

The i37 disposition substitutes “test `GrantView`/`PolicyView` fixtures,” but fixtures alone do not define the language against which the fixtures are judged.

### Existing catch

A26, A27, C4, M-E08 through M-E11, and U-AUTHORITY are the correct obligations.

### Does it catch it now?

**No, not deterministically.** Two implementations can consume the same fixture objects while applying different conjunction and target-predicate semantics, and each can construct self-consistent tests that pass.

### Required closure

Before the i37 gate tests A26/A27, freeze a minimal test-facing interface such as:

```text
lifeorch.grant_view/0.1-test
lifeorch.policy_view/0.1-test
```

It need not yet be the production storage schema, but it must byte-exactly define:

* field types and canonicalization;
* validity and revocation;
* exact tool/operation matching;
* target-predicate language;
* namespace semantics through canonical `ns_permitted`;
* effect and externality matching;
* quantitative limit intersection;
* risk and approval escalation;
* conjunction/alternative rules; and
* the complete matcher output.

The production `permission_grant/0.1` and `side_effect_policy/0.1` storage contracts may remain activation-gating if they are later proven byte-equivalent to these frozen views.

### Classification

**Freeze amendment and suite-build requirement.**

Blocker 1 is not wholly activation-gating.

---

## Ranked Finding 3 — The executor ordering leaves an executor-side TOCTOU window

### Hole

The permit state machine says the permit is claimed before any executor preflight that could race another executor, and a failed post-claim preflight becomes permanently `rejected_no_effect`.

Boundary D instead orders:

1. mutable grant/policy/health checks;
2. dynamic target re-resolution;
3. then atomic permit claim;
4. then execution.

A target mapping, symlink, junction, recipient alias, policy epoch, approval, health state, or installed artifact can change after D3/D4 but before D5’s effect. Claiming the permit prevents another executor from claiming the same permit; it does not freeze the filesystem, registry, recipient map, policy stores, or tool installation.

A malicious race can therefore substitute the actual target after the last comparison.

### Existing catch

* A32 catches authorization-side drift.
* D4 is intended to catch executor-side target substitution.
* D3 is intended to catch post-issuance revocation/drift.
* M-E29 requires target substitution at execution to be killed.

### Does it catch it now?

**Not reliably.** D4 occurs too early unless target resolution returns and execution consumes a stable object handle or equivalent immutable identity that cannot be redirected afterward.

### Required closure

Amend Boundary D ordering:

1. Resolve the permit reference and verify immutable permit structure/digest.
2. Atomically claim the permit.
3. Re-read all mutable epochs: grant, approval, policy, manifest/artifact, health, permit revocation.
4. Re-resolve dynamic targets **after claim**.
5. Bind execution to stable handles or canonical identities obtained during that re-resolution.
6. Immediately before the first effect, verify that those same bound identities are being used.
7. On any failure, transition to `rejected_no_effect`.

Expand M-E29 to include:

```text
resolve target A
mutate alias/reparse/recipient mapping to target B
attempt execution
expect rejected_no_effect and EMPTY state diff
```

Run variants both before and after permit claim.

### Classification

**Freeze amendment.**

The real Windows mechanism remains an activation gate, but the abstract ordering must be corrected in the frozen design now.

---

## Ranked Finding 4 — Completion binding is internally under-specified and M-E36 is not fully decidable

### Hole

`SubjectBinding` always contains `task_id`, but its `canonical_action_digest`, `permit_id`, and `object_ref` are optional. A status need match only every field that is present.

The completion invariants nevertheless state that status produced for one action, permit, task, object, namespace, or validator version cannot satisfy another.

Those statements conflict for a task-only binding. If the action and permit fields are absent, the evaluator has no expected action or permit identity against which to reject status from another action under the same task.

There is a second ambiguity: U-AUTHORITY requires an issued permit’s “completion-contract reference” to resolve to a trusted store, but `lifeorch.action_permit/0.1` contains no completion-contract id, version, or digest.
`packet_id` may transitively bind a completion contract, but the contract never states that completion evaluation must resolve the exact permit-time contract through that packet rather than use the task’s current contract.

A suite can therefore choose either interpretation and pass its own fixtures.

### Existing catch

A30, A32, the trusted-status requirements, completion invariant 5, U-ROLE, M-E35, and M-E36 are the correct intended controls. A30 currently only verifies that the active contract is authority-sourced and unchanged during authorization.

### Does it catch it now?

**No.** The identity to which completion is bound is not fully specified.

### Required closure

Add one of these equivalent designs:

**Preferred: explicit binding mode**

```text
completion_scope:
  task | action | permit | object
```

Then require:

* `task`: exact task binding;
* `action`: exact task plus canonical action digest;
* `permit`: exact task, action digest, and permit id;
* `object`: exact canonical object identity, plus action/permit where the object was produced by that action.

Each leaf kind should define its allowed minimum scope. In particular, executor status and state-diff leaves for an action should not be task-only.

Also bind the completion contract used for evaluation through one normative mechanism:

* add `completion_contract_id`, version, and digest to the permit; **or**
* state that the permit’s authentic `packet_id` transitively and immutably selects that exact contract and that the evaluator must use no other contract.

Add deterministic fixtures for:

* old-action status reused under a new permit;
* old-permit status reused under the same task;
* status for the wrong object;
* contract substitution after permit issue;
* omitted optional bindings;
* superseded validator versions.

### Classification

**Freeze amendment and suite-build requirement.**

The production status schemas remain activation-gating, but a closed mock status/validator view is required in i37 to make completion properties and M-E35/M-E36 decidable.

---

## Ranked Finding 5 — “Every A01–A36 deletion is killed” is not yet a decidable test contract

### Hole

The freeze says every numbered check is independently fixture-testable and deleting or bypassing any check must be killed.

Several checks are not ordinary permit/deny predicates:

* A08 records authentic packet disposition for later use.
* A30 isolates the completion contract but does not itself authorize or deny a valid action uniquely.
* A35 is a disclosure-channel obligation.
* A36 is a privileged-audit obligation.

Deleting one may leave the final permit decision unchanged because a later check denies, an earlier check already denied, or the check affects a different observable surface. A black-box `permit versus deny` oracle cannot reliably kill such mutants.

The universal machine assertions also contain predicates such as:

```text
no_path(Untrusted | Request, Authority_constructor)
trusted_origin_closure(permit)
```

These are architectural/data-flow claims, not values a normal runtime fixture can observe without instrumentation.

Likewise, `actual_effects <= authorized_effect_set` requires an effect ledger independent of the executor’s own potentially mutated status output.

### Existing catch

The A-check requirements, U-properties, mandatory mutations, mock executor, and real integration chain collectively aim to catch these failures.

### Does it catch it now?

**Not until the suite defines the observation model for each obligation.**

### Required closure

Commit a check/mutation oracle matrix with one row for every A-check, boundary obligation, U-property, and M-mutation:

```text
obligation_id
fixture_id
baseline_expected
mutant_id
observable_surface
expected_mutant_difference
independent_oracle
```

Use separate independent observables:

* decision and permit-store delta;
* ordinary caller bytes;
* privileged channel contents;
* privileged bounded audit event;
* origin/capability event ledger;
* executor entry ledger;
* permit-state transitions;
* canonical digest;
* independent state-diff/effect ledger;
* completion-evaluator result.

For `no_path` properties, implement an unforgeable authority-constructor capability and deterministically inspect the module import/call graph plus attempted constructor events. Runtime fuzzing alone cannot prove “no path.”

For A35 and A36, kill mutations by inspecting their own output surfaces, not by expecting a changed authorization decision.

A test-only check trace may confirm that checks executed, but trace presence alone must not count as proof that the security property held.

### Classification

**Suite-build requirement; minor freeze amendment to define what “independently fixture-testable” and “killed” mean.**

---

## Ranked Finding 6 — R-1 is namespace-confined already, but it needs explicit role and non-consumption isolation

### Hole

The R-1 amendment already requires the stage trace to:

* live in diagnostics;
* use canonical `ns_permitted`;
* fail closed;
* emit no cross-namespace identifying metadata;
* be deterministic; and
* be tested as an untrusted carrier.

U-AUTHORITY quantifies over diagnostics, U-SCOPE includes every diagnostic, Boundary A4 scope-checks every diagnostic channel, and the manifest invariants say diagnostics cannot set manifest authority fields.

That is sufficient for the **namespace-crossing** question if implemented literally.

The remaining ambiguity is role conversion. A31 explicitly says navigation and working memory cannot satisfy evidence, but does not name diagnostics. No seeded mutation exactly represents “cast router diagnostic into evidence, authority, health, approval, or completion.”

A buggy compiler could let stage-trace record ids or reason codes influence evidence coverage or packet disposition while preserving namespace closure. A31 would then trust the authentic but incorrectly computed disposition.

### Existing catch

U-AUTHORITY and the general structural separation partly catch it, but no exact role obligation or dedicated mutation makes the failure independently decidable.

### Does it catch it now?

**Namespace leakage: yes. Role laundering: only indirectly.**

### Required closure

Add an explicit additive obligation without changing any existing packet field:

```text
R1-AUTH-1:
  Router stage-trace envelope and payload are non-authoritative diagnostics.
  They may participate only in packet identity, deterministic evaluation,
  privileged audit, and fail-closed namespace validation.

R1-ROLE-1:
  No router diagnostic field may populate or satisfy control_plane,
  evidence[], evidence_requirements, coverage_results, packet_disposition,
  working_memory, grant/policy/approval/manifest/health data,
  TrustedStatus, completion predicates, target resolution, or effect derivation.
```

Add a seeded mutation such as:

```text
M-R11:
  Cast an R-1 diagnostic record/reason code/candidate id into evidence coverage,
  authority, approval, health, or completion status.
```

Also distinguish trusted structural envelope fields—router policy id/version and deterministic counters—from referenced candidate identifiers and payload-derived data. Neither class grants authority, but the distinction improves origin auditing.

### Classification

**Freeze amendment and suite-build requirement.**

No existing frozen MEMORY_CONTRACT or CONTEXT_PACKET_CONTRACT field must be reopened.

---

## Ranked Finding 7 — M-S08 makes part of Blocker 9 BUILD-gating

### Hole

M-S08 requires the suite to kill a mutation that exposes not only differing error bytes but also a deterministic branch or step-count signal identifying where scope failed.

Blocker 9 explicitly includes response-size and observable-step equalization, while the i37 substitute provides only the constant denial object and a bounded in-process log.

Constant bytes do not by themselves kill a step-count oracle.

### Existing catch

The constant-denial rule catches content and response-shape leakage. M-S08 is the correct mutation for deterministic control-flow leakage.

### Does it catch it now?

**Not unless i37 instruments and compares the caller-observable branch/step signature.**

Actual wall-clock equalization on Windows is not realistically proved by deterministic stdlib unit tests, but deterministic control-flow differences can be measured.

### Required closure

Split Blocker 9:

**Suite-build portion**

* define every ordinary authorization API surface;
* assert identical response schema/length;
* instrument a caller-visible deterministic step/branch signature;
* require no namespace-dependent identifying log on ordinary channels;
* kill M-S08 and M-S09.

**Activation portion**

* production ACLs;
* retention;
* redaction policy;
* IPC behavior;
* scheduler/cache/timing-channel analysis;
* operational timing equalization where required.

The freeze should avoid claiming absence of all timing side channels. It can deterministically claim constant bytes and no explicit deterministic branch/step oracle, while leaving physical timing hardening activation-gating.

### Classification

**Suite-build requirement for M-S08; activation gate for production timing/log controls.**

---

## Blocker-Disposition Audit

| Blocker                                  | Correct disposition                                                                                                                                                                                                                                                                                           |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1 — Grant/policy schemas**             | **Partly BUILD-gating.** Exact frozen test `GrantView`/`PolicyView` semantics are required now; production storage schemas may wait.                                                                                                                                                                          |
| **2 — Approval contract**                | **Partly BUILD-gating.** A closed mock `ApprovalView` is required for A29 and M-E13. Production issuer/store/IPC contract may wait.                                                                                                                                                                           |
| **3 — Windows permit store**             | Activation-gating. The in-process atomic mock is adequate for the abstract suite if its state machine is independently tested.                                                                                                                                                                                |
| **4 — Per-tool target/effect profiles**  | Activation-gating for real tools. Generic mock profiles are sufficient for the abstract MVP; no real operation may activate without its profile.                                                                                                                                                              |
| **5 — Status/validator contracts**       | **Partly BUILD-gating.** A closed mock status and validator view is needed for U-ROLE and M-E35/M-E36; production tool schemas may wait.                                                                                                                                                                      |
| **6 — Freshness policy**                 | Build requirement satisfied only if `latest-current-only` is normative and tested. Any relaxation remains activation-gating.                                                                                                                                                                                  |
| **7 — `non_execution` transition**       | Activation-gating.                                                                                                                                                                                                                                                                                            |
| **8 — Canonical ownership/equivalence**  | **BUILD-gating, apparently satisfied conditionally.** It is sufficient only if monitor, mock executor, digest builder, grant matcher, and permit verifier truly import the one #43 implementation. A second implementation triggers mandatory equivalence fixtures immediately.                               |
| **9 — Constant failure/logging**         | Split: deterministic response/step oracle is BUILD-gating; production ACL/retention/timing hardening is activation-gating.                                                                                                                                                                                    |
| **10 — Per-operation transaction/crash** | Activation-gating, beyond the generic mock state-machine tests.                                                                                                                                                                                                                                               |
| **11 — Tool health**                     | Activation-gating, beyond a closed mock health view.                                                                                                                                                                                                                                                          |
| **12 — Elevated promotion path**         | The proof that the ordinary model path cannot invoke it is BUILD-gating; the real elevated mutation path is activation-gating.                                                                                                                                                                                |
| **13 — Skill-selection wording**         | Correctly resolved by normative clarification.                                                                                                                                                                                                                                                                |
| **14 — Real-module integration**         | **BUILD-gating.** The freeze already places the real #36/#37/#40 test in i37, so calling Blocker 14 entirely activation-gating is a classification error even though its required minimum appears to be scheduled correctly. The original text explicitly says the gate cannot pass on isolated schema tests. |

---

## Staged Items That Are Load-Bearing for an Honest MVP Gate

Move into i37—or report the gate as `incomplete`:

1. At least one canonical fixture from every mandatory family 1–10.
2. A bounded fixed-seed mutational fuzzer.
3. A complete mutation kill matrix; “every mutation we can exercise” is insufficient for `pass`.
4. Exact test-facing `GrantView` and `PolicyView`.
5. Exact test-facing approval, status, validator, and health views for the checks that consume them.
6. The real #36/#37/#40 denial integration.
7. One canonical implementation shared by the monitor and mock executor, or byte-equivalence fixtures.
8. Deterministic ordinary-channel step/branch assertions for M-S08.
9. Dedicated R-1 diagnostic role-laundering tests.
10. Completion cross-action/permit/object substitution tests.

These may remain staged without compromising an honest **build milestone**, but not a frozen **gate pass**:

* expanded depth within the ten-family corpus;
* real Windows permit-store IPC/ACL/crash recovery;
* production grant/policy/approval storage schemas, once byte-equivalent test views exist;
* real per-tool target/effect profiles;
* production executor/status schemas;
* production security-log ownership and retention;
* non-default freshness relaxation;
* activation transition; and
* any real action-capable manifest.

---

## Frozen-Substrate Consistency

None of the required corrections needs to rename or widen a frozen MEMORY_CONTRACT or CONTEXT_PACKET_CONTRACT field.

* The gate-status taxonomy belongs to the action-suite/report contract.
* Grant/policy/status test views are new sibling test interfaces.
* The D-boundary reorder changes action-layer sequencing.
* Completion binding changes or clarifies the action/completion contracts.
* R-1 confinement can be made explicit as an additive action-layer consumption rule and mutation.
* Canonical `ns_permitted`, packet namespace closure, lossless evidence, working-memory scope, provenance modes, supersession, and safe-pruning semantics remain intact.

---

## Final Decision

**GO-WITH-AMENDMENTS on the freeze as a design target and on continuing the i37 build.**

**NO-GO on declaring the current reduced i37 scope a passing P0-1 deterministic gate.**

The minimum freeze amendments are:

1. distinguish build completion, gate pass, and activation;
2. freeze exact test-facing grant/policy semantics;
3. repair executor claim/recheck/target-binding order;
4. make completion scope and contract binding explicit;
5. operationalize per-check and U-property oracles;
6. add explicit R-1 diagnostic role isolation and a dedicated mutation; and
7. split deterministic denial-channel obligations from production timing/log hardening.

With those amendments, the staged production work remains appropriately activation-gating, `non_execution:true` continues to deny all authentic action proposals, and the suite can provide a meaningful deterministic result without overstating what its mocks and partial corpus prove.
