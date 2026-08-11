#!/usr/bin/env python3
# Stdlib-only SHAPE self-check for claims/i46-repo-claims.json (worker PCB-CLAIMS-i46).
# Checks: parses; required top/entity/source/edge fields present; ns + edge-type closed-set
# membership; id grammar; no dup ids. NOT the real WORK_ORDER s2 validator (Lane A's #44
# `validate` op also checks referential integrity/provenance-coverage/staleness). Exit 0/1.
import json, re, sys

NS = {"module","widget","plane","arch","contract","doc","store","decision",
      "mandate","pb","iteration","wave","ops","future"}
EDGE_TYPES = {"produces","consumes","invokes","routes-to","retrieves-from","compiles-for",
      "verifies","authorizes","audits","persists","supersedes","depends-on","governs",
      "realizes","documents"}
ID_RE = re.compile(r"^[a-z]+:[A-Za-z0-9._/-]+$")
SRC_FIELDS = ("ref", "sha256", "fields", "by", "at_commit")

def check(path):
    problems = []
    doc = json.load(open(path, "r", encoding="utf-8"))
    for k in ("schema", "by", "at_commit", "entities", "relationships"):
        if k not in doc:
            problems.append(f"top-level missing '{k}'")
    if doc.get("schema") != "lifeorch.map_claims/0.1":
        problems.append("schema != lifeorch.map_claims/0.1")
    ids = set()
    for e in doc.get("entities", []):
        eid = e.get("id")
        if not eid:
            problems.append("entity missing id"); continue
        if not ID_RE.match(eid):
            problems.append(f"{eid}: ID_GRAMMAR")
        if eid.split(":", 1)[0] not in NS:
            problems.append(f"{eid}: UNKNOWN_NS")
        if eid in ids:
            problems.append(f"{eid}: DUP_ID")
        ids.add(eid)
        if not e.get("sources"):
            problems.append(f"{eid}: missing/empty sources[]")
        for s in e.get("sources", []):
            problems += [f"{eid}: source missing '{sf}'" for sf in SRC_FIELDS if sf not in s]
    for r in doc.get("relationships", []):
        tag = f"{r.get('from')}->{r.get('to')}"
        problems += [f"edge {tag}: missing '{rf}'" for rf in ("from","type","to","sources") if rf not in r]
        if r.get("type") not in EDGE_TYPES:
            problems.append(f"edge {tag}: UNKNOWN_EDGE_TYPE {r.get('type')}")
        for s in r.get("sources", []):
            problems += [f"edge {tag}: source missing '{sf}'" for sf in SRC_FIELDS if sf not in s]
    return problems

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "claims/i46-repo-claims.json"
    try:
        problems = check(target)
    except Exception as ex:
        print(f"PARSE_FAILED: {ex}"); sys.exit(1)
    if problems:
        for p in problems:
            print(p)
        print(f"FAIL: {len(problems)} problem(s)"); sys.exit(1)
    print("SELFTEST_CLAIMS_SYNTAX_OK")
    sys.exit(0)
