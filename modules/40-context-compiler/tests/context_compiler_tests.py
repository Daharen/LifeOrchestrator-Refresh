#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Off-machine deterministic test gate for context.compile 0.2 (Module 40, i30 CONTRACT-HARDENING).

CPU-only, stdlib-only, mock retriever seam (fixture 0.2 hits). Fail-closed: exits non-zero on any
failure. Covers the work-order ACCEPTANCE items (a)-(g):
  (a) three regions structurally separated + a passing INJECTION unit test (P0-1)
  (b) packet_disposition correct across answerable / needs_expansion / abstain / conflicted /
      provenance_failed fixtures (P0-3)
  (c) consumer_profile + count_is_exact=false + fail-closed transport (oversize evidence -> omission,
      disposition=needs_expansion, control_plane + completion_contract intact) (P0-4)
  (d) selection via the s4 selpol interface (reference impl): additive fields, retrieval order preserved (P1-1)
  (e) A2 provenance modes present + each direct_span excerpt reproduces its source bytes (P0-2)
  (f) BYTE-IDENTICAL on re-run + deterministic packet_id covering the new identity fields (P1-5)
  (g) non_execution:true present
plus: selpol/RRF, corpus_version pin (abort on drift), A3 summary skill cards, expand/0.2 immutable
locked-snapshot delta, diversity cap, and fail-closed error paths.
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
import selpol_reference as selpol  # noqa: E402

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

def compile_case(name):
    if not name.endswith(".json"):
        name = name + ".json"
    return cc.run(dict(load(name), op="compile"))

# ----------------------------------------------------------------------------- primitives -------
def test_primitives():
    print("[primitives]")
    check("canonical_json sorts keys", cc.canonical_json({"b": 1, "a": 2}) == '{"a":2,"b":1}')
    check("est_tokens ceil(chars/4)", cc.est_tokens("abcde") == 2 and cc.est_tokens("") == 0)
    check("to_micros deterministic", cc.to_micros(0.5) == 500000 and cc.to_micros(None) is None)
    check("packet schema is 0.2", cc.PACKET_SCHEMA == "lifeorch.context_packet/0.2")
    check("expansion schema is 0.2", cc.EXPANSION_SCHEMA == "lifeorch.context_expansion/0.2")

# ----------------------------------------------------------------------------- normalize --------
def test_normalize():
    print("[normalize 8.1]")
    case = load("compile_case.json")
    meta = cc.run({"op": "normalize", "task": case["task"]})
    check("normalize ok", meta["ok"], json.dumps(meta))
    r = meta["result"]
    check("original_goal preserved verbatim", r["original_goal"] == case["task"]["original_goal"])
    qs = r["query_set"]
    check("query_set nonempty + bounded", 0 < len(qs) <= cc.DEFAULT_CONFIG["max_queries"])
    modes = set(q["mode"] for q in qs)
    check("has fts + exact queries", "fts" in modes and "exact" in modes, str(modes))

# ------------------------------------------------------ (P0-1) three regions + injection --------
def test_three_regions():
    print("[acceptance a: P0-1 three structurally-separated regions]")
    p = compile_case("compile_case.json")["result"]["packet"]
    for region in ("control_plane", "task_input", "evidence"):
        check("region present: " + region, region in p)
    check("control_plane provenance = descriptor-only",
          p["control_plane"]["provenance"] == "descriptor_authority_fields_only")
    check("task_input original_goal verbatim",
          p["task_input"]["original_goal"] == load("compile_case.json")["task"]["original_goal"])
    ev = p["evidence"]["excerpts"]
    check("every excerpt content_role=evidence", all(e["content_role"] == "evidence" for e in ev))
    check("every excerpt can_instruct=false", all(e["can_instruct"] is False for e in ev))
    check("every excerpt carries trust_domain + epistemic_authority",
          all("trust_domain" in e and "epistemic_authority" in e for e in ev))
    check("requested_side_effects in task_input (a request)",
          "requested_side_effects" in p["task_input"])
    check("permission_grants live ONLY in control_plane",
          "permission_grants" in p["control_plane"] and "permission_grants" not in p["task_input"])
    check("rendering contract order control->task->evidence",
          p["rendering"]["order"] == ["control_plane", "task_input", "evidence"])

