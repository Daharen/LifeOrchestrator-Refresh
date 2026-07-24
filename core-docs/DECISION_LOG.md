# DECISION_LOG

Owns **architectural rationale** so no instance must reread every discussion. Append-only; newest last.
Read only when a prior decision may bear on your task. **Entry fields:** id · date · decision · reason ·
alternatives · consequences · affects · state (provisional | locked) · revisit-if.

---

### D-0001 — Trusted bootstrap executor, not a sandbox
- **date:** 2026-07-24 · **state:** locked
- **decision:** The initial execution channel is a trust-based filesystem-queue executor. Queue-write
  access equals the Windows user's authority; no allowlists/approvals in-band.
- **reason:** Speed and unblocking real local work now; sandboxing is a large separate effort with its
  own failure modes. Honestly labeled risk beats a false safety claim.
- **alternatives:** OS sandbox, container, restricted runspace, HTTP service with auth.
- **consequences:** Only trusted agents/processes may write the queue. Modules are **forbidden** to add
  concealment, shutdown resistance, unauthorized propagation, monitoring evasion, or covert persistence.
- **affects:** Module 0, `PROJECT_DIRECTION.md`. · **revisit-if:** untrusted submitters become possible,
  or the executor is exposed beyond the local user.

### D-0002 — Isolated skill processes before persistent sessions
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Skills and tasks run as fresh isolated processes for now; no long-lived shared runspaces.
- **reason:** Simplicity, crash isolation, restart-recoverability; avoids shared-state bugs early.
- **alternatives:** persistent PowerShell sessions / warm model workers.
- **consequences:** Per-invocation startup cost (notably higher with the dotnet-tool pwsh shim).
- **affects:** Module 0, Module 1. · **revisit-if:** startup latency dominates a real workload
  (e.g. model warm-up) — then introduce persistent workers for that skill only.

### D-0003 — Filesystem queue before any local HTTP service
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Coordinate via atomic directory moves on one volume; no local network listener yet.
- **reason:** Zero infra, inspectable, restart-safe, no ports/auth to secure.
- **alternatives:** local HTTP/gRPC service; named pipes.
- **consequences:** Poll latency; single-volume requirement. · **affects:** Module 0.
  · **revisit-if:** cross-machine or low-latency streaming coordination is needed.

### D-0004 — Skill contract provides modularity; language does not
- **date:** 2026-07-24 · **state:** locked
- **decision:** Modularity is defined by `SKILL_CONTRACT.md` (manifest + result envelope), not by
  implementation language. C++ preferred for durable/central components; Python/PowerShell/wrapped
  binaries acceptable for faster/better MVPs.
- **reason:** Lets us ship useful MVPs immediately while keeping the option to reimplement in C++ later
  behind a stable interface.
- **alternatives:** mandate C++ (too slow to MVP); mandate one scripting language (poor fit for models).
- **affects:** all modules, `PROJECT_DIRECTION.md`, `SKILL_CONTRACT.md`. · **revisit-if:** the contract
  proves insufficient to hide an implementation swap.

### D-0005 — Contract starts minimal; grows only on real need
- **date:** 2026-07-24 · **state:** locked
- **decision:** `SKILL_CONTRACT.md` v0.1 is intentionally small. Extend only when a real module exposes
  a missing requirement; bump the contract version and log it here.
- **reason:** Avoids a speculative plugin framework nobody has stressed yet.
- **affects:** `SKILL_CONTRACT.md`, Module 1. · **revisit-if:** each new contract change.

### D-0006 — Long-horizon Proteus deferred to cold reference
- **date:** 2026-07-24 · **state:** **superseded by D-0010** (was: locked)
- **decision:** Deterministic canonical collapse, world simulation, projection, and structured memory
  are **not** near-term admission requirements. Their architecture lives in `cold-reference/` and is not
  loaded into ordinary module sessions.
- **reason:** Keep every fresh instance's context light and focused on shippable MVPs.
- **affects:** `PROJECT_DIRECTION.md`, `START_HERE.md`. · **revisit-if:** a module's value genuinely
  depends on one of those systems.

### D-0007 — Two-tier local model use with a review queue
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Weak local models do bulk classification/sorting/extraction; a stronger local model
  reviews only flagged/low-confidence/contradictory items via `REVIEW_QUEUE.md`; frontier models handle
  the hardest judgment and adjudication.
