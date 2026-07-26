# MODULE_WORK_ORDER

## Work Order: Coding Agent (`agent.coding`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-26 · **Roadmap entry:** `MODULE_ROADMAP.md` → Build priority Phase A #5 (last) · **Folder:** `modules/26-agent-coding/` (monotonic build-order counter: 0, 00.1, 1..25, then 26 — decoupled from the ARCHITECTURE_MAP 0-49 positions per D-0029)

---

## STATUS: DEFERRED (2026-07-26, DECISION_LOG D-0037)

This work order is **authored but not implemented.** After a probe (`m26-probe-001`) and a from-the-docs
analysis, `agent.coding` is **deferred** — a legitimate documented deferral (precedent D-0033; the roadmap
already pre-classified it "last here — the frontier already codes well; lowest near-term ROI," and D-0029
pre-deferred a local coding agent). The full MVP design below is preserved so a future session can build it
in roughly a day **once a revisit-if trigger lands** (see "STOP / deferral decision" at the end). The next
scoped unit is **Phase B — the Widget layer** (led by the Local Agent Console), which makes the already-built
Phase-A core (escalator #19, agent.local #21, doc.io #20, the generators #22–25) usable by a human.

---

### Problem being solved

There is no local capability for a *coding* loop: draft code → verify it → run it → read the error → fix →
repeat, done locally so the frontier allotment does not pay for routine scripting chores. `agent.local` (#21)
plans and invokes conforming Module tools, and `doc.io` (#20) writes files, but **agent.local deliberately
ships no code-execution tool** ("the registry IS the sandbox: there is deliberately NO arbitrary-shell /
code-exec tool," D-0032). So the one capability that distinguishes a *coding* agent from `agent.local` — the
execute-and-iterate-on-error loop — does not exist. `agent.coding` would close that gap with a **bounded,
sandboxed** loop.

### Immediate practical use

A local model, given a small self-contained coding goal ("write a Python script that renames every `.jpeg`
in a folder to `.jpg`"; "write a PowerShell one-liner that sums column 3 of a CSV"), drafts the code, checks
it, runs it against a scratch fixture, reads any error, and fixes it — end to end, with no frontier call.
Every such chore finished locally is one the weekly frontier allotment never pays for (the D-0029 thesis).

### Explicit scope (in) — the tight MVP slice

A specialization of `agent.local` (#21), **reusing its loop and adding exactly the coding-specific pieces** —
NOT a general IDE agent:

- A **bounded ReAct loop** identical in shape to `agent.local`: decide next action → generate args/code →
  invoke tool → observe → repeat until `finish` or the hard `max_steps` budget (default 4–6).
- **Decisions route THROUGH `logic.escalator` (#19)** as a closed-set `classify` task (labels = the tool
  names + `finish`) — the in-set gate guarantees a valid action or surfaces `needs_frontier` (the D-0032
  pattern, unchanged).
- **Code / argument generation and the final answer use `model.gateway` (#7)** directly.
- A **small closed tool registry** (`tools.json`), shipping exactly three coding tools:
  1. `code.write` — write the current draft to a file **inside the invocation's scratch dir only** (a thin
     use of `doc.io` #20 with the path forced under the scratch root).
  2. `code.check` — a **NEW deterministic static verifier** that parses/syntax-checks WITHOUT executing:
     Python `python -m py_compile` / `ast.parse`; PowerShell `[System.Management.Automation.Language.Parser]::ParseFile`;
     `node --check`. Safe, deterministic, no side effects — the analog of the AST-parse gate this project
     already runs before shipping every `.ps1`.
  3. `code.run` — the **gated executor**: run the drafted script **only** as a child process confined to the
     scratch dir, with a hard wall-clock timeout, **no network**, and captured stdout/stderr/exit-code fed
     back into the loop as the observation. **This is the one dangerous capability and is gated** (see
     Guardrails); it is the reason the module is deferred until a safe substrate exists.
- **Language support (MVP):** Python + PowerShell only (both present; both statically checkable; both the
  scripting the chores above need).
- **Guardrails** (this is the first skill where a local model *authors and runs* code):
  - the `agent.local` **hard `max_steps` budget** (runaway loop impossible);
  - a **`-DryRun` plan/draft preview** (drafts + static-checks, runs nothing) as the **default**;
  - **`code.run` requires an explicit `-AllowRun` opt-in** AND a resolvable **safe execution substrate**
    (below); absent either, `code.run` returns a structured `execution_not_permitted` and the loop degrades
    to draft+static-check + `needs_frontier`;
  - **scratch-dir confinement** — every write/run path is forced under `runtime/artifacts/<inv>/scratch/`;
    no caller-chosen paths (unlike `doc.io`'s general mutation surface);
  - **no network**, **no package install**, **no arbitrary shell** — the registry is the sandbox (D-0032);
  - `needs_frontier` surfaced as a status field, never a frontier call / queue write.
- **Orchestrator, NOT a review-queue producer** (like #13/#18/#19/#21): redirect child review writes to an
  in-artifact `child_review.jsonl`; the canonical `review_queue.jsonl` and the ten-producer set stay untouched.

### Non-goals (out — do NOT build)

- A general **IDE / repo agent** (multi-file navigation, project-wide refactors, reading a whole codebase).
- **Editing the Life Orchestrator repo itself**, or any path outside the scratch dir.
- **Package installs**, `pip`/`npm`/`winget`, network access, or long-running servers.
- An **arbitrary-shell / eval tool** of any kind (the exact line D-0032 drew for `agent.local`).
- Standing up a **sandbox** (a WSL distro, Windows Sandbox, a container runtime, a restricted-runspace/
  job-object jail) — that is a large, admin-gated, separate effort (D-0001), its own work order, and a
  **precondition** for this module's `code.run`, not part of this MVP.
- Compiled languages, test-framework integration, coverage, debuggers — later, if ever.

### Dependencies

- **Modules:** `agent.local` (#21, the loop + tool-spawn pattern), `logic.escalator` (#19, gated decisions),
  `model.gateway` (#7, codegen), `doc.io` (#20, scratch writes). All present and verified (`m26-probe-001`).
- **A safe execution substrate for `code.run`** — **currently ABSENT** (the blocker; see below).
- **Tools/models:** system Python 3.12 (present); pwsh 7.4.6 (present); Node (verify presence at build time).
- **Contract features:** `-InputsJson`, `-ArtifactRoot`, child-envelope spawn/parse, `child_review.jsonl` redirect.

### Skill contract requirements

- `skill_id: "agent.coding"`, `name: "Coding Agent"`, `version: 0.1.0`, `contract_version: 0.2`.
- `determinism: "mixed"`, `parallel_safe: false` (drives the gateway → GPU/port and runs child processes),
  `batch: false`, `streaming: false`.
- `result` shape: `{ goal, steps[], final_answer, scratch_files[], ran, run_results[], status, needs_frontier }`.
- `confidence` = the min per-step decision confidence (as `agent.local`); `model_provenance` = the stage-tagged
  aggregate of every child decision/gen call. Artifacts: `agent.json` / `agent.md` + the `scratch/` tree.

### Proposed implementation

- **Language:** PowerShell (the orchestrator + envelope, like every skill), plus the `code.check`/`code.run`
  child processes it spawns. Reuse `Invoke-AgentLocal.ps1` almost verbatim; add the three coding tools to a
  new `tools.json` and the scratch-dir confinement + `-AllowRun`/substrate gate.
- Fastest correct path: **fork `agent.local`**, swap the registry, add `code.check` (deterministic) and the
  gated `code.run`, add scratch confinement. Most of the module already exists as #21.

### External tools or models

- No new model. No `models.json` change. No Module 7 re-verify (composes wired tiers) — mirrors #21.
- A **stronger local coding model** (e.g. a Qwen2.5-Coder GGUF wired via `model.gateway`) is **optional but
  strongly recommended** before trusting the loop — the tiny/weak/mid general tiers are weak at code (see the
  ROI analysis). Staging one is its own probe/work-order step.

### Installation steps

- None for the static slice. For `code.run`: **stand up a safe substrate first** (separate work order) —
  candidates: install a WSL distro (`wsl --install -d Ubuntu`, multi-GB, may need elevation); enable Windows
  Sandbox (needs admin — unavailable, project is non-admin); a vetted restricted-runspace/job-object jail
  (real engineering). **None are cheap on this box today** (`m26-probe-001`).

### Tests

- **Direct + through the executor:** the `agent.local` harness pattern — a mock-children harness branching on
  the `-ArtifactRoot` leaf drives the real orchestrator off-GPU (cloud pre-ship gate), then the identical
  harness runs `-Live` on the executor with a real end-to-end goal (draft → check → run a trivial script in
  scratch → observe exit 0). Assert: scratch confinement (no write escapes `scratch/`); `code.run` refused
  without `-AllowRun`/substrate; `max_steps` budget stops a non-terminating loop; canonical queue before==after.

### MVP acceptance criteria

- A live goal produces a syntactically-valid script in `scratch/` (via `code.write` + `code.check`).
- With `-AllowRun` + a substrate: the script runs confined, its output is observed, and one fix iteration works.
- Without `-AllowRun`/substrate: `code.run` returns `execution_not_permitted`, loop degrades gracefully.
- `max_steps`, scratch confinement, no-network, and the child-review redirect all verified; queue untouched.

### Manual verification procedure

- Run a draft-only (`-DryRun`) goal; inspect the scratch script + the static-check verdict.
- Enable `-AllowRun` against a scratch substrate; confirm the run is confined and iterated.

### Documentation / Registry / State updates

- Skill `README.md` + `skill.json` + `tools.json` + examples; a `TOOL_MODEL_REGISTRY.md` `agent.coding` skill
  entry; `CURRENT_STATE.md` + `MODULE_ROADMAP.md` status; a DECISION_LOG entry for the build.

### Known follow-on work (beyond even the MVP)

- Multi-file projects; a real test-runner gate; a `route.tasks` (#24) drain of `needs_frontier` coding goals;
  a warm gateway worker (per-step cold-load cost is worse in a code-fix loop); a code-specialized local model
  tier; richer languages; a repo-scoped variant behind a much stronger sandbox.

### STOP / deferral decision (why this is deferred, and when to build it)

**Decision: DEFER (D-0037).** Three independent reasons converge:

1. **No safe execution substrate exists** (`m26-probe-001`): WSL has no distro; Windows Sandbox is absent and
   needs elevation (non-admin box); Docker is absent; PowerShell runs FullLanguage. The *useful* slice needs
   `code.run`, and running local-model-authored code at full Windows-user authority (the only option today) is
   a real safety escalation — exactly the arbitrary-code-exec capability `agent.local` deliberately excluded
   (D-0032). Building it safely first requires a sandbox: a large, admin-gated, separate effort (D-0001).
2. **Lowest near-term ROI, by the project's own assessment** (`MODULE_ROADMAP.md`; D-0029): the frontier
   already codes well and does this repo's coding through the executor. A loop built on the tiny/weak/mid
   general tiers — measured at sub-95% accuracy with a 0.20 false-approval rate (D-0030) and poor termination
   judgment (D-0032, "under-use `finish`") — is a poor fit for coding, the least error-forgiving task.
3. **The safe slice adds little over `agent.local`.** A coding agent *without* `code.run` is `agent.local`
   plus a `code.check` lint tool — better added as one tool in `agent.local`'s registry than shipped as a
   whole module. The genuinely-new capability (execute + iterate) is precisely the blocked, risky, low-ROI part.

Contrast D-0036 (`gen.video`), where the probe *proved* a viable result within VRAM, so deferral was rejected;
here the probe shows the safe substrate is **absent**, so deferral is earned.

**Revisit-if (build when any of these lands):**
- a safe execution substrate becomes available (a WSL distro installed; Windows Sandbox enabled; a container
  runtime; or a vetted restricted-runspace/job-object sandbox Module is built);
- a **code-specialized local model** is staged and wired via `model.gateway` (changes the capability calculus);
- a **warm/persistent gateway worker** lands (a code-fix loop is cold-load-cost-sensitive);
- **Phase B pull demand** — a Widget (e.g. a scratch coding console) concretely needs a local coding loop;
- the user explicitly wants it despite the ROI.

**Interim option (no module, if any coding-offload value is wanted before a sandbox exists):** add a
deterministic `code.check` (static parse/lint) tool to `agent.local`'s `tools.json` — safe, cheap, and it
lets the existing agent draft + syntax-check a script today without any of the risk above.
