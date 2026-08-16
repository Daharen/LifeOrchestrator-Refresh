#!/usr/bin/env python3
"""MANAGER_VIEW generator -- bounded, count-asserted management/audit/steering projection
(i60 Lane 3, FANOUT_AGENT_003, PB-8, D-0155). Reads modules/44-project-map/map/ (entities/*.json +
overlay/state.json) directly and core-docs/PROCESS_BACKLOG.md; renders ops/manager/generated/MANAGER_VIEW.md.

READ-ONLY over all canonical state; writes ONLY under ops/manager/. stdlib Python 3.10 only -- no model,
no network, no git call. Deterministic: same inputs -> byte-identical output (double-run identity; no
wall-clock, no randomness, every collection sorted before render).

This is NOT a per-doc approval gate and NOT the PB-7 cumulative-doc class migration (that DEFERS to i68,
D-0155) -- it is observability/steering for Nicholas: "what does the map say right now."

Sections (fixed order):
  (a) iteration + phase + the one-line overlay frontier summary
  (b) per-PLANE module-status rollup (mvp-complete / design-only / deferred / in-progress / no-status),
      counted over EVERY map entity carrying a plane_primary field (module/widget/ops/store/contract/
      arch-position/doc entities alike) -- NOT just module: entities; see COUNTS line for the module-only
      count. Plane count totals are the number that must reproduce the map's per-plane member counts
      (as of this tree: memory 15 / intelligence 8 / capability 43 / authority 6 / observability 7).
  (c) open FRONTIER CANDIDATES from the overlay
  (d) open PB rows (id + one-line item + trigger) parsed from PROCESS_BACKLOG.md's "## Open" table
  (e) live PROHIBITIONS count + OPEN-RULINGS count, and the SP3/M-03 + SEALED_CHECK status line (the
      D-0132 open ruling text, read verbatim from the overlay -- this generator does not itself evaluate
      SEALED_CHECK_47's predicates; that is a separate, explicitly-licensed act, D-0147)
  (f) a COUNTS line asserting N modules / M planes / K open-PB, each independently re-derived from the
      map/PROCESS_BACKLOG at render time -- never hardcoded. --check fails on any drift, mechanical or
      contentful.

Usage:  python ops/manager/gen-manager-view.py [--repo PATH] [--map-dir PATH] [--process-backlog PATH]
                                                [--sealed-check PATH] [--out PATH] [--date YYYY-MM-DD]
                                                [--check]
Exit codes: 0 = rendered (or --check passed with no drift); 1 = --check found drift; 2 = usage/I-O/map
error (fail-closed -- nothing written).
"""
import argparse
import glob
import hashlib
import json
import os
import re
import sys

SIZE_CAP_BYTES = 12000
STATUS_BUCKETS = ("mvp-complete", "design-only", "deferred", "in-progress", "no-status")
PLANE_PRESENTATION_ORDER = ("plane:memory", "plane:intelligence", "plane:capability",
                             "plane:authority", "plane:observability")


class GenError(Exception):
    """A map/doc read or parse failed in a way that must fail-closed (exit 2, nothing written)."""


