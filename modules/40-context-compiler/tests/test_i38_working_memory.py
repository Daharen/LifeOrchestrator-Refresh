#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""i38 (D-0104 follow-on) GATE TEST -- the packet `working_memory` region WIRED to #42's per-task store.

The i37 router (#40 0.8.0) NAMED a `working_memory` channel but left the region reserved/empty. This
drives the PRODUCTION wiring: a routed compile that BINDS a real #42 `working.memory` store + a coordinator
`working_memory_task_id` HYDRATES the packet's `working_memory` region from #42.get_active_head CONJUNCTIVELY
(task_id AND effective-namespace), READ-ONLY over the FROZEN #42. Off-machine FIRST (imports REAL #36 + #42 +
#40), THEN -Live on the executor.

Asserts acceptance (a)-(e):
  (a) a task-scoped compile with an ACTIVE #42 head HYDRATES the region -- record_kind=working,
      can_instruct=false, rendered THIRD (control_plane -> task_input -> working_memory -> evidence), and
      NOT in evidence[]; the router SELECTS the working_memory channel.
  (b) CONJUNCTIVE ns -- a cross-namespace / not-permitted task returns NOT-FOUND fail-closed, count-only,
      ZERO leakage (no nsb/SECRET metadata; no existence oracle) + the region stays reserved/empty.
  (c) state_version is in packet_id: vary it -> packet_id changes; hold it -> identical; double-run
      byte-identity; packet_id == cpkt_+sha256(body).
  (d) a no-working-memory / no-task / route-off compile is BYTE-IDENTICAL to 0.8.0 (hydration is additive +
      gated: a bound-but-empty store == no binding; only the working_memory region + the router selection
      move -- control_plane / task_input / evidence / disposition are byte-identical to the no-wm compile).
  (e) working memory NEVER satisfies evidence coverage: the working item is not in evidence[], not in any
      coverage/missing requirement; coverage + disposition are IDENTICAL with vs without hydration.

Pure python3 + stdlib + sqlite. Temp stores under /tmp only -- never the real db. READ-ONLY over #42."""

import os, sys, json, tempfile, shutil, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOR_REPO") or HERE
while REPO != os.path.dirname(REPO) and not os.path.isdir(os.path.join(REPO, "modules", "36-artifact-search")):
    REPO = os.path.dirname(REPO)
MOD = os.path.join(REPO, "modules")
sys.path.insert(0, os.path.join(MOD, "36-artifact-search"))
sys.path.insert(0, os.path.join(MOD, "42-working-memory"))
sys.path.insert(0, os.path.join(MOD, "40-context-compiler"))

import artifact_search as A          # noqa: E402  -- REAL #36
import working_memory as W           # noqa: E402  -- REAL #42 (FROZEN; read-only here)
import context_compiler as cc        # noqa: E402  -- REAL #40 0.9.0 (imports #37's REAL lib on load)

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

MARK = "wmstatemarker"       # a decisive term that lives ONLY in the working-state body (never in evidence)

# ------------------------------------------------------------------------------------------------
# fixtures: a REAL #36 tree (nsa evidence + a separate nsb) + a REAL #42 store (heads under nsa / nsb)
# ------------------------------------------------------------------------------------------------
def build_search_fixture(db):
    recs = [{"record_id": "a%02d" % i, "record_version_id": "av%02d" % i, "record_kind": "claim",
             "namespace": "nsa", "text": "generic lease fencing filler content alpha%02d beta gamma" % i,
             "source_path": "nsa/f%02d.md" % i, "authority_level": "source_material"} for i in range(12)]
    A.run({"op": "ingest-records", "db": db, "records": recs,
           "ingest_run": {"producer": "i38gate", "namespace": "nsa"}})
    nsb = [{"record_id": "b%02d" % i, "record_version_id": "bv%02d" % i, "record_kind": "claim",
            "namespace": "nsb", "text": "nsb SECRET cross-namespace content delta%02d" % i,
            "source_path": "nsb/g%02d.md" % i, "authority_level": "source_material"} for i in range(4)]
    A.run({"op": "ingest-records", "db": db, "records": nsb,
           "ingest_run": {"producer": "i38gate", "namespace": "nsb"}})
    A.run({"op": "build-hierarchy", "db": db, "max_fanout": 4})
    cat = A.Catalog(db); cv = cat._get_corpus_version(); cat.close()
    return cv

def flat_nsa_batch(db, cv, rvids):
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

def wm_put(store, out, task_id, ns, body, parent=None, namespace_scope=None):
    """Write ONE working-state version to the REAL #42 store (authorized under `ns`). Returns the summary."""
    req = {"op": "put_state", "store_path": store, "out_dir": out, "task_id": task_id,
           "allowed_namespaces": [ns], "permission_grants": [ns], "body": body}
    if parent is not None:
        req["parent_state_version"] = parent
    if namespace_scope is not None:
        req["namespace_scope"] = namespace_scope
    return W.run_request(req)

def build_wm_store(store, out):
    """coordA under nsa: v1 -> v2 (active head = v2). coordB under nsb (a cross-namespace head)."""
    wm_put(store, out, "coordA", "nsa", {"phase": "start", "note": "v1 %s" % MARK}, namespace_scope="nsa")
    wm_put(store, out, "coordA", "nsa", {"phase": "deepened", "note": "v2 current %s intermediate state" % MARK},
           parent=1)
    wm_put(store, out, "coordB", "nsb", {"phase": "secret", "note": "nsb SECRET working state"},
           namespace_scope="nsb")

# ------------------------------------------------------------------------------------------------
# the compile driver: route ON, real nsa evidence (flat batch) + an OPTIONAL #42 working-memory binding.
# ------------------------------------------------------------------------------------------------
def compile_wm(db, cv, batches, st, ns="nsa", route=True, wm_store=None, wm_task=None, requirements=None):
    task = {"original_goal": "deepen the fencing lease task", "request_text": "deepen the fencing lease task",
            "namespace": ns, "task_type": "planning", "query_class": "current_state",
            "control_plane": {"permission_grants": [{"namespaces": [ns]}]}}
    if requirements is not None:
        task["evidence_requirements"] = requirements
    args = {"op": "compile", "task": task, "retrieval_meta": {"retriever": "flat", "corpus_version": cv},
            "retrieval_batches": batches, "source_texts": st}
    if route:
        args["route"] = True
    if wm_store is not None:
        args["working_memory_store_path"] = wm_store
    if wm_task is not None:
        args["working_memory_task_id"] = wm_task
    return cc.run(args)

# ================================================================================================
def test_a_hydrate(db, cv, store):
    print("\n[a] a task-scoped compile with an ACTIVE #42 head HYDRATES the region + the router SELECTS it]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", "av02"))
    m = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")
    ok = check("(a) compile ok", m.get("ok"), json.dumps({k: m.get(k) for k in ("ok", "error_code", "error")}))
    if not ok:
        raise RuntimeError("compile failed: %s" % m)
    p = m["result"]["packet"]
    wm = p["working_memory"]
    check("(a) working_memory region PRESENT + hydrated (store_status=active_head_hydrated)",
          wm.get("present") is True and wm.get("store_status") == "active_head_hydrated", json.dumps(
              {k: wm.get(k) for k in ("present", "store_status", "item_count", "state_version")}))
    check("(a) exactly ONE working item; state_version == the ACTIVE head (v2)",
          wm.get("item_count") == 1 and wm.get("state_version") == 2, wm.get("state_version"))
    it = wm["items"][0]
    check("(a) the item is record_kind=working, content_role=working_state, can_instruct=false, is_evidence=false",
          it.get("record_kind") == "working" and it.get("content_role") == "working_state"
          and it.get("can_instruct") is False and it.get("is_evidence") is False, json.dumps(
              {k: it.get(k) for k in ("record_kind", "content_role", "can_instruct", "is_evidence")}))
    check("(a) the item carries the #42 head identity (wsv_ rvid + working_state_id + content_hash)",
          str(it.get("record_version_id")).startswith("wsv_") and str(it.get("working_state_id")).startswith("ws_")
          and str(it.get("content_hash")).startswith("sha256:"), json.dumps(
              {k: it.get(k) for k in ("record_version_id", "working_state_id")}))
    # NOT in evidence[]
    ev = p["evidence"]["excerpts"]
    ev_rvids = set(e["record_version_id"] for e in ev)
    check("(a) the working rvid is NOT in evidence[] (a SEPARATE region)", it["record_version_id"] not in ev_rvids)
    check("(a) NO evidence excerpt is record_kind=working", all(e.get("record_kind") != "working" for e in ev))
    check("(a) evidence is still populated from #36 (working memory did not displace it)", len(ev) >= 1)
    # render order: working_memory THIRD (between task and evidence); the state body renders in the region.
    rendered = cc.render_packet_input(p["control_plane"], p["task_input"], wm, ev)
    i_task = rendered.index("=== TASK ===")
    i_wm = rendered.index("=== WORKING MEMORY")
    i_ev = rendered.index("=== EVIDENCE")
    check("(a) rendered THIRD: control -> task -> working_memory -> evidence", i_task < i_wm < i_ev)
    check("(a) the hydrated working-state body renders in the working_memory region",
          MARK in rendered[i_wm:i_ev] and MARK not in rendered[i_ev:])
    # the ROUTER SELECTED the working_memory channel.
    rp = p["evaluation_hooks"]["routing_plan"]
    check("(a) the router SELECTED the working_memory channel", "working_memory" in rp["selected_channels"],
          rp["selected_channels"])
    check("(a) channel_availability.working_memory == True", rp["channel_availability"].get("working_memory") is True)
    check("(a) identity.working_state_version == the hydrated head state_version (2)",
          p["identity"]["working_state_version"] == 2, p["identity"]["working_state_version"])
    return p

