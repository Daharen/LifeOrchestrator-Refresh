#!/usr/bin/env python3
"""gen_i63_pair.py -- deterministic generator for the REAL classified backing/projection pair (i63, D-0163).

Replaces the old static example's placeholder hashes / nonexistent payloads / stale base with a manifest
computed from the ACTUAL repository state: the real backing directory identity (native bytes, confined),
the real projection target, the real anchored-region precondition, and the real whole-file postcondition.
The manifest it emits executes against a disposable clone / staging ref (see tests/test_real_pair.py and the
on-box T63-17 control) -- it is proof-by-execution, never proof-by-static-schema.

Usage (library): build_pair_manifest(repo, backing_dir=..., projection_file=..., heading=..., budget_bytes=...)
Usage (CLI):     python gen_i63_pair.py --repo <root> [--out manifest.json]
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import materialize as mz  # noqa: E402
import safepath as sp  # noqa: E402

DEFAULT_BACKING = "ops/close-txn/spec"
DEFAULT_PROJECTION = "core-docs/research/2026-08-21-i62-close-transaction.md"
DEFAULT_HEADING = "## Backing artifacts (complete, canonical)"
DEFAULT_BUDGET = 10240
DEFAULT_LEDGER = "ops/audit/retrieval-ledger/i63-orchestrator.jsonl"
MARKER = "<!-- reprojected: i63 D-0163 executable backing/projection proof -->"


def build_pair_manifest(repo, *, backing_dir=DEFAULT_BACKING, projection_file=DEFAULT_PROJECTION,
                        heading=DEFAULT_HEADING, budget_bytes=DEFAULT_BUDGET, txid="close-i63-realpair",
                        iteration=63, ledger_ref=DEFAULT_LEDGER, eol="lf", base_head=None):
    """Compute a manifest whose one projection op is bound to the backing dir's REAL native identity, with
    a real region precondition + a real whole-file postcondition and an in-budget re-projection payload."""
    if base_head is None and mz.is_git_repo(repo):
        base_head = mz.native_head(repo)
    # Fingerprint in the CANDIDATE (git-tree) domain the stage-only engine transacts, NOT the worktree: a
    # checkout's autocrlf/eol normalization rewrites worktree bytes (the on-box T63-17 clone exposed this),
    # so worktree-domain source_fingerprints drift from what APPLY re-derives. Fall back to the worktree only
    # for a non-git / not-yet-tracked source (synthetic fixtures).
    ref = base_head or "HEAD"
    if mz.is_git_repo(repo):
        src_fp, src_size = mz.tree_dir_identity(repo, backing_dir, ref)
        raw = mz.tree_blob(repo, ref, projection_file)
        if src_fp is None or raw is None:  # not tracked at ref -> worktree fallback
            src_fp, src_size = sp.dir_identity(repo, backing_dir)
            with open(sp.safe_repo_path(repo, projection_file), "rb") as fh:
                raw = fh.read()
    else:
        src_fp, src_size = sp.dir_identity(repo, backing_dir)
        with open(sp.safe_repo_path(repo, projection_file), "rb") as fh:
            raw = fh.read()
    anchor = {"type": "heading", "heading": heading}
    s, e = mz.region_span(raw, anchor)
    section = raw[s:e].decode("utf-8")
    # a deterministic, in-budget re-projection: the current section + a single marker line (idempotent-stable)
    if MARKER not in section:
        payload_text = section.rstrip("\n") + "\n" + MARKER + "\n"
    else:
        payload_text = section
    pre = mz.region_fp(raw, anchor)
    new = mz.apply_content(raw, {"kind": "replace_section", "region_anchor": anchor}, mz.eol_bytes(payload_text, eol))
    post = mz.fp(mz.sha256_bytes(new))
    op = {
        "op_id": "reproject-digest", "kind": "replace_section", "target": projection_file,
        "semantic_owner": "deterministic", "eol": eol, "owner": "ops/close-txn",
        "region_anchor": anchor, "precondition": pre, "postcondition": post,
        "payload_ref": {"inline": payload_text},
        "doc_class": "projection", "budget_bytes": budget_bytes, "backing_ref": backing_dir,
        "source_fingerprint": src_fp, "depends_on": [],
    }
    manifest = {
        "schema": "lifeorch.close_manifest/0.1",
        "header": {"transaction_id": txid, "iteration": iteration, "base_head": (base_head or "0" * 40),
                   "ledger_ref": ledger_ref, "min_bounded_fraction": 0.0, "created_by": "orchestrator-close",
                   "model_provenance": "opus-4.8", "governing_model": "frontier-agent-in-deterministic-loop"},
        "operations": [op],
    }
    return manifest


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--txid", default="close-i63-realpair")
    a = ap.parse_args(argv)
    m = build_pair_manifest(a.repo, txid=a.txid)
    text = json.dumps(m, indent=2)
    op = m["operations"][0]
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        print("wrote", a.out, "backing_identity", op["source_fingerprint"][:16],
              "backing_ref", op["backing_ref"], "budget", op["budget_bytes"])
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
