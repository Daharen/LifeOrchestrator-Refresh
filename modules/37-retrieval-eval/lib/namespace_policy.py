#!/usr/bin/env python3
# namespace_policy.py -- the ONE canonical namespace predicate + sanitized rejection policy for the memory
# substrate (Life Orchestrator module 37 `retrieval.eval`; MEMORY_CONTRACT Amendment A5 [D-0096] U1' + risk-6;
# CONTEXT_PACKET_CONTRACT i33 amendment U1'). PURE + DETERMINISTIC: no model, no I/O, no network, no
# wall-clock, no randomness, no global state.
#
# WHY THIS FILE EXISTS (A5 risk-6, red-team pack 159e9cb5). namespace is an END-TO-END information-flow
# boundary, not a soft rank bonus and not merely an envelope filter. THREE enforcement layers -- the retriever
# (#36), the selection policy (#37/selpol), and the context compiler (#40) -- MUST make the byte-identical
# accept/reject decision, or a permitted-envelope summary / node / aggregate / diagnostic / omission entry can
# still disclose forbidden-namespace information even when `evidence[]` is clean. This module is the ONE owner
# of that decision: #40 IMPORTS it, #36's retriever implements the IDENTICAL predicate, and the D-0077 fold
# asserts byte-identical accept/reject across all three. It is NEVER re-implemented per module.
#
# CLOSED-SET SEMANTICS (no widening, ever). Membership is EXACT-STRING only. There is NO wildcard, prefix,
# parent, child, sibling, shared, or implicit `all` namespace. `effective_allowed` is a CALLER-SUPPLIED closed
# set: the compiler computes it as `effective_allowed_namespaces(request, grant) = intersection(REQUEST, GRANT)`
# (task_input.namespace is a REQUEST, never authorization; the control_plane grant is the authority; neither can
# widen the other). An EMPTY effective set permits NOTHING (fail-closed -> zero hits). A `None` effective set is
# the UNSCOPED sentinel: the predicate treats it as "permit nothing"; the caller's "no closure requested"
# back-compat path is a SEPARATE caller decision that BYPASSES this predicate (it is never a value this
# predicate invents).
#
# SANITIZATION (A5 U1'd). A cross-namespace rejection leaves NO identifying metadata in any caller-visible
# output. The only caller-visible surface is an integer `namespace_violation_count` + a fail-closed flag; the
# identifying detail (namespace, ids, paths, snippets) is accumulated SEPARATELY for a PRIVILEGED LOCAL security
# log and MUST NOT reach a packet / caller. `NamespaceRejectionPolicy` is that accumulator.

NS_POLICY_ID = "ns_closed_v1"
NS_POLICY_VERSION = "1.0.0"


def normalize_allowed(allowed):
    """Normalize a caller-supplied allowed set into a `frozenset` of EXACT namespace strings, or `None`.

    - `None` -> `None` (the UNSCOPED sentinel; the predicate treats it as "permit nothing").
    - a `str` -> a singleton frozenset (a single namespace).
    - any iterable -> a frozenset of its members coerced to `str` (a `None` member is dropped -- it is not a
      real namespace; an EMPTY input stays empty -> fail-closed).

    No expansion of any kind. Pure."""
    if allowed is None:
        return None
    if isinstance(allowed, str):
        return frozenset([allowed])
    return frozenset(str(x) for x in allowed if x is not None)


def effective_allowed_namespaces(request, grant):
    """The ONE canonical scope computation (A5 U1'e): the effective closed set = intersection(REQUEST, GRANT).

    `request` (from `task_input.namespace`) is what the task ASKS FOR; `grant` (from
    `control_plane.permission_grants`) is what it is AUTHORIZED for. task_input.namespace is a REQUEST, NOT
    authorization -- it can never WIDEN scope (reconciles P0-1). Returns a `frozenset` (never `None`):
      - a `None`/absent request OR grant is treated as the EMPTY set (a missing grant grants nothing; a missing
        request requests nothing) -- there is NO implicit `all`;
      - an empty request, empty grant, or empty intersection => the EMPTY set (fail-closed: zero hits).
    Pure + deterministic."""
    req = normalize_allowed(request)
    grt = normalize_allowed(grant)
    if req is None or grt is None:
        return frozenset()
    return frozenset(req & grt)


def ns_permitted(candidate_namespace, effective_allowed):
    """The ONE canonical namespace predicate. Returns `True` IFF `candidate_namespace` is EXACTLY a member of
    the caller-supplied closed set `effective_allowed`.

    - `effective_allowed` may be a set/frozenset/list/str (normalized here) or `None`.
    - `None` or an EMPTY set permits NOTHING (fail-closed) -> always `False`.
    - a candidate with NO namespace (`None`) can never be proven in-scope -> `False` (fail-closed).
    - NO wildcard / prefix / parent / child / shared / `all` expansion -- exact membership only.

    Pure + deterministic; the byte-identical decision #36 / #37 / #40 all make."""
    if effective_allowed is None:
        return False
    allowed = effective_allowed if isinstance(effective_allowed, (set, frozenset)) else normalize_allowed(effective_allowed)
    if not allowed:
        return False
    if candidate_namespace is None:
        return False
    return str(candidate_namespace) in allowed


class NamespaceRejectionPolicy:
    """The sanitized rejection/sanitization policy (A5 U1'd). An ACCUMULATOR whose caller-visible surface is
    ONLY an integer count + a fail-closed flag, while the identifying detail is captured for a PRIVILEGED LOCAL
    security log and MUST NOT reach a packet / caller.

    - `violation_count` -- the ONLY caller-visible signal (an int).
    - `security_log`     -- privileged records (namespace, ids, paths, the effective set, stage). NEVER returned
                            to a caller / placed in a packet; the caller routes it to a privileged local sink.
    - `reject(...)`      -- record ONE cross-namespace rejection.
    - `caller_summary()` -- the sanitized surface: `{namespace_violation_count, namespace_closure_violated}`.

    Deterministic: a pure accumulator (no I/O); the sequence of `reject()` calls fully determines its state."""
    __slots__ = ("violation_count", "security_log")

    def __init__(self):
        self.violation_count = 0
        self.security_log = []  # privileged; NEVER returned to a caller / placed in a packet

    def reject(self, candidate, effective_allowed=None, stage="selection"):
        """Record ONE cross-namespace rejection. Increments the caller-visible count and appends the FULL
        identifying detail (privileged) to `security_log`. `candidate` may be a hit dict or any value."""
        self.violation_count += 1
        if isinstance(candidate, dict):
            detail = {
                "namespace": candidate.get("namespace"),
                "record_id": candidate.get("record_id"),
                "record_version_id": candidate.get("record_version_id"),
                "source_path": candidate.get("source_path"),
            }
        else:
            detail = {"namespace": None, "value": str(candidate)}
        detail["stage"] = stage
        detail["reason_code"] = "namespace_closure_violation"
        allowed = effective_allowed if isinstance(effective_allowed, (set, frozenset)) else normalize_allowed(effective_allowed)
        detail["effective_allowed"] = sorted(allowed) if allowed else []
        self.security_log.append(detail)

    def caller_summary(self):
        """The ONLY caller-visible surface -- the count + the fail-closed flag; NO identifying detail."""
        return {
            "namespace_violation_count": self.violation_count,
            "namespace_closure_violated": self.violation_count > 0,
        }
