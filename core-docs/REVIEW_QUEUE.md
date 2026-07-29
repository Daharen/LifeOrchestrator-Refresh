# REVIEW_QUEUE

Owns the **flagging workflow** that lets cheap/weak producers defer hard cases to stronger reviewers. Doc form is this
file; machine form is `review_queue.jsonl` (one JSON object per line), created when the first item is flagged. Weak
local models and deterministic tools **append**; a stronger local model (`review.processor` #9) drains it slowly in
the background; frontier models see only the distilled item.
**Loop today: ten producers -> local drainer #9 -> frontier for the residue.** (D-0007)

## What gets flagged
Low-confidence classifications (below the skill's threshold); contradictory outputs (two producers disagree);
suspected malformed data / failed transformations; uncategorized or ambiguous artifacts and entities; possible
duplicates; statements explicitly needing stronger-model review; any item exceeding a configured
confidence/uncertainty threshold.

## Record schema (`review_queue.jsonl`, one object per line)
```json
{
  "schema": "lifeorch.review.item/0.1",
  "id": "rq-000001",
  "created_at_utc": "2026-07-24T02:15:00.0000000Z",
  "flagged_by": "classify.batch",            // producing skill_id
  "reason": "low_confidence",                 // low_confidence | contradiction | malformed | uncategorized | duplicate | needs_strong_review | failed_transform
  "confidence": 0.41,                          // producer's confidence, if any
  "source_ref": "artifact://.../file.txt#L10-L14",  // pointer, NOT the whole collection
  "weak_result": { },                          // what the weak producer decided
  "requested": "adjudicate_category",          // the specific decision/correction wanted
  "status": "open",                            // open | in_review | resolved | escalated
  "resolution": null,                          // filled by the reviewer: {by, decision, at_utc, note}
  "escalated_to": null                         // e.g. "frontier" when a stronger local model defers up
}
```

## What a reviewer (or frontier model) receives — and nothing more
1. The unresolved item.
2. The **relevant source fragment** (via `source_ref`), not the whole collection.
3. The weak producer's result (`weak_result`).
4. The reason it was flagged.
5. The specific correction/adjudication requested.

This keeps escalation cheap: reviewers adjudicate single items, they do not redo whole batches. (D-0007)

## Conventions
- **Append-only** producers; only a reviewer sets `resolution`/`status`. Never rewrite history in place — add a new
  record or update status + resolution.
- One item = one decision. If a source needs many decisions, emit many records with distinct `source_ref`s.
- Resolved items may be compacted to an archive later; keep the live file small.
- Queue path defaults to the repo root (`review_queue.jsonl`); every producer takes `-ReviewQueuePath`.
- Composed/orchestrating skills **redirect** children's review writes (in-artifact `child_review.jsonl` or a
  suppressed file) and **do not re-flag** — see Non-producers.
- Producers flag at **page/item level, never per-unit** and bound the count (`-MaxReview*`), so one noisy input
  cannot fill the queue.
- Every producer confidence is a **documented heuristic, not calibrated correctness** (see Design flags).

## Producers (ten: 7/8/11/12/14/16/17/23/24/25)

Module 9 selects by `flagged_by` and handles every producer/verb **by construction**. `-ConfidenceThreshold` default
**0.5** unless noted; `source_ref` = `artifact://<invDir>/<file>`. Reason shorthand: `low_conf`, `uncat`, `fail_tx`,
`needs_strong` = the schema's `low_confidence`, `uncategorized`, `failed_transform`, `needs_strong_review`.

| producer | # | reason -> `requested` | notes / threshold | D |
|---|---|---|---|---|
| `model.gateway` | 7 | low_conf -> `review_generation_quality` | completeness conf: empty output 0.1, truncated (`finish_reason=length`) 0.4. `exchange.json`. First producer. | 0016 |
| `classify.batch` | 8 | uncat (not in label set) / malformed (empty/unparseable) / fail_tx (gateway/item error, or extract yielded no fields) / low_conf -> `adjudicate_category` (classify/multilabel) or `verify_extraction` (extract) | one item **per batch item**; completeness + in-set/JSON-validity heuristic; `classified.json#<item_id>`; `weak_result` = `{mode, model, label\|labels\|extracted, finish_reason, text_preview}`. **Suppresses the child gateway's queue writes** (child `-ReviewQueuePath` -> in-artifact `_gateway_review_suppressed.jsonl`) so each item is flagged **once**, never mis-attributed. | 0017 |
| `speech.stt` | 11 | low_conf -> `verify_transcription`; uncat -> `verify_no_speech` | **per segment**; conf = mean whisper token probability `p` over content tokens (`[_…_]` specials excluded), `-SegmentConfidenceThreshold` 0.5; bounded by `-MaxReviewSegments` **25** (worst first; truncation -> `warnings` + `result.review.truncated`). **Zero segments** from audio >= `-MinSpeechSeconds` (1.0) -> one `verify_no_speech` (`confidence:null`). | 0020 |
| `speech.tts` | 12 | fail_tx (conf <= 0.15) / low_conf -> `verify_synthesis` | synthesis-completeness heuristic (audio + duration vs text length): 0.1 empty/near-silent, 0.3 far-too-short, 0.5 short, 0.9 plausible. `tts.json`. A **failure guard, not an audio-quality judge**. | 0021 |
| `ocr.layout` | 14 | low_conf -> `verify_ocr`; uncat -> `verify_no_text` | `Windows.Media.Ocr` gives **no per-word confidence** -> legibility heuristic (fraction of clean/plausible words -> `[0.1,0.9]`); worst lines bounded by `-MaxReviewLines`; text-free non-empty image -> `verify_no_text`. | 0023 |
| `detect.objects` | 16 | low_conf -> `verify_detections`; uncat -> `verify_no_objects` | **real signal**: per-detection `score` (objectness x class prob), `confidence.overall` = best score; worst bounded by `-MaxReviewDetections`; zero detections above `-ScoreThreshold` -> `verify_no_objects`. | 0025 |
| `image.interpret` | 17 | fail_tx (empty) / needs_strong (**refusal**) / low_conf (truncated/other) -> `verify_interpretation` | local VLM (`llama-server` + mmproj): stop 0.7, `length` 0.4, refusal 0.3, empty 0.1. `interpret.json`. A stronger model judges whether a refusal was warranted. | 0026 |
| `gen.image` | 23 | fail_tx (blank/near-uniform) / low_conf (low-detail) | first **generator** producer (`gen.audio` #22 is deterministic, NOT a producer). SD 1.5 / `diffusers`; pixel-std bands 0.1/0.3/0.5/0.9 at <=2 / <8 / <15 / >=15. | 0034 |
| `gen.music` | 24 | fail_tx (silent) / low_conf (low-level) | MusicGen Small; RMS bands 0.1/0.3/0.5/0.9 at <=0.005 / <0.02 / <0.05 / >=0.05, plus a **duration-shortfall guard** capping a truncated clip. | 0035 |
| `gen.video` | 25 | fail_tx (blank/failed) / low_conf (low-detail/static) | AnimateDiff-Lightning (SD 1.5 + 4-step motion adapter); frame pixel-std as #23 **plus a motion guard** on mean inter-frame diff: <=0.5 -> 0.3 `static_no_motion`, <1.5 -> 0.5 `low_motion`. | 0036 |

Generators #23-25 share `requested:"verify_generation"`, `source_ref` = `gen.json`, `fail_tx` at conf <= 0.15, and
`weak_result` = model + prompt preview + the measured signals; only a stronger model / the frontier can say whether
the output *matches the prompt*.

**Wiring verified at ship, all PASS:** `m9-test-003` 34/34, `m11-test-001`, `m12-test-001`, `m14-test-003`,
`m16-test-001` 38/38, `m17-test-001/002` 48/48, `m24-test-002`, `m25-test-002`; #7/#8 forced-trigger gates (#8: the
gateway wrote nothing canonical), #23-25 mock gates + canonical queue live before==after.

## Consumer / drainer: `review.processor` (#9)

Selects **OPEN** items per pass (`-MaxItems` default **25**; optional `-FlaggedBy`/`-Reason`/`-Ids` filters) and
adjudicates each **single** item with a stronger local model via `model.gateway` — default `-Tier mid` (Qwen2.5-3B);
`strong` is now **Qwen3.5-9B Q5_K_M** (D-0044/D-0062; was the 27B — see Design flags).

- **The reviewer sees only the distilled item** plus a **bounded fragment resolved from `source_ref`** —
  `classify.batch`: `classified.json#<id>` -> the closed label set + that one item (recovering the label set
  `weak_result` lacks); `model.gateway`: `exchange.json` -> a bounded request/output preview. **Never the whole batch**
  (D-0007).
- Parses `{verdict, answer, confidence, escalate, rationale}`; computes a **structural reviewer confidence** (valid
  JSON + in-set corrected answer + generation completeness; a `finish_reason=length` truncation caps it <= 0.4), then
  **resolves** (`status:"resolved"` + `resolution = {by:"review.processor:<model>", decision, at_utc, note, verdict,
  reviewer_confidence, model_self_confidence, …}`) or **escalates** (`status:"escalated"`,
  `escalated_to:"frontier"`) when that confidence is `< -EscalateThreshold` (default 0.5), the model asks to escalate,
  or its output is unparseable. **Escalation is a status transition, NOT a frontier call**; the frontier (this Cowork
  agent, or a future `route.tasks` #24) drains `escalated` items separately, seeing only the distilled item.
- **Write model.** Updates the live queue **in place** — re-reads the file immediately before an atomic replace,
  rewrites only the lines it adjudicated (still `open`), and passes every other line (producer appends during the run,
  resolved items, **malformed lines**) through **verbatim**; the flagging fields
  (`schema,id,created_at_utc,flagged_by,reason,confidence,source_ref,weak_result,requested`) are never mutated. It
  **also** appends an immutable `lifeorch.review.resolution/0.1` record per adjudication to **`review_resolved.jsonl`**
  (beside the queue), so the live queue stays small **and** history survives. `-DryRun` writes neither.
- Suppresses its child gateway's review writes so draining never grows the queue. `determinism:"mixed"`,
  `batch:true`, `parallel_safe:false`. `-LoadTimeoutSec` passthrough (the gateway's 120s default bounds BOTH model load
  and the completion request). See D-0018.

## Non-producers (the set stays at ten; each verified live, canonical queue before==after)
- `voice.live` #13 — orchestrator (stt+gateway+tts); points each child's `review_queue_path` at an in-artifact
  **`child_review.jsonl`** (surfaced as `child_review_count`); `-ReviewQueuePath` routes children to a canonical queue
  instead. **The composed-skill pattern: redirect, do not re-flag.** (D-0022)
- `image.index` #18 — redirects its perception children's flags to `child_review.jsonl`. (D-0027)
- `logic.escalator` #19 — suppresses the child gateway's writes to `_gateway_review_suppressed.jsonl`; surfaces
  `needs_frontier` per task in its result (a **status signal, not a queue write**). (D-0030)
- `agent.local` #21 (incl. `-Route`) — redirects every child's review writes; `needs_frontier` on a low-confidence
  decision or exhausted `max_steps` is a status signal, not a queue write (`m21-live-001` 1->1). (D-0032/D-0041)
- `route.tools` #27 — redirects its child gateway's writes (`m28-live-001` + `m28-e2e-001` 1->1). (D-0040)
- Deterministic tools (`confidence:null`, empty `model_provenance`, never write the queue): `doc.io` #20 (D-0031),
  `gen.audio` #22 (D-0033), `fs.manage` #28 (`m29-after-003`, D-0042), `res.lease` #29 (D-0053),
  `orchestrate.fanout` #30 (D-0054), `frontier.bridge` #31 (D-0052/D-0055); also the perception children
  `image.util` / `capture.screen` / `audio.ingest`.
- Widgets — Local Agent Console Plan/Run redirects child flags (D-0041); Module Launcher redirects run outputs under
  `runtime/artifacts/<id>/` (D-0049); Verification Console audits verification packets, not the queue (D-0051).

## Design flags to revisit (open)
- **No producer confidence is calibrated correctness.** `model.gateway` measures generation *completeness*
  (`finish_reason`/empty), not whether the answer is right (D-0016); `classify.batch` = completeness + in-set/JSON
  validity (D-0017); `speech.stt` = mean whisper token probability — a real acoustic signal, but not P(transcript
  correct) (D-0020). Replace with logprob / `avg_logprob`+`no_speech_prob` / self-consistency signals when a consumer
  (Module 9) needs a real one.
- **`classify.batch` throughput = one gateway call per item x per-call model load** (D-0002/D-0016). Fine for
  small/unattended batches; when it dominates, wire it to the warm/persistent **detached `llama-server`** the gateway
  gained in Governor Phase 2 (reuse-on-same-model / evict-on-change, D-0057), or add an intra-batch single-prompt mode.
- **Strong-tier verdict parseability.** In `m9-test-003` the 27B (thinking-style) spent its budget on reasoning and hit
  `max_tokens` before emitting the `{verdict,…}` JSON, so `review.processor` correctly **escalated** it (unparseable ->
  frontier). Follow-on: tune the strong-tier prompt / raise `max_tokens` / add a no-reasoning directive. The gateway
  `no_think` hook + the 9B strong tier likely address it — **not re-verified for `review.processor`** (D-0044/D-0062).
- **Legacy-27B operating guidance and the b8661 CUDA-runtime dependency** moved to
  `TOOL_MODEL_REGISTRY.md` (D-0066); the TTS-tokenizer flag is resolved (D-0028; shared-copy collapse stays a
  deferred follow-on in `MODULE_ROADMAP.md`).
