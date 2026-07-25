# logic.escalator -- calibration results (measured, via the executor)

The Local Logic Escalator was **empirically calibrated** (D-0029 guardrail 2), not assumed. Two labeled
closed-set classification evals were run through the ladder **live** on the executor (real `model.gateway`
tiers), measuring the resolve-level distribution, accuracy (vs known labels, with always-tiny / always-mid
baselines), the false-approval rate, and cost. Reports live under `runtime/calibration/` (JSON + markdown).
Cost is a `params_b`-weighted compute proxy (tiny 0.5, weak 1.5, mid 3, strong 27; no warm worker, so each
gateway call reloads its model).

## Eval A -- "easy" set (N=12; `m19-calib-002`)

Short items with explicit disambiguating context (e.g. "a Jaguar F-Type **sports car** roaring down the
motorway"). Even the 0.5B tier handles these.

| config | accuracy | resolve dist | false-approval | mean calls/item | weighted cost/item | vs always-strong |
|--------|----------|--------------|----------------|-----------------|--------------------|------------------|
| ladder tiny->weak->mid (K=1) | **1.00** | tiny 11, weak 1 | 0.00 | 2.08 | 2.25 | **-91.7%** |
| ladder tiny->weak->mid->strong (K=1) | **1.00** | tiny 11, weak 1 | 0.00 | 2.08 | 2.25 | -91.7% |
| baseline always-tiny | 1.00 | -- | -- | 1.00 | 0.5 | -- |
| baseline always-mid | 1.00 | -- | -- | 1.00 | 3.0 | -- |

**Reads:** the ladder resolves ~92% of items at the tiny (0.5B) tier and reaches 100% accuracy at **8% of the
cost** of always calling the strong (27B) tier. The strong tier never engages (nothing escalated that far).
This is the cost-offload win -- but the eval is too easy to stress escalation or false approval.

## Eval B -- "hard" gradient set (N=14; `m19-calib-003`)

Adds named + obscure entities the 0.5B is likely to miss (Clydesdale, Cessna, Wagyu, Stratocaster, quokka,
funicular, Roquefort, hurdy-gurdy). This is the eval that actually exercises the ladder.

| config | accuracy | resolve dist | false-approval | needs_frontier | weighted cost/item | vs always-strong |
|--------|----------|--------------|----------------|----------------|--------------------|------------------|
| ladder tiny->weak->mid (K=1) | **0.786** | tiny 10, mid 4 | **0.20** (2/10) | 0 | 2.86 | -89.4% |
| ladder tiny->weak->mid->strong (K=1) | **0.571** | tiny 10, strong 4 | 0.20 (2/10) | 4 (0.29) | 18.29 | -32.3% |
| baseline always-tiny | 0.714 | -- | -- | -- | 0.5 | -- |
| baseline always-mid | **0.929** | -- | -- | -- | 3.0 | -- |

**Does it reach the ~95% target? No.** Plainly: the naive K=1 ladder reaches **78.6%** (3-tier) / **57.1%**
(4-tier) on the hard eval -- below 95%, and below the always-mid baseline (92.9%). Three measured reasons,
each pointing at a concrete follow-on:

1. **The weak judge rubber-stamps in-set-but-wrong tiny answers (false-approval 0.20).** The deterministic
   in-set gate cannot catch a wrong-but-in-set label (e13 Roquefort -> "vehicle"; e14 hurdy-gurdy ->
   "vehicle"), and the weak (1.5B) judge accepted both at the tiny tier -- confidently wrong, not flagged.
   This is exactly the two-too-weak-tiers rubber-stamp failure D-0029 predicted. **Mitigation (follow-on):** a
   self-consistency *veto* (low agreement across K samples forces escalation / flags, instead of only gating
   the short-circuit) + more skeptical judge prompts; K>1 was implemented and unit-tested but not calibrated.

2. **The 27B strong tier emits EMPTY verdicts at the MVP token caps (4/4 escalated items).** With the
   classify answer/judge caps (24 / 96 tokens), the thinking-style Qwen3.5-27B spends its budget reasoning and
   returns nothing parseable -> the escalator's empty-answer gate correctly hard-fails it -> `needs_frontier`
   (so these degrade to *flagged residue*, NOT false approvals -- the system fails safe). But it means the
   4-tier ladder is both **less accurate and far more expensive** than the 3-tier. This is the D-0018
   strong-tier-parseability issue, now confirmed for the escalator. **Mitigation (follow-on):** raise the
   strong-tier `max_tokens` and/or add a no-reasoning directive so the 27B returns a parseable verdict.

3. **On genuinely hard items the ladder currently underperforms just always using `mid` (92.9%).** Because
   too many items resolve at the tiny tier behind a rubber-stamping judge. **Mitigation (follow-on):** a
   higher floor (start at weak/mid), a cost-aware early-stop policy tuned from this calibration data, or the
   self-consistency veto above.

**What the calibration confirms works:** the deterministic gates fire correctly (empty/out-of-set answers are
hard-failed and flagged, never confidently approved -- see the 4 `needs_frontier` items); the ladder is a
large cost win when the cheap tiers suffice (Eval A: -91.7%); and the escalator degrades *safely* (wrong
strong-tier outputs become flagged residue, not silent errors). The gap to 95% is a **tuning/hardening**
problem with a measured, prioritized follow-on list -- exactly what running the experiment (rather than
assuming) was meant to surface.

_Numbers above are from the committed executor runs `m19-calib-002` (Eval A) and `m19-calib-003` (Eval B);
full per-item tables are in each run's `escalation-calibration.md`._