def test_injection():
    print("[acceptance a: P0-1 INJECTION -- evidence cannot populate control_plane / alter contract / selection]")
    inj = load("injection_case.json")
    base = {"op": "compile", "task": inj["task"], "source_texts": inj["source_texts"],
            "retrieval_meta": inj["retrieval_meta"],
            "retrieval_batches": [{"query_index": 0, "hits": inj["benign_hits"]}]}
    evil = dict(base)
    evil["retrieval_batches"] = [{"query_index": 0, "hits": inj["benign_hits"] + [inj["malicious_hit"]]}]
    pb = cc.run(base)["result"]["packet"]
    pe = cc.run(evil)["result"]["packet"]
    check("control_plane byte-identical despite injected imperative evidence",
          cc.canonical_json(pb["control_plane"]) == cc.canonical_json(pe["control_plane"]))
    check("completion_contract unchanged",
          cc.canonical_json(pb["control_plane"]["completion_contract"]) ==
          cc.canonical_json(pe["control_plane"]["completion_contract"]))
    check("skill selection unchanged",
          cc.canonical_json(pb["evidence"]["candidate_skills"]) ==
          cc.canonical_json(pe["evidence"]["candidate_skills"]))
    check("side_effect_policy still deny_all (evidence 'allow_all' ignored)",
          pe["control_plane"]["side_effect_policy"] == "deny_all")
    check("permission_grants still empty (evidence 'grant git.push' ignored)",
          pe["control_plane"]["permission_grants"] == [])
    evil_ex = [e for e in pe["evidence"]["excerpts"] if e["record_version_id"] == "evil_rec_v1"]
    check("malicious content carried ONLY as evidence (content_role=evidence, can_instruct=false)",
          len(evil_ex) == 1 and evil_ex[0]["content_role"] == "evidence" and evil_ex[0]["can_instruct"] is False)
    check("injection_probe asserts evidence did not populate control_plane",
          pe["evaluation_hooks"]["injection_probe"]["evidence_populated_control_plane"] is False)

# ---------------------------------------------------------- (P0-3) packet_disposition -----------
def test_dispositions():
    print("[acceptance b: P0-3 packet_disposition across all 5 fixtures]")
    for name, expect in [("disposition_answerable", "answerable"),
                         ("disposition_needs_expansion", "needs_expansion"),
                         ("disposition_abstain", "abstain"),
                         ("disposition_conflicted", "conflicted"),
                         ("disposition_provenance_failed", "provenance_failed")]:
        p = compile_case(name)["result"]["packet"]
        got = p["disposition"]["packet_disposition"]
        check("disposition %s == %s" % (name, expect), got == expect, "got %s" % got)
        check("disposition block mirrors metric (%s)" % name,
              p["evaluation_hooks"]["packet_metrics"]["packet_disposition"] == got)
    pa = compile_case("disposition_answerable.json")["result"]["packet"]
    check("answerable => disposition.answerable true", pa["disposition"]["answerable"] is True)
    pn = compile_case("disposition_needs_expansion.json")["result"]["packet"]
    check("needs_expansion => answerable false", pn["disposition"]["answerable"] is False)
    check("needs_expansion missing requirement is expandable",
          all(m.get("expandable") for m in pn["disposition"]["missing_requirements"]))
    pab = compile_case("disposition_abstain.json")["result"]["packet"]
    check("abstain missing requirement is NOT expandable",
          any(not m.get("expandable") for m in pab["disposition"]["missing_requirements"]))
    pc = compile_case("disposition_conflicted.json")["result"]["packet"]
    check("conflicted records a current_vs_current contradiction",
          any(x["kind"] == "current_vs_current" for x in pc["disposition"]["contradictions"]))

