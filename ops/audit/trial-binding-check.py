#!/usr/bin/env python3
"""trial-binding-check.py -- rigorous evidence-BINDING gate for a fresh-context retrieval trial (i61, D-0159).

Closes the D-0158 artifact-reconciliation weakness: that close validated bounded ledger targets by
QUERY-STRING matching across the ACCUMULATED shared runtime/artifacts (444 cross-session artifacts), so
"unbacked=0" only meant the query STRING existed somewhere -- not that THIS trial/session/HEAD produced it.

This gate instead binds the evidence to an IMMUTABLE, pre-registered manifest and a SESSION-UNIQUE artifact
root, and verifies ownership by construction:

  1. MANIFEST IMMUTABILITY: sha256(manifest.json) == the sealed value in <manifest>.sha256 (written at
     creation, before the trial's first read). Any post-hoc edit to the manifest fails the gate.
  2. HEAD BINDING: manifest.target_head == the actual git HEAD the trial ran against (--head).
  3. SESSION-UNIQUE ARTIFACT ROOT: every result.json under manifest.artifact_root/*/ that carries a
     harvest_commit carries manifest.target_head -- no cross-session/foreign-HEAD artifact contaminates
     the root (the root is fresh + trial-owned).
  4. LEDGER OWNERSHIP: every BOUNDED ledger entry (section/card/query) is backed by an artifact IN the
     session-unique root whose q == the ledger target. unbacked (a bounded target with no session artifact)
     MUST be 0. This is scanned ONLY over the session root -- never the accumulated shared dir.
  5. LEDGER/MANIFEST agreement: the ledger path == manifest.ledger_path; the ledger references the manifest
     seal (first line kind==manifest, target==sha256) so the ledger is bound to this manifest.

READ-ONLY, stdlib only, deterministic. Exit 0 = BOUND (all pass); 1 = a binding failure (listed); 2 = I/O.
"""
import argparse, glob, hashlib, json, os, sys

BOUNDED = ("section", "card", "query")


def _read(p):
    with open(p, "r", encoding="utf-8") as fh:
        return fh.read()


def _sha256_file(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def _artifact_q_and_head(env):
    """(q, harvest_commit) of a project.map query artifact, else (None, None)."""
    if not isinstance(env, dict):
        return None, None
    r = env.get("result")
    if not isinstance(r, dict):
        return None, None
    q = r.get("q")
    if not (isinstance(q, str) and q.strip()):
        return None, None
    hc = None
    for v in r.values():
        if isinstance(v, dict) and isinstance(v.get("harvest_commit"), str):
            hc = v["harvest_commit"]; break
    if hc is None and isinstance(r.get("harvest_commit"), str):
        hc = r["harvest_commit"]
    return q, hc


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--head", required=True, help="the native-git HEAD the trial ran against")
    ap.add_argument("--repo", default=None)
    a = ap.parse_args(argv)
    repo = a.repo or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    fails = []
    def ck(ok, msg):
        if not ok:
            fails.append(msg)

    if not os.path.isfile(a.manifest):
        print(json.dumps({"bound": False, "fails": ["manifest not found: %s" % a.manifest]})); return 2

    # (1) immutability
    seal_path = a.manifest + ".sha256"
    ck(os.path.isfile(seal_path), "manifest seal %s missing" % seal_path)
    man_sha = _sha256_file(a.manifest)
    if os.path.isfile(seal_path):
        sealed = _read(seal_path).split()[0].strip()
        ck(sealed == man_sha, "manifest MUTATED since seal (sha %s != sealed %s)" % (man_sha[:12], sealed[:12]))

    try:
        m = json.loads(_read(a.manifest))
    except ValueError as e:
        print(json.dumps({"bound": False, "fails": ["manifest not JSON: %s" % e]})); return 2

    for k in ("trial_id", "session_identity", "target_head", "trial_epoch", "close_iteration",
              "threshold", "tasks", "ledger_path", "artifact_root"):
        ck(k in m, "manifest missing field: %s" % k)

    # (2) HEAD binding
    ck(m.get("target_head") == a.head, "manifest.target_head %s != actual HEAD %s"
       % (str(m.get("target_head"))[:12], a.head[:12]))
    ck(float(m.get("threshold", -1)) == 0.80, "manifest.threshold != 0.80 (got %s)" % m.get("threshold"))

    art_root = m.get("artifact_root", "")
    art_abs = art_root if os.path.isabs(art_root) else os.path.join(repo, art_root)
    led = m.get("ledger_path", "")
    led_abs = led if os.path.isabs(led) else os.path.join(repo, led)
    ck(os.path.isdir(art_abs), "artifact_root not a dir: %s" % art_abs)
    ck(os.path.isfile(led_abs), "ledger_path not a file: %s" % led_abs)

    # scan ONLY the session-unique artifact root
    art_qs, foreign_head, scanned = set(), [], 0
    for path in sorted(glob.glob(os.path.join(art_abs, "*", "result.json"))):
        scanned += 1
        try:
            env = json.loads(_read(path))
        except (OSError, ValueError):
            continue
        q, hc = _artifact_q_and_head(env)
        if q is not None:
            art_qs.add(q)
            # (3) no foreign-HEAD artifact in the trial root
            if hc is not None and hc != a.head:
                foreign_head.append({"path": os.path.relpath(path, repo), "harvest_commit": hc})
    ck(not foreign_head, "session artifact root has foreign-HEAD artifacts: %s" % foreign_head)
    ck(scanned > 0, "session artifact root has NO artifacts (%s)" % art_abs)

    # (4) ledger ownership: every bounded target backed by a session artifact
    ledger_manifest_seal = None
    bounded_targets, unbacked, n_bounded = [], [], 0
    if os.path.isfile(led_abs):
        for i, raw in enumerate(_read(led_abs).splitlines()):
            raw = raw.strip()
            if not raw:
                continue
            try:
                e = json.loads(raw)
            except ValueError:
                ck(False, "ledger line %d not JSON" % (i + 1)); continue
            if e.get("kind") == "manifest":
                ledger_manifest_seal = e.get("target")
                continue
            if e.get("kind") in BOUNDED:
                n_bounded += 1
                t = e.get("target")
                bounded_targets.append(t)
                if t not in art_qs:
                    unbacked.append(t)
    ck(not unbacked, "UNBACKED bounded targets (no session artifact): %s" % unbacked)
    ck(n_bounded >= 5, "n_bounded %d < 5" % n_bounded)

    # (5) ledger<->manifest agreement
    ck(os.path.abspath(led_abs) == os.path.abspath(os.path.join(repo, led) if not os.path.isabs(led) else led),
       "ledger path resolution")
    ck(ledger_manifest_seal == man_sha,
       "ledger not bound to this manifest (ledger manifest-seal %s != manifest sha %s)"
       % (str(ledger_manifest_seal)[:12], man_sha[:12]))

    bound = not fails
    out = {"bound": bound, "trial_id": m.get("trial_id"), "target_head": m.get("target_head"),
           "artifact_root": art_root, "artifacts_scanned": scanned, "n_bounded": n_bounded,
           "unbacked": unbacked, "foreign_head": foreign_head, "manifest_sha256": man_sha,
           "fails": fails}
    print(json.dumps(out, indent=1))
    return 0 if bound else 1


if __name__ == "__main__":
    sys.exit(main())
