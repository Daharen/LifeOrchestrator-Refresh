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

### OPERATIONS section -- boot-surface wave canon (i48 CD-1)

The BOOT_PACKET carries an **OPERATIONS (wave canon)** section rendered ONLY from validated map state
(never renderer prose), so a PCB-booted orchestrator answers wave mechanics without opening the legacy
handoff (D-0133 CD-1). **Selection rule (naming convention):** an `ops:` entity renders into OPERATIONS
iff its key starts with **`boot-`** (e.g. `ops:boot-wave-clamps`); members are sorted by id. Each rendered
line is `- <one_line> [<repo-path pointer(s)>]` and is **pointer-backed with >=1 repo-path ref** (drawn
from the entity's `sources[]`) so the reader can descend. The canon set (authored in
`claims/i48-ops-canon-claims.json`): wave clamps (`<=1` GPU HARD; MaxParallel 3; workers `docs:[]`; only
the GPU lane edits models.json), lease order (`gpu -> git -> doc`), fail-closed `dev.ship` + native-git
HEAD verify + never `git add -A`, detached-server 0-orphan discipline, and the D-0077 fold-smoke rule.
**Budget + ladder position:** OPERATIONS has its own soft section budget (`SECTION_BUDGETS["ops"]`) and
fits itself 0->1->2 within it; against the 20,000-byte HARD packet total it is the **LAST** section the
total-guard ladder degrades -- section 3 (SYSTEM AT A GLANCE) hard-degrades first, and only then does
OPERATIONS compress to level 1, then to its **min floor** (level 2 = one collapsed pointer line that
still names each canon slug and one descent pointer). Boot-critical canon compresses but never vanishes.

## Query set (closed, WO s3.6; i49 adds `section` + `entity --fields`; i52 extends `section` + adds `card`)

`entity:<id>` | `edges:<id>` | `redges:<id>` | `evidence:<id>` | `deeper:<id>[:kind]` |
`section:<id>#<heading>` (i52: also `section:doc:<path>#<sel>` and `section:<id>:<kind>#<sel>`) |
`card:<id>` | `stale` | `alias:<text>` | `changed-since --paths-file <f>` (the caller
precomputes the changed-path list with `git diff --name-only <sha>`, keeping git out of the worker,
RT1-F21). Anything else is `UNSUPPORTED_QUERY`. The closed verb set is a SINGLE machine-readable
declaration (`QUERY_VERBS`) that BOTH gates the dispatcher AND renders the BOOT_PACKET RETRIEVAL
PROTOCOL table (N3, test-asserted equal -- an agent never needs `project_map.py` to learn the verbs).

### Short-form / alias id resolution (i48 CD-3)

Every id-taking query (`entity:` / `edges:` / `redges:` / `evidence:` / `deeper:`) resolves a raw id
argument to a canonical entity id before use. **A full canonical id already in the map resolves to
itself and is byte-identical to 0.1.0 (no extra keys added).** Short forms:

- **`ns:NN` / `ns:NN.N`** (e.g. `module:42`, `widget:08`) -> the UNIQUE entity in that ns whose number
  token (the key before `/`, or the whole key for `arch:`) equals `NN`.
- **`#NN`** -> the unique `module:` with number `NN`; **`pos NN`** -> the unique `arch:` position `NN`;
  a literal `aliases[]` value -> its unique holder.

Resolution is deterministic; **an ambiguous or absent short form is unresolvable**. Unresolvable ids
raise the **EXISTING `DANGLING_REF`** on `entity:`/`evidence:`/`deeper:` (as in 0.1.0) and now also on
short-form `edges:`/`redges:` (a short form is a lookup, not a filter). A **full-id-shaped miss**
(e.g. `edges:module:99/ghost`, no such entity) keeps the 0.1.0 empty-set behavior on `edges:`/`redges:`
(byte-identical). The closed query set gains **no new query names** and the error table gains **no new
codes**. When (and only when) a short form was resolved, the result echoes `"resolved":"<canonical>"`
so a reader sees which entity a bare number mapped to (this is why B's `edges:module:42|30|37` no longer
silently return `[]`); `edges:` remains OUTBOUND-only, so a resolved id with no outbound edges returns an
(honest) empty set identical to its full-id form -- inbound connectivity is `redges:`.

