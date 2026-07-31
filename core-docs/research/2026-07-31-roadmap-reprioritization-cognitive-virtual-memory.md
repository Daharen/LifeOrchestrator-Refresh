# LIFE ORCHESTRATOR ROADMAP REPRIORITIZATION
## Cognitive Virtual Memory, Selective Skill Activation, and Delegated Construction on the RTX 2080 Ti — with RTX PRO 6000 as the Horizon Platform

**Date:** 2026-07-31  
**Prepared for:** Nicholas Johnson and the Life Orchestrator fan-out orchestrator  
**Authority:** User-directed strategic reprioritization  
**Current machine:** RTX 2080 Ti 11 GB, i9-9900KF, 64 GB RAM, Windows, one heavyweight GPU resident at a time  
**Horizon machine:** RTX PRO 6000-class 96 GB system, with supporting CPU/RAM/storage upgrades as practical  
**Primary objective:** Make Nicholas the manager, product owner, and final authority over a local system that retrieves its own relevant knowledge, activates the right skills, delegates bounded work, verifies results, learns reusable procedures from experience, and iteratively constructs both Life Orchestrator and other projects such as a game.

---

## 1. DIRECTIVE TO THE FAN-OUT ORCHESTRATOR

The project’s immediate priority is no longer continued breadth-first expansion of isolated Modules, further generator upgrades, or prolonged optimization of model-residency infrastructure as an end in itself.

The highest-leverage path is now to build the **memory, retrieval, context-compilation, skill-activation, episode-recording, failure-recall, procedure-promotion, and sandboxed-work orchestration layers** that turn the existing collection of Modules into one persistent Collective Agent.

Treat this as an explicit user authorization to revise the project direction and build order accordingly.

The orchestrator should:

1. Record a new decision entry establishing this reprioritization.
2. Revise the current-truth and roadmap documents by replacement, not by narrative accretion.
3. Preserve the existing verification, audit, resource-lease, idempotency, and documentation disciplines.
4. Pull `artifact.search`, repository intelligence, context compilation, episodic/failure memory, skill retrieval/routing, procedure learning, and bounded local orchestration forward.
5. Freeze or defer work that does not materially advance the Collective Agent’s ability to retrieve, decide, delegate, verify, remember, and improve.
6. Scope and launch the first fan-out workloads described in this directive.
7. Treat the RTX 2080 Ti as the active engineering target and the RTX PRO 6000 as a planned model-quality and concurrency upgrade—not as a prerequisite for the architecture.
8. Preserve the hard distinction between:
   - the human-couriered external frontier fan-out process; and
   - a future deterministic local coordinator that may create fresh logical contexts and invoke local models.
9. Keep disk as canonical, maintain the existing mirror protocol, use named-file commits, and enforce the project’s document budgets.
10. Return to Nicholas only for genuine strategic choices, qualitative acceptance decisions, unresolved requirements, or authority changes—not for routine decomposition, testing, retrying, indexing, or implementation details that the system can handle itself.

This is not a request to discard the existing architecture. It is a request to connect it into the architecture that makes the existing work cumulatively useful.

---

## 2. THE REVISED NORTH STAR

### 2.1 The target user relationship

Nicholas should increasingly operate at the following level:

- Define what he wants.
- Set priorities, constraints, aesthetic direction, and acceptable tradeoffs.
- Approve major architecture and irreversible changes.
- Review playable builds, life-management recommendations, research conclusions, or other meaningful outputs.
- Reject, redirect, or reprioritize work.

The system should increasingly handle:

- Converting broad goals into bounded projects and work orders.
- Finding the relevant project knowledge, tools, procedures, and past failures.
- Decomposing work into sequential or parallel units.
- Selecting the appropriate local model and tool path.
- Running bounded implementation workers in isolated environments.
- Running tests, critics, reviewers, and integration checks.
- Recording evidence and producing promotion packets.
- Retrying when verification fails.
- Updating project state and proposing the next work.
- Escalating only the parts that truly require Nicholas or a frontier model.

The desired outcome is not merely a better chatbot. It is a **persistent local managerial and construction system** whose currently active reasoner is only one component.

### 2.2 The current-machine target

On the RTX 2080 Ti, the realistic target is:

> A frontier-supervised but increasingly self-operating local apprentice organization: one resident 9B-class executive model at a time, many fresh logical agent contexts, extensive deterministic tools, external memory, bounded work orders, sandboxed execution, independent review, and machine-checkable promotion gates.

The system will not become frontier-equivalent merely by running longer. It can nevertheless produce a large amount of useful work because:

- the computer may operate continuously;
- logical agents can share one resident model while using fresh contexts;
- most memory can remain outside the LLM;
- many tasks can be decomposed into narrow units;
- deterministic software can perform and verify much of the work;
- repeated solutions can be collapsed into procedures;
- failures can become retrieval-triggered prevention records;
- the 9B model can spend its limited intelligence only on the current decision.

### 2.3 The horizon-machine target

On the RTX PRO 6000-class platform, the same architecture should support:

- a substantially stronger local planner and coding model;
- larger context packets where useful;
- fewer retrieval rounds for complex tasks;
- better multi-file and repository-level reasoning;
- more capable local review and diagnosis;
- larger vision, coding, and specialist models;
- practical LoRA or adapter training;
- more model concurrency or reduced swap pressure;
- fewer frontier escalations;
- a more credible transition from “apprentice organization” to “local technical lead.”

The architecture must not depend on 96 GB VRAM to function. The larger GPU should increase executive competence and throughput without requiring a redesign of memory, contracts, procedures, verification, or the user interface.

---

## 3. CORE ARCHITECTURAL CLAIM

The Collective Agent must not be designed as:

> One small model attempting to remember the entire project and every tool in one prompt.

It must be designed as:

