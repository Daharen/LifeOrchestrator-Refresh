# Module 19 -- Local Logic Escalator (`logic.escalator`)

**Status:** MVP complete · **Contract:** v0.2 · **determinism:** mixed · **parallel_safe:** false · **batch:** true

The cost-offload keystone (Phase A #1, D-0029). It makes the *cheapest sufficient* local tier finish a task
end-to-end, spending a bigger model only when a smaller one is not good enough. It **composes `model.gateway`
(#7)** across its wired LLM tiers -- `tiny`=0.5B -> `weak`=1.5B -> `mid`=3B -> `strong`=27B -- and reimplements
no model plumbing (it spawns the gateway as a child and parses its `lifeorch.skill.result/0.1` envelope, the
same child-spawn pattern as `classify.batch` #8 and `review.processor` #9). It generalizes both #9 and
`route.tasks` (#24). Every task a low tier finishes correctly is a task the frontier allotment never pays for.

## The ladder

1. The **weakest tier answers** the task.
2. **Each higher tier judges** the current answer and either **ACCEPTs** it (stop -- the accepted layer is the
   tier that produced the current answer) or **REJECTs** it and **produces its own answer** for the next tier
   to judge.
3. It stops when a step up adds no substantial gain (a higher tier accepts the lower answer), which **fixes the
   accepted layer**. If the ladder is exhausted, the top tier's own answer is accepted.

## Deterministic ground-truth gates (guardrail 1)

The ladder **never rests on LLM-judges-LLM alone**. Every rung is anchored with a deterministic gate:

- **classify** (closed set): **in-set membership** (HARD) + **self-consistency** across K samples.
- **extract** (named fields): **JSON-schema validity** -- parseable + all required fields present (HARD) -- plus
  a **source-grounding / retrieval check** (each value must appear in the source text; soft signal).
- **generic** (freeform): no deterministic gate (`ungated`; lower confidence ceiling) + self-consistency only.

Two rules make the gate authoritative and defend against the *two-too-weak-tiers-rubber-stamp* failure mode:

- **A hard-fail overrides an LLM-judge ACCEPT.** An out-of-set label / invalid-schema extraction can never be
  accepted, no matter what a judge says -- so a weak judge cannot rubber-stamp a structurally-invalid answer.
- **Strong self-consistency + hard-pass short-circuits to ACCEPT with no judge call.** An easy task the tiny
  tier answers identically across K samples (and in-set) resolves at the tiny tier for free -- the cost saver.

The LLM judge only decides accept-vs-escalate **among deterministically-valid answers**.

## Not a review-queue producer

Like the orchestrators `voice.live` (#13) and `image.index` (#18), this skill **suppresses the child gateway's
own review writes** (to an in-artifact `_gateway_review_suppressed.jsonl`) and surfaces **`needs_frontier`** per
task as a status field in its own result. It **never** writes the canonical `review_queue.jsonl` and does not
extend `review.processor`'s queue writes. The review-queue producer set is unchanged (still seven).

## Inputs / outputs

See `skill.json` and `examples/example-invocation.md`. Result (per task): `accepted_tier`, `answer`,
`confidence` (a documented structural heuristic, NOT calibrated correctness), `needs_frontier`, `accepted_via`
(`consistency`|`judge`|`top`), `self_consistency`, `gate{hard_pass,grounded,reason}`, and the full `ladder`
trace; plus a batch `resolve_distribution` (accepted-layer histogram) and a `cost` aggregate.

## Empirical calibration (guardrail 2)

`tests/Invoke-EscalatorCalibration.ps1` runs the labeled `eval/classify-eval.json` (closed-set, known-correct
labels, deliberately mixing easy items with surface-word traps like *Jaguar / Mustang / hot dog / spider plant*)
through the ladder **live** and reports, with actual numbers: the **resolve-level distribution**, the
**accuracy** (vs known labels, with always-tiny and always-mid baselines), the **false-approval rate**
(low-tier acceptances that are confidently wrong), and the **cost** (mean gateway calls/item + a params_b-weighted
compute cost vs one always-strong call), plus whether accuracy reaches the ~95% target. See the committed
calibration report and `CURRENT_STATE.md` for the measured numbers.

## Files

- `Invoke-LogicEscalator.ps1` -- the skill.
- `skill.json` / `README.md` / `WORK_ORDER.md` / `examples/`.
- `eval/classify-eval.json` -- the labeled calibration set.
- `tests/mock-gateway.ps1` -- a deterministic mock `model.gateway` for off-GPU logic testing.
- `tests/Invoke-LogicEscalatorTests.ps1` -- dual-mode tests (mock scenarios always; `-Live` adds a real-gateway
  sanity check).
- `tests/Invoke-EscalatorCalibration.ps1` -- the live calibration harness.

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-LogicEscalator.ps1 -InputsJson '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid","strong"],"tasks":[{"id":"a","text":"a golden retriever puppy"}]}'
# or wrapped: pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'
```

## Known follow-ons (NOT built here)

A `unit_test`/code-execution deterministic gate; a retrieval/RAG gate over `artifact.search` (#23); a
warm/persistent gateway worker (shared with #7/#8/#12/#14/#16/#17); a `route.tasks` (#24) drain of
`needs_frontier` tasks; calibrated (logprob/conformal) confidence; per-task adaptive tier subsets; a cost-aware
early-stop policy tuned from the calibration data. See D-0030.
