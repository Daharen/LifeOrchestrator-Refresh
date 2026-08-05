"""
integration.py -- REAL #36/#37/#40 (0.7.0) producer->consumer integration (contract s8.7 crit 9 + 1).

The authentic #40 context_packet/0.2 outputs (captured under fixtures/real_packets/, produced by the
committed #40 0.7.0 compiler over real #36/#37 retrieval) all carry non_execution=true, so the reference
monitor must DETERMINISTICALLY DENY every one at check A06 -- proving the real module chain denies while
the shipped substrate stays read-only. The positive permit path uses ONLY the TEST-ONLY mock authority
packet (non_execution=false) from harness.build_baseline (s8.7 crit 1).
"""

import glob
import json
import os

from action_authz import canon, stores as S
from action_authz.monitor import authorize
from . import harness

_REAL_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "fixtures", "real_packets")


def _real_packets():
    out = []
    for path in sorted(glob.glob(os.path.join(_REAL_DIR, "*.json"))):
        with open(path, "r", encoding="utf-8") as fh:
            out.append((os.path.basename(path), json.load(fh)))
    return out


def _proposal_for(pkt):
    """A WELL-FORMED proposal bound to a real packet -- it passes A01-A05, then A06 denies it."""
    ident = pkt.get("identity", {})
    ti = pkt.get("task_input", {})
    return {
        "schema": "lifeorch.action_proposal/0.1", "proposal_id": "prop_real",
        "task_id": ident.get("task_id"), "packet_id": pkt["packet_id"],
        "tool_id": "fs.local", "operation": "fs.write",
        "arguments": {"path": "/u/data/%s/x.txt" % (ti.get("namespace") or "core-docs"), "content": "x"},
        "evidence_refs": [], "claimed_effects": [],
        "model_provenance": {"model_run_id": "run_real", "adapter_id": "adapter.chat",
                             "adapter_version": 1, "consumer_profile_fingerprint": "c" * 64,
                             "prompt_packet_id": pkt["packet_id"], "raw_output_hash": "d" * 64},
    }


def _run_real(pkt):
    st = S.Stores()
    pv = S.PacketStore.view_from_real_m40_packet(pkt)
    st.packets.put(pv)
    prop = _proposal_for(pkt)
    st.attest.put("run_real", "d" * 64, pkt["packet_id"], model_supplied_provenance=False)
    d = authorize(harness.prop_bytes(prop), st, mutations=frozenset())
    return d, len(st.permits._permits)


def run(check):
    """Return {"real_denied": N, "real_total": N, "positive_permit": bool, "results": [...]}."""
    reals = _real_packets()
    check.ok("real #40 0.7.0 packets present", len(reals) >= 1, "found=%d" % len(reals))
    results = []
    for name, pkt in reals:
        check.ok("%s is context_packet/0.2" % name, pkt.get("schema") == "lifeorch.context_packet/0.2")
        check.ok("%s carries non_execution=true" % name, pkt.get("non_execution") is True)
        d, n_permits = _run_real(pkt)
        check.ok("%s -> deterministic DENY at A06" % name,
                 d.outcome == "DENY" and (d.reason_code or "").startswith("A06"),
                 "reason=%s" % d.reason_code)
        check.ok("%s -> constant caller bytes" % name, d.caller_bytes == S.CONSTANT_DENIAL_BYTES)
        check.ok("%s -> no permit issued" % name, n_permits == 0)
        results.append({"packet": name, "packet_id": pkt["packet_id"],
                        "compiler_version": pkt.get("identity", {}).get("compiler_version"),
                        "outcome": d.outcome, "reason": d.reason_code})

    # positive permit path uses ONLY the test-only non_execution=false mock packet
    st, prop = harness.build_baseline()
    dp = authorize(harness.prop_bytes(prop), st, mutations=frozenset())
    positive = (dp.outcome == "PERMIT" and dp.permit["packet_id"] == "cpkt_test0001")
    check.ok("positive permit path via test-only non_execution=false packet", positive)
    # and prove the same producer->consumer code denies a non_execution=true copy of that packet
    st2, prop2 = harness.build_baseline()
    st2.packets.verify_and_get("cpkt_test0001").non_execution = True
    d2 = authorize(harness.prop_bytes(prop2), st2, mutations=frozenset())
    check.ok("same packet with non_execution=true -> A06 DENY",
             d2.outcome == "DENY" and (d2.reason_code or "").startswith("A06"))

    return {"real_denied": sum(1 for r in results if r["outcome"] == "DENY"),
            "real_total": len(results), "positive_permit": positive, "results": results}
