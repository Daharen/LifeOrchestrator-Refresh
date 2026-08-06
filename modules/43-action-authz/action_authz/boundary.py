"""
boundary.py -- the MOCK coordinator (Boundary C) + MOCK executor (Boundary D) + completion evaluation.

Boundary D invariants (contract s6): the executor accepts ONLY a privileged permit REFERENCE that
resolves to an `issued` permit in the trusted store. A raw model tool-call, an action proposal, or a
caller-created permit object NEVER reaches execution. Permit reuse / expiry / nonce / store-epoch /
revocation / manifest-drift / target-drift fail CLOSED. One permit -> exactly one consumed action.
Every denial / rejection -> NO permit + NO state diff.

Completion (s4): deterministic three-valued predicate tree over trusted status ONLY; model / evidence /
tool prose can never satisfy it. `indeterminate` is incomplete.
"""

from . import canon
from .monitor import PermitRef, authorize


class MockCoordinator(object):
    """Boundary C: the only path from a proposal to a permit is the deterministic reference monitor."""

    def __init__(self, stores):
        self.st = stores

    def propose(self, proposal_bytes, side_effect_policy_ref=None, mutations=frozenset(), toctou_hook=None):
        d = authorize(proposal_bytes, self.st, side_effect_policy_ref=side_effect_policy_ref,
                      mutations=mutations, toctou_hook=toctou_hook)
        # the model-facing return is at most a non-authoritative status; the permit ref is privileged.
        return d


class ExecResult(object):
    __slots__ = ("accepted", "state_diff", "consumed_permit_id", "status", "reason")

    def __init__(self, accepted, state_diff, consumed_permit_id=None, status=None, reason=None):
        self.accepted = accepted
        self.state_diff = state_diff        # list of effect atoms actually applied ([] == no state diff)
        self.consumed_permit_id = consumed_permit_id
        self.status = status
        self.reason = reason


def _reject(st, reason, mutations):
    # M-E31: produce a state diff even after a rejection (seeded defect).
    if "M-E31" in mutations:
        return ExecResult(False, [{"effect_class": "fs.write", "target_index": 0, "quantity": 1,
                                   "unit": "bytes", "effect_risk_class": 2, "externality": "local",
                                   "reversibility": "compensatable"}], reason=reason)
    return ExecResult(False, [], reason=reason)


