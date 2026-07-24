# speech.tts — Text-to-Speech Synthesis (Module 12)

Local text-to-speech for Life Orchestrator. Turns text into a speech WAV using the **Qwen3-TTS CustomVoice**
models (the `qwen_tts` package / transformers, under the speech venv), emitting a contract-valid
`lifeorch.skill.result/0.1` envelope. It is the third audio-track module (10–13) and the inverse of Module 11
(`speech.stt`) — together they are the two halves a future `voice.live` (Module 13) composes. First skill to
drive a **Python model** (vs. the whisper.cpp / llama.cpp binaries).

## What it does

1. Resolves the TTS model + venv python from the registry (`models.json`: `tts.weak.qwen3-0p6b` default,
   `tts.strong.qwen3-1p7b`; engine `transformers`, `engine_env` = the speech venv python).
2. A Python worker (`tts_infer.py`, run under the venv) loads the model (bf16 + `sdpa` on the RTX 2080 Ti) and
   calls `qwen_tts.Qwen3TTSModel.generate_custom_voice(text, speaker, language, instruct)` → `(wavs, sr=24000)`.
3. Writes a 24 kHz mono PCM16 `speech.wav`; the PowerShell wrapper (`Invoke-SpeechTts.ps1`) builds the envelope.
4. Optionally re-encodes to a requested `-Format` / `-SampleRate` via `audio.ingest` (Module 10).
5. Computes a **synthesis-completeness confidence** and, on a failed/too-short synthesis, routes it to the
   review queue (`flagged_by:"speech.tts"`). Populates `confidence` + `model_provenance`.

## Invocation

Direct:

```powershell
pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -Text "Hello from Life Orchestrator." -Speaker Ryan
pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -Text "Good morning." -Speaker Aiden -Instruct "Cheerful tone." -Format mp3
pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -InputsJson '{"text":"Bonjour.","speaker":"Ryan","language":"French"}'
```

Wrapped (Module 1) or as an `exec.bootstrap` task package, like the other skills.

Preset English speakers: **Ryan, Aiden**. The 0.6B CustomVoice model also ships Vivian / Serena / Uncle_Fu /
Dylan / Eric (Chinese), Ono_Anna (Japanese), Sohee (Korean) — use a speaker in the text's native language.

## Output

`result` shape (see `skill.json`): `input`, `model`, `params`, `audio{path,sample_rate,channels,samples,
duration_s,bytes,sha256,format,native_sample_rate,converted}`, `confidence{overall,reason}`,
`review{threshold,flagged,queue_path}`, `synthesis{runtime_ms,real_time_factor}`.

Artifacts under `runtime/artifacts/<invocation_id>/`: `speech.wav` (24 kHz mono PCM16, or the converted format),
`tts.json` (`lifeorch.tts.synthesis/0.1`), `tts.md`, `result.json`, `stderr.txt`, `py.log`, `tts_args.json`,
`tts_meta.json`, and `convert/…` when re-encoding ran.

## Confidence

`confidence` is a documented **synthesis-completeness heuristic**, NOT audio quality: empty/near-silent → 0.1,
far-too-short-for-the-text → 0.3, short → 0.5, plausible duration → 0.9. Below `-ConfidenceThreshold`
(default 0.5) the synthesis is flagged to the review queue (`requested:"verify_synthesis"`) — a
failed-synthesis guard a reviewer (or the frontier) can act on.

## Determinism / safety

`determinism:"mixed"` (deterministic orchestration; the model samples with `do_sample=true`, seedable via
`-Seed`), `parallel_safe:false` (binds the CUDA context + loads a model, like `model.gateway`/`speech.stt`),
`batch:false`, `streaming:false`. GPU (CUDA) required. Per-call model load is ~30–40 s cold (a warm worker is a
documented follow-on).

## Tests

`tests/Invoke-SpeechTtsTests.ps1` — dual-mode: `-UseMock` runs the *real* skill against a mock python worker
(`tests/mock-tts-infer.py`, which writes a real PCM16 WAV via stdlib) + a temp registry, validating the full
parse/confidence/review/envelope/audio.ingest-conversion path off-GPU (the cloud pre-ship gate); the default
mode resolves the real venv python + model and synthesizes live on Windows/the executor. Same assertions in
both modes.

See `WORK_ORDER.md` for scope and `DECISION_LOG.md` (D-0021) for rationale.
