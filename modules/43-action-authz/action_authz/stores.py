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

import json
import unicodedata

from . import canon
from .schemas import UINT63_MAX


class WriteOnceError(Exception):
    """i41 round-3 Finding 1: a write-once store slot was written a second time. `.reason` is a stable
    machine code. Raised (fail-closed) so an immutable issue-time binding can never be overwritten."""

    def __init__(self, reason, detail=""):
        super().__init__("%s: %s" % (reason, detail) if detail else reason)
        self.reason = reason


def _gv_uint63(x):
    """True iff x is a JSON integer in [0, UINT63_MAX] (bool is NOT an int here)."""
    return isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= UINT63_MAX


# ===========================================================================
# CONSTANT caller-visible denial (s0.5). No identifying metadata, ever.
CONSTANT_DENIAL = {"schema": "lifeorch.authorization_result/0.1", "status": "denied", "code": "AUTHZ_DENIED"}
CONSTANT_DENIAL_BYTES = canon.canonical_bytes(CONSTANT_DENIAL)

# i40 Finding 1 (completion IMMUTABLE at issue): when a permit is issued with NO completion contract
# bound at issue time, the permit store records this IMMUTABLE sentinel instead of a null binding. A
# permit carrying the sentinel can NEVER become completable via a completion contract inserted AFTER
# issuance (the "late contract insertion" vector). The binding is MANDATORY: absence is fail-closed.
NO_COMPLETION_CONTRACT = "NO_COMPLETION_CONTRACT"


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
    def view_from_real_m40_packet(pkt, non_execution=None):
        """Adapt a REAL #40 context_packet/0.2 JSON object into a trusted PacketView (integration).

        `non_execution` defaults to the packet's own field; integration.py passes an explicit
        `False` ONLY for the authorized TEST-ONLY variant (s8.7 crit 1) that lets execution proceed
        past A06 into A09/A11/A30/A31 -- it NEVER mutates the committed fixture bytes."""
        if pkt.get("schema") != "lifeorch.context_packet/0.2":
            raise ValueError("not a context_packet/0.2")
        ident = pkt.get("identity", {})
        ti = pkt.get("task_input", {})
        ne = bool(pkt.get("non_execution")) if non_execution is None else bool(non_execution)
        return PacketView(
            packet_id=pkt["packet_id"],
            task_id=ident.get("task_id"),
            non_execution=ne,
            namespace=ti.get("namespace"),
            allowed_namespaces=ti.get("allowed_namespaces", []),
            corpus_version=ident.get("corpus_version"),
            grant_snapshot_ref=ident.get("control_plane_grant_snapshot_ref"),
            current=True,
        )

    @staticmethod
    def meta_from_real_m40_packet(pkt):
        """Derive the trusted A08/A31 packet_meta (disposition) from a REAL #40 packet's disposition
        region, plus the presence flags for the 0.8.0 router stage-trace + the 0.9.0 hydrated
        working_memory region. These flags are DIAGNOSTIC-ONLY; the reference monitor never lets them
        satisfy evidence/coverage (R1-ROLE-1)."""
        disp = pkt.get("disposition", {}) or {}
        answerable = (disp.get("packet_disposition") == "answerable")
        eh = pkt.get("evaluation_hooks", {}) or {}
        wm = pkt.get("working_memory", {}) or {}
        return {
            "disposition": "answerable" if answerable else "needs_expansion",
            "provenance_ok": not bool(disp.get("provenance_failed")),
            "contradiction": bool(disp.get("contradictions")),
            "retrieval_complete": answerable,
            # DIAGNOSTIC carriers actually present in the real 0.9.0 packet (never authority):
            "routing_present": isinstance(eh.get("routing_stage_trace"), list) and bool(eh.get("routing_stage_trace")),
            "working_present": bool(wm.get("present")),
        }


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
#
# i40 Finding 4 -- the byte-exact GrantView IMPLEMENTS its declared limit algebra (it no longer reads
# only `max_quantity`). The effective grant-derived quantitative limit for an effect class is
#   grant_effect_limit(g, cls) = min( g.max_quantity[cls] , every g.limits[] entry whose limit_id==cls )
# and, because grants are ALTERNATIVES (scope union) but authority is deny-by-default, the effective
# grant-derived limit across the MATCHED (covering) grants is the GLOBAL MINIMUM (the tightest covering
# authority bounds the effect). A26 intersects THAT with the manifest ceiling (and policy/approval when
# present) at A23. Malformed / duplicate / ambiguous limit entries FAIL CLOSED. The frozen intersection
# rule (MIN) is UNCHANGED -- this is its implementation, not an amendment.