> A deterministic coordinator and memory manager that gives a model a small, task-specific working set; the model makes bounded decisions; specialist Modules execute; evaluators verify; successful experience becomes structured memory and reusable procedure.

This is **cognitive virtual memory**.

The analogy is useful:

| Computer concept | Collective Agent counterpart |
|---|---|
| Persistent storage | Files, SQLite, artifact store, source repository |
| Index | Full-text search, vector index, symbol index, relationship tables |
| Virtual-memory manager | Retrieval, reranking, context compiler, token budgeter |
| Working memory | Current model context |
| CPU | Active 3B/9B or future larger model |
| Programs | Skills, procedures, workflows, controllers |
| Processes | Fresh logical worker, reviewer, planner, or critic contexts |
| Kernel | Deterministic coordinator, permissions, leases, state machine |
| Interrupts | Test failures, new events, deadlines, changed files, contradictions |
| Logs | Episodes, traces, artifacts, model provenance, verifier results |
| Compilation | Turning a successful stochastic solution into a stable procedure |

The model does not need to memorize a 200 MB project. It needs to know how to interrogate an authoritative representation of that project.

---

## 4. STRATEGIC PRINCIPLES TO LOCK

### 4.1 External memory is authoritative; context is disposable

The source repository, databases, manifests, tests, and artifacts are authoritative. A model context is a temporary workspace and may be destroyed at any time.

Do not preserve hidden reasoning as durable project state. Preserve:

- the immutable goal;
- the normalized plan;
- completed-stage summaries;
- authoritative state changes;
- artifact references and hashes;
- decisions and evidence;
- open questions;
- constraints;
- the next-stage instruction;
- bounded raw evidence needed for verification.

### 4.2 Retrieve evidence, not merely summaries

Summaries are navigational layers, not replacements for source material.

Every summary must retain provenance to:

- the source file;
- version or content hash;
- source span, symbol, section, or chunk;
- parser and summarizer version;
- creation time;
- supersession or staleness status.

The context compiler should expand from a summary into raw evidence when the decision requires precision.

### 4.3 Embeddings are semantic addresses, not compressed documents

An embedding vector identifies semantic similarity. It does not replace the original text.

The system must store:

- original content or a canonical file reference;
- chunk metadata;
- embedding vector;
- lexical index;
- structured relationships;
- optional summaries;
- provenance and version fields.

### 4.4 Hybrid retrieval is mandatory

No single retrieval method is sufficient.

Use:

1. **Exact and lexical search** for filenames, symbols, error strings, IDs, and literal language.
2. **Semantic vector search** for conceptually similar content, procedures, failures, and episodes.
3. **Structured filters** for project, module, file type, date, version, model, status, permission, and authority.
4. **Relationship traversal** for explicit dependencies, consumers, producers, tests, decisions, and supersession.
5. **Reranking** to select the most useful evidence from the candidate pool.
6. **Model judgment** only after the search space is narrowed.

### 4.5 The deterministic coordinator owns the loop

The LLM may propose plans and actions. It must not own:

- durable task state;
- leases;
- authority;
- sandbox lifecycle;
- retry counts;
- timeouts;
- promotion;
- rollback;
- evaluator definitions;
- permission changes;
- idempotency;
- the meaning of success.

### 4.6 Fresh logical agents may share one resident model

Planner, worker, reviewer, critic, and summarizer roles may be separate logical contexts served by the same resident 9B model.

Do not assume each agent requires a separate model load or process. The current machine should prefer:

- one resident heavyweight model;
- fresh bounded contexts;
- sequential task execution;
- concise checkpoints;
- same-model reuse;
- explicit GPU handoff only when a different heavyweight pipeline is required.

### 4.7 Verification must be at least partly independent

A same-strength reviewer with a smaller task is useful, but two 9B contexts may share blind spots.

Independence should be increased through:

- blind review without the worker’s rationale;
- different prompts or roles;
- alternate retrieval packets;
- deterministic tests;
- static analysis;
- property-based tests;
- mutation tests;
- integration fixtures using real producer output;
- alternate implementation attempts;
- different models when available;
- human review for ambiguous or qualitative outcomes.

### 4.8 Promote learning into lower-cost forms

Repeated success should progressively become:

1. a retrieved example;
2. a structured failure-prevention rule;
3. a verified procedure;
4. a deterministic workflow or controller;
5. a small classifier or specialist model;
6. only later, a model adapter or fine-tune.

Do not begin with expensive foundation-model training.

### 4.9 Negative results are durable assets

Failed model choices, broken contracts, retrieval misses, silent unit disagreements, poor quantizations, and unsuccessful procedures must be stored as queryable evidence.

A failure should reduce the chance that the same failure happens again.

---

## 5. REQUIRED MEMORY TYPES

The roadmap should distinguish at least five memory classes.

### 5.1 Semantic memory

Stores facts and descriptions:

- project definitions;
- current architecture;
- user preferences and standing constraints;
- module purposes;
- game design and lore;
- technical documentation;
- decisions;
- entity descriptions;
- state summaries.

Primary retrieval methods:

- semantic vectors;
- lexical search;
- metadata filters;
- relationship traversal.

### 5.2 Procedural memory

Stores verified ways of doing things:

- preconditions;
- required inputs;
- permitted tools;
- ordered stages;
- expected state changes;
- completion predicates;
- failure branches;
- rollback instructions;
- version and verification history;
- resource requirements;
- examples and counterexamples.

Procedures should be machine-readable and separately renderable as human-readable Markdown.

### 5.3 Episodic memory

Stores individual task experiences:

- original request;
- task classification;
- retrieved context;
- plan;
- selected skills;
- model configuration;
- tool calls;
- state transitions;
- artifacts;
- tests;
- reviewer findings;
- human corrections;
- final outcome;
- compute and time costs;
- reasons for escalation.