- **reason:** Proven cheaper in prior database work (on the separate Proteus game) than having strong models redo whole sets.
- **affects:** Modules 7–9, 24; `REVIEW_QUEUE.md`. · **revisit-if:** local model quality shifts enough to
  change the tier boundaries.

### D-0008 — PowerShell 7 installed per-user via .NET global tool (pinned 7.4.6)
- **date:** 2026-07-24 · **state:** provisional
- **decision:** pwsh 7 provisioned as a .NET global tool (no admin), pinned to 7.4.6.
- **reason:** No admin available; the latest tool package is malformed; this unblocked testing immediately.
- **consequences:** pwsh only on the per-user PATH; the shim reports as `dotnet.exe` (pass explicit
  `-PwshPath`). · **affects:** `CURRENT_STATE.md`, `TOOL_MODEL_REGISTRY.md`, Module 0. · **revisit-if:**
  a system-wide winget/MSI install is preferred for broader use.

### D-0009 — Module 1 skill conventions (provisional, pending contract absorption)
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Building the first reference skill (`ref.echo`) settled three conventions not spelled out
  in `SKILL_CONTRACT.md` v0.1: (1) a skill's artifact root resolves relative to the skill folder
  (`$PSScriptRoot/runtime/artifacts/<invocation_id>/`), and the envelope always reports **absolute**
  artifact paths; (2) skills accept a generic `-InputsJson '<json object>'` argument (in addition to any
  named params) so a generic wrapper need not know each skill's parameters; (3) the wrapper emits a
  `lifeorch.skill.invocation_report/0.1` object `{manifest_valid, manifest_errors, invoked, exit_code,
  envelope_valid, envelope_errors, envelope, stderr_tail}`.
- **reason:** Needed to make `ref.echo` and the generic `Invoke-Skill.ps1` interoperate without expanding
  the contract prematurely (D-0005). Kept out of the normative contract until a second skill confirms them.
- **alternatives:** amend `SKILL_CONTRACT.md` now (risked over-fitting to one skill); per-skill bespoke
  arg passing (defeats a generic wrapper).
- **consequences:** `SKILL_CONTRACT.md` stays v0.1 unchanged; these conventions live in the Module 1
  README + this entry. Fold them in (and bump the contract version) once Module 2 (`fs.observer`) exercises
  them. · **affects:** `SKILL_CONTRACT.md`, Module 1, Module 2. · **revisit-if:** Module 2 needs a different
  arg-passing or artifact-root rule.


### D-0010 — Disentangle: this project is Life Orchestrator, separate from the Proteus game
- **date:** 2026-07-24 · **state:** locked
- **decision:** This refresh repo is **Life Orchestrator** (an AI assistant / local-skills control plane),
  not Project Proteus. "Project Proteus" is a separate systemic-RPG game; the two were accidentally
  cross-named. Actions taken: rebrand project + repo folder to Life Orchestrator (folder
  `Project-Proteus-Refresh` -> `LifeOrchestrator-Refresh`), rename schema IDs `proteus.skill.*`/`proteus.review.*`
  -> `lifeorch.*`, remove the game "long-horizon vision" and delete the `cold-reference/` slot.
- **reason:** Genuinely different projects with no overlapping subject matter; the only shared thing was the
  engineering *value* of determinism. Correct the labels now, while only one module exists.
- **reference sources (kept, not built here):** the earlier assistant codebase `LifeOrchestrator\repo` — to
  fold in later when implementation makes sense; the Proteus game (`Project-Proteus-src`) — unrelated.
- **supersedes:** D-0006 (the long-horizon Proteus / cold-reference deferral was game vision, now out of scope).
- **affects:** all docs, `SKILL_CONTRACT.md` schema IDs, Module 1 code, repo/folder name. · **revisit-if:**
  we ever intentionally re-import game concepts (not expected).


### D-0011 — Module 2 confirms the D-0009 skill conventions
- **date:** 2026-07-24 · **state:** provisional
- **decision:** `fs.observer` (Module 2) independently used the D-0009 conventions (artifact-root under
  `$PSScriptRoot`, `-InputsJson` generic arg passing, and the `lifeorch.skill.invocation_report/0.1` wrapper
  report) without change. Two skills now confirm them, so they are ready to be folded into `SKILL_CONTRACT.md`
  (with a contract-version bump) as a small housekeeping pass — deferred to keep this session scoped to Module 2.
