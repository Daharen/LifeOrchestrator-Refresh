#!/usr/bin/env python3
"""Off-box unit + CLI tests for the i60 B upgrade to ops/audit/gen-retrieval-monitor.py
(FANOUT_AGENT_001 / II-BOUND-i60): the --gate fail-closed assertion and the --artifacts-dir cross-check.
Pure stdlib (unittest + subprocess + tempfile). Run: python ops/audit/tests/test_retrieval_gate_crosscheck.py

These are ADDITIVE -- the i55 suite (test_retrieval_byte_monitor.py) still guards the base schema, the
ledger validation, and the default-invocation double-run byte-identity. This file guards only the new
opt-in behavior + that it never perturbs a default run.
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
FIXDIR = os.path.join(HERE, "fixtures")
ALLWHOLE = os.path.join(FIXDIR, "retrieval-ledger-allwhole.jsonl")
MIXED = os.path.join(FIXDIR, "retrieval-ledger-mixed.jsonl")


def load_module():
    spec = importlib.util.spec_from_file_location("gen_retrieval_monitor_gate_ut", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()


def run_cli(args, cwd=None):
    return subprocess.run([sys.executable, SCRIPT] + args, capture_output=True, text=True, cwd=cwd)


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path


def envelope(result, status="ok"):
    """Mimic project.map's emitted single-line envelope (json.dumps(env)+'\\n')."""
    env = {"schema": "lifeorch.skill.result/0.1", "skill_id": "project.map", "skill_version": "0.4.0",
           "contract_version": "0.2", "invocation_id": "cli", "status": status,
           "started_at_utc": "2026-08-16T10:00:00.1Z", "finished_at_utc": "2026-08-16T10:00:00.2Z",
           "duration_ms": None, "inputs_digest": None, "result": result, "confidence": None,
           "artifacts": [], "model_provenance": [], "diagnostics": {}, "warnings": [], "error": None}
    return json.dumps(env) + "\n"


def make_artifact(base, artifact_id, envelope_text):
    d = os.path.join(base, artifact_id)
    os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "result.json"), envelope_text)
    return d


# ------------------------------------------------------------------------------------------------
class GateUnitTest(unittest.TestCase):
    def test_gate_tripped_true_when_whole_open_and_zero_bounded(self):
        entries = MOD.parse_ledger(ALLWHOLE)
        row = MOD.compute_row(entries, "2026-08-16", 60, "x.jsonl")
        self.assertTrue(MOD.gate_tripped(row))

    def test_gate_tripped_false_with_one_bounded(self):
        entries = MOD.parse_ledger(MIXED)
        row = MOD.compute_row(entries, "2026-08-16", 60, "x.jsonl")
        self.assertFalse(MOD.gate_tripped(row))

    def test_gate_tripped_false_on_empty_ledger(self):
        row = MOD.compute_row([], "2026-08-16", 60, "x.jsonl")
        self.assertFalse(MOD.gate_tripped(row))

    def test_gate_tripped_false_boot_packet_only(self):
        entries = [{"kind": "boot_packet", "target": "bp", "bytes": 18000, "note": None}]
        row = MOD.compute_row(entries, "2026-08-16", 60, "x.jsonl")
        self.assertFalse(MOD.gate_tripped(row))  # nothing whole-opened -> nothing to object to

    def test_gate_field_present_only_when_gate_true(self):
        entries = MOD.parse_ledger(MIXED)
        self.assertNotIn("gate", MOD.compute_row(entries, "d", 60, "x"))
        self.assertEqual(MOD.compute_row(entries, "d", 60, "x", gate=True)["gate"],
                         {"status": "pass", "reason": None})


