"""
role_matrix.py -- the R1-ROLE-1 role-conversion SINK MATRIX (contract s6 amendment 6; red-team Finding 6).

The i38 build tested ONE diagnostic sink (M-R11: router stage-trace -> evidence coverage). R1-ROLE-1
prohibits MANY distinct sinks and TWO carriers (the #40 0.8.0 router stage-trace AND the 0.9.0 hydrated
working-memory region). This module parameterizes a kill over EVERY (carrier, sink) pair:

    carriers = {routing, working}
    sinks    = {evidence, evidence_requirement, coverage_result, packet_disposition, control_plane,
                grant, policy, approval, health, trusted_status, completion, target, effect}

For each pair, a scenario is built where the action is DENIED (or completion is INDETERMINATE) by the
reference monitor at the check protecting that sink, WITH the carrier present in the packet. The seeded
defect `M-RC-<CARRIER>-<SINK>` routes the carrier into exactly that sink; a kill is
sec(reference)==secure AND sec({defect})==insecure. Every pair runs under the TEST-ONLY
non_execution=false authority packet (harness.build_baseline), so A31 + completion are actually REACHED
(not short-circuited at A06). Namespace closure alone does not stop these -- the carrier stays in-namespace.
"""

from action_authz import canon
from action_authz.monitor import authorize
from action_authz.boundary import evaluate_completion_via_permit
from . import harness

pb = harness.prop_bytes
_PID = "cpkt_test0001"


def _flag(carrier):
    return "routing_present" if carrier == "routing" else "working_present"


def _mark(st, carrier):
    st.packet_meta[_PID][_flag(carrier)] = True


# --------------------------------------------------------------------------- decision-sink scenarios
def _ev(carrier):
    st, prop = harness.build_evidence_scenario(navigation_present=False, working_present=False)
    _mark(st, carrier)
    return st, prop


def _control_plane(carrier):
    st, prop = harness.build_scope_scenario()          # request={projA}; a projB target -> A18 ns DENY
    _mark(st, carrier)
    return st, prop


def _target(carrier):
    st, prop = harness.build_baseline()
    st.resolve_ctx.transitive_ns["/u/data/projA/one.txt"] = ["projB"]   # out-of-scope constituent -> A18
    _mark(st, carrier)
    return st, prop


def _grant(carrier):
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].grants[0]["allowed_target_ids"] = ["/u/data/projA/other.txt"]  # not one.txt
    _mark(st, carrier)
    return st, prop


def _delete(carrier):
    st, prop = harness.build_delete_scenario(with_approval=False)        # approval always, none present -> A29
    _mark(st, carrier)
    return st, prop


def _health(carrier):
    st, prop = harness.build_baseline()
    st.health.put("health.fs/1", "down", st.clock.now_ms())             # unhealthy -> A14 DENY
    _mark(st, carrier)
    return st, prop


def _effect(carrier):
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].grants[0]["max_quantity"] = {"fs.write": 3}
    prop["arguments"] = {"path": "/u/data/projA/one.txt", "content": "hello"}   # 5 bytes > 3 -> A26 DENY
    _mark(st, carrier)
    return st, prop


def _manifest(carrier):
    # i40 Finding 3: `manifest` sink. Installed-artifact drift -> A12 (and A32) DENY. A defect that
    # lets the carrier attest the trusted manifest/artifact currentness launders it into the manifest.
    st, prop = harness.build_baseline()
    st.manifests.set_current_installed("fs.local", "f" * 64)     # installed-artifact drift -> A12 DENY
    _mark(st, carrier)
    return st, prop


def _working_memory(carrier):
    # i40 Finding 3: `working_memory` sink. The trusted working-state TASK BINDING is derived ONLY from
    # the authentic packet; a task-binding mismatch denies at A05. A defect that lets the carrier's
    # untrusted working-memory content alter that trusted task binding launders it into working_memory
    # (the prohibited working_memory->working_memory conversion: untrusted wm content altering trusted
    # state metadata / task binding / namespace authorization / state_version / can_instruct).
    st, prop = harness.build_baseline()
    prop["task_id"] = "task_OTHER"                               # task-binding mismatch -> A05 DENY
    _mark(st, carrier)
    return st, prop


