# Work Order: Context Compiler (`context.compile`) 0.2.0 -- i30 CONTRACT-HARDENING

**Contract targeted:** `CONTEXT_PACKET_CONTRACT.md` `context_packet/0.2` (D-0087) + `MEMORY_CONTRACT.md`
A2/A3 · **Author:** CONTEXT-COMPILER-i30 (2026-08-03) · **Roadmap entry:**
`MODULE_ROADMAP.md#40-context-compiler` · **Wave:** i30 (plan `fo-30-dd453156`)

### Problem being solved
The i29 `context_packet/0.1` shipped read-only but the frontier Wave-3 design red-team returned NO-GO on
freezing the contract: a deterministic, under-budget, provenance-shaped packet could look fully
authoritative even when injected or incomplete. i30 conforms #40 to the hardened `context_packet/0.2`,
folding the P0-1..P0-4 + P1-1 + P1-5 blockers (+ MEMORY_CONTRACT A2/A3) so the packet is the SAFE,
self-describing working set the coordinator hands a disposable model. **P0-1 is a HARD GATE before any
side-effecting integration** -- until it is enforced structurally AND proven adversarially,
`non_execution:true` is mandatory and only read-only compile/eval consume the packet.

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
4. **P1-1 consume `selpol_rrf_v1`** via the s4 `select(...)` interface (retire the i29 composite score);
   additive selection fields preserve the retrieval order.
5. **P0-2 provenance modes** (A2 hash names + direct_span|derived_record|aggregate|tombstone, per-mode
   validation; a provenance failure -> packet_disposition=provenance_failed).
6. **P1-5 identity + snapshot + expansion lineage** -- distinct ids; ONE corpus_version per compile (abort
   on drift); omitted_context -> omission_manifest; `expand` -> an immutable context_expansion/0.2 delta
   with a LOCKED snapshot + depth bound.
7. **A3 skill-summary refs** -- recognise record_kind=summary + summary_type=skill_activation_card as skill
   candidates.
8. Extend `evaluation_hooks` (per-stage + packet_disposition + the P0-1 read-only injection probe).

### Non-goals (out -- do NOT build)
#37's CANONICAL selpol library (consume the interface + a reference stub; the fold wires the real lib);
the eval harness/metrics (#37); real embeddings / vector search (vector channel may be null); the
retriever/catalog DB (#36); the skill-CARD generator (#41 -- carry summary refs only); the 9B / ANY model;
the FULL P0-1 adversarial injection SUITE + the action-capable gate release (a later wave -- ship the
STRUCTURAL separation + a basic injection test); the P1-2/P1-3 selection calibration beyond the frozen
rank-RRF + occurrence-dedup baseline; UI. Do NOT touch model modules / models.json or any core-doc
(`docs:[]`).

### Dependencies
Modules: artifact.search #36 (the real retriever-0.2 `search` seam on `-Live`); retrieval.eval #37 (the s4
`selpol_rrf_v1` owner -- consumed via the frozen interface + a reference impl, wired at fold); res.lease
#29 (git lease around dev.ship). Contract features: CONTEXT_PACKET_CONTRACT s1-s8; MEMORY_CONTRACT s1
envelope + A2, s3 retriever-0.2 hit, s5 staleness enum. Tools: `pwsh>=7.4`, `python>=3.8` (stdlib only).
Models: none.

### Skill contract requirements
`skill_id=context.compile`, `version=0.2.0`, `contract_version=0.2`, `determinism=deterministic`,
`parallel_safe=true`, `batch=false`, `streaming=false`, `confidence=null`, empty `model_provenance`.
Artifact kinds: `json` (`context_packet.json` / `context_expansion.json`) + `text` (`rendered_input.txt`).

### Inputs and outputs
See `skill.json` (inputs) + `SCHEMA_NOTES.md` (the packet/expansion/selection shapes). Ops: `compile`
(default), `normalize`, `expand`.

### Proposed implementation
Python (stdlib only) for ALL packet logic + the in-module `selpol_reference` s4 seam (sidesteps the
pwsh-7.4.6 determinism traps). A thin pwsh entrypoint wraps it and owns the retriever seam (mock fixture
off-machine; real #36 on `-Live`).

### Tests
- **Off-machine:** `python tests/context_compiler_tests.py` (148 assertions covering acceptance a-g) +
  `pwsh tests/Invoke-ContextCompilerTests.ps1` (entrypoint end-to-end, mock retriever).
- **Through the executor (`-Live`):** ingest a bounded core-docs slice via #36, then
  `pwsh tests/Invoke-ContextCompilerTests.ps1 -DbPath <catalog.db> -RepoRoot <repo>` (real retriever-0.2).

### MVP acceptance criteria (a)-(g)
(a) three regions structurally separated + a passing injection unit test (evidence with imperative text
cannot populate control_plane / alter completion_contract / change skill selection); (b) packet_disposition
correct across answerable / needs_expansion / abstain / conflicted / provenance_failed fixtures; (c)
consumer_profile + count_is_exact=false + fail-closed transport (oversize evidence -> omission_manifest,
disposition=needs_expansion, control_plane + completion_contract intact); (d) selection via the s4 selpol
interface (reference impl) with the additive fields + retrieval order preserved; (e) provenance modes
present + each direct_span excerpt reproduces its source bytes; (f) byte-identical on re-run (deterministic
packet_id covering the identity fields); (g) `non_execution:true` present. `-Live`: the real #36 retriever
over a core-docs slice for >=3 LO benchmark questions -> required spans present + provenance-valid; `expand`
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
