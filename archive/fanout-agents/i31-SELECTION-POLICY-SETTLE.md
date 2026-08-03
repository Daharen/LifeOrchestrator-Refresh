# FANOUT_AGENT_002 -- READY (i31 SELECTION-POLICY SETTLE)

- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i31 (plan id `fo-31-eca37c08`)
- **Lane:** CPU (single-worker wave; GPU/coding/frontier lanes SKIPPED -- deterministic, no model)
- **Worker id / label:** CONTEXT-COMPILER-SELPOL-i31 -- context.compiler #40 0.2.0->0.3.0: RETIRE selpol_reference.py + IMPORT #37's canonical selpol_rrf_v1 (P1-1 'one owner'), per the i31-PINNED CONTEXT_PACKET_CONTRACT s4 (D-0089).
- **Module/area (exclusive):** modules/40-context-compiler (WRITE); the SOLE cross-module touch is a READ-ONLY import of modules/37-retrieval-eval/lib/selpol_rrf_v1.py
- **GPU:** false
- **Docs:** `[]` (the orchestrator mirrors all core-docs; the worker edits none)

## Mission

Realize P1-1 'one selection owner' and close the i30 D-0077 pair-1 divergence: context.compiler #40 RETIRES its in-module `selpol_reference.py` (rank-RRF-primary) and IMPORTS #37's canonical `selpol_rrf_v1` (raw-fused-score-primary), which CONTEXT_PACKET_CONTRACT s4 now PINS (D-0089). #40 builds `params.hard_filter` from `control_plane.permission_grants`, consumes the canonical additive output, and regenerates its fixtures to the canonical selection. Governing: `core-docs/CONTEXT_PACKET_CONTRACT.md` (s4 PINNED, D-0089) + `core-docs/MEMORY_CONTRACT.md`; digest `research/2026-08-02-frontier-wave3-design-redteam.md`.

## Unit (the full worker prompt -- emitted by orchestrate.fanout `plan`, verbatim)
# Fan-out worker prompt -- worker CONTEXT-COMPILER-SELPOL-i31 (plan fo-31-eca37c08, iteration 31)

You are one worker in a fan-out build of Life Orchestrator, coordinated by an orchestrator instance.
First read core-docs/START_HERE.md and core-docs/HANDOFF.md, then the docs they route you to.

## Your scoped unit
REVISE the EXISTING module modules/40-context-compiler (skill id `context.compile`) 0.2.0 -> 0.3.0 to REALIZE P1-1 "one selection owner": RETIRE the in-module `selpol_reference.py` and IMPORT #37's CANONICAL `selpol_rrf_v1` directly, conforming to the i31-PINNED CONTEXT_PACKET_CONTRACT s4 (D-0089). This ends the i30 D-0077 pair-1 divergence (your reference and #37's canonical select DIFFERENTLY) by making #40 CONSUME the one canonical library rather than a second implementation. CPU-only, parallel-safe (distinct module), DETERMINISTIC, NO model, NO network. You are the CONSUMER; the orchestrator re-runs the D-0077 selpol fold smoke asserting #40-via-canonical selects BYTE-IDENTICALLY to a direct `select()` on real #36 hits, and re-confirms the #41->#36->#40 chain + a valid context_packet/0.2.

