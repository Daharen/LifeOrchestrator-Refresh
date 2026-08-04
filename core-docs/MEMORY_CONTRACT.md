# MEMORY_CONTRACT -- the Collective Agent memory / retrieval contract (versioned)

Owns the **shared, versioned interfaces** every memory/retrieval producer and consumer builds to. This is the
ONE governing contract named for the D-0077 cross-module-smoke rule for every Wave 2+ memory producer/consumer
split (the analog of `SKILL_CONTRACT.md` for the memory substrate). Rationale lives in the red-team digest
`research/2026-08-01-frontier-memory-redteam.md` and the directive
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`; this doc is the normative distillate.

## 0. Status, versioning, scope

- **Contract set FROZEN 2026-08-01 (D-0083), for Wave 2 build.** Versions frozen here: retrieval-record +
  provenance envelope **v0.1** (new; amended to **v0.1.1** by D-0085, §0 A1); embedding-provider contract
  **0.2**; retriever contract **0.2**; plus normative catalog / evaluation / scale+privacy **gates**. FROZEN =
  normative for every Wave 2+ module and for the next revision of a Wave 1 module; it is NOT a redesign and it
  did NOT delay Wave 1 (which shipped at 0.1).
- **Amendment protocol.** Change a frozen field only via a new `DECISION_LOG` entry that bumps the affected
  contract version here, then re-verify each affected module (its `SCHEMA_NOTES.md` records the interpretation).
  Never silently edit a frozen field.
- **Amendment A1 -- record-envelope v0.1 -> v0.1.1 (D-0085, i28).** Resolves the two Wave-2 (i27) D-0077
  divergences the fold BRIDGED. (1) The envelope **`status`/`currentness` is a single STRING** from the §5 enum
  (`current` baseline) -- NOT a boolean and NOT an object; the `{state, stale_reasons, verified}` object form is
  RETIRED (§1, §5). (2) The `record_kind` enum is CLOSED; **`episode_stage` is NOT a kind** -- an episode's
  per-stage detail is STRUCTURAL (in the `episode` record `body` + `child_edges`), not a separate ingestable
  record (§1). Backward-compatible for every already-conformant module (#35/#36/#37/#38 built to the string
  status + closed enum); re-verify list = **{#39 episode.record -> 0.1.1}** (its `SCHEMA_NOTES.md` records the
  interpretation).
- **Amendment A2 -- provenance hash split + provenance modes (D-0087, i30).** Resolves the frontier Wave-3
  red-team P0-2 (the single `content_hash` was overloaded: chunk-text hash vs source-version hash, and derived
  records had no single span). The overloaded `content_hash` splits into DISTINCT provenance hashes:
  **`record_content_hash`** (this record's own canonical bytes), **`source_content_hash`** (the SOURCE FILE
  version bytes -- what s4 validation checks; the field an s3 hit called `content_hash`), and
  **`excerpt_hash`** (the cited span bytes), alongside the unchanged `record_version_id` / `source_version_id`.
  A **`provenance_mode`** enum -- `direct_span | derived_record | aggregate | tombstone` -- selects the
  validation rule (s1/s4). Backward-compatible aliasing: legacy `content_hash` reads as `source_content_hash`
  in an s3 hit / the chunk pipeline; `chunk_content_hash` reads as `excerpt_hash` for a `source_chunk`.
  Re-verify list = {#36 on its next revision; #40/#37/#41 adopt the names as they conform this wave}.
  Packet-side detail: `CONTEXT_PACKET_CONTRACT.md` s5.
- **Amendment A3 -- skill.card emits `summary`, not a second `skill` (D-0087, i30).** Resolves P0-5: #38
  repo.intel is the SOLE `record_kind = skill` producer (the structural manifest parse, `skl_`,
  `canonical_source`). skill.card #41 emits **`record_kind = summary`** with `attrs.summary_type =
  "skill_activation_card"` + a **`derives_from`** edge to #38's `skl_` record -- a navigational derivative
  that fits the CLOSED s1 enum -- so a `record_kind = skill` search returns ONE owner. The card payload +
  Stage-1/2 seams are unchanged; only the kind + the edge change. Re-verify list = {#41 -> summary (this wave)}.
- **Amendment A4 -- Tier-0 architectural-seam repairs (D-0092, i32).** Realizes the record/retriever half of the
  seam audit (`research/2026-08-03-memory-architecture-seam-audit.md` s3) Tier-0 urgent corrections, governed by
  `MEMORY_ARCHITECTURE.md` (D-0090); the packet/selection half is `CONTEXT_PACKET_CONTRACT.md` (its i32
  amendment). ADDITIVE + backward-compatible -- a v0.1.1-conformant producer/consumer stays valid; the new
  semantics bind where named. **(U1) `namespace` is a HARD retrieval boundary,** not a soft rank boost: the s3
  `filters.namespace` is an ENFORCED filter -- a candidate whose envelope `namespace` is outside the requested
  set is EXCLUDED before ranking; every hit carries its `namespace`; the retriever asserts all returned hits
  match (a mismatch is a fail-closed error, never a low-ranked hit). Single-namespace is default; a
  multi-namespace query passes an explicit set. `namespace` is a first-class catalog partition + the future
  hierarchy/node partition key. **(U4) `current_only` is a real retrieval MODE + supersession is rank-affecting.**
  The s3 `mode` gains `current_only`: any candidate whose s5 `status`/`currentness` is not `current` is
  HARD-EXCLUDED (not demoted); `historical_as_of`/`version_specific`/`any_valid_version` (s6) may still request
  stale/specific versions. A superseded record is ordered below its live successor by construction when both
  match (selection: `CONTEXT_PACKET_CONTRACT` s4). NEW first-class edge **`contradicts`** joins the s1 edge set
  (reserved-additive; detection is Tier 2 -- the edge exists now so a current-vs-current pair can drive packet
  `conflicted`). **(U2) hierarchy seam (reserved-additive; NO tree at Tier 0):** the CLOSED s1 `record_kind`
  enum gains **`node`** (a navigation node -- synopsis + bounded child list + time/authority ranges + key
  entities + child ids + counts + lexical descriptors + embedding + synopsis provenance, `MEMORY_ARCHITECTURE`
  s3 layer 6), and the s1 edge set gains **`member_of_node`** (record->node) + **`child_of_node`** (node->node).
  #36's flat catalog admits a `node` record via the envelope + `record_edges` with a `schema_version` bump and
  NO rewrite of sources/documents/versions/chunks; shortlist-and-descend + the tree build are Tier 1. Retrieval
  + selection MUST stay hierarchy-agnostic at the candidate-pool interface (no new flat-top-k-only hardening).
  **(U3) working-memory seam (reserved-additive; store at Tier 1):** the enum gains **`working`** -- a
  per-`task_id` record carrying a task's evolving state across its iterative turns; it surfaces ONLY for its own
  `task_id` (excluded from ordinary long-term retrieval by default), is `content_role != evidence` and NEVER
  control-plane authority, and follows a promote/demote lifecycle (created during a task, archived at close).
  Tier 0 reserves the kind + isolation so the compiler consults it as a DISTINCT packet region
  (`CONTEXT_PACKET_CONTRACT`). **(U5) the retriever channel set is FROZEN OPEN:** s3
  `retrieval_occurrences[].channel` is DATA -- graph/temporal/prior-use-statistics/code-symbol channels are
  added as new `channel` values with no interface change; a consumer MUST NOT hard-code `{lexical, vector}`. The
  query-classification stage that routes across channels lives in the compiler front
  (`CONTEXT_PACKET_CONTRACT`); the router is Tier 1. **Re-verify list** = {#36 (retriever hard namespace +
  `current_only` mode + the reserved kinds/edges + the additive migration + the schema-evolution gate test); #37
  selpol + #40 compiler (`CONTEXT_PACKET_CONTRACT` i32); the `MEMORY_ARCHITECTURE` Tier-0 gate}.
- **Amendment A5 -- Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING (D-0096, i33).** Folds the frontier Tier-0
  red-team (pack 159e9cb5, `research/2026-08-04-tier0-amendment-redteam.md`): the A4 seams are a correct
  ENVELOPE-level FIRST layer but INCOMPLETE -- namespace was only an envelope filter (leakage via derived records,
  diagnostic metadata, per-hop/traversal gaps) and supersession was candidate-set-dependent. A5 is ADDITIVE +
  backward-compatible and hardens the RECORD/RETRIEVER half; the packet/selection half is
  `CONTEXT_PACKET_CONTRACT` (its i33 amendment). **(U1' namespace CLOSURE -- SAFETY-CRITICAL):** `namespace` is an
  end-to-end information-flow boundary, not just an envelope filter. (a) The retriever enforces ONE canonical
  predicate `ns_permitted(candidate.namespace, effective_allowed_namespaces)` at EVERY retrieval stage AND every
  graph hop/edge-walk/rerank input -- never only the seed candidate. (b) EVERY returned or graph-reachable object
  is scope-checked (source_span/derivation_refs, edges walked, any diagnostic array the retriever emits), not just
  the hit envelope. (c) Derived records, aggregates, dedup clusters, and `node` records MUST be
  namespace-HOMOGENEOUS across their transitive provenance closure; a persisted cross-namespace derivative is
  FORBIDDEN at Tier 0 (a shared-scope contract is a later tier). (d) A cross-namespace candidate is EXCLUDED before
  ranking and leaves NO identifying metadata in any output -- the violation surfaces only as a
  `namespace_violation_count` + a fail-closed status; identifying detail (ids, paths, snippets) goes to a
  privileged local security log, never to a caller. A returned hit outside the effective set is a fail-closed ERROR
  that ABORTS, never a low-ranked hit. (e) `effective_allowed_namespaces` is CALLER-SUPPLIED (the compiler computes
  it = intersection(request, grant); the retriever treats it as a closed set and never widens it); empty set =>
  zero hits, fail-closed; no implicit all/wildcard/prefix/parent/shared namespace. (f) The SAME predicate +
  rejection policy is authored ONCE (owned by #37 `lib/`, imported by #40; #36's retriever implements the identical
  decision -- the fold asserts byte-identical accept/reject across the three), never re-implemented per module
  (risk 6). **(U4' candidate-INDEPENDENT supersession):** (a) NEW s5 currentness value `superseded` (the enum
  lacked a literal one); (b) NEW first-class edges `superseded_by` (record -> its live successor) + inverse
  `supersedes`, joining the s1 edge set (reserved-additive; A4's `contradicts` stays); (c) `effective_current(record)`
  is computed from the CATALOG/graph, not the retrieved pair: `status == current` AND no valid reachable live
  successor within scope at the pinned snapshot -- so `current_only` (s3) excludes a predecessor even when its
  successor is ABSENT from the candidate pool (A4's by-construction ordering was pool-dependent -- the defect); (d)
  chain invariants: acyclic, canonical single direction, NO cross-namespace supersession, a branch (two live
  successors) -> `conflicted` (surfaced, never a silent pick), immediate-vs-terminal successor distinguished, a
  stale/deleted successor does not silently resurrect its predecessor; (e) `contradicts` stays reserved with
  extensible attributes -- ABSENCE of the edge is NOT proof of no contradiction (detection is Tier 2). **(U2'
  hierarchy hit-shape):** retriever s3 provenance fields are CONDITIONAL on `provenance_mode` (A2) -- `direct_span`
  (path+span), `derived_record` (record_content_hash + derivation_refs; span OPTIONAL -- a node/summary/symbol has
  no single source span), `aggregate` (constituent refs), `tombstone` (deletion provenance); hits reserve
  `candidate_role` (`navigation | evidence`) + retrieval-stage lineage
  (`retrieval_stage_id`/`parent_stage_id`/`retrieval_plan_id`) because a compile is MULTI-STAGE (shortlist ->
  descend), NOT one flat top-k, with stage-local rankings (no new flat-top-k-only hardening); NAVIGATIONAL
  staleness (`summary_stale` `node`) may ROUTE but MUST NOT ANSWER; `child_of_node`/`member_of_node` EDGES are
  canonical, a node's stored child list is a rebuildable PROJECTION, no cross-namespace membership, acyclic. **(U3'
  working-state STORE seam):** the `working` kind (A4) is CONTINUITY-authoritative (the recorded current state of
  THIS task, NOT world-truth, NOT execution authority -- `can_instruct: false`, permissions live ONLY in
  control_plane). Reserve the store fields NOW: `working_state_id`, `task_id`, `state_version`,
  `parent_state_version`, `namespace_scope`, `grant_snapshot_ref`, `created_from_packet_id`, `content_hash`,
  `lifecycle_state` (`active | closed | archived`), `content_role: working_state`, `writer_authority`. Freeze the
  store semantics (STORE built at Tier 1): immutable versioned snapshots; CAS on `parent_state_version` at update;
  exactly one active head per task; explicit fork; a SEPARATE fixed working-memory budget; a closed state is not
  ordinarily retrievable; archive != evidence; PROMOTION creates a NEW derived long-term record with provenance +
  validation (never re-labels the working record). Access is CONJUNCTIVE -- `task_id` AND current-namespace
  authorization (task-isolation and namespace-isolation are DIFFERENT mechanisms; expansion never widens parent
  scope). Ordinary `search` MUST REJECT `record_kind = working` by default (retrievable only by an
  exact-`task_id` op) -- "excluded by default" is too weak; prefer a small `working_state/0.1` sub-contract. **(U5'
  classifier seam):** `query_class` (semantic) and `temporal_intent` (`current_only | historical_as_of |
  version_specific | any_valid_version`, s6) are INDEPENDENT dimensions -- an explicit user time/version OUTRANKS
  the class->mode stub; the classifier + the class->mode mapping are VERSIONED
  (`classifier_policy_id`/`classifier_policy_version`) with `composite` + `unclassified` fallback classes
  (packet-identity coverage = `CONTEXT_PACKET_CONTRACT` i33). **Re-verify list** = {#36 (per-hop `ns_permitted` +
  all-object scope-check + homogeneous derivations + sanitized fail-closed rejection + catalog
  `effective_current`/`superseded`/`superseded_by` + provenance_mode-conditional hit shape +
  candidate_role/stage-lineage reservations + `search` working-rejection; schema_version 3->4 additive); #37 (the
  canonical `ns_permitted` + rejection-policy owner; selpol supersession-chain demote; classifier-policy
  versioning) + #40 (import the predicate; conjunctive working-state access; classifier/temporal split) via
  `CONTEXT_PACKET_CONTRACT` i33; the `MEMORY_ARCHITECTURE` Tier-0 gate}. The A4 envelope-level wave STANDS as the
  foundation.
- **Adoption.** Wave 1 modules keep running as shipped at 0.1; each adopts 0.2 on its NEXT named revision
  (§9). Wave 2 NEW modules build to 0.2 from day one.
- **Grounding.** The frozen shapes reconcile the two shipped-0.1 interfaces (#35 embedding.local, #36
  artifact.search, #37 retrieval.eval; see their `SCHEMA_NOTES.md`) with the red-team's required amendments,
  and resolve the two concrete i25 divergences the D-0077 smoke surfaced (the `span` object-vs-string
  divergence, §3; the skipped-input null-vs-zero-vector divergence, §2).

## 1. The retrieval-record + provenance envelope (v0.1) -- the highest-leverage freeze

The single change that most protects the architecture: define ONE generic envelope every retrievable object
will satisfy, so file-chunks do **not** silently become the universal memory abstraction. A source chunk is
ONE `record_kind` among the kinds the architecture already anticipates: `symbol`, `summary`, `decision`,
`claim`, `episode`, `failure`, `procedure`, `skill`, `reminder`, `entity`, `relationship`, `node`, `working` (the last two added by A4). **This enum is
CLOSED (D-0085):** a producer MUST NOT emit a kind outside it. In particular an episode's per-stage detail is
STRUCTURAL -- it lives in the `episode` record `body` (a `stage_sequence` carrying the full stage detail)
and/or `child_edges` (`has_stage`), NOT as a separate `episode_stage` record. Adding a kind requires a §0
amendment with justification (do NOT build every future table now).

Do NOT build every future table now. The existing `sources -> documents -> document_versions -> chunks` tables
stay; expose chunks through this envelope via a **view/adapter** (no premature whole-DB generalization).

**Frozen envelope fields (normative names + intent):**

- `record_id` -- stable LOGICAL identity (survives revisions).
- `record_version_id` -- IMMUTABLE revision identity (one specific version of the record).
- `record_kind` -- enum; Wave 1 = `source_chunk`.
- `namespace` (a.k.a. `project_id`) -- isolation scope.
- `content_hash` -- hash of the record's canonical bytes/text. **(A2, D-0087)** split into distinct
  provenance hashes: `record_content_hash` (this record's canonical bytes), `source_content_hash` (the
  source FILE version bytes -- what s4 validation checks), `excerpt_hash` (the cited span bytes). Legacy
  `content_hash` aliases `source_content_hash` in an s3 hit / the chunk pipeline; `chunk_content_hash`
  aliases `excerpt_hash` for a `source_chunk`.
- `provenance_mode` (A2) -- `direct_span | derived_record | aggregate | tombstone`; selects s4's per-mode
  validation (a derived record has no single source span; a tombstone carries deletion provenance).
- `status` / `currentness` -- a single STRING from the §5 enum (`current` = healthy baseline); **NOT a boolean,
  NOT an object** (D-0085). Multiple simultaneous stale reasons -> optional `attrs.stale_reasons:
  [<§5 value>...]`; a provenance-check failure -> the `unverified` value (no separate `verified` flag). A
  *domain/body* status (e.g. a failure's investigation state `unverified|hypothesized|confirmed|resolved`) is a
  distinct `body`-level field, never the envelope `status`.
- `authority_level` -- how authoritative this record is as a source of truth.
- `sensitivity_class` -- privacy label (§7); present even when Wave 1 uses a single value.
- `valid_from` / `valid_to` -- nullable temporal validity.
- `created_by_ingest_run` -- the ingest/derivation run that produced it.
- `source_version_id` -- the immutable source version it derives from.
- `source_span` / `derivation_refs` -- exact source coordinates (byte span) and/or parent-record refs.
- `parser_fingerprint` / `chunker_fingerprint` / `extractor_fingerprint` / `schema_version` -- derivation
  provenance (§4).
- `token_count`.
- `embedding_space_id` -- nullable until embedded (§2).
- `parent_edges` / `child_edges` -- first-class derivation + relationship edges (chunk<-document; later
  summary<-descendants, symbol->symbol, decision supersedes decision; **(A4)** `member_of_node`/`child_of_node` node membership + tree, `contradicts` conflicting claims, **(A5)** `superseded_by`/`supersedes` supersession chains). NOT denormalized path fields.

**Chunk -> envelope mapping (Wave 1, normative for the #36 adapter):** `record_id` <- `document_id`+chunk
locator; `record_version_id` <- `chunk_id` (occurrence, below); `record_kind`=`source_chunk`;
`source_version_id` <- `version_id`; `content_hash` <- the chunk `content_hash`; `source_span` <- byte span.

**Two-level chunk identity (normative).** Distinguish a content-addressed chunk from a chunk occurrence:
`chunk_content_hash` (hash of the chunk's normalized/exact text) vs `chunk_occurrence_id` (this text at this
document version + section + span). A deterministic chunk id derives ONLY from immutable inputs --
`document_version_id + chunker_fingerprint + span + chunk_content_hash` -- **never** from insertion order or an
auto-increment sequence (stable re-ingest identity is an acceptance criterion). Identical text in multiple
authoritative locations dedups by `chunk_content_hash` without losing distinct occurrences.

## 2. Embedding-provider contract 0.2

Op `embed`. Normative changes over shipped 0.1 (#35 emitted `vectors[i]=null` + `per_input[]`; #36 mock
consumed a zero-vector-for-skipped + `input_status[]` -- BOTH are superseded):

- **Exactly one of `text` | `texts`.** Supplying both, or neither, is an error (no implementation-defined
  choice).
- **Ordered per-input RESULT records**, one array -- NOT parallel `vectors[]` + `status[]`:
  `items: [ { index, status, vector?, token_count, input_hash, truncated, error_code? } ]`. A skipped input
  (empty/oversize) has **no vector** (the field is absent), **never** a zero/garbage vector and never a silent
  drop. This resolves the i25 null-vs-zero divergence.
- **Explicit counts:** `input_count`, `vector_count` (successful), `failed_count`. The ambiguous single
  `count` is retired.
- **`input_role` / `embedding_purpose`:** `document` | `query` | (later `classification` / free-form
  instruction). Query/document template correctness (Qwen3-Embedding's asymmetric instruct prefix) is now a
  CONTRACT concern, not just a caller knob -- a mock cannot detect a forgotten query prefix, so the role is
  explicit and carried into provenance.
- **`embedding_space_id`** (a.k.a. `provider_fingerprint`) -- an immutable id that fully defines the vector
  space: model weights hash + tokenizer id/hash + pooling + query/document template + task instruction +
  normalization + precision/quantization + max sequence length + truncation policy + output dimension.
  **Storage keys on `embedding_space_id`, NOT on `provider_id + dim`** (two providers can share a dim and be
  mathematically incompatible).
- **Truncation is explicit policy:** `reject` (default) | `truncate_head` | `truncate_tail` | (later
  structured chunk-before-embed). Any truncation returns original token count, embedded token count, max, and
  the method flag. **Silent truncation is forbidden.**
- **Transport vs storage precision.** JSON numbers are acceptable for the ENVELOPE; the STORAGE
  representation is a **float32 little-endian BLOB** + fixed dim + vector-byte-length validation + optional
  vector hash + an encoding version. (The #36 0.1 JSON-array vector column is retired at #36 0.2.)
- **Determinism redefined pragmatically (three levels; gate on similarity + ranking, not byte equality):**
  (1) repeatability -- same device+config within a documented tolerance (measured cos_dist ~2e-16);
  (2) batch-equivalence -- batch vs single cosine above a threshold (measured ~8.7e-13);
  (3) retrieval-invariance -- known-near ranks above known-far and the benchmark ranking does not materially
  regress.
- **Re-embedding is out-of-place + resumable:** never overwrite an active space in place. Create a new
  `embedding_space` -> enqueue missing embeddings -> checkpoint per record -> build/populate the new index ->
  benchmark-compare -> atomically activate -> retain the prior space for rollback -> GC only by explicit
  policy. An engine-build string change triggers a COMPATIBILITY PROBE first, not an automatic full re-embed.

## 3. Retriever contract 0.2

Op `search`: `{ query, k, filters?, mode? }` -> a ranked hit array in DETERMINISTIC order. A consumer treats
array position as rank (`rank = index + 1`) and NEVER re-sorts. **(A4)** `filters.namespace` is an ENFORCED hard filter with an all-hits-match assertion; `mode` includes `current_only` (hard-excludes any non-`current` s5 status); `retrieval_occurrences[].channel` (below) is FROZEN OPEN -- do NOT hard-code `{lexical, vector}`. **(A5)** the namespace predicate is enforced at EVERY stage + graph hop (not just the seed) and every returned/reachable object is scope-checked; a cross-namespace hit is a fail-closed abort leaving no identifying metadata; `current_only` uses catalog-computed `effective_current` (the `superseded_by` chain); and hit provenance fields are conditional on `provenance_mode` with reserved `candidate_role`/retrieval-stage lineage.

**Frozen hit fields:**

- `record_id`, `record_version_id`, `record_kind`.
- `source_path` (repo-relative, POSIX-normalized) + `abs_path` (nullable, machine-specific provenance).
- `content_hash` -- the version identity.
- **`span`** -- RESOLVES the i25 divergence: `span` is ALWAYS an OBJECT `{ start, end }` of BYTE offsets (the
  canonical #36 form), PLUS a derived `span_label` string for human/section display (e.g. `"A > B"` or
  `"bytes:START-END"`). The producer always emits the object; consumers that want a string read `span_label`.
  (#37's string-consuming path adopts `span.start`/`span.end` + `span_label`; the fold adapter is retired.)
- `section_path`, `heading`, `chunk_type`.
- `currentness` / `status` + `authority_level` -- so the context compiler can reason about what it selected.
- **Per-channel diagnostics (at least in a diagnostic mode; hybrid is first-class):** `retrieval_channels`,
  `lexical_rank` + `lexical_score`, `vector_rank` + `vector_similarity`, `fused_rank` + `fused_score`,
  `fusion_algo` + `fusion_version`, `embedding_space_id`, `index_snapshot` / `corpus_version`, `filter_decisions`,
  and a stable `tie_break_key`. A single opaque `score` is RETIRED -- it makes hybrid-vs-lexical evaluation and
  debugging impossible.
- `snippet`, `rank`.

## 4. Catalog gates (artifact.search 0.2 + every Wave 2 store)

- **Explicit `schema_version` + a migrations mechanism** (forward migration, version stamped in
  `catalog_meta`).
- **Ingestion-run records** (extend the shipped `ingest_runs` with repo commit / dirty-worktree state).
- **Parser AND chunker AND extractor fingerprints** on every derived record. `chunker_fingerprint` =
  name + version + overlap policy + max tokens/chars + tokenizer identity + newline/Unicode normalization +
  code-fence policy + heading-context policy. A chunker/tokenizer/chunk-size change INVALIDATES derived chunks
  even when the source hash is unchanged.
- **Transactional current-version swap.** `current_version_id` is set atomically ONLY after: bytes captured +
  hashed; parse succeeded or received a defined degraded status; chunks + FTS rows complete; embeddings
  complete-or-explicitly-pending; provenance validated. New versions are STAGED before replacing current search
  state. On parse failure after a source change, the DB must NOT silently serve the old version as current -- it
  may serve it as an EXPLICITLY-marked stale fallback, visible to retrieval.
- **Tombstones.** Deleted sources are tombstoned (retain last known version, deletion observation time, source
  root, prior paths, provenance needed by historical episodes), not historically erased.
- **Physical-vs-logical identity.** A path is a locator, not a durable identity. Model configured source root,
  physical file occurrence (`source_locator_id` + path-history), logical document, immutable byte version.
  `content_hash` alone cannot distinguish move from copy; handle Windows path-casing dedup; treat NTFS file-ids
  as evidence only (not portable).
- **Crash-safety.** Fault-injection tests BETWEEN ingest phases; a crash must never leave FTS pointing at
  deleted chunks, current pointers referencing incomplete versions, half-populated embeddings, duplicate chunks
  after restart, or stale rows treated as current. Keep + extend the shipped integrity invariants.
- **Exact provenance reconstruction.** Every hit resolves: `retrieval hit -> record version -> chunk
  occurrence -> document version -> exact source bytes`, and reading the cited span reproduces the cited text.

## 5. Staleness taxonomy (not one boolean)

`status`/`currentness` is a single STRING (D-0085): the healthy baseline **`current`**, or -- when stale --
at least one of: `source_stale` (superseded document version); `derivation_stale`
(parser/chunker/extractor changed); `embedding_stale` (active embedding space changed); `relationship_stale`
(source version changed, edges need regeneration); `summary_stale` (a descendant changed); `authority_stale`
(no longer governs current truth); `temporal_expiry` (`valid_to` passed); **`superseded`** (a valid live successor exists in the chain -- A5); `deleted` (occurrence gone);
`unverified` (ingestion/provenance check failed). Retrieval filters current-source queries on this without
destroying historical memory; historical/version-specific queries (§6) may request stale/specific versions. **(A4)** `current_only` is a real retriever mode: a non-`current` candidate is HARD-EXCLUDED, not demoted. **(A5)** on catalog-computed `effective_current` (the `superseded_by` chain), so a superseded record is excluded even when its successor is absent from the candidate pool.
The `{state, stale_reasons, verified}` OBJECT form is RETIRED (D-0085): the effective value is the single
string `status`; any extra simultaneous reasons live in `attrs.stale_reasons`.

## 6. Evaluation gates (retrieval.eval 0.2)

- **Passage-level + evidence-group labels:** `must_include_all`, `must_include_any` groups, required
  version/span, acceptable-equivalent spans, explicitly-stale versions, `forbidden_sources`, hard privacy
  exclusions, distractors, `no_answer_expected`, label rationale, corpus snapshot, label status + reviewer. A
  file-level hit is NOT sufficient credit (a wrong chunk from the right file must not score).
- **Temporal intent per query:** `current_only` | `historical_as_of` | `version_specific` |
  `any_valid_version`. The shipped rule "a stale required source is always a miss" holds ONLY for
  `current_only`.
- **Negatives / abstention cases:** answer absent; only a stale answer exists; an attractive-but-wrong
  document; a forbidden personal source is the best lexical match; duplicates; exact-error-text required;
  paraphrase with low lexical overlap; disagreeing current sources; explicit historical intent.
- **Metrics added over 0.1** (which had recall@K / MRR / stale / provenance-presence): precision@K (or judged
  irrelevant-hit rate); nDCG@K; evidence-group coverage; forbidden-hit rate; stale-hit rate; duplicate/near-dup
  burden; source diversity; provenance VALIDITY (below); snippet-span correctness; relevant-tokens / total-
  retrieved-tokens; query latency + resource; no-answer false-positive rate; hybrid uplift AND hybrid
  regression.
- **Hybrid attribution is MANDATORY.** On the same corpus + query set run lexical-only, vector-only, and
  hybrid; report per query: results unique to each channel, required sources rescued by vectors, lexical
  exact-match results harmed by fusion, stale/forbidden results introduced by either channel, and the fusion
  contribution. A single aggregate hybrid score is insufficient.
- **Provenance VALIDATION (not presence).** For every scored hit verify: the content hash identifies the
  expected source version; the source still exists or has an explicit tombstone; the span is in bounds; reading
  the span reproduces the cited text; the snippet derives from that span; the parser+chunker fingerprint is
  known; current/stale status is correct.

## 7. Scale + privacy gates

- **Allowlisted source ROOTS** -- never crawl the whole user profile by default.
- **`sensitivity_class` on every source** (Wave 1 may use one value; the field is present from day one).
- **Exclusion rules TESTED, not just documented:** `.git`, virtualenvs, model files, databases, build
  outputs, generated artifacts, binaries/media, huge logs, minified bundles, caches, and secret/credential
  stores.
- **Egress + trust.** No local material leaves to a frontier/web service before an explicit EGRESS gate;
  embeddings are sensitive derived data; optional encryption at rest for personal-memory DBs; DB/index ACLs;
  absolute-path redaction in user-facing output; bounded logs that do NOT replicate whole source snippets; a
  retention/deletion policy.
- **Instruction-vs-evidence separation (SAFETY; hard blocker for later action waves).** Retrieved content
  (repo docs, logs, email, web captures, personal notes) is EVIDENCE, never authority or instruction. Trust +
  authority metadata stays separate from semantic relevance; a highly-relevant README or imported page must NOT
  grant permissions or override coordinator policy. Wave 1 (read-only, repo-only) does not trigger it; it
  BECOMES a safety blocker the moment retrieved content can influence side-effecting execution.
- **Deterministic-lexical provenance pinned:** SQLite build, FTS tokenizer + options, ranking function,
  locale/Unicode behavior, and stable tie-break belong in retrieval provenance.
- **Full-corpus (~200 MB) CPU-only rehearsal** before the catalog/FTS portion is called operational (a
  bounded fixture slice is insufficient): measure file/chunk counts, DB size, initial ingest, no-change
  rescan, one-file update, delete/rename, peak RAM, FTS latency, restart recovery, parser failures, and
  backlog behavior.

## 8. Hardware operating assumptions (RTX 2080 Ti build target)

One heavyweight resident model; sequential logical agents; batchable embeddings under a `gpu` lease; a CPU
fallback. Compare CPU vs GPU vectors directly -- mix in one space only within tolerance, else make the
execution backend part of `embedding_space_id`. Indexing is resumable (per-record checkpoint: source version,
record version, embedding space, status, attempt count, last error). Batch by TOKENS not document count
(cap items + aggregate tokens + payload bytes + timeout + memory headroom). Optimize TOTAL workflow latency:
measure whether CPU embedding beats repeatedly evicting/reloading the 9B before choosing to thrash the GPU.
RTX PRO 6000 (96 GB) is a horizon CONFIG (rerun benchmarks), not a redesign.

## 9. Applies-to + Wave 2 adoption

- **Wave 1 modules run as shipped (0.1).** Named next-revision work orders adopt 0.2: **#35 -> embedding
  0.2** (ordered per-input items, one-of text/texts, `embedding_space_id`, role, truncation policy, float32
  storage form); **#36 -> retriever 0.2 + catalog gates** (span object+label, per-channel scores, chunker
  fingerprint, transactional swap, migrations, float32 BLOB vectors, record-envelope view); **#37 -> eval
  0.2** (span.start/end + label, passage/evidence-group labels, temporal intent, hybrid attribution,
  provenance validation, negatives/no-answer).
- **Wave 2 NEW modules build to 0.2 from day one:** repository intelligence (symbols/imports/manifests/tests
  as typed records via the envelope, not chunks); episode + failure schema; the recorder. Each producer/consumer
  split names THIS doc as its shared contract and gets the D-0077 orchestrator cross-module smoke at fold.
- **Wave 3 / i30 conformance (D-0087):** the packet + selection layer is governed by the NEW
  `core-docs/CONTEXT_PACKET_CONTRACT.md` (`context_packet/0.2` build target). #37 authors the versioned
  `selpol_rrf_v1` selection-policy library (owned here, consumed by #40); #40 -> `context_packet/0.2`
  (control/evidence separation, packet_disposition, consumer profile, A2 provenance names); #41 -> a
  `summary` activation card (A3). D-0077 cross-module fold smoke at close.
- **This doc is authoritative** for the memory substrate; a module's `SCHEMA_NOTES.md` records how it
  interpreted a frozen field, and any deviation is a defect to reconcile at fold (or an amendment via §0).
