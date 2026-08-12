#!/usr/bin/env python3
"""Off-box unit tests for ops/audit/doc-commit-gate.py (M2-A). Pure stdlib (unittest + subprocess
+ tempfile + a real throwaway git repo per test -- no network, no fixtures outside this file).

Run:  python ops/audit/tests/test_doc_commit_gate.py
  or: python -m unittest ops.audit.tests.test_doc_commit_gate   (needs __init__.py stubs; the
      direct-run form above is the one exercised by dev.ship / CI here)
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT_DIR = os.path.dirname(HERE)               # ops/audit
GATE_PY = os.path.join(AUDIT_DIR, "doc-commit-gate.py")
GEN_DOC_HEALTH_PY = os.path.join(AUDIT_DIR, "gen-doc-health.py")

DOC_PROTOCOL_TEMPLATE = """# DOC_PROTOCOL -- test fixture

## 2. The doc set: owner, budget, over-budget action

| doc | owns | budget |
|---|---|---|
| CURRENT_STATE.md | reality NOW | {current_state_kb} KB |
| DECISION_LOG.md | append-only rationale | no cap (indexed; tool-pull only) |
| DECISION_LOG_INDEX.md | routing rows | 20 KB |

## 3. Accretion rules (hot docs)

REPLACE, don't append.
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def run(cwd, *args):
    p = subprocess.run([sys.executable, GATE_PY] + list(args), cwd=cwd,
                        capture_output=True, text=True, timeout=30)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    parsed = [json.loads(l) for l in lines]
    return p.returncode, parsed, p.stderr


def run_raw(cwd, *args):
    p = subprocess.run([sys.executable, GATE_PY] + list(args), cwd=cwd,
                        capture_output=True, text=True, timeout=30)
    return p.returncode, p.stdout, p.stderr


def git(repo, *args, check=True):
    p = subprocess.run(["git"] + list(args), cwd=repo, capture_output=True, text=True, timeout=30)
    if check and p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (args, p.stderr))
    return p


class GateRepo:
    """A throwaway git repo with the minimal Life Orchestrator doc-hygiene skeleton."""

    def __init__(self, current_state_kb=34):
        self.dir = tempfile.mkdtemp(prefix="docgate-test-")
        git(self.dir, "init", "-q")
        git(self.dir, "config", "user.email", "test@test.local")
        git(self.dir, "config", "user.name", "test")
        os.makedirs(os.path.join(self.dir, "ops", "audit"), exist_ok=True)
        shutil.copy(GATE_PY, os.path.join(self.dir, "ops", "audit", "doc-commit-gate.py"))
        shutil.copy(GEN_DOC_HEALTH_PY, os.path.join(self.dir, "ops", "audit", "gen-doc-health.py"))
        write(os.path.join(self.dir, "core-docs", "DOC_PROTOCOL.md"),
              DOC_PROTOCOL_TEMPLATE.format(current_state_kb=current_state_kb))
        write(os.path.join(self.dir, "core-docs", "DECISION_LOG.md"),
              "# DECISION_LOG\n\n## D-0001\ndecision: seed\n")
        git(self.dir, "add", "-A")
        git(self.dir, "commit", "-q", "-m", "seed")

    def write(self, relpath, text):
        write(os.path.join(self.dir, relpath), text)

    def add(self, *relpaths):
        git(self.dir, "add", *relpaths)

    def rm_staged(self, relpath):
        git(self.dir, "rm", "-q", "--cached", relpath)

    def run(self, *args):
        return run(self.dir, *args)

    def run_raw(self, *args):
        return run_raw(self.dir, *args)

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class ParseBudgetsReuseTest(unittest.TestCase):
    def test_gate_uses_gen_doc_health_parse_budgets(self):
        repo = GateRepo(current_state_kb=1)  # 1 KB budget -- trivial to bust
        try:
            repo.write("core-docs/CURRENT_STATE.md", "x" * 2000)  # 2000 bytes > 1000-byte budget
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            budget_findings = [f for f in findings if f["rule"] == "budget"]
            self.assertEqual(len(budget_findings), 1)
            self.assertEqual(budget_findings[0]["budget"], 1000)  # 1 KB * KB(1000), reused table
        finally:
            repo.cleanup()


