# Life Orchestrator — Fan-out Orchestrator Session Handoff

**Written:** 2026-07-28, end of a session that drove fan-out iterations 7 and 8.
**For:** the next Claude instance acting as the **fan-out orchestrator** (fresh session, or Nicholas continuing).
**Repo HEAD at handoff:** `c1763c1` (branch `master`), box `DESKTOP-PF5FFMF`.

This is a session bridge. It gives you the *live* context (what just happened, what's next, what to watch
for). The **enduring** operating manual lives in the repo and the attached Project — read those too (§2).

---

## 0. TL;DR

- You are the **fan-out orchestrator**: you scope units, run `orchestrate.fanout` (#30) to emit worker
  prompts, and **Nicholas pastes each prompt into a fresh Cowork session**. You NEVER drive another AI
  session — that's the hard D-0051 boundary.
- The loop has run **8 iterations**. The last two (this session): iter 7 shipped Governor Phase 3 Stage-2
  (X0/27B rung + logprobs) and wired `-AutoRamp` into the Local Agent Console; iter 8 tried to make
  `-AutoRamp` the default and to fit a 27B quant — **both were walked back on evidence** (see §3).
- **Net state of the governor:** `-AutoRamp` (Phase 3 Stage-1/2) is **built and usable, but OPT-IN**. The
  27B/X0 rung is validated **impractical** on this 11 GB GPU. The resident **Qwen3.5-9B** is the top rung.
- **The one big open decision:** a couriered frontier report recommends upgrading the 9B from Q4_K_M to
  **Q5_K_M** (fidelity + KV headroom). That's the highest-value, lowest-risk next model change.
- **Recommended iteration 9** is in §6. **Executor is healthy** (§2). **Access needed:** one folder grant (§10).

---

## 1. Your role + the hard boundary

- `orchestrate.fanout` (#30) is deterministic scaffolding; **you supply the judgement** (what the units are,
  when to fan out, when to serialize). Built on `res.lease` (#29): a `gpu` lease, a `git` commit lock, and
  `doc:<path>` ownership.
- **Human-dispatched workers (non-negotiable):** the module emits worker prompts; Nicholas starts a fresh
  Cowork session per worker and pastes the prompt. You emit — you do not automate any external AI UI.
- **Workers report; the orchestrator mirrors the shared core-docs.** Workers use `docs:[]` and never edit
  `core-docs/`. You do the doc mirror yourself under the `git` lease (§8).

---

## 2. First 10 minutes: orient + verify the box

**Read (Project mirrors these; disk is canonical):**
1. `core-docs/START_HERE.md` — routing.
2. `core-docs/HANDOFF.md` — the go-forward map.
3. `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` — the operator guide + current frontier (kept current).
4. `core-docs/CURRENT_STATE.md` — reality as it exists now.
5. `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` — the module's operating manual (the loop, sizing, leases).
6. `core-docs/research/2026-07-28-frontier-local-model-selection.md` — the model-selection research (§5).

**Verify the executor is alive** (it's how all local work runs). In `device_bash`:
```
cd ~/mnt/LifeOrchestrator-Refresh
cat modules/00-bootstrap-executor/runtime/control/heartbeat.json   # at_utc fresh (~seconds), degraded:false
```
At handoff it was instance `f74a3ebb…` (pid 37260), continuously up all session, `degraded:false`. The
watchdog runs alongside; it hasn't had to intervene. If the heartbeat is stale, see §9 (wedge recovery).

**Note:** `device_bash` is a Linux VM with the repo mounted — it **cannot** run Windows pwsh. All pwsh runs
through the **executor** via `modules/00-bootstrap-executor/exec-job.sh` (§8).

---

## 3. Where the project stands (iterations 1–8)

Modules 0–31 are built (executor, the skill contract, observers, the model gateway #7, the audio/vision/
generator stacks, `logic.escalator` #19, `doc.io` #20, `agent.local` #21, `res.lease` #29,
`orchestrate.fanout` #30, `frontier.bridge` #31). Widgets 01–03 (Local Agent Console, Module Launcher,
Verification Console) are built. Full history: `DECISION_LOG.md` (D-0001 … D-0061).

**This session:**
- **Iter 7 (D-0060, plan fo-7-5a4c227d, 2/2):** shipped Governor Phase 3 **Stage-2** — a deadline-gated
  **X0/27B one-shot recovery rung** (opt-in `-AllowLegacy27B`) + an opt-in **logprob-entropy** signal
  (logprobs are clean on both engine builds), commit `830efcc`; and **wired `-AutoRamp` into the Local
  Agent Console** (widget 01) as an opt-in toggle + governor-trace render, `33da9a5`. A post-ship
  `.GetNewClosure()` fix (`b1f36f0`) cleared a live-GUI toggle crash. Nicholas confirmed the GUI live.
- **Iter 8 (D-0061, plan fo-8-e6f2d44f, 2/2):** two evidence-driven **walk-backs**:
  - **`-AutoRamp` default-on: TRIED (`278c088`) then REVERTED (`fbacf69`).** A real-model floor-check
    caught that, **contract-less**, the auto-ramp controller has no closing signal, so it **ignores the
    agent's `finish`** and loops to `max_steps`, returning `status=error` (the file was written, but the
    envelope errored). The strict floor finishes such a goal in 1 step. Reverted byte-exact vs `b1f36f0`;
    the controller + flag + success-contract path remain **opt-in**.
  - **27B/X0 quant: NEGATIVE RESULT (nothing shipped).** No Qwen3.5-27B quant fits GPU-bound on the 11 GB
    RTX 2080 Ti (~9.9 GB free; smallest IQ2_XXS 9.61 GB collapses quality; usable quants 12–15 GB). The
    resident 9B is the effective top rung. Probe: `modules/07-model-gateway/runtime/x0quant/probe-table.md`.

**Lesson worth internalizing:** mock/API-path gates repeatedly missed **real-model** and **rendered-UI**
failure modes (the toggle crash in D-0060; the contract-less loop in D-0061). For any unit that changes
runtime behavior or UI, do a **real-model / live-GUI verification** before writing "it works" into the docs.
This is the project's verify-cost ethos in practice.

---

## 4. The Governor — current truth (see `core-docs/ADAPTIVE_RESOURCE_GOVERNOR.md`)

- **Phase 1 (D-0043):** decide at the MID (3B) floor; `-Profile frugal|floor|max`. **DONE.**
- **Phase 2 (D-0057):** detached warm/persistent `llama-server` (warm reuse ~1 ms vs ~1200 ms cold). **DONE.**
- **Phase 3 Stage-1 (D-0059) + Stage-2 slice (D-0060):** the `-AutoRamp` controller — monotonic
  model-affine epochs **M0 (3B) → M1 (fresh-context 3B retry) → S0 (9B direct classify) → X0 (27B one-shot,
  opt-in, deadline-gated)** — closed by a **pre-frozen `lifeorch.goal_verification/0.1` success contract**;
  whole-task GPU lease; residency-key matching; a governor trace. **BUILT, OPT-IN.**
- **Known gap (D-0061):** **contract-less** `-AutoRamp` has no closing signal → it discards the agent's
  `finish` and loops to `max_steps` + errors. This is why default-on was reverted. **Fix = honor `finish` /
  apply the D-0046 deterministic terminator in the M0 epoch when no contract is supplied** (iteration 9).

---

## 5. The model stack + the frontier research (the big open decision)

- **Strong tier today:** Qwen3.5-9B **Q4_K_M**, fully GPU-resident (~6.9 GB, ~68 tok/s), on llama.cpp
  b10092. Decides 6/6 on the calibration states. The 27B is retained but **impractical** (partial-offload,
  ~2.1 tok/s) and confirmed unfittable at any usable quant on 11 GB.
- **Couriered frontier report** (ChatGPT GPT-5.6 "Sol" deep research; digest at
  `core-docs/research/2026-07-28-frontier-local-model-selection.md`): the binding budget is **KV-cache/
  context, not weight-fit**; the 9B's hybrid arch keeps KV tiny (~32 KiB/token). **Recommendation: keep
  Qwen3.5-9B; upgrade the quant to `Qwen3.5-9B-Q5_K_M` (7.11 GB)** for better fidelity with real headroom
  (`Q6_K` 7.96 GB as an alt profile). Optional specialist pool (Gemma-4-12B code, Ministral-3-14B math)
  behind a **one-active-GPU-model + warm-RAM-pool + router** design (llama-cpp-python multi-model server or
  llama.cpp `--models-dir`/`--alias` + slot save/restore + host-memory prompt cache).
- **TBD (ask Nicholas):** the report also promised **audio / image / video** model leads that were **not**
  in the couriered text — request them to inform the generator modules (#22–#25).

---

## 6. Recommended iteration 9 (the next wave)

Scope with Nicholas (he chooses direction). A natural 2-worker wave (disjoint files, 1 GPU worker):

1. **Fix contract-less auto-ramp closing, then re-enable default-on** (CPU-ish; edits `modules/21`).
   Make the M0 epoch honor the agent's `finish` / apply the D-0046 terminator when no success contract is
   supplied, so a contract-less simple goal fast-paths at M0 (1 step, `completed`) exactly like the strict
   floor. **Gate with a real-model floor-check** (a contract-less "create a file" goal → 1-step `finish`,
   `completed`, 0 swaps) — the mock harness cannot catch this. Then re-flip the default and re-validate.
2. **Stage `Qwen3.5-9B-Q5_K_M` and repoint the strong tier** in `models.json` (GPU; edits `modules/07`
   `models.json` + F: staging). A low-risk fidelity upgrade with KV headroom; re-verify the S0 6/6
   calibration + `model.gateway`/`agent.local` gates. (Optional companion: `Q6_K`.)

Bigger, optional direction (design first): **evolve `model.gateway` #7 Phase 2 into a warm multi-model pool
+ router** (one active on GPU; RAM-warm specialists; `res.lease` #29 already arbitrates the GPU). Aligns
with the governor's "ramp toward capacity" philosophy. Substantial — scope carefully.

---

## 7. Outstanding items / known defects

- **Contract-less `-AutoRamp` loops + errors** (D-0061). Fix in iter 9 (§6.1). Until then `-AutoRamp` needs
  a success contract to close; the default is the (working) strict floor.
- **The `-NoAutoRamp` alias was dropped** by the full revert `fbacf69`. `-AutoRamp:$false` is the opt-out;
  re-add the alias in the iter-9 fix if wanted.
- **Widget-03 Verification Console live-GUI GPU pass (H #3)** — running a real `model.gateway` GPU
  `run_module` item through the Verification Console GUI — is still an open residual (distinct from the
  Local Agent Console pass Nicholas did this session).
- **Audio/image/video model leads** from the frontier report — not yet provided (§5).

---

## 8. How to run the loop (mechanics cheat-sheet)

**The loop:** scope units → `plan` → relay the check-in + worker prompts to Nicholas → workers run in fresh
sessions → poll `status` until `ready_for_handoff` → `handoff` (emits a Verification Console packet + next
prompts) → **you mirror the core-docs** under the `git` lease → iterate.

**Run pwsh through the executor** (from `device_bash`, in `~/mnt/LifeOrchestrator-Refresh`):
- Write a `task.ps1` under `modules/30-orchestrate-fanout/runtime/` (heredoc), then:
  `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`
- Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s per call).
- Ship a unit: `exec-job.sh devship <id> <inputs.json> <timeout>` (sha + AST + tests, fail-closed, then
  `git add` only the named files + commit with trailers, under the `git` lease).

**`plan` worker spec** (via `-WorkersJson`): `{id, label, unit, gpu?:bool, docs:[], needs_git?:true,
skill_id?, skill_dir?, inputs?, notes}`. Rules: `docs:[]` on every worker; **≤1 GPU worker per wave**;
disjoint module files per worker; correct `inputs` for any `run_module` verification item.

**Mirroring core-docs (CRLF-safe, fail-closed):** edit on disk via an anchored Python pass in `device_bash`
(normalize `\r\n`→`\n` to match; assert each anchor occurs exactly once; re-apply CRLF; atomic
temp+rename). Then commit via an executor `task.ps1` that: acquires the `git` lease → `git add -- <named
docs>` → verifies only those are staged → `git commit -F` (trailers below) → releases. Then re-mirror to the
Project: **copy the edited docs to a FRESH never-staged path** (avoid the stale-stage gotcha, §9),
`device_stage_files` them, copy into the cwd, and `project_write` each (disk `core-docs/HANDOFF.md` →
Project `claude/HANDOFF.md`; `ADAPTIVE_RESOURCE_GOVERNOR` and `FANOUT_ORCHESTRATOR_HANDOFF` also under
`claude/`; `CURRENT_STATE`/`DECISION_LOG`/`MODULE_ROADMAP` top-level).

**Commit trailers (required):**
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: <your session URL>
```
Never `git add -A`. Git write ops go through the executor (Windows), never `device_bash` (§9).

---

## 9. Hard-won gotchas (don't relearn these)

- **The wedge:** a task that BLOCKS while holding a persistent `llama-server` orphans it and can livelock the
  executor while the heartbeat stays fresh. Launch any persistent server DETACHED so the task returns. If it
  wedges, kill the orphan **out-of-band** (Task Manager → End task on `llama-server.exe`); the executor
  self-recovers. Hardened in e5b93ab, but respect the pattern.
- **`device_stage_files` stale snapshot:** re-staging a previously-staged uploads path returns OLD bytes.
  Always stage a **fresh, never-staged** path (this session copies edited docs to `runtime/docmirror<N>/`).
- **The executor process shows as `dotnet.exe`** in Task Manager (the dotnet-tool pwsh shim), not "executor"
  — it's easy to think it died when it's fine. Trust the heartbeat, not the process list.
- **`$var:` in a double-quoted string is a parse error** (`"…=$true: …"` breaks). Use `${var}` or avoid the
  trailing colon. (Cost this session one failed task.)
- **Core-docs are CRLF;** `git` autocrlf prints a harmless "LF will be replaced by CRLF" warning on commit.
- **Git over the device mount** leaves stale `index.lock` (device_bash can't unlink). Do all git **writes**
  through the executor; use `git rev-parse`/read-only plumbing over the mount only if you must.
- **Weak local tiers under-use `finish`** (D-0032). Any loop that relies on the model self-terminating needs
  a deterministic terminator — this is exactly the D-0061 default-on defect.

---

## 10. Access / permissions (for Nicholas)

- **Every orchestrator/worker session needs exactly ONE grant: connect the repo folder**
  `C:\Users\just_\LifeOrchestrator-Refresh` (desktop app "Add folder", or approve the folder-access
  request). That single connection covers reading the repo, driving the executor (`exec-job.sh`), staging,
  and committing. Nothing else is needed at startup.
- Machine prerequisite (not per-session): the **executor must be running** (`ops/start-executor.bat` or the
  watchdog), heartbeat fresh + `degraded:false`. It is, as of this handoff.
- If spinning up a **fresh orchestrator session**: prime it with the one folder grant, have it read the §2
  docs, verify the heartbeat, then scope iteration 9 with Nicholas. If the grant can't be set remotely,
  Nicholas continues in the existing session (context is large but workable).

---

*Commits this session: iter7 `33da9a5` / `830efcc` / `b1f36f0` (+docs `1d20127`); iter8 `278c088` reverted
by `fbacf69` (+docs `c1763c1`). Plans: `fo-7-5a4c227d`, `fo-8-e6f2d44f`. Executor instance `f74a3ebb…`.*
