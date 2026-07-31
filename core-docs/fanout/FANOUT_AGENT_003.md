# FANOUT_AGENT_003 -- CODING lane: NEW modules/34-video-timeline MVP (i22)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i22 (plan `fo-22-d2c492e7`)
- **Lane:** CODING
- **Worker id / label:** `VIDEO-TIMELINE-i22`
- **Module/area (exclusive):** `modules/34-video-timeline/` (BRAND-NEW; create it) -- nothing else, anywhere
- **GPU:** false
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors)

## Mission

Build the NEW `video.timeline` module (architectural position 21; next-free folder 34): a deterministic,
CPU-only, fixture-driven fuse of per-source artifacts -- media meta + #32 scenes + the reviewed sample
manifest + reviewed-schema tracks + #11 transcript + #14 OCR + #16 detections -- into ONE canonical,
searchable timeline JSON. Governing contract: `core-docs/research/2026-07-30-track-objects-design-review.md`
(the track schema + timeline semantics). A PARALLEL worker is upgrading #33 to EMIT that schema; build
against the DIGEST, not their tree.

## Unit (the full worker prompt)

**READ AND EXECUTE THE FULL EMITTED PROMPT** (it is the complete unit; disk is canonical):
`modules/30-orchestrate-fanout/runtime/artifacts/fc5b10db-bacf-43d4-b226-d052eb09717b/workers/worker-VIDEO-TIMELINE-i22.prompt.md`

Condensed scope (the prompt is authoritative; on any doubt the prompt + the governing review digest win):

- **Skeleton (contract v0.2, exemplars #32/#33):** `Invoke-VideoTimeline.ps1` (+ `-InputsJson`),
  `skill.json` (skill_id `video.timeline`, 0.1.0, determinism "deterministic", `parallel_safe:true`,
  pwsh-only requirements), README, `tests/Invoke-VideoTimelineTests.ps1`, examples + a verification-packet
  `run_module` item.
- **Input = a per-source artifact MANIFEST** (file or inline): media meta REQUIRED; scenes / samples /
  tracks / transcript / ocr / detections OPTIONAL, each validated STRICTLY against its expected shape
  (violations -> fail-closed error envelope enumerating them; unknown fields tolerated, never repaired).
- **Output = ONE canonical `timeline.json`** (`lifeorch.video_timeline/0.1`) + a SEPARATE diagnostics
  envelope. Canonical rules per the review: UTF-8 no BOM, sorted keys, fixed ordering, integer ms, no
  NaN/Inf; no abs paths/UUIDs/wall-clock in canonical bytes; carries schema id + generator version + params
  + `input_digest`. Content: coverage (from the sample manifest; "unknown" when absent, with explicitly
  DOWNGRADED presence semantics); normalized scenes; **intervals[]: per-track APPEARANCE SEGMENTATION --
  contiguous observed spans split at recorded gaps, each with separated detection/association evidence;
  gaps emitted as their own `track_gap` intervals; NEVER merge across a gap (false continuity is
  corrupting)**; events[] (speech / ocr_text / detection_sample / scene_cut) sorted `(start_ms, kind, id)`;
  index (by_class / by_track / by_scene / by_kind, stable refs); summary. `identity_scope` carried verbatim
  (never imply cross-video identity); NO field named "confidence".
- **Honest degradation modes, documented + tested:** meta-only; tracks-without-samples; transcript-only;
  OCR by frame_index only -> map via samples else REFUSE (never invent timestamps).
- **Determinism:** double-run byte-identity; cross-env sha256 hashes EQUAL (cloud vs `-Live`);
  canonical-ordering tests; a full fused fixture + per-degradation fixtures + adversarial fixtures.
- **Scope OUT (name as follow-ons):** live composition of #32/#16/#33/#11/#14 (fixtures ONLY); any
  model/VLM (that is `video.interpret`, position 22); full-text / artifact.search #23; rendering;
  cross-video identity; the dense tracking-stream contract (restate the open question).

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` (Known failures IN FULL) first; obey
  `core-docs/SKILL_CONTRACT.md`.
- No gpu lease anywhere in this unit. Acquire `git` ONLY for the dev.ship commit window; release after.
  `docs:[]`.
- Gate off-machine FIRST (cloud pwsh 7.4.6; target the #32/#33 bar -- a real 40+ assertion suite), THEN
  on-box `-Live` via the executor (`exec-job.sh`; device_bash cannot run Windows pwsh), THEN `dev.ship` the
  NEW named files ONLY (this spec intentionally has NO skill_id -- the module does not exist until you
  create it; trailers; never `git add -A`).
- VERIFY the real HEAD via native `git log` / `git show --stat`, NOT dev.ship's `committed` field (D-0072).
- `review_queue.jsonl` before == after (non-producer). No models, no network, no new deps.
- Report: `-Action report -PlanId fo-22-d2c492e7 -WorkerId VIDEO-TIMELINE-i22 -State done` (or
  blocked/failed with what+why). Negative results are first-class (D-0061): if the full fuse is too large,
  ship the largest coherent contract-valid subset in priority order tracks+samples+scenes > transcript >
  ocr > detection samples > index, and report plainly what remains.

## Verification

Cloud + `-Live` suite counts; EQUAL canonical fixture hashes across environments; dev.ship commit verified
via native git; the emitted schema summary (top-level keys + every interval/event kind); the
degradation-mode behavior table; `SCHEMA_NOTES.md` with every digest interpretation. A Verification Console
`run_module` item on the full fused fixture.

## Report-back record (ORCHESTRATOR fills from `plans/fo-22-d2c492e7/reports/` before archiving)

(pending)
