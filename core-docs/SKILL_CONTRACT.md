# SKILL_CONTRACT

**Contract version: 0.1** — Owns the interface every independently-invokable local skill must expose.
This document is deliberately small. **Extend it only when a real module needs something it lacks**,
bump the version, and log the change in `DECISION_LOG.md`.

A skill is modular because it satisfies this contract — not because of its implementation language.

---

## 1. Every skill ships a manifest: `skill.json`

Placed at the skill's root. Minimum fields:

```json
{
  "schema": "proteus.skill.manifest/0.1",
  "skill_id": "fs.observer",                     // stable, dotted, lowercase; never reused for a different skill
  "name": "Filesystem Observer",
  "version": "0.1.0",                            // semver of THIS skill
  "contract_version": "0.1",
  "purpose": "List, search, compare, and index the filesystem without screenshots.",
  "determinism": "deterministic",               // deterministic | stochastic | mixed
  "invocation": {
    "method": "pwsh-file",                       // pwsh-file | executable | python | http | dll
    "entrypoint": "Invoke-FsObserver.ps1",
    "args_spec": "see inputs"                     // how args/params are passed
  },
  "inputs": [
    {"name": "path", "type": "string", "required": true, "description": "Root to inspect."},
    {"name": "depth", "type": "int", "required": false, "default": 3}
  ],
  "outputs": {
    "result_shape": "object",                     // shape of the `result` field in the envelope
    "description": "Directory tree with metadata."
  },
  "requirements": {
    "executables": ["pwsh>=7.4"],
    "models": [],
    "libraries": [],
    "cpu": "any", "gpu": "none", "memory_mb": 128,
    "network": false, "filesystem": "read", "audio": false, "screen": false, "camera": false
  },
  "artifacts": {"root": "runtime/artifacts/<invocation_id>/"},
  "timeout": {"default_seconds": 120, "on_timeout": "kill_tree_and_report"},
  "batch": false,
  "streaming": false,
  "parallel_safe": true,
  "example_invocation_file": "examples/example-invocation.md",
  "example_result_file": "examples/example-result.json"
}
```

Required at minimum: `skill_id`, `name`, `version`, `contract_version`, `purpose`, `determinism`,
`invocation`, `inputs`, `outputs`, `requirements`, `artifacts`, `timeout`, `batch`, `streaming`,
`parallel_safe`, plus the example pointers.

---

## 2. Every invocation returns one Result Envelope (JSON)

`schema = "proteus.skill.result/0.1"`. Written to stdout as a single JSON object **and** to
`result.json` in the artifact directory. Weaker local models and scripts consume this; keep it stable.

```json
{
  "schema": "proteus.skill.result/0.1",
  "skill_id": "fs.observer",
  "skill_version": "0.1.0",
  "contract_version": "0.1",
  "invocation_id": "8f3c...guid",
  "status": "ok",                      // ok | partial | error | cancelled
  "started_at_utc": "2026-07-24T02:10:00.0000000Z",
  "finished_at_utc": "2026-07-24T02:10:01.2500000Z",
  "duration_ms": 1250,
  "inputs_digest": "sha256:...",       // hash of the normalized inputs, for caching/idempotency
  "result": { },                        // skill-specific payload (see manifest.outputs)
  "confidence": null,                   // 0.0–1.0 for stochastic skills; null for deterministic
  "artifacts": [
    {"path": "runtime/artifacts/8f3c.../tree.md", "kind": "markdown", "bytes": 4096, "sha256": "..."}
  ],
  "model_provenance": [],               // [{model_id, version, params, runtime_ms}] when a model was used
  "diagnostics": {"log": "stderr.txt"}, // pointers, counts, timings — never secrets
  "warnings": [],
  "error": null                         // when status=error: {code, message, retryable}
}
```

---

## 3. Common conventions (v0.1)

- **stdout / stderr:** the single Result Envelope goes to **stdout**; human/diagnostic logging goes to
  **stderr** and is also captured to `stderr.txt` in the artifact dir. Never mix prose into stdout.
- **Artifacts & manifest:** all output files live under `runtime/artifacts/<invocation_id>/`. The
  envelope's `artifacts[]` array **is** the manifest (path, kind, bytes, sha256).
- **Timestamps:** UTC, ISO-8601 round-trip (`o` format), e.g. `2026-07-24T02:10:00.0000000Z`.
- **Exit codes:** `0` = envelope `status` ok/partial; **non-zero** = the process failed to produce a
  valid envelope. A skill that ran but failed logically still exits `0` with `status:"error"`.
- **Model provenance:** any model use is recorded in `model_provenance[]` (id, version, params, runtime).
- **File encoding:** UTF-8 **without BOM** for all text output. JSON is UTF-8, LF line endings.
- **Path handling:** accept absolute paths or paths relative to a stated working directory; always
  emit absolute paths in results. Quote/escape for the OS; never assume no spaces.
- **Temporary files:** under the invocation's artifact dir or the OS temp dir; clean up on success,
  leave them on failure for diagnosis.
- **Version compatibility:** consumers must tolerate unknown extra fields and branch on `schema`
  version. Never repurpose an existing field's meaning without a version bump.
- **Cancellation:** honor executor cancellation (process-tree termination); write a best-effort
  `status:"cancelled"` envelope if reachable, otherwise the executor records the cancellation.
- **Partial results:** `status:"partial"` + populate whatever completed + a `warnings[]` note.
- **Resource declarations:** the manifest's `requirements` block is authoritative; the router/registry
  trusts it for scheduling.
- **Confidence:** stochastic/mixed skills MUST populate `confidence` (0.0–1.0). Below a per-skill
  threshold, add an entry to the review queue (`REVIEW_QUEUE.md`).
- **Failure:** structured only — `error:{code, message, retryable}`. No stack-trace dumping into stdout.

---

## 4. Example

**Invocation** (through the executor or directly):
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -path 'C:\Users\just_\Project-Proteus-src' -depth 2
```

**Result** (`result.json`, abbreviated): see `proteus.skill.result/0.1` above with
`result` = `{ "root": "C:\\Users\\just_\\Project-Proteus-src", "entries": [ ... ] }`.

---

## 5. What this contract intentionally does NOT specify yet

No plugin framework, no registration daemon, no RPC layer, no auth, no capability tokens. Those arrive
only if a real module proves they are needed. Start every skill from this page; grow the page last.
