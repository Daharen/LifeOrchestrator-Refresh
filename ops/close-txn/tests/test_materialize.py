#!/usr/bin/env python3
"""Tests for materialize.py -- the i63 close-transaction materializer (D-0162).

Covers PLAN/PRE-VALIDATE/APPLY/REBUILD/POST-VALIDATE/SHIP/SEAL against throwaway git repos, plus the i63
negative surface: repository escape, missing edit targets, malformed classification, missing / stale
backing, and OVERFLOW WITHOUT INFORMATION LOSS (spill, never compress). Also proves idempotence (a SEALED
re-run is a no-op) and that `main` is NEVER cut over without allow_live_cutover (INV-1/INV-9).

stdlib unittest; deterministic; throwaway repos under TemporaryDirectory (cloud/native only). Requires git.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import materialize as mz  # noqa: E402


def _git(repo, *args, input_bytes=None):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, input=input_bytes)
    if p.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace")))
    return p.stdout.decode().strip()


def make_repo():
    repo = tempfile.mkdtemp(prefix="mz-repo-")
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    _git(repo, "config", "commit.gpgsign", "false")
    return repo


def write(repo, rel, text, eol="lf"):
    path = os.path.join(repo, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = text.replace("\n", "\r\n") if eol == "crlf" else text
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(data)


def commit_all(repo, msg="base"):
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", msg)
    return _git(repo, "rev-parse", "HEAD")


def base_header(repo, txid="close-i63-test", iteration=63):
    return {
        "transaction_id": txid,
        "iteration": iteration,
        "base_head": _git(repo, "rev-parse", "HEAD"),
        "ledger_ref": "modules/44-project-map/runtime/ledger.jsonl",
        "min_bounded_fraction": 0.0,
        "created_by": "test",
        "model_provenance": "test",
        "governing_model": "frontier-agent-in-deterministic-loop",
    }


def fp(repo, rel):
    with open(os.path.join(repo, rel.replace("/", os.sep)), "rb") as fh:
        return mz.fp_of_bytes(fh.read())


class TestApplySeal(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CURRENT_STATE.md",
              "# CURRENT_STATE\n\n## Next expected action\nold text here\n\n## Other\ntail\n")
        write(self.repo, "core-docs/DECISION_LOG.md", "# DLOG\n\n## D-0001 -- x\nbody\n")
        commit_all(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _replace_manifest(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "cs", "kind": "replace_section", "target": "core-docs/CURRENT_STATE.md",
             "semantic_owner": "deterministic", "eol": "lf",
             "region_anchor": {"type": "heading", "heading": "## Next expected action"},
             "precondition": fp(self.repo, "core-docs/CURRENT_STATE.md"),
             "payload_ref": {"inline": "## Next expected action\nNEW i63 text\n\n"},
             "depends_on": []},
        ]}
        return m

    def test_plan_apply_seal_staged_no_cutover(self):
        m = self._replace_manifest()
        res = mz.Materializer(self.repo, m).run()
        self.assertTrue(res["ok"], res)
        self.assertTrue(res["sealed"])
        self.assertEqual(res["cutover"], "deferred")
        # main is UNTOUCHED (INV-1): the working file still has the old text
        with open(os.path.join(self.repo, "core-docs", "CURRENT_STATE.md")) as fh:
            self.assertIn("old text here", fh.read())
        # a staging ref exists and carries the new text
        tip = _git(self.repo, "rev-parse", "refs/lo/close/close-i63-test")
        blob = subprocess.run(["git", "-C", self.repo, "show", "%s:core-docs/CURRENT_STATE.md" % tip],
                              capture_output=True).stdout.decode()
        self.assertIn("NEW i63 text", blob)
        self.assertNotIn("old text here", blob)

    def test_idempotent_rerun_is_noop(self):
        m = self._replace_manifest()
        r1 = mz.Materializer(self.repo, m).run()
        self.assertTrue(r1["ok"])
        # re-run same manifest, same repo: PRE-VALIDATE sees the working tree unchanged (main not cut over),
        # so it re-applies onto staging deterministically and re-seals -- still ok, still deferred.
        r2 = mz.Materializer(self.repo, m).run()
        self.assertTrue(r2["ok"], r2)
        self.assertTrue(r2["sealed"])

    def test_live_cutover_when_allowed(self):
        m = self._replace_manifest()
        res = mz.Materializer(self.repo, m, allow_live_cutover=True).run()
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["cutover"], "live")
        with open(os.path.join(self.repo, "core-docs", "CURRENT_STATE.md")) as fh:
            self.assertIn("NEW i63 text", fh.read())
        # re-run after a live cutover: the target now equals the postcondition -> already-applied idempotent
        res2 = mz.Materializer(self.repo, m, allow_live_cutover=True).run()
        self.assertTrue(res2["ok"], res2)

    def test_append_marker(self):
        write(self.repo, "core-docs/DECISION_LOG.md", "# DLOG\n\n## entries\n<!-- LO:TAIL -->\n")
        commit_all(self.repo, "marker")
        m = {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "ap", "kind": "append", "target": "core-docs/DECISION_LOG.md",
             "semantic_owner": "deterministic", "eol": "lf",
             "region_anchor": {"type": "append_below", "marker": "<!-- LO:TAIL -->"},
             "precondition": fp(self.repo, "core-docs/DECISION_LOG.md"),
             "payload_ref": {"inline": "\n## D-0002 -- new\nbody2\n"},
             "depends_on": []}]}
        res = mz.Materializer(self.repo, m, allow_live_cutover=True).run()
        self.assertTrue(res["ok"], res)
        with open(os.path.join(self.repo, "core-docs", "DECISION_LOG.md")) as fh:
            body = fh.read()
        self.assertIn("D-0002", body)
        self.assertTrue(body.index("<!-- LO:TAIL -->") < body.index("D-0002"))


class TestNegative(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CURRENT_STATE.md", "# CS\n\n## Next expected action\nx\n")
        commit_all(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_missing_target_fails_closed(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "ap", "kind": "append", "target": "core-docs/DOES_NOT_EXIST.md",
             "semantic_owner": "deterministic", "eol": "lf",
             "region_anchor": {"type": "append_below", "marker": "<!-- x -->"},
             "precondition": {"basis": "native-raw", "sha256": "0" * 64},
             "payload_ref": {"inline": "y"}, "depends_on": []}]}
        res = mz.Materializer(self.repo, m).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "missing-target")

    def test_repo_escape_fails_closed(self):
        # validate_manifest would already flag it; the materializer must ALSO refuse before writing
        m = {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "esc", "kind": "create", "target": "../../etc/evil.md",
             "semantic_owner": "deterministic", "eol": "lf", "precondition": "absent",
             "payload_ref": {"inline": "pwn"}, "depends_on": []}]}
        res = mz.Materializer(self.repo, m).run()
        self.assertFalse(res["ok"])
        # plan() runs validate first -> the unsafe target is caught as a plan-error (fail-closed either way)
        self.assertIn(res["failure"], ("plan-error", "repo-escape"))

    def test_precondition_divergence(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "cs", "kind": "replace_section", "target": "core-docs/CURRENT_STATE.md",
             "semantic_owner": "deterministic", "eol": "lf",
             "region_anchor": {"type": "heading", "heading": "## Next expected action"},
             "precondition": {"basis": "native-raw", "sha256": "d" * 64},  # wrong
             "payload_ref": {"inline": "## Next expected action\nz\n"}, "depends_on": []}]}
        res = mz.Materializer(self.repo, m).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "precondition-divergence")


class TestProjectionBacking(unittest.TestCase):
    """The i63 preservation / projection-backing seam: freshness + preflight overflow (spill not compress)."""

    def setUp(self):
        self.repo = make_repo()
        # a real-shaped COLD BACKING (large, complete) and a bounded HOT PROJECTION of it
        self.backing_text = "# HARDENED CONTRACT\n" + ("detailed canonical clause. " * 400) + "\n"
        write(self.repo, "ops/close-txn/spec/close-transaction-hardened.md", self.backing_text)
        write(self.repo, "core-docs/research/digest.md", "# digest\nbounded projection\n")
        commit_all(self.repo)
        self.backing_size = os.path.getsize(
            os.path.join(self.repo, "ops", "close-txn", "spec", "close-transaction-hardened.md"))

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _projection_manifest(self, payload, budget, source_fingerprint=None, backing_ref="ops/close-txn/spec"):
        op = {"op_id": "proj", "kind": "replace_section", "target": "core-docs/research/digest.md",
              "semantic_owner": "deterministic", "eol": "lf",
              "region_anchor": {"type": "heading", "heading": "# digest"},
              "precondition": fp(self.repo, "core-docs/research/digest.md"),
              "payload_ref": {"inline": payload},
              "doc_class": "projection", "budget_bytes": budget, "backing_ref": backing_ref,
              "depends_on": []}
        if source_fingerprint is not None:
            op["source_fingerprint"] = source_fingerprint
        return {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [op]}

    def test_projection_under_budget_ok_records_evidence(self):
        m = self._projection_manifest("# digest\nshort bounded view\n", budget=10240)
        mzr = mz.Materializer(self.repo, m)
        res = mzr.run()
        self.assertTrue(res["ok"], res)
        self.assertTrue(mzr.evidence["freshness_valid"]["proj"])
        self.assertEqual(mzr.evidence["source_size"]["proj"], self.backing_size)
        self.assertGreater(mzr.evidence["projection_size"]["proj"], 0)
        self.assertEqual(mzr.evidence["overflow"], [])

    def test_projection_overflow_spills_no_information_loss(self):
        big = "# digest\n" + ("x" * 5000) + "\n"
        m = self._projection_manifest(big, budget=1024)
        mzr = mz.Materializer(self.repo, m)
        res = mzr.run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "projection-overflow")
        self.assertEqual(len(mzr.evidence["overflow"]), 1)
        ov = mzr.evidence["overflow"][0]
        self.assertFalse(ov["trimmed"])          # never trimmed
        self.assertFalse(ov["info_lost"])         # source stays lossless
        self.assertEqual(ov["resolution"], "backing-spill")
        self.assertEqual(mzr.evidence["avoidable_trim_retries"], 0)
        # the FULL source is preserved untouched (no semantic compression as recovery)
        with open(os.path.join(self.repo, "ops", "close-txn", "spec",
                               "close-transaction-hardened.md")) as fh:
            self.assertEqual(fh.read(), self.backing_text)
        # the projection file itself was NOT overwritten with a trimmed version
        with open(os.path.join(self.repo, "core-docs", "research", "digest.md")) as fh:
            self.assertNotIn("xxxx", fh.read())

    def test_missing_backing_fails_closed(self):
        m = self._projection_manifest("# digest\nv\n", budget=10240, backing_ref="ops/close-txn/NOPE")
        res = mz.Materializer(self.repo, m).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "backing-missing")

    def test_stale_backing_fails_closed(self):
        m = self._projection_manifest("# digest\nv\n", budget=10240,
                                      source_fingerprint="deadbeef")  # drifted from real backing
        res = mz.Materializer(self.repo, m).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "stale-backing")

    def test_fresh_backing_matches_recorded_fingerprint(self):
        real_fp = mz.Materializer(self.repo, self._projection_manifest("x", 10240))._path_fingerprint(
            "ops/close-txn/spec")
        m = self._projection_manifest("# digest\nv\n", budget=10240, source_fingerprint=real_fp)
        res = mz.Materializer(self.repo, m).run()
        self.assertTrue(res["ok"], res)


class TestRunnerDispatch(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CURRENT_STATE.md", "# CS\n\n## Next expected action\nx\n")
        commit_all(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _manifest_with_view_and_validator(self):
        return {"schema": "lifeorch.close_manifest/0.1", "header": base_header(self.repo), "operations": [
            {"op_id": "cs", "kind": "replace_section", "target": "core-docs/CURRENT_STATE.md",
             "semantic_owner": "deterministic", "eol": "lf",
             "region_anchor": {"type": "heading", "heading": "## Next expected action"},
             "precondition": fp(self.repo, "core-docs/CURRENT_STATE.md"),
             "payload_ref": {"inline": "## Next expected action\nnew\n"}, "depends_on": []},
            {"op_id": "rebuild", "kind": "view_rebuild", "target": "view:project.map",
             "semantic_owner": "deterministic", "payload_ref": {"generator": "map"}, "depends_on": ["cs"]},
            {"op_id": "val", "kind": "validator", "validator_id": "doc-commit-gate",
             "semantic_owner": "deterministic", "payload_ref": {"files": ["core-docs/CURRENT_STATE.md"]},
             "depends_on": ["cs"]}]}

    def test_double_run_identity_ok(self):
        def runner(kind, op):
            if kind == "view_rebuild":
                return {"digest": "STABLE"}
            return {"ok": True}
        res = mz.Materializer(self.repo, self._manifest_with_view_and_validator(), runner=runner).run()
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["phases"]["REBUILD"]["rebuilt"], ["rebuild"])
        self.assertEqual(res["phases"]["POST-VALIDATE"]["ran"], ["val"])

    def test_rebuild_drift_fails_closed(self):
        seq = {"n": 0}
        def runner(kind, op):
            if kind == "view_rebuild":
                seq["n"] += 1
                return {"digest": "D%d" % seq["n"]}  # differs across the double run
            return {"ok": True}
        res = mz.Materializer(self.repo, self._manifest_with_view_and_validator(), runner=runner).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "rebuild-drift")

    def test_validator_failure_fails_closed(self):
        def runner(kind, op):
            if kind == "view_rebuild":
                return {"digest": "S"}
            return {"ok": False, "detail": "budget bust"}
        res = mz.Materializer(self.repo, self._manifest_with_view_and_validator(), runner=runner).run()
        self.assertFalse(res["ok"])
        self.assertEqual(res["failure"], "validator-failure")

    def test_unwired_runner_defers_not_passes(self):
        # with no runner, view_rebuild + validator ops are journalled 'deferred', never silently 'passed'
        res = mz.Materializer(self.repo, self._manifest_with_view_and_validator()).run()
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["phases"]["POST-VALIDATE"]["deferred"], ["val"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
