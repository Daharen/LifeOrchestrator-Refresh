# i46 PCB red-team RT-2 — i47 experiment validity (verbatim report)

**Reviewer:** independent in-session subagent (Opus, D-0119-permitted), 2026-08-11, blind to RT-1. **Subject:** the pre-freeze experiment plan (digest s7 draft) against directive s8-s12. **Disposition:** ALL findings folded into the frozen `eval/I47_EVAL_PACKET.md`; this file is the durable evidence record.

**F1 [critical] — Agent A's boot documents will describe the treatment.** The i46 close rewrites every doc A reads (handoff, CURRENT_STATE, roadmap, D-entries, the design digest); A learns it is in an experiment and what the treatment is, violating directive 8.A ("operate exactly as before i46"), and A's handoff would name the migration gate as the frontier, contradicting its task. Fix: run the eval against a detached worktree at the last PRE-i46 commit, where the mechanism physically does not exist and the handoff's frontier matches the test task; render B's packet against that same tree. FOLDED (packet s2).

**F2 [critical] — "same frozen repository state" asserted, never operationalized; the i47 mandate report mutates the live tree between dispatches.** Fix: `git worktree add --detach` at the pinned sha; step-1 self-check `git rev-parse HEAD` in every dispatch; the mandate report touches only the LIVE tree, which the agents never read. FOLDED (packet s2/s8).

**F3 [critical] — directive 6.6A's explicit i47 requirement dropped: B receives a static Markdown file and never exercises the deterministic construction/validation path.** As specified the experiment compares two prose documents. Fix: B's step 0 = validate -> render --check -> render at the pinned sha; envelope results recorded in B's pack; a refusal is a reportable outcome. FOLDED (packet s4-B).

**F4 [critical] — the task statement leaks the answer (it verbatim-restates AUDIT_PIPELINE next_increment, the decomposition agents should derive).** Fix: state only the neutral objective; deriving the increment from the governing doc's cadence header IS a scored comprehension item; add a secondary probe into an un-preloaded branch. FOLDED (packet s3).

**F5 [critical] — no ground truth for comprehension scoring; C's free repo reading is itself contaminating and unreproducible.** Fix: freeze an ANSWER KEY (load-bearing constraint checklist + checkable facts, each a verbatim quote + pointer); C opens ONLY key-named pointers; everything else marked unverifiable. FOLDED (packet s6).

**F6 [critical] — hard floors conditioned on A's single noisy sample; ">=2 on 0-4" nearly unreachable; n=1 has no variance estimate.** Fix: absolute scoring against the checklist (B missing any load-bearing constraint => at most CONDITIONAL, independent of A); relative rule tightened to >=1 on comprehension/constraint-adherence => at most CONDITIONAL; second pair recommended; single-run small gaps reported as no-established-difference. FOLDED (packet s7).

**F7 [major] — blindness broken three ways (hash-parity assignment computable by C; ledgers/boot-source names identify candidates; acceptance framing tells C which to favor).** Fix: out-of-band assignment held by Nicholas; REDACTED spec for C; boot-source tokens neutralized; C returns scores only, verdict applied by deterministic rule afterwards; partial blinding recorded honestly. FOLDED (packet s5/s6).

**F8 [major] — model/settings/grants/dispatch shape unpinned (per-dispatch human model choice; one-line vs packet-bearing prompts).** Fix: same model + settings both arms; byte-frozen dispatch files differing only in the boot-source block; model id echoed in output header; B's packet bytes counted as boot cost. FOLDED (packet s4).

**F9 [major] — the ledger instruction is an unbalanced instrument (suppresses B's retrieval; manufactures "discipline"); no pre-registered rule for B opening the legacy handoff.** Fix: identical neutral ledger wording both arms ("recording is measurement, not a limit"); pre-registered MECHANISM-NOT-EXERCISED rule (B opens legacy handoff, or B ingest > stated fraction of A's) voiding efficiency/bounded-boot claims while comprehension scoring proceeds. FOLDED (packet s4/s7).

