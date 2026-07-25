# REVIEW_QUEUE

Owns the **flagging workflow** that lets cheap/weak producers defer hard cases to stronger reviewers.
Human/doc form is this file; the machine form is `review_queue.jsonl` (one JSON object per line),
created when the first item is flagged. Weak local models and deterministic tools **append**; a stronger
local model (Module 9) drains it slowly in the background; frontier models see only the distilled item.

## What gets flagged
- Low-confidence classifications (below the skill's threshold).
- Contradictory outputs (two producers disagree).
- Suspected malformed data / failed transformations.
- Uncategorized or ambiguous artifacts and entities.
- Possible duplicates.
- Statements explicitly needing stronger-model review.
- Any item exceeding a configured confidence/uncertainty threshold.

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

This keeps escalation cheap: reviewers adjudicate single items, they do not redo whole batches.

## Conventions
- **Append-only** producers; only a reviewer sets `resolution`/`status`. Never rewrite history in place —
  add a new record or update status + resolution.
- One item = one decision. If a source needs many decisions, emit many records with distinct `source_ref`s.
- Resolved items may be compacted to an archive later; keep the live file small.

## First producer wired (Module 7)
`model.gateway` is the **first skill that appends to `review_queue.jsonl`**. It flags a run when its
generation-completeness `confidence` falls below **0.5** (empty output → 0.1; truncated at `max_tokens`
`finish_reason=length` → 0.4), with `reason:"low_confidence"`, `flagged_by:"model.gateway"`,
`requested:"review_generation_quality"`, and a `source_ref` to that invocation's `exchange.json`. The queue
path defaults to the repo root (`review_queue.jsonl`) or `-ReviewQueuePath`. Verified end-to-end by the
Module 7 tests (a forced-truncation run produced a valid `lifeorch.review.item/0.1`).

## Second producer wired (Module 8)
`classify.batch` is the **second skill that appends to `review_queue.jsonl`** (and the first that flags real
*content* decisions, not just generation completeness). It flags a per-**item** batch result when its
**classification confidence** (a completeness+validity heuristic — see D-0017) falls below `-ConfidenceThreshold`
(default 0.5), one `lifeorch.review.item/0.1` per item, `flagged_by:"classify.batch"`, with:
- `reason` ∈ `uncategorized` (answer not in the label set), `malformed` (empty/unparseable model output),
  `failed_transform` (a gateway/item error, or extract yielded no fields), or `low_confidence` (below threshold
  otherwise);
- `source_ref` = `artifact://<invDir>/classified.json#<item_id>` (points at the single item, not the batch);
- `weak_result` = the item's `{mode, model, label|labels|extracted, finish_reason, text_preview}`;
- `requested` = `adjudicate_category` (classify/multilabel) or `verify_extraction` (extract).

Crucially, `classify.batch` **suppresses `model.gateway`'s own review-queue writes** (it points the child gateway's
`-ReviewQueuePath` at a discardable in-artifact `_gateway_review_suppressed.jsonl`) so each batch item is flagged
**once**, by `classify.batch`, with a classification-appropriate reason — the canonical queue is never
double-written or mis-attributed. Verified end-to-end by the Module 8 tests (a threshold-0.99 run produced a valid
`classify.batch` item and the gateway wrote nothing to the canonical queue). **Module 9 (`review.processor`) must
therefore handle both `flagged_by` values (`model.gateway`, `classify.batch`).**

## First consumer/drainer wired (Module 9)
`review.processor` is the **first skill that drains** `review_queue.jsonl`. Per pass it selects **OPEN** items
(bounded by `-MaxItems`, default 25; optional `-FlaggedBy`/`-Reason`/`-Ids` filters; both producers handled) and
adjudicates each **single** item with a **stronger** local model (default `-Tier mid`=Qwen2.5-3B; `strong`=27B) via
`model.gateway`. The reviewer receives **only** the distilled item — its `reason`/`requested`/`weak_result` plus a
**bounded fragment resolved from `source_ref`** (for `classify.batch`: `classified.json#<id>` → the closed label set
+ that one item, which recovers the label set `weak_result` lacks; for `model.gateway`: `exchange.json` → a bounded
request/output preview) — **never the whole batch** (keeps escalation cheap). It parses a small JSON verdict
(`{verdict, answer, confidence, escalate, rationale}`), computes a **structural reviewer confidence** (valid JSON +
in-set corrected answer + generation completeness; a `finish_reason=length` truncation caps ≤0.4), then:
- **resolves** the item — sets `status:"resolved"` and fills `resolution = {by:"review.processor:<model>", decision,
  at_utc, note, verdict, reviewer_confidence, model_self_confidence, …}` — when confident; or
