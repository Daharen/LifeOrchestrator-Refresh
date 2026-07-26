# HANDOFF -- Life Orchestrator (local-agent correction arc)

**Read this after `START_HERE.md`, before you pick an "active module."** It is the consolidated pass-off:
it lets a fresh session either (a) **continue the corrections** or (b) **return to normal roadmap progress**,
and it states the current disclaimers. Full history is in `DECISION_LOG.md` (D-0043, D-0044) and
`claude/ADAPTIVE_RESOURCE_GOVERNOR.md`; this doc is the map, not the substance.

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

## 1. Why normal progress paused (the correction arc)

The user flagged that the local LLM tiers were run under-spec and the agent was too unreliable to trust
(auditing weak output cost more than it saved). We paused one-module-per-session build-out to fix the
local-agent substrate. Two corrections have SHIPPED:

- **D-0043 -- Adaptive Resource Governor, Phase 1** (commit `bdc7748`): decide at the competent **MID floor**
  (dropped the tiny/weak ladder that anchored the good tier on weak answers); added a **`-Profile` knob**
  (frugal|floor|max) = the governor's rungs; **un-refused the 27B** in route.tools. Live: the dog goal at the
  floor default completes 3 steps / ~48 s.
- **D-0044 -- Strong tier -> Qwen3.5-9B** (commit `0bef73a`): replaced the split-brain **27B** (partial
  offload, ~2 tok/s, a 30-min agent timeout) with **Qwen3.5-9B Q4_K_M**, **fully GPU-resident** (~6.9 GB, ngl
  99, ~4.3 GB headroom, ~68 tok/s). Needed a **side-by-side llama.cpp b10092** (the 9B is a hybrid
  attention-SSM arch b8661 cannot load). A general gateway **`no_think`** hook makes it emit clean output.

## 2. Disclaimers / known issues (OPEN -- read before trusting the stack)

1. **D-0032 termination weakness -- the #1 gating bug.** `agent.local` accepts a `finish` decision
   PREMATURELY (and sometimes loops a tool to `max_steps`), so multi-tool goals -- e.g. "generate a dog AND
   place it on my desktop" -- do NOT reliably complete. It is **non-deterministic** (placed cleanly in
   D-0043; skipped placement in D-0044's tests) and **NOT a model problem** (the floor default, which uses
   `mid` not the 9B, also skipped placement). Until this is fixed, end-to-end agent runs are unreliable for
   goals needing >=2 tools in sequence. This is the recommended NEXT unit (section 3a).
