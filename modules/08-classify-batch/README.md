# classify.batch — Batch Classification & Sorting

Weak-local-model **batch** categorize / label / extract over a list of text items. `classify.batch` is the
first real consumer of **`model.gateway`** (Module 7): for each item it builds a mode-specific prompt, calls
the gateway (default tier `weak` = Qwen2.5-1.5B), parses the completion into a structured result, computes a
classification confidence, groups the items, and routes the uncertain ones to the review queue.

Skill contract: `lifeorch.skill.result/0.1`. `determinism: mixed` · `batch: true` · `parallel_safe: false`
(it drives the gateway, which binds a port + most of VRAM). Emits **only** the JSON envelope to stdout;
diagnostics to stderr.

## Modes

- **`classify`** — assign **exactly one** label from a closed `-Labels` set. This is also "routing / sorting":
  each item is routed into one bucket.
- **`multilabel`** — assign **zero or more** labels from the set (model answers with a comma list, or `NONE`).
- **`extract`** — pull a set of named `-Fields` from each item into a JSON object.

## Declaring the schema

`labels` (classify/multilabel) and `fields` (extract) are **config, not code** — swap the taxonomy without
touching the script. Each entry is either a bare string or `{name, description?}`; a description is fed to the
model to steer it:

```json
"labels": ["animal", "vehicle", "food"]
"labels": [{ "name": "bug", "description": "a defect report" }, { "name": "feature", "description": "a request" }]
"fields": [{ "name": "amount", "description": "the total in USD" }, "vendor"]
```

## Invocation

Direct:

```powershell
pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '{
  "mode":"classify", "tier":"weak",
  "labels":["animal","vehicle","food"],
  "items":[
    {"id":"a","text":"a golden retriever puppy"},
    {"id":"b","text":"a red pickup truck"},
    {"id":"c","text":"a bowl of ramen"}
  ]}'
```

Items can also come from a file (large batches): `-ItemsPath items.jsonl` (one `{id?,text}` or string per
line) or a `.json` array. Through the Module 1 wrapper:
`Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'`. Through the executor: submit a task package whose
`task.ps1` runs the entrypoint (see the module tests).

Key inputs: `mode` · `items`/`items_path` · `labels`/`fields` · `tier` (`tiny|weak|mid|strong`, default
`weak`) or `model` (explicit id) · `max_tokens` (mode defaults 24/48/220) · `temperature` (default 0.0) ·
`seed` (default 42) · `max_input_chars` (default 2000) · `confidence_threshold` (default 0.5) ·
`review_queue_path` · `registry` · `gateway_path` · `pwsh_path`. See `skill.json` for the full list.

## Result

`result` = `{ mode, model, selected_from, labels?|fields?, count, ok_count, flagged_count, error_count,
confidence_threshold, items[], groups{label -> [ids]}, review_queue_path, review_count }`. Each `items[]` =
`{ id, input_preview, status, label?|labels?|extracted?, confidence, finish_reason, parsed, in_set,
prompt_tokens, completion_tokens, raw_preview, flagged, flag_reason, review_id, error }`.

Artifacts (`runtime/artifacts/<invocation_id>/`): `classified.json` (full payload), `classified.md` (human
table + groups), `result.json` (envelope), `stderr.txt`, and `gateway/` (each per-item gateway invocation's
own artifacts).

## Confidence semantics (read this)

The per-item `confidence` is a **documented completeness + validity heuristic**, NOT a calibrated correctness
score. It combines whether the answer parsed to an **in-set** label / valid JSON, and the gateway's
generation completeness (a truncated `finish_reason=length` caps the item at ≤0.4):

- **classify:** exact in-set match + clean stop → **0.8**; matched by substring/fuzzy → **0.6**; answer not in
  the label set → **0.2** (flagged `uncategorized`, `label=null`); empty → **0.1**.
- **multilabel:** all returned labels in-set → **0.75**; clean `NONE` → **0.7**; some out-of-set dropped →
  **0.5**; nothing parseable → **0.15**.
- **extract:** valid JSON, all fields present → **0.75**; some fields missing → **0.5**; unparseable JSON →
  **0.3**; empty → **0.1**.

The **envelope-level** `confidence` is the mean of the per-item confidences. `model_provenance[]` carries one
**aggregate** entry for the model used (summed tokens, call count, total runtime); per-item token counts and
`finish_reason` live in `result.items[]`.

Items whose confidence is `< confidence_threshold` (default 0.5) are appended to the review queue as one
`lifeorch.review.item/0.1` per item (`flagged_by: "classify.batch"`), with a per-item `source_ref` into
`classified.json`. A stronger local model (Module 9, `review.processor`) drains these later.

### Why the gateway's own review writes are suppressed

`model.gateway` **also** appends to the review queue when *its* generation-completeness confidence is `< 0.5`.
To keep the canonical queue clean and correctly attributed, `classify.batch` points the gateway's
`-ReviewQueuePath` at a discardable in-artifact file (`_gateway_review_suppressed.jsonl`, path reported in the
envelope's `diagnostics.gateway_reviews_suppressed_to`) and is itself the **sole author** of the batch's
review items using its classification confidence.

## Throughput caveat

The MVP makes **one gateway call per item**, and the gateway (Module 7, D-0002/D-0016) starts and stops an
isolated `llama-server` per call — so batch throughput is bounded by per-call model load. That is fine for
small/moderate unattended batches; removing it (a warm/persistent gateway worker, or an intra-batch
single-prompt mode) is a documented follow-on, not built here. Use a small tier (`tiny`/`weak`) for speed.

## Non-goals

No physical file moving into per-label folders (sorting = the grouping/index only), no warm worker, no
open-vocabulary/taxonomy learning, no auto model selection (that's routing, Module 24), no
semantic/calibrated confidence yet, and it never talks to `llama-server` directly — it always goes through
`model.gateway`.

## Tests

`tests/Invoke-ClassifyBatchTests.ps1` (run through the executor — the live checks need the GPU + staged
models): manifest, five setup error paths, a live `classify` batch on tier `tiny`, an explicit-model resolve,
a live `extract`, review routing + gateway-suppression, the Module 1 wrapper, and a no-orphaned-`llama-server`
check. `tests/mock-gateway.ps1` is a Linux-only stand-in used to validate the parse/confidence/group logic
off-GPU; it is not used on the device.
