# PROCESS MANDATE 02 -- SUNSET METASTABILITY REPORT (i47, 2026-08-11)

**Produced per the archived `PROCESS_MANDATE.md` s3 at `sunset_iteration=47` (opened i40, D-0110; licensed by Nicholas), BEFORE any i47 wave/experiment work (the frozen I47 migration-gate run follows this report).** State transition: ACTIVE -> REPORT_DUE -> SUNSET; the mandate doc is archived to `archive/mandates/mandate-02-i40-i47.md` and the live doc DELETED (s4; the YES path licenses no successor). All numbers measured: byte counts `wc -c` at HEAD `b2aca12`; gate evidence `ops/out/doc-gate-log.jsonl`; monitor `ops/out/doc-health-log.jsonl` (19 rows; `doc_gate_hook: grn` at the i46 close); session discipline `git log -- core-docs/PROCESS_MANDATE.md`.

## 1. Item dispositions (s3.1)

**M2-A (PB-1 successor) -- the deterministic fail-closed doc-hygiene commit gate: SHIPPED i42 (D-0117), ON its hard deadline.** `ops/audit/doc-commit-gate.py` (pure stdlib, staged-blob-measured) + the git pre-commit hook (presence + hash asserted `grn` by `gen-doc-health.py` at every close since) + the `--files` executor invocation; all three D-0094 parts (accretion tripwires, proportional budgets via `parse_budgets()`, the ~40 KB re-layer trigger). ACCEPTANCE = the real firing triple logged 2026-08-08: REJECT of a deliberately over-budget probe (11,927 B vs the 10,000 B research budget) via a real commit attempt, corrected PASS (`821705c`), clean deletion (`25bf2b3`); gate tests 26/26 + hook-presence 5/5. Dogfood at ship: the i42 fold's own CURRENT_STATE edit busted 34 KB and was slimmed to comply (`963573d`).

**M2-B (PB-3 successor) -- hold the hot docs under budget: HELD, MECHANICALLY, four consecutive closes (i43-i46).** At the mandate-01 sunset the worst three measured 185% / 197% / 132% of budget -- the epoch's measured worst, ON the sunset date. Today: CURRENT_STATE 33,987/34,000 (99.96%), HANDOFF 23,857/24,000 (99.4%), MODULE_ROADMAP 31,646/37,000 (85.5%), DECISION_LOG_INDEX 19,985/20,000 (99.93%) -- every doc EDITED since i42 is at or under budget, and the INDEX re-distills recorded at i41 (pre-gate, mandate-driven), the i42 addendum, and i46 (both under the live gate) kept it there. Grandfathered exceptions (pre-gate bytes, untouched since adoption; the gate makes growth impossible without a slim): PROJECT_DIRECTION 10,756/9,000 (120%, byte-identical to its mandate-01 reading) + MEMORY_ARCHITECTURE 30,427/30,000 (101%) -- slim-at-next-touch, ceilings FROZEN in SEALED_CHECK_47 SP3. The >40 KB set (MEMORY_CONTRACT 44,058; TOOL_MODEL_REGISTRY 41,276) has its re-layer path on file (M2-C below).

