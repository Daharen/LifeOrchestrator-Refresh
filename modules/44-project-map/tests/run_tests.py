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
import re
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


# --------------------------------------------------------------- CD-3 short-form resolution ---
def _q(expr, mapdir, harvest=None):
    args = ["query", "--map", mapdir, "--q", expr]
    if harvest:
        args += ["--harvest", harvest]
    _, env, _ = cli(args)
    return env


def test_shortform():
    gmap = os.path.join(FIX, "golden-map")
    # short form resolves to canonical and yields the SAME payload as the full id (entity/edges/redges)
    pairs = [("entity", "module:90", "module:90/alpha.tool"),
             ("edges", "module:91", "module:91/beta.tool"),
             ("redges", "module:90", "module:90/alpha.tool"),
             ("entity", "widget:90", "widget:90/gamma")]
    for verb, short, full in pairs:
        es = _q("%s:%s" % (verb, short), gmap)["result"]
        ef = _q("%s:%s" % (verb, full), gmap)["result"]
        rec("shortform", "%s:%s==full-payload" % (verb, short), es.get(verb) == ef.get(verb),
            "short=%s full=%s" % (es.get(verb), ef.get(verb)))
        rec("shortform", "%s:%s surfaces resolved" % (verb, short), es.get("resolved") == full, str(es.get("resolved")))
        # full-id byte-identity vs 0.1.0: NO 'resolved' key, exactly {q, <verb>}
        rec("shortform", "%s full-id byte-identity(no-resolved)" % verb,
            "resolved" not in ef and set(ef.keys()) == {"q", verb}, "keys=%s" % sorted(ef.keys()))
    # #NN alias short form -> module
    e = _q("entity:#90", gmap)["result"]
    rec("shortform", "#90->module:90/alpha.tool", e.get("resolved") == "module:90/alpha.tool", str(e.get("resolved")))
    # negative short form -> DANGLING_REF (acceptance: module:99)
    for verb in ("entity", "edges", "redges", "evidence", "deeper"):
        env = _q("%s:module:99" % verb, gmap)
        code = env and env.get("error", {}) and env["error"].get("code")
        rec("shortform", "%s:module:99->DANGLING_REF" % verb, env["status"] == "error" and code == "DANGLING_REF", "got=%s" % code)
    # a full-id-SHAPE miss keeps the 0.1.0 empty-set behavior for edges/redges (NOT an error)
    env = _q("edges:module:99/ghost", gmap)
    rec("shortform", "edges:full-shape-miss->[] (0.1.0-identical)", env["status"] == "ok" and env["result"]["edges"] == [], str(env.get("error")))
    # deeper with :kind on a short form
    env = _q("deeper:module:90:readme", gmap)
    rec("shortform", "deeper:short:kind-resolves", env["status"] == "ok" and env["result"].get("resolved") == "module:90/alpha.tool", str(env.get("error")))


# --------------------------------------------------------------- CD-3 provenance marking ------
def test_evidence_provenance():
    gmap = os.path.join(FIX, "golden-map")
    harvest = os.path.join(FIX, "harvest.json")
    prov = os.path.join(FIX, "provenance", "map")
    # no --harvest: byte-identical to 0.1.0 (raw sources, no marking/currency)
    e0 = _q("evidence:module:90/alpha.tool", gmap)["result"]
    rec("provenance", "no-harvest-byte-identical", set(e0.keys()) == {"q", "evidence"}
        and all(set(s.keys()) <= {"ref", "sha256", "fields", "by", "at_commit", "reaffirmed"} for s in e0["evidence"]),
        "keys=%s" % sorted(e0.keys()))
    # with --harvest: marking + currency (both commits) + counts
    e1 = _q("evidence:module:90/alpha.tool", gmap, harvest)["result"]
    rec("provenance", "with-harvest-currency-both-commits",
        set(e1["currency"].keys()) == {"map_state_commit", "harvest_commit", "in_sync"}, str(e1["currency"]))
    # beyond-tree fixture: ghost research path + unknown decision marked beyond-tree; at_commit drift caught
    ep = _q("evidence:module:90/alpha.tool", prov, harvest)["result"]
    provs = {m["ref"]: m["_provenance"]["provenance"] for m in ep["evidence"]}
    rec("provenance", "beyond-tree-path-marked", provs.get("core-docs/research/2026-08-11-ghost.md") == "beyond-tree", str(provs))
    rec("provenance", "beyond-tree-decision-marked", provs.get("decision:D-0130") == "beyond-tree", str(provs))
    rec("provenance", "in-tree-path-marked", provs.get("modules/90-alpha/README.md") == "in-tree", str(provs))
    rec("provenance", "beyond_tree_count==2", ep["beyond_tree_count"] == 2, str(ep["beyond_tree_count"]))
    rec("provenance", "currency-map-vs-tree-split", ep["currency"]["in_sync"] is False, str(ep["currency"]))
    rec("provenance", "at_commit_drift-caught", ep["at_commit_drift_count"] >= 1, str(ep["at_commit_drift_count"]))


