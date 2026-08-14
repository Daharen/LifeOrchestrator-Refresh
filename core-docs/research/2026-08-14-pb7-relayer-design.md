# PB-7 KNOWLEDGE-SURFACE RE-LAYER -- DESIGN (part 1/2: architecture)

**Status: DESIGN-FIRST digest (i55, D-0141/PB-7; Opus lane, orchestrator-inline per D-0119). NOT a build.**
Companion: `2026-08-14-pb7-relayer-design-2.md` (asymptotics + guardrails + first increment + red-team +
acceptance gate). Register + governing rule: `research/2026-08-12-knowledge-surface-relayer-program.md`;
`DECISION_LOG.md` D-0141/D-0139. Reuses, does not fork: `MEMORY_ARCHITECTURE.md` (vertical) + the PCB
`modules/44-project-map/` (horizontal). Section numbering continues into part 2 (s5-s9).

## 0. Mission + the falsifiable decoupling claim

PB-7 makes cumulative project knowledge (decisions, iteration ledgers, contracts, module/tool catalogs,
research, failure history, provenance) grow without bound while the surface an ordinary session must READ
stays bounded. The i53 canon (prefer `section:`/`card:` over whole-doc opens) steers retrieval BEHAVIOR;
PB-7 shrinks WHAT there is to retrieve. Same decoupling `MEMORY_ARCHITECTURE.md` s0 formalizes, applied to
the project's own documents.

**Decoupling claim (the thing the red-team must try to break).** Let N = total project knowledge (decision
count, module count, research count, ...). For an ordinary orchestrator boot + wave-scoping task:
**(C1)** bytes read is bounded by a constant B* independent of N; **(C2)** doc-objects opened is bounded by
a constant K* independent of N; **(C3)** every fact stays losslessly recoverable, and any specific cold fact
is reachable in ONE bounded typed query (not a whole-doc scan); **(C4)** only explicitly-global questions
(full-history synthesis, oscillation detection, whole-corpus audit) pay an explicit, identified slow-path
cost -- never a silent blow-up. A re-layer is "done" per this claim + the register s6 acceptance principle,
NOT because a doc got smaller.

## 1. Two engines, one seam (reuse, don't fork)

D-0141 item 5 mandates ONE program over the two engines already built, preferring the shared catalog over
per-class routers:

