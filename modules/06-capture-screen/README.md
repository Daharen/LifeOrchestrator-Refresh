# Module 6 — Screenshot & Region Capture (`capture.screen`)

The **visual-capture** complement to the UIA skills (Modules 4–5). When a window exposes no usable UIA
tree (Unity/other game engines, GPU/canvas surfaces, custom-drawn or streamed content) or when an agent
simply needs to *see* the current pixels, this skill copies the relevant rectangle of the desktop to a
PNG (or JPG) image artifact plus a contract-valid `lifeorch.skill.result/0.1` envelope. It is
**read-only** — it never activates, moves, resizes, or otherwise touches a window, and it uses no
synthetic input. `parallel_safe:true`.

## What it does
Every target resolves to **one rectangle in virtual-desktop pixel coordinates**, which is then captured
with a single GDI `CopyFromScreen`:

| target | how it's located | rectangle |
|--------|------------------|-----------|
| `monitor` | `-Monitor <index>` \| `all` \| `primary` (default) | that monitor's bounds, or the whole virtual desktop for `all` |
| `window`  | `-Hwnd` \| `-ProcessId` \| `-Title` (glob) | the window's DWM extended frame bounds (→ `GetWindowRect` fallback) |
| `app`     | `-App <process-name glob>` | the matching process's main window (lowest pid; warns if several) |
| `region`  | `-X -Y -Width -Height` | the explicit rectangle |

`-Target` is inferred from the supplied locator when omitted (a window locator ⇒ window; `-App` ⇒ app;
an `x/y/width/height` ⇒ region; otherwise monitor). The process opts into Per-Monitor-V2 DPI awareness so
captures are true physical pixels across mixed-DPI monitors. The result always reports the resolved
`rectangle`, the `environment` (virtual-screen bounds + per-monitor list), and the mode-specific
`window` / `monitor` record.

Emits one `lifeorch.skill.result/0.1` envelope on stdout plus `capture.png` (or `.jpg`), `capture.json`
(machine) and `capture.md` (human) artifacts.

## Run
```powershell
# A monitor (primary by default):
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor primary
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor all
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor 1
# A window (by title glob / pid / hwnd):
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Title 'Calculator*'
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -ProcessId 1234
# An application's main window (by process name):
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -App notepad
# An explicit rectangle, as JPG:
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target region -X 0 -Y 0 -Width 800 -Height 600 -Format jpg
# Generic convention / wrapper:
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -InputsJson '{"target":"monitor","monitor":"primary"}'
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"target":"region","x":0,"y":0,"width":320,"height":240}'
pwsh -NoProfile -File .\tests\Invoke-CaptureScreenTests.ps1
```
Through the executor: submit a `task.ps1` that calls the entrypoint; read the envelope from
`runtime/completed/<task_id>/stdout.txt` and artifacts from `runtime/artifacts/<invocation_id>/`.

## Inputs
| name | type | default | notes |
|------|------|---------|-------|
| target | string | inferred | monitor \| window \| app \| region |
| monitor | string | primary | index \| all \| primary (target=monitor) |
| hwnd / pid / title | int / int / glob | — | window locators |
| app | string glob | — | process-name locator (target=app) |
| x / y / width / height | int | 0 / 0 / — / — | region rectangle (virtual-desktop coords) |
| format | string | png | png \| jpg (quality 90) |

## Output
`result` = `{ mode, requested, capture, window, monitor, environment }` where
`capture = { rectangle{x,y,width,height}, format, image_width, image_height, path, bytes, sha256 }` (null
on failure), `window`/`monitor` are the mode-specific records (null otherwise), and
`environment = { virtual_screen{x,y,width,height}, monitors[] }`. Full record in `capture.json`; human
summary in `capture.md`; the image in `capture.png`/`capture.jpg`. `confidence` null (no model). Error
modes return a valid error envelope (exit 0) with codes: `invalid_target`, `invalid_format`,
`invalid_region`, `no_target`, `monitor_not_found`, `target_not_found`, `window_minimized`,
`capture_failed`, `unhandled_exception`.

## Notes / boundaries
- **Read-only, screen-pixel copy.** It captures whatever is currently drawn at the target's rectangle. An
  **occluded** window therefore captures what covers it, and a **minimized** window is a
  `window_minimized` error — the skill will **not** raise/activate a window to get a clean shot (that is a
  side effect for a later window module). Off-screen/occluded compositing (`PrintWindow`) is deferred.
- **No image post-processing** — no resize/crop/annotate/OCR/base64. That is `image.util` (Module 15) and
  the perception modules (14–18); this skill only captures.
- **One still image per invocation** — no video/screen-recording/streaming, no multi-target batch.
- **Multi-monitor:** monitors are enumerated deterministically (`Screen.AllScreens` order); `all` captures
  the full virtual desktop including monitors at negative coordinates. Per-Monitor-V2 DPI awareness is
  requested so pixels are physical resolution.
- Honors the executor's hard prohibitions: no concealment, persistence, propagation, or monitoring evasion.
- Reuses Module 1's `Test-SkillManifest` / `Test-SkillResultEnvelope` and the generic `Invoke-Skill.ps1`.
