#!/usr/bin/env python3
"""validate_manifest.py -- fail-closed validator for a Life Orchestrator close-transaction manifest.

i62 PB-9 groundwork (D-0161). Enforces the STATICALLY-CHECKABLE invariants of the hardened contract
(research/2026-08-21-i62-close-transaction-hardened.md, INV-1..INV-14 + CB-* items). It VALIDATES a manifest's
well-formedness + invariants; it does NOT execute a close (the materializer is i63).

READ-ONLY. stdlib only. Deterministic (no clock, no network, no PYTHONHASHSEED dependence). Sorted output.
Exit 0 = valid; 1 = invariant violation(s) listed on stdout; 2 = I/O / usage error.

Optional --repo <root>: additionally resolve each content op's region_anchor to EXACTLY ONE span in its target
file (INV-10 span-resolvability). Without --repo, anchor structure is checked but span resolution is skipped
(noted). Reads native on-disk bytes (F-1); refuses to normalize EOL (F-2).
"""
import argparse
import json
import os
import sys

TAXONOMY = {"append", "replace_section", "create", "view_rebuild", "validator", "ack", "mirror_reconcile", "stamp"}
CONTENT_KINDS = {"append", "replace_section", "create"}
ANCHORED_KINDS = {"append", "replace_section"}
GOVERNING_MODEL = "frontier-agent-in-deterministic-loop"
GRADER_ID = "independent-grader"
MONOTONIC_BASENAMES = {"DECISION_LOG.md", "DECISION_LOG_INDEX.md"}


