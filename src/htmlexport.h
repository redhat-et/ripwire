#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


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
#include "gitstamp.h"     // htmlProvenanceFor — the page's at= stamp (2026-09-06)
#include "graph.h"       // for Communities / communities() — module (community) grouping
#include "serialize.h"   // for escapeXml (not reused here; we write jsonEscape instead)
#include "infra/jsonesc.h"     // A4-F27: canonical escape core; jsonEscape below is a thin wrapper
#include "cli.h"         // for ColorBy — the --color-by=MODE enum baked into COLOR_MODE (no cycle: cli.h pulls ingest.h/version.h only)
#include "infra/Diagnostics.h"  // VERIFY — writeEdgePayload asserts the emitted LINKS order, which the layout depends on

#include <algorithm>
#include <cmath>
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

// R-R/PRIV: drop the HOME PAIR from a corpus root, so the emitted page never carries the operator's
// home directory. `/home/jane.doe/src/app` → `src/app`; `C:\\Users\\Bob\\code` → `code`; `/home/jane`
// → `~`. (Examples are written in the Linux spelling throughout: the macOS one differs only in its
// leading segment, and test/ripwirepubliccheck.sh arm 2 forbids that literal prefix in the tree.) This is the SECURITY half of the pair described at the `const ROOT` emit site — the JS
// `rootShort()` is the presentation half, and is a no-op on what this returns.
//
// Two properties this is written for, both learned from the JS version's first cut:
//   • Structure, not tail. Taking the last two segments looks equivalent and is not: for `~/myproject`
//     — plausibly the most common layout anywhere — the home directory IS one of the last two, so a
//     tail-taker republishes the username. The leaking segment's POSITION is knowable; use it.
//   • Separators are plural. Splitting on '/' alone passes `C:\\Users\\Bob\\code` through whole.
// A root with no home pair is returned VERBATIM rather than rebuilt, so `/opt/src` keeps its leading
// separator and only the leaking shape is rewritten.
inline std::string stripHomePair( std::string_view root )
{
    if( root.empty() )
    {
        return std::string();                       // multi-root: each path carries its own label
    }

    std::vector<std::string_view> parts;
    for( std::size_t begin = 0; begin < root.size(); )
    {
        const std::size_t end = root.find_first_of( "/\\", begin );
        const std::string_view seg = root.substr( begin, end == std::string_view::npos ? std::string_view::npos : end - begin );
        if( !seg.empty() && seg != "." )
        {
            parts.push_back( seg );
        }
        if( end == std::string_view::npos )
        {
            break;
        }
        begin = end + 1;
    }

    std::size_t first = 0;
    if( first < parts.size() && parts[ first ].size() == 2 && parts[ first ][ 1 ] == ':' )
    {
        ++first;                                    // a Windows drive letter is not the home root
    }

    const auto equalsFolded = []( std::string_view a, std::string_view b )
    {
        if( a.size() != b.size() )
        {
            return false;
        }
        for( std::size_t i = 0; i < a.size(); ++i )
        {
            const char ca = ( a[i] >= 'A' && a[i] <= 'Z' ) ? char( a[i] - 'A' + 'a' ) : a[i];
            if( ca != b[i] )
            {
                return false;
            }
        }
        return true;
    };

    std::size_t dropCount = 0;
    if( first < parts.size() )
    {
        const std::string_view lead = parts[ first ];
        if( ( equalsFolded( lead, "users" ) || equalsFolded( lead, "home" ) ) && parts.size() - first >= 2 )
        {
            dropCount = 2;                          // the root segment AND the user name below it
        }
        else if( equalsFolded( lead, "root" ) )
        {
            dropCount = 1;                          // /root IS the home directory; there is no name below it
        }
    }

    // 2026-09-06 stranger audit: a root with no home pair used to be emitted VERBATIM — a checkout under
    // /Volumes, /srv, /work or a symlinked home shipped its whole absolute path into a page whose only use of
    // ROOT is the caption's last-two-segments label. Nothing on the page needs more than that label, so the
    // envelope IS the label now: the last two segments, with an ellipsis when anything was cut. The JS
    // rootShort() is idempotent over this shape.
    std::size_t begin    = first + dropCount;
    bool        elided   = false;
    if( parts.size() - begin > 2 )
    {
        begin  = parts.size() - 2;
        elided = true;
    }

    std::string out = elided ? std::string( "\xE2\x80\xA6/" ) : std::string();
    for( std::size_t i = begin; i < parts.size(); ++i )
    {
        if( i != begin )
        {
            out += '/';
        }
        out.append( parts[i] );
    }
    return out.empty() ? std::string( "~" ) : out;  // the root WAS the home directory, and nothing else
}

// Short lang label for the graph JSON (matches the terse XML convention) — model.h::langTag is the
// canonical switch; this file used to keep a private copy.