# i41 round-3 Finding 4: the OPERATIONAL pinned CLOSED top-level GrantView. The i40 build validated only
# the closed shape of entries INSIDE limits[]; the top-level grant object was never validated against the
# pinned closed field set, so an arbitrary unknown top-level field on an otherwise-valid grant still
# MATCHED (the reviewer's probe). This validator enforces the exact closed top-level field set + the exact
# operational type of every top-level value BEFORE matching; a grant that diverges is UNTRUSTABLE and
# EXCLUDED (fail closed). The accepted quantitative limit-intersection algebra and the limits[]-ENTRY
# closed-shape checks (_limits_wellformed) are UNCHANGED -- here `limits` need only be a list; its entries
# stay owned by _limits_wellformed. The behavior is pinned AS DATA by GRANT_VIEW_TOPLEVEL (+ digest) and
# exercised by the unknown/missing/mistyped/malformed golden vectors in tests/views_golden.py.
GRANT_VIEW_TOPLEVEL = {
    "schema": "lifeorch.grant_view_operational/0.1-test",
    "closed_fields": {
        "grant_id": "id_str", "tool_id": "str", "operation": "str_or_star", "action_namespace": "str",
        "allowed_target_ids": "array<str>", "effect_classes": "array<str>",
        "max_quantity": "map<str,uint63>", "externality_max": "enum{local,private_external,public_external}",
        "risk_ceiling": "uint{0..4}", "validity_from": "uint63", "validity_to": "uint63",
        "approval_mode": "enum{none,policy_dependent,always}", "scopes": "array<str>",
        "limits": "array (entry shape owned by _limits_wellformed, UNCHANGED)",
    },
    "rule": "EXACTLY the closed field set (no unknown, none missing) with the exact operational type for "
            "every value BEFORE matching; any divergence => the grant is untrustable => excluded (fail closed)",
    "unchanged": "limit-intersection algebra (MIN) + limits[]-entry closed-shape checks",
}
_GV_EXTERNALITY = ("local", "private_external", "public_external")
_GV_APPROVAL_MODE = ("none", "policy_dependent", "always")


def _grant_view_wellformed(g):
    """True iff `g` matches the pinned CLOSED top-level GrantView shape (Finding 4): EXACTLY the closed
    field set (unknown OR missing top-level field fails closed) with the exact operational type for every
    top-level value. Never raises; a malformed grant returns False (excluded from matching). The limits[]
    ENTRY shape is NOT re-validated here (owned, unchanged, by _limits_wellformed) -- `limits` need only
    be a list."""
    if not isinstance(g, dict):
        return False
    if set(g.keys()) != set(GRANT_VIEW_TOPLEVEL["closed_fields"].keys()):
        return False  # unknown OR missing top-level field (the exact closed set)
    if not (isinstance(g["grant_id"], str) and isinstance(g["tool_id"], str)
            and isinstance(g["operation"], str) and isinstance(g["action_namespace"], str)):
        return False
    if not (isinstance(g["allowed_target_ids"], list)
            and all(isinstance(x, str) for x in g["allowed_target_ids"])):
        return False
    if not (isinstance(g["effect_classes"], list)
            and all(isinstance(x, str) for x in g["effect_classes"])):
        return False
    mq = g["max_quantity"]
    if not isinstance(mq, dict):
        return False
    for k, v in mq.items():
        if not isinstance(k, str) or not _gv_uint63(v):
            return False
    if g["externality_max"] not in _GV_EXTERNALITY:
        return False
    rc = g["risk_ceiling"]
    if not (isinstance(rc, int) and not isinstance(rc, bool) and 0 <= rc <= 4):
        return False
    if not (_gv_uint63(g["validity_from"]) and _gv_uint63(g["validity_to"])):
        return False
    if g["approval_mode"] not in _GV_APPROVAL_MODE:
        return False
    if not (isinstance(g["scopes"], list) and all(isinstance(x, str) for x in g["scopes"])):
        return False
    if not isinstance(g["limits"], list):
        return False
    return True


