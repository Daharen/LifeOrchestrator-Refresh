# UNIVERSAL DERIVED-FRONT-DOOR CONTRACT -- FROZEN (i58; the governing law for the PB-7 surface migration)

**Status: FROZEN at the i58 close (D-0153; orchestrator-inline, D-0119). The ONE governing contract every i59
(root) + i60+ (per-class) knowledge-surface migration builds against.** It ELEVATES the i55 PB-7 design
(`research/2026-08-14-pb7-relayer-design.md` + `-2.md`; its s8 ruleset stays authoritative for decisions)
into a universal class-independent law, RED-TEAMED by `2026-08-15-i58-front-door-redteam.md` (the hardened
invariant set there is binding as part of this contract). Rule: D-0141 (PB-7) + D-0152 (trigger). Reuses,
never forks: the PCB #44 (horizontal) + the memory subsystem #35-43 / `MEMORY_ARCHITECTURE` (vertical). PB-6
(decisions, D-0151) is the first COMPLETE instance -- the existence proof this generalizes.

## 0. The falsifiable claim (what the red-team must break)

Let N = total project knowledge (decisions, iterations, modules, contracts, gotchas, tests, research -- each
a cumulative class). For any ordinary session's boot + primary task: **C1** hot bytes READ are bounded by a
constant B* independent of N; **C2** doc-objects opened bounded by K* independent of N; **C3**
every fact stays losslessly recoverable AND any specific cold fact is reachable in ONE bounded typed query,
never a whole-doc scan; **C4** only deliberately-global questions (full-history synthesis, oscillation
detection, whole-corpus audit) pay an explicit, identified slow-path cost -- never a silent blow-up.

## 1. The universal law (D-0152)

**Raw documents remain the lossless canonical backing but STOP being the ordinary consumption path.** For
every cumulative hot surface the ordinary read path is a bounded, deterministically GENERATED **front door**
over that backing; the raw doc is opened only to expand a specific record (C3) or answer an explicit global
question (C4). The BOOT_PACKET already IS one (generated, bounded, drift-checked); i58 makes "generated front
door" the universal unit and i59/i60+ convert the remaining hand-authored hot surfaces to it. Not "give each
doc a smaller doc" (still scales with N, still tempts compression) but "give each class a generated view + a
queryable cold backing."

## 2. What a derived front door IS (five binding properties)

A surface qualifies iff it is ALL of: **(1) Generated, not authored** -- emitted by a deterministic
producer/renderer from the backing; drop+rebuild byte-identical (double-run gate); no hand-edit -- judgment
enters only upstream as versioned evidence-pointed claims or validated synopses. **(2) Bounded
by construction** -- a hard byte/entry budget the renderer cannot exceed; the budget is a SPILL trigger,
never a compression trigger (s5). **(3) Lossless-backed** -- nothing load-bearing lives ONLY in the front
door; the backing (git + append-only logs + `archive/` + the typed catalog) is complete + rebuildable-from.
**(4) Count-asserted** -- it asserts the full COUNT (+ categories) of what it summarizes, so an omission is
DETECTABLE at boot (F1: a dropped item with no hot entity leaves no anomaly to descend on). **(5)
Spill-reachable** -- everything below the cut is reachable through the shared grammar in ONE bounded typed
query (`deeper:<id>:<kind>` / `section:` / `card:` / a #40/#37 verb), each row expandable to its canonical
span.

## 3. The generic five-layer stack (per class C; generalizes MEMORY_ARCHITECTURE s3)

Each derived layer rebuilds from the one below: **(1)** canonical backing (git + append-only logs +
`archive/`, never rewritten); **(2)** typed indexed records -- a deterministic #38-shaped producer ingests
the backing into `record_kind=<class>` records in the shared #36 catalog (id, status, typed fields, edges,
`source_version_id` + span pointer; skeleton deterministic, only synopses model-generated + validated);
**(3)** the bounded-hot front door (s2); **(4)** selective typed retrieval -- #40 routes across typed channels
(module/plane/status/type/authority/lexical/vector/graph/temporal/supersession), current-only by default,
fused by #37, global = the C4 slow path; **(5)** the expansion path -- every record expands to canonical
authority, a provenance failure ABSTAINS rather than inventing.

## 4. Two engines, one seam (reuse, don't fork -- D-0141 item 5)

**Horizontal = the PCB #44:** the bootstrap doc SET (the *number* of docs) re-layers here (BOOT_PACKET +
`map/` + `claims/` + L2 queries). **Vertical = the memory subsystem:** a single class's unbounded interior
(the 653 KB decision log; the gotcha corpus; test history) re-layers here as typed records. **The seam:** the
engines COMPOSE through ONE shared retrieval grammar -- a PCB entity gains a typed `deeper:<id>:<kind>`
pointer resolving NOT to a whole doc but to a bounded #36/#40 query; the hot front door carries count-asserted
pointers, the cold typed records answer on demand. This is the shared catalog, NOT a new per-class Markdown
router (a router whose own size scales with N is the register-s2 anti-pattern this program kills).

