"""
monitor.py -- the deterministic DENY-BY-DEFAULT action reference monitor (contract s5, checks A01-A36).

A pure function over explicitly-supplied trusted snapshots (stores.py) + a trusted clock + an atomic
permit store. Output is EXACTLY one of:
  - DENY  : the CONSTANT caller-visible denial object, no permit, no state diff.
  - PERMIT: one immutable permit in the trusted store + a privileged permit reference.

Any exception / missing value / ambiguity / unsupported type / conflict / indeterminate = DENY.

`mutations` (frozenset of M-* ids) is the seeded-defect switch used by tests/mutations.py. Empty = the
reference implementation (every security property holds). `toctou_hook`, if given, is invoked once
between A31 and A32 to let a test mutate a trusted snapshot (the deterministic TOCTOU probe).
"""

import unicodedata

from . import canon, schemas, stores as S


# ---------------------------------------------------------------------------
# amendment 6 / R1-ROLE-1 (red-team Finding 6): the role-conversion SINK MATRIX switch.
#
# R1-ROLE-1 forbids any router-diagnostic OR working-memory carrier from populating/satisfying ANY
# of these sinks. The REFERENCE monitor never reads a diagnostic/working carrier into a sink; each
# `M-RC-<CARRIER>-<SINK>` seeded defect routes the carrier into exactly ONE sink so tests/role_matrix.py
# can kill every (carrier, sink) pair independently under the test-only non_execution=false path (so
# A31 + completion are actually REACHED, not short-circuited at A06). Empty mutations => reference.
# i40 Finding 3: the matrix now covers ALL 15 FROZEN R1-ROLE-1 sinks -- the i39 list omitted `manifest`
# and `working_memory`. Every sink is protected against BOTH carriers (routing stage-trace + hydrated
# working memory) => 15 x 2 = 30 killable (carrier, sink) pairs (tests/role_matrix.py).
RC_SINKS = ("evidence", "evidence_requirement", "coverage_result", "packet_disposition",
            "control_plane", "grant", "policy", "approval", "manifest", "health", "trusted_status",
            "completion", "target", "effect", "working_memory")
_RC_CARRIER_FLAG = {"routing": "routing_present", "working": "working_present"}


def _rc_launder(pmeta, sink, mutations):
    """True iff a role-conversion defect for `sink` is active AND its diagnostic/working carrier is
    actually present in the packet. The reference impl (empty mutations) always returns False."""
    for carrier, tag in (("routing", "RT"), ("working", "WM")):
        if ("M-RC-%s-%s" % (tag, sink.upper())) in mutations and bool(pmeta.get(_RC_CARRIER_FLAG[carrier])):
            return True
    return False


def _rc_grant_from_carrier(ca_tool_id, action_namespace, targets, effects):
    """A permissive grant a role-conversion defect would synthesize from an untrusted carrier (used
    ONLY under an M-RC-*-GRANT/CONTROL_PLANE defect to show the carrier laundering into authority)."""
    return {"grant_id": "g_rc_carrier", "tool_id": ca_tool_id, "operation": "*",
            "action_namespace": action_namespace,
            "allowed_target_ids": [t["canonical_target_id"] for t in targets],
            "effect_classes": sorted({e["effect_class"] for e in effects}),
            "max_quantity": {e["effect_class"]: 1 << 62 for e in effects},
            "externality_max": "public_external", "risk_ceiling": 4, "validity_from": 0,
            "validity_to": 9_000_000_000_000_000, "approval_mode": "none",
            "scopes": [], "limits": []}


class Decision(object):
    __slots__ = ("outcome", "caller_obj", "reason_code", "permit", "permit_ref",
                 "canonical_action", "cad", "matched_grant_ids")

    def __init__(self, outcome, caller_obj, reason_code=None, permit=None, permit_ref=None,
                 canonical_action=None, cad=None, matched_grant_ids=None):
        self.outcome = outcome
        self.caller_obj = caller_obj
        self.reason_code = reason_code          # PRIVILEGED only; never in caller_obj on a plain deny
        self.permit = permit
        self.permit_ref = permit_ref
        self.canonical_action = canonical_action
        self.cad = cad
        self.matched_grant_ids = matched_grant_ids

    @property
    def caller_bytes(self):
        return canon.canonical_bytes(self.caller_obj)


