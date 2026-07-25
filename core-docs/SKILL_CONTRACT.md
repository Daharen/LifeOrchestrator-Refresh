# SKILL_CONTRACT

**Contract version: 0.2** — Owns the interface every independently-invokable local skill must expose.
This document is deliberately small. **Extend it only when a real module needs something it lacks**,
bump the version, and log the change in `DECISION_LOG.md`.

**v0.2 (2026-07-25)** promotes the three provisional Module 1 conventions (DECISION_LOG **D-0009**,
confirmed by **D-0011** and since exercised by every skill through Module 18) from the Module 1 README
into this normative contract: (1) skill-relative artifact roots with **absolute** paths reported in the
envelope (section 3), (2) the generic `-InputsJson` argument every skill accepts (section 3.1), and
(3) the generic wrapper's `lifeorch.skill.invocation_report/0.1` object (section 3.2). The change is
**additive and backward-compatible**: the wire schema ids stay `lifeorch.skill.manifest/0.1` and
`lifeorch.skill.result/0.1` (unchanged fields, unchanged meaning), so every skill built under v0.1
remains valid. A manifest's `contract_version` may read `"0.1"` (existing skills) or `"0.2"` (new
skills) — the validator requires the field, not a specific value.

A skill is modular because it satisfies this contract — not because of its implementation language.

---

## 1. Every skill ships a manifest: `skill.json`

Placed at the skill's root. Minimum fields:

