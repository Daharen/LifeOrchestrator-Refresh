# VIDEO-TIMELINE-i22 -- SHIP STATE (i22, plan `fo-22-d2c492e7`, FANOUT_AGENT_003)

**State: DONE.** NEW module `modules/34-video-timeline` (skill_id `video.timeline` 0.1.0, arch position 21)
shipped at commit **`e8583d1a2473fed720c649539716c5d467ae115f`** (subject: "video.timeline #34 0.1.0:
canonical searchable timeline fuse (Phase C pos 21, i22)"). HEAD verified via NATIVE `git log` +
`git show --stat` (D-0072), NOT the dev.ship field: exactly the 22 new named files, 2665 insertions,
`Co-Authored-By` + `Claude-Session` trailers present. Report filed:
`plans/fo-22-d2c492e7/reports/VIDEO-TIMELINE-i22.20535f5b.json` (state=done).

## Gates (all green, in order)

| gate | result |
|---|---|
| off-machine cloud (pwsh 7.4.6, Linux) | **138/138** (`ALL TESTS PASSED`, exit 0) |
| on-box `-Live` via executor (task `i22-vtl-live-gate`) | **138/138**, exit 0, 32.4 s |
| dev.ship (task `i22-vtl-ship`) | ok: sha **22/22**, AST **2/2**, tests re-run `-Live` pass, committed, git lease acquired (47 ms) + released, **0 llama-server orphans** |
| cross-environment canonical hashes | **ALL 7 fixture hashes EQUAL** cloud vs `-Live` (below) |
| `review_queue.jsonl` | before == after == `e82880321b2c4e76cd40bea26b040a81d5ee9b0a2d5c7a1e2b31e132e45e13bc` (non-producer confirmed) |

Canonical fixture sha256 (identical on both environments):
`fused=7b7e8b3bb95960d6609f15fd9d786f6941732e0faf28d8dc24be80b95ebefd54` ·
`meta-only=abe3c676162f715b89d710b291bbb3c1cadfcee6ee716c573ac7989132c4c4da` ·
`tracks-nosamples=2e1d35f4036ac35843bc6bc674a5dfd673b010aa9d9b95424eac3124fb5befb0` ·
`transcript-only=d2c0db0d691c652a2a40f4a23c724f18c80b1c1133f22be15d32c346f6abca23` ·
`ocr-map=5f17cd3e78f4a0c1a389d817bbb9f321f7a8a49193ced497726ac3fcc4a3d620` ·
`gap-heavy=4d683b1cb7f41255293418a351757e0c5c2cf782a6a209cd495d3c2349d88765` ·
`empty-sections=08fbcf7a59591690d09099633efc3c7e0d2ed4895eef8da8b7576c8fd67c96b4`.

## Shipped files (the exact commit set)

`Invoke-VideoTimeline.ps1` (entrypoint, ~1010 lines) · `skill.json` (contract v0.2, deterministic,
parallel_safe, pwsh>=7.4 only, no models/network) · `README.md` · `SCHEMA_NOTES.md` (**33 numbered digest
interpretations**) · `.gitignore` · `tests/Invoke-VideoTimelineTests.ps1` (138 assertions, dual-mode
real-skill) · 13 committed fixtures under `tests/fixtures/` (`fused`, `fused-scrambled`, `meta-only`,
`tracks-nosamples`, `transcript-only`, `ocr-map`, `ocr-refuse`, `adversarial-scenes`, `gap-heavy`,
`zero-observation`, `unlisted-sample`, `empty-sections`, `tracks-embedded-samples`) ·
`examples/example-invocation.md` · `examples/example-result.json` (captured ON-BOX from the fused run
through the Module 1 wrapper) · `examples/verification-packet.json` (packet `vp-video-timeline-i22`, a
`run_module` item on the full fused fixture + a degradation/refusal `human_action` item).

## Emitted schema (`lifeorch.video_timeline/0.1`)

Top-level keys (ordinal-sorted, canonical): `coverage, events, generator, identity_scope, index,
input_digest, intervals, scenes, schema, source, summary, timestamp_unit`.

- **intervals[] kinds:** `track_presence` (appearance segmentation: contiguous observed spans SPLIT at
  recorded gaps, never merged across one; each with `observation_count` + separated
  `evidence.detection {mean/min/max_detection_score_q, low_confidence_count}` and
  `evidence.association {iou_link_count, centroid_link_count, reacquisition_count,
  weakest_link_quality_q, maximum_gap_ms}` in integer-millionth q units) and `track_gap`
  (first-class: `start_ms, end_ms, elapsed_ms, missed_samples, reacquired_by`).
- **events[] kinds:** `speech {start_ms,end_ms,text}` · `ocr_text {timestamp_ms,text,line_count}` ·
  `detection_sample {timestamp_ms,sample_index,class_counts}` · `scene_cut {timestamp_ms,scene_index}`;
  order = `(time, kind, canonical-content)` -- fully presentation-order-free.
- **coverage** embeds the normalized sample manifest (+ `samples_source`, `span`, `status
  sampled|unknown`, `presence_semantics`) -- "sampled with no detection" vs "not sampled" vs "tracker
  gap" stay distinguishable. **identity_scope** carried verbatim. **NO field named `confidence`**
  anywhere in canonical bytes (grepped by the tests). Canonical discipline: UTF-8 no BOM, one line + one
  LF, ordinal-sorted keys, compact, integer ms, no NaN/Inf, no paths/UUIDs/wall-clock;
  `input_digest` = sha256 of the canonical NORMALIZED inputs (doubles as the envelope `inputs_digest`).

## Degradation-mode behavior table (all tested)

| inputs | behavior | status |
|---|---|---|
| meta only | valid empty timeline; coverage `unknown` | ok |
| tracks, no samples | spans+gaps still split; coverage `unknown` + `presence_semantics downgraded_no_sample_manifest` + explicit warning | partial |
| transcript only | speech events only | ok |
| ocr by `frame_index` + samples | timestamps mapped by exact frame match | ok |
| ocr by `frame_index`, no samples | **REFUSED** (violation; timestamps never invented) | error |
| sections present-but-empty | valid; `samples:[]` -> `status "sampled"`, 0 samples (distinct from unknown) | ok |
| any shape violation | fail-closed; every violation enumerated in `result.violations[{path,why}]`; NO timeline written | error |

19 refusal paths asserted, including: zero-observation track; observation `sample_index` unlisted in /
`timestamp_ms` disagreeing with the sample manifest; unalignable or duplicate-boundary gaps; fractional
ms; non-`ms` `timestamp_unit`; dims mismatch vs media; duplicate track/sample/scene ids.

## Interpretations the orchestrator should reconcile at fold (vs the parallel TRACK-STABLE-i22 emitter)

Full list = `modules/34-video-timeline/SCHEMA_NOTES.md` (33 numbered notes). Highest fold relevance:
(a) tracks file validation floor = `schema` + `tracks` only; `timestamp_unit` must be `ms` IF present;
identity_scope tolerated-absent (carried null) -- the full review file-level field list is the EMITTER's
contract; (b) observation required fields here = `sample_index` + `timestamp_ms`; association
`{kind, iou_q, gap_ms}` consumed, rest tolerated; (c) per-interval evidence is computed from the
segment's OWN observations (not track-level pass-through), reacquisition link counted in the segment it
starts; (d) centroid link quality = 0 q (IoU is 0 by construction when the fallback fired) --
`weakest_link_quality_q` needs no new formula; (e) sample manifest precedence manifest > track-file
`samples` (`coverage.samples_source` records which); (f) `coverage_ms` = sample EXTENT (instants, not
integrated dwell); (g) cross-source checks are FAIL-CLOSED (manifest is authoritative per the review).

## Follow-ons (named, NOT built)

Live composition `#32 -> #16 -> #33(upgraded) -> video.timeline` (+ #11/#14 side feeds) once the reviewed
emitter lands; `video.interpret` (pos 22, model lane); full-text / `artifact.search` #23 integration;
rendering/export (overlay video, HTML/markdown); cross-video/global identity; a `quality_score` ranking
value (versioned formula per the review); **the dense low-res tracking-stream input contract** -- the
review's open decision-gate question (sparse keyframes may lack recoverable identity continuity; the
eventual architecture may need sparse keyframes for semantics + a denser lightweight stream for temporal
identity) -- restated here, unresolved, owned by the #33 refinement track.

## Ops notes

Executor tasks: `i22-vtl-live-gate` (gate+example capture), `i22-vtl-ship` (dev.ship), `i22-vtl-report`
(report); inputs + task scripts under `modules/30-orchestrate-fanout/runtime/i22-vtl/`. Leases: git ONLY,
taken/released INSIDE dev.ship (holder `VIDEO-TIMELINE-i22`, 47 ms wait) -- no gpu lease anywhere, no doc
lease (`docs:[]`, nothing outside `modules/34-video-timeline/` touched). Expected benign residue: git's
CRLF advice warnings on the new LF files (the known mount-side noise class); the module's `runtime/`
artifacts are gitignored.
