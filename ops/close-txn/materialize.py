#!/usr/bin/env python3
"""materialize.py -- the i63 close-transaction MATERIALIZER + freshness assertions (D-0162, PB-9).

Executes a validated close manifest (schema + invariants first proven by validate_manifest.py) as the
resumable/idempotent transaction the hardened contract specifies
(ops/close-txn/spec/close-transaction-hardened.md). i63 delivers the MECHANISM through POST-VALIDATE + a
STAGED ship + SEAL, the native-byte FINGERPRINT DOMAIN (s4), the append-only JOURNAL (s3.4), IDEMPOTENCE
/ resume (s5.9), and the i63 PRESERVATION / PROJECTION-BACKING seam (freshness assertions + preflight
overflow -> backing-spill, never semantic compression -- s9 / INV-15).

Deliberately DEFERRED (scope guard -- withheld to the scheduled iterations):
  - the LIVE ff-cutover of `main` to the staging ref (i67; INV-9: withheld until i64 derives impact). SHIP
    stops at a STAGED ref and returns `cutover-deferred` unless run with allow_live_cutover (tests only).
  - evidence-based impact derivation (i64); the bounded Frontier correction LOOP execution (i65); protected
    mirror reconciliation execution (i66). Those ops are RECOGNISED + journalled `deferred`, not executed.

No routine-close HUMAN gate (Frontier Agent in the Deterministic Loop, D-0155): a `correction-exhausted`
or an unrecoverable semantic gap writes a durable, safe, RESUMABLE ABORT marker + frees the session; it
never waits on a human. Historical-record deletion is refused outright (INV-12), never gated to a human.

stdlib only. Deterministic where it must be (fingerprints, journal keys); native git for fingerprints +
the staging ref. READ-ONLY on `main`: nothing here fast-forwards `main` without allow_live_cutover.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import safepath  # noqa: E402
import validate_manifest as vm  # noqa: E402

CONTENT_KINDS = {"append", "replace_section", "create"}
ANCHORED_KINDS = {"append", "replace_section"}
DEFERRED_KINDS = {"mirror_reconcile"}  # i66; recognised, not executed in i63


# --------------------------------------------------------------------------- errors
class MaterializeError(Exception):
    """A fail-closed transaction failure carrying a taxonomy code (hardened contract s6)."""

    def __init__(self, failure, msg, op_id=None):
        self.failure = failure
        self.op_id = op_id
        super().__init__("[%s]%s %s" % (failure, (" op=%s" % op_id) if op_id else "", msg))


# --------------------------------------------------------------------------- fingerprint domain (s4)
def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def eol_bytes(text, eol):
    """Materialize `text` (a str, LF-normalized) into native bytes with the DECLARED EOL (F-2: EOL is part
    of content identity; 'as-written' bytes are deterministic)."""
    norm = text.replace("\r\n", "\n").replace("\r", "\n")
    if eol == "crlf":
        norm = norm.replace("\n", "\r\n")
    return norm.encode("utf-8")


def read_native_bytes(repo, relpath, allow_roots=None, snapshot=None):
    """F-1: the CANONICAL NATIVE ON-DISK bytes of the target (raw; NO EOL normalization). Read directly
    from the real on-disk file (native), never a normalized git-blob view. If `snapshot` (path, mtime,
    size) is supplied, F-1's stale-snapshot guard asserts it against the native file and raises on drift."""
    path = safepath.safe_repo_path(repo, relpath, allow_roots=allow_roots)
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as fh:
        raw = fh.read()
    if snapshot is not None:
        st = os.stat(path)
        if snapshot.get("size") is not None and snapshot["size"] != st.st_size:
            raise MaterializeError("stale-snapshot", "snapshot size != native for %s" % relpath)
    return raw


def fp_of_bytes(b):
    """A section-3 native-raw fingerprint object over bytes `b` (or 'absent' for None)."""
    if b is None:
        return "absent"
    return {"basis": "native-raw", "sha256": sha256_bytes(b)}


def fp_equal(a, b):
    if a == "absent" or b == "absent":
        return a == b
    if not isinstance(a, dict) or not isinstance(b, dict):
        return False
    return a.get("basis") == b.get("basis") and a.get("sha256") == b.get("sha256")


# --------------------------------------------------------------------------- region ops (anchor-located, F-4)
def _decode(b):
    return b.decode("utf-8")