READ FIRST (disk is canonical; do NOT skip):
- core-docs/START_HERE.md + core-docs/CURRENT_STATE.md 'Known failures / gotchas' IN FULL (the load-bearing gotcha corpus: the WEDGE class -> any persistent model server launches DETACHED + reaped before finalize + assert 0 UNMANAGED orphans [N/A this wave -- no model]; pwsh 7.4.6 traps -- sort-copy no-op (cast [string[]]), empty-array unroll ($x=@() first), array double-wrap (build a List + ToArray), `$var:` in a double-quoted string (use ${var}); per-file EOL (core-docs CRLF, some module docs LF); json.dump exotic-type coercion; 'trust the heartbeat, not the process list'; dev.ship can FALSE-NEGATIVE `committed` -> verify native git; the SELECTION-POLICY-i30 gotcha: an existing repo file may carry the Windows ReadOnly attribute that denies ALL writes -- if a write is denied but reads work, check (Get-Item -Force).IsReadOnly and clear it via an executor Set-ItemProperty/attrib -R).
- **core-docs/CONTEXT_PACKET_CONTRACT.md IN FULL -- s4 is now PINNED (D-0089).** The s0 pin bullet + the s4 'Scoring (PINNED, D-0089)' bullet + the 'One owner, imported not reimplemented' bullet are THE FREEZE you conform to; s8 records the #40 conformance. On any conflict this doc + its live gates win; NEVER silently edit a frozen field (amendment protocol s0). The pin: relevance-primary = #37's composite base (raw fused/lexical/score, NOT rank-RRF); AUTHORITY_RANK{1-4} + freshness ranks{0-3}; greedy source-MMR + occurrence-preserving display dedup; additive hit-copy output. Pure-rank-RRF-primary is the DEFERRED P1-2 (do NOT build it).
- **modules/37-retrieval-eval/lib/selpol_rrf_v1.py IN FULL -- the CANONICAL library you now IMPORT** (POLICY_ID='selpol_rrf_v1', POLICY_VERSION='1.0.0'; `select(candidates, descriptor, policy_id='selpol_rrf_v1', params=None) -> {selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[], stages}`) + modules/37-retrieval-eval/SCHEMA_NOTES.md sections 9-13 (the interface, the 6 stages, the RRF-over-channel-ranks, the occurrence-preserving dedup, the label->policy-signal mapping, and section 13 'Fold + #40 consumption recipe' which is EXACTLY your task: call select(..., dedup_display=True, budget) with `hard_filter` from control_plane.permission_grants + candidate `status` for temporal).
- core-docs/MEMORY_CONTRACT.md (s3 retriever-0.2 hit shape you consume; s5 staleness enum; A2 provenance modes) as your packet-build needs.
- core-docs/research/2026-08-02-frontier-wave3-design-redteam.md (P1-1 rationale) + core-docs/DECISION_LOG_INDEX.md -> pull D-0089 (THIS pin), D-0088 (the i30 divergence you resolve), D-0086/D-0087 (Wave 3 + the contract), D-0077 (the cross-module smoke rule).
- core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md section 8 (worker-spec rules) + core-docs/SKILL_CONTRACT.md + core-docs/MODULE_WORK_ORDER_TEMPLATE.md.
- your OWN modules/40-context-compiler/: SCHEMA_NOTES.md (the shipped 0.2 -- the three-region packet, disposition, consumer_profile/transport, the s4 selpol SEAM at section 8, provenance modes, identity/lineage) + skill.json + context_compiler.py + selpol_reference.py (the stub you RETIRE) + tests/context_compiler_tests.py + fixtures/.

SHARED CONTRACT (D-0077 -- the fold depends on it; record EVERY interpretation in modules/40-context-compiler/SCHEMA_NOTES.md): (a) you CONSUME the MEMORY_CONTRACT s3 retriever-0.2 hit (rank=index+1, never re-sorted). (b) you IMPORT #37's CANONICAL `selpol_rrf_v1.select(...)` from modules/37-retrieval-eval/lib/ -- NOT a reimplementation, NOT a reference stub. (c) you PRODUCE `lifeorch.context_packet/0.2` carrying the ADDITIVE selection fields the canonical select() returns.

