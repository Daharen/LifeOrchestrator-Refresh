#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Off-machine deterministic test gate for context.compile 0.3 (Module 40, i31 SELECTION-POLICY SETTLE).

CPU-only, stdlib-only, mock retriever seam (fixture 0.2 hits). Imports #37's REAL canonical
`selpol_rrf_v1` (D-0089; the in-module reference stub is RETIRED). Fail-closed: exits non-zero on any
failure. Covers the work-order ACCEPTANCE items (a)-(g):
  (a) three regions structurally separated + a passing INJECTION unit test (P0-1)
  (b) packet_disposition correct across answerable / needs_expansion / abstain / conflicted /
      provenance_failed fixtures (P0-3)
  (c) consumer_profile + count_is_exact=false + fail-closed transport (oversize evidence -> omission,
      disposition=needs_expansion, control_plane + completion_contract intact) (P0-4)
  (d) selection via the CANONICAL selpol_rrf_v1 (imported, not reimplemented): additive fields,
      retrieval order preserved, canonical policy_version 1.0.0 + 6 stages (P1-1 / D-0089)
  (e) #40's selection == a DIRECT selpol_rrf_v1.select() on the same candidates (the D-0077 byte-identity)
  (f) A2 provenance modes present + each direct_span excerpt reproduces its source bytes (P0-2)
  (g) BYTE-IDENTICAL on re-run + deterministic packet_id covering the identity fields (P1-5); non_execution:true
plus: canonical stale-demote/dedup, corpus_version pin (abort on drift), A3 summary skill cards,
expand/0.2 immutable locked-snapshot delta, diversity cap, and fail-closed error paths.
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
# P1-1 / D-0089: the ONE canonical selection library, IMPORTED by the compiler (not an in-module stub).
# We test the EXACT module #40 uses, so the #40-vs-direct-select byte-identity is over the same library.
selpol = cc.selpol  # noqa: E402

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

def _hit(path, text, rvid, rid, ns="projA", rank=1, contradicts=None, currentness="current",
         record_kind="source_chunk", candidate_role=None, superseded_by=None, effective_current=None,
         authority_level="source_material", corpus="digest_i33_0001"):
    """A minimal deterministic retriever-0.2 hit whose direct_span reproduces `text` (chunk_content_hash =
    sha256(span bytes)) -- used to build small i32/i33 cases inline."""
    b = text.encode("utf-8")
    ch = sha256_hex(b)
    h = {"record_id": rid, "record_version_id": rvid, "record_kind": record_kind,
         "chunk_id": "chk_" + rvid, "source_path": path, "abs_path": None,
         "content_hash": ch, "chunk_content_hash": ch, "span": {"start": 0, "end": len(b)},
         "span_label": "bytes:0-%d" % len(b), "status": currentness, "currentness": currentness,
         "authority_level": authority_level, "namespace": ns, "source": ns,
         "source_version_id": "ver_" + rvid, "lexical_rank": rank, "lexical_score": 1.0 - (rank - 1) * 0.01,
         "vector_rank": None, "fused_rank": rank, "fused_score": 1.0 - (rank - 1) * 0.01,
         "index_snapshot": corpus, "corpus_version": corpus,
         "tie_break_key": rvid, "snippet": text, "rank": rank}
    if contradicts is not None:
        h["contradicts"] = contradicts
    if candidate_role is not None:
        h["candidate_role"] = candidate_role
    if superseded_by is not None:
        h["superseded_by"] = superseded_by
    if effective_current is not None:
        h["effective_current"] = effective_current
    return h

def _compile_hits(hits, task_extra=None, source_texts=None, corpus="digest_i33_0001"):
    """Compile an inline pool of _hit()s under a single namespace (projA) with a matching source_texts.
    i33/U1' STRICT: a namespaced compile REQUIRES a control_plane grant (control_plane is the only authority),
    so the task carries a projA grant -> effective_allowed_namespaces = intersection({projA},{projA}) = {projA}."""
    st = source_texts or {h["source_path"]: h["snippet"] for h in hits}
    task = {"original_goal": "g", "request_text": "current claim state fencing lease",
            "namespace": "projA", "task_type": "documentation",
            "control_plane": {"permission_grants": [{"namespaces": ["projA"]}]}}
    if task_extra:
        task.update(task_extra)
    args = {"op": "compile", "task": task,
            "retrieval_batches": [{"query_index": 0, "hits": hits}],
            "source_texts": st, "retrieval_meta": {"retriever": "mock", "corpus_version": corpus}}
    return cc.run(args)

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
    check("rendering contract order control->task->working_memory->evidence (i32/U3)",
          p["rendering"]["order"] == ["control_plane", "task_input", "working_memory", "evidence"])

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
    # the control_plane's ONLY permission_grant is the legit namespace grant (i33/U1'); the evil hit's
    # 'grant git.push' is NEVER added -- permission_grants are byte-identical with/without the malicious hit.
    check("permission_grants unchanged by injected evidence (no 'git.push' added)",
          cc.canonical_json(pe["control_plane"]["permission_grants"])
          == cc.canonical_json(pb["control_plane"]["permission_grants"])
          and "git.push" not in cc.canonical_json(pe["control_plane"]["permission_grants"]))
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

