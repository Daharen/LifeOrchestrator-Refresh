#!/usr/bin/env python3
# classifier_policy.py -- the ONE VERSIONED query_class -> temporal_intent map + resolver (Life Orchestrator
# module 37 `retrieval.eval`; MEMORY_CONTRACT Amendment A5 [D-0096] U5'; CONTEXT_PACKET_CONTRACT i33
# amendment U5'). PURE + DETERMINISTIC: no model, no I/O, no network, no wall-clock, no randomness, no state.
#
# WHY (A5 U5', red-team pack 159e9cb5 change 5). `query_class` (SEMANTIC -- what KIND of question) and
# `temporal_intent` (TEMPORAL -- which version(s) are wanted) are INDEPENDENT dimensions. The i32 stub over-froze
# the class->mode identity (it baked temporal into the class and omitted policy/version fields). i33 splits them:
#   * the class -> temporal_intent map is a DEFAULT that an EXPLICIT user time/version OUTRANKS;
#   * the classifier + the map are VERSIONED (`classifier_policy_id` / `classifier_policy_version`) so packet
#     identity (CONTEXT_PACKET_CONTRACT s6) can pin them;
#   * `composite` (mixed/temporally-ambiguous intent) + `unclassified` (no class) are first-class FALLBACK
#     classes so a composite/ambiguous task is not forced into a single wrong temporal mode.
#
# OWNERSHIP. This module owns the class -> temporal_intent MAP + the explicit-override RESOLVER. #40's compiler
# front owns the task_type -> query_class STAGE (it produces the `query_class`; it IMPORTS this map to resolve
# the temporal_intent). selpol (`selpol_rrf_v1`) imports this to resolve its temporal MODE. The 4-value
# `temporal_intent` here is the CONTRACT dimension (MEMORY_CONTRACT s6) -- distinct from selpol's INTERNAL action
# modes (which also include the back-compat soft `prefer_current`).

CLASSIFIER_POLICY_ID = "clsmap_v1"
CLASSIFIER_POLICY_VERSION = "1.0.0"

# The contract temporal_intent enum (MEMORY_CONTRACT s6).
TEMPORAL_INTENTS = frozenset(["current_only", "historical_as_of", "version_specific", "any_valid_version"])

# query_class (MEMORY_ARCHITECTURE s5 planner / CONTEXT_PACKET_CONTRACT s0 i32 map) -> DEFAULT temporal_intent.
# Rationale (SCHEMA_NOTES s15): ONLY a class that inherently asks "what is true NOW" or "which healthy procedure
# NOW" defaults to `current_only` (a HARD exclude of non-current). `exact_reference` wants a SPECIFIC referenced
# record -> `version_specific`. `historical_reconstruction` reads the past -> `historical_as_of`. Every other
# class -- and the `composite`/`unclassified` fallbacks -- defaults to `any_valid_version` (stale ALLOWED), so
# the temporal dimension (which is NOT a security boundary; namespace is) never silently drops a valid record.
# This is the red-team's caution against over-freezing `current_only` as the universal mode: current_only applies
# ONLY after temporal intent resolves to it.
CLASS_TO_TEMPORAL_INTENT = {
    "current_state":             "current_only",
    "procedure_selection":       "current_only",
    "exact_reference":           "version_specific",
    "historical_reconstruction": "historical_as_of",
    "temporal_change":           "any_valid_version",
    "local_factual":             "any_valid_version",
    "global_synthesis":          "any_valid_version",
    "causal_diagnosis":          "any_valid_version",
    "precedent_search":          "any_valid_version",
    # fallback classes (U5')
    "composite":                 "any_valid_version",
    "unclassified":              "any_valid_version",
}
KNOWN_QUERY_CLASSES = frozenset(CLASS_TO_TEMPORAL_INTENT.keys())
DEFAULT_QUERY_CLASS = "unclassified"


def class_to_temporal_intent(query_class):
    """The versioned DEFAULT map: a known `query_class` -> its default temporal_intent; an unknown/absent class
    -> the `unclassified` default (`any_valid_version`). Pure + deterministic."""
    if isinstance(query_class, str) and query_class in CLASS_TO_TEMPORAL_INTENT:
        return CLASS_TO_TEMPORAL_INTENT[query_class]
    return CLASS_TO_TEMPORAL_INTENT[DEFAULT_QUERY_CLASS]


def resolve_temporal_intent(query_class=None, explicit_temporal_intent=None, explicit_version=False):
    """Resolve the effective temporal_intent, treating `query_class` and `temporal_intent` as INDEPENDENT
    dimensions (U5'). Precedence, highest first:
      (1) an EXPLICIT user `temporal_intent` (one of the 4-value enum) -- OUTRANKS the class default;
      (2) an explicit version/as-of request (`explicit_version` truthy) -> `version_specific`;
      (3) the class-default map (`class_to_temporal_intent`).
    Returns `(temporal_intent, source)` where `source` names the winning rule (for diagnostics / packet
    identity). Pure + deterministic."""
    if isinstance(explicit_temporal_intent, str) and explicit_temporal_intent in TEMPORAL_INTENTS:
        return explicit_temporal_intent, "explicit_temporal_intent"
    if explicit_version:
        return "version_specific", "explicit_version"
    resolved_class = query_class if (isinstance(query_class, str) and query_class in CLASS_TO_TEMPORAL_INTENT) else DEFAULT_QUERY_CLASS
    return CLASS_TO_TEMPORAL_INTENT[resolved_class], "class_default:" + resolved_class


def policy_stamp():
    """The versioned classifier policy id/version (for packet identity / eval reports). Pure."""
    return {"classifier_policy_id": CLASSIFIER_POLICY_ID,
            "classifier_policy_version": CLASSIFIER_POLICY_VERSION}
