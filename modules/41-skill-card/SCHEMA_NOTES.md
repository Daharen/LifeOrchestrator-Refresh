# skill.card -- SCHEMA_NOTES (Module 41, skill `skill.card` 0.1.0)

**Authority.** This file records EVERY schema/interface interpretation this PRODUCER makes of the frozen
`core-docs/MEMORY_CONTRACT.md` (D-0083, amended v0.1.1 by A1 / D-0085) and of directive section 9. The
D-0077 cross-module fold (skill.card #41 -> artifact.search #36 0.2 `ingest_records`; surfaced in #40's
packets) depends on it. Governing: `MEMORY_CONTRACT.md` s1/s5/s7 + the directive
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` section 9 (skill activation) +
Priority 6/6.1; D-0080/D-0083/D-0085.

Worker: `skill_card.py` (Python **stdlib only**: `json`, `hashlib`, `re`, `os`, `sys`, `time`, `traceback`
-- NO third-party). Entrypoint: `Invoke-SkillCard.ps1` (pwsh-file). CPU-only, no model, no network.
`worker_version` = `0.1.0`; `schema_version` on every record = `lifeorch.skill_card.record/0.1`.

skill.card is a **PRODUCER**: it EMITS `skill` record-envelope artifacts conforming to `MEMORY_CONTRACT` s1
and VALIDATES them; it does **NOT** write the catalog DB (#36 owns storage). The orchestrator feeds the real
`ingest_records.json` into #36 0.2 `ingest_records` at fold and surfaces the cards in #40's packets.

---

## 1. Determinism contract (READ FIRST)

- **Canonical artifacts** (`cards.json`, `cards.jsonl`, `records.jsonl`, `records.json`,
  `ingest_records.json`, `index_manifest.json`, `card_warnings.json`, `summary.md`, plus `eligible.json` /
  `retrieval.json`) contain **NO absolute paths, NO timestamps, NO random / wall-clock ids**. Identical
  corpus **content** => **byte-identical** canonical artifacts across runs AND machines. Proven by the
  double-run byte-identity gate (off-machine + `-Live`).
- **All ids are content+path derived** (section 3). Same inputs => same ids + same order.
- **`created_by_ingest_run` is DETERMINISTIC** -- `"ingest_" + sha256(namespace "\0" + "\n".join(sorted
  "skilljson_rel\tskilljson_content_hash"))[:24]`. A function of the scanned `skill.json` corpus content
  ONLY, never wall-clock (mirrors #38 / #36's rule that run ids/timestamps never feed an id or a digest).
  Wall-clock run provenance lives ONLY in the skill result envelope.
- **`records_digest`** = `sha256` over sorted per-record lines
  `{record_kind}\t{record_id}\t{record_version_id}\t{content_hash}\t{source_path}\t{span.start}\t{span.end}`
  (mirrors #38 exactly). **`cards_digest`** = `sha256` over sorted `{skill_id}\t{sha256(canon(card))}\t{card_status}`.
- **Canonical JSON** = `json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",",":"))`.
- **Paths** are repo-relative, forward-slash; multi-root corpora prefix each rel path with the root basename.
  **Spans** are BYTE offsets over the raw `skill.json` bytes (EOL-faithful, same as #38/#36). Discovery,
  card fields, eligibility, and retrieval scoring are all order-stable (sorted by `skill_id` / a stable
  `tie_break_key`).

## 2. record_kind emitted (the s1 CLOSED enum, D-0085)

skill.card emits exactly ONE kind: **`skill`**. The validator ACCEPTS the whole frozen s1 enum
(`symbol|summary|decision|claim|episode|failure|procedure|skill|reminder|entity|relationship`) for
forward-compat and rejects `source_chunk` (reserved by #36's chunk pipeline). `chunker_fingerprint` is
ALWAYS `null` (a card is a TYPED record, not a chunk).

## 3. Id derivation (LOGICAL vs IMMUTABLE-REVISION identity, per s1) -- and the #38 BOUNDARY

`_h(x)` = `sha256(x.encode("utf-8")).hexdigest()`; `[:N]` = first N hex chars. `ns` = `namespace` (slugged).
`\0` = NUL joiner.

- **`record_id` (stable LOGICAL id):** `"sklcard_" + _h(ns "\0" skill_id)[:24]`.
- **`record_version_id` (IMMUTABLE revision):** `"rv_" + _h(record_id "\0" content_hash)[:24]`.
- **`content_hash`** = `_h(canon(payload))` where `payload` = the whole card (bounded, deterministic; it
  INCLUDES the card `text`). A changed manifest -> a changed card -> a new `content_hash` -> a new
  `record_version_id` (a fresh revision, NOT a `record_version_conflict` under #36's idempotency).
- **`source_version_id`** aligns to #36's document model: `doc_id="doc_"+_h(ns "\0" skilljson_rel)[:24]`;
  `source_version_id="ver_"+_h(doc_id "\0" skilljson_content_hash)[:24]`.

**THE #38 BOUNDARY (record it -- avoid an ingest collision; work-order requirement):** repo.intel #38 already
emits a STRUCTURAL `skill` record with `record_id = "skl_"+_h(ns "\0" skill_id)[:24]` and
`authority_level="canonical_source"` (a direct manifest parse). skill.card #41 emits the RICHER ACTIVATION
CARD -- purpose/when-to-use/one-example/completion-checks/failure-conditions/health/latency+resource class.
Three-way distinction so both land in the SAME namespace/db WITHOUT colliding:
1. **Distinct `record_id` namespace:** `"sklcard_"` (not `"skl_"`). The 24-hex suffix is the SAME
   `_h(ns "\0" skill_id)[:24]` as #38's (so the two records for one skill are trivially joinable), but the
   PREFIX differs -> distinct rows.
2. **Distinct `authority_level`:** `"derived"` (a derived activation view) vs #38's `"canonical_source"`
   (the authoritative structural manifest). A consumer choosing "the source of truth" prefers #38; one
   choosing "what to show the 9B for routing" prefers #41.
3. **Explicit cross-link:** every card carries a `child_edge` `describes_structural_skill` (external) whose
   `external_ref` is #38's recomputed `skl_...` id -- documents the relationship (resolves only when both
   producers share the namespace at fold; informative, not required to resolve).

## 4. The s1 envelope -- field-by-field (every record)

| s1 field | skill.card value / interpretation |
|---|---|
| `record_id` / `record_version_id` | section 3 (logical vs immutable-revision). |
| `record_kind` | `"skill"` (section 2). |
| `namespace` (a.k.a. `project_id`) | slugged corpus label (default `life-orchestrator`); isolation scope. |
| `content_hash` | `_h(canon(payload))` (the card). |
| `status` / `currentness` | `"current"` -- the single s5 STRING (D-0085); a producer never emits a stale reason (a CONSUMER assigns `source_stale`/... when a manifest/parser changes). NB: the CARD's own quality lives in `payload.card_status` (`ok|partial|degraded`) + `payload.version_health.health.status` -- a DOMAIN/body status, NOT the envelope `status` (s1 rule). |
| `authority_level` | `"derived"` (BOUNDARY vs #38 `canonical_source`, section 3). |
| `sensitivity_class` | `"repo_internal"` (section 7; single value now, present from day one). |
| `valid_from` / `valid_to` | `null` / `null` (a card has no temporal expiry). |
| `created_by_ingest_run` | the DETERMINISTIC content-derived ingest id (section 1). |
| `source_version_id` | section 3 (the `skill.json`'s immutable source version). |
| `source_path` | the `skill.json` repo-relative path (ADDED alongside the envelope; #36 hits also carry `source_path`). |
| `source_span` | `{start:0, end:<skill.json byte length>}` -- the whole manifest byte region (the PRIMARY derivation source), or `null` on a read failure (then `derivation_refs` carries provenance). |
| `derivation_refs` | the EXTRA sibling docs consulted, as `[{ref:<rel>, kind:"source_doc"}...]` (README/WORK_ORDER). NOT required to resolve to emitted records (they are source docs, not #41 records) -- the validator does not resolve them (only `relationship` records resolve derivation_refs, and #41 emits none). |
| `parser_fingerprint` | `"skill.card.manifest/0.1;json"` (the manifest parse). |
| `chunker_fingerprint` | **ALWAYS `null`** (typed record, not a chunk). |
| `extractor_fingerprint` | `"skill.card.cardgen/0.1;section9"` (the section-9 card derivation). |
| `schema_version` | `lifeorch.skill_card.record/0.1`. |
| `token_count` | whitespace-token count of the card `text` (the compact searchable surrogate). |
| `embedding_space_id` | `null` (nullable until embedded; skill.card does not embed -- s2). |
| `parent_edges` | `[{skill_of_module, external, external_ref:"modules/<NN>-name"}]` when the skill lives under a module dir, else `[]`. |
| `child_edges` | one `{has_operation, external, external_ref:"<skill_id>#op:<op>"}` per supported operation (ops are card FIELDS, not separate records -> external edges), PLUS the `describes_structural_skill` cross-link (section 3). |
| `payload` | the CARD (section 5) -- feeds `content_hash` + `token_count`; what a consumer renders. Consumers tolerate this extra field (SKILL_CONTRACT s3 unknown-field rule). |
| `text` | the compact card `text`, ADDED at the TOP LEVEL so #36 `records_fts` FTS-indexes the card (Stage-2 via the #36 retriever). Additive; NOT part of `content_hash` (the payload copy is). |

## 5. The SKILL CARD -- directive section-9 field mapping (the `payload`)

Every card carries all section-9 fields; a MISSING field is SURFACED in `payload.missing_fields` (never a
crash). Derivations from the `skill.json` manifest (+ sibling docs):

| directive s9 field | card field | derivation (deterministic) |
|---|---|---|
| purpose | `purpose` | `manifest.purpose`, bounded to 400 chars; fallback to the first non-heading README line if absent; else `missing_fields += purpose`. |
| supported operations | `operations` | leading tokens of an `op`/`mode`/`action`/`command` input's pipe/comma/newline-delimited enum; else `-Op a|b|c` in `invocation.args_spec`; else the single implicit `"invoke"`. |
| typed inputs | `inputs` | `manifest.inputs` -> `{name,type,required,default?,description(capped 140)}`, sorted (required first, then name), capped 40. |
| one valid example | `example` | synthesized deterministic command line: `pwsh -NoProfile -File <entrypoint> -InputsJson '{<required inputs + default op>}'` (or `python ...`); `missing_fields += example` if no entrypoint. |
| preconditions | `preconditions` | `requirements` executables/models/libraries + gpu (when required) + network + filesystem; `"none declared"` if empty. |
| side effects | `side_effects` (+ `side_effect_kinds`) | derived from `requirements`: `filesystem_write` (filesystem write/read-write), `network`, `screen_capture`, `audio_capture`, `camera_capture`; `"none (read-only / pure)"` if empty. **`side_effect_kinds` drives Stage-1** (section 6). |
| artifacts | `artifacts` | `manifest.outputs.description` (capped) + `manifest.artifacts.root`. |
| latency / resource class | `latency_class` / `resource_class` | latency from `timeout.default_seconds` (<=30 fast, <=120 medium, <=600 slow, else very_slow); resource `gpu` when gpu required, else `heavy_cpu` (memory_mb>=2048) / `cpu_light`. |
| deterministic completion checks | `completion_checks` | `envelope.status in {ok,partial}` + result-shape match + `artifacts[] sha256` + (deterministic) re-run identity. |
| common failure / refusal conditions | `failure_conditions` | dependency unavailable / GPU OOM / missing required inputs / network unavailable / timeout / invalid-inputs->status:error. |
| version + health status | `version_health` | `{version, contract_version, determinism, health{status, reasons}}`. Health = `ok` (complete manifest), `partial` (>=1 missing section-9 field), `degraded` (malformed/unparseable manifest). |

Also on the card (for Stage 1 + join): `skill_id, name, version, determinism, parallel_safe, domain`
(the dotted skill_id prefix), `module`, `gpu_required`, `network_required`, `required_executables`,
`required_models`, `os` (default `any`), `card_status`, `missing_fields`, `source_path`, `text`.

**Malformed / partial manifests (NEVER crash -- acceptance):** invalid JSON / missing `skill_id` -> a
DEGRADED card with `skill_id="unresolved:<rel_dir>"` (a stable logical id so re-runs stay idempotent) +
`card_status="degraded"` + a `parse_failure {rel,reason,detail}` (reasons: `invalid_json`, `not_utf8`,
`missing_skill_id`, `oversize`, `read_error`) + a warning; the result envelope status becomes `partial`. A
valid manifest merely missing optional section-9 fields -> `card_status="partial"` with the gaps in
`missing_fields`. **Card size is bounded** (purpose 400, input desc 140, inputs 40, ops 40, example 600,
artifacts 300, list item 160, text 1600) -- the COMPACT model-facing view, not the full docs.

## 6. Stage 1 -- deterministic eligibility filtering (directive s9 Stage 1)

`do_eligible(cards, task)` returns `{eligible:[skill_id], excluded:[{skill_id,reasons[]}]}` (both sorted;
fully deterministic). Pure rules, no model. A task descriptor field is only enforced when present (an absent
field never excludes). Rules:

- **side-effect policy / permissions:** `allow_side_effects=false` excludes any card with non-empty
  `side_effect_kinds`; `forbidden_side_effects[]` excludes a card whose kinds intersect it; `permissions[]`
  excludes a card needing a kind not in the granted set. (TESTED: a forbidden side-effect excludes the
  side-effecting skills; a read-only skill stays eligible.)
- **dependencies:** `available_models[]` / `available_executables[]` (when provided) exclude a card whose
  `required_models` / `required_executables` are not in the available set; `unavailable_dependencies[]`
  excludes a card needing any of them. (TESTED: an unavailable model excludes the skill that needs it.)
- **gpu:** `gpu_available=false` excludes any `gpu_required` card. (TESTED.)
- **network:** `network_available=false` excludes any `network_required` card.
- **health:** `require_healthy=true` excludes cards whose `version_health.health.status != ok`;
  `exclude_degraded=true` excludes `card_status=="degraded"` cards. (TESTED.)
- **os:** `task.os` excludes a card whose `os` is neither `any` nor the task os (cards default `os="any"`;
  manifests do not declare OS today -> the rule exists but rarely fires).
- **parallel safety:** `require_parallel_safe=true` excludes `parallel_safe=false` cards.
- **domain (coarse):** `required_domains[]` keeps only cards whose `domain` matches (task_type is otherwise a
  Stage-3 classifier concern -- NON-goal here).

## 7. Stage 2 -- semantic-retrieval SEAM + lexical baseline (directive s9 Stage 2)

`do_retrieve(cards, query, k, task?)` -> a ranked hit array in DETERMINISTIC order (consumer treats
`rank=index+1`, never re-sorts). If a `task` is supplied the pool is Stage-1 pre-filtered first (composition).

- **Lexical scoring (deterministic baseline):** query tokenized (lowercase, `[a-z0-9]+`, drop 1-char +
  stopwords). Per query token, `score += weight * min(tf, 3)` over WEIGHTED card fields:
  `skill_id_tokens`(5), `name`(4), `purpose`(3), `operations`(2), `input_names`(1), `aux`
  (failure/precondition/side-effect)(1), `text`(1). A card scoring 0 is NOT returned (irrelevant EXCLUDED).
  Deterministic order `(-score, skill_id)`; `tie_break_key = skill_id`. (TESTED bidirectionally: an OCR-intent
  query ranks the OCR skill first and EXCLUDES the lease skill; a lease-intent query ranks the lease skill
  first and EXCLUDES OCR; an unrelated query returns nothing -- a test that FAILS if an irrelevant skill
  surfaces.)
- **The SEMANTIC SEAM (`result.seam`):** defines the semantic query shape
  `{query_text, task_type?, k, embedding_space_id, filters:{record_kind:"skill"}, candidate_kinds:
  [skill,procedure,episode,failure]}` and the exact **#36 `search`** call
  `{op:"search", query, k, mode:"fts", filters:{record_kind:"skill", namespace}}` that real embeddings +
  #36 hybrid retrieval fold into at the retrieval wave (#37 0.2). Records carry a top-level `text` so #36
  `records_fts` indexes them today; the fused hybrid rank replaces `lexical_score` once vectors participate.

## 8. `ingest_records` drop-in (the D-0077 fold seam) -- I PRODUCE; #36 0.2 CONSUMES

- The primary artifact `records.jsonl` = one canonical s1 record per line, deterministic global order
  (kind, then `source_path`, then `record_id`). `ingest_records.json` =
  `{ schema:"lifeorch.skill_card.ingest_records/0.1", namespace, created_by_ingest_run, producer:"skill.card",
  producer_version, record_count, records:[<s1 record>...] }`.
- **Shaped to #36 0.2 `ingest_records`** (SCHEMA_NOTES #36 s4): each record has `record_id`,
  `record_version_id`, `record_kind` (=`skill`, in the typed enum, NOT `source_chunk`), BOTH `text` (FTS)
  AND `content_hash`, s1 provenance + fingerprints, and `edges` via `parent_edges`/`child_edges`
  (materialized as first-class `record_edges` by #36). Idempotent: identical card -> identical
  `record_version_id` + `content_hash` (a re-ingest no-op); a changed card -> a NEW `record_version_id`
  (a fresh revision, never a `record_version_conflict`).
- **Divergences to reconcile at fold (record here):** (a) skill.card ADDS `source_path`, `payload`, and a
  top-level `text` to the s1 envelope (all additive; unknown-field-tolerant per SKILL_CONTRACT s3 -- #36
  reads `text` for FTS and stores `content_hash`; the extra `payload` is carried in `attrs`/ignored). (b)
  `status="current"` is the single producer value; the CONSUMER owns the s5 staleness transitions. (c) the
  card's `card_status`/`health` is a DOMAIN status in `payload`, distinct from the envelope `status`
  (per s1 rule). (d) `derivation_refs` are source-doc refs, not #41 record ids -> not resolved by the
  validator (only `relationship` records resolve them; #41 emits none). If #36 0.2 keys records on a field
  #41 derived differently, reconcile via `record_id`/`source_version_id` (both documented above).

## 9. Validator (s1 -- op `validate`, run inline on every `cards`)

`validate_records(records)` checks, per record: all s1 required fields present; `record_kind` in the frozen
enum (and NOT `source_chunk`); `content_hash == _h(canon(payload))`; `record_version_id ==
"rv_"+_h(record_id "\0" content_hash)[:24]` (id integrity -> a tampered record is REJECTED); `source_span`
is a `{start,end}` object with `start<=end` OR `derivation_refs` non-empty; every `parent_edges`/`child_edges`
target resolves to an emitted `record_id` OR is `external` with an `external_ref`; and the **#36 ingest
drop-in shape** (`text|content_hash` present). Returns `{ok, checked, errors[], ingest_shape_ok,
edge_summary}`. A non-empty `errors` is a defect (the acceptance gate requires `ok=true`).

## 10. Sensitivity + privacy (s7)

- `sensitivity_class="repo_internal"` on every record (single value now; present from day one).
- **No egress:** CPU-only, no model, no network -- nothing leaves the machine. skill.card only reads
  `skill.json` + sibling `README.md`/`WORK_ORDER.md` and emits its own analysis artifacts (it does NOT
  mutate the corpus or user data). Its OWN manifest declares `filesystem:"read"` accordingly -- artifact-dir
  emission is the contract-standard output, NOT a user-data side effect (so skill.card cards itself as a
  read-only skill, eligible under a forbid-side-effects task).
- **Discovery exclusions (TESTED):** the sorted walk prunes `.git`, `runtime`, `artifacts`, venvs, caches,
  `_to_delete`, and -- skill.card-specific -- `fixtures`, `tests`, `examples` (so nested fixture `skill.json`
  manifests are NOT mistaken for real corpus skills; the real `modules/` scan sees exactly the top-level
  `modules/<NN>-*/skill.json` set).

## 11. Non-goals (NOT built -- Priority 7 / other modules / later waves)

The task classifier (Stage 3), the 9B preflight (Stage 5), deterministic plan validation (Stage 6) --
Priority 7; the PROCEDURE schema/registry/promotion (Priority 6 procedure half -- a named follow-on); real
embeddings / semantic retrieval (the retrieval wave -- lexical baseline only); the catalog DB (#36 owns
storage -- EMIT records only); repo.intel's structural parsing (#38 -- consume the boundary, not the work);
the context compiler (#40); the reranker/eval (#37); any UI; strong-preflight integration. Does NOT touch
model modules / `models.json`.