_DECISION_SCENARIO = {
    "evidence": _ev, "evidence_requirement": _ev, "coverage_result": _ev, "packet_disposition": _ev,
    "control_plane": _control_plane, "target": _target, "grant": _grant,
    "policy": _delete, "approval": _delete, "manifest": _manifest, "health": _health, "effect": _effect,
    "working_memory": _working_memory,
}


def _decision_secure(sink, carrier, mutations):
    """secure == the action is DENIED (no permit)."""
    st, prop = _DECISION_SCENARIO[sink](carrier)
    d = authorize(pb(prop), st, mutations=mutations)
    return d.outcome == "DENY" and len(st.permits._permits) == 0


# --------------------------------------------------------------------------- completion-sink scenarios
def _completion_permit():
    st, prop = harness.build_baseline()
    cc = {
        "schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc_rm",
        "contract_version": 1, "task_id": "task_test0001", "effective_namespace": "projA",
        "grant_snapshot_ref": "grant_snap_1", "packet_id": _PID,
        "root": {"kind": "leaf", "completion_scope": "permit", "predicate": {
            "predicate_id": "p1", "predicate_kind": "executor_status", "source_id": "exec.fs/1",
            "source_version": 1, "subject_binding": {}, "max_age_ms": 60000,
            "expected": {"allowed_result_codes": ["ok"], "allowed_exit_codes": [0]}}},
        "trusted_status_sources": [{"source_id": "exec.fs/1", "source_version": 1,
                                    "status_schema": "s/1", "code_digest": "a" * 64, "max_age_ms": 60000}],
        "evaluation_policy": {"missing": "indeterminate", "malformed": "indeterminate",
                              "stale": "indeterminate", "indeterminate_is_complete": False},
    }
    cc["contract_digest"] = canon.digest_omitting(cc, "contract_digest")
    st.completion_by_packet[_PID] = cc
    d = authorize(pb(prop), st)                    # PERMIT; A34 stamps the immutable completion binding
    return st, d.permit


def _completion_secure(sink, carrier, mutations):
    """secure == completion is NOT falsely 'true' (no trusted status is present)."""
    st, permit = _completion_permit()
    v = evaluate_completion_via_permit(st, permit, mutations=mutations,
                                       evidence_claims={"__carrier_%s__" % carrier: True})
    return v != "true"


_COMPLETION_SINKS = ("trusted_status", "completion")

# ALL 15 FROZEN R1-ROLE-1 sinks (i40 Finding 3 -- i39 omitted `manifest` + `working_memory`), each
# protected against BOTH carriers => 30 killable (carrier, sink) pairs.
SINKS = ("evidence", "evidence_requirement", "coverage_result", "packet_disposition",
         "control_plane", "grant", "policy", "approval", "manifest", "health",
         "trusted_status", "completion", "target", "effect", "working_memory")
CARRIERS = ("routing", "working")


def _defect_id(carrier, sink):
    return "M-RC-%s-%s" % ({"routing": "RT", "working": "WM"}[carrier], sink.upper())


def _secure(sink, carrier, mutations):
    if sink in _COMPLETION_SINKS:
        return _completion_secure(sink, carrier, mutations)
    return _decision_secure(sink, carrier, mutations)


def run(check):
    """Kill every (carrier, sink) role-conversion pair. Returns the matrix (list of dicts)."""
    matrix = []
    for sink in SINKS:
        for carrier in CARRIERS:
            did = _defect_id(carrier, sink)
            try:
                ref = _secure(sink, carrier, frozenset())
            except Exception as e:  # noqa: BLE001
                ref = "ERR:%r" % e
            try:
                mut = _secure(sink, carrier, frozenset([did]))
            except Exception as e:  # noqa: BLE001
                mut = "ERR:%r" % e
            killed = (ref is True) and (mut is False)
            check.ok("%s [%s->%s] killed" % (did, carrier, sink), killed, "ref=%r mut=%r" % (ref, mut))
            matrix.append({"defect_id": did, "carrier": carrier, "sink": sink,
                           "status": "killed" if killed else "NOT_KILLED"})
    return matrix