// The inline vanilla-JS: a hash-routed wiki over three VIEWS (overview cards / module subgraph /
// node ego-graph), all driven by ONE force-directed sim on <canvas>. No external refs, no build step.
// Determinism note: Math.random/Date.now are used ONLY for runtime interaction state (never influence
// the emitted bytes, which are pure C++ output above this script — the seeded `rng()` below is for
// deterministic-per-load initial layout, not for anything persisted).
//
// It is emitted as SIX adjacent string literals, concatenated back to back into one <script> in
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
  // The two fills are ramp STOPS, not a third palette beside it: they were '#26c6da'/'#ff9800' and then
  // '#2bccc0'/'#ffce1c', stops of two earlier ramps that each became an orphan hue the moment the ramp
  // moved on. They are now stops 1 and 2, the ramp's own BLUE↔AMBER pair — the widest-separated pair it
  // has (340/441 normal, 259 protan, 269 deutan, 257 tritan, against 265/143/166/257 for the next best),
  // which is what a binary channel wants. Untested is the BRIGHTER of the two, on the same "risk is what
  // glows" rule the ramp below states.
  var TESTED_FILL = '#29a0cc', UNTESTED_FILL = '#eb9809';
  var testedStroke = function(n) { return !n.ts; };   // untested ⇒ dashed ring instead of a solid disc

  // ---- --color-by palettes. commColor: 12 categorical dark-bg-friendly hues for the community LENS,
  // where hue IS the message (comm % 12). hullColor is a SEPARATE palette for the module outlines —
  // see its own note below; the two used to be one array and that is exactly the defect it fixes.
  //
  // rampColor: the shared 5-step COOL→HOT ramp for cx/churn over FIXED thresholds (fixed beats quantiles
  // for legend honesty — the same bucket means the same thing in every repo).
  //   cx buckets:    0 | 1-4 | 5-9 | 10-19 | 20+   → boundaries [1,5,10,20]
  //   churn buckets: 0 | 1-2 | 3-9 | 10-29 | 30+   → boundaries [1,3,10,30]
  //
  // DEEP BLUE → MID BLUE → AMBER → ORANGE → PALE YELLOW, monotone in luminance and ordered COOL-DIM →
  // HOT-BRIGHT, which is the direction that makes a metric legible at a glance on a dark ground: the
  // calm majority sits at the dim end and the rare 20+ nodes are the ones that glow. Blue↔orange is the
  // canonical dichromacy-safe axis — red/green confusion does not act on it at all — and amber-on-black
  // is the instrument-panel convention for the same reason a car gauge uses it. Measured with a
  // Brettel/Viénot 1999 CVD simulation:
  //   stop  hex       hue    rel.lum   vs #111    normal/protan/deutan/tritan distance to the NEXT stop
  //   0     #4b81c9   214°   0.2141     4.75:1     87.6 /  66.9 /  61.4 /  68.0
  //   1     #0fa3ff   203°   0.3352     6.93:1    340.2 / 259.1 / 269.4 / 256.6
  //   2     #f9a408    39°   0.4671     9.30:1    141.8 / 150.2 / 145.6 /  61.3
  //   3     #fdcc90    33°   0.6608    12.78:1     63.0 /  68.3 /  61.7 /  64.4
  //   4     #fefabb    56°   0.9303    17.63:1        —
  // Worst ADJACENT pair, which with a monotone ramp is also the worst of all ten pairs: 63.0 normal /
  // 66.9 protan / 61.4 deutan / 61.3 tritan, against the teal-midpoint ramp this replaces at 80.2 /
  // 66.9 / 61.4 / 61.1. Protanopia and deuteranopia are UNCHANGED to the decimal, because on both
  // ramps the pair that sets them is stops 0-1 and those two stops did not move. Normal vision gives up
  // 17 points and tritanopia gains 0.2. Every stop still clears 4.5:1 against the canvas ground at the
  // same 4.75:1 floor, and the greyscale ladder is 1.458 / 1.343 / 1.375 / 1.379 — no step weaker than
  // the 1.342 the previous ramp's weakest step measured.
  //
  // THREE THINGS THE MEASUREMENT DECIDED, none of which were obvious from the ladder written down:
  //   • THE ORANGE HAS TO BE THE LIGHTER OF THE TWO WARM STOPS, and therefore the less saturated. At
  //     full chroma an amber sits at luminance 0.585 and an orange at 0.400 — the hue that reads as
  //     "orange" is intrinsically darker — so "amber then orange" and "monotone in luminance" can only
  //     both hold if the orange is a light one. Under a greyscale-step floor no colour above luminance
  //     0.64 in the orange hue band exceeds 0.47 chroma, so stop 3 is a light orange at 0.43 and that
  //     is the ceiling, not a preference. Ordering the warm run by hue instead (orange, then amber, the
  //     way every saturated heat ramp runs) measures 63.9 / 64.6 / 61.4 / 61.4 — the same to within a
  //     point and a half, so nothing was bought by inverting the ladder that was asked for.
  //   • THE TOP STOP IS PALE BY BLUE, NOT BY DESATURATION. Keeping the previous ramp's '#fff794' above
  //     a light orange collapses the top pair to 39.2/441 under deuteranopia — below the gate's 45 bar
  //     — because the two differ by five points of blue and almost nothing else. '#fefabb' is paler AND
  //     further away (61.7) precisely because its paleness comes from a blue channel at 187: blue is
  //     the one channel protanopia and deuteranopia keep intact.
  //   • THE TEAL WAS LOAD-BEARING AND IS NOT MISSED. A cyan midpoint separates from both neighbours
  //     across the whole spectrum (171/205/204 to the next stop), which is why the ramp before this one
  //     could afford a pale top. Three adjacent warm stops cannot do that, and the cost is confined to
  //     NORMAL vision, where 63.0/441 is still eight times the JND and four times the 16/441 at which
  //     two swatches start to look alike.
  // Thresholds stay FIXED. A quantile ramp would let a cold corpus manufacture a hot node by making the
  // same swatch mean 20+ in one repository and 3 in another. The gate does not take any of this on
  // trust — test/htmlrendercheck.sh arm (Q) re-derives the luminance, the greyscale step and the three
  // CVD simulations from the stops the page actually emits, each with its own mutation control.
  var commColor = ['#4a90d9','#e67e22','#2ecc71','#e74c3c','#9b59b6','#f4c542',
                   '#1abc9c','#e84393','#00acd7','#a3d977','#dea584','#7f8c8d'];
  var rampColor = ['#005ec9','#29a0cc','#eb9809','#f0ce48','#fffcd1'];
  // hullColor: the module OUTLINES, and the reason they are not commColor any more. Identity is carried
  // by containment now (see draw()'s hull block and loadSubset's), so the outline's hue says nothing the
  // outline and its label do not already say — it is decoration. Borrowed from commColor it was
  // decoration ON THE RAMP'S OWN AXES: a saturated blue (#4a90d9) and a saturated amber (#f4c542) drawn
  // over a picture whose metric runs from blue to amber. Measured against the ramp above, the nearest of
  // those twelve sits 22.0/441 from a ramp stop — closer than two ADJACENT cx buckets are to each other
  // (63.0) — so nothing in the picture could tell a reader whether a colour meant a module or a
  // complexity. These twelve are a narrow desaturated violet→rose band, chosen by maximin over that band
  // so the closest two are still 36.9/441 apart (a hull is a REGION; two adjacent ones must not read as
  // one), every one is at most 0.196 chromatic against the ramp's 0.263 floor, the nearest is 56.8/441
  // from any ramp stop, and every one clears 4.71:1 on the #111 ground because the module's NAME is
  // drawn in it. The band is 240-355°, well clear of both the ramp's blue (203-214°) and its warm run
  // (33-56°). Consecutive ids alternate dim/bright so two neighbouring modules differ by 52/441 or more.
  var hullColor = ['#768188','#8c7b7c','#848994','#978d87','#91949f','#a49393','#96a1aa','#ae9b9c','#a4aeb6','#b8a2a6','#c1b0a8','#afb8c5'];
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

  // C1 — how many LINKS carry the per-edge split-arm flag. Counted ONCE: it is a property of the
  // baked payload, not of the current view, and the legend clause below must not claim a per-view number.
  var AMB_LINKS = 0;
  for (var _k = 0; _k < LINKS.length; _k++) if (LINKS[_k].a) { AMB_LINKS++; }

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
      var shown = Math.min(maxComm + 1, hullColor.length);
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
    // C1 EDGE-CONFIDENCE clause. The node swatches above colour the node legend; this names the one thing
    // that is true of the LINES. Emitted only when the payload actually has such an edge — a corpus that
    // resolved cleanly gets no clause, because a legend for a stroke nobody can see is noise, not honesty.
    // The count is of the SELECTED MAP (the top-K subgraph this document baked), not of the whole graph
    // and not of the current view: renderProv's clause is the per-view number, and the two are labelled
    // apart because an ego view draws a handful of these and the map holds all of them.
    if (AMB_LINKS > 0) {
      html += '<span class="ec"> \u2014 dashed edge: the resolver could not choose between same-name'
            + ' definitions and split the call over all of them (' + AMB_LINKS + ' of ' + LINKS.length
            + ' in this map); read the source before trusting one.</span>';
    }
    el.innerHTML = html;
  }

  // ---- global adjacency over ALL selected nodes (NODES/LINKS indices), for BFS ego-graphs and
  // for the "entry points" / cross-link computations. Built once; every view is a FILTERED render
  // over this shared graph, never a re-fetch.
  //
  // IT IS KEPT DIRECTED. LINKS is a directed call graph — `s` is the caller and `t` the callee, built
  // in writeHtml straight off the CSR's outOff/outTargets — and this block used to open by throwing
  // that away: ONE adjacency list, each edge pushed into it from both ends, after which nothing
  // downstream could tell a caller from a callee. Measured on the pages this tool actually emits, the direction
  // discarded there is almost never ambiguous: MUTUAL pairs (A calls B and B calls A, the only case
  // where an undirected edge loses nothing) are 1 of 243 on the default page, 5 of 4721 at --top-k=2000
  // and 0 of 646 on another corpus, and self-calls are 0 everywhere. So 99.6-100% of edges had exactly
  // one true direction and the renderer symmetrised all of them.
  //
  // Two things were wrong with that, and only the second is invisible. draw() had no direction to draw
  // (fixed there, with a head). And egoGraph walked the symmetrised list, so a depth-2 neighbourhood
  // reached "my caller's other callees" by the same step as "my callee's callees" and presented them
  // identically — the sibling-of-a-caller arrives looking like a grandchild. The walk below still
  // crosses both directions, because a symbol's neighbourhood genuinely is its callers AND its callees;
  // what it no longer does is forget which was which, so the node view can state the split.
  var GN = NODES.length, GL = LINKS.length;

  var gout = [], gin = [];
  for (var i = 0; i < GN; i++) { gout.push([]); gin.push([]); }
  for (var k = 0; k < GL; k++) {
    var s = LINKS[k].s, t = LINKS[k].t;
    if (s !== t) { gout[s].push(t); gin[t].push(s); }
  }

  // k-hop BFS ego graph around `centre` (a NODES index), depth 1-3. Returns
  // {ids, edges: [{s,t}], callees, callers} where ids/edges are expressed in ORIGINAL NODES/LINKS index
  // space (the caller remaps to a local 0..n-1 index for the sim) and callees/callers are the DEPTH-1
  // counts in each direction. This is the Sourcetrail-style recenter: computed fresh at every click,
  // over the full in-memory LINKS array — no server round-trip.
  function egoGraph(centre, depth) {
    var seen = new Set([centre]);
    var frontier = [centre];
    var callees = (gout[centre] || []).length, callers = (gin[centre] || []).length;
    for (var d = 0; d < depth; d++) {
      var next = [];
      for (var fi = 0; fi < frontier.length; fi++) {
        var u = frontier[fi];
        var outs = gout[u] || [], ins = gin[u] || [];
        for (var j = 0; j < outs.length; j++) if (!seen.has(outs[j])) { seen.add(outs[j]); next.push(outs[j]); }
        for (var j2 = 0; j2 < ins.length; j2++) if (!seen.has(ins[j2])) { seen.add(ins[j2]); next.push(ins[j2]); }
      }
      frontier = next;
      if (!frontier.length) break;
    }
    var ids = Array.from(seen).sort(function(a,b){ return a-b; });
    var idSet = seen;
    var edges = [];
    for (var k = 0; k < GL; k++) {
      // the RECORD, not a fresh {s,t}: a rebuilt pair drops the split-arm bit this edge was emitted
      // with, and an edge that silently loses its own doubt draws solid — a false statement, in the one
      // view where a reader is looking closely at a handful of edges
      if (idSet.has(LINKS[k].s) && idSet.has(LINKS[k].t)) edges.push(LINKS[k]);
    }
    return { ids: ids, edges: edges, callees: callees, callers: callers };
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
  var ambEdges = 0;              // in-view edges the resolver could not pin — the caption states the count
  var labelSet = new Set();      // local indices that get a persistent text label (see loadSubset's rule)
  // ---- module HULLS: the groups draw() outlines, rebuilt per load (see loadSubset's hull block).
  var hullGroups = [];           // [{ comm, name, idx: [local indices] }], largest first
  var hullsTotal = 0;            // modules with >= MIN_HULL_MEMBERS in view — the DENOMINATOR the caption states
  var hullsDrawn = 0;            // ...and how many survived draw()'s two geometry tests and the cap
  var hullsThin = 0;             // ...dropped by the SHAPE test (see HULL_COMPACTNESS) — captioned separately,
  var hullsImpure = 0;           // ...and by the PURITY test (see HULL_PURITY): two reasons, two numbers
  var nodesInFrame = 0;          // nodes whose centre is inside the canvas rect — what a ZOOMED export shows,
  var provStamp = '';            // ...against the caption's loaded-subset totals (see draw()'s closing block)
  var MAX_HULLS = 12, MIN_HULL_MEMBERS = 3;
  var HULL_PAD_PX = 16;          // how far the outline stands off its outermost members, in SCREEN px
  // A convex hull only means "these belong together" if the group IS spatially together, and Louvain
  // communities are not always laid out that way: on this repository's own default map the three largest
  // are `size`/`find`/`empty` — name-based hubs whose members are scattered across the whole picture —
  // and their hulls came out as huge overlapping lenses covering most of the canvas. That is not
  // containment, it is a wash, and it made the picture WORSE than no outline at all.
  //
  // The test is PURITY, not size, because purity is what containment actually claims: an outline is
  // drawn only when most of what it encloses belongs to it. Measured over the hull's bounding box rather
  // than the hull itself — a point-in-polygon test per node per group is O(N x groups x vertices) every
  // frame and this is O(N x groups), which is what keeps it affordable at the 5000-node ceiling. The box
  // is the looser test of the two, so it errs toward drawing, never toward a silent drop.
  //
  // HULL_CANDIDATES bounds that cost from the other side: only the largest few groups are ever
  // considered, because they are the only ones whose outline tells a reader anything at this scale.
  var HULL_PURITY = 0.5, HULL_CANDIDATES = 24;
  // ...and the second test is SHAPE, because MIN_HULL_MEMBERS counts POINTS and a hull is a REGION.
  // Three members that happen to sit near a line pass a node count and produce a hull with almost no
  // area: it draws as a thin coloured streak across the picture and reads as a scratch on the lens, not
  // as containment. Three of them were visible on the django/db/migrations figure at rrf/top-k=120 —
  // `resolve_model_field_relations` (a 107x0 px line whose hull area is 4 px^2), `add_operation`
  // (178x8 px) and `reload_model` (137x13 px) — and the first of those was being dropped SILENTLY,
  // because a fully collinear group makes convexHull return a 2-point ring and the caller just skipped
  // it without counting it anywhere.
  //
  // The measure is the isoperimetric ratio 4*pi*A/P^2 of the RAW hull ring. The hull is convex by
  // construction, and on a convex ring that ratio is exactly thinness: 1.0 for a circle, 0.785 for a
  // square, 0.605 for an equilateral triangle — the roundest a three-member hull can be — and it falls
  // to pi/(2*aspect) for a thin one, which reproduces the three measurements above to three decimals.
  // Chosen over the two alternatives on their own terms. An AREA floor is the wrong predicate twice: it
  // is not scale-invariant, and it would drop a small ROUND module (`varint`, 23x18 px, perfectly
  // legible once HULL_PAD_PX has stood the outline off it) while the streaks it is aimed at are long
  // enough to survive one. An OBB aspect ratio measures the same thing but needs rotating calipers,
  // O(ring^2), where this is one O(ring) pass over vertices draw() already walks.
  //
  // 0.20 IS MEASURED, not picked. Over both corpora at the figure argv — 23 groups with 3+ members in
  // view — the ratios form a low cluster {0.0011, 0.0718, 0.1493} and a body from 0.2879 up, and the
  // two widest adjacent gaps in the entire distribution (2.08x and 1.93x) bracket exactly that band;
  // 0.20 is its geometric midpoint. In shape terms it is a triangle about 8:1 base-to-height. Measured
  // on the raw ring rather than the padded one drawn, so it is scale-invariant: HULL_PAD_PX is a screen
  // quantity, and testing the padded shape would make an outline appear and disappear as the reader
  // zooms — and the caption's count change with it.
  var HULL_COMPACTNESS = 0.20;
  var labelDegreeOrder = [];     // the same set as an ARRAY in descending importance, so the declutter in
                                 // draw() places the ones that matter first and drops the collisions
  var MAX_LABELS = 24;
  var MIN_LABEL_DEGREE = 2;      // rule 3: a node with one in-view edge is fringe and its name buys nothing
  // A node's on-screen radius band (see nodeRadiusPx). The FLOOR moved 3.0 -> 4.0 when kind became a
  // shape: shape is only a channel above roughly 8 px across, and a floor of 3.0 drew every zero-degree
  // node — which is every `sec` and every `var`, the two kinds that most need to be told apart from a
  // function — as a 6 px mark where a square, a bar and a circle are the same speck. 4.0 puts the
  // smallest mark at 8 px and leaves the ceiling alone, so the degree signal the band carries is
  // unchanged everywhere it was already visible.
  var MIN_NODE_PX = 4.0, MAX_NODE_PX = 15.0;
  var LABEL_HALO_PX = 3.0;       // the dark outline stroked behind every label (see placeLabel)
  var LABEL_CULL_PX = 2000;      // a label anchored further than this off-canvas is skipped (see placeLabel)
  var LABEL_H = 13;              // how tall a drawn label actually is — placeTextAt reserves rows with it
  var LABEL_GAP_PX = 3;          // placeLabel's gap between a node's edge and the first glyph of its name
  var LABEL_BASE_PX = 4;         // ...and how far BELOW the node centre that name's baseline sits
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
    // ...and seeded in the VIEWPORT'S OWN ASPECT, not a square. The spread used to be one number,
    // min(W,H)*0.7, so every layout started inside a square and — a force sim being a local optimiser
    // that mostly preserves the gross shape of its seed — settled to a roughly circular cloud. Measured
    // on the README hero at 1600x900: the settled graph used 86% of the canvas HEIGHT and 37% of its
    // WIDTH, so nearly half the picture was empty margin on a 16:9 frame. Seeding in the frame's own
    // proportions costs nothing (the physics is untouched, and the seeded LCG is still the same seeded
    // LCG) and fills it.
    var SPREAD_X = Math.max(W*0.7, 300), SPREAD_Y = Math.max(H*0.7, 300);
    for (var i = 0; i < ids.length; i++) {
      var gid = ids[i], src = NODES[gid];
      gidToLocal.set(gid, i);
      nodes.push({ gid: gid, label: src.label, type: src.type, lang: src.lang, rank: src.rank,
                   comm: src.comm, cx: src.cx, ts: src.ts, file: src.file,
                   x: W/2 + (rng()-0.5)*SPREAD_X, y: H/2 + (rng()-0.5)*SPREAD_Y, vx: 0, vy: 0 });
    }
    N = nodes.length;
    links = [];
    selfEdgesDropped = 0;
    ambEdges = 0;
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
      // C1: the per-edge SPLIT-ARM bit rides through into the sim record. NORMALISED to 0/1 here rather
      // than passed on as undefined-or-1, because two consumers compare against it — draw()'s pass
      // selector and the caption's count — and a record that never carried the key would otherwise make
      // each of them handle the absent case separately.
      var amb = edges[k].a ? 1 : 0;
      if (amb) { ambEdges++; }
      links.push({ s: s, t: t, a: amb });
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

    // ---- module HULLS: which groups get an outline.
    //
    // WHAT THIS REPLACES. Module identity was carried by hue alone, `commColor[comm % 12]` — twelve
    // colours over 26 modules on this repository's own default page, 31 on the README hero, and 299 and
    // 188 on two larger corpora. At --top-k=2000 that is 24-25 distinct modules sharing every hue, while
    // the legend printed "m0 ... m11" and said nothing about the collision, so two adjacent
    // same-coloured clusters read as one module and there was no way to tell from the picture that they
    // were not. Twelve categorical hues is roughly the ceiling for a colour channel and the module count
    // is unbounded, so no palette fixes this: CONTAINMENT is the only channel that can honestly express
    // 26-299 groups, and it is also the single largest "this hairball has structure" win available.
    //
    // The outline is independent of --color-by. It says WHICH MODULE; the fill inside still says
    // whatever lens the reader picked, so a `cx` view shows hot symbols AND the module boundaries they
    // sit inside instead of making the reader choose.
    //
    // A group needs MIN_HULL_MEMBERS points before a hull means anything (two points are a line), and at
    // most MAX_HULLS are drawn because 26 overlapping outlines is the hairball again in a second
    // channel. Both the cap and the total are handed to the caption — an undisclosed cap would be this
    // page implying it had drawn every module.
    hullGroups = [];
    hullsTotal = 0;
    if (typeof MODULES !== 'undefined' && MODULES.length) {
      var byComm = new Map();
      for (var hi = 0; hi < N; hi++) {
        var hc = nodes[hi].comm;
        if (hc < 0 || hc >= MODULES.length) { continue; }
        if (!byComm.has(hc)) { byComm.set(hc, []); }
        byComm.get(hc).push(hi);
      }
      var groups = [];
      byComm.forEach(function(idx, c) {
        if (idx.length >= MIN_HULL_MEMBERS) { groups.push({ comm: c, name: MODULES[c].name, idx: idx }); }
      });
      hullsTotal = groups.length;
      groups.sort(function(a,b){ return b.idx.length - a.idx.length || a.comm - b.comm; });
      hullGroups = groups.slice(0, HULL_CANDIDATES);   // draw() applies the purity test and the cap — both need geometry
    }

    ox = 0; oy = 0; scale = 1; autoFit = true;
    dragging = -1; panStart = null; hovered = -1; selected = -1; searchSet = null;
    SIM_STEPS = 0;
    info.textContent = '';
    if (N === 0) { paintBackdrop(); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); renderProv(); return; }
    settle();
    renderProv();
  }

  // frame everything the page DRAWS into the viewport. Called each settling frame (while autoFit) so the
  // graph is visible no matter how far the force sim spreads it; the user taking control stops it.
  //
  // It used to fit the bounding box of node CENTRES against a flat 70 px pad, and that is not the same
  // set as what lands on the canvas. A node is a disc of up to MAX_NODE_PX, and a labelled node also
  // carries its name to the RIGHT, in screen-constant 11 px text — `generate_deleted_fields` is 130 px
  // of glyphs that the centre-box knows nothing about. The flat pad absorbed the discs and roughly one
  // short name, so the defect only appears when a wide label happens to sit on the right edge: the
  // README's own lens figure shipped with a name sliced in half by the frame. Worse, it is not fixable
  // downstream — the frame is what the stated command produces, so a hand-panned screenshot would be a
  // picture the README's own reproduction line does not make.
  //
  // Reserve the drawn EXTENT per node instead, and solve for the largest scale that fits all of them.
  // The extents are screen-constant (radii and label metrics are both in screen px, deliberately — see
  // placeTextAt), so they do not move as `scale` does, which is what makes the solve exact rather than
  // iterative-until-it-looks-right: for a given s, node i occupies [x_i*s + ox - Lft_i, x_i*s + ox +
  // Rgt_i], so the admissible ox is an interval, feasibility is that interval being non-empty, and
  // feasibility is monotone in s. Binary-search s, then take the interval's midpoint, which centres the
  // drawn content — not the centres — in the frame.
  //
  // Hull NAMES are not reserved: their anchors are computed in screen space during the hull pass, which
  // needs the camera this function is choosing. The right margin a labelled node reserves absorbs most
  // of that, and a clipped hull name is one word of a region title rather than a symbol's identity.
  // The frame's own breathing room, on top of every reserved box — a FRACTION of the shorter side, not a
  // pixel count, so a thumbnail and a full-width figure get the same visual air rather than the same
  // number of pixels. A fixed pad reads as generous at 430 px and as a hairline at 1600. Floored so a
  // very small canvas still gets a margin at all; the graph is meant to sit IN the frame, not against it.
  var FIT_PAD_FRAC = 0.13, FIT_PAD_MIN_PX = 18;
  function fitPad() { return Math.max(FIT_PAD_MIN_PX, FIT_PAD_FRAC*Math.min(W, H)); }
  function fitView() {
    if (!N) return;
    ctx.font = '11px sans-serif';                       // placeLabel's font — measure what IT will draw
    var lft = new Float64Array(N), rgt = new Float64Array(N);
    var top = new Float64Array(N), bot = new Float64Array(N);
    for (var i = 0; i < N; i++) {
      var rp = nodeRadiusPx(nodes[i]);
      lft[i] = rp; rgt[i] = rp; top[i] = rp; bot[i] = rp;
    }
    for (var li = 0; li < labelDegreeOrder.length; li++) {
      // The declutter grid may still drop some of these; reserving for a label that is then skipped only
      // zooms out a hair, while NOT reserving for one that is drawn slices it. Over-reserve, deliberately.
      var k = labelDegreeOrder[li], rpk = nodeRadiusPx(nodes[k]);
      rgt[k] = Math.max(rgt[k], rpk + LABEL_GAP_PX + ctx.measureText(nodes[k].label).width);
      top[k] = Math.max(top[k], LABEL_H - LABEL_BASE_PX);
      bot[k] = Math.max(bot[k], LABEL_BASE_PX + 2);
    }

    // The admissible offset interval on one axis at scale s, or null when no offset fits every box.
    function offsetRange(s, pad, axisY, extent) {
      var lo = -Infinity, hi = Infinity;
      for (var i = 0; i < N; i++) {
        var q = ( axisY ? nodes[i].y : nodes[i].x ) * s;
        var before = axisY ? top[i] : lft[i], after = axisY ? bot[i] : rgt[i];
        var l = pad + before - q;                      if ( l > lo ) { lo = l; }
        var h = extent - pad - after - q;              if ( h < hi ) { hi = h; }
      }
      return lo <= hi ? [lo, hi] : null;
    }

    // PADDING IS A PREFERENCE; CONTAINMENT IS THE PROPERTY. On a narrow canvas one long name can be most
    // of the width — `_get_altered_foo_together_operations` measures ~200 px against a 430 px figure — so
    // the proportional pad plus that label can be wider than the frame, at which point NO scale fits and
    // the graph would fall back to the old clipping fit. Give the pad up before giving up containment:
    // halve it until a fit exists. The generous margin survives wherever there is room for it, which is
    // every full-width figure, and a cramped thumbnail loses air rather than losing a symbol's name.
    var pad = fitPad();
    while (pad > 0.5 && !(offsetRange(0.05, pad, false, W) && offsetRange(0.05, pad, true, H))) { pad /= 2; }
    if (pad <= 0.5) { pad = 0; }
    function fits(s) { return offsetRange(s, pad, false, W) !== null && offsetRange(s, pad, true, H) !== null; }

    var loS = 0.05, hiS = 2.0;
    if (!fits(loS)) {
      // Even the floor cannot hold the drawn boxes (a canvas smaller than one label, say). Fall back to
      // the centre-box fit rather than emitting a NaN camera, and let the picture overflow visibly.
      var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (var j = 0; j < N; j++) {
        var n = nodes[j];
        if (n.x < minX) minX = n.x;  if (n.x > maxX) maxX = n.x;
        if (n.y < minY) minY = n.y;  if (n.y > maxY) maxY = n.y;
      }
      scale = loS;
      ox = (W - scale*(minX+maxX))/2;
      oy = (H - scale*(minY+maxY))/2;
      return;
    }
    if (!fits(hiS)) {
      for (var it = 0; it < 24; it++) {                 // 2.0 halved 24 times resolves scale to ~1e-7
        var mid = (loS + hiS)/2;
        if (fits(mid)) { loS = mid; } else { hiS = mid; }
      }
    } else {
      loS = hiS;                                       // a tiny graph: the 2.0 ceiling is the binding limit
    }
    scale = loS;
    var rx = offsetRange(scale, pad, false, W), ry = offsetRange(scale, pad, true, H);
    ox = (rx[0] + rx[1])/2;                            // centre the DRAWN content, not the centres
    oy = (ry[0] + ry[1])/2;
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

    // repulsion O(n²) — the hottest loop on the page. Node i's position and its two force accumulators
    // are invariant in j and are lifted out of the inner loop. The accumulators are the load-bearing
    // half: N-1 typed-array read-modify-writes per i collapse to one read and one write.
    //
    // Lifting ax[i] is SAFE for a reason worth stating, because it looks like it should not be. ax[i] is
    // also written by EARLIER outer iterations, as ax[j] with j == i — but every i' < i has finished
    // before iteration i begins, and iteration i writes only ax[j] for j > i. So the addition ORDER is
    // unchanged, and a Float64Array element is a double either way: the result is bit-identical, verified
    // by running the emitted page's own script with and without these hoists and comparing every drawn
    // node centre (equal step counts in both arms — settle() stops on budget OR MAX_SIM, and the faster
    // arm otherwise simply gets further, which reads as a difference and is not one).
    //
    // Bit-identity is the bar rather than "close enough" because this layout is chaotic: one ulp of
    // difference is two different pictures 300 steps later, and the label rule in loadSubset and the
    // radius rule in nodeRadiusPx were both calibrated on specific settled pictures. A rewrite that
    // REORDERS these sums is not free even when it is faster — see the integrate loop below.
    //
    // WHY THIS STAYS O(n²). Barnes-Hut was implemented and measured against this loop, and declined.
    // The tempting summary — "BH is 3-8x faster but still misses SETTLE_BUDGET_MS at n=5000" — is
    // circular, because that budget is a constant in this file chosen for how long a page may block
    // before painting, not a yardstick for an algorithm. Measured in the unit that means something,
    // median node displacement from that arm's OWN settled layout at first paint (n=5000), the exact
    // loop lands 6.3% of the graph's span from settled and BH 0.3%: BH genuinely wins at the ceiling,
    // and this is a trade rather than a rout. It is declined because the benefit is confined to the
    // --top-k=5000 ceiling while the cost is paid at every n — BH is an APPROXIMATION, so it perturbs
    // every layout including the default 200-node picture the label and radius rules were calibrated
    // on, and it puts ~120 lines of quadtree into a page whose value is being self-contained and
    // auditable. The hoists directly above bought 57 -> 141 steps at that same ceiling (2.45x) for no
    // layout change at all, which is the cheaper half of the same win. If the whole-map view at 5000
    // nodes ever becomes the common case rather than a reachable one, BH is the right next step and
    // these are the numbers to start from. Step counts are wall-clock and machine-dependent; the
    // ratios and the bit-identity are not.
    for (var i = 0; i < N; i++) {
      var ni = nodes[i], nix = ni.x, niy = ni.y, axi = ax[i], ayi = ay[i];
      for (var j = i+1; j < N; j++) {
        var nj = nodes[j];
        var dx = nix - nj.x, dy = niy - nj.y;
        var d2 = dx*dx + dy*dy + 1;
        var f = repulse / d2;
        var fx = f*dx, fy = f*dy;
        axi += fx; ayi += fy;
        ax[j] -= fx; ay[j] -= fy;
      }
      ax[i] = axi; ay[i] = ayi;
    }
    // spring along links — links[k], nodes[s] and nodes[t] were each loaded twice per edge
    for (var k = 0; k < L; k++) {
      var lk = links[k], s = lk.s, t = lk.t, ns = nodes[s], nt = nodes[t];
      var dx = nt.x - ns.x, dy = nt.y - ns.y;
      var d = Math.sqrt(dx*dx+dy*dy)+0.001;
      var f = spring*(d-rest)/d;
      var gx = f*dx, gy = f*dy;
      ax[s] += gx; ay[s] += gy;
      ax[t] -= gx; ay[t] -= gy;
    }
    // Gravity to centre, in the VIEWPORT'S OWN PROPORTIONS. An isotropic pull produces a circular
    // cloud, and this page is drawn on a 16:9 canvas: measured on the README hero at 1600x900, the
    // settled graph used 86% of the height and 37% of the width, so the flagship picture was almost half
    // empty margin. Seeding in the frame's aspect (loadSubset) starts it right and an isotropic well
    // pulls it back round over 300 steps, so the well is elliptical too — the pull is weaker along the
    // long axis. The RATIO is the calibration and it was measured, not derived: at gravY/gravX = (W/H)^2
    // the settled cloud came out at aspect 3.6 in a 1.98 frame, i.e. the cloud's aspect tracks the
    // gravity ratio almost linearly rather than as the g^(-1/3) a linear-force-against-1/r^2 argument
    // predicts (the springs dominate). So the ratio is set to the FRAME's aspect, which lands the cloud
    // just inside it and leaves a margin instead of stretching the picture flat.
    //
    // WHAT IT COSTS, stated because it is a real cost. A force layout's one claim is "near means
    // related", and it is rotation-invariant: an anisotropic well makes "near" mildly direction-
    // dependent, so a horizontal gap and a vertical gap of the same pixel length no longer mean quite
    // the same thing. The exponent keeps that mild at the aspects a browser window actually has, and it
    // is the deliberate trade for a picture that uses the frame it is drawn in.
    var wellA = Math.sqrt(Math.max(0.4, Math.min(2.5, (W > 0 && H > 0) ? W/H : 1)));
    var gravX = gravity/wellA, gravY = gravity*wellA;
    for (var i = 0; i < N; i++) {
      var ng = nodes[i];
      ax[i] += gravX*(cx-ng.x);
      ay[i] += gravY*(cy-ng.y);
    }
    // integrate, with the per-tick displacement capped at MAX_STEP (see its declaration for the
    // exponential divergence this bounds, and the frozen tab that divergence produced)
    // nodes[i] was loaded four times per node. The reciprocal in the clamp is deliberately left ALONE:
    // q = MAX_STEP/sp then vx *= q is one division instead of two, but a*(b/c) and a*b/c differ by an
    // ulp, so unlike the three hoists above it is not value-preserving. It is already the shipped
    // behaviour and it binds on a fraction of a percent of integrations, so this is a note and not a
    // change — only that the two are different KINDS of edit, and the difference is the reason the
    // hoists above could be verified bit-identical and this one could not be.
    for (var i = 0; i < N; i++) {
      if (i === dragging) continue;
      var nv = nodes[i];
      var vx = (nv.vx + ax[i])*dampen, vy = (nv.vy + ay[i])*dampen;
      var sp = Math.sqrt(vx*vx + vy*vy);
      if (sp > MAX_STEP) { var q = MAX_STEP/sp; vx *= q; vy *= q; }
      nv.vx = vx; nv.vy = vy;
      nv.x += vx;  nv.y += vy;
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

// SECTION 3 of the renderer: the VOCABULARY OF A MARK — how big a node is, what shape it is, and the
// geometry a module outline is made of. Pure functions of their arguments: nothing here reads the camera,
// touches canvas state, or paints. Section 3b is what uses them.
//
// This is the third split, made for the reason the first two were and reported by the same instrument:
// --quality-delta measured section 3 growing 191 -> 393 lines as the shape, hull and confidence channels
// landed in it, which is the metric working as intended rather than a number to dodge. The seam is where
// a reader would put one — "what a mark IS" and "how a frame is painted" are two things, and the first
// half has no dependency on the second at all. The translation unit is unchanged: adjacent literals are
// emitted back to back, in order, into one <script>.
static const char kScriptMarks[] = R"JS(
  // ---- node SIZE. Radius reads IN-VIEW DEGREE, with rank as a tiebreak. The old `4 + 60*sqrt(rank)`
  // spanned 4.60-11.78 px with a MEAN of 5.10 on the README cut — every node a ~5 px dot — while in-view
  // degree over the same nodes spanned 1 to 111. The picture carried a hub/leaf distinction it never
  // drew, so a hairball was the honest rendering of it. sqrt keeps the growth sub-linear so a degree-111
  // hub is ~4x a degree-2 leaf and not 55x; the small rank term separates equal-degree nodes without ever
  // reordering different-degree ones.
  function nodeRadiusPx(n) { return Math.max(MIN_NODE_PX, Math.min(MAX_NODE_PX, 3 + 1.5*Math.sqrt(n.deg || 0) + 5*Math.sqrt(n.rank))); }

  // ---- node SHAPE, one table, two readers.
  //
  // SYM_SHAPES (emitted above — htmlexport.h::kSymShapes, one entry per model.h SymKind enumerator,
  // static_asserted against the roster) maps the `type` string every NODES record already carries to a
  // key of this object; each entry carries BOTH the canvas path that draws the mark and the glyph the
  // caption's shape key prints for it, so the picture and its own legend cannot describe different
  // shapes. `type` was in the payload from the beginning and reached nothing but a hover tooltip.
  //
  // Every path is written in terms of one radius `r` and normalised to the SAME AREA as a circle of that
  // radius, so shape says kind and only size says degree. Without that a square would read as a bigger
  // node than a circle at identical degree — a second variable smuggled into a nominal channel:
  //   square   half-side  0.89r   (4q^2      = pi r^2)
  //   diamond  half-diag  1.25r   (2d^2      = pi r^2)
  //   triangle circumrad  1.55r   (1.299R^2  = pi r^2)
  //   bar      1.48r x 0.53r      (4wh       = pi r^2, at 2.8:1 so it reads as a rule and not a box)
  //   plus/cross  arm half-thickness 0.40r, half-length 1.18r   (8ab - 4a^2 = pi r^2)
  var PLUS_PTS = [[-0.40,-1.18],[0.40,-1.18],[0.40,-0.40],[1.18,-0.40],[1.18,0.40],[0.40,0.40],
                  [0.40,1.18],[-0.40,1.18],[-0.40,0.40],[-1.18,0.40],[-1.18,-0.40],[-0.40,-0.40]];
  function plusPath(p, x, y, r, rot) {
    for (var pi = 0; pi < 12; pi++) {
      var dx = PLUS_PTS[pi][0]*r, dy = PLUS_PTS[pi][1]*r;
      if (rot) { var tq = (dx - dy)*0.70710678; dy = (dx + dy)*0.70710678; dx = tq; }
      if (pi) { p.lineTo(x + dx, y + dy); } else { p.moveTo(x + dx, y + dy); }
    }
    p.closePath();
  }
  var SHAPES = {
    circle:   { glyph: '●', reach: 1.00, path: function(p,x,y,r){ p.moveTo(x+r, y); p.arc(x, y, r, 0, 2*Math.PI); } },
    diamond:  { glyph: '◆', reach: 1.25, path: function(p,x,y,r){ var q = r*1.25; p.moveTo(x, y-q); p.lineTo(x+q, y); p.lineTo(x, y+q); p.lineTo(x-q, y); p.closePath(); } },
    square:   { glyph: '■', reach: 1.26, path: function(p,x,y,r){ var q = r*0.89; p.moveTo(x-q, y-q); p.lineTo(x+q, y-q); p.lineTo(x+q, y+q); p.lineTo(x-q, y+q); p.closePath(); } },
    triangle: { glyph: '▲', reach: 1.55, path: function(p,x,y,r){ var q = r*1.55; p.moveTo(x, y-q); p.lineTo(x + q*0.866, y + q*0.5); p.lineTo(x - q*0.866, y + q*0.5); p.closePath(); } },
    bar:      { glyph: '▬', reach: 1.57, path: function(p,x,y,r){ var w = r*1.48, h = r*0.53; p.moveTo(x-w, y-h); p.lineTo(x+w, y-h); p.lineTo(x+w, y+h); p.lineTo(x-w, y+h); p.closePath(); } },
    plus:     { glyph: '✚', reach: 1.25, path: function(p,x,y,r){ plusPath(p, x, y, r, 0); } },
    cross:    { glyph: '✖', reach: 1.25, path: function(p,x,y,r){ plusPath(p, x, y, r, 1); } }
  };
  // A node's mark. The `|| SHAPES.circle` is a rendering guard, not a policy: kSymShapes is
  // static_asserted to cover every SymKind, so it can only fire on a page whose payload predates a new
  // enumerator — and the caption's key is built from the same lookup, so such a page would say so.
  function shapeFor(n) { return SHAPES[SYM_SHAPES[n.type]] || SHAPES.circle; }

  // ---- module hull geometry.
  //
  // Monotone-chain convex hull over [{x,y}] — O(n log n), and free beside the O(n^2) force sim that
  // placed the points in the first place. Returns the hull ring; fewer than three non-collinear points
  // has no hull, and the caller skips those groups rather than drawing a line and calling it a region.
  function convexHull(pts) {
    if (pts.length < 3) { return []; }
    var p = pts.slice().sort(function(a,b){ return a.x - b.x || a.y - b.y; });
    function cross(o,a,b){ return (a.x-o.x)*(b.y-o.y) - (a.y-o.y)*(b.x-o.x); }
    var lo = [], up = [], i;
    for (i = 0; i < p.length; i++) {
      while (lo.length >= 2 && cross(lo[lo.length-2], lo[lo.length-1], p[i]) <= 0) { lo.pop(); }
      lo.push(p[i]);
    }
    for (i = p.length - 1; i >= 0; i--) {
      while (up.length >= 2 && cross(up[up.length-2], up[up.length-1], p[i]) <= 0) { up.pop(); }
      up.push(p[i]);
    }
    lo.pop(); up.pop();
    return lo.concat(up);
  }
  // '#rrggbb' + alpha -> 'rgba(r,g,b,a)'. The palettes are hex because that is the form a CSS legend
  // swatch needs; a translucent canvas fill needs the channels.
  function hexRgba(hex, a) {
    var v = parseInt(hex.slice(1), 16);
    return 'rgba(' + ((v >> 16) & 255) + ',' + ((v >> 8) & 255) + ',' + (v & 255) + ',' + a + ')';
  }

  // -- end of section 3a --
)JS";

// SECTION 3b of the renderer: the FRAME — the backdrop, draw() and its label declutter, and the hit test
// that has to agree with what was drawn. Everything here reads the camera and paints; the marks it paints
// come from section 3a above. Same split rationale as that section's header states.
static const char kScriptDraw[] = R"JS(
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

    // ---- module HULLS, behind everything. Containment is the channel; see loadSubset's hull block for
    // the 12-hues-over-26-modules collision it replaces and why no palette could have fixed it. The hue
    // is what is LEFT after containment took the job, so it comes from hullColor — a deliberately quiet
    // band measured against rampColor rather than the community lens' twelve saturated hues, which put
    // decoration on the two axes the metric uses. See hullColor's note for the numbers.
    //
    // Each outline is pushed HULL_PAD_PX (a screen quantity, converted here like every other one on this
    // canvas) outward from the group's centroid so it clears its own members instead of threading
    // through them, and it is drawn as a rounded blob — quadratic curves through the edge midpoints,
    // one pass over the same vertices — because a hard polygon reads as a diagram of a region and a
    // rounded one reads as the region. The fill is deliberately faint: the outline is a second channel
    // sitting UNDER whatever --color-by the reader chose, and a hull that competes with the node colours
    // has taken the lens away from them.
    var hullAnchors = [];
    hullsDrawn = 0; hullsThin = 0; hullsImpure = 0;
    for (var gi = 0; gi < hullGroups.length; gi++) {
      var grp = hullGroups[gi], gpts = [], mi;
      for (mi = 0; mi < grp.idx.length; mi++) { gpts.push({ x: nodes[grp.idx[mi]].x, y: nodes[grp.idx[mi]].y }); }
      var ring = convexHull(gpts);
      // THE SHAPE TEST — see HULL_COMPACTNESS for the three streaks that made it necessary and for why
      // 0.20. It runs FIRST because it is one O(ring) pass and the purity test below is O(N): a group
      // that cannot be a region at all never costs a walk over every node in view. A ring of fewer than
      // three points is the extreme case of the same defect — a fully collinear group, whose hull has no
      // area whatsoever — and it lands in the same counted branch, where it used to be skipped silently.
      var hullArea = 0, hullPerim = 0, hk;
      for (hk = 0; hk < ring.length; hk++) {
        var rb = ring[(hk + 1) % ring.length], rdx = rb.x - ring[hk].x, rdy = rb.y - ring[hk].y;
        hullArea  += ring[hk].x*rb.y - rb.x*ring[hk].y;
        hullPerim += Math.sqrt(rdx*rdx + rdy*rdy);
      }
      hullArea = Math.abs(hullArea)/2;
      if (ring.length < 3 || !(hullPerim > 0) || 4*Math.PI*hullArea/(hullPerim*hullPerim) < HULL_COMPACTNESS) { hullsThin++; continue; }
      if (hullsDrawn >= MAX_HULLS) { continue; }
      var gcx = 0, gcy = 0, hj;
      for (hj = 0; hj < ring.length; hj++) { gcx += ring[hj].x; gcy += ring[hj].y; }
      gcx /= ring.length; gcy /= ring.length;
      var padw = HULL_PAD_PX/scale, ex = [], topY = Infinity, topX = 0;
      for (hj = 0; hj < ring.length; hj++) {
        var vx = ring[hj].x - gcx, vy = ring[hj].y - gcy, vd = Math.sqrt(vx*vx + vy*vy) || 1;
        var pxw = ring[hj].x + vx/vd*padw, pyw = ring[hj].y + vy/vd*padw;
        ex.push({ x: pxw, y: pyw });
        if (pyw < topY) { topY = pyw; topX = pxw; }
      }
      // THE PURITY TEST — see HULL_PURITY for the three lenses that made it necessary. If most of what
      // this outline would enclose is NOT this module, the outline is not saying "these belong
      // together", it is saying nothing over the top of everything else.
      var bx0 = Infinity, by0 = Infinity, bx1 = -Infinity, by1 = -Infinity;
      for (hj = 0; hj < ex.length; hj++) {
        if (ex[hj].x < bx0) bx0 = ex[hj].x;  if (ex[hj].x > bx1) bx1 = ex[hj].x;
        if (ex[hj].y < by0) by0 = ex[hj].y;  if (ex[hj].y > by1) by1 = ex[hj].y;
      }
      var inside = 0;
      for (var qi = 0; qi < N; qi++) {
        var qn = nodes[qi];
        if (qn.x >= bx0 && qn.x <= bx1 && qn.y >= by0 && qn.y <= by1) { inside++; }
      }
      if (inside > 0 && grp.idx.length/inside < HULL_PURITY) { hullsImpure++; continue; }
      hullsDrawn++;
      ctx.beginPath();
      ctx.moveTo((ex[ex.length-1].x + ex[0].x)/2, (ex[ex.length-1].y + ex[0].y)/2);
      for (hj = 0; hj < ex.length; hj++) {
        var nxt = ex[(hj + 1) % ex.length];
        ctx.quadraticCurveTo(ex[hj].x, ex[hj].y, (ex[hj].x + nxt.x)/2, (ex[hj].y + nxt.y)/2);
      }
      ctx.closePath();
      var hcol = hullColor[grp.comm % 12];
      ctx.fillStyle = hexRgba(hcol, 0.085);
      ctx.fill();
      ctx.strokeStyle = hexRgba(hcol, 0.42);
      ctx.lineWidth = 1.4/scale;
      ctx.stroke();
      // The name is a module's TOP-RANKED MEMBER (MODULES[].name — the same string the overview card
      // uses), so on a repository whose hubs are container primitives it can read as an ordinary symbol
      // name, and the picture already has a node labelled exactly that a few pixels away. The member
      // count is what makes the two legible as different KINDS of thing — "clone ·9" is a group of
      // nine, "clone" is a symbol — and it is the number a reader wants from a region anyway.
      hullAnchors.push({ sx: topX*scale + ox, sy: topY*scale + oy - 6,
                         text: grp.name + ' ·' + grp.idx.length, color: hcol });
    }

    // ---- edges, WITH THEIR DIRECTION DRAWN.
    //
    // LINKS is a directed call graph and this loop used to render it as `moveTo(source) lineTo(target)`
    // with nothing at either end, so a picture of a call graph could not answer "which of these two
    // calls the other" — the single most basic question the graph exists to answer. It is a near-free
    // thing to draw here because the direction is near-unambiguous in the data: mutual pairs are 1 of
    // 243 on the default page, 5 of 4721 at --top-k=2000, 0 of 646 on another corpus, and self-calls
    // (which loadSubset drops and the caption counts) are 0 everywhere. A head is therefore a true
    // statement about 99.6-100% of the edges it is drawn on.
    //
    // THE HEAD IS A SCREEN QUANTITY, converted to world units here — the same rule node radii and label
    // glyphs already follow, and for the same reason: the page auto-fits a settled map at scale ~0.10 to
    // ~0.15, where a world-space head sized to look right at 1:1 is a third of a pixel and simply is not
    // there. The tip is backed off the target's own radius so it points AT the node instead of being
    // buried under it, and an edge whose VISIBLE shaft is shorter than MIN_ARROW_SHAFT_PX gets no head
    // at all: on a dense cluster those are all head and no line, which reads as noise and costs a fill
    // per edge to draw.
    //
    // Both passes are ONE path each rather than a beginPath/stroke per edge. Same pixels, and it is what
    // makes a second pass over up to 13819 edges affordable at all.
    // A SPLIT-ARM SHAFT IS DASHED. `a` is the per-edge bit writeHtml reads straight off Graph::outProv
    // (3 = one arm of a k-way split the resolver could not choose between — the same fact the XML map
    // spells prov="split"), so the picture and the data say the same thing about the same edge. It is
    // drawn as a different KIND of line and not as a shade, because a faded solid line is
    // indistinguishable from a distant one and a dashed line is not. Two passes because a dash pattern
    // is canvas STATE and cannot vary inside one path; the alternative is a beginPath/stroke per edge,
    // which is what this loop was before and what makes 13819 edges unaffordable. The pass order is
    // fixed, so the picture is stable.
    var ARROW_LEN_PX = 7.0, ARROW_HALF_PX = 3.2, MIN_ARROW_SHAFT_PX = 13.0;
    var DASH_ON_PX = 4.0, DASH_OFF_PX = 3.5;
    ctx.strokeStyle = '#8a8f98';
    ctx.lineWidth = 0.8/scale;
    ctx.globalAlpha = 0.26;
    for (var pass = 0; pass < 2; pass++) {
      ctx.setLineDash(pass ? [DASH_ON_PX/scale, DASH_OFF_PX/scale] : []);
      ctx.beginPath();
      for (var k = 0; k < L; k++) {
        var s = links[k].s, t = links[k].t;
        if (hl && !hl.has(s) && !hl.has(t)) continue;
        if ((links[k].a === 1) !== (pass === 1)) continue;
        ctx.moveTo(nodes[s].x, nodes[s].y);
        ctx.lineTo(nodes[t].x, nodes[t].y);
      }
      ctx.stroke();
    }
    ctx.setLineDash([]);
    var alen = ARROW_LEN_PX/scale, ahalf = ARROW_HALF_PX/scale;
    ctx.fillStyle = '#c3c9d2';
    ctx.globalAlpha = 0.62;
    ctx.beginPath();
    for (var k2 = 0; k2 < L; k2++) {
      var s2 = links[k2].s, t2 = links[k2].t;
      if (hl && !hl.has(s2) && !hl.has(t2)) continue;
      var a = nodes[s2], b = nodes[t2];
      var dx = b.x - a.x, dy = b.y - a.y;
      var d = Math.sqrt(dx*dx + dy*dy);
      if (!(d > 0)) continue;
      var rs = nodeRadiusPx(a)/scale, rt = nodeRadiusPx(b)/scale;
      if ((d - rs - rt)*scale < MIN_ARROW_SHAFT_PX) continue;
      var ux = dx/d, uy = dy/d;
      var tipX = b.x - ux*rt, tipY = b.y - uy*rt;
      var baseX = tipX - ux*alen, baseY = tipY - uy*alen;
      ctx.moveTo(tipX, tipY);
      ctx.lineTo(baseX - uy*ahalf, baseY + ux*ahalf);
      ctx.lineTo(baseX + uy*ahalf, baseY - ux*ahalf);
      ctx.closePath();
    }
    ctx.fill();
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
      shapeFor(n).path(ctx, n.x, n.y, r);
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
    var CELL_W = 8, CELL_H = 16;                          // LABEL_H is hoisted — fitView reserves with the same number
    // placeTextAt is the whole placement rule — cull, reserve, halo, draw — with no idea what the text
    // is FOR. It was placeLabel(i) and nothing else until the hulls needed names too; a second copy for
    // hull labels would have been a second occupancy grid's worth of behaviour that could disagree with
    // this one about what overlaps what, which is precisely the overprinting this grid exists to stop.
    function placeTextAt(text, sx, sy, fill, alpha) {
      var wpx = ctx.measureText(text).width;                // screen px directly — the font is screen px now
      // Text anchored well off the canvas is not drawn — and this is a GUARD, not an optimisation.
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
      ctx.globalAlpha = alpha;
      // A HALO first. The occupancy grid stops labels colliding with each OTHER; it says nothing about
      // what is underneath them, and in a dense view a name lands on top of a node disc — #d6d9de on a
      // bright teal is barely readable, which is the same lost label by a different route. Stroking the
      // glyphs in the canvas background before filling them makes every label legible over anything.
      ctx.lineJoin = 'round';
      ctx.lineWidth = LABEL_HALO_PX;
      ctx.strokeStyle = 'rgba(10,10,10,0.9)';
      ctx.strokeText(text, sx, sy);
      ctx.fillStyle = fill;
      ctx.fillText(text, sx, sy);
      return true;
    }
    function placeLabel(i) {
      var n = nodes[i], rpx = nodeRadiusPx(n);              // rpx is already a SCREEN radius
      return placeTextAt(n.label, n.x*scale + ox + rpx + LABEL_GAP_PX, n.y*scale + oy + LABEL_BASE_PX,
                         '#e6e9ee', (hl && !hl.has(i)) ? 0.25 : 0.95);
    }
    // Hull names go in FIRST, through the same grid: a region's name outranks any single symbol's,
    // because it is the only thing on the canvas that says what a whole cluster IS. Drawn in the hull's
    // own colour so the name and the outline are visibly the same object.
    ctx.font = '600 12px sans-serif';
    for (var ha = 0; ha < hullAnchors.length; ha++) {
      placeTextAt(hullAnchors[ha].text, hullAnchors[ha].sx, hullAnchors[ha].sy, hullAnchors[ha].color, 0.95);
    }
    ctx.font = '11px sans-serif';
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

    // ---- WHAT THIS FRAME ACTUALLY CONTAINS, and re-caption if it moved.
    //
    // The caption's node and edge counts are the LOADED subset. The camera is free to sit anywhere
    // inside it, and a picture exported after a zoom therefore stamped "120 nodes / 183 edges" across a
    // frame holding fifteen — a bitmap overstating its own contents, in the one artifact the caption
    // exists to travel in. (Found cutting the README's crop figures.) The count is of NODE CENTRES
    // inside the canvas rect: a mark half off the edge is in frame, and counting it is the reading that
    // errs toward the larger number rather than toward flattering the crop.
    //
    // The re-render is guarded on a CHANGE because the numbers renderProv states — this count and the
    // three hull counts — are all computed here, one frame after the caption that reports them. On a
    // settled page that is invisible; on an export taken straight after a zoom it is the previous view's
    // numbers stamped onto the new one. Rebuilding the caption unconditionally would put an innerHTML
    // write inside the settle loop at sixty frames a second, so it happens only when a stated number
    // actually moved.
    nodesInFrame = 0;
    for (var fi = 0; fi < N; fi++) {
      var fsx = nodes[fi].x*scale + ox, fsy = nodes[fi].y*scale + oy;
      if (fsx >= 0 && fsx <= W && fsy >= 0 && fsy <= H) { nodesInFrame++; }
    }
    var provNow = nodesInFrame + ':' + hullsDrawn + ':' + hullsThin + ':' + hullsImpure;
    if (provNow !== provStamp) { provStamp = provNow; renderProv(); }
  }

  // FILES[n.file] — the path, or an honest blank when the payload has no entry for it. FILES was emitted
  // and never read anywhere in this script (2241 bytes of dead payload on this repository's own map).
  function fileOf(n) { return (FILES && n.file < FILES.length) ? FILES[n.file] : ''; }

  // canvas → world coords
  function toWorldXY(px, py) { return { x: (px-ox)/scale, y: (py-oy)/scale }; }
  function hitTest(px, py) {
    var w = toWorldXY(px, py);
    for (var i = N-1; i >= 0; i--) {
      // The DRAWN size, so a click matches what the eye aimed at — and since a mark is no longer always
      // a circle, that size is the shape's own REACH (its farthest point from centre, the one number the
      // SHAPES table has to carry for this) and not the nominal radius. A flat 1.2x was right while
      // everything was a disc and under-covered a triangle (1.55) and a bar (1.57) the moment it wasn't.
      var n = nodes[i], r = nodeRadiusPx(n)*shapeFor(n).reach*1.15/scale;
      var dx = w.x-n.x, dy = w.y-n.y;
      if (dx*dx+dy*dy <= r*r) return i;
    }
    return -1;
  }

  // -- end of section 3b --
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

  // ---- the caption, in TWO HALVES, because they answer different questions and travel to different
  // places.
  //
  // FACTS is what this picture IS: the root it was built from, the ranker whose scores set the sizes,
  // the top-k that bounded the selection and what fraction of the repository that is, the counts in the
  // current view, the colour metric, and any state that makes the picture provisional. This tool states
  // every truncation it makes in its XML header and the page used to state nothing at all about itself —
  // a screenshot could not be audited, which is exactly the disclosure the rest of the tool is for.
  //
  // METHOD is how to READ it: which way an arrow points, what a dashed shaft means and at what
  // threshold, which nodes got labels, what each mark shape is, and how many module outlines were drawn
  // of how many — with each truncation's own count and its own reason.
  //
  // WHY THEY SPLIT. Both halves used to be one block and stampProvenance burned all of it into the
  // exported bitmap, which had reached three dense lines. A figure in a README gets three to five
  // seconds, and the stamp font is FITTED to the bitmap width against an 8 px readability floor
  // (stampProvenance), so every methodology clause added to it made the provenance it exists to carry
  // physically smaller. Method is what a caption UNDERNEATH a figure says once, in prose; provenance is
  // what has to survive the picture being lifted out of the page it came from. So the bitmap carries
  // FACTS, and the export writes METHOD beside it as a .txt (see sidecarText) — where a README author
  // can lift the wording verbatim rather than paraphrase it.
  //
  // Non-negotiable #3 is why the last FACTS line exists at all: it names the companion file AND every
  // channel whose rule moved into it. A trimmed bitmap that said nothing about the trim would be a
  // picture drawing arrowheads, dashes, shapes and outlines with no way to read any of them — the quiet
  // omission this whole block was added to prevent, re-introduced by the fix for it.
  function renderProv() {
    var el = document.getElementById('prov');
    if (!el) return;
    function k(t) { return '<span class="k">' + t + '</span> '; }
    var metric = { lang: 'language', community: 'module (community)', cx: 'cyclomatic complexity',
                   churn: 'commits (' + (CHURN_WINDOW || 'window not recorded') + ')', tested: 'has a test' }[mode] || mode;
    var pct = SYM_TOTAL ? Math.round(1000*NODE_TOTAL/SYM_TOTAL)/10 : 0;
    var viewName = currentView === 'overview' ? MODULES.length + ' modules'
                 : currentView === 'graph'    ? 'whole map'
                 : currentView === 'module'   ? 'module subgraph'
                 : 'depth-' + egoDepth + ' neighbourhood';
    var isGraph = ( currentView !== 'overview' && N > 0 );
    // Self-calls are counted in EDGE_TOTAL and cannot be drawn (loadSubset says why). This clause is
    // method-shaped but it stays with the FACTS, because it RECONCILES two counts that are both on the
    // bitmap: in the whole-map view EDGE_TOTAL and L sit on the same screen over the same node set, and
    // an unexplained difference between them is precisely the silent inconsistency this block prevents.
    var drops = ( isGraph && selfEdgesDropped > 0 )
              ? ' (' + selfEdgesDropped + ' self-call' + (selfEdgesDropped === 1 ? '' : 's') + ' not drawn)' : '';

    // ---- CAPTION FACTS. stampProvenance burns THIS half, and only this half, into the exported PNG.
    var factLines = [];
    // R-R/PRIV: the caption shows the TAIL of the root, not the whole path -- and by the time it runs,
    // the home pair is already gone, stripped in C++ by stripHomePair() before `const ROOT` was written
    // (see the emit site for why the file, not just the pixels, is the boundary). This function is the
    // PRESENTATION half: it shortens a long root to '…/a/b' so the caption fits. It re-applies the same
    // structural strip anyway, because it is cheap, it is a no-op on stripped input, and it keeps this
    // half correct on its own terms rather than correct-because-of-something-upstream.
    //
    // The caption matters because stampProvenance burns it into every exported PNG, and a PNG is the
    // thing people share. Shipping the absolute path there published the operator's filesystem layout,
    // and their home directory often carries their real name. Verified on this repo's own README
    // figures, which went to a public branch stamped with the operator's own absolute home path;
    // `strings` finds nothing, because it is rendered as pixels, so no secret scanner would ever have
    // flagged it. Taking the last two segments alone is not enough:
    // for `~/myproject` -- probably the most common layout there is -- the home directory IS one of
    // those two, so the caption published the username anyway. Measured on the first version (written
    // here in the Linux spelling; the macOS one differs only in the leading segment, which is why the
    // check below is on `users` OR `home` and is case-folded first):
    //     /home/jane.doe/src/myproject  -> …/src/myproject   clean
    //     /home/jane.doe/myproject      -> …/jane.doe/…      LEAKED
    //     /home/jane.doe                -> whole path        LEAKED  (the <=2 guard passed it through)
    //     C:\Users\Bob.Jones\code       -> whole path        LEAKED  (split was on '/' only)
    // The leaking segment is always the one after that home root, and its position is knowable, so
    // remove it by structure rather than hoping the tail misses it.
    var rootShort = function(r) {
      if (!r) { return ROOT_NAME || '.'; }
      var parts = r.replace(/[\/\\]+$/, '').split(/[\/\\]+/).filter(function(x){ return x.length && x !== '.'; });
      if (parts.length && /^[A-Za-z]:$/.test(parts[0])) { parts.shift(); }
      var lead = (parts[0] || '').toLowerCase();
      if ((lead === 'users' || lead === 'home') && parts.length >= 2) { parts.splice(0, 2); }
      else if (lead === 'root') { parts.splice(0, 1); }
      if (!parts.length) { return ROOT_NAME || '.'; }   // the name, never '~': a tilde reads as the home directory
      return (parts.length > 2 ? '…/' : '') + parts.slice(-2).join('/');
    };
    factLines.push( k('root') + '<b>' + escHtml(rootShort(ROOT)) + '</b>  ' +
                    k('ranker') + '<b>' + escHtml(RANKER) + '</b>  ' +
                    k('top-k') + '<b>' + TOPK + '</b> of ' + SYM_TOTAL + ' symbols (' + pct + '%)  ' +
                    k('map') + '<b>' + NODE_TOTAL + '</b> nodes / <b>' + EDGE_TOTAL + '</b> call edges' +
                    (AT ? '  ' + k('commit') + '<b>' + escHtml(AT) + '</b>' : '') +
                    (AT.indexOf('+shallow') >= 0 ? ' <b>(shallow clone: churn counts only the commits present)</b>' : '') +
                    '  ' + k('ripwire') + '<b>' + escHtml(VERSION) + '</b>' );
    // ...and how much of that the CAMERA is on. Absent when the camera frames the whole view, which is
    // the auto-fit default and the case where the counts above already describe the frame; present the
    // moment a zoom or a pan makes them describe more than the picture does (see draw()'s closing block).
    var framing = ( isGraph && nodesInFrame < N ) ? ', camera framing <b>' + nodesInFrame + '</b>' : '';
    factLines.push( k('view') + '<b>' + viewName + '</b>' + (currentView === 'overview' ? '' : ': ' + N + ' nodes / ' + L + ' edges' + drops + framing) + '  ' +
                    k('colour') + '<b>' + escHtml(metric) + '</b>' + (mode === 'churn' && !CHURN_OK ? ' <b>unavailable (no git history)</b>' : '') +
                    (settleTimedOut ? '  <b>settling…</b> (layout over the ' + SETTLE_BUDGET_MS + ' ms budget, still converging)'
                     : layoutStopped ? '  <b>layout stopped at step ' + SIM_STEPS + ' of ' + MAX_SIM + '</b> (the ' + LAYOUT_BUDGET_MS +
                                       ' ms layout budget is spent — positions are under-converged, drag to adjust)'
                     : '') );
    if (isGraph) {
      factLines.push( k('method') + 'arrow, dash, label, shape and module-outline rules → <b>' + escHtml(exportBase()) +
                      '.txt</b> (saved with this image)' );
    }

    // ---- CAPTION METHOD. Rendered on the page and written to the companion .txt; NOT stamped.
    var methodClauses = [];
    if (isGraph) {
      // "caller → callee" is stated for the same reason every other clause here is: the picture draws a
      // direction, and a reader must not have to guess which end of an arrow is the one doing the calling.
      methodClauses.push( 'arrow points caller → callee' );
      // The dashed shafts need a key, and it has to name WHAT the resolver could not do: "some of these
      // edges are uncertain" is not a disclosure, it is a mood. Stated as a count so a reader can weigh
      // it — and stated at zero too, because a zero here means the resolver pinned every drawn call to
      // exactly one definition, which is a result.
      //
      // THIS COUNT IS THE VIEW'S, and the legend's AMB_LINKS is the MAP'S. They are two scopes of the
      // same fact and they differ in every ego and module view, so each says which set it is counting;
      // one number reported twice under two scopes would be the silent inconsistency this block exists
      // to prevent.
      methodClauses.push( '<b>' + ambEdges + '</b> of ' + L + ' shafts dashed in this view = the resolver could not choose'
                          + ' between same-name definitions and split the call over all of them' );
      // rule 2 of loadSubset deliberately shows one label per name; a reader must not infer that from the picture
      methodClauses.push( 'labels top ' + MAX_LABELS + ' by in-view degree, one per name' );
      // The shape key is built from SYM_SHAPES, the identical lookup draw() marks a node with, so it
      // cannot name a shape the picture does not draw; and it lists only the kinds actually IN THIS
      // VIEW, because a fixed roster would print marks a reader can hunt for and never find.
      methodClauses.push( 'shapes ' + shapeKey() );
      // EVERY HULL TRUNCATION, EACH WITH ITS OWN COUNT AND ITS OWN REASON. There are three and they are
      // different failures: the cap (26 overlapping regions is the hairball again in a second channel),
      // the SHAPE test (a near-collinear group draws a streak, not a region — see HULL_COMPACTNESS), and
      // the PURITY test (an outline enclosing mostly other modules says nothing). Pooling them into one
      // number would tell a reader that outlines are missing without telling them why, and a reader
      // counting outlines against the module count is exactly who this line is for.
      if (hullsTotal > 0) {
        var hullWhy = [];
        if (hullsThin > 0)   { hullWhy.push(hullsThin + ' dropped as too thin to read as a region'); }
        if (hullsImpure > 0) { hullWhy.push(hullsImpure + ' dropped as enclosing mostly other modules'); }
        methodClauses.push( 'module outlines <b>' + hullsDrawn + '</b> of ' + hullsTotal + ' modules with ' + MIN_HULL_MEMBERS +
                            '+ nodes in view (cap ' + MAX_HULLS + (hullWhy.length ? '; ' + hullWhy.join('; ') : '') + ')' );
      }
    }
    el.innerHTML = '<div id="provfacts">' + factLines.join('<br>') + '</div>' +
                   ( methodClauses.length ? '<div id="provmethod">' + k('how to read') +
                     '<span class="mc">' + methodClauses.join('</span> · <span class="mc">') + '</span></div>' : '' );
  }

  // the shape key's text: one entry per shape present, naming every kind that shares it (class/struct/
  // interface collapse onto the square, var/field onto the plus — the collapses kSymShapes chose).
  function shapeKey() {
    var order = [], kinds = {};
    for (var i = 0; i < N; i++) {
      var t = nodes[i].type, sh = SYM_SHAPES[t] || 'circle';
      if (!Object.prototype.hasOwnProperty.call(kinds, sh)) { kinds[sh] = []; order.push(sh); }
      if (kinds[sh].indexOf(t) < 0) { kinds[sh].push(t); }
    }
    var out = [];
    for (var j = 0; j < order.length; j++) {
      out.push('<b>' + (SHAPES[order[j]] || SHAPES.circle).glyph + '</b> ' + escHtml(kinds[order[j]].join('/')));
    }
    return out.join('  ');
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
      var gid = ids[i], cnt = 0, froms = gin[gid] || [];
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
    // The caller/callee split is stated because the walk that built this view crosses BOTH directions
    // and the picture would otherwise leave a reader to count arrowheads to find out how much of a
    // neighbourhood is "who needs me" and how much is "what I need".
    info.textContent = n.label + ' · ' + n.type + ' · ' + fileOf(n) + ' · rank=' + n.rank + ' · depth=' + egoDepth +
                       ' · ' + eg.ids.length + ' nodes in view · ' + eg.callers + ' callers / ' + eg.callees + ' callees at depth 1';
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
  // The stamp's height is DERIVED from how many caption lines there are, not pinned at the two there
  // used to be. A constant here silently truncated the caption the day it grew a third line — the shape
  // key — which is the clipping defect STAMP_FONT_MIN below already exists to stop, arriving by the
  // other axis.
  var STAMP_MAX_LINES = 4, STAMP_LINE_H = 17, STAMP_TOP = 19, STAMP_BOT = 8;
  var STAMP_PAD = 14, STAMP_FONT_MAX = 13, STAMP_FONT_MIN = 8;
  // #provfacts, not #prov: the bitmap carries what this picture IS and the companion .txt carries how to
  // read it (renderProv says why the two halves split). Reading the whole caption here is what put three
  // dense lines of methodology into every exported figure, shrinking the fitted stamp font against its
  // 8 px floor until the provenance the stamp exists for was the smallest thing in the image.
  function stampLines() {
    var el = document.getElementById('provfacts');
    return el ? el.innerText.split('\n').slice(0, STAMP_MAX_LINES) : [];
  }
  function stampHeight() { var n = stampLines().length; return n ? STAMP_TOP + STAMP_LINE_H*(n - 1) + STAMP_BOT : 0; }
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
    var lines = stampLines();
    g.fillStyle = '#0b0b0b';  g.fillRect(0, y, w, stampHeight());
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
      g.fillText(t, STAMP_PAD, y + STAMP_TOP + i*STAMP_LINE_H);
    }
  }
  function exportBitmap() {
    var out = document.createElement('canvas');
    out.width  = canvas.width;
    out.height = canvas.height + Math.round(stampHeight()*DPR);
    var g = out.getContext('2d');
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    g.fillStyle = CANVAS_BG;  g.fillRect(0, 0, out.width/DPR, out.height/DPR);
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.drawImage(canvas, 0, 0);
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
    stampProvenance(g, out.width/DPR, canvas.height/DPR);
    return out;
  }
  // ONE basename for both files the export writes. It was inline in the click handler and is a function
  // now because renderProv's last FACTS line has to name the .txt the export is about to write: two
  // independently-built names are two names that drift, and a drifted one leaves a picture pointing at a
  // file that is not the one beside it — a disclosure that reads as precise and is wrong.
  function exportBase() {
    var slug = (currentView === 'node' && centreGid >= 0) ? NODES[centreGid].label : (currentView || 'graph');
    return 'ripwire-' + String(slug).replace(/[^A-Za-z0-9_.-]+/g, '_') + '-' + mode;
  }
  // The COMPANION FILE: the whole caption as plain text, provenance first and then the method half the
  // bitmap no longer carries. Both halves, because this is the file a README author lifts the wording out
  // of, and a sidecar holding only the part that moved would make them reassemble the sentence by hand.
  //
  // Built from the SAME DOM the page renders, not from a second set of strings: a plain-text copy of
  // these clauses maintained beside the HTML ones is a second thing that can disagree with the picture,
  // which is the argument that gave the hulls and the labels one placeTextAt instead of two.
  function sidecarText() {
    function textOf(id) { var e = document.getElementById(id); return e ? e.innerText : ''; }
    var out = ['ripwire --html — provenance and method for ' + exportBase() + '.png', ''];
    out = out.concat(textOf('provfacts').split('\n'));
    var spans = document.querySelectorAll('#provmethod .mc');
    if (spans.length) {
      out.push('', 'how to read this picture');
      for (var i = 0; i < spans.length; i++) { out.push('  ' + spans[i].innerText); }
    }
    return out.join('\n') + '\n';
  }
  function download(name, href) {
    var a = document.createElement('a');
    a.download = name; a.href = href;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
  }
  document.getElementById('savePng').addEventListener('click', function() {
    if (canvas.style.display === 'none') { info.textContent = 'nothing to export from the module list — open Graph, a module or a symbol first'; return; }
    draw();                                     // guarantee the frame is current, not a stale hover state
    var base = exportBase();
    download(base + '.png', exportBitmap().toDataURL('image/png'));
    download(base + '.txt', 'data:text/plain;charset=utf-8,' + encodeURIComponent(sidecarText()));
  });

  // boot
  if (GN === 0) { setChrome(false, true); resize(); paintBackdrop(); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); renderProv(); return; }
  resize();
  if (!location.hash) location.hash = '#graph';   // the boot default: the map itself (see renderGraph)
  route();
  resize();   // the caption's height is only knowable once it has content; re-measure so the canvas fits
})();
)JS";

