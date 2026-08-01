#!/usr/bin/env python3
# episode_record.py -- deterministic core of the EPISODE + FAILURE memory recorder (Life Orchestrator
# module 39 `episode.record`, contract v0.2, Wave 2 PRODUCER lane, plan fo-27-bab47060, D-0077/D-0083).
#
# WHAT THIS IS
#   The PRODUCER half of the Wave-2 episode/failure split. It DEFINES the EPISODE and FAILURE record
#   schemas as MEMORY_CONTRACT s1 record+provenance ENVELOPES (v0.1) and ships a DETERMINISTIC RECORDER
#   that turns a run TRACE into a COMPLETE `episode` record (+ `episode_stage` children) -- EVEN when the
#   run FAILED -- plus a deterministic FAILURE-SIGNATURE retrieval SEAM. No model, no network, CPU-only.
#
#   Ops (request.op):
#     record          trace -> { episode, episode_stages[], optional candidate failure } as s1 records,
#                     an ingest_records bundle, and an s1 validation report. A FAILED/TRUNCATED trace
#                     still yields a COMPLETE episode (open stages are closed, final_status=failed).
#     build-failure   failure descriptor(s) -> curated `failure` s1 record(s) (deterministic id +
#                     failure_signature + match_keys). Used to author the fixture failure corpus.
#     search-failures task-context descriptor + a failure corpus -> ranked matching failures (the SEAM a
#                     later retriever/reranker consumes). Unrelated failures (zero overlap) NEVER surface.
#     validate        s1 record(s) -> a validation report (envelope fields, id well-formedness, and
#                     PROVENANCE VALIDITY: content_hash recomputed from canonical content must match).
#
# DETERMINISM DISCIPLINE (a re-run -- same trace/descriptor -- is byte-identical, cross-machine):
#   * Every emitted field is a pure function of the FIXED input (trace/descriptor) + the recorder's own
#     fingerprints. NO wall-clock, NO uuid, NO absolute paths, NO insertion order feed any id/hash.
#     (Timestamps that appear in a record come from the trace input, which is fixed -- never from now().)
#   * ids are content+path derived (sha256, first 24 hex, kind-prefixed) -- mirrors artifact.search #36.
#   * canonical JSON: sort_keys, ensure_ascii, compact separators, one trailing LF, UTF-8 no BOM.
#   * INTEGER-ONLY canonical output: confidence is confidence_ppm (int); every numeric body value is
#     coerced to int (round-half-up) so no float repr can diverge across platforms.
#   * a records_digest (sha256 over sorted per-record lines) is the cross-env identity pin (the .json
#     artifacts are already byte-canonical; the digest is the single comparable number, like #36).
#
# INVOCATION (by the pwsh entrypoint; also runnable directly):
#   python3 episode_record.py --request <request.json>
#   Writes out_dir/{<artifacts>, worker-summary.json}; prints "OK <out_dir>" (0) or "ERR <json>" (1).
#   All logging goes to stderr and is BOUNDED (never replicates a whole record/snippet -- MEMORY_CONTRACT s7).

import sys
import os
import re
import json
import hashlib
import argparse

GENERATOR_NAME = "episode.record"
GENERATOR_VERSION = "0.1.0"
RECORD_ENVELOPE_SCHEMA = "lifeorch.memory_record/0.1"   # the MEMORY_CONTRACT s1 envelope id
EPISODE_BODY_SCHEMA = "lifeorch.episode/0.1"            # directive 10.1
EPISODE_STAGE_BODY_SCHEMA = "lifeorch.episode_stage/0.1"
FAILURE_BODY_SCHEMA = "lifeorch.failure/0.1"            # directive 5.4 / 10.2
TRACE_SCHEMA = "lifeorch.run_trace/0.1"                 # the recorder's INPUT schema
TASK_CONTEXT_SCHEMA = "lifeorch.task_context/0.1"       # the failure-retrieval query shape
INGEST_REQUEST_SCHEMA = "lifeorch.ingest_records_request/0.1"  # FIXTURE #36 0.2 sink (reconciled at fold)
SCHEMA_VERSION = "1"

# derivation fingerprints (carried into every record's provenance; a change -> new content_hash -> new
# record_version_id -> derivation_stale, exactly per MEMORY_CONTRACT s4/s5).
PARSER_FINGERPRINT = "episode.trace_parser/1"           # parses the run_trace input
EXTRACTOR_FINGERPRINT = "episode.recorder/0.1.0"        # the recorder itself (the extractor)
CHUNKER_FINGERPRINT = None                              # episodes/failures are NOT chunked

# Default privacy label (MEMORY_CONTRACT s7). An episode may reference personal/task data; the field is
# ALWAYS present. Egress stays OUT (this producer never sends anything anywhere) and snippet fields are
# bounded so a record does not replicate a whole source blob.
DEFAULT_SENSITIVITY = "project_internal"
SNIPPET_BOUND = 2000  # max chars kept for any free-text symptom/evidence/summary field

_TOKEN_RE = re.compile(r"[a-z0-9]+")
_ID_RE = re.compile(r"^[a-z]+_[0-9a-f]{24}$")
_HEXCH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

RECORD_KINDS = ("episode", "episode_stage", "failure")
ENVELOPE_FIELDS = (
    "schema", "record_id", "record_version_id", "record_kind", "body_schema", "namespace",
    "content_hash", "status", "authority_level", "sensitivity_class", "valid_from", "valid_to",
    "created_by_ingest_run", "source_version_id", "source_span", "derivation_refs",
    "parser_fingerprint", "chunker_fingerprint", "extractor_fingerprint", "schema_version",
    "token_count", "embedding_space_id", "parent_edges", "child_edges", "body",
)

