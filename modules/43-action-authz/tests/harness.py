"""
harness.py -- shared test scaffolding: a fully-consistent baseline scenario (a TEST-ONLY mock authority
packet with non_execution=false) under which a well-formed proposal is PERMITTED on the reference impl,
plus a small check accumulator.

Positive permit-path tests use ONLY this test-only non_execution=false packet (s8.7 crit 1); the real
shipped #40 packets (integration.py) carry non_execution=true and must deterministically DENY at A06.
"""

import os
import sys

_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _MODDIR not in sys.path:
    sys.path.insert(0, _MODDIR)

from action_authz import canon, stores as S  # noqa: E402
from action_authz.monitor import authorize   # noqa: E402
from action_authz.boundary import MockExecutor  # noqa: E402

RAW_HASH = "d" * 64
CPFP = "c" * 64


class Check(object):
    def __init__(self, section):
        self.section = section
        self.passed = []
        self.failed = []

    def ok(self, name, cond, detail=""):
        if cond:
            self.passed.append(name)
        else:
            self.failed.append((name, detail))
        return bool(cond)

    @property
    def n_pass(self):
        return len(self.passed)

    @property
    def n_fail(self):
        return len(self.failed)


def make_operation():
    return {
        "operation": "fs.write",
        "enabled": True,
        "arg_schema": {
            "type": "object",
            "additional_properties": False,
            "fields": [
                {"name": "path", "type": "string", "required": True, "normalize_nfc": False,
                 "set_semantics": False, "semantic_type": "path", "max_utf8_bytes": 4096},
                {"name": "content", "type": "string", "required": True, "normalize_nfc": True,
                 "set_semantics": False, "semantic_type": "content", "max_utf8_bytes": 1048576},
            ],
        },
        "canonicalizer": {"profile_id": "canon.fs/1", "profile_version": 1, "code_digest": "b" * 64},
        "target_resolver": {"profile_id": "resolve.fs/1", "profile_version": 1, "code_digest": "b" * 64},
        "effect_classifier": {"profile_id": "classify.fs.write/1", "profile_version": 1, "code_digest": "b" * 64},
        "required_permission_scopes": ["fs.write"],
        "base_risk_class": 2,
        "reversibility": "compensatable",
        "idempotency": "supported",
        "approval_requirement": "none",
        "resource_ceiling": [{"limit_id": "fs.write", "max_value": 1048576}],
        "max_target_count": 4,
        "max_effect_count": 8,
        "evidence_dependency": "none",
        "allowed_effect_classes": ["fs.write"],
        "allowed_target_kinds": ["fs.file"],
        "sandbox_class": "local_bounded",
    }


def make_delete_operation():
    op = make_operation()
    op["operation"] = "fs.delete"
    op["effect_classifier"] = {"profile_id": "classify.fs.delete/1", "profile_version": 1, "code_digest": "b" * 64}
    op["required_permission_scopes"] = ["fs.delete"]
    op["base_risk_class"] = 3
    op["reversibility"] = "irreversible"
    op["approval_requirement"] = "always"
    op["allowed_effect_classes"] = ["fs.delete"]
    op["arg_schema"]["fields"] = [f for f in op["arg_schema"]["fields"] if f["name"] == "path"]
    return op


def make_shell_operation():
    op = make_operation()
    op["operation"] = "shell.run"
    op["is_wrapper"] = True
    op["target_resolver"] = {"profile_id": "resolve.shell/1", "profile_version": 1, "code_digest": "b" * 64}
    op["effect_classifier"] = {"profile_id": "classify.shell.run/1", "profile_version": 1, "code_digest": "b" * 64}
    op["required_permission_scopes"] = ["fs.write"]
    op["base_risk_class"] = 2
    op["approval_requirement"] = "none"
    op["allowed_effect_classes"] = ["fs.delete", "fs.write", "process.spawn"]
    op["arg_schema"]["fields"] = [
        {"name": "command", "type": "string", "required": True, "normalize_nfc": False,
         "set_semantics": False, "semantic_type": "opaque", "max_utf8_bytes": 4096},
        {"name": "path", "type": "string", "required": True, "normalize_nfc": False,
         "set_semantics": False, "semantic_type": "path", "max_utf8_bytes": 4096},
    ]
    return op