# --------------------------------------------------------------- CD-1 OPERATIONS section ------
def test_operations():
    gmap = os.path.join(FIX, "golden-map")
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    model = P.load_map(gmap)
    vr = P.validate(model, harvest, is_real=True)
    lb = vr["load_bearing"]
    stale = set(vr["stale_entities"])
    body, total, ladder, _, _, _ = P._build_boot_packet(model, harvest, stale, lb)
    ops_sec = ""
    if "## OPERATIONS" in body:
        ops_sec = body.split("## OPERATIONS", 1)[1].split("\n## ", 1)[0]
    # content assertions (rendered from ops: state; each token present)
    for tok in ["<=1 GPU", "MaxParallel 3", "docs:[]", "NATIVE git", "never git add -A",
                "gpu -> git -> doc", "0 UNMANAGED orphans"]:
        rec("operations", "token:%s" % tok, tok in ops_sec, "")
    bullets = [ln for ln in ops_sec.splitlines() if ln.startswith("- ")]
    rec("operations", "every-line-pointer-backed", len(bullets) >= 5 and all("[" in b and "]" in b for b in bullets),
        "bullets=%d" % len(bullets))
    rec("operations", "packet-under-hard-20000", total <= P.BOOT_PACKET_HARD, "total=%d" % total)
    # min-floor: level 2 is a single line that never vanishes and keeps a pointer
    mn, n = P._build_operations_section(model.entities, 2)
    rec("operations", "minfloor-nonempty-with-pointer", n > 0 and bool(mn.strip()) and "descend:" in mn, "")
    # degrade-LAST: under a forced tiny HARD, section3 degrades in the ladder BEFORE OPERATIONS, and
    # OPERATIONS still survives (never removed).
    save = P.BOOT_PACKET_HARD
    try:
        P.BOOT_PACKET_HARD = 1
        b2, t2, l2, _, _, _ = P._build_boot_packet(model, harvest, stale, lb)
        idx3 = next((i for i, s in enumerate(l2) if "section3" in s), 999)
        idxop = next((i for i, s in enumerate(l2) if "OPERATIONS -> level" in s), 1000)
        rec("operations", "degrade-LAST(section3-before-OPERATIONS)", idx3 < idxop, "ladder=%s" % l2)
        rec("operations", "OPERATIONS-survives-max-degrade", "## OPERATIONS" in b2, "")
    finally:
        P.BOOT_PACKET_HARD = save


# --------------------------------------------------------------- CD-1 ops claims roundtrip -----
def test_ops_roundtrip():
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    base = os.path.join(FIX, "golden-map")
    work = tempfile.mkdtemp(prefix="pm-ops-")
    m = os.path.join(work, "m")
    shutil.copytree(base, m)
    # strip the pre-seeded boot-ops so we PROVE they arrive via ingest of the claims file
    P.write_lf(os.path.join(m, "entities", "ops.json"),
               P.dumps_map({"schema": P.SCHEMA_ENTITIES, "kind": "entities", "items": []}))
    fc = os.path.join(FIX, "i48-ops-canon-claims.fixture.json")
    res = P.op_ingest_claims(m, fc, harvest, None)
    rec("ops-roundtrip", "ingest-upserts-boot-ops", res["entities_upserted"] >= 2, str(res))
    model = P.load_map(m)
    ids = [i for i in model.entities if i.startswith("ops:boot-")]
    rec("ops-roundtrip", "boot-ops-in-map", len(ids) >= 2, str(ids))
    out = tempfile.mkdtemp(prefix="pm-opsr-")
    P.op_render(m, harvest, out, check=False, draft=False)
    bp = P.read_text(os.path.join(out, "BOOT_PACKET.md"))
    rec("ops-roundtrip", "OPERATIONS-rendered-from-ingested", "## OPERATIONS" in bp and "MaxParallel 3" in bp, "")
    d1 = _map_digest(m)
    P.op_ingest_claims(m, fc, harvest, None)
    d2 = _map_digest(m)
    rec("ops-roundtrip", "ingest-idempotent", d1 == d2, "d1=%s d2=%s" % (d1[:10], d2[:10]))
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(out, ignore_errors=True)


# --------------------------------------------------------------- mandate absence (i48 fix) ----
def test_mandate_absent():
    import copy
    # 1) _parse_mandate_header: an ABSENT doc -> {} (no crash) -- the post-i47-sunset tree state.
    with tempfile.TemporaryDirectory() as td:
        rec("mandate-absent", "absent-doc->empty-header", P._parse_mandate_header(td) == {}, "")
        cd = os.path.join(td, "core-docs")
        os.makedirs(cd)
        with open(os.path.join(cd, "PROCESS_MANDATE.md"), "wb") as fh:
            fh.write(b"# PM\n- `mandate_id: 02`\n- `state: ACTIVE`\n")
        hdr = P._parse_mandate_header(td)
        rec("mandate-absent", "present-doc-parses(regression)",
            hdr.get("mandate_id") == "02" and hdr.get("state") == "ACTIVE", str(hdr))
    # 2) fail-closed: overlay CLAIMS a mandate while the tree header is EMPTY -> OVERLAY_MANDATE_DRIFT
    gmap = os.path.join(FIX, "golden-map")
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    h2 = copy.deepcopy(harvest)
    h2["mandate"] = {}
    model = P.load_map(gmap)
    vr = P.validate(model, h2, is_real=True)
    codes = [f["code"] for f in vr["findings"]]
    rec("mandate-absent", "overlay-claims-vs-absent->DRIFT",
        any(f["code"] == "OVERLAY_MANDATE_DRIFT" and "no PROCESS_MANDATE header" in f["message"]
            for f in vr["findings"]), str(codes))
    # 3) overlay WITHOUT a mandate + empty header -> NO mandate drift (the post-sunset overlay shape)
    model2 = P.load_map(gmap)
    model2.overlay = copy.deepcopy(model2.overlay)
    model2.overlay.pop("mandate", None)
    vr2 = P.validate(model2, h2, is_real=True)
    rec("mandate-absent", "no-overlay-mandate+absent->no-drift",
        not any(f["code"] == "OVERLAY_MANDATE_DRIFT" for f in vr2["findings"]),
        str([f["code"] for f in vr2["findings"]]))
    # 4) both present (golden baseline) -> still no drift (regression; invariants match)
    vr3 = P.validate(P.load_map(gmap), harvest, is_real=True)
    rec("mandate-absent", "both-present->no-drift(regression)",
        not any(f["code"] == "OVERLAY_MANDATE_DRIFT" for f in vr3["findings"]),
        str([f["code"] for f in vr3["findings"]]))



