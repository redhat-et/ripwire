// deck5_ripwire_build.js — the ripwire public showcase deck.
// Every number is pinned by an instrument in the ripwire repo (docs/EVALS.md is the source of
// truth; §8's refused claims are absent by construction). Every --flag named exists in
// `ripwire --help` — enforced by test/deckcheck.sh, which scans THIS FILE as its `present` family;
// the slide count and the flag count are derived from this file and the binary by
// test/deckclaimcheck.sh. Design: dark, two-tone on the name's own halves — cyan = ripgrep/speed,
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
// a compact N-column row band: used by the table-shaped slides (r4, the ten moments, the ledger).
// opts.w NARROWS the band. It defaults to the full text column, which is what every full-width table
// wants — but a slide with cards beside its table needs the band to stop short of them, or the last
// column renders underneath the card and is clipped. That is one parameter, not a second copy of
// this function.
function row(s, y, h, cols, opts={}){
  const w = opts.w || (W - 2*MX);
  card(s, MX, y, w, h, opts.fill);
  let x = MX + 0.18;
  for (const c of cols){
    s.addText(c.t, { x, y: y+0.03, w: c.w, h: h-0.06, fontFace: c.mono ? MONO : SANS, fontSize: c.size||11.5,
                     bold: !!c.bold, italic: !!c.italic, color: c.color||TEXT, valign: "middle", align: c.align||"left", margin: 0 });
    x += c.w + (c.gap === undefined ? 0.12 : c.gap);
  }
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
  foot(s, "Apache-2.0  ·  single binary  ·  hermetic build (proven with the network off)  ·  21 vendored tree-sitter grammars");
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
  stat(s, "0.108 s", "median answer, warm index — round 4, all arms one machine one day, N = 60", 7.35, 2.2, 5.15, CYAN, {});
  card(s, 7.25, 4.3, 5.35, 2.15);
  stat(s, "−39.4%", "token ceiling vs the un-routed baseline — LocBench cost ledger, N = 243", 7.35, 4.55, 5.15, GREEN, {});
  s.addText("Speed caveat travels with the number: ripwire answers from a warm, pre-built index, and round 4 measured its index cost too — 0.31 s, tabulated beside the competitors' rather than omitted.",
    { x: MX, y: 5.5, w: 6.1, h: 1.2, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
  foot(s, "bench/headtohead/r4-2026-08-06/ · bench/locbench/ — every figure on this deck names its instrument");
}

/* ── S3 · what it is ────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// one binary, the whole pipeline", CYAN);
  title(s, "Crawl → parse → resolve → rank → emit. Deterministic, end to end.");
  const stages = [
    ["crawl",   "the tree, no VCS needed"],
    ["parse",   "tree-sitter, 21 vendored grammars"],
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
    ["the languages", "Rust · C++ · ObjC/C++ · C · Metal · CUDA · Python · Go · Swift · TypeScript · JavaScript · Java · Ruby · PHP · Lua · Bash · C# · JSON · TOML · YAML · Markdown — 21 vendored grammars; markdown headings are real symbols"],
    ["agent-native", "an MCP server and 161 long flags behind one `--help` that is always the authority"],
  ];
  // Row height carries the LONGEST body (the language line, which wraps to three at this width),
  // not the shortest — a fixed 0.68 clipped its last line off the bottom of the card.
  let y = 3.98;
  for (const [h2, b] of props){
    card(s, MX, y, 12.09, 0.78);
    s.addText(h2, { x: MX+0.2, y: y+0.05, w: 2.9, h: 0.68, fontFace: MONO, fontSize: 13.5, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+3.2, y: y+0.05, w: 8.7, h: 0.68, fontFace: SANS, fontSize: 12, color: TEXT, valign: "middle", margin: 0 });
    y += 0.86;
  }
}

/* ── S4 · seven families ────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// every feature, one screen", CYAN);
  title(s, "Seven families of questions it answers");
  const fams = [
    ["understand cold",  "What is this repo, and what matters in it?",          "--for  --tree  --lego  --exemplar  --recall  --pack-task  --token-budget"],
    ["navigate",         "Who calls this? Safe to change or delete? Which tests?", "--callers  --callees  --uses  --impact  --path  --connect  --affected  --situ  --test-gate  --from-trace  --pattern  --safe-delete"],
    ["detail ladder",    "Show me more — but only where it pays.",              "--detail  --pack-signatures  --outline  --expand  --compress"],
    ["quality & risk",   "Where is the risk, and did I just add some?",         "--quality-panel  --quality-delta  --dmm  --readability  --ensemble  --context-ratio  --nonlocal-state  --field-affinity  --hotspots  --lint  --clones"],
    ["self-diagnosis",   "Is my setup actually working?",                       "--doctor  --skipped"],
    ["security",         "Is this agent skill file safe to install?",           "--scan-skill  --scan-skills"],
    ["knobs & modes",    "Shape, format, cache, budget.",                       "--json  --format  --mcp"],
  ];
  let y = 1.85;
  for (const [fam, q, flags] of fams){
    card(s, MX, y, 12.09, 0.66, CARD);
    s.addText(fam,   { x: MX+0.18, y: y+0.04, w: 2.35, h: 0.58, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(q,     { x: MX+2.65, y: y+0.04, w: 3.55, h: 0.58, fontFace: SANS, fontSize: 11,  italic: true, color: MUTED, valign: "middle", margin: 0 });
    s.addText(flags, { x: MX+6.3,  y: y+0.04, w: 5.65, h: 0.58, fontFace: MONO, fontSize: 9, color: CYAN, valign: "middle", margin: 0 });
    y += 0.74;
  }
  foot(s, "--help is generated from the binary's own flag table — 161 long flags; docs/COMMANDS.md carries an entry for every one of them, 94 with a recorded invocation and its output");
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
    ["Handing the area on",           "--handoff  ·  --note-add",         "the verified-vs-heuristic packet the next agent needs"],
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
  foot(s, "and --pr-context when you are reviewing someone else's diff — per-file blast radius, tests-to-run, hotspot flags");
}

/* ── S5b · what shipped since the last deck refresh ─────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// new since 2026-08-15 — each figure re-derived on the binary that ships", CYAN);
  title(s, "What the last eight days added", { size: 32 });
  const shipped = [
    ["--pattern", "search by code SHAPE, not by node kinds",
     "foo($X, ...) across 13 grammar objects / 11 languages. On this repo VERIFY($X) finds 101 hits over 625 eligible files, each with its enclosing symbol. A pattern no served grammar resolves REFUSES (exit 1) instead of reporting hits=0.", CYAN],
    ["--safe-delete", "“can I delete this?” in one call",
     "callers + transitive radius + every read/write/import site + how much of that radius a test reaches. risk= names what was FOUND — never a go/no-go verdict.", CYAN],
    ["--impact importers=", "the second, weaker reach",
     "the files that include/require a file defining SYM, with their own cap pair — NEVER summed into reaches=, because files and symbols are different units. IngestResult: reaches=0, importers=70.", CYAN],
    ["compact --for bundles", "bodies were 52.7% of every conceptual byte",
     "the subtoken+body route now ships the ranked map plus one-hop edge context, disclosed as bundle=compact bodies=0. 15-query class B: 184,857 B → 95,256 B, −48.5%, all 11 decisive markers still present. --auto-bodies is a permanent opt-out.", GREEN],
    ["corroborated callers", "shared= on --pack-task rows",
     "a neighbour reached by four of the bundle's anchors sorts above one reached by a single anchor — omitted at 1, which is what every 1-hop row satisfies anyway.", CYAN],
    ["per-rule --lint roll-up", "a capped view stops hiding whole rules",
     "on this repository 14 of the 31 rules that fired contribute ZERO shown rows — 368 findings whose only evidence is their count=. A rule no corpus language registers carries applicable=0, so its zero is inertness, not a measurement.", AMBER],
  ];
  let y = 1.72;
  for (const [flag, what, detail, c] of shipped){
    card(s, MX, y, 12.09, 0.79);
    s.addText(flag,   { x: MX+0.18, y: y+0.05, w: 2.55, h: 0.34, fontFace: MONO, fontSize: 12, bold: true, color: c, margin: 0 });
    s.addText(what,   { x: MX+0.18, y: y+0.40, w: 2.55, h: 0.34, fontFace: SANS, fontSize: 9,  italic: true, color: MUTED, margin: 0 });
    s.addText(detail, { x: MX+2.95, y: y+0.05, w: 9.0,  h: 0.69, fontFace: SANS, fontSize: 10.5, color: TEXT, valign: "middle", margin: 0 });
    y += 0.87;
  }
  card(s, MX, 6.95, 12.09, 0.0, CARD2);
  s.addText([
    { text: "And two languages: PHP and Lua, ", options: { color: TEXT, bold: true } },
    { text: "each shipped with its floor stated rather than implied — PHP's run-time dispatch ($fn(), call_user_func, __call) names its callee at run time and is a declared floor; a Lua corpus reports no inheritance edges, because metatable inheritance has no syntax to read.", options: { color: MUTED } },
  ], { x: MX, y: 6.92, w: 12.09, h: 0.5, fontFace: SANS, fontSize: 10, margin: 0 });
}

/* ── S6 · head-to-head, round 4 ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// one harness, one machine, one day — N = 60 paired, zero exclusions", AMBER);
  title(s, "Head-to-head: every competitor, one table");
  s.addChart("bar", [{
    name: "strict file@10",
    labels: ["ripwire --for", "codebase-memory-mcp 0.9.0", "repowise 0.37.0", "graphify 0.9.34",
             "aider repo-map 0.86.2", "codeseek 0.1.31 (idents)", "aider (no-persona control)", "codeseek (raw fallback)"],
    values: [58.3, 40.0, 33.3, 31.7, 20.0, 15.0, 10.0, 0.0],
  }], {
    x: MX, y: 1.72, w: 7.5, h: 4.55, barDir: "bar",
    chartColors: [CYAN, "3A4353", "3A4353", "3A4353", "3A4353", "3A4353", "3A4353", "3A4353"],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: '0.0"%"', dataLabelColor: TEXT, dataLabelFontSize: 10.5, dataLabelFontFace: SANS,
    catAxisLabelColor: TEXT, catAxisLabelFontSize: 10, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 9, valAxisMaxVal: 70, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 40,
  });
  card(s, 8.4, 1.72, 4.2, 1.55);
  stat(s, "1.46×", "the margin over the best competitor — 58.3% against 40.0% strict file@10", 8.5, 1.85, 4.0, CYAN, { bsize: 40, bh: 0.8, lsize: 10.5 });
  card(s, 8.4, 3.4, 4.2, 1.62);
  s.addText([
    { text: "And the index it was measured with\n", options: { color: TEXT, bold: true, fontSize: 12 } },
    { text: "ripwire 0.31 s · codebase-memory-mcp 1.24 s · codeseek 3.37 s · graphify 7.82 s · repowise 34.0 s, whose worst single index was ", options: { color: MUTED, fontSize: 10.5 } },
    { text: "352 s", options: { color: AMBER, bold: true, fontSize: 10.5 } },
    { text: ". Cold, nothing to an answer: 0.213 s.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.55, y: 3.52, w: 3.9, h: 1.44, fontFace: SANS, valign: "top", margin: 0 });
  card(s, 8.4, 5.15, 4.2, 1.55);
  s.addText([
    { text: "What re-running cost us, published: ", options: { color: TEXT, bold: true, fontSize: 10.5 } },
    { text: "aider moved 18.3% → 20.0% on its own tie-break nondeterminism, and we printed the higher number. Paired, ripwire loses 2 instances to codebase-memory-mcp, 2 to repowise, and 1 each to graphify, aider and the aider control.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.55, y: 5.27, w: 3.9, h: 1.38, fontFace: SANS, valign: "top", margin: 0 });
  foot(s, "bench/headtohead/r4-2026-08-06/ — harness, per-instance JSONL and recipe committed · replaces the two non-comparable tables r1 and r2 needed");
}

/* ── S6b · the oracle round ─────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// scored against a third-party oracle, never against each other", AMBER);
  title(s, "Graded by a compiler: zero silent misses");
  card(s, MX, 1.72, 6.05, 2.45);
  s.addText("Both tools were scored against a scip-clang compiler-grade index of this repository — 68 answers, 34 blind-authored queries × --uses and --callers.",
    { x: MX+0.22, y: 1.85, w: 5.6, h: 0.72, fontFace: SANS, fontSize: 12, color: MUTED, margin: 0 });
  stat(s, "0", "true silent misses — pre-fix and post-fix alike. Every imperfect answer either carried a discriminating self-flag (amb=, defs>1, external=\"1\") or was an oracle-scope artifact where ripwire was right and the compiler could not see the file.",
    MX+0.22, 2.55, 5.6, GREEN, { bsize: 54, bh: 0.85, lsize: 10.5 });

  card(s, 7.0, 1.72, 5.6, 2.45, CARD2);
  s.addText("What a compiler-grade index costs", { x: 7.2, y: 1.85, w: 5.2, h: 0.32, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
  const cost = [
    ["warm query", "49.8 ms", "3,760 ms", "~70×"],
    ["cold start",  "208 ms",  "8.7 s",    "~40×"],
    ["index build", "none",    "~8 min",   "—"],
    ["errors",      "0 / 101", "7 / 61",   "—"],
  ];
  let cy = 2.19;
  s.addText([{ text: "ripwire", options: { color: CYAN, bold: true } }, { text: "        Serena 1.6.2.dev0 (clangd 19.1.2)", options: { color: MUTED } }],
    { x: 8.5, y: cy, w: 3.95, h: 0.28, fontFace: SANS, fontSize: 10, margin: 0 });
  cy = 2.5;
  for (const [k, a, b, mult] of cost){
    s.addText(k,    { x: 7.2,  y: cy, w: 1.3,  h: 0.32, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    s.addText(a,    { x: 8.5,  y: cy, w: 1.15, h: 0.32, fontFace: MONO, fontSize: 11.5, bold: true, color: CYAN, valign: "middle", margin: 0 });
    s.addText(b,    { x: 9.75, y: cy, w: 1.35, h: 0.32, fontFace: MONO, fontSize: 11.5, color: TEXT, valign: "middle", margin: 0 });
    s.addText(mult, { x: 11.2, y: cy, w: 1.1,  h: 0.32, fontFace: MONO, fontSize: 11.5, color: AMBER, valign: "middle", margin: 0 });
    cy += 0.38;
  }

  card(s, MX, 4.32, 12.0, 1.35);
  s.addText([
    { text: "Read honestly in both directions. ", options: { color: TEXT, bold: true } },
    { text: "The LSP is more precise — site-level 0.929/0.941 against ripwire's 0.914/0.941 after the fix round, a gap of roughly 1.5 points with recall now equal. ripwire also pays ~7× the bytes per call, because its output carries self-describing legends. What it cannot do is answer a macro query at all — clangd's documentSymbol has no macro entries, which is 3 of its 7 errors — or start in less than eight minutes.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 4.44, w: 11.55, h: 1.15, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });

  card(s, MX, 5.78, 12.0, 1.05, CARD2);
  s.addText([
    { text: "The number that moved the wrong way, published with the rest: ", options: { color: AMBER, bold: true } },
    { text: "over-hedging rose 18.6% → 22.6% across the fix round. Closing loss buckets added self-flags faster than it removed imperfect answers. That direction is deliberate — calibrated to warn too often rather than too rarely — but it is a cost, and it is on the slide.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.89, w: 11.55, h: 0.88, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "bench/headtohead/r9-2026-08-09/RESULTS.md — C++ only, 34 scorable queries, one corpus (this repository)");
}

/* ── S6d · r10, the graph-database context server ───────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// 48 paired questions, zero exclusions, both arms exit 0 on all 48", AMBER);
  title(s, "Against a graph-database context server: 27–7–14", { size: 32 });

  // This slide's table stops at TW so it never runs underneath the cards on its right.
  const TW = 7.85;
  const nrow = (ry, h, cols, fill) => { row(s, ry, h, cols, { w: TW, fill }); };
  const CW = [2.45, 0.45, 0.85, 0.9, 0.55, 1.45];
  const splits = [
    ["symbol lookup",         12, 6, 2, 4, "1.35×", AMBER],
    ["conceptual search",     15, 8, 1, 6, "1.23×", AMBER],
    ["callers / blast radius",12, 7, 2, 3, "0.39×", GREEN],
    ["task orientation",       9, 6, 2, 1, "0.06×", GREEN],
  ];
  nrow(1.66, 0.34, [
    { t: "class",      w: CW[0], color: MUTED, size: 9.5, bold: true },
    { t: "n",          w: CW[1], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "ripwire",    w: CW[2], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "GitNexus",   w: CW[3], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "tie",        w: CW[4], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "bytes ÷ it", w: CW[5], color: MUTED, size: 9.5, bold: true, align: "right" },
  ], BG);
  let y = 2.04;
  for (const [name, n, w, l, tie, ratio, rc] of splits){
    nrow(y, 0.42, [
      { t: name,        w: CW[0], color: TEXT,  size: 10.5 },
      { t: String(n),   w: CW[1], color: MUTED, size: 10.5, mono: true, align: "right" },
      { t: String(w),   w: CW[2], color: CYAN,  size: 11, mono: true, bold: true, align: "right" },
      { t: String(l),   w: CW[3], color: TEXT,  size: 11, mono: true, align: "right" },
      { t: String(tie), w: CW[4], color: MUTED, size: 11, mono: true, align: "right" },
      { t: ratio,       w: CW[5], color: rc,    size: 11, mono: true, bold: true, align: "right" },
    ]);
    y += 0.47;
  }
  nrow(y, 0.44, [
    { t: "all 48",  w: CW[0], color: TEXT,  size: 11, bold: true },
    { t: "48",      w: CW[1], color: MUTED, size: 11, mono: true, align: "right" },
    { t: "27",      w: CW[2], color: CYAN,  size: 12.5, mono: true, bold: true, align: "right" },
    { t: "7",       w: CW[3], color: TEXT,  size: 12.5, mono: true, bold: true, align: "right" },
    { t: "14",      w: CW[4], color: MUTED, size: 12.5, mono: true, align: "right" },
    { t: "0.159×",  w: CW[5], color: GREEN, size: 12.5, mono: true, bold: true, align: "right" },
  ], CARD2);

  card(s, 8.65, 1.66, 3.96, 1.72);
  s.addText("The cost of the whole sweep", { x: 8.85, y: 1.76, w: 3.6, h: 0.3, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "309,348 B", options: { color: CYAN, bold: true, fontSize: 13 } },
    { text: " against ", options: { color: MUTED, fontSize: 11 } },
    { text: "1,945,231 B", options: { color: TEXT, fontSize: 11 } },
    { text: ". Warm median 197 ms against 1,082 ms. Index 0.25–0.45 s / 6.6–16.5 MB against 23–52 s / 391–623 MB — written into the repository, not $TMPDIR.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.85, y: 2.10, w: 3.6, h: 1.2, fontFace: SANS, valign: "top", margin: 0 });

  card(s, 8.65, 3.48, 3.96, 0.88, CARD2);
  s.addText([
    { text: "What it does better: ", options: { color: AMBER, bold: true } },
    { text: "compact one-hop context at 0.7–1.0 KB, a depth-LABELLED blast radius, per-stage timing on every query, and two-command onboarding into eight agents.", options: { color: MUTED } },
  ], { x: 8.85, y: 3.56, w: 3.6, h: 0.72, fontFace: SANS, fontSize: 9.5, valign: "middle", margin: 0 });

  card(s, 8.65, 4.4, 3.96, 2.3, CARD2);
  s.addText("Failure modes, both directions", { x: 8.85, y: 4.52, w: 3.6, h: 0.3, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, margin: 0 });
  const fails = [
    ["needed a 2nd call", "0", "8/48"],
    ["empty radius, real callers", "0", "1"],
    ["malformed through a pipe", "0", "7/48"],
  ];
  let fy = 4.88;
  for (const [k, a, b] of fails){
    s.addText(k, { x: 8.85, y: fy, w: 2.2, h: 0.5, fontFace: SANS, fontSize: 9.5, color: MUTED, valign: "middle", margin: 0 });
    s.addText(a, { x: 11.1, y: fy, w: 0.45, h: 0.5, fontFace: MONO, fontSize: 11, bold: true, color: CYAN, valign: "middle", align: "right", margin: 0 });
    s.addText(b, { x: 11.62, y: fy, w: 0.8, h: 0.5, fontFace: MONO, fontSize: 11, color: TEXT, valign: "middle", align: "right", margin: 0 });
    fy += 0.5;
  }
  s.addText("The published numbers use the file-redirected form — the configuration favourable to it.",
    { x: 8.85, y: 6.32, w: 3.6, h: 0.32, fontFace: SANS, fontSize: 8.5, italic: true, color: MUTED, margin: 0 });

  card(s, MX, 4.4, 7.85, 2.3);
  s.addText([
    { text: "Its seven wins are named one by one, and its first-pass numbers do not exist. ", options: { color: AMBER, bold: true } },
    { text: "Four are cost losses on an answer ripwire gets right — a by-name lookup it serves in ~1 KB where ripwire spends 3× to also hand back the body. Three are ranking misses on webpack, and two of those share one unfixed mechanism: a symbol whose NAME matches the query beats the implementation that carries it in its body. Under the improve-first rule the round's FIRST pass was never published — its product was a loss list, and what is on this slide is the state after that list was worked. One of those fixes met its pre-registered band and was reverted anyway for failing a separate standing requirement; ", options: { color: MUTED } },
    { text: "the loss it would have fixed is still counted against us above.", options: { color: TEXT, bold: true } },
  ], { x: MX+0.22, y: 4.52, w: 7.4, h: 2.06, fontFace: SANS, fontSize: 10.5, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md §2 — GitNexus 1.6.9 (npm latest at 2026-08-22) vs ripwire at 7eb638e; django, webpack and this repository, all tree-hash verified clean · ratios are on class TOTALS, the medians form is printed there too because the two disagree");
}

/* ── S6c · the rounds ledger ────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the rule: numbers are held back until the loss list is worked", AMBER);
  title(s, "Every head-to-head round, and the ones that went against us", { size: 32 });
  const rounds = [
    ["r1", "2026-07-13/14", "Aider repo-map · codebase-memory-mcp · graphify", "superseded by r4", MUTED],
    ["r2", "2026-08-03",    "repowise · codeseek",                             "superseded by r4", MUTED],
    ["r3", "2026-08-03",    "headroom — a compression layer, so a different instrument", "passed code through byte-identical", TEXT],
    ["r4", "2026-08-06/08", "all five competitors, one harness, one day",       "the table on the previous slide", CYAN],
    ["r6", "2026-08-04/05", "agent-in-the-loop: the Codex CLI pilot",           "localization parity; +80% tokens, classified", TEXT],
    ["r7", "2026-08-08",    "CodeGraph, loss-first — we looked for our losses", "fix REJECTED by its own preregistered band", RED],
    ["r8", "2026-08-08",    "aider again, at equal token budget",               "loss questions traced to one root cause", TEXT],
    ["r9", "2026-08-09",    "Serena / scip-clang oracle",                       "0 silent misses; the fix list it produced", CYAN],
    ["r10","2026-08-22",    "GitNexus 1.6.9 — a graph-database context server", "27-7-14 — its own slide, two back", CYAN],
  ];
  let y = 1.68;
  for (const [r, when, what, outcome, c] of rounds){
    row(s, y, 0.5, [
      { t: r,       w: 0.5,  mono: true, bold: true, color: c, size: 12.5 },
      { t: when,    w: 1.35, mono: true, color: MUTED, size: 10.5 },
      { t: what,    w: 5.3,  color: TEXT, size: 11.5 },
      { t: outcome, w: 4.3,  color: c === MUTED ? MUTED : c, size: 11, italic: c === MUTED },
    ]);
    y += 0.49;
  }
  card(s, MX, 6.32, 12.09, 0.62, CARD2);
  s.addText([
    { text: "r7 in full, because it is the point: ", options: { color: AMBER, bold: true } },
    { text: "the fix was built, gated green, measured — predicted 12/22 against a pre-registered band of 10–14, measured 5/22 — and reverted rather than tuned. Published as a negative in docs/EVALS.md §7.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.41, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "bench/headtohead/ (r1–r4, r9) · bench/r7/ · bench/r8/ — harnesses committed even for rounds that rejected their own fix · r5 left no head-to-head record in this tree, so it is not listed · r10's method and pins are published in docs/EVALS.md §2, its pre-fix numbers nowhere");
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

/* ── S7b · speed, on numbers you can reproduce ──────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// compiled, not interpreted — and measured on public corpora", CYAN);
  title(s, "Fast enough to call on reflex");
  const cols = [
    ["0.213 s", "cold — nothing to an answer: parse, rank, reply, no cache (r4)", CYAN],
    ["0.108 s", "warm query, median — against aider's 2.920 s (r4)", CYAN],
    ["0.31 s",  "index build — against repowise's 34.0 s, worst case 352 s (r4)", GREEN],
    ["49.8 ms", "warm query on this repo — against a clangd LSP's 3,760 ms (r9)", GREEN],
  ];
  let sx = MX;
  for (const [n, l, c] of cols){
    card(s, sx, 1.9, 2.93, 1.68);
    stat(s, n, l, sx+0.08, 2.06, 2.77, c, { bsize: 30, bh: 0.62, lsize: 10 });
    sx += 3.05;
  }
  card(s, MX, 3.78, 5.95, 2.42);
  s.addText("Where the second goes", { x: MX+0.22, y: 3.92, w: 5.5, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "Cold profiles are tree-sitter parse plus tag-query capture — not graph math. Resolve and PageRank together are a small fraction of the run, and the ranking was never the bottleneck.\n\n", options: { color: MUTED } },
    { text: "Which is why the wins came from removing work, not micro-optimising it: demand-driven side captures, five whole-AST passes fused into one pre-order walk, a calibrated per-worker parse reserve.", options: { color: MUTED } },
  ], { x: MX+0.22, y: 4.3, w: 5.5, h: 1.8, fontFace: SANS, fontSize: 11.5, margin: 0 });

  card(s, 6.75, 3.78, 5.85, 2.42);
  s.addText("Two opt-in faster builds", { x: 6.97, y: 3.92, w: 5.4, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "LTO is on by default. PGO is a script away and buys 14–25% cold.\n\n", options: { color: MUTED } },
    { text: "Both are opt-in performance, not opt-in correctness: ", options: { color: MUTED } },
    { text: "the output stays byte-identical across build flavours", options: { color: CYAN, bold: true } },
    { text: " — the determinism gate runs on both, and CI builds a plain flavour too, because NDEBUG once compiled a whole class of degrade-path checks out of existence.", options: { color: MUTED } },
  ], { x: 6.97, y: 4.3, w: 5.4, h: 1.8, fontFace: SANS, fontSize: 11.5, margin: 0 });
  foot(s, "every card above comes from a committed harness — bench/headtohead/r4-2026-08-06/ and r9-2026-08-09/ — not from a private corpus");
}

/* ── S7b2 · the pre-release sprint, labelled historical ─────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// how it got there — the pre-release performance sprint", MUTED);
  title(s, "Work removed before work optimized");
  const wins = [
    ["file ingest",    "FILE* whole-file reads; CSV counting became a byte scan — iostream out of the hot path"],
    ["capture gating", "value-use capture runs only for the verbs that actually need it, not on every run"],
    ["AST pass fusion","five whole-AST side-capture passes share ONE pre-order walk instead of five"],
    ["parallel parse", "query compile overlaps parse scheduling; files schedule by size — ids stay deterministic"],
    ["radix + S+tree", "numeric keys for edges and scores; a bounded-scratch hot map whose fixed cap reports its own overflow"],
    ["no std::map",    "unordered_dense, reserve() before ingest — no std::unordered_map on any hot path"],
  ];
  const cw = 3.95, ch = 1.4; let i = 0;
  for (const [h2, b] of wins){
    const x = MX + (i % 3) * (cw + 0.12), y = 1.9 + Math.floor(i / 3) * (ch + 0.16);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.18, y: y+0.12, w: cw-0.36, h: 0.34, fontFace: MONO, fontSize: 12.5, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.18, y: y+0.48, w: cw-0.36, h: 0.95, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "top", margin: 0 });
    i++;
  }
  card(s, MX, 4.92, 12.09, 1.68, CARD2);
  s.addText([
    { text: "Why this slide carries no numbers. ", options: { color: AMBER, bold: true } },
    { text: "The sprint's own headline pair was measured in June 2026 on a large private C++ corpus that is not publicly reproducible, and the deck does not quote figures a reader cannot re-derive — the previous slide's numbers all come from committed harnesses. What survives the omission is the ", options: { color: MUTED } },
    { text: "shape", options: { color: TEXT, bold: true, italic: true } },
    { text: ": the graph math was never the bottleneck, and every win came from doing less work rather than doing the same work faster. Same map contract throughout — byte-identical output before and after each of these changes.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.04, w: 11.6, h: 1.46, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "the mechanisms are in bench/PROFILE.md and the commit history; the private-corpus figures they produced are deliberately not quoted");
}

/* ── S7c · the ten moments ──────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// re-measured on this repository, 2026-08-08 — run any row yourself", CYAN);
  title(s, "Ten everyday moments, and what each one costs", { size: 32 });
  const moments = [
    ["Orient me in this repo",                 "ripwire .",                    "~5.6K",   "~20K–25K",    "3.6×–4.5×"],
    ["Where is X handled?",                    "--for=\"…\"",                  "~1.9K",   "~4.9K–20K",   "2.6×–10.7×"],
    ["What do I already know?",                "--recall=\"…\"",               "~15K",    "~445K",       "29.2×"],
    ["Set me up for this task",                "--pack-task=\"…\"",            "~2.1K",   "~16K–80K",    "7.7×–37.7×"],
    ["Show me this one function",              "--expand=SYM --top-k=0",       "~260–16.5K", "~43K–174K", "2.6×–670×"],
    ["Who calls this function?",               "--callers=SYM",                "~580",    "~40K–52K",    "69.2×–89.1×"],
    ["Is it safe to change this?",             "--impact=SYM + --uses=SYM",    "~1.3K",   "~18K",        "14.4×"],
    ["I have a stack trace",                   "--from-trace=FILE",            "~1.4K",   "~124K–298K",  "86.9×–208.6×"],
    ["I changed these files — tests? radius?", "--situ",                       "~410",    "~3K–132K",    "7.3×–324.2×"],
    ["Review this PR/diff",                    "--pr-context=REF",             "~1.9K",   "~4.8K–51K",   "2.6×–27.5×"],
  ];
  row(s, 1.66, 0.34, [
    { t: "Ask it",       w: 3.25, color: MUTED, size: 10, bold: true },
    { t: "Command",      w: 2.45, color: MUTED, size: 10, bold: true, mono: true },
    { t: "ripwire",      w: 1.45, color: MUTED, size: 10, bold: true, align: "right" },
    { t: "naive read",   w: 1.8,  color: MUTED, size: 10, bold: true, align: "right" },
    { t: "savings",      w: 2.3,  color: MUTED, size: 10, bold: true, align: "right" },
  ], { fill: BG });
  let y = 2.04;
  for (const [ask, cmd, rw, naive, save] of moments){
    row(s, y, 0.42, [
      { t: ask,   w: 3.25, color: TEXT,  size: 10.5 },
      { t: cmd,   w: 2.45, color: CYAN,  size: 9.5, mono: true },
      { t: rw,    w: 1.45, color: CYAN,  size: 10.5, mono: true, bold: true, align: "right" },
      { t: naive, w: 1.8,  color: MUTED, size: 10.5, mono: true, align: "right" },
      { t: save,  w: 2.3,  color: GREEN, size: 10.5, mono: true, bold: true, align: "right" },
    ]);
    y += 0.47;
  }
  s.addText([
    { text: "Figures are ~tokens (≈ bytes/4). Every row is scored same-correct-answer-or-it-doesn't-count — both sides were checked, not assumed — and every ratio is a ", options: { color: MUTED } },
    { text: "range", options: { color: TEXT, bold: true } },
    { text: ": the cheap end and the honest end of what an agent would actually read, never the single most flattering number.", options: { color: MUTED } },
  ], { x: MX, y: 6.78, w: 12.09, h: 0.5, fontFace: SANS, fontSize: 10, margin: 0 });
}

/* ── S8 · token economy ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the cost lever", CYAN);
  title(s, "Smaller answers that are also better answers");
  card(s, MX, 1.95, 5.9, 2.5);
  stat(s, "81.4%", "fewer element bytes at top-50 — the --pack-signatures ladder,\nroot-neutralised, re-derived on this repo every run", MX+0.2, 2.25, 5.5, CYAN, { bsize: 52, lsize: 12 });
  card(s, MX, 4.65, 5.9, 1.9);
  s.addText("This figure survived its own audit: three corrections deep, re-derived root-neutrally after the original was shown to depend on how the corpus path was spelled — three spellings of one root read 18.6 points apart before that subtraction. top-50 is the quotable number because the payload is top-50 whatever --top-k says.",
    { x: MX+0.25, y: 4.85, w: 5.4, h: 1.55, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  card(s, 7.25, 1.95, 5.35, 2.5);
  s.addText("Ask for a symbol by NAME and the router uses the name-exact ranker:", { x: 7.5, y: 2.15, w: 4.9, h: 0.6, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "MRR  0.797 → 0.990\n", options: { color: GREEN, bold: true } },
    { text: "recall@1  70.0% → 98.0%\n", options: { color: GREEN, bold: true } },
    { text: "name-shaped queries on src/, held-out labels, re-derived 2026-08-08", options: { color: MUTED } },
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
  card(s, 8.5, 5.25, 4.1, 1.45);
  s.addText([
    { text: "The map grades itself before it answers. ", options: { color: TEXT, bold: true } },
    { text: "This repository's own src/: files=116 symbols=4204 edges=11727 ambiguous=5469 unresolved=1295.", options: { color: MUTED, fontFace: MONO } },
  ], { x: 8.68, y: 5.36, w: 3.8, h: 1.24, fontFace: SANS, fontSize: 10, margin: 0 });
  foot(s, "docs/EVALS.md §8 lists the numbers this project refuses to publish, each with its reason");
}

/* ── S9b · how complete is the graph ────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the honesty marks stop being a promise and become a measurement", AMBER);
  title(s, "Four levers accepted, one rejected on purpose");
  const levers = [
    ["macro edges",       "kParserVer 48", "function-like #define invocations land role=\"macro\" edges on disclosed-degraded symbols", GREEN],
    ["fn-pointer bindings","kParserVer 49", "calls through unambiguous local function-pointer bindings now resolve", GREEN],
    ["using-declarations","kParserVer 51", "re-exports emit role=\"import\" references — r9 loss bucket 1", GREEN],
    ["shadow suppression","kParserVer 52", "a local variable shadowing a function name stops stealing its use-sites — r9 loss bucket 2", GREEN],
    ["RTA-lite",          "reverted",      "instantiation-filtered CHA cone: refuted TWICE — the instantiated set crossed namespaces, and narrowed calls LOST their amb= mark", RED],
  ];
  let y = 1.8;
  for (const [n, ver, what, c] of levers){
    row(s, y, 0.66, [
      { t: n,    w: 2.15, color: c, bold: true, size: 12 },
      { t: ver,  w: 1.45, color: MUTED, size: 10.5, mono: true },
      { t: what, w: 8.0,  color: c === RED ? TEXT : MUTED, size: 11 },
    ], { fill: c === RED ? CARD2 : CARD });
    y += 0.74;
  }
  card(s, MX, 5.55, 5.95, 1.15);
  s.addText([
    { text: "The two r9 levers, against the compiler oracle: ", options: { color: TEXT, bold: true } },
    { text: "site precision 0.9046 → 0.9136, recall 0.9285 → 0.9412.", options: { color: GREEN, bold: true } },
  ], { x: MX+0.22, y: 5.68, w: 5.5, h: 0.92, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  card(s, 6.75, 5.55, 5.85, 1.15, CARD2);
  s.addText([
    { text: "The fn-pointer lever raised unresolved= by 1,039. Disclosure, not regression: ", options: { color: AMBER, bold: true } },
    { text: "call sites the resolver now RECOGNIZES but refuses to resolve are counted instead of silently ignored.", options: { color: MUTED } },
  ], { x: 6.97, y: 5.68, w: 5.4, h: 0.92, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "bench/resolverround/RESULTS.md — per-lever attribution; RTA-lite's rejection is written up in docs/EVALS.md §7");
}

/* ── S10 · proven, not promised ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// how it stays true", AMBER);
  title(s, "Proven, not promised");
  const cards = [
    ["451 gate scripts", "the suite runs on every push — plus determinism, cache-transparency and golden contracts; the gate count itself is gated against the runner's own loop"],
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

/* ── S10b · why the claims are worth anything ───────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the reason to believe any number on this deck", AMBER);
  title(s, "Claims you can trust, because we publish what failed", { size: 32 });

  card(s, MX, 1.72, 3.86, 1.72);
  stat(s, "451", "gate scripts named by test/regression.sh — and the COUNT itself is gated against the runner's own loop, so it cannot go stale quietly",
    MX+0.15, 1.86, 3.56, CYAN, { bsize: 42, bh: 0.66, lsize: 9.5 });
  card(s, 4.68, 1.72, 3.86, 1.72, CARD2);
  stat(s, "8", "registered NEGATIVES — changes built, gated green, measured against a band written before the code, and reverted rather than tuned",
    4.83, 1.86, 3.56, RED, { bsize: 42, bh: 0.66, lsize: 9.5 });
  card(s, 8.76, 1.72, 3.86, 1.72);
  stat(s, "0", "numbers on this deck without a committed instrument behind them — §8 lists the ones this project refuses to publish at all",
    8.91, 1.86, 3.56, GREEN, { bsize: 42, bh: 0.66, lsize: 9.5 });

  const arms = [
    ["the fresh-clone arm", "our own battery only ever ran inside a configured, long-lived worktree — one value of every AMBIENT input. It clones HEAD into a genuinely unconfigured checkout and re-runs the gates whose past failures were exactly that: a developer's git config, a fixture's inherited branch name, the checkout's own path length.", CYAN],
    ["the merge-conservation gate", "consistency is not conservation. A conflict resolution can drop a gate from the runner's loop while regenerating the pinned count from that SAME damaged list — both sides then agree at a wrong number. On a merge, the loop must equal the UNION of both parents', minus explicit tombstones.", AMBER],
    ["the eight, by name", "r7's prose-strip fix (predicted 12/22, band 10–14, measured 5/22) · RTA-lite, refuted twice · file-level evidence pooling, +0.00pp held-out · un-guarded query stemming · its IDF-guarded retry, VOIDED by its own verifier · query-term density weighting, both displacement guards tripped · --anchor and --cochange-boost, no confirmed lift · a name-coverage floor that MET its pre-registered band and was reverted anyway for a standing requirement.", RED],
  ];
  let y = 3.62;
  for (const [h2, b, c] of arms){
    card(s, MX, y, 12.09, 1.06);
    s.addText(h2, { x: MX+0.2, y: y+0.06, w: 3.0, h: 0.94, fontFace: MONO, fontSize: 12, bold: true, color: c, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+3.4, y: y+0.06, w: 8.5, h: 0.94, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "middle", margin: 0 });
    y += 1.14;
  }
  s.addText("A gate that cannot go red is a gate that proves nothing — which is why every arm on this deck ships with the mutation that makes it fail.",
    { x: MX, y: 7.0, w: 12.0, h: 0.4, fontFace: SANS, fontSize: 12.5, italic: true, color: AMBER, margin: 0 });
}

/* ── S11 · where it loses ───────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// own the losses — they are in the README too", AMBER);
  title(s, "Where it loses, published with the wins");
  const rows = [
    ["The public C++ number is lower than the private one it replaced",
     "SFML: strict file@10 28.7%, any@10 41.7%, first-hit MRR 0.21. Until 2026-08-07 this bullet compared against a ~89% any@10 private corpus that is no longer reproducible. That comparison is retired; the public number is the baseline going forward."],
    ["--grep costs more than it saves",
     "+19.7% tokens / −11.2% — published next to the flag it indicts, and carrying the same private-corpus caveat as every figure in that source"],
    ["PageRank is the wrong co-change ranker",
     "3.8% recall@5 against 40.3% for plain lexical, and fusing the two made it worse — relatedness is lexical, importance is structural"],
    ["Strict multi-file localization stays hard",
     "single-file gold 73.4% vs multi-file 18.2% (held-out); the same cliff on every corpus — open headroom, said plainly"],
  ];
  let y = 1.86;
  for (const [h2, b] of rows){
    card(s, MX, y, 12.09, 1.1);
    s.addText(h2, { x: MX+0.22, y: y+0.06, w: 4.55, h: 0.98, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+4.95, y: y+0.06, w: 6.9, h: 0.98, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    y += 1.2;
  }
  s.addText("A tool that publishes its counterexamples is a tool whose wins you can believe.",
    { x: MX, y: 6.72, w: 12.0, h: 0.4, fontFace: SANS, fontSize: 14, italic: true, color: AMBER, margin: 0 });
}

/* ── S11b · the quality panel ───────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the single command for \"is this code actually rotten?\"", CYAN);
  title(s, "Six families of evidence, counted — never blended", { size: 32 });
  const fams = [
    ["structural",  "shape: complexity, size, nesting, params, readability rank", "--metrics"],
    ["lexical",     "identifier text: the naming rules", "--lint  --naming-consistency"],
    ["confusion",   "syntax: the atoms-of-confusion rules", "--lint"],
    ["historical",  "git change frequency, measured PER FILE", "--hotspots"],
    ["colocation",  "how much you must READ outside this file", "--context-ratio"],
    ["state",       "this function's OWN BODY touching non-local mutable state", "--nonlocal-state"],
  ];
  let y = 1.8;
  for (const [n, what, flag] of fams){
    row(s, y, 0.6, [
      { t: n,    w: 1.75, color: CYAN, bold: true, mono: true, size: 12 },
      { t: what, w: 6.4,  color: TEXT, size: 11.5 },
      { t: flag, w: 3.5,  color: MUTED, size: 10.5, mono: true },
    ]);
    y += 0.68;
  }
  card(s, MX, 5.9, 5.95, 0.85, CARD2);
  s.addText([
    { text: "Ranked by the COUNT of distinct families that fire", options: { color: TEXT, bold: true } },
    { text: " — never a weighted composite, because a composite lets one loud family impersonate six.", options: { color: MUTED } },
  ], { x: MX+0.22, y: 6.0, w: 5.5, h: 0.65, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  card(s, 6.75, 5.9, 5.85, 0.85);
  s.addText([
    { text: "4 of 6", options: { color: AMBER, bold: true, fontSize: 16 } },
    { text: "  is what the strict preset counts — the verb says so itself, families=\"6\" enabled_n=\"4\". Two families did not clear the stability ladder.", options: { color: MUTED, fontSize: 11 } },
  ], { x: 6.97, y: 6.0, w: 5.4, h: 0.65, fontFace: SANS, valign: "middle", margin: 0 });
  foot(s, "--quality-panel[=strict|default|lenient] — and --quality-delta for the narrower question: what did MY change make worse?");
}

/* ── S11c · what the panel had to pass ──────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// a new lens does not ship because it sounds plausible", AMBER);
  title(s, "The calibration that disqualified a family", { size: 32 });
  card(s, MX, 1.8, 3.86, 2.15);
  stat(s, "+0.168", "the LARGEST cross-family correlation in the whole 6×6 matrix — widening the panel from four families to six did not raise it",
    MX+0.15, 1.98, 3.56, GREEN, { bsize: 40, bh: 0.72, lsize: 10.5 });
  card(s, 4.68, 1.8, 3.86, 2.15);
  stat(s, "27,889", "eligible functions, five independent trees — two reported separately and never pooled, because one of them is this repository",
    4.83, 1.98, 3.56, CYAN, { bsize: 40, bh: 0.72, lsize: 10.5 });
  card(s, 8.76, 1.8, 3.86, 2.15, CARD2);
  stat(s, "4 of 6", "families the strict preset actually counts — TWO were measured and held back from gating",
    8.91, 1.98, 3.56, AMBER, { bsize: 40, bh: 0.72, lsize: 10.5 });

  card(s, MX, 4.15, 12.0, 1.35);
  s.addText([
    { text: "The uncomfortable result, kept. ", options: { color: AMBER, bold: true } },
    { text: "The stability pass ran each family across a ladder of commits to ask whether it is steady enough to gate on. ", options: { color: MUTED } },
    { text: "colocation came out worse than historical on one ladder", options: { color: TEXT, bold: true } },
    { text: ", so neither gates: strict counts four of the six — a lens its own author wanted, measured, and demoted. The ladder was run precisely because that answer was possible; assuming it would pass is how a plausible axis becomes a permanent one.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 4.28, w: 11.55, h: 1.15, fontFace: SANS, fontSize: 12, valign: "middle", margin: 0 });

  card(s, MX, 5.68, 12.0, 1.02, CARD2);
  s.addText([
    { text: "--field-affinity was NOT made a family either", options: { color: TEXT, bold: true } },
    { text: " — an exclusion by unit, not a failed measurement: it ranks struct FIELDS by co-access against declared layout, and the panel's unit is a function. Stated in the calibration rather than left for someone to notice.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.79, w: 11.55, h: 0.84, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md §9.9 — same harness and criteria as the original four families, run BEFORE the two new ones shipped enabled");
}

/* ── S12 · agent wiring ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// built for the agent's seat", CYAN);
  title(s, "One command wires it into your agent", { size: 32 });
  chip(s, "$ ripwire wrap claude", MX, 1.95, 4.35, GREEN, { size: 14, h: 0.55 });
  s.addText("claude · cursor · codex · windsurf · gemini · aider — or --all to detect every one you have installed",
    { x: 5.2, y: 1.95, w: 7.4, h: 0.55, fontFace: SANS, fontSize: 12, color: MUTED, valign: "middle", margin: 0 });
  const cards = [
    ["30 MCP verbs", "15 read verbs mirroring the CLI, 12 flagship reflexes (impact, uses, edit_check, from_trace, connect …), 3 span-addressed edit verbs with a safety contract"],
    ["lazy-body handles", "read verbs return signatures and a stable handle; the agent fetches a body only when it decides it needs one — names by default, bytes on request"],
    ["18 agent skills", "moment-matched workflows (orient, navigate, change-check, quality-bar …) — wrap prints the recipe, skills/install.sh installs them"],
    ["11 orchestrator loops", "copy-paste prompts in prompts/: run the same audit, eval and head-to-head machinery that built this tool, on your own repository"],
  ];
  const cw = 5.95, ch = 1.62; let i = 0;
  for (const [h2, b] of cards){
    const x = MX + (i % 2) * (cw + 0.19), y = 2.78 + Math.floor(i / 2) * (ch + 0.18);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.2, y: y+0.12, w: cw-0.4, h: 0.4, fontFace: MONO, fontSize: 14, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.2, y: y+0.55, w: cw-0.4, h: 1.1, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
    i++;
  }
  card(s, MX, 6.30, 12.09, 0.62, CARD2);
  s.addText([
    { text: "wrap does not just print JSON: ", options: { color: TEXT, bold: true } },
    { text: "it probes what that agent already has, emits the config in that agent's own shape, and includes a use-when blurb so the agent knows which verb fires at which moment — not just that a server exists.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.39, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");
}

/* ── S12b · the research inside ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// standing on giants", AMBER);
  title(s, "The research inside — classic and current");
  s.addText([
    { text: "34 repositories + 54 papers folded", options: { color: TEXT, bold: true } },
    { text: "  ·  and a labelled survey of 221 tools that contributed nothing, which says so — every row with the lesson taken and where it lives: docs/LINEAGE.md", options: { color: MUTED } },
  ], { x: MX, y: 1.58, w: 12.0, h: 0.34, fontFace: SANS, fontSize: 13, margin: 0 });
  const classics = [
    ["1976", "Cyclomatic complexity — McCabe", "the metric behind --hotspots"],
    ["1994", "Okapi BM25 — Robertson · Spärck Jones", "the lexical ranker (twice: subtoken+body, whole-name)"],
    ["1998", "Personalized PageRank — Page · Brin", "the headline importance signal"],
    ["2008", "Louvain modularity — Blondel et al.", "the module / community map"],
    ["2009", "Reciprocal Rank Fusion — Cormack et al.", "deterministic signal fusion (--rank-by=rrf)"],
    ["2011", "Readability model — Posnett · Hindle · Devanbu", "the lexical family of the quality panel"],
    ["2019", "Delta Maintainability Model — di Biase et al.", "--dmm: one comparable number per change"],
  ];
  let y = 2.05;
  for (const [yr, t, d] of classics){
    card(s, MX, y, 6.1, 0.66);
    s.addText(yr, { x: MX+0.16, y: y+0.04, w: 0.75, h: 0.58, fontFace: MONO, fontSize: 12, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText([
      { text: t + "\n", options: { color: TEXT, bold: true, fontSize: 11 } },
      { text: d, options: { color: MUTED, fontSize: 9.5 } },
    ], { x: MX+1.0, y: y+0.04, w: 5.0, h: 0.58, fontFace: SANS, valign: "middle", margin: 0 });
    y += 0.74;
  }
  const modern = [
    ["TDAD · arXiv 2603.17973", "a static test-map cut agent-caused regressions 6.08% → 1.82%; prose TDD instructions alone made agents WORSE → the shape of --test-gate"],
    ["What-to-Retrieve · arXiv 2503.20589", "retrieval selection beats retrieval volume for coding agents → the selection-over-dumping thesis"],
    ["LocAgent / Loc-Bench (2025)", "the localization metric (strict Acc@k) and the frozen 560-instance dataset every accuracy number here is scored on"],
    ["scip-clang · Serena / clangd", "the compiler-grade oracle round 9 graded both tools against — an outside referee, not a rival"],
    ["tree-sitter", "the incremental GLR parsing substrate — 21 grammars vendored, one parser per thread"],
  ];
  y = 2.05;
  for (const [t, d] of modern){
    card(s, 7.0, y, 5.6, 0.95, CARD2);
    s.addText(t, { x: 7.2, y: y+0.06, w: 5.2, h: 0.3, fontFace: MONO, fontSize: 11, bold: true, color: CYAN, margin: 0 });
    s.addText(d, { x: 7.2, y: y+0.36, w: 5.2, h: 0.55, fontFace: SANS, fontSize: 9.5, color: MUTED, margin: 0 });
    y += 1.03;
  }
  foot(s, "counts gated in-repo (readmedriftcheck arm E derives them from LINEAGE.md's own tables) — the lineage is the design rationale, not decoration");
}

/* ── S12c · re-derive this deck ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// do not take any of it on trust", AMBER);
  title(s, "Every claim, and the command that re-derives it");
  const claims = [
    ["161 long flags · 26 slides",        "bash test/deckclaimcheck.sh"],
    ["every --flag named here exists",    "bash test/deckcheck.sh"],
    ["81.4% fewer element bytes",         "bash test/showcasecapturecheck.sh"],
    ["451 gate scripts",                  "bash test/manifestcheck.sh"],
    ["34 repos · 54 papers · 221 surveyed","bash test/readmedriftcheck.sh"],
    ["the ten moments, any row",          "ripwire . --callers=SYM | wc -c"],
    ["the head-to-head table",            "bench/headtohead/r4-2026-08-06/"],
    ["the oracle round",                  "bench/headtohead/r9-2026-08-09/RESULTS.md"],
  ];
  let y = 1.7;
  for (const [claim, cmd] of claims){
    row(s, y, 0.5, [
      { t: claim, w: 5.3,  color: TEXT, size: 12 },
      { t: cmd,   w: 6.2,  color: CYAN, size: 11.5, mono: true },
    ]);
    y += 0.575;
  }
  card(s, MX, 6.32, 12.09, 0.62, CARD2);
  s.addText([
    { text: "The deck is generated, and the generator is gated. ", options: { color: TEXT, bold: true } },
    { text: "present/deck5_ripwire_build.js is scanned for fabricated flags and its slide count is derived from its own addSlide() calls — a deck that drifts from the binary fails the suite.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.41, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md is the source of truth; §7 is the counterexamples, §8 the claims this project refuses to make");
}

/* ── S13 · quickstart / close ───────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// sixty seconds to the first ranked map", CYAN);
  title(s, "Quickstart");
  card(s, MX, 1.95, 12.09, 1.55, CARD2);
  s.addText(
"git clone <repo> && cd ripwire\ncmake -S . -B build && cmake --build build -j     # hermetic: works with the network off\n./build/ripwire --help",
    { x: MX+0.25, y: 2.12, w: 11.6, h: 1.25, fontFace: MONO, fontSize: 13.5, color: TEXT, margin: 0 });
  const firsts = [
    ["ripwire .", "the ranked map — start here on any unfamiliar repo"],
    ["ripwire . --for=\"cache invalidation\"", "the task lens: what to touch, ranked"],
    ["ripwire . --callers=someFunction", "who calls it — with the honesty marker attached"],
    ["ripwire . --quality-panel", "is this code actually rotten? six families, one shortlist"],
    ["ripwire . --test-gate", "before you commit: exactly which tests must run"],
    ["ripwire wrap claude", "wire it into your agent, in that agent's own config shape"],
  ];
  let y = 3.72;
  for (const [cmd, what] of firsts){
    chip(s, cmd, MX, y, 5.7, CYAN, { size: 12, h: 0.46 });
    s.addText(what, { x: 6.55, y: y, w: 6.1, h: 0.46, fontFace: SANS, fontSize: 11.5, color: MUTED, valign: "middle", margin: 0 });
    y += 0.54;
  }
  s.addText([
    { text: "ripgrep", options: { color: CYAN, bold: true } },
    { text: " for the speed. ", options: { color: TEXT } },
    { text: "tripwire", options: { color: AMBER, bold: true } },
    { text: " for the honesty. Apache-2.0.", options: { color: TEXT } },
  ], { x: MX, y: 7.0, w: 12.0, h: 0.45, fontFace: SANS, fontSize: 16, margin: 0 });
}

p.writeFile({ fileName: require("path").join(__dirname, "ripwire-showcase.pptx") })
  .then(() => console.log("WROTE ripwire-showcase.pptx"));
