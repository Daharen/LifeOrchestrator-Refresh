# i39 P0-1 action-authorization FULL-gate RE-REVIEW (as-built) -- couriered frontier answer (pack b2b1e5fb)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match, captured/valid); D-0052 human-courier lane. DESIGN ONLY -- `non_execution:true` holds; this changes no shipped memory/packet field and enables no execution. **Verdict: FAIL -- `p0_1_gate_status=pass` is OVER-CLAIMED; walked back to `incomplete` (D-0109).** `build_status=build_complete` + `activation_status=prohibited` are UNCHANGED, and deny-by-default HOLDS (the orchestrator D-0077 fold-i39 18/18 + the independent #43 run_suite 308/308 re-run stand; A06 denies every authentic packet; nothing is action-capable). The 7 findings below are ALL SUITE-BUILD fixes required before pass (none reopens a frozen MEMORY_CONTRACT/CONTEXT_PACKET_CONTRACT field); they become the i40 unit-0 (bundled with PB-5 the #37 lane). Companion: the i38 FAIL `research/2026-08-06-i38-p01gate-asbuilt-redteam.md` (D-0107) + the i37 freeze red-team `research/2026-08-05-i37-action-authz-freeze-redteam.md`.

---

# FAIL — `p0_1_gate_status=pass` remains over-claimed

The i39 build contains substantial, real improvements, but the seven D-0107 findings are not all closed as built. Several remaining defects are themselves logical suite-gate defects—not merely production hardening that can remain activation-gating.

The honest taxonomy remains:

```text
build_status       = build_complete
p0_1_gate_status   = incomplete
activation_status  = prohibited
```

This verdict does **not** authorize execution or allege that action capability has been activated. The review remains design-only under `non_execution:true`.

## Ranked Finding 1 — Completion is not immutably bound at issue time

### Hole

`evaluate_completion_via_permit` resolves through `permit["packet_id"]`, but two critical checks are optional:

```python
if cc.get("packet_id") is not None and cc.get("packet_id") != permit["packet_id"]:
    return "indeterminate"

b = st.permits.completion_binding(permit["permit_id"])
if b is not None and (... mismatch ...):
    return "indeterminate"
```

Thus:

1. A completion contract with no `packet_id` is not rejected for lacking the required binding.
2. A permit with no issue-time completion binding is not rejected for lacking that binding.
3. A permit may be issued when no completion contract exists, causing A34 to record `None`; a contract can then be inserted later under the permit’s packet ID and evaluated without comparison against any issue-time contract identity.

A34 explicitly records whatever `completion_binding_for_packet` returns, while that function returns `None` when no contract exists.
The claimed “omitted binding” vector tests only a leaf whose `completion_scope="task"` is weaker than the required permit scope. It does not test an absent contract `packet_id`, a deleted/null permit-store binding, or insertion of a contract after permit issuance.

### Exact closure

Require all of the following on the reference path:

```text
cc.packet_id is present
cc.packet_id == permit.packet_id
issue_time_completion_binding is present
binding.id/version/digest == current contract id/version/digest
```

When no completion contract exists at issue time, record an immutable explicit `NO_COMPLETION_CONTRACT` sentinel; that permit must remain incapable of becoming completable through a later contract insertion.

Add deterministic vectors for:

* contract inserted after permit issuance;
* missing `cc.packet_id`;
* missing/deleted permit completion binding;
* `None` issue-time binding followed by later contract insertion;
* binding changed after issue.

**Classification: SUITE-BUILD fix required before pass.**
The existing freeze amendment is sufficient; no new freeze amendment is required.

---

## Ranked Finding 2 — Boundary-D tests do not inject post-claim drift

### Hole

The frozen ordering requires atomic claim, followed by mutable-epoch rereads, post-claim target resolution/binding, and an immediate identity verification before effect. It expressly requires target mutation both before and after claim.

The implementation’s nominal order is improved: the executor claims first and then performs its checks. But the oracle helper mutates the store **before calling `execute`**:

```python
mutate(st, d)
r = MockExecutor(st).execute(d.permit_ref)
```

The claim occurs later, inside `execute`. These are post-issue/pre-claim mutations, despite being labeled “post-claim.” The same helper also accepts the permit remaining `issued`, although the expected disposition is a terminal, non-reusable `rejected_no_effect`.

There are additional decidability gaps:

