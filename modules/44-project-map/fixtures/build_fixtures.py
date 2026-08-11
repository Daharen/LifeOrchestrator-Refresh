#!/usr/bin/env python3
# -*- coding: ascii -*-
"""Deterministic fixture generator for project.map tests. Writes: a tiny fixture repo, its golden
harvest, a fully-resolved golden mini-map, the committed golden renders, the normative fixture #0
claims file, and the negative suite (one dir per error code). Run: python3 fixtures/build_fixtures.py

Re-runnable and byte-deterministic (no clock/random). The committed outputs ARE the golden."""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
sys.path.insert(0, MOD)
import project_map as P  # noqa: E402

FIX = HERE
REPO = os.path.join(FIX, "repo")
GOLDEN_MAP = os.path.join(FIX, "golden-map")
GOLDEN_GEN = os.path.join(FIX, "golden-generated")
NEG = os.path.join(FIX, "negative")
AT = "goldensha0000000000000000000000000000000"


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def wj(path, obj):
    w(path, P.dumps_map(obj))


# ---------------------------------------------------------------- fixture repo ----------------
def build_repo():
    if os.path.isdir(REPO):
        shutil.rmtree(REPO)
    # import parse_budgets source (copy the real gen-doc-health.py so the import path exists)
    real_gdh = os.path.join(os.environ.get("REAL_REPO", ""), "ops", "audit", "gen-doc-health.py")
    os.makedirs(_p("ops/audit"), exist_ok=True)
    if os.path.isfile(real_gdh):
        shutil.copy(real_gdh, _p("ops/audit/gen-doc-health.py"))
    else:
        w(_p("ops/audit/gen-doc-health.py"), _GDH_STUB)
    # modules
    for num, slug, sid, det, par in [("90", "alpha", "alpha.tool", "deterministic", True),
                                     ("91", "beta", "beta.tool", "deterministic", False)]:
        man = {"schema": "lifeorch.skill.manifest/0.1", "skill_id": sid, "name": slug.title(),
               "version": "0.1.0", "contract_version": "0.2",
               "purpose": "%s does the first thing. It also does more later." % slug.title(),
               "determinism": det, "invocation": {"method": "pwsh-file", "entrypoint": "x.ps1"},
               "inputs": [{"name": "path", "type": "string", "required": True}],
               "outputs": {"result_shape": "object"},
               "requirements": {"executables": ["pwsh>=7.4"], "network": False},
               "parallel_safe": par}
        w(_p("modules/%s-%s/skill.json" % (num, slug)), json.dumps(man, indent=2) + "\n")
        w(_p("modules/%s-%s/README.md" % (num, slug)), "# %s\nFixture module %s.\n" % (slug, num))
        w(_p("modules/%s-%s/WORK_ORDER.md" % (num, slug)), "# WORK_ORDER %s\n" % num)
        w(_p("modules/%s-%s/tests/t.ps1" % (num, slug)), "# tests\n")
    # widget
    w(_p("widgets/90-gamma/README.md"), "# gamma widget\n")
    w(_p("widgets/90-gamma/launch.bat"), "@echo off\n")
    # core-docs
    w(_p("core-docs/DOC_PROTOCOL.md"), _DOC_PROTOCOL)
    w(_p("core-docs/DECISION_LOG_INDEX.md"), _DINDEX)
    w(_p("core-docs/PROCESS_MANDATE.md"), _MANDATE)
    w(_p("core-docs/ARCHITECTURE_MAP.md"), _ARCH)


def _p(rel):
    return os.path.join(REPO, rel)


_DOC_PROTOCOL = """# DOC_PROTOCOL (fixture)

## 2. The doc set: owner, budget

| doc | owns | budget |
|---|---|---|
| DOC_PROTOCOL.md | this contract | 12 KB |
| DECISION_LOG_INDEX.md | one row per decision | 20 KB |
| PROCESS_MANDATE.md | the live mandate | 12 KB |
| ARCHITECTURE_MAP.md | long-horizon spine | 15 KB |

## 3. Next
Nothing.
"""