def is_monotonic(target):
    if not target:
        return False
    base = os.path.basename(target.replace("\\", "/"))
    return base in MONOTONIC_BASENAMES or target.endswith(".jsonl")


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def validate(manifest):
    """Return a sorted list of finding strings ([] == valid)."""
    F = []

    def bad(msg):
        F.append(msg)

    # ---- top-level shape ----
    if not isinstance(manifest, dict):
        return ["manifest is not a JSON object"]
    if manifest.get("schema") != "lifeorch.close_manifest/0.1":
        bad("schema must be 'lifeorch.close_manifest/0.1' (got %r)" % manifest.get("schema"))
    header = manifest.get("header")
    ops = manifest.get("operations")
    if not isinstance(header, dict):
        bad("header missing or not an object")
        header = {}
    if not isinstance(ops, list) or not ops:
        bad("operations missing or empty")
        ops = []

    # ---- header ----
    txid = header.get("transaction_id")
    if not isinstance(txid, str) or not txid.startswith("close-i"):
        bad("header.transaction_id must be a string like 'close-i<N>-<slug>' (got %r)" % txid)
    it = header.get("iteration")
    if not isinstance(it, int) or isinstance(it, bool) or it < 1:
        bad("header.iteration must be an integer >= 1 (got %r)" % it)
    bh = header.get("base_head")
    if not isinstance(bh, str) or not (7 <= len(bh) <= 40) or any(c not in "0123456789abcdef" for c in bh):
        bad("header.base_head must be a 7-40 char lowercase hex sha (got %r)" % bh)
    if not header.get("ledger_ref"):
        bad("header.ledger_ref is MANDATORY (INV-4; no close without a session retrieval ledger)")
    mbf = header.get("min_bounded_fraction")
    if not isinstance(mbf, (int, float)) or isinstance(mbf, bool) or not (0 <= mbf <= 1):
        bad("header.min_bounded_fraction must be a number in [0,1] (got %r)" % mbf)
    for req in ("created_by", "model_provenance"):
        if not header.get(req):
            bad("header.%s is required" % req)
    if header.get("governing_model") != GOVERNING_MODEL:
        bad("header.governing_model must be %r (got %r)" % (GOVERNING_MODEL, header.get("governing_model")))

    # ---- per-op structural + kind checks ----
    ids = {}
    for i, op in enumerate(ops):
        loc = "op[%d]" % i
        if not isinstance(op, dict):
            bad("%s is not an object" % loc)
            continue
        oid = op.get("op_id")
        loc = "op[%d]%s" % (i, ("=" + oid) if isinstance(oid, str) else "")
        if not isinstance(oid, str) or not oid:
            bad("%s missing op_id" % loc)
        else:
            ids[oid] = ids.get(oid, 0) + 1
        kind = op.get("kind")
        if kind not in TAXONOMY:
            bad("%s kind %r not in the frozen taxonomy (INV-12: no replace_doc)" % (loc, kind))
        so = op.get("semantic_owner")
        if so not in ("deterministic", "frontier"):
            bad("%s semantic_owner must be 'deterministic' or 'frontier' (got %r)" % (loc, so))
        if not isinstance(op.get("depends_on", []), list):
            bad("%s depends_on must be an array" % loc)

        # frontier ops require a task_spec (auditability; CB-DERIVE/INV-7)
        if so == "frontier" and not isinstance(op.get("task_spec"), dict):
            bad("%s semantic_owner=frontier requires a task_spec object (INV-7 auditability)" % loc)

        # per-kind required fields
        if kind in CONTENT_KINDS:
            if not op.get("target"):
                bad("%s %s requires target" % (loc, kind))
            if op.get("eol") not in ("crlf", "lf"):
                bad("%s content op requires eol in {crlf,lf} (INV-8/F-2, got %r)" % (loc, op.get("eol")))
            if "payload_ref" not in op:
                bad("%s content op requires payload_ref" % loc)
            if kind in ANCHORED_KINDS:
                _check_anchor(op, loc, bad)
                if "precondition" not in op:
                    bad("%s %s requires a precondition fingerprint (INV-8)" % (loc, kind))
            if kind == "create":
                if op.get("precondition") != "absent":
                    bad("%s create precondition must be 'absent' (got %r)" % (loc, op.get("precondition")))
            # CB-FP/F-3: a frontier content op must NOT carry a concrete postcondition sha (computed at APPLY)
            if so == "frontier":
                pc = op.get("postcondition", None)
                if isinstance(pc, dict):
                    bad("%s frontier content op must NOT pre-declare a postcondition sha (CB-FP/F-3: "
                        "computed on-device at APPLY, never the hash of its own output)" % loc)
        elif kind == "view_rebuild":
            if not op.get("target"):
                bad("%s view_rebuild requires target (the view id)" % loc)
            if "payload_ref" not in op:
                bad("%s view_rebuild requires payload_ref (generator + inputs)" % loc)
        elif kind == "validator":
            if not op.get("validator_id"):
                bad("%s validator requires validator_id" % loc)
        elif kind == "ack":
            if "payload_ref" not in op:
                bad("%s ack requires payload_ref (the predicate)" % loc)
        elif kind == "mirror_reconcile":
            if not op.get("target"):
                bad("%s mirror_reconcile requires target (the mirror id)" % loc)
            if "payload_ref" not in op:
                bad("%s mirror_reconcile requires payload_ref (managed-ref expectation)" % loc)
        elif kind == "stamp":
            if not op.get("target"):
                bad("%s stamp requires target" % loc)
            if "payload_ref" not in op:
                bad("%s stamp requires payload_ref (derivation source)" % loc)

        # INV-15: artifact classification (projection / backing). A projection declares its budget + backing;
        # a backing carries NO ingest budget and MUST NOT be a bootstrap read.
        dc = op.get("doc_class")
        if dc == "projection":
            bb = op.get("budget_bytes")
            if not isinstance(bb, int) or isinstance(bb, bool) or bb < 1:
                bad("%s doc_class=projection requires budget_bytes (int>=1) (INV-15)" % loc)
            if not op.get("backing_ref"):
                bad("%s doc_class=projection requires backing_ref (INV-15)" % loc)
        elif dc == "backing":
            if "budget_bytes" in op:
                bad("%s doc_class=backing must NOT carry budget_bytes -- backing has no ingest budget (INV-15)" % loc)
            if op.get("boot_read") is True:
                bad("%s doc_class=backing must NOT be marked a bootstrap/boot_read read (INV-15)" % loc)

        # INV-12: monotonic targets accept only append / replace_section(non-historical)
        tgt = op.get("target")
        if kind in CONTENT_KINDS and is_monotonic(tgt):
            if kind == "create":
                bad("%s create is forbidden on the append-only target %s (INV-12)" % (loc, tgt))
            if kind == "replace_section":
                ra = op.get("region_anchor") or {}
                if ra.get("region_class") != "non-historical":
                    bad("%s replace_section on the append-only target %s must set region_anchor.region_class="
                        "'non-historical' (INV-12 no-truncation)" % (loc, tgt))

    # duplicate op_ids
    for oid, n in sorted(ids.items()):
        if n > 1:
            bad("duplicate op_id %r appears %d times (must be unique)" % (oid, n))

    id_set = set(ids)
    by_id = {op.get("op_id"): op for op in ops if isinstance(op, dict) and isinstance(op.get("op_id"), str)}

    # depends_on resolvability
    for op in ops:
        if not isinstance(op, dict):
            continue
        for d in op.get("depends_on", []) or []:
            if d not in id_set:
                bad("op %r depends_on unknown op_id %r (INV-5 closure)" % (op.get("op_id"), d))
            if d == op.get("op_id"):
                bad("op %r depends_on itself" % op.get("op_id"))

    # acyclicity (Kahn)
    _check_acyclic(ops, by_id, bad)

    # CB-GRADE / INV-7: every frontier CONTENT op has a dependent independent-grader validator edge
    for op in ops:
        if not isinstance(op, dict):
            continue
        if op.get("semantic_owner") == "frontier" and op.get("kind") in CONTENT_KINDS:
            oid = op.get("op_id")
            graders = [g for g in ops if isinstance(g, dict) and g.get("kind") == "validator"
                       and str(g.get("validator_id", "")).startswith(GRADER_ID)
                       and oid in (g.get("depends_on", []) or [])]
            if not graders:
                bad("frontier content op %r has NO dependent '%s' validator edge "
                    "(CB-GRADE/INV-7: the producer must not grade itself)" % (oid, GRADER_ID))

    # INV-11: multiple ops on ONE file must be dependency-serialized + have distinct anchors
    _check_single_file_serialization(ops, by_id, bad)

    # mirror ops are terminal (post-SEAL): nothing may depend on a mirror_reconcile (INV-6)
    mirror_ids = {op.get("op_id") for op in ops if isinstance(op, dict) and op.get("kind") == "mirror_reconcile"}
    for op in ops:
        if not isinstance(op, dict):
            continue
        for d in op.get("depends_on", []) or []:
            if d in mirror_ids:
                bad("op %r depends_on mirror_reconcile op %r -- mirrors are post-SEAL terminal ops and must not "
                    "gate canonical work (INV-6)" % (op.get("op_id"), d))

    return sorted(set(F))


