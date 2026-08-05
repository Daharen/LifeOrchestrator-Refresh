# Interpretability / audit-surface scoping packet -- the phenomenology-debugger program, right-sized

**Status:** PROPOSAL (courier: Nicholas -- the D-0051/D-0052 human-courier lane). Authored 2026-08-05 by an
off-box frontier evaluation session at Nicholas's direction, from the Project mirror + read-only disk listing
(mirror verified current against disk this session). The authoring session performed NO repo, Project, or doc
writes; disk remains canonical. Adoption = the orchestrator folds this via one D-entry (suggested `provisional`),
the roadmap rows in section 8, and the PB-2 tie-in in section 7.

**Nicholas's directive:** this program enters scope SOON -- specifically R-1 binds on the wave that builds the
query router (currently deferred to i36/i37 per the i35 scoping), and Unit A fills the next wave's empty
coding lane. Rationale in section 1: audit capacity is now the binding resource, and Tier-1 "done" without an
audit surface cannot be trusted to carry weight into Tier-2 dependence.

**Adoption timing (either path works; NO i35 rework implied):** if this packet arrives at the i35 fold/close,
adoption is a CLOSE-DOCS action -- the D-entry, roadmap rows, and PB-2 sentence ride the normal end-of-session
doc pass under the `git` lease; nothing here reopens, retcons, or amends any i35 unit (R-1 targets the UNBUILT
router; Units A/B are future lanes). If it arrives at i36 scoping, adopt there. The one hard constraint: R-1 must
be standing BEFORE the router unit dispatches.

**Non-displacement clause (load-bearing):** nothing here outranks the standing gates. The ~200MB Tier-1
acceptance rehearsal, the P0-1 adversarial injection suite, the #40 unit-2/unit-3 sequencing, and PB-3 doc-debt
(deadline i40) keep their slots. Units A/B ride otherwise-empty lanes; R-1 is a requirement sentence, not a lane.

## 0. Decision requested

1. **Adopt R-1** (stage-trace emission, section 3) as a contract-level requirement binding on the i36/i37 router
   unit (HANDOFF section-4 unit 3) and every future staged filter; add one line to the CONTEXT_PACKET_CONTRACT
   amendment that lands with the router; D-0077 fold asserts it.
2. **Schedule Unit A** (Widget 05 -- Provenance Map, section 4) into the next available coding lane (slot 003
   convention; empty at i35). Distinct area `widgets/05`, `docs:[]`, no module conflict with the #40/#37 sequencing.
3. **Schedule Unit B** (Widget 06 -- Compile Trace Console, section 5) AFTER the i35 fold + rehearsal artifacts
   exist (i37-i38 window) -- those runs generate exactly the artifacts worth rendering.
4. **Gate Phase 2** (pause/possession/side-by-side, section 6) behind its own design doc + frontier red-team
   (the b4c90545 pattern), post-i40 sunset report. Do not build any of it before then.
5. **Record the PB-2 tie-in** (section 7): the future delegation/coordinator design MUST include the versioned
   delegation-decision event. One sentence now; build nothing.
6. Log ONE D-entry naming this packet AND its companion; archive or distill per DOC_PROTOCOL (a
   `core-docs/research/` landing is the natural home if kept).
7. **Adopt the companion TARGET doc** couriered with this packet -- `2026-08-05-audit-pipeline-target.md`:
   the SELF-SUFFICIENT design target for the FULL human-in-the-loop audit pipeline (mode catalog, tier
   ladder A0-A5, review-cadence header, proposed PB-4). This packet is the ENTRY VEHICLE (= tiers A0/A1);
   the target doc is what the periodic increments walk toward, reviewed every <=4-5 iterations. On
   ratification it promotes to `core-docs/AUDIT_PIPELINE.md`.

## 1. Rationale (why this is acceptance infrastructure, not a side quest)

The spine of the project is the AUDIT LOOP (D-0050): offload is only sound where verification is cheaper than
production, and Nicholas is the human auditor of record. That verify-cost logic applies to HIS attention exactly
as it applies to Claude's tokens -- and at current scale his verify-cost is unbounded because the only audit
surfaces are raw docs, git, and the Verification Console's per-unit verdicts. The system itself refuses to claim
Tier-1 acceptance on synthetic-only evidence (#37 `tier1_accepted=false` until the foreign-corpus rehearsal
passes); the same epistemics, applied one level up, says a segment whose behavior its owner cannot inspect is not
"done" in any sense that supports depending on it for the next segment. Precedent: the Verification Console
(Widget 03) was adopted mid-stream on this exact argument and became the trusted audit surface. This program is
the same move for the memory subsystem, and it is unusually cheap here for a structural reason (section 2).

