# video.timeline — example invocations

## Direct (a manifest file)

```powershell
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputFile .\tests\fixtures\fused.json
```

Fuses the committed full fixture — media meta + 2 scenes + an 8-sample manifest + 4 reviewed-schema
tracks (one with a recorded gap) + 2 transcript segments + 2 OCR entries (one keyed by `frame_index`,
mapped through the sample manifest) + 4 per-sample detection entries — into one canonical
`timeline.json`: 6 intervals (5 `track_presence` + 1 `track_gap`), 10 events, a 4-way index, and a
summary. Re-running yields byte-identical canonical output (same sha256) on any machine.

## Inline manifest (no file)

```powershell
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputsJson '{"media":{"id":"clip-1","meta":{"frame_width":640,"frame_height":360,"duration_ms":12000}}}'
```

The meta-only degradation mode: a valid, empty-but-well-formed timeline with `coverage.status "unknown"`.

## Through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"input":"tests/fixtures/fused.json"}'
```

## Degradation + refusal probes

```powershell
# tracks without a sample manifest -> coverage unknown, explicitly downgraded presence semantics, status partial
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputFile .\tests\fixtures\tracks-nosamples.json

# OCR keyed by frame_index with no sample manifest -> fail-closed refusal (timestamps are never invented)
pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputFile .\tests\fixtures\ocr-refuse.json
```

The refusal envelope is `status:"error"`, `error.code:"input_validation_failed"`, with every violation
enumerated in `result.violations[{path, why}]`; no timeline.json is written.

See `examples/example-result.json` for a full captured envelope of the fused run and
`examples/verification-packet.json` for the Verification Console packet.