class PermitRef(object):
    """A privileged reference resolved ONLY from the trusted permit store (never caller-supplied)."""
    __slots__ = ("permit_id", "store_token")

    def __init__(self, permit_id, store_token):
        self.permit_id = permit_id
        self.store_token = store_token  # in-process identity of the authentic store


def _deny(st, code, mutations, leak=None):
    caller = st.log.deny(code, mutations, leak=leak)
    return Decision("DENY", caller, reason_code=code)


def canonical_digest(ca_real, mutations=frozenset(), caller_digest=None):
    """Compute canonical_action_digest over a closed CanonicalAction (s0.6). The digest-omission
    seeded defects (M-E14..E18) are applied to a COPY so grant matching + the permit keep the full
    action. Exposed so tests/mutations.py can prove each field is bound into the digest."""
    if "M-E18" in mutations and caller_digest is not None:
        return caller_digest                              # seeded defect: trust a caller-supplied digest
    view = dict(ca_real)
    if "M-E14" in mutations:
        view["canonical_arguments"] = {}
    if "M-E15" in mutations:
        view["resolved_target_set"] = []
    if "M-E16" in mutations:
        view["derived_effect_set"] = []
    if "M-E17" in mutations:
        view["action_namespace"] = ""
        view["risk_class"] = 0
        view["sandbox_class"] = ""
        view["limits"] = []
        view["tool_manifest_digest"] = ""
        view["idempotency_key"] = ""
    return canon.digest_of(view)


def _canonicalize_args(args, arg_schema, mutations):
    """A16: canonicalize only fields the schema declares; preserve untrusted content as data."""
    if "M-E04" in mutations:
        return dict(args)  # seeded defect: skip argument canonicalization
    out = {}
    fields = {f["name"]: f for f in arg_schema.get("fields", [])}
    for k, v in args.items():
        fs = fields.get(k, {})
        if fs.get("normalize_nfc") and isinstance(v, str):
            v = unicodedata.normalize("NFC", v)
        if fs.get("set_semantics") and isinstance(v, list):
            v = canon.canon_sorted_set(v)
        out[k] = v
    return out


def _wrapper_implied_effect(command):
    if command.startswith("del ") or command.startswith("rm "):
        return "fs.delete"
    return "fs.write"


