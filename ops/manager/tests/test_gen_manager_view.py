#!/usr/bin/env python3
"""Unit tests for ops/manager/gen-manager-view.py (cloud gate, run before -Live).

Covers: rollup arithmetic, PB '## Open' parsing, the COUNTS assertion, --check drift, and the size
cap degrade ladder. Run:  python3 ops/manager/tests/test_gen_manager_view.py
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_PATH = os.path.join(HERE, "..", "gen-manager-view.py")
REAL_MAP_DIR = os.path.join(HERE, "..", "..", "..", "modules", "44-project-map", "map")
REAL_PB_PATH = os.path.join(HERE, "..", "..", "..", "core-docs", "PROCESS_BACKLOG.md")

spec = importlib.util.spec_from_file_location("gen_manager_view", MODULE_PATH)
gmv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gmv)


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)


def make_fixture_repo(tmpdir, extra_pb_rows=0, huge_items=0):
    """A minimal synthetic repo: modules/44-project-map/map/{entities,overlay} + core-docs/
    PROCESS_BACKLOG.md, small and hand-computable, plus knobs to force the size-cap ladder."""
    map_dir = os.path.join(tmpdir, "modules", "44-project-map", "map")
    ent_dir = os.path.join(map_dir, "entities")

    _write_json(os.path.join(ent_dir, "planes.json"), {"items": [
        {"id": "plane:memory"}, {"id": "plane:intelligence"}, {"id": "plane:capability"},
        {"id": "plane:authority"}, {"id": "plane:observability"},
    ]})

    modules_items = [
        {"id": "module:01/a", "plane_primary": "memory", "status": "mvp-complete"},
        {"id": "module:02/b", "plane_primary": "memory", "status": "mvp-complete"},
        {"id": "module:03/c", "plane_primary": "intelligence", "status": "deferred"},
        {"id": "module:04/d", "plane_primary": "capability", "status": "in-progress"},
        {"id": "module:05/e", "plane_primary": "authority", "status": "design-only"},
        {"id": "module:06/f", "plane_primary": "observability", "status": "mvp-complete"},
        {"id": "module:07/g", "plane_primary": "memory"},  # no status -> no-status bucket
    ]
    for i in range(huge_items):
        modules_items.append({
            "id": "module:huge/%d" % i, "plane_primary": "capability", "status": "mvp-complete",
            "one_line": "x" * 400,
        })
    _write_json(os.path.join(ent_dir, "modules.json"), {"items": modules_items})
    _write_json(os.path.join(ent_dir, "widgets.json"), {"items": [
        {"id": "widget:01/w", "plane_primary": "observability", "status": "mvp-complete"},
    ]})
    _write_json(os.path.join(ent_dir, "meta.json"), {"items": [
        {"id": "decision:D-0001", "one_line": "not plane-tagged, must not enter the rollup"},
    ]})

    _write_json(os.path.join(map_dir, "overlay", "state.json"), {
        "iteration": 12,
        "phase": {"text": "test phase"},
        "frontier": {"next_iteration": 13, "summary": "test frontier one-liner",
                     "candidates": [{"gate": "OPEN", "item": "candidate one", "pointer": "doc:x"}]},
        "prohibitions": [
            {"authority": "decision:D-1", "status": "live", "text": "live prohibition A"},
            {"authority": "decision:D-2", "status": "retired", "text": "retired, must not count"},
        ],
        "open_rulings": [
            {"ref": "decision:D-0132", "text": "SEALED_CHECK_47 test ruling text"},
            {"ref": "decision:D-9", "text": "some other open ruling"},
        ],
    })

    core = os.path.join(tmpdir, "core-docs")
    os.makedirs(core, exist_ok=True)
    pb_rows = "\n".join(
        "| PB-%d | item %d **bold** text %s | trigger %d %s | D-000%d |" %
        (i, i, "y" * 250 if extra_pb_rows else "", i, "z" * 200 if extra_pb_rows else "", i)
        for i in range(1, 3 + extra_pb_rows)
    )
    with open(os.path.join(core, "PROCESS_BACKLOG.md"), "w", encoding="utf-8") as fh:
        fh.write("# PROCESS_BACKLOG\n\n## Open\n\n| id | item | trigger | D-ref |\n|---|---|---|---|\n"
                  + pb_rows + "\n\n## Closed\n\n| id | item | closed |\n|---|---|---|\n"
                  "| PB-0 | closed row -- must NOT be counted | DONE |\n")
    with open(os.path.join(core, "SEALED_CHECK_47.md"), "w", encoding="utf-8") as fh:
        fh.write("sealed\n")
    return map_dir, os.path.join(core, "PROCESS_BACKLOG.md"), os.path.join(core, "SEALED_CHECK_47.md")


class RollupArithmeticTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.map_dir, self.pb_path, self.sealed = make_fixture_repo(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_plane_rollup_counts_and_buckets(self):
        entities = gmv.load_entities(self.map_dir)
        rollup = gmv.plane_rollup(entities)
        self.assertEqual(rollup["plane:memory"],
                          {"mvp-complete": 2, "design-only": 0, "deferred": 0, "in-progress": 0, "no-status": 1})
        self.assertEqual(rollup["plane:intelligence"]["deferred"], 1)
        self.assertEqual(rollup["plane:capability"]["in-progress"], 1)
        self.assertEqual(rollup["plane:authority"]["design-only"], 1)
        # observability: module f (mvp-complete) + widget w (mvp-complete) = 2
        self.assertEqual(rollup["plane:observability"]["mvp-complete"], 2)
        # decision:D-0001 in meta.json has no plane_primary -> must not appear anywhere
        total_entities_in_rollup = sum(sum(c.values()) for c in rollup.values())
        self.assertEqual(total_entities_in_rollup, 8)  # 7 modules + 1 widget

    def test_module_count_is_module_prefix_only(self):
        entities = gmv.load_entities(self.map_dir)
        self.assertEqual(gmv.count_modules(entities), 7)  # widgets/decisions excluded

    def test_plane_count(self):
        self.assertEqual(gmv.count_planes(self.map_dir), 5)

    def test_plane_order_fixed_then_unknown_sorted(self):
        rollup = {"plane:capability": {}, "plane:memory": {}, "plane:zzz-new": {}}
        self.assertEqual(gmv.plane_order(rollup), ["plane:memory", "plane:capability", "plane:zzz-new"])


class PBParseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.map_dir, self.pb_path, self.sealed = make_fixture_repo(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_open_rows_parsed_excludes_closed(self):
        rows = gmv.parse_open_pb_rows(self.pb_path)
        self.assertEqual([r["id"] for r in rows], ["PB-1", "PB-2"])
        self.assertNotIn("PB-0", [r["id"] for r in rows])

    def test_markdown_emphasis_stripped(self):
        rows = gmv.parse_open_pb_rows(self.pb_path)
        self.assertIn("item 1 bold text", rows[0]["item"])
        self.assertNotIn("**", rows[0]["item"])

    def test_missing_open_section_raises(self):
        bad = os.path.join(self.tmp, "no-open.md")
        with open(bad, "w", encoding="utf-8") as fh:
            fh.write("# doc\n## Closed\n| id | item | closed |\n|---|---|---|\n")
        with self.assertRaises(gmv.GenError):
            gmv.parse_open_pb_rows(bad)


class CountsAssertionAndRenderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.map_dir, self.pb_path, self.sealed = make_fixture_repo(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_counts_line_matches_map(self):
        body = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertIn("COUNTS: modules=7 | planes=5 | open_pb=2", body)

    def test_frontier_and_iteration_present_and_never_dropped_by_cap(self):
        body = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertIn("iteration: 12 (frontier -> 13)", body)
        self.assertIn("test frontier one-liner", body)

    def test_double_run_byte_identical(self):
        b1 = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        b2 = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertEqual(b1, b2)
        self.assertEqual(b1.encode("utf-8"), b2.encode("utf-8"))

    def test_lf_only_no_cr(self):
        body = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertNotIn("\r", body)

    def test_live_prohibitions_excludes_non_live(self):
        body = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertIn("live prohibitions: 1 | open rulings: 2", body)
        self.assertIn("live prohibition A", body)
        self.assertNotIn("retired, must not count", body)

    def test_sealed_check_line_sources_d0132_ruling(self):
        body = gmv.render(self.map_dir, self.pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
        self.assertIn("SEALED_CHECK_47 test ruling text", body)


class CheckDriftTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.map_dir, self.pb_path, self.sealed = make_fixture_repo(self.tmp)
        self.out = os.path.join(self.tmp, "ops", "manager", "generated", "MANAGER_VIEW.md")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, args):
        return gmv.main(args)

    def test_check_passes_after_fresh_render(self):
        rc = self._run(["--repo", self.tmp, "--date", "2026-01-01"])
        self.assertEqual(rc, 0)
        rc = self._run(["--repo", self.tmp, "--date", "2026-01-01", "--check"])
        self.assertEqual(rc, 0)

    def test_check_fails_on_missing_file(self):
        rc = self._run(["--repo", self.tmp, "--date", "2026-01-01", "--check"])
        self.assertEqual(rc, 1)

    def test_check_fails_after_one_byte_mutation(self):
        self._run(["--repo", self.tmp, "--date", "2026-01-01"])
        with open(self.out, "r+", encoding="utf-8") as fh:
            content = fh.read()
            fh.seek(0)
            fh.write(content.replace("COUNTS:", "XOUNTS:", 1))
            fh.truncate()
        rc = self._run(["--repo", self.tmp, "--date", "2026-01-01", "--check"])
        self.assertEqual(rc, 1)


class SizeCapTests(unittest.TestCase):
    def test_over_cap_degrades_and_stays_under(self):
        tmp = tempfile.mkdtemp()
        try:
            map_dir, pb_path, sealed = make_fixture_repo(tmp, extra_pb_rows=40, huge_items=40)
            body = gmv.render(map_dir, pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
            self.assertLessEqual(len(body.encode("utf-8")), gmv.SIZE_CAP_BYTES)
            self.assertIn("degraded:", body)
            # never-drop invariants
            self.assertRegex(body, r"COUNTS: modules=\d+ \| planes=5 \| open_pb=\d+")
            self.assertIn("test frontier one-liner", body)
            self.assertIn("candidate one", body)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_under_cap_untouched_no_degrade_note(self):
        tmp = tempfile.mkdtemp()
        try:
            map_dir, pb_path, sealed = make_fixture_repo(tmp)
            body = gmv.render(map_dir, pb_path, "core-docs/SEALED_CHECK_47.md", "2026-01-01")
            self.assertNotIn("degraded:", body)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class RealMapParityTests(unittest.TestCase):
    """-Live-shaped: run the generator against the ACTUAL repo map mirrored into this cloud sandbox
    (staged from the real box). Confirms the reference figures cited in FANOUT_AGENT_003's ACCEPTANCE
    section are re-derived, not hardcoded."""

    def setUp(self):
        if not os.path.isdir(REAL_MAP_DIR):
            self.skipTest("real map not staged in this sandbox")

    def test_reference_plane_counts(self):
        entities = gmv.load_entities(REAL_MAP_DIR)
        rollup = gmv.plane_rollup(entities)
        totals = {gmv._plane_short(k): sum(v.values()) for k, v in rollup.items()}
        self.assertEqual(totals.get("memory"), 15)
        self.assertEqual(totals.get("intelligence"), 8)
        self.assertEqual(totals.get("capability"), 43)
        self.assertEqual(totals.get("authority"), 6)
        self.assertEqual(totals.get("observability"), 7)

    def test_module_and_plane_counts(self):
        entities = gmv.load_entities(REAL_MAP_DIR)
        self.assertEqual(gmv.count_modules(entities), 47)
        self.assertEqual(gmv.count_planes(REAL_MAP_DIR), 5)

    def test_real_render_under_cap_and_double_run_identical(self):
        body1 = gmv.render(REAL_MAP_DIR, REAL_PB_PATH, "core-docs/SEALED_CHECK_47.md", "2026-08-16")
        body2 = gmv.render(REAL_MAP_DIR, REAL_PB_PATH, "core-docs/SEALED_CHECK_47.md", "2026-08-16")
        self.assertEqual(body1, body2)
        self.assertLessEqual(len(body1.encode("utf-8")), gmv.SIZE_CAP_BYTES)


if __name__ == "__main__":
    unittest.main(verbosity=2)
