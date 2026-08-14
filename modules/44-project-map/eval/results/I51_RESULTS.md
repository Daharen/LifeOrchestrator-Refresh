# I51 MIGRATION-GATE RESULTS -- fresh legacy-vs-PCB gate under the D-0140/N4 bars (D-0142)

**VERDICT: NO-GO (FAIL).** Quality floor (b) BREACHED -- B under A by exactly 1.0 (C1/C2 mean) on
constraint adherence -- and floor (a) tripped under the stricter adjudicator reading of adapted-K6; the
verdict therefore cannot be PASS under the frozen I47 s7 quality rules (unchanged by N4). Efficiency,
computed under the re-frozen D-0140/N4 bars: **BOOT PASS** (packet 16,943 B <= 20,000, CD-1 canon present),
**TOTAL MISS under every accounting** (B = 2.74 x A primary / 1.12 x A charitable vs the 0.7 x A bar),
VOID not tripped. **THE LEGACY HANDOFF REMAINS THE DEFAULT ORCHESTRATOR BOOTSTRAP. No migration.**
Comprehension parity on the task itself repeated for the third consecutive run: both arms derived the
identical correct increment. Applied by the i51 orchestrator (Fable 5 seat); all packs + verdicts committed
byte-verbatim alongside; the orchestrator summarized but never altered them (RT2-F13). Nicholas dispatched
every session and ran the coin-flip; the s5 intervention rule was available and never needed.

## 1. Run record

