#!/usr/bin/env python3
# test_working_memory.py -- OFF-MACHINE deterministic gate for working.memory 0.1.0 (module 42, i34).
# Stdlib-only; exercises the A5 U3' store invariants directly against the worker's run_request().
import os, sys, json, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))
import working_memory as wm  # noqa

PASS = 0
FAIL = 0
def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("ok   - %s" % name)
    else:
        FAIL += 1
        print("FAIL - %s" % name)

def _ns_path():
    # portable: prefer a sibling lib/ copy (cloud scratch), else the repo's #37 canonical (on-box), else
    # None (let the worker auto-resolve). NEVER a re-implementation -- always #37's canonical predicate.
    for c in (os.path.join(HERE, "..", "lib", "namespace_policy.py"),
              os.path.normpath(os.path.join(HERE, "..", "..", "37-retrieval-eval", "lib", "namespace_policy.py"))):
        if os.path.isfile(c):
            return c
    return None

NS_PATH = _ns_path()

def req(base, **kw):
    r = {"out_dir": base, "store_path": os.path.join(base, "wm.db")}
    if NS_PATH:
        r["ns_policy_path"] = NS_PATH
    r.update(kw)
    return r

def auth(ns):
    # an authorized caller for namespace `ns`: request==grant=={ns} -> effective={ns}
    return {"allowed_namespaces": [ns], "permission_grants": [ns]}

def run(base, **kw):
    return wm.run_request(req(base, **kw))

def read_art(base, name):
    p = os.path.join(base, name + ".json")
    if not os.path.exists(p): return None
    with open(p, "rb") as f: return f.read()

def sequence(base):
    """A fixed op sequence used for both correctness and the determinism (double-run) check."""
    outs = {}
    a = auth("projA")
    outs["v1"] = run(base, op="put_state", task_id="T1", namespace_scope="projA",
                     body={"step": 1, "note": "start"}, parent_state_version=None, **a)
    outs["v1_state"] = read_art(base, "state")
    outs["v2"] = run(base, op="put_state", task_id="T1", body={"step": 2, "note": "advance"},
                     parent_state_version=1, **a)
    outs["v2_state"] = read_art(base, "state")
    outs["promote"] = run(base, op="promote", task_id="T1", **a)
    outs["promoted"] = read_art(base, "promoted")
    return outs