SCOPE IN (WRITE ONLY under modules/40-context-compiler/; the SOLE cross-module touch is a READ-ONLY import of #37's lib). Governing: CONTEXT_PACKET_CONTRACT s4 (PINNED) + s1-s8 + MEMORY_CONTRACT s3/s5/A2.
1. **RETIRE selpol_reference.py.** Delete modules/40-context-compiler/selpol_reference.py and remove every import/reference to it. NO in-module selection implementation remains anywhere in #40.
2. **IMPORT #37's canonical selpol_rrf_v1 by a RESOLVED PORTABLE path.** Resolve the repo root from __file__ (.../modules/40-context-compiler/... -> repo root) then load modules/37-retrieval-eval/lib/selpol_rrf_v1.py (add its dir to sys.path, or importlib.util from the file path; note the lib has its own __init__.py). Deterministic, stdlib-only. BOTH the off-machine tests AND -Live import the REAL lib (no stub, no fold-time swap). Fail-closed with a clear error if the lib is missing/unimportable.
3. **Map #40's descriptor + control_plane -> the canonical select() inputs.** Build the s4 unified descriptor {namespace, component, relevant_paths, task_type, task_stage, time_horizon, seeking_failures, permission_context} (you already build this from task_input). Build `params`: `hard_filter` = matchers [{source_path, content_hash?, reason}] derived ONLY from control_plane.permission_grants (+ any descriptor forbidden_sources/privacy_exclusions) -- NEVER from an evidence record (the P0-1 boundary); `current_only` from time_horizon=='current_only' (or pass params.current_only); `budget` {max_selected?, max_tokens?, per_item_overhead?}; `dedup_display` as your packet needs; `stale`/`required_versions` if you carry them. This is the reconciliation #37 SCHEMA_NOTES s11/s13 intends: #40 passes hard_filter from control_plane, NOT via descriptor.forbidden. Call select(candidates, descriptor, 'selpol_rrf_v1', params).
4. **Consume the canonical output shape.** select() -> { selected[] (hit COPIES), ranked[] (copies PRESERVING retrieval_rank/lexical_rank/vector_rank/fused_rank + ADDING selection_rank/selection_score(int millionths)/selection_policy_id/selected/reason_codes[]/retrieval_occurrences[]/rrf_score [+ evidence_cluster_id/occurrences[] in a dedup cluster]), features_by_candidate, omission_manifest[], stages[] }. Build the packet evidence excerpts/refs FROM selected[] in selection order, carrying the additive selection fields onto each evidence item; MERGE select()'s omission_manifest with any #40 transport-drop omissions (reasons stay the s6 enum); stamp stages + policy_id/policy_version into packet identity. The retrieval array keeps rank=index+1 UNTOUCHED. Every original hit field (source_path/span/chunk_content_hash/snippet/token_count/authority_level/status) is on the returned copies -- your evidence + provenance build is unchanged in shape.
5. **Reconcile the budget boundary (P0-4 stays YOURS).** The canonical library owns selection + an optional selection-budget hook (max_selected/max_tokens over the candidate pool). Your P0-4 FAIL-CLOSED TRANSPORT accounting (final-RENDERED tokens vs consumer_profile.max_context; drop-to-omission_manifest; abstain when control_plane+task_input alone overflow) REMAINS #40's stage, composed on top of select()'s output. Document in SCHEMA_NOTES which stage drops what. NEVER let selpol's budget silently truncate control_plane / completion_contract / a required citation.
6. **Selection ORDER changes -> REGENERATE fixtures.** The pinned canonical is raw-fused-score-primary composite (the retired reference was rank-RRF-primary), so selection order/scores/packet_id CHANGE. Regenerate every expected-packet / expected-selection fixture to the canonical selection. The P0-1 injection test, P0-3 disposition, P0-4 transport, P1-5 identity, A2 provenance tests must STILL PASS (they assert packet STRUCTURE, not a specific selection order) -- update only what selection order/score/packet_id changes; do NOT weaken an assertion to make it pass.
7. **policy_version.** The packet's selection_policy stamps #37's selpol_rrf_v1 / policy_version '1.0.0' (from the imported lib, not a #40 constant). Confirm packet identity (s6) covers selection_policy id+version.

NON-GOALS (do NOT build): ANY change to modules/37-retrieval-eval/selpol_rrf_v1.py or ANY other module -- you import #37's lib READ-ONLY. IF you find the canonical select() genuinely cannot serve #40's packet-build without a #37 change, STOP and REPORT it as a fold reconciliation (name the exact gap); do NOT edit #37. Do NOT implement pure-rank-RRF-as-PRIMARY (the DEFERRED P1-2). Do NOT build the P0-1 adversarial injection SUITE or the action-capable gate release (a later wave -- keep the shipped structural separation + the basic injection unit test). No real embeddings / vector search (vector channel may be null); no #36 catalog, #37 eval, #41 cards, the 9B / any model, models.json; no UI. Do NOT touch model modules / models.json / ANY core-doc (docs:[]).

ACCEPTANCE:
(a) modules/40-context-compiler/selpol_reference.py DELETED; a grep proves NO remaining import/reference to it; #40 imports #37's canonical selpol_rrf_v1 by a resolved portable path that works OFF-MACHINE and -Live.
(b) #40 produces a valid `context_packet/0.2` whose selection fields (selection_rank/selection_score/selection_policy_id/reason_codes/retrieval_occurrences/rrf_score/omission_manifest/stages) come from the CANONICAL select(); retrieval order preserved (rank=index+1 untouched).
(c) The P0-1 three-region + injection unit test, P0-3 disposition (answerable/needs_expansion/abstain/conflicted/provenance_failed), P0-4 consumer_profile + fail-closed transport, P1-5 identity/lineage, A2 provenance modes ALL stay GREEN; non_execution:true present.
(d) Fixtures regenerated to the canonical selection; DETERMINISTIC (byte-identical packet on re-run; packet_id covers selpol_rrf_v1/1.0.0).
(e) A #40-side test proving #40's selection == a DIRECT selpol_rrf_v1.select(candidates, descriptor, params) call on the same candidates (the byte-identity the D-0077 fold repeats on real #36 hits).
(f) -Live over a real #36 retriever-0.2 slice for >=3 LO benchmark questions -> packets whose required source spans are present + provenance-valid; expand still returns a bounded immutable delta with a locked snapshot.

GATES (fail-closed): OFF-MACHINE FIRST (cloud python/pwsh, deterministic, importing the REAL #37 lib, CPU-only) THEN `-Live` on the executor over the real slice. Bump skill.json 0.2.0 -> 0.3.0 (contract_version 0.3). Update README + WORK_ORDER + SCHEMA_NOTES to CONTRACT. Canonical packet artifacts double-run byte-identical (mind the pwsh traps / json.dump exotic-type coercion).

LEASE + SHIP DISCIPLINE (res.lease #29): you hold docs:[] so you take NO doc lease; as a CPU lane you take NO gpu lease. Take the git lease ONLY around your dev.ship commit, release after. device_bash is a Linux VM and CANNOT run Windows pwsh -- everything runs through the executor (exec-job.sh). Ship via dev.ship (it verifies sha256 + AST + tests FAIL-CLOSED and commits ONLY your named files under the git lease). NOTE dev.ship must handle a DELETED file (selpol_reference.py) -- if it only stages added/modified named files, stage the deletion explicitly (git rm / git add -- selpol_reference.py) inside your commit path and assert it in the staged set. VERIFY the real HEAD via native git log / git show --stat, NOT the dev.ship 'committed' field (D-0072); if a stale 0-byte .git/index.lock blocks it, clear it via an executor task (assert no git.exe running) then re-commit. The exact res.lease + report command lines (with this plan's id) are appended to this prompt below.

VERIFY / REPORT (docs:[] -- the ORCHESTRATOR mirrors + folds ALL core-docs from your report; do NOT edit any core-doc): report DONE/PARTIAL/DEFERRED per acceptance item with the exact file+function delta and the test that proves it; the off-machine + live counts; 0 UNMANAGED llama-server/python orphans; review_queue.jsonl before==after. UPDATE modules/40-context-compiler/SCHEMA_NOTES.md recording EVERY 0.3 interpretation -- REQUIRED for the D-0077 fold (MUST record: the canonical import path + that selpol_reference.py is RETIRED; the descriptor + control_plane -> params.hard_filter mapping; the output-shape consumption [selected[] hit-copies + additive fields + omission_manifest + stages]; how #40's P0-4 transport budget composes with selpol's budget hook; the regenerated fixtures; the #40-vs-direct-select byte-identity check). Fallback (D-0061, negative results are first-class): ship the coherent TESTED prefix, keep it self-contained, report PLAINLY what remains + why. Report via the -Action report command appended below.

SCOPE OUT / do NOT: modify #37's selpol_rrf_v1 or its eval, the #36 catalog, the #41 cards, real embeddings/vector search, the 9B / models.json; touch any other module or ANY core-doc (docs:[]). Single worker this wave (MaxParallel 1) -- you hold the git lease alone for your commit.

Notes: CONTEXT-COMPILER-SELPOL lane (CPU; single-worker wave, GPU/coding/frontier lanes SKIPPED -- deterministic, no model). REVISES modules/40-context-compiler, skill.json 0.2.0 -> 0.3.0 (skill_id context.compile). REALIZES P1-1 'one selection owner': RETIRE selpol_reference.py + IMPORT #37's canonical modules/37-retrieval-eval/lib/selpol_rrf_v1.py (READ-ONLY cross-module import). s4 is PINNED (D-0089): raw-fused-score-primary composite; AUTHORITY_RANK/freshness ranks; source-MMR + display dedup; additive hit-copy output. #40 builds params.hard_filter from control_plane.permission_grants (#37 SCHEMA_NOTES s13 recipe). Selection order CHANGES vs the retired reference -> regenerate fixtures. If the canonical select() cannot serve #40 without a #37 change, STOP + report a fold reconciliation (do NOT edit #37). No model, no models.json. Brief: core-docs/fanout/FANOUT_AGENT_002.md.

## Resource leases (collision safety -- res.lease #29)
Acquire these BEFORE the work they guard, in THIS order (gpu -> git -> doc); each blocks up to the wait:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "CONTEXT-COMPILER-SELPOL-i31" -TtlSeconds 1800 -WaitSeconds 900
```
Acquire returns a lease_id; keep each one. Renew before its TTL if the work runs long.
Release in REVERSE order when the guarded work is done, or immediately if you block/abort:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "CONTEXT-COMPILER-SELPOL-i31"
```
(Release-by-holder is shown; releasing with the exact -LeaseId is stronger.)

## Report back (cadence: on_all)
Report at least once when you finish or block. Run:
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-31-eca37c08" -WorkerId "CONTEXT-COMPILER-SELPOL-i31" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
```
Use -State progress for interim updates, -State blocked with -Needs '<what you need>' if stuck, -State failed if you cannot finish.

## Ship + stop
Ship your unit through the job-runner (dev.ship). Do ONE scoped unit. Do NOT touch another worker's
module, and do NOT edit the shared core-docs the orchestrator owns -- report and let the orchestrator
mirror them (it serialises doc + git writes via res.lease). Then release your leases and report done.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' first; obey `SKILL_CONTRACT.md`.
- Acquire the `git` res.lease ONLY around your dev.ship commit; release after. No gpu/doc lease (CPU lane, docs:[]).
- Do ONE unit; WRITE only under `modules/40-context-compiler/`; import #37's lib READ-ONLY; never edit a core-doc.
- Gate off-machine first (cloud python/pwsh, importing the REAL #37 lib), then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only; stage the `selpol_reference.py` DELETION explicitly).
- Verify the real HEAD via native git (D-0072); the dev.ship `committed` field can false-negative.
- If the canonical `select()` cannot serve #40 without a #37 change, STOP + report a fold reconciliation (do NOT edit #37).
- Report via `-Action report -PlanId fo-31-eca37c08 -WorkerId CONTEXT-COMPILER-SELPOL-i31 -State done` (+ a plain summary; negative results are first-class, the D-0061 ethos).

## Verification

Off-machine (python/pwsh, real #37 lib imported) THEN `-Live` on the executor over a real #36 slice. Acceptance (a)-(f) in the Unit: selpol_reference.py deleted + no residual import; #40 imports the canonical by a resolved portable path; a valid context_packet/0.2 with the canonical selection fields; P0-1 injection / P0-3 disposition / P0-4 transport / P1-5 identity / A2 provenance all GREEN; fixtures regenerated + byte-identical on re-run; a #40-vs-direct-`select()` byte-identity test; -Live packets whose required spans are present + provenance-valid. skill.json 0.2.0 -> 0.3.0. 0 UNMANAGED orphans; review_queue before==after.

## Report-back record (ORCHESTRATOR fills from plans/fo-31-eca37c08/reports/ before archiving)

_Pending worker report._
