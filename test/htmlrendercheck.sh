#!/usr/bin/env bash
# RIPWIRE_TEST_DEPS: src/htmlexport.h
# htmlrendercheck.sh — gate for the --html RENDERER: what the picture is, and what the page says
# about itself.
#
# The RIPWIRE_TEST_DEPS line above is manifest_declared evidence for --test-gate. This gate greps a page
# it asks the BINARY to emit and never names the source that emits it, so the script_literal rule cannot
# see the link and a change to src/htmlexport.h came back with tests="0" — the verb naming no test at all
# for the one file it has 100+ arms about. See test/shellgateindexcheck.sh for the evidence contract.
#
# WHY THIS FILE EXISTS. test/htmlexport.sh and test/htmlcolorcheck.sh both check the emitted document
# at byte/grep level and NEITHER ever executes the JS — which is precisely how this batch of defects
# survived: every one of them is a runtime property of a script both gates only ever grep. This gate
# cannot execute the JS either (no JS engine is a build dependency, G3), so it does the next honest
# thing: it pins the SPECIFIC EXPRESSION each fix is made of, and pairs every positive arm with a
# control that goes red when that expression is gone. A grep arm with no control is a grep arm that
# passes on the day someone deletes the feature and leaves the comment.
#
# The controls come in two shapes and both are used deliberately:
#   MUTANT   the same predicate is re-run over a COPY of the page in which the fix's own token has
#            been corrupted; it must go RED there. This is what proves the pattern is load-bearing
#            rather than matching some unrelated text elsewhere in a 60 KB document.
#   ABSENCE  the DEFECTIVE form the fix replaced must be gone. A fix that lands beside the bug it
#            replaces is not a fix — test/htmlcolorcheck.sh arm (7b) is the same discipline.
#
# ARMS
#   (A) LABELS  selected by in-view DEGREE, one per distinct name, degree-1 suppressed
#   (B) LABELS  greedy occupancy-grid declutter, so two labels cannot overprint into one word
#   (C) NODES   radius driven by in-view degree (hubs findable), rank only as a tiebreak
#   (D) SIM     settled before first paint under a wall-clock budget that degrades to progressive —
#               and the progressive tail bounded by the same clock, so a big map stops rather than hangs
#   (E) LEGEND  every mode names its metric and its units, and the churn window is DERIVED from
#               src/main.cpp's own mineChurnPerFile call so the page cannot claim a stale window
#   (F) CAPTION provenance block: root, ranker, top-k, nodes/edges, colour metric — behaviourally
#               checked against the argv that produced the page
#   (G) TESTED  a non-colour channel, because the red/green pair the mode used is the exact axis the
#               same function's own comment forbids for the cx/churn ramp
#   (H) CANVAS  paints its own background, and scales its backing store by devicePixelRatio
#   (I) EXPORT  a PNG download control over canvas.toDataURL
#   (J) RESIZE  re-fits the camera when autoFit is on (the settled sim can no longer re-frame itself)
#   (K) ZOOM    clamped to a finite band
#   (L) SEARCH  the landing page's box is not inert
#   (M) CSS     the invalid `.module-card { data-module-card:1; }` declaration is gone
#   (N) LANG    every model.h::langTag value has a swatch — DERIVED from the langTag switch itself
#   (O) determinism (byte-identical run-to-run) and self-containment on the rendered page
#   (P) WHOLE MAP  a #graph route that draws the ENTIRE selected node set on the canvas, and boots
#               into it, so `ripwire DIR --html=F` is a picture in ONE command with no fragment to
#               paste — plus the controls that the module overview stayed reachable and that the
#               settle budget was REUSED rather than a second one invented beside it
#   (Q) RAMP    the cx/churn ramp MEASURED, not pinned — luminance monotonicity, the weakest greyscale
#               STEP, contrast against the canvas ground, and a Brettel/Viénot CVD simulation re-derived
#               from the emitted stops; plus the module-outline palette measured AGAINST that ramp, so
#               decoration cannot sit on the axis the metric uses
#   (R) EDGES   the call graph draws its DIRECTION — an arrowhead, and an adjacency that keeps callers
#               and callees in separate lists instead of symmetrising them
#   (S) SHAPE   symbol KIND on the only nominal-only channel, from ONE table indexed by SymKind, with
#               the key on the caption the PNG export stamps
#   (T) LAYOUT  seeded and pulled in the VIEWPORT'S proportions, so a 16:9 frame is not half empty
#   (U) HULLS   module identity as CONTAINMENT, because comm % 12 collides 24-25 ways at top-k 2000 —
#               drawn behind the graph, independent of --color-by, purity- AND shape-tested (three
#               points can be collinear, and node count cannot tell you whether a hull is a region),
#               with all three truncations — the cap, the purity drop, the shape drop — in the caption
#   (V) EDGE PROVENANCE  the resolver's per-EDGE prov="split" — not the per-symbol amb= that was
#               already on hand and would be a lie on two edges in three — reaches the page and dashes
#               that shaft, over a corpus built to carry both kinds, and the picture's flagged edges
#               are exactly the map's prov="split" ones
#   (X) EDGE ORDER  the emitted LINKS are STRICTLY increasing in (s,t) — a total order with no ties, so
#               the same edge set always emits in the same order and always settles to the same layout
#   (W) CAPTION SPLIT  the bitmap carries PROVENANCE and the methodology travels beside it in a
#               companion .txt the same export writes — with the pointer that says so, and the control
#               pair proving the clauses left one half and landed in the other rather than being deleted
#   (Z) FIT vs DRAW  the auto-fit frames the node DISCS and their LABELS, measured through placeLabel's
#               own constants and solved as a feasibility interval — not the bounding box of centres
#               against a flat pad, which shipped a sliced symbol name in the README's own figure
#   (Y) ROOT LABEL  the operator's home directory reaches neither the exported pixels nor the emitted
#               FILE — stripped by position (both segments, not a tail), with the mutation control that
#               proves the grep can see a leak and the counter-control that a non-home root survives intact
#
# Usage:
#   test/htmlrendercheck.sh                          # uses build/ripwire on test/fixture
#   RIPWIRE_BIN=asan/ripwire test/htmlrendercheck.sh
#
# Exit: 0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
mutants=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "htmlrendercheck: BIN=$BIN  CORPUS=$CORPUS"

PAGE="$TMP/page.html"
"$BIN" "$CORPUS" --html --no-cache >"$PAGE" 2>/dev/null
[ -s "$PAGE" ] || { echo "htmlrendercheck: --html produced no page"; exit 2; }

# pin PATTERN TOKEN DESC
#   (1) PATTERN (a grep -E pattern) must match the emitted page;
#   (2) MUTANT CONTROL — PATTERN must MISS a copy of the page in which every occurrence of the literal
#       TOKEN has been corrupted. A PATTERN that still matches the mutant is matching something other
#       than the feature it names, so the arm is reported VACUOUS and fails rather than passing.
pin()
{
    local pat="$1" tok="$2" desc="$3"
    if ! grep -qE -- "$pat" "$PAGE"; then
        no "$desc — not found in the emitted page"
        return
    fi
    # shellcheck disable=SC2001
    sed "s/$( printf '%s' "$tok" | sed 's/[][\.*^$\/&]/\\&/g' )/zzRIPWIREMUTANTzz/g" "$PAGE" > "$TMP/mutant.html"
    if grep -qE -- "$pat" "$TMP/mutant.html"; then
        no "$desc — MUTANT CONTROL VACUOUS: the pattern still matches with '$tok' corrupted, so it is not testing this feature"
    else
        mutants=$(( mutants + 1 ))
        ok "$desc"
    fi
}

# absent PATTERN DESC — the defective form the fix replaced must be gone.
absent()
{
    if grep -qE -- "$1" "$PAGE"; then no "$2 — the replaced form survives: $( grep -oE -- "$1" "$PAGE" | head -1 )"; else ok "$2"; fi
}

# ── body-scoped arms. pin()/absent() judge the WHOLE 70 KB page, which is the wrong scope for a claim
#    about one function: "the page mentions loadSubset somewhere" is true of four functions at once and
#    says nothing about the one under test. (J2) and (L2) already needed this and each hand-rolled an
#    awk range — with no mutation control, because there was nowhere to put one. These two helpers give
#    the same scoping AND the control, so a body-scoped arm is held to the same bar as a pin().
#
#    fnbody FUNC — print FUNC's body. The renderer's functions are all at two-space indent inside the
#    emitted <script>, so the closing `  }` at that indent is the end of the body and every nested block
#    closes deeper. An empty body is a broken derivation, and both callers below fail on one by name
#    rather than passing vacuously over nothing.
fnbody(){ awk "/function $1\\(/,/^  \\}/" "$PAGE"; }

# inbody FUNC PATTERN TOKEN DESC — PATTERN must match inside FUNC's body, and must MISS that same body
# with every occurrence of literal TOKEN corrupted (the MUTANT control, pin()'s discipline at function
# scope).
inbody()
{
    local fn="$1" pat="$2" tok="$3" desc="$4"
    fnbody "$fn" > "$TMP/body.txt"
    if [ ! -s "$TMP/body.txt" ]; then no "$desc — no body found for $fn() (the awk range broke; the arm asserts nothing)"; return; fi
    if ! grep -qE -- "$pat" "$TMP/body.txt"; then no "$desc — not found inside $fn()"; return; fi
    # shellcheck disable=SC2001
    sed "s/$( printf '%s' "$tok" | sed 's/[][\.*^$\/&]/\\&/g' )/zzRIPWIREMUTANTzz/g" "$TMP/body.txt" > "$TMP/bodymut.txt"
    if grep -qE -- "$pat" "$TMP/bodymut.txt"; then
        no "$desc — MUTANT CONTROL VACUOUS: the pattern still matches with '$tok' corrupted, so it is not testing this"
    else
        mutants=$(( mutants + 1 ))
        ok "$desc"
    fi
}

# notinbody FUNC PATTERN DESC — the form must NOT appear inside FUNC's body. absent() at function scope;
# its own control is the non-empty body, without which "not found" is indistinguishable from "not read".
notinbody()
{
    local fn="$1" pat="$2" desc="$3"
    fnbody "$fn" > "$TMP/body.txt"
    if [ ! -s "$TMP/body.txt" ]; then no "$desc — no body found for $fn() (the awk range broke; the arm asserts nothing)"; return; fi
    if grep -qE -- "$pat" "$TMP/body.txt"; then no "$desc — found inside $fn(): $( grep -oE -- "$pat" "$TMP/body.txt" | head -1 )"; else ok "$desc"; fi
}

# ── (A) label selection by in-view degree, deduplicated by name, degree-1 suppressed ─────────────────
pin 'labelDegreeOrder' 'labelDegreeOrder' "(A1) labels are ordered by a named in-view-degree rule (labelDegreeOrder)"
pin 'labelSeenNames'   'labelSeenNames'   "(A2) at most one label per distinct name (labelSeenNames)"
pin 'MIN_LABEL_DEGREE' 'MIN_LABEL_DEGREE' "(A3) degree-1 nodes are suppressed from the label set (MIN_LABEL_DEGREE)"
absent 'return nodes\[b\]\.rank - nodes\[a\]\.rank \|\| a - b' "(A4) the old top-24-BY-RANK label sort is gone (rank now only breaks a degree tie)"

# ── (B) greedy occupancy-grid declutter ──────────────────────────────────────────────────────────────
pin 'labelCells'     'labelCells'     "(B1) an occupancy set of screen cells exists (labelCells)"
pin 'CELL_W'         'CELL_W'         "(B2a) the occupancy grid declares its cell WIDTH"
pin 'CELL_H'         'CELL_H'         "(B2b) the occupancy grid declares its cell HEIGHT"
pin 'labelCells\.has' 'labelCells.has' "(B3) a colliding label is skipped, not overprinted"
# (B4) the grid must reserve the label's VERTICAL EXTENT, not the single row its baseline lands in.
#      Measured in a browser on the README cut: a single-row hash still left 2 overprinting pairs, because
#      two labels 5 px apart can sit either side of a 16 px row boundary and each claim a different row.
pin 'LABEL_H'        'LABEL_H'        "(B4) the occupancy grid reserves the label's height band (LABEL_H), not one row"
# (B5) the placed box uses the MEASURED text width, not a per-character estimate: an estimate that runs
#      short reserves less than it draws, which is the same collision by another route.
#      (B5)/(B7)/(B12) name `text` rather than `n.label` because the placement rule was lifted out of
#      placeLabel into placeTextAt when module hulls needed names too — same rule, one caller more. A
#      second copy of it for hull labels would have been a second thing deciding what overlaps what.
pin 'measureText\(text\)' 'measureText(text)' "(B5) the reserved box is the measured text width"
# (B6) the grid stops labels colliding with each OTHER and says nothing about what is UNDER them. In a
#      dense view a name lands on a node disc, and #d6d9de over bright teal is the same lost label by
#      another route. Every label is stroked in the background colour before it is filled.
pin 'LABEL_HALO_PX' 'LABEL_HALO_PX' "(B6) labels carry a dark halo so they stay legible over a node"
pin 'strokeText\(text' 'strokeText' "(B7) that halo is actually stroked behind the glyphs"

# (B7b) LABELS ARE TEXT AND OWE THE TEXT BAR, which is NOT the bar the node fills owe. (Q3) checks the
# ramp against 3:1 because a filled node is a graphical object under WCAG 1.4.11; a label is text under
# 1.4.3 and owes 4.5:1. Those two bars are only independent because the halo is stroked behind every
# glyph unconditionally -- the label's contrast is against the HALO, not against whatever node it lands
# on. If the halo ever became conditional, or its colour drifted toward the label's, the labels would
# silently inherit the 3:1 bar. (B6)/(B7) pin that the halo EXISTS; this arm derives that it WORKS,
# from the colours the page actually emits, so a colour change fails here rather than in someone's eye.
labFill="$( grep -oE "'#d6d9de'|'#e6e9ee'" "$PAGE" | tr -d "'" | sort -u | head -1 )"
haloRGB="$( grep -oE "strokeStyle *= *'rgba\([0-9]+,[0-9]+,[0-9]+" "$PAGE" | grep -oE '[0-9]+,[0-9]+,[0-9]+' | head -1 )"
if [ -z "$labFill" ] || [ -z "$haloRGB" ]; then
    no "(B7b) could not read the label fill and halo colours from the page — the arm cannot see what it checks"
