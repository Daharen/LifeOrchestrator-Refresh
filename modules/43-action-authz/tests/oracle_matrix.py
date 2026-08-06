"""
oracle_matrix.py -- the per-check / U-property oracle matrix (contract s6 amendment 5; i38).

One row per mandatory mutation naming the INDEPENDENT observable surface its kill is decided on
(never trace-presence alone). Built by joining the mutation REGISTRY with the observable each
sec-predicate actually inspects. Asserts every mandatory mutation has a row with a named surface.
"""

from . import mutations as MUT

# obligation_id + observable_surface + independent_oracle per mutation (contract s5/s6/s8).
_ORACLE = {
    "M-A01": ("A09/A26/U-AUTHORITY", "decision + permit-store delta", "evidence 'grant' cannot enter authority"),
    "M-A02": ("A26/U-AUTHORITY", "decision + permit-store delta", "skill-card scopes are not manifest data"),
    "M-A03": ("A29/U-AUTHORITY", "decision", "'approval received' in working memory is not an approval"),
    "M-A04": ("A30/U-ROLE", "completion evaluator result", "tool stdout is not trusted completion status"),
    "M-A05": ("A09", "decision", "proposal cannot select the authority snapshot ref"),
    "M-A06": ("A3/A6/U-ROLE", "trust-class origin", "ordinary derive never yields Authority"),
    "M-A07": ("A2/A3/no_path", "Authority-constructor capability", "no ordinary path mints Authority"),
    "M-A08": ("A19/C3", "decision", "claimed_effects excluded from derivation/matching"),
    "M-A09": ("A04", "decision", "provenance must be adapter-attested, not caller-supplied"),
    "M-A10": ("A14", "decision", "evidence cannot set tool health / enabled"),
    "M-S01": ("A11/U-SCOPE", "effective_allowed_namespaces", "authorized ns is request ∩ grant"),
    "M-S02": ("A11/U-SCOPE", "effective_allowed_namespaces", "intersection, never union"),
    "M-S03": ("A18/U-SCOPE", "ns_permitted admission", "exact-match ns (no wildcard/prefix/all)"),
    "M-S04": ("A18/A20/U-SCOPE", "decision (ns closure hop)", "every target/effect ns is checked"),
    "M-S05": ("A18/U-SCOPE", "decision (transitive members)", "closure covers transitive constituents"),
    "M-S06": ("A17/A18/U-SCOPE", "decision", "symlink/alias cannot resolve out of scope"),
    "M-S07": ("A18/U-SCOPE", "decision", "a v0.1 permit authorizes exactly one namespace"),
    "M-S08": ("A35/A36/U-SCOPE", "constant caller bytes", "no branch/step oracle to the caller"),
    "M-S09": ("A36", "ordinary log contents", "no attacker payload in the ordinary log"),
    "M-S10": ("A31/U-SCOPE", "completion evaluator result", "out-of-scope status cannot complete"),
    "M-R01": ("A31/U-ROLE", "decision", "navigation never satisfies evidence"),
    "M-R02": ("A31/A09/U-ROLE", "decision", "working memory never satisfies evidence/authority"),
    "M-R03": ("A6/U-ROLE", "trust-class origin", "derived/aggregate is not execution authority"),
    "M-R04": ("D1/U-ROLE", "executor entry + effect ledger", "no raw tool-call reaches the executor"),
    "M-R05": ("D1/U-ROLE", "executor entry + effect ledger", "no proposal reaches the executor"),
    "M-R06": ("D1/D2/U-ROLE", "executor entry + effect ledger", "executor resolves permits from the store"),
    "M-R07": ("A30/U-ROLE", "completion evaluator result", "model/evidence prose never completes"),
    "M-R08": ("A30/U-ROLE/D6", "completion evaluator result", "tool stdout is not a completion actual"),
    "M-R09": ("A35", "model-facing caller_result", "permit bytes/nonce never returned to the model"),
    "M-R10": ("A31/U-ROLE", "decision", "an unresolved frontier is not proof of absence"),
    "M-R11": ("A31/R1-ROLE-1/U-ROLE", "decision", "R-1 router stage-trace is a non-authoritative diagnostic"),
    "M-E01": ("A02/U-EFFECT", "decision", "duplicate keys rejected at strict parse"),
    "M-E02": ("A15", "decision", "unknown arg field rejected (closed schema)"),
    "M-E03": ("A15", "decision", "no type coercion"),
    "M-E04": ("A16", "canonical bytes of NFC variants", "canonicalization makes NFC variants equal"),
    "M-E05": ("A17/A18/U-SCOPE", "decision", "canonical identity used, not caller spelling"),
    "M-E06": ("A17/U-SCOPE", "decision", "aliases/symlinks resolved before authorization"),
    "M-E07": ("A19/A20/A21", "derived effect set", "wrapper delegated effects classified"),
    "M-E08": ("A26", "decision", "grant match includes operation"),
    "M-E09": ("A26", "decision", "grant match includes canonical targets"),
    "M-E10": ("A26", "decision", "grant match includes effect class/quantity/externality"),
    "M-E11": ("A27", "decision", "policy escalation cannot be weakened"),
    "M-E12": ("A28/A29", "decision", "required approval enforced"),
    "M-E13": ("A29", "decision", "approval bound to the exact digest/task/ns/manifest/grant"),
    "M-E14": ("A25/U-EFFECT", "canonical_action_digest", "digest binds arguments"),
    "M-E15": ("A25/U-EFFECT", "canonical_action_digest", "digest binds resolved targets"),
    "M-E16": ("A25/U-EFFECT", "canonical_action_digest", "digest binds derived effects"),
    "M-E17": ("A25/U-EFFECT", "canonical_action_digest", "digest binds ns/risk/sandbox/limits/idem"),
    "M-E18": ("A25/U-EFFECT", "canonical_action_digest", "digest is authorizer-computed, not caller-supplied"),
    "M-E19": ("A06/U-EFFECT", "decision", "non_execution:true denies at A06"),
    "M-E20": ("A10/A32", "decision", "stale/revoked grant rejected"),
    "M-E21": ("A29", "decision", "stale/revoked approval rejected"),
    "M-E22": ("A07", "decision", "packet/corpus drift rejected"),
    "M-E23": ("A12/A32/D3", "decision", "manifest/artifact drift rejected"),
    "M-E24": ("A14", "decision", "stale/unhealthy tool rejected"),
    "M-E25": ("A32", "decision", "the final TOCTOU recheck is present"),
    "M-E26": ("A33/U-EFFECT", "permit-store count", "one reservation -> one permit"),
    "M-E27": ("D8/U-EFFECT", "effect ledger across reuse", "one-shot permit not reusable"),
    "M-E28": ("D3", "effect ledger", "expired permit produces no effect"),
    "M-E29": ("D4/U-EFFECT", "effect ledger + state diff", "post-claim target substitution -> no effect"),
    "M-E30": ("D7/U-EFFECT", "independent effect ledger", "actual effects subset of authorized within limits"),
    "M-E31": ("D5/U-EFFECT", "effect ledger on rejection", "a rejected execution yields no state diff"),
    "M-E32": ("D8/U-EFFECT", "effect ledger after crash", "crash never makes a permit reusable"),
    "M-E33": ("D7/U-EFFECT", "effect ledger", "no retry under the same permit"),
    "M-E34": ("D7/U-EFFECT", "effect ledger", "no rollback/follow-up under the original permit"),
    "M-E35": ("A30/U-ROLE", "completion evaluator result", "missing/stale status is not success"),
    "M-E36": ("A30/U-ROLE", "completion evaluator result", "status from another action cannot complete"),
}


def run(check):
    rows = []
    for mid, cat, _fn, _note in MUT.REGISTRY:
        obl, surface, oracle = _ORACLE.get(mid, ("?", "?", "?"))
        rows.append({"mutation": mid, "category": cat, "obligation_id": obl,
                     "observable_surface": surface, "independent_oracle": oracle})
    covered = all(r["observable_surface"] not in ("?", "") for r in rows)
    check.ok("oracle matrix: an independent observable per mandatory mutation (%d rows)" % len(rows),
             covered, "uncovered=%s" % [r["mutation"] for r in rows if r["observable_surface"] == "?"])
    return rows
