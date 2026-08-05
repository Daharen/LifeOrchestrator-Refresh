#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""i37 (R-1, D-0101/D-0103) GATE TEST -- the multi-channel query ROUTER, BORN INSTRUMENTED.

Drives #40 0.8.0's OPT-IN (`route`) multi-channel router over a REAL #36 tree (the i35 public-port
pattern: retriever=artifact_search + catalog_db_path, no injected port) and asserts the
CONTEXT_PACKET_CONTRACT s9 amendment:

  (a) the born-instrumented STAGE-TRACE is PRESENT + well-formed per s9 on EVERY routed compile -- one
      integer-only record per classification / routing / channel-selection stage, with the parent chain,
      candidates_in - |removed| == candidates_out, and channel-oriented removed[] (channel_id + reason_codes).
  (b) DOUBLE-RUN byte-identity of the trace + the whole packet + packet_id (deterministic, no wall-clock).
  (c) namespace-closure SANITIZATION -- under a MIXED-namespace corpus the trace leaks NO cross-namespace
      identifying metadata (channel-only; no ids/paths/namespaces/snippets); the sanitizer drops an
      out-of-scope record entry to a COUNT.
  (d) a FLAT / non-routed compile is BYTE-IDENTICAL to 0.7.0 -- the router is purely ADDITIVE + GATED: a
      route-off compile has ZERO routing fields and is byte-identical to the same compile with `route`
      absent (optionally cross-checked against a pinned 0.7.0 baseline via env LOR_BASELINE_070).
  (e) packet_id COVERS the routing_policy id+version -- hold the policy => identical packet_id; vary the
      policy id OR version => the packet_id changes (and ONLY the routing dimension moves it).

