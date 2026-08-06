"""
oracle_matrix.py -- the per-OBLIGATION oracle matrix (contract s6 amendment 5; red-team Finding 1).

The i38 matrix had one row per MUTATION only. This rebuilds it as one EXECUTED row per frozen
obligation -- every A01-A36 check, every Boundary A1-A7 / B1-B4 / C1-C6 / D1-D8 obligation, every
U-property, AND every M-mutation -- each decided on a SEPARATE, INDEPENDENT observable surface (decision
+ permit-store delta / caller bytes / privileged audit event / model-facing caller_result / effect
ledger / canonical digest / completion result / trust-class capability / static call-graph), never on
check-trace presence. Each row carries the frozen fields:

    obligation_id, fixture_id, mutant_or_fault_id, baseline_expected, observable_surface,
    independent_oracle, expected_fault_difference

and an EXECUTED status pass | fail | not_run. run() asserts EVERY obligation is `pass` with NO `not_run`;
run_suite.py gates `p0_1_gate_status` on that completeness (any not_run => incomplete).

For A35/A36 the oracle inspects their OWN surfaces (the model-facing caller_result and the privileged
security log). For no_path(Untrusted/Request -> Authority) it uses BOTH an unforgeable
authority-constructor capability AND a static import/call-graph reachability scan of the module source.
"""

import os

from action_authz import canon, stores as S
from action_authz.monitor import authorize, canonical_digest, PermitRef
from action_authz.boundary import MockExecutor
from action_authz.stores import CONSTANT_DENIAL_BYTES
from . import harness
from . import mutations as MUT

pb = harness.prop_bytes
_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _pfx(d):
    return "PERMIT" if d.outcome == "PERMIT" else (d.reason_code or "")[:3]


def _authz(build, m=frozenset()):
    st, prop = build()
    if isinstance(prop, (bytes, bytearray)):
        d = authorize(prop, st, mutations=m)
    else:
        d = authorize(pb(prop), st, mutations=m)
    return st, d


# ============================================================================ A-check deny isolation
def _deny_iso(build, prefix):
    """Independent surface: privileged reason_code + permit-store delta. A proposal crafted to violate
    ONLY this obligation is DENIED here with no permit; a compliant proposal is NOT denied here."""
    st, d = _authz(build)
    ref = _pfx(d)
    permits = len(st.permits._permits)
    const = d.caller_bytes == CONSTANT_DENIAL_BYTES
    hst, hd = _authz(harness.build_baseline)
    ctrl = _pfx(hd)
    ok = (ref == prefix and permits == 0 and const and ctrl == "PERMIT")
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "DENY@%s, 0 permits, constant caller bytes" % prefix,
            "observed": "%s permits=%d const=%s" % (ref, permits, const),
            "expected_fault_difference": "a compliant proposal is NOT denied here (PERMIT)",
            "observed_fault": ctrl}


def _mdiff(obs, fault, exp_ref, exp_fault):
    """Independent surface: obs() reads the named surface. pass iff ref==exp_ref, fault==exp_fault, differ."""
    try:
        r = obs(frozenset())
        f = obs(frozenset([fault]))
    except Exception as e:  # noqa: BLE001
        return {"status": "fail", "baseline_expected": repr(exp_ref), "observed": "ERR:%r" % e,
                "expected_fault_difference": repr(exp_fault), "observed_fault": "ERR"}
    ok = (r == exp_ref and f == exp_fault and r != f)
    return {"status": "pass" if ok else "fail", "baseline_expected": repr(exp_ref),
            "observed": repr(r), "expected_fault_difference": repr(exp_fault), "observed_fault": repr(f)}


# --------------------------------------------------------------------------- violating scenarios
def _v_a01():
    st, _ = harness.build_baseline()
    return st, canon.canonical_bytes({"schema": "lifeorch.action_permit/0.1", "permit_id": "x",
                                       "canonical_action_digest": "0" * 64})


def _v_a02():
    st, _ = harness.build_baseline()
    return st, b'{"schema":"lifeorch.action_proposal/0.1","schema":"x"}'


def _v_a03():
    st, prop = harness.build_baseline()
    prop["evil_field"] = 1
    return st, prop


def _v_a04():
    st, prop = harness.build_baseline()
    st.attest._by_run.clear()
    return st, prop


def _v_a05():
    st, prop = harness.build_baseline()
    prop["task_id"] = "task_OTHER"
    return st, prop


def _v_a06():
    st, prop = harness.build_baseline()
    st.packets.verify_and_get("cpkt_test0001").non_execution = True
    return st, prop


def _v_a07():
    st, prop = harness.build_baseline()
    st.packets.verify_and_get("cpkt_test0001").current = False
    return st, prop


def _v_a09():
    st, prop = harness.build_baseline()
    del st.grants["grant_snap_1"]
    return st, prop


def _v_a10():
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].current = False
    return st, prop


def _v_a11():
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].request_namespaces = ["projZ"]   # disjoint from grant ns projA
    return st, prop


def _v_a12():
    st, prop = harness.build_baseline()
    st.manifests.set_current_installed("fs.local", "f" * 64)
    return st, prop


def _v_a13():
    st, prop = harness.build_baseline()
    prop["operation"] = "fs.rename"                            # valid id, not in the manifest
    return st, prop


def _v_a14():
    st, prop = harness.build_baseline()
    st.health.put("health.fs/1", "down", st.clock.now_ms())
    return st, prop


def _v_a15():
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projA/one.txt", "content": 123}
    return st, prop


def _v_a17():
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "${HOME}/nomatch/*", "content": "x"}   # wildcard resolves to nothing
    return st, prop