Episodes become training and evaluation data for routers, failure classifiers, procedure discovery, and future model adaptation.

### 5.4 Failure memory

Stores context-sensitive failure records.

A failure record should include:

- component and version;
- attempted operation;
- environmental conditions;
- observable symptoms;
- failure signature;
- root cause or current hypothesis;
- evidence;
- correction;
- prevention rule;
- affected versions;
- verification case;
- confidence and status;
- links to episodes, tests, commits, decisions, and artifacts.

Failure retrieval must be conditioned on the active task, selected skills, relevant file types, schemas, model configuration, and planned operations.

Unrelated failure history must not burden the context.

### 5.5 Prospective memory

Stores things that must matter later:

- reminders;
- deadlines;
- blocked tasks;
- awaited dependencies;
- recurring checks;
- conditions that trigger work;
- questions to revisit after a hardware, model, or project change;
- obligations and appointments;
- follow-up actions.

This is the foundation for external life management.

---

## 6. DATA AND INDEX ARCHITECTURE

### 6.1 SQLite as the first authoritative catalog

Start with SQLite rather than introducing a distributed database.

Suggested logical tables include:

- `sources`
- `documents`
- `document_versions`
- `chunks`
- `chunk_embeddings`
- `projects`
- `modules`
- `skills`
- `skill_versions`
- `procedures`
- `procedure_versions`
- `episodes`
- `episode_stages`
- `failures`
- `failure_signatures`
- `tests`
- `test_results`
- `artifacts`
- `claims`
- `decisions`
- `entities`
- `relationships`
- `tasks`
- `dependencies`
- `reminders`
- `context_packets`
- `retrieval_runs`
- `human_reviews`
- `promotions`

SQLite should own identifiers, versions, hashes, status, relationships, and authoritative metadata.

### 6.2 Full-text search

Use SQLite FTS or an equivalent local lexical index for:

- exact phrases;
- filenames;
- symbols;
- error messages;
- decision IDs;
- module IDs;
- command names;
- test names;
- user terminology.

### 6.3 Vector index

The vector index should return record IDs, not replace the records.

Initially, use the pre-provisioned embedding model already intended for artifact search. The implementation should support:

- batch embeddings;
- normalized vectors;
- deterministic model provenance;
- versioned embedding spaces;
- re-embedding on model change;
- CPU fallback where practical;
- index rebuild without losing canonical records.

### 6.4 Relationship model

A dedicated graph database is not required for the first implementation. SQLite relationship tables are sufficient.

Relationship examples:

- module consumes schema;
- module produces artifact kind;
- test verifies module;
- procedure invokes skill;
- failure occurred in episode;
- decision supersedes decision;
- file defines symbol;
- symbol calls symbol;
- task depends on task;
- game system depends on subsystem;
- reminder refers to person, appointment, or project.

### 6.5 Files remain canonical where appropriate

Do not copy every source byte into SQLite if the filesystem is already canonical.

Store:

- path;
- content hash;
- size;
- timestamps;
- parser;
- version;
- chunk spans;
- source type;
- repository commit where applicable.

Artifacts and database records must be mutually traceable.

---

## 7. INGESTION AND REPOSITORY-INTELLIGENCE PIPELINE

The initial target corpus should include the current Life Orchestrator repository, approaching approximately 200 MB and thousands of folders/files.

### 7.1 Inventory

The indexer should:

1. Walk configured roots.
2. Apply explicit inclusion and exclusion rules.
3. Record file metadata and content hashes.
4. Identify changed, new, moved, and deleted files.
5. Avoid unnecessary reprocessing.
6. Surface parser failures rather than silently omitting files.
7. Preserve repository-relative and absolute path information appropriately.

### 7.2 Type-aware parsing

Parsing should be specialized by source type:

- Markdown: headings, sections, lists, code blocks, links.
- Source code: language, symbols, imports, classes, functions, signatures, comments.
- JSON/YAML/TOML: structural paths and schema-like records.
- Logs: events, timestamps, severity, signatures.
- Git: commits, diffs, authorship, changed files.
- Test results: suite, case, status, timing, evidence.
- Skill manifests: operations, inputs, outputs, flags, side effects, dependencies.
- Artifacts: kind, producer, invocation, hash, human-visible preview information.

### 7.3 Hierarchical summaries

For large material, create a tree:

- source chunk;
- section or symbol summary;
- file summary;
- folder or subsystem summary;
- project summary.

Every parent must retain child references.

Do not use one rolling summary that repeatedly overwrites prior information. Use parallel chunk analysis followed by hierarchical consolidation.

### 7.4 Repository intelligence beyond embeddings

For code, add:

- symbol index;
- definition and reference mapping;
- import/dependency relationships;
- test ownership;
- file-to-module mapping;
- schema producer/consumer mapping;
- git history links;
- changed-file invalidation;
- eventually, AST and call graph extraction.

### 7.5 Continuous update

A filesystem watcher should queue incremental re-indexing. It must:

- debounce bursts;
- hash before expensive work;
- version records;
- invalidate stale summaries and vectors;
- preserve historical versions when required;
- update only affected hierarchy nodes;
- report backlog and failures.

---

## 8. RETRIEVAL AND CONTEXT-COMPILATION PIPELINE

This is the architectural centerpiece.

### 8.1 Task interpretation

For every new task, determine:

- project and domain;
- requested outcome;
- whether side effects are requested;
- relevant files or entities;
- time horizon;
- risk and authority level;
- resource needs;
- candidate success predicates;
- whether the request is research, life management, coding, game development, media, observation, or another category.

### 8.2 Candidate retrieval

Retrieve a broad candidate set from:

- project state;
- source chunks;
- summaries;
- skills;
- procedures;
- similar successful episodes;
- relevant failures;
- tests;
- decisions;
- entities and relationships.

### 8.3 Reranking and diversity

Rerank by:

