"""
integration.py -- REAL #36/#37/#40 producer->consumer integration (contract s8.7 crit 9 + 1; Finding 2).

Two producer generations are owned+run by the suite:

  * #40 0.7.0 (fixtures m40_070_pkt_*.json): the legacy flat packets. All carry non_execution=true, so
    the reference monitor DETERMINISTICALLY DENIES every one at A06.
  * #40 0.9.0 (fixtures m40_090_{routed,routed_adv,flat}.json): the CURRENT seam -- a routed +
    working-memory-hydrated packet (routing_stage_trace + a hydrated working_memory region +
    working_state_version in identity), its ADVERSARIAL authority-shaped variant, and its flat compile.
    These were captured from the REAL committed #40 0.9.0 compiler over the real #36 tree + #42 store
    (provenance in fixtures/real_packets/PROVENANCE.md); the suite never runs #40 live.

For 0.9.0 we run BOTH modes the red-team requires:
  (1) AUTHENTIC production-state (non_execution=true) -> A06 DENY, constant caller bytes, no permit, no diff.
  (2) An explicit TEST-ONLY authority variant (non_execution=false, s8.7 crit 1) that PRESERVES the real
      routing trace / working-memory region / state_version / evidence / packet identity and lets execution
      REACH A09/A11/A30/A31 + completion. Adversarial cases (routed_adv: authority-shaped working memory,
      cross-ns stage-trace, injected control-plane) with valid packet boundaries change NOTHING -- the
      decision + canonical digest are byte-identical to the benign routed variant.
"""

import glob
import json
import os

from action_authz import canon, stores as S
from action_authz.monitor import authorize
from action_authz.boundary import MockExecutor, evaluate_completion_via_permit
from . import harness
from . import adapter_090

_REAL_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "fixtures", "real_packets")


def _load(name):
    with open(os.path.join(_REAL_DIR, name), "r", encoding="utf-8") as fh:
        return json.load(fh)


def _real_070_packets():
    out = []
    for path in sorted(glob.glob(os.path.join(_REAL_DIR, "m40_070_*.json"))):
        out.append((os.path.basename(path), _load(os.path.basename(path))))
    return out


def _proposal_for(pkt, path):
    ident = pkt.get("identity", {})
    return {
        "schema": "lifeorch.action_proposal/0.1", "proposal_id": "prop_real",
        "task_id": ident.get("task_id"), "packet_id": pkt["packet_id"],
        "tool_id": "fs.local", "operation": "fs.write",
        "arguments": {"path": path, "content": "x"},
        "evidence_refs": [], "claimed_effects": [],
        "model_provenance": {"model_run_id": "run_real", "adapter_id": "adapter.chat",
                             "adapter_version": 1, "consumer_profile_fingerprint": "c" * 64,
                             "prompt_packet_id": pkt["packet_id"], "raw_output_hash": "d" * 64},
    }


def _run_real(pkt):
    """AUTHENTIC mode: adapt the real packet as-is (non_execution from the packet) -> A06 DENY."""
    st = S.Stores()
    pv = S.PacketStore.view_from_real_m40_packet(pkt)
    st.packets.put(pv)
    ti = pkt.get("task_input", {})
    prop = _proposal_for(pkt, "/u/data/%s/x.txt" % (ti.get("namespace") or "core-docs"))
    st.attest.put("run_real", "d" * 64, pkt["packet_id"], model_supplied_provenance=False)
    d = authorize(harness.prop_bytes(prop), st, mutations=frozenset())
    return d, len(st.permits._permits)


# --------------------------------------------------------------------------- 0.9.0 test-only authority
def _trusted_090(pkt, non_execution, disposition=None):
    """i40 Finding 5: delegate to the suite-owned EXACT context_packet/0.2 adapter, which PRESERVES the
    packet's corpus_version (A07 exercised), grant-snapshot identity, and full carriers; the only
    overlay is `non_execution`."""
    return adapter_090.build_trusted(pkt, non_execution_overlay=non_execution, disposition=disposition)