class BudgetCheckTest(unittest.TestCase):
    def test_under_budget_passes(self):
        repo = GateRepo(current_state_kb=34)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "x" * 100)
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertEqual([f for f in findings if f["rule"] == "budget"], [])
        finally:
            repo.cleanup()

    def test_over_budget_rejects_with_delta(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "y" * 1500)
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            f = [x for x in findings if x["rule"] == "budget"][0]
            self.assertEqual(f["measured"], 1500)
            self.assertEqual(f["budget"], 1000)
            self.assertEqual(f["delta"], 500)
            self.assertEqual(f["severity"], "reject")
        finally:
            repo.cleanup()


def dp_text_with_extra_s2_row(current_state_kb=1):
    """A DOC_PROTOCOL edit that touches the s2 TABLE (a new row) without changing
    CURRENT_STATE.md's own budget -- isolates 'DOC_PROTOCOL s2 touched' from 'budget raised'."""
    base = DOC_PROTOCOL_TEMPLATE.format(current_state_kb=current_state_kb)
    return base.replace(
        "| DECISION_LOG_INDEX.md | routing rows | 20 KB |\n",
        "| DECISION_LOG_INDEX.md | routing rows | 20 KB |\n"
        "| SOME_NEW_DOC.md | placeholder | 5 KB |\n")


class OverrideTest(unittest.TestCase):
    def test_override_honored_when_d_id_exists_and_doc_protocol_touched(self):
        repo = GateRepo(current_state_kb=1)
        try:
            # touch the DOC_PROTOCOL s2 table (add a row) in the same commit -- budget for
            # CURRENT_STATE.md itself stays at 1 KB, still busted by the 1500-byte doc below.
            repo.write("core-docs/DOC_PROTOCOL.md", dp_text_with_extra_s2_row(1))
            repo.write("core-docs/DECISION_LOG.md",
                        "# DECISION_LOG\n\n## D-0001\ndecision: seed\n\n## D-0042\ndecision: raise budget\n")
            repo.write("core-docs/CURRENT_STATE.md", "z" * 1500)
            repo.add("core-docs/DOC_PROTOCOL.md", "core-docs/DECISION_LOG.md", "core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged", "--message", "GATE_OVERRIDE: D-0042 raise the cap")
            self.assertEqual(code, 0, findings)
            self.assertEqual([f for f in findings if f["rule"] == "budget"], [])
            log_path = os.path.join(repo.dir, "ops", "out", "doc-gate-log.jsonl")
            self.assertTrue(os.path.isfile(log_path))
            with open(log_path) as fh:
                rows = [json.loads(l) for l in fh if l.strip()]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["d_id"], "D-0042")
        finally:
            repo.cleanup()

    def test_override_rejected_when_d_id_does_not_exist(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/DOC_PROTOCOL.md", dp_text_with_extra_s2_row(1))
            repo.write("core-docs/CURRENT_STATE.md", "z" * 1500)
            repo.add("core-docs/DOC_PROTOCOL.md", "core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged", "--message", "GATE_OVERRIDE: D-9999 nonexistent")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "budget" for f in findings))
        finally:
            repo.cleanup()

    def test_override_rejected_when_doc_protocol_not_touched(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/DECISION_LOG.md",
                        "# DECISION_LOG\n\n## D-0001\ndecision: seed\n\n## D-0042\ndecision: x\n")
            repo.write("core-docs/CURRENT_STATE.md", "z" * 1500)
            repo.add("core-docs/DECISION_LOG.md", "core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged", "--message", "GATE_OVERRIDE: D-0042 no s2 edit")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "budget" for f in findings))
        finally:
            repo.cleanup()

    def test_staged_mode_with_no_message_never_honors_override(self):
        # Simulates the real pre-commit hook: no --message is ever available to it.
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/DOC_PROTOCOL.md", dp_text_with_extra_s2_row(1))
            repo.write("core-docs/DECISION_LOG.md",
                        "# DECISION_LOG\n\n## D-0001\ndecision: seed\n\n## D-0042\ndecision: x\n")
            repo.write("core-docs/CURRENT_STATE.md", "z" * 1500)
            repo.add("core-docs/DOC_PROTOCOL.md", "core-docs/DECISION_LOG.md", "core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")  # no --message
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "budget" for f in findings))
        finally:
            repo.cleanup()