**M2-C -- docs-into-memory: ADVANCED TO DESIGN + SUBSTRATE; DEFERRED to roadmap FO-3 with live deterministic triggers.** The PCB (#44, i46, D-0130/31) built the routing/re-layer structure M2-C anticipates (design s6: doc shards -> #36 `ingest_records`; CURRENT_STATE + DECISION_LOG_INDEX first candidates). The INDEX sitting at 99.93% of cap is the standing trigger; no mandate is needed to carry it -- FO-3 + the gate's refusal pressure are the carriers.

**M2-D -- verification-before-ratification: RESOLVED STRUCTURALLY i42 (D-0118).** The round-5 independent review PASS was IN HAND when s7 was ratified (`p0_1_gate_status=pass`, pack `6bb613ea` named in the D-entry). The discipline caught two over-claims (D-0107/D-0109), then converged honestly 7->7->5->3->0. It survives the mandate as the ACTION_AUTHORIZATION_CONTRACT s7 ledger practice + the handoff standing rule + K9 of the frozen I47 answer key.

**M2-E -- subagent boundary ruling: RESOLVED i42 (D-0119, Nicholas).** In-session cloud subagents PERMITTED inside D-0051-as-amended; frontier stays human-couriered (D-0052). PB-2 unblocked and correctly still unbuilt (its build trigger is deterministic + non-displacing).

## 2. The four control dimensions (s3.2), delta vs the mandate-01 report

**(a) Stale-content PREVENTION: manual-only -> FAIL-CLOSED-MECHANIZED.** The gate refuses violating commits at commit time; one real REJECT on record plus four closes shipped under it. The i39-class failure ("grew 170%->197% while the monitor logged it") is now impossible for tracked docs.

**(b) RECOVERY: partially-mechanized (grade held; the missing half now has a named path).** Restore unchanged and exercised (handoff snapshots i43-i46; the mandate-01 archive; nothing destroyed). Re-layering -- "never invoked" at mandate-01 -- now exists as built substrate + design (PCB map + FO-3), not yet executed.

**(c) MEMORY: partially-mechanized (grade held; materially advanced).** The docs corpus now has a deterministic fail-closed comprehension layer BUILT FROM it (#44: 143 entities / 98 edges, validate 0 findings, BOOT_PACKET <=20 KB, refusal path proven live in the fold). Zero core-docs are yet #36-retrievable records (FO-3). The I47 experiment measures the layer's operational value.

**(d) LOCAL controls: partially-mechanized; the epistemic gap NARROWED.** Mandate-01: both over-claims caught ONLY by the frontier lane. This epoch: the honest-convergence discipline is structural (M2-D), and i46 produced two LOCAL catches of the mock-green/box-red class (the tests-wrapper `$live`/`$Live` collision; the WindowsApps python stub) via the orchestrator's independent re-verify, plus a live fail-closed REFUSAL (first claims ingest refused, 220 FIELD_UNCOVERED -> corrected -> 0 findings). Frontier review remains the ratification instrument BY DESIGN, not as a compensating control.

## 3. Metastability verdict (s3.3): **YES** (evidence-based; reverses mandate-01's NO)

The question: will roadmap + backlogs keep being considered + posed at intervals WITHOUT front-loading or a human re-poking?

1. **The forcing function is no longer prose -- or the mandate.** Mandate-01's NO rested on what remained after ITS sunset being prose, the control class that measurably failed. What remains after THIS sunset is a fail-closed mechanical gate on every core-doc commit (fires regardless of any mandate's existence), deterministic backlog triggers, cadence headers, and the monitor.
2. **This epoch, posing CONVERGED the debt instead of watching it grow.** M2-A shipped ON deadline (mandate-01's PB-1 shipped nothing in 8 iterations); hot-doc debt went from its measured worst to at-or-under cap and STAYED there for four closes; countdown discipline 7/7 sessions (i41-i47: `246fbeb`, `963573d`, `3db60ce`, `023fa5b`, `a3b612b`, `4fd2ecc`, `fea1fd9`, + this sunset) with zero re-poking.
3. **Consideration-at-intervals demonstrably fires action absent a build directive:** the i43-i45 no-code-wave sessions still produced the LRAP capture + the AUDIT_PIPELINE promotion + cadence keeping (review_due honored or bumped-with-reason at every wave scoping); PB-5 closed on its deterministic trigger; the capture rule kept new debt in rows instead of drifting handoff residuals.
4. Each mandate-01 NO reason is specifically answered: prose controls -> mechanical gate; posing-without-convergence -> converged + held; self-report failures caught only externally -> M2-D structural + two local catches + one live refusal.

Residual risk, stated honestly: the per-session countdown WAS mandate scaffolding and dies today. Whether the surviving constructs hold unsupervised is exactly what s5 exists to measure -- the verdict INITIATES that measurement rather than asserting it away.

## 4. The sealed check (s3.4 YES path): INITIATED

`core-docs/SEALED_CHECK_47.md` created this session: 7 machine-checkable predicates (gate+hook presence and wiring; the real firing on record; budgets held with the two grandfathered ceilings FROZEN at today's bytes; monitor regenerated post-i47 with hook `grn`; no overdue live mandate; AUDIT_PIPELINE cadence current at evaluation; the FO-3 re-layer plan still routed), `open_after_iteration: 54` (= 47 + the s6 offset 7), an integrity hash over the predicates section, and a DO-NOT-OPEN banner. ALL pass at i>=54 -> the constructs held unsupervised. ANY fail -> re-license a mandate targeting exactly the regressed predicates. **No mandate 03 is proposed.**

## 5. Sunset mechanics (s4) -- executed this session

Header set `current_iteration: 47 / iterations_to_sunset: 0 / state: SUNSET`; doc copied to `archive/mandates/mandate-02-i40-i47.md` + an ARCHIVE_INDEX line; live `PROCESS_MANDATE.md` DELETED (YES path -- nothing replaces it; SEALED_CHECK_47 is the successor instrument); DOC_PROTOCOL s2 mandate row retired + a 4 KB SEALED_CHECK_47 row added; PB-1 closed `DONE (D-0117)`; PB-3 triggers reworded to post-mandate form; this report committed at `core-docs/research/2026-08-11-process-mandate-02-report.md` + mirrored to the Project; D-0132 + index row.
