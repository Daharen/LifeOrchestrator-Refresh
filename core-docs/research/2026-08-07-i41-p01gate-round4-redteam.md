# i41 P0-1 action-authorization ROUND-4 RATIFICATION review -- couriered frontier answer (pack 678163b1)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match, captured/valid, sha256 56a7eb31..; D-0052 human-courier lane). DESIGN ONLY -- `non_execution:true` holds. **Verdict: FAIL -- do NOT ratify contract s7; `p0_1_gate_status` stays `incomplete`** (M2-D: third consecutive round with NOTHING to walk back). **Convergence: 7 (i38) -> 7 (i39) -> 5 (i40) -> 3 (this round).** ACCEPTED AS CLOSED this round: **F1** (write-once completion binding) and **F7** (pack transport -- the manifest-derived, empty-dir pre-verified pack ran CLEAN for the reviewer: 49/49 files byte-recoverable incl. WORK_ORDER.md, both documented commands exit 0, bundle `ab831c85..` reproduced -- the D-0113 F7 rule PROVEN in its first live round); F3/F6 + the accepted F4 limit-algebra and F2 post-claim portions REMAIN closed. **3 SUITE-BUILD findings remain (none reopens a frozen field) -> the next #43 unit (0.5.0 -> 0.6.0):** (1) **F5 REAL-SEAM losslessness** -- `adapt_packet_lossless()` is correct but `build_trusted()` bypasses it (still derives PacketView/meta from the raw packet; the 5 probes collapse at the monitor-facing seam): the trusted construction path must BEGIN with the lossless adapter, derive view/meta ONLY from the preserved re-parsed packet, bind the whole-packet identity digest into trusted state, and re-run the per-field + 5 named probes through THAT end-to-end path; (2) **F4 PRE-VALIDATION** -- `grant_namespaces()` dereferences raw `grant_id`/`action_namespace` at A11 BEFORE `match()`'s validation (missing fields -> uncaught KeyError, not constant DENY): validate at GrantSnapshot ingress or via ONE shared validated iterator; end-to-end authorize() vectors (unknown/missing/mistyped/malformed) -> constant DENY, no exception, no permit, no state diff; (3) **F2 LEDGER PROVENANCE** -- consumption is genuinely one-shot but the ledger still originates from `authorized_effect_set` copy: the applicator must consume handle + canonical operation args and RETURN the effect atoms; `authorized_effect_set` becomes an authorization bound/comparison, never the template; a SUCCESSOR MUTANT (consume-but-discard-result + blind-copy) must be decisively killed (the reviewer's stronger defective implementation currently passes sec_e37). Minor non-blocking: the pack's summary numbers lagged the tree (completion 17/17 / views 48/48 vs the actual 21/21 / 56/56) -- round-5 packs derive as-built numbers FROM report.json. Companions: `research/2026-08-06-i40-p01gate-round3-redteam.md` (D-0113) + predecessors.

---
# ROUND-4 RATIFICATION REVIEW — P0-1 Action-Authorization Gate

**Received pack:** invocation `678163b1-7359-45ce-9c9c-94bf5a764496`
**Verdict: FAIL — do not ratify contract s7.**

The required state remains:

```text
build_status       = build_complete
p0_1_gate_status   = incomplete
activation_status  = prohibited
non_execution      = true
```

The pack explicitly makes this review the ratification event and requires a PASS before s7 may move to `p0_1_gate_status=pass`.

## Independent reconstruction and execution

I reconstructed the received pack rather than relying on its embedded transcripts. All **49/49 files are byte-recoverable against their declared size/hash prefixes**: 42 use LF and 7 use CRLF in their original representation. `WORK_ORDER.md` is present, and the runnable manifest explicitly requires it.

From a newly reconstructed `modules/43-action-authz` tree I independently ran:

```text
python -X utf8 -B tests/run_suite.py
python -X utf8 -B tests/selfverify.py
```

Both exited **0**. My observed suite was **352/352**, mutations **68/68**, fuzzer **400/0**, oracle **150 rows / 0 not_run**, role matrix **30/30**, completion **21/21**, views **56/56**, with bundle digest beginning `ab831c852fa172e4`. `selfverify.py` independently rebuilt an empty temp tree, reproduced the same manifest digest, and reported `VERIFIED: True`.