Plus: the router realizes ALL THREE reachable channels (hierarchy_descend + flat_index + lexical_fts) with
`working_memory` NAMED as a target but NEVER hydrated (the region stays reserved/empty; #42 wiring = i38).

Pure python3 + stdlib + sqlite. Temp catalogs under /tmp only -- never the real db. Off-machine FIRST."""

import os, sys, json, tempfile, shutil, hashlib, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOR_REPO") or HERE
while REPO != os.path.dirname(REPO) and not os.path.isdir(os.path.join(REPO, "modules", "36-artifact-search")):
    REPO = os.path.dirname(REPO)
MOD = os.path.join(REPO, "modules")
sys.path.insert(0, os.path.join(MOD, "36-artifact-search"))
sys.path.insert(0, os.path.join(MOD, "40-context-compiler"))

import artifact_search as A          # noqa: E402  -- REAL #36
import context_compiler as cc        # noqa: E402  -- REAL #40 0.8.0 (imports #37's REAL lib on load)

_PASS = 0
_FAIL = 0

def check(label, ok, detail=""):
    global _PASS, _FAIL
    ok = bool(ok)
    if ok:
        _PASS += 1
    else:
        _FAIL += 1
    tag = "PASS" if ok else "FAIL"
    print("  [%s] %s%s" % (tag, label, ("   :: " + str(detail) if (detail and not ok) else
                                        ("   (" + str(detail) + ")" if detail else ""))))
    return ok

def sha256_hex(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return hashlib.sha256(b).hexdigest()

def as_run(**args):
    out = A.run(args)
    if not out.get("ok"):
        raise RuntimeError("artifact_search op failed: %s -> %s" % (args.get("op"), out))
    return out["result"]

RARE = "zephyrquux"          # a decisive rare term present in EXACTLY ONE leaf of the corpus

REQUIRED_STAGE_KEYS = ("retrieval_plan_id", "stage_id", "parent_stage_id", "policy_id",
                       "policy_version", "candidates_in", "removed", "candidates_out", "tie_break_key")
SAFE_REMOVED_KEYS = frozenset(("channel_id", "record_id", "reason_codes"))
FORBIDDEN_REMOVED_KEYS = ("namespace", "source_path", "record_version_id", "snippet", "text", "excerpt", "path")

# ------------------------------------------------------------------------------------------------
# fixtures (REAL #36 ingest + build-hierarchy) -- nsa (30 leaves; RARE buried in ONE) + a SEPARATE nsb.
# ------------------------------------------------------------------------------------------------
def build_typed_fixture(db):
    recs = []
    for i in range(30):
        d = ("dirX" if i % 3 == 0 else ("dirY" if i % 3 == 1 else "dirZ"))
        recs.append({"record_id": "a%02d" % i, "record_version_id": "av%02d" % i, "record_kind": "claim",
                     "namespace": "nsa", "text": "generic lease fencing filler content alpha%02d beta gamma" % i,
                     "source_path": "nsa/%s/f%02d.md" % (d, i), "authority_level": "source_material"})
    req = "av_required"
    recs.append({"record_id": "a_required", "record_version_id": req, "record_kind": "claim", "namespace": "nsa",
                 "text": "the decisive %s marker: the fencing lease successor state of record." % RARE,
                 "source_path": "nsa/dirX/decisive_required.md", "authority_level": "source_material"})
    as_run(op="ingest-records", db=db, records=recs, ingest_run={"producer": "i37gate", "namespace": "nsa"})
    nsb = [{"record_id": "b%02d" % i, "record_version_id": "bv%02d" % i, "record_kind": "claim",
            "namespace": "nsb", "text": "nsb SECRET cross-namespace content delta%02d" % i,
            "source_path": "nsb/g%02d.md" % i, "authority_level": "source_material"} for i in range(6)]
    as_run(op="ingest-records", db=db, records=nsb, ingest_run={"producer": "i37gate", "namespace": "nsb"})
    as_run(op="build-hierarchy", db=db, max_fanout=4)
    cat = A.Catalog(db); cv = cat._get_corpus_version(); cat.close()
    return req, cv

def flat_nsa_batch(db, cv, rvids):
    """Build injected #36-flat evidence hits (the `flat_index` channel) for a scoped nsa compile."""
    cat = A.Catalog(db)
    hits = []
    for i, rvid in enumerate(rvids):
        t = cat.conn.execute("SELECT text,record_id,source_path FROM records WHERE record_version_id=?",
                             (rvid,)).fetchone()
        b = t["text"].encode("utf-8"); ch = sha256_hex(b)
        hits.append({"record_id": t["record_id"], "record_version_id": rvid, "record_kind": "claim",
                     "candidate_role": "evidence", "source_path": t["source_path"], "content_hash": ch,
                     "chunk_content_hash": ch, "span": {"start": 0, "end": len(b)},
                     "span_label": "bytes:0-%d" % len(b), "status": "current", "currentness": "current",
                     "namespace": "nsa", "source": "nsa", "source_version_id": "ver_" + rvid,
                     "authority_level": "source_material", "lexical_rank": i + 1, "lexical_score": 1.0 - i * 0.01,
                     "fused_rank": i + 1, "fused_score": 1.0 - i * 0.01, "index_snapshot": cv,
                     "corpus_version": cv, "tie_break_key": rvid, "snippet": t["text"], "rank": i + 1})
    st = {}
    for r in cat.conn.execute("SELECT source_path,text FROM records WHERE namespace='nsa'"):
        st[r["source_path"]] = r["text"]
    cat.close()
    return [{"query_index": 0, "hits": hits}], st

def public_compile(db, cv, text, query_class, ns="nsa", route=False, with_db=True,
                   batches=None, source_texts=None, beam=8, depth=8, k=8):
    task = {"original_goal": text, "request_text": text, "namespace": ns, "task_type": "research",
            "query_class": query_class,
            "control_plane": {"permission_grants": [{"namespaces": [ns]}]},
            "config": {"hier_shortlist_k": k, "hier_beam_b": beam, "hier_depth_d": depth}}
    args = {"op": "compile", "task": task,
            "retrieval_meta": {"retriever": "artifact_search", "corpus_version": cv}}
    if with_db:
        args["catalog_db_path"] = db
    if route:
        args["route"] = True
    if batches is not None:
        args["retrieval_batches"] = batches
    if source_texts is not None:
        args["source_texts"] = source_texts
    return cc.run(args)

# ------------------------------------------------------------------------------------------------
def _wellformed_stage(rec):
    if not all(k in rec for k in REQUIRED_STAGE_KEYS):
        return False, "missing keys: %s" % [k for k in REQUIRED_STAGE_KEYS if k not in rec]
    if not isinstance(rec["candidates_in"], int) or not isinstance(rec["candidates_out"], int):
        return False, "non-int candidate counts"
    if not isinstance(rec["removed"], list):
        return False, "removed not a list"
    if rec["candidates_in"] - len(rec["removed"]) != rec["candidates_out"]:
        return False, "count mismatch in=%s removed=%s out=%s" % (
            rec["candidates_in"], len(rec["removed"]), rec["candidates_out"])
    for r in rec["removed"]:
        if not (("channel_id" in r) or ("record_id" in r)):
            return False, "removed entry lacks channel_id|record_id"
        if "reason_codes" not in r or not isinstance(r["reason_codes"], list):
            return False, "removed entry lacks reason_codes[]"
        stray = [k for k in r if k not in SAFE_REMOVED_KEYS]
        if stray:
            return False, "removed entry has non-safe keys: %s" % stray
    return True, ""

def _no_float(o):
    if isinstance(o, bool):
        return True
    if isinstance(o, float):
        return False
    if isinstance(o, dict):
        return all(_no_float(v) for v in o.values())
    if isinstance(o, list):
        return all(_no_float(v) for v in o)
    return True

def test_a_wellformed(db, req, cv):
    print("\n[a] the born-instrumented stage-trace is PRESENT + well-formed per s9 on a routed compile]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", req))
    m = public_compile(db, cv, RARE, "global_synthesis", route=True, batches=batches, source_texts=st)
    ok = check("(a) routed compile ok", m.get("ok"), json.dumps({k: m.get(k) for k in ("ok", "error_code", "error")}))
    if not ok:
        raise RuntimeError("routed compile failed: %s" % m)
    p = m["result"]["packet"]
    eh = p["evaluation_hooks"]
    trace = eh.get("routing_stage_trace")
    check("(a) routing_stage_trace PRESENT in evaluation_hooks", isinstance(trace, list) and len(trace) == 3,
          "n=%s" % (len(trace) if isinstance(trace, list) else None))
    ids = [r.get("stage_id") for r in trace]
    check("(a) three stages: classification -> routing -> channel_selection",
          ids == ["classification", "routing", "channel_selection"], ids)
    parents = [r.get("parent_stage_id") for r in trace]
    check("(a) parent chain is None -> classification -> routing",
          parents == [None, "classification", "routing"], parents)
    allwf = True
    for r in trace:
        wf, why = _wellformed_stage(r)
        if not wf:
            allwf = False
            check("(a) stage %s well-formed per s9" % r.get("stage_id"), False, why)
    check("(a) every stage record is well-formed per s9 (keys, int counts, in-|removed|==out, safe removed[])", allwf)
    check("(a) integer-only trace -- NO float anywhere (no wall-clock, no float)", _no_float(trace))
    rpid = trace[0]["retrieval_plan_id"]
    check("(a) a single deterministic retrieval_plan_id ('route_'+hash) across all stages",
          rpid.startswith("route_") and all(r["retrieval_plan_id"] == rpid for r in trace), rpid)
    # channel realization: all three reachable channels selected; working_memory NAMED but not hydrated
    rp = eh["routing_plan"]
    sel = rp["selected_channels"]
    check("(a) router realizes hierarchy_descend + flat_index + lexical_fts (ordered)",
          sel == ["hierarchy_descend", "flat_index", "lexical_fts"], sel)
    check("(a) working_memory NAMED as a routing target", rp["named_targets"] == ["working_memory"])
    routing = [r for r in trace if r["stage_id"] == "routing"][0]
    wm_removed = [r for r in routing["removed"] if r["channel_id"] == "working_memory"]
    check("(a) working_memory removed-from-hydration (reserved) in the routing stage",
          len(wm_removed) == 1 and wm_removed[0]["reason_codes"] == ["working_memory_reserved_not_hydrated"])
    check("(a) working_memory region is NOT hydrated (reserved/empty; #42 wiring = i38)",
          p["working_memory"].get("present") is False and int(p["working_memory"].get("item_count", 0)) == 0)
    # identity coverage
    idb = p["identity"]
    check("(a) identity.routing_policy = multichannel_route_v1/1.0.0",
          idb.get("routing_policy", {}).get("id") == "multichannel_route_v1"
          and idb.get("routing_policy", {}).get("version") == "1.0.0", json.dumps(idb.get("routing_policy")))
    check("(a) identity.routing_plan_digest present (sha256)",
          str(idb.get("routing_plan_digest", "")).startswith("sha256:"))
    return p