_DINDEX = """# DECISION_LOG_INDEX (fixture)

| id | date | state | decision |
|---|---|---|---|
| D-9001 | 2026-08-11 | locked | Deterministic machinery owns structure; agents provide judgment |
| D-9002 | 2026-08-11 | locked | P0-1 activation prohibited until the gate is independently ratified |
"""

_MANDATE = """# PROCESS_MANDATE (fixture)

Machine-checkable header:
- `mandate_id: 02`
- `opened_iteration: 40`
- `current_iteration: 46`
- `iterations_to_sunset: 1`
- `sunset_iteration: 47`
- `state: ACTIVE`
"""

_ARCH = """# ARCHITECTURE_MAP (fixture)

## The canonical spine (0-49)
- **23 `artifact.search`** -- retrieval over all local-skill artifacts.
- **38** Visual-only action executor -- deterministic input injection.
- **44** Synthetic screen and asset generator -- image generation family.
"""

_GDH_STUB = '''#!/usr/bin/env python3
import os, re
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = os.path.join(REPO, "core-docs")
KB = 1000
def parse_budgets():
    txt = open(os.path.join(CORE, "DOC_PROTOCOL.md"), encoding="utf-8").read()
    budgets = {}
    for m in re.finditer(r"^\\|\\s*([A-Za-z0-9_./<>&;-]+\\.md)\\s*\\|[^|]*\\|\\s*([^|]+?)\\s*\\|", txt, re.M):
        doc, b = m.group(1), m.group(2)
        km = re.search(r"(\\d+)\\s*KB", b)
        budgets[doc] = int(km.group(1)) if km else None
    return budgets
'''


# ---------------------------------------------------------------- golden map ------------------
def _src(ref, inv, fields, by, sha=True):
    s = {"ref": ref, "fields": sorted(fields), "by": by, "at_commit": AT}
    if P._ref_is_path(ref):
        path = ref.split("#", 1)[0]
        s["sha256"] = inv.get(path) if sha else None
    else:
        s["sha256"] = None
    return s


