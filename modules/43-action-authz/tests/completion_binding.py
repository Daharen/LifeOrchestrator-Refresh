"""
completion_binding.py -- completion binds via the IMMUTABLE packet_id (contract s6 amendment 4; Finding 4).

Proves the completion evaluator (boundary.evaluate_completion_via_permit) resolves the contract ONLY
through the authentic packet_id -> exact permit-time completion_contract_id/version/digest (NEVER a
current-contract-by-task lookup), enforces the per-leaf-kind MINIMUM completion_scope, and binds every
leaf to the EXACT permit -- so every substitution resolves to `indeterminate` (incomplete):

  positive; cross-action; cross-permit; wrong object; old-contract-vs-new-packet; mismatching content
  (tampered digest); omitted binding (scope weaker than the per-kind minimum); wrong validator version;
  superseded status. M-E36 (the by-task substitution hole) is decidably KILLED.
"""

from action_authz import canon
from action_authz.monitor import authorize
from action_authz.boundary import evaluate_completion_via_permit, MIN_COMPLETION_SCOPE
from action_authz.stores import NO_COMPLETION_CONTRACT
from . import harness

pb = harness.prop_bytes
_PID = "cpkt_test0001"
_TASK = "task_test0001"


def _contract(scope="permit", kind="executor_status", packet_id=_PID, source_version=1,
              subject_binding=None, tamper=False):
    cc = {
        "schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc_1",
        "contract_version": 1, "task_id": _TASK, "effective_namespace": "projA",
        "grant_snapshot_ref": "grant_snap_1", "packet_id": packet_id,
        "root": {"kind": "leaf", "completion_scope": scope, "predicate": {
            "predicate_id": "p1", "predicate_kind": kind, "source_id": "exec.fs/1",
            "source_version": source_version, "subject_binding": (subject_binding or {}),
            "max_age_ms": 60000,
            "expected": {"allowed_result_codes": ["ok"], "allowed_exit_codes": [0],
                         "expected_hash": "a" * 64}}},
        "trusted_status_sources": [{"source_id": "exec.fs/1", "source_version": source_version,
                                    "status_schema": "s/1", "code_digest": "a" * 64, "max_age_ms": 60000}],
        "evaluation_policy": {"missing": "indeterminate", "malformed": "indeterminate",
                              "stale": "indeterminate", "indeterminate_is_complete": False},
    }
    cc["contract_digest"] = canon.digest_omitting(cc, "contract_digest")
    if tamper:
        cc["contract_digest"] = "0" * 64
    return cc


def _permit_for(st, prop):
    d = authorize(pb(prop), st)
    assert d.outcome == "PERMIT", "setup: expected PERMIT, got %s/%s" % (d.outcome, d.reason_code)
    return d.permit


def _status_for(permit, source_version=1, superseded=False, kind="executor_status", extra=None):
    rec = {"predicate_kind": kind, "result_code": "ok", "exit_code": 0, "hash": "a" * 64,
           "source_id": "exec.fs/1", "source_version": source_version,
           "at_ms": 1_700_000_000_000, "namespace": "projA", "superseded": superseded,
           "subject": {"task_id": permit["task_id"],
                       "canonical_action_digest": permit["canonical_action_digest"],
                       "permit_id": permit["permit_id"]}}
    if extra:
        rec["subject"].update(extra)
    return rec


def _two_permits(cc=None):
    """Two permits under the SAME task+packet but DIFFERENT actions (one.txt vs two.txt -> distinct cad)."""
    st, prop = harness.build_baseline()
    if cc is not None:
        st.completion_by_packet[_PID] = cc
    p1 = _permit_for(st, prop)
    prop2 = dict(prop)
    prop2["proposal_id"] = "prop_2"
    prop2["arguments"] = {"path": "/u/data/projA/two.txt", "content": "hello"}
    p2 = _permit_for(st, prop2)
    return st, p1, p2


