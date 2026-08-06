// deck5_ripwire_build.js — the ripwire public showcase deck.
// Every number is pinned by an instrument in the ripwire repo (docs/EVALS.md is the source of
// truth; §8's refused claims are absent by construction). Every --flag named exists in
// `ripwire --help`. Design: dark, two-tone on the name's own halves — cyan = ripgrep/speed,
// amber = tripwire/honesty.
const pptxgen = require("pptxgenjs");

const p = new pptxgen();
p.layout = "LAYOUT_WIDE"; // 13.33 x 7.5

// palette
const BG    = "0D1117";
const CARD  = "161D28";
const CARD2 = "1B2432";
const TEXT  = "E6EDF3";
const MUTED = "8B95A5";
const CYAN  = "56D6E8";
const AMBER = "F2B84B";
const GREEN = "4AC26B";
const RED   = "E5534B";
const MONO  = "Courier New";
const SANS  = "Arial";

const W = 13.33, H = 7.5, MX = 0.62;

function bg(s){ s.background = { color: BG }; }
function kicker(s, txt, color){ s.addText(txt, { x: MX, y: 0.42, w: 9, h: 0.32, fontFace: MONO, fontSize: 13, color, margin: 0 }); }
function title(s, txt, opts={}){ s.addText(txt, { x: MX, y: 0.72, w: W-2*MX, h: 0.9, fontFace: SANS, fontSize: opts.size||34, bold: true, color: TEXT, margin: 0 }); }
function foot(s, txt){ s.addText(txt, { x: MX, y: 7.02, w: W-2*MX, h: 0.3, fontFace: MONO, fontSize: 10.5, color: MUTED, margin: 0 }); }
function chip(s, txt, x, y, w, color, opts={}){
  s.addShape("roundRect", { x, y, w, h: opts.h||0.42, fill: { color: opts.fill||CARD2 }, rectRadius: 0.06, line: { color: opts.line||"2A3547", width: 0.75 } });
  s.addText(txt, { x: x+0.06, y, w: w-0.12, h: opts.h||0.42, fontFace: MONO, fontSize: opts.size||12.5, color: color||CYAN, valign: "middle", margin: 0.04 });
}
function card(s, x, y, w, h, fill){ s.addShape("roundRect", { x, y, w, h, fill: { color: fill||CARD }, rectRadius: 0.09, line: { color: "232D3D", width: 0.75 } }); }
function stat(s, big, label, x, y, w, color, opts={}){
  s.addText(big,   { x, y,        w, h: opts.bh||0.95, fontFace: SANS, fontSize: opts.bsize||44, bold: true, color, align: "center", margin: 0 });
  s.addText(label, { x, y: y+(opts.bh||0.95)-0.06, w, h: 0.75, fontFace: SANS, fontSize: opts.lsize||12.5, color: opts.lcolor||MUTED, align: "center", margin: 0 });
}