- **EVAL_SHA_3 = `ef70a57`** (HEAD at staging; Nicholas's pick over the i49-close option). Eval folder
  `C:\Users\just_\LifeOrch-i51-eval\`: `tree\` = detached worktree @ ef70a57; `_bundle\` = the in-sync
  0.3.0 PCB -- **harvested from a throwaway worktree @ `5d46731`** (the map's own overlay `at_commit`),
  because `op_harvest` reads the working-tree filesystem and `--at-commit` is a label only; harvesting at
  HEAD flags 42/175 stale (STALE_BUDGET) since the five i49-close..i50 doc-only commits were never
  re-folded into #44. Staging validate 0 findings; render byte-identical to the committed generated views;
  `MANIFEST-i51.sha256` 31 rows, self-verified; frozen packet + `N4_BAR_REFREEZE.md` hashed as REF rows.
- **Blind limitation (recorded up front):** at ef70a57 the handoff s4, CURRENT_STATE "next action", and
  the staged git-log all name "stage + run the fresh gate," so an arm could infer it was inside the
  migration eval. The packet s5 partial-blinding note + the deterministic verdict rules absorb this;
  efficiency was orchestrator-computed and never disclosed to any arm.
- **Task = T1** (audit next increment; Nicholas). T2 remains dead (mandate sunset). The frozen T1 key
  spot-checked at HEAD before staging: A1-A4 stable; **K10/A5 partially STALE at this tree** (the full
  D-0134 entry closed the D-0129 live-click confirm and recorded the explain-window-close defect as the
  surviving rider, while CURRENT_STATE still carried "PENDING") -- see s6 anomaly 2.
- **K6 ADAPTED (recorded):** the frozen K6 ("mandate-02 report due") presumes the i47 tree; the
  adjudication spec re-scoped it to "correctly reflects the mandate-02 SUNSET / no-live-mandate state;
  CONTRADICTED = asserts a live mandate." Both adjudicators note neither pack asserts a live mandate.
- **A/B runs:** both `claude-opus-4-8` (model pin HOLDS -- the efficiency comparison is valid).
  `A_PACK.md` 24,986 B; `B_PACK.md` 24,957 B (both <= 25,000). Frozen `tree\` untouched at every pull
  (`git status --porcelain` = 0 x3). B ran step-0 (validate ok / 0 errors / 24 stale; `render --check` ok
  / no drift / packet 16,640 B at the eval sha) and recorded both envelopes. Both ledgers show
  eval-folder paths only.
- **Blinding:** Nicholas's private coin flip = **SWAP** -> **Candidate-1 = B, Candidate-2 = A**.
  Neutralization by the s5 mechanical table + i51 additions (pack filenames, `--q`, `query surface`,
  agent labels); residual-tell scan EMPTY on both candidates (BOOT_PACKET / project_map / _bundle /
  START_HERE / Agent A|B / PCB / harvest-eval / map-eval / A_PACK / B_PACK / --q all 0). Raw packs +
  dispatches quarantined OUTSIDE the eval folder before the C round; `_out\`/`_dispatch\` empty at C
  dispatch. Candidates re-hashed after the C round: byte-identical to the staged copies (no tamper).
- **Adjudicators:** C1 + C2 both report `claude-opus-5` -- a RECORDED deviation from the i47 C-tier
  (`claude-opus-4-8`); symmetric across both C sessions and both scoring orders, so the swap check is
  unaffected; scores-only output verified on both (no verdict/winner language). C1 scored Candidate-1
  first; C2 scored Candidate-2 first.

## 2. Score matrix (0-4; C1/C2 means; Candidate-1 = B, Candidate-2 = A)

| dimension | B (C1) | B (C2) | B mean | A (C1) | A (C2) | A mean | gap A-B |
|---|---|---|---|---|---|---|---|
| comprehension fidelity | 3 | 3 | 3.0 | 3 | 4 | 3.5 | 0.5 |
| retrieval sufficiency | 3 | 2 | 2.5 | 3 | 3 | 3.0 | 0.5 |
| retrieval discipline | 3 | 3 | 3.0 | 4 | 4 | 4.0 | 1.0 |
| architectural reasoning | 4 | 4 | **4.0** | 3 | 4 | 3.5 | -0.5 |
| work-plan quality | 4 | 3 | **3.5** | 3 | 3 | 3.0 | -0.5 |
| constraint adherence | 3 | 3 | **3.0** | 4 | 4 | **4.0** | **1.0** |
| epistemic honesty | 3 | 4 | 3.5 | 4 | 4 | 4.0 | 0.5 |

**Swap stability:** max C1-vs-C2 disagreement on any dimension = 1 (threshold >=2) -> STABLE; no
escalation, no INCONCLUSIVE. **Checklist (B, absolute set):** C1 = 6/6 HIT (K6 "HIT (partial)"); C2 = 5/6
(K6 "MISS (not contradicted)"); 0 CONTRADICTED from either. B non-absolute misses: K5 (both), K10 (both),
K8/K9/K11 partial (C2). A absolute set: K6 MISS + K7 MISS-partial (C2) / 6 HIT (C1); A's misses do not
feed floor (a), which tests B only. **Fact keys:** B = A1-A4 HIT, A5/A6 MISS. A = A1-A3+A5 HIT, A4 MISS,
A6 MISS-partial. **Fabrications: none confirmed by either adjudicator** (mis-attributions recorded in the
hunts; C2: "No fabricated relationship that I could verify within scope").

## 3. Rule application (frozen I47 s7 quality + D-0140/N4 efficiency; verbatim -> finding)

| rule | finding |
|---|---|
| Floor (a) B missing/contradicting ANY absolute item | **TRIPPED under C2's reading** -- adapted-K6 marked "MISS (not contradicted)" (C1: "HIT (partial)"); resolved to the stricter mark, which is also the more faithful reading of the adapted-K6 text. Consequence per (a): cap at CONDITIONAL. 0 CONTRADICTED. |
| Floor (b) B < A by >=1 (C1/C2 mean) on comprehension OR constraint | **TRIPPED** -- constraint adherence: B 3.0 vs A 4.0, gap exactly 1.0 (comprehension gap 0.5). Both adjudicators independently scored B 3 / A 4. NOT driven by the K6 adaptation: the cited deductions are pack content (see s4). |
| Floor (c) fabricated citation in B confirmed | NOT TRIPPED -- none confirmed (both hunts). |
| Floor (d) B step-0 skipped | NOT TRIPPED -- both envelopes run + recorded. |
| PASS: B comp >=3.0 AND constraint >=3.0 | met (3.0 / 3.0) -- moot under the floors |
| PASS: no dimension >=2 gap in A's favor | met (max 1.0) -- moot |
| PASS: work-plan >=3.0; swap-stable | met (3.5; stable) -- moot |
| N4 BOOT (absolute) | **PASS** -- packet 16,943 B <= 20,000; CD-1 OPERATIONS canon present, pointer-backed. Boot-total (reported, not gated): B 21,443 B vs A boot(narrow) 31,610 B. |
| N4 TOTAL: B <= 0.7 x A | **MISS** -- primary (literal N4): B 547,901 vs A 200,205 -> **B = 2.74 x A** (bar 140,144). Charitable sensitivity (nav-listings excluded both, tool source at slice bytes, staged-not-read excluded): B 220,602 vs A 197,065 -> **B = 1.12 x A** (bar 137,946). Missed under BOTH. |
| N4 VOID (PCB-insufficiency) | NOT TRIPPED -- B's legacy-surface opens (CURRENT_STATE, handoff) were either PCB-cited-first in its ledger (OPERATIONS canon, overlay phase/prohibitions/frontier -> corroboration, bytes count) or routed by the packet's own boot_read/stale protocol at a stale checkpoint; task-material docs (AUDIT_PIPELINE, design digests) are not legacy/handoff docs under the clause. |
| Verdict mapping | Floors (a)+(b) breached -> quality NOT a PASS -> **FAIL/NO-GO** (floor (a) alone would cap at CONDITIONAL; floor (b) has no cap language). Legacy stays default; the PCB is preserved as the live #44 module + this failure evidence recorded per directive s12. |

## 4. Efficiency computation (N4 accounting; exact EVAL_SHA sizes from the committed tree)

- **A (legacy):** boot(narrow) = dispatch 2,513 + START_HERE 5,333 + handoff 23,764 = 31,610. Raw opens =
  README 1,202 + B-dispatch 3,000 + CURRENT_STATE 33,928 + PROJECT_DIRECTION 10,632 + SEALED_CHECK 2,540 +
  AUDIT_PIPELINE 20,156 + CPC 34,750 (130-line read; whole-file per rule) + INDEX 20,765 (grep) + ROADMAP
  31,425 (grep+reads) + facts 7,057 = 165,455. Listing outputs ~3,140 (recursive attempt errored; per-dir
  successes). **Total 200,205 B**; ~15 opens + ~10 listings/greps.
- **B (PCB):** boot = dispatch 3,000 + BOOT_PACKET 16,943 + step-0 envelopes ~1,500 (recorded; est.) =
  21,443. #44 query outputs (edges/redges/alias rows) ~3,000 est. Raw opens (whole-file per N4) =
  L1_CARDS_modules 31,488 + AUDIT_PIPELINE 20,156 + CURRENT_STATE 33,928 + handoff 23,764 + scoping
  13,755 + i45-lrap-design 9,811 + w08 WORK_ORDER 10,209 + round5 digest 7,113 + ROADMAP 31,425 +
  SEALED_CHECK 2,540 + A-dispatch 2,513 + project_map.py 103,588 (slice read; whole-file per rule) +
  facts 7,057 = 297,347. Staged-not-read transfers (disclosed row 22) = START_HERE 5,333 + ALIASES 5,888 +
  L0 7,554 + L1_infra 41,869 + L1_widgets 5,365 + PROCESS_BACKLOG 6,982 + i43-design 7,447 = 80,438.
  Recursive listing output 145,673. **Total 547,901 B**; ~14 opens + ~9 queries + 1 recursive listing.
- Estimate sensitivity: the two estimated terms (step-0 + query envelopes, ~4.5 KB combined) are two
  orders of magnitude below the margins; no plausible estimate error flips either accounting.

## 5. Findings (F-i51; mechanism-precise -- what actually failed, distinct from i48's F1-F4)

- **F1 -- task-class dependence (dominant).** T1's answer lives in PROSE governing docs (AUDIT_PIPELINE
  cadence header/s5/s6 + the LRAP design digests + WORK_ORDER follow-ons). i49's N1 made module
  purposes/SCHEMA_NOTES query-granular -- none of THIS content is served at query granularity, so B opened
  the same prose corpus A opened (~155 KB shared) AND paid the PCB boot layer + L1 card (~48 KB) on top.
  The PCB wins on map-native tasks (the T3 class; i48 projection ~0.35 x A) and loses on
  prose-governing-doc tasks. The gate, run on a fresh task class, correctly exposed this.
- **F2 -- currency lag pushes corroboration bytes.** The map was in-sync at 5d46731 but 5 doc-only commits
  behind HEAD; the packet's own stale flags + boot_read routed B to open CURRENT_STATE + handoff whole
  (~58 KB) to re-derive currency. Doc-only iteration closes do not re-fold #44 -- the exact mechanism
  C1's hunt item on the boot-arm reconciliation names.
- **F3 -- the B-arm constraint gap is canon-coverage, mostly.** Every scored B constraint deduction is an
  item the BOOT_PACKET does not carry: the D-0064 human live-GUI-confirm rule (B asserted "ship not
  blocked on it" -- a relaxation; NOTE B also read CURRENT_STATE, so this is partly model behavior), the
  K5 doc budgets + fail-closed commit gate, the mandate-02 sunset line (adapted-K6), the poser/w08 rider
  state (K10 -- present in the overlay open_rulings yet dropped), and the red-team gate marked OPTIONAL
  against the header's "design-first -> red-team-gated". A, booted on the prose corpus, recited these
  natively. Packet-side canon extension converts each into a test-asserted assertion a future B cannot miss.
- **F4 -- navigation + bulk-transfer discipline.** B's single recursive listing (145,673 B) and 7
  staged-not-read transfers (80,438 B) are ~41% of its primary total; A navigated per-dir after its
  recursive attempt errored. No pre-frozen accounting convention covers listings or fetched-unread files
  -- both were resolved by bracketing this run; the next gate must pre-freeze them (and a dispatch line
  naming the listing convention removes the luck asymmetry).
- **F5 (positive).** Comprehension parity for the third run; B's step-0 fail-closed gate + stale-signal
  protocol worked as designed (it detected its own staleness and corrected to HEAD truth); B WON
  architectural reasoning (4.0 vs 3.5) and work-plan quality (3.5 vs 3.0) -- the PCB arm produced the more
  dispatchable plan. The deficit is canon coverage + retrieval economics, not reasoning. Both packs are
  design input for the audit front-step design wave AND the #40 beam-width wave.
- **Tree-inconsistency findings (adjudicator service, fixed at this close):** CURRENT_STATE carried the
  pre-D-0134 "live-click PENDING" line (D-0134 closed it; the window-close defect is the surviving rider)
  and "48 iterations run" vs the handoff's count. Both corrected in the i51 close commit.

## 6. Anomaly + decision log

1. Staging: first harvest attempt at HEAD -> STALE_BUDGET refusal (42/175) -> in-sync worktree harvest @
   5d46731 (s1); recorded as the F2 mechanism, not worked around silently.
2. K10/A5 key staleness at ef70a57 (D-0134 closed the live-click confirm; hot docs lagged): C2 scored K10
   per the spec text and flagged the conflict in an adjudicator note; the discriminator both C's actually
   used is the RIDER (present in A, absent in B), uncontested in every source.
3. C-tier model deviation (claude-opus-5, both C sessions) recorded; A/B pin held.
4. The i51 dispatches reused the FROZEN I47 s4 text verbatim (folder name + T1 inserted); the
   neutralization table gained i51 scrubs (pack filenames, --q, query-surface) after a first-pass
   residual-tell audit caught surviving tells; re-run clean before any C dispatch.
5. Efficiency bracketing (primary literal N4 + charitable sensitivity) pre-stated in the staging record
   BEFORE the C round returned; verdict identical under both.

## 7. Disposition -- named next units (i52 per Nicholas's directive: fix the identified issues, move to GO)

- **N5 -- prose/L2 doc-section granularity (#44):** extend `section:` to doc entities (serve a named
  heading section of any mapped core-doc/research doc, bounded, provenance-marked) + a `card:<id>` verb
  (one rendered L1 card, not the whole plane file). Kills F1's raw-open dominance. Accept: the T1
  derivation cluster (cadence header + s5 + s6; the lrap-design honesty-map section; the WORK_ORDER
  follow-ons block) each resolves as a bounded query <= 8,000 B output; a T1-style probe answers with no
  whole-doc open.
- **N6 -- OPERATIONS canon extension (#44):** add the D-0064 rule (human live-GUI confirm BEFORE done --
  full strength), K5 (budgets + fail-closed commit gate), the mandate-02 SUNSET line, the poser/w08 rider
  current state, and non-optional red-team-gate phrasing for audit increments; content assertions
  test-asserted like the i48 CD-1 set. Kills F3's packet half. Accept: a fresh PCB-booted dry-run agent
  HITs K5/K6/K9/K10 + does not soften D-0064, with no tree corroboration required.
- **N7 -- close-time currency protocol:** every iteration close (INCLUDING doc-only closes) runs the
  mechanical #44 re-fold/reaffirm + re-render so the shipped PCB is in-sync at HEAD; one ops script +
  one DOC_PROTOCOL s9 line + one handoff wave-loop line. Kills F2. Accept: post-close `validate` at HEAD
  -> 0 stale on the boot_read set; the next gate stages its bundle at HEAD with no side worktree.
- **N8 -- re-run protocol re-freeze (NICHOLAS RATIFICATION REQUIRED, the N4 pattern):** fresh
  pre-registered task pool (>=2 tasks, both classes: one map-native, one prose-governing -- the gate must
  pass on BOTH going forward, or the migration claim is scoped to map-native tasks); pre-frozen accounting
  conventions for dir-listings, staged-not-read transfers, and partial tool-source reads; a dispatch line
  pinning the listing convention for both arms; C-tier model pin refreshed; absolute-checklist wording
  re-derived against the staging tree with adaptations recorded BEFORE dispatch.
- Eval folder + worktree remain on disk pending Nicholas's disposition (i47/i48 pattern; i48 + i51
  worktrees both still registered).

## 8. Integrity

Byte-verbatim in this directory (raw sha256): `A_PACK-i51.md`
(8c205c6304068ad92b0ede1c117bba078d4120945913897d1540e277f5293be8), `B_PACK-i51.md`
(05852878a3bf3ae4b2ce12e9b71d42d6b5d17e8de8e2d49f9404fdd51cd7e5e6), `C1_VERDICT-i51.md`
(04968000527f2ba04f7f187d609dbb6e858c737bf0903eb1336883bf7ad5c74b), `C2_VERDICT-i51.md`
(f7134fc1d981d3b9f95617d87fe11f88d0742a5c2c5f7e9b88768cdb6f4d638d), the four dispatch files, and
`materials-i51/` (redacted spec + both neutralized candidates). `MANIFEST-i51.sha256` (committed
alongside) lists every file above + this results file. The i47/i48 records are unchanged by this round:
the i47 quality PASS stands as an i47 fact; i51's floors were breached on THIS run's packs under THIS
run's C round; the efficiency deficiency stands with a sharper mechanism split (F1 task-class + F2
currency + F3 canon + F4 conventions).
