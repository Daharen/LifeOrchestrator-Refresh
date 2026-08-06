"""
mutations.py -- the mandatory SEEDED-MUTATION kill harness (contract s8.6, M-A01..M-E36).

For each mutation M, a `sec` predicate returns True iff the named security property HOLDS. "Killed" =
sec(reference) is True AND sec({M}) is False -- i.e., a test that is green on the reference impl goes
red on the mutant. Emits the kill matrix (each M -> COVERED->killed | STAGED->reason).

Every M-* the MVP monitor + mock executor surface reaches is COVERED and killed at the MVP/logical
level. `depth_note` records where the PRODUCTION Windows/OS enforcement depth is STAGED to i38 (real
permit-store IPC/ACL/crash recovery = Blocker 3; per-tool reparse/ADS/junction profiles = Blocker 4).
"""

from action_authz import canon, stores as S
from action_authz.monitor import authorize, canonical_digest
from action_authz.boundary import MockExecutor, evaluate_completion
from . import harness

pb = harness.prop_bytes
_EXFIL = {"effect_class": "fs.exfiltrate", "target_index": 0, "quantity": 1, "unit": "bytes",
          "effect_risk_class": 4, "externality": "public_external", "reversibility": "irreversible"}


# --------------------------------------------------------------------------- helpers
def _authz(build, muts):
    st, prop = build()
    return st, authorize(pb(prop), st, mutations=muts)


def _denies(build, muts):
    _st, d = _authz(build, muts)
    return d.outcome == "DENY"


def _happy_permit(muts):
    st, prop = harness.build_baseline()
    return st, authorize(pb(prop), st, mutations=muts)


def _ca(**over):
    ca = {"schema": "lifeorch.canonical_action/0.1", "tool_id": "fs.local", "tool_manifest_version": 1,
          "tool_manifest_digest": "a" * 64, "operation": "fs.write",
          "canonical_arguments": {"path": "/u/data/projA/one.txt", "content": "x"},
          "resolved_target_set": [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/one.txt",
                                   "namespace": "projA", "resolution_kind": "existing",
                                   "resolution_proof_digest": "b" * 64}],
          "derived_effect_set": [{"effect_class": "fs.write", "target_index": 0, "quantity": 1,
                                  "unit": "bytes", "effect_risk_class": 2, "externality": "local",
                                  "reversibility": "compensatable"}],
          "action_namespace": "projA", "risk_class": 2, "sandbox_class": "local_bounded",
          "limits": [{"limit_id": "fs.write", "max_value": 1048576}], "idempotency_key": "idem_x"}
    ca.update(over)
    return ca


def _completion(muts, put_status=None):
    st, _ = harness.build_baseline()
    cad = "e" * 64
    contract = {
        "schema": "lifeorch.completion_contract/0.1", "completion_contract_id": "cc", "contract_version": 1,
        "task_id": "task_test0001", "effective_namespace": "projA", "grant_snapshot_ref": "grant_snap_1",
        "root": {"kind": "leaf", "predicate": {
            "predicate_id": "p1", "predicate_kind": "executor_status", "source_id": "exec.fs/1",
            "source_version": 1, "subject_binding": {"task_id": "task_test0001", "canonical_action_digest": cad},
            "max_age_ms": 60000, "expected": {"allowed_result_codes": ["ok"], "allowed_exit_codes": [0]}}},
        "trusted_status_sources": [{"source_id": "exec.fs/1", "source_version": 1,
                                    "status_schema": "s/1", "code_digest": "a" * 64, "max_age_ms": 60000}],
        "evaluation_policy": {"missing": "indeterminate", "malformed": "indeterminate",
                              "stale": "indeterminate", "indeterminate_is_complete": False},
    }
    contract["contract_digest"] = canon.digest_omitting(contract, "contract_digest")
    if put_status:
        st.status.put(put_status(cad))
    return st, contract, cad


def _raises_authority(fn):
    try:
        fn()
        return False
    except canon.AuthorityViolation:
        return True


