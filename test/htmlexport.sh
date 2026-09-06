#!/usr/bin/env bash
# htmlexport.sh — gate for P2-A: --html self-contained graph export.
#
# Usage:
#   test/htmlexport.sh                          # uses build/ripwire on test/fixture
#   RIPWIRE_BIN=asan/ripwire test/htmlexport.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "htmlexport: BIN=$BIN  CORPUS=$CORPUS"

# 1) --html output is a well-formed HTML document containing the required markers
"$BIN" "$CORPUS" --html --no-cache >"$TMP/out.html" 2>/dev/null
grep -q "<!DOCTYPE html" "$TMP/out.html" && ok "output starts with <!DOCTYPE html>" || no "output missing <!DOCTYPE html>"
grep -q "<html"          "$TMP/out.html" && ok "output contains <html>"            || no "output missing <html>"
grep -q "const NODES"    "$TMP/out.html" && ok "output contains const NODES"       || no "output missing const NODES"
grep -q "<canvas"        "$TMP/out.html" && ok "output contains <canvas>"          || no "output missing <canvas>"

# 2) at least 3 node entries in the NODES array (fixture has several symbols)
count="$( grep -c '"id"' "$TMP/out.html" 2>/dev/null || echo 0 )"
[ "$count" -ge 3 ] && ok "NODES array has >= 3 entries (found $count)" || no "NODES array has < 3 entries (found $count)"

# 3) determinism: two runs produce byte-identical output
"$BIN" "$CORPUS" --html --no-cache >"$TMP/a.html" 2>/dev/null
"$BIN" "$CORPUS" --html --no-cache >"$TMP/b.html" 2>/dev/null
diff -q "$TMP/a.html" "$TMP/b.html" >/dev/null && ok "determinism: byte-identical run-to-run" || no "determinism: non-identical output"

# 4) --html=FILE: writes to the file, stdout is empty
"$BIN" "$CORPUS" --html="$TMP/g.html" --no-cache >"$TMP/stdout.txt" 2>/dev/null
[ -s "$TMP/g.html" ]        && ok "--html=FILE: file is non-empty"    || no "--html=FILE: file is empty or missing"
[ ! -s "$TMP/stdout.txt" ]  && ok "--html=FILE: stdout is empty"      || no "--html=FILE: stdout is not empty"
grep -q "const NODES" "$TMP/g.html" && ok "--html=FILE: file contains const NODES" || no "--html=FILE: file missing const NODES"

# 5) no external script src= or link href= (self-contained, no CDN)
if grep -qE '<script[^>]+src=' "$TMP/out.html" 2>/dev/null; then
    no "self-contained: external <script src= found"
else
    ok "self-contained: no external <script src=>"
fi
if grep -qE '<link[^>]+href=' "$TMP/out.html" 2>/dev/null; then
    no "self-contained: external <link href= found"
else
    ok "self-contained: no external <link href=>"
fi

# 6) zero external http(s):// resource references anywhere in the document (CSP-safe, no CDN) —
#    the only http(s) text allowed is inside an xmlns attribute (none expected in HTML, but the check
#    is written generically so a future xmlns doesn't false-positive).
if grep -oE 'https?://[^"'"'"' <>]+' "$TMP/out.html" 2>/dev/null | grep -vq 'xmlns'; then
    no "self-contained: found http(s):// reference outside xmlns"
else
    ok "self-contained: no http(s):// resource references beyond xmlns"
fi

# 7) wiki views: the overview module-card marker, module/node hash routes, and MODULES payload exist
grep -q 'data-module-card'  "$TMP/out.html" && ok "wiki: overview module-card marker present"       || no "wiki: overview module-card marker missing"
grep -q 'const MODULES'     "$TMP/out.html" && ok "wiki: output contains const MODULES"              || no "wiki: output missing const MODULES"
grep -q 'const FILES'       "$TMP/out.html" && ok "wiki: output contains const FILES"                || no "wiki: output missing const FILES"
grep -q "#module/"          "$TMP/out.html" && ok "wiki: module-view hash route (#module/) present"  || no "wiki: module-view hash route missing"
grep -q "#node/"            "$TMP/out.html" && ok "wiki: node-view hash route (#node/) present"      || no "wiki: node-view hash route missing"
grep -q "egoGraph"          "$TMP/out.html" && ok "wiki: ego-graph BFS function present"             || no "wiki: ego-graph BFS function missing"
grep -q "id=\"crumb\""      "$TMP/out.html" && ok "wiki: breadcrumb trail element present"           || no "wiki: breadcrumb trail element missing"

