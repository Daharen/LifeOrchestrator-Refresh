# i35 P0-1 adversarial control-plane-vs-evidence INJECTION SUITE -- frontier design red-team digest

**Date:** 2026-08-05. **Wave:** i35 (plan fo-35-0a5bf334). **Source:** frontier.bridge pack
`2f6aa0dc-1160-420d-aace-74348835797d` (couriered, D-0052; read-return captured/valid, pack_id_match). Governs
the FUTURE P0-1 adversarial-injection SUITE build + the action-authorization contract freeze that must precede any
action-capable coordinator. This is a DESIGN review; no suite code exists yet.

## Verdict matrix (the frontier's GO/NO-GO)
- Shipped read-only substrate behind `non_execution:true`: **GO**.
- Structural packet separation as the PACKET-LEVEL P0-1 invariant: **GO** (with a clarification -- see below).
- Structural packet separation as the COMPLETE end-to-end safety invariant: **NO-GO**.
- A committed deterministic #37-style harness + a fixed-seed fuzzer + promoted regression fixtures: **GO**.
- Actual-model behavior / "no unauthorized model intent emitted" as the P0-1 PROOF: **NO-GO**.
- "No unauthorized intent can receive a PERMIT or cause an EFFECT" as the gate: **GO**.
- P0-1 suite as the sole gate for declaring "P0-1 enforced": **GO -- once it INCLUDES the action reference monitor.**
- P0-1 as the sole gate for a general ACTION-CAPABLE release: **NO-GO** (also needs the reference monitor +
  tool/operation effect confinement + the existing evidence-sufficiency/provenance/transport/namespace/supersession
  gates + idempotency/rollback/approval + trusted completion evaluation independent of evidence prose).
- Designing the action-capable coordinator BEFORE freezing the action-authorization contract: **NO-GO**.

## Core finding -- "the model was not steered" is the WRONG security property
No deterministic substrate test can prove a model reading adversarial evidence was not steered without fixing a
model/tokenizer/template/decoding/prompt -- and even then it measures behavior over a corpus, not a system
invariant. Split properties into two classes:
- **Deterministically enforceable (the gate):** untrusted data cannot populate/modify control_plane, construct a
  grant/approval/completion-contract/evaluator-rule/trusted-tool-manifest; requests cannot widen grants; generated
  retrieval queries cannot widen namespace/temporal/sensitivity/traversal authorization; navigation cannot be cast
  to evidence; working memory cannot be cast to authority; derived records keep non-authoritative origin; model
  output cannot directly invoke an executor; unauthorized proposals get no permit; evidence/tool prose cannot
  satisfy completion; a stale packet/grant cannot be replayed after revocation.
- **Empirically measurable, NOT substrate-provable (regression only):** whether a given model follows an injected
  instruction, proposes an irrelevant-but-permitted action, is helped by delimiters, resists by wording/family.
The stronger end-to-end invariant to build + test against: **untrusted content may arbitrarily influence model
output, but cannot alter trusted authority state, widen information access, satisfy trusted completion checks, or
cause an unauthorized side effect.**

## Attack taxonomy (14 classes the suite MUST cover)
1 direct evidence-content injection (fake control JSON / "task complete" / split across chunks); 2 rendering +
delimiter breakout (close the evidence fence, fake closing tags, tool-call after a fake delimiter); 3 unicode /
encoding / normalization evasions (bidi, zero-width, homoglyphs, base64/hex, double-encoding, nulls in ids/paths);
4 METADATA / non-body injection (filenames, titles, record ids, provenance labels, error messages, omission
reasons, diagnostic arrays, snippets, stage traces -- a body-only sanitizer misses all of these); 5 navigation-
plane injection (synopsis / navigation_ref / expand_hint / lexical descriptor / prune reason / generated descendant
query); 6 working-memory poisoning + authority laundering ("approval received" written to state; stale head; a
summary loses its trust label); 7 skill-card / procedural-memory injection (a card claims no-permission / self-
marks healthy / imitates a manifest); 8 cross-namespace exfiltration + confused-deputy retrieval (crafted
namespaces, "see the other project" refs, graph edges, aggregates, exact-id/path-prefix lookups; AND caller-visible
failure metadata -- a violation count / timing / error variant / node count becomes an existence ORACLE); 9 stale /
superseded / temporal-authority attacks (a superseded record self-declares current; successor withheld; forged
timestamps); 10 MULTI-HOP / delayed injection (evidence plants a query -> retrieves a planted node -> expand_hint
-> leaf payload -> summarized into working memory, later shown without attack context); 11 tool-output / fake-result
injection (fake approval/success markers; shell output containing tool-call JSON); 12 parser / schema /
canonicalization attacks (duplicate keys, schema downgrade, coercion, path traversal, symlinks/junctions, wildcard/
env expansion, command wrappers hiding a broader effect); 13 replay / substitution / TOCTOU (reuse a packet under
an older broader grant; revoke after compile before exec; reuse a permit; swap args after approval); 14 control-
plane-store poisoning + unauthorized promotion (untrusted records entering the authority store by another route;
model proposals self-promoting).
"Strip instructions from evidence" is inadequate: "instruction" is not syntactically definable; it conflicts with
the lossless substrate; misses non-body carriers + multi-hop + authority laundering + output-side failures; creates
a new security-critical parser; and cannot address coarse grants. Instead: preserve source losslessly, mark
origin/role, make model output non-authoritative, GATE EFFECTS OUTSIDE THE MODEL.

