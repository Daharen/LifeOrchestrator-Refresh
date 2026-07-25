# MODULE_WORK_ORDER: Local Orchestrator / Agent core (`agent.local`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md -> Build priority -> Phase A #3`

> Folder-number note: this is `modules/21-agent-local/`. The on-disk `NN-` prefix is a monotonic
> build-order counter (0, 00.1, 1..20, then 21); D-0029 severed it from the ARCHITECTURE_MAP's 0-49
> **architectural positions**. `agent.local` is a **scoped Module #26** (`skill.orchestrator`) pulled
> forward as Phase-A #3 -- the local-orchestrator cost-offload keystone -- not the video-block "21".

## Problem being solved

Modules 0-20 give the machine a large local toolkit (perception, audio, doc I/O) plus the two cost-offload
keystones: `logic.escalator` (#19, the tiered decision ladder) and `doc.io` (#20, the local Read/Write/Edit
primitive). What is still missing is the thing that **drives** them without the frontier agent in the loop: a
**local agent** that, given a goal in plain language, decides which Module to call, with what arguments,
observes the result, and repeats until the goal is done. Today every such loop -- "read this file, summarize
it, write the summary next to it" -- is run by the frontier agent, spending the scarce weekly allotment on
orchestration a local model can do. `agent.local` closes that gap: it is the frontier agent's tool loop, done
locally. Every goal a local agent finishes end-to-end is orchestration the frontier never pays for.

## Immediate practical use

A caller (an unattended executor task, a future Phase-B Widget -- the Local Agent Console -- or the frontier
agent delegating a chore) hands `agent.local` a one-line goal plus, optionally, a working directory, and gets
back a completed task: the files written/edited, a final answer, and a full step-by-step trace of which tool
ran with which arguments and what it returned. This week that means goals like *"read `notes.md` and write its
line count to `stats.txt`"*, *"create `hello.txt` containing <text>"*, or *"list the `.md` files under this
folder and write their names to `index.txt`"* -- run entirely by local models through the escalator + gateway
+ `doc.io`/`fs.observer`, with the frontier only consulted (via a surfaced `needs_frontier` flag) when the
local ladder is not confident enough.

## Explicit scope (in)

