# Widget 08 - Live-Run Audit Pathway (LRAP)

The audit program's **phenomenological top surface** (D-0120; `core-docs/AUDIT_PIPELINE.md` principle P9). A
native WinForms window that walks a **replayed `#40` compile** as **one chronological, plain-language,
intent-vs-actual narrative**, so you can find a bad input **at the step where it happens** without prerequisite
schema expertise and without switching windows.

Widgets 05/06/07 render the same data correctly but are expert-forensic and post-hoc; they are the **descend
target** you drop into on an anomaly, not the top surface. LRAP is that top surface.

> Double-click **`launch.bat`** to open it. It is **strictly read-only**: it reads one existing compile
> artifact, re-compiles nothing, calls no model, holds no lease, and writes nothing outside its own `runtime\`
> dir. `non_execution` holds; it enables no action.

## What you see

One packet, walked as six steps in order:

```
1 normalize -> 2 retrieve -> 3 route -> 4 select -> 5 budget -> 6 packet
```

Each step shows **four lanes** in plain language (not raw schema):

- **INTENT** - what this step is *supposed* to do (authored once per step, citing the contract clause it
  paraphrases).
- **INPUT** - its actual input.
- **OUTPUT** - its actual output.
- **RECONCILE** - a neutral marker (`consistent` / `INCONSISTENT here` / `not applicable` / `not emitted yet`).
  The naming prose stays **collapsed** until you press **Show why**; the raw expert pane (Widget 06) is
  reachable only behind **Show raw trace**.

The header states the overall verdict: `consistent` (every step's counts reconcile) or `INCONSISTENT at
step N`. **A green step means "counts reconcile" - a necessary-not-sufficient signal, never a claim the run is
"correct".**

## The honesty rule (why you can trust the verdicts)

A RECONCILE lane only ever **re-expresses a verdict the substrate already computes** - a set/count identity
from the Widget-07 tournament (via the pinned reader adapter) or a plain arithmetic check:

| step | reconcile identity (verdict-backed) |
|---|---|
| 1 normalize | *(none emitted - shown as an explicit P2 "not emitted yet" lane)* |
| 2 retrieve  | ranked count == raw-retrieval count *(+ a P2 note: a recall gap is undetectable)* |
| 3 route     | each round: in - removed = out; chain: out[n] = in[n+1] |
| 4 select    | packet subset of post-filter subset of raw; every dropped candidate carries an omit_reason |
| 5 budget    | tokens used <= budget; body + overhead = used; rendered + reserved <= max_context (no overflow) |
| 6 packet    | packet stage = selected set; every excerpt selected; non_execution set; trust banners present; no packet record carries a hard-exclusion reason code |

It introduces **no semantic judgment** - whether an `omit_reason` is *justified*, whether a successor *should*
exist, whether a classification is *right* are FORBIDDEN in v1 and logged as **P2** gaps (visible in the P2
backlog), never turned into a verdict. Every cell the substrate cannot emit yet renders as an explicit
**"not emitted yet - trace-emission follow-on logged"** lane; never a blank, never a fake, never a stand-in.

## Honest scope (v1)

LRAP v1 audits packet **assembly** (the input side, steps 1-6). It does **not** render the model's actual
**output**, so it does not yet reconcile intuitive instructions against intuitive outputs - that needs a wired
live run with captured output (a later, gated increment). Steps 7-8 (gate / verify) are **not** built: no wired
end-to-end run exists, and stitching `#43`/`#37` would imply a causal run that never happened. A flat
(no-router) compile renders step 3 as **not applicable** (visible, not hidden).

## Files

- `Show-LiveRunAuditPathway.ps1` - the thin STA WinForms shell (UI only).
- `LiveRunAuditPathway.psm1` - the WinForms-free driver core (the honesty map, the four-lane spine, the
  verdict-backed RECONCILE, the plain-language descend, the INTENT catalog). Unit-tested in the cloud.
- `LrapReaderAdapter.psm1` - the pinned, contract-tested reader adapter over Widgets 06/07 (the recompute
  entrypoints are excluded; a cross-widget contract test fails closed on 06/07 shape drift).
- `launch.bat` - double-click launcher (`pwsh -NoProfile -STA`).
- `tests/Invoke-LiveRunAuditPathwayTests.ps1` - dual-mode test harness (cloud gate 73/0/3; `-Live` adds the
  WinForms self-test on Windows).
- `tests/fixtures/` - five committed `#40` fixtures (`clean_routed`, `defect_mis_route`,
  `defect_dropped_candidate`, `defect_wrong_record`, `quirk_flat`) + `mint-fixtures.ps1` (their provenance).

## Self-test

```
pwsh -NoProfile -STA -File Show-LiveRunAuditPathway.ps1 -SelfTest
```

Builds, drives, and disposes the form off-screen over the committed fixtures and prints
`SELFTEST_FORM_OK`, `SELFTEST_MODEL_OK`, `SELFTEST_PANES_OK`, `SELFTEST_RECONCILE_OK`, `SELFTEST_DESCEND_OK`,
`SELFTEST_SANITIZE_OK`, `SELFTEST_REFRESH_OK`, `SELFTEST_READONLY_OK`, `SELFTEST_LAYOUT_OK`.

## Acceptance

The acceptance gate is a **human live-GUI confirm** (D-0064): walk each of the five fixtures with the RECONCILE
prose collapsed, state why at each verdict, and correctly classify it - flag each of the three defects at its
step, and do not false-flag the clean and natural-quirk controls. The widget ships self-test-green and
cloud-green with this confirm flagged **pending**.