def _limits_wellformed(g):
    """A grant's `limits[]` must be a well-formed array of {limit_id:str, max_value:uint63}. Anything
    malformed (non-list, non-dict entry, missing/negative/oversized/non-int max_value, non-string
    limit_id) makes the grant UNTRUSTABLE for effect bounding -> the grant fails closed (excluded)."""
    lims = g.get("limits", [])
    if not isinstance(lims, list):
        return False
    for lim in lims:
        if not isinstance(lim, dict):
            return False
        if set(lim.keys()) != {"limit_id", "max_value"}:
            return False  # unknown / ambiguous fields fail closed (the CLOSED limit shape)
        lid = lim.get("limit_id")
        mv = lim.get("max_value")
        if not isinstance(lid, str):
            return False
        if not (isinstance(mv, int) and not isinstance(mv, bool) and 0 <= mv <= UINT63_MAX):
            return False
    return True


def grant_effect_limit(g, effect_class):
    """The grant's effective quantitative limit for one effect class = MIN of its max_quantity[cls] and
    EVERY limits[] entry whose limit_id == cls (duplicate ids all apply -> min). No applicable bound =>
    UINT63_MAX (the manifest ceiling still bounds it at A23). Assumes _limits_wellformed(g) is True."""
    vals = []
    mq = g.get("max_quantity", {})
    if isinstance(mq, dict) and effect_class in mq:
        v = mq[effect_class]
        if isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= UINT63_MAX:
            vals.append(v)
        else:
            return 0  # malformed max_quantity for this class -> fail closed
    for lim in g.get("limits", []):
        if lim.get("limit_id") == effect_class:
            vals.append(lim["max_value"])
    return min(vals) if vals else UINT63_MAX


def effective_permit_limits(effects, manifest_ceiling, grant_limits,
                            policy_limits=None, approval_limits=None):
    """A23: effective_limit[cls] = min(manifest ceiling, grant-derived, policy, approval) per effect
    class actually derived. Returns the canonical CLOSED limits array [{limit_id, max_value}] sorted.
    Sources with no entry for a class do not bound it; a class with NO source bound => UINT63_MAX."""
    policy_limits = policy_limits or {}
    approval_limits = approval_limits or {}
    out = {}
    for e in effects:
        cls = e["effect_class"]
        vals = []
        for src in (manifest_ceiling, grant_limits, policy_limits, approval_limits):
            if cls in src:
                vals.append(src[cls])
        out[cls] = min(vals) if vals else UINT63_MAX
    return canon.canon_sorted_set([{"limit_id": k, "max_value": out[k]} for k in sorted(out)])


