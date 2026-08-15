# UNIVERSAL FRONT-DOOR CONTRACT -- HARDENED INVARIANT SET (AUTHORITATIVE; i58 freeze)

**Continues `2026-08-15-i58-front-door-redteam.md` (the confirmed breaks CB1-CB7).** These invariants are
AUTHORITATIVE and SUPERSEDE any naive clause of `2026-08-15-i58-universal-front-door-contract.md`, as the
PB-7 s8 ruleset superseded its own s4 (D-0149 precedent). Freeze verdict: the two-engine architecture + the
shared-grammar seam + the enumerable-interior re-layer are SOUND; the naive universal-boundedness claim is
CORRECTED here. Each i60+ class stays design-first -> red-team-gated; rules 3/6 are per-class build
requirements.

## s8. Authoritative hardened invariants

1. **Recovery survivor set CLOSED under generator-down (fixes CB1).** i59 retains ONE bounded,
   hand-maintained, generator-INDEPENDENT **cold-boot card** in `core-docs/` (mirrored to the Project):
   project identity + the source-of-truth rule + the canonical doc list + current active work + the last-good
   close SHA + a bounded generator-free raw read order. The survivor set is {kernel + cold-boot card}. The
   kernel ROUTES: verify+open succeed -> use the packet (Mode A); ELSE do NOT loop on rebuild -> fall back to
   the cold-boot card (Mode B); read-only mount / mobile / Project-mirror take the card path unconditionally.
   **This AMENDS D-0152's i59: the kernel alone is INSUFFICIENT.** Mechanize the kernel's bound: every
   per-class producer/gate registers under ONE uniform rebuild interface; the kernel says "run the uniform
   rebuild over all registered classes; verify boot_read 0-stale" (fixed O(1) text). Non-conformance to the
   interface is a MIGRATION GATE (a class the uniform verb cannot rebuild may not migrate) -- no hidden
   growing runbook.
2. **Honest boundedness (fixes CB3-i).** Replace "B* AND K* flat" with **B* flat; K* = O(hierarchy depth) =
   O(log_F N)**, F provisioned so depth <= 2 within a declared iteration horizon. The root asserts {total
   count + a fixed constant number of top buckets + the fanout invariant}, NOT the full semantic category
   set. Retract "one bounded descend for all of class X" -> "<= depth bounded descends." The honest law is
   **bytes flat, query-count logarithmic, completeness provable at the typed boundary.**
3. **Spill law restated + pin-the-unrecoverable + task-routable (fixes CB3-ii, CB2 window).** Replace "spill,
   never compress" with: **never shed from a hot surface to an UNCOUNTED or UN-TYPED-REACHABLE sink; shedding
   to a counted, typed-queryable cold surface is permitted -- and is still LOSSY for the hot reader, so**
   (a) any constraint whose violation is IRREVERSIBLE/safety-critical (P0-1 class, "never `git add -A`",
   GPU-lease-before-generators) is PINNED hot and may NEVER spill; the spillable set is restricted to
   constraints `enforced_by` a gate OR recoverable; (b) every spilled category carries a machine-checkable
   task-match key (action-class/module) so "must I descend?" is DETERMINISTIC, not guessed (closes the
   A6/D-0095 safe-pruning miss); a category with no reliable key FAILS CLOSED to pinned. Retract "slim-ladder
   REMOVED not re-tuned" -- the correct fix gives the ladder's overflow a count + typed pointer (a re-tune)
   and PRESERVES its section-budget machinery; the sins to remove were UN-counted + coarse-reachable, not the
   ladder itself.
4. **Compute the hot set; strike hand-authored windows (fixes CB2).** A judgment shell may contain ONLY (a)
   content that is itself a count-asserted typed registry (enumerable -> omission detectable) or (b)
   content-frozen template text (like the kernel). Free-form per-wave synthesis NOT backed by a count-asserted
   registry is PROHIBITED in any boot-read surface; a live judgment must LAND as a typed record
   (episode/reflective/decision) the shell count-asserts. Every shell carries `as_of=<HEAD/iteration>`
   validated at close (`as_of < HEAD` self-labels stale). The gotcha window is COMPUTED (`hot <=> status=live
   AND enforced_by=none AND (cross_session_scope OR recurrence>=k)`), never a per-session human pick. A
   surface earns a shell ONLY via a fixed-slot template (K slots independent of N) + a validator (shell
   mentions subset of registry union frozen-template) + a recorded D-entry -- no owner self-classification.
