#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Off-machine deterministic test gate for context.compile (Module 40).

CPU-only, stdlib-only, mock retriever seam (fixture 0.2 hits). Fail-closed: exits non-zero on any
failure. Covers the work-order ACCEPTANCE items (a)-(e) + the -Live-shaped behaviours:
  budget + exact accounting, provenance span reproduces source, omitted-context + expansion,
  byte-identical re-run (deterministic packet_id), the diversity cap (10 near-dups do not crowd out
  a distinct required source), and the expand op returning bounded raw source behind a summary.
"""
import os
import sys
import json
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
sys.path.insert(0, MOD)
FIX = os.path.join(MOD, "fixtures")

import context_compiler as cc  # noqa: E402

_passed = 0
_failed = 0

def check(name, cond, detail=""):
    global _passed, _failed
    if cond:
        _passed += 1
        print("  PASS  " + name)
    else:
        _failed += 1
        print("  FAIL  " + name + ("  :: " + detail if detail else ""))

def load(name):
    with open(os.path.join(FIX, name), "r", encoding="utf-8") as f:
        return json.load(f)

def sha256_hex(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return hashlib.sha256(b).hexdigest()

# ----------------------------------------------------------------------------- primitives -------
def test_primitives():
    print("[primitives]")
    check("canonical_json sorts keys", cc.canonical_json({"b": 1, "a": 2}) == '{"a":2,"b":1}')
    check("canonical_json stable across dict order",
          cc.canonical_json({"a": 1, "b": {"y": 2, "x": 3}}) == cc.canonical_json({"b": {"x": 3, "y": 2}, "a": 1}))
    check("est_tokens ceil(chars/4)", cc.est_tokens("abcde") == 2 and cc.est_tokens("") == 0)
    check("to_micros deterministic", cc.to_micros(0.5) == 500000 and cc.to_micros(None) is None)

# ----------------------------------------------------------------------------- normalize --------
def test_normalize():
    print("[normalize 8.1]")
    case = load("compile_case.json")
    meta = cc.run({"op": "normalize", "task": case["task"]})
    check("normalize ok", meta["ok"], json.dumps(meta))
    r = meta["result"]
    check("original_goal preserved verbatim",
          r["original_goal"] == case["task"]["original_goal"])
    qs = r["query_set"]
    check("query_set nonempty + bounded", 0 < len(qs) <= cc.DEFAULT_CONFIG["max_queries"])
    check("query_set deterministic indices", [q["query_index"] for q in qs] == list(range(len(qs))))
    # a literal (dotted skill id / entity) should surface an exact query
    modes = set(q["mode"] for q in qs)
    check("has fts + exact queries", "fts" in modes and "exact" in modes, str(modes))
    # deterministic: same input -> identical query_set
    meta2 = cc.run({"op": "normalize", "task": case["task"]})
    check("normalize byte-identical", cc.canonical_json(meta["result"]["query_set"]) ==
          cc.canonical_json(meta2["result"]["query_set"]))

# ----------------------------------------------------------- (a) budget + exact accounting ------
def test_budget_accounting():
    print("[acceptance a: token budget + EXACT accounting + truncation]")
    case = load("compile_case.json")
    # squeeze the budget so truncation happens
    case["task"]["config"]["token_budget"] = 90
    meta = cc.run(case)
    p = meta["result"]["packet"]
    acct = p["token_budget"]
    check("used <= budget", acct["used"] <= acct["budget"], json.dumps(acct))
    check("remaining == budget - used", acct["remaining"] == acct["budget"] - acct["used"])
    # exact accounting: used == sum(excerpt tokens) + overhead*count
    recomputed = sum(e["token_estimate"] for e in p["excerpts"]) + \
        acct["per_excerpt_overhead_tokens"] * len(p["excerpts"])
    check("used == recomputed exactly", acct["used"] == recomputed, "%s vs %s" % (acct["used"], recomputed))
    budget_omits = any(o["reason"] == "token_budget" for o in p["omitted_context"])
    check("truncated flag set when something dropped for budget",
          (acct["truncated"] and acct["budget_exhausted"]) == budget_omits)
    check("budget actually forced omissions", any(o["reason"] == "token_budget" for o in p["omitted_context"]),
          "no token_budget omission at budget=90")

# ------------------------------------------------------- (b) provenance reproduces source -------
def test_provenance():
    print("[acceptance b: every excerpt span reproduces its source text]")
    case = load("compile_case.json")
    meta = cc.run(case)
    p = meta["result"]["packet"]
    corpus = case["source_texts"]
    all_ok = True
    for e in p["excerpts"]:
        sp = e["source_path"]; span = e["span"]
        raw = corpus[sp].encode("utf-8")[span["start"]:span["end"]].decode("utf-8")
        ok = (raw == e["text"]) and e["provenance"]["reproduced"] and \
            (e["provenance"]["span_sha256"] == sha256_hex(raw))
        if not ok:
            all_ok = False
            print("      excerpt mismatch:", sp, span, e["provenance"])
    check("all excerpt spans reproduce cited text", all_ok)
    check("provenance_reproduced_all metric true", p["evaluation_hooks"]["packet_metrics"]["provenance_reproduced_all"])
    # chunk provenance was checked against chunk_content_hash
    checked = set(e["provenance"]["checked_against"] for e in p["excerpts"] if e["record_kind"] == "source_chunk")
    check("source_chunk checked against chunk_content_hash", checked == {"chunk_content_hash"}, str(checked))

# --------------------------------------------- (c) omitted-context + expansion affordances ------
def test_omitted_and_affordances():
    print("[acceptance c: omitted-context record + expansion affordances]")
    case = load("compile_case.json")
    case["task"]["config"]["token_budget"] = 90
    meta = cc.run(case)
    p = meta["result"]["packet"]
    check("omitted entries carry reason + rank", all("reason" in o and "rank_in_pool" in o
                                                      for o in p["omitted_context"]))
    check("budget omissions carry an expand_hint",
          all("expand_hint" in o for o in p["omitted_context"] if o["reason"] == "token_budget"))
    aff = p["expansion_affordances"]
    check("expansion affordances declared", aff["op"] == "expand" and "raw_source" in aff["request_shape"]["type"])
    # evaluation hooks record EVERY candidate with included/omit_reason
    sig = p["evaluation_hooks"]["retrieved"]
    check("eval hooks cover every candidate", len(sig) == p["evaluation_hooks"]["packet_metrics"]["candidate_count"])
    incl = set(s["record_version_id"] for s in sig if s["included"])
    exc = set(e["record_version_id"] for e in p["excerpts"])
    check("eval-hook included set == excerpts", incl == exc)

# --------------------------------------------- (d) byte-identical re-run (deterministic id) ------
def test_determinism():
    print("[acceptance d: byte-identical re-run + deterministic packet_id]")
    case = load("compile_case.json")
    m1 = cc.run(case)
    m2 = cc.run(load("compile_case.json"))
    p1, p2 = m1["result"]["packet"], m2["result"]["packet"]
    check("packet_id identical", p1["packet_id"] == p2["packet_id"], "%s vs %s" % (p1["packet_id"], p2["packet_id"]))
    check("canonical packet bytes identical", cc.canonical_json(p1) == cc.canonical_json(p2))
    # packet_id is the content hash of the packet body (minus the id itself)
    body = {k: v for k, v in p1.items() if k != "packet_id"}
    check("packet_id == cpkt_+sha256(body)[:32]",
          p1["packet_id"] == "cpkt_" + cc.sha256_of_obj(body)[:32])
    # no volatile fields leaked into the packet
    blob = cc.canonical_json(p1)
    check("no wall-clock/run-id leaked", ("created_by_ingest_run" not in blob) and ("abs_path" not in blob))

# --------------------------------------------- (e) diversity cap protects a required source ------
def test_diversity():
    print("[acceptance e: 10 near-dups do NOT crowd out a distinct required source]")
    case = load("diversity_case.json")
    required = case["_required_rvid"]; near_src = case["_near_source"]
    meta = cc.run(case)
    p = meta["result"]["packet"]
    exc_rvids = set(e["record_version_id"] for e in p["excerpts"])
    check("required distinct source IS included", required in exc_rvids,
          "required missing; excerpts=%s" % sorted(exc_rvids))
    near_included = sum(1 for e in p["excerpts"] if e["source_path"] == near_src)
    check("near-dup source capped at per_source_cap",
          near_included <= case["task"]["config"]["per_source_cap"], "near_included=%d" % near_included)
    check("overflow near-dups omitted with source_diversity_cap reason",
          any(o["reason"] == "source_diversity_cap" for o in p["omitted_context"]))
    # determinism holds here too
    p2 = cc.run(load("diversity_case.json"))["result"]["packet"]
    check("diversity packet deterministic", p["packet_id"] == p2["packet_id"])

def test_dedup_identical():
    print("[diversity: identical content dedups by content hash]")
    # two hits with identical chunk_content_hash -> one kept, one omitted duplicate_content
    txt = "identical chunk text for dedup.\n"
    corpus = {"core-docs/d.md": txt}
    b = txt.encode("utf-8")
    h = {
        "record_id": "d1", "record_version_id": "d1v", "record_kind": "source_chunk",
        "source_path": "core-docs/d.md", "content_hash": sha256_hex(b),
        "chunk_content_hash": sha256_hex(b), "span": {"start": 0, "end": len(b)},
        "span_label": "d", "currentness": "current", "authority_level": "source_material",
        "namespace": "core-docs", "rank": 1, "fused_score": 0.9, "tie_break_key": "d1v",
    }
    h2 = dict(h); h2["record_id"] = "d2"; h2["record_version_id"] = "d2v"; h2["rank"] = 2; h2["tie_break_key"] = "d2v"
    args = {"op": "compile", "task": {"original_goal": "g", "request_text": "identical chunk",
            "config": {"token_budget": 500}},
            "retrieval_batches": [{"query_index": 0, "hits": [h, h2]}], "source_texts": corpus}
    p = cc.run(args)["result"]["packet"]
    check("one excerpt kept", len(p["excerpts"]) == 1)
    check("duplicate omitted with duplicate_content", any(o["reason"] == "duplicate_content"
          for o in p["omitted_context"]))

def test_stale_demotion_and_deleted():
    print("[8.3 s5: stale demotion + deleted drop]")
    txt = "alpha current text.\nbeta stale text.\ngamma deleted text.\n"
    corpus = {"core-docs/s.md": txt}
    b = txt.encode("utf-8")
    def mk(sub, rvid, cur, rank):
        i = b.index(sub.encode("utf-8")); j = i + len(sub.encode("utf-8"))
        return {"record_id": rvid, "record_version_id": rvid, "record_kind": "source_chunk",
                "source_path": "core-docs/s.md", "content_hash": sha256_hex(b),
                "chunk_content_hash": sha256_hex(b[i:j]), "span": {"start": i, "end": j},
                "span_label": sub, "currentness": cur, "authority_level": "source_material",
                "namespace": "core-docs", "rank": rank, "fused_score": 0.9, "tie_break_key": rvid}
    cur = mk("alpha current text.", "cur", "current", 2)
    stale = mk("beta stale text.", "stale", "source_stale", 1)   # better rank but stale
    deleted = mk("gamma deleted text.", "del", "deleted", 1)
    args = {"op": "compile", "task": {"original_goal": "g", "request_text": "text",
            "task_type": "documentation", "config": {"token_budget": 500}},
            "retrieval_batches": [{"query_index": 0, "hits": [cur, stale, deleted]}], "source_texts": corpus}
    p = cc.run(args)["result"]["packet"]
    order = [e["record_version_id"] for e in p["excerpts"]]
    check("deleted dropped", "del" not in order and any(o["reason"] == "deleted" for o in p["omitted_context"]))
    check("current ranks above stale despite worse retrieval rank", order.index("cur") < order.index("stale"),
          "order=%s" % order)

# ---------------------------------------------------------- expand op (8.5) ---------------------
def test_expand():
    print("[acceptance -Live shape: expand returns bounded raw source behind a summary]")
    case = load("expand_case.json")
    cm = cc.run(case["compile_args"])
    packet = cm["result"]["packet"]
    args = {"op": "expand", "packet": packet, "request": case["expand_request"],
            "expansion_candidates": case["expansion_candidates"], "source_texts": case["source_texts"]}
    meta = cc.run(args)
    check("expand ok", meta["ok"], json.dumps(meta))
    exp = meta["result"]["expansion"]
    check("expansion has evidence", exp["evidence_count"] >= 1)
    ev = exp["evidence"][0]
    check("evidence has provenance", "provenance" in ev)
    # bounded: token estimate within budget; and it was truncated (raw is larger than 40 tokens)
    check("expansion bounded within budget", exp["token_estimate"] <= exp["budget_tokens"],
          json.dumps({"est": exp["token_estimate"], "budget": exp["budget_tokens"]}))
    check("expansion truncated (raw bigger than budget)", exp["truncated"] and ev["truncated"])
    # provenance of the bounded slice reproduces from the source (prefix check)
    corpus = case["source_texts"]
    raw_hit = case["expansion_candidates"][0]
    sp = raw_hit["source_path"]; span = raw_hit["span"]
    full = corpus[sp].encode("utf-8")[span["start"]:span["end"]].decode("utf-8")
    check("bounded evidence is a prefix of the true source span", full.startswith(ev["text"]))
    check("expand deterministic", cc.run(args)["result"]["expansion"]["expansion_id"] == exp["expansion_id"])
    # invalid type fails closed
    bad = dict(args); bad["request"] = {"type": "nope", "target": {}}
    check("invalid expand type fails closed", cc.run(bad)["ok"] is False)

def test_error_paths():
    print("[fail-closed error paths]")
    check("unknown op", cc.run({"op": "frobnicate"})["ok"] is False)
    # empty candidate pool -> a valid (empty-evidence) packet, not a crash
    m = cc.run({"op": "compile", "task": {"original_goal": "g", "request_text": "nothing matches"},
                "retrieval_batches": []})
    check("empty pool -> valid packet", m["ok"] and len(m["result"]["packet"]["excerpts"]) == 0)
    check("empty-pool packet still deterministic id", m["result"]["packet"]["packet_id"].startswith("cpkt_"))

def main():
    print("== context.compile off-machine test gate ==")
    for t in (test_primitives, test_normalize, test_budget_accounting, test_provenance,
              test_omitted_and_affordances, test_determinism, test_diversity, test_dedup_identical,
              test_stale_demotion_and_deleted, test_expand, test_error_paths):
        t()
    total = _passed + _failed
    print("\n== %d/%d passed, %d failed ==" % (_passed, total, _failed))
    return 1 if _failed else 0

if __name__ == "__main__":
    sys.exit(main())
