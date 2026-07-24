# Work Order: Screenshot & Region Capture (`capture.screen`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 6 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#6 capture.screen`

### Problem being solved
The UIA skills (`uia.inspector` / `uia.actor`, Modules 4–5) can read and act on the *accessible*
control tree, but a large class of windows exposes **no usable UIA tree at all** — Unity/other game
engines, GPU/canvas surfaces, custom-drawn apps, remote-desktop/streamed content. For those, and for
any case where an agent needs to *see* the pixels (visual verification of a state the accessibility
layer can't describe), there is currently no way to obtain an image. This module closes that gap: the
**visual-capture complement** to the UIA skills. Given a target, it copies the corresponding rectangle
of the desktop to a PNG image artifact plus a contract-valid `lifeorch.skill.result/0.1` envelope.

### Immediate practical use
An agent (frontier or local) that hits an empty/unhelpful UIA tree — or that simply needs to confirm
"what does this actually look like right now" — calls `capture.screen` to grab a monitor, a specific
window (by hwnd/pid/title), an application's main window (by process name), or an explicit screen
rectangle. The PNG can then be fed to a local vision model (a later module) or reviewed directly, and
the geometry/metadata in the envelope lets the caller reason about coordinates. This is the sensing
half that makes visual local automation possible where structured inspection fails.

### Explicit scope (in)
- **Four capture targets** (`-Target`, or inferred from which locator is supplied):
  - `monitor` — a monitor by 0-based `-Monitor <index>`, or `-Monitor all` (the whole virtual desktop
    spanning every monitor), or `-Monitor primary` (default). Multi-monitor aware, including monitors at
    negative virtual coordinates (left of / above the primary).
  - `window` — a single top-level window resolved by `-Hwnd` | `-ProcessId` | `-Title` (glob). Uses the
    window's true on-screen frame (DWM extended frame bounds, falling back to `GetWindowRect`).
  - `app` — an application's main window resolved by `-App <process-name glob>` (e.g. `notepad`,
    `*chrome*`); lowest matching pid among processes that own a main window (warns if several match).
  - `region` — an explicit rectangle `-X -Y -Width -Height` in virtual-desktop pixel coordinates.
- **Unifying model:** every target resolves to one rectangle in virtual-desktop coordinates, which is
  then captured in a single GDI `CopyFromScreen` path. The result always reports the resolved
  `rectangle`, the `environment` (virtual-screen bounds + per-monitor list), and the mode-specific
  `window` / `monitor` record.
- **Output image:** **PNG** (default). `-Format jpg` is also accepted (quality 90) for smaller
  artifacts. The image is written to `runtime/artifacts/<invocation_id>/capture.<png|jpg>`.
- **DPI:** the process opts into Per-Monitor-V2 DPI awareness (falls back to system DPI aware) so
  captures and window rectangles are in true physical pixels across mixed-DPI monitors.
- Emit one contract-valid `lifeorch.skill.result/0.1` envelope on stdout; write `capture.png`(/jpg) +
  `capture.json` (machine) + `capture.md` (human) artifacts. Reuse Module 1 validators / `Invoke-Skill.ps1`
  and run through the executor. `parallel_safe: true` (read-only; no desktop mutation).

### Non-goals (out — do NOT build)
- **No window management / activation** — no move/resize/minimize/restore/close and **no
  `SetForegroundWindow`** to raise an occluded target. Capture reads whatever is currently on screen at
  the target's rectangle (an occluded window captures what covers it; a minimized window is a structured
  `window_minimized` error). Bringing windows forward is a side effect and belongs to a later window
  module, not here.
- **No off-screen / occluded window compositing** (`PrintWindow`/DWM thumbnail rendering) in this MVP —
  screen-pixel copy only. Deferred (see follow-on) because it is a separate reliability problem per app.
- **No image post-processing** — no resize/downscale/crop-after-capture/annotate/diff/OCR/encode-to-base64.
  That is `image.util` (Module 15) and the perception modules (14–18). This module only *captures*.
- **No continuous capture / video / streaming / screen-recording** — one still image per invocation.
  Timelapse/video is Modules 19–22.