* The entire epoch recheck is skipped when `issue_snapshot` is absent because it is guarded by `if snap is not None`.
* `bound_targets` is compared and assigned, but effects are ultimately produced by copying `permit["authorized_effect_set"]`; the supposedly captured target handle is not consumed by an independently observable effect application.
* No hook exists between atomic claim and the individual epoch checks, so the critical race position is not exercised.
* The “grant revoked” oracle flips the snapshot’s `current` flag rather than separately revoking a matched grant.
* Approval expiry is checked in code but lacks its own post-claim mutation row.
* The final effect path copies authorized effects rather than applying them through the bound target identity.

### Exact closure

Add a deterministic executor hook immediately after successful atomic claim and before each recheck. Inject one fault per independent mutable surface:

```text
grant epoch
grant currentness
matched-grant revocation
policy epoch
policy currentness
approval revocation
approval expiry
manifest disappearance/digest drift
installed-artifact drift
health drift
permit-store epoch
packet currentness
packet non_execution transition
target identity drift
```

For every row require exactly:

```text
accepted == false
state_diff == []
permit_state == rejected_no_effect
second execution attempt == rejected
```

Make the issue snapshot mandatory for every store-issued permit. Model the captured target as a trusted handle object that the effect ledger actually consumes, then test target mutation both before and after claim.

**Classification: SUITE-BUILD fix required before logical pass.**

Real Windows handles, reparse-point behavior, IPC/ACL/CAS, and crash race-freedom correctly remain **ACTIVATION-gating**.

---

## Ranked Finding 3 — The role-conversion matrix omits frozen sinks

### Hole

The frozen R1-ROLE-1 obligation prohibits router diagnostics from populating or satisfying:

```text
control_plane
evidence[]
evidence_requirements
coverage_results
packet_disposition
working_memory
grant
policy
approval
manifest
health
TrustedStatus
completion
target resolution
effect derivation
```

The implemented 13-sink matrix contains:

```text
evidence
evidence_requirement
coverage_result
packet_disposition
control_plane
grant
policy
approval
health
trusted_status
completion
target
effect
```

It omits both:

* `manifest`
* `working_memory`

Therefore the reported 26/26 result is complete only against the implementation’s narrowed sink list, not against the frozen R1-ROLE-1 list.

### Exact closure

Add at minimum:

```text
routing diagnostic -> manifest
working-memory carrier -> manifest
routing diagnostic -> working_memory
```

If the design retains a full two-carrier Cartesian matrix over all 15 frozen sinks, it should produce 30 rows. For the `working_memory -> working_memory` pair, define the prohibited conversion precisely—for example, untrusted working-memory content altering trusted state metadata, task binding, namespace authorization, `state_version`, or `can_instruct`.

Each seeded defect must modify only the nominated sink, reach the check that owns that sink, and produce a separately observable authorization or completion difference.

**Classification: SUITE-BUILD fix required before pass.**

---

## Ranked Finding 4 — The byte-exact GrantView does not implement its declared limit algebra

### Hole

The freeze requires exact, decidable semantics for target predicates, quantitative limit intersection, conjunction/alternative behavior, revocation, epochs, and complete matcher output.

The new SCHEMA_NOTES definition is much stronger than i38’s and is a genuine improvement. It declares both:

```text
max_quantity: map<effect_class,uint63>
limits: array<{limit_id,max_value}>
```

and states that effective quantity uses a minimum/intersection rule.

But the matcher:

* consults `max_quantity`;
* never reads the grant’s `limits` array;
* returns only `(matched_grant_ids, ok)`;
* does not return an effective grant-derived limit;
* unions scopes across alternative grants without defining the effective quantitative limit when different matching grants carry different ceilings.

A23 then constructs permit limits solely from the manifest’s `resource_ceiling`, rather than intersecting manifest, grant, policy, or approval constraints.

The golden vector called “limit intersection” changes only `max_quantity`; it does not test the declared `limits` field or a multi-source minimum.

Consequently, two implementations can still disagree about the meaning of `limits` and multi-grant limit composition while passing the supplied vectors.

### Exact closure

Either remove the redundant `limits` field through a properly recorded amendment, or implement and pin the complete algebra. Preferably:

```text
effective_limit[effect] =
    min(
        manifest resource ceiling,
        every applicable conjunctive grant limit,
        applicable policy limit,
        applicable approval limit
    )
```

The pinned canonical view must encode the ordered matching algorithm and output shape as data, not merely field declarations.

Add golden vectors for:

* `limits.max_value < max_quantity`;
* manifest ceiling lower than grant ceiling;
* grant ceiling lower than manifest ceiling;
* two matching grants with different scopes and ceilings;
* whether grants combine scopes while limits remain per-grant or intersect globally;
* malformed and duplicate limit IDs;
* current/revoked snapshot behavior;
* unknown or ambiguous fields failing closed.

