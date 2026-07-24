# Work Order: Filesystem Observer (`fs.observer`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork), 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#fs.observer`

### Problem being solved
Agents and this project's own tooling need to inspect the local filesystem deterministically — list a
directory tree with metadata and search it by name — without taking screenshots or shipping whole
directories into a frontier model's context. This is the first *useful* skill on the Module 1 contract
and the substrate for later indexing/observation modules.

### Immediate practical use
Answers "what's under <dir>, how big, changed when, and where is <pattern>?" — a compact summary plus a
markdown tree a human can read and a JSON index a weaker local model or script can consume.

### Explicit scope (in)
- Deterministic recursive listing under a root, depth-bounded, with per-entry metadata (type, size,
  mtime, depth), sorted for stable output.
- Optional name/glob search (`pattern`) → a flat, bounded matches list.
- Artifacts: `tree.md` (human) and `index.json` (machine).
- Contract-valid `lifeorch.skill.result/0.1` envelope; runs directly, wrapped, and via the executor.
- Bounded output (`max_entries`) → `status:"partial"` + warning when exceeded; per-item error tolerance
  (skip unreadable subtrees with a warning, don't fail the whole run).

### Non-goals (out — do NOT build)
- Content/grep search inside files (later module).
- Change detection / persistent index / diffing (later; this is a point-in-time snapshot).
- Screenshots, process/window observation, UIA (Modules 3–6).
- Following symlinks/junctions (skipped to avoid cycles); hashing every file's contents.

### Dependencies
- Modules: Module 1 (`skill.bootstrap`) — reuse `lib/SkillContract.psm1` and `Invoke-Skill.ps1`.
- Tools/models: `pwsh>=7.4`. Contract features: manifest + result envelope, artifacts, timeout.

### Skill contract requirements
- `skill_id` `fs.observer`, `version` `0.1.0`, `determinism` `deterministic`, `parallel_safe` true,
  `batch` false, `streaming` false.
- `result` = `{ root, depth, generated_at_utc, entry_count, dir_count, file_count, bytes_total,
  truncated, pattern, match_count, matches[] }`; `confidence` null; artifact kinds `markdown` + `json`.

### Inputs and outputs
- **Inputs:** `path` (string, required), `depth` (int, default 3), `pattern` (string, optional glob),
  `include_hidden` (bool, default false), `max_entries` (int, default 5000).
- **Outputs:** result summary above; artifacts `tree.md`, `index.json` (+ `stderr.txt`, `result.json`).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `tree.md`, `index.json`, `stderr.txt`, `result.json`.

### Proposed implementation
- **Language:** PowerShell 7 (language policy — fast correct MVP; runs natively through the executor).
- Iterative depth-bounded walk; collect entries; sort by relative path (ordinal, case-insensitive) for a
  stable pre-order; skip reparse points; catch per-directory errors into warnings. Reuse Module 1 envelope
  conventions (inputs_digest, sha256 artifacts, UTF-8 no BOM, single JSON to stdout).

### External tools or models
- None beyond `pwsh` (registry-verified). No installs.

### Installation steps
- None. Files added under `modules/02-fs-observer/`.

### Tests
- **Direct:** run over the repo root (`-Depth 2`) → schema-valid envelope, counts > 0, `tree.md` +
  `index.json` present and listed with hashes, `index.json` entry_count matches result.
- **Search:** `-Pattern '*.md'` → non-empty matches.
- **Error:** nonexistent path → `status:"error"`, code `path_not_found`, valid envelope, exit 0.
- **Wrapped:** via `Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'` → manifest+envelope valid.
- **Through the executor:** submit task packages → `completed` + valid envelope + artifacts.

### MVP acceptance criteria
- [ ] `fs.observer` manifest passes `Test-SkillManifest`.
- [ ] Deterministic tree over a target dir; contract-valid envelope; `tree.md` + `index.json` present with
  matching hashes; counts consistent.
- [ ] Glob search returns correct matches.
- [ ] Runs through the executor (completed) and via the wrapper (both valid).
- [ ] `TOOL_MODEL_REGISTRY.md` has an `fs.observer` entry.

### Manual verification procedure
- Submit an executor task over a known dir; open `tree.md` (readable), inspect `index.json`, confirm
  `match_count`/`matches` for a `pattern`.

### Documentation requirements
- Module `README.md`, `skill.json`, `examples/` (invocation + a real captured result).

### Registry updates
- Add `fs.observer` (status, location, invocation, last test) to `TOOL_MODEL_REGISTRY.md`.

### State updates
- Update `CURRENT_STATE.md` and `MODULE_ROADMAP.md` (Module 2 → MVP complete; Module 3 next).

### Known follow-on work (future work orders — NOT this session)
- Content/grep search; change detection + persistent index; artifact/project indexing (ties to Module 23).
- Promote shared skill tooling to a `core/` location once a third skill needs it.

### STOP conditions
- Scope would exceed the "Explicit scope" list.
- A dependency is missing/broken and installing it is non-trivial.
- The contract lacks something this module needs (stop; propose the change; do not freelance).
- MVP acceptance is met — **stop; do not start Module 3.**
