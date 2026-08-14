#!/usr/bin/env python3
"""reaffirm_batch.py -- N7 close-refold currency restamps in ONE process (D-0147 follow-on).

The per-entity subprocess reaffirm loop in ops/close-refold.ps1 raced ACROSS PROCESSES on the
whole-file map writes: a later reaffirm subprocess reloaded a stale meta.json (missing the prior
write) and clobbered earlier restamps, so most restamps silently did not persist (only load-bearing
stragglers surfaced via STALE_LOAD_BEARING at validate). This driver applies the orchestrator-reviewed
reaffirm spec in a SINGLE process -- synchronous in-process load/write accumulates correctly -- reusing
project_map.op_reaffirm UNCHANGED (no edit to the tested map functions).

Usage:
  reaffirm_batch.py --map <map_dir> --harvest <harvest.json> --spec <spec.json> --by <s> --at-commit <sha>
    spec.json = [{"entity":"<id>","fields":"<csv>"}, ...]   (the reviewed judgment list)
Prints a JSON envelope to stdout; exit 0 on success, 1 on any refusal/crash (fail-closed).
"""
import argparse, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import project_map as pm


def main():
    ap = argparse.ArgumentParser(prog="reaffirm_batch.py")
    ap.add_argument("--map", required=True)
    ap.add_argument("--harvest", required=True)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--by", default="orchestrator-close")
    ap.add_argument("--at-commit", dest="at_commit", required=True)
    a = ap.parse_args()
    harvest = pm._load_harvest(a.harvest)
    spec = json.loads(pm.read_text(a.spec))
    if not isinstance(spec, list):
        print(json.dumps({"status": "error", "error": {"code": "SCHEMA_INVALID", "message": "spec must be a JSON array"}}))
        return 1
    reaffirmed = []
    total = 0
    for r in spec:
        if not isinstance(r, dict) or not r.get("entity") or not r.get("fields"):
            print(json.dumps({"status": "error", "error": {"code": "SCHEMA_INVALID", "message": "each spec entry needs entity+fields: %r" % (r,)}}))
            return 1
        eid, flds = r["entity"], r["fields"]
        try:
            res = pm.op_reaffirm(a.map, eid, flds, a.by, a.at_commit, harvest)
        except pm.Refuse as e:
            print(json.dumps({"status": "error", "error": {"code": e.code, "message": e.message, "entity": eid}}))
            return 1
        n = res.get("sources_restamped", 0)
        reaffirmed.append({"entity": eid, "fields": flds, "sources_restamped": n})
        total += n
    print(json.dumps({"status": "ok", "result": {"reaffirmed": reaffirmed, "count": len(reaffirmed), "total_sources_restamped": total}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