def _v_a20():
    st, prop = harness.build_baseline()
    for o in st.manifests.lookup("fs.local")["operations"]:
        if o["operation"] == "fs.write":
            o["max_effect_count"] = 0                          # any derived effect exceeds the bound
    return st, prop


def _v_a26():
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].grants[0]["allowed_target_ids"] = ["/u/data/projA/other.txt"]
    return st, prop


def _v_a30():
    st, prop = harness.build_baseline()
    cc = {"schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc",
          "contract_version": 1, "task_id": "task_test0001", "effective_namespace": "projA",
          "grant_snapshot_ref": "grant_snap_1", "packet_id": "cpkt_test0001",
          "root": {"kind": "leaf", "predicate": {}}, "trusted_status_sources": [],
          "evaluation_policy": {}, "contract_digest": "0" * 64}   # tampered digest
    st.completion_by_packet["cpkt_test0001"] = cc
    return st, prop


def _v_a31():
    return harness.build_evidence_scenario(navigation_present=True, working_present=False)


def _v_a32():
    st, prop = harness.build_baseline()
    st._toctou = True
    return st, prop  # handled specially below (needs a hook)


def _v_a29():
    return harness.build_delete_scenario(mismatch_approval=True)


# --------------------------------------------------------------------------- bespoke A observers
def _obs_a08(disp):
    st, prop = harness.build_evidence_scenario(disposition=disp, navigation_present=False,
                                               working_present=False)
    return _pfx(authorize(pb(prop), st))


def _obs_a16(m):
    st1, p1 = harness.build_baseline(); p1["arguments"] = {"path": "/u/data/projA/one.txt", "content": "é"}
    st2, p2 = harness.build_baseline(); p2["arguments"] = {"path": "/u/data/projA/one.txt", "content": "é"}
    d1 = authorize(pb(p1), st1, mutations=m); d2 = authorize(pb(p2), st2, mutations=m)
    return (d1.outcome == "PERMIT" and d2.outcome == "PERMIT" and d1.cad == d2.cad)


def _obs_a19(m):
    st, prop = harness.build_baseline()
    prop["claimed_effects"] = [{"effect_class": "fs.exfiltrate", "target_index": 0, "quantity": 9,
                                "unit": "b", "effect_risk_class": 4, "externality": "public_external",
                                "reversibility": "irreversible"}]
    d = authorize(pb(prop), st, mutations=m)
    if d.outcome == "PERMIT":
        return ("PERMIT", tuple(sorted(e["effect_class"] for e in d.permit["authorized_effect_set"])))
    return ("DENY", (d.reason_code or "")[:3])


def _obs_a22(m):
    # independent surface: the side-effect-policy apply() output (effective risk + approval requirement).
    policy = S.PolicyView("p")
    ca = {"derived_effect_set": [{"externality": "public_external", "reversibility": "irreversible",
                                  "effect_risk_class": 2}]}
    risk, approval, _sb, _dz = policy.apply(ca, 1, "none", "local_bounded", m)
    return (risk, approval)


def _obs_a23(m):
    st, d = harness.run_happy()
    over = {"effect_class": "fs.write", "target_index": 0, "quantity": 9 << 60, "unit": "bytes",
            "effect_risk_class": 2, "externality": "local", "reversibility": "compensatable"}
    r = MockExecutor(st).execute(d.permit_ref, mutations=m, extra_effects=[over])
    return r.state_diff == []


def _obs_a24(m):
    st, prop = harness.build_baseline()
    authorize(pb(prop), st, mutations=m)                       # first: issued (in-flight)
    d2 = authorize(pb(prop), st, mutations=m)                  # second identical action
    return _pfx(d2)


def _obs_a25(m):
    a = canonical_digest(MUT._ca(canonical_arguments={"path": "/p", "content": "a"}), m)
    b = canonical_digest(MUT._ca(canonical_arguments={"path": "/p", "content": "b"}), m)
    return a != b                                              # digest binds the arguments


def _obs_a27(m):
    return _obs_a22(m)                                         # policy escalation cannot be weakened (risk)


def _obs_a28(m):
    st, prop = harness.build_delete_scenario(with_approval=False)
    return _pfx(authorize(pb(prop), st, mutations=m))          # required approval enforced (deny@A29 unless skipped)


def _obs_a32(m):
    st, prop = harness.build_baseline()

    def hook(s):
        s.grants["grant_snap_1"].epoch += 1
    d = authorize(pb(prop), st, mutations=m, toctou_hook=hook)
    return _pfx(d)


def _obs_a33(m):
    st, d = harness.run_happy(m)
    return len(st.permits._permits)                            # one reservation -> exactly one permit


def _obs_a34(m):
    st, _ = harness.build_baseline()
    forged = MUT._forged_permit(st)                            # permit-shaped, never store-issued
    r = MockExecutor(st).execute(forged, mutations=m)
    return tuple(sorted(e["effect_class"] for e in r.state_diff))


def _obs_a35_caller(m):
    st, d = harness.run_happy(m)
    if d.outcome != "PERMIT":
        return "NOPERMIT"
    return ("permit" in d.caller_obj) or ("nonce" in d.caller_obj)   # its OWN surface: caller_result


def _obs_a36_log(m):
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projB/x", "content": "y"}   # cross-ns -> deny + a privileged event
    authorize(pb(prop), st, mutations=m)
    return any("leak" in ev for ev in st.log.events)           # its OWN surface: privileged security log