- **escalates** — sets `status:"escalated"`, `escalated_to:"frontier"` — when the reviewer confidence is
  `< -EscalateThreshold` (default 0.5), the model asks to escalate, or its output is unparseable. **Escalation is a
  status transition, not a frontier call**; the frontier (this Cowork agent, or a future `route.tasks` #24) drains
  `escalated` items separately, seeing only the distilled item.

**Write model (answers the "append vs update-in-place" question).** Only a reviewer sets `resolution`/`status`. The
skill **updates the live queue in place** — it re-reads the file immediately before an atomic replace, rewrites only
the lines it adjudicated (still `open`) with the same object plus the updated `status`/`resolution`/`escalated_to`,
and passes every other line (producer appends during the run, already-resolved items, and **malformed lines**)
through **verbatim**; the original flagging fields (`schema,id,created_at_utc,flagged_by,reason,confidence,
source_ref,weak_result,requested`) are never mutated. It **also** appends an immutable
`lifeorch.review.resolution/0.1` record per adjudication to `review_resolved.jsonl` (beside the queue). So the live
queue reflects current status (re-runs skip resolved items; the queue stays small) **and** history survives.
`-DryRun` writes neither. Like `classify.batch`, it **suppresses the child gateway's own review writes** (points the
gateway `-ReviewQueuePath` at an in-artifact file) so draining never grows the queue. `determinism:"mixed"`,
`batch:true`, `parallel_safe:false`. Verified end-to-end by the Module 9 tests (34/34; `m9-test-003`). See D-0018.
**The review-queue loop is now closed: producers (7/8) → local drainer (9) → frontier for the residue.**

## Third producer wired (Module 11)
`speech.stt` is the **third skill that appends** to `review_queue.jsonl` (after `model.gateway` and `classify.batch`),
and the first from the audio track. It transcribes audio via whisper.cpp and flags **low-confidence transcription
segments**: a segment whose confidence — the **mean whisper token probability `p`** over its content tokens (whisper
special tokens `[_…_]` excluded) — falls below `-SegmentConfidenceThreshold` (default 0.5) becomes one
`lifeorch.review.item/0.1` with `flagged_by:"speech.stt"`, `reason:"low_confidence"`,
`source_ref:"artifact://<invDir>/transcript.json#seg<index>"`, `weak_result = {model, t0_ms, t1_ms, text, token_count}`,
`requested:"verify_transcription"`. It is **bounded** by `-MaxReviewSegments` (default 25; worst-confidence segments
first; truncation recorded in `warnings` + `result.review.truncated`) so a long, noisy file cannot flood the queue.
A **zero-segment** result from audio of at least `-MinSpeechSeconds` (default 1.0) emits one `reason:"uncategorized"`,
`requested:"verify_no_speech"` item (a silent-STT-failure guard; `confidence:null`). A **text** reviewer (Module 9) can
judge whether a flagged segment reads as coherent speech even without re-listening; genuinely audio-bound cases escalate
to the frontier as usual. Unlike the model consumers, `speech.stt` has **no child gateway** to suppress (whisper is not
the gateway), and its `audio.ingest` child is deterministic and writes nothing to the queue. Module 9 already selects by
`flagged_by` and handles the new producer by construction. Verified end-to-end by the Module 11 tests (a forced 0.999
threshold produced a valid `speech.stt` review item; `m11-test-001`). **Producers are now 7/8/11 → local drainer 9 →
frontier for the residue.** See D-0020.

