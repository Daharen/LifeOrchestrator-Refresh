# Module 21 -- Local Orchestrator / Agent core (`agent.local`)

**Status:** MVP complete · **Contract:** v0.2 · **determinism:** mixed · **parallel_safe:** false · **batch:** false

The local-orchestrator cost-offload keystone (Phase A #3, D-0029). Given a natural-language **goal**, a local
model plans and executes tool calls end-to-end -- **the frontier agent's tool loop, done locally** -- so
routine orchestration stops spending the scarce weekly frontier allotment. It is the tight, useful MVP slice
of the eventual `skill.orchestrator` (#26).

## What it does (the loop)

A bounded, ReAct-style loop. Per step:

1. **Decide the next action THROUGH the escalator (#19).** "Which tool next, or `finish`?" is posed to
   `logic.escalator` as a closed-set **`classify`** task whose labels are the registered tool names + `finish`.
   The escalator's deterministic **in-set gate** guarantees a valid action (or surfaces `needs_frontier`), and
   its tiny->weak->mid ladder is the cost-offload -- the cheapest sufficient tier makes the call.
2. **`finish`?** (or the `max_steps` budget is hit) -> generate the **final answer** via one `model.gateway`
   (#7) call over the goal + transcript, and stop.
3. Otherwise **generate the tool's arguments** via one `model.gateway` call (a JSON object; the registry
   supplies the tool's arg schema + an example to the prompt), parse the first JSON object, **invoke the tool**
   as a child skill (`-InputsJson`/`-ArtifactRoot`), and append a **bounded observation** to the transcript.

It **reimplements nothing**: the escalator, the gateway, and every tool are conforming skills spawned as child
pwsh processes whose `lifeorch.skill.result/0.1` envelopes are parsed -- the same pattern as `image.index`
(#18) and `voice.live` (#13).

## Tools (the capability surface)

Tools live in a **declarative closed registry** (`tools.json`; override with `-ToolsPath`/`-Tools`). The MVP
ships two -- both already built, both safe, neither GPU-bound:

| tool | skill | what | side effects |
|------|-------|------|--------------|
| `doc.io` | #20 | read / write / edit / append a text file | writes files |
| `fs.observer` | #2 | list / search a directory tree | read-only |

**The registry IS the sandbox.** There is deliberately **no arbitrary-shell / code-exec tool** -- the agent
can do only what its curated, conforming tools allow. Adding a tool is a registry edit (+ a test), not a code
change.

## Guardrails (first skill where a local model chooses side-effecting actions)

- **Hard `max_steps` budget** (default 4). Exhausting it stops with `status:"stopped"` + `needs_frontier:true`
  -- a runaway loop cannot occur.
- **`-DryRun` plan-preview.** Runs the decide + arg-generate steps and records the intended tool + args for each
  step **without invoking any tool** (no file is written) -- preview a side-effecting plan before it runs.
- **`needs_frontier` is a status field**, never a frontier call or a queue write. Set when a decision is
  low-confidence (below `frontier_threshold`) or the budget was exhausted.

## Not a review-queue producer

Like the orchestrators `voice.live` (#13), `image.index` (#18), and `logic.escalator` (#19), `agent.local`
**redirects every child's review writes** to an in-artifact `child_review.jsonl` and **never** writes the
canonical `review_queue.jsonl`. The review-queue producer set is unchanged (still seven).

## Inputs / outputs

See `skill.json` and `examples/example-invocation.md`. Result: `{goal, working_dir, status
(completed|stopped|error), final_answer, needs_frontier, stop_reason, step_count, max_steps, dry_run,
tools_available[], steps[], cost{}}`. Each step records the escalator `decision` (chosen_tool, confidence,
accepted_tier, needs_frontier), the generated `args`, the `tool` outcome, and a bounded `observation`.
`confidence` = the min per-step decision confidence; `model_provenance` = the stage-tagged aggregate of every
child decision / generation / tool call. Artifacts: `agent.json` (machine) + `agent.md` (human transcript) +
`child_review.jsonl` (redirect sink).

## Composition + cost

Per step: up to one escalator decision (a tiny->weak->mid ladder, one gateway call per tier) + one gateway
arg-generation call. Every gateway call is currently a **cold** model load (no warm worker -- D-0002), so a
multi-step goal does several loads and can take a minute or more. Keep `max_steps` small and prefer cheap
`decision_tiers` for routine work. A warm/persistent gateway worker is the shared follow-on that removes this
cost. No new model, no `models.json` change, no Module 7 re-verify (it composes the wired tiers).

## Files

- `Invoke-AgentLocal.ps1` -- the skill.
- `skill.json` / `tools.json` / `README.md` / `WORK_ORDER.md` / `examples/`.
- `tests/mock-child.ps1` -- a deterministic mock for the escalator / gateway / tools (branches on the
  `-ArtifactRoot` leaf).
- `tests/Invoke-AgentLocalTests.ps1` -- drives the **real** orchestrator against the mock (the off-GPU pre-ship
  gate; runs unchanged live via the executor).

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -Goal "Create hello.txt containing 'hi from agent.local'" -WorkingDir C:\Users\just_\scratch
# or wrapped: pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"goal":"...","working_dir":"C:\\Users\\just_\\scratch"}'
```

## Governor Phase 3 -- the auto-ramp controller (`-AutoRamp`, opt-in, OFF by default)

`-AutoRamp` (or `{"autoramp":true}` in `-InputsJson`) delegates to **`Invoke-AutoRamp.ps1`** -- the refined
**monotonic, model-affine epoch** controller (frontier second opinion, D-0058). The shipped floor loop above is
**byte-for-byte unchanged** when the switch is off. Each epoch runs **every** LLM call on **one** resident model
and the task **never de-escalates**:

- **M0 -- 3B floor:** decide `[mid]` as a **direct one-rung classify**, 768 tok, up to 6 steps.
- **M1 -- expanded mid:** the **same** 3B, one **fresh-context** retry (1536/1024 tok, +2 steps) rebuilt from
  `{goal, current authoritative state, completed actions + artifact ids, failed checks, tools}` -- *not* "judge
  the previous answer".
- **S0 -- 9B strong:** escalate the **whole epoch** to the resident 9B, decide `[strong]` as a **direct** classify
  (2048 tok). *(Live calibration D-0058: the 9B needs >=~1024 tok or it returns empty content; at S0 it decides
  6/6 vs the 3B's 4/6.)*

**Excluded from this Stage-1 slice:** X0/27B, logprobs/entropy, self-consistency, pattern-learning.

The **closing signal** is a caller-supplied **pre-frozen deterministic success contract**
(`lifeorch.goal_verification/0.1`), frozen by hash *before* execution; a tier is "good enough" **only** when the
same frozen contract passes -- never the model's own say-so. Predicate vocabulary: `file_exists`,
`artifact_exists`, `artifact_nonempty`, `sha256_equals_source`, `json_schema_valid`, `command_exit_zero`,
`state_version_changed`, `value_equals`, `all_required_tool_postconditions_passed`. With no contract the run
returns `completed_unverified`; with an un-checkable one, `human_verification_required`.

**Warm-server + lease composition:** it consumes the `model.gateway` (#7) resident warm server; `Ensure-ResidentModel`
matches the **whole** residency key (model_id + sha256 + engine build + gpu_layers + context + no_think + server
generation) and reuses **only** on an exact match, else it evicts + reloads. The **gpu lease is acquired once for
the whole ramped task** and renewed ~30 s (gateway calls re-attach under the same holder, so it is never released
mid-task). **Triggers:** hard failures (empty/malformed/out-of-set/length-truncated decision, finish-but-contract-fails,
repeat-identical-action-no-state-change, stale/wrong resident) escalate immediately to S0; a `>=2`-strike-in-3-steps
soft accumulator uses M1 once before the reload. A **task-scoped idempotency key** (hash of tool id + normalized args)
refuses exact-duplicate mutations and **resumes from the last authoritative state** across epochs (side-effects are
never repeated). It emits a machine-checkable **governor trace** (`governor-trace.json`).

```powershell
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -AutoRamp -InputsJson '{
  "goal":"Create ramp_ok.txt containing VERIFIED","working_dir":"C:\\Users\\just_\\scratch",
  "success_contract":{"schema":"lifeorch.goal_verification/0.1","predicates":[
    {"predicate":"file_exists","path":"C:\\Users\\just_\\scratch\\ramp_ok.txt"},
    {"predicate":"artifact_nonempty","path":"C:\\Users\\just_\\scratch\\ramp_ok.txt"}]}}'
# direct: pwsh -NoProfile -File .\Invoke-AutoRamp.ps1 -Goal "..." -WorkingDir ... -SuccessContract '{...}'
```

**Tests:** `tests/Invoke-AutoRampTests.ps1` -- a mock gateway (scripted decisions/args) + a mock tool (real
filesystem side effects) + the **real** `res.lease`; 11 scenarios / 50 assertions prove epoch monotonicity,
hard + soft triggers, frozen-contract gating, residency-key mismatch -> evict/reload, idempotency + resume, and the
`completed_unverified`/`human_verification_required` paths. Validated **live** on the warm server: a floor-solvable
goal completes at **M0** (no escalation); an engineered goal ramps **M0->M1->S0** with a real 3B->9B swap, and
**0 orphaned `llama-server`** after teardown. See D-0058 + `ADAPTIVE_RESOURCE_GOVERNOR.md`.

## Known follow-ons (NOT built here)

A warm/persistent gateway worker (shared with #7/#8/#12/#14/#16/#17/#19); richer planning (sub-goals,
reflection-retry, a planning DAG); more tools in the registry (perception / audio / generator Modules) with
per-tool arg schemas; a `route.tasks` (#24) drain of `needs_frontier` goals; registry auto-discovery from
module manifests; a `batch` multi-goal mode; parallel independent tool steps; calibrated decision confidence;
a persistent working-memory across invocations. See the WORK_ORDER and DECISION_LOG.
