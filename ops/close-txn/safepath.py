#!/usr/bin/env python3
"""safepath.py -- ONE fail-closed path + input policy for the close-transaction subsystem (i63, D-0163).

The single chokepoint the validator (static, lexical) and the materializer (execution, with a real repo
root) both call, so no divergent lists of protected fields exist. Applied to EVERY path-bearing field a
manifest can carry -- header.ledger_ref, a content op target / backing_ref / string payload_ref, and the
nested path-bearing keys inside payload_ref config (files / evidence / ledger / generator / paths / inputs
/ backing_ref) -- and to the transaction_id BEFORE any filesystem side effect (a Journal directory is only
built after the id and manifest validate).

Rejects, fail-closed (i63 corrective, replacing the too-narrow i62/first-i63 guard):
  - a non-string where a path is expected (an integer backing_ref, an object ledger_ref) -- TYPE first
  - empty / NUL
  - parent traversal (`..`) at any depth
  - POSIX-absolute (`/x`), rooted (`\\x`)
  - Windows drive-relative / drive-absolute (`C:x`, `C:\\x`, `C:/x`)
  - UNC / device / network (`\\\\server\\share`, `//server/share`, `\\\\?\\`, `\\\\.\\`)
  - the `.git` directory and its case aliases (`.GIT`, `.Git`) at ANY depth (Windows case-insensitive)
  - a symlink / NTFS junction / mount / reparse transition anywhere on the resolved prefix, and the same
    for every member visited during directory identity hashing -- never lexical normalization alone
  - anything whose fully-resolved real path escapes the authorized repository root(s)

stdlib only. Deterministic. The realpath / lstat calls are the only filesystem touch, and only for
containment + reparse detection.
"""
import os
import re
import stat

_DRIVE_RE = re.compile(r"^[A-Za-z]:")            # C:  C:\  C:/  C:x  (drive-relative or -absolute)
_UNC_RE = re.compile(r"^(\\\\|//)")               # \\server  //server  \\?\  \\.\
# strict transaction_id grammar: close-i<N>-<slug>, slug is a bounded separator-free token
_TXID_RE = re.compile(r"^close-i([0-9]{1,9})-[A-Za-z0-9._-]{1,80}$")

# path-bearing keys screened wherever they appear (recursively) inside an op's config / payload_ref.
# NOTE: deliberately NOT ambiguous keys like "source" (stamp's source is 'post-cutover-head', not a path)
# or "predicate". An unsupported nested structure that could name a path is rejected, never ignored.
PATH_KEYS = {"files", "evidence", "ledger", "backing_ref", "generator", "paths", "inputs", "payload_path",
             "ledger_ref", "path", "targets"}


class PathSafetyError(ValueError):
    def __init__(self, rel, reason):
        self.rel = rel
        self.reason = reason
        super().__init__("unsafe path %r: %s" % (rel, reason))


class TxidError(ValueError):
    pass


def validate_txid(txid, iteration=None):
    """Validate the transaction_id BEFORE any filesystem side effect. Strict, bounded, separator-free, and
    (when iteration is given) bound to header.iteration. Raises TxidError; never touches the filesystem."""
    if not isinstance(txid, str) or not txid:
        raise TxidError("transaction_id must be a non-empty string (got %r)" % (txid,))
    if any(c in txid for c in ("/", "\\", "\x00")) or ".." in txid:
        raise TxidError("transaction_id must not contain path separators, NUL, or '..' (got %r)" % txid)
    m = _TXID_RE.match(txid)
    if not m:
        raise TxidError("transaction_id must match close-i<N>-<slug> with a bounded separator-free slug "
                        "(got %r)" % txid)
    if iteration is not None and int(m.group(1)) != int(iteration):
        raise TxidError("transaction_id iteration i%s != header.iteration %s" % (m.group(1), iteration))
    return txid


def _norm_slashes(p):
    return p.replace("\\", "/")