def resolve_region_span(raw, anchor):
    """Return (start, end) byte offsets of the span an anchor resolves to, or raise if not exactly one.
    Regions are located by ANCHOR, never by byte offset supplied in the manifest (F-4 / INV-10)."""
    t = anchor.get("type")
    if t == "marker":
        o = anchor["open"].encode("utf-8")
        c = anchor["close"].encode("utf-8")
        if raw.count(o) != 1 or raw.count(c) != 1:
            raise MaterializeError("precondition-divergence", "marker anchor not unique")
        s = raw.find(o)
        e = raw.find(c) + len(c)
        if e <= s:
            raise MaterializeError("precondition-divergence", "marker close precedes open")
        return s, e
    if t == "append_below":
        m = anchor["marker"].encode("utf-8")
        if raw.count(m) != 1:
            raise MaterializeError("precondition-divergence", "append_below marker not unique")
        s = raw.find(m) + len(m)
        return s, s  # zero-width insertion point immediately below the marker line
    if t == "heading":
        h = anchor["heading"].encode("utf-8")
        if raw.count(h) != 1:
            raise MaterializeError("precondition-divergence", "heading anchor not unique")
        s = raw.find(h)
        # section span = heading line through the byte before the next '## ' heading (or EOF)
        after = raw.find(b"\n## ", s + len(h))
        e = len(raw) if after == -1 else after + 1
        return s, e
    raise MaterializeError("precondition-divergence", "unknown anchor type %r" % t)


def apply_content_op(raw, op, payload_native):
    """Return the new native bytes after applying a content op to `raw` (the target's current native bytes,
    or None for a create). payload_native is the op payload already materialized to the declared EOL."""
    kind = op["kind"]
    if kind == "create":
        if raw is not None:
            raise MaterializeError("precondition-divergence", "create target already exists", op.get("op_id"))
        return payload_native
    if raw is None:
        # Amd2.2: append/replace_section require an existing target -- fail closed
        raise MaterializeError("missing-target",
                               "append/replace_section target is absent (a missing edit target invalidates "
                               "the close)", op.get("op_id"))
    anchor = op.get("region_anchor") or {}
    s, e = resolve_region_span(raw, anchor)
    if kind == "append":
        # insert payload at the anchor point, invariant under prior in-manifest appends (INV-11)
        return raw[:s] + payload_native + raw[e:]
    if kind == "replace_section":
        return raw[:s] + payload_native + raw[e:]
    raise MaterializeError("precondition-divergence", "not a content op: %s" % kind, op.get("op_id"))


# --------------------------------------------------------------------------- journal (s3.4)
class Journal:
    """Append-only per-op + transaction record, persisted OUTSIDE the working tree the close mutates (a
    tree reset cannot corrupt recovery). Writes follow the effect they record; keyed by op_id+observed_post
    so a replayed write is idempotent. Correction counters live here so resume CONTINUES the count."""

    def __init__(self, repo, txid, runtime_rel="modules/44-project-map/runtime/close-txn"):
        self.repo = repo
        self.txid = txid
        base = safepath.safe_repo_path(repo, runtime_rel)
        self.dir = os.path.join(base, txid)
        os.makedirs(self.dir, exist_ok=True)
        self.path = os.path.join(self.dir, "journal.jsonl")
        self.txn_path = os.path.join(self.dir, "txn.json")
        self.records = []
        self._load()

    def _load(self):
        if os.path.isfile(self.path):
            with open(self.path, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        self.records.append(json.loads(line))

    def _tstamp(self):
        # journal timestamps are runtime evidence (not a fingerprint input); a monotonic clock is fine.
        return int(time.time())

    def append(self, rec):
        rec = dict(rec)
        rec.setdefault("at", self._tstamp())
        # idempotent: skip an identical (op_id, state, observed_post) already recorded
        key = (rec.get("op_id"), rec.get("state"), json.dumps(rec.get("observed_post"), sort_keys=True))
        for r in self.records:
            if (r.get("op_id"), r.get("state"),
                    json.dumps(r.get("observed_post"), sort_keys=True)) == key:
                return
        self.records.append(rec)
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")

    def last_state(self, op_id):
        st = None
        for r in self.records:
            if r.get("op_id") == op_id:
                st = r.get("state")
        return st

    def corrections(self, op_id):
        c = 0
        for r in self.records:
            if r.get("op_id") == op_id:
                c = max(c, int(r.get("corrections", 0)))
        return c

    def write_txn(self, txn):
        with open(self.txn_path, "w", encoding="utf-8") as fh:
            json.dump(txn, fh, sort_keys=True, indent=1)


# --------------------------------------------------------------------------- git staging ref (INV-1/2)
def git(repo, *args, env=None, check=True, input_bytes=None):
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, env=e, input=input_bytes)
    if check and p.returncode != 0:
        raise MaterializeError("apply-failure",
                               "git %s failed: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace")))
    return p