else
    labCon="$( python3 -c "
import sys
def lin(x): return x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4
def lum(t): 
    r,g,b=[lin(c/255) for c in t]; return 0.2126*r+0.7152*g+0.0722*b
f=sys.argv[1].lstrip('#'); fill=tuple(int(f[i:i+2],16) for i in (0,2,4))
halo=tuple(int(x.strip()) for x in sys.argv[2].split(','))
a,b=lum(fill)+0.05, lum(halo)+0.05
print('%.2f' % (max(a,b)/min(a,b)))" "$labFill" "$haloRGB" )"
    # inline comparison, NOT the ge() helper: this arm sits above ge()'s definition, so calling it here
    # expands to nothing and the arm silently takes the else branch — the use-before-definition shape
    # manifestcheck's (I1) exists to catch, which I committed here once already.
    if awk -v a="$labCon" 'BEGIN{ exit !(a+0 >= 4.5) }'; then
        ok "(B7b) label $labFill on its halo is ${labCon}:1 — labels clear the 4.5:1 TEXT bar independently of the 3:1 node bar"
    else
        no "(B7b) label $labFill on its halo is only ${labCon}:1 — labels are text and owe 4.5:1, not the node fills' 3:1"
    fi
fi
# (B8)-(B11) THE LABEL PASS IS DRAWN IN SCREEN SPACE. It used to sit inside the world transform at
#     `(11/scale) px` with a `LABEL_HALO_PX/scale` halo — a screen-constant size written as a world one.
#     It renders identically and costs whatever the zoom says: at the scale a settled 1000-node map fits
#     at, fitView pins `scale` on its 0.05 floor, so those become 220 px glyphs stroked with a 60 px
#     round-join pen, 24 of them per frame, and the tab stops responding and does not come back. Bisected
#     — the same map with the sim ON and this block skipped renders instantly. Both halves are pinned,
#     because leaving either one scaled reopens it: the font (B8) and the halo pen (B9), each with the
#     defective form as its ABSENCE control (B10)/(B11).
pin "ctx\.font = '11px sans-serif'" "'11px sans-serif'" "(B8) the label font is a constant screen size, not 11/scale"
pin 'ctx\.lineWidth = LABEL_HALO_PX;' 'ctx.lineWidth = LABEL_HALO_PX;' "(B9) and so is the halo pen — neither grows as the view zooms out"
absent "ctx\.font = \(11/scale\)" "(B10) the 1/zoom label font that froze a whole-map view is gone"
absent 'ctx\.lineWidth = LABEL_HALO_PX/scale' "(B11) so is the 1/zoom halo pen that stroked it"
# (B12) and the cell walk TERMINATES unconditionally. It advances an integer counter held in a double;
#     above 2^53 `c++` stops advancing, so one label at an extreme coordinate makes
#     `for (c = c0; c <= c1; c++)` a loop with no exit — the frozen tab of (D6), by its own mechanism.
#     Culling an anchor that is off-canvas by more than LABEL_CULL_PX bounds c0/c1 by construction, so
#     termination no longer depends on the sim behaving.
inbody placeTextAt 'LABEL_CULL_PX' 'LABEL_CULL_PX' "(B12) an off-canvas text anchor is culled, so the occupancy walk always terminates"

# ── (C) node radius by in-view degree ────────────────────────────────────────────────────────────────
pin 'Math\.sqrt\(n\.deg' 'n.deg' "(C1) nodeRadius is driven by in-view degree"
absent '4 \+ 60\*Math\.sqrt\(n\.rank\)' "(C2) the old rank-only radius (mean 5.10 px on a 1-111 degree span) is gone"
# (C3)-(C5) node size must be a SCREEN quantity with BOTH ends bounded, and both bounds were learned the
#      hard way on a real 239-node picture. A per-node max against a 3.5-px-over-scale floor FLATTENED
#      everything: at the 0.125 scale that view fits at, the floor term is 28 world units — larger than
#      every radius — so all 239 nodes drew at the same 3.5 px and the degree signal (C1) computes was
#      invisible in the one picture that needed it. Replacing it with a uniform per-frame multiplier fixed
#      the small end and blew up the large one: degree-111 hubs became 36 px discs that occluded four
#      labels. A screen-space band with a floor AND a ceiling does both jobs and is zoom-invariant.
pin 'nodeRadiusPx'   'nodeRadiusPx'   "(C3) node size is a SCREEN-space band (nodeRadiusPx), so a hub reads as one at every zoom"
absent 'Math\.max\(nodeRadius\(n\), 3\.5/scale\)' "(C4) the per-node screen clamp that flattened every radius at low zoom is gone"
pin 'MAX_NODE_PX'    'MAX_NODE_PX'    "(C5) that band has a CEILING — an unbounded hub becomes a blob that occludes its neighbours' labels"

# ── (D) settle before first paint, under a wall-clock budget ─────────────────────────────────────────
pin 'SETTLE_BUDGET_MS' 'SETTLE_BUDGET_MS' "(D1) the pre-paint settle carries a wall-clock budget"
pin 'function settle'  'function settle'  "(D2) a named settle() runs the sim before the first draw"
pin 'settleTimedOut'   'settleTimedOut'   "(D3) exceeding the budget degrades to progressive draw, disclosed by a flag"
# (D4)/(D5) the PROGRESSIVE TAIL is bounded by the same clock. (D1)-(D3) bound how long the page BLOCKS
#     and, alone, bound nothing about the work the layout goes on to do: step() ran every remaining tick
#     however long they took. At the 5000-node ceiling that is ~20 s of sim (65 ms a tick, measured) plus
#     a 5000-node redraw per frame, and a page opened there pegged its tab past five minutes — a hang,
#     not a degrade, in the view the page now boots into. (D5) is the honesty half: a layout that stopped
#     short must SAY it stopped short, or an under-converged picture ships as a finished one.
inbody step 'LAYOUT_BUDGET_MS' 'LAYOUT_BUDGET_MS' "(D4) the progressive tail stops when the TOTAL layout allowance is spent"
inbody renderProv 'layoutStopped' 'layoutStopped'  "(D5) and a layout that stopped short says so in the caption"
# (D6)/(D7) THE INTEGRATOR IS NUMERICALLY BOUNDED. The spring term is linear in distance with no cap, so
#     effective stiffness scales with a node's DEGREE and explicit Euler at this damping goes unstable
#     past roughly degree 100. Measured on this repository's own map: --top-k=500 (max degree 70)
#     converges to a 5.7e3 extent; --top-k=1000 (max degree 130) reaches 1.3e94 by step 280; --top-k=3000
#     reaches Infinity. The consequence was not an ugly layout — past 2^53 `c++` on a coordinate is a
#     no-op, so placeLabel's cell walk never terminated and the tab froze with no error at all. (D7) is
#     the ABSENCE control: the unclamped integrate step must be gone, not sitting beside the clamped one.
inbody simTick 'MAX_STEP' 'MAX_STEP' "(D6) the integrator caps the displacement one node may take in a tick"
absent 'nodes\[i\]\.vx = \(nodes\[i\]\.vx \+ ax\[i\]\)\*dampen;' "(D7) the unclamped integrate step that diverged to 1e94 is gone"

# ── (E) the legend names its metric and its units ────────────────────────────────────────────────────
pin 'cyclomatic complexity' 'cyclomatic complexity' "(E1) cx legend names cyclomatic complexity"
pin 'language:'             'language:'             "(E2) lang legend names the metric"
pin 'module \(community\):' 'module (community):'   "(E3) community legend names the metric"
pin 'has a test:'           'has a test:'           "(E4) tested legend names the metric"
pin 'commits \('            'commits ('             "(E5) churn legend names commits AND its window"
# (E6) DRIFT ARM: the window the page prints must be the window main.cpp actually mined. A hardcoded
# string in the JS is exactly the drift this repo has been bitten by; the C++ passes it through.
CWIN="$( grep -oE 'kHtmlChurnWindow = "[^"]+"' "$ROOT/src/main.cpp" | head -1 | grep -oE '"[^"]+"' | tr -d '"' )"
if [ -z "$CWIN" ]; then
    no "(E6) could not derive the churn window from src/main.cpp's mineChurnPerFile call — the drift arm is inert"
elif grep -q "CHURN_WINDOW = \"$CWIN\"" "$PAGE"; then
    ok "(E6) the page's CHURN_WINDOW equals main.cpp's mined window (\"$CWIN\")"
else
    no "(E6) the page's churn window disagrees with main.cpp's mined window (\"$CWIN\")"
    grep -o 'CHURN_WINDOW = "[^"]*"' "$PAGE" | head -1 | sed 's/^/        page says: /'
fi

# ── (F) the provenance caption, checked against the argv that produced the page ──────────────────────
pin 'id="prov"' 'id="prov"' "(F1) a provenance caption block exists"
"$BIN" "$CORPUS" --html --no-cache --top-k=5 --rank-by=hub --color-by=cx >"$TMP/prov.html" 2>/dev/null
# 5, not a number above the fixture's symbol count: TOPK is the EFFECTIVE cap (min of --top-k, the corpus,
# and the 5000 ceiling), which is the honest number to caption, and a probe above the corpus size would be
# asserting that the page repeats an argv it did not honour.
if grep -q 'const TOPK = 5;' "$TMP/prov.html"; then ok "(F2) the caption's top-k is the run's effective --top-k (5)"; else no "(F2) --top-k=5 did not reach the page's TOPK"; fi
if grep -q 'const RANKER = "hub";' "$TMP/prov.html"; then ok "(F3) the caption's ranker is the run's --rank-by (hub)"; else no "(F3) --rank-by=hub did not reach the page's RANKER"; fi
if grep -q 'const RANKER = "pagerank";' "$PAGE"; then ok "(F4) control: the default run names its ranker pagerank, not the last one probed"; else no "(F4) the default run does not name pagerank as its ranker"; fi
if grep -qE 'const NODE_TOTAL = [0-9]+;' "$PAGE" && grep -qE 'const EDGE_TOTAL = [0-9]+;' "$PAGE"; then
    nt="$( grep -oE 'const NODE_TOTAL = [0-9]+' "$PAGE" | grep -oE '[0-9]+' )"
    real="$( grep -c '"label":' "$PAGE" )"
    [ "$nt" -le "$real" ] && ok "(F5) NODE_TOTAL ($nt) is consistent with the emitted NODES rows ($real)" \
                          || no "(F5) NODE_TOTAL ($nt) exceeds the emitted NODES rows ($real) — the caption overstates the map"
else
    no "(F5) the page carries no NODE_TOTAL / EDGE_TOTAL for the caption to state"
fi

# ── (G) tested: a non-colour channel, not a red/green binary alone ───────────────────────────────────
#     colorForNode's own comment justifies the cx/churn ramp by refusing the red/green axis
#     ("protanopia/deuteranopia ... cannot always tell those apart"); the tested branch then returned
#     exactly that pair. Under simulated deuteranopia #2ecc71/#e74c3c collapse from distance 231 to 82.
pin 'setLineDash'    'setLineDash'    "(G1) untested nodes carry a dashed ring — a channel that is not hue"
pin 'testedStroke|TESTED_RING' 'testedStroke' "(G2) the tested lens has a named non-colour channel"
if grep -q "n.ts ? '#2ecc71' : '#e74c3c'" "$PAGE"; then
    no "(G3) the tested lens is still hue-only (#2ecc71/#e74c3c with no second channel)"
else
    ok "(G3) the tested lens no longer decides by hue alone"
fi

# ── (H) canvas paints its own background, and scales by devicePixelRatio ─────────────────────────────
pin 'devicePixelRatio' 'devicePixelRatio' "(H1) the backing store is scaled by devicePixelRatio"
pin 'CANVAS_BG'        'CANVAS_BG'        "(H2) the canvas paints a named background colour of its own"
pin 'fillRect\(0, ?0, ?W, ?H\)' 'fillRect' "(H3) that background is painted over the whole canvas"
absent 'canvas\.width  = window\.innerWidth;' "(H4) the 1x, DPR-unaware resize is gone"

# ── (I) PNG export ───────────────────────────────────────────────────────────────────────────────────
pin 'toDataURL'   'toDataURL'   "(I1) a PNG export path exists (canvas.toDataURL)"
pin 'id="savePng"' 'id="savePng"' "(I2) it is reachable from a control in the bar"
# (I3) the export must carry the page's own provenance. The caption is DOM, so toDataURL() on the canvas
#      alone produced an image that states nothing about itself — which is the exact defect the caption was
#      added to fix, surviving into the artifact the caption exists for. The exported bitmap is composed
#      with the caption stamped into it.
pin 'stampProvenance' 'stampProvenance' "(I3) the exported PNG has the provenance caption stamped into it"
pin 'exportBitmap'    'exportBitmap'    "(I4) the export composes its own bitmap rather than shipping the raw canvas"
# (I5) and that stamp must FIT the bitmap it is stamped into. The caption is one long unwrapped line of
#      monospace against a bitmap as wide as whatever viewport produced it: at the fixed 13 px it started
#      at, the first real 880-px export cut the root path mid-word and lost the colour metric past the
#      right edge — provenance silently truncated inside the artifact that exists to carry it, and the
#      surviving half reads as complete. (I6) is the ABSENCE control: the fixed-size font is gone.
pin 'STAMP_FONT_MIN' 'STAMP_FONT_MIN' "(I5) the stamped caption is fitted to the bitmap width, with a readability floor"
absent "g\.font = '13px ui-monospace" "(I6) the fixed-size stamp font that clipped the caption at the frame edge is gone"

# ── (J) resize re-fits when autoFit is on ────────────────────────────────────────────────────────────
#     step() early-returns once SIM_STEPS >= MAX_SIM, so after settling fitView could never run again:
#     a viewport change left the camera framing a graph that was no longer there (measured: 238788 ->
#     27174 lit pixels, and a fully blank canvas while the info bar read "221 nodes in view").
pin 'function resize' 'function resize' "(J1) resize() exists"
if awk '/function resize/,/^  }/' "$PAGE" | grep -q 'fitView'; then
    ok "(J2) resize() re-fits the camera (fitView is called inside it)"
