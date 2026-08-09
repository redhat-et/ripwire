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
static const char kScript[] = R"JS(
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

  // colour by lang
  var langColor = {
    cpp: '#4a90d9', py: '#f4c542', ts: '#2d79c7', go: '#00acd7',
    rs: '#dea584', swift: '#fa7343', objc: '#9b59b6', md: '#7f8c8d', '?': '#95a5a6'
  };

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

  // ---- sim state: rebuilt by each view's render() over a FILTERED node/edge subset. `local` nodes
  // carry {gid, x, y, vx, vy, label, type, lang, rank}; `gid` maps back to the NODES index for lookups. ----
  var nodes = [], links = [], N = 0, L = 0, nbr = [];
  var ox = 0, oy = 0, scale = 1, autoFit = true;
  var dragging = -1, panStart = null, hovered = -1, selected = -1;
  var searchSet = null;
  var SIM_STEPS = 0, MAX_SIM = 300;
  var seed = 42;
  function rng() { seed = (seed * 1664525 + 1013904223) & 0xffffffff; return (seed >>> 0) / 4294967296; }

  // load a subset {ids: [NODES idx...], edges: [{s,t} in NODES idx space]} into the sim, remapped to a
  // local 0..n-1 index space. Resets camera/sim state — called on every view switch.
  function loadSubset(ids, edges) {
    seed = 42;
    var gidToLocal = new Map();
    nodes = [];
    for (var i = 0; i < ids.length; i++) {
      var gid = ids[i], src = NODES[gid];
      gidToLocal.set(gid, i);
      nodes.push({ gid: gid, label: src.label, type: src.type, lang: src.lang, rank: src.rank,
                   x: W/2 + (rng()-0.5)*Math.min(W,H)*0.7, y: H/2 + (rng()-0.5)*Math.min(W,H)*0.7, vx: 0, vy: 0 });
    }
    N = nodes.length;
    links = [];
    for (var k = 0; k < edges.length; k++) {
      var s = gidToLocal.get(edges[k].s), t = gidToLocal.get(edges[k].t);
      if (s !== undefined && t !== undefined && s !== t) links.push({ s: s, t: t });
    }
    L = links.length;
    nbr = [];
    for (var i = 0; i < N; i++) nbr.push([]);
    for (var k = 0; k < L; k++) { nbr[links[k].s].push(links[k].t); nbr[links[k].t].push(links[k].s); }

    ox = 0; oy = 0; scale = 1; autoFit = true;
    dragging = -1; panStart = null; hovered = -1; selected = -1; searchSet = null;
    SIM_STEPS = 0;
    info.textContent = '';
    if (N === 0) { ctx.clearRect(0,0,W,H); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); return; }
    step();
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
  function step() {
    if (SIM_STEPS >= MAX_SIM) return;
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
    // integrate
    for (var i = 0; i < N; i++) {
      if (i === dragging) continue;
      nodes[i].vx = (nodes[i].vx + ax[i])*dampen;
      nodes[i].vy = (nodes[i].vy + ay[i])*dampen;
      nodes[i].x += nodes[i].vx;
      nodes[i].y += nodes[i].vy;
    }
    if (autoFit) fitView();
    draw();
    requestAnimationFrame(step);
  }

  // --- draw ---
  function nodeRadius(n) { return Math.max(4, Math.min(20, 4 + 60*Math.sqrt(n.rank))); }

  function draw() {
    ctx.clearRect(0, 0, W, H);
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

    // nodes
    for (var i = 0; i < N; i++) {
      var n = nodes[i];
      var r = Math.max(nodeRadius(n), 3.5/scale);   // floor the ON-SCREEN radius so nodes stay visible when zoomed out
      var dim = (hl && !hl.has(i)) || (searchSet && !searchSet.has(i));
      ctx.globalAlpha = dim ? 0.18 : 1.0;
      ctx.beginPath();
      ctx.arc(n.x, n.y, r, 0, 2*Math.PI);
      ctx.fillStyle = langColor[n.lang] || '#999';
      ctx.fill();
      if (i === selected || i === hovered || n.gid === centreGid) {
        ctx.strokeStyle = '#fff'; ctx.lineWidth = 2/scale; ctx.stroke();
      }
    }
    ctx.globalAlpha = 1.0;
    ctx.restore();

    // tooltip
    if (hovered >= 0) {
      var n = nodes[hovered];
      var sx = n.x*scale+ox, sy = n.y*scale+oy;
      var msg = n.label + ' [' + n.type + ']';
      ctx.fillStyle = 'rgba(0,0,0,0.75)';
      ctx.font = '12px monospace';
      var tw = ctx.measureText(msg).width;
      ctx.fillRect(sx+8, sy-18, tw+10, 22);
      ctx.fillStyle = '#fff';
      ctx.fillText(msg, sx+13, sy-2);
    }
  }

  // canvas → world coords
  function toWorldXY(px, py) { return { x: (px-ox)/scale, y: (py-oy)/scale }; }
  function hitTest(px, py) {
    var w = toWorldXY(px, py);
    for (var i = N-1; i >= 0; i--) {
      var n = nodes[i], r = nodeRadius(n)*1.2;
      var dx = w.x-n.x, dy = w.y-n.y;
      if (dx*dx+dy*dy <= r*r) return i;
    }
    return -1;
  }

  // resize
  function resize() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
    W = canvas.width; H = canvas.height;
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
  canvas.addEventListener('wheel', function(e) {
    e.preventDefault();
    autoFit = false;   // user takes control of the camera
    var factor = e.deltaY < 0 ? 1.1 : 0.91;
    var cx = e.clientX, cy = e.clientY;
    ox = cx - (cx - ox)*factor; oy = cy - (cy - oy)*factor;
    scale *= factor;
    draw();
  }, { passive: false });

  // search — filters the CURRENT view's node set only
  search.addEventListener('input', function() {
    var q = search.value.trim().toLowerCase();
    if (!q) { searchSet = null; draw(); return; }
    searchSet = new Set();
    for (var i = 0; i < N; i++)
      if (nodes[i].label.toLowerCase().indexOf(q) >= 0) searchSet.add(i);
    draw();
  });

  // depth slider (node-view ego graph radius, 1-3)
  var egoDepth = 2;
  depthSlider.addEventListener('input', function() {
    egoDepth = parseInt(depthSlider.value, 10) || 2;
    depthVal.textContent = String(egoDepth);
    if (currentView === 'node') renderNode(centreGid, false);
  });

  // ---- ROUTER: #overview | #module/ID | #node/ID[/DEPTH] ----
  var currentView = null;
  var centreGid = -1;   // NODES index the current #node view is centred on (-1 outside node view)

  function setChrome(showCards, showCanvas) {
    cardsEl.className = showCards ? 'show' : '';
    canvas.style.display = showCanvas ? 'block' : 'none';
    depthSlider.parentElement.style.visibility = (currentView === 'node') ? 'visible' : 'hidden';
  }

  function renderOverview() {
    currentView = 'overview'; centreGid = -1;
    crumbEl.style.display = 'none';
    setChrome(true, false);
    var html = '';
    for (var m = 0; m < MODULES.length; m++) {
      var mod = MODULES[m];
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
    cardsEl.innerHTML = html;
    var els = cardsEl.querySelectorAll('[data-module-card]');
    for (var i = 0; i < els.length; i++) {
      els[i].addEventListener('click', function() { location.hash = '#module/' + this.getAttribute('data-mid'); });
    }
    info.textContent = MODULES.length + ' modules';
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
    info.textContent = n.label + ' · ' + n.type + ' · rank=' + n.rank + ' · depth=' + egoDepth + ' · ' + eg.ids.length + ' nodes in view';
  }

  function route() {
    var h = location.hash.replace(/^#/, '');
    var parts = h.split('/');
    if (parts[0] === 'module' && parts[1] !== undefined) {
      renderModule(parseInt(parts[1], 10) || 0);
    } else if (parts[0] === 'node' && parts[1] !== undefined) {
      var gid = parseInt(parts[1], 10) || 0;
      if (parts[2] !== undefined) { egoDepth = Math.max(1, Math.min(3, parseInt(parts[2],10)||2)); depthSlider.value = String(egoDepth); depthVal.textContent = String(egoDepth); }
      var already = trail[trailPos] === gid;
      renderNode(gid, !already);
    } else {
      renderOverview();
    }
  }
  window.addEventListener('hashchange', route);

  // boot
  if (GN === 0) { setChrome(false, true); ctx.fillStyle='#888'; ctx.font='18px sans-serif'; ctx.fillText('No nodes', 40, 40); return; }
  resize();
  if (!location.hash) location.hash = '#overview';
  route();
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

// writeHtml — emit a self-contained HTML wiki document to `out`.
//   top-min(topK, 5000) symbols selected by (rank desc, id asc) — same ordering rule as serialize.h.
//   Links: call edges among selected nodes only, sorted (s asc, t asc). Deterministic.
//   Modules: one Louvain community (graph.h communities()) per selected-node group that has ≥2
//   members, sorted (member count desc, id asc) — mirrors --communities' "a lone symbol is not a
//   module" rule so the wiki and the text verb agree.
inline void writeHtml( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank, const Graph& g, int topK )
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
        ".module-card { data-module-card:1; }\n"
        "</style>\n"
        "</head>\n"
        "<body>\n"
        "<div id=\"bar\">\n"
        "  <h1>ripwire wiki</h1>\n"
        "  <a class=\"nav\" href=\"#overview\">Overview</a>\n"
        "  <input id=\"search\" type=\"text\" placeholder=\"search labels...\">\n"
        "  <span id=\"depth\">depth <input id=\"depthSlider\" type=\"range\" min=\"1\" max=\"3\" value=\"2\" style=\"width:60px\"><span id=\"depthVal\">2</span></span>\n"
        "  <span id=\"info\"></span>\n"
        "  <span id=\"legend\">\n"
        "    <span style=\"background:#4a90d9\"></span>cpp\n"
        "    <span style=\"background:#f4c542\"></span>py\n"
        "    <span style=\"background:#2d79c7\"></span>ts\n"
        "    <span style=\"background:#00acd7\"></span>go\n"
        "    <span style=\"background:#dea584\"></span>rs\n"
        "    <span style=\"background:#fa7343\"></span>swift\n"
        "    <span style=\"background:#9b59b6\"></span>objc\n"
        "    <span style=\"background:#7f8c8d\"></span>md\n"
        "  </span>\n"
        "</div>\n"
        "<div id=\"crumb\"></div>\n"
        "<div id=\"cards\"></div>\n"
        "<canvas id=\"c\" style=\"margin-top:36px\"></canvas>\n"
        "<script>\n"
    );

    // emit NODES array — one entry per selected symbol, deterministic (rank-desc, id-asc order
    // preserved). `file` indexes FILES; `comm` is the display module id (moduleRank), or -1 if this
    // node's community didn't survive the ≥2-member filter (a singleton — still shown, just moduleless).
    std::fprintf( out, "const NODES = [\n" );
    for( NodeId k = 0; k < cap; ++k )
    {
        const Symbol&  sym  = ing.symbols[ order[k] ];
        const float    r    = rank[ order[k] ];
        const char*    tag  = symTag( sym.kind );
        const char*    lang = langTag( sym.lang );
        const NodeId   slot = moduleOf[k];
        const long     comm = ( slot == kNoNode ) ? -1L : long( moduleRank[ slot ] );

        char rankBuf[ 24 ];
        std::snprintf( rankBuf, sizeof( rankBuf ), "%.4f", double( r ) );

        std::fprintf( out, "  {\"id\":%u,\"label\":\"%s\",\"type\":\"%s\",\"lang\":\"%s\",\"rank\":%s,\"file\":%u,\"comm\":%ld}",
                      unsigned( k ),
                      jsonEscape( sym.name ).c_str(),
                      jsonEscape( tag ).c_str(),
                      jsonEscape( lang ).c_str(),
                      rankBuf,
                      unsigned( fileIdOf[k] == kNoNode ? 0 : fileIdOf[k] ),
                      comm );
        if( k + 1 < cap )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

    // emit FILES array — one path string per distinct selected-symbol file, first-seen order
    std::fprintf( out, "const FILES = [\n" );
    for( std::size_t i = 0; i < fileList.size(); ++i )
    {
        std::fprintf( out, "  \"%s\"", jsonEscape( ing.files[ fileList[i] ] ).c_str() );
        if( i + 1 < fileList.size() )
        {
            std::fprintf( out, "," );
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out, "];\n" );

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
    std::fprintf( out, "%s", kScript );

    std::fprintf( out,
        "</script>\n"
        "</body>\n"
        "</html>\n"
    );
}

}   // namespace rw
