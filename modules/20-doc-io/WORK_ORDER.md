# MODULE_WORK_ORDER — Local Document I/O (`doc.io`)

Copied from `MODULE_WORK_ORDER_TEMPLATE.md` and filled in. Keep it bounded — this exists to prevent
scope creep, not to specify the universe.

---

## Work Order: Local Document I/O (`doc.io`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority → Phase A #2 (`doc.io`)`

**Folder-number note:** on-disk `modules/20-doc-io/`. The `NN-` prefix is a **monotonic build-order counter**
(0, 00.1, 1..19, then 20); D-0029 decoupled it from the `ARCHITECTURE_MAP.md` 0-49 architectural positions.
`doc.io` has no dedicated spine slot — it is a Phase-A utility Module pulled forward as the cheap, high-utility
document primitive a local model (and, later, `agent.local`) calls.

### Problem being solved

Every local-model workflow that goes beyond one shot needs to **read**, **write**, **edit**, and **append**
text documents on this machine — read a file's content (or a slice of it), create/overwrite a document, make a
targeted in-place edit (find an exact string, replace it), or append a block to the end. Today no Module exposes
that primitive. `fs.observer` (Module 2) *inspects* the filesystem (trees, metadata, name/glob search) but never
returns a file's content and never writes; `uia.actor` mutates the UI, not files. The frontier agent has Read/
Write/Edit tools, but a **local** model driving Modules through the escalator (`logic.escalator` #19) and a future
local orchestrator (`agent.local`) have no document-I/O tool at all. `doc.io` closes that gap with a small,
deterministic, contract-conformant read/write/edit/append primitive.

### Immediate practical use

A local model — or the escalator, or a Widget, or an unattended executor task — that must **read a config/notes/
log/source file, write a generated document, patch one line in a file, or append a log/section**. Concretely this
week: it is the file substrate a local orchestrator needs to do real work (open a file → reason → edit it → save),
and it gives the review/notes/report flows a deterministic, auditable write path with content hashes and a
recoverable pre-image of every mutation.

### Explicit scope (in)

- **One skill, four operations, one op per invocation** (`-Op read|write|edit|append`).
- **read** — return a document's text (whole file, or an inclusive 1-indexed `-StartLine..-EndLine` line range),
  plus `line_count`, `byte_count`, `char_count`, `sha256`, detected `encoding`/`bom`/`eol`, and a `truncated`
  flag when the returned content is capped by `-MaxBytes`.
- **write** — create or overwrite a document with `-Content`. `-Overwrite` (default true; false → `already_exists`
  if present), `-CreateDirs` (default true), `-Eol lf|crlf` (default lf) newline normalization of the content.
- **edit** — exact-string replacement: find `-OldString`, replace with `-NewString`. Default requires **exactly one**
  occurrence (`not_found` / `not_unique` otherwise); `-ReplaceAll` replaces every occurrence; `-ExpectCount <n>`
  requires exactly n. **Preserves the file's existing EOL** (a CRLF file stays CRLF) by matching on an LF-normalized
  view and re-applying the file's newline convention on write.
- **append** — append `-Content` to the end. `-EnsureNewline` (default true) inserts a separating newline when the
  existing file does not end with one; `-Create` (default true) creates the file if missing. Appended newlines match
  the file's EOL by default.
- **Safety, all ops that mutate:** **atomic writes** (write a temp file in the same directory, then rename over the
  target — no torn files); an optional **`-ExpectSha256` optimistic-concurrency precondition** (the current file's
  sha256 must match, else `precondition_failed`) so a local model's read-modify-write loop is safe against a lost
  update; and a **recoverable pre-image** — the prior content is copied into the invocation's artifact dir as
  `before.<ext>` (bounded; skipped with a warning for very large files or with `-NoPreimage`).
- **Encoding:** UTF-8 default. Read auto-detects and strips a UTF-8 / UTF-16LE / UTF-16BE **BOM** (reported in the
  envelope); write defaults to **UTF-8 without BOM** (contract §3); edit/append **preserve** the file's detected
  encoding + BOM. A NUL-containing (binary) file is refused for read/edit/append with `binary_file`.
- **Contract conformance:** `-InputsJson` generic input, `-ArtifactRoot`, absolute artifact paths, a
  `lifeorch.skill.result/0.1` envelope on stdout + `result.json`, `stderr.txt` diagnostics.
- **Artifacts:** `doc.json` (machine result), `doc.md` (human card), `read.txt` (read), `before.<ext>` +
  `after.<ext>` (mutations), `result.json`, `stderr.txt`.

### Non-goals (out — do NOT build)

- **Batch / directory / glob** operations (one file per invocation; `batch:false`). A batch/glob mode is a follow-on.
- **Fuzzy / regex / diff-patch / multi-hunk** editing. Exact-string only (like the frontier Edit tool). A regex or
  unified-diff apply mode is a follow-on.
- **Structured-format awareness** (JSON/YAML/CSV/DOCX/PDF parsing or field edits). `doc.io` is a **text** primitive;
  format-aware editors are separate Modules/skills (and the docx/pdf/xlsx skills already exist at the frontier).
- **Move / copy / rename / delete / mkdir / chmod / metadata-set.** Those are filesystem *management*, a separate
  scoped skill (`fs.manage`, a future work order); `doc.io` only reads and writes **document content**.
- **Encodings beyond UTF-8 / UTF-16 (LE/BE) BOM handling** (no code-page/latin-1/UTF-32 matrix in the MVP).
- **Watching / tailing / streaming / locking daemons.** A read/append tail-follow or a cross-process lock protocol
  is a follow-on (see `parallel_safe` note below).
- **Sandbox / path confinement.** The executor is trust-based (D-0001); `doc.io` writes wherever the authorized user
  can. It adds **no** concealment/persistence/evasion (the D-0001 prohibitions) — a plain document tool.

### Dependencies

- Modules: none at runtime (composes nothing; Module 1 `Invoke-Skill.ps1` wraps it in tests). · Tools/models: **pwsh
  ≥7.4** + .NET `System.IO`/`System.Text`/`System.Security.Cryptography` only — **no external binary, no Python, no
  model, no `models.json` change, no Module 7 re-verify** (a pure primitive, the leanest skill yet). · Contract
  features used: `-InputsJson`, `-ArtifactRoot`, absolute artifact paths, the result envelope, `status:"error"`
  structured errors.

### Skill contract requirements

- `skill_id` `doc.io` · `name` "Local Document I/O" · `version` `0.1.0` · `contract_version` `0.2`.
- `determinism` **deterministic** → `confidence` **null**, `model_provenance` **[]**, **NOT a review-queue producer**
  (like `fs.observer` / `image.util` / `audio.ingest`). The review-queue producer set stays at **seven**.
- `parallel_safe` **false** (see rationale below) · `batch` **false** · `streaming` **false**.
- Result `result` shape: an object `{op, path, existed, file{encoding,bom,eol,line_count,byte_count,char_count,
  sha256}, ...op-specific...}` (see Inputs and outputs). `confidence`/`model_provenance` not populated. Artifact
  kinds: `json`, `markdown`, `text`.

**`parallel_safe:false` rationale (documented decision).** `doc.io` is the project's first general-purpose external-
file **mutator** — unlike the artifact-only writers `audio.ingest`/`image.util` (which only ever write fresh unique
paths and are `parallel_safe:true`), it writes/edits/appends **arbitrary caller-chosen paths**, so two concurrent
invocations *could* target the same file. The coarse manifest flag cannot say "safe for reads and distinct files,
unsafe for a same-file write," so the MVP declares the conservative **false** (the router serializes doc.io; no lost
updates) — matching the `uia.actor` "first side-effecting skill → false" precedent (D-0012). The implementation still
provides atomic temp+rename writes and the `-ExpectSha256` precondition, so a future `parallel_safe:true` (a read-only
fast path, or per-file locking) is a clean, already-scaffolded follow-on.

