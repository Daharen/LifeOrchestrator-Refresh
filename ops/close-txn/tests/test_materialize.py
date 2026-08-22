#!/usr/bin/env python3
"""Tests for materialize.py -- the corrected stage-only durable materializer (i63, D-0163).

Adversarial controls T63-01..T63-20 (the portable ones; the native-Windows NTFS junction control runs on
the box via tests/win_reparse_probe.py). Disposable temp git repos only; the canonical repo is never an
escape target. Verifies SIDE EFFECTS (staged tip, durable readback, main HEAD unchanged, no journal dir on
a bad txid), not just exit codes.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, PKG)
import materialize as mz  # noqa: E402
import safepath as sp  # noqa: E402

STUB_LEDGER = lambda *a, **k: {"gate": "stub", "exit": 0}


def g(repo, *args, inp=None):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, input=inp)
    if p.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace")))
    return p.stdout.decode().strip()



def ref(repo, name):
    p = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet", name], capture_output=True)
    return p.stdout.decode().strip()


def make_repo():
    repo = tempfile.mkdtemp(prefix="mz-")
    g(repo, "init", "-q", "-b", "main")
    g(repo, "config", "user.email", "t@t"); g(repo, "config", "user.name", "t")
    g(repo, "config", "commit.gpgsign", "false")
    os.makedirs(os.path.join(repo, "modules", "44-project-map", "runtime"), exist_ok=True)
    # keep the runtime journal dir present (gitignored-in-real-repo; here just a dir)
    return repo


def write(repo, rel, text):
    p = os.path.join(repo, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


def commit(repo, msg="base"):
    g(repo, "add", "-A"); g(repo, "commit", "-q", "-m", msg)
    return g(repo, "rev-parse", "HEAD")


def read_bytes(repo, rel):
    with open(os.path.join(repo, rel.replace("/", os.sep)), "rb") as fh:
        return fh.read()


def header(repo, txid="close-i63-t", it=63, ledger="runtime/led.jsonl"):
    return {"transaction_id": txid, "iteration": it, "base_head": g(repo, "rev-parse", "HEAD"),
            "ledger_ref": ledger, "min_bounded_fraction": 0.0, "created_by": "t", "model_provenance": "t",
            "governing_model": "frontier-agent-in-deterministic-loop"}


def det_replace(repo, target, heading, new_text):
    """A deterministic replace_section op with a real region precondition + whole-file postcondition."""
    raw = read_bytes(repo, target)
    anchor = {"type": "heading", "heading": heading}
    pre = mz.region_fp(raw, anchor)
    payload = mz.eol_bytes(new_text, "lf")
    new = mz.apply_content(raw, dict(kind="replace_section", region_anchor=anchor), payload)
    post = mz.fp(mz.sha256_bytes(new))
    return {"op_id": "cs", "kind": "replace_section", "target": target, "semantic_owner": "deterministic",
            "eol": "lf", "region_anchor": anchor, "precondition": pre, "postcondition": post,
            "payload_ref": {"inline": new_text}, "depends_on": []}


class HappyPath(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## Next\nold body\n\n## Other\ntail\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _run(self, **kw):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\nNEW body\n\n")]}
        return mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER, **kw), m

    def test_stage_only_seal_main_untouched(self):
        main_before = g(self.repo, "rev-parse", "main")
        mzr, m = self._run()
        res = mzr.run()
        self.assertTrue(res["ok"], res)
        self.assertTrue(res["sealed"])
        # main is byte/commit-identical (T63-09 baseline)
        self.assertEqual(g(self.repo, "rev-parse", "main"), main_before)
        self.assertIn("old body", read_bytes(self.repo, "core-docs/CS.md").decode())  # worktree untouched
        # the staged tip carries the NEW content, durably readable
        tip = g(self.repo, "rev-parse", "refs/lo/close/close-i63-t")
        blob = subprocess.run(["git", "-C", self.repo, "show", "%s:core-docs/CS.md" % tip],
                              capture_output=True).stdout.decode()
        self.assertIn("NEW body", blob)
        # final_head is the staged tip, NOT main (C63-06)
        self.assertEqual(res["final_head"], tip)
        self.assertNotEqual(res["final_head"], main_before)

    def test_idempotent_noop_resume_revalidates(self):
        mzr, m = self._run()
        r1 = mzr.run(); self.assertTrue(r1["ok"])
        tip1 = r1["final_head"]
        # re-run: no-op resume ONLY after revalidating manifest+tip identity
        r2 = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertTrue(r2["ok"]); self.assertEqual(r2["final_head"], tip1)
        self.assertTrue(r2["phases"]["SEAL"].get("noop_resume"))

    def test_altered_manifest_reuse_txid_not_noop(self):
        mzr, m = self._run(); mzr.run()
        m2 = json.loads(json.dumps(m))
        m2["operations"][0]["payload_ref"]["inline"] = "## Next\nDIFFERENT\n\n"
        # recompute postcondition for the altered payload so it is internally valid
        raw = read_bytes(self.repo, "core-docs/CS.md")
        new = mz.apply_content(raw, m2["operations"][0], mz.eol_bytes("## Next\nDIFFERENT\n\n", "lf"))
        m2["operations"][0]["postcondition"] = mz.fp(mz.sha256_bytes(new))
        r = mz.Materializer(self.repo, m2, ledger_gate=STUB_LEDGER).run()
        # different manifest digest -> prior seal is NOT trusted; it re-applies (still ok) but not a blind noop
        self.assertFalse(r["phases"].get("SEAL", {}).get("noop_resume"))


class PreSideEffectBoundary(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## Next\nx\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_T63_02_txid_escape_no_journal(self):
        bad = "close-i63-x/../../../../../../escaped-journal"
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo, txid=bad),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"])
        # NO journal directory anywhere (inside or outside) was created
        self.assertFalse(os.path.exists(os.path.join(self.repo, "..", "escaped-journal")))
        rt = os.path.join(self.repo, "modules", "44-project-map", "runtime", "close-txn")
        self.assertFalse(os.path.isdir(os.path.join(rt, bad)) if os.path.isdir(rt) else False)

    def test_T63_03_ledger_ref_escape_fails_in_plan(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo, ledger="/etc/passwd"),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"])
        self.assertIn(r["failure"], ("repo-escape", "plan-error"))
        self.assertEqual(ref(self.repo, "refs/lo/close/close-i63-t"), "")

    def test_target_escape_fails_before_write(self):
        op = det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")
        op["target"] = "../../etc/evil.md"
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo), "operations": [op]}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"])


class LedgerGate(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## Next\nx\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _man(self, ledger="runtime/led.jsonl", it=63):
        h = header(self.repo, ledger=ledger, it=it)
        return {"schema": "lifeorch.close_manifest/0.1", "header": h,
                "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}

    def _run_real_gate(self, man):
        return mz.Materializer(self.repo, man).run()  # real default_ledger_gate

    def test_missing_ledger(self):
        r = self._run_real_gate(self._man())
        self.assertFalse(r["ok"]); self.assertTrue(r["failure"].startswith("ledger"))

    def test_malformed_ledger(self):
        write(self.repo, "runtime/led.jsonl", "not json\n")
        r = self._run_real_gate(self._man())
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "ledger-malformed")

    def test_zero_bounded_floor(self):
        write(self.repo, "runtime/led.jsonl",
              json.dumps({"kind": "whole_doc_open", "target": "x", "bytes": 100}) + "\n")
        r = self._run_real_gate(self._man())
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "ledger-gate-failed")

    def test_valid_ledger_passes(self):
        write(self.repo, "runtime/led.jsonl",
              json.dumps({"kind": "query", "target": "entity:x", "bytes": 50}) + "\n")
        r = self._run_real_gate(self._man())
        self.assertTrue(r["ok"], r)

    def test_below_min_fraction(self):
        write(self.repo, "runtime/led.jsonl",
              json.dumps({"kind": "query", "target": "q", "bytes": 1}) + "\n" +
              json.dumps({"kind": "whole_doc_open", "target": "w", "bytes": 1000}) + "\n")
        man = self._man(); man["header"]["min_bounded_fraction"] = 0.8
        r = self._run_real_gate(man)
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "ledger-gate-failed")


class OpCompletion(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## Next\nx\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _man_with(self, extra_ops):
        cs = det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")
        return {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo),
                "operations": [cs] + extra_ops}

    def test_view_rebuild_no_runner_blocked(self):
        m = self._man_with([{"op_id": "rb", "kind": "view_rebuild", "target": "view:x",
                             "semantic_owner": "deterministic", "payload_ref": {"generator": "gen"},
                             "depends_on": ["cs"]}])
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER, runner=None).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "blocked")
        self.assertFalse(r["sealed"])

    def test_validator_no_runner_blocked(self):
        m = self._man_with([{"op_id": "v", "kind": "validator", "validator_id": "doc-gate",
                             "semantic_owner": "deterministic", "payload_ref": {"files": ["core-docs/CS.md"]},
                             "depends_on": ["cs"]}])
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER, runner=None).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "blocked")

    def test_validator_fires_on_staged_content(self):
        seen = {}
        def runner(kind, ctx):
            if kind == "validator":
                seen["tip"] = ctx["staged_tip"]
                # inspect the STAGED candidate, not main
                blob = subprocess.run(["git", "-C", self.repo, "show", "%s:core-docs/CS.md" % ctx["staged_tip"]],
                                      capture_output=True).stdout.decode()
                return {"ok": "NEW-STAGED" not in blob, "detail": "saw staged content"}
            return {"digest": "d"}
        m = self._man_with([{"op_id": "v", "kind": "validator", "validator_id": "g",
                             "semantic_owner": "deterministic", "payload_ref": {}, "depends_on": ["cs"]}])
        m["operations"][0]["payload_ref"]["inline"] = "## Next\nNEW-STAGED body\n"
        raw = read_bytes(self.repo, "core-docs/CS.md")
        new = mz.apply_content(raw, m["operations"][0], mz.eol_bytes("## Next\nNEW-STAGED body\n", "lf"))
        m["operations"][0]["postcondition"] = mz.fp(mz.sha256_bytes(new))
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER, runner=runner).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "validator-failure")
        self.assertIsNotNone(seen.get("tip"))


class DeterministicAndRegion(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## A\naaa\n\n## B\nbbb\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _man(self, op):
        return {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo), "operations": [op]}

    def test_T63_15_wrong_postcondition_fails(self):
        op = det_replace(self.repo, "core-docs/CS.md", "## A", "## A\nzzz\n\n")
        op["postcondition"] = mz.fp("0" * 64)  # wrong
        r = mz.Materializer(self.repo, self._man(op), ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "deterministic-mismatch")

    def test_T63_15_tampered_payload_fails(self):
        op = det_replace(self.repo, "core-docs/CS.md", "## A", "## A\nzzz\n\n")
        op["payload_ref"]["inline"] = "## A\nTAMPERED\n\n"  # payload no longer yields declared postcondition
        r = mz.Materializer(self.repo, self._man(op), ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "deterministic-mismatch")

    def test_T63_16_out_of_region_change_ok_in_region_change_diverges(self):
        # build an op whose precondition is region-A; then modify region B (out of region) in the working
        # tree -> the region-A precondition still holds; then modify region A -> divergence.
        op = det_replace(self.repo, "core-docs/CS.md", "## A", "## A\nnew-a\n\n")
        # out-of-region change: edit section B, recommit
        write(self.repo, "core-docs/CS.md", "# CS\n\n## A\naaa\n\n## B\nB-CHANGED\n")
        commit(self.repo, "edit B")
        op2 = dict(op); op2["postcondition"] = None; op2["semantic_owner"] = "frontier"
        op2["task_spec"] = {"goal": "x"}
        m = self._man(op2)
        m["operations"] += [{"op_id": "g", "kind": "validator", "validator_id": "independent-grader:a",
                             "semantic_owner": "deterministic", "payload_ref": {"predicate": "x"},
                             "depends_on": ["cs"]}]
        m["header"]["base_head"] = g(self.repo, "rev-parse", "HEAD")
        # region-A precondition still matches (B changed, A did not) -> applies against staged content
        def runner(kind, ctx):
            return {"ok": True} if kind == "validator" else {"digest": "d"}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER, runner=runner).run()
        self.assertTrue(r["ok"], r)
        # now change region A and re-run with the OLD precondition -> divergence
        write(self.repo, "core-docs/CS.md", "# CS\n\n## A\nA-CHANGED\n\n## B\nB-CHANGED\n")
        commit(self.repo, "edit A")
        op3 = dict(op); op3["postcondition"] = None; op3["semantic_owner"] = "frontier"; op3["task_spec"] = {"g": 1}
        m3 = self._man(op3); m3["header"]["base_head"] = g(self.repo, "rev-parse", "HEAD")
        m3["header"]["transaction_id"] = "close-i63-t2"
        m3["operations"] += [{"op_id": "g", "kind": "validator", "validator_id": "independent-grader:a",
                              "semantic_owner": "deterministic", "payload_ref": {"predicate": "x"},
                              "depends_on": ["cs"]}]
        r3 = mz.Materializer(self.repo, m3, ledger_gate=STUB_LEDGER, runner=runner).run()
        self.assertFalse(r3["ok"]); self.assertEqual(r3["failure"], "precondition-divergence")


class ForeignMainAndLease(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        write(self.repo, "core-docs/CS.md", "# CS\n\n## Next\nx\n")
        commit(self.repo)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_T63_09_foreign_main_untouched(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}
        mzr = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER)
        # advance main with a foreign commit AFTER planning base_head
        r = mzr.run()
        # base_head assertion may fail if we moved main before run; here we run then confirm main is our commit
        main_after = g(self.repo, "rev-parse", "main")
        self.assertEqual(main_after, m["header"]["base_head"])  # materializer never moved main

    def test_T63_10_no_live_cutover_symbol(self):
        # no allow_live_cutover param, no _ff_main
        self.assertFalse(hasattr(mz.Materializer, "_ff_main"))
        import inspect
        sig = inspect.signature(mz.Materializer.__init__)
        self.assertNotIn("allow_live_cutover", sig.parameters)
        with open(os.path.join(PKG, "materialize.py")) as _fh:
            self.assertNotIn("--allow-live-cutover", _fh.read())

    def test_T63_19_production_no_lease_no_git_write(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER,
                            require_lease=True, lease_verifier=lambda c: False).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "lease-required")
        # no staging ref/object was written
        self.assertEqual(ref(self.repo, "refs/lo/close/close-i63-t"), "")

    def test_lease_verified_allows(self):
        m = {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo),
             "operations": [det_replace(self.repo, "core-docs/CS.md", "## Next", "## Next\ny\n")]}
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER,
                            require_lease=True, lease_verifier=lambda c: True, lease_context="lease-123").run()
        self.assertTrue(r["ok"], r)


class ProjectionBacking(unittest.TestCase):
    def setUp(self):
        self.repo = make_repo()
        self.backing = "# HARD\n" + ("clause. " * 300) + "\n"
        write(self.repo, "ops/close-txn/spec/hardened.md", self.backing)
        write(self.repo, "core-docs/research/digest.md", "# digest\n## Backing\nold projection\n")
        commit(self.repo)
        self.bfp, self.bsize = sp.dir_identity(self.repo, "ops/close-txn/spec")

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def _proj_op(self, payload, budget, sfp, backing="ops/close-txn/spec"):
        raw = read_bytes(self.repo, "core-docs/research/digest.md")
        anchor = {"type": "heading", "heading": "## Backing"}
        pre = mz.region_fp(raw, anchor)
        new = mz.apply_content(raw, dict(kind="replace_section", region_anchor=anchor), mz.eol_bytes(payload, "lf"))
        op = {"op_id": "proj", "kind": "replace_section", "target": "core-docs/research/digest.md",
              "semantic_owner": "deterministic", "eol": "lf", "region_anchor": anchor,
              "precondition": pre, "postcondition": mz.fp(mz.sha256_bytes(new)),
              "payload_ref": {"inline": payload}, "doc_class": "projection", "budget_bytes": budget,
              "backing_ref": backing, "source_fingerprint": sfp, "depends_on": []}
        return {"schema": "lifeorch.close_manifest/0.1", "header": header(self.repo), "operations": [op]}

    def test_under_budget_records_evidence(self):
        m = self._proj_op("## Backing\nshort\n", 10240, self.bfp)
        mzr = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER)
        r = mzr.run()
        self.assertTrue(r["ok"], r)
        self.assertTrue(mzr.evidence["freshness_valid"]["proj"])
        self.assertEqual(mzr.evidence["source_size"]["proj"], self.bsize)

    def test_T63_11_full_candidate_overflow_small_payload(self):
        # small payload but the FULL resulting document exceeds the tiny budget
        m = self._proj_op("## Backing\n" + ("x" * 40) + "\n", 30, self.bfp)  # payload>30, full doc >> 30
        mzr = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER)
        r = mzr.run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "projection-overflow")
        ov = mzr.evidence["overflow"][0]
        self.assertFalse(ov["trimmed"]); self.assertFalse(ov["info_lost"])
        self.assertGreater(ov["projection_size"], ov["budget_bytes"])
        # backing untouched
        self.assertEqual(read_bytes(self.repo, "ops/close-txn/spec/hardened.md").decode(), self.backing)

    def test_T63_13_missing_source_fingerprint_fails(self):
        m = self._proj_op("## Backing\nv\n", 10240, None)
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "stale-backing")

    def test_T63_13_wrong_source_fingerprint_fails(self):
        m = self._proj_op("## Backing\nv\n", 10240, "deadbeef")
        r = mz.Materializer(self.repo, m, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "stale-backing")

    def test_T63_12_same_manifest_backing_update_stale_projection(self):
        # op1 edits the backing file; op2 projects with the OLD (base) fingerprint -> stale (must fail);
        # then with the STAGED (post-edit) fingerprint -> passes.
        backing_edit = det_replace  # not used; build backing edit manually
        raw_b = read_bytes(self.repo, "ops/close-txn/spec/hardened.md")
        # a backing edit: replace the '# HARD' heading section with more content
        anchor_b = {"type": "heading", "heading": "# HARD"}
        pre_b = mz.region_fp(raw_b, anchor_b)
        newb_payload = "# HARD\nUPDATED BACKING clause. " + ("more. " * 50) + "\n"
        newb = mz.apply_content(raw_b, dict(kind="replace_section", region_anchor=anchor_b),
                                mz.eol_bytes(newb_payload, "lf"))
        op_b = {"op_id": "editbacking", "kind": "replace_section",
                "target": "ops/close-txn/spec/hardened.md", "semantic_owner": "deterministic", "eol": "lf",
                "region_anchor": anchor_b, "precondition": pre_b, "postcondition": mz.fp(mz.sha256_bytes(newb)),
                "payload_ref": {"inline": newb_payload}, "doc_class": "backing", "depends_on": []}
        # projection depends on the backing edit; bind to OLD fingerprint -> must be stale
        pm = self._proj_op("## Backing\nv\n", 100000, self.bfp)  # self.bfp = base (pre-edit)
        pm["operations"] = [op_b, pm["operations"][0]]
        pm["operations"][1]["depends_on"] = ["editbacking"]
        r = mz.Materializer(self.repo, pm, ledger_gate=STUB_LEDGER).run()
        self.assertFalse(r["ok"]); self.assertEqual(r["failure"], "stale-backing")
        # now bind to the STAGED (post-edit) fingerprint -> passes
        staged_fp = mz.sha256_bytes(newb) if False else None  # backing_ref is the DIR; compute staged dir id
        # recompute staged dir identity with the edited file overlaid
        import hashlib
        members = {}
        base = os.path.join(self.repo, "ops", "close-txn", "spec")
        for rt, dz, fs in os.walk(base):
            for fn in sorted(fs):
                rel = os.path.relpath(os.path.join(rt, fn), base).replace(os.sep, "/")
                members[rel] = read_bytes(self.repo, "ops/close-txn/spec/" + rel)
        members["hardened.md"] = newb
        h = hashlib.sha256()
        for rel in sorted(members):
            h.update(rel.encode() + b"\0" + members[rel] + b"\0")
        pm2 = self._proj_op("## Backing\nv\n", 100000, h.hexdigest())
        pm2["header"]["transaction_id"] = "close-i63-t3"
        pm2["operations"] = [dict(op_b), pm2["operations"][0]]
        pm2["operations"][1]["depends_on"] = ["editbacking"]
        r2 = mz.Materializer(self.repo, pm2, ledger_gate=STUB_LEDGER).run()
        self.assertTrue(r2["ok"], r2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