### Provenance-at-SHA hygiene on `evidence:` (i48 CD-3)

`evidence:<id>` **without** `--harvest` is byte-identical to 0.1.0 (the raw `sources[]`). **With**
`--harvest`, each source is annotated with a `_provenance` object -- `{ref_class, in_harvest_tree,
at_commit_matches_harvest, provenance}` -- computed from **harvest facts alone (no git calls, RT1-F21):**
a `path`/`doc:` ref is *in-tree* iff present in the harvest `inventory` (or core-doc list); a
`decision:D-####` ref iff its id is in harvest `decision_ids`; a `contract:`/entity `map-ref` is marked
`map-internal`. A ref that fails to resolve in the harvested tree is marked **`beyond-tree`**, and a
source whose `at_commit` differs from the harvest commit sets `at_commit_matches_harvest:false` -- the
two signals that made B distrust the map (a research file + `decision:D-0130` + an at_commit not in the
tree). The result also carries `beyond_tree_count`, `at_commit_drift_count`, and a **`currency`** block
stating BOTH commits: `{map_state_commit (overlay.at_commit), harvest_commit, in_sync}`. Every currency
surface states both commits -- the BOOT_PACKET freshness line reads `@ tree <sha> | map-state <sha>
[in-sync|MAP-VS-TREE-SPLIT]`.

### Mandate absence -- harvest tolerates a sunset-deleted PROCESS_MANDATE.md (i48 orchestrator fix)

An ABSENT `core-docs/PROCESS_MANDATE.md` is a legitimate tree state, not a crash: a mandate SUNSET
deletes the live doc (D-0132 removed it at i47; the archived copy lives under `archive/mandates/`).
`_parse_mandate_header` now returns the EMPTY header `{}` when the file is absent (`harvest.mandate ==
{}` = *no live mandate on this tree*); 0.1.0 hard-read the file, so every post-i47 real-tree `harvest`
-- and therefore `validate`/`render`/the `-Live` smoke -- crashed (`FileNotFoundError`, exit 2).
Fail-closed cross-check added in `validate`: an overlay that still CLAIMS a mandate
(`overlay.mandate` present) against an empty header fires the existing **`OVERLAY_MANDATE_DRIFT`**
("overlay claims mandate ... but the tree has no PROCESS_MANDATE header") -- a stale overlay may not
present a dead mandate as live. The post-sunset overlay simply OMITS `mandate` (the overlay schema keeps
it optional; `required` = schema/at_commit/iteration only). `live_freeze` detection (the
`OVERLAY_PROHIBITIONS_EMPTY` gate) falls back to frozen-ENTITY status when no mandate state exists, so
standing freezes (e.g. P0-1) still demand a non-empty prohibitions list. Error table unchanged (the
new trigger reuses `OVERLAY_MANDATE_DRIFT`); covered by the `mandate-absent` suite class (4 tests).

### L2 narrative surface -- purpose retrieval + SCHEMA_NOTES section fetch (i49 N1, D-0136/D-0137)

The load-bearing DEEP narrative (manifest `purpose`; SCHEMA_NOTES prose) is now reachable at query
granularity, so a thorough boot does bounded queries instead of grepping the raw harvest/store (F1).

- **`entity:<id> --fields <csv> --harvest <h>`** serves the named manifest field(s) FROM THE HARVEST
  (not the map), provenance-stamped with `field_provenance` = `{served_from:"harvest", harvest_commit,
  ref:"modules/<dir>/skill.json", sha256}`. Servable fields = the harvestable set (version, purpose,
  determinism, parallel_safe, inputs, outputs, requirements); any other field is `UNSUPPORTED_QUERY`.
  Each string field is BOUNDED to `FIELD_SERVE_MAX` (4800) bytes; when a value is longer the result
  carries `truncated:{<field>:true}` + `full_bytes:{<field>:N}` and the `ref` points at the full
  skill.json. This extends the EXISTING `entity:` verb (no new query name); `entity:<id>` WITHOUT
  `--fields` is byte-identical to 0.1.0. A `--fields` request without `--harvest` is
  `UNSUPPORTED_QUERY`; an unresolvable id is the EXISTING `DANGLING_REF`.
