"""
views_golden.py -- byte-exact test-facing views + INDEPENDENT golden vectors (contract s6 amendment 2;
red-team Finding 3).

The five closed test-view schemas (lifeorch.grant_view / policy_view / approval_view / status_view /
validator_view 0.1-test) are specified byte-exactly in SCHEMA_NOTES.md; their CLOSED field-set +
matching-algebra specs are mirrored here as data and pinned by canonical digest (VIEW_DIGESTS). The
golden vectors below have MANUALLY-DERIVED expected results (not read off the implementation) and are
run through the ACTUAL matchers (stores.GrantSnapshot.match / PolicyView.apply / ApprovalStore /
StatusStore + boundary.MIN_COMPLETION_SCOPE) so the contract is independently DECIDABLE: any drift in
the consumed shape or matching algebra flips a golden vector.
"""

from action_authz import canon, stores as S
from action_authz.boundary import MIN_COMPLETION_SCOPE
from action_authz.schemas import UINT63_MAX

# --- the byte-exact CLOSED view specs (mirror of SCHEMA_NOTES; digest = the pin) -----------------
GRANT_VIEW = {"schema": "lifeorch.grant_view/0.1-test", "fields": {
    "grant_id": "id", "tool_id": "nsid", "operation": "nsid|*", "action_namespace": "nsid",
    "allowed_target_ids": "array<id>", "effect_classes": "array<nsid>", "max_quantity": "map<nsid,uint63>",
    "externality_max": "enum{local,private_external,public_external}", "risk_ceiling": "uint{0..4}",
    "validity_from": "uint63", "validity_to": "uint63", "approval_mode": "enum{none,policy_dependent,always}",
    "scopes": "array<nsid>", "limits": "array<{limit_id:nsid,max_value:uint63}>"}}
POLICY_VIEW = {"schema": "lifeorch.policy_view/0.1-test", "fields": {
    "policy_ref": "id", "epoch": "uint63", "current": "bool",
    "escalation": "public_external|irreversible => risk>=3 & approval=always", "weakening": "forbidden"}}
APPROVAL_VIEW = {"schema": "lifeorch.approval_view/0.1-test", "fields": {
    "approval_ref": "id", "canonical_action_digest": "sha256", "task_id": "id", "namespace": "nsid",
    "manifest_version": "uint63", "manifest_digest": "sha256", "grant_snapshot_ref": "id",
    "state": "enum{approved,...}", "revoked": "bool", "expiry_unix_ms": "uint63"}}
STATUS_VIEW = {"schema": "lifeorch.status_view/0.1-test", "fields": {
    "predicate_kind": "enum{executor_status,human_approval,test_suite,artifact_hash,object_state,postcondition}",
    "source_id": "nsid", "source_version": "uint63", "subject": "map<str,scalar>", "namespace": "nsid",
    "at_ms": "uint63", "superseded": "bool", "revoked": "bool"}}
VALIDATOR_VIEW = {"schema": "lifeorch.validator_view/0.1-test", "fields": {
    "min_completion_scope": {"executor_status": ["permit"], "state_diff": ["permit"],
                             "artifact_hash": ["action", "object", "permit"], "test_suite": ["action", "object"],
                             "object_state": ["object"], "human_approval": ["approval"],
                             "postcondition": ["action", "permit"]},
    "resolution": "contract via immutable packet_id; leaf subject DERIVED FROM PERMIT; else indeterminate"}}

VIEW_DIGESTS = {
    "grant_view": "c956a0ffea3ff7f6411adb6f43e54193bc103e9185b287b670a0311630bfe486",
    "policy_view": "7244a9de66d790d5aeb5e9d3806fc7d451ccafd47f8573b5d04a656b69cc9f00",
    "approval_view": "c09474ef17d93957b3ae5e0fe99e188c8e463baa605768da287c4f26fccf5ce8",
    "status_view": "247c0ba8e8f8956c5b8112ea29496e00e5f86476cfbc0b511cc402ccf3b9240b",
    "validator_view": "fe277edda1c368b85d26a787ec562a1715e07640ad58c68acabd50f168e5bd6c",
}
NOW = 1_700_000_000_000


