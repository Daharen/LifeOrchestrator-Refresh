# HANDOFF -- Life Orchestrator (go-forward map)

**Read this after `START_HERE.md`, before you pick an "active module."** The local-agent CORRECTION ARC IS
COMPLETE (D-0043 governor Phase 1; D-0044 strong tier -> Qwen3.5-9B; D-0046 deterministic terminator) and the
per-unit ship ceremony is now automated (D-0048 job-runner, section 3). Capability expansion has RESUMED per
`MODULE_ROADMAP.md -> Build priority`; Widget #2 (Module Launcher / Registry Browser) SHIPPED (D-0049); the next unit is Widget #3 (section 4). Full history: `DECISION_LOG.md`
(D-0043, D-0044, D-0046, D-0047, D-0048, D-0049) + `claude/ADAPTIVE_RESOURCE_GOVERNOR.md`. This doc is the map.

## 0. Where the project lives (locations)

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/`.
- **Large data (models + engines, gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` --
  per-owning-module subdirs; `_engines\` holds **two** llama.cpp engines: `llama.cpp\` (**b8661**, default for
  every tier) and `llama.cpp-b10092\` (**CUDA 12.4, self-contained**, used ONLY by the 9B strong tier via the
  model entry's `engine_path`).
- **Executor (how work runs locally):** `modules\00-bootstrap-executor\runtime\` -- staging\<id>.tmp\
  (`task.ps1` + `task.json`) -> atomic `mv` -> `pending\<id>` -> running -> completed/failed. Now driven by the
  job-runner (section 3) rather than by hand.
- **Project mirror:** the attached Claude Project mirrors `core-docs/`. **Disk is canonical**; re-mirror at
  session end (the frontier runs `project_write`; the executor cannot touch the Project).
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (Turing, CC 7.5), i9-9900KF, 64 GB; driver 591.74, CUDA 13.2 tk.

## 1. Status -- what shipped

- **D-0043 -- Governor Phase 1** (`bdc7748`): decide at the MID floor; `-Profile` knob (frugal|floor|max); un-refused the 27B in route.tools.
- **D-0044 -- Strong tier -> Qwen3.5-9B** (`0bef73a`): fully GPU-resident (~6.9 GB, ~68 tok/s) via side-by-side llama.cpp b10092; a gateway `no_think` hook.
- **D-0046 -- D-0032 deterministic terminator** (`59dea8e`): a `finish` is blocked until every routed planned tool has succeeded; never re-run a done (tool,args); default ON under `-Route`. Live: dog goal at the floor default lands on the real Desktop EVERY run (3/3). The old premature-`finish` reliability bug is RESOLVED at the floor default (max residual in #1 below).
- **D-0048 -- Module 0 job-runner** (`5644b9ba`): `dev.ship` (Invoke-DevShip.ps1) + `exec-job.sh` collapse the per-unit gate+commit ceremony to a few calls (section 3). 27/27 + 24/24 off-machine; dogfood: committed BY dev.ship itself.
- **D-0049 -- Widget #2 Module Launcher / Registry Browser** (`a699ac6`): browse every installed Module from its `skill.json` + run any one directly through the Module 1 wrapper `Invoke-Skill.ps1`; WinForms-free core + thin STA shell (the Widget #1 pattern). 62/62 cloud + **71/71 `-Live`** (real registry scan >=20 modules + a real `fs.observer` run through the wrapper, 0 orphans) -- the FIRST unit shipped end-to-end through the job-runner.

## 2. Disclaimers / known issues (read before trusting the stack)

1. **`-Profile max` is NOT reliable end-to-end -- a 9B arg-gen residual, NOT the terminator.** At the FLOOR
   default multi-tool goals complete reliably (D-0046). At `max` the 9B (gen_tier=strong) arg-generator returns
   non-JSON (`arg_parse_failed`) on EVERY step, so tools never get valid args (proven by `m21-d0032-maxdiag-001`;
   floor runs the IDENTICAL script with gen_tier=mid and lands 3/3). **Use `floor` for end-to-end agent runs.**
2. **Two-engine setup.** `strong` (9B) uses `_engines\llama.cpp-b10092\`; every other tier uses `llama.cpp\`
   (b8661). BOTH must exist; do not consolidate without re-verifying every tier + the VLM.
3. **`strong` (9B) requires `"no_think": true`** -- and even so it returned non-JSON under agent.local's longer
   arg-gen prompt (#1); not yet trustworthy as the agent's arg-generator.
4. **Intermittent orphaned `llama-server`** from the transient per-call gateway; kill stray `llama-server.exe`.
   Governor Phase 2 (warm server) removes it. (dev.ship can `check_orphans` and report the count.)
5. **The 27B is retained but demoted** (`llm.strong.qwen3p5-27b`, reachable via `-Model`, on b8661).
6. **StrictMode gotcha (D-0048):** `@($genericList).Count` throws "Argument types do not match" under
   `Set-StrictMode -Version Latest`; use `$list.Count` (or `([array]$x).Count` for maybe-null cmdlet output).

## 3. The job-runner (Module 0) -- SHIPPED (D-0047 design, D-0048 build). USE IT to ship every unit.

Two Module-0 tooling files collapse the per-unit ceremony (~40 hand-driven calls -> a few):
- **`modules/00-bootstrap-executor/Invoke-DevShip.ps1`** (`dev.ship`) -- ONE executor job that, FAIL-CLOSED:
  verifies each shipped file's sha256, AST-parses every *.ps1, runs a test command, and ONLY IF all green (and
  the index has no unrelated staged files) `git add -- <exactly the named files>` + `git commit -F` (trailers).
  Emits ONE compact `lifeorch.devship.result/0.1` {ok, sha, ast, tests, commit, orphans}; exit 0 iff ok.
- **`modules/00-bootstrap-executor/exec-job.sh`** -- device-side client (run via `device_bash`):
  `submit|wait|run|devship|status`. `devship <id> <inputs.json> [timeout] [maxwait]` submits + waits + prints
  the compact result in one call. `EXEC_RT` overrides the runtime dir.

**Ship flow for a unit:** edit in cloud -> gate off-machine (cloud pwsh + mock) -> `SendUserFile` +
`device_commit_files` the files -> write a devship-input.json (`files:[{path,sha256}]`, `ast_check`,
`test_argv` with `{PWSH}`/`{REPO}` tokens, `commit`+`commit_files`+`commit_message`-with-trailers,
`check_orphans`) -> `bash <mod>/exec-job.sh devship <id> <inputs.json> <timeout>` -> read the ONE compact JSON
(long/GPU jobs: re-run `exec-job.sh wait <id>` a few times -- device_bash caps ~45s and the executor cannot
notify the harness). The index-clean guard means it can never fold in the user's unrelated
`Show-AgentConsole.ps1` edit. Full inputs schema: the `Invoke-DevShip.ps1` header + `modules/00-bootstrap-executor/README.md`.
Mirror-to-Project is still a frontier step (`project_write`); everything else on-device goes through the runner.

## 4. Next unit -- resume capability expansion (Widget #3) + deferred substrate follow-ons

Resume `MODULE_ROADMAP.md -> Build priority`. **Widget #2 (Module Launcher / Registry Browser) SHIPPED 2026-07-27 (D-0049; `widgets/02-module-launcher/`; browses
`modules/*/skill.json` + runs any Module through the Module 1 wrapper `Invoke-Skill.ps1`; 62/62 cloud + 71/71 live via
the job-runner, commit `a699ac6`).** The **next capability unit = Phase B Widget #3 -- Review /
Escalation Dashboard** (then Voice Console, Generator Studio, Document Workspace,
System/Executor Monitor; `widgets/README.md`). Multi-tool agent runs are reliable at the floor default (D-0046),
so a Widget driving `agent.local` is safe (use floor, not max). **Ship it with the job-runner (section 3).**
**Deferred substrate follow-ons (do when they earn it):** Governor Phase 2 (warm/persistent llama-server --
removes per-call cold loads + the orphan risk; the ~26-min cold `max` run in D-0046 is the motivation); 9B
arg-gen hardening (unblocks `-Profile max`); Governor Phase 3 (auto-ramp controller).

## 5. How to choose (for the driver)

Take **Widget #3** next (capability expansion, section 4), unless warm-server speed or `-Profile max`
reliability matters more right now -- then do a deferred substrate follow-on (section 4). Either way, SHIP IT
WITH THE JOB-RUNNER (section 3). One scoped unit per session (D-0029).

## 6. Operational setup + gotchas (condensed)

- **Executor / job-runner:** prefer `exec-job.sh` (section 3) over hand-building task dirs. Under the hood:
  staging -> pending -> running -> completed/failed; result.json carries status/exit_code/duration; the executor
  honours per-task `timeout_seconds` (it killed a 30-min `max` run in D-0046). Poll a long job with `wait`.
- **Device bridge:** the repo is the connected folder. In `device_bash` use YOUR OWN session mount
  (`cd ./mnt/LifeOrchestrator-Refresh`) -- NOT `ls /sessions | head -1`. `device_bash` cannot delete; `mv`
  unwanted files into a `_to_delete\` folder.
- **Ship cloud->device:** `SendUserFile` -> `device_commit_files` (byte-exact, <=20 MB/file). Large files
  (models/engines) download ON the device via an executor `curl.exe` task.
- **Off-machine gate first:** install PowerShell 7 in the fresh cloud box (per-session path; D-0046/D-0048 used
  `/home/claude/pwsh764/pwsh` from the 7.4.6 linux-x64 tarball) + git; run against the mock harness.
- **Git via the job-runner / executor ONLY;** trailers required (`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  and `Claude-Session: ...`). NEVER `git add -A`; dev.ship's index-clean guard enforces "only my files."
- **Core-docs are CRLF;** edit via the self-gating CRLF-safe pwsh pattern (validate anchors; atomic temp+rename).
  Mirror changed core-docs to the Project by fresh-copying to a never-staged `runtime\mNNmirror\` path before
  `device_stage_files` (re-staging a previously-staged path returns STALE bytes).

_Last updated 2026-07-27 (D-0049). Widget #2 (Module Launcher / Registry Browser) SHIPPED via the job-runner (commit `a699ac6`; 62/62 cloud + 71/71 live). Next unit: Widget #3 (Review / Escalation Dashboard). Ship every unit with the job-runner (section 3); use the floor profile for end-to-end agent runs (max has a 9B arg-gen residual)._