### Inputs and outputs

**Inputs** (named params; every key also accepted via `-InputsJson`):

- `op` (string, required) — `read` | `write` | `edit` | `append`.
- `path` (string, required) — target document; absolute, or relative to the process CWD → resolved to absolute.
- `content` (string) — required for `write` and `append`.
- `old_string` / `new_string` (string) — required for `edit`.
- `replace_all` (bool, default false) · `expect_count` (int, optional) — `edit`.
- `start_line` / `end_line` (int, 1-indexed inclusive, optional) · `max_bytes` (int, default 5_000_000) — `read`.
- `eol` (`lf`|`crlf`, default `lf`) — `write`/`append` content newline normalization (append defaults to the file's
  detected EOL when it has one).
- `overwrite` (bool, default true) · `create_dirs` (bool, default true) — `write`.
- `create` (bool, default true) · `ensure_newline` (bool, default true) — `append`.
- `encoding` (string, default `utf-8`) — MVP: `utf-8`; read also auto-detects a UTF-16 LE/BE BOM.
- `expect_sha256` (string, optional) — precondition for `write`/`edit`/`append`.
- `no_preimage` (bool, default false) — disable the `before.<ext>` pre-image artifact.
- `-ArtifactRoot` (string, optional, per contract).

**Outputs** — `result`:

- Common: `op`, `path` (absolute), `existed` (before the op), `file{encoding,bom,eol,line_count,byte_count,
  char_count,sha256}` (the resulting file for mutations; the read file for read).
- `read`: `content` (bounded by `max_bytes`), `returned{start_line,end_line,line_count,byte_count,truncated}`,
  `is_binary:false`.
- `write`: `created`, `bytes_written`, `sha256_before`, `byte_count_before`, `preimage{written,path}`.
- `edit`: `occurrences`, `replacements`, `replace_all`, `sha256_before`, `byte_count_before`, `preimage{...}`.
- `append`: `created`, `bytes_appended`, `ensured_newline`, `sha256_before`, `byte_count_before`, `preimage{...}`.

### Artifact structure

- `runtime/artifacts/<invocation_id>/` →
  - `result.json` (the full envelope), `stderr.txt` (diagnostics),
  - `doc.json` (the `result` payload), `doc.md` (human card),
  - `read.txt` (read: the returned content slice), or
  - `before.<ext>` + `after.<ext>` (write/edit/append: the pre-image and the new full content; `<ext>` from the
    target's extension, default `.txt`).

### Proposed implementation

- **Language: PowerShell (pwsh 7), single script `Invoke-DocIo.ps1`.** Per the language policy (PowerShell for
  Windows filesystem work + initial MVPs) and because a text/file primitive needs nothing more; a pure-PowerShell
  skill built on cross-platform .NET `System.IO`/`System.Text` is also the strongest possible pre-ship gate — the
  **real** skill runs unmodified on the cloud Linux box (like `image.util`/`audio.ingest`, no mock).
- **Byte-level I/O for determinism:** read with `[IO.File]::ReadAllBytes`; detect BOM + EOL + binary from the bytes;
  decode explicitly; write with `[IO.File]::WriteAllBytes` to `<path>.<guid>.tmp` in the same directory, then
  `[IO.File]::Move(tmp,path,$true)` (atomic same-volume rename). **Never** use `Environment.NewLine`, `Set-Content`,
  or `Out-File` (their EOL/encoding defaults differ across platforms) — all newline handling is explicit so behavior
  is identical on Windows and Linux.
- **EOL preservation (the CRLF-core-docs gotcha, generalized):** detect `crlf`/`lf`/`mixed`/`none`; for `edit`,
  match on an LF-normalized view and re-apply the file's convention on write (uniform CRLF stays CRLF; `mixed` →
  normalize to LF with a warning). This is exactly what makes editing this repo's own CRLF docs safe.

### External tools or models

- None. pwsh ≥7.4 (present, `TOOL_MODEL_REGISTRY.md`) + .NET BCL only. No install, no download, no `models.json`.

### Installation steps

