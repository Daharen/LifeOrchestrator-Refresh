"""
render.py -- a deterministic minimal prompt renderer for the Boundary-B (model-prompt rendering)
obligations (contract s6; i40 red-team Finding 6c).

The i39 Boundary-B rows were PRESENCE assertions (does the packet declare a banner?). This renders a
real #40 0.9.0 packet to bytes per its OWN `rendering` contract -- region ORDER, evidence / working-
memory delimiters, and the can_instruct=false role banners -- so the Boundary-B oracle rows MUTATE the
ACTUAL rendering path and observe a rendered-bytes / ordering / delimiter DIFFERENCE. Boundary B is
defense-in-depth ONLY; Boundary C (the reference monitor) is the decisive authorization gate, so a
corrupted render never authorizes -- the render rows are decisive on the RENDER surface, not on authz.

Deterministic (no wall-clock); byte-identical on re-run.
"""

FAULTS = ("reorder", "drop_evidence_delimiter", "drop_working_memory_delimiter",
          "drop_can_instruct_banner")


def render_packet(pkt, fault=None):
    """Render the packet to bytes per its `rendering` contract. `fault` mutates the ACTUAL render path."""
    r = pkt.get("rendering", {}) or {}
    order = list(r.get("order", []))
    ev_delim = dict(r.get("evidence_delimiters", {}) or {})
    wm_delim = dict(r.get("working_memory_delimiters", {}) or {})
    ev_banner = r.get("evidence_role_banner", "")
    wm_banner = r.get("working_memory_role_banner", "")

    if fault == "reorder":
        order = list(reversed(order))                         # break the fixed control->...->evidence order
    elif fault == "drop_evidence_delimiter":
        ev_delim = {}
    elif fault == "drop_working_memory_delimiter":
        wm_delim = {}
    elif fault == "drop_can_instruct_banner":
        ev_banner = ev_banner.replace("can_instruct=false", "")
        wm_banner = wm_banner.replace("can_instruct=false", "")

    lines = []
    for region in order:
        lines.append("[REGION:%s]" % region)
        if region == "evidence":
            lines.append("%s|%s" % (ev_delim.get("begin", ""), ev_banner))
            for ex in ((pkt.get("evidence", {}) or {}).get("excerpts", []) or []):
                lines.append("EVID %s ci=%s" % (ex.get("excerpt_id", ""), ex.get("can_instruct")))
            lines.append("%s" % ev_delim.get("end", ""))
        elif region == "working_memory":
            lines.append("%s|%s" % (wm_delim.get("begin", ""), wm_banner))
            for it in ((pkt.get("working_memory", {}) or {}).get("items", []) or []):
                lines.append("WM %s ci=%s" % (it.get("record_id", ""), it.get("can_instruct")))
            lines.append("%s" % wm_delim.get("end", ""))
        else:
            lines.append("...%s..." % region)
    return ("\n".join(lines)).encode("utf-8")
