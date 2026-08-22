#!/usr/bin/env python3
"""materialize.py -- the i63 close-transaction MATERIALIZER, corrected (D-0163; supersedes the D-0162 engine).

Stage-only. Executes a validated close manifest as a resumable/idempotent transaction whose durable effect is
a private staging ref `refs/lo/close/<txid>` -- it NEVER touches `main` (live production cutover is i67).

The corrective engine makes the previously-*claimed* behaviors true:

  - The transaction_id and the whole manifest (incl. every path-bearing field) are validated BEFORE any
    filesystem side effect; the Journal directory is only built after that (C63-01/02).
  - The session retrieval ledger is resolved via the path policy, required as a real file, parsed, bound to
    the iteration, and put through the fail-closed retrieval gate BEFORE any render / durable stage / SEAL
    (C63-03).
  - APPLY commits each op's result as a DURABLE git object on the staging ref and RE-READS it before marking
    it verified; the journal binds manifest-digest + base HEAD + op-def + staged-ref + staged-tip + observed
    bytes and lives outside the candidate tree, so a crash before the durable effect can never false-seal an
    in-memory-only op (C63-05).
  - Every non-mirror canonical op must reach a verified terminal state, evidence-bound to the staged tip,
    before SEAL; validators/rebuilds run against the STAGED candidate, not `main`/worktree; an unavailable
    required runner is a durable BLOCKED failure, never a deferred-then-seal (C63-04).
  - SEAL binds the exact staged tip + manifest identity; a no-op resume revalidates all of that and never
    trusts a `sealed:true` marker alone (C63-06).
  - Projection preflight measures the FULL resulting projection document in the staged candidate (ordered
    same-manifest edits + native EOL), not the payload fragment; freshness binds to the exact staged backing
    in DAG order and requires a real source_fingerprint (C63-08/09).
  - Anchored preconditions are region-scoped (native bytes); deterministic content ops are re-derived and
    must match their declared result; directory identity rejects reparse members (C63-10/13).
  - There is NO live-cutover switch anywhere (C63-07). Production git writes require a verified lease context
    (C63-14); unit tests use isolated temp repos.

stdlib only.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import safepath as sp  # noqa: E402
import validate_manifest as vm  # noqa: E402

CONTENT_KINDS = {"append", "replace_section", "create"}
ANCHORED_KINDS = {"append", "replace_section"}
MIRROR_KIND = "mirror_reconcile"
GRADER_ID = "independent-grader"
RUNTIME_ROOT = "modules/44-project-map/runtime/close-txn"  # gitignored; outside the candidate tree; survives reset


class MaterializeError(Exception):
    def __init__(self, failure, msg, op_id=None):
        self.failure = failure
        self.op_id = op_id
        super().__init__("[%s]%s %s" % (failure, (" op=%s" % op_id) if op_id else "", msg))


# --------------------------------------------------------------------------- digests / fingerprints
def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def canonical_digest(obj):
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def eol_bytes(text, eol):
    norm = text.replace("\r\n", "\n").replace("\r", "\n")
    if eol == "crlf":
        norm = norm.replace("\n", "\r\n")
    return norm.encode("utf-8")


def fp(sha):
    return {"basis": "native-raw", "sha256": sha}


# --------------------------------------------------------------------------- region domain (F-4, C63-13)
def region_span(raw, anchor):
    """(start,end) byte offsets of the span an anchor resolves to -- region-scoped, never a whole file and
    never a caller-supplied offset. Raises on non-unique resolution."""
    t = anchor.get("type")
    if t == "marker":
        o = anchor["open"].encode("utf-8"); c = anchor["close"].encode("utf-8")
        if raw.count(o) != 1 or raw.count(c) != 1:
            raise MaterializeError("precondition-divergence", "marker anchor not unique")
        s = raw.find(o); e = raw.find(c) + len(c)
        if e <= s:
            raise MaterializeError("precondition-divergence", "marker close precedes open")
        return s, e
    if t == "append_below":
        m = anchor["marker"].encode("utf-8")
        if raw.count(m) != 1:
            raise MaterializeError("precondition-divergence", "append_below marker not unique")
        mstart = raw.find(m)
        lstart = raw.rfind(b"\n", 0, mstart) + 1
        nl = raw.find(b"\n", mstart)
        lend = len(raw) if nl == -1 else nl + 1
        return lstart, lend  # the whole marker line is the region
    if t == "heading":
        h = anchor["heading"].encode("utf-8")
        if raw.count(h) != 1:
            raise MaterializeError("precondition-divergence", "heading anchor not unique")
        s = raw.find(h)
        after = raw.find(b"\n## ", s + len(h))
        e = len(raw) if after == -1 else after + 1
        return s, e
    raise MaterializeError("precondition-divergence", "unknown anchor type %r" % t)


def region_fp(raw, anchor):
    s, e = region_span(raw, anchor)
    return fp(sha256_bytes(raw[s:e]))


def apply_content(raw, op, payload_native):
    """Return the new whole-file native bytes after applying a content op. `raw` is the current staged
    content (or None for create)."""
    kind = op["kind"]
    if kind == "create":
        if raw is not None:
            raise MaterializeError("precondition-divergence", "create target already exists", op.get("op_id"))
        return payload_native
    if raw is None:
        raise MaterializeError("missing-target",
                               "append/replace_section target is absent (a missing edit target invalidates "
                               "the close)", op.get("op_id"))
    anchor = op.get("region_anchor") or {}
    if kind == "append" and anchor.get("type") == "append_below":
        m = anchor["marker"].encode("utf-8")
        mstart = raw.find(m)
        nl = raw.find(b"\n", mstart)
        insert = len(raw) if nl == -1 else nl + 1
        return raw[:insert] + payload_native + raw[insert:]
    s, e = region_span(raw, anchor)  # replace_section / marker: replace the span
    return raw[:s] + payload_native + raw[e:]


# --------------------------------------------------------------------------- git
def _git(repo, *args, input_bytes=None, env=None, check=True):
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, input=input_bytes, env=e)
    if check and p.returncode != 0:
        raise MaterializeError("git-error", "git %s: %s" % (args[0], p.stderr.decode("utf-8", "replace")))
    return p


def is_git_repo(repo):
    p = _git(repo, "rev-parse", "--is-inside-work-tree", check=False)
    return p.returncode == 0 and p.stdout.strip() == b"true"


def native_head(repo):
    return _git(repo, "rev-parse", "HEAD").stdout.decode().strip()


def repo_identity(repo):
    # the empty-tree/first-commit-independent identity of THIS repo: its initial commit or the git dir path hash
    p = _git(repo, "rev-list", "--max-parents=0", "HEAD", check=False)
    root = p.stdout.decode().split("\n")[0].strip() if p.returncode == 0 else ""
    return root or sha256_bytes(os.path.realpath(os.path.join(repo, ".git")).encode())[:16]


def tree_blob(repo, ref, relpath):
    """Bytes of relpath in the git tree at `ref` (the candidate/base domain), or None if absent. This is the
    environment-INDEPENDENT byte representation the stage-only engine transacts -- NOT the worktree (which a
    checkout's autocrlf/eol normalization can rewrite). Manifests must be fingerprinted in THIS domain."""
    p = _git(repo, "cat-file", "blob", "%s:%s" % (ref, relpath), check=False)
    return p.stdout if p.returncode == 0 else None


def tree_dir_identity(repo, backing_ref, ref="HEAD"):
    """Deterministic identity (sha256_hexdigest, total_bytes) of a directory (or file) backing over the git
    tree at `ref`, using the SAME rel-to-dir / sorted / rel+NUL+bytes+NUL convention as safepath.dir_identity
    and materialize._staged_backing_identity, but over BLOB bytes. At the base (nothing staged) this equals
    the engine's staged-backing identity exactly, so a manifest authored with it binds to what APPLY will
    re-derive -- independent of the checkout's worktree EOL representation (C63-09; the on-box T63-17 clone
    exposed that safepath.dir_identity's worktree bytes drift from the candidate tree under autocrlf)."""
    listing = _git(repo, "ls-tree", "-r", "--name-only", ref, "--", backing_ref, check=False).stdout.decode()
    members = [x for x in listing.split("\n") if x.strip()]
    if not members:
        b = tree_blob(repo, ref, backing_ref)  # maybe a single-file backing
        if b is not None:
            return sha256_bytes(b), len(b)
        return None, 0
    h = hashlib.sha256()
    total = 0
    prefix = backing_ref.rstrip("/") + "/"
    for repo_rel in sorted(members):
        b = tree_blob(repo, ref, repo_rel)
        if b is None:
            continue
        rel = repo_rel[len(prefix):] if repo_rel.startswith(prefix) else repo_rel
        h.update(rel.encode("utf-8") + b"\0" + b + b"\0")
        total += len(b)
    return h.hexdigest(), total


# --------------------------------------------------------------------------- staging engine (durable)
class Staging:
    """A private staging ref built via plumbing on a throwaway index -- never touches the worktree or main.
    All object/ref writes go through `write` so production mode can require a verified lease first."""

    def __init__(self, repo, txid, base_head, workdir, write_guard):
        self.repo = repo
        self.ref = "refs/lo/close/%s" % txid
        self.base = base_head
        self.index = os.path.join(workdir, "staging.index")
        self.env = {"GIT_INDEX_FILE": self.index}
        self._guard = write_guard
        self._seeded = False

    def _seed(self):
        if not self._seeded:
            self._guard()
            _git(self.repo, "read-tree", self.base, env=self.env)
            self._seeded = True

    def tip(self):
        p = _git(self.repo, "rev-parse", "--verify", "--quiet", self.ref, check=False)
        return p.stdout.decode().strip() or None if p.returncode == 0 else None

    def current_bytes(self, relpath):
        """Current staged content of relpath (from the staging index if seeded/advanced, else base tree)."""
        self._seed()
        p = _git(self.repo, "cat-file", "blob", ":%s" % relpath, env=self.env, check=False)
        if p.returncode == 0:
            return p.stdout
        return None

    def stage(self, relpath, new_bytes, msg):
        """Durably stage new_bytes for relpath: write the blob object, update the index, commit onto the ref
        with compare-and-swap, and return the new tip commit."""
        self._seed()
        self._guard()
        oid = _git(self.repo, "hash-object", "-w", "--stdin", input_bytes=new_bytes, env=self.env).stdout.decode().strip()
        _git(self.repo, "update-index", "--add", "--cacheinfo", "100644,%s,%s" % (oid, relpath), env=self.env)
        tree = _git(self.repo, "write-tree", env=self.env).stdout.decode().strip()
        parent = self.tip() or self.base
        commit = _git(self.repo, "commit-tree", tree, "-p", parent, "-m", msg).stdout.decode().strip()
        # compare-and-swap: only advance the ref if it still points at `parent` (foreign move -> divergence)
        cur = self.tip()
        args = ["update-ref", self.ref, commit] + ([parent] if cur else [])
        r = _git(self.repo, *args, check=False)
        if r.returncode != 0:
            raise MaterializeError("staging-divergence",
                                   "staging ref moved under the transaction (CAS failed): %s"
                                   % r.stderr.decode("utf-8", "replace"))
        return commit

    def tip_bytes(self, relpath, tip=None):
        """Durable readback of relpath at the staged tip (proves the effect landed)."""
        t = tip or self.tip()
        if not t:
            return None
        p = _git(self.repo, "cat-file", "blob", "%s:%s" % (t, relpath), check=False)
        return p.stdout if p.returncode == 0 else None


# --------------------------------------------------------------------------- journal (binds durable facts)
class Journal:
    def __init__(self, repo, txid, base_head, manifest_digest, iteration):
        self.repo = repo
        self.txid = txid
        base = sp.safe_repo_path(repo, RUNTIME_ROOT)
        self.dir = os.path.join(base, txid)
        os.makedirs(self.dir, exist_ok=True)
        self.path = os.path.join(self.dir, "journal.jsonl")
        self.txn_path = os.path.join(self.dir, "txn.json")
        self.bind = {"transaction_id": txid, "base_head": base_head,
                     "manifest_digest": manifest_digest, "iteration": iteration,
                     "repo_identity": repo_identity(repo) if is_git_repo(repo) else None}
        self.records = []
        if os.path.isfile(self.path):
            with open(self.path, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        self.records.append(json.loads(line))

    def _clock(self):
        return int(time.time())

    def append(self, rec):
        rec = dict(rec)
        rec.setdefault("at", self._clock())
        rec["bind"] = self.bind
        key = json.dumps([rec.get("op_id"), rec.get("state"), rec.get("observed_post"),
                          rec.get("staged_tip")], sort_keys=True)
        for r in self.records:
            if json.dumps([r.get("op_id"), r.get("state"), r.get("observed_post"),
                           r.get("staged_tip")], sort_keys=True) == key:
                return
        self.records.append(rec)
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")

    def verified_post(self, op_id):
        post = None
        for r in self.records:
            if r.get("op_id") == op_id and r.get("state") == "verified":
                post = r
        return post

    def write_txn(self, txn):
        txn = dict(txn); txn["bind"] = self.bind
        with open(self.txn_path, "w", encoding="utf-8") as fh:
            json.dump(txn, fh, sort_keys=True, indent=1)

    def read_txn(self):
        if os.path.isfile(self.txn_path):
            try:
                with open(self.txn_path, "r", encoding="utf-8") as fh:
                    return json.load(fh)
            except (OSError, json.JSONDecodeError):
                return None
        return None


# --------------------------------------------------------------------------- ledger gate (C63-03)
def default_ledger_gate(repo, ledger_rel, iteration, min_bounded_fraction):
    """Resolve + require + parse + gate the session retrieval ledger. Prefer the canonical monitor
    (ops/audit/gen-retrieval-monitor.py --gate --check-only); fall back to a strict built-in equivalent.
    Returns an evidence dict on PASS; raises MaterializeError('ledger-...') on any failure."""
    path = sp.safe_repo_path(repo, ledger_rel)  # path policy (raises on escape)
    if not os.path.isfile(path):
        raise MaterializeError("ledger-missing", "ledger_ref is not a real file: %s" % ledger_rel)
    with open(path, "rb") as fh:
        raw = fh.read()
    digest = sha256_bytes(raw)
    monitor = os.path.join(repo, "ops", "audit", "gen-retrieval-monitor.py")
    args = [sys.executable, monitor, "--ledger", path, "--iteration", str(iteration), "--gate", "--check-only"]
    if min_bounded_fraction and min_bounded_fraction > 0:
        args += ["--min-bounded-fraction", str(min_bounded_fraction)]
    if os.path.isfile(monitor):
        p = subprocess.run(args, capture_output=True)
        if p.returncode != 0:
            raise MaterializeError("ledger-gate-failed",
                                   "retrieval gate rejected the ledger (exit %d): %s"
                                   % (p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")[:400]))
        return {"gate": "gen-retrieval-monitor", "exit": 0, "ledger_digest": digest,
                "iteration": iteration, "min_bounded_fraction": min_bounded_fraction,
                "cmd": " ".join(args[1:])}
    # built-in strict fallback: parse JSONL, enforce the zero-bounded floor + min fraction
    bounded = whole = 0
    n = 0
    for lineno, line in enumerate(raw.decode("utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            raise MaterializeError("ledger-malformed", "ledger line %d is not JSON" % lineno)
        if not isinstance(row, dict) or "kind" not in row or "bytes" not in row:
            raise MaterializeError("ledger-malformed", "ledger line %d missing kind/bytes" % lineno)
        b = row["bytes"]
        if not isinstance(b, int) or b <= 0:
            raise MaterializeError("ledger-malformed", "ledger line %d has non-positive bytes" % lineno)
        if row["kind"] in ("section", "card", "query"):
            bounded += b; n += 1
        elif row["kind"] == "whole_doc_open":
            whole += b
    if whole > 0 and bounded == 0:
        raise MaterializeError("ledger-gate-failed", "zero bounded queries alongside whole-doc opens")
    total = bounded + whole
    frac = (bounded / total) if total else 0.0
    if min_bounded_fraction and frac < min_bounded_fraction:
        raise MaterializeError("ledger-gate-failed",
                               "bounded fraction %.4f < min %.4f" % (frac, min_bounded_fraction))
    return {"gate": "builtin", "exit": 0, "ledger_digest": digest, "bounded_fraction": frac,
            "iteration": iteration, "min_bounded_fraction": min_bounded_fraction}


# --------------------------------------------------------------------------- the materializer
class Materializer:
    def __init__(self, repo, manifest, *, runner=None, ledger_gate=None,
                 require_lease=False, lease_context=None, lease_verifier=None):
        self.repo = os.path.abspath(repo)
        self.m = manifest
        self.header = manifest.get("header", {})
        self.txid = self.header.get("transaction_id")
        self.manifest_digest = canonical_digest(manifest)
        self.runner = runner
        self.ledger_gate = ledger_gate or default_ledger_gate
        self.require_lease = require_lease
        self.lease_context = lease_context
        self.lease_verifier = lease_verifier
        self.ops = list(manifest.get("operations", []))
        self.by_id = {o.get("op_id"): o for o in self.ops if isinstance(o, dict)}
        self.evidence = {"source_size": {}, "projection_size": {}, "freshness_valid": {},
                         "overflow": [], "avoidable_trim_retries": 0, "backing": {}, "ledger": None,
                         "op_states": {}}
        self.result = {"txid": self.txid, "phases": {}, "sealed": False, "final_head": None,
                       "cutover": "none (stage-only; live cutover is i67)"}
        self.journal = None
        self.staging = None

    # ---- lease-guarded git write ----
    def _write_guard(self):
        if self.require_lease:
            ok = bool(self.lease_verifier and self.lease_verifier(self.lease_context))
            if not ok:
                raise MaterializeError("lease-required",
                                       "production git write refused: no verified executor/git-lease context")

    # ---- helpers ----
    def _topo(self):
        indeg = {o["op_id"]: 0 for o in self.ops}
        adj = {o["op_id"]: [] for o in self.ops}
        for o in self.ops:
            for d in o.get("depends_on", []) or []:
                if d in indeg:
                    adj[d].append(o["op_id"]); indeg[o["op_id"]] += 1
        q = sorted([n for n, dg in indeg.items() if dg == 0]); order = []
        while q:
            n = q.pop(0); order.append(n)
            for mm in sorted(adj[n]):
                indeg[mm] -= 1
                if indeg[mm] == 0:
                    q.append(mm)
            q.sort()
        if len(order) != len(self.ops):
            raise MaterializeError("plan-error", "manifest DAG is not acyclic")
        return order

    def _payload_native(self, op):
        pr = op.get("payload_ref")
        eol = op.get("eol", "lf")
        if isinstance(pr, dict) and "inline" in pr:
            return eol_bytes(pr["inline"], eol)
        if isinstance(pr, str):
            path = sp.safe_repo_path(self.repo, pr)
            if not os.path.isfile(path):
                raise MaterializeError("apply-failure", "payload not found: %s" % pr, op.get("op_id"))
            with open(path, "rb") as fh:
                return eol_bytes(fh.read().decode("utf-8"), eol)
        raise MaterializeError("apply-failure", "content op has no usable payload_ref", op.get("op_id"))

    def _op_def_digest(self, op):
        return canonical_digest(op)

    # ---- PLAN (validates BEFORE any fs side effect) ----
    def plan(self):
        # 1. txid + iteration BEFORE touching the filesystem (C63-01)
        sp.validate_txid(self.txid, self.header.get("iteration"))
        # 2. static invariants + path policy over every field (C63-02)
        findings = vm.validate(self.m)
        if findings:
            raise MaterializeError("plan-error", "manifest invalid: %s" % "; ".join(findings[:6]))
        # 3. path policy execution-side (repo-bound) over EVERY path-bearing ref
        checker = lambda v: (None if sp.is_safe(self.repo, v) else self._reason(v))
        pf = []
        for op in self.ops:
            pf += sp.screen_refs(sp.op_path_refs(op, self.header if op is self.ops[0] else None), checker)
        # header ledger_ref explicitly (independent of op[0])
        pf += sp.screen_refs([("header.ledger_ref", self.header.get("ledger_ref"))], checker)
        pf = sorted(set(pf))
        if pf:
            raise MaterializeError("repo-escape", "unsafe path field(s): %s" % "; ".join(pf[:6]))
        # 4. base_head
        if is_git_repo(self.repo):
            hd = native_head(self.repo); bh = self.header.get("base_head")
            if not (hd.startswith(bh) or bh.startswith(hd[:len(bh)])):
                raise MaterializeError("base-head-divergence", "base_head %s != native HEAD %s" % (bh, hd))
        order = self._topo()
        self.result["phases"]["PLAN"] = {"ok": True, "order": order, "manifest_digest": self.manifest_digest}
        return order

    def _reason(self, v):
        try:
            sp.safe_repo_path(self.repo, v); return None
        except sp.PathSafetyError as e:
            return e.reason

    # ---- resume: revalidate a prior SEAL (never trust sealed:true alone) (C63-06) ----
    def _prior_seal_valid(self):
        txn = self.journal.read_txn()
        if not txn or not txn.get("sealed"):
            return None
        if txn.get("bind", {}).get("manifest_digest") != self.manifest_digest:
            return None
        tip = txn.get("final_head")
        if not tip or not is_git_repo(self.repo):
            return None
        if self.staging.tip() != tip:
            return None
        # every canonical op must still be verified against this tip
        for oid, op in self.by_id.items():
            if op.get("kind") == MIRROR_KIND:
                continue
            v = self.journal.verified_post(oid)
            if not v or v.get("staged_tip") != tip:
                return None
        return txn

    # ---- PRE-VALIDATE: the ledger gate ONLY (region preconditions + classified preflight run in APPLY, in
    #      DAG order, against the actual staged candidate so a same-manifest backing edit is seen -- C63-09) ----
    def pre_validate(self, order):
        mbf = self.header.get("min_bounded_fraction", 0)
        self.evidence["ledger"] = self.ledger_gate(self.repo, self.header.get("ledger_ref"),
                                                    self.header.get("iteration"), mbf)
        self.result["phases"]["PRE-VALIDATE"] = {"ok": True, "ledger_gated": True}

    def _staged_current(self, relpath):
        return self.staging.current_bytes(relpath)

    def _check_content_precondition(self, op, cur):
        """Region-scoped precondition (C63-13) against the CURRENT staged content. Returns 'apply' or
        'already' (idempotent whole-file match) or raises precondition-divergence / missing-target."""
        oid = op["op_id"]; kind = op["kind"]
        if kind == "create":
            if cur is None:
                return "apply"
            if cur == self._payload_native(op):
                return "already"
            raise MaterializeError("precondition-divergence", "create target exists + differs", oid)
        if cur is None:
            raise MaterializeError("missing-target", "edit target %s absent" % op["target"], oid)
        anchor = op.get("region_anchor") or {}
        cur_region = region_fp(cur, anchor)
        pre = op.get("precondition")
        if isinstance(pre, dict) and pre.get("sha256") == cur_region["sha256"]:
            return "apply"
        post = op.get("postcondition")
        if isinstance(post, dict) and sha256_bytes(cur) == post.get("sha256"):
            return "already"
        raise MaterializeError("precondition-divergence",
                               "anchored region prior != declared precondition and file != postcondition", oid)

    def _preflight_classified(self, op, cur):
        oid = op["op_id"]; dc = op["doc_class"]
        if dc == "backing":
            src = op.get("target")
            p = sp.safe_repo_path(self.repo, src)
            if cur is None and not os.path.exists(p):
                raise MaterializeError("backing-missing", "backing target %s does not exist" % src, oid)
            self.evidence["backing"][oid] = {"backing": src}
            return
        # projection: bind to the STAGED backing in DAG order (C63-09)
        backing_ref = op.get("backing_ref")
        try:
            fp_backing, size_backing = self._staged_backing_identity(backing_ref)
        except sp.PathSafetyError as e:
            raise MaterializeError("repo-escape", str(e), oid)
        if fp_backing is None:
            raise MaterializeError("backing-missing",
                                   "projection %s backing_ref %s resolves to nothing" % (oid, backing_ref), oid)
        declared = op.get("source_fingerprint")
        if not declared or not isinstance(declared, str):
            raise MaterializeError("stale-backing",
                                   "projection %s requires a source_fingerprint bound to its backing" % oid, oid)
        fresh = (declared == fp_backing)
        self.evidence["freshness_valid"][oid] = fresh
        self.evidence["source_size"][oid] = size_backing
        if not fresh:
            raise MaterializeError("stale-backing",
                                   "projection %s source_fingerprint drifted from the staged backing %s"
                                   % (oid, backing_ref), oid)
        # FULL resulting projection document preflight (C63-08): apply the op to the staged content
        payload = self._payload_native(op)
        full = apply_content(cur, op, payload)
        proj_size = len(full)
        budget = int(op["budget_bytes"])
        self.evidence["projection_size"][oid] = proj_size
        if proj_size > budget:
            self.evidence["overflow"].append({
                "op_id": oid, "projection": op["target"], "projection_size": proj_size,
                "budget_bytes": budget, "over_by": proj_size - budget, "backing_ref": backing_ref,
                "resolution": "backing-spill", "trimmed": False, "info_lost": False})
            raise MaterializeError("projection-overflow",
                                   "projection %s full result is %d B > budget %d B: SPILL to backing "
                                   "(source preserved lossless); no trim/compress" % (oid, proj_size, budget), oid)

    def _staged_backing_identity(self, backing_ref):
        """Identity (sha, size) of the backing in the STAGED candidate tree, using the SAME rel-to-dir,
        sorted, native-byte convention as safepath.dir_identity so a manifest's authored source_fingerprint
        (computed on the base tree) matches when nothing changed and DIFFERS after a same-manifest edit to
        the backing (C63-09). Reads git-blob bytes from the staging index (reflects staged edits); a git
        candidate tree contains no reparse members by construction."""
        p = sp.safe_repo_path(self.repo, backing_ref)
        staged_file = self._staged_current(backing_ref)
        if staged_file is not None:  # backing_ref is a single file (possibly edited in-manifest)
            return sha256_bytes(staged_file), len(staged_file)
        # a directory backing: enumerate candidate members under backing_ref from the staging index
        self.staging._seed()
        listing = _git(self.repo, "ls-files", "--", backing_ref, env=self.staging.env).stdout.decode()
        members = [x for x in listing.split("\n") if x.strip()]
        if not members:
            if not os.path.isdir(p):
                return None, 0
        h = hashlib.sha256(); total = 0
        prefix = backing_ref.rstrip("/") + "/"
        for repo_rel in sorted(members):
            b = self._staged_current(repo_rel)
            if b is None:
                continue
            rel = repo_rel[len(prefix):] if repo_rel.startswith(prefix) else repo_rel
            h.update(rel.encode("utf-8") + b"\0" + b + b"\0"); total += len(b)
        return h.hexdigest(), total

    # ---- APPLY (durable, DAG order) ----
    def apply(self, order):
        applied = []; already = []
        for oid in order:
            op = self.by_id[oid]
            if op.get("kind") not in CONTENT_KINDS:
                continue
            # durable idempotent skip: a prior verified record whose staged blob is still present + matches
            v = self.journal.verified_post(oid)
            if v:
                rb = self.staging.tip_bytes(op["target"], v.get("staged_tip"))
                if rb is not None and sha256_bytes(rb) == (v.get("observed_post") or {}).get("sha256"):
                    self.evidence["op_states"][oid] = "verified"; applied.append(oid); continue
            cur = self._staged_current(op["target"])
            # classified preflight (freshness + FULL-candidate overflow) in DAG order (C63-08/09)
            if op.get("doc_class") in ("projection", "backing"):
                self._preflight_classified(op, cur)
            decision = self._check_content_precondition(op, cur)
            if decision == "already":
                # target already equals its postcondition -> do NOT re-apply (append idempotence); the
                # candidate tree already carries it. Record verified against the current tip (or base).
                post = op.get("postcondition") or fp(sha256_bytes(cur))
                self.journal.append({"op_id": oid, "state": "verified", "op_def": self._op_def_digest(op),
                                     "observed_post": post, "staged_tip": self.staging.tip() or self.header.get("base_head")})
                self.evidence["op_states"][oid] = "verified"; already.append(oid); continue
            payload = self._payload_native(op)
            new = apply_content(cur, op, payload)
            post = fp(sha256_bytes(new))
            so = op.get("semantic_owner"); declared = op.get("postcondition")
            if so == "deterministic":
                if not isinstance(declared, dict) or declared.get("sha256") != post["sha256"]:
                    raise MaterializeError("deterministic-mismatch",
                                           "deterministic op result != declared postcondition "
                                           "(wrong postcondition or tampered payload)", oid)
            else:
                if isinstance(declared, dict):
                    raise MaterializeError("plan-error", "frontier content op pre-declares a postcondition", oid)
            self.journal.append({"op_id": oid, "state": "applied", "op_def": self._op_def_digest(op),
                                 "intended_post": post})  # intent BEFORE the durable effect
            tip = self.staging.stage(op["target"], new,
                                     "close-txn %s op=%s (stage-only; NOT a main cutover)" % (self.txid, oid))
            rb = self.staging.tip_bytes(op["target"], tip)
            if rb is None or sha256_bytes(rb) != post["sha256"]:
                raise MaterializeError("apply-failure", "durable readback != postcondition", oid)
            self.journal.append({"op_id": oid, "state": "verified", "op_def": self._op_def_digest(op),
                                 "observed_post": post, "staged_tip": tip})
            self.evidence["op_states"][oid] = "verified"; applied.append(oid)
        self.result["phases"]["APPLY"] = {"ok": True, "applied": applied, "already": already,
                                          "staged_tip": self.staging.tip()}
        return applied

    # ---- REBUILD + POST-VALIDATE: runners see the STAGED candidate; no deferred-then-seal (C63-04) ----
    def _runner_ctx(self, op):
        return {"repo": self.repo, "staging_ref": self.staging.ref, "staged_tip": self.staging.tip(), "op": op}

    def rebuild(self, order):
        done = []
        for oid in order:
            op = self.by_id[oid]
            if op.get("kind") != "view_rebuild":
                continue
            if self.runner is None:
                raise MaterializeError("blocked",
                                       "view_rebuild %s has no runner; refusing to seal deferred work" % oid, oid)
            r1 = self.runner("view_rebuild", self._runner_ctx(op))
            r2 = self.runner("view_rebuild", self._runner_ctx(op))
            if r1.get("digest") != r2.get("digest"):
                raise MaterializeError("rebuild-drift", "double-run digests differ for %s" % oid, oid)
            self.journal.append({"op_id": oid, "state": "verified", "observed_post": {"digest": r1.get("digest")},
                                 "staged_tip": self.staging.tip()})
            self.evidence["op_states"][oid] = "verified"; done.append(oid)
        self.result["phases"]["REBUILD"] = {"ok": True, "rebuilt": done}
        return done

    def post_validate(self, order):
        ran = []
        for oid in order:
            op = self.by_id[oid]; kind = op.get("kind")
            if kind == "validator":
                if self.runner is None:
                    raise MaterializeError("blocked",
                                           "validator %s has no runner; refusing to seal deferred work" % oid, oid)
                r = self.runner("validator", self._runner_ctx(op))
                if not r.get("ok"):
                    raise MaterializeError("validator-failure",
                                           "validator %s failed on the staged candidate: %s"
                                           % (op.get("validator_id"), r.get("detail")), oid)
            elif kind == "ack":
                pred = (op.get("payload_ref") or {}).get("predicate")
                if pred == "true":
                    pass
                elif self.runner is not None:
                    r = self.runner("ack", self._runner_ctx(op))
                    if not r.get("ok"):
                        raise MaterializeError("validator-failure", "ack %s predicate false" % oid, oid)
                else:
                    raise MaterializeError("blocked", "ack %s predicate needs a runner" % oid, oid)
            elif kind == "stamp":
                # a stamp is a deterministic content-like op; require it to have been applied+verified above,
                # OR (post-cutover volatile stamp) it belongs to i67 -> refuse to seal it here
                raise MaterializeError("blocked",
                                       "stamp %s is a post-cutover volatile op (i67); refusing to seal it in "
                                       "stage-only i63" % oid, oid)
            else:
                continue
            self.journal.append({"op_id": oid, "state": "verified", "staged_tip": self.staging.tip()})
            self.evidence["op_states"][oid] = "verified"; ran.append(oid)
        self.result["phases"]["POST-VALIDATE"] = {"ok": True, "ran": ran}
        return ran

    # ---- SEAL (binds the exact staged tip; NEVER main) ----
    def seal(self, order):
        canonical = [o for o in order if self.by_id[o].get("kind") != MIRROR_KIND]
        unresolved = [o for o in canonical if self.evidence["op_states"].get(o) != "verified"]
        if unresolved:
            raise MaterializeError("blocked", "canonical ops not verified: %s" % ", ".join(unresolved))
        tip = self.staging.tip() or self.header.get("base_head")  # candidate == base if nothing needed staging
        seal = {"sealed": True, "transaction_id": self.txid, "iteration": self.header.get("iteration"),
                "manifest_digest": self.manifest_digest, "base_head": self.header.get("base_head"),
                "staging_ref": self.staging.ref, "final_head": tip, "canonical_ops": canonical,
                "op_states": self.evidence["op_states"], "ledger": self.evidence["ledger"],
                "cutover": "none (stage-only; main untouched; live cutover is i67)", "evidence": self.evidence}
        self.journal.write_txn(seal)
        self.result["sealed"] = True; self.result["final_head"] = tip
        self.result["phases"]["SEAL"] = {"ok": True, "final_head": tip, "staging_ref": self.staging.ref}
        return seal

    def reconcile(self, order):
        mirrors = [o for o in order if self.by_id[o].get("kind") == MIRROR_KIND]
        for oid in mirrors:
            self.journal.append({"op_id": oid, "state": "deferred",
                                 "note": "mirror reconciliation is post-SEAL and belongs to i66"})
        self.result["phases"]["RECONCILE"] = {"ok": True, "deferred_mirrors": mirrors}

    # ---- driver ----
    def run(self):
        try:
            order = self.plan()
            base = self.header.get("base_head")
            workdir = sp.safe_repo_path(self.repo, RUNTIME_ROOT)
            workdir = os.path.join(workdir, self.txid)
            os.makedirs(workdir, exist_ok=True)
            self.journal = Journal(self.repo, self.txid, base, self.manifest_digest, self.header.get("iteration"))
            if is_git_repo(self.repo):
                self.staging = Staging(self.repo, self.txid, base, workdir, self._write_guard)
                prior = self._prior_seal_valid()
                if prior:
                    self.result["sealed"] = True; self.result["final_head"] = prior.get("final_head")
                    self.result["phases"]["SEAL"] = {"ok": True, "noop_resume": True,
                                                     "final_head": prior.get("final_head")}
                    self.result["ok"] = True
                    return self.result
            else:
                raise MaterializeError("plan-error", "not a git repo (stage-only engine requires git)")
            self.pre_validate(order)
            self.apply(order)
            self.rebuild(order)
            self.post_validate(order)
            self.seal(order)
            self.reconcile(order)
            self.result["ok"] = True
        except (MaterializeError, sp.PathSafetyError, sp.TxidError) as e:
            failure = getattr(e, "failure", None) or e.__class__.__name__
            if self.journal is not None:
                self.journal.append({"op_id": getattr(e, "op_id", None) or "__txn__", "state": "failed",
                                     "failure": failure, "detail": str(e), "resumable": True})
                self.journal.write_txn({"sealed": False, "failed": True, "failure": failure,
                                        "detail": str(e), "resumable": True, "evidence": self.evidence})
            self.result["ok"] = False; self.result["sealed"] = False
            self.result["failure"] = failure; self.result["detail"] = str(e)
        return self.result


def main(argv=None):
    ap = argparse.ArgumentParser(description="Materialize a close-transaction manifest (i63; stage-only).")
    ap.add_argument("manifest")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--require-lease", action="store_true",
                    help="production mode: refuse any git write without a verified executor/git-lease context.")
    a = ap.parse_args(argv)
    with open(a.manifest, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    mz = Materializer(a.repo, manifest, require_lease=a.require_lease)
    res = mz.run()
    print(json.dumps(res, indent=1, sort_keys=True))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
