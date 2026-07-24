# speech.stt — Speech-to-Text Transcription (Module 11)

Timestamped speech-to-text for Life Orchestrator. Wraps the **whisper.cpp** `whisper-cli` to turn one
audio/media file into text **segments with start/end timestamps** and a real **confidence** (the mean
whisper per-token probability), emitting a contract-valid `lifeorch.skill.result/0.1` envelope.

It is the second module of the audio track (10–13) and the first **stochastic/mixed** skill that wraps a
local **model** binary. It consumes the whisper-ready 16 kHz mono s16 WAV that `audio.ingest` (Module 10)
produces, and can call `audio.ingest` itself to normalize arbitrary input first.

## What it does

1. Resolves the STT model + whisper CLI from the model registry (`models.json`: `stt.whisper.base-en`,
   engine `whisper.cpp`, CUDA build preferred with CPU fallback).
2. **Normalizes** the input as needed (`-Normalize auto|always|never`): `auto` re-encodes through
   `audio.ingest` only when the input is not already WAV / 16000 Hz / mono / pcm_s16le; `always` forces it;
   `never` feeds the input straight to whisper.
3. Runs `whisper-cli -ojf -osrt -otxt` (full token-level JSON + SubRip + plain text).
4. Parses into timestamped segments, computes a **per-segment and overall confidence** = mean of the
   whisper token probabilities `p` (whisper special tokens excluded).
5. Routes **low-confidence segments** to the review queue (`lifeorch.review.item/0.1`,
   `flagged_by:"speech.stt"`), bounded by `-MaxReviewSegments`; a zero-segment result from non-trivial
   audio emits one `verify_no_speech` item.
6. Writes artifacts and emits the result envelope with `confidence` + `model_provenance` populated.

## Invocation

Direct:

```powershell
pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputFile .\meeting.wav
pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputFile .\clip.mp3 -Normalize always
pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputsJson '{"input":"jfk.wav","normalize":"never","language":"en"}'
```

Wrapped (Module 1) or as an `exec.bootstrap` task package, exactly like the other skills.

Key parameters: `-InputFile` (required), `-Normalize <auto|always|never>`, `-Language` (def `en`),
`-Translate`, `-Threads`, `-NoGpu`, `-BeamSize`, `-BestOf`, `-MaxLen`, `-SplitOnWord`, `-OffsetMs`,
`-DurationMs`, `-SegmentConfidenceThreshold` (def 0.5), `-MaxReviewSegments` (def 25), `-Model`
(def `stt.whisper.base-en`), plus `-Registry` / `-WhisperCliPath` / `-AudioIngestPath` / `-PwshPath` /
`-ReviewQueuePath` overrides. Any of these may also be passed inside `-InputsJson`.

## Output

`result` shape (see `skill.json`): `input`, `audio`, `model`, `params`, `language`, `text`,
`segment_count`, `token_count`, `confidence{overall,min_segment,low_confidence_segments}`,
`segments[{index,t0_ms,t1_ms,t0,t1,text,confidence,token_count,low_confidence}]`,
`review{threshold,flagged_count,truncated,queue_path}`, `whisper{cli,systeminfo,runtime_ms,real_time_factor}`.

Artifacts under `runtime/artifacts/<invocation_id>/`: `whisper.json` (raw token-level), `whisper.srt`,
`whisper.txt`, `transcript.json` (`lifeorch.stt.transcript/0.1` compact segments + confidence),
`transcript.md` (human summary), `result.json`, `stderr.txt`, `whisper.log`, and `normalize/…` when
normalization ran.

## Confidence

`confidence` = the mean whisper **token probability** over content tokens (special tokens like `[_BEG_]`
excluded), per segment and overall. It is a genuine acoustic-quality signal (unlike the gateway's
generation-completeness heuristic) but is **not** calibrated correctness — treat it as a triage signal.
Segments below `-SegmentConfidenceThreshold` (default 0.5) are flagged to the review queue.

## Determinism / safety

`determinism:"mixed"` (deterministic orchestration/parse; the model output is stochastic),
`parallel_safe:false` (binds the CUDA context, like `model.gateway`), `batch:false`, `streaming:false`.
Read-plus-write to its own artifact dir; the only shared-state write is the append-only review queue.

## Tests

`tests/Invoke-SpeechSttTests.ps1` — dual-mode: `-UseMock` runs the **real skill** against a mock
`whisper-cli` (`tests/mock-whisper.ps1` + the captured real `tests/fixtures/jfk.whisper.json`) and a temp
registry, validating the full parse/confidence/segment/review/envelope path off-GPU (the cloud pre-ship
gate, 27/27); the default mode resolves the real whisper CLI and transcribes a real WAV on Windows/the
executor. Same assertions in both modes.

See `WORK_ORDER.md` for scope and `DECISION_LOG.md` (D-0020) for rationale.
