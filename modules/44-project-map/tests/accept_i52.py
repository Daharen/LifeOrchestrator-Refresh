#!/usr/bin/env python3
# -*- coding: ascii -*-
"""project.map i52 N5/N6 -Live acceptance replays (worker PCB-N5N6-i52, plan fo-52-db941ec2).

Replays the i51 T1 derivation cluster as BOUNDED queries against the REAL repo + REAL committed
map (read-only; nothing under map/ generated/ eval/ is written), measuring the EXACT query-output
envelope bytes vs the i51 whole-doc-open baselines (I51_RESULTS s4 / B_PACK-i51 ledger):

  (a1) AUDIT_PIPELINE.md cadence-header block        vs 20,156 B whole-doc (paid by BOTH i51 arms)
  (a2) AUDIT_PIPELINE.md s5 (cadence + next_increment maintenance)          vs the same whole-doc
  (a3) AUDIT_PIPELINE.md s6 (anti-spiral guardrails)                        vs the same whole-doc
  (a4) i45-lrap-design honesty-map section (s3a)     vs  9,811 B whole-doc
  (a5) w08 WORK_ORDER follow-ons block               vs 10,209 B whole-doc
  (b)  card:module:40 + card:widget:08               vs 31,488 B L1_CARDS_modules.md whole-file

Every output envelope is saved VERBATIM under runtime/i52-accept/. Bound: (a*) <= 8,000 B each,
(b*) <= 6,000 B each. The T1-style probe check: the a1 output alone carries the live
`next_increment` line -- the T1 answer's key bytes -- with NO whole-doc open.

(a4) note (pre-fold honesty): the lrap-design doc: entity ships in claims/i52-n6-canon-claims.json
and enters the REAL map only at the orchestrator's N7 fold. Pre-fold this script (i) attempts a
REAL op_ingest_claims into a runtime COPY of the map (reporting exactly what the fold will see --
at a stale-vs-HEAD tree the staged validate is EXPECTED to refuse, the F2/N7 condition), then
(ii) patches the doc entity into the copy directly (harness surgery, labeled as such) and serves
(a4) from the patched copy against the REAL repo file. Post-fold, (a4) works on the real map as-is.

Usage: python3 tests/accept_i52.py <repo-root>
Exit 0 = every acceptance bound met; nonzero = at least one failed (each printed).
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
sys.path.insert(0, MOD)
import project_map as P  # noqa: E402

PY = sys.executable
WORKER = os.path.join(MOD, "project_map.py")
MAP = os.path.join(MOD, "map")
OUTDIR = os.path.join(MOD, "runtime", "i52-accept")

BASELINES = {"audit_pipeline_whole": 20156, "lrap_whole": 9811, "w08_wo_whole": 10209,
             "l1_modules_whole": 31488}

FAILS = []
ROWS = []


def note(name, ok, detail):
    ROWS.append((name, "OK" if ok else "FAIL", detail))
    if not ok:
        FAILS.append("%s: %s" % (name, detail))


def run_q(name, q, mapdir, harvest_path, repo=None):
    args = [PY, WORKER, "query", "--map", mapdir, "--q", q, "--harvest", harvest_path]
    if repo:
        args += ["--repo", repo]
    p = subprocess.run(args, capture_output=True, text=True)
    line = ""
    for ln in reversed(p.stdout.strip().split("\n")):
        if ln.strip().startswith("{"):
            line = ln.strip()
            break
    P.write_lf(os.path.join(OUTDIR, name + ".envelope.json"), line + "\n")
    env = json.loads(line) if line else {}
    return env, len(line.encode("utf-8"))


def main():
    repo = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.abspath(os.path.join(MOD, "..", ".."))
    os.makedirs(OUTDIR, exist_ok=True)

    # -- real harvest (read-only over the repo; output under runtime/) --
    harvest = P.op_harvest(repo, "i52-accept", False)
    hp = os.path.join(OUTDIR, "harvest.json")
    P.write_lf(hp, P.dumps_compact(harvest))

    # current whole-doc sizes at THIS tree (for the honest comparison next to the i51 baselines)
    def _lf_size(rel):
        p = os.path.join(repo, rel.replace("/", os.sep))
        try:
            with open(p, "rb") as fh:
                return len(fh.read().replace(b"\r\n", b"\n"))
        except OSError:
            return -1
    cur = {"core-docs/AUDIT_PIPELINE.md": _lf_size("core-docs/AUDIT_PIPELINE.md"),
           "core-docs/research/2026-08-08-i45-lrap-design.md": _lf_size("core-docs/research/2026-08-08-i45-lrap-design.md"),
           "widgets/08-live-run-audit-pathway/WORK_ORDER.md": _lf_size("widgets/08-live-run-audit-pathway/WORK_ORDER.md"),
           "modules/44-project-map/generated/L1_CARDS_modules.md": _lf_size("modules/44-project-map/generated/L1_CARDS_modules.md")}
    print("whole-doc sizes at this tree (LF bytes):", json.dumps(cur))

    AP = "doc:core-docs/AUDIT_PIPELINE.md"
    # ---- (a1)-(a3): AUDIT_PIPELINE cluster on the REAL COMMITTED map ----
    e, nb = run_q("a1-cadence-header", "section:%s#Cadence header" % AP, MAP, hp, repo)
    s = e.get("result", {}).get("section", {})
    note("a1-cadence-header<=8000B", e.get("status") == "ok" and nb <= 8000,
         "env=%d B (vs %d whole-doc) selector=%s" % (nb, BASELINES["audit_pipeline_whole"], s.get("selector")))
    note("a1-carries-next_increment(T1-probe, no whole-doc open)",
         "next_increment" in s.get("text", ""), "cadence block carries the T1 key bytes")
    e, nb = run_q("a2-s5", "section:%s#5. Cadence + upkeep (how this stays alive without becoming a tax)" % AP, MAP, hp, repo)
    note("a2-s5<=8000B", e.get("status") == "ok" and nb <= 8000,
         "env=%d B (vs %d whole-doc)" % (nb, BASELINES["audit_pipeline_whole"]))
    e, nb = run_q("a3-s6", "section:%s#6. Anti-spiral guardrails (carried from the packet; binding)" % AP, MAP, hp, repo)
    note("a3-s6<=8000B", e.get("status") == "ok" and nb <= 8000,
         "env=%d B (vs %d whole-doc)" % (nb, BASELINES["audit_pipeline_whole"]))

    # ---- (a5): w08 WORK_ORDER follow-ons via the widget's deeper[work-order] pointer ----
    e, nb = run_q("a5-w08-followons", "section:widget:08/live-run-audit-pathway:work-order#Follow-ons (not this session)", MAP, hp, repo)
    note("a5-w08-followons<=8000B", e.get("status") == "ok" and nb <= 8000,
         "env=%d B (vs %d whole-doc)" % (nb, BASELINES["w08_wo_whole"]))

    # ---- (b): single cards on the REAL COMMITTED map ----
    for nm, q in [("b1-card-m40", "card:module:40/context.compile"),
                  ("b1b-card-m40-alias", "card:context.compiler"),
                  ("b2-card-w08", "card:widget:08/live-run-audit-pathway")]:
        e, nb = run_q(nm, q, MAP, hp)
        c = e.get("result", {}).get("card", {})
        note("%s<=6000B" % nm, e.get("status") == "ok" and nb <= 6000,
             "env=%d B (vs %d plane file) stale-marker=%s" % (nb, BASELINES["l1_modules_whole"],
                                                              "- STALE:" in c.get("text", "")))
    # content-vs-committed-plane check (stale-line tolerant: the committed plane rendered in-sync
    # at the map-state commit; a HEAD harvest may add "- STALE:" lines -- the F2 pre-fold state)
    plane = os.path.join(MOD, "generated", "L1_CARDS_modules.md")
    if os.path.isfile(plane):
        txt = P.read_text(plane)
        want = None
        for b in txt.split("\n## ")[1:]:
            if b.startswith("module:40/context.compile\n"):
                want = ("## " + b).rstrip("\n")
                break
        with open(os.path.join(OUTDIR, "b1-card-m40.envelope.json"), encoding="utf-8") as fh:
            served = json.load(fh)["result"]["card"]["text"]

        def _strip_stale(t):
            return "\n".join(ln for ln in t.splitlines() if not ln.startswith("- STALE:")).rstrip("\n")
        note("b1-content-matches-committed-plane(stale-line-tolerant)",
             want is not None and _strip_stale(served) == _strip_stale(want),
             "committed plane block vs served card (modulo the STALE marker at a stale-vs-HEAD tree)")
    else:
        note("b1-content-matches-committed-plane(stale-line-tolerant)", False, "no committed plane file")

    # ---- (a4): lrap-design -- pre-fold path ----
    m2 = os.path.join(OUTDIR, "map-plus-claims")
    if os.path.isdir(m2):
        shutil.rmtree(m2)
    shutil.copytree(MAP, m2)
    cf = os.path.join(MOD, "claims", "i52-n6-canon-claims.json")
    ingest_report = "not-attempted"
    try:
        P.op_ingest_claims(m2, cf, harvest, None)
        ingest_report = "INGESTED-CLEAN (map in-sync at HEAD -- fold can ingest directly)"
    except P.Refuse as r:
        ingest_report = "refused:%s (expected pre-N7 at a stale-vs-HEAD tree; the fold re-harvests + re-affirms first)" % r.code
        # harness surgery, labeled: patch ONLY the doc: entity needed by (a4) into the copy
        shutil.rmtree(m2)
        shutil.copytree(MAP, m2)
        fp = os.path.join(m2, "entities", "docs.json")
        doc = json.loads(P.read_text(fp))
        claims = json.loads(P.read_text(cf))
        lrap = [x for x in claims["entities"] if x["id"].startswith("doc:")][0]
        lrap = json.loads(json.dumps(lrap))
        for src in lrap["sources"]:
            path = src["ref"].split("#", 1)[0]
            if src.get("sha256") in (None, "") and path in harvest["inventory"]:
                src["sha256"] = harvest["inventory"][path]
        doc["items"].append(lrap)
        P.write_lf(fp, P.dumps_map(doc))
    print("a4 ingest-into-copy:", ingest_report)
    e, nb = run_q("a4-lrap-honesty-map",
                  "section:doc:core-docs/research/2026-08-08-i45-lrap-design.md#3a. The per-step x per-lane HONESTY MAP (fixed HERE, not deferred to the worker -- F3)",
                  m2, hp, repo)
    note("a4-lrap-honesty-map<=8000B", e.get("status") == "ok" and nb <= 8000,
         "env=%d B (vs %d whole-doc); served from runtime map copy + claims (pre-fold: %s)"
         % (nb, BASELINES["lrap_whole"], ingest_report.split(" ")[0]))

    # ---- summary ----
    print("\n==== i52 N5/N6 -Live acceptance replays ====")
    for name, ok, detail in ROWS:
        print("  %-52s %-4s %s" % (name, ok, detail))
    print("verbatim envelopes saved under:", OUTDIR)
    if FAILS:
        print("ACCEPTANCE FAILURES:")
        for f in FAILS:
            print("  X", f)
        return 1
    print("ALL ACCEPTANCE REPLAYS GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