- **reason:** Validate conventions with a real second skill before promoting them to the normative contract (per D-0009/D-0005).
- **affects:** `SKILL_CONTRACT.md`, future modules. · **revisit-if:** the fold happens (bump version), or a third skill needs a different convention.

### D-0012 — First side-effecting skill (`uia.actor`): UIA patterns only, dry-run, not parallel-safe
- **date:** 2026-07-24 · **state:** locked
- **decision:** Module 5 `uia.actor` is the first skill that mutates external state. Its design is deliberately
  constrained: (1) it acts **only** through UIA control patterns (Invoke/Toggle/SelectionItem/ExpandCollapse/
  Value) plus `AutomationElement.SetFocus` — **never** synthetic global mouse/keyboard input (SendKeys,
  `mouse_event`, `keybd_event`, `SetCursorPos`); a control exposing no usable pattern yields a structured
  `pattern_unsupported` error, not a coordinate-click fallback. (2) It exposes a `-DryRun`/`-WhatIf` preview
  that resolves the element and reports the intended action + pattern support + current state **without
  performing it**. (3) It performs **one** action per invocation (no macros/sequences). (4) It declares
  `parallel_safe:false` (unlike the read-only observers) because it mutates shared desktop UI. (5) It resolves
  elements with the **same Children-scope DFS tree-walk as `uia.inspector`**, so the inspector's `path`
  (child-index) locators compose exactly, and it also supports automation_id (exact) / name (glob) /
  control_type (exact) locators with structured `element_not_found` / `ambiguous_locator` (candidate list) errors.
