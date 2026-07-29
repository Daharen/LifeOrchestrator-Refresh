# Life Orchestrator — Fan-out Orchestrator Session Handoff (2026-07-29, evening)

**For:** the NEXT Claude instance acting as the fan-out orchestrator (fresh session — Nicholas is handing
off to keep context small). **Read this first, then the enduring docs in §2.** This supersedes the earlier
2026-07-29 note.

**Repo HEAD at handoff:** `206b2dd` (branch `master`), box `DESKTOP-PF5FFMF`. Executor healthy. No res.lease
held. Bridge was connected at handoff.

---

## 0. TL;DR

- You are the **fan-out orchestrator**: you scope units, run `orchestrate.fanout` (#30) to emit worker
  prompts, and **Nicholas pastes each into a FRESH Cowork session**. You NEVER drive another AI session
  (the hard D-0051 boundary). Workers `docs:[]`; **you** mirror the shared core-docs.
- **Deliver worker prompts + packets to Nicholas as FILES** (SendUserFile), not on-disk GUID paths — he
  could not grab on-disk prompt md's in his view (this cost a cycle in iteration 10). Stage the emitted
  prompt, copy into the working dir, SendUserFile it.
- Two units ran this session: **iteration 10** (warm multi-model pool + router, design-first) — CLOSED +
  committed + mirrored. **iteration 11** (Verification Console UX) — shipped (`206b2dd`), Nicholas
  live-tested it, found ONE bug (§4). Its **doc-mirror is NOT done yet** (your first task, §3.1).
- **Your immediate work is in §3.** The next build direction is Nicholas's call (§5).

---

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit
lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize).
**Human-dispatched workers:** the module emits prompts; Nicholas starts a fresh session per worker and
pastes it. Workers report; the orchestrator mirrors the shared core-docs under the `git` lease. ≤1 GPU
worker per wave. Ship every unit via `dev.ship` (Module 0 job-runner).

## 2. First 10 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/HANDOFF.md`,
`core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` (operator guide — **note it still says "Next = iteration 10";
that is stale until you run the §3.1 mirror**), `core-docs/CURRENT_STATE.md`,
`modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md`. For the current build direction:
`modules/07-model-gateway/WARM_POOL_DESIGN.md` (sections 6 + 9) + `DECISION_LOG.md` D-0063.