class MockExecutor(object):
    """Boundary D."""

    def __init__(self, stores):
        self.st = stores

    def execute(self, inp, mutations=frozenset(), reresolve_targets=None,
                extra_effects=None, preflight_fail=False, followup=False):
        st = self.st

        # ---- D1: reject everything that is not a privileged, store-authentic permit reference. ----
        if isinstance(inp, PermitRef):
            if inp.store_token != id(st.permits) and "M-R06" not in mutations:
                return _reject(st, "D1_bad_store_token", mutations)
            permit_id = inp.permit_id
        elif isinstance(inp, (bytes, bytearray)):
            if "M-R04" in mutations:                      # route raw model tool-call JSON to executor
                return ExecResult(True, [{"effect_class": "fs.write", "target_index": 0, "quantity": 1,
                                          "unit": "bytes", "effect_risk_class": 2, "externality": "local",
                                          "reversibility": "compensatable"}], reason="M-R04_raw")
            return _reject(st, "D1_raw_rejected", mutations)
        elif isinstance(inp, dict):
            if inp.get("schema") == "lifeorch.action_proposal/0.1":
                if "M-R05" in mutations:                  # executor accepts a proposal as an invocation
                    return ExecResult(True, [{"effect_class": "fs.write", "target_index": 0, "quantity": 1,
                                              "unit": "bytes", "effect_risk_class": 2, "externality": "local",
                                              "reversibility": "compensatable"}], reason="M-R05_proposal")
                return _reject(st, "D1_proposal_rejected", mutations)
            if inp.get("schema") == "lifeorch.action_permit/0.1":
                if "M-R06" in mutations:                  # trust permit-shaped caller JSON, no store resolve
                    return self._run_permit(inp, mutations, reresolve_targets, extra_effects,
                                            preflight_fail, followup, from_store=False, permit_id=inp.get("permit_id"))
                return _reject(st, "D1_permit_shaped_rejected", mutations)
            return _reject(st, "D1_unknown_input", mutations)
        else:
            return _reject(st, "D1_unknown_input", mutations)

        # ---- D2: resolve the immutable permit ONLY from the trusted store. ----
        permit = st.permits.get(permit_id)
        if permit is None:
            return _reject(st, "D2_no_permit", mutations)
        return self._run_permit(permit, mutations, reresolve_targets, extra_effects,
                                preflight_fail, followup, from_store=True, permit_id=permit_id)

    def _run_permit(self, permit, mutations, reresolve_targets, extra_effects,
                    preflight_fail, followup, from_store, permit_id):
        st = self.st

        # === amendment 3 (contract s6 item 3): the executor TOCTOU order is ==================
        #   1. resolve + verify immutable permit structure/digest;
        #   2. ATOMIC claim;
        #   3. re-read all mutable epochs (grant/approval/policy/manifest/artifact/health/revocation);
        #   4. re-resolve dynamic targets AFTER claim;
        #   5. bind execution to the re-resolved stable canonical identities;
        #   6. immediately before the first effect, verify the SAME bound identity;
        #   7. on any failure -> rejected_no_effect (empty diff; permit not retriable).
        # Claiming BEFORE the recheck/re-resolve closes the window in which another executor
        # could substitute the target between the last comparison and the effect.

        # ---- step 1: verify immutable permit digest (+ expiry/epoch unless M-E28). ----
        if canon.digest_omitting(permit, "permit_digest") != permit.get("permit_digest"):
            return _reject(st, "D3_digest", mutations)
        if "M-E28" not in mutations:
            if permit.get("permit_store_epoch") != st.permits.epoch:
                return _reject(st, "D3_store_epoch", mutations)
            if st.clock.now_ms() >= permit.get("expiry_unix_ms", 0):
                return _reject(st, "D3_expired", mutations)

        # ---- M-R06 ONLY: a caller-supplied permit JSON trusted without trusted-store resolution. ----
        if not from_store:
            man = st.manifests.lookup(permit["tool_id"], mutations)
            return ExecResult(True, list(permit["authorized_effect_set"]),
                              consumed_permit_id=permit.get("permit_id"), reason="M-R06_caller_permit")

        # ---- pre-claim one-shot state handling (reuse / retry / follow-up all fail closed). ----
        state = st.permits.state(permit_id)
        if followup and state == "consumed":
            if "M-E34" in mutations:                       # rollback/follow-up under the original permit
                return ExecResult(True, list(permit["authorized_effect_set"]),
                                  consumed_permit_id=permit_id, reason="M-E34_followup")
            return _reject(st, "D_followup_rejected", mutations)
        if state == "rejected_no_effect" and "M-E33" in mutations:
            st.permits._state[permit_id] = "issued"        # retry a failed op under the same permit

        # ---- step 2: ATOMIC claim (issued -> claimed) BEFORE any recheck/re-resolve. ----
        if not st.permits.claim(permit_id, mutations):
            return _reject(st, "D5_not_claimable", mutations)

        # ---- step 3: re-read mutable epochs AFTER claim (manifest/artifact drift, revocation). ----
        man = st.manifests.lookup(permit["tool_id"], mutations)
        if man is None:
            st.permits.reject_no_effect(permit_id)
            return _reject(st, "D3_manifest_gone", mutations)
        if "M-E23" not in mutations:
            if st.manifests.current_installed_digest(permit["tool_id"]) != man["installed_artifact_digest"]:
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_installed_drift", mutations)
        if permit["tool_manifest_digest"] != man["manifest_digest"]:
            st.permits.reject_no_effect(permit_id)
            return _reject(st, "D3_manifest_drift", mutations)

        # ---- amendment 3 (red-team Finding 5): re-read ALL mutable epochs AFTER the claim. --------
        # Not just manifest/artifact -- also grant (epoch/current/revocation), side-effect policy
        # (epoch/current), approval (revocation/expiry), tool health, permit-store epoch, and
        # packet/status currentness. Any post-claim drift -> rejected_no_effect: a TERMINAL permit +
        # an EMPTY independent effect ledger. This is the ABSTRACT epoch model the logical gate owns;
        # real Windows stable-handle/reparse/crash race-freedom stays ACTIVATION-gating (recorded).
        snap = st.permits.issue_snapshot(permit_id)
        if snap is not None:
            gsx = st.grant(permit.get("grant_snapshot_ref"))
            if (gsx is None or gsx.epoch != snap.get("grant_epoch") or (not gsx.current)
                    or (set(gsx.revoked) & set(permit.get("matched_grant_ids", [])))):
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_grant_epoch", mutations)
            polx = st.policy(permit.get("side_effect_policy_ref"))
            if polx is None or polx.epoch != snap.get("policy_epoch") or (not polx.current):
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_policy_epoch", mutations)
            if permit.get("approval_ref") is not None:
                appr = st.approvals._by_ref.get(permit["approval_ref"])
                if (appr is None or appr.get("revoked") or appr.get("state") != "approved"
                        or st.clock.now_ms() >= appr.get("expiry_unix_ms", 1 << 62)):
                    st.permits.reject_no_effect(permit_id)
                    return _reject(st, "D3_approval_epoch", mutations)
            hnow = st.health.current(man["health_source"]["source_id"])
            if snap.get("health") is not None and hnow != snap.get("health"):
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_health_epoch", mutations)
            if st.permits.epoch != snap.get("store_epoch"):
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_store_epoch2", mutations)
            pvx = st.packets.verify_and_get(permit.get("packet_id"))
            if (pvx is None or (not pvx.current)
                    or pvx.non_execution != snap.get("packet_non_execution")):
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D3_packet_epoch", mutations)

        # ---- steps 4-6: re-resolve dynamic targets AFTER claim; bind + verify SAME identity. ----
        # The permit's resolved_target_set entries each carry an unforgeable `resolution_proof_digest`
        # captured at resolution -- the executor CONSUMES that captured stable handle and NEVER
        # re-resolves the caller name. `reresolve_targets` models what a fresh resolution would yield;
        # any divergence from the captured handle -> rejected_no_effect (TOCTOU substitution).
        bound_targets = permit["resolved_target_set"]
        if reresolve_targets is not None and "M-E29" not in mutations:
            if canon.canonical_bytes(reresolve_targets) != canon.canonical_bytes(permit["resolved_target_set"]):
                st.permits.reject_no_effect(permit_id)     # TOCTOU substitution -> rejected_no_effect
                return _reject(st, "D4_target_drift", mutations)
            bound_targets = reresolve_targets

        # ---- preflight failure => rejected_no_effect, NO state diff (permit not retriable). ----
        if preflight_fail:
            st.permits.reject_no_effect(permit_id)
            return _reject(st, "preflight_failed", mutations)

        # ---- D7: forbid any undeclared / over-limit effect. ----
        actual = list(permit["authorized_effect_set"])
        if extra_effects is not None:
            if "M-E30" in mutations:
                actual = actual + list(extra_effects)      # permit an undeclared/over-limit effect
            else:
                st.permits.reject_no_effect(permit_id)
                return _reject(st, "D7_undeclared_effect", mutations)
        # limit check
        for e in actual:
            for lim in permit["limits"]:
                if lim.get("limit_id") == e["effect_class"] and e["quantity"] > lim.get("max_value", 1 << 62):
                    if "M-E30" not in mutations:
                        st.permits.reject_no_effect(permit_id)
                        return _reject(st, "D7_over_limit", mutations)

        # ---- consume (claimed -> consumed) atomically with effect_started. ----
        st.permits.consume(permit_id)
        status = {"predicate_kind": "executor_status", "result_code": "ok", "exit_code": 0,
                  "subject": {"canonical_action_digest": permit["canonical_action_digest"],
                              "task_id": permit["task_id"]}}
        return ExecResult(True, actual, consumed_permit_id=permit_id, status=status)