- **reason:** Side effects demand a safety envelope. Patterns-only keeps actions on the accessibility layer
  (deterministic, inspectable, honoring the executor's hard prohibitions — no synthetic-input evasion), dry-run
  lets a caller verify a resolution before mutating anything, and `parallel_safe:false` prevents the router from
  ever running two UI mutations concurrently against one desktop. One-action-per-call keeps side effects scoped
  and auditable; sequencing belongs to a later orchestration module (#26).
- **alternatives:** allow synthetic input as a fallback (rejected — unsafe, non-deterministic, and a
  monitoring-evasion/automation-abuse hazard the executor prohibitions warn against); combine inspect+act into
  one skill (rejected — keep the read/write halves separate per the roadmap); multi-action batch (deferred to #26).
- **consequences:** Controls without a usable pattern cannot be actuated by this skill (accept for MVP; revisit
  if a real need appears — likely via a separate, clearly-scoped input skill, not a silent fallback here). The
  property-search walk is depth/element bounded like the inspector.
- **affects:** Module 5, `MODULE_ROADMAP.md` (#5, #26), `SKILL_CONTRACT.md` (`parallel_safe` semantics for
  side-effecting skills). · **revisit-if:** a module genuinely needs synthetic input, window management, or
  multi-step UI sequences — each gets its own scoped work order.

### D-0013 — Executor watchdog is COOPERATIVE, not perpetual (Module 00.1)
- **date:** 2026-07-24 · **state:** locked
- **decision:** Module 00.1 (`exec.watchdog`) may **autonomously restart the executor on a crash or a hang
  with no approval**, but it must **stand down** — never restart — after a *deliberate* stop. "Deliberate" is
  detected from a durable authorized-stop marker the executor writes on every graceful exit: Module 0 now
  writes `control/last-exit.json {reason}` in its `finally` (`stop_requested` | `signal` | `fatal_error`) and
  refreshes `control/heartbeat.json` each loop (hang = stale heartbeat while the lock is still held). The
  watchdog restarts on `fatal_error` / hard-kill (no marker) / hung, and stands down on `stop_requested` /
  `signal`. A **perpetual** design (always restart whenever down, ignoring how it stopped) is **rejected** — it
  cannot distinguish a manual stop from a crash and would restart after a deliberate close, which is exactly the
  "shutdown resistance / re-activation / preserving access after authorization is revoked" that D-0001 forbids.
- **why this does not violate D-0001:** the watchdog heals *failures* only; an authorized stop is always
  honored. It is a plain **visible, user-launched, session-scoped** process — **no** scheduled task / service /
  Run key / startup entry, does **not** survive logout or reboot, does **not** relaunch itself, and stops on
  `watchdog.stop.requested` or when its own window is closed. It never resists its own shutdown. Crash-loop
  backoff (≤N restarts per window) prevents hammering. "Manual stop" must be *graceful* (Ctrl+C / stop-executor
  / window-close, all of which leave the marker); only a `taskkill /F` or power-loss looks like a crash.
- **alternatives:** perpetual watchdog (rejected, above); an OS Scheduled Task (rejected — that *is* boot
  persistence and is harder to reason about); the cloud agent asking the user to restart every time (rejected —
  that was the failure mode on 2026-07-24 when the executor sat dead for hours during an unattended gap).
- **consequences:** the executor gains two additive markers (Module 0 12/12 unchanged); to fully stop the
  system, stop the executor *gracefully* (the watchdog then stands down on its own) or stop the watchdog first.
  A separate **Module 0 in-process self-heal** (retrying the internal IO op whose sharing-violation caused the
  06:26 crash) was **added the same session** (`Invoke-WithFileRetry` around state-writes + finalization moves,
  plus a per-loop `IOException`/`UnauthorizedAccessException` guard; Module 0 still 12/12) — complementing the
  watchdog's external recovery (defense in depth). · **affects:** Modules 0 and 00.1, `PROJECT_DIRECTION.md` (execution channel),
  `D-0001`. · **revisit-if:** untrusted submitters become possible, or anyone proposes boot persistence / an
  ignore-manual-stop mode (do not add without revisiting D-0001).

### D-0014 — Screenshot capture (`capture.screen`): read-only screen-pixel copy, parallel-safe, PNG-first
- **date:** 2026-07-24 · **state:** locked
- **decision:** Module 6 `capture.screen` is the visual-capture complement to the UIA skills. Its MVP is
  deliberately constrained: (1) **every target reduces to one rectangle in virtual-desktop coordinates** —
  monitor (`index`/`all`/`primary`), window (hwnd/pid/title), app (process-name glob → main window), or an
  explicit rectangle — captured by a single GDI `CopyFromScreen`. (2) It is **read-only and `parallel_safe:true`**
  (unlike `uia.actor`): it **never** raises, activates, moves, resizes, or closes a window and uses **no**
  synthetic input. An occluded window therefore captures whatever covers it; a **minimized** window is a
  structured `window_minimized` error, not an auto-restore. (3) **Screen-pixel copy only** — no `PrintWindow`/
  DWM-thumbnail compositing of off-screen/occluded windows in this MVP. (4) **Capture only, no post-processing**
  — no resize/crop/annotate/OCR/base64 (those are `image.util` Module 15 and the perception modules). (5)
  **PNG default** (JPG q90 optional). (6) Per-Monitor-V2 DPI awareness is requested so captures are true
  physical pixels across mixed-DPI monitors; window bounds use the DWM extended frame (→ `GetWindowRect` fallback).
- **reason:** The sensing counterpart to Modules 4–5 must be safe to run anywhere, any time (hence read-only +
  parallel-safe — the router may capture freely without the single-writer constraint `uia.actor` needs), and
  small: a reliable screen-pixel grab that other modules (a local vision model via Module 7+, `image.util`, the
  perception stack) build on. Activating windows to get a clean shot is a side effect that belongs to a
  dedicated window module, not a sensor; auto-raising also risks the interaction surprises the executor
  prohibitions caution against. Screen-pixel copy is the smallest thing that works for the driving use case
  (foreground Unity/game/canvas windows with no UIA tree).
- **alternatives:** `PrintWindow`/DWM-thumbnail off-screen capture (deferred — per-app reliability problem, own
  work order); auto-`SetForegroundWindow` before capture (rejected — side effect; belongs to a window module);
  bundling capture with resize/crop/base64 (rejected — that is Module 15; keep capture atomic); JPG-only or
  raw-BMP (rejected — PNG is lossless and universally consumable; JPG offered only for size).
- **consequences:** Occluded/minimized/off-screen targets are not composited (documented limitation; retry when
  visible, or use a future window module). Callers needing a downscaled/cropped image for cheap vision-model
  feeding compose `capture.screen` with the future `image.util` (Module 15). `parallel_safe:true` lets the
  router run captures concurrently with each other and with the read-only observers.
- **affects:** Module 6, `MODULE_ROADMAP.md` (#6, #15), `TOOL_MODEL_REGISTRY.md`, `SKILL_CONTRACT.md`
  (`screen:true` + `filesystem:write` requirements; `parallel_safe:true` for a sensor). · **revisit-if:** a real
  need appears for off-screen/occluded compositing, window activation, cursor inclusion, or capture-time
  downscaling — each gets its own scoped work order.
