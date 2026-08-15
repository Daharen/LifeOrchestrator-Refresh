# i59 red-team raw verdicts (3 adversaries, D-0119) — 2026-08-15

## A1 recovery-survivability — verdict SHIP-WITH-FIXES
- B1 [BLOCKING] "rebuild once, still broken" has no edge to Mode B; "once" unenforceable → dead-end or loop. Fix: after ONE rebuild, if re-open still fails → Mode B; never rebuild twice.
- B2 [BLOCKING] card omits pinned safety-critical standing constraints (P0-1 non_execution, never `git add -A`, GPU-lease-before-generators). Mode B silently drops the rule-3 never-spill set. Fix: add a count-asserted PINNED CONSTRAINTS slot.
- B3 [MAJOR] staleness self-label inoperative on mobile/mirror (can't compute HEAD). Fix: stamp the Project mirror with a tool-free "mirrored at <sha>/<iter>" marker.
- B4 [MAJOR] "doc-list slot doesn't go stale" is FALSE (i60+ adds/removes core-docs). Fix: as_of-qualify doc list + count; only identity + SoT-rule evergreen.
- B5 [MAJOR] card freshness coupled to generator health via "atomic close" (whole close aborts on generator fail → card never refreshed during generator-down). Fix: card update + a purely-textual validator on a generator-independent commit path.
- B6 [MAJOR] card-onto-mirror SPOF; missed push collapses survivor set to {kernel}=insufficient. Fix: kernel step 4 degrades to raw read order when card absent; close gate asserts card present-in-mirror.
- B7 [MINOR] verify-passes-but-packet-bad has no route to Mode B. Fix: Mode A cheap self-consistency check (packet epoch == HEAD / == card).
- B8 [MINOR] kernel hardcodes non-portable `python3 …`. Fix: use known-good invocation + close-gate that kernel's named paths/cmds resolve.

## A2 boundedness/anti-churn — verdict DO-NOT-SHIP (fix BREAK 1+2, re-gate)
- BREAK1 [BLOCKING] slot-4 doc list is an N-growing registry in a fixed un-spillable byte budget → guaranteed future compression (CB3/CB7 into the recovery root). Fix: hard invariant N_core-docs ≤ K_max enforced at close; crossing = batched rule-8 re-layer, not a card edit.
- BREAK2 [BLOCKING] slot-5 "current active work — replaced each close" = free-form per-wave synthesis in a boot-read surface (violates rule 4 + the design's own G7). Fix: frozen redirect to CURRENT_STATE, OR a count-asserted typed record — never a per-close hand summary.
- BREAK3 [MAJOR] "asserts boot_read 0-stale" passes VACUOUSLY (empty set / empty artifacts / self-report). Fix: ≥1 boot_read class, named-required root-pcb present+non-empty, mutation-oracle 0-stale.
- BREAK4 [MAJOR] migration gate accepts shape-conformance only; no-op rebuild + rubber-stamp verify "migrates." Fix: define "conformant" via a mutation test (corrupt backing → double-run differs AND verify fails) + byte-identity double-run.
- BREAK5 [MAJOR] count oracle `ls core-docs/*.md` is a glob convention, not proven == boot-read set. Fix: enumerate boot_read docs by path+hash; gate asserts card==registry==disk==s2; slot-7 read-order ⊆ counted set.

## A3 currency/composition — verdict SHIP-WITH-FIXES (do not ratify until close model reconciled)
- B1 [BLOCKING] "two-phase atomic close" is NOT atomic and CONTRADICTS harvest-at-HEAD N7 ordering (docs commit FIRST, then map/generated). Half-close (docs land, render throws) → card asserts SHA_new while packet is prior → divergence, no clean rollback. Fix: packet is sole epoch anchor + producer harvests staged tree; OR keep ordering but Mode A REFUSES a packet whose epoch < card (fall to Mode B) so a half-close is DETECTED not served.
- B2 [MAJOR] chicken-and-egg SHA: card can't name its own not-yet-existing packet commit; G8 "same SHA" false by construction. Fix: as_of = iter/close-id; last-good SHA = PRIOR close's packet commit; G8 "same epoch" = same close-id; card trails packet by one commit.
- B3 [MAJOR] card doc-count = a 3rd machine-unchecked source of truth → silent omission (F1). Fix: extend gate to assert card-count == wc core-docs == map doc-count == s2 rows; machine-stamp the count.
- B4 [MAJOR] Project mirror lag/partial → card as_of diverges from mirrored raw docs; "disk wins" unactionable for a desktop-less session; nothing detects it. Fix: mirror manifest {doc,hash,close-id} in one pass; card carries close-id + slot-4 hash for a disk-free self-check; partial mirror = gate fail.
- B5 [MAJOR] registry.json has no completeness oracle → a migrated class absent from registry silently skipped, passes 0-stale (CB4-iii). Fix: assert map front_door set == registry rows; a front door with no row = migration-gate violation.

## Could-NOT-break (all three): kernel prose is content-frozen + O(1); Mode A/B router structure sound; per-class registration ≠ rule-8 re-layer (distinct); lossless backing + append-only logs untouched. Architecture HOLDS.
