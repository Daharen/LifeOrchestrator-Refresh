"""
adapter_090.py -- the suite-owned EXACT context_packet/0.2 producer->consumer adapter (contract s6;
i40 red-team Finding 5).

The i39 test path (`integration._trusted_090`) short-circuited the authentic seam beyond A06: it set
current_corpus_version=None (A07 bypassed), REPLACED the packet's grant-snapshot identity with a
suite-chosen ref, and reduced the routed trace + hydrated working-memory region to TWO booleans. This
adapter is the exact seam the red-team requires:

  * validates + PRESERVES every identity-covered field (packet_id, task_id, namespace,
    allowed_namespaces, corpus_version, grant_snapshot_ref, working_state_version);
  * does NOT rewrite the packet's grant-snapshot identity -- the trusted GrantSnapshot is registered
    under the packet's OWN control_plane_grant_snapshot_ref;
  * PRESERVES corpus_version so A07 is EXERCISED (the current_corpus_version=None bypass is gone);
  * PRESERVES the complete routed stage-trace, working-memory envelope + items, evidence excerpts,
    provenance, namespace-closure metadata, and state_version as DATA (not two booleans);
  * the ONLY test-only authority overlay changes the externally-controlled `non_execution` condition;
  * carrier presence (routing_present / working_present) is DERIVED from the real structures, so the
    monitor's R1-ROLE-1 hooks see the authentic carriers, and inertness is asserted at EVERY R1 sink.

DESIGN-ONLY; nothing here is action-capable. Trusted stores whose ids/digests AGREE with the packet
stand in for the ACTIVATION-gating production grant/policy/manifest storage.
"""

from action_authz import canon, stores as S


def adapt_packet_view(pkt, non_execution_overlay=None):
    """EXACT context_packet/0.2 -> trusted PacketView. Preserves ALL identity-covered fields; the ONLY
    overlay is the externally-controlled `non_execution` (TEST-ONLY when explicitly supplied)."""
    if pkt.get("schema") != "lifeorch.context_packet/0.2":
        raise ValueError("not a context_packet/0.2")
    ident = pkt.get("identity", {}) or {}
    ti = pkt.get("task_input", {}) or {}
    ne = bool(pkt.get("non_execution")) if non_execution_overlay is None else bool(non_execution_overlay)
    return S.PacketView(
        packet_id=pkt["packet_id"],
        task_id=ident.get("task_id"),
        non_execution=ne,
        namespace=ti.get("namespace"),
        allowed_namespaces=ti.get("allowed_namespaces", []),
        corpus_version=ident.get("corpus_version"),                     # PRESERVED (A07 exercised)
        grant_snapshot_ref=ident.get("control_plane_grant_snapshot_ref"),  # NOT rewritten
        current=True)


def full_meta(pkt):
    """The A08/A31 trusted packet_meta with carrier PRESENCE derived from the REAL structures, PLUS the
    complete carriers preserved as DATA (so R1-ROLE-1 inertness is asserted on authentic records, never
    a two-boolean reduction)."""
    disp = pkt.get("disposition", {}) or {}
    eh = pkt.get("evaluation_hooks", {}) or {}
    wm = pkt.get("working_memory", {}) or {}
    ev = pkt.get("evidence", {}) or {}
    ident = pkt.get("identity", {}) or {}
    answerable = (disp.get("packet_disposition") == "answerable")
    trace = eh.get("routing_stage_trace")
    return {
        "disposition": "answerable" if answerable else "needs_expansion",
        "provenance_ok": not bool(disp.get("provenance_failed")),
        "contradiction": bool(disp.get("contradictions")),
        "retrieval_complete": answerable,
        # carrier PRESENCE derived from the authentic structures (never a hand-set boolean):
        "routing_present": bool(isinstance(trace, list) and trace),
        "working_present": bool(wm.get("present")),
        # the FULL carriers preserved as DATA (the two-boolean reduction is retired):
        "routing_stage_trace": trace,
        "working_memory_envelope": {k: wm.get(k) for k in
                                    ("present", "can_instruct", "is_evidence", "authority",
                                     "namespace_scope", "state_version", "content_role")},
        "working_memory_items": wm.get("items"),
        "working_state_version": ident.get("working_state_version"),
        "evidence_excerpts": ev.get("excerpts"),
        "namespace_closure": ident.get("namespace_closure"),
        "injected_control_plane": eh.get("injected_control_plane"),     # adversarial; must stay inert
    }


def build_trusted(pkt, non_execution_overlay=None, disposition=None):
    """Assemble a FULL trusted config CONSISTENT with the real 0.9.0 packet: corpus preserved (A07
    live), the GrantSnapshot registered under the packet's OWN grant-snapshot ref, the full carriers in
    packet_meta. Returns (stores, proposal, packet_view). The action targets /u/<ns>/one.txt."""
    ident = pkt.get("identity", {}) or {}
    ti = pkt.get("task_input", {}) or {}
    ns = ti.get("namespace") or "nsa"
    gref = ident.get("control_plane_grant_snapshot_ref")

    st = S.Stores()
    st.current_corpus_version = ident.get("corpus_version")            # PRESERVE -> A07 EXERCISED
    pv = adapt_packet_view(pkt, non_execution_overlay=non_execution_overlay)
    st.packets.put(pv)
    meta = full_meta(pkt)
    if disposition is not None:
        meta["disposition"] = disposition
        meta["retrieval_complete"] = (disposition == "answerable")
    st.packet_meta = {pv.packet_id: meta}
    st.completion_contracts = {}
    st.attest.put("run_real", "d" * 64, pv.packet_id, model_supplied_provenance=False)

    op = S.build_manifest("fs.local", [_fs_write_op()])
    st.manifests.register(op)
    st.health.put("health.fs/1", "ok", st.clock.now_ms())
    st.resolve_ctx.path_ns = [("/u/%s" % ns, ns)]
    # the trusted GrantSnapshot is registered under the packet's OWN grant-snapshot ref (id AGREES).
    st.grants[gref] = S.GrantSnapshot(
        gref,
        grants=[{"grant_id": "g_090", "tool_id": "fs.local", "operation": "fs.write",
                 "action_namespace": ns, "allowed_target_ids": ["/u/%s/one.txt" % ns],
                 "effect_classes": ["fs.write"], "max_quantity": {"fs.write": 1048576},
                 "externality_max": "local", "risk_ceiling": 2, "validity_from": 0,
                 "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
                 "scopes": ["fs.write"], "limits": [{"limit_id": "fs.write", "max_value": 1048576}]}],
        request_namespaces=[ns])
    st.policies["policy_090"] = S.PolicyView("policy_090")
    st.side_effect_policy_ref = "policy_090"
    prop = {
        "schema": "lifeorch.action_proposal/0.1", "proposal_id": "prop_real",
        "task_id": ident.get("task_id"), "packet_id": pkt["packet_id"],
        "tool_id": "fs.local", "operation": "fs.write",
        "arguments": {"path": "/u/%s/one.txt" % ns, "content": "x"},
        "evidence_refs": [], "claimed_effects": [],
        "model_provenance": {"model_run_id": "run_real", "adapter_id": "adapter.chat",
                             "adapter_version": 1, "consumer_profile_fingerprint": "c" * 64,
                             "prompt_packet_id": pkt["packet_id"], "raw_output_hash": "d" * 64},
    }
    return st, prop, pv


def _fs_write_op():
    from . import harness
    op = harness.make_operation()
    op["evidence_dependency"] = "packet_answerable"
    return op