def _t(tid="/u/data/projA/one.txt", ns="projA"):
    return {"target_kind": "fs.file", "canonical_target_id": tid, "namespace": ns,
            "resolution_kind": "existing", "resolution_proof_digest": "b" * 64}


def _e(cls="fs.write", q=1, ext="local", risk=2, rev="compensatable"):
    return {"effect_class": cls, "target_index": 0, "quantity": q, "unit": "bytes",
            "effect_risk_class": risk, "externality": ext, "reversibility": rev}


def _ca(op="fs.write", ns="projA", targets=None, effects=None):
    return {"tool_id": "fs.local", "operation": op, "action_namespace": ns,
            "resolved_target_set": targets or [_t()], "derived_effect_set": effects or [_e()]}


def _grant(over=None):
    g = {"grant_id": "g1", "tool_id": "fs.local", "operation": "fs.write", "action_namespace": "projA",
         "allowed_target_ids": ["/u/data/projA/one.txt"], "effect_classes": ["fs.write"],
         "max_quantity": {"fs.write": 1048576}, "externality_max": "local", "risk_ceiling": 2,
         "validity_from": 0, "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
         "scopes": ["fs.write"], "limits": [{"limit_id": "fs.write", "max_value": 1048576}]}
    if over:
        g.update(over)
    return g


def _match(grants, ca, scopes=("fs.write",)):
    gs = S.GrantSnapshot("gsref", grants=[dict(g) for g in grants])
    opman = {"required_permission_scopes": list(scopes)}
    _matched, ok = gs.match(ca, NOW, opman)
    return ok


