"""
schemas.py -- the four CLOSED schema validators (s1-s4) + the ClosedArgSchema validator (s2.4).

Closed-object rule (s0.4.4/5): exact field set (unknown fields rejected), required fields present,
exact types (NO coercion), bounds. Any violation => SchemaError => the monitor DENYs.

Seeded defects: M-E02 (schema downgrade / unknown-field tolerance), M-E03 (type coercion).
"""

import re

from . import canon

_ID_RE = re.compile(r"^[A-Za-z0-9._:\-]{1,256}$")
_NSID_RE = re.compile(r"^[a-z][a-z0-9._:\-]{0,127}$")
_SHA_RE = re.compile(r"^[0-9a-f]{64}$")
_NONCE_RE = re.compile(r"^[0-9a-f]{32}$")
UINT63_MAX = 9223372036854775807
RISK_CLASSES = (0, 1, 2, 3, 4)


class SchemaError(Exception):
    def __init__(self, reason, detail=""):
        super().__init__("%s: %s" % (reason, detail) if detail else reason)
        self.reason = reason


# --- exact scalar type predicates (bool is NOT an int here; JSON has distinct types) ---
def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def is_bool(x):
    return isinstance(x, bool)


def is_str(x):
    return isinstance(x, str)


def is_obj(x):
    return isinstance(x, dict)


def is_arr(x):
    return isinstance(x, list)


def is_id(x):
    return is_str(x) and bool(_ID_RE.match(x))


def is_nsid(x):
    return is_str(x) and bool(_NSID_RE.match(x))


def is_sha(x):
    return is_str(x) and bool(_SHA_RE.match(x))


def is_uint63(x):
    return is_int(x) and 0 <= x <= UINT63_MAX


def _require(cond, reason, detail=""):
    if not cond:
        raise SchemaError(reason, detail)


def _closed_fields(obj, allowed, required, mutations, where):
    """Reject unknown fields (unless M-E02) and missing required fields."""
    _require(is_obj(obj), "not_object", where)
    if "M-E02" not in mutations:
        for k in obj.keys():
            _require(k in allowed, "unknown_field", "%s.%s" % (where, k))
    for r in required:
        _require(r in obj, "missing_field", "%s.%s" % (where, r))


# ---------------------------------------------------------------------------
# s1. lifeorch.action_proposal/0.1  (Untrusted, model-facing; A03 validates it).

_PROPOSAL_FIELDS = {
    "schema", "proposal_id", "task_id", "packet_id", "tool_id", "operation",
    "arguments", "evidence_refs", "claimed_effects", "model_provenance",
}
_MODEL_PROV_FIELDS = {
    "model_run_id", "adapter_id", "adapter_version", "consumer_profile_fingerprint",
    "prompt_packet_id", "raw_output_hash",
}


def validate_action_proposal(obj, mutations=frozenset()):
    _closed_fields(obj, _PROPOSAL_FIELDS, _PROPOSAL_FIELDS, mutations, "proposal")
    _require(obj.get("schema") == "lifeorch.action_proposal/0.1", "bad_schema", str(obj.get("schema")))
    _require(is_id(obj["proposal_id"]), "proposal_id")
    _require(is_id(obj["task_id"]), "task_id")
    _require(is_id(obj["packet_id"]), "packet_id")
    _require(is_nsid(obj["tool_id"]), "tool_id")
    _require(is_nsid(obj["operation"]), "operation")
    _require(is_obj(obj["arguments"]), "arguments_not_object")

    er = obj["evidence_refs"]
    _require(is_arr(er) and len(er) <= 256, "evidence_refs_bounds")
    _require(all(is_id(x) for x in er), "evidence_refs_type")
    _require(len(set(er)) == len(er), "evidence_refs_dup")

    ce = obj["claimed_effects"]
    _require(is_arr(ce) and len(ce) <= 256, "claimed_effects_bounds")
    _require(all(is_obj(x) for x in ce), "claimed_effects_type")

    mp = obj["model_provenance"]
    _closed_fields(mp, _MODEL_PROV_FIELDS, _MODEL_PROV_FIELDS, mutations, "model_provenance")
    _require(is_id(mp["model_run_id"]), "mp.model_run_id")
    _require(is_nsid(mp["adapter_id"]), "mp.adapter_id")
    _require(is_uint63(mp["adapter_version"]), "mp.adapter_version")
    _require(is_sha(mp["consumer_profile_fingerprint"]), "mp.consumer_profile_fingerprint")
    _require(is_id(mp["prompt_packet_id"]), "mp.prompt_packet_id")
    _require(is_sha(mp["raw_output_hash"]), "mp.raw_output_hash")
    return obj