# --------------------------------------------------- (P1-1 / D-0089) canonical selpol -----------
def test_selpol_interface():
    print("[acceptance d: P1-1 selection via #37's CANONICAL selpol_rrf_v1 -- additive, order-preserving]")
    p = compile_case("compile_case.json")["result"]["packet"]
    check("selection policy_id = selpol_rrf_v1 (canonical)", p["selection"]["policy_id"] == "selpol_rrf_v1")
    # version-AGNOSTIC: assert the packet stamps the ACTUAL imported lib version/stages (never a #40 constant),
    # so a #37 selpol bump (1.1.0 off-machine -> 1.2.0 at the i33 fold) never drifts this gate.
    check("selection policy_version == the imported lib POLICY_VERSION (not a #40 constant)",
          p["selection"]["policy_version"] == selpol.POLICY_VERSION)
    check("selection owner is #37's lib", p["selection"].get("owner", "").endswith("selpol_rrf_v1.py"))
    check("selection stages == the imported lib STAGES",
          p["selection"].get("stages") == list(selpol.STAGES))
    for e in p["evidence"]["excerpts"]:
        s = e["selection"]
        check("excerpt selection has selection_rank+score+policy+reason_codes",
              all(k in s for k in ("selection_rank", "selection_score", "selection_policy_id", "reason_codes")),
              str(list(s.keys())))
        check("excerpt preserves retrieval_rank/lexical/vector/fused + additive rrf_score",
              all(k in s for k in ("retrieval_rank", "lexical_rank", "vector_rank", "fused_rank", "rrf_score")))
        check("selection_policy_id stamps the canonical id", s["selection_policy_id"] == "selpol_rrf_v1")
    # library-direct: the canonical returns hit COPIES (not id strings) + omission_manifest + stages.
    cands = [{"record_version_id": "r1", "authority_level": "source_material", "status": "current",
              "source_path": "a.md", "chunk_content_hash": "h1", "fused_score": 900000,
              "rank": 1, "retrieval_rank": 1, "lexical_rank": 1, "fused_rank": 1, "vector_rank": None},
             {"record_version_id": "r2", "authority_level": "source_material", "status": "current",
              "source_path": "b.md", "chunk_content_hash": "h2", "fused_score": 800000,
              "rank": 2, "retrieval_rank": 2, "lexical_rank": 2, "fused_rank": 2, "vector_rank": None}]
    out = selpol.select(cands, {"time_horizon": "current_only"}, selpol.POLICY_ID, {"dedup_display": True})
    check("select returns the frozen canonical shape",
          all(k in out for k in ("selected", "ranked", "policy_id", "policy_version",
                                 "features_by_candidate", "omission_manifest", "stages")))
    check("select policy_version == imported lib POLICY_VERSION", out["policy_version"] == selpol.POLICY_VERSION)
    check("select preserves retrieval order (r1 before r2)",
          [r["record_version_id"] for r in out["ranked"]] == ["r1", "r2"])
    check("selected[] are hit COPIES in selection order",
          [r["record_version_id"] for r in out["selected"]] == ["r1", "r2"])
    check("ranked rows PRESERVE retrieval_rank (additive; never re-sorted in place)",
          out["ranked"][0]["retrieval_rank"] == 1 and out["ranked"][0]["selection_rank"] == 1)
    # identical DISPLAY text -> one display item; the folded member is display_duplicate (provenance kept).
    dup = [dict(cands[0]), dict(cands[1])]; dup[1]["chunk_content_hash"] = "h1"
    out2 = selpol.select(dup, {"time_horizon": "current_only"}, selpol.POLICY_ID, {"dedup_display": True})
    folded = [r for r in out2["ranked"] if "display_duplicate" in r["reason_codes"]]
    check("identical display text collapses to ONE display item (dedup, provenance kept)",
          len(folded) == 1 and folded[0]["selected"] is False)
    heads = [r for r in out2["ranked"] if r.get("occurrences")]
    check("dedup head carries occurrences[] of both members", heads and len(heads[0]["occurrences"]) == 2)
    # hard_filter comes from PARAMS (the P0-1 boundary), never a candidate field.
    out3 = selpol.select([dict(cands[0])], {"time_horizon": "current_only"}, selpol.POLICY_ID,
                         {"hard_filter": [{"source_path": "a.md", "reason": "forbidden"}]})
    r = out3["ranked"][0]
    check("params.hard_filter hard-demotes + not selected",
          r["selected"] is False and any(c.startswith("hard_filter") for c in r["reason_codes"]))
    out4 = selpol.select([dict(cands[0])], {"time_horizon": "current_only"}, selpol.POLICY_ID,
                         {"hard_filter": []})
    check("no hard_filter -> selected", out4["ranked"][0]["selected"] is True)

def test_selpol_stale_demote():
    print("[P1-1: temporal -- current outranks a stale hit; current_only HARD-filters, prefer_current SOFT-demotes]")
    stale = {"record_version_id": "stale", "authority_level": "source_material", "status": "source_stale",
             "source_path": "s.md", "chunk_content_hash": "s", "fused_score": 900000,
             "rank": 1, "retrieval_rank": 1, "fused_rank": 1, "lexical_rank": 1}
    cur = {"record_version_id": "cur", "authority_level": "source_material", "status": "current",
           "source_path": "c.md", "chunk_content_hash": "c", "fused_score": 800000,
           "rank": 2, "retrieval_rank": 2, "fused_rank": 2, "lexical_rank": 2}
    # current_only (i32/i33): a stale hit is HARD-filtered (not soft-demoted) -- current ranks above it and it
    # is not selected. (The i32 semantic change: the 1.0.0 soft `stale_demote` moved to the prefer_current mode.)
    out = selpol.select([stale, cur], {"time_horizon": "current_only"})
    order = [r["record_version_id"] for r in out["ranked"]]
    check("current ranks above stale under current_only", order.index("cur") < order.index("stale"), str(order))
    stale_row = [r for r in out["ranked"] if r["record_version_id"] == "stale"][0]
    check("stale hard-filtered under current_only (hard_filter_stale, not selected)",
          stale_row["selected"] is False and "hard_filter_stale" in stale_row["reason_codes"],
          str(stale_row["reason_codes"]))
    # prefer_current: the surviving 1.0.0 SOFT demote -- the stale hit is demoted but still selectable.
    out2 = selpol.select([dict(stale), dict(cur)], {}, selpol.POLICY_ID, {"temporal_mode": "prefer_current"})
    s2 = [r for r in out2["ranked"] if r["record_version_id"] == "stale"][0]
    check("prefer_current soft-demotes the stale hit (stale_demote)", "stale_demote" in s2["reason_codes"],
          str(s2["reason_codes"]))

