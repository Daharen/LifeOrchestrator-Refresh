# Full-corpus rehearsal recipe (the orchestrator's ~200MB Tier-1 acceptance gate) -- i35/i36, plans fo-35-0a5bf334 / fo-36-1a676e4b

The committed SAMPLE (`tests/fixtures/rehearsal-corpus/`, the click 8.1.7 slice) is what this worker BUILDS +
VALIDATES the harness on -- small, fast, deterministic. The FULL ~200MB run is the ORCHESTRATOR's fold gate: it
is HEAVY (a network fetch + a large ingest), so it is a **documented, HASH-VERIFIED prep** here, NOT claimed
deterministic across the fetch. This file is that recipe. The harness itself (`rehearsal_eval.py`) is unchanged
between the sample and the full run -- only `corpus_root` / `benchmark` / `scales` differ.

## 0. Why a REAL foreign corpus (not synthetic, not this repo)

Synthetic scale is NECESSARY but NOT SUFFICIENT (i34): synthetic generation can accidentally align query
vocabulary / grouping keys / labels in ways a real repository does not. And the project's OWN repo would align
vocabulary with our schemas. So the corpus is a slice of REAL, FOREIGN, permissively-licensed open-source source
+ docs, never shaped for our schemas.

## 1. The pinned corpus set (permissive: BSD / MIT / Apache / PSF), hash-verified

Fetch each SDIST (source, not wheel) and VERIFY its sha256 BEFORE use (fail-closed on mismatch). These six are
the committed-sample lineage + siblings; add the LARGE-tier packages in section 4 to reach ~200MB of source text
without replication, OR use the harness's deterministic scale replication (section 3).

| package==version | sdist file | sha256 (of the .tar.gz) |
|---|---|---|
| click==8.1.7        | click-8.1.7.tar.gz        | `ca9853ad459e787e2192211578cc907e7594e294c7ccc834310722b41b9ca6de` |
| flask==3.0.3        | flask-3.0.3.tar.gz        | `ceb27b0af3823ea2737928a4d99d125a06175b8512c445cbd9a9ce200ef76842` |
| jinja2==3.1.4       | jinja2-3.1.4.tar.gz       | `4a3aee7acbbe7303aede8e9648d13b8bf88a429282aa6122a993f0ac800cb369` |
| requests==2.32.3    | requests-2.32.3.tar.gz    | `55365417734eb18255590a9ff9eb97e9e1da868d4ccd6402399eaf68af20a760` |
| rich==13.7.1        | rich-13.7.1.tar.gz        | `9be308cb1fe2f1f57d67ce99e95af38a1e2bc71ad9813b0e247cf7ffbcc3a432` |
| werkzeug==3.0.3     | werkzeug-3.0.3.tar.gz     | `097e5bfda9f0aba8da6b8545146def481d06aa7d3266e7448e2cccf67dd8bd18` |

Combined extracted text (.py/.rst/.txt/.md/.c/.h): ~5.5 MB across the six (measured 2026-08-05). That is a real
multi-project foreign corpus but SMALL -- reach ~200MB via section 3 (replication) or section 4 (large tier).

## 2. Fetch + hash-verify + prep (deterministic prep; the FETCH is a network step)

Two equivalent fetch paths -- the executor `curl.exe` path (per the fan-out handoff) or `pip download` (PyPI is
the allowlisted registry). BOTH must hash-verify.

