#!/usr/bin/env python3
"""safepath.py -- repository path-safety guard for the close-transaction subsystem (i63, D-0162).

Every filesystem reference a close manifest can name (an op `target`, a `backing_ref`, a `payload_ref`
path) MUST resolve to a real location INSIDE the authorized canonical repository (or an explicitly
authorized runtime root). This guard is the single chokepoint the validator (static) and the materializer
(before any write) both call, so the materializer can NEVER be handed a path that escapes the repo.

Hardened contract INV-8/F-1 reads native on-disk bytes; a path that escapes the repo, targets `.git`,
or dereferences a symlink/junction out of the tree would let a close read or write outside canonical.
This module rejects, before resolution is trusted:

  - parent traversal (`..` anywhere in the path)
  - absolute POSIX paths (`/etc/passwd`)
  - Windows drive-absolute paths (`C:\\Windows\\...`, `C:/Windows/...`)
  - UNC paths (`\\\\server\\share`, `//server/share`)
  - the protected `.git` directory (any component == `.git`)
  - a symlink / NTFS junction whose real target lands outside the authorized root(s)
  - anything else that resolves outside the permitted repo / authorized runtime roots

READ-ONLY (never touches the filesystem except `realpath`/`lstat` for containment + symlink checks).
stdlib only. Deterministic. No network, no clock.
"""
import os
import re

# A Windows drive-absolute prefix: a single letter, a colon, then a separator (or bare "C:").
_DRIVE_RE = re.compile(r"^[A-Za-z]:")
# A UNC prefix in either slash flavour.
_UNC_RE = re.compile(r"^(\\\\|//)")


class PathSafetyError(ValueError):
    """A manifest path is unsafe: it escapes the authorized repository root(s)."""

    def __init__(self, rel, reason):
        self.rel = rel
        self.reason = reason
        super().__init__("unsafe path %r: %s" % (rel, reason))


def _norm_slashes(p):
    return p.replace("\\", "/")


def classify_unsafe(rel):
    """Return a reason string if `rel` is structurally unsafe WITHOUT touching the filesystem, else None.

    This is the part that is identical on POSIX and Windows -- a manifest authored on one and executed on
    the other must be judged the same way, so drive/UNC/absolute are detected lexically, not via os.path.
    """
    if rel is None or not isinstance(rel, str) or rel == "":
        return "empty or non-string path"
    if "\x00" in rel:
        return "contains a NUL byte"
    if _DRIVE_RE.match(rel):
        return "Windows drive-absolute path is not repo-relative"
    if _UNC_RE.match(rel):
        return "UNC path is not repo-relative"
    s = _norm_slashes(rel)
    if s.startswith("/"):
        return "absolute path is not repo-relative"
    parts = [c for c in s.split("/") if c != ""]
    if any(c == ".." for c in parts):
        return "parent traversal ('..') is forbidden"
    if any(c == ".git" for c in parts):
        return "the .git directory is protected"
    if not parts or all(c == "." for c in parts):
        return "path does not name a target inside the repo"
    return None


def _real(p):
    # realpath resolves symlinks/junctions in the existing prefix and leaves a non-existent leaf literal.
    return os.path.realpath(p)


def _within(child_abs, parent_abs):
    """True iff child_abs is parent_abs or lives beneath it (both already realpath-resolved)."""
    try:
        return os.path.commonpath([child_abs, parent_abs]) == parent_abs
    except ValueError:
        # different drives on Windows -> commonpath raises -> not within
        return False


def safe_repo_path(repo_root, rel, allow_roots=None):
    """Resolve `rel` (a repo-relative path) to an absolute path INSIDE repo_root and return it.

    Raises PathSafetyError on any structural violation OR if the resolved real path (following symlinks/
    junctions) escapes repo_root and every explicitly authorized `allow_roots` entry. `allow_roots` are
    additional absolute roots (e.g. a runtime dir) that are themselves asserted to be within/at repo_root
    by the caller; they let a close reference an authorized-but-separate location without opening the door
    to arbitrary escape.
    """
    reason = classify_unsafe(rel)
    if reason:
        raise PathSafetyError(rel, reason)

    repo_real = _real(repo_root)
    roots = [repo_real]
    for r in (allow_roots or []):
        rr = _real(r)
        # an authorized root must itself be within the repo (defence in depth)
        if not _within(rr, repo_real):
            raise PathSafetyError(rel, "authorized root %r is itself outside the repo" % r)
        roots.append(rr)

    candidate = os.path.join(repo_real, _norm_slashes(rel).replace("/", os.sep))
    cand_real = _real(candidate)

    # containment after full symlink/junction resolution (defeats a symlink escape)
    if not any(_within(cand_real, root) for root in roots):
        raise PathSafetyError(rel, "resolves outside the authorized repository root(s)")

    # a resolved path must not re-enter .git (e.g. a symlink INTO .git)
    rel_from_repo = os.path.relpath(cand_real, repo_real)
    if rel_from_repo == ".git" or rel_from_repo.startswith(".git" + os.sep):
        raise PathSafetyError(rel, "resolves into the protected .git directory")

    return cand_real


def is_safe(repo_root, rel, allow_roots=None):
    """Boolean convenience wrapper."""
    try:
        safe_repo_path(repo_root, rel, allow_roots=allow_roots)
        return True
    except PathSafetyError:
        return False