def run(check):
    ck = check.ok
    # (0) the view SPECS are byte-exact: their canonical digest matches the pin (SCHEMA_NOTES source).
    for nm, spec in (("grant_view", GRANT_VIEW), ("policy_view", POLICY_VIEW), ("approval_view", APPROVAL_VIEW),
                     ("status_view", STATUS_VIEW), ("validator_view", VALIDATOR_VIEW)):
        ck("view %s spec digest matches the pinned byte-exact spec" % nm,
           canon.digest_of(spec) == VIEW_DIGESTS[nm], "got=%s" % canon.digest_of(spec))

    # (1) GrantView matcher golden vectors (manual expectations) ------------------------------------
    G = [
        ("exact single grant covers", [_grant()], _ca(), True),
        ("alternative grants: one covers", [_grant({"grant_id": "gx", "operation": "fs.delete"}), _grant()], _ca(), True),
        ("empty grant array -> deny", [], _ca(), False),
        ("target not in allowed_target_ids -> deny", [_grant({"allowed_target_ids": ["/u/data/projA/other.txt"]})], _ca(), False),
        ("effect class not granted -> deny", [_grant({"effect_classes": ["fs.read"]})], _ca(), False),
        ("limit intersection: quantity > max -> deny", [_grant({"max_quantity": {"fs.write": 3}})], _ca(effects=[_e(q=5)]), False),
        ("out-of-window (future validity_from) -> deny", [_grant({"validity_from": NOW + 1})], _ca(), False),
        ("expired (validity_to <= now) -> deny", [_grant({"validity_to": NOW})], _ca(), False),
        ("wrong operation -> deny", [_grant()], _ca(op="fs.delete"), False),
        ("wrong action_namespace -> deny", [_grant()], _ca(ns="projB", targets=[_t(ns="projB")]), False),
        ("externality over max -> deny", [_grant({"externality_max": "local"})], _ca(effects=[_e(ext="public_external")]), False),
        ("risk over ceiling -> deny", [_grant({"risk_ceiling": 2})], _ca(effects=[_e(risk=4)]), False),
        ("required scope not covered -> deny", [_grant({"scopes": []})], _ca(), False),
    ]
    for name, grants, ca, expect in G:
        ck("GrantView golden: %s" % name, _match(grants, ca) is expect, "expected %s" % expect)

    # a REVOKED grant is excluded from matching (conjunction over the live set).
    gs = S.GrantSnapshot("gsref", grants=[_grant()], revoked={"g1"})
    _m, ok = gs.match(_ca(), NOW, {"required_permission_scopes": ["fs.write"]})
    ck("GrantView golden: revoked grant excluded -> deny", ok is False)

    # (2) PolicyView golden: escalate for public/irreversible; never weaken. -----------------------
    pv = S.PolicyView("p")
    r_pub, a_pub, _s, dz = pv.apply({"derived_effect_set": [_e(ext="public_external")]}, 1, "none", "sb")
    ck("PolicyView golden: public_external -> risk>=3 & approval=always", r_pub >= 3 and a_pub == "always" and dz is False)
    r_irr, a_irr, _s, _d = pv.apply({"derived_effect_set": [_e(rev="irreversible")]}, 1, "none", "sb")
    ck("PolicyView golden: irreversible -> risk>=3 & approval=always", r_irr >= 3 and a_irr == "always")
    r_loc, a_loc, _s, _d = pv.apply({"derived_effect_set": [_e()]}, 2, "policy_dependent", "sb")
    ck("PolicyView golden: local effect never weakens base risk/approval",
       r_loc >= 2 and S._APPROVAL_RANK[a_loc] >= S._APPROVAL_RANK["policy_dependent"])

    # (3) ApprovalView golden: exact digest+task+ns+manifest+grant binding; any mismatch/revoked/expired -> None.
    base = {"approval_ref": "appr", "canonical_action_digest": "a" * 64, "task_id": "t", "namespace": "projA",
            "manifest_version": 1, "manifest_digest": "m" * 64, "grant_snapshot_ref": "gs",
            "state": "approved", "revoked": False, "expiry_unix_ms": 9_000_000_000_000_000}

    def _find(over=None, cad="a" * 64, task="t", ns="projA", mv=1, md="m" * 64, gs2="gs"):
        st = S.ApprovalStore()
        rec = dict(base)
        if over:
            rec.update(over)
        st.put(rec)
        return st.find_by_digest(cad, task, ns, mv, md, gs2, NOW) is not None
    ck("ApprovalView golden: exact binding -> found", _find() is True)
    ck("ApprovalView golden: cad mismatch -> None", _find(cad="b" * 64) is False)
    ck("ApprovalView golden: task mismatch -> None", _find(task="other") is False)
    ck("ApprovalView golden: namespace mismatch -> None", _find(ns="projB") is False)
    ck("ApprovalView golden: manifest digest mismatch -> None", _find(md="n" * 64) is False)
    ck("ApprovalView golden: grant snapshot mismatch -> None", _find(gs2="other") is False)
    ck("ApprovalView golden: revoked -> None", _find(over={"revoked": True}) is False)
    ck("ApprovalView golden: expired -> None", _find(over={"expiry_unix_ms": 1}) is False)

    # (4) StatusView golden: subject-exact; superseded/stale/wrong-version/out-of-scope -> None. ----
    def _sfind(over=None, subject=None, ns="projA", max_age=60000, sv=1):
        st = S.StatusStore()
        rec = {"predicate_kind": "executor_status", "result_code": "ok", "exit_code": 0,
               "source_id": "exec.fs/1", "source_version": 1, "at_ms": NOW, "namespace": "projA",
               "superseded": False, "revoked": False, "subject": {"task_id": "t", "canonical_action_digest": "a" * 64}}
        if over:
            rec.update(over)
        st.put(rec)
        return st.find("executor_status", "exec.fs/1", sv, subject or {"task_id": "t", "canonical_action_digest": "a" * 64},
                       NOW, max_age, ns) is not None
    ck("StatusView golden: subject-exact match -> found", _sfind() is True)
    ck("StatusView golden: subject mismatch -> None", _sfind(subject={"canonical_action_digest": "b" * 64}) is False)
    ck("StatusView golden: superseded -> None", _sfind(over={"superseded": True}) is False)
    ck("StatusView golden: stale (age>max) -> None", _sfind(over={"at_ms": NOW - 10_000_000}) is False)
    ck("StatusView golden: wrong validator source_version -> None", _sfind(sv=2) is False)
    ck("StatusView golden: out-of-scope namespace -> None", _sfind(over={"namespace": "projB"}) is False)

    # (5) ValidatorView golden: the per-leaf minimum-scope table matches the pinned spec byte-exactly.
    ck("ValidatorView golden: MIN_COMPLETION_SCOPE == the pinned validator_view spec",
       {k: sorted(v) for k, v in MIN_COMPLETION_SCOPE.items()} == VALIDATOR_VIEW["fields"]["min_completion_scope"])

    return {"view_digests": VIEW_DIGESTS}
