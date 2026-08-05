"""
action_authz -- module #43 action.authz (P0-1 deterministic deny-by-default action reference monitor
+ adversarial injection SUITE, MVP; iteration 37, worker P01-AUTHZ-SUITE-i37).

DESIGN-ONLY. This package authorizes NO execution and enables NO tool. `context_packet/0.2.non_execution`
remains true; check A06 deterministically DENYs every authentic packet. NOTHING is action-capable.

Built against the FROZEN core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its pinned normative
source research/2026-08-05-i36-action-authz-freeze-frontier.md. STANDARD-LIBRARY ONLY; deterministic;
integer-only JSON; byte-identical on re-run.
"""

VERSION = "0.1.0"

from . import canon, schemas, stores, monitor, boundary  # noqa: E402,F401
