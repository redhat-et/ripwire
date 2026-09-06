#pragma once

// htmlexport.h — self-contained HTML wiki export (P2-A + Wave-4 #13).
//
// Emits a complete <!DOCTYPE html> document, ONE file, hash-routed into three VIEWS rendered by the
// same embedded JS (no server, no multi-file site — "multi-page" here means multiple in-file views):
//   • #overview        — module (community) cards: name, file count, top-5 symbols, in/out module
//                         degree. Click a card → module view.
//   • #module/ID        — that community's subgraph on the existing canvas sim, its files, entry-point
//                         symbols (high in-degree from OUTSIDE the module), cross-links to neighbours.
//   • #node/ID          — Sourcetrail-style click-to-recenter: a depth-bounded (1-3) ego graph around
//                         any symbol, computed by a JS BFS over the LINKS array at click time, with a
//                         back/forward breadcrumb trail of visited symbols.
//
// Payload: NODES/FILES/LINKS/MODULES JSON literals embedded in one <script> block (deterministic
// order). Vanilla-JS O(n²) spring/repulsion force sim on <canvas> — no D3, no CDN, no network refs.
// Mouse: drag-pan, wheel-zoom, click → recenter ego graph, hover → tooltip. Search box highlights
// matching node labels in the current view.
//
// Determinism contract: the emitted bytes are byte-identical run-to-run.
//   The NODES array is sorted (rank desc, id asc) — same rule as serialize.h.
//   LINKS are sorted (s asc, t asc) among the selected-node pairs.
//   MODULES are sorted (size desc, id asc); each module's `top` list is (rank desc, id asc).
//   No timestamps, hostnames, or random values are emitted into the HTML.
//   The JS sim / BFS / view routing run client-side only and do not affect the HTML bytes.

#include "model.h"
#include "graph.h"       // for Communities / communities() — module (community) grouping
#include "serialize.h"   // for escapeXml (not reused here; we write jsonEscape instead)
#include "infra/jsonesc.h"     // A4-F27: canonical escape core; jsonEscape below is a thin wrapper
#include "cli.h"         // for ColorBy — the --color-by=MODE enum baked into COLOR_MODE (no cycle: cli.h pulls ingest.h/version.h only)

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// JSON-escape a string: escape \ " control chars, AND < > & as \uXXXX — this JSON is emitted inside an
// inline <script> block, where a literal "</script" in ANY string (markdown headings become symbol names
// verbatim) terminates the script element and turns the rest of the name into live markup. Standard
// JSON-in-script hardening; < parses identically in JS.
//
// A4-F27: thin wrapper over the canonical core in jsonesc.h (jsonesc::escapeHtml) — same <>&
// hardening this function has always had. Follow-up: now also validates UTF-8 (invalid
// sequences scrub to raw U+FFFD bytes instead of passing bytes ≥0x80 through raw) — see jsonesc.h's
// header comment. This changes emitted bytes only for invalid-UTF-8 source files; a valid-UTF-8
// file's --html output is unchanged.
inline std::string jsonEscape( std::string_view s )
{
    return jsonesc::escapeHtml( s );
}

// Short lang label for the graph JSON (matches the terse XML convention) — model.h::langTag is the
// canonical switch; this file used to keep a private copy.