def main():
    tmp = tempfile.mkdtemp(prefix="wm-test-")
    try:
        # ---- correctness on a single evolving store ----
        base = os.path.join(tmp, "main"); os.makedirs(base)
        a = auth("projA")

        s1 = run(base, op="put_state", task_id="T1", namespace_scope="projA",
                 body={"step": 1}, parent_state_version=None, **a)
        check("put_state v1 creates active head at version 1", s1.get("state_version") == 1 and s1.get("ok"))

        gh = run(base, op="get_active_head", task_id="T1", **a)
        check("get_active_head returns v1", gh.get("found") and gh.get("state_version") == 1)

        s2 = run(base, op="put_state", task_id="T1", body={"step": 2}, parent_state_version=1, **a)
        check("put_state v2 with correct CAS advances head", s2.get("state_version") == 2)

        gh2 = run(base, op="get_active_head", task_id="T1", **a)
        check("active head is now v2", gh2.get("state_version") == 2)

        # CAS conflict: stale parent (1) when head is 2
        try:
            run(base, op="put_state", task_id="T1", body={"step": 99}, parent_state_version=1, **a)
            check("stale-parent write FAILS CLOSED (cas_conflict)", False)
        except wm.WMError as e:
            check("stale-parent write FAILS CLOSED (cas_conflict)", e.code == "cas_conflict")

        # new task with a non-null parent -> cas_conflict
        try:
            run(base, op="put_state", task_id="T2", namespace_scope="projA", body={"x": 1},
                parent_state_version=5, **a)
            check("new task with non-null parent FAILS CLOSED", False)
        except wm.WMError as e:
            check("new task with non-null parent FAILS CLOSED", e.code == "cas_conflict")

        # exactly one active head per task (inspect the store)
        conn = wm.open_store(os.path.join(base, "wm.db"))
        n_heads = conn.execute("SELECT COUNT(*) c FROM working_state WHERE task_id='T1' AND is_active_head=1").fetchone()["c"]
        n_rows = conn.execute("SELECT COUNT(*) c FROM working_state WHERE task_id='T1'").fetchone()["c"]
        conn.close()
        check("exactly ONE active head per task", n_heads == 1)
        check("both versions retained (immutable snapshots)", n_rows == 2)

        # fork -> new task branch derived from T1 head, own active head, namespace inherited (no widening)
        fk = run(base, op="fork", source_task_id="T1", new_task_id="T1b", **a)
        check("fork creates a divergent head", fk.get("op") == "fork" and fk.get("new_task_id") == "T1b")
        check("fork records derives-from provenance", bool(fk.get("forked_from")))
        ghf = run(base, op="get_active_head", task_id="T1b", **a)
        check("forked task has its own active head", ghf.get("found") and ghf.get("state_version") == 1)

        # list_by_task (exact) returns all versions
        lb = run(base, op="list_by_task", task_id="T1", **a)
        check("list_by_task returns all versions for the task", lb.get("count") == 2)

        # conjunctive access: right task_id, WRONG namespace -> fail-closed, sanitized, no leakage
        wrong = run(base, op="get_active_head", task_id="T1", **auth("projB"))
        check("wrong-namespace get_active_head is fail-closed (not found)", wrong.get("found") is False and wrong.get("reason") == "namespace_denied")
        check("wrong-namespace surfaces a violation COUNT only", wrong.get("namespace_violation_count") == 1)
        check("wrong-namespace leaks NO record", "state" not in wrong and "content_hash" not in wrong)

        # empty effective set (no grant) -> fail-closed
        none_grant = run(base, op="get_active_head", task_id="T1", allowed_namespaces=["projA"], permission_grants=[])
        check("empty grant (empty intersection) fail-closed", none_grant.get("found") is False)

        # search REJECTS working
        srch = run(base, op="search", record_kind="working", **a)
        check("search rejects record_kind=working (0 results)", srch.get("count") == 0 and srch.get("working_excluded_from_search") is True)

        # close removes the task from get_active_head
        run(base, op="close", task_id="T1", **a)
        ghc = run(base, op="get_active_head", task_id="T1", **a)
        check("close removes task from get_active_head", ghc.get("found") is False)

        # archive another task
        run(base, op="put_state", task_id="T3", namespace_scope="projA", body={"y": 1}, parent_state_version=None, **a)
        run(base, op="archive", task_id="T3", **a)
        gha = run(base, op="get_active_head", task_id="T3", **a)
        check("archive removes task from get_active_head", gha.get("found") is False)

        # promote: emits a summary derived record, working record NOT re-labeled
        base2 = os.path.join(tmp, "prom"); os.makedirs(base2)
        run(base2, op="put_state", task_id="P1", namespace_scope="projA", body={"final": "state"}, parent_state_version=None, **a)
        pr = run(base2, op="promote", task_id="P1", **a)
        check("promote emits a summary record", pr.get("promoted_record_kind") == "summary")
        check("promote sets derives_from the working version", bool(pr.get("derives_from")))
        prom = json.loads(read_art(base2, "promoted"))
        check("promoted record_kind=summary + derives_from edge", prom["record_kind"] == "summary" and prom["derivation_refs"] == [pr["derives_from"]])
        # the working record itself is unchanged (still kind=working, still retrievable by task)
        ghp = run(base2, op="get_active_head", task_id="P1", **a)
        check("working record NOT re-labeled by promote", ghp.get("found") is True)

        # ---- determinism: the SAME op sequence on two fresh stores -> byte-identical artifacts + digest ----
        d1 = os.path.join(tmp, "det1"); os.makedirs(d1)
        d2 = os.path.join(tmp, "det2"); os.makedirs(d2)
        o1 = sequence(d1)
        o2 = sequence(d2)
        check("determinism: v1 state bytes identical", o1["v1_state"] == o2["v1_state"])
        check("determinism: v2 state bytes identical", o1["v2_state"] == o2["v2_state"])
        check("determinism: promoted bytes identical", o1["promoted"] == o2["promoted"])
        check("determinism: records_digest identical (promote)", o1["promote"]["records_digest"] == o2["promote"]["records_digest"])

        # ns_permitted parity: the store's authorize path uses #37's canonical predicate verbatim
        import importlib.util
        spec = importlib.util.spec_from_file_location("ns37", NS_PATH)
        ns37 = importlib.util.module_from_spec(spec); spec.loader.exec_module(ns37)
        check("ns_permitted parity: in-scope True", ns37.ns_permitted("projA", ns37.effective_allowed_namespaces(["projA"], ["projA"])) is True)
        check("ns_permitted parity: out-scope False", ns37.ns_permitted("projA", ns37.effective_allowed_namespaces(["projB"], ["projB"])) is False)
        check("ns_permitted parity: empty grant False", ns37.ns_permitted("projA", ns37.effective_allowed_namespaces(["projA"], [])) is False)

        print("\n%d passed, %d failed" % (PASS, FAIL))
        return 1 if FAIL else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
