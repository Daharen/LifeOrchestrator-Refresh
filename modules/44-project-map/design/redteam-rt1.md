# i46 PCB red-team RT-1 — mechanism drift / failure modes / doctrine (verbatim report)

**Reviewer:** independent in-session subagent (Opus, D-0119-permitted), 2026-08-11, blind to RT-2. **Subject:** the pre-freeze `2026-08-11-i46-pcb-design.md` + `WORK_ORDER.md` drafts. **Disposition:** ALL findings folded into the frozen WORK_ORDER/digest (see digest s8); this file is the durable evidence record.

**F1 [critical] — digest busts the 10 KB research budget (11,064 B), blocking the wave's own authority commit.** Fix: slim below 10,000 B before dispatch. FOLDED (digest rewritten; CRLF-equivalent ~9.9 KB).

**F2 [critical] — overlay<->PROCESS_MANDATE equality cross-check guarantees hard validation failure one iteration after every fold (i47's first mandatory act updates the countdown).** Fix: cross-check invariant fields only (mandate_id, sunset_iteration, state monotonic), require header.current_iteration >= overlay.iteration. FOLDED (WO 2.4).

**F3 [critical] — `arch:` kebab-slug key rule contradicts the harvest source (spine lines carry dotted ids for 0-26 and bare prose for 27-49); every `realizes` edge would dangle; `00.1` ungrammatical.** Fix: number-only `arch:NN`/`NN.N` keys; prose to display_name/aliases. FOLDED (WO 2.1).

**F4 [critical] — bespoke envelope + nonzero logical exits violate SKILL_CONTRACT v0.2 (refusals must be exit-0 `status:"error"` envelopes); `parallel_safe:true` false for writers; `examples/` missing.** Fix: v0.2 envelope, in-band refusal codes, parallel_safe:false, examples/. FOLDED (WO 0/3.9/5).

**F5 [critical] — source hashing undefined wrt line endings; CRLF box vs LF cloud marks everything stale, discovered at fold.** Fix: hash CRLF->LF-normalized bytes, normative; equivalence fixture. FOLDED (WO 0).

**F6 [critical] — claims format specified three incompatible ways (sources shapes; entities array-vs-object); Lane A validator would reject Lane B's file wholesale at fold.** Fix: one pinned sources shape; ingest stamps sha256; normative fixture #0 embedded. FOLDED (WO 2.2/2.5).

**F7 [critical] — ingest non-idempotent (append edges + DUP_EDGE) while the fold loop re-ingests; last-writer-wins field merge contradicts conflict detection; no multi-file atomicity.** Fix: idempotent upsert; DUP_EDGE intra-file only; same-claimant field replace else conflict/--override recorded; staged-tree validate + atomic swap. FOLDED (WO 3.3).

**F8 [critical] — per-entity whole-file staleness cries wolf (any CURRENT_STATE edit refuses the packet), no re-affirm path, provenance not per-assertion (6.6A).** Fix: per-FIELD source coverage + per-field staleness; gate on stale load-bearing FIELDS; `reaffirm` op as a recorded judgment event. FOLDED (WO 2.2/3.2/3.7).

**F9 [critical] — nothing detects MISSING entities (new module never enters the map; packet silently omits it) — fail-open in a fail-closed design; the exact false-confidence hole the directive hunts.** Fix: HARVEST_ORPHAN + ENTITY_UNBACKED hard errors. FOLDED (WO 3.2).

**F10 [major] — six directive-6.2 card fields absent (inputs/outputs/state ownership/side-effects/authority level/audit surfaces); manifest facts left unharvested; `persists`/`retrieves-from` have no legal target (no store ns); plane encoded twice (field + edges); "name first sentence" wrong (purpose is the sentence).** Fix: harvest manifest fields; add claim fields state_owned/authority_level/audit_surfaces; `store:` ns; member-of DERIVED; purpose-first-sentence. FOLDED (WO 2.1/2.2/2.3/3.1).

**F11 [major] — fold ordering ships a stale-on-arrival map (close edits core-docs AFTER the map commit); -Live suite expectation wall-clock-dependent; head_expected dead field.** Fix: map+generated = FINAL close commit; `-RepoState Skeleton|Folded` test parameter; head_expected dropped. FOLDED (WO 6.8/9).

**F12 [major] — render never receives harvest, so map-vs-reality conflict/coverage checks are off exactly when the packet is produced.** Fix: render requires --harvest; --no-harvest fixture-only. FOLDED (WO 3.4).

**F13 [major] — `--draft` writes into git-tracked generated/; Lane A instructed to ship a draft packet; committed DRAFT-STALE bytes readable as real.** Fix: drafts under runtime/ only; banner-in-generated = failure; generated/ ships EMPTY; golden renders under fixtures/. FOLDED (WO 1/3.4/6.4/7).

**F14 [major] — `skeleton:true` has no render-time gate and unplaced entities vanish from a plane-grouped index.** Fix: SKELETON_UNRESOLVED on non-draft render; skeleton cannot be load-bearing; UNPLACED group renders. FOLDED (WO 3.2/3.4/4).

**F15 [major] — overlay is prose duplicating CURRENT_STATE with existence-only pointer checks; a lifted prohibition keeps asserting itself; `load_bearing` claim-settable makes the stale gate vacuous.** Fix: derive load_bearing deterministically; prohibitions' authority = decision: entity with supersedes-edge check; overlay text as pointer captions; frontier = verbatim handoff-s4 extract. FOLDED (WO 2.2/2.4).

**F16 [major] — 20 KB packet likely infeasible vs its own content contract; no degradation ladder; doctrine one-liners are unprovenanced renderer literals; KB=1024-vs-1000 ambiguity.** Fix: per-section budgets; truncation ladder (96->72->56; collapse deprecated) recorded in envelope; doctrine lines = meta entities with sources; KB=1000. FOLDED (WO 0/4).

**F17 [major] — array ordering never mandated (`sort_keys` orders dict keys only) — the #33 Array.Sort class of bug; same-machine double-run cannot detect it; canonical JSON form left undecided.** Fix: explicit sorted() per array with stated keys; shuffle-fixture test; pinned forms (indent=1 map/claims, compact runtime); fmt --check. FOLDED (WO 0/3.8/6.2).

**F18 [major] — `--at-commit` is trusted input nothing verifies; at fold the stamped sha describes a tree that never existed.** Fix: entrypoint captures rev-parse + porcelain; dirty computed EXCLUDING modules/44 own outputs; non-draft render refuses DIRTY_TREE. FOLDED (WO 0/3.4).

**F19 [major] — WORK_ORDER is the lanes' only real spec but nothing freezes/commits it or records which bytes each lane built against; nine named ambiguous clauses.** Fix: pre-wave FROZEN commit; sha256 in both briefs; lanes report the sha; every named clause resolved (arch keys, sources shape, entities array, purpose-sentence, pinned JSON, parse_budgets IMPORT, edge-count warning semantics, exit-code table). FOLDED (WO throughout; freeze commit in the wave procedure).

**F20 [major] — no owner/cadence for judgment-field refresh; non-load-bearing staleness accumulates as unbudgeted warnings (the mandate-01 monitor lesson); `deeper[]` raw paths dangle on archive moves.** Fix: STALE_BUDGET (>20% any-field-stale refuses); fold checklist reaffirm-or-defer duty; deeper prefers doc: ids. FOLDED (WO 2.2/3.2; close checklist).

**F21 [major] — Agent B's query interface may not be executable in i47 (fresh session vs executor pwsh), collapsing progressive disclosure to a static file; two directive-6.5 questions unanswerable (changed-recently; failures).** Fix: pin `python3 modules/44-project-map/project_map.py` on the mount VM (verified live: Python 3.10 present); `changed-since --paths-file` op added; failures routed via typed deeper kind `failure`. FOLDED (WO 3.6; eval packet).

**F22 [minor] — `deeper[]` untyped, so the L2 layer cannot be filtered ("what contract governs this?" forces opening everything).** Fix: `{kind, ref}` closed kind enum + kind filter on the query. FOLDED (WO 2.2/3.6).

**F23 [minor] — the packet strips uncertainty/staleness markers the i47 rubric scores (Lane B guesses read as authoritative).** Fix: `?`/`~` index suffixes + summary line. FOLDED (WO 4).

**F24 [minor] — generated views are durable orchestrator-consumed docs no owner table governs; owner-table parse contract unstated; parse_budgets parity test vacuous against live-doc-only.** Fix: DOC_PROTOCOL s2 owner rows for map//generated/ at close; PARSE_ROW_FAILED hard error; synthetic fixture-table parity tests. FOLDED (WO 3.1/6.5; close checklist).

**VERDICT: NEEDS-REWORK — blocking F1-F19 pre-dispatch; F11/F20 pre-fold; F21 pre-i47; F22-F24 same rewrite. DISPOSITION: all folded pre-dispatch (this freeze).**