# --------------------------------------------------------------------------- sec predicates
# ===== AUTHORITY =====
def sec_a01(m):
    def build():
        st, prop = harness.build_baseline()
        prop["arguments"] = {"path": "/u/data/projA/three.txt", "content": "x"}  # not in the real grant
        prop["claimed_effects"] = [{"grant": harness._write_grant("g_inj", "projA", ["/u/data/projA/three.txt"])}]
        return st, prop
    return _denies(build, m)


def sec_a02(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].grants[0]["scopes"] = []           # real grant covers no scope
        prop["claimed_effects"] = [{"card": {"required_permission_scopes": []}}]
        return st, prop
    return _denies(build, m)


def sec_a03(m):
    def build():
        st, prop = harness.build_delete_scenario(with_approval=False)
        st.packet_meta["cpkt_test0001"]["working_approval_claim"] = True
        return st, prop
    return _denies(build, m)


def sec_a04(m):
    st, contract, cad = _completion(m)
    return evaluate_completion(contract, st, m, evidence_claims={"p1": "success"}) != "true"


def sec_a05(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].grants = []                        # packet's snapshot authorizes nothing
        st.grants["grant_snap_broad"] = S.GrantSnapshot(
            "grant_snap_broad", grants=[harness._write_grant("gb", "projA", ["/u/data/projA/one.txt"])],
            request_namespaces=["projA"])
        prop["claimed_effects"] = [{"grant_snapshot_ref": "grant_snap_broad"}]
        return st, prop
    return _denies(build, m)


def sec_a06(m):
    return _raises_authority(lambda: canon.authority_construct(
        canon.derive(canon.Tagged(canon.UNTRUSTED, "x"), "y", m), m))


def sec_a07(m):
    return _raises_authority(lambda: canon.authority_construct(canon.Tagged(canon.UNTRUSTED, {"g": 1}), m))


def sec_a08(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].grants[0]["max_quantity"] = {"fs.write": 3}
        prop["arguments"] = {"path": "/u/data/projA/one.txt", "content": "hello"}  # 5 bytes > 3
        prop["claimed_effects"] = [{"effect_class": "fs.write", "target_index": 0, "quantity": 1,
                                    "unit": "bytes", "effect_risk_class": 2, "externality": "local",
                                    "reversibility": "compensatable"}]
        return st, prop
    return _denies(build, m)


def sec_a09(m):
    def build():
        st, prop = harness.build_baseline()
        st.attest._by_run.clear()                                    # no adapter attestation
        return st, prop
    return _denies(build, m)


def sec_a10(m):
    def build():
        st, prop = harness.build_baseline()
        st.health.put("health.fs/1", "down", st.clock.now_ms())
        return st, prop
    return _denies(build, m)


# ===== SCOPE =====
def sec_s01(m):
    return "projB" not in canon.effective_namespaces({"projA", "projB"}, {"projA"}, m)


def sec_s02(m):
    return "projB" not in canon.effective_namespaces({"projA"}, {"projA", "projB"}, m)


def sec_s03(m):
    return (not canon.ns_permitted("x", frozenset(), m)) and (not canon.ns_permitted("projA.sub", {"projA"}, m))


def sec_s04(m):
    return _denies(harness.build_scope_scenario, m)


def sec_s05(m):
    def build():
        st, prop = harness.build_baseline()
        st.resolve_ctx.transitive_ns["/u/data/projA/one.txt"] = ["projB"]  # out-of-scope constituent
        return st, prop
    return _denies(build, m)


def sec_s06(m):
    return _denies(harness.build_symlink_scenario, m)


def sec_s07(m):
    return _denies(harness.build_multi_ns_scenario, m)


def sec_s08(m):
    _st, d = _authz(lambda: (harness.build_baseline()[0], _cross_prop()), m)
    return d.caller_bytes == S.CONSTANT_DENIAL_BYTES


def _cross_prop():
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projB/x", "content": "y"}
    return prop


def sec_s08b(m):
    # explicit: distinct failures return identical constant caller bytes (no oracle)
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projB/x", "content": "y"}
    d = authorize(pb(prop), st, mutations=m)
    return d.caller_bytes == S.CONSTANT_DENIAL_BYTES


def sec_s09(m):
    st, prop = harness.build_baseline()
    prop["arguments"] = {"path": "/u/data/projB/x", "content": "y"}
    authorize(pb(prop), st, mutations=m)
    return all("leak" not in ev for ev in st.log.events)


