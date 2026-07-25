# image.interpret — Image Interpretation (local VLM captions / VQA / screen)

Fourth module of the image/document perception block (14–18). Interprets one image with a **local
vision-language model** and returns a free-text interpretation — a caption, a detailed description, an answer
to a question, or a screen summary — plus `model_provenance`, a completeness/refusal confidence, and a
review-queue hand-off for low-confidence / refusal / empty results.

## What it does

- Runs the already-staged **llama.cpp `llama-server` (b8661)** in **multimodal** mode
  (`-m <vlm.gguf> --mmproj <projector.gguf>` → `POST /v1/chat/completions` with an OpenAI-style `image_url`
  base64 data URI) — the same engine `model.gateway` (#7) drives, extended with the projector. The wrapper is
  **pure PowerShell** (no python worker): it base64-encodes the image, manages the server lifecycle (free-port
  pick → health-wait → completion → `taskkill` teardown), and builds the contract envelope.
- Resolves the VLM from `models.json` (`type=vlm`), **decoupled from the gateway's `wired` gate** (like
  `ocr.layout`/`detect.objects`, D-0020/D-0023). Default `vlm.qwen2p5-vl-3b` (Qwen2.5-VL-3B-Instruct GGUF
  Q4_K_M + mmproj-f16, Apache-2.0).
- Binds a loopback port + CUDA/VRAM → **`parallel_safe:false`** (unlike the parallel-safe #14–16).
- **Stochastic/mixed**: populates the envelope `confidence` (a documented **completeness + refusal +
  non-empty heuristic** — `stop`→0.7, `length`→0.4, refusal→0.3, empty→0.1; NOT calibrated/semantic) +
  `model_provenance`, and is the **seventh review-queue producer** — a low-confidence / refusal / empty
  interpretation → one page-level `verify_interpretation` item (`low_confidence` | `needs_strong_review`
  (refusal) | `failed_transform` (empty)).
- Composes **capture.screen** (Module 6) via `-Capture` ("interpret my screen") and **image.util**
  (Module 15) via `-MaxDimension` (downscale a very large screenshot before sending, to bound vision tokens).

## Modes

| mode | default prompt | when |
|------|----------------|------|
| `caption`  | "Describe this image in one clear sentence." | explicit `-Mode caption` |
| `describe` | detailed objects/setting/text | default for a file input |
| `vqa`      | uses your `-Prompt` verbatim | default when `-Prompt` is given |
| `screen`   | screen/app/UI-oriented summary | default with `-Capture` |

## Invocation

```powershell
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\photo.jpg -Mode describe
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\chart.png -Prompt "What is the trend in this chart?"
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -Capture -Mode screen
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputFile .\big.png -MaxDimension 1280 -Prompt "What dialog is shown?"
pwsh -NoProfile -File .\Invoke-ImageInterpret.ps1 -InputsJson '{"input":"ui.png","prompt":"Summarize the visible text."}'
```

Key parameters: `-Prompt`, `-Mode` (caption|describe|vqa|screen), `-System`, `-Model`/`-Tier`, `-MaxTokens`
(512), `-Temperature` (0.2), `-TopP` (0.9), `-Seed`, `-ConfidenceThreshold` (review floor, 0.5),
`-MaxDimension`, `-Capture`/`-CaptureInputsJson`; server knobs `-Context`/`-GpuLayers`/`-Port`/
`-LoadTimeoutSec`. See `skill.json` for the full list.

## Outputs

- `interpret.json` — full structured result (model, input, image, request, preprocess, interpretation,
  confidence).
- `interpret.md` — a human-readable card (prompt · confidence · the interpretation text).
- `result.json` — the `lifeorch.skill.result/0.1` envelope (also emitted on stdout).
- Diagnostics: `interpret_args.json`, `server.out.log`, `server.err.log`, `stderr.txt`; `capture/` when
  `-Capture`; `image_util/` when `-MaxDimension` downscales.

## Model

`vlm.qwen2p5-vl-3b` — Qwen2.5-VL-3B-Instruct in GGUF (`Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf`, 1840 MB) +
projector (`mmproj-Qwen2.5-VL-3B-Instruct-f16.gguf`, 1276 MB), Apache-2.0, staged to
`F:\...\_pending-model-storage\vlm\Qwen2.5-VL-3B-Instruct-GGUF\`. Downloaded + load-and-caption verified with
this exact `llama-server` build in `m17-probe-002` (accurate caption of `dog.jpg` at ~111 tok/s, full GPU
offload on the RTX 2080 Ti). A 7B tier and the transformers-venv backend are documented follow-ons.

## Tests

`tests/Invoke-ImageInterpretTests.ps1` is **dual-mode / OS-portable**. In **seam mode** (default, the cloud
pre-ship gate) the **real** wrapper runs with `-VlmResponsePath` pointing at a **captured-real** `llama-server`
response (`tests/fixtures/*.vlm-response.json`, captured live in `m17-probe-003`), exercising the whole
parse/confidence/review/compose/envelope path off-GPU; the `image.util -MaxDimension` composition runs for
real (Pillow is portable). With **`-Live`** (Windows/executor) it also runs real `llama-server` VLM inference
end-to-end and the Windows-only `capture.screen` composition.

## Not in this MVP (follow-ons)

A warm/persistent VLM server (shared worker-pool pressure with #7/#8/#12/#14/#16); logprob/calibrated
semantic confidence; batch/directory; multi-image + multi-turn; open-vocabulary grounding boxes (a #16
follow-on); a larger VLM tier (7B) / the transformers-venv backend; wiring the VLM as a second `ocr.layout`
engine; `image.index` (#18) fusing this with #14/#15/#16.