// One drawn call edge: selected-array indices plus what the resolver was able to say about THIS pair.
//
// `amb` is Graph::outProv[e] == 3 — one arm of a k-way split, i.e. the resolver could not choose between
// several same-name definitions and divided the call over all of them. It is the SAME fact the XML map
// spells prov="split" and the MCP surface carries, which is the whole reason it is this quantity and not
// another: the picture and the data now make one claim about one edge, so a reader who checks the map
// against the page cannot find them disagreeing.
//
// It is deliberately NOT a confidence SCORE. Graph::outVals holds a float per out-edge and thresholding
// it conflates two different facts — "the resolver could not choose between k targets" and "a lone match
// was reached through a wide resolution tier on an overcommon name" — which a single dashed stroke would
// then draw identically. Naming the first one exactly is worth more than shading both.
//
// THE GRANULARITY IS STILL THE POINT. The XML's `amb="K"` is a PER-SYMBOL count — "K of this symbol's
// calls hit a name with several definitions" — and 35.4% of emitted call edges carry it. Marking all of a
// symbol's edges uncertain because one of its calls was would be a false statement about all the others.
struct HtmlEdge
{
    std::uint32_t s = 0, t = 0;
    std::uint8_t  amb = 0;
};

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
    "#b07ce8",   // Elixir — the language's conventional violet, lightened away from CSharp's #68217a and
                 // ObjC's #9b59b6 (the two nearest hues) so three purples stay separable on the #111 canvas.
    "#29b6f6",   // Dart — the language's conventional cyan-blue, pushed lighter/more saturated than Go's
                 // #00acd7 and Cpp's #4a90d9 so the three blues stay separable on the #111 canvas.
};
inline constexpr std::size_t kLangColorCount = sizeof( kLangColors ) / sizeof( kLangColors[0] );
// NB the bound names the LAST enumerator, so appending one to Lang leaves this assert TRUE and silently
// unprotecting: Elixir landed with no swatch and compiled clean, and test/htmlrendercheck.sh's (N2) arm —
// which walks langTag() against the emitted LANG_COLORS — is what actually caught it. Move this bound in
// the same commit that appends a Lang, and trust (N2), not this line, to notice if you forget.
static_assert( kLangColorCount == kLangCount,
               "kLangColors must carry one hex colour per Lang enumerator, in declaration order — a language with "
               "no swatch renders as an unlabelled grey the legend cannot explain" );

