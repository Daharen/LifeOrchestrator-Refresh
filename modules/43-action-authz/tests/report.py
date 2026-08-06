"""
report.py -- the independently-auditable EVIDENCE BUNDLE emitter (contract s6 amendment 5/7; Finding 7).

The i38 pack asserted 204/204 but shipped no machine-readable evidence, so an external reviewer could
not verify the pass. This writes a self-contained bundle under tests/report/ that lets a reviewer
re-derive the result WITHOUT trusting the README:

  report.json          -- the result taxonomy + every s8.7 criterion + both-run signature hashes +
                          section pass/fail + the mutation kill matrix + role-sink matrix + integration
                          + fuzzer + completion-binding + p01gate differential summaries.
  oracle_matrix.json   -- the full per-obligation oracle matrix (one row per A-check / boundary
                          obligation / U-property / mutation, each pass|fail|not_run).
  fixture_manifest.json-- every committed fixture with its canonical sha256 + attack-family map,
                          including the real #40 0.7.0/0.9.0 packet hashes + their provenance.
  mutation_defs.json   -- the mandatory mutation registry (id/category/staged-depth note) + the
                          mutations.py source digest (the "mutation source/patches" record).
  source_digests.json  -- sha256 of every module + test source (the tree digest) so the reviewed
                          implementation, oracle, integration, and independent p01gate are pinned.
  MANIFEST.json        -- the index + the overall bundle digest.

Everything is DETERMINISTIC (no wall-clock): the bundle is byte-identical on re-run.
"""

import glob
import hashlib
import json
import os

from action_authz import canon, VERSION
from . import mutations as MUT
from . import fixtures_suite

_MODDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# attack-family map for the committed fixtures (s8.5), plus the real-packet integration fixtures.
_FIXTURE_FAMILY = {
    "F1": 1, "F2": 2, "F3": 3, "F4": 4, "F5": 5, "F6": 6, "F7": 7, "F8": 8, "F9": 9, "F10": 10,
}


def _sha_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def _fixture_family(name):
    for pref in sorted(_FIXTURE_FAMILY, key=len, reverse=True):
        if name.startswith(pref):
            return _FIXTURE_FAMILY[pref]
    return None


def _source_digests():
    files = []
    for pat in ("action_authz/*.py", "tests/*.py", "SCHEMA_NOTES.md", "README.md", "WORK_ORDER.md"):
        files += glob.glob(os.path.join(_MODDIR, pat))
    out = {}
    for p in sorted(files):
        rel = os.path.relpath(p, _MODDIR).replace(os.sep, "/")
        out[rel] = _sha_file(p)
    return out


def _fixture_manifest():
    manifest = {"proposal_fixtures": {}, "real_packets": {}}
    for name, hv in sorted(fixtures_suite.PINNED_HASHES.items()):
        manifest["proposal_fixtures"][name] = {"canonical_sha256": hv, "family": _fixture_family(name)}
    rp_dir = os.path.join(_MODDIR, "fixtures", "real_packets")
    for p in sorted(glob.glob(os.path.join(rp_dir, "*.json"))):
        nm = os.path.basename(p)
        with open(p, "r", encoding="utf-8") as fh:
            pkt = json.load(fh)
        manifest["real_packets"][nm] = {
            "file_sha256": _sha_file(p),
            "packet_id": pkt.get("packet_id"),
            "compiler_version": pkt.get("identity", {}).get("compiler_version"),
            "non_execution": pkt.get("non_execution"),
            "family": "integration",
        }
    return manifest


def _mutation_defs():
    return {
        "registry": [{"mutation": mid, "category": cat, "staged_depth_note": note}
                     for mid, cat, _fn, note in MUT.REGISTRY],
        "mutations_source_sha256": _sha_file(os.path.join(_MODDIR, "tests", "mutations.py")),
        "note": "each mutation is an in-process seeded-defect switch (a frozenset of M-* ids) threaded "
                "through monitor/stores/boundary; the empty set is the reference implementation.",
    }


def write_bundle(payload, oracle_rows, outdir=None):
    """Write the evidence bundle. `payload` is the run-level summary assembled by run_suite; returns
    the bundle index dict (also written as MANIFEST.json)."""
    outdir = outdir or os.path.join(_MODDIR, "tests", "report")
    os.makedirs(outdir, exist_ok=True)

    files = {
        "report.json": dict(payload, action_authz_version=VERSION),
        "oracle_matrix.json": {"rows": oracle_rows, "row_count": len(oracle_rows)},
        "fixture_manifest.json": _fixture_manifest(),
        "mutation_defs.json": _mutation_defs(),
        "source_digests.json": _source_digests(),
    }
    written = {}
    for name, obj in files.items():
        b = canon.canonical_bytes(obj)
        with open(os.path.join(outdir, name), "wb") as fh:
            fh.write(b)
        written[name] = canon.sha256_hex(b)

    manifest = {"bundle": "module-43 action.authz P0-1 evidence bundle",
                "action_authz_version": VERSION,
                "files": {k: written[k] for k in sorted(written)},
                "tree_digest": files["source_digests.json"] and canon.digest_of(files["source_digests.json"]),
                "bundle_digest": canon.digest_of({k: written[k] for k in sorted(written)})}
    with open(os.path.join(outdir, "MANIFEST.json"), "wb") as fh:
        fh.write(canon.canonical_bytes(manifest))
    return manifest
