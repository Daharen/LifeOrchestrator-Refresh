"""
action_authz -- module #43 action.authz (P0-1 deterministic deny-by-default action reference monitor
+ adversarial injection SUITE; iteration 42 ROUND-4 EXACT CLOSURES, worker P01-R4-CLOSURE-43-i42,
extending the i41 build 0.5.0 -> 0.6.0).

DESIGN-ONLY. This package authorizes NO execution and enables NO tool. `context_packet/0.2.non_execution`
remains true; check A06 deterministically DENYs every authentic packet. NOTHING is action-capable.

Built against the FROZEN core-docs/ACTION_AUTHORIZATION_CONTRACT.md (D-0103) + its s6 amendments. This
version builds the 3 WORKER-SIDE EXACT CLOSURES from the ROUND-4 ratification review
(research/2026-08-07-i41-p01gate-round4-redteam.md, D-0116): F5 REAL-SEAM losslessness (build_trusted()
begins with adapt_packet_lossless() and binds the whole-packet identity into trusted state), F4 grant
PRE-VALIDATION before any operational read (one shared validated-grant iterator used by grant_namespaces()
AND match(); the A11 KeyError path dies), F2 HANDLE-BOUND ledger provenance (the mock applicator consumes
the handle + operation semantics and RETURNS the effect atoms; authorized_effect_set becomes an
authorization bound; the consume-but-discard successor mutant M-E38 is killed) -- on top of the 7 D-0109
exact closures + the 4 D-0113 round-3 closures (which ALL remain built; no regression). Under mandate-02
M2-D (D-0110) the worker does NOT claim pass: `p0_1_gate_status` stays `incomplete`; the per-finding
`exact_closure_built` + `round3_closure_built` + `round4_closure_built` flags + the suite evidence are the
claim, and the orchestrator's independent round-5 re-review PASS is the only ratification path.
STANDARD-LIBRARY ONLY; deterministic; integer-only JSON; byte-identical on re-run.
"""

VERSION = "0.6.0"

from . import canon, schemas, stores, monitor, boundary  # noqa: E402,F401
