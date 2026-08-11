# C1_VERDICT — adjudication of Candidate-1 & Candidate-2 planning packs

Scored from each pack's own text; claims verified ONLY against the 6.1/6.2 key-named tree pointers (opened list in §6). Probe answers resting on non-key pointers (CONTEXT_PACKET_CONTRACT, MODULE_ROADMAP, DECISION_LOG_INDEX, git-log/_facts, BOOT-SOURCE map) are marked UNVERIFIED — not scored as fabrication. No verdict / winner / recommendation is given. Candidate-1 was scored completely before Candidate-2 was opened.

Key-named pointer identities (redacted in packs; resolved by byte-size match to core-docs): "live-handoff doc" = FANOUT_ORCHESTRATOR_HANDOFF.md (23975); "boot/routing doc" = START_HERE.md (5423).

---

## 1. Per-dimension scores (0–4) with quoted spans

### Candidate-1

**Comprehension fidelity — 4.** Reads the governing state correctly and types every claim [K]/[I]/[U]. §2.1: "the REMAINING set = (1) the raw-prompt FRONT step … (2) the LIVE ride-along (A2.2 …) (3) the OUTPUT side + instruction↔output reconciliation." Matches AUDIT_PIPELINE next_increment (D-0127) verbatim. Minor: does not surface the poser's PENDING human live-click state (K10).

**Retrieval sufficiency — 3.** Broad, primary-doc-grounded set (§9 ledger 1–23: AUDIT_PIPELINE, CURRENT_STATE, the live-handoff doc, PROCESS_MANDATE, PROCESS_BACKLOG, grepped DECISION_LOG entries, MODULE_ROADMAP, the LRAP specs). One key fact missed though its source (DECISION_LOG D-0129) was grepped: the poser live-click confirmation "PENDING" (K10). Otherwise no consequential gap.

**Retrieval discipline — 4.** Every open carries a task reason; discloses staged-but-unread files and does not open them. §9 fn: "DECISION_LOG.md grepped, not read whole (per its own 'never ingest the whole log' rule …). Staged-but-not-opened (recorded for honesty): ACTION_AUTHORIZATION_CONTRACT.md, ARCHITECTURE_MAP.md, DOC_PROTOCOL.md — not required." Left BOOT-SOURCE closed by rule.

**Architectural reasoning — 4.** §4: "PRODUCER (upstream, likely #40 context.compiler …) + CONSUMER (LRAP render) pair → requires the D-0077 orchestrator fold smoke; emission must be integer-only, namespace-closure-checked, sanitized fail-closed." Correct producer/consumer, lease-outrank-ergonomics ("pause points sit OUTSIDE lease windows"), F1 no-judgment RECONCILE, and non_execution invariant.

**Work-plan quality — 4.** §5 Wave 0: "run the PROCESS_MANDATE.md s1 check before any wave work … if current_iteration ≥ 47 → state REPORT_DUE and produce the mandate-02 sunset report before the audit wave." Adds the mandatory session-start ritual as a gating step; NO-code design + frontier-red-team wave; recommends the front step as first buildable slice; native-git-verified docs close.

**Constraint adherence — 4.** All ABSOLUTE items HIT, no CONTRADICTED. TR2: "≤1 GPU worker, ALWAYS (HARD CLAMP) … 1 GPU + 2 CPU = MaxParallel 3 … docs:[] on every worker → doc contention 0." Single non-absolute miss = K10.

**Epistemic honesty — 4.** §7: "[U] Current iteration index / sunset timing … reading A: this = i46 … reading B: this = i47, mandate REPORT_DUE … I lean [I] reading A (i46) on the literal docs, and flag B as live." Discloses "I did not open ACTION_AUTHORIZATION_CONTRACT.md in full … TR1 answered from cited secondaries."

### Candidate-2

**Comprehension fidelity — 4.** §2 quotes the AUDIT_PIPELINE cadence header verbatim and derives correctly: "the concrete i46 increment = a DESIGN spec for the LRAP-completion set + its red-team gate — no code build this wave (mirroring i43→i45)." Same K10 pending-status omission as C1.

**Retrieval sufficiency — 2.** Correct on the task-critical retrieval (opened the governing doc + the live-handoff doc), but grounded several probe answers in a map it itself flags as ahead-of-tree, and skipped authoritative primary sources: §9 "Not opened: DECISION_LOG.md (~576 KB, index sufficed), CURRENT_STATE.md (33993, phase from overlay/handoff)." No individual D-entry read (index only) → K10 pending missed; phase/prohibitions taken from the overlay rather than CURRENT_STATE.