// The inline vanilla-JS: a hash-routed wiki over three VIEWS (overview cards / module subgraph /
// node ego-graph), all driven by ONE force-directed sim on <canvas>. No external refs, no build step.
// Determinism note: Math.random/Date.now are used ONLY for runtime interaction state (never influence
// the emitted bytes, which are pure C++ output above this script — the seeded `rng()` below is for
// deterministic-per-load initial layout, not for anything persisted).
//
// It is emitted as FIVE adjacent string literals, concatenated back to back into one <script> in
// declaration order. That is an editing split and nothing else — the same move src/main.cpp and
// src/ingest.cpp made into verbs_*.h / ingest_*.h sections, for the same reason: one 850-line literal is
// not a surface anyone can navigate, and --quality-delta reads a literal's length exactly the way it
// reads a function's. The sections must stay in this order; a seam may fall anywhere in the text, so it
// is placed on a section boundary where a reader would put one anyway.
//
// SECTION 1: what a node LOOKS like — the five --color-by palettes, colorForNode, the legend, the shared
// adjacency every view filters, and the breadcrumb trail.
static const char kScriptColour[] = R"JS(
(function() {
  var canvas = document.getElementById('c');
  var ctx = canvas.getContext('2d');
  var search = document.getElementById('search');
  var info = document.getElementById('info');
  var cardsEl = document.getElementById('cards');
  var crumbEl = document.getElementById('crumb');
  var depthSlider = document.getElementById('depthSlider');
  var depthVal = document.getElementById('depthVal');
  var W = canvas.width, H = canvas.height;

  // colour by lang. The palette is EMITTED (LANG_COLORS above — htmlexport.h::kLangColors, one entry per
  // model.h Lang enumerator, static_asserted against the roster) and never spelled here: the hand-written
  // copy that used to sit in this spot had 9 keys against langTag's 19, so eleven languages fell through to
  // an unlabelled grey. The legend below is built from the same object, so there is no second list to drift.
  var langColor = LANG_COLORS;

  // ---- the `tested` lens' two channels. H5: colorForNode used to return '#2ecc71' / '#e74c3c' — exactly
  // the red-vs-green discrimination the rampColor comment three lines down refuses for cx/churn, and for the
  // same reason. Under simulated deuteranopia that pair collapses from a perceptual distance of 231 to 82:
  // two olives. So `tested` now carries a channel that is NOT hue — tested nodes are FILLED, untested nodes
  // are hollow with a dashed ring — and the hues move onto the blue-yellow axis the ramp already uses, as
  // reinforcement rather than as the message. A monochrome print of this page is still readable.
  // The two fills are ramp STOPS, not a third palette beside it: they were '#26c6da'/'#ff9800', which were
  // stops of the ramp this page used to carry, and became orphan hues the moment that ramp was replaced.
  // Untested is the BRIGHTER of the pair, on the same "risk is what glows" rule the ramp below states.
  var TESTED_FILL = '#2bccc0', UNTESTED_FILL = '#ffce1c';
  var testedStroke = function(n) { return !n.ts; };   // untested ⇒ dashed ring instead of a solid disc

  // ---- --color-by palettes. commColor: 12 categorical dark-bg-friendly hues (comm % 12).
  //
  // rampColor: the shared 5-step COOL→HOT ramp for cx/churn over FIXED thresholds (fixed beats quantiles
  // for legend honesty — the same bucket means the same thing in every repo).
  //   cx buckets:    0 | 1-4 | 5-9 | 10-19 | 20+   → boundaries [1,5,10,20]
  //   churn buckets: 0 | 1-2 | 3-9 | 10-29 | 30+   → boundaries [1,3,10,30]
  //
  // THE RAMP IT REPLACES WAS AN ORDINAL SCALE THAT DID NOT ORDER. ['#4fc3f7','#26c6da','#ffd54f',
  // '#ff9800','#e65100'] measured:
  //   • Relative luminance 0.474 / 0.459 / 0.694 / 0.437 / 0.227 — dark→light order [4,3,1,0,2]. The
  //     BRIGHTEST swatch was the MIDDLE bucket and the DARKEST was the top one, so in greyscale, in
  //     print, or to any reader who reads lightness before hue, an ordinal ramp arrived as a permutation.
  //     Worse for this page specifically: the hottest bucket was the one that RECEDED into the #111
  //     canvas, so the picture dimmed exactly where it should have shouted.
  //   • Steps 0 and 1 collapsed under colour blindness — 29/441 RGB distance under both protanopia and
  //     deuteranopia (1.03:1 in luminance). On the README hero 71.6% of nodes sit in those two stops, so
  //     for ~8% of male readers nearly three-quarters of the flagship image was one flat colour.
  //
  // The replacement is monotone in luminance and ordered COOL-DIM → HOT-BRIGHT, which is the direction
  // that makes the metric legible at a glance on a dark ground: the calm majority sits at the dim end and
  // the rare 20+ nodes are the ones that glow. Measured with a Brettel/Viénot CVD simulation:
  //   stop  hex       rel.lum   vs #111    protan/deutan/tritan distance to the NEXT stop
  //   0     #4b81c9   0.2141    4.75:1     67.0 / 60.8 / 67.7
  //   1     #0fa3ff   0.3352    6.93:1     82.8 / 78.7 / 62.9
  //   2     #2bccc0   0.4751    9.44:1    171.3 / 205.6 / 203.4
  //   3     #ffce1c   0.6549   12.68:1    131.6 / 149.6 /  60.8
  //   4     #fff794   0.8992   17.07:1        —
  // Worst pair over ALL ten pairs, not just adjacent ones: 80.2 normal / 67.0 protan / 60.8 deutan /
  // 60.8 tritan, against the old ramp's 50.3 / 29.0 / 29.0 / 41.1 — the protan/deutan bottleneck more
  // than doubles. Every stop clears 4.5:1 against the canvas ground (the old ramp's floor was 4.98:1 and
  // is preserved at 4.75:1, still above the bar), and the ramp stays on the blue-yellow axis
  // protanopia/deuteranopia do NOT impair: no step is red, and step 2 is a cyan-teal at hue 176°, chosen
  // over the numerically-better green at 168° precisely so that no adjacent pair is a red/green pairing.
  // The gate does not take any of this on trust — test/htmlrendercheck.sh arm (Q) re-derives the
  // luminance and the three CVD simulations from the stops the page actually emits.
  var commColor = ['#4a90d9','#e67e22','#2ecc71','#e74c3c','#9b59b6','#f4c542',
                   '#1abc9c','#e84393','#00acd7','#a3d977','#dea584','#7f8c8d'];
  var rampColor = ['#4b81c9','#0fa3ff','#2bccc0','#ffce1c','#fff794'];
  var CX_STEPS = [1,5,10,20], CHURN_STEPS = [1,3,10,30];
  function rampStep(v, steps) {
    var s = 0;
    for (var i = 0; i < steps.length; i++) if (v >= steps[i]) { s = i + 1; }
    return s;
  }

  // current colour mode — initialized from the baked COLOR_MODE, switched live by the #colorMode select
  var mode = COLOR_MODE;
  function colorForNode(n) {
    if (mode === 'community') return n.comm < 0 ? '#666' : commColor[n.comm % 12];
    if (mode === 'cx') return rampColor[rampStep(n.cx, CX_STEPS)];
    if (mode === 'churn') return CHURN_OK ? rampColor[rampStep(FCHURN[n.file] || 0, CHURN_STEPS)] : '#666';
    if (mode === 'tested') return n.ts ? TESTED_FILL : UNTESTED_FILL;
    return langColor[n.lang] || langColor['?'];
  }

  // legend for the CURRENT mode, rendered into the #legend span.
  //
  // Every mode now NAMES ITS METRIC AND ITS UNITS. It used to emit a bare `0 1-4 5-9 10-19 20+` — five
  // swatches and five number ranges, with nothing anywhere on the page saying ranges of WHAT. The same
  // five buckets are cyclomatic complexity in one mode and git commits in another, and a reader landing on
  // a screenshot could not tell which, nor that "3-9" meant three commits inside an 18-month window rather
  // than three commits ever. The window is not spelled here either: it comes from CHURN_WINDOW, which the
  // C++ fills with the string it actually handed mineChurnPerFile.
  function renderLegend() {
    var el = document.getElementById('legend');
    function sw(c) { return '<span style="background:' + c + '"></span>'; }
    function ring(c) { return '<span style="background:transparent;border:2px dashed ' + c + ';box-sizing:border-box"></span>'; }
    function name(t) { return '<span class="lg">' + t + '</span> '; }
    var html = '', i, lbl;
    if (mode === 'community') {
      var maxComm = -1;
      for (i = 0; i < NODES.length; i++) if (NODES[i].comm > maxComm) { maxComm = NODES[i].comm; }
      var shown = Math.min(maxComm + 1, 12);
      html = name('module (community):');
      for (i = 0; i < shown; i++) html += sw(commColor[i]) + 'm' + i + ' ';
      html += sw('#666') + 'none';
    } else if (mode === 'cx') {
      lbl = ['0','1-4','5-9','10-19','20+'];
      html = name('cyclomatic complexity:');
      for (i = 0; i < 5; i++) html += sw(rampColor[i]) + lbl[i] + ' ';
    } else if (mode === 'churn') {
      if (!CHURN_OK) {
        html = 'churn unavailable (no git history)';
      } else {
        lbl = ['0','1-2','3-9','10-29','30+'];
        html = name('commits (' + (CHURN_WINDOW || 'window not recorded') + '), per FILE:');
        for (i = 0; i < 5; i++) html += sw(rampColor[i]) + lbl[i] + ' ';
      }
    } else if (mode === 'tested') {
      html = name('has a test:') + sw(TESTED_FILL) + 'tested ' + ring(UNTESTED_FILL) + 'untested (hollow)';
    } else {
      html = name('language:');
      for (var k in langColor) { if (Object.prototype.hasOwnProperty.call(langColor, k)) { html += sw(langColor[k]) + (k === '?' ? 'unknown' : k) + ' '; } }
    }
    el.innerHTML = html;
  }

  // ---- global adjacency over ALL selected nodes (NODES/LINKS indices), for BFS ego-graphs and
  // for the "entry points" / cross-link computations. Built once; every view is a FILTERED render
  // over this shared graph, never a re-fetch. ----
  var GN = NODES.length, GL = LINKS.length;
  var gnbr = [];
  for (var i = 0; i < GN; i++) gnbr.push([]);
  for (var k = 0; k < GL; k++) {
    var s = LINKS[k].s, t = LINKS[k].t;
    if (s !== t) { gnbr[s].push(t); gnbr[t].push(s); }
  }
  // directed in-neighbours (for "entry point" = high in-degree from OUTSIDE the module)
  var ginFrom = [];
  for (var i = 0; i < GN; i++) ginFrom.push([]);
  for (var k = 0; k < GL; k++) ginFrom[LINKS[k].t].push(LINKS[k].s);

  // k-hop BFS ego graph around `centre` (a NODES index), depth 1-3. Returns {ids: [...], edges: [{s,t}]}
  // where ids/edges are expressed in ORIGINAL NODES/LINKS index space (the caller remaps to a local
  // 0..n-1 index for the sim). This is the Sourcetrail-style recenter: computed fresh at every click,
  // over the full in-memory LINKS array — no server round-trip.
  function egoGraph(centre, depth) {
    var seen = new Set([centre]);
    var frontier = [centre];
    for (var d = 0; d < depth; d++) {
      var next = [];
      for (var fi = 0; fi < frontier.length; fi++) {
        var u = frontier[fi];
        var nb = gnbr[u] || [];
        for (var j = 0; j < nb.length; j++) if (!seen.has(nb[j])) { seen.add(nb[j]); next.push(nb[j]); }
      }
      frontier = next;
      if (!frontier.length) break;
    }
    var ids = Array.from(seen).sort(function(a,b){ return a-b; });
    var idSet = seen;
    var edges = [];
    for (var k = 0; k < GL; k++) {
      var s = LINKS[k].s, t = LINKS[k].t;
      if (idSet.has(s) && idSet.has(t)) edges.push({ s: s, t: t });
    }
    return { ids: ids, edges: edges };
  }

  // ---- breadcrumb trail (Sourcetrail "recenter" history): an array of visited #node/ID hashes with
  // a position pointer, so back/forward walk it without re-deriving from browser history (which the
  // hash router also updates, but the trail is the authoritative, always-visible UI). ----
  var trail = [];       // array of nodeIdx
  var trailPos = -1;

  function renderCrumb() {
    if (trailPos < 0) { crumbEl.style.display = 'none'; crumbEl.innerHTML = ''; return; }
    crumbEl.style.display = 'block';
    var html = '';
    html += '<a href="#" data-act="back">← back</a>';
    html += '<a href="#" data-act="fwd">→ forward</a>';
    html += '<span class="sep">|</span>';
    for (var i = 0; i < trail.length; i++) {
      if (i > trailPos) break;   // only show the trail up to the current position
      var n = NODES[trail[i]];
      if (i > 0) html += '<span class="sep">/</span>';
      var cls = (i === trailPos) ? ' style="color:#fff;font-weight:600"' : '';
      html += '<a href="#node/' + trail[i] + '"' + cls + '>' + escHtml(n.label) + '</a>';
    }
    crumbEl.innerHTML = html;
    crumbEl.querySelector('[data-act="back"]').addEventListener('click', function(e){ e.preventDefault(); goBack(); });
    crumbEl.querySelector('[data-act="fwd"]').addEventListener('click', function(e){ e.preventDefault(); goForward(); });
  }
  function pushTrail(nodeIdx) {
    trail = trail.slice(0, trailPos + 1);
    trail.push(nodeIdx);
    trailPos = trail.length - 1;
  }
  function goBack() { if (trailPos > 0) { trailPos--; location.hash = '#node/' + trail[trailPos]; } }
  function goForward() { if (trailPos < trail.length - 1) { trailPos++; location.hash = '#node/' + trail[trailPos]; } }

  function escHtml(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  // -- end of section 1 --
)JS";

// SECTION 2 of the renderer: the graph STATE — the sim subset, the force integration and its stability
// clamp, and the settle-before-paint driver. The picture it produces is section 3. Split from section 1
// for the reason src/main.cpp and
// src/ingest.cpp were split into verbs_*.h / ingest_*.h sections: the compile unit is unchanged (adjacent
// literals are emitted back to back, in order, into one <script>), only the editing surface moved. An
// 850-line string literal is not a thing anyone can navigate, and --quality-delta reads its length the
// same way it reads a function's.
static const char kScriptSim[] = R"JS(
  // ---- sim state: rebuilt by each view's render() over a FILTERED node/edge subset. `local` nodes
  // carry {gid, x, y, vx, vy, label, type, lang, rank, comm, cx, ts, file}; `gid` maps back to the
  // NODES index for lookups; the last four feed colorForNode. ----
  var nodes = [], links = [], N = 0, L = 0, nbr = [];
  // Self-calls the sim cannot draw, counted per load (see loadSubset's edge loop) so the caption can
  // state them. A subset view's L was never expected to equal EDGE_TOTAL; the whole-map view's is.
  var selfEdgesDropped = 0;
  var labelSet = new Set();      // local indices that get a persistent text label (see loadSubset's rule)
  var labelDegreeOrder = [];     // the same set as an ARRAY in descending importance, so the declutter in
                                 // draw() places the ones that matter first and drops the collisions
  var MAX_LABELS = 24;
  var MIN_LABEL_DEGREE = 2;      // rule 3: a node with one in-view edge is fringe and its name buys nothing
  var MIN_NODE_PX = 3.0, MAX_NODE_PX = 15.0;   // a node's on-screen radius band (see nodeRadiusPx)
  var LABEL_HALO_PX = 3.0;       // the dark outline stroked behind every label (see placeLabel)
  var LABEL_CULL_PX = 2000;      // a label anchored further than this off-canvas is skipped (see placeLabel)
  // THE INTEGRATOR'S STABILITY LIMIT, and the freeze that came of not having one.
  //
  // The spring term is LINEAR in distance with no cap, so a node's effective stiffness scales with its
  // DEGREE, and explicit Euler at this damping is stable up to roughly degree 100 and unstable past it.
  // Measured on this repository's own map: at --top-k=500 (max degree 70) the layout converges to a
  // 5.7e3 extent; at --top-k=1000 (max degree 130) it grows exponentially — 6.3e3 after one tick, 1.3e94
  // after 280 — and at --top-k=3000 it reaches Infinity outright.
  //
  // What that DID is much worse than an ugly layout. Once a coordinate passes 2^53, adding 1 to it is a
  // no-op in a double, so placeLabel's `for (c = c0; c <= c1; c++)` cell walk stops advancing and NEVER
  // TERMINATES: the tab freezes solid, with no error, no console message and no recovery. It was found
  // by bisection — the same map renders instantly with the sim running and the label block skipped —
  // and it would have been reachable before this view existed, through a depth-3 neighbourhood of any
  // degree-130 hub; a view over the whole map just makes it reachable by opening the page.
  //
  // Capping the DISPLACEMENT one node may take in one tick is the standard remedy and it restores
  // stability rather than merely bounding the damage: at top-k 1000 the peak step falls from 6.7e100 to
  // 6.1e3 and the layout converges to 8.0e3; at top-k 3000, from Infinity to 1.4e4. It binds only during
  // the first violent ticks of a crowded seed — 0.27% of integrations on a 120-node map, whose settled
  // extent moves 2.71e3 to 2.72e3, a difference no picture shows. placeLabel's own cull is the second
  // half: this stops the divergence, that stops any future one from being able to freeze anything.
  var MAX_STEP = 500;            // world units a node may move in one tick
  var ox = 0, oy = 0, scale = 1, autoFit = true;
  var dragging = -1, panStart = null, hovered = -1, selected = -1;
  var searchSet = null;
  var SIM_STEPS = 0, MAX_SIM = 300;
  // The canvas paints its OWN background before anything else. The #111 used to live only on <body>, so the
  // canvas itself was transparent — which is invisible on screen and fatal on export: toDataURL composites
  // onto WHITE, where the #d6d9de labels and the 0.28-alpha edges simply disappear. A picture of this graph
  // was not obtainable from the page that draws it.
  var CANVAS_BG = '#111111';
  // Zoom band. `scale *= factor` was unbounded: a wheel flick reached 0 or Infinity with no way back, and
  // the only recovery was a reload. The floor is below fitView's own 0.05 clamp so a fitted view is never
  // pinned against it; the ceiling is where a 4 px node fills the viewport.
  var SCALE_MIN = 0.02, SCALE_MAX = 8;
  // Pre-paint settling budget (item 4). The sim is 300 O(n^2) steps: 0.2 s at n=239, 0.5 s at n=850, ~11.5 s
  // at n=5000. Running it to completion before the first paint makes the picture appear finished and makes a
  // screenshot reproducible; running it unconditionally would hang the tab on the big end. So it is a budget,
  // and blowing the budget DEGRADES to the old progressive draw rather than freezing — disclosed in the
  // provenance caption, never silent.
  var SETTLE_BUDGET_MS = 2000;
  var settleTimedOut = false;
  // ...and the TOTAL allowance, progressive tail included. The pre-paint budget above bounds how long the
  // page BLOCKS; on its own it bounds nothing about how much work the layout goes on to do, because step()
  // then runs every remaining tick no matter how long they take. That gap was survivable while every view
  // was a subset and only survivable then: at the 5000-node ceiling the remainder is ~20 s of sim (65 ms a
  // tick, measured) plus a full 5000-node/13819-edge redraw per frame, and a page opened there pegged its
  // tab past five minutes — not a degrade, a hang, in the view the page now BOOTS into. Same clock, same
  // flag, same caption: when the allowance is gone the layout stops where it is and renderProv states the
  // step it stopped at, so an under-converged picture is labelled as one rather than passed off as final.
  var LAYOUT_BUDGET_MS = 6000;
  var layoutStopped = false;
  var layoutT0 = 0;
  var DPR = 1;                   // devicePixelRatio at the last resize(); the backing store is scaled by it
  var seed = 42;
  function rng() { seed = (seed * 1664525 + 1013904223) & 0xffffffff; return (seed >>> 0) / 4294967296; }

  // load a subset {ids: [NODES idx...], edges: [{s,t} in NODES idx space]} into the sim, remapped to a
  // local 0..n-1 index space. Resets camera/sim state — called on every view switch.
  function loadSubset(ids, edges) {
    seed = 42;
    var gidToLocal = new Map();
    nodes = [];
    // seed spread floored at 300 world units: a zero-sized viewport at boot (hidden tab/iframe — W=H=0)
    // used to seed every node at the SAME point, and coincident nodes have dx=dy=0 so the repulsion
    // force is zero forever — the cluster could never separate. autoFit reframes whatever spread we pick.
    var SPREAD = Math.max(Math.min(W,H)*0.7, 300);
    for (var i = 0; i < ids.length; i++) {
      var gid = ids[i], src = NODES[gid];
      gidToLocal.set(gid, i);
      nodes.push({ gid: gid, label: src.label, type: src.type, lang: src.lang, rank: src.rank,
                   comm: src.comm, cx: src.cx, ts: src.ts, file: src.file,
                   x: W/2 + (rng()-0.5)*SPREAD, y: H/2 + (rng()-0.5)*SPREAD, vx: 0, vy: 0 });
    }
    N = nodes.length;
    links = [];
    selfEdgesDropped = 0;
    for (var k = 0; k < edges.length; k++) {
      var s = gidToLocal.get(edges[k].s), t = gidToLocal.get(edges[k].t);
      if (s === undefined || t === undefined) continue;
      // A self-call is a real edge — EDGE_TOTAL counts it — and a force layout has nowhere to put it: a
      // spring from a node to itself has zero length and zero direction. Dropping it is right; dropping
      // it SILENTLY was fine only while every view was a subset, where nobody expects L to equal
      // EDGE_TOTAL. The whole-map view is the one place a reader checks the caption's two edge counts
      // against each other, so the difference is counted here and stated by renderProv rather than left
      // as an unexplained gap between two numbers on the same screen.
      if (s === t) { selfEdgesDropped++; continue; }
      links.push({ s: s, t: t });
    }
    L = links.length;
    nbr = [];
    for (var i = 0; i < N; i++) nbr.push([]);
    for (var k = 0; k < L; k++) { nbr[links[k].s].push(links[k].t); nbr[links[k].t].push(links[k].s); }
    // IN-VIEW degree, resolved once per load: it drives label selection AND node radius, and both used to
    // read `rank` instead — a GLOBAL score that says nothing about this view.
    for (var i = 0; i < N; i++) { nodes[i].deg = nbr[i].length; }

    // ---- persistent labels. Three rules, and the measurement that chose them.
    //
    // The old rule was "top 24 by rank". On this repository's own README cut — the depth-2 neighbourhood of
    // lexicalScoresTiered, 239 nodes — it spent 22 of its 24 labels on container methods (size, empty, buf,
    // push_back, find, clear, end, reserve, begin, emplace_back, back, pop_back, grow, min), 13 of them from
    // src/infra/svector.h alone, and left exactly 2 for functions this repository is actually about.
    //
    // Ranking by in-view DEGREE alone does not fix that, and neither does rank x degree: those container
    // methods ARE the hubs (size has in-view degree 111, push_back 59, empty 49), so both rules re-elect
    // them. The measurable culprit is something else — 13 NAMES covered 28 of those nodes. Three different
    // `find`, three `empty`, two each of `buf`/`end`/`begin`/`back`/`data`/`push_back`: the label set was
    // spending its budget printing the same word again and again over different symbols, which is not only
    // clutter but ambiguous (nothing on the page said which `find`).
    //
    //   1. order by IN-VIEW degree (rank breaks ties) — importance in THIS picture, not in the repository
    //   2. at most one label per distinct NAME — the rule that actually frees the budget
    //   3. drop degree-1 nodes — a leaf with one edge is fringe; its name costs a slot and explains nothing
    //
    // Measured on that same cut: 24 labels over 24 distinct names, and 11 of them domain functions
    // (lexicalScoresTiered, namingLensChecks, resolveAtSeed, gitLogFileSets, buildPreciseIncludeAdj,
    // lexicalScoresNameExactTiered, getIndex, resolveAllByNameQualified, declaredFieldsFor,
    // joinNormalizeLookup, lexicalNormalize) against 2 before. rank x degree scored 1.
    //
    // Rule 2 hides symbols, so the page must SAY so rather than let a reader infer "one find exists": the
    // provenance caption states the rule, the tooltip and info line name the FILE, and hover/search/select
    // still label any node on demand. The centre of a #node view is always labelled (draw() forces it).
    labelSet = new Set();
    labelDegreeOrder = [];
    var byDegree = [];
    for (var i = 0; i < N; i++) { if (nodes[i].deg >= MIN_LABEL_DEGREE) { byDegree.push(i); } }
    byDegree.sort(function(a,b){ return nodes[b].deg - nodes[a].deg || nodes[b].rank - nodes[a].rank || a - b; });
    var labelSeenNames = new Set();
    for (var i = 0; i < byDegree.length && labelDegreeOrder.length < MAX_LABELS; i++) {
      var li = byDegree[i];
      if (labelSeenNames.has(nodes[li].label)) continue;
      labelSeenNames.add(nodes[li].label);
      labelDegreeOrder.push(li);
      labelSet.add(li);
    }

    ox = 0; oy = 0; scale = 1; autoFit = true;
    dragging = -1; panStart = null; hovered = -1; selected = -1; searchSet = null;
    SIM_STEPS = 0;
    info.textContent = '';
    if (N === 0) { paintBackdrop(); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); renderProv(); return; }
    settle();
    renderProv();
  }

  // frame ALL nodes into the viewport with padding. Called each settling frame (while autoFit) so the graph
  // is visible no matter how far the force sim spreads it; the user taking control (pan/zoom/drag) stops it.
  function fitView() {
    if (!N) return;
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (var i = 0; i < N; i++) {
      var n = nodes[i];
      if (n.x < minX) minX = n.x;  if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;  if (n.y > maxY) maxY = n.y;
    }
    var pad = 70, gw = Math.max(1, maxX-minX), gh = Math.max(1, maxY-minY);
    scale = Math.max(0.05, Math.min((W-2*pad)/gw, (H-2*pad)/gh, 2.0));
    ox = (W - scale*(minX+maxX))/2;
    oy = (H - scale*(minY+maxY))/2;
  }

  // --- simulation ---
  // simTick() is ONE integration step and paints nothing. It was previously fused with the draw + rAF
  // driver, which is why the page could only ever be watched settling: there was no way to ask for the
  // finished layout. settle() below runs it in a tight loop; step() keeps the progressive path for the
  // over-budget case.
  function simTick() {
    SIM_STEPS++;
    var repulse = 1500, spring = 0.04, rest = 80, dampen = 0.82, gravity = 0.025;
    var cx = W/2, cy = H/2;
    var ax = new Float64Array(N), ay = new Float64Array(N);

    // repulsion O(n²)
    for (var i = 0; i < N; i++) {
      for (var j = i+1; j < N; j++) {
        var dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y;
        var d2 = dx*dx + dy*dy + 1;
        var f = repulse / d2;
        ax[i] += f*dx; ay[i] += f*dy;
        ax[j] -= f*dx; ay[j] -= f*dy;
      }
    }
    // spring along links
    for (var k = 0; k < L; k++) {
      var s = links[k].s, t = links[k].t;
      var dx = nodes[t].x - nodes[s].x, dy = nodes[t].y - nodes[s].y;
      var d = Math.sqrt(dx*dx+dy*dy)+0.001;
      var f = spring*(d-rest)/d;
      ax[s] += f*dx; ay[s] += f*dy;
      ax[t] -= f*dx; ay[t] -= f*dy;
    }
    // gravity to centre
    for (var i = 0; i < N; i++) {
      ax[i] += gravity*(cx-nodes[i].x);
      ay[i] += gravity*(cy-nodes[i].y);
    }
    // integrate, with the per-tick displacement capped at MAX_STEP (see its declaration for the
    // exponential divergence this bounds, and the frozen tab that divergence produced)
    for (var i = 0; i < N; i++) {
      if (i === dragging) continue;
      var vx = (nodes[i].vx + ax[i])*dampen, vy = (nodes[i].vy + ay[i])*dampen;
      var sp = Math.sqrt(vx*vx + vy*vy);
      if (sp > MAX_STEP) { var q = MAX_STEP/sp; vx *= q; vy *= q; }
      nodes[i].vx = vx; nodes[i].vy = vy;
      nodes[i].x += vx;  nodes[i].y += vy;
    }
  }

  function now() { return (window.performance && window.performance.now) ? window.performance.now() : Date.now(); }

  // Run the whole sim before the first paint, under a wall-clock budget. Over budget, hand the rest to the
  // progressive rAF path so a very large graph degrades instead of hanging the tab (non-negotiable: a
  // recoverable limit is a degrade, and it is disclosed — renderProv prints "settling…" while it is true).
  function settle() {
    layoutT0 = now();
    settleTimedOut = false;
    layoutStopped = false;
    while (SIM_STEPS < MAX_SIM) {
      simTick();
      if (now() - layoutT0 > SETTLE_BUDGET_MS) { settleTimedOut = true; break; }
    }
    if (autoFit) fitView();
    draw();
    if (settleTimedOut) requestAnimationFrame(step);
  }

  // the progressive driver — the pre-settle behaviour, now reached only past the pre-paint budget, and
  // itself bounded by the TOTAL allowance (see LAYOUT_BUDGET_MS). It watches the same clock settle()
  // started, so "2 s before the first paint, 6 s of layout in all" is one budget with two checkpoints
  // rather than two budgets that can disagree.
  function step() {
    if (SIM_STEPS >= MAX_SIM) { settleTimedOut = false; renderProv(); return; }
    if (now() - layoutT0 > LAYOUT_BUDGET_MS) {
      layoutStopped = true; settleTimedOut = false;
      if (autoFit) fitView();
      draw();
      renderProv();
      return;
    }
    simTick();
    if (autoFit) fitView();
    draw();
    requestAnimationFrame(step);
  }

  // -- end of section 2 --
)JS";