## Enforcement model -- four boundaries
- **A. Storage/retrieval/packet assembly (where structural separation is genuinely enforceable):** provenance-typed
  values in code -- `Authority<T>` (constructible only by the coordinator/user-authority store), `Request<T>`
  (cannot self-authorize), `Untrusted<T>` (evidence/navigation/working/retrieved-procedure-prose/tool-output),
  `TrustedStatus<T>` (narrow validator/executor results). NO generic merge Untrusted->Authority; copy/summarize/
  cluster/derive/promote PRESERVES non-authority unless a separate ELEVATED promotion runs; control-plane creation
  uses an allowlisted trusted source, not field-names-found-in-data; namespace closure over transitive provenance +
  every output channel.
- **B. Model-prompt boundary (defense-in-depth + auditability, NOT decisive):** separate roles, one canonical
  renderer, escaped/length-prefixed evidence, banners, source hashes, no evidence interpolated into control
  templates. A "channel the model literally cannot cross" does not exist once both channels share one context --
  prevent STRUCTURAL reassignment, cannot prevent semantic attention.
- **C. Coordinator action-AUTHORIZATION boundary (THE decisive boundary):** the model emits an UNTRUSTED action
  PROPOSAL, never an executable tool call; a deterministic reference monitor evaluates it against trusted grants +
  side-effect policy + trusted tool manifest + canonicalized args/resolved effects + current namespace/scope +
  approval state + current grant state + risk/transaction policy. Evidence may supply proposed facts/params; NEVER
  permission.
- **D. Executor boundary:** rejects raw model output; accepts only a trusted ONE-SHOT permit (so a future
  coordinator bug cannot bypass the monitor; authorization is independently testable).

## Minimal action-authorization contract (freeze BEFORE any action-capable coordinator -- Gap 1)
`lifeorch.action_proposal/0.1` {proposal_id, task_id, packet_id, tool_id, operation, arguments, evidence_refs[],
claimed_effects[] (advisory, never trusted), model_provenance} -- treat as user-controlled input.
`lifeorch.tool_manifest/0.1` {tool_id, manifest_version, operations[], CLOSED arg schemas, trusted effect
classifier, target canonicalizer, required permission scopes, risk_class, reversibility, idempotency, rollback,
sandbox_class, approval requirements, health source} -- belongs to installed code / a trusted registry; retrieved
skill cards may DESCRIBE but never DEFINE/override it.
Authorization algorithm (indeterminate = DENY): validate closed schema -> canonicalize args -> resolve aliases/
paths/symlinks/junctions/redirects/wildcards/recipients -> derive the ACTUAL effect set from the manifest (not
claimed_effects) -> deny if proposal-only/non-executing -> deny if packet/grant/corpus/manifest/approval stale ->
match concrete op+targets+effects+count+limits+window+risk against a trusted grant -> apply side_effect_policy ->
require explicit approval where policy/risk demands -> for evidence-dependent actions require the right evidence
disposition + validators -> issue a ONE-SHOT permit bound to the exact action digest -> log without copying
attacker-controlled evidence.
`lifeorch.action_permit/0.1` {permit_id, issuer, task_id, packet_id, canonical_action_digest, tool_id,
tool_manifest_version, operation, resolved_target_set, authorized_effect_set, effective_namespace, grant_snapshot_ref,
approval_ref?, limits, expiry, nonce, idempotency_key} -- never rendered back into an ordinary model context.
Executor: accepts only a valid permit; verifies digest + manifest version + expiry/nonce/revocation/one-shot;
sandbox + resource bounds; captures state diff; returns trusted structured status + untrusted text; cannot modify
policy. COMPLETION is trusted predicates over exit status / state diff / artifact hashes / tests / expected object
state / explicit human approval / postconditions -- NEVER model or evidence prose.

