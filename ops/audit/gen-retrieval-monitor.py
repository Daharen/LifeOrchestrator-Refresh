#!/usr/bin/env python3
"""Retrieval-Byte Monitor -- deterministic per-wave rollup (i55, PB-7 observability half; FANOUT_AGENT_002).
i60 upgrade (PB-8, FANOUT_AGENT_001 / II-BOUND-i60): + a FAIL-CLOSED GATE (--gate) and an OPTIONAL
artifact cross-check (--artifacts-dir) so a self-reported zero-bounded-opens session can no longer pass
unnoticed and a ledger can be cross-checked against the query artifacts project.map actually persisted.

READ-ONLY over its INPUT (a ledger file + optional artifact dirs); writes nothing except one appended log
row (+ stdout echo), and NOTHING at all when it rejects (fail-closed). Turns the migration gate's one-shot
A/B charged-retrieval-byte number (D-0146 F-i53-eff; the byte-charging method in
modules/44-project-map/eval/results/I53_RESULTS.md + EFFICIENCY-i53.md: charged bytes == the size of what
actually entered model-visible context, per open) into a STANDING per-wave measurement: one row per close
in ops/out/retrieval-bytes-log.jsonl, mirroring ops/audit/gen-doc-health.py's row-per-close pattern.

This script does NOT observe retrieval itself -- an agent's opens are not filesystem-observable state the
way doc sizes are. It ROLLS UP a session's self-reported LEDGER (one JSON line per open; see LEDGER SCHEMA
below), which the agent appends to as it works (the RETRIEVAL PROTOCOL: "RECORD every open in your ledger").
Increment A's ops/retrieval/retrieve.ps1 makes that append AUTOMATIC for bounded queries (the easy path is
now the measured path). The rollup arithmetic is deterministic (no model judgement): sums and a fraction,
over validated input.

LEDGER SCHEMA (JSONL, one open per line):
  {"kind": <one of "boot_packet"|"section"|"card"|"query"|"whole_doc_open">,
   "target": "<entity id, doc path, or query form -- the thing opened>",
   "bytes": <int > 0 -- charged bytes: the size of what entered model-visible context for this open>,
   "note": "<optional free-text>"}
  - "boot_packet"    the PCB BOOT_PACKET.md read (N4 BOOT bar: <= 20,000 B).
  - "section"/"card"/"query"   a bounded PCB fetch (project_map.py query --q 'section:...'/'card:...'/
    any other bounded --q form) -- these are the retrieval the RETRIEVAL PROTOCOL steers agents toward.
    Increment A's affordance charges these its canonical-minified query-result-payload byte size.
  - "whole_doc_open" a full-file ingest (Read / project_read / a plain file open) -- the expensive default;
    charged its full on-disk byte size, matching the gate's accounting (verified: this monitor's own
    ops/audit/retrieval-ledger/i55-agent002.jsonl first row reproduces CURRENT_STATE.md's 34,319 B and
    FANOUT_ORCHESTRATOR_HANDOFF.md's ~24,093 B exactly against I53/EFFICIENCY-i53's charged figures).
  Unknown keys, a non-mapping line, an unrecognized kind, an empty/non-string target, or a non-positive-int
  bytes value are FAIL-CLOSED: the whole run rejects (exit 1) and NOTHING is appended -- a bad ledger must
  not silently under- or over-count. Blank lines are skipped.

OUTPUT ROW (one JSON object appended to ops/out/retrieval-bytes-log.jsonl per --iteration close):
  {date, iteration, boot_packet_bytes, total_charged_bytes, whole_doc_open_bytes, bounded_query_bytes,
   bounded_fraction, whole_doc_opens: [{target,bytes,warnings}], n_queries, boot_packet_bar: {limit_bytes,
   status}, warnings: [{target,bytes,reasons}], ledger_entries, ledger_source}
   [+ "gate": {status} only when --gate is passed AND the gate does not trip]
   [+ "cross_check": {dirs, artifacts_scanned, query_artifacts, unbacked, unrecorded} only when
     --artifacts-dir is passed]
  bounded_fraction = bounded_query_bytes / total_charged_bytes (bounded = section+card+query kinds only;
  null when total_charged_bytes is 0). boot_packet_bar reports (does not gate) boot_packet_bytes against the
  N4 BOOT bar (20,000 B; D-0140). A whole_doc_open of a re-layer-eligible cumulative doc (DECISION_LOG.md /
  DECISION_LOG_INDEX.md) or of anything > 40,000 B (the DOC_PROTOCOL s2 re-layer trigger) is a WARN, not a
  reject -- surfaced in "warnings" and echoed per-entry in "whole_doc_opens[].warnings".

--gate (FAIL-CLOSED, i60 B): when set and whole_doc_open_bytes > 0 AND bounded_query_bytes == 0, the run
  REJECTS (exit 1, machine reason "zero_bounded_opens" on stdout, nothing appended) -- a session that
  whole-opened docs but issued zero bounded queries can no longer pass silently. Otherwise the gate passes
  (exit 0, row appended with a "gate":{"status":"pass"} field). An empty ledger, or one with no whole-doc
  opens, does not trip (nothing was whole-opened to object to). The orchestrator wires --gate into the ops
  wave-close so the assertion runs every wave.

--artifacts-dir DIR (repeatable, i60 B): cross-check the ledger against the result.json artifacts
  project.map's wrapper persists per query (modules/30-orchestrate-fanout/runtime/artifacts/*/result.json,
  modules/44-project-map/runtime/artifacts/*/result.json). A bounded ledger entry whose target matches NO
  query artifact => 'unbacked'; a query artifact whose q matches NO bounded ledger entry => 'unrecorded'.
  Both are surfaced in the row's "cross_check" object, NEVER silently dropped; both are WARN-level (exit
  code unchanged -- they never by themselves reject). Each DIR is scanned as <DIR>/*/result.json.

Usage:  python ops/audit/gen-retrieval-monitor.py --ledger <path> --iteration <N> [--date YYYY-MM-DD]
                                                    [--repo PATH] [--out-dir PATH] [--gate]
                                                    [--artifacts-dir DIR [--artifacts-dir DIR ...]]
Exit codes: 0 = row emitted; 1 = ledger content rejected OR --gate tripped (fail-closed, nothing written);
            2 = usage/I-O error.
"""
import argparse
import glob
import json
import os
import sys