// The node SHAPE roster, indexed by the SymKind enumerator — the same table shape as kLangColors above,
// and beside it deliberately, for the same reason: two hand-maintained lists behind one enum is the
// drift shape that left eleven languages in an unlabelled grey. This one is indexed BY the enum with
// the same static_assert, so adding a SymKind without a shape is a compile error rather than a symbol
// that silently renders as something it is not.
//
// WHY SHAPE AT ALL. `type` is already in every NODES record and reached nothing but a hover tooltip.
// Kind is NOMINAL data — there is no order in which a class is more than a macro — and shape is the one
// visual channel that is nominal-only, so this is the correct pairing rather than a decoration. The need
// is measured, not aesthetic: on one corpus 1,078 of 2,000 selected nodes are markdown SECTIONS and
// VARIABLES — things that cannot carry a call edge at all — drawn as circles identical to functions,
// which is the whole reason 69% of that page read as isolated dots. A reader could not tell "this
// repository's functions are disconnected" (alarming, and false) from "most of what is on screen is
// documentation and data" (ordinary, and true).
//
// The collapses are deliberate and the caption's key names them: class/struct/interface all mean "a
// type" and share the square; var and field both mean "a slot" and share the plus. `other` gets that
// plus rotated 45° rather than falling through to the function circle, because a fallback to circle
// would be the page asserting that 20 corpus-wide symbols are functions.
inline constexpr const char* kSymShapes[] = {
    "circle",     // Function
    "diamond",    // Method
    "square",     // Class
    "square",     // Struct
    "square",     // Interface
    "plus",       // Var
    "bar",        // Section
    "triangle",   // Macro
    "plus",       // Field
    "cross",      // Other
};
inline constexpr std::size_t kSymShapeCount = sizeof( kSymShapes ) / sizeof( kSymShapes[0] );
static_assert( kSymShapeCount == std::size_t( SymKind::Other ) + 1,
               "kSymShapes must carry one shape per SymKind enumerator, in declaration order — a kind with no "
               "shape falls back to the function circle, which is the page asserting something false about it" );


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
    std::string_view                  atStamp;                   // gitstamp::stampAt of the mapped root ("" off git / multi-root): the caption's commit
    std::string_view                  rootName;                  // the mapped root's last path segment — the page's name, never its path
    std::string_view                  version;                   // kRipwireVersion, so a handed-around page says which binary drew it
};

