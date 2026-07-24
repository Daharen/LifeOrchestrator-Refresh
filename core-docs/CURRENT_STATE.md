# CURRENT_STATE

Owns **reality as it exists now** — not intended architecture. Keep it compact; history goes elsewhere.
**Update this at the end of every work session.** A machine-readable `CURRENT_STATE.json` counterpart
is planned (serves scripts and weaker local models) but not yet created.

- **Project phase:** MVP module build-out.
- **Active module:** _none in progress._ **Modules 0–8 complete** (0 executor · 1 `skill.bootstrap` · 2
  `fs.observer` · 3 `proc.observer` · 4 `uia.inspector` · 5 `uia.actor` · 6 `capture.screen` · 7 `model.gateway` ·
  8 `classify.batch`), plus **Module 00.1 — Executor Watchdog & Recovery (`exec.watchdog`)** (infrastructure).
  **Module 8 — Batch Classification & Sorting (`classify.batch`) is MVP complete this session** — the **first real
  consumer of `model.gateway`**: for each item in a batch it calls the gateway (default `-Tier weak` = 1.5B) with a
  mode-specific prompt (`classify` one-label / `multilabel` / `extract` fields), parses the completion, computes a
  classification confidence (completeness+validity heuristic), groups the items, and routes below-threshold items to
  `review_queue.jsonl` (`flagged_by:"classify.batch"`; it **suppresses** the gateway's own review writes to keep the
  canonical queue correctly attributed). `determinism:"mixed"`, `batch:true`, `parallel_safe:false`. **Tests 33/33 via
  the executor** (`m8-test-001`, exit 0, ~26s). **Module 9 — Review Queue Processor (`review.processor`) is next**
  (author its work order next session). Note: **the review queue now has two producers** — `model.gateway` and
  `classify.batch`.