Therefore **F7 is CLOSED**. The prior transport failure is not present in this pack.

There is a minor non-blocking reporting discrepancy: the pack's introductory summary still says completion `17/17` and views `48/48`, whereas the received executable tree now produces `21/21` and `56/56`. This should be updated for evidentiary consistency, but it is not itself the reason for FAIL. The pack's stated transport claim and required commands are recorded here.

## Ranked blocking findings

1. **F5 — the new lossless representation exists, but the actual trusted integration seam still bypasses it.**
   **Class: SUITE-BUILD before pass. Severity: ratification blocker.**

   `adapt_packet_lossless()` itself is substantially correct: it validates the core, preserves the entire packet as canonical bytes, hashes those bytes, re-parses the complete packet, and derives its view/meta from the packet.

   The problem is that the **actual trusted construction path does not use it**. `build_trusted()` still takes the raw packet and directly calls `adapt_packet_view(pkt)` and `full_meta(pkt)`, then places only those reduced structures into the trusted stores. It never obtains or retains the `PreservedPacket`, its canonical bytes, or its whole-packet identity digest.

   I reproduced the exact five formerly-inert probes against the received code: `identity.compiler_version`, `identity.selection_policy`, `retrieval_provenance`, `evidence.current_state_refs`, and `selection.stages`. In every case, `adapt_packet_lossless()` correctly produced a different identity digest — **but `build_trusted()` produced an identical PacketView, identical packet metadata, identical authorization outcome, and identical CAD**. In other words, two materially different authentic packets still collapse at the trusted seam that actually feeds the monitor.

   The current integration tests prove that the sidecar lossless object notices mutations, but not that the monitor-facing trusted representation cannot collapse them; those tests explicitly mutate fields and compare `adapt_packet_lossless(...).identity_digest`.

   **Exact closure required:** make the actual 0.7.0/0.9.0 trusted construction path begin with `adapt_packet_lossless()`. Derive PacketView and metadata only from the preserved/reparsed packet, and retain or bind the whole-packet canonical identity in the trusted adapter state so it cannot be discarded before consumption. Then run the per-field and five named mutations through **that same end-to-end build path** and require either fail-closed or a distinguishable trusted representation. This requires no `CONTEXT_PACKET_CONTRACT` field change.

2. **F4 — the top-level GrantView validator is real, but it runs too late to protect all operational reads.**
   **Class: SUITE-BUILD before pass. Severity: ratification blocker.**

   `_grant_view_wellformed()` correctly defines the exact closed field set and rejects unknown/missing/mistyped values, and `GrantSnapshot.match()` invokes it before doing its matching logic.

   But `GrantSnapshot.grant_namespaces()` directly dereferences `g["action_namespace"]` and `g["grant_id"]` without validation. The monitor calls that method at **A11**, before the later grant match.

   I reproduced this against the positive/test-only path. Removing `scopes` or corrupting `risk_ceiling` eventually gives a clean A26 denial because those fields survive until `match()`. But removing either `grant_id` or `action_namespace` causes an uncaught **`KeyError`** in `grant_namespaces()` instead of deterministic constant denial. Thus the claim that *all missing/mistyped/malformed top-level values fail closed operationally* is not yet true.

   The test blind spot is visible in `views_golden.py`: the new F4 vectors call `GrantSnapshot.match()` directly. They therefore prove the validator is load-bearing **inside the matcher**, but do not exercise the earlier A11 access.

   **Exact closure required:** validate grants before *any* operational consumption — preferably once at trusted GrantSnapshot ingress, or through one validated-grant iterator shared by both `grant_namespaces()` and `match()`. No raw grant field may be dereferenced before validation. Add end-to-end `authorize()` vectors for unknown, missing `grant_id`, missing `action_namespace`, and representative mistyped/malformed fields, requiring constant DENY, no exception, no permit, and no state diff. The existing validator pin and limit algebra can remain unchanged.

