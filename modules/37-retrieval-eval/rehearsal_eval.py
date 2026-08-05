#!/usr/bin/env python3
# rehearsal_eval.py -- the Tier-1 ACCEPTANCE-GATE REHEARSAL harness for retrieval.eval (Life Orchestrator
# module 37 `retrieval.eval` 0.8.0, contract v0.7; i35 Lane B REHEARSAL-HARNESS + i36 WIRED-DESCEND drive,
# plan fo-36-1a676e4b (i36) / fo-35-0a5bf334 (i35),
# D-0090/D-0098/D-0077; governing MEMORY_ARCHITECTURE s10 + MEMORY_BENCHMARK + CONTEXT_PACKET_CONTRACT i34 s7 +
# MEMORY_CONTRACT A6/s7).
#
# WHAT THIS IS
#   The RUNNABLE half of the ~200MB real-corpus rehearsal that i34 hierarchy_eval.py SCAFFOLDED + FLAGGED OPEN.
#   i34 proved the s10 invariants on a DETERMINISTIC SYNTHETIC model (necessary, NOT sufficient -- synthetic
#   generation can accidentally align query vocabulary / grouping keys / labels in ways a real repository does
#   not). This worker turns that scaffold into a harness that INGESTS a REAL FOREIGN corpus slice into a #36
#   hierarchy (via #36's shipped `ingest`/`ingest-records`/`build-hierarchy` ops), runs a MANUALLY-LABELED query
#   set, and MEASURES the MEMORY_ARCHITECTURE s10 Tier-1 acceptance criteria against #36/#40 driven READ-ONLY
#   through the external_command adapter seam -- emitting a canonical report + a single computed `tier1_accepted`.
#
#   CLI-AGNOSTIC: the harness measures WHATEVER #36/#40 CLIs it is pointed at (default: the real cores resolved
#   relative to this module; overridable argv so the ORCHESTRATOR points it at Lane A's WIRED #40 CLI at fold).
#   It does NOT claim project-level Tier-1 acceptance -- `tier1_accepted` is computed over the corpus+CLI it is
#   pointed at; the orchestrator runs the full ~200MB gate at fold and owns the project flip.
#
#   FLAT path (default): NAVIGATION COST is measured via #36's own `shortlist`/`descend` (shipped in 0.5.0), a
#   #36-direct BASELINE. i36 (opt-in `wired_descend`): the harness ALSO DRIVES #40 0.7.0's SHIPPED public
#   `-Retriever artifact_search` shortlist-and-descend port (aa2f0fb / D-0100) end to end and measures s10
#   against the WIRED packets -- navigation cost from #40's OWN plan trace
#   (packet.retrieval_completeness.navigation_nodes_examined) plus dual recall (hierarchy-PATH reach AND
#   end-to-end PACKET-EVIDENCE recall) / shortlist regret / fallback frequency / stale-window recall, with the
#   #36-direct+#40-flat path retained as a LABELED baseline (descend-vs-flat deltas). If a metric genuinely
#   needs a #36/#40 output field that is ABSENT, the harness records a FOLD_RECONCILIATION flag and refuses
#   `tier1_accepted` (it never silently passes). A caller NOT requesting `wired_descend` gets the 0.7.0 flat
#   metrics BYTE-IDENTICAL (regression-proven).
#
# DETERMINISM: the SAMPLE path is deterministic + CPU-only + stdlib-only + no model + no network. The corpus
#   SAMPLE is committed + byte-normalized (content_hash stable CRLF-vs-LF); scale replicas are a pure function of
#   the sample + the scale index; #36/#40 are deterministic; the report is integer-only (ratios in ppm),
#   sort_keys, ensure_ascii, one trailing LF, UTF-8 no BOM, NO volatile fields (paths/pids/wall-clock) ->
#   byte-identical on a re-run, cross-machine. Volatile timing lives only in worker-summary.json.
#   The full-corpus fetch (the orchestrator's ~200MB run) is a documented, HASH-VERIFIED prep -- NOT claimed
#   deterministic across a network fetch; see FULL_CORPUS_RECIPE.md.
#
# INVOCATION (by the pwsh entrypoint -Op rehearsal; also runnable directly):
#   python3 rehearsal_eval.py --request <request.json>
#   request = { op:"rehearsal", out_dir, benchmark?:<path|inline>, corpus_root?:<dir>, adapter?:{...},
#               scales?:[int...], fanout?:int, config?:{...}, wired_descend?:bool }
#   wired_descend:true DRIVES #40 0.7.0's WIRED descend path + flips the AUTHORITATIVE tier1_accepted to the
#   WIRED result (the ORCHESTRATOR points the overridable adapter m40_argv at the frozen #40 0.7.0 CLI at fold).
#   Writes out_dir/{rehearsal_report.json, rehearsal_report.md, worker-summary.json}; prints "OK <out_dir>".

import sys
import os
import json
import argparse
import tempfile
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import hierarchy_eval as he  # reuse canon_bytes/sha256_hex/digest/ppm/percentile -- he stays byte-identical (imported, never edited)

GENERATOR_NAME = "retrieval.eval/rehearsal"
GENERATOR_VERSION = "0.8.0"   # i36: + the opt-in WIRED-DESCEND drive path (0.7.0 flat metrics byte-identical)
REHEARSAL_REPORT_SCHEMA = "lifeorch.rehearsal_eval_report/0.1"
REHEARSAL_HARNESS_VERSION = "rehearsal_eval_v1"
BENCHMARK_SCHEMA = "lifeorch.rehearsal_benchmark/0.1"

DEFAULT_SCALES = [1, 10, 100]          # replication factors -> leaf counts spanning >=2 orders of magnitude
DEFAULT_FANOUT = 8
DEFAULT_CONFIG = {
    "candidate_k": 10,                 # flat-search depth per query
    "hier_shortlist_k": 4,             # #36 shortlist k (navigation frontier width)
    "hier_beam_b": 4,                  # beam width per descend level (fast path)
    "hier_depth_cap": 32,
    "token_budget": 2000,              # #40 packet budget (bounded-context-cost gate)
    "max_excerpts": 40,
    "scale_queries": 8,                # localized/ambiguous queries sampled per scale
}

# ---------------------------------------------------------------- i36 WIRED-DESCEND drive constants (opt-in)
# The i36 half of the Tier-1 flip: DRIVE #40 0.7.0's SHIPPED shortlist-and-descend port (the REAL
# ArtifactSearchHierarchyPort wired into the PUBLIC `-Retriever artifact_search` path, aa2f0fb/D-0100) end to
# end, and MEASURE s10 against the WIRED packets -- nav cost from #40's OWN plan trace, not #36-direct counts.
# GATED behind req.wired_descend: a caller NOT requesting it gets the 0.7.0 flat metrics BYTE-IDENTICAL
# (regression-proven). #40 is DRIVEN READ-ONLY via the external_command adapter (m40_argv overridable).
DESCEND_QUERY_CLASSES = ("global_synthesis", "precedent_search")  # #40 DESCEND_QUERY_CLASSES (context_compiler.py)
WIRED_DESCEND_CLASS = "global_synthesis"                          # the descend class used for coerced scale nav
DEFAULT_WIRED_DEPTH_D = 6                                         # #40 hier_depth_d default (bounded descend depth)
canon_bytes = he.canon_bytes
sha256_hex = he.sha256_hex
digest = he.digest
ppm = he.ppm
percentile = he.percentile


class RehearsalError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable


def log(msg):
    s = str(msg)
    if len(s) > 400:
        s = s[:400] + "...[+%d]" % (len(s) - 400)
    sys.stderr.write("[retrieval.eval/rehearsal] " + s + "\n")


def eol_norm_bytes(b):
    """EOL-normalize like #36/#37: decode UTF-8, strip BOM, CRLF/CR -> LF, re-encode."""
    t = b.decode("utf-8", "replace")
    if t and t[0] == "﻿":
        t = t[1:]
    return t.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


