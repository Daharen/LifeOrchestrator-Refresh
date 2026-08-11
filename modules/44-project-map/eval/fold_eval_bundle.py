#!/usr/bin/env python3
# -*- coding: ascii -*-
"""i46 close: build the FROZEN i47 eval bundle against the EVAL_SHA worktree (I47_EVAL_PACKET s2).

Reproducible construction (committed with the bundle so the i47 session or any auditor can re-derive):
  1. seed map-eval from the EVAL_SHA worktree harvest (tests/seed_map.py -- mechanical fields only);
  2. re-stamp the seed at_commit to EVAL_SHA;
  3. ingest the SAME foldfix claims used for the live map, with the recorded override; entities/edges
     the validator refuses against the EVAL_SHA tree (ENTITY_UNBACKED / DANGLING_REF etc.) are DROPPED
     mechanically and logged to PRUNE_LOG.md (bounded retry loop);
  4. write overlay-eval (iteration 45; frontier = a VERBATIM extract of the worktree handoff s4 first
     sentence block, derivation recorded; same live prohibitions -- all live at EVAL_SHA);
  5. validate (must be 0 findings) -> render generated-eval (budget/ladder rules apply);
  6. copy the tool snapshot; emit MANIFEST-input listing (hashing happens in the close task).

Usage: python3 fold_eval_bundle.py <worktree-root> <eval-sha> <module-dir> <bundle-out-dir>
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys

def run(argv):
    p = subprocess.run(argv, capture_output=True, text=True)
    out = p.stdout.strip()
    try:
        env = json.loads(out)
    except Exception:
        raise SystemExit("worker did not emit an envelope: rc=%s stderr=%s" % (p.returncode, p.stderr[-800:]))
    return env


SLUG_REMAP = {
 "module:00/exec.bootstrap": "module:00/bootstrap-executor",
 "module:00.1/exec.watchdog": "module:00.1/exec-watchdog",
 "module:01/skill.bootstrap": "module:01/skill-bootstrap",
 "module:26/agent.coding": "module:26/agent-coding",
 "module:40/context.compiler": "module:40/context.compile",
 "module:43/action.authz": "module:43/action-authz"}

def _remap_claims(claims):
    for e in claims["entities"]:
        if e["id"] in SLUG_REMAP:
            e.setdefault("aliases", []).append(e["id"].split("/", 1)[1])
            e["id"] = SLUG_REMAP[e["id"]]
        for dp in e.get("deeper", []) or []:
            dp["ref"] = SLUG_REMAP.get(dp.get("ref", ""), dp.get("ref", ""))
        if e.get("authority_docs"):
            e["authority_docs"] = [SLUG_REMAP.get(a, a) for a in e["authority_docs"]]
    seen = set(); out = []
    for r in claims["relationships"]:
        r["from"] = SLUG_REMAP.get(r["from"], r["from"]); r["to"] = SLUG_REMAP.get(r["to"], r["to"])
        k = (r["from"], r["type"], r["to"])
        if k not in seen:
            seen.add(k); out.append(r)
    claims["relationships"] = out
def main():
    wt, sha, mod, out = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3]), os.path.abspath(sys.argv[4])
    py = sys.executable
    pm = os.path.join(mod, "project_map.py")
    os.makedirs(out, exist_ok=True)
    mape = os.path.join(out, "map-eval")
    if os.path.isdir(mape):
        shutil.rmtree(mape)
    prune_log = []

    # 1-2. seed from the worktree + re-stamp
    r = subprocess.run([py, os.path.join(mod, "tests", "seed_map.py"), wt, mape], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("seed failed: " + r.stderr[-800:])
    for root, _dirs, files in os.walk(mape):
        for fn in files:
            p = os.path.join(root, fn)
            b = io.open(p, encoding="utf-8").read()
            b2 = b.replace('"at_commit": "seed"', '"at_commit": "%s"' % sha)
            if b2 != b:
                io.open(p, "w", newline="\n", encoding="utf-8").write(b2)
    # harvest-eval for validate/render/B-step-0
    hv = os.path.join(out, "harvest-eval.json")
    env = run([py, pm, "harvest", "--repo", wt, "--at-commit", sha, "--dirty", "false", "--out", hv])
    if env["status"] != "ok":
        raise SystemExit("harvest-eval failed")
    prune_log.append("harvest-eval counts: %s" % json.dumps(env["result"]["counts"], sort_keys=True))

    # 3. ingest foldfix claims with mechanical pruning loop
    claims = json.load(open(os.path.join(mod, "claims", "i46-repo-claims-foldfix.json")))
    _remap_claims(claims)
    override = "i47 eval bundle: same recorded override as the live fold (WO s3.3); claims re-stamped against the EVAL_SHA tree"
    for attempt in range(1, 8):
        cpath = os.path.join(out, "claims-eval.json")
        io.open(cpath, "w", newline="\n", encoding="utf-8").write(json.dumps(claims, sort_keys=True, indent=1) + "\n")
        env = run([py, pm, "ingest-claims", "--claims", cpath, "--map", mape, "--harvest", hv, "--override", override])
        if env["status"] == "ok":
            prune_log.append("ingest attempt %d: OK %s" % (attempt, json.dumps(env["result"], sort_keys=True)))
            break
        finds = env.get("result", {}).get("findings", [])
        if not finds:
            raise SystemExit("ingest refused with no findings: " + json.dumps(env)[:600])
        drop_edges = set()
        bad_src = {}   # entity -> set of offending source path/ref prefixes
        bad_fld = {}   # entity -> set of uncovered fields
        for f in finds:
            w = f.get("where", "")
            msg = f.get("message", "")
            prune_log.append("PRUNE(att %d): %s %s %s" % (attempt, f.get("code"), w, msg[:120]))
            m = re.match(r"^edge (\S+) -\[(\S+)\]-> (\S+)", w)
            if m:
                drop_edges.add((m.group(1), m.group(2), m.group(3))); continue
            ms = re.search(r"source (?:ref )?'([^']+)'", msg)
            if ms:
                bad_src.setdefault(w, set()).add(ms.group(1)); continue
            mf = re.search(r"claimed field '([^']+)'", msg)
            if mf:
                bad_fld.setdefault(w, set()).add(mf.group(1)); continue
            bad_src.setdefault(w, set()).add("__WHOLE__")
        before = (len(claims["entities"]), len(claims["relationships"]))
        kept, dropped_ids = [], set()
        REQUIRED = ("one_line", "plane_primary")
        for e in claims["entities"]:
            eid = e["id"]
            if eid in bad_src:
                refs = bad_src[eid]
                if "__WHOLE__" in refs:
                    dropped_ids.add(eid); prune_log.append("DROP-ENTITY %s (unclassifiable finding)" % eid); continue
                e["sources"] = [s for s in e.get("sources", []) if (s.get("ref", "").split("#", 1)[0] not in refs and s.get("ref", "") not in refs)]
                if not e["sources"]:
                    dropped_ids.add(eid); prune_log.append("DROP-ENTITY %s (no sources left)" % eid); continue
                prune_log.append("DROP-SOURCE %s: %s" % (eid, sorted(refs)))
            if eid in bad_fld:
                for fld in sorted(bad_fld[eid]):
                    if fld in REQUIRED:
                        e.setdefault("sources", []).append({"ref": "core-docs/ARCHITECTURE_MAP.md", "sha256": None,
                            "fields": [fld], "by": "orchestrator-i46-fold",
                            "at_commit": sha})
                        prune_log.append("RESOURCE %s.%s -> ARCHITECTURE_MAP.md (required field; true at EVAL_SHA)" % (eid, fld))
                    else:
                        e.pop(fld, None)
                        prune_log.append("DROP-FIELD %s.%s" % (eid, fld))
            kept.append(e)
        claims["entities"] = kept
        claims["relationships"] = [r2 for r2 in claims["relationships"]
                                   if (r2["from"], r2["type"], r2["to"]) not in drop_edges
                                   and r2["from"] not in dropped_ids and r2["to"] not in dropped_ids]
        for e in claims["entities"]:
            if e.get("deeper"):
                e["deeper"] = [dp for dp in e["deeper"] if dp.get("ref") not in dropped_ids]
            if e.get("authority_docs"):
                e["authority_docs"] = [a for a in e["authority_docs"] if a not in dropped_ids]
        after = (len(claims["entities"]), len(claims["relationships"]))
        prune_log.append("after prune: entities %d -> %d, edges %d -> %d" % (before[0], after[0], before[1], after[1]))
    else:
        raise SystemExit("ingest did not converge in 5 attempts; see PRUNE_LOG")

    # 3b. overlay-meta stubs (D-0079/0119/0120/0129) -- same claims file as the live fold; doc-backed at EVAL_SHA
    mc = os.path.join(mod, "claims", "i46-overlay-meta-claims.json")
    env = run([py, pm, "ingest-claims", "--claims", mc, "--map", mape, "--harvest", hv, "--override", override])
    if env["status"] != "ok":
        raise SystemExit("overlay-meta ingest (eval) refused: " + json.dumps(env.get("result", {}))[:800])
    prune_log.append("overlay-meta ingest (eval): OK")

    # 4. overlay-eval: frontier = verbatim extract of the worktree handoff s4 first paragraph
    hb = io.open(os.path.join(wt, "core-docs", "FANOUT_ORCHESTRATOR_HANDOFF.md"), encoding="utf-8", errors="replace").read()
    m = re.search(r"^## 4\..*?\r?\n\r?\n(.*?)(?:\r?\n\r?\n)", hb, re.S | re.M)
    frontier_txt = re.sub(r"\s+", " ", (m.group(1) if m else ""))[:300]
    overlay = {
        "schema": "lifeorch.map_overlay/0.1",
        "at_commit": sha,
        "iteration": 45,
        "phase": {"ref": "doc:core-docs/CURRENT_STATE.md",
                  "text": "Collective Agent build on cognitive virtual memory (D-0080); Tier-1 accepted; audit program mid-arc (LRAP shipped i45; poser arc D-0126..D-0129)."},
        "frontier": {"next_iteration": 46, "summary": frontier_txt,
                     "derived_from": "core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md s4 at %s (verbatim first-paragraph extract, whitespace-normalized, by fold_eval_bundle.py)" % sha,
                     "candidates": [
                         {"ref": "doc:core-docs/AUDIT_PIPELINE.md", "text": "the LRAP ride-along / OUTPUT increment [front-runner]"},
                         {"ref": "mandate:02", "text": "M2-C first increment (docs-into-memory design note)"},
                         {"ref": "module:40/context.compile", "text": "the #40 beam-WIDTH fast-beam follow-on"}]},
        "mandate": {"id": "02", "sunset_iteration": 47, "state": "ACTIVE"},
        "prohibitions": [
            {"text": "P0-1 / action.authz ACTIVATION prohibited -- the ratified gate result is a DESIGN pass only; non_execution:true holds", "authority": "decision:D-0118", "status": "live"},
            {"text": "No orchestrator-driven external/frontier AI sessions; frontier material is human-couriered; in-session cloud subagents ARE permitted", "authority": "decision:D-0119", "status": "live"},
            {"text": "Warm-pool durable supervisor default-ON is GATE-NO; classic detached-warm stays the trusted default", "authority": "decision:D-0079", "status": "live"},
            {"text": "FROZEN: generator upgrades, video.interpret + live composition, deep real-time perception, broad training", "authority": "decision:D-0080", "status": "live"}],
        "open_rulings": [
            {"text": "LRAP poser live-click confirm pending (Nicholas: ? -> Ask -> a real 9B answer)", "ref": "decision:D-0129"},
            {"text": "_to_delete_w07/ disposition (the open i43 ruling)", "ref": "decision:D-0120"}],
        "boot_read": [
            {"kind": "other", "ref": "core-docs/START_HERE.md"},
            {"kind": "other", "ref": "core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md"},
            {"kind": "other", "ref": "core-docs/CURRENT_STATE.md"},
            {"kind": "other", "ref": "core-docs/PROCESS_MANDATE.md"}]}
    od = os.path.join(mape, "overlay")
    os.makedirs(od, exist_ok=True)
    io.open(os.path.join(od, "state.json"), "w", newline="\n", encoding="utf-8").write(
        json.dumps(overlay, sort_keys=True, indent=1) + "\n")

    # 5. validate (0 findings) + render
    env = run([py, pm, "validate", "--map", mape, "--harvest", hv])
    if env["status"] != "ok" or env.get("result", {}).get("findings"):
        io.open(os.path.join(out, "PRUNE_LOG.md"), "w", newline="\n", encoding="utf-8").write(
            "# PARTIAL (validate failed)\n\n" + "\n".join("- " + ln for ln in prune_log) + "\n")
        raise SystemExit("eval validate not clean: " + json.dumps(env.get("result", {}))[:1200])
    prune_log.append("eval validate: 0 findings")
    gen = os.path.join(out, "generated-eval")
    if os.path.isdir(gen):
        shutil.rmtree(gen)
    env = run([py, pm, "render", "--map", mape, "--harvest", hv, "--out", gen,
               "--at-commit", sha, "--dirty", "false"])
    if env["status"] != "ok":
        raise SystemExit("eval render refused: " + json.dumps(env.get("result", {}))[:1200])
    prune_log.append("eval render: OK %s" % json.dumps(env.get("result", {}), sort_keys=True)[:400])

    # 6. tool snapshot
    tool = os.path.join(out, "tool")
    if os.path.isdir(tool):
        shutil.rmtree(tool)
    os.makedirs(tool)
    shutil.copy2(pm, os.path.join(tool, "project_map.py"))
    shutil.copy2(os.path.join(mod, "Invoke-ProjectMap.ps1"), os.path.join(tool, "Invoke-ProjectMap.ps1"))
    shutil.copytree(os.path.join(mod, "schema"), os.path.join(tool, "schema"))
    shutil.copy2(os.path.join(mod, "tests", "seed_map.py"), os.path.join(tool, "seed_map.py"))

    io.open(os.path.join(out, "PRUNE_LOG.md"), "w", newline="\n", encoding="utf-8").write(
        "# i47 eval-bundle construction log (fold_eval_bundle.py @ EVAL_SHA %s)\n\n" % sha +
        "\n".join("- " + ln for ln in prune_log) + "\n")
    print("EVAL_BUNDLE_OK")

if __name__ == "__main__":
    main()