**Classification: SUITE-BUILD fix required before pass.**
If the intended semantics differ from the existing frozen “limit intersection” rule, that change would additionally require a **FREEZE AMENDMENT**.

---

## Ranked Finding 5 — The 0.9.0 chain is authentic at A06 but synthetic beyond A06

### Hole

The integration source now explicitly loads routed, adversarial, and flat 0.9.0 packets, verifies their structural markers, and exercises A06. That materially closes the original absence of the current producer generation.

However, the test-only path does not preserve the complete authentic trusted seam:

* it sets `current_corpus_version=None`, bypassing A07 corpus consistency;
* it replaces the packet view’s original grant snapshot reference with `grant_snap_090`;
* it supplies newly constructed manifest, grant, policy, health, resolver, and proposal records.

More importantly, the adapter reduces the routed trace and working-memory region to two booleans:

```text
routing_present
working_present
```

The actual diagnostic records, working-memory items, provenance, state metadata, and injected structures do not cross into the monitor-facing representation.

The resulting test does demonstrate that the monitor reaches A09/A11/A30/A31 under a packet-derived task, namespace, disposition, and packet ID. It does not fully demonstrate that the authentic current producer-consumer adapter preserves and safely classifies every 0.9.0 carrier. The benign/adversarial equality is partly guaranteed because most differing carrier content has already been discarded by adaptation.

### Exact closure

Create a suite-owned exact adapter for `context_packet/0.2` that:

* validates and preserves all identity-covered fields;
* does not rewrite the packet’s grant-snapshot identity;
* preserves the complete routed trace, working-memory envelopes/items, evidence structures, provenance, namespace metadata, and state version;
* applies a test-only authority overlay that changes only the externally controlled `non_execution` condition;
* provides trusted stores whose IDs and digests agree with the packet rather than replacing packet identity values.

Run benign and adversarial packets through that exact seam and assert inertness at every R1 sink.

**Classification: SUITE-BUILD fix required before pass.**

---

## Ranked Finding 6 — The 141-row matrix is broader, but not independently decisive for every obligation

### Hole

The matrix now has the requested categories and is no longer merely a 67-row mutation list. A35 is observed on the model-facing caller result, and A36 uses the privileged log rather than relying only on authorization outcome. This is meaningful progress.

Nevertheless, several independence claims remain too strong.

#### `no_path` is not a call-graph proof

The static test:

* reads only `canon.py` and `monitor.py`;
* searches for two guard strings;
* regex-counts textual occurrences of `authority_construct(` in `monitor.py`.

It does not construct a module-level call graph, inspect aliases/import bindings, follow helper calls, or inspect `boundary.py`, `stores.py`, and `schemas.py`. This is source-pattern checking, not the required reachability inspection.

#### A36 does not prove mandatory audit emission

The A36 observer returns whether any event contains a `leak` key. Deleting audit emission entirely would return `False`, the same as the secure baseline. It therefore proves only “no leak under this fixture,” not “the required bounded audit event exists and is correct.”

#### Boundary-B rows are presence assertions

The four rendering rows inspect whether expected packet fields or banners are present. They have no injected fault or independently exercised renderer transformation; their `observed_fault` is simply reported as “C-decisive.”

#### Several A-check rows still use the checked path’s own reason code

A reason-code assertion is useful for isolation, but it is not always an independent observable surface. A suite can reproduce a check label and its result from the same defective path.

### Exact closure

* Build a deterministic stdlib `ast`-based call graph over every `action_authz` module.
* Resolve direct imports, aliases, attribute calls, and reachable helper functions from ordinary entry points.
* Combine that graph with the authority-constructor capability instrumentation.
* For A36 require exactly one correctly shaped bounded audit event and separately assert no attacker payload.
* Add deletion/corruption faults for audit emission.
* For Boundary B, mutate the actual rendering path and observe rendered bytes, ordering, and delimiters, or explicitly classify those rows as non-decisive defense-in-depth evidence rather than independent authorization oracles.
* Where feasible, pair each A-check with a state, capability, digest, permit-store, caller-channel, or ledger surface outside the implementation branch being tested.

**Classification: SUITE-BUILD fix required before pass.**

---

## Ranked Finding 7 — The supplied review pack is not independently runnable

### Hole

The pack’s included-file manifest contains only 21 files. It does not include the complete source tree needed by its own runner.

`run_suite.py` imports:

```text
action_authz.VERSION
tests.harness
tests.fixtures_suite
tests.properties
tests.fuzzer
tests.report
```

