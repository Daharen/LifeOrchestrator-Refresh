#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deterministically generate the off-machine fixtures for context.compile.

Every 0.2-shape hit's span points into the corpus text and its `chunk_content_hash` is set to
sha256(span_bytes) so the compiler's provenance check genuinely reproduces the cited text.
Run:  python _gen_fixtures.py   (writes compile_case.json, diversity_case.json, expand_case.json)
"""
import json
import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))

def sha256_hex(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return hashlib.sha256(b).hexdigest()

def chunk_hit(source_path, full_text, start, end, *, rank, record_kind="source_chunk",
              record_id=None, record_version_id=None, currentness="current",
              authority_level="source_material", namespace="core-docs", section_path=None,
              heading=None, chunk_type="markdown_section", fused_score=None, snippet=None,
              lexical_score=None):
    b = full_text.encode("utf-8")
    span_bytes = b[start:end]
    cch = sha256_hex(span_bytes)
    file_hash = sha256_hex(b)
    rid = record_id or ("srec_" + sha256_hex(source_path + "\0" + str(start))[:24])
    rvid = record_version_id or ("occ_" + sha256_hex(source_path + "\0" + str(start) + "\0" + cch)[:24])
    if fused_score is None:
        fused_score = round(1.0 - (rank - 1) * 0.01, 6)
    if lexical_score is None:
        lexical_score = fused_score
    label = section_path or ("bytes:%d-%d" % (start, end))
    return {
        "record_id": rid,
        "record_version_id": rvid,
        "record_kind": record_kind,
        "chunk_id": "chk_" + sha256_hex(source_path + "\0" + str(start))[:24],
        "source_path": source_path,
        "abs_path": None,
        "content_hash": file_hash,           # SOURCE VERSION identity (file bytes hash)
        "chunk_content_hash": cch,           # == sha256(span bytes) -> provenance reproduces
        "span": {"start": start, "end": end},
        "span_label": label,
        "section_path": section_path,
        "heading": heading,
        "chunk_type": chunk_type,
        "status": currentness,
        "currentness": currentness,
        "authority_level": authority_level,
        "namespace": namespace,
        "source": namespace,
        "source_version_id": "ver_" + sha256_hex(source_path + "\0" + file_hash)[:24],
        "embedding_space_id": None,
        "retrieval_channels": ["lexical"],
        "lexical_rank": rank,
        "lexical_score": lexical_score,
        "vector_rank": None,
        "vector_similarity": None,
        "fused_rank": rank,
        "fused_score": fused_score,
        "fusion_algo": "lexical_only",
        "fusion_version": "1",
        "index_snapshot": "digest_fixture_0001",
        "corpus_version": "digest_fixture_0001",
        "filter_decisions": {},
        "tie_break_key": rvid,
        "snippet": snippet if snippet is not None else span_bytes.decode("utf-8"),
        "rank": rank,
    }

# ---------------------------------------------------------------- compile_case (mixed kinds) ----
def build_compile_case():
    alpha = (
        "# Resource Lease\n\n"                                             # 0..16
        "The res.lease module #29 grants gpu, git, and doc leases.\n\n"     # 16..75
        "## Fencing\n\n"                                                    # 75..87
        "Three-identity fencing rejects a stale holder deterministically.\n\n"  # 87..152
        "## Ship discipline\n\n"                                            # 152..172
        "Acquire gpu then git then doc; release in reverse order.\n"        # 172..228
    )
    procdoc = (
        "# Ship a unit\n\n"
        "Run dev.ship: it verifies sha256 + AST + tests fail-closed, then commits named files.\n"
    )
    skilldoc = "context.compile turns a task descriptor into a token-budgeted context packet.\n"
    faildoc = "dev.ship can FALSE-NEGATIVE committed; verify the real HEAD via native git log.\n"

    corpus = {
        "core-docs/alpha.md": alpha,
        "core-docs/proc.md": procdoc,
        "core-docs/skill.md": skilldoc,
        "core-docs/fail.md": faildoc,
    }

    def seg(text, sub):
        i = text.index(sub)
        return i, i + len(sub.encode("utf-8")) if False else i + len(sub)

    ab = alpha.encode("utf-8")
    # byte spans of a few sections in alpha.md
    s1 = ab.index("The res.lease".encode("utf-8"))
    e1 = ab.index("\n\n## Fencing".encode("utf-8"))
    s2 = ab.index("Three-identity".encode("utf-8"))
    e2 = ab.index("\n\n## Ship".encode("utf-8"))
    s3 = ab.index("Acquire gpu".encode("utf-8"))
    e3 = len(ab)

    pb = procdoc.encode("utf-8")
    ps = pb.index("Run dev.ship".encode("utf-8"))
    pe = len(pb)
    sb = skilldoc.encode("utf-8")
    fb = faildoc.encode("utf-8")

    hits_primary = [
        chunk_hit("core-docs/alpha.md", alpha, s1, e1, rank=1, section_path="Resource Lease",
                  authority_level="authoritative"),
        chunk_hit("core-docs/alpha.md", alpha, s2, e2, rank=2, section_path="Resource Lease > Fencing"),
        chunk_hit("core-docs/alpha.md", alpha, s3, e3, rank=3, section_path="Resource Lease > Ship discipline"),
    ]
    hits_proc = [
        chunk_hit("core-docs/proc.md", procdoc, ps, pe, rank=1, record_kind="procedure",
                  section_path="Ship a unit", chunk_type="procedure",
                  record_id="prec_ship", record_version_id="prec_ship_v1", authority_level="derived"),
    ]
    hits_skill = [
        chunk_hit("core-docs/skill.md", skilldoc, 0, len(sb), rank=1, record_kind="skill",
                  record_id="skill.context.compile", record_version_id="skill.context.compile@0.1.0",
                  chunk_type="skill", authority_level="derived"),
    ]
    hits_fail = [
        chunk_hit("core-docs/fail.md", faildoc, 0, len(fb), rank=1, record_kind="failure",
                  record_id="fail_devship_fn", record_version_id="fail_devship_fn_v1",
                  chunk_type="failure", authority_level="derived"),
    ]

    task = {
        "original_goal": "Ship the context compiler safely under the git lease.",
        "request_text": "How does res.lease #29 fencing work and how do I ship a unit with dev.ship?",
        "namespace": "core-docs",
        "task_type": "coding",
        "time_horizon": "current_only",
        "relevant_paths": ["core-docs/alpha.md"],
        "relevant_entities": ["res.lease", "dev.ship"],
        "requested_side_effects": ["git.commit"],
        "authority": "worker",
        "constraints": ["docs:[] -- do not edit core-docs"],
        "config": {"token_budget": 400, "per_source_cap": 3},
    }
    retrieval_meta = {"retriever": "mock", "retriever_version": "fixture/1",
                      "corpus_version": "digest_fixture_0001", "index_snapshot": "digest_fixture_0001",
                      "embedding_space_id": None, "fusion_algo": "lexical_only", "fusion_version": "1"}
    batches = [
        {"query_index": 0, "hits": hits_primary},
        {"query_index": 1, "hits": hits_fail},
        {"query_index": 2, "hits": hits_proc},
        {"query_index": 3, "hits": hits_skill},
    ]
    return {"task": task, "retrieval_batches": batches, "source_texts": corpus,
            "retrieval_meta": retrieval_meta}

# ---------------------------------------------------------------- diversity_case ----------------
def build_diversity_case():
    # 10 near-duplicate chunks in ONE source (distinct text -> distinct chunk_content_hash) ranked 1..10,
    # plus 1 DISTINCT required source ranked 11. per_source_cap must stop the near-dups from crowding it out.
    lines = []
    for i in range(10):
        lines.append("Near duplicate paragraph number %02d about the warm pool supervisor gate.\n" % i)
    near = "".join(lines)
    required = "The REQUIRED distinct source: the git lease serializes the dev.ship commit.\n"
    corpus = {"core-docs/near.md": near, "core-docs/required.md": required}

    nb = near.encode("utf-8")
    hits = []
    off = 0
    for i in range(10):
        ln = lines[i].encode("utf-8")
        start, end = off, off + len(ln)
        off = end
        hits.append(chunk_hit("core-docs/near.md", near, start, end, rank=i + 1,
                              section_path="Near %02d" % i))
    rb = required.encode("utf-8")
    req_hit = chunk_hit("core-docs/required.md", required, 0, len(rb), rank=11,
                        section_path="Required", record_id="req_distinct",
                        record_version_id="req_distinct_v1")
    hits.append(req_hit)

    task = {
        "original_goal": "Summarize the current shipping discipline.",
        "request_text": "warm pool supervisor gate and the git lease dev.ship commit",
        "namespace": "core-docs",
        "task_type": "documentation",
        "config": {"token_budget": 2000, "per_source_cap": 3, "max_excerpts": 40},
    }
    return {"task": task, "retrieval_batches": [{"query_index": 0, "hits": hits}],
            "source_texts": corpus,
            "retrieval_meta": {"retriever": "mock", "corpus_version": "digest_div_0001"},
            "_required_rvid": "req_distinct_v1", "_near_source": "core-docs/near.md"}

# ---------------------------------------------------------------- expand_case -------------------
def build_expand_case():
    # A summary excerpt whose raw source lives behind it; expand(raw_source) must fetch bounded raw text.
    raw = ("# Detailed spec\n\n"
           "The context packet carries immutable goal, normalized task, excerpts with provenance, "
           "omitted context, token accounting, and expansion affordances. " * 6 + "\n")
    summary = "Summary: the context packet has goal, excerpts, omitted context, and expansion.\n"
    corpus = {"core-docs/spec.md": raw, "core-docs/summary.md": summary}

    rb = raw.encode("utf-8")
    sb = summary.encode("utf-8")
    summary_hit = chunk_hit("core-docs/summary.md", summary, 0, len(sb), rank=1,
                            record_kind="summary", record_id="sum_spec",
                            record_version_id="sum_spec_v1", chunk_type="summary",
                            authority_level="derived")
    raw_hit = chunk_hit("core-docs/spec.md", raw, 0, len(rb), rank=1, record_id="chunk_spec",
                        record_version_id="chunk_spec_v1", section_path="Detailed spec")

    task = {
        "original_goal": "Explain the context packet spec.",
        "request_text": "context packet spec summary",
        "namespace": "core-docs",
        "task_type": "research",
        "config": {"token_budget": 200},
    }
    compile_args = {"task": task, "retrieval_batches": [{"query_index": 0, "hits": [summary_hit]}],
                    "source_texts": corpus, "retrieval_meta": {"retriever": "mock"}}
    expand_request = {"type": "raw_source", "target": {"record_version_id": "chunk_spec_v1"},
                      "budget": {"max_tokens": 40}}
    return {"compile_args": compile_args, "expand_request": expand_request,
            "expansion_candidates": [raw_hit], "source_texts": corpus,
            "_raw_full_tokens": int((len(raw) + 3) // 4)}

def build_task_only():
    return build_compile_case()["task"]

def build_live_task():
    # A task descriptor for the -Live acceptance over a real core-docs slice ingested by #36.
    # Terms chosen to hit real core-docs content (>=3 LO benchmark questions folded into one packet).
    return {
        "original_goal": "Ship the Wave 3 context compiler safely under the res.lease git lease.",
        "request_text": ("How does res.lease fencing work, how do I ship a unit with dev.ship, "
                         "and what is the executor wedge gotcha?"),
        "namespace": "core-docs",
        "task_type": "coding",
        "time_horizon": "current_only",
        "relevant_paths": ["CURRENT_STATE.md"],
        "relevant_entities": ["res.lease", "dev.ship", "wedge", "heartbeat"],
        "requested_side_effects": ["git.commit"],
        "authority": "worker",
        "constraints": ["docs:[] -- workers do not edit core-docs"],
        "config": {"token_budget": 1200, "per_source_cap": 3, "candidate_k": 20},
    }

def build_expand_case_full(compile_module):
    """Build a self-contained entrypoint-level expand case: {packet, request, expansion_candidates,
    source_texts} where `packet` is the real compiled packet from the expand_case compile_args."""
    ec = build_expand_case()
    args = dict(ec["compile_args"]); args["op"] = "compile"
    meta = compile_module.run(args)
    packet = meta["result"]["packet"]
    return {"packet": packet, "request": ec["expand_request"],
            "expansion_candidates": ec["expansion_candidates"], "source_texts": ec["source_texts"]}

def main():
    import sys
    sys.path.insert(0, os.path.dirname(HERE))
    import context_compiler as _cc
    cases = {
        "compile_case.json": build_compile_case(),
        "diversity_case.json": build_diversity_case(),
        "expand_case.json": build_expand_case(),
        "task_only.json": build_task_only(),
        "live_task.json": build_live_task(),
        "expand_case_full.json": build_expand_case_full(_cc),
    }
    for name, obj in cases.items():
        path = os.path.join(HERE, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        print("wrote", name)

if __name__ == "__main__":
    main()