def sec_s10(m):
    def put(cad):
        return {"predicate_kind": "executor_status", "result_code": "ok", "exit_code": 0,
                "source_id": "exec.fs/1", "source_version": 1, "at_ms": 1_700_000_000_000,
                "namespace": "projB",  # out of the contract's effective namespace
                "subject": {"task_id": "task_test0001", "canonical_action_digest": cad}}
    st, contract, cad = _completion(m, put)
    return evaluate_completion(contract, st, m) != "true"


# ===== ROLE =====
def sec_r01(m):
    def build():
        return harness.build_evidence_scenario(navigation_present=True, working_present=False)
    return _denies(build, m)


def sec_r02(m):
    def build():
        return harness.build_evidence_scenario(navigation_present=False, working_present=True)
    return _denies(build, m)


def sec_r03(m):
    return _raises_authority(lambda: canon.aggregate_to_authority({"value": {"grant": 1}}, m))


def sec_r04(m):
    st, _ = harness.build_baseline()
    r = MockExecutor(st).execute(b'{"tool":"fs.local","op":"fs.write"}', mutations=m)
    return (not r.accepted) and r.state_diff == []


def sec_r05(m):
    st, prop = harness.build_baseline()
    r = MockExecutor(st).execute(prop, mutations=m)
    return (not r.accepted) and r.state_diff == []


def sec_r06(m):
    st, _ = harness.build_baseline()
    forged = _forged_permit(st)
    r = MockExecutor(st).execute(forged, mutations=m)
    return r.state_diff == []


def _forged_permit(st):
    man = st.manifests.lookup("fs.local")
    p = {"schema": "lifeorch.action_permit/0.1", "permit_id": "permit_forged", "issuer": "x",
         "issuer_version": 1, "issued_at_unix_ms": st.clock.now_ms(),
         "expiry_unix_ms": st.clock.now_ms() + 60000, "task_id": "task_test0001", "packet_id": "cpkt_test0001",
         "canonical_action_digest": "0" * 64, "tool_id": "fs.local", "tool_manifest_version": 1,
         "tool_manifest_digest": man["manifest_digest"], "operation": "fs.write",
         "canonical_arguments": {"path": "/u/data/projA/one.txt", "content": "x"}, "risk_class": 2,
         "resolved_target_set": [], "authorized_effect_set": [{"effect_class": "fs.write", "target_index": 0,
                                                               "quantity": 1, "unit": "bytes",
                                                               "effect_risk_class": 2, "externality": "local",
                                                               "reversibility": "compensatable"}],
         "effective_namespace": "projA", "grant_snapshot_ref": "grant_snap_1", "matched_grant_ids": ["g_write"],
         "side_effect_policy_ref": "policy_1", "limits": [], "sandbox_class": "local_bounded",
         "nonce": "0" * 32, "idempotency_key": "idem_forged", "permit_store_epoch": st.permits.epoch}
    p["permit_digest"] = canon.digest_omitting(p, "permit_digest")
    return p


def sec_r07(m):
    st, contract, cad = _completion(m)
    return evaluate_completion(contract, st, m, evidence_claims={"task": "complete"}) != "true"


def sec_r08(m):
    st, contract, cad = _completion(m)
    return evaluate_completion(contract, st, m, evidence_claims={"p1": "success"}) != "true"


def sec_r09(m):
    _st, d = _happy_permit(m)
    return d.outcome == "PERMIT" and "permit" not in d.caller_obj and "nonce" not in d.caller_obj


def sec_r10(m):
    return _denies(harness.build_absence_scenario, m)


def sec_r11(m):
    # amendment 6 / R1-ROLE-1: the #40 0.8.0 router stage-trace is a non-authoritative
    # diagnostic; casting it into evidence coverage (M-R11) must not authorize an
    # evidence-dependent action against a non-answerable packet.
    def build():
        st, prop = harness.build_evidence_scenario(navigation_present=False, working_present=False)
        st.packet_meta["cpkt_test0001"]["routing_present"] = True
        return st, prop
    return _denies(build, m)


# ===== EFFECT / CANON / REPLAY / TOCTOU =====
def sec_e01(m):
    try:
        canon.strict_parse(b'{"a":1,"a":2}', canon.PROPOSAL_MAX_BYTES, m)
        return False
    except canon.CanonError:
        return True


