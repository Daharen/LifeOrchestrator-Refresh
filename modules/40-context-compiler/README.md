# Module 40 -- context.compile (Context Compiler) 0.2.0

The Collective Agent's context-compilation centerpiece (D-0080 directive Priority 4 / section 8),
**hardened to `core-docs/CONTEXT_PACKET_CONTRACT.md` (`context_packet/0.2`, D-0087)**. A **deterministic,
CPU-only, no-model, no-network** skill that turns a task descriptor into a versioned, token-budgeted,
SAFE, self-describing `lifeorch.context_packet/0.2` the coordinator hands a disposable model:

```
normalize (8.1) -> retrieve via the retriever-0.2 seam (8.2)
-> select via the s4 selpol interface (P1-1: selpol_rrf_v1, reference impl; the fold wires #37's canonical lib)
-> token budget with EXACT accounting (8.4/16.3) + fail-closed transport (P0-4)
-> context_packet/0.2 = THREE regions (control_plane / task_input / evidence, P0-1),
   packet_disposition (P0-3), A2 provenance modes (P0-2), identity/lineage (P1-5),
   an omission_manifest, an immutable expand seam (8.5), and packet-evaluation hooks (8.6)
```

It **consumes** the FROZEN `MEMORY_CONTRACT` retriever-0.2 hit shape (s3) + s5 staleness enum + s1/A2
provenance envelope AND the `CONTEXT_PACKET_CONTRACT` s4 selection-policy interface, and **produces**
packets that retrieval.eval #37 0.2 and a fresh 9B consume at the orchestrator fold (D-0077). The 9B is
NOT run here -- this module is deterministic; the model consumes the packet downstream.

## The i30 hardening (context_packet/0.1 -> 0.2)
- **P0-1 (SAFETY-CRITICAL): three regions.** `control_plane` (policy / permission_grants /
  request_authority / side_effect_policy / completion_contract / escalation_conditions) is built ONLY
  from the descriptor's authority fields, in a code path that CANNOT read retrieved records -- a retrieved
  README/log with imperative text can NEVER create a permission grant, set the side-effect policy, or
  define the completion contract. `task_input` carries the request (requested side effects are REQUESTS,
  not authorization). `evidence` items each carry `content_role=evidence`, `can_instruct=false`,
  `trust_domain`, `epistemic_authority`, and provenance. A top-level `non_execution:true` flag + a
  rendering contract (control_plane first, task_input, evidence LAST inside hard delimiters). A passing
  injection unit test proves an evidence item with imperative text changes neither `control_plane`, the
  `completion_contract`, nor skill selection.
- **P0-3: `packet_disposition`** in `{answerable, needs_expansion, abstain, conflicted,
  provenance_failed}` from `evidence_requirements`/`coverage_results`/`missing_requirements`/
  `contradictions` -- a normal answer is permitted ONLY when `answerable` (conservative while the vector
  channel is empty).
- **P0-4: `consumer_profile`** (model/tokenizer/chat-template/max_context/reserved_*) + a count on the
  FINAL RENDERED input, `count_method=conservative_upper_bound`, `count_is_exact=false`, and **fail-closed
  transport** (oversize evidence drops to the `omission_manifest`, never truncating control_plane /
  completion_contract / a required citation).