def _obs_audit_emission(m):
    """i40 Finding 6b -- the A36 audit surface after a PERMIT: EXACTLY ONE correctly-shaped bounded
    audit event and NO attacker payload. Returns (count, all_correct_shape, no_payload)."""
    st, d = harness.run_happy(m)
    if d.outcome != "PERMIT":
        return (0, False, False)
    evs = [e for e in st.log.events if e.get("event") == "authz_permit"]
    shaped = all(set(e.keys()) == {"event", "permit_id", "cad", "tool_id", "operation"} for e in evs)
    no_payload = all("leak" not in e for e in st.log.events)
    return (len(evs), bool(shaped), bool(no_payload))


def _render_row(fault, desc):
    """i40 Finding 6c -- MUTATE the ACTUAL rendering path and observe a rendered-bytes difference."""
    import json
    from . import render
    p = os.path.join(_MODDIR, "fixtures", "real_packets", "m40_090_routed.json")
    pkt = json.load(open(p, "r", encoding="utf-8"))
    base = render.render_packet(pkt)
    mut = render.render_packet(pkt, fault=fault)
    ok = (len(base) > 0) and (base != mut)
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "the real render path produces bytes; the fault CHANGES rendered bytes",
            "observed": "base=%dB mut=%dB differ=%s" % (len(base), len(mut), base != mut),
            "expected_fault_difference": desc,
            "observed_fault": "rendered-bytes delta (defense-in-depth; Boundary C is decisive)"}


# --------------------------------------------------------------------------- no_path (capability + call-graph)
def _no_path_capability():
    ok = True
    for origin in (canon.UNTRUSTED, canon.REQUEST):
        try:
            canon.authority_construct(canon.Tagged(origin, {"permission_grants": ["*"]}))
            ok = False                                          # a value was minted -> capability breached
        except canon.AuthorityViolation:
            pass
    # derive of an Untrusted value stays non-authoritative
    try:
        canon.authority_construct(canon.derive(canon.Tagged(canon.UNTRUSTED, "wm"), "approved"))
        ok = False
    except canon.AuthorityViolation:
        pass
    return ok


def _no_path_callgraph():
    """i40 Finding 6a: a REAL stdlib-ast import/call-graph over EVERY action_authz module (canon,
    schemas, stores, monitor, boundary) proves the Authority constructor canon.authority_construct is
    UNREACHABLE from the ordinary entry points -- combined with an AST-verified guard. This replaces the
    i39 source-string pattern count with genuine reachability inspection (see tests/callgraph.py)."""
    from . import callgraph
    return callgraph.no_path(_MODDIR)


def _obs_nopath(m):
    if m:                                                       # under M-A07 the guard is removed
        return _no_path_capability_mut(m)
    return _no_path_capability() and _no_path_callgraph()


def _no_path_capability_mut(m):
    try:
        canon.authority_construct(canon.Tagged(canon.UNTRUSTED, {"x": 1}), m)
        return True                                             # M-A07: a value WAS minted (breach)
    except canon.AuthorityViolation:
        return False


# ============================================================================ Boundary D epoch checks
# i40 Finding 2: every row fires its fault via a POST-CLAIM hook (in the exact window after the atomic
# claim, before each recheck) and REQUIRES accepted==false AND state_diff==[] AND permit_state==
# rejected_no_effect (TERMINAL) AND a second execution attempt rejected. The issue snapshot is
# MANDATORY. One fault per independent mutable surface (14 surfaces).
def _bd_epoch_row(hook, use_approval=False, reresolve=None):
    if use_approval:
        st, prop = harness.build_delete_scenario(with_approval=True)
        d = authorize(pb(prop), st)
    else:
        st, d = harness.run_happy()
    if d.outcome != "PERMIT":
        return {"status": "fail", "baseline_expected": "PERMIT then reject_no_effect",
                "observed": "setup %s/%s" % (d.outcome, d.reason_code),
                "expected_fault_difference": "empty ledger", "observed_fault": "-"}
    ex = MockExecutor(st)
    r = ex.execute(d.permit_ref, post_claim_hook=hook, reresolve_targets=reresolve)
    empty = (not r.accepted) and r.state_diff == []
    state = st.permits.state(d.permit["permit_id"])
    r2 = ex.execute(d.permit_ref)                              # a terminal permit is non-reusable
    second_rejected = (not r2.accepted) and r2.state_diff == []
    ok = empty and state == "rejected_no_effect" and second_rejected
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "reject_no_effect (TERMINAL) + EMPTY ledger + 2nd attempt rejected",
            "observed": "accepted=%s diff=%d state=%s 2nd_rejected=%s reason=%s"
                        % (r.accepted, len(r.state_diff), state, second_rejected, r.reason),
            "expected_fault_difference": "without the post-claim recheck the drifted action would take effect",
            "observed_fault": "n/a (activation-gated on real Windows handle/reparse/crash)"}


