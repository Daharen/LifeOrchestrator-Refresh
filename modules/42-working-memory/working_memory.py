#!/usr/bin/env python3
# working_memory.py -- deterministic core of the per-task WORKING-MEMORY STORE (Life Orchestrator module 42
# `working.memory` 0.1.0, contract v0.2, i34 Tier-1 build, plan fo-34-45fcbd0d, D-0090/D-0096/D-0077).
#
# WHAT THIS IS
#   The MEMORY_ARCHITECTURE Tier-1 per-`task_id` WORKING-MEMORY STORE that MEMORY_CONTRACT Amendment A5 (U3',
#   D-0096) fully specified and RESERVED but did not build. It lets a deepening task distinguish its OWN
#   current intermediate state from stale earlier state (the mechanical cure for "deteriorates on iterative
#   prompts"), kept STRICTLY out of long-term evidence + execution authority. Distinct from long-term storage
#   (#36 owns that catalog) and from the context packet (#40 renders a `working_memory` region by consulting
#   this store's read op). No model, no network, CPU-only, stdlib-only (sqlite3 + hashlib + json).
#
#   TRUST (A5 U3' / CONTEXT_PACKET_CONTRACT i33 U3'): a `working` record is CONTINUITY-authoritative -- the
#   recorded current STATE of THIS task -- NOT world-truth, NOT execution authority. Every working record
#   carries `content_role: "working_state"` + `can_instruct: false`; permissions live ONLY in a packet's
#   control_plane, NEVER here.
#
#   STORE SEMANTICS (the working_state/0.1 sub-contract; SCHEMA_NOTES.md is normative):
#     * immutable versioned snapshots (a state is never mutated in place; a change appends a new version);
#     * CAS on `parent_state_version` at update (a stale-parent write FAILS CLOSED -- `cas_conflict`);
#     * exactly ONE active head per `task_id` (enforced transactionally);
#     * explicit `fork` -> a NEW task branch whose v1 derives from a source task's active head;
#     * a SEPARATE fixed working-memory budget (a per-record body byte cap; distinct from the evidence budget);
#     * a `closed`/`archived` state is NOT ordinarily retrievable (get_active_head returns nothing);
#     * archive != evidence; PROMOTION creates a NEW derived long-term record (record_kind=summary, a
#       `derives_from` edge to the working record, provenance_mode=derived_record) -- it NEVER re-labels the
#       working record.
#
#   CONJUNCTIVE ISOLATION (A5 U3'): access requires `task_id` AND current-namespace authorization. Task-
#   isolation and namespace-isolation are DIFFERENT mechanisms; an op NEVER widens parent scope. The namespace
#   half reuses #37's ONE canonical predicate `ns_permitted` (namespace_policy.py, imported READ-ONLY -- A5
#   risk-6; NEVER re-implemented). A cross-namespace access leaves NO identifying metadata: only an integer
#   `namespace_violation_count` + a fail-closed flag surface; detail goes to a PRIVILEGED local security log.
#
#   ORDINARY `search` REJECTS `record_kind = working` (A5 U3'): working records are retrievable ONLY by an
#   exact-`task_id` op here (get_active_head / list_by_task). The `search` op proves the boundary: it returns
#   zero working records + `working_excluded_from_search`. "Excluded by default" is too weak -- it is enforced.
#
# DETERMINISM (a re-run of the SAME op sequence on a fresh store is byte-identical, cross-machine):
#   every emitted id/hash is a pure function of FIXED content (sha256, first 24 hex, kind-prefixed) --
#   NO wall-clock, NO uuid, NO absolute paths feed any id/hash; state_version is a monotonic int per task;
#   canonical JSON = sort_keys + ensure_ascii + compact + one trailing LF + UTF-8 no BOM.
#
# INVOCATION (by the pwsh entrypoint; also runnable directly):
#   python3 working_memory.py --request <request.json>
#   Writes out_dir/{<artifacts>, worker-summary.json}; prints "OK <out_dir>" (0) or "ERR <json>" (1).

import sys
import os
import json
import hashlib
import argparse
import sqlite3

