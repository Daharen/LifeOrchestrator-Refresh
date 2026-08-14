# i53 MIGRATION-GATE STAGING RECORD -- fresh two-class legacy-vs-PCB gate (frozen at staging)

**Status: STAGED, frozen at HEAD, pending Nicholas's final review + dispatch.** This record freezes every
pre-registered choice for the i53 gate BEFORE either arm runs. Authorities: `eval/results/N8_RERUN_REFREEZE.md`
(D-0144 run protocol) + `eval/results/N4_BAR_REFREEZE.md` (D-0140 bars) + `eval/I47_EVAL_PACKET.md` s1-s6
mechanics + s7 quality floors (unchanged by N4/N8) + `eval/results/I51_RESULTS.md` (the NO-GO this re-run
answers). Any post-freeze edit voids the run unless Nicholas ratifies it in a D-entry.

## 0. Precondition (N7 -- BLOCKING; PASSED)

Independent harvest + validate at HEAD via the executor (`runtime/i53-stage/precheck-summary.json`):
- HEAD = `1ee201d6f041a4bae45a43519988b852890eb984` (the i52 FINAL N7 close-refold fold).
- harvest at HEAD: `status ok`, `dirty false`.
- **validate: 0 findings, 0 stale.** The shipped map is in-sync at HEAD -> the gate stages its bundle at HEAD
  with **NO side worktree** (the i51 F2 harvest-source workaround is retired; N7 acceptance holds).
- render `--check` vs the committed working-tree `generated/` reported GENERATED_DRIFT on all 6 files -- this is
  the autocrlf artifact (committed working tree is CRLF at 17,265 B; a fresh render is LF at ~16,963 B); the
  bundle build uses EOL-normalized comparison (`boot_matches_committed`, the proven i51 path), so this does not
  affect the gate. The authoritative in-sync signal is validate (0/0), which is green.

## 1. Frozen state + identities

