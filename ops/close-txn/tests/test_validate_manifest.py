#!/usr/bin/env python3
"""Tests for validate_manifest.py (i62 PB-9 groundwork).

Positive: the shipped example manifests validate clean.
Negative: each invariant, exercised by a targeted mutation of a valid base, produces its specific finding.
Also tests the CLI exit codes (0 valid / 1 invalid / 2 usage) and the helper functions.

stdlib unittest; deterministic; no network. Run: python3 -m unittest -v (from ops/close-txn/tests) or
python3 tests/test_validate_manifest.py
"""
import copy
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import validate_manifest as vm  # noqa: E402

EXAMPLES = os.path.join(PKG, "examples")


def load(name):
    with open(os.path.join(EXAMPLES, name), "r", encoding="utf-8") as fh:
        return json.load(fh)


def findings_contain(findings, needle):
    return any(needle in f for f in findings)


class PositiveExamples(unittest.TestCase):
    def test_canonical_close_valid(self):
        self.assertEqual(vm.validate(load("canonical-close.json")), [])

    def test_two_edit_one_file_valid(self):
        self.assertEqual(vm.validate(load("two-edit-one-file.json")), [])

    def test_i63_backing_projection_valid(self):
        # a REAL classified backing/projection pair (hardened spec <-> research digest), not a synthetic
        # mutation: a backing op (no budget, not boot_read) + a projection op (budget + backing_ref).
        self.assertEqual(vm.validate(load("i63-backing-projection.json")), [])


