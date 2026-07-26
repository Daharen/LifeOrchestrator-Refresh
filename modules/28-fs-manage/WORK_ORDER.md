# MODULE_WORK_ORDER: File Manage (`fs.manage`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-26 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority` (the deferred "deposit on the desktop" last-mile from D-0041)

> Folder-number note: on-disk `modules/28-fs-manage/`; the `NN-` prefix is a monotonic build-order counter
> (0, 00.1, 1..27, then 28). `fs.manage` is the `doc.io` (#20) follow-on named there ("a sibling `fs.manage`
> (move/copy/rename/delete/mkdir)"), scoped to the copy/move/mkdir MVP.

## Problem being solved

Running *"generate an image of a dog and place it on my desktop"* through `agent.local -Route` (D-0041)
generated the image but **never placed it on the desktop** (evidence: run `m29-before-001` — router picked only
`[gen.image]`, the image landed in the tool's artifact dir, the Desktop stayed empty; the grounded final answer
even said "the goal of placing the image on the desktop was not achieved"). The registry had **no tool that moves
or copies a file to a destination**. `fs.manage` is that last-mile tool.

## Immediate practical use

`agent.local` (and any Widget/caller) can now finish "make X and put it in folder Y" goals: gen.image/gen.music/
capture.screen produce a file, then `fs.manage` copies/moves it to the Desktop / Downloads / a chosen folder.

## Explicit scope (in)

- A **deterministic** skill (the `doc.io` #20 pattern: pure PowerShell + .NET, structured errors, sha256 report,
  no external binary/model). **One `-Op` per call: `copy` | `move` | `mkdir`.**
- **Smart path resolution** on `source` + `dest` — the feature that makes "put it on my desktop" work by default:
  known folders (`desktop`/`downloads`/`documents`/`pictures`/`music`/`videos`/`home`/`temp`) via
  `[Environment]::GetFolderPath` (correct even when Desktop is OneDrive-redirected), `~` → home, `%ENV%` expansion,
  absolute as-is, relative vs CWD. A **folder** destination keeps the source filename; a **file** path renames it.
- **Overwrite guard** (default off → `already_exists`); `create_dirs` for the destination parent.
- **Registry integration:** add `fs.manage` to `agent.local`'s `tools.json` with **`resolve_paths: false`** (a new
  per-tool flag) so the agent passes its path args verbatim — the working-dir prepend would otherwise turn
  `dest="desktop"` into `<workdir>\desktop`. agent.local's `Get-Observation` also surfaces `gen.image`'s produced
  `image.path` so the next step's arg-gen can copy it as `source`.

## Non-goals (out — do NOT build)

- **`delete`** (destructive — a local model choosing to delete is a real risk; defer, or gate behind `-AllowDelete`
  in a later increment). **`rename`** as a distinct op (a same-dir `move` covers it).
- Directory copy/move (files only in the MVP), glob/batch, recursive trees, symlinks, permissions/ACLs.
- No new model / no `models.json` change / no Module 7 re-verify; not a review-queue producer.

## Dependencies

- None to run (pure PowerShell + .NET). Composed by `agent.local` (#21) via the registry; chained after
  `gen.image` (#23) in the target demo.

## Skill contract requirements

- `skill_id` `fs.manage`, `version` `0.1.0`, `contract_version` `0.2`. `determinism` **deterministic**
  (`confidence:null`, empty `model_provenance`), `parallel_safe` **false**, `batch` **false**, `streaming` **false**.
- `result`: copy/move → `{op, source, dest, dest_folder, filename, dest_was_dir, overwrote, bytes, sha256,
  source_still_exists}`; mkdir → `{op, path, created, existed}`. Artifacts `manage.json`/`manage.md`.

## Tests

- **Off-machine (cloud pwsh, pre-ship gate):** `tests/Invoke-FsManageTests.ps1` (**21/21**) — copy-into-dir,
  move-rename, overwrite guard (+ `overwrite=true`), nested mkdir (+ existing), known-folder `desktop` resolution
  (lands under the user home), `~`/`%ENV%` expansion, error paths (`input_not_found`/`invalid_op`/
  `missing_parameter`), the Module 1 wrapper. OS-portable + deterministic.
- **agent.local integration (off-machine 54/54):** a `resolve_paths=false` mock tool receives an **un-prefixed**
  `dest="desktop"` (S13) — the working-dir prepend is correctly skipped.
- **Live (executor):** shipped-files sha256 + AST on target; and the **REAL chained e2e** — *"generate an image of
  a dog and place it on my desktop"* `-Route` → `[gen.image, fs.manage]` → the dog image lands on the real Desktop.

## MVP acceptance criteria

- [ ] Manifest validates; deterministic/parallel_safe=false/batch=false/streaming=false.
- [ ] copy/move/mkdir work; a folder dest keeps the filename; a file dest renames; overwrite guarded.
- [ ] `desktop`/`~`/`%ENV%` resolve correctly (Desktop via GetFolderPath, OneDrive-safe).
- [ ] agent.local routes `[gen.image, fs.manage]` for the goal and the image lands on the Desktop **by default**.
- [ ] Not a review-queue producer; Module 1 wrapper runs it.

## Registry updates / State updates

- `agent.local/tools.json` (add fs.manage, resolve_paths:false); `TOOL_MODEL_REGISTRY.md` (fs.manage entry);
  `CURRENT_STATE.md`, `MODULE_ROADMAP.md`, `DECISION_LOG.md` (D-0042).

## Known follow-on work (NOT this session)

- `delete`/`rename` (gated), directory ops, glob/batch, a general artifact-collector; richer chained-goal
  reliability (the D-0032 termination follow-on — the models still under-use `finish`).

## STOP conditions

- Scope beyond copy/move/mkdir. MVP acceptance met (the image lands on the Desktop by default) — stop.