class RelayerTest(unittest.TestCase):
    def test_over_40kb_rejects_without_relayer_note(self):
        repo = GateRepo(current_state_kb=9999)  # budget huge, isolate the re-layer check
        try:
            repo.write("core-docs/CURRENT_STATE.md", "a" * 41000)
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "relayer_40kb" for f in findings))
        finally:
            repo.cleanup()

    def test_over_40kb_passes_with_relayer_note_reference(self):
        repo = GateRepo(current_state_kb=9999)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "a" * 41000)
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run(
                "--staged", "--message",
                "slim per research/2026-08-08-current-state-relayer-plan.md")
            self.assertEqual(code, 0, findings)
            self.assertEqual([f for f in findings if f["rule"] == "relayer_40kb"], [])
        finally:
            repo.cleanup()

    def test_under_budget_but_over_40kb_still_triggers_relayer_separately_from_budget(self):
        repo = GateRepo(current_state_kb=50)  # 50 KB budget covers 41000 bytes
        try:
            repo.write("core-docs/CURRENT_STATE.md", "a" * 41000)
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            self.assertEqual([f for f in findings if f["rule"] == "budget"], [])
            self.assertTrue(any(f["rule"] == "relayer_40kb" for f in findings))
        finally:
            repo.cleanup()


class AccretionTest(unittest.TestCase):
    def test_prior_chain_rejects(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/CURRENT_STATE.md", "Active work: X\n[prior] Active work: Y\n")
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "accretion_prior_chain" for f in findings))
        finally:
            repo.cleanup()

    def test_single_last_updated_line_is_not_a_false_positive(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/CURRENT_STATE.md", "stuff\nLast updated: 2026-08-01, did X\n")
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertEqual([f for f in findings if "accretion" in f["rule"]], [])
        finally:
            repo.cleanup()

    def test_replacing_one_last_updated_line_with_another_is_not_a_chain(self):
        repo = GateRepo()
        repo.write("core-docs/CURRENT_STATE.md", "stuff\nLast updated: 2026-08-01, did X\n")
        repo.add("core-docs/CURRENT_STATE.md")
        git(repo.dir, "commit", "-q", "-m", "seed last-updated")
        try:
            repo.write("core-docs/CURRENT_STATE.md", "stuff\nLast updated: 2026-08-02, did Y\n")
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertEqual([f for f in findings if "accretion" in f["rule"]], [])
        finally:
            repo.cleanup()

    def test_stacked_last_updated_lines_added_this_commit_rejects(self):
        repo = GateRepo()
        repo.write("core-docs/CURRENT_STATE.md", "stuff\nLast updated: 2026-08-01, did X\n")
        repo.add("core-docs/CURRENT_STATE.md")
        git(repo.dir, "commit", "-q", "-m", "seed last-updated")
        try:
            repo.write("core-docs/CURRENT_STATE.md",
                        "stuff\nLast updated: 2026-08-01, did X\nLast updated: 2026-08-02, did Y\n")
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "accretion_stacked_last_updated" for f in findings))
        finally:
            repo.cleanup()


class IndexDensityTest(unittest.TestCase):
    def test_long_index_row_warns_but_does_not_reject(self):
        repo = GateRepo()
        try:
            long_row = "| D-0999 | 2026-08-08 | locked | " + ("x" * 220) + " |\n"
            repo.write("core-docs/DECISION_LOG_INDEX.md", "# index\n" + long_row)
            repo.add("core-docs/DECISION_LOG_INDEX.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertTrue(any(f["rule"] == "index_density" and f["severity"] == "warn"
                                 for f in findings))
        finally:
            repo.cleanup()


