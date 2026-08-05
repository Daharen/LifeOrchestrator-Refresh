"""
stores.py -- the trusted snapshot stores the reference monitor reads (all MOCK, in-process, deterministic).

These stand in for the companion trusted interfaces that are ACTIVATION-gating blockers (contract s2):
  - GrantView / PolicyView              (Blocker 1: real permission_grant/0.1 + side_effect_policy/0.1)
  - ApprovalStore                       (Blocker 2: real action_approval/0.1)
  - PermitStore (in-process atomic MOCK)(Blocker 3: real Windows IPC/ACL/CAS/epoch/crash recovery -> i38)
  - target_resolver / effect_classifier (Blocker 4: per-tool Windows path/reparse/ADS profiles -> i38)
  - HealthSource / ValidatorRegistry    (Blockers 5/11)
  - SecurityLog + constant denial       (Blocker 9: production privileged-log ownership -> i38)

The generic resolver/effect INTERFACES are frozen here; the Windows-specific per-tool PROFILE DEPTH
(reparse points, alternate data streams, junctions, device names) is STAGED to i38 (Blocker 4).
"""

import unicodedata

from . import canon
from .schemas import UINT63_MAX


# ===========================================================================
# CONSTANT caller-visible denial (s0.5). No identifying metadata, ever.
CONSTANT_DENIAL = {"schema": "lifeorch.authorization_result/0.1", "status": "denied", "code": "AUTHZ_DENIED"}
CONSTANT_DENIAL_BYTES = canon.canonical_bytes(CONSTANT_DENIAL)


class SecurityLog(object):
    """Bounded, privileged, local security log (s0.5 / A36). Attacker-controlled payload is NEVER
    copied here except length-bounded in an explicit non-executable data field."""

    def __init__(self):
        self.events = []          # privileged; not caller-visible
        self.caller_channel = []  # what an ordinary caller would receive (must stay constant)

    def deny(self, reason_code, mutations=frozenset(), leak=None):
        # A36: privileged event carries a bounded reason code only.
        ev = {"event": "authz_deny", "reason_code": str(reason_code)[:64]}
        if "M-S09" in mutations and leak is not None:
            ev["leak"] = str(leak)  # seeded defect: attacker payload into an ordinary log
        self.events.append(ev)
        # M-S08: return identifying data / a variant code to the ordinary caller (an oracle).
        if "M-S08" in mutations:
            self.caller_channel.append({"schema": CONSTANT_DENIAL["schema"], "status": "denied",
                                        "code": "AUTHZ_DENIED_%s" % reason_code, "detail": leak})
            return dict(self.caller_channel[-1])
        self.caller_channel.append(dict(CONSTANT_DENIAL))
        return dict(CONSTANT_DENIAL)


# ===========================================================================
# Deterministic trusted clock (no wall-clock reaches the canonical_action_digest, s0.6).
class Clock(object):
    def __init__(self, base_ms=1_700_000_000_000):
        self._now = base_ms

    def now_ms(self):
        return self._now

    def advance(self, ms):
        self._now += ms


# ===========================================================================
# Packet store + integrity verifier.
class PacketView(object):
    __slots__ = ("packet_id", "task_id", "non_execution", "namespace", "allowed_namespaces",
                 "corpus_version", "grant_snapshot_ref", "current", "content_digest")

    def __init__(self, packet_id, task_id, non_execution, namespace, allowed_namespaces,
                 corpus_version, grant_snapshot_ref, current=True, content_digest=None):
        self.packet_id = packet_id
        self.task_id = task_id
        self.non_execution = non_execution
        self.namespace = namespace
        self.allowed_namespaces = list(allowed_namespaces)
        self.corpus_version = corpus_version
        self.grant_snapshot_ref = grant_snapshot_ref
        self.current = current
        self.content_digest = content_digest


