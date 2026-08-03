# FANOUT_AGENT_003 -- i30 CONTRACT-HARDENING SKILL-SUMMARY lane

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i30 (plan id `fo-30-dd453156`)
- **Lane:** CPU -- the GPU lane is SKIPPED this wave (deterministic, no model)
- **Worker id / label:** SKILL-SUMMARY-i30
- **Module/area (exclusive):** modules/41-skill-card (skill id `skill.card`) 0.1.0 -> 0.2.0
- **GPU:** false
- **Docs:** `[]`

## Mission

Conform skill.card #41 to `core-docs/MEMORY_CONTRACT.md` Amendment A3 (frontier Wave-3 P0-5): emit
`record_kind = summary` (an activation card that DERIVES FROM #38's structural skill record), NOT a second
`record_kind = skill`. This makes repo.intel #38 the SOLE `record_kind = skill` producer, so a `record_kind = skill`
search returns ONE owner. A MINIMAL envelope-level change -- the card payload, Stage-1 eligibility, and Stage-2
retrieval stay UNCHANGED. PRODUCER of `summary` skill-activation records (ingested by #36; surfaced in #40's packets).

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/e0626255-ae62-4a28-acf5-b14c6d48e845/workers/worker-SKILL-SUMMARY-i30.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan.)

Scope digest (orientation only -- the emitted prompt governs):

- record_kind `skill` -> `summary`; add attrs.summary_type='skill_activation_card'. Keep record_id `sklcard_`, authority_level `derived`, the payload + Stage-1 + Stage-2 byte-identical in behavior.
- Replace/augment the `describes_structural_skill` child_edge with a `derives_from` edge (external, external_ref = #38's `skl_` id) per A3.
- content_hash = _h(canon(payload)) is UNCHANGED (record_kind + edges are envelope, not payload) -> record_id/record_version_id stay STABLE; idempotent re-ingest.
- Validator: `summary` is the primary emitted kind (still reject source_chunk); the ingest_records.json drop-in stays shaped for #36 0.2.
- NON-goals: P1-6 richer card fields + three-valued Stage-1 + degraded fail-closed (a NAMED follow-on, NOT this wave); the procedure registry; real embeddings; #36/#40/#37; models.json. Keep the change MINIMAL.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md`.
- Read `core-docs/CONTEXT_PACKET_CONTRACT.md` (D-0087; context_packet/0.2 + the s4 selection interface) + `core-docs/MEMORY_CONTRACT.md` (A2/A3) IN FULL -- the governing contracts for this wave. Pull the frontier digest `core-docs/research/2026-08-02-frontier-wave3-design-redteam.md` for the P0/P1 rationale.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY your module.
- Gate OFF-MACHINE first (cloud pwsh/python + mock/seam), THEN `-Live` on the executor; ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire the `git` lease ONLY around your dev.ship commit (release after). VERIFY the real HEAD via native `git log`/`git show --stat`, NOT the dev.ship `committed` field (D-0072).
- Any persistent llama-server launches DETACHED + is reaped before finalize (N/A this wave -- no model); assert 0 UNMANAGED orphans. Report via `-Action report -PlanId fo-30-dd453156 -WorkerId <id> -State done` (negative results are first-class, D-0061).

## Verification

Every emitted card record is record_kind=`summary` with attrs.summary_type='skill_activation_card' + a `derives_from` edge to #38's `skl_` id; the s1 validator passes on the fixture + real modules/ corpus; a test proving NO #41 record carries record_kind=`skill` (a `record_kind=skill` query returns only #38's records); the ingest_records.json still drops into #36 0.2 (shape check); deterministic re-run byte-identical (ids/order stable, content_hash unchanged); Stage-1 + Stage-2 tests stay GREEN. `-Live` over the real modules/ corpus. skill.json 0.2.0 + docs to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-30-dd453156/reports/`)

skill.card #41 0.1.0->0.2.0 SHIPPED `54c2e79` -- A3: record_kind skill->summary + attrs.summary_type=skill_activation_card + a derives_from edge to #38's skl_ record; #38 is now the SOLE record_kind=skill owner. Envelope-only (payload/Stage-1/Stage-2 unchanged; content_hash+ids STABLE). 81/81 python + 85/85 -Live. FOLD: D-0077 pair-2 PASSED clean -- 40/40 summary cards ingested into #36; a record_kind=skill search returns 0 #41 records; surfaced in a real context_packet/0.2.
