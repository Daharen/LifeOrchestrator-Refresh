# FANOUT_AGENT_002 -- READY

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i39 (plan `fo-39-df2e3a67`)
- **Lane:** CPU
- **Worker id / label:** `FASTBEAM-RECALL-36-i39` -- artifact.search #36 0.6.0 -> 0.7.0: fast-beam recall lever
- **Module/area (exclusive):** `modules/36-artifact-search` (ONLY)
- **GPU:** false
- **Docs:** `[]`
- **Convenience copy of the full emitted prompt:** `modules/30-orchestrate-fanout/runtime/artifacts/2fcdbfb0-ff94-48d2-9d81-dc0d028a0212/workers/worker-FASTBEAM-RECALL-36-i39.prompt.md`

## Mission
i36 measured `hierarchy_path_recall = 0 ppm`: the Tier-1 descend fast-beam reaches NONE of the required leaves on its own; end-to-end recall is 100% only via the exhaustive indexed #36-flat fallback (the SAFE-PRUNING design). #40's `run_hierarchy_plan` takes `frontier = roots[:beam_b]` -- it **slices** #36's ranked shortlist without re-ranking, so fast-path recall is governed by **#36's** shortlist/descend ranking. Strengthen that ranking so the fast-beam itself contributes recall and the flat fallback fires less. Quality lever, not a correctness change; `non_execution:true` holds.

## Unit (self-contained)
EXCLUSIVE to `modules/36-artifact-search` (skill `artifact.search`, 0.6.0 -> 0.7.0); `docs:[]`; CPU; deterministic; integer-only; DOUBLE-RUN byte-identical on every canonical-bytes path. READ-ONLY over the FROZEN #40 0.9.0 + #37 -- do NOT modify them; use #40's wired descend + #37's rehearsal ONLY to measure.

**READ FIRST (governing, do not edit):** `research/2026-08-05-i36-tier1-acceptance-rehearsal.md` (the follow-on + s10 criteria + `hierarchy_path_recall`) + `core-docs/CONTEXT_PACKET_CONTRACT.md` (i34 shortlist-and-descend + safe pruning) + `core-docs/MEMORY_CONTRACT.md` (A6 Tier-1 hierarchy; the ONE canonical `ns_permitted`) + your OWN `modules/36-artifact-search` (`shortlist`/`descend`/`prune_verdict` in `artifact_search.py`; the bounded descriptors `entity_union`/`lexical_descriptor`/`kind_histogram`) + its `SCHEMA_NOTES.md` + `modules/40-context-compiler` `run_hierarchy_plan` (READ-ONLY, to see how your ranking is consumed) + `modules/37-retrieval-eval` `rehearsal_eval.py` (the harness you MEASURE with).

**BUILD.** Strengthen the shortlist + descend node RANKING to incorporate the bounded structural-synopsis descriptors against the query -- query-term overlap with the node's bounded `lexical_descriptor` (df), `entity_union` match, `kind_histogram` -- deterministic, integer-only, RANKING ONLY. **HARD INVARIANTS (non-negotiable):**
- **RANKING ONLY, NEVER a pruning oracle.** The V2 safe-pruning no-false-negative predicates (`prune_verdict` / `SOUND_PRUNE_CHANNELS`) are UNCHANGED. A bounded descriptor may REORDER candidates but must NEVER negatively EXCLUDE a branch; a stale/summary synopsis never prunes; absent a sound certificate the branch is retained/expanded. **End-to-end recall must NEVER drop.**
- **Port response shapes byte-stable.** `shortlist`/`descend`/`prune_verdict` return the SAME field shapes (only ORDER changes; any ranking score is ADDITIVE) so #40 0.9.0 is structurally unaffected -- a flat/non-descend/unscoped compile stays byte-identical; #40's i35 public-port gate (32/32) + the i34 smoke (38/38) still pass.
- **Namespace closure unchanged.** Cross-ns candidates still EXCLUDED before ranking; import the ONE canonical `ns_permitted`, never reimplement.
- **Nav cost bounded.** Do not widen nav cost beyond O(beam_b * depth_d); beam WIDTH (`beam_b`) is #40-owned and OUT OF SCOPE -- improve ranking so the right nodes rank WITHIN the existing beam.

**MEASURE (acceptance).** Re-run #37's committed rehearsal (`Invoke-RetrievalEval -Op rehearsal`, `wired_descend:true`) over the committed real-foreign SAMPLE (and the 6-package corpus per `FULL_CORPUS_RECIPE` if practical) driving #40 0.9.0's wired descend READ-ONLY. **ACCEPTANCE:** `hierarchy_path_recall` STRICTLY > 0 on >=1 labeled descend query with ALL s10 criteria STILL passing (bounded cost / 0 contamination / current-vs-historical / provenance / sub-linear nav from #40's plan trace / packet+guaranteed recall 1,000,000 ppm) + no regression to #36's own suite (0.6.0 38/38 + 56/56 A6-regression + 227/227 -Live) + #40 i35 gate 32/32 + i34 smoke 38/38. If #36 ranking alone cannot lift recall within `beam_b`, REPORT the measured cause plainly -- a first-class NEGATIVE result; the beam-width lever is a #40 follow-on, not this unit.

**CONSTRAINTS.** Do NOT modify #40/#37/#42/#43 or any core-doc. Do NOT change safe-pruning; do NOT reduce recall or widen nav cost. Keep double-run byte-identity on every canonical-bytes path.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order (this unit: **git** only); release on exit/abort.
- Do ONE unit; never touch modules/areas outside `modules/36-artifact-search`; `docs:[]`.
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-39-df2e3a67 -WorkerId FASTBEAM-RECALL-36-i39 -State done` + a plain measured summary (negative results are first-class).

## Verification
The ranking change; BEFORE/AFTER `hierarchy_path_recall` (ppm) on the rehearsal descend queries; proof that safe-pruning + end-to-end recall + nav-sublinearity + ns-closure are PRESERVED; the port-shape byte-stability proof (#40 unaffected); regression results (#36 own suite + #40 i35 gate + i34 smoke); a plain statement of the recall lift (or the negative result + its cause).

## Report-back record (ORCHESTRATOR fills from `plans/fo-39-df2e3a67/reports/` before archiving)
_pending._