## 5. Spill, never compress (the binding law -- D-0152 G5)

At its budget a front door SPILLS the overflow to a cold typed query leaving a count-asserted pointer; it
NEVER truncates, abbreviates, count-collapses, or drops distinctions to fit. **The PCB renderer's slim-ladder
is the named ANTI-PATTERN, scheduled for REMOVAL at i59/i60+:** 96->72->56-char truncation, entry->count
collapse, authority-list trim to 40, and 20 KB section compression are COMPRESSION mechanized inside the
generator (D-0152). A budget breach is a spill/re-layer event, not a slim (DOC_PROTOCOL s2, D-0141). Test:
after a spill the overflow is reachable in one bounded query AND the asserted count still equals
backing-count -- else the "spill" was compression in disguise.

## 6. Surface classification (what migrates, what does not)

- **Already a front door:** BOOT_PACKET + the decision overlay root (PB-6, D-0151).
- **Migrates (i60+):** CURRENT_STATE's cumulative sub-registries (gotcha corpus -> `record_kind=failure`;
  latest-green test table -> typed test records), the handoff iteration ledger (-> iteration/episode
  records), module/tool catalogs, PROCESS_BACKLOG, research, provenance/archive indexes -- each keeps a
  bounded hand-authored shell where human judgment lives + SHEDS its cumulative interior to typed records + a
  count-asserted pointer.
- **The KERNEL exception (i59; the ONE hand-authored survivor).** START_HERE reduces to a stable ~0.5-1 KB
  bootstrap kernel: how to verify/rebuild the PCB + open the generated packet -- NO iteration, active-work,
  roster, or changing state. It is the ONE exception to "everything generated" because a broken generator
  must still leave a trustworthy recovery entrypoint (the bootstrap-recovery guarantee); it stays tiny +
  stable BY carrying no cumulative content, so it never trips its own cap.
- **Judgment carve-out (red-team-bounded, s8).** A surface whose hot value is irreducible human SYNTHESIS
  (the "reality now" narrative; the live frontier menu; the load-bearing gotcha WINDOW) keeps a bounded
  hand-authored shell -- but that shell is itself budgeted and count-asserts the cumulative registry it
  points into. "Judgment" licenses a bounded shell, never an unbounded hot surface.

## 7. Front-door lifecycle (extends the N7 close-refold)

produce (ingest the backing at close HEAD) -> validate (fail-closed: count-assertion == backing-count; 0
orphan/unbacked) -> render (drift-checked, budget-bounded, spill-not-compress) -> currency (per-commit: if
HEAD advanced past `ingested_through`, ingest the delta BEFORE compiling, else self-label
`currentness=stale`). The PCB N7 close-refold already does this for the map + decision catalog; i60+ extends
the SAME step to each class, so currency is a wave-close ASSERTION -- tracked by the retrieval-byte monitor
(D-0149).

## 8. Hardened invariant set (the freeze gate)

The i58 3-adversary red-team is the freeze gate: `2026-08-15-i58-front-door-redteam.md` (the confirmed
breaks) + `2026-08-15-i58-front-door-hardened.md` (the AUTHORITATIVE hardened invariant set s8; D-0119). The
hardened invariants SUPERSEDE any naive clause here -- incl. C1/C2-both-flat, spill-never-compress, G2, the
kernel -- and are binding as part of this contract. The PB-7 s8 rules are the per-class instance generalized.

## 9. Acceptance gate (when a migration is done; generalizes PB-7 G1-G6)

**G1** B* + K* stay flat as N grows across >=2 orders of magnitude (#37 Tier-1 rehearsal shape). **G2** full
COUNT + categories asserted, no member silently absent, "all live members of class X" is ONE bounded descend.
**G3** every record expands to its canonical span; drop+rebuild byte-identical; git/archive untouched. **G4**
no partially-superseded aspect dropped; a mid-wave boot never serves superseded-as-current. **G5** the front
door SPILLS not compresses; the slim-ladder is REMOVED not re-tuned; `enforced_by` retires gotchas as gates
land. **G6** doc-commit-gate green; P0-1 `non_execution` untouched (retrieved memory is EVIDENCE); boot_read
0-stale at HEAD; the kernel bootstraps even with the generator down.

## 10. Migration sequence + rails (non-displacing)

**i59** = root migration: START_HERE -> the ~0.5-1 KB kernel (s6) + the PCB packet as the first fully-owned
generated front door. **i60+** = class-by-class (CURRENT_STATE interior, handoff ledger, catalogs, backlogs,
gotchas, tests, research), each reusing the PB-6 producer+verb shape. Every increment is design-first ->
red-team-gated -> ships via dev.ship with `docs:[]` workers, NON-DISPLACING (gate ratification + core memory
sequencing outrank it; P0-1 stays FROZEN; the boot-wiring follow-ons -- #36 query-level bounded load, static
plane-map -> live #44 lookup, the `ops:boot-decision-retrieval` canon entity -- fold in). No loss of history:
git + `archive/` + append-only logs stay complete + untouched; the re-layer only ADDS rebuildable views.