- **Horizontal axis = the PCB (#44 `project.map`), already the DEFAULT bootstrap (D-0146).** BOOT_PACKET =
  the bounded-hot boot view; `map/` + `claims/` + the L2 narrative queries (`section:`/`card:`/`--q`/
  `evidence:`/`deeper:`) = the indexed representation over the core-doc SET. The bootstrap doc set (the
  *number* of docs) re-layers HERE.
- **Vertical axis = the memory subsystem (#35-43) + `MEMORY_ARCHITECTURE` (T0-T3).** Typed records (#38
  repo.intel producer shape, #36 artifact.search FTS5 catalog + Tier-1 bounded-fanout hierarchy nodes),
  query-aware selective retrieval (#37 selpol_rrf_v1, #40 context.compiler), supersession-aware records.
  The deep cumulative REGISTRIES (a single doc's unbounded interior: the 640 KB decision log especially)
  re-layer HERE via the M2-C "docs-into-memory" re-layer.

**The seam (the load-bearing design decision).** The two engines are NOT parallel; they COMPOSE through a
shared retrieval grammar. The PCB map already exposes bounded queries over its entities. PB-7 makes a
cumulative registry's typed records reachable through THAT SAME grammar: a PCB entity gains a typed
`deeper:<id>:<kind>` pointer (kind in decision|contract|failure|research|...) that resolves NOT to a whole
doc but to a **bounded memory query** against #36/#40 -- e.g. `deeper:<module>:decision` -> "the current +
task-relevant decisions touching this module," compiled by #40 + #37, each row expandable to its canonical
`DECISION_LOG.md` span. The hot packet carries pointers; the cold typed records answer on demand. This is
the shared catalog, not a new per-class Markdown router (which would itself scale with the corpus -- the
register s2 anti-pattern).

## 2. The generic re-layer stack (per cumulative class C)

Generalizes `MEMORY_ARCHITECTURE.md` s3 + the register s3 target. Five layers; each derived layer is
rebuildable from the one below (nothing important lives only in the hot view):

1. **Canonical backing (lossless, immutable).** git + the append-only `DECISION_LOG.md` + `archive/`. NEVER
   rewritten by a re-layer; complete for all time.
2. **Typed indexed records (derived, versioned).** A deterministic producer (the #38 repo.intel shape)
   ingests the backing into `record_kind=<class>` records in the shared #36 catalog: stable id, status
   (current/superseded/folded/closed), typed fields, edges (`supersedes`/`derives_from`/`describes_*`), and
   a `source_version_id` + span pointer back to canonical. Skeleton is DETERMINISTIC (identity, status,
   edges, hierarchy splits -- `MEMORY_ARCHITECTURE` s1); only synopses are model-generated + validated.
3. **Bounded-hot current/router view.** A small always-loaded view carrying only near-universally-useful
   material + pointers into (2). For the doc SET this is the BOOT_PACKET; for decisions it is the packet
   OVERLAY (live frontier + open rulings + prohibitions) plus a compiled task-relevant set -- never the
   whole index.
4. **Selective typed retrieval.** The #40 planner classifies the need and routes across channels
   (module/plane/status/type/authority/lexical/vector/graph/temporal/supersession), current-only by
   default, fused by #37 selpol; global questions take the explicit slow path.
5. **Expansion path.** Every condensed record expands through intermediate records to canonical
   authority/evidence; a provenance failure abstains rather than inventing (`MEMORY_ARCHITECTURE` s8).

## 3. The three named targets

**(A) `DECISION_LOG.md` (~640 KB, append-only) -- the archetype; = PB-6, the first increment.**
Stays canonical + lossless; NEVER read whole. HOT = the packet overlay's live decisions + a bounded
compiled "task-relevant + recent" set. COLD = every superseded/folded/closed decision, reachable by typed
query (module/plane/status/type/supersession/precedent). The `DECISION_LOG_INDEX.md` whole-file bootstrap
ingestion is replaced by a selective index-of-index: decisions become `record_kind=decision` records in #36
with supersession edges; #40 returns the relevant set. Exactly the D-0139 PB-6 target (separate the lossless
ledger / the complete routing catalog / the selective retrieval / the bounded-fanout hierarchy).

**(B) `CURRENT_STATE.md` (34 KB cap) -- keep the hot view; shed its cumulative sub-registries.**
CURRENT_STATE is ALREADY the archetypal bounded-hot current-state view (reality-now; replace-don't-append;
no prior-accretion chains). Its INTERIOR carries two cumulative sub-registries that grow with the module count:
the "Known failures" gotcha corpus and the "Current tests" latest-green table. Re-layer moves the FULL
gotcha corpus to `record_kind=failure` records (component/symptom/recurrence/authority) and the full
test-history to typed test-result records, leaving CURRENT_STATE with a bounded "load-bearing gotcha
window" + "latest-green summary" + pointers. The doc stays the hot view; its unbounded interior goes
vertical. (A `CURRENT_STATE.json` counterpart = the PCB FO-2 lever named in the doc header.)

**(C) `DECISION_LOG_INDEX.md` (~22 KB, growth-exempt CATALOG, D-0139) -- the transitional router.**
A router whose own size scales with the corpus -- the register s2 anti-pattern, tolerated by D-0139 as an
interim (growth-exempt, per-row density; the 40 KB trigger is a WARN, not a reject). Re-layer replaces its
whole-file bootstrap role with the memory hierarchy's bounded-fanout index-of-index so the hot routing
surface grows in DEPTH, not linearly. It survives as the complete, human-readable routing catalog (cold,
retrievable, still the append-a-row upkeep target) but is NOT bootstrap-ingested whole once (A) lands.

## 4. Read path, promotion/demotion, currency

**Read path = the map->gates->trace->possession funnel (`AUDIT_PIPELINE.md` s0, same decoupling).** Attend
at the TOP (BOOT_PACKET overlay + CURRENT_STATE hot view) -> descend on ANOMALY via one bounded typed query
(`deeper:`/`section:`/`card:`/FTS) -> expand to canonical only when a specific record is in question ->
whole-corpus traversal ONLY for an explicitly-global question (the slow path). Hot first; cold on demand;
global is explicit and costed.

**Promotion/demotion (deterministic -- never model judgement).** A record is HOT while (status=current) AND
(within the recency OR task-relevance window). Demotion to COLD is deterministic on a supersession/fold/
close edge (the index already marks superseded predecessors in-row); the record leaves the hot compiled set
but stays fully retrievable via history/supersession/precedent queries. Promotion into a task's hot set is
the #40 planner matching typed signals. A recurring cross-history pattern (A->B->A oscillation, a recurring
failure, a reopened settled choice) may be promoted into a provenance-linked reflective/failure record
surfaced on relevance -- without loading the whole history (register s3 cold-history clause).

**Currency (how it holds).** Canonical is authoritative + append-only; derived records carry
`record_version_id`/`source_version_id` + content hashes. A changed leaf marks its ancestor-path synopses
STALE (the `currentness` enum), regenerated LAZILY and served stale-but-provenance-intact until regenerated
(`MEMORY_ARCHITECTURE` s6). The PCB's N7 close-refold already restamps the map at each wave close (0 stale
on boot_read at HEAD); PB-7 extends that same deterministic close-refold to re-stamp the registry records,
so currency is a wave-close ASSERTION, not a manual chore -- dovetailing with the i55 retrieval-byte monitor
(the second lane), which makes the hot-surface byte cost a per-wave measurement.

**The naive rule above is INSUFFICIENT** -- part 2 s8 REFINES it (`binding_scope` exemption,
`partially_superseded_by` edge, `enforced_by` demote-on-enforcement, per-commit currency); that hardened
ruleset is authoritative.

Continued -> `2026-08-14-pb7-relayer-design-2.md` (s5 asymptotics, s6 guardrails, s7 first increment, s8
red-team, s9 acceptance gate).