STOPWORDS = frozenset([
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "had", "has", "have", "in",
    "into", "is", "it", "its", "of", "on", "or", "the", "then", "to", "with", "was", "when", "while",
    "a.k.a", "via", "per", "no", "not",
])

# Generic operation verbs/glue removed from the OPERATIONS facet only: they carry no discriminating
# signal ("run", "execute", ...) and would otherwise create spurious cross-failure operation matches.
OP_STOPWORDS = frozenset([
    "run", "execute", "use", "do", "make", "get", "call", "invoke", "perform", "that", "across",
    "contains", "non", "across", "then",
])


def log(msg):
    # BOUNDED diagnostic logging (MEMORY_CONTRACT s7): never dump a whole record or snippet to stderr.
    s = str(msg)
    if len(s) > 300:
        s = s[:300] + "...[+%d]" % (len(s) - 300)
    sys.stderr.write("[episode.record] " + s + "\n")


# ------------------------------------------------------------------ determinism helpers

def canon_bytes(obj):
    """Canonical JSON bytes: sorted keys, compact, ensure_ascii, one trailing LF, UTF-8 no BOM."""
    s = json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    return (s + "\n").encode("utf-8")


def canon_str(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def sha256_hex(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return hashlib.sha256(b).hexdigest()


def id24(*parts):
    """First 24 hex of sha256 over NUL-joined parts -- the artifact.search #36 id convention."""
    return sha256_hex("\0".join(str(p) for p in parts).encode("utf-8"))[:24]


def normalized_text(raw_bytes):
    """Decode UTF-8, strip a leading BOM, normalize CRLF/CR -> LF."""
    t = raw_bytes.decode("utf-8")
    if t and t[0] == "﻿":
        t = t[1:]
    return t.replace("\r\n", "\n").replace("\r", "\n")


def content_hash_of(obj):
    """sha256:<hex> over the canonical bytes of a (already integer-only) object."""
    return "sha256:" + sha256_hex(canon_bytes(obj))


def bounded(s):
    """Bound a free-text field so a record never replicates a whole blob (MEMORY_CONTRACT s7)."""
    if s is None:
        return None
    s = str(s)
    if len(s) <= SNIPPET_BOUND:
        return s
    return s[:SNIPPET_BOUND] + "...[+%d chars]" % (len(s) - SNIPPET_BOUND)


def token_estimate(obj):
    """Deterministic whitespace-token estimate over the canonical text of a body."""
    return len(canon_str(obj).split())


def _round_half_up(x):
    # round-half-up on a non-negative-or-negative float, deterministic
    if x >= 0:
        return int(x + 0.5)
    return -int(-x + 0.5)


def intify(obj):
    """Recursively coerce every float to an int (round-half-up) so canonical output is INTEGER-ONLY
    (no float repr can diverge across platforms). bools are left as-is; ints untouched."""
    if isinstance(obj, bool):
        return obj
    if isinstance(obj, float):
        return _round_half_up(obj)
    if isinstance(obj, dict):
        return {k: intify(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [intify(v) for v in obj]
    return obj


def tokens(text):
    return [t for t in _TOKEN_RE.findall(str(text).lower()) if t not in STOPWORDS and len(t) > 1]


def op_tokens(text):
    """Operation-facet tokens: content tokens minus generic operation verbs (see OP_STOPWORDS)."""
    return [t for t in tokens(text) if t not in OP_STOPWORDS]


def sorted_unique(seq):
    return sorted(set(x for x in seq if x))


def norm_ext(e):
    e = str(e).strip().lower()
    if not e:
        return None
    if not e.startswith("."):
        e = "." + e
    return e


def norm_component(c):
    """Component/skill identity tokens: keep the whole dotted id AND its split tokens."""
    c = str(c).strip().lower()
    out = []
    if c:
        out.append(c)
        out.extend(_TOKEN_RE.findall(c))
    return sorted_unique(out)


# ------------------------------------------------------------------ input loading

def load_json_input(value, base_dir, what):
    """value is either an inline object/list or a path (abs, or relative to base_dir)."""
    if isinstance(value, (dict, list)):
        return value
    if isinstance(value, str):
        path = value if os.path.isabs(value) else os.path.join(base_dir or os.getcwd(), value)
        if not os.path.isfile(path):
            raise ValueError("%s file not found: %s" % (what, value))
        with open(path, "rb") as fh:
            return json.loads(normalized_text(fh.read()))
    raise ValueError("%s must be a path or an inline object" % what)


# ------------------------------------------------------------------ s1 envelope construction

def build_envelope(record_kind, record_id, version_prefix, namespace, body, body_schema,
                   source_version_id, derivation_refs, authority_level, sensitivity_class,
                   valid_from, valid_to, parent_edges, child_edges, source_span=None):
    """Assemble a MEMORY_CONTRACT s1 record+provenance envelope. Every derived id/hash is deterministic.
    content_hash is computed over the IMMUTABLE canonical content (body + kind + namespace + provenance
    fingerprints + source refs) -- NOT over the logical record_id or volatile fields -- so a change in
    the run's content OR the recorder version yields a new content_hash -> a new record_version_id."""
    body = intify(body)
    canonical_content = {
        "record_kind": record_kind,
        "body_schema": body_schema,
        "namespace": namespace,
        "body": body,
        "source_version_id": source_version_id,
        "source_span": source_span,
        "derivation_refs": derivation_refs,
        "parent_edges": parent_edges,
        "child_edges": child_edges,
        "parser_fingerprint": PARSER_FINGERPRINT,
        "chunker_fingerprint": CHUNKER_FINGERPRINT,
        "extractor_fingerprint": EXTRACTOR_FINGERPRINT,
        "schema_version": SCHEMA_VERSION,
    }
    content_hash = content_hash_of(canonical_content)
    record_version_id = version_prefix + "_" + id24(record_id, content_hash)
    created_by_ingest_run = "recrun_" + id24(source_version_id, EXTRACTOR_FINGERPRINT)
    env = {
        "schema": RECORD_ENVELOPE_SCHEMA,
        "record_id": record_id,
        "record_version_id": record_version_id,
        "record_kind": record_kind,
        "body_schema": body_schema,
        "namespace": namespace,
        "content_hash": content_hash,
        # status/currentness = the s5 taxonomy, NOT a single boolean. Fresh record -> current, no stale
        # reasons; verified is set true here and INDEPENDENTLY recomputed by the validator (op validate).
        "status": {"state": "current", "stale_reasons": [], "verified": True},
        "authority_level": authority_level,
        "sensitivity_class": sensitivity_class,
        "valid_from": valid_from,
        "valid_to": valid_to,
        "created_by_ingest_run": created_by_ingest_run,
        "source_version_id": source_version_id,
        "source_span": source_span,
        "derivation_refs": derivation_refs,
        "parser_fingerprint": PARSER_FINGERPRINT,
        "chunker_fingerprint": CHUNKER_FINGERPRINT,
        "extractor_fingerprint": EXTRACTOR_FINGERPRINT,
        "schema_version": SCHEMA_VERSION,
        "token_count": token_estimate(body),
        "embedding_space_id": None,   # nullable until embedded; this producer never embeds
        "parent_edges": parent_edges,
        "child_edges": child_edges,
        "body": body,
    }
    return env


def recompute_content_hash(env):
    """Recompute content_hash from an envelope's canonical content -- provenance VALIDATION (s6)."""
    canonical_content = {
        "record_kind": env.get("record_kind"),
        "body_schema": env.get("body_schema"),
        "namespace": env.get("namespace"),
        "body": env.get("body"),
        "source_version_id": env.get("source_version_id"),
        "source_span": env.get("source_span"),
        "derivation_refs": env.get("derivation_refs"),
        "parent_edges": env.get("parent_edges"),
        "child_edges": env.get("child_edges"),
        "parser_fingerprint": env.get("parser_fingerprint"),
        "chunker_fingerprint": env.get("chunker_fingerprint"),
        "extractor_fingerprint": env.get("extractor_fingerprint"),
        "schema_version": env.get("schema_version"),
    }
    return content_hash_of(intify(canonical_content))


# ------------------------------------------------------------------ trace -> episode + stages (RECORDER)

def trace_version_id(trace):
    """A deterministic immutable id of the trace INPUT (the source this record derives from)."""
    tid = str(trace.get("trace_id") or trace.get("task_id") or "trace")
    thash = "sha256:" + sha256_hex(canon_bytes(intify(trace)))
    return "tracever_" + id24(tid, thash), thash


def _event_stage_groups(events):
    """Group ordered events into stages. ROBUST to a FAILED/TRUNCATED trace: an open stage with no
    matching stage_end is closed anyway (status inferred), and a trace with NO stage markers gets one
    synthetic 'run' stage. Returns a list of dicts {name, role, event_indices[], had_error, closed}."""
    groups = []
    cur = None

    def open_stage(name, role, idx):
        return {"name": name or "stage", "role": role, "event_indices": [idx], "had_error": False,
                "closed": False, "explicit_status": None, "duration_ms": None}

    any_marker = any(e.get("type") in ("stage_start", "stage_end") for e in events)
    if not any_marker:
        # synthesize a single stage covering all events
        g = {"name": "run", "role": None, "event_indices": list(range(len(events))),
             "had_error": any(e.get("type") == "error" for e in events), "closed": True,
             "explicit_status": None, "duration_ms": None}
        return [g]

    for idx, e in enumerate(events):
        et = e.get("type")
        if et == "stage_start":
            if cur is not None and not cur["closed"]:
                cur["closed"] = True  # implicit close (no stage_end) -> inferred status later
                groups.append(cur)
            cur = open_stage(e.get("stage"), e.get("role"), idx)
        elif et == "stage_end":
            if cur is None:
                cur = open_stage(e.get("stage"), e.get("role"), idx)
            cur["event_indices"].append(idx)
            cur["closed"] = True
            cur["explicit_status"] = e.get("status")
            if e.get("duration_ms") is not None:
                cur["duration_ms"] = e.get("duration_ms")
            groups.append(cur)
            cur = None
        else:
            if cur is None:
                cur = open_stage(e.get("stage"), e.get("role"), idx)
            cur["event_indices"].append(idx)
            if et == "error":
                cur["had_error"] = True
    if cur is not None:
        # a still-open stage at end of a truncated/failed trace -> close it, inferred status
        cur["closed"] = True
        groups.append(cur)
    return groups


def _collect_from_events(events, indices):
    """Pull the typed sub-records out of a set of event indices (bounded free text)."""
    tool_invocations, state_changes, test_results = [], [], []
    reviewer_outcomes, human_interventions, errors, notes = [], [], [], []
    models = []
    for i in indices:
        e = events[i]
        et = e.get("type")
        if et == "tool_invocation":
            tool_invocations.append({
                "seq": e.get("seq", i),
                "skill_id": e.get("skill_id"),
                "op": e.get("op"),
                "status": e.get("status"),
                "args_digest": e.get("args_digest"),
                "artifact_refs": e.get("artifact_refs") or [],
                "duration_ms": e.get("duration_ms"),
            })
            if e.get("model_id"):
                models.append({"model_id": e.get("model_id"), "version": e.get("model_version"),
                               "engine_build": e.get("engine_build")})
        elif et == "state_change":
            state_changes.append({
                "seq": e.get("seq", i),
                "target": e.get("target"),
                "kind": e.get("kind"),
                "before": bounded(e.get("before")),
                "after": bounded(e.get("after")),
                "reversible": e.get("reversible"),
            })
        elif et == "test_result":
            test_results.append({
                "seq": e.get("seq", i),
                "suite": e.get("suite"),
                "passed": e.get("passed"),
                "failed": e.get("failed"),
                "total": e.get("total"),
                "status": e.get("status"),
            })
        elif et == "reviewer_outcome":
            reviewer_outcomes.append({
                "seq": e.get("seq", i),
                "reviewer": e.get("reviewer"),
                "verdict": e.get("verdict"),
                "note": bounded(e.get("note")),
            })
        elif et == "human_intervention":
            human_interventions.append({
                "seq": e.get("seq", i),
                "kind": e.get("kind"),
                "note": bounded(e.get("note")),
            })
        elif et == "error":
            errors.append({
                "seq": e.get("seq", i),
                "code": e.get("code"),
                "message": bounded(e.get("message")),
                "stage": e.get("stage"),
            })
        elif et == "note":
            notes.append({"seq": e.get("seq", i), "text": bounded(e.get("text"))})
        elif et == "model":
            models.append({"model_id": e.get("model_id"), "version": e.get("model_version"),
                           "engine_build": e.get("engine_build")})
    return {
        "tool_invocations": tool_invocations, "state_changes": state_changes,
        "test_results": test_results, "reviewer_outcomes": reviewer_outcomes,
        "human_interventions": human_interventions, "errors": errors, "notes": notes,
        "models": models,
    }


def _stage_status(group, coll, trace_failed):
    if group["explicit_status"]:
        return group["explicit_status"]
    if group["had_error"] or coll["errors"]:
        return "failed"
    if trace_failed:
        # a still-open stage in a failed/truncated trace is incomplete
        return "incomplete"
    return "ok"


def record_trace(trace, namespace, emit_failure_default=True):
    """The RECORDER: a run trace -> a COMPLETE episode record (+ episode_stage children) + an optional
    candidate failure record. Works even when the trace FAILED or is truncated."""
    if not isinstance(trace, dict):
        raise ValueError("trace must be an object")
    events = trace.get("events") or []
    if not isinstance(events, list):
        raise ValueError("trace.events must be a list")
    events = sorted(events, key=lambda e: (e.get("seq", 0), events.index(e)))

    task_id = str(trace.get("task_id") or "task")
    parent_project = trace.get("parent_project")
    ns = namespace or parent_project or "default"
    attempt = int(trace.get("attempt", 1))

    src_version_id, trace_hash = trace_version_id(trace)
    trace_id = str(trace.get("trace_id") or task_id)

    declared_status = trace.get("final_status")
    any_error = any(e.get("type") == "error" for e in events)
    final_status = declared_status or ("failed" if any_error else "ok")
    trace_failed = final_status in ("failed", "error", "escalated", "cancelled")

    # ---- stages ----
    groups = _event_stage_groups(events)
    episode_record_id = "ep_" + id24(ns, task_id, attempt)

    stage_records = []
    stage_refs = []            # ordered lightweight refs kept in the episode body
    episode_child_edges = []
    agg = {"tool_invocations": [], "state_changes": [], "test_results": [],
           "reviewer_outcomes": [], "human_interventions": [], "errors": [], "models": []}

    for si, group in enumerate(groups):
        coll = _collect_from_events(events, group["event_indices"])
        st_status = _stage_status(group, coll, trace_failed)
        ev_range = [min(group["event_indices"]), max(group["event_indices"]) + 1] if group["event_indices"] else [0, 0]
        stage_name = group["name"]
        stage_body = {
            "stage_index": si,
            "stage_name": stage_name,
            "role": group["role"],
            "status": st_status,
            "closed_explicitly": group["explicit_status"] is not None,
            "duration_ms": group["duration_ms"],
            "tool_invocations": coll["tool_invocations"],
            "state_changes": coll["state_changes"],
            "test_results": coll["test_results"],
            "reviewer_outcomes": coll["reviewer_outcomes"],
            "human_interventions": coll["human_interventions"],
            "errors": coll["errors"],
            "notes": coll["notes"],
            "model_provenance": coll["models"],
        }
        stage_record_id = "eps_" + id24(episode_record_id, si, stage_name)
        stage_parent_edges = [{"edge_kind": "stage_of", "parent_record_id": episode_record_id, "ordinal": si}]
        stage_deriv = [{"ref_kind": "run_trace", "trace_id": trace_id,
                        "trace_content_hash": trace_hash, "event_range": ev_range}]
        stage_env = build_envelope(
            "episode_stage", stage_record_id, "epsv", ns, stage_body, EPISODE_STAGE_BODY_SCHEMA,
            src_version_id, stage_deriv, "observed", DEFAULT_SENSITIVITY,
            trace.get("started_at"), trace.get("finished_at"), stage_parent_edges, [])
        stage_records.append(stage_env)
        stage_refs.append({"ordinal": si, "stage_name": stage_name, "status": st_status,
                           "record_id": stage_record_id})
        episode_child_edges.append({"edge_kind": "has_stage", "child_record_id": stage_record_id, "ordinal": si})
        for key in ("tool_invocations", "state_changes", "test_results", "reviewer_outcomes",
                    "human_interventions", "errors", "models"):
            agg[key].extend(coll[key])

    # de-dup aggregated models deterministically
    seen_m = set()
    models = []
    for m in agg["models"]:
        key = canon_str(m)
        if key not in seen_m:
            seen_m.add(key)
            models.append(m)

    # ---- failure/escalation reasons (always populated coherently, esp. on failure) ----
    escalation_reasons = list(trace.get("escalation_reasons") or [])
    failure_reasons = []
    for er in agg["errors"]:
        msg = er.get("message") or er.get("code") or "error"
        failure_reasons.append(bounded(msg))
    tf = trace.get("failure")
    if tf and tf.get("observable_symptoms"):
        failure_reasons.append(bounded(tf.get("observable_symptoms")))

    engines = sorted_unique([m.get("engine_build") for m in models if m.get("engine_build")])

    episode_body = {
        "task_id": task_id,
        "parent_project": parent_project,
        "original_request": bounded(trace.get("original_request")),
        "context_packet_id": trace.get("context_packet_id"),
        "attempt": attempt,
        "plan": trace.get("plan") or [],
        "stage_sequence": stage_refs,
        "model_provenance": models,
        "engine_provenance": engines,
        "tool_invocations": agg["tool_invocations"],
        "state_changes": agg["state_changes"],
        "artifacts": trace.get("artifacts") or [],
        "test_results": agg["test_results"],
        "reviewer_outcomes": agg["reviewer_outcomes"],
        "human_interventions": agg["human_interventions"],
        "final_status": final_status,
        "metrics": trace.get("metrics") or {},
        "escalation_reasons": escalation_reasons,
        "failure_reasons": failure_reasons,
        "stage_count": len(stage_records),
        "complete": True,   # the recorder ALWAYS emits a complete episode, even from a failed trace
    }
    episode_deriv = [{"ref_kind": "run_trace", "trace_id": trace_id,
                      "trace_content_hash": trace_hash,
                      "event_range": [0, len(events)]}]
    episode_env = build_envelope(
        "episode", episode_record_id, "epv", ns, episode_body, EPISODE_BODY_SCHEMA,
        src_version_id, episode_deriv, "observed", DEFAULT_SENSITIVITY,
        trace.get("started_at"), trace.get("finished_at"), [], episode_child_edges)

    # ---- candidate failure record (only when the run failed AND a failure descriptor is present) ----
    failure_env = None
    if trace_failed and tf and emit_failure_default:
        descriptor = dict(tf)
        descriptor.setdefault("component", (models[0]["model_id"] if models else task_id))
        descriptor.setdefault("attempted_operation", trace.get("original_request"))
        descriptor["authority_level"] = "proposed"     # auto-derived candidate, not curated
        descriptor.setdefault("status", "unverified")
        descriptor["episode_ref"] = {"record_id": episode_record_id,
                                     "record_version_id": episode_env["record_version_id"]}
        failure_env = build_failure(descriptor, ns, src_version_id, trace_id, trace_hash)

    return episode_env, stage_records, failure_env


# ------------------------------------------------------------------ failure records + signature + seam

def compute_failure_facets(descriptor):
    """The structured normalized token SET the retrieval seam matches on (task-conditioned)."""
    ec = descriptor.get("environmental_conditions") or {}
    comps = []
    for c in [descriptor.get("component")] + list(descriptor.get("skills") or []) + list(ec.get("tools") or []) + list(ec.get("components") or []):
        if c:
            comps.extend(norm_component(c))
    operations = op_tokens(descriptor.get("attempted_operation") or "") + [t for op in (descriptor.get("planned_operations") or []) for t in op_tokens(op)]
    file_types = [norm_ext(x) for x in (ec.get("file_types") or [])]
    schemas = []
    for s in (ec.get("schemas") or []) + list(descriptor.get("schemas") or []):
        if s:
            schemas.append(str(s).lower())
            schemas.extend(_TOKEN_RE.findall(str(s).lower()))
    model_tokens = []
    mc = ec.get("model_config") or {}
    for v in list(mc.values()) + list(ec.get("runtime") and [ec.get("runtime")] or []):
        if v:
            model_tokens.extend(_TOKEN_RE.findall(str(v).lower()))
    symptom_tokens = tokens(descriptor.get("observable_symptoms") or "")
    keywords = []
    for k in (descriptor.get("keywords") or []):
        keywords.extend(tokens(k))
    return {
        "components": sorted_unique(comps),
        "operations": sorted_unique(operations),
        "file_types": sorted_unique([f for f in file_types if f]),
        "schemas": sorted_unique(schemas),
        "model_tokens": sorted_unique(model_tokens),
        "symptom_tokens": sorted_unique(symptom_tokens),
        "keywords": sorted_unique(keywords),
    }


def compute_failure_signature(descriptor, facets):
    """A DETERMINISTIC, task-conditioned signature. Folds component + operation + symptom + condition
    keys so two occurrences of the SAME failure class (same component/op/symptoms/conditions) get the
    SAME signature -> the SAME logical failure record_id (dedup), while an unrelated failure differs."""
    comp_key = ",".join(facets["components"])
    op_key = ",".join(facets["operations"])
    sym_key = ",".join(facets["symptom_tokens"])
    cond_key = ",".join(facets["file_types"] + facets["schemas"] + facets["model_tokens"])
    digest = sha256_hex("\n".join([comp_key, op_key, sym_key, cond_key]).encode("utf-8"))[:20]
    lead = str(descriptor.get("component") or (facets["components"][0] if facets["components"] else "component")).lower()
    return "fsig1:%s:%s" % (re.sub(r"[^a-z0-9]", "-", lead)[:24], digest)


def build_failure(descriptor, namespace, source_version_id=None, trace_id=None, trace_hash=None):
    """Build a FAILURE s1 record from a descriptor (curated corpus entry OR an auto-derived candidate)."""
    if not isinstance(descriptor, dict):
        raise ValueError("failure descriptor must be an object")
    ns = namespace or descriptor.get("namespace") or "default"
    facets = compute_failure_facets(descriptor)
    signature = descriptor.get("failure_signature") or compute_failure_signature(descriptor, facets)

    conf = descriptor.get("confidence")
    if conf is None:
        confidence_ppm = descriptor.get("confidence_ppm")
        confidence_ppm = int(confidence_ppm) if confidence_ppm is not None else 500000
    else:
        confidence_ppm = _round_half_up(float(conf) * 1000000.0)

    body = {
        "component": descriptor.get("component"),
        "component_version": descriptor.get("component_version"),
        "affected_versions": descriptor.get("affected_versions") or [],
        "attempted_operation": bounded(descriptor.get("attempted_operation")),
        "environmental_conditions": descriptor.get("environmental_conditions") or {},
        "observable_symptoms": bounded(descriptor.get("observable_symptoms")),
        "failure_signature": signature,
        "root_cause": bounded(descriptor.get("root_cause")),
        "hypothesis": bounded(descriptor.get("hypothesis")),
        "evidence": [{"kind": (e or {}).get("kind"), "ref": (e or {}).get("ref"),
                      "snippet": bounded((e or {}).get("snippet"))}
                     for e in (descriptor.get("evidence") or [])],
        "correction": bounded(descriptor.get("correction")),
        "prevention_rule": bounded(descriptor.get("prevention_rule")),
        "verification_case": descriptor.get("verification_case"),
        "confidence_ppm": confidence_ppm,
        "status": descriptor.get("status") or "unverified",
        "match_keys": facets,
    }
    record_id = "fail_" + id24(ns, signature)
    # links / derivation refs to episodes/tests/commits/decisions/artifacts
    deriv = []
    parent_edges = []
    ep = descriptor.get("episode_ref")
    if ep and ep.get("record_id"):
        deriv.append({"ref_kind": "episode", "record_id": ep.get("record_id"),
                      "record_version_id": ep.get("record_version_id")})
        parent_edges.append({"edge_kind": "occurred_in_episode", "parent_record_id": ep.get("record_id")})
    for lk in (descriptor.get("links") or []):
        deriv.append({"ref_kind": (lk or {}).get("kind"), "ref": (lk or {}).get("ref")})
    if trace_id is not None:
        deriv.append({"ref_kind": "run_trace", "trace_id": trace_id, "trace_content_hash": trace_hash})

    svid = source_version_id or ("fdesc_" + id24(ns, signature, canon_str(descriptor)))
    authority = descriptor.get("authority_level") or "curated"
    sensitivity = descriptor.get("sensitivity_class") or DEFAULT_SENSITIVITY
    return build_envelope(
        "failure", record_id, "failv", ns, body, FAILURE_BODY_SCHEMA,
        svid, deriv, authority, sensitivity,
        descriptor.get("valid_from"), descriptor.get("valid_to"), parent_edges, [])


def _corpus_entry_facets(entry):
    """Return (record_id, facets, component, signature) for a corpus entry that is EITHER a built
    failure record (s1 envelope) OR a raw descriptor."""
    if isinstance(entry, dict) and entry.get("record_kind") == "failure" and entry.get("body"):
        b = entry["body"]
        mk = b.get("match_keys") or compute_failure_facets(b)
        return entry.get("record_id"), mk, b.get("component"), b.get("failure_signature")
    # a descriptor
    facets = compute_failure_facets(entry)
    sig = entry.get("failure_signature") or compute_failure_signature(entry, facets)
    rid = "fail_" + id24(entry.get("namespace") or "default", sig)
    return rid, facets, entry.get("component"), sig


# facet weights for the deterministic overlap score (integers -> no float in canonical output)
FACET_WEIGHTS = [
    # (query_facet_key, failure_facet_key, weight)
    ("components", "components", 5),
    ("operations", "operations", 4),
    ("schemas", "schemas", 4),
    ("model_tokens", "model_tokens", 3),
    ("file_types", "file_types", 2),
    ("keywords", "symptom_tokens", 2),
    ("keywords", "keywords", 2),
]


def task_context_facets(tc):
    """Normalize a lifeorch.task_context/0.1 query into the same facet token sets."""
    comps = []
    for c in list(tc.get("components") or []) + list(tc.get("skills") or []):
        comps.extend(norm_component(c))
    operations = [t for op in (tc.get("planned_operations") or []) for t in op_tokens(op)]
    file_types = sorted_unique([norm_ext(x) for x in (tc.get("file_types") or []) if x])
    schemas = []
    for s in (tc.get("schemas") or []):
        if s:
            schemas.append(str(s).lower())
            schemas.extend(_TOKEN_RE.findall(str(s).lower()))
    model_tokens = []
    mc = tc.get("model_config") or {}
    for v in list(mc.values()):
        if v:
            model_tokens.extend(_TOKEN_RE.findall(str(v).lower()))
    if tc.get("runtime"):
        model_tokens.extend(_TOKEN_RE.findall(str(tc.get("runtime")).lower()))
    keywords = []
    for k in (tc.get("keywords") or []):
        keywords.extend(tokens(k))
    return {
        "components": sorted_unique(comps),
        "operations": sorted_unique(operations),
        "file_types": file_types,
        "schemas": sorted_unique(schemas),
        "model_tokens": sorted_unique(model_tokens),
        "keywords": sorted_unique(keywords),
    }


def search_failures(task_context, corpus, k=None):
    """The FAILURE-SIGNATURE retrieval SEAM (directive 5.4). Deterministic signature/facet-overlap
    baseline: score = sum(weight * |query_facet & failure_facet|). A failure with ZERO overlap is
    EXCLUDED (never surfaces). Ranked by (-score, record_id) -- a stable, cross-platform tie-break.
    This is the seam a later retriever/reranker consumes -- NOT a production retriever."""
    qf = task_context_facets(task_context)
    q_sig = task_context.get("failure_signature")
    results = []
    for entry in corpus:
        rid, ff, component, signature = _corpus_entry_facets(entry)
        score = 0
        matched = {}
        for qkey, fkey, weight in FACET_WEIGHTS:
            inter = set(qf.get(qkey, [])) & set(ff.get(fkey, []))
            if inter:
                score += weight * len(inter)
                matched[qkey + "->" + fkey] = sorted(inter)
        # exact-signature short-circuit boost (a caller that already knows the signature)
        if q_sig and signature and q_sig == signature:
            score += 1000
            matched["exact_signature"] = [signature]
        if score > 0:
            results.append({
                "record_id": rid,
                "failure_signature": signature,
                "component": component,
                "score": score,
                "matched_facets": matched,
            })
    results.sort(key=lambda r: (-r["score"], r["record_id"]))
    for i, r in enumerate(results):
        r["rank"] = i + 1
    if k is not None:
        results = results[: max(0, int(k))]
    return {
        "schema": "lifeorch.failure_search_result/0.1",
        "query_schema": TASK_CONTEXT_SCHEMA,
        "query_facets": qf,
        "corpus_size": len(corpus),
        "match_count": len(results),
        "results": results,
    }


# ------------------------------------------------------------------ s1 validator

def validate_record(env):
    """Validate one record against the MEMORY_CONTRACT s1 envelope, INCLUDING provenance validity
    (content_hash recomputed from canonical content must match -- s6)."""
    errors = []
    if not isinstance(env, dict):
        return {"record_id": None, "record_kind": None, "valid": False, "errors": ["not an object"]}
    for f in ENVELOPE_FIELDS:
        if f not in env:
            errors.append("missing field: %s" % f)
    rk = env.get("record_kind")
    if rk not in RECORD_KINDS:
        errors.append("invalid record_kind: %r" % rk)
    rid = env.get("record_id")
    if not (isinstance(rid, str) and _ID_RE.match(rid)):
        errors.append("malformed record_id: %r" % rid)
    rvid = env.get("record_version_id")
    if not (isinstance(rvid, str) and _ID_RE.match(rvid)):
        errors.append("malformed record_version_id: %r" % rvid)
    ch = env.get("content_hash")
    if not (isinstance(ch, str) and _HEXCH_RE.match(ch)):
        errors.append("malformed content_hash: %r" % ch)
    # status/currentness must be the taxonomy object, not a bare boolean
    st = env.get("status")
    if not (isinstance(st, dict) and "state" in st and "stale_reasons" in st):
        errors.append("status must be a currentness object {state, stale_reasons, verified}")
    if env.get("sensitivity_class") in (None, ""):
        errors.append("sensitivity_class missing (required by s7 from day one)")
    if "embedding_space_id" not in env:
        errors.append("embedding_space_id field absent (must be present, nullable)")
    for ek in ("parent_edges", "child_edges", "derivation_refs"):
        if not isinstance(env.get(ek), list):
            errors.append("%s must be a list (first-class edges, not path fields)" % ek)
    # PROVENANCE VALIDITY: recompute content_hash
    if isinstance(ch, str) and _HEXCH_RE.match(ch or ""):
        recomputed = recompute_content_hash(env)
        if recomputed != ch:
            errors.append("content_hash MISMATCH (provenance invalid): declared %s recomputed %s" % (ch, recomputed))
        # record_version_id must derive from (record_id, content_hash)
        expect_v = id24(rid, ch)
        if isinstance(rvid, str) and not rvid.endswith(expect_v):
            errors.append("record_version_id does not derive from (record_id, content_hash)")
    # kind-specific required body fields
    b = env.get("body") or {}
    if rk == "episode":
        for bf in ("task_id", "original_request", "plan", "stage_sequence", "final_status",
                   "tool_invocations", "state_changes", "test_results", "metrics", "complete"):
            if bf not in b:
                errors.append("episode.body missing %s" % bf)
    elif rk == "episode_stage":
        for bf in ("stage_index", "stage_name", "status"):
            if bf not in b:
                errors.append("episode_stage.body missing %s" % bf)
    elif rk == "failure":
        for bf in ("component", "attempted_operation", "observable_symptoms", "failure_signature",
                   "match_keys", "confidence_ppm", "status"):
            if bf not in b:
                errors.append("failure.body missing %s" % bf)
    return {"record_id": rid, "record_kind": rk, "valid": len(errors) == 0, "errors": errors}


def validate_records(records):
    per = [validate_record(r) for r in records]
    counts = {}
    for r in per:
        counts[r["record_kind"]] = counts.get(r["record_kind"], 0) + 1
    return {
        "schema": "lifeorch.record_validation_report/0.1",
        "envelope_contract": RECORD_ENVELOPE_SCHEMA,
        "num_records": len(records),
        "num_valid": sum(1 for r in per if r["valid"]),
        "all_valid": all(r["valid"] for r in per) if per else False,
        "kind_counts": counts,
        "records": per,
    }


# ------------------------------------------------------------------ ingest bundle (FIXTURE #36 0.2 sink)

def ingest_bundle(namespace, records):
    """Shape the emitted records into a #36 0.2 `ingest_records` request (FIXTURE contract, reconciled
    at fold). Each record is an s1 envelope; the bundle is what the orchestrator feeds to artifact.search."""
    return {
        "schema": INGEST_REQUEST_SCHEMA,
        "op": "ingest_records",
        "namespace": namespace,
        "record_count": len(records),
        "records": records,
    }


def records_digest(records):
    """sha256 over sorted per-record 'RID\\tKIND\\tCONTENT_HASH\\tVERSION' lines -- the cross-env pin
    (like #36's catalog_digest: repo-relative + content-derived, never abs paths/rowids/timestamps)."""
    lines = sorted("%s\t%s\t%s\t%s" % (r.get("record_id"), r.get("record_kind"),
                                       r.get("content_hash"), r.get("record_version_id"))
                   for r in records)
    return "sha256:" + sha256_hex("\n".join(lines).encode("utf-8"))


# ------------------------------------------------------------------ driver

def write_canon(out_dir, name, obj):
    b = canon_bytes(obj)
    p = os.path.join(out_dir, name)
    with open(p, "wb") as fh:
        fh.write(b)
    return {"name": name, "path": os.path.abspath(p), "sha256": sha256_hex(b), "bytes": len(b)}


def run(request):
    op = request.get("op") or "record"
    out_dir = request.get("out_dir")
    if not out_dir:
        raise ValueError("request.out_dir is required")
    os.makedirs(out_dir, exist_ok=True)
    base_dir = request.get("base_dir") or os.getcwd()
    namespace = request.get("namespace")
    artifacts = []

    if op == "record":
        trace = load_json_input(request.get("trace") if request.get("trace") is not None else request.get("input"), base_dir, "trace")
        emit_failure = request.get("emit_failure", True)
        episode_env, stage_records, failure_env = record_trace(trace, namespace, emit_failure)
        ns = episode_env["namespace"]
        all_records = [episode_env] + stage_records + ([failure_env] if failure_env else [])
        validation = validate_records(all_records)
        bundle = ingest_bundle(ns, all_records)
        artifacts.append(write_canon(out_dir, "episode.json", episode_env))
        artifacts.append(write_canon(out_dir, "episode_stages.json", stage_records))
        if failure_env:
            artifacts.append(write_canon(out_dir, "failure.json", failure_env))
        artifacts.append(write_canon(out_dir, "records.json", bundle))
        artifacts.append(write_canon(out_dir, "validation.json", validation))
        summary = {
            "ok": True,
            "op": op,
            "namespace": ns,
            "episode_record_id": episode_env["record_id"],
            "episode_version_id": episode_env["record_version_id"],
            "episode_final_status": episode_env["body"]["final_status"],
            "stage_count": len(stage_records),
            "failure_emitted": failure_env is not None,
            "failure_record_id": failure_env["record_id"] if failure_env else None,
            "failure_signature": failure_env["body"]["failure_signature"] if failure_env else None,
            "record_count": len(all_records),
            "records_digest": records_digest(all_records),
            "all_valid": validation["all_valid"],
            "artifacts": artifacts,
            "error": None,
        }

    elif op == "build-failure":
        if request.get("failures") is not None:
            descriptors = load_json_input(request.get("failures"), base_dir, "failures")
            if not isinstance(descriptors, list):
                raise ValueError("failures must be a list")
        else:
            descriptors = [load_json_input(request.get("failure") if request.get("failure") is not None else request.get("input"), base_dir, "failure")]
        records = [build_failure(d, namespace) for d in descriptors]
        ns = namespace or (records[0]["namespace"] if records else "default")
        validation = validate_records(records)
        bundle = ingest_bundle(ns, records)
        artifacts.append(write_canon(out_dir, "failures.json", records))
        artifacts.append(write_canon(out_dir, "records.json", bundle))
        artifacts.append(write_canon(out_dir, "validation.json", validation))
        summary = {
            "ok": True, "op": op, "namespace": ns,
            "record_count": len(records),
            "records_digest": records_digest(records),
            "record_ids": [r["record_id"] for r in records],
            "failure_signatures": [r["body"]["failure_signature"] for r in records],
            "all_valid": validation["all_valid"],
            "artifacts": artifacts, "error": None,
        }

    elif op == "search-failures":
        tc = load_json_input(request.get("task_context") if request.get("task_context") is not None else request.get("input"), base_dir, "task_context")
        corpus = load_json_input(request.get("corpus"), base_dir, "corpus")
        if isinstance(corpus, dict) and "records" in corpus:
            corpus = corpus["records"]
        if not isinstance(corpus, list):
            raise ValueError("corpus must be a list (of failure records or descriptors)")
        res = search_failures(tc, corpus, request.get("k"))
        artifacts.append(write_canon(out_dir, "search.json", res))
        summary = {
            "ok": True, "op": op,
            "corpus_size": res["corpus_size"],
            "match_count": res["match_count"],
            "result_ids": [r["record_id"] for r in res["results"]],
            "top_record_id": (res["results"][0]["record_id"] if res["results"] else None),
            "search_digest": "sha256:" + sha256_hex(canon_bytes(res)),
            "artifacts": artifacts, "error": None,
        }

    elif op == "validate":
        records = load_json_input(request.get("records") if request.get("records") is not None else request.get("input"), base_dir, "records")
        if isinstance(records, dict) and "records" in records:
            records = records["records"]
        if isinstance(records, dict):
            records = [records]
        report = validate_records(records)
        artifacts.append(write_canon(out_dir, "validation.json", report))
        summary = {
            "ok": True, "op": op,
            "num_records": report["num_records"],
            "num_valid": report["num_valid"],
            "all_valid": report["all_valid"],
            "artifacts": artifacts, "error": None,
        }
    else:
        raise ValueError("unknown op: %r (record|build-failure|search-failures|validate)" % op)

    with open(os.path.join(out_dir, "worker-summary.json"), "wb") as fh:
        fh.write(canon_bytes(summary))
    return summary


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True, help="path to the request JSON")
    args = ap.parse_args(argv)
    with open(args.request, "rb") as fh:
        request = json.loads(normalized_text(fh.read()))
    try:
        run(request)
        sys.stdout.write("OK %s\n" % request.get("out_dir"))
        return 0
    except Exception as e:
        err = {"ok": False, "op": request.get("op"),
               "error": {"code": "episode_record_failed", "message": str(e), "retryable": False}}
        out_dir = request.get("out_dir")
        if out_dir:
            try:
                os.makedirs(out_dir, exist_ok=True)
                with open(os.path.join(out_dir, "worker-summary.json"), "wb") as fh:
                    fh.write(canon_bytes(err))
            except Exception:
                pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"], sort_keys=True))
        log("ERROR: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
