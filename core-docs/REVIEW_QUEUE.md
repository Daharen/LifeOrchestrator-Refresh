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

## Design flags to revisit (not yet actioned — for a future session/frontier pass)
- **classify.batch confidence is also a heuristic (completeness + in-set/JSON validity), not calibrated
  correctness.** It is richer than the gateway's completeness signal but still not a probability the label is right.
  Replace with a calibrated / logprob / self-consistency signal alongside the gateway's (D-0017).
- **classify.batch throughput = one gateway call per item × per-call model load** (no warm worker — D-0002/D-0016).
  Fine for small/unattended batches; when it dominates, add a warm/persistent gateway worker or an intra-batch
  single-prompt mode. This module is the concrete pressure to do so.
- **model.gateway confidence is a heuristic, not semantic.** It measures generation *completeness*
  (finish_reason/empty), NOT whether the answer is *correct*. Replace with a logprob- or self-consistency-based
  **semantic** confidence when Module 9 (`review.processor`) needs a real signal. (D-0016.)
- **TTS tokenizer triplication (~650 MB × 3).** `Qwen3-TTS-Tokenizer-12Hz` is duplicated inside both
  CustomVoice models' `speech_tokenizer\`. De-duplicate when Module 12 (`speech.tts`) is built.
- **Staged llama.cpp engine depends on a system CUDA runtime.** The portable `_engines\llama.cpp\bin\` copy
  (72 MB) runs today but links to a CUDA runtime installed outside `F:\Qwen3.5-27B`. Confirm the runtime's
  home before that folder is torn down; if it lived only there, restage the CUDA DLLs too.
- **27B GGUF gpu_layers is a guess (28).** ~16 GB Q4 > 11 GB VRAM → partial offload; the value was not
  load-tested this session. Tune when the strong tier is first exercised (Module 9).
