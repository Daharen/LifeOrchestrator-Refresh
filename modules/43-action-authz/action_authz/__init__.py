"""
action_authz -- module #43 action.authz (P0-1 deterministic deny-by-default action reference monitor
+ adversarial injection SUITE; iteration 41 ROUND-3 EXACT CLOSURES, worker P01-R3-CLOSURE-43-i41,
extending the i40 build 0.4.0 -> 0.5.0).

DESIGN-ONLY. This package authorizes NO execution and enables NO tool. `context_packet/0.2.non_execution`
remains true; check A06 deterministically DENYs every authentic packet. NOTHING is action-capable.

Built against the FROZEN core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its s6 amendments. This
version builds the 4 WORKER-SIDE EXACT CLOSURES from the ROUND-3 ratification review
(research/2026-08-06-i40-p01gate-round3-redteam.md, D-0113): F1 write-once immutable completion binding,
F2 consumed TargetHandle on the effect path, F4 operational top-level GrantView enforcement, F5 lossless
context_packet/0.2 adapter -- on top of the 7 D-0109 exact closures (which ALL remain built). Under
mandate-02 M2-D (D-0110) the worker does NOT claim pass: `p0_1_gate_status` stays `incomplete`; the
per-finding `exact_closure_built` + `round3_closure_built` flags + the suite evidence are the claim, and
the orchestrator's independent round-4 re-review PASS is the only ratification path.
STANDARD-LIBRARY ONLY; deterministic; integer-only JSON; byte-identical on re-run.
"""

VERSION = "0.5.0"

from . import canon, schemas, stores, monitor, boundary  # noqa: E402,F401
