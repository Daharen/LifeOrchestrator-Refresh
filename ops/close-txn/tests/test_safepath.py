#!/usr/bin/env python3
"""Adversarial tests for safepath.py -- the unified fail-closed path+input policy (i63 corrective, D-0163).

Includes the permanent V63-01..V63-14 regression corpus (the exact escape shapes the independent review
replayed) + the transaction-id escape (T63-02) + reparse/symlink controls (portable symlink here; the real
NTFS junction control runs on Windows via the executor, see tests/win_reparse_probe.py). Disposable temp
repos only -- the canonical repo is never an escape target.
"""
import os
import sys
import tempfile
import shutil
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import safepath as sp  # noqa: E402


def checker_for(repo):
    def _c(v):
        try:
            sp.safe_repo_path(repo, v)
            return None
        except sp.PathSafetyError as e:
            return e.reason
    return _c


class Txid(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(sp.validate_txid("close-i63-abc.def-1", 63), "close-i63-abc.def-1")

    def test_iteration_binding(self):
        with self.assertRaises(sp.TxidError):
            sp.validate_txid("close-i63-x", 64)

    def test_escape_journal(self):
        # T63-02 exact counterexample
        with self.assertRaises(sp.TxidError):
            sp.validate_txid("close-i63-x/../../../../../../escaped-journal", 63)

    def test_backslash(self):
        with self.assertRaises(sp.TxidError):
            sp.validate_txid("close-i63-x\\y", 63)

    def test_dotdot(self):
        with self.assertRaises(sp.TxidError):
            sp.validate_txid("close-i63-..", 63)

    def test_bad_grammar(self):
        for bad in ["i63-x", "close-x", "close-i-x", "", "close-i63-", None, 5]:
            with self.assertRaises(sp.TxidError):
                sp.validate_txid(bad, 63)

    def test_length_bounded(self):
        with self.assertRaises(sp.TxidError):
            sp.validate_txid("close-i63-" + "a" * 200, 63)


class V63Corpus(unittest.TestCase):
    """Replay the exact escape categories the review's V63-01..14 corpus covered -- each must fail closed
    BEFORE any read/write, for the correct reason."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="v63-repo-")
        os.makedirs(os.path.join(self.repo, "core-docs"), exist_ok=True)
        self.chk = checker_for(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _reject(self, val, needle):
        r = self.chk(val)
        self.assertIsNotNone(r, "expected reject for %r" % val)
        self.assertIn(needle, r)

    def test_V63_01_target_traversal(self):
        self._reject("../../etc/passwd", "parent traversal")

    def test_V63_02_posix_absolute(self):
        self._reject("/etc/passwd", "absolute")

    def test_V63_03_drive_absolute(self):
        self._reject("C:\\Windows\\system32\\x", "Windows drive")

    def test_V63_04_drive_relative(self):
        self._reject("C:evil.md", "Windows drive")

    def test_V63_05_unc(self):
        self._reject("\\\\evil\\share\\x", "UNC")

    def test_V63_06_device_path(self):
        self._reject("\\\\?\\C:\\x", "UNC")

    def test_V63_07_dotgit(self):
        self._reject(".git/hooks/pre-commit", "protected")

    def test_V63_08_dotgit_case_alias(self):
        self._reject(".GIT/config", "protected")

    def test_V63_09_nested_dotgit(self):
        self._reject("core-docs/.Git/config", "protected")

    def test_V63_10_payload_escape(self):
        self._reject("../../secret", "parent traversal")

    def test_V63_11_ledger_absolute(self):
        self._reject("/var/ledger.jsonl", "absolute")

    def test_V63_12_backing_ref_integer(self):
        # screen_refs must reject a non-string path field
        refs = [("op.backing_ref", 123)]
        f = sp.screen_refs(refs, self.chk)
        self.assertTrue(any("must be a string path" in x for x in f), f)

    def test_V63_13_nested_evidence_escape(self):
        op = {"op_id": "v", "kind": "validator",
              "payload_ref": {"predicate": "x", "evidence": ["../../x", "core-docs/ok.md"]}}
        refs = sp.op_path_refs(op)
        f = sp.screen_refs(refs, self.chk)
        self.assertTrue(any("parent traversal" in x for x in f), f)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_V63_14_symlink_escape(self):
        outside = tempfile.mkdtemp(prefix="v63-out-")
        try:
            with open(os.path.join(outside, "loot"), "w") as fh:
                fh.write("secret")
            link = os.path.join(self.repo, "core-docs", "escape")
            try:
                os.symlink(os.path.join(outside, "loot"), link)
            except (OSError, NotImplementedError):
                self.skipTest("cannot symlink")
            r = self.chk("core-docs/escape")
            self.assertIsNotNone(r)
            self.assertTrue(("reparse" in r) or ("outside" in r), r)
        finally:
            shutil.rmtree(outside, ignore_errors=True)


class OpPathScreening(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="ops-repo-")
        os.makedirs(os.path.join(self.repo, "core-docs"), exist_ok=True)
        with open(os.path.join(self.repo, "core-docs", "d.md"), "w") as fh:
            fh.write("x")
        self.chk = checker_for(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_header_ledger_screened(self):
        op = {"op_id": "a", "kind": "ack", "payload_ref": {"predicate": "true"}}
        refs = sp.op_path_refs(op, header={"ledger_ref": "../../x"})
        f = sp.screen_refs(refs, self.chk)
        self.assertTrue(any("header.ledger_ref" in x and "parent traversal" in x for x in f), f)

    def test_content_all_fields(self):
        op = {"op_id": "c", "kind": "replace_section", "target": "core-docs/d.md",
              "payload_ref": "runtime/p.md", "backing_ref": "ops/close-txn/spec"}
        refs = sp.op_path_refs(op, header={"ledger_ref": "core-docs/d.md"})
        # all safe here (they resolve inside; runtime/p.md parent exists-or-not but no traversal)
        f = sp.screen_refs(refs, self.chk)
        # runtime/ and ops/close-txn/spec don't exist -> safe_repo_path allows nonexistent-inside paths
        self.assertEqual([x for x in f if "unsafe" in x], [], f)

    def test_integer_backing_ref_rejected(self):
        op = {"op_id": "c", "kind": "replace_section", "target": "core-docs/d.md",
              "payload_ref": "runtime/p.md", "backing_ref": 42}
        f = sp.screen_refs(sp.op_path_refs(op), self.chk)
        self.assertTrue(any("backing_ref" in x and "must be a string path" in x for x in f), f)

    def test_lexical_checker_matches_execution(self):
        # the static validator uses classify_unsafe; it must agree on the escapes
        op = {"op_id": "c", "kind": "create", "target": "../../x", "payload_ref": {"inline": "y"}}
        f = sp.screen_refs(sp.op_path_refs(op), sp.classify_unsafe)
        self.assertTrue(any("parent traversal" in x for x in f), f)


class DirIdentity(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="dir-repo-")
        self.outside = tempfile.mkdtemp(prefix="dir-out-")
        os.makedirs(os.path.join(self.repo, "spec", "sub"), exist_ok=True)
        with open(os.path.join(self.repo, "spec", "a.md"), "w") as fh:
            fh.write("aaa")
        with open(os.path.join(self.repo, "spec", "sub", "b.md"), "w") as fh:
            fh.write("bbb")
        with open(os.path.join(self.outside, "loot"), "w") as fh:
            fh.write("secret-loot")

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)
        shutil.rmtree(self.outside, ignore_errors=True)

    def test_ok_deterministic(self):
        d1, n1 = sp.dir_identity(self.repo, "spec")
        d2, n2 = sp.dir_identity(self.repo, "spec")
        self.assertEqual(d1, d2)
        self.assertEqual(n1, 6)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_nested_symlink_member_rejected(self):
        # C63-10: a nested link to an external file must be rejected, not followed
        link = os.path.join(self.repo, "spec", "sub", "leak")
        try:
            os.symlink(os.path.join(self.outside, "loot"), link)
        except (OSError, NotImplementedError):
            self.skipTest("cannot symlink")
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.dir_identity(self.repo, "spec")
        self.assertIn("reparse", cm.exception.reason)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_nested_symlinked_dir_rejected(self):
        link = os.path.join(self.repo, "spec", "outdir")
        try:
            os.symlink(self.outside, link, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("cannot symlink")
        with self.assertRaises(sp.PathSafetyError):
            sp.dir_identity(self.repo, "spec")


if __name__ == "__main__":
    unittest.main(verbosity=2)