# ------------------------------------------------ (P0-4) consumer_profile + transport -----------
def test_consumer_profile_and_transport():
    print("[acceptance c: P0-4 consumer_profile + fail-closed transport]")
    p = compile_case("compile_case.json")["result"]["packet"]
    prof = p["consumer_profile"]
    for k in ("model_id", "tokenizer_id", "tokenizer_fingerprint", "chat_template_id",
              "max_context", "reserved_system_tokens", "reserved_tool_tokens", "reserved_generation_tokens"):
        check("consumer_profile has " + k, k in prof)
    ta = p["transport_accounting"]
    check("count on FINAL RENDERED input", ta["counted_on"] == "final_rendered_input")
    check("count_method conservative_upper_bound", ta["count_method"] == "conservative_upper_bound")
    check("count_is_exact false (no real tokenizer)", ta["count_is_exact"] is False)
    check("rendered token count present", isinstance(ta["rendered_tokens"], int) and ta["rendered_tokens"] > 0)
    pt = compile_case("transport_overflow_case.json")["result"]["packet"]
    dropped = [o for o in pt["omission_manifest"] if o["reason"] == "transport_overflow"]
    check("oversize evidence dropped for transport_overflow", len(dropped) >= 1)
    check("transport disposition = needs_expansion", pt["disposition"]["packet_disposition"] == "needs_expansion")
    check("control_plane intact after transport drop", "completion_contract" in pt["control_plane"])
    check("completion_contract intact after transport drop",
          pt["control_plane"]["completion_contract"].get("goal") ==
          load("transport_overflow_case.json")["task"]["original_goal"])
    # fail-closed-by-dropping: the packet RECOVERS to fit by shedding evidence (never truncates the
    # control frame); the signal is the transport drop + the conservative re-disposition, not a lie about budget.
    check("transport forced >=1 evidence drop", pt["transport_accounting"]["dropped_for_transport"] >= 1)
    check("control frame itself did NOT overflow (never truncated)",
          pt["transport_accounting"]["control_plane_overflow"] is False)
    check("packet recovered to fit after shedding evidence", pt["transport_accounting"]["fits"] is True)

# --------------------------------------------------- (P1-1) selpol s4 interface -----------------
def test_selpol_interface():
    print("[acceptance d: P1-1 selection via the s4 select() interface -- additive, order-preserving]")
    p = compile_case("compile_case.json")["result"]["packet"]
    check("selection policy_id = selpol_rrf_v1", p["selection"]["policy_id"] == "selpol_rrf_v1")
    check("selection policy_version present", bool(p["selection"]["policy_version"]))
    for e in p["evidence"]["excerpts"]:
        s = e["selection"]
        check("excerpt selection has selection_rank+score+policy",
              all(k in s for k in ("selection_rank", "selection_score", "selection_policy_id", "reason_codes")),
              str(list(s.keys())))
        check("excerpt preserves retrieval_rank/lexical/vector/fused",
              all(k in s for k in ("retrieval_rank", "lexical_rank", "vector_rank", "fused_rank")))
    cands = [{"record_version_id": "r1", "authority_level": "source_material", "currentness": "current",
              "retrieval_rank": 1, "lexical_rank": 1, "fused_rank": 1, "vector_rank": None,
              "excerpt_hash": "h1", "retrieval_occurrences": [{"query_index": 0, "rank": 1, "fused_rank": 1}]},
             {"record_version_id": "r2", "authority_level": "source_material", "currentness": "current",
              "retrieval_rank": 2, "lexical_rank": 2, "fused_rank": 2, "vector_rank": None,
              "excerpt_hash": "h2", "retrieval_occurrences": [{"query_index": 0, "rank": 2, "fused_rank": 2}]}]
    out = selpol.select(cands, {"time_horizon": "current_only"})
    check("select returns the frozen shape",
          all(k in out for k in ("selected", "ranked", "policy_id", "policy_version", "features_by_candidate")))
    check("select preserves retrieval order (r1 before r2)",
          [r["record_version_id"] for r in out["ranked"]] == ["r1", "r2"])
    check("select marks selected reps", out["selected"] == ["r1", "r2"])
    dup = [dict(cands[0]), dict(cands[1])]; dup[1]["excerpt_hash"] = "h1"
    out2 = selpol.select(dup, {"time_horizon": "current_only"})
    capped = [r for r in out2["ranked"] if "diversity_capped" in r["reason_codes"]]
    check("identical display text is diversity_capped (provenance kept)", len(capped) == 1)
    fb = [dict(cands[0]), dict(cands[1])]
    out3 = selpol.select(fb, {"forbidden_sources": [], "time_horizon": "current_only"})
    check("no forbidden -> none hard-filtered", all(not r["hard_filtered"] for r in out3["ranked"]))

