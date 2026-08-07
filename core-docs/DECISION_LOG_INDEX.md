# DECISION_LOG_INDEX -- routing labels only (one row per decision)

Read this index first; pull the full entries you need from `DECISION_LOG.md` by ID. That log is authoritative
and complete -- this index only helps an agent (incl. a small-context model) find relevant entries WITHOUT
loading the ~400 KB log, so it must stay ingestible whole -- NOT a second log. Reduced 2026-08-03 to routing
labels; full detail is in `DECISION_LOG.md`.

## Index maintenance rules (LOAD-BEARING -- keep this a router, not a log)

1. **One line per decision.** The `decision` cell is ONE distinctive sentence fragment naming what was decided
   (target <= ~160 chars). More detail -> `DECISION_LOG.md`, not here.
2. **Routing fields only:** id, date, state, the essential decision, + a supersession/fold pointer if one
   exists. Nothing else.
3. **Exclude** rationale, implementation/test/module inventories, commit hashes, plan ids, version numbers,
   file paths, findings, consequences, and future-work -- unless a token is the ONLY way to distinguish or
   route the decision.
4. **Append, don't expand.** New decision -> new row. Edit an old row ONLY to change its state or add a pointer
   -- never to enlarge it. Compact form: `superseded (was <state>)` / `folded (was <state>)` in the state cell
   + `[superseded by D-00yy]` / `[folded by D-00yy]` in the decision cell.
5. **Compress at append time.** When you add a D-entry to `DECISION_LOG.md`, distill its index row to one
   fragment from the start -- do NOT paste the entry's summary. Re-bloat begins here. Distill from the entry's DECISION and match the terse exemplars (e.g. D-0086..D-0089), NOT the newest rows -- which may have drifted.
6. **Budget 20 KB (DOC_PROTOCOL s2).** An append-only index trends upward -- per-row discipline (rules 1-5) is
   the real guard; snapshot to `archive/doc-snapshots/<date>/` before any slim (history is never deleted).
