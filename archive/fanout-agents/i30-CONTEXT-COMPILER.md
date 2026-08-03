# FANOUT_AGENT_001 -- i30 CONTRACT-HARDENING CONTEXT-COMPILER lane

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i30 (plan id `fo-30-dd453156`)
- **Lane:** CODING (CPU) -- the GPU lane is SKIPPED this wave (deterministic compiler, no model)
- **Worker id / label:** CONTEXT-COMPILER-i30
- **Module/area (exclusive):** modules/40-context-compiler (skill id `context.compile`) 0.1.0 -> 0.2.0
- **GPU:** false
- **Docs:** `[]`

## Mission

Conform the context packet compiler #40 to the NEW `core-docs/CONTEXT_PACKET_CONTRACT.md` (`context_packet/0.2`)
-- the packet is the SAFE, self-describing working set the coordinator hands a disposable model. Fold the
frontier Wave-3 red-team P0-1 (control_plane / task_input / evidence structural separation -- SAFETY-CRITICAL,
a `non_execution` gate), P0-3 (packet_disposition), P0-4 (consumer_profile + exact/upper-bound transport), P1-1
(consume the ONE selection-policy library, retiring the self-contained reranker), P1-5 (identity/lineage), and
the MEMORY_CONTRACT A2 provenance modes. CONSUMER of the retriever-0.2 hit + #37's `selpol_rrf_v1`.

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/e0626255-ae62-4a28-acf5-b14c6d48e845/workers/worker-CONTEXT-COMPILER-i30.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan.)

Scope digest (orientation only -- the emitted prompt governs):

- P0-1 (SAFETY-CRITICAL): three top-level regions -- `control_plane` (ONLY from the descriptor's authority fields, NEVER from retrieval) / `task_input` / `evidence` (content_role=evidence, can_instruct=false, trust_domain, epistemic_authority, provenance); a `non_execution:true` flag; a structural guarantee + an injection unit test (evidence imperative text cannot populate control_plane / alter completion_contract / change selection).
- P0-3: a mandatory `packet_disposition` (answerable|needs_expansion|abstain|conflicted|provenance_failed) + evidence_requirements/coverage/missing/contradictions; a normal answer ONLY when answerable; conservative while the vector channel is empty.
- P0-4: a mandatory `consumer_profile` + count the FINAL RENDERED input + count_method/count_is_exact=false; fail-closed transport (drop to the omission_manifest, never truncate control_plane/completion_contract/a required citation).
- P1-1: RETIRE the self-contained composite score; call `selpol_rrf_v1` via the CONTEXT_PACKET_CONTRACT s4 frozen interface (build to it with a spec-faithful in-module reference impl; the orchestrator wires #37's canonical lib at the D-0077 fold); additive selection fields preserve the retrieval order.
- P0-2/P1-5: A2 provenance-mode names (record_content_hash/source_content_hash/excerpt_hash + provenance_mode); packet identity/snapshot + `omitted_context` -> `omission_manifest`; immutable `expand` delta with a locked snapshot.
- A3: skill activation cards are now record_kind=summary (summary_type=skill_activation_card) -- recognise them as skill candidates.
- NON-goals: #37's canonical selpol library, the eval/#36/#41, real embeddings/vectors, the 9B, the FULL P0-1 adversarial suite (a later wave), models.json.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md`.
- Read `core-docs/CONTEXT_PACKET_CONTRACT.md` (D-0087; context_packet/0.2 + the s4 selection interface) + `core-docs/MEMORY_CONTRACT.md` (A2/A3) IN FULL -- the governing contracts for this wave. Pull the frontier digest `core-docs/research/2026-08-02-frontier-wave3-design-redteam.md` for the P0/P1 rationale.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY your module.
- Gate OFF-MACHINE first (cloud pwsh/python + mock/seam), THEN `-Live` on the executor; ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire the `git` lease ONLY around your dev.ship commit (release after). VERIFY the real HEAD via native `git log`/`git show --stat`, NOT the dev.ship `committed` field (D-0072).
- Any persistent llama-server launches DETACHED + is reaped before finalize (N/A this wave -- no model); assert 0 UNMANAGED orphans. Report via `-Action report -PlanId fo-30-dd453156 -WorkerId <id> -State done` (negative results are first-class, D-0061).

## Verification

A DETERMINISTIC `context_packet/0.2` with: the three regions structurally separated + a passing injection unit test; `packet_disposition` correct across answerable/needs_expansion/abstain/conflicted/provenance_failed fixtures; `consumer_profile` + count_is_exact=false + fail-closed transport (oversize evidence -> omission_manifest, control_plane+completion_contract intact); selection via the s4 interface (reference impl) with the retrieval order preserved; direct_span excerpts reproduce source bytes; byte-identical re-run (deterministic packet_id); `non_execution:true`. `-Live` over a real core-docs slice (>=3 LO questions); `expand` returns a bounded immutable delta. Report off-machine + `-Live` counts; 0 orphans; skill.json 0.2.0 + README + WORK_ORDER + SCHEMA_NOTES to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-30-dd453156/reports/`)

context.compiler #40 0.1.0->0.2.0 SHIPPED `f06e6e7` -- context_packet/0.2 (P0-1 three-region control/evidence separation + non_execution + injection test; P0-3 disposition; P0-4 consumer_profile/transport count_is_exact=false; P1-1 select via the s4 selpol_reference seam; P1-5 identity/lineage; A2 provenance modes). 148/148 python + -Live real slice; 0 orphans. FOLD: the D-0077 pair-1 selpol smoke found #40's selpol_reference selects DIFFERENTLY from #37's canonical selpol_rrf_v1 -> i31 settle (re-ship #40 to import #37's canonical, retire the reference).