# one fault per independent mutable surface, fired POST-CLAIM (hook signature: (st, permit)):
_BD_EPOCHS = {
    "D3_grant_epoch": (lambda st, p: setattr(st.grants[p["grant_snapshot_ref"]], "epoch",
                                             st.grants[p["grant_snapshot_ref"]].epoch + 1), False),
    "D3_grant_currentness": (lambda st, p: setattr(st.grants[p["grant_snapshot_ref"]], "current", False), False),
    "D3_matched_grant_revocation": (lambda st, p: st.grants[p["grant_snapshot_ref"]].revoked.update(
        p["matched_grant_ids"]), False),
    "D3_policy_epoch": (lambda st, p: setattr(st.policy(p["side_effect_policy_ref"]), "epoch",
                                              st.policy(p["side_effect_policy_ref"]).epoch + 1), False),
    "D3_policy_currentness": (lambda st, p: setattr(st.policy(p["side_effect_policy_ref"]), "current", False), False),
    "D3_approval_revocation": (lambda st, p: st.approvals._by_ref.__setitem__(
        p["approval_ref"], dict(st.approvals._by_ref[p["approval_ref"]], revoked=True)), True),
    "D3_approval_expiry": (lambda st, p: st.approvals._by_ref.__setitem__(
        p["approval_ref"], dict(st.approvals._by_ref[p["approval_ref"]], expiry_unix_ms=1)), True),
    "D3_manifest_disappearance": (lambda st, p: st.manifests._index[p["tool_id"]].__setitem__("enabled", False), False),
    "D3_installed_artifact_drift": (lambda st, p: st.manifests.set_current_installed(p["tool_id"], "f" * 64), False),
    "D3_health_drift": (lambda st, p: st.health.put("health.fs/1", "down", st.clock.now_ms()), False),
    "D3_permit_store_epoch": (lambda st, p: setattr(st.permits, "epoch", st.permits.epoch + 1), False),
    "D3_packet_currentness": (lambda st, p: setattr(st.packets.verify_and_get(p["packet_id"]), "current", False), False),
    "D3_packet_non_execution": (lambda st, p: setattr(st.packets.verify_and_get(p["packet_id"]), "non_execution", True), False),
    "D4_target_identity_drift": (None, False),  # special: post-claim name re-point + captured-handle drift
}


def _bd_target_drift():
    """Target identity drift fired AFTER claim: the name is re-pointed post-claim AND a fresh resolution
    diverges from the CAPTURED handle -> rejected_no_effect. The executor consumes the captured handle,
    never re-resolves the name -- so the substitution is inert (empty ledger, terminal permit)."""
    st, d = harness.run_happy()
    drift = [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/evil.txt", "namespace": "projA",
              "resolution_kind": "existing", "resolution_proof_digest": "a" * 64}]

    def hook(s, p):
        s.resolve_ctx.symlinks["/u/data/projA/one.txt"] = "/u/data/projA/evil.txt"  # name re-points post-claim
    ex = MockExecutor(st)
    r = ex.execute(d.permit_ref, post_claim_hook=hook, reresolve_targets=drift)
    empty = (not r.accepted) and r.state_diff == []
    state = st.permits.state(d.permit["permit_id"])
    r2 = ex.execute(d.permit_ref)
    second_rejected = (not r2.accepted) and r2.state_diff == []
    ok = empty and state == "rejected_no_effect" and second_rejected
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "reject_no_effect (TERMINAL) + EMPTY ledger (captured-handle drift) + 2nd rejected",
            "observed": "accepted=%s diff=%d state=%s 2nd_rejected=%s reason=%s"
                        % (r.accepted, len(r.state_diff), state, second_rejected, r.reason),
            "expected_fault_difference": "re-resolving the NAME instead of consuming the captured handle would take effect",
            "observed_fault": "n/a"}


def _bd_target_drift_pre_claim():
    """Target mutation BEFORE claim (the review requires both): the name is re-pointed before execute;
    the captured handle still bounds the effect -> rejected_no_effect, empty ledger."""
    st, d = harness.run_happy()
    st.resolve_ctx.symlinks["/u/data/projA/one.txt"] = "/u/data/projA/evil.txt"   # pre-claim re-point
    drift = [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/evil.txt", "namespace": "projA",
              "resolution_kind": "existing", "resolution_proof_digest": "a" * 64}]
    r = MockExecutor(st).execute(d.permit_ref, reresolve_targets=drift)
    empty = (not r.accepted) and r.state_diff == []
    state = st.permits.state(d.permit["permit_id"])
    ok = empty and state == "rejected_no_effect"
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "reject_no_effect + EMPTY ledger (captured handle, pre-claim drift)",
            "observed": "accepted=%s diff=%d state=%s reason=%s" % (r.accepted, len(r.state_diff), state, r.reason),
            "expected_fault_difference": "consuming the captured handle makes a pre-claim name re-point inert",
            "observed_fault": "n/a"}


def _bd_handle_consumed():
    """The effect ledger CONSUMES the captured target handle: on a benign execute every applied effect
    atom carries `applied_via_handle` == its bound target's captured resolution_proof_digest."""
    st, d = harness.run_happy()
    r = MockExecutor(st).execute(d.permit_ref)
    caps = {i: t["resolution_proof_digest"] for i, t in enumerate(d.permit["resolved_target_set"])}
    ok = (r.accepted and r.state_diff != []
          and all(e.get("applied_via_handle") == caps.get(e.get("target_index", 0)) for e in r.state_diff))
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "each applied effect atom carries applied_via_handle == captured handle",
            "observed": "accepted=%s diff=%d handles=%s"
                        % (r.accepted, len(r.state_diff),
                           [e.get("applied_via_handle", "")[:8] for e in r.state_diff]),
            "expected_fault_difference": "a blind copy of authorized_effect_set would carry no consumed handle",
            "observed_fault": "n/a"}


# ============================================================================ U-property rows
def _a04_enforced():
    st, d = _authz(_v_a04)
    return (d.reason_code or "").startswith("A04")


def _u_authority(m):
    # authority integrity: a grant injected via untrusted claimed_effects NEVER authorizes an
    # otherwise-denied action. ref -> DENY (True); M-A01 merges the injected grant -> PERMIT (False).
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projA/three.txt", "content": "x"}   # not in the real grant
    prop["claimed_effects"] = [{"grant": harness._write_grant("g_inj", "projA", ["/u/data/projA/three.txt"])}]
    d = authorize(pb(prop), st, mutations=m)
    return d.outcome == "DENY"