### 2a. Executor curl.exe (Windows box)
```
# for each package: URL = https://files.pythonhosted.org/packages/source/<first-letter>/<pkg>/<file>
curl.exe -L -o click-8.1.7.tar.gz  https://files.pythonhosted.org/packages/source/c/click/click-8.1.7.tar.gz
# ...repeat for the six...
# VERIFY (fail-closed): every sha256 must equal the table above
CertUtil -hashfile click-8.1.7.tar.gz SHA256
```
### 2b. pip download (any box with python)
```
pip download click==8.1.7 flask==3.0.3 jinja2==3.1.4 requests==2.32.3 rich==13.7.1 werkzeug==3.0.3 \
    --no-deps --no-binary :all: -d ./_full_corpus_sdists
```
### 2c. Extract + EOL-normalize + organize into NAMESPACES + a manifest
```
python3 prep_full_corpus.py --sdists ./_full_corpus_sdists --out ./full-corpus --manifest ./full-corpus/MANIFEST.json
```
`prep_full_corpus.py` (a documented ~40-line prep, NOT shipped as a gated skill -- it is corpus prep) must:
1. VERIFY each sdist sha256 against section 1 (fail-closed on mismatch).
2. Extract each package; **byte-normalize** every text file (strip BOM, CRLF/CR -> LF) so `content_hash` is
   stable CRLF-vs-LF (matches #36 + this harness).
3. Organize into >= 2 NAMESPACES so the cross-namespace-contamination criterion is exercised at scale. The
   recommended split is ONE namespace per package (`click`, `flask`, `jinja2`, `requests`, `rich`, `werkzeug`),
   optionally sub-split code (`src/`) vs docs (`docs/`) as the sample does (`clickcode` / `clickdocs`).
4. Write `MANIFEST.json` = `{corpus_id, upstream:[{package,version,sha256}], files:[{path,bytes,sha256}],
   manifest_digest}` (same shape as `tests/fixtures/rehearsal-corpus/MANIFEST.json`).

## 3. Reach ~200MB deterministically (the harness already does this)

The harness's `scales` parameter INGESTS the corpus at increasing replication factors (each replica carries a
unique localized decisive token so localized queries stay localized). To reach a ~200MB / >=2-orders-of-magnitude
leaf sweep from the ~5.5MB pinned set, drive:
```
Invoke-RetrievalEval.ps1 -Op rehearsal -InputsJson '{
  "corpus_root":   "C:/.../full-corpus",
  "benchmark":     "C:/.../full-benchmark.json",
  "scales":        [1, 40, 1600],
  "wired_descend": true }'
```
`scales=[1,40,1600]` over ~5.5MB -> ~1600x -> ~8.8GB of ingested replicas at the top scale (well past ~200MB;
lower the top factor to land near 200MB: ~200MB/5.5MB ~= 36x, so `[1, 36, 3600]` still spans >=2 orders while the
MIDDLE scale lands ~200MB). Pick the factors so `max/min >= 100` (enforced) and the middle/top scale reaches the
byte target you want measured.

## 4. OR the LARGE tier (reach ~200MB of DISTINCT source, no replication)

Add these pinned large permissive packages (fetch + hash-verify the same way; confirm each sha256 at fetch time,
they are large so they were not pre-hashed here -- record them into the manifest):
`django` (BSD, ~9MB sdist / ~30MB extracted), `sphinx` (BSD), `pandas` (BSD, large), `sqlalchemy` (MIT), plus the
CPython source tarball `Python-3.12.x.tgz` from python.org (PSF, ~150MB extracted with tests) if python.org is
reachable from the executor. Distinct source avoids the replication caveat entirely; a manifest with per-file
sha256 pins it.

## 5. The full labeled benchmark

`full-benchmark.json` is a `lifeorch.rehearsal_benchmark/0.1` file (same schema as the sample) whose `corpus`
names the full-corpus namespaces + whose `queries` are MANUALLY LABELED against the fetched content (verify anchor
terms by grep, as the sample's `label_provenance` records). Cover all five kinds (cross-cutting / rare-decisive /
current-vs-historical / exact-reference / global-synthesis) with PINNED expected outcomes; add a controlled
supersession `temporal_records` pair for the current-vs-historical criterion. The sample benchmark
(`tests/fixtures/rehearsal-benchmark.json`) is the template.

## 5a. i36 WIRED-DESCEND drive (the Tier-1 flip mechanism)

