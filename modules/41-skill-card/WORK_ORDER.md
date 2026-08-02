# WORK_ORDER -- Module 41 skill.card (Wave 3 SKILL-CARD lane, plan fo-29-87dbfa0b, worker SKILL-CARD-i29)

## Goal

Build the Wave 3 **skill-activation substrate** (directive Priority 6 / section 9): a DETERMINISTIC
generator that turns each module's `skill.json` (+ README/WORK_ORDER) into a compact, model-facing SKILL
CARD; a searchable skill INDEX that emits `skill` record-envelope artifacts to `MEMORY_CONTRACT` s1 (for
#36 0.2 `ingest_records`); Stage-1 deterministic eligibility filtering; and a Stage-2 semantic-retrieval
SEAM (a deterministic lexical baseline). The half that lets the coordinator decide WHICH skill applies
without loading every command into the 9B.

## Scope IN (only `modules/41-skill-card/`)

1. **Skill card format + generator** (s9): deterministic; all section-9 fields; SURFACE missing fields;
   NEVER crash on a partial/malformed manifest (degraded card + warning); bounded card size.
2. **Skill index**: emit each card as a `skill` s1 record-envelope artifact; deterministic ids; idempotent;
   the `ingest_records.json` drop-in for #36 0.2; record the #38 boundary.
3. **Stage 1 -- deterministic eligibility filtering**: task descriptor -> eligible skills; pure rules.
4. **Stage 2 -- semantic-retrieval seam**: define the query shape; ship a deterministic lexical baseline
   over the card index (right candidates ranked; irrelevant excluded).
5. **Validator + provenance**: every record carries provenance + fingerprints + `sensitivity_class`; a
   validator against s1; canonical JSON artifacts in deterministic order.

## Non-goals (NOT built -- Priority 7 / other modules / later waves)

- The lightweight task **classifier** (Stage 3), the **9B preflight** (Stage 5), deterministic **plan
  validation** (Stage 6) -- Priority 7.
- The **procedure** schema / registry / promotion (Priority 6's procedure half -- a named follow-on;
  THIS unit is the SKILL-card half).
- **Real embeddings / semantic retrieval** (the retrieval wave -- a lexical baseline only here).
- The **catalog DB** (#36 owns storage -- skill.card EMITS records only).
- **repo.intel's structural parsing** (#38 -- skill.card consumes the boundary, not the work).
- The **context compiler** (#40), the reranker/eval (#37), any **UI**, strong-preflight integration.
- Do NOT touch model modules / `models.json`; do NOT edit any core-doc (`docs:[]`).

## Interfaces

- **Consumes:** the `SKILL_CONTRACT` manifest (`skill.json`) of every scanned module (+ optional sibling
  `README.md` / `WORK_ORDER.md`).
- **Produces:** `skill` s1 record-envelope artifacts (`records.jsonl` / `ingest_records.json`) to
  `MEMORY_CONTRACT` s1 -- the drop-in for **#36 artifact.search 0.2 `ingest_records`**.
- **Governing contract:** `core-docs/MEMORY_CONTRACT.md` s1 (the `skill` record envelope) + s5 (the status
  string) + s7 (privacy: `sensitivity_class`, no egress). On any conflict, that contract + its live gates win.

## Acceptance

- Compact cards for the FIXTURE skill set AND the real `modules/` corpus (bounded) with all section-9
  fields; missing fields surfaced; never crash on a partial/malformed manifest.
- `skill` records PASS the s1 validator AND are shaped to drop into #36 0.2 `ingest_records` (typed kind,
  `text|content_hash`, not `source_chunk`, `chunker_fingerprint` null); the #38 boundary recorded.
- Stage-1 eligibility DETERMINISTICALLY excludes the right skills (forbidden side-effect / unavailable
  dependency / GPU-unavailable / degraded).
- The Stage-2 lexical baseline returns the RIGHT candidate skills AND EXCLUDES irrelevant ones (a test that
  FAILS if an irrelevant skill surfaces).
- DETERMINISTIC re-run (identical cards/records/ids/order). `-Live` over the real `modules/` corpus.

## Gates (fail-closed)

OFF-MACHINE FIRST (cloud python, deterministic, CPU-only) THEN `-Live` on the Windows executor. `skill.json`
0.1.0 + README + WORK_ORDER + SCHEMA_NOTES to `SKILL_CONTRACT`. Double-run byte-identical. Ship via
`dev.ship` (sha256 + AST + tests fail-closed, named files only, under the `git` lease); VERIFY the real HEAD
via native `git`. Assert 0 UNMANAGED orphans + `review_queue.jsonl` before==after.

## Status

Shipped i29 (SKILL-CARD-i29). See `CURRENT_STATE.md` / `MODULE_ROADMAP.md` (orchestrator-mirrored) + this
module's report for the folded test counts.