# --------------------------------------------------------------- i49 N1/N2/N3 acceptance -------
def _cli_raw(args, cwd=None):
    """Run the worker; return the raw last JSON envelope LINE (str) for exact byte measurement."""
    p = subprocess.run([PY, WORKER] + args, capture_output=True, text=True, cwd=cwd)
    for line in reversed(p.stdout.strip().split("\n")):
        line = line.strip()
        if line.startswith("{"):
            return line
    return ""


def test_n1_purpose():
    gmap = os.path.join(FIX, "golden-map")
    harvest = os.path.join(FIX, "harvest.json")
    # N1(1): short form + --fields purpose + --harvest -> served FROM HARVEST, provenance-stamped
    rc, env, err = cli(["query", "--map", gmap, "--q", "entity:module:90", "--fields", "purpose", "--harvest", harvest])
    r = (env or {}).get("result", {})
    ok = (env and env["status"] == "ok" and r.get("resolved") == "module:90/alpha.tool"
          and r["fields"]["purpose"].startswith("Alpha does the first thing")
          and r["field_provenance"]["served_from"] == "harvest"
          and r["field_provenance"]["harvest_commit"] == "goldensha0000000000000000000000000000000"
          and r["field_provenance"]["ref"] == "modules/90-alpha/skill.json"
          and bool(r["field_provenance"]["sha256"]))
    rec("n1-purpose", "serves-purpose-from-harvest-provenance-stamped", ok, str(r)[:180])
    # bounded: a huge purpose -> truncated + WHOLE query envelope <= 6000 B (acceptance a: vs 478,784 B grep)
    big = json.loads(P.read_text(harvest))
    for m in big["modules"]:
        if m["num"] == "90":
            m["purpose"] = "X" * 40000
    bp = tempfile.mktemp(suffix=".json"); P.write_lf(bp, json.dumps(big))
    raw = _cli_raw(["query", "--map", gmap, "--q", "entity:module:90", "--fields", "purpose", "--harvest", bp])
    env2 = json.loads(raw); r2 = env2["result"]; envbytes = len(raw.encode("utf-8"))
    rec("n1-purpose", "bounded-envelope<=6000B(acceptance-a)", envbytes <= 6000, "bytes=%d" % envbytes)
    rec("n1-purpose", "truncation-flagged+full_bytes",
        r2.get("truncated", {}).get("purpose") is True and r2.get("full_bytes", {}).get("purpose") == 40000, str(r2.get("full_bytes")))
    rec("n1-purpose", "served-len==FIELD_SERVE_MAX",
        len(r2["fields"]["purpose"].encode("utf-8")) == P.FIELD_SERVE_MAX, str(len(r2["fields"]["purpose"])))
    # negatives
    rc, env, _ = cli(["query", "--map", gmap, "--q", "entity:module:99", "--fields", "purpose", "--harvest", harvest])
    rec("n1-purpose", "unknown-module->DANGLING_REF", env["status"] == "error" and env["error"]["code"] == "DANGLING_REF", str(env.get("error")))
    rc, env, _ = cli(["query", "--map", gmap, "--q", "entity:module:90", "--fields", "purpose"])
    rec("n1-purpose", "fields-without-harvest->UNSUPPORTED_QUERY", env["status"] == "error" and env["error"]["code"] == "UNSUPPORTED_QUERY", str(env.get("error")))
    rc, env, _ = cli(["query", "--map", gmap, "--q", "entity:module:90", "--fields", "load_bearing", "--harvest", harvest])
    rec("n1-purpose", "non-harvest-field->UNSUPPORTED_QUERY", env["status"] == "error" and env["error"]["code"] == "UNSUPPORTED_QUERY", str(env.get("error")))
    # regression (acceptance d): entity WITHOUT --fields is 0.2.0-identical; --harvest alone does not change it
    rc, ef, _ = cli(["query", "--map", gmap, "--q", "entity:module:90/alpha.tool"])
    rc, eh, _ = cli(["query", "--map", gmap, "--q", "entity:module:90/alpha.tool", "--harvest", harvest])
    rec("n1-purpose", "entity-no-fields-0.2.0-identical",
        set(ef["result"].keys()) == {"q", "entity"} and ef["result"] == eh["result"], str(sorted(ef["result"].keys())))


