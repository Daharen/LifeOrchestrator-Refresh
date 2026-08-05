# Work Order: retrieval.eval -- 0.7.0 -> 0.8.0 (i36 WIRED-DESCEND drive, the Tier-1 flip harness half)

**Contract version targeted:** 0.7 (schema UNCHANGED) · **Author:** FANOUT_AGENT_001 (REHEARSAL-WIRE-DESCEND-i36) / 2026-08-05 ·
**Roadmap:** i36 Tier-1 ACCEPTANCE wave lane A (plan `fo-36-1a676e4b`; D-0100; governing `MEMORY_ARCHITECTURE` s10 +
`CONTEXT_PACKET_CONTRACT` i34 s7 + `MEMORY_CONTRACT` A6). Predecessor: 0.7.0 (REHEARSAL-HARNESS-i35).

### Problem being solved (i36)

i35 shipped the RUNNABLE rehearsal but it measured NAVIGATION via #36's own `shortlist`/`descend` and compiled #40
packets FLAT (the #40 CLI was flat-only before i35 Lane A). i35 Lane A (#40 0.7.0, `aa2f0fb`) WIRED the real
`ArtifactSearchHierarchyPort` into #40's PUBLIC `-Retriever artifact_search` path. This revision makes the harness
DRIVE that WIRED descend path end-to-end so the ORCHESTRATOR can run the full ~200MB gate against #40 0.7.0 at fold
and flip project-level `tier1_accepted`.

### Scope (in) -- touch ONLY `modules/37-retrieval-eval` (ADDITIVE + OPT-IN); #40 is READ-ONLY via the adapter

- A WIRED-DESCEND drive path (`compile_packet_wired` + the wired labeled/scale/stale measurements) gated behind
  `req.wired_descend`; construct #40 descend-triggering requests (keys from #40 SCHEMA_NOTES s18, never guessed);
  invoke via the overridable adapter `m40_argv`; MEASURE s10 against the WIRED packets incl. sub-linear nav from
  #40's OWN plan trace + dual recall / regret / fallback-frequency / stale-window.
- The `#36-direct-nav + #40-flat` path RETAINED as a LABELED baseline (descend-vs-flat deltas). The non-wired path
  stays BYTE-IDENTICAL to 0.7.0 (skeleton digest pinned).
- **Version:** `skill.json` 0.7.0 -> 0.8.0 / contract 0.7 (unchanged); `SCHEMA_NOTES.md` s17 (every i36
  interpretation, for the fold); `FULL_CORPUS_RECIPE.md` s5a/s6 (the WIRED invocation + `m40_argv` override).

### Acceptance (i36) -- see `SCHEMA_NOTES.md` s17 + `test_rehearsal_eval` (55/55; the `test_wired` 11-criterion gate)

(a) a WIRED-descend drive path triggering #40 0.7.0's port via the adapter; (b) s10 measured against WIRED packets
incl. sub-linear nav from #40's own trace + dual recall/regret/fallback/stale-window; (c) the flat baseline retained
+ labeled; (d) FULL_CORPUS_RECIPE updated; (e) `tier1_accepted` harness-computed, NOT a project claim; (f) shipped
0.7.0 eval/hierarchy/rehearsal tests GREEN, the non-wired path byte-identical, eval/skill 0.7.0 -> 0.8.0.

---

# Work Order: retrieval.eval -- 0.6.0 -> 0.7.0 (i35 REHEARSAL-HARNESS, the Tier-1 acceptance gate)

**Contract version targeted:** 0.7 · **Author:** FANOUT_AGENT_002 (REHEARSAL-HARNESS-i35) / 2026-08-05 ·
**Roadmap:** i35 CONSUMER WIRING lane B (plan `fo-35-0a5bf334`; D-0090/D-0098/D-0077; governing
`MEMORY_ARCHITECTURE` s10 + `MEMORY_BENCHMARK` + `CONTEXT_PACKET_CONTRACT` i34 s7 + `MEMORY_CONTRACT` A6/s7).
Predecessor: 0.6.0 (HIERARCHY-EVAL-i34).

### Problem being solved (i35)

i34 SCAFFOLDED + FLAGGED the ~200MB real-corpus rehearsal as the OPEN pre-freeze/pre-activation gate and reported
`tier1_accepted=false` on synthetic-only (synthetic scale is necessary, NOT sufficient). This revision turns that
scaffold into a RUNNABLE Tier-1 acceptance-gate harness: INGEST a REAL FOREIGN corpus slice into a #36 hierarchy,
run a MANUALLY-LABELED query set, MEASURE the s10 criteria against #36/#40 driven READ-ONLY via the external_command
adapter seam, and emit a computed `tier1_accepted` -- so the orchestrator can run the full gate vs Lane A's WIRED
#40 CLI at fold and own the project-level flip.

### Scope (in) -- touch ONLY `modules/37-retrieval-eval` (ADDITIVE)

- **NEW `rehearsal_eval.py`** (op `rehearsal`): the adapter seam (real #36/#40 as subprocess), corpus ingest +
  build-hierarchy, the labeled-query correctness pass, the scale sweep (bounded cost + sub-linear navigation),
  the s10 criteria + a computed `tier1_accepted`, canonical `rehearsal_report.json`
  (`lifeorch.rehearsal_eval_report/0.1`) + `.md` + `worker-summary.json`. IMPORTS `hierarchy_eval` helpers (that
  file stays byte-identical).
- **NEW committed real foreign corpus SAMPLE** `tests/fixtures/rehearsal-corpus/**` (BSD `click 8.1.7` slice +
  `LICENSE.rst` + `MANIFEST.json` [per-file sha256 + digest]); **NEW `tests/fixtures/rehearsal-benchmark.json`**
  (manually-labeled queries, all 5 kinds, pinned outcomes); **NEW `tests/fixtures/rehearsal-temporal-records.json`**
  (a controlled supersession pair for the temporal criterion); **NEW `FULL_CORPUS_RECIPE.md`** (hash-verified
  ~200MB fetch/prep recipe).
- **NEW `tests/test_rehearsal_eval.py`** (off-machine deterministic gate, 34 checks) + a `-Op rehearsal` branch in
  the wrapper (isolated; the benchmark + hierarchy-eval paths unchanged) + rehearsal checks appended to
  `tests/Invoke-RetrievalEvalTests.ps1`.
- **Version:** `skill.json` 0.7.0 / contract 0.7; `SCHEMA_NOTES.md` s16 (every i35 interpretation, for the fold),
  this WORK_ORDER, README.

### Acceptance -- the s10 criteria (a)-(e) + dual recall each a deterministic threshold; `tier1_accepted` computed
over the pointed corpus+CLI (NOT a project claim); a `fold_reconciliation` flag REFUSES acceptance on an absent
#36/#40 field. `hierarchy_eval.py` + `retrieval_eval.py` + `lib/*` BYTE-IDENTICAL (regression); the deterministic
sample path byte-identical on re-run (pinned `report_digest`). Off-machine FIRST (real portable #36/#40 cores),
then `-Live` on the executor.

---

# Work Order: retrieval.eval -- 0.4.0 -> 0.5.0 (selpol_rrf_v1 1.2.0 + eval-0.5, i33 NAMESPACE-CLOSURE)

**Contract version targeted:** 0.5 · **Author:** FANOUT_AGENT_002 (RETRIEVAL-EVAL-PREDICATE-i33) / 2026-08-04 ·
**Roadmap:** i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING, CPU lane B (plan fo-33-d7b55e46; D-0096
MEMORY_CONTRACT A5 + CONTEXT_PACKET_CONTRACT i33 amendment). Predecessor: 0.4.0 (RETRIEVAL-EVAL-SELPOL-TIER0-i32).

### Problem being solved (i33)

The frontier Tier-0 red-team (`159e9cb5`, `research/2026-08-04-tier0-amendment-redteam.md`) found the i32
amendments were a correct ENVELOPE-level FIRST layer but INCOMPLETE: namespace was only an envelope filter
(derived-record / diagnostic-metadata leakage; per-hop gaps) and supersession was candidate-set-DEPENDENT (a
predecessor stayed `current` when its successor was absent). As the SELECTION-POLICY + NAMESPACE-PREDICATE OWNER,
this revision authors the ONE canonical namespace predicate + rejection policy, makes supersession
candidate-INDEPENDENT, and splits `query_class` from `temporal_intent`. #40 IMPORTS the predicate + the class-map;
the orchestrator runs the D-0077 mixed-namespace LEAKAGE-path smoke at fold.

### Scope (in) -- touch ONLY `modules/37-retrieval-eval`

- **NEW `lib/namespace_policy.py`** (U1' / A5 risk-6): `ns_permitted` (closed-set membership; no wildcard/prefix/
  parent/shared/all; empty/None -> reject) + `effective_allowed_namespaces` (intersection(request, grant)) +
  `NamespaceRejectionPolicy` (violation_count + privileged security_log + sanitized caller_summary). The ONE owner
  #36 + #40 import.
- **NEW `lib/classifier_policy.py`** (U5'): versioned `CLASS_TO_TEMPORAL_INTENT` map (9 classes + `composite` +
  `unclassified`) + `resolve_temporal_intent` where an explicit user temporal_intent/version OUTRANKS the class.
- **`lib/selpol_rrf_v1.py` 1.1.0 -> 1.2.0** (additive; 1.1.0-default byte-identical): namespace CLOSURE via the
  canonical predicate + a sanitized DROP (no leak in any diagnostic array); candidate-INDEPENDENT supersession via
  the catalog `effective_current` boolean (pool-independent `hard_filter_stale`) + catalog-ref demote + branch
  `conflicted`; the query_class/temporal_intent split via `classifier_policy`. `POLICY_VERSION 1.2.0`.
- **eval 0.4 -> 0.5:** `selection_conformance` extended to MEASURE the leakage paths + NEW `benchmark5.json`
  fixture; report schema `/0.5`; `skill.json` 0.5.0 / contract 0.5. Every shipped RAW/reranked/packet metric VALUE
  preserved; all report SHA + input_digest pins re-computed.
- **Docs:** `SCHEMA_NOTES.md` s15 (every A5/i33 interpretation, for the fold), this WORK_ORDER, README.

### Acceptance -- see `SCHEMA_NOTES.md` s15; the selpol unit suite (`tests/test_selpol.py`, s15-21) + the pwsh
suite (`tests/Invoke-RetrievalEvalTests.ps1`, benchmark4 + benchmark5 sections) prove U1'/U4'/U5' + the 1.1.0
byte-identity regression.

---

# Work Order (historical): retrieval.eval -- 0.3.0 -> 0.4.0 (selpol_rrf_v1 1.1.0 + eval-0.4, i32 Tier-0 seams)

**Contract version targeted:** 0.4 · **Author:** FANOUT_AGENT_002 (RETRIEVAL-EVAL-SELPOL-TIER0-i32) / 2026-08-04 ·
**Roadmap:** i32 Tier-0 MEMORY-ARCHITECTURE seam repairs, CPU lane B (plan fo-32-0fb25203; D-0092
CONTEXT_PACKET_CONTRACT i32 amendment + MEMORY_CONTRACT A4). Predecessor: 0.3.0 (SELECTION-POLICY-i30 / SETTLE-i31).

### Problem being solved (i32)

Tier 0 makes `namespace` a HARD retrieval/partition boundary, `current_only` a real retrieval MODE with
supersession-aware ranking, keeps the retriever channel set OPEN, and adds a query-classification seam. As the
SELECTION-POLICY OWNER, this revision folds those into `selpol_rrf_v1` (1.0.0 -> 1.1.0, ADDITIVE) and scores them
(eval 0.3 -> 0.4). #40 IMPORTS the library; the orchestrator runs the D-0077 selpol byte-identity smoke at fold.

### Scope (in) -- touch ONLY `modules/37-retrieval-eval`

- **`lib/selpol_rrf_v1.py` 1.0.0 -> 1.1.0** (additive stages): (U1) stage-1 `hard_filter_namespace` +
  soft-project-bonus retirement (conditional on `allowed_namespaces`); (U4) `current_only` HARD `hard_filter_stale`
  + `prefer_current` soft relocation + a rank-affecting `superseded_demote` (stable topological reorder) +
  `contradicts` propagation (`contradicts_pairs[]`); (U5) `query_class` -> temporal mode (Tier-0 stub) + OPEN
  channels (`retrieval_occurrences[]` honored channel-agnostically). `POLICY_VERSION 1.1.0`; a 1.0.0-default call
  is BYTE-IDENTICAL (regression-pinned). New reason_codes fold in additively; `STAGES` -> 8.
- **eval 0.3 -> 0.4:** a `selection_conformance` block measuring namespace isolation / current_only correctness /
  supersession ordering / reason-code coverage (integer-only, deterministic) + NEW `benchmark4.json` fixture;
  report schema `/0.4`; `skill.json` 0.4.0 / contract 0.4. Every shipped RAW/reranked/packet metric VALUE preserved.
- **Docs:** `SCHEMA_NOTES.md` s14 (every i32 interpretation, for the fold), this WORK_ORDER, README.

### Acceptance -- see `SCHEMA_NOTES.md` s14; the selpol unit suite (`tests/test_selpol.py`) + the pwsh suite
(`tests/Invoke-RetrievalEvalTests.ps1`, benchmark4 section) prove U1/U4/U5 + the 1.0.0 byte-identity regression.

---

# Work Order (historical): retrieval.eval -- 0.2.0 -> 0.3.0 (selpol_rrf_v1 + eval-0.3)

**Contract version targeted:** 0.3 · **Author:** FANOUT_AGENT_002 (SELECTION-POLICY-i30) / 2026-08-03 ·
**Roadmap:** Wave 3 CONTRACT-HARDENING, CPU lane (plan fo-30-dd453156; D-0087 CONTEXT_PACKET_CONTRACT s4 +
MEMORY_CONTRACT A2/A3; P1-1). Predecessor: 0.2.0 (RETRIEVAL-QUALITY-i29, plan fo-29-87dbfa0b).

### Problem being solved

Two selection implementations diverged: #37 shipped a standalone deterministic `rerank()`; #40 shipped a
self-contained composite score. The frontier Wave-3 red-team's **P1-1** requires exactly ONE versioned
deterministic selection-policy library, OWNED by #37 and CONSUMED by #40 + #37's own eval A/B. This revision
authors that library (`selpol_rrf_v1`) extracted from `rerank()`, and refines the eval harness to score
per-stage + `packet_disposition` (the P1-4 subset i30 needs).

### Explicit scope (in) -- touch ONLY `modules/37-retrieval-eval`

- **`lib/selpol_rrf_v1.py`** -- the s4 interface `select(candidates, descriptor, policy_id, params) ->
  {selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[]}`. PURE +
  deterministic (stdlib). Stages: hard filters -> temporal stale-demote (s5) -> authority (epistemic_authority)
  -> versioned RRF over CHANNEL RANKS (retrieval_occurrences[]; P1-2) -> occurrence-preserving DISPLAY dedup
  (identical text -> one display item + occurrences[] + evidence_cluster_id; P1-3) -> budget. Output ADDITIVE:
  preserves retrieval_rank/lexical_rank/vector_rank/fused_rank; adds selection_rank/selection_score/
  selection_policy_id/selected/reason_codes; NEVER re-sorts the retrieval array in place.
- **Adopt it in the harness:** `rerank()` becomes a thin wrapper over `selpol_rrf_v1` (the measured A/B measures
  the library). The shipped 0.2 benchmark + reranker A/B stay GREEN (regression -- metric VALUES byte-preserved).
- **Eval refinement (P1-4 subset):** score PER STAGE (raw / post-filter / packet) + `packet_disposition`
  correctness (read from a supplied #40 packet or computed deterministically); mark hybrid metrics
  `not_applicable` (NOT zero) while the vector channel is EMPTY. Full graded-relevance P1-4 is a named follow-on.
- Fixtures proving the library RESCUES a required source out of raw top-K + DEMOTES a stale/forbidden hit (A/B
  delta) PRESERVING retrieval_rank, and occurrence-preserving dedup (identical text -> one display item,
  occurrences kept).

### Non-goals (out -- do NOT build)

The context compiler #40 (consume its packets at fold only); real embeddings / a vector index / real vector
search (the vector channel stays scaffolded but EMPTY); a MODEL-based reranker (deterministic only); the FULL
P1-4 metric set / judged relevance grades (follow-on); P1-2/P1-3 calibration beyond the frozen rank-RRF +
occurrence-dedup baseline; the retriever/catalog #36; skill cards #41; a production router; UI. No model / CUDA
/ network; do NOT touch model modules / models.json.

### Skill contract requirements

`skill_id retrieval.eval`, `version 0.3.0`, `contract_version 0.3`, `determinism deterministic`,
`parallel_safe true`, `batch false`, `streaming false`. `confidence` = null; `model_provenance` = [];
artifact kinds `json` + `markdown`. Report schema `lifeorch.retrieval_eval_report/0.3`.

### Tests

- **Off-machine (cloud python):** `tests/test_selpol.py` (library-direct unit suite: s4 interface, purity,
  determinism, additive output, rescue+demote preserving retrieval_rank, RRF over channel ranks,
  occurrence-preserving dedup, budget) + the worker over every fixture (double-run byte-identical). pwsh in the
  cloud is absent, so the full pwsh harness runs on `-Live`.
- **`-Live` (Windows executor):** `tests/Invoke-RetrievalEvalTests.ps1` -- AST + py_compile gates (incl.
  `lib/selpol_rrf_v1.py` + `tests/test_selpol.py`), the library-direct unit suite, manifest (0.3.0) + envelope
  validation, the KNOWN 0.1/0.2 metric VALUES PRESERVED (regression), the eval-0.3 selpol packet benchmark
  (occurrence dedup, budget -> needs_expansion, packet_disposition 5/6), pinned canonical shas + double-run
  identity, the additive selection fields, hybrid not_applicable, fail-closed error envelopes, the Module 1
  wrapper; plus a real core-docs slice via the real #36 retriever-0.2. Asserts cross-env canonical-hash parity,
  0 orphaned llama-server/python, `review_queue.jsonl` before == after.

### MVP acceptance criteria

- [x] `selpol_rrf_v1` DETERMINISTIC + PURE (byte-identical selection on re-run); signature EXACTLY matches s4.
- [x] A test where the library RESCUES a required source out of raw top-K AND DEMOTES a stale/forbidden hit
      with the A/B delta reported, PRESERVING retrieval_rank (mock2 mq-b/mq-d + test_selpol).
- [x] Occurrence-preserving dedup (identical text -> one display item WITHOUT losing occurrences)
      (benchmark3 d1 + test_selpol).
- [x] The shipped 0.2 benchmark + reranker A/B stay GREEN (regression); reports byte-identical on re-run.
- [x] Per-stage metrics + packet_disposition scoring compute with KNOWN fixture values (benchmark3).
- [ ] `-Live` over a real core-docs slice via the real #36 retriever 0.2 (filled at ship).

### Documentation

`README.md` + `skill.json` (0.3.0) + `SCHEMA_NOTES.md` (D-0077: every interpretation) + `examples/` -- updated.

### Registry / state updates

Worker holds `docs:[]`: the ORCHESTRATOR mirrors + folds all core-docs from this worker's report. This worker
edits NO core-doc.

### STOP conditions

- Acceptance met -> stop; do not build #40, an embedder, a model reranker, or `artifact.search`.
- docs:[] -> never edit a core-doc; report and let the orchestrator fold.

## i34 Lane B -- HIERARCHY-EVAL (D-0098, plan fo-34-584fd656): SHIPPED 0.5.0 -> 0.6.0

Brief: `core-docs/fanout/FANOUT_AGENT_002.md`. Governing: `CONTEXT_PACKET_CONTRACT` i34 s7 + `MEMORY_CONTRACT`
A6 + `MEMORY_ARCHITECTURE` s10 + `research/2026-08-04-i34-hierarchy-design-redteam.md`.

**Delivered (ADDITIVE; `retrieval_eval.py` + `lib/*` UNCHANGED -> the shipped benchmark path is byte-identical):**
`hierarchy_eval.py` (a self-contained deterministic worker: a synthetic bounded-fanout hierarchy model with
SAFE-PRUNING + generations/CAS + shortlist/descend; the measures; the adversarial fixtures; the Tier-1 gate set;
the rehearsal scaffold; the external_command fold seam) + `-Op hierarchy-eval` in the wrapper (an isolated branch)
+ `tests/test_hierarchy_eval.py` (26 pinned checks) + hierarchy checks appended to
`tests/Invoke-RetrievalEvalTests.ps1` + skill/contract 0.6.0/0.6.

**Verification:** navigation-cost sub-linear across >=2 orders of magnitude (p50 2..6, ratio/leaf strictly
decreasing), DUAL recall (fast-beam 25% / guaranteed 100% / packet 100%), 5/5 adversarial fixtures, 11/11 Tier-1
gates across 5 dimensions, rehearsal gate OPEN (Tier-1 NOT accepted on synthetic-only), deterministic
byte-identical, all shipped eval tests regression-green (report shas unchanged).

**Non-goals (this wave):** the #36 node/tree builder + shortlist/descend; the #40 plan / retrieval_completeness
emission (MEASURED, not built); the working-memory store; the router; real embeddings/vector; the 9B. Measure
#36/#40 via the external_command adapter; the REAL wiring + the ~200MB rehearsal are the D-0077 fold / a later wave.