class PacketStore(object):
    def __init__(self):
        self._by_id = {}

    def put(self, view):
        # integrity digest over the trusted view fields
        if view.content_digest is None:
            view.content_digest = canon.digest_of({
                "packet_id": view.packet_id, "task_id": view.task_id,
                "non_execution": view.non_execution, "namespace": view.namespace,
                "allowed_namespaces": sorted(view.allowed_namespaces),
                "corpus_version": view.corpus_version, "grant_snapshot_ref": view.grant_snapshot_ref})
        self._by_id[view.packet_id] = view
        return view

    def verify_and_get(self, packet_id):
        return self._by_id.get(packet_id)

    @staticmethod
    def view_from_real_m40_packet(pkt):
        """Adapt a REAL #40 context_packet/0.2 JSON object into a trusted PacketView (integration)."""
        if pkt.get("schema") != "lifeorch.context_packet/0.2":
            raise ValueError("not a context_packet/0.2")
        ident = pkt.get("identity", {})
        ti = pkt.get("task_input", {})
        return PacketView(
            packet_id=pkt["packet_id"],
            task_id=ident.get("task_id"),
            non_execution=bool(pkt.get("non_execution")),
            namespace=ti.get("namespace"),
            allowed_namespaces=ti.get("allowed_namespaces", []),
            corpus_version=ident.get("corpus_version"),
            grant_snapshot_ref=ident.get("control_plane_grant_snapshot_ref"),
            current=True,
        )


# ===========================================================================
# Adapter attestation (A04): the trusted model adapter's record of the raw model output.
class AdapterAttestation(object):
    def __init__(self):
        self._by_run = {}

    def put(self, model_run_id, raw_output_hash, prompt_packet_id, model_supplied_provenance=False):
        self._by_run[model_run_id] = {
            "raw_output_hash": raw_output_hash,
            "prompt_packet_id": prompt_packet_id,
            "model_supplied_provenance": model_supplied_provenance,
        }

    def get(self, model_run_id):
        return self._by_run.get(model_run_id)


# ===========================================================================
# Tool-manifest registry (Authority; A12-A14). Canonicalizer/resolver/effect-classifier are
# installed-code PROFILES resolved by id -- never defined by a card/proposal/evidence.

class ResolveCtx(object):
    """Trusted local resolution snapshot for the mock resolver profiles."""

    def __init__(self):
        self.env = {"HOME": "/u/data", "ROOT": "/u"}
        self.symlinks = {"/u/data/link_a": "/u/data/real_a",         # one-hop alias table
                        "/u/data/projA/decoy.txt": "/u/shared/leak.txt"}  # in-scope name -> out-of-scope target
        self.path_ns = [("/u/data/projA", "projA"), ("/u/data/projB", "projB"),
                        ("/u/data", "core-docs"), ("/u/shared", "shared")]
        # a wildcard listing that includes a file OUTSIDE the baseline grant (three.txt) so a
        # wildcard expansion is denied at concrete grant match (family 9).
        self.listing = {"/u/data/projA": ["/u/data/projA/one.txt", "/u/data/projA/two.txt",
                                          "/u/data/projA/three.txt"]}
        self.transitive_ns = {}  # canonical_target_id -> [transitive provenance namespaces] (M-S05)

    def namespace_of(self, path):
        for prefix, ns in self.path_ns:
            if path == prefix or path.startswith(prefix + "/"):
                return ns
        return "unknown"


def _expand_env(path, ctx, mutations):
    if "M-E06" in mutations:
        return path  # seeded defect: fail to expand env vars
    out = path
    for k, v in ctx.env.items():
        out = out.replace("${%s}" % k, v)
    return out


def _follow_symlink(path, ctx, mutations):
    if "M-E06" in mutations:
        return path  # seeded defect: fail to resolve symlinks/junctions/redirects
    return ctx.symlinks.get(path, path)


def profile_resolve_fs(op, canon_args, ctx, opman, mutations):
    """target_resolver profile: caller path -> canonical target identity + namespace (A17)."""
    raw = canon_args.get("path", "")
    # a synthetic multi-namespace target set (used only to exercise the A18 single-namespace check).
    if raw == "/u/multi":
        resolved_list = ["/u/data/projA/one.txt", "/u/data/projB/b.txt"]
    elif "M-E05" in mutations:
        # seeded defect: resolve targets using CALLER SPELLING, not canonical identity
        resolved_list = [raw]
    else:
        expanded = _expand_env(raw, ctx, mutations)
        # wildcard expansion
        if "*" in expanded:
            base = expanded.rsplit("/", 1)[0]
            resolved_list = list(ctx.listing.get(base, [])) or []
            if not resolved_list:
                raise _ResolveError("wildcard_no_match")
        else:
            resolved_list = [_follow_symlink(expanded, ctx, mutations)]
    targets = []
    for i, rp in enumerate(resolved_list):
        true_ns = ctx.namespace_of(rp)
        if "M-S06" in mutations and rp != raw:
            # seeded defect: a symlink/alias/redirect resolved OUT of scope but keeps the requested
            # (in-scope) path's namespace instead of the true resolved namespace.
            ns = ctx.namespace_of(raw)
        else:
            ns = true_ns
        targets.append({
            "target_kind": "fs.file",
            "canonical_target_id": rp,
            "namespace": ns,
            "resolution_kind": "existing",
            "resolution_proof_digest": canon.sha256_hex(("resolve:%s->%s" % (raw, rp)).encode("utf-8")),
        })
    return canon.canon_sorted_set(targets)