- **`section:<id>#<heading>`** (needs `--repo` + `--harvest`) fetches ONE named heading's section from
  the entity's SCHEMA_NOTES.md, repo-READ-ONLY (like harvest), CRLF->LF `sha256`-stamped. **Selector:**
  the exact heading text after the leading `#`s, whitespace-normalized (collapsed + stripped) on both
  sides, case-sensitive; the section spans that heading line to the next heading of the SAME-OR-
  SHALLOWER level (so nested sub-headings are included) or EOF. The body is BOUNDED to
  `SECTION_FETCH_MAX` (6600) bytes (`truncated:true` when clipped; the cap keeps the whole query
  OUTPUT envelope <= 8,000 B -- the i49 doc said "(8000)", a doc error corrected at i52; the CODE
  constant was 6600 at i49 and is unchanged). **Target resolution (N1(3)):** an
  authored `deeper[kind=schema-notes]` PATH pointer is preferred (the section fetch is that pointer's
  natural resolution); otherwise the target is `modules/<dir>/SCHEMA_NOTES.md` derived from harvest.
  **Refusals reuse the EXISTING closed codes:** an unresolved id, a module with no SCHEMA_NOTES, or a
  missing file all refuse `DANGLING_REF`; an unknown heading also refuses `DANGLING_REF` (the `#heading`
  ref does not resolve); a missing `--repo`/`--harvest` is `UNSUPPORTED_QUERY`. No new error codes.

### Overlay frontier richness (i49 N2)

The overlay `frontier.candidates[]` may carry OPTIONAL rich objects `{item, gate|status, pointer|ref}`
(all optional; the overlay stays orchestrator-authored at fold -- this module ships only the schema,
the render, and fixtures). The BOOT_PACKET **OVERLAY** section renders each rich candidate as
`- [<gate>] <item> -> <pointer>` at handoff-s4 usefulness (so task-scoping needs no legacy handoff,
F3). An overlay with NO rich candidates renders BYTE-IDENTICAL to 0.2.0. The frontier block self-fits
to the section-4 soft budget (levels 0=full, 1=trim, 2=one collapsed count+gates line) and has a
documented **total-guard ladder position: it degrades AFTER section 3 and BEFORE OPERATIONS** -- so
OPERATIONS still degrades LAST, and the packet stays <= 20,000 B HARD.

### Doc-section + card granularity (i52 N5, D-0142 F1)

The i51 gate showed the T1 answer living in PROSE governing docs (AUDIT_PIPELINE cadence header /
s5 / s6; the LRAP design digest; the w08 WORK_ORDER follow-ons) that the PCB served only as
whole-doc opens. N5 extends the EXISTING `section:` verb -- no new query names -- to three target
classes, and adds `card:<id>`:

**`section:` targets (resolution order per FORM, not guesswork):**

1. **Bare form on a non-doc entity** (`section:<id>#<sel>`): the i49 SCHEMA_NOTES resolution,
   **byte-identical** (deeper[schema-notes] pointer preferred, else harvested
   `modules/<dir>/SCHEMA_NOTES.md`). An ATX-matched result carries EXACTLY the 0.3.0 keys.
2. **Bare form on a `doc:` entity** (`section:doc:<repo-path>#<sel>`): the doc's OWN file -- the id
   key IS the repo path (core-docs AND mapped research docs). Result marks `target:"doc-entity"`.
3. **Deeper-pointer form** (`section:<id>:<kind>#<sel>`, mirrors `deeper:<id>[:kind]`): serves the
   file behind the entity's typed `deeper[]` pointer. **Closed serve kinds**
   `SECTION_SERVE_KINDS = readme|research|schema-notes|work-order`; any other deeper kind refuses
   `UNSUPPORTED_QUERY` (they are pointer classes, not servable files). When several pointers of the
   kind exist, the **lexicographically-first path ref** serves (deeper[] is canonically
   (kind,ref)-sorted, so this is the file order -- deterministic). Result marks
   `target:"deeper[<kind>]"`. Short forms compose (`section:widget:90:work-order#...`).

