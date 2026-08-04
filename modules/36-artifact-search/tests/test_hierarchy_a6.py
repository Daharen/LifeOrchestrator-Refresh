#!/usr/bin/env python3
"""A6 (D-0098, i34) off-machine gate for the bounded-fanout HIERARCHY built into artifact.search.

Pure cloud-python, deterministic, CPU-only (the sanctioned OFF-MACHINE FIRST gate). Drives the REAL worker via
artifact_search.run(...) + direct Catalog calls for the internal invariants (ABA race, safe-pruning,
propagation). Covers acceptance (a)-(i) of the worker brief. The pwsh Invoke-ArtifactSearchTests.ps1 covers the
same via the entrypoint on-device.

Exit 0 iff every check passes.
"""
import os, sys, json, tempfile, shutil, subprocess, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, SKILL)
import artifact_search as A  # noqa: E402

PASS = 0
FAIL = 0
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1; print("  [PASS] %s" % name)
    else:
        FAIL += 1; print("  [FAIL] %s %s" % (name, detail))

def run(**args):
    return A.run(args)

def payload(out):
    return out["result"]

def write_corpus(root, files):
    for rel, txt in files.items():
        p = os.path.join(root, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(txt)

def main():
    tmp = tempfile.mkdtemp(prefix="a6-")
    try:
        db = os.path.join(tmp, "cat.db")
        # ---- corpus: projA has MANY files ALL in one dir (low-cardinality/dominant grouping key test) ----
        rootA = os.path.join(tmp, "projA")
        filesA = {}
        for i in range(40):
            # a shared term 'frobnicator' in a few files; a unique term per file
            body = "shared frobnicator topic\n" if i % 7 == 0 else "generic content here\n"
            filesA["docs/file_%02d.md" % i] = "# Heading %02d\n\n%suniqueterm%02d alpha beta gamma\n" % (i, body, i)
        write_corpus(rootA, filesA)
        rootB = os.path.join(tmp, "projB")
        write_corpus(rootB, {"a.md": "# B\n\nprojb only content zeta\n", "b.md": "# B2\n\nmore projb delta\n"})

        oi = run(op="ingest", db=db, source="projA", root=rootA, embed_provider="mock")
        check("ingest projA ok", oi["ok"] and payload(oi)["counts"]["added"] == 40, json.dumps(payload(oi)["counts"]))
        oib = run(op="ingest", db=db, source="projB", root=rootB, embed_provider="mock")
        check("ingest projB ok", oib["ok"] and payload(oib)["counts"]["added"] == 2)

        # a few typed records in projA (evidence) + projB
        recs = [
            {"record_id": "d1", "record_version_id": "dv1", "record_kind": "decision", "namespace": "projA",
             "text": "decide to use frobnicator", "authority_level": "decision"},
            {"record_id": "s1", "record_version_id": "sv1", "record_kind": "summary", "namespace": "projA",
             "text": "summary alpha", "authority_level": "derived"},
            {"record_id": "d2", "record_version_id": "dv2", "record_kind": "decision", "namespace": "projB",
             "text": "projb decision epsilon", "authority_level": "decision"},
        ]
        orr = run(op="ingest-records", db=db, records=recs, ingest_run={"producer": "test", "namespace": "projA"})
        check("ingest-records ok", orr["ok"] and payload(orr)["counts"]["accepted"] == 3)

        sv = run(op="catalog", db=db)
        schema = payload(sv)["schema_version"]
        check("schema_version == 5", schema == "5", "got %s" % schema)
        digest_before = payload(sv)["digest"]
        sha_before = payload(sv)["shipped_tables_schema_sha"]
        # baseline flat search
        s_before = run(op="search", db=db, query="frobnicator", k=50)
        res_before = [(h["record_version_id"], h["rank"]) for h in payload(s_before)["results"]]
        node_hits_before = [h for h in payload(s_before)["results"] if h["record_kind"] == "node"]
        check("(f/d) flat search returns NO node records", len(node_hits_before) == 0)

        # =============== build the hierarchy (fanout 4 -> multi-level over 40+ leaves) ===============
        ob = run(op="build-hierarchy", db=db, max_fanout=4)
        bd = payload(ob)
        check("(a) build ok + all_valid", ob["ok"] and bd["all_valid"], json.dumps(bd.get("built", [{}])[0].get("problems", [])))
        by_ns = {b["namespace"]: b for b in bd["built"]}
        check("(e) two separate hierarchies built (proja, projb)", "proja" in by_ns and "projb" in by_ns, str(sorted(by_ns)))
        A_h = by_ns["proja"]
        check("(a) projA has nodes + a root + a tree_digest", A_h["node_count"] > 1 and A_h["root_node_id"] and A_h["tree_digest"])

        # ---- (h) additive: catalog_digest + shipped-table sha UNCHANGED by the build; flat search unchanged ----
        sv2 = run(op="catalog", db=db)
        check("(h) catalog_digest unchanged after build (nodes excluded)", payload(sv2)["digest"] == digest_before,
              "%s != %s" % (payload(sv2)["digest"][:12], digest_before[:12]))
        check("(h) shipped_tables_schema_sha unchanged", payload(sv2)["shipped_tables_schema_sha"] == sha_before)
        s_after = run(op="search", db=db, query="frobnicator", k=50)
        res_after = [(h["record_version_id"], h["rank"]) for h in payload(s_after)["results"]]
        check("(h/i) flat search results byte-identical after build", res_after == res_before)

        # ---- (i) integrity all green (incl. hierarchy invariants) ----
        ig = run(op="integrity", db=db)
        bad = [c for c in payload(ig)["checks"] if not c["ok"]]
        check("(i) integrity all checks pass", payload(ig)["ok"], json.dumps(bad))

        # =============== direct Catalog inspection ===============
        cat = A.Catalog(db)
        hid_A = A.make_hierarchy_id("proja", A.HIERARCHY_KIND_SOURCE_MODULE)
        nodes = list(cat.conn.execute("SELECT * FROM nodes WHERE hierarchy_id=? ORDER BY level,node_id", (hid_A,)))
        maxlevel = max(nd["level"] for nd in nodes)
        # ---- (b) balanced: depth is logarithmic (NOT a deep thin chain) despite one dominant dir key ----
        # 40 leaves, fanout 4 -> ceil(log4(40)) ~= 3 levels; a thin chain would be depth ~ 40.
        check("(b) balanced depth (no deep thin chain under a dominant key)", maxlevel <= 4, "maxlevel=%d node_count=%d" % (maxlevel, len(nodes)))
        # fanout + occupancy
        over = 0; leaf_parent_sizes = []
        for nd in nodes:
            deg = len(json.loads(nd["child_ids_json"] or "[]")) + len(json.loads(nd["member_ids_json"] or "[]"))
            if deg > 4: over += 1
            if nd["level"] == 0: leaf_parent_sizes.append(len(json.loads(nd["member_ids_json"] or "[]")))
        check("(b) no node exceeds MAX_FANOUT", over == 0)
        check("(b) leaf-parent occupancy balanced (min>=ceil/2)", (min(leaf_parent_sizes) >= 2), "sizes=%s" % leaf_parent_sizes)

        # ---- (a) projection == canonical edges for every node ----
        proj_ok = True
        for nd in nodes:
            proj_children = set(json.loads(nd["child_ids_json"] or "[]"))
            proj_members = set(json.loads(nd["member_ids_json"] or "[]"))
            edge_children = set(e["src_ref"] for e in cat.conn.execute(
                "SELECT src_ref FROM record_edges WHERE edge_kind='child_of_node' AND dst_ref=?", (nd["node_id"],)))
            edge_members = set(e["src_ref"] for e in cat.conn.execute(
                "SELECT src_ref FROM record_edges WHERE edge_kind='member_of_node' AND dst_ref=?", (nd["node_id"],)))
            if proj_children != edge_children or proj_members != edge_members:
                proj_ok = False; break
        check("(a) node child/member projection == canonical edges", proj_ok)

        # ---- (a) vector aggregate: present (chunks have mock vectors) + byte-reproducible; absent when empty ----
        leaf_parents = [nd for nd in nodes if nd["level"] == 0]
        va_present = [nd for nd in leaf_parents if nd["vector_aggregate_json"]]
        check("(a) vector_aggregate present on chunk leaf-parents", len(va_present) > 0)
        if va_present:
            va = json.loads(va_present[0]["vector_aggregate_json"])
            check("(a) vector_aggregate is sufficient statistics (sum+count+algo)",
                  "vector_sum" in va and "vector_count" in va and va["accumulation_algo"] == A.VEC_AGG_ACCUM_ALGO)
        cat.close()

        # ---- (b/i) byte-identical rebuild: same corpus -> identical tree_digest ----
        ob2 = run(op="build-hierarchy", db=db, max_fanout=4)
        bd2 = {b["namespace"]: b for b in payload(ob2)["built"]}
        check("(b/i) rebuild tree_digest identical (deterministic)",
              bd2["proja"]["tree_digest"] == A_h["tree_digest"] and bd2["projb"]["tree_digest"] == by_ns["projb"]["tree_digest"])
        # catalog_digest still stable across the rebuild
        check("(i) catalog_digest stable across rebuild", run(op="catalog", db=db)["result"]["digest"] == digest_before)

        # ---- (c) atomic tree-version publication: tree_version incremented; one current; pinned-version behavior ----
        cat = A.Catalog(db)
        cur = list(cat.conn.execute("SELECT tree_version,is_current FROM hierarchies WHERE hierarchy_id=?", (hid_A,)))
        check("(c) exactly one current version per hierarchy", sum(1 for r in cur if r["is_current"]) == 1 and len(cur) == 1)
        tv_now = [r["tree_version"] for r in cur if r["is_current"]][0]
        check("(c) tree_version incremented on rebuild (tv2)", tv_now == "tv2", tv_now)
        cat.close()
        # a compile pinning the OLD version tv1 is not served (fail-safe) -> pins one version
        sl_pin = run(op="shortlist", db=db, query="frobnicator", effective_allowed_namespaces=["projA"], hierarchy_version="tv1")
        check("(c) shortlist pinning a stale tree_version is not served (pins one version)",
              payload(sl_pin)["pinned_version_unavailable_count"] >= 1 and payload(sl_pin)["count"] == 0)

        # ---- (c) atomic: fault before commit -> prior tree intact ----
        try:
            run(op="build-hierarchy", db=db, max_fanout=8, _fault="before_hierarchy_commit")
            check("(c) fault injection raised", False, "no exception")
        except A.ASError as e:
            check("(c) fault injection before commit raised", e.code == "fault_injected")
        st = run(op="hierarchy", db=db, namespace="projA")
        h_after_fault = payload(st)["hierarchies"][0]
        check("(c) prior tree intact after aborted build (still tv2, max_fanout 4)",
              h_after_fault["tree_version"] == "tv2" and h_after_fault["max_fanout"] == 4)

        # =============== (f) authorization-bound shortlist/descend ===============
        sl = run(op="shortlist", db=db, query="frobnicator", effective_allowed_namespaces=["projA"])
        sld = payload(sl)
        check("(f) shortlist scoped to projA returns only projA nodes",
              sld["count"] >= 1 and all(n["namespace"] == "proja" for n in sld["nodes"]))
        check("(f) shortlist nodes are candidate_role=navigation (never evidence)",
              all(n["candidate_role"] == "navigation" for n in sld["nodes"]))
        # multi-ns scope -> SEPARATE roots (never a merged root)
        sl2 = run(op="shortlist", db=db, query="content", effective_allowed_namespaces=["projA", "projB"])
        roots_ns = sorted(n["namespace"] for n in payload(sl2)["nodes"] if n["is_root"])
        check("(e) multi-ns shortlist -> separate roots per namespace (no merged root)",
              "proja" in roots_ns and "projb" in roots_ns)

        rootA_id = h_after_fault["root_node_id"]
        de = run(op="descend", db=db, node_id=rootA_id, effective_allowed_namespaces=["projA"], retrieval_plan_id="plan1")
        ded = payload(de)
        check("(f) descend authorized returns direct children (frontier-expansion, not flat scan)",
              ded["authorized"] and ded["child_count"] >= 1 and ded["child_count"] <= 4)
        check("(f) descend carries stage lineage + retrieval_plan_id",
              ded["retrieval_plan_id"] == "plan1" and ded["parent_stage_id"] == "stage:shortlist:1")
        # unauthorized namespace -> fail closed, count only, NO identifying metadata
        de_no = run(op="descend", db=db, node_id=rootA_id, effective_allowed_namespaces=["projB"], retrieval_plan_id="p")
        dn = payload(de_no)
        check("(f) descend on out-of-scope node fails closed (count-only, no metadata)",
              dn["authorized"] is False and dn["child_count"] == 0 and dn["children"] == [] and "namespace" not in dn)
        # a foreign/bogus node_id -> identical opaque fail-closed shape
        de_bogus = run(op="descend", db=db, node_id="nd_deadbeefdeadbeefdeadbeef", effective_allowed_namespaces=["projA"], retrieval_plan_id="p")
        db_ = payload(de_bogus)
        check("(f) descend on a foreign node_id fails closed (count-only)",
              db_["authorized"] is False and db_["child_count"] == 0 and db_["children"] == [])

        # =============== (g) SAFE-PRUNING channel predicates ===============
        cat = A.Catalog(db)
        # a leaf-parent node with known member text
        lp = cat.conn.execute("SELECT * FROM nodes WHERE hierarchy_id=? AND level=0 ORDER BY node_id LIMIT 1", (hid_A,)).fetchone()
        lp_id = lp["node_id"]
        # gather the ACTUAL terms present in this node's subtree (must NEVER be pruned -- no false negative)
        member_ids = json.loads(lp["member_ids_json"] or "[]")
        present_terms = set()
        for m in member_ids:
            occ = cat.conn.execute("SELECT text FROM chunks WHERE chunk_occurrence_id=?", (m,)).fetchone()
            if occ:
                present_terms |= set(A._a6_terms(occ["text"]))
        no_false_neg = all(cat.prune_verdict(lp_id, "lexical", t) == "keep" for t in present_terms)
        check("(g) NO false-negative prune: every present term is KEPT", no_false_neg)
        check("(g) a definitely-absent term is PRUNED (Bloom no-false-negative absence)",
              cat.prune_verdict(lp_id, "lexical", "zzz_absent_termxyz_9931") == "prune")
        check("(g) a bounded DESCRIPTOR channel NEVER prunes", cat.prune_verdict(lp_id, "descriptor", "anything") == "keep")
        check("(g) the vector channel NEVER prunes (centroid alone cannot exclude)",
              cat.prune_verdict(lp_id, "vector", "x") == "keep")
        # kind: exact histogram membership
        check("(g) kind prune: absent kind pruned", cat.prune_verdict(lp_id, "kind", "episode") == "prune")
        check("(g) kind keep: present kind kept", cat.prune_verdict(lp_id, "kind", "source_chunk") == "keep")
        # authority: exact set membership
        check("(g) authority prune: absent authority pruned", cat.prune_verdict(lp_id, "authority", "top_secret_absent") == "prune")
        check("(g) authority keep: present authority kept", cat.prune_verdict(lp_id, "authority", "source_material") == "keep")

        # =============== (d) three axes + generations + CAS ABA + propagation + summary_stale routes ===========
        # pick a member leaf and propagate its change
        leaf = member_ids[0]
        anc = cat._node_ancestors(cat._nodes_for_leaf(leaf)[0])
        dirtied = cat.propagate_leaf_change(leaf)
        check("(d) propagation dirties the full ancestor path", set(anc).issubset(set(dirtied)))
        # every dirtied node is stale + summary_stale + generation bumped; a node OFF the path stays fresh
        stale_rows = list(cat.conn.execute("SELECT node_id,synopsis_freshness,status,subtree_generation,synopsis_generation FROM nodes WHERE node_id IN (%s)" % ",".join("?" for _ in dirtied), dirtied))
        check("(d) dirtied nodes are synopsis stale + status summary_stale (evidence status axis separate)",
              all(r["synopsis_freshness"] == "stale" and r["status"] == "summary_stale" for r in stale_rows))
        check("(d) dirtied nodes: subtree_generation advanced past synopsis_generation (topology stays valid)",
              all(r["subtree_generation"] > r["synopsis_generation"] for r in stale_rows))
        off_path = cat.conn.execute("SELECT COUNT(*) n FROM nodes WHERE hierarchy_id=? AND synopsis_freshness='fresh'", (hid_A,)).fetchone()["n"]
        check("(d) nodes off the ancestor path stay fresh (local update, not global)", off_path >= 1)
        # summary_stale routes-but-never-answers: the (stale) root still shortlists (routes); nodes never in search
        sl_stale = run(op="shortlist", db=db, query="frobnicator", effective_allowed_namespaces=["projA"])
        check("(d) a summary_stale node still ROUTES (shortlist returns it) + flags staleness",
              payload(sl_stale)["count"] >= 1 and payload(sl_stale)["stale_navigation_encountered"] is True)
        s_stale = run(op="search", db=db, query="frobnicator", k=50, filters={"mode": "current_only"})
        check("(d) summary_stale never ANSWERS: no node in current_only evidence search",
              all(h["record_kind"] != "node" for h in payload(s_stale)["results"]))

        # ABA / lost-update: regen with a STALE expected generation must NOT clear
        target = dirtied[-1]  # the root (deepest ancestor)
        g_now = cat.conn.execute("SELECT subtree_generation FROM nodes WHERE node_id=?", (target,)).fetchone()["subtree_generation"]
        r1 = cat.regen_node(target, expected_generation=g_now)
        check("(d) regen with the current generation CLEARS (fresh)", r1["cleared"] is True and
              cat.conn.execute("SELECT synopsis_freshness FROM nodes WHERE node_id=?", (target,)).fetchone()["synopsis_freshness"] == "fresh")
        # now a 2nd mutation advances the generation; a LATE regen from the OLD snapshot must fail (ABA)
        cat.propagate_leaf_change(leaf)
        g_stale = g_now  # the snapshot a slow regen would have read
        r2 = cat.regen_node(target, expected_generation=g_stale)
        fresh_after = cat.conn.execute("SELECT synopsis_freshness FROM nodes WHERE node_id=?", (target,)).fetchone()["synopsis_freshness"]
        check("(d) ABA/lost-update: a regen from a stale generation is REFUSED (node stays stale)",
              r2["cleared"] is False and fresh_after == "stale")
        # a stale synopsis is NEVER eligible to supply a prune proof
        check("(g/d) a STALE node never prunes (even a definitely-absent key)",
              cat.prune_verdict(target, "lexical", "zzz_absent_termxyz_9931") == "keep")
        cat.close()
        # refresh clears everything deterministically
        rf = run(op="refresh-hierarchy", db=db, namespace="projA")
        check("(d) refresh regenerates all stale nodes", payload(rf)["cleared"] == payload(rf)["stale"])

        # =============== (h/i) additive 4->5 migration: v4 seed -> v5, shipped tables byte-identical ===========
        v4worker = os.path.join(SKILL, "fixtures", "artifact_search_v4.py")
        db4 = os.path.join(tmp, "v4.db")
        if os.path.exists(v4worker):
            # seed with the frozen v4 worker (subprocess; its main() reads an args json + writes meta)
            def run_v4(args):
                aj = os.path.join(tmp, "v4args.json"); mj = os.path.join(tmp, "v4meta.json")
                args = dict(args); args["meta_path"] = mj
                with open(aj, "w") as fh: json.dump(args, fh)
                subprocess.run([sys.executable, v4worker, aj], capture_output=True)
                with open(mj) as fh: return json.load(fh)
            m1 = run_v4({"op": "ingest", "db": db4, "source": "projA", "root": rootA, "embed_provider": "mock"})
            check("(h) v4 seed built at schema_version 4", m1.get("worker", {}).get("schema_version") == "4")
            cat4 = A.Catalog(db4)  # opening with the NEW worker migrates 4->5 in place
            check("(h) v4 db migrates to schema 5 in place", cat4.schema_version() == "5")
            sha_v4migrated = cat4.shipped_tables_schema_sha()
            cat4.close()
            # a fresh v5 db's shipped-table sha (should match -- additive migration rewrote none of them)
            dbf = os.path.join(tmp, "fresh.db")
            run(op="ingest", db=dbf, source="projA", root=rootA, embed_provider="mock")
            catf = A.Catalog(dbf); sha_fresh = catf.shipped_tables_schema_sha(); catf.close()
            check("(h) migrated-v4 shipped_tables_schema_sha == fresh-v5 (byte-identical shipped tables)",
                  sha_v4migrated == sha_fresh, "%s vs %s" % (sha_v4migrated[:12], sha_fresh[:12]))
            mg = run(op="migrate", db=db4)
            check("(h) migrate reports 4->5 + integrity ok", payload(mg)["schema_version"] == "5" and payload(mg)["integrity"]["ok"])
            # records/chunks preserved: a search on the migrated db still works
            sm = run(op="search", db=db4, query="frobnicator", k=5)
            check("(i) migrated db still serves flat search", payload(sm)["count"] >= 1)
        else:
            check("(h) v4 fixture present", False, "missing fixtures/artifact_search_v4.py")

        # ---- (i) zero-nodes namespace = flat behavior: a records-only ns with NO vectors -> vector_aggregate ABSENT ----
        dbn = os.path.join(tmp, "novec.db")
        run(op="ingest-records", db=dbn, records=[
            {"record_id": "x1", "record_version_id": "xv1", "record_kind": "claim", "namespace": "novec", "text": "claim one alpha"},
            {"record_id": "x2", "record_version_id": "xv2", "record_kind": "claim", "namespace": "novec", "text": "claim two beta"},
        ], ingest_run={"producer": "t", "namespace": "novec"})
        run(op="build-hierarchy", db=dbn, max_fanout=4)
        catn = A.Catalog(dbn)
        hidn = A.make_hierarchy_id("novec", A.HIERARCHY_KIND_SOURCE_MODULE)
        nnodes = list(catn.conn.execute("SELECT vector_aggregate_json FROM nodes WHERE hierarchy_id=?", (hidn,)))
        catn.close()
        check("(a) vector_aggregate ABSENT while the vector channel is empty",
              len(nnodes) >= 1 and all(nd["vector_aggregate_json"] is None for nd in nnodes))

        print("\nRESULT: %d/%d passed  (fail=%d)" % (PASS, PASS + FAIL, FAIL))
        print("ALLPASS=%s" % ("true" if FAIL == 0 else "false"))
        return 0 if FAIL == 0 else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