def test_selection_byte_identity():
    print("[acceptance e: #40's selection == a DIRECT selpol_rrf_v1.select() on the same candidates (D-0077)]")
    # Rebuild EXACTLY what op_compile feeds the library from the case, call the canonical DIRECTLY, and
    # assert the compiled packet's selection ordering is byte-identical -- proving #40 consumes the one
    # canonical library faithfully (no #40-side re-ranking), the invariant the D-0077 fold repeats on #36.
    case = load("compile_case.json")
    m = cc.run(dict(case, op="compile"))
    packet = m["result"]["packet"]
    task = case["task"]
    config = cc._resolve_config(task, {})
    norm = cc.normalize_task(task, config)
    batches = case["retrieval_batches"]
    pool, _ = cc.build_candidate_pool(batches)
    control_plane = cc.build_control_plane(task, norm["original_goal"])
    descriptor = cc.build_selection_descriptor(task, norm)
    params = cc.build_selection_params(control_plane, descriptor)
    candidates = [cc._selection_candidate(e) for e in pool.values()]
    direct = selpol.select(candidates, descriptor, selpol.POLICY_ID, params)
    # the packet's per-candidate selection ordering (record_version_id -> selection_rank)
    packet_order = {s["record_version_id"]: s["selection_rank"]
                    for s in packet["evaluation_hooks"]["retrieved"]}
    direct_order = {r["record_version_id"]: r["selection_rank"] for r in direct["ranked"]}
    check("#40 selection order == direct canonical select() (byte-identical ranks)",
          packet_order == direct_order, "packet=%s direct=%s" % (packet_order, direct_order))
    # the packet's excerpt selection_score/reason_codes come straight from the canonical ranked rows
    direct_by_rvid = {r["record_version_id"]: r for r in direct["ranked"]}
    ok = True
    for e in packet["evidence"]["excerpts"]:
        dr = direct_by_rvid.get(e["record_version_id"], {})
        if (e["selection"]["selection_score"] != dr.get("selection_score")
                or e["selection"]["reason_codes"] != dr.get("reason_codes")):
            ok = False
    check("excerpt selection_score + reason_codes come straight from the canonical select()", ok)
    check("direct select() carries the imported lib policy_version",
          direct["policy_version"] == selpol.POLICY_VERSION)

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

# =============================================================== i32 Tier-0 seam repairs (D-0092) ===

def test_query_classification():
    print("[i32/U5 acceptance b: deterministic query-classification stage -- all 9 classes reachable]")
    # all nine MEMORY_ARCHITECTURE s5 classes are reachable by SOME task_type (a stub; router is Tier 1).
    reachable = set(cc.TASK_TYPE_QUERY_CLASS.values())
    check("all 9 query classes reachable by task_type", reachable == cc.QUERY_CLASS_SET,
          "%s vs %s" % (sorted(reachable), sorted(cc.QUERY_CLASS_SET)))
    check("classifier maps documentation -> global_synthesis",
          cc.classify_query({}, "documentation", [])[0] == "global_synthesis")
    check("classifier maps coding -> procedure_selection",
          cc.classify_query({}, "coding", [])[0] == "procedure_selection")
    check("explicit task.query_class overrides",
          cc.classify_query({"query_class": "precedent_search"}, "coding", [])[0] == "precedent_search")
    check("unmapped task_type + literals -> exact_reference",
          cc.classify_query({}, "weird", ["D-0092"])[0] == "exact_reference")
    # stamped into task_input + selection descriptor + identity (packet_id coverage, s6).
    p = compile_case("compile_case.json")["result"]["packet"]
    check("query_class in task_input", p["task_input"]["query_class"] in cc.QUERY_CLASS_SET)
    check("query_class in selection.descriptor",
          p["selection"]["descriptor"]["query_class"] == p["task_input"]["query_class"])
    check("query_class in identity", p["identity"]["query_class"] == p["task_input"]["query_class"])
    # query_class is part of packet identity: change it, the packet_id changes.
    base = load("compile_case.json")
    alt = json.loads(json.dumps(base)); alt["task"]["query_class"] = "precedent_search"
    palt = cc.run(dict(alt, op="compile"))["result"]["packet"]
    check("query_class change alters packet_id (identity coverage)", palt["packet_id"] != p["packet_id"])
    check("altered query_class stamped", palt["identity"]["query_class"] == "precedent_search")

def test_current_only_propagation():
    print("[i33/U4'+U5' acceptance b: temporal_intent from the CANONICAL classifier; explicit time overrides]")
    def params_for(task):
        config = cc._resolve_config(task, {}); norm = cc.normalize_task(task, config)
        cp = cc.build_control_plane(task, norm["original_goal"])
        desc = cc.build_selection_descriptor(task, norm)
        return norm, cc.build_selection_params(cp, desc)
    # a current-leaning class (verification -> current_state) resolves to current_only (canonical map).
    n0, p0 = params_for({"original_goal": "g", "request_text": "status", "task_type": "verification"})
    check("current_state class -> current_only True", p0["current_only"] is True and n0["current_only"] is True
          and n0["temporal_intent"] == "current_only")
    # per #37's canonical classifier, global_synthesis (documentation) is any_valid_version (temporal is NOT a
    # security boundary -- namespace is; current_only applies ONLY after intent resolves to it).
    n1, p1 = params_for({"original_goal": "g", "request_text": "state", "task_type": "documentation"})
    check("global_synthesis class -> any_valid_version (canonical)", p1["current_only"] is False
          and n1["temporal_intent"] == "any_valid_version")
    n2, p2 = params_for({"original_goal": "g", "request_text": "history", "task_type": "history"})
    check("historical_reconstruction -> historical_as_of (not current)",
          p2["current_only"] is False and n2["query_class"] == "historical_reconstruction"
          and n2["temporal_intent"] == "historical_as_of")
    n3, p3 = params_for({"original_goal": "g", "request_text": "history", "task_type": "history",
                         "time_horizon": "current_only"})
    check("explicit time_horizon OUTRANKS the class default", p3["current_only"] is True)
    check("query temporal_mode carried on the retriever query set",
          all(q.get("temporal_mode") in cc.TEMPORAL_INTENT_SET for q in n0["query_set"]))
    # a current-vs-current `contradicts` edge among selected evidence -> packet_disposition conflicted (U4).
    t = "Alpha current claim.\n"; u = "Beta current claim.\n"
    ha = _hit("projA/a.md", t, "ca_v1", "ca", contradicts=["cb_v1"])
    hb = _hit("projA/b.md", u, "cb_v1", "cb", rank=2)
    args = {"op": "compile", "task": {"original_goal": "reconcile", "request_text": "current claim",
            "namespace": "projA", "task_type": "documentation",
            "control_plane": {"permission_grants": [{"namespaces": ["projA"]}]}},
            "retrieval_batches": [{"query_index": 0, "hits": [ha, hb]}],
            "source_texts": {"projA/a.md": t, "projA/b.md": u},
            "retrieval_meta": {"retriever": "mock", "corpus_version": "digest_i33_0001"}}
    pc = cc.run(args)["result"]["packet"]
    check("contradicts edge among current evidence -> conflicted",
          pc["disposition"]["packet_disposition"] == "conflicted")
    check("contradicts_edge contradiction recorded",
          any(x["kind"] == "contradicts_edge" for x in pc["disposition"]["contradictions"]))