- **P1-1: the retired composite score.** Selection is delegated to the s4 `select(candidates, descriptor,
  policy_id, params)` interface (`selpol_reference.py`, a spec-faithful reference impl of `selpol_rrf_v1`;
  the orchestrator wires #37's canonical library at the D-0077 fold). Selection is ADDITIVE -- channel
  ranks (`retrieval/lexical/vector/fused_rank`) are PRESERVED; `selection_rank`/`selection_score`/
  `reason_codes` are added; the retrieval array is never re-sorted in place.
- **P0-2: A2 provenance.** `record_content_hash` / `source_content_hash` / `excerpt_hash` + a
  `provenance_mode` in `{direct_span, derived_record, aggregate, tombstone}` with per-mode validation.
- **P1-5: identity/lineage.** `task_id` / `packet_id` / `parent_packet_id` / `expansion_id`; ONE
  `corpus_version` per compile (ABORT on drift); `omitted_context` renamed `omission_manifest`; `expand`
  returns an IMMUTABLE `context_expansion/0.2` delta with the corpus snapshot LOCKED to the parent.
- **A3: skill cards.** A skill candidate is a structural #38 `skill` record OR a #41 activation card
  (`record_kind=summary` + `attrs.summary_type=skill_activation_card`).

## Layout
- `context_compiler.py` -- the deterministic worker (all packet logic; stdlib only).
- `selpol_reference.py` -- the CONTEXT_PACKET_CONTRACT s4 selection-policy REFERENCE impl (`selpol_rrf_v1`);
  the fold swaps in #37's canonical library and asserts byte-identical selection.
- `Invoke-ContextCompiler.ps1` -- the thin entrypoint + the retriever seam (mock off-machine; real #36 `-Live`).
- `skill.json` -- the `lifeorch.skill.manifest/0.1` manifest (version 0.2.0, contract 0.2).
- `SCHEMA_NOTES.md` -- **the D-0077 fold contract** (every 0.2 schema/interface interpretation).
- `WORK_ORDER.md`, `examples/`, `fixtures/`, `tests/`.

## Ops
- **compile** (default) -- task descriptor -> `context_packet/0.2` (+ byte-identical `context_packet.json`
  + `rendered_input.txt`).
- **normalize** -- task descriptor -> the deterministic query set (used by the `-Live` retriever seam).
- **expand** (8.5) -- packet + an expansion request -> an IMMUTABLE `context_expansion/0.2` delta with
  bounded additional evidence WITH provenance + a LOCKED corpus snapshot + a depth bound. NOT a live loop.

## Retriever seam
The deterministic worker never calls another process; the retriever is INJECTED.
- **mock** (off-machine): deterministic fixture 0.2 hits (`-Retriever mock -CaseFile ...`).
- **artifact_search** (`-Live`): `normalize` -> run the REAL artifact.search #36 `search` per derived query
  -> `compile` over the gathered retriever-0.2 hits (`-Retriever artifact_search -DbPath ... -RepoRoot ...`).
The compiler MUST NOT depend on the vector channel being populated (lexical-only today).

## Run
```powershell
# off-machine (deterministic mock)
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever mock -CaseFile .\fixtures\compile_case.json

# -Live (real #36 retriever-0.2 over an ingested core-docs catalog)
pwsh -NoProfile -File .\Invoke-ContextCompiler.ps1 -Op compile -Retriever artifact_search `
  -Task .\fixtures\live_task.json -DbPath ..\36-artifact-search\runtime\catalog\as.db -RepoRoot ..\..
```
See `examples/example-invocation.md`. Every invocation emits one `lifeorch.skill.result/0.1` envelope on
stdout; the packet is also a canonical `context_packet.json` artifact (byte-identical on re-run).

## Determinism + provenance
Canonical JSON (`sort_keys`, compact, UTF-8/LF) + a content-derived `packet_id` that COVERS every identity
field (compiler + selection-policy + consumer-profile + budget + grant snapshot + corpus_version +
selected record-version ids + the omission_manifest -- all in the hashed body); integer-only selection
features (scores folded to millionths); no floats, timestamps, run ids, or `abs_path` in the packet.
`direct_span` excerpt text is read from the SOURCE BYTE SPAN and validated against `excerpt_hash` so the
cited span reproduces the text (`provenance.reproduced`).

## Tests
```bash
python tests/context_compiler_tests.py                 # 148 assertions (acceptance a-g + selpol/provenance/identity/expand)
pwsh   tests/Invoke-ContextCompilerTests.ps1           # entrypoint end-to-end (mock)
pwsh   tests/Invoke-ContextCompilerTests.ps1 -DbPath <#36 catalog> -RepoRoot <repo>   # -Live
```

Non-goals (owned elsewhere / a later wave): #37's canonical selpol library (consume the interface + a
reference impl); real embeddings/vector search; the retriever/catalog DB (#36); skill-card content (#41);
the eval harness/metrics (#37); the 9B / any model; episode recording (#39); the FULL P0-1 adversarial
injection SUITE + the action-capable gate release; UI; web search.