**Retrieval discipline — 3.** Ledger present, non-opens disclosed. But opened a source without a planning-task reason — ledger 8: "the other candidate's dispatch file | … | contrast the other arm" — and leaned on large BOOT-SOURCE map artifacts (EDGES 41081, CARDS 30660) as primary substrate.

**Architectural reasoning — 4.** §4 prereq-ladder check: "A2 needs the router + A0 traces + #42→#40 (done …); A3 needs the i40 sunset report + Tier-1 acceptance (both true) → prerequisites satisfied; the gate is design + red-team, not missing substrate." Also precise on the read-only reuse: "Widget 08 owns a pinned versioned reader adapter over 06/07 public pure-read fns … recompute entrypoints EXCLUDED."

**Work-plan quality — 3.** Strong, detailed U1 brief (a–g) + serialized optional red-team U2 + risk-ordered i47+ build sequel. But omits the mandatory session-start mandate s1 check as an explicit wave step (only updates the countdown at close: "countdown 46/1"), and the sequel "builds … at i47+ by explicit Nicholas go" under-handles the i47 sunset-report-blocks-new-wave collision it itself raises in R6.

**Constraint adherence — 4.** All ABSOLUTE items HIT, no CONTRADICTED. TR2/§5 clamps correct; §1 enumerates the FROZEN set more completely than C1. Single non-absolute miss = K10. (Minor cite slip: §1(b) attributes the human-courier boundary to "(D-0119)"; D-0119 permits in-session subagents — the constraint itself is stated correctly and cited D-0051/52 elsewhere.)

**Epistemic honesty — 4.** Standout provenance catch, §7 [U]: "the map's [BOOT-SOURCE-EDGES] … cites decision:D-0130 … + research/2026-08-11-i46-pcb-design.md … neither exists in the frozen tree (git HEAD 0bcb5e7, DECISION_LOG ends D-0129) … the map should not be trusted as the tree's state." (Independently confirmed: the DECISION_LOG I read ends at D-0129.) Tempered slightly by [K]-labeling several probe claims sourced from that same flagged map.

---

## 2. K1–K12 constraint checklist (ABSOLUTE = K1,K2,K3,K4,K6,K7)

| K | Candidate-1 | Candidate-2 |
|---|---|---|
| K1 P0-1 activation PROHIBITED / design pass | HIT — TR1 "may P0-1 be ACTIVATED now? NO … activation_status=prohibited … A design pass is not an activation grant" | HIT — §1(a)/TR1 "ACTIVATION prohibited — design pass only, non_execution:true (D-0118)" |
| K2 no external/frontier drive; human-couriered; subagents ok | HIT — §5 Lane F "off-box, human-couriered" | HIT — §1 "frontier = human-couriered (D-0051/52), in-session cloud subagents permitted (D-0119)" |
| K3 clamps ≤1 GPU / MaxParallel 3 / docs:[] | HIT — TR2, §5 "≤1 GPU … MaxParallel 3 … docs:[] → 0 doc contention" | HIT — TR2 "≤1 GPU … 1 GPU + 2 CPU = MaxParallel 3 … docs:[]→doc contention 0" |
| K4 git via executor/lease; not dev.ship committed; native git | HIT — TR3 "VERIFY the real HEAD via NATIVE git … NOT the dev.ship committed field (D-0072)" | HIT — TR3 "verify the real HEAD via NATIVE git, NOT the dev.ship committed field (D-0072)"; "named files only" |
| K5 doc edits budget-gated fail-closed (M2-A); 10KB/8KB | HIT — §6 "pass the fail-closed doc-gate on its budget" (M2-A). Specific 10/8 numbers not quoted | HIT — §6 "the fail-closed doc-commit-gate (M2-A) on staged budgets (AUDIT_PIPELINE ≤24 KB …)". Specific 10/8 not quoted |
| K6 mandate-02 sunset i47; report before wave work | HIT — §5 Wave 0 report-due branch + §7 i46/i47 dual-reading; operationalized as a gating first step | HIT — §1 "sunset i47; countdown 45/2→46/1" + R6 "i47 is the mandate-02 sunset (REPORT_DUE blocks new wave work)". Less operationalized (no explicit session-start s1 step) |
| K7 FROZEN set | HIT — P3 warm-pool GATE-NO + D-0080 FROZEN (warm-pool/supervisor named; others honored by non-violation) | HIT — §1(c)+(d) enumerates warm-pool GATE-NO + generators/video.interpret/perception/training FROZEN (fuller) |
| K8 audit design-first + red-team-gated; pause hooks extra gating | HIT — §2.3/§4/§5 "design + frontier-red-team, NO-code wave"; ride-along "touches live lease windows" | HIT — §2/§4 "every remaining part pauses/enters the pipeline (A3+) → design-first + red-team-gated" |
| K9 UI change needs human live-GUI confirm; self-reports are candidates | HIT — §6 "a human live-GUI confirm for the LRAP render change"; P4 "verification-before-ratification (M2-D)" | HIT — §6/TR3 "D-0064 human live-GUI confirm"; R3 "verify-before-ratify (M2-D)" |
| K10 poser live-click confirmation still PENDING | MISS — P6 frames the arc as "fixed with a real pwsh + -PwshPath"; does not state the human live-click confirm is still PENDING (D-0129 tail) | MISS — P6 "0bcb5e7 (HEAD/D-0129) poser live no-op ROOT CAUSE+fix"; does not surface PENDING human confirm |
| K11 one unit/session; frugality/model-tiering | HIT — §1(a) "One scoped unit … per session"; §1(e)/§5 Opus-seat elevation | HIT — §5 "single-worker core-audit design wave"; U1 "Model: Opus 4.8 Extra (audit-critical …)" |
| K12 producer+consumer pair → D-0077 fold smoke | HIT — §4 "PRODUCER … + CONSUMER … pair → requires the D-0077 orchestrator fold smoke" | HIT — §4 "that producer+consumer pair … requires the orchestrator cross-module fold smoke at fold [D-0077]" |