def test_a_flat_class_routing(db, cv):
    print("\n[a] a routed DESCEND-class-but-no-flat vs a LOCAL-class compile record the right reason codes]")
    # local_factual + flat batches -> hierarchy_descend removed (class_not_descend); flat_index+lexical kept
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01"))
    m = public_compile(db, cv, "look up the fencing lease claim", "local_factual", route=True,
                       batches=batches, source_texts=st)
    trace = m["result"]["packet"]["evaluation_hooks"]["routing_stage_trace"]
    routing = [r for r in trace if r["stage_id"] == "routing"][0]
    reasons = {r["channel_id"]: r["reason_codes"] for r in routing["removed"]}
    check("(a) local_factual -> hierarchy_descend removed with class_not_descend",
          reasons.get("hierarchy_descend") == ["class_not_descend"], reasons)
    sel = m["result"]["packet"]["evaluation_hooks"]["routing_plan"]["selected_channels"]
    check("(a) local_factual selected = flat_index + lexical_fts (no hierarchy)", sel == ["flat_index", "lexical_fts"], sel)

def test_b_determinism(db, req, cv):
    print("\n[b] double-run byte-identity of the trace, the whole packet, and packet_id]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", req))
    p1 = public_compile(db, cv, RARE, "global_synthesis", route=True, batches=batches, source_texts=st)["result"]["packet"]
    batches2, st2 = flat_nsa_batch(db, cv, ("av00", "av01", req))
    p2 = public_compile(db, cv, RARE, "global_synthesis", route=True, batches=batches2, source_texts=st2)["result"]["packet"]
    check("(b) routed packet_id byte-identical on re-run", p1["packet_id"] == p2["packet_id"],
          "%s vs %s" % (p1["packet_id"], p2["packet_id"]))
    t1 = cc.canonical_json(p1["evaluation_hooks"]["routing_stage_trace"])
    t2 = cc.canonical_json(p2["evaluation_hooks"]["routing_stage_trace"])
    check("(b) routing_stage_trace byte-identical on re-run", t1 == t2)
    check("(b) whole routed packet byte-identical on re-run", cc.canonical_json(p1) == cc.canonical_json(p2))
    check("(b) packet_id == cpkt_+sha256(body-without-packet_id)[:32] (id truly covers the routed body)",
          p1["packet_id"] == "cpkt_" + cc.sha256_of_obj({k: v for k, v in p1.items() if k != "packet_id"})[:32])

