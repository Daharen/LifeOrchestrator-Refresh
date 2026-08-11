#!/usr/bin/env python3
# -*- coding: ascii -*-
"""project.map -Live full-repo smoke (WO s6.8). Runs on the mount VM (Python 3.10) or the box.
Usage: python3 tests/live_smoke.py <repo-root> <Skeleton|Folded>

Harvests the REAL repo, checks the counts-sanity floors, validates the committed map/ WITH harvest,
and asserts the coverage invariant (0 HARVEST_ORPHAN + 0 ENTITY_UNBACKED). The pass/fail expectation
is a PARAMETER (RepoState), not wall-clock guesswork (RT1-F11):
  Skeleton -> validate clean AND skeletons may remain (render would refuse SKELETON_UNRESOLVED).
  Folded   -> validate clean AND no skeletons remain AND non-draft render succeeds.
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
sys.path.insert(0, MOD)
import project_map as P  # noqa: E402


def main():
    repo = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.abspath(os.path.join(MOD, "..", ".."))
    state = sys.argv[2] if len(sys.argv) > 2 else "Skeleton"
    map_dir = os.path.join(MOD, "map")
    fails = []

    harvest = P.op_harvest(repo, "live-smoke", False)
    c = harvest["counts"]
    print("harvest counts:", json.dumps(c))
    checks = [
        ("modules>=45", c["modules"] >= 45),
        ("has-00.1", any(m.get("num") == "00.1" for m in harvest["modules"])),
        ("widgets==8", c["widgets"] == 8),
        ("core_docs>=20", c["core_docs"] >= 20),
        ("arch covers 0..49", any(a["num"] == "0" for a in harvest["arch"]) and any(a["num"] == "49" for a in harvest["arch"])),
    ]
    for nm, ok in checks:
        print(("  OK " if ok else "  XX "), nm)
        if not ok:
            fails.append(nm)

    model = P.load_map(map_dir)
    vr = P.validate(model, harvest, is_real=True)
    orphans = [f for f in vr["findings"] if f["code"] == "HARVEST_ORPHAN"]
    unbacked = [f for f in vr["findings"] if f["code"] == "ENTITY_UNBACKED"]
    other = [f for f in vr["findings"] if f["code"] not in ("HARVEST_ORPHAN", "ENTITY_UNBACKED")]
    print("validate: %d findings (orphans=%d unbacked=%d other=%d)"
          % (len(vr["findings"]), len(orphans), len(unbacked), len(other)))
    for f in vr["findings"][:40]:
        print("   ", f["code"], f["where"])
    if orphans:
        fails.append("HARVEST_ORPHAN(%d)" % len(orphans))
    if unbacked:
        fails.append("ENTITY_UNBACKED(%d)" % len(unbacked))
    if other:
        fails.append("validate-other(%d)" % len(other))

    skels = [rid for rid, r in model.entities.items() if r.get("skeleton")]
    if state == "Skeleton":
        print("Skeleton state: %d skeleton entities remain (expected, render would refuse)" % len(skels))
    elif state == "Folded":
        if skels:
            fails.append("Folded-but-%d-skeletons" % len(skels))
        try:
            out = tempfile.mkdtemp(prefix="pm-live-")
            res = P.op_render(map_dir, harvest, out, check=False, draft=False)
            print("Folded render OK: BOOT_PACKET=%d B ladder=%s" % (res["boot_packet_bytes"], res["ladder"]))
        except P.Refuse as r:
            fails.append("Folded-render-refused:%s" % r.code)

    print("counts-by-ns entities:", json.dumps(_ns_counts(model.entities)))
    if fails:
        print("LIVE SMOKE FAIL:", fails)
        return 1
    print("LIVE SMOKE GREEN (state=%s)" % state)
    return 0


def _ns_counts(ents):
    out = {}
    for rid in ents:
        ns = rid.split(":", 1)[0]
        out[ns] = out.get(ns, 0) + 1
    return out


if __name__ == "__main__":
    sys.exit(main())
