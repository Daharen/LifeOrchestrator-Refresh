# i59 ROADMAP RECONCILIATION -- planning addendum (D-0155; NOT a live control-plane owner)

Evidence-backed planning record produced by the i59 planning-reconciliation addendum (Nicholas's directive).
It explains the plan; it does NOT become a second source of truth. Canonical owners: `CURRENT_STATE.md`
(reality now), `FANOUT_ORCHESTRATOR_HANDOFF.md` (frontier/ops), `PROCESS_BACKLOG.md` (PB items), the PCB
overlay (map frontier), `DECISION_LOG.md` (rationale). No core logic changed; iteration stays 59, next 60.

## The verified i50-i59 arc (three clumps)

- **i50-i53 -- made handoff ingestion smaller + targeted.** The first attempt was insufficient; `card:`/
  `section:` retrieval + stronger canonicalization made the PCB `BOOT_PACKET.md` the DEFAULT orchestrator
  bootstrap (i53, D-0146; legacy handoff = fallback). Efficiency rider F-i53-eff opened: prefer bounded
  fetches.
- **i54-i57 -- began stopping high-growth docs from being read as monoliths.** The decision log became the
  first serious relevance-selected / index-derived pilot: the PB-6 decision re-layer DESIGNED (i55, D-0149)
  -> BUILT (#45 decision.intel + #40 verb 0.10.0, i56, D-0150) -> BOOT-WIRED (standing catalog + overlay root
  view, i57, D-0151; boot stops whole-ingesting the index).
- **i58-i59 -- generalized into a common generated-front-door architecture.** i58 FROZE + 3-adversary
  red-teamed the universal derived-front-door contract (hardened s8 authoritative, D-0153). i59 migrated the
  ROOT: START_HERE -> a stable routing KERNEL, a bounded generator-independent COLD_BOOT_CARD, and the shared
  `ops/frontdoor/` registry + rebuild + gate + migration gate (D-0154).

**Unfinished + load-bearing: F-i53-eff.** Bounded `card:`/`section:` retrieval EXISTS, but agents still
routinely whole-open documents -- the retrieval ledgers show **zero bounded opens** in the observed i55/i58/
i59 sessions (bounded_fraction 0.0). This is an ADOPTION / affordance / enforcement gap, not an architecture
failure. F-i53-eff stays OPEN until observed behaviour is bounded by default -- infrastructure existence does
NOT satisfy it.

## The clarified direction (D-0155)

1. Agent-facing material converges on bounded, GENERATED projections of canonical facts, task-selected.
2. Canonical records + evidence stay authoritative; generated front doors are never a second source of truth.
3. Routine open/close/housekeeping/baton converge on a **resumable deterministic transaction**, with Frontier
   Agent judgment inserted ONLY where semantic impact cannot be decided mechanically -- the operating model is
   **Frontier Agent in the Deterministic Loop** (routine close is not human-gated).
4. Nicholas gets a bounded management/audit projection for observability + steering -- NOT a per-document
   approval gate.
5. Changes propagate only through demonstrated dependencies + declared impact -- no stale neighbours, no
   speculative repo-wide cascades.

## The i60-i79 rolling roadmap (i60-i61 committed; later blocks = sequenced intent, revalidated at boundaries)

- **i60-i61 -- make the small handoff actually small, truthful, easy to use.** Prove + ENFORCE bounded
  bootstrap/retrieval on fresh work; close F-i53-eff (bounded `card:`/`section:` the easy default, whole-doc
  fallback needs an explicit reason); make retrieval measurement automatic (zero-bounded-opens cannot pass
  unnoticed via a self-reported monitor); repair FO-6 (`-Action query -Repo` passthrough); produce a bounded
  generated MANAGER/PROGRAM projection from canonical state; treat SP3/M-03 + stale version/test claims as
  explicit TRUTH questions (no silent activation). **Exit:** a fresh agent starts from START_HERE/
  COLD_BOOT_CARD, does representative tasks without routine whole-doc reads, leaves machine-verifiable
  retrieval evidence; all live planning surfaces agree on current truth.
- **i62-i67 -- make closing + housekeeping ONE resumable procedure.** i62 contract + red-team the close
  transaction (ownership, failure states, recovery); i63 the close manifest/materializer + freshness
  assertions; i64 evidence-based impact detection (fingerprints, dependency + targeted-test selection); i65
  the two deterministic validation stages + bounded Frontier correction loops; i66 protected local->GitHub/
  mirror reconciliation (managed-ref pruning, remote verify, in-flight exclusions); i67 fault-inject, resume
  from partial failure, prove idempotence, cut over. A required-doc iteration marker may be ONE freshness
  signal but must NOT license a touch-every-doc sweep; applicability = declared ownership + evidence-based
  impact.
- **i68-i73 -- turn the major changing document FAMILIES into bounded generated views** (semantic families,
  not random files). i68-i69 current-work family (current state / handoff / frontier / backlog slices / open
  rulings); i70-i71 health family (gotchas / failures / test evidence / audit status / warnings); i72-i73
  system-catalog family (modules / tools / contracts / versions / architecture + edge/schema compatibility).
  Rebuild only views affected by changed facts; do NOT recursively wrap every view in another permanent index.
- **i74-i76 -- make memory change how the agent works.** Connect #21 retrieval -> #40 task context; make #42
  persistent working state useful across iteration boundaries; capture #39 episodes/failures from real work;
  let #41 consolidate repeated procedures; benchmark on representative LifeOrchestrator work. #40 beam-width
  stays evidence-triggered (promote only if workload evidence shows retrieval is bottlenecked there).
- **i77-i79 -- make the system inspectable, then re-plan.** Preserve/reconcile request -> selected context ->
  relevance reasoning -> actions -> output -> instruction<->output correspondence; complete the remaining
  raw-prompt FRONT / live ride-along / OUTPUT-reconciliation audit work (the AUDIT_PIPELINE build block);
  prove pause/replay/takeover/post-hoc boundaries; i79 reviews the prior 20 iterations + sets the next horizon
  from evidence.

## Deferrals (owner + evidence-based trigger; recorded in PROCESS_BACKLOG / MODULE_ROADMAP / the overlay)

- **First additional PB-7 class migration:** DEFER i60 -> **i68** (sequencing, not abandonment). Owner:
  PROCESS_BACKLOG PB-7. Trigger: bounded-ingest adoption (F-i53-eff satisfied) + the close transaction landed.
- **F-i53-eff:** pull FORWARD to i60-i61; keep OPEN until observed bounded-by-default. Owner: MODULE_ROADMAP
  #44 rider / CURRENT_STATE. Trigger: machine-verified bounded retrieval on representative tasks.
- **FO-6 `-Action query -Repo` passthrough:** pull FORWARD to i60 (obstructs use of the built architecture).
  Owner: MODULE_ROADMAP #44 FO-6.
- **#44 FO-1/FO-2/FO-3/FO-4/FO-5:** placed i60-i67 / the first semantic migration per verified dependencies
  (FO-2 CURRENT_STATE projection + FO-1 changed-since/impact + FO-3 map->#36 records feed the close
  transaction + i68-i69 current-work family; FO-5 doc-gate rows when views promote). Owner: MODULE_ROADMAP #44.
- **#40 beam-width:** evidence-triggered, NOT auto-scheduled. Owner: MODULE_ROADMAP #40 / PB.
- **PB-2 delegation seam:** deferred until its trigger / a spare lane; must not displace control-plane work.
- **Widget 08 explain-window-close defect:** rides the next relevant audit/UI touch (D-0134) unless severity
  demands earlier. Owner: MODULE_ROADMAP widgets/08 / CURRENT_STATE.
- **SP3/M-03:** retain the mandate/authority deferral; i60 MAY reconcile the underlying truth + budget but must
  NOT silently license M-03. Owner: SEALED_CHECK_47 (sealed) + PROCESS_BACKLOG.
- **P0-1 activation:** remains FROZEN (retrieved memory is EVIDENCE).
- **Generators / video.interpret / real-time perception / broad training / warm-pool / portability:** existing
  freezes/deferrals preserved (D-0079/D-0080) unless a separate authoritative trigger already fired.
- **Research / provenance / history front doors:** deferred until measured ingestion pressure justifies another
  semantic family.

## Source pointers
D-0146 (PCB default) · D-0149/D-0150/D-0151 (PB-6 arc) · D-0152/D-0153 (i58 contract freeze) · D-0154 (i59
root migration) · `research/2026-08-15-i58-front-door-hardened.md` (hardened s8) · `research/2026-08-15-i59-
root-migration-{hardened,redteam}.md` · AUDIT_PIPELINE cadence header · SEALED_CHECK_47 (SP3/M-03).
