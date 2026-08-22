#!/usr/bin/env python3
"""test_real_pair.py -- T63-17: execute the REAL backing/projection representative manifest in a disposable
clone and verify by SIDE EFFECT (not static schema): real source identity resolves, the full projection is
fresh + within budget, the backing is byte-preserved, and `main` is unchanged (i63, D-0163).

Uses a synthetic repo mirroring the canonical layout (ops/close-txn/spec/* backing dir + a research digest);
the identical control runs on the canonical Windows repo via the on-box T63-17 harness."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
sys.path.insert(0, os.path.join(PKG, "examples"))
import materialize as mz  # noqa: E402
import safepath as sp  # noqa: E402
import gen_i63_pair as gen  # noqa: E402

STUB_LEDGER = lambda *a, **k: {"gate": "stub"}


def gitq(repo, *args):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode())
    return p.stdout.decode().strip()


class RealPairExecution(unittest.TestCase):
    def setUp(self):
        self.src = tempfile.mkdtemp(prefix="rp-src-")
        gitq(self.src, "init", "-q", "-b", "main")
        gitq(self.src, "config", "user.email", "t@t"); gitq(self.src, "config", "user.name", "t")
        gitq(self.src, "config", "commit.gpgsign", "false")
        # a realistic multi-file COLD BACKING dir
        for name, body in [("close-transaction-hardened.md", "# HARDENED\n" + ("clause. " * 400) + "\n"),
                           ("close-transaction-contract.md", "# CONTRACT\n" + ("c. " * 100) + "\n"),
                           ("close-transaction-redteam.md", "# REDTEAM\n" + ("r. " * 200) + "\n")]:
            self._w("ops/close-txn/spec/" + name, body)
        # the bounded HOT PROJECTION with the real heading anchor
        self._w("core-docs/research/2026-08-21-i62-close-transaction.md",
                "# digest\n\n## Backing artifacts (complete, canonical)\n- points to ops/close-txn/spec\n\n## Purpose\nx\n")
        self._w("ops/audit/retrieval-ledger/i63-orchestrator.jsonl", "")
        gitq(self.src, "add", "-A"); gitq(self.src, "commit", "-q", "-m", "base")

    def _w(self, rel, text):
        p = os.path.join(self.src, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)

    def tearDown(self):
        shutil.rmtree(self.src, ignore_errors=True)

    def test_T63_17_execute_in_disposable_clone(self):
        clone = tempfile.mkdtemp(prefix="rp-clone-")
        try:
            gitq(".", "clone", "-q", "--local", self.src, clone)
            gitq(clone, "config", "user.email", "t@t"); gitq(clone, "config", "user.name", "t")
            main_before = gitq(clone, "rev-parse", "main")
            # identity of the backing dir in the clone -- the engine binds the CANDIDATE (git-tree) domain,
            # NOT the worktree (an autocrlf checkout can rewrite worktree bytes; the tree stays canonical)
            tree_fp, tree_size = mz.tree_dir_identity(clone, "ops/close-txn/spec", main_before)
            wt_before = sp.dir_identity(clone, "ops/close-txn/spec")   # worktree stability reference
            m = gen.build_pair_manifest(clone, txid="close-i63-realpair")
            op = m["operations"][0]
            self.assertEqual(op["source_fingerprint"], tree_fp)   # bound to the REAL candidate-tree identity
            # execute stage-only in the clone
            mzr = mz.Materializer(clone, m, ledger_gate=STUB_LEDGER)
            res = mzr.run()
            self.assertTrue(res["ok"], res)
            self.assertTrue(res["sealed"])
            self.assertTrue(mzr.evidence["freshness_valid"]["reproject-digest"])
            self.assertEqual(mzr.evidence["source_size"]["reproject-digest"], tree_size)
            proj_size = mzr.evidence["projection_size"]["reproject-digest"]
            self.assertLessEqual(proj_size, op["budget_bytes"])   # full projection within budget
            self.assertGreater(proj_size, 0)
            # main is byte/commit-identical; the backing dir is untouched (both tree AND worktree domains)
            self.assertEqual(gitq(clone, "rev-parse", "main"), main_before)
            self.assertEqual(mz.tree_dir_identity(clone, "ops/close-txn/spec", main_before), (tree_fp, tree_size))
            self.assertEqual(sp.dir_identity(clone, "ops/close-txn/spec"), wt_before)
            # the staged tip carries the re-projected digest (durably), NOT the worktree
            tip = res["final_head"]
            staged = subprocess.run(["git", "-C", clone, "show",
                                     "%s:core-docs/research/2026-08-21-i62-close-transaction.md" % tip],
                                    capture_output=True).stdout.decode()
            self.assertIn(gen.MARKER, staged)
            with open(os.path.join(clone, "core-docs", "research",
                                   "2026-08-21-i62-close-transaction.md")) as fh:
                self.assertNotIn(gen.MARKER, fh.read())  # worktree unchanged (stage-only)
        finally:
            shutil.rmtree(clone, ignore_errors=True)

    def test_T63_17b_worktree_eol_drift_uses_candidate_tree_domain(self):
        """Regression for the on-box T63-17 clone finding: a checkout whose autocrlf rewrites the worktree to
        CRLF while the git blob stays LF makes safepath.dir_identity (worktree) drift from the candidate tree.
        The generator MUST fingerprint the candidate (git-tree) domain the engine transacts, so the manifest
        still binds + seals despite a dirty CRLF worktree (i63, D-0163)."""
        clone = tempfile.mkdtemp(prefix="rp-eol-")
        try:
            gitq(".", "clone", "-q", "--local", self.src, clone)
            gitq(clone, "config", "user.email", "t@t"); gitq(clone, "config", "user.name", "t")
            # simulate an autocrlf checkout: rewrite the worktree bytes to CRLF WITHOUT touching the blob
            for rel in ["ops/close-txn/spec/close-transaction-hardened.md",
                        "ops/close-txn/spec/close-transaction-contract.md",
                        "ops/close-txn/spec/close-transaction-redteam.md",
                        "core-docs/research/2026-08-21-i62-close-transaction.md"]:
                p = os.path.join(clone, rel.replace("/", os.sep))
                with open(p, "rb") as fh:
                    data = fh.read()
                with open(p, "wb") as fh:
                    fh.write(data.replace(b"\n", b"\r\n"))
            head = gitq(clone, "rev-parse", "HEAD")
            wt_fp, _ = sp.dir_identity(clone, "ops/close-txn/spec")            # worktree (now CRLF)
            tree_fp, _ = mz.tree_dir_identity(clone, "ops/close-txn/spec", head)  # candidate tree (LF)
            self.assertNotEqual(wt_fp, tree_fp)   # the exact drift the on-box clone hit
            m = gen.build_pair_manifest(clone, txid="close-i63-eoldrift")
            self.assertEqual(m["operations"][0]["source_fingerprint"], tree_fp)   # tree-domain, NOT worktree
            self.assertNotEqual(m["operations"][0]["source_fingerprint"], wt_fp)
            res = mz.Materializer(clone, m, ledger_gate=STUB_LEDGER).run()
            self.assertTrue(res["ok"] and res["sealed"], res)   # seals despite the CRLF worktree drift
        finally:
            shutil.rmtree(clone, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
