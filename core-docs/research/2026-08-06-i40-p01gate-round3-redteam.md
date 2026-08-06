# i40 P0-1 action-authorization ROUND-3 RATIFICATION review -- couriered frontier answer (pack 5807bc3e)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match, captured/valid, sha256 b55822c6..; D-0052 human-courier lane). DESIGN ONLY -- `non_execution:true` holds; this changes no shipped memory/packet field and enables no execution. **Verdict: FAIL -- do NOT ratify contract s7; `p0_1_gate_status` stays `incomplete`.** THE M2-D DIFFERENCE (D-0110): unlike i38/i39, NOTHING was over-claimed this round -- #43 0.4.0 (`663145b`) emitted `incomplete` with `exact_closure_built` 7/7 as the claim carrier, so this FAIL walks nothing back; the review is the ratification gate working as designed. ACCEPTED AS CLOSED: F3 (all-15-sink role matrix) + F6 (call-graph/A36/render oracles) + the quantitative portion of F4 + the post-claim/terminal portion of F2. **5 SUITE-BUILD findings remain (none reopens a frozen field) -> the i41 #43 unit** (contract s7 D-0113 fold-block). Finding 5 (the pack omitted `WORK_ORDER.md`) is an ORCHESTRATOR pack-authoring omission -- the file exists on-box with the exact expected digest 36e713da..; future packs are GENERATED from the suite's required-file manifest and extracted+run from an empty dir BEFORE couriering. Companions: `research/2026-08-06-i39-p01gate-recheck-redteam.md` (D-0109) + `research/2026-08-06-i38-p01gate-asbuilt-redteam.md` (D-0107).

---

# ROUND-3 RATIFICATION REVIEW - P0-1 Action-Authorization Gate

**Pack:** `5807bc3e-541b-4fd0-a9cd-cde6c82c4720`
**Reviewed build:** `action.authz 0.4.0`, commit `663145b`
**Verdict:** **FAIL**
**Ratification:** **Do not re-ratify contract s7.**
**Required state:** `build_status=build_complete | p0_1_gate_status=incomplete | activation_status=prohibited`

The pack requires an actual reconstruction and empty-directory execution, followed by a source-level determination of whether all seven D-0109 closures genuinely hold.

## Independent execution

I extracted all 48 embedded files byte-for-byte and verified their declared sizes and hash prefixes before running the module.

From the reconstructed `modules/43-action-authz` root, I ran:

```text
python -X utf8 -B tests/run_suite.py
```

Observed result:

```text
Behavioral suite:       334/334 passed
Fixture families:       all 10
Mandatory mutations:    67/67 killed
Fuzzer:                  400 iterations / 0 violations
Oracle matrix:           149 rows / 0 not_run
Role matrix:             30/30
Completion vectors:      17/17
View vectors:            48/48
Exact closures reported: 6/7
Suite result:            INCONSISTENT
Process exit code:       1
```

The failed exact closure was Finding 7:

```text
finding_7 exact_closure_built = False
review pack missing: ['WORK_ORDER.md']
```

I also ran `tests/selfverify.py`. It terminated with `FileNotFoundError` while attempting to copy the missing `WORK_ORDER.md`.

The failure is intrinsic to the transported pack. `run_suite.py` explicitly requires `WORK_ORDER.md` for pack completeness, and returns exit 1 unless every exact-closure flag is true. `selfverify.py` independently includes that file in its mandatory copy set.

The bundled historical transcript nevertheless says `verified:true`, and its source-digest inventory contains a digest for `WORK_ORDER.md`. Therefore that transcript was generated from a fuller source tree than the tree actually transported in this pack. It does not attest the received artifact.

## Ranked findings

### 1. F1 - Completion binding is not immutable in the store

**Class:** `SUITE-BUILD before pass`
**Severity:** Ratification blocker

The completion evaluator itself correctly rejects an absent binding, permanently rejects the sentinel, and compares the issue-time contract ID, version, and digest against the currently resolved contract.

The hole is in `PermitStore`:

```python
def record_completion_binding(self, permit_id, binding):
    self._completion_binding[permit_id] = dict(binding)

def completion_binding(self, permit_id):
    return self._completion_binding.get(permit_id)
```

The record operation is an unrestricted overwrite, and the getter returns the stored mutable dictionary directly.

I reproduced this sequence:

1. Issue a permit when no completion contract exists; it receives `NO_COMPLETION_CONTRACT`.
2. Insert a completion contract afterward; evaluation remains `indeterminate`.
3. Call `record_completion_binding` again with the new contract identity.
4. Supply matching trusted status.
5. Evaluation becomes `true`.

Thus **late insertion alone is blocked**, but the claimed issue-time immutability is not enforced. A caller holding the trusted store can replace the sentinel or original binding after issuance. The returned dictionary can also be mutated in place.

This contradicts the stated closure that the sentinel is immutable and can "never" become completable through later insertion.

**Exact closure required**

* Make completion binding write-once per permit ID.
* Reject any second recording attempt, including an identical value.
* Store an immutable representation or private canonical bytes.
* Return a defensive copy or immutable view.
* Add vectors for:

  * sentinel overwrite after contract insertion;
  * valid-binding overwrite with a replacement contract;
  * mutation through the getter's returned object;
  * duplicate/concurrent recording.

### 2. F2 - Post-claim testing is genuine, but the target handle still is not consumed

**Class:** `SUITE-BUILD before pass`
**Severity:** Ratification blocker

The post-claim part of F2 is genuinely closed:

* atomic claim occurs first;
* the hook fires immediately afterward;
* the mandatory issue snapshot is checked after the hook;
* drift produces `rejected_no_effect`;
* the oracle checks an empty ledger and rejects a second attempt.
  The remaining hole is the handle-consumption claim.

The executor creates the prospective effect list by copying:

```python
actual = list(permit["authorized_effect_set"])
```

It then passes that copied list to `_apply_through_handles`.

`_apply_through_handles` extracts the `resolution_proof_digest` string from each target and appends that string as `applied_via_handle` to a copy of each effect:

```python
ledger.append(dict(e, applied_via_handle=h))
```

That is still a **permit-effect copy plus an identifying annotation**. A digest string is not a trusted handle object or capability that performs or authorizes the operation. The effect ledger is not independently produced by an effect path that must consume a captured target handle.

The present oracle would allow a defective implementation to copy `authorized_effect_set`, attach the expected digest, and pass.

**Exact closure required**

* Represent the captured target as a distinct trusted `TargetHandle` object or opaque capability, not a string copied from target metadata.
* Make the effect-applicator API require that object.
* Generate the effect ledger from the handle-bound applicator result, not from `permit["authorized_effect_set"]`.
* Make handles one-shot or otherwise observably consumed.
* Add a killed mutant that performs the current behavior: blind effect copy plus the correct `applied_via_handle` tag.

Real Windows handle/reparse behavior may remain activation-gating, but the logical mock must still model actual handle consumption rather than handle-shaped labeling.

### 3. F5 - The "exact" 0.9 adapter is lossy

**Class:** `SUITE-BUILD before pass`
**Severity:** Ratification blocker

`adapt_packet_view` claims to preserve all identity-covered fields, but it extracts only:

* `packet_id`;
* `task_id`;
* `non_execution`;
* namespace and allowed namespaces;
* `corpus_version`;
* grant-snapshot reference;
* a hard-coded `current=True`.

The authentic 0.9 packet identity also contains, among other things, compiler version, selection policy, query class, temporal intent, classifier policy, namespace-closure data, working-state version, retrieval-plan digest, consumer profile, selected record versions, budget, and omission-manifest digest.

`full_meta` also preserves only selected portions of the packet: routing trace, a reduced working-memory envelope, working-memory items, excerpts, namespace closure, and injected control-plane data. It does not preserve the complete identity, retrieval provenance, selection structures, evidence structures, control plane, transport accounting, or other packet carriers.

I confirmed this experimentally: independently changing each of the following produced identical adapter output:

* `identity.compiler_version`;
* `identity.selection_policy`;
* `retrieval_provenance`;
* `evidence.current_state_refs`;
* selection-stage content.

Consequently, two materially different authentic packets can collapse into the same supposedly exact trusted representation. The current tests prove that selected carriers are inert; they do not prove a lossless `context_packet/0.2` seam.

**Exact closure required**

* Preserve the complete packet, or preserve canonical packet bytes plus a validated derived view.
* Validate all packet-identity-covered fields and their internal coherence.
* Preserve complete identity, control plane, working memory, evidence, provenance, routing/selection trace, namespace metadata, and transport/omission metadata.
* Permit the test overlay to alter only `non_execution`.
* Add per-field mutation properties: changing any identity-covered field must either alter the preserved canonical identity or fail closed.
* Add round-trip or canonical-byte equivalence between the authentic packet and the adapter's preserved packet representation.

