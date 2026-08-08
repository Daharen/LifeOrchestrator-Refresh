# FANOUT_AGENT_003 -- READY (i42 Lane B: #43 action.authz 0.5.0->0.6.0, the 3 round-4 closures)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i42 (plan id `fo-42-e5403d74`)
- **Lane:** CODING (CPU)
- **Worker id / label:** P01-R4-CLOSURE-43-i42
- **Module/area (exclusive):** `modules/43-action-authz` (EXTENDS 0.5.0 -> 0.6.0)
- **GPU:** false
- **Docs:** `[]`

## Mission
Build the **3 ROUND-4 exact closures** from the pack-678163b1 ratification FAIL (D-0116): F5 real-seam losslessness, F4 grant pre-validation, F2 handle-bound ledger provenance. 5th ratification round; nothing walked back for three rounds running (M2-D). `non_execution:true` holds; NOTHING becomes action-capable. Governing SPEC: `research/2026-08-07-i41-p01gate-round4-redteam.md` (build to each "Exact closure required" block).

## Unit (the full worker prompt)
Read + execute the complete engineered prompt (self-contained, ~13 KB) at:
`modules/30-orchestrate-fanout/runtime/artifacts/7ed39a71-20e1-4158-a9e9-4bd3cf6161b2/workers/worker-P01-R4-CLOSURE-43-i42.prompt.md`
(Nicholas also pastes this file as the SendUserFile convenience copy.)

The 3 closures in brief:
- **F5** -- `build_trusted()` must BEGIN with `adapt_packet_lossless()`; derive PacketView + meta ONLY from the preserved/re-parsed packet; bind the whole-packet identity digest into trusted state; re-run the per-field + 5 named probes (identity.compiler_version, identity.selection_policy, retrieval_provenance, evidence.current_state_refs, selection.stages) END-TO-END through `build_trusted` -> fail-closed or a distinguishable trusted representation.
- **F4** -- validate grants BEFORE any operational read (one shared validated-grant iterator used by `grant_namespaces()` + `match()`); the A11 KeyError path dies; end-to-end `authorize()` vectors (unknown / missing grant_id / missing action_namespace / mistyped / malformed) -> constant DENY, no exception/permit/state-diff. Limit algebra + validator pin unchanged.
- **F2** -- the mock applicator consumes handle + canonical args and RETURNS the effect atoms; `authorized_effect_set` becomes an authorization bound/comparison, never the template; KILL the consume-but-discard-result + blind-copy successor mutant.

M2-D: `p0_1_gate_status=incomplete` in EVERY artifact + NEW `round4_closure_built {f5,f4,f2}`; the D-0109 `finding_1..7` + `round3_closure_built {f1,f2,f4,f5}` flags ALL stay true (no regression). `report.json` is the SINGLE source of as-built counts (the round-4 summary lagged the tree). Regression floor: whole 0.5.0 suite green + grows (oracle not_run=0 GATING; role 30/30); double-run byte-identity; empty-dir self-verify re-run on the FINAL tree; run_suite's required-file manifest (incl. WORK_ORDER.md) stays strict. If a closure would need a FROZEN-field amendment: STOP + report (the review says none does).

RECOMMENDED MODEL: **Opus 4.8 Extra** (5th ratification round -- do NOT downgrade). F7 pack transport is ORCHESTRATOR-owned at fold (round-5 pack).

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire the res.lease `git` lease before committing; release on exit. No GPU.
- Do ONE unit; EXCLUSIVE to `modules/43-action-authz`; `docs:[]`.
- Gate off-machine FIRST (pure python), then `exec-job.sh devship` (module modules/43-action-authz; AST/tests fail-closed; named files only). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.
- If your device bridge dies before your first push: STOP + report in-session (the i40 lesson) -- the orchestrator runs recovery; do not improvise a second ship path.
- Report: `-Action report -PlanId fo-42-e5403d74 -WorkerId P01-R4-CLOSURE-43-i42 -State done` + a plain measured summary (negative results first-class).

## Verification
`round4_closure_built {f5,f4,f2}` true|false + an evidence pointer each (F5 end-to-end probe results through `build_trusted`; F4 end-to-end `authorize()` DENY vectors; F2 killed successor-mutant id). Full suite numbers + oracle not_run count. Empty-dir self-verify transcript. Confirmation the D-0109 finding_1..7 + round3 flags still read true. Taxonomy emitted (build_complete / incomplete / prohibited). `report.json` single-source confirmation.

## Report-back record (orchestrator fills at fold)
_empty._
