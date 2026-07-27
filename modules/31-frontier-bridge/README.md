# Module 31 — `frontier.bridge` (Frontier Bridge, local context packager)

A deterministic, **LOCAL-ONLY, NO-NETWORK** context packager. It turns a Claude-written prompt plus a
set of local files into **one copy-paste pack** that the user manually carries to their own external
model session (e.g. their own ChatGPT), and it reads the pasted answer back for Claude.

## The boundary (DECISION_LOG D-0051 / D-0052) — non-negotiable

`frontier.bridge` performs **outbound local packaging only**. It reads local files and writes a pack
file. It **never** submits to, scrapes, or drives ChatGPT or any external AI UI or service — it opens
no network connection of any kind. The **human is the sole courier**: they copy the pack out and paste
the answer back. This is the legitimate, in-bounds version of frontier offload (D-0052); the prohibited
version — software that automates access to an external AI service — is explicitly out of scope and is
guarded against by a static no-network assertion in the tests.

`skill.json` declares `requirements.network = false`. A test (`T15`) fails the build if any network
cmdlet appears in the entrypoint source.

## Actions

One action per invocation.

### `pack` (default)
Assemble the pack. Inputs (named params or a single `-InputsJson '<object>'`; a named param overrides
the matching JSON key):

- `prompt` *(required)* — the Claude-written instructions/context.
- `question` — the specific question, emphasised at the end of the pack.
- `paths` — explicit file paths and/or globs (e.g. `src\lib\*.ps1`).
- `folder` — a folder to include, with `include` / `exclude` name globs and `recurse` (default true).
- `max_file_bytes` (default 2,000,000) — any single file larger than this is skipped (`too_large`).
- `max_total_bytes` (default 20,000,000) — once the pack would exceed this, further files are skipped
  (`total_cap`). Binary files (NUL in the first 8 KB) are skipped (`binary`).
- `title`, `out_name`, `return_file` — cosmetic / naming.

Outputs, in `runtime/artifacts/<invocation_id>/`:

- `<out_name>.md` — the pack: a header (title, invocation id, *local-only* note), `## INSTRUCTIONS`,
  `## QUESTION`, an included/skipped manifest, then each file's content wrapped in
  `>>>>> FBRIDGE::<id>::FILE n : <path> >>>>>` … `<<<<< FBRIDGE::<id>::END n : <path> <<<<<`
  delimiters, and a `## HOW TO RETURN THE ANSWER` footer.
- `manifest.json` — `lifeorch.frontier.pack_manifest/0.1`: exactly what was included/skipped
  (path, bytes, sha256, encoding).
- `<out_name>.answer.md` — the **return file**: a stub with a dashed separator; the user pastes the
  model's answer below it.

### `read-return`
Read the pasted answer back. Input: `return_file` *(required)* — the file the user pasted into. The
result carries `{captured, content, sha256, char_count}`. If the file still holds only the stub,
`captured` is `false` and `status` is `partial`.

## Contract

`SKILL_CONTRACT.md` v0.2. Emits one `lifeorch.skill.result/0.1` envelope on stdout **and** to
`result.json` in the artifact dir. `determinism: deterministic` (identical semantic inputs → identical
`inputs_digest` and identical pack file set/content; `confidence: null`, empty `model_provenance`).
**Not** a review-queue producer. `parallel_safe: true` (reads inputs; writes only into its own
per-invocation artifact dir). CPU-only; no models; no external binaries.

## Run

```powershell
# pack
pwsh -NoProfile -File .\Invoke-FrontierBridge.ps1 -Action pack -Prompt "..." -Question "..." -Folder "..." -Include "*.ps1"
# read the answer back
pwsh -NoProfile -File .\Invoke-FrontierBridge.ps1 -Action read-return -ReturnFile "...\<id>\<out_name>.answer.md"
```

See `examples/` for full invocations and a representative result envelope.

## Tests

```powershell
pwsh -File tests\Test-FrontierBridge.ps1 -PwshPath pwsh [-WrapperPath ..\01-skill-bootstrap\Invoke-Skill.ps1]
```

63 checks (pure file I/O, no mock): pack/glob/folder/include/exclude/recurse, `too_large` /
`total_cap` / `binary` skips, no-match → `partial`, prompt-only, missing-input errors, `read-return`
capture + empty + not-found, `-InputsJson` equivalence + named-override, determinism, envelope-schema
completeness, the **no-network** static assertion, and manifest self-check. With `-WrapperPath` it also
runs through the Module 1 wrapper (the live box gate supplies it).