**F10 [major] — efficiency scored with no measurer/instrument/threshold (tokens unavailable to agents).** Fix: artifact-computable proxies only (boot bytes; retrieved bytes = ledger file sizes at the pinned sha; open count; query count); one ledger schema; tokens/latency only if Nicholas exports; pre-registered bar (B total ingest <= 0.5x A = "materially smaller"). FOLDED (packet s7).

**F11 [major] — rubric anchors, aggregation, and any positive PASS definition absent (two mediocre packs could PASS by matching).** Fix: per-dimension 0/2/4 anchor sentences; every score cites a quoted span; positive PASS = no floor breach AND B absolute >=3 on comprehension + constraint adherence AND no >=2 gap in A's favor on load-bearing dimensions AND the efficiency bar for GO. FOLDED (packet s6/s7).

**F12 [major] — CONDITIONAL PASS unbounded; default mechanism during i48 undefined.** Fix: <=3 named deficiencies, each a single bounded unit with an acceptance test; legacy remains default until re-check passes; >3 = FAIL. FOLDED (packet s7).

**F13 [major] — the beneficiary packages the verdict; "frozen" has no integrity gate (no hashes for packet/dispatches/key/rubric).** Fix: eval/ MANIFEST.sha256 over every frozen artifact, verified as the i47 session's first action; C's verdict file delivered to Nicholas and committed byte-verbatim, hash quoted in the D-entry. FOLDED (packet s5/s8).

**F14 [major] — the mechanism's central claim (reliable expansion, stable identity/provenance) never directly tested; none of directive 6.5's questions asked.** Fix: fixed probe set (six 6.5-style questions answered with pointers) + three pre-registered trap items (P0-1 activation PROHIBITED; <=1 GPU / MaxParallel 3; verify-HEAD-via-native-git) in BOTH dispatches, mechanically scored against the key. FOLDED (packet s3/s6).

**F15 [major] — teach-to-the-test: the same seat authors the overlay and selects the eval task (directive 6.8 forbids the tested design designing its test).** Fix: overlay frontier = mechanically-derived verbatim extract of the boot-commit handoff s4 (derivation recorded); Nicholas selects the task at dispatch from >=3 pre-listed candidates; independent sign-off (this review + Nicholas ratification) before dispatch. FOLDED (packet s3/s5; WO 2.4).

**F16 [major] — the legacy procedure and the dry-run rule contradict (A's boot mandates writes/box checks the eval forbids), scored as a comprehension difference.** Fix: both dispatches enumerate identical suspended duties ("where the procedure requires a write, state what you would write"); box facts given as text; C instructed not to score suspended steps. FOLDED (packet s4).

**F17 [minor] — B's query path unspecified; executor round-trips would suppress B's retrieval.** Fix: pin `python3 modules/44-project-map/project_map.py ... --q ...` on the mount VM (proven pre-freeze: Python 3.10.12 verified live); per-query wall time in the ledger. FOLDED (packet s4-B).

**F18 [minor] — human-in-the-loop leakage unconstrained; no stop rule.** Fix: byte-identical frozen prompt files; only permitted reply "proceed per your dispatch and record the uncertainty"; other interventions void (one re-run, recorded); session-death = one re-run, reported. FOLDED (packet s5).

**F19 [minor] — output length uncontrolled; LLM judges reward length; biases toward the prose-fed control.** Fix: identical deliverable cap both arms (<=25,000 bytes, per-section caps); rubric states length is not evidence; quoted-span requirement. FOLDED (packet s4/s6).

**F20 [minor] — one adjudicator, one candidate order, no reliability estimate for a decision governing the whole bootstrap.** Fix: two independent C sessions with swapped order; >=2 disagreement on any dimension escalates to Nicholas; verdict unstable under swap = inconclusive, not PASS. FOLDED (packet s5).

**VERDICT: NEEDS-REWORK (blocking F1-F8, F11, F13, F15). DISPOSITION: all folded into the frozen packet (this freeze).**
