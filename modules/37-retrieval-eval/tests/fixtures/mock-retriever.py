#!/usr/bin/env python3
# mock-retriever.py -- a FIXTURE external retriever that conforms to the D-0077 retriever interface
# (op `search`; inputs {query, k, filters?}; result = ranked array of
# {source_path, content_hash, chunk_id, span, score, snippet} in deterministic order).
#
# It exists to PROVE the harness's external_command seam -- the exact contract the orchestrator points at
# the real artifact.search at fold. It reads a canned plan (argv[1]) mapping query text -> ranked hits,
# reads the request {query,k,filters} from stdin, and prints ONE JSON envelope {"result":{"hits":[...]}}
# to stdout (hits_pointer="result.hits"). Fully deterministic; no corpus, no model, no network.
import sys
import json


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: mock-retriever.py <plan.json>  (request on stdin)\n")
        return 2
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        plan = json.load(fh)
    req = json.loads(sys.stdin.read())
    query = req.get("query", "")
    k = int(req.get("k", 10))
    hits = plan.get(query, [])[: max(0, k)]
    sys.stdout.write(json.dumps({"result": {"hits": hits}}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