def _check_anchor(op, loc, bad):
    ra = op.get("region_anchor")
    if not isinstance(ra, dict):
        bad("%s %s requires a region_anchor object (INV-10; never a byte offset)" % (loc, op.get("kind")))
        return
    t = ra.get("type")
    if t == "marker":
        if not ra.get("open") or not ra.get("close"):
            bad("%s region_anchor type=marker requires open + close marker strings" % loc)
    elif t == "append_below":
        if not ra.get("marker"):
            bad("%s region_anchor type=append_below requires a marker line" % loc)
    elif t == "heading":
        if not ra.get("heading"):
            bad("%s region_anchor type=heading requires a heading string" % loc)
    else:
        bad("%s region_anchor.type must be marker|append_below|heading (got %r)" % (loc, t))


def _check_acyclic(ops, by_id, bad):
    indeg = {}
    adj = {}
    for op in ops:
        if not isinstance(op, dict):
            continue
        oid = op.get("op_id")
        if not isinstance(oid, str):
            continue
        indeg.setdefault(oid, 0)
        adj.setdefault(oid, [])
    for op in ops:
        if not isinstance(op, dict):
            continue
        oid = op.get("op_id")
        for d in op.get("depends_on", []) or []:
            if d in indeg and oid in indeg:  # only real edges
                adj[d].append(oid)
                indeg[oid] += 1
    queue = sorted([n for n, dgr in indeg.items() if dgr == 0])
    seen = 0
    while queue:
        n = queue.pop(0)
        seen += 1
        for m in sorted(adj[n]):
            indeg[m] -= 1
            if indeg[m] == 0:
                queue.append(m)
        queue.sort()
    if seen != len(indeg):
        cyc = sorted([n for n, dgr in indeg.items() if dgr > 0])
        bad("depends_on graph has a CYCLE among ops: %s (INV must be acyclic)" % ", ".join(cyc))


def _reachable(src, dst, by_id):
    """True if dst is reachable from src via depends_on edges (src depends (transitively) on dst)."""
    stack = [src]
    seen = set()
    while stack:
        n = stack.pop()
        if n == dst:
            return True
        if n in seen:
            continue
        seen.add(n)
        op = by_id.get(n)
        if op:
            for d in op.get("depends_on", []) or []:
                stack.append(d)
    return False