- direct relevance;
- authority;
- freshness;
- project match;
- component match;
- source quality;
- task-stage match;
- failure likelihood;
- procedural applicability.

Prevent ten near-duplicate results from crowding out distinct necessary evidence.

### 8.4 Context packet

The context compiler should emit a versioned packet containing:

- immutable original goal;
- normalized task statement;
- current authoritative state;
- constraints and permissions;
- relevant source excerpts with provenance;
- candidate skills;
- relevant procedures;
- relevant failure records;
- similar successful examples;
- open questions;
- required completion contract;
- token-budget accounting;
- omitted-context summary;
- escalation conditions.

The packet should be small enough for the selected model and specific enough that a fresh context can act without loading the whole project.

### 8.5 Adaptive expansion

The worker may request expansion:

- fetch raw source behind a summary;
- retrieve more evidence for one claim;
- inspect a related symbol;
- obtain a failure record;
- retrieve a tool’s full contract;
- fetch a prior episode.

The worker should not receive the entire database.

### 8.6 Context quality signals

Record:

- which records were retrieved;
- why;
- rank;
- score;
- whether each record was used;
- whether missing context caused failure;
- whether irrelevant context caused confusion;
- final task outcome.

This creates data for improving retrieval.

---

## 9. SKILL ACTIVATION AND TOOL-SELECTION PIPELINE

The 9B model should never receive every command and complete implementation detail.

### Stage 1 — deterministic eligibility filtering

Filter by:

- task type;
- side-effect policy;
- permissions;
- operating system;
- target application;
- file type;
- module health;
- resource availability;
- parallel-safety;
- dependency status;
- model or GPU requirements.

### Stage 2 — semantic skill retrieval

Embed the task and retrieve candidate:

- skills;
- procedures;
- examples;
- failures.

### Stage 3 — lightweight task classifier

Classify across stable dimensions such as:

- research;
- coding;
- file manipulation;
- planning;
- life management;
- desktop observation;
- UI action;
- image/audio/video;
- game subsystem;
- verification;
- documentation.

Begin with a small model or deterministic rules. As episodes accumulate, train a compact classifier.

### Stage 4 — reranker

Reduce to a small candidate set.

### Stage 5 — 9B preflight

Give the 9B:

- task;
- constraints;
- candidate skill cards;
- procedures;
- relevant failures;
- completion contract.

It chooses a bounded plan.

### Stage 6 — deterministic plan validation

Reject:

- unknown skill IDs;
- invalid schemas;
- missing required fields;
- forbidden side effects;
- unavailable dependencies;
- resource conflicts;
- plans without a closing condition;
- duplicate mutation attempts;
- authority violations.

### Skill card format

Every skill card should include:

- purpose;
- supported operations;
- typed inputs;
- one valid example;
- preconditions;
- side effects;
- artifacts;
- latency/resource class;
- deterministic completion checks;
- common failure or refusal conditions;
- version and health status.

Detailed implementation documentation should be retrieved only when needed.

---

## 10. EPISODE, FAILURE, AND PROCEDURE LEARNING

### 10.1 Episode recorder

Every significant run should produce a structured episode even when it fails.

Required fields:

- task ID and parent project;
- original request;
- context packet ID;
- plan;
- stage sequence;
- model and engine provenance;
- tool invocations;
- state changes;
- artifacts and hashes;
- test results;
- reviewer outcomes;
- human interventions;
- final status;
- time and resource metrics;
- failure or escalation reasons.

### 10.2 Failure miner

A scheduled or manually invoked process should identify:

- repeated errors;
- repeated human corrections;
- repeated retrieval misses;
- high-cost paths;
- silent integration disagreements;
- frequently failing tool combinations;
- model/configuration-specific problems;
- procedures with low success rates.

It should propose candidate failure records or prevention rules, not promote them automatically.

### 10.3 Procedure discovery

When several episodes show a recurring successful sequence:

1. Identify invariant preconditions and steps.
2. Extract variable parameters.
3. Name completion checks.
4. Identify common failure branches.
5. Create a candidate machine-readable procedure.
6. Replay it against past episodes or fixtures.
7. Run adversarial and boundary cases.
8. Submit a promotion packet.

### 10.4 Promotion authority

The model may propose. The deterministic system evaluates. Nicholas or an authorized promotion policy approves.

Changes to the following always require elevated approval:

- evaluator definitions;
- permissions;
- executor authority;
- sandbox escape boundaries;
- core contracts;
- destructive operations;
- automatic promotion policy;
- safety or privacy rules.

### 10.5 Rollback

Every promoted procedure, classifier, route rule, or module version must be:

- versioned;
- reversible;
- tied to evaluation evidence;
- monitored through canaries;
- automatically disabled on defined regressions where safe.

---

## 11. VERIFICATION ARCHITECTURE

Verification is not a final step. It is a design requirement for every capability.

### 11.1 Retrieval verification

Create a benchmark corpus with known-required sources.

Measure:

- recall at K;
- mean reciprocal rank;
- exact-source retrieval;
- stale-source exclusion;
- version correctness;
- provenance completeness;
- failure-memory trigger recall;
- false-positive retrieval burden;
- context packet size;
- task success with and without retrieval.

### 11.2 Summary verification

Use:

- section coverage;
- claim-to-source links;
- contradiction detection;
- stratified source sampling;
- pre-generated questions;
- reconstruction tests;
- hierarchy consistency;
- unsupported-claim rejection.

Random samples are supplementary, not sufficient.

### 11.3 Skill routing verification

Use a labeled task suite:

- expected eligible tools;
- forbidden tools;
- required procedures;
- relevant failure records;
- side-effect constraints;
- route confidence;
- false-positive and false-negative rates.

### 11.4 Procedure verification

Use:

- deterministic fixtures;
- recorded episode replay;
- edge cases;
- fault injection;
- idempotency tests;
- interruption and resume;
- rollback tests;
- state-diff checks.

### 11.5 Coding verification

Use:

- compile/build;
- unit tests;
- integration tests;
- property-based tests;
- static analysis;
- format/lint checks;
- mutation testing where valuable;
- real producer-to-consumer fixtures;
- benchmark comparison;
- executable smoke tests;
- artifact inspection.

### 11.6 Review-agent verification

Evaluate reviewers themselves:

- known-bug detection rate;
- false approvals;
- false rejections;
- calibration;
- independence from worker rationale;
- value added beyond deterministic tests.

Do not assume that another 9B context is automatically a competent judge.

### 11.7 Human verification

The Verification Console remains important, but it should evolve from an isolated widget into one approval surface inside the future unified interface.

Human review packets should include:

- what changed;
- why;
- evidence;
- unresolved ambiguity;
- exact decision requested;
- rollback path;
- previewable artifacts;
- no unnecessary implementation logs.

---

## 12. SANDBOXED CODING AND SELF-CONSTRUCTION PIPELINE

The goal is for the system to construct Modules and game systems while Nicholas manages direction.

### 12.1 Work-order generation

A planner creates a bounded work order containing:

- concrete problem;
- immediate use;
- explicit scope;
- non-goals;
- dependencies;
- allowed files;
- tools;
- success contract;
- required tests;
- resource budget;
- escalation conditions.

### 12.2 Isolation

Use the lightest adequate isolation:

- git worktree for ordinary repository tasks;
- restricted subprocess/container where practical;
- full VM for installers, unknown code, OS-level changes, or clean-machine reproducibility;
- explicit GPU scheduling only when required.

### 12.3 Worker cycle

1. Receive context packet and work order.
2. Inspect only relevant code and evidence.
3. Propose a stage plan.
4. Modify the isolated workspace.
5. Build and test.
6. Diagnose failures.
7. Retry within a bounded budget.
8. Produce a diff, artifacts, tests, and report.

### 12.4 Independent review cycle

A reviewer receives:

- work order;
- diff;
- relevant source;
- tests and results;
- no worker chain-of-thought.

It searches for:

- unmet requirements;
- hidden assumptions;
- regressions;
- missing tests;
- unsafe side effects;
- contract incompatibilities;
- stale documentation;
- integration risks.

### 12.5 Promotion cycle

The coordinator:

1. Runs required gates.
2. Runs real producer/consumer smoke tests where applicable.
3. Compares candidate and baseline.
4. Builds a promotion packet.
5. Requests human approval only when required.
6. Commits named files under the existing git discipline.
7. Records the episode and any failures.
8. Updates the task graph.

---

## 13. GAME-DEVELOPMENT MANAGEMENT PROSPECT

The target is not “generate a whole game from one prompt.” It is an iterative software organization.

### 13.1 Game knowledge model

Store:

- design bible;
- architecture;
- subsystem contracts;
- game rules;
- lore;
- art direction;
- assets;
- current playable state;
- backlog;
- dependencies;
- known bugs;
- performance budgets;
- acceptance criteria;
- test scenes;
- deterministic seeds;
- save-state fixtures;
- telemetry.

### 13.2 Managerial loop

Nicholas provides a goal such as:

- improve combat feedback;
- build inventory;
- add procedural rooms;
- implement an enemy family;
- improve progression;
- make a playable vertical slice.

The system:

1. Retrieves the relevant design and architecture.
2. Decomposes the goal into bounded backlog items.
3. Identifies dependencies and risks.
4. Creates work orders.
5. Runs coding workers.
6. Builds and tests.
7. Captures screenshots/video/telemetry.
8. Runs review and regression.
9. Produces a playable build.
10. Presents Nicholas with meaningful product decisions.
11. Records feedback.
12. Iterates.

### 13.3 Required game verification

- automated builds;
- deterministic test scenes;
- save/load checks;
- performance telemetry;
- screenshot or video comparisons;
- input replay;
- crash and log inspection;
- gameplay invariant checks;
- balance simulations where feasible;
- human playtest acceptance.

### 13.4 Engine strategy

Keep engine-facing interfaces modular and exportable. The system should be able to build an MVP using an engine while preserving domain logic, data formats, and module boundaries that reduce lock-in.

Do not attempt to abstract every engine before a playable loop exists. Preserve attachment points and tests.

---

## 14. EXTERNAL LIFE-MANAGEMENT PROSPECT

Life management requires prospective memory plus controlled access to personal systems.

### 14.1 Capability classes

- reminders and follow-up;
- calendar and scheduling;
- task and project tracking;
- correspondence preparation;
- document organization;
- deadline and dependency tracking;
- recurring household or administrative workflows;
- financial record organization;
- travel research;
- health and appointment preparation;
- personal knowledge retrieval.

### 14.2 Life-management loop

1. Capture a request, event, or obligation.
2. Identify entities, dates, dependencies, and authority.
3. Retrieve relevant preferences and prior episodes.
4. Determine whether action, reminder, research, or human approval is needed.
5. Create tasks and conditions.
6. Monitor status where authorized.
7. Surface only meaningful decisions or changes.
8. Record completion and update future procedures.

### 14.3 Privacy and authority

Personal data remains local by default.

The coordinator must distinguish:

- read-only retrieval;
- draft creation;
- reversible local changes;
- external communication;
- financial or legal commitment;
- destructive action.

External or consequential actions require explicit authorization unless a separately approved standing policy exists.

---

## 15. BROAD SEARCH AND RESEARCH PROSPECT

The system should support research across almost any task without loading entire corpora.

### 15.1 Research pipeline

