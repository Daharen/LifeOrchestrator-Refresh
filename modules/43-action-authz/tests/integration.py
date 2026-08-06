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
def _fs_write_op(evidence_dependency="none"):
    op = harness.make_operation()
    op["evidence_dependency"] = evidence_dependency
    return op


def _trusted_090(pkt, non_execution, disposition=None):
    """Build a FULL trusted authority config CONSISTENT with a real 0.9.0 packet's task/namespace, with
    an explicit non_execution (TEST-ONLY when False). Preserves the packet's own identity/task_id; the
    disposition (A08/A31) is taken from the real packet unless overridden."""
    ns = (pkt.get("task_input", {}) or {}).get("namespace") or "nsa"
    st = S.Stores()
    st.current_corpus_version = None                          # skip A07 corpus-drift (real cv differs)
    pv = S.PacketStore.view_from_real_m40_packet(pkt, non_execution=non_execution)
    pv.grant_snapshot_ref = "grant_snap_090"                  # bind to a grant snapshot we control
    st.packets.put(pv)
    meta = S.PacketStore.meta_from_real_m40_packet(pkt)
    if disposition is not None:
        meta["disposition"] = disposition
        meta["retrieval_complete"] = (disposition == "answerable")
    st.packet_meta = {pv.packet_id: meta}
    st.completion_contracts = {}
    st.attest.put("run_real", "d" * 64, pv.packet_id, model_supplied_provenance=False)
    op = _fs_write_op(evidence_dependency="packet_answerable")
    st.manifests.register(S.build_manifest("fs.local", [op]))
    st.health.put("health.fs/1", "ok", st.clock.now_ms())
    st.resolve_ctx.path_ns = [("/u/%s" % ns, ns)]
    st.grants["grant_snap_090"] = S.GrantSnapshot(
        "grant_snap_090",
        grants=[{"grant_id": "g_090", "tool_id": "fs.local", "operation": "fs.write",
                 "action_namespace": ns, "allowed_target_ids": ["/u/%s/one.txt" % ns],
                 "effect_classes": ["fs.write"], "max_quantity": {"fs.write": 1048576},
                 "externality_max": "local", "risk_ceiling": 2, "validity_from": 0,
                 "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
                 "scopes": ["fs.write"], "limits": [{"limit_id": "fs.write", "max_value": 1048576}]}],
        request_namespaces=[ns])
    st.policies["policy_090"] = S.PolicyView("policy_090")
    st.side_effect_policy_ref = "policy_090"
    prop = _proposal_for(pkt, "/u/%s/one.txt" % ns)
    return st, prop, pv


def _completion_contract_for(pkt, ns):
    cc = {"schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc_090",
          "contract_version": 1, "task_id": pkt.get("identity", {}).get("task_id"),
          "effective_namespace": ns, "grant_snapshot_ref": "grant_snap_090", "packet_id": pkt["packet_id"],
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
            "results": results}