```json
{
  "schema": "lifeorch.skill.manifest/0.1",
  "skill_id": "fs.observer",                     // stable, dotted, lowercase; never reused for a different skill
  "name": "Filesystem Observer",
  "version": "0.1.0",                            // semver of THIS skill
  "contract_version": "0.2",                    // "0.1" or "0.2"; required field, value not enforced
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

`schema = "lifeorch.skill.result/0.1"`. Written to stdout as a single JSON object **and** to
`result.json` in the artifact directory. Weaker local models and scripts consume this; keep it stable.

```json
{
  "schema": "lifeorch.skill.result/0.1",
  "skill_id": "fs.observer",
  "skill_version": "0.1.0",
  "contract_version": "0.2",
  "invocation_id": "8f3c...guid",
  "status": "ok",                      // ok | partial | error | cancelled
  "started_at_utc": "2026-07-24T02:10:00.0000000Z",
  "finished_at_utc": "2026-07-24T02:10:01.2500000Z",
  "duration_ms": 1250,
  "inputs_digest": "sha256:...",       // hash of the normalized inputs, for caching/idempotency
  "result": { },                        // skill-specific payload (see manifest.outputs)
  "confidence": null,                   // 0.0–1.0 for stochastic skills; null for deterministic
  "artifacts": [
    {"path": "C:\\Users\\just_\\...\\02-fs-observer\\runtime\\artifacts\\8f3c...\\tree.md", "kind": "markdown", "bytes": 4096, "sha256": "..."}
  ],                                    // paths are ABSOLUTE in practice (section 3); manifest declares the relative root template
  "model_provenance": [],               // [{model_id, version, params, runtime_ms}] when a model was used
  "diagnostics": {"log": "stderr.txt"}, // pointers, counts, timings — never secrets
  "warnings": [],
  "error": null                         // when status=error: {code, message, retryable}
}
```

---

## 3. Common conventions (v0.2)

- **stdout / stderr:** the single Result Envelope goes to **stdout**; human/diagnostic logging goes to
  **stderr** and is also captured to `stderr.txt` in the artifact dir. Never mix prose into stdout.
- **Artifacts & artifact root (normative, D-0009):** a skill resolves its artifact root **relative to
  the skill folder** — `$PSScriptRoot/runtime/artifacts/<invocation_id>/` — unless the caller supplies
  `-ArtifactRoot`; it creates that directory and writes every output file there. The envelope's
  `artifacts[]` array **is** the manifest of that directory (`path`, `kind`, `bytes`, `sha256`) and
  **always reports absolute paths**, even though the manifest declares the root as the relative template
  `runtime/artifacts/<invocation_id>/`.
- **Timestamps:** UTC, ISO-8601 round-trip (`o` format), e.g. `2026-07-24T02:10:00.0000000Z`.
- **Exit codes:** `0` = envelope `status` ok/partial; **non-zero** = the process failed to produce a
  valid envelope. A skill that ran but failed logically still exits `0` with `status:"error"`.
- **Model provenance:** any model use is recorded in `model_provenance[]` (id, version, params, runtime).
- **File encoding:** UTF-8 **without BOM** for all text output. JSON is UTF-8, LF line endings.
- **Path handling:** accept absolute paths or paths relative to a stated working directory; always
  emit absolute paths in results. Quote/escape for the OS; never assume no spaces.
- **Temporary files:** under the invocation's artifact dir or the OS temp dir; clean up on success,
  leave them on failure for diagnosis.
- **Version compatibility:** consumers must tolerate unknown extra fields and branch on the `schema`
  version. Never repurpose an existing field's meaning without a version bump. The **contract document
  version** (this file: 0.2) and the **wire schema ids** (`lifeorch.skill.manifest/0.1`,
  `lifeorch.skill.result/0.1`) version independently: a backward-compatible contract revision bumps the
  document but not the schema ids. A manifest's `contract_version` states which contract revision the
  skill targets; the validator checks the field is present, not its value.
- **Cancellation:** honor executor cancellation (process-tree termination); write a best-effort
  `status:"cancelled"` envelope if reachable, otherwise the executor records the cancellation.
- **Partial results:** `status:"partial"` + populate whatever completed + a `warnings[]` note.
- **Resource declarations:** the manifest's `requirements` block is authoritative; the router/registry
  trusts it for scheduling.
- **Confidence:** stochastic/mixed skills MUST populate `confidence` (0.0–1.0). Below a per-skill
  threshold, add an entry to the review queue (`REVIEW_QUEUE.md`).
- **Failure:** structured only — `error:{code, message, retryable}`. No stack-trace dumping into stdout.

### 3.1 Generic input passing: `-InputsJson` (normative, D-0009)

Every skill entrypoint accepts a single generic argument **`-InputsJson '<json object>'`** whose keys are
the skill's inputs — **in addition to** any named parameters it also exposes. This lets a generic caller
(the wrapper below, the executor, a router, or an orchestrator skill) invoke any skill without knowing its
parameter list: it passes one JSON object. A skill may also offer named params for humans and direct
calls; when both a named param and an `-InputsJson` key supply the same input, the skill documents which
wins (skills to date let an explicit named param override the JSON). A skill also accepts an optional
**`-ArtifactRoot`** to relocate its artifact root — used by the wrapper and by orchestrator skills
(e.g. `voice.live`, `image.index`) that spawn children into a shared invocation directory.

### 3.2 The generic wrapper's report: `lifeorch.skill.invocation_report/0.1` (normative, D-0009)

The generic wrapper `Invoke-Skill.ps1` (Module 1) runs any conforming skill as **validate manifest ->
invoke in an isolated process -> validate the result envelope**, and emits exactly one
`lifeorch.skill.invocation_report/0.1` JSON object to stdout:

```json
{
  "schema": "lifeorch.skill.invocation_report/0.1",
  "skill_dir": "<path to the skill folder>",
  "skill_id": "fs.observer",            // from the manifest, or null if unreadable
  "manifest_valid": true,
  "manifest_errors": [],
  "invoked": true,                       // false if the manifest failed validation or the entrypoint is missing
  "exit_code": 0,                        // the skill process's exit code (null if not invoked)
  "envelope_valid": true,
  "envelope_errors": [],
  "envelope": { },                       // the parsed lifeorch.skill.result/0.1 (null if none/invalid)
  "stderr_tail": "<= 800 trailing chars of the skill's stderr"
}
```

The wrapper exits `0` only when the manifest is valid **and** the skill exited `0` **and** the emitted
envelope validates; otherwise `1`. With `-PassThruEnvelope` it re-emits the skill's raw result envelope
instead of this report. The report is a **wrapper/tooling** schema — it is *not* the skill's own output
(that is the `lifeorch.skill.result/0.1` envelope of section 2, which the report nests under `envelope`).

---

## 4. Example

**Invocation** (through the executor or directly):
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -path 'C:\Users\just_\LifeOrchestrator-Refresh' -depth 2
```

**Result** (`result.json`, abbreviated): see `lifeorch.skill.result/0.1` above with
`result` = `{ "root": "C:\\Users\\just_\\LifeOrchestrator-Refresh", "entries": [ ... ] }`.

---

## 5. What this contract intentionally does NOT specify yet

No plugin framework, no registration daemon, no RPC layer, no auth, no capability tokens. Those arrive
only if a real module proves they are needed. Start every skill from this page; grow the page last.
