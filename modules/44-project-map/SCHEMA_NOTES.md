# project.map SCHEMA_NOTES -- `lifeorch.project_map/0.1`

The `schema/` JSON Schemas are documentation form; the normative validator is the hand-rolled stdlib
code in `project_map.py::validate` (WO s0/s3.2). This doc is the human-readable contract.

## Identifiers (WO s2.1)

`id = <ns>:<key>`, grammar `^[a-z]+:[A-Za-z0-9._/-]+$`, GLOBAL uniqueness, referential integrity on
every edge endpoint and pointer. Closed namespace enum:

| ns | key rule | example |
|---|---|---|
| module | `NN/slug` or `NN.N/slug`, slug = skill_id | `module:36/artifact.search`, `module:00.1/exec.watchdog` |
| widget | `NN/dir-slug` | `widget:08/live-run-audit-pathway` |
| plane | one of memory/intelligence/capability/authority/observability | `plane:authority` |
| arch | `NN` or `NN.N` -- NUMBER ONLY (RT1-F3); prose in display_name/aliases | `arch:43` |
| contract | kebab | `contract:context-packet` |
| doc | repo-relative path | `doc:core-docs/CURRENT_STATE.md` |
| store | kebab (persistent stores, RT1-F10) | `store:artifact-search-sqlite` |
| decision / mandate / pb / iteration / wave / ops / future | `D-####` / `NN` / `PB-N` / `iNN` / plan id / kebab / kebab | `decision:D-0080` |

`arch:44` (a spine position) and `module:44/project.map` (this module) are DIFFERENT entities and are
never conflated. `meta.json` holds thin stubs (id + one_line + sources) for decision/mandate/pb/
iteration/wave/future ids referenced by edges or the overlay.

## Entity record (WO s2.2)

Required: `id`, `ns`, `display_name`, `one_line` (<=160), `sources[]` (>=1). Source pinned shape
(RT1-F6): `{"ref","sha256"(hex64|null),"fields":[...],"by","at_commit"}`. `ref` is a repo path
(optionally `#anchor`) | `decision:D-####` | `contract:<name>` | an entity id; `sha256` is REQUIRED for
path refs (claims may submit null; ingest stamps it). Per-field provenance: each present coverable
field (one_line, plane_primary, planes_secondary, status, version, purpose, inputs, outputs,
determinism, parallel_safe, requirements, state_owned, authority_level, audit_surfaces, aliases,
authority_docs, deeper) must appear in some source's `fields` (or `["*"]`, harvest only), else
`FIELD_UNCOVERED`; no sources at all is `MISSING_PROVENANCE`.

Conditional fields: `plane_primary` (required for module/widget/ops unless `skeleton:true`) +
`planes_secondary[]`; `status` enum {proposed, ready, in-progress, blocked, mvp-complete, active,
design-only, frozen, deferred, deprecated, replaced}; the harvested mechanical fields (version,
purpose, determinism, parallel_safe, inputs, outputs, requirements) -- a map value disagreeing with
harvest is `CONFLICT_HARVEST`; the directive-6.2 claim fields (state_owned[], authority_level,
audit_surfaces[]); `aliases[]`; `authority_docs[]` (doc:/contract: ids); `deeper[]` = ordered typed
`{"kind","ref"}` with kind in {readme, work-order, schema-notes, contract, decision, failure, research,
test, trace, other} (RT1-F22); `confidence` {established|uncertain} (uncertain REQUIRES `note`);
`skeleton` (bool). **Derived, never authored (`DERIVED_FIELD_AUTHORED`):** `load_bearing` -- true iff
ns==contract OR plane_primary==authority OR referenced by an overlay prohibition/frontier OR
status in {active,in-progress} (RT1-F15); and `member-of` edges (derived from plane_primary +
planes_secondary at render).

## Relationships (WO s2.3)

`{from, type, to, sources[]}`. Closed types: produces, consumes, invokes, routes-to, retrieves-from,
compiles-for, verifies, authorizes, audits, persists, supersedes, depends-on, governs, realizes,
documents. `member-of` is DERIVED (authoring it is `DERIVED_FIELD_AUTHORED`). `realizes` = module:/
widget: -> arch:; `persists`/`retrieves-from` -> store:; `governs` originates at contract:/doc:.
Duplicate `(from,type,to)` within one file is `DUP_EDGE` (across ingest runs it is an idempotent
no-op, RT1-F7). >15 outbound edges of one type is an envelope WARNING, not an error.

## Overlay (`lifeorch.map_overlay/0.1`, WO s2.4)