class _ResolveError(Exception):
    pass


def profile_classify_fs_write(op, canon_args, targets, opman, mutations):
    content = canon_args.get("content", "")
    qty = len(content.encode("utf-8"))
    effects = []
    for i, _t in enumerate(targets):
        effects.append({"effect_class": "fs.write", "target_index": i, "quantity": qty,
                        "unit": "bytes", "effect_risk_class": 2,
                        "externality": "local", "reversibility": "compensatable"})
    return canon.canon_sorted_set(effects)


def profile_classify_fs_delete(op, canon_args, targets, opman, mutations):
    effects = []
    for i, _t in enumerate(targets):
        effects.append({"effect_class": "fs.delete", "target_index": i, "quantity": 1,
                        "unit": "objects", "effect_risk_class": 3,
                        "externality": "local", "reversibility": "irreversible"})
    return canon.canon_sorted_set(effects)


def profile_classify_shell_run(op, canon_args, targets, opman, mutations):
    """WRAPPER classifier (A21): classify the DELEGATED effect, not the wrapper process."""
    if "M-E07" in mutations:
        # seeded defect: classify only the wrapper/meta-tool process effect
        return canon.canon_sorted_set([{"effect_class": "process.spawn", "target_index": 0,
                                        "quantity": 1, "unit": "processes", "effect_risk_class": 1,
                                        "externality": "local", "reversibility": "reversible"}])
    cmd = canon_args.get("command", "")
    effects = []
    for i, _t in enumerate(targets):
        if cmd.startswith("del ") or cmd.startswith("rm "):
            effects.append({"effect_class": "fs.delete", "target_index": i, "quantity": 1,
                            "unit": "objects", "effect_risk_class": 3,
                            "externality": "local", "reversibility": "irreversible"})
        else:
            effects.append({"effect_class": "fs.write", "target_index": i, "quantity": 1,
                            "unit": "bytes", "effect_risk_class": 2,
                            "externality": "local", "reversibility": "compensatable"})
    return canon.canon_sorted_set(effects)


PROFILES = {
    "resolve.fs/1": profile_resolve_fs,
    "resolve.shell/1": profile_resolve_fs,
    "classify.fs.write/1": profile_classify_fs_write,
    "classify.fs.delete/1": profile_classify_fs_delete,
    "classify.shell.run/1": profile_classify_shell_run,
}


class ManifestRegistry(object):
    def __init__(self):
        self._manifests = {}     # tool_id -> manifest object
        self._index = {}         # tool_id -> {version, manifest_digest, installed_artifact_digest, enabled}
        self._current_installed = {}  # tool_id -> current on-disk installed digest (may DRIFT)

    def register(self, manifest):
        tid = manifest["tool_id"]
        self._manifests[tid] = manifest
        self._index[tid] = {
            "manifest_version": manifest["manifest_version"],
            "manifest_digest": manifest["manifest_digest"],
            "installed_artifact_digest": manifest["installed_artifact_digest"],
            "enabled": True,
        }
        self._current_installed[tid] = manifest["installed_artifact_digest"]

    def lookup(self, tool_id, mutations=frozenset()):
        """A12: resolve from the allowlisted registry only; exact tool id, enabled, matching digests."""
        man = self._manifests.get(tool_id)
        idx = self._index.get(tool_id)
        if man is None or idx is None:
            return None
        if not idx["enabled"]:
            return None
        if man["manifest_version"] != idx["manifest_version"]:
            return None
        if man["manifest_digest"] != idx["manifest_digest"]:
            return None
        if man["installed_artifact_digest"] != idx["installed_artifact_digest"]:
            return None
        return man

    def current_installed_digest(self, tool_id):
        return self._current_installed.get(tool_id)

    def set_current_installed(self, tool_id, digest):
        self._current_installed[tool_id] = digest


