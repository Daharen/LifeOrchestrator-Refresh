# Work Order: Image Index (`image.index`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md#module-18`

### Problem being solved
The perception block built four independent skills over the last four modules — `ocr.layout` (#14, text + boxes),
`image.util` (#15, pixel meta + hashes), `detect.objects` (#16, object boxes + scores), `image.interpret` (#17, a VLM
free-text interpretation) — but nothing **fuses** them. To reason about "what is in this image" a caller must invoke
four skills, parse four envelopes, and stitch the results by hand. Module 18 `image.index` closes that gap: **one call
per image → one fused record** carrying the pixel meta/hashes + OCR text/lines + object detections + the VLM
interpretation, each stage tagged with its own confidence and model provenance, plus a human-readable per-image card.
It is the **capstone** of the image/document block (14–18).

### Immediate practical use
A frontier or local agent (or a future `artifact.search` #23 / `route.tasks` #24 / `observe.broker` #25) can index a
screenshot or a photo into a single machine-readable `index.json` and a human `index.md` "card" — a durable, searchable
description of one image — with a single invocation, choosing how deep to look via flags (hash-only, +OCR, +objects,
+interpretation). "Index this screenshot" and "describe + read + detect everything in this photo" become one command.

### Explicit scope (in)
- **An orchestrator/composer, not a new perception engine.** It spawns the existing child skills as child `pwsh`
  processes, parses their `lifeorch.skill.result/0.1` envelopes, and **reimplements nothing** (the payoff of the shared
  contract — mirrors `voice.live` #13).
- **Children:**
  - `image.util` (#15) — **always** runs (op `meta`): the deterministic backbone. Yields canonical dimensions +
    format/mode + `sha256`/`pHash`/`dHash`. Every indexed image gets meta + hashes even with no other flag.
  - `ocr.layout` (#14) — behind **`-Ocr`**. Text + per-word/line boxes + reading order.
  - `detect.objects` (#16) — behind **`-Detect`**. Class boxes + real per-detection scores + `class_summary`.
  - `image.interpret` (#17) — behind **`-Interpret`**. VLM free-text (default mode `describe`; `-Prompt` → VQA).
  - **`-All`** convenience → enables `-Ocr -Detect -Interpret`.
- **Sources:** an explicit `-InputFile`, or **`-Capture`** (compose `capture.screen` #6 **once**, then feed the captured
  PNG to every child — capture is not repeated per child).
- **Compose knobs passed through** (image.index reimplements none of these — the child owns each):
  - **`-MaxDimension`** → passed to `detect` and `interpret` (they downscale-then-rescale-boxes-to-original correctly).
    `image.util` always runs on the **original** for canonical meta/hash; OCR runs native (Windows.Media.Ocr handles up
    to 10000 px).
  - Per-child selectors: `-Language` (ocr), `-Classes` (detect), `-InterpretMode`/`-Prompt`/`-Tier`/`-InterpretModel`
    (interpret).
- **Sequential** child execution (capture → image.util → ocr → detect → interpret). Sequential is the MVP: it avoids
  VRAM/loopback-port contention from `image.interpret`'s `llama-server` and sidesteps the executor's file-lock class;
  concurrent execution is an explicit non-goal/follow-on.
- **Fused output:** `index.json` (machine: image meta/hashes + OCR words/lines + detections + the VLM interpretation,
  **each stage tagged with its confidence + provenance**) and `index.md` (a human per-image card). Envelope
  `confidence` = the **minimum** confidence across the stochastic stages that actually ran (weakest-link signal for the
  fused record), `null` when only `image.util` ran. Aggregate **stage-tagged `model_provenance`** from every child.
- **Orchestrator, NOT a review-queue producer** (mirrors `voice.live` #13): it **redirects** children's review-queue
  writes to an in-artifact **`child_review.jsonl`** (default) so a transient index run does not flood the canonical
  `review_queue.jsonl`, and it **does not re-flag** anything itself. `-ReviewQueuePath` lets a caller aim child flags
  elsewhere (e.g. the canonical queue) if they explicitly want that.

### Non-goals (out — do NOT build)
- **No new model, no `models.json` change, no Module 7 re-verify** — #18 composes existing skills; it wires nothing new.
  (PROBE/confirm before assuming; but expected: none.)
- **Not a review producer** — no new `flagged_by`, no canonical-queue writes, no `REVIEW_QUEUE.md` change.
- **No concurrent/parallel child execution** (sequential MVP; concurrency is a follow-on).
- **No batch/directory/glob indexing** (one image per call; batch is a follow-on, like every other perception module).
- **No new perception logic** — no reimplemented OCR/detection/captioning/hashing; no cross-stage "grounding" (e.g.
  associating a detection box with an OCR word or a caption phrase) — that fusion-reasoning is a later module (#22/#25).
- **No overlay/annotated image** (needs the deferred `image.util` draw op).
- **No persistence/DB/search index** — that is `artifact.search` (#23).

### Dependencies
- Modules: `image.util` #15 (always), `ocr.layout` #14, `detect.objects` #16, `image.interpret` #17, `capture.screen`
  #6 (via `-Capture`), `skill.bootstrap` #1 (`lib/SkillContract.psm1` + `Invoke-Skill.ps1`).
- Tools/models: **none new.** Transitively the children use the system python (image.util/detect), Windows PowerShell
  5.1 + Windows.Media.Ocr (ocr), and the staged `llama-server` + `vlm.qwen2p5-vl-3b` (interpret) — all already present
  and registry-driven; #18 resolves nothing from `models.json` itself.
- Contract features: `-InputsJson` generic arg passing; `review_queue_path` redirect; child `-ArtifactRoot` sub-roots;
  `lifeorch.skill.result/0.1` envelope parsing + `model_provenance` aggregation.

### Skill contract requirements
- `skill_id` = `image.index`, `name` = "Image Index", `version` = `0.1.0`, `contract_version` = `0.1`.
- `determinism` = **`mixed`** (deterministic when only `image.util` runs; stochastic when any of ocr/detect/interpret
  run). `parallel_safe` = **`false`** (conservatively — can bind CUDA/VRAM + a loopback port via `-Interpret`; a run
  limited to image.util+ocr+detect is effectively parallel-safe but the manifest declares the conservative superset).
  `batch` = `false`. `streaming` = `false`.
- `result` shape: see below. `confidence` populated (min stochastic child confidence) or `null` (image.util-only).
  `model_provenance` = the stage-tagged aggregate of all child models. Artifact kinds: `json` (`index.json`) +
  `markdown` (`index.md`).

### Inputs and outputs
- **Inputs (named params / `InputsJson` keys):** `input`/`-InputFile` (string; required unless `-Capture`),
  `-Capture` (switch) + `-CaptureInputsJson`, `-Ocr`/`-Detect`/`-Interpret`/`-All` (switches), `-MaxDimension` (int),
  `-Language` (ocr), `-Classes` (string[] detect), `-InterpretMode` (caption|describe|vqa|screen, default `describe`),
  `-Prompt` (interpret VQA), `-Tier`/`-InterpretModel` (interpret model), `-ConfidenceThreshold` (passed to the
  stochastic children for their own review flagging), child path overrides
  (`-ImageUtilPath`/`-OcrPath`/`-DetectPath`/`-InterpretPath`/`-CapturePath`), `-PwshPath`/`-PythonPath`/
  `-Powershell51Path`, `-ReviewQueuePath`, `-InputsJson`, `-ArtifactRoot`, `-InvocationId`.
- **Outputs (`result`, schema `lifeorch.image.index/0.1`):**
  `input{path,source,capture}`, `image{width,height,format,mode,has_alpha,dpi,...}` (from image.util meta),
  `hashes{sha256,phash,dhash}` (from image.util), `stages{ image_util, ocr, detect, interpret }` — each a
  `{ran,status,confidence,reason,artifact_dir,error,+stage-specific payload}` object (ocr: text/word_count/line_count/
  lines; detect: detection_count/class_summary/detections; interpret: mode/text/finish_reason/completion_tokens),
  `summary{caption,ocr_text,top_objects,stochastic_confidence_min,stages_ran,stages_ok,stages_error}`,
  `review{mode,child_review_path,child_review_count}`, `config{...}`.
  Artifacts: `index.json` (kind `json`), `index.md` (kind `markdown`).

### Artifact structure
- `runtime/artifacts/<invocation_id>/`
  - `index.json` — the fused machine record (schema `lifeorch.image.index/0.1`).
  - `index.md` — the human per-image card.
  - `result.json` — the standard result envelope.
  - `child_review.jsonl` — redirected child review items (present only if a child flagged something).
  - `stderr.txt` — diagnostics.
  - `image_util/`, `ocr/`, `detect/`, `interpret/`, `capture/` — each child's own artifact sub-root (referenced by
    `stages.*.artifact_dir`).

### Proposed implementation
- **Language: PowerShell** (pwsh 7.4.6) — a pure orchestrator, no model/pixel work of its own; matches `voice.live`.
  Reuse: the `Has`/`Prop`/`Get-Sha256Hex`/`Resolve-RepoRoot`/`Resolve-Child`/`Invoke-Child`/`Add-Provenance` scaffolding
  from `Invoke-VoiceLive.ps1` (#13); the `-Capture`/`-MaxDimension` + `InputsJson`-merge compose helpers from
  `Invoke-ImageInterpret.ps1`/`Invoke-DetectObjects.ps1` (#16/#17).
- **Flow:** merge `InputsJson` → resolve source (file, or capture once via #6) → resolve requested child entrypoints →
  run `image.util meta` → optionally `ocr.layout`/`detect.objects`/`image.interpret` (each with
  `review_queue_path=<child_review.jsonl>`, `input=<image>`, `-MaxDimension` for detect/interpret) → parse each
  envelope, aggregate provenance, tag confidences → fuse `index.json`/`index.md` → emit the envelope.

### External tools or models
- None to install — see Dependencies. Everything the children need is already verified in `TOOL_MODEL_REGISTRY.md`.

### Installation steps
- None (composes existing modules). Cloud box: install pwsh 7.4.6 for the off-machine gate (done at session start).

### Tests
- **Cloud pre-ship gate (off-machine):** AST parse-check every shipped `.ps1`; a **dual-mode** harness
  (`Invoke-ImageIndexTests.ps1 -UseMock`) points all four children (and capture) at a single `tests/mock-child.ps1`
  that branches on its `-ArtifactRoot` leaf (`image_util|ocr|detect|interpret|capture`) and emits a valid
  child envelope (the image.util branch emits real meta+hashes for a generated fixture) — so the **real**
  `Invoke-ImageIndex.ps1` fuse/aggregate/redirect/envelope logic runs unchanged on the cloud Linux box. Mirrors the
  M13 mock-children gate (the VLM's real weights can't run on the cloud box).
- **Through the executor (live, Windows):** the identical harness with real children over a real fixture image —
  image.util always; `-Ocr`/`-Detect`/`-Interpret` on; the `-Capture` compose; `-MaxDimension` pass-through; the child
  review redirect (canonical `review_queue.jsonl` untouched); the Module 1 wrapper. Assert schema-valid envelope +
  `index.json`/`index.md` artifacts with sha256, no orphaned `llama-server`/`python`/`powershell` processes, and
  byte-exact shipped-file sha256.

### MVP acceptance criteria
- `image.index` produces a schema-valid `lifeorch.skill.result/0.1` envelope + `index.json` + `index.md`.
- Default run (no flags) fuses **image.util meta+hashes** only, `confidence:null`, empty aggregate provenance.
- `-All` fuses all four stages; `stages.*` each carry `{status,confidence,reason,payload,artifact_dir}`; envelope
  `confidence` = min stochastic child confidence; `model_provenance` aggregates ocr+detect+interpret (stage-tagged).
- Child review writes land in the in-artifact `child_review.jsonl`; the canonical `review_queue.jsonl` is **not**
  written by image.index.
- `-Capture` sources the image once via `capture.screen` and feeds it to every stage (`input.source:"capture"`).
- `-MaxDimension` reaches detect + interpret (boxes rescaled to original).
- Error paths (`input_not_found`, a requested child entrypoint missing, capture failure) → schema-valid `status:error`.
- Tests green off-machine (mock children) **and** live via the executor; no orphaned processes.

### Manual verification procedure
- Run `Invoke-ImageIndex.ps1 -InputFile <photo> -All` on the executor; open `index.md` and confirm the card shows the
  caption, the OCR text, and the object table; open `index.json` and confirm each stage's confidence + provenance and
  the top-level `sha256`/`phash`/`dhash`.
- Run `-Capture -All -InterpretMode screen` and confirm the screen is captured once, read, detected, and interpreted.

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- **None expected** (`TOOL_MODEL_REGISTRY.md` + `models.json` unchanged — it wires nothing new). Confirm during build.

### State updates
- Update `CURRENT_STATE.md` (Active module → none; #18 complete; block 14–18 complete) and `MODULE_ROADMAP.md` (#18 →
  MVP complete). New `DECISION_LOG.md` **D-0027**. `REVIEW_QUEUE.md` only if it unexpectedly becomes a producer (it
  won't). Mirror `core-docs/` → the attached Claude Project.

### Known follow-on work (NOT this session)
- **Concurrent** child execution (a warm-worker pool shared with #7/#8/#12/#14/#16/#17; run parallel-safe children
  together). **Batch/directory/glob** indexing. **Cross-stage grounding** (associate detections ↔ OCR words ↔ caption
  phrases; open-vocab boxes). **Overlay/annotated card image** (needs the `image.util` draw op). Persisting indices into
  `artifact.search` (#23). A frontier/`route.tasks` (#24) consumer of the redirected `child_review.jsonl`.

### STOP conditions
- Scope would exceed the "Explicit scope" list. A requested child is missing/broken (report; don't reimplement it).
- The contract lacks something #18 needs (stop, propose the change, don't freelance). MVP acceptance met — **stop; do
  not start Module 19.**
