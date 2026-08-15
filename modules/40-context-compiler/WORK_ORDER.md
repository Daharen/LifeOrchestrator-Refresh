# Work Order: Context Compiler (`context.compile`) 0.10.0 -- i56 PB-6 `compile_relevant_decisions` VERB (FANOUT_AGENT_002)

### i56 delta (D-0149, PB-6) -- NEW `compile_relevant_decisions` VERB, ADDITIVE (module semver 0.9.0 -> 0.10.0; `context_packet/0.2` schema/contract_version UNCHANGED -- this op emits no packet)
**Frozen governing doc:** `core-docs/research/2026-08-14-pb6-decision-record-schema.md` (s4 = this lane's
verb spec; the s8 hardened predicate in `research/2026-08-14-pb7-relayer-design-2.md` is AUTHORITATIVE
over the doc's own s4 naive rule). This is the FANOUT_AGENT_002 (i56) lane of PB-6 -- the retrieval-verb
half of a D-0077 producer/consumer split; FANOUT_AGENT_001 (lane A, a separate parallel worker) owns the
producer that ingests `DECISION_LOG.md` into `record_kind=decision` #36 records. A NEW `op` key
(`compile_relevant_decisions`) in the SAME `context_compiler.py`/`skill.json` -- `compile`/`normalize`/
`expand` are byte-for-byte UNCHANGED (proven: the owned suite re-runs 322/322 + 32/32 + 34/34 + 42/42,
zero re-baselines). Full interpretation: `SCHEMA_NOTES.md` **s21**.

Compiles `{modules[], planes[], recency_window, action_class?, query_text?}` into a bounded top-k
task-relevant `current` decision set (supersession-aware, current-only default) plus the
ALWAYS-included standing-constraint ROOT view (rule 3: pinned root synopsis + child-category pointers +
an asserted COUNT that survives any budget cut via a `deeper:*:prohibition` spill, never a silent drop
or compression). Implements the s8 hardened predicate as deterministic code (rule 1 binding_scope
exemption / rule 2 demote-on-enforcement / rule 4 `partially_superseded_by` conservative retention /
rule 5 per-commit `ingested_through` currency degrade to `currentness=stale`); routes ordinary-decision
RANKING through #37's canonical `selpol_rrf_v1` (P1-1/D-0089 reuse -- NO new retrieval architecture),
while decision CURRENCY stays this domain's own s8 rules (selpol is not re-asked to adjudicate a
vocabulary it doesn't have). Global/full-history questions (C4) short-circuit to a slow-path marker
before any pool load. Off-machine, this worker's own session has no lane-A-produced #36 catalog, so
build+test runs entirely against an injected `decision_pool` fixture (a standing_prohibition, a
gate-enforced invariant, a partial-supersession pair, a full-supersession control, and a stale-
`ingested_through` case) -- a real build-time bug (a display-dedup collision that silently dropped one
side of a partial-supersession pair -- exactly an F3 failure) was caught by this worker's own F3 gate
and fixed by carrying each record's `source_span` into its selpol hit. **Gate:**
`tests/test_i56_compile_relevant_decisions.py` 30/30 (F1 asserted-count-survives-budget, rule-2
demote-on-enforcement, F3 partial-supersession survival, F4 stale-currency degrade, C4 slow-path,
double-run + pool-order-independent byte-identity, empty/absent-pool fail-soft, OPS-surface +
existing-op regression) + the UNCHANGED owned suite (460/460 total). **Deferred (flagged, not claimed
done):** the -Live `catalog_db_path` path through a REAL #36 catalog is UNPROVEN in this session (no
lane-A catalog exists here) -- the real producer -> #36 -> verb seam is the orchestrator's D-0077 fold
smoke (frozen contract s5), per the FANOUT_AGENT_002 brief's rails. **Non-goals:** no PB-6 producer
(lane A); no `recency_window` hard filter yet (accepted + echoed, not load-bearing); no
`deeper:*:prohibition` cold-query resolution (the verb emits the pointer only); no core-doc edits
(`docs:[]`); no #36/#37 change (imported READ-ONLY).