`wired_descend:true` (top-level or under `config`) makes the harness DRIVE #40 0.7.0's SHIPPED public
`-Retriever artifact_search` shortlist-and-descend port (aa2f0fb / D-0100) end-to-end and MEASURE s10 against the
WIRED packets -- navigation cost from #40's OWN plan trace, not the #36-direct baseline. A request WITHOUT
`wired_descend` is BYTE-IDENTICAL to 0.7.0 (regression-proven; the flat #36-direct-nav + #40-flat path is retained
as a LABELED baseline for the descend-vs-flat delta).

**The WIRED-descend #40 request the harness constructs (keys from #40 SCHEMA_NOTES s18; NEVER guessed).** For each
labeled query (own descend class) + each scale localized query (coerced to `global_synthesis`) the harness builds:
```
{ "op": "compile",
  "task": { "original_goal": <q>, "request_text": <q>, "namespace": <ns>, "task_type": "research",
            "query_class": "global_synthesis"|"precedent_search",          # a #40 DESCEND class
            "control_plane": { "permission_grants": [ { "namespaces": [<ns>] } ] },   # SCOPED, single ns
            "config": { "hier_shortlist_k": 4, "hier_beam_b": 4, "hier_depth_d": 6, "token_budget": 2000 } },
  "retrieval_meta": { "retriever": "artifact_search", "corpus_version": <cv> },       # pinned snapshot
  "catalog_db_path": <the built #36 catalog db>,                                       # over the built tree
  "retrieval_batches": [ { "query_index": 0, "hits": <#36 flat search hits> } ] }      # recall-safe fallback
```
The port constructs ONLY when ALL hold (`_maybe_build_artifact_search_port`): retriever normalizes to
`artifact_search`, a real `catalog_db_path`, a DESCEND `query_class`, an ENFORCED non-empty SINGLE-namespace
closure, #36 importable, and a CURRENT published hierarchy for that namespace. The harness reads the WIRED nav
cost from `packet.retrieval_completeness.navigation_nodes_examined` and the stage trace from
`packet.retrieval_completeness.retrieval_plan.stages[]`.

**The `m40_argv` adapter override** (how the ORCHESTRATOR points the harness at the FROZEN #40 0.7.0 CLI at fold):
```
"adapter": { "m40_argv": ["<pwsh>", "-NoProfile", "-File",
                          "C:/.../modules/40-context-compiler/Invoke-ContextCompiler.ps1",
                          "-InputsJson", "{REQUEST_FILE}"] }        # or the python core: ["{PYTHON}","{M40}","{REQUEST_FILE}"]
```
The adapter substitutes `{PYTHON}`/`{M36}`/`{M40}`/`{REQUEST_FILE}` and reads each core's envelope from
`request.meta_path`. Default `m40_argv` resolves the python core sibling to the module -- the orchestrator overrides
it to Lane A's WIRED #40 CLI. The non-wired flat path is UNCHANGED regardless of the override.

## 6. Run + the flip

The harness emits `rehearsal_report.json` + a computed `tier1_accepted` over the corpus+CLI it is pointed at. It
does NOT claim project-level Tier-1 acceptance. In WIRED mode the report adds a `wired_descend` block (its own
11-criterion s10 tier1 measured against the WIRED packets + the descend-vs-flat deltas) and flips the AUTHORITATIVE
`tier1_acceptance`/summary `tier1_accepted` to the WIRED result. The ORCHESTRATOR runs this with
`wired_descend:true` (and the `m40_argv` override) against the FROZEN #40 0.7.0 CLI at the D-0077 fold; only if the
full ~200MB gate passes does the orchestrator flip project-level `tier1_accepted`. If the #40 CLI it is pointed at
cannot be driven into descend (or lacks a field a criterion needs), the harness records a `fold_reconciliation`
flag and REFUSES `tier1_accepted` (never a silent pass).