// SECTION 3 of the renderer: the PICTURE — node size, the backdrop, draw() and its label declutter, and
// the hit test that has to agree with what was drawn. Split from section 2 at the boundary section 2's
// own header already named ("the graph state AND the picture"), for the reason the first split states:
// the translation unit is unchanged (adjacent literals are emitted back to back, in order, into one
// <script>) and only the editing surface moved. It is also what --quality-delta reported when this lane's
// fixes pushed section 2 past 450 lines, which is the metric working as intended rather than a number to
// dodge — the seam is where a reader would put one.
static const char kScriptDraw[] = R"JS(
  // --- draw ---
  // Radius reads IN-VIEW DEGREE, with rank as a tiebreak. The old `4 + 60*sqrt(rank)` spanned 4.60-11.78 px
  // with a MEAN of 5.10 on the README cut — every node a ~5 px dot — while in-view degree over the same
  // nodes spanned 1 to 111. The picture carried a hub/leaf distinction it never drew, so a hairball was the
  // honest rendering of it. sqrt keeps the growth sub-linear so a degree-111 hub is ~4x a degree-2 leaf and
  // not 55x; the small rank term separates equal-degree nodes without ever reordering different-degree ones.
  function nodeRadiusPx(n) { return Math.max(MIN_NODE_PX, Math.min(MAX_NODE_PX, 3 + 1.5*Math.sqrt(n.deg || 0) + 5*Math.sqrt(n.rank))); }

  // The canvas's own background, painted as the FIRST op of every frame. clearRect leaves transparent
  // pixels; on screen the body's #111 shows through and it looks fine, but every export path (toDataURL,
  // the PNG button, a browser "save image") composites transparency onto white, where this page's light
  // labels and 28%-alpha edges vanish. Painting it is what makes the picture exportable at all.
  function paintBackdrop() {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.fillStyle = CANVAS_BG;
    ctx.fillRect(0, 0, W, H);
  }

  function draw() {
    paintBackdrop();
    ctx.save();
    ctx.translate(ox, oy); ctx.scale(scale, scale);

    // highlight set: neighbours of selected
    var hl = null;
    if (selected >= 0) {
      hl = new Set(nbr[selected]);
      hl.add(selected);
    }

    // edges
    ctx.strokeStyle = '#8a8f98';
    ctx.lineWidth = 0.8/scale;
    ctx.globalAlpha = 0.28;
    for (var k = 0; k < L; k++) {
      var s = links[k].s, t = links[k].t;
      if (hl && !hl.has(s) && !hl.has(t)) continue;
      ctx.beginPath();
      ctx.moveTo(nodes[s].x, nodes[s].y);
      ctx.lineTo(nodes[t].x, nodes[t].y);
      ctx.stroke();
    }
    ctx.globalAlpha = 1.0;

    // Node size is a SCREEN quantity converted to world units here, exactly the way the labels already
    // are — a hub has to look like a hub at every zoom, and it must never grow into a blob that swallows
    // the labels around it. Two earlier shapes both failed on this cut and are worth naming: a per-node
    // max against a 3.5-px-over-scale floor FLATTENED everything (at the 0.125 scale a 239-node view fits
    // at, the floor term exceeded every radius, so all 239 nodes drew at the same 3.5 px and the degree
    // signal was invisible in the one picture that needed it); a uniform per-frame multiplier fixed the
    // small end and blew up the large one, turning degree-111 hubs into 36 px discs that occluded four
    // labels. A screen-space band does both jobs and is zoom-invariant.
    // nodes. In `tested` mode an UNTESTED node is drawn hollow with a dashed ring instead of a filled
    // disc — the second, non-hue channel H5 is about. Every other mode fills as before.
    var hollow = (mode === 'tested');
    for (var i = 0; i < N; i++) {
      var n = nodes[i];
      var r = nodeRadiusPx(n)/scale;   // screen px -> world units, inside the transformed draw
      var dim = (hl && !hl.has(i)) || (searchSet && !searchSet.has(i));
      ctx.globalAlpha = dim ? 0.18 : 1.0;
      ctx.beginPath();
      ctx.arc(n.x, n.y, r, 0, 2*Math.PI);
      if (hollow && testedStroke(n)) {
        ctx.fillStyle = CANVAS_BG; ctx.fill();
        ctx.setLineDash([3/scale, 2.5/scale]);
        ctx.strokeStyle = colorForNode(n); ctx.lineWidth = Math.max(1.4/scale, r*0.3); ctx.stroke();
        ctx.setLineDash([]);
      } else {
        ctx.fillStyle = colorForNode(n);
        ctx.fill();
      }
      if (i === selected || i === hovered || n.gid === centreGid) {
        ctx.strokeStyle = '#fff'; ctx.lineWidth = 2/scale; ctx.stroke();
      }
    }

    ctx.globalAlpha = 1.0;
    ctx.restore();

    // ---- labels, decluttered by a greedy occupancy grid, drawn in SCREEN space.
    //
    // They used to be drawn in local-index order with no collision test at all, so two labels whose boxes
    // overlapped simply printed on top of each other: `release`/`resize`/`size` came out as "reisleaze",
    // `empty`/`end` as "eand". Text that is unreadable is worse than absent — it still costs the pixels and
    // now also costs the reader's trust in the ones that ARE legible.
    //
    // The grid is a Set of "col:row" cells over SCREEN space (constant cell size, so the declutter behaves
    // the same at every zoom). Placement is in descending importance — labelDegreeOrder first, then the
    // always-shown hovered/selected/centre — so when two labels collide the more important one is the one
    // that survives. A skipped label is not lost: hover, click or search brings any node's name back.
    //
    // THE TEXT IS DRAWN OUTSIDE THE WORLD TRANSFORM, and this is not a tidiness preference. It used to be
    // drawn inside it at `(11/scale) px` with a `LABEL_HALO_PX/scale` halo — a screen-constant size
    // expressed as a world quantity, which renders identically and costs whatever the zoom says. At the
    // scale a settled 1000-node map fits at, fitView pins `scale` on its 0.05 floor, so those became 220 px
    // glyphs stroked with a 60 px round-join pen, twenty-four of them per frame: the tab stopped responding
    // and never came back. Bisected to this block (a build with the sim on and the labels skipped renders
    // the same map instantly). Every coordinate below is the screen coordinate the occupancy grid was
    // ALREADY computing, so the picture is unchanged pixel for pixel — the difference is that the cost no
    // longer scales with 1/zoom. Node radii were converted to screen units for the same reason one commit
    // earlier; the labels were the half that was left behind, and only a whole-map view was large enough
    // to show it.
    ctx.font = '11px sans-serif';
    // CELL_H is the grid's row pitch; LABEL_H is how tall a drawn label actually is. They are different
    // numbers and conflating them was a real bug: reserving only the row the BASELINE lands in leaves two
    // labels 5 px apart claiming different rows either side of a 16 px boundary. Measured in a browser on
    // the README cut, that still left 2 overprinting pairs after the grid went in — one of them over the
    // centre symbol's own name. The box now spans every row the text touches, and its width is MEASURED
    // rather than estimated from the character count (an estimate that runs short reserves less than it
    // draws, which is the same collision by a second route).
    var labelCells = new Set();
    var CELL_W = 8, CELL_H = 16, LABEL_H = 13;
    function placeLabel(i) {
      var n = nodes[i];
      var rpx = nodeRadiusPx(n);                            // already a SCREEN radius
      var sx = n.x*scale + ox + rpx + 3, sy = n.y*scale + oy + 4;
      var wpx = ctx.measureText(n.label).width;             // screen px directly — the font is screen px now
      // A label anchored well off the canvas is not drawn — and this is a GUARD, not an optimisation.
      // The cell walk below advances an integer counter held in a double, and above 2^53 `c++` stops
      // advancing, so ONE label at an extreme coordinate turns `for (c = c0; c <= c1; c++)` into a loop
      // that cannot terminate: no error, no console message, a permanently frozen tab. MAX_STEP stops
      // the divergence that produced such coordinates; this makes the loop's termination unconditional
      // rather than contingent on the sim staying well behaved. The `!(...)` form rejects NaN too.
      if (!(sx > -LABEL_CULL_PX && sx < W + LABEL_CULL_PX && sy > -LABEL_CULL_PX && sy < H + LABEL_CULL_PX)) { return false; }
      var c0 = Math.floor(sx/CELL_W), c1 = Math.floor((sx + wpx)/CELL_W);
      var r0 = Math.floor((sy - LABEL_H)/CELL_H), r1 = Math.floor((sy + 2)/CELL_H);
      if (c1 - c0 > 200) c1 = c0 + 200;                     // a pathological label cannot monopolise the grid
      for (var rr = r0; rr <= r1; rr++) { for (var c = c0; c <= c1; c++) { if (labelCells.has(c + ':' + rr)) return false; } }
      for (var rr2 = r0; rr2 <= r1; rr2++) { for (var c2 = c0; c2 <= c1; c2++) { labelCells.add(c2 + ':' + rr2); } }
      ctx.globalAlpha = (hl && !hl.has(i)) ? 0.25 : 0.95;
      // A HALO first. The occupancy grid stops labels colliding with each OTHER; it says nothing about
      // what is underneath them, and in a dense view a name lands on top of a node disc — #d6d9de on a
      // bright teal is barely readable, which is the same lost label by a different route. Stroking the
      // glyphs in the canvas background before filling them makes every label legible over anything.
      ctx.lineJoin = 'round';
      ctx.lineWidth = LABEL_HALO_PX;
      ctx.strokeStyle = 'rgba(10,10,10,0.9)';
      ctx.strokeText(n.label, sx, sy);
      ctx.fillStyle = '#e6e9ee';
      ctx.fillText(n.label, sx, sy);
      return true;
    }
    var forced = [];
    if (hovered  >= 0) forced.push(hovered);
    if (selected >= 0) forced.push(selected);
    for (var i = 0; i < N; i++) { if (nodes[i].gid === centreGid) { forced.push(i); break; } }
    for (var fi = 0; fi < forced.length; fi++) placeLabel(forced[fi]);   // never decluttered away
    if (searchSet) {
      // a live query REPLACES the standing set — matches are what you are looking for
      var shown = 0;
      for (var i = 0; i < N && shown < 80; i++) { if (searchSet.has(i) && placeLabel(i)) shown++; }
    } else {
      for (var li = 0; li < labelDegreeOrder.length; li++) placeLabel(labelDegreeOrder[li]);
    }
    ctx.globalAlpha = 1.0;

    // tooltip — now names the FILE. 13 label names covered 28 nodes on the README cut (three different
    // `empty`, three `find`), and the page emitted a FILES array it never read, so the one question a
    // duplicate name raises was the one question the UI could not answer.
    if (hovered >= 0) {
      var n = nodes[hovered];
      var sx = n.x*scale+ox, sy = n.y*scale+oy;
      var msg = n.label + ' [' + n.type + ']  ' + fileOf(n);
      ctx.fillStyle = 'rgba(0,0,0,0.82)';
      ctx.font = '12px ui-monospace,SFMono-Regular,Menlo,monospace';
      var tw = ctx.measureText(msg).width;
      ctx.fillRect(sx+8, sy-18, tw+10, 22);
      ctx.fillStyle = '#fff';
      ctx.fillText(msg, sx+13, sy-2);
    }
  }

  // FILES[n.file] — the path, or an honest blank when the payload has no entry for it. FILES was emitted
  // and never read anywhere in this script (2241 bytes of dead payload on this repository's own map).
  function fileOf(n) { return (FILES && n.file < FILES.length) ? FILES[n.file] : ''; }

  // canvas → world coords
  function toWorldXY(px, py) { return { x: (px-ox)/scale, y: (py-oy)/scale }; }
  function hitTest(px, py) {
    var w = toWorldXY(px, py);
    for (var i = N-1; i >= 0; i--) {
      var n = nodes[i], r = nodeRadiusPx(n)*1.2/scale;   // the DRAWN size, so a click matches what the eye aimed at
      var dx = w.x-n.x, dy = w.y-n.y;
      if (dx*dx+dy*dy <= r*r) return i;
    }
    return -1;
  }

  // -- end of section 3 --
)JS";