KB = 1000
BOUNDED_KINDS = ("section", "card", "query")
ALL_KINDS = ("boot_packet", "section", "card", "query", "whole_doc_open")
ALLOWED_ENTRY_KEYS = {"kind", "target", "bytes", "note"}
CUMULATIVE_DOC_BASENAMES = {"DECISION_LOG.md", "DECISION_LOG_INDEX.md"}
RELAYER_TRIGGER_BYTES = 40000          # DOC_PROTOCOL s2: "re-layer ~40 KB (PB-7)"
N4_BOOT_BAR_BYTES = 20000              # D-0140/N4 re-freeze: BOOT_PACKET <= 20,000 B
GATE_ZERO_BOUNDED = "zero_bounded_opens"   # i60 B fail-closed gate machine reason


class LedgerError(Exception):
    """A ledger line failed validation -- fail-closed, caller rejects the whole run."""


def _basename(target):
    return target.replace("\\", "/").rsplit("/", 1)[-1]


def parse_ledger(path):
    """Read + validate a ledger JSONL file. Returns a list of {kind,target,bytes,note} dicts in file order.
    Raises LedgerError on the first invalid line (fail-closed: no partial/best-effort parse)."""
    entries = []
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                raise LedgerError("line %d: not valid JSON (%s)" % (lineno, e))
            if not isinstance(obj, dict):
                raise LedgerError("line %d: entry is not a JSON object" % lineno)
            extra = set(obj.keys()) - ALLOWED_ENTRY_KEYS
            if extra:
                raise LedgerError("line %d: unrecognized key(s) %s" % (lineno, sorted(extra)))
            missing = {"kind", "target", "bytes"} - set(obj.keys())
            if missing:
                raise LedgerError("line %d: missing required key(s) %s" % (lineno, sorted(missing)))
            kind = obj["kind"]
            if kind not in ALL_KINDS:
                raise LedgerError("line %d: kind %r not in %s" % (lineno, kind, ALL_KINDS))
            target = obj["target"]
            if not isinstance(target, str) or not target.strip():
                raise LedgerError("line %d: target must be a non-empty string" % lineno)
            b = obj["bytes"]
            if isinstance(b, bool) or not isinstance(b, int) or b <= 0:
                raise LedgerError("line %d: bytes must be a positive integer, got %r" % (lineno, b))
            note = obj.get("note")
            if note is not None and not isinstance(note, str):
                raise LedgerError("line %d: note must be a string if present" % lineno)
            entries.append({"kind": kind, "target": target, "bytes": b, "note": note})
    return entries


