"""
canon.py -- the ONE canonical strict parser + canonical serializer + digest + ns_permitted
            + trust-origin tags for module #43 action.authz (P0-1 reference monitor MVP, i37).

Frozen source: core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its pinned normative text
research/2026-08-05-i36-action-authz-freeze-frontier.md s0.4 (strict parse / canonical serialize),
s0.6 (canonical_action_digest), s7 A5 (the ONE imported ns_permitted).

STANDARD-LIBRARY ONLY. Deterministic. Integer-only JSON. Byte-identical on re-run.

Blocker 8 (canonical parser/serializer/digest/grant-matcher/permit-verifier OWNERSHIP): module #43
owns THIS single canonical implementation; every check imports it (never re-implements it).

The `mutations` parameter (a frozenset of M-* ids) is the in-process seeded-defect switch used ONLY by
the mutation-kill harness (tests/mutations.py). With the default empty set this is the reference impl.
"""

import hashlib
import json

# ---------------------------------------------------------------------------
# Exact byte limits (s0.4.3) per contract object.
PROPOSAL_MAX_BYTES = 1_048_576
MANIFEST_MAX_BYTES = 4_194_304
PERMIT_MAX_BYTES = 4_194_304
COMPLETION_MAX_BYTES = 2_097_152

MAX_DEPTH = 16
MAX_MEMBERS = 1024
MAX_ITEMS = 4096

# Trust-origin classes (s0.2). A value that merely has an authority-shaped field NAME is NOT authority.
AUTHORITY = "authority"
REQUEST = "request"
UNTRUSTED = "untrusted"
TRUSTED_STATUS = "trusted_status"


class CanonError(Exception):
    """Strict-parse / canonicalization failure. `.reason` is a stable machine code."""

    def __init__(self, reason, detail=""):
        super().__init__("%s: %s" % (reason, detail) if detail else reason)
        self.reason = reason


class AuthorityViolation(Exception):
    """Raised when an Untrusted/Request value is routed into the Authority constructor (U-ROLE)."""


# ---------------------------------------------------------------------------
# Strict parser (s0.4: valid-UTF8, dup-key reject, integer-only, depth/size limits).

def _reject_float(_s):
    raise CanonError("float", "floating-point values are forbidden (integer-only JSON)")


def _reject_constant(c):
    raise CanonError("nonfinite", "NaN/Infinity are forbidden: %s" % c)


def _make_pairs_hook(allow_dup):
    def hook(pairs):
        if not allow_dup:
            seen = set()
            for k, _ in pairs:
                if k in seen:
                    raise CanonError("duplicate_key", k)
                seen.add(k)
        return dict(pairs)
    return hook


def _check_limits(o, depth):
    if depth > MAX_DEPTH:
        raise CanonError("max_depth", "> %d" % MAX_DEPTH)
    if isinstance(o, dict):
        if len(o) > MAX_MEMBERS:
            raise CanonError("max_members", "> %d" % MAX_MEMBERS)
        for v in o.values():
            _check_limits(v, depth + 1)
    elif isinstance(o, list):
        if len(o) > MAX_ITEMS:
            raise CanonError("max_items", "> %d" % MAX_ITEMS)
        for v in o:
            _check_limits(v, depth + 1)


def strict_parse(data, max_bytes, mutations=frozenset()):
    """Parse `data` (bytes) under s0.4. Any violation raises CanonError (=> the monitor DENYs).

    - valid UTF-8, BOM rejected, lone surrogates rejected (utf-8 decode does this);
    - duplicate object keys rejected BEFORE schema validation (unless M-E01);
    - integer-only: floats + NaN/Infinity rejected;
    - exact byte limit; max depth 16, max members 1024, max items 4096.
    """
    if not isinstance(data, (bytes, bytearray)):
        raise CanonError("not_bytes", type(data).__name__)
    if len(data) > max_bytes:
        raise CanonError("byte_limit", "%d > %d" % (len(data), max_bytes))
    if data[:3] == b"\xef\xbb\xbf":
        raise CanonError("bom", "UTF-8 BOM rejected")
    try:
        text = bytes(data).decode("utf-8")  # strict: rejects invalid seqs + lone surrogates
    except UnicodeDecodeError as e:
        raise CanonError("invalid_utf8", str(e))
    allow_dup = "M-E01" in mutations  # seeded defect: skip strict duplicate-key rejection
    try:
        obj = json.loads(
            text,
            object_pairs_hook=_make_pairs_hook(allow_dup),
            parse_float=_reject_float,
            parse_constant=_reject_constant,
        )
    except CanonError:
        raise
    except (ValueError, RecursionError) as e:
        raise CanonError("json_parse", str(e))
    _check_limits(obj, 1)
    return obj


# ---------------------------------------------------------------------------
# Canonical serializer (s0.4.6-8) + SHA-256 digests (s0.4.10).