// SECTION 4 of the renderer: everything that responds to a person — resize, mouse, wheel, the search
// box and the results panel it fills, and the depth slider. The hash router and the views it renders are
// section 5.
static const char kScriptViews[] = R"JS(
  // ---- resize. Two defects lived here.
  //
  // H10 (sharpness): the backing store was set to the CSS pixel count, so on any retina display the whole
  // canvas was rendered at 1x and scaled up by the compositor — every node edge and every label soft. The
  // backing store is now devicePixelRatio times the CSS size, with the CSS size pinned in style so the page
  // still lays out in CSS pixels; paintBackdrop() re-establishes the DPR transform each frame, so all
  // drawing code keeps working in CSS-pixel coordinates and nothing else had to change.
  //
  // H8 (a stranded camera): step() early-returns once SIM_STEPS >= MAX_SIM, so after settling fitView could
  // never run again — and resize() set canvas.width, which CLEARS the canvas, then redrew with the old
  // camera. Measured: a viewport change dropped the graph from 238788 to 27174 lit pixels, and in one case
  // left a fully blank canvas while the info bar read "221 nodes in view", recoverable only by reload.
  // Re-fitting whenever autoFit is still on restores the invariant the settling loop used to maintain.
  function chromeTop() {
    var p = document.getElementById('prov');
    return 36 + ((p && p.offsetHeight) ? p.offsetHeight : 0);
  }
  function resize() {
    var top = chromeTop();
    var cssW = Math.max(1, window.innerWidth), cssH = Math.max(1, window.innerHeight - top);
    DPR = Math.max(1, Math.min(4, window.devicePixelRatio || 1));
    canvas.style.marginTop = top + 'px';
    canvas.style.width  = cssW + 'px';
    canvas.style.height = cssH + 'px';
    canvas.width  = Math.round(cssW*DPR);
    canvas.height = Math.round(cssH*DPR);
    W = cssW; H = cssH;                      // the drawing code's coordinate space stays CSS pixels
    var el;
    if ((el = document.getElementById('crumb'))) el.style.top = top + 'px';
    if ((el = document.getElementById('hits')))  el.style.top = top + 'px';
    stackCardsBelowHits();   // cards clear the results panel when it is open (see its comment)
    if (autoFit) fitView();
    draw();
  }
  window.addEventListener('resize', resize);

  // mouse events. A click that HITS a node re-centres the ego graph on it (Sourcetrail-style) UNLESS
  // it is already the sole centre of a #node view (double-click-to-reselect toggles the 1-hop
  // highlight instead, same as the old single-view behaviour, so hovering/inspecting still works).
  canvas.addEventListener('mousedown', function(e) {
    autoFit = false;   // user takes control of the camera
    var hit = hitTest(e.clientX, e.clientY);
    if (hit >= 0) { dragging = hit; }
    else { panStart = { x: e.clientX - ox, y: e.clientY - oy }; }
  });
  canvas.addEventListener('mousemove', function(e) {
    if (dragging >= 0) {
      var w = toWorldXY(e.clientX, e.clientY);
      nodes[dragging].x = w.x; nodes[dragging].y = w.y;
      nodes[dragging].vx = 0; nodes[dragging].vy = 0;
      draw(); return;
    }
    if (panStart) { ox = e.clientX - panStart.x; oy = e.clientY - panStart.y; draw(); return; }
    var h = hitTest(e.clientX, e.clientY);
    if (h !== hovered) { hovered = h; draw(); }
  });
  var mouseMoved = false;
  canvas.addEventListener('mousemove', function() { mouseMoved = (dragging >= 0); });
  canvas.addEventListener('mouseup', function(e) {
    var wasDragging = dragging >= 0 && mouseMoved;
    dragging = -1; panStart = null; mouseMoved = false;
    if (wasDragging) return;   // a drag-release is not a click-to-recenter
    var hit = hitTest(e.clientX, e.clientY);
    if (hit < 0) { selected = -1; info.textContent = ''; draw(); return; }
    var n = nodes[hit];
    if (n.gid === centreGid) {
      // clicking the current ego-graph centre toggles 1-hop highlight instead of a no-op recenter
      selected = (selected === hit) ? -1 : hit;
      info.textContent = selected >= 0 ? (n.label + ' · ' + n.type + ' · rank=' + n.rank) : '';
      draw();
    } else {
      location.hash = '#node/' + n.gid;
    }
  });
  // H12: the zoom is CLAMPED. `scale *= factor` compounded without bound, so a few wheel flicks reached
  // 0 or Infinity and there was no gesture that came back — the graph was gone and the only fix was a
  // reload. The factor is recomputed from the clamped scale so the cursor stays the anchor at the rails.
  canvas.addEventListener('wheel', function(e) {
    e.preventDefault();
    autoFit = false;   // user takes control of the camera
    var want = scale * (e.deltaY < 0 ? 1.1 : 0.91);
    var next = Math.max(SCALE_MIN, Math.min(SCALE_MAX, want));
    var factor = next / scale;
    if (factor === 1) return;
    var cx = e.clientX, cy = e.clientY - chromeTop();
    ox = cx - (cx - ox)*factor; oy = cy - (cy - oy)*factor;
    scale = next;
    draw();
  }, { passive: false });

  // ---- search. On the canvas views it filters the CURRENT node set. On the OVERVIEW it used to do
  // nothing at all: renderOverview never calls loadSubset, so N === 0 and this loop ran zero times — the
  // box you land on matched nothing, always, and said nothing about it. That is the same silent-failure
  // shape as H1, in a control the user's eye lands on first. It now searches the WHOLE symbol set (the
  // only set the landing page has) and renders the hits as links into the node view.
  search.addEventListener('input', function() {
    var q = search.value.trim().toLowerCase();
    if (currentView === 'overview') { overviewSearch(q); return; }
    if (!q) { searchSet = null; draw(); return; }
    searchSet = new Set();
    for (var i = 0; i < N; i++)
      if (nodes[i].label.toLowerCase().indexOf(q) >= 0) searchSet.add(i);
    draw();
  });

  // #hits and #cards are both position:fixed at the chrome's bottom edge, so the results panel would sit
  // ON TOP of the first row of module cards. Measured in a browser: hits occupied 76-105 px and cards
  // started at 76. The cards start below whatever the panel currently occupies.
  function stackCardsBelowHits() {
    var h = document.getElementById('hits');
    var visible = h && h.style.display === 'block';
    cardsEl.style.top = (chromeTop() + (visible ? h.offsetHeight : 0)) + 'px';
  }

  function overviewSearch(q) {
    var el = document.getElementById('hits');
    if (!q) { el.style.display = 'none'; el.innerHTML = ''; renderOverviewCards(null); stackCardsBelowHits(); return; }
    var hits = [];
    for (var i = 0; i < NODES.length; i++) {
      if (NODES[i].label.toLowerCase().indexOf(q) >= 0) hits.push(i);
    }
    var html = '<span class="n">' + hits.length + ' symbol' + (hits.length === 1 ? '' : 's') + ' match "' + escHtml(q) + '"' +
               (hits.length > 40 ? ' (first 40)' : '') + '</span>';
    for (var h = 0; h < hits.length && h < 40; h++) {
      var nd = NODES[hits[h]];
      html += '<a href="#node/' + hits[h] + '/2">' + escHtml(nd.label) + '</a>';
    }
    if (!hits.length) html += '<span class="n">nothing in this map — the page holds the top ' + NODE_TOTAL + ' of ' + SYM_TOTAL + ' symbols</span>';
    el.innerHTML = html;
    el.style.display = 'block';
    renderOverviewCards(q);
    stackCardsBelowHits();
  }

  // depth slider (node-view ego graph radius, 1-3)
  var egoDepth = 2;
  depthSlider.addEventListener('input', function() {
    egoDepth = parseInt(depthSlider.value, 10) || 2;
    depthVal.textContent = String(egoDepth);
    if (currentView === 'node') renderNode(centreGid, false);
  });

  // -- end of section 4 --
)JS";