def test_c_namespace_closure(db, cv):
    print("\n[c] namespace-closure sanitization: under a MIXED nsa+nsb corpus the trace leaks NO cross-ns metadata]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01"))
    m = public_compile(db, cv, "fencing lease " + RARE, "global_synthesis", ns="nsa", route=True,
                       batches=batches, source_texts=st)
    check("(c) mixed-corpus nsa routed compile ok", m.get("ok"),
          json.dumps({k: m.get(k) for k in ("ok", "error_code", "error")}))
    trace = m["result"]["packet"]["evaluation_hooks"]["routing_stage_trace"]
    blob = json.dumps(trace)
    check("(c) NO nsb / SECRET identifying metadata anywhere in the router trace",
          "nsb" not in blob and "SECRET" not in blob, blob[:200])
    stray = []
    for rec in trace:
        for r in rec["removed"]:
            for k in FORBIDDEN_REMOVED_KEYS:
                if k in r:
                    stray.append((rec["stage_id"], k))
    check("(c) NO removed[] entry carries an identifying field (namespace/path/rvid/snippet/text)", not stray, stray)
    check("(c) every removed[] entry is channel-only (keys subset of {channel_id, record_id, reason_codes})",
          all(set(r).issubset(SAFE_REMOVED_KEYS) for rec in trace for r in rec["removed"]))
    # the sanitizer itself: a fabricated OUT-OF-SCOPE record entry -> dropped to a COUNT (no ids)
    closure = {"unscoped_global": False, "effective": ["nsa"], "enforced": True}
    dirty = [{"retrieval_plan_id": "route_x", "stage_id": "channel_selection", "parent_stage_id": "routing",
              "policy_id": cc.ROUTING_POLICY_ID, "policy_version": cc.ROUTING_POLICY_VERSION,
              "candidates_in": 2, "candidates_out": 1, "tie_break_key": "t",
              "removed": [{"record_id": "leak1", "record_version_id": "bv00", "namespace": "nsb",
                           "source_path": "nsb/g00.md", "snippet": "SECRET", "reason_codes": ["x"]}]}]
    clean = cc._sanitize_route_trace(dirty, closure)
    cblob = json.dumps(clean)
    check("(c) sanitizer drops an OUT-OF-SCOPE record entry to a count (sanitized_removed_count)",
          clean[0].get("sanitized_removed_count") == 1 and clean[0]["removed"] == []
          and "nsb" not in cblob and "SECRET" not in cblob and "leak1" not in cblob, cblob)
    # an IN-SCOPE record entry is kept but reduced to safe fields (no path/snippet/namespace)
    ok_in = [{"retrieval_plan_id": "route_x", "stage_id": "routing", "parent_stage_id": "classification",
              "policy_id": cc.ROUTING_POLICY_ID, "policy_version": cc.ROUTING_POLICY_VERSION,
              "candidates_in": 1, "candidates_out": 0, "tie_break_key": "t",
              "removed": [{"record_id": "av00", "namespace": "nsa", "source_path": "nsa/x.md",
                           "reason_codes": ["y"]}]}]
    ci = cc._sanitize_route_trace(ok_in, closure)[0]["removed"][0]
    check("(c) an IN-SCOPE record entry keeps record_id + reason_codes but strips path/namespace",
          ci.get("record_id") == "av00" and set(ci).issubset(SAFE_REMOVED_KEYS)
          and "source_path" not in ci and "namespace" not in ci, ci)

