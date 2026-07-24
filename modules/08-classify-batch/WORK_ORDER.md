# Work Order: Batch Classification & Sorting (`classify.batch`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 8 session, 2026-07-24) · **Roadmap entry:** `MODULE_ROADMAP.md#8`

### Problem being solved
`model.gateway` (Module 7) can run a local LLM once and return a contract-valid envelope, but nothing yet
uses it to do *bulk, unattended* work. Frontier and local agents that want to categorize/label/extract over
a **batch** of inputs would otherwise call the gateway by hand per item, invent their own prompting, parse
free text themselves, compute their own confidence, and hand-manage the review queue. This module closes that
gap: **one skill that takes a batch of text items + a label/field schema, runs the weak local model over each
item through the gateway, and returns per-item labels with a classification confidence** — routing the
uncertain ones to `REVIEW_QUEUE` automatically. It is the **first real consumer of `model.gateway`** and the
early proof that weak local models do useful work on their own.

### Immediate practical use
This week: an agent (or a scheduled job) hands `classify.batch` a set of short texts — file summaries, log
lines, notes, message snippets, filenames — plus a fixed set of categories, and gets back `{id → label,
confidence}` for the whole batch plus a grouped view, with low-confidence items already queued for a stronger
model (Module 9, `review.processor`) to adjudicate later. Selecting *which* strength runs the batch is one
argument (`-Tier weak|tiny|mid|strong`, or an explicit `-Model`), because the gateway owns model resolution.