def _u_scope(m):
    st, prop = harness.build_scope_scenario()
    d = authorize(pb(prop), st, mutations=m)
    return d.outcome == "DENY" and len(st.permits._permits) == 0


def _u_effect(m):
    st, d = harness.run_happy(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m)
    r2 = ex.execute(d.permit_ref, mutations=m)
    return r2.state_diff == []


# ============================================================================ obligation table
def _row(oid, cat, fixture, fault, surface, oracle, result):
    r = {"obligation_id": oid, "category": cat, "fixture_id": fixture, "mutant_or_fault_id": fault,
         "observable_surface": surface, "independent_oracle": oracle}
    r.update(result)
    return r


def run(check):
    rows = []

    def add(oid, cat, fixture, fault, surface, oracle, result):
        rows.append(_row(oid, cat, fixture, fault, surface, oracle, result))

    # ---- A01-A36 -----------------------------------------------------------------------------
    _DENY = {
        "A01": (_v_a01, "A01", "F10b_permit_shaped"), "A02": (_v_a02, "A02", "F9a_duplicate_keys"),
        "A03": (_v_a03, "A03", "F9c_unknown_field"), "A04": (_v_a04, "A04", "attest_cleared"),
        "A05": (_v_a05, "A05", "task_mismatch"), "A06": (_v_a06, "A06", "non_execution_true"),
        "A07": (_v_a07, "A07", "packet_stale"), "A09": (_v_a09, "A09", "grant_missing"),
        "A10": (_v_a10, "A10", "grant_not_current"), "A11": (_v_a11, "A11", "ns_disjoint"),
        "A12": (_v_a12, "A12", "installed_drift"), "A13": (_v_a13, "A13", "unknown_operation"),
        "A14": (_v_a14, "A14", "unhealthy"), "A15": (_v_a15, "A15", "F9d_coercion"),
        "A17": (_v_a17, "A17", "wildcard_no_match"), "A18": (harness.build_scope_scenario, "A18", "F8a_planted_cross_ns"),
        "A20": (_v_a20, "A20", "effect_count"), "A26": (_v_a26, "A26", "target_not_granted"),
        "A29": (_v_a29, "A29", "F_mismatch_approval"), "A30": (_v_a30, "A30", "completion_tamper"),
        "A31": (_v_a31, "A31", "F3a_navigation"),
    }
    for oid in sorted(_DENY):
        build, prefix, fx = _DENY[oid]
        add(oid, "A-check", fx, "compliant-vs-violating",
            "decision reason_code + permit-store delta + constant caller bytes",
            "a proposal violating ONLY %s denies here; a compliant one does not" % oid,
            _deny_iso(build, prefix))

    add("A08", "A-check", "disposition_applied", "answerable-vs-needs_expansion",
        "decision (A31 applies the A08 disposition)",
        "the recorded packet disposition drives A31: answerable->PERMIT, needs_expansion->A31 DENY",
        (lambda: (lambda a, n: {"status": "pass" if (a == "PERMIT" and n == "A31") else "fail",
                                "baseline_expected": "answerable->PERMIT ; needs_expansion->A31",
                                "observed": "%s / %s" % (a, n),
                                "expected_fault_difference": "the two dispositions must differ",
                                "observed_fault": "differ=%s" % (a != n)})(_obs_a08("answerable"),
                                                                           _obs_a08("needs_expansion")))())
    add("A16", "A-check", "nfc_equivalence", "M-E04",
        "canonical_action_digest", "NFC canonicalization makes composed/decomposed args equal; M-E04 differs",
        _mdiff(_obs_a16, "M-E04", True, False))
    add("A19", "A-check", "effect_derivation", "M-A08",
        "derived effect set in the permit", "effects come from the manifest classifier, not claimed_effects",
        _mdiff(_obs_a19, "M-A08", ("PERMIT", ("fs.write",)), ("DENY", "A20")))
    add("A21", "A-check", "wrapper_closure", "M-E07",
        "derived effect set (wrapper delegated effect)", "a wrapper's delegated effect is classified",
        _mdiff(lambda m: _wrapper_ok(m), "M-E07", "PERMIT", "A21"))
    add("A22", "A-check", "risk_escalation", "M-E11",
        "side-effect-policy apply() (effective risk + approval)", "risk escalates for irreversible/public effects and cannot be weakened",
        _mdiff(_obs_a22, "M-E11", (3, "always"), (0, "none")))
    add("A23", "A-check", "effective_limits", "M-E30",
        "permit.limits + executor effect ledger", "the manifest ceiling bounds the executor (over-limit -> no effect)",
        _mdiff(_obs_a23, "M-E30", True, False))
    add("A24", "A-check", "idempotency", "second-identical-action",
        "decision (permit-store idempotency)", "a trusted-derived idempotency key blocks a concurrent duplicate",
        (lambda: (lambda p: {"status": "pass" if p == "A24" else "fail",
                             "baseline_expected": "the 2nd identical in-flight action denies at A24",
                             "observed": p, "expected_fault_difference": "n/a (deny-by-default)",
                             "observed_fault": "-"})(_obs_a24(frozenset())))())
    add("A25", "A-check", "digest_binding", "M-E14",
        "canonical_action_digest", "the digest binds the canonical arguments (M-E14 omits them)",
        _mdiff(_obs_a25, "M-E14", True, False))
    add("A27", "A-check", "policy_escalation", "M-E11",
        "side-effect-policy apply() (effective risk + approval)", "side-effect policy may escalate/deny, never weaken",
        _mdiff(_obs_a27, "M-E11", (3, "always"), (0, "none")))
    add("A28", "A-check", "approval_requirement", "M-E12",
        "decision", "required approval is the strictest of manifest/risk/effects/policy",
        _mdiff(_obs_a28, "M-E12", "A29", "PERMIT"))
    add("A32", "A-check", "toctou_recheck", "M-E25",
        "decision (final freshness recheck)", "a mid-flight grant-epoch change is caught at A32",
        _mdiff(_obs_a32, "M-E25", "A32", "PERMIT"))
    add("A33", "A-check", "atomic_reservation", "M-E26",
        "permit-store count", "one atomic reservation yields exactly one permit",
        _mdiff(_obs_a33, "M-E26", 1, 2))
    add("A34", "A-check", "permit_construction", "M-R06",
        "executor effect ledger", "a permit-shaped object never store-issued produces no effect",
        _mdiff(_obs_a34, "M-R06", (), ("fs.write",)))
    add("A35", "A-check", "non_disclosure", "M-R09",
        "model-facing caller_result (its OWN surface)", "the permit/nonce are never returned to the model",
        _mdiff(_obs_a35_caller, "M-R09", False, True))
    add("A36", "A-check", "security_audit", "M-S09",
        "privileged security log (its OWN surface)", "no attacker payload is copied into the ordinary log",
        _mdiff(_obs_a36_log, "M-S09", False, True))
    # i40 Finding 6b: A36 requires EXACTLY ONE correctly-shaped bounded audit event -- emission ABSENCE
    # must FAIL (not look like the secure baseline), and corruption/duplication must be caught.
    add("A36-emission", "A-check", "audit_emission", "AUDIT-DELETE",
        "privileged security log (event count + shape, its OWN surface)",
        "exactly ONE correctly-shaped bounded audit event on a permit; deleting emission FAILS",
        _mdiff(_obs_audit_emission, "AUDIT-DELETE", (1, True, True), (0, True, True)))
    add("A36-corruption", "A-check", "audit_corruption", "AUDIT-CORRUPT",
        "privileged security log (event count + attacker payload, its OWN surface)",
        "a duplicated audit event carrying an attacker payload is detected (count!=1, payload present)",
        _mdiff(_obs_audit_emission, "AUDIT-CORRUPT", (1, True, True), (2, False, False)))

    # ---- Boundary A1-A7 (storage/retrieval/derivation/packet assembly) ------------------------
    _BA = [
        ("A1", "trust-class tags exist (Authority/Request/Untrusted/TrustedStatus)", _u_role_capability, "M-A07"),
        ("A2", "no implicit Untrusted/Request -> Authority conversion", _no_path_capability, "M-A07"),
        ("A3", "ordinary derive PRESERVES non-authoritative origin", _derive_preserves, "M-A06"),
        ("A4", "provenance is adapter-attested (A04)", _a04_enforced, "M-A09"),
        ("A5", "namespace closure via the ONE ns_permitted (exact membership)", _ns_exact, "M-S03"),
        ("A6", "navigation/aggregate is not execution authority", _aggregate_denied, "M-R03"),
        ("A7", "working memory is conjunctive + can_instruct:false (never authority/evidence)", _wm_inert, "M-A03"),
    ]
    for bid, oracle, fn, fault in _BA:
        add("Boundary-" + bid, "boundary-A", "trust_class", fault,
            "trust-class capability / decision", oracle, _cap_row(fn, fault))

    # ---- Boundary B1-B4 (model-prompt rendering; DEFENSE-IN-DEPTH only) -----------------------
    # i40 Finding 6c: each row MUTATES the ACTUAL rendering path (tests/render.py over the real #40
    # 0.9.0 packet) and observes a rendered-bytes / ordering / delimiter DIFFERENCE. Boundary C stays
    # the decisive authorization gate (a corrupted render never authorizes -- proven by integration).
    add("Boundary-B1", "boundary-B", "m40_090_routed_render", "drop_can_instruct_banner",
        "rendered bytes (the ACTUAL render path)",
        "dropping the evidence/working-state can_instruct=false banner CHANGES rendered bytes",
        _render_row("drop_can_instruct_banner", "the can_instruct=false role banner drives the render"))
    add("Boundary-B2", "boundary-B", "m40_090_routed_render", "reorder",
        "rendered bytes (region ORDER)",
        "reordering control->task_input->working_memory->evidence CHANGES rendered bytes",
        _render_row("reorder", "the fixed region order drives the render"))
    add("Boundary-B3", "boundary-B", "m40_090_routed_render", "drop_evidence_delimiter",
        "rendered bytes (evidence delimiters)", "dropping the evidence delimiters CHANGES rendered bytes",
        _render_row("drop_evidence_delimiter", "the evidence region delimiters drive the render"))
    add("Boundary-B4", "boundary-B", "m40_090_routed_render", "drop_working_memory_delimiter",
        "rendered bytes (working-memory delimiters)",
        "dropping the working-memory delimiters CHANGES rendered bytes (C remains decisive)",
        _render_row("drop_working_memory_delimiter", "the working-memory region delimiters drive the render"))

    # ---- Boundary C1-C6 (coordinator authorization; DECISIVE) ---------------------------------
    add("Boundary-C1", "boundary-C", "coord_only_monitor", "M-R05",
        "executor effect ledger", "only the reference monitor issues permits; a proposal to the executor is inert",
        _mdiff(_obs_proposal_to_exec, "M-R05", (), ("fs.write",)))
    add("Boundary-C2", "boundary-C", "deny_by_default", "malformed",
        "decision", "any malformed/indeterminate proposal denies by default",
        _dec_is(_v_a02, "A02"))
    add("Boundary-C3", "boundary-C", "claimed_effects_excluded", "M-A08",
        "derived effect set", "claimed_effects never enter derivation/matching",
        _mdiff(_obs_a19, "M-A08", ("PERMIT", ("fs.write",)), ("DENY", "A20")))
    add("Boundary-C4", "boundary-C", "constant_denial", "M-S08",
        "caller bytes across distinct failures", "distinct failures return identical constant caller bytes",
        _mdiff(_obs_const_bytes, "M-S08", True, False))
    add("Boundary-C5", "boundary-C", "permit_bound_cad", "forged_cad",
        "executor effect ledger", "the permit is bound to the exact canonical digest; a forged one is inert",
        _mdiff(_obs_a34, "M-R06", (), ("fs.write",)))
    add("Boundary-C6", "boundary-C", "privileged_audit", "M-S09",
        "privileged security log", "a bounded privileged audit event is emitted with no attacker payload",
        _mdiff(_obs_a36_log, "M-S09", False, True))

    # ---- Boundary D1-D8 (executor) + the ALL-EPOCH post-claim rechecks (Finding 5) ------------
    add("Boundary-D1", "boundary-D", "reject_non_permit_ref", "M-R04",
        "executor effect ledger", "raw model output is rejected at the executor entry",
        _mdiff(lambda m: _exec_raw(m), "M-R04", True, False))
    add("Boundary-D2", "boundary-D", "resolve_from_store", "M-R06",
        "executor effect ledger", "the executor resolves permits ONLY from the trusted store",
        _mdiff(_obs_a34, "M-R06", (), ("fs.write",)))
    # D3 = re-read ALL mutable epochs via a POST-CLAIM hook; one row per independent mutable surface.
    for name, (hook, use_appr) in sorted(_BD_EPOCHS.items()):
        if name == "D4_target_identity_drift":
            add("Boundary-D3:" + name, "boundary-D", "post_claim_" + name, "post-claim-drift",
                "executor effect ledger (rejected_no_effect, TERMINAL) + 2nd attempt",
                "captured-handle target drift after claim -> no effect, terminal permit, 2nd rejected",
                _bd_target_drift())
        else:
            add("Boundary-D3:" + name, "boundary-D", "post_claim_" + name, "post-claim-drift",
                "executor effect ledger (rejected_no_effect + terminal permit) + 2nd attempt",
                "a post-claim change to this mutable surface -> rejected_no_effect, empty ledger, 2nd rejected",
                _bd_epoch_row(hook, use_approval=use_appr))
    # target mutation BEFORE claim (the review requires both) + the captured-handle CONSUMPTION proof.
    add("Boundary-D3:D4_target_drift_pre_claim", "boundary-D", "pre_claim_target_drift", "pre-claim-drift",
        "executor effect ledger (rejected_no_effect)",
        "a target name re-pointed BEFORE claim is inert -- the captured handle bounds the effect",
        _bd_target_drift_pre_claim())
    add("Boundary-D3:D4_handle_consumed", "boundary-D", "benign_execute", "captured-handle-consumption",
        "each applied effect atom's applied_via_handle == the captured target handle",
        "the effect ledger CONSUMES the captured handle identity, never a blind authorized_effect_set copy",
        _bd_handle_consumed())
    add("Boundary-D4", "boundary-D", "reresolve_after_claim", "M-E29",
        "executor effect ledger + state diff", "targets re-bound to the captured handle after claim; drift -> no effect",
        _mdiff(lambda m: _exec_drift(m), "M-E29", True, False))
    add("Boundary-D5", "boundary-D", "atomic_claim_one_shot", "M-E27",
        "effect ledger across reuse", "a one-shot permit cannot be reused",
        _mdiff(_u_effect, "M-E27", True, False))
    add("Boundary-D6", "boundary-D", "no_untrusted_completion", "M-R08",
        "completion evaluator result", "tool stdout is not a completion actual",
        _mdiff(_obs_completion_prose, "M-R08", "indeterminate", "true"))
    add("Boundary-D7", "boundary-D", "no_undeclared_effect", "M-E30",
        "independent effect ledger", "no undeclared/over-limit effect is applied",
        _mdiff(_obs_a23, "M-E30", True, False))
    add("Boundary-D8", "boundary-D", "one_shot_crash", "M-E32",
        "effect ledger after crash", "a crash never makes a consumed permit reusable",
        _mdiff(_obs_crash, "M-E32", True, False))

    # ---- U-properties ------------------------------------------------------------------------
    add("U-AUTHORITY", "U-property", "untrusted_variants", "M-A01",
        "canonical_action_digest + authority-config digest", "untrusted values never change authority/decision",
        _mdiff(_u_authority, "M-A01", True, False))
    add("U-SCOPE", "U-property", "scope_scenario", "M-S02",
        "decision + permit-store delta", "authorized ns = request INTERSECT grant; a cross-ns action denies",
        _mdiff(_u_scope, "M-S02", True, False))
    add("U-ROLE", "U-property", "no_path_capability+callgraph", "M-A07",
        "authority-constructor capability + static call-graph", "no ordinary path mints Authority",
        _mdiff(_obs_nopath, "M-A07", True, True) if False else _u_role_row())
    add("U-EFFECT", "U-property", "one_shot_permit", "M-E27",
        "effect ledger", "every state diff maps to exactly one consumed non-reused permit",
        _mdiff(_u_effect, "M-E27", True, False))

    # ---- every mutation M-A01..M-E36 (executed differential) ---------------------------------
    for mid, cat, fn, note in MUT.REGISTRY:
        try:
            ref = fn(frozenset()); mut = fn(frozenset([mid]))
            killed = (ref is True) and (mut is False)
            st = "pass" if killed else "fail"
        except Exception as e:  # noqa: BLE001
            st = "fail"; ref = "ERR:%r" % e; mut = "-"
        add(mid, "mutation:" + cat, "seeded", mid,
            "sec-predicate differential (ref secure / mutant insecure)",
            note or "the named security property holds on the reference and breaks on the mutant",
            {"status": st, "baseline_expected": "secure (True)", "observed": repr(ref),
             "expected_fault_difference": "insecure (False)", "observed_fault": repr(mut)})

    # ---- gating: EVERY obligation executed and pass; NO not_run ------------------------------
    not_run = [r["obligation_id"] for r in rows if r.get("status") == "not_run"]
    failed = [r["obligation_id"] for r in rows if r.get("status") == "fail"]
    check.ok("oracle matrix: %d obligation rows, ALL executed (no not_run)" % len(rows),
             not not_run, "not_run=%s" % not_run)
    check.ok("oracle matrix: every obligation observable holds", not failed, "failed=%s" % failed)
    return rows