3. **F2 — one-shot handle consumption is now genuine, but the ledger-origin requirement is still not proved.**
   **Class: SUITE-BUILD before pass. Severity: ratification blocker.**

   This round does materially improve F2. `TargetHandle` is now a distinct object, `consume()` is genuinely one-shot, and the executor observes consumed handles. That portion is closed.

   However, the prior exact closure did not merely require *also consuming a handle*. It required the effect ledger to be generated **from the handle-bound applicator result, not from `permit["authorized_effect_set"]`**. That requirement is explicitly preserved in the prior finding.

   The received executor still begins its prospective effects with:

   ```python
   actual = list(permit["authorized_effect_set"])
   ```

   and sends that list into `apply_effects_through_handles()`. Inside the applicator, the reference implementation consumes the handle but then builds each ledger atom via `atom = dict(e)` from that supplied permit effect, adding only the consumed handle's tag.

   Therefore the substantive architecture is presently **authorized-effect copy + genuine handle consumption**, rather than an effect operation whose independently produced result becomes the ledger.

   I tested the oracle directly with a stronger defective implementation: consume each `TargetHandle`, **ignore the value returned by `consume()`**, then blindly copy the authorized effect and read the digest directly from the handle. Both `sec_e37` and the `Boundary-D3:D4_handle_consumed` oracle still PASS under that defect. The reason is visible in `sec_e37`: it checks that the ledger has the expected tag and that handles are marked consumed, but never establishes that the ledger's effect atoms originated from the consumed capability's applicator result.

   **Exact closure required:** the mock effect applicator should consume a `TargetHandle` together with the operation's canonical arguments/operation semantics and itself return the actual effect atom(s). The permit's `authorized_effect_set` should then be used as an authorization bound/comparison against that returned result, not as the source template used to manufacture the result. Strengthen M-E37 or add a mandatory successor mutant which **does consume the handle but then discards the applicator result and blind-copies `authorized_effect_set`**. That mutant must be decisively killed. Real OS handles remain activation-gating; this is only the logical Boundary-D model.

## Closures accepted

**F1 is CLOSED within the stated mock/build scope.** `record_completion_binding()` now rejects every sequential second write, stores canonical immutable bytes, and `completion_binding()` re-parses a fresh object. The suite now explicitly verifies valid-binding replacement rejection, getter mutation isolation, and duplicate-identical recording rejection. The original sentinel-overwrite path also passes. I do not treat real concurrent IPC/CAS atomicity as a renewed F1 suite-build blocker because the production Windows permit-store atomicity remains explicitly activation-gating.

**F7 is CLOSED**, as described above. **F3 and F6 remain accepted as closed** from round 3; I found no regression requiring them to be reopened. The previously accepted quantitative limit-intersection portion of F4 also remains closed, as does the post-claim/terminal-rejection portion of F2.

## Frozen-contract assessment

I found **no requirement to reopen or amend a frozen `CONTEXT_PACKET_CONTRACT` or `MEMORY_CONTRACT` field**.

The three remaining blockers are implementation/seam issues: F5 requires actually carrying the already-existing complete packet representation through the adapter boundary; F4 requires validating the already-pinned GrantView before every operational read; F2 requires making the mock effect result genuinely originate at the handle-bound applicator instead of the authorized-effect declaration.

The existing activation gates therefore remain activation gates rather than being promoted into this ratification failure: production Windows IPC/ACL/CAS/crash recovery, real per-tool reparse/ADS/junction/device handles and profiles, production storage/status/log contracts, freshness relaxation, the actual `non_execution=false` transition, physical timing channels, and rollback. The received pack itself records these as still staged while `non_execution:true` holds.

## Final ratification statement

**FAIL — the round-4 pack identified by invocation `678163b1-7359-45ce-9c9c-94bf5a764496` does not ratify contract s7.**

The honest state remains `build_complete | p0_1_gate_status=incomplete | activation_status=prohibited`.

Three `SUITE-BUILD before pass` findings remain: **F5 actual-seam losslessness, F4 pre-validation GrantView access, and F2 independent handle-bound ledger provenance**. F1 and F7 are closed; F3/F6 remain closed. None of the three remaining fixes requires a freeze amendment.