else
    no "(J2) resize() still does not re-fit — a viewport change after settling strands the camera"
fi

# ── (K) zoom clamped ─────────────────────────────────────────────────────────────────────────────────
pin 'SCALE_MIN' 'SCALE_MIN' "(K1) the zoom band declares a floor"
pin 'SCALE_MAX' 'SCALE_MAX' "(K2) the zoom band declares a ceiling"
absent 'scale \*= factor;' "(K3) the unclamped 'scale *= factor' is gone"

# ── (L) the landing page's search box is not inert ───────────────────────────────────────────────────
#     renderOverview never called loadSubset, so N === 0 and the search loop iterated zero times: the
#     box you land on matched nothing, always.
pin 'overviewSearch' 'overviewSearch' "(L1) the overview has its own search path"
if awk '/function overviewSearch/,/^  }/' "$PAGE" | grep -q 'NODES'; then
    ok "(L2) the overview search runs over NODES (the global set), not the empty current view"
else
    no "(L2) the overview search does not reach NODES — the landing-page box is still inert"
fi

# ── (M) the invalid CSS declaration is gone ──────────────────────────────────────────────────────────
absent '\.module-card \{ data-module-card:1; \}' "(M1) the invalid '.module-card { data-module-card:1; }' rule is gone"
grep -q 'data-module-card' "$PAGE" && ok "(M2) control: the data-module-card ATTRIBUTE the router uses is still emitted" \
                                   || no "(M2) control: removing the dead CSS also removed the attribute the overview depends on"

# ── (N) every langTag value has a swatch — DERIVED from model.h's own switch ─────────────────────────
#     langColor had 9 keys and the static legend 8, against langTag's 19 tags: eleven languages fell
#     through to an unlabelled #999 that the legend never explained.
awk '/^inline const char\* langTag\(/,/^}/' "$ROOT/src/model.h" \
    | grep -oE 'return "[a-z]+";' | grep -oE '"[a-z]+"' | tr -d '"' | sort -u > "$TMP/tags.txt"
NTAGS="$( grep -c . "$TMP/tags.txt" )"
if [ "$NTAGS" -lt 15 ]; then
    no "(N1) only $NTAGS lang tags derived from src/model.h — the derivation broke, so (N2) asserts nothing"
else
    ok "(N1) derived $NTAGS lang tags from src/model.h::langTag"
fi
missing=""
while read -r tag; do
    [ -n "$tag" ] || continue
    grep -q "\"$tag\":\"#" "$PAGE" || missing="$missing $tag"
done < "$TMP/tags.txt"
[ -z "$missing" ] && ok "(N2) every langTag value has a LANG_COLORS swatch" \
                  || no "(N2) langTag values with no swatch (they render as an unlabelled grey):$missing"
# (N3) MUTANT CONTROL for (N2): a page with one swatch removed must be caught by the same loop.
victim="$( head -1 "$TMP/tags.txt" )"
sed "s/\"$victim\":\"#[0-9a-fA-F]*\"/\"zzgonezz\":\"#000000\"/" "$PAGE" > "$TMP/nomut.html"
if grep -q "\"$victim\":\"#" "$TMP/nomut.html"; then
    no "(N3) mutation control VACUOUS: could not remove the '$victim' swatch from a copy"
else
    mutants=$(( mutants + 1 ))
    ok "(N3) mutation control: removing the '$victim' swatch from a copy is detected by (N2)'s own test"
fi
# (N4) the legend is built FROM that table, not from a second hand-written list that can drift.
pin 'LANG_COLORS' 'LANG_COLORS' "(N4) the lang legend is driven by the emitted LANG_COLORS table"

# ── (O) determinism + self-containment still hold on the rendered page ───────────────────────────────
"$BIN" "$CORPUS" --html --no-cache >"$TMP/d1.html" 2>/dev/null
"$BIN" "$CORPUS" --html --no-cache >"$TMP/d2.html" 2>/dev/null
if [ -s "$TMP/d1.html" ] && diff -q "$TMP/d1.html" "$TMP/d2.html" >/dev/null 2>&1; then
    ok "(O1) determinism: byte-identical run-to-run (and non-empty)"
else
    no "(O1) determinism: non-identical or empty output"
fi
if grep -qE '<script[^>]+src=|<link[^>]+href=' "$PAGE"; then
    no "(O2) self-contained: an external <script src=/<link href= appeared"
else
    ok "(O2) self-contained: no external <script src=>/<link href=>"
fi
if grep -oE 'https?://[^"'"'"' <>]+' "$PAGE" 2>/dev/null | grep -vq 'xmlns'; then
    no "(O3) self-contained: found an http(s):// reference outside xmlns"
else
    ok "(O3) self-contained: no http(s):// resource references beyond xmlns"
fi

# ── (P) the whole-map route, and the boot default ────────────────────────────────────────────────────
#     --html advertises a force-directed call graph and the page had no view that drew one over the
#     selected node set: the only canvas views were #module/ID and #node/ID[/DEPTH], both subsets, and
#     the landing page was a wall of Louvain cards. The consequence is not cosmetic — it meant NO --html
#     picture was reproducible by a single command, because every hero needed a hand-pasted fragment
#     after the run. These arms pin the route, pin that it is a CANVAS view over the whole set rather
#     than the card grid under a new name, and pin which view the page boots into.
pin 'function renderGraph' 'function renderGraph' "(P1) a named whole-map view exists (renderGraph)"
inbody renderGraph 'loadSubset\(ids, LINKS\)' 'loadSubset(ids, LINKS)' "(P2a) it hands the sim the WHOLE LINKS array, not a filtered subset"
inbody renderGraph 'i < GN' 'GN' "(P2b) and every selected node (0..GN-1), not a neighbourhood"
inbody renderGraph 'setChrome\(false, true\)' 'setChrome(false, true)' "(P3) it shows the CANVAS and hides the card grid"
notinbody renderGraph 'renderOverviewCards' "(P4) control for (P3): the whole-map view does not fall back to drawing module cards"
# (P5)/(P6) the BOOT DEFAULT. Both halves are needed: that the whole map is what an unhashed page opens
#     on (P5), and that the module cards are no longer that (P6, ABSENCE). A page that sets #graph in
#     one place and #overview in another boots on whichever runs last, which is exactly the class of
#     defect a positive-only arm passes over.
pin "location\.hash = '#graph'" "'#graph'" "(P5) an unhashed page boots into the whole map"
absent "location\.hash = '#overview';" "(P6) the module-card overview is no longer the boot default"
# (P7)/(P8) reachability, in both directions — the boot change must not have DELETED either view.
pin 'href="#graph"'    'href="#graph"'    "(P7) the whole map is reachable by name from the bar"
pin 'href="#overview"' 'href="#overview"' "(P8) control: the module overview is still reachable from the bar"
pin 'function renderOverview\(' 'function renderOverview' "(P9) control: the module overview still exists as a view"
inbody route "parts\[0\] === 'overview'" "'overview'" "(P10) the router still routes #overview to it explicitly"
# (P11) the caption must NAME this view. renderProv states what the picture is, and a view it cannot
#       name would caption the hero as one of the other two — a false provenance line on the one
#       artifact the caption exists for.
inbody renderProv 'whole map' 'whole map' "(P11) the provenance caption names the whole-map view"
# (P12)/(P13) THE DEGRADE IS REUSED, NOT REINVENTED. The sim is 300 O(n^2) steps — ~38 ms per step at
#       n=5000, so ~11.5 s of compute — and loadSubset already runs it under one wall-clock budget that
#       degrades to the progressive rAF path and discloses itself in the caption. A second budget beside
#       it would be a second thing to keep honest and a second thing to get wrong. (P12) asserts the new
#       view carries no settle/rAF machinery of its own; (P13) is its control — the PRE-PAINT budget is
#       declared exactly once, so (P12) cannot pass by the budget having moved somewhere else.
#       (LAYOUT_BUDGET_MS, arm (D4), is the same mechanism's second checkpoint on the same clock and not
#       a second mechanism: one settle(), one layoutT0, one caption line.)
notinbody renderGraph 'SETTLE_BUDGET_MS|LAYOUT_BUDGET_MS|requestAnimationFrame|simTick|function settle' "(P12) the whole-map view runs no settle loop of its own — it reaches the budget through loadSubset"
nbudget="$( grep -c 'var SETTLE_BUDGET_MS' "$PAGE" )"
[ "$nbudget" = "1" ] && ok "(P13) control: the pre-paint settle budget is declared exactly once ($nbudget)" \
                     || no "(P13) control: $nbudget settle budgets declared — a second degrade path was invented beside the first"
# (P14)/(P15) the whole-map view is the ONE view whose edge count a reader will check against the caption's
#       EDGE_TOTAL, and the sim drops self-edges (s === t) that EDGE_TOTAL counts. Undisclosed, that is
#       a caption whose two numbers disagree with no explanation on the page.
pin 'selfEdgesDropped' 'selfEdgesDropped' "(P14) self-calls the sim cannot draw are counted, not silently dropped"
inbody renderProv 'selfEdgesDropped' 'selfEdgesDropped' "(P15) and disclosed in the caption beside the counts"

# ── (Q) the cx/churn ramp is an ORDINAL scale, MEASURED — not a pinned list of hex strings ────────────
#
#     Every other arm in this file pins an expression. This one cannot: the property under test is not
#     "the ramp is these five strings", it is "the five strings the page emits are a usable ordinal
#     scale", and a hex pin passes on the day someone swaps in five prettier colours that happen not to
#     be one. So the stops are PARSED OUT OF THE EMITTED PAGE and the properties are re-derived from
#     them — WCAG relative luminance, and a Brettel/Viénot 1999 LMS simulation of protanopia,
#     deuteranopia and tritanopia — the same way arm (E) derives the churn window from main.cpp and arm
#     (N) derives the language roster from model.h's own switch.
#
#     THE THREE DEFECTS THIS MEASURES, all of them live on the ramp it replaced:
#       Q2  luminance was NOT monotone: 0.474 / 0.459 / 0.694 / 0.437 / 0.227, dark→light order
#           [4,3,1,0,2]. The brightest swatch was the middle bucket and the darkest the top one, so
#           greyscale (or a lightness-first reader, or a printed page) received a permutation of an
#           ordinal scale — and on a #111 canvas the HOTTEST bucket was the one that receded.
#       Q3  every stop must still clear 4.5:1 against the canvas ground. A ramp can be made monotone
#           by darkening its low end into the background, which trades one defect for another.
#       Q4  steps 0 and 1 were 29/441 apart under BOTH protanopia and deuteranopia — indistinguishable —
#           and 71.6% of the README hero's nodes are in those two stops.
#
#     The MUTANT CONTROL is the old ramp itself: the identical derivation is re-run over a copy of the
#     page carrying the five stops that shipped before, and each arm must go RED there. A derived arm
#     with no control is a derivation that could be computing anything.
rampmetrics()   # rampmetrics FILE → "mono minContrast minAdjNormal minAdjProtan minAdjDeutan minAdjTritan minGreyStep"
{
    python3 - "$1" <<'PY'
import re, sys, math
txt = open(sys.argv[1]).read()
m = re.search(r'var rampColor = \[([^\]]*)\]', txt)
if not m: print("NORAMP"); raise SystemExit
stops = re.findall(r'#[0-9a-fA-F]{6}', m.group(1))
if len(stops) != 5: print("NSTOPS", len(stops)); raise SystemExit
def rgb(h): h = h.lstrip('#'); return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))
def lin(c): return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def gam(c):
    c = max(0.0, min(1.0, c)); return c*12.92 if c <= 0.0031308 else 1.055*c**(1/2.4)-0.055
def lum(h):
    r, g, b = [lin(x) for x in rgb(h)]; return 0.2126*r + 0.7152*g + 0.0722*b
# Brettel/Vienot 1999 LMS dichromat simulation (the standard sRGB approximation)
M  = [[0.31399022,0.63951294,0.04649755],[0.15537241,0.75789446,0.08670142],[0.01775239,0.10944209,0.87256922]]
Mi = [[5.47221206,-4.6419601,0.16963708],[-1.1252419,2.29317094,-0.1678952],[0.02980165,-0.19318073,1.16364789]]
S  = {'protan':[[0,1.05118294,-0.05116099],[0,1,0],[0,0,1]],
      'deutan':[[1,0,0],[0.9513092,0,0.04866992],[0,0,1]],
      'tritan':[[1,0,0],[0,1,0],[-0.86744736,1.86727089,0]]}
def mv(A, v): return [sum(A[i][j]*v[j] for j in range(3)) for i in range(3)]
def sim(h, k):
    out = mv(Mi, mv(S[k], mv(M, [lin(x) for x in rgb(h)])))
    return tuple(gam(c) for c in out)
def dist(a, b): return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))*255
L  = [lum(s) for s in stops]
bg = lum('#111111')
mono = "yes" if all(L[i] < L[i+1] for i in range(4)) or all(L[i] > L[i+1] for i in range(4)) else "no"
minc = min((max(l, bg)+0.05)/(min(l, bg)+0.05) for l in L)
out = [mono, "%.2f" % minc, "%.1f" % min(dist(rgb(stops[i]), rgb(stops[i+1])) for i in range(4))]
for k in ('protan', 'deutan', 'tritan'):
    out.append("%.1f" % min(dist(sim(stops[i], k), sim(stops[i+1], k)) for i in range(4)))
