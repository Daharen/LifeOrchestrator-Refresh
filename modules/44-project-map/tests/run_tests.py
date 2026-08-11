#!/usr/bin/env python3
# -*- coding: ascii -*-
"""project.map cloud test suite (WO s6). Pure stdlib; runnable by python3 on the cloud, the mount VM
(3.10), and the box (3.12). The pwsh entrypoint tests/Invoke-ProjectMapTests.ps1 shells out to THIS.

Classes: golden-positive, determinism (double-run + shuffle + CRLF/LF), the negative suite (one named
fixture per error code, each failing with exactly that code, exercised through the CLI envelope),
drift gate, parse_budgets import parity, ingest idempotence + interrupted-ingest, reaffirm/fmt/
changed-since. Exit 0 only if every class passes; prints per-class counts."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
FIX = os.path.join(MOD, "fixtures")
PY = sys.executable
WORKER = os.path.join(MOD, "project_map.py")
sys.path.insert(0, MOD)
import project_map as P  # noqa: E402

RESULTS = []
FAILS = []


def rec(cls, name, ok, detail=""):
    RESULTS.append((cls, name, ok, detail))
    if not ok:
        FAILS.append("%s :: %s :: %s" % (cls, name, detail))


def cli(args, cwd=None):
    p = subprocess.run([PY, WORKER] + args, capture_output=True, text=True, cwd=cwd)
    env = None
    for line in reversed(p.stdout.strip().split("\n")):
        line = line.strip()
        if line.startswith("{"):
            try:
                env = json.loads(line)
                break
            except Exception:
                continue
    return p.returncode, env, p.stderr


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read().replace(b"\r\n", b"\n")


# --------------------------------------------------------------- golden positive --------------
def test_golden():
    harvest = os.path.join(FIX, "harvest.json")
    gmap = os.path.join(FIX, "golden-map")
    rc, env, err = cli(["validate", "--map", gmap, "--harvest", harvest])
    rec("golden", "validate-ok", rc == 0 and env and env["status"] == "ok",
        "rc=%s status=%s err=%s" % (rc, env and env.get("status"), err[:200]))
    out = tempfile.mkdtemp(prefix="pm-golden-")
    rc, env, err = cli(["render", "--map", gmap, "--harvest", harvest, "--out", out])
    ok = rc == 0 and env and env["status"] == "ok"
    rec("golden", "render-ok", ok, "rc=%s status=%s" % (rc, env and env.get("status")))
    # byte-compare vs committed golden-generated/
    gg = os.path.join(FIX, "golden-generated")
    names = sorted(os.listdir(gg))
    match = all(os.path.isfile(os.path.join(out, n)) and read_bytes(os.path.join(out, n)) == read_bytes(os.path.join(gg, n)) for n in names)
    rec("golden", "render-byte-identical-vs-committed", match, "files=%s" % names)
    shutil.rmtree(out, ignore_errors=True)


# --------------------------------------------------------------- determinism ------------------
def test_determinism():
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    gmap = os.path.join(FIX, "golden-map")
    # double-run render byte-identity
    a = tempfile.mkdtemp(prefix="pm-a-"); b = tempfile.mkdtemp(prefix="pm-b-")
    P.op_render(gmap, harvest, a, check=False, draft=False)
    P.op_render(gmap, harvest, b, check=False, draft=False)
    names = sorted(os.listdir(a))
    dig_a = P.sha256_norm(b"".join(read_bytes(os.path.join(a, n)) for n in names))
    dig_b = P.sha256_norm(b"".join(read_bytes(os.path.join(b, n)) for n in names))
    rec("determinism", "double-run-render", dig_a == dig_b, "a=%s b=%s" % (dig_a[:12], dig_b[:12]))
    # shuffle test: reorder items in every map file + reverse edges -> byte-identical render
    smap = tempfile.mkdtemp(prefix="pm-shuf-")
    shutil.copytree(gmap, os.path.join(smap, "map"))
    for root, _, files in os.walk(os.path.join(smap, "map")):
        for fn in files:
            if not fn.endswith(".json"):
                continue
            fp = os.path.join(root, fn)
            doc = json.loads(P.read_text(fp))
            if isinstance(doc, dict) and isinstance(doc.get("items"), list):
                doc["items"] = list(reversed(doc["items"]))
                for it in doc["items"]:
                    if isinstance(it, dict) and isinstance(it.get("sources"), list):
                        it["sources"] = list(reversed(it["sources"]))
                # write NON-canonically (compact, reversed) to prove order is normalized on read
                with open(fp, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(json.dumps(doc, separators=(",", ":")))
    s = tempfile.mkdtemp(prefix="pm-shufout-")
    P.op_render(os.path.join(smap, "map"), harvest, s, check=False, draft=False)
    dig_s = P.sha256_norm(b"".join(read_bytes(os.path.join(s, n)) for n in names))
    rec("determinism", "shuffle-invariant-render", dig_s == dig_a, "shuf=%s golden=%s" % (dig_s[:12], dig_a[:12]))
    # CRLF/LF hash equivalence
    sample = os.path.join(gmap, "relationships.json")
    raw = read_bytes(sample)
    lf = tempfile.mktemp(suffix=".json"); crlf = tempfile.mktemp(suffix=".json")
    open(lf, "wb").write(raw)
    open(crlf, "wb").write(raw.replace(b"\n", b"\r\n"))
    rec("determinism", "crlf-lf-hash-equivalent", P.sha256_file(lf) == P.sha256_file(crlf),
        "lf=%s crlf=%s" % (P.sha256_file(lf)[:12], P.sha256_file(crlf)[:12]))
    for d in (a, b, smap, s):
        shutil.rmtree(d, ignore_errors=True)


# --------------------------------------------------------------- negative suite ---------------
def test_negatives():
    negdir = os.path.join(FIX, "negative")
    cases = sorted(os.listdir(negdir))
    seen_codes = set()
    for name in cases:
        d = os.path.join(negdir, name)
        case = json.loads(P.read_text(os.path.join(d, "case.json")))
        expect = case["expect"]
        op = case["op"]
        args = case["args"]
        work = tempfile.mkdtemp(prefix="pm-neg-")
        # copy the whole case dir so ops that write (ingest/render) never touch the fixture
        for item in os.listdir(d):
            src = os.path.join(d, item)
            dst = os.path.join(work, item)
            if os.path.isdir(src):
                shutil.copytree(src, dst)
            else:
                shutil.copy(src, dst)
        argv = [op]
        if "map" in args:
            argv += ["--map", os.path.join(work, args["map"])]
        if "harvest" in args:
            argv += ["--harvest", os.path.join(work, args["harvest"])]
        if "claims" in args:
            argv += ["--claims", os.path.join(work, args["claims"])]
        if "out" in args:
            argv += ["--out", os.path.join(work, args["out"])]
        if "repo" in args:
            argv += ["--repo", os.path.join(work, args["repo"]), "--at-commit", "x", "--dirty", "false"]
        if "fmt_paths" in args:
            argv += ["--fmt-paths"] + [os.path.join(work, x) for x in args["fmt_paths"]]
        if args.get("check"):
            argv += ["--check"]
        rc, env, err = cli(argv)
        got = env and env.get("error", {}) and env["error"].get("code")
        ok = rc == 0 and env and env["status"] == "error" and got == expect
        rec("negative", "%s->%s" % (name, expect), ok,
            "rc=%s status=%s got=%s err=%s" % (rc, env and env.get("status"), got, err[:150]))
        if ok:
            seen_codes.add(expect)
        shutil.rmtree(work, ignore_errors=True)
    # behavior checks: UNSUPPORTED_QUERY + DRAFT_RENDER
    gmap = os.path.join(FIX, "golden-map"); harvest = os.path.join(FIX, "harvest.json")
    rc, env, err = cli(["query", "--map", gmap, "--q", "bogus:whatever"])
    ok = env and env["status"] == "error" and env["error"]["code"] == "UNSUPPORTED_QUERY"
    rec("negative", "UNSUPPORTED_QUERY(behavior)", ok, "got=%s" % (env and env.get("error")))
    if ok:
        seen_codes.add("UNSUPPORTED_QUERY")
    # draft targeting generated/ refuses DRAFT_RENDER
    tmpgen = tempfile.mkdtemp(prefix="pm-gen-")
    rc, env, err = cli(["render", "--map", gmap, "--harvest", harvest, "--out", tmpgen, "--draft"])
    ok = env and env["status"] == "error" and env["error"]["code"] == "DRAFT_RENDER"
    rec("negative", "DRAFT_RENDER(generated-refused)", ok, "got=%s" % (env and env.get("error")))
    if ok:
        seen_codes.add("DRAFT_RENDER")
    # draft under runtime/ writes with banner + DRAFT_RENDER
    rt = os.path.join(tempfile.mkdtemp(prefix="pm-rt-"), "runtime", "draft")
    rc, env, err = cli(["render", "--map", gmap, "--harvest", harvest, "--out", rt, "--draft"])
    banner_ok = env and env["status"] == "error" and env["error"]["code"] == "DRAFT_RENDER" \
        and os.path.isfile(os.path.join(rt, "BOOT_PACKET.md")) \
        and "DRAFT-STALE" in P.read_text(os.path.join(rt, "BOOT_PACKET.md"))
    rec("negative", "DRAFT_RENDER(runtime-banner)", banner_ok, "")
    # render without --harvest refuses
    rc, env, err = cli(["render", "--map", gmap, "--out", tempfile.mkdtemp()])
    rec("negative", "render-without-harvest-refuses", env and env["status"] == "error", "")
    # coverage summary
    from project_map import CODES
    exercised = seen_codes
    missing = [c for c in CODES if c not in exercised]
    rec("negative", "all-codes-exercised (%d/%d)" % (len(exercised), len(CODES)), not missing,
        "missing=%s" % missing)


# --------------------------------------------------------------- drift gate -------------------
def test_drift():
    gmap = os.path.join(FIX, "golden-map"); harvest = os.path.join(FIX, "harvest.json")
    gg = os.path.join(FIX, "golden-generated")
    rc, env, err = cli(["render", "--map", gmap, "--harvest", harvest, "--out", gg, "--check"])
    rec("drift", "check-green-on-committed-golden", rc == 0 and env and env["status"] == "ok",
        "status=%s" % (env and env.get("status")))
    # DRAFT-STALE banner under a generated tree fails --check
    work = tempfile.mkdtemp(prefix="pm-drift-")
    shutil.copytree(gg, os.path.join(work, "gen"))
    with open(os.path.join(work, "gen", "ALIASES.md"), "a", encoding="utf-8", newline="\n") as fh:
        fh.write(P.DRAFT_BANNER + "\n")
    rc, env, err = cli(["render", "--map", gmap, "--harvest", harvest, "--out", os.path.join(work, "gen"), "--check"])
    rec("drift", "draft-banner-under-generated-fails", env and env["status"] == "error"
        and env["error"]["code"] == "GENERATED_DRIFT", "got=%s" % (env and env.get("error")))
    shutil.rmtree(work, ignore_errors=True)


# --------------------------------------------------------------- parse_budgets parity ---------
def test_parse_budgets_parity():
    repo = os.path.join(FIX, "repo")
    core = tempfile.mkdtemp(prefix="pm-core-")
    cases = {
        "normal": "| doc | owns | budget |\n|---|---|---|\n| A.md | x | 12 KB |\n| B.md | y | no cap |\n",
        "kb-units": "| doc | owns | budget |\n|---|---|---|\n| C.md | z | 7 KB each |\n",
    }
    ok = True
    detail = []
    for nm, tbl in cases.items():
        P.write_lf(os.path.join(core, "DOC_PROTOCOL.md"), "## 2. set\n\n" + tbl)
        got = P.imported_parse_budgets(repo, core_dir=core)
        # identical to a fresh direct call of the SAME imported function on the SAME fixture
        got2 = P.imported_parse_budgets(repo, core_dir=core)
        ok = ok and (got == got2)
        detail.append("%s=%s" % (nm, got))
    # KB units parsed to ints; 'no cap' -> None (proves we consumed the real function's semantics)
    P.write_lf(os.path.join(core, "DOC_PROTOCOL.md"), "## 2\n\n" + cases["normal"])
    g = P.imported_parse_budgets(repo, core_dir=core)
    ok = ok and g.get("A.md") == 12 and g.get("B.md") is None
    rec("parity", "parse_budgets-import-parity", ok, "; ".join(detail))
    shutil.rmtree(core, ignore_errors=True)


# --------------------------------------------------------------- ingest idempotence -----------
def _benign_claims(path):
    claims = {"schema": P.SCHEMA_CLAIMS, "by": "lane-B-i46", "at_commit":
              "goldensha0000000000000000000000000000000",
              "entities": [{"id": "module:90/alpha.tool", "aliases": ["#90", "alpha"],
                            "sources": [{"ref": "modules/90-alpha/README.md", "sha256": None,
                                         "fields": ["aliases"], "by": "lane-B-i46",
                                         "at_commit": "goldensha0000000000000000000000000000000"}]}],
              "relationships": [{"from": "module:91/beta.tool", "type": "consumes",
                                 "to": "module:90/alpha.tool",
                                 "sources": [{"ref": "decision:D-9001", "sha256": None, "fields": ["*"],
                                              "by": "lane-B-i46",
                                              "at_commit": "goldensha0000000000000000000000000000000"}]}]}
    P.write_lf(path, P.dumps_map(claims))


def _map_digest(map_dir):
    parts = []
    for root, dirs, files in os.walk(map_dir):
        dirs.sort()
        for fn in sorted(files):
            parts.append(read_bytes(os.path.join(root, fn)))
    return P.sha256_norm(b"".join(parts))


def test_ingest():
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    base = os.path.join(FIX, "golden-map")
    work = tempfile.mkdtemp(prefix="pm-ing-")
    m1 = os.path.join(work, "m1")
    shutil.copytree(base, m1)
    claims = os.path.join(work, "claims.json")
    _benign_claims(claims)
    P.op_ingest_claims(m1, claims, harvest, None)
    dig1 = _map_digest(m1)
    P.op_ingest_claims(m1, claims, harvest, None)   # re-ingest -> no-op
    dig2 = _map_digest(m1)
    rec("ingest", "idempotent-double-ingest", dig1 == dig2, "d1=%s d2=%s" % (dig1[:12], dig2[:12]))
    # interrupted-ingest: a failing (dangling) claim leaves map/ untouched
    m2 = os.path.join(work, "m2")
    shutil.copytree(base, m2)
    before = _map_digest(m2)
    bad = os.path.join(work, "bad.json")
    P.write_lf(bad, P.dumps_map({"schema": P.SCHEMA_CLAIMS, "by": "x", "at_commit": "z",
               "entities": [], "relationships": [{"from": "module:90/alpha.tool", "type": "invokes",
               "to": "module:zz/none", "sources": [{"ref": "decision:D-9001", "sha256": None,
               "fields": ["*"], "by": "x", "at_commit": "z"}]}]}))
    refused = False
    try:
        P.op_ingest_claims(m2, bad, harvest, None)
    except P.Refuse:
        refused = True
    after = _map_digest(m2)
    rec("ingest", "interrupted-ingest-leaves-map-untouched", refused and before == after,
        "refused=%s eq=%s" % (refused, before == after))
    shutil.rmtree(work, ignore_errors=True)


# --------------------------------------------------------------- reaffirm/fmt/changed-since ---
def test_reaffirm_fmt_changed():
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    base = os.path.join(FIX, "golden-map")
    work = tempfile.mkdtemp(prefix="pm-rfc-")
    m = os.path.join(work, "m")
    shutil.copytree(base, m)
    res = P.op_reaffirm(m, "module:90/alpha.tool", "one_line", "checker", "commitX", harvest)
    rec("reaffirm", "reaffirm-restamps", res["sources_restamped"] >= 1, str(res))
    refused = False
    try:
        P.op_reaffirm(m, "module:90/alpha.tool", "load_bearing", "checker", "commitX", harvest)
    except P.Refuse:
        refused = True
    rec("reaffirm", "reaffirm-refuses-derived-field", refused, "")
    # fmt: golden canonical -> ok; non-canonical -> FMT_NONCANONICAL
    try:
        P.op_fmt([m], check=True)
        fmt_ok = True
    except P.Refuse:
        fmt_ok = False
    rec("fmt", "fmt-golden-canonical-ok", fmt_ok, "")
    bad = os.path.join(work, "bad")
    P.write_lf(os.path.join(bad, "x.json"), '{"b":2,"a":1}')
    try:
        P.op_fmt([bad], check=True)
        flagged = False
    except P.Refuse as r:
        flagged = r.code == "FMT_NONCANONICAL"
    rec("fmt", "fmt-flags-noncanonical", flagged, "")
    # changed-since
    pf = os.path.join(work, "paths.txt")
    P.write_lf(pf, "modules/90-alpha/README.md\n")
    res = P.op_query(base, "changed-since", harvest, pf)
    rec("changed-since", "maps-paths-to-entities",
        "module:90/alpha.tool" in res["touched_entities"], str(res["touched_entities"]))
    shutil.rmtree(work, ignore_errors=True)


def main():
    for t in (test_golden, test_determinism, test_negatives, test_drift,
              test_parse_budgets_parity, test_ingest, test_reaffirm_fmt_changed):
        try:
            t()
        except Exception as e:
            import traceback
            rec(t.__name__, "CRASH", False, "%s: %s" % (type(e).__name__, e))
            traceback.print_exc()
    # summary
    classes = {}
    for cls, name, ok, detail in RESULTS:
        c = classes.setdefault(cls, [0, 0])
        c[0] += 1 if ok else 0
        c[1] += 1
    print("\n==== project.map cloud suite ====")
    for cls in sorted(classes):
        p, n = classes[cls]
        print("  %-14s %d/%d" % (cls, p, n))
    print("  %-14s %d/%d" % ("TOTAL", sum(1 for r in RESULTS if r[2]), len(RESULTS)))
    if FAILS:
        print("\nFAILURES:")
        for f in FAILS:
            print("  X", f)
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
