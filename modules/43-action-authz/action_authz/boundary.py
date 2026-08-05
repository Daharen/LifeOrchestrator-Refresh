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

        # ---- D3: verify permit digest, epoch, expiry, nonce, revocation, manifest/artifact drift. ----
        if canon.digest_omitting(permit, "permit_digest") != permit.get("permit_digest"):
            return _reject(st, "D3_digest", mutations)
        if "M-E28" not in mutations:
            if permit.get("permit_store_epoch") != st.permits.epoch:
                return _reject(st, "D3_store_epoch", mutations)
            if st.clock.now_ms() >= permit.get("expiry_unix_ms", 0):
                return _reject(st, "D3_expired", mutations)
        man = st.manifests.lookup(permit["tool_id"], mutations)
        if man is None:
            return _reject(st, "D3_manifest_gone", mutations)
        if "M-E23" not in mutations:
            if st.manifests.current_installed_digest(permit["tool_id"]) != man["installed_artifact_digest"]:
                return _reject(st, "D3_installed_drift", mutations)
        if permit["tool_manifest_digest"] != man["manifest_digest"]:
            return _reject(st, "D3_manifest_drift", mutations)

        # ---- D4: re-resolve dynamic target identity; require an exact match. ----
        if reresolve_targets is not None and "M-E29" not in mutations:
            if canon.canonical_bytes(reresolve_targets) != canon.canonical_bytes(permit["resolved_target_set"]):
                return _reject(st, "D4_target_drift", mutations)

        # ---- M-R06 ONLY: a caller-supplied permit JSON trusted without trusted-store resolution. ----
        if not from_store:
            return ExecResult(True, list(permit["authorized_effect_set"]),
                              consumed_permit_id=permit.get("permit_id"), reason="M-R06_caller_permit")

        # ---- one-shot state handling (reuse / retry / follow-up all fail closed). ----
        state = st.permits.state(permit_id)
        if followup and state == "consumed":
            if "M-E34" in mutations:                       # rollback/follow-up under the original permit
                return ExecResult(True, list(permit["authorized_effect_set"]),
                                  consumed_permit_id=permit_id, reason="M-E34_followup")
            return _reject(st, "D_followup_rejected", mutations)
        if state == "rejected_no_effect" and "M-E33" in mutations:
            st.permits._state[permit_id] = "issued"        # retry a failed op under the same permit

        # ---- D5: atomic claim (issued -> claimed). Reuse after claim/consume/reject fails closed. ----
        if not st.permits.claim(permit_id, mutations):
            return _reject(st, "D5_not_claimable", mutations)

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
