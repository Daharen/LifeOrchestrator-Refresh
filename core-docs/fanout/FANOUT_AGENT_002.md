# FANOUT_AGENT_002 -- i46 Lane B: AUTHOR the system-map claims file (judgment layer)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i46 (plan id `fo-46-6dd32d37`)
- **Lane:** CPU
- **Worker id / label:** `PCB-CLAIMS-i46`
- **Module/area (exclusive):** `modules/44-project-map/claims/` ONLY (the module's code is a parallel lane's -- touch NOTHING else)
- **GPU:** false
- **Docs:** `[]`
- **RECOMMENDED MODEL:** Sonnet 5 High (exact-spec'd; downstream machine-validated fail-closed; not ratification-critical -- D-0114 default lane)

## Mission (why this exists)

Nicholas's comprehension/bootstrap reconstruction directive hijacked i46 to build the **Project Comprehension Bootstrap**: a deterministic system map whose MECHANICAL facts are harvested by machinery (not you) and whose architectural JUDGMENT -- plane memberships, routing one-liners, relationships, where-to-descend pointers -- enters ONLY through a versioned, evidence-pointed claims file that a validator accepts or rejects fail-closed. You author that claims file for the whole repo. Governing docs: `modules/44-project-map/WORK_ORDER.md` s2.1/2.2/2.3/2.5 (THE frozen schema) + `core-docs/research/2026-08-11-i46-pcb-design.md` (decision record).

## Unit (the full worker prompt)

The complete emitted prompt is the file `modules/30-orchestrate-fanout/runtime/artifacts/db536ce1-fe00-4da4-a89c-407e7599a10e/workers/worker-PCB-CLAIMS-i46.prompt.md` (also delivered to you as a FILE) -- **execute that verbatim; it is the authority for this unit.** Compressed here for the 8 KB slot budget:

- **FIRST:** verify the WORK_ORDER sha256 = `439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725` (LF bytes). Mismatch => STOP + report. Fixture #0 in WO s2.5 is the normative claims shape -- match it field-for-field.
- **AUTHOR** `claims/i46-repo-claims.json` (`lifeorch.map_claims/0.1`; LF, UTF-8, ASCII, `json.dumps sort_keys indent=1` + trailing newline). COVERAGE: modules 00, 00.1, 01..43 (`module:NN/skill_id`) · widgets 01..08 (`widget:NN/dir-slug`) · ops tools (doc-commit-gate, gen-doc-health, exec-job, setup, + real others) · contracts (skill, memory, context-packet, action-authorization, doc-protocol; decide doc: vs contract: for MEMORY_ARCHITECTURE/AUDIT_PIPELINE and note why) · the 5 planes with 1-line definitions · arch positions 0-49 (+00.1) with `realizes` edges (verify 32->19, 33->20, 34->21, 36->23, 27-partial->24 in the docs; cite) · `store:` entities the docs support (artifact-search-sqlite, review-queue-jsonl, decision-log, model-registry, lease-dir, plans-dir, episode-store, ...) · meta stubs for every decision:/mandate:/pb:/iteration: your sources reference.
- **FIELDS** per entity (WO 2.2): plane_primary (+secondary where real); one_line <=160 chars (a ROUTING line: what it is + why you'd open it); status (MODULE_ROADMAP vocabulary); state_owned[]/authority_level/audit_surfaces[] where meaningful; deeper[] TYPED ordered pointers ({kind, ref}); aliases (#NN); confidence established|uncertain + note -- **honest uncertainty ALWAYS beats invented evidence**.
- **EDGES** (WO 2.3 closed enum; target <=~250 total): the ARCHITECTURAL graph only; every edge evidence-pointed; NO member-of (derived); no duplicates.
- **EVERY claimed field:** >=1 source `{ref, sha256:null, fields:[...], by:"lane-B-i46", at_commit:"<HEAD you read at>"}`; ref = repo path (+#anchor) | decision:D-#### | contract:<name>. Read the REAL docs; cite what you actually read. NEVER restate a harvestable fact (versions, manifest fields, doc sizes) -- the validator rejects it (CLAIM_RESTATES_HARVEST).
- **ALSO SHIP:** `claims/validate_claims_syntax.py` (<=60-line stdlib self-check: parses; required fields; ids in the closed ns set; edge types in enum; exits 0/1) + `claims/CLAIMS_NOTES.md` (<=4 KB: coverage counts, the uncertain list, judgment calls, gaps).

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first.
- ONE unit; NOTHING outside `claims/`; `docs:[]`; no model call; CPU only.
- Gate: run your syntax self-check clean, TWICE, before ship. Ship via `exec-job.sh devship` (test_argv = `python3 claims/validate_claims_syntax.py`; named files = exactly your three; trailers); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Leases: git at ship only; release on exit.
- Report: `-Action report -PlanId fo-46-6dd32d37 -WorkerId PCB-CLAIMS-i46 -State done` + plain measured summary. The orchestrator machine-validates + merges your file at fold -- expect rejects back if shape drifts; honest uncertainty beats confident invention (D-0107/D-0109).

## Verification (what proves it)

Syntax self-check exit 0 (x2, stated); devship commit verified via native git; REPORT carries: the WORK_ORDER sha, entity/edge counts by ns, the uncertain count + list, the top-15 docs read, known gaps. Final acceptance happens at the orchestrator fold: A's validator over your file (the D-0077 cross-module smoke) -- your success measure is LOW rejection count with HONEST uncertainty marks, not maximal coverage.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

_pending._
