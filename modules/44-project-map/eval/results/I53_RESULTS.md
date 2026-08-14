# I53 MIGRATION-GATE RESULTS -- fresh two-class legacy-vs-PCB gate under the D-0140/N4 bars + D-0144/N8 protocol

**VERDICT: GO (PASS).** Quality PASSES on BOTH tasks and efficiency PASSES on both tasks; no floor tripped;
swap-stable. Under the frozen verdict mapping (quality PASS both + BOOT PASS + per-task TOTAL PASS both +
not-voided) the migration is **LICENSED: the PCB `BOOT_PACKET` becomes the default orchestrator bootstrap; the
legacy handoff is preserved as fallback/history until a later retirement gate.** This reverses the i51 NO-GO:
the map-native task (T-map) exposed the legacy arm's reliance on prose/doctrine, and the N6 canon (overlay
prohibitions + open_rulings folded into the boot packet) gave the PCB arm the exact constraint coverage the
legacy arm missed -- the i51 constraint-adherence floor is now cleared with the PCB arm ABOVE the legacy arm.
Both arms + adjudicators pinned `claude-opus-4-8` (comparison valid). Nicholas dispatched every session, ran the
coin flip; the intervention rule was available and unused. Packs + verdicts committed byte-verbatim; the
orchestrator summarized but never altered them.

## 1. Run record

- **EVAL_SHA (tree) = `1ee201d`** (HEAD, the i52 FINAL N7 close-refold). Bundle harvested + rendered at the
  map's own at_commit **`80b260e`** (HEAD's content-identical parent -- the fold only touched map/+generated/;
  N7 in-sync, no side worktree). Precondition: independent harvest+validate at HEAD = **0 findings / 0 stale**.