in addition to the files that were included.

The pack also omits:

* `action_authz/__init__.py`;
* the actual 0.7.0 and 0.9.0 JSON packet fixtures;
* `tests/report.py`;
* generated `report.json`;
* `oracle_matrix.json`;
* `fixture_manifest.json`;
* `mutation_defs.json`;
* `source_digests.json`;
* `MANIFEST.json`.

Those are precisely the artifacts SCHEMA_NOTES says establish independent auditability.

I extracted the 21 bundled files and executed the stated command. It stopped before test collection with:

```text
ImportError: cannot import name 'VERSION' from 'action_authz'
```

Even after supplying that missing initializer, the other imported test modules and packet fixtures are still absent. The claimed 308/308 and evidence-bundle digest therefore cannot be independently regenerated from this review pack.

### Exact closure

Ship a clean, complete runnable tree containing:

```text
all action_authz package files
all imported tests
all fixture JSON
tests/report.py
both generated report bundles or the final deterministic bundle
source-tree digests
fixture hashes and provenance
the orchestrator fold report and exact packet hashes
```

From an empty directory, the documented command must:

1. exit zero;
2. reproduce 308/308;
3. reproduce all 141 oracle rows;
4. reproduce the same source and fixture digests;
5. regenerate a byte-identical report manifest.

**Classification: SUITE-BUILD / REVIEW-PACK fix required before independently confirmed pass.**

---

# Direct answers

## F1 — Is the oracle matrix independently observable?

**No, not fully.**

The scope expansion to 141 rows is real. A35’s caller surface is appropriate. A36 is on the correct class of surface but checks only absence of a leak, not mandatory audit emission. The `no_path` implementation is not a genuine module-wide import/call-graph analysis.

## F2 — Does the authentic 0.9.0 chain exercise the formerly short-circuited obligations?

**Partly.**

It owns 0.9.0-loading code and reaches A09/A11/A30/A31 in the synthetic authority mode. It does not preserve the complete authentic trusted identity and carrier representation beyond A06, and the packet JSON files needed to verify authenticity are absent from the review pack.

## F3 — Are the byte-exact views sufficient to prevent divergent implementations from both passing?

**No.**

The views are substantially more explicit, but the declared grant `limits` field and limit-intersection semantics are not implemented or tested. The pinned object does not capture the full matching algorithm sufficiently to resolve that divergence.

## F4 — Does `packet_id` plus `MIN_COMPLETION_SCOPE` close the task-only completion hole?

**Not yet.**

It closes ordinary cross-action status substitution when a properly bound contract exists. It does not close absent packet binding, absent issue-time binding, or late contract insertion after permit issuance.

## F5 — Is Boundary D complete for a logical pass?

**No.**

The executor code has the intended nominal ordering, but the suite does not inject faults after claim, does not require the snapshot, permits `issued` as an acceptable result, and does not independently demonstrate effects being applied through the captured target identity.

Real Windows race-freedom remains correctly staged to activation.

## F6 — Does the 26-row matrix close role laundering?

**No.**

It omits the frozen `manifest` and `working_memory` sinks.

## Frozen-contract consistency

None of the required repairs needs to reopen a frozen `MEMORY_CONTRACT` or `CONTEXT_PACKET_CONTRACT` field:

* `packet_id` already exists and is the intended authentic binding;
* working-memory and diagnostic role restrictions already exist;
* the missing role sinks are enforcement tests for existing restrictions;
* Boundary-D hooks and target handles are action-layer mock changes;
* oracle and report repairs are suite-only;
* no evidence rewriting or sanitization is needed.

The governing amendment itself characterizes R1 isolation as additive and explicitly says it changes no packet field.

## Items that may remain activation-gating

The following do not block a future logical suite pass once the findings above close:

* real Windows permit-store IPC/ACL/CAS/crash recovery;
* production per-tool reparse, ADS, junction, recipient, and stable-handle profiles;
* production grant/policy/approval storage formats after exact conversion proof;
* production executor/status and security-log ownership;
* freshness relaxation;
* the real `non_execution=false` transition;
* physical timing-channel hardening;
* operation-specific rollback and crash recovery.

These are already identified by the runner as staged activation work.

# Final disposition

```text
FAIL — the reported pass is over-claimed.

build_status       = build_complete
p0_1_gate_status   = incomplete
activation_status  = prohibited
```

The build should not be discarded. The deny-by-default architecture and i39 additions represent real progress. But Findings 1–7 above must close—or the affected requirement must be explicitly and properly amended—before `p0_1_gate_status=pass` is honest.