def build_baseline():
    """Return (stores, proposal_dict) for the happy path that PERMITS on the reference impl."""
    st = S.Stores()
    st.current_corpus_version = "corpus_v1"

    packet_id = "cpkt_test0001"
    task_id = "task_test0001"
    st.packets.put(S.PacketView(
        packet_id=packet_id, task_id=task_id, non_execution=False,
        namespace="projA", allowed_namespaces=["projA"], corpus_version="corpus_v1",
        grant_snapshot_ref="grant_snap_1", current=True))
    st.packet_meta = {packet_id: {"disposition": "answerable", "provenance_ok": True,
                                  "contradiction": False, "retrieval_complete": True}}
    st.completion_contracts = {}
    st.validated_claims = {}

    st.attest.put("run_1", RAW_HASH, packet_id, model_supplied_provenance=False)

    man = S.build_manifest("fs.local", [make_operation(), make_delete_operation(), make_shell_operation()])
    st.manifests.register(man)

    st.health.put("health.fs/1", "ok", st.clock.now_ms())

    st.grants["grant_snap_1"] = S.GrantSnapshot(
        "grant_snap_1",
        grants=[
            {"grant_id": "g_write", "tool_id": "fs.local", "operation": "fs.write",
             "action_namespace": "projA", "allowed_target_ids": ["/u/data/projA/one.txt",
                                                                  "/u/data/projA/two.txt"],
             "effect_classes": ["fs.write"], "max_quantity": {"fs.write": 1048576},
             "externality_max": "local", "risk_ceiling": 2, "validity_from": 0,
             "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
             "scopes": ["fs.write"], "limits": [{"limit_id": "fs.write", "max_value": 1048576}]},
        ],
        epoch=1, current=True, request_namespaces=["projA"])

    st.policies["policy_1"] = S.PolicyView("policy_1")
    st.side_effect_policy_ref = "policy_1"

    proposal = {
        "schema": "lifeorch.action_proposal/0.1",
        "proposal_id": "prop_1",
        "task_id": task_id,
        "packet_id": packet_id,
        "tool_id": "fs.local",
        "operation": "fs.write",
        "arguments": {"path": "/u/data/projA/one.txt", "content": "hello"},
        "evidence_refs": [],
        "claimed_effects": [],
        "model_provenance": {
            "model_run_id": "run_1", "adapter_id": "adapter.chat", "adapter_version": 1,
            "consumer_profile_fingerprint": CPFP, "prompt_packet_id": packet_id,
            "raw_output_hash": RAW_HASH,
        },
    }
    return st, proposal


def _delete_grant():
    return {"grant_id": "g_delete", "tool_id": "fs.local", "operation": "fs.delete",
            "action_namespace": "projA", "allowed_target_ids": ["/u/data/projA/one.txt"],
            "effect_classes": ["fs.delete"], "max_quantity": {"fs.delete": 1},
            "externality_max": "local", "risk_ceiling": 3, "validity_from": 0,
            "validity_to": 9_000_000_000_000_000, "approval_mode": "always",
            "scopes": ["fs.delete"], "limits": [{"limit_id": "fs.delete", "max_value": 1}]}


def build_delete_scenario(with_approval=False, stale_approval=False, mismatch_approval=False):
    """fs.delete on projA WITH a matching grant, so approval (always, risk 3 + irreversible) is the gate."""
    st, prop = build_baseline()
    st.grants["grant_snap_1"].grants.append(_delete_grant())
    prop["operation"] = "fs.delete"
    prop["arguments"] = {"path": "/u/data/projA/one.txt"}
    if with_approval or stale_approval or mismatch_approval:
        man_digest = st.manifests.lookup("fs.local")["manifest_digest"]
        cad = _delete_cad()
        rec = {"approval_ref": "appr_1",
               "canonical_action_digest": (cad if not mismatch_approval else "0" * 64),
               "task_id": "task_test0001", "namespace": "projA",
               "manifest_version": 1, "manifest_digest": man_digest,
               "grant_snapshot_ref": "grant_snap_1", "issuer": "human:nicholas",
               "state": ("revoked" if stale_approval else "approved"),
               "revoked": bool(stale_approval),
               "expiry_unix_ms": (1 if stale_approval else 9_000_000_000_000_000)}
        st.approvals.put(rec)
    return st, prop


