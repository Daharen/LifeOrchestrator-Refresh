# voice.live — Voice Interaction Loop (Module 13)

The **capstone of the audio track (10–13)**. Given one input speech file, `voice.live` runs a local voice turn
by **composing the modules already built** — it reimplements nothing:

1. **STT** — `speech.stt` (Module 11) transcribes the audio; whisper's segmentation is the utterance /
   voice-activity detection. Zero segments → `speech_detected:false` (skip the rest).
2. **Respond** *(optional, `-Respond`, default on)* — `model.gateway` (Module 7) answers the transcript with a
   concise voice-assistant system prompt.
3. **Speak** *(optional, `-Speak`, default on)* — `speech.tts` (Module 12) synthesizes the answer (or the
   transcript, with `-ReadbackTranscript`) to `reply.wav`.

Each child runs as a spawned pwsh process; `voice.live` parses its `lifeorch.skill.result/0.1` envelope. This is
the first skill that composes several stochastic model skills end-to-end, and it validates that the skill contract
makes them cleanly composable.

## Invocation

```powershell
# full turn: audio question -> transcript -> answer -> spoken reply
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile .\question.wav

# transcribe + speak the transcript back (no LLM)
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile .\q.wav -Respond:$false -ReadbackTranscript:$true

# transcript + answer only (no audio reply), via -InputsJson
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputsJson '{"input":"q.wav","speak":false,"tier":"mid"}'
```

Wrapped (Module 1) or as an `exec.bootstrap` task package, like the other skills. Child entrypoints are resolved
from their sibling module folders by default and are overridable (`-SttPath`/`-GatewayPath`/`-TtsPath`).

## Output

`result`: `input`, `speech_detected`, `transcript{text,utterance_count,confidence,language,artifact_dir}`,
`response{text,model,confidence,finish_reason}` | null, `reply{path,format,sample_rate,duration_s,bytes,sha256}` |
null, `stages[{name,status,ms,error}]`, `config{...}`, `child_review_path`, `child_review_count`.

Envelope `confidence` = the STT transcript confidence (the "did we understand the user" signal);
`model_provenance` = the **aggregate** of every child model used (stt + gateway + tts), each tagged with its `stage`.

Artifacts under `runtime/artifacts/<invocation_id>/`: `voice.json` (`lifeorch.voice.turn/0.1`), `voice.md`,
`reply.wav` (when speaking), `result.json`, `stderr.txt`, `child_review.jsonl`, and child artifact subdirs
`stt/`, `gateway/`, `tts/`.

## Review-queue behavior

`voice.live` is an **orchestrator, not a review producer**. Its children (`speech.stt`, `model.gateway`,
`speech.tts`) each flag their own low-confidence outputs; `voice.live` points their review writes at an in-artifact
`child_review.jsonl` by default so a transient turn does not flood the canonical queue (surfaced as
`child_review_count`). Pass `-ReviewQueuePath` to route child flags to a canonical queue instead.

## Scope

MVP is a **file-driven offline voice turn**. **Live microphone capture / streaming is a non-goal** (no mic can be
assumed on this desktop; a mic front-end + streaming loop is a follow-on). Standalone VAD pre-segmentation is
deferred (the whisper VAD tool exists but no VAD ggml model is staged — `m13-probe-001`); whisper's own
segmentation via `speech.stt` is the utterance detector.

`determinism:"mixed"`, `parallel_safe:false` (children bind CUDA sequentially), `batch:false`. A full turn pays
three cold model loads (~1–2 min); a warm-worker pool is the shared follow-on.

## Tests

`tests/Invoke-VoiceLiveTests.ps1` — dual-mode: `-UseMock` points all three children at `tests/mock-child.ps1`
(canned envelopes; the tts branch writes a real WAV) so the full pipeline runs off-GPU (cloud pre-ship gate); the
default mode resolves the real children and runs a live turn on a real speech WAV (Windows/executor). Same
assertions.

See `WORK_ORDER.md` for scope and `DECISION_LOG.md` (D-0022) for rationale.
