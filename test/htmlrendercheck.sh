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
#   (D) SIM     settled before first paint, under a wall-clock budget that degrades to progressive
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

# ── (C) node radius by in-view degree ────────────────────────────────────────────────────────────────
pin 'Math\.sqrt\(n\.deg' 'n.deg' "(C1) nodeRadius is driven by in-view degree"
absent '4 \+ 60\*Math\.sqrt\(n\.rank\)' "(C2) the old rank-only radius (mean 5.10 px on a 1-111 degree span) is gone"

# ── (D) settle before first paint, under a wall-clock budget ─────────────────────────────────────────
pin 'SETTLE_BUDGET_MS' 'SETTLE_BUDGET_MS' "(D1) the pre-paint settle carries a wall-clock budget"
pin 'function settle'  'function settle'  "(D2) a named settle() runs the sim before the first draw"
pin 'settleTimedOut'   'settleTimedOut'   "(D3) exceeding the budget degrades to progressive draw, disclosed by a flag"

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

echo
echo "  ($mutants mutation controls ran and went red on their mutants)"
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
