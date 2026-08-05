#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""i35 (D-0100) GATE TEST -- the REAL hierarchy_port wired into #40's PUBLIC `artifact_search` path.

Unlike the i34 fold smoke (which INJECTS a port), this drives the PRODUCTION wiring: the compile request
carries `retrieval_meta.retriever = "artifact_search"` + a `catalog_db_path` and NO `hierarchy_port`, so
#40 CONSTRUCTS a real `ArtifactSearchHierarchyPort` over a REAL #36 catalog and runs the shortlist-and-descend
plan end to end. Off-machine FIRST (imports the REAL #36 Catalog + ops), THEN -Live on the executor.

Asserts acceptance (a)-(f):
  (a) a real port over #36 Catalog/shortlist/descend/prune_verdict, resolved-portable import; one pinned
      tree_version + corpus_snapshot per compile.
  (b) PUBLIC retriever=artifact_search + DESCEND class + scoped runs the plan for real (no injected port);
      a non-descend / no-db_path / non-artifact_search request stays flat, BYTE-IDENTICAL + additive/gated.
  (c) SEAM 1 leaf hydration: bare descend refs -> full evidence; provenance HOLDS (reproduced direct_span;
      the cited span reproduces the source bytes); a source_chunk reconstructs to the REAL ingested file.
  (d) SEAM 2 prune-certificate from REAL per-term prune_verdict; a bounded descriptor / stale synopsis NEVER
      prunes; a sound no-false-negative certificate DOES prune -- recall preserved.
  (e) V2-V5 stay green: nodes NEVER in evidence[]; a foreign/out-of-scope descend fails closed (count only);
      a cross-namespace nav object -> sanitized abort; deterministic packet_id covering hierarchy identity.
  (f) a flat compile stays byte-identical; all shipped 0.6/0.7 tests stay green (the 322-suite, run separately).

Pure python3 + stdlib + sqlite. Temp catalogs under /tmp only -- never the real db."""

import os, sys, json, tempfile, shutil, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOR_REPO") or HERE
while REPO != os.path.dirname(REPO) and not os.path.isdir(os.path.join(REPO, "modules", "36-artifact-search")):
    REPO = os.path.dirname(REPO)
MOD = os.path.join(REPO, "modules")
sys.path.insert(0, os.path.join(MOD, "36-artifact-search"))
sys.path.insert(0, os.path.join(MOD, "40-context-compiler"))

import artifact_search as A          # noqa: E402  -- REAL #36
import context_compiler as cc        # noqa: E402  -- REAL #40 (imports #37's REAL lib on load)

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

# ------------------------------------------------------------------------------------------------
# fixtures (REAL #36 ingest + build-hierarchy)
# ------------------------------------------------------------------------------------------------
def build_typed_fixture(db):
    """nsa: ~30 typed-record leaves; the RARE term in exactly ONE (buried in a subtree). nsb: a SEPARATE
    tree the nsa-scoped query is NOT authorized for. Returns (required_leaf_rvid, corpus_version)."""
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
    as_run(op="ingest-records", db=db, records=recs, ingest_run={"producer": "i35gate", "namespace": "nsa"})
    nsb = [{"record_id": "b%02d" % i, "record_version_id": "bv%02d" % i, "record_kind": "claim",
            "namespace": "nsb", "text": "nsb SECRET cross-namespace content delta%02d" % i,
            "source_path": "nsb/g%02d.md" % i, "authority_level": "source_material"} for i in range(6)]
    as_run(op="ingest-records", db=db, records=nsb, ingest_run={"producer": "i35gate", "namespace": "nsb"})
    as_run(op="build-hierarchy", db=db, max_fanout=4)
    cat = A.Catalog(db); cv = cat._get_corpus_version(); cat.close()
    return req, cv

def build_chunk_fixture(tmp):
    """Ingest REAL files (a file crawl -> source_chunk leaves with real spans + abs_path) so the SEAM-1
    hydration exercises the SHIPPED export_chunk_texts path + reconstruction to the real source file."""
    root = os.path.join(tmp, "srcroot")
    os.makedirs(os.path.join(root, "sub"))
    files = {
        "sub/lease_a.md": "# Lease A\n\nThe fencing lease overview covers renewal and the current state.\n",
        "sub/lease_b.md": "# Lease B\n\nThe decisive %s marker: fencing lease successor details here.\n" % RARE,
        "notes.md": "# Notes\n\nGeneric fencing lease filler about renewal cadence and cost.\n",
    }
    for rel, body in files.items():
        p = os.path.join(root, rel.replace("/", os.sep))
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
    db = os.path.join(tmp, "chunks.db")
    as_run(op="ingest", db=db, source="nsc", root=root)
    as_run(op="build-hierarchy", db=db, max_fanout=4)
    cat = A.Catalog(db); cv = cat._get_corpus_version(); cat.close()
    return db, cv, root

# ------------------------------------------------------------------------------------------------
# the PUBLIC-path compile driver: NO injected hierarchy_port; #40 CONSTRUCTS the real port from db_path.
# ------------------------------------------------------------------------------------------------
def public_compile(db, cv, request_text, query_class, ns="nsa", retriever="artifact_search",
                   with_db=True, batches=None, source_texts=None, beam=8, depth=8, k=8):
    task = {"original_goal": request_text, "request_text": request_text, "namespace": ns,
            "task_type": "research", "query_class": query_class,
            "control_plane": {"permission_grants": [{"namespaces": [ns]}]},
            "config": {"hier_shortlist_k": k, "hier_beam_b": beam, "hier_depth_d": depth}}
    args = {"op": "compile", "task": task,
            "retrieval_meta": {"retriever": retriever, "corpus_version": cv}}
    if with_db:
        args["catalog_db_path"] = db
    if batches is not None:
        args["retrieval_batches"] = batches
    if source_texts is not None:
        args["source_texts"] = source_texts
    return cc.run(args)

# ================================================================================================
def test_a_b_c_e_public_typed(db, req, cv):
    print("\n[a/b/c/e] PUBLIC artifact_search path constructs the real port; required leaf reached+hydrated]")
    m = public_compile(db, cv, RARE, "global_synthesis")
    ok = check("(b) public compile ok (no injected port; retriever=artifact_search + catalog_db_path)",
               m.get("ok"), json.dumps({k2: m.get(k2) for k2 in ("ok", "error_code", "error")}))
    if not ok:
        raise RuntimeError("public compile failed: %s" % m)
    check("(a) the real port was BOUND (warning records the resolved #36 import)",
          any(str(w).startswith("hierarchy_port_bound:artifact_search:") for w in m.get("warnings") or []),
          m.get("warnings"))
    p = m["result"]["packet"]
    check("(b) the plan RAN (retrieval_completeness present -> not a flat compile)",
          "retrieval_completeness" in p)
    ev = p["evidence"]["excerpts"]
    ev_rvids = set(e["record_version_id"] for e in ev)
    check("(c) required leaf REACHED via descend -> in evidence[]", req in ev_rvids,
          "evidence=%s" % sorted(ev_rvids))
    check("(e) NO record_kind='node' in evidence[]", all(e.get("record_kind") != "node" for e in ev))
    nav = p["evidence"]["navigation_refs"]
    check("(e) navigation nodes routed to navigation_refs (candidate_role=navigation)",
          len(nav) >= 1 and all(r.get("candidate_role") == "navigation" for r in nav))
    check("(e) no emitted node rvid leaked into evidence[]",
          not (set(r["record_version_id"] for r in nav) & ev_rvids))
    # (c) provenance HOLDS: the required leaf reproduces its ingested source bytes
    cat = A.Catalog(db)
    body = cat.conn.execute("SELECT text FROM records WHERE record_version_id=?", (req,)).fetchone()["text"]
    cat.close()
    reqe = [e for e in ev if e["record_version_id"] == req][0]
    prov = reqe.get("provenance") or {}
    check("(c) required-leaf provenance reproduced direct_span (span sha256 == excerpt_hash)",
          prov.get("provenance_mode") == "direct_span" and prov.get("reproduced") is True, json.dumps(prov))
    check("(c) required-leaf excerpt reconstructs to the ingested source body", reqe.get("text") == body)
    check("(c) EVERY excerpt is a reproduced direct_span (no unreproduced provenance)",
          all(e["provenance"]["reproduced"] is True and e["provenance"]["valid"] is True for e in ev))
    # (a) one pinned tree_version + hierarchy identity coverage
    hib = p["identity"].get("hierarchy", {})
    tv = as_run(op="hierarchy", db=db, namespace="nsa")["hierarchies"][0]["tree_version"]
    check("(a/e) identity.hierarchy pins tree_version + plan/prune/builder policy",
          hib.get("tree_version") == tv and hib.get("plan_policy", {}).get("id") == "shortlist_descend_v1"
          and hib.get("prune_policy", {}).get("id") == "safe_prune_v1"
          and hib.get("builder_policy", {}).get("id"), json.dumps(hib))
    return p

def test_d_safe_pruning(db, req, cv):
    print("\n[d] SEAM 2: a SOUND no-false-negative certificate prunes; a bounded descriptor / stale never prunes]")
    m = public_compile(db, cv, RARE, "global_synthesis")
    rc = m["result"]["packet"]["retrieval_completeness"]
    ev = set(e["record_version_id"] for e in m["result"]["packet"]["evidence"]["excerpts"])
    check("(d) a branch WAS pruned via a sound certificate (pruned_branch_count>=1)",
          rc["pruned_branch_count"] >= 1, "pruned=%d reasons=%s" % (rc["pruned_branch_count"], rc["prune_reasons"]))
    check("(d) every prune reason is a no-false-negative certificate (certified_absent:*)",
          bool(rc["prune_reasons"]) and all(str(r["reason"]).startswith("certified_absent:")
                                            for r in rc["prune_reasons"]), rc["prune_reasons"])
    check("(d) recall preserved despite pruning (required leaf still reached)", req in ev)
    check("(d) prune enforcement policy = safe_prune_v1/1.0.0",
          rc["prune_policy_id"] == "safe_prune_v1" and rc["prune_policy_version"] == "1.0.0")
    # #36-level: a bounded 'descriptor' channel NEVER prunes (only sound Bloom/exact channels can)
    node = as_run(op="shortlist", db=db, query=RARE, effective_allowed_namespaces=["nsa"], k=1)["nodes"][0]
    vb = as_run(op="prune-verdict", db=db, node_id=node["node_id"], channel="descriptor",
                key="zz_absent_key_9931")["verdict"]
    check("(d) #36 bounded 'descriptor' channel returns 'keep' even for a definitely-absent key", vb == "keep")
    # a COMMON term present across branches -> NO branch soundly prunable -> nothing pruned, recall kept
    mc = public_compile(db, cv, "lease", "global_synthesis")
    rcc = mc["result"]["packet"]["retrieval_completeness"]
    check("(d) a present-everywhere term prunes NO branch (all keep; no false-negative)",
          rcc["pruned_branch_count"] == 0, "pruned=%d" % rcc["pruned_branch_count"])

def test_d_stale_never_prunes(tmp):
    print("\n[d] a STALE navigation synopsis is NEVER a prune proof (retained, flagged, never a silent miss)]")
    db = os.path.join(tmp, "stale.db")
    recs = [{"record_id": "h%02d" % i, "record_version_id": "hv%02d" % i, "record_kind": "claim",
             "namespace": "nsa",
             "text": ("the decisive %s marker lease successor" % RARE) if i == 1 else
                     ("generic lease filler content alpha%02d" % i),
             "source_path": "nsa/h%02d.md" % i, "authority_level": "source_material"} for i in range(12)]
    as_run(op="ingest-records", db=db, records=recs, ingest_run={"producer": "i35gate", "namespace": "nsa"})
    as_run(op="build-hierarchy", db=db, max_fanout=4)
    cat = A.Catalog(db); cv = cat._get_corpus_version()
    hid = A.make_hierarchy_id("nsa", A.HIERARCHY_KIND_SOURCE_MODULE)
    stale_node = None
    for nd in cat.conn.execute("SELECT * FROM nodes WHERE hierarchy_id=? AND level=0 ORDER BY node_id", (hid,)):
        if RARE not in json.loads(nd["lexical_descriptor_json"] or "{}"):
            stale_node = nd; break
    members = json.loads(stale_node["member_ids_json"] or "[]")
    cat.close()
    base = public_compile(db, cv, RARE, "global_synthesis")
    base_pruned = base["result"]["packet"]["retrieval_completeness"]["pruned_branch_count"]
    check("[d] shallow baseline: >=1 rare-term-free sibling pruned via a sound certificate", base_pruned >= 1,
          "baseline pruned=%d" % base_pruned)
    as_run(op="hierarchy-mark-changed", db=db, leaf_id=members[0])   # #36 propagate -> stale ancestor path
    sm = public_compile(db, cv, RARE, "global_synthesis")
    src = sm["result"]["packet"]["retrieval_completeness"]
    sev = set(e["record_version_id"] for e in sm["result"]["packet"]["evidence"]["excerpts"])
    check("[d] stale_navigation_encountered flagged True", src["stale_navigation_encountered"] is True)
    check("[d] the stale sibling is RETAINED not pruned (pruned drops below baseline)",
          src["pruned_branch_count"] < base_pruned,
          "stale pruned=%d baseline=%d" % (src["pruned_branch_count"], base_pruned))
    check("[d] a stale synopsis never causes a silent miss (required leaf still reachable OR frontier not exhausted)",
          ("hv01" in sev) or (src["frontier_exhausted"] is False))

def test_c_source_chunk_reconstruction(tmp):
    print("\n[c] SEAM 1 over REAL source_chunk leaves: excerpt reconstructs to the ingested FILE (shipped op)]")
    db, cv, root = build_chunk_fixture(tmp)
    m = public_compile(db, cv, "fencing lease " + RARE, "global_synthesis", ns="nsc")
    ok = check("(c) public compile over a file-crawled (source_chunk) corpus ok", m.get("ok"),
               json.dumps({k: m.get(k) for k in ("ok", "error_code", "error")}))
    if not ok:
        return
    ev = m["result"]["packet"]["evidence"]["excerpts"]
    chunk_ev = [e for e in ev if e.get("record_kind") == "source_chunk"]
    check("(c) at least one source_chunk excerpt was hydrated + reached", len(chunk_ev) >= 1,
          "evidence kinds=%s" % [e.get("record_kind") for e in ev])
    allrepro = all(e["provenance"]["provenance_mode"] == "direct_span" and e["provenance"]["reproduced"] is True
                   for e in chunk_ev)
    check("(c) every source_chunk excerpt is a reproduced direct_span (span sha256 == excerpt_hash)", allrepro)

def test_e_foreign_descend_and_closure(db, cv):
    print("\n[e] a foreign/out-of-scope descend FAILS CLOSED; a mixed-corpus scoped compile stays clean]")
    # #36-level: descend on an nsb node while scoped to nsa -> authorized:False (count only, no metadata)
    nsb_nodes = as_run(op="shortlist", db=db, query="content", effective_allowed_namespaces=["nsb"], k=1)["nodes"]
    if nsb_nodes:
        d = A.run({"op": "descend", "db": db, "node_id": nsb_nodes[0]["node_id"], "retrieval_plan_id": "rp",
                   "effective_allowed_namespaces": ["nsa"], "hierarchy_version": None,
                   "corpus_snapshot": None})["result"]
        check("(e) descend on an nsb node while scoped to nsa FAILS CLOSED (authorized=False, no children)",
              d.get("authorized") is False and not d.get("children") and not d.get("leaf_members"),
              json.dumps({k: d.get(k) for k in ("authorized", "child_count", "leaf_member_count")}))
    # end-to-end: an nsa-scoped compile over the MIXED corpus emits a CLEAN packet with ZERO nsb metadata
    m = public_compile(db, cv, "fencing lease " + RARE, "global_synthesis")
    blob = json.dumps(m)
    check("(e) mixed-corpus nsa compile succeeds with NO nsb/SECRET metadata in the packet",
          m.get("ok") and "nsb" not in blob and "SECRET" not in blob)

def test_f_flat_gated_additive(db, req, cv):
    print("\n[b/f] the plan is ADDITIVE + GATED: a flat request is byte-identical with vs without the port trigger]")
    body_leaves = []
    cat = A.Catalog(db)
    for i, rvid in enumerate(("av00", "av01", req)):
        t = cat.conn.execute("SELECT text,record_id,source_path FROM records WHERE record_version_id=?",
                             (rvid,)).fetchone()
        b = t["text"].encode("utf-8"); ch = sha256_hex(b)
        body_leaves.append({"record_id": t["record_id"], "record_version_id": rvid, "record_kind": "claim",
                            "candidate_role": "evidence", "source_path": t["source_path"], "content_hash": ch,
                            "chunk_content_hash": ch, "span": {"start": 0, "end": len(b)},
                            "span_label": "bytes:0-%d" % len(b), "status": "current", "currentness": "current",
                            "namespace": "nsa", "source": "nsa", "source_version_id": "ver_" + rvid,
                            "authority_level": "source_material", "lexical_rank": i + 1,
                            "lexical_score": 1.0 - i * 0.01, "fused_rank": i + 1, "fused_score": 1.0 - i * 0.01,
                            "index_snapshot": cv, "corpus_version": cv, "tie_break_key": rvid,
                            "snippet": t["text"], "rank": i + 1})
    st = {}
    for r in cat.conn.execute("SELECT source_path,text FROM records WHERE namespace='nsa'"):
        st[r["source_path"]] = r["text"]
    cat.close()
    batches = [{"query_index": 0, "hits": body_leaves}]
    # A vs B are IDENTICAL requests differing ONLY by the presence of catalog_db_path (retriever + source_texts
    # + batches all held equal). For a NON-descend class the port is gated OFF, so the i35 construction path is
    # inert -> the two packets MUST be byte-identical (the plan is purely additive + gated).
    a1 = public_compile(db, cv, "look up the fencing lease claim", "local_factual", batches=batches,
                        source_texts=st, with_db=True)
    b1 = public_compile(db, cv, "look up the fencing lease claim", "local_factual", batches=batches,
                        source_texts=st, with_db=False)
    pa = a1["result"]["packet"]; pb = b1["result"]["packet"]
    check("(b) non-descend compile ok with artifact_search retriever+db_path set", a1.get("ok"))
    check("(f) NO retrieval_completeness / identity.hierarchy on the flat compile (plan gated off)",
          "retrieval_completeness" not in pa and "hierarchy" not in pa["identity"])
    check("(f) flat packet BYTE-IDENTICAL with vs without catalog_db_path (construction is additive + gated)",
          cc.canonical_json(pa) == cc.canonical_json(pb),
          "id a=%s b=%s" % (pa["packet_id"], pb["packet_id"]))
    # C: a DESCEND class but NO catalog_db_path -> still flat (no port constructed).
    c1 = public_compile(db, cv, RARE, "global_synthesis", with_db=False, batches=batches, source_texts=st)
    check("(b) descend class but NO catalog_db_path -> flat (no port)",
          "retrieval_completeness" not in c1["result"]["packet"])

def test_a_determinism(db, cv):
    print("\n[a/e] deterministic packet_id covering hierarchy identity (byte-identical on re-run)]")
    p1 = public_compile(db, cv, RARE, "global_synthesis")["result"]["packet"]
    p2 = public_compile(db, cv, RARE, "global_synthesis")["result"]["packet"]
    check("(e) packet_id byte-identical on re-run (deterministic)", p1["packet_id"] == p2["packet_id"],
          "%s vs %s" % (p1["packet_id"], p2["packet_id"]))
    check("(e) packet_id == cpkt_+sha256(body-without-packet_id)[:32] (id truly covers the hierarchy body)",
          p1["packet_id"] == "cpkt_" + cc.sha256_of_obj(
              {k: v for k, v in p1.items() if k != "packet_id"})[:32])

def main():
    print("== i35 PUBLIC artifact_search hierarchy-port GATE (REAL #36 tree + REAL #40 constructed port) ==")
    tmp = tempfile.mkdtemp(prefix="i35gate-")
    try:
        db = os.path.join(tmp, "typed.db")
        req, cv = build_typed_fixture(db)
        print("[fixture] typed.db corpus_version=%s required_leaf=%s" % (cv, req))
        test_a_b_c_e_public_typed(db, req, cv)
        test_d_safe_pruning(db, req, cv)
        test_d_stale_never_prunes(tmp)
        test_c_source_chunk_reconstruction(tmp)
        test_e_foreign_descend_and_closure(db, cv)
        test_f_flat_gated_additive(db, req, cv)
        test_a_determinism(db, cv)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\nI35-GATE RESULT: %d passed, %d failed" % (_PASS, _FAIL))
    return 0 if _FAIL == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