def classify_unsafe(rel):
    """Lexical rejects (identical on POSIX + Windows). Returns a reason string or None. A non-string is a
    hard reject here too (callers should type-check, but this is the backstop)."""
    if rel is None or not isinstance(rel, str):
        return "path is not a string (a non-string path field is rejected)"
    if rel == "":
        return "empty path"
    if "\x00" in rel:
        return "contains a NUL byte"
    if _DRIVE_RE.match(rel):
        return "Windows drive path is not repo-relative"
    if _UNC_RE.match(rel):
        return "UNC / device / network path is not repo-relative"
    s = _norm_slashes(rel)
    if s.startswith("/"):
        return "absolute / rooted path is not repo-relative"
    parts = [c for c in s.split("/") if c != ""]
    if any(c == ".." for c in parts):
        return "parent traversal ('..') is forbidden"
    if any(c.lower() == ".git" for c in parts):
        return "the .git directory is protected (case-insensitive, any depth)"
    if not parts or all(c == "." for c in parts):
        return "path does not name a target inside the repo"
    return None


def _is_reparse(path):
    """True if `path` is a symlink OR (Windows) a junction / mount / reparse point."""
    try:
        st = os.lstat(path)
    except OSError:
        return False
    if stat.S_ISLNK(st.st_mode):
        return True
    tag = getattr(st, "st_reparse_tag", 0)  # Windows (Python 3.8+): non-zero for junction/mount/reparse
    return bool(tag)


def _real(p):
    return os.path.realpath(p)


def _within(child_abs, parent_abs):
    try:
        return os.path.commonpath([child_abs, parent_abs]) == parent_abs
    except ValueError:
        return False


def _reject_reparse_prefix(repo_real, cand_abs):
    """Walk each EXISTING component from repo_real down toward cand_abs; reject if any is a reparse point.
    Defeats a junction/symlink introduced mid-path even when realpath would still land inside the repo."""
    rel = os.path.relpath(cand_abs, repo_real)
    if rel == os.curdir:
        return
    cur = repo_real
    for comp in rel.split(os.sep):
        if comp in ("", os.curdir):
            continue
        cur = os.path.join(cur, comp)
        if os.path.lexists(cur) and _is_reparse(cur):
            raise PathSafetyError(rel, "path crosses a symlink/junction/reparse point (%s)" % comp)


def safe_repo_path(repo_root, rel, allow_roots=None):
    """Resolve `rel` to an absolute path INSIDE repo_root (or an explicitly authorized allow_root that is
    itself within repo_root) and return it, or raise PathSafetyError. A manifest string can never grant
    itself a new root: allow_roots are supplied by the caller, not by the manifest."""
    reason = classify_unsafe(rel)
    if reason:
        raise PathSafetyError(rel, reason)

    repo_real = _real(repo_root)
    roots = [repo_real]
    for r in (allow_roots or []):
        rr = _real(r)
        if not _within(rr, repo_real):
            raise PathSafetyError(rel, "authorized root %r is outside the repo" % r)
        roots.append(rr)

    candidate = os.path.join(repo_real, _norm_slashes(rel).replace("/", os.sep))
    cand_real = _real(candidate)
    if not any(_within(cand_real, root) for root in roots):
        raise PathSafetyError(rel, "resolves outside the authorized repository root(s)")

    # protected .git after resolution (a symlink INTO .git, case-insensitive)
    rel_from_repo = os.path.relpath(cand_real, repo_real)
    low = rel_from_repo.replace("\\", "/").lower()
    if low == ".git" or low.startswith(".git/"):
        raise PathSafetyError(rel, "resolves into the protected .git directory")

    # reject a reparse transition anywhere on the existing prefix (not lexical-only)
    root_for_prefix = next((rt for rt in roots if _within(cand_real, rt)), repo_real)
    _reject_reparse_prefix(root_for_prefix, cand_real)
    return cand_real


def is_safe(repo_root, rel, allow_roots=None):
    try:
        safe_repo_path(repo_root, rel, allow_roots=allow_roots)
        return True
    except PathSafetyError:
        return False


