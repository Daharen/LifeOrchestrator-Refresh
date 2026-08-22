#!/usr/bin/env python
# test_repo_intel.py -- off-machine, stdlib-only determinism/validator gate for repo.intel (Module 38).
#
# Pure Python (no pwsh, no third-party): drives repo_intel.py directly over the bundled fixture repo and a
# bounded real slice, asserting the MVP acceptance criteria (>=4 record_kinds, complete provenance,
# deterministic double-run byte-identity, parser-failure surfacing + exclusion, s1 validator pass +
# tamper-detection, edge-endpoint resolution, ingest_records shaping). Complements the pwsh harness
# (Invoke-RepoIntelTests.ps1) which additionally proves the entrypoint + envelope. Prints RESULT/ALLPASS
# and exits with the failure count.
#
#   python3 tests/test_repo_intel.py
import os, sys, json, hashlib, shutil, tempfile, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, SKILL)
import repo_intel as ri  # noqa: E402

FIXTURE = os.path.join(SKILL, "fixtures", "repo")
PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print("  [PASS] %s" % name)
    else:
        FAIL += 1
        print("  [FAIL] %s %s" % (name, detail))


def index(root, namespace, outdir, **kw):
    args = {"op": "index", "root": root, "namespace": namespace, "output_dir": outdir}
    args.update(kw)
    return ri.do_index(args)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    tmp = tempfile.mkdtemp(prefix="m38-py-")
    try:
        # ---- 1) index the clean fixture ----
        o1 = os.path.join(tmp, "o1")
        p = index(FIXTURE, "fixture", o1)
        check("index: >=4 record_kinds", len(p["record_kinds"]) >= 4, str(p["record_kinds"]))
        for k in ("symbol", "entity", "relationship", "skill", "summary"):
            check("index: kind '%s' present" % k, k in p["record_kinds"])
        check("index: validation.ok", p["validation"]["ok"], str(p["validation"]["errors"][:3]))
        check("index: 0 parse_failures on clean fixture", p["parse_failure_count"] == 0)
        check("index: records_digest is 64 hex",
              len(p["records_digest"]) == 64 and all(c in "0123456789abcdef" for c in p["records_digest"]))
        check("index: >=1 symbol and >=1 skill",
              p["record_counts_by_kind"].get("symbol", 0) >= 1 and p["record_counts_by_kind"].get("skill", 0) >= 1)
        # edges: total>0 and none unresolved (validator already asserts; cross-check summary)
        es = p["edge_summary"]
        check("index: edges total>0", es["total"] > 0, str(es))
        digest1 = p["records_digest"]

        # ---- 2) deterministic double-run: byte-identical canonical artifacts ----
        o2 = os.path.join(tmp, "o2")
        p2 = index(FIXTURE, "fixture", o2)
        check("deterministic: records_digest identical", p2["records_digest"] == digest1)
        allsame = True
        for name in ("records.jsonl", "records.json", "ingest_records.json", "index_manifest.json",
                     "inventory.json", "parse_failures.json", "summary.md"):
            if sha(os.path.join(o1, name)) != sha(os.path.join(o2, name)):
                allsame = False
        check("deterministic: ALL canonical artifacts byte-identical", allsame)

        # ---- 3) every record passes the s1 validator; ids are content-derived ----
        recs = [json.loads(l) for l in open(os.path.join(o1, "records.jsonl"), encoding="utf-8")]
        v = ri.validate_records(recs)
        check("validator: clean records ok", v["ok"], str(v["errors"][:3]))
        # id integrity: recompute content_hash + record_version_id
        r0 = recs[0]
        ch = ri._h(ri.canon(r0["payload"]))
        check("id-integrity: content_hash == _h(canon(payload))", ch == r0["content_hash"])
        check("id-integrity: record_version_id derivation",
              r0["record_version_id"] == "rv_" + ri._h(r0["record_id"] + "\0" + ch)[:24])

        # ---- 4) provenance: a symbol span slices back to source containing the symbol name ----
        sym = next(r for r in recs if r["record_kind"] == "symbol" and r["payload"]["name"] == "Get-Thing")
        raw = open(os.path.join(FIXTURE, sym["source_path"]), "rb").read()
        sl = raw[sym["source_span"]["start"]:sym["source_span"]["end"]].decode("utf-8")
        check("provenance: symbol span slices back to 'Get-Thing'", "Get-Thing" in sl, repr(sl))
        check("provenance: symbol carries source_version_id + pwsh fingerprint",
              sym["source_version_id"] and "pwsh" in (sym["parser_fingerprint"] or ""))

        # ---- 5) relationships: resolvable import + external + tests + produces_schema ----
        rels = [r for r in recs if r["record_kind"] == "relationship"]
        imp = [r for r in rels if r["payload"]["relationship_type"] == "imports"]
        check("rel: a dot-source import resolves in-corpus",
              any((not r["payload"]["external"]) and str(r["payload"]["to"] or "").endswith("Helper.psm1") for r in imp))
        check("rel: an external import is flagged external",
              any(r["payload"]["external"] for r in imp))
        check("rel: tests edge present", any(r["payload"]["relationship_type"] == "tests" for r in rels))
        check("rel: produces_schema edge present", any(r["payload"]["relationship_type"] == "produces_schema" for r in rels))
        # every relationship's in-corpus derivation_refs resolve
        ids = set(r["record_id"] for r in recs)
        check("rel: all in-corpus derivation_refs resolve",
              all(all(d in ids for d in r["derivation_refs"]) for r in rels))

        # ---- 6) markdown fence-awareness + breadcrumbs ----
        secs = [r for r in recs if r["record_kind"] == "summary" and r["payload"].get("summary_type") == "markdown_section"]
        check("md: fenced '## Not A Heading' is NOT a section",
              not any(r["payload"]["heading"] == "Not A Heading" for r in secs))
        check("md: nested breadcrumb 'Guide > Setup > Detailed Steps'",
              any(r["payload"]["section_path"] == "Guide > Setup > Detailed Steps" for r in secs))

        # ---- 7) ingest_records.json shape (the #36 0.2 drop-in) ----
        ing = json.load(open(os.path.join(o1, "ingest_records.json"), encoding="utf-8"))
        check("ingest_records: {schema,namespace,records[]} + count matches",
              "schema" in ing and "namespace" in ing and ing["record_count"] == len(ing["records"]))
        check("ingest_records: record chunker_fingerprint is null (typed, not chunk)",
              ing["records"][0]["chunker_fingerprint"] is None)

        # ---- 8) parse-failure surfacing + exclusion (inject into a temp copy) ----
        mut = os.path.join(tmp, "mut")
        shutil.copytree(FIXTURE, mut)
        open(os.path.join(mut, "blob.bin"), "wb").write(bytes([0, 1, 2, 66, 255, 254]))
        open(os.path.join(mut, "modules", "50-sample", "data", "broken.json"), "w").write("{ bad json, }")
        open(os.path.join(mut, "modules", "50-sample", "src_broken.py"), "w").write("def oops(\n  return 1\n")
        open(os.path.join(mut, "notes_bad.txt"), "wb").write(b"good \xff\xfe bad")
        pm = index(mut, "mut", os.path.join(tmp, "om"))
        reasons = set(pf["reason"] for pf in pm["parse_failures"])
        check("parse-failure: invalid_json surfaced", "invalid_json" in reasons)
        check("parse-failure: python_syntax_error surfaced", "python_syntax_error" in reasons)
        check("parse-failure: not_utf8 surfaced", "not_utf8" in reasons)
        check("exclusion: blob.bin excluded (excluded_count>=1)", pm["excluded_count"] >= 1)
        inv = json.load(open(os.path.join(tmp, "om", "inventory.json"), encoding="utf-8"))
        check("exclusion: blob.bin NOT in inventory",
              not any(f["path"].endswith("blob.bin") for f in inv["files"]))
        check("parse-failure: validation still ok (good files still emitted)", pm["validation"]["ok"])

        # ---- 9) tamper detection ----
        recs[0]["content_hash"] = "deadbeef"
        vt = ri.validate_records(recs)
        check("tamper: corrupted content_hash detected (ok=false)", not vt["ok"])

        # ---- 10) validate op via the worker subprocess (args-file interface) ----
        args_path = os.path.join(tmp, "vargs.json")
        meta_path = os.path.join(tmp, "vmeta.json")
        json.dump({"op": "validate", "records_path": os.path.join(o1, "records.jsonl"), "meta_path": meta_path},
                  open(args_path, "w"))
        rc = subprocess.call([sys.executable, os.path.join(SKILL, "repo_intel.py"), args_path])
        vm = json.load(open(meta_path))
        check("validate op: exit 0 + ok", rc == 0 and vm["validation"]["ok"])

        # ---- 11) bounded real slice (../../modules [+ ../../core-docs]) ----
        def _has_files(d):
            return os.path.isdir(d) and any(fn for _dp, _dn, fns in os.walk(d) for fn in fns)
        real = [os.path.abspath(d)
                for d in (os.path.join(SKILL, "..", "..", "modules"), os.path.join(SKILL, "..", "..", "core-docs"))
                if _has_files(d)]
        if real:
            os.makedirs(os.path.join(tmp, "or1"), exist_ok=True)
            a = {"op": "index", "roots": [os.path.abspath(d) for d in real], "namespace": "life-orchestrator",
                 "file_budget": 30, "output_dir": os.path.join(tmp, "or1")}
            pr = ri.do_index(a)
            check("real-slice: validation ok + records>0 + >=3 kinds",
                  pr["validation"]["ok"] and pr["total_records"] > 0 and len(pr["record_kinds"]) >= 3,
                  "records=%d kinds=%s" % (pr["total_records"], pr["record_kinds"]))
            a2 = dict(a); a2["output_dir"] = os.path.join(tmp, "or2"); os.makedirs(a2["output_dir"], exist_ok=True)
            pr2 = ri.do_index(a2)
            check("real-slice: deterministic re-index (digest identical)",
                  pr2["records_digest"] == pr["records_digest"])
        else:
            check("real-slice: [skipped: no ../modules or ../core-docs]", True)

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # i63 (D-0162): the declarative roots manifest makes ops/close-txn/spec (close-txn COLD BACKING)
    # discoverable through the ordinary indexing machinery -- a NARROW explicit root, not an ops/ sweep.
    repo_root = os.path.dirname(os.path.dirname(SKILL))
    rman = os.path.join(repo_root, "ops", "repo-intel-roots.json")
    if os.path.isfile(rman):
        rr = ri._load_roots_manifest(rman)
        spec_root = os.path.join(repo_root, "ops", "close-txn", "spec")
        check("roots-manifest: ops/close-txn/spec is an explicit indexed root",
              any(os.path.abspath(r) == os.path.abspath(spec_root) for r in rr))
        if os.path.isdir(spec_root):
            tmp2 = tempfile.mkdtemp(prefix="m38-roots-")
            try:
                pr = index(spec_root, "life-orchestrator", tmp2)
                recs = open(os.path.join(tmp2, "records.jsonl"), "r", encoding="utf-8").read()
                check("roots-manifest: indexing the backing root surfaces the hardened spec",
                      "close-transaction-hardened.md" in recs and pr["total_records"] > 0)
            finally:
                shutil.rmtree(tmp2, ignore_errors=True)
    else:
        check("roots-manifest: [skipped: no ops/repo-intel-roots.json]", True)

    print("")
    print("RESULT: %d/%d passed  (fail=%d)" % (PASS, PASS + FAIL, FAIL))
    print("ALLPASS=%s" % ("true" if FAIL == 0 else "false"))
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