def canonical_bytes(obj):
    """Canonical JSON bytes: keys sorted by Unicode code point, no insignificant whitespace,
    lowercase literals, UTF-8, exactly one trailing LF. Integer-only (allow_nan=False)."""
    try:
        s = json.dumps(
            obj,
            sort_keys=True,          # ascending Unicode code-point key order (s0.4.6)
            ensure_ascii=False,      # lossless UTF-8 (s0.4.8/9)
            separators=(",", ":"),   # no insignificant whitespace (s0.4.8)
            allow_nan=False,         # integers only; no NaN/Infinity (s0.3)
        )
    except ValueError as e:
        raise CanonError("serialize", str(e))
    _reject_floats(obj)
    return s.encode("utf-8") + b"\n"


def _reject_floats(o):
    if isinstance(o, float):
        raise CanonError("float", "canonical output must be integer-only")
    if isinstance(o, dict):
        for v in o.values():
            _reject_floats(v)
    elif isinstance(o, (list, tuple)):
        for v in o:
            _reject_floats(v)


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def digest_of(obj):
    """SHA-256 over canonical bytes (64 lowercase hex)."""
    return sha256_hex(canonical_bytes(obj))


def digest_omitting(obj, self_field):
    """Digest of a closed object with its own self-hash field omitted (s0.4.10)."""
    return digest_of({k: v for k, v in obj.items() if k != self_field})


def canon_sorted_set(items):
    """Deduplicate + sort a set-valued array by canonical element bytes (s0.4.7).
    Elements may be scalars or closed objects."""
    seen = {}
    for it in items:
        key = canonical_bytes(it)
        seen[key] = it
    return [seen[k] for k in sorted(seen.keys())]


# ---------------------------------------------------------------------------
# The ONE canonical namespace predicate (s7 A5). IMPORTED everywhere; never re-implemented.

def ns_permitted(candidate_ns, effective_allowed, mutations=frozenset()):
    """True iff `candidate_ns` is inside the closed set `effective_allowed`.

    NO wildcard / prefix / parent / shared / empty-means-all semantics (s0.3, A11).
    Empty allowed set => zero hits (False). Caller supplies the closed set; this never widens it.
    """
    allowed = frozenset(effective_allowed)
    if "M-S03" in mutations:
        # seeded defect: implicit wildcard/prefix/parent + empty-means-all
        if not allowed or "*" in allowed:
            return True
        for a in allowed:
            if candidate_ns == a or candidate_ns.startswith(a + ".") or candidate_ns.startswith(a):
                return True
        return False
    return candidate_ns in allowed


def effective_namespaces(request_namespaces, grant_namespaces, mutations=frozenset()):
    """A11: authorized namespaces = intersection(Request task_input.namespace, Authority grants).
    Never a union; never proposal-derived; empty intersection => deny (empty set)."""
    req = frozenset(request_namespaces)
    grant = frozenset(grant_namespaces)
    if "M-S01" in mutations:
        return req                    # seeded defect: raw request namespace, no grant intersection
    if "M-S02" in mutations:
        return req | grant            # seeded defect: union instead of intersection
    return req & grant


# ---------------------------------------------------------------------------
# Trust-origin tags (s0.2 / Boundary A1). Kept deliberately small: the property tests use these to
# prove no ordinary path converts Untrusted/Request into Authority (U-ROLE / M-A06 / M-A07).

class Tagged(object):
    __slots__ = ("origin", "value")

    def __init__(self, origin, value):
        self.origin = origin
        self.value = value


def derive(tagged, new_value, mutations=frozenset()):
    """Ordinary copy/summary/cluster/decode/transform PRESERVES non-authoritative origin (A3/A6).
    Seeded defect M-A06 launders the origin to Authority."""
    origin = AUTHORITY if "M-A06" in mutations else tagged.origin
    return Tagged(origin, new_value)


def aggregate_to_authority(record, mutations=frozenset()):
    """A6/M-R03: a derived / aggregate record NEVER becomes execution authority merely because its
    sources had high epistemic authority. Seeded defect M-R03 laundering it into authority."""
    if "M-R03" in mutations:
        return record.get("value")
    raise AuthorityViolation("derived/aggregate record is not execution authority")


def authority_construct(x, mutations=frozenset()):
    """The ONLY constructor of an Authority value on the ordinary path. Requires an already-Authority
    origin; an Untrusted/Request value raises (there is NO implicit conversion, s0.2).
    Seeded defect M-A07 removes the guard (ordinary model-initiated promotion into authority)."""
    if "M-A07" in mutations:
        return x.value if isinstance(x, Tagged) else x
    if not isinstance(x, Tagged) or x.origin != AUTHORITY:
        raise AuthorityViolation(
            "cannot construct Authority from %s" % (x.origin if isinstance(x, Tagged) else type(x).__name__)
        )
    return x.value
