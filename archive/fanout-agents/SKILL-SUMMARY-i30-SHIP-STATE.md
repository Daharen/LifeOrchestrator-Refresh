# SKILL-SUMMARY-i30 -- SHIP-STATE (skill.card #41 0.1.0 -> 0.2.0)

**Worker:** FANOUT_AGENT_003 / SKILL-SUMMARY-i30 · **Plan:** fo-30-dd453156 (i30 CONTRACT-HARDENING) ·
**Lane:** CPU (GPU lane SKIPPED; no model, no network) · **docs:[]** (orchestrator mirrors core-docs).
**Commit:** `54c2e799` (parent `d4cfadc8`) · **State:** DONE.

## Mission (delivered)

Conform skill.card #41 to `MEMORY_CONTRACT` **Amendment A3** (D-0087; frontier Wave-3 red-team P0-5): the
card is now emitted as `record_kind = summary` (a skill-ACTIVATION card that DERIVES FROM #38's structural
`skill` record), **NOT** a second `record_kind = skill`. So **repo.intel #38 is the SOLE `record_kind = skill`
producer** and a `record_kind = skill` search returns ONE owner. A MINIMAL, ENVELOPE-level change: the card
payload, Stage-1 eligibility, and Stage-2 lexical scoring are UNCHANGED.

## What changed (envelope only; `modules/41-skill-card/`)

1. **record_kind `skill` -> `summary`** (`EMITTED_KIND`), plus **`attrs.summary_type = "skill_activation_card"`**
   added to the record envelope (NOT in `payload`, so it does not feed `content_hash`).
2. **`describes_structural_skill` child_edge FULLY REPLACED by a `derives_from` external edge** to #38's
   recomputed `skl_` id (byte-identical `external_ref`; a navigational derivative per A3). Decision: replace,
   not augment -- one boundary edge, edge_count stable. No `describes_structural_skill` remains.
3. **Validator (s1 + A3):** for skill.card's OWN records (schema_version `lifeorch.skill_card.record/0.1`) it
   now REQUIRES `record_kind == summary` AND `attrs.summary_type == skill_activation_card` -- so a record
   forced back to `skill` or stripped of `summary_type` is REJECTED. Gated by schema, so a FOREIGN `summary`
   record (e.g. #38's structural summaries) is never falsely rejected.
4. **`extractor_fingerprint` bumped** `skill.card.cardgen/0.1;section9` -> `.../0.2;section9;summary-activation`
   (s4: a derivation-version change; envelope field, does not alter `content_hash`/ids).
5. **Stage-2 semantic seam filter** updated to `record_kind=summary` + `summary_type=skill_activation_card`
   (both `semantic_query_shape` and `artifact_search_call`) -- otherwise the seam would retrieve #38's
   STRUCTURAL records, not the cards. The lexical SCORING/ranking behaviour is byte-identical (untouched).
6. `skill.json` 0.1.0 -> **0.2.0**; `Invoke-SkillCard.ps1` `$SKILL_VERSION` -> 0.2.0; `WORKER_VERSION` -> 0.2.0;
   README / WORK_ORDER / SCHEMA_NOTES / examples updated to contract; `example-result.json` regenerated.

## Stability invariant (verified)

`content_hash = _h(canon(payload))` is UNCHANGED (payload/card byte-identical), so **`record_id` +
`record_version_id` stay STABLE** across the flip. Off-machine proof over the fixture set:
`cards_digest` **byte-identical** to 0.1.0 (`5d0187de...`); `records_digest` **changed** (`abfcbc6a...` ->
`124d4391...`) reflecting the envelope-kind change. Sample `fixture.gen.image`: `record_id`
`sklcard_6e5fdd00c66756a89dba3453`, `record_version_id` `rv_351579441da72a5fb09b2891` -- both unchanged;
`derives_from` external_ref `skl_6e5fdd00c66756a89dba3453` (unchanged, joinable suffix).

## Acceptance / gates (all PASS)

- Off-machine (cloud python3): **81/81** `tests/test_skill_card.py` (was 72; +9 A3 assertions), incl. real
  modules/ slice; **double-run byte-identical** for all canonical artifacts.
- `-Live` (Windows executor): **85/85** `tests/Invoke-SkillCardTests.ps1` (was 80; +5 A3 assertions), incl.
  the real modules/ corpus.
- dev.ship: **sha256 19/19 OK, AST 2/2 OK, tests 85/85 pass, committed `54c2e799`** under the `git` lease
  (holder SKILL-SUMMARY-i30, acquired+released); **orphans llama-server=0 / python=0**.
- Native-git HEAD verify (D-0072, not the dev.ship `committed` field): HEAD `54c2e799`, 10 files, both
  trailers present; **review_queue.jsonl sha UNCHANGED** (`e8288032...` before==after).
- Tests prove: NO emitted #41 record is `record_kind=skill`; a `record_kind=skill` query over the combined
  corpus (#41 summaries + a synthetic #38 `skl_`) returns ONLY #38; ingest_records.json still drops into #36
  0.2 (shape + attrs preserved).

## Decisions / notes for the fold

- **Fully replaced** (not aliased) `describes_structural_skill` -> `derives_from`; documented in SCHEMA_NOTES §3.
- **A2 provenance-name split NOT adopted** this wave: work-order SCOPE IN is kind+edge+summary_type+validator
  and `content_hash` is kept UNCHANGED; per A2's backward-compat aliasing, legacy `content_hash` reads as
  `source_content_hash`. Full A2 name split for the card record is a follow-on (out of this wave's minimal scope).
- **Kind flip vs #36 re-ingest:** same `record_version_id` + unchanged `content_hash` means #36's
  content-idempotency treats a pre-existing 0.1 `skill`-kind row as a no-op and may not rewrite the stored
  `record_kind`. The orchestrator folds on a FRESH #36 catalog (D-0077), so the `summary` kind stores cleanly;
  no live envelope migration is needed this wave. (Recorded in SCHEMA_NOTES §8.)
- **P1-6 DEFERRED** (named follow-on, NOT this wave): richer card fields (applicability / effect_set /
  risk_class / required_permission_scopes / rollback / sandbox_class / health_ref / ...), three-valued Stage-1
  (`eligible|ineligible|indeterminate`), and degraded-card fail-closed.

## Residuals

None blocking. schema_version wire id kept at `lifeorch.skill_card.record/0.1` (A3 changes only valid s1
envelope values; no new wire id needed). Orchestrator report recorded at
`plans/fo-30-dd453156/reports/SKILL-SUMMARY-i30.*.json`.