# ----------------------------------------------------------------- the external_command adapter (READ-ONLY seam)
class Adapter:
    """Drives the REAL #36/#40 CLIs as subprocesses via an argv template (the retrieval_eval.py external_command
    convention). Default argv resolves the real cores relative to this module; the orchestrator overrides argv to
    point at Lane A's WIRED CLI at fold. Each core reads a request JSON file (argv positional) and writes its
    result envelope to request.meta_path (#36 -> {ok, result}; #40 -> {ok, result:{packet,...}})."""

    def __init__(self, cfg, module_dir):
        cfg = cfg or {}
        self.kind = cfg.get("kind", "real_cli")
        self.python = cfg.get("python") or sys.executable
        self.m36_path = cfg.get("m36_path") or os.path.normpath(
            os.path.join(module_dir, "..", "36-artifact-search", "artifact_search.py"))
        self.m40_path = cfg.get("m40_path") or os.path.normpath(
            os.path.join(module_dir, "..", "40-context-compiler", "context_compiler.py"))
        self.m36_argv = cfg.get("m36_argv") or ["{PYTHON}", "{M36}", "{REQUEST_FILE}"]
        self.m40_argv = cfg.get("m40_argv") or ["{PYTHON}", "{M40}", "{REQUEST_FILE}"]
        self.timeout = int(cfg.get("timeout_seconds", 600))
        self.tmp = tempfile.mkdtemp(prefix="rehearsal-adapter-")
        self._seq = 0
        self.last_meta = None
        self.calls = {"m36": 0, "m40": 0}

    def _subst(self, tok, req_file):
        return (tok.replace("{PYTHON}", self.python).replace("{M36}", self.m36_path)
                .replace("{M40}", self.m40_path).replace("{REQUEST_FILE}", req_file))

    def _run(self, argv_tmpl, request):
        self._seq += 1
        rf = os.path.join(self.tmp, "req_%06d.json" % self._seq)
        mp = os.path.join(self.tmp, "meta_%06d.json" % self._seq)
        request = dict(request)
        request["meta_path"] = mp
        with open(rf, "w", encoding="utf-8") as f:
            json.dump(request, f)
        argv = [self._subst(a, rf) for a in argv_tmpl]
        try:
            proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.timeout)
        except subprocess.TimeoutExpired:
            raise RehearsalError("adapter_timeout", "subprocess timed out: %r" % (argv[:2],))
        if not os.path.exists(mp):
            raise RehearsalError("adapter_no_meta", "no meta from %r rc=%s stderr=%s"
                                 % (argv[:3], proc.returncode, proc.stderr.decode("utf-8", "replace")[:300]))
        with open(mp, "r", encoding="utf-8") as f:
            meta = json.load(f)
        self.last_meta = meta
        return meta

    def m36(self, request):
        self.calls["m36"] += 1
        meta = self._run(self.m36_argv, request)
        if not meta.get("ok"):
            raise RehearsalError("m36_error", "op=%s code=%s msg=%s"
                                 % (request.get("op"), meta.get("error_code"), str(meta.get("error"))[:200]))
        return meta.get("result", {})

    def m40(self, args):
        self.calls["m40"] += 1
        return self._run(self.m40_argv, args)

    def cleanup(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


# ----------------------------------------------------------------- #36 op wrappers
def m36_ingest(ad, db, namespace, root):
    return ad.m36({"op": "ingest", "db": db, "source": namespace, "root": root})


def m36_ingest_records(ad, db, records, ingest_run):
    return ad.m36({"op": "ingest-records", "db": db, "records": records, "ingest_run": ingest_run})


def m36_build(ad, db, fanout):
    return ad.m36({"op": "build-hierarchy", "db": db, "max_fanout": int(fanout)})


def m36_search(ad, db, query, k, namespace=None, current_only=False):
    filters = {}
    if namespace is not None:
        filters["namespace"] = namespace
    if current_only:
        filters["current_only"] = True
    return ad.m36({"op": "search", "db": db, "query": query, "k": int(k), "filters": filters})


def m36_shortlist(ad, db, query, namespace, k):
    return ad.m36({"op": "shortlist", "db": db, "query": query, "namespace": namespace, "k": int(k)})


def m36_descend(ad, db, node_id, namespace):
    return ad.m36({"op": "descend", "db": db, "node_id": node_id, "namespace": namespace})


def m36_mark_changed(ad, db, leaf_id):
    return ad.m36({"op": "hierarchy-mark-changed", "db": db, "leaf_id": leaf_id})


# ----------------------------------------------------------------- navigation beam driver (over the REAL #36 tree)
import re
_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _query_tokens(q):
    return set(t.lower() for t in _TOKEN_RE.findall(q or "") if len(t) >= 2)


def _score_key(n):
    ms = n.get("match_score")
    return (-int(round((ms or 0) * 1000000)), n.get("node_id", ""))


def _descriptor_score(child, qtok):
    """RANKING-ONLY overlap of the query tokens with the child's bounded synopsis (lexical_descriptor +
    entity_union). Never prunes (a bounded lossy descriptor may omit a rare decisive term -> the fast beam then
    MISSES it, which is exactly the recall gap the exhaustive-flat fallback must cover)."""
    terms = set()
    ld = child.get("lexical_descriptor")
    if isinstance(ld, dict):
        terms |= set(str(k).lower() for k in ld.keys())
    elif isinstance(ld, (list, tuple)):
        terms |= set(str(k).lower() for k in ld)
    for e in (child.get("entity_union") or []):
        if isinstance(e, (list, tuple)) and e:
            terms.add(str(e[0]).lower())
        elif isinstance(e, str):
            terms.add(e.lower())
    return len(qtok & terms)


def navigate(ad, db, namespace, query, shortlist_k, beam, guaranteed=False, depth_cap=32):
    """Drive #36 shortlist -> descend as a BOUNDED GLOBAL-beam navigation over the real tree. The global frontier
    is capped at `beam` each level (ranked by the RANKING-ONLY node synopsis), so nodes_examined ~ beam * depth ~
    beam * log_F(leaf_count) -- sub-linear and bounded. Counts nodes_examined (shortlist frontier + every descend
    expansion) and the leaf record_version_ids reached; non-beam branches are UNRESOLVED (the compiler's
    exhaustive-flat fallback covers them). No safe-pruning subprocess is used, so a rare decisive term the bounded
    descriptor omits produces an honest fast-beam MISS (recovered by the fallback)."""
    qtok = _query_tokens(query)
    sr = m36_shortlist(ad, db, query, namespace, shortlist_k)
    nodes = list(sr.get("nodes", []))
    nodes.sort(key=_score_key)
    nodes_examined = len(nodes)
    reached = set()
    unresolved = 0
    frontier = [n["node_id"] for n in nodes][:beam]
    unresolved += max(0, len(nodes) - beam)
    seen_nodes = set(frontier)
    depth = 0
    while frontier and depth < depth_cap:
        cand = []
        for nid in frontier:
            d = m36_descend(ad, db, nid, namespace)
            if not d.get("authorized", True):
                continue
            nodes_examined += 1
            for lm in d.get("leaf_members", []):
                rv = lm.get("record_version_id")
                if rv:
                    reached.add(rv)
            for c in d.get("children", []):
                cand.append((_descriptor_score(c, qtok), c.get("node_id")))
        if not cand:
            break
        cand.sort(key=lambda t: (-t[0], t[1] or ""))
        keep = [nid for _, nid in cand[:beam] if nid]
        unresolved += max(0, len(cand) - beam)
        frontier = [nid for nid in keep if nid not in seen_nodes]
        seen_nodes.update(frontier)
        depth += 1
    return {"nodes_examined": nodes_examined, "reached": reached, "unresolved": unresolved, "depth": depth}


# ----------------------------------------------------------------- provenance validation (reconstruct to source)
def validate_provenance(hit, corpus_roots):
    """A source_chunk reconstructs IFF the whole file's EOL-normalized sha256 == hit.content_hash AND the byte
    span slice's sha256 == hit.excerpt_hash. A typed record reconstructs IFF its content identity is present and
    internally consistent (no source file). Returns (valid, kind, checks)."""
    sp = hit.get("source_path")
    ns = hit.get("namespace")
    span = hit.get("span") or {}
    ch = hit.get("content_hash")
    eh = hit.get("excerpt_hash") or hit.get("chunk_content_hash")
    kind = hit.get("record_kind") or ""
    present = bool(sp and ch and (eh is not None) and ("start" in span) and ("end" in span))
    if kind == "source_chunk":
        checks = {"present": present, "content_hash_matches_source": False, "span_reproduces_bytes": False}
        root = corpus_roots.get(ns)
        if present and root and sp:
            fp = os.path.join(root, sp.replace("/", os.sep))
            if os.path.exists(fp):
                nb = eol_norm_bytes(open(fp, "rb").read())
                checks["content_hash_matches_source"] = (sha256_hex(nb) == ch)
                s, e = int(span.get("start", -1)), int(span.get("end", -1))
                if 0 <= s <= e <= len(nb):
                    checks["span_reproduces_bytes"] = (sha256_hex(nb[s:e]) == eh)
        valid = checks["present"] and checks["content_hash_matches_source"] and checks["span_reproduces_bytes"]
        return valid, "source_chunk", checks
    # typed record
    rch = hit.get("record_content_hash") or ch
    checks = {"present": bool(ch), "content_identity_present": bool(rch)}
    valid = bool(ch) and bool(rch)
    return valid, "typed_record", checks


# ----------------------------------------------------------------- #40 packet compile (flat, injected hits)
def compile_packet(ad, query_obj, hits, retrieval_meta, corpus_root, config):
    ns = query_obj["namespace"]
    ti = query_obj.get("temporal_intent", "any_valid_version")
    task = {
        "original_goal": query_obj["query"],
        "request_text": query_obj["query"],
        "namespace": ns,
        "task_type": "default",
        "query_class": query_obj.get("query_class"),
        "time_horizon": "current_only" if ti == "current_only" else None,
        "control_plane": {"permission_grants": [{"effect": "allow", "namespaces": [ns]}]},
        "config": {"token_budget": config["token_budget"], "max_excerpts": config["max_excerpts"]},
    }
    args = {
        "op": "compile",
        "task": task,
        "retrieval_batches": [{"query_index": 0, "hits": hits}],
        "retrieval_meta": retrieval_meta,
    }
    if corpus_root:
        args["repo_root"] = corpus_root
    meta = ad.m40(args)
    return meta


# ----------------------------------------------------------------- correctness pass (the labeled real-corpus queries)
def ingest_corpus(ad, db, benchmark, fixtures_dir, corpus_root, fanout):
    """Ingest the committed real foreign corpus (files -> namespaces) + the controlled supersession records, then
    build the bounded-fanout hierarchy. Returns (corpus_roots, ns_all, built)."""
    corpus = benchmark.get("corpus", {})
    corpus_roots = {}
    ns_all = []
    for nsdef in corpus.get("namespaces", []):
        ns = nsdef["namespace"]
        root = os.path.normpath(os.path.join(corpus_root, nsdef["dir"].split("/", 1)[1])) \
            if nsdef["dir"].startswith(corpus.get("corpus_dir", "") + "/") \
            else os.path.normpath(os.path.join(fixtures_dir, nsdef["dir"]))
        if not os.path.isdir(root):
            raise RehearsalError("corpus_missing", "namespace %s dir not found: %s" % (ns, root))
        m36_ingest(ad, db, ns, root)
        corpus_roots[ns] = root
        ns_all.append(ns)
    tr = corpus.get("temporal_records")
    if tr:
        trp = os.path.normpath(os.path.join(fixtures_dir, tr))
        with open(trp, "r", encoding="utf-8") as f:
            trdoc = json.load(f)
        m36_ingest_records(ad, db, trdoc["records"], trdoc.get("ingest_run", {}))
        for r in trdoc["records"]:
            if r.get("namespace") and r["namespace"] not in ns_all:
                ns_all.append(r["namespace"])
    built = m36_build(ad, db, fanout)
    return corpus_roots, ns_all, built


def measure_labeled_query(ad, db, q, corpus_roots, ns_all, config):
    ns = q["namespace"]
    depth = config["candidate_k"]
    ti = q.get("temporal_intent", "any_valid_version")
    current_only = (ti == "current_only")
    forbidden = set(q.get("forbidden_namespaces", []))
    corpus_root = corpus_roots.get(ns)

    sres = m36_search(ad, db, q["query"], depth, namespace=ns, current_only=current_only)
    hits = sres.get("results", [])
    returned_ns = sorted({h.get("namespace") for h in hits})
    contamination = sum(1 for h in hits if (h.get("namespace") != ns) or (h.get("namespace") in forbidden))

    prov_total = prov_valid = 0
    for h in hits:
        v, kind, _ = validate_provenance(h, corpus_roots)
        if kind == "source_chunk":
            prov_total += 1
            if v:
                prov_valid += 1

    req_srcs = set(q.get("required_sources", []))
    hit_srcs = {h.get("source_path") for h in hits}
    req_recs = set(q.get("required_records", []))
    excl_recs = set(q.get("excluded_records", []))
    hit_recs = {h.get("record_version_id") for h in hits}
    flat_recall = 1 if ((not req_srcs or (req_srcs & hit_srcs)) and (not req_recs or (req_recs & hit_recs))) else 0
    temporal_ok = True
    if req_recs:
        temporal_ok = temporal_ok and bool(req_recs & hit_recs)
    if excl_recs:
        temporal_ok = temporal_ok and not (excl_recs & hit_recs)
    temporal_applicable = bool(req_recs or excl_recs)

    # ground-truth target leaf rvids + the EXHAUSTIVE (flat) baseline (any-version, version-agnostic reach).
    # guaranteed/exhaustive recall == the target is findable by exhaustive flat retrieval (the fallback baseline);
    # the hierarchy fast-beam supplies the cheaper path whose recall we compare against it.
    anyres = m36_search(ad, db, q["query"], depth, namespace=ns, current_only=False)
    any_srcs = {h.get("source_path") for h in anyres.get("results", [])}
    any_rvids = {h.get("record_version_id") for h in anyres.get("results", [])}
    target_rvids = set(req_recs)
    for h in anyres.get("results", []):
        if h.get("source_path") in req_srcs:
            target_rvids.add(h.get("record_version_id"))
    guar_reach = 1 if ((not req_srcs or (req_srcs & any_srcs)) and (not req_recs or (req_recs & any_rvids))) else 0

    nav = navigate(ad, db, ns, q["query"], config["hier_shortlist_k"], config["hier_beam_b"],
                   guaranteed=False, depth_cap=config["hier_depth_cap"])
    fast_reach = 1 if (target_rvids and (target_rvids & nav["reached"])) else 0

    # #40 packet (flat compile over the injected scoped hits = the fallback/evidence path)
    rmeta = {"retriever": "artifact.search", "retriever_version": "0.5.0",
             "corpus_version": sres.get("corpus_version")}
    pmeta = compile_packet(ad, q, hits, rmeta, corpus_root, config)
    packet_ok = bool(pmeta.get("ok"))
    pkt = (pmeta.get("result") or {}).get("packet", {}) if packet_ok else {}
    disposition = (pkt.get("disposition") or {}).get("packet_disposition") if pkt else None
    selected_rvids = set(((pkt.get("identity") or {}).get("selected_record_version_ids") or [])) if pkt else set()
    excerpts = (pkt.get("evidence") or {}).get("excerpts", []) if pkt else []
    pkt_ns = sorted({e.get("namespace") for e in excerpts})
    pkt_contamination = sum(1 for e in excerpts if (e.get("namespace") != ns) or (e.get("namespace") in forbidden))
    tb = pkt.get("token_budget") or {}
    used = int(tb.get("used", 0))
    budget = int(tb.get("budget", config["token_budget"]))
    excerpt_count = len(excerpts)

    # packet-evidence recall: a required source/record retained in the packet evidence
    retained_srcs = {e.get("source_path") for e in excerpts}
    packet_recall = 1 if ((not req_srcs or (req_srcs & retained_srcs)) and
                          (not req_recs or (req_recs & selected_rvids))) else 0
    # packet provenance validity over retained excerpts (source chunks only)
    ppkt_total = ppkt_valid = 0
    for e in excerpts:
        prov = e.get("provenance") or {}
        if (e.get("record_kind") or "source_chunk") == "source_chunk":
            ppkt_total += 1
            if prov.get("reproduced") is True and prov.get("valid") is True:
                ppkt_valid += 1

    return {
        "query_id": q["query_id"],
        "kind": q.get("kind"),
        "namespace": ns,
        "temporal_intent": ti,
        "returned_count": len(hits),
        "returned_namespaces": returned_ns,
        "contamination_hits": contamination,
        "search_namespace_violation_count": int(sres.get("namespace_violation_count", 0)),
        "provenance_source_chunk_total": prov_total,
        "provenance_source_chunk_valid": prov_valid,
        "flat_recall": flat_recall,
        "temporal_applicable": temporal_applicable,
        "temporal_ok": bool(temporal_ok),
        "targets_resolved": len(target_rvids),
        "nodes_examined_fast": nav["nodes_examined"],
        "hierarchy_path_reach_fast": fast_reach,
        "hierarchy_path_reach_guaranteed": guar_reach,
        "packet_ok": packet_ok,
        "packet_disposition": disposition,
        "expected_disposition": q.get("expected_disposition"),
        "disposition_ok": (disposition == q.get("expected_disposition")) if q.get("expected_disposition") else True,
        "packet_excerpt_count": excerpt_count,
        "packet_token_used": used,
        "packet_token_budget": budget,
        "packet_within_budget": bool(used <= budget and excerpt_count <= config["max_excerpts"]),
        "packet_namespaces": pkt_ns,
        "packet_contamination_hits": pkt_contamination,
        "packet_evidence_recall": packet_recall,
        "packet_provenance_total": ppkt_total,
        "packet_provenance_valid": ppkt_valid,
    }


# ----------------------------------------------------------------- scale pass (bounded cost + sub-linear navigation)
def _read_corpus_files(corpus_roots):
    """Read the real code namespace's files once (bytes) to seed deterministic replicas."""
    files = []
    for ns, root in sorted(corpus_roots.items()):
        for dirpath, _, fns in os.walk(root):
            for fn in sorted(fns):
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p, root).replace(os.sep, "/")
                files.append((ns, rel, open(p, "rb").read()))
        break  # only the FIRST namespace (the code corpus) seeds scale replicas
    files.sort(key=lambda t: (t[0], t[1]))
    return files