def sec_e02(m):
    def build():
        st, prop = harness.build_baseline()
        prop["evil_unknown"] = 1
        return st, prop
    return _denies(build, m)


def sec_e03(m):
    def build():
        st, prop = harness.build_baseline()
        prop["arguments"] = {"path": "/u/data/projA/one.txt", "content": 123}
        return st, prop
    return _denies(build, m)


def sec_e04(m):
    a = canonical_digest(_ca(canonical_arguments={"path": "/p", "content": "é"}), m)  # composed
    b = canonical_digest(_ca(canonical_arguments={"path": "/p", "content": "é"}), m)  # decomposed
    # In the full pipeline NFC canonicalization makes these equal; here we assert the reference
    # DISTINGUISHES only because canonicalization is applied -- proven end-to-end below via the monitor.
    st1, p1 = harness.build_baseline(); p1["arguments"] = {"path": "/u/data/projA/one.txt", "content": "é"}
    st2, p2 = harness.build_baseline(); p2["arguments"] = {"path": "/u/data/projA/one.txt", "content": "é"}
    d1 = authorize(pb(p1), st1, mutations=m)
    d2 = authorize(pb(p2), st2, mutations=m)
    return d1.outcome == "PERMIT" and d2.outcome == "PERMIT" and d1.cad == d2.cad


def sec_e05(m):
    return _denies(harness.build_symlink_scenario, m)


def sec_e06(m):
    return _denies(harness.build_symlink_scenario, m)


def sec_e07(m):
    def build():
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
        return st, prop
    st, d = _authz(build, m)
    return d.outcome == "PERMIT" and "fs.write" in {e["effect_class"] for e in d.permit["authorized_effect_set"]}


def sec_e08(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].grants[0]["operation"] = "fs.append"  # not the proposed op
        return st, prop
    return _denies(build, m)


def sec_e09(m):
    def build():
        st, prop = harness.build_baseline()
        prop["arguments"] = {"path": "/u/data/projA/two.txt", "content": "x"}  # granted? one.txt+two.txt
        st.grants["grant_snap_1"].grants[0]["allowed_target_ids"] = ["/u/data/projA/one.txt"]  # only one.txt
        return st, prop
    return _denies(build, m)


def sec_e10(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].grants[0]["max_quantity"] = {"fs.write": 3}
        prop["arguments"] = {"path": "/u/data/projA/one.txt", "content": "hello"}  # 5 > 3
        return st, prop
    return _denies(build, m)


def sec_e11(m):
    policy = S.PolicyView("p")
    ca = {"derived_effect_set": [{"externality": "public_external", "reversibility": "irreversible",
                                  "effect_risk_class": 2}]}
    risk, approval, _sb, _dz = policy.apply(ca, 1, "none", "local_bounded", m)
    return approval == "always" and risk >= 3


def sec_e12(m):
    return _denies(lambda: harness.build_delete_scenario(with_approval=False), m)


def sec_e13(m):
    return _denies(lambda: harness.build_delete_scenario(mismatch_approval=True), m)


def sec_e14(m):
    return canonical_digest(_ca(canonical_arguments={"path": "/p", "content": "a"}), m) != \
        canonical_digest(_ca(canonical_arguments={"path": "/p", "content": "b"}), m)


def sec_e15(m):
    t2 = [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/two.txt", "namespace": "projA",
           "resolution_kind": "existing", "resolution_proof_digest": "b" * 64}]
    return canonical_digest(_ca(), m) != canonical_digest(_ca(resolved_target_set=t2), m)


def sec_e16(m):
    e2 = [{"effect_class": "fs.write", "target_index": 0, "quantity": 999, "unit": "bytes",
           "effect_risk_class": 2, "externality": "local", "reversibility": "compensatable"}]
    return canonical_digest(_ca(), m) != canonical_digest(_ca(derived_effect_set=e2), m)


def sec_e17(m):
    return canonical_digest(_ca(action_namespace="projA"), m) != canonical_digest(_ca(action_namespace="projB"), m)


def sec_e18(m):
    return canonical_digest(_ca(), m, caller_digest="0" * 64) != "0" * 64