// SECTION 5 of the renderer: the ROUTER and what it renders — the three views, the provenance caption,
// the PNG export, and boot. Section 4 is the hand on the controls; this is where a hash becomes a
// picture. Same split rationale as sections 2/3 above: one literal, one editing surface, no change to
// the emitted document beyond the seam comments.
static const char kScriptRouter[] = R"JS(
  // ---- ROUTER: #graph (home) | #overview | #module/ID | #node/ID[/DEPTH] ----
  var currentView = null;
  var centreGid = -1;   // NODES index the current #node view is centred on (-1 outside node view)

  function setChrome(showCards, showCanvas) {
    cardsEl.className = showCards ? 'show' : '';
    canvas.style.display = showCanvas ? 'block' : 'none';
    depthSlider.parentElement.style.visibility = (currentView === 'node') ? 'visible' : 'hidden';
    if (!showCards) { document.getElementById('hits').style.display = 'none'; }
  }

  // ---- the provenance caption. Two lines under the bar naming what this picture IS: the root it was
  // built from, the ranker whose scores set the sizes, the top-k that bounded the selection and what
  // fraction of the repository that is, the counts in the CURRENT view, and the colour metric. This tool
  // states every truncation it makes in its XML header and the page stated nothing at all about itself —
  // a screenshot of it could not be audited, which is exactly the disclosure the rest of the tool is for.
  // The label rule goes here too: rule 2 of loadSubset deliberately shows one label per name, and a
  // reader must not have to infer that from the picture.
  function renderProv() {
    var el = document.getElementById('prov');
    if (!el) return;
    function k(t) { return '<span class="k">' + t + '</span> '; }
    var metric = { lang: 'language', community: 'module (community)', cx: 'cyclomatic complexity',
                   churn: 'commits (' + (CHURN_WINDOW || 'window not recorded') + ')', tested: 'has a test' }[mode] || mode;
    var pct = SYM_TOTAL ? Math.round(1000*NODE_TOTAL/SYM_TOTAL)/10 : 0;
    var l1 = k('root') + '<b>' + escHtml(ROOT || '.') + '</b>  ' +
             k('ranker') + '<b>' + escHtml(RANKER) + '</b>  ' +
             k('top-k') + '<b>' + TOPK + '</b> of ' + SYM_TOTAL + ' symbols (' + pct + '%)  ' +
             k('map') + '<b>' + NODE_TOTAL + '</b> nodes / <b>' + EDGE_TOTAL + '</b> call edges';
    var viewName = currentView === 'overview' ? MODULES.length + ' modules'
                 : currentView === 'graph'    ? 'whole map'
                 : currentView === 'module'   ? 'module subgraph'
                 : 'depth-' + egoDepth + ' neighbourhood';
    // Self-calls are counted in EDGE_TOTAL on line 1 and cannot be drawn (loadSubset says why). In a
    // subset view nobody compares L against EDGE_TOTAL; in the whole-map view the two numbers sit on the
    // same screen over the same node set, and an unexplained difference between them is precisely the
    // silent inconsistency this caption exists to prevent.
    var drops = ( currentView !== 'overview' && selfEdgesDropped > 0 )
              ? ' (' + selfEdgesDropped + ' self-call' + (selfEdgesDropped === 1 ? '' : 's') + ' not drawn)' : '';
    var l2 = k('view') + '<b>' + viewName + '</b>' + (currentView === 'overview' ? '' : ': ' + N + ' nodes / ' + L + ' edges' + drops) + '  ' +
             k('colour') + '<b>' + escHtml(metric) + '</b>' + (mode === 'churn' && !CHURN_OK ? ' <b>unavailable (no git history)</b>' : '') + '  ' +
             k('labels') + 'top ' + MAX_LABELS + ' by in-view degree, one per name' +
             (settleTimedOut ? '  <b>settling…</b> (layout over the ' + SETTLE_BUDGET_MS + ' ms budget, still converging)'
              : layoutStopped ? '  <b>layout stopped at step ' + SIM_STEPS + ' of ' + MAX_SIM + '</b> (the ' + LAYOUT_BUDGET_MS +
                                ' ms layout budget is spent — positions are under-converged, drag to adjust)'
              : '');
    el.innerHTML = l1 + '<br>' + l2;
  }

  // the module cards, optionally filtered to modules whose name or any MEMBER matches `q` (the overview
  // half of the search fix — a card list that ignores the query would be the same inert control again)
  function renderOverviewCards(q) {
    var html = '', kept = 0;
    for (var m = 0; m < MODULES.length; m++) {
      var mod = MODULES[m];
      if (q) {
        var hit = mod.name.toLowerCase().indexOf(q) >= 0;
        for (var j = 0; !hit && j < mod.members.length; j++) { if (NODES[mod.members[j]].label.toLowerCase().indexOf(q) >= 0) hit = true; }
        if (!hit) continue;
      }
      kept++;
      html += '<div class="card module-card" data-module-card="1" data-mid="' + m + '">';
      html += '<h2>' + escHtml(mod.name) + '</h2>';
      html += '<div class="meta">' + mod.fileCount + ' files · ' + mod.symCount + ' symbols · in ' + mod.inCross + ' / out ' + mod.outCross + '</div>';
      html += '<ul>';
      for (var i = 0; i < mod.top.length; i++) {
        var nd = NODES[mod.top[i]];
        html += '<li>' + escHtml(nd.label) + ' <span style="color:#666">[' + nd.type + ']</span></li>';
      }
      html += '</ul></div>';
    }
    if (MODULES.length === 0) html = '<div style="color:#999;padding:20px">No multi-symbol modules detected — the graph is too small or too sparse for community grouping.</div>';
    else if (q && kept === 0) html = '<div style="color:#999;padding:20px">No module contains a symbol matching "' + escHtml(q) + '".</div>';
    cardsEl.innerHTML = html;
    var els = cardsEl.querySelectorAll('[data-module-card]');
    for (var i = 0; i < els.length; i++) {
      els[i].addEventListener('click', function() { location.hash = '#module/' + this.getAttribute('data-mid'); });
    }
    info.textContent = (q ? kept + ' of ' + MODULES.length : MODULES.length) + ' modules';
  }

  function renderOverview() {
    currentView = 'overview'; centreGid = -1;
    crumbEl.style.display = 'none';
    setChrome(true, false);
    var q = search.value.trim().toLowerCase();
    if (q) { overviewSearch(q); } else { document.getElementById('hits').style.display = 'none'; renderOverviewCards(null); stackCardsBelowHits(); }
    renderProv();
  }

  // ---- #graph — the WHOLE selected node set, drawn. This is the page's home view.
  //
  // WHY IT HAD TO EXIST. --html's own --help line calls the artifact a "force-directed call graph", and
  // until this route the page had no view that drew one: #module/ID and #node/ID[/DEPTH] are both proper
  // SUBSETS, and the landing view was a grid of Louvain cards. Two consequences, and the second is the
  // one that mattered.
  //
  //   1. The cards are a weak first screen on their own terms. Measured on this repository's own map:
  //      65% of them are single-file, 35% carry `in 0 / out 0` (not one cross-module edge), the median
  //      card holds 2 symbols, and the largest are titled `size`, `find`, `empty`, `push_back` — a
  //      community named after its highest-ranked member is named after a container primitive.
  //   2. NO --html PICTURE WAS REPRODUCIBLE BY A SINGLE COMMAND. Every hero needed a fragment pasted in
  //      after the run, and the README's was `#node/431/2` — a POSITION in the rank-sorted array, so not
  //      a name and not stable across --top-k. Name-addressable routes fixed half of that; a run whose
  //      output is the picture fixes the other half. `ripwire DIR --rank-by=rrf --color-by=cx --html=F`
  //      IS the image now, with nothing to paste and nothing to remember.
  //
  // The module overview loses nothing but the boot slot: same route, same bar link, same search-into-
  // modules path. A view that answers "how is this repository grouped" is a good second screen and was a
  // poor first one, because it is an ANSWER about the map and the map itself was never on screen.
  //
  // COST, AND WHY IT DEGRADES RATHER THAN HANGS. This is the largest view the page can build — up to the
  // 5000-node ceiling writeHtml selects at — against a sim that is 300 O(n^2) steps, ~38 ms per step at
  // n=5000. Nothing new is needed for that and nothing new is added: loadSubset already settles under one
  // wall-clock budget and hands the remainder to the progressive rAF path, and renderProv says
  // "settling…" for exactly as long as that is true. A second budget here would be a second thing to
  // keep honest and a second thing to get wrong.
  function renderGraph() {
    currentView = 'graph'; centreGid = -1;
    crumbEl.style.display = 'none';
    setChrome(false, true);
    var ids = [];
    for (var i = 0; i < GN; i++) { ids.push(i); }
    loadSubset(ids, LINKS);   // renders the caption itself, once N/L are known
    info.textContent = GN + ' symbols · ' + MODULES.length + ' modules · click a node to open its neighbourhood';
  }

  function renderModule(mid) {
    var mod = MODULES[mid];
    currentView = 'module'; centreGid = -1;
    crumbEl.style.display = 'none';
    setChrome(false, true);
    if (!mod) { loadSubset([], []); return; }
    var ids = mod.members.slice().sort(function(a,b){ return a-b; });
    var idSet = new Set(ids);
    var edges = [];
    for (var k = 0; k < GL; k++) if (idSet.has(LINKS[k].s) && idSet.has(LINKS[k].t)) edges.push(LINKS[k]);
    loadSubset(ids, edges);
    // entry points: members with an in-edge from OUTSIDE this module (high outside in-degree first)
    var entryCount = new Map();
    for (var i = 0; i < ids.length; i++) {
      var gid = ids[i], cnt = 0, froms = ginFrom[gid] || [];
      for (var j = 0; j < froms.length; j++) if (!idSet.has(froms[j])) cnt++;
      if (cnt > 0) entryCount.set(gid, cnt);
    }
    var entries = Array.from(entryCount.keys()).sort(function(a,b){ return entryCount.get(b)-entryCount.get(a) || a-b; }).slice(0,5);
    var neighNames = mod.neigh.map(function(nid){ return MODULES[nid].name; });
    var msg = mod.name + ' · ' + ids.length + ' symbols · entry points: ' + (entries.map(function(g){return NODES[g].label;}).join(', ') || 'none');
    if (neighNames.length) msg += ' · neighbours: ' + neighNames.join(', ');
    info.textContent = msg;
  }

  function renderNode(gid, addToTrail) {
    currentView = 'node'; centreGid = gid;
    setChrome(false, true);
    var eg = egoGraph(gid, egoDepth);
    loadSubset(eg.ids, eg.edges);
    if (addToTrail !== false) pushTrail(gid);
    renderCrumb();
    var n = NODES[gid];
    info.textContent = n.label + ' · ' + n.type + ' · ' + fileOf(n) + ' · rank=' + n.rank + ' · depth=' + egoDepth + ' · ' + eg.ids.length + ' nodes in view';
    renderProv();
  }

  // ---- #node/WHAT[/DEPTH] — WHAT is a symbol NAME, or (still) a numeric NODES index.
  //
  // The index is a position in the rank-sorted NODES array, so `#node/431/2` is not a name, is not stable
  // across --top-k, and is not something a document can be written against: the README's own hero link is
  // exactly that, and it silently addresses a different symbol the moment the map is regenerated with a
  // different ceiling. Resolving by name first makes `#node/lexicalScoresTiered/2` mean what it says, and
  // keeps every existing numeric link working. A name that appears on several symbols resolves to the
  // highest-ranked one — deterministic (NODES is rank-sorted, so it is the first match) and disclosed in
  // the info line, which names the file the winner came from.
  function gidForRoute(what) {
    if (/^[0-9]+$/.test(what)) { var ix = parseInt(what, 10); return (ix >= 0 && ix < NODES.length) ? ix : -1; }
    var want = decodeURIComponent(what);
    for (var i = 0; i < NODES.length; i++) { if (NODES[i].label === want) return i; }
    var lower = want.toLowerCase();
    for (var j = 0; j < NODES.length; j++) { if (NODES[j].label.toLowerCase() === lower) return j; }
    return -1;
  }

  // ---- ROUTER. Boot sets the hash, and setting it fires hashchange, so route() used to run TWICE at
  // boot: harmless when the landing view was a card grid, and a doubled full-map settle now that it is
  // not. routedHash makes route() idempotent on the hash it last rendered. Nothing real is suppressed —
  // every navigation on this page changes the hash, and the browser fires no hashchange for a set to
  // the value already there (which is why click-the-current-node already went through its own branch).
  var routedHash = null;
  function route() {
    var h = location.hash.replace(/^#/, '');
    if (h === routedHash) { return; }
    routedHash = h;
    var parts = h.split('/');
    if (parts[0] === 'overview') {
      renderOverview();
    } else if (parts[0] === 'module' && parts[1] !== undefined) {
      renderModule(parseInt(parts[1], 10) || 0);
    } else if (parts[0] === 'node' && parts[1] !== undefined) {
      if (parts[2] !== undefined) { egoDepth = Math.max(1, Math.min(3, parseInt(parts[2],10)||2)); depthSlider.value = String(egoDepth); depthVal.textContent = String(egoDepth); }
      var gid = gidForRoute(parts[1]);
      if (gid < 0) {
        // an unresolvable route is SAID, not silently redirected to node 0 (which is what parseInt||0 did).
        // It lands on the home view — the whole map, which is the thing you can then search — rather than
        // on whichever view happened to be the landing page when this branch was written.
        renderGraph();
        info.textContent = 'no symbol named "' + decodeURIComponent(parts[1]) + '" in this map (top ' + NODE_TOTAL + ' of ' + SYM_TOTAL + ')';
        return;
      }
      var already = trail[trailPos] === gid;
      renderNode(gid, !already);
    } else {
      renderGraph();   // '#graph', an empty hash, and any hash this router does not recognise
    }
  }
  window.addEventListener('hashchange', route);

  // colour-mode selector: initial value from the baked COLOR_MODE; a change re-renders legend + canvas
  var modeSel = document.getElementById('colorMode');
  modeSel.value = COLOR_MODE;
  modeSel.addEventListener('change', function() { mode = modeSel.value; renderLegend(); renderProv(); draw(); });
  renderLegend();

  // ---- PNG export. With the canvas painting its own background and its backing store scaled by DPR, this
  // is now the correct way to get a picture of the graph out of the page: an OS screenshot is capped at the
  // display's own resolution and includes the browser chrome, whereas toDataURL hands back exactly the
  // backing store — DPR x the CSS size, background composited, nothing else in the frame.
  // The exported bitmap is COMPOSED, not the raw canvas. The provenance caption is DOM, so a plain
  // canvas.toDataURL() hands back a picture that states nothing about itself — the exact defect the
  // caption was added to fix, surviving into the one artifact the caption exists for. A README image, a
  // bug report, a slide: every one of them travels without the page around it. So the export draws the
  // graph into its own bitmap with the caption stamped underneath, in the page's own colours.
  var STAMP_H = 44;
  var STAMP_PAD = 14, STAMP_FONT_MAX = 13, STAMP_FONT_MIN = 8;
  function stampFont(px) { return px + 'px ui-monospace,SFMono-Regular,Menlo,monospace'; }
  // The caption is one long unwrapped line of monospace, and the exported bitmap is as wide as whatever
  // viewport produced it. At a fixed 13 px the first real export CLIPPED it at the frame edge: the root
  // path stopped mid-word and the colour metric — the thing the picture is coloured BY — was gone
  // entirely, cut off past the right margin with nothing to say so. That is the export existing to carry
  // provenance and silently dropping half of it, which is worse than not stamping at all, because the
  // remaining half looks complete. The font is fitted to the widest line instead (never larger than 13,
  // floored at 8 where monospace stops being readable), and a line that STILL does not fit is elided
  // with a marker so the loss is visible in the image rather than at its edge.
  function stampProvenance(g, w, y) {
    var el = document.getElementById('prov');
    var lines = el ? el.innerText.split('\n').slice(0, 2) : [];
    g.fillStyle = '#0b0b0b';  g.fillRect(0, y, w, STAMP_H);
    g.fillStyle = '#2a2a2a';  g.fillRect(0, y, w, 1);
    var avail = w - 2*STAMP_PAD, widest = 0, i;
    g.font = stampFont(STAMP_FONT_MAX);
    for (i = 0; i < lines.length; i++) { widest = Math.max(widest, g.measureText(lines[i]).width); }
    var px = STAMP_FONT_MAX;
    if (widest > avail && widest > 0) { px = Math.max(STAMP_FONT_MIN, Math.floor(STAMP_FONT_MAX*avail/widest)); }
    g.font = stampFont(px);
    g.fillStyle = '#9aa1aa';
    for (i = 0; i < lines.length; i++) {
      var t = lines[i];
      if (g.measureText(t).width > avail) {
        while (t.length > 1 && g.measureText(t + '…').width > avail) { t = t.slice(0, -1); }
        t = t + '…';
      }
      g.fillText(t, STAMP_PAD, y + 19 + i*17);
    }
  }
  function exportBitmap() {
    var out = document.createElement('canvas');
    out.width  = canvas.width;
    out.height = canvas.height + Math.round(STAMP_H*DPR);
    var g = out.getContext('2d');
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    g.fillStyle = CANVAS_BG;  g.fillRect(0, 0, out.width/DPR, out.height/DPR);
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.drawImage(canvas, 0, 0);
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    stampProvenance(g, out.width/DPR, canvas.height/DPR);
    return out;
  }
  document.getElementById('savePng').addEventListener('click', function() {
    if (canvas.style.display === 'none') { info.textContent = 'nothing to export from the module list — open Graph, a module or a symbol first'; return; }
    draw();                                     // guarantee the frame is current, not a stale hover state
    var a = document.createElement('a');
    var slug = (currentView === 'node' && centreGid >= 0) ? NODES[centreGid].label : (currentView || 'graph');
    a.download = 'ripwire-' + String(slug).replace(/[^A-Za-z0-9_.-]+/g, '_') + '-' + mode + '.png';
    a.href = exportBitmap().toDataURL('image/png');
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
  });

  // boot
  if (GN === 0) { setChrome(false, true); resize(); paintBackdrop(); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); renderProv(); return; }
  resize();
  if (!location.hash) location.hash = '#graph';   // the boot default: the map itself (see renderGraph)
  route();
  resize();   // the caption's height is only knowable once it has content; re-measure so the canvas fits
})();
)JS";