## Fourth producer wired (Module 12)
`speech.tts` is the **fourth skill that appends** to `review_queue.jsonl` (after `model.gateway`, `classify.batch`,
`speech.stt`), and the second from the audio track. It synthesizes speech via Qwen3-TTS and flags a **failed or
suspiciously-short synthesis**: when its **synthesis-completeness confidence** — a documented heuristic over produced
audio + duration vs. input length (empty/near-silent 0.1, far-too-short-for-the-text 0.3, short 0.5, plausible 0.9) —
falls below `-ConfidenceThreshold` (default 0.5), it appends one `lifeorch.review.item/0.1` with
`flagged_by:"speech.tts"`, `reason` = `failed_transform` (confidence ≤ 0.15) or `low_confidence` otherwise,
`source_ref:"artifact://<invDir>/tts.json"`, `weak_result = {model, speaker, text_preview, duration_s, chars,
confidence_reason}`, `requested:"verify_synthesis"`. It is a **synthesis-failure guard** (empty/garbled/truncated audio),
not an audio-quality judge. Like the deterministic `audio.ingest`, its child (`audio.ingest`, used only for optional
format conversion) writes nothing to the queue, so there is no gateway-style suppression to do. Module 9 selects by
`flagged_by` and handles the new `verify_synthesis` verb by construction. Verified end-to-end by the Module 12 tests (a
forced too-short/failed synthesis produced a valid `speech.tts` item; `m12-test-001`). **Producers are now 7/8/11/12 →
local drainer 9 → frontier for the residue.** See D-0021.

## Composed skills aggregate child flags (Module 13)
`voice.live` (Module 13) is an **orchestrator, not a producer** — it composes `speech.stt` + `model.gateway` +
`speech.tts` and adds no review decision of its own. To keep a transient voice turn from flooding the canonical queue,
it points each child's `review_queue_path` at an in-artifact **`child_review.jsonl`** by default (surfaced in the result
as `child_review_count`); passing `-ReviewQueuePath` routes the children's flags to a canonical queue instead. This is
the general pattern for composed skills: **redirect children's review writes to an aggregate, do not re-flag.** The four
producers above are unchanged. See D-0022. **`image.index` (Module 18) and `logic.escalator` (Module 19) follow this same
orchestrator/non-producer pattern** — #18 redirects its perception children's flags to an in-artifact `child_review.jsonl`;
#19 (the Local Logic Escalator) suppresses the child gateway's review writes to an in-artifact
`_gateway_review_suppressed.jsonl` and surfaces `needs_frontier` per task in its own result (a status signal, NOT a queue
write) — so the canonical `review_queue.jsonl` producer set stays at **seven** (7/8/11/12/14/16/17). See D-0027, D-0030.

## Fifth producer wired (Module 14)
`ocr.layout` is the **fifth skill that appends** to `review_queue.jsonl` (after `model.gateway`, `classify.batch`,
`speech.stt`, `speech.tts`), and the first from the perception track. It OCRs an image via `Windows.Media.Ocr` and flags
a **poorly-legible or text-free** result. Because Windows.Media.Ocr exposes **no** per-word confidence, its confidence is
a documented **legibility heuristic** (the fraction of recognized words that are clean/plausible tokens → `[0.1,0.9]`).
When the **overall** confidence falls below `-ConfidenceThreshold` (default 0.5), it appends **one page-level**
`lifeorch.review.item/0.1` with `flagged_by:"ocr.layout"`, `reason:"low_confidence"`,
`source_ref:"artifact://<invDir>/ocr.json"`, `weak_result = {engine, image, word_count, line_count, reason,
low_confidence_lines, lines:[…worst lines, bounded by -MaxReviewLines]}`, `requested:"verify_ocr"`. A **text-free
non-empty image** instead appends one `reason:"uncategorized"`, `requested:"verify_no_text"` item (a silent-OCR-failure
guard). It is **page-level, not per-line** — the confidence is a coarse page-legibility proxy, not a per-unit signal, and
per-line items would flood the queue. Module 9 selects by `flagged_by` and handles the new `verify_ocr`/`verify_no_text`
verbs by construction. Verified end-to-end by the Module 14 tests (a forced 0.999 threshold produced a valid `ocr.layout`
item; a blank image produced a `verify_no_text` item; `m14-test-003`). **Producers are now 7/8/11/12/14 → local drainer 9
→ frontier for the residue.** See D-0023.