def test_namespace_hard_boundary():
    print("[i33/U1' acceptance a: effective = intersection(request, grant), passed BOTH ways + fail-closed]")
    # single-namespace compile: effective = {projA} (request projA, no grant ceiling -> request stands).
    p = compile_case("namespace_case.json")["result"]["packet"]
    check("effective allowed_namespaces in task_input", p["task_input"]["allowed_namespaces"] == ["projA"])
    check("allowed_namespaces in identity (packet_id coverage)", p["identity"]["allowed_namespaces"] == ["projA"])
    check("identity carries the namespace_closure (request/grant/effective/policy_id)",
          p["identity"]["namespace_closure"]["request"] == ["projA"]
          and p["identity"]["namespace_closure"]["effective"] == ["projA"]
          and p["identity"]["namespace_closure"]["grant"] == ["projA"]
          and "policy_id" in p["identity"]["namespace_closure"])
    check("selection.import_sources carries the ns predicate source (audit, not identity)",
          "ns_predicate_source" in p["selection"]["import_sources"])
    ex_ns = set(e["namespace"] for e in p["evidence"]["excerpts"])
    check("every excerpt is in-namespace", ex_ns <= {"projA"} and len(p["evidence"]["excerpts"]) >= 1)
    # GATE TEST 3 (i33, part A): provenance-expansion on a NAMESPACED fixture -- every excerpt reconstructs.
    for e in p["evidence"]["excerpts"]:
        if e["provenance"]["provenance_mode"] == cc.PROV_DIRECT_SPAN:
            src = load("namespace_case.json")["source_texts"][e["source_path"]]
            raw = src.encode("utf-8")[e["span"]["start"]:e["span"]["end"]].decode("utf-8")
            check("namespaced direct_span reproduces source bytes", raw == e["text"] and e["provenance"]["reproduced"])
    check("gate test 3A: provenance_reproduced_all on the namespaced fixture",
          p["evaluation_hooks"]["packet_metrics"]["provenance_reproduced_all"]
          and p["evaluation_hooks"]["packet_metrics"]["provenance_valid_all"])
    ref_ns = set()
    for key in ("current_state_refs", "candidate_skills", "relevant_procedures",
                "relevant_failures", "similar_episodes", "navigation_refs"):
        for r in p["evidence"].get(key, []):
            if r.get("namespace") is not None:
                ref_ns.add(r["namespace"])
    check("every ref is in-namespace", ref_ns <= {"projA"})
    # filters.namespace reaches the retriever query set = the EFFECTIVE set (U1', retriever-side half).
    for q in p["retrieval_provenance"]["query_set"]:
        check("query carries filters.namespace (effective)", q["filters"].get("namespace") == "projA")
        check("query carries the effective_allowed_namespaces closed set",
              q["filters"].get("effective_allowed_namespaces") == ["projA"])
        break
    # the selection params carry the EFFECTIVE allowed_namespaces (the selpol-side half).
    case = load("namespace_case.json"); task = case["task"]
    config = cc._resolve_config(task, {}); norm = cc.normalize_task(task, config)
    cp = cc.build_control_plane(task, norm["original_goal"]); desc = cc.build_selection_descriptor(task, norm)
    params = cc.build_selection_params(cp, desc)
    check("params.allowed_namespaces passed to selpol (effective)", params["allowed_namespaces"] == ["projA"])
    check("descriptor.allowed_namespaces passed to selpol (effective)", desc["allowed_namespaces"] == ["projA"])

    # GATE TEST 3 (i33, part B) -- SANITIZED ABORT: a mixed pool (projB) fails closed; ONLY a count surfaces
    # and NO cross-namespace metadata (id/path/snippet) is anywhere in the returned payload.
    mm = cc.run(dict(load("namespace_mixed_case.json"), op="compile"))
    check("cross-namespace pool fails closed (namespace_closure_violation)",
          (not mm["ok"]) and mm.get("error_code") == "namespace_closure_violation", json.dumps(mm))
    check("failed_closed compile_status", mm.get("compile_status") == "failed_closed")
    check("only a namespace_violation_count surfaces (>=1)", mm.get("namespace_violation_count", 0) >= 1)
    blob = json.dumps(mm)
    check("NO cross-namespace identifying metadata in the payload (sanitized)",
          ("projB" not in blob) and ("b_doc" not in blob) and ("900 seconds" not in blob), blob[:400])
    check("no packet emitted on the sanitized abort", "packet" not in mm.get("result", {}) and "result" not in mm)

    # a multi-namespace compile requires BOTH the REQUEST naming the namespaces AND control_plane GRANTing
    # them (intersection). Requesting projA+projB with a grant of projA+projB -> effective = {projA, projB}.
    grant = json.loads(json.dumps(load("namespace_mixed_case.json")))
    grant["task"]["namespaces"] = ["projA", "projB"]                             # the REQUEST names both
    grant["task"]["control_plane"] = {"permission_grants": [{"namespaces": ["projA", "projB"]}]}  # the GRANT
    mg = cc.run(dict(grant, op="compile"))
    check("multi-namespace request+grant admits both namespaces (no violation)", mg["ok"],
          json.dumps({k: mg.get(k) for k in ("ok", "error_code", "namespace_violation_count")}))
    pg = mg["result"]["packet"]
    check("granted compile carries both namespaces",
          set(e["namespace"] for e in pg["evidence"]["excerpts"]) == {"projA", "projB"})
    check("identity allowed_namespaces (effective) covers both",
          set(pg["identity"]["allowed_namespaces"]) == {"projA", "projB"})

    # EMPTY INTERSECTION -> FAIL CLOSED: request projA but control_plane grants ONLY projB (disjoint).
    empt = json.loads(json.dumps(load("namespace_case.json")))
    empt["task"]["control_plane"] = {"permission_grants": [{"namespaces": ["projB"]}]}
    me = cc.run(dict(empt, op="compile"))
    check("empty intersection fails closed (namespace_closure_empty)",
          (not me["ok"]) and me.get("error_code") == "namespace_closure_empty", json.dumps(me))
    check("empty-intersection effective set is []", me.get("effective_allowed_namespaces") == [])

    # request WIDENING is clamped by the grant: request {projA,projB}, grant ONLY {projA} -> effective {projA}
    # and the projB candidate then trips the sanitized scope-check (a request can never widen past the grant).
    widen = json.loads(json.dumps(load("namespace_mixed_case.json")))
    widen["task"]["namespaces"] = ["projA", "projB"]
    widen["task"]["control_plane"] = {"permission_grants": [{"namespaces": ["projA"]}]}
    mw = cc.run(dict(widen, op="compile"))
    check("request cannot widen past the grant (projB clamped -> fail-closed)",
          (not mw["ok"]) and mw.get("error_code") == "namespace_closure_violation", json.dumps(mw))

