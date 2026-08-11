# WORK_ORDER — modules/44-project-map (`project.map`) v0.1.0

**Unit:** BUILD the Project Comprehension Bootstrap (PCB) mechanism — deterministic construction, validation, and rendering of the Life Orchestrator system map, capability cards, and orchestrator boot packet. **Authority:** Nicholas's comprehension/bootstrap reconstruction directive (i46) + `core-docs/research/2026-08-11-i46-pcb-design.md` (the frozen decision record; red-team RT-1 findings F1-F24 are FOLDED into this spec). Build to THIS work order exactly; report the sha256 of the WORK_ORDER bytes you built against. **Non-goals:** replacing the legacy handoff (i46 builds ALONGSIDE it; directive 6.7); any #36 write path (FO-3); any model call; any core-doc edit (`docs:[]`).

## 0. Identity, constraints, determinism (HARD RULES)

- Skill id `project.map`, dir `modules/44-project-map/`, version 0.1.0. **Namespace note:** the module is `module:44/project.map`; architectural position 44 is the DIFFERENT entity `arch:44`. The map contains both, never conflated.
- Stdlib-only Python worker (`project_map.py`, **Python 3.10-compatible** — runs on the Linux mount VM's 3.10 AND the box's 3.12) + pwsh 7.4.6 entrypoint. No third-party deps, no network, no `datetime.now()`/randomness in any artifact byte. READ-ONLY over the repo outside its own `map/`, `generated/`, `runtime/`, `fixtures/`.
- **Envelope + exits (RT1-F4):** `Invoke-ProjectMap.ps1` emits the SKILL_CONTRACT v0.2 `lifeorch.skill.result/0.1` envelope on stdout (map payload under `result`; timestamps live ONLY in the envelope, which is excluded from byte-identity gates). A logical refusal (validation failure, stale refusal, unsupported query, draft) = **exit 0 with `status:"error"`** (or `"ok"` with warnings where stated) + a machine `error.code` from the published table (§3.9). Nonzero exit = crash/no-valid-envelope only. `parallel_safe:false` (ingest/render write shared state). `examples/` dir required per contract.
- **Canonical bytes:** LF, UTF-8, no BOM, trailing newline, ASCII-only source files. JSON forms PINNED (RT1-F17): `map/` + `claims/` files = `json.dumps(obj, sort_keys=True, indent=1)` + `"\n"`; `runtime/` harvest + query output = compact `separators=(',',':')`. **Every emitted array is explicitly sorted** by a stated key: entities by `id`; edges by `(from,type,to)`; sources by `(ref,by)`; all path lists lexicographic bytewise. Filesystem enumeration order must never leak (shuffle-fixture test §6).
- **Hashing (RT1-F5):** every `sha256` over file content is computed on **CRLF→LF-normalized bytes** (`data.replace(b"\r\n", b"\n")`). Normative everywhere (sources, MANIFESTs, drift checks). Negative fixture: CRLF and LF copies of one file MUST hash identical.
- **KB = 1000 bytes** everywhere (matches `parse_budgets()`; RT1-F16).
- **Git facts are INPUTS (RT1-F18):** the pwsh entrypoint captures `git rev-parse HEAD` + `git status --porcelain` and passes `--at-commit <sha> --dirty <true|false>` (dirty = any tracked change **outside `modules/44-project-map/`** — the module's own uncommitted outputs are expected at fold). The worker never shells to git, except: `changed-since` consumes a pre-computed `--paths-file` (see §3.7).

## 1. File layout (all new; nothing outside modules/44-project-map/)

```
modules/44-project-map/
  skill.json  Invoke-ProjectMap.ps1  project_map.py  README.md  WORK_ORDER.md  SCHEMA_NOTES.md
  examples/                       # contract-required example invocations
  schema/ (4 files)               # documentation-form JSON Schemas; hand-rolled stdlib validation is normative code
  map/                            # CANONICAL STATE (git-tracked): entities/{modules,widgets,planes,arch-positions,
                                  #   contracts,docs,ops,stores,meta}.json  relationships.json  overlay/state.json
  claims/                         # agent-submitted claims inputs (Lane B ships i46-repo-claims.json; Lane A NEVER writes here)
  generated/                      # DERIVED VIEWS -- ships EMPTY except .gitkeep (RT1-F13); populated at FOLD only:
                                  #   BOOT_PACKET.md L0_SYSTEM_MAP.md L1_CARDS_{modules,widgets,infra}.md ALIASES.md
  fixtures/                       # golden mini-map + rendered-golden outputs + the negative suite + example claims
  tests/Invoke-ProjectMapTests.ps1
  runtime/                        # scratch + ALL --draft output (gitignored)
```

## 2. Schema `lifeorch.project_map/0.1`

### 2.1 Identifiers

`id = <ns>:<key>`, grammar `^[a-z]+:[A-Za-z0-9._/-]+$`, GLOBAL uniqueness, closed ns enum:

| ns | key rule | example |
|---|---|---|
| module | `NN/slug` or `NN.N/slug`, slug = skill_id | `module:36/artifact.search`, `module:00.1/exec.watchdog` |
| widget | `NN/dir-slug` | `widget:08/live-run-audit-pathway` |
| plane | `memory intelligence capability authority observability` | `plane:authority` |
| arch | **`NN` or `NN.N` — number only (RT1-F3)**; prose name goes in display_name/aliases | `arch:43` |
| contract | kebab name | `contract:context-packet` |
| doc | repo-relative path | `doc:core-docs/CURRENT_STATE.md` |
| store | kebab name — persistent data stores (RT1-F10) | `store:artifact-search-sqlite`, `store:review-queue-jsonl` |
| decision | `D-####` | `decision:D-0080` |
| mandate / pb / iteration / wave | `NN` / `PB-N` / `iNN` / plan id | `mandate:02`, `pb:PB-4`, `iteration:i46` |
| ops | kebab slug | `ops:doc-commit-gate` |
| future | kebab slug (sparingly) | `future:real-time-autonomic-layer` |

`meta.json` holds thin stubs (id + one_line + sources) for decision/mandate/pb/iteration/wave/future ids referenced by edges/overlay — only those actually referenced; DECISION_LOG_INDEX stays the decision authority. Every edge endpoint and overlay pointer must resolve (referential integrity).

### 2.2 Entity record (`{"schema":"lifeorch.project_map/0.1","kind":"entities","items":[...]}`)

Fields: `id` `ns` `display_name` `one_line` (<=160 chars) — REQUIRED. `sources[]` — REQUIRED, >=1 item, **pinned single shape (RT1-F6):**

```json
{"ref": "modules/36-artifact-search/skill.json", "sha256": "<hex64|null>", "fields": ["version","purpose"], "by": "harvest_v1|lane-B-i46|orchestrator-i46", "at_commit": "<sha>"}
```

`ref` = repo path (optionally `#free-anchor-text`) | `decision:D-####` | `contract:<name>` | entity id. `sha256` REQUIRED for path refs (claims may submit `null`; **ingest computes and stamps it**); null/absent for non-path refs. `fields` = the entity fields THIS source supports (**per-field provenance, RT1-F8**); `["*"]` allowed only for harvest.
Conditional fields: `plane_primary` (required module/widget/ops unless `skeleton:true`) + `planes_secondary[]` — `member-of` edges are **DERIVED from these at render, never authored (RT1-F10)**; `status` (enum: proposed|ready|in-progress|blocked|mvp-complete|active|design-only|frozen|deferred|deprecated|replaced); `version`, `purpose`, `inputs[]`, `outputs[]`, `determinism`, `parallel_safe`, `requirements{}` — **harvested from skill.json where present (RT1-F10); purpose one_line seed = first sentence of manifest `purpose` (NOT `name`)**; `state_owned[]`, `authority_level` (free-short), `audit_surfaces[]` — claim fields (directive 6.2); `aliases[]`; `authority_docs[]` (doc:/contract: ids); `deeper[]` — ordered, **typed (RT1-F22):** `{"kind":"readme|work-order|schema-notes|contract|decision|failure|research|test|trace|other","ref":"<path-or-id>"}` (prefer `doc:` ids for core-docs); `confidence` (`established|uncertain`; uncertain REQUIRES `note`); `skeleton` (bool, harvest-seeded entities pending claims); `load_bearing` — **DERIVED, never authored (RT1-F15):** true iff ns==contract OR plane_primary==authority OR referenced by overlay prohibitions/frontier OR status in {active,in-progress}.

### 2.3 Relationships

`{from, type, to, sources[]}` (same source shape). Closed types: `produces consumes invokes routes-to retrieves-from compiles-for verifies authorizes audits persists supersedes depends-on governs realizes documents` (NOTE: `member-of` is derived, not authorable; `persists`/`retrieves-from` target `store:` ids). `realizes` = module:/widget: -> arch: only; `governs` = contract:/doc: -> any. Duplicate `(from,type,to)` WITHIN one file/claims submission = `DUP_EDGE`; across ingest runs = idempotent no-op (RT1-F7). Architectural graph only; validator WARNS (envelope warning, not error) over 15 outbound edges of one type per entity.

### 2.4 Overlay (`overlay/state.json`, `map_overlay/0.1`)

Orchestrator-authored each close. Fields: `schema`, `at_commit`, `iteration`, `phase {ref, text<=160}`, `frontier {next_iteration, summary<=300 — a VERBATIM extract of the handoff s4 frontier sentence(s), derivation recorded in `derived_from`, candidates:[{ref, text<=120}]}`, `mandate {id, sunset_iteration, state}` — **cross-check vs the parsed PROCESS_MANDATE header on the INVARIANT fields only: mandate_id, sunset_iteration, and state-monotonicity (ACTIVE->REPORT_DUE->SUNSET); require header current_iteration >= overlay.iteration. NO equality check on countdown fields (RT1-F2)**; `prohibitions[]` `{text<=160, authority: decision:<id>, status:"live"}` — non-empty while any freeze is live; each authority must be a decision: stub entity; ERROR if that decision has an inbound `supersedes` edge while status:"live" (RT1-F15); `open_rulings[]`, `boot_read[]` (typed pointers). Every pointer must resolve. Overlay text fields are POINTER CAPTIONS; owning prose stays in the owner docs during the experiment window.

### 2.5 Claims (`claims/*.json`, `map_claims/0.1`)

`{"schema":"lifeorch.map_claims/0.1","by":"lane-B-i46","at_commit":"<sha>","entities":[<partial entity records, each with "id" + claimed fields + sources[]>],"relationships":[<edge records>]}` — entities/relationships are ARRAYS (RT1-F6). Rules: every claimed field covered by >=1 source whose `fields` lists it; claims restating a harvestable fact = `CLAIM_RESTATES_HARVEST`; unknown => `confidence:"uncertain"` + note (never invent evidence); claims may NOT set derived fields (`load_bearing`, member-of edges). **Fixture #0 (normative example a conforming validator MUST accept byte-verbatim; ships in `fixtures/`):**

```json
{"schema":"lifeorch.map_claims/0.1","by":"example","at_commit":"0000000000000000000000000000000000000000",
 "entities":[{"id":"module:36/artifact.search","plane_primary":"memory","one_line":"SQLite+FTS5 typed-record memory substrate; Tier-1 hierarchy + fast-beam retrieval.",
   "sources":[{"ref":"modules/36-artifact-search/README.md","sha256":null,"fields":["plane_primary","one_line"],"by":"example","at_commit":"0000000000000000000000000000000000000000"}]}],
 "relationships":[{"from":"module:40/context.compiler","type":"retrieves-from","to":"store:artifact-search-sqlite",
   "sources":[{"ref":"decision:D-0100","sha256":null,"fields":["*"],"by":"example","at_commit":"0000000000000000000000000000000000000000"}]}]}
```

## 3. Operations (worker argv; envelope per §0)

1. **harvest** `--repo <root> --at-commit <sha> --dirty <bool> [--out runtime/harvest.json]` — mechanical facts: module dirs (NN + NN.N) + skill.json `skill_id`,`version`,`purpose` (first sentence),`inputs`,`outputs`,`determinism`,`parallel_safe`,`requirements` + presence flags (README/WORK_ORDER/SCHEMA_NOTES/tests/skill.json); widget dirs + presence flags; core-docs list + LF-normalized sizes + budgets via **importing `parse_budgets()` from `ops/audit/gen-doc-health.py`** (importlib path-load; re-implementation FORBIDDEN unless import is impossible on both platforms — then a fixture-table parity test is mandatory, RT1-F24); DOC_PROTOCOL s2 owner column (parse contract: the s2 table's `| doc | owns | budget |` rows; a row that fails to parse = HARD error, not a skip); DECISION_LOG_INDEX ids (`^\|\s*D-\d{4}`); PROCESS_MANDATE machine header; ARCHITECTURE_MAP positions — parse contract: spine lines `- **<num>` with optional backticked id; positions WITHOUT a backticked id get display_name from the heading prose; emit `arch:<num>` keys only (RT1-F3); git HEAD/dirty passthrough. Deterministic given identical tree bytes (sorted outputs; shuffle-tested).
2. **validate** `--map map/ --harvest <file> [--no-harvest]` — full rule set, ALL findings reported: schema/required/grammar/enums; global uniqueness; referential integrity (edges, overlay pointers, deeper refs, aliases); per-field provenance coverage; derived-field authorship ban; `CONFLICT_HARVEST` (map field != harvested value); `CONFLICT_CLAIMS`; **coverage (RT1-F9): `HARVEST_ORPHAN`** (harvested module/widget/core-doc/ops unit with no entity) **+ `ENTITY_UNBACKED`** (entity whose path sources/refs no longer exist) — both HARD errors; staleness per FIELD (recompute normalized sha256 per source; a mismatch marks that source's `fields` stale); **stale gating: any stale load-bearing FIELD = error; >20% of entities carrying any stale field = error (`STALE_BUDGET`, RT1-F20); else warnings**; overlay rules (§2.4); skeleton rules (`skeleton:true` exempts plane_primary ONLY; a skeleton item that is load-bearing-derived = error). `--no-harvest` = fixture tests only; running validate without harvest on the real map is itself an error.
3. **ingest-claims** `--claims <file> --map map/ --harvest <file>` — validate claims standalone -> cross-check -> **idempotent upsert** (entities keyed by id; per-field replace ONLY when the incoming `by` matches the field's recorded claimant, else `CONFLICT_CLAIMS` unless `--override <reason>` — recorded into the field's sources; edges keyed (from,type,to), re-ingest = no-op) -> stamp claim-source sha256s -> **stage to a temp tree, validate the STAGED tree, atomic swap (RT1-F7)**. Any error => nothing merged.
4. **render** `--map map/ --harvest <file> --out generated/ [--check] [--draft --out runtime/draft/]` — **requires harvest; runs full validate first; refuses on ANY error (RT1-F12)**. `--check`: re-render to temp, byte-compare vs committed generated/. `--draft`: permitted ONLY with an `--out` under `runtime/` (RT1-F13); stamps `DRAFT-STALE` banner in every file + `status:"error"`, `error.code:"DRAFT_RENDER"`. Non-draft render REFUSES if: `--dirty true` (`DIRTY_TREE`), any skeleton item remains (`SKELETON_UNRESOLVED`, RT1-F14), prohibitions empty while overlay lists none against live freezes (`OVERLAY_PROHIBITIONS_EMPTY`), stale rules (§3.2), or BOOT_PACKET over budget (`PACKET_OVER_BUDGET`).
5. **verify** `--map map/ --harvest <file>` — freshness sweep: per-field stale list + would-render-refuse verdict + coverage orphans.
6. **query** `--map map/ --q <expr>` — `entity:<id>` | `edges:<id>` | `redges:<id>` | `evidence:<id>` | `deeper:<id>[:kind]` | `stale` | `alias:<text>` | `changed-since --paths-file <f>` (maps a pre-computed changed-path list to touched entities via source/deeper refs; the CALLER produces the list with `git diff --name-only <sha>`, keeping git out of the worker, RT1-F21). Anything else: `error.code:"UNSUPPORTED_QUERY"`.
7. **reaffirm** `--map map/ --entity <id> --fields <csv> --by <who> --at-commit <sha>` (RT1-F8) — re-stamps the named fields' sources at current hashes, recording a reaffirm event into sources (`by`,`at_commit`); the machine-logged path for "I checked, still true". Refuses if the entity/field doesn't exist or the field is derived.
8. **fmt** `--check map/ claims/` — canonical-form verifier (byte-rewrites nothing with `--check`; exit envelope lists nonconforming files; RT1-F17). **selftest** — embedded quick suite printing `SELFTEST_*_OK`.
9. **Error-code table (normative, closed):** `SCHEMA_INVALID ID_GRAMMAR UNKNOWN_NS UNKNOWN_EDGE_TYPE DUP_ID DUP_EDGE DANGLING_REF MISSING_PROVENANCE FIELD_UNCOVERED CLAIM_RESTATES_HARVEST CONFLICT_HARVEST CONFLICT_CLAIMS DERIVED_FIELD_AUTHORED HARVEST_ORPHAN ENTITY_UNBACKED STALE_LOAD_BEARING STALE_BUDGET OVERLAY_MANDATE_DRIFT OVERLAY_PROHIBITIONS_EMPTY OVERLAY_DANGLING SKELETON_UNRESOLVED SKELETON_LOAD_BEARING DIRTY_TREE DRAFT_RENDER PACKET_OVER_BUDGET GENERATED_DRIFT FMT_NONCANONICAL UNSUPPORTED_QUERY PARSE_ROW_FAILED`.

## 4. Generated views

Header per file: `<!-- GENERATED by project.map render from map/ @ <at_commit> -- DO NOT EDIT; edit map/ + re-render -->` + freshness line (stale count MUST be 0 non-draft). A DRAFT-STALE banner in any `generated/` file = test FAILURE (RT1-F13).

- **BOOT_PACKET.md — <=20,000 bytes HARD (KB=1000), per-section budgets + degradation ladder (RT1-F16):** (1) identity/purpose + doctrine lines — RENDERED from `meta.json` doctrine entities WITH sources (never renderer literals) — <=2,500 B; (2) five planes + member counts <=800 B; (3) SYSTEM AT A GLANCE — every module/widget/ops entity grouped by plane_primary (an `UNPLACED` group renders if any lack one — belt to F14's braces), line form `id — one_line [status]` with one_line TRUNCATED at 96 chars (full text in L1 cards), `?` suffix on uncertain, `~` on any-field-stale (RT1-F23), deprecated|replaced collapsed to a count + L1 pointer — <=9,000 B; (4) OVERLAY verbatim (incl. MANDATORY prohibitions) <=3,000 B; (5) AUTHORITY TABLE (owner-doc rows from harvest + authority_docs) <=2,200 B; (6) RETRIEVAL PROTOCOL (progressive-disclosure rules; do-NOT-ingest-until-relevant; RECORD-every-open ledger duty; exact `python3 modules/44-project-map/project_map.py` query invocations + a `stale`/`verify` first-step; boot_read pointers) <=2,500 B. Ladder when section 3 would overflow: one_line truncation 96->72->56, then collapse `mvp-complete` widgets to counts — each ladder step recorded in the render envelope, never silent.
- **L0_SYSTEM_MAP.md** — full index incl. arch positions, module<->arch collision table, edge-count summaries, uncertainty/stale summary line ("N of M uncertain, K stale — query stale / L1 cards").
- **L1_CARDS_*.md** — one card per entity: id/aliases/planes/status/version/one_line/purpose/inputs/outputs/side-effects (determinism+parallel_safe+requirements)/state_owned/authority_level/audit_surfaces/key edges in+out/deeper (typed, ordered)/confidence+note/stale flags. Derived only.
- **ALIASES.md** — `#NN` / `pos NN` / dir-slug / skill-id -> canonical id.

## 5. skill.json + entrypoint

Manifest per SKILL_CONTRACT v0.2 mirroring #38's shape; `parallel_safe:false`; `side_effects:"writes only modules/44-project-map/{map,generated,runtime}"`; `examples/` populated. Entrypoint: `-Action` -> argv; captures git HEAD/porcelain (per §0); `$ErrorActionPreference='Stop'`; stdout = envelope only.

## 6. Tests (cloud FIRST, then -Live; every class below present + counted)

1. **Golden positive:** fixture mini-map (>=10 entities across >=5 ns incl. store:+arch:, >=12 edges, overlay, doctrine metas) -> validate OK, render OK into a temp out, byte-compare vs committed `fixtures/golden-generated/`.
2. **Determinism:** double-run byte-identity (harvest on a fixture tree; render golden) + **shuffle test** (same fixture content presented in permuted FS/input order -> byte-identical output; RT1-F17) + CRLF/LF hash-equivalence fixture (RT1-F5). -Live adds cloud-vs-box digest parity on golden render.
3. **Negative suite — one named fixture per error code** (>=22): every §3.9 code EXCEPT UNSUPPORTED_QUERY/DRAFT_RENDER exercised via a fixture that FAILS with exactly that code; plus UNSUPPORTED_QUERY + DRAFT_RENDER behavior checks; plus: claims file restating harvest; overlay prohibition whose authority decision carries an inbound supersedes edge; packet 20,001 bytes -> PACKET_OVER_BUDGET; render without --harvest refuses; --draft targeting generated/ refuses.
4. **Drift gate:** `render --check` green on golden; mutated-generated fixture FAILS `GENERATED_DRIFT`; any DRAFT-STALE banner under a generated tree FAILS.
5. **parse_budgets import parity:** synthetic fixture tables (missing rows, malformed cells, KB units) -> identical output to `gen-doc-health.py` parse on the same fixtures + hard error on unparseable owner rows (RT1-F24).
6. **Idempotence:** ingest same claims twice -> byte-identical map/; corrected-claims re-ingest (same `by`) -> field updated, no DUP_EDGE (RT1-F7). Interrupted-ingest simulation: staged-tree failure leaves map/ untouched.
7. **reaffirm/fmt/changed-since:** reaffirm restamps + refuses derived fields; fmt --check flags a noncanonical file; changed-since maps a fixture paths-file to the right entities.
8. **Full-repo smoke (-Live):** harvest real repo (counts sanity: >=45 module units incl. 00.1, 8 widgets, >=20 core-docs, arch 0-49); validate the committed skeleton map WITH harvest -> expected result per `-RepoState Skeleton|Folded` parameter (RT1-F11: the expectation is a test PARAMETER, not wall-clock guesswork). Assert 0 orphan processes.

## 7. Lane A build sequence + boundaries

1 skill.json+entrypoint+skeleton; 2 harvest(+parity); 3 validate(+negative suite); 4 ingest-claims(+idempotence); 5 render(+budget/drift/draft/ladder); 6 query+reaffirm+fmt+selftest; 7 **seed `map/` from harvest ONLY** (mechanical fields; `skeleton:true`; NO plane/one_line judgment beyond manifest-`purpose` first sentence as the seed one_line; planes/curated one_lines/edges/deeper = claims-lane work); commit `generated/` EMPTY (+.gitkeep); golden renders live under `fixtures/golden-generated/`; 8 README+SCHEMA_NOTES+examples; 9 gates: cloud suite -> -Live (`-RepoState Skeleton`) -> devship (named files; trailers; NOTHING under claims/).
**Do NOT:** write claims/; author the real overlay (fixture overlay lives in fixtures/ only); assign judgment fields; touch anything outside modules/44-project-map/. **Deviation from this spec without a written reason in your report = FAIL (honest INCOMPLETE beats false done, D-0107/D-0109).**

## 8. Lane A acceptance + report

Cloud suite green (per-class counts) -> -Live green (incl. full-repo smoke + digest parity) -> devship. REPORT: WORK_ORDER sha256 built against; counts by ns; negative-suite table (fixture -> code); determinism evidence (double-run + shuffle + CRLF digests); parse-parity result; envelope-conformance spot-check (one refusal envelope quoted); BOOT_PACKET golden byte size + ladder behavior; deviations with reasons; open items honestly flagged.

## 9. Fold (orchestrator-owned; the lane's boundary ends above)

Verify HEADs native-git -> independent suite re-run -> box `harvest` -> `ingest-claims` Lane B's file (conflicts resolved by orchestrator judgment via corrected claims re-ingest / recorded --override) -> author real `overlay/state.json` (frontier = verbatim handoff-s4 extract) -> full `validate` (0 errors; skeleton cleared) -> **all i46 core-doc close edits land FIRST -> re-harvest -> non-draft `render` -> budget/`--check`/double-run gates -> map+generated commit is the FINAL close commit (RT1-F11)** -> freeze `eval/` per the i47 packet (its own MANIFEST.sha256; eval/ is orchestrator-authored — NOT Lane A scope) -> D-entry + mirror + DOC_PROTOCOL owner rows for map//generated/ (RT1-F24).