# 8) MODULES array actually has at least one entry on the fixture corpus (it has several files/dirs,
#    so Louvain should find at least one ≥2-member community)
mod_count="$( grep -c '"symCount"' "$TMP/out.html" 2>/dev/null || echo 0 )"
[ "$mod_count" -ge 1 ] && ok "wiki: MODULES array has >= 1 entry (found $mod_count)" || no "wiki: MODULES array is empty (found $mod_count)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 9) EDGE CONFIDENCE IS RENDERED, not discarded (Round C, lane B).
#
# ripwire resolves every call edge and records, per edge, whether it had to guess — the same fact the XML
# map discloses as prov="split" on a <c> child and aggregates into amb=/ambiguous=. Before this arm the
# HTML export threw that away at render time: LINKS entries were plain {s,t} pairs and every edge in the
# picture was drawn identically, so the one view a human actually looks at was the one view that could not
# say which edges were guesses. This arm pins that the fact reaches the payload, reaches the paint, and
# reaches a legend a reader can find without reading the source.
#
# PRESENCE GUARD FIRST. test/fixture resolves cleanly (ambiguous=0), so an arm run against it would assert
# over an empty set and pass for the wrong reason. The guard builds a corpus with a KNOWN two-way split and
# refuses to continue unless the corpus really has one.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
AMB="$TMP/ambcorpus"; mkdir -p "$AMB"
printf 'int foo() { return 1; }\n'     > "$AMB/a.cpp"
printf 'int foo() { return 2; }\n'     > "$AMB/b.cpp"
printf 'int bar() { return foo(); }\n' > "$AMB/caller.cpp"
amb_n="$( "$BIN" "$AMB" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
amb_n="${amb_n:-0}"
if [ "$amb_n" -ge 1 ]; then
    ok "edge-confidence presence guard: the probe corpus really has ambiguous=$amb_n (arm is observable)"

    "$BIN" "$AMB" --html --no-cache >"$TMP/amb.html" 2>/dev/null
    # (a) the per-edge flag reaches the LINKS payload — omitted on confident edges, so grep for a marked one
    grep -qE '\{"s":[0-9]+,"t":[0-9]+,"a":1\}' "$TMP/amb.html" \
      && ok "edge confidence: LINKS carries the per-edge low-confidence flag on a split edge" \
      || no "edge confidence: LINKS entries are still plain {s,t} — amb= is computed and discarded at render time"
    # (b) the flag reaches the PAINT: a distinct stroke, not just a datum nobody draws
    grep -q 'setLineDash' "$TMP/amb.html" \
      && ok "edge confidence: the renderer strokes low-confidence edges distinctly (setLineDash)" \
      || no "edge confidence: no distinct stroke — the flag is in the payload but invisible in the picture"
    # (c) the meaning reaches a LEGEND a reader can find (the honesty vocabulary is in the OUTPUT, docs/METHODOLOGY §6)
    # anchored on a phrase that appears ONLY in the rendered legend string — 'could not choose' also occurs
    # in the embedded script's own comments, so grepping for it would pass with the legend clause deleted.
    grep -q 'read the source before trusting one' "$TMP/amb.html" \
      && ok "edge confidence: the view carries a legend defining the low-confidence stroke" \
      || no "edge confidence: the stroke is rendered with nothing on screen defining it"
    # (d) OMIT AT CONFIDENT — test/fixture resolves cleanly, so no edge there may carry the flag.
    grep -q '"a":1' "$TMP/out.html" \
      && no "edge confidence: a cleanly-resolved corpus wrongly carries the low-confidence flag (omit-at-confident broken)" \
      || ok "edge confidence: a cleanly-resolved corpus carries no flag at all (omit-at-confident holds)"
    # (e) determinism of the marked view
    "$BIN" "$AMB" --html --no-cache >"$TMP/amb2.html" 2>/dev/null
    diff -q "$TMP/amb.html" "$TMP/amb2.html" >/dev/null \
      && ok "edge confidence: marked view is byte-identical run-to-run" \
      || no "edge confidence: marked view is not deterministic"
else
    no "edge-confidence presence guard FAILED: the probe corpus reports ambiguous=$amb_n — this arm cannot observe what it asserts"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
