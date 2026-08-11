#!/usr/bin/env python3
"""Doc Health & Packet-Size Monitor -- deterministic generator (D-0101 / PB-4, audit tier A0.5).

READ-ONLY. Reads live repo state and (re)emits ops/out/doc-health-monitor.html + appends one
snapshot row to ops/out/doc-health-log.jsonl. Zero doc-upkeep: it reads current state, maintains
nothing. Run at each wave close (see FANOUT_ORCHESTRATOR_HANDOFF s7); fold into the audit sub-agent
wrap when memory/audit matures, so the monitor never becomes the bloat it measures.

Usage (via the executor):  python ops/audit/gen-doc-health.py [--head <sha>] [--date <YYYY-MM-DD>]
Status rule (Nicholas): green if <=90% of quota (>=10% under) / yellow 90-110% / red >110%.
"""
import os, re, glob, json, sys, argparse, subprocess, hashlib

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # .../<repo>
CORE = os.path.join(REPO, "core-docs")
OUT_DIR = os.path.join(REPO, "ops", "out")
KB = 1000
HOOK_PATH = os.path.join(REPO, ".git", "hooks", "pre-commit")
HOOK_MANIFEST = os.path.join(REPO, "ops", "audit", "doc-gate-hook.sha256")


def hook_status():
    """M2-A hook-presence assertion (D-0110/i42): is the doc-commit-gate pre-commit hook
    installed and current? Reads the expected sha256 from ops/audit/doc-gate-hook.sha256 (the
    manifest owned by doc-commit-gate.py --install-hook) and compares it to the hash of the
    INSTALLED .git/hooks/pre-commit -- both machine-local facts, read fresh every run.
    Returns (status, detail) with status in {"red","grn"} (never "yel" -- hook presence is
    binary: it either matches the shipped manifest or it does not)."""
    if not os.path.isfile(HOOK_MANIFEST):
        return "red", "no ops/audit/doc-gate-hook.sha256 manifest -- the doc-commit-gate has not been installed on this box"
    try:
        with open(HOOK_MANIFEST, encoding="ascii") as fh:
            expected = fh.read().split()[0].strip().lower()
    except (OSError, IndexError):
        return "red", "ops/audit/doc-gate-hook.sha256 is unreadable or empty"
    if not os.path.isfile(HOOK_PATH):
        return "red", ".git/hooks/pre-commit is MISSING -- run ops/install-doc-gate.bat"
    with open(HOOK_PATH, "rb") as fh:
        actual = hashlib.sha256(fh.read()).hexdigest()
    if actual != expected:
        return "red", ".git/hooks/pre-commit is STALE (hash mismatch) -- re-run ops/install-doc-gate.bat"
    return "grn", ".git/hooks/pre-commit present and matches the shipped manifest"

def sz(p):
    try: return os.path.getsize(p)
    except OSError: return None

def parse_budgets():
    """Parse the DOC_PROTOCOL s2 table: rows `| doc.md | owns | N KB |` (or 'no cap')."""
    txt = open(os.path.join(CORE, "DOC_PROTOCOL.md"), encoding="utf-8").read()
    budgets = {}
    for m in re.finditer(r"^\|\s*([A-Za-z0-9_./<>&;-]+\.md)\s*\|[^|]*\|\s*([^|]+?)\s*\|", txt, re.M):
        doc, b = m.group(1), m.group(2)
        km = re.search(r"(\d+)\s*KB", b)
        budgets[doc] = int(km.group(1)) if km else None   # None = uncapped/no cap
    return budgets

def git_head():
    try:
        return subprocess.run(["git","-C",REPO,"log","-1","--format=%h"],
                              capture_output=True, text=True, timeout=20).stdout.strip() or "unknown"
    except Exception: return "unknown"

