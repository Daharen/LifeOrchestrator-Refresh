#!/usr/bin/env python
# test_decision_intel.py -- off-machine (cloud pre-ship gate) determinism/coverage/validator harness for
# decision.intel. Drives the REAL worker (decision_intel.py) against the REAL core-docs/DECISION_LOG.md +
# DECISION_LOG_INDEX.md (no synthetic fixture -- the real corpus IS the acceptance surface at this scale,
#149 decisions). stdlib only. Exit 0 = all assertions passed; prints a PASS/FAIL line per assertion.
#
# Usage:
#   python3 test_decision_intel.py [decision_log_path] [decision_log_index_path]
# Defaults (relative to this file): ../../../core-docs/DECISION_LOG.md (repo layout:
# modules/45-decision-intel/tests/test_decision_intel.py -> core-docs/ is three levels up).
import sys, os, json, shutil, tempfile, subprocess, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_DIR = os.path.dirname(HERE)
WORKER = os.path.join(MODULE_DIR, "decision_intel.py")

DEFAULT_LOG = os.path.normpath(os.path.join(MODULE_DIR, "..", "..", "core-docs", "DECISION_LOG.md"))
DEFAULT_IDX = os.path.normpath(os.path.join(MODULE_DIR, "..", "..", "core-docs", "DECISION_LOG_INDEX.md"))

FAKE_SHA = "0123456789abcdef0123456789abcdef01234567"

_pass = 0
_fail = 0


def check(name, cond, detail=""):
    global _pass, _fail
    if cond:
        _pass += 1
        print("PASS: %s" % name)
    else:
        _fail += 1
        print("FAIL: %s %s" % (name, ("-- " + detail) if detail else ""))


