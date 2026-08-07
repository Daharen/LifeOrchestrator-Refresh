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

import json

from action_authz import canon, stores as S


# ===========================================================================================
# i41 round-3 Finding 5: the LOSSLESS context_packet/0.2 seam.
#
# The i40 adapter preserved only a SELECTED subset, so two materially different authentic packets could
# collapse into the same trusted representation (the reviewer proved changes to identity.compiler_version,
# identity.selection_policy, retrieval_provenance, evidence.current_state_refs, and selection-stage content
# each produced IDENTICAL adapter output). This seam instead preserves the COMPLETE packet as canonical
# bytes PLUS a validated derived view: `identity_digest` is the SHA-256 over the complete packet's
# canonical bytes, so changing ANY packet field (identity-covered or otherwise) changes it; the packet
# round-trips byte-identically. The ONLY test-only authority overlay is `non_execution` -- it changes the
# DERIVED view only, never the preserved packet bytes / identity digest.
#
# The identity-covered CORE below is present in BOTH the 0.7.0 and 0.9.0 authentic generations and is
# VALIDATED on every packet (missing any => fail closed). 0.9.0-only carriers (routing_plan_digest /
# routing_policy) are additionally asserted by require_routed() where present. Preservation is by whole-
# packet canonical bytes, so NOTHING is lost regardless of generation.

_IDENTITY_CORE = (
    "task_id", "compiler_version", "corpus_version", "control_plane_grant_snapshot_ref",
    "selection_policy", "classifier_policy", "query_class", "temporal_intent", "namespace_closure",
    "working_state_version", "retrieval_plan_digest", "consumer_profile", "selected_record_version_ids",
    "budget", "omission_manifest_digest", "allowed_namespaces",
)
# the top-level regions the packet-identity coherence covers (control plane / working memory / evidence /
# retrieval provenance / routing+selection trace / disposition / omission + transport accounting); present
# in both generations. Missing any => fail closed.
_TOPLEVEL_CORE = (
    "schema", "packet_id", "non_execution", "identity", "task_input", "control_plane", "working_memory",
    "evidence", "retrieval_provenance", "evaluation_hooks", "selection", "disposition",
    "omission_manifest", "transport_accounting", "consumer_profile",
)
# 0.9.0-only identity carriers (routed generation) -- asserted preserved where the packet is a routed 0.9.0.
_IDENTITY_ROUTED = ("routing_plan_digest", "routing_policy")


class LosslessError(Exception):
    """The lossless context_packet/0.2 seam rejected a packet (fail closed). `.reason` is a stable code."""

    def __init__(self, reason, detail=""):
        super().__init__("%s: %s" % (reason, detail) if detail else reason)
        self.reason = reason


class PreservedPacket(object):
    """The COMPLETE authentic packet preserved as canonical bytes + a validated derived view (Finding 5).

    * `canonical` -- canonical bytes of the COMPLETE packet (round-trips byte-identically).
    * `identity_digest` -- SHA-256 over `canonical`; changing ANY packet field changes it.
    * `complete` -- a fresh deep copy re-parsed from `canonical` (round-trip proof; == the input packet).
    * `view` -- the trusted PacketView the monitor consumes (the ONLY overlay is non_execution).
    * `meta` -- the full A08/A31 packet_meta with the complete carriers preserved as DATA.
    """

    __slots__ = ("packet_id", "canonical", "identity_digest", "complete", "view", "meta")

    def __init__(self, packet_id, canonical, identity_digest, complete, view, meta):
        self.packet_id = packet_id
        self.canonical = canonical
        self.identity_digest = identity_digest
        self.complete = complete
        self.view = view
        self.meta = meta


def _validate_lossless(pkt):
    """Validate the identity-covered CORE + top-level regions + internal coherence (Finding 5). Fail
    closed (LosslessError) on any missing/mistyped field so a malformed packet is never silently accepted."""
    if not isinstance(pkt, dict) or pkt.get("schema") != "lifeorch.context_packet/0.2":
        raise LosslessError("not_context_packet")
    for f in _TOPLEVEL_CORE:
        if f not in pkt:
            raise LosslessError("toplevel_missing", f)
    if not isinstance(pkt.get("packet_id"), str):
        raise LosslessError("packet_id_type")
    if not isinstance(pkt.get("non_execution"), bool):
        raise LosslessError("non_execution_type")
    ident = pkt.get("identity")
    if not isinstance(ident, dict):
        raise LosslessError("identity_type")
    for f in _IDENTITY_CORE:
        if f not in ident:
            raise LosslessError("identity_field_missing", f)
    if not isinstance(pkt.get("task_input"), dict):
        raise LosslessError("task_input_type")
    # coherence: the derived-view identity fields the monitor consumes must be self-consistent.
    if not isinstance(ident.get("task_id"), str):
        raise LosslessError("task_id_type")
    ti = pkt["task_input"]
    if "allowed_namespaces" in ti and not isinstance(ti["allowed_namespaces"], list):
        raise LosslessError("allowed_namespaces_type")


def adapt_packet_lossless(pkt, non_execution_overlay=None):
    """EXACT, LOSSLESS context_packet/0.2 -> PreservedPacket. Validates all identity-covered core fields +
    coherence (fail closed), preserves the COMPLETE packet as canonical bytes + identity digest, and
    derives the trusted view (whose ONLY overlay is non_execution). Round-trips byte-identically."""
    _validate_lossless(pkt)
    canonical = canon.canonical_bytes(pkt)              # COMPLETE packet (integer-only; no floats)
    identity_digest = canon.sha256_hex(canonical)       # changing ANY field changes this
    complete = json.loads(canonical.decode("utf-8"))    # round-trip deep copy (== pkt)
    view = adapt_packet_view(pkt, non_execution_overlay=non_execution_overlay)
    meta = full_meta(pkt)
    return PreservedPacket(pkt["packet_id"], canonical, identity_digest, complete, view, meta)


def require_routed(pkt):
    """Assert the 0.9.0 routed generation's extra identity carriers are present (validated + preserved
    where the packet is a routed 0.9.0). Returns True iff all are present."""
    ident = pkt.get("identity", {}) or {}
    return all(f in ident for f in _IDENTITY_ROUTED)


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
