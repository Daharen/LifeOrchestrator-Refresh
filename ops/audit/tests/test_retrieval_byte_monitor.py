#!/usr/bin/env python3
"""Off-box unit + CLI tests for ops/audit/gen-retrieval-monitor.py (i55, FANOUT_AGENT_002).
Pure stdlib (unittest + subprocess). Run: python ops/audit/tests/test_retrieval_byte_monitor.py
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT_DIR = os.path.dirname(HERE)
SCRIPT = os.path.join(AUDIT_DIR, "gen-retrieval-monitor.py")
FIXTURE = os.path.join(HERE, "fixtures", "retrieval-ledger-fixture.jsonl")


def load_module():
    spec = importlib.util.spec_from_file_location("gen_retrieval_monitor_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()


def run_cli(args, cwd=None):
    return subprocess.run([sys.executable, SCRIPT] + args, capture_output=True, text=True, cwd=cwd)


class ParseLedgerTest(unittest.TestCase):
    def _write(self, dirpath, name, text):
        p = os.path.join(dirpath, name)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        return p

    def test_valid_fixture_parses_all_seven_entries(self):
        entries = MOD.parse_ledger(FIXTURE)
        self.assertEqual(len(entries), 7)
        self.assertEqual(entries[0]["kind"], "boot_packet")

    def test_blank_lines_skipped(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '\n\n{"kind":"query","target":"x","bytes":10}\n\n')
            entries = MOD.parse_ledger(p)
            self.assertEqual(len(entries), 1)

    def test_bad_json_line_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", "{not json}\n")
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_non_object_line_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '["kind","query"]\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_unknown_kind_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"whole_repo_scan","target":"x","bytes":10}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_missing_required_key_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","bytes":10}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_unknown_extra_key_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"x","bytes":10,"session":"s1"}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_zero_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"x","bytes":0}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_negative_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"x","bytes":-5}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_float_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"x","bytes":10.5}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_bool_bytes_rejected(self):
        # bool is a subclass of int in Python -- must be explicitly excluded.
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"x","bytes":true}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_empty_target_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", '{"kind":"query","target":"   ","bytes":10}\n')
            with self.assertRaises(MOD.LedgerError):
                MOD.parse_ledger(p)

    def test_empty_ledger_parses_to_no_entries(self):
        with tempfile.TemporaryDirectory() as d:
            p = self._write(d, "l.jsonl", "")
            self.assertEqual(MOD.parse_ledger(p), [])


class ComputeRowTest(unittest.TestCase):
    def setUp(self):
        self.entries = MOD.parse_ledger(FIXTURE)
        self.row = MOD.compute_row(self.entries, "2026-08-14", 55, "fixtures/retrieval-ledger-fixture.jsonl")

    def test_boot_packet_bytes(self):
        self.assertEqual(self.row["boot_packet_bytes"], 17265)

    def test_boot_packet_bar_pass(self):
        self.assertEqual(self.row["boot_packet_bar"], {"limit_bytes": 20000, "status": "pass"})

    def test_bounded_query_bytes_and_n_queries(self):
        self.assertEqual(self.row["bounded_query_bytes"], 2600 + 1600 + 1900)
        self.assertEqual(self.row["n_queries"], 3)

    def test_whole_doc_open_bytes(self):
        self.assertEqual(self.row["whole_doc_open_bytes"], 20384 + 638000 + 5423)

    def test_total_charged_bytes(self):
        self.assertEqual(self.row["total_charged_bytes"], 17265 + 20384 + 638000 + 5423 + 2600 + 1600 + 1900)

    def test_bounded_fraction(self):
        expected = round(6100 / 687172, 4)
        self.assertEqual(self.row["bounded_fraction"], expected)

    def test_decision_log_flagged_both_reasons(self):
        warn = next(w for w in self.row["warnings"] if w["target"] == "core-docs/DECISION_LOG.md")
        self.assertEqual(sorted(warn["reasons"]), ["cumulative_doc", "over_40kb_threshold"])

    def test_audit_pipeline_not_flagged(self):
        targets_flagged = {w["target"] for w in self.row["warnings"]}
        self.assertNotIn("core-docs/AUDIT_PIPELINE.md", targets_flagged)

    def test_start_here_not_flagged(self):
        targets_flagged = {w["target"] for w in self.row["warnings"]}
        self.assertNotIn("core-docs/START_HERE.md", targets_flagged)

    def test_exactly_one_warning(self):
        self.assertEqual(len(self.row["warnings"]), 1)

    def test_whole_doc_opens_sorted_desc_by_bytes(self):
        sizes = [e["bytes"] for e in self.row["whole_doc_opens"]]
        self.assertEqual(sizes, sorted(sizes, reverse=True))

    def test_ledger_entries_count(self):
        self.assertEqual(self.row["ledger_entries"], 7)

    def test_empty_ledger_bounded_fraction_is_none(self):
        row = MOD.compute_row([], "2026-08-14", 55, "empty.jsonl")
        self.assertIsNone(row["bounded_fraction"])
        self.assertEqual(row["total_charged_bytes"], 0)
        self.assertEqual(row["warnings"], [])

    def test_boot_packet_bar_warn_when_over_n4_bar(self):
        entries = [{"kind": "boot_packet", "target": "x", "bytes": 20001, "note": None}]
        row = MOD.compute_row(entries, "2026-08-14", 55, "x.jsonl")
        self.assertEqual(row["boot_packet_bar"]["status"], "warn")

    def test_over_40kb_non_cumulative_doc_flagged(self):
        entries = [{"kind": "whole_doc_open", "target": "core-docs/MEMORY_CONTRACT.md",
                    "bytes": 48000, "note": None}]
        row = MOD.compute_row(entries, "2026-08-14", 55, "x.jsonl")
        self.assertEqual(len(row["warnings"]), 1)
        self.assertEqual(row["warnings"][0]["reasons"], ["over_40kb_threshold"])


class CliTest(unittest.TestCase):
    def test_missing_ledger_exits_2(self):
        with tempfile.TemporaryDirectory() as d:
            p = run_cli(["--ledger", os.path.join(d, "nope.jsonl"), "--iteration", "55",
                         "--out-dir", d])
            self.assertEqual(p.returncode, 2)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_bad_ledger_exits_1_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = os.path.join(d, "bad.jsonl")
            with open(ledger, "w", encoding="utf-8") as fh:
                fh.write('{"kind":"nonsense","target":"x","bytes":10}\n')
            p = run_cli(["--ledger", ledger, "--iteration", "55", "--out-dir", d])
            self.assertEqual(p.returncode, 1)
            self.assertIn("REJECTED", p.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_bad_ledger_does_not_touch_existing_log(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "retrieval-bytes-log.jsonl")
            with open(log, "w", encoding="utf-8") as fh:
                fh.write('{"prior":"row"}\n')
            ledger = os.path.join(d, "bad.jsonl")
            with open(ledger, "w", encoding="utf-8") as fh:
                fh.write('{"kind":"nonsense","target":"x","bytes":10}\n')
            p = run_cli(["--ledger", ledger, "--iteration", "55", "--out-dir", d])
            self.assertEqual(p.returncode, 1)
            with open(log, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), '{"prior":"row"}\n')

    def test_valid_run_exits_0_and_appends_one_row(self):
        with tempfile.TemporaryDirectory() as d:
            p = run_cli(["--ledger", FIXTURE, "--iteration", "55", "--date", "2026-08-14",
                         "--out-dir", d])
            self.assertEqual(p.returncode, 0, p.stderr)
            log = os.path.join(d, "retrieval-bytes-log.jsonl")
            with open(log, encoding="utf-8") as fh:
                lines = fh.readlines()
            self.assertEqual(len(lines), 1)
            row = json.loads(lines[0])
            self.assertEqual(row["iteration"], 55)
            self.assertEqual(row["date"], "2026-08-14")

    def test_two_runs_append_two_rows(self):
        with tempfile.TemporaryDirectory() as d:
            run_cli(["--ledger", FIXTURE, "--iteration", "55", "--date", "2026-08-14", "--out-dir", d])
            run_cli(["--ledger", FIXTURE, "--iteration", "56", "--date", "2026-08-15", "--out-dir", d])
            log = os.path.join(d, "retrieval-bytes-log.jsonl")
            with open(log, encoding="utf-8") as fh:
                lines = fh.readlines()
            self.assertEqual(len(lines), 2)

    def test_no_date_defaults_to_undated(self):
        with tempfile.TemporaryDirectory() as d:
            run_cli(["--ledger", FIXTURE, "--iteration", "55", "--out-dir", d])
            log = os.path.join(d, "retrieval-bytes-log.jsonl")
            with open(log, encoding="utf-8") as fh:
                row = json.loads(fh.readline())
            self.assertEqual(row["date"], "undated")

    def test_double_run_byte_identical_row(self):
        """The core determinism gate: two independent runs against the SAME fixture ledger, same
        --date/--iteration, produce byte-identical row content (no wall-clock, no PRNG, no ordering
        dependence on filesystem iteration order)."""
        with tempfile.TemporaryDirectory() as d1, tempfile.TemporaryDirectory() as d2:
            p1 = run_cli(["--ledger", FIXTURE, "--iteration", "55", "--date", "2026-08-14",
                          "--out-dir", d1])
            p2 = run_cli(["--ledger", FIXTURE, "--iteration", "55", "--date", "2026-08-14",
                          "--out-dir", d2])
            self.assertEqual(p1.returncode, 0, p1.stderr)
            self.assertEqual(p2.returncode, 0, p2.stderr)
            with open(os.path.join(d1, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                line1 = fh.readline()
            with open(os.path.join(d2, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                line2 = fh.readline()
            self.assertEqual(line1, line2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
