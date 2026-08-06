"""
action_authz -- module #43 action.authz (P0-1 deterministic deny-by-default action reference monitor
+ adversarial injection SUITE; iteration 40 EXACT CLOSURES, worker P01-EXACT-CLOSURE-43-i40, extending
the i39 build 0.3.0 -> 0.4.0).

DESIGN-ONLY. This package authorizes NO execution and enables NO tool. `context_packet/0.2.non_execution`
remains true; check A06 deterministically DENYs every authentic packet. NOTHING is action-capable.

Built against the FROZEN core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its s6 amendments + the
i39 as-built RE-REVIEW (research/2026-08-06-i39-p01gate-recheck-redteam.md, D-0109), whose 7 per-finding
EXACT CLOSURES this version builds. Under mandate-02 M2-D (D-0110) the worker does NOT claim pass:
`p0_1_gate_status` stays `incomplete`; the per-finding `exact_closure_built` flags + the suite evidence
are the claim, and the orchestrator's independent as-built re-review PASS is the only ratification path.
STANDARD-LIBRARY ONLY; deterministic; integer-only JSON; byte-identical on re-run.
"""

VERSION = "0.4.0"

from . import canon, schemas, stores, monitor, boundary  # noqa: E402,F401