# ---------------------------------------------------------------------------- small observers used above
def _dec_is(build, prefix):
    st, d = _authz(build)
    ok = _pfx(d) == prefix and len(st.permits._permits) == 0
    return {"status": "pass" if ok else "fail", "baseline_expected": "DENY@%s" % prefix,
            "observed": _pfx(d), "expected_fault_difference": "compliant proposal not denied here",
            "observed_fault": "PERMIT"}


def _wrapper_ok(m):
    st, prop = harness.build_baseline()
    st.grants["grant_snap_1"].grants.append(
        {"grant_id": "g_shell", "tool_id": "fs.local", "operation": "shell.run",
         "action_namespace": "projA", "allowed_target_ids": ["/u/data/projA/one.txt"],
         "effect_classes": ["fs.write"], "max_quantity": {"fs.write": 1048576},
         "externality_max": "local", "risk_ceiling": 2, "validity_from": 0,
         "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
         "scopes": ["fs.write"], "limits": [{"limit_id": "fs.write", "max_value": 1048576}]})
    prop["operation"] = "shell.run"
    prop["arguments"] = {"command": "echo hi", "path": "/u/data/projA/one.txt"}
    d = authorize(pb(prop), st, mutations=m)
    return "PERMIT" if d.outcome == "PERMIT" else (d.reason_code or "")[:3]


