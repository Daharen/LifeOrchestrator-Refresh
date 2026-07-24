# Project Proteus — Refresh

Clean, standalone home for the near-term **local skills** track. Deliberately separate and self-contained,
away from the legacy Proteus framework (which lives under `Project-Proteus-src` and is **not** used here).

## Layout
- **`core-docs/`** — the control plane. **Start at [`core-docs/START_HERE.md`](core-docs/START_HERE.md).**
- **`modules/`** — one number-prefixed folder per module (`00-bootstrap-executor/`, `01-...`), each
  self-contained: code + `skill.json` + `WORK_ORDER.md` + `README` + tests all in the one folder.

## Orientation (fresh Claude instances)
Read `core-docs/START_HERE.md` first — it routes you to everything else and names the active module.
Build **one module at a time**; MVP completion beats speculative architecture.

## Execution
`modules/00-bootstrap-executor/` is the Trusted High-Risk Bootstrap Executor — the local execution
channel. Run future executor instances from here. It is trust-based, **not** a sandbox (see
`core-docs/PROJECT_DIRECTION.md`).