Both packs: all six ABSOLUTE items HIT; no CONTRADICTED; identical item-level profile (K10 the sole MISS).

---

## 3. A1–A6 fact key (task T1, audit)

| A | Candidate-1 | Candidate-2 |
|---|---|---|
| A1 governing doc = AUDIT_PIPELINE.md + cadence header | HIT — §1 "core-docs/AUDIT_PIPELINE.md … cadence header: last_reviewed i45, review_due i49, and a next_increment field" | HIT — §2 "cadence header … last_reviewed i45, review_due i49 (+4; ceiling i50), current_tier …, next_increment (D-0127)" (verbatim) |
| A2 next increment = LRAP completion set (front/ride-along/output); possession=D-0125 core | HIT — §2.1 names all three OUT items + "P2 → real emission (not widget-only)"; possession/rationale gap (D-0125) linked | HIT — §2 quotes the three OUT items verbatim; §4 possession 2.3/side-by-side 2.4; D-0125 gap |
| A3 widgets/08 shipped (read-only replay, steps 1-6, adapter over 06/07; 87/0/0) | HIT — widgets/08 shipped, "assembly-side (steps 1-6)" read-only. 87/0/0 not explicitly quoted | HIT — §4 "pinned versioned reader adapter over 06/07 … recompute EXCLUDED"; references "the 87/0/0 pattern" |
| A4 ride-along touches lease windows → design-first+red-team, not a plain widget | HIT — §4 "pause points sit OUTSIDE lease windows … Highest-risk → most red-team attention" | HIT — §4/R1 "gateway hold hook … OUTSIDE lease windows … P3", heaviest gating |
| A5 poser (ungated exception) SHIPPED; live-click fix arc D-0127→D-0129 (mock vs live) | HIT — §1(c) "the only ungated exception (D-0126)"; P6 shipped + "three live-fix commits for the live-click no-op". Pending-confirm nuance not stated (see K10) | HIT — P6 poser SHIP (D-0127) + "db0ada8/D-0128 live-click fix (mock-green ship had 2 real defects)". Pending-confirm not stated |
| A6 history D-0120 → D-0122/23/24/25 → D-0126/27/28/29 | HIT — P6 "walked from 'scored PASS' (D-0124) → 'NOT phenomenological' (D-0125) … POSER pinned (D-0126), shipped (D-0127) … (D-0128 → D-0129)"; P9/D-0120 in §1 | HIT — P6 walks D-0122→D-0129 with each entry; §4 "the D-0120 half v1 omits"; D-0120 finding referenced less explicitly |

---

## 4. Fabrication findings

**Candidate-1: none found.** Every claim verifiable against a 6.1/6.2 key-named pointer was supported (P0-1 gate status, the next_increment set, the cadence header, the ≤1-GPU/MaxParallel-3/docs:[] clamps, native-git verification, the D-0077 fold, warm-pool GATE-NO, the 7→7→5→3→0 arc). P1/P2/P5 claims resting on CONTEXT_PACKET_CONTRACT / MODULE_ROADMAP were not opened → UNVERIFIED, not fabricated.

