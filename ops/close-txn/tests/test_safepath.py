#!/usr/bin/env python3
"""Adversarial tests for safepath.py -- repository escape must fail closed (i63, D-0162).

These run BEFORE the materializer is ever allowed to write: every path a manifest can name is proven to
resolve inside the authorized repo, and every known escape vector is proven to raise. stdlib unittest;
deterministic; creates a throwaway repo tree under a TemporaryDirectory (cloud/native only -- never the
delete-less mount VM).
"""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import safepath as sp  # noqa: E402


class StructuralRejects(unittest.TestCase):
    """Lexical rejects need no filesystem -- POSIX and Windows must agree."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="sp-repo-")

    def _bad(self, rel, needle):
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.safe_repo_path(self.repo, rel)
        self.assertIn(needle, cm.exception.reason)

    def test_parent_traversal(self):
        self._bad("../secrets.txt", "parent traversal")

    def test_parent_traversal_midpath(self):
        self._bad("core-docs/../../etc/passwd", "parent traversal")

    def test_absolute_posix(self):
        self._bad("/etc/passwd", "absolute path")

    def test_windows_drive(self):
        self._bad("C:\\Windows\\system32\\drivers\\etc\\hosts", "drive-absolute")

    def test_windows_drive_fwdslash(self):
        self._bad("C:/Windows/system32", "drive-absolute")

    def test_unc_backslash(self):
        self._bad("\\\\evil-server\\share\\x", "UNC path")

    def test_unc_fwdslash(self):
        self._bad("//evil-server/share/x", "UNC path")

    def test_dotgit_component(self):
        self._bad(".git/hooks/pre-commit", "protected")

    def test_dotgit_nested(self):
        self._bad("modules/.git/config", "protected")

    def test_empty(self):
        self._bad("", "empty")

    def test_nul_byte(self):
        self._bad("core-docs/x\x00.md", "NUL")


class ContainmentAndSymlinks(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="sp-repo-")
        self.outside = tempfile.mkdtemp(prefix="sp-out-")
        os.makedirs(os.path.join(self.repo, "core-docs"), exist_ok=True)
        os.makedirs(os.path.join(self.repo, "ops", "close-txn", "spec"), exist_ok=True)
        with open(os.path.join(self.repo, "core-docs", "CURRENT_STATE.md"), "w") as fh:
            fh.write("hi")
        with open(os.path.join(self.outside, "loot.txt"), "w") as fh:
            fh.write("secret")

    def test_ok_existing_file(self):
        p = sp.safe_repo_path(self.repo, "core-docs/CURRENT_STATE.md")
        self.assertTrue(p.endswith(os.path.join("core-docs", "CURRENT_STATE.md")))

    def test_ok_nonexistent_leaf_create(self):
        # a create target does not exist yet but its parent is inside the repo -> allowed
        p = sp.safe_repo_path(self.repo, "ops/close-txn/materialize.py")
        self.assertTrue(sp._within(p, sp._real(self.repo)))

    def test_ok_backing_dir(self):
        p = sp.safe_repo_path(self.repo, "ops/close-txn/spec")
        self.assertTrue(sp._within(p, sp._real(self.repo)))

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_symlink_escape_file(self):
        # a symlink INSIDE the repo pointing at an outside file must be rejected
        link = os.path.join(self.repo, "core-docs", "escape.md")
        try:
            os.symlink(os.path.join(self.outside, "loot.txt"), link)
        except (OSError, NotImplementedError):
            self.skipTest("cannot create symlink here")
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.safe_repo_path(self.repo, "core-docs/escape.md")
        self.assertIn("outside", cm.exception.reason)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_symlink_dir_escape(self):
        # a symlinked directory inside the repo pointing outside -> a child under it must be rejected
        link = os.path.join(self.repo, "outlink")
        try:
            os.symlink(self.outside, link, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("cannot create symlink here")
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.safe_repo_path(self.repo, "outlink/loot.txt")
        self.assertIn("outside", cm.exception.reason)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlink unsupported")
    def test_symlink_into_dotgit(self):
        os.makedirs(os.path.join(self.repo, ".git"), exist_ok=True)
        with open(os.path.join(self.repo, ".git", "config"), "w") as fh:
            fh.write("[core]")
        link = os.path.join(self.repo, "core-docs", "gitcfg")
        try:
            os.symlink(os.path.join(self.repo, ".git", "config"), link)
        except (OSError, NotImplementedError):
            self.skipTest("cannot create symlink here")
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.safe_repo_path(self.repo, "core-docs/gitcfg")
        self.assertIn(".git", cm.exception.reason)

    def test_allow_root_within_repo_ok(self):
        rt = os.path.join(self.repo, "modules", "44-project-map", "runtime")
        os.makedirs(rt, exist_ok=True)
        p = sp.safe_repo_path(self.repo, "modules/44-project-map/runtime/j.jsonl", allow_roots=[rt])
        self.assertTrue(sp._within(p, sp._real(self.repo)))

    def test_allow_root_outside_repo_rejected(self):
        with self.assertRaises(sp.PathSafetyError) as cm:
            sp.safe_repo_path(self.repo, "core-docs/CURRENT_STATE.md", allow_roots=[self.outside])
        self.assertIn("outside the repo", cm.exception.reason)


if __name__ == "__main__":
    unittest.main(verbosity=2)