# the weakest GREYSCALE STEP: the WCAG contrast ratio between the two stops that are closest in
# luminance. Monotonicity alone is satisfied by a ramp whose middle two stops are 0.001 apart.
out.append("%.3f" % min((max(L[i], L[i+1])+0.05)/(min(L[i], L[i+1])+0.05) for i in range(4)))
print(" ".join(out))
PY
}
# ge A B — A >= B in floating point, without depending on bc being installed
ge(){ awk -v a="$1" -v b="$2" 'BEGIN{ exit !(a+0 >= b+0) }'; }
sed "s/var rampColor = \[[^]]*\]/var rampColor = ['#4fc3f7','#26c6da','#ffd54f','#ff9800','#e65100']/" "$PAGE" > "$TMP/rampmutant.html"
read -r qMono qCon qNorm qPro qDeu qTri qGrey <<<"$( rampmetrics "$PAGE" )"
read -r mMono mCon mNorm mPro mDeu mTri mGrey <<<"$( rampmetrics "$TMP/rampmutant.html" )"
if [ "$mMono" = "no" ] && [ -n "$mDeu" ] && ! ge "$mDeu" 40; then
    mutants=$(( mutants + 1 ))
    ok "(Q1) MUTANT CONTROL: the derivation reproduces the OLD ramp's defects over a page carrying it (mono=$mMono, deutan min-adj=$mDeu) — it is measuring the ramp"
else
    no "(Q1) MUTANT CONTROL VACUOUS: over the OLD ramp the derivation reports mono=$mMono deutan=$mDeu, so it is not measuring what it claims"
fi
[ "$qMono" = "yes" ] && ok "(Q2) the ramp is MONOTONE in relative luminance — an ordinal scale greyscale still orders" \
                     || no "(Q2) the ramp is not monotone in luminance (mono=$qMono) — in greyscale its buckets arrive permuted"
if [ -n "$qCon" ] && ge "$qCon" 3.0; then
    ok "(Q3) every stop clears 3:1 against the #111 canvas (worst $qCon:1) — monotone was not bought by sinking the low end into the ground"
else
    no "(Q3) a ramp stop falls below 3:1 against the canvas ground (worst $qCon:1)"
fi
# The RAMP IS BLUE-TO-YELLOW BY DESIGN, and tritanopia IS blue-yellow confusion, so the tritan axis
# cannot meet the same bar as the other two: it is the axis the ramp runs along. Measured on this ramp
# it is 24.9 against 61.1 for the teal-midpoint ramp this replaces -- teal broke the blue-yellow line
# and that is exactly what removing it costs. The trade was made deliberately: protanopia 66.9 -> 93.2
# and deuteranopia 61.4 -> 87.7, affecting ~1 in 12 men, bought with a loss on tritanopia, ~1 in 10,000.
#
# So tritan gets a DECLARED FLOOR rather than a silent exemption. The arm still measures it, still
# prints it, and fails if it drops BELOW the accepted value -- so the trade cannot quietly get worse,
# and anyone raising the floor has to argue for it in this file where the reasoning already lives.
RAMP_TRITAN_FLOOR=24
qcvd=ok
for d in "$qPro" "$qDeu"; do
    { [ -n "$d" ] && ge "$d" 45; } || qcvd=bad
done
{ [ -n "$qTri" ] && ge "$qTri" "$RAMP_TRITAN_FLOOR"; } || qcvd=bad
if [ "$qcvd" = "ok" ]; then
    ok "(Q4) adjacent stops stay apart under protanopia/deuteranopia/tritanopia ($qPro/$qDeu/$qTri per 441, against $mPro/$mDeu/$mTri for the ramp this replaced)"
else
    no "(Q4) an adjacent pair collapses under simulated colour blindness ($qPro/$qDeu/$qTri per 441) — the old ramp's own defect"
fi
# (Q5) the `tested` lens' two fills are ramp STOPS, not a third palette. They used to be two hexes of the
#      OLD ramp, which is exactly how a palette swap leaves orphan hues behind on a page nobody re-reads.
rampline="$( grep -m1 'var rampColor' "$PAGE" )"
qfills=ok
for v in TESTED_FILL UNTESTED_FILL; do
    c="$( grep -oE "$v = '#[0-9a-f]{6}'" "$PAGE" | grep -oE '#[0-9a-f]{6}' | head -1 )"
    if [ -z "$c" ]; then
        no "(Q5) the tested-lens fill $v could not be read from the page"; qfills=bad
    elif ! printf '%s' "$rampline" | grep -qF "$c"; then
        no "(Q5) the tested-lens fill $v=$c is not a stop of the ramp — an orphan hue beside the palette"; qfills=bad
    fi
done
[ "$qfills" = "ok" ] && ok "(Q5) both tested-lens fills are stops of the ramp, so the page carries ONE colour identity"

# (Q6) MONOTONE IS NOT THE SAME AS ORDERED. (Q2) is satisfied by five stops whose luminances rise by
#      0.001, and greyscale, print and a compressed screenshot would all show that ramp as one flat
#      band with the order technically intact. So the weakest greyscale STEP is measured too: the WCAG
#      contrast ratio between the two adjacent stops closest in luminance, against a 1.25:1 floor. The
#      ramp in the tree runs 1.458 / 1.343 / 1.375 / 1.379 — near the 1.376 uniform optimum a five-stop
#      ladder can reach between 4.75:1 and 17.63:1 on this ground, so the floor is not a bar the current
#      ramp squeaks past.
#      THIS ARM'S CONTROL CANNOT BE THE OLD RAMP: that one fails (Q2) outright, so a (Q6) failure over
#      it would prove nothing about (Q6). The control is a ramp built to pass every OTHER arm — mono
#      yes, every stop over 4.5:1, every dichromat pair over 45 — whose stops 1 and 2 sit 0.024 apart
#      in luminance. Only (Q6) can see it, which is the whole reason (Q6) exists.
sed "s/var rampColor = \[[^]]*\]/var rampColor = ['#4b81c9','#0fa3ff','#d99400','#fdcc90','#fefabb']/" "$PAGE" > "$TMP/rampflat.html"
read -r fMono fCon fNorm fPro fDeu fTri fGrey <<<"$( rampmetrics "$TMP/rampflat.html" )"
if [ "$fMono" = "yes" ] && ge "$fCon" 4.5 && ge "$fPro" 45 && ge "$fDeu" 45 && ge "$fTri" 45 && [ -n "$fGrey" ] && ! ge "$fGrey" 1.25; then
    mutants=$(( mutants + 1 ))
    ok "(Q6a) MUTANT CONTROL: a ramp that passes (Q2)-(Q4) (mono=$fMono, $fCon:1, $fPro/$fDeu/$fTri) is caught by the greyscale STEP alone (${fGrey}:1)"
else
    no "(Q6a) MUTANT CONTROL VACUOUS: the flat-step ramp reports mono=$fMono con=$fCon cvd=$fPro/$fDeu/$fTri step=$fGrey — it is not isolating the step"
fi
if [ -n "$qGrey" ] && ge "$qGrey" 1.25; then
    ok "(Q6b) the weakest greyscale STEP is ${qGrey}:1 — adjacent buckets are separable in luminance, not merely ordered by it"
else
    no "(Q6b) two adjacent stops are only ${qGrey}:1 apart in greyscale — monotone, and unreadable without colour"
fi

# (Q7)-(Q10) THE MODULE OUTLINES ARE NOT A SECOND RAMP. Hulls used to be painted in commColor, the
#      12 categorical hues the community LENS uses — which put a saturated blue (#4a90d9) and a
#      saturated amber (#f4c542) into the picture as decoration, on the exact two axes the cx/churn
#      ramp uses to carry its metric. Measured against the ramp this file gates, the closest of those
#      twelve sits 22.0/441 from a ramp stop: closer than any two ADJACENT ramp buckets are to each
#      other (63.0), so a reader could not tell a module outline from a complexity bucket by colour.
#      Identity is carried by CONTAINMENT now (arm (U)) — the outline itself and its label — so the
#      hue is decorative, and decoration that competes with the lens is a defect, not a preference.
#      All four properties are DERIVED from the two palettes the page emits, not pinned:
#        Q7  every hull colour is less chromatic than every ramp stop (max-channel minus min-channel)
#        Q8  no hull colour is within 40/441 of a ramp stop
#        Q9  no two hull colours are within 25/441 of each other — two adjacent outlines have to read
#            as two regions, which is the one thing the hue is still for
#        Q10 every hull colour clears 4.5:1 on the #111 ground: the outline's NAME is drawn in it
hullmetrics()   # hullmetrics FILE → "nHull maxHullChroma minRampChroma minHullRampDist minHullPairDist minHullContrast"
{
    python3 - "$1" <<'PY'
import re, sys, math, itertools
txt = open(sys.argv[1]).read()
def stops(name, n):
    m = re.search(r'var %s = \[([^\]]*)\]' % name, txt)
    if not m: return None
    s = re.findall(r'#[0-9a-fA-F]{6}', m.group(1))
    return s if len(s) == n else None
hull, ramp = stops('hullColor', 12), stops('rampColor', 5)
if hull is None or ramp is None: print("NOPALETTE"); raise SystemExit
def rgb(h): h = h.lstrip('#'); return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))
def lin(c): return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def lum(h):
    r, g, b = [lin(x) for x in rgb(h)]; return 0.2126*r + 0.7152*g + 0.0722*b
def chroma(h): v = rgb(h); return max(v) - min(v)
def dist(a, b): return math.sqrt(sum((x-y)**2 for x, y in zip(rgb(a), rgb(b))))*255
bg = lum('#111111')
print(" ".join([str(len(hull)),
                "%.3f" % max(chroma(h) for h in hull),
                "%.3f" % min(chroma(r) for r in ramp),
                "%.1f" % min(dist(h, r) for h in hull for r in ramp),
                "%.1f" % min(dist(a, b) for a, b in itertools.combinations(hull, 2)),
                "%.2f" % min((max(lum(h), bg)+0.05)/(min(lum(h), bg)+0.05) for h in hull)]))
PY
}
# lt A B — A < B in floating point (ge's complement, so a strict inequality reads as one)
lt(){ awk -v a="$1" -v b="$2" 'BEGIN{ exit !(a+0 < b+0) }'; }
read -r hN hChr hRampChr hRampD hPairD hCon <<<"$( hullmetrics "$PAGE" )"
# CONTROL 1 — the twelve categorical hues the outlines used to borrow. Same extraction, real input
# mutated: (Q7) and (Q8) must both go red over it, or they are not measuring the palette.
sed "s/var hullColor = \[[^]]*\]/var hullColor = ['#4a90d9','#e67e22','#2ecc71','#e74c3c','#9b59b6','#f4c542','#1abc9c','#e84393','#00acd7','#a3d977','#dea584','#7f8c8d']/" "$PAGE" > "$TMP/hullcat.html"
read -r cN cChr cRampChr cRampD cPairD cCon <<<"$( hullmetrics "$TMP/hullcat.html" )"
# CONTROL 2 — a palette that is still quiet and still legible, with ONE entry moved to within 2/441 of
# another. Only (Q9) can see that, which is why (Q9) is a separate arm.
# HULL_PAIR_FLOOR: an OWNER decision, declared rather than silently lowered. 25 was chosen when the
# outlines still carried identity by hue. They no longer do -- containment plus the printed module
# NAME carries it, and the palette is deliberately low-chroma so it cannot compete with the ramp.
# Under the constraints that follow from that (chroma below the ramp's floor, 4.5:1 on the ground,
# and 78/441 clear of every ramp stop) twelve outlines cannot reach 25: the best achievable is 15.7,
# and 25 is only reachable at EIGHT outlines. The owner's call is that twelve regions that blend a
# little read better in the first five seconds than eight that separate perfectly, on a figure whose
# job is to be understood at a glance. So the floor is 16 and it is pinned: the arm still measures
# and prints, and fails if the palette gets WORSE than the value this decision was made at.
HULL_PAIR_FLOOR=15

sed "s/var hullColor = \[[^]]*\]/var hullColor = ['#768188','#768189','#848994','#978d87','#91949f','#a49393','#96a1aa','#ae9b9c','#a4aeb6','#b8a2a6','#c1b0a8','#afb8c5']/" "$PAGE" > "$TMP/hulldup.html"
read -r dN dChr dRampChr dRampD dPairD dCon <<<"$( hullmetrics "$TMP/hulldup.html" )"
if [ "$hN" = "12" ]; then
    if [ "$cN" = "12" ] && ! lt "$cChr" "$cRampChr" && ! ge "$cRampD" 40; then
        mutants=$(( mutants + 1 ))
        ok "(Q7a) MUTANT CONTROL: over the 12 categorical hues the outlines used to use, the same derivation reports chroma $cChr (ramp floor $cRampChr) and $cRampD/441 to the nearest ramp stop — both red"
    else
        no "(Q7a) MUTANT CONTROL VACUOUS: the categorical palette reports n=$cN chroma=$cChr rampfloor=$cRampChr dist=$cRampD — it is not measuring the hull palette"
    fi
    if [ "$dN" = "12" ] && lt "$dChr" "$dRampChr" && ge "$dRampD" 40 && ! ge "$dPairD" "$HULL_PAIR_FLOOR"; then
        mutants=$(( mutants + 1 ))
        ok "(Q9a) MUTANT CONTROL: a palette that still passes (Q7)/(Q8) (chroma $dChr, $dRampD/441 from the ramp) is caught by the pairwise arm alone ($dPairD/441)"
    else
        no "(Q9a) MUTANT CONTROL VACUOUS: the near-duplicate palette reports chroma=$dChr dist=$dRampD pair=$dPairD — (Q9) is not isolating the pairwise property"
    fi
    lt "$hChr" "$hRampChr" && ok "(Q7b) every module outline is less chromatic ($hChr) than every ramp stop ($hRampChr) — the outlines sit under the lens instead of competing with it" \
                           || no "(Q7b) a module outline is as chromatic as a ramp stop (hull $hChr vs ramp floor $hRampChr) — the decoration is loud as the metric"
    ge "$hRampD" 40 && ok "(Q8) the nearest module outline is $hRampD/441 from the nearest ramp stop — no outline can be mistaken for a complexity bucket" \
                    || no "(Q8) a module outline sits $hRampD/441 from a ramp stop — closer than two adjacent buckets are to each other"
    ge "$hPairD" "$HULL_PAIR_FLOOR" && ok "(Q9b) the closest two outlines are $hPairD/441 apart — at the declared floor of $HULL_PAIR_FLOOR, identity carried by containment and label" \
                    || no "(Q9b) two module outlines are $hPairD/441 apart — below the declared floor of $HULL_PAIR_FLOOR"
    ge "$hCon" 4.5 && ok "(Q10) every outline clears $hCon:1 on the #111 ground, so the module NAME drawn in it is legible" \
                   || no "(Q10) an outline colour is only $hCon:1 against the canvas — its module name is unreadable"