- **Eval folder** `C:\Users\just_\LifeOrch-i53-eval\`: `tree\` @ HEAD; `_bundle\` = the in-sync 0.4.0 PCB
  (BOOT_PACKET byte-identical to the shipped file, 17,265 B); `MANIFEST-i53.sha256` 33 rows self-verified. The
  frozen tree/bundle/dispatch re-verified UNTAMPERED after both rounds; `tree\` clean x N.
- **Task pool (frozen):** T-map (memory-subsystem build-state census, #35-42+44) + T-prose (audit next
  increment + governing constraints + dry-run wave plan). Both arms ran both, T-map first. Keys re-derived at
  HEAD (K6 sunset; K10 = D-0134 rider; M1-M6 from the map cards; A1-A6 the i51 key updated for D-0134).
- **A/B model pins:** both `claude-opus-4-8` -> HOLD. **C1/C2 pins:** both `claude-opus-4-8` (Opus 4.8 Extra) ->
  HOLD (the i51 opus-5 drift did NOT recur; N8 rule 5 satisfied, no pre-C STOP).
- **Blinding:** coin flip (Nicholas, private) = **SWAP** -> Candidate-1 = Arm B (PCB), Candidate-2 = Arm A
  (legacy). Neutralization (I47 s5 table + i51/i53 additions); residual-tell scan EMPTY on both candidates;
  raw packs + dispatches + the bundle quarantined OUTSIDE the eval folder before the C round (tighter than i51,
  which left the bundle). Candidates re-hashed after the C round: byte-identical (no tamper). C1 scored
  Candidate-1 first, C2 scored Candidate-2 first.
- **Partial-blinding limitation (recorded, i47 s5 honesty note):** the PCB arm's boot self-check block is a
  retrieval-style signal that survives name-scrubbing. C's role is evidence-cited scoring and the verdict rule
  is deterministic; the score gap is substantiated by fact-key HITs (Candidate-1 hit all M1-M6/A1-A6; Candidate-2
  missed M6/A5 and absolute K7/K10), not by identification.

## 2. Score matrix (0-4; C1/C2 means; Candidate-1 = B/PCB, Candidate-2 = A/legacy)

**Candidate-1 (B/PCB): every dimension 4.0 on BOTH tasks from BOTH adjudicators (C1 and C2 identical).**

| dimension | B T-map | B T-prose | A T-map | A T-prose | (C1,C2 for A T-map) | (C1,C2 for A T-prose) |
|---|---|---|---|---|---|---|
| comprehension fidelity | 4.0 | 4.0 | **2.0** | 4.0 | (2,2) | (4,4) |
| retrieval sufficiency | 4.0 | 4.0 | 2.0 | **2.0** | (2,2) | (2,2) |
| retrieval discipline | 4.0 | 4.0 | 4.0 | 4.0 | (4,4) | (4,4) |
| architectural reasoning | 4.0 | 4.0 | 2.5 | 3.5 | (3,2) | (4,3) |
| work-plan quality | 4.0 | 4.0 | 3.0 | 3.0 | (3,3) | (3,3) |
| constraint adherence | 4.0 | 4.0 | 4.0 | **2.0** | (4,4) | (2,2) |
| epistemic honesty | 4.0 | 4.0 | 3.5 | 4.0 | (4,3) | (4,4) |

**Swap stability:** max C1-vs-C2 per-dimension disagreement = **1** (on A's arch/honesty; Candidate-1 = 0
disagreement, both adjudicators straight 4.0). Threshold >=2 -> **STABLE**; no escalation, no INCONCLUSIVE.
**Checklist (B, absolute set K1,K2,K3,K4,K6,K7):** 6/6 HIT from both adjudicators (0 MISS, 0 CONTRADICTED).
**Fact keys:** B = M1-M6 HIT + A1-A6 HIT (A6 partial on history substeps, key content HIT). A = M6 MISS, A5 MISS,
absolute K7 MISS + K10 MISS; M4 top-line HIT but edge membership diverges (prose-induced). **Fabrications in B:
none confirmed by either adjudicator.**

## 3. Rule application (frozen I47 s7 quality floors + D-0140/N4 + D-0144/N8 efficiency; verbatim -> finding)

| rule | finding |
|---|---|
| Floor (a): B missing/contradicting ANY absolute item (K1,K2,K3,K4,K6,K7) | **NOT TRIPPED** -- B (Candidate-1) HIT all six absolute keys from both adjudicators. |
| Floor (b): B < A by >=1 (C1/C2 mean) on comprehension OR constraint | **NOT TRIPPED** -- B >= A on every task/dimension; B leads by +2.0 on T-map comprehension and +2.0 on T-prose constraint adherence (the exact axes). *(This is the floor i51 breached; now reversed.)* |
| Floor (c): fabricated relationship/citation in B confirmed | **NOT TRIPPED** -- both false-confidence hunts found none in Candidate-1. |
| Floor (d): B step-0 skipped | **NOT TRIPPED** -- B ran validate + render-check, recorded both envelopes (0 stale, in-sync). |
| PASS: B comp >=3.0 AND constraint >=3.0 (both tasks) | MET (4.0 / 4.0 on both). |
| PASS: no dimension with a >=2 gap in A's favor | MET (A never exceeds B on any dimension). |
| PASS: work-plan >=3.0 (B); swap-stable | MET (4.0 both tasks; max disagreement 1). |
| N4 BOOT (absolute) | **PASS** -- BOOT_PACKET 17,265 B <= 20,000; CD-1 OPERATIONS canon present, pointer-backed. |
| N4/N8 TOTAL per task (B <= 0.7 x A, charged retrieval bytes, boot amortized 50/50) | **PASS both** -- T-map B 61,530 vs bar 83,985 (0.51x A); T-prose B 37,277 vs bar 42,716 (0.61x A). Robust across boot-allocation choices; the zero-boot T-prose retrieval cross-check TIES (finding F-i53-eff). |
| N4 VOID (PCB-insufficiency) | **NOT TRIPPED** -- B's AUDIT_PIPELINE/AAC opens are task-material or PCB-cited-first corroboration. |
| Verdict mapping | Quality PASS both + BOOT PASS + per-task TOTAL PASS both + not-voided -> **GO**. Migration LICENSED. |

## 4. Findings (F-i53)

- **F-i53-1 (dominant, positive) -- the map-native task is the PCB's decisive win.** On T-map the legacy arm
  substituted a 7-way "Collective Agent planes" doctrine taxonomy for the map's 5 plane tags, landing the
  multi-plane set (M6) and contract-ownership membership (M4 edges) WRONG, and headlined #44 rather than #43 on
  (a). The PCB arm read the map's `plane:`/`governs<-`/`audits<-` fields directly and hit every census fact.
  Structured map state beat prose reconstruction on the exact class the map is built for.
- **F-i53-2 (positive) -- N6 closed the i51 constraint gap.** On T-prose the legacy arm MISSED the D-0080
  FROZEN set (K7) and the D-0134 w08 window-close rider (K10/A5) -- both now carried in the boot packet's
  OVERLAY (prohibitions + open_rulings, the N6 render). The PCB arm recited them natively. i51's floor-(b)
  constraint deficit is not merely closed but reversed (B +2.0 on T-prose constraint).
- **F-i53-eff (load-bearing, for the next increment) -- the PCB did NOT exploit N5 `section:` on T-prose.** The
  PCB arm opened AUDIT_PIPELINE.md WHOLE (20,384 B) rather than using the N5 doc-section fetches (cadence header
  ~2.6 KB); its T-prose retrieval equals the legacy arm's, and its per-task TOTAL pass leans on the cheaper PCB
  boot. N5 delivered the capability; this run did not use it. The GO is not contingent on it (the bars pass
  regardless), but retrieval economics on prose-governing tasks remain a real headroom item -- steer future
  boot packets / dispatch guidance to prefer `section:` fetches over whole-doc opens.
- **F-i53-3 (positive) -- comprehension parity holds a fourth run:** both arms independently derived the same
  T-prose next unit (the raw-prompt FRONT step, ride-along + output as follow-ons). The PCB deficit in prior
  runs was economics + canon coverage, never comprehension; both are now resolved.

## 5. Integrity

Byte-verbatim in `eval/results/` (raw sha256): `A_PACK-i53.md`, `B_PACK-i53.md`, `C1_VERDICT-i53.md`,
`C2_VERDICT-i53.md`, the four dispatch files, `materials-i53/` (the redacted ADJUDICATION_SPEC + both
neutralized candidates), `STAGING_RECORD-i53.md`, `EFFICIENCY-i53.md`, and this results file.
`MANIFEST-i53.sha256` lists every file. The i47/i48/i51 records are unchanged: i51's floors were breached on
i51's packs; i53's PASS stands on i53's packs under i53's C round with re-derived keys at HEAD.

## 6. Disposition -- the migration (GO)

The GO licenses promoting the PCB `BOOT_PACKET` to the DEFAULT orchestrator bootstrap. The close executes:
`START_HERE.md` routes new orchestrators to the BOOT_PACKET first (verify/query-stale, then progressive
disclosure), with the legacy handoff demoted to a fallback/history pointer; the handoff's role narrows to what
the PCB does not yet carry; a D-entry records the GO + quotes the verdict shas + this rule table; CURRENT_STATE
+ MODULE_ROADMAP updated; DOC_PROTOCOL promotion rows; N7 close-refold at HEAD (0 stale); doc-health monitor
regenerated. F-i53-eff (prefer `section:` fetches) is the named efficiency follow-on, NOT a gate condition.