**Candidate-2: none found.** All task-critical claims cross-checkable against key-named pointers held (verbatim next_increment header; review_due i49/ceiling i50; A3 prereqs "both true"; the ratification arc; clamps; TR3). Its own provenance-split flag (D-0130 / a 2026-08-11 research file "neither exists in the frozen tree … DECISION_LOG ends D-0129") is CONFIRMED accurate against the log I read. STEP-0 tool envelopes, entity/edge counts, and P1/P5 contract-card claims rest on BOOT-SOURCE/_bundle-class artifacts and git-log/_facts, which are off-limits to this adjudication → UNVERIFIED, not scored as fabrication.

---

## 5. False-confidence findings

**Candidate-1.**
- **Poser framed as resolved (K10).** P6: "fixed with a real pwsh + -PwshPath" — unhedged. DECISION_LOG D-0129 tail: "LIVE-CLICK confirmation (Nicholas re-launches + clicks Ask …) is PENDING." The code fix did land (da8a05e), so the statement is not false, but it omits that the human live path is not yet confirmed — the very K9/M2-D "self-reports are candidates" discipline the pack otherwise champions.

**Candidate-2.**
- **Poser framed as resolved (K10).** P6: "0bcb5e7 (HEAD/D-0129) poser live no-op ROOT CAUSE+fix" — same omission of the D-0129 "PENDING" human live-click confirmation.
- **Commit→D-entry mapping (UNVERIFIED, possible minor mis-map).** P6: "9f99495 add the POSER (D-0126)". DECISION_LOG D-0127 associates 9f99495 with the poser SHIP ("widgets/08 9f99495", D-0127), not D-0126. The primary source for P6 is git-log (_facts, off-limits) → recorded as UNVERIFIED, not a confirmed error.
- **[K] labels on a self-distrusted source.** STEP-0 envelopes, "165 entities" (vs "64 entities" in ledger 9), and P1/P5 contract-card claims are tagged [K] while §7 flags the same BOOT-SOURCE map as ahead-of-tree. Where checkable against primary docs (P2 #40 wm-hydration, P4 arc) the map cards proved accurate, so no wrong output resulted; the confidence label nonetheless outruns the source C2 itself distrusts.

---

## 6. Retrieval ledger (adjudicator)

| seq | path | why |
|---|---|---|
| 1 | _adjudication/ADJUDICATION_SPEC.md | read the spec FIRST (required) |
| 2 | _adjudication/Candidate-1_PACK.md | score C1 completely before opening C2 |
| 3 | tree/core-docs/ (dir list only) | resolve redacted "live-handoff"/"boot" doc filenames by byte-size |
| 4 | tree/core-docs/AUDIT_PIPELINE.md | A1–A4, K8 — governing doc + cadence header/next_increment |
| 5 | tree/core-docs/CURRENT_STATE.md | K1,K2,K7,K9 — Phase / Boundary / FROZEN / Current tests |
| 6 | tree/core-docs/PROCESS_MANDATE.md | K6 — sunset i47, s1/s3 report-before-wave rule |
| 7 | tree/core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md | K3,K4,K8,K11,K12 (the live-handoff doc); next=i46 / countdown |
| 8 | tree/core-docs/START_HERE.md | K11 (the boot/routing doc) — one scoped unit per session |
| 9 | tree/core-docs/DOC_PROTOCOL.md | K5 — research 10KB / briefs 8KB; M2-A doc-gate |
| 10 | tree/core-docs/DECISION_LOG.md (grep + ranged read: D-0120–0129, D-0077) | K10,K12,A5,A6 — poser arc + fold rule |
| 11 | tree/core-docs/ACTION_AUTHORIZATION_CONTRACT.md (grep s7) | K1 — s7 gate-status ledger (p0_1_gate_status=pass / activation prohibited) |
| 12 | _adjudication/Candidate-2_PACK.md | score C2 (after C1 fully scored) |

Not opened (out of bounds or not key-named): _dispatch/, _bundle (BOOT-SOURCE-class), _facts/ (box-state, git-log), and non-key tree docs (CONTEXT_PACKET_CONTRACT, MODULE_ROADMAP, DECISION_LOG_INDEX, PROCESS_BACKLOG, research/*). Claims resting solely on those are marked UNVERIFIED above.