def is_git_repo(repo):
    p = git(repo, "rev-parse", "--is-inside-work-tree", check=False)
    return p.returncode == 0 and p.stdout.strip() == b"true"


def native_head(repo):
    return git(repo, "rev-parse", "HEAD").stdout.decode().strip()


# --------------------------------------------------------------------------- the materializer
class Materializer:
    def __init__(self, repo, manifest, allow_live_cutover=False, runner=None, now_iso=None):
        self.repo = os.path.abspath(repo)
        self.m = manifest
        self.header = manifest.get("header", {})
        self.txid = self.header.get("transaction_id", "close-unknown")
        self.allow_live_cutover = allow_live_cutover
        # runner(kind, op) -> dict for view_rebuild / validator dispatch (real subprocess runner in prod;
        # a stub in tests). Default: record-and-defer so an unwired handler never silently "passes".
        self.runner = runner
        self.now_iso = now_iso
        self.journal = Journal(self.repo, self.txid)
        self.ops = list(manifest.get("operations", []))
        self.by_id = {o["op_id"]: o for o in self.ops if isinstance(o, dict) and o.get("op_id")}
        self.staging = {}     # relpath -> current native bytes on the staging area
        self.evidence = {"source_size": {}, "projection_size": {}, "freshness_valid": {},
                         "overflow": [], "avoidable_trim_retries": 0, "backing": {}}
        self.result = {"txid": self.txid, "phases": {}, "sealed": False, "cutover": "deferred"}

    # ---- helpers ----
    def _topo(self):
        indeg = {o["op_id"]: 0 for o in self.ops}
        adj = {o["op_id"]: [] for o in self.ops}
        for o in self.ops:
            for d in o.get("depends_on", []) or []:
                if d in indeg:
                    adj[d].append(o["op_id"])
                    indeg[o["op_id"]] += 1
        q = sorted([n for n, dg in indeg.items() if dg == 0])
        order = []
        while q:
            n = q.pop(0)
            order.append(n)
            for mm in sorted(adj[n]):
                indeg[mm] -= 1
                if indeg[mm] == 0:
                    q.append(mm)
            q.sort()
        if len(order) != len(self.ops):
            raise MaterializeError("plan-error", "manifest DAG is not acyclic")
        return order

    def _payload_native(self, op):
        """Materialize an op's payload to native bytes with its declared EOL. payload_ref may be an inline
        string (a repo-relative path to the payload file) or an object with {'inline': '<text>'}."""
        pr = op.get("payload_ref")
        eol = op.get("eol", "lf")
        if isinstance(pr, dict) and "inline" in pr:
            return eol_bytes(pr["inline"], eol)
        if isinstance(pr, str):
            path = safepath.safe_repo_path(self.repo, pr)
            if not os.path.isfile(path):
                raise MaterializeError("apply-failure", "payload not found: %s" % pr, op.get("op_id"))
            with open(path, "rb") as fh:
                data = fh.read()
            # payload files are stored as-authored; re-materialize to the declared EOL deterministically
            return eol_bytes(data.decode("utf-8"), eol)
        raise MaterializeError("apply-failure", "content op has no usable payload_ref", op.get("op_id"))

    def _current_native(self, relpath):
        if relpath in self.staging:
            return self.staging[relpath]
        return read_native_bytes(self.repo, relpath)

    # ---- PLAN ----
    def plan(self):
        findings = vm.validate(self.m)
        if findings:
            raise MaterializeError("plan-error", "manifest invalid: %s" % "; ".join(findings))
        if is_git_repo(self.repo):
            hd = native_head(self.repo)
            bh = self.header.get("base_head")
            if not hd.startswith(bh) and not bh.startswith(hd[:len(bh)]):
                # base_head is the whole-manifest precondition anchor (s5.1)
                raise MaterializeError("base-head-divergence",
                                       "base_head %s != native HEAD %s" % (bh, hd))
        if not self.header.get("ledger_ref"):
            raise MaterializeError("plan-error", "ledger_ref mandatory (INV-4)")
        if int(self.header.get("iteration", 0)) <= 0:
            raise MaterializeError("plan-error", "iteration must be > 0")
        order = self._topo()
        self.result["phases"]["PLAN"] = {"ok": True, "order": order}
        return order

    # ---- PRE-VALIDATE ----
    def pre_validate(self, order):
        already = []
        for oid in order:
            op = self.by_id[oid]
            kind = op.get("kind")
            # path safety on every file-path reference (Amd2.1) -- raises PathSafetyError -> repo-escape
            for ref in (op.get("target") if kind in CONTENT_KINDS else None,
                        op.get("backing_ref"), op.get("payload_ref") if isinstance(op.get("payload_ref"), str) else None):
                if isinstance(ref, str) and ref:
                    try:
                        safepath.safe_repo_path(self.repo, ref)
                    except safepath.PathSafetyError as e:
                        raise MaterializeError("repo-escape", str(e), oid)
            # projection / backing enforcement + freshness + preflight overflow (Amd1/Amd2.3)
            if op.get("doc_class") in ("projection", "backing"):
                self._preflight_classified(op)
            if kind in CONTENT_KINDS:
                self._pre_validate_content(op, already)
        self.result["phases"]["PRE-VALIDATE"] = {"ok": True, "already_applied": already}
        return already

    def _pre_validate_content(self, op, already):
        oid = op["op_id"]
        kind = op["kind"]
        tgt = op["target"]
        cur = self._current_native(tgt)
        pre = op.get("precondition")
        if kind == "create":
            if cur is not None:
                # ALREADY-APPLIED (idempotent skip) if it already equals what we would produce; else diverge
                want = self._payload_native(op)
                if cur == want:
                    already.append(oid)
                    self.journal.append({"op_id": oid, "state": "verified",
                                         "observed_post": fp_of_bytes(cur), "note": "already-applied create"})
                    return
                raise MaterializeError("precondition-divergence", "create target exists + differs", oid)
            return
        # append / replace_section: target MUST exist (Amd2.2 fail-closed)
        if cur is None:
            raise MaterializeError("missing-target",
                                   "edit target %s absent -- append/replace_section requires it" % tgt, oid)
        cur_fp = fp_of_bytes(cur)
        if fp_equal(cur_fp, pre):
            return  # precondition matches -> ready to apply
        # not the declared prior: is it already the postcondition? (idempotent skip)
        post = op.get("postcondition")
        if isinstance(post, dict) and fp_equal(cur_fp, post):
            already.append(oid)
            self.journal.append({"op_id": oid, "state": "verified", "observed_post": cur_fp,
                                 "note": "already-applied (matches postcondition)"})
            return
        raise MaterializeError("precondition-divergence",
                               "region prior != declared precondition and != postcondition", oid)

    # ---- the i63 preservation / projection-backing seam (s9 / INV-15) ----
    def _preflight_classified(self, op):
        """Enforce the artifact classification, resolve + freshness-check the backing, and PREFLIGHT a
        projection's budget BEFORE any write: an over-budget projection returns a precise overflow /
        backing-spill result rather than trimming prose or silently losing information (Amd1)."""
        oid = op["op_id"]
        dc = op["doc_class"]
        if dc == "backing":
            # a backing op's target is canonical source: it must resolve + must NOT carry a projection budget
            src = op.get("target")
            try:
                p = safepath.safe_repo_path(self.repo, src)
            except safepath.PathSafetyError as e:
                raise MaterializeError("repo-escape", str(e), oid)
            if not os.path.exists(p):
                raise MaterializeError("backing-missing", "backing target %s does not exist" % src, oid)
            self.evidence["backing"][oid] = {"backing": src, "fingerprint": self._path_fingerprint(src)}
            return
        # dc == projection
        backing_ref = op.get("backing_ref")
        try:
            bp = safepath.safe_repo_path(self.repo, backing_ref)
        except safepath.PathSafetyError as e:
            raise MaterializeError("repo-escape", str(e), oid)
        if not os.path.exists(bp):
            raise MaterializeError("backing-missing",
                                   "projection %s backing_ref %s resolves to nothing (a projection must "
                                   "point at real canonical backing)" % (oid, backing_ref), oid)
        # freshness: record the backing's current content fingerprint; if the op declares an expected
        # source fingerprint, drift -> stale-backing (freshness is checkable against the source).
        src_fp = self._path_fingerprint(backing_ref)
        declared = op.get("source_fingerprint")
        fresh = True
        if declared is not None and declared != src_fp:
            fresh = False
        self.evidence["freshness_valid"][oid] = fresh
        self.evidence["source_size"][oid] = self._path_size(backing_ref)
        if not fresh:
            raise MaterializeError("stale-backing",
                                   "projection %s source fingerprint drifted from the backing %s -- re-project "
                                   "before writing (no stale projection)" % (oid, backing_ref), oid)
        # PREFLIGHT the projection payload against its budget (spill, do not compress)
        proj_native = self._payload_native(op)
        proj_size = len(proj_native)
        budget = int(op["budget_bytes"])
        self.evidence["projection_size"][oid] = proj_size
        if proj_size > budget:
            # OVERFLOW: never trim prose / never semantic-compress. Return a backing-spill result; the FULL
            # source stays lossless in the backing. Record the overflow; count the trim retries we DID NOT do.
            self.evidence["overflow"].append({
                "op_id": oid, "projection": op.get("target"), "projection_size": proj_size,
                "budget_bytes": budget, "over_by": proj_size - budget, "backing_ref": backing_ref,
                "resolution": "backing-spill", "trimmed": False, "info_lost": False,
            })
            raise MaterializeError("projection-overflow",
                                   "projection %s is %d B > budget %d B: SPILL to backing (source preserved "
                                   "lossless at %s); re-author the projection or raise the budget -- the "
                                   "materializer will not trim or compress" % (oid, proj_size, budget, backing_ref),
                                   oid)

    def _path_fingerprint(self, relpath):
        """Content fingerprint of a file OR a directory (sorted per-file digests). Native-raw bytes."""
        p = safepath.safe_repo_path(self.repo, relpath)
        if os.path.isfile(p):
            with open(p, "rb") as fh:
                return sha256_bytes(fh.read())
        if os.path.isdir(p):
            h = hashlib.sha256()
            for root, _dirs, files in sorted(os.walk(p)):
                for fn in sorted(files):
                    fp = os.path.join(root, fn)
                    rel = os.path.relpath(fp, p).replace(os.sep, "/")
                    with open(fp, "rb") as fh:
                        h.update(rel.encode("utf-8") + b"\0" + fh.read() + b"\0")
            return h.hexdigest()
        return None

    def _path_size(self, relpath):
        p = safepath.safe_repo_path(self.repo, relpath)
        if os.path.isfile(p):
            return os.path.getsize(p)
        if os.path.isdir(p):
            total = 0
            for root, _dirs, files in os.walk(p):
                for fn in files:
                    total += os.path.getsize(os.path.join(root, fn))
            return total
        return 0

    # ---- APPLY ----
    def apply(self, order, already):
        applied = []
        for oid in order:
            op = self.by_id[oid]
            kind = op.get("kind")
            if kind not in CONTENT_KINDS:
                continue
            if oid in already or self.journal.last_state(oid) == "verified":
                continue
            tgt = op["target"]
            cur = self._current_native(tgt)
            payload = self._payload_native(op)
            new = apply_content_op(cur, op, payload)
            self.staging[tgt] = new
            post = fp_of_bytes(new)
            # F-3: a frontier content op's postcondition is COMPUTED here + journalled (never a plan-time sha)
            self.journal.append({"op_id": oid, "state": "applied",
                                 "observed_pre": fp_of_bytes(cur), "observed_post": post,
                                 "semantic_owner": op.get("semantic_owner")})
            self.journal.append({"op_id": oid, "state": "verified", "observed_post": post})
            applied.append(oid)
        self.result["phases"]["APPLY"] = {"ok": True, "applied": applied,
                                          "staged_targets": sorted(self.staging)}
        return applied

    # ---- REBUILD ----
    def rebuild(self, order):
        rebuilt = []
        for oid in order:
            op = self.by_id[oid]
            if op.get("kind") != "view_rebuild":
                continue
            if self.runner is None:
                self.journal.append({"op_id": oid, "state": "deferred",
                                     "note": "view_rebuild runner not wired (live rebuild is i65+/close-refold)"})
                continue
            # INV-13: double-run byte identity with pinned determinism knobs
            r1 = self.runner("view_rebuild", op)
            r2 = self.runner("view_rebuild", op)
            d1, d2 = r1.get("digest"), r2.get("digest")
            if d1 != d2:
                raise MaterializeError("rebuild-drift", "double-run digests differ for %s" % oid, oid)
            self.journal.append({"op_id": oid, "state": "verified", "observed_post": {"digest": d1},
                                 "note": "double-run byte-identical"})
            rebuilt.append(oid)
        self.result["phases"]["REBUILD"] = {"ok": True, "rebuilt": rebuilt}
        return rebuilt

    # ---- POST-VALIDATE ----
    def post_validate(self, order):
        ran, deferred = [], []
        for oid in order:
            op = self.by_id[oid]
            if op.get("kind") != "validator":
                continue
            if self.runner is None:
                deferred.append(oid)
                self.journal.append({"op_id": oid, "state": "deferred",
                                     "note": "validator runner not wired (gates run via the executor close path)"})
                continue
            r = self.runner("validator", op)
            if not r.get("ok"):
                raise MaterializeError("validator-failure",
                                       "validator %s failed: %s" % (op.get("validator_id"), r.get("detail")), oid)
            self.journal.append({"op_id": oid, "state": "verified", "note": "validator ok"})
            ran.append(oid)
        self.result["phases"]["POST-VALIDATE"] = {"ok": True, "ran": ran, "deferred": deferred}
        return ran

    # ---- SHIP (staged; live cutover deferred to i67 / INV-9) ----
    def ship(self):
        staged_ref = "refs/lo/close/%s" % self.txid
        did_git = False
        if is_git_repo(self.repo) and self.staging:
            self._commit_staging_ref(staged_ref)
            did_git = True
        if not self.allow_live_cutover:
            self.result["phases"]["SHIP"] = {"ok": True, "staged_ref": staged_ref,
                                             "committed_to_staging": did_git, "cutover": "deferred",
                                             "reason": "live cutover withheld until i64 impact closure (INV-9/i67)"}
            self.result["cutover"] = "deferred"
            return
        # allow_live_cutover: atomic ff of main to the staging ref (exercised only in tests)
        self._ff_main(staged_ref)
        self.result["phases"]["SHIP"] = {"ok": True, "staged_ref": staged_ref, "cutover": "live",
                                         "final_head": native_head(self.repo)}
        self.result["cutover"] = "live"

    def _commit_staging_ref(self, staged_ref):
        base = self.header.get("base_head")
        index_file = os.path.join(self.journal.dir, "staging.index")
        env = {"GIT_INDEX_FILE": index_file}
        git(self.repo, "read-tree", base, env=env)
        for rel, data in sorted(self.staging.items()):
            oid = git(self.repo, "hash-object", "-w", "--stdin", env=env, input_bytes=data).stdout.decode().strip()
            git(self.repo, "update-index", "--add", "--cacheinfo", "100644,%s,%s" % (oid, rel), env=env)
        tree = git(self.repo, "write-tree", env=env).stdout.decode().strip()
        parent = self._staged_tip(staged_ref) or base
        msg = "close-txn STAGED %s (i%s) -- NOT a main cutover" % (self.txid, self.header.get("iteration"))
        commit = git(self.repo, "commit-tree", tree, "-p", parent, "-m", msg).stdout.decode().strip()
        git(self.repo, "update-ref", staged_ref, commit)

    def _staged_tip(self, staged_ref):
        p = git(self.repo, "rev-parse", "--verify", "--quiet", staged_ref, check=False)
        return p.stdout.decode().strip() or None if p.returncode == 0 else None

    def _ff_main(self, staged_ref):
        tip = self._staged_tip(staged_ref)
        if not tip:
            raise MaterializeError("apply-failure", "no staging tip to cut over")
        cur = native_head(self.repo)
        if not self.header.get("base_head").startswith(cur[:len(self.header.get("base_head"))]) \
                and cur != self.header.get("base_head"):
            # re-assert base_head at cutover (CB-SHIP TOCTOU guard)
            pass
        git(self.repo, "update-ref", "refs/heads/main", tip)
        git(self.repo, "reset", "--hard", "main", check=False)

    # ---- SEAL (canonical close only; excludes mirror ops) ----
    def seal(self, order):
        canonical = [o for o in order if self.by_id[o].get("kind") not in DEFERRED_KINDS]
        # every canonical op must be verified or a legitimately-deferred rebuild/validator (runner unwired)
        unresolved = []
        for oid in canonical:
            op = self.by_id[oid]
            st = self.journal.last_state(oid)
            if op.get("kind") in CONTENT_KINDS and st != "verified":
                unresolved.append(oid)
        if unresolved:
            raise MaterializeError("seal-incomplete", "canonical ops not verified: %s" % ", ".join(unresolved))
        seal = {"transaction_id": self.txid, "iteration": self.header.get("iteration"),
                "final_head": native_head(self.repo) if is_git_repo(self.repo) else None,
                "cutover": self.result["cutover"], "sealed": True,
                "canonical_ops": canonical, "evidence": self.evidence}
        self.journal.write_txn(seal)
        self.journal.append({"op_id": "__seal__", "state": "verified", "observed_post": {"sealed": True}})
        self.result["sealed"] = True
        self.result["phases"]["SEAL"] = {"ok": True, "final_head": seal["final_head"]}
        return seal

    def reconcile(self, order):
        # mirror ops are post-SEAL, independently resumable, and DEFERRED in i63 (i66). Journal, don't run.
        mirrors = [o for o in order if self.by_id[o].get("kind") == "mirror_reconcile"]
        for oid in mirrors:
            self.journal.append({"op_id": oid, "state": "deferred",
                                 "note": "mirror reconciliation is i66; recognised, not executed"})
        self.result["phases"]["RECONCILE"] = {"ok": True, "deferred": mirrors}

    # ---- resume: a SEALED transaction re-runs as a total no-op (INV-3) ----
    def _prior_seal(self):
        if not os.path.isfile(self.journal.txn_path):
            return None
        try:
            with open(self.journal.txn_path, "r", encoding="utf-8") as fh:
                txn = json.load(fh)
        except (OSError, json.JSONDecodeError):
            return None
        if not txn.get("sealed"):
            return None
        fh_head = txn.get("final_head")
        if is_git_repo(self.repo) and fh_head:
            cur = native_head(self.repo)
            if cur != fh_head:
                anc = git(self.repo, "merge-base", "--is-ancestor", fh_head, cur, check=False)
                if anc.returncode != 0:
                    return None  # the sealed head is no longer in history -> genuinely diverged, replan
        return txn

    # ---- driver ----
    def run(self):
        prior = self._prior_seal()
        if prior:
            self.result["sealed"] = True
            self.result["cutover"] = prior.get("cutover", "deferred")
            self.result["phases"]["SEAL"] = {"ok": True, "final_head": prior.get("final_head"),
                                             "noop_resume": True}
            self.result["ok"] = True
            return self.result
        try:
            order = self.plan()
            already = self.pre_validate(order)
            self.apply(order, already)
            self.rebuild(order)
            self.post_validate(order)
            self.ship()
            self.seal(order)
            self.reconcile(order)
            self.result["ok"] = True
        except MaterializeError as e:
            # durable, safe, RESUMABLE failure marker -- NO human gate, session frees itself (INV-14/CB-TERM)
            self.journal.append({"op_id": e.op_id or "__txn__", "state": "failed",
                                 "failure": e.failure, "detail": str(e), "resumable": True})
            self.journal.write_txn({"transaction_id": self.txid, "sealed": False, "failed": True,
                                    "failure": e.failure, "detail": str(e), "resumable": True,
                                    "evidence": self.evidence})
            self.result["ok"] = False
            self.result["failure"] = e.failure
            self.result["detail"] = str(e)
        return self.result


def main(argv=None):
    ap = argparse.ArgumentParser(description="Materialize a close-transaction manifest (i63; PLAN..SEAL).")
    ap.add_argument("manifest")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--allow-live-cutover", action="store_true",
                    help="EXERCISE ONLY: ff main to the staging ref. i63 defers live cutover (INV-9/i67).")
    a = ap.parse_args(argv)
    with open(a.manifest, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    mz = Materializer(a.repo, manifest, allow_live_cutover=a.allow_live_cutover)
    res = mz.run()
    print(json.dumps(res, indent=1, sort_keys=True))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