// The APPEARANCE payload, emitted as ONE section because it is one payload: everything the page needs
// to decide what a node looks like before it decides where it goes. The file-keyed churn array, the flag
// saying whether that array is evidence at all, the baked initial colour mode, the language palette, and
// the SymKind→shape roster. Its own function so writeHtml — already a 360-line emitter — grows by a
// call. It was writeColorPayload while colour was all of it; the name moved with the content rather
// than leaving a function called "color" emitting the shape table.
// `fileList` maps FILES index → ing.files index; churn is file-granularity, so it is keyed by the
// former and looked up through the latter.
// The page's two identity facts (2026-09-06): the commit stamp every XML root carries, and the root's LAST path
// segment. Multi-root pages carry neither (each root labels its own paths). The segment is a NAME — the path it
// came from never reaches the page; stripHomePair() on the ROOT envelope stays the privacy boundary.
struct HtmlProvenance { std::string atStamp; std::string rootName; };

inline HtmlProvenance htmlProvenanceFor( const std::string& root, bool multiRoot )
{
    HtmlProvenance out;
    if( multiRoot )
    {
        return out;
    }
    out.atStamp = gitstamp::stampAt( root );
    std::error_code ec;
    const auto      canon = std::filesystem::canonical( root, ec );
    if( !ec )
    {
        out.rootName = canon.filename().string();
    }
    return out;
}

