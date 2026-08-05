#!/usr/bin/env python3
"""i36 (FANOUT_AGENT_002) off-machine gate for the ADDITIVE, READ-ONLY by-record_version_id `get-record`
op added to artifact.search (0.5.0 -> 0.6.0) -- the i35 Lane A FOLD RECONCILIATION (D-0100): #40's leaf
hydration reached into #36's `records` table because #36 had NO by-rvid body-fetch op. get-record returns,
per rvid, the FULL s1 envelope + the evidence body sufficient for #40 leaf HYDRATION, reusing the shipped
provenance derivation.

Pure cloud-python, deterministic, CPU-only (the sanctioned OFF-MACHINE FIRST gate). Drives the REAL worker
via artifact_search.run(...). Covers acceptance (a)-(f) of the worker brief. The pwsh
Invoke-ArtifactSearchTests.ps1 covers the same via the entrypoint on-device.

Exit 0 iff every check passes.
"""
import os, sys, json, tempfile, shutil, hashlib

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

def sha256_text(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def main():
    tmp = tempfile.mkdtemp(prefix="getrec-i36-")
    try:
        db = os.path.join(tmp, "cat.db")
        # ---- corpus: projA source_chunks + projA/projB typed records (evidence, working, supersession) ----
        rootA = os.path.join(tmp, "projA")
        filesA = {}
        for i in range(8):
            filesA["docs/file_%02d.md" % i] = "# Heading %02d\n\nalpha%02d frobnicator beta gamma delta\n" % (i, i)
        write_corpus(rootA, filesA)
        oi = run(op="ingest", db=db, source="projA", root=rootA, embed_provider="mock")
        check("setup: ingest projA (8 chunk files)", oi["ok"] and payload(oi)["counts"]["added"] == 8,
              json.dumps(payload(oi)["counts"]))

        recs = [
            # a projA decision (evidence) with a real text body
            {"record_id": "d1", "record_version_id": "dv1", "record_kind": "decision", "namespace": "projA",
             "text": "decide to adopt the frobnicator approach", "authority_level": "decision"},
            # a projB decision (FOREIGN to a projA-scoped caller)
            {"record_id": "d2", "record_version_id": "dv2", "record_kind": "decision", "namespace": "projB",
             "text": "projb secret decision zeta", "authority_level": "decision"},
            # a projA WORKING record scoped to task T1 (U3' conjunctive access)
            {"record_id": "w1", "record_version_id": "wv1", "record_kind": "working", "namespace": "projA",
             "task_id": "T1", "content_role": "working_state", "text": "working state for task T1 epsilon"},
            # a supersession chain in projA: R1 (current) superseded_by R2 (current, live successor)
            {"record_id": "r", "record_version_id": "r1", "record_kind": "claim", "namespace": "projA",
             "status": "current", "text": "claim first revision omega",
             "edges": [{"edge_kind": "superseded_by", "dst_ref": "r2", "dst_kind": "record"}]},
            {"record_id": "r", "record_version_id": "r2", "record_kind": "claim", "namespace": "projA",
             "status": "current", "text": "claim second revision omega"},
        ]
        orr = run(op="ingest-records", db=db, records=recs, ingest_run={"producer": "test", "namespace": "projA"})
        check("setup: ingest-records accepted 5", orr["ok"] and payload(orr)["counts"]["accepted"] == 5,
              json.dumps(payload(orr)["counts"]))

        cat0 = run(op="catalog", db=db)
        digest_before = payload(cat0)["digest"]
        sha_before = payload(cat0)["shipped_tables_schema_sha"]
        check("setup: schema_version == 5 (NO migration)", payload(cat0)["schema_version"] == "5")

        # a source_chunk rvid (= chunk_occurrence_id) from list-records
        lr = run(op="list-records", db=db, filters={"namespace": "projA", "record_kind": "source_chunk"}, limit=50)
        chunk_rvids = [r["record_version_id"] for r in payload(lr)["records"]]
        check("setup: list-records yields source_chunk rvids", len(chunk_rvids) == 8)
        sc_rvid = sorted(chunk_rvids)[0]

        # ============================ (a) envelope + evidence body for #40 hydration ============================
        g = payload(run(op="get-record", db=db, target_id="dv1", effective_allowed_namespaces=["projA"]))
        check("(a) get-record found the typed record dv1", g["found_count"] == 1 and g["requested"] == 1)
        rec = g["records"][0]
        env = rec["envelope"]; ev = rec["evidence"]
        check("(a) top-level identity fields present",
              rec["record_version_id"] == "dv1" and rec["record_kind"] == "decision" and rec["namespace"] == "projA")
        check("(a) envelope carries the full s1 fields",
              all(k in env for k in ("record_id", "record_version_id", "record_kind", "namespace", "content_hash",
                                     "status", "authority_level", "sensitivity_class", "valid_from", "valid_to",
                                     "source_version_id", "source_span", "provenance_mode", "parent_edges", "child_edges")))
        check("(a) evidence carries the hydration body (text + provenance)",
              ev.get("text") == "decide to adopt the frobnicator approach"
              and all(k in ev for k in ("content_hash", "span", "span_label", "section_path", "heading",
                                        "status", "currentness", "authority_level", "namespace",
                                        "provenance_mode", "provenance", "embedding_space_id", "source_version_id")))
        check("(a) evidence is a DIRECT fetch (retrieval-stage lineage stripped)",
              "retrieval_stage_id" not in ev and "parent_stage_id" not in ev and "retrieval_plan_id" not in ev)

        # source_chunk rvid -> envelope + evidence with text/span/hashes (chunk-backed)
        gc = payload(run(op="get-record", db=db, target_id=sc_rvid, effective_allowed_namespaces=["projA"]))
        check("(a) get-record resolves a source_chunk rvid (chunk_occurrence_id)", gc["found_count"] == 1)
        crec = gc["records"][0]; cev = crec["evidence"]
        check("(a) source_chunk evidence: text + span + chunk_content_hash + content_hash + abs_path",
              crec["record_kind"] == "source_chunk" and cev.get("text")
              and cev.get("chunk_content_hash") and cev.get("content_hash")
              and cev.get("span") and "start" in cev["span"] and "end" in cev["span"])

        # the FOLD flow: descend leaf_members -> get-record hydrates each (the exact #40 path)
        run(op="build-hierarchy", db=db, max_fanout=4)
        st = payload(run(op="hierarchy", db=db, namespace="projA"))
        rootA_id = st["hierarchies"][0]["root_node_id"]
        de = payload(run(op="descend", db=db, node_id=rootA_id, effective_allowed_namespaces=["projA"], retrieval_plan_id="p1"))
        # walk down to leaf members (descend children until we hit leaf_members)
        frontier = [rootA_id]; leaf_rvids = []; guard = 0
        while frontier and guard < 50:
            guard += 1
            nid = frontier.pop(0)
            d = payload(run(op="descend", db=db, node_id=nid, effective_allowed_namespaces=["projA"], retrieval_plan_id="p1"))
            if not d.get("authorized"):
                continue
            leaf_rvids.extend([m["record_version_id"] for m in d.get("leaf_members", [])])
            frontier.extend([c["node_id"] for c in d.get("children", [])])
        leaf_rvids = sorted(set(leaf_rvids))
        check("(a/fold) descend surfaced leaf_member rvids", len(leaf_rvids) >= 8, "n=%d" % len(leaf_rvids))
        gh = payload(run(op="get-record", db=db, rvids=leaf_rvids, effective_allowed_namespaces=["projA"]))
        check("(a/fold) get-record HYDRATES every descend leaf_member (the D-0100 seam)",
              gh["found_count"] == len(leaf_rvids) and gh["namespace_violation_count"] == 0 and gh["unresolved_count"] == 0,
              json.dumps({"found": gh["found_count"], "req": len(leaf_rvids)}))
        check("(a/fold) every hydrated leaf carries text + provenance",
              all(r["evidence"].get("text") and r["evidence"].get("provenance") for r in gh["records"]))

        # ============================ (b) provenance holds ============================
        # source_chunk: chunk_content_hash == sha256(canonical chunk text); == export-chunk-texts entry
        ex = payload(run(op="export-chunk-texts", db=db))
        ex_by_chunk = {c["chunk_id"]: c for c in ex["chunks"]}
        prov_ok = True; prov_detail = ""
        for r in gh["records"]:
            if r["record_kind"] != "source_chunk":
                continue
            e = r["evidence"]
            if sha256_text(e["text"]) != e["chunk_content_hash"]:
                prov_ok = False; prov_detail = "chunk_content_hash != sha256(text) for %s" % r["record_version_id"]; break
            xc = ex_by_chunk.get(e["chunk_id"])
            if xc is None or xc["text"] != e["text"] or xc["chunk_content_hash"] != e["chunk_content_hash"] \
               or xc["span"] != e["span"]:
                prov_ok = False; prov_detail = "export-chunk-texts mismatch for %s" % r["record_version_id"]; break
        check("(b) source_chunk provenance holds (chunk_content_hash==sha256(text) & matches export-chunk-texts)",
              prov_ok, prov_detail)
        # typed record: content_hash == sha256(text); record_content_hash == content_hash
        check("(b) typed-record provenance holds (content_hash == sha256(text))",
              sha256_text(ev["text"]) == ev["content_hash"] and ev.get("record_content_hash") == ev["content_hash"],
              "%s vs %s" % (ev.get("content_hash", "")[:12], sha256_text(ev["text"])[:12]))

        # ============================ (c) namespace closure (A5/U1' + U3') ============================
        # foreign rvid (projB record) scoped to projA -> count-only, NO identifying metadata
        gf = payload(run(op="get-record", db=db, target_id="dv2", effective_allowed_namespaces=["projA"]))
        blob = json.dumps(gf)
        check("(c) foreign rvid fails closed: count-only, NO record returned",
              gf["found_count"] == 0 and gf["namespace_violation_count"] == 1 and gf["records"] == [])
        check("(c) foreign rvid leaks NO identifying metadata (no projB ns / secret text / path)",
              ("projB" not in blob) and ("projb" not in blob) and ("secret" not in blob) and ("zeta" not in blob))
        # a bogus rvid -> unresolved count-only (no metadata)
        gb = payload(run(op="get-record", db=db, rvids=["occ_deadbeefdeadbeefdeadbeef", "nope@9"], effective_allowed_namespaces=["projA"]))
        check("(c) unknown rvids -> unresolved_count only (no leak)",
              gb["found_count"] == 0 and gb["unresolved_count"] == 2 and gb["namespace_violation_count"] == 0)
        # working-kind: default REJECT without conjunctive task_id + in-scope namespace
        gw_noscope = payload(run(op="get-record", db=db, target_id="wv1", effective_allowed_namespaces=["projA"]))
        check("(c/U3') working rvid WITHOUT task_id -> denied (count-only)",
              gw_noscope["found_count"] == 0 and gw_noscope["working_denied_count"] == 1)
        gw_wrongtask = payload(run(op="get-record", db=db, target_id="wv1", effective_allowed_namespaces=["projA"], task_id="T2"))
        check("(c/U3') working rvid with WRONG task_id -> denied", gw_wrongtask["working_denied_count"] == 1)
        gw_notns = payload(run(op="get-record", db=db, target_id="wv1", task_id="T1"))  # unscoped ns
        check("(c/U3') working rvid with task_id but NO namespace authorization -> denied",
              gw_notns["found_count"] == 0 and gw_notns["working_denied_count"] == 1)
        gw_ok = payload(run(op="get-record", db=db, target_id="wv1", effective_allowed_namespaces=["projA"], task_id="T1"))
        check("(c/U3') working rvid with CONJUNCTIVE task_id + in-scope namespace -> returned",
              gw_ok["found_count"] == 1 and gw_ok["records"][0]["record_kind"] == "working"
              and gw_ok["records"][0]["evidence"]["text"] == "working state for task T1 epsilon")
        # explicit EMPTY effective set -> zero results, fail-closed
        ge = payload(run(op="get-record", db=db, target_id="dv1", effective_allowed_namespaces=[]))
        check("(c) explicit EMPTY effective set -> zero results (fail-closed)",
              ge["found_count"] == 0 and ge["namespace_violation_count"] == 1 and ge["namespace_enforced"] is True)
        # unscoped (absent) -> back-compat: the record resolves
        gu = payload(run(op="get-record", db=db, target_id="dv1"))
        check("(c) absent effective set -> unscoped back-compat (resolves)",
              gu["found_count"] == 1 and gu["namespace_enforced"] is False)

        # ============================ (d) version-exact default + current_only + no migration ============================
        gr1 = payload(run(op="get-record", db=db, target_id="r1", effective_allowed_namespaces=["projA"]))
        r1rec = gr1["records"][0]
        check("(d) version-exact by default: r1 returned exactly (a predecessor with a live successor)",
              gr1["found_count"] == 1 and r1rec["record_version_id"] == "r1")
        check("(d) r1 surfaces catalog-computed supersession flags (effective_current False, superseded_by=[r2])",
              r1rec["effective_current"] is False and r1rec["superseded_by"] == ["r2"])
        gr1c = payload(run(op="get-record", db=db, target_id="r1", effective_allowed_namespaces=["projA"], current_only=True))
        check("(d) current_only EXCLUDES the superseded predecessor r1 (catalog-computed, pool-independent)",
              gr1c["found_count"] == 0 and gr1c["current_excluded_count"] == 1)
        gr2c = payload(run(op="get-record", db=db, target_id="r2", effective_allowed_namespaces=["projA"], current_only=True))
        check("(d) current_only KEEPS the live successor r2",
              gr2c["found_count"] == 1 and gr2c["records"][0]["effective_current"] is True)
        # a batch mixing r1 + r2 under current_only -> only r2
        grb = payload(run(op="get-record", db=db, rvids=["r1", "r2"], effective_allowed_namespaces=["projA"], current_only=True))
        check("(d) current_only batch: only the live r2 hydrates (1 excluded)",
              grb["found_count"] == 1 and grb["current_excluded_count"] == 1
              and grb["records"][0]["record_version_id"] == "r2")
        check("(d) schema_version stays 5 (NO migration by get-record)",
              gr1["schema_version"] == "5")

        # ============================ (e) regression: byte-identical existing paths + determinism ============================
        cat1 = run(op="catalog", db=db)
        check("(e) catalog_digest UNCHANGED by get-record (read-only, no corpus writes)",
              payload(cat1)["digest"] == digest_before, "%s != %s" % (payload(cat1)["digest"][:12], digest_before[:12]))
        check("(e) shipped_tables_schema_sha unchanged", payload(cat1)["shipped_tables_schema_sha"] == sha_before)
        # determinism: two identical get-record runs are byte-identical
        a = payload(run(op="get-record", db=db, rvids=["dv1", sc_rvid, "r1"], effective_allowed_namespaces=["projA"]))
        b = payload(run(op="get-record", db=db, rvids=["dv1", sc_rvid, "r1"], effective_allowed_namespaces=["projA"]))
        for kvol in ("db",):
            a.pop(kvol, None); b.pop(kvol, None)
        check("(e) get-record is DETERMINISTIC (byte-identical re-run)",
              json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True))
        # input-permutation independence: reversed rvids -> identical canonical records[] order
        c = payload(run(op="get-record", db=db, rvids=["r1", sc_rvid, "dv1"], effective_allowed_namespaces=["projA"]))
        c.pop("db", None)
        check("(e) records[] canonical (input-permutation independent)",
              [r["record_version_id"] for r in a["records"]] == [r["record_version_id"] for r in c["records"]])
        # integrity still green
        ig = run(op="integrity", db=db)
        check("(e) integrity all green after get-record activity", payload(ig)["ok"])

        # ============================ (f) worker version bumped ============================
        check("(f) WORKER_VERSION bumped to 0.6.0", A.WORKER_VERSION == "0.6.0", A.WORKER_VERSION)
        check("(f) missing rvid raises a clean error", _raises_missing_rvid(db))

        print("\nRESULT: %d/%d passed  (fail=%d)" % (PASS, PASS + FAIL, FAIL))
        print("ALLPASS=%s" % ("true" if FAIL == 0 else "false"))
        return 0 if FAIL == 0 else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def _raises_missing_rvid(db):
    try:
        A.run({"op": "get-record", "db": db, "effective_allowed_namespaces": ["projA"]})
        return False
    except A.ASError as e:
        return e.code == "missing_rvid"


if __name__ == "__main__":
    sys.exit(main())