def test_selpol_stale_demote():
    print("[P1-1: temporal demote -- current outranks a better-ranked stale under current_only]")
    stale = {"record_version_id": "stale", "authority_level": "source_material", "currentness": "source_stale",
             "retrieval_rank": 1, "fused_rank": 1, "excerpt_hash": "s",
             "retrieval_occurrences": [{"query_index": 0, "rank": 1, "fused_rank": 1}]}
    cur = {"record_version_id": "cur", "authority_level": "source_material", "currentness": "current",
           "retrieval_rank": 2, "fused_rank": 2, "excerpt_hash": "c",
           "retrieval_occurrences": [{"query_index": 0, "rank": 2, "fused_rank": 2}]}
    out = selpol.select([stale, cur], {"time_horizon": "current_only"})
    order = [r["record_version_id"] for r in out["ranked"]]
    check("current ranks above stale despite worse retrieval rank", order.index("cur") < order.index("stale"), str(order))
    check("stale row carries stale_demote reason",
          any("stale_demote" in r["reason_codes"] for r in out["ranked"] if r["record_version_id"] == "stale"))

# --------------------------------------------------- (P0-2) provenance modes --------------------
def test_provenance_modes():
    print("[acceptance e: P0-2 provenance modes + direct_span reproduces source bytes]")
    case = load("compile_case.json")
    p = cc.run(dict(case, op="compile"))["result"]["packet"]
    corpus = case["source_texts"]
    for e in p["evidence"]["excerpts"]:
        prov = e["provenance"]
        check("excerpt has A2 hash names",
              all(k in prov for k in ("record_content_hash", "source_content_hash", "excerpt_hash")))
        check("excerpt has provenance_mode", prov["provenance_mode"] in
              (cc.PROV_DIRECT_SPAN, cc.PROV_DERIVED, cc.PROV_AGGREGATE, cc.PROV_TOMBSTONE))
        if prov["provenance_mode"] == cc.PROV_DIRECT_SPAN:
            sp = e["source_path"]; span = e["span"]
            raw = corpus[sp].encode("utf-8")[span["start"]:span["end"]].decode("utf-8")
            check("direct_span reproduces cited text", raw == e["text"] and prov["reproduced"])
            check("direct_span checked against excerpt_hash", prov["checked_against"] == "excerpt_hash")
    check("provenance_reproduced_all metric true",
          p["evaluation_hooks"]["packet_metrics"]["provenance_reproduced_all"])
    pf = compile_case("disposition_provenance_failed.json")["result"]["packet"]
    check("broken direct_span -> reproduced false",
          any(not e["provenance"]["reproduced"] for e in pf["evidence"]["excerpts"]))