### Explicit scope (in)
- **Three batch modes over a list of text items**, each item `{id?, text}`:
  - `classify` — assign **exactly one** label from a caller-supplied closed set (this is also "routing/
    sorting": each item is routed to one bucket).
  - `multilabel` — assign **zero or more** labels from the closed set.
  - `extract` — pull a caller-supplied set of **named fields** from each item into a JSON object.
- **Caller-declared schema:** `labels` (for classify/multilabel) and `fields` (for extract), each entry either
  a bare string or `{name, description?}`; the description is fed to the model to steer it. This is *config*,
  not code — swapping the taxonomy needs no code change.
- **Per item: call `model.gateway`** (default `-Tier weak` = Qwen2.5-1.5B) with a mode-specific system prompt,
  low temperature, and a fixed seed; parse the completion into a structured result; compute a
  **classification-appropriate confidence** (documented heuristic — see below); collect the item.
- **Batch result + grouping (the "sorting" half):** every item's structured result, plus a `groups` map
  (`label → [item ids]`) and counts (`ok`/`flagged`/`error`). Sorting = producing the grouping/index.
- **Review-queue routing:** each item whose confidence is below `-ConfidenceThreshold` (default 0.5) is
  appended to `review_queue.jsonl` as one `lifeorch.review.item/0.1`, `flagged_by:"classify.batch"`, with a
  per-item `source_ref` — one review record per uncertain **item** (not one per batch).
- **Provenance + confidence:** envelope `model_provenance[]` carries one aggregate entry for the model used
  (summed tokens, call count, total runtime); envelope `confidence` = mean per-item confidence. Per-item token
  counts / finish_reason / raw text live in `result.items[]`.
- **Artifacts:** `classified.json` (full payload), `classified.md` (human table), plus `result.json` +
  `stderr.txt`, under `runtime/artifacts/<invocation_id>/`. Nested gateway child artifacts under
  `<invocation_id>/gateway/`.

### Non-goals (out — do NOT build)
- **Physically moving/copying files into per-label folders.** Sorting here means producing the grouping/index;
  a side-effecting file mover is a later, separately-scoped skill (it would flip filesystem to write + change
  the safety posture). This module only writes its own artifacts + the review queue.
- **A warm/persistent model server or intra-batch batching into one prompt.** MVP is **one gateway call per
  item** (clean per-item confidence + provenance + review routing). Throughput is bounded by the gateway's
  per-call model load (D-0002 / D-0016 — no warm worker yet). Documented follow-on, not built here.
- **Reimplementing inference / talking to `llama-server` directly.** classify.batch goes **through** the
  gateway; it never binds a port or loads a model itself. (That is the whole point of being the first consumer.)
- **Open-vocabulary / free-form category invention, taxonomy learning, clustering, active learning, few-shot
  example management.** Closed label/field sets supplied by the caller only.
- **Semantic (logprob/self-consistency) confidence.** Heuristic only for the MVP, same doctrine as the gateway
  (build the stochastic version first; harden when it earns it).
- **Auto model/tier selection** ("pick the best model") — that is routing (Module 24). Tier/model is explicit.
- **Adjudicating the review queue.** Draining/resolving flagged items is Module 9 (`review.processor`).

### Dependencies
- Modules: **7 (`model.gateway`** — the child it invokes), **1 (`skill.bootstrap`** — `lib/SkillContract.psm1`
  validators + `Invoke-Skill.ps1` wrapper), **0** (executor, for running/testing). · Tools/models: `pwsh`
  7.4.6; via the gateway, the llama.cpp `llama-server` + a GGUF LLM (default the staged 1.5B). · Contract
  features: `confidence`, `model_provenance`, `determinism:"mixed"`, artifact envelope, review-queue append.

### Skill contract requirements
- `skill_id` `classify.batch` · `name` "Batch Classification & Sorting" · `version` `0.1.0` ·
  `determinism` **`mixed`** (deterministic orchestration/parsing/grouping; stochastic model labels — mirrors
  the gateway) · `parallel_safe` **`false`** (it drives the gateway, which binds a port + most of VRAM;
  concurrent batches would contend the GPU) · `batch` **`true`** · `streaming` `false`.
- `result` shape (object): `{ mode, model, selected_from, labels?|fields?, count, ok_count, flagged_count,
  error_count, confidence_threshold, items[], groups{} , review_queue_path, review_count }` where each
  `items[]` = `{ id, input_preview, status, label?|labels?|extracted?, confidence, finish_reason,
  in_set?/parsed?, prompt_tokens, completion_tokens, raw_preview, flagged, flag_reason?, review_id? }`.
- `confidence` populated (envelope-level = mean per-item). `model_provenance[]` = one aggregate entry.
- Artifact kinds: `json` (`classified.json`), `markdown` (`classified.md`), plus `result.json` + `stderr.txt`.

### Inputs and outputs
- **Inputs** (named params + `-InputsJson`): `mode` (string, default `classify`: `classify|multilabel|
  extract`); `items` (array — `[{id?,text}]` or `[string]`, via `-InputsJson`) **or** `items_path` (string —
  a `.jsonl` of `{id?,text}`/strings, or a `.json` array); `labels` (array — for classify/multilabel);
  `fields` (array — for extract); `tier` (string, default `weak`); `model` (string, optional — overrides
  tier); `max_tokens` (int, optional — per-item cap; mode default 24/48/220); `temperature` (number, default
  0.0); `seed` (int, default 42); `max_input_chars` (int, default 2000); `confidence_threshold` (number,
  default 0.5); `registry` (string, optional — passed to the gateway); `gateway_path` (string, optional —
  path to `Invoke-ModelGateway.ps1`; default resolved from the repo); `pwsh_path` (string, optional — pwsh to
  spawn the gateway child; default the dotnet-tool pwsh); `review_queue_path` (string, optional — where THIS
  skill writes flagged items; default repo-root `review_queue.jsonl`). Standard: `-InputsJson`,
  `-ArtifactRoot`, `-InvocationId`.
- **Outputs:** the `result` object above; artifacts `classified.json`, `classified.md`, `stderr.txt`,
  `result.json` (+ nested gateway artifacts).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `classified.json` (full payload), `classified.md` (human table),
  `result.json` (envelope), `stderr.txt` (diagnostics), and `gateway/` (each per-item gateway invocation's
  own artifact dir) + `_gateway_review_suppressed.jsonl` (see below).

### Proposed implementation
- **Language: PowerShell** (per policy: fastest correct MVP; orchestrates an existing skill; Windows-native).
  `Invoke-ClassifyBatch.ps1`.
- **Per item:** build a mode-specific `-System` prompt (classify: "respond with ONLY one label from this exact
  set"; multilabel: "comma-separated labels from the set, or NONE"; extract: "respond with ONLY a JSON object
  with these keys, null if absent"), truncate the item text to `max_input_chars`, then spawn the gateway as a
  child pwsh process: `& <pwsh> -NoProfile -File <gateway> -Tier <t> -System <sys> -Prompt <text> -MaxTokens
  <n> -Temperature 0 -Seed <seed> -ArtifactRoot <invDir>/gateway -ReviewQueuePath <invDir>/_gateway_review_
  suppressed.jsonl` (capture the child's single stdout envelope; stderr → temp file — mirrors `Invoke-Skill.ps1`).
- **Why suppress the gateway's own review writes:** the gateway appends to the review queue on *its* low
  generation-completeness confidence (<0.5). To keep the canonical queue clean and correctly attributed,
  classify.batch points the gateway's `-ReviewQueuePath` at a discardable in-artifact file and is itself the
  **sole author** of `flagged_by:"classify.batch"` items using its classification confidence.
- **Parse + confidence heuristic (documented; classification completeness + validity, NOT calibrated
  correctness):**
  - classify: normalize (trim, strip quotes/trailing punctuation, case-fold) → exact in-set match, gateway
    finish `stop` → **0.8**; matched only by substring/fuzzy, or extra text present → **0.6**; answer not in
    the label set → **0.2** (flag `uncategorized`, label `null`); empty/gateway-error → **0.1** (flag).
  - multilabel: all returned labels in-set, finish `stop` → **0.75**; some returned out-of-set (dropped) →
    **0.5**; `NONE` cleanly → **0.7**; none parseable → **0.15** (flag).
  - extract: valid JSON, all requested fields present & non-null → **0.75**; valid JSON, some fields
    missing/null → **0.5** (flag `failed_transform` if none present); unparseable JSON (salvaged first `{...}`)
    → **0.3** (flag); empty → **0.1** (flag).
  - A gateway `finish_reason=length` (truncation) caps the item at ≤0.4 and adds a warning (mirrors the
    gateway's own signal).
  - Item confidence `< confidence_threshold` → one `review_queue.jsonl` record.
- **Robustness:** a per-item gateway failure never aborts the batch (that item → `status:"error"`, flagged
  `failed_transform`, batch continues); StrictMode-safe array handling (assign `@()` first, `.ToArray()` on
  lists — per the confirmed pwsh 7.4.6 gotchas); only the JSON envelope to stdout, diagnostics to stderr.
- **Batch status:** all items ok → `ok`; ≥1 item errored but ≥1 succeeded → `partial`; setup failure
  (no items/labels/fields/mode/gateway) → `error` with a structured `error{code,message,retryable}`.

### External tools or models (already present — do NOT reinstall)
- `model.gateway` at `modules/07-model-gateway/Invoke-ModelGateway.ps1` (+ its `models.json`, the staged
  `llama-server`, the GGUF LLMs). Nothing new to install. `pwsh` 7.4.6 at the dotnet-tool path.

### Installation steps
- None. This module only adds PowerShell + docs; it reuses the gateway and Module 1 libraries in place.

### Tests
- **Direct + through the executor** (`Invoke-ClassifyBatchTests.ps1`, run via the executor for GPU + models):
  - Manifest validates (`Test-SkillManifest`).
  - Error paths (no model load, fast): `no_items`, `no_labels` (classify with empty labels), `invalid_mode`,
    `no_fields` (extract, no fields), `gateway_not_found` — each a **valid error envelope, exit 0**.
  - **LIVE** `classify` over a small batch (3–4 items) on `-Tier tiny`/`weak` with an obvious taxonomy (e.g.
    animal/vehicle/food): envelope validates, `status ok`, every item has an in-set `label` and a `confidence`
    in 0..1, `groups` partitions the ids, aggregate `model_provenance[0]` has summed tokens + call count,
    artifacts on disk with sha256.
  - **LIVE** `extract` over 1–2 items (e.g. pull `{name, topic}`): item `extracted` is a JSON object with the
    requested keys.
  - **Review routing:** a deliberately ambiguous item (or `-ConfidenceThreshold 0.99`) forces a low-confidence
    flag → assert a `review_queue.jsonl` line with `schema lifeorch.review.item/0.1`,
    `flagged_by:"classify.batch"`, per-item `source_ref`; and assert the gateway's own review writes went to
    the **suppressed** in-artifact file, not the canonical queue.
  - Wrapper: `Invoke-Skill.ps1 -SkillDir <module> -InputsJson '{...}'` reports manifest+envelope valid.
  - No orphaned `llama-server` process remains after the run.

### MVP acceptance criteria
- [ ] `skill.json` validates (`Test-SkillManifest`).
- [ ] A live `classify` batch returns `status:"ok"`, a valid envelope, every item labeled in-set with a
      confidence, a correct `groups` partition, and one aggregate `model_provenance` entry.
- [ ] `extract` mode returns a JSON object per item with the requested fields.
- [ ] `tier` alias and explicit `model_id` both resolve (delegated to the gateway).
- [ ] Every setup error path emits a valid `status:"error"` envelope at `exit 0`; a per-item gateway failure
      degrades that item only and yields batch `status:"partial"`.
- [ ] A below-threshold item appends exactly one `lifeorch.review.item/0.1` (`flagged_by:"classify.batch"`)
      to the canonical review queue; the gateway's own review writes are suppressed to the artifact dir.
- [ ] Runs direct, wrapped (`Invoke-Skill.ps1`), and through the executor; artifacts written with sha256.
- [ ] Full regression suite green through the executor; no orphaned `llama-server`.

### Manual verification procedure
- Submit a classify batch through the executor with `{mode:"classify", tier:"weak", labels:["animal",
  "vehicle","food"], items:[{id:"a",text:"a golden retriever puppy"},{id:"b",text:"a red pickup truck"},
  {id:"c",text:"a bowl of ramen"}]}`; confirm `completed`, read the `stdout.txt` envelope, open
  `classified.md`, confirm each item's label is sensible and `groups` matches, and that no `llama-server`
  lingers.

### Documentation requirements
- Skill `README.md` (modes, schema declaration, confidence semantics + why it differs from the gateway's,
  gateway-review suppression, throughput caveat, how to add/swap a taxonomy or tier), `skill.json`,
  `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add `classify.batch` to `TOOL_MODEL_REGISTRY.md` (status, location, invocation, last test). No new model.

### State updates
- `CURRENT_STATE.md` (active module, tests, next action), `MODULE_ROADMAP.md#8` → MVP complete,
  `DECISION_LOG.md` (new entry: classify.batch design — per-item gateway calls, gateway-review suppression,
  classification confidence heuristic), `REVIEW_QUEUE.md` (note classify.batch as a second producer + the
  throughput/warm-worker and calibrated-confidence follow-ons).

### Known follow-on work (NOT this session)
- Warm/persistent gateway worker (or an intra-batch single-prompt mode) to remove per-item model-load cost
  once batch latency dominates (pressure on D-0002 / D-0016).
- A side-effecting `sort.files` skill that physically routes files into per-label folders from a
  classify.batch result.
- Calibrated/semantic per-item confidence (replace the completeness+validity heuristic).
- Module 9 (`review.processor`) to drain the items this module flags.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g., moving files, a warm worker, open-vocabulary) → stop,
  write it to the roadmap.
- The gateway cannot be invoked (missing/failing) and fixing it is non-trivial → stop, report (it is a
  separate, already-complete module).
- MVP acceptance met → **stop; do not start Module 9.**