2. **Two-engine setup.** `strong` (9B) uses `_engines\llama.cpp-b10092\` via the 9B entry's `engine_path`;
   every other tier uses `_engines\llama.cpp\` (b8661). BOTH dirs must exist; b8661 is kept for rollback.
   Do not "consolidate" onto b10092 without re-verifying every tier + the VLM on it (a separate unit).
3. **`strong` (9B) requires `"no_think": true`** in its `models.json` entry. Without it the gateway's default
   flags leave Qwen3.5 reasoning ON and it emits EMPTY content at `finish=length`. Do not remove it.
4. **Intermittent orphaned `llama-server`.** The transient per-call gateway occasionally leaves a
   `llama-server` holding VRAM. If VRAM is unexpectedly occupied, kill stray `llama-server.exe`. The warm
   server (section 3b) removes this.
5. **The 27B is retained but demoted.** `llm.strong.qwen3p5-27b` stays in `models.json` (reachable via
   `-Model`) but is no longer the strong tier; it still loads on b8661.

## 3. Continue the corrections (priority order)

Each is a normal one-scoped-unit session: probe -> build -> off-machine gate (cloud pwsh + mock) -> ship
byte-exact (sha + AST on target) -> live-test via the executor -> commit + docs + Project mirror.

### (a) FIX D-0032 -- deterministic terminator (NEXT; unblocks reliable end-to-end)

Build a **deterministic terminator + repeat guard** in `agent.local`
(`modules/21-agent-local/Invoke-AgentLocal.ps1`), model-independent:
- Do NOT accept a `finish` decision while any **planned tool** (from the `-Route` selection, when routing is
  on) has not yet succeeded at least once -- unless the step budget is hit. When routing is off, fall back to
  a lighter heuristic (require >=1 successful side-effecting tool for goals that imply an output).
- Add a **repeat-action guard**: if the same tool is chosen with materially the same args and already
  succeeded, block re-running it (prevents the gen.image/fs.manage loops to `max_steps`).
- Small, surgical, safely defaulted (e.g. `-RequirePlannedToolsBeforeFinish` on by default when `-Route`);
  cap the override by the step budget so a genuinely-unneeded planned tool can't stall forever; surface the
  enforcement in `result` (e.g. `finish_blocked_reason`).
- Verify: extend `tests/Invoke-AgentLocalTests.ps1` (currently 58/58) with finish-blocked-until-planned,
  repeat-guard, and still-finishes-when-done cases; then LIVE run "Generate an image of a dog and place it
  on my desktop" at BOTH `floor` and `max` several times and confirm the dog lands EVERY run (new-png
  detection; clean up after; assert 0 orphaned llama-server).

### (b) Governor Phase 2 -- warm / persistent model server

Removes the per-call cold load AND the orphan issue. `model.gateway` (#7) starts a TRANSIENT `llama-server`
per call; keep a RESIDENT one, evict+load only on a real model change, measure warm-vs-cold. With the 9B
strong (~6.9 GB) + the 3B mid (~2 GB) both fitting in 11 GB, a warm server could even keep BOTH tiers
resident (free tier-switching) -- validate that. See `claude/ADAPTIVE_RESOURCE_GOVERNOR.md` -> Phase 2.

### (c) Governor Phase 3 -- auto-ramp controller

Run at the `floor` rung; ramp the envelope toward the machine ceiling only on unsolved / failed-verification;
stop at verified-success or ceiling. Decision-escalation to the 27B must be a DIRECT classify call, not the
escalator judge (measured to re-break, D-0043). See the governor doc -> Phase 3.

## 4. Return to normal progress (the roadmap)

The corrections do NOT block normal build-out -- they improve the substrate the Widgets drive. To resume,
follow `MODULE_ROADMAP.md -> Build priority`. Phase A modules (0-25, plus 27 `route.tools`, 28 `fs.manage`)
are complete; Phase B (Widgets) #1 **Local Agent Console** is done. **The next normal unit is Widget #2 --
Module Launcher / Registry Browser** (then Review/Escalation Dashboard, Voice Console, Generator Studio,
Document Workspace, System/Executor Monitor; full list + rationale in `widgets/README.md`). One scoped
Module or Widget per session (D-0029). CAVEAT: any Widget that drives `agent.local` for multi-tool goals
inherits the D-0032 unreliability until section 3a is done -- prefer finishing D-0032 first if the Widget
depends on reliable multi-step agent runs.

## 5. How to choose (for the driver)

- **"Keep fixing" / reliability matters** -> do (a) D-0032, then (b)/(c) as desired.
- **"Back to normal"** -> next roadmap unit (Widget #2), accepting the D-0032 disclaimer above.
- **Recommended:** finish (a) D-0032 first -- it is what makes the local agent trustworthy end-to-end -- then
  choose corrections-vs-roadmap. The model + decision-floor bottlenecks are already solved (D-0043/D-0044);
  the terminator is the last thing between "fast, resident, clean models" and "reliably finishes the task."

## 6. Operational setup + gotchas (condensed)

- **Executor:** staging -> pending -> running -> completed/failed; trust `completed\<id>\stdout.txt` (not the
  running snapshot). Poll ~30 s. `task.json` = `{task_id, script_file:"task.ps1", timeout_seconds}`.
- **Device bridge:** the repo is the connected folder. In `device_bash` use YOUR OWN session mount
  (`cd ./mnt/LifeOrchestrator-Refresh`, i.e. `/sessions/<your-uid>/mnt/...`) -- NOT `ls /sessions | head -1`
  (that can pick another session -> Permission denied). `device_bash` cannot delete; `mv` unwanted files into
  a `_to_delete\` folder.
- **Ship cloud->device:** `SendUserFile` -> `device_commit_files` (byte-exact, <=20 MB/file); verify sha + AST
  on target. Large files (models/engines, >20 MB) download ON the device via an executor `curl.exe` task.
- **Off-machine gate first:** cloud pwsh at `/home/claude/pwsh764/pwsh` against the module's mock harness.
- **Git via the executor ONLY;** commit trailers required (`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  and `Claude-Session: ...`). Stage ONLY your files -- NEVER `git add -A` (the user has an unrelated working
  edit on `widgets/01-local-agent-console/Show-AgentConsole.ps1`).
- **Core-docs are CRLF;** edit via the self-gating CRLF-safe pwsh pattern (validate all anchors before any
  write; atomic temp+rename). Mirror changed docs to the Project by fresh-copying to a never-staged
  `runtime\mNNmirror\` path before `device_stage_files` (re-staging a previously-staged path returns STALE
  bytes).

_Last updated 2026-07-26 (D-0045). Location references audited clean; strong tier = Qwen3.5-9B on b10092._