- A **new orchestrator** Module that **composes `logic.escalator` (#19) + `model.gateway` (#7)** and **invokes
  other conforming Modules as child skills** -- reusing the proven child-spawn + envelope-parse scaffolding from
  `image.index` (#18) / `voice.live` (#13). **Reimplements no model plumbing and no tool logic.**
- A **bounded ReAct-style agent loop**. Per step:
  1. **Decide the next action through the escalator** (guardrail: the decision is anchored by a deterministic
     gate). The action is chosen from a **closed set** = the registered tool names + the terminal `finish`.
     This is framed as a `logic.escalator` **`classify`** task (`labels` = tools + `finish`), so the escalator's
     **in-set membership gate** guarantees a valid action (or surfaces `needs_frontier`), and the tiny->weak->mid
     ladder does the cost-offload. The escalator's own `needs_frontier` flows straight through.
  2. If the action is `finish` (or the step budget is hit): **generate the final answer** via one `model.gateway`
     call over the goal + the step transcript, and stop.
  3. Otherwise **generate the chosen tool's arguments** via one `model.gateway` call (a small JSON object keyed
     by the tool's declared inputs; the tool registry supplies the schema + an example to the prompt), parse the
     first JSON object from the completion, then **invoke the tool** as a child skill (`-InputsJson`/`-ArtifactRoot`),
     parse its `lifeorch.skill.result/0.1` envelope, and append a **bounded observation** to the transcript.
- A **declarative, closed tool registry** (`tools.json` in the module dir; overridable via `-ToolsPath`/`-Tools`).
  Each entry: `tool` (the action label), `skill_id`, `entrypoint` (repo-relative), `description`, `args_hint`,
  `args_example`, `required` (input names), and `side_effecting` (bool). **The MVP ships exactly two tools --
  `doc.io` (#20) and `fs.observer` (#2)** -- both already built, both non-GPU, deterministic, and safe (one
  read-only observer + one file primitive whose writes ARE the point of "do real work"). The registry is the
  agent's entire capability surface; extending it (later) extends the agent without code change.
- **Tight-scoping guardrails** (this is the first skill where a *local model chooses side-effecting actions*):
  - **Hard `max_steps` budget** (default 4) -- a runaway loop cannot occur; exhausting it stops with
    `status:"stopped"` + `needs_frontier:true`.
  - **`-DryRun` plan-preview** -- run the decide+arg-generate steps and record the intended tool+args for each
    step **without invoking any tool** (so a human/caller can preview a side-effecting plan before it runs).
  - **The registry is the sandbox** -- there is **no arbitrary-shell / code-exec tool** in the MVP; the agent
    can do only what its (curated, conforming) tools allow.
- **Orchestrator, NOT a review-queue producer** (like #13/#18/#19): it **redirects/suppresses** every child's
  review writes to an in-artifact sink (`child_review.jsonl`) and surfaces **`needs_frontier`** in its own
  result. It **never** writes the canonical `review_queue.jsonl`; the seven-producer set is unchanged.
- **Contract-clean envelope**: `determinism:"mixed"`, one `lifeorch.skill.result/0.1` to stdout, per-step trace
  + aggregated stage-tagged `model_provenance`, `confidence` = the weakest-link decision confidence.

## Non-goals (out -- do NOT build)

- **No new model, no `models.json` change, no Module 7 re-verify** (it composes the four already-wired LLM tiers
  via the escalator/gateway).
- **No warm/persistent model worker.** Per-call gateway spawn (D-0002); a warm pool is a shared follow-on. The
  throughput caveat (many cold model loads per multi-step goal) is documented, not fixed here.
- **No arbitrary-shell / arbitrary-code tool**, no network tool, no self-modification -- the MVP tool set is
  `doc.io` + `fs.observer` only. Adding tools is a registry edit + a test, a later increment.
- **No multi-goal batch** (`batch:false`, one goal per invocation), no parallel tool execution, no streaming.
- **No planning DAG / sub-agents / reflection-retry beyond a single re-ask on a bad arg parse.** The MVP is a
  linear bounded loop; richer planning is a documented follow-on.
- **No frontier call.** `needs_frontier` is a status signal only (escalation-as-status-transition, D-0018).
- Not a general skill-composition workflow engine across all Modules (that is the full `skill.orchestrator` #26)
  and not the task router (`route.tasks` #24). This is the tight, useful MVP slice of #26.

## Dependencies

- Modules: **19 `logic.escalator`** (decision ladder; spawned child, envelope parsed), **7 `model.gateway`**
  (arg-gen + final answer; spawned child), and the **registered tools** -- **20 `doc.io`**, **2 `fs.observer`**
  (spawned children). All present and MVP-complete.
- Tools/models: the four wired LLM tiers in `models.json` (`tiny`/`weak`/`mid`/`strong`) via the escalator/gateway.
- Contract features: `-InputsJson`, `-ArtifactRoot`, `-InvocationId`, `status`, `confidence`, `model_provenance`,
  the child `review_queue_path` redirect (escalator + gateway accept it).

## Skill contract requirements

- `skill_id` `agent.local`, `name` "Local Orchestrator / Agent", `version` `0.1.0`, `contract_version` `0.2`.
- `determinism` **mixed**, `parallel_safe` **false** (drives the gateway -> GPU/port and can invoke `doc.io`
  file mutations), `batch` **false**, `streaming` **false**.
- `result` shape: `{goal, working_dir, status, final_answer, needs_frontier, step_count, max_steps, dry_run,
  tools_available[], steps[], cost{}}` (see Inputs and outputs). `confidence` = min per-step decision confidence
  (null if no decision ran); `model_provenance` = aggregate of all child decisions/gen calls, stage-tagged.
  Artifacts: `agent.json` (machine) + `agent.md` (human transcript) + `child_review.jsonl` (redirect sink).

## Inputs and outputs

- **Inputs** (named params AND `-InputsJson`):
  - `goal` (string, **required**) -- the natural-language task.
  - `working_dir` (string, optional) -- a base dir the agent is told to operate in (relative tool paths are
    resolved against it; purely advisory to the model + used to resolve relative paths the model emits).
  - `max_steps` (int, default 4), `dry_run` (bool, default false).
  - `decision_tiers` (array, default `["tiny","weak","mid"]`) -- the escalator ladder for the tool decision
    (excludes the 27B `strong`, which emits empty verdicts at MVP token caps -- D-0030).
  - `gen_tier` (string, default `mid`) -- the gateway tier for arg-generation + final answer.
  - `frontier_threshold` (number, default 0.5) -- passed to the escalator; a decision below it -> `needs_frontier`.
  - `max_observation_chars` (int, default 600), `max_transcript_chars` (int, default 4000) -- bound what the
    model sees (keeps the decision text within the escalator's `max_input_chars`).
  - sampling `temperature` (default 0.0 greedy), `seed` (default 42), `max_tokens` (arg/answer gen cap).
  - plumbing: `tools_path`/`tools` (registry override), `escalator_path`, `gateway_path`, `registry` (models.json),
    `pwsh_path`, `load_timeout_s`, `review_queue_path` (relocates the in-artifact child-review sink).
- **Outputs** (`result`):
  `{ goal, working_dir, status: completed|stopped|error, final_answer, needs_frontier, step_count, max_steps,
     dry_run, tools_available:[{tool,skill_id,side_effecting}],
     steps:[ { index, decision:{chosen_tool, confidence, accepted_tier, accepted_via, needs_frontier, ok},
               args, args_raw?, tool:{skill_id, invoked, status, error}, observation, error } ],
     cost:{ decision_calls, gen_calls, tool_calls, total_gateway_calls, total_tokens, total_runtime_ms },
     is_review_producer:false, child_reviews_redirected_to }`.
  Artifacts `agent.json` (kind json) + `agent.md` (kind markdown).

## Artifact structure

- `runtime/artifacts/<invocation_id>/` -> `agent.json`, `agent.md`, `result.json`, `stderr.txt`,
  `child_review.jsonl` (redirected child review writes, when any), and per-child sub-roots
  `decision-<n>/`, `arggen-<n>/`, `tool-<n>/`, `final/` (each child's nested artifacts).

## Proposed implementation

- **Language:** PowerShell 7 (per policy: fastest useful MVP; owns the contract envelope; spawns children as
  child pwsh exactly as #18/#13/#19 do). No Python worker (all children are pwsh skills).
- Reuse the proven helpers verbatim in spirit from `image.index`: `Has`/`Prop`, `Get-Sha256Hex`,
  `Resolve-RepoRoot`, `Resolve-Child`, `Invoke-Child` (`& $PwshPath ... -InputsJson ... -ArtifactRoot ...`,
  parse stdout envelope), `Add-Provenance`, `Test-ChildOk`, `Get-ChildErrCode`, `Get-ChildConf`, plus a
  `Get-FirstJsonObject` (first `{...}` object, brace-matched) for arg parsing.
- The **loop**: build the decision text (goal + bounded transcript + tool menu), call the escalator (single
  1-item `classify` batch), read `tasks[0].{answer,confidence,accepted_tier,accepted_via,needs_frontier}`; if
  `finish`/budget/`needs_frontier`-stop -> final answer via gateway; else arg-gen via gateway, parse, invoke the
  tool, summarize the observation (bounded), append to transcript, next step.
- **Non-producer:** every child that accepts `review_queue_path` is given the in-artifact `child_review.jsonl`
  sink; the agent never writes the canonical queue and never re-flags.

## External tools or models

- Only the already-present Modules (7, 19, 20, 2) + the four wired LLM tiers. **Nothing to install on Windows.**
  Cloud box: pwsh 7.4.6 (done) for AST-parse + the mock-children harness.

## Installation steps

- None on Windows (composes existing wired modules/models). Cloud: pwsh 7.4.6 already installed.

## Tests

- **Direct / off-machine (cloud pre-ship gate):** `tests/Invoke-AgentLocalTests.ps1` drives the **real**
  `Invoke-AgentLocal.ps1` against `tests/mock-child.ps1` (a deterministic mock that **branches on the
  `-ArtifactRoot` leaf** -- `decision-*` -> a mock escalator envelope choosing a tool; `arggen-*`/`final` -> a
  mock gateway envelope returning args JSON / a final answer; `tool-*` -> a mock tool envelope), with a mock
  tools registry pointing every tool entrypoint at the mock. Exercises: the multi-step loop, tool selection,
  arg-generation + JSON parse, tool invocation + observation, the `finish` action, the `max_steps` cap ->
  `stopped`+`needs_frontier`, `needs_frontier` pass-through, `-DryRun` (no tool invoked), error paths (bad arg
  JSON, tool-returns-error, escalator-returns-unknown/needs_frontier), child-review redirection, envelope
  validity, and the Module 1 wrapper. **AST-parse every `.ps1` first.** Runs green on cloud Linux (pwsh 7.4.6).
- **Through the executor (live):**
  - `m21-verify-001` -- shipped files sha256 byte-exact + AST-parse on the target.
  - `m21-test-001` -- the mock harness live on Windows (real orchestrator + mock children) -- logic parity on-target.
  - `m21-live-001` -- a **real end-to-end** run: 1-2 achievable goals (e.g. write a fixed-content file via
    `doc.io`; then read a fixture + write a derived line to an output) with the **real** escalator
    (`[tiny,weak,mid]`) + **real** gateway (`mid`) + **real** `doc.io`/`fs.observer`. Assert: the loop finishes,
    the expected output file exists with expected content, the envelope validates, `model_provenance` spans
    real tiers, **no orphaned `llama-server`**, and the **canonical `review_queue.jsonl` is untouched**
    (before==after).

## MVP acceptance criteria

- [ ] Manifest validates; flags `determinism=mixed`, `parallel_safe=false`, `batch=false`, `streaming=false`.
- [ ] The loop **decides a tool through the escalator** (in-set gate) and **invokes it**, appending a bounded
      observation; a multi-step goal advances across steps and reaches `finish`.
- [ ] `-DryRun` records the intended tool + args for each step and **invokes no tool** (no file is written).
- [ ] The `max_steps` budget is a hard cap; exhausting it -> `status:"stopped"` + `needs_frontier:true`.
- [ ] `needs_frontier` is a status field (never a queue write / frontier call); it is set when the escalator
      decision is low-confidence or the budget is exhausted.
- [ ] The canonical `review_queue.jsonl` is untouched (all child review writes redirected).
- [ ] Envelope validates (`lifeorch.skill.result/0.1`); `confidence` in 0..1 or null; per-tier/stage
      `model_provenance`.
- [ ] Live: a **real** end-to-end goal produces the expected file with the expected content through real
      children; no orphaned `llama-server`.
- [ ] Module 1 wrapper runs it.

## Manual verification procedure

- Run `m21-live-001` via the executor; open `agent.md` (the human transcript) and confirm each step names the
  chosen tool, the arguments, and the observation, and that the target output file exists on disk with the
  expected content. Confirm `review_queue.jsonl` line-count is unchanged before/after. Confirm no
  `llama-server`/pwsh orphans.

## Documentation requirements

- Skill `README.md` + `skill.json` + `tools.json` (the default registry) + `examples/example-invocation.md` +
  `examples/example-result.json`.

## Registry updates

- `TOOL_MODEL_REGISTRY.md`: add the `agent.local` skill entry (composes 19+7 and invokes 20+2; no new model).

## State updates

- `CURRENT_STATE.md` (active module -> done, tests, the live-run outcome), `MODULE_ROADMAP.md` (Phase A #3 ->
  MVP complete + a per-module entry), `DECISION_LOG.md` (a new D-00xx), `REVIEW_QUEUE.md` (note: `agent.local`
  is an orchestrator/non-producer that redirects child flags, like #13/#18/#19).

## Known follow-on work (NOT this session)

- A warm/persistent gateway worker (shared with #7/#8/#12/#14/#16/#17/#19) to kill the per-step cold-load cost;
  richer planning (sub-goals, reflection-retry, a planning DAG); more tools in the registry (the perception,
  audio, and generator Modules) with per-tool arg schemas; a `route.tasks` (#24) drain of `needs_frontier`
  goals; auto-discovery of the registry from module manifests; a `batch` multi-goal mode; parallel independent
  tool steps; calibrated decision confidence; a persistent working-memory/scratchpad across invocations.

## STOP conditions

- Scope would exceed the "Explicit scope" list. A missing dependency is non-trivial to install. The contract
  lacks something (stop, propose the change, do not freelance). **MVP acceptance is met -- stop; do not start
  the next module.**
