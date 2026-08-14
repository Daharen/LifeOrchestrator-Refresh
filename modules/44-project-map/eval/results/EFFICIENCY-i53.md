# i53 EFFICIENCY COMPUTATION (orchestrator-side; pre-stated BEFORE the C round; never disclosed to any arm)

Model pins: A + B BOTH `claude-opus-4-8` (self-reported line 1 of each pack) -> **pin HOLDS, efficiency
comparison valid.** Packs: A 24,647 B, B 23,604 B (both <= 25,000). MANIFEST re-verified untampered; tree clean.
Dual counters: for BOTH arms retrieval_bytes ~= model_visible_bytes (no staged-but-unread rows). B's step-0
caused the on-device validator to read harvest-eval.json (488,506) + map-eval internally -- charged to NEITHER
counter (deterministic-layer internal materialization; only the envelopes entered context). This is exactly the
N8 dual-counter case ("do not confuse how much the computer touched with how much expensive intelligence
consumed"); recorded, not gated.

## Per-arm ledger tally (bytes; from each pack's section 7)

**A (legacy):** common(BOOT+shared) = listings 3,290 + START_HERE 5,423 + box 497 + git-log 2,901 + handoff
24,092 + CURRENT_STATE 34,319 + PROJECT_DIRECTION 10,756 = **81,278**. T-map = MODULE_ROADMAP 32,416 +
MEMORY_ARCHITECTURE 30,427 + ARCHITECTURE_MAP 16,496 = **79,339**. T-prose = AUDIT_PIPELINE 20,384 = **20,384**.
**A total = 181,001.**

**B (PCB):** common(BOOT+shared+traps grep) = listings/env/step-0 3,520 + BOOT_PACKET 17,265 + box/git 3,400 +
list core-docs/tree 1,800 + AAC-head+handoff-grep 7,800 = **33,785**. T-map = L1_CARDS_modules 31,487 +
L0_SYSTEM_MAP 7,786 + L1_CARDS_widgets 5,364 = **44,637**. T-prose = AUDIT_PIPELINE 20,384 = **20,384**.
**B total = 98,806.**

## The frozen bar: per-task TOTAL (boot amortized 50/50), B.total_t <= 0.7 x A.total_t

| task | A total_t (common/2 + task) | B total_t | 0.7 x A bar | B / A | verdict |
|---|---|---|---|---|---|
| **T-map** | 40,639 + 79,339 = **119,978** | 16,893 + 44,637 = **61,530** | 83,985 | **0.51x** | **PASS** |
| **T-prose** | 40,639 + 20,384 = **61,023** | 16,893 + 20,384 = **37,277** | 42,716 | **0.61x** | **PASS** |

**BOTH tasks PASS the TOTAL bar.** BOOT bar: B BOOT_PACKET 17,265 <= 20,000 + CD-1 canon present -> **PASS**.
VOID: NOT tripped (B's AUDIT_PIPELINE/AAC opens are task-material or PCB-cited-first corroboration -- the I51
clause reading). **All efficiency bars met on both tasks.**

## Cross-checks (reported, NOT gates) + the load-bearing finding

- **Combined total** (boot once): B 98,806 vs A 181,001; 0.7 x A = 126,701 -> **PASS (0.55x)**.
- **Retrieval-only (zero boot):** T-map A 79,339 / B 44,637 -> PASS (0.56x). **T-prose A 20,384 / B 20,384 ->
  TIE (1.00x), does NOT meet 0.7x.** The verdict is robust across every boot-allocation choice EXCEPT this
  zero-boot edge, which is a cross-check, not the frozen gate.
- **FINDING F-i53-eff (load-bearing):** on T-prose **B opened AUDIT_PIPELINE.md WHOLE (20,384 B)** -- it did
  NOT use the N5 `section:` fetches (the cadence-header/s5 sections that i52 proved serve at ~2.4-2.6 KB). So
  B's T-prose retrieval equals A's; B's per-task PASS leans ENTIRELY on the cheaper PCB boot (17 KB packet vs
  ~81 KB legacy boot), not on cheaper prose retrieval. N5 delivered the capability; this B agent did not exploit
  it. The T-map win, by contrast, is real query-granular retrieval (cards/L0 vs three whole prose docs).

## Comprehension notes (for the record; C1/C2 do the actual scoring)

- Both arms derived the SAME T-prose next unit (the raw-prompt FRONT step) with near-identical constraint sets
  -> comprehension parity on T-prose (a fourth consecutive parity across the gate's runs).
- On T-map, B's map-derived governance (contract:memory governs #35-39; #41/#42 doc-only) MATCHES the map edges;
  A's prose-derived answer (MEMORY_CONTRACT owns #35,36,38,39,41,42) diverges from the edges -- a case where the
  PCB's structured edges yielded the more precise answer. Both arms caught the (a) trap (the set {35-42,44} is
  all mvp-complete; #43 design-only sits OUTSIDE the set by construction).
- Note on the M3 key: the task set (35-42 + 44) EXCLUDES #43, so the fully-correct (a) answer is "none in the
  set; #43 is the design-only module, outside the set" -- both arms gave this; adjudication should credit it
  (the key's "#43" line is the out-of-set pointer, not an in-set gap).
