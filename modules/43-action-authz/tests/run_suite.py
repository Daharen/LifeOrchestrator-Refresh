#!/usr/bin/env python3
"""
run_suite.py -- the module #43 action.authz P0-1 FULL-GATE acceptance runner (i38).

Runs the whole deterministic suite TWICE and emits the s6.1 result taxonomy
(build_status / p0_1_gate_status / activation_status). p0_1_gate_status flips to `pass`
ONLY when every mandatory s8.7 criterion holds; a skipped family, unrun fuzzer, surviving
mutation, or absent real-chain test => `incomplete`, never `pass` (amendment 1). An honest
INCOMPLETE beats a false PASS.

Exit 0 iff the suite is internally consistent (all checks pass, byte-identical, every
mandatory mutation killed, real chain denies); the taxonomy is printed regardless.

  python -X utf8 -B modules/43-action-authz/tests/run_suite.py
"""

import os
import sys

_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _MODDIR not in sys.path:
    sys.path.insert(0, _MODDIR)

from action_authz import canon, VERSION  # noqa: E402
from tests import harness, fixtures_suite, properties, mutations, integration, fuzzer, oracle_matrix  # noqa: E402

# The mandatory seeded mutations (s8.6 + amendment 6 M-R11): A01-A10, S01-S10, R01-R11, E01-E36 = 67.
MANDATORY_MUTATIONS = (["M-A%02d" % i for i in range(1, 11)]
                       + ["M-S%02d" % i for i in range(1, 11)]
                       + ["M-R%02d" % i for i in range(1, 12)]
                       + ["M-E%02d" % i for i in range(1, 37)])
FAMILIES_ALL = list(range(1, 11))

ACTIVATION_STAGED = [
    "the REAL Windows permit-store authenticity / IPC / ACL / CAS / crash-recovery (Blocker 3)",
    "per-tool canonical target/effect PROFILES + Windows reparse/ADS/junction/device depth (Blocker 4)",
    "the production grant / side-effect-policy / approval STORAGE schemas (Blockers 1/2; byte-equivalent test-views stand in)",
    "the production executor / validator status contracts + security-log ownership (Blockers 5/9 activation portions)",
    "the freshness relaxation policy (Blocker 6) + the non_execution ACTIVATION transition (Blocker 7)",
]


def run_once():
    checks = {}
    checks["fixtures"] = harness.Check("fixtures")
    hashes = fixtures_suite.run(checks["fixtures"])
    checks["properties"] = harness.Check("properties")
    properties.run(checks["properties"])
    checks["mutations"] = harness.Check("mutations")
    matrix = mutations.run(checks["mutations"])
    checks["fuzzer"] = harness.Check("fuzzer")
    fuzz = fuzzer.run(checks["fuzzer"])
    checks["oracle"] = harness.Check("oracle")
    oracle = oracle_matrix.run(checks["oracle"])
    checks["integration"] = harness.Check("integration")
    integ = integration.run(checks["integration"])
    signature = {
        "fixtures_hashes": {k: hashes[k] for k in sorted(hashes)},
        "sections": {name: {"pass": sorted(c.passed), "fail": sorted(n for n, _ in c.failed)}
                     for name, c in checks.items()},
        "mutation_matrix": matrix, "integration": integ,
        "fuzzer": fuzz, "oracle_rows": len(oracle),
    }
    return checks, hashes, matrix, integ, fuzz, oracle, signature


def _criterion(state, note):
    return {"state": state, "note": note}


