# MODULE_WORK_ORDER: Local Logic Escalator (`logic.escalator`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md -> Build priority -> Phase A #1`

> Folder-number note: this is `modules/19-logic-escalator/`. The on-disk `NN-` prefix is a monotonic
> build-order counter (0, 00.1, 1..18, then 19); D-0029 severed it from the ARCHITECTURE_MAP's 0-49
> **architectural positions**. `logic.escalator` has no dedicated spine slot -- it generalizes
> `route.tasks` (#24) + `review.processor` (#9), pulled forward. The video block's "19 media.decompose"
> is an architectural label (deferred to Phase C) and will take its own next-free folder number when built.

## Problem being solved

The weekly frontier allotment is the scarce resource, and Modules 0-18 already give the machine a large
local-model toolkit. What is missing is the single highest-leverage cost-offload primitive: a way to make
the *cheapest sufficient* local tier finish a task end-to-end, and to only spend a bigger model when the
smaller one is not good enough. Today `classify.batch` (#8) always uses one weak tier, and `review.processor`
(#9) always uses one stronger tier on flagged items -- neither escalates a task through the tiers, and
neither decides "the smaller answer is already good enough, stop." The Local Logic Escalator closes that gap:
a task climbs an escalating ladder (tiny 0.5B -> weak 1.5B -> mid 3B -> strong 27B, all via `model.gateway`),
each higher tier judging the tier below and either accepting it or producing its own answer for the next tier
to judge, stopping when a step up adds no substantial gain -- which fixes the accepted layer. Every task a
low tier finishes correctly is a task the frontier never pays for.

## Immediate practical use

An agent (or a future Widget / local orchestrator) hands `logic.escalator` a batch of closed-set
classification or field-extraction tasks and gets back, per task, the accepted answer, which tier produced
it, a confidence, and a `needs_frontier` flag for the residue -- at a fraction of always-calling-the-strong-tier
cost. It is the routing/cost-offload engine the Phase-B Local Agent Console and the local orchestrator
(`agent.local`) will call for every sub-decision.

## Explicit scope (in)

- A **new** module that composes `model.gateway` (#7) across tiers. Reuses the child-spawn + envelope-parse
  scaffolding from `classify.batch` (#8) / `review.processor` (#9); **reimplements no model plumbing**.
- The **escalating ladder** mechanism: tier 0 answers; each higher tier judges the current answer and either
  ACCEPTs it (stop; accepted layer = the tier that produced the current answer) or REJECTs and produces its
  own answer for the next tier; the top tier's answer is accepted if reached.
- **Deterministic ground-truth gates that anchor every rung** (guardrail 1, D-0029): the ladder never rests
  on LLM-judges-LLM alone. Per task kind:
  - `classify` (closed set): **in-set membership** (hard gate) + **self-consistency** across K samples.
  - `extract` (named fields): **JSON schema validation** -- parseable + all required fields present (hard) --
    plus a **source-grounding / retrieval check** (each value is a normalized substring of the source; soft)
    + self-consistency.
  - `generic` (freeform): no deterministic gate (flagged `ungated`), self-consistency (exact-match) only.
  A **hard-fail is authoritative for REJECT** (overrides an LLM-judge ACCEPT -- the anti-rubber-stamp
  defense); **strong self-consistency + hard-pass is authoritative for ACCEPT** (deterministic short-circuit,
  no judge call -- the cost saver for easy tasks). The LLM judge decides accept-vs-escalate only among
  deterministically-valid answers.
- **Batch** input (`batch:true`): a set of tasks, ladder run per task.
- **Empirical calibration** (guardrail 2, D-0029): a small labeled eval set (`eval/classify-eval.json`,
  closed-set, known-correct labels) + a calibration harness (`tests/Invoke-EscalatorCalibration.ps1`) that
  runs it through the escalator **live via the executor** and measures the **resolve-level distribution**
  (accepted-tier histogram), the **accuracy** (vs known labels; with always-tiny and always-strong baselines),
  the **false-approval rate** (accepted-below-top answers that are wrong), and the **cost** (mean gateway
  calls/task + tokens vs one strong call). Reports actual numbers and whether it reaches the ~95% target;
  if it cannot, says so plainly.

## Non-goals (out -- do NOT build)

- **Not a review-queue producer.** It suppresses the child gateway's own review writes to an in-artifact file
  (like #8/#9) and surfaces `needs_frontier` per task as a *status field in its own result*; it does **not**
  write the canonical `review_queue.jsonl` and does **not** extend `review.processor`'s queue writes.
- No warm/persistent model worker (per-call gateway spawn, D-0002); a warm-worker pool is a shared follow-on.
- No new model, no `models.json` change, no Module 7 re-verify (it composes the four already-wired LLM tiers).
- No frontier call. `needs_frontier` is a status signal only (escalation-as-status-transition, per D-0018).
- No unit-test/code-execution gate in the MVP (the deterministic gates are in-set / schema / grounding /
  self-consistency -- the ones that apply to classify+extract; a code-`unit test` gate is a documented follow-on).
- Not a general workflow engine / router across tools (that is `route.tasks` #24 / `skill.orchestrator` #26).

## Dependencies

- Modules: **7 `model.gateway`** (spawned as a child; its `lifeorch.skill.result/0.1` envelope parsed).
  Optionally invoked by #8's callers later. · Tools/models: the four wired LLM tiers in `models.json`
  (`tiny`=0.5B, `weak`=1.5B, `mid`=3B, `strong`=27B). · Contract features: `-InputsJson`, `-ArtifactRoot`,
  `confidence`, `model_provenance`, `status`.

## Skill contract requirements

- `skill_id` `logic.escalator`, `name` "Local Logic Escalator", `version` `0.1.0`, `contract_version` `0.2`.
- `determinism` **mixed**, `parallel_safe` **false** (drives the gateway -> GPU/port), `batch` **true**,
  `streaming` **false**.
- `result` shape: per-task ladder records + resolve distribution + cost aggregate (see Inputs and outputs).
- `confidence` populated (mean per-task structural confidence); `model_provenance` populated (per-tier
  aggregate, stage-tagged by tier alias). Artifacts: `escalation.json` (machine) + `escalation.md` (human).

## Inputs and outputs

- **Inputs** (named params AND `-InputsJson`):
  - `kind` (`classify`|`extract`|`generic`, default `classify`), `tasks` (array) or `tasks_path` (file),
    shared `labels` / `fields` (per-task may override), `tiers` (ordered alias list, default
    `["tiny","weak","mid","strong"]`), `samples` K (self-consistency, default 1), `sample_temperature`
    (default 0.7), `accept_consistency` (short-circuit agreement, default 1.0), `frontier_threshold`
    (per-task confidence below which `needs_frontier`, default 0.5), `max_tokens`, `temperature` (greedy
    default 0.0), `seed`, `max_input_chars`; gateway plumbing `registry`, `gateway_path`, `pwsh_path`,
    `review_queue_path` (suppression sink override), `load_timeout_s` (raise for a cold strong tier).
  - Task objects: classify `{id?,text,labels?}`; extract `{id?,text,fields?}`; generic `{id?,prompt}`.
- **Outputs** (`result`): `{ kind, tiers, samples, count, resolved_count, needs_frontier_count,
  resolve_distribution:{<tier>:n}, cost:{total_gateway_calls,total_tokens,mean_calls_per_task}, tasks:[
  {id, kind, accepted_tier, accepted_tier_index, answer, confidence, needs_frontier, self_consistency,
  gate:{hard_pass,grounded,reason}, ladder:[{tier,tier_index,role,gateway_call_ok,verdict,produced_answer,
  samples,agreement,gate_pass,finish_reason,prompt_tokens,completion_tokens}], gateway_calls, tokens} ] }`.
  Artifacts `escalation.json` (kind json) + `escalation.md` (kind markdown).

## Artifact structure

- `runtime/artifacts/<invocation_id>/` -> `escalation.json`, `escalation.md`, `stderr.txt`,
  `_gateway_review_suppressed.jsonl` (the child gateway's suppressed review writes), `gateway/<child-inv>/...`
  (each gateway call's nested artifacts).

## Proposed implementation

- **Language:** PowerShell 7 (per policy: fastest useful MVP; owns the contract envelope; spawns the gateway
  child exactly as #8/#9 do). No Python worker (the gateway is the only external process).
- Reuse the proven helpers verbatim in spirit: `Has`, `Get-Sha256Hex`, `Get-NormToken`, `Get-FirstJsonObject`,
  `Resolve-RepoRoot`, the `Invoke-Gateway` child-spawn (`& $PwshPath @gwArgs 2> tmpErr`, parse stdout envelope,
  suppress gateway review writes), and the per-tier provenance aggregation.
- Per-kind **gate** functions: `Test-ClassifyGate` (in-set), `Test-ExtractGate` (JSON + fields + grounding),
  self-consistency = majority-vote agreement over K normalized samples.
- The **ladder** loop implements answer -> (deterministic short-circuit?) -> judge -> accept/produce, with the
  hard-fail-overrides-accept rule and the strong-consistency-short-circuit rule.

## External tools or models

- Only `model.gateway` + the four wired LLM tiers (already present -- `TOOL_MODEL_REGISTRY.md` / `models.json`).
  Nothing to install on Windows. Cloud box: pwsh 7.4.6 (for AST parse + the mock-gateway harness).

## Installation steps

- None on Windows (composes existing wired models). Cloud: install pwsh 7.4.6 (done) for the pre-ship gate.

## Tests

- **Direct / off-machine (cloud pre-ship gate):** `tests/Invoke-LogicEscalatorTests.ps1 -UseMock` drives the
  **real** escalator against `tests/mock-gateway.ps1` (a deterministic mock `model.gateway` keyed on the
  task-content markers + the answer/judge system prompt + the requested tier) so the ladder logic
  (short-circuit, escalation, deterministic-reject-override, needs_frontier, suppression, provenance,
  resolve-distribution, envelope validity, wrapper) runs off-GPU on Linux. AST-parse every `.ps1` first.
- **Through the executor (live):**
  - `le-test-001` -- the test harness live (mock parts + a minimal real-gateway ladder sanity on the small tiers).
  - `le-ladder-001` -- a real full `[tiny,weak,mid,strong]` ladder on 1-2 crafted hard tasks (strong engages;
    `-LoadTimeoutSec ~300` for the cold 27B).
  - `le-calib-001` -- `tests/Invoke-EscalatorCalibration.ps1` over `eval/classify-eval.json` (tiers
    `[tiny,weak,mid]`) -> the resolve-distribution / accuracy / false-approval / cost report.

## MVP acceptance criteria

- [ ] Manifest validates; flags `determinism=mixed`, `batch=true`, `parallel_safe=false`, `streaming=false`.
- [ ] The ladder escalates: a crafted item the low tier gets wrong (or out-of-set) is NOT accepted at that
      tier; a deterministic hard-fail overrides an LLM-judge ACCEPT (anti-rubber-stamp) -- proven in the mock.
- [ ] An easy, self-consistent, in-set item short-circuits at the lowest tier with no judge call (cost saver).
- [ ] `needs_frontier` is set (not a queue write) when even the top tier's answer hard-fails / is low-confidence.
- [ ] The canonical `review_queue.jsonl` is untouched (child gateway review writes suppressed).
- [ ] Envelope validates (`lifeorch.skill.result/0.1`); `confidence` in 0..1; per-tier `model_provenance`.
- [ ] Live: a real multi-tier ladder run resolves tasks across >=2 real tiers; the 27B strong tier engages once.
- [ ] Calibration reports **actual numbers**: resolve-distribution, accuracy (+ baselines), false-approval
      rate, and cost; states whether accuracy reaches ~95% (and if not, says so plainly).
- [ ] Module 1 wrapper runs it; no orphaned `llama-server`.

## Manual verification procedure

- Run `le-calib-001` via the executor; read `escalation-calibration.{json,md}`: confirm most easy tasks resolve
  low, the false-approval rate is reported, and the cost is < always-strong. Confirm `review_queue.jsonl`
  line-count is unchanged before/after.

## Documentation requirements

- Skill `README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json`.

## Registry updates

- `TOOL_MODEL_REGISTRY.md`: add the `logic.escalator` skill entry (composes the four wired LLM tiers; no new model).

## State updates

- `CURRENT_STATE.md` (active module -> done, tests, calibration numbers), `MODULE_ROADMAP.md` (Phase A #1 ->
  MVP complete + a per-module entry), `DECISION_LOG.md` (a new D-00xx), `REVIEW_QUEUE.md` (note: escalator is
  an orchestrator/non-producer that redirects child flags, like #13/#18).

## Known follow-on work (NOT this session)

- A `unit_test` / code-execution deterministic gate; a `retrieval`/RAG gate over `artifact.search` (#23);
  a warm/persistent gateway worker (shared with #7/#8/#12/#14/#16/#17); a `route.tasks` (#24) drain of
  `needs_frontier` tasks; calibrated (logprob / conformal) confidence; per-task adaptive tier subsets; a
  cost-aware early-stop policy tuned from the calibration data.

## STOP conditions

- Scope would exceed the "Explicit scope" list. A missing dependency is non-trivial to install. The contract
  lacks something (stop, propose the change, do not freelance). **MVP acceptance is met -- stop; do not start
  the next module.**