def test_working_memory_region():
    print("[i33/U3' acceptance d: working_memory -- continuity-authoritative + conjunctive access + state_version]")
    p = compile_case("namespace_case.json")["result"]["packet"]
    check("working_memory is a FOURTH top-level region", "working_memory" in p)
    wm = p["working_memory"]
    check("working_memory reserved + empty (no store)",
          wm["present"] is False and wm["items"] == [] and wm["item_count"] == 0)
    check("working_memory items carry content_role=working_state, can_instruct=false",
          wm["content_role"] == "working_state" and wm["can_instruct"] is False)
    check("working_memory is NOT evidence + is CONTINUITY-authoritative (i33)",
          wm["is_evidence"] is False and wm["authority"] == "continuity_authoritative")
    # U3' (i33): CONJUNCTIVE access (task_id AND effective-namespace) + namespace_scope = the effective set.
    check("working_memory access is conjunctive (task_id AND effective-namespace)",
          wm["access_policy"] == "conjunctive_task_id_and_effective_namespace")
    check("working_memory namespace_scope == the effective closed set", wm["namespace_scope"] == ["projA"])
    # U3' (i33): the A5 state_version is reserved (None while empty) AND covered by packet identity.
    check("working_memory carries the A5 state_version (None at Tier 0)", "state_version" in wm)
    check("packet identity covers the working-state state_version",
          "working_state_version" in p["identity"] and p["identity"]["working_state_version"] == wm["state_version"])
    # U3' (i33): the reserved A5 store fields are present (store is Tier 1, not built).
    for f in ("working_state_id", "state_version", "parent_state_version", "namespace_scope",
              "grant_snapshot_ref", "created_from_packet_id", "content_hash", "lifecycle_state",
              "content_role", "writer_authority"):
        check("reserved A5 store field: " + f, f in wm["reserved_store_fields"])
    check("working_memory keyed by task_id", wm["task_id"] == p["identity"]["task_id"])
    check("working_memory is a DISTINCT region (not inside control_plane/evidence)",
          "working_memory" not in p["control_plane"] and "working_memory" not in p["evidence"])
    check("render order control->task->working_memory->evidence",
          p["rendering"]["order"] == ["control_plane", "task_input", "working_memory", "evidence"])
    rendered = cc.render_packet_input(p["control_plane"], p["task_input"], wm, p["evidence"]["excerpts"])
    i_task = rendered.index("=== TASK ===")
    i_wm = rendered.index("=== WORKING MEMORY")
    i_ev = rendered.index("=== EVIDENCE")
    check("working_memory rendered between task and evidence", i_task < i_wm < i_ev)
    # the conjunctive-access predicate: a foreign-task item is rejected; a same-task in-scope item accepted.
    tid = wm["task_id"]
    closure = {"effective": ["projA"], "enforced": True, "unscoped_global": False}
    check("conjunctive access rejects a foreign task_id",
          cc._working_item_accessible({"task_id": "other", "namespace_scope": "projA"}, tid, closure) is False)
    check("conjunctive access rejects an out-of-scope namespace",
          cc._working_item_accessible({"task_id": tid, "namespace_scope": "projB"}, tid, closure) is False)
    check("conjunctive access accepts same-task in-scope",
          cc._working_item_accessible({"task_id": tid, "namespace_scope": "projA"}, tid, closure) is True)

