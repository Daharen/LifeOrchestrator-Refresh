# ref.echo — Reference Echo Skill

The canonical worked example for the Proteus skill contract (v0.1) and a trivial
health-check for the skill channel. Given a `message` and a `repeat` count it echoes the
message back N times, writes an `echo.txt` artifact, and emits a schema-valid
`proteus.skill.result/0.1` envelope on stdout.

## Inputs
| name    | type   | required | default | notes                         |
|---------|--------|----------|---------|-------------------------------|
| message | string | no       | ping    | text to echo                  |
| repeat  | int    | no       | 1       | repeat count, must be >= 1     |

Pass inputs as named params (`-Message`, `-Repeat`) or via the generic `-InputsJson`
convention. `-ArtifactRoot` and `-InvocationId` are optional overrides.

## Output
`result` = `{ echoed, message, repeat, host, user, pwsh_version, pid }`.
Deterministic, so `confidence` is `null`. Artifacts: `echo.txt` (the echoed text).
`repeat < 1` produces a valid envelope with `status:"error"` (code `invalid_input`).

## Contract conventions demonstrated
- Single JSON envelope to **stdout**; diagnostics to **stderr** and `stderr.txt`.
- Artifacts under `runtime/artifacts/<invocation_id>/` (resolved relative to this skill
  folder via `$PSScriptRoot`); absolute paths reported in the envelope.
- `inputs_digest` = `sha256:` of the compact normalized inputs.
- Exit code `0` whenever a valid envelope is produced (even on logical `status:"error"`).

See `examples/` for invocation and result examples.
