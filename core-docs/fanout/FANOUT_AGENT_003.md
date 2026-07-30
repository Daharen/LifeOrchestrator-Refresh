# FANOUT_AGENT_003 -- Coding lane: MEDIA-decompose (NEW module modules/32-media-decompose)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i16 (plan id `fo-16-f125365c`)
- **Lane:** CODING (CPU; a DISTINCT module/area from slot 002)
- **Worker id / label:** `MEDIA-decompose` -- NEW module `media.decompose` (Phase C video position 19)
- **Module/area (exclusive):** `modules/32-media-decompose/` ONLY (a brand-new folder)
- **GPU:** false
- **Docs:** `[]`

## Mission

Build the FIRST module of the Phase C canonical spine (`MODULE_ROADMAP.md` -> Build priority Phase C: video
19-22; `ARCHITECTURE_MAP.md` position 19 = `media.decompose`). It is the VIDEO analog of the deterministic
perception primitives `audio.ingest` #10 and `image.util` #15: given a video, decompose it into constituent
parts via ffmpeg/ffprobe. Folder = `modules/32-media-decompose` (32 = next-free folder number; architectural
position 19). CPU-only, DETERMINISTIC, `parallel_safe:true` (no CUDA / model / port), reproducible.

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/b6ef5fb3-88a7-4dab-8bad-058bc1d90e03/workers/worker-MEDIA-decompose.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (create ONLY `modules/32-media-decompose/` + its tests/fixtures):**
- `skill.json` (id `media.decompose`; `parallel_safe:true`) + `Invoke-MediaDecompose.ps1` emitting the
  `lifeorch.skill.result/0.1` envelope + `README.md` + `tests/` (dual-mode cloud + `-Live`) + a deterministic
  fixture generator.
- **MVP ops (meta ALWAYS; rest are opt-in flags -- keep the surface small):**
  * **meta (ALWAYS):** `ffprobe -show_format -show_streams -of json` -> structured JSON (container, duration,
    per-stream codec/resolution/fps/pix_fmt/bitrate/channels/sample-rate, stream counts).
  * **-Audio:** extract the primary audio to WAV by **composing `audio.ingest` #10** (default whisper-ready
    16 kHz mono s16; `-AudioFormat`/`-Loudness` passthrough); `no_audio_stream` cleanly if none.
  * **-Keyframes N:** up to N frames as PNGs -- prefer scene-change frames (`select='gt(scene,thr)'`) else
    evenly spaced; capped, deterministic order; write a frame-index+timestamp sidecar.
  * **-Scenes:** scene-change detection (ffmpeg scene score) -> JSON `{index,start,end,score}` list;
    deterministic threshold param.
- **Reuse patterns:** resolve **ffprobe as the SIBLING of the resolved ffmpeg** (the Python `Scripts\ffprobe.exe`
  shim gotcha -- CRITICAL); drain child stdout+stderr async / to files (pipe-deadlock); coerce meta
  JSON-serializable; artifacts per `SKILL_CONTRACT.md`; mind the pwsh 7.4.6 array gotchas (List[object] +
  `.ToArray()`; guard `@()` on maybe-null). **Deterministic fixture:** generate a tiny video via ffmpeg lavfi
  (`testsrc2` + sine) so tests reproduce in BOTH cloud and on-device.

**SCOPE OUT (explicit follow-ons -- name in README + report, do NOT build):** subtitle-stream extraction to
.srt/.vtt; clip segmentation; proxy transcode; batch/directory; VAD segmentation; contact-sheet/thumbnail
grid; ANY model/VLM frame interpretation (that is `video.interpret`, architectural #22, later). Touch no
other module/widget/core-doc; not a review-queue producer.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (ffmpeg/ffprobe 8.1 paths + the
  ffprobe-shim gotcha + pwsh 7.4.6 array gotchas + child-pipe-deadlock + JSON-serializable-meta) +
  `SKILL_CONTRACT.md` (manifest + envelope + artifact rules) + `modules/10-audio-ingest` and
  `modules/15-image-util` as reference modules; obey `SKILL_CONTRACT.md`.
- Acquire the **git** lease for the commit; release on exit. No GPU lease (no GPU/model).
- Gate off-machine FIRST: ffmpeg/ffprobe are portable -- run the REAL skill in the cloud against the generated
  lavfi fixture (install ffmpeg in the cloud if absent) and assert meta/audio/keyframes/scenes; dual-mode
  `tests/Invoke-MediaDecomposeTests.ps1` (cloud real + on-device `-Live`). AST-parse the shipped `.ps1`.
  `dev.ship` the named `modules/32` files (FAIL-CLOSED; named files; trailers). Do ONE unit; `docs:[]` -- the
  orchestrator owns the `MODULE_ROADMAP`/`CURRENT_STATE`/`TOOL_MODEL_REGISTRY` updates; just report what you built.
- Report: `-Action report -PlanId fo-16-f125365c -WorkerId MEDIA-decompose -State done -Summary "<one line>"`
  (`progress`/`blocked -Needs`/`failed` as needed). Negative results are first-class (D-0061 ethos).

## Verification

Cloud + on-device `-Live` test counts; the produced artifacts (`meta.json`, the WAV, keyframe PNGs + sidecar,
`scenes.json`) with paths; confirm `parallel_safe:true` (no CUDA/port/model bind); a **Verification Console
`run_module`** item (decompose the fixture -> meta + one op). Report counts + artifact paths + the named
follow-ons. This STARTS the Phase C video block.

## Report-back record (ORCHESTRATOR fills from `plans/fo-16-f125365c/reports/` before archiving)

_(pending)_