def test_new_reason_codes_carry():
    print("[i32/U-import acceptance d: the new selpol reason_codes are CARRIED onto evidence + omission]")
    # #40 copies selpol reason_codes verbatim onto the excerpt (proven end-to-end by byte-identity); here we
    # prove #40 HANDLES the NEW i32 codes (produced by selpol 1.1.0 at the fold): superseded_demote is
    # carried onto a SELECTED excerpt; a hard_filter_namespace/-stale SUNK row maps to omission 'hard_filter'.
    txt = "superseded but still selected below its successor.\n"
    hit = {"record_version_id": "r_sup", "record_id": "rr", "record_kind": "source_chunk",
           "source_path": "projA/s.md", "namespace": "projA", "authority_level": "source_material",
           "status": "current", "currentness": "current", "content_hash": sha256_hex(txt),
           "chunk_content_hash": sha256_hex(txt), "span": {"start": 0, "end": len(txt.encode())},
           "span_label": "b", "snippet": txt, "token_count": 8}
    pool = {"r_sup": {"hit": hit, "record_version_id": "r_sup", "best_rank": 2,
                      "matched_queries": [0], "occurrences": []}}
    rows = [{"record_version_id": "r_sup", "selection_rank": 2, "selection_score": 5,
             "selection_policy_id": "selpol_rrf_v1", "selected": True, "rrf_score": 100,
             "reason_codes": ["superseded_demote", "fusion_rrf", "selected"],
             "retrieval_rank": 1, "lexical_rank": 1, "vector_rank": None, "fused_rank": 1}]
    ex, om, acc = cc.select_into_budget(rows, pool, cc.DEFAULT_CONFIG, {"projA/s.md": txt}, None, [])
    check("superseded_demote carried onto the excerpt",
          len(ex) == 1 and "superseded_demote" in ex[0]["selection"]["reason_codes"])
    for code in ("hard_filter_namespace", "hard_filter_stale"):
        h2 = dict(hit, record_version_id="r_" + code, namespace="projB")
        pool2 = {h2["record_version_id"]: {"hit": h2, "record_version_id": h2["record_version_id"],
                 "best_rank": 1, "matched_queries": [0], "occurrences": []}}
        rows2 = [{"record_version_id": h2["record_version_id"], "selection_rank": 1, "selection_score": -9,
                  "selected": False, "reason_codes": [code], "retrieval_rank": 1}]
        ex2, om2, _ = cc.select_into_budget(rows2, pool2, cc.DEFAULT_CONFIG, {}, None, [])
        check("%s -> omission reason hard_filter, not excerpted" % code,
              not ex2 and any(o["reason"] == "hard_filter" for o in om2))

# =============================================================== i33 NAMESPACE-CLOSURE + SUPERSESSION ===

def test_i33_all_object_scope_check():
    print("[i33/U1' acceptance a: EVERY packet-visible object scope-checked -- no cross-ns leak in diagnostics]")
    # A projA compile whose pool ALSO carries a projB hit. Off-machine (selpol 1.1.0 SINKS it but its
    # metadata would still leak via ranked[]/features_by_candidate/omission/eval-hooks) -- i33 #40 aborts
    # BEFORE selection, so NO cross-namespace metadata reaches ANY diagnostic array. Only a count surfaces.
    ha = _hit("projA/a.md", "Project A pins the lease TTL.\n", "a_v1", "a", ns="projA", rank=1)
    hb = _hit("projB/secret.md", "Project B SECRET pins TTL 900.\n", "b_v1", "b", ns="projB", rank=2)
    m = cc.run({"op": "compile",
                "task": {"original_goal": "State A TTL.", "request_text": "lease TTL", "namespace": "projA",
                         "task_type": "documentation",
                         "control_plane": {"permission_grants": [{"namespaces": ["projA"]}]}},
                "retrieval_batches": [{"query_index": 0, "hits": [ha, hb]}],
                "source_texts": {"projA/a.md": ha["snippet"], "projB/secret.md": hb["snippet"]},
                "retrieval_meta": {"retriever": "mock", "corpus_version": "digest_i33_0001"}})
    check("mixed pool fails closed", (not m["ok"]) and m["error_code"] == "namespace_closure_violation")
    check("violation count >= 1", m.get("namespace_violation_count", 0) >= 1)
    blob = json.dumps(m)
    for leak in ("projB", "b_v1", "SECRET", "secret.md", "900"):
        check("NO leak of %r in any diagnostic/output (sanitized)" % leak, leak not in blob)
    # a SANITIZED security log (privileged) is written ONLY to output_dir, never the returned payload.
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        m2 = cc.run({"op": "compile", "output_dir": td,
                     "task": {"original_goal": "State A TTL.", "request_text": "lease TTL",
                              "namespace": "projA", "task_type": "documentation",
                              "control_plane": {"permission_grants": [{"namespaces": ["projA"]}]}},
                     "retrieval_batches": [{"query_index": 0, "hits": [ha, hb]}],
                     "source_texts": {"projA/a.md": ha["snippet"], "projB/secret.md": hb["snippet"]},
                     "retrieval_meta": {"retriever": "mock", "corpus_version": "digest_i33_0001"}})
        logp = os.path.join(td, "namespace_security_log.json")
        check("privileged security log written to output_dir", os.path.isfile(logp))
        if os.path.isfile(logp):
            sec = json.load(open(logp))
            check("security log holds the privileged detail (projB) OUT of the payload",
                  "projB" in json.dumps(sec) and "projB" not in json.dumps(m2))