1. Clarify the decision or deliverable.
2. Decompose into research questions.
3. Search local memory first.
4. Acquire external sources where permitted.
5. Preserve provenance and retrieval date.
6. Parse and chunk.
7. Extract claims and evidence.
8. Detect contradictions and gaps.
9. Retrieve source passages for synthesis.
10. Produce a cited result.
11. Store durable findings and unresolved questions.
12. Update or invalidate findings when sources change.

### 15.2 Research roles

Logical contexts may include:

- query planner;
- source collector;
- source-quality reviewer;
- extractor;
- contradiction finder;
- synthesizer;
- final verifier.

These roles may use the same resident model sequentially.

---

## 16. RTX 2080 TI OPERATING POLICY

### 16.1 One heavyweight resident

Assume only one major LLM or generator is resident at a time.

Prefer:

- 9B for planning, difficult routing, synthesis, coding, and review;
- 3B or smaller models for stable classification/extraction where measured adequate;
- deterministic software whenever possible;
- sequential logical agents over simultaneous heavyweight residents.

### 16.2 Embedding workload

Embedding is batchable and may run:

- during idle periods;
- at lower priority;
- on GPU under the lease;
- on CPU as a fallback if practical;
- incrementally after initial indexing.

Do not repeatedly embed unchanged content.

### 16.3 Context discipline

The 9B should receive compact context packets, not long hot documents.

Use:

- fresh contexts;
- retrieval expansion;
- bounded stage checkpoints;
- same-model reuse;
- context-size metrics;
- explicit truncation detection.

### 16.4 Overnight and idle work

Use idle compute for:

- corpus indexing;
- embedding;
- retrieval evaluation;
- episode mining;
- procedure candidate generation;
- test generation;
- sandbox builds;
- regression suites;
- low-priority research;
- asset processing.

### 16.5 Infrastructure freeze

Preserve the classic detached warm-server path as the trusted baseline.

The durable supervisor and multi-model pool should remain optional/default-off until their remaining gates are justified by real workload value. Do not allow additional supervisor hardening to consume the next roadmap waves unless:

- a defect threatens the trusted baseline;
- it blocks the first memory/orchestration workloads;
- or measured task throughput proves the improvement is necessary.

The current project has already invested heavily in this infrastructure. Treat it as sufficient substrate for now, not as the product.

### 16.6 Do not pursue on the 2080 Ti

Defer:

- broad foundation-model training;
- attempts to make the 27B a normal top tier;
- unrestricted general autonomous planning;
- simultaneous heavyweight agents;
- speculative distributed infrastructure;
- broad model fine-tuning before episode data and evaluations exist.

---

## 17. RTX PRO 6000 HORIZON REQUIREMENTS

Maintain a hardware-abstraction layer so the upgrade changes configuration rather than architecture.

### 17.1 Model tier changes

The future platform may support:

- high-fidelity 27B-class planner/coder;
- larger quantized reasoning models;
- stronger VLMs;
- more capable specialist models;
- larger context;
- model adapters;
- limited multi-model residency.

### 17.2 System upgrades

Plan for:

- at least 128 GB system RAM, preferably more if large models and indexes justify it;
- fast NVMe capacity;
- appropriate power and cooling;
- stronger CPU/platform for compilation, indexing, media, and prompt prefill.

### 17.3 Migration tests

Before changing the primary model:

- rerun retrieval benchmarks;
- rerun skill-routing benchmarks;
- rerun reviewer calibration;
- rerun procedure suites;
- compare task success, latency, and compute;
- re-embed only if the embedding model changes;
- preserve rollback to the 2080 Ti configuration.

---

## 18. ROADMAP REPRIORITIZATION

### Priority 0 — Direction and document reset

**Owner:** fan-out orchestrator itself.

Revise:

- `PROJECT_DIRECTION.md`
- `CURRENT_STATE.md`
- `MODULE_ROADMAP.md`
- `ARCHITECTURE_MAP.md`
- `FANOUT_ORCHESTRATOR_HANDOFF.md`
- `DECISION_LOG.md`
- `DECISION_LOG_INDEX.md`

Actions:

- Add the cognitive-virtual-memory north star.
- State the 2080 Ti target and RTX PRO 6000 horizon.
- Pull memory/search/context/routing/orchestration work forward.
- Mark video interpretation, generator upgrades, and nonblocking supervisor work as deferred.
- Preserve current modules and current truth.
- Add a new decision record.
- Create bounded work orders for the first wave.
- Keep document budgets through replacement and archiving.

### Priority 1 — Embedding service and artifact-search substrate

Build:

- a versioned embedding adapter/service;
- deterministic artifact catalog;
- SQLite schema;
- FTS;
- filesystem ingestion;
- typed chunk records;
- query API;
- provenance;
- incremental updates;
- initial Life Orchestrator corpus.

### Priority 2 — Retrieval evaluation

Build:

- benchmark queries;
- known-required sources;
- metrics;
- stale-version cases;
- failure-retrieval cases;
- regression command;
- human-readable report.

No retrieval system is accepted without measured retrieval quality.

### Priority 3 — Repository intelligence

Add:

- type-aware parsers;
- Markdown hierarchy;
- code symbol index;
- manifest index;
- test/module relationships;
- producer/consumer relationships;
- git version links;
- incremental invalidation.

### Priority 4 — Context compiler

Build:

- task normalization;
- candidate retrieval;
- reranking;
- token budget;
- context packet schema;
- source provenance;
- adaptive expansion;
- omitted-context record;
- packet evaluation.

### Priority 5 — Episodic and failure memory

Build:

- episode schema;
- automatic episode capture;
- failure record schema;
- failure-signature retrieval;
- human correction capture;
- failure mining;
- benchmark suite.

### Priority 6 — Skill and procedure registry

Build:

- compact skill cards;
- procedure schema;
- procedure versioning;
- candidate extraction from episodes;
- replay verification;
- promotion and rollback.

### Priority 7 — Skill routing and strong preflight