def test_b_cross_ns_fail_closed(db, cv, store):
    print("\n[b] a cross-namespace / not-permitted task -> NOT-FOUND fail-closed, ZERO leakage, region reserved]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", "av02"))
    # scoped to nsa, but request coordB (whose head is under nsb) -> conjunctive ns denies -> not found.
    m = compile_wm(db, cv, batches, st, ns="nsa", wm_store=store, wm_task="coordB")
    ok = check("(b) compile still succeeds (fail-closed is NOT a crash)", m.get("ok"),
               json.dumps({k: m.get(k) for k in ("ok", "error_code", "error")}))
    if not ok:
        raise RuntimeError("compile failed: %s" % m)
    p = m["result"]["packet"]
    wm = p["working_memory"]
    check("(b) region stays RESERVED/empty (present=False, item_count=0)",
          wm.get("present") is False and wm.get("item_count") == 0 and wm.get("items") == [],
          json.dumps({k: wm.get(k) for k in ("present", "item_count")}))
    check("(b) state_version stays None (no head hydrated across the namespace boundary)",
          wm.get("state_version") is None)
    blob = cc.canonical_json(p)
    check("(b) ZERO leakage: no 'nsb' / 'SECRET' / 'coordB' metadata anywhere in the packet",
          "nsb" not in blob and "SECRET" not in blob and "coordB" not in blob)
    # the router did NOT select working_memory (indistinguishable from a genuine absence -- no oracle).
    rp = p["evaluation_hooks"]["routing_plan"]
    routing = [s for s in p["evaluation_hooks"]["routing_stage_trace"] if s["stage_id"] == "routing"][0]
    wm_removed = [r for r in routing["removed"] if r["channel_id"] == "working_memory"]
    check("(b) working_memory NOT selected; removed with the SAME reserved reason (no existence oracle)",
          "working_memory" not in rp["selected_channels"] and len(wm_removed) == 1
          and wm_removed[0]["reason_codes"] == ["working_memory_reserved_not_hydrated"], json.dumps(wm_removed))
    # a MISSING task id is byte-identical to the cross-ns denial (the packets match exactly -> no oracle).
    m_absent = compile_wm(db, cv, batches, st, ns="nsa", wm_store=store, wm_task="task_does_not_exist")
    check("(b) cross-ns-denied packet == genuine-absence packet (fail-closed is INDISTINGUISHABLE)",
          cc.canonical_json(p) == cc.canonical_json(m_absent["result"]["packet"]))