# ---------------------------------------------------------------------------
# s2.4 ClosedArgSchema validator (A15). Closed, non-coercing input schema.

_ARG_TYPES = {
    "string", "integer", "boolean", "object",
    "string_array", "integer_array", "object_array",
}


def _check_scalar(val, ftype, fs, mutations, where):
    coerce = "M-E03" in mutations
    if ftype == "string":
        if not is_str(val):
            _require(coerce, "type_string", where)
            val = str(val)
        b = len(val.encode("utf-8"))
        if "min_utf8_bytes" in fs:
            _require(b >= fs["min_utf8_bytes"], "min_utf8_bytes", where)
        if "max_utf8_bytes" in fs:
            _require(b <= fs["max_utf8_bytes"], "max_utf8_bytes", where)
    elif ftype == "integer":
        if not is_int(val):
            _require(coerce, "type_integer", where)
        if "min_value" in fs and is_int(val):
            _require(val >= fs["min_value"], "min_value", where)
        if "max_value" in fs and is_int(val):
            _require(val <= fs["max_value"], "max_value", where)
    elif ftype == "boolean":
        if not is_bool(val):
            _require(coerce, "type_boolean", where)
    if "enum_values" in fs:
        _require(val in fs["enum_values"], "enum", where)
    return val


def validate_closed_args(args, arg_schema, mutations=frozenset()):
    """Validate proposal.arguments against a manifest OperationManifest.arg_schema (ClosedArgSchema).
    Returns the validated args (a coerced COPY when the M-E03 defect is active, so the coercion is
    actually observable downstream -- otherwise a byte-identical copy)."""
    _require(is_obj(arg_schema) and arg_schema.get("type") == "object", "arg_schema_root")
    _require(arg_schema.get("additional_properties") is False, "arg_schema_open")
    fields = {f["name"]: f for f in arg_schema.get("fields", [])}
    _require(is_obj(args), "args_not_object")

    if "M-E02" not in mutations:
        for k in args.keys():
            _require(k in fields, "unknown_arg", k)

    out = dict(args)
    for name, fs in fields.items():
        ftype = fs["type"]
        _require(ftype in _ARG_TYPES, "bad_arg_type", ftype)
        present = name in args
        if not present:
            _require(not fs.get("required", False), "missing_required_arg", name)
            continue
        val = args[name]
        where = "args.%s" % name
        if ftype in ("string", "integer", "boolean"):
            out[name] = _check_scalar(val, ftype, fs, mutations, where)
        elif ftype == "object":
            _require(is_obj(val), "type_object", where)
            if "object_schema" in fs:
                out[name] = validate_closed_args(val, fs["object_schema"], mutations)
        elif ftype in ("string_array", "integer_array", "object_array"):
            _require(is_arr(val), "type_array", where)
            if "min_items" in fs:
                _require(len(val) >= fs["min_items"], "min_items", where)
            if "max_items" in fs:
                _require(len(val) <= fs["max_items"], "max_items", where)
            elem = {"string_array": "string", "integer_array": "integer", "object_array": "object"}[ftype]
            new_list = []
            for i, v in enumerate(val):
                if elem == "object":
                    _require(is_obj(v), "type_object", "%s[%d]" % (where, i))
                    if "object_schema" in fs:
                        new_list.append(validate_closed_args(v, fs["object_schema"], mutations))
                    else:
                        new_list.append(v)
                else:
                    new_list.append(_check_scalar(v, elem, fs, mutations, "%s[%d]" % (where, i)))
            out[name] = new_list
    return out