def _entry_warnings(target, b):
    reasons = []
    if _basename(target) in CUMULATIVE_DOC_BASENAMES:
        reasons.append("cumulative_doc")
    if b > RELAYER_TRIGGER_BYTES:
        reasons.append("over_40kb_threshold")
    return reasons


def _iter_result_json(dirs):
    """Yield (path, parsed_envelope) for every <DIR>/*/result.json across dirs, in sorted path order.
    Unreadable / non-JSON artifacts are skipped (yielded as (path, None)); nothing here mutates state."""
    seen = set()
    for d in dirs:
        pattern = os.path.join(d, "*", "result.json")
        for path in sorted(glob.glob(pattern)):
            ap = os.path.abspath(path)
            if ap in seen:
                continue
            seen.add(ap)
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    yield path, json.loads(fh.read())
            except (OSError, ValueError, RecursionError):
                # RecursionError: json.loads on a deeply-nested planted artifact (NOT a ValueError). The
                # artifacts dir accumulates untrusted per-wave files, so a scan MUST never crash wave-close
                # on one bad file -- count it as unparseable and move on (i60 red-team RT-B #4).
                yield path, None


def _artifact_query_form(env):
    """Return the query form q of a project.map QUERY artifact, else None (validate/verify/render/etc.
    carry no result.q). A query artifact is an envelope whose result is a dict containing key 'q'."""
    if not isinstance(env, dict):
        return None
    result = env.get("result")
    if isinstance(result, dict):
        q = result.get("q")
        if isinstance(q, str) and q.strip():
            return q
    return None


def cross_check(entries, dirs):
    """Cross-check bounded ledger targets against persisted query artifacts (i60 B). Returns a dict:
    {dirs, artifacts_scanned, query_artifacts, unbacked, unrecorded, unparseable}. Deterministic (sorted).
    unbacked  = bounded ledger target with NO matching query artifact q.
    unrecorded = query artifact q with NO matching bounded ledger target.
    Both are WARN-level and always fully listed -- never silently dropped."""
    dirs = sorted(set(dirs))
    bounded_targets = sorted({e["target"] for e in entries if e["kind"] in BOUNDED_KINDS})
    artifact_qs = []
    scanned = 0
    unparseable = 0
    for _path, env in _iter_result_json(dirs):
        scanned += 1
        if env is None:
            unparseable += 1
            continue
        q = _artifact_query_form(env)
        if q is not None:
            artifact_qs.append(q)
    artifact_q_set = set(artifact_qs)
    ledger_target_set = set(bounded_targets)
    unbacked = sorted(t for t in bounded_targets if t not in artifact_q_set)
    unrecorded = sorted({q for q in artifact_qs if q not in ledger_target_set})
    return {
        "dirs": dirs,
        "artifacts_scanned": scanned,
        "query_artifacts": len(artifact_qs),
        "unparseable": unparseable,
        "unbacked": unbacked,
        "unrecorded": unrecorded,
    }


def compute_row(entries, date, iteration, ledger_source, cross_check_result=None, gate=False):
    boot_packet_bytes = sum(e["bytes"] for e in entries if e["kind"] == "boot_packet")
    whole_doc = [e for e in entries if e["kind"] == "whole_doc_open"]
    bounded = [e for e in entries if e["kind"] in BOUNDED_KINDS]
    whole_doc_open_bytes = sum(e["bytes"] for e in whole_doc)
    bounded_query_bytes = sum(e["bytes"] for e in bounded)
    total_charged_bytes = boot_packet_bytes + whole_doc_open_bytes + bounded_query_bytes
    bounded_fraction = (round(bounded_query_bytes / total_charged_bytes, 4)
                         if total_charged_bytes > 0 else None)

    whole_doc_opens = []
    warnings = []
    for e in sorted(whole_doc, key=lambda e: (-e["bytes"], e["target"])):
        reasons = _entry_warnings(e["target"], e["bytes"])
        row = {"target": e["target"], "bytes": e["bytes"]}
        if reasons:
            row["warnings"] = reasons
            warnings.append({"target": e["target"], "bytes": e["bytes"], "reasons": reasons})
        whole_doc_opens.append(row)

    boot_status = "pass" if boot_packet_bytes <= N4_BOOT_BAR_BYTES else "warn"

    row = {
        "date": date,
        "iteration": iteration,
        "boot_packet_bytes": boot_packet_bytes,
        "total_charged_bytes": total_charged_bytes,
        "whole_doc_open_bytes": whole_doc_open_bytes,
        "bounded_query_bytes": bounded_query_bytes,
        "bounded_fraction": bounded_fraction,
        "whole_doc_opens": whole_doc_opens,
        "n_queries": len(bounded),
        "boot_packet_bar": {"limit_bytes": N4_BOOT_BAR_BYTES, "status": boot_status},
        "warnings": warnings,
        "ledger_entries": len(entries),
        "ledger_source": ledger_source,
    }
    # i60 B additions are strictly ADDITIVE + opt-in: a default invocation (no --gate, no --artifacts-dir)
    # produces a byte-identical row to the i55 schema, preserving every existing test + the double-run gate.
    if gate:
        row["gate"] = {"status": "pass", "reason": None}
    if cross_check_result is not None:
        row["cross_check"] = cross_check_result
    return row