- **No multi-target batch** — one target per invocation (`batch:false`). Composition is Module 26.
- **No synthetic input, no concealment/persistence/propagation/monitoring-evasion** (executor hard
  prohibition). The skill runs once, in the foreground, as ordinary visible activity.

### Dependencies
- Modules: **1** (`SkillContract.psm1` validators, `Invoke-Skill.ps1` wrapper). Runs through Module **0**
  (executor). Complements Modules 4–5 (used when their UIA tree is empty/insufficient).
- Tools/models: `pwsh>=7.4` (registry `pwsh`); `System.Windows.Forms` + `System.Drawing` (GDI capture,
  monitor geometry) — WinForms/Drawing load in the dotnet-tool pwsh (verified 2026-07-24, Module 5); Win32
  `user32`/`dwmapi` via `Add-Type` (window rect, enumeration, DPI). No models.
- Contract features: manifest `lifeorch.skill.manifest/0.1`; result `lifeorch.skill.result/0.1`;
  `-InputsJson` generic arg convention and artifact-root convention (DECISION_LOG D-0009).

### Skill contract requirements
- `skill_id` = `capture.screen`; `name` = `Screenshot & Region Capture`; `version` = `0.1.0`;
  `determinism` = `deterministic` (definite pixel copy of live screen state, no model; `confidence` = null);
  `parallel_safe` = **true** (read-only — multiple captures may run concurrently, unlike `uia.actor`);
  `batch` = false; `streaming` = false. `requirements.screen` = **true**; `filesystem` = `write` (it writes
  the image artifact).
- `result` shape: `{ mode, requested, capture, window, monitor, environment }` where
  `capture = { rectangle{x,y,width,height}, format, image_width, image_height, path, bytes, sha256 }`
  (null on failure), `window`/`monitor` are the mode-specific records (null otherwise), and
  `environment = { virtual_screen{...}, monitors[] }`. `confidence` null; `model_provenance` empty.
  Artifacts: `capture.png`|`capture.jpg` (png/jpeg), `capture.json` (json), `capture.md` (markdown).

### Inputs and outputs
- **Inputs** (named params and/or `-InputsJson`):
  - `target` string (opt): `monitor|window|app|region`. If omitted, inferred: a window locator ⇒ window;
    `app` ⇒ app; an `x/y/width/height` ⇒ region; else `monitor`.
  - `monitor` string (opt, default `primary`): `<index>` | `all` | `primary`.
  - `hwnd` int · `pid` int · `title` string glob (opt) — window locators.
  - `app` string glob (opt) — process-name locator for `app` mode.
  - `x` `y` `width` `height` int (opt) — region rectangle (virtual-desktop coords).
  - `format` string (opt, default `png`): `png` | `jpg`.
- **Outputs:** the `result` object above in the envelope; artifacts `capture.<png|jpg>` + `capture.json`
  + `capture.md` under `runtime/artifacts/<invocation_id>/` (plus `stderr.txt`, `result.json` per convention).

### Artifact structure
- `runtime/artifacts/<invocation_id>/capture.png` (or `.jpg`) — the captured image.
- `runtime/artifacts/<invocation_id>/capture.json` — machine record: full result payload + `lifeorch.capture/0.1` tag.
- `runtime/artifacts/<invocation_id>/capture.md`   — human summary (mode, target, rectangle, image dims, monitors).
- `runtime/artifacts/<invocation_id>/stderr.txt`, `result.json` — per contract.

### Proposed implementation
- **Language:** PowerShell (per language policy — Windows screen/geometry MVP; same stack as Modules 3–5;
  wraps GDI/WinForms/Win32 via `Add-Type`). No new executable to install.
- Approach: set Per-Monitor-V2 DPI awareness (fallback system-aware). Enumerate monitors via
  `System.Windows.Forms.Screen.AllScreens` + `SystemInformation.VirtualScreen`. Resolve the requested
  target to a single virtual-desktop rectangle: monitor bounds / window frame (DWM extended frame bounds
  → `GetWindowRect` fallback; `IsIconic` ⇒ `window_minimized`) / process main window / explicit rect.
  Capture with `Graphics.CopyFromScreen` into a `Bitmap` and `Save` as PNG (or JPEG q90). Build the
  envelope with the same helper shape as Modules 4–5 (UTF-8 no BOM; only the envelope on stdout; lists
  emitted via `.ToArray()` to avoid the `@($list)` pitfall). Window title resolution uses a compact
  `EnumWindows` P/Invoke (visible, titled top-level windows).