def _completion_contract_for(pkt, ns):
    gref = pkt.get("identity", {}).get("control_plane_grant_snapshot_ref")
    cc = {"schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc_090",
          "contract_version": 1, "task_id": pkt.get("identity", {}).get("task_id"),
          "effective_namespace": ns, "grant_snapshot_ref": gref, "packet_id": pkt["packet_id"],
          "root": {"kind": "leaf", "completion_scope": "permit", "predicate": {
              "predicate_id": "p1", "predicate_kind": "executor_status", "source_id": "exec.fs/1",
              "source_version": 1, "subject_binding": {}, "max_age_ms": 60000,
              "expected": {"allowed_result_codes": ["ok"], "allowed_exit_codes": [0]}}},
          "trusted_status_sources": [{"source_id": "exec.fs/1", "source_version": 1,
                                      "status_schema": "s/1", "code_digest": "a" * 64, "max_age_ms": 60000}],
          "evaluation_policy": {"missing": "indeterminate", "malformed": "indeterminate",
                                "stale": "indeterminate", "indeterminate_is_complete": False}}
    cc["contract_digest"] = canon.digest_omitting(cc, "contract_digest")
    return cc


def run(check):
    results = []

    # ===== #40 0.7.0 legacy flat chain: every authentic packet DENIES at A06 =====================
    reals = _real_070_packets()
    check.ok("real #40 0.7.0 packets present", len(reals) >= 1, "found=%d" % len(reals))
    for name, pkt in reals:
        check.ok("%s is context_packet/0.2" % name, pkt.get("schema") == "lifeorch.context_packet/0.2")
        check.ok("%s carries non_execution=true" % name, pkt.get("non_execution") is True)
        d, n = _run_real(pkt)
        check.ok("%s -> deterministic DENY at A06" % name,
                 d.outcome == "DENY" and (d.reason_code or "").startswith("A06"), "reason=%s" % d.reason_code)
        check.ok("%s -> constant caller bytes" % name, d.caller_bytes == S.CONSTANT_DENIAL_BYTES)
        check.ok("%s -> no permit issued" % name, n == 0)
        results.append({"packet": name, "packet_id": pkt["packet_id"],
                        "compiler_version": pkt.get("identity", {}).get("compiler_version"),
                        "outcome": d.outcome, "reason": d.reason_code})

    # ===== #40 0.9.0 authentic chain (routed + working-memory hydrated) ==========================
    routed = _load("m40_090_routed.json")
    routed_adv = _load("m40_090_routed_adv.json")
    flat = _load("m40_090_flat.json")
    ns09 = (routed.get("task_input", {}) or {}).get("namespace") or "nsa"

    # structural: the routed packet really carries the 0.9.0 seam we are testing against.
    check.ok("0.9.0 routed compiler_version==0.9.0",
             routed.get("identity", {}).get("compiler_version") == "0.9.0")
    check.ok("0.9.0 routed HYDRATED working_memory (present, state_version=2)",
             (routed.get("working_memory") or {}).get("present") is True
             and (routed.get("working_memory") or {}).get("state_version") == 2)
    check.ok("0.9.0 routed carries the router stage-trace (3 records)",
             isinstance((routed.get("evaluation_hooks") or {}).get("routing_stage_trace"), list)
             and len((routed.get("evaluation_hooks") or {}).get("routing_stage_trace")) == 3)
    check.ok("0.9.0 routed identity.working_state_version==2",
             routed.get("identity", {}).get("working_state_version") == 2)

    # (1) AUTHENTIC (non_execution=true) -> A06 DENY for routed / routed_adv / flat.
    for nm, pkt in (("m40_090_routed", routed), ("m40_090_routed_adv", routed_adv), ("m40_090_flat", flat)):
        check.ok("%s carries non_execution=true" % nm, pkt.get("non_execution") is True)
        d, n = _run_real(pkt)
        check.ok("%s -> deterministic DENY at A06" % nm,
                 d.outcome == "DENY" and (d.reason_code or "").startswith("A06"), "reason=%s" % d.reason_code)
        check.ok("%s -> constant caller bytes" % nm, d.caller_bytes == S.CONSTANT_DENIAL_BYTES)
        check.ok("%s -> no permit issued" % nm, n == 0)
        results.append({"packet": nm + ".json", "packet_id": pkt["packet_id"],
                        "compiler_version": pkt.get("identity", {}).get("compiler_version"),
                        "outcome": d.outcome, "reason": d.reason_code})

    # (2) TEST-ONLY authority variant (non_execution=false): execution REACHES A09/A11/A30/A31 + issue.
    st, prop, pv = _trusted_090(routed, non_execution=False)
    st.completion_by_packet[pv.packet_id] = _completion_contract_for(routed, ns09)
    d_ok = authorize(harness.prop_bytes(prop), st, mutations=frozenset())
    check.ok("0.9.0 test-only non_execution=false routed -> PERMIT (reaches A09/A11/A30/A31/A34)",
             d_ok.outcome == "PERMIT", "reason=%s" % d_ok.reason_code)
    check.ok("0.9.0 permit is bound to the REAL packet_id", d_ok.outcome == "PERMIT"
             and d_ok.permit["packet_id"] == routed["packet_id"])
    # execute the permit -> Boundary D (all-epoch recheck) consumes exactly one action.
    if d_ok.outcome == "PERMIT":
        ex = MockExecutor(st)
        r = ex.execute(d_ok.permit_ref, mutations=frozenset())
        check.ok("0.9.0 test-only permit executes -> exactly one consumed action + a state diff",
                 r.accepted and r.state_diff != [] and r.consumed_permit_id == d_ok.permit["permit_id"])
        # completion is REACHED and binds via the immutable packet_id (indeterminate without status).
        v0 = evaluate_completion_via_permit(st, d_ok.permit)
        check.ok("0.9.0 completion reached, indeterminate without trusted status", v0 == "indeterminate")
        st.status.put({"predicate_kind": "executor_status", "result_code": "ok", "exit_code": 0,
                       "source_id": "exec.fs/1", "source_version": 1, "at_ms": st.clock.now_ms(),
                       "namespace": ns09, "subject": {"task_id": d_ok.permit["task_id"],
                       "canonical_action_digest": d_ok.permit["canonical_action_digest"],
                       "permit_id": d_ok.permit["permit_id"]}})
        v1 = evaluate_completion_via_permit(st, d_ok.permit)
        check.ok("0.9.0 completion true ONLY via the exact-permit trusted status", v1 == "true")

    # (2b) ADVERSARIAL routed_adv (authority-shaped wm + cross-ns trace + injected control-plane) with
    # valid packet boundaries -> the DECISION + canonical digest are byte-identical to the benign routed.
    st_adv, prop_adv, _ = _trusted_090(routed_adv, non_execution=False)
    d_adv = authorize(harness.prop_bytes(prop_adv), st_adv, mutations=frozenset())
    check.ok("0.9.0 adversarial routed_adv -> SAME outcome as benign routed",
             d_adv.outcome == d_ok.outcome, "adv=%s benign=%s" % (d_adv.outcome, d_ok.outcome))
    check.ok("0.9.0 adversarial routed_adv -> SAME canonical_action_digest (carriers cannot launder)",
             d_adv.cad == d_ok.cad, "adv=%s benign=%s" % (d_adv.cad, d_ok.cad))

    # (2c) R1-ROLE-1 at the REAL seam: a non-answerable 0.9.0 packet whose ONLY 'coverage' is the real
    # router stage-trace + hydrated working memory still DENIES at A31 (carriers never satisfy evidence).
    st_r1, prop_r1, _ = _trusted_090(routed, non_execution=False, disposition="needs_expansion")
    d_r1 = authorize(harness.prop_bytes(prop_r1), st_r1, mutations=frozenset())
    check.ok("0.9.0 non-answerable + real routing/wm carriers -> A31 DENY (R1-ROLE-1)",
             d_r1.outcome == "DENY" and (d_r1.reason_code or "").startswith("A31"),
             "reason=%s" % d_r1.reason_code)

    # ===== i40 Finding 5: the EXACT context_packet/0.2 adapter is decisive at the real seam =========
    # (5a) A07 is EXERCISED (the current_corpus_version=None bypass is gone): the adapter PRESERVES the
    # packet's corpus_version, so a corpus-drift denies at A07.
    st_cv, prop_cv, pv_cv = adapter_090.build_trusted(routed, non_execution_overlay=False)
    check.ok("0.9.0 adapter PRESERVES corpus_version (== packet identity)",
             st_cv.current_corpus_version == routed["identity"]["corpus_version"]
             and pv_cv.corpus_version == routed["identity"]["corpus_version"])
    st_cv.current_corpus_version = "corpus_DRIFT"            # a drift the adapter did NOT introduce
    d_cv = authorize(harness.prop_bytes(prop_cv), st_cv, mutations=frozenset())
    v090_a07 = d_cv.outcome == "DENY" and (d_cv.reason_code or "").startswith("A07")
    check.ok("0.9.0 adapter: corpus drift -> A07 DENY (A07 EXERCISED, not bypassed)", v090_a07,
             "reason=%s" % d_cv.reason_code)

    # (5b) the adapter does NOT rewrite the packet's grant-snapshot identity (id AGREES with the packet).
    gref_pkt = routed["identity"]["control_plane_grant_snapshot_ref"]
    st_id, _, pv_id = adapter_090.build_trusted(routed, non_execution_overlay=False)
    check.ok("0.9.0 adapter: trusted grant-snapshot id AGREES with the packet (not rewritten)",
             pv_id.grant_snapshot_ref == gref_pkt and gref_pkt in st_id.grants)

    # (5c) the two-boolean reduction is RETIRED: the full carriers cross into the trusted meta as DATA.
    meta = adapter_090.full_meta(routed)
    v090_carriers = (isinstance(meta.get("routing_stage_trace"), list) and len(meta["routing_stage_trace"]) == 3
                     and isinstance(meta.get("working_memory_items"), list) and len(meta["working_memory_items"]) == 1
                     and isinstance(meta.get("evidence_excerpts"), list) and len(meta["evidence_excerpts"]) == 3
                     and meta.get("working_state_version") == 2
                     and isinstance(meta.get("namespace_closure"), dict))
    check.ok("0.9.0 adapter PRESERVES full carriers as DATA (trace/wm items/evidence/state_version/ns)",
             v090_carriers)

    # (5d) INERTNESS at EVERY R1 sink through the exact seam. The REAL carriers (routing stage-trace +
    # hydrated working memory) are present in the authentic packet's meta. For EVERY (carrier, sink)
    # pair we run the corresponding R1-ROLE-1 laundering defect `M-RC-<carrier>-<sink>` through THIS
    # exact seam and assert the decision + canonical digest are IDENTICAL to the reference -- the real
    # carriers cannot launder authority into ANY of the 15 sinks. (role_matrix additionally proves each
    # sink defect is DECISIVELY killed in a scenario where that sink's check is the deciding gate.)
    from action_authz.monitor import RC_SINKS
    st_ref, prop_ref, _ = adapter_090.build_trusted(routed, non_execution_overlay=False)
    d_ref = authorize(harness.prop_bytes(prop_ref), st_ref, mutations=frozenset())
    inert_all = (d_ref.outcome == "PERMIT")
    for sink in RC_SINKS:
        for tag in ("RT", "WM"):
            defect = "M-RC-%s-%s" % (tag, sink.upper())
            st_s, prop_s, _ = adapter_090.build_trusted(routed, non_execution_overlay=False)
            d_s = authorize(harness.prop_bytes(prop_s), st_s, mutations=frozenset([defect]))
            if not (d_s.outcome == d_ref.outcome and d_s.cad == d_ref.cad):
                inert_all = False
    check.ok("0.9.0 exact seam: real carriers INERT at EVERY R1 sink "
             "(no M-RC-*-<sink> defect over the authentic carriers alters the decision/cad)", inert_all)
    v090_exact_adapter = bool(v090_a07 and v090_carriers and inert_all
                              and pv_id.grant_snapshot_ref == gref_pkt)

    # ===== i41 round-3 Finding 5: the LOSSLESS context_packet/0.2 seam ===========================
    # The i40 adapter preserved only a subset, so two materially different authentic packets could
    # collapse into the same trusted representation. adapter_090.adapt_packet_lossless preserves the
    # COMPLETE packet (canonical bytes + an identity digest over the whole packet), so changing ANY field
    # is detected; the packet round-trips byte-identically; the ONLY overlay is non_execution. We run BOTH
    # generations -- authentic 0.7.0 (x4) AND 0.9.0 (benign routed + adversarial routed_adv + flat) --
    # through THIS exact seam.
    def _perturb(v):
        if isinstance(v, bool):
            return not v
        if isinstance(v, str):
            return v + "_MUT"
        if isinstance(v, int):
            return v + 1
        if isinstance(v, list):
            return list(v) + ["__MUT__"]
        if isinstance(v, dict):
            return dict(v, __mut__=1)
        return "__MUT__"

    def _mut_copy(pkt, path):
        cp = json.loads(json.dumps(pkt))
        node = cp
        for k in path[:-1]:
            node = node[k]
        node[path[-1]] = _perturb(node[path[-1]])
        return cp

    all_authentic = [p for _n, p in reals] + [routed, routed_adv, flat]
    lossless_ok = True
    for pkt in all_authentic:
        try:
            pp = adapter_090.adapt_packet_lossless(pkt)
        except adapter_090.LosslessError:
            lossless_ok = False
            continue
        # round-trip byte-identity: the preserved representation re-derives the packet exactly.
        if pp.complete != pkt or canon.canonical_bytes(pp.complete) != pp.canonical:
            lossless_ok = False
        if pp.view.packet_id != pkt["packet_id"] or pp.packet_id != pkt["packet_id"]:
            lossless_ok = False
    check.ok("lossless seam: every authentic 0.7.0+0.9.0 packet round-trips byte-identically (%d packets)"
             % len(all_authentic), lossless_ok)

    # PER-IDENTITY-FIELD MUTATION: changing ANY identity-covered field alters the preserved identity
    # digest (or fails closed). The FIVE probes the reviewer proved inert in i40 are now DETECTED.
    base_digest = adapter_090.adapt_packet_lossless(routed).identity_digest
    per_field_ok = True
    for f in adapter_090._IDENTITY_CORE:
        mp = _mut_copy(routed, ["identity", f])
        try:
            if adapter_090.adapt_packet_lossless(mp).identity_digest == base_digest:
                per_field_ok = False
        except adapter_090.LosslessError:
            pass  # fail-closed is an acceptable detection (per the exact-closure requirement)
    named_probes = (["identity", "compiler_version"], ["identity", "selection_policy"],
                    ["retrieval_provenance"], ["evidence", "current_state_refs"], ["selection", "stages"])
    probes_detected = True
    for path in named_probes:
        mp = _mut_copy(routed, path)
        try:
            if adapter_090.adapt_packet_lossless(mp).identity_digest == base_digest:
                probes_detected = False
        except adapter_090.LosslessError:
            pass
    check.ok("lossless seam: mutating ANY identity-covered field alters the preserved identity digest",
             per_field_ok)
    check.ok("lossless seam: the 5 i40-inert probes (compiler_version/selection_policy/"
             "retrieval_provenance/evidence.current_state_refs/selection.stages) are now DETECTED",
             probes_detected)

    # OVERLAY-ONLY: the test-only authority overlay changes ONLY non_execution (never the preserved packet
    # bytes / identity digest); the derived view's non_execution flips.
    pp_t = adapter_090.adapt_packet_lossless(routed, non_execution_overlay=True)
    pp_f = adapter_090.adapt_packet_lossless(routed, non_execution_overlay=False)
    overlay_only = (pp_t.identity_digest == pp_f.identity_digest and pp_t.canonical == pp_f.canonical
                    and pp_t.view.non_execution is True and pp_f.view.non_execution is False)
    check.ok("lossless seam: the overlay alters ONLY non_execution (identity digest + bytes unchanged)",
             overlay_only)

    # the 0.9.0 routed generation's extra identity carriers (routing_plan_digest/routing_policy) are present.
    routed_carriers = adapter_090.require_routed(routed) and adapter_090.require_routed(routed_adv)
    check.ok("lossless seam: 0.9.0 routed identity carriers (routing_plan_digest/routing_policy) preserved",
             routed_carriers)

    v090_lossless_adapter = bool(lossless_ok and per_field_ok and probes_detected and overlay_only
                                 and routed_carriers)

    # ===== positive permit path via the TEST-ONLY mock packet + the same-code non_execution=true deny ==
    st, prop = harness.build_baseline()
    dp = authorize(harness.prop_bytes(prop), st, mutations=frozenset())
    positive = (dp.outcome == "PERMIT" and dp.permit["packet_id"] == "cpkt_test0001")
    check.ok("positive permit path via test-only non_execution=false packet", positive)
    st2, prop2 = harness.build_baseline()
    st2.packets.verify_and_get("cpkt_test0001").non_execution = True
    d2 = authorize(harness.prop_bytes(prop2), st2, mutations=frozenset())
    check.ok("same packet with non_execution=true -> A06 DENY",
             d2.outcome == "DENY" and (d2.reason_code or "").startswith("A06"))

    return {"real_denied": sum(1 for r in results if r["outcome"] == "DENY"),
            "real_total": len(results), "positive_permit": positive,
            "v090_test_only_permit": bool(d_ok.outcome == "PERMIT"),
            "v090_adversarial_identical": bool(d_adv.cad == d_ok.cad and d_adv.outcome == d_ok.outcome),
            "v090_exact_adapter": v090_exact_adapter, "v090_a07_exercised": bool(v090_a07),
            "v090_lossless_adapter": v090_lossless_adapter,
            "results": results}
