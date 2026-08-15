# i59 ROOT-MIGRATION DESIGN — HARDENED (post-red-team; AUTHORITATIVE for the i59 build)

**Concretizes hardened s8 rule 1** (`2026-08-15-i58-front-door-hardened.md`) and folds the i59 red-team
(3 in-session cloud adversaries, D-0119; raw verdicts archived). The `{kernel + cold-boot card + uniform
rebuild interface}` ARCHITECTURE HELD (all 3 adversaries could not break the kernel prose, the Mode-A/B router,
or the lossless backing). 13 confirmed gaps (5 ratification-blocking) are folded below; these supersede the
pre-red-team digest's naive clauses (the PB-7/D-0149 precedent). i59 is a doc/ops migration — no module code.

## s1. Scope
Migrates the ROOT front door only: `START_HERE.md` → a stable boot **kernel**; adds a generator-INDEPENDENT
**cold-boot card** (`core-docs/COLD_BOOT_CARD.md`); mechanizes the kernel's bound with `ops/frontdoor/`
(registry + driver + a close-gate step); amends `DOC_PROTOCOL.md` s2. Survivor set = {kernel + cold-boot card}.
Untouched: i60+ classes, P0-1 (FROZEN; retrieved memory = EVIDENCE), DECISION_LOG/index/git/archive
(append-only, lossless). The renderer slim-ladder removal/re-tune stays flagged, not this unit (s8 rule 3).

## s2. The boot kernel (replaces START_HERE.md) — folds A1-B1/B7/B8
Content-frozen template, ~1 KB, NO changing state (no iteration/active-work/roster). ROUTES only; references
the uniform rebuild verb as fixed O(1) text. Routing (fail-closed, non-looping):
- **Mode A**: verify the PCB; if OK AND the packet's self-declared epoch is NOT behind the card's last-good
  epoch (cheap sanity, A1-B7) → open BOOT_PACKET, progressive disclosure. Done.
- **Rebuild-ONCE**: if verify fails / packet missing / epoch-behind, and you can run the generator → run
  `ops/frontdoor/Rebuild-FrontDoors.ps1` exactly once, re-open. **If it still fails → go to Mode B. Never
  rebuild twice** (A1-B1: terminate by consequence, not an unenforceable "once").
- **Mode B**: cannot run the generator (read-only mount / mobile / Project-mirror / generator down) → read
  `COLD_BOOT_CARD.md`. **If the card is absent on this surface (mirror miss) → degrade to the raw read order**
  (PROJECT_DIRECTION → CURRENT_STATE → handoff → DECISION_LOG_INDEX) so the survivor set never collapses to
  {kernel} (A1-B6). Mount/mobile/mirror take Mode B unconditionally.
Invocation: `python3 modules/44-project-map/project_map.py verify …` (proven cross-platform incl. this mount);
on-box sessions may use `Invoke-ProjectMap.ps1 -Action verify`. A close-gate asserts the kernel's named paths +
commands resolve (A1-B8). Exact frozen text = Appendix K.

## s3. The cold-boot card (`core-docs/COLD_BOOT_CARD.md`) — folds A1-B2/B3/B4/B5, A2-BREAK1/BREAK2, A3-B2
Generator-INDEPENDENT, hand-maintained, mirrored to Project. Near-frozen: the ONLY per-close-changing fields
are MECHANICAL STAMPS (as_of, last-good SHA, the machine-verified doc count) — no per-wave synthesis. Slots:
1. **as_of** = `i<N> / <close-id>` (NOT a not-yet-existing SHA — A3-B2). Evergreen-vs-stamped is labeled.
2. **Identity** — one frozen line. *(evergreen)*
3. **Source-of-truth rule** — disk canonical; Project mirrors core-docs/; disk wins. *(evergreen)*
4. **PINNED CONSTRAINTS** (NEW — A1-B2, s8 rule 3 pin-the-unrecoverable): a COUNT-ASSERTED never-spill set
   carried INLINE so Mode B never drops it — P0-1 activation prohibited / `non_execution` holds; NEVER
   `git add -A`; lease order gpu→git→doc (GPU-lease-before-generators); orchestrator never drives external/
   frontier AI (D-0051/D-0119); ≤1 GPU worker/wave. "`P` pinned as of <close-id>", validated at close against
   the packet PROHIBITIONS+STANDING set. *(count as_of-stamped; membership evergreen unless a D-entry adds one)*
5. **Canonical doc list** — COUNT-ASSERTED "`N` core-docs as of <close-id>", each `FILENAME — ≤6-word owns`.
   **Hard invariant N ≤ K_max=30**; crossing K_max is a batched rule-8 re-layer (a new front-door class), NOT
   silent card compression (A2-BREAK1). Machine-verified at close (A3-B3). *(as_of-stamped, A1-B4)*
6. **Active work + frontier** — **FROZEN REDIRECT** to `CURRENT_STATE §Phase+active work` + the packet OVERLAY.
   NOT summarized here (A2-BREAK2: no per-close free-form synthesis). *(evergreen redirect)*
7. **Last-good close SHA** — the PRIOR close's packet-commit SHA, a real existing commit (A3-B1/B2). *(stamped)*
8. **Generator-free read order** — PROJECT_DIRECTION → CURRENT_STATE → FANOUT_ORCHESTRATOR_HANDOFF →
   DECISION_LOG_INDEX (read index, pull entries by ID — not whole-ingest). *(evergreen)*
Budget: 4 KB (new s2 row). Mirrored to Project top-level.