// A module CARD (one Louvain community, restricted to the selected node set): the Overview view's
// unit. `top` holds up to 5 selected-array indices (rank desc, id asc). `inCross`/`outCross` count
// LINKS edges crossing the module boundary (from/to a DIFFERENT module), among selected nodes only —
// the "in/out dependency counts" the Overview card shows.
struct ModuleCard
{
    std::uint32_t        commId = 0;
    std::string           name;          // top-ranked member's label, or dominant dir if unnamed
    std::vector<NodeId>   files;          // distinct fileIds touched by this module's selected symbols
    std::vector<NodeId>   members;        // selected-array indices in this module (rank desc, id asc)
    std::vector<NodeId>   top;            // up to 5 of `members`
    std::uint32_t         inCross  = 0;
    std::uint32_t         outCross = 0;
};

// The COLOR_MODE JS literal's value for each --color-by mode (the baked INITIAL mode; the in-page
// selector switches live among all five). A NAME TABLE indexed by the enumerator, deliberately NOT
// the switch-returning-a-tag idiom: model.h::refRoleTag, accessshape.h::shapeName and
// namingconsistency.h::styleTag are already three copies of that shape, and --quality-delta reads a
// fourth as a new clone of a reused helper rather than as a house pattern. Declaration ORDER is the
// index, which is what the static_assert pins — add an enumerator without a name and it is a
// compile error, not a silently wrong colour mode.
inline constexpr const char* kColorByNames[] = { "lang", "community", "cx", "churn", "tested" };
inline constexpr std::size_t kColorByNameCount = sizeof( kColorByNames ) / sizeof( kColorByNames[0] );
static_assert( kColorByNameCount == std::size_t( ColorBy::Tested ) + 1,
               "kColorByNames must carry one name per ColorBy enumerator, in declaration order" );

inline const char* colorByLabel( ColorBy m ) noexcept
{
    const std::size_t idx = std::size_t( m );
    return idx < kColorByNameCount ? kColorByNames[ idx ] : kColorByNames[0];
}

// The ranker's name for the page's provenance caption. Same NAME TABLE shape as kColorByNames above, and
// beside it deliberately: main.cpp's §B2.1 ternary names only the three rankers that STAMP the XML header
// (authority/hub/rrf, nullptr for the rest), which is the right answer for a header attribute that must
// stay absent on a default run and the wrong one for a caption that has to say something on every run.
// Declaration ORDER is the index and the static_assert pins it, so adding a RankBy enumerator without a
// name is a compile error rather than a page that silently mislabels its own ranks.
inline constexpr const char* kRankByNames[] = { "pagerank", "authority", "hub", "rrf", "churn", "churn-decay" };
inline constexpr std::size_t kRankByNameCount = sizeof( kRankByNames ) / sizeof( kRankByNames[0] );
static_assert( kRankByNameCount == std::size_t( RankBy::ChurnDecay ) + 1,
               "kRankByNames must carry one name per RankBy enumerator, in declaration order" );

// H4 — the language palette, indexed by the Lang enumerator so it cannot fall behind the roster.
//
// It already had. model.h::langTag emits 19 tags; the page's hand-written `langColor` object carried 9
// keys and its hand-written legend listed 8, so ELEVEN languages (js sh java rb json cs c toml yaml php
// lua) fell through to an unlabelled `#999` — on this repository six Bash symbols rendered as a grey the
// legend never explained, which is "not measured" painted as if it were an answer (non-negotiable #3).
// Two hand-maintained lists behind one enum is the drift shape; ONE table indexed BY the enum, with the
// same static_assert kColorByNames uses, is the fix — and the page's swatches AND its legend are both
// generated from this array, so no second list is left to drift.
//
// Hues: the nine that existed keep their exact values, so a cpp/py/ts/go/rs/swift/objc/md corpus emits the
// same colours it always did; the eleven new ones are each language's conventional colour, picked to stay
// separable on the page's #111 canvas. `?` (Lang::Unknown) keeps the neutral grey, which is honest — an
// unknown language IS the absence of a measurement — and the legend now labels that swatch as such.
inline constexpr const char* kLangColors[] = {
    "#4a90d9",   // Cpp
    "#f4c542",   // Python
    "#2d79c7",   // TypeScript
    "#00acd7",   // Go
    "#dea584",   // Rust
    "#fa7343",   // Swift
    "#9b59b6",   // ObjC
    "#7f8c8d",   // Markdown
    "#e8d44d",   // JavaScript
    "#89e051",   // Bash
    "#b07219",   // Java
    "#c9455f",   // Ruby
    "#95a5a6",   // Unknown ("?")
    "#a8b5c4",   // Json
    "#68217a",   // CSharp
    "#7aa6c2",   // C
    "#a0703c",   // Toml
    "#cb9a3d",   // Yaml
    "#8892bf",   // Php
    "#4b8bbe",   // Lua
};
inline constexpr std::size_t kLangColorCount = sizeof( kLangColors ) / sizeof( kLangColors[0] );
static_assert( kLangColorCount == std::size_t( Lang::Lua ) + 1,
               "kLangColors must carry one hex colour per Lang enumerator, in declaration order — a language with "
               "no swatch renders as an unlabelled grey the legend cannot explain" );


