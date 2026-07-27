# HANDOFF -- Life Orchestrator (local-agent correction arc)

**Read this after `START_HERE.md`, before you pick an "active module."** It is the consolidated pass-off:
it lets a fresh session either (a) **continue the corrections** or (b) **return to normal roadmap progress**,
and it states the current disclaimers. Full history is in `DECISION_LOG.md` (D-0043, D-0044, D-0046) and
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
local-agent substrate. Three corrections have SHIPPED:

- **D-0043 -- Adaptive Resource Governor, Phase 1** (commit `bdc7748`): decide at the competent **MID floor**
  (dropped the tiny/weak ladder that anchored the good tier on weak answers); added a **`-Profile` knob**
  (frugal|floor|max) = the governor's rungs; **un-refused the 27B** in route.tools. Live: the dog goal at the
  floor default completes 3 steps / ~48 s.
- **D-0044 -- Strong tier -> Qwen3.5-9B** (commit `0bef73a`): replaced the split-brain **27B** (partial
  offload, ~2 tok/s, a 30-min agent timeout) with **Qwen3.5-9B Q4_K_M**, **fully GPU-resident** (~6.9 GB, ngl
  99, ~4.3 GB headroom, ~68 tok/s). Needed a **side-by-side llama.cpp b10092** (the 9B is a hybrid
  attention-SSM arch b8661 cannot load). A general gateway **`no_think`** hook makes it emit clean output.
- **D-0046 -- D-0032 deterministic terminator + repeat-action guard** (agent.local): a `finish` decision is
  blocked until every routed **planned tool** has succeeded (force-select the first unsatisfied one, capped by
  the step budget), and an already-succeeded (tool, materially-same args) is never re-run. Default ON under
  `-Route`, surfaced as `result.terminator`. **Live: the dog goal `-Route` at the floor default lands on the
  real Desktop EVERY run (3/3), incl. a run where the terminator forced fs.manage after the model tried to
  finish early.** Tests 58 -> 87, all green off-machine + on target. See section 2#1 for the max residual.

## 2. Disclaimers / known issues (read before trusting the stack)