- **Repo / working dir:** **`C:\Users\just_\LifeOrchestrator-Refresh\`** — the clean standalone home for
  **Life Orchestrator** (near-term local-skills track; git-initialized). Layout: `core-docs/` (these docs)
  and `modules/<NN>-<name>/` (one per module). **Reference sources (separate, not built here):** the earlier
  assistant codebase `LifeOrchestrator\repo` (fold in later) and the separate **Project Proteus** game
  (`Project-Proteus-src`).
- **Executor status:** MVP complete, **running.** **Canonical instance:** the Life Orchestrator executor at
  `LifeOrchestrator-Refresh/modules/00-bootstrap-executor/` (pwsh 7.4.6, host `DESKTOP-PF5FFMF`). It crashed
  once mid-session (2026-07-24T06:26:36Z, instance `0a1f8e69…`, transient file-lock — see Known failures), was
  **restarted** and is now instance `857d7251…` (up 13:52Z); restart recovery correctly marked the orphaned
  `m5-example-001` as `abandoned_after_restart`. The original at `proteus_repo/tools/trusted-bootstrap-executor/`
  was stopped earlier; the physical `proteus_repo/tools/` leftover removal is still pending
  (`ops/finish-game-cleanup.bat`). **Now covered by the watchdog (Module 00.1):** launch `ops/start-watchdog.bat`
  for unattended resilience — it auto-restarts the executor on crash/hang and stands down on a graceful stop.
  **The live executor was restarted onto the marker code and is now instance `51061264…` (pid 4844), emitting
  `control/heartbeat.json`/`last-exit.json` (heartbeat fresh 2026-07-24T17:26Z; it has since run the Module 7 and
  Module 8 tasks — `m8-smoke-001`/`m8-test-001`, both `completed` exit 0). The earlier "restart it once" action is resolved.**

## Completed modules
- **Module 0** — Trusted High-Risk Bootstrap Executor. 12/12 integration tests pass on Windows.
- **Module 1** — Skill Contract & Registry Bootstrap (`skill.bootstrap`). Reference skill `ref.echo`,
  contract validators (`lib/SkillContract.psm1`), and a generic wrapper (`Invoke-Skill.ps1`). Runs directly
  and through the executor; emits schema-valid `lifeorch.skill.result/0.1`. Module tests 11/11 (2026-07-24).
- **Module 2** — Filesystem Observer (`fs.observer`). Deterministic depth-bounded tree + name/glob search;
  `tree.md` + `index.json` artifacts; contract-valid envelope; runs direct/wrapped/executor. Tests 16/16 (2026-07-24).
- **Module 3** — Process & Window Observer (`proc.observer`). Snapshot of processes + top-level windows +
  foreground (Win32); `report.md` + `processes.json` + `windows.json`. Tests 16/16 (2026-07-24).
- **Module 4** — UI Automation Inspector (`uia.inspector`). Read-only UIA control-tree walk of a target
  window/desktop (control type, name, automation id, bounds, patterns, state); `tree.md` + `elements.json`. Tests 16/16 (2026-07-24).
- **Module 5** — UI Automation Actor (`uia.actor`). **Acting** half of UIA: invoke/toggle/select/expand/
  collapse/setvalue/focus on an element located by automation id / name / control type / inspector child-path.
  UIA control patterns only (no synthetic input); `-DryRun`/`-WhatIf` preview; `parallel_safe:false` (first
  side-effecting skill). `action.md` + `action.json` artifacts. **Tests 26/26 via executor (2026-07-24)** —
  incl. real invoke/toggle/setvalue self-verified against a self-contained WinForms probe window. Committed `1691d16`.
- **Module 6** — Screenshot & Region Capture (`capture.screen`). **Visual-capture** complement to the UIA
  skills: resolve a target (monitor `index|all|primary` / window by hwnd|pid|title / app by process name /
  explicit rectangle) to one virtual-desktop rectangle, then GDI `CopyFromScreen` → **PNG** (or JPG q90) image
  artifact + `capture.json`/`capture.md`. Read-only (`parallel_safe:true`, `screen:true`), Per-Monitor-V2 DPI
  aware, multi-monitor. **Tests 39/39 via executor (2026-07-24)** — monitor(primary/all), region(png+jpg),
  window (self-verified against a WinForms probe), all error paths, wrapper; smoke `m6-smoke-001` captured a
  real dual-monitor primary (1920×1080).
- **Module 00.1** — Executor Watchdog & Recovery (`exec.watchdog`). **Cooperative** supervisor: autonomously
  restarts the executor on crash/hang (no approval), stands down on an authorized graceful stop; on-demand
  `Recover-Executor.ps1 -Force`. Not perpetual, no boot persistence, visible + self-killable (D-0013, honors
  D-0001). Adds `heartbeat.json`/`last-exit.json` to Module 0 (additive; 12/12 unaffected). Tests 22/22 (2026-07-24).
- **Module 7** — Local Model Gateway (`model.gateway`). Common interface that runs local **LLMs** (GGUF) via the
  llama.cpp **`llama-server`** (start → `/health` → `/v1/chat/completions` → kill), model chosen from a declarative
  `models.json` by `-Model` id / `-Tier` alias (tiny/weak/mid/strong) / default. Declares STT/TTS/embedding (staged;
  `model_not_wired` until Modules 11/12/23). **First stochastic/mixed skill:** populates `model_provenance` (tokens/
  timings/finish_reason/device) + a generation-completeness `confidence` (stop→0.7, length→0.4, empty→0.1; `<0.5` →
  `review_queue.jsonl`). `parallel_safe:false`. Artifacts `output.txt`/`exchange.json`. **Tests 28/28 via executor
  (2026-07-24)** — live gen on staged 0.5B/1.5B, truncation→review-queue, error paths, wrapper, clean server teardown.
  See D-0015 (large-data), D-0016 (gateway design).
- **Module 8** — Batch Classification & Sorting (`classify.batch`). **First real consumer of `model.gateway`.** Three
  modes over a list of `{id?,text}` items: `classify` (exactly one label from a closed set — also routing/sorting),
  `multilabel` (zero+ labels), `extract` (named fields → JSON). Calls the gateway **once per item** (`-Tier weak`
  default) with a mode-specific prompt at temp 0 / fixed seed; parses the completion; computes a per-item
  classification **confidence** (documented completeness+validity heuristic, NOT calibrated — classify: in-set+stop
  0.8 / fuzzy 0.6 / out-of-set 0.2; multilabel 0.75/0.7/0.5/0.15; extract 0.75/0.5/0.3/0.1; `length` caps ≤0.4);
  groups items (`label→[ids]`); appends below-threshold items (default 0.5) to `review_queue.jsonl` as
  `lifeorch.review.item/0.1` `flagged_by:"classify.batch"` with per-item `source_ref`. **Suppresses the gateway's own
  review writes** to an in-artifact `_gateway_review_suppressed.jsonl`. Envelope `confidence` = mean per-item;
  `model_provenance[]` = one aggregate entry (summed tokens, call count, total runtime). `determinism:"mixed"`,
  `batch:true`, `parallel_safe:false`. Artifacts `classified.json`/`classified.md`. **Tests 33/33 via executor
  (2026-07-24)** — five error paths, live classify(0.5B)/extract, explicit-model(1.5B) resolve, review routing +
  gateway suppression, wrapper, no orphaned `llama-server`; smoke `m8-smoke-001` labeled animal/vehicle correctly.
  See D-0017. **Throughput caveat:** one gateway call per item × per-call model load (D-0002/D-0016) — fine for
  small/unattended batches; warm-worker/intra-batch-prompt is a follow-on.

## Installed dependencies (verified this machine)
- **PowerShell 7.4.6** — installed as a .NET global tool at
  `C:\Users\just_\.dotnet\tools\pwsh.exe`. (Was **not** present before; installed 2026-07-24.)
- **.NET SDK 9.0.100** — `C:\Program Files\dotnet\dotnet.exe`.
- **git** — on PATH. **winget** — present (user WindowsApps). **choco** — not installed.
- **WinForms + STA runspace** work in the dotnet-tool pwsh (`System.Windows.Forms` loads; an STA runspace
  can host a Form + `Application.Run`) — verified 2026-07-24 (used by the Module 5 probe test).
- Not admin. No system-wide `pwsh` (only the user `~\.dotnet\tools` entry — resolves in new shells).

## Installed local models
- **Discovered + registered (2026-07-24).** 4 LLM GGUF (Qwen2.5 0.5B/1.5B/3B + Qwen3.5-27B; all `wired` via
  `model.gateway`), 1 STT (Whisper base.en), 2 TTS voices + 1 tokenizer (Qwen3-TTS 0.6B/1.7B), 1 embedding
  (Qwen3-Embedding-0.6B). **All copied to portable F: storage** (`…\LifeOrchestrator-Refresh_Large_Data\
  _pending-model-storage\`, ~27.4 GB). Full inventory + sizes + engines in `TOOL_MODEL_REGISTRY.md`; relocation plan
  in that folder's `MIGRATION.md`. Non-LLM models are declared but wired in their own modules (11/12/23).

## Available hardware (measured 2026-07-24)
- **CPU** Intel i9-9900KF (8c/16t @3.6GHz) · **RAM** 64 GB · **GPU** NVIDIA RTX 2080 Ti **11 GB VRAM** (CUDA,
  driver 591.74, cc 7.5) · **OS** Windows 10 Pro 19045 x64. Host `DESKTOP-PF5FFMF`, user `just_`.
- **Drives (fixed):** C: 893 GB (**~67 GB / 7.5% free — constrained**), E: "Game Drive" 858 GB (~534 GB free),
  **F: "Storage space" 3.72 TB (~1.78 TB free)** = the large-data home. (No D: on this box.)
- Full profile + runtimes in `TOOL_MODEL_REGISTRY.md` (Hardware profile).

## Active model servers
- None persistent. `model.gateway` starts a **transient `llama-server`** on a free loopback port per call and kills
  it when done (no warm/persistent worker yet — D-0002).

## Known working invocation paths
- Executor: `pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1` /
  `...\Submit-BootstrapTask.ps1` / `...\Stop-BootstrapExecutor.ps1` (from the module dir).
- Direct pwsh (any script): `C:\Users\just_\.dotnet\tools\pwsh.exe -NoProfile -File <script>`.
- Skill (direct): `pwsh -NoProfile -File modules\01-skill-bootstrap\skills\ref.echo\Invoke-RefEcho.ps1 -Message <s> -Repeat <n>`.
- Skill (wrapped): `pwsh -NoProfile -File modules\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir <skill dir> [-InputsJson '<json>']`.
- Skill (through executor): submit a task package whose `task.ps1` calls either entrypoint; read the
  envelope from `runtime/completed/<task_id>/stdout.txt`.
- uia.actor (direct): `pwsh -NoProfile -File modules\05-uia-actor\Invoke-UiaActor.ps1 -Title '<glob>' -Action <invoke|toggle|select|expand|collapse|setvalue|focus> [-AutomationId|-Name|-ControlType|-Path <loc>] [-Value <s>] [-DryRun]`.
- capture.screen (direct): `pwsh -NoProfile -File modules\06-capture-screen\Invoke-CaptureScreen.ps1 [-Target <monitor|window|app|region>] [-Monitor <index|all|primary>] [-Hwnd|-ProcessId|-Title <loc>] [-App <glob>] [-X -Y -Width -Height] [-Format <png|jpg>]` (or `-InputsJson '<json>'`).
- model.gateway (direct): `pwsh -NoProfile -File modules\07-model-gateway\Invoke-ModelGateway.ps1 [-Model <id>|-Tier <tiny|weak|mid|strong>] -Prompt '<s>' [-System '<s>'] [-MaxTokens -Temperature -TopP -TopK -Seed]` (or `-InputsJson '<json {…,messages[]}>'`). Registry: `modules\07-model-gateway\models.json`.
- User ops (click-to-run): `ops/*.bat` — start/stop/restart/status the executor and run tests; each writes
  output to `ops/out/` for the agent to read.
- Watchdog: `ops/start-watchdog.bat` (supervise), `ops/stop-watchdog.bat`, `ops/recover-executor.bat [-Force]`;
  direct `pwsh -NoProfile -File modules\00.1-exec-watchdog\Watch-Executor.ps1` / `...\Recover-Executor.ps1`.

## Current tests
- Executor: `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` — 12/12 pass
  (invoke with `-PwshPath 'C:\Users\just_\.dotnet\tools\pwsh.exe'`; see Known failures).
- Module 1: `modules/01-skill-bootstrap/tests/Invoke-SkillBootstrapTests.ps1` — 11/11 pass (2026-07-24).
- Module 2: `modules/02-fs-observer/tests/Invoke-FsObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 3: `modules/03-proc-observer/tests/Invoke-ProcObserverTests.ps1` — 16/16 pass (2026-07-24).
- Module 4: `modules/04-uia-inspector/tests/Invoke-UiaInspectorTests.ps1` — 16/16 pass (2026-07-24).
- Module 5: `modules/05-uia-actor/tests/Invoke-UiaActorTests.ps1` — **26/26 pass** (manifest, dry-run,
  five error paths, wrapper, and live setvalue/toggle/invoke + dry-run-invoke against a WinForms probe;
  run 2026-07-24 via the executor as `m5-test-001`, exit 0, 13s).
- Module 00.1: `modules/00.1-exec-watchdog/tests/Invoke-WatchdogTests.ps1` — **22/22 pass** (pure decision
  logic; `Test-ExecutorAlive`; `Get-ExecutorState`; Module 0 heartbeat/last-exit markers; and integration on
  temp runtimes: watchdog auto-restarts a crash and stands down on an authorized stop; `wd-test-002` 2026-07-24).
  Module 0 regression re-run **12/12** with the additive markers (`wd-precheck-001`).
- Module 6: `modules/06-capture-screen/tests/Invoke-CaptureScreenTests.ps1` — **39/39 pass** (manifest;
  monitor primary/all; region png+jpg with PNG/JPEG magic-byte + sha256 checks; six error paths; wrapper; and
  a live window capture self-verified against a WinForms probe; run 2026-07-24 via the executor as
  `m6-test-001`, exit 0, ~138s).
- Module 7: `modules/07-model-gateway/tests/Invoke-ModelGatewayTests.ps1` — **28/28 pass** (manifest; registry
  declares all modalities + 4 wired LLMs; five error paths incl. `model_not_found`/`model_not_wired`/
  `registry_not_found`; **live** generation on the staged 0.5B via `-Tier tiny` — status ok, finish_reason stop,
  confidence 0.7, provenance with token counts, artifact sha256 verified; wrapper ran the 1.5B; a forced
  truncation → confidence 0.4 → a valid review-queue item; no orphaned `llama-server`; run 2026-07-24 via the
  executor as `m7-test-002`, exit 0, ~15s).
- Module 8: `modules/08-classify-batch/tests/Invoke-ClassifyBatchTests.ps1` — **33/33 pass** (manifest +
  batch/parallel_safe/determinism flags; five setup error paths `no_labels`/`no_items`/`invalid_mode`/`no_fields`/
  `gateway_not_found`; **live** `classify` batch of 3 on `-Tier tiny` (each item labeled in-set, groups partition,
  aggregate provenance calls=3, `classified.json` sha256 verified); explicit `-Model` 1.5B resolves; **live**
  `extract` returns the requested keys; review routing at threshold 0.99 → a `classify.batch` review item with
  per-item `source_ref` and the gateway's writes suppressed from the canonical queue; Module 1 wrapper; no orphaned
  `llama-server`; run 2026-07-24 via the executor as `m8-test-001`, exit 0, ~26s). A cloud-only mock-gateway harness
  (`tests/mock-gateway.ps1`) validated the parse/confidence/group logic off-GPU before shipping.

## Known failures / gotchas
- **Executor fatal-crashed on a transient file lock (2026-07-24T06:26:36Z).** While task `m5-example-001`
  was running (a task that launched a GUI subprocess and where the agent was also reading `runtime/` over
  the device-bridge mount), the executor died with `The process cannot access the file because it is being
  used by another process` and `Error during cancellation: ...`, then `Executor stopped`. Likely a
  directory-move (running→completed/failed) or state-write colliding with an open handle (possibly the
  Linux-mount reader, or the task's own child process). **Fixed two ways (2026-07-24):** (1) externally
  auto-recovered by the watchdog (Module 00.1); (2) **in-process self-heal** — `Invoke-WithFileRetry` now
  wraps the atomic state-writes (`Write-JsonAtomic`) and the queue finalization move (`Move-FinalizedTask`),
  and a per-iteration loop guard catches `IOException`/`UnauthorizedAccessException` and continues, so this
  crash class no longer kills the executor. Module 0 tests remain **12/12** with the self-heal. Operational
  note still worth keeping: avoid holding handles on `runtime/` from the mount while tasks run; keep polls brief.
- The dotnet-tool `pwsh` shim reports its process path as `dotnet.exe`, so `(Get-Process -Id $PID).Path`
  is **not** a reliable pwsh locator. Pass explicit pwsh paths. Executor/harness already accept `-PwshPath`.
- **`@($list)` on a raw `System.Collections.Generic.List[object]` throws "Argument types do not match"**
  (pwsh 7.4.6) when it holds `[pscustomobject]`s — use `$list.ToArray()`. Module 5 uses `.ToArray()` throughout.
- The **latest** `PowerShell` .NET global-tool package is malformed (missing tool manifest); pin a
  version (7.4.6 used).
- Launching a live GUI probe window from *inside* a background executor task can hang that task's UIA calls
  if the window's UI thread stops pumping (observed once with `m5-example-001`). The Module 5 **test** harness
  drives a probe reliably; prefer side-effect-free dry-runs when capturing examples to avoid GUI-in-task risk.
- Skill scripts must write **only** the JSON envelope to stdout (diagnostics to stderr); the executor
  captures stdout verbatim into `stdout.txt`, which is parsed as the envelope.
- **PowerShell empty-array unroll (pwsh 7.4.6, StrictMode):** `$x = if(cond){@($y)}else{@()}` assigns **`$null`**
  when the empty-array branch is taken (an empty array written from a block unrolls to nothing), so a later
  `$x.Count` throws "The property 'Count' cannot be found." Assign the array first (`$x=@(); if(cond){$x=@($y)}`).
  Hit + fixed in `model.gateway` (empty `-Stop`).
- **PowerShell array double-wrap (pwsh 7.4.6):** a helper that does `return ,$out` (comma to prevent unrolling) and
  is then collected with `@(helper)` yields a **1-element array whose single element is the inner array**, not the
  N elements — so a later `foreach`/lookup silently iterates once over the whole array (no error; wrong results). In
  `classify.batch` this made label matching quietly fail while the labels list still *looked* right in the envelope.
  Fix: build into a `List[object]` and `return $acc.ToArray()` (no leading comma); let `@(...)` re-collect normally.
- **`$var:` in a double-quoted string** (e.g. `"item $id: done"`) parses `$id:` as a scope/drive reference and is a
  **syntax error** — delimit with `${id}` (`"item ${id}: done"`). Cheap to catch: parse every shipped `.ps1` with
  `[System.Management.Automation.Language.Parser]::ParseFile` before submitting (the cloud agent installed pwsh 7.4.6
  on Linux purely to parse-check + run a mock-gateway logic harness off-GPU before shipping Module 8).
- **This llama.cpp build (b8661) `llama-cli` is interactive-only** — it rejects `-no-cnv` ("use llama-completion
  instead", which isn't built) and decorates stdout with a banner/`>`/timing footer. Script LLMs via **`llama-server`**
  (`/v1/chat/completions` → clean JSON with `finish_reason`/`usage`/`timings`), as `model.gateway` does.
- **Child-process pipe deadlock:** reading a child's stdout to end while its stderr pipe fills (llama.cpp logs a lot)
  deadlocks. Drain both streams async (`ReadToEndAsync`) or redirect to files, and close the child's stdin. (The
  gateway uses `Start-Process` with file-redirected server logs; probes used async reads.)
- `capture.screen` uses screen-pixel copy (`CopyFromScreen`): an **occluded** window captures whatever covers
  it and a **minimized** window returns a `window_minimized` error — it does **not** raise/activate windows
  (read-only). Per-Monitor-V2 DPI awareness is set once per process (ignored if already set). Off-screen /
  `PrintWindow` compositing is deferred (Module 6 follow-on). Note (Linux only, does not affect the Windows
  executor): `System.Drawing.Common` is Windows-only, so `capture.screen` cannot even be dry-run on a
  non-Windows host — the cloud agent validated it by pwsh syntax-parse + Roslyn compile of the embedded C#,
  then ran it on the Windows executor.

## Unresolved questions
- Root cause of the executor file-lock crash (see Known failures) — reproduce and harden Module 0.
- Install pwsh system-wide (winget, needs UAC) vs. keep the per-user dotnet-tool build.
- Contract finalization: fold the provisional Module 1 conventions (artifact-root resolution, `-InputsJson`
  generic arg passing, `lifeorch.skill.invocation_report/0.1`) into `SKILL_CONTRACT.md` and bump the version —
  now exercised by Modules 2–7. (See DECISION_LOG D-0009.)
- **Model relocation:** the staged models in `_pending-model-storage\` must eventually move into their owning
  modules' F: folders (Modules 7/11/12/23) and the pending folder be deleted when empty (see its `MIGRATION.md`).
- **model.gateway follow-ons:** semantic (not just completeness) confidence; a warm/persistent server if load
  latency dominates; tune the 27B `gpu_layers` for 11 GB VRAM (see REVIEW_QUEUE.md).

## Next expected action
1. Author the **Module 9 work order** (`modules/09-review-processor/WORK_ORDER.md`) and implement `review.processor`:
   a **stronger** local model (via `model.gateway`, tier `mid`/`strong`) that drains `review_queue.jsonl` — the items
   `model.gateway` and now `classify.batch` flag — adjudicating each single flagged item (setting `resolution`/
   `status`), NOT redoing whole batches. Depends on Modules 7, 8, and `REVIEW_QUEUE`.
2. Housekeeping (deferred): fold the D-0009 conventions into `SKILL_CONTRACT.md` and bump the contract version
   (now exercised by Modules 2–8; DECISION_LOG D-0009/D-0011); relocate staged models per `MIGRATION.md`; the pending
   `proteus_repo/tools/` leftover removal (`ops/finish-game-cleanup.bat`); classify.batch follow-ons (warm-worker /
   intra-batch prompt for throughput; calibrated confidence; a side-effecting `sort.files` mover) — see D-0017.

- **Last updated:** 2026-07-24 (UTC) · **Last updating agent:** Claude (Cowork — Module 8 classify.batch build session).