def _mk_section_repo():
    repo = tempfile.mkdtemp(prefix="secrepo-")
    d = os.path.join(repo, "modules", "90-alpha"); os.makedirs(d)
    SN = ("# alpha SCHEMA_NOTES\n\n## 3. ranking\n\nprose.\n\n"
          "## 15. the FAST-BEAM residual lever (RANKING ONLY)\n\n"
          "the beam slices the shortlist; the residual lever is #40-owned BEAM WIDTH, a #40 follow-on.\n\n"
          "### 15.1 nested\n\nstays inside 15.\n\n## 16. after\n\nnot 15.\n")
    P.write_lf(os.path.join(d, "SCHEMA_NOTES.md"), SN)
    h = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    for m in h["modules"]:
        if m["num"] == "90":
            m["has_schema_notes"] = True
    hp = os.path.join(repo, "h.json"); P.write_lf(hp, json.dumps(h))
    return repo, hp


def test_n1_section():
    gmap = os.path.join(FIX, "golden-map")
    repo, hp = _mk_section_repo()
    head = "15. the FAST-BEAM residual lever (RANKING ONLY)"
    raw = _cli_raw(["query", "--map", gmap, "--q", "section:module:90#" + head, "--repo", repo, "--harvest", hp])
    env = json.loads(raw); s = env["result"]["section"]; envbytes = len(raw.encode("utf-8"))
    rec("n1-section", "fetch-ok+beam+#40(acceptance-b)",
        env["status"] == "ok" and "beam" in s["text"].lower() and "#40" in s["text"], "")
    rec("n1-section", "envelope<=8000B", envbytes <= 8000, "bytes=%d" % envbytes)
    rec("n1-section", "spans-nested-excludes-next", "15.1 nested" in s["text"] and "16. after" not in s["text"], "")
    rec("n1-section", "sha-stamped+path+level",
        bool(s["sha256"]) and s["path"].endswith("SCHEMA_NOTES.md") and s["level"] == 2, str(s.get("level")))
    raw2 = _cli_raw(["query", "--map", gmap, "--q", "section:module:90#  15.   the FAST-BEAM residual lever (RANKING ONLY) ", "--repo", repo, "--harvest", hp])
    rec("n1-section", "selector-whitespace-normalized", json.loads(raw2)["status"] == "ok", "")
    for q, exp, nm in [("section:module:90#NoHeading", "DANGLING_REF", "unknown-heading"),
                       ("section:module:91#x", "DANGLING_REF", "module-without-schema-notes"),
                       ("section:module:99#x", "DANGLING_REF", "unresolved-module")]:
        e = json.loads(_cli_raw(["query", "--map", gmap, "--q", q, "--repo", repo, "--harvest", hp]))
        rec("n1-section", "%s->%s" % (nm, exp), e["status"] == "error" and e["error"]["code"] == exp, str(e.get("error")))
    e = json.loads(_cli_raw(["query", "--map", gmap, "--q", "section:module:90#" + head, "--harvest", hp]))
    rec("n1-section", "no-repo->UNSUPPORTED_QUERY", e["status"] == "error" and e["error"]["code"] == "UNSUPPORTED_QUERY", "")
    e = json.loads(_cli_raw(["query", "--map", gmap, "--q", "section:module:90#" + head, "--repo", repo]))
    rec("n1-section", "no-harvest->UNSUPPORTED_QUERY", e["status"] == "error" and e["error"]["code"] == "UNSUPPORTED_QUERY", "")
    # N1(3): a deeper[schema-notes] PATH pointer is preferred over the derived path
    m = P.load_map(gmap)
    m.entities["module:90/alpha.tool"] = dict(m.entities["module:90/alpha.tool"])
    m.entities["module:90/alpha.tool"]["deeper"] = [{"kind": "schema-notes", "ref": "modules/90-alpha/SCHEMA_NOTES.md#anchor"}]
    rel = P._schema_notes_rel_for("module:90/alpha.tool", json.loads(P.read_text(hp)), m)
    rec("n1-section", "deeper-schema-notes-pointer-preferred", rel == "modules/90-alpha/SCHEMA_NOTES.md", str(rel))
    # a LARGE section clips head+tail, keeps the tail sentinel, and the whole envelope stays <= 8000 B
    repo2 = tempfile.mkdtemp(prefix="bigsec-")
    d2 = os.path.join(repo2, "modules", "90-alpha"); os.makedirs(d2)
    body = "## 9. big\n\nBEAMHEAD start.\n" + ("filler beam line %d\n" % 0) + "\n".join("mid line %d" % i for i in range(1200)) + "\nTAILSENTINEL #40 ownership at the very end.\n"
    P.write_lf(os.path.join(d2, "SCHEMA_NOTES.md"), "# x\n\n" + body)
    h2 = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    for mm in h2["modules"]:
        if mm["num"] == "90": mm["has_schema_notes"] = True
    hp2 = os.path.join(repo2, "h.json"); P.write_lf(hp2, json.dumps(h2))
    raw = _cli_raw(["query", "--map", gmap, "--q", "section:module:90#9. big", "--repo", repo2, "--harvest", hp2])
    e = json.loads(raw); s = e["result"]["section"]; envb = len(raw.encode("utf-8"))
    rec("n1-section", "large-section-clipped-envelope<=8000", e["status"] == "ok" and s["truncated"] is True and envb <= 8000, "env=%d body=%d" % (envb, s["bytes"]))
    rec("n1-section", "clip-keeps-head-and-tail-sentinel", "BEAMHEAD" in s["text"] and "TAILSENTINEL #40" in s["text"] and "clipped" in s["text"], "")