def test_c_state_version_identity(db, cv, tmp):
    print("\n[c] state_version is in packet_id: vary -> changes; hold -> identical; double-run byte-identity]")
    store = os.path.join(tmp, "wm_c.db"); out = os.path.join(tmp, "wm_c_out")
    wm_put(store, out, "coordA", "nsa", {"phase": "start", "note": "v1"}, namespace_scope="nsa")
    wm_put(store, out, "coordA", "nsa", {"phase": "v2", "note": "state two"}, parent=1)
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", "av02"))
    p_v2a = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")["result"]["packet"]
    p_v2b = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")["result"]["packet"]
    check("(c) HOLD state_version=2 -> byte-identical packet_id (double-run determinism)",
          p_v2a["packet_id"] == p_v2b["packet_id"], "%s vs %s" % (p_v2a["packet_id"], p_v2b["packet_id"]))
    check("(c) whole hydrated packet byte-identical on re-run",
          cc.canonical_json(p_v2a) == cc.canonical_json(p_v2b))
    check("(c) packet_id == cpkt_+sha256(body-without-packet_id)[:32] (id truly covers the hydrated body)",
          p_v2a["packet_id"] == "cpkt_" + cc.sha256_of_obj(
              {k: v for k, v in p_v2a.items() if k != "packet_id"})[:32])
    # advance the head to v3 -> a NEW state_version -> a NEW packet_id (state_version enters identity).
    wm_put(store, out, "coordA", "nsa", {"phase": "v3", "note": "state three"}, parent=2)
    p_v3 = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")["result"]["packet"]
    check("(c) VARY state_version (2 -> 3) -> packet_id CHANGES", p_v2a["packet_id"] != p_v3["packet_id"],
          "%s vs %s" % (p_v2a["packet_id"], p_v3["packet_id"]))
    check("(c) identity.working_state_version tracks the head (3)", p_v3["identity"]["working_state_version"] == 3)

