# episode.record -- SCHEMA_NOTES (Module 39, skill `episode.record` 0.1.0)

**Authority.** This file records EVERY schema/interface interpretation for the D-0077 cross-module fold
(episode.record #39 PRODUCES episode/failure records; #36 0.2 `ingest_records` is the SINK). The
orchestrator's fold smoke depends on it. Governing contract: `core-docs/MEMORY_CONTRACT.md` s1 (record +
provenance envelope v0.1), s5 (staleness), s6 (provenance validation), s7 (privacy); directive
`research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` sections 5.3 (episodic), 5.4
(failure), 10 (recorder). D-0080/D-0083.

Worker: `episode_record.py` (Python stdlib only). Entrypoint: `Invoke-EpisodeRecord.ps1` (pwsh-file).
CPU-only, no model, no network. Fingerprints: `parser_fingerprint="episode.trace_parser/1"`,
`extractor_fingerprint="episode.recorder/0.1.0"`, `chunker_fingerprint=null` (episodes/failures are NOT
chunked), envelope `schema_version="1"`.

---

## 1. Determinism contract (READ FIRST)

- **Every emitted field is a pure function of the FIXED input (the run trace / the failure descriptor) +
  the recorder's own fingerprints.** No wall-clock, no uuid, no absolute path, no insertion order ever
  feeds an id, a hash, or the canonical bytes. Any timestamp that appears in a record (`valid_from`,
  `valid_to`) comes from the trace input, which is fixed -- never from `now()`.
- **canonical JSON** for every emitted record/report/bundle: `sort_keys`, `ensure_ascii`, compact
  separators, one trailing LF, UTF-8 no BOM. **INTEGER-ONLY**: `confidence` is stored as `confidence_ppm`
  (int) and a recursive `intify` pass coerces every remaining float to an int (round-half-up), so no float
  repr can diverge across platforms. => a re-run (same inputs) is **byte-identical, cross-machine**.
- **`records_digest`** = `sha256` over sorted `"{record_id}\t{record_kind}\t{content_hash}\t{record_version_id}"`
  lines -- the single comparable cross-env pin (the analog of #36's `catalog_digest`; content-derived, never
  abs-path/rowid/timestamp). The `worker-summary.json` carries absolute artifact paths (volatile); the
  record `.json` artifacts + `records_digest` are the canonical pins. The `lifeorch.skill.result/0.1`
  envelope (from the pwsh wrapper) carries all other volatile diagnostics.
- Input files are EOL-normalized (CRLF/CR -> LF, BOM stripped) before parse, and the trace content hash is
  taken over the **re-canonicalized** parsed object -- so a CRLF (Windows) vs LF (cloud) checkout of a
  fixture yields identical records.

## 2. The MEMORY_CONTRACT s1 record + provenance ENVELOPE (v0.1) -- as implemented

Every emitted record is ONE generic envelope `schema="lifeorch.memory_record/0.1"` carrying ALL the s1
normative fields, with the kind-specific payload nested under **`body`** (typed by `body_schema`). This is
the interpretation of "define ONE generic envelope every retrievable object satisfies" (MEMORY_CONTRACT
s1): a chunk is one `record_kind`; an episode/stage/failure is another. Envelope fields (all present on
every record):

`schema, record_id, record_version_id, record_kind, body_schema, namespace, content_hash, status,
authority_level, sensitivity_class, valid_from, valid_to, created_by_ingest_run, source_version_id,
source_span, derivation_refs, parser_fingerprint, chunker_fingerprint, extractor_fingerprint,
schema_version, token_count, embedding_space_id, parent_edges, child_edges, body`.

Interpretations of the s1 fields:

- **`record_id`** = the stable LOGICAL identity (survives revisions). Kind-prefixed, content-derived
  (`x[:24]` = first 24 hex of sha256 -- the artifact.search #36 convention):
  - episode: `"ep_" + sha256(namespace "\0" task_id "\0" attempt)[:24]` -- the task-RUN occurrence.
  - episode_stage: `"eps_" + sha256(episode.record_id "\0" stage_index "\0" stage_name)[:24]`.
  - failure: `"fail_" + sha256(namespace "\0" failure_signature)[:24]` -- so two occurrences of the SAME
    failure class (same signature) map to the SAME logical record (dedup), while occurrences link via edges.
- **`record_version_id`** = the IMMUTABLE revision. `"<pfx>v_" + sha256(record_id "\0" content_hash)[:24]`
  (pfx: `ep`/`eps`/`fail`). A change in content OR the recorder version -> new content_hash -> new version.
- **`content_hash`** = `"sha256:" + sha256(canon_bytes(canonical_content))` over the IMMUTABLE canonical
  content = `{record_kind, body_schema, namespace, body, source_version_id, source_span, derivation_refs,
  parent_edges, child_edges, parser_fingerprint, chunker_fingerprint, extractor_fingerprint,
  schema_version}` -- EXCLUDES record_id / volatile fields. It folds in `extractor_fingerprint` so a
  recorder change is a `derivation_stale` event (s5). The validator RECOMPUTES this (s6 provenance validity).
- **`status`** = the s5 currentness taxonomy OBJECT `{state, stale_reasons[], verified}`, NOT a bare
  boolean. A freshly recorded episode is `{state:"current", stale_reasons:[], verified:true}`. (The
  failure's INVESTIGATION state -- unverified|hypothesized|confirmed|resolved -- is a separate `body.status`,
  distinct from envelope staleness.)
- **`authority_level`**: `observed` (episode/episode_stage -- a factual log of a real run), `curated`
  (a failure authored into the corpus with a correction/prevention_rule), `proposed` (an auto-derived
  candidate failure from a failed trace, not yet reviewed).
- **`sensitivity_class`**: s7 label, ALWAYS present. Default `project_internal`; overridable per record.
- **`valid_from` / `valid_to`**: nullable temporal validity, sourced from `trace.started_at`/`finished_at`
  (provenance timestamps from the fixed input; never wall-clock).
- **`created_by_ingest_run`** = `"recrun_" + sha256(source_version_id "\0" extractor_fingerprint)[:24]` --
  a DETERMINISTIC recorder-run id (stable per trace+recorder), so it can be carried WITHOUT breaking
  byte-identity (contrast a random run id, which would be volatile).
- **`source_version_id`** = the immutable id of the trace this record derives from
  (`"tracever_" + sha256(trace_id "\0" trace_content_hash)[:24]`; `trace_content_hash` = sha256 over the
  re-canonicalized trace). For a curated failure with no trace, `"fdesc_" + id24(...)`.
- **`source_span`** = `null` for episodes/failures (they are not byte-slices of a file); the exact source
  coordinates live in **`derivation_refs`** instead (s1 allows byte-span AND/OR parent-record refs). An
  episode's derivation_refs = `[{ref_kind:"run_trace", trace_id, trace_content_hash, event_range:[0,N]}]`;
  a stage's ref carries its own `event_range`; a failure's refs link the episode / trace / any
  commits/tests/decisions from the descriptor `links`.
- **`token_count`** = a deterministic whitespace-token estimate over the canonical text of `body`.
- **`embedding_space_id`** = `null` (episodes/failures are NOT embedded by this producer; the field is
  present + nullable exactly per s2/s1).
- **`parent_edges` / `child_edges`** = FIRST-CLASS edge arrays (NOT denormalized path fields):
  - episode `child_edges`: `[{edge_kind:"has_stage", child_record_id: <stage>, ordinal:i}]` per stage.
  - episode_stage `parent_edges`: `[{edge_kind:"stage_of", parent_record_id: <episode>, ordinal:i}]`.
  - failure `parent_edges`: `[{edge_kind:"occurred_in_episode", parent_record_id: <episode>}]` when derived
    from a trace. (The edge is one-directional episode<-failure to avoid a hash cycle; the episode is built
    and hashed before the failure's id is known.)

## 3. EPISODE body schema (`lifeorch.episode/0.1`; directive 10.1)

`{ task_id, parent_project, original_request, context_packet_id, attempt, plan[], stage_sequence[] (ordered
lightweight refs {ordinal, stage_name, status, record_id} -- the FULL stage records are separate
episode_stage records via child_edges), model_provenance[] (deduped {model_id, version, engine_build}),
engine_provenance[] (engine build strings), tool_invocations[] (aggregated across stages), state_changes[]
(bounded before/after), artifacts[] (from trace.artifacts), test_results[], reviewer_outcomes[],
human_interventions[], final_status (ok|partial|failed|cancelled|escalated), metrics{} (time + resource,
integer-coerced), escalation_reasons[], failure_reasons[], stage_count, complete:true }`.

`complete:true` is invariant: the recorder ALWAYS emits a complete episode, even from a failed or truncated
trace (see s5 of this doc).

## 4. EPISODE_STAGE body schema (`lifeorch.episode_stage/0.1`)

`{ stage_index, stage_name, role, status (ok|failed|incomplete|skipped), closed_explicitly, duration_ms,
tool_invocations[], state_changes[], test_results[], reviewer_outcomes[], human_interventions[], errors[],
notes[], model_provenance[] }`. Each is its own s1 record, linked to the parent episode by edges (s2).

## 5. The RECORDER + its INPUT trace schema (`lifeorch.run_trace/0.1`)

Trace input: `{ schema, trace_id, task_id, parent_project, attempt?, original_request, context_packet_id?,
started_at?, finished_at?, final_status, plan?[], models?[], metrics?{}, escalation_reasons?[], failure?{},
events:[ {seq, type, stage?, role?, ...} ] }`. Event `type`s: `stage_start`, `stage_end` (carries
`status`, `duration_ms`), `tool_invocation` (`skill_id, op, status, args_digest, artifact_refs,
duration_ms, model_id?`), `state_change` (`target, kind, before, after, reversible`), `test_result`,
`reviewer_outcome`, `human_intervention`, `error` (`code, message, stage`), `note`, `model`.

Recorder behavior (`op record`):
- Events are grouped into stages by `stage_start`/`stage_end`. **ROBUST to a FAILED/TRUNCATED trace:** an
  open stage with no matching `stage_end` is closed anyway (status inferred: `failed` if it saw an error,
  else `incomplete` when the run failed, else `ok`); a trace with NO stage markers gets one synthetic `run`
  stage. => a failed run still yields a COMPLETE episode + complete stages.
- `final_status` = `trace.final_status`, else inferred (`failed` if any error event, else `ok`).
- On a failed run WITH a `trace.failure` descriptor (and `emit_failure` true, the default), the recorder
  also emits a CANDIDATE `failure` record (`authority_level="proposed"`, `body.status="unverified"`) linked
  to the episode. This is NOT failure mining (that is a later wave) -- it is one candidate from one trace.

## 6. FAILURE body schema + the failure_signature (`lifeorch.failure/0.1`; directive 5.4/10.2)

`{ component, component_version, affected_versions[], attempted_operation, environmental_conditions{runtime?,
tools?, file_types?, schemas?, model_config?, ...}, observable_symptoms, failure_signature, root_cause,
hypothesis, evidence[]{kind, ref, snippet(bounded)}, correction, prevention_rule, verification_case,
confidence_ppm (int), status (unverified|hypothesized|confirmed|resolved), match_keys{...} }`.

- **`failure_signature`** (deterministic, task-conditioned) = `"fsig1:{component-slug}:{digest20}"` where
  `digest20 = sha256(comp_key "\n" op_key "\n" symptom_key "\n" cond_key)[:20]` and each `*_key` is a
  sorted-unique normalized token join over, respectively: the component/skill/tool tokens; the
  attempted/planned OPERATION tokens (minus generic verbs -- see `OP_STOPWORDS`, so "run"/"execute" do not
  create spurious matches); the observable-symptom tokens; and the CONDITION tokens (file_types + schemas +
  model/runtime). Same component+operation+symptoms+conditions -> same signature -> same logical
  `record_id` (dedup). Conditioning on file types / schemas / model config is what makes retrieval
  task-conditioned (directive 5.4).
- **`match_keys`** = the structured normalized token SETS the retrieval seam scores on:
  `{components, operations, file_types, schemas, model_tokens, symptom_tokens, keywords}`.

## 7. The FAILURE-SIGNATURE retrieval SEAM (`op search-failures`; directive 5.4)

Query shape `lifeorch.task_context/0.1`: `{ components?, skills?, file_types?, schemas?, model_config?{},
planned_operations?, keywords?, failure_signature? }`. Deterministic baseline: `score = sum over facets of
weight_f * |query_facet_tokens & failure_facet_tokens|`, weights: components/skills->components **5**,
planned_operations->operations **4**, schemas->schemas **4**, model_config->model_tokens **3**,
file_types->file_types **2**, keywords->symptom_tokens **2**, keywords->keywords **2**; an exact
`failure_signature` match adds **1000**. A failure with **zero overlap is EXCLUDED** (never surfaces).
Ranked by `(-score, record_id)` -- a stable, cross-platform tie-break. Result:
`{schema:"lifeorch.failure_search_result/0.1", query_facets, corpus_size, match_count, results:[{record_id,
failure_signature, component, score, matched_facets, rank}]}`. This is the SEAM a later retriever/reranker
CONSUMES; it is NOT a production retriever (no embeddings, no BM25, no live store). The corpus may be built
failure records (s1 envelopes) OR raw descriptors (facets computed on the fly).

## 8. s1 VALIDATOR (`op validate`) -- incl. PROVENANCE validity (s6)

Checks per record: all s1 envelope fields present; `record_kind` valid; `record_id`/`record_version_id`
well-formed (`^[a-z]+_[0-9a-f]{24}$`); `content_hash` well-formed; `status` is the currentness object (not a
bool); `sensitivity_class` present; `embedding_space_id` present (nullable); parent/child/derivation edges
are lists; **content_hash RECOMPUTES from canonical content** (a tampered body is rejected with a
`content_hash MISMATCH`); `record_version_id` derives from `(record_id, content_hash)`; and kind-specific
required body fields. Report: `{all_valid, num_valid, kind_counts, records:[{record_id, record_kind, valid,
errors[]}]}`.

## 9. Privacy / sensitivity policy (MEMORY_CONTRACT s7)

An episode may reference personal/task data. Therefore: `sensitivity_class` is on every record (default
`project_internal`); **egress is OUT** (this producer never sends anything to any network/frontier -- it
only reads a trace and writes local JSON); free-text symptom/evidence/summary/state-change fields are
BOUNDED (`SNIPPET_BOUND` = 2000 chars, truncated with a deterministic `...[+K chars]` marker) so a record
does not replicate a whole blob; and the worker's stderr diagnostics are bounded (never dump a whole record
or snippet). Instruction-vs-evidence separation (s7): a recorded episode/failure is EVIDENCE, never
authority -- it carries `authority_level` metadata separate from any semantic content; this producer is
read-only and does not trigger the side-effecting-action safety blocker.

## 10. FOLD drop-in -- the #36 0.2 `ingest_records` SINK (D-0077; FIXTURE, reconciled at fold)

`op record` and `op build-failure` also emit `records.json` = an **ingest bundle**
`{schema:"lifeorch.ingest_records_request/0.1", op:"ingest_records", namespace, record_count, records:[<s1
envelope>...]}` (see `tests/fixtures/ingest_records-fixture.schema.json`). #36 0.2 (built by a sibling
worker THIS wave) defines the real `ingest_records` sink; this producer builds every record to the FROZEN
s1 envelope and ships the fixture bundle shape. **At fold** the orchestrator feeds a REAL episode + failure
record into #36 0.2 `ingest_records`; any wrapping divergence (e.g. #36 keying embeddings on
`embedding_space_id`, which is `null` here) is reconciled then and recorded back here. Acceptance: every
record in the bundle validates against s1 (`op validate` -> `all_valid:true`).

