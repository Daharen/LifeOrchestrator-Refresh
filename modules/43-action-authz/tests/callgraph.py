"""
callgraph.py -- a deterministic stdlib-`ast` import/call-graph reachability analyzer over EVERY
action_authz module (contract s6 amendment 5; i40 red-team Finding 6a).

The i39 `no_path` oracle read only canon.py + monitor.py and regex-counted `authority_construct(` --
source-string pattern counting, NOT a reachability proof. This builds a real module-level call graph:
it resolves direct imports, aliases (`from . import canon`, `stores as S`, `from .monitor import
authorize`), attribute calls (`canon.authority_construct`, `S.PROFILES`, `self.method`), and reachable
helper functions from the ordinary entry points, then asserts the Authority constructor
`canon.authority_construct` is UNREACHABLE from the ordinary model path.

The unresolved-attribute edges are OVER-APPROXIMATED (an `x.method()` whose receiver type is unknown is
treated as reaching EVERY function named `method`). Over-approximation is the SAFE direction for a
no-path proof: it can only make MORE nodes reachable, so if the Authority constructor is still
unreachable under it, no ordinary path can reach it. Runtime fuzzing cannot prove "no path"; this reads
the source and proves it structurally.
"""

import ast
import os

MODULES = ("canon", "schemas", "stores", "monitor", "boundary")

# the ordinary model -> action path entry points (NOT the trusted authority-store write path).
ENTRYPOINTS = ("monitor.authorize", "boundary.MockExecutor.execute", "boundary.MockExecutor._run_permit",
               "boundary.MockCoordinator.propose", "boundary.evaluate_completion",
               "boundary.evaluate_completion_via_permit")

AUTHORITY_CONSTRUCTOR = "canon.authority_construct"


def _module_path(moddir, m):
    return os.path.join(moddir, "action_authz", m + ".py")


def build_call_graph(moddir):
    """Return (defs, edges): defs maps qualname -> ast node; edges maps caller qualname -> set(callee
    qualnames). Qualnames are `module.func` or `module.Class.method`."""
    trees = {}
    for m in MODULES:
        with open(_module_path(moddir, m), "r", encoding="utf-8") as fh:
            trees[m] = ast.parse(fh.read(), filename=m + ".py")

    aliases = {m: {} for m in MODULES}          # per module: local alias -> ("module", mod) | ("func", "mod.fn")
    defs = {}                                   # qualname -> ast FunctionDef node
    name_index = {}                             # bare fn/method name -> set(qualnames)

    def _register(qual, node):
        defs[qual] = node
        name_index.setdefault(qual.split(".")[-1], set()).add(qual)

    for m in MODULES:
        for node in trees[m].body:
            if isinstance(node, ast.ImportFrom):
                base = (node.module or "").lstrip(".")
                for alias in node.names:
                    asname = alias.asname or alias.name
                    if node.module is None:                 # from . import canon [as X]
                        if alias.name in MODULES:
                            aliases[m][asname] = ("module", alias.name)
                    elif base in MODULES:                   # from .monitor import authorize
                        aliases[m][asname] = ("func", "%s.%s" % (base, alias.name))
            elif isinstance(node, ast.FunctionDef):
                _register("%s.%s" % (m, node.name), node)
            elif isinstance(node, ast.ClassDef):
                for sub in node.body:
                    if isinstance(sub, ast.FunctionDef):
                        _register("%s.%s.%s" % (m, node.name, sub.name), sub)

    edges = {q: set() for q in defs}
    for qual, node in defs.items():
        m = qual.split(".")[0]
        amap = aliases[m]
        for call in ast.walk(node):             # ast.walk descends into nested defs (over-approx, safe)
            if not isinstance(call, ast.Call):
                continue
            f = call.func
            if isinstance(f, ast.Name):
                nm = f.id
                local = "%s.%s" % (m, nm)
                if local in defs:
                    edges[qual].add(local)
                elif nm in amap and amap[nm][0] == "func":
                    edges[qual].add(amap[nm][1])
                else:
                    edges[qual].update(name_index.get(nm, ()))     # unresolved bare name -> over-approx
            elif isinstance(f, ast.Attribute):
                attr = f.attr
                val = f.value
                if isinstance(val, ast.Name) and val.id in amap and amap[val.id][0] == "module":
                    tgt = "%s.%s" % (amap[val.id][1], attr)
                    if tgt in defs:
                        edges[qual].add(tgt)
                    else:
                        edges[qual].update(name_index.get(attr, ()))   # module attr, not a top-level def
                else:
                    edges[qual].update(name_index.get(attr, ()))       # self./obj./Class. -> over-approx
    return defs, edges


def reachable_from(edges, entrypoints):
    seen = set()
    stack = [e for e in entrypoints if e in edges]
    while stack:
        q = stack.pop()
        if q in seen:
            continue
        seen.add(q)
        stack.extend(c for c in edges.get(q, ()) if c not in seen)
    return seen


def guard_present(defs):
    """AST-verify (not string match) that canon.authority_construct raises AuthorityViolation."""
    node = defs.get(AUTHORITY_CONSTRUCTOR)
    if node is None:
        return False
    for sub in ast.walk(node):
        if isinstance(sub, ast.Raise):
            exc = sub.exc
            nm = None
            if isinstance(exc, ast.Call) and isinstance(exc.func, ast.Name):
                nm = exc.func.id
            elif isinstance(exc, ast.Name):
                nm = exc.id
            if nm == "AuthorityViolation":
                return True
    return False


def authority_reachable(moddir):
    """(reachable_bool, reachable_set, defs) -- is the Authority constructor reachable from ANY ordinary
    entry point under the over-approximated call graph?"""
    defs, edges = build_call_graph(moddir)
    reach = reachable_from(edges, ENTRYPOINTS)
    return (AUTHORITY_CONSTRUCTOR in reach), reach, defs


def no_path(moddir):
    """True iff the ordinary model path provably CANNOT mint Authority: the constructor is unreachable
    in the call graph AND its guard (raise AuthorityViolation) is present."""
    reachable, _reach, defs = authority_reachable(moddir)
    return (not reachable) and guard_present(defs)


def summary(moddir):
    defs, edges = build_call_graph(moddir)
    reach = reachable_from(edges, ENTRYPOINTS)
    return {"modules": list(MODULES), "functions_analyzed": len(defs),
            "entrypoints": list(ENTRYPOINTS), "reachable_count": len(reach),
            "authority_constructor": AUTHORITY_CONSTRUCTOR,
            "authority_constructor_reachable": AUTHORITY_CONSTRUCTOR in reach,
            "guard_present": guard_present(defs)}
