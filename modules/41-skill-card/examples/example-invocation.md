# skill.card -- example invocations

`skill.card` turns each module's `skill.json` (+ sibling README/WORK_ORDER) into a compact, model-facing
SKILL CARD, emits each card as a MEMORY_CONTRACT s1 `summary` skill-activation record (A3, D-0087 -- it
DERIVES FROM #38's structural `skill` record; a drop-in for #36 0.2 `ingest_records`), and ships Stage-1
eligibility filtering + a Stage-2 lexical retrieval baseline over the card index.

## Generate cards + the skill index over the real modules corpus

```powershell
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Roots ..\..\modules -Namespace life-orchestrator
```

Writes `cards.json` / `cards.jsonl` (the compact cards), `records.jsonl` / `records.json` (the s1 `summary`
skill-activation records), `ingest_records.json` (the #36 0.2 `ingest_records` drop-in), `index_manifest.json`, and
`summary.md` to the invocation artifact dir. Deterministic: identical corpus content -> byte-identical
artifacts across runs and machines.

## Stage 1 -- deterministic eligibility filtering

```powershell
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op eligible -Roots ..\..\modules `
     -TaskJson '{"gpu_available":false,"allow_side_effects":false}'
```

Returns `eligible[skill_id]` + `excluded[{skill_id,reasons[]}]`. GPU-required skills are excluded when no
GPU is available; side-effecting skills are excluded when side effects are forbidden.

## Stage 2 -- lexical retrieval of candidate skills (the semantic-retrieval seam)

```powershell
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op retrieve -Roots ..\..\modules `
     -Query "transcribe speech audio to text" -K 5
```

Returns the ranked candidate skills for the task intent (and excludes irrelevant skills). Add `-TaskJson`
to pre-filter the pool by Stage-1 eligibility before ranking. The `result.seam` documents the semantic query
shape and the `#36 search` call that real embeddings fold into at the retrieval wave.

## Validate an emitted records artifact against MEMORY_CONTRACT s1

```powershell
pwsh -NoProfile -File .\Invoke-SkillCard.ps1 -Op validate -RecordsPath .\runtime\artifacts\<id>\records.jsonl
```