inline void writeAppearancePayload( std::FILE* out, const std::vector<std::uint32_t>& fileList, const HtmlColorExtras& color )
{
    rw::emitRaw( out, "const FCHURN = [" );
    for( std::size_t i = 0; i < fileList.size(); ++i )
    {
        const std::uint32_t fc = ( color.fileChurn && fileList[i] < color.fileChurn->size() ) ? ( *color.fileChurn )[ fileList[i] ] : 0u;
        rw::emitTo( out, "{}{}", i ? "," : "", fc );
    }
    rw::emitRaw( out, "];\n" );
    // whether git evidence existed — 0 ⇒ churn mode discloses "unavailable" instead of lying zeros
    rw::emitTo( out, "const CHURN_OK = {};\n", color.churnEvidence ? 1 : 0 );
    rw::emitTo( out, "const AT = \"{}\";\n", jsonEscape( color.atStamp ).c_str() );
    rw::emitTo( out, "const ROOT_NAME = \"{}\";\n", jsonEscape( color.rootName ).c_str() );
    rw::emitTo( out, "const VERSION = \"{}\";\n", jsonEscape( color.version ).c_str() );
    // the WINDOW those commit counts were mined over. The legend used to print a bare "0 1-2 3-9 10-29 30+"
    // with no unit and no horizon, so "3-9" could be read as three commits ever; it is three commits inside
    // this window. Passed in by the caller rather than spelled in the JS, because the JS cannot know what
    // main.cpp handed mineChurnPerFile — a hardcoded string here is a claim the page cannot back.
    rw::emitTo( out, "const CHURN_WINDOW = \"{}\";\n", jsonEscape( color.churnWindow ).c_str() );
    // the baked initial colour mode (--color-by=MODE); the in-page selector switches live from here
    rw::emitTo( out, "const COLOR_MODE = \"{}\";\n", colorByLabel( color.initialMode ) );
    // the ranker whose scores the `rank` field carries — the provenance caption's second fact
    // Read from kRankByNames INLINE rather than through an accessor of its own. A second four-line
    // "clamp the enumerator, fall back to entry 0" function beside colorByLabel is a duplicate of it, and
    // factoring the clamp into a shared helper only moved the problem — colorByLabel then became a
    // one-line wrapper that matched three unrelated one-line wrappers elsewhere in the tree. This name
    // has exactly one consumer, so it does not need a function; colorByLabel, which is the shared
    // accessor for a mode the selector also switches, keeps its own.
    const std::size_t rankIdx = std::size_t( color.ranker );
    rw::emitTo( out, "const RANKER = \"{}\";\n", rankIdx < kRankByNameCount ? kRankByNames[ rankIdx ] : kRankByNames[0] );
    // the LANG palette the page's swatches AND its legend are both built from: langTag(L) -> hex, in
    // enumerator order. It belongs in this function and not one of its own: this IS the colour payload,
    // and a separate emitter beside it was a fifth copy of the same comma-separated JSON loop.
    // Deterministic by construction — a constexpr array walked in index order.
    rw::emitRaw( out, "const LANG_COLORS = {" );
    for( std::size_t i = 0; i < kLangColorCount; ++i )
    {
        rw::emitTo( out, "{}\"{}\":\"{}\"", i ? "," : "", langTag( Lang( i ) ), kLangColors[i] );
    }
    rw::emitRaw( out, "};\n" );
    // ...and the SHAPE roster the page's node marks AND the caption's shape key are both built from. It
    // rides in this function rather than one of its own for the reason the LANG palette does: this IS
    // the appearance payload, and a separate emitter beside it would be another copy of the same
    // comma-separated JSON loop. Deterministic by construction — a constexpr array walked in index
    // order, keyed by the same symTag the NODES records' `type` field carries, so the JS looks a node's
    // shape up by the string it already has.
    rw::emitRaw( out, "const SYM_SHAPES = {" );
    for( std::size_t i = 0; i < kSymShapeCount; ++i )
    {
        rw::emitTo( out, "{}\"{}\":\"{}\"", i ? "," : "", symTag( SymKind( i ) ), kSymShapes[i] );
    }
    rw::emitRaw( out, "};\n" );
}