def build_golden(harvest):
    inv = harvest["inventory"]
    E = []

    def mod(num, slug, sid, plane, status, det, par, one):
        skill = "modules/%s-%s/skill.json" % (num, slug)
        readme = "modules/%s-%s/README.md" % (num, slug)
        return {
            "id": "module:%s/%s" % (num, sid), "ns": "module",
            "display_name": "#%s %s" % (num, sid), "one_line": one,
            "plane_primary": plane, "status": status,
            "version": "0.1.0", "determinism": det, "parallel_safe": par,
            "aliases": ["#%s" % num], "authority_docs": ["contract:skill-contract"],
            "deeper": [{"kind": "readme", "ref": readme},
                       {"kind": "contract", "ref": "contract:skill-contract"}],
            "confidence": "established",
            "sources": [_src(skill, inv, ["version", "determinism", "parallel_safe"], "harvest_v1"),
                        _src(readme, inv, ["one_line", "plane_primary", "status", "aliases",
                                           "authority_docs", "deeper"], "lane-B-i46")],
        }
    E.append(mod("90", "alpha", "alpha.tool", "capability", "active", "deterministic", True,
                 "Alpha capability tool; first-line deterministic worker in the fixture."))
    E.append(mod("91", "beta", "beta.tool", "memory", "mvp-complete", "deterministic", False,
                 "Beta memory substrate; persists and serves the alpha store."))
    # widget
    E.append({"id": "widget:90/gamma", "ns": "widget", "display_name": "gamma", "one_line":
              "Gamma observability widget; audits beta and invokes alpha.",
              "plane_primary": "observability", "status": "mvp-complete", "aliases": ["gamma-widget"],
              "confidence": "established",
              "sources": [_src("widgets/90-gamma/README.md", inv, ["one_line", "plane_primary", "status", "aliases"], "lane-B-i46")]})
    # planes
    for p in P.PLANES:
        E.append({"id": "plane:%s" % p, "ns": "plane", "display_name": p.title() + " plane",
                  "one_line": "%s plane (D-0080 fixture doctrine)." % p.title(),
                  "sources": [_src("core-docs/ARCHITECTURE_MAP.md", inv, ["one_line"], "harvest_v1")]})
    # arch
    for n, nm in [("23", "artifact.search"), ("38", "visual-executor")]:
        E.append({"id": "arch:%s" % n, "ns": "arch", "display_name": nm,
                  "one_line": "Architecture position %s (%s)." % (n, nm),
                  "sources": [_src("core-docs/ARCHITECTURE_MAP.md", inv, ["one_line"], "harvest_v1")]})
    # store
    E.append({"id": "store:alpha-store", "ns": "store", "display_name": "Alpha store",
              "one_line": "Persistent store backing alpha/beta in the fixture.",
              "sources": [_src("decision:D-9001", inv, ["one_line"], "lane-B-i46")]})
    # contract
    E.append({"id": "contract:skill-contract", "ns": "contract", "display_name": "Skill contract",
              "one_line": "The skill interface contract governing modules in the fixture.",
              "sources": [_src("core-docs/DOC_PROTOCOL.md", inv, ["one_line"], "harvest_v1")]})
    # docs (one per harvested core-doc -> no HARVEST_ORPHAN)
    for cd in harvest["core_docs"]:
        path = cd["path"]
        E.append({"id": "doc:%s" % path, "ns": "doc", "display_name": os.path.basename(path),
                  "one_line": "Core doc %s (fixture)." % os.path.basename(path),
                  "sources": [_src(path, inv, ["one_line"], "harvest_v1")]})
    # meta stubs (doctrine + prohibition authority)
    E.append({"id": "decision:D-9001", "ns": "decision", "display_name": "D-9001",
              "one_line": "Deterministic machinery owns structure; agents provide only judgment.",
              "doctrine": True,
              "sources": [_src("decision:D-9001", inv, ["one_line"], "orchestrator-i46")]})
    E.append({"id": "decision:D-9002", "ns": "decision", "display_name": "D-9002",
              "one_line": "P0-1 activation is prohibited until the gate is independently ratified.",
              "sources": [_src("decision:D-9002", inv, ["one_line"], "orchestrator-i46")]})

    def edge(fr, ty, to, by="lane-B-i46"):
        return {"from": fr, "type": ty, "to": to,
                "sources": [_src("decision:D-9001", inv, ["*"], by)]}
    R = [
        edge("module:90/alpha.tool", "realizes", "arch:23"),
        edge("module:91/beta.tool", "realizes", "arch:38"),
        edge("module:91/beta.tool", "persists", "store:alpha-store"),
        edge("module:90/alpha.tool", "retrieves-from", "store:alpha-store"),
        edge("module:90/alpha.tool", "invokes", "module:91/beta.tool"),
        edge("module:90/alpha.tool", "depends-on", "module:91/beta.tool"),
        edge("widget:90/gamma", "invokes", "module:90/alpha.tool"),
        edge("widget:90/gamma", "audits", "module:91/beta.tool"),
        edge("contract:skill-contract", "governs", "module:90/alpha.tool"),
        edge("contract:skill-contract", "governs", "module:91/beta.tool"),
        edge("doc:core-docs/DOC_PROTOCOL.md", "documents", "module:90/alpha.tool"),
        edge("module:90/alpha.tool", "verifies", "module:91/beta.tool"),
    ]
    overlay = {
        "schema": P.SCHEMA_OVERLAY, "at_commit": AT, "iteration": 46,
        "phase": {"ref": "doc:core-docs/PROCESS_MANDATE.md", "text": "i46 fixture close; PCB build."},
        "frontier": {"next_iteration": 47, "summary": "i47 migration gate dry-run (fixture).",
                     "derived_from": "doc:core-docs/PROCESS_MANDATE.md", "candidates": []},
        "mandate": {"id": "02", "sunset_iteration": "47", "state": "ACTIVE"},
        "prohibitions": [{"text": "No P0-1 activation until ratified", "authority": "decision:D-9002",
                          "status": "live"}],
        "open_rulings": [],
        "boot_read": [{"kind": "contract", "ref": "contract:skill-contract"},
                      {"kind": "decision", "ref": "decision:D-9001"}],
    }
    return E, R, overlay