def build_manifest(tool_id, operations, sandbox_class="local_bounded",
                   installed="a" * 64, health_source=None):
    if health_source is None:
        health_source = {"source_id": "health.fs/1", "source_version": 1,
                         "max_age_ms": 60_000, "healthy_codes": ["ok"]}
    man = {
        "schema": "lifeorch.tool_manifest/0.1",
        "tool_id": tool_id,
        "manifest_version": 1,
        "registry_id": "registry.local/1",
        "installed_artifact_digest": installed,
        "operations": operations,
        "sandbox_class": sandbox_class,
        "health_source": health_source,
    }
    man["manifest_digest"] = canon.digest_omitting(man, "manifest_digest")
    return man


# ===========================================================================
# Grant snapshot + GrantView matcher (A26). Concrete op+target+effect+limit+window matching.
class GrantSnapshot(object):
    def __init__(self, grant_snapshot_ref, grants, epoch=1, current=True, revoked=None,
                 request_namespaces=None):
        self.ref = grant_snapshot_ref
        self.grants = grants
        self.epoch = epoch
        self.current = current
        self.revoked = set(revoked or [])
        self.request_namespaces = list(request_namespaces or [])

    def grant_namespaces(self):
        return {g["action_namespace"] for g in self.grants if g["grant_id"] not in self.revoked}

    def match(self, ca, now_ms, opman, mutations=frozenset()):
        """Return (matched_grant_ids sorted-unique, ok). Deny (ok=False) if scopes uncovered."""
        target_ids = {t["canonical_target_id"] for t in ca["resolved_target_set"]}
        matched = []
        covered_scopes = set()
        for g in self.grants:
            if g["grant_id"] in self.revoked:
                continue
            if g["tool_id"] != ca["tool_id"]:
                continue
            if "M-E08" not in mutations and g["operation"] != ca["operation"]:
                continue  # M-E08: match only on tool id, omit operation
            if g["action_namespace"] != ca["action_namespace"]:
                continue
            # validity window
            if not (g.get("validity_from", 0) <= now_ms < g.get("validity_to", UINT63_MAX)):
                continue
            # concrete target closure (A26)
            if "M-E09" not in mutations:
                allowed_t = set(g.get("allowed_target_ids", []))
                if not target_ids.issubset(allowed_t):
                    continue  # some target not authorized by this grant
            # concrete effect closure (A26)
            if "M-E10" not in mutations:
                ok_eff = True
                for e in ca["derived_effect_set"]:
                    if e["effect_class"] not in g.get("effect_classes", []):
                        ok_eff = False
                        break
                    maxq = g.get("max_quantity", {}).get(e["effect_class"], UINT63_MAX)
                    if e["quantity"] > maxq:
                        ok_eff = False
                        break
                    if _externality_rank(e["externality"]) > _externality_rank(g.get("externality_max", "public_external")):
                        ok_eff = False
                        break
                    if e["effect_risk_class"] > g.get("risk_ceiling", 4):
                        ok_eff = False
                        break
                if not ok_eff:
                    continue
            matched.append(g["grant_id"])
            covered_scopes |= set(g.get("scopes", []))
        required = set(opman.get("required_permission_scopes", []))
        if not matched:
            return [], False
        if not required.issubset(covered_scopes):
            return [], False
        return sorted(set(matched)), True


_EXT_RANK = {"local": 0, "private_external": 1, "public_external": 2}


def _externality_rank(x):
    return _EXT_RANK.get(x, 2)


# ===========================================================================
# Side-effect policy (A27/A28). May narrow/escalate/deny; never weaken.
class PolicyView(object):
    def __init__(self, policy_ref, current=True, epoch=1):
        self.ref = policy_ref
        self.current = current
        self.epoch = epoch

    def apply(self, ca, base_risk, base_approval, base_sandbox, mutations=frozenset()):
        """Return (effective_risk, approval_requirement, sandbox_class, deny_bool)."""
        risk = base_risk
        approval = base_approval
        # rule: any public_external effect escalates approval->always + risk>=3
        has_public = any(e["externality"] == "public_external" for e in ca["derived_effect_set"])
        has_irrev = any(e["reversibility"] == "irreversible" for e in ca["derived_effect_set"])
        esc_risk = 3 if (has_public or has_irrev) else base_risk
        esc_approval = "always" if (has_public or has_irrev) else base_approval
        if "M-E11" in mutations:
            # seeded defect: policy REDUCES risk / approval (weakening)
            risk = min(base_risk, 0)
            approval = "none"
            return risk, approval, base_sandbox, False
        risk = max(base_risk, esc_risk)
        approval = _stricter_approval(base_approval, esc_approval)
        return risk, approval, base_sandbox, False