Generalize routing into:

- deterministic eligibility;
- embedding candidate retrieval;
- lightweight classification;
- reranking;
- 9B bounded selection;
- deterministic plan validation.

The existing strong-preflight work may be incorporated here, but it should consume the retrieval/context infrastructure rather than remain only a model-tier switch.

### Priority 8 — Read-only Collective Agent vertical slice

A single user request should:

1. enter through one command/UI path;
2. retrieve project knowledge;
3. select skills;
4. compile a context packet;
5. run a fresh 9B context;
6. produce an answer with source references;
7. record an episode;
8. expose retrieval and verification evidence.

No side effects in the first slice.

### Priority 9 — Sandboxed coding worker

Build:

- work-order generator;
- worktree lifecycle;
- restricted command runner;
- build/test loop;
- independent reviewer;
- promotion packet;
- rollback.

### Priority 10 — Sequential local orchestrator

Use the already-developed baton-pass concepts, but connect them to:

- context packets;
- episode state;
- procedure records;
- failure recall;
- sandbox workers;
- frozen success contracts.

Prove A→B→A resume, interruption recovery, exactly-once effects, and no human courier step for local contexts.

### Priority 11 — Domain vertical slices

Build three bounded demonstrations:

1. **Life management:** prospective memory and one recurring workflow.
2. **Research:** broad search with provenance and contradiction handling.
3. **Game development:** one manager request converted into work orders, implementation, build, review, and playable artifact.

### Priority 12 — Unified user interface

Build the single-access-point interface described in the addendum after the read-only Collective Agent path exists. Do not build an attractive shell around disconnected workflows before the core context and memory path is real.

### Priority 13 — Specialist training and future model adaptation

Only after sufficient episodes and labels exist:

- skill classifier;
- failure classifier;
- reranker;
- specialist extraction models;
- LoRA/adapters on future hardware.

---

## 19. FIRST FAN-OUT WORKLOADS

The first wave should prove the foundational producer-consumer chain.

The orchestrator must first perform Priority 0 and create the work orders. Workers remain `docs:[]`; the orchestrator alone folds shared documents.

### Wave 1, GPU lane — Embedding adapter

**Goal:** Turn the existing pre-provisioned embedding model into a conforming, versioned, testable local capability.

**Scope:**

- text and batch-text input;
- normalized vector output;
- dimensions and model provenance;
- deterministic input-order preservation;
- explicit empty/oversize handling;
- GPU lease;
- CPU fallback feasibility probe;
- no vector database;
- no artifact ingestion;
- no routing.

**Acceptance:**

- stable schema;
- repeated-input consistency within defined tolerance;
- batch/single equivalence;
- no orphaned model processes;
- model/version/hash recorded;
- latency and memory measurements;
- fixture vectors or similarity-order tests;
- clean failure modes.

### Wave 1, coding lane — `artifact.search` deterministic MVP

**Goal:** Create the authoritative catalog and hybrid lexical-search substrate.

**Scope:**

- SQLite schema;
- source and version records;
- file inventory;
- content hash;
- Markdown-aware chunking;
- generic text chunk fallback;
- FTS;
- metadata filters;
- embedding-provider interface with a mock;
- search result provenance;
- incremental changed-file ingest;
- initial CLI/skill contract.

**Non-goals:**

- AST/call graph;
- summaries;
- episodes;
- failure memory;
- context compiler;
- UI;
- general web search.

**Acceptance:**

- index a bounded fixture repository;
- index a bounded slice of the real repository;
- exact and FTS retrieval;
- deterministic re-ingest;
- changed/deleted file reconciliation;
- no duplicate chunks;
- database integrity check;
- provenance from result to source;
- mock embedding contract tests.

### Wave 1, CPU lane — Retrieval evaluation harness

**Goal:** Make retrieval quality measurable before vector integration.

**Scope:**

- benchmark schema;
- query and required-source labels;
- lexical baseline;
- recall@K, MRR, stale-source errors, provenance checks;
- report artifact;
- fixture corpus;
- initial Life Orchestrator benchmark questions;
- no production router.

**Acceptance:**

- deterministic benchmark run;
- known lexical baseline;
- failing test when a required source is absent;
- version/staleness test;
- machine-readable and human-readable reports.

### Wave 1, optional frontier lane — Memory architecture red-team

Review:

- SQLite schema;
- embedding adapter contract;
- artifact-search boundaries;
- benchmark design;
- provenance;
- versioning;
- privacy;
- failure modes;
- 2080 Ti operating assumptions.

This is a design review only. The local wave must not block on it unless the orchestrator identifies a safety-critical issue.

### Orchestrator fold after Wave 1

The orchestrator must run a real producer-consumer smoke:

1. embedding adapter produces vectors;
2. `artifact.search` ingests them;
3. benchmark executes hybrid retrieval;
4. results resolve to real source spans;
5. repeat run is stable;
6. changed-file re-index updates results;
7. all artifacts and model provenance are captured.

Parallel isolated worker tests are not sufficient.

---

## 20. SECOND AND THIRD WAVES

### Wave 2 — Repository intelligence and memory records

Suggested disjoint lanes:

- Markdown hierarchy and file/folder summary records;
- code/symbol/manifest/test relationship index;
- episode and failure schema plus recorder;
- optional frontier review of context-compilation schema.

Run cross-module ingestion against real repository data.

### Wave 3 — Context compiler and skill retrieval

Suggested lanes:

- context packet compiler;
- compact skill-card generator and skill index;
- retrieval reranker/evaluation expansion;
- optional strong-preflight integration.

Acceptance requires a fresh 9B context to answer repository questions using only compiled packets, with source provenance and measured token use.

---

## 21. SUCCESS METRICS FOR THE REPRIORITIZATION

Track at least:

### Retrieval