**Selector precedence:** the ATX exact-heading match runs FIRST (i49 semantics, unchanged). When NO
ATX heading matches, a **bold-label fallback** runs: a line-leading `**<bold text>**` paragraph
matches when the selector equals its LABEL = the bold text up to the first `(` or `:` (whitespace-
normalized, case-sensitive; the full bold text also matches); the block spans that line to the next
ATX heading of ANY level, the next bold-label line, or EOF; first match wins. This makes governing-
doc TOP blocks -- e.g. `section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header` -- query-servable
(the i51 T1 cluster's highest-value bytes are exactly such a block). A bold-label result carries
`selector:"bold-label"` + `level:0`; a fetch that matches neither refuses the existing
`DANGLING_REF`. All targets: repo-READ-ONLY, CRLF->LF sha-stamped, body bounded to
`SECTION_FETCH_MAX` with the head+tail clip marker.

**`card:<id>`** (needs `--harvest`; `--map` only, no repo reads) serves ONE rendered L1 card,
**content-matching the committed plane file by construction**: the plane `L1_CARDS_*` files and the
card query BOTH render through the single `_l1_card_lines()` source (test-asserted block-equal
against the golden plane file). Includes the STALE marker (hence `--harvest`); result carries
`{id, group, plane_file, harvest_commit, bytes, truncated, text}`; body bounded to `CARD_FETCH_MAX`
(5000). Short forms resolve with the `resolved` echo; an unknown id refuses `DANGLING_REF`; missing
`--harvest` refuses `UNSUPPORTED_QUERY`. An agent never opens a 31 KB plane file for one card.

### OPERATIONS canon extension + open_rulings render (i52 N6, D-0142 F3/K10)

`claims/i52-n6-canon-claims.json` (by `PCB-N5N6-i52`; ingested by the orchestrator at fold) extends
the boot canon with four `ops:boot-*` entities, each evidence-pointed at its owner doc: the
**D-0064 rule AT FULL STRENGTH** (ANY UI change needs a HUMAN live-GUI confirm BEFORE it is called
done -- no softening; the i51 B-arm relaxed this to "ship not blocked"), the **K5 doc budgets +
fail-closed commit gate** (DOC_PROTOCOL s2; `ops/audit/doc-commit-gate.py` REFUSES violating
core-doc commits), the **mandate-02 SUNSET state** (NO live process mandate; SEALED_CHECK_47 armed,
opens i>=54; the M2-A gate + PB triggers + cadence headers + monitor SURVIVE the sunset), and the
**NON-OPTIONAL red-team gate** for audit increments (design-first -> red-team-gated; A3+ mandatory;
D-0126 poser = the one recorded exception). The claims file also maps the LRAP design digest as a
`doc:` entity (unlocking its N5 section fetch) and adds the `decision:D-0064` meta stub.

**Render changes:** the OVERLAY section now renders **every `open_rulings[]` entry with its ref**
(`- <text> (<ref>)` under `OPEN RULINGS`) -- the K10 drop was a rider present in overlay/state.json
yet absent from the packet. Ladder position: like PROHIBITIONS, open rulings are NEVER
ladder-degraded; only frontier candidates trim inside section 4. `SECTION_BUDGETS["ops"]` rose
**2000 -> 3000** so all 9 canon one_lines render VERBATIM at level 0 (at 2000 the level-1 trim
would truncate canon at 96 chars and could cut the D-0064 phrasing); OPERATIONS keeps its
**degrades-LAST** total-guard position and the 20,000 B packet HARD cap is unchanged.

**Canon content tests (the i48 CD-1 pattern, extended):** every canon ops one_line is asserted
VERBATIM in the golden BOOT_PACKET (single-sourced from the claims file, so fixture and fold cannot
drift), plus named required sub-tokens AND a forbidden-token list; a negative test renders a
softened D-0064 phrasing ("ship not blocked...") and MUST FAIL the canon check. The fixture overlay
carries an open ruling so the rulings render path is golden-tested.

### RETRIEVAL PROTOCOL verb table (i49 N3)

BOOT_PACKET section 6 renders the FULL closed query set as an exact-invocation `| query form | returns |`
table from the single `QUERY_VERBS` tuple (every verb incl. `section`, the `entity --fields` serve, and
the `--harvest`/`--repo`/`--fields` modifiers, each with a one-line what-it-returns). The same tuple
gates `op_query`, so the packet's documented interface can never drift from the dispatcher (kills F4).