def test_d_byte_identical_no_wm(db, cv, store, tmp):
    print("\n[d] a no-wm / no-task / route-off compile is BYTE-IDENTICAL to 0.8.0 (additive + gated)]")
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", "av02"))
    # B: routed, NO wm binding.  C: routed, a wm store bound to a NON-EXISTENT path (no head).
    pB = compile_wm(db, cv, batches, st, wm_store=None, wm_task=None)["result"]["packet"]
    pC = compile_wm(db, cv, batches, st, wm_store=os.path.join(tmp, "does_not_exist.db"),
                    wm_task="coordA")["result"]["packet"]
    check("(d) a bound-but-empty/absent store == NO binding (byte-identical -> 0.8.0 behavior)",
          cc.canonical_json(pB) == cc.canonical_json(pC), "%s vs %s" % (pB["packet_id"], pC["packet_id"]))
    check("(d) the no-wm region is reserved/empty (present=False, item_count=0, state_version=None)",
          pB["working_memory"]["present"] is False and pB["working_memory"]["item_count"] == 0
          and pB["working_memory"]["state_version"] is None)
    check("(d) no-wm identity.working_state_version is None", pB["identity"]["working_state_version"] is None)
    # route OFF, even WITH a valid wm binding -> reserved (hydration is gated on the router selecting it).
    pOff = compile_wm(db, cv, batches, st, route=False, wm_store=store, wm_task="coordA")["result"]["packet"]
    pOffNo = compile_wm(db, cv, batches, st, route=False, wm_store=None, wm_task=None)["result"]["packet"]
    check("(d) route OFF + a bound store == route OFF + no binding (gated on route)",
          cc.canonical_json(pOff) == cc.canonical_json(pOffNo))
    check("(d) route-off region reserved (no hydration without the router selecting the channel)",
          pOff["working_memory"]["present"] is False)
    # ADDITIVE: the hydrated compile differs from the no-wm compile ONLY in the working-memory dimension.
    pA = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")["result"]["packet"]
    check("(d) hydration CHANGES the packet_id vs the no-wm compile", pA["packet_id"] != pB["packet_id"])
    for region in ("control_plane", "task_input", "evidence", "disposition", "token_budget"):
        check("(d) additive: %s byte-identical with vs without hydration" % region,
              cc.canonical_json(pA[region]) == cc.canonical_json(pB[region]))

