# fs.manage — File Manage (copy / move / mkdir) (Module 28)

**`fs.manage`** is the deterministic **last-mile file-placement** primitive: it puts a file the machine produced
where the user wants it. It closes the "deposit on the desktop" gap — the reason *"generate an image of a dog and
place it on my desktop"* previously produced the image but never delivered it.

One op per invocation:

- **copy** — copy an existing file to a destination (a folder or a full file path).
- **move** — move/rename an existing file to a destination.
- **mkdir** — create a folder (parents included).

## Smart path resolution (why "put it on my desktop" just works)

Both `source` and `dest` go through a forgiving resolver so a local model can say what a human would:

- **Known folders** — `desktop`, `downloads`, `documents`/`docs`, `pictures`, `music`, `videos`, `home`, `temp`
  resolve to the *real* user folder via `[Environment]::GetFolderPath` (so a OneDrive-redirected Desktop like
  `C:\Users\you\OneDrive\Desktop` is found correctly — a hardcoded `C:\Users\you\Desktop` would be wrong).
- **`~`** → the user home; **`%VAR%`** environment variables are expanded.
- An **absolute** path is used as-is; a **relative** path resolves against the current directory.
- When the destination is a **folder** (a known folder, an existing directory, a trailing-separator path, or an
  extension-less path), the source's own filename is kept inside it; a full file path renames it.

An existing destination file is **not** overwritten unless `overwrite=true` (else `already_exists`).

## Inputs (named or `-InputsJson`)

`op` (**required**, copy|move|mkdir); `source` + `dest` (copy/move); `path` (mkdir); `overwrite` (default false);
`create_dirs` (default true).

## Output (`result`)

copy/move → `{op, source, dest (final absolute path), dest_folder, filename, dest_was_dir, overwrote, bytes,
sha256, source_still_exists}`; mkdir → `{op, path, created, existed}`. Artifacts `manage.json`/`manage.md`.

## Flags

`determinism: deterministic` (`confidence:null`, empty `model_provenance`), `parallel_safe: false` (mutates
arbitrary caller-chosen paths, like `doc.io`), `batch: false`, `streaming: false`. **NOT a review-queue
producer.** Pure PowerShell + .NET — no external binary / Python / model / `models.json` change.

## Use with agent.local

`fs.manage` is in `agent.local`'s curated `tools.json` with **`resolve_paths: false`**, so the agent passes its
`source`/`dest` **verbatim** (the working-dir prepend is skipped) and fs.manage does the known-folder/`~`/`%ENV%`
resolution itself. Chained with `gen.image`, *"generate an image of a dog and place it on my desktop"* now
routes to `[gen.image, fs.manage]`, generates the image, and copies it to the real Desktop.

## Tests

`tests/Invoke-FsManageTests.ps1` (21/21) — copy-into-dir, move-rename, the overwrite guard, nested mkdir,
known-folder `desktop` resolution (lands under the user home), `~`/`%ENV%` expansion, error paths, and the
Module 1 wrapper. OS-portable + deterministic; runs on cloud pwsh (pre-ship gate) and unchanged live.