**Contract targeted:** `CONTEXT_PACKET_CONTRACT.md` `context_packet/0.2` with **s4 PINNED (D-0089)** + the
**i32 amendment (D-0092)** + the **i33 amendment (D-0096)** + the **i34 amendment (D-0098)** +
`MEMORY_CONTRACT.md` A2/A3/A4/A5/**A6** + `MEMORY_ARCHITECTURE.md` s5/s6/s9 · **Author:** HIERARCHY-PORT-i35
(2026-08-05) · **Roadmap entry:** `MODULE_ROADMAP.md#40-context-compiler` · **Wave:** i35 (plan
`fo-35-0a5bf334`) · **Supersedes:** the i34 0.6.0 build (SHORTLIST-DESCEND-i34, plan `fo-34-584fd656`).

### i35 delta (D-0100) -- WIRE the REAL hierarchy_port into #40's PUBLIC `-Retriever artifact_search` path, ADDITIVE over context_packet/0.2 (schema string UNCHANGED; semver 0.6.0 -> 0.7.0; contract_version 0.5 -> 0.7)
i34's `run_hierarchy_plan` ran ONLY via an INJECTED `args['hierarchy_port']` (the D-0077 fold adapter); with the
real `artifact_search` retriever the public compile was FLAT-only. i35 makes #40 CONSTRUCT a real
`ArtifactSearchHierarchyPort` over #36 artifact.search's SHIPPED authorization-bound ops (`MEMORY_CONTRACT` A6 H6:
`shortlist`/`descend`/`prune_verdict` + catalog) so the PUBLIC `-Retriever artifact_search` + DESCEND-class +
SCOPED compile runs the shortlist-and-descend plan for REAL. #36 is IMPORTED READ-ONLY by a resolved-portable path
and NEVER modified; an injected port still WINS (fold seam kept). Every i35 field is GATED on the port
constructing -> a flat/non-descend/unscoped/non-artifact_search/multi-namespace compile is BYTE-IDENTICAL to 0.6.
Full interpretation: `SCHEMA_NOTES.md` **s18**. **(a)** the real port + resolved-portable `_load_artifact_search`
(lazy; missing #36 -> flat-fallback, never a crash) + one pinned `tree_version`/`corpus_snapshot` per compile via
`policy_info` (assembled from #36 `hierarchy_status`). **(b)** `_maybe_build_artifact_search_port` gates on
retriever=artifact_search + `catalog_db_path` + descend query_class + a single enforced/non-empty effective
namespace + a current published hierarchy; the entrypoint now passes `catalog_db_path`; the flat search hits stay
as the recall-safe fallback. **(SEAM 1)** leaf HYDRATION -- #36 `descend` bare refs -> full evidence (source_chunk
via the SHIPPED `export_chunk_texts`; typed-record body via the Catalog `records` table by `record_version_id` --
the recorded reconciliation seam, no shipped by-ref body op); the port supplies the exact source bytes so
`resolve_excerpt` reproduces every excerpt deterministically (span sha256 == excerpt_hash). **(SEAM 2)**
PRUNE-CERTIFICATE composition from #36's per-term `prune_verdict` -- excludes ONLY when EVERY query term is provably
absent (no-false-negative, #36's own tokenizer); a bounded descriptor / stale synopsis NEVER prunes. **(V2-V5)**
kept green through the real port. **Gate:** `tests/test_i35_public_port.py` 32/32 (public-path constructed port
over a real #36 tree) + the i34 injected-port fold smoke 38/38 + the shipped suite 322/322. **Non-goals:** no #36/#37
change (READ-ONLY); no #40<->#42 working_memory wiring; no multi-channel router; no multi-namespace fusion; no
P0-1 suite / action-capable release; no model/vector/UI; no core-doc edits (`docs:[]`).

### i34 delta (D-0098) -- Tier-1 hierarchy shortlist-and-descend + SAFE PRUNING + retrieval completeness, ADDITIVE over context_packet/0.2 (schema string UNCHANGED; semver 0.5.0 -> 0.6.0)
CONSUMER-side PLAN over #36's authorization-bound `shortlist`/`descend` ops (`MEMORY_CONTRACT` A6 H6); #36 (Lane A)
is a PARALLEL producer, so off-machine #40 tests the PLAN over an injected `hierarchy_port` + the REAL #37 lib,
and the real-tree recall proves at the orchestrator D-0077 fold. Every i34 field is GATED on a plan running -> a
zero-node/flat/non-descend/unscoped compile is BYTE-IDENTICAL to 0.5. Full interpretation: `SCHEMA_NOTES.md`
**s17**. **(V1)** the multi-stage descend-decision (query_class stub -> global_synthesis/precedent_search route;
bounded B/D shortlist->descend->leaves->existing selpol/budget/packet; nodes route via `navigation_refs`, never
`evidence[]`). **(V2 P0)** SAFE PRUNING -- prune ONLY via a #36 channel-specific NO-FALSE-NEGATIVE certificate;
else expand/flat-fallback/`needs_expansion`|`abstain`; a stale synopsis never prunes; a bounded descriptor is
never a certificate. **(V3)** `retrieval_completeness` (a hierarchy MISS != proved ABSENCE). **(V4)** packet
identity += hierarchy_id + pinned tree_version + builder/prune/plan policy ids + the stage trace. **(V5)**
navigation-vs-evidence closure -- every nav-visible object `ns_permitted`-checked + fail-closed SANITIZED.
**Acceptance:** off-machine 322/322 (280 0.5 + 42 i34); flat byte-identity preserved; the `-Live`/real-tree
end-to-end recall DEFERRED to the orchestrator D-0077 hierarchy fold (#36 not yet shipped). skill.json
`0.5.0 -> 0.6.0`.

### i33 delta (D-0096) -- namespace closure + supersession hardening, ADDITIVE over context_packet/0.2 (schema string UNCHANGED; semver 0.4.0 -> 0.5.0)
Hardens the packet/selection half (full interpretation: `SCHEMA_NOTES.md` **s16**): **(U1')** SAFETY-CRITICAL
namespace CLOSURE -- `task_input.namespace` is a REQUEST not authorization; the compiler computes
`effective_allowed_namespaces = intersection(REQUEST, control_plane GRANT)` and passes THAT (never the raw
request) to selpol + the retriever, an EMPTY intersection FAILS CLOSED; the canonical `ns_permitted` (IMPORTED
from #37) scope-checks EVERY packet-visible object and a cross-namespace object ANYWHERE ABORTS SANITIZED
(count only; detail -> a privileged security log). **(U4')** candidate-INDEPENDENT supersession -- the
per-candidate CATALOG `effective_current` signal is passed to selpol (pool-independent hard-filter under
current_only); a supersession BRANCH -> `conflicted`. **(U2')** navigation vs evidence -- a
`candidate_role=navigation` node ROUTES (navigation_refs) but is NEVER answer-evidence; navigational staleness
never fails coverage. **(U3')** working_memory hardening -- CONTINUITY-authoritative + CONJUNCTIVE access
(task_id AND effective-namespace) + reserved A5 `state_version`/store fields (store is Tier 1). **(U5')**
query_class / temporal_intent SPLIT -- independent dimensions; explicit user time OUTRANKS the class default;
the versioned classifier map is IMPORTED (composite/unclassified fallback). Packet identity now COVERS
temporal_intent + the classifier policy id/version + the working-state state_version + the retrieval-plan/stage
trace. #40 IMPORTS #37's `selpol_rrf_v1` + `ns_permitted` + the versioned class->mode map READ-ONLY; off-machine
(#37 not yet at 1.2.0) #40 PREFERS the canonical + falls back to a marked SHIM (`selection.import_sources`).
Off-machine (cloud python importing the REAL #37 lib): **272/272** -- the selpol 1.2.0 NEW-behavior +
`-Live` legs are DEFERRED to the orchestrator D-0077 mixed-namespace fold. The i32/i31 scope below is retained
for reference (the i32 namespace model is SUPERSEDED by U1' above; the rest is hardened, not replaced).

### i33 acceptance criteria (a)-(g)
(a) `effective_allowed_namespaces = intersection(request, grant)` computed + passed both ways; an empty
intersection fails closed; EVERY packet-visible object scope-checked; a mixed-ns fixture proves NO cross-ns item
(evidence OR diagnostic) reaches the packet -- only a count. (b) catalog `effective_current` passed to selpol
(absent-successor superseded filtered at the fold); a branch -> `packet_disposition=conflicted`. (c)
`candidate_role` consumed (navigation routes, never answer-evidence); navigational staleness does not fail
coverage; provenance_mode honored. (d) `working_memory` continuity-authoritative + conjunctive access +
`state_version` in packet identity; NO store built. (e) query_class/temporal_intent split with explicit-time
override; versioned `classifier_policy` imported; packet identity covers it all. (f) imports selpol (`ns_permitted`
+ versioned map) READ-ONLY; P0-1 three-region + `non_execution:true` + P0-3 + P0-4 + P1-5 + A2 stay green;
GATE TEST 3 (provenance-expansion + sanitized-abort on a namespaced fixture) passes; deterministic packet_id.
(g) a #40-side test proving #40's selection == a direct `selpol_rrf_v1.select(...)` on the same candidates +
new params. skill.json `0.4.0 -> 0.5.0`; SCHEMA_NOTES s16 records every A5/i33 interpretation.

---

## i31 scope (retained for reference)

### Problem being solved
i30 shipped `context_packet/0.2` with the s4 selection-policy interface consumed via an in-module
`selpol_reference.py` (rank-RRF-primary). The D-0077 fold caught #40's reference and #37's canonical
`selpol_rrf_v1` selecting DIFFERENTLY (neither a defect -- s4 had frozen the interface + stages but not the
scoring). D-0089 PINS the s4 scoring as #37's canonical (raw-fused-score-primary composite + AUTHORITY_RANK/
freshness ranks + greedy source-MMR + occurrence-preserving display dedup) and requires **one selection
owner**: #40 RETIRES `selpol_reference.py` and IMPORTS #37's canonical library directly. The packet schema
is unchanged (`context_packet/0.2`); only the selection SOURCE changes. **P0-1 stays a HARD GATE** -- the
hard-filter authority is the control plane, never an evidence field; `non_execution:true` remains mandatory.

### Immediate practical use
The orchestrator feeds this compiler's REAL packets into retrieval.eval #37 0.2 + a fresh 9B at the D-0077
fold, and wires #37's canonical `selpol_rrf_v1` behind the s4 interface (asserting byte-identical
selection). A later read-only Collective Agent slice (Priority 8) calls `compile` per task and `expand` on
demand -- but never side-effects while `non_execution` is true.

### Explicit scope (in) -- governed by CONTEXT_PACKET_CONTRACT s1-s8 + MEMORY_CONTRACT s3/s5/A2
1. **P0-1 (SAFETY-CRITICAL) three-region packet** -- `control_plane` (descriptor authority fields ONLY,
   NEVER from retrieval) / `task_input` (requested side effects are requests, not authorization) /
   `evidence` (content_role=evidence, can_instruct=false, trust_domain, epistemic_authority, provenance).
   A STRUCTURAL guarantee (control_plane cannot be populated by a retrieved record) + `non_execution:true`
   + a rendering contract + an injection unit test.
2. **P0-3 `packet_disposition`** (answerable|needs_expansion|abstain|conflicted|provenance_failed) from
   evidence_requirements/coverage/missing/contradictions; answer ONLY when answerable; conservative while
   the vector channel is empty.
3. **P0-4 `consumer_profile` + exact transport accounting** -- count on the FINAL RENDERED input,
   count_method + count_is_exact=false, fail-closed transport (drop to omission_manifest, never truncate
   control_plane/completion_contract/a required citation).
4. **P1-1 / D-0089 -- one selection owner.** RETIRE `selpol_reference.py`; IMPORT #37's canonical
   `selpol_rrf_v1` by a resolved portable path; build `params.hard_filter` from
   `control_plane.permission_grants` (+ descriptor forbidden/privacy), NEVER from an evidence field; pass
   `dedup_display=True`, no library budget; consume the canonical additive output (hit copies +
   `selection_rank`/`selection_score`/`selection_policy_id`/`reason_codes`/`rrf_score`/`retrieval_occurrences`
   + `omission_manifest` + `stages`); REGENERATE fixtures to the canonical selection; a #40-vs-direct-`select()`
   byte-identity test (D-0077).
5. **P0-2 provenance modes** (A2 hash names + direct_span|derived_record|aggregate|tombstone, per-mode
   validation; a provenance failure -> packet_disposition=provenance_failed).
6. **P1-5 identity + snapshot + expansion lineage** -- distinct ids; ONE corpus_version per compile (abort
   on drift); omitted_context -> omission_manifest; `expand` -> an immutable context_expansion/0.2 delta
   with a LOCKED snapshot + depth bound.
7. **A3 skill-summary refs** -- recognise record_kind=summary + summary_type=skill_activation_card as skill
   candidates.
8. Extend `evaluation_hooks` (per-stage + packet_disposition + the P0-1 read-only injection probe).

### Non-goals (out -- do NOT build)
ANY change to #37's `selpol_rrf_v1` or its eval (import READ-ONLY; if the canonical genuinely cannot serve
#40's packet-build, STOP + report a fold reconciliation naming the exact gap -- do NOT edit #37); pure-rank-RRF
as the PRIMARY sort (the deferred P1-2); near-dup-algorithm calibration (P1-3); the eval harness/metrics (#37);
real embeddings / vector search (vector channel may be null); the retriever/catalog DB (#36); the skill-CARD
generator (#41 -- carry summary refs only); the 9B / ANY model; the FULL P0-1 adversarial injection SUITE +
the action-capable gate release (a later wave -- keep the STRUCTURAL separation + a basic injection test); UI.
Do NOT touch model modules / models.json or any core-doc (`docs:[]`).

### Dependencies
Modules: artifact.search #36 (the real retriever-0.2 `search` seam on `-Live`); retrieval.eval #37 (the s4
`selpol_rrf_v1` owner -- consumed via the frozen interface + a reference impl, wired at fold); res.lease
#29 (git lease around dev.ship). Contract features: CONTEXT_PACKET_CONTRACT s1-s8; MEMORY_CONTRACT s1
envelope + A2, s3 retriever-0.2 hit, s5 staleness enum. Tools: `pwsh>=7.4`, `python>=3.8` (stdlib only).
Models: none.

### Skill contract requirements
`skill_id=context.compile`, `version=0.3.0`, `contract_version=0.3`, `determinism=deterministic`,
`parallel_safe=true`, `batch=false`, `streaming=false`, `confidence=null`, empty `model_provenance`.
Artifact kinds: `json` (`context_packet.json` / `context_expansion.json`) + `text` (`rendered_input.txt`).

### Inputs and outputs
See `skill.json` (inputs) + `SCHEMA_NOTES.md` (the packet/expansion/selection shapes). Ops: `compile`
(default), `normalize`, `expand`.

### Proposed implementation
Python (stdlib only) for ALL packet logic (sidesteps the pwsh-7.4.6 determinism traps); selection is
DELEGATED to #37's canonical `selpol_rrf_v1`, imported by a resolved portable path (`_load_canonical_selpol`
resolves `../37-retrieval-eval/lib/selpol_rrf_v1.py` from `__file__`; `LIFEORCH_SELPOL_PATH` overrides;
fail-closed if missing). A thin pwsh entrypoint wraps it and owns the retriever seam (mock fixture
off-machine; real #36 on `-Live`).

### Tests
- **Off-machine:** `python tests/context_compiler_tests.py` (162 assertions covering acceptance a-g,
  importing the REAL #37 canonical `selpol_rrf_v1`, incl. the #40-vs-direct-`select()` byte-identity) +
  `pwsh tests/Invoke-ContextCompilerTests.ps1` (entrypoint end-to-end, mock retriever).
- **Through the executor (`-Live`):** ingest a bounded core-docs slice via #36, then
  `pwsh tests/Invoke-ContextCompilerTests.ps1 -DbPath <catalog.db> -RepoRoot <repo>` (real retriever-0.2).

### MVP acceptance criteria (a)-(g)
(a) three regions structurally separated + a passing injection unit test (evidence with imperative text
cannot populate control_plane / alter completion_contract / change skill selection); (b) packet_disposition
correct across answerable / needs_expansion / abstain / conflicted / provenance_failed fixtures; (c)
consumer_profile + count_is_exact=false + fail-closed transport (oversize evidence -> omission_manifest,
disposition=needs_expansion, control_plane + completion_contract intact); (d) selection via #37's CANONICAL
`selpol_rrf_v1` (imported; policy_version 1.0.0; the 6 stages) with the additive fields + retrieval order
preserved; (e) #40's selection == a DIRECT `selpol_rrf_v1.select()` on the same candidates (the D-0077
byte-identity); (f) provenance modes present + each direct_span excerpt reproduces its source bytes; (g)
byte-identical on re-run (deterministic packet_id covering the identity fields) + `non_execution:true`
present; `selpol_reference.py` DELETED + no residual code import. `-Live`: the real #36 retriever over a
core-docs slice for >=3 LO benchmark questions -> required spans present + provenance-valid; `expand`
returns a bounded immutable delta with a locked snapshot.

### Documentation requirements
`README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json` +
`SCHEMA_NOTES.md` (the D-0077 fold contract, recording EVERY 0.2 interpretation).

### Registry / state updates
`docs:[]` -- the worker reports; the ORCHESTRATOR mirrors `CURRENT_STATE.md` / `MODULE_ROADMAP.md` /
`TOOL_MODEL_REGISTRY.md` at fold and wires #37's canonical selpol library.

### Known follow-on work
The FULL P0-1 adversarial injection SUITE + the action-capable gate release; P1-2/P1-3 selection
calibration (score comparability, near-dup algorithm); the real 9B tokenizer (retire the ceil(chars/4)
upper bound -> count_is_exact=true); richer skill-card fields + three-valued eligibility (P1-6); the shared
cross-module fixture; a FULL context_packet/0.2 freeze.

### STOP conditions
Scope would exceed the list above; a dependency is missing/broken; the contract lacks something needed
(stop + propose an amendment via CONTEXT_PACKET_CONTRACT s0, do not freelance); MVP acceptance met -- stop;
do not start the next module.