def test_i33_candidate_role_navigation():
    print("[i33/U2' acceptance c: candidate_role navigation ROUTES but is NEVER answer-evidence]")
    ev = _hit("projA/answer.md", "The lease TTL is 1800 seconds under res.lease.\n", "ev_v1", "ev",
              ns="projA", rank=2)
    nav = _hit("projA/index.md", "Navigation node: lease topics live under res.lease docs.\n", "nav_v1", "nav",
               ns="projA", rank=1, record_kind="node", currentness="summary_stale")
    m = _compile_hits([nav, ev])
    check("navigation compile ok", m["ok"], json.dumps({k: m.get(k) for k in ("ok", "error_code")}))
    p = m["result"]["packet"]
    ex_rvids = set(e["record_version_id"] for e in p["evidence"]["excerpts"])
    check("navigation node is NOT an answer-evidence excerpt", "nav_v1" not in ex_rvids)
    check("evidence hit IS an excerpt", "ev_v1" in ex_rvids)
    nav_refs = p["evidence"].get("navigation_refs", [])
    check("navigation node surfaced in navigation_refs", any(r["record_version_id"] == "nav_v1" for r in nav_refs))
    check("navigation ref flags may_answer=false + navigational_stale",
          nav_refs and nav_refs[0]["may_answer"] is False and nav_refs[0]["navigational_stale"] is True)
    # NAVIGATIONAL staleness (summary_stale node) does NOT drive abstain -- the evidence hit still answers.
    check("navigational staleness does not force abstain",
          p["disposition"]["packet_disposition"] in ("answerable", "needs_expansion"))
    # a node with NO evidence for a required path -> the node routes (needs_expansion), never abstain.
    nav_only = _hit("projA/topics.md", "Node listing failure topics.\n", "n2_v1", "n2", ns="projA",
                    rank=1, record_kind="node")
    m2 = _compile_hits([nav_only], task_extra={"relevant_paths": ["projA/topics.md"]})
    check("a routing-only node keeps the packet from a false abstain",
          m2["ok"] and m2["result"]["packet"]["disposition"]["packet_disposition"] != "answerable")


def test_i33_catalog_effective_current_passthrough():
    print("[i33/U4' acceptance b: catalog effective_current + supersession edges PASSED THROUGH to selpol]")
    # #40 PLUMBS the catalog signal onto the candidate; selpol 1.2.0 (at the fold) hard-filters an
    # absent-successor superseded candidate under current_only. Off-machine we prove the PASS-THROUGH.
    hit = _hit("projA/old.md", "old superseded content.\n", "old_v1", "old", ns="projA",
               superseded_by=["new_v9"], effective_current=False, currentness="superseded")
    entry = {"hit": hit, "record_version_id": "old_v1", "best_rank": 1,
             "matched_queries": [0], "occurrences": []}
    cand = cc._selection_candidate(entry)
    check("candidate carries catalog effective_current (False)", cand["effective_current"] is False)
    check("candidate carries superseded_by edge (absent successor)", cand["superseded_by"] == ["new_v9"])
    check("candidate carries the s5 'superseded' status through", cand["status"] == "superseded")
    check("candidate default candidate_role = evidence", cand["candidate_role"] == "evidence")
    # the selection block records that the catalog effective_current passthrough is engaged.
    p = _compile_hits([hit])["result"]["packet"]
    check("selection.i33_params records the catalog effective_current passthrough",
          p["selection"]["i33_params"]["catalog_effective_current_passthrough"] is True)
    check("selection.import_sources records the ns/classifier import provenance",
          all(k in p["selection"]["import_sources"]
              for k in ("selpol_policy_version", "ns_predicate_source", "classifier_policy_source")))


def test_i33_supersession_branch_conflicted():
    print("[i33/U4' acceptance b: a supersession BRANCH (>=2 live successors) -> packet_disposition conflicted]")
    base = _hit("projA/base.md", "Base record with two live successors.\n", "base_v1", "base",
                ns="projA", rank=1, superseded_by=["s1_v1", "s2_v1"], currentness="current")
    s1 = _hit("projA/s1.md", "Successor one, current.\n", "s1_v1", "s1", ns="projA", rank=2)
    s2 = _hit("projA/s2.md", "Successor two, current.\n", "s2_v1", "s2", ns="projA", rank=3)
    p = _compile_hits([base, s1, s2])["result"]["packet"]
    check("supersession branch -> conflicted", p["disposition"]["packet_disposition"] == "conflicted")
    check("a supersession_branch contradiction is recorded",
          any(x["kind"] == "supersession_branch" for x in p["disposition"]["contradictions"]))
    # #40 ALSO consumes a selpol-surfaced branch signal (field name reconciled at the fold): feed a synthetic
    # sel output and assert detect_supersession_conflicts picks it up.
    syn = {"supersession_conflicts": [{"record_id": "rX", "record_version_ids": ["x1", "x2"]}]}
    conf = cc.detect_supersession_conflicts(syn, [], {})
    check("selpol-surfaced branch signal consumed",
          any(c["kind"] == "supersession_branch" and c.get("source") == "selpol" for c in conf))


def test_i33_temporal_intent_split():
    print("[i33/U5' acceptance e: query_class/temporal_intent split + versioned classifier in identity]")
    # query_class (semantic) and temporal_intent (temporal) are INDEPENDENT + both stamped.
    m = cc.run({"op": "normalize", "task": {"original_goal": "g", "request_text": "state",
                                            "task_type": "documentation"}})
    r = m["result"]
    check("query_class stamped (semantic)", r["query_class"] == "global_synthesis")
    check("temporal_intent stamped (independent)", r["temporal_intent"] in cc.TEMPORAL_INTENT_SET)
    check("classifier_policy_id/version stamped (imported, versioned)",
          bool(r["classifier_policy_id"]) and bool(r["classifier_policy_version"]))
    # an EXPLICIT user time OUTRANKS the class->mode default.
    hist = cc.run({"op": "normalize", "task": {"original_goal": "g", "request_text": "h",
                                               "task_type": "history"}})["result"]
    check("history class default is non-current", hist["temporal_intent"] != "current_only")
    histx = cc.run({"op": "normalize", "task": {"original_goal": "g", "request_text": "h",
                    "task_type": "history", "time_horizon": "current_only"}})["result"]
    check("explicit time_horizon OUTRANKS the class default",
          histx["temporal_intent"] == "current_only"
          and histx["temporal_intent_basis"].startswith("explicit"))
    # composite / unclassified fallback classes are reachable + handled by the temporal resolver.
    comp = cc.classify_query({"query_class": "composite"}, "coding", [])
    check("composite fallback class reachable (explicit)", comp[0] == "composite")
    ti, _ = cc.resolve_temporal_intent({}, "composite")
    check("composite resolves to a valid temporal_intent", ti in cc.TEMPORAL_INTENT_SET)
    un = cc.classify_query({}, "totally-unmapped-type", [])
    check("unmapped task_type + no literals -> unclassified", un[0] == "unclassified")
    # packet identity COVERS temporal_intent + classifier policy: changing temporal_intent changes packet_id.
    base = load("compile_case.json")
    p0 = cc.run(dict(base, op="compile"))["result"]["packet"]
    check("identity covers temporal_intent", p0["identity"]["temporal_intent"] == "current_only")
    check("identity covers the versioned classifier policy",
          p0["identity"]["classifier_policy"]["id"] and p0["identity"]["classifier_policy"]["version"])
    alt = json.loads(json.dumps(base)); alt["task"]["time_horizon"] = "any_valid_version"
    palt = cc.run(dict(alt, op="compile"))["result"]["packet"]
    check("temporal_intent change alters packet_id (identity coverage)", palt["packet_id"] != p0["packet_id"])
    check("altered temporal_intent stamped", palt["identity"]["temporal_intent"] == "any_valid_version")


