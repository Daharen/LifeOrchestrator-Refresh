# cold-reference/ (long-horizon Proteus — DO NOT load by default)

This directory holds the **distant** Proteus architecture. It is **cold context**: fresh Claude
instances must **not** read anything here during ordinary module work. Load a document from here only
when your active work order genuinely concerns that specific system, and say so in `CURRENT_STATE.md`.

`PROJECT_DIRECTION.md` already carries the one-paragraph summary of the long-term vision; that is all a
near-term session needs. The full material stays here to preserve continuity without burdening context.

## Expected contents (migrate the existing Proteus documents into these slots)
- `long-term-deterministic-architecture.md` — deterministic canonical collapse & replay.
- `canonicalization-and-similarity.md`
- `simulation-architecture.md`
- `projection-architecture.md`
- `design-intent-compilation.md`
- `historical-checkpoints/` — dated snapshots of prior direction.

> These files are **not** created by the control-plane bootstrap. Drop the existing long-horizon
> Proteus documents in here when migrating the project so the routing in `START_HERE.md` stays valid.
> Until then this directory is intentionally near-empty.
