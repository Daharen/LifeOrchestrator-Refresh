# Frontier red-team -- Wave 1 memory-substrate DESIGN review (i25, pack 12c8f539)

**Folded:** 2026-08-01 (D-0082). **Verdict: GO** -- proceed, conditional on a shared-contract AMENDMENT before the Wave-2 fold; NOT a redesign and NOT a delay of Wave 1. Captured via frontier.bridge read-return (valid/captured/pack_id_match).

**Orchestrator reconciliation.** Wave 1 (#35 embedding.local + #36 artifact.search + #37 retrieval.eval) shipped and the D-0077 cross-module smoke PASSED (real 1024-dim embed -> store -> search -> benchmark; recall/provenance 1.0; digest stable; change detected). The smoke already validated this review's central worry -- that isolated worker tests cannot prove the producer and consumers read the shared contracts identically -- by catching a `span` object-vs-string divergence between artifact.search and retrieval.eval (bridged at the fold). No safety-critical blocker applies to the bounded, repo-only, read-only wave; the two would-be blockers (indexing arbitrary personal dirs without allowlists/sensitivity/egress; retrieved content driving side-effecting execution without a trusted-vs-untrusted separation) are NOT triggered and become gates for later personal-data / action waves.

**Wave-2 agenda (from this review; see D-0082):** freeze a versioned retrieval-RECORD + PROVENANCE contract (chunks are one record kind among symbols/summaries/decisions/episodes/failures/procedures/skills/reminders); embedding contract 0.2; retriever contract 0.2 (resolves the span divergence + per-channel scores/ranks + record/version identity); catalog gates (schema versioning/migrations, transactional current-version swap, tombstones, crash test); evaluation gates (passage-level + evidence-group labels, negatives/no-answer, lexical-vs-vector-vs-hybrid attribution); scale + privacy gates (allowlisted roots, sensitivity field, full-corpus CPU rehearsal).

---

# Wave 1 Memory-Substrate Design Red-Team

## Gate verdict

**PROCEED, BUT AMEND THE SHARED CONTRACTS BEFORE FOLD.**

I do **not** see a safety-critical reason to block the bounded, repository-only, read-only Wave 1. The choice of SQLite, FTS5, immutable source versions, local embeddings, and a real producer-to-consumer integration smoke is directionally sound.

I would, however, refuse to call the present design “future-proof.” It is a good **file-search MVP**, but it is not yet a sufficiently defined foundation for the broader cognitive-memory architecture. The central risk is that `chunks` become the accidental universal memory abstraction, after which summaries, symbols, episodes, failures, procedures, decisions, and prospective memories all have to impersonate filesystem chunks.

Two conditions would become safety blockers:

1. Indexing arbitrary personal directories, client material, credentials, or health/financial records without explicit root allowlists, sensitivity labels, and egress controls.
2. Allowing retrieved repository or personal text to influence side-effecting execution before the system distinguishes **trusted instructions** from **untrusted retrieved content**.

Neither is necessary for the bounded Wave 1 described here.

---

# Single highest-leverage change

## Freeze a versioned **retrieval-record and provenance contract** now

Do not attempt to build every future memory table in Wave 1. Do define one generic envelope that every retrievable object will eventually satisfy.

A source chunk should be one kind of retrieval record, alongside future:

* symbols;
* summaries;
* decisions;
* claims;
* episodes;
* failures;
* procedures;
* skills;
* reminders;
* entities and relationships.

The governing architecture already expects retrieval across all of those types, not merely source chunks.

At minimum, freeze fields equivalent to:

* `record_id`: stable logical identity;
* `record_version_id`: immutable revision identity;
* `record_kind`;
* `project_id` or namespace;
* `content_hash`;
* `currentness/status`;
* `authority_level`;
* `sensitivity_class`;
* `valid_from` / `valid_to`, where applicable;
* `created_by_ingest_run`;
* `source_version_id`;
* exact source span or derivation references;
* parser, chunker, extractor, and schema provenance;
* token count;
* embedding-space identity;
* parent and child derivation edges.

The existing `sources → documents → document_versions → chunks` tables can remain. Add a view or adapter that exposes chunks through this generic retrieval-record contract. That avoids prematurely generalizing the whole database while preventing `artifact.search` from hard-coding “retrievable thing = file chunk.”

This one change also gives the context compiler, benchmark harness, repository intelligence, and later memory types a shared target.

---

# A. SQLite catalog, chunking, versions, and provenance

## What is right

SQLite is appropriate for this scale and operating model. The architecture needs transactions, exact identifiers, filtering, joins, FTS, version status, and provenance more than it needs a distributed database. The directive correctly assigns identifiers, versions, hashes, status, relationships, and authoritative metadata to SQLite while leaving canonical source bytes on the filesystem.
The proposed initial tables are a reasonable file-catalog decomposition:

* `sources`;
* `documents`;
* `document_versions`;
* `chunks`;
* `chunk_embeddings`.

The design is also correct that vectors should address canonical records rather than replace them.

## What is underdefined

### 1. Physical location and logical identity are conflated

A path is a locator, not a durable document identity.

The schema must distinguish:

* configured source root;
* physical file occurrence;
* logical document;
* immutable byte version;
* path history.

Otherwise:

* a rename may look like delete plus create;
* two identical files may look like one moved file;
* a copied file may incorrectly inherit another file’s history;
* Windows path casing may create duplicates;
* the same repository at two roots may collapse or duplicate unpredictably.

Content hash alone cannot distinguish move from copy. Consider a stable `source_locator_id` plus path-history records. NTFS file IDs may be useful evidence on the current machine but should not be the only identity because they are not portable.

### 2. Chunk identity needs two levels

A content-addressed chunk and a chunk occurrence are not always the same thing.

Use something equivalent to:

* `chunk_content_hash`: hash of normalized or exact chunk text;
* `chunk_occurrence_id`: this text at this document version, section, and span.

That allows deduplication without losing the fact that identical text appears in multiple authoritative locations.

A deterministic chunk ID should derive from immutable inputs such as:

`document_version_id + chunker_fingerprint + span + chunk_content_hash`

It should not depend on insertion order or an auto-increment sequence if stable re-ingest identity is an acceptance criterion.

### 3. Parser provenance is not enough

The worker brief records `parser` and `parser_version`, but chunk output also depends on:

* chunker name and version;
* complete chunking configuration;
* overlap policy;
* maximum tokens or characters;
* tokenizer identity;
* newline and Unicode normalization;
* encoding detection;
* code-block policy;
* heading-context policy.

A parser upgrade, tokenizer change, or chunk-size change should invalidate derived chunks even when the source hash is unchanged.

### 4. Currentness needs explicit transactional semantics

Do not infer “current” from the newest timestamp.

A logical document should have an explicit `current_version_id`, changed atomically only after:

1. bytes are captured and hashed;
2. parsing succeeds or receives a defined degraded status;
3. chunks and FTS rows are complete;
4. required embedding state is either complete or explicitly pending;
5. provenance validation passes.

On parser failure after a file changes, the database must not silently continue serving the old version as though it were current. It can serve it as an explicitly marked stale fallback, but that distinction must be visible to retrieval.

Deleted sources should generally be tombstoned rather than historically erased.

### 5. Provenance should be a derivation chain

`source_path + content_hash + span` is necessary but insufficient.

A trustworthy result should resolve through:

`retrieval hit → record version → chunk occurrence → document version → exact source bytes`

It should also identify:

* ingestion run;
* repository commit or dirty-worktree state;
* parser and chunker fingerprints;
* embedding space;
* retrieval run;
* ranking and fusion configuration.

The architecture intends summaries, claims, decisions, episodes, and procedures to become retrievable and mutually related. It also anticipates relationship mappings such as symbols calling symbols and decisions superseding decisions. Those require first-class derivation and relationship edges rather than denormalized path fields.

## What the current schema would make hard later

### Repository intelligence

Code symbols, imports, manifests, tests, and producer-consumer relationships are not naturally chunks. They require stable typed entities scoped to particular source versions. The roadmap expressly expects those additions in the next wave.

Without a generic record/version layer, repository intelligence will either:

* overload `chunks`;
* build a parallel catalog;
* or require a schema migration that rewrites retrieval.

### Context compiler

The context compiler needs more than relevance and text. It must reason about:

* authority;
* currentness;
* sensitivity;
* source type;
* token cost;
* duplication;
* evidentiary role;
* omitted context;
* why a record was selected.

The planned context packet explicitly contains authoritative state, constraints, source excerpts, procedures, failure records, token accounting, and omitted-context information. A file-chunk-only schema does not supply enough metadata to compile that packet reliably.

### Episodic, failure, and procedure memory

Episodes and procedures have lifecycles, promotion states, approvals, rollback relationships, and evidence. The architecture requires episodes to record context packets, plans, tools, state changes, test results, human interventions, and model provenance.

They should be structured records that are retrievable—not Markdown documents generated solely to fit `artifact.search`.

---

# B. Embedding-provider interface

## Verdict

**Adequate as a first adapter test; insufficient as a durable embedding-space contract.**

The current contract usefully requires model identity, hash, engine build, dimensions, normalization, order preservation, and clean empty/oversize handling. Those are good requirements.

Several ambiguities remain.

## 1. Skipped inputs conflict with “vectors in exact input order”

If an oversize input is skipped, does `vectors[i]`:

* disappear;
* become `null`;
* contain an empty vector;
* or remain in a separate compact vector array?

Replace parallel arrays with an ordered result per input:

```text
items: [
  {
    index,
    status,
    vector?,
    token_count,
    input_hash,
    truncated,
    error_code?
  }
]
```

Also distinguish:

* `input_count`;
* `vector_count`;
* `failed_count`.

The existing generic `count` field is too ambiguous.

## 2. Require exactly one input form

The contract permits `text` and/or `texts`. State that exactly one must be supplied. Otherwise workers may make incompatible choices when both are present.

## 3. Add `input_role` or `embedding_purpose`

Many embedding models distinguish query and document representations through different prefixes, templates, or instructions.

The contract should support at least:

* `document`;
* `query`;
* possibly `classification` or a free-form task instruction later.

A mock hashed vector cannot detect that the real adapter forgot a query prefix or used the document template for both sides.

## 4. Define an immutable embedding-space fingerprint

`model_id`, version, SHA-256, engine build, dimension, and normalization still do not fully define the vector space.

The fingerprint should incorporate:

* model weights hash;
* tokenizer identity and hash;
* pooling method;
* query/document template;
* task instruction;
* normalization;
* precision and quantization;
* maximum sequence length;
* truncation policy;
* relevant engine settings;
* output dimension.

Call this `embedding_space_id` or `provider_fingerprint`.

Rows should not merely store `provider_id + dim`; two providers with the same dimension can be mathematically incompatible.

## 5. Make oversize behavior explicit policy

Defaulting to rejection is sensible. The caller should be able to request an explicit policy later:

* `reject`;
* `truncate_head`;
* `truncate_tail`;
* possibly structured chunking before embedding.

Any truncation must return:

* original token count;
* embedded token count;
* maximum;
* truncation flag and method.

Silent truncation must remain forbidden.

## 6. Define transport precision

Arrays of generic JSON numbers are acceptable for the adapter envelope but should not become the canonical database representation.

The storage contract should specify something like:

* float32 little-endian BLOB;
* fixed dimension;
* vector byte length validation;
* optional vector hash;
* encoding version.

JSON vectors will create large envelopes, slow PowerShell serialization, and uncertain numeric round-trips.

## 7. Redefine determinism pragmatically

Exact float equality across:

* CPU and GPU;
* differing batch sizes;
* engine builds;
* thread counts;

may be unrealistic.

Test three levels:

1. **Repeatability:** same device and configuration within a measured numeric tolerance.
2. **Batch equivalence:** cosine similarity between batch and single embeddings above a threshold.
3. **Retrieval invariance:** known-near items remain above known-far items and benchmark ranking does not materially regress.

The current design correctly asks for a documented tolerance, but the acceptance gate should emphasize similarity and ranking invariants rather than byte equality.

## Re-embedding strategy

Never overwrite an old embedding space in place.

Use:

1. create new `embedding_space`;
2. enqueue missing embeddings;
3. checkpoint progress per record;
4. build or populate the new index;
5. run benchmark comparison;
6. atomically select it as active;
7. retain the prior space for rollback;
8. garbage-collect only under explicit policy.

Engine changes should trigger a compatibility probe first. Do not automatically re-embed an entire corpus merely because an engine build string changed if vectors remain equivalent within the approved tolerance.

---

# C. `artifact.search`, chunking, FTS, reconciliation, and scale

## What breaks at approximately 200 MB?

**SQLite and FTS5 are not the likely breakpoints.**

The source itself identifies a target of roughly 200 MB and thousands of files. That is modest for SQLite. The likely failures are operational:

* too many tiny filesystem operations;
* hashing files one transaction at a time;
* parsing large or generated files;
* binary and minified content;
* junction or symlink loops;
* locked files;
* files mutating while being read;
* watcher storms;
* vector serialization and brute-force search;
* unbounded snippets or reports;
* incomplete restart recovery.

## Required ingestion mechanics

### Use transactional batches and WAL

Use:

* WAL mode;
* prepared statements;
* batched transactions;
* useful indexes on current status, path, hash, document, and embedding space;
* bounded work queues;
* backpressure and backlog reporting.

### Hash and parse the same byte snapshot

Do not:

1. hash a file;
2. reopen it later;
3. parse different bytes;
4. associate them with the first hash.

Capture or stream from a consistent snapshot. At minimum, compare size and modification metadata before and after processing and retry if the source changed.

### Define exclusions and limits

Explicitly handle:

* `.git`;
* virtual environments;
* model files;
* databases;
* build outputs;
* generated artifacts;
* binary media;
* huge logs;
* minified bundles;
* cache directories;
* secrets and credential stores.

The governing design already calls for explicit inclusion and exclusion rules and requires parser failures to be surfaced. The Wave 1 gate should test those rules rather than merely documenting them.

### Make reconciliation crash-safe

New versions should be staged before replacing current search state. A crash must not leave:

* FTS pointing at deleted chunk rows;
* current-version pointers referencing incomplete versions;
* half-populated embeddings;
* duplicated chunks after restart;
* stale rows still treated as current.

Add fault-injection tests between each ingestion phase.

### Preserve deleted history

Deletion reconciliation should remove deleted material from default-current search while retaining:

* the tombstone;
* last known version;
* deletion observation time;
* source root;
* prior paths;
* provenance needed by historical episodes.

## Markdown chunking concerns

“Markdown-aware” is a direction, not a sufficiently precise contract.

Tests should cover:

* headings with no body;
* duplicate heading names;
* deeply nested headings;
* very long sections;
* code fences larger than embedding limits;
* tables;
* front matter;
* links and reference definitions;
* list structures;
* mixed newline types;
* malformed fences;
* generated Markdown;
* repeated boilerplate.

Every chunk should preserve:

* section path;
* exact line and byte or character range;
* chunk kind;
* ordinal;
* parent section;
* token count;
* overlap or inherited-heading text;
* whether displayed text differs from exact source bytes.

Do not use normalized offsets without retaining a mapping to original source coordinates.

## Is the mock-to-real swap clean?

**Shape-clean, not behavior-clean.**

The mock verifies:

* envelope shape;
* dimension;
* ordering;
* empty and oversize handling.

It does not verify:

* query/document templates;
* tokenizer behavior;
* pooling;
* actual dimension;
* vector distribution;
* normalization precision;
* batch-dependent differences;
* real latency;
* persistence format;
* nearest-neighbor ordering;
* hybrid fusion.

The fold smoke is therefore essential, but one real query is not enough.

## The retriever interface is under-specified for hybrid search

The current result provides one `score` and no indication of how that score was produced. Yet the architecture mandates hybrid retrieval and the fold is expected to execute it.

Every hit should include, at least in diagnostic mode:

* retrieval method or candidate channels;
* lexical rank and raw score;
* vector rank and similarity;
* fused rank and score;
* fusion algorithm and version;
* embedding-space ID;
* index snapshot or corpus version;
* filter decisions;
* stable tie-break key.

A single opaque score prevents debugging and makes hybrid-versus-lexical evaluation impossible.

## Vector-search boundary

`chunk_embeddings` is storage, not necessarily an index.

The design should explicitly choose an MVP:

* brute-force cosine search in bounded batches;
* a SQLite vector extension;
* or an external local vector index keyed back to SQLite IDs.

Brute force may be perfectly acceptable initially, but state a ceiling and benchmark it. For example:

* maximum indexed vectors;
* expected dimension;
* cold and warm query latency;
* maximum RAM allocation;
* threshold at which a real ANN index becomes required.

---

# D. Retrieval-evaluation benchmark

## What the proposed metrics cover

The initial suite correctly includes:

* recall@K;
* MRR;
* stale-source handling;
* provenance completeness;
* deterministic machine and human reports.

Those are proper baseline metrics. The broader governing document also expects exact-source retrieval, version correctness, false-positive burden, packet size, and task success with and without retrieval.

The Wave 1 worker brief does not yet measure enough of that broader intent.

## Required-source labeling needs a richer schema

A query should not simply list required filenames.

Support:

* `must_include_all`;
* `must_include_any` groups;
* required document versions;
* required spans or section paths;
* acceptable equivalent spans;
* explicitly stale versions;
* forbidden results;
* hard privacy exclusions;
* distractors;
* `no_answer_expected`;
* label rationale;
* corpus snapshot;
* label status and reviewer.

A file-level hit is not enough. Retrieval can return an irrelevant chunk from the correct file and receive undeserved credit.

For multi-source questions, recall must measure whether all necessary evidence classes were retrieved, not whether any one relevant document appeared.

## Add negative and abstention cases

The benchmark should include queries where:

* the answer is absent;
* only a stale answer exists;
* an attractive but wrong document exists;
* a forbidden personal source contains the best lexical match;
* duplicate documents exist;
* the correct result requires exact error text;
* the query is paraphrased and has little lexical overlap;
* multiple current sources disagree;
* the user explicitly asks for historical rather than current information.

Without no-answer tests, increasing recall can reward indiscriminate retrieval.

## Add these metrics

* precision@K or judged irrelevant-hit rate;
* nDCG@K for graded relevance;
* required-evidence-group coverage;
* forbidden-hit rate;
* stale-hit rate;
* duplicate or near-duplicate burden;
* source diversity;
* provenance validity, not just field presence;
* snippet-span correctness;
* relevant tokens divided by total retrieved tokens;
* query latency and resource use;
* no-answer false-positive rate;
* hybrid uplift over lexical;
* hybrid regressions relative to lexical.

## Hybrid attribution is mandatory

For the same corpus and query set, run:

1. lexical-only;
2. vector-only;
3. hybrid.

Report per-query:

* results unique to each channel;
* required sources rescued by vectors;
* lexical exact-match results harmed by fusion;
* stale or forbidden results introduced by either channel;
* final fusion contribution.

A single aggregate hybrid score can hide the fact that semantic retrieval damaged exact-ID, error-message, or filename queries.

## Staleness must be query-conditioned

A stale source is wrong for “What is the current state?” but may be exactly right for:

* “What did the project say before D-0080?”
* “Which prior decision was superseded?”
* “When was this failure introduced?”

Therefore, the benchmark schema needs a temporal intent:

* current-only;
* historical-as-of;
* version-specific;
* any valid version.

The present rule that stale required material always counts as wrong is correct only for current-state queries.

## Provenance completeness must be validated

Do not count provenance as complete merely because path, hash, and span fields are non-null.

For every benchmark hit, verify:

1. the content hash identifies the expected source version;
2. the source still exists or has an explicit tombstone;
3. the span is in bounds;
4. reading the span reproduces the cited text;
5. the snippet is derived from that span;
6. the parser and chunker fingerprint is known;
7. current/stale status is correct.

---

# E. Provenance, versioning, staleness, and privacy

## Staleness is not one boolean

Represent at least:

* **source stale:** superseded document version;
* **derivation stale:** parser, chunker, or extractor changed;
* **embedding stale:** active embedding space changed;
* **relationship stale:** source version changed and graph edges need regeneration;
* **summary stale:** a descendant changed;
* **authority stale:** source no longer governs current truth;
* **temporal expiry:** valid-until date passed;
* **deleted:** source occurrence no longer exists;
* **unverified:** ingestion or provenance check failed.

This allows current-source filtering without destroying historical memory.

## Privacy requirements

“Local by default” is a good policy but not a full privacy design. The architecture explicitly anticipates personal knowledge, financial records, health preparation, correspondence, and reminders.

Add:

* root-level allowlists—never crawl the entire user profile by default;
* source sensitivity labels;
* project and identity namespaces;
* retrieval filters based on caller authority;
* no raw snippets in ordinary logs;
* absolute-path redaction in user-facing output;
* database and index ACLs;
* backup policy;
* deletion and retention policy;
* egress policy before any local material is sent to frontier or web services;
* treatment of embeddings as sensitive derived data;
* optional encryption at rest for personal-memory databases.

FTS tables and embeddings both disclose information. “No network contacted” reduces exposure but does not protect against another local account, malware, backups, or later accidental export.

## Retrieved content must not become authority

Repository documents, logs, emails, web captures, and personal notes can contain instructions. Later context compilation must present them as **evidence**, not system commands.

Trust and authority metadata must remain separate from semantic relevance. A highly relevant README or imported web page must not be allowed to grant permissions or override coordinator policy.

---

# F. Failure modes and RTX 2080 Ti assumptions

## Hardware assumptions are sensible

The design correctly treats:

* one heavyweight resident model;
* sequential logical agents;
* batchable embeddings;
* GPU lease use;
* CPU fallback;
* incremental embedding;
* compact contexts;

as the active operating policy.

The embedding model is not the likely hardware problem. Scheduling and interruption behavior are.

## Required operational safeguards

### 1. Embedding queue and checkpointing

Indexing should be resumable by:

* source version;
* record version;
* embedding space;
* status;
* attempt count;
* last error.

Do not restart an entire re-embedding pass after a crash.

### 2. Batch by tokens, not document count

A batch of 32 short chunks and 32 maximum-length chunks are radically different workloads. Enforce:

* maximum items;
* maximum aggregate tokens;
* maximum payload bytes;
* timeout;
* memory headroom.

### 3. Verify CPU/GPU compatibility

If CPU fallback and GPU embeddings are placed in the same vector space, compare them directly. If their cosine differences or rankings exceed tolerance, either:

* prohibit mixing;
* or treat execution backend as part of the embedding-space fingerprint.

### 4. Avoid disruptive model thrashing

Measure whether CPU embedding is cheaper overall than repeatedly evicting and reloading the 9B. The design should optimize total workflow latency, not isolated embedding throughput.

### 5. Pin SQLite and FTS behavior

Deterministic lexical results also depend on:

* SQLite build;
* FTS tokenizer;
* tokenization options;
* ranking function;
* locale and Unicode behavior;
* stable tie-break order.

These belong in retrieval provenance.

### 6. Add full-scale CPU-only rehearsal

The current acceptance gate indexes a bounded real-repository slice. That is insufficient to expose thousands-file ingestion and reconciliation failures.

Before calling the catalog/FTS portion operational, run a full approximately 200 MB rehearsal without requiring all embeddings. Measure:

* file and chunk counts;
* database size;
* initial ingest time;
* no-change rescan time;
* one-file update time;
* delete and rename time;
* peak RAM;
* FTS query latency;
* restart recovery;
* parser failures;
* backlog behavior.

---

# Ranked risks

## 1. File chunks become the universal memory abstraction — **High**

**Consequence:** parallel schemas, duplicated retrieval logic, or a major migration before episodes, failures, procedures, and symbols can participate naturally.

**Mitigation:** freeze the generic versioned retrieval-record envelope now.

## 2. Hybrid retrieval remains an opaque implementation detail — **High**

**Consequence:** mock integration passes, but no one can explain whether lexical or vector retrieval found a result, whether fusion helped, or why exact identifiers disappeared.

**Mitigation:** add per-channel ranks and scores, fusion provenance, retrieval mode, and embedding-space identity to the retriever contract.

## 3. Current/stale transitions are not crash-atomic — **High**

**Consequence:** stale versions appear current, FTS and catalog disagree, partial updates become retrievable, or citations resolve to the wrong bytes.

**Mitigation:** staged version creation, transactional current-pointer swap, tombstones, integrity checks, and fault injection.

## 4. Benchmark labels are too coarse and produce false confidence — **High**

**Consequence:** returning any chunk from the expected file counts as success even when the required evidence is absent.

**Mitigation:** passage-level and evidence-group labels, negatives, no-answer cases, graded relevance, and hybrid attribution.

## 5. Privacy and trust metadata are deferred too far — **Medium–High**

**Consequence:** broad personal indexing or later external-model use exposes sensitive information; retrieved content is mistaken for authorized instruction.

**Mitigation:** allowlisted roots, sensitivity/authority labels, ACL-aware retrieval, egress controls, and instruction-versus-evidence separation.

## 6. Re-ingestion and re-embedding are not sufficiently resumable — **Medium**

**Consequence:** long jobs repeat work, old and new embedding spaces mix, and crashes leave ambiguous state.

**Mitigation:** immutable embedding spaces, per-record job state, checkpointing, atomic activation, and rollback.

## 7. Scale validation uses only a bounded slice — **Medium**

**Consequence:** the design passes fixtures while failing on path collisions, junctions, generated files, watcher storms, and transaction overhead.

**Mitigation:** full-corpus CPU catalog/FTS rehearsal with explicit performance budgets.

---

# Amendments I would require before the Wave 1 fold

1. **Embedding contract 0.2**

   * exactly one of `text` or `texts`;
   * ordered per-input results;
   * query/document role;
   * explicit truncation policy;
   * `embedding_space_id`;
   * vector encoding and precision;
   * separate input and successful-vector counts.

2. **Retriever contract 0.2**

   * immutable record and record-version IDs;
   * record kind;
   * currentness and authority;
   * source/version/span provenance;
   * retrieval channel;
   * lexical/vector/fused scores and ranks;
   * fusion and index version;
   * stable tie-break key.

3. **Catalog gates**

   * explicit schema version and migrations;
   * ingestion-run records;
   * parser/chunker fingerprints;
   * transactional current-version swap;
   * tombstone behavior;
   * crash/restart test;
   * exact provenance reconstruction.

4. **Evaluation gates**

   * passage-level required labels;
   * any/all evidence groups;
   * forbidden and distractor sources;
   * no-answer query;
   * lexical-only versus vector-only versus hybrid report;
   * provenance validity;
   * stale-current and historical-version tests.

5. **Scale and privacy gates**

   * allowlisted source roots;
   * exclusion rules;
   * sensitivity field, even if all Wave 1 sources initially use one value;
   * full-corpus catalog/FTS rehearsal;
   * bounded logs that do not replicate entire source snippets.

---

# Final assessment

The strategic direction is correct. The insistence on external authoritative memory, disposable model contexts, hybrid retrieval, provenance, versioning, and real cross-module integration is substantially better than continuing to accumulate isolated modules. The fold smoke is especially important because isolated worker tests cannot prove that the producer and consumers interpret the shared contracts identically.

The design’s weakness is not SQLite, the 2080 Ti, or the size of the corpus. It is that the current shared interfaces describe **transport shapes** more precisely than they describe **semantic identities**:

* What exactly is a retrievable record?
* Which immutable version was retrieved?
* Which embedding space produced the vector?
* Why is the record current and authoritative?
* Which channel retrieved it?
* How was it fused?
* Can the cited span reconstruct the exact evidence?
* Is the caller permitted to receive it?

Answer those questions in the contracts before the workers’ interpretations harden into separate implementations.

**Recommended gate: GO, conditional on a contract amendment—not a redesign and not a delay of the local wave.**

