# MODULE_ROADMAP (fixture)

Owns build order, per-unit status, and the deferred follow-on menu.

## Built modules

**2 `fs.observer`** — Filesystem Observer · MVP complete (D-0002). Listings, discovery, change detection,
metadata; no screenshots. **Follow-ons:** batch/directory.

**7 `model.gateway`** — Local Model Gateway · MVP complete (D-0015/16). Local LLMs via llama.cpp; warm
detached server; `res.lease` gpu wired. **Follow-ons:** the warm multi-model pool + router.

## Widgets (Phase B, `widgets/`)

- **04 Fan-out Wave Dashboard** — MVP shipped 2026-07-29 (D-0067). Native read-only wave-status surface;
  parses the #30 plan dir + #29 leases dir; zero side effects.
- **05 Provenance Map** -- Proposed (D-0101; the audit-surface ENTRY VEHICLE, tier A1). Read-only native
  WinForms construction map that JOINS the canonical docs + git dev.ship trailers + the HANDOFF ledger +
  runtime/plans reports + Verification-Console verdicts. Exclusive `widgets/05-provenance-map/`, docs:[],
  STRICTLY read-only.
- **Backlog:** Voice Console · Generator Studio · Document Workspace.
