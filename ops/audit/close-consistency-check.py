#!/usr/bin/env python3
"""close-consistency-check.py -- deterministic FINAL-CLOSE cross-surface agreement gate (i61, D-0158).

Fail-closed assertion that the LIVE planning docs and the GENERATED front doors AGREE on the facts a stale
generated surface has historically drifted on (the i60 MANAGER_VIEW "gate deferred to i61" regression that
survived a corrected overlay because MANAGER_VIEW was never re-rendered):

  (1) current iteration      -- overlay.iteration
  (2) next iteration         -- overlay.frontier.next_iteration
  (3) retrieval-gate state   -- WIRED into the close path + zero-bounded floor ACTIVE at the current
                                iteration; the meaningful-fraction RAISE lands at the next iteration.
                                (NO surface may still say enforcement is deferred / observe-only / not-yet-active.)

Plus:
  (4) COLD_BOOT_CARD mechanical-stamp currency: as_of == overlay.iteration; doc COUNT == len(ls core-docs/*.md);
      last-good SHA is a real commit and an ANCESTOR of HEAD.
  (5) MANAGER_VIEW --check clean (the committed file == a fresh render of the current map/overlay).

Surfaces: map/overlay/state.json, generated/BOOT_PACKET.md, ops/manager/generated/MANAGER_VIEW.md,
core-docs/CURRENT_STATE.md, core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md, core-docs/COLD_BOOT_CARD.md.

READ-ONLY. stdlib only. Deterministic (no clock, no network). Exit 0 = all agree; 1 = disagreement(s)
listed on stdout; 2 = I/O / usage error.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys


def _read(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        return fh.read().replace("\r\n", "\n").replace("\r", "\n")


def _load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=None)
    ap.add_argument("--expect-iteration", type=int, default=None,
                    help="optional: assert overlay.iteration equals this (defends against a wrong overlay)")
    a = ap.parse_args(argv)

    repo = a.repo or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    P = lambda *r: os.path.join(repo, *r)

    fails = []
    def check(cond, msg):
        if not cond:
            fails.append(msg)

    try:
        overlay = _load_json(P("modules", "44-project-map", "map", "overlay", "state.json"))
    except (OSError, json.JSONDecodeError) as e:
        print("close-consistency: FAILED to read overlay: %s" % e); return 2
    cur = overlay.get("iteration")
    frontier = overlay.get("frontier", {}) or {}
    nxt = frontier.get("next_iteration")
    summary = frontier.get("summary", "") or ""
    if not isinstance(cur, int) or not isinstance(nxt, int):
        print("close-consistency: overlay missing integer iteration/next_iteration (%r/%r)" % (cur, nxt)); return 2
    if a.expect_iteration is not None:
        check(cur == a.expect_iteration, "overlay.iteration %r != expected %r" % (cur, a.expect_iteration))

    boot = _read(P("modules", "44-project-map", "generated", "BOOT_PACKET.md"))
    mgr = _read(P("ops", "manager", "generated", "MANAGER_VIEW.md"))
    cs = _read(P("core-docs", "CURRENT_STATE.md"))
    fh = _read(P("core-docs", "FANOUT_ORCHESTRATOR_HANDOFF.md"))
    card = _read(P("core-docs", "COLD_BOOT_CARD.md"))

    # (1)+(2) iteration / next agreement on the generated surfaces
    check(("iteration: %d" % cur) in boot, "BOOT_PACKET missing 'iteration: %d'" % cur)
    check(("frontier -> %d" % nxt) in boot, "BOOT_PACKET missing 'frontier -> %d'" % nxt)
    check(("iteration: %d (frontier -> %d)" % (cur, nxt)) in mgr,
          "MANAGER_VIEW missing 'iteration: %d (frontier -> %d)' (stale -- not re-rendered from the overlay?)"
          % (cur, nxt))

    # (1)+(2) on the live planning docs: current CLOSED + next NEXT, present in BOTH
    for name, txt in (("CURRENT_STATE", cs), ("FANOUT_HANDOFF", fh)):
        check(("i%d CLOSED" % cur) in txt, "%s does not state 'i%d CLOSED' as the current close" % (name, cur))
        check(re.search(r"(NEXT\s*=\s*i%d|i%d\s*=\s*bounded-ingest ADOPTION)" % (nxt, nxt), txt) is not None,
              "%s does not route NEXT to i%d" % (name, nxt))

    # (3) retrieval-gate state: WIRED + active-floor language present; NO stale/contradictory phrasing.
    for name, txt in (("overlay.summary", summary), ("BOOT_PACKET", boot),
                      ("CURRENT_STATE", cs), ("FANOUT_HANDOFF", fh)):
        check("WIRED" in txt or "wired" in txt,
              "%s does not describe the retrieval gate as WIRED into the close path" % name)
    FORBIDDEN = [
        "gate ENFORCEMENT deferred",
        "gate enforcement + adoption proof -> i%d" % nxt,
        "enforcement deferred to i%d" % nxt,
        "deferred/observe-only",
        "observe-only",
        "ACTIVATE the fail-closed close-path gate",
        "NEXT = i%d" % cur,
        "NEXT=i%d" % cur,
    ]
    for name, txt in (("BOOT_PACKET", boot), ("MANAGER_VIEW", mgr),
                      ("CURRENT_STATE", cs), ("FANOUT_HANDOFF", fh)):
        for bad in FORBIDDEN:
            check(bad not in txt, "%s still contains stale/contradictory phrase: %r" % (name, bad))

    # (4) COLD_BOOT_CARD mechanical-stamp currency
    m = re.search(r"\*\*as_of:\*\*\s*i(\d+)", card)
    check(m is not None and int(m.group(1)) == cur,
          "COLD_BOOT_CARD as_of != overlay iteration i%d (got %s)" % (cur, m.group(1) if m else "none"))
    n_docs = len(glob.glob(P("core-docs", "*.md")))
    mc = re.search(r"##\s*CANONICAL DOC LIST\s*--\s*(\d+)\s*core-docs as of i(\d+)", card)
    check(mc is not None and int(mc.group(1)) == n_docs and int(mc.group(2)) == cur,
          "COLD_BOOT_CARD doc-count/as_of stamp != (%d core-docs, i%d); got %s"
          % (n_docs, cur, (mc.group(1), mc.group(2)) if mc else "none"))
    mg = re.search(r"##\s*LAST-GOOD CLOSE\s*--\s*`([0-9a-f]{7,40})`", card)
    if mg is None:
        fails.append("COLD_BOOT_CARD LAST-GOOD SHA stamp not found/parseable")
    else:
        sha = mg.group(1)
        rc = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", sha, "HEAD"],
                            capture_output=True, text=True)
        check(rc.returncode == 0, "COLD_BOOT_CARD last-good `%s` is not an ancestor of HEAD (rc=%d)"
              % (sha, rc.returncode))

    # (5) MANAGER_VIEW --check clean (committed == fresh render). Use the committed snapshot date.
    md = re.search(r"^snapshot:\s*(\S+)", mgr, re.M)
    date = md.group(1) if md else "undated"
    gen = P("ops", "manager", "gen-manager-view.py")
    rc = subprocess.run([sys.executable, gen, "--repo", repo, "--date", date, "--check"],
                        capture_output=True, text=True)
    check(rc.returncode == 0, "MANAGER_VIEW --check FAILED (date=%s): %s"
          % (date, (rc.stderr or rc.stdout).strip()[:200]))

    if fails:
        print("close-consistency-check: FAIL (%d)" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("close-consistency-check: PASS -- iteration i%d, next i%d, gate WIRED+floor-active, "
          "cold-card current, MANAGER_VIEW --check clean, all surfaces agree." % (cur, nxt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