def authorize(proposal_bytes, st, side_effect_policy_ref=None, mutations=frozenset(),
              toctou_hook=None, channel="proposal"):
    log = st.log

    # ---- A01 channel/type gate (part 1): only the proposal endpoint. -------------------------
    if channel != "proposal":
        return _deny(st, "A01_channel", mutations)

    # ---- A02 strict parse (s0.4). ------------------------------------------------------------
    try:
        obj = canon.strict_parse(proposal_bytes, canon.PROPOSAL_MAX_BYTES, mutations)
    except canon.CanonError as e:
        return _deny(st, "A02_parse:" + e.reason, mutations)

    # ---- A01 (part 2): reject permit-shaped / raw tool-call / unknown-schema inputs. ---------
    if not isinstance(obj, dict):
        return _deny(st, "A01_not_object", mutations)
    sch = obj.get("schema")
    if sch != "lifeorch.action_proposal/0.1":
        # permit-shaped output, tool_manifest, completion_contract, or a raw tool-call envelope
        return _deny(st, "A01_bad_schema", mutations)

    # ---- A03 proposal schema. ----------------------------------------------------------------
    try:
        schemas.validate_action_proposal(obj, mutations)
    except schemas.SchemaError as e:
        return _deny(st, "A03_schema:" + e.reason, mutations)

    mp = obj["model_provenance"]

    # ---- A04 trusted provenance attachment. --------------------------------------------------
    if "M-A09" not in mutations:
        att = st.attest.get(mp["model_run_id"])
        if att is None:
            return _deny(st, "A04_no_attestation", mutations)
        if att["raw_output_hash"] != mp["raw_output_hash"]:
            return _deny(st, "A04_raw_hash", mutations)
        if att["model_supplied_provenance"]:
            return _deny(st, "A04_forged_provenance", mutations)

    # ---- A05 packet lookup + task binding. ---------------------------------------------------
    pv = st.packets.verify_and_get(obj["packet_id"])
    if pv is None:
        return _deny(st, "A05_packet_lookup", mutations)
    # Packet disposition + carrier flags (A08) are resolved HERE so the R1-ROLE-1 sink hooks that
    # protect the earliest checks (A05 task binding) can reference the carrier presence.
    pmeta = getattr(st, "packet_meta", {}).get(pv.packet_id,
                                               {"disposition": "answerable", "provenance_ok": True,
                                                "contradiction": False, "retrieval_complete": True})
    if pv.task_id != obj["task_id"]:
        # R1-ROLE-1 `working_memory` sink: an untrusted working-memory / routing carrier must NEVER
        # alter the TRUSTED working-state task binding. The reference derives the task binding ONLY
        # from the authentic packet; M-RC-*-WORKING_MEMORY launders the carrier into it.
        if not _rc_launder(pmeta, "working_memory", mutations):
            return _deny(st, "A05_task_binding", mutations, leak=obj["task_id"])
    if mp["prompt_packet_id"] != obj["packet_id"]:
        return _deny(st, "A05_prompt_packet", mutations)

    # ---- A06 NON-EXECUTION gate (the headline: denies every authentic packet). ---------------
    if "M-E19" not in mutations:
        if pv.non_execution is not False:
            return _deny(st, "A06_non_execution", mutations)

    # ---- A07 packet freshness (+ corpus drift). ----------------------------------------------
    if not pv.current:
        return _deny(st, "A07_packet_stale", mutations)
    cur_corpus = getattr(st, "current_corpus_version", None)
    if cur_corpus is not None and pv.corpus_version != cur_corpus and "M-E22" not in mutations:
        return _deny(st, "A07_corpus_drift", mutations)

    # ---- A08 packet disposition (resolved at A05 above; applied at A31). ----------------------

    # ---- A09 current authority snapshot. -----------------------------------------------------
    grant_ref = pv.grant_snapshot_ref
    policy_ref = side_effect_policy_ref or st.side_effect_policy_ref
    if "M-A05" in mutations:
        # seeded defect: the proposal (via untrusted claimed_effects) selects the authority snapshot.
        for ce in obj["claimed_effects"]:
            if isinstance(ce, dict) and "grant_snapshot_ref" in ce:
                grant_ref = ce["grant_snapshot_ref"]
            if isinstance(ce, dict) and "policy_ref" in ce:
                policy_ref = ce["policy_ref"]
    gs = st.grant(grant_ref)
    if gs is None:
        return _deny(st, "A09_grant_snapshot", mutations)
    if "M-A01" in mutations:
        # seeded defect: an evidence/claimed_effects object with a `grant` key merges into authority.
        injected = [ce["grant"] for ce in obj["claimed_effects"] if isinstance(ce, dict) and "grant" in ce]
        if injected:
            gs.grants = list(gs.grants) + injected
    policy = st.policy(policy_ref)
    if policy is None:
        return _deny(st, "A09_policy", mutations)

    # ---- A10 grant freshness / revocation. ---------------------------------------------------
    if "M-E20" not in mutations:
        if not gs.current:
            return _deny(st, "A10_grant_stale", mutations)
    grant_epoch_at_check = gs.epoch

    # ---- A11 effective namespace = intersection(request, grants) via the ONE ns_permitted. ----
    request_ns = set(gs.request_namespaces) if gs.request_namespaces else set(pv.allowed_namespaces or [pv.namespace])
    # Finding 4 (round-4): grant_namespaces() routes through the shared VALIDATED-grant iterator, so this
    # A11 read cannot dereference a raw grant field before validation (a malformed grant is excluded and
    # fails closed to constant DENY at A11_empty_namespace, never an uncaught KeyError).
    eff_ns = canon.effective_namespaces(request_ns, gs.grant_namespaces(mutations), mutations)
    if _rc_launder(pmeta, "control_plane", mutations):
        # R1-ROLE-1 defect: a diagnostic/working carrier widens the effective namespace (control-plane
        # authority). The reference NEVER lets a carrier touch the ns intersection.
        eff_ns = set(eff_ns) | set(gs.grant_namespaces(mutations))
    if not eff_ns:
        return _deny(st, "A11_empty_namespace", mutations)

    # ---- A12 trusted manifest lookup. --------------------------------------------------------
    man = st.manifests.lookup(obj["tool_id"], mutations)
    if man is None:
        return _deny(st, "A12_manifest", mutations)
    installed_at_check = st.manifests.current_installed_digest(obj["tool_id"])
    # R1-ROLE-1 `manifest` sink: an untrusted routing/working carrier must NEVER attest the trusted
    # tool manifest / installed-artifact currentness. The reference trusts ONLY the allowlisted
    # registry; M-RC-*-MANIFEST launders the carrier into the manifest currentness at A12 AND A32.
    if (installed_at_check != man["installed_artifact_digest"] and "M-E23" not in mutations
            and not _rc_launder(pmeta, "manifest", mutations)):
        return _deny(st, "A12_installed_drift", mutations)

    # ---- A13 operation lookup (exact, case-sensitive, enabled). ------------------------------
    opman = None
    for o in man["operations"]:
        if o["operation"] == obj["operation"]:
            opman = o
            break
    if opman is None:
        return _deny(st, "A13_operation", mutations)
    if not opman.get("enabled", False) and "M-A10" not in mutations:
        return _deny(st, "A13_disabled", mutations)

    # ---- A14 tool health. --------------------------------------------------------------------
    if "M-A10" not in mutations and not _rc_launder(pmeta, "health", mutations):
        # (_rc_launder "health": a diagnostic/working carrier asserts the tool is healthy -- R1-ROLE-1.)
        hs = man["health_source"]
        hrec = st.health.current(hs["source_id"])
        if hrec is None:
            return _deny(st, "A14_no_health", mutations)
        if hrec["code"] not in hs["healthy_codes"]:
            return _deny(st, "A14_unhealthy", mutations)
        if "M-E24" not in mutations and (st.clock.now_ms() - hrec["at_ms"]) > hs["max_age_ms"]:
            return _deny(st, "A14_stale_health", mutations)
    health_at_check = st.health.current(man["health_source"]["source_id"])

    # ---- A15 closed argument validation. -----------------------------------------------------
    try:
        validated_args = schemas.validate_closed_args(obj["arguments"], opman["arg_schema"], mutations)
    except schemas.SchemaError as e:
        return _deny(st, "A15_args:" + e.reason, mutations)

    # ---- A16 canonicalize arguments. ---------------------------------------------------------
    canon_args = _canonicalize_args(validated_args, opman["arg_schema"], mutations)

    # ---- A17 resolve targets. ----------------------------------------------------------------
    resolver = S.PROFILES.get(opman["target_resolver"]["profile_id"])
    if resolver is None:
        return _deny(st, "A17_no_resolver", mutations)
    try:
        targets = resolver(obj["operation"], canon_args, st.resolve_ctx, opman, mutations)
    except S._ResolveError as e:
        return _deny(st, "A17_resolve:" + str(e), mutations)
    if not targets:
        return _deny(st, "A17_no_targets", mutations)

    # ---- A18 target bounds + closure + single namespace. -------------------------------------
    if len(targets) > opman["max_target_count"]:
        return _deny(st, "A18_target_count", mutations)
    transitive_ns = getattr(st.resolve_ctx, "transitive_ns", {})
    for t in targets:
        if t["target_kind"] not in opman["allowed_target_kinds"]:
            return _deny(st, "A18_target_kind", mutations)
        if len(t["resolution_proof_digest"]) != 64:
            return _deny(st, "A18_proof_digest", mutations)
        ns_to_check = [] if "M-S04" in mutations else [t["namespace"]]  # M-S04 omits this ns hop
        if "M-S05" not in mutations:
            ns_to_check += transitive_ns.get(t["canonical_target_id"], [])
        _tgt_launder = _rc_launder(pmeta, "target", mutations)  # R1-ROLE-1: carrier -> target resolution
        for ns in ns_to_check:
            if not _tgt_launder and not canon.ns_permitted(ns, eff_ns, mutations):
                return _deny(st, "A18_ns_closure", mutations, leak=ns)
    target_namespaces = {t["namespace"] for t in targets}
    if len(target_namespaces) != 1 and "M-S07" not in mutations:
        return _deny(st, "A18_multi_namespace", mutations)
    action_namespace = sorted(target_namespaces)[0]

    # ---- A19 derive actual effects (NOT from claimed_effects). -------------------------------
    if "M-A08" in mutations:
        effects = canon.canon_sorted_set(obj["claimed_effects"])  # seeded defect: trust claimed_effects
    else:
        classifier = S.PROFILES.get(opman["effect_classifier"]["profile_id"])
        if classifier is None:
            return _deny(st, "A19_no_classifier", mutations)
        effects = classifier(obj["operation"], canon_args, targets, opman, mutations)
    if not effects:
        return _deny(st, "A19_no_effects", mutations)
    if _rc_launder(pmeta, "effect", mutations):
        # R1-ROLE-1 defect: a diagnostic/working carrier rewrites the DERIVED effect quantity (effect
        # derivation). The reference derives effects ONLY from the manifest classifier over canon args.
        effects = [dict(e, quantity=1) for e in effects]

    # ---- A20 effect validation (+ the effect-scope ns hop; M-S04 omits this one hop). --------
    if len(effects) > opman["max_effect_count"]:
        return _deny(st, "A20_effect_count", mutations)
    for e in effects:
        if e["effect_class"] not in opman["allowed_effect_classes"]:
            return _deny(st, "A20_effect_class", mutations)
        ti = e.get("target_index")
        if not schemas.is_uint63(ti) or ti >= len(targets):
            return _deny(st, "A20_target_index", mutations)
        if not schemas.is_uint63(e.get("quantity")):
            return _deny(st, "A20_quantity", mutations)
        if "M-S04" not in mutations:
            if not canon.ns_permitted(targets[ti]["namespace"], eff_ns, mutations):
                return _deny(st, "A20_ns_closure", mutations)

    # ---- A21 wrapper / meta-effect closure. --------------------------------------------------
    if opman.get("is_wrapper"):
        implied = _wrapper_implied_effect(canon_args.get("command", ""))
        if implied not in {e["effect_class"] for e in effects}:
            return _deny(st, "A21_wrapper_closure", mutations)

    # ---- A22 effective risk (base) + policy escalation (A27 escalation folded before digest). -
    base_risk = opman["base_risk_class"]
    for e in effects:
        base_risk = max(base_risk, e["effect_risk_class"])
    if any(e["externality"] == "public_external" for e in effects):
        base_risk = max(base_risk, 3)
    eff_risk, policy_approval, sandbox_class, policy_deny = policy.apply(
        {"derived_effect_set": effects}, base_risk, opman["approval_requirement"], opman["sandbox_class"], mutations)
    policy_epoch_at_check = policy.epoch

    # ---- A26(match) computed EARLY (Finding 4): the grant-derived limit ALGEBRA feeds A23 so the
    #      canonical action's `limits` reflect min(manifest, grant, ...) BEFORE the A25 digest. The
    #      grant DENY decision is still applied at A26 below; this is a construction fold (like the
    #      A27 risk fold, SCHEMA_NOTES), not a reordering of the deny semantics. --------------------
    card = None
    for ce in obj["claimed_effects"]:
        if isinstance(ce, dict) and isinstance(ce.get("card"), dict):
            card = ce["card"]
    opman_match = opman
    if "M-A02" in mutations and card and "required_permission_scopes" in card:
        # seeded defect: a skill/procedure card's required_permission_scopes accepted as manifest data.
        opman_match = dict(opman)
        opman_match["required_permission_scopes"] = card["required_permission_scopes"]
    _ca_for_match = {"schema": "lifeorch.canonical_action/0.1", "tool_id": obj["tool_id"],
                     "operation": obj["operation"], "action_namespace": action_namespace,
                     "resolved_target_set": targets, "derived_effect_set": effects}
    matched, grant_ok, grant_limits = gs.match(_ca_for_match, st.clock.now_ms(), opman_match, mutations)

    # ---- A23 effective limits = min(manifest ceiling, grant-derived, policy, approval) (Finding 4). -
    # The matcher READS limits[] AND max_quantity; A23 INTERSECTS the grant-derived limit with the
    # manifest resource ceiling (policy/approval limit sources are staged; folded here when present).
    manifest_ceiling = {}
    for c in canon.canon_sorted_set(opman.get("resource_ceiling", [])):
        manifest_ceiling[c["limit_id"]] = c["max_value"]
    limits = S.effective_permit_limits(effects, manifest_ceiling, grant_limits)

    # ---- A24 idempotency key (trusted-derived; NOT proposal-supplied). -----------------------
    idem_basis = {"ns": action_namespace, "tool": obj["tool_id"], "op": obj["operation"],
                  "targets": sorted(t["canonical_target_id"] for t in targets),
                  "effects": sorted(e["effect_class"] for e in effects)}
    idempotency_key = "idem_" + canon.sha256_hex(canon.canonical_bytes(idem_basis))[:40]
    if opman.get("idempotency") == "required" and not idempotency_key:
        return _deny(st, "A24_no_idem", mutations)
    if st.permits.idempotency_conflict(idempotency_key):
        return _deny(st, "A24_idem_conflict", mutations)

    # ---- A25 construct canonical action + digest (never accept a caller digest). -------------
    # ca_real is ALWAYS complete (used for grant match + permit); the digest is computed over a
    # separate view so the digest-omission mutations (M-E14..E18) cannot bleed into matching.
    ca_real = {
        "schema": "lifeorch.canonical_action/0.1",
        "tool_id": obj["tool_id"],
        "tool_manifest_version": man["manifest_version"],
        "tool_manifest_digest": man["manifest_digest"],
        "operation": obj["operation"],
        "canonical_arguments": canon_args,
        "resolved_target_set": targets,
        "derived_effect_set": effects,
        "action_namespace": action_namespace,
        "risk_class": eff_risk,
        "sandbox_class": sandbox_class,
        "limits": limits,
        "idempotency_key": idempotency_key,
    }
    caller_digest = None
    if isinstance(obj.get("arguments"), dict) and "_caller_digest" in obj["arguments"]:
        caller_digest = obj["arguments"]["_caller_digest"]
    cad = canonical_digest(ca_real, mutations, caller_digest)
    ca_full = dict(ca_real)
    ca_full["_digest"] = cad  # internal handle only; never serialized into the permit hash

    # ---- A26 concrete grant match (DECISION; the match + grant-limit algebra ran early above). -----
    ok = grant_ok
    if not ok and _rc_launder(pmeta, "grant", mutations):
        # R1-ROLE-1 defect: a diagnostic/working carrier is accepted as a grant (grant authority).
        _ = _rc_grant_from_carrier(obj["tool_id"], action_namespace, targets, effects)
        matched, ok = ["g_rc_carrier"], True
    if not ok:
        return _deny(st, "A26_grant", mutations)

    # ---- A27 side-effect policy (deny path; escalation already folded into eff_risk). --------
    if policy_deny:
        return _deny(st, "A27_policy_deny", mutations)

    # ---- A28 approval requirement (strictest). -----------------------------------------------
    approval_req = S.approval_required(opman["approval_requirement"], eff_risk, {"derived_effect_set": effects},
                                       policy_approval, mutations)
    if _rc_launder(pmeta, "policy", mutations):
        # R1-ROLE-1 defect: a diagnostic/working carrier weakens the side-effect policy / approval
        # escalation. The reference computes approval as the STRICTEST of manifest/risk/effects/policy.
        approval_req = "none"

    # ---- A29 approval validation. ------------------------------------------------------------
    approval_ref = None
    if approval_req == "always":
        if "M-E12" in mutations:
            approval_ref = None  # seeded defect: skip required approval
        else:
            rec = st.approvals.find_by_digest(cad, obj["task_id"], action_namespace,
                                              man["manifest_version"], man["manifest_digest"],
                                              grant_ref, st.clock.now_ms(), mutations)
            if rec is None:
                if "M-A03" in mutations and pmeta.get("working_approval_claim"):
                    approval_ref = "wm_forged_approval"  # working-memory 'approval received' accepted
                elif _rc_launder(pmeta, "approval", mutations):
                    approval_ref = "rc_carrier_approval"  # R1-ROLE-1: carrier laundered into approval
                else:
                    return _deny(st, "A29_approval", mutations)
            else:
                approval_ref = rec["approval_ref"]

    # ---- A30 completion-contract isolation (does not authorize this action). -----------------
    # amendment 4 (Finding 4): resolve the bound contract via the IMMUTABLE packet_id first (the
    # completion evaluator binds through packet_id, never a current-contract-by-task lookup). The
    # by-task map is retained ONLY as the legacy isolation fallback for the tamper check.
    cc = getattr(st, "completion_by_packet", {}).get(obj["packet_id"])
    if cc is None:
        cc = getattr(st, "completion_contracts", {}).get(obj["task_id"])
    if cc is not None:
        if canon.digest_omitting(cc, "contract_digest") != cc.get("contract_digest"):
            return _deny(st, "A30_completion_tamper", mutations)

    # ---- A31 evidence-dependency gate. -------------------------------------------------------
    dep = opman.get("evidence_dependency", "none")
    if dep in ("packet_answerable", "validated_claims"):
        answerable = (pmeta.get("disposition") == "answerable")
        if not answerable and "M-R01" in mutations and pmeta.get("navigation_present"):
            answerable = True   # seeded defect: navigation cast into evidence coverage
        if not answerable and "M-R02" in mutations and pmeta.get("working_present"):
            answerable = True   # seeded defect: working memory cast into evidence coverage
        if not answerable and "M-R11" in mutations and pmeta.get("routing_present"):
            # amendment 6 / R1-ROLE-1: the #40 0.8.0 router stage-trace is a non-authoritative
            # DIAGNOSTIC; seeded defect M-R11 launders it into evidence coverage.
            answerable = True
        # the FULL R1-ROLE-1 sink matrix over the evidence-class sinks (routing + working carriers):
        for _sink in ("evidence", "evidence_requirement", "coverage_result", "packet_disposition"):
            if not answerable and _rc_launder(pmeta, _sink, mutations):
                answerable = True
        if not answerable:
            return _deny(st, "A31_not_answerable", mutations)
        if not pmeta.get("provenance_ok", False):
            return _deny(st, "A31_provenance", mutations)
        if pmeta.get("contradiction"):
            return _deny(st, "A31_contradiction", mutations)
    if dep == "validated_claims":
        vok = getattr(st, "validated_claims", {}).get(obj["task_id"], False)
        if not vok:
            return _deny(st, "A31_validated_claims", mutations)
    if opman.get("absence_dependent") and "M-R10" not in mutations:
        if not pmeta.get("retrieval_complete", False):
            return _deny(st, "A31_absence_incomplete", mutations)

    # ---- (deterministic TOCTOU probe: a test mutates a snapshot here) ------------------------
    if toctou_hook is not None:
        toctou_hook(st)

    # ---- A32 freshness recheck before issue (TOCTOU barrier). --------------------------------
    # Note: the M-E19/E20/E23 defects are "accept X globally", so they also disable A32's recheck of
    # the same item (otherwise A32 would independently catch them -- defence in depth). M-E25 removes
    # the WHOLE recheck (its kill uses a mid-flight change only A32 can see).
    if "M-E25" not in mutations:
        gs2 = st.grant(grant_ref)
        if gs2 is None or gs2.epoch != grant_epoch_at_check:
            return _deny(st, "A32_grant_change", mutations)
        if "M-E20" not in mutations and not gs2.current:
            return _deny(st, "A32_grant_stale", mutations)
        if st.policy(policy_ref).epoch != policy_epoch_at_check:
            return _deny(st, "A32_policy_change", mutations)
        if "M-E23" not in mutations and not _rc_launder(pmeta, "manifest", mutations) and \
                st.manifests.current_installed_digest(obj["tool_id"]) != man["installed_artifact_digest"]:
            return _deny(st, "A32_installed_drift", mutations)
        hnow = st.health.current(man["health_source"]["source_id"])
        if health_at_check is not None and (hnow is None or hnow != health_at_check):
            return _deny(st, "A32_health_change", mutations)
        pv2 = st.packets.verify_and_get(obj["packet_id"])
        if pv2 is None or not pv2.current:
            return _deny(st, "A32_packet_change", mutations)
        if "M-E19" not in mutations and pv2.non_execution is not False:
            return _deny(st, "A32_packet_change", mutations)

    # ---- A33 atomic permit reservation. ------------------------------------------------------
    seq = getattr(st, "_res_seq", 0)
    st._res_seq = seq + 1
    nonce = canon.sha256_hex(canon.canonical_bytes({"cad": cad, "seq": seq}))[:32]
    permit_id = "permit_" + canon.sha256_hex(canon.canonical_bytes({"cad": cad, "nonce": nonce}))[:40]
    epochs_snapshot = {"grant": grant_epoch_at_check, "policy": policy_epoch_at_check,
                       "store": st.permits.epoch}
    if not st.permits.reserve(permit_id, nonce, idempotency_key, cad, epochs_snapshot, mutations):
        return _deny(st, "A33_reservation", mutations)

    # ---- A34 permit construction. ------------------------------------------------------------
    issued = st.clock.now_ms()
    expiry = issued + 60_000  # bounded minimum lifetime
    permit = {
        "schema": "lifeorch.action_permit/0.1",
        "permit_id": permit_id,
        "issuer": "lifeorch.action_authz/0.1",
        "issuer_version": 1,
        "issued_at_unix_ms": issued,
        "expiry_unix_ms": expiry,
        "task_id": obj["task_id"],
        "packet_id": obj["packet_id"],
        "canonical_action_digest": cad,
        "tool_id": obj["tool_id"],
        "tool_manifest_version": man["manifest_version"],
        "tool_manifest_digest": man["manifest_digest"],
        "operation": obj["operation"],
        "canonical_arguments": canon_args,
        "risk_class": eff_risk,
        "resolved_target_set": targets,
        "authorized_effect_set": effects,
        "effective_namespace": action_namespace,
        "grant_snapshot_ref": grant_ref,
        "matched_grant_ids": sorted(set(matched)),
        "side_effect_policy_ref": policy_ref,
        "limits": limits,
        "sandbox_class": sandbox_class,
        "nonce": nonce,
        "idempotency_key": idempotency_key,
        "permit_store_epoch": st.permits.epoch,
    }
    if approval_ref is not None:
        permit["approval_ref"] = approval_ref
    permit["permit_digest"] = canon.digest_omitting(permit, "permit_digest")

    if "M-E26" in mutations:
        # seeded defect: issue TWO permits from one atomic reservation
        st.permits.insert(dict(permit))
        p2 = dict(permit)
        p2["permit_id"] = permit_id + "b"
        st.permits.insert(p2)
    else:
        st.permits.insert(permit)

    # amendment 3 (Boundary D) + amendment 4 (completion binding): capture the trusted ISSUE-TIME
    # epoch snapshot the executor re-reads AFTER the atomic claim (grant/policy/approval/manifest/
    # artifact/health/packet+status currentness/store epoch), and stamp the IMMUTABLE completion
    # binding resolved via the authentic packet_id (never a current-contract-by-task lookup).
    st.permits.record_issue_snapshot(permit_id, {
        "grant_epoch": grant_epoch_at_check,
        "grant_current": gs.current,
        "policy_epoch": policy_epoch_at_check,
        "installed_digest": man["installed_artifact_digest"],
        "manifest_digest": man["manifest_digest"],
        "health": health_at_check,
        "packet_current": pv.current,
        "packet_non_execution": pv.non_execution,
        "store_epoch": st.permits.epoch,
        "approval_ref": approval_ref,
    })
    st.permits.record_completion_binding(permit_id, st.completion_binding_for_packet(obj["packet_id"]))

    # ---- A35 permit non-disclosure. ----------------------------------------------------------
    if "M-R09" in mutations:
        caller_obj = {"schema": "lifeorch.authorization_result/0.1", "status": "accepted",
                      "code": "PROPOSAL_ACCEPTED_FOR_EXECUTION",
                      "permit": permit, "nonce": nonce, "matched_grant_ids": matched}
    else:
        caller_obj = {"schema": "lifeorch.authorization_result/0.1", "status": "accepted",
                      "code": "PROPOSAL_ACCEPTED_FOR_EXECUTION"}

    # ---- A36 security audit (bounded; no attacker payload; Finding 6). -----------------------
    # EXACTLY ONE correctly-shaped bounded audit event is emitted on a permit -- its ABSENCE is a
    # failure (not the secure baseline). AUDIT-DELETE seeds emission deletion; AUDIT-CORRUPT seeds a
    # malformed/duplicated event carrying an attacker payload. The A36 oracle asserts count==1 +
    # exact shape + no payload against BOTH faults (tests/oracle_matrix.py).
    if "AUDIT-DELETE" not in mutations:
        _audit_ev = {"event": "authz_permit", "permit_id": permit_id, "cad": cad,
                     "tool_id": obj["tool_id"], "operation": obj["operation"]}
        if "AUDIT-CORRUPT" in mutations:
            _audit_ev["leak"] = obj.get("arguments")      # attacker payload copied into the log
            log.events.append(_audit_ev)
            log.events.append(dict(_audit_ev))            # duplicate: no longer EXACTLY ONE
        else:
            log.events.append(_audit_ev)

    return Decision("PERMIT", caller_obj, reason_code=None, permit=permit,
                    permit_ref=PermitRef(permit_id, id(st.permits)),
                    canonical_action=ca_full, cad=cad, matched_grant_ids=sorted(set(matched)))