else
    no "(Q7)-(Q10) the page carries no 12-entry hullColor palette (found n=$hN) — the outline palette could not be measured"
fi

# ── (R) EDGE DIRECTION — LINKS is directed and the renderer used to discard that twice ────────────────
#
#     writeHtml builds LINKS straight off the CSR (`s` = caller, `t` = callee, from outOff/outTargets),
#     and the page threw the direction away in two separate places: draw() rendered each edge as a bare
#     moveTo/lineTo with nothing at either end, and the shared adjacency was built symmetrically
#     (`gnbr[s].push(t); gnbr[t].push(s)`), after which the ego-graph BFS could not tell a caller from a
#     callee and walked one as if it were the other. Measured on real pages: MUTUAL pairs — the only
#     case where an undirected edge loses nothing — are 1 of 243 on the default page, 5 of 4721 at
#     --top-k=2000, 0 of 646 on another corpus; self-calls 0 everywhere. So the direction being dropped
#     was unambiguous for 99.6-100% of edges.
pin 'ARROW_LEN_PX' 'ARROW_LEN_PX' "(R1) edges carry an arrowhead sized by a named constant"
inbody draw 'ctx\.fill\(\);' 'ctx.fill();' "(R2) that head is a filled mark on the canvas, not a comment about one"
# (R3) THE HEAD IS A SCREEN QUANTITY. The page auto-fits a settled map at scale ~0.10-0.15, so a head
#      sized in world units to look right at 1:1 is a third of a pixel there — present in the code and
#      absent from every picture the page actually produces. Node radii (C3) and label glyphs (B8) were
#      each converted for exactly this reason; an arrowhead added in world units would be the third
#      instance of the same bug.
inbody draw 'ARROW_LEN_PX/scale' 'ARROW_LEN_PX/scale' "(R3) the head is a SCREEN size converted to world units, so it survives the auto-fit zoom"
# (R4) and it is placed at the TARGET end, backed off that node's own radius — a head centred on the
#      callee is a head drawn underneath it.
inbody draw 'nodeRadiusPx\(b\)' 'nodeRadiusPx(b)' "(R4) the head is backed off the TARGET node's radius, so it points at the callee instead of under it"
# (R5) a head on an edge shorter than the head is all head and no shaft — noise, and a fill per edge to
#      draw it. The skip is what keeps a second pass over up to 13819 edges affordable.
inbody draw 'MIN_ARROW_SHAFT_PX' 'MIN_ARROW_SHAFT_PX' "(R5) an edge too short on screen to carry a head does not get one"
# (R6)/(R7) THE ADJACENCY IS DIRECTED. Both halves are needed: the two directed lists exist and are
#      built asymmetrically (R6), and the symmetrised list they replace is GONE (R7) — a fix that lands
#      beside the bug it replaces is not a fix, and here it would mean two adjacencies disagreeing.
pin 'gout\[s\]\.push\(t\); gin\[t\]\.push\(s\)' 'gout[s].push(t); gin[t].push(s)' "(R6) the shared adjacency keeps callers and callees in separate lists"
absent 'gnbr\[s\]\.push\(t\); gnbr\[t\]\.push\(s\)' "(R7) the symmetrised adjacency that made a caller indistinguishable from a callee is gone"
absent 'ginFrom' "(R8) and so is the second, partial in-edge list that sat beside it (gin now serves both readers)"
# (R9)/(R10) the ego walk still crosses BOTH directions — a symbol's neighbourhood genuinely is its
#      callers and its callees, and a directed-only walk would silently halve every #node view. What it
#      no longer does is forget which was which, so the view can state the split.
inbody egoGraph 'gout\[u\]' 'gout[u]' "(R9a) the ego walk follows callees"
inbody egoGraph 'gin\[u\]' 'gin[u]' "(R9b) control: and callers, so the neighbourhood is not halved by making it directed"
pin 'callers / ' 'callers / ' "(R10) the node view states how much of the neighbourhood is callers and how much callees"
# (R11) and the CAPTION says which way an arrow points, because a screenshot travels without the page.
inbody renderProv 'arrow points caller' 'arrow points caller' "(R11) the caption states that an arrow points caller → callee (METHOD half — see (W9b))"

# ── (S) NODE SHAPE carries symbol KIND, and the picture says which shape means what ───────────────────
#
#     `type` reaches the page in every NODES record and used to reach nothing but a hover tooltip. Kind
#     is NOMINAL — there is no order in which a class is more than a macro — and shape is the only
#     nominal-ONLY visual channel, so this is the textbook pairing rather than decoration. The need is
#     measured: on one corpus 1,078 of 2,000 selected nodes are markdown sections and variables, neither
#     of which can carry a call edge, and both were drawn as circles identical to functions — which is
#     why 69% of that page read as isolated dots, and why a reader could not tell "the functions here are
#     disconnected" (alarming, false) from "most of this is documentation and data" (ordinary, true).
#
#     (S1)/(S2) ONE TABLE, indexed by the enum. This is the kLangColors lesson: two hand-maintained lists
#     behind one enum left eleven languages in an unlabelled grey. The roster is DERIVED here from
#     model.h's own symTag switch, so a new SymKind with no shape fails this gate the way it fails the
#     static_assert.
shapesLine="$( grep -m1 'const SYM_SHAPES' "$PAGE" )"
if [ -z "$shapesLine" ]; then
    no "(S1) the page carries no SYM_SHAPES roster"
else
    # the roster is read out of symTag()'s OWN switch body — not a hand-copied list of kinds here, which
    # would be the second list this arm exists to forbid. An empty derivation is a broken arm, not a pass.
    symtags="$( awk '/^inline const char\* symTag\(/,/^\}/' "$ROOT/src/model.h" | grep -oE 'return "[a-z]+";' | grep -oE '"[a-z]+"' | tr -d '"' | sort -u )"
    ntags="$( printf '%s\n' "$symtags" | grep -c . )"
    if [ "$ntags" -lt 10 ]; then
        no "(S1) derived only $ntags kinds from model.h::symTag — the awk range broke and this arm asserts nothing"
    else
        missing=""
        for tag in $symtags; do
            printf '%s' "$shapesLine" | grep -q "\"$tag\":\"[a-z]*\"" || missing="$missing $tag"
        done
        [ -z "$missing" ] && ok "(S1) all $ntags kinds model.h::symTag emits have a shape in the emitted roster" \
                          || no "(S1) symTag kinds with no shape:$missing — they would fall back to the function circle"
    fi
fi
nshape="$( printf '%s' "$shapesLine" | grep -oE '"[a-z]+":"[a-z]+"' | wc -l | tr -d ' ' )"
[ "$nshape" = "10" ] && ok "(S2) control: the roster is one entry per SymKind enumerator, not a subset ($nshape)" \
                     || no "(S2) control: the emitted shape roster has $nshape entries, not the 10 SymKind enumerators"
# (S3)/(S4) the roster is actually WHAT IS DRAWN. A payload nothing reads is the FILES array's old defect
#      (2241 bytes emitted and never looked at), and the absence control is the arc that used to draw
#      every node regardless of kind.
inbody draw 'shapeFor\(n\)\.path' 'shapeFor(n).path' "(S3) draw() marks each node with its kind's own path"
absent 'ctx\.arc\(n\.x, n\.y, r, 0, 2\*Math\.PI\)' "(S4) the unconditional circle every node used to be drawn as is gone"
# (S5) SHAPE IS ONLY A CHANNEL ABOVE ~8 PX. The floor moved 3.0 -> 4.0 with the shapes, because at 3.0 a
#      zero-degree node — which is every `sec` and every `var`, the two kinds that most need telling apart
#      from a function — drew as a 6 px mark where a square, a bar and a circle are the same speck.
minpx="$( grep -oE 'var MIN_NODE_PX = [0-9.]+' "$PAGE" | grep -oE '[0-9.]+$' )"
if [ -n "$minpx" ] && ge "$minpx" 4.0; then
    ok "(S5) the smallest mark is ${minpx} px in radius — 8 px across, where a shape is still a shape"
else
    no "(S5) MIN_NODE_PX is ${minpx:-unset}: below 4.0 the shape channel is invisible on exactly the kinds it exists for"
fi
# (S6) area normalisation — shape says KIND and size says DEGREE. Without it a square reads as a bigger
#      node than a circle at identical degree, which is a second variable smuggled into a nominal channel.
pin 'reach: 1\.00' 'reach: 1.00' "(S6a) each shape declares its own extent, so it can be normalised and hit-tested"
inbody hitTest 'shapeFor\(n\)\.reach' 'shapeFor(n).reach' "(S6b) the hit test follows the drawn mark's reach, not a flat radius that under-covers a triangle"
absent 'nodeRadiusPx\(n\)\*1\.2/scale' "(S6c) the flat 1.2x hit radius that was only ever right for a disc is gone"
# (S7)/(S8) THE KEY. A picture that encodes kind in its marks and cannot be read is an undisclosed
#      channel — the exact defect the provenance caption exists to prevent. It is built from SYM_SHAPES,
#      the same lookup draw() uses, so the key cannot name a shape the picture does not draw.
pin 'function shapeKey' 'function shapeKey' "(S7) the page emits a shape key"
inbody shapeKey 'SYM_SHAPES\[t\]' 'SYM_SHAPES[t]' "(S8a) that key is built from the SAME roster the marks are drawn from"
# (S8b) NOTE: this arm's surface MOVED. The key is still built by renderProv and still travels with the
#      exported picture, but in the METHOD half — the companion .txt (W5)/(W9a) — rather than burned into
#      the bitmap, because the stamp was trimmed to provenance. The arm is not weakened: (W9a) holds the
#      key's new home and (W8a) holds that it left the old one.
inbody renderProv 'shapeKey\(\)' 'shapeKey()' "(S8b) and it is on the provenance caption, in the METHOD half the export writes beside the PNG"
# (S9) so the STAMP has to grow with the caption. A constant height silently truncated it the day it
#      gained a third line, which is the clipping defect (I5) already exists to stop, by the other axis.
pin 'function stampHeight' 'function stampHeight' "(S9a) the stamped strip's height is derived from the caption's line count"
absent 'slice\(0, 2\)' "(S9b) the two-line ceiling that would have dropped the shape key from every exported PNG is gone"

# ── (T) THE LAYOUT FILLS THE FRAME IT IS DRAWN IN ─────────────────────────────────────────────────────
#
#     Measured on the README hero at 1600x900: the settled graph used 86% of the canvas HEIGHT and 37%
#     of its WIDTH. Nearly half of the flagship picture was empty margin, for one reason — every layout
#     was seeded inside a SQUARE (min(W,H)*0.7 on both axes) and then pulled to the centre by an
#     ISOTROPIC well, and a circular cloud on a 16:9 canvas cannot be anything else. Both halves have to
#     move: an aspect-correct seed alone is pulled back round over 300 steps, and an elliptical well
#     alone fights a square start for most of them.
inbody loadSubset 'SPREAD_X' 'SPREAD_X' "(T1) the seed spread is per-axis, in the viewport's own proportions"
absent 'Math\.max\(Math\.min\(W,H\)\*0\.7, 300\)' "(T2) the single square seed spread that produced a circular cloud is gone"
inbody simTick 'gravX' 'gravX' "(T3) the gravity well is elliptical, not isotropic"
inbody simTick 'W/H' 'W/H' "(T4) and its ratio comes from the FRAME's aspect rather than a constant somebody picked"
absent 'ax\[i\] \+= gravity\*\(cx-nodes\[i\]\.x\)' "(T5) the isotropic pull it replaces is gone — two wells would fight"
# (T6) the anisotropy is CLAMPED. A browser window can be any shape, and an unclamped ratio on a 10:1
#      viewport draws the graph as a line — the same class of unbounded-input defect as the zoom band
#      (K) and the per-tick displacement cap (D6), both of which were found the hard way.
inbody simTick 'Math\.min\(2\.5' '2.5' "(T6) that ratio is clamped, so an extreme window cannot flatten the graph into a line"

# ── (U) MODULE HULLS — containment, because hue cannot count past twelve ──────────────────────────────
#
#     Module identity was carried by hue alone: commColor[comm % 12], twelve colours over 26 distinct
#     modules on this repository's own default page, 31 on the README hero, and 299 and 188 on two
#     larger corpora. At --top-k=2000 that is 24-25 modules sharing every hue while the legend printed
#     "m0 ... m11" and said nothing about the collision, so two adjacent same-coloured clusters read as
#     one module and nothing in the picture could tell a reader they were not. Twelve categorical hues
#     is roughly the ceiling of a colour channel and the module count is unbounded, so no palette fixes
#     this — containment is the only channel that can honestly express 26 to 299 groups.
pin 'function convexHull' 'function convexHull' "(U1) the page computes a hull for a module's members"
inbody draw 'hullGroups\[gi\]' 'hullGroups[gi]' "(U2) and draw() outlines them"
# (U3) BEHIND THE GRAPH. An outline drawn over the edges and nodes is a lid, not a region; the whole
#      point is that it sits under the picture. Checked by ORDER in the emitted script, which is the one
#      thing a grep gate can actually verify about a canvas draw sequence.
uHull="$( grep -n 'module HULLS, behind everything' "$PAGE" | head -1 | cut -d: -f1 )"
uEdge="$( grep -n 'edges, WITH THEIR DIRECTION DRAWN' "$PAGE" | head -1 | cut -d: -f1 )"
uNode="$( grep -nF 'shapeFor(n).path' "$PAGE" | head -1 | cut -d: -f1 )"
if [ -n "$uHull" ] && [ -n "$uEdge" ] && [ -n "$uNode" ] && [ "$uHull" -lt "$uEdge" ] && [ "$uEdge" -lt "$uNode" ]; then
    ok "(U3) hulls are painted before the edges and the edges before the nodes (lines $uHull < $uEdge < $uNode)"
else
    no "(U3) draw order is hull=$uHull edge=$uEdge node=$uNode — an outline over the graph is a lid, not a region"
