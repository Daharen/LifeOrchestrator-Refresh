"""
p01gate.py -- an INDEPENDENT, blind second implementation of the canonical surface (contract Blocker 8 /
s8.7 crit 8; red-team Finding 7). It shares NO code with action_authz.canon: a hand-rolled recursive
canonical serializer + strict parser + SHA-256 digest + exact-membership ns predicate, written to the
same frozen spec (research/2026-08-05-i36-action-authz-freeze-frontier.md s0.3/s0.4/s0.6, s7 A5).

`run(check)` is the DIFFERENTIAL harness: over a corpus of vectors it asserts p01gate is BYTE-EQUIVALENT
to canon for canonical_bytes / digest_of / digest_omitting / canonical_action_digest, and AGREES on
accept/reject for strict_parse + ns_permitted. Agreement makes the single canonical implementation
independently checkable rather than merely self-consistent.
"""

import hashlib
import json as _json

from action_authz import canon  # imported ONLY to DIFFERENTIALLY COMPARE, never to reuse logic

PROVENANCE = {
    "impl": "p01gate (independent blind second implementation)",
    "shares_code_with_canon": False,
    "spec": "research/2026-08-05-i36-action-authz-freeze-frontier.md s0.3/s0.4/s0.6 + s7 A5",
    "surface": ["strict_parse", "canonical_bytes", "digest_of", "digest_omitting",
                "ns_permitted", "canonical_action_digest"],
}

_ESCAPE = {'"': '\\"', '\\': '\\\\', '\b': '\\b', '\f': '\\f', '\n': '\\n', '\r': '\\r', '\t': '\\t'}


