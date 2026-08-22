#!/usr/bin/env python3
"""test_native_junction.py -- T63-14: a REAL native-Windows NTFS junction acceptance control (i63, D-0163).

The red-team disproved any claim that reparse handling was proven without a genuine native junction. This
control creates an actual NTFS junction with `mklink /J` (not a symlink emulation, not a monkeypatched
st_reparse_tag) INSIDE a disposable temp repo, pointing at a disposable OUTSIDE target, and asserts the
safepath policy refuses to (a) resolve a path through the junction, (b) resolve the junction itself, and
(c) fold the junction into a directory identity. The escape target is a throwaway temp dir -- the canonical
repository is NEVER used as an escape target. Skips (does not fail) on non-Windows, where no NTFS junction
can exist; the on-box native verification stack is where it actually executes."""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import safepath as sp  # noqa: E402


@unittest.skipUnless(os.name == "nt", "native NTFS junction control is Windows-only")
class NativeJunctionControl(unittest.TestCase):
    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="t63-14-")
        self.repo = os.path.join(self.base, "repo")
        self.outside = os.path.join(self.base, "outside-secret")
        os.makedirs(os.path.join(self.repo, "core-docs"))
        os.makedirs(self.outside)
        with open(os.path.join(self.outside, "secret.txt"), "w", encoding="utf-8") as fh:
            fh.write("exfiltrate me -- I live OUTSIDE the repo\n")
        # a REAL native NTFS junction INSIDE the repo -> the outside target
        self.junction = os.path.join(self.repo, "core-docs", "linkdir")
        r = subprocess.run(["cmd", "/c", "mklink", "/J", self.junction, self.outside],
                           capture_output=True, text=True)
        self.made = (r.returncode == 0)
        self.mklink_err = (r.stdout + r.stderr).strip()
        self.tag = 0
        if self.made:
            self.tag = getattr(os.lstat(self.junction), "st_reparse_tag", 0)

    def tearDown(self):
        # detach the junction without following it into the (separate) target, then drop the disposable tree
        try:
            os.rmdir(self.junction)
        except OSError:
            pass
        shutil.rmtree(self.base, ignore_errors=True)

    def test_junction_is_a_real_reparse_point(self):
        self.assertTrue(self.made, "mklink /J failed (%s); native control cannot run" % self.mklink_err)
        self.assertNotEqual(self.tag, 0, "junction carries no st_reparse_tag -> not a genuine NTFS reparse point")
        self.assertFalse(stat.S_ISLNK(os.lstat(self.junction).st_mode),
                         "a /J junction is NOT a symlink -- it must be caught by the reparse-tag path, not S_ISLNK")
        self.assertTrue(sp._is_reparse(self.junction))
        # the outside secret really is reachable THROUGH the junction on disk (so rejection is meaningful)
        self.assertTrue(os.path.exists(os.path.join(self.junction, "secret.txt")))

    def test_safe_repo_path_rejects_traversal_through_junction(self):
        self.assertTrue(self.made, self.mklink_err)
        with self.assertRaises(sp.PathSafetyError):
            sp.safe_repo_path(self.repo, "core-docs/linkdir/secret.txt")
        self.assertFalse(sp.is_safe(self.repo, "core-docs/linkdir/secret.txt"))

    def test_safe_repo_path_rejects_the_junction_itself(self):
        self.assertTrue(self.made, self.mklink_err)
        with self.assertRaises(sp.PathSafetyError):
            sp.safe_repo_path(self.repo, "core-docs/linkdir")

    def test_dir_identity_rejects_a_junction_member(self):
        self.assertTrue(self.made, self.mklink_err)
        with self.assertRaises(sp.PathSafetyError):
            sp.dir_identity(self.repo, "core-docs")


if __name__ == "__main__":
    unittest.main(verbosity=2)