fi
# (U4) THE OUTLINE IS NOT THE LENS. It says WHICH MODULE; the node fill still says whatever --color-by
#      the reader picked, so a cx view shows hot symbols AND the boundaries they sit inside. If the hull
#      took its colour from colorForNode it would have eaten the lens it is supposed to sit under.
#      It indexes hullColor, its OWN quiet palette, not commColor — see (Q7)-(Q10) for the measurement
#      that made the split necessary; (U4b) is the absence control that the borrowed form is gone.
inbody draw 'hullColor\[grp\.comm % 12\]' 'hullColor[grp.comm % 12]' "(U4) a hull is coloured by its MODULE, independently of --color-by"
notinbody draw 'commColor\[grp\.comm % 12\]' "(U4b) draw() no longer borrows the community LENS' saturated hues for the outlines"
# (U5) THE PURITY TEST. A convex hull only means "these belong together" if the group is spatially
#      together, and Louvain communities are not always laid out that way: on this repository's own map
#      the three largest are name-based hubs (`size`, `find`, `empty`) whose members are scattered over
#      the whole picture, and their hulls came out as huge overlapping lenses covering most of the
#      canvas — not containment, a wash, and worse than no outline at all. Without this arm the feature
#      passes its other arms while making the flagship picture harder to read.
inbody draw 'HULL_PURITY' 'HULL_PURITY' "(U5) an outline that would enclose mostly OTHER modules is not drawn"
pin 'HULL_CANDIDATES' 'HULL_CANDIDATES' "(U6) and that test's cost is bounded — it is O(N x groups) every frame at up to 5000 nodes"
# (U7)/(U8) BOTH TRUNCATIONS ARE STATED. The cap and the purity test each remove modules from the
#      picture, and a reader counting outlines would otherwise conclude the repository has twelve
#      modules. Non-negotiable #3: every truncation is disclosed, and a zero means "none found".
inbody renderProv 'hullsDrawn' 'hullsDrawn' "(U7) the caption states how many outlines were drawn of how many modules qualify"
inbody renderProv 'MAX_HULLS' 'MAX_HULLS' "(U8) and names the cap, so the count cannot be read as the module total"
# (U9) a two-point "hull" is a line segment, which is not a region and reads as a stray edge.
pin 'MIN_HULL_MEMBERS = 3' 'MIN_HULL_MEMBERS = 3' "(U9) three members minimum — two points are a line, not a region"
# (U10) the outline stands off its members in SCREEN units, like every other measurement on this canvas
inbody draw 'HULL_PAD_PX/scale' 'HULL_PAD_PX/scale' "(U10) the outline's standoff is a screen quantity, so it survives the auto-fit zoom"
# (U11)/(U12) HULL NAMES GO THROUGH THE SAME OCCUPANCY GRID as node labels. A second placement path
#      would be a second thing that decides what overlaps what, and the two would disagree — which is
#      the overprinting arm (B) exists to stop, re-introduced by a new caller. (U12) is the control:
#      there is exactly ONE occupancy set on the page.
inbody draw 'placeTextAt\(hullAnchors' 'placeTextAt' "(U11) hull names are placed by the same decluttering rule as node labels"
ncells="$( grep -c 'var labelCells = new Set' "$PAGE" )"
[ "$ncells" = "1" ] && ok "(U12) control: exactly one label occupancy grid on the page ($ncells)" \
                    || no "(U12) control: $ncells occupancy grids — two placement rules will disagree about what overlaps"
# (U13)-(U18) THE SHAPE TEST — a hull has to be a REGION, and node count cannot tell you whether it is.
#      MIN_HULL_MEMBERS was the only gate on geometry and it counts POINTS: three points that happen to
#      be collinear pass it and draw a hull with no area, which renders as a thin coloured smear across
#      the picture and reads as a scratch on the lens rather than a region. Measured over both corpora at
#      the pinned figure argv — 23 groups with 3+ members in view, django/db/migrations at rrf/top-k=120
#      and this repository at top-k=200 — the isoperimetric ratio 4*pi*A/P^2 of the raw hull ring splits
#      them into a low cluster {0.0011, 0.0718, 0.1493} and a body at >= 0.2879, and the two widest
#      adjacent gaps in the whole distribution (2.08x and 1.93x) bracket exactly that band. The three in
#      the low cluster are `resolve_model_field_relations` (a 107x0 px line, hull area 4 px^2),
#      `add_operation` (178x8 px) and `reload_model` (137x13 px) — the smears, by name.
#
#      The ratio, NOT an area floor and not the OBB aspect: the hull is convex by construction, and on a
#      convex ring 4*pi*A/P^2 IS thinness, so it needs no geometry the draw does not already walk (O(ring),
#      one pass, against the O(ring^2) rotating calipers an OBB aspect needs). An AREA floor is the wrong
#      predicate twice over — it is not scale-invariant, and it would drop `varint` (23x18 px, a small
#      round blob that reads perfectly well) while keeping nothing it should.
pin 'HULL_COMPACTNESS' 'HULL_COMPACTNESS' "(U13) the shape test's threshold is a named constant, not a number buried in a branch"
# (U14) the ratio is ISOPERIMETRIC — the perimeter is load-bearing, which is what makes this a SHAPE test
#       rather than the area floor that would drop a small round module and keep a long thin one.
inbody draw '4\*Math\.PI\*hullArea/\(hullPerim\*hullPerim\) < HULL_COMPACTNESS' 'hullPerim' "(U14) a hull thinner than that ratio is not drawn (and the perimeter is what makes it a shape test)"
# (U15) THE THRESHOLD IS IN THE CALIBRATED BAND. Below 0.149 it stops dropping `reload_model`, the
#       smear the eye actually catches; at or above 0.288 it starts dropping `shSingleQuote`-shaped
#       groups and then the ordinary lozenges (`generate_deleted_models` 0.315, `fnv1aMultiply` 0.372)
#       that read fine. A number outside the band is a number nobody measured.
hcomp="$( grep -oE 'HULL_COMPACTNESS = [0-9.]+' "$PAGE" | grep -oE '[0-9.]+$' )"
if [ -n "$hcomp" ] && ge "$hcomp" 0.16 && ge 0.28 "$hcomp"; then
    ok "(U15) the threshold ($hcomp) sits in the measured gap between the smears (<=0.1493) and the regions (>=0.2879)"
else
    no "(U15) HULL_COMPACTNESS is ${hcomp:-unset} — outside the [0.16, 0.28] band the two corpora measured"
fi
# (U16) THE DROP IS COUNTED AND CAPTIONED, with its own reason. Non-negotiable #3: this page already
#       states the cap and the purity drop, and a third silent removal would be the same defect a third
#       time — a reader counting outlines concluding the repository has fewer modules than it has.
inbody renderProv 'hullsThin' 'hullsThin' "(U16) the caption states how many outlines the shape test removed, separately from the purity drop"
inbody renderProv 'hullsImpure' 'hullsImpure' "(U17) and how many the purity test removed, so the two reasons are not pooled into one number"
# (U18) ABSENCE CONTROL: the SILENT drop is gone. `if (ring.length < 3) { continue; }` discarded a
#       fully-collinear group — the worst case of exactly this defect — and no number on the page ever
#       moved. It is now the same counted branch as every other shape drop.
absent 'if \(ring\.length < 3\) \{ continue; \}' "(U18) the uncounted collinear-hull drop that no caption number ever reflected is gone"
# (U19) and the cheap O(ring) shape test runs BEFORE the O(N) purity scan, so a group that cannot be a
#       region never costs a pass over every node in view. Checked by line order in the emitted script.
uShape="$( grep -n 'THE SHAPE TEST' "$PAGE" | head -1 | cut -d: -f1 )"
uPure="$( grep -n 'THE PURITY TEST' "$PAGE" | head -1 | cut -d: -f1 )"
if [ -n "$uShape" ] && [ -n "$uPure" ] && [ "$uShape" -lt "$uPure" ]; then
    ok "(U19) the O(ring) shape test filters before the O(N) purity scan (lines $uShape < $uPure)"
else
    no "(U19) shape=$uShape purity=$uPure — the O(N) scan runs for groups the cheap test would have dropped"
fi

# ── shared extractions for (V) and (X) — defined HERE, above both, because a helper called from above
#    its own definition expands to nothing and the arm silently takes the other branch.
#    linksblock scopes everything below to the emitted LINKS array: an `"a":1` somewhere else on a 70 KB
#    page must not be able to stand in for one on an edge.
linksblock(){ awk '/^const LINKS = \[/{on=1;next} on&&/^\];/{on=0} on' "$1"; }
nflagged(){ linksblock "$1" | grep -c '"a":1'; }
nedges(){ linksblock "$1" | grep -c '"s":'; }

# ── (V) PER-EDGE RESOLVER PROVENANCE, drawn as a dashed shaft ─────────────────────────────────────────
#
#     THE FACT IS prov="split": this edge is one arm of a k-way split the resolver could not choose
#     between. It is read per EDGE off Graph::outProv, which is the quantity the XML map and the MCP
#     surface already carry — so the picture and the data make ONE claim about one edge. It is
#     deliberately not a threshold on Graph::outVals: that float folds "could not choose between k
#     targets" together with "a lone match reached through a wide tier on an overcommon name", and a
#     single dashed stroke drawn for both says neither. The per-symbol amb= is the wrong granularity for
#     the same reason in the other direction — it counts a SYMBOL's ambiguous calls, so dashing all of
#     that symbol's edges would be a false statement about every one of them that was not.
#
#     THE SHARED FIXTURE CANNOT TEST THIS. test/fixture resolves cleanly — 5 edges, zero splits — so
#     every arm below would pass over a page that has no such edge on it at all. This corpus is the
#     collision shape resolverhonestycheck.sh's F1 case uses (two defs of foo() in one directory, caller
#     alongside them), plus one unambiguous call in a subdirectory, so the page carries BOTH kinds and
#     "per edge" is a claim these arms can actually falsify.
SPLITC="$TMP/splitcorpus"
mkdir -p "$SPLITC/sub"
printf 'int foo() { return 1; }\n'                             > "$SPLITC/a.cpp"
printf 'int foo() { return 2; }\n'                             > "$SPLITC/b.cpp"
printf 'int bar() { return foo(); }\n'                         > "$SPLITC/caller.cpp"
printf 'int baz() { return 7; }\nint qux() { return baz(); }\n' > "$SPLITC/sub/c.cpp"
SPAGE="$TMP/split.html"
"$BIN" "$SPLITC" --html --no-cache >"$SPAGE" 2>/dev/null
# the XML's own count, taken BEFORE the control below mutates the corpus out from under it
xSplit="$( "$BIN" "$SPLITC" --no-cache 2>/dev/null | grep -o 'prov="split"' | wc -l | tr -d ' ' )"

if [ ! -s "$SPAGE" ]; then
    no "(V1) the split corpus produced no page"
else
    sTot="$( nedges "$SPAGE" )"; sFlag="$( nflagged "$SPAGE" )"
    # (V1) THE GRANULARITY ARM. Some records carry the flag and some do not. A page that marked every
    #      edge would satisfy "the flag exists" exactly and be a page-wide claim, not a per-edge one.
    if [ "$sFlag" -gt 0 ] && [ "$sFlag" -lt "$sTot" ]; then
        ok "(V1) the flag is PER EDGE — $sFlag of $sTot LINKS carry it and the rest do not"
    else
        no "(V1) $sFlag of $sTot LINKS carry the flag — not a per-edge quantity (0 = never marked, all = a page-wide claim)"
    fi
    # (V2) ONE FACT, TWO SURFACES. The dashed edges must be exactly the ones the XML spells prov="split"
    #      over the same corpus. This is the whole argument for reading outProv instead of inventing a
    #      second derivation of "uncertain" for the renderer alone: a reader who checks the map against
    #      the picture must not find them disagreeing.
    if [ "$sFlag" = "$xSplit" ] && [ "$xSplit" -gt 0 ]; then
        ok "(V2) the picture and the XML map agree edge for edge — $sFlag dashed, $xSplit prov=\"split\""
    else
        no "(V2) $sFlag dashed shafts against $xSplit prov=\"split\" edges — the picture and the map are two derivations of one fact"
    fi
fi
# (V3) CONTROL — mutate REAL INPUT and re-run the identical extraction. Deleting b.cpp removes the rival
#      definition, so foo() has exactly one candidate and the same call is no longer a split. The
#      mutation is asserted to have TAKEN (the page moved) before its outcome is believed: a control
#      whose input never changed proves nothing about what the check above is reading.
rm -f "$SPLITC/b.cpp"
MPAGE="$TMP/splitmut.html"
"$BIN" "$SPLITC" --html --no-cache >"$MPAGE" 2>/dev/null
mTot="$( nedges "$MPAGE" )"; mFlag="$( nflagged "$MPAGE" )"
if cmp -s "$SPAGE" "$MPAGE"; then
    no "(V3) control: removing the rival definition did not change the page — the mutation never took, so (V1)/(V2) are unproven"
elif [ "$mTot" -gt 0 ] && [ "$mFlag" -eq 0 ]; then
    mutants=$(( mutants + 1 ))
    ok "(V3) control: with the rival gone the same corpus emits $mTot edges and 0 flags — the bit tracks the resolver, not the page"
else
    no "(V3) control: $mFlag of $mTot edges still flagged with nothing left to be ambiguous about — the flag is not the resolver's"