class P01Error(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


# --- canonical serialize (independent recursive builder; NOT json.dumps) -------------------------
def _estr(s):
    buf = ['"']
    for ch in s:
        e = _ESCAPE.get(ch)
        if e is not None:
            buf.append(e)
        elif ord(ch) < 0x20:
            buf.append("\\u%04x" % ord(ch))
        else:
            buf.append(ch)
    buf.append('"')
    return "".join(buf)


def _ser(o):
    if isinstance(o, bool):
        return "true" if o else "false"
    if o is None:
        return "null"
    if isinstance(o, float):
        raise P01Error("float")
    if isinstance(o, int):
        return str(o)
    if isinstance(o, str):
        return _estr(o)
    if isinstance(o, (list, tuple)):
        return "[" + ",".join(_ser(x) for x in o) + "]"
    if isinstance(o, dict):
        parts = []
        for k in sorted(o.keys()):            # ascending Unicode code-point order
            if not isinstance(k, str):
                raise P01Error("nonstr_key")
            parts.append(_estr(k) + ":" + _ser(o[k]))
        return "{" + ",".join(parts) + "}"
    raise P01Error("type:" + type(o).__name__)


def canonical_bytes(o):
    return _ser(o).encode("utf-8") + b"\n"


def digest_of(o):
    return hashlib.sha256(canonical_bytes(o)).hexdigest()


def digest_omitting(o, field):
    return digest_of({k: v for k, v in o.items() if k != field})


# --- strict parse (independent; same s0.4 rules) -------------------------------------------------
def strict_parse(data, max_bytes):
    if not isinstance(data, (bytes, bytearray)):
        raise P01Error("not_bytes")
    if len(data) > max_bytes:
        raise P01Error("byte_limit")
    if data[:3] == b"\xef\xbb\xbf":
        raise P01Error("bom")
    try:
        text = bytes(data).decode("utf-8")
    except UnicodeDecodeError:
        raise P01Error("invalid_utf8")

    def _no_dup(pairs):
        seen = set()
        for k, _v in pairs:
            if k in seen:
                raise P01Error("duplicate_key")
            seen.add(k)
        return dict(pairs)

    def _nofloat(_s):
        raise P01Error("float")

    def _noconst(c):
        raise P01Error("nonfinite")

    try:
        obj = _json.loads(text, object_pairs_hook=_no_dup, parse_float=_nofloat, parse_constant=_noconst)
    except P01Error:
        raise
    except (ValueError, RecursionError):
        raise P01Error("json_parse")
    _limits(obj, 1)
    return obj


def _limits(o, depth):
    if depth > 16:
        raise P01Error("max_depth")
    if isinstance(o, dict):
        if len(o) > 1024:
            raise P01Error("max_members")
        for v in o.values():
            _limits(v, depth + 1)
    elif isinstance(o, list):
        if len(o) > 4096:
            raise P01Error("max_items")
        for v in o:
            _limits(v, depth + 1)


def ns_permitted(candidate, allowed):
    return candidate in frozenset(allowed)


# --- differential corpus + harness ---------------------------------------------------------------
def _corpus():
    return [
        {}, [], 0, 1, -7, "", "hello", "a\"b\\c/d", "tab\tnl\nlf\r", "unicode: é ü 漢字 🚀",
        "zero width\u200b\u0000tab", {"b": 1, "a": 2, "c": [3, 2, 1]},
        {"nested": {"z": [{"k": "v"}, {"k2": 2}], "a": None, "flag": True}},
        {"x": 9223372036854775807, "y": -9223372036854775808},
        [{"o": i, "s": "s%d" % i} for i in range(5)],
        {"schema": "lifeorch.canonical_action/0.1", "tool_id": "fs.local",
         "operation": "fs.write", "canonical_arguments": {"path": "/u/data/projA/one.txt", "content": "é"},
         "resolved_target_set": [{"target_kind": "fs.file", "canonical_target_id": "/u/data/projA/one.txt",
                                  "namespace": "projA"}],
         "derived_effect_set": [{"effect_class": "fs.write", "quantity": 5}],
         "action_namespace": "projA", "risk_class": 2, "limits": [{"limit_id": "fs.write", "max_value": 3}]},
    ]


def _parse_vectors():
    return [b'{"a":1}', b'{"a":1,"a":2}', b'{"x":1.5}', b'{"n":NaN}', b'[1,2,3]',
            b'\xef\xbb\xbf{"a":1}', b'{"k":"\xff"}', b'not json', b'{"u":"\\u00e9"}',
            b'{"deep":' + b'[' * 20 + b']' * 20 + b'}']


def run(check):
    diffs = 0
    n = 0
    for o in _corpus():
        n += 1
        a = canonical_bytes(o)
        b = canon.canonical_bytes(o)
        if a != b:
            diffs += 1
            check.ok("p01gate canonical_bytes == canon [vec %d]" % n, False,
                     "p01=%r canon=%r" % (a[:40], b[:40]))
        if digest_of(o) != canon.digest_of(o):
            diffs += 1
            check.ok("p01gate digest_of == canon [vec %d]" % n, False)
    check.ok("p01gate canonical_bytes/digest byte-equivalent to canon over corpus (%d vectors)" % n,
             diffs == 0, "diffs=%d" % diffs)

    # digest_omitting on a self-hashing object
    obj = {"a": 1, "b": 2, "self": "x"}
    check.ok("p01gate digest_omitting == canon", digest_omitting(obj, "self") == canon.digest_omitting(obj, "self"))

    # canonical_action_digest: same closed view -> same digest via both impls
    from action_authz.monitor import canonical_digest
    ca = _corpus()[-1]
    check.ok("p01gate agrees on canonical_action_digest", digest_of(ca) == canonical_digest(ca))

    # strict_parse: identical accept/reject decisions; when both accept, identical canonical bytes
    pmismatch = 0
    for v in _parse_vectors():
        try:
            pa = strict_parse(v, canon.PROPOSAL_MAX_BYTES)
            ea = None
        except P01Error as e:
            pa, ea = None, e.reason
        try:
            cb = canon.strict_parse(v, canon.PROPOSAL_MAX_BYTES)
            ec = None
        except canon.CanonError as e:
            cb, ec = None, e.reason
        both_reject = (ea is not None) and (ec is not None)
        both_accept = (ea is None) and (ec is None)
        if not (both_reject or both_accept):
            pmismatch += 1
        elif both_accept and canonical_bytes(pa) != canon.canonical_bytes(cb):
            pmismatch += 1
    check.ok("p01gate strict_parse agrees with canon on accept/reject + bytes (%d vectors)"
             % len(_parse_vectors()), pmismatch == 0, "mismatch=%d" % pmismatch)

    # ns_permitted: exact membership agreement (no wildcard/prefix/parent/all)
    ns_cases = [("projA", ["projA"]), ("projA.sub", ["projA"]), ("x", []), ("a", ["a", "b"]),
                ("projB", ["projA"]), ("*", ["projA"])]
    ns_ok = all(ns_permitted(c, a) == canon.ns_permitted(c, a) for c, a in ns_cases)
    check.ok("p01gate ns_permitted == canon (exact membership, no widening)", ns_ok)

    return {"provenance": PROVENANCE, "corpus_vectors": n, "byte_equivalent": diffs == 0}
