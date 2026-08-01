# repo.intel -- SCHEMA_NOTES (Module 38, skill `repo.intel` 0.1.0)

**Authority.** This file records EVERY schema/interface interpretation this PRODUCER makes of the frozen
`core-docs/MEMORY_CONTRACT.md` (D-0083). The D-0077 cross-module fold (repo.intel #38 -> artifact.search
#36 0.2 `ingest_records`) depends on it. Governing: `MEMORY_CONTRACT.md` s1/s4/s5/s7/s9; the directive
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` s6.4/7.1/7.2/7.4; D-0080/D-0083.

Worker: `repo_intel.py` (Python **stdlib only**: `json`, `hashlib`, `re`, `ast`, `os` -- NO third-party).
Entrypoint: `Invoke-RepoIntel.ps1` (pwsh-file). CPU-only, no model, no network. `worker_version` = `0.1.0`;
`schema_version` on every record = `lifeorch.repo_intel.record/0.1` (= `RECORD_SCHEMA`).

repo.intel is a **PRODUCER**: it EMITS record-envelope artifacts conforming to MEMORY_CONTRACT s1 and
VALIDATES them; it does **NOT** write the catalog DB (#36 owns storage). The orchestrator feeds the real
`records.jsonl` / `ingest_records.json` into #36 0.2 `ingest_records` at fold.

---

## 1. Determinism contract (READ FIRST)

- **Canonical artifacts** (`records.jsonl`, `records.json`, `ingest_records.json`, `index_manifest.json`,
  `inventory.json`, `parse_failures.json`, `summary.md`) contain **NO absolute paths, NO timestamps, NO
  random / wall-clock ids**. Identical corpus **content** => **byte-identical** canonical artifacts across
  runs AND machines. Proven by the double-run byte-identity gate (both off-machine and `-Live`).
- **All ids are content+path derived** (section 3). Same inputs => same ids + same order.
- **`created_by_ingest_run` is DETERMINISTIC** -- `"ingest_" + sha256(namespace "\0" + "\n".join(sorted
  "rel_path\tcontent_hash"))[:24]`. It is a function of the corpus content ONLY, never wall-clock, so
  re-indexing identical content yields byte-identical records. Wall-clock run provenance (started/finished
  timestamps, host) lives ONLY in the skill result envelope, never in a record or an id (mirrors #36's rule
  that `run_id`/timestamps never feed an id or the digest).
- **`records_digest`** = `sha256` over sorted lines, one per record:
  `{record_kind}\t{record_id}\t{record_version_id}\t{content_hash}\t{source_path}\t{span.start}\t{span.end}`.
  Repo-relative paths + byte spans + content hashes only -> machine-independent for identical content.
- **Canonical JSON** = `json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",",":"))`.
- **Paths** are repo-relative, forward-slash. **Spans** are BYTE offsets over raw file bytes (EOL-faithful:
  a CRLF file and its LF copy are legitimately different content -> different hashes/spans, same as #36).
  Multi-root corpora prefix each rel path with the root's basename so paths never collide.

## 2. record_kinds emitted (the s1 enum subset)

`symbol` | `entity` | `relationship` | `skill` | `summary` (all five of the kinds s1 anticipates for repo
intelligence). NOT emitted (out of scope / other modules): `source_chunk` (#36 chunks; repo.intel emits
TYPED records, not chunks -- so `chunker_fingerprint` is ALWAYS `null`), `decision`/`claim`/`procedure`/
`reminder` (later waves), `episode`/`failure` (#39).

| kind | what | one per |
|---|---|---|
| `entity` | structural node: FILE, FOLDER, MODULE (`payload.entity_type`) | file / folder / `modules/<NN>-*` |
| `symbol` | code symbol DEF: pwsh function/class, python def/class/method (`payload.symbol_type`) | definition |
| `skill` | a `skill.json` manifest (skill_id, ops, inputs, determinism, requirements) | skill.json |
| `summary` | DETERMINISTIC structural summary: markdown section, file outline, folder index, json-config, text-file | section / file / folder |
| `relationship` | first-class dependency edge (see section 5) | edge |

## 3. Id derivation (normative -- LOGICAL vs IMMUTABLE-REVISION identity, per s1)

`_h(x)` = `sha256(x.encode("utf-8")).hexdigest()`; `[:N]` = first N hex chars (mirrors #36's `x[:24]`).
`ns` = `namespace` (slugged, machine-independent). `\0` = NUL joiner.

**`record_id` (stable LOGICAL identity -- survives content revisions; path/name-derived):**
- file entity: `"ent_file_" + _h(ns "\0file\0" rel)[:20]`
- folder entity: `"ent_dir_" + _h(ns "\0dir\0" rel)[:20]`
- module entity: `"ent_mod_" + _h(ns "\0module\0" module_rel)[:20]`
- symbol: `"sym_" + _h(ns "\0" rel "\0" qualified_name "\0" symbol_kind)[:24]`
- skill: `"skl_" + _h(ns "\0" skill_id)[:24]`
- markdown section summary: `"sum_sec_" + _h(ns "\0" rel "\0" section_path "\0" ordinal)[:20]`
- file outline / json-config / text-file summary: `"sum_file_" + _h(ns "\0" rel)[:20]`
- folder index summary: `"sum_dir_" + _h(ns "\0" rel)[:20]`
- relationship: `"rel_" + _h(ns "\0" rel_type "\0" from_key "\0" to_key)[:24]`

**`record_version_id` (IMMUTABLE revision identity -- changes when the record's content changes):**
`"rv_" + _h(record_id "\0" content_hash)[:24]`.

**`content_hash`** = `_h(canonical_json(payload))` -- the hash of the record's own canonical semantic
content (the `payload` object), NOT the whole source file. (The source FILE's byte hash is carried
separately as the file entity's `payload.content_hash` and feeds `source_version_id`.)

**`source_version_id`** (the immutable SOURCE version a record derives from) aligns to #36's derivation so
records slot into its document model: `doc_id = "doc_" + _h(ns "\0" rel)[:24]`;
`source_version_id = "ver_" + _h(doc_id "\0" file_content_hash)[:24]`. Records tied to one source file carry
it; cross-file `relationship` and folder/module `entity` records set it `null` and use `derivation_refs`.

The validator recomputes `content_hash` from `payload` and `record_version_id` from `record_id`+`content_hash`
-> id-integrity is a checked acceptance criterion (a tampered record is rejected).

## 4. The s1 envelope -- field-by-field interpretation (every record)

| s1 field | repo.intel value / interpretation |
|---|---|
| `record_id` / `record_version_id` | section 3 (logical vs immutable-revision). |
| `record_kind` | section 2 enum. |
| `namespace` (a.k.a. `project_id`) | the slugged corpus label (default `life-orchestrator`); isolation scope. |
| `content_hash` | `_h(canonical_json(payload))` (section 3). |
| `status` / `currentness` | `"current"` -- a freshly-produced record is current, NOT one of the s5 stale reasons (`source_stale`/`derivation_stale`/... are assigned by a CONSUMER when a source/parser/edge changes; a producer never emits a stale record). |
| `authority_level` | `"canonical_source"` -- the repo is the canonical source of truth (single value for Wave 2; the field is present from day one). |
| `sensitivity_class` | `"repo_internal"` (s7 single value now; present from day one). |
| `valid_from` / `valid_to` | `null` / `null` -- structural source-derived records have no temporal expiry. |
| `created_by_ingest_run` | the DETERMINISTIC content-derived ingest id (section 1). |
| `source_version_id` | section 3; `null` for cross-file relationship + folder/module entities (they use `derivation_refs`). |
| `source_path` | repo-relative provenance path (ADDED alongside the envelope; #36 hits also carry `source_path`). |
| `source_span` | ALWAYS an OBJECT `{start,end}` of BYTE offsets (the s3 canonical span form), or `null` when a record has no single source region (folder/module entity, cross-file relationship). Symbols/sections/skills always carry a byte span. |
| `derivation_refs` | parent-record ids a record derives from when it has no single byte span: folder/module entity -> its child record ids; relationship -> its `[from_id, to_id]` (in-corpus endpoints only). |
| `parser_fingerprint` | the per-type parser id+version+options (section 6); `null` for pure-relationship/summary records that used an extractor. |
| `chunker_fingerprint` | **ALWAYS `null`** -- repo.intel emits typed records, not chunks. |
| `extractor_fingerprint` | the relationship/summary extractor id+version (section 6); `null` for direct-parse records. |
| `schema_version` | `lifeorch.repo_intel.record/0.1`. |
| `token_count` | deterministic whitespace-token count of the record's `payload.text` (a compact searchable text surrogate). |
| `embedding_space_id` | `null` (nullable until embedded; repo.intel does not embed -- s2). |
| `parent_edges` / `child_edges` | first-class edge objects (section 5), NOT denormalized path fields. |
| `payload` | the record's kind-specific semantic content (ADDED; feeds `content_hash` + `token_count` + is what a consumer renders). Consumers tolerate this extra field (SKILL_CONTRACT s3 unknown-field rule). |

## 5. The edge model (first-class edges -- s1 `parent_edges`/`child_edges` + `relationship` records)

An **edge object** = `{ edge_type, external:bool, target_record_id | (external_ref when external) }`. Every
non-external `target_record_id` MUST resolve to an emitted record; every external edge carries an
`external_ref` (a declared out-of-corpus target). Edge-endpoint integrity is a validated acceptance criterion.

**Containment + definition edges** live on `parent_edges`/`child_edges` of the structural records:
- folder `contains_file` / `contains_folder` file/subfolder; file `contained_in` folder.
- file `defines` symbol; symbol `defined_in` file.
- file `has_section` markdown-section; section `section_of` file; file `has_outline`/`has_structure`/`has_summary`.
- file `declares_skill` skill; skill `declared_in` file.

**The dependency graph** is emitted as first-class `relationship` records (`payload.relationship_type`):
- `imports` -- file -> imported target. Resolved to an in-corpus file when possible (pwsh dot-source /
  `Import-Module` of a repo `.psm1`; deterministic path-join + unique-basename fallback), else `external:true`
  with the raw target as `external_ref` (e.g. python `import os`, `Import-Module Pester`). `payload.import_kind`
  in {`import`, `import_from`, `import_module`, `using_module`, `dot_source`}.
- `in_module` -- file -> its `modules/<NN>-*` module entity.
- `tests` -- a `modules/<NN>/tests/*` file -> its module entity.
- `skill_of_module` -- a skill record -> its module entity.
- `produces_schema` -- module -> a schema id its `skill.json` declares (generic wire schemas
  `lifeorch.skill.{manifest,result,invocation_report}/0.1` are excluded as non-signal); the schema id is an
  external edge ref.
- `consumes_schema` -- module -> a schema id referenced anywhere in its text that it does NOT itself produce.

**INTERPRETATION FOR THE FOLD:** relationship records carry `derivation_refs = [from_id, to_id]` for
in-corpus endpoints (so #36 can resolve provenance) and an external edge on `child_edges` for out-of-corpus
targets. A CONSUMER that wants only the property graph can read `record_kind == "relationship"`; one that
wants the containment tree can walk `parent_edges`/`child_edges`. Both representations are always present.

## 6. Parser + extractor fingerprints (s4 -- a version change invalidates derived records)

`parser_fingerprint` / `extractor_fingerprint` values (name;version;options):
- inventory (file entity): `repo.intel.inventory/0.1;sorted-walk;sha256`
- markdown: `repo.intel.md/0.1;atx-headings;fence-aware`
- powershell: `repo.intel.pwsh/0.1;regex;function+class+import+dotsource`
- python: `repo.intel.python/0.1;ast;def+class+import`
- skill.json: `repo.intel.skill-json/0.1;manifest`
- json config: `repo.intel.json-config/0.1;toplevel-keys`
- text/other: `repo.intel.text/0.1;lines`
- relationships extractor: `repo.intel.relationships/0.1;imports+module+test+schema`
- summary extractor: `repo.intel.summary/0.1;file-outline+folder-index`

**Parser strategies + their deterministic bounds (recorded honestly):**
- **Markdown** -- ATX headings `^#{1,6}\s+`, fence-aware (``` / ~~~ toggles suppress heading detection);
  `section_path` = ` > `-joined breadcrumb (a stack popped to the new level); a section span runs from the
  heading line start to the next same-or-higher heading (or EOF), byte-exact.
- **PowerShell** -- **regex** extraction of `function`/`filter`/`class` DEFS + `Import-Module`/`using module`/
  dot-source imports. A symbol's `source_span` is the **signature-line byte region** (from the def line start
  to the next line start), NOT the full brace body (full-body spans + reference resolution are the AST
  call-graph NON-GOAL). Deterministic; never crashes on malformed pwsh.
- **Python** -- the stdlib **`ast`** module: top-level + nested `FunctionDef`/`AsyncFunctionDef`/`ClassDef` ->
  symbols (methods qualified `Class.method`, `symbol_type` method); `Import`/`ImportFrom` -> imports. A
  symbol's `source_span` is the **line region** `[start-of-def-line, start-of-line-after-end)` (byte offsets
  from a line-start table -- robust across CPython versions, avoids `col_offset` encoding ambiguity). A
  `SyntaxError` is caught -> surfaced as a `python_syntax_error` parse failure (no symbols, never a crash).
- **skill.json** -- parsed as JSON -> a normalized `skill` record (skill_id, name, version, determinism,
  parallel_safe, method/entrypoint, input names, requirement flags, schema ids). Invalid JSON / missing
  `skill_id` -> parse failure.
- **JSON/config** -- top-level structural keys (sorted, capped) -> a `json_config` summary. Invalid JSON ->
  parse failure.
- **text/other** -- a minimal `text_file` summary (line + byte count). No semantic parse (non-goal).

## 7. Inventory, allowlist + exclusions (s7 -- TESTED, not just documented)

- **Allowlisted ROOTS only** -- never crawl the whole profile; default the repo `modules/` + `core-docs/`.
- Deterministic **sorted** walk (dirs + files). Repo-relative forward-slash paths; multi-root corpora prefix
  the root basename.
- **Excluded DIR segments** (default, configurable via `-ExcludeDirs`): `.git`, `runtime`, `artifacts`,
  `__pycache__`, `node_modules`, `.vs`, `.idea`, `bin`, `obj`, `.pytest_cache`, `_to_delete`, `venv`, `.venv`,
  `env`, `python_env`, `.mypy_cache`, `.ipynb_checkpoints`.
- **Excluded GLOBS** (default, configurable via `-ExcludeGlobs`): `*.db*`/`*.sqlite*` (DBs); model files
  `*.gguf,*.safetensors,*.onnx,*.pt,*.pth,*.ckpt,*.bin,*.pkl,*.npy,*.npz`; binaries `*.exe,*.dll,*.so,...`;
  media `*.png,*.jpg,*.mp4,*.wav,...`; archives `*.zip,*.gz,*.7z,*.tar,...`; `*.pdf`, `*.lock`. Excluded files
  are counted (`excluded_count`) and NEVER appear in the inventory. **Tested** (a `blob.bin` is excluded, not
  parsed).
- **Parse failures are SURFACED, never silently dropped** (a walked file that is binary=NUL, oversize
  `>5 MB`, non-UTF-8, or fails its type parser). The file ENTITY is still emitted (inventory stays complete);
  the failure is recorded in `parse_failures[{rel,reason,detail}]` + a warning + envelope `status=partial`.
  **Tested** (invalid json, python syntax error, non-utf8 text each surface distinctly).

## 8. `ingest_records` drop-in (the D-0077 fold seam) -- I PRODUCE; #36 0.2 CONSUMES

- The primary artifact `records.jsonl` = one canonical s1 record per line, deterministic global order
  (kind bucket `entity < skill < symbol < summary < relationship`, then `source_path`, then `span.start`,
  then `record_id`).
- `ingest_records.json` = `{ schema:"lifeorch.repo_intel.ingest_records/0.1", namespace,
  created_by_ingest_run, record_count, records:[<s1 record>...] }` -- the drop-in payload for #36 0.2
  `ingest_records`.
- **INTERPRETATION FOR THE FOLD:** #36 0.2 defines the exact `ingest_records` op signature (not yet built at
  the time of this ship). repo.intel builds strictly to **MEMORY_CONTRACT s1** (the frozen shared contract);
  the orchestrator reconciles any thin wrapping at fold (D-0077). Each record already carries #36-aligned
  `source_version_id`/`doc`-style derivation + repo-relative `source_path` + byte `source_span`, so a record
  maps onto #36's `documents`/`document_versions` model without loss. `chunker_fingerprint` is `null`
  (typed record, not a chunk) -- a records-ingest path must NOT assume the chunk envelope.
- **Divergence to reconcile at fold (record here):** (a) repo.intel adds `source_path` + `payload` to the s1
  envelope (both additive; unknown-field-tolerant per SKILL_CONTRACT s3). (b) `status="current"` is a single
  producer value; the CONSUMER owns the s5 staleness transitions. (c) if #36 0.2 keys records on a field
  repo.intel derived differently, reconcile via `record_id`/`source_version_id` (both documented above).

## 9. Validator (s1 -- op `validate`, and run inline on every `index`)

`validate_records(records)` checks, per record: all s1 required fields present; `record_kind` in the enum;
`content_hash == _h(canonical_json(payload))`; `record_version_id == "rv_"+_h(record_id "\0" content_hash)[:24]`
(id integrity); `source_span` is a `{start,end}` object with `start<=end` OR `derivation_refs` non-empty; every
`parent_edges`/`child_edges` target resolves to an emitted `record_id` OR is an `external` edge with an
`external_ref`; every `relationship` record's in-corpus `derivation_refs` resolve. Returns
`{ok, checked, errors[], edge_summary{total,resolved_internal,external}}`. `index` embeds this as
`result.validation`; a non-empty `errors` is a defect (the acceptance gate requires `ok=true`).

## 10. Non-goals (NOT built -- later waves / other modules)

AST call-graph / full reference resolution (symbol DEFS + imports only), LLM summaries, embeddings, the
catalog DB / storage (#36 owns it -- repo.intel EMITS artifacts only), episode/failure schema (#39), the
context compiler, any UI, git-history parsing (a named follow-on), continuous filesystem watching.