// The EDGE payload: the LINKS records. Its own function for the reason writeAppearancePayload and
// writeDocumentShell are theirs — writeHtml is a 400-line emitter and this is one nameable concept, so
// the caller grows by a call instead of by a loop.
//
// `"a":1` is the per-edge split-arm flag (HtmlEdge says what it is). It is OMITTED at confident rather
// than written as `"a":0`, so a cleanly-resolving corpus emits the identical bytes it emitted before the
// axis existed, and the key costs nothing on the 5000-node ceiling's 13819 edges except where it is true.
inline void writeEdgePayload( std::FILE* out, const std::vector<HtmlEdge>& edges )
{
    // THE EMITTED ORDER IS A FUNCTION OF THE EDGE SET, and this is what pins it. `s` and `t` print as %u
    // integers, so a STRICTLY increasing (s,t) sequence is a TOTAL ORDER WITH NO TIES: a given edge set
    // has exactly one strictly-increasing arrangement, therefore the same edges always emit in the same
    // order and always settle to the same layout. writeHtml's sort note has the measurements showing why
    // that matters — permuting these records moves every drawn node above ~500 of them.
    //
    // THE STRICTNESS IS THE PROPERTY, not a tidier way to say sorted. Relax `<` to `<=` to let duplicate
    // edges through and ties come back; ties admit more than one arrangement; every failure that note
    // describes returns with this check still green. It is assertable at all only because writeHtml
    // dedups AFTER sorting. Verified on this tree at both ends of the range — top-k=200 → 245 edges,
    // top-k=1500 → 3032 edges, strictly increasing, zero duplicates. htmlrendercheck.sh arm (X) re-derives
    // both from the emitted page, with a control that permutes real LINKS and re-runs the same check.
    //
    // It cannot catch a change to which edges are SELECTED, and it should not: that is meant to change
    // the picture. It catches every REORDERING of the same set, which is not.
    rw::emitRaw( out, "const LINKS = [\n" );
    for( std::size_t k = 0; k < edges.size(); ++k )
    {
        VERIFY( k == 0 || edges[k - 1].s < edges[k].s || ( edges[k - 1].s == edges[k].s && edges[k - 1].t < edges[k].t ) );
        rw::emitTo( out, "  {{\"s\":{},\"t\":{}{}{}\n", unsigned( edges[k].s ), unsigned( edges[k].t ),
                      edges[k].amb ? ",\"a\":1}" : "}", ( k + 1 < edges.size() ) ? "," : "" );
    }
    rw::emitRaw( out, "];\n" );
}