## 2. Why this is cheap HERE: the contracts already are the instrumentation

Every pane of the proposed debugger renders an artifact the Tier-0/Tier-1 contracts ALREADY mandate. No new
instrumentation of the pipeline is required for Units A/B -- they are READERS.

| Debugger pane | Existing mandated artifact |
|---|---|
| Exact model view | The packet IS the model's whole context (P0-1 regions, rendering contract, exact transport accounting; deterministic `packet_id`) |
| Retrieval + selection trace | selpol output: `ranked[]` preserving lexical/vector/fused ranks, `selection_rank`, `reason_codes[]`, `features_by_candidate`, `stages[]`, `omission_manifest` |
| Rule / exception stack | `reason_codes[]` (`hard_filter_namespace`, `hard_filter_stale`, `superseded_demote`, ...) + versioned `classifier_policy` with the i33 U5' explicit-override rule |
| Token + state ledger | `consumer_profile` + final-rendered count + `count_method`; #42 immutable snapshots (`state_version`, CAS lineage) |
| Task timeline | #39 episodes (structural `stage_sequence`) + #42 heads + plan/report dirs under `runtime/plans/` |
| Hierarchy navigation trace | i34 V3 fields: `retrieval_completeness`, `pruned_branch_count`, `prune_reasons[]`, `fallback_used`, stage lineage (`retrieval_stage_id`/`parent_stage_id`/`retrieval_plan_id`) |
| Channel counterfactuals | MEMORY_CONTRACT s6 MANDATED hybrid attribution (lexical-only vs vector-only vs hybrid, per-query rescued/harmed) -- #37 machinery is the seed |

The one gap that will get expensive if it closes wrong: the router (unbuilt, i36/i37) and future staged
eligibility filters. Hence R-1, the only time-sensitive item.

## 3. R-1 -- the stage-trace requirement (bind at i36 router scoping; cost ~0)

Normative text, paste-ready for the router brief + the contract amendment that lands with it:

> Every staged candidate-transforming step in retrieval routing and selection -- the multi-channel query router's
> classification/routing/channel-selection stages, skill/procedure eligibility stages when built, and any future
> staged filter -- MUST emit a deterministic, integer-only stage-trace record per stage:
> `{retrieval_plan_id, stage_id, parent_stage_id?, policy_id, policy_version, candidates_in, removed[]:
> {record_id|channel_id, reason_codes[]}, candidates_out, tie_break_key?}`, byte-identical on re-run, carried in
> the compile's `evaluation_hooks`/diagnostics so #37 can score per stage. The trace is a DIAGNOSTIC ARRAY under
> i33 U1': namespace-closure-checked, sanitized fail-closed, no cross-namespace identifying metadata. This is a
> trace-EMISSION requirement only -- zero behavior change. The D-0077 fold asserts presence + determinism.

This extends the selpol `stages[]`/`reason_codes[]`/A5 stage-lineage discipline to the router at birth. Retrofit
later would mean re-opening a shipped router contract; adopted now it is one paragraph in a brief.

## 4. Unit A -- Widget 05 "Provenance Map" (the construction map; next coding lane; est. 1 session)

**Scope.** Read-only native Widget (WinForms + `launch.bat`, D-0038) that joins what the process already
maintains: MODULE_ROADMAP status, CURRENT_STATE tests table + Known failures, DECISION_LOG_INDEX rows, git log
trailers (dev.ship named-file commits), the HANDOFF iteration ledger, `runtime/plans/<id>/` reports, and
Verification Console verdicts where parseable. Views: what exists (module -> version -> iteration -> D-entry ->
commit -> files); what changed since a chosen iteration/date; verification state per unit; what is planned but
unbuilt (roadmap Build priority + the HANDOFF candidate menu). This is the audit funnel's top altitude:
map -> gates -> trace; attend at the top, descend on anomaly.

**Acceptance gates.** (a) Renders entirely from canonical on-disk docs + read-only git -- ZERO new doc-upkeep
obligations; (b) deterministic parses with graceful degradation (an over-budget/malformed hot doc surfaces as a
visible flag -- incidentally auto-surfacing PB-3 debt); (c) "new since last visit" diff persisted only in the
widget's own runtime dir; (d) strictly read-only -- no doc writes, no git writes, no executor jobs, no model
calls; (e) usable answer to "what did iteration N build and under which decision?" in one click.

**Lane fit.** Coding lane (CPU), exclusive area `widgets/05-provenance-map/`, `docs:[]`, no lease beyond git for
the dev.ship commit. Fits slot 003 in i36 without touching the #40 sequencing.