def test_e_never_evidence(db, cv, store):
    print("\n[e] working memory NEVER satisfies evidence coverage (not in evidence[]/coverage; coverage invariant)]")
    # a requirement whose term (MARK) appears ONLY in the working-state body -- it must remain UNSATISFIED
    # (working memory is not evidence), and coverage must be IDENTICAL with vs without hydration.
    reqs = [{"id": "req_mark", "description": "the %s state marker" % MARK, "must_include_any": [MARK]}]
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01", "av02"))
    pA = compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA", requirements=reqs)["result"]["packet"]
    pB = compile_wm(db, cv, batches, st, wm_store=None, wm_task=None, requirements=reqs)["result"]["packet"]
    wm = pA["working_memory"]
    check("(e) the region IS hydrated for this case (so the check is meaningful)", wm.get("present") is True)
    it_rvid = wm["items"][0]["record_version_id"]
    disp = pA["disposition"]
    # the working item never appears among the evidence that satisfies a requirement
    sat_rvids = set()
    for c in disp.get("coverage_results") or []:
        for s in (c.get("satisfied_by") or c.get("evidence") or []):
            sat_rvids.add(s if isinstance(s, str) else s.get("record_version_id"))
    check("(e) the working rvid never satisfies a coverage requirement", it_rvid not in sat_rvids)
    check("(e) coverage_results IDENTICAL with vs without the hydrated working memory",
          cc.canonical_json(disp.get("coverage_results")) == cc.canonical_json((pB["disposition"] or {}).get("coverage_results")))
    check("(e) missing_requirements IDENTICAL with vs without hydration (WM adds no evidence sufficiency)",
          cc.canonical_json(disp.get("missing_requirements")) == cc.canonical_json((pB["disposition"] or {}).get("missing_requirements")))
    check("(e) packet_disposition IDENTICAL with vs without hydration",
          disp.get("packet_disposition") == pB["disposition"].get("packet_disposition"))
    check("(e) evidence[] byte-identical with vs without hydration (WM is a separate region)",
          cc.canonical_json(pA["evidence"]) == cc.canonical_json(pB["evidence"]))

def test_f_readonly_frozen_42(store, tmp):
    print("\n[f] #42 is READ-ONLY: the compile's get_active_head never mutates the store (records_digest stable)]")
    # snapshot every working_state row, run a hydrating compile, re-snapshot -> identical.
    import sqlite3
    def snap(p):
        c = sqlite3.connect(p); c.row_factory = sqlite3.Row
        rows = [dict(r) for r in c.execute("SELECT * FROM working_state ORDER BY record_version_id")]
        c.close()
        return cc.sha256_of_obj(rows)
    before = snap(store)
    # (the actual hydrating compiles above already ran against `store`); do one more explicitly here.
    dbdir = os.path.join(tmp, "ro36"); os.makedirs(dbdir, exist_ok=True)
    db = os.path.join(dbdir, "s.db"); cv = build_search_fixture(db)
    batches, st = flat_nsa_batch(db, cv, ("av00", "av01"))
    compile_wm(db, cv, batches, st, wm_store=store, wm_task="coordA")
    after = snap(store)
    check("(f) the #42 store is byte-identical before/after a hydrating compile (READ-ONLY, FROZEN #42)",
          before == after, "%s vs %s" % (before[:16], after[:16]))

def main():
    print("== i38 WORKING-MEMORY HYDRATION GATE (REAL #36 tree + REAL #42 store + REAL #40 0.9.0) ==")
    tmp = tempfile.mkdtemp(prefix="i38gate-")
    try:
        db = os.path.join(tmp, "search.db")
        cv = build_search_fixture(db)
        store = os.path.join(tmp, "wm.db"); out = os.path.join(tmp, "wm_out")
        build_wm_store(store, out)
        print("[fixture] search.db cv=%s ; wm.db heads: coordA(nsa,v2) coordB(nsb,v1)" % cv)
        test_a_hydrate(db, cv, store)
        test_b_cross_ns_fail_closed(db, cv, store)
        test_c_state_version_identity(db, cv, tmp)
        test_d_byte_identical_no_wm(db, cv, store, tmp)
        test_e_never_evidence(db, cv, store)
        test_f_readonly_frozen_42(store, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nI38-GATE RESULT: %d passed, %d failed" % (_PASS, _FAIL))
    return 0 if _FAIL == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