## s4. Uniform rebuild interface (`ops/frontdoor/`) — folds A2-BREAK3/BREAK4, A3-B5
- **registry.json** — `[{class_id, rebuild{cmd,args}, verify{cmd,args}, boot_read, migrated_in}]`. i59 registers
  ONE class `root-pcb` (rebuild = Invoke-ProjectMap render; verify = verify; boot_read:true).
- **Rebuild-FrontDoors.ps1** — reads the registry, runs rebuild→verify per class, prints one JSON envelope, and
  ASSERTS (non-vacuity floor, A2-BREAK3): ≥1 boot_read class; named-required `root-pcb` present + boot_read:true
  + non-empty artifact set; every boot_read class 0-stale. `-VerifyOnly` serves the kernel's Mode-A verify.
- **Migration GATE** (rule 1) — a class migrates only after it registers a **conformant** entry, where conformant
  (A2-BREAK4) = a mutation test passes: corrupt a backing byte → the class's `verify` MUST report stale/fail AND
  its render double-run MUST differ (root-pcb meets this via #44's drift-check + verify freshness). A class the
  uniform verb cannot rebuild, or that fails the mutation test, MAY NOT migrate.
- **Registry completeness oracle** (A3-B5) — the close-gate asserts {map surfaces tagged front_door=true} ==
  {registry rows}; a front door with no row is a migration-gate violation. i59: exactly one, `root-pcb`.

## s5. The i59 close model — folds A3-B1/B4 (replaces the false "atomic across two commits")
The close is NOT atomic across two commits (it CANNOT be: the #44 producer harvests the committed HEAD, so docs
commit first, then map/generated is the FINAL commit — DOC_PROTOCOL s9.7 / N7). Instead, safe-by-DETECTION:
- **Phase 1** (generator-independent — A1-B5): commit the doc set {kernel, card, registry, driver, DOC_PROTOCOL,
  D-0154} under the git lease; doc-commit-gate PASS + the NEW frontdoor gate step PASS. This lands even if
  Phase 2 later aborts, so the card stays maintainable during a generator-down spell.
- **Phase 2**: N7 close-refold renders + commits map/+generated/ (the packet) = the epoch anchor.
- **Completeness**: the close is COMPLETE only if Phase 2 lands green (driver green + 0-stale on boot_read). If
  Phase 2 fails, the close is INCOMPLETE: the card's close-id is AHEAD of the packet's epoch, and **Mode A
  detects packet-epoch < card and falls to Mode B** — a half-close is DETECTED, never served as consistent.
  Recovery = re-run the idempotent refold; no history mutation.
- **Mirror manifest** (A3-B4/A1-B3): at close write `claude/MIRROR_MANIFEST.md` {close-id; mirrored docs;
  per-doc content-hash}; the card carries the close-id so a Project-only session self-checks card-vs-manifest
  WITHOUT disk; a partial/failed mirror is DETECTABLE (card self-labels "mirror inconsistent — request
  re-mirror"). Full mirror atomicity is out of reach (separate step); detectability is the honest bar.

## s6. NEW close-gate step — `ops/frontdoor/frontdoor-gate` (extends the fail-closed close) — folds A2-BREAK5, A3-B3/B5
Asserts at close HEAD, fail-closed: (a) card doc-list count == `ls core-docs/*.md` count == DOC_PROTOCOL s2
row count == PCB map doc-entity count; (b) slot-8 read-order docs ⊆ the counted set; (c) N ≤ K_max, P ≤ PIN_MAX;
(d) card PINNED set ⊆ the packet PROHIBITIONS+STANDING set; (e) registry completeness oracle (s4); (f) the
kernel's named paths/commands resolve. Any mismatch aborts the close.

## s7. i59 acceptance gates
G-kernel (≤1 KB, zero changing-state tokens, routes A + rebuild-once→B + B-degrade, O(1) rebuild ref);
G-card (generator-independent, self-sufficient for Mode B incl. the pinned set, near-frozen, count-verified);
G-rebuild (driver GREEN on the box over the i59 registry, non-vacuity floor holds — the mechanization proof);
G7 (kernel + card enumerable-or-frozen; no free-form synthesis — slot 6 is a redirect); G8 (kernel, card
close-id, packet epoch agree at close as ONE close-id; half-close falls to Mode B); frontdoor-gate PASS;
no-regression (an in-flight OLD-START_HERE session still boots: kernel targets exist at the close commit + the
mirror). Design-first→red-team-gated: DONE (this digest is the folded gate output).

## s8. Migration safety
Reversible (START_HERE prior bytes → git + `archive/doc-snapshots/2026-08-15/`); append-only logs untouched.
Load-bearing surface → staged for Nicholas review before the Phase-1 commit ("gate: frozen at staging").
Open knobs for review: K_max=30 / PIN_MAX; whether the frontdoor-gate ships as a doc-commit-gate extension now
or a standalone i59 script; whether the mirror-manifest is i59 or deferred to the first desktop-less-risk close.

## Appendix K -- frozen kernel text

The committed kernel = `core-docs/START_HERE.md` (this migration's output). It routes Mode A (verify -> open
BOOT_PACKET), rebuild-ONCE (`ops/frontdoor/Rebuild-FrontDoors.ps1`), then Mode B (`COLD_BOOT_CARD.md`, with a
raw-read-order fallback if the card is absent); it names the uniform rebuild verb as fixed O(1) text and holds
no changing state. See START_HERE.md for the exact bytes.