# ---------------------------------------------------------------------------
# Completion evaluation (s4): three-valued over trusted status ONLY.

def _matches_expected(kind, rec, expected):
    if kind == "executor_status":
        return rec.get("result_code") in expected.get("allowed_result_codes", [])
    if kind == "human_approval":
        return rec.get("state") == expected.get("required_state")
    if kind == "test_suite":
        return (rec.get("passed", 0) >= expected.get("minimum_passed", 0) and
                rec.get("failed", 1 << 62) <= expected.get("maximum_failed", 0))
    if kind == "artifact_hash":
        return rec.get("hash") == expected.get("expected_hash")
    return False


def _leaf_value(leaf, st, mutations, effective_namespace, evidence_claims):
    pk = leaf["predicate"]
    kind = pk["predicate_kind"]
    subject = dict(pk.get("subject_binding", {}))
    rec = st.status.find(kind, pk["source_id"], pk["source_version"], subject, st.clock.now_ms(),
                         pk["max_age_ms"], effective_namespace, mutations)
    if rec is None:
        if "M-E35" in mutations:
            return True                                    # missing/stale status as success
        if "M-R08" in mutations and evidence_claims.get(pk["predicate_id"]) == "success":
            return True                                    # untrusted tool text as a completion actual
        if "M-A04" in mutations and evidence_claims.get(pk["predicate_id"]) == "success":
            return True                                    # tool stdout as trusted completion status
        return None                                        # indeterminate
    return _matches_expected(kind, rec, pk.get("expected", {}))