## 5. Unit B -- Widget 06 "Compile Trace Console" (+ compile-layer counterfactual runner; i37-i38; est. 1-2 sessions)

**Scope.** Read-only renderer over compile/eval artifacts: the packet's four regions with trust banners (P0-1);
selpol `ranked[]`/`reason_codes[]`/`stages[]`/`omission_manifest` (+ R-1 router traces once they exist);
classifier policy + resolved `temporal_intent` incl. the override path; retrieval plan/stage lineage with
shortlist/descend + V3 completeness/prune fields; `consumer_profile` token ledger; #42 `state_version` timeline.
PLUS a counterfactual runner: a thin harness that re-invokes #40's compile CLI on the SAME pinned
`corpus_version`/`tree_version` with exactly one varied input -- channel mask (seeded from #37's mandated hybrid
attribution), selection-policy version, effective namespace set, `temporal_intent`, budget, or an excluded
`record_version_id` -- then diffs packets (`packet_id`, ranked deltas, disposition delta, omission delta). This
answers "did success depend on the vector channel / one record / a rule / a summary / the working state / the
budget" deterministically, with zero model calls.

**Acceptance gates.** (a) Byte-identical re-render on unchanged inputs; (b) ablation output reconciles with
#37's hybrid-attribution numbers on the shared fixture; (c) renders REAL i35-fold and rehearsal artifacts, not
synthetic mocks; (d) writes nothing outside its own runtime dir; (e) every displayed diagnostic honors the i33
sanitization rules (the console must not become a namespace side-channel).

**Sequencing.** After the i35 fold: the wired #40 CLI + the rehearsal produce the first artifact corpus worth
rendering. Building it earlier means rendering stubs.

## 6. Phase 2 -- ride-along pause, Possession Harness, side-by-side (design-first; post-i40)

Deferred by design, not rejected. Gate: its OWN design doc -> frontier red-team -> build (the b4c90545 pattern),
scheduled after the i40 mandate sunset report. Constraints already known and non-negotiable in that design:

- **Pause points sit OUTSIDE lease windows.** A human deliberating must never hold the `gpu` lease or block a
  finalize -- pause at packet-ready boundaries only (the D-0055/56 wedge, with a person as the orphan).
- **Possession = existing affordances only.** Render the packet (the packet already IS total agent-visible
  context -- isolation comes free from P0-1/A5); accept only the existing ops as human moves: answer /
  `needs_expansion` via the immutable expand delta / abstain / conflict report / baton per the #42 schema.
- **Possession sessions emit labeled fixtures.** Every blind human-vs-9B run on an identical packet is a
  human-adjudicated eval case for #37 -- MEMORY_BENCHMARK explicitly wants scarce human judgment spent there.
  Nicholas's debugging time mints ground truth as a byproduct.
- **`non_execution` holds.** A possessed context grants no side-effect authority; the P0-1 gate is untouched.

**Deliberately unbuilt until evidence demands (state them so scope cannot creep):** roll-forward counterfactuals
through live model calls (each is a real serialized run on a one-model box -- batch-only if ever, never an
interactive scrubber); embedding interpretability beyond neighbors/ranks/ablation (research-grade, low
operational yield; the vector channel is empty today anyway); any live-operate IDE surface (the executor +
Verification Console already own manual invocation).

## 7. PB-2 tie-in -- the delegation-decision event (one reserved sentence; build nothing)

When the local-coordinator/delegation design (PB-2, D-0080-authorized, unbuilt) is eventually written, it MUST
include a versioned DELEGATION-DECISION event: `{delegation_policy_id, policy_version, trigger_class,
reason_codes[], spawned_context_refs[]}` -- structurally an EPISODE STAGE in the #39 record body (the
`record_kind` enum stays CLOSED), so every spawn is as auditable as every selection. This packet adds the
requirement to PB-2's text; it does not open the design.

## 8. Entry mechanics (orchestrator)

Roadmap rows (content below; format per MODULE_ROADMAP conventions): Widget 05 Provenance Map -- read-only
project-provenance viewer; next coding lane; acceptance gates s4. Widget 06 Compile Trace Console -- read-only
compile/eval trace renderer + compile-layer counterfactual runner; post-i35-fold; gates s5. Phase 2 possession
program -- design-first, post-i40, red-team-gated; constraints s6. Plus: R-1 into the i36 router brief + the
router-wave contract amendment; the PB-2 sentence; one D-entry naming this packet. Suggested naming is
ratifiable; nothing here modifies any frozen field.
