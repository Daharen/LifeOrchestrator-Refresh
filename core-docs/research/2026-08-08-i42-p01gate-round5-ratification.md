# i42 P0-1 action-authorization ROUND-5 RATIFICATION review -- couriered frontier answer (pack 6bb613ea)

**Status:** captured verbatim via frontier.bridge read-return (pack_id_match=true, captured/valid; D-0052 human-courier lane). DESIGN ONLY -- `non_execution:true` holds. **Verdict: PASS -- ratify contract s7 to `p0_1_gate_status=pass`** (`activation_status=prohibited` UNCHANGED). The reviewer INDEPENDENTLY reconstructed all 47 pack files and ran `run_suite.py` (364/364, bundle `3b5d62f426143b29`) + `selfverify.py` (VERIFIED:True) from an EMPTY DIR, and confirmed F5/F4/F2 CLOSED + F1/F3/F6/F7 + the D-0109 regression PASS + NO frozen-contract reopen. Convergence: 7 (i38) -> 7 (i39) -> 5 (i40) -> 3 (i41) -> 0 (i42). Non-blocking note: F5's `build_trusted()` lives in `tests/adapter_090.py`, not `boundary.py` (a path-label typo, not a finding). This ratification is folded as D-0118. Companions: `research/2026-08-07-i41-p01gate-round4-redteam.md` (D-0116) + predecessors.

---
# Round-5 Ratification Verdict: **PASS**

**Pack / invocation:** `6bb613ea-7306-4986-87df-e4a8db05d12f`

**Ratification decision:** The orchestrator may ratify contract s7 to:

`build_status = build_complete`
`p0_1_gate_status = pass`
`activation_status = prohibited`

This is a **design-gate PASS only**. It does not authorize activation: `non_execution:true` remains in force, exactly as the pack requires. 

I found **no remaining SUITE-BUILD finding and no FREEZE-AMENDMENT finding**.

* **F7 — PASS / CLOSED.** I reconstructed all **47 embedded files** from the courier pack into a fresh directory and verified them against their declared byte sizes and SHA-256 prefixes. From that exact reconstruction, `python -X utf8 -B tests/run_suite.py` exited **0** with **364/364**, 69/69 mutations killed, 152 oracle rows with `not_run=0`, 30/30 role matrix, 21/21 completion, 64/64 views, 60/60 integration, 86/86 fixtures, and the expected bundle digest **`3b5d62f426143b29`**. I then ran `python -X utf8 -B tests/selfverify.py`; it exited **0**, independently rebuilt into an empty directory, reproduced the same manifest digest, reported byte-identical manifests/source/fixture digests and ended **`VERIFIED: True`**. This satisfies the exact Round-5 transport requirement. 

* **F5 — PASS / CLOSED.** The actual monitor-facing construction seam now genuinely starts with `adapt_packet_lossless()`, operates from `pp.complete`, derives its view/meta from that preserved/re-parsed object, and binds the whole-packet identity digest into `PacketView.content_digest`, packet metadata, `st.packet_identity`, and the retained preserved packet.  The suite then drives the complete identity set plus the five specifically named probes—`compiler_version`, `selection_policy`, `retrieval_provenance`, `evidence.current_state_refs`, and `selection.stages`—through **`build_trusted()` itself**, requiring a distinguishable trusted representation or fail-closed result.  I separately exercised that probe set against the reconstructed tree; no collapse remained. **The Round-4 real-seam defect is closed.**

* **F4 — PASS / CLOSED.** `GrantSnapshot._valid_grants()` is now the single shared ingress used by both `grant_namespaces()` and `match()`, and a grant is yielded only after `_grant_view_wellformed()` succeeds. Thus `grant_id`, `action_namespace`, and the other operational fields are not dereferenced before validation.  The validator itself requires exactly the closed top-level field set and verifies the operational types rather than merely describing them.  I independently deleted every closed top-level field one at a time and also tested unknown/mistyped/malformed cases; each failed closed rather than creating an A11 exception or authorization path. The previously accepted quantitative limit algebra remains intact.

* **F2 — PASS / CLOSED.** `derive_operation_effects()` obtains prospective effects from the installed manifest's classifier using the permit's canonical operation arguments and bound targets—not from `authorized_effect_set`.  Those prospective effects are passed through `apply_effects_through_handles()`, which consumes the one-shot `TargetHandle` and returns the applied atoms with capability-derived target identity and consumption proof.  Only afterward is that returned ledger compared against `authorized_effect_set` as the D7 authorization bound. The explicit M-E38 successor mutation consumes the handle but throws away that result and blind-copies the authorization set; the resulting provenance is detectably wrong.  The dedicated `sec_e38` oracle tests exactly the missing handle-derived target/proof properties.  I independently compared the normal and M-E38 paths; normal passes the provenance oracle and M-E38 fails it. **M-E38 is decisively killed.**

* **F1/F3/F6/F7 and D-0109 regression — PASS.** F1 remains write-once/defensive-copy bound and completion remains 21/21. F3 remains the full **30/30** two-carrier × 15-sink role matrix, including the previously omitted `manifest` and `working_memory` sinks. F6 retains the actual stdlib-AST call-graph no-authority path; I independently ran its call-graph summary and the authority constructor remained unreachable from the audited entrypoints. The oracle still requires exactly one correctly shaped A36 audit event, with deletion and corruption/duplication faults, and Boundary-B rows mutate the real render path rather than a synthetic substitute.  `exact_closure_built.finding_1..finding_7` are all still true; the Round-3 and Round-4 closure flags are likewise all true. The previous review explicitly left F1/F7 closed while defining only F5/F4/F2 as the remaining blockers, and those three are now satisfied. 

* **Frozen-contract consistency — PASS.** I found no change that requires reopening a `CONTEXT_PACKET_CONTRACT` or `MEMORY_CONTRACT` field. F5 preserves more of the existing packet at the action-boundary seam; F4 strengthens validation of the action-layer test GrantView; F2 strengthens the logical Boundary-D effect-applicator model. None widens packet authority, rewrites the evidence corpus, changes memory semantics, or relaxes `non_execution`. The remaining real Windows permit-store/IPC/ACL/CAS/crash-recovery work, per-tool target/reparse/ADS/device profiles, production stores/status/log contracts, freshness relaxation, timing-channel work, rollback, and the actual `non_execution=false` transition remain **ACTIVATION-gating**, consistent with a design PASS while activation remains prohibited. 

### Non-blocking documentation note

The pack's opening summary calls the F5 function `action_authz/boundary.py build_trusted()`, but the audited `build_trusted()` implementation actually resides in `tests/adapter_090.py`. The substantive SCHEMA/test material points to the correct implementation. I classify this as a **documentation/path-label typo only**, not a suite-build, freeze, or activation finding.

**Final disposition: `PASS`. Ratify s7 for pack `6bb613ea-7306-4986-87df-e4a8db05d12f` to `p0_1_gate_status=pass`. Keep `activation_status=prohibited` and `non_execution:true`.**
