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
from tests import (harness, fixtures_suite, properties, mutations, integration, fuzzer,  # noqa: E402
                   oracle_matrix, role_matrix, completion_binding, p01gate, views_golden, report)

# The mandatory seeded mutations (s8.6 + amendment 6 M-R11 + i41 round-3 Finding 2 M-E37):
# A01-A10, S01-S10, R01-R11, E01-E37 = 68.
MANDATORY_MUTATIONS = (["M-A%02d" % i for i in range(1, 11)]
                       + ["M-S%02d" % i for i in range(1, 11)]
                       + ["M-R%02d" % i for i in range(1, 12)]
                       + ["M-E%02d" % i for i in range(1, 38)])
FAMILIES_ALL = list(range(1, 11))

ACTIVATION_STAGED = [
    "the REAL Windows permit-store authenticity / IPC / ACL / CAS / crash-recovery (Blocker 3)",
    "per-tool canonical target/effect PROFILES + Windows reparse/ADS/junction/device depth (Blocker 4)",
    "the production grant / side-effect-policy / approval STORAGE schemas (Blockers 1/2; byte-equivalent test-views stand in)",
    "the production executor / validator status contracts + security-log ownership (Blockers 5/9 activation portions)",
    "the freshness relaxation policy (Blocker 6) + the non_execution ACTIVATION transition (Blocker 7)",
]

# i40 Finding 7 -- the COMPLETE independently-runnable review tree. run_suite verifies every required
# file is present on disk (pack completeness); tests/selfverify.py performs the EMPTY-DIR reproduction.
REVIEW_PACK_FILES = [
    "action_authz/__init__.py", "action_authz/canon.py", "action_authz/schemas.py",
    "action_authz/stores.py", "action_authz/monitor.py", "action_authz/boundary.py",
    "tests/__init__.py", "tests/harness.py", "tests/fixtures_suite.py", "tests/properties.py",
    "tests/mutations.py", "tests/integration.py", "tests/adapter_090.py", "tests/fuzzer.py",
    "tests/oracle_matrix.py", "tests/callgraph.py", "tests/render.py", "tests/role_matrix.py",
    "tests/completion_binding.py", "tests/views_golden.py", "tests/p01gate.py", "tests/report.py",
    "tests/run_suite.py", "tests/selfverify.py",
    "fixtures/real_packets/m40_070_pkt_0.json", "fixtures/real_packets/m40_070_pkt_1.json",
    "fixtures/real_packets/m40_070_pkt_2.json", "fixtures/real_packets/m40_070_pkt_3.json",
    "fixtures/real_packets/m40_090_routed.json", "fixtures/real_packets/m40_090_routed_adv.json",
    "fixtures/real_packets/m40_090_flat.json", "fixtures/real_packets/PROVENANCE.md",
    "SCHEMA_NOTES.md", "README.md", "WORK_ORDER.md",
]


def _review_pack_complete():
    """True + [] iff every file the runnable review tree needs is present on disk (Finding 7)."""
    missing = [f for f in REVIEW_PACK_FILES
               if not os.path.exists(os.path.join(_MODDIR, f.replace("/", os.sep)))]
    return (not missing), missing


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
    checks["role"] = harness.Check("role")
    role = role_matrix.run(checks["role"])
    checks["completion"] = harness.Check("completion")
    completion = completion_binding.run(checks["completion"])
    checks["views"] = harness.Check("views")
    views = views_golden.run(checks["views"])
    checks["p01gate"] = harness.Check("p01gate")
    p01 = p01gate.run(checks["p01gate"])
    checks["integration"] = harness.Check("integration")
    integ = integration.run(checks["integration"])
    signature = {
        "fixtures_hashes": {k: hashes[k] for k in sorted(hashes)},
        "sections": {name: {"pass": sorted(c.passed), "fail": sorted(n for n, _ in c.failed)}
                     for name, c in checks.items()},
        "mutation_matrix": matrix, "integration": integ, "fuzzer": fuzz,
        "oracle_rows": len(oracle), "oracle_digest": canon.digest_of(oracle),
        "role_matrix": role, "p01gate": p01["byte_equivalent"], "views": views["view_digests"],
    }
    return checks, hashes, matrix, integ, fuzz, oracle, role, completion, p01, views, signature


def _criterion(state, note):
    return {"state": state, "note": note}