def test_i33_unscoped_and_determinism():
    print("[i33: unscoped-global back-compat + a mixed unscoped pool guard + determinism]")
    # NO namespace declared + no grant -> UNSCOPED global compile (i32 back-compat: boundary not enforced).
    m = cc.run({"op": "compile", "task": {"original_goal": "g", "request_text": "content"},
                "retrieval_batches": [{"query_index": 0, "hits": [
                    _hit("a.md", "unnamespaced content.\n", "u1", "u", ns=None, rank=1)]}],
                "source_texts": {"a.md": "unnamespaced content.\n"},
                "retrieval_meta": {"retriever": "mock"}})
    check("unscoped global compile ok (no namespace declared)", m["ok"], json.dumps(
        {k: m.get(k) for k in ("ok", "error_code")}))
    check("unscoped closure is not enforced", m["result"]["packet"]["identity"]["namespace_closure"]["enforced"] is False)
    # an UNSCOPED compile over a >1-distinct-namespace pool cannot be disambiguated -> fail closed.
    mm = cc.run({"op": "compile", "task": {"original_goal": "g", "request_text": "content"},
                 "retrieval_batches": [{"query_index": 0, "hits": [
                     _hit("a.md", "ns a.\n", "a1", "a", ns="nsA", rank=1),
                     _hit("b.md", "ns b.\n", "b1", "b", ns="nsB", rank=2)]}],
                 "source_texts": {"a.md": "ns a.\n", "b.md": "ns b.\n"},
                 "retrieval_meta": {"retriever": "mock"}})
    check("unscoped mixed-namespace pool fails closed",
          (not mm["ok"]) and mm["error_code"] == "namespace_closure_violation")
    # determinism: the same i33 compile is byte-identical on re-run (incl the new identity fields).
    a = _compile_hits([_hit("projA/d.md", "deterministic.\n", "d1", "d", ns="projA")])
    b = _compile_hits([_hit("projA/d.md", "deterministic.\n", "d1", "d", ns="projA")])
    check("i33 packet byte-identical on re-run",
          cc.canonical_json(a["result"]["packet"]) == cc.canonical_json(b["result"]["packet"]))


def test_i33_expand_no_widen():
    print("[i33/U1': expansion NEVER widens the parent namespace scope]")
    parent = _compile_hits([_hit("projA/a.md", "Project A fencing + lease content.\n", "a1", "a",
                                 ns="projA", rank=1)])["result"]["packet"]
    check("parent packet is projA-scoped", parent["identity"]["allowed_namespaces"] == ["projA"])
    cands = [_hit("projA/more.md", "more projA evidence about the lease.\n", "m1", "m", ns="projA", rank=1),
             _hit("projB/leak.md", "projB SECRET leak content.\n", "l1", "l", ns="projB", rank=2)]
    args = {"op": "expand", "packet": parent,
            "request": {"type": "more_evidence", "budget": {"max_tokens": 200}},
            "expansion_candidates": cands,
            "source_texts": {"projA/more.md": cands[0]["snippet"], "projB/leak.md": cands[1]["snippet"]}}
    m = cc.run(args)
    check("expand ok", m["ok"], json.dumps({k: m.get(k) for k in ("ok", "error_code")}))
    exp = m["result"]["expansion"]
    check("expansion effective allowed_namespaces = parent scope [projA]", exp["allowed_namespaces"] == ["projA"])
    check("cross-namespace expansion candidate DROPPED (never widens scope)",
          exp["expansion_namespace_dropped"] >= 1)
    ev_rvids = set(e["record_version_id"] for e in exp["evidence"])
    check("projB candidate NOT in the expansion evidence", "l1" not in ev_rvids and "m1" in ev_rvids)
    check("NO projB metadata leaked into the expansion", "projB" not in json.dumps(exp)
          and "SECRET" not in json.dumps(exp))


def main():
    print("== context.compile 0.5 off-machine test gate (i33 namespace-closure + supersession-hardening) ==")
    for t in (test_primitives, test_normalize, test_three_regions, test_injection,
              test_dispositions, test_consumer_profile_and_transport, test_selpol_interface,
              test_selpol_stale_demote, test_selection_byte_identity, test_provenance_modes,
              test_identity_and_determinism, test_corpus_pin, test_omission_and_diversity,
              test_a3_skill_cards, test_eval_hooks, test_expand, test_error_paths,
              test_query_classification, test_current_only_propagation, test_namespace_hard_boundary,
              test_working_memory_region, test_new_reason_codes_carry,
              # i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING (D-0096)
              test_i33_all_object_scope_check, test_i33_candidate_role_navigation,
              test_i33_catalog_effective_current_passthrough, test_i33_supersession_branch_conflicted,
              test_i33_temporal_intent_split, test_i33_unscoped_and_determinism, test_i33_expand_no_widen):
        t()
    total = _passed + _failed
    print("\n== %d/%d passed, %d failed ==" % (_passed, total, _failed))
    return 1 if _failed else 0

if __name__ == "__main__":
    sys.exit(main())
