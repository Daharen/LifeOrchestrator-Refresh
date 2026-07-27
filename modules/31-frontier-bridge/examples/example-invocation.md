# frontier.bridge — example invocations

`frontier.bridge` is **local-only**: it reads local files and writes a copy-paste pack. It never
contacts ChatGPT or any external service. The human is the sole courier (DECISION_LOG D-0052).

## 1. Pack a folder for an external second opinion

```powershell
pwsh -NoProfile -File .\Invoke-FrontierBridge.ps1 `
  -Action pack `
  -Prompt "You are a senior PowerShell reviewer. Review the attached module for correctness and race conditions." `
  -Question "Is the atomic-move queue logic free of the double-claim race?" `
  -Folder "C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor" `
  -Include "*.ps1" `
  -Exclude "*.Tests.ps1"
```

Produces (in `runtime/artifacts/<invocation_id>/`):

- `frontier-pack-<id>.md` — the copy-paste pack: instructions + question + each `.ps1` concatenated
  with `FBRIDGE::<id>` begin/end delimiters + a manifest.
- `manifest.json` — exactly what was included/skipped (path, bytes, sha256, encoding).
- `frontier-pack-<id>.answer.md` — the empty **return file** to paste the model's answer into.

The human then: copies the pack into their own model session → pastes the reply below the dashed
separator in the return file.

## 2. Pack specific files / globs via the generic input channel

```powershell
pwsh -NoProfile -File .\Invoke-FrontierBridge.ps1 `
  -InputsJson '{"action":"pack","prompt":"Explain this bug.","question":"Why is $x null?","paths":["src\\a.ps1","src\\lib\\*.ps1"]}'
```

## 3. Read the pasted answer back for Claude

```powershell
pwsh -NoProfile -File .\Invoke-FrontierBridge.ps1 `
  -Action read-return `
  -ReturnFile "C:\...\runtime\artifacts\<id>\frontier-pack-<id>.answer.md"
```

Returns `{captured:true, content:"<the answer text>", sha256:...}` in the result envelope for Claude
to consume. If the file still holds only the stub, `captured` is `false` and `status` is `partial`.