def _eval_expr(node, st, mutations, ns, evidence_claims):
    kind = node["kind"]
    if kind == "leaf":
        return _leaf_value(node, st, mutations, ns, evidence_claims)
    vals = [_eval_expr(c, st, mutations, ns, evidence_claims) for c in node["children"]]
    if kind == "all":
        if any(v is False for v in vals):
            return False
        if all(v is True for v in vals):
            return True
        return None
    if kind == "any":
        if any(v is True for v in vals):
            return True
        if all(v is False for v in vals):
            return False
        return None
    if kind == "at_least":
        k = node["threshold"]
        t = sum(1 for v in vals if v is True)
        ind = sum(1 for v in vals if v is None)
        if t >= k:
            return True
        if t + ind < k:
            return False
        return None
    return None


def evaluate_completion(contract, st, mutations=frozenset(), evidence_claims=None):
    """Return 'true' | 'false' | 'indeterminate'. A task is complete only when the root is exactly true."""
    evidence_claims = evidence_claims or {}
    if "M-R07" in mutations and evidence_claims.get("task") == "complete":
        return "true"                                      # model/evidence prose satisfies completion
    v = _eval_expr(contract["root"], st, mutations, contract["effective_namespace"], evidence_claims)
    return {True: "true", False: "false", None: "indeterminate"}[v]


# ---------------------------------------------------------------------------
# amendment 4 (red-team Finding 4): completion is bound through the authentic IMMUTABLE `packet_id`,
# NOT a current-contract-by-task lookup, and every leaf is scoped to the EXACT permit.
#
# The per-leaf-kind MINIMUM binding scope (frozen, byte-exact in SCHEMA_NOTES). A leaf whose declared
# `completion_scope` is weaker than its kind's minimum makes the whole contract indeterminate --
# closing the "executor_status bound to task" hole. `permit` implies the exact canonical action.
MIN_COMPLETION_SCOPE = {
    "executor_status": frozenset(("permit",)),
    "state_diff":      frozenset(("permit",)),
    "artifact_hash":   frozenset(("object", "action", "permit")),
    "test_suite":      frozenset(("action", "object")),
    "object_state":    frozenset(("object",)),
    "human_approval":  frozenset(("approval",)),
    "postcondition":   frozenset(("action", "permit")),
}


def _rc_completion_launder(mutations, evidence_claims, sink):
    """R1-ROLE-1 completion sinks: a diagnostic/working carrier laundered into TrustedStatus /
    completion. The carrier's presence is signalled by evidence_claims["__carrier_<c>__"]; the
    reference (no M-RC-* id) never honours it."""
    for carrier, tag in (("routing", "RT"), ("working", "WM")):
        if ("M-RC-%s-%s" % (tag, sink.upper())) in mutations and evidence_claims.get("__carrier_%s__" % carrier):
            return True
    return False


def _permit_subject(permit, scope, leaf):
    """The subject a completion leaf must bind, DERIVED FROM THE PERMIT (not the contract), so status
    from another action/permit/object cannot satisfy it. Returns None if the scope's binding is
    unavailable on this permit (e.g. an approval leaf on a permit with no approval_ref)."""
    if scope == "task":
        return {"task_id": permit["task_id"]}
    if scope == "action":
        return {"task_id": permit["task_id"], "canonical_action_digest": permit["canonical_action_digest"]}
    if scope == "permit":
        return {"task_id": permit["task_id"], "canonical_action_digest": permit["canonical_action_digest"],
                "permit_id": permit["permit_id"]}
    if scope == "object":
        oid = (leaf.get("predicate", {}).get("subject_binding", {}) or {}).get("object_id")
        tids = {t["canonical_target_id"] for t in permit.get("resolved_target_set", [])}
        if oid is None or oid not in tids:      # the object must be one THIS permit actually authorized
            return None
        return {"object_id": oid}
    if scope == "approval":
        ar = permit.get("approval_ref")
        return None if ar is None else {"approval_ref": ar}
    return None


