#!/usr/bin/env python3
# -*- coding: ascii -*-
"""Seed modules/44-project-map/map/ from harvest ONLY (WO s7). One-time Lane A build tool -- NOT a
runtime op of the skill. Mechanical fields only: modules/widgets are skeleton:true with one_line =
the manifest purpose FIRST SENTENCE (never a judgment field); core-docs/arch are mechanical; the 5
fixed planes are seeded as structural constants (a documented boundary decision -- see the report).
generated/ ships EMPTY (+.gitkeep). NO planes/curated one_lines/edges/deeper/overlay -- those are the
claims lane's and the orchestrator's at fold. Usage: python3 tests/seed_map.py <repo-root> <map-dir>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
sys.path.insert(0, MOD)
import project_map as P  # noqa: E402


def _src(ref, inv, fields, by="harvest_v1", at=None):
    s = {"ref": ref, "fields": sorted(fields), "by": by, "at_commit": at}
    if P._ref_is_path(ref):
        s["sha256"] = inv.get(ref.split("#", 1)[0])
    else:
        s["sha256"] = None
    return s


def _first_existing(repo, inv, candidates, prefix):
    for c in candidates:
        if c in inv:
            return c
    for path in sorted(inv):
        if path.startswith(prefix):
            return path
    return None


def seed(repo, map_dir):
    at = "seed"
    harvest = P.op_harvest(repo, at, False)
    inv = harvest["inventory"]
    m = P.MapModel()

    def put(rec):
        m.entities[rec["id"]] = rec
        m.entity_files[rec["id"]] = P._file_for_ns(P._ns_of(rec["id"]))

    # modules (skeleton:true; one_line = purpose first sentence; scalar mechanical fields only)
    for mod in harvest["modules"]:
        num, sid, slug = mod.get("num"), mod.get("skill_id"), mod.get("dir_slug")
        eid = "module:%s/%s" % (num, sid or slug)
        prefix = "modules/%s-%s/" % (num, slug)
        ref = _first_existing(repo, inv, ["modules/%s-%s/skill.json" % (num, slug),
                                          "modules/%s-%s/README.md" % (num, slug),
                                          "modules/%s-%s/WORK_ORDER.md" % (num, slug)], prefix)
        one = mod.get("purpose_first_sentence") or ("Harvest-seeded module %s (awaiting claims)." % mod.get("dir"))
        rec = {"id": eid, "ns": "module", "display_name": "#%s %s" % (num, sid or slug),
               "one_line": P._clip160(one), "skeleton": True, "aliases": ["#%s" % num]}
        fields = ["one_line", "aliases"]
        for f in ("version", "determinism", "parallel_safe"):
            if mod.get(f) is not None:
                rec[f] = mod[f]
                fields.append(f)
        if ref:
            rec["sources"] = [_src(ref, inv, fields, "harvest_v1", at)]
        else:
            rec["sources"] = [_src(eid, inv, fields, "harvest_v1", at)]
        put(rec)

    # widgets (skeleton:true)
    for wid in harvest["widgets"]:
        num, slug = wid.get("num"), wid.get("dir_slug")
        eid = "widget:%s/%s" % (num, slug)
        prefix = "widgets/%s-%s/" % (num, slug)
        ref = _first_existing(repo, inv, ["widgets/%s-%s/README.md" % (num, slug),
                                          "widgets/%s-%s/launch.bat" % (num, slug)], prefix)
        rec = {"id": eid, "ns": "widget", "display_name": slug, "skeleton": True,
               "one_line": P._clip160("Harvest-seeded widget %s (awaiting claims)." % wid.get("dir")),
               "aliases": ["#%s-widget" % num]}
        rec["sources"] = [_src(ref or eid, inv, ["one_line", "aliases"], "harvest_v1", at)]
        put(rec)

    # core-docs (mechanical; one_line seeded from the DOC_PROTOCOL owner column when available)
    owners = {r["doc"]: r.get("owns") for r in harvest["doc_owner_rows"]}
    for cd in harvest["core_docs"]:
        path = cd["path"]
        name = os.path.basename(path)
        owns = owners.get(name)
        one = ("%s -- %s" % (name, owns)) if owns else ("Core doc %s." % name)
        put({"id": "doc:%s" % path, "ns": "doc", "display_name": name,
             "one_line": P._clip160(one),
             "sources": [_src(path, inv, ["one_line"], "harvest_v1", at)]})

    # arch positions (mechanical, number-only keys)
    arch_src = "core-docs/ARCHITECTURE_MAP.md"
    for a in harvest["arch"]:
        put({"id": "arch:%s" % a["num"], "ns": "arch",
             "display_name": a.get("display_name") or a["num"],
             "one_line": P._clip160(a.get("one_line") or ("Architecture position %s." % a["num"])),
             "aliases": ["pos %s" % a["num"]],
             "sources": [_src(arch_src, inv, ["one_line", "aliases"], "harvest_v1", at)]})

    # 5 fixed planes (structural constants; boundary decision recorded in the report)
    for p in P.PLANES:
        put({"id": "plane:%s" % p, "ns": "plane", "display_name": "%s plane" % p.title(),
             "one_line": P._clip160("The %s plane (D-0080 Collective-Agent planes)." % p.title()),
             "sources": [_src(arch_src, inv, ["one_line"], "harvest_v1", at)]})

    m.edges = []
    m.overlay = None
    P._write_map(m, map_dir)
    # generated/ ships EMPTY (+.gitkeep)
    gen = os.path.join(os.path.dirname(map_dir), "generated")
    os.makedirs(gen, exist_ok=True)
    P.write_lf(os.path.join(gen, ".gitkeep"), "")

    # self-check: validate the seed WITH harvest (Skeleton state must be clean)
    model = P.load_map(map_dir)
    vr = P.validate(model, harvest, is_real=True)
    ns = {}
    for rid in model.entities:
        k = rid.split(":", 1)[0]
        ns[k] = ns.get(k, 0) + 1
    print("seeded ns counts:", ns)
    print("validate findings:", len(vr["findings"]))
    for f in vr["findings"][:50]:
        print("  ", f["code"], f["where"], f["message"])
    return 0 if not vr["findings"] else 1


if __name__ == "__main__":
    repo = os.path.abspath(sys.argv[1])
    map_dir = os.path.abspath(sys.argv[2])
    sys.exit(seed(repo, map_dir))
