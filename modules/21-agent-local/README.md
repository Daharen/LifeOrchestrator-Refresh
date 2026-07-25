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

## Known follow-ons (NOT built here)

A warm/persistent gateway worker (shared with #7/#8/#12/#14/#16/#17/#19); richer planning (sub-goals,
reflection-retry, a planning DAG); more tools in the registry (perception / audio / generator Modules) with
per-tool arg schemas; a `route.tasks` (#24) drain of `needs_frontier` goals; registry auto-discovery from
module manifests; a `batch` multi-goal mode; parallel independent tool steps; calibrated decision confidence;
a persistent working-memory across invocations. See the WORK_ORDER and DECISION_LOG.