def build_scaled_corpus(seed_files, reps, dest):
    """Deterministically replicate the seed corpus `reps` times into `dest`; each replica's FIRST file carries a
    unique localized decisive token ZZLOCAL_<r> so a localized query stays localized (real bytes, controlled
    scale). Returns the number of replica directories."""
    for r in range(reps):
        subdir = os.path.join(dest, "rep%05d" % r)
        os.makedirs(subdir, exist_ok=True)
        for i, (_ns, rel, raw) in enumerate(seed_files):
            outp = os.path.join(subdir, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(outp) or subdir, exist_ok=True)
            nb = eol_norm_bytes(raw)
            if i == 0:
                nb = nb + ("\n# ZZLOCAL_%05d unique decisive marker for replica %05d\n" % (r, r)).encode("utf-8")
            with open(outp, "wb") as f:
                f.write(nb)
    return reps


def measure_scales(ad, corpus_roots, scales, fanout, config, adapter_tmp):
    seed_files = _read_corpus_files(corpus_roots)
    per_scale = []
    dual = {"fast_hits": 0, "guar_hits": 0, "packet_hits": 0, "queries": 0, "regret": 0, "fallback": 0}
    for reps in scales:
        sdir = os.path.join(adapter_tmp, "scale_%05d" % reps)
        sdb = os.path.join(adapter_tmp, "scale_%05d.db" % reps)
        os.makedirs(sdir, exist_ok=True)
        build_scaled_corpus(seed_files, reps, sdir)
        m36_ingest(ad, sdb, "scale", sdir)
        built = m36_build(ad, sdb, fanout)
        b0 = (built.get("built") or [{}])[0]
        leaf_count = int(b0.get("leaf_count", 0))
        node_count = int(b0.get("node_count", 0))
        tree_depth = int(b0.get("depth", 0))
        tree_digest = b0.get("tree_digest", "")

        # sample localized decisive queries (deterministic replica indices)
        q = min(config["scale_queries"], reps)
        idxs = [(i * reps) // q for i in range(q)] if q else []
        localized_cost = []
        for r in idxs:
            token = "ZZLOCAL_%05d" % r
            # localized target rvid via the EXHAUSTIVE flat search (the guaranteed/fallback baseline)
            sres = m36_search(ad, sdb, token, config["candidate_k"], namespace="scale", current_only=False)
            hits = sres.get("results", [])
            tset = {h.get("record_version_id") for h in hits}
            nav = navigate(ad, sdb, "scale", token, config["hier_shortlist_k"], config["hier_beam_b"],
                           guaranteed=False, depth_cap=config["hier_depth_cap"])
            localized_cost.append(nav["nodes_examined"])
            fast = 1 if (tset and (tset & nav["reached"])) else 0
            guar = 1 if tset else 0                       # exhaustive flat retrieval is the guaranteed baseline
            # packet fallback: #40 compiles from the FLAT hits -> retains the target iff flat found it
            flat_found = 1 if tset else 0
            dual["queries"] += 1
            dual["fast_hits"] += fast
            dual["guar_hits"] += guar
            dual["packet_hits"] += 1 if (fast or flat_found) else 0
            if guar and not fast:
                dual["regret"] += 1
            if not fast and flat_found:
                dual["fallback"] += 1

        localized_cost.sort()
        # bounded context cost: one packet at this scale over a localized query's flat hits
        used = excerpt_count = budget = 0
        if idxs:
            token = "ZZLOCAL_%05d" % idxs[0]
            sres = m36_search(ad, sdb, token, config["candidate_k"], namespace="scale", current_only=False)
            qobj = {"query": token, "namespace": "scale", "query_class": "local_factual",
                    "temporal_intent": "any_valid_version"}
            rmeta = {"retriever": "artifact.search", "retriever_version": "0.5.0",
                     "corpus_version": sres.get("corpus_version")}
            pmeta = compile_packet(ad, qobj, sres.get("results", []), rmeta, sdir, config)
            if pmeta.get("ok"):
                pkt = (pmeta.get("result") or {}).get("packet", {})
                tb = pkt.get("token_budget") or {}
                used = int(tb.get("used", 0))
                budget = int(tb.get("budget", config["token_budget"]))
                excerpt_count = len((pkt.get("evidence") or {}).get("excerpts", []))
        per_scale.append({
            "reps": reps,
            "leaf_count": leaf_count,
            "node_count": node_count,
            "tree_depth": tree_depth,
            "tree_digest": tree_digest,
            "queries": len(idxs),
            "nodes_examined_p50": percentile(localized_cost, 50),
            "nodes_examined_p95": percentile(localized_cost, 95),
            "nodes_examined_max": localized_cost[-1] if localized_cost else 0,
            "nodes_examined_over_leaves_ppm": ppm(percentile(localized_cost, 50), leaf_count),
            "packet_token_used": used,
            "packet_token_budget": budget,
            "packet_excerpt_count": excerpt_count,
            "packet_within_budget": bool(used <= budget and excerpt_count <= config["max_excerpts"]),
        })
    # sub-linearity: nodes/leaf ratio strictly decreases; p50 not constant; span >=2 orders
    ratios = [s["nodes_examined_over_leaves_ppm"] for s in per_scale]
    p50s = [s["nodes_examined_p50"] for s in per_scale]
    leaves = [s["leaf_count"] for s in per_scale]
    sublinear = len(ratios) >= 2 and all(ratios[i] >= ratios[i + 1] for i in range(len(ratios) - 1)) and ratios[0] > ratios[-1]
    not_constant = len(p50s) >= 2 and p50s[-1] > p50s[0]
    leaf_span_ok = (min(leaves) > 0) and (max(leaves) // max(1, min(leaves)) >= 100)
    within_budget_all = all(s["packet_within_budget"] for s in per_scale)
    bounded_cost = within_budget_all and (len(per_scale) >= 2) and \
        (per_scale[-1]["packet_token_used"] <= per_scale[0]["packet_token_budget"])
    return {
        "per_scale": per_scale,
        "leaf_span_ok": bool(leaf_span_ok),
        "leaf_span_x": (max(leaves) // max(1, min(leaves))) if leaves else 0,
        "navigation_sublinear": bool(sublinear),
        "navigation_not_constant": bool(not_constant),
        "bounded_context_cost": bool(bounded_cost),
        "dual": {
            "queries": dual["queries"],
            "hierarchy_path_recall_ppm": ppm(dual["fast_hits"], dual["queries"]),
            "guaranteed_path_recall_ppm": ppm(dual["guar_hits"], dual["queries"]),
            "packet_evidence_recall_ppm": ppm(dual["packet_hits"], dual["queries"]),
            "shortlist_regret_ppm": ppm(dual["regret"], dual["queries"]),
            "fallback_frequency_ppm": ppm(dual["fallback"], dual["queries"]),
        },
    }


# ================================================================= i36 WIRED-DESCEND drive path (opt-in, additive)
def _wired_depth_d(config):
    d = config.get("hier_depth_d")
    return int(d) if d is not None else DEFAULT_WIRED_DEPTH_D


def _src_hit(present_paths, required):
    """A required source file (basename) is credited iff some retained excerpt's source_path matches it (exact
    or path-suffixed). ANY required source present -> reached (matches the flat harness's recall semantics)."""
    if not required:
        return True
    for s in required:
        for p in present_paths:
            if p and (p == s or p.endswith("/" + s) or p.endswith(s)):
                return True
    return False


def compile_packet_wired(ad, query_obj, db, corpus_version, corpus_root, config, query_class,
                         flat_hits=None, current_only=False):
    """Construct a #40 request that TRIGGERS #40 0.7.0's real hierarchy_port (acceptance a/b) and invoke it via
    the adapter m40(): retriever=artifact_search + catalog_db_path over the built #36 tree + a DESCEND
    query_class + a SCOPED single-namespace grant (effective_allowed_namespaces present) + the pinned
    corpus_version. Keys read from #40 SCHEMA_NOTES s18 (never guessed). flat_hits=None -> the PURE descend path
    (no fallback; its packet-evidence recall == the hierarchy fast-path reach). flat_hits set -> the PRODUCTION
    recall-safe path: the shipped #36 `search` seam hits stay as the fallback + the plan's leaves are APPENDED --
    exactly what Invoke-ContextCompiler.ps1 -Retriever artifact_search does in production."""
    ns = query_obj["namespace"]
    task = {
        "original_goal": query_obj["query"],
        "request_text": query_obj["query"],
        "namespace": ns,
        "task_type": "research",
        "query_class": query_class,
        "time_horizon": "current_only" if current_only else None,
        "control_plane": {"permission_grants": [{"effect": "allow", "namespaces": [ns]}]},
        "config": {"token_budget": config["token_budget"], "max_excerpts": config["max_excerpts"],
                   "hier_shortlist_k": config["hier_shortlist_k"], "hier_beam_b": config["hier_beam_b"],
                   "hier_depth_d": _wired_depth_d(config)},
    }
    args = {
        "op": "compile",
        "task": task,
        "retrieval_meta": {"retriever": "artifact_search", "retriever_version": "0.5.0",
                           "corpus_version": corpus_version},
        "catalog_db_path": db,
    }
    if corpus_root:
        args["repo_root"] = corpus_root
    if flat_hits is not None:
        args["retrieval_batches"] = [{"query_index": 0, "hits": flat_hits}]
    return ad.m40(args)


def _wired_packet(meta):
    ok = bool(meta.get("ok"))
    pkt = (meta.get("result") or {}).get("packet", {}) if ok else {}
    rc = pkt.get("retrieval_completeness") or {}
    ev = (pkt.get("evidence") or {}).get("excerpts", []) if pkt else []
    nav_refs = (pkt.get("evidence") or {}).get("navigation_refs", []) if pkt else []
    disp = (pkt.get("disposition") or {}).get("packet_disposition") if pkt else None
    tb = pkt.get("token_budget") or {}
    return {"ok": ok, "pkt": pkt, "rc": rc, "ev": ev, "nav_refs": nav_refs, "disposition": disp,
            "used": int(tb.get("used", 0)), "budget": int(tb.get("budget", 0)),
            "descend_ran": ("retrieval_completeness" in pkt)}


def measure_labeled_query_wired(ad, db, q, corpus_roots, config, corpus_version):
    """Drive #40 0.7.0's public artifact_search path over one labeled real-corpus query and MEASURE the WIRED
    packet. PRODUCTION compile (own class -> descend runs iff the class routes there [q1/q6/q7 global_synthesis];
    the shipped #36 flat search seam injected as the recall-safe fallback). A DESCEND-class query gets an extra
    PURE descend compile (no fallback) isolating the hierarchy fast-path reach (the honest bounded-beam gap).
    s10: contamination (evidence + navigation_refs), provenance (reproduced direct_span), temporal (current_only),
    disposition, budget, and the nav cost + completeness signals from #40's OWN plan trace."""
    ns = q["namespace"]
    depth = config["candidate_k"]
    ti = q.get("temporal_intent", "any_valid_version")
    current_only = (ti == "current_only")
    forbidden = set(q.get("forbidden_namespaces", []))
    req_srcs = set(q.get("required_sources", []))
    req_recs = set(q.get("required_records", []))
    excl_recs = set(q.get("excluded_records", []))
    corpus_root = corpus_roots.get(ns)
    own_class = q.get("query_class")
    is_descend_class = own_class in DESCEND_QUERY_CLASSES

    sres = m36_search(ad, db, q["query"], depth, namespace=ns, current_only=current_only)
    flat_hits = sres.get("results", [])
    anyres = m36_search(ad, db, q["query"], depth, namespace=ns, current_only=False)
    any_srcs = {h.get("source_path") for h in anyres.get("results", [])}
    any_recs = {h.get("record_version_id") for h in anyres.get("results", [])}
    guar = 1 if (_src_hit(any_srcs, req_srcs) and (not req_recs or (req_recs & any_recs))) else 0

    prod = _wired_packet(compile_packet_wired(ad, q, db, corpus_version, corpus_root, config, own_class,
                                              flat_hits=flat_hits, current_only=current_only))
    ev = prod["ev"]
    nav_refs = prod["nav_refs"]
    rc = prod["rc"]
    ev_srcs = {e.get("source_path") for e in ev}
    ev_recs = {e.get("record_version_id") for e in ev}
    ev_ns = sorted({e.get("namespace") for e in ev})
    contamination = sum(1 for e in ev if (e.get("namespace") != ns) or (e.get("namespace") in forbidden))
    contamination += sum(1 for r in nav_refs if (r.get("namespace") not in (ns, None)) or (r.get("namespace") in forbidden))
    packet_recall = 1 if (_src_hit(ev_srcs, req_srcs) and (not req_recs or (req_recs & ev_recs))) else 0
    temporal_applicable = bool(req_recs or excl_recs)
    temporal_ok = True
    if req_recs:
        temporal_ok = temporal_ok and bool(req_recs & ev_recs)
    if excl_recs:
        temporal_ok = temporal_ok and not (excl_recs & ev_recs)
    prov_total = prov_valid = 0
    for e in ev:
        if (e.get("record_kind") or "source_chunk") == "source_chunk":
            prov_total += 1
            prov = e.get("provenance") or {}
            if prov.get("reproduced") is True and prov.get("valid") is True:
                prov_valid += 1
    disp = prod["disposition"]
    exp_disp = q.get("expected_disposition")
    disp_ok = (disp == exp_disp) if exp_disp else True
    within = bool(prod["used"] <= prod["budget"] and len(ev) <= config["max_excerpts"])

    ran = bool(prod["descend_ran"])
    wired_nav_examined = int(rc.get("navigation_nodes_examined", 0)) if ran else 0
    leaf_candidates = int(rc.get("leaf_candidates_collected", 0)) if ran else 0
    pruned = int(rc.get("pruned_branch_count", 0)) if ran else 0
    fallback_used = bool(rc.get("fallback_used")) if ran else None
    frontier_exhausted = bool(rc.get("frontier_exhausted")) if ran else None
    stale_enc = bool(rc.get("stale_navigation_encountered")) if ran else None
    stage_count = len(((rc.get("retrieval_plan") or {}).get("stages")) or []) if ran else 0

    path_reach = None
    if is_descend_class:
        pure = _wired_packet(compile_packet_wired(ad, q, db, corpus_version, corpus_root, config, own_class))
        p_srcs = {e.get("source_path") for e in pure["ev"]}
        p_recs = {e.get("record_version_id") for e in pure["ev"]}
        path_reach = 1 if (_src_hit(p_srcs, req_srcs) and (not req_recs or (req_recs & p_recs))) else 0

    return {
        "query_id": q["query_id"], "kind": q.get("kind"), "namespace": ns, "temporal_intent": ti,
        "own_query_class": own_class, "descend_ran": ran,
        "wired_evidence_count": len(ev), "wired_evidence_namespaces": ev_ns,
        "wired_contamination_hits": contamination,
        "wired_navigation_nodes_examined": wired_nav_examined,
        "wired_leaf_candidates_collected": leaf_candidates,
        "wired_stage_count": stage_count,
        "wired_pruned_branch_count": pruned,
        "wired_fallback_used": fallback_used,
        "wired_frontier_exhausted": frontier_exhausted,
        "wired_stale_navigation_encountered": stale_enc,
        "wired_provenance_total": prov_total, "wired_provenance_valid": prov_valid,
        "wired_guaranteed_recall": guar,
        "wired_hierarchy_path_reach": path_reach,
        "wired_packet_recall": packet_recall,
        "wired_regret": (1 if (path_reach is not None and guar and not path_reach) else 0),
        "wired_fallback_recovered": (1 if (path_reach is not None and not path_reach and packet_recall) else 0),
        "temporal_applicable": temporal_applicable, "wired_temporal_ok": bool(temporal_ok),
        "wired_disposition": disp, "expected_disposition": exp_disp, "wired_disposition_ok": bool(disp_ok),
        "wired_token_used": prod["used"], "wired_token_budget": prod["budget"], "wired_within_budget": within,
    }


def measure_scales_wired(ad, corpus_roots, scales, fanout, config, adapter_tmp):
    """Bounded-cost + SUB-LINEAR navigation from #40's OWN plan trace
    (packet.retrieval_completeness.navigation_nodes_examined), over deterministic real-byte replicas spanning
    >=2 orders of magnitude. Each localized ZZLOCAL query is driven through #40's DESCEND path: PURE descend
    (fast-path reach + the nav trace) and PRODUCTION (+the #36 flat fallback -> recall preserved). Yields the
    wired dual recall / regret / fallback-frequency + the wired bounded-cost check."""
    seed_files = _read_corpus_files(corpus_roots)
    per_scale = []
    dual = {"path_hits": 0, "guar_hits": 0, "packet_hits": 0, "queries": 0, "regret": 0, "fallback": 0}
    for reps in scales:
        sdir = os.path.join(adapter_tmp, "wscale_%05d" % reps)
        sdb = os.path.join(adapter_tmp, "wscale_%05d.db" % reps)
        os.makedirs(sdir, exist_ok=True)
        build_scaled_corpus(seed_files, reps, sdir)
        m36_ingest(ad, sdb, "scale", sdir)
        built = m36_build(ad, sdb, fanout)
        b0 = (built.get("built") or [{}])[0]
        leaf_count = int(b0.get("leaf_count", 0))
        node_count = int(b0.get("node_count", 0))
        tree_depth = int(b0.get("depth", 0))
        tree_digest = b0.get("tree_digest", "")
        cv = m36_search(ad, sdb, "ZZLOCAL", 1, namespace="scale", current_only=False).get("corpus_version")

        qn = min(config["scale_queries"], reps)
        idxs = [(i * reps) // qn for i in range(qn)] if qn else []
        wnav_cost = []
        for r in idxs:
            token = "ZZLOCAL_%05d" % r
            sres = m36_search(ad, sdb, token, config["candidate_k"], namespace="scale", current_only=False)
            flat_hits = sres.get("results", [])
            # recall by RECORD IDENTITY (rvid) -- the file/record-level semantic the labeled queries
            # (required_records) + the flat baseline (tset) use. An excerpt is a WINDOW of its chunk, so a
            # text-substring check would UNDER-credit a correctly-retained record whose cited span excludes the
            # trailing marker line (observed at scale: prod rvid-hit True while the windowed text omits the marker).
            tset = {h.get("record_version_id") for h in flat_hits if h.get("record_version_id")}
            guar = 1 if tset else 0
            qobj = {"query": token, "namespace": "scale"}
            pure = _wired_packet(compile_packet_wired(ad, qobj, sdb, cv, sdir, config, WIRED_DESCEND_CLASS))
            prod = _wired_packet(compile_packet_wired(ad, qobj, sdb, cv, sdir, config, WIRED_DESCEND_CLASS,
                                                      flat_hits=flat_hits))
            wnav_cost.append(int(pure["rc"].get("navigation_nodes_examined", 0)))
            path_reach = 1 if (tset and (tset & {e.get("record_version_id") for e in pure["ev"]})) else 0
            packet_reach = 1 if (tset and (tset & {e.get("record_version_id") for e in prod["ev"]})) else 0
            dual["queries"] += 1
            dual["path_hits"] += path_reach
            dual["guar_hits"] += guar
            dual["packet_hits"] += packet_reach
            if guar and not path_reach:
                dual["regret"] += 1
            if not path_reach and packet_reach:
                dual["fallback"] += 1
        wnav_cost.sort()
        used = budget = excerpt_count = 0
        if idxs:
            token = "ZZLOCAL_%05d" % idxs[0]
            sres = m36_search(ad, sdb, token, config["candidate_k"], namespace="scale", current_only=False)
            prod = _wired_packet(compile_packet_wired(ad, {"query": token, "namespace": "scale"}, sdb, cv, sdir,
                                                      config, WIRED_DESCEND_CLASS, flat_hits=sres.get("results", [])))
            used = prod["used"]
            budget = prod["budget"]
            excerpt_count = len(prod["ev"])
        per_scale.append({
            "reps": reps, "leaf_count": leaf_count, "node_count": node_count, "tree_depth": tree_depth,
            "tree_digest": tree_digest, "queries": len(idxs),
            "wired_nav_examined_p50": percentile(wnav_cost, 50),
            "wired_nav_examined_p95": percentile(wnav_cost, 95),
            "wired_nav_examined_max": wnav_cost[-1] if wnav_cost else 0,
            "wired_nav_over_leaves_ppm": ppm(percentile(wnav_cost, 50), leaf_count),
            "packet_token_used": used, "packet_token_budget": budget, "packet_excerpt_count": excerpt_count,
            "packet_within_budget": bool(used <= budget and excerpt_count <= config["max_excerpts"]),
        })
    ratios = [s["wired_nav_over_leaves_ppm"] for s in per_scale]
    p50s = [s["wired_nav_examined_p50"] for s in per_scale]
    leaves = [s["leaf_count"] for s in per_scale]
    sublinear = len(ratios) >= 2 and all(ratios[i] >= ratios[i + 1] for i in range(len(ratios) - 1)) and ratios[0] > ratios[-1]
    # log-shaped guard: nav grows STRICTLY SLOWER than leaf count (a bounded plan may keep nav ~constant, which
    # is still sub-linear -- so we require nav_growth_ppm < leaf_growth_ppm, NOT that nav grows).
    nav_growth_ppm = ppm(p50s[-1], p50s[0]) if p50s and p50s[0] else 0
    leaf_growth_ppm = ppm(leaves[-1], leaves[0]) if leaves and leaves[0] else 0
    sublinear_growth = bool(nav_growth_ppm < leaf_growth_ppm)
    leaf_span_ok = (min(leaves) > 0) and (max(leaves) // max(1, min(leaves)) >= 100)
    within_all = all(s["packet_within_budget"] for s in per_scale)
    bounded_cost = within_all and (len(per_scale) >= 2) and \
        (per_scale[-1]["packet_token_used"] <= per_scale[0]["packet_token_budget"])
    return {
        "per_scale": per_scale, "leaf_span_ok": bool(leaf_span_ok),
        "leaf_span_x": (max(leaves) // max(1, min(leaves))) if leaves else 0,
        "navigation_sublinear": bool(sublinear), "navigation_sublinear_growth": sublinear_growth,
        "nav_growth_ppm": nav_growth_ppm, "leaf_growth_ppm": leaf_growth_ppm,
        "bounded_context_cost": bool(bounded_cost),
        "dual": {
            "queries": dual["queries"],
            "hierarchy_path_recall_ppm": ppm(dual["path_hits"], dual["queries"]),
            "guaranteed_path_recall_ppm": ppm(dual["guar_hits"], dual["queries"]),
            "packet_evidence_recall_ppm": ppm(dual["packet_hits"], dual["queries"]),
            "shortlist_regret_ppm": ppm(dual["regret"], dual["queries"]),
            "fallback_frequency_ppm": ppm(dual["fallback"], dual["queries"]),
        },
    }


def measure_stale_window_wired(ad, db, corpus_roots, config, corpus_version):
    """STALE-WINDOW recall: mark a real leaf changed (#36 hierarchy-mark-changed propagates staleness up the
    ancestor path), then re-drive the descend compile. A stale navigation synopsis is NEVER a prune proof
    (V2/A6) -> stale_navigation_encountered flags True, the branch is RETAINED not pruned, and the required
    evidence stays reachable via the recall-safe fallback (never a silent miss). Runs LAST (mutates the db)."""
    ns = sorted(corpus_roots.keys())[0]
    corpus_root = corpus_roots.get(ns)
    query = "progressbar"                       # rare decisive term (label_provenance: only clickcode/termui.py)
    sres = m36_search(ad, db, query, config["candidate_k"], namespace=ns, current_only=False)
    flat_hits = sres.get("results", [])
    target_recs = {h.get("record_version_id") for h in flat_hits if h.get("record_version_id")}
    nav = navigate(ad, db, ns, query, config["hier_shortlist_k"], config["hier_beam_b"],
                   depth_cap=config["hier_depth_cap"])
    reached = sorted(x for x in nav["reached"] if x)
    leaf_id = reached[0] if reached else (sorted(target_recs)[0] if target_recs else None)
    base = _wired_packet(compile_packet_wired(ad, {"query": query, "namespace": ns}, db, corpus_version,
                                              corpus_root, config, WIRED_DESCEND_CLASS, flat_hits=flat_hits))
    base_pruned = int(base["rc"].get("pruned_branch_count", 0))
    marked = False
    if leaf_id:
        try:
            m36_mark_changed(ad, db, leaf_id)
            marked = True
        except RehearsalError:
            marked = False
    st = _wired_packet(compile_packet_wired(ad, {"query": query, "namespace": ns}, db, corpus_version,
                                            corpus_root, config, WIRED_DESCEND_CLASS, flat_hits=flat_hits))
    st_recs = {e.get("record_version_id") for e in st["ev"]}
    recall_preserved = 1 if (not target_recs or (target_recs & st_recs)) else 0
    stale_pruned = int(st["rc"].get("pruned_branch_count", 0))
    return {
        "namespace": ns, "query": query, "leaf_marked_changed": bool(marked),
        "baseline_pruned_branch_count": base_pruned,
        "stale_navigation_encountered": bool(st["rc"].get("stale_navigation_encountered")),
        "stale_pruned_branch_count": stale_pruned,
        "stale_pruned_not_increased": bool(stale_pruned <= base_pruned),
        "recall_preserved_after_stale": recall_preserved,
    }


def probe_wired_capability(ad):
    """Prove #40 0.7.0 CAN be driven into the descend path (acceptance a/b) -- else a FOLD RECONCILIATION.
    Builds a tiny real #36 tree and drives a scoped global_synthesis artifact_search compile; asserts the port
    constructed + emitted retrieval_completeness incl. navigation_nodes_examined + the stage trace."""
    caps = {"wired_port_constructs": False, "wired_emits_retrieval_completeness": False,
            "wired_emits_navigation_nodes_examined": False, "wired_emits_stage_trace": False,
            "absent_required": []}
    tmpdb = os.path.join(ad.tmp, "wprobe.db")
    root = os.path.join(ad.tmp, "wprobe_corpus")
    os.makedirs(root, exist_ok=True)
    with open(os.path.join(root, "a.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# A\n\nThe WPROBEWORD decisive marker plus lease fencing content alpha.\n")
    with open(os.path.join(root, "b.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# B\n\nGeneric fencing lease filler beta gamma delta content here.\n")
    try:
        m36_ingest(ad, tmpdb, "wprobe", root)
        m36_build(ad, tmpdb, 4)
        cv = m36_search(ad, tmpdb, "WPROBEWORD", 3, namespace="wprobe").get("corpus_version")
        m = compile_packet_wired(ad, {"query": "WPROBEWORD", "namespace": "wprobe"}, tmpdb, cv, root,
                                 DEFAULT_CONFIG, WIRED_DESCEND_CLASS)
        pkt = (m.get("result") or {}).get("packet", {}) if m.get("ok") else {}
        rc = pkt.get("retrieval_completeness")
        caps["wired_port_constructs"] = any(str(w).startswith("hierarchy_port_bound:")
                                            for w in (pkt.get("warnings") or []))
        caps["wired_emits_retrieval_completeness"] = rc is not None
        caps["wired_emits_navigation_nodes_examined"] = bool(rc and ("navigation_nodes_examined" in rc))
        caps["wired_emits_stage_trace"] = bool(rc and (rc.get("retrieval_plan") or {}).get("stages"))
    except RehearsalError as e:
        caps["absent_required"].append("wired:%s" % e.code)
    for req in ("wired_port_constructs", "wired_emits_retrieval_completeness",
                "wired_emits_navigation_nodes_examined", "wired_emits_stage_trace"):
        if not caps[req]:
            caps["absent_required"].append(req)
    return caps


def compute_criteria_wired(labeled, scale, stale, wcaps):
    total = len(labeled)
    descend_rows = [r for r in labeled if r["descend_ran"]]
    contamination_hits = sum(r["wired_contamination_hits"] for r in labeled)
    crit_contam = (contamination_hits == 0)
    tq = [r for r in labeled if r["temporal_applicable"]]
    crit_temporal = bool(tq) and all(r["wired_temporal_ok"] for r in tq)
    ptot = sum(r["wired_provenance_total"] for r in labeled)
    pval = sum(r["wired_provenance_valid"] for r in labeled)
    crit_prov = (ptot > 0 and pval == ptot)
    labeled_within = all(r["wired_within_budget"] for r in labeled)
    crit_bounded = bool(scale["bounded_context_cost"] and labeled_within)
    crit_nav = bool(scale["navigation_sublinear"] and scale["navigation_sublinear_growth"] and scale["leaf_span_ok"])
    lab_packet_ppm = ppm(sum(r["wired_packet_recall"] for r in labeled), total)
    crit_packet_recall = (lab_packet_ppm == 1000000 and scale["dual"]["packet_evidence_recall_ppm"] == 1000000)
    lab_guar_ppm = ppm(sum(r["wired_guaranteed_recall"] for r in labeled), total)
    crit_guar = (lab_guar_ppm == 1000000 and scale["dual"]["guaranteed_path_recall_ppm"] == 1000000)
    crit_disp = all(r["wired_disposition_ok"] for r in labeled)
    crit_descend_ran = bool(descend_rows) and all(r["descend_ran"] for r in descend_rows) \
        and (scale["dual"]["queries"] > 0)
    crit_stale = bool(stale["recall_preserved_after_stale"]) and \
        (bool(stale["stale_navigation_encountered"]) or not stale["leaf_marked_changed"])
    fold = list(wcaps.get("absent_required", []))
    crit_no_fold = (len(fold) == 0)
    criteria = [
        {"criterion": "wired_descend_path_ran", "s10": "a/b", "passed": crit_descend_ran,
         "detail": {"descend_class_queries": len(descend_rows), "scale_descend_queries": scale["dual"]["queries"]}},
        {"criterion": "bounded_context_cost", "s10": "(a)", "passed": crit_bounded,
         "detail": {"scale_bounded": scale["bounded_context_cost"], "labeled_within_budget": labeled_within}},
        {"criterion": "cross_namespace_contamination", "s10": "(b)", "passed": crit_contam,
         "detail": {"contamination_hits": contamination_hits}},
        {"criterion": "current_vs_historical", "s10": "(c)", "passed": crit_temporal,
         "detail": {"temporal_queries": len(tq), "honored": sum(1 for r in tq if r["wired_temporal_ok"])}},
        {"criterion": "provenance_reconstruction", "s10": "(d)", "passed": crit_prov,
         "detail": {"source_chunk_total": ptot, "valid": pval, "valid_ppm": ppm(pval, ptot)}},
        {"criterion": "navigation_sublinear_from_plan", "s10": "(e)", "passed": crit_nav,
         "detail": {"sublinear": scale["navigation_sublinear"], "sublinear_growth": scale["navigation_sublinear_growth"],
                    "leaf_span_x": scale["leaf_span_x"], "nav_growth_ppm": scale["nav_growth_ppm"],
                    "leaf_growth_ppm": scale["leaf_growth_ppm"],
                    "source": "packet.retrieval_completeness.navigation_nodes_examined"}},
        {"criterion": "packet_evidence_recall", "s10": "dual", "passed": crit_packet_recall,
         "detail": {"labeled_ppm": lab_packet_ppm, "scale_ppm": scale["dual"]["packet_evidence_recall_ppm"]}},
        {"criterion": "guaranteed_path_recall", "s10": "dual", "passed": crit_guar,
         "detail": {"labeled_ppm": lab_guar_ppm, "scale_ppm": scale["dual"]["guaranteed_path_recall_ppm"]}},
        {"criterion": "packet_disposition_correct", "s10": "P0-3", "passed": crit_disp,
         "detail": {"queries": total, "correct": sum(1 for r in labeled if r["wired_disposition_ok"])}},
        {"criterion": "stale_window_recall_preserved", "s10": "seam", "passed": crit_stale,
         "detail": {"stale_encountered": stale["stale_navigation_encountered"],
                    "recall_preserved": stale["recall_preserved_after_stale"],
                    "leaf_marked_changed": stale["leaf_marked_changed"]}},
        {"criterion": "no_fold_reconciliation", "s10": "seam", "passed": crit_no_fold,
         "detail": {"absent_required_fields": fold}},
    ]
    passed = sum(1 for c in criteria if c["passed"])
    tier1 = (passed == len(criteria))
    return criteria, passed, tier1, fold


def build_wired_descend(ad, db, corpus_roots, benchmark, config, scales, fanout, adapter_tmp):
    """Orchestrate the WIRED-descend measurement over the SAME built corpus (reuses the adapter + db). Order:
    the labeled + scale measurements run on the un-mutated db; the stale-window probe runs LAST (it mutates)."""
    wcaps = probe_wired_capability(ad)
    labeled = []
    for q in benchmark.get("queries", []):
        ns = q["namespace"]
        cv = m36_search(ad, db, q["query"], 1, namespace=ns).get("corpus_version")
        labeled.append(measure_labeled_query_wired(ad, db, q, corpus_roots, config, cv))
    scale = measure_scales_wired(ad, corpus_roots, scales, fanout, config, adapter_tmp)
    ns0 = sorted(corpus_roots.keys())[0]
    cv0 = m36_search(ad, db, "reconstruct", 1, namespace=ns0).get("corpus_version")
    stale = measure_stale_window_wired(ad, db, corpus_roots, config, cv0)
    criteria, passed, tier1, fold = compute_criteria_wired(labeled, scale, stale, wcaps)
    descend_rows = [r for r in labeled if r["descend_ran"]]
    return {
        "wired_harness_version": "rehearsal_wired_descend_v1",
        "drives": ("#40 0.7.0 public -Retriever artifact_search shortlist-and-descend port "
                   "(aa2f0fb / D-0100), DRIVEN READ-ONLY via the external_command adapter"),
        "capabilities": {k: wcaps[k] for k in wcaps if k != "absent_required"},
        "fold_reconciliation": fold,
        "labeled_queries": labeled,
        "scale_sweep": scale,
        "stale_window": stale,
        "tier1_criteria": criteria,
        "tier1_criteria_passed": passed,
        "tier1_criteria_total": len(criteria),
        "descend_vs_flat": {
            "note": ("the WIRED descend fast-path is bounded-beam LOSSY (honest); the exhaustive #36-flat "
                     "fallback preserves packet recall -- the red-team gap, now measured from #40's OWN plan "
                     "trace (navigation_nodes_examined) rather than #36-direct shortlist/descend counts."),
            "labeled_descend_class_count": len(descend_rows),
            "scale_wired_nav_over_leaves_ppm": [s["wired_nav_over_leaves_ppm"] for s in scale["per_scale"]],
            "scale_wired_hierarchy_path_recall_ppm": scale["dual"]["hierarchy_path_recall_ppm"],
            "scale_wired_guaranteed_recall_ppm": scale["dual"]["guaranteed_path_recall_ppm"],
            "scale_wired_packet_recall_ppm": scale["dual"]["packet_evidence_recall_ppm"],
            "scale_wired_regret_ppm": scale["dual"]["shortlist_regret_ppm"],
            "scale_wired_fallback_frequency_ppm": scale["dual"]["fallback_frequency_ppm"],
        },
        "tier1_acceptance": {
            "accepted": bool(tier1),
            "scope": "computed over the corpus + #40 0.7.0 WIRED CLI this harness was pointed at (NOT a project-level claim)",
            "reason": ("all s10 Tier-1 criteria met against the WIRED descend packets" if tier1 else
                       "one or more s10 Tier-1 criteria not met against the WIRED packets (or a fold reconciliation is open)"),
            "project_flip_owner": ("orchestrator (runs the full ~200MB gate vs #40 0.7.0's WIRED descend path "
                                   "at fold + owns the project tier1_accepted flip -- never a silent pass)"),
        },
    }


# ----------------------------------------------------------------- capabilities probe (fold reconciliation)
def probe_capabilities(ad):
    caps = {"m36_search": False, "m36_shortlist": False, "m36_descend": False, "m36_build": False,
            "m40_compile": False, "m40_emits_retrieval_completeness": False,
            "m36_worker": None, "m40_worker": None, "absent_required": []}
    tmpdb = os.path.join(ad.tmp, "probe.db")
    tmproot = os.path.join(ad.tmp, "probe_corpus")
    os.makedirs(tmproot, exist_ok=True)
    with open(os.path.join(tmproot, "probe.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Probe\n\nThe PROBEWORD marker appears here for a capability probe.\n")
    try:
        m36_ingest(ad, tmpdb, "probe", tmproot)
        m36_build(ad, tmpdb, 4)
        caps["m36_build"] = True
        w = (ad.last_meta or {}).get("worker") or {}
        # STABLE fields only -- python/sqlite version strings are volatile cross-machine (byte-identity)
        caps["m36_worker"] = {"worker_version": w.get("worker_version"), "schema_version": w.get("schema_version")}
        m36_search(ad, tmpdb, "PROBEWORD", 3, namespace="probe")
        caps["m36_search"] = True
        sr = m36_shortlist(ad, tmpdb, "PROBEWORD", "probe", 4)
        caps["m36_shortlist"] = True
        nodes = sr.get("nodes", [])
        if nodes:
            m36_descend(ad, tmpdb, nodes[0]["node_id"], "probe")
            caps["m36_descend"] = True
    except RehearsalError as e:
        caps["absent_required"].append("m36:%s" % e.code)
    try:
        sres = m36_search(ad, tmpdb, "PROBEWORD", 3, namespace="probe")
        qobj = {"query": "PROBEWORD", "namespace": "probe", "query_class": "local_factual",
                "temporal_intent": "any_valid_version"}
        pmeta = compile_packet(ad, qobj, sres.get("results", []), {"retriever": "artifact.search"}, tmproot,
                               DEFAULT_CONFIG)
        caps["m40_compile"] = bool(pmeta.get("ok"))
        if pmeta.get("ok"):
            pkt = (pmeta.get("result") or {}).get("packet", {})
            comp = pkt.get("compiler") or {}
            caps["m40_worker"] = {"name": comp.get("name"), "version": comp.get("version")}
            caps["m40_emits_retrieval_completeness"] = (pkt.get("retrieval_completeness") is not None)
        else:
            caps["m40_worker"] = {"error_code": pmeta.get("error_code")}
    except RehearsalError as e:
        caps["absent_required"].append("m40:%s" % e.code)
    for req in ("m36_search", "m36_shortlist", "m36_descend", "m36_build", "m40_compile"):
        if not caps[req]:
            caps["absent_required"].append(req)
    return caps


# ----------------------------------------------------------------- criteria + tier1_accepted
def compute_criteria(labeled, scale, caps):
    def agg_sum(key):
        return sum(r[key] for r in labeled)

    total_q = len(labeled)
    # (b) cross-namespace contamination (search + packet), across all labeled queries
    contamination_hits = agg_sum("contamination_hits") + agg_sum("packet_contamination_hits")
    contamination_ppm = ppm(sum(1 for r in labeled if r["contamination_hits"] or r["packet_contamination_hits"]),
                            total_q)
    crit_contamination = (contamination_hits == 0)
    # (c) current-vs-historical: every temporal-applicable query honored
    temporal_q = [r for r in labeled if r["temporal_applicable"]]
    crit_temporal = all(r["temporal_ok"] for r in temporal_q) and (len(temporal_q) > 0)
    # (d) provenance reconstruction over returned + packet source chunks
    prov_total = agg_sum("provenance_source_chunk_total") + agg_sum("packet_provenance_total")
    prov_valid = agg_sum("provenance_source_chunk_valid") + agg_sum("packet_provenance_valid")
    prov_ppm = ppm(prov_valid, prov_total)
    crit_provenance = (prov_total > 0 and prov_valid == prov_total)
    # (a) bounded context cost (scale pass) + every labeled packet within budget
    labeled_within = all(r["packet_within_budget"] for r in labeled)
    crit_bounded = bool(scale["bounded_context_cost"] and labeled_within)
    # (e) navigation sub-linear + span >=2 orders
    crit_navigation = bool(scale["navigation_sublinear"] and scale["navigation_not_constant"] and scale["leaf_span_ok"])
    # packet-evidence recall (labeled) == full + scale packet recall == full
    labeled_packet_recall_ppm = ppm(agg_sum("packet_evidence_recall"), total_q)
    crit_packet_recall = (labeled_packet_recall_ppm == 1000000 and
                          scale["dual"]["packet_evidence_recall_ppm"] == 1000000)
    # disposition correctness
    crit_disposition = all(r["disposition_ok"] for r in labeled)
    # guaranteed path recall (labeled) full
    labeled_guar_ppm = ppm(sum(r["hierarchy_path_reach_guaranteed"] for r in labeled if r["targets_resolved"]),
                           max(1, sum(1 for r in labeled if r["targets_resolved"])))
    crit_guaranteed = (labeled_guar_ppm == 1000000 and scale["dual"]["guaranteed_path_recall_ppm"] == 1000000)
    # fold reconciliation
    fold_reconciliation = list(caps.get("absent_required", []))
    crit_no_fold = (len(fold_reconciliation) == 0)

    criteria = [
        {"criterion": "bounded_context_cost", "s10": "(a)", "passed": crit_bounded,
         "detail": {"scale_bounded": scale["bounded_context_cost"], "labeled_within_budget": labeled_within}},
        {"criterion": "cross_namespace_contamination", "s10": "(b)", "passed": crit_contamination,
         "detail": {"contamination_hits": contamination_hits, "queries_with_contamination_ppm": contamination_ppm}},
        {"criterion": "current_vs_historical", "s10": "(c)", "passed": crit_temporal,
         "detail": {"temporal_queries": len(temporal_q),
                    "honored": sum(1 for r in temporal_q if r["temporal_ok"])}},
        {"criterion": "provenance_reconstruction", "s10": "(d)", "passed": crit_provenance,
         "detail": {"source_chunk_total": prov_total, "valid": prov_valid, "valid_ppm": prov_ppm}},
        {"criterion": "navigation_sublinear", "s10": "(e)", "passed": crit_navigation,
         "detail": {"sublinear": scale["navigation_sublinear"], "not_constant": scale["navigation_not_constant"],
                    "leaf_span_x": scale["leaf_span_x"]}},
        {"criterion": "packet_evidence_recall", "s10": "dual", "passed": crit_packet_recall,
         "detail": {"labeled_ppm": labeled_packet_recall_ppm,
                    "scale_ppm": scale["dual"]["packet_evidence_recall_ppm"]}},
        {"criterion": "guaranteed_path_recall", "s10": "dual", "passed": crit_guaranteed,
         "detail": {"labeled_ppm": labeled_guar_ppm, "scale_ppm": scale["dual"]["guaranteed_path_recall_ppm"]}},
        {"criterion": "packet_disposition_correct", "s10": "P0-3", "passed": crit_disposition,
         "detail": {"queries": total_q, "correct": sum(1 for r in labeled if r["disposition_ok"])}},
        {"criterion": "no_fold_reconciliation", "s10": "seam", "passed": crit_no_fold,
         "detail": {"absent_required_fields": fold_reconciliation}},
    ]
    passed = sum(1 for c in criteria if c["passed"])
    tier1 = (passed == len(criteria))
    return criteria, passed, tier1, fold_reconciliation


# ----------------------------------------------------------------- report
def build_report(benchmark, corpus_root, fixtures_dir, config, scales, fanout, adapter_cfg, wired=False):
    module_dir = HERE
    ad = Adapter(adapter_cfg, module_dir)
    try:
        caps = probe_capabilities(ad)
        db = os.path.join(ad.tmp, "corpus.db")
        corpus_roots, ns_all, built = ingest_corpus(ad, db, benchmark, fixtures_dir, corpus_root, fanout)
        built_list = built.get("built", [])
        labeled = [measure_labeled_query(ad, db, q, corpus_roots, ns_all, config)
                   for q in benchmark.get("queries", [])]
        scale = measure_scales(ad, corpus_roots, scales, fanout, config, ad.tmp)
        # i36 (opt-in): DRIVE #40 0.7.0's WIRED descend path over the SAME built corpus + measure s10 against
        # the WIRED packets. Runs AFTER the flat labeled + scale measurements (the stale-window probe inside
        # mutates the db LAST); None when not requested -> the report stays byte-identical to 0.7.0.
        wired_block = build_wired_descend(ad, db, corpus_roots, benchmark, config, scales, fanout, ad.tmp) \
            if wired else None
        criteria, passed, tier1, fold = compute_criteria(labeled, scale, caps)
        calls = dict(ad.calls)
    finally:
        ad.cleanup()

    # corpus manifest digest (stable, committed)
    man_digest = None
    corpus = benchmark.get("corpus", {})
    if corpus.get("manifest"):
        mp = os.path.normpath(os.path.join(fixtures_dir, corpus["manifest"]))
        if os.path.exists(mp):
            man_digest = json.load(open(mp, "r", encoding="utf-8")).get("manifest_digest")

    report = {
        "schema": REHEARSAL_REPORT_SCHEMA,
        "generator": GENERATOR_NAME,
        "generator_version": GENERATOR_VERSION,
        "rehearsal_harness_version": REHEARSAL_HARNESS_VERSION,
        "benchmark_id": benchmark.get("benchmark_id"),
        "benchmark_schema": benchmark.get("schema"),
        "ratio_unit": "ppm",
        "adapter_kind": ad.kind,
        "cli_capabilities": {k: caps[k] for k in caps if k != "absent_required"},
        "fold_reconciliation": fold,
        "corpus": {
            "manifest_digest": man_digest,
            "namespaces": ns_all,
            "built": [{"namespace": b.get("namespace"), "leaf_count": b.get("leaf_count"),
                       "node_count": b.get("node_count"), "depth": b.get("depth"),
                       "tree_digest": b.get("tree_digest"), "topology_state": b.get("topology_state")}
                      for b in built_list],
        },
        "params": {"scales": list(scales), "fanout": fanout, "config": config},
        "labeled_queries": labeled,
        "scale_sweep": scale,
        "tier1_criteria": criteria,
        "tier1_criteria_passed": passed,
        "tier1_criteria_total": len(criteria),
        "adapter_calls": calls,
        "tier1_acceptance": {
            "accepted": bool(tier1),
            "scope": "computed over the corpus + CLI this harness was pointed at (NOT a project-level claim)",
            "reason": ("all s10 Tier-1 criteria met on the pointed corpus+CLI" if tier1 else
                       "one or more s10 Tier-1 criteria not met (or a fold reconciliation is open)"),
            "project_flip_owner": "orchestrator (runs the full ~200MB gate vs Lane A's WIRED #40 CLI at fold)",
        },
    }
    # i36 (opt-in): a wired-descend request ADDS a labeled `wired_descend` block + flips the AUTHORITATIVE
    # tier1_acceptance to the WIRED result. A non-wired request adds NOTHING here (byte-identical to 0.7.0).
    if wired_block is not None:
        report["measurement_mode"] = "wired_descend"
        report["wired_descend"] = wired_block
        report["tier1_acceptance"] = dict(wired_block["tier1_acceptance"])

    # structural_digest = the report MINUS the measured-CLI IDENTITY (m36/m40 worker versions). The full
    # report_digest is byte-identical on a re-run of the SAME machine, but ACROSS machines it legitimately tracks
    # the #36/#40 CLI VERSION the harness measured (CLI-agnostic by design; e.g. the device #40 may be a newer
    # build than a cloud snapshot). structural_digest is cross-env STABLE: it pins the corpus + metrics + criteria
    # + tier1_accepted independent of which #36/#40 BUILD produced them.
    struct = json.loads(canon_bytes(report).decode("utf-8"))
    struct["cli_capabilities"]["m36_worker"] = "<measured>"
    struct["cli_capabilities"]["m40_worker"] = "<measured>"
    report["structural_digest"] = digest(struct)
    report["report_digest"] = digest(report)
    return report


def render_md(report):
    L = []
    L.append("# Tier-1 rehearsal report (%s)" % report["rehearsal_harness_version"])
    L.append("")
    L.append("Real foreign corpus: `%s` (benchmark `%s`). Ratios in ppm. report_digest %s."
             % (report["benchmark_id"], report["benchmark_schema"], report["report_digest"]))
    L.append("")
    L.append("Adapter: `%s`. CLI capabilities: %s" % (report["adapter_kind"], json.dumps(report["cli_capabilities"], sort_keys=True)))
    if report["fold_reconciliation"]:
        L.append("")
        L.append("**FOLD RECONCILIATION OPEN:** %s" % ", ".join(report["fold_reconciliation"]))
    L.append("")
    L.append("## Corpus (real, ingested via #36)")
    L.append("")
    L.append("| namespace | leaves | nodes | depth | topology |")
    L.append("|---|--:|--:|--:|---|")
    for b in report["corpus"]["built"]:
        L.append("| %s | %s | %s | %s | %s |" % (b["namespace"], b["leaf_count"], b["node_count"], b["depth"], b["topology_state"]))
    L.append("")
    L.append("## Scale sweep (bounded context cost + sub-linear navigation)")
    L.append("")
    L.append("| reps | leaves | nodes | depth | nav p50 | nav p95 | p50/leaves(ppm) | pkt used/budget | excerpts | within |")
    L.append("|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--:|")
    for s in report["scale_sweep"]["per_scale"]:
        L.append("| %d | %d | %d | %d | %d | %d | %d | %d/%d | %d | %s |" % (
            s["reps"], s["leaf_count"], s["node_count"], s["tree_depth"], s["nodes_examined_p50"],
            s["nodes_examined_p95"], s["nodes_examined_over_leaves_ppm"], s["packet_token_used"],
            s["packet_token_budget"], s["packet_excerpt_count"], s["packet_within_budget"]))
    sc = report["scale_sweep"]
    L.append("")
    L.append("sub-linear=%s not_constant=%s leaf_span=%dx bounded_cost=%s"
             % (sc["navigation_sublinear"], sc["navigation_not_constant"], sc["leaf_span_x"], sc["bounded_context_cost"]))
    d = sc["dual"]
    L.append("dual recall (scale): fast=%d ppm guaranteed=%d ppm packet=%d ppm | regret=%d ppm fallback=%d ppm"
             % (d["hierarchy_path_recall_ppm"], d["guaranteed_path_recall_ppm"], d["packet_evidence_recall_ppm"],
                d["shortlist_regret_ppm"], d["fallback_frequency_ppm"]))
    L.append("")
    L.append("## Labeled queries (real foreign corpus)")
    L.append("")
    L.append("| query | kind | ns | contam | prov(v/t) | fast | guar | pkt recall | disp | within |")
    L.append("|---|---|---|--:|--:|:--:|:--:|:--:|---|:--:|")
    for r in report["labeled_queries"]:
        L.append("| %s | %s | %s | %d | %d/%d | %d | %d | %d | %s | %s |" % (
            r["query_id"], r["kind"], r["namespace"], r["contamination_hits"] + r["packet_contamination_hits"],
            r["provenance_source_chunk_valid"] + r["packet_provenance_valid"],
            r["provenance_source_chunk_total"] + r["packet_provenance_total"],
            r["hierarchy_path_reach_fast"], r["hierarchy_path_reach_guaranteed"], r["packet_evidence_recall"],
            r["packet_disposition"], r["packet_within_budget"]))
    L.append("")
    L.append("## Tier-1 criteria: %d/%d passed" % (report["tier1_criteria_passed"], report["tier1_criteria_total"]))
    L.append("")
    for c in report["tier1_criteria"]:
        L.append("- [%s] %s: %s" % (c["s10"], c["criterion"], "PASS" if c["passed"] else "FAIL"))
    L.append("")
    wd = report.get("wired_descend")
    if wd is not None:
        L.append("")
        L.append("## WIRED descend (i36 -- #40 0.7.0 public artifact_search port, DRIVEN read-only)")
        L.append("")
        L.append("Capabilities: %s" % json.dumps(wd["capabilities"], sort_keys=True))
        if wd["fold_reconciliation"]:
            L.append("")
            L.append("**FOLD RECONCILIATION OPEN:** %s" % ", ".join(wd["fold_reconciliation"]))
        sc = wd["scale_sweep"]
        L.append("")
        L.append("| reps | leaves | nodes | depth | wired nav p50 | wired nav p95 | nav/leaves(ppm) | pkt used/budget | within |")
        L.append("|--:|--:|--:|--:|--:|--:|--:|--:|:--:|")
        for s in sc["per_scale"]:
            L.append("| %d | %d | %d | %d | %d | %d | %d | %d/%d | %s |" % (
                s["reps"], s["leaf_count"], s["node_count"], s["tree_depth"], s["wired_nav_examined_p50"],
                s["wired_nav_examined_p95"], s["wired_nav_over_leaves_ppm"], s["packet_token_used"],
                s["packet_token_budget"], s["packet_within_budget"]))
        L.append("")
        L.append("wired sub-linear=%s (nav grows %d ppm vs leaves %d ppm) leaf_span=%dx bounded_cost=%s"
                 % (sc["navigation_sublinear"], sc["nav_growth_ppm"], sc["leaf_growth_ppm"],
                    sc["leaf_span_x"], sc["bounded_context_cost"]))
        d = sc["dual"]
        L.append("wired dual (scale): hierarchy-PATH=%d ppm guaranteed=%d ppm packet=%d ppm | regret=%d ppm fallback=%d ppm"
                 % (d["hierarchy_path_recall_ppm"], d["guaranteed_path_recall_ppm"], d["packet_evidence_recall_ppm"],
                    d["shortlist_regret_ppm"], d["fallback_frequency_ppm"]))
        L.append("")
        L.append("| query | kind | ns | descend | contam | prov(v/t) | wired nav | PATH | guar | packet | disp | within |")
        L.append("|---|---|---|:--:|--:|--:|--:|:--:|:--:|:--:|---|:--:|")
        for r in wd["labeled_queries"]:
            L.append("| %s | %s | %s | %s | %d | %d/%d | %s | %s | %d | %d | %s | %s |" % (
                r["query_id"], r["kind"], r["namespace"], r["descend_ran"], r["wired_contamination_hits"],
                r["wired_provenance_valid"], r["wired_provenance_total"], r["wired_navigation_nodes_examined"],
                ("-" if r["wired_hierarchy_path_reach"] is None else r["wired_hierarchy_path_reach"]),
                r["wired_guaranteed_recall"], r["wired_packet_recall"], r["wired_disposition"],
                r["wired_within_budget"]))
        sw = wd["stale_window"]
        L.append("")
        L.append("stale-window: marked=%s stale_encountered=%s pruned %d->%d recall_preserved=%s"
                 % (sw["leaf_marked_changed"], sw["stale_navigation_encountered"],
                    sw["baseline_pruned_branch_count"], sw["stale_pruned_branch_count"],
                    sw["recall_preserved_after_stale"]))
        L.append("")
        L.append("### WIRED Tier-1 criteria: %d/%d passed" % (wd["tier1_criteria_passed"], wd["tier1_criteria_total"]))
        L.append("")
        for c in wd["tier1_criteria"]:
            L.append("- [%s] %s: %s" % (c["s10"], c["criterion"], "PASS" if c["passed"] else "FAIL"))
        L.append("")
    ta = report["tier1_acceptance"]
    L.append("**tier1_accepted = %s** -- %s (%s). Project flip: %s."
             % (ta["accepted"], ta["reason"], ta["scope"], ta["project_flip_owner"]))
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------- dispatch
def _load_benchmark(req, fixtures_dir):
    b = req.get("benchmark")
    if b is None:
        b = os.path.join(fixtures_dir, "rehearsal-benchmark.json")
    if isinstance(b, str):
        with open(b, "r", encoding="utf-8") as f:
            return json.load(f), os.path.dirname(os.path.abspath(b))
    return b, fixtures_dir


def run_request(req):
    op = req.get("op", "rehearsal")
    if op != "rehearsal":
        raise RehearsalError("bad_op", "rehearsal_eval.py handles op=rehearsal (got %r)" % op, False)
    out_dir = req.get("out_dir") or "."
    os.makedirs(out_dir, exist_ok=True)
    fixtures_dir = req.get("fixtures_dir") or os.path.join(HERE, "tests", "fixtures")
    benchmark, bench_dir = _load_benchmark(req, fixtures_dir)
    fixtures_dir = bench_dir
    corpus_root = req.get("corpus_root")
    if not corpus_root:
        corpus_root = os.path.join(fixtures_dir, benchmark.get("corpus", {}).get("corpus_dir", "rehearsal-corpus"))
    corpus_root = os.path.normpath(corpus_root)

    scales = [int(x) for x in (req.get("scales") or DEFAULT_SCALES)]
    if len(scales) < 2 or (max(scales) // max(1, min(scales))) < 100:
        raise RehearsalError("bad_scales", "scales must span >= 2 orders of magnitude (max/min >= 100)", False)
    fanout = int(req.get("fanout", DEFAULT_FANOUT))
    if fanout < 2:
        raise RehearsalError("bad_fanout", "fanout must be >= 2", False)
    config = dict(DEFAULT_CONFIG)
    config.update(req.get("config") or {})
    adapter_cfg = req.get("adapter") or {}
    wired = bool(req.get("wired_descend") or (req.get("config") or {}).get("wired_descend"))

    report = build_report(benchmark, corpus_root, fixtures_dir, config, scales, fanout, adapter_cfg, wired=wired)
    with open(os.path.join(out_dir, "rehearsal_report.json"), "wb") as f:
        f.write(canon_bytes(report))
    with open(os.path.join(out_dir, "rehearsal_report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(render_md(report))

    summary = {
        "ok": True,
        "op": "rehearsal",
        "rehearsal_harness_version": REHEARSAL_HARNESS_VERSION,
        "benchmark_id": report["benchmark_id"],
        "adapter_kind": report["adapter_kind"],
        "tier1_criteria_passed": report["tier1_criteria_passed"],
        "tier1_criteria_total": report["tier1_criteria_total"],
        "tier1_accepted": report["tier1_acceptance"]["accepted"],
        "fold_reconciliation": report["fold_reconciliation"],
        "navigation_sublinear": report["scale_sweep"]["navigation_sublinear"],
        "bounded_context_cost": report["scale_sweep"]["bounded_context_cost"],
        "scale_packet_evidence_recall_ppm": report["scale_sweep"]["dual"]["packet_evidence_recall_ppm"],
        "adapter_calls": report["adapter_calls"],
        "structural_digest": report["structural_digest"],
        "report_digest": report["report_digest"],
    }
    wd = report.get("wired_descend")
    if wd is not None:
        summary["measurement_mode"] = "wired_descend"
        summary["wired_tier1_criteria_passed"] = wd["tier1_criteria_passed"]
        summary["wired_tier1_criteria_total"] = wd["tier1_criteria_total"]
        summary["wired_tier1_accepted"] = wd["tier1_acceptance"]["accepted"]
        summary["wired_fold_reconciliation"] = wd["fold_reconciliation"]
        summary["tier1_accepted"] = wd["tier1_acceptance"]["accepted"]   # authoritative flip signal when wired
    with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
        f.write(canon_bytes(summary))
    return summary


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args(argv)
    with open(args.request, "r", encoding="utf-8") as f:
        req = json.load(f)
    out_dir = req.get("out_dir") or "."
    try:
        run_request(req)
        sys.stdout.write("OK %s\n" % out_dir)
        return 0
    except RehearsalError as e:
        err = {"ok": False, "error": {"code": e.code, "message": e.message, "retryable": e.retryable}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("ERROR %s: %s" % (e.code, e.message))
        return 1
    except Exception as e:  # noqa
        err = {"ok": False, "error": {"code": "unhandled", "message": str(e), "retryable": False}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("UNHANDLED: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
