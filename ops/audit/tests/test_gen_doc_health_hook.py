#!/usr/bin/env python3
"""Off-box unit tests for the M2-A hook-presence assertion added to gen-doc-health.py
(hook_status()): missing manifest / missing hook / stale hook -> red; matching hook -> grn.
Pure stdlib. Run: python ops/audit/tests/test_gen_doc_health_hook.py
"""
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT_DIR = os.path.dirname(HERE)
GEN_DOC_HEALTH_PY = os.path.join(AUDIT_DIR, "gen-doc-health.py")
GATE_PY = os.path.join(AUDIT_DIR, "doc-commit-gate.py")


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(repo, *args):
    p = subprocess.run(["git"] + list(args), cwd=repo, capture_output=True, text=True, timeout=30)
    if p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (args, p.stderr))
    return p


class HookStatusTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="hookstatus-test-")
        git(self.dir, "init", "-q")
        git(self.dir, "config", "user.email", "t@t.local")
        git(self.dir, "config", "user.name", "t")
        os.makedirs(os.path.join(self.dir, "ops", "audit"), exist_ok=True)
        os.makedirs(os.path.join(self.dir, "core-docs"), exist_ok=True)
        shutil.copy(GEN_DOC_HEALTH_PY, os.path.join(self.dir, "ops", "audit", "gen-doc-health.py"))
        shutil.copy(GATE_PY, os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"))
        with open(os.path.join(self.dir, "core-docs", "DOC_PROTOCOL.md"), "w") as fh:
            fh.write("## 2. The doc set\n\n| doc | owns | budget |\n|---|---|---|\n")
        git(self.dir, "add", "-A")
        git(self.dir, "commit", "-q", "-m", "seed")
        # module-per-test to dodge Python's import cache on the hyphenated filename
        self.mod = load_module(os.path.join(self.dir, "ops", "audit", "gen-doc-health.py"),
                                "gdh_%s" % os.path.basename(self.dir))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_missing_manifest_is_red(self):
        status, detail = self.mod.hook_status()
        self.assertEqual(status, "red")
        self.assertIn("manifest", detail)

    def test_installed_hook_is_green(self):
        p = subprocess.run([sys.executable,
                             os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"),
                             "--install-hook"], cwd=self.dir, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        status, detail = self.mod.hook_status()
        self.assertEqual(status, "grn")

    def test_manifest_present_but_hook_missing_is_red(self):
        subprocess.run([sys.executable,
                         os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"),
                         "--install-hook"], cwd=self.dir, capture_output=True, text=True, check=True)
        os.remove(os.path.join(self.dir, ".git", "hooks", "pre-commit"))
        status, detail = self.mod.hook_status()
        self.assertEqual(status, "red")
        self.assertIn("MISSING", detail)

    def test_stale_hook_content_is_red(self):
        subprocess.run([sys.executable,
                         os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"),
                         "--install-hook"], cwd=self.dir, capture_output=True, text=True, check=True)
        hook_path = os.path.join(self.dir, ".git", "hooks", "pre-commit")
        with open(hook_path, "a") as fh:
            fh.write("\n# tampered\n")
        status, detail = self.mod.hook_status()
        self.assertEqual(status, "red")
        self.assertIn("STALE", detail)

    def test_gen_doc_health_run_embeds_hook_status_in_log_row_and_html(self):
        subprocess.run([sys.executable,
                         os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"),
                         "--install-hook"], cwd=self.dir, capture_output=True, text=True, check=True)
        p = subprocess.run([sys.executable, os.path.join(self.dir, "ops", "audit", "gen-doc-health.py"),
                             "--date", "2026-08-08"], cwd=self.dir, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(os.path.join(self.dir, "ops", "out", "doc-health-log.jsonl")) as fh:
            last = fh.readlines()[-1]
        self.assertIn('"doc_gate_hook":{"status":"grn"', last)
        with open(os.path.join(self.dir, "ops", "out", "doc-health-monitor.html")) as fh:
            html = fh.read()
        self.assertIn('chip grn"><span class="dot"></span>Hook OK', html)


if __name__ == "__main__":
    unittest.main(verbosity=2)