// Side data for the --color-by node-colour modes. Every export embeds ALL five modes' data; the
// pointers may be null (the caller's pipeline may not have computed them), in which case the page
// still renders — tested falls to 0, churn to 0 with churnEvidence=false disclosing "no git history".
struct HtmlColorExtras
{
    const std::vector<std::uint8_t>*  tested        = nullptr;   // per-symbol tested flag (QMetrics.tested), may be null
    const std::vector<std::uint32_t>* fileChurn     = nullptr;   // per-ORIGINAL-file commit counts (ing.files index), may be null
    bool                              churnEvidence = false;     // false ⇒ no git history: churn mode discloses instead of lying zeros
    ColorBy                           initialMode   = ColorBy::Lang;
    std::string_view                  churnWindow;               // the window the caller actually MINED ("18 months ago"), for the legend
    RankBy                            ranker        = RankBy::PageRank;   // for the provenance caption — which ranks these are
};

// The three --color-by JS constants, emitted as ONE section because they are one payload: the
// file-keyed churn array, the flag saying whether that array is evidence at all, and the baked
// initial mode. Its own function so writeHtml — already a 360-line emitter — grows by a call.
// `fileList` maps FILES index → ing.files index; churn is file-granularity, so it is keyed by the
// former and looked up through the latter.
inline void writeColorPayload( std::FILE* out, const std::vector<std::uint32_t>& fileList, const HtmlColorExtras& color )
{
    std::fprintf( out, "const FCHURN = [" );
    for( std::size_t i = 0; i < fileList.size(); ++i )
    {
        const std::uint32_t fc = ( color.fileChurn && fileList[i] < color.fileChurn->size() ) ? ( *color.fileChurn )[ fileList[i] ] : 0u;
        std::fprintf( out, "%s%u", i ? "," : "", fc );
    }
    std::fprintf( out, "];\n" );
    // whether git evidence existed — 0 ⇒ churn mode discloses "unavailable" instead of lying zeros
    std::fprintf( out, "const CHURN_OK = %d;\n", color.churnEvidence ? 1 : 0 );
    // the WINDOW those commit counts were mined over. The legend used to print a bare "0 1-2 3-9 10-29 30+"
    // with no unit and no horizon, so "3-9" could be read as three commits ever; it is three commits inside
    // this window. Passed in by the caller rather than spelled in the JS, because the JS cannot know what
    // main.cpp handed mineChurnPerFile — a hardcoded string here is a claim the page cannot back.
    std::fprintf( out, "const CHURN_WINDOW = \"%s\";\n", jsonEscape( color.churnWindow ).c_str() );
    // the baked initial colour mode (--color-by=MODE); the in-page selector switches live from here
    std::fprintf( out, "const COLOR_MODE = \"%s\";\n", colorByLabel( color.initialMode ) );
    // the ranker whose scores the `rank` field carries — the provenance caption's second fact
    // Read from kRankByNames INLINE rather than through an accessor of its own. A second four-line
    // "clamp the enumerator, fall back to entry 0" function beside colorByLabel is a duplicate of it, and
    // factoring the clamp into a shared helper only moved the problem — colorByLabel then became a
    // one-line wrapper that matched three unrelated one-line wrappers elsewhere in the tree. This name
    // has exactly one consumer, so it does not need a function; colorByLabel, which is the shared
    // accessor for a mode the selector also switches, keeps its own.
    const std::size_t rankIdx = std::size_t( color.ranker );
    std::fprintf( out, "const RANKER = \"%s\";\n", rankIdx < kRankByNameCount ? kRankByNames[ rankIdx ] : kRankByNames[0] );
    // the LANG palette the page's swatches AND its legend are both built from: langTag(L) -> hex, in
    // enumerator order. It belongs in this function and not one of its own: this IS the colour payload,
    // and a separate emitter beside it was a fifth copy of the same comma-separated JSON loop.
    // Deterministic by construction — a constexpr array walked in index order.
    std::fprintf( out, "const LANG_COLORS = {" );
    for( std::size_t i = 0; i < kLangColorCount; ++i )
    {
        std::fprintf( out, "%s\"%s\":\"%s\"", i ? "," : "", langTag( Lang( i ) ), kLangColors[i] );
    }
    std::fprintf( out, "};\n" );
}

// The document SHELL — <head>, the whole stylesheet, and the chrome (#bar, #prov, #hits, #crumb,
// #cards, the canvas) — up to the opening <script>. Lifted out of writeHtml for the reason
// writeColorPayload states at its own head: writeHtml is a 400-line emitter and this is a nameable,
// input-free concept, so the caller grows by a call instead of by ninety lines of literal. Nothing here
// depends on the graph; every byte is constant.
inline void writeDocumentShell( std::FILE* out )
{
    // emit document head. Three in-file VIEWS share one #bar + one #c canvas; #cards (Overview) and
    // #crumb (breadcrumb trail) are additional DOM regions toggled by the router, not separate pages.
    std::fprintf( out,
        "<!DOCTYPE html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>ripwire wiki</title>\n"
        "<style>\n"
        "* { margin:0; padding:0; box-sizing:border-box; }\n"
        "body { background:#111; color:#eee; font:13px/1.4 sans-serif; overflow:hidden; }\n"
        "#bar { position:fixed; top:0; left:0; right:0; height:36px; background:rgba(0,0,0,.7);\n"
        "       display:flex; align-items:center; gap:12px; padding:0 12px; z-index:10; }\n"
        "#bar h1 { font-size:13px; font-weight:600; white-space:nowrap; }\n"
        "#bar a.nav { color:#7fb2ff; text-decoration:none; font-size:12px; white-space:nowrap; }\n"
        "#bar a.nav:hover { text-decoration:underline; }\n"
        "#search { background:#222; border:1px solid #444; color:#eee; padding:3px 8px;\n"
        "          border-radius:4px; font-size:12px; width:200px; }\n"
        "#info { font-size:12px; color:#aaa; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }\n"
        "#legend { font-size:11px; color:#999; white-space:nowrap; }\n"
        "#legend span { display:inline-block; width:10px; height:10px; border-radius:50%%; margin-right:3px; }\n"
        // the metric NAME inside the legend is text, not a swatch — it must escape the circle rule above
        "#legend span.lg { width:auto; height:auto; border-radius:0; color:#c8ccd2; margin-right:5px; }\n"
        "#colorMode { background:#222; border:1px solid #444; color:#eee; padding:3px 6px;\n"
        "             border-radius:4px; font-size:12px; }\n"
        "#depth { font-size:11px; color:#999; display:flex; align-items:center; gap:4px; white-space:nowrap; }\n"
        "canvas { display:block; }\n"
        "#crumb { position:fixed; top:36px; left:0; right:0; z-index:9; background:rgba(20,20,20,.85);\n"
        "         font-size:11px; padding:4px 12px; white-space:nowrap; overflow-x:auto; display:none; }\n"
        "#crumb a { color:#7fb2ff; text-decoration:none; margin-right:4px; }\n"
        "#crumb a:hover { text-decoration:underline; }\n"
        "#crumb .sep { color:#666; margin-right:4px; }\n"
        "#cards { position:fixed; top:36px; left:0; right:0; bottom:0; overflow:auto; padding:16px;\n"
        "         display:none; grid-template-columns:repeat(auto-fill,minmax(260px,1fr)); gap:12px; align-content:start; }\n"
        "#cards.show { display:grid; }\n"
        "#cards.show ~ canvas, #cards.show ~ #crumb { display:none; }\n"
        ".card { background:#1b1b1e; border:1px solid #333; border-radius:6px; padding:12px; cursor:pointer; }\n"
        ".card:hover { border-color:#7fb2ff; }\n"
        ".card h2 { font-size:13px; margin-bottom:6px; word-break:break-all; }\n"
        ".card .meta { font-size:11px; color:#999; margin-bottom:6px; }\n"
        ".card ul { list-style:none; font-size:11px; color:#ccc; }\n"
        ".card li { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }\n"
        // H11: `.module-card { data-module-card:1; }` used to sit here. `data-module-card:1` is not a CSS
        // declaration — the property does not exist, so the whole rule was dropped by every parser that has
        // ever read this page. The ATTRIBUTE the overview router selects on is written by renderOverview
        // (data-module-card="1") and is unaffected; this was dead bytes shaped like a selector.
        "#prov { position:fixed; left:0; right:0; z-index:8; background:rgba(0,0,0,.55); color:#8f96a0;\n"
        "        font:11px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; padding:3px 12px;\n"
        "        white-space:nowrap; overflow-x:auto; border-bottom:1px solid #222; }\n"
        "#prov b { color:#c8ccd2; font-weight:600; }\n"
        "#prov .k { color:#6f757e; }\n"
        "#bar button { background:#222; border:1px solid #444; color:#eee; padding:3px 8px;\n"
        "              border-radius:4px; font-size:12px; cursor:pointer; }\n"
        "#bar button:hover { border-color:#7fb2ff; }\n"
        "#hits { position:fixed; top:36px; left:0; right:0; z-index:9; background:rgba(20,20,20,.92);\n"
        "        font-size:12px; padding:6px 12px; display:none; max-height:40%%; overflow:auto; }\n"
        "#hits a { color:#7fb2ff; text-decoration:none; margin-right:14px; display:inline-block; }\n"
        "#hits a:hover { text-decoration:underline; }\n"
        "#hits .n { color:#8f96a0; margin-right:10px; }\n"
        "</style>\n"
        "</head>\n"
        "<body>\n"
        "<div id=\"bar\">\n"
        "  <h1>ripwire wiki</h1>\n"
        // Two named routes in the bar, in the order the page uses them. "Graph" is the boot view (the
        // whole selected map — see the renderGraph header for why it is the boot view and not the cards);
        // the module overview keeps its route and its link and is simply no longer the landing page. Its
        // link is relabelled from "Overview" to "Modules" because it is no longer an overview of anything
        // the reader has not already seen — it is one specific lens on the map now on screen behind it.
        "  <a class=\"nav\" href=\"#graph\">Graph</a>\n"
        "  <a class=\"nav\" href=\"#overview\">Modules</a>\n"
        "  <input id=\"search\" type=\"text\" placeholder=\"search labels...\">\n"
        "  <span id=\"depth\">depth <input id=\"depthSlider\" type=\"range\" min=\"1\" max=\"3\" value=\"2\" style=\"width:60px\"><span id=\"depthVal\">2</span></span>\n"
        "  <span id=\"info\"></span>\n"
        "  <select id=\"colorMode\"><option value=\"lang\">lang</option><option value=\"community\">community</option>"
            "<option value=\"cx\">cx</option><option value=\"churn\">churn</option><option value=\"tested\">tested</option></select>\n"
        "  <span id=\"legend\"></span>\n"
        "  <button id=\"savePng\" title=\"download this view as a PNG\">PNG</button>\n"
        "</div>\n"
        // The provenance caption. This tool's whole posture is disclosure — every truncation stated, every
        // count labelled a floor — and the page stated NOTHING about itself: not the root it maps, not which
        // ranker produced the sizes, not how many of the repository's symbols it is showing. Two lines, filled
        // by renderProv() from the baked constants above, so the picture can be read (or screenshotted into a
        // README) without the argv that made it.
        "<div id=\"prov\"></div>\n"
        "<div id=\"hits\"></div>\n"
        "<div id=\"crumb\"></div>\n"
        "<div id=\"cards\"></div>\n"
        "<canvas id=\"c\"></canvas>\n"
        "<script>\n"
    );
}