## Sixth producer wired (Module 16)
`detect.objects` is the **sixth skill that appends** to `review_queue.jsonl` (after `model.gateway`, `classify.batch`,
`speech.stt`, `speech.tts`, `ocr.layout`), and the second from the perception track. It detects objects in one image via a
staged ONNX YOLOX detector (onnxruntime) and flags **weak or empty** results. Unlike `ocr.layout`, its confidence is a
**real** signal — each detection carries the model's own `score` (objectness × class probability), and the page-level
`confidence.overall` is the **best** detection's score. When `overall` falls below `-ConfidenceThreshold` (default 0.5), it
appends **one page-level** `lifeorch.review.item/0.1` with `flagged_by:"detect.objects"`, `reason:"low_confidence"`,
`source_ref:"artifact://<invDir>/detect.json"`, `weak_result = {model, image, detection_count, reason, low_confidence_count,
detections:[…worst by score, bounded by -MaxReviewDetections]}`, `requested:"verify_detections"`. A **non-empty image with
zero detections** above `-ScoreThreshold` instead appends one `reason:"uncategorized"`, `requested:"verify_no_objects"` item
(a silent-detection-failure guard). It is **page-level, not per-box** — one item per image so a busy scene cannot flood the
queue. A text reviewer (Module 9) can sanity-check the class list / counts against the requested verb even without the pixels;
genuinely vision-bound cases escalate to the frontier. Its optional children (`image.util` for `-MaxDimension` downscale,
`capture.screen` for `-Capture`) are deterministic / non-producers, so there is no gateway-style suppression to do. Module 9
selects by `flagged_by` and handles the new `verify_detections`/`verify_no_objects` verbs by construction. Verified
end-to-end by the Module 16 tests (a forced 0.999 threshold produced a valid `detect.objects` item; a 0.999 score floor
produced a `verify_no_objects` item; `m16-test-001`, 38/38). **Producers are now 7/8/11/12/14/16 → local drainer 9 →
frontier for the residue.** See D-0025.

## Seventh producer wired (Module 17)
`image.interpret` is the **seventh skill that appends** to `review_queue.jsonl` (after `model.gateway`, `classify.batch`,
`speech.stt`, `speech.tts`, `ocr.layout`, `detect.objects`), and the third from the perception track. It interprets one
image with a local VLM (llama.cpp `llama-server` + mmproj) and flags a **weak, refusing, or empty** interpretation. Its
confidence is a documented **completeness + refusal + non-empty heuristic** (like `model.gateway`/`ocr.layout`, not
calibrated): generation stop → 0.7, truncated (`finish_reason=length`) → 0.4, a detected **refusal** → 0.3, empty output →
0.1. When the envelope `confidence` falls below `-ConfidenceThreshold` (default 0.5), it appends **one page-level**
`lifeorch.review.item/0.1` with `flagged_by:"image.interpret"`, `source_ref:"artifact://<invDir>/interpret.json"`,
`weak_result = {model, mode, image, prompt, finish_reason, confidence_reason, answer_preview}`,
`requested:"verify_interpretation"`, and a **reason mapped from the failure**: `failed_transform` (empty output),
`needs_strong_review` (a refusal — a stronger model / the frontier can judge whether the refusal is warranted), or
`low_confidence` (truncated / otherwise low). It is **page-level, not per-sentence** — one item per interpretation. A text
reviewer (Module 9) can sanity-check the interpretation against the prompt/mode; genuinely vision-bound cases escalate to
the frontier. Its optional children (`image.util` for `-MaxDimension`, `capture.screen` for `-Capture`) are deterministic /
non-producers, so there is no gateway-style suppression to do. Module 9 selects by `flagged_by` and handles the new
`verify_interpretation` verb by construction. Verified end-to-end by the Module 17 tests (forced low-confidence, a refusal
fixture, and an empty fixture each produced the right `image.interpret` item; `m17-test-001/002`, 48/48). **Producers are now
7/8/11/12/14/16/17 → local drainer 9 → frontier for the residue.** See D-0026.

