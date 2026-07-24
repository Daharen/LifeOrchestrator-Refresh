# Work Order: Skill Contract & Registry Bootstrap (`skill.bootstrap`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork), 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#skill.bootstrap`

### Problem being solved
There is a drafted skill contract (`SKILL_CONTRACT.md` v0.1) but nothing that *proves* a real skill
can satisfy it, and no shared tooling to check that a manifest or a result envelope actually conforms.
Without a worked example and a validator, every later module would reinvent the interface and drift.

### Immediate practical use
Gives the very next module (Module 2, `fs.observer`) a copyable pattern and a validator it can call,
plus a generic wrapper that runs any conforming skill and confirms its envelope — so skills can be
invoked and trusted through the Module 0 executor this week.

### Explicit scope (in)
- Dependency-free validators for `proteus.skill.manifest/0.1` and `proteus.skill.result/0.1`.
- One trivial reference skill (`ref.echo`) with `skill.json`, entrypoint, README, and examples.
- A simple invocation wrapper: validate manifest -> run entrypoint (isolated process) -> validate envelope.
- Proof it runs **directly** and **through the executor**, emitting a schema-valid envelope.
- A `TOOL_MODEL_REGISTRY.md` entry format for a skill, proven by `ref.echo`.

### Non-goals (out — do NOT build)
- A plugin framework, registration daemon, RPC/HTTP layer, auth, or capability tokens.
- A machine-readable JSON registry / router (Module 24) or a shared skills SDK.
- Normative changes to `SKILL_CONTRACT.md` beyond recording provisional conventions (see below).
- Any second skill, or `fs.observer` work.

### Dependencies
- Modules: Module 0 (`exec.bootstrap`, running). · Tools/models: `pwsh>=7.4` (registry: `pwsh` 7.4.6).
- Contract features: manifest + result-envelope schemas; artifact location; timeout block.

### Skill contract requirements
- `skill_id` `ref.echo`, `name` "Reference Echo Skill", `version` `0.1.0`, `determinism` `deterministic`,
  `parallel_safe` true, `batch` false, `streaming` false.
- `result` shape `{ echoed, message, repeat, host, user, pwsh_version, pid }`; `confidence` null
  (deterministic); `model_provenance` empty; artifact kind `text` (`echo.txt`).

### Inputs and outputs
- **Inputs:** `message` (string, default `ping`), `repeat` (int, default 1, must be >= 1).
- **Outputs:** result object above; artifact `echo.txt`; envelope also written to
  `runtime/artifacts/<invocation_id>/result.json`.

### Artifact structure
- `skills/ref.echo/runtime/artifacts/<invocation_id>/` -> `echo.txt`, `result.json`, `stderr.txt`.

### Proposed implementation
- **Language:** PowerShell 7 (per language policy: fastest correct MVP; the *contract*, not the
  language, provides modularity — D-0004). Validators live in a `.psm1` reused by wrapper and tests.
- Reference skill is self-contained (no import) so it stays independently runnable.

### External tools or models
- Only `pwsh` (already installed, registry-verified). No new installs.

### Installation steps
- None. Files are added under `modules/01-skill-bootstrap/`.

### Tests
- **Direct:** run `Invoke-RefEcho.ps1` in an isolated pwsh; assert stdout is a schema-valid envelope,
  `status:ok`, correct `echoed`, and the `echo.txt` artifact exists with a matching hash.
- **Through the executor:** submit a task package that runs the entrypoint (and one that runs the
  wrapper); assert the executor reports `completed` and `stdout.txt` holds a valid envelope / report.

### MVP acceptance criteria
- [ ] `ref.echo` manifest passes `Test-SkillManifest`.
- [ ] Direct run emits a `Test-SkillResultEnvelope`-valid envelope (`status:ok`).
- [ ] Same skill run **through the executor** completes and emits a valid envelope.
- [ ] Generic wrapper reports `manifest_valid` and `envelope_valid` true.
- [ ] `TOOL_MODEL_REGISTRY.md` has a `ref.echo` entry in the proven format.

### Manual verification procedure
- Submit both task packages to the running executor; read `runtime/completed/<id>/stdout.txt` and the
  skill's `runtime/artifacts/<id>/result.json`; confirm they match and validate.

### Documentation requirements
- Module `README.md`, skill `README.md`, `skill.json`, `examples/` (invocation + a real captured result).

### Registry updates
- Add `ref.echo` (status installed, location, invocation, last test) to `TOOL_MODEL_REGISTRY.md`.

### State updates
- Update `CURRENT_STATE.md` (Module 1 -> MVP complete, next action) and `MODULE_ROADMAP.md`.
- Record provisional conventions in `DECISION_LOG.md` (D-0009).

### Known follow-on work (future work orders / roadmap — NOT this session)
- Fold the adopted conventions (artifact-root resolution, `-InputsJson`, invocation_report schema)
  into `SKILL_CONTRACT.md` once a second skill confirms them (then bump the contract version).
- Promote `Invoke-Skill.ps1` / `SkillContract.psm1` to a shared `core/` location when Module 2 needs them.
- Machine-readable registry + task router (Module 24).

### STOP conditions
- Scope would exceed the "Explicit scope" list.
- A dependency is missing/broken and installing it is non-trivial.
- The contract lacks something the module needs (stop; propose the change; do not freelance).
- MVP acceptance is met — **stop; do not start Module 2.**