- recall@5 and recall@20;
- MRR;
- stale-result rate;
- required-source coverage;
- average context packet tokens;
- irrelevant-context ratio;
- query latency.

### Agent task success

- completed and verified rate;
- human correction rate;
- frontier escalation rate;
- repeated failure rate;
- average retries;
- task time;
- model tokens;
- GPU residency/swap cost.

### Learning

- number of validated failure records;
- prevention-trigger accuracy;
- procedures proposed;
- procedures promoted;
- procedure replay success;
- human interventions avoided;
- regressions after promotion.

### User value

- number of meaningful tasks completed without manual decomposition;
- management decisions requested from Nicholas;
- hours of unattended useful work;
- time from request to verifiable artifact;
- percentage of outputs presented through the unified access path.

---

# ADDENDUM A — SINGLE ACCESS POINT / FRONTIER-LIKE LOCAL INTERFACE

## A.1 Goal

The existing Widgets are useful but separate. The long-term user surface should be one local application resembling the interaction model of a frontier chat site while exposing the richer state of the Collective Agent.

The interface should not reimplement Module logic. It should orchestrate and render existing services.

## A.2 Primary chat surface

The central surface should support:

- persistent conversation threads;
- streaming responses;
- Markdown;
- code blocks;
- tables;
- images;
- audio/video;
- file and artifact cards;
- citations to local sources;
- progress and status;
- resumable tasks;
- user interruption;
- approvals;
- follow-up prompts;
- rendered errors and recovery options.

## A.3 Structured agent displays

Useful blocks include:

- current plan;
- active stage;
- agent/worker tree;
- selected skills;
- context packet summary;
- retrieved memory cards;
- failure warnings;
- tool calls;
- artifacts;
- tests and verifier results;
- approvals required;
- changes since last update;
- next proposed tasks.

These should be collapsible so the user sees the answer first and operational detail when desired.

## A.4 Unified navigation

Suggested areas:

- **Chat**
- **Projects**
- **Runs**
- **Tasks**
- **Artifacts**
- **Memory**
- **Procedures**
- **Failures**
- **Approvals**
- **Modules**
- **System**

## A.5 Existing Widget integration

The new interface should absorb or link the functions of:

- Local Agent Console;
- Module Launcher and Registry Browser;
- Verification Console;
- Fan-out Wave Dashboard.

Their tested driver cores should become backend services or reusable components. Do not discard them merely to create a new shell.

## A.6 Manager view

For game and project construction, provide:

- roadmap;
- backlog;
- dependency graph;
- active workers;
- blocked items;
- builds;
- screenshots/video;
- test status;
- risks;
- decisions awaiting Nicholas;
- next recommended priorities.

## A.7 Life-management view

Provide:

- upcoming obligations;
- reminders;
- pending replies;
- blocked tasks;
- recurring workflows;
- recommendations;
- explicit action approvals.

## A.8 Interface sequencing

1. Thin read-only chat over context compiler.
2. Render source and memory cards.
3. Render tool calls and artifacts.
4. Add approval blocks.
5. Add persistent projects and runs.
6. Integrate Verification Console.
7. Integrate Module Launcher.
8. Integrate fan-out and local orchestrator views.
9. Add domain dashboards.

Do not begin with a large visual redesign before the context compiler produces useful, inspectable packets.

---

# ADDENDUM B — DOCUMENT REVISION CHECKLIST FOR THE ORCHESTRATOR

## `PROJECT_DIRECTION.md`

Add:

- Cognitive virtual memory as the system model.
- Persistent external memory and disposable contexts.
- Nicholas-as-manager target.
- 2080 Ti apprentice-organization phase.
- RTX PRO 6000 local-technical-lead horizon.
- Procedure promotion and failure memory.
- Unified access-point objective.

## `CURRENT_STATE.md`

Replace active work with:

- direction reset;
- first memory/retrieval wave;
- current trusted model and hardware;
- frozen/deferred lanes;
- first acceptance gates.

## `MODULE_ROADMAP.md`

Pull forward:

- embedding adapter;
- artifact search;
- retrieval evaluation;
- repository intelligence;
- context compiler;
- episode/failure memory;
- skill/procedure registry;
- skill routing;
- read-only Collective Agent;
- sandbox coding worker;
- sequential orchestrator;
- domain vertical slices;
- unified interface.

Defer:

- nonblocking supervisor optimization;
- additional generators;
- model-heavy video interpretation;
- deep real-time perception;
- broad training.

## `ARCHITECTURE_MAP.md`

Add or clarify:

- memory plane;
- retrieval plane;
- context compiler;
- episode/failure/procedure stores;
- sandbox worker plane;
- unified user interface;
- hardware-independent model tiering.

## `FANOUT_ORCHESTRATOR_HANDOFF.md`

Replace the current candidate menu with:

- Wave 1 embedding adapter;
- artifact-search MVP;
- retrieval evaluation;
- optional memory-architecture frontier review.

Preserve current wave constraints and cross-module smoke rule.

## `DECISION_LOG.md` and index

Record:

- user-directed reprioritization;
- rationale;
- current-machine and horizon-machine distinction;
- frozen/deferred work;
- first wave;
- revisit conditions.

---

## 22. FINAL DECISION RULE

When choosing between candidate work, prefer the work that most increases the system’s ability to:

1. know what it already has;
2. retrieve only what matters;
3. recognize which skill or procedure applies;
4. remember relevant failures;
5. decompose a goal into bounded work;
6. execute in isolation;
7. verify independently;
8. preserve the result as reusable capability;
9. return only meaningful management decisions to Nicholas.

A new capability that cannot be found, selected, composed, verified, remembered, and surfaced through one access path is not yet part of the Collective Agent.

The 2080 Ti is sufficient to build this operating system of intelligence. The RTX PRO 6000 is the horizon upgrade that will make its executive model far more capable. Build the operating system now.