- **EVAL_SHA = HARVEST_SHA = `1ee201d`** (HEAD; N7 in-sync -- eval_sha == harvest_sha, no side worktree).
- **Eval folder (OUTSIDE the repo; grant-level isolation): `C:\Users\just_\LifeOrch-i53-eval\`** --
  `tree\` = `git worktree add --detach` at HEAD (Agent A boot substrate + both arms' deep reads);
  `_bundle\` (Agent B only) = the in-sync 0.4.0 PCB harvested at HEAD (BOOT_PACKET + generated-eval + map-eval +
  tool\); `_facts\` (git-log.txt last 12 + box-state.txt, identical for both arms); `_dispatch\A.md`,`B.md`
  (byte-frozen); `_out\` (the only agent write location).
- **MANIFEST:** `MANIFEST-i53.sha256` (CRLF->LF-normalized sha256 of every `_bundle\` / `_dispatch\` / `_facts\`
  file + this record + the four REF authorities). The gate sessions' isolation = an eval-folder-ONLY grant.

## 2. The two-class task pool (frozen; both arms run BOTH; order pinned T-map FIRST, then T-prose)

Nicholas ratified this exact pair (i53) as the two load-bearing benchmark classes for THIS migration decision --
NOT a permanent taxonomy of orchestrator work (the N8 scope guard).

- **T-map (map-native):** "Produce the current build-state census of the memory subsystem -- modules 35 through
  42 plus module 44 (project.map). For EACH module give: its current version, its build status, the contract
  and/or governing doc that owns it, and any audit widget or active freeze attached to it. Then answer: (a) which
  module in this set is NOT yet built to mvp -- name it, its status, and the decision that governs that state;
  (b) which single contract or governing doc owns the largest share of the subsystem; (c) which of these modules
  sit in more than one plane." -- the answer lives in the map's entity cards, governance/audit edges, planes, and
  overlay; the PCB should serve it at query granularity while legacy must open MODULE_ROADMAP + MEMORY_ARCHITECTURE
  + CURRENT_STATE whole. This is the map's home turf.
- **T-prose (prose-governing):** "Determine what the audit/interpretability program's own governing documentation
  says its NEXT increment should be, and enumerate every active constraint that governs HOW that increment must be
  built (freezes, gates, human-in-the-loop requirements, verification rules). Then produce the full dry-run wave
  plan for the SINGLE next unit." -- the i51 T1 class, now served by N5 (`section:` doc granularity) + N6 (the
  OPERATIONS canon). The constraint-enumeration clause STRESSES the constraint-adherence dimension B lost on in
  i51 (3.0 vs 4.0) -- the sharpest test of whether N6 closed F3.

**GO requires every bar met on BOTH tasks.** Quality floors adjudicated per task; efficiency computed per task.
Anything less is CONDITIONAL, the record naming the failed class (a map-native-only pass licenses nothing by
itself).

## 3. Model pins (N8 rule 5, as ratified)

- **A + B arms = `claude-opus-4-8` (Opus 4.8 Extra, default reasoning).** A pack self-reports its model id; an
  A/B pin miss = RECORD + STOP before dispatch (the efficiency comparison is void otherwise).
- **C1 + C2 adjudicators = `claude-opus-4-8` (Opus 4.8 Extra), the project default frontier tier.** A runtime
  model mismatch is RECORDED and STOPs adjudication BEFORE the C round begins -- no silent substitution, no
  mid-run adaptation. NO Fable 5 escalation is frozen for this run (default). Opus 5 is NOT a fallback (Nicholas
  i52 / D-0144). [The i51 C round drifted to opus-5 unrecorded-until-after; i53 enforces the pin as a pre-C stop.]

## 4. Efficiency accounting (N4 bars + N8 dual-counter; computed orchestrator-side, never disclosed to any arm)

- **Two counters per ledger row, never collapsed (N8 amendment):** `retrieval_bytes` (what the arm CAUSED to be
  transferred/listed/returned) and `model_visible_bytes` (what entered readable context). **The N4 0.7 x A bar
  runs on charged `retrieval_bytes`** (the pre-ratified metric); both are reported side-by-side.
- **Accounting conventions (frozen; the identical dispatch disclosure carries them to both arms):** directory
  listings charged at emitted bytes (a recursive whole-repo listing charged in full); staged/fetched files
  charged at full size whether or not opened (`retrieval_bytes` full, `model_visible_bytes` 0 if unread); a
  bounded/ranged read charged at RETURNED bytes for both arms; a whole-file open charged whole. NO bracketing --
  these leave exactly one accounting.
- **Per-task allocation (frozen at staging -- the two-task extension of N4):** each ledger row is tagged
  `T1 | T2 | BOOT | shared`. `BOOT` (dispatch + boot-source + B's step-0) is a one-time cost amortized **50/50**
  across the two tasks. Per-task total_t = BOOT_retrieval/2 + task-t retrieval. **Bar: B.total_t <= 0.7 x A.total_t
  for t in {T-map, T-prose}.** ALSO reported as cross-checks (not additional gates): per-task retrieval-only (no
  boot) and the COMBINED total (BOOT + all retrieval, the i51-comparable metric). The verdict must be robust
  across these views; if they disagree the record states it (the i51 primary/charitable pattern).
- **N4 BOOT bar (absolute):** BOOT_PACKET renders <= 20,000 B AND carries the CD-1 OPERATIONS canon,
  pointer-backed, degrade-LAST. Boot-total reported, not gated.
- **N4 VOID (PCB-insufficiency):** VOID iff B opens a legacy/handoff doc for an answer NOT already PCB-cited
  earlier in its ledger; corroboration opens do not void but their bytes count.

## 5. Quality floors + verdict mapping (frozen I47 s7, unchanged by N4/N8; applied per task)

- Floor (a): B missing/contradicting ANY absolute item (K1,K2,K3,K4,K6,K7) -> cap at CONDITIONAL.
- Floor (b): B < A by >=1 (C1/C2 mean) on comprehension fidelity OR constraint adherence -> NO cap language ->
  FAIL. (This is the floor i51 breached.)
- Floor (c): a fabricated relationship/citation in B confirmed by C -> FAIL.
- Floor (d): B's step-0 validate/render skipped -> FAIL.
- PASS (per task): no floor; B comp >=3.0 AND constraint >=3.0 (C1/C2 mean); no dimension with a >=2 gap in A's
  favor; work-plan >=3.0; swap-stable (no unresolved >=2 per-dimension C1/C2 disagreement).
- **Verdict:** quality PASS on BOTH tasks AND boot PASS AND total PASS on BOTH tasks AND not-voided -> **GO**
  (PCB becomes the default orchestrator bootstrap; legacy preserved as fallback/history). Any bar unmet/voided or
  quality short on EITHER task -> **CONDITIONAL** (<=3 bounded named deficiencies, legacy default) or **NO-GO**
  (floors breached / >3 deficiencies). INCONCLUSIVE (unstable under swap after escalation) = NO-GO this round.

## 6. Re-derived checklist + fact keys (adaptations recorded at staging; C opens only key-named pointers)

The absolute checklist K1-K12 is carried from I47 s6.1 and spot-checked at HEAD: K1-K5, K7-K9, K11, K12 STABLE;
**K6** stays the i51 sunset adaptation (mandate-02 SUNSET; surviving controls incl. SEALED_CHECK_47 i>=54);
**K10 re-derived to HEAD** = the D-0134 widgets/08 explain-window-close rider (was "poser live-click PENDING /
D-0129" at i47). The T-prose fact key A1-A6 is the i51 key with **A5/A6 updated** for the D-0134 rider. The
T-map fact key M1-M6 is NEW, derived from the shipped map cards/edges/overlay at HEAD (map is 0-stale, so the
cards are authoritative). Full text of all keys is in `_adjudication\ADJUDICATION_SPEC.md` (redacted) + carried
here for the orchestrator's rule application.

## 7. Staging adaptations (recorded BEFORE dispatch, per N8 standing rules)

- **Pack format is two-task** (sections 1-7; TASK-1 census in s2, TASK-2 derivation+constraints+plan in s3, one
  combined ledger in s7 tagged per task). The i51 nine-section single-task format is superseded for this run.
- **The i47/i51 six-item probe set (P1-P6) is DROPPED; the three traps (TR1-TR3) are KEPT.** Rationale: the
  probes' content (module-42 deps, selection-policy canon, warm-pool, P0-1 arc, context-packet contract, recent
  commits) is now substantially covered by T-map (status/governance) + T-prose (constraints) + the K-checklist;
  dropping them keeps the two-task pack within the 25,000 B budget. The traps are the highest-signal blind checks
  (a compressed map is likely to drop them) and are retained verbatim.
- **Blind limitation (recorded up front, i51 pattern):** at HEAD the handoff s4, CURRENT_STATE next-action, the
  overlay frontier, and the staged git-log all name "stage + run the fresh two-class gate," so an arm could infer
  it is inside the migration eval. The packet's partial-blinding posture + the deterministic per-task verdict
  rules absorb this; efficiency is orchestrator-computed and never disclosed to any arm.
- **Honest TOTAL-bar risk (pre-registered):** the BOOT_PACKET lists CURRENT_STATE + FANOUT_ORCHESTRATOR_HANDOFF +
  SEALED_CHECK_47 + START_HERE as boot_read pointers. At HEAD (0 stale) B's step-0 shows in-sync, so B SHOULD NOT
  need to open those whole for currency (the N7 payoff). If B nonetheless opens them whole (~58-64 KB), the
  T-prose TOTAL bar may miss even with query-granular prose retrieval -- a real property of the current PCB the
  gate will measure. If it misses on that, the finding names the next fix (a query-gated boot_read currency check).
  This is NOT engineered around.

## 8. Session flow (from here)

1 Build the eval folder (`stage_i53.py` via the executor; validate 0 / render / boot_matches_committed /
manifest self-verify). 2 Nicholas's final review of this frozen pack. 3 Nicholas dispatches Arm A + Arm B (fresh
sessions, eval-folder-only grant, `claude-opus-4-8`); A/B pin miss = STOP. 4 Packs into `_out\`; orchestrator
computes the per-task dual-counter efficiency; Nicholas's private coin-flip -> Candidate-1/2; orchestrator
neutralizes (I47 s5 table + i51 additions), residual-tell scan EMPTY, quarantines raw packs. 5 Nicholas
dispatches C1 + C2 (Opus 4.8 Extra; mismatch = STOP pre-C). 6 Apply s5 rules per task; author `I53_RESULTS.md` +
MANIFEST byte-verbatim; GO/CONDITIONAL/NO-GO recommendation + evidence to Nicholas. 7 Close per DOC_PROTOCOL s9;
N7 close-refold; regenerate the doc-health monitor.