def _delete_cad():
    st, prop = build_baseline()
    st.grants["grant_snap_1"].grants.append(_delete_grant())
    prop["operation"] = "fs.delete"
    prop["arguments"] = {"path": "/u/data/projA/one.txt"}
    d = authorize(prop_bytes(prop), st, mutations=frozenset(["M-E12"]))
    return d.cad


def build_evidence_scenario(dependency="packet_answerable", disposition="needs_expansion",
                            navigation_present=True, working_present=True):
    """fs.write op whose manifest requires evidence, with a NON-answerable packet -> A31 DENY."""
    st, prop = build_baseline()
    man = st.manifests.lookup("fs.local")
    for o in man["operations"]:
        if o["operation"] == "fs.write":
            o["evidence_dependency"] = dependency
    st.packet_meta["cpkt_test0001"] = {"disposition": disposition, "provenance_ok": True,
                                       "contradiction": False, "retrieval_complete": True,
                                       "navigation_present": navigation_present,
                                       "working_present": working_present}
    return st, prop


def _write_grant(gid, ns, target_ids, scopes=("fs.write",), maxq=1048576):
    return {"grant_id": gid, "tool_id": "fs.local", "operation": "fs.write",
            "action_namespace": ns, "allowed_target_ids": list(target_ids),
            "effect_classes": ["fs.write"], "max_quantity": {"fs.write": maxq},
            "externality_max": "local", "risk_ceiling": 2, "validity_from": 0,
            "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
            "scopes": list(scopes), "limits": [{"limit_id": "fs.write", "max_value": maxq}]}


def build_scope_scenario():
    """request={projA}; grants cover projA+projB; a projB target -> A18 ns-closure DENY (decisive)."""
    st, prop = build_baseline()
    gs = st.grants["grant_snap_1"]
    gs.request_namespaces = ["projA"]
    gs.grants = [_write_grant("g_a", "projA", ["/u/data/projA/one.txt"]),
                 _write_grant("g_b", "projB", ["/u/data/projB/b.txt"])]
    prop["arguments"] = {"path": "/u/data/projB/b.txt", "content": "x"}
    return st, prop


def build_multi_ns_scenario():
    """two targets in DIFFERENT namespaces -> A18 single-namespace DENY (M-S07)."""
    st, prop = build_baseline()
    gs = st.grants["grant_snap_1"]
    gs.request_namespaces = ["projA", "projB"]
    gs.grants = [_write_grant("g_multi", "projA", ["/u/data/projA/one.txt", "/u/data/projB/b.txt"]),
                 _write_grant("g_bns", "projB", ["/u/data/projB/b.txt"])]
    prop["arguments"] = {"path": "/u/multi", "content": "x"}
    return st, prop


def build_symlink_scenario():
    """in-scope name /u/data/projA/decoy.txt is a symlink to out-of-scope /u/shared/leak.txt.
    Reference resolves it out of scope -> A18 DENY; M-E05/M-E06/M-S06 permit it."""
    st, prop = build_baseline()
    gs = st.grants["grant_snap_1"]
    gs.request_namespaces = ["projA"]
    gs.grants = [_write_grant("g_sym", "projA",
                              ["/u/data/projA/decoy.txt", "/u/shared/leak.txt"])]
    prop["arguments"] = {"path": "/u/data/projA/decoy.txt", "content": "x"}
    return st, prop


def build_absence_scenario():
    """op is absence-dependent; the retrieval frontier is unresolved -> A31 DENY unless M-R10."""
    st, prop = build_baseline()
    man = st.manifests.lookup("fs.local")
    for o in man["operations"]:
        if o["operation"] == "fs.write":
            o["absence_dependent"] = True
    st.packet_meta["cpkt_test0001"]["retrieval_complete"] = False
    return st, prop


def make_stale_health(st):
    st.health.put("health.fs/1", "ok", st.clock.now_ms() - 10_000_000)


def prop_bytes(proposal):
    return canon.canonical_bytes(proposal)


def run_happy(mutations=frozenset()):
    """Build a fresh baseline and authorize the happy-path proposal. Returns (st, decision)."""
    st, prop = build_baseline()
    d = authorize(prop_bytes(prop), st, mutations=mutations)
    return st, d


def execute_decision(st, decision, mutations=frozenset(), **kw):
    ex = MockExecutor(st)
    return ex.execute(decision.permit_ref, mutations=mutations, **kw)