- None. (Confirm `pwsh 7.4.6` on the target — already recorded — and that .NET `File.Move(string,string,bool)` is
  available on the target's .NET 8; it is.)

### Tests

- **Off-machine (cloud pre-ship gate):** AST-parse-check `Invoke-DocIo.ps1` + the test harness on cloud pwsh 7.4.6;
  then run the **real** skill through the **real** harness on the cloud Linux box (no mock — .NET file I/O is
  cross-platform). This is the `image.util`/`audio.ingest` real-engine-on-cloud gate.
- **Direct:** run the skill standalone for each op + each error path; assert a schema-valid `lifeorch.skill.result/0.1`
  envelope, correct `result` fields, on-disk sha256 == reported, and byte-exact content.
- **Through the executor (live on Windows):** submit the identical harness as a task package; assert `result.json`
  + artifacts + no leftover `*.tmp` files; plus a live CRLF-preservation check that edits a real CRLF fixture and
  confirms it stays CRLF, and a Module 1 wrapper run.

### MVP acceptance criteria

- [ ] `Invoke-DocIo.ps1` + `skill.json` + `README.md` + `examples/` present; manifest validates (Module 1).
- [ ] All four ops work: read (whole + line-range + truncation), write (create + overwrite + `already_exists` +
      `create_dirs`), edit (unique + `replace_all` + `not_found`/`not_unique`/`count_mismatch` + **CRLF preserved**),
      append (create + ensure-newline + EOL match).
- [ ] Atomic writes (no torn file; no leftover `*.tmp`); `-ExpectSha256` precondition enforced (`precondition_failed`);
      pre-image `before.<ext>` written and recoverable.
- [ ] BOM detect/strip on read; UTF-8-no-BOM on write; BOM preserved on edit/append; `binary_file` refusal.
- [ ] Every error path returns `status:"error"` + `error{code,message,retryable}` at **exit 0**; a valid envelope always.
- [ ] Deterministic posture verified: `confidence` null, empty `model_provenance`, **review queue untouched**.
- [ ] Reported `sha256`/`byte_count`/`line_count` match the on-disk file exactly.
- [ ] Off-machine harness green on the cloud box **and** the identical harness green live via the executor; shipped
      files sha256 byte-exact on the target.

### Manual verification procedure

- Read this file back with `-Op read`; edit a scratch copy of a CRLF core-doc with `-Op edit` and confirm (a) the
  change applied and (b) `file.eol` is still `crlf`; append a line and confirm `ensure_newline`; overwrite with
  `-ExpectSha256` set to a wrong hash and confirm `precondition_failed`.

### Documentation requirements

- Skill `README.md` + `skill.json` manifest + `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates

- Add a `doc.io` **skill** entry to `TOOL_MODEL_REGISTRY.md` (status installed, location, invocation, ops, last test).
  No tool/model/runtime entry (uses only pwsh + .NET, already registered).

### State updates

- Update `CURRENT_STATE.md` (new module complete; deterministic; not a producer) and this module's `MODULE_ROADMAP.md`
  status (Phase A #2 MVP complete). Add `DECISION_LOG.md` D-0031. `REVIEW_QUEUE.md` unchanged (non-producer — note
  the producer set stays at seven). No `models.json` change.

### Known follow-on work (NOT this session)

- Batch / directory / glob ops; a regex or unified-diff apply mode; structured-format (JSON/YAML/CSV) field edits;
  a sibling `fs.manage` for move/copy/rename/delete/mkdir; more encodings (code pages, UTF-32); a read-only or
  per-file-lock `parallel_safe:true` mode + a tail/follow read; insert-at-line / replace-line-range ops.

### STOP conditions (when to halt instead of expanding)

- Scope would exceed the "Explicit scope" list above (esp. batch, regex/diff, format-awareness, or fs-management).
- A dependency is missing/broken and installing it is non-trivial (not expected — pwsh + .NET only).
- The contract lacks something this module needs (stop, propose the contract change, do not freelance it).
- MVP acceptance is met — **stop; do not start the next module.**