def _anchor_key(op):
    ra = op.get("region_anchor") or {}
    return json.dumps(ra, sort_keys=True)


def _check_single_file_serialization(ops, by_id, bad):
    # group content ops by target
    groups = {}
    for op in ops:
        if isinstance(op, dict) and op.get("kind") in CONTENT_KINDS and op.get("target"):
            groups.setdefault(op["target"], []).append(op)
    for tgt, g in sorted(groups.items()):
        if len(g) < 2:
            continue
        # distinct anchors (non-overlap heuristic; create has no anchor -> flagged separately if mixed)
        anchors = [_anchor_key(o) for o in g if o.get("kind") in ANCHORED_KINDS]
        if len(anchors) != len(set(anchors)):
            bad("target %s has multiple ops sharing an identical region_anchor "
                "(INV-11 non-overlap; anchors must be distinct)" % tgt)
        # pairwise dependency-serialization: for every unordered pair, one must (transitively) depend on the other
        ids = [o.get("op_id") for o in g]
        for a in range(len(ids)):
            for b in range(a + 1, len(ids)):
                x, y = ids[a], ids[b]
                if not (_reachable(x, y, by_id) or _reachable(y, x, by_id)):
                    bad("ops %r and %r both edit %s but are not dependency-serialized "
                        "(INV-11: multi-edits to one file must be ordered via depends_on)" % (x, y, tgt))


def resolve_anchor_spans(manifest, repo):
    """Optional INV-10 span-resolvability check against native on-disk bytes (F-1, no EOL normalization)."""
    F = []
    for op in manifest.get("operations", []):
        if not isinstance(op, dict) or op.get("kind") not in ANCHORED_KINDS:
            continue
        tgt = op.get("target")
        ra = op.get("region_anchor") or {}
        if not tgt:
            continue
        path = os.path.join(repo, tgt.replace("/", os.sep))
        if not os.path.isfile(path):
            F.append("anchor-check SKIP: %s target %s not found under --repo" % (op.get("op_id"), tgt))
            continue
        with open(path, "rb") as fh:
            raw = fh.read()  # native bytes, NOT decoded/normalized (F-1/F-2)
        t = ra.get("type")
        if t == "marker":
            o = ra.get("open", "").encode("utf-8")
            c = ra.get("close", "").encode("utf-8")
            no, nc = raw.count(o), raw.count(c)
            if no != 1 or nc != 1:
                F.append("%s marker anchor does not resolve to exactly one span in %s (open x%d, close x%d)"
                         % (op.get("op_id"), tgt, no, nc))
        elif t == "append_below":
            m = ra.get("marker", "").encode("utf-8")
            n = raw.count(m)
            if n != 1:
                F.append("%s append_below marker occurs %dx (must be exactly 1) in %s" % (op.get("op_id"), n, tgt))
        elif t == "heading":
            h = ra.get("heading", "").encode("utf-8")
            n = raw.count(h)
            if n != 1:
                F.append("%s heading anchor occurs %dx (must be exactly 1) in %s" % (op.get("op_id"), n, tgt))
    return F


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate a close-transaction manifest (i62 PB-9).")
    ap.add_argument("manifest", help="path to the manifest JSON")
    ap.add_argument("--repo", default=None, help="optional repo root for INV-10 anchor span resolution")
    a = ap.parse_args(argv)

    try:
        manifest = load_manifest(a.manifest)
    except FileNotFoundError:
        print("validate_manifest: manifest not found: %s" % a.manifest)
        return 2
    except json.JSONDecodeError as e:
        print("validate_manifest: manifest is not valid JSON: %s" % e)
        return 2

    findings = validate(manifest)
    if a.repo:
        findings = sorted(set(findings) | set(resolve_anchor_spans(manifest, a.repo)))

    hard = [f for f in findings if not f.startswith("anchor-check SKIP")]
    skips = [f for f in findings if f.startswith("anchor-check SKIP")]
    if hard:
        print("validate_manifest: INVALID (%d finding%s)" % (len(hard), "" if len(hard) == 1 else "s"))
        for f in hard:
            print("  - " + f)
        for s in skips:
            print("  . " + s)
        return 1
    print("validate_manifest: VALID -- %d operations, all invariants hold%s"
          % (len(manifest.get("operations", [])), (" (%d anchor-check skipped)" % len(skips)) if skips else ""))
    for s in skips:
        print("  . " + s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