# --------------------------------------------------- (P1-5) identity + determinism --------------
def test_identity_and_determinism():
    print("[acceptance f/g: deterministic packet_id covering identity + non_execution]")
    m1 = compile_case("compile_case.json")
    m2 = compile_case("compile_case.json")
    p1, p2 = m1["result"]["packet"], m2["result"]["packet"]
    check("packet_id identical", p1["packet_id"] == p2["packet_id"])
    check("canonical packet bytes identical", cc.canonical_json(p1) == cc.canonical_json(p2))
    body = {k: v for k, v in p1.items() if k != "packet_id"}
    check("packet_id == cpkt_+sha256(body)[:32]", p1["packet_id"] == "cpkt_" + cc.sha256_of_obj(body)[:32])
    ident = p1["identity"]
    for k in ("task_id", "corpus_version", "compiler_version", "selection_policy",
              "consumer_profile", "control_plane_grant_snapshot_ref", "selected_record_version_ids",
              "budget", "omission_manifest_digest"):
        check("identity covers " + k, k in ident)
    check("result payload exposes packet_content_hash",
          m1["result"]["packet_content_hash"] == "sha256:" + cc.sha256_of_obj(body))
    altcase = load("compile_case.json"); altcase["task"]["consumer_profile"] = {"max_context": 4096}
    palt = cc.run(dict(altcase, op="compile"))["result"]["packet"]
    check("consumer_profile change alters packet_id (identity coverage)",
          palt["packet_id"] != p1["packet_id"])
    check("non_execution true (g)", p1["non_execution"] is True)
    blob = cc.canonical_json(p1)
    check("no wall-clock/run-id/abs_path leaked",
          ("created_by_ingest_run" not in blob) and ("abs_path" not in blob))

def test_corpus_pin():
    print("[P1-5: one corpus_version per compile -- ABORT on drift]")
    m = cc.run(dict(load("corpus_drift_case.json"), op="compile"))
    check("corpus drift aborts (no half-snapshot packet)",
          (not m["ok"]) and m.get("error_code") == "corpus_drift", json.dumps(m))

# --------------------------------------------------- omission_manifest + diversity --------------
def test_omission_and_diversity():
    print("[omission_manifest + diversity cap (renamed from omitted_context)]")
    case = load("compile_case.json"); case["task"]["config"]["token_budget"] = 90
    p = cc.run(dict(case, op="compile"))["result"]["packet"]
    check("omission_manifest present (renamed)", "omission_manifest" in p and "omitted_context" not in p)
    check("budget omissions carry an expand_hint",
          all("expand_hint" in o for o in p["omission_manifest"] if o["reason"] == "token_budget"))
    check("some evidence dropped for token_budget",
          any(o["reason"] == "token_budget" for o in p["omission_manifest"]))
    dc = load("diversity_case.json")
    pd = cc.run(dict(dc, op="compile"))["result"]["packet"]
    exc = set(e["record_version_id"] for e in pd["evidence"]["excerpts"])
    check("required distinct source included", dc["_required_rvid"] in exc)
    near = sum(1 for e in pd["evidence"]["excerpts"] if e["source_path"] == dc["_near_source"])
    check("near-dup source capped at per_source_cap", near <= dc["task"]["config"]["per_source_cap"])
    check("overflow near-dups omitted source_diversity_cap",
          any(o["reason"] == "source_diversity_cap" for o in pd["omission_manifest"]))

# --------------------------------------------------- A3 skill activation cards ------------------
def test_a3_skill_cards():
    print("[A3: skill.card summary records recognised as skill candidates]")
    a3 = load("skill_card_summary_case.json")
    p = cc.run(dict(a3, op="compile"))["result"]["packet"]
    rvids = set(r["record_version_id"] for r in p["evidence"]["candidate_skills"])
    check("summary skill_activation_card recognised", a3["_summary_skill_rvid"] in rvids)
    check("structural skill record recognised", a3["_structural_skill_rvid"] in rvids)
    kinds = set(r.get("skill_card_kind") for r in p["evidence"]["candidate_skills"])
    check("both summary + skill card kinds present", kinds == {"summary", "skill"}, str(kinds))

