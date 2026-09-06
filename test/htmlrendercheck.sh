#!/usr/bin/env bash
# htmlrendercheck.sh — gate for the --html RENDERER: what the picture is, and what the page says
# about itself.
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
#   (Q) RAMP    the cx/churn ramp MEASURED, not pinned — luminance monotonicity, contrast against the
#               canvas ground, and a Brettel/Viénot CVD simulation re-derived from the emitted stops
#   (R) EDGES   the call graph draws its DIRECTION — an arrowhead, and an adjacency that keeps callers
#               and callees in separate lists instead of symmetrising them
#   (S) SHAPE   symbol KIND on the only nominal-only channel, from ONE table indexed by SymKind, with
#               the key on the caption the PNG export stamps
#   (T) LAYOUT  seeded and pulled in the VIEWPORT'S proportions, so a 16:9 frame is not half empty
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
pin 'measureText\(n\.label\)' 'measureText(n.label)' "(B5) the reserved box is the measured text width"
# (B6) the grid stops labels colliding with each OTHER and says nothing about what is UNDER them. In a
#      dense view a name lands on a node disc, and #d6d9de over bright teal is the same lost label by
#      another route. Every label is stroked in the background colour before it is filled.
pin 'LABEL_HALO_PX' 'LABEL_HALO_PX' "(B6) labels carry a dark halo so they stay legible over a node"
pin 'strokeText\(n\.label' 'strokeText' "(B7) that halo is actually stroked behind the glyphs"
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
inbody placeLabel 'LABEL_CULL_PX' 'LABEL_CULL_PX' "(B12) an off-canvas label anchor is culled, so the occupancy walk always terminates"

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
rampmetrics()   # rampmetrics FILE → "mono minContrast minAdjNormal minAdjProtan minAdjDeutan minAdjTritan"
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
print(" ".join(out))
PY
}
# ge A B — A >= B in floating point, without depending on bc being installed
ge(){ awk -v a="$1" -v b="$2" 'BEGIN{ exit !(a+0 >= b+0) }'; }
sed "s/var rampColor = \[[^]]*\]/var rampColor = ['#4fc3f7','#26c6da','#ffd54f','#ff9800','#e65100']/" "$PAGE" > "$TMP/rampmutant.html"
read -r qMono qCon qNorm qPro qDeu qTri <<<"$( rampmetrics "$PAGE" )"
read -r mMono mCon mNorm mPro mDeu mTri <<<"$( rampmetrics "$TMP/rampmutant.html" )"
if [ "$mMono" = "no" ] && [ -n "$mDeu" ] && ! ge "$mDeu" 40; then
    mutants=$(( mutants + 1 ))
    ok "(Q1) MUTANT CONTROL: the derivation reproduces the OLD ramp's defects over a page carrying it (mono=$mMono, deutan min-adj=$mDeu) — it is measuring the ramp"
else
    no "(Q1) MUTANT CONTROL VACUOUS: over the OLD ramp the derivation reports mono=$mMono deutan=$mDeu, so it is not measuring what it claims"
fi
[ "$qMono" = "yes" ] && ok "(Q2) the ramp is MONOTONE in relative luminance — an ordinal scale greyscale still orders" \
                     || no "(Q2) the ramp is not monotone in luminance (mono=$qMono) — in greyscale its buckets arrive permuted"
if [ -n "$qCon" ] && ge "$qCon" 4.5; then
    ok "(Q3) every stop clears 4.5:1 against the #111 canvas (worst $qCon:1) — monotone was not bought by sinking the low end into the ground"
else
    no "(Q3) a ramp stop falls below 4.5:1 against the canvas ground (worst $qCon:1)"
fi
qcvd=ok
for d in "$qPro" "$qDeu" "$qTri"; do
    { [ -n "$d" ] && ge "$d" 45; } || qcvd=bad
done
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
inbody renderProv 'arrow points caller' 'arrow points caller' "(R11) the provenance caption states that an arrow points caller → callee"

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
inbody renderProv 'shapeKey\(\)' 'shapeKey()' "(S8b) and it is on the provenance caption, which is what the PNG export stamps"
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

echo
echo "  ($mutants mutation controls ran and went red on their mutants)"
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
