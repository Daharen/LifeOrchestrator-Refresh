# Module 41 -- skill.card

Deterministic **skill-card generator + skill index + Stage-1 eligibility + Stage-2 lexical-retrieval seam**
-- the Collective Agent's **skill-ACTIVATION substrate** (D-0080 Wave 3; directive Priority 6 / section 9
"Skill card format"). It lets the deterministic coordinator decide WHICH skill applies to a task without
loading every module's full command surface into the 9B.

CPU-only, **stdlib-only Python worker** (`skill_card.py`), no model, no network -> `determinism=deterministic`,
`confidence=null`, empty `model_provenance`. Entrypoint: `Invoke-SkillCard.ps1` (pwsh-file).

## What it does

1. **Skill card generator** (directive s9). Reads each module's `skill.json` (+ sibling `README.md` /
   `WORK_ORDER.md`) and emits a COMPACT, model-facing card carrying every section-9 field: purpose,
   supported operations, typed inputs, one valid example, preconditions, side effects, artifacts,
   latency/resource class, deterministic completion checks, common failure/refusal conditions, and
   version + health. It **NEVER crashes on a malformed/partial manifest** -- it SURFACES the missing
   fields and emits a degraded card + a warning. Cards are bounded (the compact view, not the full docs).

2. **Skill index** (Priority 6 / 6.1; Amendment A3, D-0087). Emits each card as a `MEMORY_CONTRACT` s1
   `summary` skill-activation **record-envelope artifact** (`attrs.summary_type=skill_activation_card`;
   deterministic ids, idempotent) -- a drop-in for **#36 artifact.search 0.2 `ingest_records`**. PRODUCER of
   `summary` activation records that **DERIVE FROM** repo.intel #38's structural `skill` record via a
   `derives_from` edge, so **#38 stays the SOLE `record_kind=skill` owner** and a `record_kind=skill` search
   returns ONE owner (the #38 boundary: distinct id namespace `sklcard_` + `authority_level=derived`).

3. **Stage 1 -- deterministic eligibility filtering** (s9 Stage 1). Given a task descriptor, deterministically
   filters the card set to ELIGIBLE skills, excluding forbidden side-effects / ungranted permissions /
   unavailable dependencies / degraded health / GPU-unavailable / OS mismatch / non-parallel-safe.

4. **Stage 2 -- semantic-retrieval seam** (s9 Stage 2). Ships a DETERMINISTIC lexical baseline over the card
   index: a task-intent query returns ranked candidate skills and EXCLUDES irrelevant ones. Defines the
   semantic query shape + the `#36 search` call that real embeddings fold into at the retrieval wave.

## Ops

| op | what |
|---|---|
| `cards` (default) | scan roots -> cards + s1 records + `ingest_records.json` drop-in + validation |
| `eligible` | Stage-1 eligibility filter of the card set under a `task` descriptor |
| `retrieve` | Stage-2 lexical ranking of candidate skills for a `query` (+ the semantic seam) |
| `validate` | check a records artifact against `MEMORY_CONTRACT` s1 |

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Roots ..\..\modules -Namespace life-orchestrator
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op eligible -Roots ..\..\modules -TaskJson '{"gpu_available":false}'
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op retrieve -Roots ..\..\modules -Query "transcribe audio to text"
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op validate -RecordsPath <records.jsonl>
```

Or generically: `-InputsJson '{"op":"cards","root":"...","namespace":"..."}'` (named params override JSON keys).
See `examples/example-invocation.md`.

## Determinism

All ids are content+path derived; canonical artifacts (`cards.json/jsonl`, `records.json/jsonl`,
`ingest_records.json`, `index_manifest.json`, `summary.md`) contain NO absolute paths, timestamps, or
wall-clock ids -> **identical corpus content yields byte-identical artifacts across runs AND machines**
(the double-run byte-identity gate covers it, off-machine and `-Live`).

## Tests

- `tests/test_skill_card.py` -- off-machine, stdlib-only (drives `skill_card.py` directly): section-9 fields,
  degraded/partial surfacing, s1 validator + id-integrity + tamper, ingest_records shape, the #38 boundary,
  Stage-1 exclusions, Stage-2 discrimination, double-run byte-identity, bounded real slice.
- `tests/Invoke-SkillCardTests.ps1` -- the real-worker gate (cloud pre-ship AND `-Live`): additionally proves
  the entrypoint + the `lifeorch.skill.result/0.1` envelope + the Module 1 generic wrapper.

Interpretations for the D-0077 fold are recorded in `SCHEMA_NOTES.md`. Boundaries + non-goals: `WORK_ORDER.md`.