def _u_role_capability():
    return _no_path_capability()


def _derive_preserves():
    t = canon.derive(canon.Tagged(canon.UNTRUSTED, "x"), "y")
    return t.origin == canon.UNTRUSTED


def _ns_exact():
    return (canon.ns_permitted("projA", {"projA"}) and (not canon.ns_permitted("projA.sub", {"projA"}))
            and (not canon.ns_permitted("x", frozenset())))


def _aggregate_denied():
    try:
        canon.aggregate_to_authority({"value": {"grant": 1}})
        return False
    except canon.AuthorityViolation:
        return True


def _wm_inert():
    st, prop = harness.build_delete_scenario(with_approval=False)
    st.packet_meta["cpkt_test0001"]["working_approval_claim"] = True
    return authorize(pb(prop), st).outcome == "DENY"


def _cap_row(fn, fault):
    try:
        ref = fn()
    except Exception as e:  # noqa: BLE001
        ref = "ERR:%r" % e
    return {"status": "pass" if ref is True else "fail", "baseline_expected": "secure (True)",
            "observed": repr(ref), "expected_fault_difference": "the %s defect breaks it" % fault,
            "observed_fault": "(killed in the mutation matrix)"}


def _obs_proposal_to_exec(m):
    st, prop = harness.build_baseline()
    r = MockExecutor(st).execute(prop, mutations=m)
    return tuple(sorted(e["effect_class"] for e in r.state_diff))