## 11. Concurrency / scope

`parallel_safe=true`: the module is pure deterministic CPU logic touching only its own artifact dir; no
shared mutable state, no model, no network. (Wave-level "parallel-safe (distinct module)" also holds -- it
touches only `modules/39-episode-memory`.)

## 12. Non-goals (NOT built -- later waves)

Auto-capture wired into agent.local #21 (the recorder is INVOKED with a trace, not auto-wired); failure
MINING across a live episode store / procedure discovery (directive 10.2/10.3, Priority 5/6); embeddings;
the catalog DB / storage (#36 owns it); the context compiler; UI. The fixture failure corpus is a FEW
illustrative gotchas from CURRENT_STATE, not a mined corpus.

## 13. Gotcha discovered this unit (report to orchestrator for CURRENT_STATE)

**PowerShell variable names are CASE-INSENSITIVE, so a local `$op` silently IS the `-Op` parameter `$Op`.**
Initializing `$op = $null` before reading `$Op` wiped the bound parameter, so `-Op <value>` was ignored and
every op defaulted to `record` (the `-InputsJson` path still worked because it re-read `$p.op`). Caught by
the build-failure/validate/search dispatch tests, NOT by the record tests (whose default op is `record`).
Fix: never name a local the same (case-insensitively) as a parameter; the local op var is `$opName`.