### External tools or models
- None beyond `pwsh` + WinForms/Drawing + `user32`/`dwmapi` P/Invoke, all present/verified
  (`TOOL_MODEL_REGISTRY.md`). No install needed.

### Installation steps
- None. Files live in `modules/06-capture-screen/`.

### Tests (`tests/Invoke-CaptureScreenTests.ps1`, run via the executor)
- **Manifest** validates (`Test-SkillManifest`).
- **Monitor** — `primary` capture: valid envelope, status ok/partial, `mode=monitor`, `capture` non-null,
  image file exists on disk, its bytes' sha256 equals `result.capture.sha256`, `image_width/height > 0`,
  PNG magic bytes present, exit 0. `all` capture: rectangle equals the virtual screen bounds.
- **Region** — `-Target region -X 0 -Y 0 -Width 120 -Height 80`: image is exactly 120×80; PNG magic.
  A `jpg` region capture: `result.capture.format=jpg`, `capture.jpg` exists, JPEG magic (FF D8).
- **Window** — against a self-contained WinForms probe window (STA runspace helper `Start-CaptureProbe.ps1`,
  unique title, auto-closes, guaranteed teardown): capture by `-Title` ⇒ status ok/partial, `window`
  non-null, `window.title` matches the probe, `image_width/height > 0`, `bounds_source` in {dwm,getwindowrect}.
- **Error paths** (all side-effect-free, must be valid error envelopes, exit 0): `invalid_target`;
  `invalid_format`; `invalid_region` (width/height 0); `monitor_not_found` (index 999); `no_target`
  (`-Target window` with no locator); `target_not_found` (`-Target window -Title <no-such>`).
- **Wrapper** integration: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{region…}'` ⇒ `manifest_valid` &
  `envelope_valid` true.

### MVP acceptance criteria
- [ ] Manifest validates; entrypoint accepts named params **and** `-InputsJson`.
- [ ] Each of monitor(primary/all/index) / window / app / region reachable; monitor + region + window
      proven to really capture (image on disk, dims correct, sha matches), multi-monitor geometry reported.
- [ ] PNG (default) and JPG both produce a valid image file with correct magic bytes.
- [ ] Every failure mode returns a **valid** `lifeorch.skill.result/0.1` error envelope (exit 0), never a crash.
- [ ] Runs direct, wrapped, and through the executor; artifacts written; tests all pass.

### Manual verification procedure
- `capture.screen -Target monitor -Monitor primary` → open `capture.png`; confirm it shows the primary
  display. Open Notepad, `capture.screen -App notepad` → confirm the PNG shows the Notepad window.

### Documentation requirements
- Skill `README.md`, `skill.json` manifest, `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `capture.screen` entry to `TOOL_MODEL_REGISTRY.md` (status installed, location, invocation, targets,
  I/O, limitations, last test).

### State updates
- `CURRENT_STATE.md` (Module 6 complete, tests, next action = Module 7) and `MODULE_ROADMAP.md`
  (Module 6 → MVP complete). Log the capture-scope decisions (screen-pixel copy vs. PrintWindow;
  `parallel_safe:true`) in `DECISION_LOG.md`; add any residual uncertainty to `REVIEW_QUEUE.md`.

### Known follow-on work (defer — not this session)
- `PrintWindow`/DWM-thumbnail capture of occluded or off-screen windows; capturing a specific monitor a
  window sits on; cursor inclusion; capture-then-downscale / crop / base64 for cheap vision-model feeding
  (belongs to `image.util` Module 15); multi-target batch; per-window client-area-only capture. → later
  work orders / Modules 15–18, 26.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g. adding window activation, PrintWindow compositing,
  or image post-processing) — stop, write it into the roadmap.
- A required capability (WinForms/Drawing/GDI capture) is missing and working around it is non-trivial —
  stop, note it in `REVIEW_QUEUE.md`.
- The contract lacks something needed — stop, propose the change in DECISION_LOG, do not freelance.
- **MVP acceptance met — stop; do not start Module 7.**
