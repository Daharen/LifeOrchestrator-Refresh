# FANOUT_AGENT_003 -- READY (i41 Lane A: P01-R3-CLOSURE-43-i41)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i41 (plan id `fo-41-35be4fdc`)
- **Lane:** CODING (CPU)
- **Recommended model (D-0114):** **Opus 4.8 Extra** -- fourth round on a ratification-critical gate; do NOT downgrade this lane.
- **Worker id / label:** `P01-R3-CLOSURE-43-i41` -- action.authz #43 0.4.0->0.5.0: the 4 worker-side round-3 exact closures
- **Module/area (exclusive):** `modules/43-action-authz`
- **GPU:** false
- **Docs:** `[]`

## Mission (2-4 lines)

Build the 4 WORKER-SIDE exact closures from the ROUND-3 ratification review of the P0-1 deny-by-default gate
(`research/2026-08-06-i40-p01gate-round3-redteam.md`, pack 5807bc3e, D-0113) -- to the letter of each
"Exact closure required" block. Round 3 was the first with NO over-claim (M2-D held); keep it that way: you
never claim pass -- NEW `round3_closure_built` flags + suite evidence carry the claim; ratification is the
orchestrator's, only on the round-4 review's PASS.

## Unit

**EXECUTE VERBATIM the emitted worker prompt at:**
`modules/30-orchestrate-fanout/runtime/artifacts/30faa27a-0b0b-4f36-9f17-3bd82c6d891e/workers/worker-P01-R3-CLOSURE-43-i41.prompt.md`
(10.8 KB -- the complete instruction; it exceeds this slot's 8 KB budget, so the emitted file is the
authoritative copy; Nicholas also receives it as a chat file at dispatch.) Condensed map (the prompt + the
review digest govern; F-numbers = the round-3 review's):

1. **F1 WRITE-ONCE completion binding (PermitStore):** any second `record_completion_binding` per permit_id rejected (incl. an identical value); immutable stored representation; defensive-copy getter; vectors: sentinel-overwrite after late contract insertion / binding-overwrite / getter-mutation / duplicate recording; the review's 5-step overwrite sequence now fails at step 3.
2. **F2 consumed TargetHandle:** a distinct trusted handle object the effect-applicator API REQUIRES; the ledger generated from the handle-bound applicator result (never `authorized_effect_set`); one-shot observable consumption; the 0.4.0 blind-copy+digest-tag behavior becomes a KILLED mutant.
3. **F5 lossless context_packet/0.2 adapter:** complete packet (or canonical bytes + validated view); ALL identity-covered fields validated + preserved incl. the five probes the reviewer proved inert; per-identity-field mutation properties (any change alters the preserved identity or fails closed); round-trip equivalence; overlay flips ONLY non_execution; authentic 0.7.0 + 0.9.0 packets through the exact seam.
4. **F4 operational top-level GrantView enforcement:** the exact closed field set + types validated BEFORE matching; unknown/missing/mistyped/malformed top-level fields rejected; the OPERATIONAL validator pinned; the accepted limit-intersection algebra unchanged.

**THE GATE-STATUS RULE (M2-D -- non-negotiable):** `p0_1_gate_status` stays **`incomplete`** in EVERY artifact.
NEW machine-readable `round3_closure_built: {f1_write_once_binding, f2_consumed_target_handle,
f4_toplevel_grantview, f5_lossless_adapter}` flags + the D-0109 `exact_closure_built` finding_1..7 flags (ALL
must stay true) carry the claim. `run_suite.py`'s required-file manifest (incl. `WORK_ORDER.md`) stays exactly
as strict -- it caught the i40 pack gap. F7 (pack transport) is ORCHESTRATOR-owned at fold:
manifest-generated round-4 pack, empty-dir verified, then couriered.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Leases in **gpu -> git -> doc** order (this unit: `git` only); holder `P01-R3-CLOSURE-43-i41`, TTL 1800, wait 900; release on exit.
- ONE unit; EXCLUSIVE to `modules/43-action-authz`; do NOT modify #36/#37/#40/#42 or any core-doc (`docs:[]`); no frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT field reopened (the review confirmed none needs it).
- Pure Python stdlib; deterministic; integer-only JSON; DOUBLE-RUN byte-identical on every canonical-bytes path; `non_execution:true` holds; A06 still denies every authentic packet; nothing action-capable.
- Gate off-machine first (cloud python), then `exec-job.sh devship` (module modules/43-action-authz; FAIL-CLOSED; named files only; trailers). VERIFY the real HEAD via native git (D-0072). Assert 0 orphans. Bridge dies pre-push -> STOP + report plainly (the i40 recovery path is orchestrator-run).
- Report: `-Action report -PlanId fo-41-35be4fdc -WorkerId P01-R3-CLOSURE-43-i41 -State done -Summary "..."` (+ plain summary; negative/partial results first-class).

## Verification

Full suite green + GROWN (oracle not_run=0 stays GATING; role 30/30; the D-0109 flags true); per-closure
`round3_closure_built` flags + evidence pointers; the FINAL-tree empty-dir self-verify transcript (exit 0,
byte-identical report manifest) inside the regenerated evidence bundle; double-run byte-identity. At fold the
orchestrator re-runs run_suite independently + i34 smoke 38/38, generates the round-4 pack FROM THE SUITE'S
OWN MANIFEST, extracts + runs it from an EMPTY DIR, then Nicholas couriers; s7 ratifies ONLY on that PASS,
naming the pack id (M2-D).

## Report-back record (ORCHESTRATOR fills from `plans/fo-41-35be4fdc/reports/` before archiving)

_(empty until fold)_