5. **Cross-front-door currency (fixes CB4).** A **compile epoch**: sample HEAD once per boot -> `epoch_sha`;
   every front door consulted serves as of `epoch_sha`, else the WHOLE compile carries ONE boot-level "as of
   <sha>, N commits behind" flag; G4 gains: no two front doors in one compile serve different epochs without
   that unified flag. Key currency on each backing's own content-version (+ a backing->front-door dependency
   map) so only affected front doors re-check; define non-append currency by content-hash. Resolve **C1 vs
   G4** explicitly: either a genuinely incremental producer (cost bounded by |delta|) OR ordinary boots
   self-label stale and re-ingest happens ONLY at close. **Two-phase atomic close:** all N producers stage; a
   single close-gate asserts every front door `ingested_through == close_HEAD` + an INDEPENDENT validate;
   only then the final `map/`+`generated/` commit lands; any failure aborts the whole close. Extend 0-stale
   from boot_read to ALL front doors; emit a gated close-manifest. Render every count currency-qualified
   inline ("94 live as of <sha>; re-derive via `deeper:*:prohibition`"), never a bare "complete."
6. **Classifier oracle / honest G2 (fixes CB5).** Reconcile `asserted_count` against an INDEPENDENT
   completeness oracle at the canonical layer (a write-time `authority:standing` tag on the DECISION_LOG
   entry, cross-checked against the keyword classifier; disagreement fails the doc-commit-gate). Absent the
   oracle, DOWNGRADE G2 to "no CLASSIFIED-standing constraint silently absent" and book the classifier seam
   as an accepted residual.
7. **Synopsis = frozen replayed INPUT (fixes CB6).** A validated synopsis, once accepted, is pinned as a
   content-hashed versioned claim; drop+rebuild REPLAYS the pinned bytes and never re-invokes the model;
   regeneration is an explicit gated re-validation event (new version id) OUTSIDE the byte-identity rebuild
   path.
8. **Batched, provisioned re-layer (fixes CB7).** Provision root fanout with headroom for a declared horizon;
   when ANY root first approaches budget, re-layer ALL cumulative-class roots to the next depth in ONE
   red-teamed wave sized to last >= M iterations. FORBID single-class reflexive re-layers of the boot surface.

## Acceptance-gate additions

- **G7 -- synthesis-completeness.** Every boot-read shell passes rule-4's mentions-subset-of-(registry union
  frozen-template) validator at close; no free-form synthesis un-backed by a count-asserted registry.
- **G8 -- cross-front-door consistency.** Compile-epoch consistency (rule 5) + the two-phase atomic close
  across ALL front doors; 0-stale asserted over every front door, not only boot_read.

G7/G8 join the contract s9 gate (G1 corrected per rule 2; G2 per rule 6; G4/G5 per rules 5/3).

## i59 + i60+ consequences (the freeze that governs the migration)

- **i59 (root) is AMENDED (rule 1):** START_HERE -> the kernel AND the generator-independent cold-boot card;
  register the uniform rebuild interface. The kernel is NOT the sole survivor.
- **i60+ (per class):** the pin-the-unrecoverable + task-match-key (rule 3), the enumerable-or-frozen shell +
  computed hot set (rule 4), the compile-epoch + two-phase close (rule 5), the classifier oracle (rule 6),
  and the frozen-replayed synopsis (rule 7) are BUILD REQUIREMENTS, each design-first -> red-team-gated.
- **Sequencing:** re-layers are batched (rule 8), NON-DISPLACING; P0-1 stays FROZEN (retrieved memory is
  EVIDENCE); git + `archive/` + append-only logs stay complete + untouched.
