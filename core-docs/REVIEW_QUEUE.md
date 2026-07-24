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
  "schema": "proteus.review.item/0.1",
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
