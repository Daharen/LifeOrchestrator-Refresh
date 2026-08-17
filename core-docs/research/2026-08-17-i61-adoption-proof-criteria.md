# i61 bounded-ingest ADOPTION proof -- FROZEN threshold + acceptance criteria (F-i53-eff)

Authored 2026-08-17, at the corrected i60-close HEAD, BEFORE the fresh-context trial is run or judged
(Phase 2 item 4: "freeze the meaningful bounded-fraction threshold and the acceptance criteria before
judging the result"). Nothing below may be softened after the trial; a failing trial leaves F-i53-eff OPEN
and records the measured failure (Phase 2 item 6 / close requirement).

## The measurement problem the threshold must avoid

The standing monitor (`ops/audit/gen-retrieval-monitor.py`) computes
`bounded_fraction = bounded_query_bytes / total_charged_bytes`, where
`total_charged_bytes = boot_packet_bytes + whole_doc_open_bytes + bounded_query_bytes`.
The BOOT_PACKET (~18 KB) is the MANDATORY, SANCTIONED bounded bootstrap -- it is the bounded surface, not a
whole-doc open. Counting it in the denominator of an adoption metric penalises a perfectly-bounded session
for booting correctly, so a raw `bounded_fraction >= 0.5` bar can be failed by a genuinely bounded session as
a fixed-cost artifact rather than a real adoption failure. The adoption question is narrower and cleaner:

  Of the DISCRETIONARY retrieval a session chose (everything BEYOND the mandatory boot packet),
  what fraction was bounded (section:/card:/query) rather than whole_doc_open?

## Frozen metric (added to the monitor row, additive)

`discretionary_bounded_fraction = bounded_query_bytes / (bounded_query_bytes + whole_doc_open_bytes)`
(null when the denominator is 0 -- i.e. the session did no discretionary retrieval at all).

This excludes `boot_packet` from both numerator and denominator, so the fixed boot cost cannot distort it.
Whole-doc-heavy orchestrator baseline for calibration: i60 orchestrator session bounded_fraction 0.027;
its discretionary_bounded_fraction is ~0.05 (bounded 2946 B vs whole-doc ~55 KB) -- clearly NOT adopted.

## Frozen threshold

theta = 0.80  (>= 80% of DISCRETIONARY retrieval bytes went through the bounded affordance).

"Meaningful fraction" = bounded retrieval is the DOMINANT discretionary mode by a wide margin, an order of
magnitude above the whole-doc-heavy baseline. 0.80 is a by-default bar, not a token-gesture floor.

## Frozen acceptance criteria for closing F-i53-eff (ALL must hold on the genuine trial)

1. GATE PASS on the trial ledger at close, enforcing BOTH:
   (a) zero-bounded floor: bounded_query_bytes > 0 (the i60 floor); and
   (b) meaningful fraction: discretionary_bounded_fraction is non-null AND >= theta (0.80).
2. n_queries >= 5 -- a non-trivial number of genuine bounded queries spanning the frozen task set
   (guards against a degenerate 1-tiny-query, 0-whole-doc "100%" pass).
3. ZERO whole_doc_open entries that were AVOIDABLE: any whole_doc_open in the trial ledger must carry an
   explicit recorded reason (RETRIEVAL PROTOCOL). The trial is designed so representative orientation +
   planning + technical-retrieval tasks are answerable from the boot packet + bounded queries alone.
4. EVIDENCE BINDING (not query-string matching): the trial ledger + monitor row bind to the exact
   session identity, iteration (60 -- the corrected-HEAD epoch), git HEAD SHA (the corrected Phase-1 HEAD),
   ledger path, and the persisted project.map query-artifact set. Monitor `--artifacts-dir` cross-check
   reports unbacked = 0 (every bounded ledger target is backed by a real persisted query artifact).
5. The trial COMPLETES the frozen representative tasks using only {boot packet + bounded queries} -- i.e.
   bounded-by-default was SUFFICIENT to orient, plan, and retrieve technical detail (adoption is not
   crippling), demonstrated in the fresh context's own report.

## The frozen representative task set (fixed before the trial boots)

Q1 (orientation): current iteration, next iteration, and the one-line frontier -- from the boot packet.
Q2 (orientation): the live PINNED prohibition on P0-1 / action.authz activation -- bounded fetch.
Q3 (planning): the open PROCESS_BACKLOG rows and which is the i61 driver -- bounded fetch.
Q4 (technical): project.map (#44) current version + one narrative-query verb form -- bounded fetch.
Q5 (technical): the retrieval-gate state (wired? floor vs fraction) -- from packet overlay + bounded fetch.
Q6 (technical): one section-level fact from a large core-doc (e.g. AUDIT_PIPELINE cadence) via section: --
   the case that would otherwise be a whole-doc open, proving the bounded path replaces it.

## Enforcement wiring

- `ops/audit/gen-retrieval-monitor.py` gains `--min-bounded-fraction <theta>` (gates
  discretionary_bounded_fraction; additive -- default off preserves the i55/i60 row + tests byte-identical).
- `ops/close-refold.ps1 -Mode fold` runs the gate FAIL-CLOSED and, for the i61 close, passes
  `-MinBoundedFraction 0.80` against the genuine TRIAL ledger. The whole-doc-heavy orchestrator/cleanup
  session's own close remains at the zero-bounded floor (the raise judges the ADOPTION trial evidence, not
  the cleanup session).