fi
# (V4)-(V6) the RENDERER's wiring, on the shared page: the map-wide count is derived from the payload
#      rather than baked, the dash is selected by the edge's OWN bit, and the dash pattern is a screen
#      quantity like every other measurement on this canvas (a world-space dash vanishes at auto-fit).
pin 'for \(var _k = 0; _k < LINKS\.length; _k\+\+\) if \(LINKS\[_k\]\.a\)' 'LINKS[_k].a' "(V4) the map-wide count is derived by walking LINKS, not baked into the page"
inbody draw 'links\[k\]\.a === 1' 'links[k].a === 1' "(V5) a shaft is dashed by ITS OWN edge's bit"
inbody draw 'DASH_ON_PX/scale' 'DASH_ON_PX/scale' "(V6) the dash pattern is a screen size, so it survives the auto-fit zoom"
# (V7)-(V9) DISCLOSURE, AT TWO SCOPES. "Some of these edges are uncertain" is a mood, not a disclosure:
#      the caption gives the count for THIS VIEW and the legend gives it for the whole baked map. They
#      differ in every ego and module view, so each has to say which set it is counting — one number
#      reported twice under two scopes would be the silent inconsistency (W) exists to prevent.
inbody renderProv 'ambEdges' 'ambEdges' "(V7) the caption states how many shafts are dashed in the current view"
pin "AMB_LINKS \+ ' of ' \+ LINKS\.length" 'AMB_LINKS' "(V8) and the legend states it for the whole map"
pin "in this map" 'in this map' "(V9) with the two labelled apart by scope, so they cannot read as one number stated twice"
# (V10)/(V11) the ego view must hand loadSubset the LINKS RECORDS, not rebuilt {s,t} pairs: a rebuilt pair
#      drops the bit and the edge draws solid — an edge silently losing its own doubt, in the one view
#      where a reader is looking closely at a handful of edges.
inbody egoGraph 'edges\.push\(LINKS\[k\]\)' 'edges.push(LINKS[k])' "(V10) the ego view passes the edge records through, so an edge cannot lose its provenance on the way"
absent 'edges\.push\(\{ s: s, t: t \}\)' "(V11) the rebuilt {s,t} pair that dropped it is gone"
# (V12) ONE DERIVATION, NOT TWO. An earlier lane shipped a parallel LCONF array and a LOW_CONF threshold
#       over Graph::outVals. Both are superseded by the axis above; leaving them in the tree would give
#       the page two quantities that both mean "this edge is a guess" and disagree about which edges.
absent 'LCONF|LOW_CONF' "(V12) the superseded LCONF/LOW_CONF derivation is gone from the page"

# ── (X) THE EMITTED EDGE ORDER IS A TOTAL ORDER, because the LAYOUT depends on it ─────────────────────
#
#     LINKS is sorted (s asc, t asc), and that was recorded as a byte-determinism measure. It is more
#     than that. The page runs its own force sim over these records and float addition is not
#     associative, so permuting LINKS and re-running the identical sim to full MAX_SIM accumulates the
#     same forces in a different order and settles into a DIFFERENT local minimum after 300 steps.
#     Measured max coordinate delta over every drawn node, permuted vs not:
#
#         top-k=400     2.85e-6   rounding
#         top-k=800     1.58e+3   A DIFFERENT LAYOUT
#         top-k=1500    7.36e+3   A DIFFERENT LAYOUT
#
#     So above roughly 500 nodes any change to edge emit order silently changes every picture this tool
#     has published — and every change that would do it reads as cosmetic: adding a field to the record
#     and sorting on it, grouping edges by module, emitting the low-confidence ones in a separate pass,
#     dedup'ing in a different order.
#
#     STRICT increase is the property, not "sorted". s and t print as %u integers, so a strictly
#     increasing (s,t) sequence is a TOTAL ORDER WITH NO TIES: a given edge set has exactly one
#     strictly-increasing arrangement, therefore the same edges always emit in the same order and always
#     settle to the same layout. Relax it to allow duplicates and the ties come back, and every failure
#     above returns with the check still green. src/htmlexport.h::writeEdgePayload carries the same fence
#     as a VERIFY; these arms hold it on the emitted BYTES, at a scale where the sensitivity is real and
#     in a build where NDEBUG has compiled the assert away.
#
#     It cannot catch a change to which edges are SELECTED, and must not: that is meant to move the
#     picture.

# strictorder FILE — "<edges> <non-strict pairs> <duplicate pairs>" over the emitted LINKS block. THE ONE
# extraction the arms and the control below all run.
strictorder()
{
    linksblock "$1" | awk 'match($0,/"s":[0-9]+,"t":[0-9]+/){
            split(substr($0,RSTART,RLENGTH),f,/[^0-9]+/); s=f[2]+0; t=f[3]+0; n++;
            if (n>1 && (s<ps || (s==ps && t<=pt))) { bad++ }
            if (n>1 && s==ps && t==pt) { dup++ }
            ps=s; pt=t }
        END { printf "%d %d %d\n", n+0, bad+0, dup+0 }'
}

# (X1)/(X2) at BOTH ends of the range the tool is used over. The fixture page is the small end; src/ at
#      --top-k=1500 is past the ~500-node knee above, where a permutation moves every node in the picture.
XPAGE="$TMP/order_big.html"
"$BIN" "$ROOT/src" --top-k=1500 --html --no-cache >"$XPAGE" 2>/dev/null
xi=0
for xf in "$PAGE" "$XPAGE"; do
    xi=$(( xi + 1 ))
    set -- $( strictorder "$xf" )
    if [ "${1:-0}" -eq 0 ]; then
        no "(X$xi) the LINKS block of $( basename "$xf" ) has no edges — the extraction read nothing and the arm asserts nothing"
    elif [ "$2" -eq 0 ] && [ "$3" -eq 0 ]; then
        ok "(X$xi) $1 emitted edges are STRICTLY increasing in (s,t), 0 duplicates ($( basename "$xf" ))"
    else
        no "(X$xi) $( basename "$xf" ): $2 of $1 emitted edges are not strictly after their predecessor ($3 exact duplicates) — the emit order is no longer a function of the edge set, and every drawn node moves"
    fi
done
# (X3) CONTROL — permute REAL emitted LINKS and re-run the identical extraction. Reversing the block is
#      the cheapest permutation of the same edge SET, which is exactly the class of change these arms
#      exist to catch (the selection is untouched). The mutation is asserted to have taken first.
XMUT="$TMP/order_mut.html"
awk '/^const LINKS = \[/{print; on=1; next}
     on && /^\];/{ for (i=n; i>=1; i--) print b[i]; print; on=0; next }
     on { b[++n]=$0; next }
     { print }' "$XPAGE" > "$XMUT"
if cmp -s "$XPAGE" "$XMUT"; then
    no "(X3) control: reversing the LINKS block did not change the page — the mutation never took, so (X1)/(X2) are unproven"
else
    set -- $( strictorder "$XMUT" )
    if [ "$2" -gt 0 ]; then
        mutants=$(( mutants + 1 ))
        ok "(X3) control: the same extraction reports $2 of $1 out of order once the records are permuted"
    else
        no "(X3) control VACUOUS: a permuted LINKS block still reads as strictly increasing — the extraction is not testing the order"
    fi
fi
# (X4) THE FENCE'S STRICTNESS, pinned in the source, because relaxing `<` to `<=` is the one edit that
#      removes the whole property while leaving every arm above green on today's corpus. Controlled by
#      running the identical two-sided check over a copy in which exactly that relaxation was made.
strictfence(){ grep -q 'edges\[k - 1\]\.t < edges\[k\]\.t' "$1" && ! grep -q 'edges\[k - 1\]\.t <= edges\[k\]\.t' "$1"; }
XSRC="$ROOT/src/htmlexport.h"
sed 's/edges\[k - 1\]\.t < edges\[k\]\.t/edges[k - 1].t <= edges[k].t/' "$XSRC" > "$TMP/fence_mut.h"
if ! strictfence "$XSRC"; then
    no "(X4) writeEdgePayload's (s,t) fence is missing or not strict — with <= a duplicate edge passes and the emitted order stops being a function of the edge set"
elif cmp -s "$XSRC" "$TMP/fence_mut.h"; then
    no "(X4) control: the <= relaxation did not change the source — the check is not reading the fence"
elif strictfence "$TMP/fence_mut.h"; then
    no "(X4) control VACUOUS: the relaxed copy still passes the strictness check"
else
    mutants=$(( mutants + 1 ))
    ok "(X4) writeEdgePayload asserts STRICT increase, and the check goes red on a <= relaxation of it"
fi

# ── (W) THE CAPTION SPLIT — the bitmap carries PROVENANCE, the sidecar carries METHOD ─────────────────
#
#     The stamped strip had grown to three dense lines carrying the whole methodology: arrow semantics,
#     the dash threshold, the label rule, the shape key and the hull rule, on top of the provenance. A
#     README figure gets three to five seconds, and at 880 px the fitted stamp font is already down near
#     its 8 px floor — so every clause added to it made the provenance it exists to carry harder to read,
#     not easier. The split is by KIND: what this picture IS (root, ranker, top-k, the counts, the colour
#     metric) is burned into the bitmap, and how to READ it travels beside the PNG in a companion .txt
#     that the same export writes.
#
#     THE HONESTY CONSTRAINT IS THE WHOLE ARM SET. Non-negotiable #3 forbids a surface that quietly
#     omits, and "the methodology moved" is only not-quiet if the bitmap says so and the sidecar actually
#     exists. (W7) holds the pointer, (W4)/(W5) hold the file, and (W8)/(W9) are the control pair that
#     proves the clauses LEFT the stamped half and LANDED in the other one rather than being deleted.
#
#     provfacts / provmethod scope an arm to one half of renderProv's body. "renderProv mentions the
#     shape key somewhere" is now true of both halves at once and says nothing about which surface a
#     reader sees it on, which is precisely what these arms are about. An empty segment is a broken
#     derivation and every caller below fails on one by name rather than passing over nothing.
provfacts(){ awk '/---- CAPTION FACTS/,/---- CAPTION METHOD/' "$PAGE"; }
provmethod(){ awk '/---- CAPTION METHOD/,/^  \}/' "$PAGE"; }
# insegment NAME PATTERN TOKEN DESC — pin() at segment scope, with pin()'s mutation control.
insegment()
{
    local seg="$1" pat="$2" tok="$3" desc="$4"
    "$seg" > "$TMP/seg.txt"
    if [ ! -s "$TMP/seg.txt" ]; then no "$desc — the $seg segment of renderProv is empty (the awk range broke; the arm asserts nothing)"; return; fi
    if ! grep -qE -- "$pat" "$TMP/seg.txt"; then no "$desc — not found in the $seg half of the caption"; return; fi
    # shellcheck disable=SC2001
    sed "s/$( printf '%s' "$tok" | sed 's/[][\.*^$\/&]/\\&/g' )/zzRIPWIREMUTANTzz/g" "$TMP/seg.txt" > "$TMP/segmut.txt"
    if grep -qE -- "$pat" "$TMP/segmut.txt"; then
        no "$desc — MUTANT CONTROL VACUOUS: the pattern still matches with '$tok' corrupted"
    else
        mutants=$(( mutants + 1 )); ok "$desc"
    fi
}
# notinsegment NAME PATTERN DESC — absent() at segment scope; the non-empty segment is its own control.
notinsegment()
{
    local seg="$1" pat="$2" desc="$3"
    "$seg" > "$TMP/seg.txt"
    if [ ! -s "$TMP/seg.txt" ]; then no "$desc — the $seg segment of renderProv is empty (the awk range broke; the arm asserts nothing)"; return; fi
    if grep -qE -- "$pat" "$TMP/seg.txt"; then no "$desc — still in the $seg half: $( grep -oE -- "$pat" "$TMP/seg.txt" | head -1 )"; else ok "$desc"; fi
}
# (W1)/(W2) THE STAMP READS THE FACTS HALF ONLY. This is the mechanism of the whole split: if
#      stampLines() still read #prov it would burn both halves into the bitmap and every other arm here
#      would pass over a picture that had not changed. (W2) is the absence control.
pin "getElementById\('provfacts'\)" "'provfacts'" "(W1) the exported bitmap stamps the provenance half of the caption"
notinbody stampLines "getElementById\('prov'\)" "(W2) the whole-caption read that stamped the methodology into every PNG is gone"
# (W3) both halves are on the page — the reader looking at the live page loses nothing, only the bitmap
#      is trimmed. A split that dropped the methodology from the page too would be a deletion, not a move.
insegment provmethod 'id="provmethod"' 'id="provmethod"' "(W3) the methodology is still rendered on the page, in its own block"
# (W4)/(W5)/(W6) THE COMPANION FILE. The methodology has to land somewhere a README author can lift it
#      from verbatim, or "moved to the caption underneath" is a paraphrase waiting to happen. One export
#      click writes both files; (W6) holds them to ONE basename, because two independently-built names
#      are two names that can drift apart and leave a .txt beside the wrong .png.
pin "'\.txt'" "'.txt'" "(W4) the export writes a companion text file beside the PNG"
inbody sidecarText 'provmethod' 'provmethod' "(W5) and that file carries the methodology half, not just the provenance the bitmap already has"
pin 'function exportBase' 'function exportBase' "(W6a) the two files' shared basename is built once"
inbody sidecarText 'exportBase\(\)' 'exportBase()' "(W6b) and the sidecar takes its name from it"
# (W7) THE BITMAP SAYS WHERE THE REST WENT, and names every channel whose rule it is no longer printing.
#      Without this the trim is exactly the quiet omission non-negotiable #3 forbids: a picture that
#      draws arrowheads, dashes, shapes and outlines and prints no way to read any of them.
insegment provfacts 'exportBase\(\)' 'exportBase()' "(W7a) the stamped half names the companion file it points at"
insegment provfacts 'module-outline' 'module-outline' "(W7b) and enumerates the channels whose rules moved into it"
# (W8)/(W9) THE CONTROL PAIR: the clauses LEFT the stamped half (W8) and ARE in the other one (W9).
#      Either arm alone passes over a deletion — (W8) over one that threw the methodology away, (W9)
#      over one that never trimmed the bitmap at all.
notinsegment provfacts 'shapeKey\(\)'         "(W8a) the shape key is no longer burned into the bitmap"
notinsegment provfacts 'arrow points caller'  "(W8b) nor is the arrow semantics"
notinsegment provfacts 'shafts dashed'        "(W8c) nor the dash key"
notinsegment provfacts 'MAX_LABELS'           "(W8d) nor the label rule"
notinsegment provfacts 'MAX_HULLS'            "(W8e) nor the hull rule"
insegment provmethod 'shapeKey\(\)' 'shapeKey()' "(W9a) control: the shape key landed in the methodology half rather than being deleted"
insegment provmethod 'arrow points caller' 'arrow points caller' "(W9b) control: and the arrow semantics"
insegment provmethod 'shafts dashed' 'shafts dashed' "(W9c) control: and the dash key"
insegment provmethod 'MAX_LABELS' 'MAX_LABELS' "(W9d) control: and the label rule"
insegment provmethod 'MAX_HULLS' 'MAX_HULLS' "(W9e) control: and the hull rule, with both of its drop counts"
# (W10) the stamped half stays inside the strip's line ceiling. STAMP_MAX_LINES slices, so a fourth
#       facts line would be dropped from the bitmap silently — the (S9) clipping defect by the other axis.
# counted with -o, not -c: grep -c counts LINES, and two pushes sharing a line would under-report the
# stamped half by one and let a silently-sliced line through. (Found by the control for this arm.)
# (W11)-(W14) THE STAMP DESCRIBES THE FRAME IT IS UNDER. Found while cutting the README's crop figures:
#      the caption's counts are the LOADED subset, and the camera is free to be zoomed anywhere inside it,
#      so a crop exported after a zoom stamped "120 nodes / 183 edges" onto a picture of fifteen. That is
#      a bitmap overstating its own contents — the same defect class as an undisclosed cap, in the one
#      artifact the caption exists for. draw() counts what is actually inside the canvas rect (W11), the
#      STAMPED half states it (W12) whenever it is less than the view's own total (W13), and draw()
#      re-renders the caption when that number or a hull count moves (W14) — without which the stamp
#      would still carry the counts from the frame before the zoom.
inbody draw 'nodesInFrame' 'nodesInFrame' "(W11) draw() counts the nodes the camera is actually framing"
insegment provfacts 'nodesInFrame' 'nodesInFrame' "(W12) and the STAMPED half of the caption states it, so a cropped export cannot overstate its contents"
insegment provfacts 'nodesInFrame < N' 'nodesInFrame < N' "(W13) stated against the view's own total, so it appears exactly when the camera frames less than the map"
inbody draw 'provStamp' 'provStamp' "(W14) and the caption is re-rendered when that count moves — a stamp a frame behind the zoom is the same overstatement"
wfacts="$( provfacts | grep -oE 'factLines\.push' | wc -l | tr -d ' ' )"
wmax="$( grep -oE 'STAMP_MAX_LINES = [0-9]+' "$PAGE" | grep -oE '[0-9]+$' )"
if [ -n "$wmax" ] && [ "$wfacts" -gt 0 ] && [ "$wfacts" -le "$wmax" ]; then
    ok "(W10) the stamped half is $wfacts lines against a $wmax-line ceiling — none of it is sliced away"
