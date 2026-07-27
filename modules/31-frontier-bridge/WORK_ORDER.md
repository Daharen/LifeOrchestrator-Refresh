# Work Order: Frontier Bridge (`frontier.bridge`)

**Contract version targeted:** 0.2 · **Author:** Claude C-frontier-bridge / 2026-07-27 · **Roadmap entry:** `MODULE_ROADMAP.md#31` (Phase B, D-0052)

### Problem being solved
The user wants frontier-model strength (his own flat-rate ChatGPT session) available for the occasional
hard reasoning task or second opinion, without spending Claude's Cowork tokens and without any software
touching an external AI service. No module assembles the local context for that hand-off.

### Immediate practical use
Claude writes a prompt + question and points `frontier.bridge` at the relevant repo files; the user
copies the emitted pack into his own ChatGPT, pastes the answer into the return file, and Claude reads
it back with `read-return`. A high-value, human-couriered escalation lane.

### Explicit scope (in)
- `pack` action: prompt + question + selected local files (paths/globs or a folder with include/exclude/recurse) → one copy-paste pack + a manifest + an empty return file.
- Size guards: `max_file_bytes` (skip `too_large`), `max_total_bytes` (skip `total_cap`), binary skip.
- `read-return` action: read the pasted answer back into the result envelope for Claude.
- `-InputsJson` generic channel + named params (named overrides JSON), per contract 3.1.

### Non-goals (out — do NOT build)
- **Any network / external-service access.** No submitting, scraping, or driving ChatGPT or any AI UI (the D-0051/D-0052 boundary). This is outbound local packaging only.
- Automatic clipboard control, browser automation, or "send" of any kind.
- Structured-format extraction, chunking/token-budgeting, or diffing — later work orders if earned.

### Dependencies
- Modules: Module 0 (executor, to run it) + Module 1 (wrapper, for the live gate). Tools/models: none. Contract features: `-InputsJson`, `-ArtifactRoot`, result envelope v0.2.

### Skill contract requirements
- `skill_id` `frontier.bridge`; `determinism` deterministic; `parallel_safe` true; `batch` false; `streaming` false.
- `result` shapes as in README; `confidence` null; `model_provenance` empty; artifact kinds markdown + json. Not a review producer.

### Inputs and outputs
- **Inputs:** action, prompt, question, paths[], folder, include[], exclude[], recurse, max_file_bytes, max_total_bytes, title, out_name, return_file (see `skill.json`).
- **Outputs:** pack `.md`, `manifest.json` (`lifeorch.frontier.pack_manifest/0.1`), `<out_name>.answer.md` return stub.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `<out_name>.md`, `manifest.json`, `<out_name>.answer.md`, `result.json`.

### Proposed implementation
- **Language:** PowerShell 7 over cross-platform .NET (per language policy: Windows filesystem glue; and the real skill gates unchanged on the cloud Linux box — no mock). Pure file I/O; UTF-8-no-BOM output; BOM-aware decode; ordinal-sorted deterministic file order.

### External tools or models
- None. `pwsh>=7.4` only (already in `TOOL_MODEL_REGISTRY.md`).

### Installation steps
- None beyond pwsh 7.

### Tests
- **Direct:** `tests/Test-FrontierBridge.ps1 -PwshPath <pwsh>` — 63 checks, asserts schema-valid envelope + behaviour + the no-network static assertion.
- **Through the executor / wrapper:** pass `-WrapperPath ..\01-skill-bootstrap\Invoke-Skill.ps1`; ship via `dev.ship` (sha + AST + this test).

### MVP acceptance criteria
- All 63 direct checks pass off-machine (cloud pwsh 7.4.6). ✅
- Envelope validates against `lifeorch.skill.result/0.1`; `determinism` stable; not a producer. ✅
- No network cmdlet anywhere in the entrypoint; `requirements.network=false`. ✅
- Live: passes through the Module 1 wrapper + `dev.ship` (sha + AST + tests) on the box.

### Manual verification procedure
- Run `pack` over a small folder; open the pack, confirm delimiters + manifest + local-only note; paste an answer into the return file; run `read-return` and confirm the content comes back.

### Registry / state updates (frontier step — not this worker)
- Add a `TOOL_MODEL_REGISTRY.md` entry; update `CURRENT_STATE.md` + `MODULE_ROADMAP.md#31`; log D-0052 build. **This worker reports to the orchestrator and does not touch core-docs** (the orchestrator mirrors them).

### Known follow-on work
- Token/char budgeting + chunked multi-pack; structured-format aware inclusion; a manifest of prior packs; optional redaction globs.

### STOP conditions
- Any temptation to add network/"send" behaviour → STOP (violates D-0052).
- MVP acceptance met → stop; do not start another module.