def _leaf_value_bound(leaf, st, mutations, ns, evidence_claims, permit):
    pk = leaf["predicate"]
    kind = pk["predicate_kind"]
    scope = leaf.get("completion_scope")
    allowed = MIN_COMPLETION_SCOPE.get(kind)
    if "M-E36" not in mutations:
        if allowed is None or scope not in allowed:
            return None                                     # scope weaker than the per-kind minimum
        subject = _permit_subject(permit, scope, leaf)
        if subject is None:
            return None                                     # required binding absent on this permit
    else:
        # seeded defect: ignore completion_scope AND bind by the CONTRACT's own (attacker-influenced)
        # subject_binding by TASK -- the substitution hole the amendment closes.
        subject = dict(pk.get("subject_binding", {}))
    rec = st.status.find(kind, pk["source_id"], pk["source_version"], subject, st.clock.now_ms(),
                         pk["max_age_ms"], ns, mutations)
    if rec is None:
        if "M-E35" in mutations:
            return True
        if "M-R08" in mutations and evidence_claims.get(pk["predicate_id"]) == "success":
            return True
        if "M-A04" in mutations and evidence_claims.get(pk["predicate_id"]) == "success":
            return True
        if _rc_completion_launder(mutations, evidence_claims, "trusted_status"):
            return True                                     # carrier laundered into TrustedStatus
        return None
    return _matches_expected(kind, rec, pk.get("expected", {}))


def _eval_expr_bound(node, st, mutations, ns, evidence_claims, permit):
    kind = node["kind"]
    if kind == "leaf":
        return _leaf_value_bound(node, st, mutations, ns, evidence_claims, permit)
    vals = [_eval_expr_bound(c, st, mutations, ns, evidence_claims, permit) for c in node["children"]]
    if kind == "all":
        if any(v is False for v in vals):
            return False
        if all(v is True for v in vals):
            return True
        return None
    if kind == "any":
        if any(v is True for v in vals):
            return True
        if all(v is False for v in vals):
            return False
        return None
    if kind == "at_least":
        k = node["threshold"]
        t = sum(1 for v in vals if v is True)
        ind = sum(1 for v in vals if v is None)
        if t >= k:
            return True
        if t + ind < k:
            return False
        return None
    return None


def evaluate_completion_via_permit(st, permit, mutations=frozenset(), evidence_claims=None):
    """Evaluate completion for a PERMIT by resolving the completion contract through the authentic
    IMMUTABLE packet_id (never a current-contract-by-task lookup) and scoping every leaf to the exact
    permit. Returns 'true' | 'false' | 'indeterminate' ('indeterminate' is incomplete). Any
    substitution (cross-action/permit/object, old-contract-vs-new-packet, tampered/omitted binding,
    wrong validator version, superseded status) resolves to indeterminate."""
    evidence_claims = evidence_claims or {}
    if "M-R07" in mutations and evidence_claims.get("task") == "complete":
        return "true"                                       # model/evidence prose satisfies completion
    if _rc_completion_launder(mutations, evidence_claims, "completion"):
        return "true"                                       # carrier laundered into completion
    cc = st.completion_contract_for_packet(permit["packet_id"], mutations)
    if cc is None:
        return "indeterminate"
    if canon.digest_omitting(cc, "contract_digest") != cc.get("contract_digest"):
        return "indeterminate"                              # tampered / mismatching content
    if "M-E36" not in mutations:
        if cc.get("packet_id") is not None and cc.get("packet_id") != permit["packet_id"]:
            return "indeterminate"                          # old-contract-vs-new-packet
        if cc.get("task_id") != permit.get("task_id"):
            return "indeterminate"
        b = st.permits.completion_binding(permit["permit_id"])
        if b is not None and (b.get("completion_contract_id") != cc.get("completion_contract_id")
                              or b.get("contract_version") != cc.get("contract_version")
                              or b.get("contract_digest") != cc.get("contract_digest")):
            return "indeterminate"                          # not the contract bound at issue time
    v = _eval_expr_bound(cc["root"], st, mutations, cc["effective_namespace"], evidence_claims, permit)
    return {True: "true", False: "false", None: "indeterminate"}[v]