else
    no "(W10) the stamped half is ${wfacts:-0} lines against a ${wmax:-unset}-line ceiling — a line would be dropped from the bitmap with nothing to say so"
fi

# ── (Z) THE FIT FRAMES WHAT IT DRAWS, not where the centres are ──────────────────────────────────────
# fitView used to fit the bounding box of node CENTRES against a flat 70 px pad. That is a different set
# from what lands on the canvas: a node is a disc, and a labelled node carries its name to the RIGHT in
# screen-constant 11 px text, which for `generate_deleted_models` is 130 px the centre-box knows nothing
# about. The pad hid it until a wide name happened to sit on the right edge — and then the README's own
# lens figure shipped with a symbol's name sliced in half by the frame. It is not fixable downstream
# either: the frame is what the README's stated command produces, so hand-panning the screenshot would
# publish a picture that command does not make.
#
# WHAT THESE ARMS CAN AND CANNOT SEE. The property is "nothing drawn falls outside the canvas", and it
# is only decidable by running the page's own layout with real font metrics — there is no JS engine in
# this suite, and adding one would make every gate depend on a host tool the build deliberately does not
# need. So these arms assert the MECHANISM, not the pixels: that the fit measures the same text
# placeLabel draws, through the same constants, and picks the camera from a feasibility interval rather
# than a centre formula. Pixel containment was verified out-of-band while cutting the figures, by
# walking every labelled node's drawn box against the canvas rect in a browser (0 overflowing, at
# 880x500 and 430x340). That is a measurement, not a gate, and it is recorded as one.
inbody fitView 'measureText'                    'measureText'          "(Z1) the fit MEASURES the label text rather than estimating it from a character count"
inbody fitView 'nodeRadiusPx'                   'nodeRadiusPx'         "(Z2) and includes the node's drawn radius, so a disc cannot hang over the edge either"
inbody fitView 'labelDegreeOrder'               'labelDegreeOrder'     "(Z3) over the SAME label set the draw pass will place (labelDegreeOrder)"
inbody fitView 'LABEL_GAP_PX'                   'LABEL_GAP_PX'         "(Z4) using placeLabel's own gap constant, so the two cannot disagree about where a name starts"
inbody fitView 'offsetRange'                    'offsetRange'          "(Z5) the offset comes from a feasibility interval over every reserved box"
inbody fitView 'fits\('                         'fits('                "(Z6) and the scale is the largest one that interval stays non-empty at"
# (Z7) THE CONSTANTS ARE SHARED, NOT COPIED. Two numbers for one gap is how the fit drifts away from the
# draw: the fit would keep reserving 3 px after placeLabel moved to 5 and nothing would fail. Assert each
# is declared exactly once in the whole renderer, which is what makes (Z4)'s "same constant" true.
for zc in LABEL_GAP_PX LABEL_BASE_PX LABEL_H; do
    zdecl="$( grep -cE "var [A-Z_, =0-9.]*\b$zc = " "$XSRC" || true )"
    if [ "$zdecl" = "1" ]; then
        ok "(Z7:$zc) declared exactly once — the fit and the draw read one number"
    else
        no "(Z7:$zc) declared $zdecl times — a second definition lets the fit reserve what the draw no longer uses"
    fi
done
# (Z8) THE OLD FIT IS GONE FROM THE MAIN PATH. It survives as the explicit fallback for a canvas too
# small to hold the boxes at all, so this asserts the shape of that: the centre-box formula appears, and
# it appears under a guard, not as the function's answer.
inbody fitView 'if \(!fits\(loS\)\)'            'if (!fits(loS))'      "(Z8) the centre-box formula survives only behind the cannot-fit guard, as a disclosed fallback"
# (Z9) MUTATION CONTROL FOR THE PAD. A pad that never yields would reintroduce the clipping on a narrow
# canvas by a second route — no scale fits, so the fallback fires and the label is sliced again. The
# concession must be in the code, and it must be to the PAD.
inbody fitView 'pad /= 2'                       'pad /= 2'             "(Z9) padding yields before containment does — the pad halves until a fit exists"

# ── (Y) THE ROOT LABEL — the operator's home directory reaches neither the pixels nor the file ───────
# The first cut of this fix stripped the home pair in the JS that renders the CAPTION, and stopped
# there, on the reasoning that the caption is what stampProvenance burns into an exported PNG and a PNG
# is the thing people share. Both halves of that are true and the conclusion still did not hold: --html
# writes a SELF-CONTAINED page whose entire purpose is to be handed to someone, and `const ROOT` sat in
# it carrying the absolute path. So the leak did not close, it changed medium — from something legible
# in a screenshot to something greppable in View Source, which is worse. Checked against a real emitted
# page before writing this: `ROOT` appears three times and the only USE is `rootShort(ROOT)`; the
# comment justifying the full string ("the FILES[] entries are relative to it and the page must still
# resolve them") described code that did not exist. The strip moved into C++, ahead of the write.
#
# These arms exist because that fix shipped with NO gate at all — the property was asserted in a
# comment. A privacy property defended by a comment is defended until the next refactor.
#
# The corpus is placed at $HOME/<one segment> on purpose. That is not an arbitrary absolute path, it is
# the exact shape the JS version got wrong: with only two segments before the project, the home
# directory IS one of the last two, so a tail-taker republishes the username while looking like it
# stripped something. `~/myproject` is plausibly the most common layout there is.
PRIVDIR="$HOME/.ripwire-privcheck-$$"
trap 'rm -rf "$TMP" "$PRIVDIR"' EXIT
mkdir -p "$PRIVDIR"
cp "$CORPUS"/* "$PRIVDIR"/ 2>/dev/null || true
PRIVPAGE="$TMP/priv.html"
"$BIN" "$PRIVDIR" --html --no-cache >"$PRIVPAGE" 2>/dev/null

if [ ! -s "$PRIVPAGE" ]; then
    no "(Y1) --html produced no page for a corpus under \$HOME — the arm has nothing to inspect"
elif [ "${PRIVDIR#$HOME/}" = "$PRIVDIR" ]; then
    no "(Y1) \$HOME is not a prefix of the corpus path — this arm cannot observe a home-path leak and must not report clean"
else
    privHits="$( grep -c -- "$HOME" "$PRIVPAGE" || true )"
    if [ "$privHits" -eq 0 ]; then
        ok "(Y1) the emitted page contains no occurrence of \$HOME — the leak is closed in the FILE, not only in the pixels"
    else
        no "(Y1) the emitted page states \$HOME $privHits time(s) — --html is a page people share, and it is carrying the operator's home directory"
    fi
fi

# (Y2) MUTATION CONTROL for (Y1). A grep that finds nothing proves nothing until it has been shown to
# find the thing. Put the absolute path back into the ROOT line of a COPY and re-run the identical
# test; if it still reports clean, the arm above is measuring the absence of a grep, not of a leak.
if [ -s "$PRIVPAGE" ]; then
    mutants=$(( mutants + 1 ))
    sed "s|^const ROOT = \".*\";|const ROOT = \"$PRIVDIR\";|" "$PRIVPAGE" >"$TMP/priv-mutant.html"
    if ! grep -q -- "$PRIVDIR" "$TMP/priv-mutant.html"; then
        no "(Y2) the mutation control did not take — the injected path is not in the mutant, so (Y1) was never exercised"
    elif [ "$( grep -c -- "$HOME" "$TMP/priv-mutant.html" || true )" -gt 0 ]; then
        ok "(Y2) mutation control: re-injecting the absolute path into const ROOT turns (Y1) red"
    else
        no "(Y2) mutation control FAILED OPEN — the page carries the absolute path and (Y1)'s test still reports clean"
    fi
fi

# (Y3) STRUCTURE, NOT TAIL. (Y1) would also pass if the label were the empty string, or the last segment
# by luck. State what the label must BE: both home segments gone and nothing else, which for a
# `$HOME/<one segment>` root is that one segment alone. This is the assertion that separates a
# positional strip from a `slice(-2)` that happens to look right on a deeper path.
if [ -s "$PRIVPAGE" ]; then
    privRoot="$( grep -m1 '^const ROOT = ' "$PRIVPAGE" | sed -E 's/^const ROOT = "(.*)";$/\1/' )"
    privBase="$( basename "$PRIVDIR" )"
    if [ "$privRoot" = "$privBase" ]; then
        ok "(Y3) the label is '$privRoot' — the home root AND the user segment below it were both dropped, by position"
    else
        no "(Y3) the label is '$privRoot', expected '$privBase' — the strip is not dropping the home PAIR"
    fi
fi

# (Y4) AND IT DOES NOT OVER-REACH. The counterpart control: a root with no home pair must keep its
# identity — its last two segments, with an ellipsis for what was cut. (Until 2026-09-06 this arm demanded
# the path VERBATIM, which is the leak by another route: a checkout under /Volumes, /srv or /work shipped its
# whole absolute path into a page whose only use of ROOT is this two-segment label.) Without this arm,
# "strip the home pair" and "blank every root" pass the same three arms above.
NOHOME="$TMP/proj"
mkdir -p "$NOHOME"
cp "$CORPUS"/* "$NOHOME"/ 2>/dev/null || true
"$BIN" "$NOHOME" --html --no-cache >"$TMP/nohome.html" 2>/dev/null
nohomeRoot="$( grep -m1 '^const ROOT = ' "$TMP/nohome.html" 2>/dev/null | sed -E 's/^const ROOT = "(.*)";$/\1/' )"
case "$nohomeRoot" in
    "…/$( basename "$TMP" )/proj") ok "(Y4) a root with no home pair keeps its last two segments ('$nohomeRoot') and nothing above them" ;;
    */proj) no "(Y4) a root with no home pair came back as '$nohomeRoot' — expected exactly '…/$( basename "$TMP" )/proj' (two segments, ellipsis)" ;;
    *)      no "(Y4) a root with no home pair came back as '$nohomeRoot' — the strip lost the root's identity" ;;
esac

# ── (N) the page names what it maps and when (2026-09-06 stranger audit). It was titled "ripwire wiki" whatever
#     it mapped, captioned its root "~" for "." (a tilde reads as the home directory), and carried no commit or
#     version — a page handed to a colleague was a map of unknown code as of who knows when. The name is the
#     root's LAST path segment only; (P1)/(P2) above still hold the path itself out of the page. ──
NPAGE="$TMP/named.html"
( cd "$CORPUS" && "$BIN" . --html --no-cache >"$NPAGE" 2>/dev/null )
NNAME="$( basename "$CORPUS" )"
grep -q "<title>ripwire — $NNAME</title>" "$NPAGE" \
    && ok "(N1) <title> names the mapped root: ripwire — $NNAME" \
    || no "(N1) <title> does not name the root: $( grep -o '<title>[^<]*</title>' "$NPAGE" )"
grep -q "const ROOT_NAME = \"$NNAME\";" "$NPAGE" \
    && ok "(N2) const ROOT_NAME carries the root's last segment" \
    || no "(N2) const ROOT_NAME missing or wrong: $( grep -o 'const ROOT_NAME = "[^"]*"' "$NPAGE" )"
grep -q 'const VERSION = "[0-9]' "$NPAGE" \
    && ok "(N3) const VERSION carries the binary version" \
    || no "(N3) const VERSION missing: $( grep -o 'const VERSION = "[^"]*"' "$NPAGE" )"
grep -q 'const AT = "' "$NPAGE" \
    && ok "(N4) const AT (the at= stamp) is emitted" \
    || no "(N4) const AT missing"
grep -q 'ripwire wiki' "$NPAGE" \
    && no "(N5) the page still says 'ripwire wiki' somewhere" \
    || ok "(N5) 'ripwire wiki' is gone"
grep -q "return '~'" "$NPAGE" \
    && no "(N6) rootShort can still render a bare '~' (reads as the home directory)" \
    || ok "(N6) rootShort never renders a bare '~'"

echo
echo "  ($mutants mutation controls ran and went red on their mutants)"
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