class GateCliTest(unittest.TestCase):
    def test_gate_rejects_all_whole_open_exit1_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            p = run_cli(["--ledger", ALLWHOLE, "--iteration", "60", "--date", "2026-08-16",
                         "--out-dir", d, "--gate"])
            self.assertEqual(p.returncode, 1, p.stderr)
            self.assertIn(MOD.GATE_ZERO_BOUNDED, p.stdout)   # machine reason on stdout
            reason = json.loads(p.stdout.strip().splitlines()[0])
            self.assertEqual(reason["gate"], "zero_bounded_opens")
            self.assertEqual(reason["bounded_query_bytes"], 0)
            self.assertGreater(reason["whole_doc_open_bytes"], 0)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_gate_passes_with_one_bounded_exit0_writes_row(self):
        with tempfile.TemporaryDirectory() as d:
            p = run_cli(["--ledger", MIXED, "--iteration", "60", "--date", "2026-08-16",
                         "--out-dir", d, "--gate"])
            self.assertEqual(p.returncode, 0, p.stderr)
            with open(os.path.join(d, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                row = json.loads(fh.readline())
            self.assertEqual(row["gate"], {"status": "pass", "reason": None})

    def test_no_gate_flag_never_rejects_on_zero_bounded(self):
        # backward compat: without --gate the all-whole-open ledger still writes a row + exit 0.
        with tempfile.TemporaryDirectory() as d:
            p = run_cli(["--ledger", ALLWHOLE, "--iteration", "60", "--out-dir", d])
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertTrue(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_gate_reject_preserves_existing_log(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "retrieval-bytes-log.jsonl")
            write(log, '{"prior":"row"}\n')
            p = run_cli(["--ledger", ALLWHOLE, "--iteration", "60", "--out-dir", d, "--gate"])
            self.assertEqual(p.returncode, 1)
            with open(log, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), '{"prior":"row"}\n')

    def test_gate_still_rejects_bad_ledger_first(self):
        # a malformed ledger is rejected by parse (exit 1) regardless of --gate; nothing written.
        with tempfile.TemporaryDirectory() as d:
            bad = write(os.path.join(d, "bad.jsonl"), '{"kind":"nope","target":"x","bytes":1}\n')
            p = run_cli(["--ledger", bad, "--iteration", "60", "--out-dir", d, "--gate"])
            self.assertEqual(p.returncode, 1)
            self.assertIn("REJECTED", p.stderr)


# ------------------------------------------------------------------------------------------------
class CrossCheckTest(unittest.TestCase):
    def _fixture_pair(self, base):
        """A ledger + an artifacts dir engineered to yield EXACTLY one unbacked + one unrecorded."""
        ledger = write(os.path.join(base, "ledger.jsonl"),
                       '{"kind":"card","target":"card:module:40","bytes":420}\n'
                       '{"kind":"query","target":"entity:module:36/artifact.search","bytes":338}\n')
        art = os.path.join(base, "artifacts")
        # BACKED: artifact q matches the card ledger target
        make_artifact(art, "a1", envelope({"q": "card:module:40", "card": {"id": "module:40"}}))
        # UNRECORDED: a query artifact with no matching ledger target
        make_artifact(art, "a2", envelope({"q": "entity:module:44/project.map", "entity": {"id": "x"}}))
        # NON-QUERY artifact (validate result, no q) -> ignored, not unrecorded
        make_artifact(art, "a3", envelope({"ok": True, "error_count": 0, "findings": []}))
        # MALFORMED artifact -> unparseable, skipped (counted)
        make_artifact(art, "a4", "{ this is not json")
        # (the ledger's 'entity:module:36/artifact.search' target has NO artifact -> unbacked)
        return ledger, art

    def test_flags_one_unbacked_one_unrecorded(self):
        with tempfile.TemporaryDirectory() as d:
            ledger, art = self._fixture_pair(d)
            entries = MOD.parse_ledger(ledger)
            cc = MOD.cross_check(entries, [art])
            self.assertEqual(cc["unbacked"], ["entity:module:36/artifact.search"])
            self.assertEqual(cc["unrecorded"], ["entity:module:44/project.map"])

    def test_non_query_artifact_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            _ledger, art = self._fixture_pair(d)
            cc = MOD.cross_check([], [art])
            # a3 (validate) contributes no q; only a1,a2 are query artifacts.
            self.assertEqual(cc["query_artifacts"], 2)

    def test_scanned_and_unparseable_counts(self):
        with tempfile.TemporaryDirectory() as d:
            _ledger, art = self._fixture_pair(d)
            cc = MOD.cross_check([], [art])
            self.assertEqual(cc["artifacts_scanned"], 4)
            self.assertEqual(cc["unparseable"], 1)

    def test_deterministic_sorted(self):
        with tempfile.TemporaryDirectory() as d:
            ledger, art = self._fixture_pair(d)
            entries = MOD.parse_ledger(ledger)
            self.assertEqual(MOD.cross_check(entries, [art]), MOD.cross_check(entries, [art]))

    def test_missing_dir_is_empty_not_error(self):
        cc = MOD.cross_check([], [os.path.join(tempfile.gettempdir(), "no-such-dir-xyz-123")])
        self.assertEqual(cc["artifacts_scanned"], 0)
        self.assertEqual(cc["unrecorded"], [])

    def test_deeply_nested_artifact_counted_unparseable_not_crash(self):
        # i60 red-team RT-A #4: a planted deeply-nested result.json makes json.loads raise RecursionError
        # (NOT ValueError). The scan must count it as unparseable and NOT crash wave-close (DoS).
        with tempfile.TemporaryDirectory() as d:
            art = os.path.join(d, "artifacts")
            make_artifact(art, "good", envelope({"q": "card:module:40", "card": {}}))
            make_artifact(art, "bomb", "[" * 60000 + "]" * 60000)
            cc = MOD.cross_check([], [art])              # must not raise
            self.assertEqual(cc["artifacts_scanned"], 2)
            self.assertEqual(cc["unparseable"], 1)
            self.assertEqual(cc["query_artifacts"], 1)

    def test_cross_check_field_present_only_with_flag(self):
        entries = MOD.parse_ledger(MIXED)
        self.assertNotIn("cross_check", MOD.compute_row(entries, "d", 60, "x"))
        row = MOD.compute_row(entries, "d", 60, "x", cross_check_result={"unbacked": [], "unrecorded": []})
        self.assertIn("cross_check", row)


class CrossCheckCliTest(unittest.TestCase):
    def test_cli_writes_cross_check_and_exit0(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = write(os.path.join(d, "ledger.jsonl"),
                           '{"kind":"card","target":"card:module:40","bytes":420}\n')
            art = os.path.join(d, "artifacts")
            make_artifact(art, "a1", envelope({"q": "card:module:40", "card": {"id": "m40"}}))
            make_artifact(art, "a2", envelope({"q": "card:module:99", "card": {"id": "m99"}}))
            outd = os.path.join(d, "out")
            p = run_cli(["--ledger", ledger, "--iteration", "60", "--date", "2026-08-16",
                         "--out-dir", outd, "--artifacts-dir", art])
            self.assertEqual(p.returncode, 0, p.stderr)
            with open(os.path.join(outd, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                row = json.loads(fh.readline())
            self.assertIn("cross_check", row)
            self.assertEqual(row["cross_check"]["unbacked"], [])
            self.assertEqual(row["cross_check"]["unrecorded"], ["card:module:99"])

    def test_two_artifact_dirs_repeatable_flag(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = write(os.path.join(d, "ledger.jsonl"),
                           '{"kind":"card","target":"card:module:40","bytes":420}\n')
            art1 = os.path.join(d, "fanout")
            art2 = os.path.join(d, "map")
            make_artifact(art1, "b1", envelope({"q": "card:module:40", "card": {}}))
            make_artifact(art2, "b2", envelope({"q": "card:module:41", "card": {}}))
            outd = os.path.join(d, "out")
            p = run_cli(["--ledger", ledger, "--iteration", "60", "--out-dir", outd,
                         "--artifacts-dir", art1, "--artifacts-dir", art2])
            self.assertEqual(p.returncode, 0, p.stderr)
            with open(os.path.join(outd, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                row = json.loads(fh.readline())
            self.assertEqual(row["cross_check"]["artifacts_scanned"], 2)
            self.assertEqual(row["cross_check"]["unrecorded"], ["card:module:41"])


class DoubleRunDeterminismTest(unittest.TestCase):
    def test_gate_and_crosscheck_row_byte_identical(self):
        with tempfile.TemporaryDirectory() as base:
            art = os.path.join(base, "artifacts")
            make_artifact(art, "a1", envelope({"q": "card:module:40", "card": {"id": "m40"}}))
            make_artifact(art, "a2", envelope({"q": "card:module:99", "card": {"id": "m99"}}))

            def run(outd):
                r = run_cli(["--ledger", MIXED, "--iteration", "60", "--date", "2026-08-16",
                             "--out-dir", outd, "--gate", "--artifacts-dir", art])
                self.assertEqual(r.returncode, 0, r.stderr)
                with open(os.path.join(outd, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                    return fh.readline()

            with tempfile.TemporaryDirectory() as d1, tempfile.TemporaryDirectory() as d2:
                self.assertEqual(run(d1), run(d2))


class FractionGateUnitTest(unittest.TestCase):
    """i61 (D-0158) meaningful-fraction gate: discretionary_bounded_fraction + fraction_gate_tripped."""
    def test_discretionary_field_is_opt_in(self):
        entries = MOD.parse_ledger(MIXED)
        self.assertNotIn("discretionary_bounded_fraction", MOD.compute_row(entries, "d", 60, "x"))
        r = MOD.compute_row(entries, "d", 61, "x", min_bounded_fraction=0.8)
        self.assertIn("discretionary_bounded_fraction", r)
        self.assertEqual(r["min_bounded_fraction"], 0.8)

    def test_discretionary_excludes_boot_packet(self):
        entries = [{"kind": "boot_packet", "target": "bp", "bytes": 18000, "note": None},
                   {"kind": "whole_doc_open", "target": "d", "bytes": 1000, "note": None},
                   {"kind": "query", "target": "q", "bytes": 9000, "note": None}]
        r = MOD.compute_row(entries, "d", 61, "x", min_bounded_fraction=0.8)
        self.assertEqual(r["discretionary_bounded_fraction"], 0.9)  # 9000/(9000+1000), boot excluded

    def test_fraction_gate_trips_below_and_on_zero_bounded(self):
        low = MOD.compute_row([{"kind": "whole_doc_open", "target": "d", "bytes": 9000, "note": None},
                               {"kind": "query", "target": "q", "bytes": 1000, "note": None}],
                              "d", 61, "x", min_bounded_fraction=0.8)
        self.assertTrue(MOD.fraction_gate_tripped(low, 0.8))    # 0.1 < 0.8
        self.assertFalse(MOD.fraction_gate_tripped(low, 0.05))  # 0.1 >= 0.05
        zero = MOD.compute_row([{"kind": "whole_doc_open", "target": "d", "bytes": 9000, "note": None}],
                               "d", 61, "x", min_bounded_fraction=0.8)
        self.assertTrue(MOD.fraction_gate_tripped(zero, 0.8))   # no bounded at all

    def test_fraction_gate_passes_high(self):
        hi = MOD.compute_row([{"kind": "whole_doc_open", "target": "d", "bytes": 1000, "note": None},
                              {"kind": "query", "target": "q", "bytes": 9000, "note": None}],
                             "d", 61, "x", min_bounded_fraction=0.8)
        self.assertFalse(MOD.fraction_gate_tripped(hi, 0.8))    # 0.9 >= 0.8


class FractionGateCliTest(unittest.TestCase):
    def _ledger(self, d, bounded, whole):
        parts = []
        if whole:   parts.append('{"kind":"whole_doc_open","target":"doc","bytes":%d}' % whole)
        if bounded: parts.append('{"kind":"query","target":"q:x","bytes":%d}' % bounded)
        return write(os.path.join(d, "l.jsonl"), "\n".join(parts) + "\n")

    def test_cli_rejects_below_threshold_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            led = self._ledger(d, 1000, 9000)  # discretionary fraction 0.1
            p = run_cli(["--ledger", led, "--iteration", "61", "--out-dir", d, "--gate",
                         "--min-bounded-fraction", "0.8"])
            self.assertEqual(p.returncode, 1, p.stderr)
            self.assertIn(MOD.GATE_BELOW_MIN_FRACTION, p.stdout)
            reason = json.loads(p.stdout.strip().splitlines()[0])
            self.assertEqual(reason["gate"], "below_min_bounded_fraction")
            self.assertEqual(reason["discretionary_bounded_fraction"], 0.1)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_cli_passes_above_threshold_writes_row(self):
        with tempfile.TemporaryDirectory() as d:
            led = self._ledger(d, 9000, 1000)  # 0.9
            p = run_cli(["--ledger", led, "--iteration", "61", "--out-dir", d, "--gate",
                         "--min-bounded-fraction", "0.8"])
            self.assertEqual(p.returncode, 0, p.stderr)
            with open(os.path.join(d, "retrieval-bytes-log.jsonl"), encoding="utf-8") as fh:
                row = json.loads(fh.readline())
            self.assertEqual(row["discretionary_bounded_fraction"], 0.9)
            self.assertEqual(row["gate"], {"status": "pass", "reason": None})

    def test_check_only_never_writes(self):
        with tempfile.TemporaryDirectory() as d:
            led = self._ledger(d, 9000, 1000)  # passes
            p = run_cli(["--ledger", led, "--iteration", "61", "--out-dir", d, "--gate",
                         "--min-bounded-fraction", "0.8", "--check-only"])
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_check_only_rejects_below_threshold_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            led = self._ledger(d, 1000, 9000)  # fails
            p = run_cli(["--ledger", led, "--iteration", "61", "--out-dir", d, "--gate",
                         "--min-bounded-fraction", "0.8", "--check-only"])
            self.assertEqual(p.returncode, 1)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))

    def test_check_only_rejects_zero_bounded_floor(self):
        with tempfile.TemporaryDirectory() as d:
            led = self._ledger(d, 0, 9000)  # zero bounded, whole-doc present
            p = run_cli(["--ledger", led, "--iteration", "61", "--out-dir", d, "--gate", "--check-only"])
            self.assertEqual(p.returncode, 1)
            self.assertFalse(os.path.exists(os.path.join(d, "retrieval-bytes-log.jsonl")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
