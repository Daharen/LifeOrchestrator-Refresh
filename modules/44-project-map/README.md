# module:44 project.map -- Project Comprehension Bootstrap (PCB) 0.1.0

Deterministic, fail-closed machinery that HARVESTS mechanical repo facts, VALIDATES the canonical
project map, idempotently INGESTS evidence-pointed agent claims, and RENDERS bounded
progressive-disclosure views (a BOOT_PACKET, an L0 system map, L1 capability cards, and an alias
index). It is the mechanism under the i47 legacy-vs-new bootstrap dry-run: agents provide judgment
only through versioned, evidence-pointed claims; the deterministic layer owns structure, identity,
validation, and rendering. Governing spec: `WORK_ORDER.md` (frozen; sha256
`439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725` over LF bytes) plus
`core-docs/research/2026-08-11-i46-pcb-design.md` and `design/redteam-rt1.md` (folded findings F1-F24).

## What it is

A stdlib-only Python 3.10-compatible worker (`project_map.py`) behind a pwsh 7.4.6 entrypoint
(`Invoke-ProjectMap.ps1`) that emits the SKILL_CONTRACT v0.2 result envelope. It is READ-ONLY over the
repo outside its own `map/`, `generated/`, `runtime/`, `fixtures/`. No model, no network, CPU-only.
`parallel_safe:false` (ingest/render write shared state).

- **Canonical state** lives in `map/`: per-namespace entity files (`entities/*.json`),
  `relationships.json`, and the orchestrator-authored `overlay/state.json`. Pinned JSON form:
  `json.dumps(obj, sort_keys=True, indent=1)` + `"\n"`, with every array explicitly sorted.
- **Provenance is per FIELD.** Every claimed field is backed by a source whose `fields` list names it;
  every source carries a CRLF->LF-normalized sha256 for path refs. Staleness is computed per field.
- **Derived, never authored:** `load_bearing` and `member-of` edges are computed at render time.
- **Fail-closed both ways:** a harvested unit with no entity (`HARVEST_ORPHAN`) and an entity whose
  path source no longer exists (`ENTITY_UNBACKED`) are hard errors -- the map cannot silently omit a
  new module, nor keep a stale ghost.

## Operations (`-Action`)

`harvest` mechanical facts -> `validate` the map fail-closed -> `ingest-claims` (idempotent staged-tree
atomic swap) -> `render` the bounded views -> `verify` (freshness sweep) -> `query` (closed set) ->
`reaffirm` (recorded "I checked, still true") -> `fmt --check` (canonical-form gate) -> `selftest`.

```
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action harvest  -Repo <repo> -Out runtime/harvest.json
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action validate -Map map -Harvest runtime/harvest.json
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action render   -Map map -Harvest runtime/harvest.json -Out generated
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action query    -Map map -Q entity:module:36/artifact.search
```

The worker is directly runnable too (the pinned progressive-disclosure query path, RT1-F21):

```
python3 project_map.py query --map map --q edges:module:40/context.compiler
python3 project_map.py query --map map --q deeper:doc:core-docs/AUDIT_PIPELINE.md:failure
python3 project_map.py verify  --map map --harvest runtime/harvest.json
```

A logical refusal is exit 0 + `status:"error"` + a machine `error.code` from the closed table (see
`SCHEMA_NOTES.md`). A non-zero exit means the process crashed without a valid envelope.

## Layout

```
skill.json  Invoke-ProjectMap.ps1  project_map.py  README.md  SCHEMA_NOTES.md  WORK_ORDER.md
schema/            documentation-form JSON Schemas (hand-rolled stdlib validation is the normative code)
map/               canonical state: entities/*.json  relationships.json  overlay/state.json
claims/            agent-submitted claims (a parallel lane owns this; the build lane NEVER writes here)
generated/         derived views -- ships EMPTY (+ .gitkeep); populated at FOLD only
fixtures/          golden mini-map + golden renders + the negative suite + fixture #0 + the generator
tests/             run_tests.py (the cloud suite), live_smoke.py, seed_map.py, Invoke-ProjectMapTests.ps1
runtime/           scratch + ALL --draft output (gitignored)
examples/          contract-required example invocation + result
```

## Tests

`pwsh -NoProfile -File tests/Invoke-ProjectMapTests.ps1` runs the cloud suite (golden byte-identity;
determinism = double-run + shuffle + CRLF/LF hash equivalence; the negative suite = one fixture per
error code, each failing with exactly that code; the drift gate; parse_budgets import parity; ingest
idempotence + interrupted-ingest safety; reaffirm/fmt/changed-since). Add `-Live` for the full-repo
smoke (`-RepoState Skeleton|Folded`). The logic lives in `tests/run_tests.py` so it runs identically on
the mount VM (3.10), the cloud, and the box (3.12).

`map/` is harvest-seeded skeleton state (every module/widget is `skeleton:true`, awaiting the claims
lane); `generated/` is intentionally empty until fold. Non-draft render refuses while any skeleton
remains (`SKELETON_UNRESOLVED`) -- by design.