## Harness structure (7 layers) + the smallest honest suite
Layers: 1 committed adversarial FIXTURES (one shared cross-module set; pin canonical HASHES + named security
PROPERTIES, not whole packet bytes); 2 packet-boundary assertions; 3 a fixed-seed deterministic mutational FUZZER
(metamorphic: replacing any untrusted payload may change rendering/relevance/proposal but NEVER trusted authority /
effective scope / authorization rules / completion); 4 a mock-model output generator (emit malicious proposals
directly -- prove safety even if the model is fully compromised); 5 a mock coordinator + executor (raw proposals
never reach the executor; denial -> no permit -> no state diff; one permit per action; digest-bound; reuse/revoke/
manifest-drift fail); 6 security MUTATION testing (seed defects -- drop a ns check, merge evidence into control,
trust a card's permission field, accept raw tool JSON at the executor -- EVERY seeded mutation must be KILLED);
7 actual-model probes (AFTER the deterministic gate; regression measurement only).
Smallest honest suite = 10 fixture families (direct+fake-control; delimiter/unicode/encoding; navigation injection;
working-memory poisoning; skill/procedure permission+effect; cross-namespace leakage incl. side channels; stale/
superseded reassertion; multi-hop query planting; parser/canonicalization/replay; malicious proposals at the mock
authz+executor) + 4 universal properties (AUTHORITY integrity, SCOPE integrity, ROLE integrity, EFFECT integrity)
+ 3 methods (committed fixtures, fixed-seed property/mutation, cross-module action-boundary integration).
Acceptance gate passes ONLY when: all mandatory fixtures pass; runs byte/property deterministic; no cross-namespace
identifying data reaches caller-visible output; ALL seeded security mutations killed; every denied proposal ->
no permit + no state diff; no raw-model-output path reaches an executor; one canonical (or byte-equivalent) trusted
manifest+grant implementation; the same producer->consumer chain passes on REAL module outputs.
Non-goals: model the full agent; prove a model is injection-immune; general answer quality; every tool's business
logic; a universal instruction detector; sanitize/rewrite the lossless corpus; a GPU model as the security oracle;
another model context as an independent safety proof.

## Five safety-critical gaps to close BEFORE coordinator design
1 (largest blocker) no frozen action-reference-monitor contract -> freeze proposal/manifest/authorization/permit/
executor first. 2 "evidence cannot change skill selection" is overbroad + not deterministically testable -> reframe:
evidence cannot EXPAND eligibility or alter permissions/risk/health/effect-set/approval, and every selected op is
independently authorized (if selection itself must be evidence-immune, selection must be CODE, not a model
decision). 3 coarse grants permit harmful-but-authorized steering -> grants must constrain concrete op + canonical
target + effect class + quantity + duration + risk + approval, not merely tool identity. 4 caller-visible namespace
failure metadata is an oracle -> return a CONSTANT sanitized failure to ordinary callers; detail only in a
privileged local security log. 5 trusted-origin closure must include PROMOTION + derived memory -> authority-store
writes + policy promotions require a separate elevated path; origin labels survive every normal derivation.

## Single highest-leverage element + ranked risks
Highest leverage: **a tiny, deterministic, DENY-BY-DEFAULT action reference monitor whose one-shot permits bind the
exact canonical effect to a trusted grant snapshot** -- it flips the threat model from "the model must resist every
injection" to "the model may be fully steered and still cannot exceed its capability envelope," and gives the suite
a crisp model-independent acceptance test.
Ranked risks: 1 missing/bypassable action-authorization path; 2 overbroad grants; 3 confused-deputy in args/paths/
wrappers/aliases/redirects/meta-tools; 4 authority laundering via working-memory/summaries/procedures/tool-output/
promotion; 5 cross-namespace leakage via transitive provenance/traversal/diagnostics/side-channels; 6 replay/TOCTOU
across packet/grant/manifest/approval/exec; 7 multi-hop injection that keeps payload influence but loses origin
labels; 8 parser/canonicalization DIFFERENTIALS between compiler/authorizer/executor; 9 fake completion/escalation
suppression from evidence/tool prose; 10 treating successful model prompt-injection tests as proof of architectural
safety.

## Orchestrator take-away (for the roadmap)
The P0-1 SUITE is now a designed, buildable unit (a #37-style deterministic harness + committed fixtures + a
fixed-seed fuzzer + a mock authz/executor boundary + seeded-mutation kills). Its GATE, however, REQUIRES the
action-reference-monitor CONTRACT (proposal/manifest/authorization/permit/executor/completion) to be frozen FIRST --
so the pre-action-capable sequence is: (1) freeze `lifeorch.action_proposal/tool_manifest/action_permit` +
completion-predicate contracts (design-now, no coordinator yet); (2) build the P0-1 suite against them + the
shipped packet separation; (3) only then design an action-capable coordinator. None of this unblocks side effects
now -- `non_execution:true` holds; the memory substrate stays read-only.