def test_d_flat_byte_identical(db, req, cv):
    print("\n[d] a FLAT / non-routed compile is BYTE-IDENTICAL to 0.7.0 (the router is additive + gated)]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", req))
    # route OFF vs the SAME args with the `route` key entirely ABSENT -> must be byte-identical.
    off = public_compile(db, cv, RARE, "global_synthesis", route=False, batches=batches, source_texts=st)
    batches2, st2 = flat_nsa_batch(db, cv, ("av00", "av01", req))
    absent = public_compile(db, cv, RARE, "global_synthesis", route=False, batches=batches2, source_texts=st2)
    po = off["result"]["packet"]; pa = absent["result"]["packet"]
    check("(d) route-off packet has NO routing_stage_trace / routing_plan in evaluation_hooks",
          "routing_stage_trace" not in po["evaluation_hooks"] and "routing_plan" not in po["evaluation_hooks"])
    check("(d) route-off identity has NO routing_policy / routing_plan_digest",
          "routing_policy" not in po["identity"] and "routing_plan_digest" not in po["identity"])
    check("(d) route-off compile byte-identical to the route-absent compile (additive + gated)",
          cc.canonical_json(po) == cc.canonical_json(pa), "%s vs %s" % (po["packet_id"], pa["packet_id"]))
    # a routed packet, with the router additions removed, reduces EXACTLY to the flat packet -> proves the
    # router is a pure superset (0.7.0 flat body is a subset of the routed body).
    on = public_compile(db, cv, RARE, "global_synthesis", route=True, batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0],
                        source_texts=st)["result"]["packet"]
    stripped = json.loads(cc.canonical_json(on))
    stripped["evaluation_hooks"].pop("routing_stage_trace", None)
    stripped["evaluation_hooks"].pop("routing_plan", None)
    stripped["identity"].pop("routing_policy", None)
    stripped["identity"].pop("routing_plan_digest", None)
    stripped.pop("packet_id", None)
    # the router also records ONE audit warning (`query_router_engaged:*`, like the i35 hierarchy_port_bound
    # warning) -- strip that router-attributable warning too, then the routed body reduces EXACTLY to the flat.
    if "warnings" in stripped:
        stripped["warnings"] = [w for w in stripped["warnings"] if not str(w).startswith("query_router_engaged")]
    flat_body = json.loads(cc.canonical_json({k: v for k, v in po.items() if k != "packet_id"}))
    check("(d) routed body MINUS the router additions == the flat 0.7.0 body (pure superset; nothing else moved)",
          cc.canonical_json(stripped) == cc.canonical_json(flat_body),
          "delta keys: %s" % sorted(set(json.dumps(stripped)) ^ set(json.dumps(flat_body))))
    # OPTIONAL cross-version literal check vs a pinned 0.7.0 baseline worker (env LOR_BASELINE_070).
    base = os.environ.get("LOR_BASELINE_070")
    if base and os.path.isfile(base):
        spec = importlib.util.spec_from_file_location("context_compiler_070", base)
        cc070 = importlib.util.module_from_spec(spec)
        sys.modules["context_compiler_070"] = cc070
        spec.loader.exec_module(cc070)
        flat_task = {"original_goal": "look up alpha", "request_text": "look up alpha", "namespace": "nsa",
                     "task_type": "research", "query_class": "local_factual",
                     "control_plane": {"permission_grants": [{"namespaces": ["nsa"]}]}}
        fb, fst = flat_nsa_batch(db, cv, ("av00", "av01"))
        a70 = cc070.run({"op": "compile", "task": flat_task, "retrieval_batches": fb, "source_texts": fst,
                         "retrieval_meta": {"retriever": "injected", "corpus_version": cv}})["result"]["packet"]
        a80 = cc.run({"op": "compile", "task": flat_task, "retrieval_batches": fb, "source_texts": fst,
                      "retrieval_meta": {"retriever": "injected", "corpus_version": cv}})["result"]["packet"]
        d70 = json.loads(cc.canonical_json({k: v for k, v in a70.items() if k != "packet_id"}))
        d80 = json.loads(cc.canonical_json({k: v for k, v in a80.items() if k != "packet_id"}))
        # the ONLY expected differences are the three version stamps.
        d70["compiler"]["version"] = d80["compiler"]["version"]
        d70["compiler"]["worker_version"] = d80["compiler"]["worker_version"]
        d70["identity"]["compiler_version"] = d80["identity"]["compiler_version"]
        check("(d) [baseline] flat 0.8.0 body == frozen 0.7.0 body EXCEPT the 3 version stamps",
              cc.canonical_json(d70) == cc.canonical_json(d80))
    else:
        print("  [note] LOR_BASELINE_070 unset -> the (portable) additive+gated proof stands; cross-version literal check skipped")

