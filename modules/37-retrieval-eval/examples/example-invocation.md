# retrieval.eval -- example invocations

## 1. The shipped 0.1 lexical baseline (regression-green)

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json
```

Runs BM25-lite over `tests/fixtures/corpus/` against `benchmark.json` (7 queries). Known aggregate:
recall@K 857143 ppm, MRR 857143, stale-source rate 142857, forbidden-hit rate 142857, provenance
completeness 1000000, provenance validity 964286 (validation flags the archived stale copy's `current`
status), precision@1 857143, nDCG@5 857143.

## 2. The eval-0.2 lexical benchmark (evidence groups, temporal intent, privacy, no-answer, duplicates)

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark2.json
```

Exercises: must_include_all / must_include_any evidence groups; temporal intent (current_only /
version_specific); a forbidden + hard-privacy personal source that is the best lexical match; no-answer
(a clean abstain and a false positive); near-duplicate burden + source diversity; chunk-level credit
(the right file appears but the required chunk is only credited by K=5).

## 3. An external retriever-0.2 (the fold seam) -- provenance validation + reranker A/B

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\mock2-benchmark.json
```

`mock-retriever.py` replays canned retriever-0.2 hits from `mock2-plan.json` (span objects + per-channel
diagnostics + status enums), validated against `corpus2/`. It drives: a required-absent miss; a forbidden
source returned; a hit whose span does NOT reproduce the cited text (provenance INVALID even though it
matched); and the DETERMINISTIC reranker rescuing a current required source to rank 1 while demoting a
forbidden/stale hit (A/B delta: recall@1 / nDCG@1 uplift +500000 ppm). `examples/example-result.json` is a
sanitized envelope from this run.

## 4. The eval-0.3 selpol packet benchmark (occurrence dedup, budget, packet_disposition)

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark3.json
```

Exercises the `selpol_rrf_v1` PACKET stage (`lib/selpol_rrf_v1.py`; CONTEXT_PACKET_CONTRACT s4): two
byte-identical near-duplicates collapse to ONE display item carrying both `occurrences[]` + an
`evidence_cluster_id` (provenance preserved -> packet duplicate burden 0); a `max_selected=1` budget drops the
required chunk into the `omission_manifest` -> `needs_expansion`; and `packet_disposition` scoring against
`expected_packet_disposition` labels (accuracy 833333 ppm = 5/6, catching a supplied #40 packet that wrongly
claims `answerable` for an absent required source). The report (`lifeorch.retrieval_eval_report/0.3`) adds
`selection_policy`, `stage_metrics` (raw / post_filter / packet), `aggregate_packet`, `packet_disposition_eval`,
`hybrid_applicability`, and the additive per-hit selection fields (`retrieval_rank` preserved +
`selection_rank`/`selection_score`/`selection_policy_id`/`selected`/`reason_codes`).

## 5. Generic caller form / point at the real artifact.search #36 at fold

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputsJson '{"benchmark":"tests/fixtures/benchmark2.json"}'
```

At the D-0077 fold, set the benchmark's `retriever` to an `external_command` spec invoking `artifact.search`'s
`search` op with `hits_pointer` at its ranked hits, required labels using #36's `content_hash` (the source
version identity) + byte spans, and `provenance_corpus_dir` = the real corpus root. No code change is needed.
