# FAN-OUT PROTOCOL -- how an orchestrator instance drives `orchestrate.fanout`

**Audience:** the ONE Claude instance acting as the fan-out orchestrator (D-0050/D-0051). This is the
operating manual for the `orchestrate.fanout` (#30) module. The module is deterministic scaffolding; YOU
supply the judgement (what the units are, when to fan out, when to serialize). Read `START_HERE.md` +
`HANDOFF.md` first; this doc governs only the multi-instance loop.

## The hard boundary (non-negotiable)

You NEVER automate, drive, scrape, or submit to any external AI service or Claude UI. The workers are
**human-dispatched**: the module emits worker prompts, and **Nicholas** pastes each into a fresh Cowork
session. The instant software bridges two AI services it becomes the prohibited automated access (D-0051).
The check-in prompt is the human interface; the Verification Console packet is the human audit surface.

## The loop (one iteration)

1. **Scope the units.** Pick 1..N scoped units that can proceed in parallel (each is "one scoped unit per
   instance", D-0029 relaxed by D-0050). For each, decide: does it need the **GPU** (any model/render run ->
   `gpu:true`)? which shared **docs** will it edit (`docs:[...]`)? does it **commit** (`needs_git`, default
   true)? Give it an `id`, a one-line `unit`, and -- if its output is a runnable module -- `skill_id` +
   `skill_dir` (+ `inputs`) so its verification item is a `run_module`.

2. **`plan`.** Call `-Action plan` with the worker specs, a `-Title`, the `-Iteration`, `-MaxParallel`
   (start at **2** -- the trial size), and `-ReportBack` (`on_all` or `on_each`). Thread `-LeaseDir` (the
   shared res.lease dir all instances use) and `-PlansDir` (the shared plans dir) if you use non-default
   locations. The module returns `dispatch_now` (<= MaxParallel, **at most one GPU worker**), `queued`,
   `conflicts` (GPU serialization + doc contention), one prompt per worker, and one check-in prompt.
   - **Resolve conflicts before dispatch.** If `conflicts.doc_contention` is non-empty, two workers claim the
     same doc: either re-scope so only one owns it, or accept that they serialize on `doc:<path>` (slower).
     Prefer having **workers NOT edit shared core-docs at all** -- they report, and YOU mirror the shared
     docs (see step 6).
   - **Heed the preflight.** If the plan warns a needed resource is held live, the box is busy -- shrink the
     wave or wait.

3. **Hand Nicholas the check-in.** Give Nicholas exactly the one `check-in.prompt.md`: it tells him which
   worker prompts to start now, which are queued, and when to report back. Do not hand him N prompts to
   reason about -- hand him the one check-in that references them.

4. **Workers run (separate sessions).** Each worker: reads its prompt, **acquires its leases in order
   (gpu -> git -> doc), releases in reverse**, does its ONE unit, ships via `dev.ship`, then runs
   `-Action report ... -State done` (or `blocked`/`failed`). GPU-heavy units naturally serialize on the
   single `gpu` lease -- that is the clamp-to-1 in action; keep `MaxParallel` GPU work to one at a time.

5. **Poll `status`.** Call `-Action status -PlanId <id>` until `ready_for_handoff` is true (`on_all` = every
   worker terminal; `on_each` = the first terminal worker, for a rolling handoff). A workflow cannot block
   waiting on a human, so this is asynchronous: Nicholas comes back when the cadence says.

6. **`handoff`.** Call `-Action handoff -PlanId <id>` (with `-NextWorkersJson` for the next iteration, or omit
   to get an editable template). It emits `verification-packet.json` -- give it to Nicholas to load in the
   **Verification Console**: he runs each `run_module` item through `Invoke-Skill.ps1`, works the checklist,
   and exports a `lifeorch.verification.result/0.1` you read back. Then **mirror the shared docs YOURSELF**,
   serialized: acquire `res.lease` `git` (and `doc:<path>` for each core-doc you touch) directly, update
   CURRENT_STATE / MODULE_ROADMAP / DECISION_LOG / etc., release in reverse. Workers never touch these.

7. **Iterate.** Persist the next plan (`-Action plan -Iteration <n+1> ...`) and repeat, or close the loop with
   a normal handoff.

## Resource discipline (the res.lease contract you and the workers share)

- **Acquire order** (deadlock avoidance): `gpu` -> `git` -> `doc:<path>`. **Release in reverse.** The module
  emits every worker's commands in this order; you follow the same when you mirror docs.
- Set a **stable holder** per session (`$env:LIFEORCH_INSTANCE`, else the module uses the worker id). Release
  by `-LeaseId` when you have it; release-by-holder otherwise.
- Every instance MUST resolve the **same** `-LeaseDir` and `-PlansDir`. Pass them explicitly if not default.
- `git` is a single lease -> commits serialize (dev.ship + your doc mirror). `gpu` is a single lease -> one
  model/render at a time. `doc:<path>` -> one editor of a shared doc at a time.

## Sizing

- Start **MaxParallel = 2** (trial). Scale up only as the box proves it keeps up (I/O + the single GPU are the
  ceilings). **Clamp GPU-heavy units to 1** -- the module already caps dispatch to one GPU worker, and the
  `gpu` lease enforces it at runtime even if two are dispatched.
- Keep each worker to ONE scoped unit. If a worker wants to expand scope, it reports `blocked`/`needs` and you
  spin the extra work into the next iteration's specs -- never let a worker widen mid-run.
