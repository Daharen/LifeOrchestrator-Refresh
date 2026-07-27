# HANDOFF -- Life Orchestrator (go-forward map)

**Read this after `START_HERE.md`, before you pick an "active module."** The local-agent CORRECTION ARC IS
COMPLETE (D-0043 governor Phase 1; D-0044 strong tier -> Qwen3.5-9B; D-0046 deterministic terminator). The
project has RESUMED capability expansion per `MODULE_ROADMAP.md -> Build priority`, with ONE infrastructure
unit first (section 3). Full history: `DECISION_LOG.md` (D-0043, D-0044, D-0046, D-0047) +
`claude/ADAPTIVE_RESOURCE_GOVERNOR.md`. This doc is the map, not the substance.

## 0. Where the project lives (locations)

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/`.
- **Large data (models + engines, gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` --
  per-owning-module subdirs; `_engines\` holds **two** llama.cpp engines: `llama.cpp\` (**b8661**, the default
  for every tier) and `llama.cpp-b10092\` (**CUDA 12.4, self-contained**, used ONLY by the 9B strong tier via
  the model entry's `engine_path`).
- **Executor (how work runs locally):** `modules\00-bootstrap-executor\runtime\` -- build a task dir in
  `staging\<id>.tmp\` (`task.ps1` + `task.json`), atomically `mv` it to `pending\<id>`, then read
  `completed\<id>\stdout.txt`.
- **Project mirror:** the attached Claude Project mirrors `core-docs/`. **Disk is canonical**; re-mirror
  disk -> Project at session end.
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (Turing, CC 7.5), i9-9900KF, 64 GB; driver 591.74 (CUDA 13.1
  max), CUDA 13.2 toolkit.

## 1. Status -- what shipped (the corrections are done)

- **D-0043 -- Governor Phase 1** (commit `bdc7748`): decide at the competent MID floor (dropped the tiny/weak
  ladder that anchored the good tier on weak answers); `-Profile` knob (frugal|floor|max); un-refused the 27B
  in route.tools.
- **D-0044 -- Strong tier -> Qwen3.5-9B** (commit `0bef73a`): fully GPU-resident (~6.9 GB, ngl 99, ~68 tok/s)
  via a side-by-side llama.cpp b10092 (the 9B is a hybrid attention-SSM arch b8661 cannot load); a general
  gateway `no_think` hook.
- **D-0046 -- D-0032 deterministic terminator + repeat guard** (commit `59dea8e`): a `finish` decision is
  blocked until every routed planned tool has succeeded (force the first unsatisfied one, capped by the step
  budget); an already-succeeded (tool, materially-same args) is never re-run; default ON under `-Route`,
  surfaced as `result.terminator`. **Live: the dog goal `-Route` at the floor default lands on the real
  Desktop EVERY run (3/3), incl. a run where the terminator forced fs.manage after the model tried to finish
  early.** Tests 58 -> 87, all green off-machine + on target. **The old D-0032 premature-`finish` reliability
  bug is RESOLVED** at the floor default; see disclaimer #1 for the `max` residual.

## 2. Disclaimers / known issues (read before trusting the stack)

1. **`-Profile max` is NOT reliable end-to-end -- a 9B arg-gen residual, NOT the terminator.** At the FLOOR
   default multi-tool goals now complete reliably (D-0046). At `max` the 9B (gen_tier=strong) arg-generator
   returns non-JSON (`arg_parse_failed`) on EVERY step, so tools never get valid args (proven by
   `m21-d0032-maxdiag-001`; floor runs the IDENTICAL shipped script with gen_tier=mid and lands 3/3). The
   terminator handles it correctly (blocks the premature finishes, reports stopped / succeeded=[], no
   over-claim). **Use `floor` for end-to-end agent runs;** hardening the 9B arg-gen (section 4) unblocks `max`.
2. **Two-engine setup.** `strong` (9B) uses `_engines\llama.cpp-b10092\` via the 9B entry's `engine_path`;
   every other tier uses `_engines\llama.cpp\` (b8661). BOTH must exist; do not "consolidate" onto b10092
   without re-verifying every tier + the VLM on it (a separate unit).
3. **`strong` (9B) requires `"no_think": true`** in its `models.json` entry -- without it the gateway leaves
   Qwen3.5 reasoning ON and it emits EMPTY at `finish=length`. Even WITH it, the 9B returned non-JSON under
   `agent.local`'s longer arg-gen prompt (disclaimer #1) -- not yet trustworthy as the agent's arg-generator.
4. **Intermittent orphaned `llama-server`.** The transient per-call gateway occasionally leaves one holding
   VRAM; kill stray `llama-server.exe`. The warm server (section 4) removes this. (D-0046 floor runs: 0.)
5. **The 27B is retained but demoted** (`llm.strong.qwen3p5-27b` in `models.json`, reachable via `-Model`,
   loads on b8661) but is no longer the strong tier.

## 3. ACTIVE UNIT -- executor JOB-RUNNER (Module 0 expansion) + `dev.ship` harness (D-0047)

The immediate next unit is INFRASTRUCTURE, not a capability Module: collapse the per-unit ship/verify/test/
commit/mirror ceremony that dominates ongoing frontier-token use (~40 hand-driven device calls + ~30 poll
round-trips per unit today -- bespoke `task.ps1` authoring, sha-verify, AST, tests, git-add-only-mine +
commit-with-trailers, CRLF-safe doc edits, Project mirror). Build:
- **A reusable executor CLIENT** (`modules/00-bootstrap-executor/Invoke-ExecJob.ps1`): encapsulate the
  `staging\<id>.tmp\` -> `pending\<id>` submit dance; return a COMPACT result {status, exit_code, duration_ms,
  stdout_tail, result} -- stop re-authoring mkdir/heredoc/mv, stop reading raw dumps.
- **A device-side `dev.ship` ORCHESTRATOR** run as ONE executor job: given {file->expected-sha map, a test
  command, a commit message, the commit file list}, verify each sha256 + AST-parse the `.ps1`, run the tests,
  and IF green `git add -- <only those files>` + `git commit -F <msg-with-trailers>`; emit ONE compact summary
  {sha_ok, ast_ok, tests, committed_sha, staged_files, orphans}. Collapses verify+test+commit from ~4
  separately-polled jobs into ONE submit + one poll-to-done + one compact read.
- **Cloud-side steps stay with the frontier** (SendUserFile->device_commit_files ship-in; project_write
  mirror-out) -- a few calls, unchanged. **Ceiling:** `device_bash` caps at ~45 s and the executor cannot
  notify the harness, so long GPU jobs still need a few polls; the win is killing the DRIVING calls + verbose
  outputs + re-authoring, not every wait. **Stretch:** emit/refresh a compact `CURRENT_STATE.json` byproduct
  to cut start-of-session context re-acquisition.
Gate it the usual way (off-machine mock -> ship byte-exact -> live via the executor); `dev.ship` should run
its OWN gate through the client (dogfood). See D-0047.

## 4. After the job-runner -- resume capability expansion + deferred substrate follow-ons

Resume `MODULE_ROADMAP.md -> Build priority`. Phase A Modules (0-25, +27 route.tools, +28 fs.manage) are
complete; Phase B (Widgets) #1 Local Agent Console is done. **Next capability unit = Widget #2 -- Module
Launcher / Registry Browser** (then Review/Escalation Dashboard, Voice Console, Generator Studio, Document
Workspace, System/Executor Monitor; `widgets/README.md`). Multi-tool agent runs are reliable at the floor
default now, so a Widget driving `agent.local` is safe (use floor, not max). **Deferred substrate follow-ons
(do when they earn it):** Governor Phase 2 (warm/persistent llama-server -- removes per-call cold loads + the
orphan risk; the ~26-min cold `max` run in D-0046 is the motivation); 9B arg-gen hardening (unblocks
`-Profile max` -- a JSON-grammar / stricter arg-gen prompt / fall-back-to-mid fix); Governor Phase 3
(auto-ramp controller).

## 5. How to choose (for the driver)

Do the **job-runner (section 3) next** -- it is the highest-leverage frontier-token save and it makes every
later unit cheaper. After it, take the next `MODULE_ROADMAP.md` unit (Widget #2), or a deferred substrate
follow-on (section 4) if warm-server speed / `max` reliability matters more at the time. One scoped unit per
session (D-0029).

## 6. Operational setup + gotchas (condensed)

- **Executor:** staging -> pending -> running -> completed/failed; trust `completed\<id>\stdout.txt` (not the
  running snapshot). Poll ~30 s. `task.json` = `{task_id, script_file:"task.ps1", timeout_seconds}` (the
  executor honours per-task `timeout_seconds`; it killed a 30-min `max` run at its limit in D-0046).
- **Device bridge:** the repo is the connected folder. In `device_bash` use YOUR OWN session mount
  (`cd ./mnt/LifeOrchestrator-Refresh`, i.e. `/sessions/<your-uid>/mnt/...`) -- NOT `ls /sessions | head -1`
  (that can pick another session -> Permission denied). `device_bash` cannot delete; `mv` unwanted files into
  a `_to_delete\` folder.
- **Ship cloud->device:** `SendUserFile` -> `device_commit_files` (byte-exact, <=20 MB/file); verify sha + AST
  on target. Large files (models/engines, >20 MB) download ON the device via an executor `curl.exe` task.
- **Off-machine gate first:** cloud pwsh -- install PowerShell 7 in the fresh cloud box (the path is
  per-session; D-0046 used `/home/claude/pwsh764/pwsh` after downloading the 7.4.6 linux-x64 tarball) and run
  against the module's mock harness.
- **Git via the executor ONLY;** commit trailers required (`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  and `Claude-Session: ...`). Stage ONLY your files -- NEVER `git add -A` (the user has an unrelated working
  edit on `widgets/01-local-agent-console/Show-AgentConsole.ps1`).
- **Core-docs are CRLF;** edit via the self-gating CRLF-safe pwsh pattern (validate all anchors before any
  write; atomic temp+rename). Mirror changed docs to the Project by fresh-copying to a never-staged
  `runtime\mNNmirror\` path before `device_stage_files` (re-staging a previously-staged path returns STALE
  bytes).

_Last updated 2026-07-27 (D-0047). Correction arc COMPLETE (D-0043/44/46); resumed capability expansion. ACTIVE unit = the executor job-runner (Module 0 expansion) + `dev.ship` harness; then Widget #2. Use the floor profile for end-to-end agent runs (max has a 9B arg-gen residual)._