class UnlistedCoreDocTest(unittest.TestCase):
    def test_unlisted_core_doc_warns_not_rejects(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/ACTION_AUTHORIZATION_CONTRACT.md", "no s2 row for this one\n")
            repo.add("core-docs/ACTION_AUTHORIZATION_CONTRACT.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertTrue(any(f["rule"] == "unlisted_core_doc" and f["severity"] == "warn"
                                 for f in findings))
        finally:
            repo.cleanup()

    def test_unlisted_core_doc_still_gets_accretion_check(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/ACTION_AUTHORIZATION_CONTRACT.md",
                        "line one\n[prior] line two\n")
            repo.add("core-docs/ACTION_AUTHORIZATION_CONTRACT.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 1)
            self.assertTrue(any(f["rule"] == "accretion_prior_chain" for f in findings))
        finally:
            repo.cleanup()


class ExemptionTest(unittest.TestCase):
    def test_archive_modules_widgets_and_non_md_are_exempt(self):
        repo = GateRepo()
        try:
            repo.write("archive/whatever.md", "x" * 999999)
            repo.write("modules/99-x/README.md", "y" * 999999)
            repo.write("widgets/w/README.md", "z" * 999999)
            repo.write("core-docs/notes.txt", "w" * 999999)
            repo.write("core-docs/DECISION_LOG.md", "u" * 999999)  # uncapped by design
            repo.add("archive/whatever.md", "modules/99-x/README.md", "widgets/w/README.md",
                      "core-docs/notes.txt", "core-docs/DECISION_LOG.md")
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertEqual(findings, [])
        finally:
            repo.cleanup()


class DeletionTest(unittest.TestCase):
    def test_pure_deletion_is_allowed_with_no_report_line(self):
        repo = GateRepo(current_state_kb=1)
        repo.write("core-docs/CURRENT_STATE.md", "y" * 1500)  # would bust the 1 KB budget if added
        repo.add("core-docs/CURRENT_STATE.md")
        git(repo.dir, "commit", "-q", "-m", "seed oversized doc (pretend it predates the gate)")
        try:
            repo.rm_staged("core-docs/CURRENT_STATE.md")
            os.remove(os.path.join(repo.dir, "core-docs", "CURRENT_STATE.md"))
            code, findings, _ = repo.run("--staged")
            self.assertEqual(code, 0)
            self.assertEqual(findings, [])
        finally:
            repo.cleanup()


class FailClosedTest(unittest.TestCase):
    def test_missing_gen_doc_health_fails_closed(self):
        repo = GateRepo()
        try:
            os.remove(os.path.join(repo.dir, "ops", "audit", "gen-doc-health.py"))
            repo.write("core-docs/CURRENT_STATE.md", "x")
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, stderr = repo.run("--staged")
            self.assertEqual(code, 2)
            self.assertIn("GATE ERROR", stderr)
        finally:
            repo.cleanup()

    def test_files_mode_naming_an_unstaged_path_fails_closed(self):
        repo = GateRepo()
        try:
            code, findings, stderr = repo.run("--files", "core-docs/NOPE_NOT_STAGED.md")
            self.assertEqual(code, 2)
        finally:
            repo.cleanup()

    def test_not_a_git_repo_fails_closed(self):
        d = tempfile.mkdtemp(prefix="docgate-notrepo-")
        try:
            p = subprocess.run([sys.executable, GATE_PY, "--staged", "--repo", d],
                                cwd=d, capture_output=True, text=True, timeout=30)
            self.assertEqual(p.returncode, 2)
        finally:
            shutil.rmtree(d, ignore_errors=True)


class FilesModeTest(unittest.TestCase):
    def test_files_mode_matches_staged_mode_on_named_subset(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "y" * 1500)
            repo.write("core-docs/DECISION_LOG_INDEX.md", "# index\nrow\n")
            repo.add("core-docs/CURRENT_STATE.md", "core-docs/DECISION_LOG_INDEX.md")
            code_staged, findings_staged, _ = repo.run("--staged")
            code_files, findings_files, _ = repo.run("--files", "core-docs/CURRENT_STATE.md",
                                                       "core-docs/DECISION_LOG_INDEX.md")
            self.assertEqual(code_staged, code_files)
            self.assertEqual(findings_staged, findings_files)
        finally:
            repo.cleanup()


class DeterminismTest(unittest.TestCase):
    def test_double_run_byte_identical_report(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "y" * 1500)
            repo.write("core-docs/DECISION_LOG_INDEX.md",
                        "# index\n" + ("x" * 220) + "\n")
            repo.add("core-docs/CURRENT_STATE.md", "core-docs/DECISION_LOG_INDEX.md")
            p1 = subprocess.run([sys.executable, GATE_PY, "--staged"], cwd=repo.dir,
                                 capture_output=True, text=True, timeout=30)
            p2 = subprocess.run([sys.executable, GATE_PY, "--staged"], cwd=repo.dir,
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(p1.returncode, p2.returncode)
            self.assertEqual(p1.stdout, p2.stdout)
        finally:
            repo.cleanup()


class InstallHookTest(unittest.TestCase):
    def test_install_hook_idempotent_and_manifest_matches(self):
        repo = GateRepo()
        try:
            code1, _, _ = repo.run_raw("--install-hook")
            self.assertEqual(code1, 0)
            hook_path = os.path.join(repo.dir, ".git", "hooks", "pre-commit")
            self.assertTrue(os.path.isfile(hook_path))
            with open(hook_path, "rb") as fh:
                content1 = fh.read()
            manifest_path = os.path.join(repo.dir, "ops", "audit", "doc-gate-hook.sha256")
            self.assertTrue(os.path.isfile(manifest_path))
            import hashlib
            digest = hashlib.sha256(content1).hexdigest()
            with open(manifest_path) as fh:
                manifest = fh.read()
            self.assertIn(digest, manifest)
            # idempotent: second install-hook call is a no-op on content
            code2, _, _ = repo.run_raw("--install-hook")
            self.assertEqual(code2, 0)
            with open(hook_path, "rb") as fh:
                content2 = fh.read()
            self.assertEqual(content1, content2)
        finally:
            repo.cleanup()

    def test_installed_hook_actually_fires_on_real_commit(self):
        repo = GateRepo(current_state_kb=1)
        try:
            code, _, _ = repo.run_raw("--install-hook")
            self.assertEqual(code, 0)
            repo.write("core-docs/CURRENT_STATE.md", "y" * 1500)  # over the 1 KB budget
            repo.add("core-docs/CURRENT_STATE.md")
            p = git(repo.dir, "commit", "-m", "should be rejected by the hook", check=False)
            self.assertNotEqual(p.returncode, 0)
            log = git(repo.dir, "log", "--oneline")
            self.assertNotIn("should be rejected", log.stdout)
            # now fix it and commit again -- should pass
            repo.write("core-docs/CURRENT_STATE.md", "y" * 100)
            repo.add("core-docs/CURRENT_STATE.md")
            p2 = git(repo.dir, "commit", "-m", "now compliant", check=False)
            self.assertEqual(p2.returncode, 0)
        finally:
            repo.cleanup()


class CatalogGrowthTest(unittest.TestCase):
    """D-0139: DECISION_LOG_INDEX.md is a growth-exempt routing CATALOG -- no whole-file byte
    reject; per-row density + accretion + all OTHER docs' budgets stay fail-closed."""

    def _index(self, nrows, cell="routing label"):
        head = "# DECISION_LOG_INDEX\n\n| id | date | state | decision |\n|---|---|---|---|\n"
        rows = "".join("| D-%04d | 2026-08-12 | locked | %s %d |\n" % (i, cell, i) for i in range(1, nrows + 1))
        return head + rows

    def test_index_over_20kb_not_rejected(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/DECISION_LOG_INDEX.md", self._index(700))  # ~35 KB, over 20 KB, under 40 KB
            repo.add("core-docs/DECISION_LOG_INDEX.md")
            code, findings, err = repo.run("--staged", "--repo", repo.dir)
            self.assertFalse([f for f in findings if f["rule"] == "budget" and f["severity"] == "reject"], findings)
            self.assertFalse([f for f in findings if f["rule"] == "relayer_40kb"], findings)
            self.assertEqual(code, 0, (code, findings, err))
        finally:
            repo.cleanup()

    def test_index_past_40kb_warns_not_rejects(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/DECISION_LOG_INDEX.md", self._index(900))  # ~45 KB, past the 40 KB re-layer line
            repo.add("core-docs/DECISION_LOG_INDEX.md")
            code, findings, err = repo.run("--staged", "--repo", repo.dir)
            self.assertTrue([f for f in findings if f["rule"] == "relayer_catalog_40kb" and f["severity"] == "warn"], findings)
            self.assertFalse([f for f in findings if f["severity"] == "reject"], findings)
            self.assertEqual(code, 0, (code, findings, err))
        finally:
            repo.cleanup()

    def test_index_density_still_warns(self):
        repo = GateRepo()
        try:
            repo.write("core-docs/DECISION_LOG_INDEX.md",
                       "# DECISION_LOG_INDEX\n\n| D-9999 | 2026-08-12 | locked | " + ("x" * 220) + " |\n")
            repo.add("core-docs/DECISION_LOG_INDEX.md")
            code, findings, err = repo.run("--staged", "--repo", repo.dir)
            self.assertTrue([f for f in findings if f["rule"] == "index_density" and f["severity"] == "warn"], findings)
            self.assertEqual(code, 0, (code, findings))
        finally:
            repo.cleanup()

    def test_other_core_doc_still_rejects_over_budget(self):
        repo = GateRepo(current_state_kb=1)
        try:
            repo.write("core-docs/CURRENT_STATE.md", "x" * 2000)  # > 1000-byte budget
            repo.add("core-docs/CURRENT_STATE.md")
            code, findings, err = repo.run("--staged", "--repo", repo.dir)
            self.assertTrue([f for f in findings if f["rule"] == "budget" and f["severity"] == "reject"], findings)
            self.assertEqual(code, 1, (code, findings))
        finally:
            repo.cleanup()


if __name__ == "__main__":
    unittest.main(verbosity=2)