def run(check):
    ck = check.ok

    # positive: bound contract + a matching permit-scoped trusted status -> true
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    ck("completion positive: packet-bound contract + exact-permit status -> true",
       evaluate_completion_via_permit(st, p1) == "true")

    # cross-action / cross-permit: two permits (distinct cad + permit_id) under the SAME task+packet.
    # A status produced for p2 must NOT complete p1 (different action); p2 completes only via its own.
    st, p1, p2 = _two_permits(cc=_contract(scope="permit"))
    st.status.put(_status_for(p2))
    ck("completion cross-action: status for another action cannot complete p1",
       evaluate_completion_via_permit(st, p1) == "indeterminate")
    ck("completion cross-permit: p2 completes via its OWN permit-scoped status",
       evaluate_completion_via_permit(st, p2) == "true")

    # wrong object: an artifact_hash leaf naming an object THIS permit did not authorize -> indeterminate
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="object", kind="artifact_hash",
                                              subject_binding={"object_id": "/u/data/projA/two.txt"})
    p1 = _permit_for(st, prop)                                   # permit target is one.txt, not two.txt
    st.status.put(_status_for(p1, kind="artifact_hash", extra={"object_id": "/u/data/projA/two.txt"}))
    ck("completion wrong-object: object not authorized by this permit -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # old-contract-vs-new-packet: the by-packet contract declares a DIFFERENT packet_id -> indeterminate
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit", packet_id="cpkt_OTHER")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    ck("completion old-contract: contract bound to another packet_id -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # mismatching content: a completion contract TAMPERED AFTER issue -> the evaluator's own digest
    # recompute catches it -> indeterminate (and A30 independently denies a tampered contract at issue).
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    st.completion_by_packet[_PID]["contract_digest"] = "0" * 64   # post-issue tamper
    ck("completion tampered-digest: mismatching content -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # omitted binding: executor_status scoped to `task` (weaker than the minimum `permit`) -> indeterminate
    ck("min-scope table: executor_status minimum is exactly {permit}",
       MIN_COMPLETION_SCOPE["executor_status"] == frozenset(("permit",)))
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="task")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    ck("completion omitted-binding: executor_status scope=task < minimum -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # wrong validator version: status carries a different source_version -> no match -> indeterminate
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit", source_version=1)
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1, source_version=2))
    ck("completion wrong-validator-version: source_version mismatch -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # superseded status: a superseded status record is not current -> indeterminate
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1, superseded=True))
    ck("completion superseded-status: superseded status cannot complete -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # ===================================================================================
    # i40 Finding 1 -- completion is IMMUTABLY bound at issue time. New deterministic vectors.
    # ===================================================================================

    # (F1.1) LATE CONTRACT INSERTION: a permit issued with NO completion contract records the immutable
    # NO_COMPLETION_CONTRACT sentinel and can NEVER become completable by inserting a contract AFTER
    # issuance -- even with a perfectly-matching status.
    st, prop = harness.build_baseline()                          # no completion_by_packet entry
    p1 = _permit_for(st, prop)                                   # sentinel stamped at A34
    ck("F1.1 issue-with-no-contract stamps the immutable NO_COMPLETION_CONTRACT sentinel",
       (st.permits.completion_binding(p1["permit_id"]) or {}).get("sentinel") == NO_COMPLETION_CONTRACT)
    st.completion_by_packet[_PID] = _contract(scope="permit")    # contract inserted AFTER issuance
    st.status.put(_status_for(p1))                               # + a perfectly-matching status
    ck("F1.1 late-inserted contract can NEVER complete a sentinel permit -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # (F1.2) MISSING cc.packet_id: a contract present at issue but lacking packet_id -> indeterminate
    # (even with a matching status). The packet_id binding is REQUIRED, not optional.
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit", packet_id=None)
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    ck("F1.2 contract missing packet_id -> indeterminate (packet_id binding REQUIRED)",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # (F1.3) DELETED permit completion binding: the issue-time binding is MANDATORY; if it is absent
    # (deleted from the permit store) the evaluator fails closed -> indeterminate.
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    del st.permits._completion_binding[p1["permit_id"]]          # delete the issue-time binding
    ck("F1.3 deleted issue-time binding -> indeterminate (binding is MANDATORY, fail-closed)",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # (F1.4) BINDING CHANGED AFTER ISSUE: the contract bound at issue is SWAPPED for a different
    # (self-consistent) contract post-issue; the immutable issue-time binding no longer matches the
    # resolved contract's id/version/digest -> indeterminate.
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")    # contract A (cc_1)
    p1 = _permit_for(st, prop)                                   # binding stamped from A
    st.status.put(_status_for(p1))
    cc_b = _contract(scope="permit")
    cc_b["completion_contract_id"] = "cc_2"                      # a DIFFERENT contract, self-consistent
    cc_b["contract_digest"] = canon.digest_omitting(cc_b, "contract_digest")
    st.completion_by_packet[_PID] = cc_b                         # swap the contract post-issue
    ck("F1.4 contract swapped after issue -> issue-time binding mismatch -> indeterminate",
       evaluate_completion_via_permit(st, p1) == "indeterminate")

    # (F1.5) POSITIVE control for F1.1-F1.4: the SAME shape with the contract present at issue AND
    # the binding intact completes -> true (proves the above deny on the binding, not on the status).
    st, prop = harness.build_baseline()
    st.completion_by_packet[_PID] = _contract(scope="permit")
    p1 = _permit_for(st, prop)
    st.status.put(_status_for(p1))
    ck("F1.5 positive control: contract bound at issue + intact binding + status -> true",
       evaluate_completion_via_permit(st, p1) == "true")

    # M-E36 DECIDABLE: a task-only contract + another action's status is INERT on the reference but
    # falsely completes under the by-task substitution defect M-E36 -> a kill.
    def sec_me36(m):
        st, prop = harness.build_baseline()
        st.completion_by_packet[_PID] = _contract(scope="permit", subject_binding={"task_id": _TASK})
        p1 = _permit_for(st, prop)
        # a status from ANOTHER action (different cad + permit_id), same task
        rec = _status_for(p1)
        rec["subject"]["canonical_action_digest"] = "f" * 64
        rec["subject"]["permit_id"] = "permit_other"
        st.status.put(rec)
        return evaluate_completion_via_permit(st, p1, mutations=m) != "true"
    killed = sec_me36(frozenset()) is True and sec_me36(frozenset(["M-E36"])) is False
    ck("M-E36 decidable: by-task substitution completes falsely ONLY under the defect (killed)", killed)

    return {"min_scope": {k: sorted(v) for k, v in MIN_COMPLETION_SCOPE.items()}}