# ---------------------------------------------------------------------------- op-wide path screening
def _iter_path_values(obj):
    """Yield every value found under a PATH_KEYS key, recursively, as (key, value)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in PATH_KEYS:
                yield k, v
            if isinstance(v, (dict, list)):
                for kv in _iter_path_values(v):
                    yield kv
    elif isinstance(obj, list):
        for it in obj:
            if isinstance(it, (dict, list)):
                for kv in _iter_path_values(it):
                    yield kv


CONTENT_KINDS = {"append", "replace_section", "create"}


def op_path_refs(op, header=None):
    """Return the list of (label, value) path-bearing references an op (and optionally the header) carries.
    A value may be a string path, a list of string paths, or a non-string that a path was expected for
    (which the checker must reject). This is the ONE enumerator both the validator and materializer use."""
    refs = []
    if header is not None:
        refs.append(("header.ledger_ref", header.get("ledger_ref")))
    kind = op.get("kind")
    if kind in CONTENT_KINDS:
        refs.append(("%s.target" % op.get("op_id"), op.get("target")))
        pr = op.get("payload_ref")
        if isinstance(pr, str):
            refs.append(("%s.payload_ref" % op.get("op_id"), pr))
        elif isinstance(pr, dict) and "inline" not in pr:
            # a content op whose payload_ref is a non-inline object with no recognized path -> flagged below
            pass
    if "backing_ref" in op:
        refs.append(("%s.backing_ref" % op.get("op_id"), op.get("backing_ref")))
    # nested config (payload_ref dicts for validator/rebuild/etc, and any nested path keys)
    for container_key in ("payload_ref", "task_spec"):
        c = op.get(container_key)
        if isinstance(c, (dict, list)):
            for k, v in _iter_path_values(c):
                refs.append(("%s.%s.%s" % (op.get("op_id"), container_key, k), v))
    return refs


def screen_refs(refs, checker):
    """Apply `checker` (classify_unsafe for static; a repo-bound closure for execution) to each ref value.
    A list expands to its members. A non-string where a path is expected is a hard finding. Returns a list
    of finding strings ([] == all safe). `checker(value)` returns a reason string or None."""
    findings = []
    for label, val in refs:
        if val is None:
            if label.endswith(".target") or label == "header.ledger_ref":
                findings.append("%s is missing (a required path)" % label)
            continue
        vals = val if isinstance(val, list) else [val]
        for v in vals:
            if not isinstance(v, str):
                findings.append("%s must be a string path (got %r)" % (label, type(v).__name__))
                continue
            reason = checker(v)
            if reason:
                findings.append("%s unsafe: %s (%r)" % (label, reason, v))
    return findings


# ---------------------------------------------------------------------------- confined directory identity
def dir_identity(repo_root, rel, allow_roots=None):
    """Deterministic native-byte identity of a directory (or file) over ONLY safely-confined members.
    Rejects (raises PathSafetyError) if any traversed directory or file member is a symlink / junction /
    reparse point -- never follows one out of the tree (C63-10). Members are sorted by repo-relative path;
    each contributes rel-path + NUL + raw bytes + NUL. Returns (sha256_hexdigest, total_bytes)."""
    import hashlib
    base = safe_repo_path(repo_root, rel, allow_roots=allow_roots)
    if os.path.isfile(base) and not _is_reparse(base):
        with open(base, "rb") as fh:
            data = fh.read()
        return hashlib.sha256(data).hexdigest(), len(data)
    if not os.path.isdir(base):
        raise PathSafetyError(rel, "backing path does not resolve to a file or directory")
    h = hashlib.sha256()
    total = 0
    for root, dirs, files in os.walk(base, followlinks=False):
        # reject any reparse dir member before descending
        for d in list(dirs):
            p = os.path.join(root, d)
            if _is_reparse(p):
                raise PathSafetyError(os.path.relpath(p, base),
                                      "directory member is a symlink/junction/reparse point")
        dirs.sort()
        for fn in sorted(files):
            p = os.path.join(root, fn)
            if _is_reparse(p):
                raise PathSafetyError(os.path.relpath(p, base),
                                      "file member is a symlink/junction/reparse point")
            relm = os.path.relpath(p, base).replace(os.sep, "/")
            with open(p, "rb") as fh:
                b = fh.read()
            h.update(relm.encode("utf-8") + b"\0" + b + b"\0")
            total += len(b)
    return h.hexdigest(), total
