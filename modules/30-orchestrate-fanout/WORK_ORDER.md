# MODULE_WORK_ORDER -- Fan-out Orchestrator (`orchestrate.fanout`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-27 · **Roadmap entry:** `MODULE_ROADMAP.md#orchestrate.fanout`

> On-disk `modules/30-orchestrate-fanout/`. The `NN-` prefix is the monotonic build-order counter
> (0, 00.1, 1..29, then 30); D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions.
> `orchestrate.fanout` is the coordination unit named by D-0051, built ON TOP OF `res.lease` (#29).

### Problem being solved

The multi-instance direction (D-0050) and the user's fan-out orchestrator (D-0051) want ONE orchestrator
Claude instance to run **N worker Cowork sessions** building the Life Orchestrator in parallel on this one
box. `res.lease` (#29) shipped the collision-safety primitive (a GPU lease, a git/commit lock, `doc:<path>`
ownership). What is still missing is the deterministic **scaffolding** that turns "run N workers" into a
concrete, collision-safe plan: who runs now vs. queued, which leases each worker must hold and in what order,
the ready-to-paste worker prompts, exactly one check-in prompt for Nicholas, and -- when the workers report
back -- the assembled final handoff plus a Verification Console packet Nicholas can audit. A skill cannot
spawn Claude sessions; it CAN produce and manage every deterministic artifact around them.

### Immediate practical use

The orchestrator instance (a Claude Cowork session) calls this skill to: (1) turn a list of worker unit-specs
into a fan-out **plan** (schedule + per-worker prompts + one Nicholas check-in prompt), respecting the GPU
clamp and doc-ownership conflicts; (2) collect each worker's progress **report**; (3) check **status** /
whether the report-back cadence is satisfied; (4) assemble the **handoff** (next-iteration worker prompts +
one check-in prompt + a `lifeorch.verification.packet/0.1` for the Verification Console). It composes
`res.lease` for collision safety and the Verification Console packet/result as its human-I/O.

### Explicit scope (in)

- One action per invocation: `plan | report | status | handoff | list`.
- `plan`: deterministic scheduler over worker specs -> assigns each worker its ordered lease set
  (**acquire-order gpu -> git -> doc:\<path\>**, release reverse), computes `dispatch_now` (trial of
  `max_parallel`, default 2; **clamped to at most one GPU worker**) vs. `queued`, flags **doc-ownership
  conflicts** (>1 worker editing the same doc) and **GPU serialization**, emits one worker prompt per worker
  + exactly one Nicholas check-in prompt (+ the report-back cadence), and persists the plan.
- `plan` **preflight** (optional, composes `res.lease`): spawn `res.lease -Action list` (read-only,
  parallel-safe) to snapshot current holdings and warn if a needed resource is already held live. Skips
  cleanly (a noted warning, not a failure) when res.lease is not resolvable or `-NoPreflight`.
- Embed the **exact** `res.lease acquire/release` command lines each worker must run in that worker's prompt.
- `report`: a worker (or the orchestrator on its behalf) records a progress report
  `{state: started|progress|blocked|done|failed, summary, needs?}` -- one file per report (parallel-safe).
- `status`: roster of workers + each worker's latest report state + `ready_for_handoff` per the cadence
  (`on_all` = every worker done/failed; `on_each` = >=1 done/failed).
- `handoff`: assemble a handoff summary + the next-iteration worker prompts (from a supplied next-spec or a
  template) + exactly one check-in prompt + a **Verification Console packet** (`lifeorch.verification.packet/0.1`)
  with one `run_module`/`human_action` item per worker output.
- Deterministic, `parallel_safe:true`, orchestrator/**non-producer** (no review-queue writes). Pure
  PowerShell + .NET -- no external binary / Python / model / `models.json` change / Module 7 re-verify.
- A short **operating-protocol doc** (`FANOUT_PROTOCOL.md`) telling the orchestrator instance how to drive it.

### Non-goals (out -- do NOT build)

- Spawning / driving Claude Cowork sessions or any external AI (that is the human's job; automating it is the
  prohibited access boundary, D-0051/D-0052). The skill only emits prompts + collects reports.
- Acquiring/holding leases FOR the workers (each worker holds its own via `res.lease` at runtime); the plan
  only tells them which to take. The orchestrator acquires `git`/`doc:` around its OWN doc mirroring by
  calling `res.lease` directly (documented in the protocol doc), not through this skill.
- A fair FIFO/priority scheduler, live worker monitoring, auto-renew, or a warm-server lease (res.lease
  follow-ons).
- Editing shared core-docs or committing (that is dev.ship + the orchestrator; this skill writes only under
  its own plans dir + artifact dir).

### Dependencies

- Modules: **`res.lease` #29** (composed as a read-only child for preflight; its acquire/release commands are
  embedded in worker prompts), **Verification Console** widget #03 (its `lifeorch.verification.packet/0.1`
  schema is emitted at handoff), `skill.bootstrap` #1 (the generic wrapper + contract).
- Tools/models: none (pure PowerShell + .NET). Contract features: `-InputsJson`, `-ArtifactRoot`, the result
  envelope, skill-relative artifact roots.

### Skill contract requirements

- `skill_id` `orchestrate.fanout`; `name` "Fan-out Orchestrator"; `version` 0.1.0; `determinism`
  `deterministic`; `parallel_safe` **true** (report writes are per-file; plan/handoff are per-invocation);
  `batch` false; `streaming` false.
- `result` shape per action (see below). `confidence` **null**, `model_provenance` **empty** (deterministic).
  Artifact kinds: `json`, `markdown`. NOT a review-queue producer.

### Inputs and outputs

- **Inputs (via named params or `-InputsJson`):** `action` (req); `workers` (plan: array of
  `{id, label?, unit, gpu?:bool, docs?:[paths], needs_git?:bool=true, inputs?, skill_id?, skill_dir?, notes?}`);
  `title`, `iteration` (int, default 1), `max_parallel` (int, default 2), `report_back` (`on_all`|`on_each`,
  default `on_all`); `plan_id` (report/status/handoff); `worker_id`, `state`, `summary`, `needs` (report);
  `next_workers` (handoff: same shape as `workers`); `plans_dir`, `res_lease_path`, `no_preflight`.
- **Outputs (`result`):**
  - `plan`: `{plan_id, iteration, title, max_parallel, report_back, workers:[{id, gpu, docs, leases:[...],
    acquire_commands:[...], release_commands:[...], prompt_path}], dispatch_now:[ids], queued:[ids],
    conflicts:{doc_contention:[{doc, workers}], gpu_serialized:[ids]}, preflight:{ran, held:[...], note},
    check_in_prompt_path, plan_dir}`
  - `report`: `{plan_id, worker_id, state, recorded:true, report_file}`
  - `status`: `{plan_id, iteration, report_back, workers:[{id, state, last_summary, reported_at}],
    counts:{total, done, failed, blocked, running, no_report}, ready_for_handoff:bool}`
  - `handoff`: `{plan_id, next_iteration, summary, worker_prompts_next:[paths], check_in_prompt_path,
    verification_packet_path, handoff_path}`
  - `list`: `{plans_dir, count, plans:[{plan_id, iteration, title, worker_count, created_at_utc}]}`

### Artifact structure

- `runtime/artifacts/<invocation_id>/` -> `fanout.json` + `fanout.md` (+ `stderr.txt`); `plan` also writes
  `workers/worker-<id>.prompt.md` and `check-in.prompt.md`; `handoff` also writes `handoff.md`,
  `verification-packet.json`, and `next-workers/worker-<id>.prompt.md`.
- **Plan store (shared, cross-invocation, like res.lease's lease dir):** `-PlansDir`, else
  `$env:LIFEORCH_FANOUT_DIR`, else `$PSScriptRoot/runtime/plans`; each plan =
  `plans/<plan_id>/plan.json` + `plans/<plan_id>/reports/<worker_id>.<guid8>.json` (per-file =
  parallel-safe appends).

### Proposed implementation

- **Language:** PowerShell 7 + .NET (per policy: deterministic file/string work, matches res.lease #29 exactly;
  no new runtime). Mirrors `Invoke-ResLease.ps1`'s structure (Has/Prop helpers, atomic writes, artifact block,
  envelope block, `-InputsJson` merge).
- Pure planning + file I/O. The only child spawn is the OPTIONAL read-only `res.lease list` preflight (the
  agent.local/image.index spawn-and-parse-envelope pattern), mockable via `-ResLeasePath`.

### External tools or models

- None. `res.lease` #29 is the only composed skill (already built, D-0053). No install.

### Installation steps

- None (pure PowerShell). Cloud gate: pwsh 7.4.6 on the Linux box (per D-0048).

### Tests

- **Dual-mode / OS-portable harness** (`tests/Invoke-OrchestrateFanoutTests.ps1`), ASCII-only, temp plans dir,
  drives the REAL skill; a mock `res.lease` (`tests/mock-reslease.ps1`) for the preflight seam; the optional
  Module 1 wrapper via `-WrapperPath`. Scenarios: manifest sanity; plan (2 non-gpu -> both dispatch_now);
  GPU clamp (2 gpu -> serialized, <=1 in dispatch_now); doc conflict surfaced; acquire-order + embedded
  commands; preflight warns on a held resource (mock); report -> status reflects it; ready_for_handoff per
  cadence (on_all/on_each); handoff -> handoff.json/md + a VALID verification packet + check-in + next prompts;
  list; error paths (missing action, invalid action, no workers, unknown plan_id); deterministic (null
  confidence, empty provenance); canonical review queue untouched; Module 1 wrapper.
- **Through the executor / live:** same harness `-Live` via `dev.ship` (sha + AST + tests, fail-closed commit).

### MVP acceptance criteria

- [ ] `plan` produces a collision-safe schedule (GPU clamp + doc-conflict flags), one prompt per worker + one
  Nicholas check-in prompt, and persists the plan; each worker prompt embeds the correct ordered res.lease
  acquire/release commands.
- [ ] `report` records; `status` reflects state + computes `ready_for_handoff` per the cadence.
- [ ] `handoff` emits a schema-valid `lifeorch.verification.packet/0.1` + next-iteration prompts + one check-in.
- [ ] Every invocation emits a schema-valid `lifeorch.skill.result/0.1` (deterministic: null confidence, empty
  provenance); NOT a review-queue producer.
- [ ] Harness green off-machine (pwsh 7.4.6) AND `-Live` via dev.ship; files byte-exact + AST-parse OK.

### Manual verification procedure

- Nicholas runs the harness `-Live`; then a **dogfood**: the orchestrator writes a real 2-worker plan for a
  small real unit, Nicholas eyeballs the two worker prompts + the check-in prompt for sanity.

### Documentation requirements

- Skill `README.md` + `skill.json` + `examples/` (example-invocation.md + example-result.json) +
  `FANOUT_PROTOCOL.md` (the operating-protocol doc).

### Registry / state updates

- Add the `TOOL_MODEL_REGISTRY.md` entry; update `CURRENT_STATE.md` + `MODULE_ROADMAP.md`; append
  `DECISION_LOG.md` D-0054; re-point `HANDOFF.md` + `START_HERE.md`; mirror changed core-docs to the Project.

### Known follow-on work

- Wire res.lease renew/auto-renew into long worker leases; live worker monitoring; a fair/priority scheduler;
  a `report` merge into a single reports log with a res.lease `doc:` guard; richer next-iteration templating;
  a `route.tools`-style tool-scoping of each worker's allowed modules.

### STOP conditions

- Scope beyond the action list above; automating any external AI session (out, D-0051); the contract lacking
  something (stop, propose the change); MVP acceptance met -- stop, do not start the next unit.
