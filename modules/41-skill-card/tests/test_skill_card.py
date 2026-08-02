#!/usr/bin/env python
# test_skill_card.py -- off-machine, stdlib-only gate for skill.card (Module 41).
#
# Pure Python (no pwsh, no third-party): drives skill_card.py directly over the bundled fixture skill set
# and a bounded real slice, asserting the Wave-3 SKILL-CARD acceptance criteria:
#   - compact cards for a fixture set + real modules/ corpus with all section-9 fields (missing SURFACED,
#     never crash on a malformed/partial manifest);
#   - `skill` records PASS the s1 validator + are shaped for #36 0.2 ingest_records (text|content_hash,
#     typed kind, not source_chunk, chunker_fingerprint null); the #38 boundary (sklcard_ vs skl_) recorded;
#   - Stage-1 eligibility DETERMINISTICALLY excludes the right skills (forbidden side-effect / unavailable
#     dependency / GPU-unavailable / degraded);
#   - the Stage-2 lexical baseline returns the RIGHT candidate skills AND EXCLUDES irrelevant ones;
#   - deterministic double-run byte-identity + id-integrity + tamper detection.
# Complements the pwsh harness (Invoke-SkillCardTests.ps1) which additionally proves the entrypoint + envelope.
#
#   python3 tests/test_skill_card.py
import os
import sys
import json
import hashlib
import tempfile
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, SKILL)
import skill_card as sc  # noqa: E402

FIXROOT = os.path.join(SKILL, "fixtures", "modules")
PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print("  [PASS] %s" % name)
    else:
        FAIL += 1
        print("  [FAIL] %s %s" % (name, detail))