_APPROVAL_RANK = {"none": 0, "policy_dependent": 1, "always": 2}


def _stricter_approval(a, b):
    return a if _APPROVAL_RANK.get(a, 0) >= _APPROVAL_RANK.get(b, 0) else b


def approval_required(manifest_req, effective_risk, ca, policy_approval, mutations=frozenset()):
    """A28: strictest of manifest, risk, effects, policy."""
    ranks = [_APPROVAL_RANK.get(manifest_req, 0), _APPROVAL_RANK.get(policy_approval, 0)]
    if effective_risk >= 3:
        ranks.append(_APPROVAL_RANK["always"])
    if any(e["reversibility"] == "irreversible" for e in ca["derived_effect_set"]):
        ranks.append(_APPROVAL_RANK["always"])
    top = max(ranks)
    return {0: "none", 1: "policy_dependent", 2: "always"}[top]


# ===========================================================================
# Approval store (A29).
class ApprovalStore(object):
    def __init__(self):
        self._by_ref = {}

    def put(self, rec):
        self._by_ref[rec["approval_ref"]] = rec

    def find_by_digest(self, cad, task_id, namespace, manifest_version, manifest_digest,
                       grant_snapshot_ref, now_ms, mutations=frozenset()):
        """A29: locate a current trusted approval bound to the EXACT canonical_action_digest + task +
        namespace + manifest version/digest + grant snapshot. Seeded defect M-E13 drops the binding."""
        for rec in self._by_ref.values():
            if "M-E13" in mutations:
                return rec  # seeded defect: accept an approval bound to a different digest/task/ns/...
            # exact binding checks (always enforced)
            if rec.get("canonical_action_digest") != cad:
                continue
            if rec.get("task_id") != task_id or rec.get("namespace") != namespace:
                continue
            if rec.get("manifest_version") != manifest_version or rec.get("manifest_digest") != manifest_digest:
                continue
            if rec.get("grant_snapshot_ref") != grant_snapshot_ref:
                continue
            # freshness / revocation checks (skipped by seeded defect M-E21)
            if "M-E21" not in mutations:
                if rec.get("state") != "approved" or rec.get("revoked"):
                    continue
                if now_ms >= rec.get("expiry_unix_ms", UINT63_MAX):
                    continue
            return rec
        return None

    def get_valid(self, approval_ref, ca, task_id, namespace, manifest_version, manifest_digest,
                  grant_snapshot_ref, now_ms, mutations=frozenset()):
        rec = self._by_ref.get(approval_ref)
        if rec is None:
            return None
        if "M-E13" in mutations:
            return rec  # seeded defect: accept approval bound to a different digest/task/ns/...
        if rec.get("state") != "approved":
            return None
        if rec.get("revoked"):
            return None
        if now_ms >= rec.get("expiry_unix_ms", UINT63_MAX):
            return None
        if rec.get("canonical_action_digest") != ca["_digest"]:
            return None
        if rec.get("task_id") != task_id:
            return None
        if rec.get("namespace") != namespace:
            return None
        if rec.get("manifest_version") != manifest_version:
            return None
        if rec.get("manifest_digest") != manifest_digest:
            return None
        if rec.get("grant_snapshot_ref") != grant_snapshot_ref:
            return None
        return rec


# ===========================================================================
# Tool-health source (A14).
class HealthStore(object):
    def __init__(self):
        self._by_source = {}

    def put(self, source_id, code, at_ms):
        self._by_source[source_id] = {"code": code, "at_ms": at_ms}

    def current(self, source_id):
        return self._by_source.get(source_id)


# ===========================================================================
# Validator registry + trusted status store (completion leaves, s4.5).
class StatusStore(object):
    def __init__(self):
        self._records = []  # list of trusted status records

    def put(self, rec):
        self._records.append(rec)

    def find(self, predicate_kind, source_id, source_version, subject, now_ms, max_age_ms,
             effective_namespace, mutations=frozenset()):
        for r in self._records:
            if r.get("predicate_kind") != predicate_kind:
                continue
            if r.get("source_id") != source_id or r.get("source_version") != source_version:
                continue
            # subject binding (every present field must match exactly, s4.4)
            ok = True
            for k, v in subject.items():
                if v is not None and r.get("subject", {}).get(k) != v:
                    ok = False
                    break
            if not ok and "M-E36" not in mutations:
                continue  # M-E36: status from another task/action/permit/object satisfies completion
            # freshness
            if "M-E35" not in mutations:
                if now_ms - r.get("at_ms", 0) > max_age_ms:
                    continue  # stale
            # namespace closure (s4.5.6)
            if "M-S10" not in mutations:
                if not canon.ns_permitted(r.get("namespace"), {effective_namespace}, mutations):
                    continue
            return r
        return None


