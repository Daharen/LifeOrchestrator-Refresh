# I48 RE-CHECK RESULTS -- the CD-1 probe + CD-2 A/B efficiency re-run (D-0136)

**VERDICT: the CONDITIONAL re-check FAILS -- efficiency VOID (RT2-F9, twice over) AND both bars missed
as computed. THE LEGACY HANDOFF REMAINS THE DEFAULT ORCHESTRATOR BOOTSTRAP. No migration.** Quality/
comprehension parity repeated (both arms derived the identical correct increment with every trap hit).
Applied by the i48 orchestrator (Fable 5 seat); packs committed byte-verbatim alongside; the orchestrator
summarized but never altered them (RT2-F13). Nicholas ran the whole loop REMOTELY (held sessions, GO
messages, the s5 intervention rule available but never needed).

## 1. Run record

- **EVAL_SHA_2 = `2fc483f`** (the i48 fold commit). Eval folder `C:\Users\just_\LifeOrch-i48-eval\`:
  detached worktree at EVAL_SHA_2; `_facts` (git-log 12, box-state); `_bundle` (map-eval + generated-eval +
  BOOT_PACKET 15,111 B + harvest-eval.json + the 0.2.0 tool; step-0 self-check green at staging);
  `_dispatch` PROBE/A/B (A/B = the FROZEN I47_EVAL_PACKET s4 text verbatim, folder name updated; the probe
  is NEW, mechanism-blind); MANIFEST-i48.sha256 (30 rows, CRLF->LF shas). Staging note: generated-eval was
  first copied from the committed render (harvest @24347fe) -> GENERATED_DRIFT vs the eval harvest
  (@2fc483f) -> bundle-locally re-stamped (overlay at_commit -> 2fc483f; the fold commit is the only delta
  and every map-cited source is byte-identical) + fresh-rendered; recorded here.
- **Sessions (all `claude-opus-4-8`, eval-folder grant ONLY):** i48-PROBE-B (pack 11,983 B, 20:54Z),
  i48-EVAL-A (23,664 B, 21:12Z), i48-EVAL-B (19,918 B, 21:14Z). Worktree pristine after every run
  (`git status --porcelain` = 0 modified, checked at each pull).
- **Task:** T3 verbatim (pre-registered i46 wording). T2 was INVALID on this tree (its wording presumes a
  live process mandate; the mandate sunset at i47) -- the choice set collapsed to T3; Nicholas deferred the
  pick and no discretionary (answer-aware) selection occurred. Inserted into both dispatch files
  identically post-probe (A.md 2,526 B sha 3d6b0c16...; B.md 3,013 B sha d68f9091...; manifest re-run).
- **No C-adjudication round** (quality passed at i47; this re-check gates efficiency only, per D-0133).

## 2. CD-1 probe (PROBE_PACK.md)

- All four canon questions answered completely and correctly; ledger rows 5-10 show the PCB ALONE answered
  them FIRST (BOOT_PACKET OPERATIONS + the five `ops:boot-*` queries), and the pack states its answers
  stand on the PCB citations. THEN rows 11-14: four `tree\` opens for exact-quote corroboration, one being
  the legacy handoff. **Strict CD-1 bar ("NO tree-handoff open") = NOT MET.** Root cause judged an
  ORCHESTRATOR PROBE-DESIGN DEFECT (recorded before A/B ran): the probe dispatch demanded pointer-cited
  completeness and carried the B-protocol "legacy docs are not forbidden" line -- inviting corroboration --
  and set no economy signal; it therefore measured "will a thorough agent ALSO read primary sources when
  free to" (yes, trivially) rather than "does the PCB suffice" (its ledger answered: yes). Decision at the
  time: fold the CD-1 acceptance into the CD-2 B ledger (the D-0133 wording describes exactly that agent)
  rather than over-claim a pass or re-probe; risk named (T3 spend on a void).

## 3. CD-2 efficiency computation (s7 proxies, orchestrator-computed from the packs' own ledgers)

**A (legacy boot):** boot(narrow, pre-registered primary) = dispatch 2,526 + START_HERE 5,423 + handoff
23,891 = **31,840 B**. Retrieved (ledger rows incl. the 154,920 B recursive tree listing and every grep'd
file at full size) = **666,679 B**. **Total = 698,519 B**; ~21 file opens + 4 dir/queries.

**B (PCB boot):** boot = dispatch 3,013 + BOOT_PACKET 15,111 + step-0 envelopes (~600 est., i47
convention) = **18,724 B**. Retrieved = **839,263 B** + query outputs (~5,000 est.): harvest-eval.json RAW
**478,784** + project_map.py source **90,116** + arch-positions.json RAW **82,474** + L1_CARDS_modules
31,388 + ROADMAP 31,826 + CPC 35,121 + MEM_ARCH 30,427 + **handoff 23,891 (row 19)** + INDEX 19,996 +
PB 4,826 + git-log 9,981 + box-state 433. **Total ~= 862,987 B**; ~14 opens + ~9 queries/runs.

| rule (FROZEN s7) | computation | finding |
|---|---|---|
| VOID (a): B opened the legacy handoff, no START_HERE route | B ledger row 19 (why: "wave canon + deferred menu") | **TRIPPED -> VOID** |
| VOID (b): B total > 0.9x A total | 862,987 > 628,667 | **TRIPPED -> VOID** |
| Bar 1: B boot <= 0.5x A boot(narrow) | 18,724 vs 15,920 | **MISS (+17.6%)** |
| Bar 2: B total <= 0.7x A total | 862,987 vs 488,963 | **MISS (B = 1.24x A)** |

**B ingested ~24% MORE than A.** Verdict mapping (D-0133): bars unmet/voided -> the CONDITIONAL is NOT
lifted -> **legacy stays default; no migration unit licensed.**

## 4. Findings (mechanism-precise; the value of the negative result)

- **F1 (dominant, ~75% of B's ingest): raw-store fallback.** harvest-eval.json 478,784 + project_map.py
  90,116 + arch-positions.json 82,474 = **651,374 B** of raw reads. Root cause: the load-bearing DEEP
  narrative (manifest `purpose` strings -- where the fast-beam residual sentence lives -- and SCHEMA_NOTES
  content) is NOT reachable at query granularity, so a thorough agent greps the raw store; the whole file
  counts (the pre-registered proxy) and costs MORE than A's curated docs. The legacy handoff is,
  functionally, a hand-curated ~24 KB cache of exactly-what-an-orchestrator-needs; the PCB cannot beat it
  on bytes until L2 serves deep content query-granular.
- **F2: the boot bar is arithmetically unreachable post-CD-1.** The bar (0.5 x A-narrow = 15,920) leaves
  ~12.9 KB for the packet after the dispatch; the packet is 15,111 B BECAUSE CD-1 added the canon the i47
  run was faulted for lacking. CD-1 and the frozen boot bar are in direct tension; the bar was calibrated
  to the 13 KB pre-canon packet. A migration decision cannot rationally hang on an unreachable bar.
- **F3: the handoff-open's WHY changed.** i47: canon need (closed by CD-1 -- TR2/TR3 now cite BOOT_PACKET
  OPERATIONS first, in both the probe and B). i48: frontier/deferred-menu detail + corroboration (the
  overlay carries candidates but not the s4 richness).
- **F4: B read the tool source (90 KB) to learn the query verbs** although the packet's RETRIEVAL PROTOCOL
  documents the invocations -- an exact query-verb table (with the closed set + short forms) in the packet
  is a cheap packet-side fix.
- **F5 (positive):** comprehension parity AGAIN (identical correct increment, all traps hit, both arms;
  A additionally surfaced line-level archive/SCHEMA_NOTES provenance). The PCB's fail-closed step-0 held in
  the field: B's first `render --check` correctly fired GENERATED_DRIFT on its own incomplete /tmp staging
  and B recorded the refusal as a result. Both packs double as REAL design input for the eventual #40
  beam-width wave (menu item d) -- T3 was spent but not wasted.

## 5. Disposition + named next units (i49 candidates -- Nicholas direction required; NOT executed tonight)

- **N1 -- L2 narrative surface:** serve `purpose` / SCHEMA_NOTES sections at query granularity (the CD-3
  pattern applied to deep content) so raw-store greps become bounded queries.
- **N2 -- overlay/packet frontier richness:** carry the deferred-menu/frontier detail so handoff s4 is not
  needed for task-scoping.
- **N3 -- packet query-verb table:** exact invocation forms in the RETRIEVAL PROTOCOL section (kills F4).
- **N4 -- bar re-freeze (NICHOLAS RATIFICATION REQUIRED):** the frozen bars are arithmetically dead
  post-CD-1 (F2); any future gate needs re-frozen, coherent bars (e.g., an absolute boot bound + a total
  bar measured WITH the query surface) ratified in a D-entry BEFORE the next run.
- Eval folder + worktree remain on disk pending Nicholas's disposition (i47 pattern).

## 6. Integrity

Byte-verbatim in this directory: `PROBE_PACK.md`, `A_PACK.md`, `B_PACK.md`, `PROBE-dispatch.md`,
`A-dispatch.md`, `B-dispatch.md` (T3-inserted forms), `MANIFEST-i48.sha256`. Worktree untouched at every
pull (0 modified). The i47 record (`I47_RESULTS.md`) is unchanged by this round: quality PASS stands;
the efficiency deficiency stands UNRESOLVED with a sharper mechanism attribution (F1-F4).