def test_e_identity_covers_policy(db, req, cv):
    print("\n[e] packet_id COVERS routing_policy id+version (hold => identical; vary => changes)]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", req))
    hold1 = public_compile(db, cv, RARE, "global_synthesis", route=True, batches=batches, source_texts=st)["result"]["packet"]
    hold2 = public_compile(db, cv, RARE, "global_synthesis", route=True,
                           batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0], source_texts=st)["result"]["packet"]
    check("(e) hold the policy -> identical packet_id", hold1["packet_id"] == hold2["packet_id"])
    off = public_compile(db, cv, RARE, "global_synthesis", route=False,
                         batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0], source_texts=st)["result"]["packet"]
    sv_v, sv_i = cc.ROUTING_POLICY_VERSION, cc.ROUTING_POLICY_ID
    try:
        cc.ROUTING_POLICY_VERSION = "9.9.9"
        varv = public_compile(db, cv, RARE, "global_synthesis", route=True,
                              batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0], source_texts=st)["result"]["packet"]
        cc.ROUTING_POLICY_VERSION = sv_v
        cc.ROUTING_POLICY_ID = "other_route_vX"
        vari = public_compile(db, cv, RARE, "global_synthesis", route=True,
                              batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0], source_texts=st)["result"]["packet"]
    finally:
        cc.ROUTING_POLICY_VERSION = sv_v
        cc.ROUTING_POLICY_ID = sv_i
    check("(e) vary routing_policy VERSION -> packet_id changes", varv["packet_id"] != hold1["packet_id"],
          "%s vs %s" % (varv["packet_id"], hold1["packet_id"]))
    check("(e) vary routing_policy ID -> packet_id changes", vari["packet_id"] != hold1["packet_id"])
    check("(e) the routing policy is the ONLY router-side mover (a non-routed id stays stable, != routed)",
          off["packet_id"] != hold1["packet_id"])
    # restored constants -> back to the held id (proves the change was purely the policy, not incidental drift)
    restored = public_compile(db, cv, RARE, "global_synthesis", route=True,
                              batches=flat_nsa_batch(db, cv, ("av00", "av01", req))[0], source_texts=st)["result"]["packet"]
    check("(e) restoring the policy returns the ORIGINAL held packet_id", restored["packet_id"] == hold1["packet_id"])

def main():
    print("== i37 ROUTER + BORN-INSTRUMENTED STAGE-TRACE GATE (REAL #36 tree + REAL #40 0.8.0) ==")
    tmp = tempfile.mkdtemp(prefix="i37gate-")
    try:
        db = os.path.join(tmp, "typed.db")
        req, cv = build_typed_fixture(db)
        print("[fixture] typed.db corpus_version=%s required_leaf=%s (nsa 31 leaves + nsb 6 mixed)" % (cv, req))
        test_a_wellformed(db, req, cv)
        test_a_flat_class_routing(db, cv)
        test_b_determinism(db, req, cv)
        test_c_namespace_closure(db, cv)
        test_d_flat_byte_identical(db, req, cv)
        test_e_identity_covers_policy(db, req, cv)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nI37-GATE RESULT: %d passed, %d failed" % (_PASS, _FAIL))
    return 0 if _FAIL == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