GENERATOR_NAME = "working.memory"
GENERATOR_VERSION = "0.1.0"
RECORD_ENVELOPE_SCHEMA = "lifeorch.memory_record/0.1"       # the MEMORY_CONTRACT s1 envelope id
WORKING_BODY_SCHEMA = "lifeorch.working_state/0.1"          # the per-task working-state body/sub-contract id
SUMMARY_BODY_SCHEMA = "lifeorch.summary/0.1"               # promotion target body family
SCHEMA_VERSION = "1"
STORE_SCHEMA_VERSION = 1                                    # the sqlite store schema version

# derivation fingerprints (carried into provenance; a change -> new content_hash -> new record_version_id).
EXTRACTOR_FINGERPRINT = "working.memory.store/0.1.0"
PARSER_FINGERPRINT = "working.memory.state_parser/1"

DEFAULT_SENSITIVITY = "project_internal"
DEFAULT_AUTHORITY = "working"                               # a working state is NOT authoritative long-term
BODY_BUDGET_BYTES = 65536                                   # the SEPARATE fixed working-memory per-record budget
CONTENT_ROLE = "working_state"
LIFECYCLE_STATES = ("active", "closed", "archived")

# MEMORY_CONTRACT s1 CLOSED record_kind enum (mirrors #36/#39). `working` is this store's kind; `summary` is
# the promotion target. Ordinary search must reject `working`.
RECORD_KINDS = frozenset([
    "source_chunk", "symbol", "summary", "decision", "claim", "episode", "failure", "procedure",
    "skill", "reminder", "entity", "relationship", "node", "working",
])

# -- import #37's ONE canonical namespace predicate (A5 risk-6): READ-ONLY, NEVER re-implemented. Resolve a
#    portable path: a caller-supplied ns_policy_path, else a sibling lib/, else the repo's #37 lib. --
def _load_ns_policy(explicit_path):
    import importlib.util
    here = os.path.dirname(os.path.abspath(__file__))
    cands = []
    if explicit_path:
        cands.append(explicit_path)
    cands.append(os.path.join(here, "lib", "namespace_policy.py"))
    cands.append(os.path.normpath(os.path.join(here, "..", "37-retrieval-eval", "lib", "namespace_policy.py")))
    for c in cands:
        if c and os.path.isfile(c):
            spec = importlib.util.spec_from_file_location("namespace_policy", c)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            return mod, os.path.abspath(c)
    raise WMError("ns_policy_not_found", "canonical namespace_policy.py not found (tried: %s)" % "; ".join(cands), False)


class WMError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable


def log(msg):
    s = str(msg)
    if len(s) > 300:
        s = s[:300] + "...[+%d]" % (len(s) - 300)
    sys.stderr.write("[working.memory] " + s + "\n")


# ------------------------------------------------------------------ determinism helpers

def canon_bytes(obj):
    """Canonical JSON bytes: sorted keys, compact, ensure_ascii, one trailing LF, UTF-8 no BOM."""
    s = json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    return (s + "\n").encode("utf-8")


def canon_text(obj):
    return canon_bytes(obj).decode("utf-8")


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def content_hash(obj):
    return "sha256:" + sha256_hex(canon_bytes(obj))


def gen_id(prefix, *parts):
    """A content-derived id: <prefix>_<first 24 hex of sha256 over the canonical parts>. Pure."""
    h = sha256_hex(canon_bytes(list(parts)))
    return "%s_%s" % (prefix, h[:24])


def coerce_body(body):
    """The state payload is stored as an OPAQUE canonical object. Enforce the working-memory budget."""
    if body is None:
        body = {}
    if not isinstance(body, (dict, list)):
        body = {"value": body}
    b = canon_bytes(body)
    if len(b) > BODY_BUDGET_BYTES:
        raise WMError("working_budget_exceeded",
                      "state body %d bytes exceeds the working-memory budget %d" % (len(b), BODY_BUDGET_BYTES),
                      False)
    return body


# ------------------------------------------------------------------ store

