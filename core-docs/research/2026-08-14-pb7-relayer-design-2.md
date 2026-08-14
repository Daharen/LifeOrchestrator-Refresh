# PB-7 KNOWLEDGE-SURFACE RE-LAYER -- DESIGN (part 2/2: increment + red-team)

**Continues `2026-08-14-pb7-relayer-design.md` (s0-s4).** DESIGN-FIRST (i55, D-0141/PB-7). NOT a build. The
s8 hardened ruleset is AUTHORITATIVE over the s4 naive rule.

## 5. Why neither axis scales linearly

- **bytes-per-doc (vertical).** Hot views are bounded by construction: BOOT_PACKET <= the N4 bar
  (<=20,000 B), CURRENT_STATE <= its 34 KB cap. Their cumulative interiors (decision history, gotcha corpus,
  test history) are SHED to typed records retrieved selectively; growing decisions 148 -> 10,000 grows the
  cold catalog + hierarchy DEPTH, not the hot bytes.
- **docs-per-task (horizontal).** Boot reads are a FIXED set (BOOT_PACKET -> CURRENT_STATE +
  SEALED_CHECK/handoff-fallback), not "all 22 core-docs + 37 research + the index." The PCB collapses the doc
  SET into one packet + bounded queries; the 38th research doc adds a record, not a mandatory read.
- Neither B* nor K* scales with N -- **once the s8 hardening bounds the standing-constraint subset** (else
  F1/F2 leave a growing residue). Global questions are the explicit exception (C4).

## 6. Guardrails (binding)

- **No loss of history.** git + `archive/` + the append-only `DECISION_LOG.md` stay complete + untouched;
  the re-layer only ADDS derived, rebuildable views (drop+rebuild always available; `MEMORY_ARCHITECTURE`
  s1). "Reconstruction impossible" is a correct abstention, never an invitation to invent.
- **doc-commit-gate + budgets SURVIVE.** Budgets still catch bloat; the growth-exempt CATALOG kind (D-0139)
  exists; the >40 KB clause becomes a re-layer TRIGGER (D-0141), not a slim demand. PB-7 removes no gate; it
  ADDS the producer as a commit-time ingestion trigger (F4).
- **P0-1 stays FROZEN.** Retrieved memory is EVIDENCE (`can_instruct=false`); PB-7 touches only the
  knowledge/evidence plane, never control/action authority. `non_execution:true` holds (`AUDIT_PIPELINE`
  s3.6).
- **Determinism.** Identity/status/edges/hierarchy/staleness/budgets + the hot predicate = deterministic
  code (s8 makes "load-bearing" computed, not judged); only synopses are model-generated + validated.

## 7. First build increment (ONE scoped unit): the decision re-layer READ-PATH (PB-6)

Design-first; build is a later scoped wave. Scope = the minimum that proves the decoupling on the largest,
most-painful surface (640 KB log; index at cap; the i50 ledger-collapse) and exercises the PCB<->memory seam
every later class reuses:

- **Producer (deterministic, #38-shaped).** Ingest `DECISION_LOG.md` (+ index rows) into
  `record_kind=decision` records in #36: id, title, status, affected modules/planes, type, authority,
  date/iteration, edges, `source_span` -> canonical. Rebuildable; double-run byte-identical; coverage-
  validated vs the index. **Red-team-required fields:** `binding_scope ∈ {standing_prohibition, invariant,
  ordinary}` (deterministic from markers "FROZEN"/"never"/"prohibited"); a `partially_superseded_by` edge
  distinct from full `superseded_by`; `enforced_by=<gate|none>`; `ingested_through=<HEAD at last ingest>`.
- **Retrieval verb (built engines).** "Compile the task-relevant decision set": signals (modules, plane,
  recency) -> current + relevant decisions (bounded top-k, supersession-aware, current-only default), each
  expandable to canonical. Route via #40 + #37 -- no new retrieval arch.
- **Hot-surface change.** Boot stops ingesting `DECISION_LOG_INDEX.md` whole; the overlay carries the
  bounded standing-constraint ROOT view (F1) + live frontier; task history arrives via the verb.
- **Why decisions first:** largest surface + live pain; D-0139/D-0141 name it first; the decision +
  supersession seams exist; proves C1-C4 before any other class. Later classes reuse the same producer+verb
  shape.

## 8. Red-team -- 3 in-session adversaries (D-0119). THREE CONFIRMED BREAKS.

Independent adversaries (whole-doc-open / currency / unbounded-growth) CONVERGED: the s4 `HOT ⇔ current ∧
in-window` rule cannot handle records that are **current forever** or **partly** superseded.

- **F1 (BREAKS, most damaging -- growth + whole-doc). Standing-constraint hot set is unbounded.**
  Prohibitions/invariants ("P0-1 FROZEN", "never `git add -A`", D-0051/D-0079) are `status=current` forever,
  never acquire a supersession edge, are universally relevant -- so the lone demotion rule never fires, yet
  the set grows monotonically with project age (2-9x over the boot bar at the s5 stress point). Truncation
  is UNDETECTABLE: a dropped prohibition has no hot entity -> no `deeper:` pointer -> no anomaly.
  B* becomes a growing function under a fixed cap = "progressively harsher compression," the register-s6
  self-failure signal.
- **F2 (BREAKS). Cross-cutting gotcha residue has no deterministic demotion path.** Module-scoped gotchas
  re-layer cleanly (`deeper:<module>:failure`); session-universal ones (dev.ship false-negative, stale
  `device_stage_files`, native-git verify, heartbeat-not-process-list) hit EVERY wave, can't be
  module-scoped, and CURRENT_STATE forbids the only lever ("Do not compress a live gotcha away"). "Load-
  bearing" was a human judgement -- a determinism violation.
- **F3 (BREAKS). Partial supersession permanently drops still-governing doctrine.** One entry, two aspects
  (the real D-0050 offload + verify-cost); a later entry revises ONE aspect, recorded "supersedes D-0050";
  record-granular supersession -> D-0050 COLD -> the AND-gate makes it un-promotable forever; the in-force
  aspect is silently absent and expansion can't fire on an already-filtered record. Permanent; scales with
  every partial supersession.
- **F4 (BREAKS, runner-up). Between-wave currency window.** "0 stale at HEAD" holds only at close instants;
  a mid-wave append (D-0142 supersedes D-0100) advances HEAD while the derived catalog is un-re-ingested, so
  a mid-wave boot serves D-0100 as current AND omits D-0142 -- on the highest-churn surface we have.
- **Held (fairness).** Bounded-fanout absorbs entity/card growth into DEPTH; supersession-chain
  reconstruction is deterministic + bounded; a universal-seam change is legitimately global (C4). Open-
  rulings + module-roster/test-table SURVIVE-WITH-CAVEAT (need a real close cadence / a true O(1) aggregate);
  cross-class "why" + oscillation prior-failure ride model-inferred completeness -> correct abstention.

**AUTHORITATIVE hardened ruleset (supersedes s4's naive rule):**
1. **`binding_scope` exemption.** `standing_prohibition|invariant` records are exempt from recency/relevance
   demotion; they leave hot ONLY via explicit repeal/full-supersession OR rule 2.
2. **Demote-on-enforcement (honest retirement).** A prohibition/gotcha stays hot only while
   `enforced_by=none`; once bound to a deterministic gate (lint, AST-parse, lease wrapper, monitor) it
   demotes to a cold record with `enforced_by=<gate>` -- the session need not CARRY what the machine now
   PREVENTS (precedent: `$var:`->dev.ship AST; P0-1->#43). Predicate:
   `hot ⇔ status=live ∧ enforced_by=none ∧ (cross_session_scope ∨ recurrence≥k)`.
3. **Depth-bound + budgeted overlay.** Put standing constraints under the #36 bounded-fanout hierarchy; the
   overlay pins only the ROOT synopsis + child-category pointers + an ASSERTED COUNT (completeness PROVED
   without every leaf) and descends the branch matching the wave's action-class. The overlay is a #40
   budgeted region (rank = breadth x severity x recency x recurrence); below the cut, SPILL to a cold query
   (`deeper:*:prohibition`) -- spill, never compress.
4. **`partially_superseded_by` + demotion guard.** Producer emits full `superseded_by` (-> demote) ONLY on
   an explicit total-replacement marker; else defaults to `partially_superseded_by` and KEEPS the
   predecessor `status=current` (conservative over-inclusion -- bounded, non-misleading, never silent loss).
   Demote to COLD only on a FULL supersession/fold/close edge.
5. **Per-commit currency.** On every boot/compile, compare `ingested_through` to canonical HEAD; if HEAD
   advanced, incrementally ingest the append delta BEFORE compiling; if deferred, mark `currentness=stale`
   and degrade retrieval to "current as of <version>, K un-ingested appends." Wire the producer into the
   doc-commit-gate.
6. **Slow-path negatives.** A completeness-required negative ("is this novel / did we ever decide X?") is C4
   slow-path, never a fast query; promote a "settled-questions" reflective index to a boot pointer so
   re-litigating a PREVIOUSLY-settled question is caught cheaply.

## 9. Acceptance gate (an increment is "done" when)

Register s6 principle + the s8 hardening (measurable, not "the doc got smaller"):
- **G1 bounded hot.** Boot hot-bytes B* + doc-count K* stay flat as N grows across >=2 orders of magnitude
  (the `MEMORY_ARCHITECTURE` Tier-1 rehearsal shape, scaffolded by #37).
- **G2 completeness provable.** The standing-constraint overlay asserts its full COUNT + categories at boot
  (rule 3); no binding constraint is ever silently absent; "all live constraints of action-class X" is one
  bounded descend.
- **G3 lossless + expandable.** Every record expands to its canonical span; drop+rebuild is byte-identical
  (double-run gate); git/archive untouched.
- **G4 honest currency.** No partially-superseded aspect dropped (rule 4); a mid-wave boot never serves
  superseded-as-current (rule 5) -- it re-ingests or self-labels stale.
- **G5 no harsher-compression drift.** The overlay spills to cold, never compresses (rule 3); `enforced_by`
  retires >=1 gotcha as gates land.
- **G6 gates intact.** doc-commit-gate green; P0-1 `non_execution` untouched; boot_read 0-stale.

**Bottom line: the re-layer IS worth building** -- the two-engine architecture + the seam are sound; the
naive HOT-iff-current rule is not. The s8 hardened ruleset is the design a builder implements; first
increment = the PB-6 decision read-path (s7) carrying those fields.
