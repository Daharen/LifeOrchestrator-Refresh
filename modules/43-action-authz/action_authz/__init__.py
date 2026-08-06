"""
action_authz -- module #43 action.authz (P0-1 deterministic deny-by-default action reference monitor
+ adversarial injection SUITE; iteration 38 FULL GATE, worker P01-GATE-FULL-i38, extending the i37 MVP).

DESIGN-ONLY. This package authorizes NO execution and enables NO tool. `context_packet/0.2.non_execution`
remains true; check A06 deterministically DENYs every authentic packet. NOTHING is action-capable.

Built against the FROZEN core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its 7 i38 red-team
amendments (s6) + its pinned normative source research/2026-08-05-i36-action-authz-freeze-frontier.md.
STANDARD-LIBRARY ONLY; deterministic; integer-only JSON; byte-identical on re-run.
"""

VERSION = "0.3.0"

from . import canon, schemas, stores, monitor, boundary  # noqa: E402,F401
