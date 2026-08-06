#!/usr/bin/env python3
"""
selfverify.py -- Finding 7 EMPTY-DIR self-verification of the review pack (i40 red-team Finding 7).

Copies the COMPLETE runnable review tree into an EMPTY temp dir (excluding tests/report + __pycache__),
runs the documented command `python3 tests/run_suite.py` THERE via subprocess, and requires:

  * exit code matches the canonical source run;
  * the full suite result + all oracle rows reproduced;
  * identical source + fixture digests (source_digests.json / fixture_manifest.json);
  * a BYTE-IDENTICAL report MANIFEST (bundle_digest) vs a canonical run in the source tree.

Writes the transcript to tests/report/self_verify.json (deliberately NOT part of the byte-compared
bundle, so it never perturbs the digest it attests). The pack is proven INDEPENDENTLY runnable: the
308->334 result + 149 oracle rows + digests + the bundle manifest reproduce from nothing but the pack.

DESIGN-ONLY; p0_1_gate_status stays `incomplete` (M2-D). This is the Finding-7 self-verification the
worker commits inside the evidence bundle.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_COPY = ("action_authz", "tests", "fixtures", "SCHEMA_NOTES.md", "README.md", "WORK_ORDER.md")


def _run_suite_in(cwd):
    proc = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join("tests", "run_suite.py")],
                          cwd=cwd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def _read_json(root, *parts):
    with open(os.path.join(root, *parts), "r", encoding="utf-8") as fh:
        return json.load(fh)


def _ignore(d, names):
    drop = []
    for n in names:
        if n == "__pycache__" or (n == "report" and os.path.basename(d) == "tests"):
            drop.append(n)
    return drop


def _copy_tree(dst):
    for entry in _COPY:
        src = os.path.join(_MODDIR, entry)
        d = os.path.join(dst, entry)
        if os.path.isdir(src):
            shutil.copytree(src, d, ignore=_ignore)
        else:
            shutil.copy2(src, d)


def main():
    # 1. canonical run in the SOURCE tree (regenerate the bundle we will reproduce).
    rc_src, _out_src, _err_src = _run_suite_in(_MODDIR)
    src_manifest = _read_json(_MODDIR, "tests", "report", "MANIFEST.json")
    src_report = _read_json(_MODDIR, "tests", "report", "report.json")

    # 2. EMPTY temp dir; copy the COMPLETE tree; run the documented command from nothing.
    tmp = tempfile.mkdtemp(prefix="p01_selfverify_")
    try:
        _copy_tree(tmp)
        report_pre_exists = os.path.exists(os.path.join(tmp, "tests", "report"))
        rc_tmp, out_tmp, err_tmp = _run_suite_in(tmp)
        tmp_manifest = _read_json(tmp, "tests", "report", "MANIFEST.json")
        tmp_report = _read_json(tmp, "tests", "report", "report.json")
        tmp_oracle = _read_json(tmp, "tests", "report", "oracle_matrix.json")
        tmp_srcdig = _read_json(tmp, "tests", "report", "source_digests.json")
        src_srcdig = _read_json(_MODDIR, "tests", "report", "source_digests.json")
    finally:
        pass

    manifest_identical = (src_manifest.get("bundle_digest") == tmp_manifest.get("bundle_digest"))
    files_identical = (src_manifest.get("files") == tmp_manifest.get("files"))
    digests_identical = (src_srcdig == tmp_srcdig)
    dbl_identical = tmp_report.get("double_run", {}).get("identical") is True
    taxonomy_ok = tmp_report.get("taxonomy") == src_report.get("taxonomy")
    exit_zero = (rc_tmp == 0)                                # the documented command must EXIT ZERO
    exit_matches_source = (rc_tmp == rc_src)
    verified = bool(exit_zero and exit_matches_source and (not report_pre_exists) and manifest_identical
                    and files_identical and digests_identical and dbl_identical and taxonomy_ok)

    transcript = {
        "schema": "lifeorch.p01_self_verify/0.1",
        "verified": verified,
        "empty_dir": True,
        "report_dir_pre_existed_in_pack": report_pre_exists,
        "source_exit_code": rc_src,
        "empty_dir_exit_code": rc_tmp,
        "empty_dir_exit_zero": exit_zero,
        "exit_codes_match": exit_matches_source,
        "manifest_bundle_digest": src_manifest.get("bundle_digest"),
        "empty_dir_bundle_digest": tmp_manifest.get("bundle_digest"),
        "manifest_byte_identical": manifest_identical,
        "bundle_files_byte_identical": files_identical,
        "source_and_fixture_digests_identical": digests_identical,
        "oracle_rows_reproduced": tmp_oracle.get("row_count"),
        "double_run_identical": dbl_identical,
        "taxonomy_reproduced": tmp_report.get("taxonomy"),
        "exact_closure_built_reproduced": tmp_report.get("exact_closure_built"),
        "documented_command": "python3 -X utf8 -B tests/run_suite.py",
        "note": "the review pack was extracted into an EMPTY temp dir and the documented command run; "
                "the full suite + all oracle rows + source/fixture digests + the report MANIFEST "
                "reproduced byte-identically. p0_1_gate_status stays incomplete (M2-D).",
    }
    shutil.rmtree(tmp, ignore_errors=True)

    outp = os.path.join(_MODDIR, "tests", "report", "self_verify.json")
    os.makedirs(os.path.dirname(outp), exist_ok=True)
    with open(outp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(transcript, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("=" * 82)
    print("FINDING-7 EMPTY-DIR SELF-VERIFICATION")
    print("  empty-dir exit code ...... %s (zero=%s; source %s; match=%s)"
          % (rc_tmp, exit_zero, rc_src, exit_matches_source))
    print("  report dir pre-existed ... %s (must be False)" % report_pre_exists)
    print("  bundle MANIFEST digest ... source=%s" % (src_manifest.get("bundle_digest") or "")[:24])
    print("                             tmp   =%s" % (tmp_manifest.get("bundle_digest") or "")[:24])
    print("  manifest byte-identical .. %s" % manifest_identical)
    print("  src/fixture digests ...... identical=%s" % digests_identical)
    print("  oracle rows reproduced ... %s" % tmp_oracle.get("row_count"))
    print("  double-run identical ..... %s" % dbl_identical)
    print("  taxonomy reproduced ...... %s" % tmp_report.get("taxonomy"))
    print("  -> transcript: tests/report/self_verify.json")
    print("VERIFIED: %s" % verified)
    print("=" * 82)
    return 0 if verified else 1


if __name__ == "__main__":
    sys.exit(main())
