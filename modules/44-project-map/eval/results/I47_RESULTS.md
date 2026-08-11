# I47 MIGRATION-GATE RESULTS -- legacy vs PCB bootstrap (D-0133)

**VERDICT: CONDITIONAL.** Quality PASS under the frozen I47_EVAL_PACKET s7 rules (floors clear; swap-stable); ALL efficiency / bounded-boot claims VOID for this run by the pre-registered MECHANISM-NOT-EXERCISED clause (RT2-F9). **The legacy handoff remains the default orchestrator bootstrap** until the i48 CONDITIONAL re-check passes. Applied by the i47 orchestrator; C1/C2 outputs committed byte-verbatim alongside; the orchestrator summarized but never altered them (RT2-F13).

## 1. Run record

- Packet: `eval/I47_EVAL_PACKET.md`, MANIFEST 30/30 OK at session start AND re-verified on the staged copies (28/28 bundle files) before dispatch. EVAL_SHA `0bcb5e7d9fdcd78a85cd4b646c9e2aca8190520c`; detached worktree verified by rev-parse.
- Task: **T1** (Nicholas, recorded 2026-08-11T14:15Z; installed into both dispatch files 14:16:42Z, hash-asserted).
- **A run VALID** (dispatch sha `9daf2b43...`): eval-folder grant only (Nicholas-confirmed; its ledger rows 1-3 = names-only skeleton probing to LOCATE the folder, then the grant). Pack `A_PACK.md` 24,414 B, sha `fe12bd28...`.
- **B run 1 VOID** (wrong grant): dispatched with the REPO folder connected; its ledger read the live staging task + ran git against the live repo (saw HEAD `53c211f`, 6 ahead) and reconstructed the condition. Isolation (RT2-F1/F2) + agent-blinding broken -> VOID per s2/s5; ONE re-run licensed. Void pack preserved: `B_PACK-void-run1.md`, sha `164dde9d...`. (Agent behavior itself was honest and well-flagged.)
- **B run 2 VALID** (dispatch sha `be126ff8...`, same frozen bytes): every ledger row in-condition (eval folder only); `_out\B_PACK.md` 24,997 B, sha `4c1acc47...`; frozen tree untouched (0 files modified, both checks).
- **Blinding:** Nicholas's private literal coin flip = **KEEP** -> A = Candidate-1, B = Candidate-2. Neutralization by the s5 mechanical table (recorded in `materials/`; two legend-decode scrubs added -- a pack legend line may not undo the substitution). C1 scored Candidate-1-first; C2 scored Candidate-2-first; both returned scores+quotes+tables ONLY (verified: no verdict/winner language). C1 noted it resolved the two redacted doc identities by byte-size match -- the partial-blinding case the packet pre-accepts (s5 honesty note); the deterministic rules below absorb it.
- Model pin: A, B, C1, C2 all report `claude-opus-4-8` (the Opus 4.8 Extra seat tier). Orchestrator seat this session: Fable 5 (Nicholas's dispatch).
- Verdicts: `C1_VERDICT.md` 15,673 B sha `fdb7d3e5...`; `C2_VERDICT.md` 10,120 B sha `619d9d8e...` (both <=20,000).

## 2. Score matrix (0-4; seven C-scored dimensions; efficiency = s7 proxies, orchestrator-computed)

| dimension | A=Cand-1 (C1) | A (C2) | A mean | B=Cand-2 (C1) | B (C2) | B mean | gap A-B |
|---|---|---|---|---|---|---|---|
| comprehension fidelity | 4 | 4 | **4.0** | 4 | 4 | **4.0** | 0 |
| retrieval sufficiency | 3 | 3 | 3.0 | 2 | 3 | 2.5 | 0.5 |
| retrieval discipline | 4 | 4 | 4.0 | 3 | 4 | 3.5 | 0.5 |
| architectural reasoning | 4 | 4 | 4.0 | 4 | 4 | 4.0 | 0 |
| work-plan quality | 4 | 4 | 4.0 | 3 | 4 | **3.5** | 0.5 |
| constraint adherence | 4 | 4 | **4.0** | 4 | 4 | **4.0** | 0 |
| epistemic honesty | 4 | 4 | 4.0 | 4 | 4 | 4.0 | 0 |

**Swap stability:** max C1-vs-C2 disagreement on any dimension = 1 (threshold >=2) -> STABLE; no escalation, no INCONCLUSIVE.
**Checklist:** both candidates 6/6 ABSOLUTE HIT (K1,K2,K3,K4,K6,K7), 0 CONTRADICTED; both verdicts agree the sole item-level miss is **K10** (poser live-click still PENDING) -- which is precisely the open D-0129 item awaiting Nicholas. **A1-A6:** all HIT both candidates (C2 marks B's A6 HIT-partial: D-0120 not cited). **Fabrications: none found** by either adjudicator (UNVERIFIED != fabricated; C's pointer set was the 6.1/6.2 key only).

## 3. s7 rule application (verbatim; rule -> finding)

| rule | finding |
|---|---|
| Floor (a) B missing/contradicting ANY absolute item | NOT TRIPPED -- B 6/6 HIT, 0 CONTRADICTED (both verdicts) |
| Floor (b) B < A by >=1 (mean) on comprehension OR constraint | NOT TRIPPED -- both gaps 0.0 |
| Floor (c) fabricated relationship/citation in B confirmed | NOT TRIPPED -- none found |
| Floor (d) B step-0 validate/render skipped | NOT TRIPPED -- both envelopes run + recorded (validate ok/0 errors; render --check ok/stale 0) |
| PASS: B comp >=3.0 AND constraint >=3.0 | MET -- 4.0 / 4.0 |
| PASS: no dimension >=2 gap in A's favor | MET -- max gap 0.5 |
| PASS: work-plan >=3.0 | MET -- 3.5 |
| PASS: swap-stable | MET -- max disagreement 1 |
| Efficiency: MECHANISM-NOT-EXERCISED | **TRIPPED** -- B run-2 ledger row 16 opened `tree\core-docs\FANOUT_ORCHESTRATOR_HANDOFF.md` (23,975 B; why: "wave mechanics"), not via a START_HERE routing line -> ALL efficiency/bounded-boot claims VOID for this run |
| Verdict mapping: PASS quality + efficiency bar unmet/voided | **CONDITIONAL** (the deficiency IS efficiency; bounded corrections below) |

## 4. Efficiency proxies (computed from artifacts; recorded although VOID)

Sizes = the EVAL_SHA worktree checkout (tree-sizes dump), per s7; query rows = output bytes as recorded.
- **A:** boot(narrow, pre-registered primary: dispatch 2,447 + START_HERE 5,423 + handoff 23,975) = **31,845 B**; boot(broad sensitivity, + its stated reading path opens) ~131,491 B. Retrieved files 193,084 B + tree-listing output 123,612 B + 3 DECISION_LOG greps (outputs unrecorded by A -> bounds [0 .. 3x576,158]). **Total [348,541 .. 2,077,015] B**; opens 15; queries 8.
- **B run 2:** boot = dispatch 2,934 + BOOT_PACKET 12,945 + step-0 envelopes (~600 est.) = **~16,479 B**; retrieved ~225,191 B (incl. handoff 23,975 + EDGES 41,081 + L1-modules 30,660); **total ~241,670 B**; opens ~17; queries ~8.
- Against the bars (VOID, shown for the record): boot 16,479 vs 0.5xA(narrow)=15,922 -> would MISS by ~3.5% (would PASS the broad-A sensitivity); total 241,670 vs 0.7xA(min)=243,979 -> would PASS by ~1%; vs 0.9xA -> no second void trigger. The pre-registration of the narrow-boot primary was made before B run 2 existed (recorded in-session).

## 5. CONDITIONAL deficiencies (<=3; each ONE bounded i48 unit WITH an acceptance test; legacy stays default until the re-check passes)

- **CD-1 -- boot-surface wave-mechanics coverage.** Finding: given the whole tree, the PCB-booted agent still opened the legacy handoff for wave mechanics/clamps -- the BOOT_PACKET/L1 layer does not carry the s1/s4/s7-s9 operational canon. Unit: extend the generated views (BOOT_PACKET operations section or an L1 ops card) with the clamp/lease/ship-verify canon, pointer-backed, within the 20 KB packet budget. **Accept:** a fresh PCB-booted dry-run agent answers K3/K4/TR2/TR3 completely with NO `tree\` handoff open in its ledger (RT2-F9 un-triggered).
- **CD-2 -- efficiency bars unproven.** Unit: after CD-1, re-run the efficiency comparison under the same frozen mechanics (fresh task pick per Nicholas). **Accept:** both s7 bars met, un-voided.
- **CD-3 -- map query-surface gaps.** Finding: B's recorded tool limits (`edges:module:42|30|37` -> `[]`; `entity:widget:08` -> DANGLING_REF; the map-vs-tree provenance split it flagged) pushed it to bulk card/EDGES reads. Unit: edge-query id forms + alias resolution + provenance-at-EVAL_SHA hygiene in #44. **Accept:** B run-2's three failed/flagged queries return non-empty/resolved against the same map.

## 6. Anomaly + decision log (all recorded in-session)

1. Nicholas's observer note ("A didn't use the executor") -- under the dispatch HARD RULES executor jobs are forbidden (dry run); the concern is scored via K4/TR3 (both candidates HIT). Kept out of adjudication materials.
2. B run-1 wrong-grant VOID + one re-run (s5); root cause = dispatch folder-attach flow; fixed by explicit eval-only attach on the re-run.
3. A_PACK quarantined out of `_out\` before the B re-run (restored after); raw packs quarantined before the C runs; `_out\` empty at each dispatch point.
4. Redaction decisions: the efficiency dimension moved out of C scoring (the rubric's own anchor defers to s7 proxies C cannot compute); the false-confidence-hunt "compact-map" phrase neutralized to avoid mechanism leakage; two legend-decode scrubs added to the s5 substitution table.
5. C outputs verified scores-only; C ledgers within bounds (spec + packs + key-named pointers).
6. Shared K10 miss across A, B, C-noted: the LRAP poser live-click confirm is STILL PENDING (D-0129) -- Nicholas's open item, now independently rediscovered by the eval.

## 7. Integrity

Byte-verbatim in this directory: `C1_VERDICT.md` (`fdb7d3e5c647769f660209d263e94fcdbaa711341e04938900db16a20bcf52f2`), `C2_VERDICT.md` (`619d9d8eca8e222f4321665bf66c843efc860bfcada3f000227c34dc69f26e4e`), `A_PACK.md` (`fe12bd2816402f0e20a9b546fff9407279e9f8be3b5ebc364472df67e7685e41`), `B_PACK.md` (`4c1acc477a5b3daa606f022a8699c19e29c92f9fc00dde435e5c5700468c7251`), `B_PACK-void-run1.md` (`164dde9d9846c45698fae2b4d342bee2d2dacdbddeef59f1555c2f36cc2364ef`). `materials/` = the redacted spec, both neutralized packs, the two C dispatches, and the two final A/B dispatches (T1-inserted). The eval folder + worktree remain on disk pending Nicholas's disposition (packet s8-7).