### 4. F4 - Limit intersection works, but the pinned closed GrantView is not enforced

**Class:** `SUITE-BUILD before pass`
**Severity:** Ratification blocker

The quantitative portion of F4 is implemented correctly:

* `max_quantity` and every applicable `limits[]` entry are intersected by minimum;
* duplicate limit IDs all participate;
* matched grants use a global minimum;
* manifest, grant, policy, and approval bounds are supported by `effective_permit_limits`.

However, the pinned `GRANT_VIEW` declares an exact closed top-level grant field set. The matcher only checks the closed shape of entries inside `limits[]`; it never validates the top-level grant object against that pinned field set.

I added an arbitrary top-level field to an otherwise valid grant:

```python
{"surprise_unknown_top_level": "accepted"}
```

The real matcher returned:

```text
(['g1'], True, {'fs.write': 1048576})
```

Therefore the declared closed view and the operational matcher can diverge while every current vector remains green. The existing unknown-field test covers only fields inside a `limits[]` entry.

**Exact closure required**

* Validate the exact top-level GrantView field set before matching.
* Validate required fields and exact types for all top-level values.
* Reject unknown top-level fields.
* Add vectors for unknown, missing, mistyped, and malformed top-level grant fields.
* Pin the operational validator itself, not only the descriptive `GRANT_VIEW` data object.

### 5. F7 - The transported review tree is incomplete

**Class:** `SUITE-BUILD before pass`
**Severity:** Independent ratification blocker

The pack describes itself as a 48-file complete runnable tree, but its included-files inventory ends without `WORK_ORDER.md`. Both `run_suite.py` and `selfverify.py` require that file.

This causes:

* `finding_7 exact_closure_built=False`;
* `consistent=False`;
* documented-command exit 1;
* `selfverify.py` failure before empty-directory reproduction;
* a regenerated report bundle different from the bundled attestation.

**Exact closure required**

* Add the exact `WORK_ORDER.md` whose expected digest is
  `36e713dafab2a5941d17ee5ccaa7853f6ceb87a2a671266faa6ee6ecb39ef1e7`.
* Rebuild the frontier pack from the exact source tree.
* Regenerate the evidence bundle and self-verification transcript from that transported tree.
* Independently extract the newly transported pack into an empty directory and run both documented commands before resubmission.

## Findings that do close

### F3 - PASS

The implementation and test matrix enumerate all 15 frozen sinks, including `manifest` and `working_memory`, against both router and working-memory carriers, producing the required 30 pairs.

I found no remaining F3 ratification blocker.

### F6 - PASS for the design gate

The call-graph implementation is a real stdlib-AST reachability analysis over the action-authorization modules and ordinary entry points rather than source-pattern counting.

A36 separately requires exactly one correctly shaped event and kills deletion and corruption/duplication faults. Boundary-B is explicitly treated as defense-in-depth rather than the decisive authorization boundary.

This does not remove the already-recorded activation gates for production logging, timing equalization, operating-system handles, or Windows store behavior.

## Frozen-contract assessment

I found **no need to reopen or amend a frozen `CONTEXT_PACKET_CONTRACT` or `MEMORY_CONTRACT` field**.

The failures are implementation and suite defects:

* F1 requires store immutability.
* F2 requires faithful handle-consumption modeling.
* F4 requires enforcement of the already-pinned closed GrantView.
* F5 requires preservation of existing packet fields rather than any packet-field change.
* F7 requires correct packaging.

All are `SUITE-BUILD before pass`. None is a freeze amendment, and none should be deferred as merely activation-gating.

## Final ratification statement

**FAIL - pack `5807bc3e-541b-4fd0-a9cd-cde6c82c4720` does not ratify contract s7.**

The gate must remain:

```text
build_status       = build_complete
p0_1_gate_status   = incomplete
activation_status  = prohibited
non_execution      = true
```

Five suite-build findings remain:

1. completion binding is overwriteable and externally mutable;
2. the effect path copies permit effects and merely tags them with a digest rather than consuming a trusted handle;
3. the 0.9 adapter is materially lossy;
4. the closed GrantView is not operationally enforced at the top level;
5. the transported tree omits `WORK_ORDER.md` and cannot pass its own empty-directory verification.

F3 and F6 are accepted as closed. The quantitative limit-intersection portion of F4 and the post-claim/terminal portion of F2 are also accepted, but their remaining holes independently prevent PASS.