def gate_tripped(row):
    """The i60 fail-closed gate condition: docs were whole-opened but ZERO bounded queries were issued."""
    return row["whole_doc_open_bytes"] > 0 and row["bounded_query_bytes"] == 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ledger", required=True, help="path to the session ledger JSONL file")
    ap.add_argument("--iteration", required=True, type=int, help="wave/iteration number, e.g. 55")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD; omit for 'undated' (no sandbox clock)")
    ap.add_argument("--repo", default=None, help="repo root (default: 2 levels up from this file)")
    ap.add_argument("--out-dir", default=None, help="output dir (default: <repo>/ops/out)")
    ap.add_argument("--gate", action="store_true",
                    help="FAIL-CLOSED: reject (exit 1) if docs were whole-opened but zero bounded queries")
    ap.add_argument("--artifacts-dir", action="append", default=None, dest="artifacts_dirs",
                    metavar="DIR", help="scan <DIR>/*/result.json for the ledger<->artifact cross-check "
                                        "(repeatable)")
    a = ap.parse_args(argv)

    repo = a.repo or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = a.out_dir or os.path.join(repo, "ops", "out")
    date = a.date or "undated"

    if not os.path.isfile(a.ledger):
        print("gen-retrieval-monitor: ledger not found: %s" % a.ledger, file=sys.stderr)
        return 2

    try:
        entries = parse_ledger(a.ledger)
    except LedgerError as e:
        print("gen-retrieval-monitor: REJECTED (fail-closed, nothing written): %s" % e, file=sys.stderr)
        return 1

    cc = None
    if a.artifacts_dirs:
        cc = cross_check(entries, a.artifacts_dirs)

    ledger_source = os.path.relpath(os.path.abspath(a.ledger), repo).replace("\\", "/")
    row = compute_row(entries, date, a.iteration, ledger_source, cross_check_result=cc, gate=a.gate)

    # i60 fail-closed gate: decided AFTER the row is computed, BEFORE anything is written. On a trip we
    # emit a machine reason + exit 1 and write NOTHING (identical no-write discipline to a ledger reject).
    if a.gate and gate_tripped(row):
        reason = {
            "gate": GATE_ZERO_BOUNDED,
            "iteration": a.iteration,
            "whole_doc_open_bytes": row["whole_doc_open_bytes"],
            "bounded_query_bytes": row["bounded_query_bytes"],
            "total_charged_bytes": row["total_charged_bytes"],
            "ledger_source": ledger_source,
        }
        print(json.dumps(reason, separators=(",", ":")))
        print("gen-retrieval-monitor: GATE REJECTED (fail-closed, nothing written): %s "
              "(whole_doc_open_bytes=%d, bounded_query_bytes=0)"
              % (GATE_ZERO_BOUNDED, row["whole_doc_open_bytes"]), file=sys.stderr)
        return 1

    os.makedirs(out_dir, exist_ok=True)
    log_path = os.path.join(out_dir, "retrieval-bytes-log.jsonl")
    line = json.dumps(row, separators=(",", ":"))
    with open(log_path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")

    print("OK", log_path)
    print(line)
    summary = ("boot_packet=%dB (bar %s) total=%dB bounded_fraction=%s warnings=%d" % (
        row["boot_packet_bytes"], row["boot_packet_bar"]["status"], row["total_charged_bytes"],
        row["bounded_fraction"], len(row["warnings"])))
    if a.gate:
        summary += " gate=pass"
    if cc is not None:
        summary += " cross_check(unbacked=%d unrecorded=%d over %d artifacts)" % (
            len(cc["unbacked"]), len(cc["unrecorded"]), cc["artifacts_scanned"])
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
