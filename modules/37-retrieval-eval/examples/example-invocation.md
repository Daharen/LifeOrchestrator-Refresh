# retrieval.eval -- example invocations

`retrieval.eval` runs a **retrieval-quality benchmark** against any retriever that satisfies the D-0077
retriever interface and emits deterministic machine + human reports. All output goes to the invocation's
artifact directory; the single `lifeorch.skill.result/0.1` envelope goes to stdout.

## 1. Run the built-in lexical baseline over the fixture corpus

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\benchmark.json
```

The benchmark file names its own retriever (`lexical_baseline`) and corpus (`corpus`, resolved relative
to the benchmark file). The run writes `report.json` (machine, canonical) + `report.md` (human) into
`runtime/artifacts/<invocation_id>/`. Re-running is byte-identical.

Known baseline numbers over this fixture corpus (7 queries): recall@K = 857143 ppm (6/7), MRR = 857143,
stale-source rate = 142857 (1/7), forbidden-hit rate = 142857 (1/7), provenance completeness = 1000000.

## 2. Generic caller form (`-InputsJson`)

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputsJson '{"benchmark":"tests/fixtures/benchmark.json"}'
```

## 3. Point the harness at an EXTERNAL retriever (the fold seam)

Override the retriever with an `external_command` spec. The command must read a request
`{query, k, filters}` (via stdin here) and print a JSON envelope whose `result.hits` is the ranked hit
array `[{source_path, content_hash, chunk_id, span, score, snippet}, ...]`. The `mock-retriever.py`
fixture is a working example; at fold the orchestrator points this at the real `artifact.search`.

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\tests\fixtures\mock-benchmark.json
```

or inline the override on any benchmark:

```powershell
pwsh -NoProfile -File .\Invoke-RetrievalEval.ps1 -InputFile .\my-benchmark.json `
  -RetrieverJson '{"kind":"external_command","argv":["{PYTHON}","{BASE_DIR}/mock-retriever.py","{BASE_DIR}/mock-plan.json"],"request_via":"stdin","hits_pointer":"result.hits"}'
```

## 4. Regression command (deterministic double-run)

Run the same benchmark twice and compare `report.json` sha256 -- identical bytes prove determinism:

```powershell
pwsh -NoProfile -File .\tests\Invoke-RetrievalEvalTests.ps1 -PwshPath <pwsh>
```

The test harness pins the baseline `report.json`/`report.md` sha256 and the mock `report.json` sha256, so
a drift in the corpus, the metrics, or cross-environment bytes fails the gate.

See `examples/example-result.json` for a representative (sanitized) result envelope.