class NegativeMutations(unittest.TestCase):
    def setUp(self):
        self.base = load("canonical-close.json")
        # sanity: base must be clean or the mutation tests are meaningless
        self.assertEqual(vm.validate(self.base), [])

    def _ops(self, m):
        return {o["op_id"]: o for o in m["operations"]}

    def test_replace_doc_taxonomy(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["kind"] = "replace_doc"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "not in the frozen taxonomy"), f)

    def test_duplicate_op_id(self):
        m = copy.deepcopy(self.base)
        m["operations"].append(copy.deepcopy(self._ops(m)["mirror-github"]))
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "duplicate op_id"), f)

    def test_cycle(self):
        m = copy.deepcopy(self.base)
        # make append-dlog depend on its own grader -> cycle append-dlog -> grade-dlog -> append-dlog
        self._ops(m)["append-dlog"]["depends_on"] = ["grade-dlog"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "CYCLE"), f)

    def test_frontier_no_grader(self):
        m = copy.deepcopy(self.base)
        # remove the grader edge for replace-cs-next
        m["operations"] = [o for o in m["operations"] if o["op_id"] != "grade-cs-next"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "NO dependent 'independent-grader'"), f)

    def test_frontier_selfhash(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["postcondition"] = {
            "basis": "native-raw",
            "sha256": "f" * 64,
        }
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "must NOT pre-declare a postcondition"), f)

    def test_monotonic_create(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["append-dlog"]
        op["kind"] = "create"
        op["precondition"] = "absent"
        del op["region_anchor"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "create is forbidden on the append-only target"), f)

    def test_monotonic_replace_section_needs_nonhistorical(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["append-dlog"]
        op["kind"] = "replace_section"
        op["region_anchor"] = {"type": "heading", "heading": "## Some Section"}
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "region_class='non-historical'"), f)

    def test_missing_ledger(self):
        m = copy.deepcopy(self.base)
        del m["header"]["ledger_ref"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "ledger_ref is MANDATORY"), f)

    def test_bad_iteration(self):
        m = copy.deepcopy(self.base)
        m["header"]["iteration"] = 0
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "iteration must be an integer >= 1"), f)

    def test_bad_governing_model(self):
        m = copy.deepcopy(self.base)
        m["header"]["governing_model"] = "human-in-the-loop"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "governing_model must be"), f)

    def test_unserialized_multiedit(self):
        m = copy.deepcopy(self.base)
        # add a second edit to CURRENT_STATE.md that is NOT serialized with replace-cs-next
        m["operations"].append({
            "op_id": "cs-phase2",
            "kind": "replace_section",
            "target": "core-docs/CURRENT_STATE.md",
            "semantic_owner": "frontier",
            "eol": "crlf",
            "region_anchor": {"type": "heading", "heading": "## Phase + active work"},
            "precondition": {"basis": "native-raw", "sha256": "9" * 64},
            "postcondition": None,
            "payload_ref": "x",
            "task_spec": {"goal": "phase"},
            "depends_on": [],
        })
        m["operations"].append({
            "op_id": "grade-cs-phase2",
            "kind": "validator",
            "validator_id": "independent-grader:cs-phase2",
            "semantic_owner": "deterministic",
            "payload_ref": {"predicate": "claim-vs-evidence"},
            "depends_on": ["cs-phase2"],
        })
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "not dependency-serialized"), f)

    def test_shared_anchor_multiedit(self):
        m = copy.deepcopy(self.base)
        # two serialized edits to CURRENT_STATE.md sharing the SAME anchor -> overlap
        anchor = {"type": "heading", "heading": "## Next expected action"}
        m["operations"].append({
            "op_id": "cs-dup",
            "kind": "replace_section",
            "target": "core-docs/CURRENT_STATE.md",
            "semantic_owner": "frontier",
            "eol": "crlf",
            "region_anchor": anchor,
            "precondition": {"basis": "native-raw", "sha256": "8" * 64},
            "postcondition": None,
            "payload_ref": "x",
            "task_spec": {"goal": "dup"},
            "depends_on": ["replace-cs-next"],
        })
        m["operations"].append({
            "op_id": "grade-cs-dup",
            "kind": "validator",
            "validator_id": "independent-grader:cs-dup",
            "semantic_owner": "deterministic",
            "payload_ref": {"predicate": "x"},
            "depends_on": ["cs-dup"],
        })
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "identical region_anchor"), f)

    def test_missing_anchor(self):
        m = copy.deepcopy(self.base)
        del self._ops(m)["replace-cs-next"]["region_anchor"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "requires a region_anchor object"), f)

    def test_content_missing_eol(self):
        m = copy.deepcopy(self.base)
        del self._ops(m)["replace-cs-next"]["eol"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "content op requires eol"), f)

    def test_frontier_missing_task_spec(self):
        m = copy.deepcopy(self.base)
        del self._ops(m)["replace-cs-next"]["task_spec"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "requires a task_spec"), f)

    def test_unresolved_depends_on(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["rebuild-map"]["depends_on"].append("does-not-exist")
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "unknown op_id"), f)

    def test_nothing_depends_on_mirror(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["stamp-map-sha"]["depends_on"].append("mirror-github")
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "mirrors are post-SEAL terminal"), f)

    def test_bad_base_head(self):
        m = copy.deepcopy(self.base)
        m["header"]["base_head"] = "ZZZ"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "base_head must be"), f)

    def test_validator_missing_id(self):
        m = copy.deepcopy(self.base)
        del self._ops(m)["val-consistency"]["validator_id"]
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "validator requires validator_id"), f)

    # ---- INV-15 artifact classification (projection / backing) ----
    def test_projection_requires_budget_and_backing(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["doc_class"] = "projection"  # no budget_bytes / backing_ref
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "doc_class=projection requires budget_bytes"), f)
        self.assertTrue(findings_contain(f, "doc_class=projection requires backing_ref"), f)

    def test_valid_projection_ok(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["replace-cs-next"]
        op["doc_class"] = "projection"
        op["budget_bytes"] = 10000
        op["backing_ref"] = "ops/close-txn/spec/"
        self.assertEqual(vm.validate(m), [])  # a well-formed projection adds no finding

    def test_backing_forbids_budget(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["replace-cs-next"]
        op["doc_class"] = "backing"
        op["budget_bytes"] = 10000
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "doc_class=backing must NOT carry budget_bytes"), f)

    def test_backing_forbids_boot_read(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["replace-cs-next"]
        op["doc_class"] = "backing"
        op["boot_read"] = True
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "doc_class=backing must NOT be marked a bootstrap"), f)


