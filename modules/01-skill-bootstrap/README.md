# Module 1 — Skill Contract & Registry Bootstrap (`skill.bootstrap`)

Establishes the smallest common tooling that makes independently-invokable local skills
real: contract **validators**, a reference **skill**, and a generic **invocation wrapper**.
It deliberately is **not** a plugin framework.

## What this module delivers
- `lib/SkillContract.psm1` — dependency-free validators `Test-SkillManifest` and
  `Test-SkillResultEnvelope` for `proteus.skill.manifest/0.1` and `proteus.skill.result/0.1`.
- `skills/ref.echo/` — the reference skill (`skill.json` + `Invoke-RefEcho.ps1` + examples).
- `Invoke-Skill.ps1` — the generic wrapper: **validate manifest -> run in an isolated pwsh
  process -> validate the result envelope**, emitting a `proteus.skill.invocation_report/0.1`.
- `tests/Invoke-SkillBootstrapTests.ps1` — regression tests (direct, wrapped, error path).

## How to run
```powershell
# Direct
pwsh -NoProfile -File .\skills\ref.echo\Invoke-RefEcho.ps1 -Message "hi" -Repeat 2

# Wrapped (manifest + envelope validated)
pwsh -NoProfile -File .\Invoke-Skill.ps1 -SkillDir .\skills\ref.echo -InputsJson '{"message":"hi","repeat":2}'

# Tests
pwsh -NoProfile -File .\tests\Invoke-SkillBootstrapTests.ps1
```
Through the Module 0 executor: submit a `task.ps1` that calls either entrypoint above;
read the envelope from `runtime/completed/<task_id>/stdout.txt`.

## Adding a new skill (the pattern this module proves)
1. Create `skills/<skill.id>/` with a `skill.json` (see `SKILL_CONTRACT.md`) and an entrypoint.
2. Entrypoint writes exactly one `proteus.skill.result/0.1` envelope to stdout; artifacts to
   `runtime/artifacts/<invocation_id>/`.
3. Validate with `Test-SkillManifest` / `Test-SkillResultEnvelope` (or run via `Invoke-Skill.ps1`).
4. Add a `TOOL_MODEL_REGISTRY.md` entry for the skill.

## Adopted conventions (candidates for the contract to absorb later)
- **Artifact root** resolves relative to the skill folder (`$PSScriptRoot`); the envelope
  always reports absolute artifact paths.
- **Generic argument passing**: a skill accepts `-InputsJson '<json object>'` so a generic
  wrapper need not know each skill's parameters. Named params may also be offered.
- **Wrapper report**: `proteus.skill.invocation_report/0.1` = `{ manifest_valid, manifest_errors,
  invoked, exit_code, envelope_valid, envelope_errors, envelope, stderr_tail }`.

These are recorded in `DECISION_LOG.md` (D-0009) as provisional, to be folded into the
contract once a second skill confirms them.
