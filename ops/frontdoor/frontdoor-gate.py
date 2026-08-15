#!/usr/bin/env python3
"""ops/frontdoor/frontdoor-gate.py -- the i59 front-door close-gate (hardened s8; red-team A2-BREAK5, A3-B3/B5).

Fail-closed. Asserts the boot-surface survivor set is self-consistent at the close HEAD:
  (a) COLD_BOOT_CARD doc-list == the on-disk core-docs/*.md set (silent add/drop is detectable)
  (b) every card doc has a DOC_PROTOCOL s2 owner row (declared + budgeted)
  (c) card doc COUNT header == len(list) == filesystem count, and <= kmax
  (d) the card generator-free read-order docs are a subset of the doc-list
  (e) card PINNED count == pinned lines <= pin_max, each citing an extant D-####
  (f) registry: >=1 class, exactly one root-pcb (boot_read), each boot_read artifact present+non-empty
  (g) the boot kernel's named paths all resolve

Usage: python3 ops/frontdoor/frontdoor-gate.py [--repo .]  (exit 0 = PASS, non-zero = FAIL)
"""
import argparse, json, os, re, sys


def read(p):
    with open(p, "r", encoding="utf-8") as fh:
        return fh.read()


def parse_s2_doc_cells(doc_protocol_text):
    cells = []
    in_s2 = False
    seen_header = False
    for ln in doc_protocol_text.split("\n"):
        if ln.startswith("## "):
            was = in_s2
            in_s2 = ln.lstrip("# ").strip().startswith("2.")
            if was and not in_s2:
                break
            seen_header = False
            continue
        if not in_s2:
            continue
        s = ln.strip()
        if not s.startswith("|"):
            continue
        row = [c.strip() for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in row):
            continue
        if not seen_header:
            seen_header = True
            continue
        if row and row[0]:
            cells.append(row[0])
    return cells


def section(card_text, header_startswith):
    """Return the lines of the '## <header...>' section (header line + body until next '## ')."""
    lines = card_text.split("\n")
    out, grab = [], False
    for ln in lines:
        if ln.startswith("## "):
            grab = header_startswith.lower() in ln.lower()
            if grab:
                out.append(ln)
            continue
        if grab:
            out.append(ln)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    cd = os.path.join(repo, "core-docs")

    fails, checks = [], []

    def ck(ok, name, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        if not ok:
            fails.append("%s: %s" % (name, detail))

    fs_docs = sorted(n for n in os.listdir(cd) if n.endswith(".md") and os.path.isfile(os.path.join(cd, n)))
    card_path = os.path.join(cd, "COLD_BOOT_CARD.md")
    reg_path = os.path.join(repo, "ops", "frontdoor", "registry.json")

    ck(os.path.isfile(card_path), "card-present", card_path)
    ck(os.path.isfile(reg_path), "registry-present", reg_path)
    if fails:
        print(json.dumps({"ok": False, "fails": fails, "checks": checks}, indent=1))
        sys.exit(1)

    card = read(card_path)
    reg = json.loads(read(reg_path))
    kmax = int(reg.get("kmax_core_docs", 30))
    pin_max = int(reg.get("pin_max", 12))

    # doc list
    dl = section(card, "CANONICAL DOC LIST")
    card_docs = []
    for ln in dl:
        m = re.match(r"^- ([A-Za-z0-9_]+\.md)\b", ln.strip())
        if m:
            card_docs.append(m.group(1))
    hdr = " ".join(dl[:1])
    mcnt = re.search(r"(\d+)\s+core-docs", hdr)
    card_n = int(mcnt.group(1)) if mcnt else -1

    ck(sorted(card_docs) == fs_docs, "doc-list==filesystem",
       "card=%d fs=%d missing=%s extra=%s" % (len(card_docs), len(fs_docs),
        sorted(set(fs_docs) - set(card_docs)), sorted(set(card_docs) - set(fs_docs))))
    ck(card_n == len(card_docs) == len(fs_docs), "doc-count-consistent",
       "header=%d list=%d fs=%d" % (card_n, len(card_docs), len(fs_docs)))
    ck(len(fs_docs) <= kmax, "doc-count<=kmax", "%d<=%d" % (len(fs_docs), kmax))

    # every card doc has an s2 row
    s2 = set(parse_s2_doc_cells(read(os.path.join(cd, "DOC_PROTOCOL.md"))))
    missing_s2 = [d for d in card_docs if d not in s2]
    ck(not missing_s2, "docs-have-s2-row", "missing=%s" % missing_s2)

    # read-order subset
    ro = section(card, "GENERATOR-FREE RAW READ ORDER")
    ro_docs = re.findall(r"`([A-Za-z0-9_]+\.md)`", "\n".join(ro))
    ck(set(ro_docs) <= set(card_docs) and ro_docs, "read-order-subset",
       "read_order=%s not_in_list=%s" % (ro_docs, sorted(set(ro_docs) - set(card_docs))))

    # pinned constraints -- group each numbered item with its wrapped continuation lines
    pin = section(card, "PINNED CONSTRAINTS")
    pin_items, cur = [], None
    for ln in pin[1:]:  # skip the header line
        if re.match(r"^\d+\.\s", ln.strip()):
            if cur is not None:
                pin_items.append(cur)
            cur = ln.strip()
        elif cur is not None and ln.strip():
            cur += " " + ln.strip()
    if cur is not None:
        pin_items.append(cur)
    mph = re.search(r"(\d+)", " ".join(pin[:1]))
    pin_hdr = int(mph.group(1)) if mph else -1
    dl_all = set(re.findall(r"D-\d{4}", read(os.path.join(cd, "DECISION_LOG.md"))))
    pin_lines = pin_items
    pin_drefs_ok = all(any(dr in dl_all for dr in re.findall(r"D-\d{4}", ln)) for ln in pin_items)
    ck(pin_hdr == len(pin_lines) and len(pin_lines) <= pin_max, "pinned-count",
       "header=%d lines=%d max=%d" % (pin_hdr, len(pin_lines), pin_max))
    ck(pin_drefs_ok and pin_lines, "pinned-cite-extant-D", "every pinned line cites an extant D-####")

    # registry structural
    classes = reg.get("classes", [])
    root = [c for c in classes if c.get("class_id") == "root-pcb"]
    br = [c for c in classes if c.get("boot_read") is True]
    ck(len(classes) >= 1 and len(br) >= 1, "registry-nonvacuous", "classes=%d boot_read=%d" % (len(classes), len(br)))
    ck(len(root) == 1 and root[0].get("boot_read") is True, "root-pcb-present", "n=%d" % len(root))
    for c in br:
        art = os.path.join(repo, c.get("boot_read_artifact", "").replace("/", os.sep))
        ok = os.path.isfile(art) and os.path.getsize(art) > 0
        ck(ok, "artifact-nonempty:%s" % c.get("class_id"), art)

    # kernel named paths resolve
    for rel in ("modules/44-project-map/project_map.py",
                "modules/44-project-map/generated/BOOT_PACKET.md",
                "ops/frontdoor/Rebuild-FrontDoors.ps1",
                "core-docs/COLD_BOOT_CARD.md",
                "core-docs/START_HERE.md"):
        ck(os.path.exists(os.path.join(repo, rel.replace("/", os.sep))), "kernel-path:%s" % rel, rel)

    ok = not fails
    print(json.dumps({"ok": ok, "fails": fails, "checks": checks}, indent=1))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
