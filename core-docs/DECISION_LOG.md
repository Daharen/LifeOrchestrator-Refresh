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
