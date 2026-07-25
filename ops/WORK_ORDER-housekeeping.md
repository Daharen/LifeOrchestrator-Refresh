# Work Order: Housekeeping Pass (2026-07-25) — contract finalization + model relocation + game-repo cleanup

**Contract version targeted:** 0.2 (this pass bumps it) · **Author:** Claude (Cowork) / 2026-07-25 ·
**Roadmap entry:** n/a (cross-cutting housekeeping; `CURRENT_STATE.md → Next expected action #4`, DECISION_LOG D-0009/D-0011)

Not a numbered module. This is the deferred housekeeping pass, taken now that the provisional Module 1
conventions are exercised by every skill through Module 18 and the owning modules for every staged model
(7/11/12/16/17) are built.

### Problem being solved
Three pieces of accrued debt, each independently safe and low-risk:
1. **Contract finalization.** `SKILL_CONTRACT.md` has stayed at v0.1 while three Module 1 conventions
   (D-0009, confirmed by D-0011) went normative in practice across Modules 2–18: skill-relative artifact
   roots with absolute paths in the envelope, the generic `-InputsJson` argument, and the wrapper's
   `lifeorch.skill.invocation_report/0.1`. Promote them; bump the contract document to v0.2.
2. **Model relocation + tokenizer de-dup.** All local models still sit in the temporary staging area
   `…_Large_Data\_pending-model-storage\`. Per D-0015 / `_pending-model-storage\MIGRATION.md`, move each
   into its owning module's F: home, update `models.json`, de-duplicate the triplicated 12 Hz TTS
   tokenizer, and delete the staging folder when empty.
3. **Game-repo cleanup.** Remove the stopped original executor leftover at
   `C:\Users\just_\Project-Proteus-src\proteus_repo\tools\` (recon: an empty 0 MB tree).

### Explicit scope (in)
- Edit `core-docs\SKILL_CONTRACT.md`: bump header to v0.2, fold in the three D-0009 conventions as
  normative (new §3.1 `-InputsJson`, §3.2 `invocation_report`, and the artifact-root/absolute-path rule
  in §3). Keep the wire schema ids at `/0.1` (additive, backward-compatible). Log a new DECISION_LOG entry
  (D-0028) resolving D-0009/D-0011.
- Update the stale "candidates for the contract to absorb later" note in `modules\01-skill-bootstrap\README.md`.
- Relocate every staged model dir within F: into `…_Large_Data\<NN>-<module>\` (LLMs → `07-model-gateway`,
  whisper → `11-speech-stt`, TTS voices → `12-speech-tts`, detectors → `16-detect-objects`, VLM →
  `17-image-interpret`, embedding → `23-artifact-search` pre-provisioned), and the shared llama.cpp engine
  → `…_Large_Data\_engines\` (root; shared by #7 and #17).
- Rewrite the ~11 absolute paths + `engines.llama-server` in `modules\07-model-gateway\models.json`;
  remove the declared-only `tts.tokenizer.qwen3-12hz` entry (deduped).
- De-duplicate the tokenizer by deleting the redundant standalone copy (byte-identical to each voice's
  bundled `speech_tokenizer\`, sha256 836B7B35…; consumed by no skill).
- Delete the emptied `_pending-model-storage\` (and its `MIGRATION.md`, vlm HF cache) after skills verify green.
- Remove `proteus_repo\tools\`.
- Re-verify every affected wired skill loads from its new path; commit; update core docs; mirror to the Project.

### Non-goals (out — do NOT build)
- No junctions/symlinks to collapse the two per-voice bundled `speech_tokenizer\` copies to one physical
  file — D-0015 prefers self-contained portable copies over links; each voice stays independently copyable.
  (A qwen_tts external-tokenizer-path config change is a possible future follow-on, not this pass.)
- No schema-id bump (`/0.1` stays), no rewrite of the 18 existing skill manifests, no validator change
  (the validator already requires `contract_version` to be present, not a specific value).
- No new skill, no Module 19, no touching module code other than the Module 1 README note.

### Dependencies
- Modules: 0 (executor), 1 (contract/validators), 7/11/12/16/17 (owning modules of the staged models).
- Tools/models: the staged models + the llama.cpp/whisper.cpp/qwen_tts/onnxruntime engines (all present).
- Docs: `SKILL_CONTRACT.md`, `_pending-model-storage\MIGRATION.md`, `models.json`, `DECISION_LOG.md`.

### Tests / verification
- Contract: validators already accept the change (schema ids unchanged; `contract_version` value unchecked).
  Confirmed `invocation_report` shape against `Invoke-Skill.ps1`'s actual emission.
- Relocation: executor task `hk-relocate-001` pre-flights (src exists / dst free), moves within F:
  (same-volume renames), Test-Paths all 15 new model files. `models.json` transformed with strict
  occurrence assertions + JSON-parse + zero-`_pending-model-storage` invariant; committed byte-exact and
  sha256-verified via an executor read.
- Skills: executor task `hk-verify-001` loads all 4 LLM tiers + whisper STT + Qwen3-TTS (with its bundled
  tokenizer) + ONNX detector + multimodal VLM, each from its new F: home; orphan check.

### MVP acceptance criteria
- `SKILL_CONTRACT.md` is v0.2 with the three conventions normative; DECISION_LOG D-0028 logged.
- `_pending-model-storage\` deleted; every `models.json` path resolves to a real file under an owning-module
  F: home; the tokenizer exists once per voice (standalone copy gone) and TTS still synthesizes.
- All re-verify smokes return `status: ok`; no orphaned model servers.
- `proteus_repo\tools\` gone.
- Commit made via the executor (Co-Authored-By + Claude-Session trailers); core docs updated; Project mirrored.

### STOP conditions
- A relocation pre-flight failure (missing src / dst collision) — abort moves, report, do not force.
- Any re-verify smoke fails to load a model from its new path — stop, diagnose (do not delete the staging
  folder until green, so a move-back recovery stays trivial).
- Scope creep beyond the three items above — stop and log to the roadmap instead.

### Known follow-on work (NOT this pass)
- Collapse the two per-voice bundled tokenizers to a single shared copy via a qwen_tts external-tokenizer
  config (testable; deferred for portability).
- Relocate/retire the whisper.cpp engine builds (still referenced at their `F:\Local_TTS_Large_Data\external`
  source via `engine_candidates`) and the speech venv — external engines, out of scope here.
- Eventually retire `LifeOrchestrator-Refresh_Large_Data` extras if the root has no real content (per MIGRATION.md).
