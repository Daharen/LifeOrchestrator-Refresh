# doc.io — Local Document I/O (Module 20)

A small, **deterministic** document primitive: **read**, **write**, **edit**, and **append** UTF-8 text
documents on this machine. One operation per invocation. This is the file substrate local models (the
escalator `logic.escalator` #19, a future local orchestrator `agent.local`, Widgets, unattended executor
tasks) call to do real document work — the local counterpart to the frontier agent's Read/Write/Edit tools.

Pure PowerShell over cross-platform .NET file I/O — **no external binary, no Python, no model, no
`models.json` change**. It composes nothing at runtime. Like `fs.observer`/`image.util`/`audio.ingest` it is
`determinism:"deterministic"` (`confidence:null`, empty `model_provenance`) and **not a review-queue producer**.

## Operations

| op | does | key inputs |
|----|------|-----------|
| `read`   | return a document's text (whole file or a 1-indexed inclusive line range) + metadata | `path`, `start_line?`, `end_line?`, `max_bytes?` |
| `write`  | create or overwrite a document with `content` | `path`, `content`, `overwrite?`, `create_dirs?`, `eol?` |
| `edit`   | exact-string replace: find `old_string`, replace with `new_string` | `path`, `old_string`, `new_string`, `replace_all?`, `expect_count?` |
| `append` | append `content` to the end (create if missing) | `path`, `content`, `ensure_newline?`, `create?` |

## Invocation

Direct (named params):

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op read  -Path C:\path\notes.md -StartLine 10 -EndLine 40
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op write -Path C:\path\out.md -Content "# Title`nbody" -Eol lf
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op edit  -Path C:\path\out.md -OldString "foo" -NewString "bar"
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op append -Path C:\path\log.md -Content "- new entry"
```

Generic (`-InputsJson`, the path a caller/orchestrator uses):

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -InputsJson '{"op":"edit","path":"C:\\x\\a.md","old_string":"foo","new_string":"bar","replace_all":true}'
```

Wrapped (Module 1) or as an `exec.bootstrap` task package: `..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir .`.

## Safety model

- **Atomic writes.** Every mutation writes a temp file in the target's own directory and renames it over the
  target (`File.Move(..., overwrite:$true)`), so a reader never sees a half-written file and a crash never
  leaves a truncated document. No `*.tmp` remains on success.
- **Optimistic concurrency.** Pass `expect_sha256` (the sha256 you last read) on `write`/`edit`/`append`; if the
  file changed since, the op fails with `precondition_failed` instead of clobbering the newer content. This is
  what makes a local model's read → reason → edit loop safe.
- **Pessimistic serialization (opt-in doc lease, res.lease #29).** Pass `-Lease` (or `lease:true`) on
  `write`/`edit`/`append` to acquire the `doc:<relpath>` lease around the whole read-modify-write, so several
  instances editing the *same* file serialize instead of racing. The resource name is auto-derived from the
  target (repo-relative when under the repo, else the absolute path; `-LeaseResource` overrides). Held by
  another and not free within `lease_wait_s` (default 120) → `doc_lease_unavailable` (retryable); **additive and
  graceful** — off by default, and when `res.lease` is absent/unresolvable it logs a warning and proceeds with
  behaviour unchanged. Released right after the atomic write (and on any emit). The outcome is reported under
  `result.lease{enabled,resource,available,acquired,owned,already_held,lease_id,held_by,released}`. This
  completes the res.lease consumer trio (`gpu`→model.gateway #7, `git`→dev.ship, `doc:<path>`→doc.io).
- **Recoverable pre-image.** Every mutating op copies the prior content into the invocation's artifact dir as
  `before.<ext>` (and the new content as `after.<ext>`), so a bad edit is always recoverable. Skipped with a
  warning for files larger than ~8 MB, or with `-NoPreimage`.
- **EOL preservation.** `edit`/`append` keep the file's existing newline convention — a CRLF file (like this
  repo's own core-docs) stays CRLF; an LF file stays LF. `write` writes `eol` (default `lf`; `crlf` optional).
- **Encoding.** UTF-8 by default. `read` auto-detects and strips a UTF-8 / UTF-16LE / UTF-16BE **BOM** (reported
  in the envelope); `write` defaults to UTF-8 **without** BOM (contract §3); `edit`/`append` **preserve** the
  file's detected encoding + BOM. A binary file (NUL byte) is refused for read/edit/append with `binary_file`.

## Result (`result`) shape

Common: `{op, path (absolute), existed, file:{encoding, bom, eol, line_count, byte_count, char_count, sha256}}`.

- `read`  → `content` (bounded by `max_bytes`), `returned:{start_line, end_line, line_count, byte_count, truncated, ranged}`.
- `write` → `created`, `bytes_written`, `sha256_before`, `byte_count_before`, `preimage:{written,path,reason}`.
- `edit`  → `occurrences`, `replacements`, `replace_all`, `sha256_before`, `byte_count_before`, `preimage`.
- `append`→ `created`, `bytes_appended`, `ensured_newline`, `sha256_before`, `byte_count_before`, `preimage`.

`confidence` is `null` and `model_provenance` is `[]` (deterministic). The full `lifeorch.skill.result/0.1`
envelope goes to stdout and to `result.json`; diagnostics to `stderr.txt`.

## Errors (all `status:"error"`, structured `error:{code,message,retryable}`, exit 0)

`invalid_op`, `missing_parameter`, `input_not_found`, `path_is_directory`, `parent_not_found`, `already_exists`,
`binary_file`, `not_found` (edit: 0 matches), `not_unique` (edit: >1 match, no `replace_all`/`expect_count`),
`count_mismatch`, `precondition_failed`, `invalid_range`, `invalid_argument`, `no_change`, `encoding_unsupported`.

## Artifacts (`runtime/artifacts/<invocation_id>/`)

`result.json`, `stderr.txt`, `doc.json` (machine result), `doc.md` (human card); `read.txt` (read) **or**
`before.<ext>` + `after.<ext>` (write/edit/append).

## Flags

`determinism:"deterministic"` · `parallel_safe:false` · `batch:false` · `streaming:false`.

**`parallel_safe:false`** — `doc.io` is the first general-purpose external-file **mutator** (it writes arbitrary
caller-chosen paths, unlike the artifact-only writers `audio.ingest`/`image.util`), so two concurrent
invocations *could* target the same file. The conservative MVP declares `false` (the router serializes it) even
though reads and distinct-file writes are independent; atomic writes + `expect_sha256` + the opt-in `-Lease`
per-file `doc:<path>` lock (Safety model above) are in place so a future `parallel_safe:true` mode is a clean
follow-on. See DECISION_LOG D-0031.

## Non-goals (see WORK_ORDER.md)

Batch/directory/glob; regex or diff-patch editing; structured-format (JSON/YAML/CSV/DOCX) field edits;
move/copy/rename/delete/mkdir (a future `fs.manage`); encodings beyond UTF-8/UTF-16-BOM; watch/tail/lock daemons.

## Tests

`tests/Invoke-DocIoTests.ps1` is real-worker and OS-portable (no mock — .NET file I/O is cross-platform): it
generates its own fixtures, runs the **real** skill for every op + error path + CRLF/BOM/precondition/atomic
check, and validates the Module 1 wrapper. It ran on the cloud Linux box (pwsh 7.4.6) as the pre-ship gate and
the identical harness ran live via the Windows executor. See `WORK_ORDER.md` and DECISION_LOG D-0031.