def test_n2_frontier():
    import copy
    gmap = os.path.join(FIX, "golden-map")
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    model = P.load_map(gmap)
    sec_empty, nr = P._build_overlay_section(model, 0)
    rec("n2-frontier", "empty-candidates-no-frontier-block(0.2.0-identical)",
        nr == 0 and "FRONTIER CANDIDATES" not in sec_empty, "")
    model.overlay = copy.deepcopy(model.overlay)
    model.overlay["frontier"]["candidates"] = [
        {"item": "#40 beam-width", "gate": "deferred D-0134", "pointer": "MODULE_ROADMAP.md#40"},
        {"item": "AUDIT_PIPELINE next_increment", "gate": "review_due i49", "pointer": "core-docs/AUDIT_PIPELINE.md"},
        {"item": "bar re-freeze (N4)", "gate": "requires Nicholas ratification", "pointer": "decision:D-0137"}]
    vr = P.validate(model, harvest, is_real=True)
    body, total, ladder = P._build_boot_packet(model, harvest, set(vr["stale_entities"]), vr["load_bearing"])[:3]
    block = body.split("FRONTIER CANDIDATES", 1)[1].split("PROHIBITIONS", 1)[0]
    cand = [ln for ln in block.splitlines() if ln.startswith("- [")]
    gated = [ln for ln in cand if re.match(r"^- \[[^\]]+\] ", ln)]
    rec("n2-frontier", ">=3-candidates-each-gated(acceptance-c)", len(cand) >= 3 and len(gated) == len(cand), "n=%d gated=%d" % (len(cand), len(gated)))
    rec("n2-frontier", "carries-item-gate-pointer", all("->" in ln for ln in cand), str(cand)[:160])
    rec("n2-frontier", "packet<=20000", total <= P.BOOT_PACKET_HARD, "total=%d" % total)
    save = P.BOOT_PACKET_HARD
    try:
        P.BOOT_PACKET_HARD = 1
        b2, t2, l2 = P._build_boot_packet(model, harvest, set(vr["stale_entities"]), vr["load_bearing"])[:3]
        idx3 = next((i for i, s in enumerate(l2) if "total-guard: section3" in s), 999)
        idxov = next((i for i, s in enumerate(l2) if "total-guard: OVERLAY frontier" in s), 1000)
        idxop = next((i for i, s in enumerate(l2) if "total-guard: OPERATIONS" in s), 2000)
        rec("n2-frontier", "ladder section3<frontier<OPERATIONS(OPERATIONS-last)", idx3 < idxov < idxop, "ladder=%s" % l2)
        rec("n2-frontier", "frontier-min-floor-collapses-with-gates", "frontier candidates:" in b2 and "gates:" in b2, "")
        rec("n2-frontier", "OPERATIONS-survives-max-degrade", "## OPERATIONS" in b2, "")
    finally:
        P.BOOT_PACKET_HARD = save


def _is_unknown_verb(env):
    return (env.get("status") == "error" and env.get("error", {}).get("code") == "UNSUPPORTED_QUERY"
            and "not in the closed set" in (env["error"].get("message") or ""))


def test_n3_verbtable():
    gmap = os.path.join(FIX, "golden-map")
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    model = P.load_map(gmap)
    vr = P.validate(model, harvest, is_real=True)
    body = P._build_boot_packet(model, harvest, set(vr["stale_entities"]), vr["load_bearing"])[0]
    proto = body.split("## RETRIEVAL PROTOCOL", 1)[1]
    forms = re.findall(r"^\| `([^`]+)` \|", proto, re.M)
    tokens = sorted({f.split(":")[0].split(" ")[0] for f in forms})
    rec("n3-verbtable", "table==QUERY_VERB_TOKENS(test-asserted-equal)", tokens == sorted(P.QUERY_VERB_TOKENS), "table=%s" % tokens)
    # the dispatcher recognizes EXACTLY the declared verbs (a declared verb never reads as 'unknown verb')
    probe = {"entity": "entity:module:90", "edges": "edges:module:90", "redges": "redges:module:90",
             "evidence": "evidence:module:90", "deeper": "deeper:module:90", "alias": "alias:#90",
             "section": "section:module:90#x", "card": "card:module:90",
             "stale": "stale", "changed-since": "changed-since"}
    accepted = []
    for v in P.QUERY_VERB_TOKENS:
        rc, env, _ = cli(["query", "--map", gmap, "--q", probe[v]])
        if not _is_unknown_verb(env or {}):
            accepted.append(v)
    rec("n3-verbtable", "every-declared-verb-dispatch-accepted", sorted(accepted) == sorted(P.QUERY_VERB_TOKENS), "accepted=%s" % sorted(accepted))
    rc, env, _ = cli(["query", "--map", gmap, "--q", "bogus:x"])
    rec("n3-verbtable", "undeclared-verb->UNSUPPORTED_QUERY(not-in-closed-set)", _is_unknown_verb(env or {}), str(env.get("error")))
    rec("n3-verbtable", "table-lists-modifiers(--harvest/--fields/--repo)+section",
        "--harvest" in proto and "--fields" in proto and "--repo" in proto and "section:" in proto, "")