def js(o): return json.dumps(o, separators=(",",":"))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--head", default=None); ap.add_argument("--date", default=None)
    a = ap.parse_args()
    head = a.head or git_head()
    date = a.date or "undated"   # pass --date to stamp; runtime has no clock in some sandboxes

    budgets = parse_budgets()
    docs, uncapped = [], []
    for path in sorted(glob.glob(os.path.join(CORE, "*.md"))):
        name = os.path.basename(path); b = sz(path)
        if b is None: continue
        q = budgets.get(name)
        if q: docs.append([name, b, q])
        elif name == "DECISION_LOG.md" or budgets.get(name, "MISSING") is None:
            uncapped.append([name, b])
    # worker-spec bytes per iteration
    iters = []
    for f in glob.glob(os.path.join(REPO,"modules","30-orchestrate-fanout","runtime","workers-i*.json")):
        m = re.search(r"workers-i(\d+)\.json$", f)
        if m and sz(f): iters.append([int(m.group(1)), sz(f)])
    iters.sort()
    # frontier packs
    packs = []
    for f in glob.glob(os.path.join(REPO,"modules","31-frontier-bridge","runtime","artifacts","*","frontier-pack-*.md")):
        if f.endswith(".answer.md"): continue
        b = sz(f)
        if not b: continue
        mm = re.search(r"frontier-pack-(i\d+)[-_](.+)\.md$", os.path.basename(f))
        lbl = (mm.group(1)+" "+mm.group(2).replace("-"," ")) if mm else os.path.basename(f)
        packs.append([lbl, b])
    packs.sort(key=lambda r:-r[1]); packs = packs[:8]

    # health counts for the log
    def cls(p): return "red" if p>110 else ("yel" if p>90 else "grn")
    scored = sorted(([n,b,q,b/(q*KB)*100] for n,b,q in docs), key=lambda r:-r[3])
    counts = {"red":0,"yel":0,"grn":0}
    for _,_,_,p in scored: counts[cls(p)] += 1

    hook_cls, hook_detail = hook_status()

    html = TEMPLATE
    html = html.replace("__SNAP_DATE__", date).replace("__HEAD__", head)
    html = html.replace("/*__DOCS__*/[]", js(docs))
    html = html.replace("/*__UNCAPPED__*/[]", js(uncapped))
    html = html.replace("/*__ITERS__*/[]", js(iters))
    html = html.replace("/*__PACKS__*/[]", js(packs))
    html = html.replace("__HOOK_CLASS__", hook_cls)
    html = html.replace("__HOOK_LABEL__", "Hook OK" if hook_cls == "grn" else "Hook missing/stale")
    html = html.replace("__HOOK_DETAIL__", hook_detail)

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "doc-health-monitor.html")
    open(out, "w", encoding="utf-8", newline="\n").write(html)
    # append a log row (the "log for each" -- a snapshot history, integer-only, deterministic)
    row = {"date":date,"head":head,"over":counts["red"],"watch":counts["yel"],"healthy":counts["grn"],
           "worst":scored[0][0] if scored else None,"worst_pct":round(scored[0][3]) if scored else None,
           "docs":{n:{"bytes":b,"quota_kb":q,"pct":round(b/(q*KB)*100)} for n,b,q in docs},
           "worker_spec_bytes":{str(i):b for i,b in iters},
           "doc_gate_hook":{"status":hook_cls,"detail":hook_detail}}
    with open(os.path.join(OUT_DIR,"doc-health-log.jsonl"),"a",encoding="utf-8",newline="\n") as fh:
        fh.write(json.dumps(row, separators=(",",":"))+"\n")
    print("OK", out)
    print("over=%d watch=%d healthy=%d worst=%s %d%%" % (counts["red"],counts["yel"],counts["grn"],
          scored[0][0] if scored else "-", round(scored[0][3]) if scored else 0))

TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Life Orchestrator -- Doc Health & Packet-Size Monitor</title>
<style>
  :root{color-scheme:light dark;
    --plane:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;
    --grid:#e1e0d9;--base:#c3c2b7;--ring:rgba(11,11,11,0.10);
    --good:#0ca30c;--warn:#fab219;--crit:#d03b3b;--series:#2a78d6;
    --good-wash:rgba(12,163,12,0.10);--warn-wash:rgba(250,178,25,0.14);--crit-wash:rgba(208,59,59,0.10);}
  @media (prefers-color-scheme: dark){:root{
    --plane:#0d0d0d;--surface:#1a1a19;--ink:#fff;--ink2:#c3c2b7;--muted:#898781;
    --grid:#2c2c2a;--base:#383835;--ring:rgba(255,255,255,0.10);--series:#3987e5;
    --good-wash:rgba(12,163,12,0.16);--warn-wash:rgba(250,178,25,0.16);--crit-wash:rgba(208,59,59,0.18);}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--plane);color:var(--ink);font-family:system-ui,-apple-system,"Segoe UI",sans-serif;font-size:14px;line-height:1.45}
  .wrap{max-width:1040px;margin:0 auto;padding:28px 20px 60px}
  h1{font-size:20px;margin:0 0 2px;font-weight:650}
  .sub{color:var(--ink2);font-size:13px;margin:0 0 22px}
  .sub code{background:var(--surface);border:1px solid var(--ring);border-radius:4px;padding:1px 5px;font-size:12px}
  h2{font-size:14px;font-weight:650;margin:30px 0 10px}
  .card{background:var(--surface);border:1px solid var(--ring);border-radius:12px;padding:16px 18px}
  .kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:6px}
  .kpi{background:var(--surface);border:1px solid var(--ring);border-radius:12px;padding:14px 16px}
  .kpi .n{font-size:26px;font-weight:680;font-variant-numeric:tabular-nums;letter-spacing:-.01em}
  .kpi .l{color:var(--ink2);font-size:12px;margin-top:2px}
  .kpi.red .n{color:var(--crit)}.kpi.yel .n{color:var(--warn)}.kpi.grn .n{color:var(--good)}
  table{width:100%;border-collapse:collapse;font-size:13px}
  thead th{text-align:left;color:var(--muted);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.04em;padding:0 10px 8px;border-bottom:1px solid var(--grid)}
  th.num,td.num{text-align:right;font-variant-numeric:tabular-nums}
  tbody td{padding:9px 10px;border-bottom:1px solid var(--grid);vertical-align:middle}
  tbody tr:last-child td{border-bottom:none}
  .doc{font-weight:560}
  .meter{position:relative;height:9px;border-radius:5px;background:var(--grid);overflow:hidden;min-width:120px}
  .meter>i{position:absolute;left:0;top:0;bottom:0;border-radius:5px;display:block}
  .meter .q{position:absolute;top:-3px;bottom:-3px;width:2px;background:var(--base)}
  .chip{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;padding:3px 9px 3px 8px;border-radius:20px;white-space:nowrap}
  .chip .dot{width:8px;height:8px;border-radius:50%;flex:0 0 8px}
  .chip.red{background:var(--crit-wash);color:var(--crit)}.chip.red .dot{background:var(--crit)}
  .chip.yel{background:var(--warn-wash);color:#8a6100}.chip.yel .dot{background:var(--warn)}
  .chip.grn{background:var(--good-wash);color:var(--good)}.chip.grn .dot{background:var(--good)}
  .chip.na{background:transparent;color:var(--muted);border:1px solid var(--ring)}.chip.na .dot{background:var(--muted)}
  @media (prefers-color-scheme: dark){.chip.yel{color:#fab219}}
  svg{display:block;width:100%;height:auto;overflow:visible}
  .bar{fill:var(--series)}
  .axlabel{fill:var(--muted);font-size:10px;font-variant-numeric:tabular-nums}
  .vlabel{fill:var(--ink2);font-size:10px;font-variant-numeric:tabular-nums;text-anchor:middle;font-weight:600}
  .gridln{stroke:var(--grid);stroke-width:1}
  .chartcard{position:relative}
  .tip{position:absolute;pointer-events:none;opacity:0;transform:translate(-50%,-110%);background:var(--ink);color:var(--surface);font-size:12px;font-weight:600;padding:5px 9px;border-radius:7px;white-space:nowrap;transition:opacity .08s;font-variant-numeric:tabular-nums}
  .note{color:var(--ink2);font-size:12.5px;margin:10px 2px 0}
  .legend{display:flex;gap:16px;flex-wrap:wrap;color:var(--ink2);font-size:12px;margin:4px 2px 0}
  .legend span{display:inline-flex;align-items:center;gap:6px}
  .legend i{width:9px;height:9px;border-radius:2px;display:inline-block}
  .foot{margin-top:34px;color:var(--muted);font-size:12px;border-top:1px solid var(--grid);padding-top:12px}
  .small{color:var(--muted);font-size:11.5px}
</style>
</head>
<body>
<div class="wrap">
  <h1>Doc Health &amp; Packet-Size Monitor</h1>
  <p class="sub">Governing-doc size vs. budget (DOC_PROTOCOL s2) + per-iteration worker-context growth. Snapshot <code>__SNAP_DATE__</code> · HEAD <code>__HEAD__</code>. Read-only; regenerated by the orchestrator at each wave close.</p>
  <p class="sub"><span class="chip __HOOK_CLASS__"><span class="dot"></span>__HOOK_LABEL__</span> <span class="small">M2-A doc-commit-gate pre-commit hook (machine-local) -- __HOOK_DETAIL__</span></p>
  <div class="kpis" id="kpis"></div>
  <div class="legend">
    <span><i style="background:var(--crit)"></i>Over budget (&gt;110% of quota)</span>
    <span><i style="background:var(--warn)"></i>Watch (90-110%)</span>
    <span><i style="background:var(--good)"></i>Healthy (&le;90%)</span>
    <span class="small">quota tick = 100% · green &ge;10% under · yellow &plusmn;10% · red &gt;10% over</span>
  </div>
  <h2>Governing docs -- size vs. budget</h2>
  <div class="card"><table>
    <thead><tr><th>Document</th><th class="num">Size</th><th class="num">Quota</th><th class="num">% of quota</th><th style="width:190px">Fill (tick = quota)</th><th>Status</th></tr></thead>
    <tbody id="rows"></tbody></table></div>
  <p class="note">DECISION_LOG.md is <b>uncapped by design</b> (append-only, tool-pull only) -- shown for reference, not scored. Reds are the tracked PB-3 doc-debt (+ any small stable doc nudging over).</p>
  <h2>Per-iteration worker-context (worker-spec bytes emitted each wave)</h2>
  <div class="card chartcard"><div id="chart"></div><div class="tip" id="tip"></div>
    <p class="note">The size of the worker briefs a wave hands to fresh fan-out sessions (<code>workers-i&lt;N&gt;.json</code>) -- a proxy for the context each fresh agent ingests; the growth to watch for stall-out.</p></div>
  <h2>Frontier packs (couriered) -- context bundles, not doc bloat</h2>
  <div class="card"><table><thead><tr><th>Frontier pack</th><th class="num">Size</th><th>Note</th></tr></thead><tbody id="frows"></tbody></table></div>
  <p class="note">Frontier packs inline the full text of the governing docs they reference, so size &asymp; the docs carried, not orchestration overhead. Tracked so a growing frontier-review cost stays visible.</p>
  <div class="foot">Regenerated by the orchestrator at each wave close (a deterministic read over <code>wc -c core-docs/*.md</code> + DOC_PROTOCOL s2 budgets + <code>runtime/</code> artifact sizes) -- a snapshot row also appends to <code>ops/out/doc-health-log.jsonl</code>. Zero doc-upkeep. To fold into the audit sub-agent wrap once memory/audit matures (D-0101 / PB-4), so the monitor never becomes the bloat it measures.</div>
</div>
<script>
const KB=1000;
const docs=/*__DOCS__*/[];
const uncapped=/*__UNCAPPED__*/[];
const iters=/*__ITERS__*/[];
const packs=/*__PACKS__*/[];
const cls=p=>p>110?"red":(p>90?"yel":"grn");
const label=c=>({red:"Over budget",yel:"Watch",grn:"Healthy"}[c]);
const dot=c=>({red:"var(--crit)",yel:"var(--warn)",grn:"var(--good)"}[c]);
const kb=b=>(b/KB).toFixed(b<10*KB?1:0);
const scored=docs.map(([n,b,q])=>({n,b,q,p:b/(q*KB)*100})).sort((a,z)=>z.p-a.p);
let counts={red:0,yel:0,grn:0};
document.getElementById("rows").innerHTML=scored.map(d=>{const c=cls(d.p);counts[c]++;
  const fill=Math.min(d.p,140)/140*100,qpos=100/140*100;
  return `<tr><td class="doc">${d.n}</td><td class="num">${kb(d.b)} KB</td><td class="num">${d.q} KB</td><td class="num">${d.p.toFixed(0)}%</td><td><div class="meter"><i style="width:${fill}%;background:${dot(c)}"></i><span class="q" style="left:${qpos}%"></span></div></td><td><span class="chip ${c}"><span class="dot"></span>${label(c)}</span></td></tr>`;
}).join("")+uncapped.map(([n,b])=>`<tr><td class="doc">${n}</td><td class="num">${kb(b)} KB</td><td class="num">&mdash;</td><td class="num">&mdash;</td><td><span class="small">uncapped (append-only)</span></td><td><span class="chip na"><span class="dot"></span>Not scored</span></td></tr>`).join("");
document.getElementById("kpis").innerHTML=[["grn",counts.grn,"Healthy (&le;90%)"],["yel",counts.yel,"Watch (90-110%)"],["red",counts.red,"Over budget (&gt;110%)"],["",(scored[0]?scored[0].p.toFixed(0)+"%":"-"),"Worst: "+(scored[0]?scored[0].n.replace(".md",""):"-")]].map(([k,n,l])=>`<div class="kpi ${k}"><div class="n">${n}</div><div class="l">${l}</div></div>`).join("");
document.getElementById("frows").innerHTML=packs.map(([n,b])=>`<tr><td class="doc">${n}</td><td class="num">${kb(b)} KB</td><td class="small">inlined governing docs</td></tr>`).join("");
(function(){const W=980,H=230,padL=34,padR=8,padT=18,padB=26;
  if(!iters.length){return;}
  const max=Math.max(...iters.map(d=>d[1])),yTop=Math.max(10000,Math.ceil(max/5000)*5000);
  const iw=(W-padL-padR)/iters.length,bw=Math.min(iw*0.62,26);
  const x=i=>padL+i*iw+(iw-bw)/2,y=v=>padT+(1-v/yTop)*(H-padT-padB);
  const pk=iters.reduce((m,d,i)=>d[1]>iters[m][1]?i:m,0);
  let g="";for(let t=0;t<=yTop;t+=10000){g+=`<line class="gridln" x1="${padL}" x2="${W-padR}" y1="${y(t)}" y2="${y(t)}"/><text class="axlabel" x="${padL-6}" y="${y(t)+3}" text-anchor="end">${t/1000}</text>`;}
  let bars="";iters.forEach((d,i)=>{const bx=x(i),by=y(d[1]),bh=H-padB-by;
    bars+=`<rect class="bar" x="${bx}" y="${by}" width="${bw}" height="${bh}" rx="3" data-it="${d[0]}" data-kb="${(d[1]/1000).toFixed(1)}"></rect>`;
    if(i%2===0||i===iters.length-1)bars+=`<text class="axlabel" x="${bx+bw/2}" y="${H-padB+13}" text-anchor="middle">${d[0]}</text>`;
    if(i===pk||i===iters.length-1)bars+=`<text class="vlabel" x="${bx+bw/2}" y="${by-5}">${(d[1]/1000).toFixed(0)}</text>`;});
  document.getElementById("chart").innerHTML=`<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="worker-spec KB per iteration"><text class="axlabel" x="${padL-6}" y="${padT-6}" text-anchor="end">KB</text>${g}<line class="gridln" x1="${padL}" x2="${W-padR}" y1="${H-padB}" y2="${H-padB}" style="stroke:var(--base)"/>${bars}</svg>`;
  const tip=document.getElementById("tip"),card=document.getElementById("chart").parentElement;
  document.querySelectorAll(".bar").forEach(r=>{r.addEventListener("mousemove",e=>{const cr=card.getBoundingClientRect();tip.style.left=(e.clientX-cr.left)+"px";tip.style.top=(e.clientY-cr.top-8)+"px";tip.style.opacity=1;tip.textContent=`i${r.dataset.it} · ${r.dataset.kb} KB`;});r.addEventListener("mouseleave",()=>tip.style.opacity=0);});
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