# ===========================================================================
# Atomic in-process MOCK permit store (Blocker 3: real Windows IPC/ACL/CAS/crash -> i38).
class PermitStore(object):
    def __init__(self):
        self.epoch = 1
        self._permits = {}         # permit_id -> permit obj
        self._state = {}           # permit_id -> issued|claimed|consumed|revoked|expired|rejected_no_effect
        self._effect_started = {}  # permit_id -> bool
        self._reservations = {}    # permit_id -> reservation
        self._idem = {}            # idempotency_key -> permit_id (in-flight/completed)
        self._reserved_digests = set()

    def idempotency_conflict(self, idempotency_key):
        pid = self._idem.get(idempotency_key)
        if pid is None:
            return False
        st = self._state.get(pid)
        return st in ("issued", "claimed", "consumed")

    def reserve(self, permit_id, nonce, idempotency_key, cad, epochs_snapshot, mutations=frozenset()):
        """A33: atomic reservation; only if no conflicting reservation + epochs still equal."""
        if "M-E26" not in mutations:
            if permit_id in self._reservations:
                return False
            if cad in self._reserved_digests and idempotency_key in self._idem:
                # a live reservation for the same idempotent action already exists
                if self.idempotency_conflict(idempotency_key):
                    return False
        self._reservations[permit_id] = {"nonce": nonce, "idempotency_key": idempotency_key,
                                         "cad": cad, "epochs": dict(epochs_snapshot)}
        self._reserved_digests.add(cad)
        self._idem[idempotency_key] = permit_id
        return True

    def insert(self, permit):
        self._permits[permit["permit_id"]] = permit
        self._state[permit["permit_id"]] = "issued"
        self._effect_started[permit["permit_id"]] = False
        return permit

    def get(self, permit_id):
        return self._permits.get(permit_id)

    def state(self, permit_id):
        return self._state.get(permit_id)

    def revoke(self, permit_id):
        if self._state.get(permit_id) == "issued":
            self._state[permit_id] = "revoked"

    def claim(self, permit_id, mutations=frozenset()):
        st = self._state.get(permit_id)
        if "M-E27" in mutations:
            self._state[permit_id] = "claimed"  # seeded defect: reuse after claim/consume/reject
            return True
        if st != "issued":
            return False
        self._state[permit_id] = "claimed"
        return True

    def consume(self, permit_id):
        if self._state.get(permit_id) == "claimed":
            self._state[permit_id] = "consumed"
            self._effect_started[permit_id] = True
            return True
        return False

    def reject_no_effect(self, permit_id):
        if self._state.get(permit_id) == "claimed":
            self._state[permit_id] = "rejected_no_effect"

    def effect_started(self, permit_id):
        return self._effect_started.get(permit_id, False)

    def recover_after_crash(self, permit_id, mutations=frozenset()):
        """A crash after effect_started must NOT make the permit reusable (s3.3 / M-E32)."""
        if "M-E32" in mutations:
            self._state[permit_id] = "issued"  # seeded defect: crash makes permit reusable
            return
        # correct: stays consumed; idempotency/state-diff logic handles recovery
        if self._effect_started.get(permit_id):
            self._state[permit_id] = "consumed"


# ===========================================================================
# Bundle of all stores threaded through the monitor + executor.
class Stores(object):
    def __init__(self):
        self.packets = PacketStore()
        self.attest = AdapterAttestation()
        self.grants = {}            # grant_snapshot_ref -> GrantSnapshot
        self.policies = {}          # policy_ref -> PolicyView
        self.manifests = ManifestRegistry()
        self.approvals = ApprovalStore()
        self.health = HealthStore()
        self.status = StatusStore()
        self.clock = Clock()
        self.permits = PermitStore()
        self.log = SecurityLog()
        self.resolve_ctx = ResolveCtx()
        self.side_effect_policy_ref = None  # the current policy ref for the task authority

    def grant(self, ref):
        return self.grants.get(ref)

    def policy(self, ref):
        return self.policies.get(ref)