// writeHtml — emit a self-contained HTML wiki document to `out`.
//   top-min(topK, 5000) symbols selected by (rank desc, id asc) — same ordering rule as serialize.h.
//   Links: call edges among selected nodes only, sorted (s asc, t asc). Deterministic.
//   Modules: one Louvain community (graph.h communities()) per selected-node group that has ≥2
//   members, sorted (member count desc, id asc) — mirrors --communities' "a lone symbol is not a
//   module" rule so the wiki and the text verb agree.
inline void writeHtml( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank, const Graph& g, int topK, const HtmlColorExtras& color,
                       std::string_view rootArg = {} )   // R-R: the root FILES[] entries are relative to
{
    const std::vector<std::uint32_t>& outOff     = g.outOff;
    const std::vector<NodeId>&        outTargets = g.outTargets;
    const std::size_t S = ing.symbols.size();
    if( S == 0 )
    {
        // empty graph: still emit a valid document
        std::fprintf( out, "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>ripwire graph</title></head>"
                           "<body><p>No symbols found.</p></body></html>\n" );
        return;
    }

    // select top-min(topK, 5000) by (rank desc, id asc)
    const std::size_t cap = std::min<std::size_t>( topK > 0 ? std::size_t( topK ) : S, std::min( S, std::size_t( 5000 ) ) );

    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    std::sort( order.begin(), order.end(), [ & ]( NodeId a, NodeId b )
               {
        if( rank[a] != rank[b] ) { return rank[a] > rank[b];
}
        return a < b; } );
    order.resize( cap );

    // map original symbol id → selected-array index (kNoNode if not selected)
    std::vector<NodeId> idxOf( S, kNoNode );
    for( NodeId k = 0; k < cap; ++k )
    {
        idxOf[order[k]] = k;
    }

    // build LINKS: edges among selected nodes, sorted (s asc, t asc) for determinism
    struct Edge { std::uint32_t s, t; };
    std::vector<Edge> edges;
    for( NodeId k = 0; k < cap; ++k )
    {
        const NodeId  id  = order[k];
        const NodeId  si  = k;
        for( std::uint32_t e = outOff[id]; e < outOff[id + 1]; ++e )
        {
            const NodeId tgt = outTargets[e];
            if( tgt < S && idxOf[tgt] != kNoNode )
            {
                edges.push_back( { si, idxOf[tgt] } );
            }
        }
    }
    // sort (s, t) for determinism
    std::sort( edges.begin(), edges.end(), [ ]( const Edge& a, const Edge& b )
    { return a.s != b.s ? a.s < b.s : a.t < b.t; } );
    // deduplicate (same symbol can appear via different resolve paths)
    edges.erase( std::unique( edges.begin(), edges.end(), [ ]( const Edge& a, const Edge& b )
    { return a.s == b.s && a.t == b.t; } ), edges.end() );

    // ---- module (community) grouping over the FULL graph, restricted to the selected node set ----
    // communities() is deterministic (id-order local-moving, ties → lower id) so this is byte-stable.
    const Communities cm = communities( g );

    // distinct files touched by SELECTED symbols, in first-seen (selected-array) order → dense FILES
    // index. A node's `file` JSON field is an index into this array, not a full path string, so
    // repeated paths (many symbols per file) cost 4 bytes instead of the whole string per node.
    std::vector<NodeId> fileIdOf( cap );        // selected-array index → FILES index
    std::vector<std::uint32_t> fileList;        // FILES index → original ing.files index
    {
        std::vector<NodeId> remap( ing.files.size(), kNoNode );
        for( NodeId k = 0; k < cap; ++k )
        {
            const std::uint32_t origFile = ing.symbols[ order[k] ].fileId;
            if( origFile < remap.size() && remap[ origFile ] == kNoNode )
            {
                remap[ origFile ] = NodeId( fileList.size() );
                fileList.push_back( origFile );
            }
            fileIdOf[k] = ( origFile < remap.size() ) ? remap[ origFile ] : kNoNode;
        }
    }

    // group selected nodes by community id (commId = cm.comm[order[k]], the ORIGINAL symbol's community)
    HashMap<std::uint32_t, std::uint32_t> moduleSlot;   // commId → index into `modules`
    std::vector<ModuleCard> modules;
    for( NodeId k = 0; k < cap; ++k )
    {
        const std::uint32_t c = cm.comm[ order[k] ];
        auto it = moduleSlot.find( c );
        std::uint32_t slot;
        if( it == moduleSlot.end() ) { slot = std::uint32_t( modules.size() ); moduleSlot.emplace( c, slot ); modules.push_back( {} ); modules.back().commId = c; }
        else
        {
            slot = it->second;
        }
        modules[ slot ].members.push_back( k );
        if( fileIdOf[k] != kNoNode &&
            std::find( modules[ slot ].files.begin(), modules[ slot ].files.end(), fileIdOf[k] ) == modules[ slot ].files.end() )
        {
            modules[ slot ].files.push_back( fileIdOf[k] );
        }
    }
    // keep only modules with ≥2 selected members — "a lone symbol is not a module" (matches --communities)
    modules.erase( std::remove_if( modules.begin(), modules.end(),
                   [ ]( const ModuleCard& m ) { return m.members.size() < 2; } ), modules.end() );

    // per-selected-node → module-array slot (kNoNode if its community didn't survive the ≥2 filter)
    std::vector<NodeId> moduleOf( cap, kNoNode );
    for( NodeId m = 0; m < modules.size(); ++m )
    {
        for( NodeId k : modules[m].members )
        {
            moduleOf[k] = m;
        }
    }

    // rank/name the members within each module, pick top-5, name the card after the top member
    for( ModuleCard& m : modules )
    {
        std::sort( m.members.begin(), m.members.end(), [ & ]( NodeId a, NodeId b )
        { return rank[ order[a] ] != rank[ order[b] ] ? rank[ order[a] ] > rank[ order[b] ] : order[a] < order[b]; } );
        std::sort( m.files.begin(), m.files.end() );
        const std::size_t topN = std::min<std::size_t>( 5, m.members.size() );
        m.top.assign( m.members.begin(), m.members.begin() + topN );
        m.name = ing.symbols[ order[ m.members.front() ] ].name;
    }

    // cross-module edge counts (in/out), counted over the selected LINKS only
    for( const Edge& e : edges )
    {
        const NodeId ms = moduleOf[e.s], mt = moduleOf[e.t];
        if( ms == kNoNode || mt == kNoNode || ms == mt )
        {
            continue;
        }
        ++modules[ ms ].outCross;
        ++modules[ mt ].inCross;
    }

    // final module order: member count desc, commId asc (deterministic; matches --communities)
    std::vector<NodeId> modOrder( modules.size() );
    for( NodeId m = 0; m < modules.size(); ++m )
    {
        modOrder[m] = m;
    }
    std::sort( modOrder.begin(), modOrder.end(), [ & ]( NodeId a, NodeId b )
               {
        if( modules[a].members.size() != modules[b].members.size() ) { return modules[a].members.size() > modules[b].members.size();
}
        return modules[a].commId < modules[b].commId; } );
    // moduleRank[slot] = position in modOrder (the DISPLAY id used in JSON/URLs) — stable, 0-based
    std::vector<NodeId> moduleRank( modules.size() );
    for( NodeId disp = 0; disp < modOrder.size(); ++disp )
    {
        moduleRank[modOrder[disp]] = disp;
    }

    writeDocumentShell( out );

    // emit NODES array — one entry per selected symbol, deterministic (rank-desc, id-asc order
    // preserved). `file` indexes FILES; `comm` is the display module id (moduleRank), or -1 if this
    // node's community didn't survive the ≥2-member filter (a singleton — still shown, just moduleless).
    // `cx` (cyclomatic) and `ts` (tested 0/1) feed the --color-by cx/tested modes; churn stays out of
    // the per-node record because it is file-granularity — one FCHURN array keyed by `file` instead.
    std::fprintf( out, "const NODES = [\n" );
    for( NodeId k = 0; k < cap; ++k )
    {
        const Symbol&  sym  = ing.symbols[ order[k] ];
        const float    r    = rank[ order[k] ];
        const char*    tag  = symTag( sym.kind );
        const char*    lang = langTag( sym.lang );
        const NodeId   slot = moduleOf[k];
        const long     comm = ( slot == kNoNode ) ? -1L : long( moduleRank[ slot ] );
        const unsigned ts   = ( color.tested && order[k] < color.tested->size() && ( *color.tested )[ order[k] ] ) ? 1u : 0u;

        char rankBuf[ 24 ];
        std::snprintf( rankBuf, sizeof( rankBuf ), "%.4f", double( r ) );

        std::fprintf( out, "  {\"id\":%u,\"label\":\"%s\",\"type\":\"%s\",\"lang\":\"%s\",\"rank\":%s,\"file\":%u,\"comm\":%ld,\"cx\":%u,\"ts\":%u}",
                      unsigned( k ),
                      jsonEscape( sym.name ).c_str(),
                      jsonEscape( tag ).c_str(),
                      jsonEscape( lang ).c_str(),
                      rankBuf,
                      unsigned( fileIdOf[k] == kNoNode ? 0 : fileIdOf[k] ),
                      comm,
                      unsigned( sym.cx ),
                      ts );
        if( k + 1 < cap )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

    // R-R: the corpus root, stated ONCE — the page's own envelope anchor, so a reader can still resolve
    // the relative FILES[] entries below back to a checkout. Empty on a multi-root run, where each path
    // already carries its own root label.
    const std::string htmlRootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    std::fprintf( out, "const ROOT = \"%s\";\n", jsonEscape( htmlRootPrefix ).c_str() );

    // emit FILES array — one path string per distinct selected-symbol file, first-seen order (R-R: each
    // relative to ROOT above, so the page no longer repeats the checkout prefix once per file)
    std::fprintf( out, "const FILES = [\n" );
    for( std::size_t i = 0; i < fileList.size(); ++i )
    {
        const std::string_view hp = rootArg.empty() ? std::string_view( ing.files[ fileList[i] ] )
                                                    : rw::sarif::rootRelativeUri( ing.files[ fileList[i] ], htmlRootPrefix );
        std::fprintf( out, "  \"%s\"", jsonEscape( std::string( hp ) ).c_str() );
        if( i + 1 < fileList.size() )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

    // the --color-by payload: per-FILES-index churn, its evidence flag, and the baked initial mode
    writeColorPayload( out, fileList, color );

    // emit LINKS array — sorted (s, t) pairs
    std::fprintf( out, "const LINKS = [\n" );
    for( std::size_t k = 0; k < edges.size(); ++k )
    {
        std::fprintf( out, "  {\"s\":%u,\"t\":%u}", unsigned( edges[k].s ), unsigned( edges[k].t ) );
        if( k + 1 < edges.size() )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

    // The remaining provenance facts for the caption. NODE_TOTAL/EDGE_TOTAL are the whole selected map;
    // the caption states them beside the CURRENT view's counts, because "221 nodes in view" out of 200 and
    // out of 5000 are different claims and the page used to make neither. TOPK is the ceiling that produced
    // the selection (the effective one, after --max-tokens/adaptive have cut it — the number that explains
    // the map you are looking at, not the number that was typed).
    std::fprintf( out, "const TOPK = %zu;\nconst NODE_TOTAL = %zu;\nconst EDGE_TOTAL = %zu;\nconst SYM_TOTAL = %zu;\n",
                  cap, cap, edges.size(), S );

    // emit MODULES array — the Overview cards, sorted (member count desc, commId asc). `members` and
    // `top` are selected-array (NODES) indices; `neigh` is the sorted, deduped list of OTHER display
    // module ids this module shares a selected LINKS edge with (Module view's "cross-links").
    std::fprintf( out, "const MODULES = [\n" );
    for( std::size_t disp = 0; disp < modOrder.size(); ++disp )
    {
        const ModuleCard& m = modules[ modOrder[disp] ];
        std::vector<std::uint32_t> neigh;
        for( const Edge& e : edges )
        {
            const NodeId ms = moduleOf[e.s], mt = moduleOf[e.t];
            if( ms == kNoNode || mt == kNoNode )
            {
                continue;
            }
            if( ms == modOrder[disp] && mt != modOrder[disp] )
            {
                neigh.push_back( moduleRank[mt] );
            }
            if( mt == modOrder[disp] && ms != modOrder[disp] )
            {
                neigh.push_back( moduleRank[ms] );
            }
        }
        std::sort( neigh.begin(), neigh.end() );
        neigh.erase( std::unique( neigh.begin(), neigh.end() ), neigh.end() );

        std::fprintf( out, "  {\"id\":%zu,\"name\":\"%s\",\"symCount\":%zu,\"fileCount\":%zu,\"files\":[",
                      disp, jsonEscape( m.name ).c_str(), m.members.size(), m.files.size() );
        for( std::size_t i = 0; i < m.files.size(); ++i )
        {
            std::fprintf( out, "%u", unsigned( m.files[i] ) );
            if( i + 1 < m.files.size() )
            {
                std::fprintf( out, "," );
            }
        }
        std::fprintf( out, "],\"members\":[" );
        for( std::size_t i = 0; i < m.members.size(); ++i )
        {
            std::fprintf( out, "%u", unsigned( m.members[i] ) );
            if( i + 1 < m.members.size() )
            {
                std::fprintf( out, "," );
            }
        }
        std::fprintf( out, "],\"top\":[" );
        for( std::size_t i = 0; i < m.top.size(); ++i )
        {
            std::fprintf( out, "%u", unsigned( m.top[i] ) );
            if( i + 1 < m.top.size() )
            {
                std::fprintf( out, "," );
            }
        }
        std::fprintf( out, "],\"inCross\":%u,\"outCross\":%u,\"neigh\":[", m.inCross, m.outCross );
        for( std::size_t i = 0; i < neigh.size(); ++i )
        {
            std::fprintf( out, "%u", neigh[i] );
            if( i + 1 < neigh.size() )
            {
                std::fprintf( out, "," );
            }
        }
        std::fprintf( out, "]}" );
        if( disp + 1 < modOrder.size() )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

    // inline the JS sim + wiki router
    std::fprintf( out, "%s%s%s%s%s", kScriptColour, kScriptSim, kScriptDraw, kScriptViews, kScriptRouter );

    std::fprintf( out,
        "</script>\n"
        "</body>\n"
        "</html>\n"
    );
}

}   // namespace rw
