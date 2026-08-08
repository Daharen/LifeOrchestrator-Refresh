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

# i40 Finding 4 -- the ORDERED grant-matching algorithm + the CLOSED result shape encoded AS DATA
# (not merely field declarations), pinned by canonical digest. Two implementations that both pass the
# golden vectors AND reproduce this digest cannot diverge on limits[] / multi-grant limit composition.
GRANT_MATCH_ALGORITHM = {
    "schema": "lifeorch.grant_match_algorithm/0.1-test",
    "ordered_steps": [
        "exclude grants in the revoked set",
        "tool_id == ca.tool_id",
        "operation == ca.operation (no wildcard on the ordinary path)",
        "action_namespace == ca.action_namespace",
        "validity_from <= now_ms < validity_to",
        "limits[] closed+well-formed else EXCLUDE the grant (fail closed)",
        "resolved_target_set canonical ids SUBSET of allowed_target_ids",
        "for each derived effect: class in effect_classes AND quantity <= grant_effect_limit(g,class) "
        "AND externality_rank <= externality_max AND effect_risk_class <= risk_ceiling",
    ],
    "grant_effect_limit": "min(max_quantity[class], every limits[] entry whose limit_id==class); "
                          "duplicate ids ALL apply (min); no applicable bound => uint63_max; "
                          "malformed max_quantity for the class => 0 (fail closed)",
    "conjunction_within_grant": "a grant matches ONLY if it covers ALL targets AND ALL effects",
    "alternatives_across_grants": "grants are alternatives; covered scopes UNION across matched grants",
    "effective_grant_limit_across_matched": "global MIN of grant_effect_limit over the MATCHED grants "
                                            "(the tightest covering authority bounds the effect)",
    "required_scope_rule": "required_permission_scopes SUBSET of union(matched scopes) else deny",
    "a23_effective_permit_limit": "per effect class: min(manifest resource ceiling, grant-derived, "
                                  "policy limit, approval limit)",
    "closed_result_shape": {"matched_grant_ids": "sorted_unique<id>", "ok": "bool",
                            "effective_grant_limits": "map<effect_class_nsid,uint63>"},
    "fail_closed": ["empty grant array", "no covering grant", "uncovered required scope",
                    "malformed/ambiguous/duplicate-shape limit entry", "unknown limit fields"],
    "frozen_intersection_rule": "MIN (UNCHANGED from the freeze; this is its implementation)",
}
GRANT_MATCH_ALGORITHM_DIGEST = "ff5f66bdf9fd3f14a233637fad0e34543a8a95120857a3383fb4eb809dfdeac8"
# i41 round-3 Finding 4 -- the OPERATIONAL top-level GrantView validator (stores.GRANT_VIEW_TOPLEVEL)
# pinned by canonical digest: the validator BEHAVIOR is encoded as data, not only the descriptive spec.
GRANT_VIEW_TOPLEVEL_DIGEST = "cd136af292fbd1206bcb578ef4904bc2f3c2d7d52e9576185b0cb26cc6b105e4"
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
    _matched, ok, _limits = gs.match(ca, NOW, opman)
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
    _m, ok, _lim = gs.match(_ca(), NOW, {"required_permission_scopes": ["fs.write"]})
    ck("GrantView golden: revoked grant excluded -> deny", ok is False)

    # (1b) i40 Finding 4 -- GRANT LIMIT ALGEBRA golden vectors (limits[] IMPLEMENTED + intersected).
    def _m3(grants, ca, scopes=("fs.write",)):
        g2 = S.GrantSnapshot("gsref", grants=[dict(g) for g in grants])
        return g2.match(ca, NOW, {"required_permission_scopes": list(scopes)})

    # class 1: limits.max_value < max_quantity -> the limits[] entry binds tighter than max_quantity.
    g_l = _grant({"max_quantity": {"fs.write": 100}, "limits": [{"limit_id": "fs.write", "max_value": 30}]})
    _m, ok1a, lim1 = _m3([g_l], _ca(effects=[_e(q=20)]))
    ck("F4.1 limits(30)<max_quantity(100): qty 20 matches; effective grant limit == 30",
       ok1a and lim1.get("fs.write") == 30)
    _m, ok1b, _ = _m3([g_l], _ca(effects=[_e(q=50)]))          # 50 > limits 30 (though < max_quantity 100)
    ck("F4.1 limits(30)<max_quantity(100): qty 50 > limits 30 -> deny", ok1b is False)

    # class 2: manifest ceiling < grant ceiling -> A23 effective = manifest.
    lims2 = S.effective_permit_limits([_e()], {"fs.write": 10}, {"fs.write": 100})
    ck("F4.2 manifest(10) < grant(100) -> A23 effective permit limit == 10",
       lims2 == [{"limit_id": "fs.write", "max_value": 10}])

    # class 3: grant ceiling < manifest -> A23 effective = grant.
    lims3 = S.effective_permit_limits([_e()], {"fs.write": 100}, {"fs.write": 7})
    ck("F4.3 grant(7) < manifest(100) -> A23 effective permit limit == 7",
       lims3 == [{"limit_id": "fs.write", "max_value": 7}])

    # class 4: two matching grants, different scopes AND ceilings -> scope UNION; limit = global MIN.
    gA = _grant({"grant_id": "gA", "scopes": ["s1"], "max_quantity": {"fs.write": 100},
                 "limits": [{"limit_id": "fs.write", "max_value": 100}]})
    gB = _grant({"grant_id": "gB", "scopes": ["s2"], "max_quantity": {"fs.write": 40},
                 "limits": [{"limit_id": "fs.write", "max_value": 40}]})
    _m, ok4, lim4 = _m3([gA, gB], _ca(effects=[_e(q=30)]), scopes=("s1", "s2"))
    ck("F4.4 two grants diff scopes+ceilings: qty 30 matches (scope UNION); limit = min(100,40)=40",
       ok4 and lim4.get("fs.write") == 40)

    # class 5: malformed limit entry -> the grant is untrustable -> excluded (fail closed) -> deny.
    g_bad = _grant({"limits": [{"limit_id": "fs.write", "max_value": -1}]})
    _m, ok5, _ = _m3([g_bad], _ca())
    ck("F4.5 malformed limit (negative max_value) -> grant excluded -> deny", ok5 is False)

    # class 6: duplicate limit IDs -> all apply (min). qty 10 matches @ min 20; qty 30 denies.
    g_dup = _grant({"max_quantity": {"fs.write": 100},
                    "limits": [{"limit_id": "fs.write", "max_value": 50}, {"limit_id": "fs.write", "max_value": 20}]})
    _m, ok6a, lim6 = _m3([g_dup], _ca(effects=[_e(q=10)]))
    ck("F4.6 duplicate limit ids: qty 10 matches; effective == min(50,20)=20", ok6a and lim6.get("fs.write") == 20)
    _m, ok6b, _ = _m3([g_dup], _ca(effects=[_e(q=30)]))
    ck("F4.6 duplicate limit ids: qty 30 > min(20) -> deny", ok6b is False)

    # class 7: revoked snapshot -> excluded from the algebra (tested above; asserted here on the tuple).
    gsR = S.GrantSnapshot("gsref", grants=[_grant()], revoked={"g1"})
    _m, ok7, lim7 = gsR.match(_ca(), NOW, {"required_permission_scopes": ["fs.write"]})
    ck("F4.7 revoked grant excluded from the limit algebra -> deny + empty limits", ok7 is False and lim7 == {})

    # class 8: unknown/ambiguous fields in a limit entry fail closed (closed shape {limit_id,max_value}).
    g_unk = _grant({"limits": [{"limit_id": "fs.write", "max_value": 1048576, "surprise": 1}]})
    _m, ok8, _ = _m3([g_unk], _ca())
    ck("F4.8 unknown field in a limit entry -> fail closed -> deny", ok8 is False)

    # the ORDERED matching algorithm + CLOSED result shape is pinned AS DATA (byte-exact).
    ck("F4 grant-match algorithm + closed result shape pinned by digest",
       canon.digest_of(GRANT_MATCH_ALGORITHM) == GRANT_MATCH_ALGORITHM_DIGEST,
       "got=%s" % canon.digest_of(GRANT_MATCH_ALGORITHM))

    # (1c) i41 round-3 Finding 4 -- OPERATIONAL top-level GrantView enforcement. The i40 matcher validated
    # only the closed shape of entries INSIDE limits[]; the top-level grant object was never validated, so
    # an arbitrary unknown top-level field on an otherwise-valid grant still MATCHED (the reviewer's probe).
    # The pinned CLOSED top-level field set + exact operational types are now enforced BEFORE matching.
    def _match_mut(grants, ca, muts, scopes=("fs.write",)):
        gs = S.GrantSnapshot("gsref", grants=[dict(g) for g in grants])
        _m, ok, _l = gs.match(ca, NOW, {"required_permission_scopes": list(scopes)}, mutations=muts)
        return ok

    # PIN the operational validator: its closed field set == the descriptive GRANT_VIEW pin, AND the
    # validator DATA is pinned by canonical digest (behavior encoded as data + vectors, not only a descriptor).
    _op_covers = set(S.GRANT_VIEW_TOPLEVEL["closed_fields"].keys()) == set(GRANT_VIEW["fields"].keys())
    _op_pinned = canon.digest_of(S.GRANT_VIEW_TOPLEVEL) == GRANT_VIEW_TOPLEVEL_DIGEST
    ck("F4.R3 operational GrantView closed-field set == the descriptive GRANT_VIEW pin", _op_covers)
    ck("F4.R3 operational GrantView validator pinned by canonical digest", _op_pinned,
       "got=%s" % canon.digest_of(S.GRANT_VIEW_TOPLEVEL))

    # the reviewer's exact probe: an arbitrary unknown top-level field on an otherwise-valid grant.
    g_unknown_top = _grant()
    g_unknown_top["surprise_unknown_top_level"] = "accepted"
    r4_unknown = _match([g_unknown_top], _ca()) is False
    ck("F4.R3 unknown top-level grant field -> fail closed -> deny (the reviewer's probe)", r4_unknown)

    # DECIDABLE: the SAME probe MATCHES under M-GV01 (validation skipped) and DENIES on the reference.
    r4_decidable = (_match_mut([g_unknown_top], _ca(), frozenset(["M-GV01"])) is True
                    and _match_mut([g_unknown_top], _ca(), frozenset()) is False)
    ck("F4.R3 top-level validation is load-bearing: unknown-field probe matches ONLY under M-GV01", r4_decidable)

    # missing required top-level field.
    g_missing = _grant()
    del g_missing["scopes"]
    r4_missing = _match([g_missing], _ca()) is False
    ck("F4.R3 missing required top-level grant field -> fail closed -> deny", r4_missing)

    # mistyped top-level fields (wrong JSON type).
    r4_mistyped = (_match([_grant({"risk_ceiling": "2"})], _ca()) is False
                   and _match([_grant({"validity_from": "0"})], _ca()) is False
                   and _match([_grant({"max_quantity": [1, 2]})], _ca()) is False
                   and _match([_grant({"allowed_target_ids": "not-a-list"})], _ca()) is False)
    ck("F4.R3 mistyped top-level fields (risk_ceiling/validity_from/max_quantity/allowed_target_ids) -> deny",
       r4_mistyped)

    # malformed top-level values (right type, out of domain).
    r4_malformed = (_match([_grant({"risk_ceiling": 9})], _ca()) is False
                    and _match([_grant({"externality_max": "cosmic"})], _ca()) is False
                    and _match([_grant({"approval_mode": "whenever"})], _ca()) is False
                    and _match([_grant({"max_quantity": {"fs.write": -1}})], _ca()) is False)
    ck("F4.R3 malformed top-level values (risk_ceiling/externality_max/approval_mode/max_quantity) -> deny",
       r4_malformed)

    # a fully well-formed grant still MATCHES (the validator does NOT over-reject).
    r4_wellformed = _match([_grant()], _ca()) is True
    ck("F4.R3 a fully well-formed top-level grant still matches (no over-rejection)", r4_wellformed)

    round3_f4 = bool(_op_covers and _op_pinned and r4_unknown and r4_decidable and r4_missing
                     and r4_mistyped and r4_malformed and r4_wellformed)

    # (1d) i41 round-4 Finding 4 -- END-TO-END authorize() DENY vectors (NOT just direct match() calls).
    # The round-4 blind spot: the F4 vectors above call GrantSnapshot.match() directly, exercising the
    # validator INSIDE the matcher but never the earlier A11 grant_namespaces() read (the monitor calls
    # grant_namespaces() at A11, BEFORE match()). grant_namespaces() now routes through the ONE shared
    # validated-grant iterator, so a malformed grant fails closed to CONSTANT DENY at A11 -- never an
    # uncaught KeyError. Each vector runs the FULL monitor on a TEST-ONLY non_execution=false packet (so
    # execution REACHES A11) and requires: DENY + constant caller bytes + NO permit + NO exception + no
    # reachable state diff.
    from tests import harness as _h
    from action_authz.monitor import authorize as _authz, PermitRef
    from action_authz.boundary import MockExecutor as _Exec

    def _e2e_deny(corrupt):
        st, prop = _h.build_baseline()
        corrupt(st.grants["grant_snap_1"].grants[0])
        try:
            d = _authz(_h.prop_bytes(prop), st, mutations=frozenset())
        except Exception:                       # a raw-field dereference before validation would RAISE
            return {"ok": False, "raised": True}
        # no permit issued + constant caller bytes + the executor can produce no state diff (no permit).
        r = _Exec(st).execute(PermitRef("permit_ghost", id(st.permits)))
        ok = (d.outcome == "DENY" and d.caller_bytes == S.CONSTANT_DENIAL_BYTES
              and len(st.permits._permits) == 0 and r.state_diff == [])
        return {"ok": ok, "raised": False, "reason": d.reason_code}

    def _del(field):
        return lambda g: g.pop(field, None)

    def _set(field, val):
        return lambda g: g.__setitem__(field, val)

    def _add_unknown(g):
        g["surprise_unknown_top_level"] = "accepted"

    _e2e_cases = [
        ("unknown top-level grant field", _add_unknown),
        ("missing grant_id (the A11 KeyError probe)", _del("grant_id")),
        ("missing action_namespace (the A11 KeyError probe)", _del("action_namespace")),
        ("mistyped risk_ceiling (str)", _set("risk_ceiling", "2")),
        ("mistyped allowed_target_ids (not a list)", _set("allowed_target_ids", "nope")),
        ("malformed max_quantity (negative)", _set("max_quantity", {"fs.write": -1})),
        ("malformed externality_max (out of domain)", _set("externality_max", "cosmic")),
    ]
    f4_e2e_all = True
    for name, corrupt in _e2e_cases:
        res = _e2e_deny(corrupt)
        ck("F4.R4 end-to-end authorize(): %s -> constant DENY, no permit, no exception, no state diff" % name,
           res["ok"], "raised=%s reason=%s" % (res.get("raised"), res.get("reason")))
        if not res["ok"]:
            f4_e2e_all = False

    # DECIDABLE + load-bearing at A11: under M-GV01 the shared validated-grant iterator SKIPS validation, so
    # a grant MISSING grant_id makes the A11 grant_namespaces() read dereference a raw field -> it RAISES;
    # the reference (validated) path instead fails closed to constant DENY. This proves the pre-validation is
    # what closes the A11 KeyError path (the round-4 defect), not an incidental later check.
    def _raises_under(muts):
        st, prop = _h.build_baseline()
        st.grants["grant_snap_1"].grants[0].pop("grant_id", None)
        try:
            _authz(_h.prop_bytes(prop), st, mutations=muts)
            return False
        except Exception:
            return True
    f4_a11_loadbearing = (_raises_under(frozenset(["M-GV01"])) is True
                          and _raises_under(frozenset()) is False)
    ck("F4.R4 A11 pre-validation is load-bearing: a missing-grant_id grant raises ONLY under M-GV01 "
       "(the reference fails closed to constant DENY at A11)", f4_a11_loadbearing)

    round4_f4 = bool(f4_e2e_all and f4_a11_loadbearing)

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

    return {"view_digests": VIEW_DIGESTS, "round3_f4_toplevel_grantview": round3_f4,
            "round4_f4_prevalidation": round4_f4}