class I63Hardening(unittest.TestCase):
    """i63 (D-0162): path safety, classification strictness, and fail-closed missing edit targets."""

    def setUp(self):
        self.base = load("canonical-close.json")
        self.assertEqual(vm.validate(self.base), [])

    def _ops(self, m):
        return {o["op_id"]: o for o in m["operations"]}

    def test_target_repo_escape(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["target"] = "../../etc/passwd"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, ".target unsafe"), f)

    def test_target_windows_drive(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["target"] = "C:/Windows/system32/x.md"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "Windows drive"), f)

    def test_backing_ref_repo_escape(self):
        m = copy.deepcopy(self.base)
        op = self._ops(m)["replace-cs-next"]
        op["doc_class"] = "projection"
        op["budget_bytes"] = 10000
        op["backing_ref"] = "../../secret"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "backing_ref unsafe"), f)

    def test_payload_ref_repo_escape(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["payload_ref"] = "..\\..\\evil.md"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "payload_ref unsafe"), f)

    def test_unknown_doc_class(self):
        m = copy.deepcopy(self.base)
        self._ops(m)["replace-cs-next"]["doc_class"] = "sidecar"
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "doc_class 'sidecar' is unknown"), f)

    def test_projection_fields_without_classification(self):
        m = copy.deepcopy(self.base)
        # budget_bytes on an op that is NOT doc_class=projection is a mis-declaration
        self._ops(m)["replace-cs-next"]["budget_bytes"] = 5000
        f = vm.validate(m)
        self.assertTrue(findings_contain(f, "projection fields require the projection classification"), f)

    def test_missing_target_repo_fails_closed(self):
        # resolve_anchor_spans against a repo dir: an append/replace_section on an ABSENT file is a HARD
        # finding, not an anchor-check SKIP (Amd2.2).
        import tempfile
        repo = tempfile.mkdtemp(prefix="vm-repo-")
        try:
            findings = vm.resolve_anchor_spans(self.base, repo)
            hard = [x for x in findings if not x.startswith("anchor-check SKIP")]
            self.assertTrue(any("does not exist under --repo" in x for x in hard), findings)
        finally:
            import shutil
            shutil.rmtree(repo, ignore_errors=True)

    def test_created_target_is_deferred_not_failed(self):
        # a target that a create op in the SAME manifest produces is a deferred SKIP, not a hard fail
        import tempfile
        m = copy.deepcopy(self.base)
        m["operations"].append({
            "op_id": "make-new", "kind": "create", "target": "core-docs/NEWDOC.md",
            "semantic_owner": "deterministic", "eol": "lf", "precondition": "absent",
            "payload_ref": "runtime/new.md", "depends_on": [],
        })
        m["operations"].append({
            "op_id": "app-new", "kind": "append", "target": "core-docs/NEWDOC.md",
            "semantic_owner": "deterministic", "eol": "lf",
            "region_anchor": {"type": "append_below", "marker": "<!-- t -->"},
            "precondition": {"basis": "native-raw", "sha256": "a" * 64},
            "payload_ref": "runtime/app.md", "depends_on": ["make-new"],
        })
        repo = tempfile.mkdtemp(prefix="vm-repo-")
        try:
            findings = vm.resolve_anchor_spans(m, repo)
            self.assertTrue(any("created earlier in this manifest" in x for x in findings), findings)
            self.assertFalse(any("app-new" in x and "does not exist" in x for x in findings), findings)
        finally:
            import shutil
            shutil.rmtree(repo, ignore_errors=True)


class Helpers(unittest.TestCase):
    def test_is_monotonic(self):
        self.assertTrue(vm.is_monotonic("core-docs/DECISION_LOG.md"))
        self.assertTrue(vm.is_monotonic("core-docs/DECISION_LOG_INDEX.md"))
        self.assertTrue(vm.is_monotonic("ops/out/retrieval-bytes-log.jsonl"))
        self.assertFalse(vm.is_monotonic("core-docs/CURRENT_STATE.md"))
        self.assertFalse(vm.is_monotonic(None))

    def test_reachable(self):
        m = load("canonical-close.json")
        by_id = {o["op_id"]: o for o in m["operations"]}
        self.assertTrue(vm._reachable("grade-dlog", "append-dlog", by_id))
        self.assertFalse(vm._reachable("append-dlog", "grade-dlog", by_id))


class CLI(unittest.TestCase):
    def test_exit0_valid(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = vm.main([os.path.join(EXAMPLES, "canonical-close.json")])
        self.assertEqual(rc, 0)
        self.assertIn("VALID", buf.getvalue())

    def test_exit2_missing_file(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = vm.main([os.path.join(EXAMPLES, "does-not-exist.json")])
        self.assertEqual(rc, 2)

    def test_exit1_invalid(self):
        # a SHIPPED static negative example (no temp-file write/delete: robust on the delete-less mount VM
        # and the native executor alike). negative-missing-ledger.json omits header.ledger_ref (INV-4).
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = vm.main([os.path.join(EXAMPLES, "negative-missing-ledger.json")])
        self.assertEqual(rc, 1)
        self.assertIn("INVALID", buf.getvalue())
        self.assertIn("ledger_ref is MANDATORY", buf.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
