# SCHEMA_NOTES -- retrieval.eval (Module 37, Wave 1 CPU lane, plan fo-25-3b718a13)

**REQUIRED by D-0077.** This module is the CONSUMER side of a schema producer/consumer pair: it calls a
retriever (the producer -- lane B / `artifact.search` #23 at fold; its own lexical baseline now). This doc
records EVERY schema + interface interpretation the harness codes against, so the orchestrator's
cross-module fold smoke can wire the real `artifact.search` behind this harness without guessing.

Governing design doc: `core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`
sections 8 (retrieval interface), 11.1 (retrieval verification metrics), 8.6 (context-quality signals).
Decisions: D-0080/D-0081 (direction), D-0077 (the cross-module smoke rule).

---

## 1. The retriever interface I CONSUME (D-0077 shared contract)

Op `search`. The harness calls ANY retriever satisfying this; nothing else about the retriever is assumed.

- **Input:** `{ query: string, k: int, filters?: object }`.
- **Result:** a **ranked array** of hit objects, in **DETERMINISTIC order** (the retriever owns its ranking
  and its tie-break; the harness treats array position as rank, `rank = index + 1`, and NEVER re-sorts).
- **Hit object:**

  | field | type | meaning |
  |---|---|---|
  | `source_path` | string | repo-relative source path (POSIX-normalized on read: `\`->`/`, leading `./` stripped) |
  | `content_hash` | string | version identity of the surfaced source -- `sha256:<64hex>` OR an opaque non-empty version id (`version_id` is accepted as an alias) |
  | `chunk_id` | string | stable id of the returned chunk within the source |
  | `span` | string | where in the source: a heading/section path (e.g. `A > B`) or a line/byte range |
  | `score` | number | retriever score (opaque to the harness; used only for the retriever's own ordering) |
  | `snippet` | string | short human preview of the chunk |

  The harness tolerates unknown extra fields and coerces missing string fields to `""` (an empty
  `content_hash`/`span` then counts as INCOMPLETE provenance -- see section 4).

### How the harness reaches a retriever

Two retriever kinds are built in (spec in the benchmark's `retriever` or overridden via `-RetrieverJson`):

- **`lexical_baseline`** (shipped now; the KNOWN baseline): deterministic BM25-lite over a fixture corpus.
  `{ kind, corpus_dir, k1?=1.5, b?=0.75, include_suffixes?=[".md",".txt"], exclude_dir_names?=[] }`.
  It produces conforming hits itself (see section 3).
- **`external_command`** (the FOLD seam): invoke any external retriever as a subprocess.
  `{ kind, argv:[...], request_via: "stdin"|"file"|"arg", hits_pointer?="result.hits", timeout_seconds?=60,
  label? }`. The request `{query,k,filters}` is delivered per `request_via`; the command's stdout is parsed
  as JSON and `hits_pointer` (a dotted path) navigates to the ranked hits array (a bare top-level array is
  also accepted). argv tokens `{PYTHON}` `{BASE_DIR}` `{MODULE_ROOT}` `{REQUEST_FILE}` `{REQUEST_JSON}` are
  substituted at call time. **At fold the orchestrator sets `argv` to invoke `artifact.search`'s `search`
  op and points `hits_pointer` at wherever its envelope carries the ranked hits.** `tests/fixtures/
  mock-retriever.py` is a working conforming example.

---

## 2. The benchmark schema I author against -- `lifeorch.retrieval_benchmark/0.1`

A JSON file (or inline object). Each query carries its REQUIRED-SOURCE labels.

```jsonc
{
  "schema": "lifeorch.retrieval_benchmark/0.1",
  "benchmark_id": "lo-fixture-v1",
  "corpus_dir": "corpus",                 // optional; baseline corpus, resolved relative to base_dir
  "retriever": { "kind": "lexical_baseline", ... },   // optional default; request can override
  "k_values": [1, 3, 5, 10],              // optional (default [1,3,5,10])
  "retrieval_depth": 10,                   // optional (default max(k_values); raised to >= max(k_values))
  "queries": [
    {
      "query_id": "q1-install",            // REQUIRED, unique
      "query": "how do I ...",             // REQUIRED, the query text
      "required_sources": [                 // >=0; the source(s) a correct retrieval MUST surface
        { "source_path": "guides/install.md",
          "content_hash": "sha256:...",     // optional; when present it MUST match (wrong hash = miss)
          "span": "Install > Start",        // optional
          "require_span": false }           // optional; when true the hit's span must equal `span`
      ],
      "stale_sources": [                    // optional; known-superseded (path, hash) -- a hit of one is a stale error
        { "source_path": "archive/install.v1.md", "content_hash": "sha256:..." }
      ],
      "forbidden_sources": [                // optional; sources that must NOT appear (path, or path+hash)
        { "source_path": "reference/glossary.md" }
      ],
      "filters": { "path_prefix": "guides/" } // optional; passed verbatim to the retriever
    }
  ]
}
```

### Matching semantics (load-bearing)

A hit **H** matches a required source **R** iff: `H.source_path == R.source_path` **AND** (if `R.content_hash`
is given) `H.content_hash == R.content_hash` **AND** (if `R.require_span` and `R.span`) `H.span == R.span`.

The version rule is the point of section 4.2 of the design doc: **a right path with a STALE/superseded
content_hash is a MISS, not a hit** -- it is additionally reported as a `wrong_version_hit` (right path,
labelled hash mismatched) or, when it matches a `stale_sources` entry, an `explicit_stale_hit`.

---

## 3. The lexical baseline (deterministic, KNOWN)

- **content_hash is EOL-NORMALIZED:** `sha256:` + sha256 of the file's UTF-8 text with a BOM stripped and
  CRLF/CR normalized to LF. So a Windows (CRLF) vs cloud (LF) checkout hashes IDENTICALLY -- the benchmark's
  labelled hashes are stable regardless of git EOL handling.
- **tokenization:** lowercase, `[a-z0-9]+`, minus a small FIXED English stopword set (documented in the
  worker) so filenames/symbols/terminology dominate the signal.
- **chunking:** Markdown by ATX heading (a pre-heading preamble is its own chunk; `span` = the heading path);
  plain text by blank-line paragraph (`span` = a line range). `chunk_id` = `<relpath>#<NNN>`.
- **scoring:** BM25 (`k1`, `b`; non-negative BM25+ idf). Chunks with zero query-term overlap are NEVER
  returned. Rank key = `(-score_millionths, source_path, chunk_id)` -- a stable, cross-platform tie-break.
- **score_unit = millionths:** the score in every hit and report is an integer (`round_half_up(score*1e6)`),
  so no float appears in the canonical output. (Adjacent-score gaps over the fixture corpus are ~0.08, far
  larger than any libm ULP, so ranking + rounding are cross-platform stable.)

---

## 4. Metrics (section 11.1) and the report schema -- `lifeorch.retrieval_eval_report/0.1`

All ratios are integer **ppm** (parts-per-million), round-half-up (`ratio_unit: "ppm"`). No float anywhere.

- **recall@K** (per K in `k_values`): per-query = matched-required-within-K / required; aggregate macro =
  round(mean of per-query ppm); micro = round(sum matched / sum required).
- **MRR:** per-query reciprocal rank of the FIRST hit matching ANY required source within `retrieval_depth`
  (0 if none); aggregate = round(mean).
- **stale-source rate:** fraction of queries with >=1 `explicit_stale_hit` OR `wrong_version_hit` in depth.
- **provenance completeness:** fraction of ALL returned hits (within depth) whose `source_path` +
  `content_hash` + `chunk_id` + `span` are ALL non-empty.
- **forbidden-hit rate:** fraction of queries with >=1 forbidden source in depth (false-positive burden).
- also: `queries_all_required_present`, `total_hits`, `total_required`, per-query `missing_required`.

`report.json` (schema `lifeorch.retrieval_eval_report/0.1`) = `{ schema, generator{name,version,score_unit},
benchmark_id, benchmark_schema, retriever{kind}, input_digest, corpus?, aggregate{...ppm...},
per_query[{query_id, query, num_required, matched_at_k, recall_at_k_ppm, first_relevant_rank,
reciprocal_rank_ppm, all_required_present, missing_required[], explicit_stale_hits[], wrong_version_hits[],
stale_affected, forbidden_hits[], provenance_total, provenance_complete, returned[{rank, source_path,
content_hash, chunk_id, span, score, provenance_complete}]}] }`.

**Canonical discipline (both report.json and report.md):** UTF-8 no BOM, sorted keys, compact separators,
one trailing LF, integer-only (scores millionths, ratios ppm), and NO volatile fields (no timestamps /
invocation ids / absolute paths / host / wall-clock). Re-running on identical input is byte-identical across
machines. The volatile diagnostics live in the separate `lifeorch.skill.result/0.1` envelope. `input_digest`
= `sha256:` of the canonical bytes of {benchmark queries, retriever spec (minus corpus_dir), corpus source
hashes, k_values, retrieval_depth}.

---

## 5. Fold notes (for the orchestrator's D-0077 smoke)

To point this harness at the real `artifact.search`: author a benchmark whose `retriever` is an
`external_command` spec invoking `artifact.search`'s `search` op, with `hits_pointer` set to the envelope
path holding its ranked hits, and required-source labels using `artifact.search`'s `content_hash`/version
identity. The harness needs NO change: the baseline and the real retriever run through the same code path,
and the deterministic report lets the orchestrator compare retrieval quality before/after vector
integration. If `artifact.search`'s hit provenance omits any of source_path/content_hash/span, this
harness's provenance-completeness metric will report it below 1.0 -- that is the intended signal.
