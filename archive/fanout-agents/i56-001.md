# FANOUT_AGENT_001 -- PB-6 decision-record PRODUCER (#45 decision.intel) -- READY

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i56 (plan id `fo-56-<id>` once planned)
- **Lane:** CPU / CODING lane A (no GPU)
- **Worker id / label:** `DEC-PRODUCER-i56`
- **Module/area (exclusive):** `modules/45-decision-intel/` (BRAND-NEW module -- you create it). READ-ONLY everywhere else. You do NOT write `modules/36-*` (its ingest is orchestrator-run at fold), `modules/40-*` (lane B), any core-doc, `map/`, or `generated/`.
- **GPU:** false
- **Docs:** `[]` (you report; the orchestrator mirrors core-docs)
- **Recommended model:** Sonnet 5 High (D-0114 default lane: exact-spec'd against a frozen contract + suite-gated fail-closed + a reference producer to mirror; not ratification-critical)

## Mission

Build the first PB-7 increment's PRODUCER (D-0141/PB-6, design `research/2026-08-14-pb7-relayer-design-2.md` s7): a deterministic, `#38 repo.intel`-shaped producer that turns the append-only `DECISION_LOG.md` (~640 KB) + `DECISION_LOG_INDEX.md` rows into typed `record_kind=decision` record artifacts, so the decision surface becomes losslessly-backed + typed-indexed + cold-retrievable while the hot boot surface stays bounded. You EMIT + VALIDATE record artifacts; **#36 owns catalog storage -- the orchestrator feeds your artifacts into #36 `ingest_records` at fold** (the built #38->#36 D-0077 pattern). This is lane A of a producer/consumer pair; lane B (`modules/40` verb) consumes your record schema, so conform EXACTLY to the frozen contract.

## Unit (ONE scoped module; build + ship `modules/45-decision-intel/`)

**READ FIRST, in order:** `core-docs/research/2026-08-14-pb6-decision-record-schema.md` (THE FROZEN CONTRACT you build to -- envelope conformance, the typed field table, deterministic derivation rules, edge kinds, the s8 hardened predicate), then `research/2026-08-14-pb7-relayer-design.md` s2/s3 + `-2.md` s7/s8, then `modules/38-repo-intel/SCHEMA_NOTES.md` + `repo_intel.py` (the producer archetype you mirror -- determinism contract, ids, `records_digest`, canonical JSON, byte spans), `modules/36-artifact-search/SCHEMA_NOTES.md` s1/s4 (the record + provenance envelope + `record_edges` + `ingest_records` input shape), `MEMORY_CONTRACT.md` s1, `SKILL_CONTRACT.md` (v0.2 envelope).

**BUILD `modules/45-decision-intel/` (`decision.intel` 0.1.0):**
- `decision_intel.py` (Python **stdlib only**: `json,hashlib,re,os` -- NO third-party; CPU-only, no model, no network) that parses `DECISION_LOG.md` + `DECISION_LOG_INDEX.md` and emits, per the frozen contract: `records.jsonl`, `records.json`, `ingest_records.json`, `index_manifest.json`, `summary.md` -- MEMORY_CONTRACT s1 envelopes with `record_kind="decision"`, `namespace="decisions"`, `record_id="dec_<NNNN>"`, the full typed field set (title/date/iteration/affected_modules/planes/type/authority/**binding_scope**/**enforced_by**/**ingested_through**/source_span; `synopsis` RESERVED null) and `record_edges` (`supersedes`/`superseded_by` ONLY on an explicit total-replacement marker; else `partially_superseded_by`; `derives_from`).
- Deterministic marker rules (document EVERY regex in SCHEMA_NOTES): `binding_scope` from FROZEN/prohibited -> `standing_prohibition`, never/always/inviolable/HARD -> `invariant`, else `ordinary`; `enforced_by=<gate-id>` when the entry binds a deterministic gate (doc-commit-gate / dev.ship AST / lease wrapper / a monitor) else `none`; `ingested_through` = the `DECISION_LOG.md` HEAD sha for the run (identical across all records; sourced deterministically -- NO git in the worker, take it from an input param the orchestrator/harness supplies, mirroring #38's no-git rule).
- **Determinism (HARD):** identical inputs => byte-identical canonical artifacts across runs + machines (double-run byte-identity gate, cloud + -Live); all ids content+path derived; canonical JSON `sort_keys+ensure_ascii+separators=(",",":")`; BYTE spans over raw bytes (core-docs are CRLF -- EOL-faithful); NO absolute paths/timestamps/random in any canonical artifact; `records_digest` per the contract.
- **Coverage validation:** assert every `DECISION_LOG_INDEX.md` routing row has a corresponding emitted record and every record's `source_span` resolves to its canonical `DECISION_LOG.md` entry; emit a `coverage.json` (missing/extra lists must be empty to pass).
- `Invoke-DecisionIntel.ps1` (pwsh-file entrypoint; SKILL_CONTRACT v0.2 result envelope to stdout, diagnostics to stderr), `skill.json` (`decision.intel` 0.1.0), `SCHEMA_NOTES.md` (records EVERY schema/marker interpretation -- this is the per-module D-0077 record), `README.md`, `WORK_ORDER.md`.

## Rails (standing)
- Boot from the PCB `modules/44-project-map/generated/BOOT_PACKET.md` (step-0 verify / query stale); read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease in **git** order (no GPU, no doc); release on exit. Do ONE unit; `docs:[]`; touch ONLY `modules/45-decision-intel/**`.
- Gate off-machine (cloud pwsh/python) FIRST, then `-Live` on the executor, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, NAMED FILES ONLY under `modules/45-decision-intel/**`; trailers); **VERIFY the real HEAD via native git** (D-0072), never the dev.ship `committed` field; assert 0 UNMANAGED orphans.
- Watch the gotchas: pwsh 7.4.6 determinism traps (empty-array unroll; `[Array]::Sort` copy; `@($list)` on List[object]; `$var:`->`${var}`); a worker session may lack pwsh/executor (leave the ship to the orchestrator -- that is DONE-minus-ship, not failure); stage FRESH paths only.

## Verification / report-back
- Suite green cloud + `-Live` (double-run byte-identity + shuffle determinism over ALL canonical artifacts; coverage empty-diff; every typed field + edge kind fixture-asserted incl. a `standing_prohibition` case, an `enforced_by=<gate>` case, and a `partially_superseded_by` default case).
- Report (`-Action report -PlanId <plan> -WorkerId DEC-PRODUCER-i56 -State done` + a plain measured summary): record count vs index-row count (coverage diff = 0); the `records_digest`; byte-identity proof; the marker-rule table; any decision entry your rules could not classify deterministically (flag honestly -- an honest INCOMPLETE beats a false done, D-0107/D-0109). Do NOT ingest into the real `#36` -- the orchestrator runs `ingest_records` + the D-0077 seam smoke at fold.
- Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving): _empty._