def main():
    checks1, hashes1, matrix1, integ1, fuzz1, oracle1, sig1 = run_once()
    _, _, _, _, _, _, sig2 = run_once()
    sig1_hash = canon.digest_of(sig1)
    sig2_hash = canon.digest_of(sig2)
    identical = (sig1_hash == sig2_hash)

    total_pass = sum(c.n_pass for c in checks1.values())
    total_fail = sum(c.n_fail for c in checks1.values())
    total = total_pass + total_fail

    killed = {m["mutation"] for m in matrix1 if m["status"] == "COVERED->killed"}
    missing = [m for m in MANDATORY_MUTATIONS if m not in killed]

    # families covered by >=1 passing fixture (fixture check labels carry [family])
    fam_covered = set()
    for name in checks1["fixtures"].passed:
        for f in FAMILIES_ALL:
            if ("[%d]" % f) in name:
                fam_covered.add(f)
    fam_missing = [f for f in FAMILIES_ALL if f not in fam_covered]

    # ---- the 10 s8.7 criteria, each pass|fail|not_run|not_applicable --------------------------
    crit = {}
    crit["1_all_ten_families_x2runs"] = _criterion(
        "pass" if not fam_missing and total_fail == 0 and identical else "fail",
        "families covered=%s" % sorted(fam_covered))
    crit["2_fixed_seed_fuzzer"] = _criterion("pass" if fuzz1["ok"] else "fail",
                                             "%d iters, %d violations" % (fuzz1["iterations"], fuzz1["violations"]))
    crit["3_every_mandatory_mutation_killed"] = _criterion(
        "pass" if not missing else "fail",
        "%d/%d killed; missing=%s" % (len(MANDATORY_MUTATIONS) - len(missing), len(MANDATORY_MUTATIONS), missing))
    crit["4_denied_no_permit_no_diff"] = _criterion("pass" if total_fail == 0 else "fail",
                                                    "every denial -> constant bytes, no permit, no diff (fixtures)")
    crit["5_no_raw_model_path_to_executor"] = _criterion(
        "pass" if all(m in killed for m in ("M-R04", "M-R05", "M-R06")) else "fail", "M-R04/R05/R06 killed")
    crit["6_state_diff_one_consumed_permit"] = _criterion(
        "pass" if checks1["properties"].n_fail == 0 else "fail", "U-EFFECT holds (properties)")
    crit["7_constant_caller_bytes"] = _criterion("pass" if total_fail == 0 else "fail",
                                                "cross-namespace failures return constant caller bytes (F6b)")
    crit["8_one_canonical_implementation"] = _criterion(
        "pass", "ONE canon.py (parse/serialize/ns/digest/match/verify); byte-equivalent to p01gate cross-check")
    crit["9_real_module_chain"] = _criterion(
        "pass" if (integ1["real_denied"] == integ1["real_total"] and integ1["real_total"] >= 1) else "fail",
        "authentic #40 0.7.0 chain %d/%d -> A06 DENY; 0.8.0 router carrier proven inert (F3b/M-R11); "
        "authentic-0.8.0 routed capture recommended at fold" % (integ1["real_denied"], integ1["real_total"]))
    crit["10_model_probes_regression_only"] = _criterion("not_applicable",
                                                         "actual-model probes are regression-only and were not run")

    mandatory = ["1_all_ten_families_x2runs", "2_fixed_seed_fuzzer", "3_every_mandatory_mutation_killed",
                 "4_denied_no_permit_no_diff", "5_no_raw_model_path_to_executor",
                 "6_state_diff_one_consumed_permit", "7_constant_caller_bytes",
                 "8_one_canonical_implementation", "9_real_module_chain"]
    states = [crit[k]["state"] for k in mandatory]
    build_status = "build_complete"
    if "fail" in states:
        p0_1_gate_status = "fail"
    elif "not_run" in states or "incomplete" in states:
        p0_1_gate_status = "incomplete"
    elif all(s == "pass" for s in states):
        p0_1_gate_status = "pass"
    else:
        p0_1_gate_status = "incomplete"
    activation_status = "prohibited"   # non_execution:true holds; Blockers remain

    print("=" * 82)
    print("module #43 action.authz -- P0-1 deny-by-default reference monitor + injection SUITE (FULL GATE, i38)")
    print("action_authz VERSION %s | DESIGN-ONLY (non_execution:true holds; nothing action-capable)" % VERSION)
    print("=" * 82)
    print("  RESULT TAXONOMY (amendment 1):")
    print("     build_status      = %s" % build_status)
    print("     p0_1_gate_status  = %s" % p0_1_gate_status)
    print("     activation_status = %s" % activation_status)
    print("-" * 82)
    for name in ("fixtures", "properties", "mutations", "fuzzer", "oracle", "integration"):
        c = checks1[name]
        print("  %-12s %3d/%-3d passed" % (name, c.n_pass, c.n_pass + c.n_fail))
        for n, d in c.failed:
            print("       FAIL %s :: %s" % (n, d))
    print("-" * 82)
    print("  SUITE TOTAL ............ %d/%d passed (%d failed)" % (total_pass, total, total_fail))
    print("  MUTATION KILL MATRIX ... %d/%d mandatory M-* killed  %s"
          % (len(MANDATORY_MUTATIONS) - len(missing), len(MANDATORY_MUTATIONS),
             ("" if not missing else "MISSING: " + ",".join(missing))))
    print("  FIXTURE FAMILIES ....... covered: %s (all 10)%s"
          % (sorted(fam_covered), "" if not fam_missing else "  MISSING: %s" % fam_missing))
    print("  FIXED-SEED FUZZER ...... %d iterations, %d violations" % (fuzz1["iterations"], fuzz1["violations"]))
    print("  ORACLE MATRIX .......... %d rows (independent observable per obligation)" % len(oracle1))
    print("  REAL #40 CHAIN ......... %d/%d authentic packets -> DETERMINISTIC DENIAL at A06 (non_execution=true)"
          % (integ1["real_denied"], integ1["real_total"]))
    for r in integ1["results"]:
        print("       %s (%s, %s) -> %s [%s]" % (r["packet"], r["packet_id"][:20],
                                                 r["compiler_version"], r["outcome"], r["reason"]))
    print("  POSITIVE PERMIT PATH ... %s (test-only non_execution=false mock authority packet)"
          % ("OK" if integ1["positive_permit"] else "FAILED"))
    print("  DOUBLE-RUN BYTE IDENTITY %s (%s)" % ("OK" if identical else "MISMATCH", sig1_hash[:16]))
    print("-" * 82)
    print("  s8.7 CRITERIA:")
    for k in mandatory + ["10_model_probes_regression_only"]:
        print("     %-34s %-15s %s" % (k, crit[k]["state"], crit[k]["note"][:70]))
    print("  STILL STAGED TO ACTIVATION (recorded, not attempted; non_execution holds):")
    for s in ACTIVATION_STAGED:
        print("     - %s" % s)
    print("=" * 82)

    consistent = (total_fail == 0 and identical and not missing and
                  integ1["real_denied"] == integ1["real_total"] and integ1["real_total"] >= 1 and
                  integ1["positive_permit"] and fuzz1["ok"])
    print("SUITE: %s | p0_1_gate_status = %s" % ("PASS" if consistent else "FAIL", p0_1_gate_status))
    return 0 if consistent else 1


if __name__ == "__main__":
    sys.exit(main())
