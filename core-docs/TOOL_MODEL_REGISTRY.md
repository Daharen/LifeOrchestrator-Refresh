# TOOL_MODEL_REGISTRY

**Lookup registry** — what exists on this box and can actually be invoked. Read when **selecting or invoking** a
tool/model; add an entry the moment you install or verify one.

- **Machine-readable twin:** `modules/07-model-gateway/models.json` — the authority for **exact absolute paths,
  sha256, tiers, engine_path, gpu_layers, context**. This doc must never contradict it.
- **Not owned here:** build order / per-module status / **deferred follow-ons** → `MODULE_ROADMAP.md` · now-summary
  → `CURRENT_STATE.md` · review-queue schema + producer/consumer table → `REVIEW_QUEUE.md` · orchestrator ops →
  `FANOUT_ORCHESTRATOR_HANDOFF.md` · governor design → `ADAPTIVE_RESOURCE_GOVERNOR.md` · rationale →
  `DECISION_LOG.md` · pre-consolidation full text (full flag lists, I/O schemas, per-band confidence ladders) →
  `archive/`. **Status vocab:** installed · available · inactive · broken · planned · retired.
- **Universal skill invocation:** `pwsh -NoProfile -File .\Invoke-<Name>.ps1 <params>` (every skill also accepts
  `-InputsJson '<json>'`, same keys in snake_case), or wrapped
  `pwsh -File ..\..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '<json>'`, or as an
  `exec.bootstrap` task package. Each emits a `lifeorch.skill.result/0.1` envelope on stdout +
  `runtime/artifacts/<invocation_id>/`. Flags shown are the load-bearing subset (full sets: each `Invoke-*.ps1`).
  `ps:` = `parallel_safe` · `v:` = last verification (tests · task id · date). Review producers flag to
  `review_queue.jsonl` below confidence 0.5 unless overridden; confidences are heuristic, **not calibrated**.
- **Discipline:** never list a tool `installed` you have not invoked here; prefer `planned` until verified.

---

## 1. Host executables & runtimes

**`pwsh` — PowerShell 7.4.6** · `C:\Users\just_\.dotnet\tools\pwsh.exe` (.NET global tool; user PATH
`~\.dotnet\tools`, **not** system PATH) · `pwsh -NoProfile -ExecutionPolicy Bypass -File <script>`. Runtime for all
skills + the executor; loads managed UI Automation (`UIAutomationClient`/`UIAutomationTypes`) +
`System.Windows.Forms`/`System.Drawing`; can host a WinForms loop on an STA runspace. **GOTCHA:** the shim reports
its process path as `dotnet.exe` — pass an explicit `-PwshPath` when a skill spawns a child. **Version pinned** (the
latest tool package is broken). Verified 2026-07-24.

**`dotnet` — .NET SDK 9.0.100** · `C:\Program Files\dotnet\dotnet.exe`; installs .NET global tools without admin
(network = NuGet). **`git`** · on PATH; commits go through `dev.ship`, which holds the `res.lease` **`git`** lease
(D-0055). **`winget`** · `…\AppData\Local\Microsoft\WindowsApps\winget.exe` — **GOTCHA:** system-wide installs need
a UAC/admin approval **the automation cannot click**. All verified 2026-07-24.