Orchestrator-authored each close. The mandate cross-check is INVARIANT-FIELDS ONLY (RT1-F2): mandate_id,
sunset_iteration, and state monotonicity (ACTIVE->REPORT_DUE->SUNSET), plus header.current_iteration >=
overlay.iteration -- NO equality check on countdown fields, so the next session's countdown update
cannot brick the map (`OVERLAY_MANDATE_DRIFT`). Prohibitions are non-empty while any freeze is live
(`OVERLAY_PROHIBITIONS_EMPTY`); each authority is a `decision:` stub; a live prohibition whose authority
decision has an inbound `supersedes` edge, or any unresolved pointer, is `OVERLAY_DANGLING`. Overlay
text fields are pointer captions; the frontier summary is a VERBATIM handoff-s4 extract.

## Claims (`lifeorch.map_claims/0.1`, WO s2.5)

`{"schema","by","at_commit","entities":[...],"relationships":[...]}` -- both arrays (RT1-F6). Every
claimed field covered by >=1 source naming it; a claim restating a harvestable fact is
`CLAIM_RESTATES_HARVEST`; unknowns must be `confidence:"uncertain"` + note; claims may not set derived
fields. Ingest is idempotent: per-field replace only when the incoming `by` matches the field's recorded
claimant, else `CONFLICT_CLAIMS` unless `--override <reason>` (recorded). Ingest validates the STAGED
tree and atomic-swaps; any error merges nothing. `fixtures/example-claims.json` is the normative
fixture #0 a conforming validator accepts byte-verbatim.

## Canonical bytes & hashing (WO s0)

LF, UTF-8, no BOM, trailing newline, ASCII-only sources. `map/`+`claims/` = indent=1 sorted; `runtime/`
harvest + query output = compact. Every array is explicitly sorted by a stated key (entities by id;
edges by (from,type,to); sources by (ref,by,fields)); FS enumeration order never leaks (shuffle-tested).
Every content sha256 is over CRLF->LF-normalized bytes. KB = 1000. `parse_budgets()` is IMPORTED from
`ops/audit/gen-doc-health.py` (importlib path-load; re-implementation forbidden, RT1-F24).

## Closed error-code table (WO s3.9)

`SCHEMA_INVALID ID_GRAMMAR UNKNOWN_NS UNKNOWN_EDGE_TYPE DUP_ID DUP_EDGE DANGLING_REF MISSING_PROVENANCE
FIELD_UNCOVERED CLAIM_RESTATES_HARVEST CONFLICT_HARVEST CONFLICT_CLAIMS DERIVED_FIELD_AUTHORED
HARVEST_ORPHAN ENTITY_UNBACKED STALE_LOAD_BEARING STALE_BUDGET OVERLAY_MANDATE_DRIFT
OVERLAY_PROHIBITIONS_EMPTY OVERLAY_DANGLING SKELETON_UNRESOLVED SKELETON_LOAD_BEARING DIRTY_TREE
DRAFT_RENDER PACKET_OVER_BUDGET GENERATED_DRIFT FMT_NONCANONICAL UNSUPPORTED_QUERY PARSE_ROW_FAILED`.
When several findings exist, `error.code` is the table-order-lowest; `result.findings` lists them all.

## Render (WO s3.4/s4)

Render REQUIRES harvest and runs full validate first, refusing on ANY error (RT1-F12). Non-draft render
also refuses `DIRTY_TREE` (harvest dirty, computed excluding modules/44 itself), `SKELETON_UNRESOLVED`
(any skeleton remains), and `PACKET_OVER_BUDGET` (BOOT_PACKET > 20000 bytes HARD after the ladder). The
BOOT_PACKET has per-section budgets and a recorded degradation ladder (one_line 96->72->56, then
collapse mvp-complete widgets to counts) and `?`/`~` uncertainty/stale markers (RT1-F16/F23). `--draft`
is permitted ONLY under `runtime/`; it stamps a DRAFT-STALE banner in every file and returns
`DRAFT_RENDER` (RT1-F13). `render --check` byte-compares a fresh render against the committed tree
(`GENERATED_DRIFT`; a DRAFT-STALE banner under a generated tree fails it too).

## Query set (closed, WO s3.6)

`entity:<id>` | `edges:<id>` | `redges:<id>` | `evidence:<id>` | `deeper:<id>[:kind]` | `stale` |
`alias:<text>` | `changed-since --paths-file <f>` (the caller precomputes the changed-path list with
`git diff --name-only <sha>`, keeping git out of the worker, RT1-F21). Anything else is
`UNSUPPORTED_QUERY`.