def sec_e19(m):
    def build():
        st, prop = harness.build_baseline()
        st.packets.verify_and_get("cpkt_test0001").non_execution = True
        return st, prop
    return _denies(build, m)


def sec_e20(m):
    def build():
        st, prop = harness.build_baseline()
        st.grants["grant_snap_1"].current = False
        return st, prop
    return _denies(build, m)


def sec_e21(m):
    return _denies(lambda: harness.build_delete_scenario(stale_approval=True), m)


def sec_e22(m):
    def build():
        st, prop = harness.build_baseline()
        st.current_corpus_version = "corpus_v2"
        return st, prop
    return _denies(build, m)


def sec_e23(m):
    def build():
        st, prop = harness.build_baseline()
        st.manifests.set_current_installed("fs.local", "f" * 64)
        return st, prop
    return _denies(build, m)


def sec_e24(m):
    def build():
        st, prop = harness.build_baseline()
        harness.make_stale_health(st)
        return st, prop
    return _denies(build, m)


def sec_e25(m):
    st, prop = harness.build_baseline()

    def hook(s):
        s.grants["grant_snap_1"].epoch += 1
    d = authorize(pb(prop), st, mutations=m, toctou_hook=hook)
    return d.outcome == "DENY"


def sec_e26(m):
    st, d = _happy_permit(m)
    return len(st.permits._permits) == 1


def sec_e27(m):
    st, d = _happy_permit(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m)
    r2 = ex.execute(d.permit_ref, mutations=m)
    return r2.state_diff == []


def sec_e28(m):
    st, d = _happy_permit(m)
    st.clock.advance(120_000)  # past expiry
    r = MockExecutor(st).execute(d.permit_ref, mutations=m)
    return r.state_diff == []


def sec_e29(m):
    st, d = _happy_permit(m)
    drift = [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/evil.txt",
              "namespace": "projA", "resolution_kind": "existing", "resolution_proof_digest": "a" * 64}]
    r = MockExecutor(st).execute(d.permit_ref, mutations=m, reresolve_targets=drift)
    return r.state_diff == []


def sec_e30(m):
    st, d = _happy_permit(m)
    r = MockExecutor(st).execute(d.permit_ref, mutations=m, extra_effects=[_EXFIL])
    return "fs.exfiltrate" not in {e["effect_class"] for e in r.state_diff}


def sec_e31(m):
    st, _ = harness.build_baseline()
    r = MockExecutor(st).execute(b'{"raw":1}', mutations=m)
    return r.state_diff == []


def sec_e32(m):
    st, d = _happy_permit(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m)
    st.permits.recover_after_crash(d.permit["permit_id"], mutations=m)
    r = ex.execute(d.permit_ref, mutations=m)
    return r.state_diff == []


def sec_e33(m):
    st, d = _happy_permit(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m, preflight_fail=True)
    r = ex.execute(d.permit_ref, mutations=m)
    return r.state_diff == []


def sec_e34(m):
    st, d = _happy_permit(m)
    ex = MockExecutor(st)
    ex.execute(d.permit_ref, mutations=m)
    r = ex.execute(d.permit_ref, mutations=m, followup=True)
    return r.state_diff == []


def sec_e35(m):
    st, contract, cad = _completion(m)
    return evaluate_completion(contract, st, m) != "true"


def sec_e36(m):
    def put(cad):
        return {"predicate_kind": "executor_status", "result_code": "ok", "exit_code": 0,
                "source_id": "exec.fs/1", "source_version": 1, "at_ms": 1_700_000_000_000, "namespace": "projA",
                "subject": {"task_id": "OTHER_task", "canonical_action_digest": "f" * 64}}
    st, contract, cad = _completion(m, put)
    return evaluate_completion(contract, st, m) != "true"


# --------------------------------------------------------------------------- registry
_D_STORE = "MVP uses an in-process atomic MOCK permit store; real Windows IPC/ACL/CAS/crash recovery is Blocker 3 -> i38"
_D_PROFILE = "MVP uses a generic resolver; real Windows reparse-point/ADS/junction/device profile depth is Blocker 4 -> i38"