**`ffmpeg` / `ffprobe` — Gyan.dev full build 8.1** · `…\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe` (package
bin `…\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-8.1-full_build\bin\`) ·
`ffmpeg -hide_banner -nostdin -y -i <in> [filters] [-ar -ac -c:a -b:a] -map_metadata -1 <out>` ·
`ffprobe -v error -print_format json -show_format -show_streams <file>`. Encoders: libmp3lame, aac, flac, libopus,
libvorbis, pcm_s16/s24/s32/f32le + video; deterministic; NVENC/CUDA available.
**GOTCHA (ffprobe shadowing):** `where.exe ffprobe` returns a **Python shim** `…\Python310\Scripts\ffprobe.exe`
*before* the real `…\WinGet\Links\ffprobe.exe` — **resolve ffprobe as the sibling of the resolved ffmpeg** (or
exclude `\Python*\Scripts\`). The Linux device-mount cannot `stat` the WinGet `Links\*.exe` reparse points (Windows
`Test-Path`/`where.exe` resolve them fine). Verified 2026-07-24 (`m10-ffprobe-001`); used by #10, #22, #25.

**`Pillow` (PIL) + `numpy`** · the **system python** `…\AppData\Local\Programs\Python\Python312\python.exe`
(**PIL 10.2.0 + numpy 1.26.4**, cv2 4.9.0); fallback = the speech venv on F: (PIL 12.2.0 + numpy 2.4.4). pHashes are
**stable across PIL/numpy versions** (`m15-probe-001`). **GOTCHA:** `image.util` uses the system python (CPU-only,
not the CUDA/speech venv) for parallel-safety; Pillow 12 dropped `transp_webp` (harmless warning). Verified 2026-07-25.

**`Windows.Media.Ocr` — system OCR engine** (id `ocr.windows.media`, `wired:false`) · WinRT
(`Windows.Media.Ocr.OcrEngine`), OS component; zero install, no admin/GPU/network/model file; recognizer languages
**en-US**; `MaxImageDimension = 10000`. Reached only via **Windows PowerShell 5.1**
`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe` (5.1.19041.6456). **GOTCHA:** **pwsh 7.4.6 cannot load
the WinRT projection** here (`m14-probe-001`) — use the 5.1 `System.Runtime.WindowsRuntime` `AsTask`/`Await`
reflection pattern; **5.1 parses a BOM-less `.ps1` as ANSI**, so any 5.1 worker must stay **ASCII-only**. Verified
2026-07-25 (used by #14).

**`tesseract` — installed, NOT wired** (id `ocr.tesseract`) · `C:\Program Files\Tesseract-OCR\tesseract.exe`
(`m14-probe-001`). The natural second `ocr.layout -Engine` (calibrated per-word confidence, hOCR/TSV,
multi-language). **OPEN follow-on.**

---

## 2. Skills & Modules

### 2.1 Skill index
`ps` = `parallel_safe` · **prod** = review-queue producer (`flagged_by` = the skill id) · det = determinism.
Paths are repo-relative; every entry also takes `-InputsJson`. Extended contracts + gotchas: §2.2.

| id (M#) | entrypoint · key params | what · contract · binding limits | v: |
|---|---|---|---|
| `exec.bootstrap` (M0) | `modules/00-bootstrap-executor/Start-BootstrapExecutor.ps1` (+`Submit-`/`Stop-`; `ops/restart-executor.bat`) | runs local PowerShell **task packages** (concurrency, timeout, capture, restart recovery); task dirs atomically published to `runtime/pending/`; det · **trust-based, NOT a sandbox** | 12/12 + 16/16 hardened 2026-07-28 · D-0056 |
| `exec.watchdog` (M00.1) | `modules/00.1-exec-watchdog/` via `ops/start-watchdog.bat`, `ops/recover-executor.bat [-Force]` | cooperative executor recovery (crash / hang / heartbeating-but-wedged); det; **session-scoped — no boot persistence** | 22/22 · 33/33 hardened 2026-07-28 · D-0013/56 |
| `skill.bootstrap` (M1) | `modules/01-skill-bootstrap/` — `Import-Module lib\SkillContract.psm1`; `Invoke-Skill.ps1 -SkillDir <dir>` | validates the manifest + result envelopes, runs any conforming skill → `…invocation_report/0.1`; field/type/enum checks only | 2026-07-24; reused by every Module |
| `ref.echo` (M1) | `modules/01-skill-bootstrap/skills/ref.echo/Invoke-RefEcho.ps1 -Message <s> -Repeat <n>` | skill-channel health check + the canonical contract example; det | 2026-07-24 via executor |
| `fs.observer` (M2) | `modules/02-fs-observer/Invoke-FsObserver.ps1 -Path <dir> -Depth <n> [-Pattern <glob>]` | depth-bounded tree + metadata + name/glob search; det · **ps:true**; in `agent.local` tools.json | 16/16 2026-07-24 |
| `proc.observer` (M3) | `modules/03-proc-observer/Invoke-ProcObserver.ps1 [-NameFilter <glob>] [-VisibleOnly]` | processes + top-level windows (titles, pid/name, bounds, min/max, foreground); det snapshot | 16/16 2026-07-24 |
| `uia.inspector` (M4) | `modules/04-uia-inspector/Invoke-UiaInspector.ps1 [-Hwnd\|-ProcessId\|-Title <glob>] [-Depth]` | read-only UIA control-tree walk; det; **some apps (Unity) expose NO UIA tree** → use #6/#14 | 16/16 2026-07-24 |
| `uia.actor` (M5) | `modules/05-uia-actor/Invoke-UiaActor.ps1 [-Hwnd\|-ProcessId\|-Title] -Action <invoke\|toggle\|select\|expand\|collapse\|setvalue\|focus> [-AutomationId\|-Name\|-ControlType\|-Path] [-Value -DryRun]` | ONE UIA pattern action on one element (no synthetic input); det · **ps:false (SIDE-EFFECTING)**; ambiguous locators → candidate list; no window management; no keyboard text without a ValuePattern | **26/26** 2026-07-24 (live WinForms probe) |
| `capture.screen` (M6) | `modules/06-capture-screen/Invoke-CaptureScreen.ps1 [-Target <monitor\|window\|app\|region>] [-Monitor -Hwnd\|-ProcessId\|-Title\|-App] [-X -Y -Width -Height -Format]` | monitor / window / app main window / rect → PNG (JPG q90) + `sha256`; det pixel copy · **ps:true**. **GOTCHA:** copies **screen pixels** — an occluded window captures what covers it, a minimized one → `window_minimized`; it never raises/activates/moves windows and uses no synthetic input; no post-processing (→#15); Per-Monitor-V2 DPI set once per process | **39/39** `m6-smoke-001` 2026-07-24 |
| `model.gateway` (M7) | `modules/07-model-gateway/Invoke-ModelGateway.ps1 [-Model <id>\|-Tier <tiny\|weak\|mid\|strong>] -Prompt <s> [-System -MaxTokens -Temperature -Seed -GpuLayers -Context -LoadTimeoutSec -EvictWarm]` | **the single entry point to local text LLMs** (llama.cpp `llama-server`); mixed · **ps:false** (port + most of VRAM) · **prod**; no streaming | base **42/42** + warm **23/23**, 0 orphans, 2026-07-28 · D-0016/44/55/57/62 |
| `classify.batch` (M8) | `modules/08-classify-batch/Invoke-ClassifyBatch.ps1 -InputsJson '{mode,tier\|model,labels\|fields,items\|items_path,confidence_threshold}'` | batch categorize/label/extract; one #7 call per item (default `weak`); mixed · **ps:false** · **prod**; **index only — no file moving** (→#28) | **33/33** `m8-test-001` 2026-07-24 · D-0017 |
| `review.processor` (M9) | `modules/09-review-processor/Invoke-ReviewProcessor.ps1 [-QueuePath -MaxItems -FlaggedBy -Tier\|-Model -EscalateThreshold -DryRun]` | drains `review_queue.jsonl` with a stronger model (default `mid`; `strong` = the resident 9B); resolves or escalates in place; **consumer, not a producer** | **34/34** `m9-test-003` 2026-07-24 · D-0018 |
| `audio.ingest` (M10) | `modules/10-audio-ingest/Invoke-AudioIngest.ps1 -InputFile <path> [-Format <wav\|mp3\|flac\|opus\|ogg\|m4a>] [-SampleRate -Channels -SampleFormat -Bitrate] [-Loudness <none\|peak\|ebu>]` | ffmpeg normalize+convert one file; **defaults = whisper-ready 16 kHz mono s16 WAV**; det · **ps:true**; audio only (`-vn`) | **43/43** `m10-test-001` 2026-07-24 · D-0019 |
| `speech.stt` (M11) | `modules/11-speech-stt/Invoke-SpeechStt.ps1 -InputFile <path> [-Normalize <auto\|always\|never>] [-Language -Translate -NoGpu -Model]` | whisper.cpp timestamped transcription (normalizes via #10); mixed · **ps:false** (CUDA) · **prod**; base.en ≈ **0.07 rtf**; **English-only** | **27/27** `m11-test-001` + live smoke 2026-07-24 · D-0020 |
| `speech.tts` (M12) | `modules/12-speech-tts/Invoke-SpeechTts.ps1 -Text <s> [-Speaker -Language -Instruct -Seed -Format -Model]` | Qwen3-TTS CustomVoice → 24 kHz mono PCM16 WAV; **Ryan/Aiden** + zh/ja/ko; mixed · **ps:false** (CUDA) · **prod**; ~30–40 s cold load | **25/25** `m12-test-001` 2026-07-24 · D-0021 |
| `voice.live` (M13) | `modules/13-voice-live/Invoke-VoiceLive.ps1 -InputFile <audio> [-Respond -Speak -ReadbackTranscript -Tier -Speaker -Language -Format]` | one voice turn #11 → #7 → #12 → `reply.wav`; **ps:false** · orchestrator/non-producer; **file-driven only — no mic/streaming** | **21/21** `m13-test-001` + live smoke 2026-07-24 · D-0022 |
| `ocr.layout` (M14) | `modules/14-ocr-layout/Invoke-OcrLayout.ps1 -InputFile <image> [-Language <bcp47>] [-Engine <model_id>] [-ConfidenceThreshold -Capture]` | text + **per-word pixel boxes + reading-order lines** via Windows.Media.Ocr in a PS 5.1 worker; mixed · **ps:true** · **prod** | **30/30** `m14-test-003` + smoke 2026-07-25 · D-0023 |
| `image.util` (M15) | `modules/15-image-util/Invoke-ImageUtil.ps1 -InputFile <image> -Op <meta\|resize\|crop\|convert\|tile\|similarity>` + per-op flags (`-Width -Height -Mode <fit\|fill\|exact> -MaxDimension`; `-X -Y -CropWidth -CropHeight -Region`; `-Format -Quality`; `-TileCols -TileRows`; `-CompareTo`) | metadata + hashes always plus one op; `resize` reports `scale_x`/`scale_y` for box rescaling; Pillow+numpy on the **system python**; **det**, non-producer · **ps:true**; frame 0 only; **no `models.json` entry** | **48/48** `m15-test-001` 2026-07-25 (JPEG `dpi`/`IFDRational` fix) · D-0024 |
| `detect.objects` (M16) | `modules/16-detect-objects/Invoke-DetectObjects.ps1 -InputFile <image> [-Model\|-Tier <nano\|tiny>] [-ScoreThreshold -NmsThreshold -Classes -MaxDimension -Capture] [-Provider <cpu\|cuda\|dml>]` | ONNX YOLOX boxes with **real per-detection confidence**; **ps:true on the DEFAULT CPU provider — `-Provider cuda\|dml` is NOT parallel-safe** · **prod**; COCO-80 | **38/38** `m16-test-001` + probe 2026-07-25 · D-0025 |
| `image.interpret` (M17) | `modules/17-image-interpret/Invoke-ImageInterpret.ps1 -InputFile <image> [-Prompt] [-Mode <caption\|describe\|vqa\|screen>] [-Model\|-Tier <3b>] [-MaxTokens -Seed -MaxDimension -Capture -GpuLayers -Port]` | local VLM caption/describe/VQA/screen via `llama-server` multimodal HTTP; **ps:false** (port+GPU, one at a time) · **prod**; ~111 tok/s; **no boxes** (→#16) | **48/48** `m17-test-001/002` 2026-07-25 · D-0026 |
| `logic.escalator` (M19) | `modules\19-logic-escalator\Invoke-LogicEscalator.ps1` | tier ladder via #7 with **deterministic ground-truth gates**; `batch:true` · non-producer; **calibrated 78.6 % acc / 0.20 false-approval / −89 % cost — NOT ~95 %** | **24/24 mock + 28/28 `-Live`** `m19-test-001` 2026-07-25 · D-0030 |
| `doc.io` (M20) | `modules/20-doc-io/Invoke-DocIo.ps1 -Op <read\|write\|edit\|append> -Path <file>` + op flags (`-StartLine -EndLine -MaxBytes`; `-Content -Overwrite -CreateDirs -Eol <lf\|crlf>`; `-OldString -NewString -ReplaceAll -ExpectCount`; `-EnsureNewline -Create`) + `[-Encoding -ExpectSha256 -Lease]` | the UTF-8 **text-document** read/write/exact-edit/append primitive; **det**, non-producer · **ps:false** (arbitrary caller paths); no move/copy/mkdir (→#28) | **106/106 `-Live`** (88 base + 18 lease) 2026-07-28 · D-0031/56 |
| `agent.local` (M21) | `modules/21-agent-local/Invoke-AgentLocal.ps1 -Goal <s> [-WorkingDir -MaxSteps <8> -DryRun -Route] [-Profile <frugal\|floor\|max>] [-AutoRamp[:$false]\|-NoAutoRamp] [-AllowLegacy27B] [-DecisionTiers -GenTier -Seed -MaxTokens -ToolsPath]` | bounded ReAct loop (#19 decide → #7 args → child skill → observe); **the registry IS the capability surface — NO arbitrary-shell tool**; **ps:false** · non-producer | **102/102** + AutoRamp **122/122** + live floor-check PASS 2026-07-28 · D-0032/41/43/46/59–62 |
| `gen.audio` (M22) | `modules/22-gen-audio/Invoke-GenAudio.ps1 -Kind <tone\|chord\|noise\|sweep\|silence> [-Frequency\|-Note\|-Frequencies\|-Notes] [-Waveform <sine\|square\|triangle\|sawtooth>] [-Color <white\|pink\|brown\|blue\|violet\|velvet>] [-Seed -FreqStart -FreqEnd -Duration -SampleRate -Channels -Amplitude -FadeInMs -FadeOutMs -Format]` | ffmpeg-lavfi synthetic signals (**no model**): beeps, chords, pitches, noise, fixtures; det (seeded → byte-reproducible) · **ps:true**; **no neural TTA/SFX**, no music (→#24) | **43/43** `m22-test-001` 2026-07-25 · D-0033 |
| `gen.image` (M23) | `modules/23-gen-image/Invoke-GenImage.ps1 -Prompt <text> [-NegativePrompt -Width -Height -Steps -Guidance -Seed] [-Scheduler <dpm++\|euler\|euler_a\|ddim>] [-Format <png\|jpg\|webp>] [-Model\|-Tier]` | SD 1.5 text-to-image (diffusers, speech venv); **ps:false** (CUDA) · **prod**; ~2–3 s @512², **~2.6 GB VRAM**; **`safety_checker` DISABLED** | **32/32 `-Live`** `m23-test-005` 2026-07-25 · D-0034 |
| `gen.music` (M24) | `modules/24-gen-music/Invoke-GenMusic.ps1 -Prompt <text> [-Duration <1..30>] [-Guidance <0..15>] [-Temperature -TopK -TopP -Seed -Normalize -Format -Model\|-Tier]` | MusicGen **instrumental** clip → 32 kHz mono PCM16 WAV; **ps:false** (CUDA) · **prod**; **~2.4 GB VRAM**; Small only, **1..30 s** | **42/42 `-Live`** `m24-test-002` 2026-07-26 · D-0035 |
| `gen.video` (M25) | `modules/25-gen-video/Invoke-GenVideo.ps1 -Prompt <text> [-NegativePrompt -NumFrames -Width -Height -Steps -Guidance -Fps -Seed -Offload] [-Format <mp4\|gif>] [-Model\|-Tier]` | AnimateDiff-Lightning 4-step on SD 1.5 → short **silent** MP4/GIF; **ps:false** (CUDA) · **prod**; **~4.75 GB VRAM**; ~2 s clips | **46/46 `-Live`** `m25-test-002` 2026-07-26 · D-0036 |
| `route.tools` (M27) | `modules/27-route-tools/Invoke-RouteTools.ps1` | request + `tools.json` → #7 at **MID** + a **deterministic catalog gate** → the minimal validated tool-id subset; non-executing, injection-resistant. `strong` was HARD-refused (`strong_tier_forbidden`, empty 27B output); **since D-0043 it SOFT-warns and proceeds** — the catalog gate makes a garbage selection safe (consumer falls back to the full set) | **33/33** off-machine 2026-07-28 · D-0040, D-0043 |
| `fs.manage` (M28) | `modules/28-fs-manage/Invoke-FsManage.ps1` | copy/move/mkdir with **smart path resolution** — known folders via `[Environment]::GetFolderPath` (finds a **OneDrive-redirected Desktop**), `~`, `%ENV%`; overwrite-guarded; det | 21/21 + **25/25** `m29-verify-001` + REAL e2e `m29-after-003` 2026-07-26 · D-0042 |
| `res.lease` (M29) | `modules/29-resource-lease/Invoke-ResLease.ps1 <acquire\|release\|renew\|status\|list>` | filesystem lease/lock with TTL; atomic `CreateNew` reservation, race-safe stale reclaim, `lease_id`, **timezone-safe expiry**; det · **ps:true** | **38/38** + **41/41 `-Live`** `m29-reslease-ship-003` `36d7e0be` 2026-07-27 · D-0053 |
| `orchestrate.fanout` (M30) | `modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action <plan\|report\|status\|handoff\|list>` (+ `FANOUT_PROTOCOL.md`) | scaffolding for N parallel worker Cowork sessions on #29 — one action per invocation; det · **ps:true**; ops → `FANOUT_ORCHESTRATOR_HANDOFF.md` | **51/51** cloud (`2ffe162e`) + **71/71 `-Live`** `2afd5de` 2026-07-28 · D-0054/58 |

### 2.2 Extended contracts & gotchas

**#0 `exec.bootstrap`.** Emits `control/heartbeat.json` (health `degraded`, `poll_error_streak`,
`stuck_finalize_count`, `oldest_stuck_finalize_age_seconds`) + `control/last-exit.json`. **Hardening (D-0056):** on
timeout/cancel it reaps the **whole process tree** incl. a detached `llama-server` (per-PID descendants → root →
orphan-name sweep) **before** the finalize move; a blocked `running→done` move is DEFERRED (`degraded`) rather than
starving pending-claim; file-sharing violations self-heal. Canonical dir `modules/00-bootstrap-executor/`; the old
`proteus_repo/tools/trusted-bootstrap-executor/` is stopped, pending removal from the game repo.

**#00.1 `exec.watchdog`.** Session-scoped and user-launched: no boot/OS persistence, does not survive
logout/reboot, does not self-revive. **(Re)start `ops/start-watchdog.bat` before any unattended multi-worker run.**
A `taskkill /F`/power loss reads as a crash and is recovered; an authorized `stop_requested`/`signal` exit makes it
stand down.

**#7 `model.gateway` — warm server (Governor Phase 2, DONE, D-0057).** The persistent `llama-server` is launched
**DETACHED via `Win32_Process.Create` so it OUTLIVES the executor Job** — the fix for the D-0055/D-0056 executor
wedge. Reuse-on-same-model, evict-on-model-change, `-EvictWarm` for a clean stop; warm reuse `load_ms` **1** vs
**1196** cold. The per-call **`gpu` `res.lease`** keeps **≤1 server on the GPU**.
**GOTCHA (never reintroduce):** a task that **blocks while holding** a persistent server both fails on timeout and
orphans the server → the executor livelocks on the finalize move. Launch detached and **return**.
**`no_think` hook (D-0044):** a model entry with `"no_think": true` makes the gateway append ` /no_think` to the
system message; without it Qwen3.5 models leave reasoning ON and emit **EMPTY content at `finish=length`**.

**#9 `review.processor` — OPEN caveats.** Escalation is a **status transition, not a frontier call** (the human /
#31 drains `escalated`). The in-place queue write re-reads immediately before an atomic replace but is **NOT a full
concurrency protocol** — a single background drainer is assumed. **A thinking-style `strong` model may exhaust
`max_tokens` before emitting the JSON verdict → the item is safely escalated.** **No compaction/archival of resolved
items yet (OPEN).**

**#14 `ocr.layout`.** **Windows.Media.Ocr only** in the MVP (Tesseract declared, not wired). An image over
`MaxImageDimension` (**10000 px**) returns `image_too_large` → downscale with #15. **`ocr_worker.ps1` MUST stay
ASCII-only** — Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI, not UTF-8.

**#19 `logic.escalator` — known defect (OPEN).** As a *judge* over a weak tier's answer the ladder **anchors** on
that answer — the measured reason `agent.local` now decides at a **mid-only floor** (D-0043). A
lower-tier-valid-over-higher-tier-empty fallback is **not built**. Detail: `modules\19-logic-escalator\CALIBRATION.md`.

**#20 `doc.io` — safety + lease.** **Atomic** temp+rename writes (no torn files, no leftover `.docio-*.tmp`);
optional `-ExpectSha256` optimistic-concurrency precondition (`precondition_failed`); recoverable `before.<ext>`
pre-image; **EOL preservation** (a CRLF file stays CRLF); UTF-8 default with UTF-16 BOM detect/preserve; binary (NUL)
files refused. **`-Lease` (D-0056)** is opt-in: acquires the `doc:<relpath>` lease around the read-modify-write,
releases by `lease_id`, returns `doc_lease_unavailable` when contended, degrades gracefully when off / absent.

**#21 `agent.local` — current defaults (newest state).** `DecisionTiers=[mid]`, the **mid-only floor** (D-0043: the
`[tiny,weak,mid]` ladder actively DEGRADED decisions — 3.8x slower AND wrong); `MaxSteps=8`; `-Profile` presets
`frugal={[tiny,weak,mid],mid,6,512}` / `floor={[mid],mid,8,768}` (default) / `max={[mid],strong,10,2048}` — explicit
params always beat a profile. **`-AutoRamp` is DEFAULT-ON since D-0062**: monotonic model-affine epochs M0→M1→S0; a
contract-less goal closes at M0 via the D-0046 deterministic terminator once ≥1 required side-effecting tool
succeeds; `-NoAutoRamp` / `-AutoRamp:$false` reproduce the strict floor byte-for-byte. `-AllowLegacy27B` is the
opt-in **deadline-gated** X0/27B one-shot recovery rung (D-0060).
**tools.json (curated 10):** `doc.io` · `fs.observer` · `capture.screen` · `ocr.layout` · `detect.objects` ·
`image.interpret` · `speech.stt` · `audio.ingest` · `gen.image` · `gen.music`; `fs.manage` #28 is wired with
`resolve_paths:false` (path args passed verbatim). `-Route` pre-selects a subset via #27 (D-0041). **Guardrails:** a
hard `max_steps` budget (exhausting → `stopped` + `needs_frontier`); `-DryRun` plan preview; the closed tool
registry; child review writes go to an in-artifact `child_review.jsonl`, leaving the canonical `review_queue.jsonl`
and the ten-producer set untouched. **KNOWN OPEN (D-0032):** the tiny/weak/mid models **under-use the `finish`
action** — the budget is the backstop; better termination remains the #1 follow-on.

**#29 `res.lease` — conventional resources + order.** `gpu` (one model run at a time) → `git` (commit lock) →
`doc:<path>` (doc ownership). **Always acquire in gpu → git → doc order; release by `lease_id`.** Wired consumers
(trio complete): `gpu` → #7 and `git` → `dev.ship` (both D-0055); `doc:<path>` → #20 `-Lease` (D-0056). A UTC-7
stale-detection bug was caught live and fixed. **OPEN:** auto-renew; live monitoring; a fair scheduler.

**#30 `orchestrate.fanout` — boundary + scheduling.** `plan` computes `dispatch_now` as a trial of `MaxParallel`
**clamped to one GPU worker**, flags gpu-serialization + doc-ownership conflicts, emits each worker's ordered
gpu→git→doc `res.lease` acquire/release commands + a worker prompt + one check-in prompt, and runs an optional
read-only `res.lease list` preflight; `handoff` emits a `lifeorch.verification.packet/0.1` + next-iteration prompts.
**HARD BOUNDARY: it never spawns or drives an AI session — the human is the courier** (D-0051/D-0052).
**packet validation (D-0058):** emitted `run_module` items must carry `inputs` MATCHING the target skill's op
contract (fo-1/fo-4 passed `{task,files}` where `frontier.bridge pack` needs `{prompt,files}`).

### 2.3 Built but NOT yet given a registry entry
Shipped, but no full entry above — **absence here is not "not built"** (status/detail: `MODULE_ROADMAP.md`).
Test counts across this doc are as-of-registration; the authoritative per-suite table is `CURRENT_STATE.md ->
Current tests`.
- **`image.index` (M18)** `modules/18-image-index/` — fuses #15 (always) + optional #14/#16/#17
  (`-Ocr`/`-Detect`/`-Interpret`/`-All`, `-Capture`); children run **sequentially** (VLM VRAM/port contention);
  non-producer; ps:false; confidence = **min** stochastic stage. 41/41 · D-0027.
- **`agent.coding` (M26)** WORK_ORDER only — **DEFERRED, NOT built**: no safe code-execution substrate on this box
  (`m26-probe-001`: WSL launcher but no distro; Windows Sandbox absent + needs elevation; no Docker) · D-0037.
- **`frontier.bridge` (M31)** `modules/31-frontier-bridge/` — deterministic **LOCAL-ONLY, NO-NETWORK** context
  packager (`pack` + read-return with answer-markers/`pack_id`/validator). **It never contacts, scrapes or drives
  any external AI UI.** 65/65 at build (+ hardened return-capture `b17a945`) · D-0052/55/57.
- **Widgets** `widgets/01-local-agent-console` (Plan/Run + `-AutoRamp` toggle, 91/91 `-Live`), `02-module-launcher`,
  `03-verification-console` (audit loop; teardown sweeps orphan detached `llama-server`; 173/173 cloud mock + live STA SelfTests) · D-0041/57/58/64/65.
  **`dev.ship`** holds the `git` lease around index-check + add + commit; 39/39 · D-0055.

---

## 3. Hardware profile (measured 2026-07-24 — DESKTOP-PF5FFMF)
- **CPU:** Intel Core i9-9900KF — 8 c / 16 t @ 3.6 GHz. **RAM:** 64 GB (63.9 total; ~38 free at measure).
- **GPU:** **NVIDIA GeForce RTX 2080 Ti, 11 GB VRAM** (11264 MiB), driver **591.74**, compute cap **7.5**, CUDA
  present. Driver max CUDA **13.1**; CUDA **13.2** toolkit installed. (Two DisplayLink USB "adapters" are **not**
  compute GPUs.) **Practical budget ≈ 9.9 GB free** after OS/desktop — the cap that makes the 27B impractical (D-0061).
- **OS:** Windows 10 Pro 19045 (x64). **Drives (fixed):** C: 893 GB (**~67 GB / 7.5 % free — CONSTRAINED**);
  E: "Game Drive" 858 GB (~534 GB free); **F: "Storage space" 3.72 TB (~1.78 TB free)** — large-data home. (No D:.)

## 4. Local model runtimes (verified on this machine)
**llama.cpp — TWO BUILDS, side by side:**
- **b8661 (b7ad48ebd), CUDA — the DEFAULT engine for every tier except the 9B.** Source build
  `F:\Qwen3.5-27B\llama.cpp\build\bin\`; **portable copy**
  `F:\…\LifeOrchestrator-Refresh_Large_Data\_engines\llama.cpp\bin\` (shared by #7 + #17; relocated 2026-07-25 out
  of `_pending-model-storage` — D-0028). Runs standalone but **needs a system CUDA runtime**.
- **b10092, CUDA 12.4, SELF-CONTAINED** (bundles `cudart64_12`/`cublas64_12`/`cublasLt64_12`) at
  `_engines\llama.cpp-b10092\bin\`. **Only the strong-tier 9B pins `engine_path` to it** (a per-model override the
  gateway already supported) → zero global blast radius; cu12.4 chosen for guaranteed compat with driver 591.74.
  Qwen2.5-3B (mid) also loads on b10092 (backward-compat verified).
- **BOTH builds must remain staged.** Do NOT consolidate onto a single engine without re-verifying EVERY tier
  plus the VLM (#17) — the b10092 universal-engine probe across all 5 fixtures is the gated unit for that
  (`FANOUT_ORCHESTRATOR_HANDOFF.md` §4, GPU menu (d)); the VLM is the gating fixture.
- **Why the split:** Qwen3.5-9B is a hybrid attention-SSM arch that **b8661 CANNOT load** (`missing tensor
  blk.32.ssm_conv1d.weight`). The dense 27B loads fine on b8661.
- **GOTCHA:** this build's `llama-cli` is **interactive-only** (rejects `-no-cnv`) — **use `llama-server` for
  scripting.** Clean per-token logprobs are confirmed on **both** builds (D-0060).
- **Multimodal (verified `m17-probe-001/002`):** `llama-server --help` exposes `-mm/--mmproj`, `--mmproj-offload`,
  `--image-min/max-tokens` (full mtmd support); with `--mmproj <projector.gguf>` it accepts OpenAI-style `image_url`
  (base64 data URI) content on `/v1/chat/completions`. Wired by #17 with the Qwen2.5-VL-3B GGUF.

**whisper.cpp** — CUDA + CPU builds with `whisper-cli.exe`/`whisper-server.exe` under
`F:\Local_TTS_Large_Data\external\whisper.cpp_{cuda,cpu_backup_2026_04_17}\build\bin\Release\`. Both load headless
(`m11-probe-001`; the CUDA build initializes the RTX 2080 Ti). Flags confirmed: `-oj`/`-ojf` (full JSON incl.
per-token `p`), `-osrt`/`-otxt`, `-of <base>`, `-np`, `-l <lang>`, `-ng`, `-t`, `-bs`/`-bo`. `whisper-cli` accepts
flac/mp3/ogg/wav; #11 still normalizes to 16 kHz mono s16 WAV via `audio.ingest` for determinism. The `llama-cli`
interactive gotcha does **not** apply here. Wired by #11, 2026-07-24.

**Speech Python venv** — `F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe`
(Python 3.12.10; torch **2.11.0+cu128**, torchaudio, transformers **4.57.3**, accelerate, safetensors, soundfile
0.13.1, librosa 0.11, onnxruntime, **`qwen_tts`**, **diffusers 0.35.2**, torchvision 0.26).
`qwen_tts.Qwen3TTSModel.generate_custom_voice(...)` loads bf16 + `sdpa` (flash-attn absent) → `(List[np.ndarray],
sr=24000)`. **This is the venv every GPU generator runs under** (`engine_env`): #12, #23, #24, #25. The diffusers
install (2026-07-25) added only diffusers + importlib_metadata + zipp — torch/transformers/`qwen_tts` unchanged;
MusicGen needed **no** install. Verified `m12-probe-001/002`, `m23-probe-002`.

**System Python** 3.12.10 (`…\AppData\Local\Programs\Python\Python312`) — torch 2.2.1 (**CPU-only**),
**onnxruntime-gpu 1.17.1** + onnxruntime-directml 1.17.1 (providers: Tensorrt/CUDA/CPU), torchvision 0.17.1,
**Pillow 10.2.0 + numpy 1.26.4 + cv2 4.9.0**. Wired by #15 and #16 (its worker requests **`CPUExecutionProvider`**
by default — deterministic + parallel-safe, no GPU binding; `m16-probe-001` reproduced the cloud YOLOX-Nano
detections byte-for-byte). **GPU work must use the speech venv, not this interpreter.**

**Ollama / LM Studio: NOT installed.** git / winget / .NET SDK 9 / node: present.

## 5. Installed local models (inventory — DO NOT re-download; portable copies on F:)
Per-owning-module homes under `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\<NN>-<module>\` (relocated
2026-07-25, D-0028; the `_pending-model-storage\` staging area + its `MIGRATION.md` are deleted — the source
originals are recorded in **D-0028**). `file/dir` is relative to `…_Large_Data\`; **exact absolute paths, sha256 and
engine settings live in `models.json`.** `wired` = runnable by `model.gateway` today.

| model_id | type | file/dir (under …_Large_Data\) | size | engine | wired |
|---|---|---|---|---|---|
| `llm.weak.qwen2p5-0p5b` | llm | `07-model-gateway\llm\Qwen2.5-0.5B-Instruct-Q4_K_M\…gguf` | 0.38 GB | llama-server b8661 | **yes** — tier `tiny` |
| `llm.weak.qwen2p5-1p5b` | llm | `07-model-gateway\llm\Qwen2.5-1.5B-Instruct-Q4_K_M\…gguf` | 0.94 GB | llama-server b8661 | **yes** — tier `weak`, gateway default |
| `llm.weak.qwen2p5-3b` | llm | `07-model-gateway\llm\Qwen2.5-3B-Instruct-IQ4_XS\…gguf` | 1.66 GB | llama-server b8661 | **yes** — tier `mid`, the decision floor |
| `llm.strong.qwen3p5-9b` | llm | `07-model-gateway\llm\Qwen3.5-9B-Q5_K_M\Qwen_Qwen3.5-9B-Q5_K_M.gguf` | **7.11 GB** (7,111,487,520 B; sha `a686d88e…`) | llama-server **b10092** (`engine_path` pin) | **yes** — tier `strong` |
| `llm.strong.qwen3p5-9b-q4` | llm | `07-model-gateway\llm\Qwen3.5-9B-Q4_K_M\Qwen_Qwen3.5-9B-Q4_K_M.gguf` | 6.17 GB (6,169,341,984 B; sha `d784ce9e…`; ~6.9 GB VRAM at load) | llama-server **b10092** | no — kept for a **one-flip rollback** |
| `llm.strong.qwen3p5-27b` | llm | `07-model-gateway\llm\Qwen3.5-27B-Q4_K_M\…gguf` | 16.3 GB | llama-server b8661 | retained via `-Model` / `-AllowLegacy27B`; **no longer the tier** |
| `stt.whisper.base-en` | stt | `11-speech-stt\stt\whisper-ggml-base.en\ggml-base.en.bin` | 0.14 GB | whisper.cpp | via `speech.stt` #11 |
| `tts.weak.qwen3-0p6b` | tts | `12-speech-tts\Qwen3-TTS-12Hz-0.6B-CustomVoice\` (+ bundled `speech_tokenizer\`) | 2.38 GB | transformers | via `speech.tts` #12 (default) |
| `tts.strong.qwen3-1p7b` | tts | `12-speech-tts\Qwen3-TTS-12Hz-1.7B-CustomVoice\` (+ bundled `speech_tokenizer\`) | 4.31 GB | transformers | via `speech.tts` #12 |
| `embedding.qwen3-0p6b` | embedding | `23-artifact-search\embedding\Qwen3-Embedding-0.6B\` | 1.12 GB | transformers | no — pre-provisioned for the unbuilt artifact-search module |
| `detect.yolox.nano` | detector | `16-detect-objects\detector\yolox-nano\yolox_nano.onnx` | 3.66 MB | onnxruntime | via `detect.objects` #16 (default) |
| `detect.yolox.tiny` | detector | `16-detect-objects\detector\yolox-tiny\yolox_tiny.onnx` | 20.2 MB | onnxruntime | via `detect.objects` #16 (`-Tier tiny`) |
| `vlm.qwen2p5-vl-3b` | vlm | `17-image-interpret\vlm\Qwen2.5-VL-3B-Instruct-GGUF\{…Q4_K_M.gguf, mmproj-…f16.gguf}` | 1.80 + 1.25 GB | llama-server (mmproj) | via `image.interpret` #17 (default) |
| `image.sd15` | image-gen | `23-gen-image\stable-diffusion-v1-5\` (diffusers fp16 folder) | 2.13 GB | diffusers | via `gen.image` #23 (default) |
| `music.musicgen-small` | music-gen | `24-gen-music\musicgen-small\` (transformers folder, safetensors) | 2.37 GB | transformers | via `gen.music` #24 (default) |
| `video.animatediff-lightning` | video-gen | `25-gen-video\animatediff-lightning\` (motion adapter) + base `23-gen-image\stable-diffusion-v1-5\` | 0.91 GB (+SD1.5) | diffusers | via `gen.video` #25 (default) |

- **Tiers (`models.json`):** LLM `tiny`=0.5B, `weak`=1.5B (gateway default), `mid`=3B (the decision floor),
  `strong`=**Qwen3.5-9B Q5_K_M**; detector `nano` (default) / `tiny`; vlm `3b`; image-gen `sd15`; music-gen `small`.
- **Licenses:** detectors are COCO-80 **YOLOX ONNX (Apache-2.0)**; the VLM is **Qwen2.5-VL-3B-Instruct GGUF Q4_K_M +
  mmproj-f16 (Apache-2.0)**; the 9B GGUFs are **bartowski** quants.
- The standalone `tts.tokenizer.qwen3-12hz` entry was **removed 2026-07-25** — byte-identical to each voice's
  bundled `speech_tokenizer\`, which the voices actually load (D-0028). Detector / vlm / image-gen / music-gen /
  video-gen entries are read by their own skills and are deliberately **decoupled from the gateway `wired` gate**
  (`wired:false` is correct for them).

## 6. Strong LLM tier — current state (D-0044 → D-0061 → D-0062)
- **Tier now:** `tiers.llm.strong` = **`llm.strong.qwen3p5-9b` (Qwen3.5-9B Q5_K_M, bartowski)** — fully GPU-resident
  **~7.11 GB**, `gpu_layers=99`, `context=8192`, `no_think:true`, `engine_path` pinned to **b10092**. Live S0
  calibration **6/6 @ 2048 tok**, non-empty, `finish=stop`. Q4→Q5 = a fidelity upgrade with real KV headroom (on
  11 GB the binding budget is **KV-cache/context, not weight-fit**).
- **Rollback:** the Q4_K_M entry is retained as **`llm.strong.qwen3p5-9b-q4` (`wired:false`)**; Q4 measured ~6.9 GB,
  ngl 99, ~4.3 GB headroom, GPU-bound **~68 tok/s**.
- **`no_think` REQUIRED:** without the gateway's ` /no_think` hook the 9B leaves reasoning ON and emits **EMPTY
  content at `finish=length`**. **TOKEN-BUDGET GOTCHA (documented, NOT a regression):** the 32-token
  latency-calibration harness returns EMPTY on **BOTH Q4 and Q5**; the 9B needs **≥ ~1024 tokens** to emit a
  decision — hence S0 uses **2048**.
- **The 27B is DEMOTED but reachable** (`-Model` / `agent.local -AllowLegacy27B`, deadline-gated). **Validated
  impractical (D-0061): NO Qwen3.5-27B quant fits GPU-bound on the 11 GB card** (~9.9 GB free — IQ2_XXS 9.61 GB
  collapses quality; IQ3_XXS 12.8 / Q2_K 12.1 / Q3_K_M 14.8 GB are over); the incumbent Q4 decides correctly but at
  **2.1 tok/s** partial offload (~88 s warm / ~170 s cold). Probe:
  `modules/07-model-gateway/runtime/x0quant/probe-table.md`; confirmed independently by the couriered frontier report
  (`core-docs/research/2026-07-28-frontier-local-model-selection.md`) — the 9B's hybrid arch keeps KV ~32 KiB/token
  vs a dense 14B's ~160. The 27B is a **generation/verification/routing rung, NOT an escalator decision-classifier
  rung** (escalating the DECISION to it re-broke with empty output, `m31-p1-max-001`) — hence `-Profile max` = mid
  decisions + strong generation.
- **Consumers of `-Tier strong`:** the governor's max `gen_tier`, `review.processor` #9, `agent.local`'s S0 epoch.
- **OPEN / deferred:** Q6_K (7.96 GB) is the documented alternative quant; an optional **specialist pool**
  (Gemma-4-12B code, Ministral-3-14B math, Gemma-4-E4B backup) behind a one-active-GPU-model + warm-RAM-pool + router
  is **designed, not built** (D-0063). The frontier report's **audio/image/video model leads are still outstanding
  (TBD — request from Nicholas)**.

**Legacy 27B operating notes (moved from REVIEW_QUEUE, D-0066):** `gpu_layers` TUNED 28 -> **32** (Module 9
sweep `m9-tune27b-001`, 2026-07-24: {20,28,36} all loaded; throughput 1.43 / 1.67 / 1.93 tok/s; 32 leaves
headroom for desktop VRAM). Cold first load ~90 s (16 GB from F:), warm ~7–9 s — a cold load approaches the
gateway's 120 s default `LoadTimeoutSec` (which bounds load AND the request at ~2 tok/s), so pass
`-LoadTimeoutSec ~300` for ANY 27B run. Reachable only via `-Model` / `-AllowLegacy27B` (deadline-gated).

**Engine CUDA-runtime dependency (open):** the portable `_engines\llama.cpp\bin\` (b8661, 72 MB) copy runs
today but links a CUDA runtime installed OUTSIDE `F:\Qwen3.5-27B`. Confirm the runtime's home before that
folder is torn down; if it lived only there, restage the CUDA DLLs too. (b10092 is self-contained.)

## 7. Large-data storage (F:)
- **Root:** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` — home for all module data > ~50 MB (D-0015).
  Holds the shared `_engines\` (`llama.cpp\` = b8661, `llama.cpp-b10092\`) and per-owning-module homes
  `07-model-gateway\`, `11-speech-stt\`, `12-speech-tts\`, `16-detect-objects\`, `17-image-interpret\`,
  `23-artifact-search\` (embedding, pre-provisioned), `23-gen-image\`, `24-gen-music\`, `25-gen-video\`, plus
  `README.md` + two `.lnk` shortcuts. `_pending-model-storage\` was **emptied and deleted 2026-07-25** (D-0028).
- **RULE:** the C: repo **never** stores model weights or engines; skills reference them by absolute F: paths in
  `models.json`. C: is at ~7.5 % free — do not stage large data there.

## 8. Planned / not yet present (do not assume these exist)
- **C++ toolchain for native modules** — **verify CMake/MSVC before the first C++ module**; register when confirmed.
- **Tesseract as a wired OCR engine** — binary present, not wired (§1).
- **Warm multi-model pool + router** — designed only (D-0063).
- **A safe code-execution substrate** (WSL distro / Windows Sandbox / container / vetted restricted runspace) —
  absent; blocks `agent.coding` #26 (D-0037).
- **Standalone VAD model** — not staged (`voice.live` #13 uses whisper segments).