/* ── S1 · title ─────────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  s.addText("ripwire", { x: MX, y: 1.55, w: 8.4, h: 1.35, fontFace: MONO, fontSize: 76, bold: true, color: TEXT, margin: 0 });
  s.addText("The ripgrep of AI context.", { x: MX, y: 2.95, w: 9.5, h: 0.6, fontFace: SANS, fontSize: 27, bold: true, color: TEXT, margin: 0 });
  s.addText("A zero-runtime-dependency C++23 CLI that maps any codebase into a ranked, deterministic\ncall graph for coding agents — and puts a tripwire on every claim it emits.",
    { x: MX, y: 3.6, w: 10.6, h: 0.95, fontFace: SANS, fontSize: 16, color: MUTED, margin: 0 });

  card(s, MX, 4.85, 5.9, 1.35);
  s.addText([{ text: "rip", options: { color: CYAN, bold: true } }, { text: " — the speed half", options: { color: TEXT, bold: true } }],
    { x: MX+0.25, y: 5.0, w: 5.4, h: 0.4, fontFace: SANS, fontSize: 16, margin: 0 });
  s.addText("Structural answers in tens of milliseconds, from a call graph it built itself.",
    { x: MX+0.25, y: 5.42, w: 5.4, h: 0.65, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  card(s, MX+6.2, 4.85, 5.9, 1.35);
  s.addText([{ text: "wire", options: { color: AMBER, bold: true } }, { text: " — the honesty half", options: { color: TEXT, bold: true } }],
    { x: MX+6.45, y: 5.0, w: 5.4, h: 0.4, fontFace: SANS, fontSize: 16, margin: 0 });
  s.addText("Unprovable totals ship labelled as floors. A zero means none found — never none exists.",
    { x: MX+6.45, y: 5.42, w: 5.4, h: 0.65, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  foot(s, "Apache-2.0  ·  single binary  ·  hermetic build (proven with the network off)  ·  15 vendored tree-sitter grammars");
}

/* ── S2 · the problem ───────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the problem", CYAN);
  title(s, "Your agent reads the whole library to answer one question");
  s.addText([
    { text: "Blind grep, then whole-file reads. Most of what enters the context window is never used — it is paid for anyway, on every step of every task.\n\n", options: {} },
    { text: "And bigger context is not better context: irrelevant text actively degrades the answer. The job is selection — a small, ranked, structural map beats a pile of open files.", options: {} },
  ], { x: MX, y: 1.95, w: 6.1, h: 3.2, fontFace: SANS, fontSize: 16.5, color: TEXT, margin: 0 });

  card(s, 7.25, 1.95, 5.35, 2.15);
  stat(s, "0.114 s", "median answer, warm index — latest head-to-head round, N = 60", 7.35, 2.2, 5.15, CYAN, {});
  card(s, 7.25, 4.3, 5.35, 2.15);
  stat(s, "−39.4%", "token ceiling vs the un-routed baseline — LocBench cost ledger, N = 243", 7.35, 4.55, 5.15, GREEN, {});
  s.addText("Speed caveat travels with the number: ripwire answers from a warm, pre-built index; competitor medians include their per-question work. Same instances, same gold, same metric code.",
    { x: MX, y: 5.5, w: 6.1, h: 1.2, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
  foot(s, "bench/headtohead/r2-2026-08-03/ · bench/locbench/ — every figure on this deck names its instrument");
}

/* ── S3 · what it is ────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// one binary, the whole pipeline", CYAN);
  title(s, "Crawl → parse → resolve → rank → emit. Deterministic, end to end.");
  const stages = [
    ["crawl",   "the tree, no VCS needed"],
    ["parse",   "tree-sitter, 15 vendored grammars"],
    ["resolve", "references → call graph"],
    ["rank",    "Personalized PageRank"],
    ["emit",    "minified XML, one line"],
  ];
  const bw = 2.25, gap = 0.22; let x = MX;
  for (const [name, sub] of stages){
    card(s, x, 2.2, bw, 1.5, CARD2);
    s.addText(name, { x: x+0.12, y: 2.38, w: bw-0.24, h: 0.45, fontFace: MONO, fontSize: 17, bold: true, color: CYAN, margin: 0 });
    s.addText(sub,  { x: x+0.12, y: 2.86, w: bw-0.24, h: 0.75, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
    if (name !== "emit") s.addText("→", { x: x+bw-0.04, y: 2.62, w: 0.32, h: 0.5, fontFace: SANS, fontSize: 20, color: MUTED, margin: 0 });
    x += bw + gap;
  }
  const props = [
    ["byte-identical", "two runs, same bytes — a gate on every push, not a tendency; warm equals cold"],
    ["zero runtime deps", "CMake + a C++23 compiler; builds with the network off — vendored everything"],
    ["11 languages", "C/C++, ObjC, Python, TS/JS, Java, Go, Rust, Ruby, Swift, C#, Bash — plus JSON and Metal (a C++ dialect)"],
    ["agent-native", "an MCP server and 135 long flags behind one `--help` that is always the authority"],
  ];
  let y = 4.15;
  for (const [h2, b] of props){
    card(s, MX, y, 12.09, 0.68);
    s.addText(h2, { x: MX+0.2, y: y+0.05, w: 2.9, h: 0.58, fontFace: MONO, fontSize: 13.5, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+3.2, y: y+0.05, w: 8.7, h: 0.58, fontFace: SANS, fontSize: 12.5, color: TEXT, valign: "middle", margin: 0 });
    y += 0.78;
  }
}

/* ── S4 · seven families ────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// every feature, one screen", CYAN);
  title(s, "Seven families of questions it answers");
  const fams = [
    ["understand cold",  "What is this repo, and what matters in it?",          "--for  --tree  --lego  --exemplar  --recall  --top-k  --token-budget"],
    ["navigate",         "Who calls this? Safe to change? Which tests?",        "--callers  --callees  --uses  --impact  --path  --connect  --affected  --situ  --test-gate  --grep"],
    ["detail ladder",    "Show me more — but only where it pays.",              "--detail  --pack-signatures  --outline  --expand  --compress"],
    ["quality & risk",   "Where is the risk, and did I just add some?",         "--hotspots  --clones  --metrics  --deps  --lint  --quality-delta  --edit-check  --pr-context  --merge-scout"],
    ["self-diagnosis",   "Is my setup actually working?",                       "--doctor"],
    ["security",         "Is this agent skill file safe to install?",           "--scan-skill  --scan-skills"],
    ["knobs & modes",    "Shape, format, cache, budget.",                       "--json  --format  --mcp"],
  ];
  let y = 1.85;
  for (const [fam, q, flags] of fams){
    card(s, MX, y, 12.09, 0.66, CARD);
    s.addText(fam,   { x: MX+0.18, y: y+0.04, w: 2.35, h: 0.58, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(q,     { x: MX+2.65, y: y+0.04, w: 3.85, h: 0.58, fontFace: SANS, fontSize: 11,  italic: true, color: MUTED, valign: "middle", margin: 0 });
    s.addText(flags, { x: MX+6.6,  y: y+0.04, w: 5.35, h: 0.58, fontFace: MONO, fontSize: 9.5, color: CYAN, valign: "middle", margin: 0 });
    y += 0.74;
  }
  foot(s, "ripwire --help is generated from the binary's own flag table — 135 long flags; docs/COMMANDS.md documents 90 of them with real recorded output");
}

/* ── S5 · the moments ───────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// reach for it at the moment, not the manual", CYAN);
  title(s, "The reflexes: which verb fires when");
  const moments = [
    ["Landing cold on a task",        "--for=\"<task>\"  ·  --pack-task", "ranked, budgeted context in one call"],
    ["Stack trace in hand",           "--from-trace",                     "frames mapped to symbols, innermost body included"],
    ["“Is it safe to change X?”", "--impact  ·  --uses",         "the whole blast radius, not just 1-hop callers"],
    ["Just edited a symbol",          "--edit-check",                     "did the contract change, who breaks — ~ms, warm"],
    ["About to write a helper",       "--exemplar  ·  --grep",            "imitate the house pattern; catch the duplicate early"],
    ["Landing several branches",      "--merge-scout",                    "pairwise conflict sites + a landing order"],
    ["Before you call it done",       "--quality-delta  ·  --test-gate",  "only what you made worse; exactly which tests to run"],
    ["Reviewing a diff",              "--pr-context",                     "per-file blast radius, tests-to-run, hotspot flags"],
  ];
  const cw = 5.95, ch = 1.08; let i = 0;
  for (const [when, flags, what] of moments){
    const x = MX + (i % 2) * (cw + 0.19), y = 1.9 + Math.floor(i / 2) * (ch + 0.16);
    card(s, x, y, cw, ch);
    s.addText(when,  { x: x+0.18, y: y+0.08, w: cw-0.36, h: 0.34, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
    s.addText(flags, { x: x+0.18, y: y+0.42, w: cw-0.36, h: 0.3,  fontFace: MONO, fontSize: 11.5, color: CYAN, margin: 0 });
    s.addText(what,  { x: x+0.18, y: y+0.72, w: cw-0.36, h: 0.32, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });
    i++;
  }
}

/* ── S6 · head-to-head ──────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// same instances, same gold, same metric code", AMBER);
  title(s, "Head-to-head: every round, every tool");
  const H2H_CHART = (label, arms, vals, colors, yTop, hChart, vMax) => {
    s.addText(label, { x: MX, y: yTop, w: 7.3, h: 0.28, fontFace: SANS, fontSize: 11.5, bold: true, color: TEXT, margin: 0 });
    s.addChart("bar", [{ name: "strict file@10", labels: arms, values: vals }], {
      x: MX, y: yTop+0.3, w: 7.3, h: hChart, barDir: "bar",
      chartColors: colors,
      showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.0", dataLabelColor: TEXT, dataLabelFontSize: 11, dataLabelFontFace: SANS,
      catAxisLabelColor: TEXT, catAxisLabelFontSize: 10.5, catAxisLabelFontFace: SANS,
      valAxisLabelColor: MUTED, valAxisLabelFontSize: 9, valAxisMaxVal: vMax, valAxisMinVal: 0,
      valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
      showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
      barGapWidthPct: 50,
    });
  };
  H2H_CHART("Round 2 (2026-08-03) — strict file@10, N = 60",
    ["ripwire --for", "repowise 0.37.0", "codeseek 0.1.31 (ident arm)", "codeseek 0.1.31 (raw fallback)"],
    [58.3, 33.3, 15.0, 0.0], [CYAN, "3A4353", "3A4353", "3A4353"], 1.82, 2.25, 70);
  H2H_CHART("Round 1 — strict file@10, N = 60 (own binary + evaluator; rounds are not number-comparable)",
    ["ripwire --for", "codebase-memory-mcp", "graphify", "Aider repo-map"],
    [36.7, 26.7, 21.7, 13.3], [CYAN, "3A4353", "3A4353", "3A4353"], 4.5, 2.25, 45);
  card(s, 8.2, 1.95, 4.4, 1.7);
  stat(s, "58.3%", "strict file@10 — every gold file in the top ten\nN = 60 paired, zero exclusions · 17–2 paired vs repowise", 8.3, 2.1, 4.2, CYAN, { lsize: 11 });
  card(s, 8.2, 3.75, 4.4, 1.7);
  s.addText([
    { text: "Median wall (query, warm): ", options: { color: TEXT, bold: true } },
    { text: "ripwire 0.114 s · repowise 1.14 s (incl. a per-query server spawn) — round 1: Aider 2.5 s · graphify 5.8 s, cold per run.\n", options: { color: MUTED } },
    { text: "codeseek's raw arm: 0 results on 60/60 — a query-protocol boundary, not its embedder mode. Vexp and CodeIndexer were excluded by free-tier caps, not beaten.", options: { color: MUTED } },
  ], { x: 8.4, y: 3.88, w: 4.05, h: 1.5, fontFace: SANS, fontSize: 10, margin: 0 });
  card(s, 8.2, 5.6, 4.4, 1.1);
  s.addText([
    { text: "Round 3, different instrument: ", options: { color: TEXT, bold: true } },
    { text: "headroom (the compression layer) passed code through byte-identical; ripwire answered at 7.3% of the naive baseline's tokens.", options: { color: MUTED } },
  ], { x: 8.4, y: 5.71, w: 4.05, h: 0.92, fontFace: SANS, fontSize: 10, margin: 0 });
  foot(s, "bench/headtohead/REPORT.md (r1) · r2-2026-08-03/ · r3-headroom-2026-08-03/ · docs/EVALS.md §2 — an adversarial VERIFIER.md ships with each round");
}

/* ── S7 · locbench ──────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// held-out, repo-disjoint, frozen dataset", AMBER);
  title(s, "Routing the ranker: +33 points, measured properly");
  s.addChart("bar", [{
    name: "strict file@10",
    labels: ["pre-routing baseline", "routed --for (shipping)"],
    values: [27.6, 60.9],
  }], {
    x: MX, y: 2.1, w: 6.3, h: 3.9, barDir: "col",
    chartColors: ["3A4353", GREEN],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.0", dataLabelColor: TEXT, dataLabelFontSize: 15, dataLabelFontFace: SANS,
    catAxisLabelColor: TEXT, catAxisLabelFontSize: 12.5, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 10, valAxisMaxVal: 70, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 80,
  });
  const rows = [
    ["+33.33pp", "paired delta, 243 held-out instances in 78 repository clusters", GREEN],
    ["+25.00pp", "clustered-bootstrap 95% lower bound — the honest floor", GREEN],
    ["−39.4%", "token ceiling for that gain", CYAN],
    ["+3.4%", "warm latency for that gain", MUTED],
  ];
  let y = 2.1;
  for (const [n, l, c] of rows){
    card(s, 7.3, y, 5.3, 0.86);
    s.addText(n, { x: 7.5, y: y+0.06, w: 1.75, h: 0.74, fontFace: SANS, fontSize: 21, bold: true, color: c, valign: "middle", margin: 0 });
    s.addText(l, { x: 9.3, y: y+0.06, w: 3.2, h: 0.74, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    y += 0.98;
  }
  foot(s, "bench/locbench/ — czlll/Loc-Bench_V1, 560 rows, JSON SHA-256 pinned in dataset.lock; metric code = LocAgent's strict Acc@k");
}

/* ── S7b · how much faster (cold-to-cold) ───────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// compiled, not interpreted", CYAN);
  title(s, "How much faster: same algorithm, 9-42\u00d7 the speed");
  s.addChart("bar", [{
    name: "cold-to-cold speedup vs Aider repo-map (\u00d7)",
    labels: ["repo A", "repo B", "repo C", "repo D", "repo E"],
    values: [11.3, 19.1, 9.1, 31.6, 42.0],
  }], {
    x: MX, y: 2.0, w: 6.6, h: 4.2, barDir: "col",
    chartColors: [CYAN, CYAN, CYAN, CYAN, CYAN],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.0\"\u00d7\"", dataLabelColor: TEXT, dataLabelFontSize: 12, dataLabelFontFace: SANS,
    catAxisLabelColor: MUTED, catAxisLabelFontSize: 11, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 10, valAxisMaxVal: 45, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 55,
  });
  s.addText("Five repositories, tag caches cleared each run, minimum of N runs. Same pipeline on both sides \u2014 tree-sitter parse then PageRank \u2014 so the gap is compiled versus interpreted.",
    { x: MX, y: 6.3, w: 6.6, h: 0.7, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });
  card(s, 7.55, 2.0, 5.05, 1.9);
  s.addText([
    { text: "1,560-file repository\n", options: { color: TEXT, bold: true, fontSize: 13 } },
    { text: "~1 s cold \u00b7 0.18 s warm", options: { color: CYAN, bold: true, fontSize: 22 } },
    { text: "\nAider's map of the same tree: 40 s cold", options: { color: MUTED, fontSize: 11.5 } },
  ], { x: 7.75, y: 2.2, w: 4.65, h: 1.55, fontFace: SANS, margin: 0 });
  card(s, 7.55, 4.1, 5.05, 2.1);
  s.addText([
    { text: "Where the second goes (self-profiled)\n", options: { color: TEXT, bold: true, fontSize: 13 } },
    { text: "parse ~780 ms \u2192 33 ms warm (24\u00d7, the cache)\nresolve + PageRank together: ~21 ms\n", options: { color: MUTED, fontSize: 11.5 } },
    { text: "The ranking is the cheap part \u2014 the graph math was never the bottleneck.", options: { color: CYAN, fontSize: 11.5, italic: true } },
  ], { x: 7.75, y: 4.3, w: 4.65, h: 1.8, fontFace: SANS, margin: 0 });
  foot(s, "bench/BENCHMARK.md (caveat: measured 2026-06-20 on a large private C++ corpus \u2014 historical, not publicly reproducible) \u00b7 bench/PROFILE.md");
}

/* ── S7b2 · the performance sprint ──────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the performance sprint", CYAN);
  title(s, "Half the wait: work removed before work optimized");
  const stats = [
    ["100 ms", "cold C++ run — was 190 ms, −47%", CYAN],
    ["20 ms",  "warm cache run — was 40 ms, half", CYAN],
    ["< 3 ms", "graph + rank + emit — below the noise floor", GREEN],
    ["green",  "determinism, ASan, det-gate and cache gates — unchanged", AMBER],
  ];
  let sx = MX;
  for (const [n, l, c] of stats){
    card(s, sx, 1.95, 2.93, 1.5);
    stat(s, n, l, sx+0.08, 2.12, 2.77, c, { bsize: 30, bh: 0.62, lsize: 10 });
    sx += 3.05;
  }
  const wins = [
    ["file ingest",    "FILE* whole-file reads; CSV counting became a byte scan — iostream out of the hot path"],
    ["--no-cache",     "skips contentHash64() entirely when no lookup or save can use it — pure waste removed"],
    ["capture gating", "value-use capture runs only for --uses, --metrics, --for and --exemplar — side captures 404 → 57 ms"],
    ["parallel parse", "query compile overlaps parse scheduling; files schedule by size — ids stay deterministic"],
    ["backlog cap",    "parsed-file backlog bounded at 4 files / 8 MiB per worker — memory pressure stays sane"],
  ];
  let y = 3.7;
  for (const [h2, b] of wins){
    card(s, MX, y, 12.09, 0.56);
    s.addText(h2, { x: MX+0.2, y: y+0.03, w: 2.5, h: 0.5, fontFace: MONO, fontSize: 12.5, bold: true, color: CYAN, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+2.9, y: y+0.03, w: 9.0, h: 0.5, fontFace: SANS, fontSize: 11.5, color: TEXT, valign: "middle", margin: 0 });
    y += 0.64;
  }
  foot(s, "pre-release performance sprint — measured on the private ~1,500-file C++ corpus (historical, not publicly reproducible); same map contract: byte-identical output before and after");
}

/* ── S7b3 · sort + infra, and where the time goes now ───────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// where the time goes now", CYAN);
  title(s, "Faster at scale — and the long pole is the parser");
  const infra = [
    ["radix edges",     "numeric keys for graph edges — ~6× edge sort at scale, on the production graph path"],
    ["radix scores",    "score/id ordering made numeric — 5.8–8.5× in benchmarks, deterministic tie-break kept"],
    ["timsort scratch", "caller-owned scratch buffer, no per-frame allocation — best on nearly-sorted updates"],
    ["pdqsort bench",   "added as the adversarial baseline; std::sort held up well — the baseline keeps us honest"],
    ["S+tree hot map",  "bounded-scratch dynamic map: 20.4 ms vs 68.3 ms lookup — a fixed-cap guard reports overflow"],
    ["hash lookup",     "unordered_dense HashMap, reserve() before ingest — no std::unordered_map on any hot path"],
  ];
  const cw = 3.95, ch = 1.62; let i = 0;
  for (const [h2, b] of infra){
    const x = MX + (i % 3) * (cw + 0.12), y = 1.95 + Math.floor(i / 3) * (ch + 0.16);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.18, y: y+0.12, w: cw-0.36, h: 0.36, fontFace: MONO, fontSize: 12.5, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.18, y: y+0.5,  w: cw-0.36, h: 1.05, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "top", margin: 0 });
    i++;
  }
  card(s, MX, 5.5, 12.09, 1.15, CARD2);
  s.addText([
    { text: "Cold profiles are now tree-sitter parse + tag-query capture, not graph math. ", options: { color: TEXT } },
    { text: "Demand-driven captures already cut 404 → 57 ms; the next wins are query- and grammar-specific. ", options: { color: MUTED } },
    { text: "Same stuff it needs to do — just a lot less waiting.", options: { color: CYAN, italic: true } },
  ], { x: MX+0.25, y: 5.62, w: 11.6, h: 0.9, fontFace: SANS, fontSize: 12.5, valign: "middle", margin: 0 });
  foot(s, "pre-release performance sprint — sort/index wins matter most past cache scale; determinism and sanitizer gates stayed green throughout");
}

/* ── S7c · the token bill, cut ──────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the token bill, cut", CYAN);
  title(s, "Six real agent questions: 24.9\u00d7 fewer tokens than the naive read");
  s.addChart("bar", [{
    name: "tokens",
    labels: ["naive: grep dump + whole-file reads", "ripwire answers"],
    values: [367192, 14758],
  }], {
    x: MX, y: 2.1, w: 7.2, h: 3.6, barDir: "bar",
    chartColors: ["3A4353", CYAN],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "#,##0", dataLabelColor: TEXT, dataLabelFontSize: 13, dataLabelFontFace: SANS,
    catAxisLabelColor: TEXT, catAxisLabelFontSize: 12, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 9, valAxisMaxVal: 400000, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 70,
  });
  card(s, 8.1, 2.1, 4.5, 1.8);
  stat(s, "96.0%", "fewer tokens \u2014 14,758 vs 367,192, tiktoken cl100k_base,\nsix questions: who-calls, orientation, blast radius \u2026", 8.2, 2.3, 4.3, GREEN, { bsize: 40, lsize: 10.5 });
  card(s, 8.1, 4.1, 4.5, 1.6);
  s.addText([
    { text: "The anti-headline, published next to it: ", options: { color: MUTED } },
    { text: "--grep costs +19.7% tokens (\u221211.2%)", options: { color: AMBER, bold: true, fontFace: MONO } },
    { text: " \u2014 not every verb is a reducer, and the docs say which.", options: { color: MUTED } },
  ], { x: 8.3, y: 4.28, w: 4.1, h: 1.3, fontFace: SANS, fontSize: 11.5, margin: 0 });
  s.addText("Caveat carried with every figure on this slide: measured 2026-06-20 on a large private C++ corpus \u2014 historical, private, not publicly reproducible. The public, gated companions are the 67.0% element-byte reduction and LocBench's \u221239.4% ceiling.",
    { x: MX, y: 6.15, w: 7.2, h: 0.85, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });
  foot(s, "bench/BENCHMARK.md \u00b7 docs/EVALS.md \u00a75 \u2014 the baseline is what an agent does WITHOUT the tool");
}

/* ── S8 · token economy ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the cost lever", CYAN);
  title(s, "Smaller answers that are also better answers");
  card(s, MX, 1.95, 5.9, 2.5);
  stat(s, "67.0%", "fewer element bytes at top-50 — the --pack-signatures ladder,\nroot-neutralised measurement", MX+0.2, 2.25, 5.5, CYAN, { bsize: 52, lsize: 12 });
  card(s, MX, 4.65, 5.9, 1.9);
  s.addText("This figure survived its own audit: three corrections deep, re-derived root-neutrally after the original was shown to depend on how the corpus path was spelled. A gate re-derives it against every fresh capture.",
    { x: MX+0.25, y: 4.85, w: 5.4, h: 1.55, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  card(s, 7.25, 1.95, 5.35, 2.5);
  s.addText("Ask for a symbol by NAME and the router uses the name-exact ranker:", { x: 7.5, y: 2.15, w: 4.9, h: 0.6, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "MRR  0.859 → 0.993\n", options: { color: GREEN, bold: true } },
    { text: "recall@1  76.7% → 98.7%\n", options: { color: GREEN, bold: true } },
    { text: "name-shaped queries on src/, held-out labels", options: { color: MUTED } },
  ], { x: 7.5, y: 2.8, w: 4.9, h: 1.5, fontFace: MONO, fontSize: 14, margin: 0 });
  card(s, 7.25, 4.65, 5.35, 1.9);
  s.addText("And the pollution metric — fixture and generated paths contaminating results — is driven to 0.0% on the ranking lane while recall went UP, not down.",
    { x: 7.5, y: 4.85, w: 4.9, h: 1.55, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  foot(s, "docs/EVALS.md §4–§5 — showcasecapturecheck re-derives the byte-reduction triple; recallevalcheck pins the ranking bars");
}

/* ── S9 · the tripwire ──────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the half no other tool ships", AMBER);
  title(s, "The tripwire: honesty as an output contract");
  const rules = [
    ["counts_floor=\"1\"", "call edges come from source text — dynamic dispatch adds no edge, so every count that cannot claim completeness is labelled a floor, in the output itself"],
    ["a zero is a measurement", "zero means none found, never none exists — and absent ≠ 0"],
    ["truncation is disclosed", "every cap, page seam and budget cut is named in the header before you read a row"],
    ["refusals teach", "a refused query names the flag, the problem, and a working example — never a bare error"],
  ];
  let y = 1.95;
  for (const [h2, b] of rules){
    card(s, MX, y, 7.6, 1.06);
    s.addText(h2, { x: MX+0.2, y: y+0.09, w: 7.2, h: 0.36, fontFace: MONO, fontSize: 13.5, bold: true, color: AMBER, margin: 0 });
    s.addText(b,  { x: MX+0.2, y: y+0.45, w: 7.2, h: 0.55, fontFace: SANS, fontSize: 11, color: MUTED, margin: 0 });
    y += 1.18;
  }
  card(s, 8.5, 1.95, 4.1, 3.1, CARD2);
  s.addText("$ ripwire . --callers=rankGraphTeleport", { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });
  s.addText([
    { text: "<callers of=\"rankGraphTeleport\"\n  defs=\"1\" count=\"6\" ", options: { color: TEXT } },
    { text: "counts_floor=\"1\"", options: { color: AMBER, bold: true } },
    { text: ">\n<s t=\"fn\" n=\"runEval\" .../>\n<s t=\"fn\" n=\"rankGraph\" .../>\n…\n</callers>", options: { color: TEXT } },
  ], { x: 8.68, y: 2.42, w: 3.8, h: 2.5, fontFace: MONO, fontSize: 10.5, valign: "top", margin: 0 });
  card(s, 8.5, 5.25, 4.1, 1.35);
  s.addText([
    { text: "docs/EVALS.md §8", options: { color: AMBER, bold: true, fontFace: MONO } },
    { text: " — the list of numbers this project refuses to publish, each with the reason. The counterexample section is not an afterthought.", options: { color: MUTED } },
  ], { x: 8.68, y: 5.4, w: 3.8, h: 1.1, fontFace: SANS, fontSize: 11, margin: 0 });
}

/* ── S10 · proven, not promised ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// how it stays true", AMBER);
  title(s, "Proven, not promised");
  const cards = [
    ["334 gate scripts", "the suite runs on every push — plus determinism, cache-transparency and golden contracts; the gate count itself is gated against the runner's own loop"],
    ["byte-identical, always", "two runs over the same tree produce the same bytes; warm equals cold. Enforced in CI, twice — Release AND a plain flavour, because NDEBUG once blinded a whole class of checks"],
    ["differential refactoring", "a refactor must prove it changed nothing observable: two binaries, hundreds of argv vectors, stdout + stderr + exit codes byte-identical"],
    ["held-out labels, authored blind", "eval labels were written by reading source before the ranker ever ran on them — so the eval is allowed to say the ranker is wrong. It has."],
    ["sanitizer wall", "ASan + UBSan + integer + float-cast, no-recover; TSan separately; leak suppression is one pinned file"],
    ["its own output is audited", "the showcase capture is regenerated and adversarially re-read as a claims corpus — the methodology ships in docs/METHODOLOGY.md"],
  ];
  const cw = 3.95, ch = 2.2; let i = 0;
  for (const [h2, b] of cards){
    const x = MX + (i % 3) * (cw + 0.12), y = 1.95 + Math.floor(i / 3) * (ch + 0.18);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.18, y: y+0.14, w: cw-0.36, h: 0.62, fontFace: SANS, fontSize: 14.5, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.18, y: y+0.6, w: cw-0.36, h: 1.5, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "top", margin: 0 });
    i++;
  }
}

/* ── S11 · where it loses ───────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// own the losses — they are in the README too", AMBER);
  title(s, "Where it loses, published with the wins");
  const rows = [
    ["--grep costs more than it saves", "+19.7% tokens / −11.2% — measured, in the docs, next to the flag it indicts"],
    ["PageRank is the wrong co-change ranker", "3.8% recall@5 against 40.3% for plain lexical — relatedness is lexical; importance is structural"],
    ["a signature can outweigh its body", "one symbol's signature + doc comment: 303 bytes; its full body: 158 — the compact form lost"],
    ["strict multi-file localization stays hard", "single-file gold 73.4% vs multi-file 18.2% (held-out); the same cliff on every corpus — open headroom, said plainly"],
  ];
  let y = 2.0;
  for (const [h2, b] of rows){
    card(s, MX, y, 12.09, 1.02);
    s.addText(h2, { x: MX+0.22, y: y+0.08, w: 5.4, h: 0.86, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+5.8,  y: y+0.08, w: 6.05, h: 0.86, fontFace: SANS, fontSize: 11.5, color: MUTED, valign: "middle", margin: 0 });
    y += 1.16;
  }
  s.addText("A tool that publishes its counterexamples is a tool whose wins you can believe.",
    { x: MX, y: 6.65, w: 12.0, h: 0.4, fontFace: SANS, fontSize: 14, italic: true, color: AMBER, margin: 0 });
}

/* ── S12 · agent wiring ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// built for the agent's seat", CYAN);
  title(s, "Wire it into Codex in one command", { size: 30 });
  chip(s, "$ codex mcp add ripwire -- ripwire --mcp", MX, 2.0, 6.8, GREEN, { size: 13.5, h: 0.55 });
  s.addText("plugin bundle also ships all 17 skills", { x: 7.7, y: 2.0, w: 4.9, h: 0.55, fontFace: SANS, fontSize: 12, color: MUTED, valign: "middle", margin: 0 });
  const cards = [
    ["30 MCP verbs", "15 read verbs mirroring the CLI, 12 flagship reflexes (impact, uses, edit_check, from_trace, connect …), 3 span-addressed edit verbs with a safety contract"],
    ["lazy-body handles", "read verbs return signatures and a stable handle; the agent fetches a body only when it decides it needs one — names by default, bytes on request"],
    ["17 agent skills", "moment-matched workflows (orient, navigate, change-check, quality-bar …), bundled in the Codex plugin or installed by skills/install.sh"],
    ["prompts/ — self-improvement", "ten copy-paste orchestrator loops: run the same audit, eval and head-to-head machinery that built the tool, on your own repo"],
  ];
  const cw = 5.95, ch = 1.72; let i = 0;
  for (const [h2, b] of cards){
    const x = MX + (i % 2) * (cw + 0.19), y = 2.85 + Math.floor(i / 2) * (ch + 0.18);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.2, y: y+0.12, w: cw-0.4, h: 0.4, fontFace: MONO, fontSize: 14, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.2, y: y+0.55, w: cw-0.4, h: 1.1, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
    i++;
  }
  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");
}

/* ── S12b · the research inside ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// standing on giants", AMBER);
  title(s, "The research inside \u2014 classic and current");
  s.addText([
    { text: "29 repositories + 37 papers folded", options: { color: TEXT, bold: true } },
    { text: "  \u00b7  220 more surveyed and labeled \u2014 every row with the lesson taken and where it lives: docs/LINEAGE.md", options: { color: MUTED } },
  ], { x: MX, y: 1.58, w: 12.0, h: 0.34, fontFace: SANS, fontSize: 13, margin: 0 });
  const classics = [
    ["1976", "Cyclomatic complexity \u2014 McCabe", "the metric behind --hotspots"],
    ["1994", "Okapi BM25 \u2014 Robertson \u00b7 Sp\u00e4rck Jones", "the lexical ranker (twice: subtoken+body, whole-name)"],
    ["1998", "Personalized PageRank \u2014 Page \u00b7 Brin", "the headline importance signal"],
    ["1999", "HITS hubs & authorities \u2014 Kleinberg", "the alternate lens (--rank-by=authority|hub)"],
    ["2008", "Louvain modularity \u2014 Blondel et al.", "the module / community map"],
    ["2009", "Reciprocal Rank Fusion \u2014 Cormack et al.", "deterministic signal fusion (--rank-by=rrf)"],
  ];
  let y = 2.05;
  for (const [yr, t, d] of classics){
    card(s, MX, y, 6.1, 0.72);
    s.addText(yr, { x: MX+0.16, y: y+0.05, w: 0.75, h: 0.62, fontFace: MONO, fontSize: 12.5, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText([
      { text: t + "\n", options: { color: TEXT, bold: true, fontSize: 11.5 } },
      { text: d, options: { color: MUTED, fontSize: 10 } },
    ], { x: MX+1.0, y: y+0.05, w: 5.0, h: 0.62, fontFace: SANS, valign: "middle", margin: 0 });
    y += 0.82;
  }
  const modern = [
    ["TDAD \u00b7 arXiv 2603.17973", "a static test-map cut agent-caused regressions 6.08% \u2192 1.82%; prose TDD instructions alone made agents WORSE \u2192 the shape of --test-gate"],
    ["What-to-Retrieve \u00b7 arXiv 2503.20589", "retrieval selection beats retrieval volume for coding agents \u2192 the selection-over-dumping thesis"],
    ["LocAgent / Loc-Bench (2025)", "the localization metric (strict Acc@k) and the frozen 560-instance dataset every accuracy number here is scored on"],
    ["tree-sitter", "the incremental GLR parsing substrate \u2014 15 grammars vendored, one parser per thread"],
  ];
  y = 2.05;
  for (const [t, d] of modern){
    card(s, 7.0, y, 5.6, 1.12, CARD2);
    s.addText(t, { x: 7.2, y: y+0.08, w: 5.2, h: 0.34, fontFace: MONO, fontSize: 11.5, bold: true, color: CYAN, margin: 0 });
    s.addText(d, { x: 7.2, y: y+0.44, w: 5.2, h: 0.62, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });
    y += 1.24;
  }
  foot(s, "counts gated in-repo (readmedriftcheck arm E derives them from LINEAGE.md's own tables) \u2014 the lineage is the design rationale, not decoration");
}

/* ── S13 · quickstart / close ───────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// sixty seconds to the first ranked map", CYAN);
  title(s, "Quickstart");
  card(s, MX, 1.95, 12.09, 2.0, CARD2);
  s.addText(
"git clone <repo> && cd ripwire\ncmake -S . -B build && cmake --build build -j     # hermetic: works with the network off\n./build/ripwire --help",
    { x: MX+0.25, y: 2.15, w: 11.6, h: 1.6, fontFace: MONO, fontSize: 14, color: TEXT, margin: 0 });
  const firsts = [
    ["ripwire .", "the ranked map — start here on any unfamiliar repo"],
    ["ripwire . --for=\"cache invalidation\"", "the task lens: what to touch, ranked"],
    ["ripwire . --callers=someFunction", "who calls it — with the honesty marker attached"],
    ["ripwire . --test-gate", "before you commit: exactly which tests must run"],
  ];
  let y = 4.2;
  for (const [cmd, what] of firsts){
    chip(s, cmd, MX, y, 5.7, CYAN, { size: 12.5, h: 0.5 });
    s.addText(what, { x: 6.55, y: y, w: 6.1, h: 0.5, fontFace: SANS, fontSize: 12, color: MUTED, valign: "middle", margin: 0 });
    y += 0.62;
  }
  s.addText([
    { text: "ripgrep", options: { color: CYAN, bold: true } },
    { text: " for the speed. ", options: { color: TEXT } },
    { text: "tripwire", options: { color: AMBER, bold: true } },
    { text: " for the honesty. Apache-2.0.", options: { color: TEXT } },
  ], { x: MX, y: 6.85, w: 12.0, h: 0.45, fontFace: SANS, fontSize: 16, margin: 0 });
}

p.writeFile({ fileName: require("path").join(__dirname, "ripwire-showcase.pptx") })
  .then(() => console.log("WROTE ripwire-showcase.pptx"));
