# AUDIT_PIPELINE (fixture) -- design TARGET, staged

**Status:** ADOPTED governing target doc (fixture stand-in).

**Cadence header (orchestrator maintains by replacement -- the PROCESS_MANDATE countdown pattern):**
- `last_reviewed: i45`
- `review_due: i54`
- `current_tier: A1 + read-only A2 + LRAP v1`
- `next_increment (D-0127): FRONTSTEP-SENTINEL -- the raw-prompt FRONT step; then the LIVE ride-along; then the OUTPUT side. Each design-first -> red-team-gated`

## 0. Purpose

Fixture purpose body.

## 5. Cadence + upkeep (how this stays alive without becoming a tax)

1. At every wave scoping: is review_due reached? CADENCE-S5-SENTINEL.
2. When due or triggered: update the cadence header + next_increment BY REPLACEMENT.

## 6. Anti-spiral guardrails (carried from the packet; binding)

Non-displacement; read-only by default; GUARDRAIL-S6-SENTINEL: every increment through A2 is a
reader; anything that pauses or enters the pipeline (A3+) is design-first + red-team-gated.
