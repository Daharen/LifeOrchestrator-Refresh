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
- **date:** 2026-07-24 · **state:** **folded into `SKILL_CONTRACT.md` v0.2 by D-0028** (was: provisional)
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
- **date:** 2026-07-24 · **state:** **folded into `SKILL_CONTRACT.md` v0.2 by D-0028** (was: provisional)
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

### D-0015 — Large model/data lives on F: as portable per-module copies; C: repo stays small
- **date:** 2026-07-24 · **state:** locked
- **decision:** Model weights and any module data >~50 MB do **not** live in the C: repo (C: is space-constrained:
  ~67 GB / 7.5% free). They live on the **F:** drive under `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\`
  (matching the user's existing `<App>_Large_Data` convention), mirroring the repo's `modules\` layout for big data.
  Skills resolve models by **absolute F: paths** recorded in their registry (config, not code) — not via links —
  so a moved model is a one-line path edit. Human navigation is served by two `.lnk` shortcuts (repo `modules\` →
  F: root, and back). Because several **original** model folders are obsolete side-projects the user may delete
  (`F:\Qwen3.5-27B`, `F:\Local_TTS_Large_Data`, the ACE-Step suite), models are **copied** (non-destructive) into a
  staging area `…\_pending-model-storage\` so nothing depends on those originals. As each **owning** module is built,
  its model(s) move from staging into `…\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\`; **when
  `_pending-model-storage\` is empty it is deleted** (see its `MIGRATION.md`). The **inference engines** are staged
  too (the llama.cpp `build\bin\`, verified to run standalone) for the same portability reason.
- **reason:** Keep the git repo lean and portable; decouple the project from doomed source folders; make model
  selection/relocation trivial (paths in a registry). Copies (not in-place references) are the user's explicit
  requirement — stale references to torn-down folders would silently break skills.
- **alternatives:** reference models in place on F: (rejected — couples to obsolete folders); copy into the C: repo
  (rejected — no space, and git would try to track GBs); OS symlinks/junctions for resolution (rejected — abs paths
  in the registry are simpler and inspectable; `.lnk` shortcuts are for humans only).
- **consequences:** `_pending-model-storage\` currently holds ~27.4 GB (engine + 4 LLM GGUF + whisper + 2 TTS +
  tokenizer + embedding). A future session must actually relocate + de-stage as modules are built. The staged engine
  depends on a system CUDA runtime (see REVIEW_QUEUE). · **affects:** `TOOL_MODEL_REGISTRY.md` (inventory + large-data
  section), Modules 7/11/12/23, repo `.gitignore` (`*.lnk`). · **revisit-if:** C: space is freed, or a module needs a
  large-data layout the `<NN>-<module>\` scheme doesn't cover.

### D-0016 — model.gateway wraps llama-server per call; declares all modalities, wires LLM; heuristic confidence
- **date:** 2026-07-24 · **state:** locked (engine choice), provisional (confidence heuristic)
- **decision:** Module 7 `model.gateway` is the common local-model interface. MVP design: (1) **run local LLMs via
  the llama.cpp `llama-server`** — start a server on a free loopback port → wait for `/health` → POST
  `/v1/chat/completions` → parse → **always kill the server** (one isolated server per call, D-0002). Chosen over
  `llama-cli` because this build (b8661) made `llama-cli` an interactive chat tool (rejects `-no-cnv`, decorates
  stdout); the server returns **clean structured JSON** (content, `finish_reason`, token `usage`, `timings`) — better
  for provenance and confidence. (2) A **declarative registry** (`models.json`) **declares every discovered model**
  (LLM×4, STT, TTS×2 + tokenizer, embedding) but only **wired LLMs execute**; non-wired/non-LLM returns a structured
  `model_not_wired` error naming the future module (STT→11, TTS→12, embed→23). Selection is explicit (`model_id` or a
  `tier` alias) — **no auto "which model is best"** (that is routing, Module 24). (3) First **stochastic/mixed** skill:
  populate `model_provenance[]` (id/version/params/tokens/timings/finish_reason/device) and **`confidence`** via a
  **documented generation-completeness heuristic** (stop→0.7, length→0.4, empty→0.1), NOT semantic correctness;
  `< 0.5` → append to the review queue.
- **reason:** Smallest useful MVP that unblocks Modules 8–9 (they need local LLM text). Wrapping the existing server
  (not reimplementing) fits the language policy; structured JSON gives honest provenance. Declaring-but-not-wiring the
  other modalities keeps scope tight while recording what exists.
- **alternatives:** `llama-cli --single-turn` + stdout parsing (rejected — decorated/fragile output, no token/stop
  metadata); a persistent warm server shared across calls (deferred — D-0002; revisit if load latency dominates, e.g.
  the 27B); wiring STT/TTS/embedding now (deferred to their modules); logprob/self-consistency semantic confidence
  (deferred — heuristic first, per the stochastic-then-harden doctrine).
- **consequences:** `parallel_safe:false` (a per-call server binds a port + most of VRAM); `determinism:"mixed"`;
  per-call model-load cost (fine for small models; the 27B is slow + partial-offload). The confidence number is only a
  completeness signal — consumers should read `model_provenance` for the real detail. · **affects:** Module 7,
  Modules 8/9/24, `SKILL_CONTRACT.md` (`confidence`/`model_provenance` first real use), `REVIEW_QUEUE.md`.
  · **revisit-if:** load latency forces warm workers; a semantic confidence is needed; routing (Module 24) subsumes
  tier selection.

### D-0017 — classify.batch: per-item gateway calls, suppress the gateway's review writes, classification confidence
- **date:** 2026-07-24 · **state:** locked (gateway-consumption + suppression), provisional (confidence heuristic)
- **decision:** Module 8 `classify.batch` is the **first real consumer of `model.gateway`** and sets the pattern for
  every downstream skill that runs a local model over many inputs. MVP design: (1) **one gateway call per item** —
  for each `{id?,text}` it builds a mode-specific prompt (`classify` = exactly one label from a closed set, also
  routing/sorting; `multilabel` = zero+ labels; `extract` = named fields → JSON), spawns `Invoke-ModelGateway.ps1`
  as a child (default `-Tier weak`=1.5B, temp 0, fixed seed), and parses the completion. It **never** binds a port or
  loads a model itself — it goes *through* the gateway (the point of being the first consumer). (2) **A
  classification-appropriate confidence**, distinct from the gateway's generation-completeness signal: a documented
  completeness+validity heuristic combining in-set match / valid JSON with the gateway's `finish_reason` (classify
  in-set+stop 0.8 / fuzzy 0.6 / out-of-set 0.2 / empty 0.1; multilabel 0.75/0.7/0.5/0.15; extract 0.75/0.5/0.3/0.1;
  a `length` truncation caps the item ≤0.4). `< threshold` (default 0.5) → one `lifeorch.review.item/0.1` per item
  with a per-item `source_ref`. (3) **classify.batch is the sole, correctly-attributed author of the batch's review
  items** — it points the gateway's `-ReviewQueuePath` at a discardable in-artifact `_gateway_review_suppressed.jsonl`
  so the gateway's own `<0.5`-completeness appends do **not** land in the canonical queue (which would double-flag and
  mis-attribute). (4) `determinism:"mixed"`, `batch:true`, `parallel_safe:false` (it drives the gateway → GPU/port
  contention). Envelope `confidence` = mean per-item; `model_provenance[]` = one **aggregate** entry (summed tokens,
  call count, total runtime) to keep the envelope bounded.
- **reason:** Smallest useful MVP that proves weak local models do useful unattended bulk work, and does it *through*
  the gateway so model choice stays a one-line config change (D-0016). Per-item calls give honest per-item confidence,
  provenance, and review routing; batching many items into one prompt is fragile on 0.5B/1.5B models and muddies
  per-item confidence. Suppressing the gateway's review writes keeps the queue single-authored per producer, which
  Module 9 relies on.
- **alternatives:** batch all items into one gateway prompt (rejected for the MVP — unreliable multi-item JSON on weak
  models, harder per-item confidence/truncation; a documented follow-on behind a warm gateway); talk to `llama-server`
  directly from classify.batch (rejected — reimplements + bypasses the gateway, breaks modularity); let the gateway
  write to the canonical queue too (rejected — double-flag + wrong `flagged_by`); calibrated/logprob confidence
  (deferred — heuristic first, per the stochastic-then-harden doctrine); physically moving files into per-label folders
  (rejected — that flips filesystem to write and changes the safety posture; belongs to a separate `sort.files` skill).
- **consequences:** batch throughput is bounded by the gateway's per-call model load (D-0002/D-0016) — fine for
  small/unattended batches, and it creates concrete pressure to build a warm/persistent gateway worker. The review
  queue now has **two producers** (`model.gateway`, `classify.batch`); Module 9 must handle both `flagged_by` values.
  The confidence is a completeness+validity signal, not correctness — consumers should read the per-item fields.
  · **affects:** Module 8, Modules 7/9/24, `REVIEW_QUEUE.md`, `TOOL_MODEL_REGISTRY.md`. · **revisit-if:** load latency
  forces a warm worker / intra-batch prompt; a calibrated confidence is needed; a side-effecting file-sorter is built;
  routing (Module 24) subsumes tier selection.

### D-0018 — review.processor: single-item adjudication, update-in-place + append-log, escalation-as-status-transition
- **date:** 2026-07-24 · **state:** locked (adjudication scope + write model + escalation), provisional (reviewer confidence heuristic)
- **decision:** Module 9 `review.processor` is the **first consumer/drainer** of `review_queue.jsonl` and sets the
  pattern for how flagged items are resolved. MVP design: (1) **single-item adjudication** — it selects OPEN items
  (bounded `-MaxItems`; `-FlaggedBy`/`-Reason`/`-Ids` filters; handles **both** `flagged_by` producers) and, per item,
  calls `model.gateway` **once** with a **stronger** model (default `-Tier mid`=Qwen2.5-3B; `strong`=27B), feeding it
  **only** the distilled item: `reason`/`requested`/`weak_result` + a **bounded fragment resolved from `source_ref`**
  (`classify.batch` `classified.json#<id>` → the closed label set + that one item; `model.gateway` `exchange.json` →
  bounded request/output), **never the whole batch** (honors D-0007 / `REVIEW_QUEUE.md`). (2) **A structural reviewer
  confidence** (valid-JSON `{verdict,answer,confidence,escalate,rationale}` + in-set corrected answer + generation
  completeness; a `length` truncation caps ≤0.4), NOT calibrated correctness. (3) **Escalation is a status
  transition, not a frontier call** — below `-EscalateThreshold` (default 0.5), or an explicit model-escalate, or an
  unparseable verdict → `status:"escalated"`, `escalated_to:"frontier"`; the frontier drains those separately. (4)
  **Write model:** the live queue is **updated in place** (re-read immediately before an atomic
  `[System.IO.File]::Move(...,overwrite)`; only adjudicated still-`open` lines change to carry `status`+`resolution`+
  `escalated_to`; original flagging fields and all other/producer/**malformed** lines pass through verbatim) **and**
  an immutable `lifeorch.review.resolution/0.1` record per adjudication is appended to `review_resolved.jsonl`. This
  is the deliberate answer to "append vs update-in-place": **update the live status in place** (so re-runs skip
  resolved items and the queue stays small) **plus an append-only history log** (so nothing is destroyed). `-DryRun`
  writes neither. (5) It **suppresses the child gateway's own review writes** (in-artifact `-ReviewQueuePath`) so
  draining never grows the queue, and exposes a **`-LoadTimeoutSec` passthrough** for the slow strong tier.
  `determinism:"mixed"`, `batch:true`, `parallel_safe:false`.
- **reason:** Closes the two-tier loop (D-0007) cheaply: a stronger local model settles most flagged items from a
  single distilled record, and only genuine residue reaches the frontier. In-place status keeps the live queue small
  and re-runnable; the append-only log preserves the audit trail the "never rewrite history" convention protects.
  Going *through* the gateway (not `llama-server` directly) keeps model choice a one-line config change and mirrors
  the Module 8 consumer pattern.
- **alternatives:** append a resolution record and leave the item open (rejected — re-runs would re-pick the open
  line forever / duplicate ids; the schema's `status`+`resolution` slots intend in-place transition); rewrite the
  whole queue destructively (rejected — loses producer appends during the run and the original flagging fields; the
  re-read-before-atomic-replace + verbatim passthrough avoids this); have `review.processor` call a frontier model
  itself (rejected — that is routing, Module 24; escalation stays a status transition); a real lock / `in_review`
  claim protocol for concurrent drainers (deferred — the single-background-drainer case is covered; noted follow-on);
  calibrated/semantic reviewer confidence (deferred — heuristic first, per the stochastic-then-harden doctrine).
- **consequences:** The 27B **`gpu_layers` was tuned 28→32** and a cold 27B load (~90s, ~2 tok/s) can exceed the
  gateway's 120s default, hence the `-LoadTimeoutSec` passthrough (see REVIEW_QUEUE). A thinking-style strong model
  may exhaust `max_tokens` before emitting the JSON verdict → it is safely **escalated** rather than mis-resolved
  (observed in `m9-test-003`); a strong-tier prompt/token follow-on is logged. The write-back re-reads immediately
  before an atomic replace but is **not** a full concurrency protocol — fine for the single background drainer this
  phase intends; a lock is a noted follow-on. · **affects:** Module 9, Modules 7/8/24, `REVIEW_QUEUE.md`,
  `TOOL_MODEL_REGISTRY.md`, `models.json` (27B gpu_layers). · **revisit-if:** concurrent drainers/producers need a
  lock; a frontier `route.tasks` (#24) drains `escalated`; resolved-item compaction is built; a calibrated reviewer
  confidence is needed; a warm gateway worker lands.

### D-0019 — audio.ingest wraps ffmpeg/ffprobe; deterministic; whisper-ready defaults; sibling-ffprobe resolution
- **date:** 2026-07-24 · **state:** locked (wrap-the-binary + resolution + defaults), provisional (format/loudness surface)
- **decision:** Module 10 `audio.ingest` — the first audio-track module and the **first skill to wrap an external
  executable** rather than reimplement — normalizes+converts one audio/media file by driving `ffmpeg` (+`ffprobe`).
  MVP design: (1) **one input → one output**; the **first audio stream** is used (audio extracted from video via
  `-vn -map 0:a:0`); target `-Format` ∈ {wav,mp3,flac,opus,ogg,m4a} with the right codec per container, plus
  `-SampleRate`/`-Channels`/`-SampleFormat` (wav) normalization and optional `-Loudness` (`none` | `peak`, a two-pass
  `volumedetect`→`volume` gain to `-PeakDb` | `ebu`, EBU R128 `loudnorm`). (2) **Defaults are whisper-ready** —
  wav / 16000 Hz / mono / s16 / no loudness — so Module 11 (`speech.stt`, whisper.cpp) consumes the output directly
  with no flags. (3) **`ffprobe` is resolved as the sibling of the resolved `ffmpeg`** (param → `Get-Command ffmpeg`
  → known dirs; ffprobe = sibling → non-`Python\Scripts` `Get-Command`), deliberately dodging the Python
  `…\Python310\Scripts\ffprobe.exe` shim that shadows the real ffprobe on this machine's PATH. (4)
  `determinism:"deterministic"` (a fixed transcode of fixed bytes by a fixed tool — `confidence` null,
  `model_provenance` empty) and **`parallel_safe:true`** (reads an input, writes only its own invocation artifact
  dir; no shared external state, unlike `uia.actor`/`model.gateway` — it is CPU-bound, so heavy fan-out contends CPU
  only). (5) Child ffmpeg/ffprobe run via `ProcessStartInfo.ArgumentList` (per-arg escaping; spaces safe) with both
  streams drained asynchronously (avoids the documented pipe-fill deadlock); the exact `argv` is recorded in the
  envelope. `-map_metadata -1` (+`-bitexact` for wav) drops input metadata for clean, reproducible output.
- **reason:** Smallest useful MVP that unblocks the whole audio track: a reliable normalize/convert primitive the
  STT/TTS/voice modules can assume. Wrapping the present, full-featured ffmpeg (rather than a PCM library) fits the
  language policy (wrap existing binaries) and covers every needed codec at once. Whisper-ready defaults make the
  very next module a one-liner. Sibling-ffprobe resolution is the honest fix for a real PATH hazard on this box.
- **alternatives:** reimplement decode/resample in a library (rejected — ffmpeg already solves it, portably);
  trust `Get-Command ffprobe` (rejected — returns the Python shim first); make it `parallel_safe:false` like the
  GPU/port skills (rejected — no shared resource is bound; CPU contention is a scheduling concern, not correctness);
  bundle trimming/denoise/segmentation now (rejected — scope; → Module 13 / follow-ons); pipe ffmpeg stdout to
  capture the audio (rejected — file output + async stderr drain is simpler and deadlock-free).
- **consequences:** the review queue is untouched (a deterministic skill flags nothing). Throughput is per-call
  ffmpeg spawn (fine; no warm worker needed for a CPU transcode). Registry gains an `ffmpeg`/`ffprobe` tool entry
  and an `audio.ingest` skill entry. · **affects:** Module 10, Modules 11–13, `TOOL_MODEL_REGISTRY.md`,
  `MODULE_ROADMAP.md`. · **revisit-if:** a batch/streaming path, trimming/segmentation, or denoise/EQ is needed
  (each its own scoped follow-on); ffmpeg is upgraded/relocated (resolution already dynamic).

### D-0020 — speech.stt wraps whisper.cpp; mixed determinism; token-probability confidence; per-segment review producer
- **date:** 2026-07-24 · **state:** locked (wrap-the-binary + normalization + registry-read + review model), provisional (confidence heuristic)
- **decision:** Module 11 `speech.stt` — the second audio-track module and the first **stochastic/mixed** skill to wrap a
  local **model** binary (vs. Module 7's server) — transcribes one audio file with timestamps by driving the whisper.cpp
  `whisper-cli`. MVP design, settled after a **probe-first** pass (`m11-probe-001/002` confirmed this build's exact flags
  and JSON before any code — the CUDA build loads headless and prints the RTX 2080 Ti; both CUDA + CPU builds support
  `-oj/-ojf/-osrt/-otxt/-of/-np/-l/-ng`; do **not** assume flags, per the llama.cpp interactive-only lesson): (1) **run
  `whisper-cli -ojf`** (full JSON incl. per-token linear probability `p`) `-osrt -otxt -of <base>` and parse the
  `transcription[]` into timestamped segments `{index,t0_ms,t1_ms,t0,t1,text,confidence,token_count,low_confidence}`.
  (2) **Confidence = mean whisper token probability `p`** over content tokens (whisper special tokens `[_…_]` excluded),
  per segment and overall — a genuine **acoustic** signal (richer than the gateway's generation-completeness heuristic),
  but NOT calibrated correctness. Populate envelope `confidence` (overall) + `model_provenance[1]` (id/engine/build/device,
  decode params, audio duration, segment/token counts, runtime, real-time factor, whisper systeminfo). (3) **Review-queue
  producer on low-confidence segments** (the **third** producer, after 7/8): one `lifeorch.review.item/0.1` per segment
  below `-SegmentConfidenceThreshold` (default 0.5), `flagged_by:"speech.stt"`, `requested:"verify_transcription"`,
  `source_ref:"…/transcript.json#seg<i>"`, **bounded** by `-MaxReviewSegments` (default 25, worst-first, truncation
  noted) so a long noisy file cannot flood the queue; a zero-segment result from ≥`-MinSpeechSeconds` audio emits one
  `uncategorized`/`verify_no_speech` item (silent-failure guard). A **text** reviewer (Module 9) can judge transcript
  plausibility even without the audio. (4) **Input normalization via `audio.ingest`** (`-Normalize auto|always|never`):
  `auto` probes the input (sibling-of-ffmpeg ffprobe, per D-0019) and only re-encodes when it is not already WAV/16 kHz/
  mono/s16, feeding whisper-ready audio directly otherwise — composing the audio track (Module 10 → 11) exactly as
  intended. `speech.stt` spawns `audio.ingest` as a child `pwsh` (mirroring `classify.batch`'s gateway spawn). (5)
  **Registry-driven, but decoupled from the gateway's `wired` gate:** it resolves the model `path` + whisper
  `engine_candidates` (CUDA build preferred, CPU fallback) from `models.json` — but the STT entry stays **`wired:false`**
  there on purpose (the gateway MVP runs `type=llm` only, so it still returns `model_not_wired` for STT; Module 7's tests
  assert exactly that). Added `defaults.stt`/`tiers.stt` (additive; llm resolution untouched — Module 7 re-verified 28/28).
  `determinism:"mixed"`, `parallel_safe:false` (binds the CUDA context, like `model.gateway`), `batch:false`.
- **reason:** Smallest useful MVP that unblocks the rest of the audio/voice track (TTS #12, voice.live #13) and feeds text
  consumers (`classify.batch`/`review.processor`): a reliable timestamped transcript with an honest per-segment confidence
  and cheap review routing. Wrapping the present whisper.cpp (not reimplementing) fits the language policy; token-`p`
  confidence is a real signal the gateway lacked. Reading the model from the registry keeps model choice a one-line config
  change (D-0016 philosophy) without touching the gateway's execution gate. Auto-normalization makes the common case a
  one-liner while staying robust to arbitrary inputs.
- **alternatives:** feed arbitrary audio straight to whisper and rely on its internal resampling (rejected for the default —
  `auto` normalization via the proven `audio.ingest` is deterministic and container-agnostic; `never` remains for callers
  who know their input is ready); flip the STT entry `wired:true` (rejected — breaks Module 7's `model_not_wired`
  assertion and misstates that the *gateway* can run it; speech.stt reads the entry directly instead); flag the whole
  invocation once rather than per segment (rejected — per-segment matches the producer pattern of 7/8 and gives a reviewer
  a concrete unit; bounded to avoid flooding); one review item per low token rather than per segment (rejected — too
  granular for a text reviewer); calibrated/semantic confidence, word-level artifacts, VAD/diarization/batch (deferred —
  heuristic-first per the stochastic-then-harden doctrine; segmentation → Module 13).
- **consequences:** the review queue now has **three** producers (`model.gateway`, `classify.batch`, `speech.stt`); Module 9
  already drains by `flagged_by` and handles new producers by construction (the new `requested:"verify_transcription"`/
  `"verify_no_speech"` verbs and a null-confidence no-speech item are passthrough for the adjudicator). Throughput is a
  per-call `whisper-cli` spawn (base.en on CUDA ≈ 0.07 real-time factor — 11 s of audio in ~0.7 s; a warm whisper-server
  is a follow-on if load latency ever dominates). Registry gains `defaults.stt`/`tiers.stt` + a whisper.cpp runtime entry.
  · **affects:** Module 11, Modules 10/12/13/9, `TOOL_MODEL_REGISTRY.md`, `models.json`, `REVIEW_QUEUE.md`,
  `MODULE_ROADMAP.md`. · **revisit-if:** a warm whisper worker, batch/streaming, calibrated/semantic confidence, VAD/
  diarization, or a larger/multilingual STT model is needed (each its own scoped follow-on); a unified model gateway ever
  subsumes STT execution.

### D-0021 — speech.tts wraps Qwen3-TTS via a Python worker; mixed determinism; synthesis-completeness confidence; fourth review producer
- **date:** 2026-07-24 · **state:** locked (Python-worker + wrap + registry-read + review model), provisional (confidence heuristic)
- **decision:** Module 12 `speech.tts` — the third audio-track module and the **first skill to drive a Python model**
  (vs. the whisper.cpp / llama.cpp *binaries*) — synthesizes speech from text with the **Qwen3-TTS CustomVoice** models
  (`qwen_tts` package / transformers, under the speech venv). MVP design, settled after a **probe-first** pass
  (`m12-probe-001/002` confirmed the venv (torch 2.11+cu128, transformers 4.57.3, `qwen_tts`, soundfile, CUDA on the
  RTX 2080 Ti), the model layout, and — critically — the real inference API by *doing a live synthesis* before writing
  the skill: `qwen_tts.Qwen3TTSModel.from_pretrained(path, device_map="cuda:0", dtype=bfloat16, attn_implementation=
  "sdpa")` then `generate_custom_voice(text, speaker, language, instruct) -> (List[np.ndarray], sr=24000)`; flash-attn is
  absent so `sdpa` is the attn; no local `*.py`/trust_remote_code). Design: (1) a **two-part** skill — a Python worker
  (`tts_infer.py`, run under the venv) loads the model + synthesizes + writes the WAV and a small JSON meta; a
  **PowerShell wrapper** (`Invoke-SpeechTts.ps1`) builds the contract envelope. The wrapper spawns python and reads the
  **meta file** (not stdout) so transformers/qwen_tts console chatter can never corrupt the parsed result. (2) Output is
  a **24 kHz mono PCM16 `speech.wav`** at the model's native rate; a requested non-wav `-Format` or non-24k
  `-SampleRate` is produced by composing **`audio.ingest`** (Module 10) — the audio track wired the other direction
  (11 consumes audio.ingest; 12 feeds it). (3) **Confidence = a documented synthesis-completeness heuristic** (audio
  produced + plausible duration vs. input length: empty/near-silent 0.1, far-too-short 0.3, short 0.5, plausible 0.9) —
  NOT audio quality; a conservative lower bound (~0.03 s/char) so only clearly-failed synthesis flags. (4) **Fourth
  review-queue producer** — a synthesis below `-ConfidenceThreshold` (default 0.5) appends one `lifeorch.review.item/0.1`
  (`flagged_by:"speech.tts"`, `reason` `failed_transform`≤0.15 else `low_confidence`, `requested:"verify_synthesis"`) —
  a failed-synthesis guard. (5) **Registry-driven, decoupled from the gateway's `wired` gate** (mirrors D-0020): resolves
  the model `path` + `engine_env` (the venv python) from `models.json`, but the TTS entries stay **`wired:false`** there
  (the gateway MVP runs `type=llm` only). Added `defaults.tts`/`tiers.tts` (additive; Module 7 re-verified 28/28).
  `determinism:"mixed"` (deterministic orchestration; the model samples with `do_sample=true`, seedable via `-Seed`),
  `parallel_safe:false` (binds the CUDA context + loads a model), `batch:false`.
- **reason:** Smallest useful MVP that gives the system a voice and completes the STT↔TTS pair (with Module 11) that a
  future `voice.live` (#13) composes. Wrapping the present `qwen_tts` package (not reimplementing a TTS stack) fits the
  language policy (Python for model ecosystems); the worker+wrapper split keeps the contract envelope in PowerShell (like
  every other skill) while the model lives in its native Python. The meta-file hand-off is the robust answer to
  "stdout gets polluted by ML libraries". Composing `audio.ingest` for format conversion reuses Module 10 rather than
  re-encoding in Python.
- **alternatives:** parse the worker's stdout for the result (rejected — transformers/qwen_tts print freely to stdout/
  stderr; a meta file is deterministic); reimplement TTS or call transformers `AutoModel` directly (rejected —
  transformers 4.57 lacks `Qwen3TTSForConditionalGeneration`; `qwen_tts` is the supported path and is installed); encode
  non-wav formats in Python via soundfile/ffmpeg-python (rejected — `audio.ingest` already solves it, deterministically);
  flip the TTS entries `wired:true` (rejected — misstates that the *gateway* runs them and risks the Module 7 posture;
  speech.tts reads them directly); a calibrated audio-quality confidence, voice cloning/design, batch, streaming
  (deferred — heuristic-first; scoped follow-ons / Module 13). `bfloat16` on the Turing GPU works (torch handles it);
  `float16` is the documented fallback.
- **consequences:** the review queue now has **four** producers (`model.gateway`, `classify.batch`, `speech.stt`,
  `speech.tts`); Module 9 selects by `flagged_by` and handles the new `verify_synthesis` verb by construction. Per-call
  model load is **~30–40 s cold** (1.8 GB read + qwen_tts import) and synthesis runs at ~5× real-time on this GPU (rtf
  ≈ 5.2 for the 0.6B) — fine for unattended use; a warm/persistent TTS worker is the concrete follow-on pressure (shared
  with the gateway/#8 warm-worker item). Registry gains `defaults.tts`/`tiers.tts` + a `speech.tts` skill entry + a
  qwen_tts/speech-venv runtime note. The triplicated 12 Hz speech tokenizer (REVIEW_QUEUE note) is still pending
  de-duplication when models relocate. · **affects:** Module 12, Modules 10/11/13/9, `TOOL_MODEL_REGISTRY.md`,
  `models.json`, `REVIEW_QUEUE.md`, `MODULE_ROADMAP.md`. · **revisit-if:** a warm TTS worker, voice cloning/design,
  batch/streaming, long-form chunking, calibrated confidence, or SSML is needed (each its own scoped follow-on).

### D-0022 — voice.live composes STT+LLM+TTS; orchestrator not a producer; file-driven turn (live mic deferred)
- **date:** 2026-07-24 · **state:** locked (compose-not-reimplement + child spawn + child-review aggregation + offline scope)
- **decision:** Module 13 `voice.live` — the **capstone of the audio track (10–13)** and the first skill that **composes
  several stochastic model skills end-to-end** — turns one input speech file into a voice turn by orchestrating the
  modules already built: **(1) `speech.stt`** transcribes (whisper segmentation = utterance / voice-activity detection;
  zero segments → `speech_detected:false`, skip the rest), **(2) `model.gateway`** answers the transcript (optional,
  `-Respond`), **(3) `speech.tts`** speaks the answer or the transcript (optional, `-Speak`/`-ReadbackTranscript`) to
  `reply.wav`. MVP design: (1) **compose, do not reimplement** — each child is spawned as a child pwsh with an
  overridable entrypoint path (`-SttPath`/`-GatewayPath`/`-TtsPath`) and its `lifeorch.skill.result/0.1` envelope is
  parsed (the same child-spawn pattern as `classify.batch`→gateway and `speech.stt`→audio.ingest); a stage that errors
  short-circuits to a structured `stage_failed` naming the stage, and partial progress (e.g. transcript but the LLM
  failed) is still reported (`status:"partial"`). (2) **Envelope `confidence` = the STT transcript confidence** (the
  "did we understand the user" signal); **`model_provenance` = the aggregate** of every child model used (stt + gateway
  + tts), each entry tagged with its `stage`. (3) **Orchestrator, NOT a review producer** — the children flag their own
  low-confidence outputs; voice.live points their `review_queue_path` at an in-artifact `child_review.jsonl` by default
  so a transient turn does not flood the canonical queue (surfaced as `child_review_count`); `-ReviewQueuePath` routes
  them to a canonical queue instead. It never writes its own review items (no new decision to review — it composes).
  (4) **File-driven offline turn**; `determinism:"mixed"`, `parallel_safe:false` (children bind CUDA sequentially),
  `batch:false`. **No new model / no `models.json` change** — it reuses the children's own registry resolution.
- **reason:** Proves the payoff of the whole contract program: because Modules 7/11/12 all emit the same envelope, a
  local voice assistant turn is *pure orchestration* — no model glue, no reimplementation. Composing children as
  processes (not importing their code) keeps each independently replaceable (D-0004) and crash-isolated (D-0002).
  Aggregating child review writes keeps interactive turns from spamming the canonical queue while still surfacing the
  signal. STT-confidence as the turn confidence is the honest "did the turn work" number.
- **alternatives:** re-implement STT/LLM/TTS inline or import child internals (rejected — breaks replaceability and the
  contract's whole point); add an LLM-free readback-only loop as the only mode (rejected — the LLM bridge is the useful
  turn; kept `-Respond`/`-Speak`/`-ReadbackTranscript` toggles so readback and transcript-only are still available);
  make voice.live its own review producer (rejected — it adds no new decision; double-flagging would mis-attribute);
  **live microphone capture / streaming** (rejected for the MVP — no mic can be assumed on this headless desktop and the
  executor is not a realtime audio path; a mic `audio.capture` skill + streaming loop is a scoped follow-on); a
  standalone VAD pre-segmentation pass (deferred — `whisper-vad-speech-segments.exe` exists but **no VAD ggml model is
  staged**, `m13-probe-001`; whisper's own segmentation via `speech.stt` is the utterance detector).
- **consequences:** a full turn pays **three cold model loads** (~1–2 min; observed ~58 s for a short answer — stt
  ~1.8 s, respond ~2.7 s, speak ~54 s dominated by TTS) — a warm-worker pool is the shared follow-on pressure (with
  #7/#8/#12). The review queue is unchanged (voice.live aggregates, does not produce). The **audio track (10–13) is now
  complete.** This is the composition substrate a future streaming voice loop, routing (#24), and a desktop-observation
  broker (#25) build on. · **affects:** Module 13, Modules 7/10/11/12/9, `TOOL_MODEL_REGISTRY.md`, `MODULE_ROADMAP.md`,
  `REVIEW_QUEUE.md`. · **revisit-if:** mic capture / streaming, standalone VAD (stage a model), multi-turn dialogue +
  memory, or a warm-worker pool is built (each its own scoped follow-on).

### D-0023 — ocr.layout wraps Windows.Media.Ocr via a PowerShell 5.1 worker; mixed; legibility confidence; fifth review producer; composes capture.screen
- **date:** 2026-07-25 · **state:** locked (engine choice + PS-5.1-worker + meta hand-off + registry-read + review model + capture compose), provisional (confidence heuristic; single OCR engine)
- **decision:** Module 14 `ocr.layout` — the first module of the image/document perception block (14–18) and the first
  **parallel-safe** stochastic/mixed perception skill — recognizes the text in one image and returns it with **per-word
  pixel bounding boxes and lines in reading order**. MVP design, settled after a **probe-first** pass (`m14-probe-001`,
  do **not** assume an OCR engine exists): (1) **Engine = the system `Windows.Media.Ocr`** (WinRT). Zero install, native
  to Windows 10, `en-US` recognizer present, `MaxImageDimension=10000`; the probe OCR'd a generated fixture to `"HELLO
  WORLD The quick brown fox 12345"` (100% correct incl. digits) with word boxes + line grouping + `TextAngle` in ~74 ms.
  (2) **Reached only via a Windows PowerShell 5.1 worker** — the probe confirmed **pwsh 7.4.6 cannot load the WinRT
  projection** on this box ("RuntimeException"), but 5.1 can via the classic `System.Runtime.WindowsRuntime` `AsTask`/
  `Await` reflection. So the skill is a two-part unit like `speech.tts` (D-0021), in a **PowerShell-5.1 worker** variant:
  a pwsh-7 wrapper (`Invoke-OcrLayout.ps1`) drives `ocr_worker.ps1` (run under `powershell.exe`) and reads its **meta
  file** (robust to any WinRT/console chatter), never its stdout. (3) **Confidence = a documented legibility heuristic**
  (Windows.Media.Ocr exposes **no** per-word confidence, unlike whisper token-`p`): the fraction of recognized words that
  are clean/plausible tokens, mapped to `[0.1,0.9]` per line and overall; a no-text result scores lowest. NOT calibrated
  correctness. (4) **Fifth review-queue producer** (after 7/8/11/12): overall `< -ConfidenceThreshold` (default 0.5) → one
  page-level `verify_ocr` item carrying the worst lines (bounded by `-MaxReviewLines`); a text-free non-empty image → one
  `verify_no_text` item (silent-fail guard). `flagged_by:"ocr.layout"`. Page-level (not per-line) because the confidence
  is a coarse page-legibility proxy, not a per-unit signal. (5) **Registry-driven, decoupled from the gateway `wired`
  gate** (mirrors D-0020): resolves the engine from `models.json` (`ocr.windows.media`, type `ocr`, engine
  `windows.media.ocr`); the entry stays `wired:false` (the gateway runs `type=llm` only — Module 7 re-verified 28/28 with
  the additive entries). Added `defaults.ocr`/`tiers.ocr`. (6) **Composes `capture.screen` (Module 6)**: with `-Capture`
  (and optional `-CaptureInputsJson`) and no `-InputFile`, spawns `capture.screen` as a child pwsh and OCRs its PNG —
  the same child-spawn pattern as `speech.stt`→`audio.ingest`; makes "read the text on my screen" a one-liner. (7)
  `determinism:"mixed"`, **`parallel_safe:true`** (binds no port/VRAM/CUDA context — the first genuinely parallel-safe
  perception skill; the only shared-state write is the append-only review queue), `batch:false`, `streaming:false`.
- **reason:** Smallest useful MVP that opens the perception block and is immediately useful (OCR a screenshot / scanned
  page / the live screen). Using the built-in `Windows.Media.Ocr` embodies "offload to the local machine with what is
  already there" — no install, no admin, no model download, no GPU — and it already returns boxes + reading order. The
  5.1-worker + meta-file hand-off is the robust answer to "pwsh 7 can't reach WinRT here" and reuses the proven D-0021
  pattern. Reading the engine from the registry keeps engine choice a one-line config change; composing `capture.screen`
  reuses Module 6 rather than reimplementing capture.
- **alternatives:** **Tesseract** (also installed at `C:\Program Files\Tesseract-OCR\tesseract.exe`, found by the probe)
  as the MVP engine (deferred — it is heavier, an external dependency, and CPU-only; but it yields **calibrated per-word
  confidence** + hOCR/TSV boxes + multi-language, so it is **declared** as `ocr.tesseract` and is the natural next engine
  behind the `-Engine` seam + the calibrated-confidence follow-on); a Python OCR lib (easyocr/paddleocr/rapidocr —
  rejected: none installed, and installing needs model downloads); calling WinRT from pwsh 7 directly (rejected — the
  projection does not load here); parsing the worker's stdout (rejected — a meta file is deterministic, per D-0021);
  per-line review items (rejected for the MVP — page-level avoids flooding for a coarse page-legibility signal);
  downscaling images over `MaxImageDimension` and rescaling boxes (deferred — returns a structured `image_too_large`;
  pairs with `image.util` #15); a drawn overlay PNG of the boxes (deferred — follow-on, cheap once #15 exists); flipping
  the ocr entry `wired:true` (rejected — misstates that the *gateway* runs it; the skill reads the entry itself).
- **consequences:** the review queue now has **five** producers (`model.gateway`, `classify.batch`, `speech.stt`,
  `speech.tts`, `ocr.layout`); Module 9 selects by `flagged_by` and handles the new `verify_ocr`/`verify_no_text` verbs by
  construction. A **new hard rule surfaced**: any script that runs under Windows PowerShell 5.1 must be **ASCII-only** —
  5.1 reads a BOM-less `.ps1` as ANSI (not UTF-8), so a UTF-8 em dash in the worker broke parsing (`m14-diag-002`); fixed
  by making `ocr_worker.ps1` ASCII-only (the pwsh-7 wrapper may keep non-ASCII, as pwsh 7 reads UTF-8). Registry gains
  `defaults.ocr`/`tiers.ocr` + `ocr.windows.media` (default) and `ocr.tesseract` (declared) entries. Throughput is a
  per-call `powershell.exe` spawn (~0.5–1 s; the OCR itself ~74 ms) — fine; a warm 5.1 worker is a possible follow-on if
  it ever dominates. · **affects:** Module 14, Modules 6/9, `TOOL_MODEL_REGISTRY.md`, `models.json`, `REVIEW_QUEUE.md`,
  `MODULE_ROADMAP.md`, `SKILL_CONTRACT.md` (first parallel-safe stochastic perception skill). · **revisit-if:** Tesseract
  (or a VLM, #17) is wired as a second engine; a calibrated/semantic confidence, an overlay PNG, `MaxImageDimension`
  downscaling, multi-column reflow, or batch/PDF OCR is built (each its own scoped follow-on).

### D-0024 — image.util is a deterministic Pillow+numpy Python worker under the system python; not a review producer; no models.json change
- **date:** 2026-07-25 · **state:** locked (backend choice + Python worker + meta hand-off + deterministic + tool-not-model), provisional (op surface may grow)
- **decision:** Module 15 `image.util` — the second module of the image/document perception block (14–18) and the **first
  deterministic perception skill** — does the small, boring, deterministic image operations the perception block and
  everything downstream keep needing: **one image in -> metadata + content/perceptual hashes always, plus one optional op**:
  **resize** (`fit`/`fill`/`exact` with width/height, or a single `max_dimension` = longest-side cap; reports
  `original`/`result`/`scale_x`/`scale_y`), **crop** (explicit pixel rect / `normalized` 0..1 rect / named `region` +
  `region_fraction`; clamped with a warning), **convert** (png/jpg/webp/bmp/tiff + quality; alpha flattened onto white
  where the format has none), **tile** (a `cols`x`rows` grid or fixed `tile_width`x`tile_height` with optional `overlap`,
  bounded to 400 tiles), and **similarity** (pHash/dHash Hamming distance + a `1 - hamming/bits` score vs a second image).
  Metadata = `format/mode/width/height/has_alpha/dpi/n_frames/EXIF-lite`; hashes = **sha256** (exact file content) + a DCT
  **pHash** + a gradient **dHash** (64-bit). MVP design, settled after a **probe-first** pass (`m15-probe-001`): (1)
  **Backend = Pillow + numpy under the system python** (`…\Python312`, PIL 10.2.0 + numpy 1.26.4). The probe confirmed live
  round-trips of all five formats, LANCZOS + `PIL.features` webp/libtiff/jpg, EXIF read, and a numpy-DCT pHash — and,
  critically, that the **perceptual hashes are identical across PIL 10.2/numpy 1.26 and PIL 12.2/numpy 2.4**, so they are
  safe to store and compare across machines. Chosen over the speech venv (PIL 12.2) because the system python is **CPU-only**
  (so the skill is genuinely `parallel_safe`, binding no CUDA/venv) and not tied to the speech stack; over `ffmpeg`
  (weaker at metadata/EXIF/format nuance) and `System.Drawing` (Windows-only, no perceptual hashing). (2) **Two-part skill**
  like `speech.tts` (D-0021) but **deterministic**: a Python worker (`image_worker.py`) does all pixel work and writes a
  JSON **meta file**; the pwsh-7 wrapper (`Invoke-ImageUtil.ps1`) resolves the interpreter (`-PythonPath` -> system Python312
  -> speech venv -> PATH, first that imports PIL+numpy), spawns the worker, reads the **meta file** (never stdout — robust
  to any library chatter), and builds the contract envelope, hashing every artifact. (3) **Deterministic posture**:
  `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`, **NOT a review-queue producer** (it makes no
  uncertain judgment — like `audio.ingest`/`fs.observer`). (4) **A tool, not a model**: Pillow is registered in
  `TOOL_MODEL_REGISTRY.md`, but there is **no `models.json` entry and no Module 7 re-verify** (contrast the OCR/STT/TTS
  registry-driven modules) — exactly as `audio.ingest` treats `ffmpeg`. `parallel_safe:true`, `batch:false`, `streaming:false`.
- **reason:** Smallest useful set that closes the "deterministic pixel plumbing" gap for the whole perception block and is
  immediately useful (downscale-before-OCR, thumbnails, crop, dedup by perceptual hash). Pillow is the richest, most
  portable image library and is already installed — wrapping it (not reimplementing) fits the language policy (Python for
  the imaging ecosystem; PowerShell owns the envelope). Reporting resize `scale_x`/`scale_y` is deliberate: it makes the
  `ocr.layout` **MaxImageDimension downscale-then-rescale-boxes** composition a one-liner for the caller (rescale boxes by
  `1/scale`). Because Pillow is portable AND version-stable, the test harness runs the **real** worker on the cloud box
  (no mock needed, unlike the WinRT/CUDA engines that forced mocks in M11/12/14) — the same real-engine-on-cloud pre-ship
  gate as `audio.ingest`, but stronger.
- **alternatives:** wrap `ffmpeg` for single-image resize/convert (rejected — no perceptual hashing, weaker metadata/EXIF,
  awkward for crop/tile); `System.Drawing` / .NET (rejected — Windows-only, no pHash, and `capture.screen` already shows its
  limits); the **speech venv** python as the worker interpreter (rejected as default — heavier, CUDA-bound, ties a CPU tool
  to the GPU stack; kept as a **fallback** in the resolver, and it produces identical hashes); a mock worker for the
  off-machine gate (rejected — Pillow runs for real on Linux, so the real worker is a better gate); a review-queue producer
  or a `confidence` (rejected — the operations are deterministic, there is nothing to review); an **operation pipeline**
  (multiple ops per call) (deferred — one primary op per call is simpler and sufficient; a pipeline is a follow-on);
  **draw/annotate/overlay**, **batch/directory**, rotate/flip/auto-orient, denoise/filters, multi-frame editing (deferred —
  scoped follow-ons; the box-overlay PNG in particular pairs with a future draw op).
- **consequences:** the perception block (14–18) now has its deterministic image primitive; the review queue is unchanged
  (still five producers — `image.util` produces nothing). `models.json` is untouched, so Module 7 stays 28/28 without a
  re-run. The system python is now a wired runtime (Pillow+numpy). Two `ocr.layout` follow-ons are unblocked and documented
  (MaxImageDimension downscale + box overlay) but intentionally **not** wired here. Throughput is a per-call python spawn
  (~0.2–0.8 s) — fine for the perception use; a warm worker is a possible follow-on if it ever dominates. · **affects:**
  Module 15, `TOOL_MODEL_REGISTRY.md`, `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (does **not** touch `models.json`,
  `REVIEW_QUEUE.md`, or Module 7). · **revisit-if:** a draw/overlay op, batch/directory processing, an operation pipeline,
  rotate/flip/auto-orient, or a warm worker is built (each its own scoped follow-on); or `detect.objects` (#16) / a VLM (#17)
  needs a shared image-preprocessing path.

### D-0025 — detect.objects wraps a staged ONNX YOLOX via onnxruntime (system python, CPU); mixed; real per-detection confidence; sixth review producer; composes capture.screen + image.util
- **date:** 2026-07-25 · **state:** locked (backend + model family + Python worker + CPU/parallel-safe + registry-driven + review producer), provisional (model family / tiers may grow)
- **decision:** Module 16 `detect.objects` — the **third** module of the image/document perception block (14–18) — detects
  objects in **one** image and returns each as `{class, class_id, score, box{x,y,width,height}}` with a **real per-detection
  confidence** (not a heuristic) plus overall/mean/min and a per-detection `low_confidence` flag. Settled after a
  **probe-first** pass (`detect-001` package survey + `m16-probe-001` live): (1) **Backend = a staged ONNX detector run via
  `onnxruntime` in a Python worker (`detect_worker.py`) under the system python** (onnxruntime-gpu **1.17.1** + PIL + numpy;
  all already present — no install). Chosen over a torch/torchvision model in the speech venv (heavier, CUDA-bound, ties a
  CPU detector to the GPU stack) and over wrapping a binary (none suitable). (2) **Model = YOLOX-Nano ONNX** (`detect.yolox.nano`,
  416×416, COCO-80, **Apache-2.0**, ~3.66 MB), downloaded on the cloud box and **staged to F:**
  (`_pending-model-storage\detector\yolox-nano\`), sha256-verified byte-exact; `detect.yolox.tiny` staged as a more-accurate
  drop-in tier. Preproc = letterbox-416 (pad 114, BGR, raw 0–255, CHW); decode = grids/strides {8,16,32}
  (`xy=(raw+grid)·stride`, `wh=exp(raw)·stride`); `score = objectness × class`; class-aware NMS; boxes mapped to original
  pixels. (3) **Two-part skill** like `image.util` (D-0024) — worker does inference+decode, writes a JSON **meta file**; the
  pwsh-7 wrapper (`Invoke-DetectObjects.ps1`) resolves the detector from **`models.json` (`type=detector`), decoupled from the
  gateway `wired` gate** (mirrors `ocr.layout` D-0023 / D-0020), resolves the interpreter, spawns the worker, reads the meta,
  and builds the contract envelope. (4) **CPU execution provider by default** → binds no port/VRAM/CUDA → **`parallel_safe:true`**
  (a `-Provider cuda|dml` opt-in is available and is *not* parallel-safe). (5) **`determinism:"mixed"`**: the envelope
  `confidence` is the **best detection's real score** (0.1 sentinel when nothing is found); `model_provenance` carries
  model/engine/provider/timings/detection_count. (6) **Sixth review-queue producer**: a below-`-ConfidenceThreshold` (0.5)
  best score → one page-level `verify_detections` (`low_confidence`) item; **zero** detections on a non-empty image →
  `verify_no_objects` (`uncategorized`). (7) **Composes** `capture.screen` (#6) via `-Capture` ("detect on screen") and
  `image.util` (#15) via `-MaxDimension` (downscale a huge input, then rescale boxes back to original pixels).
  `batch:false`, `streaming:false`.
- **reason:** Object boxes+labels are the perception primitive the block was missing (#14 text, #15 pixels, #16 objects);
  ONNX+onnxruntime is the lightest real-model path already installed, gives **genuine** per-detection confidence (unlike the
  OCR legibility heuristic), and CPU inference is deterministic + portable — so the **real** worker runs on the cloud pre-ship
  gate (identical detections on cloud onnxruntime 1.25 and Windows onnxruntime 1.17.1, `m16-probe-001`), the strongest gate,
  like `image.util`/`audio.ingest`. YOLOX is a clean **Apache-2.0** citizen with directly-downloadable ONNX and a
  well-documented decode. Registry-driven resolution keeps the detector swappable (tiny/-S/RT-DETR) with no code change;
  decoupling from the gateway `wired` gate keeps the gateway type=llm-only (Module 7 unaffected).
- **alternatives:** torchvision detection model in the speech venv (rejected as default — CUDA-bound, weight-cache download,
  ties a CPU tool to the GPU stack); a torch/ONNX model on the GPU by default (rejected — not parallel-safe; onnxruntime-gpu
  1.17.1 cuDNN deps uncertain — CPU is the safe, portable default); YOLOv8/v5 (works but **AGPL** — YOLOX Apache-2.0 preferred);
  reimplementing resize in the worker instead of composing `image.util` (rejected — composing #15 reuses the tested
  downscale+scale-factor path, which surfaced and fixed a real image.util bug); a mock worker for the cloud gate (rejected —
  onnxruntime runs for real on Linux, so the real worker is the better gate); per-detection review items (rejected — a coarse
  page-level flag like `ocr.layout`, so a busy image cannot flood the queue); overlay/annotated output (deferred — needs the
  `image.util` draw op, D-0024); batch/segmentation/tracking/VLM open-vocab (deferred — later modules).
- **consequences:** the perception block can now name+locate objects; the review queue has a **sixth** producer (7/8/11/12/14/16).
  `models.json` gained `defaults.detector`/`tiers.detector` + `detect.yolox.nano`/`detect.yolox.tiny` (type `detector`, engine
  `onnxruntime`, `wired:false` for the gateway) — **additive; Module 7 re-verified 28/28**. The **system python is now also an
  onnxruntime detection runtime**. **Side fix:** composing `image.util` on a real JPEG surfaced a latent Module 15 bug — a
  JPEG `dpi` of `IFDRational` is not JSON-serializable, so `json.dump` raised mid-write and truncated the worker meta;
  `image_worker.py` now coerces `dpi` to float (`safe_dpi`). **Module 15 re-verified 48/48** (no regression); the fix also
  hardens #15 for #17/#18. Live: `m16-test-001` — detect.objects **38/38** (incl. the capture composition), image.util 48/48,
  model.gateway 28/28, real-registry smoke, 0 orphans. · **affects:** Module 16 (new), Module 15 (`image_worker.py` dpi fix),
  `models.json`, `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`, `CURRENT_STATE.md`, `MODULE_ROADMAP.md`. · **revisit-if:** an
  overlay/annotated image (image.util draw op), batch/directory, a larger tier / RT-DETR / a VLM open-vocab detector (#17),
  GPU-by-default or a warm detector worker, calibrated confidence, or object tracking (#20) is built.

### D-0026 — image.interpret is a local VLM via llama.cpp llama-server + mmproj (Qwen2.5-VL-3B GGUF); pure-PowerShell wrapper; mixed; completeness+refusal confidence; seventh review producer; composes capture.screen + image.util; parallel_safe:false
- **date:** 2026-07-25 · **state:** locked (backend = llama.cpp multimodal + model family + pure-PowerShell wrapper + registry-driven + review producer + parallel_safe:false), provisional (confidence heuristic; single VLM/tier)
- **decision:** Module 17 `image.interpret` — the **fourth** module of the image/document perception block (14–18) and the block's first **semantic/free-text** perception skill — interprets **one** image with a local **VLM** and returns free-text (`interpretation.text`): a caption, a detailed description, an answer to a `-Prompt` (VQA), or a screen summary (`-Capture`). Settled after a **probe-first** pass (`m17-probe-001/002/003`): (1) **Backend = the already-staged llama.cpp `llama-server` (b8661) in multimodal mode** (`-m <vlm.gguf> --mmproj <projector.gguf>` -> `POST /v1/chat/completions` with an OpenAI-style `image_url` base64 data URI). `m17-probe-001` confirmed this build has full mtmd support (`--mmproj`/`--mmproj-offload`/`--image-max-tokens`); chosen over a transformers VLM in the speech venv (also viable — transformers 4.57.3 + CUDA + Qwen2-VL/2.5-VL classes — but heavier bf16, no bitsandbytes, needs qwen_vl_utils) and an ONNX VLM (awkward two-graph decode) because it **reuses the project's blessed engine** (the same `llama-server` model.gateway #7 drives; no new runtime/venv) and a quantized GGUF is VRAM-light + fast. (2) **Model = `vlm.qwen2p5-vl-3b`** (Qwen2.5-VL-3B-Instruct GGUF Q4_K_M ~1.8 GB + `mmproj-f16` ~1.3 GB, **Apache-2.0**), downloaded from `ggml-org/Qwen2.5-VL-3B-Instruct-GGUF` and **staged to F:** (sha256 recorded), then **load-and-caption verified live** with this exact server build before coding (`m17-probe-002`: accurate dog.jpg caption, full GPU offload, ~111 tok/s). (3) **Pure-PowerShell wrapper** (`Invoke-ImageInterpret.ps1`, **no python worker**): base64-encodes the image, reuses model.gateway's `llama-server` lifecycle (free-port -> `Start-Process` w/ redirected logs -> `/health` -> completion -> synchronous `taskkill`+`WaitForExit` teardown), builds the envelope. (4) **Registry-driven, decoupled from the gateway `wired` gate** (mirrors D-0020/D-0023/D-0025): resolves the VLM from `models.json` (`type=vlm`), which stays `wired:false` for the gateway (type=llm only); added `defaults.vlm`/`tiers.vlm`. (5) **`parallel_safe:false`** — binds a loopback port + CUDA/VRAM (unlike the parallel-safe #14–16, as anticipated). (6) **`determinism:"mixed"`**: envelope `confidence` = a documented **completeness+refusal+non-empty heuristic** (stop 0.7 / length 0.4 / refusal 0.3 / empty 0.1; NOT calibrated/semantic, like model.gateway/ocr.layout); `model_provenance` carries model/engine/build/device/tokens/timings/finish_reason. (7) **Seventh review-queue producer**: a below-`-ConfidenceThreshold` (0.5) / refusal / empty interpretation -> one page-level `verify_interpretation` item (`low_confidence` | `needs_strong_review` (refusal) | `failed_transform` (empty)). (8) **Composes** `capture.screen` (#6) via `-Capture` ("interpret my screen") and `image.util` (#15) via `-MaxDimension` (downscale before sending, to bound vision tokens). (9) **Cloud gate = a captured-real-response seam** (`-VlmResponsePath`): a VLM's real weights can't run on the Linux cloud box, so the harness feeds a **captured-real** `llama-server` response (from `m17-probe-003`) into the real wrapper's parse/confidence/review/compose/envelope path — the speech.stt/ocr.layout mock-engine gate in its HTTP variant. `batch:false`, `streaming:false`.
- **reason:** Free-text interpretation is the semantic primitive the block was missing (#14 text, #15 pixels, #16 objects, #17 meaning), and the last one #18 (`image.index`) needs. Driving the already-staged `llama-server` embodies "offload with what's already there" — no new runtime, no heavy transformers-stack download — and a quantized 3B VL GGUF fully offloads on the 11 GB RTX 2080 Ti with headroom. The pure-PowerShell wrapper reuses #7's proven HTTP + lifecycle so there is no python worker to maintain; registry-driven resolution keeps the VLM swappable (a 7B tier / a different family) with no code change; decoupling from the `wired` gate keeps the gateway type=llm-only (Module 7 unaffected).
- **alternatives:** a **transformers VLM in the speech venv** (Qwen2-VL-2B/Qwen2.5-VL bf16; rejected as the MVP — heavier, CUDA/venv-bound, needs qwen_vl_utils + a ~4–7 GB safetensors download; **documented as the follow-on backend**); an **ONNX VLM** (rejected — vision-encoder + decoder two-graph plumbing is far more work than reusing llama-server); a **python worker** driving llama-server (rejected — PowerShell already owns the HTTP + envelope path in #7; a worker would only add a layer); **grounding/bounding-box** VLM output (rejected/deferred — open-vocab boxes belong to a detect.objects #16 follow-on / #22); **logprob/calibrated** confidence (deferred — llama-server can return token logprobs; a real per-token-probability or self-consistency confidence is a follow-on, as for model.gateway); a **mock HTTP server** for the cloud gate (rejected — a captured-real-response file is simpler and tests the same parse/confidence/review path); a **warm/persistent** VLM server (deferred — shared worker-pool pressure with #7/#8/#12/#14/#16). Chose Qwen2.5-VL-3B over Qwen2-VL-2B (newer, stronger, still Apache-2.0 + fits) and over 7B (declared as a follow-on tier).
- **consequences:** the perception block can now describe / answer-about / interpret an image + the live screen; the review queue has a **seventh** producer (7/8/11/12/14/16/17), and Module 9 handles the new `verify_interpretation` verb by construction. `models.json` gained `defaults.vlm`/`tiers.vlm` + `vlm.qwen2p5-vl-3b` (type `vlm`, engine `llama-server`, carries a `mmproj` path, `wired:false` for the gateway) — **additive; Module 7 re-verified 28/28** (`m17-test-001`). The staged **`llama-server` is now also a multimodal runtime** (recorded in the registry + `TOOL_MODEL_REGISTRY.md`). **model.gateway pre-registered `vision = Module 17` in its not-wired hint (D-0016); the shipped type is `vlm` (per the work order) — a harmless cosmetic mismatch (the gateway runs type=llm only and never executes it).** Live: `m17-test-001/002` — image.interpret **48/48** (seam + real VLM describe/VQA + capture.screen compose + no orphans), model.gateway 28/28, cloud pre-ship gate 40/40, shipped-file sha256 byte-exact. · **affects:** Module 17 (new), Modules 6/9/15, `models.json`, `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`, `CURRENT_STATE.md`, `MODULE_ROADMAP.md`. · **revisit-if:** a warm/persistent VLM server, logprob/calibrated confidence, batch/directory, multi-image/multi-turn, open-vocab grounding boxes, a 7B tier or the transformers-venv backend, wiring the VLM as a second `ocr.layout` engine, or `image.index` (#18) consuming this is built.

### D-0027 — image.index fuses 14–17 into one per-image index via a sequential orchestrator; NOT a review producer (redirects child flags); mixed; parallel_safe:false; no models.json change
- **date:** 2026-07-25 · **state:** locked (orchestrator/compose design + always-image.util backbone + flag-gated stochastic stages + child-review redirect + not-a-producer + sequential execution + min-of-stages confidence), provisional (concurrency; batch; cross-stage grounding)
- **decision:** Module 18 `image.index` — the **capstone** of the image/document perception block (14–18) and the **second skill to compose several stochastic perception skills end-to-end** (after `voice.live` #13 for audio) — fuses the perception children into **one per-image record** (`index.json` machine + `index.md` human card). Settled points: (1) **Modeled on `voice.live` #13** — an **orchestrator/composer**, not a new perception engine: it spawns each child as a **child pwsh**, parses its `lifeorch.skill.result/0.1` envelope, aggregates each child's `model_provenance` **stage-tagged**, and **reimplements nothing** (reuses the `Has`/`Prop`/`Get-Sha256Hex`/`Resolve-Child`/`Invoke-Child`/`Add-Provenance` scaffolding from `Invoke-VoiceLive.ps1` + the `-Capture`/`-MaxDimension` + `InputsJson`-merge compose helpers from `Invoke-ImageInterpret.ps1`/`Invoke-DetectObjects.ps1`). (2) **Which children run:** **`image.util` (#15) ALWAYS** (op `meta` → metadata + `sha256`/`pHash`/`dHash`; the deterministic backbone every indexed image gets), and the three stochastic stages behind flags — **`ocr.layout` (#14) `-Ocr`**, **`detect.objects` (#16) `-Detect`**, **`image.interpret` (#17) `-Interpret`** (`-All` runs the three). A lean, fast, deterministic, parallel-safe default (hash+meta only); opt into depth. (3) **Sources:** an explicit `-InputFile`, or **`-Capture`** which composes `capture.screen` (#6) **once** and feeds the captured PNG to every stage (not re-captured per child). **`-MaxDimension`** passes through to detect + interpret (they downscale-then-rescale boxes); image.util meta/hash always run on the original. (4) **Sequential** child execution (capture → image.util → ocr → detect → interpret): the MVP choice — it avoids the VRAM/loopback-port contention `image.interpret`'s `llama-server` would create if run concurrently with the others, and sidesteps the executor file-lock class; concurrency is a documented follow-on. (5) **Orchestrator, NOT a review-queue producer** (mirrors #13): it passes `review_queue_path = <invDir>/child_review.jsonl` to each child, **redirecting** their flags away from the canonical `review_queue.jsonl`, and it does **not** re-flag — so the **producer set stays at seven** (7/8/11/12/14/16/17). (6) **`determinism:"mixed"`** (deterministic when only image.util runs; stochastic with any optional stage): envelope `confidence` = the **minimum** confidence across the stochastic stages that actually ran (the weakest-link signal for the fused record), `null` when only image.util ran. (7) **`parallel_safe:false`** — conservatively, because it can bind CUDA/VRAM + a loopback port via `-Interpret` (a run limited to image.util+ocr+detect is effectively parallel-safe, but the manifest declares the conservative superset). `batch:false`, `streaming:false`. (8) **No new model / no `models.json` change / no Module 7 re-verify** — it composes existing skills; a pure orchestrator (confirmed, not assumed). Artifacts `index.json`/`index.md`.
- **reason:** The block built four independent perception skills (#14 text, #15 pixels/hashes, #16 objects, #17 meaning) but nothing fused them; #18 is the one call that turns four envelopes into one searchable per-image record. Modeling it on `voice.live` (the proven audio-capstone orchestrator) rather than inventing a new pattern keeps it thin and correct — the shared skill contract is exactly what makes "spawn the children, parse envelopes, fuse" possible with zero reimplementation. Always running image.util gives every index a cheap deterministic backbone (dimensions + content hashes for dedup/identity) even when the caller wants nothing heavier; gating the stochastic stages behind flags keeps the default fast and GPU-free. Redirecting child review writes (not producing) is right because a transient index run should not flood the canonical queue with the same flags its children already know how to emit — and the redirected `child_review.jsonl` is still there for a future `route.tasks`/`artifact.search` consumer. Sequential execution is the MVP-honest choice given one image and the VLM's exclusive GPU/port hold.
- **alternatives:** **image.util-only-is-useless / run everything by default** (rejected — the MVP doctrine + the value of a fast deterministic default; `-All` is one flag away); **concurrent child execution** (deferred — real VRAM/port contention from `image.interpret` + executor file-lock risk; needs the warm-worker pool shared with #7/#8/#12/#14/#16/#17); **image.index does its own downscale/capture and feeds downscaled coords to children** (rejected — each child already implements `-MaxDimension` downscale-then-rescale-boxes correctly, so passing it through keeps #18 reimplementation-free); **making it an eighth review producer** that re-emits a fused flag (rejected — the children already flag; re-flagging would double-count and misattribute, and #13 set the orchestrator-redirects precedent); **`determinism:"deterministic"`** (rejected — it invokes stochastic children under flags; `mixed` matches `voice.live`); **envelope confidence = the interpret ("headline") confidence** or the mean (rejected — the **min/weakest-link** is the honest "should a human look at this record" signal; a photo with no text correctly pulls it to OCR's 0.1); **cross-stage grounding** (associate a detection box with an OCR word / a caption phrase; deferred — that is fusion *reasoning*, a #22/#25 concern, not this MVP); **batch/directory indexing** and an **overlay/annotated card image** (deferred — batch is every perception module's follow-on; the overlay needs the `image.util` draw op). The cloud pre-ship gate is a **mock-children** harness (`tests/mock-child.ps1` branching on the `-ArtifactRoot` leaf `capture|image_util|ocr|detect|interpret`), the M13 pattern in its image variant — a VLM/WinRT/ONNX child can't run on the Linux cloud box, so mocks drive the *real* orchestrator's fuse/aggregate/redirect/envelope logic off-GPU (40/40) before the identical harness runs live.
- **consequences:** the perception block (14–18) is **complete** — an agent can index a screenshot or a photo into one machine-readable record + a human card with a single call, choosing hash-only → +OCR → +objects → +interpretation via flags. **No `models.json` / `TOOL_MODEL_REGISTRY.md` / `REVIEW_QUEUE.md` change** (wires nothing new; not a producer — the review-queue producer set stays at seven). The first live run surfaced that on a real photo OCR correctly finds **no text** (confidence 0.1), which is the fused record's genuine weakest link — so two test assertions were made **mode-robust** (envelope confidence = the min of the per-stage confidences; `summary.ocr_text` mirrors the ocr stage) rather than hard-coding the mock's values; the skill logic was already correct. Live: `m18-test-002` — image.index **41/41** (default image.util-only + `-All` fusion on `dog.jpg`: meta+hashes + OCR + 5 detections + a full VLM description, 3 stage-tagged provenance, min-confidence fusion; the child-review **redirect** with the canonical queue **verified untouched, 0→0**; the Module 1 wrapper; **0 orphaned `llama-server`/python**), cloud mock-children gate **40/40**, 9 shipped files sha256 byte-exact. · **affects:** Module 18 (new), Modules 6/14/15/16/17 (composed, unchanged), `CURRENT_STATE.md`, `MODULE_ROADMAP.md`. · **revisit-if:** concurrent children / a shared warm-worker pool, batch/directory/glob indexing, cross-stage grounding (detections↔OCR↔caption; open-vocab boxes), an overlay/annotated card image (needs an image.util draw op), or persisting indices into `artifact.search` (#23) / draining the redirected `child_review.jsonl` via `route.tasks` (#24) is built.


### D-0028 — Housekeeping: fold D-0009/D-0011 into contract v0.2; relocate staged models to owning-module F: homes; de-dup TTS tokenizer; remove the game-repo executor leftover
- **date:** 2026-07-25 · **state:** locked
- **decision:** A single scoped housekeeping pass, taken now that every skill through Module 18 has exercised the provisional Module 1 conventions and the owning modules of every staged model (7/11/12/16/17) are built. Three parts. **(A) Contract finalization.** Promote the three D-0009 conventions (confirmed by D-0011) from the Module 1 README into the normative `SKILL_CONTRACT.md`, bumping the **contract document** version 0.1 -> **0.2**: (1) a skill resolves its artifact root relative to the skill folder (`$PSScriptRoot/runtime/artifacts/<invocation_id>/`, or a caller `-ArtifactRoot`) and the envelope reports **absolute** artifact paths (S3); (2) every skill accepts a generic `-InputsJson '<json object>'` in addition to named params (new S3.1); (3) the generic wrapper emits `lifeorch.skill.invocation_report/0.1` = `{schema, skill_dir, skill_id, manifest_valid, manifest_errors, invoked, exit_code, envelope_valid, envelope_errors, envelope, stderr_tail}` (new S3.2 — the shape verified against `Invoke-Skill.ps1`'s actual emission, which carries three more fields than D-0009 first listed). **The wire schema ids stay `lifeorch.skill.manifest/0.1` and `lifeorch.skill.result/0.1`** — the change is additive/backward-compatible, so all existing skills stay valid declaring `contract_version` "0.1"; the validators (`SkillContract.psm1`) require the field's presence, not its value, so no validator or manifest change was needed. **(B) Model relocation + tokenizer de-dup** (per D-0015 / `_pending-model-storage\MIGRATION.md`). Moved every staged model within F: (same-volume renames) into its owning module's `..._Large_Data\<NN>-<module>\` home: LLMs -> `07-model-gateway\llm`, whisper -> `11-speech-stt\stt`, the two Qwen3-TTS voices -> `12-speech-tts`, YOLOX detectors -> `16-detect-objects\detector`, the Qwen2.5-VL GGUF+mmproj -> `17-image-interpret\vlm`, the embedding -> `23-artifact-search\embedding` (pre-provisioned for the unbuilt owning module so the staging area could be fully emptied). The **shared llama.cpp engine** went to `..._Large_Data\_engines\` at the **root** (not under Module 7 as MIGRATION.md's pre-#17 table assumed) because both `model.gateway` (#7) and `image.interpret` (#17) resolve it from the registry `engines.llama-server` — one shared home, one path edit. Rewrote the ~11 absolute paths + `engines.llama-server` in `models.json`. **De-duplicated the triplicated 12 Hz TTS tokenizer** by deleting the redundant **standalone** `Qwen3-TTS-Tokenizer-12Hz` copy and its declared-only registry entry `tts.tokenizer.qwen3-12hz` (byte-identical to each voice's bundled `speech_tokenizer\`, sha256 836B7B35...; consumed by no skill — the voices load their own bundled copy). Deleted the emptied `_pending-model-storage\` (+ its `MIGRATION.md` and the vlm HF download cache). **(C)** Removed the stopped original executor leftover `C:\Users\just_\Project-Proteus-src\proteus_repo\tools\` (an empty 0 MB tree at recon; `proteus_repo` itself untouched).
- **reason:** Pay down accrued, low-risk debt at a natural checkpoint. The contract had drifted (provisional conventions used everywhere but not normative); the models sat in a staging area explicitly marked temporary; the game repo held a dead leftover. Same-volume moves are instant and reversible, and every consuming skill reads model paths from the one registry, so relocation is a config edit + re-verify, not a code change.
- **alternatives:** **Bump the schema ids to /0.2** (rejected — would break all existing manifests + the validators for a purely additive change; the doc version and the wire-schema version are decoupled). **Collapse the two per-voice bundled tokenizers to one physical copy via junctions/symlinks** (rejected — D-0015 prefers self-contained portable copies over links, which survive a naive tree copy; only the genuinely-redundant standalone copy was removed; a qwen_tts external-tokenizer-path config is a possible future follow-on). **Put the shared engine under `07-model-gateway`** (rejected — it is shared by #17; a root `_engines\` avoids cross-module coupling). **Leave the embedding staged** (rejected — would keep `_pending-model-storage` alive; pre-provisioning `23-artifact-search\` is zero-risk since the embedding is declared-only, consumed by no skill). **Delete via ops `finish-game-cleanup.bat`** (it `pause`s for a human double-click; a headless executor `task.ps1` `Remove-Item` is the equivalent).
- **consequences:** `SKILL_CONTRACT.md` is v0.2; D-0009/D-0011 are resolved (folded). `models.json` now points at per-module homes (13 models; tokenizer entry gone) and is byte-exact on disk (sha256 5aed38db...). `_pending-model-storage\` and `proteus_repo\tools\` are gone. **Re-verified live via the executor (`hk-verify-001`): all 4 LLM tiers load (0.5B/1.5B/3B finish=stop; 27B partial/length at max_tokens=8, expected), whisper transcribed the real jfk.wav, Qwen3-TTS synthesized with its bundled tokenizer, the ONNX detector found 5 objects, the VLM captioned dog.jpg — each from its new F: home; 0 orphaned model servers.** No skill code changed (only the Module 1 README's stale "candidates" note was refreshed). **Provenance of the originals** the staging copies came from (recorded here since MIGRATION.md was deleted): `F:\Qwen3.5-27B\{model, small-models, llama.cpp\build\bin}`, `F:\Local_TTS_Large_Data\models\whisper.cpp\ggml-base.en.bin`, `F:\My_Programs\Local_Computer_Speech_Large_Data\models\qwen\Qwen3-TTS-*`, `F:\Coding\AI Models\Music\ACE-Step-1.5\checkpoints\Qwen3-Embedding-0.6B`. · **affects:** `SKILL_CONTRACT.md` (v0.2), `models.json`, `CURRENT_STATE.md`, `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`, `MODULE_ROADMAP.md`, Module 1 README; resolves D-0009, D-0011, and the D-0015 relocation. · **revisit-if:** a qwen_tts external-tokenizer-path config lets the two per-voice tokenizers collapse to one shared copy; the whisper.cpp engine builds / speech venv (still referenced at their `F:\Local_TTS_Large_Data` / `Local_Computer_Speech_Large_Data` sources) are ever relocated; a future skill needs a `contract_version` value check.


### D-0029 — Pivot to a usable-local-core-first build order; Module/Widget vocabulary; the widgets/ (HID) layer; long-horizon architecture map
- **date:** 2026-07-25 · **state:** locked (vocabulary + folder + priority-over-sequence), provisional (exact utility/widget order; Local Logic Escalator design)
- **decision:** Re-prioritize the build order and split the taxonomy. **(A) Vocabulary.** Two kinds of thing: a **Module** (a backend capability under `modules/` that agents invoke via `SKILL_CONTRACT.md`) and a **Widget** (a human-interface tool — a real window/application — under the new `widgets/` folder that connects a *person* into the Module architecture, usually by driving the local orchestrator + Local Logic Escalator). "Widget" is the adopted term for the HID / human-interface layer (colloquial, modular, signals a full app that plugs in — not a lesser sub-window). **(B) Folder.** Created `widgets/` parallel to `modules/`, with `widgets/README.md` defining the layer + its buildout order. **(C) Priority over sequence.** The canonical 0-49 architecture (now captured in the new core-doc `ARCHITECTURE_MAP.md`, including the real-time autonomic layer 45-49 and the 6-level operating hierarchy) is the *destination*, and its numbers are **architectural positions, not build order.** The near-term order is re-sequenced (in `MODULE_ROADMAP.md → Build priority`) to deliver a **locally usable core first**: Phase A utility + cost-offload Modules (Local Logic Escalator; Local Model Doc I/O; a local orchestrator/agent core; then generators cheapest-first — audio, image, music, video; Coding Agent last); Phase B the Widget layer (led by the Local Agent Console); and only Phase C resumes the slower spine (video 19-22, search/routing/orchestration 23-26, then the 27-49 research + autonomic stack, deferred). **(D) Local Logic Escalator design guidance.** The user's escalating ladder (the weakest model answers -> each higher tier judges the tier below and either accepts it or produces its own answer for the next tier to judge, stopping when the step up would add no substantial gain, which fixes the accepted layer) is adopted as a generalization of `review.processor` (#9) + `route.tasks` (#24). Two guardrails are required before trusting it: (1) do NOT rely on LLM-judges-LLM alone at each rung — anchor with **deterministic ground-truth gates** wherever they exist (schema validation, unit tests, retrieval checks, self-consistency across samples) to avoid the false-approval failure mode where two too-weak tiers rubber-stamp each other; (2) it must be **empirically calibrated** — sandbox it and measure the resolve-level distribution AND the false-approval rate (a ladder that calls N tiers can cost more than one correct call unless most tasks resolve low), targeting a stated confidence (~95%) rather than assuming it.
- **reason:** Budget + usability. The weekly frontier allotment is the scarce resource, and the project's own doctrine is "speed + practical usefulness first, offload cost locally." Completing the full 0-49 spine before anything is usable inverts that — Modules 27-49 are the most expensive, least pre-solved, research-heavy items and do not make the system usable near-term. The highest-leverage budget move is the Local Logic Escalator + a local-LLM-as-first-stage interface: every task a local model finishes end-to-end is a task the frontier allotment never pays for, and it immediately makes the already-built 0-18 stack usable without the frontier in the loop. The generators are user-visible capability but do not defend the budget, so they follow the cost-offload keystones. The Widget layer turns the offloaded core into something a human actually uses.
- **alternatives:** **Keep the strict sequential 0-44/0-49 order** (rejected — burns budget on the hardest research modules before delivering usable value; contradicts the doctrine). **Build all four generators first** (rejected — they consume budget rather than defend it; sequenced after the escalator/orchestrator/doc-I/O keystones, cheapest-first). **Build a local coding agent early** (deferred — the frontier already codes well; lowest near-term ROI). **Rely on the escalator's LLM self-judgment alone** (rejected — the false-approval risk; deterministic gates + empirical calibration required). **Name the human-interface items "Plugins" or "HID Items"** (set aside — "Plugin" already means a skills/MCP bundle in the Claude/Cowork ecosystem and "HID" reads as input hardware; "Widget" avoids both while staying memorable). **Fold the 0-49 detail into `MODULE_ROADMAP.md`** (rejected — the roadmap now owns *build order*; the canonical spine + real-time layers + hierarchy live in a separate `ARCHITECTURE_MAP.md` so the roadmap stays about what to build next).
- **consequences:** New core-doc `ARCHITECTURE_MAP.md` (canonical 0-49 + real-time 45-49 + 6-level hierarchy + the discovery->collapse mechanism; model names annotated as non-binding candidates). New `widgets/` folder + README. `PROJECT_DIRECTION.md` gains the Module/Widget vocabulary + the usable-core-first priority; `MODULE_ROADMAP.md` gains a "Build priority" section (Phase A/B/C) and the note that 0-49 numbers are positions not order; `START_HERE.md` routes to `widgets/` + `ARCHITECTURE_MAP.md` and the vocabulary; `CURRENT_STATE.md` next-action reflects the new order. **No code was built this session — direction/documentation only.** The real-time autonomic layer (45-49) and the general-screen-perception stack (27-44) are explicitly **deferred** but recorded so the direction is not lost. · **affects:** `ARCHITECTURE_MAP.md` (new), `widgets/` (new), `PROJECT_DIRECTION.md`, `MODULE_ROADMAP.md`, `START_HERE.md`, `CURRENT_STATE.md`; supersedes the strict-sequential reading of `MODULE_ROADMAP.md`. · **revisit-if:** the utility/widget order needs reshuffling once the escalator lands; the escalator's calibration shows the ladder is not cost-effective or cannot hit the target confidence; the budget picture changes materially; or a project-wide Widget delivery approach (native vs web) is chosen.

### D-0030 — logic.escalator: escalating tier ladder composing model.gateway; deterministic ground-truth gates anchor every rung; orchestrator-not-producer; empirically calibrated (does NOT reach ~95% with the naive K=1 config)
- **date:** 2026-07-25 · **state:** locked (ladder mechanism + deterministic-gate anchoring + orchestrator/non-producer + folder-number scheme), provisional (confidence heuristic; tier/token tuning; self-consistency policy)
- **decision:** Module 19 `logic.escalator` (Phase A #1, realizing D-0029(D)) is the cost-offload keystone and the first Phase-A build. MVP design: **(1) Composes `model.gateway` (#7)** across its four wired LLM tiers (tiny 0.5B / weak 1.5B / mid 3B / strong 27B) — spawns the gateway as a child pwsh and parses its `lifeorch.skill.result/0.1` envelope, reusing the #8/#9 child-spawn scaffolding; **reimplements no model plumbing**. **(2) The escalating ladder** (the user's design): tier 0 answers; each higher tier JUDGES the current answer in one gateway call (`{accept,answer,confidence,rationale}`) and either ACCEPTs it (stop — accepted layer = the tier that produced the current answer) or REJECTs and uses its own answer for the next tier to judge; the top tier's answer is accepted if the ladder is exhausted. **(3) Deterministic ground-truth gates anchor every rung** (guardrail 1) so the ladder never rests on LLM-judges-LLM alone: `classify` = in-set membership (HARD) + self-consistency across K samples; `extract` = JSON-schema validity + all-required-fields (HARD) + source-grounding; `generic` = ungated + self-consistency. **A hard-fail overrides an LLM-judge ACCEPT** (an out-of-set / invalid answer can never be accepted, no matter what a judge says — the anti-rubber-stamp defense); **strong self-consistency + hard-pass short-circuits to ACCEPT with no judge call** (the cost saver for easy items). **(4) Orchestrator, NOT a review-queue producer** (like `voice.live` #13 / `image.index` #18): it suppresses the child gateway's own review writes to an in-artifact `_gateway_review_suppressed.jsonl` and surfaces `needs_frontier` per task as a status field in its own result — it never writes the canonical `review_queue.jsonl` (scope: NOT extending `review.processor`'s queue writes; the producer set stays at seven). **(5)** `determinism:"mixed"`, `parallel_safe:false` (drives the gateway → GPU/port), `batch:true`, `streaming:false`; **no new model / no `models.json` change / no Module 7 re-verify**. **(6) Folder-number scheme:** on-disk `modules/19-logic-escalator/` — the `NN-` prefix is a monotonic build-order counter (D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions); the escalator has no dedicated spine slot (it generalizes #24 + #9). The video block's "19–22" remain architectural labels, deferred to Phase C, and take their own next-free folder numbers when built.
- **empirical calibration (guardrail 2 — the experiment, run not assumed):** a labeled closed-set eval was run through the ladder LIVE via the executor (`m19-calib-002` easy N=12; `m19-calib-003` hard-gradient N=14), measuring resolve-level distribution, accuracy (+ always-tiny/always-mid baselines), false-approval rate, and a params_b-weighted cost. **Findings, reported plainly:** on the easy eval the ladder resolves ~92% at the tiny tier at 100% accuracy and **−91.7% cost vs always-strong**. On the hard eval the naive **K=1** ladder **does NOT reach the ~95% target**: 3-tier `[tiny,weak,mid]` = **78.6% acc, false-approval 0.20** (the weak 1.5B judge rubber-stamped 2 in-set-but-wrong tiny answers — the exact failure D-0029 predicted, now measured), −89% cost; 4-tier `[+strong]` = **57.1%** because the thinking-style 27B **emits empty verdicts at the MVP token caps** (the D-0018 strong-parseability issue, confirmed) → those 4 escalated items degrade to flagged `needs_frontier` (fail-safe, NOT false approvals) and cost jumps (only −32% vs always-strong). The always-mid baseline (92.9%) shows the capability exists; the ladder loses it to early low-tier resolution behind a rubber-stamping judge. Full numbers: `modules/19-logic-escalator/CALIBRATION.md` + `runtime/calibration/`.
- **reason:** The escalator is the single highest-leverage budget item (D-0029): every task a low tier finishes end-to-end is one the frontier never pays for. Composing the gateway (not reimplementing) keeps model choice a one-line config change and mirrors the #8/#9 consumer pattern. Anchoring rungs with deterministic gates is what makes the ladder trustworthy rather than a stack of rubber-stamps; calibrating it empirically (rather than assuming ~95%) is what the user explicitly required — and it paid off by surfacing the concrete failure modes (judge rubber-stamping; strong-tier empty verdicts) instead of shipping a false claim.
- **alternatives:** rely on the LLM judges alone (rejected — the 0.20 false-approval measurement is exactly why); make it a review-queue producer (rejected — it resolves tasks; `needs_frontier` is a status signal, like #13/#18 redirect); extend `review.processor` (rejected — a new, more general module per the work order); a warm/persistent gateway worker (deferred — D-0002, shared follow-on); include a `unit_test`/retrieval gate in the MVP (deferred — the in-set/schema/grounding/self-consistency gates cover classify+extract; code/RAG gates are follow-ons); default `-Samples`>1 (kept at 1 for the MVP + cost — self-consistency implemented + unit-tested but not live-calibrated); number the folder to a 0-49 position (rejected — it has none; the build-order counter is honest and avoids squatting media.decompose's #19 label).
- **consequences:** A new cost-offload primitive the Phase-B Widgets + a local orchestrator (`agent.local`) will call. Tests 24/24 mock (cloud pre-ship) + 28/28 `-Live` (`m19-test-001`, 0 orphans); 10 files sha256 byte-exact + AST-parse OK on the target (`m19-verify-001`). **Measured, prioritized follow-ons:** (a) raise the strong-tier `max_tokens` / add a no-reasoning directive so the 27B returns a parseable verdict (D-0018); (b) a self-consistency **veto** (low agreement forces escalation / flags, not just gating the short-circuit) + more skeptical judge prompts, to cut the 0.20 false-approval; (c) a higher floor / cost-aware early-stop (always-mid beat the ladder on hard items); (d) live-calibrate K>1 self-consistency; (e) a `route.tasks` (#24) drain of `needs_frontier` tasks; (f) calibrated (logprob/conformal) confidence. · **affects:** Module 19 (new), Modules 7/8/9 (composed / patterns reused), `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (Build priority + Module 19 entry), `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`; realizes D-0029(D). · **revisit-if:** the follow-on tuning lifts accuracy to the ~95% target; a warm worker lands; the folder-number scheme needs revisiting when video (Phase C) is built; self-consistency is made a false-approval veto.

### D-0031 — doc.io: deterministic read/write/edit/append text primitive; pure PowerShell + .NET; atomic writes + EOL preservation + expect_sha256 precondition + recoverable pre-image; NOT a review producer; no models.json change; parallel_safe:false
- **date:** 2026-07-25 · **state:** locked (op set + deterministic posture + atomic/EOL/precondition/pre-image safety model + tool-not-model), provisional (parallel_safe:false; encoding surface; op surface may grow)
- **decision:** Module 20 `doc.io` (Phase A #2, per D-0029) is the cheap, high-utility document primitive a local model (the escalator #19, a future `agent.local`, Widgets, unattended executor tasks) calls to do real file work — the local counterpart to the frontier agent's Read/Write/Edit tools. MVP design: **(1) One skill, four ops, one op per invocation** (`-Op read|write|edit|append`): **read** (whole file or a 1-indexed inclusive `start_line..end_line` range, `max_bytes` cap) returns content + `{encoding,bom,eol,line_count,byte_count,char_count,sha256}`; **write** creates/overwrites with `content` (`overwrite`/`create_dirs`, `eol lf|crlf`); **edit** is exact-string replace (`old_string`→`new_string`; default requires **exactly one** occurrence — `not_found`/`not_unique` otherwise — with `replace_all` and `expect_count` variants); **append** adds `content` to the end (`ensure_newline`, `create`). **(2) Deterministic posture** (like `fs.observer`/`image.util`/`audio.ingest`): `determinism:"deterministic"`, `confidence:null`, empty `model_provenance`, **NOT a review-queue producer** — the canonical `review_queue.jsonl` and the **seven-producer set (7/8/11/12/14/16/17) are untouched** (verified live: before==after). **(3) A tool, not a model** — pure PowerShell over cross-platform .NET `System.IO`/`System.Text`/`System.Security.Cryptography`; **no external binary, no Python, no model, no `models.json` change, no Module 7 re-verify** (the leanest skill yet). **(4) Safety model** for every mutation: **atomic writes** (temp file in the target's own dir → `File.Move(...,overwrite)` rename; no torn files, no leftover `.docio-*.tmp`); an optional **`expect_sha256` optimistic-concurrency precondition** (`precondition_failed` if the file changed since — makes a local model's read→reason→edit loop safe against a lost update); a **recoverable pre-image** (`before.<ext>` copied into the artifact dir, `after.<ext>` the new content; skipped >~8 MB or with `-NoPreimage`); and **EOL preservation** — `edit`/`append` keep the file's existing convention (a CRLF file — like this repo's own core-docs — stays CRLF) by matching on an LF-normalized view and re-applying the file's EOL on write; `write` writes `eol` (default `lf`). **(5) Encoding:** UTF-8 default; `read` auto-detects + strips a UTF-8/UTF-16LE/UTF-16BE BOM (reported); `write` = UTF-8 **no BOM** (contract §3); `edit`/`append` **preserve** the detected encoding + BOM; a binary (NUL) file is refused for read/edit/append with `binary_file`. **(6) Flags:** `parallel_safe:false`, `batch:false`, `streaming:false`; byte-level I/O (never `Environment.NewLine`/`Set-Content`/`Out-File`) so behavior is identical on Windows and Linux.
- **`parallel_safe:false` (the one genuinely debatable call):** `doc.io` is the project's first general-purpose external-file **mutator** — it writes/edits/appends **arbitrary caller-chosen paths**, unlike the artifact-only writers `audio.ingest`/`image.util` (which only write fresh unique paths and are `parallel_safe:true`), so two concurrent invocations *could* target the same file. The coarse manifest flag cannot express "safe for reads and distinct files, unsafe for a same-file write," so the conservative MVP declares **false** (the router serializes it — no lost updates), matching the `uia.actor` "first side-effecting skill → false" precedent (D-0012). Atomic writes + `expect_sha256` are in place so a future `parallel_safe:true` (a read-only fast path, or per-file locking) is a clean, already-scaffolded follow-on.
- **reason:** Every local-model workflow past one shot needs to read/write/edit/append documents, and no Module exposed that (`fs.observer` inspects but never returns content or writes; `uia.actor` drives UI, not files). A pure-PowerShell primitive on cross-platform .NET is also the strongest possible pre-ship gate — the **real** skill runs unchanged on the cloud Linux box (no mock, like `image.util`/`audio.ingest`). Exact-string edit (not fuzzy/regex) mirrors the frontier Edit tool and keeps the op deterministic and predictable; EOL preservation is exactly what makes editing this repo's own CRLF docs safe; the `expect_sha256` precondition + atomic writes + always-on pre-image are the honest safety net for a write primitive a local model will hammer unattended.
- **alternatives:** fuzzy/regex/diff-patch editing (rejected for the MVP — exact-string is deterministic and matches the frontier tool; a regex/unified-diff apply mode is a follow-on); structured-format (JSON/YAML/CSV/DOCX) field edits (rejected — `doc.io` is a **text** primitive; format-aware editors are separate skills, and docx/pdf/xlsx already exist at the frontier); bundling move/copy/rename/delete/mkdir (rejected — that is filesystem *management*, a future `fs.manage` work order; `doc.io` only reads/writes document **content**); `parallel_safe:true` with locking now (deferred — conservative false + atomic/precondition scaffolding first); a code-page/latin-1/UTF-32 encoding matrix (deferred — UTF-8 + UTF-16-BOM detect/preserve covers the need); making it `mixed`/a producer (rejected — deterministic file ops decide nothing to review); a Python worker (rejected — .NET file I/O is richer here, needs no interpreter, and runs the real skill on the cloud gate).
- **consequences:** A new deterministic document primitive the Phase-A `agent.local` orchestrator and the Phase-B Widgets will call directly, and that composes naturally with the escalator (#19). **Tests 88/88 on the cloud pre-ship gate (real skill + real Module 1 wrapper) and 88/88 live via the executor** (`m20-test-001`, exit 0) — every op + error path + CRLF/BOM/precondition/atomic/pre-image + the named-param-overrides-`InputsJson` contract rule; 8 files sha256 byte-exact + AST-parse OK on the target. **No `models.json` / `TOOL_MODEL_REGISTRY` model / `REVIEW_QUEUE` change** (a tool, not a model; not a producer). Measured follow-ons (NOT this session): batch/directory/glob; a regex or unified-diff apply mode; structured-format field edits; a sibling `fs.manage` (move/copy/rename/delete/mkdir); more encodings; a read-only or per-file-lock `parallel_safe:true` mode + a tail/follow read; insert-at-line / replace-line-range ops. · **affects:** Module 20 (new), `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (Build priority Phase A #2 + Module 20 entry), `TOOL_MODEL_REGISTRY.md` (a `doc.io` skill entry); `REVIEW_QUEUE.md` unchanged (non-producer; producer set stays seven). · **revisit-if:** batch/glob, regex/diff editing, `fs.manage`, more encodings, or a `parallel_safe:true` mode is built (each its own scoped follow-on).


### D-0032 — agent.local: a bounded ReAct local agent loop; decisions route THROUGH logic.escalator, args/answer via model.gateway, tools from a declarative closed registry (doc.io + fs.observer); hard max_steps budget + DryRun; orchestrator-not-producer; no models.json change; the finding that small models under-use `finish`
- **date:** 2026-07-25 · **state:** locked (loop shape + escalator-for-decisions + closed tool-registry + guardrails + orchestrator/non-producer + folder-number scheme), provisional (termination policy; the MVP tool set; decision/gen tier defaults; confidence heuristic)
- **decision:** Module 21 `agent.local` (Phase A #3, per D-0029) is the local-orchestrator cost-offload keystone — the tight, useful MVP slice of `skill.orchestrator` (#26), NOT the full workflow engine. MVP design: **(1) A bounded, ReAct-style loop.** Given a natural-language `goal` it runs, per step: **decide** the next action → (if not `finish`/over-budget) **generate** the tool arguments → **invoke** the tool → **observe** (a bounded summary appended to a transcript) → repeat; on `finish` or `max_steps` it produces a **final answer**. It is the frontier agent's tool loop, done locally. **(2) The decision routes THROUGH `logic.escalator` (#19).** "Which tool next, or `finish`?" is posed to the escalator as a single-item closed-set **`classify`** task whose `labels` are the registered tool names + `finish` — so the escalator's deterministic **in-set gate** guarantees the returned action is a real tool (or surfaces `needs_frontier`), and its tiny→weak→mid ladder is the cost-offload. This is the literal reading of D-0029's "plans and invokes any Module **through the escalator**." **(3) Arg-generation + the final answer use `model.gateway` (#7)** directly (one call each; the args are the first brace-matched JSON object parsed from the completion, with a relative-path resolve against `working_dir`). **(4) Tools are conforming Modules invoked as child skills** — the `image.index` (#18) spawn-a-child-pwsh-and-parse-its-`lifeorch.skill.result/0.1`-envelope pattern; **reimplements nothing** (not the escalator, not the gateway, not the tools). **(5) A declarative, closed tool registry** (`tools.json`; overridable via `-ToolsPath`/`-Tools`): each entry = `{tool, skill_id, entrypoint, description, args_hint, args_example, required[], side_effecting}`. **The MVP ships exactly two tools — `doc.io` (#20) + `fs.observer` (#2)** — both already built, both non-GPU, one read-only observer + one file primitive whose writes ARE the point of "do real work." **The registry IS the sandbox: there is deliberately NO arbitrary-shell / code-exec tool** — the agent can do only what its curated conforming tools allow. **(6) Guardrails** (this is the first skill where a *local model chooses side-effecting actions*): a **hard `max_steps` budget** (default 4; exhausting → `status:"stopped"` + `needs_frontier:true` — a runaway loop cannot occur); a **`-DryRun` plan-preview** (runs the decide+arg-generate steps and records the intended tool+args per step but invokes NO tool); `needs_frontier` is a **status field**, never a frontier call or a queue write. **(7) Orchestrator, NOT a review-queue producer** (like `voice.live` #13 / `image.index` #18 / `logic.escalator` #19): it redirects every child's review writes to an in-artifact `child_review.jsonl` and never writes the canonical `review_queue.jsonl` — the seven-producer set is unchanged. **(8)** `determinism:"mixed"`, `parallel_safe:false` (drives the gateway → GPU/port, can invoke `doc.io` file mutations), `batch:false`, `streaming:false`; **no new model / no `models.json` change / no Module 7 re-verify** (it composes the wired tiers). Envelope `confidence` = the min per-step decision confidence; `model_provenance` = the stage-tagged aggregate of every child decision/gen/tool call. **(9) Folder-number scheme:** on-disk `modules/21-agent-local/` — the `NN-` prefix is a monotonic build-order counter (D-0029 decoupled it from the ARCHITECTURE_MAP 0-49 positions); `agent.local` is a scoped slice of #26, not the video-block "21."
- **the empirical finding (reported plainly, per the D-0030 ethos):** the live end-to-end run (`m21-live-001`) proved the pattern works — goal "create hello.txt containing 'hi from agent.local'" → the agent chose `doc.io` **through the escalator**, the 3B generated `{op:write,path,content}`, and **the file was written on disk with the exact content**; a second goal invoked `fs.observer`; 0 orphaned `llama-server`; canonical queue 1→1. **BUT the tiny/weak/mid models under-use the `finish` action:** both live goals ran to `max_steps` (the model re-chose a tool and re-did the already-completed action) instead of self-terminating once the goal was met. **The hard `max_steps` budget caught it every time** (`status:"stopped"`, `needs_frontier:true`, and the gateway-written final answer still correctly reported the goal as achieved) — which is exactly why the budget guardrail exists. The `finish` action itself is exercised and works in the mock harness (which reaches `finish` deterministically); the gap is small-model *termination judgment*, not the loop mechanism. This is honestly the same shape as D-0030's escalator finding: the mechanism is sound, the small-model policy layer needs tuning, and it is reported rather than hidden.
- **reason:** `agent.local` is the highest-leverage remaining cost-offload primitive after the escalator + doc.io: it lets a local model run an entire read→reason→act chore end-to-end, so the frontier stops paying for routine orchestration. Framing the tool decision as an escalator `classify` reuses the one guardrailed decision primitive the project already calibrated (in-set gate + cost-offload) instead of hand-rolling a second router; using the gateway for free-text arg/answer generation keeps the composition honest (escalator for gated decisions, gateway for generation, child skills for the work). A **closed registry with no shell tool** is the single most important scoping choice — it bounds the agent's power to a curated, contract-conforming, auditable set, which is what makes a local-model-driven side-effecting loop safe to ship at all. The `max_steps` budget + `-DryRun` are the honest safety net for exactly the termination weakness the calibration surfaced. Keeping the MVP a linear bounded loop (no sub-agents / planning DAG / reflection) matches "the frontier already orchestrates well — keep the MVP small and useful."
- **alternatives:** **A separate hand-rolled tool router instead of the escalator** (rejected — the escalator is the project's calibrated decision primitive and D-0029 says "through the escalator"; a single-tier `-DecisionTiers ["mid"]` already gives a one-model-call decision path with the in-set gate, no second router needed). **Use the escalator's `extract` kind for argument generation** (rejected — the escalator's extract gate requires each value to be *grounded* as a substring of the source, which is wrong for generated content like file text; the gateway is the right tool for free-form args). **Auto-discover the tool set from all module manifests** (deferred — a curated closed registry is safer and keeps the in-set label set small and reliable; auto-discovery is a follow-on). **Include stochastic/GPU tools (the perception/audio/generator Modules) in the MVP registry** (deferred — they bind VRAM/ports and complicate the loop; `doc.io` + `fs.observer` prove the pattern with zero GPU contention). **A shell / arbitrary-code tool** (rejected outright for the MVP — it would make the sandbox the whole machine; the registry-is-the-sandbox property is the safety model). **Add termination detection now (a deterministic goal-satisfied check or repeat-action stop)** (deferred — the `max_steps` budget already makes it *safe*; making it *optimal* is the #1 follow-on, and adding it now would expand scope past the linear-bounded-loop MVP). **`batch:true` multi-goal** / **parallel tool steps** / **warm gateway worker** (all deferred follow-ons). **Number the folder to a 0-49 position** (rejected — it is a scoped slice of #26 with no dedicated spine slot; the build-order counter is honest).
- **consequences:** A new local-orchestrator primitive the Phase-B Widgets (led by the Local Agent Console) will drive, and the first skill to let a local model plan+execute a side-effecting tool chain end-to-end. **Tests 39/39 mock off-machine (cloud pwsh 7.4.6, the real orchestrator + a mock-children harness branching on the `-ArtifactRoot` leaf + the real Module 1 wrapper) + 39/39 the same harness `-Live` on Windows (`m21-test-001`, exit 0) + a REAL end-to-end run (`m21-live-001`)** — the write-a-file money shot succeeded, `fs.observer` engaged, 0 orphaned `llama-server`, canonical queue 1→1. 10 files sha256 byte-exact + AST-parse OK on the target (`m21-verify-001`). **No `models.json` / model / `REVIEW_QUEUE` producer change** (composes the wired tiers; non-producer). **Measured, prioritized follow-ons:** (a) **better termination** — a deterministic goal-satisfied check, a repeat-(tool,args) detector that forces `finish`, or a dedicated "are-we-done?" gate (the #1 item; the small models under-use `finish`); (b) a **warm/persistent gateway worker** (shared with #7/#8/#12/#14/#16/#17/#19) to remove the per-step cold-load cost; (c) richer planning (sub-goals, reflection-retry, a planning DAG); (d) more tools in the registry (perception/audio/generator Modules) with per-tool arg schemas; (e) a `route.tasks` (#24) drain of `needs_frontier` goals; (f) registry auto-discovery from manifests; (g) a `batch` multi-goal mode / parallel independent steps; (h) calibrated decision confidence; (i) a persistent working-memory across invocations. · **affects:** Module 21 (new), Modules 19/7/20/2 (composed / invoked), `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (Build priority Phase A #3 + Module 21 entry), `TOOL_MODEL_REGISTRY.md` (an `agent.local` skill entry); `REVIEW_QUEUE.md` (a note: orchestrator/non-producer that redirects child flags, like #13/#18/#19; producer set stays seven). · **revisit-if:** termination detection is added (the models keep under-using `finish`); a warm worker lands; the tool registry grows to GPU/stochastic Modules or is auto-discovered; a `batch`/parallel mode or richer planning is built; the folder-number scheme needs revisiting when video (Phase C) is built.

### D-0033 -- gen.audio: procedural audio generation via ffmpeg lavfi; deterministic; non-producer; neural deferred
- **date:** 2026-07-25 - **state:** locked (procedural-synthesis MVP, wrap-the-binary, deterministic + parallel_safe), provisional (kind/shaping surface)
- **decision:** Module 22 `gen.audio` (Phase A #4, the generators' cheapest-first opener) is a **deterministic, procedural ffmpeg synthesizer**, NOT a neural text-to-audio model. It generates one synthetic signal per invocation from a compact spec -- `-Kind tone|chord|noise|sweep|silence` -- by building a single `-f lavfi` source (`aevalsrc` waveform expressions for tone/chord/sweep: sine/square/triangle/sawtooth summed partials with amplitude/N clip-safety and a linear-chirp phase term; `anoisesrc` seeded colored noise; `anullsrc` silence), then encoding in the same ffmpeg pass to wav/mp3/flac/opus/ogg/m4a (codec map identical to `audio.ingest`; `-bitexact` for wav; libopus rate guard -> 48 kHz). Note names map by equal temperament (A4=440). Shaping: duration (0<d<=3600), sample_rate (8000..192000), channels (1|2), amplitude (0..1), fade in/out (`afade`). Pure PowerShell wrapping the present ffmpeg 8.1 (reusing `audio.ingest`'s `Invoke-Proc` + ffmpeg/sibling-ffprobe resolution + envelope machinery). `determinism:"deterministic"` (confidence null, model_provenance empty; noise is seeded so output is byte-reproducible), `parallel_safe:true` (CPU-only, writes only its artifact dir), `batch:false`. **NOT a review-queue producer** (the seven-producer set + canonical `review_queue.jsonl` untouched, verified before==after). No `models.json` change / no Module 7 re-verify. Artifacts `audio.<ext>`/`gen.json`/`gen.md`.
- **reason:** The roadmap places `gen.audio` FIRST among generators as the *cheapest*. A probe (`m22-probe-001`) confirmed (a) ffmpeg 8.1 synthesizes sine/`anoisesrc`/`aevalsrc`/`anullsrc` to valid PCM16 WAV + encodes mp3 end-to-end (5/5 synth cases + mp3, ffprobe-valid), and (b) **no neural audio-gen stack is staged** -- neither the system python nor the speech venv has `audiocraft`/`diffusers`/`stable_audio_tools`/`audioldm`/`TTS`/`bark`, and no audio-gen model exists on disk. Neural would need a library install + a multi-GB model on a space-constrained C: and an 11 GB (cc 7.5) GPU -- the opposite of cheapest-first. Procedural synthesis is instant, robust, CPU-only, deterministic, and reuses the proven ffmpeg-wrap pattern (D-0019). It is genuinely useful now: notification beeps, alert tones/chords, reference pitches, masking/focus noise, test signals, and audio fixtures for the Widget layer and the audio track. Follows the doctrine "ship the smallest thing that works; harden (neural) only when it earns it."
- **alternatives:** (1) a **neural text-to-audio SFX model** (AudioGen/AudioLDM/Stable Audio Open) now -- rejected for the MVP (install + multi-GB download + GPU risk; not cheapest; deferred to a follow-on stochastic tier that would add `model_provenance` + a real `confidence` + review-producer behaviour). (2) **compose `audio.ingest` as a child** for format conversion (like `speech.tts`) -- rejected; generating directly to the target codec in the one ffmpeg pass keeps it self-contained + truly parallel-safe (a caller wanting EBU/peak loudness pipes the output through `audio.ingest` deliberately). (3) fold music in here -- rejected; structured music is the separate later `gen.music`. (4) `parallel_safe:false` like the GPU skills -- rejected; no shared resource is bound (CPU-only, like `audio.ingest`/`image.util`).
- **consequences:** the generator track opens with a robust, zero-cost, deterministic primitive the Phase-B Widgets can call immediately; the review queue is untouched (a deterministic skill flags nothing). Registry gains a `gen.audio` skill entry (the `ffmpeg`/`ffprobe` tool entry already exists from Module 10). **Tests:** 41/41 off-machine (cloud pwsh 7.4.6 + real cloud ffmpeg 6.1.1, real skill + real harness -- no mock) -> 8 files sha256 byte-exact + AST-parse OK on target -> **43/43 live** via the executor (`m22-test-001`, exit 0) incl. the Module 1 manifest-validator + wrapper; canonical queue before==after (1->1). - **affects:** Module 22 (new), Module 10 (reused ffmpeg machinery), `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (Build priority Phase A #4 + a Module 22 entry), `TOOL_MODEL_REGISTRY.md` (a `gen.audio` skill entry); `REVIEW_QUEUE.md` (a note: deterministic non-producer). - **revisit-if:** the neural text-to-audio SFX tier is built (its own work order); batch/multi-signal, ADSR/DTMF/Morse/metronome presets, sweep waveforms, or a direct `audio.ingest` loudness pipe is wanted (each a scoped follow-on).

### D-0034 -- gen.image: local text-to-image via Stable Diffusion 1.5 (diffusers Python worker + meta hand-off); mixed; generation-completeness confidence; eighth review producer; parallel_safe:false; diffusers installed into the speech venv
- **date:** 2026-07-25 - **state:** locked (backend = diffusers SD1.5 + Python-worker+meta + registry-driven + review producer + parallel_safe:false + venv-install), provisional (confidence heuristic; single model/tier)
- **decision:** Module 23 `gen.image` (Phase A #5, the second generator and the first NEURAL one) turns a text prompt into one image with a local **Stable Diffusion 1.5** pipeline -- the #44 architectural family (Qwen-Image / FLUX.1-schnell / SDXL) built early as a standalone Phase-A generator (D-0029). Settled after a **probe-first** pass (`m23-probe-001/002`): (1) **Backend = the `diffusers` `StableDiffusionPipeline` (fp16, CUDA)** driven by a **Python worker** (`gen_image_infer.py`, under the speech venv) with a **meta-file hand-off** to a PowerShell wrapper (`Invoke-GenImage.ps1`) -- the D-0021 `speech.tts` pattern (the wrapper reads the worker's meta JSON, never its stdout, so diffusers/torch chatter can't corrupt the parse). (2) **Model = `image.sd15`** (Stable Diffusion 1.5, diffusers **fp16**, CreativeML OpenRAIL-M), downloaded from `stable-diffusion-v1-5/stable-diffusion-v1-5` (fp16 variant, ~2.13 GB) and **staged to F:** under `23-gen-image\stable-diffusion-v1-5\`, then **load-and-generate verified live** before coding (`m23-probe-002`: 512x512 in 2.8 s, pipeline load 1.9 s, **VRAM peak 2.61 GB**, a real non-blank apple). (3) **diffusers 0.35.2 installed into the speech venv** (torch 2.11+cu128 + transformers 4.57 + accelerate + safetensors + torchvision already present; the install added only diffusers + importlib_metadata + zipp) -- and **Module 12 (`speech.tts`) safety re-verified**: torch/transformers unchanged, `qwen_tts` still imports. The system python is torch 2.2.1+**cpu** (no CUDA), so the speech venv is the only home for GPU generation. (4) **Registry-driven, decoupled from the gateway `wired` gate** (mirrors D-0020/D-0021/D-0026): resolves `image.sd15` (`type=image-gen`, `engine=diffusers`, `engine_env`=venv python, `params.variant=fp16`) from `models.json`, which stays `wired:false` for the gateway (type=llm only); added `defaults.image`/`tiers.image`. (5) **`parallel_safe:false`** -- binds the CUDA context + loads a model (like `speech.tts`/`image.interpret`). (6) **`determinism:"mixed"`**: the sampler is stochastic, seedable via `-Seed` (a fixed seed is byte-reproducible on this GPU -- confirmed live, std 64.987==64.987; `-Seed -1` picks a random seed and records the actual seed used). Envelope `confidence` = a documented **generation-completeness / non-blank heuristic** from the image pixel std (blank/uniform <=2 -> 0.1, very-low <8 -> 0.3, low <15 -> 0.5, has-content >=15 -> 0.9; NOT aesthetic quality, NOT calibrated); `model_provenance` carries model/engine/device/dtype/params/pixels/runtime. (7) **Eighth review-queue producer**: a below-`-ConfidenceThreshold` (0.5) / blank / failed generation -> one `verify_generation` item (`flagged_by:"gen.image"`, `failed_transform` <=0.15 else `low_confidence`). (8) **Controls:** `-Prompt` (required), `-NegativePrompt`, `-Width`/`-Height` (512 default; mult of 8, 128..1024), `-Steps` (20; DPM++), `-Guidance` (7.5), `-Seed`, `-Scheduler` (dpm++|euler|euler_a|ddim), `-Format` (png|jpg|webp). (9) **Cloud pre-ship gate = a stdlib mock worker** (`tests/mock-worker.py`, no torch/diffusers/PIL; writes a real valid PNG + a prompt-driven meta) driving the **real** wrapper -- the `speech.tts` mock-python-worker gate in its image variant, since a GPU diffusion model can't run on the Linux cloud box. `batch:false`, `streaming:false`.
- **reason:** Text-to-image is the generator the roadmap places after `gen.audio`, and the first neural one. SD 1.5 is the cheapest-first choice that actually runs here: smallest (~2 GB fp16), fastest (~3 s at 512x512), most Turing-compatible (cc 7.5), best-documented `diffusers` path, fully fitting the 11 GB RTX 2080 Ti with huge headroom (2.6 GB peak). Driving `diffusers` via a Python worker reuses the proven `speech.tts` worker+meta pattern (Python owns the model ecosystem, PowerShell owns the contract envelope); registry-driven resolution keeps the model swappable with no code change; decoupling from the `wired` gate keeps the gateway type=llm-only (Module 7 unaffected). Installing `diffusers` into the existing CUDA speech venv (vs. a new venv) is the cheapest path and was gated on a Module-12 safety re-verify.
- **alternatives:** **FLUX.1-schnell** (12B, Apache-2.0; rejected for the MVP -- needs CPU-offload or a GGUF loader to fit 11 GB, the opposite of cheapest-first; documented follow-on tier) and **SDXL / SDXL-Turbo** (rejected -- larger + non-commercial license; documented follow-on tiers); a **dedicated venv** for image gen (rejected as the MVP -- reusing the CUDA speech venv is cheaper and was safety-gated; a separate venv is the fallback if diffusers ever disturbs the speech stack); a **single-file `.safetensors` + `from_single_file`** (rejected -- the diffusers folder format loads fully offline with `local_files_only=True`, self-contained on F: per D-0015); **safety_checker enabled** (rejected -- it blackout-replaces flagged images, which breaks a deterministic generator and confuses tests; content responsibility stays with the caller; a real safety pass is a separate module); **calibrated/aesthetic-model confidence** (deferred -- the completeness/non-blank heuristic matches the family's honesty); img2img / inpainting / ControlNet / upscaling / LoRA, `num_images>1` batch, a warm/persistent pipeline worker, more schedulers (all deferred follow-ons).
- **consequences:** the generator track now spans deterministic audio (#22) + neural images (#23); the review queue has an **eighth** producer (7/8/11/12/14/16/17/**23**), and Module 9 handles the new `verify_generation` verb by construction. `models.json` gained `defaults.image`/`tiers.image` + `image.sd15` (type `image-gen`, engine `diffusers`, `wired:false`) -- **additive; Module 7 re-verified 28/28** (`m23-m7regress-001`). The **speech venv now carries `diffusers` 0.35.2** (recorded in `TOOL_MODEL_REGISTRY.md`). **A subtle test-harness bug was found + fixed:** `GetCurrentProcess().MainModule.FileName` returns `dotnet.exe` (not pwsh) when a script is launched via the `.dotnet` tools `pwsh.exe` shim on Windows, so the live harness's child-process launches silently failed (`$e` was null); the harness now resolves pwsh via `$PSHOME` (cross-platform) -- the mock gate never hit this (the cloud box has a real pwsh binary). Off-machine **42/42** (cloud mock gate) -> shipped 10 files byte-exact (sha256 + AST-parse OK on target) -> **32/32 `-Live`** via the executor (`m23-test-005`, real SD generations, same-seed byte-reproducible, real JPEG, canonical queue 1->1, 0 orphans) -> Module 7 **28/28** (`m23-m7regress-001`). License note: SD 1.5 is **CreativeML OpenRAIL-M** (permits local generation with behavioral-use restrictions), a deliberate deviation from the project's Apache-2.0 preference taken for the cheapest-first working model; FLUX.1-schnell (Apache-2.0) is the documented permissive follow-on. - **affects:** Module 23 (new), Modules 9/12 (composed / safety-reverified), `models.json`, `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`, `CURRENT_STATE.md`, `MODULE_ROADMAP.md`. - **revisit-if:** a FLUX/SDXL/Turbo tier, img2img/inpainting/ControlNet/upscaling/LoRA, batch/`num_images>1`, a warm/persistent pipeline worker, calibrated/aesthetic confidence, a real prompt-safety pass, or a dedicated image-gen venv is built (each its own scoped follow-on).

### D-0035 -- gen.music: local text-to-music via MusicGen Small (transformers MusicgenForConditionalGeneration; Python worker + meta hand-off); mixed; generation-completeness confidence; ninth review producer; parallel_safe:false; NO new library install
- **date:** 2026-07-26 - **state:** locked (backend = transformers MusicGen + Python-worker+meta + registry-driven + review producer + parallel_safe:false + no-install), provisional (confidence heuristic; single model/tier)
- **decision:** Module 24 `gen.music` (Phase A #4, the third generator and the second NEURAL one) turns a text prompt into one short instrumental clip with a local **MusicGen Small** model -- the generator track's music slot (`gen.audio` #22 procedural sound -> `gen.image` #23 neural images -> **`gen.music` #24** -> `gen.video`). Settled after a **probe-first** pass (`m24-probe-001/002`): (1) **Backend = transformers `MusicgenForConditionalGeneration` (CUDA)** driven by a **Python worker** (`music_gen_infer.py`, under the speech venv) with a **meta-file hand-off** to a PowerShell wrapper (`Invoke-GenMusic.ps1`) -- the D-0021 `speech.tts` / D-0034 `gen.image` pattern (the wrapper reads the worker's meta JSON, never its stdout, so transformers/torch chatter can't corrupt the parse). (2) **Model = `music.musicgen-small`** (`facebook/musicgen-small`, transformers folder format, CC-BY-NC-4.0), downloaded and **staged to F:** under `24-gen-music\musicgen-small\`, then **load-and-generate verified live before coding** (`m24-probe-002`: a 5.06 s clip in 7.6 s, VRAM peak 2.4 GB, 32 kHz mono, `torch.manual_seed` byte-reproducible). Pruned the redundant audiocraft-format weights (`pytorch_model.bin`/`state_dict.bin`/`compression_state_dict.bin`) -> ~2.37 GB, reload-verified (`m24-prune-001`); `model.safetensors` sha256 recorded. (3) **NO new library install** -- transformers 4.57.3 already ships MusicGen (confirmed `m24-probe-001`; neither audiocraft nor the standalone encodec package is needed). This makes gen.music **cheaper + lower-risk than gen.image** (which needed a diffusers install): the speech venv package set is untouched, so **Module 12 (`speech.tts`) is unaffected by construction** (not re-run). (4) **Registry-driven, decoupled from the gateway `wired` gate** (mirrors D-0020/D-0021/D-0026/D-0034): resolves `music.musicgen-small` (`type=music-gen`, `engine=transformers`, `engine_env`=venv python) from `models.json`, which stays `wired:false` for the gateway (type=llm only); added `defaults.music`/`tiers.music`. (5) **`parallel_safe:false`** -- binds the CUDA context + loads a model (like `speech.tts`/`image.interpret`/`gen.image`). (6) **`determinism:"mixed"`**: the MusicGen sampler is stochastic, seedable via `-Seed` (a fixed seed is byte-reproducible on this GPU; `-Seed -1` picks + records a random seed). Envelope `confidence` = a documented **generation-completeness / non-silent heuristic** from the audio RMS (silent/failed <=0.005 -> 0.1, very-low <0.02 -> 0.3, low <0.05 -> 0.5, has-content >=0.05 -> 0.9; plus a duration-shortfall guard; NOT musical quality, NOT calibrated); `model_provenance` carries model/engine/device/dtype/params/tokens/audio_seconds/runtime. (7) **Ninth review-queue producer**: a below-`-ConfidenceThreshold` (0.5) / silent / failed generation -> one `verify_generation` item (`flagged_by:"gen.music"`, `failed_transform` <=0.15 else `low_confidence`; producer set 7/8/11/12/14/16/17/23/**24**). (8) **Output = 32 kHz mono PCM16 WAV** (peak-normalized to <=0.99 to avoid clipping, since MusicGen can exceed +-1.0); an optional non-wav `-Format` (mp3/flac/opus/ogg/m4a) or non-native `-SampleRate` is produced by **composing `audio.ingest` (#10)** -- the audio track wired the same direction as `speech.tts`. **Controls:** `-Prompt` (required), `-Duration` (1..30 s -> `round(duration*~50)` tokens via the model frame rate), `-Guidance` (0..15), `-Temperature` (0..2; 0=greedy), `-TopK`, `-TopP`, `-Seed`, `-Normalize`, `-Format`, `-SampleRate`. (9) **Cloud pre-ship gate = a stdlib mock worker** (`tests/mock-worker.py`, stdlib `wave`, no torch/transformers/soundfile; writes a real WAV + a prompt-driven RMS meta) driving the **real** wrapper -- the `speech.tts`/`gen.image` mock-python-worker gate in its music variant, since a GPU MusicGen model can't run on the Linux cloud box. `batch:false`, `streaming:false`.
- **reason:** Music generation is the roadmap's third generator (after procedural audio + neural images), and the second neural one. MusicGen Small is the cheapest-first choice that actually runs here: the smallest quality music model, fully within the 11 GB RTX 2080 Ti (~2.4 GB peak), Turing-compatible, and -- crucially -- **already supported by the installed transformers**, so it needs zero library install (the lowest-risk neural add yet). Driving it via a Python worker reuses the proven worker+meta pattern (Python owns the model ecosystem, PowerShell owns the contract envelope); registry-driven resolution keeps the model swappable; decoupling from the `wired` gate keeps the gateway type=llm-only (Module 7 unaffected). Composing `audio.ingest` for format conversion reuses Module 10 rather than re-encoding in Python.
- **alternatives:** **audiocraft** (Meta's MusicGen library; rejected -- transformers ships MusicGen natively, so audiocraft is an unnecessary heavy install); **Stable Audio Open** (needs `stable_audio_tools` + a gated HF download; rejected for the MVP -- not cheapest; a documented follow-on); **AudioLDM2-music via diffusers** (already have diffusers; rejected -- MusicGen is the stronger, canonical text-to-music model and needs no extra deps); **MusicGen Medium/Large** (rejected for the MVP -- larger/slower; documented follow-on tiers); **MusicgenMelody** (melody-conditioned; a follow-on); **fp16** (rejected as default -- fp32 is robust on 11 GB with headroom and avoids MusicGen's fp16 EnCodec-decode artifacts; fp16 is a follow-on knob); **writing non-wav directly in the worker** (rejected -- composing `audio.ingest` reuses the tested encode path and keeps the worker simple); a **real/HTTP model on the cloud gate** (rejected -- a GPU model can't run on the Linux box; the stdlib mock-worker gate exercises the same wrapper path). CC-BY-NC-4.0 is **non-commercial** -- a deliberate deviation from the Apache-2.0 preference, precedented by SD 1.5's OpenRAIL-M in gen.image (D-0034); MusicGen weights are the standard local text-to-music choice and this is local generation.
- **consequences:** the generator track now spans deterministic audio (#22) + neural images (#23) + neural music (#24); the review queue has a **ninth** producer (7/8/11/12/14/16/17/23/**24**), and Module 9 handles the `verify_generation` verb (shared with gen.image) by construction. `models.json` gained `defaults.music`/`tiers.music` + `music.musicgen-small` (type `music-gen`, engine `transformers`, `wired:false`) -- **additive; Module 7 re-verified 28/28** (`m24-m7regress-001`). The **speech venv is unchanged** (no install) so Module 12 needs no re-verify. Off-machine **49/49** (cloud mock gate, cloud pwsh 7.4.6) -> shipped 10 files byte-exact (sha256 + AST-parse OK on target, `m24-verify-001`) -> **42/42 `-Live`** via the executor (`m24-test-002`: real MusicGen generations, same-seed byte-reproducible, mp3 + resample via the real `audio.ingest`, canonical queue 1->1, 0 orphaned python/llama-server) -> Module 7 **28/28** (`m24-m7regress-001`). A test-assertion robustness fix: the `echo.params` case now accepts `ok|partial` (a nonsense prompt legitimately produced a low-RMS clip the skill correctly flagged -> `partial`; the D-0027 mode-robust-assertion pattern). - **affects:** Module 24 (new), Modules 9/10 (composed) / 12 (unaffected, no venv change), `models.json`, `TOOL_MODEL_REGISTRY.md`, `REVIEW_QUEUE.md`, `CURRENT_STATE.md`, `MODULE_ROADMAP.md`. - **revisit-if:** a MusicGen Medium/Large or Stable Audio Open tier, MusicgenMelody (melody-conditioned), batch/multi-clip, a warm/persistent worker, calibrated/aesthetic confidence, a prompt-safety pass, stereo, or >30 s via sliding-window continuation is built (each its own scoped follow-on).