# --------------------------------------------------------------- i52 N5 doc-section / card ----
def test_n5_docsection():
    """N5 (D-0142 F1): the section: verb serves doc: entities + deeper[]-pointer targets, bounded.
    Cloud acceptance probes replay the REAL i51 T1-cluster selector shapes against stand-ins."""
    gmap = os.path.join(FIX, "golden-map")
    repo = os.path.join(FIX, "repo")
    harvest = os.path.join(FIX, "harvest.json")

    def sq(expr):
        raw = _cli_raw(["query", "--map", gmap, "--q", expr, "--repo", repo, "--harvest", harvest])
        return json.loads(raw), len(raw.encode("utf-8"))

    # (a1) doc-entity form + BOLD-LABEL selector: the cadence header (NOT an ATX heading)
    e, nb = sq("section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header")
    s = e.get("result", {}).get("section", {})
    rec("n5-docsection", "cadence-header-bold-label-serves",
        e["status"] == "ok" and "FRONTSTEP-SENTINEL" in s.get("text", "") and "next_increment" in s.get("text", ""),
        str(e.get("error"))[:120])
    rec("n5-docsection", "cadence-header-marks-target+selector",
        s.get("target") == "doc-entity" and s.get("selector") == "bold-label" and s.get("level") == 0, str({k: s.get(k) for k in ("target", "selector", "level")}))
    rec("n5-docsection", "cadence-header-block-excludes-body", "## 0." not in s.get("text", ""), "")
    rec("n5-docsection", "cadence-envelope<=8000B(acceptance-a)", nb <= 8000, "bytes=%d" % nb)
    # (a2)/(a3) ATX sections of the doc entity (the REAL s5/s6 heading texts)
    e5, nb5 = sq("section:doc:core-docs/AUDIT_PIPELINE.md#5. Cadence + upkeep (how this stays alive without becoming a tax)")
    rec("n5-docsection", "s5-atx-serves", e5["status"] == "ok" and "CADENCE-S5-SENTINEL" in e5["result"]["section"]["text"], str(e5.get("error"))[:120])
    rec("n5-docsection", "s5-no-selector-key(atx)", "selector" not in e5["result"]["section"] and e5["result"]["section"].get("target") == "doc-entity", "")
    e6, nb6 = sq("section:doc:core-docs/AUDIT_PIPELINE.md#6. Anti-spiral guardrails (carried from the packet; binding)")
    rec("n5-docsection", "s6-atx-serves", e6["status"] == "ok" and "GUARDRAIL-S6-SENTINEL" in e6["result"]["section"]["text"], str(e6.get("error"))[:120])
    rec("n5-docsection", "s5+s6-envelopes<=8000B", nb5 <= 8000 and nb6 <= 8000, "s5=%d s6=%d" % (nb5, nb6))
    # (a4) research doc entity (mapped via the N6 claims -> golden): the honesty-map section
    e3, nb3 = sq("section:doc:core-docs/research/2026-08-08-i45-lrap-design.md#3a. The per-step x per-lane HONESTY MAP (fixed HERE, not deferred to the worker -- F3)")
    rec("n5-docsection", "research-doc-honesty-map-serves",
        e3["status"] == "ok" and "HONESTY-MAP-SENTINEL" in e3["result"]["section"]["text"] and nb3 <= 8000,
        "bytes=%d err=%s" % (nb3, str(e3.get("error"))[:100]))
    # (a5) deeper-pointer form: the w08-shape follow-ons block via widget deeper[work-order]
    e4, nb4 = sq("section:widget:90/gamma:work-order#Follow-ons (not this session)")
    s4 = e4.get("result", {}).get("section", {})
    rec("n5-docsection", "deeper-work-order-follow-ons-serves",
        e4["status"] == "ok" and "follow-on ALPHA" in s4.get("text", "") and s4.get("target") == "deeper[work-order]",
        str(e4.get("error"))[:120])
    rec("n5-docsection", "deeper-envelope<=8000B", nb4 <= 8000, "bytes=%d" % nb4)
    # short form + kind composes; resolved echoed
    e4s, _ = sq("section:widget:90:work-order#Follow-ons (not this session)")
    rec("n5-docsection", "short-form+kind-resolves", e4s["status"] == "ok" and e4s["result"].get("resolved") == "widget:90/gamma", str(e4s["result"].get("resolved")))
    # deeper[research] kind serve
    e4r, _ = sq("section:widget:90/gamma:research#3a. The per-step x per-lane HONESTY MAP (fixed HERE, not deferred to the worker -- F3)")
    rec("n5-docsection", "deeper-research-serves", e4r["status"] == "ok" and "HONESTY-MAP-SENTINEL" in e4r["result"]["section"]["text"], str(e4r.get("error"))[:100])
    # i49 byte-identity pin: an ATX module SCHEMA_NOTES fetch carries EXACTLY the 0.3.0 key set
    repo2, hp2 = _mk_section_repo()
    raw = _cli_raw(["query", "--map", gmap, "--q", "section:module:90/alpha.tool#3. ranking", "--repo", repo2, "--harvest", hp2])
    es = json.loads(raw)
    keys = sorted(es["result"]["section"].keys())
    rec("n5-docsection", "i49-schema-notes-keyset-byte-identical",
        es["status"] == "ok" and keys == sorted(["path", "sha256", "heading", "level", "harvest_commit", "bytes", "truncated", "text"]),
        "keys=%s" % keys)
    # negatives (existing codes only)
    for expr, code, nm in [
            ("section:doc:core-docs/GHOST.md#x", "DANGLING_REF", "unmapped-doc"),
            ("section:doc:core-docs/AUDIT_PIPELINE.md#No Such Heading", "DANGLING_REF", "missing-heading-doc"),
            ("section:module:90/alpha.tool:work-order#x", "DANGLING_REF", "no-pointer-of-kind"),
            ("section:widget:90/gamma:decision#x", "UNSUPPORTED_QUERY", "kind-not-servable")]:
        en, _ = sq(expr)
        rec("n5-docsection", "%s->%s" % (nm, code), en["status"] == "error" and en["error"]["code"] == code, str(en.get("error"))[:100])
    rc, env, _ = cli(["query", "--map", gmap, "--q", "section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header", "--harvest", harvest])
    rec("n5-docsection", "doc-form-no-repo->UNSUPPORTED_QUERY", env["status"] == "error" and env["error"]["code"] == "UNSUPPORTED_QUERY", "")