def run_worker(log_path, idx_path, outdir, ingested_through=FAKE_SHA):
    meta_path = os.path.join(outdir, "meta.json")
    args = {
        "op": "index",
        "decision_log_path": log_path,
        "decision_log_index_path": idx_path,
        "namespace": "decisions",
        "ingested_through": ingested_through,
        "output_dir": outdir,
        "meta_path": meta_path,
    }
    args_path = os.path.join(outdir, "args.json")
    with open(args_path, "w", encoding="utf-8") as fh:
        json.dump(args, fh)
    r = subprocess.run([sys.executable, WORKER, args_path], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(meta_path):
        raise RuntimeError("worker failed exit=%s stdout=%r stderr=%r" % (r.returncode, r.stdout, r.stderr))
    with open(meta_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main():
    log_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOG
    idx_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_IDX

    if not os.path.isfile(log_path) or not os.path.isfile(idx_path):
        print("SKIP: real corpus not found at %r / %r (pass explicit paths as argv) " % (log_path, idx_path))
        return 0

    tmp1 = tempfile.mkdtemp(prefix="decint_run1_")
    tmp2 = tempfile.mkdtemp(prefix="decint_run2_")
    try:
        meta1 = run_worker(log_path, idx_path, tmp1)
        meta2 = run_worker(log_path, idx_path, tmp2)

        check("worker ok run1", meta1.get("ok") is True)
        check("worker ok run2", meta2.get("ok") is True)

        check("total_records == index_row_count", meta1["total_records"] == meta1["coverage"]["index_row_count"],
              "%r vs %r" % (meta1["total_records"], meta1["coverage"]["index_row_count"]))
        check("coverage.ok", meta1["coverage"]["ok"] is True, json.dumps(meta1["coverage"]))
        check("coverage: no missing", meta1["coverage"]["missing_records_for_index_rows"] == [])
        check("coverage: no extra", meta1["coverage"]["extra_records_without_index_row"] == [])
        check("coverage: spans resolve", meta1["coverage"]["span_resolution_ok"] is True)

        check("validation.ok", meta1["validation"]["ok"] is True, json.dumps(meta1["validation"]["errors"][:5]))
        check("validation.error_count == 0", meta1["validation"]["error_count"] == 0)
        check("validation.checked == total_records", meta1["validation"]["checked"] == meta1["total_records"])

        check("edge_summary has resolved internal edges", meta1["edge_summary"]["resolved_internal"] > 0,
              json.dumps(meta1["edge_summary"]))
        check("edge_summary: no unresolved (validation already 0-error implies this, cross-check)",
              meta1["validation"]["error_count"] == 0)

        check("unresolved_supersession_targets is empty", meta1["unresolved_supersession_targets"] == [],
              json.dumps(meta1["unresolved_supersession_targets"]))

        cbs = meta1["counts_by_binding_scope"]
        check("binding_scope: standing_prohibition present", cbs.get("standing_prohibition", 0) > 0, json.dumps(cbs))
        check("binding_scope: invariant present", cbs.get("invariant", 0) > 0, json.dumps(cbs))
        check("binding_scope: ordinary present", cbs.get("ordinary", 0) > 0, json.dumps(cbs))

        cst = meta1["counts_by_status"]
        check("status: at least one non-current (supersession/fold detected)",
              (cst.get("superseded", 0) + cst.get("folded", 0)) > 0, json.dumps(cst))

        # ---- deterministic double-run byte-identity over every canonical artifact ----
        names = ["records.jsonl", "records.json", "ingest_records.json", "index_manifest.json", "coverage.json"]
        all_identical = True
        for n in names:
            p1 = os.path.join(tmp1, n)
            p2 = os.path.join(tmp2, n)
            ok = os.path.isfile(p1) and os.path.isfile(p2) and sha256_file(p1) == sha256_file(p2)
            check("byte-identical across runs: %s" % n, ok)
            all_identical = all_identical and ok
        check("byte-identical across runs: ALL canonical artifacts", all_identical)

        # ---- an enforced_by=<gate> case exists (spot-check via records.jsonl) ----
        recs = []
        with open(os.path.join(tmp1, "records.jsonl"), "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line:
                    recs.append(json.loads(line))
        enforced = [r for r in recs if r["payload"]["enforced_by"] != "none"]
        check("at least one enforced_by != none case", len(enforced) > 0)

        # ---- ingest_records.json conforms to the #36 INPUT shape (required keys per record) ----
        with open(os.path.join(tmp1, "ingest_records.json"), "r", encoding="utf-8") as fh:
            ir = json.load(fh)
        check("ingest_records: op field", ir.get("op") == "ingest-records")
        check("ingest_records: record_count matches", ir.get("record_count") == len(recs))
        req_keys = {"record_id", "record_version_id", "record_kind", "text", "namespace", "status",
                    "source_path", "source_span", "attrs", "edges"}
        bad = [r["record_id"] for r in ir["records"] if not req_keys.issubset(set(r.keys()))]
        check("ingest_records: every record has required INPUT-shape keys", bad == [], json.dumps(bad[:5]))
        bad_kind = [r["record_id"] for r in ir["records"] if r["record_kind"] != "decision"]
        check("ingest_records: every record_kind == decision", bad_kind == [])

        # ---- tamper detection: mutate a record's content_hash, validator must reject ----
        tampered = list(recs)
        if tampered:
            t = dict(tampered[0])
            t["content_hash"] = "0" * 64
            tamper_path = os.path.join(tmp1, "tampered.jsonl")
            with open(tamper_path, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(t) + "\n")
            meta_v = os.path.join(tmp1, "meta_validate_tamper.json")
            args_v = {"op": "validate", "records_path": tamper_path, "meta_path": meta_v}
            args_v_path = os.path.join(tmp1, "args_validate_tamper.json")
            with open(args_v_path, "w", encoding="utf-8") as fh:
                json.dump(args_v, fh)
            subprocess.run([sys.executable, WORKER, args_v_path], capture_output=True, text=True)
            with open(meta_v, "r", encoding="utf-8") as fh:
                mv = json.load(fh)
            check("validator rejects a tampered content_hash", mv["validation"]["ok"] is False)

    finally:
        shutil.rmtree(tmp1, ignore_errors=True)
        shutil.rmtree(tmp2, ignore_errors=True)

    print("")
    print("RESULT: %d passed, %d failed" % (_pass, _fail))
    return 0 if _fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