def main():
    checks1, hashes1, matrix1, integ1, fuzz1, oracle1, role1, completion1, p011, views1, sig1 = run_once()
    _, _, _, _, _, _, _, _, _, _, sig2 = run_once()
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
    # ---- the i39 gating additions (red-team Findings 1-7) -------------------------------------
    oracle_not_run = [r["obligation_id"] for r in oracle1 if r.get("status") == "not_run"]
    oracle_failed = [r["obligation_id"] for r in oracle1 if r.get("status") == "fail"]
    oracle_complete = (not oracle_not_run) and (not oracle_failed) and checks1["oracle"].n_fail == 0
    role_killed = sum(1 for r in role1 if r["status"] == "killed")
    role_all = (checks1["role"].n_fail == 0 and role_killed == len(role1) and len(role1) > 0)
    completion_ok = checks1["completion"].n_fail == 0
    views_ok = checks1["views"].n_fail == 0
    p01_ok = checks1["p01gate"].n_fail == 0 and bool(p011["byte_equivalent"])
    v090_ok = bool(integ1.get("v090_test_only_permit") and integ1.get("v090_adversarial_identical"))

    crit["8_one_canonical_implementation"] = _criterion(
        "pass" if p01_ok else "fail",
        "ONE canon.py cross-validated BYTE-EQUIVALENT to the INDEPENDENT blind p01gate over %d vectors "
        "(shipped in the bundle)" % p011["corpus_vectors"])
    crit["9_real_module_chain"] = _criterion(
        "pass" if (integ1["real_denied"] == integ1["real_total"] and integ1["real_total"] >= 1 and v090_ok) else "fail",
        "authentic #40 0.7.0+0.9.0 chain %d/%d -> A06 DENY; the 0.9.0 routed+wm test-only variant REACHES "
        "A09/A11/A30/A31; adversarial cad-identical" % (integ1["real_denied"], integ1["real_total"]))
    crit["10_model_probes_regression_only"] = _criterion("not_applicable",
                                                         "actual-model probes are regression-only and were not run")
    crit["11_obligation_oracle_complete"] = _criterion(
        "pass" if oracle_complete else ("incomplete" if oracle_not_run else "fail"),
        "%d obligation rows (A01-A36 + Boundary A/B/C/D + U-properties + mutations); not_run=%s failed=%s"
        % (len(oracle1), oracle_not_run, oracle_failed))
    crit["12_role_sink_matrix"] = _criterion(
        "pass" if role_all else "fail",
        "R1-ROLE-1 sink matrix %d/%d (carrier x sink) killed under non_execution=false" % (role_killed, len(role1)))
    crit["13_completion_packet_binding"] = _criterion(
        "pass" if completion_ok else "fail",
        "completion binds via the immutable packet_id + per-leaf minimum-scope; every substitution -> indeterminate")
    crit["14_v090_authentic_chain_in_suite"] = _criterion(
        "pass" if v090_ok else "fail",
        "the #40 0.9.0 routed+wm authentic chain is OWNED + RUN inside the suite gate (both modes)")
    v090_exact = bool(integ1.get("v090_exact_adapter") and integ1.get("v090_a07_exercised"))
    crit["15_exact_090_adapter"] = _criterion(
        "pass" if v090_exact else "fail",
        "the suite-owned EXACT context_packet/0.2 adapter preserves corpus_version (A07 exercised) + "
        "grant-snapshot identity + full carriers; carriers INERT at every R1 sink")

    # ---- i40 Finding closures -> per-finding exact_closure_built flags (the WORKER's claim carrier) --
    def _rows_ok(pred):
        return all(r.get("status") == "pass" for r in oracle1 if pred(r["obligation_id"]))
    from tests import callgraph
    bd_ok = _rows_ok(lambda oid: str(oid).startswith("Boundary-D3"))
    f6_ids = {"U-ROLE", "A36-emission", "A36-corruption", "Boundary-B1", "Boundary-B2",
              "Boundary-B3", "Boundary-B4"}
    f6_rows_ok = _rows_ok(lambda oid: oid in f6_ids)
    no_path_ok = callgraph.no_path(_MODDIR)
    pack_complete, pack_missing = _review_pack_complete()
    exact_closure_built = {
        "finding_1": bool(completion_ok),                         # completion IMMUTABLE at issue
        "finding_2": bool(bd_ok and oracle_complete),             # Boundary-D post-claim (terminal + 2nd)
        "finding_3": bool(role_all and len(role1) == 30),         # 15-sink x 2-carrier role matrix
        "finding_4": bool(views_ok),                              # GrantView limit algebra + pinned
        "finding_5": bool(v090_exact),                            # exact context_packet/0.2 adapter
        "finding_6": bool(f6_rows_ok and no_path_ok and oracle_complete),  # decisive oracles
        "finding_7": bool(pack_complete),                         # complete runnable review tree
    }

    # === i41 round-3 (D-0113) -- the 4 WORKER-SIDE exact closures from the round-3 ratification review.
    # Machine-readable, alongside the D-0109 exact_closure_built flags (which ALL stay true; no regression).
    # These CARRY the round-3 claim; the gate still stays `incomplete` (M2-D) -- the orchestrator's
    # independent round-4 re-review PASS is the only ratification path.
    handle_consumed_ok = _rows_ok(lambda oid: oid == "Boundary-D3:D4_handle_consumed")
    round3_closure_built = {
        "f1_write_once_binding": bool(completion_ok and completion1.get("round3_f1_write_once_binding")),
        "f2_consumed_target_handle": bool("M-E37" in killed and handle_consumed_ok and oracle_complete),
        "f4_toplevel_grantview": bool(views_ok and views1.get("round3_f4_toplevel_grantview")),
        "f5_lossless_adapter": bool(integ1.get("v090_lossless_adapter")),
    }

    # === M2-D / D-0110 (NON-NEGOTIABLE): the WORKER never claims pass. `p0_1_gate_status` stays =====
    # `incomplete` in EVERY emitted artifact -- the independent as-built RE-REVIEW's PASS (couriered by
    # the orchestrator at fold) is the ONLY path to ratification. An honest incomplete-with-evidence,
    # carried by the exact_closure_built flags + the suite evidence, IS the deliverable.
    build_status = "build_complete"
    p0_1_gate_status = "incomplete"
    activation_status = "prohibited"   # non_execution:true holds; Blockers remain

    # the criteria are still evaluated (evidence for the re-review), but they do NOT flip the gate.
    mandatory = ["1_all_ten_families_x2runs", "2_fixed_seed_fuzzer", "3_every_mandatory_mutation_killed",
                 "4_denied_no_permit_no_diff", "5_no_raw_model_path_to_executor",
                 "6_state_diff_one_consumed_permit", "7_constant_caller_bytes",
                 "8_one_canonical_implementation", "9_real_module_chain",
                 "11_obligation_oracle_complete", "12_role_sink_matrix",
                 "13_completion_packet_binding", "14_v090_authentic_chain_in_suite",
                 "15_exact_090_adapter"]

    print("=" * 82)
    print("module #43 action.authz -- P0-1 deny-by-default reference monitor + injection SUITE (i41 ROUND-3 CLOSURES)")
    print("action_authz VERSION %s | DESIGN-ONLY (non_execution:true holds; nothing action-capable)" % VERSION)
    print("=" * 82)
    print("  RESULT TAXONOMY (amendment 1; M2-D / D-0110 -- the worker does NOT claim pass):")
    print("     build_status      = %s" % build_status)
    print("     p0_1_gate_status  = %s   (PINNED; the independent as-built re-review PASS ratifies)" % p0_1_gate_status)
    print("     activation_status = %s" % activation_status)
    print("  EXACT CLOSURES BUILT (i39 findings 1-7; the worker's machine-readable claim):")
    for i in range(1, 8):
        k = "finding_%d" % i
        print("     %-11s exact_closure_built = %s" % (k, exact_closure_built[k]))
    if not pack_complete:
        print("     (review pack missing: %s)" % pack_missing)
    print("  ROUND-3 CLOSURES BUILT (i41 / D-0113; the 4 worker-side round-3 exact closures):")
    for k in ("f1_write_once_binding", "f2_consumed_target_handle", "f4_toplevel_grantview",
              "f5_lossless_adapter"):
        print("     %-26s round3_closure_built = %s" % (k, round3_closure_built[k]))
    print("-" * 82)
    for name in ("fixtures", "properties", "mutations", "fuzzer", "oracle", "role", "completion",
                 "views", "p01gate", "integration"):
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
    print("  OBLIGATION ORACLE ...... %d rows, all executed pass|fail|not_run (not_run=%d): A01-A36 + "
          "Boundary A/B/C/D + U-properties + mutations" % (len(oracle1), len(oracle_not_run)))
    print("  R1-ROLE-1 SINK MATRIX .. %d/%d (carrier x sink) killed under non_execution=false"
          % (role_killed, len(role1)))
    print("  COMPLETION BINDING ..... packet_id-bound + per-leaf min-scope; %d/%d substitution checks pass"
          % (checks1["completion"].n_pass, checks1["completion"].n_pass + checks1["completion"].n_fail))
    print("  BYTE-EXACT VIEWS ....... %d/%d golden vectors pass; the 5 test-view specs pinned by digest"
          % (checks1["views"].n_pass, checks1["views"].n_pass + checks1["views"].n_fail))
    print("  INDEPENDENT p01gate .... byte-equivalent=%s over %d vectors (Blocker-8 differential, shipped)"
          % (p011["byte_equivalent"], p011["corpus_vectors"]))
    print("  REAL #40 CHAIN ......... %d/%d authentic packets -> DETERMINISTIC DENIAL at A06 (non_execution=true)"
          % (integ1["real_denied"], integ1["real_total"]))
    for r in integ1["results"]:
        print("       %s (%s, %s) -> %s [%s]" % (r["packet"], r["packet_id"][:20],
                                                 r["compiler_version"], r["outcome"], r["reason"]))
    print("  0.9.0 TEST-ONLY CHAIN .. permit reaches A09/A11/A30/A31=%s ; adversarial cad-identical=%s"
          % (integ1.get("v090_test_only_permit"), integ1.get("v090_adversarial_identical")))
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

    all_round3 = all(round3_closure_built.values())
    consistent = (total_fail == 0 and identical and not missing and
                  integ1["real_denied"] == integ1["real_total"] and integ1["real_total"] >= 1 and
                  integ1["positive_permit"] and fuzz1["ok"] and oracle_complete and role_all and
                  completion_ok and p01_ok and v090_ok and v090_exact and views_ok and pack_complete and
                  all_round3)

    # ---- independently-auditable evidence bundle (red-team Finding 7) ------------------------
    payload = {
        "taxonomy": {"build_status": build_status, "p0_1_gate_status": p0_1_gate_status,
                     "activation_status": activation_status},
        "exact_closure_built": exact_closure_built,
        "round3_closure_built": round3_closure_built,
        "gate_status_rule": "M2-D/D-0110: worker emits incomplete-with-evidence; the independent "
                            "as-built re-review PASS (orchestrator, at fold) is the only ratification path",
        "criteria": crit,
        "double_run": {"identical": identical, "signature_sha256": sig1_hash},
        "totals": {"pass": total_pass, "fail": total_fail},
        "sections": {name: {"pass": c.n_pass, "fail": c.n_fail} for name, c in sorted(checks1.items())},
        "mutation_kill": {"killed": len(MANDATORY_MUTATIONS) - len(missing),
                          "total": len(MANDATORY_MUTATIONS), "missing": missing},
        "families_covered": sorted(fam_covered),
        "fuzzer": fuzz1, "integration_summary": {k: integ1[k] for k in sorted(integ1) if k != "results"},
        "integration_results": integ1["results"], "role_matrix": role1, "role_killed": role_killed,
        "completion_binding": completion1, "p01gate": p011, "views": views1,
        "oracle": {"rows": len(oracle1), "not_run": oracle_not_run, "failed": oracle_failed},
        "activation_staged": ACTIVATION_STAGED, "consistent": consistent,
    }
    manifest = report.write_bundle(payload, oracle1)
    print("  EVIDENCE BUNDLE ........ tests/report/ (%d files; bundle_digest %s)"
          % (len(manifest["files"]), manifest["bundle_digest"][:16]))
    print("=" * 82)
    all_built = all(exact_closure_built.values())
    print("SUITE: %s | build_complete | p0_1_gate_status = %s | activation=prohibited"
          % ("consistent" if consistent else "INCONSISTENT", p0_1_gate_status))
    print("EXACT CLOSURES: %d/7 built (i39) + %d/4 round-3 built (i41)%s | activation prohibited | "
          "ratification awaits the independent round-4 re-review PASS (M2-D)"
          % (sum(exact_closure_built.values()), sum(round3_closure_built.values()),
             "" if (all_built and all_round3) else " (INCOMPLETE)"))
    return 0 if (consistent and all_built and all_round3) else 1


if __name__ == "__main__":
    sys.exit(main())