def _plane_card_block(plane_file, rid):
    txt = P.read_text(os.path.join(FIX, "golden-generated", plane_file))
    blocks = txt.split("\n## ")
    for b in blocks[1:]:
        if b.startswith(rid + "\n"):
            return ("## " + b).rstrip("\n")
    return None


def test_n5_card():
    """N5 (D-0142 F1): card:<id> serves ONE rendered L1 card, content-matching the committed
    plane file (single-source _l1_card_lines), bounded -- never a 31 KB plane-file open."""
    gmap = os.path.join(FIX, "golden-map")
    harvest = os.path.join(FIX, "harvest.json")
    for rid, group, short in [("module:90/alpha.tool", "modules", "module:90"),
                              ("widget:90/gamma", "widgets", "widget:90")]:
        raw = _cli_raw(["query", "--map", gmap, "--q", "card:%s" % rid, "--harvest", harvest])
        e = json.loads(raw); nb = len(raw.encode("utf-8"))
        c = e.get("result", {}).get("card", {})
        rec("n5-card", "%s-serves" % rid, e["status"] == "ok" and c.get("group") == group
            and c.get("plane_file") == "L1_CARDS_%s.md" % group, str(e.get("error"))[:100])
        rec("n5-card", "%s-envelope<=6000B(acceptance-b)" % rid, nb <= 6000, "bytes=%d" % nb)
        want = _plane_card_block("L1_CARDS_%s.md" % group, rid)
        rec("n5-card", "%s-content-matches-plane-file" % rid, want is not None and c.get("text", "").rstrip("\n") == want,
            "served=%r vs plane=%r" % (str(c.get("text"))[:60], str(want)[:60]))
        rec("n5-card", "%s-full-id-keyset" % rid, sorted(e["result"].keys()) == ["card", "q"], str(sorted(e["result"].keys())))
        es = json.loads(_cli_raw(["query", "--map", gmap, "--q", "card:%s" % short, "--harvest", harvest]))
        rec("n5-card", "%s-short-form-resolves" % short, es["status"] == "ok" and es["result"].get("resolved") == rid, str(es["result"].get("resolved")))
    # negatives
    rc, env, _ = cli(["query", "--map", gmap, "--q", "card:module:99", "--harvest", harvest])
    rec("n5-card", "unknown-id->DANGLING_REF", env["status"] == "error" and env["error"]["code"] == "DANGLING_REF", str(env.get("error")))
    rc, env, _ = cli(["query", "--map", gmap, "--q", "card:module:90"])
    rec("n5-card", "no-harvest->UNSUPPORTED_QUERY", env["status"] == "error" and env["error"]["code"] == "UNSUPPORTED_QUERY", str(env.get("error")))


# --------------------------------------------------------------- i52 N6 canon assertions ------
def _n6_claims():
    return json.loads(P.read_text(os.path.join(MOD, "claims", "i52-n6-canon-claims.json")))


# The i48 CD-1 pattern, extended: EVERY N6 canon assertion is string-asserted against the packet.
# Required = each canon ops one_line VERBATIM (single-sourced from the claims file) + the named
# load-bearing sub-tokens; forbidden = softened-D-0064 phrasings a future render must never carry.
N6_REQUIRED_TOKENS = [
    "HUMAN live-GUI confirm BEFORE it is called done",   # D-0064 full strength
    "no softening",
    "REFUSES violating core-doc commits",                 # K5 fail-closed gate
    "DOC_PROTOCOL s2",
    "doc-commit-gate.py",
    "Mandate-02 is SUNSET",                               # K6 sunset state
    "NO live process mandate",
    "SEALED_CHECK_47 armed, opens i>=54",
    "SURVIVE",
    "design-first -> red-team-gated",                     # K9 non-optional red-team gate
    "NEVER OPTIONAL",
]
N6_FORBIDDEN_TOKENS = ["ship not blocked", "not blocked on", "ship-not-blocked", "confirm later"]