// The document SHELL — <head>, the whole stylesheet, and the chrome (#bar, #prov, #hits, #crumb,
// #cards, the canvas) — up to the opening <script>. Lifted out of writeHtml for the reason
// writeAppearancePayload states at its own head: writeHtml is a 400-line emitter and this is a nameable,
// input-free concept, so the caller grows by a call instead of by ninety lines of literal. Nothing here
// depends on the graph; every byte is constant.
// 2026-09-06 stranger audit: the page was titled "ripwire wiki" whatever it mapped, and named its root "~" for
// "." — a page handed to a colleague read as a map of someone's home directory, of unknown code. The title is
// the mapped root's NAME (its last path segment, never its path: the home-pair strip below stays the privacy
// boundary), and the caption carries the commit stamp and the binary version, same as every XML root does.
inline void writeDocumentShell( std::FILE* out, const std::string& pageTitle )
{
    // emit document head. Three in-file VIEWS share one #bar + one #c canvas; #cards (Overview) and
    // #crumb (breadcrumb trail) are additional DOM regions toggled by the router, not separate pages.
    rw::emitTo( out,
        "<!DOCTYPE html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>{}</title>\n"
        "<style>\n"
        "* {{ margin:0; padding:0; box-sizing:border-box; }}\n"
        "body {{ background:#111; color:#eee; font:13px/1.4 sans-serif; overflow:hidden; }}\n"
        "#bar {{ position:fixed; top:0; left:0; right:0; height:36px; background:rgba(0,0,0,.7);\n"
        "       display:flex; align-items:center; gap:12px; padding:0 12px; z-index:10; }}\n"
        "#bar h1 {{ font-size:13px; font-weight:600; white-space:nowrap; }}\n"
        "#bar a.nav {{ color:#7fb2ff; text-decoration:none; font-size:12px; white-space:nowrap; }}\n"
        "#bar a.nav:hover {{ text-decoration:underline; }}\n"
        "#search {{ background:#222; border:1px solid #444; color:#eee; padding:3px 8px;\n"
        "          border-radius:4px; font-size:12px; width:200px; }}\n"
        "#info {{ font-size:12px; color:#aaa; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}\n"
        "#legend {{ font-size:11px; color:#999; white-space:nowrap; }}\n"
        "#legend span {{ display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:3px; }}\n"
        // the metric NAME inside the legend is text, not a swatch — it must escape the circle rule above
        "#legend span.lg {{ width:auto; height:auto; border-radius:0; color:#c8ccd2; margin-right:5px; }}\n"
        // C1: and the edge-confidence clause is a SENTENCE, for the same reason and with the same escape.
        "#legend span.ec {{ display:inline; width:auto; height:auto; border-radius:0; margin:0; color:#7a7f88; }}\n"
        "#colorMode {{ background:#222; border:1px solid #444; color:#eee; padding:3px 6px;\n"
        "             border-radius:4px; font-size:12px; }}\n"
        "#depth {{ font-size:11px; color:#999; display:flex; align-items:center; gap:4px; white-space:nowrap; }}\n"
        "canvas {{ display:block; }}\n"
        "#crumb {{ position:fixed; top:36px; left:0; right:0; z-index:9; background:rgba(20,20,20,.85);\n"
        "         font-size:11px; padding:4px 12px; white-space:nowrap; overflow-x:auto; display:none; }}\n"
        "#crumb a {{ color:#7fb2ff; text-decoration:none; margin-right:4px; }}\n"
        "#crumb a:hover {{ text-decoration:underline; }}\n"
        "#crumb .sep {{ color:#666; margin-right:4px; }}\n"
        "#cards {{ position:fixed; top:36px; left:0; right:0; bottom:0; overflow:auto; padding:16px;\n"
        "         display:none; grid-template-columns:repeat(auto-fill,minmax(260px,1fr)); gap:12px; align-content:start; }}\n"
        "#cards.show {{ display:grid; }}\n"
        "#cards.show ~ canvas, #cards.show ~ #crumb {{ display:none; }}\n"
        ".card {{ background:#1b1b1e; border:1px solid #333; border-radius:6px; padding:12px; cursor:pointer; }}\n"
        ".card:hover {{ border-color:#7fb2ff; }}\n"
        ".card h2 {{ font-size:13px; margin-bottom:6px; word-break:break-all; }}\n"
        ".card .meta {{ font-size:11px; color:#999; margin-bottom:6px; }}\n"
        ".card ul {{ list-style:none; font-size:11px; color:#ccc; }}\n"
        ".card li {{ overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}\n"
        // H11: `.module-card { data-module-card:1; }` used to sit here. `data-module-card:1` is not a CSS
        // declaration — the property does not exist, so the whole rule was dropped by every parser that has
        // ever read this page. The ATTRIBUTE the overview router selects on is written by renderOverview
        // (data-module-card="1") and is unaffected; this was dead bytes shaped like a selector.
        "#prov {{ position:fixed; left:0; right:0; z-index:8; background:rgba(0,0,0,.55); color:#8f96a0;\n"
        "        font:11px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; padding:3px 12px;\n"
        "        white-space:nowrap; overflow-x:auto; border-bottom:1px solid #222; }}\n"
        "#prov b {{ color:#c8ccd2; font-weight:600; }}\n"
        "#prov .k {{ color:#6f757e; }}\n"
        // The METHOD half of the caption, dimmed and ruled off from the FACTS above it. The two are
        // separated visually on the page for the same reason they are separated in the export: one says
        // what this picture is and the other says how to read it, and only the first is stamped into the
        // bitmap. Both stay in #prov so chromeTop() keeps measuring the whole strip in one offsetHeight.
        "#provmethod {{ color:#787f88; }}\n"
        "#bar button {{ background:#222; border:1px solid #444; color:#eee; padding:3px 8px;\n"
        "              border-radius:4px; font-size:12px; cursor:pointer; }}\n"
        "#bar button:hover {{ border-color:#7fb2ff; }}\n"
        "#hits {{ position:fixed; top:36px; left:0; right:0; z-index:9; background:rgba(20,20,20,.92);\n"
        "        font-size:12px; padding:6px 12px; display:none; max-height:40%; overflow:auto; }}\n"
        "#hits a {{ color:#7fb2ff; text-decoration:none; margin-right:14px; display:inline-block; }}\n"
        "#hits a:hover {{ text-decoration:underline; }}\n"
        "#hits .n {{ color:#8f96a0; margin-right:10px; }}\n"
        "</style>\n"
        "</head>\n"
        "<body>\n"
        "<div id=\"bar\">\n"
        "  <h1>{}</h1>\n"
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
        , pageTitle.c_str(), pageTitle.c_str() );
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
        rw::emitRaw( out, "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>ripwire graph</title></head>"
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

    // build LINKS: edges among selected nodes, sorted (s asc, t asc) for determinism. HtmlEdge's own
    // declaration says what `amb` is and why it has to be per-EDGE and not the per-symbol amb= count.
    std::vector<HtmlEdge> edges;
    const std::vector<std::uint8_t>& outProv = g.outProv;
    for( NodeId k = 0; k < cap; ++k )
    {
        const NodeId  id  = order[k];
        const NodeId  si  = k;
        for( std::uint32_t e = outOff[id]; e < outOff[id + 1]; ++e )
        {
            const NodeId tgt = outTargets[e];
            if( tgt < S && idxOf[tgt] != kNoNode )
            {
                // outProv is allocated only when the resolver had something to record — an SCIP
                // overlay, an FFI binding edge, or a split — so an EMPTY one means "nothing here was
                // ambiguous", not "the array is missing". The bound check degrades to that answer
                // rather than reading past the end of a Graph a harness filled with topology alone.
                const std::uint8_t amb = ( e < outProv.size() && outProv[e] == 3u ) ? std::uint8_t( 1 ) : std::uint8_t( 0 );
                edges.push_back( { si, idxOf[tgt], amb } );
            }
        }
    }
    // Sort (s, t). `amb` is deliberately NOT a sort key, so the confidence bit cannot reorder anything.
    //
    // THIS ORDER IS LOAD-BEARING FOR THE LAYOUT, not only for the byte-determinism gate. The page runs
    // its own force sim over these records and float addition is not associative, so permuting LINKS and
    // re-running the identical sim to full MAX_SIM accumulates the same forces in a different order and
    // settles into a DIFFERENT local minimum after 300 steps. Measured max coordinate delta over every
    // drawn node, permuted vs not:
    //
    //     top-k=400     2.85e-6   rounding
    //     top-k=800     1.58e+3   A DIFFERENT LAYOUT
    //     top-k=1500    7.36e+3   A DIFFERENT LAYOUT
    //
    // So above roughly 500 nodes any change to edge EMIT ORDER silently changes every picture this tool
    // has published — and every change that would do it reads as cosmetic: adding a field to the record
    // and sorting on it, grouping edges by module, emitting the low-confidence ones in a separate pass,
    // dedup'ing in a different order. writeEdgePayload's VERIFY is the fence; its note says why STRICT
    // increase is the property that makes the emitted order a function of the edge SET alone.
    std::sort( edges.begin(), edges.end(), [ ]( const HtmlEdge& a, const HtmlEdge& b )
    { return a.s != b.s ? a.s < b.s : a.t < b.t; } );
    // Deduplicate (the same pair can arrive via different resolve paths). The flag is OR-FOLDED into the
    // survivor rather than inherited from whichever row sorted first: an edge one of whose resolutions
    // was a guess IS a guess, and std::unique's keep-the-first rule would make that answer depend on
    // sort order — the one thing the note above says must not decide anything.
    {
        std::size_t writeIndex = 0;
        for( std::size_t readIndex = 0; readIndex < edges.size(); ++readIndex )
        {
            if( writeIndex > 0 && edges[writeIndex - 1].s == edges[readIndex].s && edges[writeIndex - 1].t == edges[readIndex].t )
            {
                edges[writeIndex - 1].amb = std::uint8_t( edges[writeIndex - 1].amb | edges[readIndex].amb );
                continue;
            }
            edges[writeIndex++] = edges[readIndex];
        }
        edges.resize( writeIndex );
    }

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
    for( const HtmlEdge& e : edges )
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

    // the title is HTML text: escape it (the root name is user-chosen; a "<" in it must not become markup)
    std::string pageTitle = "ripwire";
    if( !color.rootName.empty() )
    {
        std::vector<char> titleEsc;
        pageTitle += " — ";
        pageTitle += std::string( rw::escapeXml( color.rootName, titleEsc ) );
    }
    writeDocumentShell( out, pageTitle );

    // emit NODES array — one entry per selected symbol, deterministic (rank-desc, id-asc order
    // preserved). `file` indexes FILES; `comm` is the display module id (moduleRank), or -1 if this
    // node's community didn't survive the ≥2-member filter (a singleton — still shown, just moduleless).
    // `cx` (cyclomatic) and `ts` (tested 0/1) feed the --color-by cx/tested modes; churn stays out of
    // the per-node record because it is file-granularity — one FCHURN array keyed by `file` instead.
    rw::emitRaw( out, "const NODES = [\n" );
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
        rw::formatTo( rankBuf, sizeof( rankBuf ), "{:.4f}", double( r ) );

        rw::emitTo( out, "  {{\"id\":{},\"label\":\"{}\",\"type\":\"{}\",\"lang\":\"{}\",\"rank\":{},\"file\":{},\"comm\":{},\"cx\":{},\"ts\":{}}}",
                      unsigned( k ),
                      jsonEscape( sym.name ).c_str(),
                      jsonEscape( tag ).c_str(),
                      jsonEscape( lang ).c_str(),
                      rw::cstr( rankBuf ),
                      unsigned( fileIdOf[k] == kNoNode ? 0 : fileIdOf[k] ),
                      comm,
                      unsigned( sym.cx ),
                      ts );
        if( k + 1 < cap )
        {
            rw::emitRaw( out, "," );
        }
        rw::emitRaw( out, "\n" );
    }
    rw::emitRaw( out, "];\n" );

    // R-R: the corpus root, stated ONCE — the page's own envelope anchor, so a reader can still resolve
    // the relative FILES[] entries below back to a checkout. Empty on a multi-root run, where each path
    // already carries its own root label.
    const std::string htmlRootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );

    // R-R/PRIV: the prefix above is used STRUCTURALLY, to make each FILES[] entry relative — but what
    // reaches the page is the home-pair-stripped label, never the absolute path. The JS `rootShort()`
    // that formats the caption already strips this pair, and that was believed to be the whole fix; it
    // is not. It only protects the PIXELS. `const ROOT` sat in the emitted file carrying the operator's
    // absolute home path, and --html's whole purpose is to hand someone a self-contained page — so the
    // leak simply moved from the screenshot to View Source, where it is greppable rather than merely
    // legible. The comment above this block used to justify keeping the full string by claiming the page
    // resolves FILES[] against it. Checked against a real emitted page: `ROOT` appears three times, and
    // the only USE is `rootShort(ROOT)` in the caption. Nothing resolved anything. Strip it at the
    // source, so no surface downstream can leak what was never written.
    //
    // Two implementations of one rule is how a rule drifts, so they are split by ROLE rather than
    // duplicated: this is the SECURITY boundary (the pair never enters the file) and `rootShort()` is a
    // PRESENTATION formatter (the '…/a/b' tail). Running the JS over an already-stripped label is a
    // no-op — its own guard is on a leading `users`/`home`/`root` segment, which is exactly what is
    // gone by then. test/htmlrendercheck.sh (P1) greps the emitted page; (P2) is its mutation control.
    const std::string htmlRootLabel = stripHomePair( htmlRootPrefix );
    rw::emitTo( out, "const ROOT = \"{}\";\n", jsonEscape( htmlRootLabel ).c_str() );

    // emit FILES array — one path string per distinct selected-symbol file, first-seen order (R-R: each
    // relative to ROOT above, so the page no longer repeats the checkout prefix once per file)
    rw::emitRaw( out, "const FILES = [\n" );
    for( std::size_t i = 0; i < fileList.size(); ++i )
    {
        const std::string_view hp = rootArg.empty() ? std::string_view( ing.files[ fileList[i] ] )
                                                    : rw::sarif::rootRelativeUri( ing.files[ fileList[i] ], htmlRootPrefix );
        rw::emitTo( out, "  \"{}\"", jsonEscape( std::string( hp ) ).c_str() );
        if( i + 1 < fileList.size() )
        {
            rw::emitRaw( out, "," );
        }
        rw::emitRaw( out, "\n" );
    }
    rw::emitRaw( out, "];\n" );

    // the appearance payload: per-FILES-index churn, its evidence flag, the baked initial colour mode,
    // the language palette, and the SymKind→shape roster
    writeAppearancePayload( out, fileList, color );

    // the edge payload: LINKS, and the per-edge resolver confidences parallel to it
    writeEdgePayload( out, edges );

    // The remaining provenance facts for the caption. NODE_TOTAL/EDGE_TOTAL are the whole selected map;
    // the caption states them beside the CURRENT view's counts, because "221 nodes in view" out of 200 and
    // out of 5000 are different claims and the page used to make neither. TOPK is the ceiling that produced
    // the selection (the effective one, after --max-tokens/adaptive have cut it — the number that explains
    // the map you are looking at, not the number that was typed).
    rw::emitTo( out, "const TOPK = {};\nconst NODE_TOTAL = {};\nconst EDGE_TOTAL = {};\nconst SYM_TOTAL = {};\n",
                  cap, cap, edges.size(), S );

    // emit MODULES array — the Overview cards, sorted (member count desc, commId asc). `members` and
    // `top` are selected-array (NODES) indices; `neigh` is the sorted, deduped list of OTHER display
    // module ids this module shares a selected LINKS edge with (Module view's "cross-links").
    rw::emitRaw( out, "const MODULES = [\n" );
    for( std::size_t disp = 0; disp < modOrder.size(); ++disp )
    {
        const ModuleCard& m = modules[ modOrder[disp] ];
        std::vector<std::uint32_t> neigh;
        for( const HtmlEdge& e : edges )
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

        rw::emitTo( out, "  {{\"id\":{},\"name\":\"{}\",\"symCount\":{},\"fileCount\":{},\"files\":[",
                      disp, jsonEscape( m.name ).c_str(), m.members.size(), m.files.size() );
        for( std::size_t i = 0; i < m.files.size(); ++i )
        {
            rw::emitTo( out, "{}", unsigned( m.files[i] ) );
            if( i + 1 < m.files.size() )
            {
                rw::emitRaw( out, "," );
            }
        }
        rw::emitRaw( out, "],\"members\":[" );
        for( std::size_t i = 0; i < m.members.size(); ++i )
        {
            rw::emitTo( out, "{}", unsigned( m.members[i] ) );
            if( i + 1 < m.members.size() )
            {
                rw::emitRaw( out, "," );
            }
        }
        rw::emitRaw( out, "],\"top\":[" );
        for( std::size_t i = 0; i < m.top.size(); ++i )
        {
            rw::emitTo( out, "{}", unsigned( m.top[i] ) );
            if( i + 1 < m.top.size() )
            {
                rw::emitRaw( out, "," );
            }
        }
        rw::emitTo( out, "],\"inCross\":{},\"outCross\":{},\"neigh\":[", m.inCross, m.outCross );
        for( std::size_t i = 0; i < neigh.size(); ++i )
        {
            rw::emitTo( out, "{}", neigh[i] );
            if( i + 1 < neigh.size() )
            {
                rw::emitRaw( out, "," );
            }
        }
        rw::emitRaw( out, "]}" );
        if( disp + 1 < modOrder.size() )
        {
            rw::emitRaw( out, "," );
        }
        rw::emitRaw( out, "\n" );
    }
    rw::emitRaw( out, "];\n" );

    // inline the JS sim + wiki router
    rw::emitTo( out, "{}{}{}{}{}{}", kScriptColour, kScriptSim, kScriptMarks, kScriptDraw, kScriptViews, kScriptRouter );

    rw::emitRaw( out,
        "</script>\n"
        "</body>\n"
        "</html>\n"
 );
}

}   // namespace rw