## Design flags to revisit (not yet actioned — for a future session/frontier pass)
- **speech.stt confidence is mean token probability — honest but not calibrated.** A real acoustic signal (richer than
  the gateway's completeness heuristic) but not a probability the transcript is *correct*; replace with a calibrated /
  `avg_logprob`+`no_speech_prob` / self-consistency signal when a consumer needs it (D-0020).
- **classify.batch confidence is also a heuristic (completeness + in-set/JSON validity), not calibrated
  correctness.** It is richer than the gateway's completeness signal but still not a probability the label is right.
  Replace with a calibrated / logprob / self-consistency signal alongside the gateway's (D-0017).
- **classify.batch throughput = one gateway call per item × per-call model load** (no warm worker — D-0002/D-0016).
  Fine for small/unattended batches; when it dominates, add a warm/persistent gateway worker or an intra-batch
  single-prompt mode. This module is the concrete pressure to do so.
- **model.gateway confidence is a heuristic, not semantic.** It measures generation *completeness*
  (finish_reason/empty), NOT whether the answer is *correct*. Replace with a logprob- or self-consistency-based
  **semantic** confidence when Module 9 (`review.processor`) needs a real signal. (D-0016.)
- ~~**TTS tokenizer triplication (~650 MB × 3).**~~ **Resolved 2026-07-25 (D-0028):** the redundant standalone
  `Qwen3-TTS-Tokenizer-12Hz` copy + its declared-only `tts.tokenizer.qwen3-12hz` registry entry were removed
  (byte-identical to each voice's bundled `speech_tokenizer\`, sha256 836B7B35…, which the voices actually load).
  Each voice keeps its own bundled copy (self-contained + portable); collapsing the two remaining per-voice copies
  to one shared copy is a deferred qwen_tts-external-tokenizer-config follow-on.
- **Staged llama.cpp engine depends on a system CUDA runtime.** The portable `_engines\llama.cpp\bin\` copy
  (72 MB) runs today but links to a CUDA runtime installed outside `F:\Qwen3.5-27B`. Confirm the runtime's
  home before that folder is torn down; if it lived only there, restage the CUDA DLLs too.
- **27B GGUF gpu_layers — TUNED 28 → 32 (Module 9, 2026-07-24).** Swept `gpu_layers ∈ {20, 28, 36}` on an idle
  GPU via the gateway (`m9-tune27b-001`): **all three loaded (no OOM)** and generated; throughput rose monotonically
  (1.43 / 1.67 / 1.93 tok/s). Raised the registry default to **32** (`models.json`) — strictly fewer offloaded layers
  than the `36` that fit, so it fits with headroom for the RTX 2080 Ti's desktop-display VRAM. **Cold first load ~90s**
  (16 GB read from F:), warm ~7–9s (OS file cache). Because a cold load approaches the gateway's default 120s
  `LoadTimeoutSec` (which bounds BOTH load and the completion request, and the 27B runs ~2 tok/s), `review.processor`
  now exposes a **`-LoadTimeoutSec` passthrough** — use `~300` for strong-tier runs. Still slow (~2 tok/s): reserve
  `strong` for the hardest items; `mid` (3B, full GPU offload, ~5s load) is the routine default.
- **Strong-tier verdict parseability (new follow-on).** In `m9-test-003` the 27B (a thinking-style model) spent its
  token budget on reasoning and hit `max_tokens` before emitting the `{verdict,…}` JSON, so `review.processor`
  correctly **escalated** it (unparseable → frontier). Follow-on: tune the strong-tier prompt / raise its
  `max_tokens` / add a no-reasoning directive so the 27B returns a parseable verdict and resolves more items locally.