def n6_canon_findings(packet_text, claims=None):
    """Return a list of canon failures (empty == packet carries the full-strength canon)."""
    fails = []
    claims = claims or _n6_claims()
    for rec_ in claims["entities"]:
        if rec_["id"].startswith("ops:boot-"):
            if rec_["one_line"] not in packet_text:
                fails.append("one_line-missing:%s" % rec_["id"])
    for tok in N6_REQUIRED_TOKENS:
        if tok not in packet_text:
            fails.append("required-token-missing:%s" % tok)
    for tok in N6_FORBIDDEN_TOKENS:
        if tok in packet_text:
            fails.append("forbidden-token-present:%s" % tok)
    return fails


def test_n6_canon():
    gmap = os.path.join(FIX, "golden-map")
    harvest = json.loads(P.read_text(os.path.join(FIX, "harvest.json")))
    bp = P.read_text(os.path.join(FIX, "golden-generated", "BOOT_PACKET.md"))
    # (c) the golden packet carries EVERY canon assertion
    fails = n6_canon_findings(bp)
    rec("n6-canon", "golden-packet-carries-every-canon-assertion", not fails, str(fails))
    # every canon line is pointer-backed inside OPERATIONS
    ops_sec = bp.split("## OPERATIONS", 1)[1].split("\n## ", 1)[0] if "## OPERATIONS" in bp else ""
    canon_lines = [ln for ln in ops_sec.splitlines() if ln.startswith("- ")]
    rec("n6-canon", "canon-lines-pointer-backed(>=4)", len(canon_lines) >= 4 and all("[" in ln and "]" in ln for ln in canon_lines), "n=%d" % len(canon_lines))
    # (c) >= 1 rendered open_ruling with its ref
    rec("n6-canon", "open-ruling-rendered-with-ref",
        "OPEN RULINGS" in bp and "gamma explain window cannot be closed after the fact" in bp and "(decision:D-9002)" in bp, "")
    # OPERATIONS held level 0 (no ops ladder step) so canon one_lines are verbatim, never truncated
    model = P.load_map(gmap)
    vr = P.validate(model, harvest, is_real=True)
    _, _, ladder, _, _, _ = P._build_boot_packet(model, harvest, set(vr["stale_entities"]), vr["load_bearing"])
    rec("n6-canon", "ops-level-0-no-truncation", not any("OPERATIONS" in step for step in ladder), str(ladder))
    # ingest roundtrip of the SHIPPED claims file: strip the canon -> ingest -> present + idempotent
    work = tempfile.mkdtemp(prefix="pm-n6-")
    m = os.path.join(work, "m")
    shutil.copytree(gmap, m)
    P.write_lf(os.path.join(m, "entities", "ops.json"),
               P.dumps_map({"schema": P.SCHEMA_ENTITIES, "kind": "entities", "items": []}))
    for fn, drop in (("meta.json", "decision:D-0064"), ("docs.json", "doc:core-docs/research/2026-08-08-i45-lrap-design.md")):
        fp = os.path.join(m, "entities", fn)
        doc = json.loads(P.read_text(fp))
        doc["items"] = [it for it in doc["items"] if it.get("id") != drop]
        P.write_lf(fp, P.dumps_map(doc))
    cf = os.path.join(MOD, "claims", "i52-n6-canon-claims.json")
    res = P.op_ingest_claims(m, cf, harvest, None)
    rec("n6-canon", "shipped-claims-ingest-upserts(6)", res["entities_upserted"] == 6, str(res))
    d1 = _map_digest(m)
    P.op_ingest_claims(m, cf, harvest, None)
    rec("n6-canon", "shipped-claims-ingest-idempotent", _map_digest(m) == d1, "")
    out = tempfile.mkdtemp(prefix="pm-n6r-")
    P.op_render(m, harvest, out, check=False, draft=False)
    bp2 = P.read_text(os.path.join(out, "BOOT_PACKET.md"))
    rec("n6-canon", "post-ingest-render-carries-canon", not n6_canon_findings(bp2), str(n6_canon_findings(bp2))[:200])
    # NEGATIVE: a softened D-0064 phrasing FAILS the canon assertions
    m2 = os.path.join(work, "m2")
    shutil.copytree(gmap, m2)
    fp = os.path.join(m2, "entities", "ops.json")
    doc = json.loads(P.read_text(fp))
    for it in doc["items"]:
        if it["id"] == "ops:boot-ui-live-confirm":
            it["one_line"] = "D-0064: UI live-GUI confirm is advisory; ship not blocked on it; confirm later at a convenient touch."
    P.write_lf(fp, P.dumps_map(doc))
    model2 = P.load_map(m2)
    vr2 = P.validate(model2, harvest, is_real=True)
    body2, _, _, _, _, _ = P._build_boot_packet(model2, harvest, set(vr2["stale_entities"]), vr2["load_bearing"])
    soft = n6_canon_findings(body2)
    rec("n6-canon", "softened-D-0064-FAILS-canon-check",
        any(f.startswith("required-token-missing:HUMAN live-GUI confirm") for f in soft)
        and any(f.startswith("forbidden-token-present:") for f in soft), str(soft)[:200])
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(out, ignore_errors=True)


def main():
    for t in (test_golden, test_determinism, test_negatives, test_drift,
              test_parse_budgets_parity, test_ingest, test_reaffirm_fmt_changed,
              test_shortform, test_evidence_provenance, test_operations, test_ops_roundtrip,
              test_mandate_absent, test_n1_purpose, test_n1_section, test_n2_frontier,
              test_n3_verbtable, test_n5_docsection, test_n5_card, test_n6_canon):
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
