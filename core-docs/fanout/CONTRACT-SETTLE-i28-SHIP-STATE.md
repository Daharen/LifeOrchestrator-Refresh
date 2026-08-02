# CONTRACT-SETTLE (i28) -- SHIP STATE (plan fo-28-45c4ad65, D-0085)

**Shipped 2026-08-02.** Single CPU worker (GPU + frontier + 2nd-CPU/coding lanes skipped); docs:[]; named-files-only dev.ship; native-git verified. 0 UNMANAGED orphans.

## Amendment (orchestrator, D-0085 scoping commit `90dd95b`)

MEMORY_CONTRACT record-envelope v0.1 -> **v0.1.1** (Amendment A1): (1) envelope `status`/`currentness` = a single s5 STRING (`current` baseline; the `{state,stale_reasons,verified}` object form RETIRED; multi-reason -> optional `attrs.stale_reasons`; a provenance failure -> `unverified`; a domain/body status stays `body.status`). (2) `record_kind` enum CLOSED; `episode_stage` NOT a kind -- an episode's per-stage detail is STRUCTURAL (in `episode.body.stage_sequence` + `child_edges`). Backward-compatible for #35/#36/#37/#38; re-verify {#39}.

## Module (worker, `3dab699`)

**episode.record #39 0.1.0 -> 0.1.1** -- envelope status emitted as the s5 string; `episode_stage` retired as an emitted/ingestable kind, the full per-stage s4 detail (stage_index/name/role/status/closed_explicitly/duration_ms/tool_invocations/state_changes/test_results/reviewer_outcomes/human_interventions/errors/notes/model_provenance) folded into `episode.body.stage_sequence` + `has_stage` child_edges by ordinal; s1 validator updated (status must be the s5 string; the episode_stage branch removed); extractor_fingerprint + skill 0.1.1. Suite 114 -> 123 GREEN cloud + `-Live`, byte-identical cross-env (Windows py3.12 == cloud py3.11). review_queue unchanged.

## D-0077 re-smoke (orchestrator) -- PASSED 30/30

episode.record 0.1.1 (episode + failure, from the shipped trace fixtures) fed RAW (NO bridge) into #36 0.2 `ingest_records`: **would_bridge dropStage=0 / coerceStatus=0** (0 bridging needed) -> episode+failure accepted, **0 rejections** -> no `episode_stage` kind in the bundle or the store -> every envelope status is the s5 string (`current`) -> `episode.body.stage_sequence` carries full stage detail + `has_stage` edges -> list-records episode/failure resolve with derivation_refs provenance -> retriever-0.2 hit shape (span object + span_label, opaque score retired) -> provenance span reproduces source (content_hash == file sha256) -> idempotent re-ingest (catalog_digest stable) -> integrity ok -> 0 orphans. The two i27 divergences are RESOLVED.

## Next

Wave 3 (context compiler + skill-card/registry + retrieval reranker), built to MEMORY_CONTRACT 0.2/v0.1.1 with the D-0077 cross-module smoke at fold. Residual: #35 embedding 0.2 adoption + real vector SEARCH (retrieval wave); the ~200 MB full-corpus CPU rehearsal (MEMORY_CONTRACT s7); a full hot-doc slim pass.