1. **D-0032 termination weakness -- RESOLVED (D-0046) at the floor default; a MAX residual remains.** The
   deterministic terminator (above) fixes the premature-`finish` / loop-to-max_steps bug: at the **floor
   default** the multi-tool dog goal ("generate a dog AND place it on my desktop", `-Route`) now completes
   reliably (3/3 live, dog on the real Desktop). **BUT `-Profile max` still does NOT land the dog** -- NOT a
   terminator fault: the **9B (gen_tier=strong) arg-generator returns non-JSON (`arg_parse_failed`) on every
   step**, so gen.image/fs.manage never receive valid args (proven by `m21-d0032-maxdiag-001`; floor runs the
   IDENTICAL script with gen_tier=mid and lands 3/3). The terminator handled it correctly (blocked the
   premature finishes, reported `stopped`/`succeeded=[]`, did NOT over-claim). Treat `max` as unreliable for
   the full agent until the 9B arg-gen is hardened (see #3) -- **use `floor` for end-to-end agent runs.**
2. **Two-engine setup.** `strong` (9B) uses `_engines\llama.cpp-b10092\` via the 9B entry's `engine_path`;
   every other tier uses `_engines\llama.cpp\` (b8661). BOTH dirs must exist; b8661 is kept for rollback.
   Do not "consolidate" onto b10092 without re-verifying every tier + the VLM on it (a separate unit).
3. **`strong` (9B) requires `"no_think": true`** in its `models.json` entry -- without it the gateway's
   default flags leave Qwen3.5 reasoning ON and it emits EMPTY content at `finish=length`. Do not remove it.
   **KNOWN-BAD (D-0046):** even WITH `no_think`, under `agent.local`'s longer arg-gen prompt the 9B returned
   non-JSON on every step (`arg_parse_failed` x10) in the live `max` run -- so the 9B is not yet trustworthy
   as the agent's arg-generator. Hardening this (stricter arg-gen system prompt / JSON-grammar constrain /
   a shorter arg-gen context / fall back arg-gen to mid) is a good next unit; it is what blocks `-Profile max`
   end-to-end.
4. **Intermittent orphaned `llama-server`.** The transient per-call gateway occasionally leaves a
   `llama-server` holding VRAM. If VRAM is unexpectedly occupied, kill stray `llama-server.exe`. The warm
   server (section 3b) removes this. (D-0046's floor runs + cleanup showed 0 orphans, baseline==final==0.)
5. **The 27B is retained but demoted.** `llm.strong.qwen3p5-27b` stays in `models.json` (reachable via
   `-Model`) but is no longer the strong tier; it still loads on b8661.

## 3. Continue the corrections (priority order)

Each is a normal one-scoped-unit session: probe -> build -> off-machine gate (cloud pwsh + mock) -> ship
byte-exact (sha + AST on target) -> live-test via the executor -> commit + docs + Project mirror.

### (a) FIX D-0032 -- deterministic terminator -- DONE (D-0046)

SHIPPED. Built the deterministic finish-gate (do not accept `finish` until every routed planned tool has
succeeded, else force the first unsatisfied one, capped by the step budget) + a repeat-action guard (never
re-run an already-succeeded (tool,args); finish deterministically when all planned tools are satisfied) in
`modules/21-agent-local/Invoke-AgentLocal.ps1`; new `-RequirePlannedToolsBeforeFinish` (default ON under
`-Route`), surfaced as `result.terminator`. Tests 58 -> **87/87** off-machine + on target; **floor x3 live
landed the dog on the real Desktop EVERY run** (terminator fired once, forcing fs.manage). **Residual (now
the top follow-on):** `-Profile max` still does not land because the 9B arg-generator returns non-JSON every
step (section 2#1/#3) -- a 9B/gateway hardening unit, NOT more terminator work.

### (b) Governor Phase 2 -- warm / persistent model server (RECOMMENDED NEXT)

Removes the per-call cold load AND the orphan issue -- and is the same root cause as the painful `max`
slowness seen in D-0046 (each 9B call cold-loads; a full max run took ~26 min). `model.gateway` (#7) starts a
TRANSIENT `llama-server` per call; keep a RESIDENT one, evict+load only on a real model change, measure
warm-vs-cold. With the 9B strong (~6.9 GB) + the 3B mid (~2 GB) both fitting in 11 GB, a warm server could
keep BOTH tiers resident (free tier-switching) -- validate that. See `claude/ADAPTIVE_RESOURCE_GOVERNOR.md`
-> Phase 2.

### (c) Governor Phase 3 -- auto-ramp controller

Run at the `floor` rung; ramp the envelope toward the machine ceiling only on unsolved / failed-verification;
stop at verified-success or ceiling. Decision-escalation to the 27B must be a DIRECT classify call, not the
escalator judge (measured to re-break, D-0043). See the governor doc -> Phase 3.

### (d) 9B arg-gen hardening (NEW, unblocks `-Profile max` end-to-end)

The 9B (strong) returns non-JSON for `agent.local` arg-generation despite `no_think` (D-0046). Options: a
stricter arg-gen system prompt / JSON grammar constrain in `model.gateway`; shorten the arg-gen context;
or fall arg-gen back to `mid` when `gen_tier=strong` misbehaves. Small, measurable; makes `max` land.

## 4. Return to normal progress (the roadmap)

The corrections do NOT block normal build-out -- they improve the substrate the Widgets drive. To resume,
follow `MODULE_ROADMAP.md -> Build priority`. Phase A modules (0-25, plus 27 `route.tools`, 28 `fs.manage`)
are complete; Phase B (Widgets) #1 **Local Agent Console** is done. **The next normal unit is Widget #2 --
Module Launcher / Registry Browser** (then Review/Escalation Dashboard, Voice Console, Generator Studio,
Document Workspace, System/Executor Monitor; full list + rationale in `widgets/README.md`). One scoped
Module or Widget per session (D-0029). NOTE: multi-tool agent runs are now reliable at the **floor** default
(D-0046), so a Widget driving `agent.local` is safe as long as it uses `floor` (not `max`, section 2#1).

## 5. How to choose (for the driver)

- **"Keep fixing" / reliability + speed matters** -> do **(b) Governor Phase 2 (warm server)** next -- it
  removes the per-call cold load (the ~26-min `max` run in D-0046) + the orphan risk, and is the biggest
  remaining substrate win; optionally **(d) 9B arg-gen hardening** to make `-Profile max` land end-to-end.
- **"Back to normal"** -> next roadmap unit (Widget #2); multi-tool agent runs are reliable at `floor` now.
- **Recommended:** the model + decision-floor + termination bottlenecks are solved (D-0043/D-0044/D-0046);
  the remaining substrate pain is per-call cold loads -> **Phase 2 (b)** is the highest-leverage next unit.

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

_Last updated 2026-07-27 (D-0046). D-0032 terminator SHIPPED + live-validated at the floor default (dog lands 3/3); the `-Profile max` 9B arg-gen residual is documented (section 2#1/#3, 3d). Recommended next: Governor Phase 2 (warm server)._