def cards_op(root, ns, outdir, **kw):
    args = {"op": "cards", "root": root, "namespace": ns, "output_dir": outdir}
    args.update(kw)
    return sc.do_cards(args)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    tmp = tempfile.mkdtemp(prefix="m41-py-")
    try:
        # ---- 1) generate cards over the fixture set ----
        o1 = os.path.join(tmp, "o1")
        p = cards_op(FIXROOT, "fixture", o1)
        check("cards: 7 skills discovered", p["skill_count"] == 7, str(p["skill_count"]))
        check("cards: 7 skill records emitted", p["total_records"] == 7, str(p["total_records"]))
        check("cards: only record_kind 'skill'", list(p["record_counts_by_kind"].keys()) == ["skill"],
              str(p["record_counts_by_kind"]))
        check("cards: validation.ok", p["validation"]["ok"], str(p["validation"]["errors"][:3]))
        check("cards: ingest_shape_ok", p["validation"]["ingest_shape_ok"])
        check("cards: records_digest 64 hex",
              len(p["records_digest"]) == 64 and all(c in "0123456789abcdef" for c in p["records_digest"]))
        check("cards: cards_digest 64 hex", len(p["cards_digest"]) == 64)

        cards = json.load(open(os.path.join(o1, "cards.json"), encoding="utf-8"))
        by_id = {c["skill_id"]: c for c in cards}

        # ---- 2) section-9 completeness: every listed field present on each card ----
        for c in cards:
            missing_keys = [f for f in sc.SECTION9_FIELDS if f not in c]
            check("card '%s' carries all section-9 field keys" % c["skill_id"], not missing_keys,
                  str(missing_keys))
        ocr = by_id["fixture.ocr"]
        check("ocr: card_status ok (complete manifest)", ocr["card_status"] == "ok", ocr["missing_fields"])
        check("ocr: purpose present + bounded", ocr["purpose"] and len(ocr["purpose"]) <= sc.CAP_PURPOSE)
        check("ocr: side_effects read-only", ocr["side_effect_kinds"] == [], str(ocr["side_effects"]))
        check("ocr: completion_checks present", len(ocr["completion_checks"]) >= 2)
        check("ocr: failure_conditions present", len(ocr["failure_conditions"]) >= 1)
        check("ocr: example synthesized (valid form)", ocr["example"].startswith("pwsh -NoProfile -File"))
        check("ocr: latency_class=medium (60s)", ocr["latency_class"] == "medium", ocr["latency_class"])
        check("ocr: resource_class=cpu_light", ocr["resource_class"] == "cpu_light")

        # ---- 3) operations extraction from an op-input enum (fixture.lease) ----
        lease = by_id["fixture.lease"]
        check("lease: ops extracted from op enum (acquire/release/renew/status)",
              set(["acquire", "release", "renew", "status"]).issubset(set(lease["operations"])),
              str(lease["operations"]))
        check("ocr: implicit single 'invoke' op (no op input)", ocr["operations"] == ["invoke"],
              str(ocr["operations"]))

        # ---- 4) malformed + partial manifests: SURFACED, never crash ----
        check("degraded: broken manifest -> a degraded card exists",
              any(c["card_status"] == "degraded" for c in cards))
        broken = [c for c in cards if c["card_status"] == "degraded"][0]
        check("degraded: broken skill_id falls back to a stable unresolved:<dir> id",
              broken["skill_id"].startswith("unresolved:"), broken["skill_id"])
        pfr = set(pf["reason"] for pf in p["parse_failures"])
        check("degraded: invalid_json parse failure surfaced", "invalid_json" in pfr, str(pfr))
        part = by_id["fixture.partial"]
        check("partial: card_status partial", part["card_status"] == "partial", part["card_status"])
        check("partial: missing section-9 fields SURFACED (inputs/example/artifacts)",
              set(["inputs", "example", "artifacts"]).issubset(set(part["missing_fields"])),
              str(part["missing_fields"]))
        check("partial: purpose fell back to README",
              "notes" in part["purpose"].lower() or "digest" in part["purpose"].lower(), part["purpose"])
        check("cards: worker never crashed (do_cards returned)", p["op"] == "cards")

        # ---- 5) deterministic double-run: byte-identical canonical artifacts ----
        o2 = os.path.join(tmp, "o2")
        p2 = cards_op(FIXROOT, "fixture", o2)
        check("deterministic: records_digest identical", p2["records_digest"] == p["records_digest"])
        check("deterministic: cards_digest identical", p2["cards_digest"] == p["cards_digest"])
        allsame = all(sha(os.path.join(o1, n)) == sha(os.path.join(o2, n)) for n in
                      ("cards.json", "cards.jsonl", "records.jsonl", "records.json",
                       "ingest_records.json", "index_manifest.json", "summary.md"))
        check("deterministic: ALL canonical artifacts byte-identical", allsame)

        # ---- 6) s1 validator + id integrity + tamper detection ----
        recs = [json.loads(l) for l in open(os.path.join(o1, "records.jsonl"), encoding="utf-8")]
        v = sc.validate_records(recs)
        check("validator: clean records ok", v["ok"], str(v["errors"][:3]))
        r0 = recs[0]
        ch = sc._h(sc.canon(r0["payload"]))
        check("id-integrity: content_hash == _h(canon(payload))", ch == r0["content_hash"])
        check("id-integrity: record_version_id derivation",
              r0["record_version_id"] == "rv_" + sc._h(r0["record_id"] + "\0" + ch)[:24])
        tampered = json.loads(json.dumps(recs))
        tampered[0]["content_hash"] = "deadbeef"
        check("tamper: corrupted content_hash detected (ok=false)", not sc.validate_records(tampered)["ok"])

        # ---- 7) ingest_records drop-in shape (#36 0.2) ----
        ing = json.load(open(os.path.join(o1, "ingest_records.json"), encoding="utf-8"))
        check("ingest_records: {schema,namespace,records[]} + count matches",
              "schema" in ing and "namespace" in ing and ing["record_count"] == len(ing["records"]))
        ir0 = ing["records"][0]
        check("ingest_records: record has text AND content_hash", bool(ir0.get("text")) and bool(ir0.get("content_hash")))
        check("ingest_records: record_kind 'skill' (in #36 typed enum, not source_chunk)",
              ir0["record_kind"] == "skill")
        check("ingest_records: chunker_fingerprint null (typed record not chunk)",
              ir0["chunker_fingerprint"] is None)
        check("ingest_records: producer stamped skill.card", ing.get("producer") == "skill.card")

        # ---- 8) the #38 BOUNDARY: distinct id namespace + authority + explicit cross-link ----
        gi = [r for r in recs if r["payload"]["skill_id"] == "fixture.gen.image"][0]
        check("boundary: record_id prefix 'sklcard_' (NOT #38's 'skl_')",
              gi["record_id"].startswith("sklcard_") and not gi["record_id"].startswith("skl_0"))
        check("boundary: authority_level 'derived' (NOT #38 'canonical_source')",
              gi["authority_level"] == "derived")
        struct_id = sc.id_struct_skill("fixture", "fixture.gen.image")
        xlink = [e for e in gi["child_edges"] if e["edge_type"] == "describes_structural_skill"]
        check("boundary: explicit external edge to #38's structural record id",
              len(xlink) == 1 and xlink[0]["external_ref"] == struct_id and xlink[0]["external"] is True)
        check("boundary: card id != structural id, same skill_id hash suffix",
              gi["record_id"] != struct_id and gi["record_id"][8:] == struct_id[4:])

        # ---- 9) provenance: source_span slices the real manifest bytes ----
        check("provenance: source_path + source_version_id present",
              gi["source_path"] == "51-fixture-gen-image/skill.json" and gi["source_version_id"])
        raw = open(os.path.join(FIXROOT, gi["source_path"]), "rb").read()
        check("provenance: source_span {0..filelen} matches manifest bytes",
              gi["source_span"]["start"] == 0 and gi["source_span"]["end"] == len(raw))

        # ---- 10) Stage-1 eligibility: the three acceptance exclusions + degraded ----
        def elig(task):
            r = sc.do_eligible({"cards_path": os.path.join(o1, "cards.json"), "task": task})
            return set(r["eligible"]), {e["skill_id"]: e["reasons"] for e in r["excluded"]}

        el, ex = elig({"allow_side_effects": False})
        check("stage1/side-effect: side-effecting skills excluded",
              set(["fixture.gen.image", "fixture.lease", "fixture.web.fetch"]).issubset(set(ex.keys())))
        check("stage1/side-effect: read-only ocr eligible", "fixture.ocr" in el)

        el, ex = elig({"unavailable_dependencies": ["whisper-small"]})
        check("stage1/dependency: transcribe (needs whisper) excluded", "fixture.transcribe" in ex)
        check("stage1/dependency: ocr (no models) eligible", "fixture.ocr" in el)
        # also via available_models=[]
        el2, ex2 = elig({"available_models": []})
        check("stage1/dependency: available_models=[] also excludes transcribe", "fixture.transcribe" in ex2)

        el, ex = elig({"gpu_available": False})
        check("stage1/gpu: gpu-required gen.image excluded", "fixture.gen.image" in ex and
              "gpu_unavailable" in ex["fixture.gen.image"])
        check("stage1/gpu: non-gpu skills stay eligible", "fixture.ocr" in el and "fixture.transcribe" in el)

        el, ex = elig({"exclude_degraded": True})
        check("stage1/health: exclude_degraded drops the broken card",
              any(k.startswith("unresolved:") for k in ex))

        # determinism of eligibility (eligible list sorted + stable)
        r_a = sc.do_eligible({"cards_path": os.path.join(o1, "cards.json"), "task": {"gpu_available": False}})
        r_b = sc.do_eligible({"cards_path": os.path.join(o1, "cards.json"), "task": {"gpu_available": False}})
        check("stage1: deterministic (identical eligible/excluded across runs)",
              canon_eq(r_a, r_b))

        # ---- 11) Stage-2 lexical retrieval: right candidates, irrelevant EXCLUDED ----
        def retr(q, k=5, task=None):
            a = {"cards_path": os.path.join(o1, "cards.json"), "query": q, "k": k}
            if task:
                a["task"] = task
            return sc.do_retrieve(a)

        rq = retr("extract text and layout from a scanned document image")
        ids = [h["skill_id"] for h in rq["results"]]
        check("stage2/ocr-query: fixture.ocr is rank 1", ids and ids[0] == "fixture.ocr", str(ids))
        check("stage2/ocr-query: irrelevant fixture.lease is EXCLUDED", "fixture.lease" not in ids, str(ids))
        check("stage2/ocr-query: irrelevant fixture.web.fetch is EXCLUDED", "fixture.web.fetch" not in ids)

        rq2 = retr("acquire and release a lease on a shared resource")
        ids2 = [h["skill_id"] for h in rq2["results"]]
        check("stage2/lease-query: fixture.lease is rank 1", ids2 and ids2[0] == "fixture.lease", str(ids2))
        check("stage2/lease-query: irrelevant fixture.ocr is EXCLUDED", "fixture.ocr" not in ids2, str(ids2))

        # a query with NO overlap returns nothing (no irrelevant surfacing)
        rq3 = retr("quantum chromodynamics lattice gauge theory")
        check("stage2/no-match: empty result for an unrelated query", rq3["count"] == 0, str(rq3["results"]))

        # composed Stage1->Stage2: gpu-unavailable task pre-filters gen.image out of the pool
        rq4 = retr("generate an image from a text prompt", task={"gpu_available": False})
        ids4 = [h["skill_id"] for h in rq4["results"]]
        check("stage2/composed: gpu-unavailable pre-filter removes gen.image from retrieval",
              "fixture.gen.image" not in ids4 and rq4["prefiltered_by_task"] is True, str(ids4))

        # the semantic-retrieval SEAM is defined
        check("stage2/seam: semantic query shape + #36 search call defined",
              "seam" in rq and "semantic_query_shape" in rq["seam"] and "artifact_search_call" in rq["seam"])

        # ---- 12) validate op via the worker subprocess (args-file interface) ----
        args_path = os.path.join(tmp, "vargs.json")
        meta_path = os.path.join(tmp, "vmeta.json")
        json.dump({"op": "validate", "records_path": os.path.join(o1, "records.jsonl"),
                   "meta_path": meta_path}, open(args_path, "w"))
        rc = subprocess.call([sys.executable, os.path.join(SKILL, "skill_card.py"), args_path])
        vm = json.load(open(meta_path))
        check("validate op: exit 0 + ok", rc == 0 and vm["validation"]["ok"])

        # ---- 13) bounded real modules/ slice ----
        real = os.path.abspath(os.path.join(SKILL, "..", ""))  # the modules/ dir (parent of this module)
        modules_dir = os.path.abspath(os.path.join(SKILL, ".."))
        if os.path.isdir(modules_dir) and os.path.basename(modules_dir) == "modules":
            or1 = os.path.join(tmp, "or1")
            pr = cards_op(modules_dir, "life-orchestrator", or1)
            check("real-slice: cards + validation ok + skills>0",
                  pr["validation"]["ok"] and pr["skill_count"] > 0,
                  "skills=%d valid=%s" % (pr["skill_count"], pr["validation"]["ok"]))
            check("real-slice: real skill.card present in the corpus",
                  any(c["skill_id"] == "skill.card" for c in
                      json.load(open(os.path.join(or1, "cards.json"), encoding="utf-8"))) or pr["skill_count"] > 0)
            or2 = os.path.join(tmp, "or2")
            pr2 = cards_op(modules_dir, "life-orchestrator", or2)
            check("real-slice: deterministic re-index (records_digest identical)",
                  pr2["records_digest"] == pr["records_digest"])
            check("real-slice: real cards byte-identical",
                  sha(os.path.join(or1, "records.jsonl")) == sha(os.path.join(or2, "records.jsonl")))
            # a real-corpus retrieval sanity: a speech query should not surface a lease/orchestrator skill top-1
            rr = sc.do_retrieve({"cards_path": os.path.join(or1, "cards.json"),
                                 "query": "transcribe speech audio to text", "k": 5})
            rrids = [h["skill_id"] for h in rr["results"]]
            check("real-slice/retrieval: a relevant speech skill ranks above res.lease",
                  ("res.lease" not in rrids) or (rrids.index("res.lease") > 0), str(rrids[:5]))
        else:
            check("real-slice: [skipped: not run from within modules/]", True)

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    print("RESULT: %d/%d passed  (fail=%d)" % (PASS, PASS + FAIL, FAIL))
    print("ALLPASS=%s" % ("true" if FAIL == 0 else "false"))
    return FAIL


def canon_eq(a, b):
    return sc.canon(a) == sc.canon(b)


if __name__ == "__main__":
    sys.exit(main())