| id | date | state | decision |
|---|---|---|---|
| D-0001 | 2026-07-24 | locked | Trusted bootstrap executor, not a sandbox |
| D-0002 | 2026-07-24 | provisional | Isolated skill processes before persistent sessions |
| D-0003 | 2026-07-24 | provisional | Filesystem queue before any local HTTP service |
| D-0004 | 2026-07-24 | locked | Skill contract defines modularity; implementation language does not |
| D-0005 | 2026-07-24 | locked | Keep the skill contract minimal until real needs require expansion |
| D-0006 | 2026-07-24 | superseded (was locked) | Proteus long-horizon architecture deferred [superseded by D-0010] |
| D-0007 | 2026-07-24 | provisional | Two-tier local models with a review queue |
| D-0008 | 2026-07-24 | provisional | PowerShell 7 installed per-user and pinned to 7.4.6 |
| D-0009 | 2026-07-24 | folded (was provisional) | Initial skill conventions awaiting contract absorption [folded by D-0028] |
| D-0010 | 2026-07-24 | locked | Life Orchestrator separated from the unrelated Proteus game |
| D-0011 | 2026-07-24 | folded (was provisional) | Second skill confirms D-0009 conventions [folded by D-0028] |
| D-0012 | 2026-07-24 | locked | uia.actor uses UIA patterns only, supports dry-run, and is not parallel-safe |
| D-0013 | 2026-07-24 | locked | Executor watchdog heals failures but honors deliberate shutdowns |
| D-0014 | 2026-07-24 | locked | capture.screen is read-only, parallel-safe, and PNG-first |
| D-0015 | 2026-07-24 | locked | Large models and data live on F:; the C: repository stays small |
| D-0016 | 2026-07-24 | locked / provisional | model.gateway wraps per-call llama-server execution behind one local-model interface |
| D-0017 | 2026-07-24 | locked / provisional | classify.batch uses per-item gateway calls and owns its review writes |
| D-0018 | 2026-07-24 | locked / provisional | review.processor adjudicates single items with live-state updates and append-only history |
| D-0019 | 2026-07-24 | locked / provisional | audio.ingest provides deterministic ffmpeg/ffprobe normalization for speech pipelines |
| D-0020 | 2026-07-24 | locked / provisional | speech.stt wraps whisper.cpp with segment confidence and review production |
| D-0021 | 2026-07-24 | locked / provisional | speech.tts wraps Qwen3-TTS through a Python worker |
| D-0022 | 2026-07-24 | locked | voice.live composes STT, LLM, and TTS without becoming a review producer |
| D-0023 | 2026-07-25 | locked / provisional | ocr.layout wraps Windows.Media.Ocr through a PowerShell 5.1 worker |
| D-0024 | 2026-07-25 | locked / provisional | image.util provides deterministic Pillow/numpy transforms without review production |
| D-0025 | 2026-07-25 | locked / provisional | detect.objects wraps staged CPU ONNX YOLOX inference |
| D-0026 | 2026-07-25 | locked / provisional | image.interpret uses a local Qwen2.5-VL model through llama.cpp |
| D-0027 | 2026-07-25 | locked / provisional | image.index composes perception outputs without becoming a review producer |
| D-0028 | 2026-07-25 | locked | Skill conventions folded into contract v0.2; staged models moved to module homes |
| D-0029 | 2026-07-25 | locked / provisional | Build order pivots to a usable local core; Modules and Widgets separated |
| D-0030 | 2026-07-25 | locked / provisional | logic.escalator uses deterministic gates to climb model tiers |
| D-0031 | 2026-07-25 | locked / provisional | doc.io provides atomic deterministic text read/write/edit/append operations |
| D-0032 | 2026-07-25 | locked / provisional | agent.local is a bounded ReAct loop with gated decisions and a closed tool registry |
| D-0033 | 2026-07-25 | locked / provisional | gen.audio uses deterministic ffmpeg procedural generation; neural audio deferred |
| D-0034 | 2026-07-25 | locked / provisional | gen.image uses local Stable Diffusion 1.5 and produces review items |
| D-0035 | 2026-07-26 | locked / provisional | gen.music uses local MusicGen Small and produces review items |
| D-0036 | 2026-07-26 | locked / provisional | gen.video uses AnimateDiff-Lightning on SD 1.5 and produces review items |
| D-0037 | 2026-07-26 | locked / provisional | agent.coding deferred pending a safe execution substrate and stronger near-term value |
| D-0038 | 2026-07-26 | locked / provisional | Widgets default to native WinForms/PowerShell and always ship launchers |
| D-0039 | 2026-07-26 | locked / provisional | Local Agent Console uses a thin WinForms shell over a UI-free driver core |
| D-0040 | 2026-07-26 | locked / provisional | route.tools provides deterministic mid-tier tool routing |
| D-0041 | 2026-07-26 | locked / provisional | agent.local gains router-constrained Plan/Run modes over a curated tool registry |
| D-0042 | 2026-07-26 | locked / provisional | fs.manage provides deterministic file operations and agent wiring |
| D-0043 | 2026-07-26 | locked / provisional | Governor minimum tier raised to MID; resource profiles added |
| D-0044 | 2026-07-26 | locked / provisional | Qwen3.5-9B replaces the partial-offload 27B as the strong tier |
| D-0045 | 2026-07-26 | superseded (was locked) | Single handoff and START_HERE pointer established [handoff retired by D-0066] |
| D-0046 | 2026-07-27 | locked / provisional | agent.local gains deterministic termination and repeat-action protection |
| D-0047 | 2026-07-27 | locked / provisional | Resume capability expansion; build the executor job-runner and dev.ship harness next |
| D-0048 | 2026-07-27 | locked | Executor job-runner and dev.ship harness shipped |
| D-0049 | 2026-07-27 | locked / provisional | Module Launcher browses and runs installed Modules through the generic wrapper |
| D-0050 | 2026-07-27 | locked / provisional | Adopt verify-cost offloading, an audit-loop spine, and a Claude-led bridge doctrine |
| D-0051 | 2026-07-27 | locked / provisional | Verification Console shipped; external-AI boundary later amended by D-0080 |
| D-0052 | 2026-07-27 | locked / provisional | Human-couriered frontier context packaging allowed; automated external AI access remains out |
| D-0053 | 2026-07-27 | locked / provisional | Atomic TTL filesystem leases coordinate multi-instance resources |
| D-0054 | 2026-07-27 | locked / provisional | Fan-out orchestrator built on res.lease |
| D-0055 | 2026-07-27 | locked / provisional | Fan-out orchestrator dogfooded across three parallel workers |
| D-0056 | 2026-07-28 | locked / provisional | Fan-out adds document leases; executor hardened after a warm-server wedge |
| D-0057 | 2026-07-28 | locked / provisional | Detached warm server shipped; verification audit loop validated |
| D-0058 | 2026-07-28 | locked / provisional | Verification teardown and packet validation hardened; Governor Phase 3 reviewed |
| D-0059 | 2026-07-28 | locked / provisional | AutoRamp Stage 1 controller shipped |
| D-0060 | 2026-07-28 | locked / provisional | AutoRamp Stage 2 adds X0/27B recovery and logprobs; Console adopts AutoRamp |
| D-0061 | 2026-07-28 | locked | AutoRamp default-on reverted; 27B/X0 rejected for 11 GB GPU; 9B selected |
| D-0062 | 2026-07-28 | locked | AutoRamp default-on restored; strong 9B quant set to Q5_K_M |
| D-0063 | 2026-07-29 | locked | Warm multi-model pool and router require design-first validation |
| D-0064 | 2026-07-29 | locked | Verification Console gains packet discovery and type-specific rendering |
| D-0065 | 2026-07-29 | locked | Verification verdicts made durable; expanded four-lane wave approved next |
| D-0066 | 2026-07-29 | locked | Core docs consolidated under one handoff, budgets, index, worker slots, and archive |
| D-0067 | 2026-07-29 | locked | Expanded four-lane waves adopted; warm-pool Stage 1 remains opt-in pending hardening |
| D-0068 | 2026-07-30 | locked | Warm-pool critical hardening completed; portability and dashboard follow-ons shipped |
| D-0069 | 2026-07-30 | locked | Durable gateway supervisor added; media.decompose starts the video spine |
| D-0070 | 2026-07-30 | locked | SD 3.5 image tier and track.objects added; SD 1.5 remains default |
| D-0071 | 2026-07-30 | locked | Trajectory review adopts an R1-R4 work-order chain; GPU lease split becomes immediate priority |
| D-0072 | 2026-07-30 | locked | GPU lease-split primitive introduced with fencing, residency pins, handoff, and lock-order checks |
| D-0073 | 2026-07-30 | locked | GPU lease transition primitive adds three-identity fencing and scheduler-owned atomic transitions |
| D-0074 | 2026-07-30 | locked | Scheduled unattended fan-out rejected; defer autonomy to the local baton-pass agent |
| D-0075 | 2026-07-31 | locked | GPU lease primitive hardened against ABA, partial transitions, and recovery failures |
| D-0076 | 2026-07-31 | locked | GPU lease consumers live-proven; supervisor security findings re-gate warm-pool default-on |
| D-0077 | 2026-07-31 | locked | Video tracker and timeline shipped; cross-module fold smoke mandated for isolated producer/consumer waves |
| D-0078 | 2026-07-31 | locked | Durable supervisor hardened and Job-Object custody closed [default-on gate revised by D-0079] |
| D-0079 | 2026-07-31 | locked | Warm-pool default-on blocked by supervisor red-team; required hardening sequence expanded |
| D-0080 | 2026-07-31 | locked | Pivot to Collective Agent cognitive virtual memory; freeze warm-pool, generators, and real-time work |
| D-0081 | 2026-07-31 | locked | Frontier direction review ratifies D-0080 without changes |
| D-0082 | 2026-08-01 | locked | Collective Agent memory substrate shipped; contract freeze required before Wave 2 |
| D-0083 | 2026-08-01 | locked | MEMORY_CONTRACT freezes retrieval-record, embedding-provider, and retriever interfaces |
| D-0084 | 2026-08-01 | locked | Memory records stack shipped; episode-record contract divergences require settlement |
| D-0085 | 2026-08-01 | locked | Memory status standardized; episode stages remain structural, not record kinds |
| D-0086 | 2026-08-02 | locked | Context compiler and skill retrieval shipped; side effects blocked pending contract hardening |
| D-0087 | 2026-08-02 | locked | Context-packet and memory contracts hardened for control/evidence separation and provenance |
| D-0088 | 2026-08-03 | locked | Contract conformance shipped; selection-policy implementations found inconsistent |
| D-0089 | 2026-08-03 | locked | Selection policy pinned to retrieval.eval canonical implementation; context.compiler must import it |
| D-0090 | 2026-08-03 | locked | Adopt the full long-horizon memory architecture as the evidence-staged design target (Tiers 0-3, design-now vs build-now). |
| D-0091 | 2026-08-03 | locked | Selection-policy settle (i31): context.compiler imports retrieval.eval's canonical selpol, resolving the i30 divergence. |
| D-0092 | 2026-08-04 | provisional | Tier-0 seam repairs (i32, p1): contract amendments for hard-namespace, current/supersession, and reserved hierarchy/working/query seams. |
| D-0093 | 2026-08-04 | provisional | Establish PROCESS_BACKLOG (process/doc-hygiene router) + capture rule; the mechanical commit gate, not the prose checklist, is the forcing function. |
| D-0094 | 2026-08-04 | provisional | Adopt a sunsetting PROCESS_MANDATE (time-boxed, self-deleting, mandatory sunset report) + a blind sealed-check regression test for process health. |
| D-0095 | 2026-08-04 | provisional | Frontier red-team (159e9cb5): NO-GO on i32 as-written (envelope-only namespace; candidate-dependent supersession); open i33 namespace-closure hardening. |
| D-0096 | 2026-08-04 | locked | i33 p1: MEMORY_CONTRACT A5 + CONTEXT_PACKET_CONTRACT i33 re-amend the Tier-0 seams end-to-end (namespace-closure + supersession-hardening; per-hop ns predicate, catalog effective_current, working-state store, classifier split); + a machine-checkable mandate sunset countdown. |
| D-0097 | 2026-08-04 | locked | i33 CLOSED: the namespace-closure + supersession-hardening re-conformance wave shipped (#36 0.4.0 / #37 selpol 1.2.0 + eval 0.5 / #40 0.5.0; ONE canonical ns_permitted, risk-6); the D-0077 mixed-namespace fold smoke PASSED (fail_count=0; airtight sanitized fail-closed closure; deterministic real #36->#40 packet); Tier-0 seams DONE -> i34 = Tier 1. |
| D-0098 | 2026-08-04 | locked | i34 Tier-1 hierarchy design red-team (b4c90545) NO-GO-as-drafted -> the A6/i34 PART-1 redraft: safe-pruning (navigation prioritizes, never excludes without a no-false-negative proof) + retrieval-completeness + generations/CAS staleness + authz-bound frontier ops + write-time ns-homogeneity + hierarchy identity + balanced bulk-build (minimal; live split -> i35). |
| D-0099 | 2026-08-05 | locked | i34 CLOSED: the Tier-1 bounded-fanout hierarchy wave shipped + the D-0077 hierarchy fold smoke PASSED; the per-task working-memory store shipped in parallel; Tier-1 acceptance stays gated on the ~200MB real-corpus rehearsal. |

| D-0100 | 2026-08-05 | locked | i35 CLOSED: CONSUMER WIRING shipped (#40 0.7.0 the real hierarchy_port into the public artifact_search path + SEAM1 hydration + SEAM2 prune-cert; #37 0.7.0 the runnable ~200MB Tier-1 acceptance-gate rehearsal harness); the D-0077 fold PASSED (wired public port 32/32 + i34 regression 38/38 + rehearsal 35/35); project tier1_accepted DEFERRED to i36 (full run vs the WIRED descend path); the P0-1 injection-suite DESIGN red-team folded (NO-GO as sole action gate without a deny-by-default action reference monitor). |

| D-0101 | 2026-08-05 | provisional | Adopt the couriered audit-surface / interpretability program (staged A0-A5 targets; R-1 stage-trace emission binds the router; Widgets 05/06/07 = the audit-tier vehicles) |
| D-0102 | 2026-08-05 | locked | i36 CLOSED: TIER-1 ACCEPTED -- 11/11 s10 over a hash-verified foreign corpus at 100x leaf span; project tier1_accepted TRUE (descend fast-beam lossy; #36-flat fallback preserves recall) |
| D-0103 | 2026-08-05 | provisional | i37 open: action-authorization contract FROZEN as the P0-1 design target (design-only; non_execution holds; s9 blockers 1-14 = activation-gating) + safety+router wave scoped (NEW #43 P0-1 suite MVP + #40 query router R-1 born-instrumented, plan fo-37-9995475a) + a parallel frontier freeze red-team. |
| D-0104 | 2026-08-05 | locked | i37 CLOSED: the safety+router wave shipped (#40 0.8.0 born-instrumented query ROUTER + NEW #43 action.authz P0-1 suite MVP, 66/66 mutation-kills, 192/192); the D-0077 cross-module fold PASSED 13/13 (a real 0.8.0 routed + adversarial-stage-trace packet -> #43 monitor -> deterministic A06 DENY) + i34 38/38; the frontier freeze red-team folded GO-WITH-AMENDMENTS (7 i38 freeze/suite amendments; MVP = build_complete, gate incomplete, NOT a full P0-1 gate pass). |
| D-0105 | 2026-08-06 | provisional | i38 open: scope the P0-1 FULL-GATE (#43: the 7 frozen s6 amendments + full corpus/fuzzer/complete M-* kill matrix -> a full p0_1_gate_status) + #40<->#42 working-memory wiring + NEW Widget 06 Compile Trace Console (3-lane CPU, plan fo-38-2b1efe73); PROCESS_MANDATE countdown 37->38 (sunset i40); PB-4 triggered (Widget 06). |
| D-0106 | 2026-08-06 | provisional | i38 close: the P0-1 action-authz FULL gate (p0_1_gate_status=pass; #43 0.2.0 204/204 + orchestrator D-0077 fold 18/18) + #40 0.9.0 working-memory hydration + NEW Widget 06 SHIPPED + verified; contract s7 ratifies the pass + pins the test-views; frontier as-built re-review couriered; slots archived/reset. |
| D-0107 | 2026-08-06 | provisional | i38 frontier fold: the P0-1 gate AS-BUILT re-review returned FAIL -> p0_1_gate_status WALKED BACK to incomplete (over-claimed vs s6; build_complete + activation prohibited + deny-by-default UNCHANGED); 7 items (oracle-matrix scope, 0.9.0 integration, byte-exact test-views, packet_id completion binding, all-epochs recheck, all-sink M-R11, verifiability) -> i39 unit-0. |
| D-0108 | 2026-08-06 | locked | i39 `fo-39-df2e3a67`: P0-1 gate -> HONEST pass (#43 0.3.0 `8f01a15`, 7 D-0107 findings closed, 308/308, 141-row oracle, fold-i39 18/18) + #36 0.7.0 fast-beam recall (hpr 58823->117647) + NEW widgets/07 audit tier-A2; #37 wired-digest re-pin (d0d54aba) + pre-existing manifest-version = PB-5 #37 lane; frontier re-review couriered (b2b1e5fb) |
| D-0109 | 2026-08-06 | locked | i39 as-built re-review FAIL -- pass walked back to incomplete AGAIN; 7 findings -> i40 unit-0 [supersedes the D-0108 pass claim] |
| D-0110 | 2026-08-06 | locked | i40 sunset: mandate-01 report verdict NO -> mandate 02 LICENSED (sunset i47; M2-A deadline i42; M2-D verify-before-ratify structural; M2-E open) |
| D-0111 | 2026-08-06 | locked | i40 wave open (2-lane CPU): #43 the 7 exact closures (no pass claim -- M2-D) + #37 PB-5 reconcile |
| D-0112 | 2026-08-06 | locked | i40 close: #43 0.4.0 exact closures (orchestrator-recovered ship; gate stays incomplete) + #37 0.8.1 (PB-5 closed); round-3 pack couriered |
| D-0113 | 2026-08-06 | locked | i40 round-3 review FAIL -- s7 not ratified; 5 suite-build findings -> the i41 #43 unit; no walk-back (M2-D) |
| D-0114 | 2026-08-07 | provisional | i41 worker model tiering: Sonnet 5 High default lanes + elevation triggers (#43 stays Opus); Fable = orchestrator seat/inline; fanout retained |
| D-0115 | 2026-08-07 | locked | i41 close: #43 0.5.0 round-3 closures shipped + independently verified (M2-D held); round-4 pack couriered (manifest-derived, empty-dir pre-verified); next = i42 M2-A build |