# ---------------------------------------------------------------------------
# s3. lifeorch.action_permit/0.1 -- validator used to (a) load store permits, (b) let the executor
# reject permit-SHAPED caller JSON that never resolved from the trusted store (D2).

_PERMIT_REQUIRED = {
    "schema", "permit_id", "issuer", "issuer_version", "issued_at_unix_ms", "expiry_unix_ms",
    "task_id", "packet_id", "canonical_action_digest", "tool_id", "tool_manifest_version",
    "tool_manifest_digest", "operation", "canonical_arguments", "risk_class", "resolved_target_set",
    "authorized_effect_set", "effective_namespace", "grant_snapshot_ref", "matched_grant_ids",
    "side_effect_policy_ref", "limits", "sandbox_class", "nonce", "idempotency_key",
    "permit_store_epoch", "permit_digest",
}
_PERMIT_ALLOWED = _PERMIT_REQUIRED | {"approval_ref"}  # approval_ref conditional


def validate_action_permit_shape(obj, mutations=frozenset()):
    _closed_fields(obj, _PERMIT_ALLOWED, _PERMIT_REQUIRED, mutations, "permit")
    _require(obj.get("schema") == "lifeorch.action_permit/0.1", "bad_schema")
    _require(is_id(obj["permit_id"]), "permit_id")
    _require(is_sha(obj["canonical_action_digest"]), "cad")
    _require(is_sha(obj["permit_digest"]), "permit_digest")
    _require(_NONCE_RE.match(obj["nonce"]) is not None, "nonce")
    _require(obj["risk_class"] in RISK_CLASSES, "risk_class")
    _require(is_uint63(obj["issued_at_unix_ms"]) and is_uint63(obj["expiry_unix_ms"]), "times")
    _require(obj["expiry_unix_ms"] > obj["issued_at_unix_ms"], "expiry_le_issue")
    return obj


# ---------------------------------------------------------------------------
# s4. lifeorch.completion_contract/0.1 -- structural validation for stored contracts.

_COMPLETION_REQUIRED = {
    "schema", "completion_contract_id", "contract_version", "task_id", "effective_namespace",
    "grant_snapshot_ref", "root", "trusted_status_sources", "evaluation_policy", "contract_digest",
}
_EVAL_POLICY = {"missing": "indeterminate", "malformed": "indeterminate",
                "stale": "indeterminate", "indeterminate_is_complete": False}


def validate_completion_contract(obj, mutations=frozenset()):
    _closed_fields(obj, _COMPLETION_REQUIRED, _COMPLETION_REQUIRED, mutations, "completion")
    _require(obj.get("schema") == "lifeorch.completion_contract/0.1", "bad_schema")
    _require(obj.get("evaluation_policy") == _EVAL_POLICY, "evaluation_policy")
    _require(is_id(obj["task_id"]), "task_id")
    _validate_expr(obj["root"], 1, mutations)
    return obj


def _validate_expr(node, depth, mutations):
    _require(depth <= 16, "completion_depth")
    _require(is_obj(node) and "kind" in node, "expr")
    kind = node["kind"]
    if kind == "leaf":
        _require("predicate" in node, "leaf_predicate")
    elif kind in ("all", "any"):
        _require(is_arr(node.get("children")) and node["children"], "children")
        for c in node["children"]:
            _validate_expr(c, depth + 1, mutations)
    elif kind == "at_least":
        ch = node.get("children")
        _require(is_arr(ch) and ch, "children")
        t = node.get("threshold")
        _require(is_uint63(t) and 1 <= t <= len(ch), "threshold")
        for c in ch:
            _validate_expr(c, depth + 1, mutations)
    else:
        raise SchemaError("expr_kind", str(kind))
