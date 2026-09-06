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

echo
echo "  ($mutants mutation controls ran and went red on their mutants)"
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