STORE_DDL = """
CREATE TABLE IF NOT EXISTS store_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS working_state (
  record_version_id     TEXT PRIMARY KEY,
  working_state_id      TEXT NOT NULL,
  task_id               TEXT NOT NULL,
  namespace_scope       TEXT NOT NULL,
  state_version         INTEGER NOT NULL,
  parent_state_version  INTEGER,
  content_hash          TEXT NOT NULL,
  grant_snapshot_ref    TEXT,
  created_from_packet_id TEXT,
  forked_from           TEXT,
  writer_authority      TEXT NOT NULL,
  lifecycle_state       TEXT NOT NULL,
  is_active_head        INTEGER NOT NULL DEFAULT 0,
  body                  TEXT NOT NULL,
  UNIQUE(task_id, state_version)
);
CREATE INDEX IF NOT EXISTS ix_ws_task ON working_state(task_id);
CREATE INDEX IF NOT EXISTS ix_ws_logical ON working_state(working_state_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ws_head ON working_state(task_id) WHERE is_active_head = 1;
"""


def open_store(store_path):
    newdb = not os.path.exists(store_path)
    d = os.path.dirname(os.path.abspath(store_path))
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    conn = sqlite3.connect(store_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON;")
    conn.executescript(STORE_DDL)
    if newdb:
        conn.execute("INSERT OR REPLACE INTO store_meta(k,v) VALUES('store_schema_version',?)",
                     (str(STORE_SCHEMA_VERSION),))
    conn.commit()
    return conn


def _head_row(conn, task_id):
    cur = conn.execute(
        "SELECT * FROM working_state WHERE task_id=? AND is_active_head=1 AND lifecycle_state='active'",
        (task_id,))
    return cur.fetchone()


def _row_to_envelope(row):
    """Build the MEMORY_CONTRACT s1 record ENVELOPE (record_kind=working) for a stored state version."""
    body = json.loads(row["body"])
    env = {
        "schema": RECORD_ENVELOPE_SCHEMA,
        "record_id": row["working_state_id"],
        "record_version_id": row["record_version_id"],
        "record_kind": "working",
        "body_schema": WORKING_BODY_SCHEMA,
        "namespace": row["namespace_scope"],
        "content_hash": row["content_hash"],
        "record_content_hash": row["content_hash"],
        "provenance_mode": "derived_record",
        "status": "current",
        "authority_level": DEFAULT_AUTHORITY,
        "sensitivity_class": DEFAULT_SENSITIVITY,
        "content_role": CONTENT_ROLE,
        "can_instruct": False,
        "valid_from": None,
        "valid_to": None,
        "created_by_ingest_run": None,
        "source_version_id": None,
        "source_span": None,
        "derivation_refs": ([row["forked_from"]] if row["forked_from"] else []),
        "parser_fingerprint": PARSER_FINGERPRINT,
        "chunker_fingerprint": None,
        "extractor_fingerprint": EXTRACTOR_FINGERPRINT,
        "schema_version": SCHEMA_VERSION,
        "token_count": len(canon_text(body).split()),
        "embedding_space_id": None,
        "parent_edges": [],
        "child_edges": [],
        # -- the A5 U3' working-state store fields --
        "working_state_id": row["working_state_id"],
        "task_id": row["task_id"],
        "state_version": row["state_version"],
        "parent_state_version": row["parent_state_version"],
        "namespace_scope": row["namespace_scope"],
        "grant_snapshot_ref": row["grant_snapshot_ref"],
        "created_from_packet_id": row["created_from_packet_id"],
        "lifecycle_state": row["lifecycle_state"],
        "writer_authority": row["writer_authority"],
        "body": body,
    }
    return env


def _authorize(nsmod, rej, namespace_scope, effective_allowed, stage):
    """Conjunctive namespace half: ns_permitted(namespace_scope, effective_allowed). Fail-closed + sanitized.
    Returns True if permitted; else records ONE sanitized rejection (no leakage) and returns False."""
    if nsmod.ns_permitted(namespace_scope, effective_allowed):
        return True
    rej.reject({"namespace": namespace_scope}, effective_allowed, stage=stage)
    return False


# ------------------------------------------------------------------ ops
# Every op returns (summary_dict, artifacts_dict{name: obj}). Access-controlled ops take effective_allowed.

def _effective(req, nsmod):
    """Compute the caller's effective allowed namespace set = intersection(request, grant) (A5 U1'e).
    `allowed_namespaces` (request) + `permission_grants` (grant) are caller-supplied; neither widens."""
    request = req.get("allowed_namespaces", req.get("namespace_request"))
    grant = req.get("permission_grants", req.get("namespace_grant"))
    if request is None and grant is None and req.get("effective_allowed_namespaces") is not None:
        return nsmod.normalize_allowed(req.get("effective_allowed_namespaces"))
    return nsmod.effective_allowed_namespaces(request, grant)


def op_put_state(conn, nsmod, rej, req):
    task_id = req.get("task_id")
    if not task_id:
        raise WMError("no_task_id", "put_state requires task_id", False)
    body = coerce_body(req.get("body"))
    eff = _effective(req, nsmod)
    head = _head_row(conn, task_id)
    exp_parent = req.get("parent_state_version", None)

    if head is None:
        # v1 (new task): parent must be null/0; caller declares namespace_scope + must be authorized for it.
        ns_scope = req.get("namespace_scope") or req.get("namespace")
        if not ns_scope:
            raise WMError("no_namespace_scope", "put_state (new task) requires namespace_scope", False)
        if not _authorize(nsmod, rej, ns_scope, eff, "put_state"):
            raise WMError("namespace_denied", "conjunctive access denied", False)
        if exp_parent not in (None, 0):
            raise WMError("cas_conflict",
                          "put_state for a new task expects parent_state_version null/0, got %r" % (exp_parent,),
                          False)
        state_version = 1
        parent_version = None
        forked_from = req.get("forked_from")
    else:
        # v(N+1): namespace_scope is IMMUTABLE per task (expansion never widens parent scope). CAS on parent.
        ns_scope = head["namespace_scope"]
        if not _authorize(nsmod, rej, ns_scope, eff, "put_state"):
            raise WMError("namespace_denied", "conjunctive access denied", False)
        if req.get("namespace_scope") and req.get("namespace_scope") != ns_scope:
            raise WMError("namespace_immutable",
                          "a task's namespace_scope is fixed at v1; cannot change on update", False)
        if exp_parent is None or int(exp_parent) != int(head["state_version"]):
            # CAS: the caller's expected parent must equal the current active head.
            raise WMError("cas_conflict",
                          "stale parent: expected parent_state_version=%s, current head=%s" %
                          (exp_parent, head["state_version"]), False)
        state_version = int(head["state_version"]) + 1
        parent_version = int(head["state_version"])
        forked_from = head["forked_from"]

    ws_id = req.get("working_state_id") or gen_id("ws", task_id, ns_scope)  # logical id: stable per task branch
    rvid = gen_id("wsv", ws_id, state_version, canon_text(body))
    chash = content_hash(body)
    row = {
        "working_state_id": ws_id, "record_version_id": rvid, "task_id": task_id,
        "namespace_scope": ns_scope, "state_version": state_version, "parent_state_version": parent_version,
        "content_hash": chash, "grant_snapshot_ref": req.get("grant_snapshot_ref"),
        "created_from_packet_id": req.get("created_from_packet_id"), "forked_from": forked_from,
        "writer_authority": req.get("writer_authority") or "task", "lifecycle_state": "active",
        "body": canon_text(body),
    }
    try:
        conn.execute("BEGIN IMMEDIATE")
        if head is not None:
            conn.execute("UPDATE working_state SET is_active_head=0 WHERE task_id=? AND is_active_head=1",
                         (task_id,))
        conn.execute(
            """INSERT INTO working_state(working_state_id,record_version_id,task_id,namespace_scope,
               state_version,parent_state_version,content_hash,grant_snapshot_ref,created_from_packet_id,
               forked_from,writer_authority,lifecycle_state,is_active_head,body)
               VALUES(:working_state_id,:record_version_id,:task_id,:namespace_scope,:state_version,
               :parent_state_version,:content_hash,:grant_snapshot_ref,:created_from_packet_id,:forked_from,
               :writer_authority,:lifecycle_state,1,:body)""", row)
        conn.execute("COMMIT")
    except sqlite3.IntegrityError as e:
        conn.execute("ROLLBACK")
        raise WMError("cas_conflict", "concurrent head update rejected: %s" % e, False)

    env = _row_to_envelope(dict(_head_row(conn, task_id)))
    summ = {"op": "put_state", "task_id": task_id, "namespace_scope": ns_scope,
            "working_state_id": ws_id, "record_version_id": rvid, "state_version": state_version,
            "parent_state_version": parent_version, "content_hash": chash,
            "active_head_version": state_version}
    return summ, {"state": env}


def op_get_active_head(conn, nsmod, rej, req):
    task_id = req.get("task_id")
    if not task_id:
        raise WMError("no_task_id", "get_active_head requires task_id", False)
    eff = _effective(req, nsmod)
    head = _head_row(conn, task_id)
    if head is None:
        return {"op": "get_active_head", "task_id": task_id, "found": False,
                "reason": "no_active_head"}, {}
    if not _authorize(nsmod, rej, head["namespace_scope"], eff, "get_active_head"):
        # sanitized fail-closed: no record, no identifying detail
        return {"op": "get_active_head", "task_id": task_id, "found": False,
                "reason": "namespace_denied"}, {}
    env = _row_to_envelope(dict(head))
    return {"op": "get_active_head", "task_id": task_id, "found": True,
            "working_state_id": env["working_state_id"], "state_version": env["state_version"],
            "content_hash": env["content_hash"]}, {"state": env}


def op_list_by_task(conn, nsmod, rej, req):
    task_id = req.get("task_id")
    if not task_id:
        raise WMError("no_task_id", "list_by_task requires task_id (exact)", False)
    eff = _effective(req, nsmod)
    cur = conn.execute("SELECT * FROM working_state WHERE task_id=? ORDER BY state_version ASC", (task_id,))
    rows = [dict(r) for r in cur.fetchall()]
    if not rows:
        return {"op": "list_by_task", "task_id": task_id, "count": 0, "versions": []}, {}
    # conjunctive: the task's namespace_scope (fixed) must be authorized
    ns_scope = rows[0]["namespace_scope"]
    if not _authorize(nsmod, rej, ns_scope, eff, "list_by_task"):
        return {"op": "list_by_task", "task_id": task_id, "count": 0, "versions": [],
                "reason": "namespace_denied"}, {}
    envs = [_row_to_envelope(r) for r in rows]
    versions = [{"state_version": r["state_version"], "lifecycle_state": r["lifecycle_state"],
                 "is_active_head": bool(r["is_active_head"]), "content_hash": r["content_hash"]} for r in rows]
    return {"op": "list_by_task", "task_id": task_id, "count": len(rows), "versions": versions}, \
           {"records": envs}


def op_fork(conn, nsmod, rej, req):
    src_task = req.get("source_task_id") or req.get("task_id")
    new_task = req.get("new_task_id")
    if not src_task or not new_task:
        raise WMError("fork_args", "fork requires source_task_id and new_task_id", False)
    if new_task == src_task:
        raise WMError("fork_args", "new_task_id must differ from source_task_id", False)
    eff = _effective(req, nsmod)
    src_head = _head_row(conn, src_task)
    if src_head is None:
        raise WMError("no_source_head", "fork source task has no active head", False)
    ns_scope = src_head["namespace_scope"]  # a fork NEVER widens scope: inherits the source namespace
    if not _authorize(nsmod, rej, ns_scope, eff, "fork"):
        raise WMError("namespace_denied", "conjunctive access denied", False)
    if _head_row(conn, new_task) is not None:
        raise WMError("fork_target_exists", "new_task_id already has an active head", False)
    body = json.loads(src_head["body"])
    put_req = {"task_id": new_task, "namespace_scope": ns_scope, "body": body,
               "parent_state_version": None, "forked_from": src_head["record_version_id"],
               "grant_snapshot_ref": req.get("grant_snapshot_ref"),
               "created_from_packet_id": req.get("created_from_packet_id"),
               "writer_authority": req.get("writer_authority") or "task",
               "allowed_namespaces": req.get("allowed_namespaces"),
               "permission_grants": req.get("permission_grants"),
               "effective_allowed_namespaces": req.get("effective_allowed_namespaces")}
    summ, arts = op_put_state(conn, nsmod, rej, put_req)
    summ["op"] = "fork"
    summ["source_task_id"] = src_task
    summ["new_task_id"] = new_task
    summ["forked_from"] = src_head["record_version_id"]
    return summ, arts


def _set_lifecycle(conn, nsmod, rej, req, new_state, opname):
    task_id = req.get("task_id")
    if not task_id:
        raise WMError("no_task_id", "%s requires task_id" % opname, False)
    eff = _effective(req, nsmod)
    head = _head_row(conn, task_id)
    if head is None:
        return {"op": opname, "task_id": task_id, "changed": False, "reason": "no_active_head"}, {}
    if not _authorize(nsmod, rej, head["namespace_scope"], eff, opname):
        raise WMError("namespace_denied", "conjunctive access denied", False)
    conn.execute("UPDATE working_state SET lifecycle_state=? WHERE working_state_id=? AND state_version=?",
                 (new_state, head["working_state_id"], head["state_version"]))
    conn.commit()
    return {"op": opname, "task_id": task_id, "changed": True, "lifecycle_state": new_state,
            "state_version": head["state_version"]}, {}


def op_close(conn, nsmod, rej, req):
    return _set_lifecycle(conn, nsmod, rej, req, "closed", "close")


def op_archive(conn, nsmod, rej, req):
    return _set_lifecycle(conn, nsmod, rej, req, "archived", "archive")


def op_promote(conn, nsmod, rej, req):
    """PROMOTION creates a NEW derived long-term record (record_kind=summary) with a derives_from edge to the
    working record + provenance -- it NEVER re-labels the working record (which stays untouched)."""
    task_id = req.get("task_id")
    if not task_id:
        raise WMError("no_task_id", "promote requires task_id", False)
    eff = _effective(req, nsmod)
    head = _head_row(conn, task_id)
    if head is None:
        raise WMError("no_active_head", "promote: task has no active head", False)
    if not _authorize(nsmod, rej, head["namespace_scope"], eff, "promote"):
        raise WMError("namespace_denied", "conjunctive access denied", False)
    src = _row_to_envelope(dict(head))
    body = {"summary_type": "working_state_promotion", "promoted_from_task": task_id,
            "state_version": src["state_version"], "state_body": src["body"]}
    body = coerce_body(body)
    rid = gen_id("sum", "working_promotion", task_id, src["record_version_id"])
    rvid = gen_id("sumv", rid, canon_text(body))
    chash = content_hash(body)
    promoted = {
        "schema": RECORD_ENVELOPE_SCHEMA, "record_id": rid, "record_version_id": rvid,
        "record_kind": "summary", "body_schema": SUMMARY_BODY_SCHEMA, "namespace": src["namespace_scope"],
        "content_hash": chash, "record_content_hash": chash, "provenance_mode": "derived_record",
        "status": "current", "authority_level": "derived", "sensitivity_class": DEFAULT_SENSITIVITY,
        "content_role": "evidence", "can_instruct": False, "valid_from": None, "valid_to": None,
        "created_by_ingest_run": None, "source_version_id": None, "source_span": None,
        "derivation_refs": [src["record_version_id"]],
        "parser_fingerprint": PARSER_FINGERPRINT, "chunker_fingerprint": None,
        "extractor_fingerprint": EXTRACTOR_FINGERPRINT, "schema_version": SCHEMA_VERSION,
        "token_count": len(canon_text(body).split()), "embedding_space_id": None,
        "parent_edges": [], "child_edges": [],
        "attrs": {"summary_type": "working_state_promotion"},
        "edges": [{"edge_kind": "derives_from", "from_record_version_id": rvid,
                   "to_record_version_id": src["record_version_id"]}],
        "body": body,
    }
    # the working record is NOT re-labeled -- assert its kind is unchanged
    assert src["record_kind"] == "working"
    summ = {"op": "promote", "task_id": task_id, "promoted_record_id": rid,
            "promoted_record_version_id": rvid, "derives_from": src["record_version_id"],
            "promoted_record_kind": "summary", "working_record_unchanged": True}
    return summ, {"promoted": promoted, "source_working_state": src}


def op_search(conn, nsmod, rej, req):
    """Ordinary search MUST REJECT record_kind=working (A5 U3'). This op proves the boundary: it never returns
    a working record. Working state is retrievable ONLY by the exact-task_id ops."""
    requested = req.get("record_kind")
    return {"op": "search", "results": [], "count": 0,
            "working_excluded_from_search": True,
            "reason": ("record_kind=working is not retrievable via search; use get_active_head/list_by_task"
                       if requested == "working" else "this store never exposes working records via search"),
            "requested_record_kind": requested}, {}


OPS = {
    "put_state": op_put_state, "get_active_head": op_get_active_head, "list_by_task": op_list_by_task,
    "fork": op_fork, "close": op_close, "archive": op_archive, "promote": op_promote, "search": op_search,
}


# ------------------------------------------------------------------ main / request dispatch

def run_request(req):
    op = req.get("op")
    if op not in OPS:
        raise WMError("bad_op", "op must be one of: %s" % ", ".join(sorted(OPS)), False)
    out_dir = req.get("out_dir") or "."
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    store_path = req.get("store_path") or os.path.join(out_dir, "working_memory.db")
    nsmod, ns_path = _load_ns_policy(req.get("ns_policy_path"))
    rej = nsmod.NamespaceRejectionPolicy()
    conn = open_store(store_path)
    try:
        summ, arts = OPS[op](conn, nsmod, rej, req)
    finally:
        conn.close()

    # write canonical artifacts (byte-identical on a re-run of the same op sequence)
    written = []
    for name, obj in arts.items():
        p = os.path.join(out_dir, name + ".json")
        with open(p, "wb") as f:
            f.write(canon_bytes(obj))
        written.append(name + ".json")

    # the sanitized namespace surface (A5 U1'd): a COUNT only; identifying detail stays privileged.
    caller_ns = rej.caller_summary()
    # privileged security log -> a local file, NEVER returned to a caller / placed in a record
    if rej.security_log:
        with open(os.path.join(out_dir, "ns-security-log.jsonl"), "w", encoding="utf-8") as f:
            for d in rej.security_log:
                f.write(json.dumps(d, sort_keys=True) + "\n")

    summary = dict(summ)
    summary["ok"] = True
    summary["store_schema_version"] = STORE_SCHEMA_VERSION
    summary["ns_policy_id"] = getattr(nsmod, "NS_POLICY_ID", None)
    summary["ns_policy_version"] = getattr(nsmod, "NS_POLICY_VERSION", None)
    summary["ns_policy_path"] = ns_path
    summary["namespace_violation_count"] = caller_ns["namespace_violation_count"]
    summary["namespace_closure_violated"] = caller_ns["namespace_closure_violated"]
    summary["artifacts_written"] = sorted(written)
    # a cross-env identity pin over the emitted records (like #36/#39 records_digest)
    digest_src = [canon_text(obj) for _, obj in sorted(arts.items())]
    summary["records_digest"] = "sha256:" + sha256_hex(canon_bytes(digest_src))
    with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
        f.write(canon_bytes(summary))
    return summary


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args(argv)
    with open(args.request, "r", encoding="utf-8") as f:
        req = json.load(f)
    out_dir = req.get("out_dir") or "."
    try:
        summ = run_request(req)
        sys.stdout.write("OK %s\n" % out_dir)
        return 0
    except WMError as e:
        err = {"ok": False, "error": {"code": e.code, "message": e.message, "retryable": e.retryable}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("ERROR %s: %s" % (e.code, e.message))
        return 1
    except Exception as e:  # noqa
        err = {"ok": False, "error": {"code": "unhandled", "message": str(e), "retryable": False}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("UNHANDLED: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
