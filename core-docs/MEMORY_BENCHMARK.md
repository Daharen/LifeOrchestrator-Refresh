# MEMORY_BENCHMARK -- the memory-quality + foreign-corpus validation architecture (governing)

Owns the **validation design** that supplies the evidence for every tier gate in `MEMORY_ARCHITECTURE.md`. It
specifies WHAT is measured, on WHICH corpora, HOW ground truth is established without an omniscient oracle, and
what the harness deliberately does NOT claim. It is the fitness function that lets the Collective Agent's memory
grow by evidence instead of by guesswork, and the mechanism that catches deterioration the sweep it begins.
Subordinate to `MEMORY_ARCHITECTURE.md`; the retrieval-metric field specs live in `MEMORY_CONTRACT.md` s6 +
`retrieval.eval` (#37), which this doc generalizes from top-k retrieval scoring into whole-lifecycle validation.

## 0. Purpose + honest scope

The harness exists to DETECT known + measurable regressions early, demonstrate headroom (bounded working-context
cost as the corpus grows), reveal architectural weakness, and give explicit evidence for when the next tier must
activate. It does NOT guarantee non-deterioration and must never be described as if it did (limitation, not
disclaimer -- `MEMORY_ARCHITECTURE.md` s11). A passing benchmark means "no measured regression on the tested
dimensions at the tested scale," nothing stronger.

## 1. Design principles (the rules that keep the benchmark honest)

- **No synthetic replica of this project.** The principal scale/adversarial test must NOT depend on building
  another Life-Orchestrator-like corpus, especially one 10-100x larger. No realistic equivalent exists in our
  native format; constructing one is circular (it tests whether the system can consume records already shaped
  like its own architecture) and prohibitively expensive. Useful real material beats meaningless synthetic bulk.
- **Foreign material is the test.** The canonical formats are internal products; the benchmark feeds material
  that was never designed for our schemas and checks whether the system builds its own view (intake, section 3).
- **Self-verifying ground truth.** Use corpora with objective or partly-objective ground truth so neither
  Nicholas nor a frontier model must hold a complete superior understanding of every corpus. Keep a private
  reference copy; let the system ingest another copy; independently withhold / remove / corrupt / substitute /
  reorder selected components; verify against reality (compilation, tests, schemas, known behavior).
- **Harness independence from the tested agent.** The agent may PROPOSE cases, likely failure points, and useful
  questions, but must NOT control final case selection, what is withheld/mutated, the mutation manifest, hidden
  answers, hidden tests, or final scoring. A separate deterministic harness owns those. Selection uses
  randomization + dependency-informed sampling so the system cannot optimize to a fixed benchmark.
- **Frontier models assist, they are not the oracle.** They may design difficult qualitative cases, review
  disputed interpretations, produce additional hidden tests, and judge summaries lacking mechanical ground truth.
  They are NOT expected to absorb an entire corpus independently -- the whole point of this system is a memory
  more persistent + structurally sophisticated than a frontier model's temporary context.
- **Functional equivalence over textual identity.** Where multiple valid reconstructions exist, score functional
  equivalence (compiles, passes tests, satisfies the schema/API), not string match. Where evidence is
  insufficient, correct ABSTENTION scores better than invention.

## 2. Corpus selection -- separated benchmark dimensions

Do not conflate scale with abstraction. Different corpora stress different capabilities; pick per dimension:

- **Storage + retrieval scale** -- large, relatively CLEAN foreign corpora (e.g. a big well-structured OSS
  monorepo + its docs). Tests bounded context cost + retrieval recall/latency as size grows.
- **Abstraction + memory formation** -- smaller but DISORGANIZED foreign corpora (informal notes, mixed docs,
  inconsistent terminology). Tests entity/type/boundary discovery + synopsis quality.
- **Truth maintenance** -- REVISION-HEAVY corpora (long git histories, superseding decisions, changelogs). Tests
  currentness / supersession / contradiction handling.
- **Namespace isolation** -- MIXED corpora (several unrelated projects interleaved). Tests cross-project
  contamination.
- **Continued learning** -- INCREMENTALLY UPDATED corpora (later commits/versions applied after initial ingest).
  Tests learning without global rebuild or stale-state confusion.
- **Causal diagnosis + reconstruction** -- SELECTIVELY DAMAGED corpora (components withheld/broken). Tests
  prediction of failure, dependency identification, and functional reconstruction.

**Corpus criteria:** real + useful; objective or partly-objective ground truth (builds, tests, schemas, known
dependency behavior, recorded bug/fix history); a permissive licence compatible with local ingestion; a size
band appropriate to the dimension; available offline on F: (the corpora are gitignored large data, per D-0015/28).

Controlled adversarial transformations are applied to REAL corpora rather than fabricating fake ones: remove
indexes, flatten structure, mix projects, insert stale versions, duplicate files, introduce contradictions,
remove cross-references, add later updates. The transformation is deterministic + recorded in a mutation manifest
the agent cannot see.

## 3. The lifecycle under test (eight stages)

The plan measures the whole memory lifecycle, not top-k retrieval or plausible-sounding answers:

1. **Discovery** -- identify corpus boundaries, projects, file types, entities, chronology, versions, duplicates,
   likely relationships from raw foreign material.
2. **Normalization** -- convert heterogeneous inputs into canonical records while PRESERVING the originals.
3. **Organization** -- form namespaces, bounded hierarchies, indexes, graph relationships, temporal chains.
4. **Consolidation** -- derive stable claims, synopses, failure patterns, procedures, and current doctrine from
   repeated/evolving evidence.
5. **Navigation** -- serve exact lookup, current-state questions, historical reconstruction, causal diagnosis,
   procedure selection, cross-document synthesis, global overview, and abstention.
6. **Reconstruction** -- every substantive derived memory expands through intermediate records back to correct
   original source evidence.
7. **Continued learning** -- absorb later corrections, reversals, new versions, and additional projects without
   global rebuild, stale-state confusion, or uncontrolled context growth.
8. **Functional reconstruction** -- restore selected missing modules/schemas/docs/relationships and pass external
   verification.

## 4. Ground-truth + evaluation mechanisms

Establish truth mechanically wherever possible; reserve model judgement for the genuinely qualitative:

- **compilation + execution** of reconstructed/affected code;
- **existing tests** in the corpus;
- **independently generated HIDDEN tests** (held out from the agent; may be frontier-assisted);
- **API + schema compatibility** checks;
- **known dependency behavior**;
- **historical bug/fix behavior** (does the system predict the recorded failure?);
- **deterministic outputs** (byte/functional equivalence of reconstructions);
- **source reconstruction** (does the derived view expand to the withheld original?);
- **currentness accuracy** (current vs historical labelled correctly against the known timeline);
- **cross-project contamination rate** (records/answers leaking across the mixed-corpus boundary);
- **correct abstention** (insufficient-evidence cases scored right for saying so).

The private reference copy + the mutation manifest are the answer key; the harness compares the agent's outputs
against them deterministically. For multi-valid cases, functional-equivalence checks replace textual match.

## 5. Query classes exercised (navigation)

Each maps to a retrieval path (`MEMORY_ARCHITECTURE.md` s5) and must be scored separately -- aggregate uplift
must not hide an exact-string or safety-query failure:

- exact reference / ID lookup;
- current-state ("what governs X now?");
- historical reconstruction ("how did that rule arise?");
- temporal change ("what changed between versions/dates?");
- local factual;
- global synthesis / dominant-themes overview;
- causal explanation / failure diagnosis ("why did component Y break?");
- procedure selection ("how do we accomplish Z here?");
- precedent search;
- deliberately-unanswerable (evidence withheld -> must abstain).

## 6. Metrics (measured at minimum, per dimension + per scale point)

- ingestion coverage;
- provenance fidelity (derived -> source expansion correctness);
- retrieval recall + precision (per query class + per stage: raw retrieval / post-filter / packet);
- currentness + temporal correctness;
- contradiction handling;
- cross-project isolation;
- abstention correctness (invention penalized; correct abstention rewarded);
- reconstruction success (functional-equivalence);
- context cost (tokens in the compiled packet -- MUST stay bounded as corpus grows);
- retrieval latency (fast path) + slow-path cost when triggered;
- incremental update cost (work per new record: target ~one leaf + bounded ancestry + secondary indexes);
- hierarchy splitting behavior (fanout respected; depth grows, hot surface does not);
- procedural fidelity (promoted procedures verified externally);
- performance as corpus SIZE and HETEROGENEITY increase (the headroom curves).

The signature "headroom" evidence is a curve: context cost + routine-query latency roughly FLAT while corpus size
climbs across orders of magnitude, with global-query cost rising only on the explicit slow path.

## 7. Harness architecture + independence

- **Reference store (sealed):** the private pristine copy of each corpus + the mutation manifest + hidden
  tests/answers. Owned by the harness; never exposed to the agent.
- **Ingest copy:** the (possibly mutated) copy the system ingests.
- **Mutator (deterministic):** applies the recorded transformations with a seeded, dependency-informed sampler;
  emits the manifest. Randomization prevents fixed-benchmark optimization; dependency-awareness ensures damage
  lands where it exercises reconstruction/diagnosis.
- **Scorer (deterministic):** runs compilation/tests/schema/equivalence checks + compares against the reference;
  computes the section-6 metrics. Mechanical where possible.
- **Qualitative panel (optional, frontier-assisted):** judges only summaries/interpretations lacking mechanical
  ground truth, and produces additional hidden tests; never the sole scorer, never fed the whole corpus as an
  oracle.
- **Agent boundary:** the tested Collective Agent may propose cases/questions/failure points into a queue the
  harness may or may not use; it has no read access to the reference store, manifest, hidden tests, or scoring.

## 8. Relationship to `retrieval.eval` (#37) and the build order

`retrieval.eval` #37 (recall@K / MRR / nDCG / stale / provenance / per-stage / packet-disposition, eval-0.3) is
the SEED: it already scores retrieval + packet quality deterministically on a fixture + real slice. This doc
generalizes it into whole-lifecycle validation over foreign corpora. Build order tracks the tiers: a v1 harness
(Tier 1) covers discovery/normalization/organization/navigation + the bounded-context-cost + isolation +
currentness curves on 2-3 corpora; Tier 2 adds consolidation/procedural/continued-learning measures; Tier 3 adds
the large-scale + global-traversal curves. The harness is itself deterministic infrastructure and is validated
like any other module (off-machine gate -> `-Live` -> dev.ship), with the corpora as gitignored F: large data.