Verify the executor (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
`cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` → `at_utc` fresh, `degraded:false`. At
handoff: instance `f74a3ebb…`, pid 37260, healthy all session. `device_bash` is a Linux VM — it CANNOT run
Windows pwsh; all pwsh runs through the executor via `modules/00-bootstrap-executor/exec-job.sh`.

## 3. YOUR IMMEDIATE WORK (in order)

### 3.1 — Mirror iteration 11 into the core-docs (D-0064). NOT DONE.

Iteration 11 shipped (`206b2dd`) but the core-docs still stop at iteration 10 (D-0063). Do the mirror:
append **DECISION_LOG D-0064** (iteration 11: Verification Console UX shipped `206b2dd` — packet discovery,
by-kind item render, output locations; cloud 133/133 + CPU-live SelfTest OK; **plus the open verdict-persistence
bug in §4 as a known-issue/revisit-if**), and update `CURRENT_STATE` / `HANDOFF` /
`FANOUT_ORCHESTRATOR_HANDOFF` for iteration 11. Then re-mirror those to the Project. **Mechanics in §6.**
(The iteration-10 mirror this session is your worked example — same anchors, same CRLF-safe pattern.)

### 3.2 — The Console verdict-persistence BUG (Nicholas found it live). Recommended = iteration 12.

**Symptom (Nicholas, verbatim intent):** in the Verification Console, tick the checklist + set **Overall
verdict = pass**, click **Save item verdict**, select a different item, then return to the first item →
the checklist shows **unticked** and Overall verdict shows **skipped** (defaults). Unknown whether the
exported result JSON still holds the saved values (a view-only restore bug) or the data is actually lost —
**the fix must determine which and handle both.**

**Likely location (I traced it):** `widgets/03-verification-console/Show-VerificationConsole.ps1` —
`Show-SelectedItem` (saves the outgoing item via `Save-CurrentItemVerdict`, then loads the incoming item's
saved state into the controls) and `Save-CurrentItemVerdict`. The restore path re-ticks the **checklist**
(`$checked = ([string]$c.verdict -eq 'pass')`) but does **not** appear to restore the **Overall-verdict
combo** (no `$s.overallCombo.SelectedItem = $st.overall` on select) — and the iteration-11 worker rewrote
~221 lines in exactly this area, so treat it as a **regression from `206b2dd`**. Also verify the per-item
saved state (`$st`) is persisted into a store keyed by item id that survives navigation AND flows into
`New-VerificationResult` / Export.

**Fix scope (a small CPU widgets/03 unit):** on item-select, restore ALL of {checklist checks, Overall
verdict combo, notes} for the selected item from its saved state; ensure Save persists per-item across
selections and into Export; add a core test (save item A → select B → re-select A → assert restored state ==
saved) and an Export-contains-verdicts assertion; then a **human live-GUI re-confirm** (the D-0049/D-0060
lesson: mock/API gates miss rendered-UI bugs — this bug slipped the 133/133 gate for exactly that reason).

### 3.3 — Then scope the next BUILD unit with Nicholas (§5).

## 4. Iteration 11 as shipped (for the D-0064 entry)

Plan `fo-11-4dbc8dce` (1 CPU worker `VC-ux`, 0 conflicts). Commit `206b2dd` — 4 files, +602/-28:
`widgets/03-verification-console/` VerificationConsole.psm1 (+302; new core fns `Get-RecentPackets` /
`Get-ItemActionModel` / `Get-ReferencedPaths`, unit-tested), Show-VerificationConsole.ps1 (+221),
tests (+84), README. Delivered: Open-latest + Recent-packets picker + default browse dir; human_action
Run-disabled + Open affordance; plain-language INVALID; run_module Run enabled; artifact_root + plan_id/
report_back/source in the header. Gate cloud 133/133 + CPU-only live SelfTest OK. **Open bug: §3.2.**
Iteration 11 `handoff` was NOT formally run (verification was Nicholas's live-GUI pass) — you may run
`-Action handoff -PlanId fo-11-4dbc8dce` if you want a packet, but it is optional.

## 5. The next build direction (Nicholas chooses)

- **RECOMMENDED first: fix the §3.2 Console verdict bug** (small, CPU, widgets/03) — the audit surface must
  reliably save verdicts before it is trusted for real verification.
- **Then: Warm pool Stage-1 (the big build).** A **READY dispatch package** exists at
  `claude/iter11-stage1-DRAFT.md` (⚠ filename says "iter11" but iteration 11 became the Console UX unit —
  **renumber it to the next free iteration when you dispatch**). It builds the **named pool manager
  (mechanism C)** extending the D-0057 detached warm server, per `WARM_POOL_DESIGN.md` §6 + §9. Mechanism C
  is **confirmed** by the couriered ChatGPT Pro second opinion (D-0063): native `--models` router (A) is
  only a supervisor — it does NOT remove the ~4 s GPU upload; B rejected. All the policy (residency key,
  task-affinity epochs, whole-task lease, 90 s keep-resident, 16K f16 KV default, engine b10092 fixture
  test, coding-specialist-behind-a-benchmark) is in `WARM_POOL_DESIGN.md` §9. It is a GPU worker (≤1/wave).
- **Also outstanding:** request the frontier report's **audio/image/video model leads** from Nicholas (they
  were not in the couriered text) to feed generators #22–#25.
- **Backlog:** portability / new-machine bring-up (a scoped setup.ps1 unit; do before a hardware upgrade).

## 6. Mechanics cheat-sheet

**Loop:** scope → `plan` → relay the ONE check-in + each worker prompt **as FILES** → workers run in fresh
sessions (acquire leases gpu→git→doc, do one unit, `dev.ship`, `-Action report -State done`) → poll
`-Action status -PlanId <id>` until `ready_for_handoff` → `-Action handoff` → **you mirror the core-docs**.

**Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1`
under `modules/30-orchestrate-fanout/runtime/`, then
`bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`. Long/GPU
jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s). Ship a unit: `exec-job.sh devship …`.
Author a plan by writing `workers-i<N>.json` (per-worker `{id,label,unit,gpu?,docs:[],needs_git?,skill_id?,
skill_dir?,inputs?,notes}`) + a `task-plan-i<N>.ps1` (copy `task-plan-i10.ps1`), run it, confirm
`dispatch_now`/0-conflicts/clean-preflight.

**Doc mirror (CRLF-safe, fail-closed):** the core-docs are CRLF (the worker's `WARM_POOL_DESIGN.md` is LF —
per-file EOL). Edit on-device with a fail-closed Python pass (assert each anchor occurs exactly once; atomic
write; preserve per-file EOL — see this session's iter-10 mirror for the exact pattern: appends for
DECISION_LOG/new sections, `sub_once` for CURRENT_STATE/HANDOFF anchored prepends, whole-line replace for
FANOUT_ORCHESTRATOR_HANDOFF's `## Where things stand` + `**Next =` lines). Then commit via an executor
`task.ps1` that acquires the `git` lease → `git reset -q` → `git add -- <named docs>` → assert only those
staged → `git commit -F <msg>` → release. **Trailers required:**
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: <url>`. Never `git add -A`.
Then re-mirror to the Project: `device_stage_files` the edited core-docs (fresh — never re-stage a prior
path, stale-snapshot gotcha), copy into the working dir, `project_write` with `local_path` (keeps big
content out of your context). Project paths: `CURRENT_STATE.md`/`DECISION_LOG.md`/`MODULE_ROADMAP.md`
top-level; `HANDOFF.md`, `FANOUT_ORCHESTRATOR_HANDOFF.md`, `ADAPTIVE_RESOURCE_GOVERNOR.md` under `claude/`.

## 7. Gotchas (don't relearn)

- **Deliver prompts/packets as FILES** (§0) — the #1 UX lesson this session.
- **The wedge:** a task that BLOCKS holding a persistent llama-server orphans it + can livelock the executor.
  Launch persistent servers DETACHED; reap before finalize; assert 0 orphans. If wedged, kill the orphan
  out-of-band (Task Manager → End task `llama-server.exe`).
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes. Stage a
  fresh/never-staged path.
- **`project_write local_path` must be inside the working directory** (e.g. `/home/claude/…`), not `/tmp`.
- **`-Action status` once returned no artifact** via `exec-job.sh run` this session (harmless — the worker's
  `report` file under `plans/<id>/reports/` is the source of truth; read it directly).
- **Rendered-UI bugs slip mock/API gates** (D-0049/D-0060 + the §3.2 verdict bug). Any UI change needs a
  human live-GUI confirm before "done" in the docs.
- The executor process shows as `dotnet.exe`; trust the heartbeat, not the process list.

## 8. Box state at handoff

HEAD `206b2dd` (master). Executor `f74a3ebb…` healthy (`degraded:false`). No res.lease held (gpu/git free).
The large `git status` M-list over the Linux mount is CRLF noise — authoritative state is clean on Windows;
do git writes through the executor. Iteration plans: `fo-10-fbfbae02` (done, mirrored), `fo-11-4dbc8dce`
(done, mirror pending §3.1). Access to resume: connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh` (one grant), verify the heartbeat, then start at §3.1.