def write_map(map_dir, entities, edges, overlay):
    if os.path.isdir(map_dir):
        shutil.rmtree(map_dir)
    m = P.MapModel()
    for e in entities:
        m.entities[e["id"]] = e
        m.entity_files[e["id"]] = P._file_for_ns(P._ns_of(e["id"]))
    m.edges = [dict(x, _file="relationships.json") for x in edges]
    m.overlay = overlay
    P._write_map(m, map_dir)


def main():
    build_repo()
    harvest = P.op_harvest(REPO, AT, False)
    w(os.path.join(FIX, "harvest.json"), P.dumps_compact(harvest))
    E, R, ov = build_golden(harvest)
    write_map(GOLDEN_MAP, E, R, ov)
    # validate golden
    model = P.load_map(GOLDEN_MAP)
    vr = P.validate(model, harvest, is_real=True)
    if vr["findings"]:
        print("GOLDEN VALIDATION FAILED:")
        for f in vr["findings"]:
            print("  ", f["code"], f["where"], f["message"])
        sys.exit(1)
    # render golden -> committed golden-generated/
    if os.path.isdir(GOLDEN_GEN):
        shutil.rmtree(GOLDEN_GEN)
    res = P.op_render(GOLDEN_MAP, harvest, GOLDEN_GEN, check=False, draft=False)
    print("GOLDEN OK: %d entities, %d edges, BOOT_PACKET=%d bytes, ladder=%s"
          % (len(E), len(R), res["boot_packet_bytes"], res["ladder"]))
    # fixture #0 (byte-verbatim normative claims example)
    w(os.path.join(FIX, "example-claims.json"), FIXTURE0)
    # negatives
    build_negatives(harvest)
    print("fixtures built.")


FIXTURE0 = ('{"schema":"lifeorch.map_claims/0.1","by":"example","at_commit":"000000000000000000000'
            '0000000000000000000",\n "entities":[{"id":"module:36/artifact.search","plane_primary'
            '":"memory","one_line":"SQLite+FTS5 typed-record memory substrate; Tier-1 hierarchy + '
            'fast-beam retrieval.",\n   "sources":[{"ref":"modules/36-artifact-search/README.md","'
            'sha256":null,"fields":["plane_primary","one_line"],"by":"example","at_commit":"000000'
            '0000000000000000000000000000000000000"}]}],\n "relationships":[{"from":"module:40/con'
            'text.compiler","type":"retrieves-from","to":"store:artifact-search-sqlite",\n   "sour'
            'ces":[{"ref":"decision:D-0100","sha256":null,"fields":["*"],"by":"example","at_commit"'
            ':"0000000000000000000000000000000000000000"}]}]}\n')