REGISTRY = [
    ("M-A01", "authority", sec_a01, None), ("M-A02", "authority", sec_a02, None),
    ("M-A03", "authority", sec_a03, None), ("M-A04", "authority", sec_a04, None),
    ("M-A05", "authority", sec_a05, None), ("M-A06", "authority", sec_a06, None),
    ("M-A07", "authority", sec_a07, None), ("M-A08", "authority", sec_a08, None),
    ("M-A09", "authority", sec_a09, None), ("M-A10", "authority", sec_a10, None),
    ("M-S01", "scope", sec_s01, None), ("M-S02", "scope", sec_s02, None),
    ("M-S03", "scope", sec_s03, None), ("M-S04", "scope", sec_s04, None),
    ("M-S05", "scope", sec_s05, None), ("M-S06", "scope", sec_s06, _D_PROFILE),
    ("M-S07", "scope", sec_s07, None), ("M-S08", "scope", sec_s08, None),
    ("M-S09", "scope", sec_s09, None), ("M-S10", "scope", sec_s10, None),
    ("M-R01", "role", sec_r01, None), ("M-R02", "role", sec_r02, None),
    ("M-R03", "role", sec_r03, None), ("M-R04", "role", sec_r04, None),
    ("M-R05", "role", sec_r05, None), ("M-R06", "role", sec_r06, None),
    ("M-R07", "role", sec_r07, None), ("M-R08", "role", sec_r08, None),
    ("M-R09", "role", sec_r09, None), ("M-R10", "role", sec_r10, None),
    ("M-R11", "role", sec_r11, None),  # amendment 6: R-1 router-diagnostic role laundering
    ("M-E01", "effect", sec_e01, None), ("M-E02", "effect", sec_e02, None),
    ("M-E03", "effect", sec_e03, None), ("M-E04", "effect", sec_e04, None),
    ("M-E05", "effect", sec_e05, _D_PROFILE), ("M-E06", "effect", sec_e06, _D_PROFILE),
    ("M-E07", "effect", sec_e07, None), ("M-E08", "effect", sec_e08, None),
    ("M-E09", "effect", sec_e09, None), ("M-E10", "effect", sec_e10, None),
    ("M-E11", "effect", sec_e11, None), ("M-E12", "effect", sec_e12, None),
    ("M-E13", "effect", sec_e13, None), ("M-E14", "effect", sec_e14, None),
    ("M-E15", "effect", sec_e15, None), ("M-E16", "effect", sec_e16, None),
    ("M-E17", "effect", sec_e17, None), ("M-E18", "effect", sec_e18, None),
    ("M-E19", "effect", sec_e19, None), ("M-E20", "effect", sec_e20, None),
    ("M-E21", "effect", sec_e21, None), ("M-E22", "effect", sec_e22, None),
    ("M-E23", "effect", sec_e23, None), ("M-E24", "effect", sec_e24, None),
    ("M-E25", "effect", sec_e25, None), ("M-E26", "effect", sec_e26, _D_STORE),
    ("M-E27", "effect", sec_e27, None), ("M-E28", "effect", sec_e28, _D_STORE),
    ("M-E29", "effect", sec_e29, _D_PROFILE), ("M-E30", "effect", sec_e30, None),
    ("M-E31", "effect", sec_e31, None), ("M-E32", "effect", sec_e32, _D_STORE),
    ("M-E33", "effect", sec_e33, None), ("M-E34", "effect", sec_e34, None),
    ("M-E35", "effect", sec_e35, None), ("M-E36", "effect", sec_e36, None),
]


def run(check):
    """Run the kill harness; record into `check`; return the kill matrix (list of dicts)."""
    matrix = []
    for mid, cat, fn, note in REGISTRY:
        try:
            ref = fn(frozenset())
        except Exception as e:  # noqa: BLE001
            ref = "ERR:%r" % e
        try:
            mut = fn(frozenset([mid]))
        except Exception as e:  # noqa: BLE001
            mut = "ERR:%r" % e
        killed = (ref is True) and (mut is False)
        check.ok("%s killed [%s]" % (mid, cat), killed, "ref=%r mut=%r" % (ref, mut))
        matrix.append({"mutation": mid, "category": cat,
                       "status": "COVERED->killed" if killed else "NOT_KILLED",
                       "depth_staged": note})
    return matrix