class GrantSnapshot(object):
    def __init__(self, grant_snapshot_ref, grants, epoch=1, current=True, revoked=None,
                 request_namespaces=None):
        self.ref = grant_snapshot_ref
        self.grants = grants
        self.epoch = epoch
        self.current = current
        self.revoked = set(revoked or [])
        self.request_namespaces = list(request_namespaces or [])

    def _valid_grants(self, mutations=frozenset()):
        """i41 round-4 Finding 4: the ONE shared VALIDATED-grant iterator used by BOTH grant_namespaces()
        and match(). A grant is yielded ONLY after it passes the pinned CLOSED top-level GrantView
        validation (_grant_view_wellformed), so NO raw grant field is EVER dereferenced before validation.
        This closes the A11 grant_namespaces() KeyError path: a grant missing grant_id / action_namespace
        (or unknown/mistyped/malformed top-level) is EXCLUDED here -- never dereferenced -- so the A11 read
        fails closed to constant DENY instead of raising. M-GV01 is the decidable seeded defect that SKIPS
        the validation (kept killable AND load-bearing at BOTH A11 and A26)."""
        skip = "M-GV01" in mutations
        for g in self.grants:
            if skip or _grant_view_wellformed(g):
                yield g

    def grant_namespaces(self, mutations=frozenset()):
        """A11: the effective action namespaces the VALIDATED grants authorize, via the ONE shared
        validated-grant iterator. No raw grant field is dereferenced before validation, so a malformed
        grant (missing/mistyped grant_id or action_namespace) is EXCLUDED and fails closed to constant
        DENY -- never an uncaught KeyError (i41 round-4 Finding 4)."""
        return {g["action_namespace"] for g in self._valid_grants(mutations)
                if g["grant_id"] not in self.revoked}

    def match(self, ca, now_ms, opman, mutations=frozenset()):
        """CLOSED matcher result (Finding 4): a 3-tuple (matched_grant_ids sorted-unique, ok,
        effective_grant_limits). `effective_grant_limits` is {effect_class: uint63} -- the GLOBAL MIN
        of grant_effect_limit(g, cls) over the MATCHED grants (the tightest covering authority). Deny
        (ok=False, {}) if no grant covers or a required scope is uncovered. The DECISION semantics are
        unchanged; the third element is the newly-implemented grant-derived limit algebra."""
        target_ids = {t["canonical_target_id"] for t in ca["resolved_target_set"]}
        classes = {e["effect_class"] for e in ca["derived_effect_set"]}
        matched = []
        covered_scopes = set()
        eff_limits = {}                     # effect_class -> running MIN over matched grants
        # Finding 4: iterate the ONE shared VALIDATED-grant iterator so the pinned CLOSED top-level
        # GrantView validation runs BEFORE any raw grant field is dereferenced (same validation that now
        # also protects the earlier A11 grant_namespaces() read). A grant whose top-level shape diverges
        # (unknown/missing/mistyped/malformed field) is untrustable and EXCLUDED (fail closed). M-GV01 is
        # the decidable defect that skips this validation (in the shared iterator).
        for g in self._valid_grants(mutations):
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
            # malformed/ambiguous limits[] => the grant is untrustable for bounding => fail closed.
            if not _limits_wellformed(g):
                continue
            # concrete target closure (A26)
            if "M-E09" not in mutations:
                allowed_t = set(g.get("allowed_target_ids", []))
                if not target_ids.issubset(allowed_t):
                    continue  # some target not authorized by this grant
            # concrete effect closure (A26) -- now reads BOTH max_quantity AND limits[] (min).
            if "M-E10" not in mutations:
                ok_eff = True
                for e in ca["derived_effect_set"]:
                    if e["effect_class"] not in g.get("effect_classes", []):
                        ok_eff = False
                        break
                    eff_lim = grant_effect_limit(g, e["effect_class"])   # min(max_quantity, limits[])
                    if e["quantity"] > eff_lim:
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
            # accumulate the GLOBAL MIN grant-derived limit per derived effect class over matched grants
            for cls in classes:
                gl = grant_effect_limit(g, cls)
                eff_limits[cls] = gl if cls not in eff_limits else min(eff_limits[cls], gl)
        required = set(opman.get("required_permission_scopes", []))
        if not matched:
            return [], False, {}
        if not required.issubset(covered_scopes):
            return [], False, {}
        return sorted(set(matched)), True, eff_limits


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
            # freshness + supersession/revocation (a superseded or revoked status is not current;
            # Finding 4 substitution: superseded/revoked status cannot satisfy completion).
            if "M-E35" not in mutations:
                if now_ms - r.get("at_ms", 0) > max_age_ms:
                    continue  # stale
                if r.get("superseded") or r.get("revoked"):
                    continue
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
        # amendment 3 (Boundary D, red-team Finding 5): the trusted ISSUE-TIME epoch snapshot the
        # executor re-reads ALL of after the atomic claim (grant/policy/approval/manifest+artifact/
        # health/packet+status currentness/store-epoch). Keyed by permit_id; recorded at A34.
        self._issue_snapshot = {}  # permit_id -> {grant_epoch, policy_epoch, installed_digest, ...}
        # amendment 4 (red-team Finding 4) + i41 round-3 Finding 1: the IMMUTABLE, WRITE-ONCE completion
        # binding stamped at issue time from the authentic packet_id, stored as private canonical bytes
        # (record_completion_binding rejects any second write; completion_binding returns a defensive copy).
        self._completion_binding = {}  # permit_id -> immutable canonical bytes (write-once)

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

    def record_issue_snapshot(self, permit_id, snapshot):
        """Capture the trusted epoch snapshot the executor re-reads after claim (Boundary D)."""
        self._issue_snapshot[permit_id] = dict(snapshot)

    def issue_snapshot(self, permit_id):
        return self._issue_snapshot.get(permit_id)

    def record_completion_binding(self, permit_id, binding):
        """i41 round-3 Finding 1: WRITE-ONCE per permit_id. The issue-time completion binding is
        IMMUTABLE -- ANY second recording attempt (even one carrying an identical value) is REJECTED
        (raises WriteOnceError, fail-closed), so the NO_COMPLETION_CONTRACT sentinel or the original
        binding can NEVER be overwritten after issuance. The stored representation is PRIVATE CANONICAL
        BYTES (immutable); completion_binding() returns a defensive copy. This makes the review's
        reproduced 5-step overwrite sequence fail at step 3 (the re-record)."""
        if permit_id in self._completion_binding:
            raise WriteOnceError("completion_binding_write_once", permit_id)
        self._completion_binding[permit_id] = canon.canonical_bytes(binding)  # immutable bytes

    def completion_binding(self, permit_id):
        """Return a DEFENSIVE COPY (a fresh object parsed from the immutable stored canonical bytes) of
        the issue-time binding, or None if no binding was ever stamped (the evaluator fails closed on an
        absent binding). Mutating the returned object NEVER affects the store."""
        raw = self._completion_binding.get(permit_id)
        if raw is None:
            return None
        return json.loads(raw.decode("utf-8"))

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
        # amendment 4 (red-team Finding 4): completion contracts bound to a packet by its IMMUTABLE
        # packet_id (the control-plane store). The completion evaluator resolves ONLY from here via
        # the permit's packet_id -- NEVER a current-contract-by-task lookup. `completion_contracts`
        # (by task_id) is retained ONLY for the A30 isolation tamper-check + legacy leaf tests.
        self.completion_by_packet = {}

    def grant(self, ref):
        return self.grants.get(ref)

    def policy(self, ref):
        return self.policies.get(ref)

    def completion_contract_for_packet(self, packet_id, mutations=frozenset()):
        """Resolve the completion contract via the authentic immutable packet_id (Finding 4).
        Seeded defect M-E36 substitutes a current-contract-BY-TASK lookup (the substitution hole)."""
        cc = self.completion_by_packet.get(packet_id)
        if cc is not None:
            return cc
        if "M-E36" in mutations:
            pv = self.packets.verify_and_get(packet_id)
            if pv is not None:
                return self.completion_contracts.get(pv.task_id)
        return None

    def completion_binding_for_packet(self, packet_id):
        """The IMMUTABLE completion binding stamped into a permit at issue time (Finding 1).

        Returns the {completion_contract_id, contract_version, contract_digest} of the contract bound
        by the authentic packet_id AT ISSUE, or -- when NO completion contract exists at issue time --
        the explicit immutable ``{"sentinel": NO_COMPLETION_CONTRACT}``. The binding is NEVER None:
        every store-issued permit records exactly one immutable binding, and a permit issued with the
        sentinel can never become completable through a later contract insertion. Fail-closed by
        construction: the completion evaluator treats an absent binding (permit never stamped) as
        indeterminate, and the sentinel as permanently-incomplete."""
        cc = self.completion_by_packet.get(packet_id)
        if cc is None:
            return {"sentinel": NO_COMPLETION_CONTRACT}
        return {"completion_contract_id": cc.get("completion_contract_id"),
                "contract_version": cc.get("contract_version"),
                "contract_digest": cc.get("contract_digest")}
