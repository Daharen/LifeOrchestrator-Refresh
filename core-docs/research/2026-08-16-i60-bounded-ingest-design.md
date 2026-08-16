# i60 BOUNDED-INGEST + CONTROL-PLANE HARDENING -- design + evidence (D-0155/D-0156; DELIVERY iteration)

Design/evidence record for the i60 fan-out wave (plan fo-60-d578e353). NOT a control-plane owner (canonical:
CURRENT_STATE.md, FANOUT_ORCHESTRATOR_HANDOFF.md, PROCESS_BACKLOG PB-8, the PCB overlay, DECISION_LOG D-0156).
Delivery iteration (Nicholas): A/B/C/D shipped, E recorded read-only at fold; a deferral needs a concrete gate
failure or a demonstrated dependency, not "design-first". i61 = fresh-session adoption proof + hardening.

## Frontier verified at boot
- PCB packet verify GREEN (0 errors, 0 stale, 184 entities). Box: heartbeat degraded:false, no live lease, HEAD
  fad020f (i59 corrective refold), 0 unmanaged orphans, doc-gate hook grn.
- F-i53-eff OPEN + load-bearing: bounded card:/section: EXISTS but the ledgers show bounded_fraction 0.0 across
  i55/i58/i59; gen-retrieval-monitor.py rolled up a SELF-REPORTED ledger and did not gate.
- FO-6 confirmed at source: Invoke-ProjectMap.ps1 emitted --repo ONLY in the harvest branch; the else branch
  (query/render/validate/verify/reaffirm/fmt) dropped -Repo, so query --q section:/card:/evidence: --harvest
  could not resolve repo-backed content through the entrypoint.

## Increments (map 1:1 to PB-8)
- A -- bounded-default affordance: ops/retrieval/retrieve.ps1, ONE verb; runs a bounded #44 query AND
  auto-appends the correct {kind,target,bytes} ledger line (charged bytes = the canonical python oracle
  len(json.dumps(result,ensure_ascii=False,separators=(",",":")).encode())), so the EASY path is the MEASURED path.
- B -- automatic measurement: gen-retrieval-monitor.py gains --gate (FAIL-CLOSED: whole-doc opens with zero
  bounded queries => exit 1) + --artifacts-dir (ledger<->query-artifact cross-check: unbacked/unrecorded surfaced).
- C -- FO-6 repair: the wrapper passes --repo through for non-harvest actions, provider-guarded.
- D -- bounded manager/program projection: ops/manager/gen-manager-view.py renders a bounded, count-asserted
  MANAGER_VIEW over canonical map state (per-plane status rollup + open frontier/PB + rulings + SP3/M-03/
  SEALED_CHECK status) with a --check drift gate. Observability/steering; NOT a per-doc gate, NOT a class migration.
- E -- SP3/M-03 truth (read-only at fold; record only, no M-03 license).

## Lanes (3 CPU/coding; NO GPU; MaxParallel 3; all docs:[])
Lane 1 (001, Opus 4.8 Extra) = A+B (ops/audit + ops/retrieval); Lane 2 (002, Sonnet 5 High) = C (modules/44
wrapper); Lane 3 (003, Sonnet 5 High) = D (ops/manager). Disjoint areas -> 0 doc/module contention; no
producer/consumer split -> D-0077 fold-smoke N/A. Demonstrated dependency: A's section: adoption proof rides
C's FO-6 fix (both land i60; fold verifies C first); D reads map JSON directly, independent of C.

## As-built + evidence (i60 close, D-0156)
Shipped commits (native-git verified): f838952a (D, ops/manager, 21/21), 88f41dee (A+B, ops/retrieval +
monitor), e4c4fdde (C, FO-6; #44 0.4.0->0.4.1; run_tests 169/169). Lane 2 was DONE-minus-ship (no box bridge);
the orchestrator ran the -Live gate + dev.ship (sha256+AST+tests fail-closed under the git lease) + verified the
native HEAD (D-0072) + filed the report.

Lane 1 folded its 2-subagent in-session red-team (D-0119) breaks before ship: artifact-directory RecursionError
DoS; pwsh/python Unicode byte-count divergence (U+0085/2028/2029, out-of-range ints, array payloads -> byte
charging delegated to python by construction); malformed / degenerate / empty envelope handling (fail-closed);
case-sensitive success checking.

Cross-lane integration smoke (orchestrator-owned): section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header
resolved status:ok non-empty through the FO-6-fixed wrapper with -Repo AND through retrieve.ps1 -> exactly ONE
ledger entry {section, target exact, bytes 2428}; the independent byte oracle recomputed 2428==2428; monitor
--gate => pass, bounded_fraction 1.0; --artifacts-dir scanned 189 artifacts, 0 unbacked, 3 unrecorded; suites
green (m44 169/169, retrieve 41/41, gate-crosscheck OK, manager OK). MANAGER_VIEW drifted only on the snapshot
date; regenerated at close.

E -- SEALED_CHECK_47: integrity VERIFIES (1ea2a600... over the CRLF ## Predicates->EOF region; git shows the
file byte-identical to its i47 creation commit 53c211f). SP1/SP2/SP4/SP5/SP6/SP7 PASS; SP3 FAIL (ARCHITECTURE_MAP
16496 > 15000). Seal RETAINED; M-03 DEFERRED, NOT licensed (consistent with D-0147).

## Accepted residuals -> i61 (NOT deferred first implementation; each is a concrete gate/dependency, not "design-first")
1. F-i53-eff stays OPEN until a fresh PCB-booted session does representative tasks bounded-by-default and leaves
   machine-verified retrieval evidence. 2. The gate enforces a ZERO-bounded floor, not a meaningful fraction.
3. Some ledger properties remain self-reported. 4. Artifact reconciliation is query-string based, not
   session/commit-identity bound. 5. The fail-closed close-path retrieval gate is WIRED + ACTIVE (i60, D-0157: ops/close-refold.ps1
   -Ledger runs gen-retrieval-monitor --gate + ABORTS a zero-bounded close); i61 raises the zero-floor to a meaningful fraction. 6. MANAGER_VIEW ops/frontdoor
   class-registration is an optional i61 follow-on.

## Source pointers
D-0155 reconciliation - D-0156 close - PB-8/PB-9 - CURRENT_STATE - handoff s4 - ops/audit/gen-retrieval-monitor.py
- ops/retrieval/retrieve.ps1 - ops/manager/gen-manager-view.py - modules/44-project-map/Invoke-ProjectMap.ps1.
