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
    if pv.task_id != obj["task_id"]:
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

    # ---- A08 packet disposition (recorded; applied at A31). ----------------------------------
    pmeta = getattr(st, "packet_meta", {}).get(pv.packet_id,
                                               {"disposition": "answerable", "provenance_ok": True,
                                                "contradiction": False, "retrieval_complete": True})

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
    eff_ns = canon.effective_namespaces(request_ns, gs.grant_namespaces(), mutations)
    if not eff_ns:
        return _deny(st, "A11_empty_namespace", mutations)

    # ---- A12 trusted manifest lookup. --------------------------------------------------------
    man = st.manifests.lookup(obj["tool_id"], mutations)
    if man is None:
        return _deny(st, "A12_manifest", mutations)
    installed_at_check = st.manifests.current_installed_digest(obj["tool_id"])
    if installed_at_check != man["installed_artifact_digest"] and "M-E23" not in mutations:
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
    if "M-A10" not in mutations:
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
        for ns in ns_to_check:
            if not canon.ns_permitted(ns, eff_ns, mutations):
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

    # ---- A23 effective limits (manifest ceiling; grant/approval verified at A26/A29). ---------
    limits = canon.canon_sorted_set(opman.get("resource_ceiling", []))

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

    # ---- A26 concrete grant match. -----------------------------------------------------------
    card = None
    for ce in obj["claimed_effects"]:
        if isinstance(ce, dict) and isinstance(ce.get("card"), dict):
            card = ce["card"]
    opman_match = opman
    if "M-A02" in mutations and card and "required_permission_scopes" in card:
        # seeded defect: a skill/procedure card's required_permission_scopes accepted as manifest data.
        opman_match = dict(opman)
        opman_match["required_permission_scopes"] = card["required_permission_scopes"]
    matched, ok = gs.match(ca_real, st.clock.now_ms(), opman_match, mutations)
    if not ok:
        return _deny(st, "A26_grant", mutations)

    # ---- A27 side-effect policy (deny path; escalation already folded into eff_risk). --------
    if policy_deny:
        return _deny(st, "A27_policy_deny", mutations)

    # ---- A28 approval requirement (strictest). -----------------------------------------------
    approval_req = S.approval_required(opman["approval_requirement"], eff_risk, {"derived_effect_set": effects},
                                       policy_approval, mutations)

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
                else:
                    return _deny(st, "A29_approval", mutations)
            else:
                approval_ref = rec["approval_ref"]

    # ---- A30 completion-contract isolation (does not authorize this action). -----------------
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
        if "M-E23" not in mutations and \
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

    # ---- A35 permit non-disclosure. ----------------------------------------------------------
    if "M-R09" in mutations:
        caller_obj = {"schema": "lifeorch.authorization_result/0.1", "status": "accepted",
                      "code": "PROPOSAL_ACCEPTED_FOR_EXECUTION",
                      "permit": permit, "nonce": nonce, "matched_grant_ids": matched}
    else:
        caller_obj = {"schema": "lifeorch.authorization_result/0.1", "status": "accepted",
                      "code": "PROPOSAL_ACCEPTED_FOR_EXECUTION"}

    # ---- A36 security audit (bounded; no attacker payload). ----------------------------------
    log.events.append({"event": "authz_permit", "permit_id": permit_id, "cad": cad,
                       "tool_id": obj["tool_id"], "operation": obj["operation"]})

    return Decision("PERMIT", caller_obj, reason_code=None, permit=permit,
                    permit_ref=PermitRef(permit_id, id(st.permits)),
                    canonical_action=ca_full, cad=cad, matched_grant_ids=sorted(set(matched)))