def build_negatives(harvest):
    if os.path.isdir(NEG):
        shutil.rmtree(NEG)
    import copy
    E, R, ov = build_golden(harvest)
    inv = harvest["inventory"]

    def base():
        return copy.deepcopy(E), copy.deepcopy(R), copy.deepcopy(ov)

    def emit(code, entities, edges, overlay, op="validate", harv=harvest, args=None, expect=None):
        d = os.path.join(NEG, code)
        write_map(os.path.join(d, "map"), entities, edges, overlay)
        w(os.path.join(d, "harvest.json"), P.dumps_compact(harv))
        a = {"map": "map", "harvest": "harvest.json"}
        a.update(args or {})
        meta = {"code": code, "op": op, "expect": expect or code, "args": a}
        w(os.path.join(d, "case.json"), P.dumps_compact(meta))

    # ---- structural single-error mutations off the golden base ----
    e, r, o = base()
    bad = copy.deepcopy(e[0]); bad["id"] = "module:99/Bad Id"; bad["display_name"] = "bad"
    bad["aliases"] = []; e.append(bad)  # additive, unreferenced -> only ID_GRAMMAR
    emit("ID_GRAMMAR", e, r, o)

    e, r, o = base(); e.append({"id": "zzz:thing", "ns": "zzz", "display_name": "x", "one_line": "y",
                                "sources": [_src("core-docs/ARCHITECTURE_MAP.md", harvest["inventory"], ["one_line"], "harvest_v1")]})
    emit("UNKNOWN_NS", e, r, o)

    e, r, o = base(); r.append({"from": "module:90/alpha.tool", "type": "frobnicates",
                                "to": "module:91/beta.tool",
                                "sources": [_src("decision:D-9001", harvest["inventory"], ["*"], "x")]})
    emit("UNKNOWN_EDGE_TYPE", e, r, o)

    # DUP_ID: write_map dedups by id, so materialize the duplicate directly into modules.json
    e, r, o = base()
    emit("DUP_ID", e, r, o)
    mj = os.path.join(NEG, "DUP_ID", "map", "entities", "modules.json")
    doc = json.loads(P.read_text(mj))
    doc["items"].append(copy.deepcopy(doc["items"][0]))
    w(mj, P.dumps_map(doc))

    e, r, o = base(); r.append(copy.deepcopy(r[0]))  # duplicate edge (from,type,to) in one file
    emit("DUP_EDGE", e, r, o)

    e, r, o = base(); r.append({"from": "module:90/alpha.tool", "type": "invokes",
                                "to": "module:99/missing",
                                "sources": [_src("decision:D-9001", harvest["inventory"], ["*"], "x")]})
    emit("DANGLING_REF", e, r, o)

    # MISSING_PROVENANCE via an edge with no sources (avoids cascading FIELD_UNCOVERED)
    e, r, o = base()
    r.append({"from": "module:90/alpha.tool", "type": "invokes", "to": "widget:90/gamma", "sources": []})
    emit("MISSING_PROVENANCE", e, r, o)

    e, r, o = base(); e[0]["audit_surfaces"] = ["logs"]  # present field, not covered by any source
    emit("FIELD_UNCOVERED", e, r, o)

    e, r, o = base(); e[0]["load_bearing"] = True
    emit("DERIVED_FIELD_AUTHORED", e, r, o)

    # member-of authored edge -> also DERIVED_FIELD_AUTHORED (documented alias)
    e, r, o = base(); r.append({"from": "module:90/alpha.tool", "type": "member-of", "to": "plane:capability",
                                "sources": [_src("decision:D-9001", harvest["inventory"], ["*"], "x")]})
    emit("DERIVED_FIELD_AUTHORED_EDGE", e, r, o, expect="DERIVED_FIELD_AUTHORED")

    # CONFLICT_HARVEST: entity version disagrees with harvested skill.json
    e, r, o = base(); e[0]["version"] = "9.9.9"
    emit("CONFLICT_HARVEST", e, r, o)

    # SCHEMA_INVALID: bad status enum
    e, r, o = base(); e[0]["status"] = "banana"
    emit("SCHEMA_INVALID", e, r, o)

    # SKELETON_LOAD_BEARING: skeleton + status active (load-bearing)
    e, r, o = base(); e[0]["skeleton"] = True
    emit("SKELETON_LOAD_BEARING", e, r, o)

    # SKELETON_UNRESOLVED (render): a benign skeleton entity, render refuses
    e, r, o = base()
    e[1]["skeleton"] = True; e[1]["status"] = "proposed"; e[1].pop("plane_primary", None)
    emit("SKELETON_UNRESOLVED", e, r, o, op="render", args={"out": "_out"})

    # HARVEST_ORPHAN: drop the widget entity while harvest still lists the widget dir
    e, r, o = base()
    e = [x for x in e if x["id"] != "widget:90/gamma"]
    r = [x for x in r if "widget:90/gamma" not in (x["from"], x["to"])]
    emit("HARVEST_ORPHAN", e, r, o)

    # ENTITY_UNBACKED: source path ref that is not in harvest inventory
    e, r, o = base()
    e[0]["sources"].append({"ref": "modules/90-alpha/GHOST.md", "sha256": "a" * 64,
                            "fields": ["one_line"], "by": "lane-B-i46", "at_commit": AT})
    emit("ENTITY_UNBACKED", e, r, o)

    # STALE_LOAD_BEARING: load-bearing entity's source sha256 no longer matches inventory
    e, r, o = base()
    for s in e[0]["sources"]:
        if s.get("ref", "").endswith("README.md"):
            s["sha256"] = "b" * 64
    emit("STALE_LOAD_BEARING", e, r, o)

    # OVERLAY_MANDATE_DRIFT: overlay mandate id disagrees with header invariant
    e, r, o = base(); o["mandate"]["id"] = "03"
    emit("OVERLAY_MANDATE_DRIFT", e, r, o)

    # OVERLAY_PROHIBITIONS_EMPTY: live freeze (mandate ACTIVE) but no prohibitions
    e, r, o = base(); o["prohibitions"] = []
    emit("OVERLAY_PROHIBITIONS_EMPTY", e, r, o)

    # OVERLAY_DANGLING: prohibition authority whose decision carries an inbound supersedes edge
    e, r, o = base()
    r.append({"from": "decision:D-9001", "type": "supersedes", "to": "decision:D-9002",
              "sources": [_src("decision:D-9001", harvest["inventory"], ["*"], "x")]})
    emit("OVERLAY_DANGLING", e, r, o)

    # DIRTY_TREE (render): harvest.dirty true
    e, r, o = base()
    hd = json.loads(P.dumps_compact(harvest)); hd["dirty"] = True
    emit("DIRTY_TREE", e, r, o, op="render", harv=hd, args={"out": "_out"})

    # STALE_BUDGET: >20% of entities carry a stale field, NONE load-bearing (else STALE_LOAD_BEARING).
    # PROCESS_MANDATE doc is load-bearing (frontier.derived_from refs it), so exclude it.
    e, r, o = base()
    stale_targets = {"doc:core-docs/DOC_PROTOCOL.md", "doc:core-docs/DECISION_LOG_INDEX.md",
                     "doc:core-docs/ARCHITECTURE_MAP.md", "widget:90/gamma"}
    for x in e:
        if x["id"] in stale_targets:
            for s in x["sources"]:
                if P._ref_is_path(s.get("ref", "")):
                    s["sha256"] = "c" * 64
    emit("STALE_BUDGET", e, r, o)

    # ---- op-driven negatives (need a claims file / big map / drift / fmt / repo) ----
    # PACKET_OVER_BUDGET: a large valid map whose BOOT_PACKET exceeds the hard 20000 B after the ladder
    big = []
    for p in P.PLANES:
        big.append({"id": "plane:%s" % p, "ns": "plane", "display_name": p, "one_line": "%s plane." % p,
                    "sources": [_src("decision:D-9001", inv, ["one_line"], "x")]})
    big.append({"id": "decision:D-9001", "ns": "decision", "display_name": "D-9001",
                "one_line": "doctrine.", "sources": [_src("decision:D-9001", inv, ["one_line"], "x")]})
    for i in range(320):
        one = ("ops unit %03d deterministic padding line to fill the system-at-a-glance section body "
               "well beyond") % i
        big.append({"id": "ops:pad-%03d" % i, "ns": "ops", "display_name": "pad %03d" % i,
                    "one_line": one[:120], "plane_primary": "capability", "status": "active",
                    "sources": [_src("decision:D-9001", inv, ["one_line", "plane_primary", "status"], "x")]})
    minh = {"schema": "lifeorch.project_map.harvest/0.1", "at_commit": AT, "dirty": False,
            "modules": [], "widgets": [], "core_docs": [], "doc_owner_rows": [], "decision_ids": [],
            "mandate": {}, "arch": [], "budgets": {}, "inventory": {}, "counts": {}}
    emit("PACKET_OVER_BUDGET", big, [], None, op="render", harv=minh, args={"out": "_out"})

    # GENERATED_DRIFT: committed generated/ mutated vs a fresh render (render --check)
    e, r, o = base()
    d = os.path.join(NEG, "GENERATED_DRIFT")
    write_map(os.path.join(d, "map"), e, r, o)
    w(os.path.join(d, "harvest.json"), P.dumps_compact(harvest))
    P.op_render(os.path.join(d, "map"), harvest, os.path.join(d, "generated"), check=False, draft=False)
    # mutate one committed file
    bp = os.path.join(d, "generated", "BOOT_PACKET.md")
    with open(bp, "a", encoding="utf-8", newline="\n") as fh:
        fh.write("<!-- tampered -->\n")
    w(os.path.join(d, "case.json"), P.dumps_compact(
        {"code": "GENERATED_DRIFT", "op": "render", "expect": "GENERATED_DRIFT",
         "args": {"map": "map", "harvest": "harvest.json", "out": "generated", "check": True}}))

    # FMT_NONCANONICAL: a non-canonical JSON file under a map/ dir
    d = os.path.join(NEG, "FMT_NONCANONICAL")
    w(os.path.join(d, "map", "entities", "modules.json"),
      '{"schema":"lifeorch.project_map/0.1","kind":"entities","items":[]}')  # compact = non-canonical
    w(os.path.join(d, "case.json"), P.dumps_compact(
        {"code": "FMT_NONCANONICAL", "op": "fmt", "expect": "FMT_NONCANONICAL",
         "args": {"fmt_paths": ["map"], "check": True}}))

    # CLAIM_RESTATES_HARVEST: a claim that restates a harvested (mechanical) field
    d = os.path.join(NEG, "CLAIM_RESTATES_HARVEST")
    e, r, o = base(); write_map(os.path.join(d, "map"), e, r, o)
    w(os.path.join(d, "harvest.json"), P.dumps_compact(harvest))
    claims = {"schema": P.SCHEMA_CLAIMS, "by": "lane-B-i46", "at_commit": AT,
              "entities": [{"id": "module:90/alpha.tool", "version": "0.1.0",
                            "sources": [{"ref": "modules/90-alpha/skill.json", "sha256": None,
                                         "fields": ["version"], "by": "lane-B-i46", "at_commit": AT}]}],
              "relationships": []}
    w(os.path.join(d, "claims.json"), P.dumps_map(claims))
    w(os.path.join(d, "case.json"), P.dumps_compact(
        {"code": "CLAIM_RESTATES_HARVEST", "op": "ingest-claims", "expect": "CLAIM_RESTATES_HARVEST",
         "args": {"map": "map", "harvest": "harvest.json", "claims": "claims.json"}}))

    # CONFLICT_CLAIMS: a claim on a field held by a different claimant (no --override)
    d = os.path.join(NEG, "CONFLICT_CLAIMS")
    e, r, o = base(); write_map(os.path.join(d, "map"), e, r, o)
    w(os.path.join(d, "harvest.json"), P.dumps_compact(harvest))
    claims = {"schema": P.SCHEMA_CLAIMS, "by": "other-lane", "at_commit": AT,
              "entities": [{"id": "module:90/alpha.tool", "one_line": "A different curated one_line.",
                            "sources": [{"ref": "modules/90-alpha/README.md", "sha256": None,
                                         "fields": ["one_line"], "by": "other-lane", "at_commit": AT}]}],
              "relationships": []}
    w(os.path.join(d, "claims.json"), P.dumps_map(claims))
    w(os.path.join(d, "case.json"), P.dumps_compact(
        {"code": "CONFLICT_CLAIMS", "op": "ingest-claims", "expect": "CONFLICT_CLAIMS",
         "args": {"map": "map", "harvest": "harvest.json", "claims": "claims.json"}}))

    # PARSE_ROW_FAILED: harvest a repo whose DOC_PROTOCOL s2 has a malformed row
    d = os.path.join(NEG, "PARSE_ROW_FAILED")
    shutil.copytree(REPO, os.path.join(d, "repo"))
    bad = _DOC_PROTOCOL.replace("| ARCHITECTURE_MAP.md | long-horizon spine | 15 KB |",
                                "| ARCHITECTURE_MAP.md | missing budget cell |")
    w(os.path.join(d, "repo", "core-docs", "DOC_PROTOCOL.md"), bad)
    w(os.path.join(d, "case.json"), P.dumps_compact(
        {"code": "PARSE_ROW_FAILED", "op": "harvest", "expect": "PARSE_ROW_FAILED",
         "args": {"repo": "repo"}}))

    print("negatives built:", sorted(os.listdir(NEG)))


if __name__ == "__main__":
    main()
