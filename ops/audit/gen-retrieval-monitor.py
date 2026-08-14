#!/usr/bin/env python3
"""Retrieval-Byte Monitor -- deterministic per-wave rollup (i55, PB-7 observability half; FANOUT_AGENT_002).

READ-ONLY over its INPUT (a ledger file); writes nothing except one appended log row (+ stdout echo).
Turns the migration gate's one-shot A/B charged-retrieval-byte number (D-0146 F-i53-eff; the byte-charging
method in modules/44-project-map/eval/results/I53_RESULTS.md + EFFICIENCY-i53.md: charged bytes == the size
of what actually entered model-visible context, per open) into a STANDING per-wave measurement: one row per
close in ops/out/retrieval-bytes-log.jsonl, mirroring ops/audit/gen-doc-health.py's row-per-close pattern.

This script does NOT observe retrieval itself -- an agent's opens are not filesystem-observable state the
way doc sizes are. It ROLLS UP a session's self-reported LEDGER (one JSON line per open; see LEDGER SCHEMA
below), which the agent appends to as it works (the RETRIEVAL PROTOCOL: "RECORD every open in your ledger").
The rollup arithmetic is deterministic (no model judgement): sums and a fraction, over validated input.

LEDGER SCHEMA (JSONL, one open per line):
  {"kind": <one of "boot_packet"|"section"|"card"|"query"|"whole_doc_open">,
   "target": "<entity id, doc path, or query form -- the thing opened>",
   "bytes": <int > 0 -- charged bytes: the size of what entered model-visible context for this open>,
   "note": "<optional free-text>"}
  - "boot_packet"    the PCB BOOT_PACKET.md read (N4 BOOT bar: <= 20,000 B).
  - "section"/"card"/"query"   a bounded PCB fetch (project_map.py query --q 'section:...'/'card:...'/
    any other bounded --q form) -- these are the retrieval the RETRIEVAL PROTOCOL steers agents toward.
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
  bounded_fraction = bounded_query_bytes / total_charged_bytes (bounded = section+card+query kinds only;
  null when total_charged_bytes is 0). boot_packet_bar reports (does not gate) boot_packet_bytes against the
  N4 BOOT bar (20,000 B; D-0140). A whole_doc_open of a re-layer-eligible cumulative doc (DECISION_LOG.md /
  DECISION_LOG_INDEX.md) or of anything > 40,000 B (the DOC_PROTOCOL s2 re-layer trigger) is a WARN, not a
  reject -- surfaced in "warnings" and echoed per-entry in "whole_doc_opens[].warnings".

Usage:  python ops/audit/gen-retrieval-monitor.py --ledger <path> --iteration <N> [--date YYYY-MM-DD]
                                                    [--repo PATH] [--out-dir PATH]
Exit codes: 0 = row emitted; 1 = ledger content rejected (fail-closed, nothing written); 2 = usage/I-O error.
"""
import argparse
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


def compute_row(entries, date, iteration, ledger_source):
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

    return {
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


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ledger", required=True, help="path to the session ledger JSONL file")
    ap.add_argument("--iteration", required=True, type=int, help="wave/iteration number, e.g. 55")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD; omit for 'undated' (no sandbox clock)")
    ap.add_argument("--repo", default=None, help="repo root (default: 2 levels up from this file)")
    ap.add_argument("--out-dir", default=None, help="output dir (default: <repo>/ops/out)")
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

    ledger_source = os.path.relpath(os.path.abspath(a.ledger), repo).replace("\\", "/")
    row = compute_row(entries, date, a.iteration, ledger_source)

    os.makedirs(out_dir, exist_ok=True)
    log_path = os.path.join(out_dir, "retrieval-bytes-log.jsonl")
    line = json.dumps(row, separators=(",", ":"))
    with open(log_path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")

    print("OK", log_path)
    print(line)
    print("boot_packet=%dB (bar %s) total=%dB bounded_fraction=%s warnings=%d" % (
        row["boot_packet_bytes"], row["boot_packet_bar"]["status"], row["total_charged_bytes"],
        row["bounded_fraction"], len(row["warnings"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