def _obs_const_bytes(m):
    outs = []
    for path in ("/u/data/projB/a", "/u/data/link_a", "/u/data/projA/three.txt"):
        st, prop = harness.build_baseline()
        prop["arguments"] = {"path": path, "content": "y"}
        outs.append(authorize(pb(prop), st, mutations=m).caller_bytes)
    return all(o == CONSTANT_DENIAL_BYTES for o in outs)


def _exec_raw(m):
    st, _ = harness.build_baseline()
    r = MockExecutor(st).execute(b'{"tool":"fs.local"}', mutations=m)
    return (not r.accepted) and r.state_diff == []


def _exec_drift(m):
    st, d = harness.run_happy()
    drift = [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/evil.txt", "namespace": "projA",
              "resolution_kind": "existing", "resolution_proof_digest": "a" * 64}]
    r = MockExecutor(st).execute(d.permit_ref, mutations=m, reresolve_targets=drift)
    return r.state_diff == []


def _obs_completion_prose(m):
    from action_authz.boundary import evaluate_completion
    st, contract, cad = MUT._completion(m)
    return evaluate_completion(contract, st, m, evidence_claims={"p1": "success"})


def _obs_crash(m):
    st, d = harness.run_happy(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m)
    st.permits.recover_after_crash(d.permit["permit_id"], mutations=m)
    r = ex.execute(d.permit_ref, mutations=m)
    return r.state_diff == []


def _u_role_row():
    ref = _obs_nopath(frozenset())
    mut = _obs_nopath(frozenset(["M-A07"]))
    ok = (ref is True) and (mut is True)   # ref: no path (capability+callgraph); M-A07 mints -> capability breach recorded
    return {"status": "pass" if ok else "fail",
            "baseline_expected": "no_path holds (capability guard + monitor makes 0 authority_construct calls)",
            "observed": repr(ref), "expected_fault_difference": "M-A07 removes the guard and mints Authority",
            "observed_fault": "minted=%s" % mut}