# --------------------------------------------------- eval hooks ---------------------------------
def test_eval_hooks():
    print("[evaluation_hooks: per-stage + disposition + injection probe]")
    p = compile_case("compile_case.json")["result"]["packet"]
    eh = p["evaluation_hooks"]
    check("stages: raw_retrieval/post_filter/packet present",
          all(k in eh["stages"] for k in ("raw_retrieval", "post_filter", "packet")))
    check("disposition_eval present", "packet_disposition" in eh["disposition_eval"])
    check("injection_probe present", eh["injection_probe"]["control_plane_source"] == "descriptor_authority_fields_only")
    sig = eh["retrieved"]
    check("eval hooks cover every candidate", len(sig) == eh["packet_metrics"]["candidate_count"])
    incl = set(s["record_version_id"] for s in sig if s["included"])
    exc = set(e["record_version_id"] for e in p["evidence"]["excerpts"])
    check("eval-hook included set == excerpts", incl == exc)

# --------------------------------------------------- expand op (8.5) / 0.2 ----------------------
def test_expand():
    print("[expand -> lifeorch.context_expansion/0.2 immutable delta, corpus snapshot LOCKED]")
    case = load("expand_case.json")
    cm = cc.run(dict(case["compile_args"], op="compile"))
    packet = cm["result"]["packet"]
    args = {"op": "expand", "packet": packet, "request": case["expand_request"],
            "expansion_candidates": case["expansion_candidates"], "source_texts": case["source_texts"]}
    meta = cc.run(args)
    check("expand ok", meta["ok"], json.dumps(meta))
    exp = meta["result"]["expansion"]
    check("expansion schema 0.2", exp["schema"] == "lifeorch.context_expansion/0.2")
    check("expansion immutable", exp["immutable"] is True)
    check("expansion parent_packet_id set", exp["parent_packet_id"] == packet["packet_id"])
    check("corpus snapshot locked to parent",
          exp["corpus_snapshot"]["locked_to_parent"] is True and
          exp["corpus_snapshot"]["corpus_version"] == packet["identity"]["corpus_version"])
    check("expansion has depth bound", exp["depth"] <= exp["depth_bound"])
    check("expansion bounded within budget", exp["token_estimate"] <= exp["budget_tokens"])
    check("expansion evidence carries provenance + can_instruct=false",
          all("provenance" in e and e["can_instruct"] is False for e in exp["evidence"]))
    check("expand deterministic", cc.run(args)["result"]["expansion"]["expansion_id"] == exp["expansion_id"])
    bad = dict(args); bad["request"] = dict(case["expand_request"], depth=5, depth_bound=1)
    check("expand depth beyond bound fails closed", cc.run(bad)["ok"] is False)
    bad2 = dict(args); bad2["request"] = {"type": "nope", "target": {}}
    check("invalid expand type fails closed", cc.run(bad2)["ok"] is False)

def test_error_paths():
    print("[fail-closed error paths]")
    check("unknown op", cc.run({"op": "frobnicate"})["ok"] is False)
    m = cc.run({"op": "compile", "task": {"original_goal": "g", "request_text": "nothing matches"},
                "retrieval_batches": []})
    check("empty pool -> valid packet", m["ok"] and len(m["result"]["packet"]["evidence"]["excerpts"]) == 0)
    check("empty-pool packet still deterministic id", m["result"]["packet"]["packet_id"].startswith("cpkt_"))
    check("empty-pool packet is non_execution", m["result"]["packet"]["non_execution"] is True)

def main():
    print("== context.compile 0.2 off-machine test gate ==")
    for t in (test_primitives, test_normalize, test_three_regions, test_injection,
              test_dispositions, test_consumer_profile_and_transport, test_selpol_interface,
              test_selpol_stale_demote, test_provenance_modes, test_identity_and_determinism,
              test_corpus_pin, test_omission_and_diversity, test_a3_skill_cards, test_eval_hooks,
              test_expand, test_error_paths):
        t()
    total = _passed + _failed
    print("\n== %d/%d passed, %d failed ==" % (_passed, total, _failed))
    return 1 if _failed else 0

if __name__ == "__main__":
    sys.exit(main())
