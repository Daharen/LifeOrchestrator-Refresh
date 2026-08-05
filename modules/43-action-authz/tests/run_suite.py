#!/usr/bin/env python3
"""
run_suite.py -- the module #43 action.authz P0-1 MVP acceptance runner.

Runs the whole deterministic suite TWICE and gates on:
  - all checks pass (NN/NN across fixtures + universal properties + mutation kills + real integration);
  - every mandatory seeded mutation M-A01..M-E36 is KILLED;
  - every real #40 0.7.0 packet is deterministically DENIED (A06, non_execution=true);
  - the two runs are BYTE-IDENTICAL (identical property results + canonical fixture hashes + kill matrix).

Exit 0 iff the gate passes; exit 1 otherwise. STANDARD-LIBRARY ONLY; deterministic.

  python -X utf8 -B modules/43-action-authz/tests/run_suite.py
"""

import os
import sys

_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _MODDIR not in sys.path:
    sys.path.insert(0, _MODDIR)

from action_authz import canon, VERSION  # noqa: E402
from tests import harness, fixtures_suite, properties, mutations, integration  # noqa: E402

STAGED_TO_I38 = [
    "the full 10-family fixture corpus (families 3,4,5,8 + the remainder of 1,2,6,7,9)",
    "the fixed-seed mutational FUZZER (s8.7 crit 2)",
    "per-tool canonical target/effect PROFILES + Windows reparse/ADS/junction/device depth (Blocker 4)",
    "the REAL Windows permit-store authenticity / IPC / ACL / CAS / crash-recovery (Blocker 3)",
    "the grant / side-effect-policy / approval SCHEMAS (Blockers 1/2; MVP uses GrantView/PolicyView + approval fixtures)",
    "the executor / validator status contracts (Blocker 5) + production security-log contract (Blocker 9)",
]
FAMILIES_COVERED = "10 (PRIMARY) + representative 1, 2, 6, 7, 9"
FAMILIES_STAGED = "3, 4, 5, 8 + the full corpus of 1/2/6/7/9"


def run_once():
    checks = {}
    checks["fixtures"] = harness.Check("fixtures")
    hashes = fixtures_suite.run(checks["fixtures"])
    checks["properties"] = harness.Check("properties")
    properties.run(checks["properties"])
    checks["mutations"] = harness.Check("mutations")
    matrix = mutations.run(checks["mutations"])
    checks["integration"] = harness.Check("integration")
    integ = integration.run(checks["integration"])
    signature = {
        "fixtures_hashes": {k: hashes[k] for k in sorted(hashes)},
        "sections": {name: {"pass": sorted(c.passed), "fail": sorted(n for n, _ in c.failed)}
                     for name, c in checks.items()},
        "mutation_matrix": matrix,
        "integration": integ,
    }
    return checks, hashes, matrix, integ, signature


def main():
    checks1, hashes1, matrix1, integ1, sig1 = run_once()
    _, _, _, _, sig2 = run_once()
    sig1_hash = canon.digest_of(sig1)
    sig2_hash = canon.digest_of(sig2)
    identical = (sig1_hash == sig2_hash)

    total_pass = sum(c.n_pass for c in checks1.values())
    total_fail = sum(c.n_fail for c in checks1.values())
    total = total_pass + total_fail

    killed = sum(1 for m in matrix1 if m["status"] == "COVERED->killed")
    not_killed = [m["mutation"] for m in matrix1 if m["status"] != "COVERED->killed"]
    depth_staged = [m["mutation"] for m in matrix1 if m.get("depth_staged")]

    print("=" * 78)
    print("module #43 action.authz -- P0-1 deny-by-default reference monitor + injection SUITE (MVP)")
    print("worker P01-AUTHZ-SUITE-i37 | action_authz VERSION %s | DESIGN-ONLY (non_execution holds)" % VERSION)
    print("=" * 78)
    for name in ("fixtures", "properties", "mutations", "integration"):
        c = checks1[name]
        print("  %-12s %3d/%-3d passed" % (name, c.n_pass, c.n_pass + c.n_fail))
        for n, d in c.failed:
            print("       FAIL %s :: %s" % (n, d))
    print("-" * 78)
    print("  SUITE TOTAL ............ %d/%d passed (%d failed)" % (total_pass, total, total_fail))
    print("  MUTATION KILL MATRIX ... %d/%d killed  %s" %
          (killed, len(matrix1), ("" if not not_killed else "NOT KILLED: " + ",".join(not_killed))))
    print("     depth-staged to i38 (killed at MVP level; production OS/IPC enforcement deferred): %s"
          % (", ".join(depth_staged) if depth_staged else "none"))
    print("  FIXTURE FAMILIES ....... covered: %s | staged->i38: %s" % (FAMILIES_COVERED, FAMILIES_STAGED))
    print("  REAL #40 0.7.0 CHAIN ... %d/%d authentic packets -> DETERMINISTIC DENIAL at A06 (non_execution=true)"
          % (integ1["real_denied"], integ1["real_total"]))
    for r in integ1["results"]:
        print("       %s (%s, %s) -> %s [%s]" % (r["packet"], r["packet_id"][:20],
                                                 r["compiler_version"], r["outcome"], r["reason"]))
    print("  POSITIVE PERMIT PATH ... %s (test-only non_execution=false mock authority packet)"
          % ("OK" if integ1["positive_permit"] else "FAILED"))
    print("  DOUBLE-RUN BYTE IDENTITY %s" % ("OK" if identical else "MISMATCH"))
    print("     run1 signature sha256 = %s" % sig1_hash)
    print("     run2 signature sha256 = %s" % sig2_hash)
    print("  STAGED TO i38:")
    for s in STAGED_TO_I38:
        print("     - %s" % s)
    print("=" * 78)

    ok = (total_fail == 0 and identical and not not_killed and
          integ1["real_denied"] == integ1["real_total"] and integ1["real_total"] >= 1 and
          integ1["positive_permit"])
    print("RESULT: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
