#!/usr/bin/env python3
"""ops/audit/doc-commit-gate.py -- M2-A deterministic, fail-closed doc-hygiene commit gate.

Enforces DOC_PROTOCOL.md section 2 (per-doc size budgets) and section 3 (accretion rules) over a
git commit's staged doc content, BEFORE the commit lands. Pure Python standard library only.
Reuses ops/audit/gen-doc-health.py::parse_budgets() for the DOC_PROTOCOL s2 budget table (do not
re-implement the table parse).

Governing spec: core-docs/research/2026-08-07-i41-m2a-doc-gate-scope.md (i42 build).

USAGE
-----
  python ops/audit/doc-commit-gate.py --staged   [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
  python ops/audit/doc-commit-gate.py --files F [F ...] [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
  python ops/audit/doc-commit-gate.py --worktree [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
  python ops/audit/doc-commit-gate.py --install-hook [--repo PATH]

Exactly one of --staged / --files / --worktree / --install-hook is required.

  --staged      Check the current git INDEX (staged set): `git diff --cached --name-only
                --diff-filter=ACMR`. This is what the installed .git/hooks/pre-commit calls.
                Budget/size checks read the STAGED BLOB bytes (git cat-file), never the working
                tree, since they can legitimately differ mid-commit.
  --files       Check an explicit named list AS IF it were the staged set restricted to those
                paths (same staged-blob semantics as --staged). This is what the SECONDARY
                commit-task invocation calls, on the same named files it is about to `git commit`.
                A named file with no entry in the staged diff is a gate error (fail-closed --
                the caller asked to check something that is not actually staged).
  --worktree    Local dry-run: check the CURRENT WORKING-TREE bytes of core-docs/**/*.md instead
                of the git index (no commit needed). Diff/added-line checks (accretion, index
                density) compare the working tree against HEAD. Never used by the installed hook.
  --install-hook
                Idempotently (re)write .git/hooks/pre-commit to the canonical hook body (see
                HOOK_CONTENT below) and (re)write ops/audit/doc-gate-hook.sha256 with its digest.
                This is what ops/install-doc-gate.bat shells out to; the .bat has no embedded
                hook text of its own, so there is exactly one canonical hook body (this module).

  --message / --message-file
                The exact text of the commit message THIS invocation is gating, if known. Needed
                for GATE_OVERRIDE and the re-layer note reference (see NOTE below). Optional.
  --date        Pin a date string into log rows (deterministic; default omits a date field).

EXIT CODES
----------
  0  PASS   (report may still contain WARN lines -- a WARN never changes the exit code)
  1  REJECT (>=1 check failed; the report on stdout names every offending file/rule)
  2  GATE ERROR (the gate could not complete its own checks -- git plumbing failed, a staged
     blob could not be read, parse_budgets() raised, etc.). A gate error is FAIL-CLOSED: it is
     treated exactly like a reject by every caller (non-zero exit), it just could not produce a
     normal report. Never silently exits 0 on internal failure.

REPORT FORMAT
-------------
One JSON object per line on stdout, sorted deterministically by (file, rule, severity) so
identical input produces a byte-identical report on repeated runs (no clock/random in the body).
Fields: file, rule, severity ("reject"|"warn"), measured, budget, delta, detail. A short
human-readable summary additionally goes to stderr. On a GATE ERROR, stdout carries a single
`{"error": "..."}` line instead.

KNOWN LIMITATION (stated plainly, per the acceptance report requirement) -- commit-message
visibility in the PRIMARY (pre-commit hook) path
----------------------------------------------------------------------------------------------
git's pre-commit hook runs BEFORE the commit message is collected (verified empirically: no env
var, argv, or `.git/COMMIT_EDITMSG` carries the message-in-progress at pre-commit time -- the
COMMIT_EDITMSG file, when present at all, holds the PREVIOUS commit attempt's stale text). This
is a real git architectural fact, not an oversight here. Consequence: when this gate is invoked
via `--staged` with no `--message`/`--message-file` (i.e. the installed pre-commit hook, its
normal mode), GATE_OVERRIDE and the re-layer note reference can never be honored -- an over-budget
or over-40KB staged doc is REJECTED unconditionally in that path, fail-closed. The override /
re-layer escape hatches are only reachable through the SECONDARY `--files` invocation (the
orchestrator's commit-task script, which constructs the commit message itself and can pass it via
--message/--message-file before it ever calls `git commit`), or by re-running this gate by hand
with --message before committing. This is a deliberate design resolution of a real constraint, not
an unimplemented feature -- it also matches the "no silent bypass" principle: a hook that can't see
the message cannot be tricked by one either.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

KB = 1000
RESEARCH_BUDGET_KB = 10
FANOUT_BUDGET_KB = 8
RELAYER_THRESHOLD_BYTES = 40000  # D-0094 proportional-budget / re-layer trigger (named constant)
INDEX_DENSITY_MAX_CHARS = 200
RELAYER_NOTE_RE = re.compile(r"research/[^\s]*-relayer-[^\s]*\.md")
OVERRIDE_RE = re.compile(r"GATE_OVERRIDE:\s*(D-\d{4,})")
LAST_UPDATED_RE = re.compile(r"^\s*\**last[- ]updated\b", re.I)

# ---------------------------------------------------------------------------
# The ONE canonical .git/hooks/pre-commit body. ASCII, LF line endings, no
# machine-specific absolute paths baked in (resolves its own repo root).
# doc-gate-hook.sha256 is the sha256 hex digest of exactly these bytes.
# ---------------------------------------------------------------------------
HOOK_CONTENT = (
    "#!/bin/sh\n"
    "# Installed by ops/install-doc-gate.bat -- Life Orchestrator doc-hygiene commit gate (M2-A).\n"
    "# Do not hand-edit; re-run ops/install-doc-gate.bat to update. Presence/hash asserted by\n"
    "# ops/audit/gen-doc-health.py against ops/audit/doc-gate-hook.sha256.\n"
    "REPO_ROOT=\"$(cd \"$(dirname \"$0\")/../..\" && pwd)\"\n"
    "PY=python\n"
    "command -v python >/dev/null 2>&1 || PY=python3\n"
    "\"$PY\" \"$REPO_ROOT/ops/audit/doc-commit-gate.py\" --staged --repo \"$REPO_ROOT\"\n"
    "exit $?\n"
)


class GateError(Exception):
    """Raised on any condition where the gate cannot complete its own checks (fail-closed)."""


# ---------------------------------------------------------------------------
# git plumbing
# ---------------------------------------------------------------------------
def find_repo_root(explicit):
    if explicit:
        return os.path.abspath(explicit)
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                              text=True, timeout=20)
    except OSError as e:
        raise GateError("git not runnable: %s" % e)
    if out.returncode != 0:
        raise GateError("not inside a git repo (git rev-parse --show-toplevel failed): %s"
                         % out.stderr.strip())
    return out.stdout.strip()


def run_git(repo, args, allow_fail=False):
    try:
        p = subprocess.run(["git"] + args, cwd=repo, capture_output=True, text=True, timeout=30)
    except OSError as e:
        raise GateError("git invocation failed (%s): %s" % (args, e))
    if p.returncode != 0 and not allow_fail:
        raise GateError("git %s failed: %s" % (" ".join(args), p.stderr.strip()))
    return p


def run_git_bytes(repo, args):
    try:
        p = subprocess.run(["git"] + args, cwd=repo, capture_output=True, timeout=30)
    except OSError as e:
        raise GateError("git invocation failed (%s): %s" % (args, e))
    if p.returncode != 0:
        raise GateError("git %s failed: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout


def git_head(repo):
    p = run_git(repo, ["log", "-1", "--format=%h"], allow_fail=True)
    return p.stdout.strip() or "unknown"


def staged_status_map(repo):
    """path (posix, relative to repo root) -> status letter (A/M/D/R/C/...) for the whole index."""
    out = run_git(repo, ["diff", "--cached", "--name-status", "-z", "--find-renames"]).stdout
    parts = [x for x in out.split("\0") if x]
    m = {}
    i = 0
    while i < len(parts):
        status = parts[i]
        letter = status[0]
        if letter in ("R", "C"):
            # status, old_path, new_path
            new_path = parts[i + 2]
            m[new_path] = letter
            i += 3
        else:
            path = parts[i + 1]
            m[path] = letter
            i += 2
    return m


def staged_blob_text(repo, path):
    try:
        raw = run_git_bytes(repo, ["cat-file", "-p", ":%s" % path])
    except GateError:
        raise GateError("could not read staged blob for %r (not in the index?)" % path)
    return raw.decode("utf-8", "replace")


def staged_diff_added_lines(repo, path):
    """[(new_lineno, text), ...] for '+' lines in `git diff --cached -U0 -- path`."""
    out = run_git(repo, ["diff", "--cached", "-U0", "--", path], allow_fail=True).stdout
    return _parse_added_lines(out)


def worktree_diff_added_lines(repo, path):
    """Added lines of the working tree vs HEAD (for --worktree dry runs)."""
    out = run_git(repo, ["diff", "-U0", "HEAD", "--", path], allow_fail=True).stdout
    if not out.strip():
        # untracked (no HEAD blob) -- every line in the file counts as "added"
        head_check = run_git(repo, ["cat-file", "-e", "HEAD:%s" % path], allow_fail=True)
        if head_check.returncode != 0:
            full = read_worktree_text(repo, path)
            return [(i + 1, l) for i, l in enumerate(full.splitlines())]
    return _parse_added_lines(out)


def _parse_added_lines(diff_text):
    added = []
    new_lineno = None
    for line in diff_text.splitlines():
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if m:
            new_lineno = int(m.group(1))
            continue
        if new_lineno is None:
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            added.append((new_lineno, line[1:]))
            new_lineno += 1
        elif line.startswith("-"):
            pass  # deleted line: does not consume a new-file line number
        else:
            new_lineno += 1
    return added


def read_worktree_text(repo, path):
    full = os.path.join(repo, path)
    try:
        with open(full, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError as e:
        raise GateError("could not read worktree file %r: %s" % (path, e))


def doc_protocol_s2_touched_staged(repo):
    status = staged_status_map(repo)
    if "core-docs/DOC_PROTOCOL.md" not in status or status["core-docs/DOC_PROTOCOL.md"] == "D":
        return False
    return _s2_hunk_overlap(staged_blob_text(repo, "core-docs/DOC_PROTOCOL.md"),
                             run_git(repo, ["diff", "--cached", "-U0", "--", "core-docs/DOC_PROTOCOL.md"]).stdout)


def doc_protocol_s2_touched_files(repo, files):
    if "core-docs/DOC_PROTOCOL.md" not in files:
        return False
    return _s2_hunk_overlap(staged_blob_text(repo, "core-docs/DOC_PROTOCOL.md"),
                             run_git(repo, ["diff", "--cached", "-U0", "--", "core-docs/DOC_PROTOCOL.md"]).stdout)


def _s2_hunk_overlap(staged_text, diff_text):
    lines = staged_text.splitlines()
    start = end = None
    for i, l in enumerate(lines):
        if start is None and re.match(r"^##\s*2\.", l):
            start = i  # 0-based; section header line itself
        elif start is not None and re.match(r"^##\s*3\.", l):
            end = i - 1
            break
    if start is None:
        return False
    if end is None:
        end = len(lines) - 1
    lo, hi = start + 1, end + 1  # 1-based inclusive line range of section 2
    for m in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff_text, re.M):
        c = int(m.group(1))
        d = int(m.group(2)) if m.group(2) is not None else 1
        if d == 0:
            new_start = new_end = c  # pure-deletion hunk: insertion point c
        else:
            new_start, new_end = c, c + d - 1
        if new_start <= hi and new_end >= lo:
            return True
    return False


# ---------------------------------------------------------------------------
# parse_budgets() reuse (import gen-doc-health.py by path -- hyphenated filename)
# ---------------------------------------------------------------------------
def load_parse_budgets(repo):
    path = os.path.join(repo, "ops", "audit", "gen-doc-health.py")
    if not os.path.isfile(path):
        raise GateError("cannot locate ops/audit/gen-doc-health.py to reuse parse_budgets()")
    spec = importlib.util.spec_from_file_location("gen_doc_health_for_gate", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:
        raise GateError("gen-doc-health.py failed to import: %s" % e)
    if not hasattr(mod, "parse_budgets"):
        raise GateError("gen-doc-health.py has no parse_budgets()")
    # parse_budgets() reads core-docs/DOC_PROTOCOL.md straight off disk (the CURRENT worktree
    # copy). That is correct for --worktree; for --staged/--files we want the STAGED budget
    # table, so re-parse against the staged blob when DOC_PROTOCOL.md differs from HEAD-index.
    return mod


def parse_budgets_from_text(text):
    """Same regex as gen-doc-health.py::parse_budgets(), applied to arbitrary text (the staged
    blob) instead of the worktree file, so budget lookups see the budgets AS THEY WILL BE
    immediately after this commit lands, not a possibly-stale worktree copy."""
    budgets = {}
    for m in re.finditer(r"^\|\s*([A-Za-z0-9_./<>&;-]+\.md)\s*\|[^|]*\|\s*([^|]+?)\s*\|", text, re.M):
        doc, b = m.group(1), m.group(2)
        km = re.search(r"(\d+)\s*KB", b)
        budgets[doc] = int(km.group(1)) if km else None
    return budgets


# ---------------------------------------------------------------------------
# classification
# ---------------------------------------------------------------------------
EXEMPT, CORE, RESEARCH, FANOUT, UNLISTED, UNCAPPED = (
    "exempt", "core", "research", "fanout", "unlisted", "uncapped")


def classify(path, budgets):
    """-> (kind, budget_bytes_or_None)"""
    top = path.split("/", 1)[0]
    if top in ("archive", "modules", "widgets"):
        return EXEMPT, None
    if not path.endswith(".md"):
        return EXEMPT, None
    if not path.startswith("core-docs/"):
        return EXEMPT, None
    rest = path[len("core-docs/"):]
    if rest == "DECISION_LOG.md":
        return EXEMPT, None
    if rest.startswith("research/"):
        return RESEARCH, RESEARCH_BUDGET_KB * KB
    base = os.path.basename(rest)
    if rest.startswith("fanout/") and re.match(r"FANOUT_AGENT_.*\.md$", base):
        return FANOUT, FANOUT_BUDGET_KB * KB
    budget = budgets.get(base, "MISSING")
    if budget == "MISSING":
        return UNLISTED, None
    if budget is None:
        return UNCAPPED, None
    return CORE, budget * KB


# ---------------------------------------------------------------------------
# findings
# ---------------------------------------------------------------------------
def reject(file, rule, measured=None, budget=None, delta=None, detail=None):
    return {"file": file, "rule": rule, "severity": "reject", "measured": measured,
            "budget": budget, "delta": delta, "detail": detail}


def warn(file, rule, measured=None, budget=None, delta=None, detail=None):
    return {"file": file, "rule": rule, "severity": "warn", "measured": measured,
            "budget": budget, "delta": delta, "detail": detail}


def extract_override_id(message):
    if not message:
        return None
    m = OVERRIDE_RE.search(message)
    return m.group(1) if m else None


def override_id_exists(d_id, decision_log_text):
    return re.search(r"\b%s\b" % re.escape(d_id), decision_log_text) is not None


# ---------------------------------------------------------------------------
# the gate over one already-resolved (path, kind, budget, measured, added_lines, full_text) unit
# ---------------------------------------------------------------------------
def gate_one(unit, message, decision_log_text, doc_protocol_touched, findings, honored_overrides):
    path, kind, budget_bytes, measured, full_text, added_lines = unit

    if kind == UNLISTED:
        findings.append(warn(path, "unlisted_core_doc",
                              detail="no s2 budget -- add a DOC_PROTOCOL s2 row"))

    # BUDGET
    if kind in (CORE, RESEARCH, FANOUT) and budget_bytes is not None and measured > budget_bytes:
        delta = measured - budget_bytes
        d_id = extract_override_id(message)
        if d_id and doc_protocol_touched and decision_log_text is not None \
                and override_id_exists(d_id, decision_log_text):
            honored_overrides.append({"file": path, "measured": measured, "budget": budget_bytes,
                                       "rule": "budget", "d_id": d_id})
        else:
            findings.append(reject(path, "budget", measured=measured, budget=budget_bytes, delta=delta))

    # RE-LAYER TRIGGER (D-0094) -- independent of the s2 budget check above
    if kind != EXEMPT and measured > RELAYER_THRESHOLD_BYTES:
        if not (message and RELAYER_NOTE_RE.search(message)):
            findings.append(reject(path, "relayer_40kb", measured=measured,
                                    budget=RELAYER_THRESHOLD_BYTES,
                                    delta=measured - RELAYER_THRESHOLD_BYTES))

    # ACCRETION TRIPWIRES
    if kind != EXEMPT:
        for lineno, text in added_lines:
            if "[prior]" in text:
                findings.append(reject(path, "accretion_prior_chain", detail="line %d" % lineno))
                break
        match_lines = [i for i, l in enumerate(full_text.splitlines()) if LAST_UPDATED_RE.search(l)]
        if len(match_lines) >= 2:
            stacked = any(match_lines[i + 1] - match_lines[i] <= 3 for i in range(len(match_lines) - 1))
            added_linenos = {ln for ln, _ in added_lines}
            touched = any((i + 1) in added_linenos for i in match_lines)
            if stacked and touched:
                findings.append(reject(path, "accretion_stacked_last_updated",
                                        measured=len(match_lines),
                                        detail="lines %s" % [i + 1 for i in match_lines]))

    # INDEX DENSITY (warn only)
    if os.path.basename(path) == "DECISION_LOG_INDEX.md":
        for lineno, text in added_lines:
            if len(text) > INDEX_DENSITY_MAX_CHARS:
                findings.append(warn(path, "index_density", measured=len(text),
                                      budget=INDEX_DENSITY_MAX_CHARS, detail="line %d" % lineno))


# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------
def gather_units_staged(repo, restrict_to=None):
    status = staged_status_map(repo)
    budgets_worktree = None
    dp_staged_text = None
    if "core-docs/DOC_PROTOCOL.md" in status and status["core-docs/DOC_PROTOCOL.md"] != "D":
        dp_staged_text = staged_blob_text(repo, "core-docs/DOC_PROTOCOL.md")
        budgets = parse_budgets_from_text(dp_staged_text)
    else:
        gdh = load_parse_budgets(repo)
        budgets = gdh.parse_budgets()

    paths = restrict_to if restrict_to is not None else sorted(status)
    units = []
    for path in paths:
        letter = status.get(path)
        if restrict_to is not None and letter is None:
            raise GateError("--files named %r but it is not in the staged diff (git diff --cached)" % path)
        if letter == "D":
            continue  # a pure deletion is never over-budget -- allow, no report line
        kind, budget_bytes = classify(path, budgets)
        if kind == EXEMPT:
            continue
        full_text = staged_blob_text(repo, path)
        measured = len(full_text.encode("utf-8"))
        added = staged_diff_added_lines(repo, path)
        units.append((path, kind, budget_bytes, measured, full_text, added))
    return units


def gather_units_worktree(repo):
    core = os.path.join(repo, "core-docs")
    gdh = load_parse_budgets(repo)
    budgets = gdh.parse_budgets()
    units = []
    for root, _dirs, files in os.walk(core):
        for fn in sorted(files):
            if not fn.endswith(".md"):
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, repo).replace(os.sep, "/")
            kind, budget_bytes = classify(rel, budgets)
            if kind == EXEMPT:
                continue
            text = read_worktree_text(repo, rel)
            measured = len(text.encode("utf-8"))
            added = worktree_diff_added_lines(repo, rel)
            units.append((rel, kind, budget_bytes, measured, text, added))
    units.sort(key=lambda u: u[0])
    return units


def decision_log_text_for(repo, prefer_staged):
    status = staged_status_map(repo) if prefer_staged else {}
    if "core-docs/DECISION_LOG.md" in status and status["core-docs/DECISION_LOG.md"] != "D":
        return staged_blob_text(repo, "core-docs/DECISION_LOG.md")
    path = os.path.join(repo, "core-docs", "DECISION_LOG.md")
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    return None


def append_log_rows(repo, rows):
    if not rows:
        return
    out_dir = os.path.join(repo, "ops", "out")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "doc-gate-log.jsonl")
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            fh.write(json.dumps(row, separators=(",", ":"), sort_keys=True) + "\n")


def emit_report(findings):
    findings_sorted = sorted(findings, key=lambda f: (f["file"], f["rule"], f["severity"]))
    for f in findings_sorted:
        sys.stdout.write(json.dumps(f, separators=(",", ":"), sort_keys=True) + "\n")
    rejects = [f for f in findings_sorted if f["severity"] == "reject"]
    warns = [f for f in findings_sorted if f["severity"] == "warn"]
    if rejects:
        print("doc-commit-gate: REJECT (%d finding%s, %d warning%s)" %
              (len(rejects), "" if len(rejects) == 1 else "s",
               len(warns), "" if len(warns) == 1 else "s"), file=sys.stderr)
        for f in rejects:
            print("  REJECT %s [%s] measured=%s budget=%s delta=%s %s" %
                  (f["file"], f["rule"], f["measured"], f["budget"], f["delta"], f["detail"] or ""),
                  file=sys.stderr)
    else:
        print("doc-commit-gate: PASS (%d warning%s)" %
              (len(warns), "" if len(warns) == 1 else "s"), file=sys.stderr)
    for f in warns:
        print("  WARN %s [%s] %s" % (f["file"], f["rule"], f["detail"] or ""), file=sys.stderr)
    return 1 if rejects else 0


# ---------------------------------------------------------------------------
# install-hook
# ---------------------------------------------------------------------------
def install_hook(repo):
    hooks_dir = os.path.join(repo, ".git", "hooks")
    if not os.path.isdir(hooks_dir):
        raise GateError("no .git/hooks directory under %r -- is this a git repo?" % repo)
    hook_path = os.path.join(hooks_dir, "pre-commit")
    digest = hashlib.sha256(HOOK_CONTENT.encode("ascii")).hexdigest()
    existing = None
    if os.path.isfile(hook_path):
        with open(hook_path, "rb") as fh:
            existing = fh.read()
    changed = existing != HOOK_CONTENT.encode("ascii")
    if changed:
        with open(hook_path, "wb") as fh:
            fh.write(HOOK_CONTENT.encode("ascii"))
        try:
            os.chmod(hook_path, 0o755)
        except OSError:
            pass
    manifest_dir = os.path.join(repo, "ops", "audit")
    os.makedirs(manifest_dir, exist_ok=True)
    manifest_path = os.path.join(manifest_dir, "doc-gate-hook.sha256")
    manifest_line = "%s  pre-commit\n" % digest
    manifest_changed = True
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r", encoding="ascii") as fh:
            manifest_changed = fh.read() != manifest_line
    if manifest_changed:
        with open(manifest_path, "w", encoding="ascii", newline="\n") as fh:
            fh.write(manifest_line)
    print("hook %s (sha256 %s)" % ("installed/updated" if changed else "already up to date", digest))
    print("manifest %s: %s" % ("written" if manifest_changed else "already current", manifest_path))
    return 0


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def build_argparser():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--staged", action="store_true")
    mode.add_argument("--files", nargs="+", metavar="PATH")
    mode.add_argument("--worktree", action="store_true")
    mode.add_argument("--install-hook", action="store_true")
    ap.add_argument("--repo", default=None)
    msg = ap.add_mutually_exclusive_group()
    msg.add_argument("--message", default=None)
    msg.add_argument("--message-file", default=None)
    ap.add_argument("--date", default=None)
    return ap


def resolve_message(args):
    if args.message is not None:
        return args.message
    if args.message_file:
        with open(args.message_file, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    return None


def main(argv=None):
    ap = build_argparser()
    args = ap.parse_args(argv)
    try:
        repo = find_repo_root(args.repo)

        if args.install_hook:
            return install_hook(repo)

        message = resolve_message(args)
        findings = []
        honored = []

        if args.staged:
            units = gather_units_staged(repo)
            dp_touched = doc_protocol_s2_touched_staged(repo)
            dlog_text = decision_log_text_for(repo, prefer_staged=True)
        elif args.files:
            norm = [p.replace(os.sep, "/") for p in args.files]
            units = gather_units_staged(repo, restrict_to=norm)
            dp_touched = doc_protocol_s2_touched_files(repo, norm)
            dlog_text = decision_log_text_for(repo, prefer_staged=True)
        else:  # worktree
            units = gather_units_worktree(repo)
            dp_touched = False  # message-gated bypasses are not evaluated in local dry-run mode
            dlog_text = decision_log_text_for(repo, prefer_staged=False)

        for unit in units:
            gate_one(unit, message, dlog_text, dp_touched, findings, honored)

        if honored:
            date_or_head = args.date or git_head(repo)
            rows = [dict(row, date=date_or_head) for row in honored]
            append_log_rows(repo, rows)
            for row in honored:
                print("doc-commit-gate: OVERRIDE HONORED %s [%s] via %s" %
                      (row["file"], row["rule"], row["d_id"]), file=sys.stderr)

        return emit_report(findings)

    except GateError as e:
        print(json.dumps({"error": str(e)}, sort_keys=True))
        print("doc-commit-gate: GATE ERROR (fail-closed): %s" % e, file=sys.stderr)
        return 2
    except Exception as e:  # noqa: BLE001 -- fail-closed on literally anything unexpected
        print(json.dumps({"error": "unexpected: %r" % e}, sort_keys=True))
        print("doc-commit-gate: UNEXPECTED GATE ERROR (fail-closed): %r" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
