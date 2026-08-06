# FANOUT_AGENT_002 -- READY (i40 Lane B: M37-RECONCILE-i40)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i40 (plan id `fo-40-d42fd1ac`)
- **Lane:** CPU
- **Worker id / label:** `M37-RECONCILE-i40` -- retrieval.eval #37 fold-reconciliation + version hygiene (PB-5, D-0108)
- **Module/area (exclusive):** `modules/37-retrieval-eval`
- **GPU:** false
- **Docs:** `[]`

## Mission (2-4 lines)

Close PROCESS_BACKLOG PB-5 (D-0108): re-pin #37's WIRED_STRUCTURAL_DIGEST (moved legitimately by #36 0.7.0's
fast-beam; i39-verified prefix `sha256:d0d54aba`, wired metric IMPROVED) and reconcile the pre-existing
manifest-version inconsistency (skill.json 0.8.0 vs harness/worker-envelope 0.7.0 literals) to ONE declared
version source of truth with a permanent -Live drift assertion -> #37 -Live FULLY GREEN.

## Unit (the full worker prompt -- verbatim from the plan; also at `modules/30-orchestrate-fanout/runtime/artifacts/73041f89-714b-4112-8a70-919ffe77be82/workers/worker-M37-RECONCILE-i40.prompt.md`)

RECONCILE #37 retrieval.eval (PB-5, deferred at the i39 fold, D-0108) in the EXISTING module modules/37-retrieval-eval: (a) the wired-digest re-pin + (b) the manifest-version single source of truth -> #37 -Live FULLY GREEN. EXCLUSIVE to modules/37-retrieval-eval; docs:[]; CPU (no GPU); deterministic; READ-ONLY over the FROZEN #36 0.7.0 / #40 0.9.0 / #42 / #43 (drive them to measure, never modify them).

WHY: i39's #36 0.7.0 fast-beam LEGITIMATELY moved the wired-descend structure, so the pinned WIRED_STRUCTURAL_DIGEST in tests/test_rehearsal_eval.py is stale. The re-derived value was verified at the i39 fold (prefix sha256:d0d54aba; the wired metric IMPROVED -- 11/11 s10 criteria, hierarchy_path_recall 58823 -> 117647 ppm, guaranteed + packet recall 1,000,000 ppm) but the re-pin was NOT committed because attempting it surfaced a SEPARATE PRE-EXISTING #37 -Live failure: skill.json declares `0.8.0` while the harness check + the worker envelope emit `0.7.0` -- an internal version-string inconsistency predating i39 (undetected because i37/i38 never re-ran #37 -Live). The i39 orchestrator correctly did NOT blind-fix semantics mid-fold and reverted the tree clean. You own the semantics now.

READ FIRST (do not edit core-docs): core-docs/DECISION_LOG.md entry D-0108 (the deferral record -- the '#37 fold-reconciliation DEFERRED' block) + your OWN modules/37-retrieval-eval (skill.json; the -Live harness checks; the worker envelope emitter; tests/test_rehearsal_eval.py) + its SCHEMA_NOTES.md + research/2026-08-05-i36-tier1-acceptance-rehearsal.md (the s10 criteria the rehearsal asserts).

BUILD. (a) RE-PIN: re-derive WIRED_STRUCTURAL_DIGEST using the harness's OWN derivation over the CURRENT committed #36 0.7.0 + #40 0.9.0 wired descend structure. CONFIRM the derived value matches the i39-verified prefix sha256:d0d54aba -- if it does NOT match, STOP and report the mismatch plainly (do not pin an unverified structure). Pin the full value in tests/test_rehearsal_eval.py. (b) VERSION TRUTH: diagnose which surface is semantically right (skill.json 0.8.0 reflects the i36 eval-0.8.0 bump; the envelope/harness literals lag) and make EVERY version surface derive from ONE declared source -- e.g. the harness check + the worker envelope READ the skill.json version instead of carrying hardcoded literals. Record the single-source rule in SCHEMA_NOTES.md. Add a cheap PERMANENT -Live assertion that the envelope-emitted version == the skill.json version, so any future drift FAILS loudly instead of sitting undetected. Bump the module version consistent with your own rule (e.g. 0.8.0 -> 0.8.1) if your rule requires a bump; do not bump for its own sake.

ACCEPTANCE: #37 -Live FULLY GREEN (every existing check + the new version assertion); the wired rehearsal re-run passes 11/11 s10 criteria with the recall lift INTACT (hierarchy_path_recall 117647 ppm on the committed sample; guaranteed + packet recall 1,000,000 ppm); the non-wired path stays byte-identical to before your change; NO port/response-shape/contract changes; NO other module touched.

GATES. Off-machine FIRST where practical (the digest derivation + version-surface audit are cloud-checkable). Then exec-job.sh devship (skill retrieval.eval; AST + tests FAIL-CLOSED; named files only). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.

REPORT (`-Action report ... -State done` + plain summary): the re-derived digest (FULL value) + its match to the d0d54aba prefix; the version-truth rule + which surfaces now derive from it; the #37 -Live result list; the rehearsal 11/11 + recall numbers; a plain green / not-green statement. Negative/partial results are first-class.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Leases in **gpu -> git -> doc** order (this unit: `git` only); release on exit. Holder `M37-RECONCILE-i40`, TTL 1800, wait 900.
- Do ONE unit; never touch modules/areas outside the exclusive claim; `docs:[]`.
- Gate off-machine first, then ship via `exec-job.sh devship` (FAIL-CLOSED, named files only, trailers); files reach the box via SendUserFile + device_commit_files.
- No persistent servers needed; assert 0 orphans anyway.
- Report: `-Action report -PlanId fo-40-d42fd1ac -WorkerId M37-RECONCILE-i40 -State done -Summary "..."` (+ plain summary; negative results first-class).

## Verification

#37 -Live full green list; wired rehearsal 11/11 with hierarchy_path_recall 117647 ppm + guaranteed/packet 1e6; non-wired byte-identity; the full re-derived digest; the new version assertion firing on an induced drift (test-only) then green.

## Report-back record (ORCHESTRATOR fills from `plans/fo-40-d42fd1ac/reports/` before archiving)

_(empty until fold)_