def _repo_default():
    # .../<repo>/ops/manager/gen-manager-view.py -> 3 dirname() calls up to <repo>
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def write_lf(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def read_text(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        return fh.read().replace("\r\n", "\n").replace("\r", "\n")


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        raise GenError("cannot read/parse %s: %s" % (path, e))


def _clean_one_line(s):
    """Strip markdown emphasis + collapse whitespace/newlines to a single-line string."""
    if s is None:
        return ""
    s = s.replace("**", "").replace("`", "")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _truncate(s, n):
    if len(s) <= n:
        return s
    return s[: max(0, n - 1)].rstrip() + "…"


# ---------------------------------------------------------------------------
# Map reads
# ---------------------------------------------------------------------------

def load_entities(map_dir):
    """Every entity across every entities/*.json file, in (filename, file-order) order."""
    ent_dir = os.path.join(map_dir, "entities")
    if not os.path.isdir(ent_dir):
        raise GenError("map entities dir not found: %s" % ent_dir)
    entities = []
    for path in sorted(glob.glob(os.path.join(ent_dir, "*.json"))):
        doc = load_json(path)
        items = doc.get("items") if isinstance(doc, dict) else None
        if not isinstance(items, list):
            raise GenError("%s: expected {'items': [...]}" % path)
        for it in items:
            if isinstance(it, dict):
                entities.append(it)
    return entities


def load_overlay(map_dir):
    path = os.path.join(map_dir, "overlay", "state.json")
    if not os.path.isfile(path):
        raise GenError("overlay state not found: %s" % path)
    return load_json(path)


def count_planes(map_dir):
    """M = the number of plane: entities declared in entities/planes.json (the closed plane enum)."""
    planes_path = os.path.join(map_dir, "entities", "planes.json")
    if not os.path.isfile(planes_path):
        raise GenError("planes.json not found: %s" % planes_path)
    doc = load_json(planes_path)
    items = doc.get("items", [])
    return len({it["id"] for it in items if isinstance(it, dict) and it.get("id")})


def count_modules(entities):
    """N = the number of module: entities anywhere in the map (id prefix 'module:')."""
    return len({e["id"] for e in entities if isinstance(e.get("id"), str) and e["id"].startswith("module:")})


def plane_rollup(entities):
    """{plane_id: {status_bucket: count}} over every entity carrying a truthy plane_primary.
    A status outside STATUS_BUCKETS[:-1] (unset, or any value the map has not yet standardized on)
    lands in the 'no-status' catch-all bucket so per-plane bucket totals always equal the plane's
    member count -- no entity is silently dropped from the rollup."""
    rollup = {}
    for e in entities:
        plane = e.get("plane_primary")
        if not plane:
            continue
        plane_id = plane if plane.startswith("plane:") else "plane:%s" % plane
        status = e.get("status")
        bucket = status if status in STATUS_BUCKETS[:-1] else "no-status"
        rollup.setdefault(plane_id, {b: 0 for b in STATUS_BUCKETS})
        rollup[plane_id][bucket] += 1
    return rollup


def plane_order(rollup):
    """Fixed presentation order (memory/intelligence/capability/authority/observability, the closed
    5-plane enum's established convention -- BOOT_PACKET precedent); any plane_primary value the map
    carries that is NOT in that fixed set is appended after it, sorted by id, so a future plane still
    renders deterministically instead of being dropped."""
    known = [p for p in PLANE_PRESENTATION_ORDER if p in rollup]
    extra = sorted(p for p in rollup if p not in PLANE_PRESENTATION_ORDER)
    return known + extra


# ---------------------------------------------------------------------------
# PROCESS_BACKLOG.md '## Open' table parse
# ---------------------------------------------------------------------------

def parse_open_pb_rows(pb_path):
    """Rows of the '## Open' markdown table: [{'id','item','trigger'}], in document order.
    A data row is any line '| PB-<n> | ... | ... | ... |' between the '## Open' heading and the next
    '## ' heading -- deliberately NOT a generic markdown-table parser (header/separator rows never
    start with '| PB-', so this stays simple and exact for this doc's one known table shape)."""
    if not os.path.isfile(pb_path):
        raise GenError("PROCESS_BACKLOG not found: %s" % pb_path)
    text = read_text(pb_path)
    m = re.search(r"^## Open\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        raise GenError("PROCESS_BACKLOG has no '## Open' section")
    section = m.group(1)
    rows = []
    for line in section.splitlines():
        if not re.match(r"^\|\s*PB-\d+\s*\|", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        rows.append({
            "id": cells[0],
            "item": _clean_one_line(cells[1]),
            "trigger": _clean_one_line(cells[2]),
        })
    return rows


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

def _plane_short(plane_id):
    return plane_id.split(":", 1)[-1]


def render(map_dir, pb_path, sealed_check_pointer, date):
    entities = load_entities(map_dir)
    overlay = load_overlay(map_dir)
    n_modules = count_modules(entities)
    m_planes = count_planes(map_dir)
    pb_rows = parse_open_pb_rows(pb_path)
    k_open_pb = len(pb_rows)
    rollup = plane_rollup(entities)

    frontier = overlay.get("frontier", {})
    phase = overlay.get("phase", {})
    prohibitions = overlay.get("prohibitions", [])
    open_rulings = overlay.get("open_rulings", [])
    live_prohibitions = [p for p in prohibitions if p.get("status") == "live"]

    sealed_ruling = next((r for r in open_rulings if r.get("ref") == "decision:D-0132"), None)
    sealed_line = (_clean_one_line(sealed_ruling["text"]) if sealed_ruling
                   else "no open D-0132 (SEALED_CHECK_47 SP3) ruling found in the overlay")

    lines = []
    lines.append("<!-- GENERATED by ops/manager/gen-manager-view.py from modules/44-project-map/map/ "
                  "-- DO NOT EDIT; edit map/ (or PROCESS_BACKLOG.md) + re-render -->")
    lines.append("# MANAGER_VIEW -- Life Orchestrator (bounded management/audit/steering projection)")
    lines.append("purpose: observability + steering for Nicholas over canonical map state -- NOT a "
                  "per-doc approval gate, NOT the PB-7 cumulative-doc class migration (that DEFERS to "
                  "i68, D-0155).")
    lines.append("snapshot: %s" % date)
    lines.append("")

    # (a) iteration + phase + one-line frontier
    lines.append("## ITERATION + PHASE")
    lines.append("iteration: %s (frontier -> %s)" % (overlay.get("iteration", "?"),
                                                       frontier.get("next_iteration", "?")))
    lines.append("phase: %s" % _clean_one_line(phase.get("text")))
    lines.append("frontier (one line): %s" % _clean_one_line(frontier.get("summary")))
    lines.append("")

    # (b) per-plane module-status rollup
    lines.append("## PER-PLANE STATUS ROLLUP")
    for plane_id in plane_order(rollup):
        counts = rollup[plane_id]
        total = sum(counts.values())
        detail = " | ".join("%s=%d" % (b, counts[b]) for b in STATUS_BUCKETS if counts[b])
        lines.append("plane: %s (%d) -- %s" % (_plane_short(plane_id), total, detail or "no members"))
    lines.append("")

    # (c) frontier candidates
    lines.append("## FRONTIER CANDIDATES")
    candidates = frontier.get("candidates", [])
    if not candidates:
        lines.append("(none open)")
    for c in candidates:
        lines.append("- [%s] %s -> %s" % (_clean_one_line(c.get("gate")),
                                           _truncate(_clean_one_line(c.get("item")), 160),
                                           c.get("pointer", "")))
    lines.append("")

    # (d) open PB rows
    lines.append("## OPEN PROCESS_BACKLOG ROWS (%d)" % k_open_pb)
    for r in pb_rows:
        lines.append("- %s: %s | trigger: %s" % (r["id"], _truncate(r["item"], 200),
                                                   _truncate(r["trigger"], 160)))
    lines.append("")

    # (e) prohibitions / rulings / SEALED_CHECK
    lines.append("## PROHIBITIONS + OPEN RULINGS + SEALED_CHECK")
    lines.append("live prohibitions: %d | open rulings: %d" % (len(live_prohibitions), len(open_rulings)))
    for p in live_prohibitions:
        lines.append("- [%s] %s (%s)" % (p.get("status"), _clean_one_line(p.get("text")), p.get("authority")))
    lines.append("SP3/M-03/SEALED_CHECK_47 status: %s (pointer: %s)" %
                 (_truncate(sealed_line, 240), sealed_check_pointer))
    lines.append("")

    # (f) counts line -- asserted, must match the map at render time
    lines.append("## COUNTS")
    lines.append("COUNTS: modules=%d | planes=%d | open_pb=%d" % (n_modules, m_planes, k_open_pb))
    lines.append("")

    body = "\n".join(lines).rstrip("\n") + "\n"
    return _apply_size_cap(body, n_modules, m_planes, k_open_pb)


def _section_span(body, heading):
    """Byte span [start,end) of a '## <heading>' section (heading line through its trailing blank
    line), or None if absent."""
    m = re.search(r"^## " + re.escape(heading) + r"\s*$", body, re.M)
    if not m:
        return None
    start = m.start()
    nxt = re.search(r"^## ", body[m.end():], re.M)
    end = m.end() + nxt.start() if nxt else len(body)
    return start, end


def _apply_size_cap(body, n_modules, m_planes, k_open_pb):
    """Degrade the lowest-priority sections first if over SIZE_CAP_BYTES. NEVER drop/shrink the
    ITERATION+PHASE, COUNTS, or FRONTIER CANDIDATES sections. Degrade ladder (lowest priority first):
      1. drop the per-line prohibitions detail (keep the live/open counts line)
      2. drop the PROCESS_BACKLOG per-row detail (keep the '(N)' count heading)
      3. drop the per-plane status BREAKDOWN, keep just the plane total line
    Each step is recorded in a trailing 'degraded:' note so a degraded render is never silently
    mistaken for a full one."""
    if len(body.encode("utf-8")) <= SIZE_CAP_BYTES:
        return body

    degraded = []

    def _drop_prohibition_lines(b):
        span = _section_span(b, "PROHIBITIONS + OPEN RULINGS + SEALED_CHECK")
        if not span:
            return b
        start, end = span
        section = b[start:end]
        kept = "\n".join(ln for ln in section.splitlines() if not ln.startswith("- ["))
        if not kept.endswith("\n"):
            kept += "\n"
        return b[:start] + kept + b[end:]

    def _drop_pb_row_detail(b):
        span = _section_span(b, "OPEN PROCESS_BACKLOG ROWS (%d)" % k_open_pb)
        if not span:
            return b
        start, end = span
        heading_line = b[start:end].splitlines()[0]
        return b[:start] + heading_line + "\n\n" + b[end:]

    def _drop_plane_breakdown(b):
        span = _section_span(b, "PER-PLANE STATUS ROLLUP")
        if not span:
            return b
        start, end = span
        section = b[start:end]
        out = []
        for ln in section.splitlines():
            m = re.match(r"(plane: \S+ \(\d+\)) -- .*", ln)
            out.append(m.group(1) if m else ln)
        kept = "\n".join(out)
        if not kept.endswith("\n"):
            kept += "\n"
        return b[:start] + kept + b[end:]

    ladder = [("drop_prohibition_detail", _drop_prohibition_lines),
              ("drop_pb_row_detail", _drop_pb_row_detail),
              ("drop_plane_breakdown", _drop_plane_breakdown)]
    for name, fn in ladder:
        if len(body.encode("utf-8")) <= SIZE_CAP_BYTES:
            break
        body = fn(body)
        degraded.append(name)

    if degraded:
        note = "degraded: %s (size cap %d B)\n" % (", ".join(degraded), SIZE_CAP_BYTES)
        body = body.rstrip("\n") + "\n\n" + note
    return body


def sha256_norm(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=None)
    ap.add_argument("--map-dir", default=None)
    ap.add_argument("--process-backlog", default=None)
    ap.add_argument("--sealed-check", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--date", default=None)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)

    repo = a.repo or _repo_default()
    map_dir = a.map_dir or os.path.join(repo, "modules", "44-project-map", "map")
    pb_path = a.process_backlog or os.path.join(repo, "core-docs", "PROCESS_BACKLOG.md")
    sealed_check_path = a.sealed_check or os.path.join(repo, "core-docs", "SEALED_CHECK_47.md")
    out_path = a.out or os.path.join(repo, "ops", "manager", "generated", "MANAGER_VIEW.md")
    date = a.date or "undated"

    sealed_rel = os.path.relpath(os.path.abspath(sealed_check_path), repo).replace(os.sep, "/")

    try:
        body = render(map_dir, pb_path, sealed_rel, date)
    except GenError as e:
        print("gen-manager-view: FAILED (fail-closed, nothing written): %s" % e, file=sys.stderr)
        return 2

    size = len(body.encode("utf-8"))
    if size > SIZE_CAP_BYTES:
        print("gen-manager-view: INTERNAL ERROR: degraded render still %d B > cap %d B" %
              (size, SIZE_CAP_BYTES), file=sys.stderr)
        return 2

    if a.check:
        if not os.path.isfile(out_path):
            print("gen-manager-view: --check FAILED: missing committed file %s" % out_path, file=sys.stderr)
            return 1
        committed = read_text(out_path)
        if sha256_norm(committed) != sha256_norm(body):
            print("gen-manager-view: --check FAILED: byte drift vs committed %s" % out_path, file=sys.stderr)
            return 1
        print("OK --check: no drift (%d B)" % size)
        return 0

    write_lf(out_path, body)
    print("OK", out_path, "(%d B)" % size)
    return 0


if __name__ == "__main__":
    sys.exit(main())

